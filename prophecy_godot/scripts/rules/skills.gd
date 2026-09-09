class_name PSkills
extends RefCounted
## 수동 기술(HTML skills.js 이식): Q 감속장(레벨·변형 3) + E 선택 기술(5종, 레벨·변형). 기술 피해에는 무기 숙련이 적용되지 않는다.
## 감속장 수치(반지름·지속·감속)는 cfg.player.slowfield(첫 전투 호환), 재사용은 build.special_cd(레벨·집중·박자·샘).

## 선택 계측(도구 전용, 읽기만 한다): probe가 null이 아니면 중력핵의 사용·끌기·틱·붕괴·종료를 그대로 알려준다.
## null이면 훅 자체가 실행되지 않는다 — 판정·수명·피해·난수를 바꾸지 않는다(PHitRecorder와 같은 방식).
## 쓰는 곳: tools/gravity_probe.gd. 쓰고 나면 반드시 다시 null로 되돌린다.
static var probe = null

static func _tell(st: CombatState, g: Dictionary, ev: String, data: Dictionary = {}) -> void:
	if probe != null:
		probe.on_gravity(st, g, ev, data)

## 중력핵 조절값(data/growth.json의 skills.gravity.tune). 표에 없는 값은 지금까지의 규칙 그대로다 —
## tune이 아예 없으면 동작이 하나도 바뀌지 않는다. 시험안을 하드코딩하지 않고 데이터에서 읽기 위한 통로다.
##  dur 유지 시간(초) · radius 반지름 · pull_base 끌어당김 기본 속도(레벨 계수 pull과 곱한다) · tick 피해 간격(초, 피해는 dps×간격이라 DPS는 그대로)
##  collapse_r/collapse_mult 변형 '붕괴'의 마무리 폭발 · base_collapse_mult 기본형 마무리 폭발(0이면 없음) · boss_mult 보스에게 주는 틱 피해 배수
static func gravity_tune() -> Dictionary:
	var SK := PCatalog.skills()
	var T: Dictionary = (SK.get("gravity", {}) as Dictionary).get("tune", {})
	return { "dur": float(T.get("dur", 1.2)), "radius": float(T.get("radius", 140.0)), "pull_base": float(T.get("pull_base", 90.0)),
		"tick": float(T.get("tick", 0.25)), "collapse_r": float(T.get("collapse_r", 100.0)), "collapse_mult": float(T.get("collapse_mult", 3.0)),
		"base_collapse_mult": float(T.get("base_collapse_mult", 0.0)), "boss_mult": float(T.get("boss_mult", 1.0)) }

static func init(st: CombatState) -> void:
	st.skill_state = { "storm": {}, "gravity": {}, "ward": {}, "target": null, "field2": {} }
	st.player.e_cd = 0.0

static func cd_of(st: CombatState, slot: String) -> float:
	var sk = st.build.skills.get(slot)
	if sk == null:
		return 0.0
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	var mult: float = float(st.build.skill_cd_mult)
	if slot == "e":
		mult *= float(st.build.get("e_cd_mult", 1.0)) # 특성 '수동기술 운용'(없으면 ×1.0)
	return float(d.cooldown[mini(3, int(sk.level)) - 1]) * mult

## 특성 '연계 준비'의 E 피해·흡수 감소(없으면 1.0)
static func link_skill_mult(st: CombatState) -> float:
	if st.build.has("trait_dmg") and (st.build.trait_dmg as Dictionary).has("link_skill_mult"):
		return float(st.build.trait_dmg.link_skill_mult)
	return 1.0

static func sdmg(st: CombatState, slot: String) -> float:
	var sk = st.build.skills.get(slot)
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	if d.has("damage"):
		return float(d.damage[mini(3, int(sk.level)) - 1])
	return 0.0

static func hit(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary = {}) -> float:
	var o := opt.duplicate()
	var eid := String(st.build.skills.e.id) if st.build.skills.get("e") != null else "e"
	o.src = { "skill": true, "direct": false, "skill_id": eid }
	return st.damage_enemy(e, dmg * link_skill_mult(st), o)

