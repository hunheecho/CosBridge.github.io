class_name PEnemiesNew
extends RefCounted
## 신규 기본 몬스터 8종(HTML enemies.js 이식): 멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적.
## + 특수 정예 7종(2026-09-08 추가, 시험값): 정예 궁수·정예 검사·피의 송곳니·역병 조율사·사슬 집행자·군단 기수·균열 채굴자
##   와 그들이 만드는 파괴 가능한 구조물 2종(군단 깃발·돌무더기). 정의는 data/enemies.json, 배치표는 data/elites.json, 설명은 docs/ELITES.md.
## PEnemies.update가 has(type)인 개체에 update를 호출한다. 공통 규칙: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음.
## 상호작용: 감속장은 준비·실행·빈틈 진행(tf)을 늦추고, 냉기는 이동만 늦춘다. 넉백은 돌진·잠복·도약 중에는 무시(combat_state.knock_enemy), 방패병은 50%(def.knockMult).
## 면역(최소 범위): 잠복충·균열 채굴자의 지하 구간(hidden)은 직접 공격·투사체 대상이 되지 않는다(바닥 효과는 적용). 그 외 면역 없음.
## 피해 감소(방패·깃발)는 shield_mult 한 곳에서만 계산하고, 여러 효과가 겹쳐도 곱하지 않는다(가장 강한 하나만).
## 개체별 추가 필드(snake_case, 지연 초기화): face, preview, charge_len, charge_end, charge_blocked, charge_dist, hit_done, heal_t, hex_t, cast_target, cast_pts, cast_t,
##   burrow_cd, emerge_at, web_t, web_at, side, base_dir, exploded, block_fx_t,
##   정예: shot_left, blocked_sec, leap_at, leap_from, pods, chain_len, chain_d, pull_from, slam_at, plant_left, order_left, order_t, banner_ref,
##   지휘받는 쪽: rally_t, ordered(leash_boost는 rally_t가 끝나면 PEnemies.update가 1.0으로 되돌린다). 구조물: banner_ttl, banner_r, ring_t, rubble_ttl, trail_t

const COMMITTED := {
	"boar": ["charge_aim", "charge_lock", "charge"],
	"shieldbearer": ["bash_aim", "bash"],
	"shaman": ["cast", "hex_aim"],
	"bomber": ["fuse"],
	"burrower": ["dive", "under", "warn", "emerge", "bite_aim"],
	"spider": ["web_aim", "bite_aim"],
	"frostcaller": ["cast"],
	"rogue": ["slash1_aim", "slash2_aim"],
	# 특수 정예 7종(2026-09-08, 시험값). 연계 전체를 '위험 공격 중'으로 센다 — 다른 적이 그 위에 겹쳐 쌓지 않게
	"elite_archer": ["aim", "shot_lock", "fan_aim", "fan_lock"],
	"elite_blademaster": ["dash1_aim", "dash1_lock", "dash1", "dash2_aim", "dash2_lock", "dash2", "guard", "slam_aim", "slam"],
	"elite_fang": ["bite_aim", "backoff", "leap_aim", "leap_lock", "leap"], # backoff는 연계 중간 이동이라 '연계 중'으로 센다
	"elite_plaguecaller": ["throw_aim", "swell", "burst_aim"],
	"elite_chainbreaker": ["chain_aim", "chain_lock", "chain_fly", "pull", "slam_aim", "slam_lock", "sweep_aim"],
	"elite_standard": ["plant_aim", "slash_aim"],
	"elite_miner": ["dive", "under", "warn", "erupt", "bite_aim"],
}

## 특수 정예 7종의 type(구조물 2종 제외). data/enemies.json 정의 + data/elites.json 배치표
const ELITE_TYPES := ["elite_archer", "elite_blademaster", "elite_fang", "elite_plaguecaller", "elite_chainbreaker", "elite_standard", "elite_miner"]
## 정예가 만드는 파괴 가능한 구조물(깃발·돌무더기). PEnemies.update가 구조물 중 이 둘만 갱신한다
const ELITE_STRUCTURES := ["elite_banner", "elite_rubble"]

static func has(type: String) -> bool:
	return COMMITTED.has(type) or ELITE_STRUCTURES.has(type)

static func is_elite(type: String) -> bool:
	return ELITE_TYPES.has(type)

static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	match String(e.type):
		"boar":
			update_boar(st, e, dt)
		"shieldbearer":
			update_shieldbearer(st, e, dt)
		"shaman":
			update_shaman(st, e, dt)
		"bomber":
			update_bomber(st, e, dt)
		"burrower":
			update_burrower(st, e, dt)
		"spider":
			update_spider(st, e, dt)
		"frostcaller":
			update_frostcaller(st, e, dt)
		"rogue":
			update_rogue(st, e, dt)
		"elite_archer":
			update_elite_archer(st, e, dt)
		"elite_blademaster":
			update_elite_blademaster(st, e, dt)
		"elite_fang":
			update_elite_fang(st, e, dt)
		"elite_plaguecaller":
			update_elite_plaguecaller(st, e, dt)
		"elite_chainbreaker":
			update_elite_chainbreaker(st, e, dt)
		"elite_standard":
			update_elite_standard(st, e, dt)
		"elite_miner":
			update_elite_miner(st, e, dt)
		"elite_banner":
			update_banner(st, e, dt)
		"elite_rubble":
			update_rubble(st, e, dt)

static func is_committed(e: Dictionary) -> bool:
	var c: Array = COMMITTED.get(String(e.type), [])
	return c.has(String(e.state))

# ---------- 공용 도우미 ----------
## 빈틈 상태로 전환. label=false면 "빈틈!" 표시 생략
static func to_recover(st: CombatState, e: Dictionary, dur: float, label: bool = true) -> void:
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = dur
	if label:
		st.text(e.x, e.y - e.r - 26.0, "빈틈!", "#ffd166")

## 궁수식 거리 유지(장애물 우회)
static func keep_distance(st: CombatState, e: Dictionary, d: Dictionary, dt: float, sm: float) -> void:
	var p := st.player
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if dist < float(d.keepMin):
		st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
	elif dist > float(d.keepMax):
		st.approach(e, p.x, p.y, float(d.speed) * sm, dt)

## 부채꼴 근접 판정(직접 공격: 장애물 가림 적용)
static func arc_hit(st: CombatState, e: Dictionary, ang: float, R: float, half: float, dmg: float, src: String) -> void:
	var p := st.player
	if PGeom.in_arc(e.x, e.y, R, ang, half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
		st.damage_player(dmg, src, e)

static func _recover_tick(e: Dictionary, adv: float) -> void:
	e.state_t += adv
	if float(e.state_t) >= float(e.recover_dur):
		e.state = "approach"
		e.state_t = 0.0

# ---------- A. 멧돼지: 긴 직선 돌파 ----------
static func update_boar(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach":
			if dist < float(d.minDist): # 너무 가까우면 물러나서 거리를 벌린 뒤 돌파(밀어붙이기 금지)
				e.state = "backoff"
				e.state_t = 0.0
				return
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			# 코앞이 막혀 있으면 돌파하지 않는다
			if dist <= float(d.engageDist) and dist >= float(d.minDist) and not st.los_blocked(e.x, e.y, p.x, p.y) \
				and float(PBoss.dash_path(st, e, atan2(p.y - e.y, p.x - e.x), float(d.chargeDist))["len"]) >= float(d.minDist) and st.may_attack(e, dt):
				e.state = "charge_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"backoff": # 최대 1.5초 뒤로 물러남(벽에 막히면 접선 방향). 거리가 벌어지면 접근 상태로
			e.state_t += dt
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
			if dist >= float(d.minDist) + 40.0 or float(e.state_t) >= 1.5:
				e.state = "approach"
				e.state_t = 0.0
		"charge_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			e.preview = PBoss.dash_path(st, e, float(e.aim_angle), float(d.chargeDist)) # 예고와 실제가 같은 계산
			var pv: Dictionary = e.preview
			if float(e.state_t) >= float(d.aim) and not pv.is_empty() and float(pv["len"]) < float(d.minDist): # 준비 중 통로가 막히면 돌파 취소
				e.state = "approach"
				e.state_t = 0.0
				e.preview = {}
				return
			if float(e.state_t) >= float(d.aim):
				e.state = "charge_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				var path := PBoss.dash_path(st, e, float(e.dir), float(d.chargeDist))
				e.charge_len = float(path["len"])
				e.charge_end = path.end
				e.charge_blocked = float(path["len"]) < float(d.chargeDist) - 1.0 # 통로가 장애물·벽에서 끊기면 그 끝에서 충돌(긴 빈틈)
				e.charge_dist = 0.0
				e.hit_done = false
				st.ev("lock")
		"charge_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.lock):
				e.state = "charge"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"charge": # 거리 기준: 감속되어도 경로·거리 그대로. 장애물·벽에 닿으면 긴 빈틈
			var remain: float = maxf(0.0, float(e.charge_len) - float(e.charge_dist))
			var stp: float = minf(float(d.chargeSpeed) * tf * dt, remain)
			var x0: float = e.x
			var y0: float = e.y
			var mv := st.move_swept(e, cos(float(e.dir)) * stp, sin(float(e.dir)) * stp)
			e.charge_dist = float(e.charge_dist) + PGeom.dist(e.x, e.y, x0, y0)
			if not bool(e.hit_done) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
				e.hit_done = true
				e.bite_t = 0.0
				st.ev("bite")
				st.damage_player(float(d.damage), "boar", e)
			var done: bool = float(e.charge_dist) >= float(e.charge_len) - 1e-6 or stp <= 1e-9
			if String(mv.hit) != "" or (done and bool(e.charge_blocked)):
				e.state = "stagger"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 26.0, "충돌! 긴 빈틈", "#ffd166")
				st.fx({ "kind": "impact", "x": e.x + cos(float(e.dir)) * e.r, "y": e.y + sin(float(e.dir)) * e.r, "r": 40.0, "ttl": 0.3 })
				st.ev("boss_land")
			elif done:
				to_recover(st, e, float(d.recover))
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.stun):
				e.state = "approach"
				e.state_t = 0.0
		"recover":
			_recover_tick(e, adv)

