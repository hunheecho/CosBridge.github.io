class_name PEnemies
extends RefCounted
## 적 행동 분배: 늑대·늑대 우두머리(godot-0.3.1 규칙, D33/D35 보존) · 궁수·포자(HTML combat.js) · 신규 8종(PEnemiesNew, HTML enemies.js).
## 공통: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음. 감속장은 준비·실행·빈틈 진행(tf)을 늦추고 냉기는 이동만 늦춘다.

## 늑대 계열(0.3.1 규칙) 판별: bite·dash 블록을 가진 정의(first_fight.json에는 godot_rules 키가 없다)
static func is_wolf(d: Dictionary) -> bool:
	return bool(d.get("godot_rules", false)) or (d.has("bite") and d.has("dash"))

static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	var type := String(e.type)
	if bool(e.get("structure", false)):
		return
	if is_wolf(e.def):
		update_wolf(st, e, dt)
	elif type == "archer":
		update_archer(st, e, dt)
	elif type == "spore":
		update_spore(st, e, dt)
	elif PEnemiesNew.has(type):
		PEnemiesNew.update(st, e, dt)

static func is_committed(e: Dictionary) -> bool:
	if e.state in ["bite_track", "bite_lock", "bite_hit"]:
		return true
	return PEnemiesNew.is_committed(e)

static func shield_mult(st: CombatState, e: Dictionary, opt: Dictionary) -> float:
	if bool(e.get("boss", false)): # 신규 보스의 예고된 방패·방어 자세(정면 부분 경감). 기존 보스 3종은 1.0
		return PBoss3.shield_mult(st, e, opt)
	return PEnemiesNew.shield_mult(st, e, opt)

static func on_damaged(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary) -> void:
	PEnemiesNew.on_damaged(st, e, dmg, opt)

static func detonate(st: CombatState, z: Dictionary) -> void:
	PEnemiesNew.detonate(st, z)

## 봇용 위협 도형(화면에 보이는 예고와 같은 정보만). out에 {kind, e, x, y, ang, len, w, r, half, prog, locked} 추가
static func threats(st: CombatState, e: Dictionary, out: Array) -> void:
	var d: Dictionary = e.def
	var p := st.player
	if is_wolf(d):
		var D: Dictionary = d.dash
		var B: Dictionary = d.bite
		if e.state == "crouch":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": float(D.dash_speed) * float(D.dash_time) + 40.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": float(e.state_t) / float(D.crouch), "locked": false })
		elif e.state == "lock" or e.state == "dash":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": float(D.dash_speed) * float(D.dash_time) + 40.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": 1.0, "locked": true })
		elif e.state == "bite_track":
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(B.reach) + 24.0, "half": float(B.arc_deg) * PI / 360.0 + 0.35, "prog": float(e.state_t) / float(B.track), "locked": false })
		elif e.state == "bite_lock" or e.state == "bite_hit":
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "r": float(B.reach) + 24.0, "half": float(B.arc_deg) * PI / 360.0 + 0.35, "prog": 1.0, "locked": true })
	elif e.type == "archer":
		if e.state == "aim":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": 2000.0, "w": 40.0, "prog": float(e.state_t) / float(d.aim), "locked": false })
		elif e.state == "lock":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": 2000.0, "w": 40.0, "prog": 1.0, "locked": true })
	elif e.type == "spore":
		if e.state == "swell":
			out.append({ "kind": "circle", "e": e, "x": e.x, "y": e.y, "r": float(d.cloudR), "prog": float(e.state_t) / float(d.swell), "locked": float(e.state_t) / float(d.swell) > 0.6 })
	else:
		PEnemiesNew.threats(st, e, out)

static func zone_threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "spore":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r })
	PEnemiesNew.zone_threats(st, out)

# ---------- 늑대·늑대 우두머리 (docs/RULES.md §늑대: 가까우면 물기, 적당한 거리·재사용 가능·자리 확보 시 돌진) ----------
static func dash_states_count(st: CombatState) -> int:
	var n := 0
	for e in st.alive_enemies():
		if e.state == "crouch" or e.state == "lock" or e.state == "dash":
			n += 1
	return n

static func bite_states_count(st: CombatState) -> int:
	var n := 0
	for e in st.alive_enemies():
		if e.state == "bite_track" or e.state == "bite_lock" or e.state == "bite_hit":
			n += 1
	return n

