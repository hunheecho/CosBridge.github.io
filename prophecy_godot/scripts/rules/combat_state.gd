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
var pending: Array = []        # 등장 대기(예고 중). 동시 생존 상한에 포함된다
var formation: Dictionary = {} # {total, alive_cap, group, interval}
var spawn_total: int = 0
var spawn_count: int = 0       # 지금까지 예약(등장 + 대기)한 수
var spawn_timer: float = 0.4
var spawn_hold: bool = false   # 테스트·시연용: 소환 멈춤(승리 판정도 나지 않는다)
var spawned_all: bool = false
var attack_log: Array = []     # [t, id, kind] 공격 시작 순서(재현 검사용)
var field: Dictionary = {}
var obstacles: Array = []
var arena_w: float
var arena_h: float
var effects: Array = []   # 표시용 이벤트(화면이 읽기만 한다): {kind, x, y, ttl, t, ...}
var events: Array = []    # 소리·통계용 이벤트 이름
var stats: Dictionary = { "kills": 0, "damage_taken": 0.0, "damage_taken_nominal": 0.0, "attacks": 0, "hits": 0, "dodges": 0, "special_uses": 0, "perfect_dodges": 0, "elapsed": 0.0, "dodge_dists": [], "xp": 0.0, "max_alive": 0, "max_dash_states": 0, "max_bite_states": 0 }
var metrics: Dictionary = { "dmg": {}, "taken": {}, "enemies": {} } # 피해 출처별 유효 피해(과잉 제외), 받은 피해 원인별(유효 피해, 합 = stats.damage_taken = 실제 체력 감소)
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
	formation = cfg.formation if cfg.has("formation") else cfg.formations[cfg.formation_default]
	spawn_total = int(formation.total)
	spawn_timer = float(cfg.spawn.first_delay)
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

# ---------- 소환(편성: 전체 수·동시 생존 상한·묶음·보충 간격) ----------
## 진입 지점: 가장자리 8곳 중 플레이어에서 min_player_dist 이상 떨어진 곳을 시드로 고른다(없으면 가장 먼 곳)
func pick_entry_point() -> Array:
	var pts: Array = cfg.spawn.entry_points
	var ok := []
	var far := []
	var far_d := -1.0
	for q in pts:
		var dd := PGeom.dist(float(q[0]), float(q[1]), player.x, player.y)
		if dd >= float(cfg.spawn.min_player_dist):
			ok.append([float(q[0]), float(q[1])])
		if dd > far_d:
			far_d = dd
			far = [float(q[0]), float(q[1])]
	if ok.is_empty():
		return far
	return ok[rng.int_range(0, ok.size() - 1)]

## 묶음 n마리를 한 진입 지점 주변에 예약(예고 뒤 등장). 플레이어 바로 위·장애물 안에는 두지 않는다
func queue_group(type: String, n: int) -> void:
	var er: float = float(cfg.enemies[type].r)
	var base := pick_entry_point()
	var spread: float = float(cfg.spawn.group_spread)
	var min_pd: float = float(cfg.spawn.min_player_dist)
	for i in n:
		var px: float = base[0] + rng.range_f(-spread, spread)
		var py: float = base[1] + rng.range_f(-spread, spread)
		px = clampf(px, er + 4.0, arena_w - er - 4.0)
		py = clampf(py, er + 4.0, arena_h - er - 4.0)
		var vp := nearest_valid_pos(px, py, er)
		if not vp.is_empty():
			px = vp[0]
			py = vp[1]
		var dp := PGeom.dist(px, py, player.x, player.y)
		if dp < min_pd * 0.5: # 진입 지점이 멀어도 편차로 가까워졌으면 플레이어 반대쪽으로 민다
			var away := PGeom.norm(px - player.x, py - player.y) if dp > 1e-6 else [1.0, 0.0]
			px = clampf(player.x + away[0] * min_pd * 0.5, er + 4.0, arena_w - er - 4.0)
			py = clampf(player.y + away[1] * min_pd * 0.5, er + 4.0, arena_h - er - 4.0)
			vp = nearest_valid_pos(px, py, er)
			if not vp.is_empty():
				px = vp[0]
				py = vp[1]
		pending.append({ "type": type, "x": px, "y": py, "t": float(cfg.spawn.warn) })
		_fx({ "kind": "spawnwarn", "x": px, "y": py, "ttl": float(cfg.spawn.warn), "type": type })
	_ev("group")

