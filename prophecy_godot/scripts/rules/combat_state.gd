class_name CombatState
extends RefCounted
## 첫 전투 규칙(순수 시뮬레이션). 화면·입력 장치·저장소를 모르며, 고정 단계 step(input, dt)로만 진행한다.
## 입력 = {mx, my, dodge_press, dodge_held, special} (게임 행동). dodge_press = 이 단계에서 새로 누름(1회성), dodge_held = 지금 누르고 있음(상태).
## 사람 입력과 봇 입력이 같은 함수를 쓴다. 회피 규칙은 docs/RULES.md §회피.
## 이식 원본: prophecy_action_prototype/src/combat.js·weapons.js·skills.js (v0.8.0, ee10fc7). 차이는 docs/PORT_NOTES.md에 적는다.

var cfg: Dictionary
var rng: PRng
var seed_value: int
var t: float = 0.0
var step_n: int = 0
var status: String = "running" # running | won | lost
var player: Dictionary
var enemies: Array = []
var pending: Array = []
var waves: Array = []
var wave_index: int = -1
var wave_timer: float = 0.4
var spawned_all: bool = false
var field: Dictionary = {}
var obstacles: Array = []
var arena_w: float
var arena_h: float
var effects: Array = []   # 표시용 이벤트(화면이 읽기만 한다): {kind, x, y, ttl, t, ...}
var events: Array = []    # 소리·통계용 이벤트 이름
var stats: Dictionary = { "kills": 0, "damage_taken": 0.0, "attacks": 0, "hits": 0, "dodges": 0, "special_uses": 0, "perfect_dodges": 0, "elapsed": 0.0, "dodge_dists": [] }
var metrics: Dictionary = { "dmg": {}, "taken": {}, "enemies": {} } # 피해 출처별 유효 피해(과잉 제외), 받은 피해 원인별
var settled: bool = false
var _next_id: int = 1

func _init(config: Dictionary, seed_v: int = 1) -> void:
	cfg = config
	seed_value = seed_v
	rng = PRng.new(seed_v)
	arena_w = float(cfg.arena.w)
	arena_h = float(cfg.arena.h)
	for o in cfg.obstacles:
		obstacles.append({ "id": o.id, "type": o.type, "x": float(o.x), "y": float(o.y), "r": float(o.r) })
	waves = cfg.waves.duplicate(true)
	wave_timer = float(cfg.constants.first_wave_timer)
	var P: Dictionary = cfg.player
	player = {
		"x": float(P.start.x), "y": float(P.start.y), "r": float(P.r), "hp": float(P.hp), "hp_max": float(P.hp),
		"face": 0.0, "moving": false,
		"dodge_active": false, "dodge_t": 0.0, "dodge_dx": 0.0, "dodge_dy": 0.0, "dodge_cd": 0.0,
		"dodge_dist": 0.0, "dodge_released": false, "dodge_end": "",
		"hit_prot": 0.0, "attack_timer": float(cfg.weapon.first_attack_delay), "swing_t": 9.0, "swing_angle": 0.0,
		"special_cd": 0.0, "dead": false, "flash": 0.0, "hurt_t": 9.0,
	}

# ---------- 도우미 ----------
func _fx(e: Dictionary) -> void:
	e["t"] = 0.0
	effects.append(e)

func _ev(name: String) -> void:
	events.append(name)

func alive_enemies() -> Array:
	var out := []
	for e in enemies:
		if not e.dead:
			out.append(e)
	return out

func time_factor(ox: float, oy: float, orad: float) -> float:
	if not field.is_empty() and PGeom.dist(field.x, field.y, ox, oy) <= field.r + orad:
		return float(cfg.player.slowfield.slow)
	return 1.0

func in_field(ox: float, oy: float, orad: float) -> bool:
	return not field.is_empty() and PGeom.dist(field.x, field.y, ox, oy) <= field.r + orad

func los_blocked(ax: float, ay: float, bx: float, by: float) -> bool:
	for ob in obstacles:
		if PGeom.seg_circle(ax, ay, bx, by, ob.x, ob.y, ob.r):
			return true
	return false

