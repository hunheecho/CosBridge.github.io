class_name PSkills
extends RefCounted
## 수동 기술(HTML skills.js 이식). **Q와 E는 같은 6종을 공유한다**(2026-09-10 §7):
## 감속장 · 돌풍 · 칼날 폭풍 · 낙뢰 · 중력핵 · 수호 결계. 슬롯이 기술을 정하지 않는다 — 기술 id가 정한다.
##
## 슬롯이 뜻하는 것은 **입력 키와 재사용 시계**뿐이다:
##   q → 입력 special · 시계 player.special_cd · 배율 build.special_cd(q_cd_mult 포함)
##   e → 입력 skill_e  · 시계 player.e_cd      · 배율 build.skill_cd_mult × e_cd_mult
## 그래서 "Q 사용 시"(슬롯 조건)와 "감속장 사용 시"(기술 조건)는 서로 다른 조건이며 코드에서도 갈라 쓴다.
##
## 기술 상태(field·field2·storm·gravity·ward)는 **기술마다 하나씩**이다. 같은 기술을 두 슬롯에 둘 수 없으므로
## (PGrowth가 후보·확정 양쪽에서 막는다) 상태가 슬롯끼리 충돌하지 않는다.
## 기술 피해에는 무기 숙련이 적용되지 않는다.
## 감속장 수치(반지름·지속·감속)는 cfg.player.slowfield(첫 전투 호환), 재사용은 그 감속장이 든 슬롯의 시계를 따른다.

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

## 두 슬롯 이름(순서 고정: 화면·통계가 같은 순서를 쓴다)
const SLOTS := ["q", "e"]

static func init(st: CombatState) -> void:
	st.skill_state = { "storm": {}, "gravity": {}, "ward": {}, "target": null, "field2": {} }
	st.player.e_cd = 0.0
	st.eq_act = {}
	st.eq_trail = {}
	st.eq_guard = {}
	st.eq_debt = {}

## 기술 id가 든 슬롯("q"|"e"). 없으면 ""
static func slot_of(st: CombatState, id: String) -> String:
	for s in SLOTS:
		var sk = st.build.skills.get(s)
		if sk != null and String(sk.id) == id:
			return String(s)
	return ""

## 그 슬롯의 최종 재사용 시간(초).
## q는 PBuild.derive가 이미 계산해 둔 build.special_cd(그 슬롯 기술의 레벨별 기본 × 집중·박자·샘 × q_cd_mult)를 그대로 쓴다.
static func cd_of(st: CombatState, slot: String) -> float:
	var sk = st.build.skills.get(slot)
	if sk == null:
		return 0.0
	if slot == "q":
		return maxf(1.0, float(st.build.special_cd))
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	var mult: float = float(st.build.skill_cd_mult)
	mult *= float(st.build.get("e_cd_mult", 1.0)) # 특성 '수동기술 운용'(없으면 ×1.0)
	return float(d.cooldown[mini(3, int(sk.level)) - 1]) * mult

## 그 슬롯의 남은 재사용 시간을 읽는다(슬롯마다 시계가 다르다)
static func cd_left(st: CombatState, slot: String) -> float:
	return maxf(0.0, float(st.player.special_cd) if slot == "q" else float(st.player.get("e_cd", 0.0)))

static func set_cd_left(st: CombatState, slot: String, v: float) -> void:
	if slot == "q":
		st.player.special_cd = maxf(0.0, v)
	else:
		st.player.e_cd = maxf(0.0, v)

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

## 기술 피해. 출처 키는 **슬롯이 아니라 기술 id**다(감속장이 E에 있어도 출처는 감속장이다)
static func hit(st: CombatState, e: Dictionary, dmg: float, skill_id: String, opt: Dictionary = {}) -> float:
	var o := opt.duplicate()
	o.src = { "skill": true, "direct": false, "skill_id": skill_id }
	return st.damage_enemy(e, dmg * link_skill_mult(st), o)

# ---------- 감속장(슬롯 무관) ----------
## 감속장을 그 슬롯에서 발동한다. 예전 이름 cast_q는 아래에 남겨 둔다(첫 전투 호환).
static func cast_field(st: CombatState, slot: String) -> void:
	var p := st.player
	var S: Dictionary = st.cfg.player.slowfield
	var b := st.build
	var sk = b.skills.get(slot)
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
	st.stats.field_uses = int(st.stats.get("field_uses", 0)) + 1 # 감속장 사용 횟수(기술 조건)
	st.ev("special")
	st.text(p.x, p.y - 50.0, "감속장", "#a9d8ff")

static func on_field_end(st: CombatState, f: Dictionary) -> void:
	var slot := slot_of(st, "slowfield")
	var sk = st.build.skills.get(slot) if slot != "" else null
	if sk != null and sk.get("variant") != null and String(sk.variant) == "echo":
		st.add_zone("slowecho", f.x, f.y, f.r, 1.5, 0.0)
	st.skill_state.field2 = {}

static func in_field2(st: CombatState, ox: float, oy: float, orad: float) -> bool:
	if st.skill_state.is_empty():
		return false
	var f: Dictionary = st.skill_state.get("field2", {})
	return not f.is_empty() and PGeom.dist(f.x, f.y, ox, oy) <= f.r + orad

# ---------- 공격기 5종(어느 칸에 있어도 같다) ----------
## 돌풍의 부채꼴 기하. 조준·판정·표시가 모두 이 두 값만 쓴다(한 곳에서만 정한다).
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

## 돌풍 전용 조준 ①: 사용 순간의 '유효한 가까운 적'을 고른다.
##
## 왜 p.face를 쓰지 않는가 — face는 이동하면 매 프레임 이동 방향으로(combat_state.gd:1952),
## 자동공격이 나가면 그 대상 방향으로(weapons.gd:176·212·323·363·377) 덮인다.
## 한 단계 순서가 이동 → 기술 발동 → 자동공격이라 **이동 중에는 언제나 이동 방향으로 나갔다**
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

## 돌풍 전용 조준 ②: 실제로 나갈 각.
## 유효한 적이 없으면(사거리 밖·벽 뒤·구조물뿐·적 없음) **마지막으로 바라보던 방향**(p.face)으로 그대로 나간다.
## p.face의 뜻은 건드리지 않는다 — 여기서 읽기만 하고, 돌풍이 face에 쓰는 일은 없다.
static func gust_angle(st: CombatState) -> float:
	var p := st.player
	var tg := gust_target(st)
	if tg.is_empty():
		return float(p.face)
	return atan2(float(tg.y) - float(p.y), float(tg.x) - float(p.x))