# ---------- B. 방패병: 정면 방어 ----------
## 2026-09-08 사용자 확정: 정면 감소 70% → 85%(def.frontMult 0.15), 정면 각 120도 유지.
## 접근 중과 방패치기 **준비 중(bash_aim)**에는 방패를 유지하고, 실제 방패치기(bash)와 그 뒤 빈틈(recover)에만 연다.
## 방향 전환은 느리게 유지(turnRate 2.2 rad/s)해 측·후방 공략이 답이 되게 한다. 판정 점검은 docs/SHIELDBEARER.md.
static func update_shieldbearer(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("face"):
		e.face = atan2(p.y - e.y, p.x - e.x)
	# 방향 전환은 즉시가 아니다: 초당 turnRate(감속장 안에서는 더 느리게)
	var want: float = atan2(p.y - e.y, p.x - e.x)
	var diff := PGeom.ang_diff(float(e.face), want)
	var max_turn: float = float(d.turnRate) * adv
	e.face = float(e.face) + clampf(diff, -max_turn, max_turn)
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) + e.r and absf(diff) < PGeom.deg(50.0) and st.may_attack(e, dt):
				e.state = "bash_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"bash_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.aim):
				e.state = "bash"
				e.state_t = 0.0
				e.dir = e.face
				st.move_swept(e, cos(float(e.dir)) * float(d.lunge), sin(float(e.dir)) * float(d.lunge))
				var half: float = PGeom.deg(float(d.bashDeg)) / 2.0
				arc_hit(st, e, float(e.dir), float(d.bashRange), half, float(d.damage), "bash")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.bashRange), "half": half, "ttl": 0.18, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("boss_sweep")
		"bash":
			e.state_t += adv
			if float(e.state_t) >= 0.12:
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 방패가 지금 닫혀(방어) 있는가. 2026-09-08 사용자 확정: 접근 중과 방패치기 **준비 중**에는 유지,
## 실제 방패치기(bash)와 그 뒤 빈틈(recover)에만 열린다. 정예 검사(elite_blademaster)의 방패 자세도 같은 함수로 묻는다
static func guard_closed(e: Dictionary) -> bool:
	match String(e.type):
		"shieldbearer":
			return String(e.state) != "bash" and String(e.state) != "recover"
		"elite_blademaster":
			return String(e.state) == "guard"
	return false

## 방패 판정: 방패가 닫혀 있고 공격 **출처**가 정면 부채꼴 안이면 frontMult(방패병 0.15 = 85% 감소,
## 정예 검사 guardMult 0.0 = 정면 직접 피해 완전 차단). 출처 위치가 없는 바닥·추가·기술·지속 피해는 정상.
## 감소는 **한 번만** 적용한다: 여러 방어 효과가 겹치면 곱하지 않고 가장 강한 하나(min)만 쓴다.
static func shield_mult(st: CombatState, e: Dictionary, opt: Dictionary) -> float:
	var m := 1.0
	if guard_closed(e) and e.has("face") and _blockable(opt):
		var d: Dictionary = e.def
		var from: Dictionary = opt.get("from", st.player)
		var a: float = atan2(float(from.y) - e.y, float(from.x) - e.x)
		var half: float = PGeom.deg(float(d.get("guardDeg", d.get("frontDeg", 0.0)))) / 2.0
		if half > 0.0 and absf(PGeom.ang_diff(float(e.face), a)) <= half:
			m = minf(m, float(d.get("guardMult", d.get("frontMult", 1.0))))
	if _rally_guard(st, e) and _blockable(opt): # 군단 기수 깃발의 방어 지원(중복 아님: 더 강한 쪽만)
		m = minf(m, float(PCatalog.enemy("elite_standard").get("banner", {}).get("guardMult", 1.0)))
	# 출격 준비물 '파쇄 기름': 방어 감소에 하한을 둔다. min으로 고른 결과에 **한 번만** 적용하고 곱하지 않는다
	m = maxf(m, PConsumables.guard_floor(st.build))
	return m

## 방패·깃발이 막을 수 있는 피해인가(직접 공격 = 무기 본체·투사체). 바닥·추가·기술·지속 피해는 정상
static func _blockable(opt: Dictionary) -> bool:
	var sr: Dictionary = opt.get("src", {})
	return bool(sr.get("direct", true)) and not bool(sr.get("extra", false)) and not bool(sr.get("skill", false)) and not opt.has("dot")

# ---------- C. 주술사: 치료 시전(우선 처치 대상) ----------
## 치료 대상: 자기·보스·주술사·지하 제외, 사거리 안에서 잃은 비율이 가장 큰 아군. 없으면 {}
static func heal_target(st: CombatState, e: Dictionary) -> Dictionary:
	var d: Dictionary = e.def
	var best := {}
	var bs := 0.0
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.boss) or bool((o.def as Dictionary).get("boss", false)) or String(o.type) == "shaman" or bool(o.get("hidden", false)):
			continue
		if float(o.hp) >= float(o.hp_max):
			continue
		if PGeom.dist(o.x, o.y, e.x, e.y) > float(d.healRange):
			continue
		var miss: float = 1.0 - float(o.hp) / float(o.hp_max)
		if miss > bs:
			bs = miss
			best = o
	return best