func spawn_enemy(type: String, x: float, y: float) -> Dictionary:
	var d: Dictionary = cfg.enemies[type]
	var e := {
		"id": _next_id, "type": type, "def": d, "x": x, "y": y, "r": float(d.r), "hp": float(d.hp), "hp_max": float(d.hp),
		"spawn_t": t, "acted": false, "state": "approach", "state_t": 0.0, "dir": 0.0, "aim_angle": 0.0, "flash": 0.0, "dead": false, "death_t": 0.0,
		"vx": 0.0, "vy": 0.0, "hit_by": false, "steer_side": 0, "steer_t": 0.0, "face_x": 1.0, "last_x": x, "last_y": y, "bite_t": 9.0,
		# 공격 재사용: 생성 시 시드로 1회 정한 초기 편차. dash_ready_at은 시뮬레이션 시간(배율 없음), 재사용 대기(cd)는 적 시간 배율을 따른다
		"dash_ready_at": t + rng.range_f(float(d.dash.first_delay[0]), float(d.dash.first_delay[1])),
		"dash_cd": 0.0, "bite_cd": rng.range_f(float(d.bite.initial_delay[0]), float(d.bite.initial_delay[1])),
		"last_dash_end": -1.0, "dash_granted": false, "bite_hit_done": false, "bites": 0, "dashes": 0,
	}
	_next_id += 1
	enemies.append(e)
	var m := _metrics_for(type)
	m.spawned += 1
	return e

func _metrics_for(type: String) -> Dictionary:
	if not metrics.enemies.has(type):
		metrics.enemies[type] = { "spawned": 0, "killed": 0, "prepared": 0, "executed": 0, "died_before_attack": 0, "died_before_execute": 0, "bites_prepared": 0, "bites_executed": 0, "bite_hits": 0, "dashes_prepared": 0, "dashes_executed": 0, "dash_hits": 0 }
	return metrics.enemies[type]

## 등장 대기 진행 + 보충. 동시 생존 상한(살아 있는 + 대기)을 넘겨 예약하지 않고, 묶음 사이에 최소 간격을 둔다
func update_spawner(dt: float) -> void:
	for sp in pending:
		sp.t -= dt
		if sp.t <= 0.0:
			spawn_enemy(sp.type, sp.x, sp.y)
	var keep := []
	for sp in pending:
		if sp.t > 0.0:
			keep.append(sp)
	pending = keep
	spawned_all = spawn_count >= spawn_total and pending.is_empty()
	if spawn_hold or spawn_count >= spawn_total:
		return
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	var room: int = int(formation.alive_cap) - alive_enemies().size() - pending.size()
	if room <= 0:
		return
	var n: int = mini(int(formation.group), mini(room, spawn_total - spawn_count))
	if n <= 0:
		return
	queue_group("wolf", n)
	spawn_count += n
	spawn_timer = float(formation.interval)

## 남은 적 수(살아 있는 + 등장 대기 + 아직 예약하지 않은 수)
func remaining() -> Dictionary:
	var alive_n := alive_enemies().size()
	return { "total": alive_n + pending.size() + (spawn_total - spawn_count), "alive": alive_n, "pending": pending.size(), "cap": int(formation.alive_cap), "spawn_total": spawn_total, "spawned": spawn_count - pending.size() }

## 처치 경험치: 같은 전투의 기본 예산(base_fight_xp)을 편성의 전체 수로 나눈다. 소수 누적(표시는 내림)
func xp_per_kill() -> float:
	return float(cfg.reward.base_fight_xp) / float(spawn_total)

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
	# 유효 피해 = 타격 직전 남은 체력을 넘지 않는 양(과잉 제외). 총합·출처별에 같은 값을 기록한다. 명목 피해는 damage_taken_nominal에만 남긴다
	var effective: float = minf(amount, maxf(0.0, p.hp))
	p.hp -= effective
	stats.damage_taken += effective
	stats.damage_taken_nominal += amount
	metrics.taken[src] = float(metrics.taken.get(src, 0.0)) + effective
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
	stats.xp += xp_per_kill()
	var m := _metrics_for(e.type)
	m.killed += 1
	if not e.acted:
		m.died_before_attack += 1 # 공격 준비(예고)조차 못 하고 죽음
	if e.bites + e.dashes == 0:
		m.died_before_execute += 1 # 예고는 했지만 실제 공격(물기 유효 구간·돌진)을 한 번도 못 하고 죽음
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