func valid_pos(x: float, y: float, r: float) -> bool:
	if x < r or x > arena_w - r or y < r or y > arena_h - r:
		return false
	for ob in obstacles:
		if PGeom.dist(x, y, ob.x, ob.y) < ob.r + r + 2.0:
			return false
	return true

func nearest_valid_pos(x: float, y: float, r: float) -> Array:
	if valid_pos(x, y, r):
		return [x, y]
	var rad := 12.0
	while rad <= 260.0:
		for i in 16:
			var a := float(i) / 16.0 * TAU
			var px := x + cos(a) * rad
			var py := y + sin(a) * rad
			if valid_pos(px, py, r):
				return [px, py]
		rad += 12.0
	return []

## 장애물·벽 밖으로 밀어낸다
func push_out(o: Dictionary) -> void:
	for ob in obstacles:
		var dx: float = o.x - ob.x
		var dy: float = o.y - ob.y
		var d := sqrt(dx * dx + dy * dy)
		var mn: float = ob.r + o.r
		if d < mn:
			var nx := 1.0
			var ny := 0.0
			if d > 1e-6:
				nx = dx / d
				ny = dy / d
			o.x = ob.x + nx * mn
			o.y = ob.y + ny * mn
	o.x = clampf(o.x, o.r, arena_w - o.r)
	o.y = clampf(o.y, o.r, arena_h - o.r)

## 원이 이동하며 장애물과 처음 닿는 t와 장애물 인덱스. 없으면 [-1, -1]
func sweep_circle(x0: float, y0: float, x1: float, y1: float, r: float) -> Array:
	var best_t := -1.0
	var best_i := -1
	for i in obstacles.size():
		var ob: Dictionary = obstacles[i]
		var tt := PGeom.seg_circle_t(x0, y0, x1, y1, ob.x, ob.y, ob.r + r)
		if tt >= 0.0 and (best_i < 0 or tt < best_t):
			best_t = tt
			best_i = i
	return [best_t, best_i]

## 스윕 이동: 벽·장애물에 닿으면 그 지점에서 정지. slide면 남은 이동량을 접선 방향으로 한 번 더. 반환 {hit: ""|"wall"|장애물 id, t}
func move_swept(o: Dictionary, dx: float, dy: float, slide: bool = false) -> Dictionary:
	var x0: float = o.x
	var y0: float = o.y
	var x1 := x0 + dx
	var y1 := y0 + dy
	var tt := 1.0
	var hit := ""
	var hit_ob := {}
	var wx := clampf(x1, o.r, arena_w - o.r)
	var wy := clampf(y1, o.r, arena_h - o.r)
	if wx != x1 or wy != y1:
		var tx := 1.0
		var ty := 1.0
		if wx != x1:
			tx = (wx - x0) / dx
		if wy != y1:
			ty = (wy - y0) / dy
		tt = maxf(0.0, minf(tt, minf(tx, ty)))
		hit = "wall"
	var sw := sweep_circle(x0, y0, x0 + dx, y0 + dy, o.r)
	if sw[1] >= 0 and sw[0] < tt:
		tt = sw[0]
		hit_ob = obstacles[sw[1]]
		hit = hit_ob.id
	if hit != "":
		var t2 := maxf(0.0, tt - 1e-3)
		o.x = x0 + dx * t2
		o.y = y0 + dy * t2
	else:
		o.x = x1
		o.y = y1
	push_out(o)
	if hit != "" and slide:
		var rx := dx * (1.0 - tt)
		var ry := dy * (1.0 - tt)
		if hit == "wall":
			if wx != x1:
				rx = 0.0
			if wy != y1:
				ry = 0.0
		else:
			var nx: float = o.x - hit_ob.x
			var ny: float = o.y - hit_ob.y
			var nl := sqrt(nx * nx + ny * ny)
			if nl < 1e-9:
				nl = 1.0
			nx /= nl
			ny /= nl
			var dot := rx * nx + ry * ny
			rx -= dot * nx
			ry -= dot * ny
		if absf(rx) + absf(ry) > 1e-6:
			var sw2 := sweep_circle(o.x, o.y, o.x + rx, o.y + ry, o.r)
			var t3 := 1.0
			if sw2[1] >= 0:
				t3 = maxf(0.0, sw2[0] - 1e-3)
			o.x += rx * t3
			o.y += ry * t3
			push_out(o)
	return { "hit": hit, "t": tt }