static func update_shaman(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("heal_t"):
		e.heal_t = 2.0
		e.hex_t = 1.5
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			e.heal_t = float(e.heal_t) - dt
			e.hex_t = float(e.hex_t) - dt
			if float(e.heal_t) <= 0.0:
				var tg := heal_target(st, e)
				if not tg.is_empty() and st.may_attack(e, dt):
					e.state = "cast"
					e.state_t = 0.0
					e.cast_target = tg
					e.ready_t = -1.0
					st.note_attack(e, "prepare")
					st.text(e.x, e.y - e.r - 26.0, "치료 시전", "#e9b6ff")
					return
			if float(e.hex_t) <= 0.0 and dist <= float(d.keepMax) + 40.0 and not st.los_blocked(e.x, e.y, p.x, p.y) and st.may_attack(e, dt):
				e.state = "hex_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"cast":
			var tgv = e.get("cast_target")
			e.state_t += adv
			if tgv == null or bool(tgv.dead) or PGeom.dist(float(tgv.x), float(tgv.y), e.x, e.y) > float(d.healRange) + 40.0:
				e.cast_target = null
				e.heal_t = float(d.healInterval) * 0.5
				to_recover(st, e, 0.6, false)
				return
			if float(e.state_t) >= float(d.healCast):
				var tg: Dictionary = tgv
				var before: float = tg.hp
				tg.hp = minf(float(tg.hp_max), float(tg.hp) + float(tg.hp_max) * float(d.healRatio))
				var amt: float = float(tg.hp) - before
				st.metrics.heals += 1
				st.metrics.heal_amount += amt
				st.text(tg.x, tg.y - tg.r - 22.0, "+" + str(int(round(amt))), "#9cffb0")
				st.fx({ "kind": "burst", "x": tg.x, "y": tg.y, "r": tg.r + 14.0, "ttl": 0.3, "color": "#e9b6ff" })
				st.ev("orb")
				st.note_attack(e, "execute")
				e.heal_t = float(d.healInterval)
				e.cast_target = null
				to_recover(st, e, float(d.recover))
		"hex_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.hexAim):
				e.dir = e.aim_angle
				var ang: float = e.dir
				var pr_hex := { "owner": "enemy", "kind": "hex", "shooter": e, "x": e.x + cos(ang) * (e.r + 4.0), "y": e.y + sin(ang) * (e.r + 4.0), "vx": cos(ang) * float(d.hexSpeed), "vy": sin(ang) * float(d.hexSpeed), "r": float(d.hexR), "dmg": float(d.hexDamage), "ttl": 4.0, "angle": ang, "dead": false, "hits": {} }
				CombatState.stamp_projectile(e, pr_hex)
				st.projectiles.append(pr_hex)
				st.ev("shoot")
				st.note_attack(e, "execute")
				e.hex_t = float(d.hexInterval)
				to_recover(st, e, float(d.recover), false)
		"recover":
			_recover_tick(e, adv)

## 막기 연출(사용자 확정): **실제 방어 판정이 일어난 순간에만** 방패 타격 효과·금속음·짧은 '방어' 표시.
## damage_enemy가 피해를 적용한 직후 같은 opt로 다시 물어보므로(shield_mult는 부작용 없는 조회) 판정과 연출이 어긋나지 않는다.
## 화면의 '방어 중/열림' 구분과 흰 방패·"막음" 표시는 render.gd가 e.state·e.blocked_t로 이미 그린다.
static func note_block(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	if shield_mult(st, e, opt) >= 1.0:
		return
	if st.t - float(e.get("block_fx_t", -9.0)) < 0.15: # 연타로 소리·글자가 겹치지 않게(판정은 매번 그대로)
		return
	e.block_fx_t = st.t
	var fa: float = float(e.get("face", 0.0))
	var bx: float = e.x + cos(fa) * (float(e.r) + 6.0)
	var by: float = e.y + sin(fa) * (float(e.r) + 6.0)
	st.fx({ "kind": "burst", "x": bx, "y": by, "r": 16.0, "ttl": 0.22, "color": "#e8e8f0" }) # 방패 타격 효과
	st.fx({ "kind": "spark", "x": bx, "y": by, "ttl": 0.18, "angle": fa + PI, "crit": false })
	st.text(e.x, e.y - float(e.r) - 40.0, "방어", "#cfe3ff")
	st.ev("shatter") # 금속음(짧은 고음 사각파)

## 시전 방해: 12 이상 한 방 또는 넉백(20 이상)이면 끊긴다. 처치는 당연히 끊는다.
static func on_damaged(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary) -> void:
	note_block(st, e, opt)
	if String(e.type) == "shaman" and e.state == "cast" and (dmg >= float(e.def.interruptDamage) or float(opt.get("knock", 0.0)) >= 20.0):
		e.cast_target = null
		e.heal_t = float(e.def.healInterval) * 0.5
		st.metrics.interrupts += 1
		st.text(e.x, e.y - e.r - 40.0, "시전 중단!", "#7ef2ff")
		to_recover(st, e, 1.0)

# ---------- D. 폭탄 운반체 ----------
static func update_bomber(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) + e.r and st.may_attack(e, dt):
				e.state = "fuse"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.ev("lock")
		"fuse": # 멈춰 서서 준비. 넉백으로 밀리면 표시 원도 같이 움직인다(실제 범위 = 표시 범위)
			e.state_t += adv
			if float(e.state_t) >= float(d.fuse):
				st.note_attack(e, "execute")
				if dist <= float(d.blastR) + p.r:
					st.damage_player(float(d.damage), "blast", e)
				st.fx({ "kind": "mineburst", "x": e.x, "y": e.y, "r": float(d.blastR), "ttl": 0.4 })
				st.ev("explode")
				e.exploded = true
				e.hp = 0.0
				e.dead = true
				e.death_t = 0.0
				e.acted = true
				var m := st.metrics_for(e)
				m.exploded = int(m.get("exploded", 0)) + 1

# ---------- E. 잠복충 ----------
static func update_burrower(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("burrow_cd"):
		e.burrow_cd = 1.0
	if e.state != "under" and e.state != "dive" and e.state != "warn":
		e.burrow_cd = float(e.burrow_cd) - dt
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and float(e.burrow_cd) <= 0.0 and st.may_attack(e, dt):
				e.state = "dive"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
			elif dist <= float(d.biteRange) + e.r and st.may_attack(e, dt):
				e.state = "bite_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"dive":
			e.state_t += adv
			if float(e.state_t) >= float(d.dive):
				e.state = "under"
				e.state_t = 0.0
				e.hidden = true
		"under": # 짧은 지하 이동(플레이어 추적 허용). 끝나면 출현 지점 확정(지형 안 금지)
			e.state_t += adv
			var n := PGeom.norm(p.x - e.x, p.y - e.y)
			st.move_swept(e, n[0] * float(d.underSpeed) * sm * dt, n[1] * float(d.underSpeed) * sm * dt, true)
			if float(e.state_t) >= float(d.under) or dist < 30.0:
				var pos := st.nearest_valid_pos(e.x, e.y, e.r, 200.0)
				if pos.is_empty():
					pos = [e.x, e.y]
				e.emerge_at = pos
				e.state = "warn"
				e.state_t = 0.0
				st.ev("lock")
		"warn":
			e.state_t += adv
			if float(e.state_t) >= float(d.warn):
				var at: Array = e.emerge_at
				e.x = float(at[0])
				e.y = float(at[1])
				e.hidden = false
				e.state = "emerge"
				e.state_t = 0.0
				st.note_attack(e, "execute")
				if PGeom.dist(e.x, e.y, p.x, p.y) <= float(d.emergeR) + p.r:
					st.damage_player(float(d.damage), "emerge", e)
				st.fx({ "kind": "bossland", "x": e.x, "y": e.y, "r": float(d.emergeR), "ttl": 0.4 })
				st.ev("boss_land")
				e.burrow_cd = float(d.cooldown)
		"emerge":
			e.state_t += adv
			if float(e.state_t) >= 0.15:
				e.state = "stagger"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 26.0, "빈틈!", "#ffd166")
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.exposed):
				e.state = "approach"
				e.state_t = 0.0
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "bite")
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.biteRecover))
		"recover":
			_recover_tick(e, adv)

# ---------- F. 거미 ----------
static func web_count(st: CombatState) -> int:
	var n := 0
	for z in st.zones:
		if z.type == "web":
			n += 1
	return n

static func update_spider(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("web_t"):
		e.web_t = 1.2
	match String(e.state):
		"approach":
			# 거미줄 직전에만 거리를 두고, 그 외에는 물려고 다가온다
			if float(e.web_t) > 1.5:
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			else:
				keep_distance(st, e, d, dt, sm)
			e.web_t = float(e.web_t) - dt
			if dist <= float(d.biteRange) + e.r and st.may_attack(e, dt):
				e.state = "bite_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				return
			if float(e.web_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and st.may_attack(e, dt): # 플레이어 진행 방향 앞(70)에 예고. 예고 위치는 시작 때 확정
				var ax: float = p.x + cos(float(p.face)) * 70.0
				var ay: float = p.y + sin(float(p.face)) * 70.0
				var pos := st.nearest_valid_pos(ax, ay, 0.0, 120.0)
				if pos.is_empty():
					pos = [p.x, p.y]
				e.web_at = pos
				e.state = "web_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"web_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.webAim):
				while web_count(st) >= int(d.maxWebs):
					for i in st.zones.size():
						if st.zones[i].type == "web":
							st.zones.remove_at(i)
							break
				var at: Array = e.web_at
				var z := st.add_zone("web", float(at[0]), float(at[1]), float(d.webR), float(d.webTtl), 0.0)
				z.slow = float(d.webSlow)
				st.metrics.webs += 1
				st.note_attack(e, "execute")
				e.web_t = float(d.webInterval)
				st.ev("spore")
				to_recover(st, e, 0.5, false)
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "bite")
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

# ---------- G. 서리술사 ----------
static func update_frostcaller(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("cast_t"):
		e.cast_t = 1.5
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			e.cast_t = float(e.cast_t) - dt
			if float(e.cast_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and st.may_attack(e, dt): # 위치는 시전 시작 때 확정: 플레이어 위치 + 진행 방향으로 3개
				var ang: float = float(p.face) if bool(p.moving) else st.rng.range_f(0.0, TAU)
				var pts := []
				for i in 3:
					var x: float = p.x + cos(ang) * float(d.spacing) * float(i)
					var y: float = p.y + sin(ang) * float(d.spacing) * float(i)
					var pos := st.nearest_valid_pos(clampf(x, 20.0, st.arena_w - 20.0), clampf(y, 20.0, st.arena_h - 20.0), 0.0, 120.0)
					if pos.is_empty():
						pos = [p.x, p.y]
					pts.append(pos)
				e.cast_pts = pts
				e.state = "cast"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.ev("lock")
		"cast":
			e.state_t += adv
			if float(e.state_t) >= float(d.castAim):
				var pts: Array = e.cast_pts
				var delays: Array = d.delays
				for i in pts.size():
					var pt: Array = pts[i]
					var z := st.add_zone("frostzone", float(pt[0]), float(pt[1]), float(d.zoneR), float(delays[i]), 0.0)
					z.order = i + 1
					z.dmg = float(d.damage) * float(e.get("tier_dmg", 1.0)) # 등급 피해 배율(장판은 attacker가 없어 생성 시 적용)
					z.owner = e
				st.note_attack(e, "execute")
				e.cast_t = float(d.castInterval)
				e.cast_pts = []
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 서리 영역 폭발(combat_state.update_zones가 ttl 소진 직전에 호출). 회피 무적·피격 보호 적용(damage_player)
static func detonate(st: CombatState, z: Dictionary) -> void:
	var p := st.player
	if z.type == "frostzone":
		st.fx({ "kind": "frostburst", "x": z.x, "y": z.y, "r": z.r, "ttl": 0.35 })
		st.ev("shatter")
		if PGeom.dist(z.x, z.y, p.x, p.y) <= z.r + p.r:
			st.damage_player(float(z.dmg), "frostzone")

# ---------- H. 쌍날 도적 ----------
static func update_rogue(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if int(e.get("side", 0)) == 0:
		e.side = -1 if st.rng.next() < 0.5 else 1
	match String(e.state):
		"approach":
			if dist > float(d.flankDist):
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			else:
				var n := PGeom.norm(p.x - e.x, p.y - e.y)
				var side: float = float(e.side)
				var tx: float = p.x - n[0] * 30.0 + (-n[1]) * side * float(d.flankOffset)
				var ty: float = p.y - n[1] * 30.0 + n[0] * side * float(d.flankOffset)
				st.approach(e, tx, ty, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) + e.r and st.may_attack(e, dt):
				e.state = "slash1_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"slash1_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.aim1):
				e.dir = e.aim_angle
				slash(st, e, d)
				e.state = "slash2_aim"
				e.state_t = 0.0
				e.base_dir = e.dir
				e.aim_angle = e.dir
		"slash2_aim": # 두 번째 베기: 첫 방향에서 ±adjust 안에서만 보정
			var want: float = atan2(p.y - e.y, p.x - e.x)
			var lim: float = PGeom.deg(float(d.adjustDeg))
			e.aim_angle = float(e.base_dir) + clampf(PGeom.ang_diff(float(e.base_dir), want), -lim, lim)
			e.state_t += adv
			if float(e.state_t) >= float(d.aim2):
				e.dir = e.aim_angle
				slash(st, e, d)
				to_recover(st, e, float(d.recover))
		"recover":
			e.state_t += adv
			if float(e.state_t) >= float(e.recover_dur):
				e.state = "approach"
				e.state_t = 0.0
				e.side = -int(e.side)

static func slash(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	var half: float = PGeom.deg(float(d.slashDeg)) / 2.0
	arc_hit(st, e, float(e.dir), float(d.slashRange) + e.r, half, float(d.damage), "slash")
	st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.slashRange) + e.r, "half": half, "ttl": 0.14, "enemy": true })
	e.bite_t = 0.0
	st.note_attack(e, "execute")
	st.ev("boss_sweep")

