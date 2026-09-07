class_name PEnemiesNew
extends RefCounted
## 신규 기본 몬스터 8종(HTML enemies.js 이식): 멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적.
## PEnemies.update가 has(type)인 개체에 update를 호출한다. 공통 규칙: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음.
## 상호작용: 감속장은 준비·실행·빈틈 진행(tf)을 늦추고, 냉기는 이동만 늦춘다. 넉백은 돌진·잠복·도약 중에는 무시(combat_state.knock_enemy), 방패병은 50%(def.knockMult).
## 면역(최소 범위): 잠복충 지하 구간(hidden)은 직접 공격·투사체 대상이 되지 않는다(바닥 효과는 적용). 그 외 면역 없음.
## 개체별 추가 필드(snake_case, 지연 초기화): face, preview, charge_len, charge_end, charge_blocked, charge_dist, hit_done, heal_t, hex_t, cast_target, cast_pts, cast_t,
##   burrow_cd, emerge_at, web_t, web_at, side, base_dir, exploded

const COMMITTED := {
	"boar": ["charge_aim", "charge_lock", "charge"],
	"shieldbearer": ["bash_aim", "bash"],
	"shaman": ["cast", "hex_aim"],
	"bomber": ["fuse"],
	"burrower": ["dive", "under", "warn", "emerge", "bite_aim"],
	"spider": ["web_aim", "bite_aim"],
	"frostcaller": ["cast"],
	"rogue": ["slash1_aim", "slash2_aim"],
}

static func has(type: String) -> bool:
	return COMMITTED.has(type)

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

## 방패 판정: 방패가 닫혀 있고(접근·이동 중) 공격 출처가 정면 부채꼴 안이면 30%. 출처 위치가 없는 바닥·추가 효과는 정상 피해
static func shield_mult(st: CombatState, e: Dictionary, opt: Dictionary) -> float:
	if String(e.type) != "shieldbearer" or not e.has("face"):
		return 1.0
	if e.state == "bash_aim" or e.state == "bash" or e.state == "recover": # 방패 열림
		return 1.0
	var sr: Dictionary = opt.get("src", {})
	# 방패는 직접 공격(무기 본체·투사체)만 막는다. 바닥·추가·기술·지속 피해는 정상
	if not bool(sr.get("direct", true)) or bool(sr.get("extra", false)) or bool(sr.get("skill", false)) or opt.has("dot"):
		return 1.0
	var from: Dictionary = opt.get("from", st.player)
	var a: float = atan2(float(from.y) - e.y, float(from.x) - e.x)
	if absf(PGeom.ang_diff(float(e.face), a)) <= PGeom.deg(float(e.def.frontDeg)) / 2.0:
		return float(e.def.frontMult)
	return 1.0

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
				st.projectiles.append({ "owner": "enemy", "kind": "hex", "shooter": e, "x": e.x + cos(ang) * (e.r + 4.0), "y": e.y + sin(ang) * (e.r + 4.0), "vx": cos(ang) * float(d.hexSpeed), "vy": sin(ang) * float(d.hexSpeed), "r": float(d.hexR), "dmg": float(d.hexDamage), "ttl": 4.0, "angle": ang, "dead": false, "hits": {} })
				st.ev("shoot")
				st.note_attack(e, "execute")
				e.hex_t = float(d.hexInterval)
				to_recover(st, e, float(d.recover), false)
		"recover":
			_recover_tick(e, adv)

## 시전 방해: 12 이상 한 방 또는 넉백(20 이상)이면 끊긴다. 처치는 당연히 끊는다.
static func on_damaged(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary) -> void:
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
					z.dmg = float(d.damage)
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

static func zone_threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "frostzone":
			out.append({ "kind": "circle", "x": z.x, "y": z.y, "r": z.r, "prog": 1.0 - float(z.ttl) / float(z.max_ttl), "locked": float(z.ttl) < 0.45 })
		elif z.type == "web":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r, "web": true })