## 장애물을 돌아가는 조향(HTML steerDir). 반환 [x, y] 단위 벡터
func steer_dir(e: Dictionary, tx: float, ty: float) -> Array:
	var dx: float = tx - e.x
	var dy: float = ty - e.y
	var dist := sqrt(dx * dx + dy * dy)
	if dist < 1e-6:
		return [0.0, 0.0]
	var d := [dx / dist, dy / dist]
	var blocker := {}
	var best_along := INF
	for ob in obstacles:
		var R: float = ob.r + e.r + 6.0
		var ox: float = ob.x - e.x
		var oy: float = ob.y - e.y
		var along: float = ox * d[0] + oy * d[1]
		if along <= 0.0 or along > minf(dist, 200.0) + R:
			continue
		var side: float = absf(-ox * d[1] + oy * d[0])
		if side < R and along < best_along:
			best_along = along
			blocker = ob
	if blocker.is_empty():
		e.steer_side = 0
		return d
	var ox2: float = blocker.x - e.x
	var oy2: float = blocker.y - e.y
	var od := sqrt(ox2 * ox2 + oy2 * oy2)
	var R2: float = blocker.r + e.r + 6.0
	var cross: float = d[0] * oy2 - d[1] * ox2
	if e.steer_side == 0 or e.steer_t <= 0.0:
		e.steer_side = -1 if cross > 0.0 else 1
		e.steer_t = 0.8
	var side_sign: float = float(e.steer_side)
	if od <= R2 + 0.5:
		var nx := ox2 / od
		var ny := oy2 / od
		return [-ny * side_sign, nx * side_sign]
	var base := atan2(oy2, ox2)
	var off := asin(minf(1.0, R2 / od))
	var ang := base + off * side_sign
	return [cos(ang), sin(ang)]

# ---------- 스폰·웨이브 ----------
func edge_pos() -> Array:
	var side := rng.int_range(0, 3)
	var pad := 30.0
	if side == 0:
		return [rng.range_f(pad, arena_w - pad), pad]
	if side == 1:
		return [arena_w - pad, rng.range_f(pad, arena_h - pad)]
	if side == 2:
		return [rng.range_f(pad, arena_w - pad), arena_h - pad]
	return [pad, rng.range_f(pad, arena_h - pad)]

func queue_wave(wave: Array) -> void:
	for g in wave:
		var er: float = float(cfg.enemies[g.type].r)
		for i in int(g.n):
			var p := edge_pos()
			var tries := 0
			while (PGeom.dist(p[0], p[1], player.x, player.y) < 160.0 or not valid_pos(p[0], p[1], er)) and tries < 12:
				p = edge_pos()
				tries += 1
			var vp := nearest_valid_pos(p[0], p[1], er)
			if not vp.is_empty():
				p = vp
			pending.append({ "type": g.type, "x": p[0], "y": p[1], "t": float(cfg.constants.spawn_warn) })
			_fx({ "kind": "spawnwarn", "x": p[0], "y": p[1], "ttl": float(cfg.constants.spawn_warn), "type": g.type })
	_ev("wave")

func spawn_enemy(type: String, x: float, y: float) -> Dictionary:
	var d: Dictionary = cfg.enemies[type]
	var e := {
		"id": _next_id, "type": type, "def": d, "x": x, "y": y, "r": float(d.r), "hp": float(d.hp), "hp_max": float(d.hp),
		"spawn_t": t, "acted": false, "state": "approach", "state_t": 0.0, "dir": 0.0, "aim_angle": 0.0, "flash": 0.0, "dead": false, "death_t": 0.0,
		"dash_left": int(d.dashes), "vx": 0.0, "vy": 0.0, "hit_by": false, "steer_side": 0, "steer_t": 0.0, "face_x": 1.0, "last_x": x, "last_y": y, "bite_t": 9.0,
	}
	_next_id += 1
	enemies.append(e)
	var m := _metrics_for(type)
	m.spawned += 1
	return e