## 수동 기술 발동(슬롯 공용). slot = "q" | "e".
## 성공하면 true. 대상이 없어 발동하지 못하면 false(재사용 시간도 소비하지 않는다 — 예전 E 규칙 그대로).
static func cast(st: CombatState, slot: String) -> bool:
	var p := st.player
	var b := st.build
	var sk = b.skills.get(slot)
	if sk == null:
		return false
	var sid := String(sk.id)
	var d: Dictionary = PCatalog.skills()[sid]
	var v: String = String(sk.variant) if sk.get("variant") != null else ""
	var dmg := sdmg(st, slot)
	var S := st.skill_state
	var lv := mini(3, int(sk.level))
	# ---------- 장비 기술([4]~[9])의 발동 자격 ----------
	# **그 장비를 벗으면 쓸 수 없다.** 자격은 착용 목록(build.equip_types)에서 직접 확인한다 —
	# 합산 사전(build.equip)은 같은 키를 뒤 슬롯이 덮어쓰기 때문에 두 장비가 각각 기술을 줄 때 하나가 사라진다.
	# 자격이 없거나 다른 장비 기술이 진행 중이면 **재사용 시간도 소비하지 않고** 아무 일도 하지 않는다.
	if is_eq(sid) and (not eq_granted(st, sid) or not st.eq_act.is_empty()):
		return false
	var cd_now := true # [7]의 첫 입력만 false다(기록만 시작한다 — 재사용은 귀환·만료 때 건다)
	match sid:
		"slowfield":
			cast_field(st, slot)
		"gust":
			# 조준각은 **사용 순간에 한 번** 정한다. 아래의 적중 판정·밀어내기·바람길 자리·
			# 표시(fx.angle = 화면에 그리는 부채꼴)가 전부 이 하나의 값을 쓰므로 표시와 판정이 어긋날 수 없다.
			# 이동 방향은 이 계산에 들어오지 않는다 — 그래서 이동 중에도 조준이 덮이지 않는다.
			var ang: float = gust_angle(st)
			if v == "whirl":
				st.fx({ "kind": "gust", "x": p.x, "y": p.y, "r": 130.0, "whirl": true, "ttl": 0.3 })
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, p.x, p.y) <= 130.0 + e.r:
						hit(st, e, dmg, sid)
						push_enemy(st, e, PGeom.norm(e.x - p.x, e.y - p.y), 140.0 + 30.0 * float(lv - 1))
			else:
				st.fx({ "kind": "gust", "x": p.x, "y": p.y, "angle": ang, "len": GUST_LEN, "w": GUST_W, "ttl": 0.3 })
				for e in st.alive_targets():
					if PGeom.in_beam(p.x, p.y, ang, GUST_LEN, GUST_W, e.x, e.y, e.r) and not st.los_blocked(p.x, p.y, e.x, e.y):
						hit(st, e, dmg, sid)
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
				bolt_at(st, at, 45.0, dmg, sid)
				if v == "chain":
					var others := []
					for e in st.alive_targets():
						var dd := PGeom.dist(e.x, e.y, at.x, at.y)
						if dd <= 150.0 and dd > 20.0 and others.size() < 2:
							others.append(e)
					for o in others:
						var oa := { "x": o.x, "y": o.y }
						st.delayed.append({ "t": 0.15, "fn": func(): bolt_at(st, oa, 40.0, dmg * 0.5, sid) })
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
		# ---------- 장비 기술 여섯(3절 [4]~[9]) ----------
		"eq_flashcut", "eq_meteor":
			eq_start_charge(st, slot, sid, dmg)
		"eq_riposte":
			eq_start_guard(st, slot, dmg)
		"eq_retrace":
			cd_now = eq_retrace_press(st, slot, dmg)
		"eq_icetomb":
			eq_start_tomb(st, slot)
		"eq_reprieve":
			eq_start_reprieve(st, slot)
	set_cd_left(st, slot, cd_of(st, slot) if cd_now else 0.0)
	if sid != "slowfield": # 감속장은 cast_field가 자기 신호·문구를 이미 냈다(소리가 두 번 나지 않게)
		st.ev("skill_e", { "id": sid, "slot": slot })
		st.text(p.x, p.y - 62.0, String(d.name), "#ffe9a8")
	# ---------- 여기부터는 **슬롯 조건**이다(기술 종류와 무관하다) ----------
	# "Q 사용 시"·"E 사용 시"라고 적힌 효과는 전부 아래에 있고, "감속장 사용 시"는 cast_field 안에 있다.
	if slot == "q":
		st.stats.special_uses += 1
		if (b.equip as Dictionary).has("relay"):
			st.relay_window = float(b.equip.relay.window) # 연계 방패: Q 뒤 E까지 허용 창
		return true
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
	if (b.boss_rewards as Array).has("volley"):
		PWeapons.volley(st)
	return true

## 예전 이름(첫 전투·도구 호환). Q/E 슬롯을 그대로 발동한다
static func cast_q(st: CombatState) -> bool:
	return cast(st, "q")

static func cast_e(st: CombatState) -> bool:
	return cast(st, "e")

static func bolt_at(st: CombatState, at: Dictionary, r: float, dmg: float, skill_id: String = "strike") -> void:
	st.fx({ "kind": "strike", "x": at.x, "y": at.y, "r": r, "ttl": 0.3 })
	for e in st.alive_targets():
		if PGeom.dist(e.x, e.y, at.x, at.y) <= r + e.r:
			hit(st, e, dmg, skill_id)
	st.ev("explode")

static func update(st: CombatState, dt: float) -> void:
	var p := st.player
	var S := st.skill_state
	eq_update(st, dt) # 장비 기술은 skill_state와 별개 상태를 쓴다(전부 비어 있으면 아무 일도 없다)
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
	# 자동 조준 표시(낙뢰·중력핵). **어느 슬롯에 있든** 그 슬롯의 재사용이 끝났을 때만 보인다
	S.target = null
	for slot in SLOTS:
		var sk = st.build.skills.get(slot)
		if sk == null or cd_left(st, String(slot)) > 0.0:
			continue
		var sid := String(sk.id)
		if sid != "strike" and sid != "gravity":
			continue
		var tg: Dictionary = auto_target(st, 260.0) if sid == "strike" else cluster(st, 260.0)
		if not tg.is_empty():
			S.target = { "x": tg.x, "y": tg.y }
			break
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
					hit(st, e, float(storm.dmg), "bladestorm", { "dir": PGeom.norm(e.x - storm.x, e.y - storm.y), "knock": 8.0 })
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
					var dealt := hit(st, e, float(g.dps) * iv * (float(g.get("boss_mult", 1.0)) if e.boss else 1.0), "gravity")
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
						var hurt := hit(st, e, float(g.dmg) * cm, "gravity", { "dir": PGeom.norm(e.x - g.x, e.y - g.y), "knock": 60.0 })
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
						hit(st, e, 8.0, "ward", { "dir": PGeom.norm(e.x - p.x, e.y - p.y), "knock": 10.0 })
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