# ---------- Q 감속장 ----------
static func cast_q(st: CombatState) -> void:
	var p := st.player
	var S: Dictionary = st.cfg.player.slowfield
	var b := st.build
	var sk = b.skills.get("q")
	var variant: String = String(sk.variant) if sk != null and sk.get("variant") != null else ""
	if not st.field.is_empty():
		st.end_field()
	var dur := float(S.duration) * float(b.duration_mult)
	if variant == "split":
		st.field = { "x": p.x, "y": p.y, "r": 100.0, "ttl": dur, "max_ttl": dur, "follow": false }
		var far := {}
		var bd := INF
		for e in st.alive_targets():
			var d := PGeom.dist(e.x, e.y, p.x, p.y)
			if d > 60.0 and d < bd:
				bd = d
				far = e
		st.skill_state.field2 = { "x": far.x, "y": far.y, "r": 100.0, "ttl": dur, "max_ttl": dur } if not far.is_empty() else {}
	else:
		st.field = { "x": p.x, "y": p.y, "r": float(S.radius), "ttl": dur, "max_ttl": dur, "follow": variant == "follow" }
	p.special_cd = maxf(1.0, float(b.special_cd))
	st.stats.special_uses += 1
	if (b.equip as Dictionary).has("relay"):
		st.relay_window = float(b.equip.relay.window) # 연계 방패: Q 뒤 E까지 허용 창
	st.ev("special")
	st.text(p.x, p.y - 50.0, "감속장", "#a9d8ff")

static func on_field_end(st: CombatState, f: Dictionary) -> void:
	var sk = st.build.skills.get("q")
	if sk != null and sk.get("variant") != null and String(sk.variant) == "echo":
		st.add_zone("slowecho", f.x, f.y, f.r, 1.5, 0.0)
	st.skill_state.field2 = {}

static func in_field2(st: CombatState, ox: float, oy: float, orad: float) -> bool:
	if st.skill_state.is_empty():
		return false
	var f: Dictionary = st.skill_state.get("field2", {})
	return not f.is_empty() and PGeom.dist(f.x, f.y, ox, oy) <= f.r + orad

# ---------- E ----------
## 돌풍(E)의 부채꼴 기하. 조준·판정·표시가 모두 이 두 값만 쓴다(한 곳에서만 정한다).
## 값은 예전과 같다 — 이번 조준 수정은 거리·폭을 바꾸지 않는다.
const GUST_LEN := 170.0
const GUST_W := 120.0

static func auto_target(st: CombatState, range_v: float) -> Dictionary:
	var p := st.player
	var mk = st.mark_target
	if mk != null and not mk.dead and PGeom.dist(p.x, p.y, mk.x, mk.y) <= range_v + mk.r:
		return mk
	var alive := st.alive_targets()
	for e in alive:
		if e.elite and PGeom.dist(p.x, p.y, e.x, e.y) <= range_v + e.r:
			return e
	var best := {}
	var bd := INF
	for e in alive:
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d <= range_v + e.r and d < bd:
			bd = d
			best = e
	return best

static func cluster(st: CombatState, range_v: float) -> Dictionary:
	var p := st.player
	var list := []
	for e in st.alive_targets():
		if not e.boss and PGeom.dist(p.x, p.y, e.x, e.y) <= range_v:
			list.append(e)
	if list.is_empty():
		var tg := auto_target(st, range_v)
		return { "x": tg.x, "y": tg.y } if not tg.is_empty() else {}
	var sx := 0.0
	var sy := 0.0
	for e in list:
		sx += e.x
		sy += e.y
	return { "x": sx / float(list.size()), "y": sy / float(list.size()) }

static func push_enemy(st: CombatState, e: Dictionary, dir: Array, amount: float) -> void:
	if e.boss or bool(e.airborne):
		return
	st.move_swept(e, dir[0] * amount, dir[1] * amount)
	if e.state == "dash":
		e.state = "recover"
		e.state_t = 0.0