func _metrics_for(type: String) -> Dictionary:
	if not metrics.enemies.has(type):
		metrics.enemies[type] = { "spawned": 0, "killed": 0, "prepared": 0, "executed": 0, "died_before_attack": 0 }
	return metrics.enemies[type]

func update_waves(dt: float) -> void:
	for s in pending:
		s.t -= dt
		if s.t <= 0.0:
			spawn_enemy(s.type, s.x, s.y)
	var keep := []
	for s in pending:
		if s.t > 0.0:
			keep.append(s)
	pending = keep
	var alive_n := alive_enemies().size()
	if wave_index < waves.size() - 1 and alive_n == 0 and pending.is_empty():
		wave_timer -= dt
		if wave_timer <= 0.0:
			wave_index += 1
			wave_timer = float(cfg.constants.wave_delay)
			queue_wave(waves[wave_index])
	spawned_all = wave_index >= waves.size() - 1 and pending.is_empty()

## 남은 적 수(살아 있는 + 등장 대기 + 남은 웨이브 정의)와 남은 웨이브
func remaining() -> Dictionary:
	var n := alive_enemies().size() + pending.size()
	var i := wave_index + 1
	while i < waves.size():
		for g in waves[i]:
			n += int(g.n)
		i += 1
	return { "total": n, "alive": alive_enemies().size(), "waves_left": maxi(0, waves.size() - 1 - maxi(0, wave_index)), "waves": waves.size() }

# ---------- 피해 ----------
func damage_player(amount: float, src: String) -> bool:
	var p := player
	if p.dead or status != "running":
		return false
	if p.dodge_active:
		stats.perfect_dodges += 1
		_fx({ "kind": "text", "x": p.x, "y": p.y - 30.0, "ttl": 0.8, "text": "회피!", "color": "#7ef2ff" })
		_ev("perfect")
		return false
	if p.hit_prot > 0.0:
		return false
	p.hp -= amount
	stats.damage_taken += amount
	metrics.taken[src] = float(metrics.taken.get(src, 0.0)) + amount
	p.flash = 0.2
	p.hurt_t = 0.0
	p.hit_prot = float(cfg.player.hit_protect)
	_fx({ "kind": "hitflash", "x": p.x, "y": p.y, "ttl": 0.25 })
	_ev("hurt")
	if p.hp <= 0.0:
		p.hp = 0.0
		p.dead = true
		status = "lost"
		_ev("lose")
	return true

## 적 피해. src_key = 피해 출처(예: "weapon:sword"). 유효 피해(과잉 제외)를 출처별로 집계한다. 빈틈(recover) 배율 적용
func damage_enemy(e: Dictionary, amount: float, src_key: String, knock: float = 0.0, dir: Array = []) -> float:
	if e.dead:
		return 0.0
	var dmg := amount
	var crit: bool = e.state == "recover"
	if crit:
		dmg *= float(cfg.constants.exposed_mult)
	dmg = round(dmg * 10.0) / 10.0
	var effective: float = minf(dmg, maxf(0.0, e.hp))
	metrics.dmg[src_key] = float(metrics.dmg.get(src_key, 0.0)) + effective
	e.hp -= dmg
	e.flash = 0.12
	if knock > 0.0 and not dir.is_empty() and e.state != "dash":
		e.vx += dir[0] * knock * 2.0
		e.vy += dir[1] * knock * 2.0
	_fx({ "kind": "spark", "x": e.x, "y": e.y, "ttl": 0.22, "crit": crit })
	_fx({ "kind": "text", "x": e.x + rng.range_f(-8.0, 8.0), "y": e.y - e.r - 6.0, "ttl": 0.8, "text": str(int(round(dmg))), "color": "#ffd166" if crit else "#ffffff" })
	_ev("hit")
	if e.hp <= 0.0:
		_kill_enemy(e)
	return dmg

func _kill_enemy(e: Dictionary) -> void:
	e.dead = true
	e.death_t = 0.0
	stats.kills += 1
	var m := _metrics_for(e.type)
	m.killed += 1
	if not e.acted:
		m.died_before_attack += 1
	_fx({ "kind": "death", "x": e.x, "y": e.y, "r": e.r, "ttl": 0.4 })
	_ev("kill")