# ============================================================================
# 장비 기술 여섯 (정본 지시 docs/SPEC_EQUIP_SKILLBANK.md 3절 [4]~[9] · 5절 · 7절)
#
# 무엇이 다른가 — 일반 수동 기술과 **같은 Q/E 두 칸**을 쓰지만 id가 eq_ 로 시작하고
#  · 레벨·개조가 없다(data/growth.json에 max 1 · variants 없음 · e_skills 목록 밖)
#  · **그 장비를 착용해야만** 발동한다(장비 정의의 grantsSkill). 벗으면 그 자리의 기술은 쓸 수 없다.
#  · 슬롯 조건(재사용 시계·'E 사용 시' 장비 효과·특성 연계 창)은 일반 기술과 **똑같이** 적용된다(§5).
#
# 상태를 왜 넷으로 나눴는가
#   eq_act   진행 중인 채널 **하나**(충전·순간이동·도약·귀환·갇힘). 이동·회피를 묶고, 무적을 여기서 유도한다.
#   eq_trail [7]의 경로 기록(움직이면서 계속 쌓이므로 채널이 아니다)
#   eq_guard [6]의 정면 방어 창(이동을 묶지 않는다)
#   eq_debt  [9]의 예정 피해(전투 내내 남을 수 있고 정산 경로가 따로 있다)
# 넷이 전부 비어 있으면 아래 코드는 한 줄도 실행되지 않는다 — **기준 전투(D33) 지문이 그대로다.**
#
# **무적은 타이머가 아니라 상태에서 유도한다**(eq_invuln). eq_act가 어떤 이유로든 사라지면
# (취소·해제·최대 시간·화면 전환·전투 종료) 무적도 그 자리에서 함께 사라진다 —
# 남는 무적을 만들 수 있는 자리가 코드에 없다.
#
# 여기 숫자는 하나도 없다. 전부 data/growth.json의 skills.<id>.tune(첫 시험값)에서 읽는다.
# ============================================================================

## 장비 기술 여섯의 id(순서 고정: 문서·검사가 같은 순서를 쓴다)
const EQ_IDS := ["eq_flashcut", "eq_meteor", "eq_riposte", "eq_retrace", "eq_icetomb", "eq_reprieve"]
## 진행 중인 장비 기술이 없을 때 돌려주는 상수(매 단계 사전을 새로 만들지 않는다)
const EQ_NONE := { "dodge": false, "q": false, "e": false }
## [6] 받아치기가 **막지 않는** 피해 출처. 장판·바닥 지대·환경 피해다.
## 공통 경로("zone")를 지나지 않고 damage_player로 직접 들어오는 바닥 지대만 여기 적는다 —
## 나머지 판단은 '공격자가 있는가'와 '정면인가' 두 조건이 맡는다.
const EQ_GUARD_DENY := ["zone", "frostzone", "boss_rubble", "boss_icepath"]

static func is_eq(id: String) -> bool:
	return EQ_IDS.has(id)

## 그 장비 기술의 조절값(data/growth.json skills.<id>.tune). 없으면 빈 사전이고 아래 기본값이 쓰인다
static func eq_tune(sid: String) -> Dictionary:
	var SK := PCatalog.skills()
	return (SK.get(sid, {}) as Dictionary).get("tune", {})

## 지금 **착용한 장비**가 이 기술을 주는가.
## 합산 사전(build.equip)이 아니라 착용 목록(build.equip_types)을 본다 —
## PBuild.derive가 같은 eff 키를 뒤 슬롯으로 덮어쓰기 때문에, 두 장비가 각각 기술을 주면
## 합산 사전에는 하나만 남는다. 착용 목록을 보면 그 구멍이 없다.
static func eq_granted(st: CombatState, sid: String) -> bool:
	for tid in (st.build.get("equip_types", []) as Array):
		var d: Dictionary = PCatalog.equipment_def(String(tid))
		if String(d.get("grantsSkill", "")) == sid:
			return true
	return false

## 지금 장비 기술이 주는 무적인가. **상태에서 유도한다** — 상태가 사라지면 무적도 사라진다.
## 회피 무적(player.invuln_t)과 다른 것이며 '완벽 회피'로 세지 않는다.
static func eq_invuln(st: CombatState) -> bool:
	return not st.eq_act.is_empty() and bool(st.eq_act.get("invuln", false))

## 지금 이동·회피가 묶여 있는가(충전·순간이동·도약·귀환·갇힘). 채널이 없으면 언제나 false
static func eq_locks_move(st: CombatState) -> bool:
	return not st.eq_act.is_empty()

## [5] 낙성 강하의 **도약 중**인가. 그동안에는 공중이라 장애물 밀어내기(push_out)를 적용하지 않는다 —
## 대신 착지점이 발동 순간에 이미 유효성을 확인한 자리다. 이것은 무적과 아무 상관이 없다(무적 구간은 따로 명시한다).
static func eq_airborne(st: CombatState) -> bool:
	return not st.eq_act.is_empty() and String(st.eq_act.get("id", "")) == "eq_meteor" and String(st.eq_act.get("phase", "")) == "leap"

## [8] 결정 관: 지금 **새 공격을 시작하지 않는** 구간인가.
## '새 공격'만이다 — 이미 발사한 투사체·설치된 지뢰·깔린 장판·지연 착탄은 그대로 흐른다(CombatState.update_attack).
static func eq_holds_attacks(st: CombatState) -> bool:
	return not st.eq_act.is_empty() and String(st.eq_act.get("id", "")) == "eq_icetomb"