## 돌풍(E) 전용 조준 ①: 사용 순간의 '유효한 가까운 적'을 고른다.
##
## 왜 p.face를 쓰지 않는가 — face는 이동하면 매 프레임 이동 방향으로(combat_state.gd:1952),
## 자동공격이 나가면 그 대상 방향으로(weapons.gd:176·212·323·363·377) 덮인다.
## 한 단계 순서가 이동 → cast_e → 자동공격이라 **이동 중에는 언제나 이동 방향으로 나갔다**
## (발사 267회의 조준 오차 중앙값 90~150도, 발당 유효 적중 1.22 → 자동 조준 뒤 1.70 — docs/sim/PROBE_GUST.md).
##
## '유효한 적' = 이 돌풍이 실제로 때릴 수 있는 적. 아래 판정과 **같은 조건**만 쓴다:
##  ① 살아 있고 숨지 않았다(alive_targets)
##  ② 구조물·공중이 아니다(밀어낼 수 없는 것에 조준을 뺏기지 않는다)
##  ③ 부채꼴 사거리 안이다 — 중심 거리 ≤ GUST_LEN + 적 반지름(in_beam의 사거리 조건과 같다)
##  ④ 장애물에 가리지 않았다 — st.los_blocked, 아래 적중 판정에 쓰는 그 검사 그대로
## 그래서 여기서 고른 적은 **반드시 맞는다**(그 방향으로 쏘면 ③④가 그대로 성립한다).
##
## 고르는 규칙: 조건을 만족하는 적 중 **중심 거리가 가장 짧은 하나**.
## 동점이면 st.enemies에 먼저 들어온 적(등장 순서)을 고른다 — 난수를 쓰지 않아 언제나 같은 답이다.
static func gust_target(st: CombatState) -> Dictionary:
	var p := st.player
	var best := {}
	var bd := INF
	for e in st.alive_targets():
		if bool(e.get("structure", false)) or bool(e.get("airborne", false)):
			continue
		var d: float = PGeom.dist(p.x, p.y, e.x, e.y)
		if d > GUST_LEN + float(e.r) or d >= bd:
			continue
		if st.los_blocked(p.x, p.y, e.x, e.y):
			continue
		bd = d
		best = e
	return best

## 돌풍(E) 전용 조준 ②: 실제로 나갈 각.
## 유효한 적이 없으면(사거리 밖·벽 뒤·구조물뿐·적 없음) **마지막으로 바라보던 방향**(p.face)으로 그대로 나간다.
## p.face의 뜻은 건드리지 않는다 — 여기서 읽기만 하고, 돌풍이 face에 쓰는 일은 없다.
static func gust_angle(st: CombatState) -> float:
	var p := st.player
	var tg := gust_target(st)
	if tg.is_empty():
		return float(p.face)
	return atan2(float(tg.y) - float(p.y), float(tg.x) - float(p.x))

