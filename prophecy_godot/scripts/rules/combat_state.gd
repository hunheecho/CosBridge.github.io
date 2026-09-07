class_name CombatState
extends RefCounted
## 전투 규칙(순수 시뮬레이션, HTML combat.js 이식 + godot-0.3.1 첫 전투 규칙 보존). 화면·입력 장치·저장소를 모르며 고정 단계 step(input, dt)로만 진행한다.
## 입력 = {mx, my, dodge_press, dodge_held, special, skill_e}. 사람 입력과 봇 입력이 같은 함수를 쓴다. 회피·늑대·밀도 규칙은 docs/RULES.md.
## 생성: CombatState.new(opts) — opts는 docs/PORT_CONVENTIONS.md. 첫 전투(D33 기준 전투)는 CombatState.first_fight(cfg, seed).

var cfg: Dictionary            # 호환 설정(player·enemies·constants·spawn·formation·reward). 첫 전투는 first_fight.json 그대로
var build: Dictionary          # PBuild.derive 결과
var opts: Dictionary
var rng: PRng
var seed_value: int
var t: float = 0.0
var step_n: int = 0
var status: String = "running" # running | won | lost | timeout
var mode: String = "normal"    # normal | boss
var objective: String = "clear"
var region_id: String = ""
var hp_mult: Dictionary = { "normal": 1.0, "elite": 1.0, "boss": 1.0 }
var time_limit: float = 0.0
var fixed_build: bool = false
var overlap_limit: int = 0
var intro: float = 0.0
var player: Dictionary
var enemies: Array = []
var pending: Array = []        # 등장 대기(예고 중). 동시 생존 상한에 포함된다
var projectiles: Array = []
var zones: Array = []
var pickups: Array = []
var objects: Array = []
var obj: Dictionary = {}       # 목표 진행 상태(PObjectives)
var mission: Dictionary = {}
var risk: String = ""
var chest: Dictionary = {}
var chest_enabled: bool = false
var chest_spawned: bool = false
var boss: Dictionary = {}
var boss_id: String = ""
var boss_down_t: float = 0.0
var pending_loss: bool = false
var orbs_spawned: Dictionary = {}
var phase_events: Array = []
var weapons: Array = []
var mines: Array = []
var delayed: Array = []
var skill_state: Dictionary = {}
var field: Dictionary = {}
var mark_target = null
var caster_cd: float = 0.0
var caster_shield: Dictionary = {}
var low_shield_used: bool = false
var temp_buff: String = ""
var level_ups: int = 0
var xp_gained: float = 0.0
var formation: Dictionary = {} # {units[], alive_cap, group, interval, type_caps{}, total}
var spawn_total: int = 0
var spawn_count: int = 0       # 지금까지 예약(등장 + 대기)한 수
var spawn_timer: float = 0.4
var spawn_hold: bool = false   # 테스트·시연용: 소환 멈춤(승리 판정도 나지 않는다)
var spawned_all: bool = false
var xp_map: Dictionary = {}    # type → 마리당 경험치(밀도 모델 예산). 없으면 xp_default_scale × 단위값
var xp_default_scale: float = 1.0
var attack_log: Array = []     # [t, id, kind] 공격 시작 순서(재현 검사용)
var obstacles: Array = []
var arena_w: float
var arena_h: float
var arena_id: String = "clearing"
var effects: Array = []   # 표시용 이벤트(화면이 읽기만 한다): {kind, x, y, ttl, t, ...}
var events: Array = []    # 소리·통계용 이벤트 이름
var stats: Dictionary = {}
var metrics: Dictionary = {}
var active_t: Dictionary = {}
var stats_recorded: bool = false
var settled: bool = false
var _in_step: bool = false
var _next_id: int = 1

static func _new_stats() -> Dictionary:
	return { "kills": 0, "damage_taken": 0.0, "damage_taken_nominal": 0.0, "attacks": 0, "hits": 0, "dodges": 0, "special_uses": 0, "e_uses": 0, "perfect_dodges": 0, "elapsed": 0.0, "dodge_dists": [], "xp": 0.0, "level_ups": 0, "max_alive": 0, "max_dash_states": 0, "max_bite_states": 0, "chest_gold": 0, "boss_damage": 0.0, "absorbed": 0.0, "healed": 0.0, "elite_kills": 0, "saving_kills": 0, "equip_procs": {} }

static func _new_metrics() -> Dictionary:
	return { "dmg": {}, "taken": {}, "taken_hits": {}, "enemies": {}, "hits": {}, "patterns": {}, "absorbed": 0.0, "interrupts": 0, "webs": 0, "heals": 0, "heal_amount": 0.0, "far_frac": -1.0 }