## 장비 기술의 피해. **경로 이름(cause)을 반드시 적어 보낸다.**
## 적지 않으면 PSupport.cause_of가 '무기 id 없는 파생 피해'를 main_extra로 떨어뜨려
## 승인되지 않은 연계가 우연히 열린다. 자격표는 data/supports.json 한 곳뿐이다(새 장치 없음).
##
## 2026-09-10 사용자 확정 뒤로 이 이름이 **자격을 실제로 가른다.**
##  · eq_slash · eq_meteor_core · eq_meteor_wave · eq_riposte · eq_retrace
##    → 자격표 frost_shatter·plague_host_burst의 **allow에 적혀 있다**(파쇄·숙주 파열을 발동할 수 있다).
##  · eq_icetomb → 두 표의 **deny에 그대로 남아 있다**(결정 관은 파쇄도 숙주 파열도 열지 않는다).
##  · [9] 유예의 시계는 적에게 피해를 주지 않아 이 함수를 아예 지나가지 않는다.
##  · 감전 후속·방전 충전·까마귀 표적은 **여섯 전부 deny 그대로**이고, 흡혈은 data/growth.json
##    LIFESTEAL.denied에 여섯 전부 적혀 있다 — 이번에 함께 열지 않았다.
## **묶음 경로 이름(equip_skill_direct 같은 것)을 새로 만들지 않았다** — 기술별 출처를 남겨야
## 통계·기록에서 무엇이 깼는지 따로 셀 수 있고, 닫아 둔 둘이 그 이름에 묻어 들어올 길도 없다.
static func eq_hit(st: CombatState, e: Dictionary, dmg: float, skill_id: String, cause: String, opt: Dictionary = {}) -> float:
	var o := opt.duplicate()
	o["cause"] = cause
	o["src"] = { "skill": true, "direct": false, "skill_id": skill_id }
	return st.damage_enemy(e, dmg * link_skill_mult(st), o)

# ---------- 입력: 떼기·재입력·취소 ----------
## 진행 중인 장비 기술이 이 단계의 입력을 **먼저** 가져간다. 돌려주는 값 = 가져간 것 {dodge, q, e}.
## 진행 중인 것이 없으면 EQ_NONE이라 예전 입력 경로가 그대로 실행된다.
##
## '놓으면 발동'을 어떻게 아는가 — 입력 계약({mx,my,dodge_press,dodge_held,special,skill_e})에는
## Q/E의 **누름**만 있고 유지가 없다(그 계약은 화면·입력 담당의 소유라 여기서 바꾸지 않았다).
## 그래서 출구를 셋 둔다:
##   ① 입력이 special_held / skill_e_held 를 함께 주면 **실제로 손을 뗀 순간**(정본 동작)
##   ② 같은 칸을 **다시 누르면** 즉시 발동
##   ③ **최대 충전 시간**에 닿으면 자동 발동
## ①이 없는 지금의 PC·터치·봇 입력에서도 ②③이 있으므로 충전이 영원히 남지 않는다.
static func eq_take_input(st: CombatState, input: Dictionary) -> Dictionary:
	var a: Dictionary = st.eq_act
	var tr: Dictionary = st.eq_trail
	if a.is_empty() and tr.is_empty():
		return EQ_NONE
	var q_press: bool = bool(input.get("special", false))
	var e_press: bool = bool(input.get("skill_e", false))
	var took := { "dodge": false, "q": false, "e": false }
	if not a.is_empty():
		var slot := String(a.get("slot", "q"))
		var is_q: bool = slot == "q"
		var press: bool = q_press if is_q else e_press
		var has_hold: bool = input.has("special_held") if is_q else input.has("skill_e_held")
		var hold: bool = bool(input.get("special_held", false)) if is_q else bool(input.get("skill_e_held", false))
		if has_hold and hold:
			a["hold_seen"] = true
		var charging: bool = String(a.get("phase", "")) == "charge"
		var tomb: bool = String(a.get("id", "")) == "eq_icetomb"
		if (charging or tomb) and bool(input.get("dodge_press", false)):
			took["dodge"] = true
			if charging:
				eq_cancel(st, "space") # 충전 중 Space = 취소(재사용 시간을 돌려준다)
			else:
				eq_release(st, "space") # 갇힘 중 Space = 해제(무적이 남지 않는다)
			return took
		if charging or tomb:
			if press:
				took[slot] = true
				eq_release(st, "press")
				return took
			if has_hold and bool(a.get("hold_seen", false)) and not hold:
				eq_release(st, "release")
				return took
		# 진행 중에는 같은 칸의 새 입력을 삼킨다(중복 발동·재사용 우회 금지)
		if press:
			took[slot] = true
		return took
	# [7] 되짚는 궤적: 기록 중 같은 칸 재입력 = 귀환
	var slot2 := String(tr.get("slot", "q"))
	var press2: bool = q_press if slot2 == "q" else e_press
	if press2:
		took[slot2] = true
		eq_retrace_return(st)
	return took

# ---------- 진행 ----------
static func eq_update(st: CombatState, dt: float) -> void:
	eq_update_guard(st, dt)
	eq_update_trail(st, dt)
	eq_update_debt(st, dt)
	eq_update_act(st, dt)

static func eq_update_act(st: CombatState, dt: float) -> void:
	var a: Dictionary = st.eq_act
	if a.is_empty():
		return
	a["t"] = float(a.t) + dt
	var sid := String(a.id)
	var charging: bool = String(a.phase) == "charge"
	match sid:
		"eq_flashcut":
			if charging:
				a["invuln"] = false # 충전 중에는 공격받을 수 있다(3절 [4])
				if float(a.t) >= float(a.max):
					eq_release(st, "max")
			else:
				a["invuln"] = true # 발동하는 짧은 순간에만 무적
				if float(a.t) >= float(a.get("blink", 0.1)):
					st.eq_act = {}
		"eq_meteor":
			if charging:
				a["invuln"] = false
				a["aim"] = eq_meteor_aim(st, float(a.get("range", 220.0))) # 아직 충전 중이라 조준은 계속 고른다
				if float(a.t) >= float(a.max):
					eq_release(st, "max")
			else:
				eq_meteor_step(st, a)
		"eq_retrace":
			eq_retrace_step(st, a, dt)
		"eq_icetomb":
			a["invuln"] = true
			if float(a.t) >= float(a.max):
				eq_release(st, "max")

## 채널을 정상적으로 마무리한다(떼기·재입력·Space·최대 시간). why는 기록용이다
static func eq_release(st: CombatState, why: String) -> void:
	var a: Dictionary = st.eq_act
	if a.is_empty():
		return
	match String(a.id):
		"eq_flashcut":
			eq_flashcut_fire(st, a)
		"eq_meteor":
			eq_meteor_launch(st, a)
		"eq_icetomb":
			eq_tomb_break(st, a, why)

## 충전을 취소한다(Space·화면 전환). 기술이 나가지 않았으므로 **재사용 시간을 돌려준다.**
## eq_act를 비우는 순간 무적·이동 잠금도 함께 사라진다(무적은 상태에서 유도하므로).
static func eq_cancel(st: CombatState, _why: String) -> void:
	var a: Dictionary = st.eq_act
	if a.is_empty():
		return
	var slot := String(a.get("slot", "q"))
	st.eq_act = {}
	set_cd_left(st, slot, 0.0)
	st.text(st.player.x, st.player.y - 62.0, "취소", "#9ea8b8")