static func cast_e(st: CombatState) -> bool:
	var p := st.player
	var b := st.build
	var sk = b.skills.get("e")
	if sk == null:
		return false
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	var v: String = String(sk.variant) if sk.get("variant") != null else ""
	var dmg := sdmg(st, "e")
	var S := st.skill_state
	var lv := mini(3, int(sk.level))
	match String(sk.id):
		"gust":
			# 조준각은 **사용 순간에 한 번** 정한다. 아래의 적중 판정·밀어내기·바람길 자리·
			# 표시(fx.angle = 화면에 그리는 부채꼴)가 전부 이 하나의 값을 쓰므로 표시와 판정이 어긋날 수 없다.
			# 이동 방향은 이 계산에 들어오지 않는다 — 그래서 이동 중에도 조준이 덮이지 않는다.
			var ang: float = gust_angle(st)
			if v == "whirl":
				st.fx({ "kind": "gust", "x": p.x, "y": p.y, "r": 130.0, "whirl": true, "ttl": 0.3 })
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, p.x, p.y) <= 130.0 + e.r:
						hit(st, e, dmg)
						push_enemy(st, e, PGeom.norm(e.x - p.x, e.y - p.y), 140.0 + 30.0 * float(lv - 1))
			else:
				st.fx({ "kind": "gust", "x": p.x, "y": p.y, "angle": ang, "len": GUST_LEN, "w": GUST_W, "ttl": 0.3 })
				for e in st.alive_targets():
					if PGeom.in_beam(p.x, p.y, ang, GUST_LEN, GUST_W, e.x, e.y, e.r) and not st.los_blocked(p.x, p.y, e.x, e.y):
						hit(st, e, dmg)
						push_enemy(st, e, [cos(ang), sin(ang)], 140.0 + 30.0 * float(lv - 1))
			if v == "windpath":
				for i in 3:
					var pos := st.nearest_valid_pos(p.x + cos(ang) * 55.0 * float(i), p.y + sin(ang) * 55.0 * float(i), 0.0, 60.0)
					if not pos.is_empty():
						st.add_zone("windpath", pos[0], pos[1], 40.0, 3.0, 0.0)
		"bladestorm":
			S.storm = { "x": p.x, "y": p.y, "t": 1.2, "tick": 0.0, "r": 70.0 if v == "condensed" else 110.0, "dmg": dmg * (1.8 if v == "condensed" else 1.0), "advancing": v == "advancing", "dir": [cos(p.face), sin(p.face)] }
		"strike":
			var tg := auto_target(st, 260.0)
			if tg.is_empty():
				return false
			var at := { "x": tg.x, "y": tg.y }
			st.fx({ "kind": "strikewarn", "x": at.x, "y": at.y, "r": 45.0, "ttl": 0.25 })
			st.text(at.x, at.y - 30.0, "낙뢰", "#fff3a0")
			st.delayed.append({ "t": 0.25, "fn": func():
				bolt_at(st, at, 45.0, dmg)
				if v == "chain":
					var others := []
					for e in st.alive_targets():
						var dd := PGeom.dist(e.x, e.y, at.x, at.y)
						if dd <= 150.0 and dd > 20.0 and others.size() < 2:
							others.append(e)
					for o in others:
						var oa := { "x": o.x, "y": o.y }
						st.delayed.append({ "t": 0.15, "fn": func(): bolt_at(st, oa, 40.0, dmg * 0.5) })
				if v == "storm":
					var z := st.add_zone("storm", at.x, at.y, 50.0, 2.0, dmg * 0.3)
					z.tick = 0.5 })
		"gravity":
			var c := cluster(st, 260.0)
			if c.is_empty():
				return false
			var GT := gravity_tune()
			S.gravity = { "x": c.x, "y": c.y, "t": float(GT.dur), "hold": 1.0 if v == "orbit" else 0.0, "r": float(GT.radius), "pull": float(GT.pull_base) * float(d.pull[lv - 1]), "dps": dmg, "tick": 0.0, "collapse": v == "collapse", "dmg": dmg,
				"tick_iv": float(GT.tick), "cr": float(GT.collapse_r), "cm": (float(GT.collapse_mult) if v == "collapse" else float(GT.base_collapse_mult)), "boss_mult": float(GT.boss_mult) }
			_tell(st, S.gravity, "cast", { "level": lv, "variant": v })
		"ward":
			var amt := float(d.shield[lv - 1]) * link_skill_mult(st)
			S.ward = { "t": 4.0, "amt": amt, "fortress": v == "fortress", "pulse": v == "pulse", "pulse_t": 0.0 }
			p.ward_shield = float(p.ward_shield) + amt
			p.shield += amt
			p.shield_max = maxf(p.shield_max, p.shield)
			st.fx({ "kind": "burst", "x": p.x, "y": p.y, "r": 40.0, "ttl": 0.3, "color": "#7ef2ff" })
	p.e_cd = cd_of(st, "e")
	st.stats.e_uses += 1
	if b.has("trait_dmg") and (b.trait_dmg as Dictionary).has("link_window"):
		st.link_t = float(b.trait_dmg.link_window) # 특성 '연계 준비': 중첩 없이 시간만 갱신(피해 없는 E도 발동)
	var EQ: Dictionary = b.equip
	if EQ.has("eShield") and st.caster_cd <= 0.0:
		st.caster_cd = float(EQ.eShield.cd)
		var prev: float = float(st.caster_shield.amt) if not st.caster_shield.is_empty() else 0.0
		p.shield = p.shield - prev + float(EQ.eShield.shield)
		st.caster_shield = { "amt": float(EQ.eShield.shield), "t": float(EQ.eShield.dur) }
		p.shield_max = maxf(p.shield_max, p.shield)
		st.stats.equip_procs.caster_shield = int(st.stats.equip_procs.get("caster_shield", 0)) + 1
	if EQ.has("relay") and st.relay_window > 0.0 and st.relay_cd <= 0.0: # 연계 방패: Q 뒤 창 안의 E → 보호막(잔량은 새 보호막으로 대체)
		st.relay_cd = float(EQ.relay.cd)
		st.relay_window = 0.0
		var prev_r: float = float(st.relay_shield.amt) if not st.relay_shield.is_empty() else 0.0
		p.shield = p.shield - prev_r + float(EQ.relay.shield)
		st.relay_shield = { "amt": float(EQ.relay.shield), "t": float(EQ.relay.dur) }
		p.shield_max = maxf(p.shield_max, p.shield)
		st.stats.equip_procs.relay_shield = int(st.stats.equip_procs.get("relay_shield", 0)) + 1
	st.ev("skill_e", { "id": String(sk.id) })
	st.text(p.x, p.y - 62.0, String(d.name), "#ffe9a8")
	if (b.boss_rewards as Array).has("volley"):
		PWeapons.volley(st)
	return true