# ========== 특수 정예 7종 (2026-09-08, 시험값 — data/enemies.json 정의 · data/elites.json 배치표 · docs/ELITES.md) ==========
## 공통 규칙
##  - 예고 → 방향(위치) 확정 → 실행 → 빈틈. 확정 뒤에는 추적하지 않으므로 회피가 통한다.
##  - 연계 시작 전에 CombatState.may_attack을 그대로 쓴다(위험 공격 동시 제한). 거기에 **정예 동시 연계 1**을
##    더한다(보완): 일반 전투는 overlap_limit이 0이라 may_attack이 항상 참이므로, 정예끼리 연계를 겹쳐
##    탈출 불가능한 상황을 만들지 않도록 이 한 줄만 추가한다. 일반 적의 압박은 줄이지 않는다.
##  - 무조건 명중·회피 불가 공격·강제 피해 할당량은 쓰지 않는다. 모든 피해는 st.damage_player(회피·피격 보호가 그대로 작동).

## 지금 연계 중인 다른 정예가 있는가(정예 동시 연계 상한 1, 시험값)
static func elite_busy(st: CombatState, e: Dictionary) -> bool:
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.get("boss", false)):
			continue
		if is_elite(String(o.type)) and is_committed(o):
			return true
	return false

## 연계를 시작해도 되는가: 기존 동시 제한(may_attack) + 정예 동시 연계 1
static func elite_may_start(st: CombatState, e: Dictionary, dt: float) -> bool:
	if elite_busy(st, e):
		e.ready_t = -1.0
		return false
	return st.may_attack(e, dt)

## 예고 시작 공통 처리(계측·표시)
static func elite_begin(st: CombatState, e: Dictionary, state: String, label: String = "", color: String = "#ffb0b0") -> void:
	e.state = state
	e.state_t = 0.0
	e.ready_t = -1.0
	st.note_attack(e, "prepare")
	if label != "":
		st.text(e.x, e.y - float(e.r) - 30.0, label, color)

## 느린 방향 전환(방패 자세·조준 유지용). 반환 = 남은 각도 차이
static func face_toward(e: Dictionary, tx: float, ty: float, rate: float, adv: float) -> float:
	if not e.has("face"):
		e.face = atan2(ty - float(e.y), tx - float(e.x))
	var want: float = atan2(ty - float(e.y), tx - float(e.x))
	var diff := PGeom.ang_diff(float(e.face), want)
	var mx: float = rate * adv
	e.face = float(e.face) + clampf(diff, -mx, mx)
	return diff

## 원형 착탄(장애물 가림 없음 — 바닥에 떨어지는 충격). 맞으면 true
static func circle_hit(st: CombatState, e: Dictionary, cx: float, cy: float, r: float, dmg: float, src: String) -> bool:
	var p := st.player
	var hit := false
	if PGeom.dist(cx, cy, p.x, p.y) <= r + float(p.r):
		hit = st.damage_player(dmg, src, e)
	st.fx({ "kind": "bossland", "x": cx, "y": cy, "r": r, "ttl": 0.4 })
	st.ev("boss_land")
	st.note_attack(e, "execute")
	return hit

## 옆으로 이동(재장전·자리 옮기기). side = -1|1
static func strafe(st: CombatState, e: Dictionary, speed: float, dt: float) -> void:
	var p := st.player
	var n := PGeom.norm(p.x - e.x, p.y - e.y)
	if int(e.get("side", 0)) == 0:
		e.side = -1 if st.rng.next() < 0.5 else 1
	var s: float = float(e.side)
	st.approach(e, e.x + (-n[1]) * s * 120.0, e.y + n[0] * s * 120.0, speed, dt)

# ---------- A. 정예 궁수(추격 사수) ----------
## 첫 조준 0.70초(추적 0.58 + 방향 고정 0.12) → 단발 3회(간격 0.50초 = 재조준 0.38 + 고정 0.12)
## → 별도 예고 0.75초(추적 0.60 + 고정 0.15) 뒤 부채꼴 3발 → 측면 이동·재장전 1.4초 빈틈.
## 발사 방향은 shot_lock/fan_lock 시작 때 고정한다(그 뒤에는 플레이어를 따라가지 않는다).
static func update_elite_archer(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("shot_left"):
		e.shot_left = int(d.shots)
		e.blocked_sec = 0.0
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			var blocked: bool = st.los_blocked(e.x, e.y, p.x, p.y)
			e.blocked_sec = (float(e.blocked_sec) + dt) if blocked else 0.0
			if float(e.blocked_sec) >= float(d.blockedLimit): # 장애물에 계속 막히면 사격 위치를 바꾼다
				e.blocked_sec = 0.0
				e.side = -int(e.get("side", 1))
				e.state = "reposition"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "자리 옮김", "#cfe3ff")
				return
			if not blocked and dist <= float(d.keepMax) + 60.0 and elite_may_start(st, e, dt):
				e.shot_left = int(d.shots)
				elite_begin(st, e, "aim", "조준", "#ffd166")
		"reposition":
			e.state_t += dt
			strafe(st, e, float(d.strafeSpeed) * sm, dt)
			if float(e.state_t) >= float(d.strafeTime):
				e.state = "approach"
				e.state_t = 0.0
		"aim": # 매 발 재조준(추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			var need: float = float(d.aim) if int(e.shot_left) == int(d.shots) else float(d.reaim)
			if float(e.state_t) >= need:
				e.state = "shot_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 방향 확정 — 여기서부터 추적하지 않는다
				st.ev("lock")
		"shot_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.lock):
				_arrow(st, e, float(e.dir), float(d.arrowSpeed), float(d.arrowR), float(d.arrowDamage))
				st.note_attack(e, "execute")
				e.shot_left = int(e.shot_left) - 1
				if int(e.shot_left) > 0:
					e.state = "aim"
					e.state_t = 0.0
				else:
					e.state = "fan_aim"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "부채꼴 3발", "#ff9f43")
		"fan_aim": # 별도 예고(추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.fanAim):
				e.state = "fan_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 중앙 화살 방향 확정
				st.ev("lock")
		"fan_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.fanLock):
				var n: int = int(d.fanCount)
				var step: float = PGeom.deg(float(d.fanDeg))
				for i in n:
					var off: float = (float(i) - float(n - 1) / 2.0) * step
					_arrow(st, e, float(e.dir) + off, float(d.arrowSpeed), float(d.arrowR), float(d.fanDamage))
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.recover))
		"recover": # 측면 이동·재장전
			strafe(st, e, float(d.strafeSpeed) * sm, dt)
			_recover_tick(e, adv)
			if String(e.state) == "approach":
				e.side = -int(e.get("side", 1))

static func _arrow(st: CombatState, e: Dictionary, ang: float, speed: float, r: float, dmg: float) -> void:
	var pr := { "owner": "enemy", "kind": "arrow", "shooter": e, "x": e.x + cos(ang) * (float(e.r) + 4.0), "y": e.y + sin(ang) * (float(e.r) + 4.0),
		"vx": cos(ang) * speed, "vy": sin(ang) * speed, "r": r, "dmg": dmg, "ttl": 4.0, "angle": ang, "dead": false, "hits": {} }
	CombatState.stamp_projectile(e, pr)
	st.projectiles.append(pr)
	st.ev("shoot")