## 이미 발동한 이동(도약·순간이동·귀환)을 중간에 끝낸다. **재사용 시간은 그대로 둔다**(이미 썼다).
## 어디서 끝나든 유효한 자리에 내려놓는다
static func eq_abort(st: CombatState, _why: String) -> void:
	if st.eq_act.is_empty():
		return
	st.eq_act = {}
	eq_land_valid(st)

## 지금 자리가 유효하지 않으면 가장 가까운 유효 위치로 옮긴다(벽 안쪽에 남지 않게)
static func eq_land_valid(st: CombatState) -> void:
	var p := st.player
	if not st.valid_pos(float(p.x), float(p.y), float(p.r)):
		var pos := st.nearest_valid_pos(float(p.x), float(p.y), float(p.r), 200.0)
		if not pos.is_empty():
			p.x = float(pos[0])
			p.y = float(pos[1])
	st.push_out(p)

## **화면 전환·전투 종료 공통 정리.** 진행 중인 것을 그 자리에서 끝낸다 —
## 충전은 취소(환급) · 갇힘은 정상 해제 · 도약/귀환은 중단 · 기록은 만료 · 방어 창은 조용히 닫는다.
## 예정 피해([9])는 **여기서 지우지 않는다.** 조용한 삭제를 막기 위해 정산 경로로만 없앤다.
static func eq_stop_all(st: CombatState, why: String) -> void:
	if not st.eq_act.is_empty():
		var sid := String(st.eq_act.get("id", ""))
		if String(st.eq_act.get("phase", "")) == "charge":
			eq_cancel(st, why)
		elif sid == "eq_icetomb":
			eq_release(st, why)
		else:
			eq_abort(st, why)
	if not st.eq_trail.is_empty():
		eq_trail_expire(st, why)
	if not st.eq_guard.is_empty():
		st.eq_guard = {} # 막은 공격이 없으므로 밀치기도 내지 않는다

## 화면 전환(성장 선택·강적 등장 연출)에 들어갈 때. 그동안 적이 행동하지 않으므로
## 충전·무적·입력 상태를 들고 가지 않는다
static func eq_on_transition(st: CombatState) -> void:
	if st.eq_act.is_empty() and st.eq_trail.is_empty() and st.eq_guard.is_empty():
		return
	eq_stop_all(st, "화면 전환")

## 전투가 끝나는 그 단계. 진행 중인 것을 정리하고 **남은 예정 피해를 정산한다**(조용한 삭제 금지).
## 이미 이긴 전투를 사후 정산으로 뒤집지 않도록, 승리 확정 뒤의 정산은 체력을 1 미만으로 내리지 않는다.
static func eq_on_combat_end(st: CombatState) -> void:
	if st.eq_act.is_empty() and st.eq_trail.is_empty() and st.eq_guard.is_empty() and st.eq_debt.is_empty():
		return
	eq_stop_all(st, "전투 종료")
	eq_settle(st, "전투 종료", st.status == "won")

## 전투 중 빌드가 바뀌었을 때(레벨업 재계산·장비 교체). 더 이상 그 장비를 착용하지 않으면
## 진행 중인 장비 기술을 끝내고 **예정 피해는 정산한다** — 장비 해제로 조용히 사라지지 않게.
static func eq_on_rebuild(st: CombatState) -> void:
	if not st.eq_act.is_empty() and not eq_granted(st, String(st.eq_act.get("id", ""))):
		eq_stop_all(st, "장비 해제")
	if not st.eq_trail.is_empty() and not eq_granted(st, "eq_retrace"):
		eq_trail_expire(st, "장비 해제")
	if not st.eq_guard.is_empty() and not eq_granted(st, "eq_riposte"):
		st.eq_guard = {}
	if not st.eq_debt.is_empty() and not eq_granted(st, "eq_reprieve"):
		eq_settle(st, "장비 해제", false)

# ---------- [4] 찰나 가르기 ----------
## [4][5] 공통 충전 시작. 충전 중에는 제자리에 서고(이동 잠금) **공격받을 수 있다**(무적 없음)
static func eq_start_charge(st: CombatState, slot: String, sid: String, dmg: float) -> void:
	var T := eq_tune(sid)
	var a := { "id": sid, "slot": slot, "phase": "charge", "t": 0.0, "invuln": false,
		"hold_seen": false, "dmg": dmg, "max": float(T.get("charge", 0.55)) }
	if sid == "eq_meteor":
		a["range"] = float(T.get("range", 220.0))
		a["aim"] = eq_meteor_aim(st, float(a["range"]))
	st.eq_act = a
	st.ev("lock")

## 놓는 순간: **여기서 방향이 확정된다.** 전방을 일자로 베며 순간 이동한다.
##  · 벽·바위·나무는 통과하지 않는다 — 스윕 이동(move_swept)이 장애물·경계에서 멈춘다.
##    적 몸은 장애물이 아니므로 그대로 관통한다.
##  · 경로의 적을 **한 번씩**: 살아 있는 대상 목록을 한 번만 훑으므로 큰 적이라고 여러 번 맞지 않는다.
##  · 무적은 이 뒤 짧은 blink 구간뿐이다(충전 구간에는 없었다).
static func eq_flashcut_fire(st: CombatState, a: Dictionary) -> void:
	var p := st.player
	var T := eq_tune("eq_flashcut")
	var ang: float = float(p.face)
	var len_v := float(T.get("len", 240.0))
	var wid := float(T.get("w", 44.0))
	var x0: float = float(p.x)
	var y0: float = float(p.y)
	st.move_swept(p, cos(ang) * len_v, sin(ang) * len_v)
	eq_land_valid(st)
	var x1: float = float(p.x)
	var y1: float = float(p.y)
	var dmg := float(a.get("dmg", 0.0))
	for e in st.alive_targets():
		if PGeom.dist_seg(float(e.x), float(e.y), x0, y0, x1, y1) <= wid * 0.5 + float(e.r):
			eq_hit(st, e, dmg, "eq_flashcut", "eq_slash", { "dir": [cos(ang), sin(ang)], "knock": 12.0 })
	st.fx({ "kind": "eq_slash", "x": x0, "y": y0, "x1": x1, "y1": y1, "w": wid, "ttl": 0.28 })
	st.ev("dash_hit")
	a["phase"] = "blink"
	a["t"] = 0.0
	a["blink"] = float(T.get("blink", 0.1))
	a["invuln"] = true

# ---------- [5] 낙성 강하 ----------
## 착지점 후보. **유효하지 않은 지형에는 착지하지 않는다** — 가장 가까운 유효 위치로 당긴다.
## 충전 중에는 매 단계 다시 고르고, 놓는 순간의 값이 그대로 확정된다
static func eq_meteor_aim(st: CombatState, range_v: float) -> Array:
	var p := st.player
	var ax: float = float(p.x) + cos(float(p.face)) * range_v
	var ay: float = float(p.y) + sin(float(p.face)) * range_v
	var pos := st.nearest_valid_pos(ax, ay, float(p.r), 200.0)
	if pos.is_empty():
		return [float(p.x), float(p.y)]
	return [float(pos[0]), float(pos[1])]

