class_name PEnemies
extends RefCounted
## 적 행동 분배: 늑대·늑대 우두머리(godot-0.3.1 규칙, D33/D35 보존) · 궁수·포자(HTML combat.js) · 신규 8종(PEnemiesNew, HTML enemies.js).
## 공통: 준비(예고) → 확정 → 실행 → 빈틈. 감속장은 준비·실행·빈틈 진행(tf)을 늦추고 냉기는 이동만 늦춘다.
## 접촉 피해: 원칙적으로 없다. **포자 괴물만 예외**(2026-09-08 사용자 확정, 아래 '포자 괴물' 절 참고).

## 늑대 계열(0.3.1 규칙) 판별: bite·dash 블록을 가진 정의(first_fight.json에는 godot_rules 키가 없다)
static func is_wolf(d: Dictionary) -> bool:
	return bool(d.get("godot_rules", false)) or (d.has("bite") and d.has("dash"))

static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	var type := String(e.type)
	if bool(e.get("structure", false)):
		# 제단·봉인 장치는 PObjectives가 굴린다. 정예가 만든 깃발·돌무더기는 스스로 수명을 센다(부수면 즉시 사라진다)
		if PEnemiesNew.ELITE_STRUCTURES.has(type):
			PEnemiesNew.update(st, e, dt)
		return
	# 군단 기수 깃발의 집결·돌격 명령은 시간 제한이 있고, 깃발이 사라지면 다음 단계에 저절로 꺼진다
	if float(e.get("rally_t", 0.0)) > 0.0:
		e.rally_t = float(e.rally_t) - dt
		if float(e.rally_t) <= 0.0:
			e.rally_t = 0.0
			e.ordered = false
			e.leash_boost = 1.0
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
			# 예고 원은 **준비를 시작한 자리**에 고정한다(플레이어를 따라가지 않는다). 실제 구름도 같은 자리에 생긴다
			var c := spore_swell_center(e)
			out.append({ "kind": "circle", "e": e, "x": c[0], "y": c[1], "r": float(d.cloudR), "prog": float(e.state_t) / float(d.swell), "locked": float(e.state_t) / float(d.swell) > 0.6 })
	else:
		PEnemiesNew.threats(st, e, out)

static func zone_threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "spore":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r })
	PEnemiesNew.zone_threats(st, out)

## **지원 연결선**(위협이 아니다 — threats와 일부러 분리했다. 봇의 회피 계산에 섞이면 안 되기 때문이다).
## 지금 누가 누구를 치료하고 있는지를 화면·계측이 읽을 수 있게 내보낸다. 그리는 것은 render.gd 담당이며
## 무엇을 그려야 하는지는 docs/ENEMY_FEEDBACK.md에 적었다.
## out에 { kind:"heal_link", e(시전자), target(대상), x,y(시전자), tx,ty(대상), prog(0~1 시전 진행), ratio(회복 비율) } 추가
static func support_links(st: CombatState, out: Array) -> void:
	for e in st.enemies:
		if e.dead:
			continue
		var tg := PEnemiesNew.heal_link_target(e)
		if tg.is_empty():
			continue
		out.append({ "kind": "heal_link", "e": e, "target": tg, "x": e.x, "y": e.y, "tx": tg.x, "ty": tg.y,
			"prog": clampf(float(e.state_t) / maxf(0.001, float((e.def as Dictionary).healCast)), 0.0, 1.0),
			"ratio": PEnemiesNew.dv(e, "healRatio", 0.0) })

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
			if dist <= float(d.keepMax) + 40.0 and float(e.state_t) >= 0.3 and PEnemiesNew.may_start(st, e, dt):
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
				var pr_arrow := { "owner": "enemy", "kind": "arrow", "shooter": e, "x": e.x + cos(e.dir) * (e.r + 4.0), "y": e.y + sin(e.dir) * (e.r + 4.0), "vx": cos(e.dir) * float(d.arrowSpeed), "vy": sin(e.dir) * float(d.arrowSpeed), "r": float(d.arrowR), "dmg": float(d.arrowDamage), "ttl": 4.0, "angle": e.dir, "dead": false, "hits": {} }
				CombatState.stamp_projectile(e, pr_arrow)
				st.projectiles.append(pr_arrow)
				st.ev("shoot")
				st.note_attack(e, "execute")
				e.state = "recover"
				e.state_t = 0.0
		"recover":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.recover):
				e.state = "approach"
				e.state_t = 0.0

# ---------- 포자 괴물 (HTML updateSpore + 2026-09-08 결함 수정) ----------
## **수정 전 결함**(사용자가 직접 플레이하고 확정): 포자가 폭발이 닿지 않는 거리에서 멈춰,
## 플레이어가 가만히 있어도 공격을 맞지 않았다. enemies.json의 engageDist(130)가 cloudR(80)보다 커서
## 구름이 플레이어에게 절대 닿지 않았고, 예고 중에도 따라오지 않으니 서 있기만 하면 무해했다.
##
## **확정된 수정**(사용자 결정, 시험값은 data/pacing.json "spore"):
##  1. 폭발 반경의 절반까지 **충분히 접근한 뒤** 준비한다(접근 거리 = cloudR × approach_frac).
##  2. 준비를 시작하면 **그 자리에 멈추고** 폭발 중심을 고정해 범위를 예고한다.
##  3. 예고 중에는 플레이어를 따라가지 않는다 — 구름은 고정된 중심에 생긴다.
##  4. 몸이 겹치면 **포자 개체별 접촉 피해**가 있다(이 파일에서 유일한 접촉 피해 예외).
##  5. 여러 포자와 겹치면 개체 수만큼 중첩된다(공통 피격 보호 면제, CombatState.hit_protected).
##  6. 개체별 접촉 재타격 간격(contact_interval)으로 매 프레임 피해를 막는다.
##  7. 회피 무적은 그대로 적용된다(damage_player 최상단에서 걸러진다).
##
## **같은 프레임 처리 순서**(docs/SPORE_FIX.md): 접촉 피해는 그 포자의 갱신 **맨 처음**에 계산된다.
## CombatState.update_enemies가 st.enemies 순서대로 돌므로 목록에서 앞선 개체가 먼저 때린다.
## 접촉 피해는 공통 보호를 **읽지 않고** 세우기만 한다 → 뒤따르는 일반 공격은 막히고, 반대로
## 일반 공격이 먼저 들어와 보호가 서 있어도 접촉 피해는 그대로 들어간다. 구름(장판) 피해는
## 프레임 끝의 update_zones에서 zone_tick(0.5초)으로 따로 계산된다(기존 그대로).