# ---------- 플레이어 ----------
func update_player(input: Dictionary, dt: float) -> void:
	var p := player
	var P: Dictionary = cfg.player
	p.swing_t += dt
	p.hurt_t += dt
	if p.hit_prot > 0.0:
		p.hit_prot -= dt
	if p.flash > 0.0:
		p.flash -= dt
	if p.special_cd > 0.0:
		p.special_cd = maxf(0.0, p.special_cd - dt)
	var mv := PGeom.norm(float(input.get("mx", 0.0)), float(input.get("my", 0.0)))
	p.moving = mv[0] != 0.0 or mv[1] != 0.0
	if p.moving:
		p.face = atan2(mv[1], mv[0])
	# 회피(docs/RULES.md §회피): 누르는 순간(dodge_press) 같은 단계에서 즉시 출발. 방향은 시작 순간 고정
	# (이동 입력이 있으면 그 방향, 없으면 마지막 바라보는 방향 face). 재사용 대기는 시작 순간부터 센다.
	var D: Dictionary = P.dodge
	if not p.dodge_active and bool(input.get("dodge_press", false)) and p.dodge_cd <= 0.0:
		var d := mv if p.moving else [cos(p.face), sin(p.face)]
		p.dodge_active = true
		p.dodge_t = 0.0
		p.dodge_dist = 0.0
		p.dodge_released = false
		p.dodge_end = ""
		p.dodge_dx = d[0]
		p.dodge_dy = d[1]
		p.dodge_cd = float(D.cooldown)
		stats.dodges += 1
		_ev("dodge")
	if p.dodge_cd > 0.0:
		p.dodge_cd = maxf(0.0, p.dodge_cd - dt)
		if p.dodge_cd < 1e-6:
			p.dodge_cd = 0.0 # 고정 단계 누적 오차로 0이 안 되는 것 방지(정확히 cooldown/STEP 단계 뒤 재사용 가능)
	if p.dodge_active:
		# 누름 상태: 떼면(hold 방식) 최소 거리를 채운 시점에 끝난다. fixed 방식은 떼도 최대 거리까지 간다.
		if not bool(input.get("dodge_held", false)):
			p.dodge_released = true
		var spd := float(D.distance) / float(D.duration) # 회피 속도는 일정(150/0.26)
		var target := float(D.distance)
		if String(D.mode) == "hold" and p.dodge_released:
			target = maxf(float(D.min_distance), p.dodge_dist)
		var remain := maxf(0.0, target - p.dodge_dist)
		var want := minf(spd * dt, remain) # 마지막 이동량은 남은 거리로 제한(초과 이동 없음)
		var x0: float = p.x
		var y0: float = p.y
		var blocked := false
		if want > 0.0:
			var res := move_swept(p, p.dodge_dx * want, p.dodge_dy * want)
			blocked = String(res.hit) != "" # 바위·나무·경계에 막히면 그 자리에서 종료(붙어서 무적 유지 없음)
		p.dodge_dist += PGeom.dist(x0, y0, p.x, p.y)
		p.dodge_t += dt
		if blocked or p.dodge_dist >= target - 1e-6 or p.dodge_t >= float(D.duration) - 1e-9:
			p.dodge_active = false # 무적(dodge_active)은 회피 이동과 함께 끝난다
			p.dodge_end = "blocked" if blocked else ("max" if p.dodge_dist >= float(D.distance) - 1e-6 else "release")
			stats.dodge_dists.append(snapped(p.dodge_dist, 0.1))
	else:
		move_swept(p, mv[0] * float(P.speed) * dt, mv[1] * float(P.speed) * dt, true)
	if bool(input.get("special", false)) and p.special_cd <= 0.0:
		cast_slowfield()
	push_out(p)
	update_attack(dt)

func cast_slowfield() -> void:
	var S: Dictionary = cfg.player.slowfield
	var p := player
	field = { "x": p.x, "y": p.y, "r": float(S.radius), "ttl": float(S.duration), "max_ttl": float(S.duration) }
	p.special_cd = float(S.cooldown)
	stats.special_uses += 1
	_ev("special")
	_fx({ "kind": "text", "x": p.x, "y": p.y - 50.0, "ttl": 0.8, "text": "감속장", "color": "#a9d8ff" })