## 놓는 순간: 착지점을 **확정**한다. 이후 도약 중에는 다시 추적하지 않는다.
## 무적 구간을 여기서 명시적으로 적는다 — '공중이라 무적'이 아니다.
static func eq_meteor_launch(st: CombatState, a: Dictionary) -> void:
	var T := eq_tune("eq_meteor")
	var p := st.player
	var aim: Array = a.get("aim", [float(p.x), float(p.y)])
	a["phase"] = "leap"
	a["t"] = 0.0
	a["fx0"] = float(p.x)
	a["fy0"] = float(p.y)
	a["tx"] = float(aim[0])
	a["ty"] = float(aim[1])
	a["leap"] = float(T.get("leap", 0.45))
	a["iv0"] = float(T.get("invuln_from", 0.0))
	a["iv1"] = float(T.get("invuln_to", 0.3))
	a["invuln"] = false
	st.ev("dodge")

## 도약 진행. 위치는 확정된 두 점 사이의 직선 보간이다(공중이라 장애물을 넘는다 —
## 대신 **착지점은 발동 순간에 유효성을 확인한 자리**이므로 유효하지 않은 지형에 내려앉지 않는다)
static func eq_meteor_step(st: CombatState, a: Dictionary) -> void:
	var p := st.player
	var dur := maxf(0.001, float(a.get("leap", 0.45)))
	var tt := float(a.t)
	a["invuln"] = tt >= float(a.get("iv0", 0.0)) and tt < float(a.get("iv1", 0.3))
	var k := clampf(tt / dur, 0.0, 1.0)
	p.x = float(a["fx0"]) + (float(a["tx"]) - float(a["fx0"])) * k
	p.y = float(a["fy0"]) + (float(a["ty"]) - float(a["fy0"])) * k
	if k >= 1.0:
		eq_meteor_land(st, a)
		st.eq_act = {}

## 착지. 중심 강타와 바깥 충격파는 **배타적**이라 한 적이 둘 다 맞지 않는다
static func eq_meteor_land(st: CombatState, a: Dictionary) -> void:
	var T := eq_tune("eq_meteor")
	var p := st.player
	p.x = float(a["tx"])
	p.y = float(a["ty"])
	eq_land_valid(st)
	var core_r := float(T.get("core_r", 70.0))
	var wave_r := float(T.get("wave_r", 150.0))
	var knock := float(T.get("knock", 40.0))
	var dmg := float(a.get("dmg", 0.0))
	var wave := dmg * float(T.get("wave_mult", 0.35))
	for e in st.alive_targets():
		var d := PGeom.dist(float(e.x), float(e.y), float(p.x), float(p.y))
		var n := PGeom.norm(float(e.x) - float(p.x), float(e.y) - float(p.y))
		if d <= core_r + float(e.r):
			eq_hit(st, e, dmg, "eq_meteor", "eq_meteor_core", { "dir": n, "knock": knock })
		elif d <= wave_r + float(e.r):
			eq_hit(st, e, wave, "eq_meteor", "eq_meteor_wave", { "dir": n, "knock": knock * 0.5 })
	st.fx({ "kind": "eq_slam", "x": p.x, "y": p.y, "r": core_r, "wave": wave_r, "ttl": 0.35 })
	st.ev("explode")

# ---------- [6] 받아치기 ----------
## 짧게 정면을 방어한다. **오래 눌러도 길어지지 않는다**(고정 시간이고 유지 입력을 아예 읽지 않는다).
## 막는 방향은 그 순간 바라보는 방향(player.face)이다 — 몸을 돌리면 막는 쪽도 돈다.
static func eq_start_guard(st: CombatState, slot: String, dmg: float) -> void:
	var T := eq_tune("eq_riposte")
	st.eq_guard = { "slot": slot, "t": float(T.get("guard", 0.45)), "dmg": dmg, "blocked": false }

static func eq_update_guard(st: CombatState, dt: float) -> void:
	var g: Dictionary = st.eq_guard
	if g.is_empty():
		return
	g["t"] = float(g.t) - dt
	if float(g.t) <= 0.0:
		eq_guard_expire(st, g) # 못 막았다 → 약한 방패 밀치기로 끝난다

## 이 공격을 받아치기가 막는가. 막았으면 true(피해 0 + 강한 부채꼴 반격).
##
## 막는 것: **공격자가 있는 정면의 직접 타격과 투사체**.
## 막지 않는 것: 장판·지속·환경 피해(공통 경로 "zone"과 EQ_GUARD_DENY의 바닥 지대, 공격자가 없는 피해).
## **같은 공격 하나로 반격이 두 번 나오지 않는다**: 막는 즉시 방어 창을 닫는다.
static func eq_riposte_block(st: CombatState, src: String, attacker) -> bool:
	var g: Dictionary = st.eq_guard
	if g.is_empty() or bool(g.get("blocked", false)):
		return false
	if attacker == null or EQ_GUARD_DENY.has(src) or src.begins_with("zone"):
		return false
	var p := st.player
	var e: Dictionary = attacker
	var T := eq_tune("eq_riposte")
	var to_e := atan2(float(e.y) - float(p.y), float(e.x) - float(p.x))
	if absf(PGeom.ang_diff(to_e, float(p.face))) > deg_to_rad(float(T.get("arc", 120.0)) * 0.5):
		return false
	g["blocked"] = true
	st.eq_guard = {} # 막는 즉시 방어가 끝난다
	var ang := float(p.face)
	var r := float(T.get("counter_r", 130.0))
	var half := deg_to_rad(float(T.get("counter_arc", 120.0)) * 0.5)
	var knock := float(T.get("counter_knock", 30.0))
	for o in st.alive_targets():
		if PGeom.in_arc(p.x, p.y, r, ang, half, o.x, o.y, o.r) and not st.los_blocked(p.x, p.y, o.x, o.y):
			eq_hit(st, o, float(g.get("dmg", 0.0)), "eq_riposte", "eq_riposte", { "dir": PGeom.norm(float(o.x) - float(p.x), float(o.y) - float(p.y)), "knock": knock })
	st.fx({ "kind": "eq_counter", "x": p.x, "y": p.y, "angle": ang, "r": r, "half": half, "ttl": 0.3 })
	st.text(p.x, p.y - 44.0, "받아침!", "#ffe9a8")
	st.ev("block")
	st.stats.equip_procs.counter_guard = int(st.stats.equip_procs.get("counter_guard", 0)) + 1
	return true