## 이 단계에 돌진을 원하는가(접근 중·첫 지연 경과·재사용 가능·거리 조건·시야)
static func wants_dash(st: CombatState, e: Dictionary) -> bool:
	if e.state != "approach" or e.dead or not is_wolf(e.def):
		return false
	var D: Dictionary = e.def.dash
	if float(e.get("grace", 0.0)) > 0.0:
		return false
	if st.t < float(e.dash_ready_at) or float(e.dash_cd) > 0.0:
		return false
	var dist := PGeom.dist(e.x, e.y, st.player.x, st.player.y)
	if dist < float(D.min_dist) or dist > float(D.engage_dist):
		return false
	return not st.los_blocked(e.x, e.y, st.player.x, st.player.y)

## 동시 돌진 제한: 빈 자리만큼, 마지막 돌진이 오래된 순(동률은 id) — 매 단계 추첨 없음
static func grant_dash_slots(st: CombatState) -> void:
	var max_c: int = int(st.cfg.enemies.wolf.dash.max_concurrent)
	var free: int = max_c - dash_states_count(st)
	if free <= 0:
		return
	var cands := []
	for e in st.alive_enemies():
		if wants_dash(st, e):
			cands.append(e)
	cands.sort_custom(func(a, b):
		if a.last_dash_end != b.last_dash_end:
			return a.last_dash_end < b.last_dash_end
		return a.id < b.id)
	for i in mini(free, cands.size()):
		cands[i].dash_granted = true

static func _bite_hit_check(st: CombatState, e: Dictionary) -> bool:
	var B: Dictionary = e.def.bite
	var p := st.player
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if dist > float(B.reach):
		return false
	var ang := atan2(p.y - e.y, p.x - e.x)
	return absf(PGeom.ang_diff(ang, e.dir)) <= float(B.arc_deg) * PI / 360.0