## 첫 전투(godot-0.3.1 D33 기준 전투): first_fight.json 설정 그대로. RNG 소비 순서·늑대 규칙·검격 타이밍이 0.3.1과 같다
static func first_fight(config: Dictionary, seed_v: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var form: Dictionary = config.formation if config.has("formation") else config.formations[config.formation_default]
	var units := []
	for i in int(form.total):
		units.append("wolf")
	var o := { "build": b, "seed": seed_v, "cfg": config, "obstacles": config.obstacles, "arena": "first_fight",
		"formation": { "units": units, "alive_cap": int(form.alive_cap), "group": int(form.group), "interval": float(form.interval), "type_caps": {} },
		"xp_map": { "wolf": float(config.reward.base_fight_xp) / float(form.total) }, "objective": "clear", "first_fight": true }
	return CombatState.new(o)

func _init(o: Dictionary) -> void:
	opts = o
	stats = _new_stats()
	metrics = _new_metrics()
	build = o.build
	seed_value = int(o.get("seed", 1))
	rng = PRng.new(seed_value)
	var C := PCatalog.config()
	var ff: bool = bool(o.get("first_fight", false))
	if o.has("cfg"):
		cfg = o.cfg
	else:
		cfg = _make_cfg(C)
	if o.has("cfg_overrides"):
		_apply_overrides(cfg, o.cfg_overrides)
	arena_w = float(cfg.arena.w)
	arena_h = float(cfg.arena.h)
	arena_id = String(o.get("arena", "clearing"))
	var arena_def: Dictionary = PCatalog.arenas().get(arena_id, {}) if not ff else {}
	var obs: Array = o.obstacles if o.has("obstacles") else arena_def.get("obstacles", [])
	for ob in obs:
		obstacles.append({ "id": String(ob.id), "type": String(ob.type), "x": float(ob.x), "y": float(ob.y), "r": float(ob.r) })
	objective = String(o.get("objective", "clear"))
	region_id = String(o.get("region_id", ""))
	if o.has("hp_mult"):
		for k in o.hp_mult:
			hp_mult[k] = float(o.hp_mult[k])
	time_limit = float(o.get("time_limit", 0.0))
	fixed_build = bool(o.get("fixed_build", false))
	overlap_limit = int(o.get("overlap_limit", 0))
	risk = String(o.get("risk", ""))
	mission = o.get("mission", {})
	chest_enabled = bool(o.get("chest", false))
	xp_map = o.get("xp_map", {})
	xp_default_scale = float(o.get("xp_default_scale", 1.0))
	var P: Dictionary = cfg.player
	var ps: Dictionary = arena_def.get("playerStart", { "x": arena_w / 2.0, "y": arena_h / 2.0 }) if not ff else P.start
	if P.has("start"):
		ps = P.start
	var hp_max: float = float(build.hp_max)
	player = {
		"x": float(ps.x), "y": float(ps.y), "r": float(P.r), "hp": minf(float(o.get("hp", hp_max)), hp_max), "hp_max": hp_max,
		"shield": float(build.shield), "shield_max": float(build.shield), "ward_shield": 0.0,
		"face": 0.0, "moving": false, "walk_t": 0.0,
		"dodge_active": false, "dodge_t": 0.0, "dodge_dx": 0.0, "dodge_dy": 0.0, "dodge_cd": 0.0,
		"dodge_dist": 0.0, "dodge_released": false, "dodge_end": "", "ember_idx": -1,
		"hit_prot": 0.0, "zone_tick": 0.0, "swing_t": 9.0, "swing_form": "arc", "swing_angle": 0.0,
		"special_cd": 0.0, "e_cd": 0.0, "dead": false, "flash": 0.0, "hurt_t": 9.0,
	}
	weapons = PWeapons.init(self)
	PSkills.init(self)
	# 편성(밀도 모델). 목표 전투는 PObjectives가 웨이브를 정하고 여기서 편성으로 바꾼다
	if o.has("formation"):
		set_formation(o.formation)
	elif o.has("waves"):
		set_formation(PFormation.from_waves(o.waves, o.get("density", {}), region_id, self))
	else:
		set_formation({ "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} })
	spawn_timer = float(cfg.spawn.first_delay)
	if bool(o.get("boss", false)):
		mode = "boss"
		objective = "boss"
		spawned_all = true
		var bs: Dictionary = arena_def.get("bossStart", { "x": arena_w / 2.0, "y": 120.0 })
		boss_id = String(o.get("boss_id", "boss"))
		var bz := PBoss.spawn(self, float(bs.x), float(bs.y), boss_id)
		if o.has("boss_hp") and float(o.boss_hp) > 0.0:
			bz.hp = float(o.boss_hp)
			bz.hp_max = float(o.boss_hp)
		intro = float(PBoss.cfg_of(bz).intro)
	elif PObjectives.is_objective(objective):
		PObjectives.setup(self, o)

## 일반 전투용 호환 설정: player(회피·감속장 포함)·enemies·constants·spawn
static func _make_cfg(C: Dictionary) -> Dictionary:
	var P: Dictionary = C.PLAYER
	var D := PCatalog.density()
	var wolf: Dictionary = PCatalog.enemies().wolf
	return {
		"arena": C.ARENA.duplicate(),
		"player": { "hp": float(P.hp), "speed": float(P.speed), "r": float(P.r), "hit_protect": float(P.hitProtect), "zone_tick": float(P.zoneTick), "dodge": P.dodge.duplicate(true),
			"slowfield": { "radius": float(P.special.radius), "duration": float(P.special.duration), "cooldown": float(P.special.cooldown), "slow": float(P.special.slow) }, "exposed_mult": float(P.exposedMult) },
		"enemies": PCatalog.enemies().duplicate(true),
		"constants": { "spawn_warn": float(C.SPAWN_WARN), "separation": float(C.SEPARATION), "exposed_mult": float(P.exposedMult), "death_linger": 0.9, "wave_delay": float(C.WAVE_DELAY) },
		"spawn": { "first_delay": float(D.first_delay), "warn": float(D.warn), "min_player_dist": float(D.min_player_dist), "group_spread": float(D.group_spread), "entry_points": D.entry_points },
		"chest": C.CHEST, "ember": C.EMBER, "frost": C.FROST, "stasis": C.STASIS, "flare": C.FLARE, "saving": C.SAVING,
		"wolf_dash_max": int(wolf.dash.max_concurrent),
	}

static func _apply_overrides(base: Dictionary, ov: Dictionary) -> void:
	for k in ov:
		if base.has(k) and typeof(base[k]) == TYPE_DICTIONARY and typeof(ov[k]) == TYPE_DICTIONARY:
			_apply_overrides(base[k], ov[k])
		else:
			base[k] = ov[k]

func set_formation(f: Dictionary) -> void:
	formation = f
	spawn_total = (f.units as Array).size()
	spawn_count = 0
	spawned_all = spawn_total == 0 and mode == "boss"
	if xp_map.is_empty() and f.has("xp_map"):
		xp_map = f.xp_map
	if f.has("xp_default_scale"):
		xp_default_scale = float(f.xp_default_scale)

# ---------- 도우미 ----------
func fx(e: Dictionary) -> void:
	e["t"] = 0.0
	effects.append(e)

func _fx(e: Dictionary) -> void:
	fx(e)

## 이벤트 이름은 항상 문자열로 남긴다(소리·테스트). 부가 데이터는 events_data에 따로
var events_data: Array = []
func ev(name: String, data: Dictionary = {}) -> void:
	events.append(name)
	if not data.is_empty():
		var d := data.duplicate()
		d.name = name
		events_data.append(d)

func _ev(name: String) -> void:
	ev(name)

func text(x: float, y: float, txt: String, color: String = "#ffffff") -> void:
	fx({ "kind": "text", "x": x, "y": y, "ttl": 0.8, "text": txt, "color": color })

func alive_enemies() -> Array:
	var out := []
	for e in enemies:
		if not e.dead:
			out.append(e)
	return out

## 직접·투사체 대상(지하 hidden 제외, 구조물 포함)
func alive_targets() -> Array:
	var out := []
	for e in enemies:
		if not e.dead and not bool(e.get("hidden", false)):
			out.append(e)
	return out

func alive_units() -> int:
	var n := 0
	for e in enemies:
		if not e.dead and not bool(e.get("structure", false)):
			n += 1
	return n

func metrics_for(e: Dictionary) -> Dictionary:
	var k: String = String(e.type) + (":summoned" if bool(e.get("summoned", false)) else "")
	return _metrics_for(k)

func _metrics_for(type: String) -> Dictionary:
	if not metrics.enemies.has(type):
		metrics.enemies[type] = { "spawned": 0, "killed": 0, "exploded": 0, "prepared": 0, "executed": 0, "died_before_attack": 0, "died_before_execute": 0, "bites_prepared": 0, "bites_executed": 0, "bite_hits": 0, "dashes_prepared": 0, "dashes_executed": 0, "dash_hits": 0, "ttk": [], "ttk_from_hit": [], "death_effects": 0 }
	return metrics.enemies[type]

## 공격 준비(예고 시작)·실행(피해 판정 발생)·사망 효과를 구분해 센다
func note_attack(e: Dictionary, phase: String) -> void:
	var m := metrics_for(e)
	if phase == "prepare":
		m.prepared += 1
		e.prepared = true
		e.acted = true
		attack_log.append([snapped(t, 0.0001), e.id, String(e.state)])
	elif phase == "execute":
		m.executed += 1
		e.executed = int(e.get("executed", 0)) + 1
	elif phase == "death":
		m.death_effects += 1

# ---------- 시간(감속) ----------
func in_field_xy(ox: float, oy: float, orad: float) -> bool:
	if not field.is_empty() and PGeom.dist(field.x, field.y, ox, oy) <= field.r + orad:
		return true
	return PSkills.in_field2(self, ox, oy, orad)

func in_field(o: Dictionary) -> bool:
	return in_field_xy(float(o.x), float(o.y), float(o.get("r", 0.0)))

func in_slow_echo(ox: float, oy: float, orad: float) -> bool:
	for z in zones:
		if z.type == "slowecho" and PGeom.dist(z.x, z.y, ox, oy) <= z.r + orad:
			return true
	return false

## 감속장 안 0.4 / 잔향 0.7 / 그 외 1 (첫 전투 호환: time_factor(x, y, r))
func time_factor(ox, oy = null, orad: float = 0.0) -> float:
	if typeof(ox) == TYPE_DICTIONARY:
		return time_factor(float(ox.x), float(ox.y), float(ox.get("r", 0.0)))
	if in_field_xy(float(ox), float(oy), orad):
		return float(cfg.player.slowfield.slow)
	if in_slow_echo(float(ox), float(oy), orad):
		return 0.7
	return 1.0

## 이동 속도: 냉기 0.6, 감속장 0.4, 둘 다면 더 강한 쪽(곱하지 않는다)
func enemy_speed_mult(e: Dictionary) -> float:
	var tf := time_factor(e)
	return minf(tf, float(cfg.frost.slow) if float(e.get("chill", 0.0)) > 0.0 else 1.0) if cfg.has("frost") else tf

# ---------- 지형 ----------
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

func nearest_valid_pos(x: float, y: float, r: float, max_r: float = 260.0) -> Array:
	if valid_pos(x, y, r):
		return [x, y]
	var rad := 12.0
	while rad <= max_r:
		for i in 16:
			var a := float(i) / 16.0 * TAU
			var px := x + cos(a) * rad
			var py := y + sin(a) * rad
			if valid_pos(px, py, r):
				return [px, py]
		rad += 12.0
	return []

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

## 직선 빔이 장애물에 막히는 길이
func beam_length(fx0: float, fy0: float, ang: float, L: float) -> float:
	var ex := fx0 + cos(ang) * L
	var ey := fy0 + sin(ang) * L
	var best := L
	for ob in obstacles:
		var tt := PGeom.seg_circle_t(fx0, fy0, ex, ey, ob.x, ob.y, ob.r)
		if tt >= 0.0:
			best = minf(best, tt * L)
	return best

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
	if int(e.steer_side) == 0 or float(e.steer_t) <= 0.0:
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

## 장애물을 돌아 접근한다
func approach(e: Dictionary, tx: float, ty: float, speed: float, dt: float) -> void:
	if float(e.steer_t) > 0.0:
		e.steer_t = float(e.steer_t) - dt
	var n: Array
	if obstacles.is_empty():
		n = PGeom.norm(tx - e.x, ty - e.y)
	else:
		n = steer_dir(e, tx, ty)
	move_swept(e, n[0] * speed * dt, n[1] * speed * dt, true)

# ---------- 소환(밀도 모델: 전체 수·동시 생존 상한·묶음·보충 간격·역할별 상한) ----------
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

## 묶음을 한 진입 지점 주변에 예약(예고 뒤 등장). 플레이어 바로 위·장애물 안에는 두지 않는다. types = 이 묶음의 종류 목록
func queue_group_units(types: Array) -> void:
	var base := pick_entry_point()
	var spread: float = float(cfg.spawn.group_spread)
	var min_pd: float = float(cfg.spawn.min_player_dist)
	for type in types:
		var er: float = float(PCatalog.enemy(String(type)).r) if not cfg.enemies.has(type) else float(cfg.enemies[type].r)
		var px: float = base[0] + rng.range_f(-spread, spread)
		var py: float = base[1] + rng.range_f(-spread, spread)
		px = clampf(px, er + 4.0, arena_w - er - 4.0)
		py = clampf(py, er + 4.0, arena_h - er - 4.0)
		var vp := nearest_valid_pos(px, py, er)
		if not vp.is_empty():
			px = vp[0]
			py = vp[1]
		var dp := PGeom.dist(px, py, player.x, player.y)
		if dp < min_pd * 0.5:
			var away := PGeom.norm(px - player.x, py - player.y) if dp > 1e-6 else [1.0, 0.0]
			px = clampf(player.x + away[0] * min_pd * 0.5, er + 4.0, arena_w - er - 4.0)
			py = clampf(player.y + away[1] * min_pd * 0.5, er + 4.0, arena_h - er - 4.0)
			vp = nearest_valid_pos(px, py, er)
			if not vp.is_empty():
				px = vp[0]
				py = vp[1]
		pending.append({ "type": String(type), "x": px, "y": py, "t": float(cfg.spawn.warn) })
		fx({ "kind": "spawnwarn", "x": px, "y": py, "ttl": float(cfg.spawn.warn), "type": String(type) })
	ev("group")

func queue_group(type: String, n: int) -> void:
	var list := []
	for i in n:
		list.append(type)
	queue_group_units(list)

## HTML식 가장자리 등장(지원병·보스 소환 외 즉시 예약). 플레이어 160 밖·유효 위치
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
		for i in int(g.n):
			var er := float(PCatalog.enemy(String(g.type)).r)
			var p := edge_pos()
			var tries := 0
			while (PGeom.dist(p[0], p[1], player.x, player.y) < 160.0 or not valid_pos(p[0], p[1], er)) and tries < 12:
				p = edge_pos()
				tries += 1
			var vp := nearest_valid_pos(p[0], p[1], er)
			if not vp.is_empty():
				p = vp
			pending.append({ "type": String(g.type), "x": p[0], "y": p[1], "t": float(cfg.constants.spawn_warn) })
			fx({ "kind": "spawnwarn", "x": p[0], "y": p[1], "ttl": float(cfg.constants.spawn_warn), "type": String(g.type) })
	ev("wave")

func alive_count_of(type: String) -> int:
	var n := 0
	for e in enemies:
		if not e.dead and String(e.type) == type:
			n += 1
	for sp in pending:
		if String(sp.type) == type:
			n += 1
	return n

## 등장 대기 진행 + 보충. 동시 생존 상한(살아 있는 + 대기)을 넘겨 예약하지 않고, 묶음 사이에 최소 간격을 둔다. 종류별 상한은 순서를 지키며 건너뛴다
func update_spawner(dt: float) -> void:
	for sp in pending:
		sp.t -= dt
		if sp.t <= 0.0:
			var e := spawn_enemy(String(sp.type), float(sp.x), float(sp.y))
			if bool(sp.get("summoned", false)):
				e.summoned = true
				e.grace = float(PCatalog.boss_defs().boss.overlap.summonGrace)
	var keep := []
	for sp in pending:
		if sp.t > 0.0:
			keep.append(sp)
	pending = keep
	if mode == "boss":
		return
	spawned_all = spawn_count >= spawn_total and pending.is_empty()
	if spawn_hold or spawn_count >= spawn_total:
		return
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	var room: int = int(formation.alive_cap) - alive_units() - pending.size()
	if room <= 0:
		return
	var units: Array = formation.units
	var caps: Dictionary = formation.get("type_caps", {})
	var picked := []
	var counts := {}
	var i := spawn_count
	while i < units.size() and picked.size() < mini(int(formation.group), room):
		var tp := String(units[i])
		var cap: int = int(caps.get(tp, 9999))
		if alive_count_of(tp) + int(counts.get(tp, 0)) >= cap:
			i += 1
			continue
		picked.append(tp)
		counts[tp] = int(counts.get(tp, 0)) + 1
		units.remove_at(i)
		units.insert(spawn_count + picked.size() - 1, tp) # 뽑은 순서대로 앞으로 당겨 순서를 보존
		i = spawn_count + picked.size()
	if picked.is_empty():
		spawn_timer = 0.2
		return
	queue_group_units(picked)
	spawn_count += picked.size()
	spawn_timer = float(formation.interval)
	if chest_enabled and not chest_spawned and spawn_count > int(formation.group):
		chest_spawned = true
		var pos := edge_pos()
		chest = { "x": pos[0], "y": pos[1], "r": float(cfg.chest.r), "opened": false, "t": 0.0 }

func spawn_enemy(type: String, x: float, y: float) -> Dictionary:
	var d: Dictionary = cfg.enemies[type] if cfg.enemies.has(type) else PCatalog.enemy(type)
	var e := {
		"id": _next_id, "type": type, "def": d, "name": String(d.name), "x": x, "y": y, "r": float(d.r), "hp": float(d.hp), "hp_max": float(d.get("hpMax", d.hp)),
		"spawn_t": t, "first_hit_t": -1.0, "acted": false, "prepared": false, "executed": 0, "state": "approach", "state_t": 0.0, "dir": 0.0, "aim_angle": 0.0,
		"chill": 0.0, "burn": {}, "bleed": {}, "stasis": 0, "conduct": 0.0, "flash": 0.0, "dead": false, "death_t": 0.0,
		"vx": 0.0, "vy": 0.0, "hit_by": false, "steer_side": 0, "steer_t": 0.0, "face_x": 1.0, "last_x": x, "last_y": y, "bite_t": 9.0, "move_t": 0.0, "anim_t": 0.0,
		"elite": bool(d.get("elite", false)), "boss": bool(d.get("boss", false)), "structure": bool(d.get("structure", false)), "hidden": false, "airborne": false,
		"summoned": false, "grace": 0.0, "ready_t": -1.0, "recover_dur": 0.0, "blocked_t": 0.0, "resonance": {}, "resonance_t": -999.0, "brand": 0, "leash": 0.0, "leash_boost": 1.0,
	}
	if PEnemies.is_wolf(d):
		# 늑대·우두머리(0.3.1 규칙): 생성 시 시드로 1회 정한 초기 편차. dash_ready_at은 시뮬레이션 시간(배율 없음), 재사용 대기(cd)는 적 시간 배율을 따른다
		e.dash_ready_at = t + rng.range_f(float(d.dash.first_delay[0]), float(d.dash.first_delay[1]))
		e.dash_cd = 0.0
		e.bite_cd = rng.range_f(float(d.bite.initial_delay[0]), float(d.bite.initial_delay[1]))
		e.last_dash_end = -1.0
		e.dash_granted = false
		e.bite_hit_done = false
		e.bites = 0
		e.dashes = 0
		e.dash_left = int(d.dash.get("dashes", 1))
	var cls := "boss" if e.boss else ("elite" if e.elite else "normal")
	var mult: float = float(hp_mult.get(cls, 1.0))
	e.hp = e.hp * mult
	e.hp_max = e.hp_max * mult
	e.hp_class = cls
	_next_id += 1
	enemies.append(e)
	metrics_for(e).spawned += 1
	return e

## 남은 적 수(살아 있는 + 등장 대기 + 아직 예약하지 않은 수)
func remaining() -> Dictionary:
	var alive_n := alive_units()
	var queued: int = maxi(0, spawn_total - spawn_count)
	return { "total": alive_n + pending.size() + queued, "alive": alive_n, "pending": pending.size(), "queued": queued, "cap": int(formation.get("alive_cap", 0)), "spawn_total": spawn_total, "spawned": spawn_count - pending.size() }

## 정예 수: 남은 예약 + 대기 + 생존 + 처치 누적
func elite_count() -> Dictionary:
	var killed: int = int(stats.elite_kills)
	var total := killed
	for e in enemies:
		if e.elite and not e.structure and not e.dead:
			total += 1
	for sp in pending:
		if bool(PCatalog.enemy(String(sp.type)).get("elite", false)):
			total += 1
	var units: Array = formation.get("units", [])
	for i in range(spawn_count, units.size()):
		if bool(PCatalog.enemy(String(units[i])).get("elite", false)):
			total += 1
	return { "total": total, "killed": killed }

## 첫 전투 호환: 마리당 경험치
func xp_per_kill() -> float:
	if xp_map.has("wolf"):
		return float(xp_map.wolf)
	return 0.0

func xp_for(e: Dictionary) -> float:
	if bool(e.get("structure", false)) or bool(e.get("boss", false)):
		return 0.0
	var km: float = float(opts.get("xp_kill_mult", 0.3))
	if bool(e.get("summoned", false)):
		return PGrowth.xp_value_unit(String(e.type), true, region_id, km)
	if xp_map.has(e.type):
		return float(xp_map[e.type])
	return PGrowth.xp_value_unit(String(e.type), false, region_id, km) * xp_default_scale

# ---------- 플레이어 피해 ----------
func check_low_shield_start() -> void:
	var p := player
	var EQ: Dictionary = build.equip
	if EQ.has("lowShield") and not low_shield_used and intro <= 0.0 and p.hp > 0.0 and p.hp <= p.hp_max * float(EQ.lowShield.frac):
		low_shield_used = true
		p.shield += float(EQ.lowShield.shield)
		p.shield_max = maxf(p.shield_max, p.shield)
		stats.equip_procs.emergency_shield = 1

## attacker: 피해를 준 적(있을 때). 시간의 방패 판정에만 쓴다. 유효 피해(타격 직전 체력 상한)와 명목 피해를 분리해 집계한다(0.3.1 규칙)
func damage_player(amount: float, src: String, attacker = null) -> bool:
	var p := player
	if p.dead or status != "running" or intro > 0.0:
		return false
	if not boss.is_empty() and bool(boss.dead):
		return false
	if p.dodge_active:
		stats.perfect_dodges += 1
		text(p.x, p.y - 30.0, "회피!", "#7ef2ff")
		ev("perfect")
		return false
	if p.hit_prot > 0.0:
		return false
	apply_player_damage(amount, src, attacker)
	p.hit_prot = float(cfg.player.hit_protect)
	return true

func apply_player_damage(amount: float, src: String, attacker = null) -> void:
	if not obj.is_empty():
		PObjectives.on_player_hit(self)
	var p := player
	var EQ: Dictionary = build.equip
	var direct_hit := src != "zone"
	var nominal := amount
	if direct_hit and float(build.toughness) > 0.0:
		amount = round(amount * (1.0 - float(build.toughness)) * 10.0) / 10.0
	if direct_hit and EQ.has("bigHit") and amount >= p.hp_max * float(EQ.bigHit.frac):
		amount = round(amount * (1.0 - float(EQ.bigHit.reduce)) * 10.0) / 10.0
		stats.equip_procs.iron_shield = int(stats.equip_procs.get("iron_shield", 0)) + 1
	if direct_hit and EQ.has("fieldTaken") and attacker != null and in_field(attacker):
		amount = round(amount * (1.0 - float(EQ.fieldTaken)) * 10.0) / 10.0
		stats.equip_procs.time_shield = int(stats.equip_procs.get("time_shield", 0)) + 1
	var rest := amount
	if p.shield > 0.0:
		var used := minf(p.shield, rest)
		p.shield -= used
		rest -= used
		if not caster_shield.is_empty():
			caster_shield.amt = maxf(0.0, float(caster_shield.amt) - used)
		PSkills.on_shield_damaged(self, used)
		metrics.absorbed += used
		stats.absorbed += used
	var effective: float = minf(rest, maxf(0.0, p.hp))
	if rest > 0.0:
		p.hp -= effective
		stats.damage_taken += effective
	stats.damage_taken_nominal += nominal
	metrics.taken[src] = float(metrics.taken.get(src, 0.0)) + effective
	metrics.taken_hits[src] = int(metrics.taken_hits.get(src, 0)) + 1
	p.flash = 0.2
	p.hurt_t = 0.0
	if EQ.has("lowShield") and not low_shield_used and p.hp > 0.0 and p.hp <= p.hp_max * float(EQ.lowShield.frac):
		low_shield_used = true
		p.shield += float(EQ.lowShield.shield)
		p.shield_max = maxf(p.shield_max, p.shield)
		stats.equip_procs.emergency_shield = 1
		text(p.x, p.y - 44.0, "비상 방패!", "#9fd8ff")
	fx({ "kind": "hitflash", "x": p.x, "y": p.y, "ttl": 0.25 })
	if src != "zone" or amount > 0.0:
		text(p.x, p.y - 28.0, "-" + str(int(round(amount))), "#ff6b6b")
	ev("hurt", { "src": src })
	if p.hp <= 0.0:
		p.hp = 0.0
		p.dead = true
		pending_loss = true
		if not _in_step: # 단계 밖(테스트·도구)에서 받은 치명 피해는 즉시 확정. 단계 안에서는 끝에서 승리 우선 판정
			status = "lost"
			ev("lose")

func zone_damage(amount: float) -> void:
	var p := player
	if p.dead or p.dodge_active or intro > 0.0 or (not boss.is_empty() and bool(boss.dead)):
		return
	apply_player_damage(amount, "zone")

## 넉백(0.3.1 배율 ×2 유지 — HTML ×4와 다름, PORT_BASELINE C21). 돌진·도약·돌파·지하 중 무시, 보스·방패병 배율
func knock_enemy(e: Dictionary, n: Array, amount: float) -> void:
	if e.state == "dash" or e.state == "leap":
		return
	if e.boss:
		amount *= float(PBoss.cfg_of(e).knockMult)
	if e.def.has("knockMult"):
		amount *= float(e.def.knockMult)
	if e.state == "charge" or e.state == "under" or e.state == "warn":
		return
	e.vx += n[0] * amount * 2.0
	e.vy += n[1] * amount * 2.0

func src_key(opt: Dictionary) -> String:
	var sr: Dictionary = opt.get("src", {})
	if opt.has("tag"):
		return String(opt.tag)
	if sr.has("tag"):
		return String(sr.tag)
	if opt.has("dot"):
		return "dot:" + String(opt.dot) + "@" + String(opt.get("dot_src", "common"))
	if bool(sr.get("skill", false)):
		return "skill:" + String(sr.get("skill_id", "e"))
	if sr.has("weapon_id"):
		return "weapon:" + String(sr.weapon_id)
	return "other"

## 적 피해. opt = {src{...}, dir[x,y], knock, from{x,y}, bleed, chill, dot, ground, no_conduct, tag} 또는 문자열 src_key(첫 전투 호환). 유효 피해(과잉 제외)를 출처별로 집계
func damage_enemy(e: Dictionary, amount: float, opt = {}, knock_c: float = 0.0, dir_c: Array = []) -> float:
	if e.dead:
		return 0.0
	var o: Dictionary
	if typeof(opt) == TYPE_STRING:
		o = { "src": { "tag": String(opt), "direct": true }, "knock": knock_c, "dir": dir_c }
	else:
		o = opt
	var sr: Dictionary = o.get("src", { "direct": true })
	var direct: bool = bool(sr.get("direct", true)) and not bool(sr.get("extra", false)) and not bool(sr.get("skill", false))
	var dmg := amount
	var crit: bool = e.state == "recover" or e.state == "stagger"
	if crit:
		dmg *= float(build.exposed_mult)
	var EQ: Dictionary = build.equip
	if direct and EQ.has("eliteDirect") and (e.elite or e.boss):
		dmg *= 1.0 + float(EQ.eliteDirect)
	if direct and EQ.has("fieldDirect") and in_field(e):
		dmg *= 1.0 + float(EQ.fieldDirect)
	var sm := PEnemies.shield_mult(self, e, o)
	if sm != 1.0:
		dmg *= sm
		e.blocked_t = 0.2
	dmg = round(dmg * 10.0) / 10.0
	var effective: float = minf(dmg, maxf(0.0, e.hp))
	if e.boss:
		stats.boss_damage += effective
	var k := src_key(o)
	metrics.dmg[k] = float(metrics.dmg.get(k, 0.0)) + effective
	if float(e.first_hit_t) < 0.0:
		e.first_hit_t = t
	e.hp -= dmg
	e.flash = 0.12
	if e.boss and e.hp > 0.0:
		PBoss.check_phase(self, e)
	var knock: float = float(o.get("knock", 0.0))
	var dir: Array = o.get("dir", [])
	if knock > 0.0 and not dir.is_empty():
		knock_enemy(e, dir, knock)
	PEnemies.on_damaged(self, e, dmg, o)
	var dm := float(build.duration_mult)
	if direct:
		if PBuild.has_common(build, "frost"):
			e.chill = maxf(float(e.chill), float(cfg.frost.chill) * dm)
		if PBuild.has_common(build, "burn"):
			var BV: Dictionary = PCatalog.growth().COMMON_VALUES.burn
			var dd := 1.0 + float(EQ.get("dotDur", 0.0))
			if e.burn.is_empty() or float(e.burn.dps) <= float(BV.dps):
				var prev_t: float = float(e.burn.t) if not e.burn.is_empty() else 0.0
				e.burn = { "t": maxf(prev_t, float(BV.dur) * dm * dd), "dps": float(BV.dps), "tick": float(e.burn.get("tick", 0.0)) if not e.burn.is_empty() else 0.0, "src": String(sr.get("weapon_id", "common")) }
		if PBuild.has_common(build, "stasis") and in_field(e):
			e.stasis = mini(int(cfg.stasis.maxStacks), int(e.stasis) + 1)
	if o.has("chill"):
		e.chill = maxf(float(e.chill), float(o.chill) * dm)
	if o.has("bleed") and sr.has("weapon"):
		var dps := float(sr.weapon.damage) * 0.3
		var dd2 := 1.0 + float(EQ.get("dotDur", 0.0))
		if e.bleed.is_empty() or float(e.bleed.dps) <= dps:
			var prev_b: float = float(e.bleed.t) if not e.bleed.is_empty() else 0.0
			e.bleed = { "t": maxf(prev_b, float(o.bleed) * dd2), "dps": dps, "tick": float(e.bleed.get("tick", 0.0)) if not e.bleed.is_empty() else 0.0, "src": String(sr.get("weapon_id", "weapon")) }
	PWeapons.on_hit(self, e, o, dmg)
	fx({ "kind": "spark", "x": e.x, "y": e.y, "ttl": 0.22, "crit": crit, "angle": (atan2(dir[1], dir[0]) if not dir.is_empty() else 0.0) })
	fx({ "kind": "text", "x": e.x + rng.range_f(-8.0, 8.0), "y": e.y - e.r - 6.0, "ttl": 0.8, "text": str(int(round(dmg))), "color": "#ffd166" if crit else "#ffffff" })
	ev("hit", { "crit": crit })
	if e.hp <= 0.0:
		kill_enemy(e, o)
	return dmg

func _kill_enemy(e: Dictionary) -> void:
	kill_enemy(e, {})

func kill_enemy(e: Dictionary, o: Dictionary) -> void:
	e.dead = true
	e.death_t = 0.0
	if not e.structure:
		stats.kills += 1
	if e.elite and not e.structure:
		stats.elite_kills += 1
	var m := metrics_for(e)
	m.killed += 1
	if not e.acted:
		m.died_before_attack += 1
	if int(e.get("executed", 0)) == 0 and int(e.get("bites", 0)) + int(e.get("dashes", 0)) == 0:
		m.died_before_execute += 1
	m.ttk.append(snapped(t - float(e.spawn_t), 0.01))
	if float(e.first_hit_t) >= 0.0:
		m.ttk_from_hit.append(snapped(t - float(e.first_hit_t), 0.01))
	ev("kill", { "type": String(e.type) })
	# 경험치: 처치 원인과 무관하게 즉시, 같은 적은 1회
	var xp := xp_for(e)
	if xp > 0.0:
		stats.xp += xp
		xp_gained += xp
		if build.has("growth") and not fixed_build:
			var gained := PGrowth.add_xp(build.growth, xp)
			if gained > 0:
				level_ups += gained
				stats.level_ups += gained
				ev("levelup", { "n": gained })
				text(player.x, player.y - 62.0, "레벨 업!", "#ffe066")
	if e.boss:
		e.state = "dead"
		e.airborne = false
		boss_down_t = 0.0
		ev("boss_down")
	if not e.structure and PBuild.has_common(build, "saving") and in_field(e) and player.special_cd > 0.0:
		player.special_cd = maxf(0.0, player.special_cd - float(cfg.saving.cdPerKill))
		stats.saving_kills += 1
		text(e.x, e.y - e.r - 22.0, "감속장 -%d초" % int(cfg.saving.cdPerKill), "#a9d8ff")
		ev("saving")
	fx({ "kind": "death", "x": e.x, "y": e.y, "r": e.r, "ttl": 0.4, "color": String(e.def.get("color", "#9aa0a8")) })
	if e.type == "spore":
		add_zone("spore", e.x, e.y, float(e.def.deathCloudR), float(e.def.deathCloudTtl), float(e.def.cloudDamage))
		note_attack(e, "death")
	if PBuild.has_common(build, "frost") and float(e.chill) > 0.0:
		var F: Dictionary = cfg.frost
		for i in int(F.shards):
			var a := float(i) / float(F.shards) * TAU
			projectiles.append({ "owner": "player", "kind": "shard_common", "x": e.x, "y": e.y, "vx": cos(a) * float(F.shardSpeed), "vy": sin(a) * float(F.shardSpeed), "r": 4.0, "dmg": float(F.shardDamage) * float(build.mastery_mult), "ttl": float(F.shardTtl), "hits": { e.id: true }, "tag": "common:frost", "dead": false, "weapon": null })
		text(e.x, e.y - 20.0, "파편!", "#bfefff")
		ev("shatter")
	if PBuild.has_common(build, "flare"):
		var on_fire := false
		for z in zones:
			if z.type == "fire" and PGeom.dist(z.x, z.y, e.x, e.y) <= z.r + e.r:
				on_fire = true
				break
		if on_fire:
			var F2: Dictionary = cfg.flare
			fx({ "kind": "flare", "x": e.x, "y": e.y, "r": float(F2.radius), "ttl": 0.35 })
			for oth in enemies:
				if not oth.dead and oth != e and PGeom.dist(oth.x, oth.y, e.x, e.y) <= float(F2.radius) + oth.r:
					damage_enemy(oth, float(F2.damage) * float(build.mastery_mult), { "dir": PGeom.norm(oth.x - e.x, oth.y - e.y), "knock": 40.0, "src": { "extra": true, "direct": false, "tag": "common:flare" } })
			text(e.x, e.y - 34.0, "불꽃 파열!", "#ff9f43")
			ev("explode")
	PWeapons.on_kill(self, e, o)
	if mark_target != null and mark_target == e:
		mark_target = null

func add_zone(type: String, x: float, y: float, r: float, ttl: float, dmg: float) -> Dictionary:
	var z := { "type": type, "x": x, "y": y, "r": r, "ttl": ttl, "max_ttl": ttl, "dmg": dmg, "tick": 0.0, "t": 0.0 }
	zones.append(z)
	return z

## 잔불: 장애물 안쪽이면 그 조각은 생략
func add_fire_at(x: float, y: float) -> bool:
	var E: Dictionary = cfg.ember
	if not valid_pos(x, y, 0.0):
		return false
	add_zone("fire", x, y, float(E.radius) * float(build.width_mult), float(E.ttl) * float(build.duration_mult), float(E.damage))
	return true

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
		p.walk_t += dt
		p.face = atan2(mv[1], mv[0])
	# 회피(docs/RULES.md §회피): 누르는 순간 즉시 출발, 방향 고정, 재사용 대기는 시작 순간부터
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
		p.dodge_cd = float(D.cooldown) * float(build.dodge_cd_mult)
		p.ember_idx = -1
		if PBuild.has_common(build, "ember"):
			p.ember_idx = 0
			add_fire_at(p.x, p.y)
		stats.dodges += 1
		ev("dodge")
	if p.dodge_cd > 0.0:
		p.dodge_cd = maxf(0.0, p.dodge_cd - dt)
		if p.dodge_cd < 1e-6:
			p.dodge_cd = 0.0
	if p.dodge_active:
		if not bool(input.get("dodge_held", false)):
			p.dodge_released = true
		var spd := float(D.distance) / float(D.duration)
		var target := float(D.distance)
		if String(D.mode) == "hold" and p.dodge_released:
			target = maxf(float(D.min_distance), p.dodge_dist)
		var remain := maxf(0.0, target - p.dodge_dist)
		var want := minf(spd * dt, remain)
		var x0: float = p.x
		var y0: float = p.y
		var blocked := false
		if want > 0.0:
			var res := move_swept(p, p.dodge_dx * want, p.dodge_dy * want)
			blocked = String(res.hit) != ""
		p.dodge_dist += PGeom.dist(x0, y0, p.x, p.y)
		p.dodge_t += dt
		if PBuild.has_common(build, "ember"):
			var E: Dictionary = cfg.ember
			var frac: float = p.dodge_dist / float(D.distance)
			var idx := int(floor(frac * float(E.count)))
			if idx > int(p.ember_idx) and idx < int(E.count):
				p.ember_idx = idx
				add_fire_at(p.x, p.y)
		if blocked or p.dodge_dist >= target - 1e-6 or p.dodge_t >= float(D.duration) - 1e-9:
			p.dodge_active = false
			p.dodge_end = "blocked" if blocked else ("max" if p.dodge_dist >= float(D.distance) - 1e-6 else "release")
			stats.dodge_dists.append(snapped(p.dodge_dist, 0.1))
	else:
		var wind := 1.0
		var web := 1.0
		for z in zones:
			if z.type == "windpath" and PGeom.dist(z.x, z.y, p.x, p.y) <= z.r:
				wind = 1.4
			elif z.type == "web" and PGeom.dist(z.x, z.y, p.x, p.y) <= z.r + p.r * 0.5:
				web = 0.5
		var spd2 := float(P.speed) * float(build.speed_mult) * wind * web
		move_swept(p, mv[0] * spd2 * dt, mv[1] * spd2 * dt, true)
	if bool(input.get("special", false)) and p.special_cd <= 0.0:
		PSkills.cast_q(self)
	if bool(input.get("skill_e", false)) and p.e_cd <= 0.0 and build.skills.get("e") != null:
		PSkills.cast_e(self)
	push_out(p)
	update_attack(dt)

## 첫 전투 호환 이름
func cast_slowfield() -> void:
	PSkills.cast_q(self)

func update_attack(dt: float) -> void:
	var before := 0
	for w in weapons:
		before += int(w.count)
	PWeapons.update(self, dt)
	var after := 0
	for w in weapons:
		after += int(w.count)
	stats.attacks += after - before

# ---------- 판단 보조(동시 공격 제한) ----------
func is_committed(e: Dictionary) -> bool:
	return e.state in ["crouch", "lock", "dash", "aim", "swell"] or PEnemies.is_committed(e)

func may_attack(e: Dictionary, dt: float) -> bool:
	if overlap_limit <= 0:
		return true
	var n := 0
	for o in enemies:
		if o != e and not o.dead and not o.boss and is_committed(o):
			n += 1
	if n >= overlap_limit:
		e.ready_t = -1.0
		return false
	if float(e.ready_t) < 0.0:
		var d: Array = PCatalog.boss_defs().boss.overlap.wolfDelay
		e.ready_t = rng.range_f(float(d[0]), float(d[1]))
	e.ready_t = float(e.ready_t) - dt
	return float(e.ready_t) <= 0.0

## 보스전 겹침 제한: 늑대 돌진 준비·실행 동시 1, 보스 확정·실행 중 시작 금지, 열리면 개체별 무작위 지연
func wolf_may_attack(e: Dictionary, dt: float) -> bool:
	if mode != "boss":
		return may_attack(e, dt)
	var others := false
	for o in enemies:
		if o != e and not o.dead and not o.boss and (o.state == "crouch" or o.state == "lock" or o.state == "dash"):
			others = true
			break
	var boss_busy: bool = not boss.is_empty() and not bool(boss.dead) and PBoss.boss_committed(boss)
	if others or boss_busy:
		e.ready_t = -1.0
		return false
	if float(e.ready_t) < 0.0:
		var d: Array = PCatalog.boss_defs().boss.overlap.wolfDelay
		e.ready_t = rng.range_f(float(d[0]), float(d[1]))
	e.ready_t = float(e.ready_t) - dt
	return float(e.ready_t) <= 0.0

func dash_states_count() -> int:
	return PEnemies.dash_states_count(self)

func bite_states_count() -> int:
	return PEnemies.bite_states_count(self)

# ---------- 적 갱신 ----------
func update_enemies(dt: float) -> void:
	PEnemies.grant_dash_slots(self)
	for e in enemies:
		if e.dead:
			e.death_t += dt
			continue
		e.anim_t += dt
		e.bite_t += dt
		var mdx: float = e.x - e.last_x
		var mdy: float = e.y - e.last_y
		var mlen := sqrt(mdx * mdx + mdy * mdy)
		if mlen > 0.05:
			e.move_t += mlen / 40.0
			if absf(mdx) > 0.02:
				e.face_x = 1.0 if mdx > 0.0 else -1.0
		e.last_x = e.x
		e.last_y = e.y
		if e.flash > 0.0:
			e.flash -= dt
		if float(e.chill) > 0.0:
			e.chill = float(e.chill) - dt
		if float(e.conduct) > 0.0:
			e.conduct = float(e.conduct) - dt
		if float(e.blocked_t) > 0.0:
			e.blocked_t = float(e.blocked_t) - dt
		for key in ["burn", "bleed"]:
			var d: Dictionary = e[key]
			if not d.is_empty() and float(d.t) > 0.0:
				d.t = float(d.t) - dt
				d.tick = float(d.get("tick", 0.0)) - dt
				if float(d.tick) <= 0.0:
					d.tick = 0.5
					damage_enemy(e, float(d.dps) * 0.5, { "src": { "extra": true, "direct": false }, "dot": key, "dot_src": String(d.get("src", "common")) })
					if e.dead:
						break
			elif not d.is_empty():
				e[key] = {}
		if e.dead:
			continue
		if e.boss:
			PBoss.update(self, e, dt)
		else:
			PEnemies.update(self, e, dt)
		e.dash_granted = false
		if bool(e.get("airborne", false)):
			continue
		if e.vx != 0.0 or e.vy != 0.0:
			move_swept(e, e.vx * dt, e.vy * dt)
			var k := exp(-10.0 * dt)
			e.vx *= k
			e.vy *= k
			if absf(e.vx) < 1.0:
				e.vx = 0.0
			if absf(e.vy) < 1.0:
				e.vy = 0.0
		if not bool(e.get("hidden", false)):
			push_out(e)
	resolve_overlaps(dt)
	var keep := []
	for e in enemies:
		if not e.dead or e.death_t < float(cfg.constants.death_linger) or e.boss:
			keep.append(e)
	enemies = keep
	var al := alive_units()
	if al > stats.max_alive:
		stats.max_alive = al
	var ds := PEnemies.dash_states_count(self)
	if ds > stats.max_dash_states:
		stats.max_dash_states = ds
	var bs := PEnemies.bite_states_count(self)
	if bs > stats.max_bite_states:
		stats.max_bite_states = bs

## 겹침 해소(피해 없음, 0.3.1 규칙): 적끼리 절반씩(단계당 ≤6px), 적-플레이어는 적 70%·플레이어 30%(120/s 상한). 회피 중 통과. 구조물은 밀리지 않고 상대만 민다
func resolve_overlaps(dt: float) -> void:
	var al := alive_enemies()
	for i in al.size():
		for j in range(i + 1, al.size()):
			var A: Dictionary = al[i]
			var Bq: Dictionary = al[j]
			if A.state == "dash" or Bq.state == "dash" or bool(A.airborne) or bool(Bq.airborne) or bool(A.hidden) or bool(Bq.hidden):
				continue
			if A.structure and Bq.structure:
				continue
			var dx: float = Bq.x - A.x
			var dy: float = Bq.y - A.y
			var dd := sqrt(dx * dx + dy * dy)
			var mn: float = A.r + Bq.r
			if dd < mn:
				var n: Array = [dx / dd, dy / dd] if dd > 1e-6 else [cos(float(A.id) * 2.399), sin(float(A.id) * 2.399)]
				var push: float = minf((mn - dd) / 2.0 * float(cfg.constants.separation), 6.0)
				if A.structure:
					Bq.x += n[0] * push * 2.0
					Bq.y += n[1] * push * 2.0
					push_out(Bq)
					continue
				if Bq.structure:
					A.x -= n[0] * push * 2.0
					A.y -= n[1] * push * 2.0
					push_out(A)
					continue
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
		if e.state == "dash" or e.structure or bool(e.airborne) or bool(e.hidden):
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
	var cap: float = 120.0 * dt
	if mag > 1e-9:
		var k := minf(1.0, cap / mag)
		move_swept(p, px_sum * k, py_sum * k, true)
		push_out(p)

# ---------- 투사체 ----------
func update_projectiles(dt: float) -> void:
	var p := player
	for pr in projectiles:
		var tf: float = time_factor(float(pr.x), float(pr.y), float(pr.r)) if pr.owner == "enemy" else 1.0
		if pr.owner == "player" and (pr.get("target") != null or not (pr.get("boomerang", {}) as Dictionary).is_empty()):
			PWeapons.steer_projectile(self, pr, dt)
		if bool(pr.dead):
			continue
		if pr.owner == "player" and pr.get("weapon") != null and not bool(pr.get("cloned", false)) and not bool(pr.get("is_clone", false)) and (build.boss_rewards as Array).has("clone") and in_field(pr):
			pr.cloned = true
			var c: Dictionary = pr.duplicate()
			c.hits = (pr.hits as Dictionary).duplicate()
			c.is_clone = true
			c.cloned = true
			c.x = pr.x - pr.vy * 0.03
			c.y = pr.y + pr.vx * 0.03
			c.boomerang = {}
			projectiles.append(c)
		var nx: float = pr.x + pr.vx * tf * dt
		var ny: float = pr.y + pr.vy * tf * dt
		var obs := sweep_circle(pr.x, pr.y, nx, ny, pr.r)
		var t_obs: float = obs[0] if obs[1] >= 0 else INF
		if pr.owner == "enemy":
			var tp := PGeom.seg_circle_t(pr.x, pr.y, nx, ny, p.x, p.y, p.r + pr.r)
			if tp >= 0.0 and tp <= t_obs:
				pr.dead = true
				damage_player(float(pr.dmg), String(pr.kind), pr.get("shooter"))
		else:
			var cands := []
			for e in enemies:
				if e.dead or bool(e.hidden) or (pr.hits as Dictionary).has(e.id):
					continue
				var tt := PGeom.seg_circle_t(pr.x, pr.y, nx, ny, e.x, e.y, e.r + pr.r)
				if tt >= 0.0:
					cands.append([tt, e])
			cands.sort_custom(func(a, b): return a[0] < b[0])
			for c in cands:
				if c[0] > t_obs:
					break
				if pr.get("weapon") != null or pr.kind == "shard_common":
					if PWeapons.on_projectile_hit(self, pr, c[1]):
						pr.dead = true
						break
				else:
					pr.dead = true
					damage_enemy(c[1], float(pr.dmg), { "dir": PGeom.norm(pr.vx, pr.vy), "knock": 10.0 })
					break
		if not bool(pr.dead) and obs[1] >= 0:
			pr.dead = true
			fx({ "kind": "spark", "x": pr.x + pr.vx * tf * dt * obs[0], "y": pr.y + pr.vy * tf * dt * obs[0], "ttl": 0.15, "angle": atan2(-pr.vy, -pr.vx), "crit": false })
		pr.x = nx
		pr.y = ny
		pr.ttl -= dt
		if pr.x < -10.0 or pr.x > arena_w + 10.0 or pr.y < -10.0 or pr.y > arena_h + 10.0 or pr.ttl <= 0.0:
			pr.dead = true
	var keep := []
	for pr in projectiles:
		if not bool(pr.dead):
			keep.append(pr)
	projectiles = keep

# ---------- 지역·필드 ----------
func update_zones(dt: float) -> void:
	var p := player
	p.zone_tick -= dt
	var max_dmg := 0.0
	for z in zones:
		z.ttl -= dt
		z.t += dt
		if z.type == "spore" and PGeom.dist(z.x, z.y, p.x, p.y) <= z.r + p.r * 0.5:
			max_dmg = maxf(max_dmg, float(z.dmg))
		if z.type == "hazard":
			max_dmg = maxf(max_dmg, PObjectives.zone_damage(self, z, p))
		if z.type == "fire":
			z.tick -= dt
			if z.tick <= 0.0:
				z.tick = float(cfg.ember.tick)
				for e in enemies:
					if not e.dead and PGeom.dist(z.x, z.y, e.x, e.y) <= z.r + e.r:
						if z.get("weapon") != null:
							damage_enemy(e, float(z.dmg), { "src": { "weapon": z.weapon.stats, "weapon_id": z.weapon.id, "direct": false, "extra": true } })
						else:
							damage_enemy(e, float(z.dmg) * float(build.mastery_mult), { "src": { "extra": true, "direct": false, "tag": "common:ember" } })
		if z.type == "coldground":
			z.tick -= dt
			if z.tick <= 0.0:
				z.tick = 0.25
				for e in enemies:
					if not e.dead and PGeom.dist(z.x, z.y, e.x, e.y) <= z.r + e.r:
						e.chill = maxf(float(e.chill), 1.0)
		if z.type == "storm":
			z.tick -= dt
			if z.tick <= 0.0:
				z.tick = 0.5
				fx({ "kind": "strike", "x": z.x + rng.range_f(-20.0, 20.0), "y": z.y + rng.range_f(-20.0, 20.0), "r": 30.0, "ttl": 0.2 })
				for e in enemies:
					if not e.dead and PGeom.dist(z.x, z.y, e.x, e.y) <= z.r + e.r:
						damage_enemy(e, float(z.dmg), { "src": { "skill": true, "direct": false, "skill_id": "strike" } })
	if max_dmg > 0.0 and p.zone_tick <= 0.0:
		p.zone_tick = float(cfg.player.get("zone_tick", 0.5))
		zone_damage(max_dmg)
	if max_dmg == 0.0 and p.zone_tick < 0.0:
		p.zone_tick = 0.0
	for z in zones:
		if z.type == "frostzone" and z.ttl <= 0.0:
			PEnemies.detonate(self, z)
	var keep := []
	for z in zones:
		if z.ttl > 0.0:
			keep.append(z)
	zones = keep
	check_low_shield_start()
	if caster_cd > 0.0:
		caster_cd -= dt
	if not caster_shield.is_empty():
		caster_shield.t = float(caster_shield.t) - dt
		if float(caster_shield.t) <= 0.0:
			player.shield = maxf(0.0, player.shield - float(caster_shield.amt))
			caster_shield = {}
	if not field.is_empty():
		field.ttl -= dt
		if field.ttl <= 0.0:
			end_field()

func update_field(dt: float) -> void:
	pass # update_zones가 처리(첫 전투 호환 이름)

## 감속장 종료: 정지된 칼날 흔적을 터뜨리고 필드를 제거
func end_field() -> void:
	var f := field
	if f.is_empty():
		return
	if PBuild.has_common(build, "stasis"):
		var total := 0.0
		for e in enemies:
			if not e.dead and int(e.stasis) > 0:
				var dmg := float(e.stasis) * float(cfg.stasis.damagePerStack) * float(build.mastery_mult)
				fx({ "kind": "stasisburst", "x": e.x, "y": e.y, "r": 34.0 + float(e.stasis) * 10.0, "ttl": 0.4 })
				e.stasis = 0
				total += damage_enemy(e, dmg, { "src": { "extra": true, "direct": false, "tag": "common:stasis" } })
		if total > 0.0:
			text(f.x, f.y - f.r - 26.0, "정지된 칼날 폭발 %d" % int(round(total)), "#cfeaff")
			ev("explode")
	fx({ "kind": "fieldend", "x": f.x, "y": f.y, "r": f.r, "ttl": 0.35 })
	field = {}
	PSkills.on_field_end(self, f)

func update_pickups(dt: float) -> void:
	var p := player
	for k in pickups:
		k.t += dt
		if not bool(k.taken) and PGeom.dist(k.x, k.y, p.x, p.y) <= k.r + p.r:
			k.taken = true
			var before: float = p.hp
			p.hp = minf(p.hp_max, p.hp + float(k.amount))
			stats.healed += p.hp - before
			text(p.x, p.y - 34.0, "+%d" % int(round(p.hp - before)), "#9cffb0")
			ev("orb")
	var keep := []
	for k in pickups:
		if not bool(k.taken):
			keep.append(k)
	pickups = keep

func update_chest(dt: float) -> void:
	if chest.is_empty():
		return
	var p := player
	if not bool(chest.opened) and PGeom.dist(chest.x, chest.y, p.x, p.y) <= chest.r + p.r:
		chest.opened = true
		chest.t = 0.0
		var g := rng.int_range(int(cfg.chest.gold[0]), int(cfg.chest.gold[1]))
		stats.chest_gold += g
		text(chest.x, chest.y - 24.0, "+%d 금화" % g, "#ffd166")
		ev("chest")
	if bool(chest.opened):
		chest.t += dt

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
	if PObjectives.is_objective(objective):
		if PObjectives.check(self):
			status = "won"
			ev("win")
		return
	if objective == "boss":
		if not boss.is_empty() and bool(boss.dead):
			status = "won"
			ev("win")
	elif (objective == "clear" or objective == "elite") and spawned_all and pending.is_empty() and alive_units() == 0:
		status = "won"
		ev("win")

## 고정 단계 1회. 종료 뒤에는 표시용 효과만 진행한다(전투 시간·재사용 시간은 멈춘다)
func step(input: Dictionary, dt: float) -> void:
	step_n += 1
	if status != "running":
		update_effects(dt)
		for e in enemies:
			if e.dead:
				e.death_t += dt
		if not boss.is_empty() and bool(boss.dead):
			boss_down_t += dt
		return
	if intro > 0.0:
		intro -= dt
		for e in enemies:
			e.anim_t = float(e.get("anim_t", 0.0)) + dt
		update_effects(dt)
		if intro <= 0.0 and not boss.is_empty():
			boss.state = "approach"
			boss.state_t = 0.0
			ev("boss_roar", { "phase": 1 })
		return
	_in_step = true
	t += dt
	stats.elapsed += dt
	for w in build.weapons:
		var k := "weapon:" + String(w.id)
		active_t[k] = float(active_t.get(k, 0.0)) + dt
	active_t["skill:q"] = float(active_t.get("skill:q", 0.0)) + dt
	if build.skills.get("e") != null:
		var ke := "skill:" + String(build.skills.e.id)
		active_t[ke] = float(active_t.get(ke, 0.0)) + dt
	if time_limit > 0.0 and t >= time_limit:
		status = "timeout"
		ev("timeout")
		_in_step = false
		return
	update_player(input, dt)
	PSkills.update(self, dt)
	update_enemies(dt)
	if not obj.is_empty():
		PObjectives.update(self, dt)
	update_projectiles(dt)
	update_zones(dt)
	update_pickups(dt)
	update_chest(dt)
	update_spawner(dt)
	update_effects(dt)
	check_objective()
	if status == "running" and pending_loss:
		status = "lost"
		ev("lose")
	if status == "won":
		pending_loss = false
	_in_step = false

## 레벨업 선택 적용 뒤: 파생 수치 재계산·무기 목록 갱신(타이머 유지)
func rebuild(b: Dictionary) -> void:
	var p := player
	var old_max: float = p.hp_max
	build = b
	p.hp_max = float(b.hp_max)
	if float(b.hp_max) > old_max:
		p.hp = minf(p.hp_max, p.hp + (float(b.hp_max) - old_max))
	PWeapons.refresh(self)

## 결과 요약(정산은 호출자가 1회만 한다: settled 플래그)
func summary() -> Dictionary:
	var total := 0.0
	for k in metrics.dmg:
		total += metrics.dmg[k]
	var dmg := {}
	for k in metrics.dmg:
		dmg[k] = snapped(metrics.dmg[k], 0.1)
	var en := {}
	for k in metrics.enemies:
		var m: Dictionary = metrics.enemies[k]
		var ended: int = int(m.killed) + int(m.exploded)
		var ttk_avg := 0.0
		for v in m.ttk:
			ttk_avg += float(v)
		en[k] = m.duplicate(true)
		en[k].died_before_attack_rate = (snapped(float(m.died_before_attack) / float(ended), 0.001) if ended > 0 else -1.0)
		en[k].ttk_avg = (snapped(ttk_avg / float(m.ttk.size()), 0.01) if m.ttk.size() > 0 else -1.0)
	var out := { "status": status, "elapsed": snapped(t, 0.01), "hp": player.hp, "hp_max": player.hp_max, "kills": stats.kills, "damage_taken": stats.damage_taken, "damage_taken_nominal": stats.damage_taken_nominal, "absorbed": stats.absorbed,
		"attacks": stats.attacks, "hits": stats.hits, "dodges": stats.dodges, "special_uses": stats.special_uses, "e_uses": stats.e_uses, "dmg": dmg, "dmg_total": snapped(total, 0.1), "taken": metrics.taken.duplicate(), "taken_hits": metrics.taken_hits.duplicate(), "enemies": en, "steps": step_n, "seed": seed_value,
		"dodge_mode": String(cfg.player.dodge.mode), "dodge_cooldown": float(cfg.player.dodge.cooldown), "dodge_dists": stats.dodge_dists.duplicate(), "perfect_dodges": stats.perfect_dodges,
		"formation": String(cfg.formation_id) if cfg.has("formation_id") else String(opts.get("formation_name", "?")), "spawn_total": spawn_total, "spawned": spawn_count, "xp": snapped(stats.xp, 0.0001), "level_ups": stats.level_ups,
		"max_alive": stats.max_alive, "max_dash_states": stats.max_dash_states, "max_bite_states": stats.max_bite_states, "dash_max": int(cfg.enemies.wolf.dash.max_concurrent), "wolf_hp": float(cfg.enemies.wolf.hp),
		"boss_damage": snapped(stats.boss_damage, 0.1), "patterns": metrics.patterns.duplicate(), "chest_gold": stats.chest_gold, "healed": stats.healed, "region_id": region_id, "arena": arena_id, "objective": objective, "hp_mult": hp_mult.duplicate(), "time_limit": time_limit, "fixed_build": fixed_build, "interrupts": metrics.interrupts, "heals": metrics.heals, "webs": metrics.webs, "far_frac": metrics.far_frac, "equip_procs": stats.equip_procs.duplicate(), "boss_id": boss_id }
	if build.has("growth") and build.growth != null:
		var g: Dictionary = build.growth
		var wl := []
		for w in g.weapons:
			wl.append("%s:%d%s" % [String(w.id), int(w.level), (":" + "+".join(w.mods)) if (w.mods as Array).size() > 0 else ""])
		out.build = { "level": int(g.level), "weapons": wl, "commons": g.commons.duplicate(), "passives": g.passives.duplicate(), "e": g.skills.get("e"), "q": g.skills.get("q") }
	return out