# ---------- B. 정예 검사(철갑 추격자) ----------
## 돌진 베기(예고 0.65) → 새 방향 예고(0.50) → 두 번째 돌진 베기 → 방패 자세 1.5초 → 내려찍기 → 빈틈 1.0초.
## 돌진 중에는 추적 회전이 없다(확정 각 그대로). 방패 자세는 **정면 직접 피해 완전 차단**(guardMult 0.0) —
## 일반 방패병의 85% 감소(frontMult 0.15)와 구분된다. 측·후면과 바닥 피해는 그대로 들어간다.
static func update_elite_blademaster(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	face_toward(e, p.x, p.y, float(d.guardTurn) if String(e.state) == "guard" else 6.0, adv)
	match String(e.state):
		"approach":
			if dist < float(d.minDist): # 붙어 있으면 스스로 거리를 만든다(밀어붙이기 금지 — 멧돼지와 같은 규칙)
				e.state = "backoff"
				e.state_t = 0.0
				return
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and not st.los_blocked(e.x, e.y, p.x, p.y) and elite_may_start(st, e, dt):
				elite_begin(st, e, "dash1_aim", "돌진 베기 1/2", "#ffb0b0")
		"backoff": # 최대 1.2초 물러난다(벽에 막히면 접선). 거리가 벌어지면 돌진 연계로, 끝까지 붙어 있으면 근접 연계(방패 자세 → 내려찍기)로
			e.state_t += dt
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
			if dist >= float(d.minDist) + 30.0:
				e.state = "approach"
				e.state_t = 0.0
			elif float(e.state_t) >= float(d.backoffTime) and elite_may_start(st, e, dt):
				elite_begin(st, e, "guard", "방패 자세(정면 차단)", "#a9d8ff")
		"dash1_aim", "dash2_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			var first: bool = String(e.state) == "dash1_aim"
			e.preview = PBoss.dash_path(st, e, float(e.aim_angle), float(d.dashDist))
			if float(e.state_t) >= (float(d.aim1) if first else float(d.aim2)):
				var path := PBoss.dash_path(st, e, float(e.aim_angle), float(d.dashDist))
				e.dir = e.aim_angle # 방향 확정 — 돌진 중 추적 회전 금지
				e.charge_len = float(path["len"])
				e.charge_end = path.end
				e.charge_dist = 0.0
				e.hit_done = false
				e.state = "dash1_lock" if first else "dash2_lock"
				e.state_t = 0.0
				st.ev("lock")
		"dash1_lock", "dash2_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.lock):
				e.state = "dash1" if String(e.state) == "dash1_lock" else "dash2"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"dash1", "dash2":
			if _charge_step(st, e, float(d.dashSpeed), float(d.dashDamage), "elite_blade", dt, tf):
				if String(e.state) == "dash1":
					e.state = "dash2_aim"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "돌진 베기 2/2", "#ffb0b0")
				else:
					e.state = "guard"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "방패 자세(정면 차단)", "#a9d8ff")
		"guard": # 정면 직접 피해 완전 차단. 방향 전환은 느리다(측·후면이 답)
			e.state_t += adv
			st.approach(e, p.x, p.y, float(d.speed) * float(d.guardSpeed) * sm, dt)
			if float(e.state_t) >= float(d.guardDur):
				elite_begin(st, e, "slam_aim", "내려찍기", "#ff9f43")
		"slam_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.slamAim):
				circle_hit(st, e, e.x + cos(float(e.face)) * float(d.slamOffset), e.y + sin(float(e.face)) * float(d.slamOffset), float(d.slamR), float(d.slamDamage), "elite_slam")
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 확정 경로를 따라 한 단계 돌진(감속되어도 경로·거리 그대로). 반환 true = 끝(거리 도달·충돌)
static func _charge_step(st: CombatState, e: Dictionary, speed: float, dmg: float, src: String, dt: float, tf: float) -> bool:
	var p := st.player
	var remain: float = maxf(0.0, float(e.charge_len) - float(e.charge_dist))
	var stp: float = minf(speed * tf * dt, remain)
	var x0: float = e.x
	var y0: float = e.y
	var mv := st.move_swept(e, cos(float(e.dir)) * stp, sin(float(e.dir)) * stp)
	e.charge_dist = float(e.charge_dist) + PGeom.dist(e.x, e.y, x0, y0)
	if not bool(e.hit_done) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, float(p.r) + float(e.r)):
		e.hit_done = true
		e.bite_t = 0.0
		st.ev("bite")
		st.damage_player(dmg, src, e)
	return float(e.charge_dist) >= float(e.charge_len) - 1e-6 or String(mv.hit) != "" or stp <= 1e-9

# ---------- C. 피의 송곳니(정예 늑대) ----------
## 측면으로 돌아 접근 → 짧은 물기(예고 0.35) → 짧게 이탈 0.5초 → 착지 예고(추적 0.60 + 확정 0.15) →
## 도약 공격 → 빈틈 1.1초. 착지 위치는 leap_lock 시작 때 확정하고 그 뒤 추적하지 않는다.
## 도약이 빗나가면(착지 원 밖) 더 긴 빈틈 1.6초 — '도약 실패 = 공격 기회'.
static func update_elite_fang(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if int(e.get("side", 0)) == 0:
		e.side = -1 if st.rng.next() < 0.5 else 1
	match String(e.state):
		"approach": # 정면이 아니라 옆으로 돌아 붙는다
			if dist > float(d.flankDist):
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			else:
				var n := PGeom.norm(p.x - e.x, p.y - e.y)
				var s: float = float(e.side)
				st.approach(e, p.x - n[0] * 26.0 + (-n[1]) * s * float(d.flankOffset), p.y - n[1] * 26.0 + n[0] * s * float(d.flankOffset), float(d.speed) * sm, dt)
			if dist <= float(d.biteRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "bite_aim", "", "#ffb0b0")
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "elite_bite")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.biteRange) + e.r, "half": PGeom.deg(float(d.biteDeg)) / 2.0, "ttl": 0.14, "enemy": true })
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				st.ev("bite")
				e.state = "backoff"
				e.state_t = 0.0
		"backoff": # 짧게 이탈(도약 거리 확보)
			e.state_t += adv
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.backoffSpeed) * sm, dt)
			if float(e.state_t) >= float(d.backoffTime):
				elite_begin(st, e, "leap_aim", "도약", "#ff9f43")
		"leap_aim": # 착지 지점 예고(추적)
			e.state_t += adv
			e.leap_at = _leap_target(st, e, float(d.leapRange))
			if float(e.state_t) >= float(d.leapAim):
				e.state = "leap_lock"
				e.state_t = 0.0
				e.leap_at = _leap_target(st, e, float(d.leapRange)) # 착지 위치 확정 — 여기서부터 추적하지 않는다
				e.leap_from = [e.x, e.y]
				st.ev("lock")
		"leap_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.leapLock):
				e.state = "leap"
				e.state_t = 0.0
				e.airborne = true
				st.note_attack(e, "execute")
		"leap": # 확정된 착지점까지 포물선 이동(공중이라 밀리지 않는다)
			e.state_t += adv
			var at: Array = e.leap_at
			var fr: Array = e.leap_from
			var k: float = clampf(float(e.state_t) / float(d.leapTime), 0.0, 1.0)
			e.x = float(fr[0]) + (float(at[0]) - float(fr[0])) * k
			e.y = float(fr[1]) + (float(at[1]) - float(fr[1])) * k
			if k >= 1.0:
				e.airborne = false
				var hit := circle_hit(st, e, e.x, e.y, float(d.leapR), float(d.leapDamage), "elite_leap")
				if hit:
					to_recover(st, e, float(d.recover))
				else: # 도약 실패 — 더 긴 빈틈(공격 기회)
					e.state = "stagger"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 26.0, "빗나감 — 큰 빈틈!", "#ffd166")
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.missStagger):
				e.state = "approach"
				e.state_t = 0.0
				e.side = -int(e.side)
		"recover":
			_recover_tick(e, adv)
			if String(e.state) == "approach":
				e.side = -int(e.side)

## 착지 지점: 플레이어 위치(사거리 상한), 지형 안이면 가장 가까운 유효 위치
static func _leap_target(st: CombatState, e: Dictionary, max_range: float) -> Array:
	var p := st.player
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var dd := sqrt(dx * dx + dy * dy)
	var k: float = 1.0 if dd <= max_range or dd < 1e-6 else max_range / dd
	var pos := st.nearest_valid_pos(e.x + dx * k, e.y + dy * k, float(e.r), 160.0)
	return pos if not pos.is_empty() else [e.x, e.y]