static func update_wolf(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var D: Dictionary = d.dash
	var B: Dictionary = d.bite
	var p := st.player
	var tf := st.time_factor(e.x, e.y, e.r)
	var sm := st.enemy_speed_mult(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	var boss_mode: bool = st.mode == "boss"
	if float(e.dash_cd) > 0.0:
		e.dash_cd = maxf(0.0, float(e.dash_cd) - dt * tf)
		if float(e.dash_cd) < 1e-6:
			e.dash_cd = 0.0
	if float(e.bite_cd) > 0.0:
		e.bite_cd = maxf(0.0, float(e.bite_cd) - dt * tf)
		if float(e.bite_cd) < 1e-6:
			e.bite_cd = 0.0
	if float(e.get("grace", 0.0)) > 0.0:
		e.grace = float(e.grace) - dt
	var leash: float = float(e.get("leash_boost", 1.0))
	match e.state:
		"approach":
			if dist <= float(B.reach) and float(e.bite_cd) <= 0.0 and float(e.get("grace", 0.0)) <= 0.0 and (not boss_mode or st.wolf_may_attack(e, dt)):
				e.state = "bite_track"
				e.state_t = 0.0
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				e.acted = true
				e.dash_granted = false
				e.ready_t = -1.0
				st.metrics_for(e).bites_prepared += 1
				st.metrics_for(e).prepared += 1
				e.attack_n = int(e.get("attack_n", 0)) + 1 # 공격 인스턴스 번호(관측·계측 전용, 규칙·난수 무관)
				st.attack_log.append([snapped(st.t, 0.0001), e.id, "bite"])
			elif bool(e.dash_granted) and (not boss_mode or st.wolf_may_attack(e, dt)):
				e.dash_granted = false
				e.state = "crouch"
				e.state_t = 0.0
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				e.acted = true
				e.ready_t = -1.0
				e.dash_left = int(D.get("dashes", 1))
				st.metrics_for(e).dashes_prepared += 1
				st.metrics_for(e).prepared += 1
				e.attack_n = int(e.get("attack_n", 0)) + 1 # 공격 인스턴스 번호(관측·계측 전용, 규칙·난수 무관)
				st.attack_log.append([snapped(st.t, 0.0001), e.id, "dash"])
			elif dist > float(B.reach) - 4.0:
				st.approach(e, p.x, p.y, float(d.speed) * sm * leash, dt)
		"bite_track":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += dt * tf
			if float(e.state_t) >= float(B.track):
				e.state = "bite_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("bite_lock")
		"bite_lock":
			e.state_t += dt * tf
			if float(e.state_t) >= float(B.lock):
				e.state = "bite_hit"
				e.state_t = 0.0
				e.bite_hit_done = false
				e.bites = int(e.bites) + 1
				st.metrics_for(e).bites_executed += 1
				st.metrics_for(e).executed += 1
		"bite_hit":
			if not bool(e.bite_hit_done) and _bite_hit_check(st, e):
				e.bite_hit_done = true
				e.bite_t = 0.0
				st.ev("bite")
				if st.damage_player(float(B.damage), "wolf:bite", e):
					st.metrics_for(e).bite_hits += 1
			e.state_t += dt * tf
			if float(e.state_t) >= float(B.active):
				e.state = "bite_recover"
				e.state_t = 0.0
				e.bite_cd = float(B.cooldown)
		"bite_recover":
			e.state_t += dt * tf
			if float(e.state_t) >= float(B.recover):
				e.state = "approach"
				e.state_t = 0.0
		"crouch":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += dt * tf
			var need: float = float(D.get("second_crouch", D.crouch)) if int(e.dash_left) < int(D.get("dashes", 1)) else float(D.crouch)
			if float(e.state_t) >= need:
				e.state = "lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("lock")
		"lock":
			e.state_t += dt * tf
			if float(e.state_t) >= float(D.lock):
				e.state = "dash"
				e.state_t = 0.0
				e.hit_by = false
				e.dashes = int(e.dashes) + 1
				st.metrics_for(e).dashes_executed += 1
				st.metrics_for(e).executed += 1
		"dash":
			var remain := maxf(0.0, float(D.dash_time) - float(e.state_t))
			var use_dt := minf(dt * tf, remain)
			e.state_t += dt * tf
			var stp := float(D.dash_speed) * use_dt
			var x0: float = e.x
			var y0: float = e.y
			var mv := st.move_swept(e, cos(e.dir) * stp, sin(e.dir) * stp)
			if not bool(e.hit_by) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
				e.hit_by = true
				e.bite_t = 0.0
				st.ev("dash_hit")
				if st.damage_player(float(D.damage), "wolf:dash", e):
					st.metrics_for(e).dash_hits += 1
			var hit_wall: bool = String(mv.hit) != ""
			if float(e.state_t) >= float(D.dash_time) or hit_wall:
				if not bool(e.hit_by):
					e.bite_t = 0.0
				e.dash_left = int(e.dash_left) - 1
				if int(e.dash_left) > 0:
					e.state = "crouch" # 우두머리: 두 번째 돌진(짧은 준비)
					e.state_t = 0.0
				else:
					e.state = "recover"
					e.state_t = 0.0
					e.dash_cd = float(D.cooldown)
					e.last_dash_end = st.t
		"recover":
			e.state_t += dt * tf
			if float(e.state_t) >= float(D.recover):
				e.state = "approach"
				e.state_t = 0.0

# ---------- 궁수 (HTML updateArcher) ----------
static func update_archer(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match e.state:
		"approach":
			if dist < float(d.keepMin):
				st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
			elif dist > float(d.keepMax):
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			e.state_t += dt * tf
			if dist <= float(d.keepMax) + 40.0 and float(e.state_t) >= 0.3 and st.may_attack(e, dt):
				e.state = "aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.aim):
				e.state = "lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("lock")
		"lock":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.lock):
				st.projectiles.append({ "owner": "enemy", "kind": "arrow", "shooter": e, "x": e.x + cos(e.dir) * (e.r + 4.0), "y": e.y + sin(e.dir) * (e.r + 4.0), "vx": cos(e.dir) * float(d.arrowSpeed), "vy": sin(e.dir) * float(d.arrowSpeed), "r": float(d.arrowR), "dmg": float(d.arrowDamage), "ttl": 4.0, "angle": e.dir, "dead": false, "hits": {} })
				st.ev("shoot")
				st.note_attack(e, "execute")
				e.state = "recover"
				e.state_t = 0.0
		"recover":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.recover):
				e.state = "approach"
				e.state_t = 0.0

# ---------- 포자 괴물 (HTML updateSpore) ----------
static func update_spore(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match e.state:
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and st.may_attack(e, dt):
				e.state = "swell"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"swell":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.swell):
				st.add_zone("spore", e.x, e.y, float(d.cloudR), float(d.cloudTtl), float(d.cloudDamage) * float(e.get("tier_dmg", 1.0)))
				st.ev("spore")
				st.note_attack(e, "execute")
				e.state = "recover"
				e.state_t = 0.0
		"recover":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.recover):
				e.state = "approach"
				e.state_t = 0.0