## 자동 공격(검격): 주기마다 사거리 안·가림 없는 가장 가까운 적을 향해 부채꼴. 대상이 없으면 대기(주기 소모 없음)
func update_attack(dt: float) -> void:
	var p := player
	var W: Dictionary = cfg.weapon
	p.attack_timer -= dt
	if p.attack_timer > 0.0:
		return
	var target := pick_target(float(W.range), true)
	if target.is_empty():
		p.attack_timer = 0.05 # HTML과 같이 대상이 없으면 0.05초 뒤 다시 찾는다
		return
	p.attack_timer = maxf(-float(W.interval) * 0.5, p.attack_timer) + float(W.interval) # HTML weapons.js와 같이 음수 잔여를 이월(주기 누적 오차 방지)
	var ang := atan2(target.y - p.y, target.x - p.x)
	var half := float(W.arc_deg) * PI / 360.0
	p.face = ang
	p.swing_t = 0.0
	p.swing_angle = ang
	stats.attacks += 1
	_fx({ "kind": "arc", "x": p.x, "y": p.y, "angle": ang, "r": float(W.range), "half": half, "ttl": 0.16 })
	for e in alive_enemies():
		if PGeom.in_arc(p.x, p.y, float(W.range), ang, half, e.x, e.y, e.r) and not los_blocked(p.x, p.y, e.x, e.y):
			stats.hits += 1
			damage_enemy(e, float(W.damage), "weapon:" + str(W.id), float(W.knock), PGeom.norm(e.x - p.x, e.y - p.y))
	_ev("swing")

func pick_target(range_v: float, need_los: bool) -> Dictionary:
	var p := player
	var best := {}
	var bd := INF
	for e in alive_enemies():
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d > range_v + e.r:
			continue
		if need_los and los_blocked(p.x, p.y, e.x, e.y):
			continue
		if d < bd:
			bd = d
			best = e
	return best

# ---------- 늑대 ----------
func _approach(e: Dictionary, tx: float, ty: float, speed: float, dt: float) -> void:
	if e.steer_t > 0.0:
		e.steer_t -= dt
	var n: Array
	if obstacles.is_empty():
		n = PGeom.norm(tx - e.x, ty - e.y)
	else:
		n = steer_dir(e, tx, ty)
	move_swept(e, n[0] * speed * dt, n[1] * speed * dt, true)