# ---------- 늑대 (docs/RULES.md §늑대: 가까우면 물기, 적당한 거리·재사용 가능·자리 확보 시 돌진) ----------
func _approach(e: Dictionary, tx: float, ty: float, speed: float, dt: float) -> void:
	if e.steer_t > 0.0:
		e.steer_t -= dt
	var n: Array
	if obstacles.is_empty():
		n = PGeom.norm(tx - e.x, ty - e.y)
	else:
		n = steer_dir(e, tx, ty)
	move_swept(e, n[0] * speed * dt, n[1] * speed * dt, true)

## 돌진 자리(준비·고정·실행 합계) 사용 수
func dash_states_count() -> int:
	var n := 0
	for e in alive_enemies():
		if e.state == "crouch" or e.state == "lock" or e.state == "dash":
			n += 1
	return n

func bite_states_count() -> int:
	var n := 0
	for e in alive_enemies():
		if e.state == "bite_track" or e.state == "bite_lock" or e.state == "bite_hit":
			n += 1
	return n

## 이 단계에 돌진을 원하는가(접근 중·첫 지연 경과·재사용 가능·거리 조건·시야)
func wants_dash(e: Dictionary) -> bool:
	if e.state != "approach" or e.dead:
		return false
	var D: Dictionary = e.def.dash
	if t < float(e.dash_ready_at) or e.dash_cd > 0.0:
		return false
	var dist := PGeom.dist(e.x, e.y, player.x, player.y)
	if dist < float(D.min_dist) or dist > float(D.engage_dist):
		return false
	return not los_blocked(e.x, e.y, player.x, player.y)

## 동시 돌진 제한: 빈 자리만큼, 마지막 돌진이 오래된 순(동률은 id) — 매 단계 추첨 없음, 같은 시드·입력이면 같은 순서
func grant_dash_slots() -> void:
	var D: Dictionary = cfg.enemies.wolf.dash
	var free: int = int(D.max_concurrent) - dash_states_count()
	if free <= 0:
		return
	var cands := []
	for e in alive_enemies():
		if wants_dash(e):
			cands.append(e)
	cands.sort_custom(func(a, b):
		if a.last_dash_end != b.last_dash_end:
			return a.last_dash_end < b.last_dash_end
		return a.id < b.id)
	for i in mini(free, cands.size()):
		cands[i].dash_granted = true

func _bite_hit_check(e: Dictionary) -> bool:
	var B: Dictionary = e.def.bite
	var p := player
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if dist > float(B.reach):
		return false
	var ang := atan2(p.y - e.y, p.x - e.x)
	return absf(PGeom.ang_diff(ang, e.dir)) <= float(B.arc_deg) * PI / 360.0