# ---------- D. 역병 조율사(정예 포자) ----------
## 포자 3개를 흩어 투척(예고 0.5) → 부풀기 0.9초 → 0.45초 간격 순차 폭발 → 재정비 1.5초.
## 잔류 구름은 수(3)·시간(2.6초) 상한이 있고, 전장 전체를 덮지 않도록 배치 전에 탈출 방향 수를 확인한다.
## 근접(96 이내)에는 예고된 좁은 포자 분출(70°)로 대응한다.
static func update_elite_plaguecaller(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("cast_t"):
		e.cast_t = 0.4
		e.pods = []
	e.cast_t = float(e.cast_t) - dt # 재사용은 상태와 무관하게 흐른다(붙어서 분출만 반복하면 주 연계를 못 보게 되기 때문)
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			# 주 무기는 포자 3개다. 분출은 '붙었는데 아직 포자가 준비되지 않았을 때'의 대응이지 기본 행동이 아니다
			if float(e.cast_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "throw_aim", "포자 3개", "#9cff9c")
				return
			if dist <= float(d.burstRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "burst_aim", "포자 분출", "#9cff9c")
		"throw_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.throwAim):
				e.pods = _place_pods(st, e)
				e.state = "swell"
				e.state_t = 0.0
				st.ev("spore")
				st.ev("hazard_warn")
		"swell": # 부풀기 → 순차 폭발(각 포자의 정해진 시각). 모두 터지면 재정비
			e.state_t += adv
			_update_pods(st, e, d)
			var left := false
			for pod in e.pods:
				if not bool(pod.done):
					left = true
			if not left:
				e.cast_t = float(d.castInterval)
				to_recover(st, e, float(d.recover))
		"burst_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.burstAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.burstRange) + e.r, PGeom.deg(float(d.burstDeg)) / 2.0, float(d.burstDamage), "elite_spore_burst")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.burstRange) + e.r, "half": PGeom.deg(float(d.burstDeg)) / 2.0, "ttl": 0.16, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("spore")
				to_recover(st, e, float(d.burstRecover))
		"recover":
			keep_distance(st, e, d, dt, sm)
			_recover_tick(e, adv)

## 포자 3개 배치: 플레이어 주위에 흩어 놓되, 놓고 나서도 탈출 방향이 minExits개 이상 남는 자리만 쓴다
static func _place_pods(st: CombatState, e: Dictionary) -> Array:
	var d: Dictionary = e.def
	var p := st.player
	var base: float = float(p.face) if bool(p.moving) else atan2(p.y - e.y, p.x - e.x)
	var pods: Array = []
	for i in int(d.podCount):
		var a: float = base + PGeom.deg(float(d.podArcDeg)) * (float(i) - float(int(d.podCount) - 1) / 2.0)
		var cx: float = p.x + cos(a) * float(d.podSpread)
		var cy: float = p.y + sin(a) * float(d.podSpread)
		var pos := st.nearest_valid_pos(clampf(cx, 20.0, st.arena_w - 20.0), clampf(cy, 20.0, st.arena_h - 20.0), 0.0, 120.0)
		if pos.is_empty():
			continue
		var trial := { "x": float(pos[0]), "y": float(pos[1]), "r": float(d.podR) }
		var all: Array = pods.duplicate()
		all.append(trial)
		if _exits_open(st, all, float(d.probe)) < int(d.minExits): # 전장을 통째로 막지 않는다
			continue
		trial["order"] = pods.size() + 1
		trial["land_at"] = st.t + float(d.swell) + float(pods.size()) * float(d.podGap)
		trial["done"] = false
		pods.append(trial)
	return pods

static func _update_pods(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	for pod in e.pods:
		if bool(pod.done) or st.t < float(pod.land_at):
			continue
		pod.done = true
		circle_hit(st, e, float(pod.x), float(pod.y), float(pod.r), float(d.podDamage), "elite_spore")
		var z := st.add_zone("spore", float(pod.x), float(pod.y), float(pod.r) * 0.8, float(d.cloudTtl), float(d.cloudDamage) * float(e.get("tier_dmg", 1.0)))
		z.owner = e
		_trim_clouds(st, e, int(d.maxClouds))
		st.ev("spore")

## 이 개체가 남긴 구름 수 상한(오래된 것부터 제거). 전역 장판 상한(PPacing)과 별개로 개체 몫을 제한한다
static func _trim_clouds(st: CombatState, e: Dictionary, cap: int) -> void:
	var mine := []
	for z in st.zones:
		if String(z.type) == "spore" and z.get("owner") == e:
			mine.append(z)
	while mine.size() > cap:
		var oldest: Dictionary = mine[0]
		for z in mine:
			if float(z.t) > float(oldest.t):
				oldest = z
		st.zones.erase(oldest)
		mine.erase(oldest)

## 플레이어 주위 16방향 중 probe 거리 지점이 위험 원에 덮이지 않은 방향 수(PBoss3.exits_open과 같은 규칙)
static func _exits_open(st: CombatState, dangers: Array, probe: float) -> int:
	var p := st.player
	var free := 0
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var x: float = p.x + cos(a) * probe
		var y: float = p.y + sin(a) * probe
		if x < float(p.r) or y < float(p.r) or x > st.arena_w - float(p.r) or y > st.arena_h - float(p.r):
			continue
		var blocked := false
		for dz in dangers:
			if PGeom.dist(float(dz.x), float(dz.y), x, y) <= float(dz.r) + float(p.r):
				blocked = true
				break
		if not blocked:
			free += 1
	return free

# ---------- E. 사슬 집행자 ----------
## 직선 사슬 예고(추적 0.60 + 확정 0.15) → 발사(사슬은 바위에 막힌다) → 명중 시 짧은 끌기 0.35초 →
## 내려찍기 예고 0.55 + 확정 0.15 → 강타. 끌린 뒤 강타까지 0.70초의 **입력 기회**가 반드시 남는다(고정값, 시험값).
## 빗나가면 회수 빈틈 1.4초. 근접(72 이내)에서 돌면 예고된 횡베기로 대응한다.
static func update_elite_chainbreaker(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			if dist <= float(d.nearDist) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "sweep_aim", "횡베기", "#ffb0b0")
				return
			if dist <= float(d.engageDist) and not st.los_blocked(e.x, e.y, p.x, p.y) and elite_may_start(st, e, dt):
				elite_begin(st, e, "chain_aim", "사슬", "#ffd166")
		"chain_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			e.chain_len = st.beam_length(e.x, e.y, float(e.aim_angle), float(d.chainLen)) # 예고와 실제가 같은 계산(바위에서 끊긴다)
			if float(e.state_t) >= float(d.chainAim):
				e.state = "chain_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 방향 확정
				e.chain_len = st.beam_length(e.x, e.y, float(e.dir), float(d.chainLen))
				e.chain_d = 0.0
				st.ev("lock")
		"chain_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.chainLock):
				e.state = "chain_fly"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"chain_fly": # 사슬 머리가 확정된 직선을 따라 나아간다
			var d0: float = float(e.chain_d)
			e.chain_d = minf(float(e.chain_len), d0 + float(d.chainSpeed) * adv)
			var hx0: float = e.x + cos(float(e.dir)) * d0
			var hy0: float = e.y + sin(float(e.dir)) * d0
			var hx1: float = e.x + cos(float(e.dir)) * float(e.chain_d)
			var hy1: float = e.y + sin(float(e.dir)) * float(e.chain_d)
			if PGeom.seg_circle(hx0, hy0, hx1, hy1, p.x, p.y, float(p.r) + float(d.chainW) / 2.0):
				if st.damage_player(float(d.chainDamage), "elite_chain", e): # 회피·피격 보호로 막히면 끌기도 없다
					e.state = "pull"
					e.state_t = 0.0
					e.pull_from = [p.x, p.y]
					st.ev("bite")
					st.text(p.x, p.y - 34.0, "끌림!", "#ff9f43")
					return
				e.chain_d = float(e.chain_len) # 회피됨 — 회수
			if float(e.chain_d) >= float(e.chain_len) - 1e-6:
				e.state = "retract"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "회수 — 빈틈!", "#ffd166")
		"pull": # 짧은 끌기(장애물·벽은 그대로 막는다)
			e.state_t += adv
			var want: float = float(d.pullTo) + float(e.r) + float(p.r)
			var cur := PGeom.dist(e.x, e.y, p.x, p.y)
			if cur > want:
				var n := PGeom.norm(e.x - p.x, e.y - p.y)
				var stp: float = minf(float(d.pullSpeed) * dt, cur - want)
				st.move_swept(p, n[0] * stp, n[1] * stp, true)
			if float(e.state_t) >= float(d.pullTime):
				# 강타 위치는 **예고 시작 때** 확정한다(예외를 의도적으로 둔다):
				# 끌기로 자리를 강제한 직후이므로, 여기서도 추적하면 회피할 입력 기회가 사라진다.
				# 그래서 slam_aim 0.55 + slam_lock 0.15 = 0.70초 동안 원의 위치가 고정이고 걸어서 벗어날 수 있다.
				e.slam_at = [p.x, p.y]
				elite_begin(st, e, "slam_aim", "강타", "#ff9f43")
		"slam_aim": # 확정된 자리에 원이 고정된 채 0.55초 — 회피할 입력 기회
			e.state_t += adv
			if float(e.state_t) >= float(d.slamAim):
				e.state = "slam_lock"
				e.state_t = 0.0
				st.ev("lock")
		"slam_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.slamLock):
				var at: Array = e.slam_at
				circle_hit(st, e, float(at[0]), float(at[1]), float(d.slamR), float(d.slamDamage), "elite_chain_slam")
				to_recover(st, e, float(d.recover))
		"sweep_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.sweepAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.sweepRange) + e.r, PGeom.deg(float(d.sweepDeg)) / 2.0, float(d.sweepDamage), "elite_chain_sweep")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.sweepRange) + e.r, "half": PGeom.deg(float(d.sweepDeg)) / 2.0, "ttl": 0.16, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("boss_sweep")
				to_recover(st, e, float(d.sweepRecover))
		"retract":
			e.state_t += adv
			if float(e.state_t) >= float(d.retract):
				e.state = "approach"
				e.state_t = 0.0
		"recover":
			_recover_tick(e, adv)

# ---------- F. 군단 기수 ----------
## 파괴 가능한 깃발 설치(예고 0.8) → 범위 안 아군 집결·방어 지원 → 일부 호위에게 돌격 명령 → 재배치.
## **적을 새로 소환하지 않는다**(무한 경험치·금화 공급 금지). 명령은 유한 예산(orderBudget), 깃발도 유한(plantBudget).
## 지휘받은 적도 위험 공격 동시 제한(may_attack)을 그대로 따른다 — 명령은 이동·집결만 바꾼다.
static func update_elite_standard(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var B: Dictionary = d.banner
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("plant_left"):
		e.plant_left = int(d.plantBudget)
		e.order_left = int(B.orderBudget)
		e.order_t = 2.0
		e.banner_ref = null
	var bn = e.get("banner_ref")
	var banner_alive: bool = bn != null and not bool(bn.dead)
	if banner_alive:
		_banner_command(st, e, bn, B, dt)
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.slashRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "slash_aim", "", "#ffb0b0")
				return
			if not banner_alive and int(e.plant_left) > 0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "plant_aim", "깃발 설치", "#e0c060")
		"plant_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.plantAim):
				var ang: float = atan2(e.y - p.y, e.x - p.x)
				var pos := st.nearest_valid_pos(e.x + cos(ang) * float(d.bannerOffset), e.y + sin(ang) * float(d.bannerOffset), 12.0, 120.0)
				if pos.is_empty():
					pos = [e.x, e.y]
				var b := st.spawn_enemy("elite_banner", float(pos[0]), float(pos[1]))
				b.banner_ttl = float(B.ttl)
				b.banner_r = float(B.radius)
				e.banner_ref = b
				e.plant_left = int(e.plant_left) - 1
				st.note_attack(e, "execute")
				st.text(float(pos[0]), float(pos[1]) - 30.0, "깃발", "#e0c060")
				st.fx({ "kind": "burst", "x": float(pos[0]), "y": float(pos[1]), "r": float(B.radius), "ttl": 0.5, "color": "#e0c060" })
				st.ev("wave")
				to_recover(st, e, float(d.recover))
		"slash_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.slashAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.slashRange) + e.r, PGeom.deg(float(d.slashDeg)) / 2.0, float(d.slashDamage), "elite_standard")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.slashRange) + e.r, "half": PGeom.deg(float(d.slashDeg)) / 2.0, "ttl": 0.14, "enemy": true })
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 주기적 호위 돌격 명령(유한 예산). **적을 새로 소환하지 않는다** — 이미 싸우고 있는 적의 이동만 바꾼다.
## 명령받은 적도 위험 공격 동시 제한(may_attack)을 그대로 따른다
static func _banner_command(st: CombatState, e: Dictionary, bn: Dictionary, B: Dictionary, dt: float) -> void:
	e.order_t = float(e.order_t) - dt
	if float(e.order_t) > 0.0 or int(e.order_left) <= 0:
		return
	e.order_t = float(B.orderInterval)
	var cands := []
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.get("boss", false)) or bool(o.get("structure", false)):
			continue
		if PGeom.dist(bn.x, bn.y, o.x, o.y) <= float(B.radius) and not bool(o.get("ordered", false)):
			cands.append(o)
	cands.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var n: int = mini(int(B.orderCount), mini(cands.size(), int(e.order_left)))
	for i in n:
		var o: Dictionary = cands[i]
		o.ordered = true
		o.rally_t = float(B.orderDur) # 명령 지속 동안은 집결보다 빠르다(rally_t가 끝나면 leash_boost가 1.0으로 돌아간다)
		o.leash_boost = float(B.orderSpeed)
		st.text(o.x, o.y - float(o.r) - 26.0, "돌격 명령", "#e0c060")
	if n > 0:
		e.order_left = int(e.order_left) - n
		st.ev("group")