func update_wolf(e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := player
	var tf := time_factor(e.x, e.y, e.r)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match e.state:
		"approach":
			_approach(e, p.x, p.y, float(d.speed) * tf, dt)
			if dist <= float(d.engage_dist) and not los_blocked(e.x, e.y, p.x, p.y):
				e.state = "crouch"
				e.state_t = 0.0
				e.dash_left = int(d.dashes)
				e.acted = true
				_metrics_for(e.type).prepared += 1
		"crouch": # 방향 추적 중(예고)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += dt * tf
			if e.state_t >= float(d.crouch):
				e.state = "lock" # 방향 확정: 이후 바꾸지 않는다
				e.state_t = 0.0
				e.dir = e.aim_angle
				_ev("lock")
		"lock":
			e.state_t += dt * tf
			if e.state_t >= float(d.lock):
				e.state = "dash"
				e.state_t = 0.0
				e.hit_by = false
				_metrics_for(e.type).executed += 1
		"dash":
			var remain := maxf(0.0, float(d.dash_time) - e.state_t)
			var use_dt := minf(dt * tf, remain)
			e.state_t += dt * tf
			var stp := float(d.dash_speed) * use_dt
			var x0: float = e.x
			var y0: float = e.y
			var mv := move_swept(e, cos(e.dir) * stp, sin(e.dir) * stp)
			if not e.hit_by and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
				e.hit_by = true
				e.bite_t = 0.0
				_ev("bite")
				damage_player(float(d.damage), "wolf")
			var hit_wall: bool = mv.hit != ""
			if e.state_t >= float(d.dash_time) or hit_wall:
				if not e.hit_by:
					e.bite_t = 0.0
				e.dash_left -= 1
				if e.dash_left > 0:
					e.state = "crouch"
					e.state_t = 0.0
				else:
					e.state = "recover" # 빈틈
					e.state_t = 0.0
		"recover":
			e.state_t += dt * tf
			if e.state_t >= float(d.recover):
				e.state = "approach"
				e.state_t = 0.0

func update_enemies(dt: float) -> void:
	for e in enemies:
		if e.dead:
			e.death_t += dt
			continue
		e.bite_t += dt
		var mdx: float = e.x - e.last_x
		if absf(mdx) > 0.02:
			e.face_x = 1.0 if mdx > 0.0 else -1.0
		e.last_x = e.x
		e.last_y = e.y
		if e.flash > 0.0:
			e.flash -= dt
		update_wolf(e, dt)
		if e.vx != 0.0 or e.vy != 0.0:
			move_swept(e, e.vx * dt, e.vy * dt)
			var k := exp(-10.0 * dt)
			e.vx *= k
			e.vy *= k
			if absf(e.vx) < 1.0:
				e.vx = 0.0
			if absf(e.vy) < 1.0:
				e.vy = 0.0
		push_out(e)
	# 분리: 완전히 겹치지 않게
	var al := alive_enemies()
	for i in al.size():
		for j in range(i + 1, al.size()):
			var A: Dictionary = al[i]
			var B: Dictionary = al[j]
			if A.state == "dash" or B.state == "dash":
				continue
			var dx: float = B.x - A.x
			var dy: float = B.y - A.y
			var dd := sqrt(dx * dx + dy * dy)
			var mn: float = A.r + B.r
			if dd < mn and dd > 1e-6:
				var push: float = (mn - dd) / 2.0 * float(cfg.constants.separation)
				A.x -= dx / dd * push
				A.y -= dy / dd * push
				B.x += dx / dd * push
				B.y += dy / dd * push
				push_out(A)
				push_out(B)
	var keep := []
	for e in enemies:
		if not e.dead or e.death_t < float(cfg.constants.death_linger):
			keep.append(e)
	enemies = keep

func update_field(dt: float) -> void:
	if field.is_empty():
		return
	field.ttl -= dt
	if field.ttl <= 0.0:
		field = {}

func update_effects(dt: float) -> void:
	for f in effects:
		f.t += dt
		if f.kind == "text":
			f.y -= 30.0 * dt
	var keep := []
	for f in effects:
		if f.t < f.ttl:
			keep.append(f)
	effects = keep

func check_objective() -> void:
	if status != "running":
		return
	if spawned_all and pending.is_empty() and alive_enemies().is_empty():
		status = "won"
		_ev("win")

## 고정 단계 1회. 종료 뒤에는 표시용 효과만 진행한다(전투 시간·재사용 시간은 멈춘다)
func step(input: Dictionary, dt: float) -> void:
	step_n += 1
	if status != "running":
		update_effects(dt)
		for e in enemies:
			if e.dead:
				e.death_t += dt
		return
	t += dt
	stats.elapsed += dt
	update_player(input, dt)
	update_enemies(dt)
	update_field(dt)
	update_waves(dt)
	update_effects(dt)
	check_objective()

## 결과 요약(정산은 호출자가 1회만 한다: settled 플래그)
func summary() -> Dictionary:
	var total := 0.0
	for k in metrics.dmg:
		total += metrics.dmg[k]
	return { "status": status, "elapsed": snapped(t, 0.01), "hp": player.hp, "hp_max": player.hp_max, "kills": stats.kills, "damage_taken": stats.damage_taken, "attacks": stats.attacks, "hits": stats.hits, "dodges": stats.dodges, "special_uses": stats.special_uses, "dmg": metrics.dmg.duplicate(), "dmg_total": snapped(total, 0.1), "taken": metrics.taken.duplicate(), "enemies": metrics.enemies.duplicate(true), "steps": step_n, "seed": seed_value, "dodge_mode": String(cfg.player.dodge.mode), "dodge_cooldown": float(cfg.player.dodge.cooldown), "dodge_dists": stats.dodge_dists.duplicate(), "perfect_dodges": stats.perfect_dodges }