## 창이 끝났는데 한 번도 막지 못했다 → 약한 방패 밀치기로 끝난다
static func eq_guard_expire(st: CombatState, g: Dictionary) -> void:
	st.eq_guard = {}
	var T := eq_tune("eq_riposte")
	var p := st.player
	var ang := float(p.face)
	var r := float(T.get("push_r", 70.0))
	var half := deg_to_rad(float(T.get("push_arc", 100.0)) * 0.5)
	var dmg := float(g.get("dmg", 0.0)) * float(T.get("push_mult", 0.24))
	var knock := float(T.get("push_knock", 24.0))
	for o in st.alive_targets():
		if PGeom.in_arc(p.x, p.y, r, ang, half, o.x, o.y, o.r) and not st.los_blocked(p.x, p.y, o.x, o.y):
			eq_hit(st, o, dmg, "eq_riposte", "eq_riposte", { "dir": PGeom.norm(float(o.x) - float(p.x), float(o.y) - float(p.y)), "knock": knock })
	st.fx({ "kind": "eq_push", "x": p.x, "y": p.y, "angle": ang, "r": r, "half": half, "ttl": 0.22 })

# ---------- [7] 되짚는 궤적 ----------
## 첫 입력: 지금 자리를 표시하고 이동 경로 기록을 시작한다.
## **재사용 시간은 걸지 않는다**(false를 돌려준다) — 귀환했을 때, 또는 기록이 만료·중단됐을 때 건다.
static func eq_retrace_press(st: CombatState, slot: String, dmg: float) -> bool:
	var T := eq_tune("eq_retrace")
	var p := st.player
	st.eq_trail = { "slot": slot, "t": 0.0, "tick": 0.0, "dmg": dmg,
		"dur": float(T.get("record", 4.0)), "sample": float(T.get("sample", 0.08)),
		"min_step": float(T.get("min_step", 6.0)), "max_pts": int(T.get("max_pts", 60)),
		"pts": [[float(p.x), float(p.y)]] }
	st.fx({ "kind": "eq_mark", "x": p.x, "y": p.y, "r": float(p.r) + 6.0, "ttl": 0.6 })
	return false

## 기록 진행. **시간과 길이가 모두 유한하다**(dur 초 · max_pts 점, 넘치면 오래된 점부터 버린다)
static func eq_update_trail(st: CombatState, dt: float) -> void:
	var tr: Dictionary = st.eq_trail
	if tr.is_empty():
		return
	tr["t"] = float(tr.t) + dt
	if float(tr.t) >= float(tr.dur):
		eq_trail_expire(st, "만료")
		return
	tr["tick"] = float(tr.tick) - dt
	if float(tr.tick) > 0.0:
		return
	tr["tick"] = float(tr.sample)
	var pts: Array = tr.pts
	var p := st.player
	var last: Array = pts[pts.size() - 1]
	if PGeom.dist(float(last[0]), float(last[1]), float(p.x), float(p.y)) < float(tr.min_step):
		return
	pts.append([float(p.x), float(p.y)])
	if pts.size() > int(tr.max_pts):
		pts.remove_at(0)

## 기록 만료·중단. 기록만 버리고 **재사용 시간을 그때 건다**(기준을 한 곳에 둔다)
static func eq_trail_expire(st: CombatState, why: String) -> void:
	var tr: Dictionary = st.eq_trail
	if tr.is_empty():
		return
	var slot := String(tr.get("slot", "q"))
	st.eq_trail = {}
	set_cd_left(st, slot, cd_of(st, slot))
	st.text(st.player.x, st.player.y - 62.0, "궤적 " + why, "#9ea8b8")

## 재입력: 기록한 길을 거슬러 돌아온다. 여기서 재사용 시간을 건다
static func eq_retrace_return(st: CombatState) -> void:
	var tr: Dictionary = st.eq_trail
	if tr.is_empty() or not st.eq_act.is_empty():
		return
	var T := eq_tune("eq_retrace")
	var slot := String(tr.get("slot", "q"))
	var pts: Array = (tr.pts as Array).duplicate()
	var dmg := float(tr.get("dmg", 0.0))
	st.eq_trail = {}
	pts.reverse()
	st.eq_act = { "id": "eq_retrace", "slot": slot, "phase": "return", "t": 0.0, "invuln": false,
		"pts": pts, "i": 0, "hit": {}, "dmg": dmg,
		"speed": float(T.get("speed", 900.0)), "hit_r": float(T.get("hit_r", 34.0)) }
	set_cd_left(st, slot, cd_of(st, slot))
	st.ev("dodge")

## 귀환 진행. **벽을 뚫지 않는다** — 기록 뒤 지형이 달라졌어도 스윕 이동이 장애물에서 멈추고,
## 막히면 그 자리에서 귀환이 끝난다(유효하지 않은 자리에 남지 않는다)
static func eq_retrace_step(st: CombatState, a: Dictionary, dt: float) -> void:
	var p := st.player
	var pts: Array = a.pts
	var budget := float(a.speed) * dt
	var guard := 0
	while budget > 0.0 and int(a["i"]) < pts.size() and guard < 64:
		guard += 1
		var tgt: Array = pts[int(a["i"])]
		var bx: float = float(p.x)
		var by: float = float(p.y)
		var d := PGeom.dist(bx, by, float(tgt[0]), float(tgt[1]))
		if d <= 0.5:
			a["i"] = int(a["i"]) + 1
			continue
		var stepd := minf(budget, d)
		var n := PGeom.norm(float(tgt[0]) - bx, float(tgt[1]) - by)
		var res := st.move_swept(p, n[0] * stepd, n[1] * stepd)
		var moved := PGeom.dist(bx, by, float(p.x), float(p.y))
		eq_retrace_hits(st, a, bx, by, float(p.x), float(p.y))
		budget -= maxf(moved, 0.0)
		if String(res.hit) != "" or moved <= 1e-6:
			eq_retrace_finish(st, a)
			return
		if PGeom.dist(float(p.x), float(p.y), float(tgt[0]), float(tgt[1])) <= 0.5:
			a["i"] = int(a["i"]) + 1
	if int(a["i"]) >= pts.size() or guard >= 64:
		eq_retrace_finish(st, a)