## 깃발(구조물): 살아 있는 동안 범위 안 아군의 집결 상태를 매 단계 새로 칠한다(rally_t 0.25초 갱신).
## 부수거나 수명이 끝나면 갱신이 멈추고 0.25초 안에 저절로 꺼진다 — 죽은 깃발의 효과가 남지 않는다
static func update_banner(st: CombatState, e: Dictionary, dt: float) -> void:
	var B: Dictionary = PCatalog.enemy("elite_standard").banner
	# 깃발 범위와 지휘받는 적을 눈에 보이게 한다(0.6초마다 고리 하나. 전용 그림은 render.gd 담당)
	e.ring_t = float(e.get("ring_t", 0.0)) - dt
	var show: bool = float(e.ring_t) <= 0.0
	if show:
		e.ring_t = 0.6
		st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": float(B.radius), "ttl": 0.55, "color": "#e0c060" })
	for o in st.enemies:
		if bool(o.dead) or bool(o.get("boss", false)) or bool(o.get("structure", false)) or bool(o.get("ordered", false)):
			continue
		if PGeom.dist(e.x, e.y, o.x, o.y) <= float(B.radius):
			o.rally_t = 0.25
			o.leash_boost = float(B.rallySpeed)
			if show:
				st.fx({ "kind": "burst", "x": o.x, "y": o.y, "r": float(o.r) + 8.0, "ttl": 0.4, "color": "#e0c060" })
	e.banner_ttl = float(e.get("banner_ttl", 20.0)) - dt
	if float(e.banner_ttl) <= 0.0:
		e.hp = 0.0
		st.kill_enemy(e, {})

## 깃발 방어 지원: 살아 있는 깃발 범위 안의 일반 적은 직접 피해가 조금 줄어든다(중복 아님 — shield_mult가 min으로 한 번만)
static func _rally_guard(st: CombatState, e: Dictionary) -> bool:
	if bool(e.get("boss", false)) or bool(e.get("structure", false)):
		return false
	for o in st.enemies:
		if bool(o.dead) or String(o.type) != "elite_banner":
			continue
		if PGeom.dist(o.x, o.y, e.x, e.y) <= float(o.get("banner_r", 0.0)):
			return true
	return false

# ---------- G. 균열 채굴자 ----------
## 지하 이동 흔적 → 출현 위치 예고 0.7초 → 솟구치기 → 작은 돌무더기 생성 → 지상 빈틈 1.6초.
## 출현 위치는 warn 시작 때 확정하고 그 뒤 추적하지 않는다. 지하 구간은 최소 0.6 / 최대 1.6초로 제한해
## '지하에만 오래 숨어 시간 끌기'를 막는다. 돌무더기는 파괴 가능하고 수(4)·수명(8초) 상한이 있으며,
## 놓은 뒤에도 플레이어 주위 탈출 방향이 minExits개 이상 남는 자리에만 놓는다.
static func update_elite_miner(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("burrow_cd"):
		e.burrow_cd = 1.2
	if String(e.state) != "under" and String(e.state) != "dive" and String(e.state) != "warn":
		e.burrow_cd = float(e.burrow_cd) - dt
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and float(e.burrow_cd) <= 0.0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "dive", "잠행", "#c8a06a")
			elif dist <= float(d.biteRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "bite_aim", "", "#ffb0b0")
		"dive":
			e.state_t += adv
			if float(e.state_t) >= float(d.dive):
				e.state = "under"
				e.state_t = 0.0
				e.hidden = true
		"under": # 지하 이동 흔적(추적 허용). 최소·최대 시간 안에서만 머문다
			e.state_t += adv
			var n := PGeom.norm(p.x - e.x, p.y - e.y)
			st.move_swept(e, n[0] * float(d.underSpeed) * sm * dt, n[1] * float(d.underSpeed) * sm * dt, true)
			e.trail_t = float(e.get("trail_t", 0.0)) - dt # 지하 이동 흔적: 0.12초마다 하나(매 단계 만들면 화면이 덮인다)
			if float(e.trail_t) <= 0.0:
				e.trail_t = 0.12
				st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": 12.0, "ttl": 0.35, "color": "#a08050" })
			if float(e.state_t) >= float(d.underMax) or (float(e.state_t) >= float(d.underMin) and dist < 40.0):
				var pos := st.nearest_valid_pos(e.x, e.y, float(e.r), 200.0)
				if pos.is_empty():
					pos = [e.x, e.y]
				e.emerge_at = pos # 출현 위치 확정 — 그 뒤 추적하지 않는다
				e.state = "warn"
				e.state_t = 0.0
				st.ev("lock")
				st.ev("hazard_warn")
		"warn":
			e.state_t += adv
			if float(e.state_t) >= float(d.warn):
				var at: Array = e.emerge_at
				e.x = float(at[0])
				e.y = float(at[1])
				e.hidden = false
				e.state = "erupt"
				e.state_t = 0.0
				circle_hit(st, e, e.x, e.y, float(d.eruptR), float(d.eruptDamage), "elite_erupt")
				_place_rubble(st, e, d)
				e.burrow_cd = float(d.cooldown)
		"erupt":
			e.state_t += adv
			if float(e.state_t) >= 0.15:
				e.state = "stagger"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "빈틈!", "#ffd166")
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.exposed):
				e.state = "approach"
				e.state_t = 0.0
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "elite_pick")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.biteRange) + e.r, "half": PGeom.deg(float(d.biteDeg)) / 2.0, "ttl": 0.14, "enemy": true })
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.biteRecover))
		"recover":
			_recover_tick(e, adv)