static func bolt_at(st: CombatState, at: Dictionary, r: float, dmg: float) -> void:
	st.fx({ "kind": "strike", "x": at.x, "y": at.y, "r": r, "ttl": 0.3 })
	for e in st.alive_targets():
		if PGeom.dist(e.x, e.y, at.x, at.y) <= r + e.r:
			hit(st, e, dmg)
	st.ev("explode")

static func update(st: CombatState, dt: float) -> void:
	var p := st.player
	var S := st.skill_state
	if S.is_empty():
		return
	if p.e_cd > 0.0:
		p.e_cd = maxf(0.0, p.e_cd - dt)
	if not st.field.is_empty() and bool(st.field.get("follow", false)):
		st.field.x = p.x
		st.field.y = p.y
	var f2: Dictionary = S.get("field2", {})
	if not f2.is_empty():
		f2.ttl = float(f2.ttl) - dt
		if float(f2.ttl) <= 0.0:
			S.field2 = {}
	var sk = st.build.skills.get("e")
	if sk != null and (String(sk.id) == "strike" or String(sk.id) == "gravity") and p.e_cd <= 0.0:
		var tg: Dictionary = auto_target(st, 260.0) if String(sk.id) == "strike" else cluster(st, 260.0)
		S.target = { "x": tg.x, "y": tg.y } if not tg.is_empty() else null
	else:
		S.target = null
	var storm: Dictionary = S.get("storm", {})
	if not storm.is_empty():
		storm.t = float(storm.t) - dt
		if bool(storm.advancing):
			storm.x += storm.dir[0] * 150.0 * dt
			storm.y += storm.dir[1] * 150.0 * dt
		else:
			storm.x = p.x
			storm.y = p.y
		storm.tick = float(storm.tick) - dt
		if float(storm.tick) <= 0.0:
			storm.tick = 0.2
			for e in st.alive_targets():
				if PGeom.dist(e.x, e.y, storm.x, storm.y) <= float(storm.r) + e.r:
					hit(st, e, float(storm.dmg), { "dir": PGeom.norm(e.x - storm.x, e.y - storm.y), "knock": 8.0 })
		if float(storm.t) <= 0.0:
			S.storm = {}
	var g: Dictionary = S.get("gravity", {})
	if not g.is_empty():
		g.t = float(g.t) - dt
		var active: bool = float(g.t) > -float(g.hold)
		var pulled: Array = [] # 계측 전용(probe가 null이면 그대로 비어 있다)
		for e in st.alive_targets():
			if e.boss or bool(e.airborne):
				continue
			var dd := PGeom.dist(e.x, e.y, g.x, g.y)
			if dd <= float(g.r) + e.r and dd > 8.0:
				var n := PGeom.norm(g.x - e.x, g.y - e.y)
				st.move_swept(e, n[0] * float(g.pull) * dt, n[1] * float(g.pull) * dt)
				if probe != null:
					pulled.append({ "e": e, "before": dd, "after": PGeom.dist(e.x, e.y, g.x, g.y) })
		_tell(st, g, "pull", { "list": pulled, "dt": dt, "active": active })
		var iv := float(g.get("tick_iv", 0.25))
		g.tick = float(g.tick) - dt
		if float(g.tick) <= 0.0 and float(g.t) > 0.0:
			g.tick = iv
			var ticked: Array = [] # 계측 전용
			for e in st.alive_targets():
				if PGeom.dist(e.x, e.y, g.x, g.y) <= float(g.r) + e.r:
					# 틱 피해는 dps × 간격이라 간격을 바꿔도 초당 피해는 그대로다. 보스는 끌리지 않으므로 배수(boss_mult)를 따로 둔다
					var dealt := hit(st, e, float(g.dps) * iv * (float(g.get("boss_mult", 1.0)) if e.boss else 1.0))
					if probe != null:
						ticked.append({ "e": e, "dealt": dealt })
			_tell(st, g, "tick", { "list": ticked, "each": float(g.dps) * iv })
		if not active:
			var cm := float(g.get("cm", 3.0 if bool(g.collapse) else 0.0))
			if cm > 0.0:
				var cr := float(g.get("cr", 100.0))
				st.fx({ "kind": "burst", "x": g.x, "y": g.y, "r": cr, "ttl": 0.35, "color": "#c9a0ff" })
				var boomed: Array = [] # 계측 전용
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, g.x, g.y) <= cr + e.r:
						var hurt := hit(st, e, float(g.dmg) * cm, { "dir": PGeom.norm(e.x - g.x, e.y - g.y), "knock": 60.0 })
						if probe != null:
							boomed.append({ "e": e, "dealt": hurt })
				st.ev("explode")
				_tell(st, g, "collapse", { "list": boomed, "each": float(g.dmg) * cm })
			_tell(st, g, "end")
			S.gravity = {}
	var w: Dictionary = S.get("ward", {})
	if not w.is_empty():
		w.t = float(w.t) - dt
		if bool(w.fortress):
			for e in st.alive_targets():
				if PGeom.dist(e.x, e.y, p.x, p.y) <= 60.0 + e.r:
					push_enemy(st, e, PGeom.norm(e.x - p.x, e.y - p.y), 30.0 * dt)
		if bool(w.pulse):
			w.pulse_t = float(w.pulse_t) - dt
			if float(w.pulse_t) <= 0.0:
				w.pulse_t = 0.8
				st.fx({ "kind": "spin", "x": p.x, "y": p.y, "r": 110.0, "ttl": 0.2 })
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, p.x, p.y) <= 110.0 + e.r and not st.los_blocked(p.x, p.y, e.x, e.y):
						hit(st, e, 8.0, { "dir": PGeom.norm(e.x - p.x, e.y - p.y), "knock": 10.0 })
		if float(w.t) <= 0.0:
			var rest := minf(p.shield, float(p.ward_shield))
			p.shield -= rest
			p.ward_shield = 0.0
			S.ward = {}

## 결계 보호막이 피해로 줄면 잔여량 추적
static func on_shield_damaged(st: CombatState, used: float) -> void:
	var p := st.player
	if float(p.ward_shield) > 0.0:
		p.ward_shield = maxf(0.0, float(p.ward_shield) - used)