## **적 하나는 귀환 한 번당 한 번만** 맞는다(같은 적 주변을 여러 번 돌아도 중복이 없다).
## 판단은 이 귀환에만 쓰는 적 id 표(a.hit) 하나뿐이다
static func eq_retrace_hits(st: CombatState, a: Dictionary, x0: float, y0: float, x1: float, y1: float) -> void:
	var hit: Dictionary = a.hit
	var r := float(a.hit_r)
	var dmg := float(a.get("dmg", 0.0))
	for e in st.alive_targets():
		var id := int(e.id)
		if hit.has(id):
			continue
		if PGeom.dist_seg(float(e.x), float(e.y), x0, y0, x1, y1) <= r + float(e.r):
			hit[id] = true
			eq_hit(st, e, dmg, "eq_retrace", "eq_retrace", { "dir": PGeom.norm(x1 - x0, y1 - y0), "knock": 8.0 })

static func eq_retrace_finish(st: CombatState, a: Dictionary) -> void:
	st.fx({ "kind": "eq_retrace", "x": st.player.x, "y": st.player.y, "pts": (a.pts as Array).duplicate(), "ttl": 0.3 })
	st.eq_act = {}
	eq_land_valid(st)

# ---------- [8] 결정 관 ----------
static func eq_start_tomb(st: CombatState, slot: String) -> void:
	var T := eq_tune("eq_icetomb")
	st.eq_act = { "id": "eq_icetomb", "slot": slot, "phase": "encase", "t": 0.0,
		"invuln": true, "hold_seen": false, "max": float(T.get("max", 1.2)) }
	st.fx({ "kind": "eq_tomb", "x": st.player.x, "y": st.player.y, "r": float(st.player.r) + 10.0, "ttl": 0.3 })
	st.ev("freeze")

## 해제: **먼저 상태를 비운다** — 무적은 상태에서 유도하므로 여기서 그 자리에 사라진다.
## 그 뒤에 주변 적에게 냉기를 부여한다(자격표 frost_stack은 eq_icetomb를 막지 않는다)
static func eq_tomb_break(st: CombatState, _a: Dictionary, _why: String) -> void:
	var T := eq_tune("eq_icetomb")
	var p := st.player
	var r := float(T.get("r", 130.0))
	var n := int(T.get("chill", 2))
	st.eq_act = {}
	var chill_dur := float((st.cfg.get("frost", {}) as Dictionary).get("chill", 2.0)) * float(st.build.get("duration_mult", 1.0))
	var o := { "cause": "eq_icetomb", "src": { "skill": true, "direct": false, "skill_id": "eq_icetomb" } }
	for e in st.alive_targets():
		if PGeom.dist(float(e.x), float(e.y), float(p.x), float(p.y)) > r + float(e.r):
			continue
		e.chill = maxf(float(e.chill), chill_dur)
		st.add_chill_stack(e, n, o)
	st.fx({ "kind": "eq_tomb_break", "x": p.x, "y": p.y, "r": r, "ttl": 0.35 })
	st.text(p.x, p.y - 44.0, "결정 관 해제", "#bfefff")
	st.ev("shatter")

# ---------- [9] 유예의 시계 ----------
## 발동. **재사용으로 예정 피해가 조용히 사라지지 않는다** — 남아 있던 것을 먼저 정산하고 새로 시작한다
static func eq_start_reprieve(st: CombatState, slot: String) -> void:
	var T := eq_tune("eq_reprieve")
	if not st.eq_debt.is_empty():
		eq_settle(st, "재사용", false)
	st.eq_debt = { "slot": slot, "t": float(T.get("dur", 3.0)), "amount": 0.0,
		"frac": float(T.get("frac", 0.6)), "erase": float(T.get("erase", 0.5)),
		"cap": float(st.player.hp_max) * float(T.get("cap", 0.35)) }
	st.fx({ "kind": "eq_reprieve", "x": st.player.x, "y": st.player.y, "r": 34.0, "ttl": 0.3 })

static func eq_update_debt(st: CombatState, dt: float) -> void:
	var db: Dictionary = st.eq_debt
	if db.is_empty():
		return
	db["t"] = float(db.t) - dt
	if float(db.t) <= 0.0:
		eq_settle(st, "정산", false)

## 받은 피해의 일부를 예정 피해로 미룬다.
## **부르는 자리는 CombatState.apply_player_damage의 한 곳뿐이고, 모든 경감이 끝난 뒤다.**
##  · 앞에 두면 미룬 값에 경감이 다시 걸려 **방어가 두 번** 적용된다.
##  · 뒤(보호막 차감 뒤)에 두면 이미 보호막이 먹은 몫까지 다시 미루게 된다.
##  · 무적·피격 보호·보조 완전 차단에 막힌 피해는 애초에 이 함수까지 오지 않는다.
static func eq_reprieve_defer(st: CombatState, amount: float) -> float:
	var db: Dictionary = st.eq_debt
	if db.is_empty() or amount <= 0.0:
		return amount
	var room := maxf(0.0, float(db.cap) - float(db.amount))
	if room <= 0.0:
		return amount
	var moved: float = round(minf(amount * float(db.frac), room) * 10.0) / 10.0
	if moved <= 0.0:
		return amount
	db["amount"] = float(db.amount) + moved
	st.stats.equip_procs.reprieve_coat = int(st.stats.equip_procs.get("reprieve_coat", 0)) + 1
	st.text(st.player.x, st.player.y - 56.0, "유예 " + str(int(round(moved))), "#c9a0ff")
	return round((amount - moved) * 10.0) / 10.0

## 효과 중 **주무기 직접 타격**으로 실제 피해를 주면 예정 피해가 그만큼 지워진다.
## 보조무기·지속 피해·다른 파생 타격으로는 지워지지 않는다 — 경로 판정은 자격표 어휘 한 곳(frost_cause_of)만 쓴다
static func eq_reprieve_erase(st: CombatState, effective: float, o: Dictionary) -> void:
	var db: Dictionary = st.eq_debt
	if db.is_empty() or effective <= 0.0 or float(db.amount) <= 0.0:
		return
	if st.frost_cause_of(o) != "main_direct":
		return
	var cut := minf(float(db.amount), effective * float(db.erase))
	db["amount"] = maxf(0.0, round((float(db.amount) - cut) * 10.0) / 10.0)

## 정산. 예정 피해를 **없애는 유일한 출구**다 — 재사용·장비 해제·전투 종료도 전부 여기를 지난다.
## floor1 = 승리가 확정된 뒤의 정산(이미 이긴 전투를 사후 정산으로 뒤집지 않는다)
static func eq_settle(st: CombatState, why: String, floor1: bool) -> void:
	var db: Dictionary = st.eq_debt
	if db.is_empty():
		return
	var amt := float(db.amount)
	st.eq_debt = {}
	if amt <= 0.0:
		return
	st.text(st.player.x, st.player.y - 56.0, "유예 " + why, "#c9a0ff")
	st.settle_reprieve(amt, floor1)