func update_wolf(e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var D: Dictionary = d.dash
	var B: Dictionary = d.bite
	var p := player
	var tf := time_factor(e.x, e.y, e.r)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	# 재사용 대기는 상태와 무관하게 적 시간 배율로 줄어든다(감속장 안에서는 느리게, 일시정지는 단계가 없으므로 정지)
	if e.dash_cd > 0.0:
		e.dash_cd = maxf(0.0, e.dash_cd - dt * tf)
		if e.dash_cd < 1e-6:
			e.dash_cd = 0.0
	if e.bite_cd > 0.0:
		e.bite_cd = maxf(0.0, e.bite_cd - dt * tf)
		if e.bite_cd < 1e-6:
			e.bite_cd = 0.0
	match e.state:
		"approach":
			if dist <= float(B.reach) and e.bite_cd <= 0.0:
				e.state = "bite_track" # 물기 준비: 앞 0.2초 추적
				e.state_t = 0.0
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				e.acted = true
				e.dash_granted = false
				_metrics_for(e.type).bites_prepared += 1
				_metrics_for(e.type).prepared += 1
				attack_log.append([snapped(t, 0.0001), e.id, "bite"])
			elif e.dash_granted:
				e.dash_granted = false
				e.state = "crouch" # 돌진 준비(자리 확보됨)
				e.state_t = 0.0
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				e.acted = true
				_metrics_for(e.type).dashes_prepared += 1
				_metrics_for(e.type).prepared += 1
				attack_log.append([snapped(t, 0.0001), e.id, "dash"])
			elif dist > float(B.reach) - 4.0:
				_approach(e, p.x, p.y, float(d.speed) * tf, dt)
			# 물기 범위 안인데 재사용 대기 중이면 제자리(밀고 들어가지 않는다)
		"bite_track": # 방향 추적(예고)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += dt * tf
			if e.state_t >= float(B.track):
				e.state = "bite_lock" # 방향 고정: 이후 추적하지 않는다
				e.state_t = 0.0
				e.dir = e.aim_angle
				_ev("bite_lock")
		"bite_lock":
			e.state_t += dt * tf
			if e.state_t >= float(B.lock):
				e.state = "bite_hit" # 공격 유효 구간(0.1초): 예고한 부채꼴에 1회만 타격
				e.state_t = 0.0
				e.bite_hit_done = false
				e.bites += 1
				_metrics_for(e.type).bites_executed += 1
				_metrics_for(e.type).executed += 1
		"bite_hit":
			if not e.bite_hit_done and _bite_hit_check(e):
				e.bite_hit_done = true
				e.bite_t = 0.0
				_ev("bite")
				if damage_player(float(B.damage), "wolf:bite"):
					_metrics_for(e.type).bite_hits += 1
			e.state_t += dt * tf
			if e.state_t >= float(B.active):
				e.state = "bite_recover" # 물기 뒤 빈틈(피해 보너스 없음)
				e.state_t = 0.0
				e.bite_cd = float(B.cooldown) # 유효 구간 종료 시점부터, 빈틈 0.4 포함
		"bite_recover":
			e.state_t += dt * tf
			if e.state_t >= float(B.recover):
				e.state = "approach"
				e.state_t = 0.0
		"crouch": # 돌진 방향 추적 중(예고)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += dt * tf
			if e.state_t >= float(D.crouch):
				e.state = "lock" # 방향 확정: 이후 바꾸지 않는다
				e.state_t = 0.0
				e.dir = e.aim_angle
				_ev("lock")
		"lock":
			e.state_t += dt * tf
			if e.state_t >= float(D.lock):
				e.state = "dash"
				e.state_t = 0.0
				e.hit_by = false
				e.dashes += 1
				_metrics_for(e.type).dashes_executed += 1
				_metrics_for(e.type).executed += 1
		"dash":
			var remain := maxf(0.0, float(D.dash_time) - e.state_t)
			var use_dt := minf(dt * tf, remain)
			e.state_t += dt * tf
			var stp := float(D.dash_speed) * use_dt
			var x0: float = e.x
			var y0: float = e.y
			var mv := move_swept(e, cos(e.dir) * stp, sin(e.dir) * stp)
			if not e.hit_by and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
				e.hit_by = true
				e.bite_t = 0.0
				_ev("dash_hit")
				if damage_player(float(D.damage), "wolf:dash"):
					_metrics_for(e.type).dash_hits += 1
			var hit_wall: bool = mv.hit != ""
			if e.state_t >= float(D.dash_time) or hit_wall:
				if not e.hit_by:
					e.bite_t = 0.0
				e.state = "recover" # 빈틈(받는 피해 ×1.5). 장애물에 막혀 끝나도 같다
				e.state_t = 0.0
				e.dash_cd = float(D.cooldown) # 돌진 종료 시점부터, 빈틈 0.9 포함
				e.last_dash_end = t
		"recover": # 빈틈: 물기를 포함한 모든 공격 금지
			e.state_t += dt * tf
			if e.state_t >= float(D.recover):
				e.state = "approach"
				e.state_t = 0.0

func update_enemies(dt: float) -> void:
	grant_dash_slots()
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
		e.dash_granted = false # 이 단계에 쓰지 않은 허가는 버린다(다음 단계에 다시 판단)
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
	resolve_overlaps(dt)
	var keep := []
	for e in enemies:
		if not e.dead or e.death_t < float(cfg.constants.death_linger):
			keep.append(e)
	enemies = keep
	var al := alive_enemies().size()
	if al > stats.max_alive:
		stats.max_alive = al
	var ds := dash_states_count()
	if ds > stats.max_dash_states:
		stats.max_dash_states = ds
	var bs := bite_states_count()
	if bs > stats.max_bite_states:
		stats.max_bite_states = bs

## 겹침 해소(피해 없음): 적끼리는 절반씩, 적-플레이어는 적이 70%·플레이어가 30%. 플레이어 밀림은 단계당 상한(고속 날림 없음),
## 회피 중에는 적의 몸을 통과한다. 같은 좌표면 id 기반 방향. 밀린 뒤 장애물·경계 밖으로 밀어낸다(장애물 안으로 들어가지 않음)
func resolve_overlaps(dt: float) -> void:
	var al := alive_enemies()
	for i in al.size():
		for j in range(i + 1, al.size()):
			var A: Dictionary = al[i]
			var Bq: Dictionary = al[j]
			if A.state == "dash" or Bq.state == "dash":
				continue
			var dx: float = Bq.x - A.x
			var dy: float = Bq.y - A.y
			var dd := sqrt(dx * dx + dy * dy)
			var mn: float = A.r + Bq.r
			if dd < mn:
				var n: Array = [dx / dd, dy / dd] if dd > 1e-6 else [cos(float(A.id) * 2.399), sin(float(A.id) * 2.399)]
				var push: float = minf((mn - dd) / 2.0 * float(cfg.constants.separation), 6.0)
				A.x -= n[0] * push
				A.y -= n[1] * push
				Bq.x += n[0] * push
				Bq.y += n[1] * push
				push_out(A)
				push_out(Bq)
	var p := player
	if p.dead or p.dodge_active:
		return
	var px_sum := 0.0
	var py_sum := 0.0
	for e in al:
		if e.state == "dash":
			continue
		var dx: float = p.x - e.x
		var dy: float = p.y - e.y
		var dd := sqrt(dx * dx + dy * dy)
		var mn: float = p.r + e.r
		if dd < mn:
			var n: Array = [dx / dd, dy / dd] if dd > 1e-6 else [cos(float(e.id) * 2.399), sin(float(e.id) * 2.399)]
			var overlap: float = mn - dd
			e.x -= n[0] * overlap * 0.7
			e.y -= n[1] * overlap * 0.7
			push_out(e)
			px_sum += n[0] * overlap * 0.3
			py_sum += n[1] * overlap * 0.3
	var mag := sqrt(px_sum * px_sum + py_sum * py_sum)
	var cap: float = 120.0 * dt # 플레이어 밀림 상한 120/s(여러 적의 밀침을 합산해도 이 이상 빠르지 않다)
	if mag > 1e-9:
		var k := minf(1.0, cap / mag)
		move_swept(p, px_sum * k, py_sum * k, true)
		push_out(p)

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
	update_spawner(dt)
	update_effects(dt)
	check_objective()

## 결과 요약(정산은 호출자가 1회만 한다: settled 플래그)
func summary() -> Dictionary:
	var total := 0.0
	for k in metrics.dmg:
		total += metrics.dmg[k]
	return { "status": status, "elapsed": snapped(t, 0.01), "hp": player.hp, "hp_max": player.hp_max, "kills": stats.kills, "damage_taken": stats.damage_taken, "damage_taken_nominal": stats.damage_taken_nominal, "attacks": stats.attacks, "hits": stats.hits, "dodges": stats.dodges, "special_uses": stats.special_uses, "dmg": metrics.dmg.duplicate(), "dmg_total": snapped(total, 0.1), "taken": metrics.taken.duplicate(), "enemies": metrics.enemies.duplicate(true), "steps": step_n, "seed": seed_value, "dodge_mode": String(cfg.player.dodge.mode), "dodge_cooldown": float(cfg.player.dodge.cooldown), "dodge_dists": stats.dodge_dists.duplicate(), "perfect_dodges": stats.perfect_dodges, "formation": String(cfg.formation_id) if cfg.has("formation_id") else "?", "spawn_total": spawn_total, "spawned": spawn_count, "xp": snapped(stats.xp, 0.0001), "max_alive": stats.max_alive, "max_dash_states": stats.max_dash_states, "max_bite_states": stats.max_bite_states, "dash_max": int(cfg.enemies.wolf.dash.max_concurrent), "wolf_hp": float(cfg.enemies.wolf.hp) }