## 접촉 피해 출처 이름(정본). CombatState.hit_protected()가 이 값 하나만 공통 보호에서 뺀다.
## 그쪽은 순환 참조(파싱) 때문에 상수 대신 같은 글자를 직접 쓴다 — 두 값이 같은지는 tests/spore_tests.gd가 단언한다
const SPORE_CONTACT_SRC := "spore:contact"

## 수정 전 동작 재현(대조군 전용, 게임 기본값 아님): 접근 거리 = engageDist, 폭발 중심 미고정, 접촉 피해 없음
static var spore_legacy := OS.get_environment("PROPHECY_SPORE_LEGACY") != ""

## 포자 시험값 겹쳐쓰기(data/pacing.json "spore"). 없으면 아래 기본값 — 규칙 코드에 숫자를 두지 않는 관례대로 표가 정본이다
static func spore_cfg() -> Dictionary:
	return PCatalog.pacing().get("spore", {})

## 준비를 시작하는 중심 간 거리. 폭발 반경의 절반이 기본이며, 몸 크기(포자+플레이어 반지름)보다
## 가깝게는 요구하지 않는다 — 실제 판정(몸)과 예고 표시가 어긋나지 않게 한다
static func spore_engage_dist(st: CombatState, e: Dictionary) -> float:
	var d: Dictionary = e.def
	if spore_legacy:
		return float(d.engageDist)
	var frac := float(spore_cfg().get("approach_frac", 0.5))
	return maxf(float(d.cloudR) * frac, float(e.r) + float(st.player.r))

## 예고·폭발의 중심(준비 시작 시 고정된 자리). 준비 중이 아니거나 대조군이면 지금 몸 위치
static func spore_swell_center(e: Dictionary) -> Array:
	if not spore_legacy and e.has("swell_x"):
		return [float(e.swell_x), float(e.swell_y)]
	return [float(e.x), float(e.y)]

## 개체별 접촉 피해. 몸이 겹치면 contact_damage, 같은 포자에게는 contact_interval 안에 다시 맞지 않는다.
## 공통 피격 보호는 면제(hit_protected)라 여러 포자가 겹치면 개체 수만큼 중첩된다. 회피 무적은 그대로 막는다
static func spore_contact(st: CombatState, e: Dictionary, dt: float) -> void:
	if spore_legacy:
		return
	var tf := st.time_factor(e)
	if float(e.get("contact_cd", 0.0)) > 0.0:
		e.contact_cd = maxf(0.0, float(e.get("contact_cd", 0.0)) - dt * tf)
	var p := st.player
	if float(e.get("contact_cd", 0.0)) > 0.0:
		return
	if PGeom.dist(e.x, e.y, p.x, p.y) > float(e.r) + float(p.r):
		return
	# 재타격 간격은 **닿는 순간** 선다(막혔는지와 무관). 늑대 물기가 회피당해도 그 공격을 소모하는 것과 같은 규칙이며,
	# 회피 무적 중에 매 프레임 '회피!'가 뜨는 연타도 이것으로 막는다.
	# 계측은 apply_player_damage가 metrics.taken["spore:contact"]에 자동으로 남긴다
	e.contact_cd = float(spore_cfg().get("contact_interval", 1.0))
	st.damage_player(float(spore_cfg().get("contact_damage", 3.0)), SPORE_CONTACT_SRC, e)

static func update_spore(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	spore_contact(st, e, dt) # 상태와 무관한 몸 접촉. 이 포자 갱신의 맨 처음(처리 순서 고정)
	match e.state:
		"approach":
			var engage := spore_engage_dist(st, e)
			if dist > engage: # 충분히 접근할 때까지만 따라간다 — 붙은 뒤에는 밀고 들어가지 않는다
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= engage and PEnemiesNew.may_start(st, e, dt):
				e.state = "swell"
				e.state_t = 0.0
				e.ready_t = -1.0
				e.swell_x = e.x # 준비를 시작한 자리에 폭발 중심을 고정(예고 = 실제)
				e.swell_y = e.y
				st.note_attack(e, "prepare")
		"swell":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.swell):
				var c := spore_swell_center(e)
				st.add_zone("spore", c[0], c[1], float(d.cloudR), float(d.cloudTtl), float(d.cloudDamage) * float(e.get("tier_dmg", 1.0)))
				st.ev("spore")
				st.note_attack(e, "execute")
				e.erase("swell_x")
				e.erase("swell_y")
				e.state = "recover"
				e.state_t = 0.0
		"recover":
			e.state_t += dt * tf
			if float(e.state_t) >= float(d.recover):
				e.state = "approach"
				e.state_t = 0.0