## 돌무더기 배치: 전역 상한(rockMax)과 탈출 방향 검사를 통과한 자리에만. 시작점·목표·출구를 막지 않는다
static func _place_rubble(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	var p := st.player
	var live := rubble_count(st)
	var placed := 0
	for i in int(d.rockCount):
		if live + placed >= int(d.rockMax):
			break
		var a: float = atan2(p.y - e.y, p.x - e.x) + PGeom.deg(70.0) * (1.0 if i % 2 == 0 else -1.0)
		var cx: float = e.x + cos(a) * (float(d.eruptR) * 0.9)
		var cy: float = e.y + sin(a) * (float(d.eruptR) * 0.9)
		var pos := st.nearest_valid_pos(clampf(cx, 30.0, st.arena_w - 30.0), clampf(cy, 30.0, st.arena_h - 30.0), float(d.rockR) + 4.0, 120.0)
		if pos.is_empty():
			continue
		var dangers := [{ "x": float(pos[0]), "y": float(pos[1]), "r": float(d.rockR) }]
		for o in st.enemies:
			if not o.dead and String(o.type) == "elite_rubble":
				dangers.append({ "x": o.x, "y": o.y, "r": float(o.r) })
		if _exits_open(st, dangers, float(d.probe)) < int(d.minExits): # 유일한 탈출로를 막지 않는다
			continue
		var rk := st.spawn_enemy("elite_rubble", float(pos[0]), float(pos[1]))
		rk.rubble_ttl = float(d.rockTtl)
		placed += 1
	if placed > 0:
		st.ev("boss_land")

static func rubble_count(st: CombatState) -> int:
	var n := 0
	for o in st.enemies:
		if not o.dead and String(o.type) == "elite_rubble":
			n += 1
	return n

## 돌무더기(구조물): 수명이 끝나면 무너진다. 그 전에 부술 수도 있다
static func update_rubble(st: CombatState, e: Dictionary, dt: float) -> void:
	e.rubble_ttl = float(e.get("rubble_ttl", 8.0)) - dt
	if float(e.rubble_ttl) <= 0.0:
		e.hp = 0.0
		st.kill_enemy(e, {})

# ---------- 봇용 위협 도형(화면에 보이는 예고와 같은 정보만) ----------
static func threats(st: CombatState, e: Dictionary, out: Array) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var type := String(e.type)
	var state := String(e.state)
	if type == "boar":
		var pv: Dictionary = e.get("preview", {})
		if state == "charge_aim" and not pv.is_empty():
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": float(pv["len"]) + 30.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": float(e.state_t) / float(d.aim), "locked": false })
		elif state == "charge_lock" or state == "charge":
			var cl: float = float(e.get("charge_len", 0.0))
			if cl <= 0.0:
				cl = float(d.chargeDist)
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": cl + 30.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": 1.0, "locked": true })
	elif type == "shieldbearer" and state == "bash_aim":
		var prog: float = float(e.state_t) / float(d.aim)
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.face, "r": float(d.bashRange) + float(d.lunge) + 20.0, "half": PGeom.deg(float(d.bashDeg)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.6 })
	elif type == "shaman" and state == "hex_aim":
		var prog: float = float(e.state_t) / float(d.hexAim)
		out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": 2000.0, "w": 40.0, "prog": prog, "locked": prog > 0.7 })
	elif type == "bomber" and state == "fuse":
		out.append({ "kind": "circle", "e": e, "x": e.x, "y": e.y, "r": float(d.blastR), "prog": float(e.state_t) / float(d.fuse), "locked": true })
	elif type == "burrower" and state == "warn" and e.has("emerge_at"):
		var at: Array = e.emerge_at
		out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": float(d.emergeR), "prog": float(e.state_t) / float(d.warn), "locked": true })
	elif (type == "burrower" or type == "spider") and state == "bite_aim":
		var prog: float = float(e.state_t) / float(d.biteAim)
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.6 })
	elif type == "rogue" and (state == "slash1_aim" or state == "slash2_aim"):
		var prog: float = float(e.state_t) / (float(d.aim1) if state == "slash1_aim" else float(d.aim2))
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.slashRange) + e.r + 10.0, "half": PGeom.deg(float(d.slashDeg)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.5 })
	elif is_elite(type):
		elite_threats(st, e, out)

## 특수 정예 7종의 예고 도형(화면 표시와 같은 기하). 확정(locked) 뒤에는 추적하지 않는다
static func elite_threats(st: CombatState, e: Dictionary, out: Array) -> void:
	var d: Dictionary = e.def
	var p := st.player
	var state := String(e.state)
	var w: float = (float(e.r) + float(p.r)) * 2.0 + 30.0
	match String(e.type):
		"elite_archer":
			if state == "aim":
				var need: float = float(d.aim) if int(e.get("shot_left", 1)) == int(d.shots) else float(d.reaim)
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": 2000.0, "w": 40.0, "prog": float(e.state_t) / need, "locked": false })
			elif state == "shot_lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": 2000.0, "w": 40.0, "prog": 1.0, "locked": true })
			elif state == "fan_aim" or state == "fan_lock":
				var ang: float = float(e.aim_angle) if state == "fan_aim" else float(e.dir)
				var half: float = PGeom.deg(float(d.fanDeg)) * (float(int(d.fanCount) - 1) / 2.0) + 0.12
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": 900.0, "half": half, "prog": (float(e.state_t) / float(d.fanAim)) if state == "fan_aim" else 1.0, "locked": state == "fan_lock" })
		"elite_blademaster":
			if state == "dash1_aim" or state == "dash2_aim":
				var pv: Dictionary = e.get("preview", {})
				var L: float = float(pv["len"]) if not pv.is_empty() else float(d.dashDist)
				var need2: float = float(d.aim1) if state == "dash1_aim" else float(d.aim2)
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": L + 30.0, "w": w, "prog": float(e.state_t) / need2, "locked": false })
			elif state == "dash1_lock" or state == "dash2_lock" or state == "dash1" or state == "dash2":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": maxf(0.0, float(e.get("charge_len", 0.0)) - float(e.get("charge_dist", 0.0))) + 30.0, "w": w, "prog": 1.0, "locked": true })
			elif state == "slam_aim":
				out.append({ "kind": "circle", "e": e, "x": e.x + cos(float(e.get("face", 0.0))) * float(d.slamOffset), "y": e.y + sin(float(e.get("face", 0.0))) * float(d.slamOffset), "r": float(d.slamR), "prog": float(e.state_t) / float(d.slamAim), "locked": true })
		"elite_fang":
			if state == "bite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.biteAim), "locked": float(e.state_t) / float(d.biteAim) > 0.6 })
			elif (state == "leap_aim" or state == "leap_lock" or state == "leap") and e.has("leap_at"):
				var at: Array = e.leap_at
				out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": float(d.leapR), "prog": (float(e.state_t) / float(d.leapAim)) if state == "leap_aim" else 1.0, "locked": state != "leap_aim" })
		"elite_plaguecaller":
			if state == "burst_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.burstRange) + e.r + 10.0, "half": PGeom.deg(float(d.burstDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.burstAim), "locked": float(e.state_t) / float(d.burstAim) > 0.6 })
			elif state == "swell":
				for pod in e.get("pods", []):
					if bool(pod.done):
						continue
					var left: float = maxf(0.0, float(pod.land_at) - st.t)
					out.append({ "kind": "circle", "e": e, "x": float(pod.x), "y": float(pod.y), "r": float(pod.r), "prog": 1.0 - left / maxf(0.001, float(d.swell)), "locked": true, "order": int(pod.order) })
		"elite_chainbreaker":
			if state == "chain_aim" or state == "chain_lock":
				var cl: float = float(e.get("chain_len", float(d.chainLen)))
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.aim_angle) if state == "chain_aim" else float(e.dir), "len": cl, "w": float(d.chainW), "prog": (float(e.state_t) / float(d.chainAim)) if state == "chain_aim" else 1.0, "locked": state == "chain_lock" })
			elif state == "chain_fly":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": float(e.get("chain_d", 0.0)), "w": float(d.chainW), "prog": 1.0, "locked": true })
			elif (state == "slam_aim" or state == "slam_lock") and e.has("slam_at"):
				var sat: Array = e.slam_at
				out.append({ "kind": "circle", "e": e, "x": float(sat[0]), "y": float(sat[1]), "r": float(d.slamR), "prog": (float(e.state_t) / float(d.slamAim)) if state == "slam_aim" else 1.0, "locked": true })
			elif state == "sweep_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.sweepRange) + e.r + 10.0, "half": PGeom.deg(float(d.sweepDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.sweepAim), "locked": float(e.state_t) / float(d.sweepAim) > 0.6 })
		"elite_standard":
			if state == "slash_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.slashRange) + e.r + 10.0, "half": PGeom.deg(float(d.slashDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.slashAim), "locked": float(e.state_t) / float(d.slashAim) > 0.6 })
		"elite_miner":
			if state == "warn" and e.has("emerge_at"):
				var mat: Array = e.emerge_at
				out.append({ "kind": "circle", "e": e, "x": float(mat[0]), "y": float(mat[1]), "r": float(d.eruptR), "prog": float(e.state_t) / float(d.warn), "locked": true })
			elif state == "bite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.biteAim), "locked": float(e.state_t) / float(d.biteAim) > 0.6 })

static func zone_threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "frostzone":
			out.append({ "kind": "circle", "x": z.x, "y": z.y, "r": z.r, "prog": 1.0 - float(z.ttl) / float(z.max_ttl), "locked": float(z.ttl) < 0.45 })
		elif z.type == "web":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r, "web": true })
