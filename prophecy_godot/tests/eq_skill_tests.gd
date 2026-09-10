extends SceneTree
## 장비 기술 여섯 검사(화면 없음).
## 실행: python tools/run_suites.py --suites eq_skill_tests --jobs 1
##      (직접: godot --headless --path prophecy_godot -s tests/eq_skill_tests.gd)
##
## 대상(docs/SPEC_EQUIP_SKILLBANK.md 3절 [4]~[9] · 5절 · 7절 · docs/EQUIP_SKILLS.md)
##  [4] eq_flashcut 찰나 가르기 · [5] eq_meteor 낙성 강하 · [6] eq_riposte 받아치기
##  [7] eq_retrace 되짚는 궤적 · [8] eq_icetomb 결정 관 · [9] eq_reprieve 유예의 시계
##
## 여기서 못박는 것
##  1. **그 장비를 벗으면 발동하지 않는다**(재사용 시간도 소비하지 않는다).
##  2. [4] 장애물 앞 정지 · 한 적 한 번 · 충전 중 피격 가능 · 발동 순간만 무적 · Space 취소.
##  3. [5] 발동 뒤 착지점 불변 · 유효 지형 착지 · 무적 구간이 표에 적힌 그대로(공중이라 무적이 아니다).
##  4. [6] 한 공격에 반격 1회 · 장판은 막지 않음 · 오래 눌러도 지속되지 않음.
##  5. [7] 귀환당 적 1회 · 벽 안 뚫음 · 만료 처리와 재사용 기준.
##  6. [8] **새 공격만** 중단(이미 발사한 것은 흐른다) · 취소·전환 뒤 무적이 남지 않음.
##  7. [9] 방어를 두 번 적용하지 않음 · 이미 막힌 피해를 잡지 않음 · 조용한 삭제 없음.
##  8. 7절 연계 자격: 여섯 경로가 파쇄·감전 후속·방전 충전·까마귀 표적·숙주 파열을 열지 않는다.
##
## 수치는 전부 **첫 시험값**이다(data/growth.json skills.eq_*.tune · data/world.json · data/meta.json).
## 사용자가 승인한 밸런스가 아니다.

const STEP := 1.0 / 120.0

const EQ_BLADE := "instant_blade"      # [4] 찰나의 검(무기·일반)
const EQ_MAUL := "falling_star_maul"   # [5] 낙성 추(무기·일반)
const EQ_GUARD := "counter_guard"      # [6] 받아넘김의 방패(방패·일반)
const EQ_GREAVES := "retrace_greaves"  # [7] 되짚는 각반(갑옷·일반)
const EQ_COFFIN := "crystal_coffin"    # [8] 결정 관(방패·제작)
const EQ_COAT := "reprieve_coat"       # [9] 유예의 외투(갑옷·제작)

## 배정표(보고서와 같은 순서·같은 값). 기술 id → [장비 id, 부위, 제작인가, 기본 능력치 키]
const ROWS := {
	"eq_flashcut": [EQ_BLADE, "weapon", false, "eliteDirect"],
	"eq_meteor": [EQ_MAUL, "weapon", false, "reach"],
	"eq_riposte": [EQ_GUARD, "shield", false, "bigHit"],
	"eq_retrace": [EQ_GREAVES, "armor", false, "speed"],
	"eq_icetomb": [EQ_COFFIN, "shield", true, "lowShield"],
	"eq_reprieve": [EQ_COAT, "armor", true, "hpMax"],
}

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 시험실 ----------
## 원하는 기술을 Q에 넣고 원하는 장비를 착용한 빈 전장. auto=false면 자동기술을 끈다
func mk(q_id: String, equip: Dictionary = {}, weapon: String = "sword", auto: bool = false) -> CombatState:
	var g: Dictionary = PGrowth.new_growth(weapon)
	g.skills.q = { "id": q_id, "level": 1, "variant": null } if q_id != "" else null
	var run: Dictionary = PBuild.empty_run_like(g)
	var eqd: Dictionary = run.equipment
	for slot in equip:
		eqd[String(slot)] = String(equip[slot])
	var b: Dictionary = PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "arena": "clearing",
		"waves": [], "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.face = 0.0
	if not auto:
		st.player.attack_timer = 1.0e9
	return st

## 그 기술과 그 기술을 주는 장비를 함께 갖춘 전장(정상 사용 경로)
func armed(sid: String, weapon: String = "sword", auto: bool = false) -> CombatState:
	var row: Array = ROWS[sid]
	return mk(sid, { String(row[1]): String(row[0]) }, weapon, auto)

func dummy(st: CombatState, dx: float, dy: float = 0.0, hp: float = 1000000.0, type_id: String = "wolf") -> Dictionary:
	var e: Dictionary = st.spawn_enemy(type_id, float(st.player.x) + dx, float(st.player.y) + dy)
	e.hp = hp
	e.hp_max = hp
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

## 입력 사전. held를 주면 '유지 상태를 함께 알려주는 입력 경로'를 흉내 낸다
func inp(q: bool = false, e: bool = false, dodge: bool = false, mx: float = 0.0, my: float = 0.0) -> Dictionary:
	return { "mx": mx, "my": my, "dodge_press": dodge, "dodge_held": false, "special": q, "skill_e": e }

func inp_hold(q_hold: bool, q_press: bool = false) -> Dictionary:
	var d := inp(q_press)
	d["special_held"] = q_hold
	return d

## 단계 진행(전투 규칙 전체를 통과시킨다 — 중간 상태 주입이 아니다)
func run_steps(st: CombatState, seconds: float, input: Dictionary = {}) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		st.step(input if not input.is_empty() else inp(), STEP)

## 위와 같되 시험 대상 적을 제자리에 묶어 둔다(pins = [[적, x, y], ...]).
## 왜 필요한가 — 적은 살아 있으면 플레이어를 향해 걸어온다. 거리로 갈리는 판정(중심/바깥)을 잴 때
## 그 이동이 섞이면 무엇을 쟀는지 알 수 없다. **규칙은 그대로 돌리고 좌표만 고정한다.**
func run_steps_pinned(st: CombatState, seconds: float, input: Dictionary, pins: Array) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		st.step(input if not input.is_empty() else inp(), STEP)
		for row in pins:
			var e: Dictionary = row[0]
			e.x = float(row[1])
			e.y = float(row[2])

func near(a: float, b: float, tol: float = 0.06) -> bool:
	return absf(a - b) <= tol

func tune(sid: String) -> Dictionary:
	return PSkills.eq_tune(sid)

func _init() -> void:
	sec0_defs()
	sec1_flashcut()
	sec2_meteor()
	sec3_riposte()
	sec4_retrace()
	sec5_icetomb()
	sec6_reprieve()
	sec7_eligibility()
	sec8_cleanup()
	sec9_focus()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 0. 정의·배정표·성장 없음 ----------
func sec0_defs() -> void:
	var SK := PCatalog.skills()
	var all_ok := true
	var bad := ""
	for sid in PSkills.EQ_IDS:
		var d: Dictionary = SK.get(String(sid), {})
		# 레벨 없음(max 1) · 개조 없음(variants 없음) · 재사용 표는 한 칸
		if d.is_empty() or int(d.get("max", 3)) != 1 or d.has("variants") or (d.cooldown as Array).size() != 1:
			all_ok = false
			bad += String(sid) + " "
	ok("5절: 여섯 기술 모두 **레벨 없음(max 1)·개조 없음(variants 없음)**", all_ok, bad)

	var e_list: Array = PCatalog.e_skills()
	var none_in_pool := true
	for sid in PSkills.EQ_IDS:
		if e_list.has(String(sid)):
			none_in_pool = false
	ok("5절: 여섯 기술이 **일반 수동 기술 후보 목록(e_skills)에 없다** — 레벨업 3택·상점 진열에 섞이지 않는다",
		none_in_pool, str(e_list))

	var map_ok := true
	var map_bad := ""
	for sid in ROWS:
		var row: Array = ROWS[sid]
		var d: Dictionary = PCatalog.equipment_def(String(row[0]))
		var eff: Dictionary = d.get("eff", {})
		# 기본 능력치 **하나** + 고유 효과(grantsSkill) · 부위 · 일반/제작 구분
		if d.is_empty() or String(d.slot) != String(row[1]) or eff.size() != 1 or not eff.has(String(row[3])) \
				or String(d.get("grantsSkill", "")) != String(sid) or PCatalog.is_crafted(String(row[0])) != bool(row[2]):
			map_ok = false
			map_bad += "%s(%s) " % [String(row[0]), str(eff.keys())]
	ok("2절: 여섯 장비 모두 **기본 능력치 하나 + 고유 효과(grantsSkill)**이고 부위·일반/제작이 배정표와 같다", map_ok, map_bad)

	ok("2절: 장비 슬롯은 여전히 셋뿐이다 — 슬롯을 늘리지 않았다",
		(PCatalog.world().equip_slots as Array).size() == 3)

	# 강화 표는 **기본 능력치 경로만** 담는다(4절: 횟수·단계·지속·재사용·무적 시간은 넣지 않는다)
	var up_ok := true
	var up_bad := ""
	for sid in ROWS:
		var row: Array = ROWS[sid]
		var d: Dictionary = PCatalog.equipment_def(String(row[0]))
		for path in (d.get("upgrade", {}) as Dictionary):
			if not String(path).begins_with(String(row[3])):
				up_ok = false
				up_bad += "%s:%s " % [String(row[0]), String(path)]
	ok("4절: 강화 표에 **기본 능력치 경로만** 있다(기술 성능·무적 시간은 강화로 오르지 않는다)", up_ok, up_bad)

	# 강화 +2를 걸어도 기술 조절값(tune)은 한 글자도 달라지지 않는다
	var t0: Dictionary = tune("eq_flashcut")
	var eff2: Dictionary = PCatalog.equipment_eff(EQ_BLADE, 2)
	ok("4절: 장비 강화 +2는 기본 능력치만 올린다 — 기술 조절값은 그대로",
		float(eff2.get("eliteDirect", 0.0)) > float((PCatalog.equipment_def(EQ_BLADE).eff as Dictionary).eliteDirect)
		and not eff2.has("grantsSkill") and near(float(t0.len), 240.0),
		"eliteDirect %s · len %s" % [str(eff2.get("eliteDirect", 0.0)), str(t0.len)])

	var gl: Dictionary = PCatalog.glossary()
	var gl_ok := gl.has("eq_skill")
	for sid in ROWS:
		if not gl.has("eq:" + String(ROWS[sid][0])):
			gl_ok = false
	ok("용어 사전에 '장비 기술'과 여섯 장비 항목이 있다", gl_ok)

	# 폐기 장비 '반격 방패'와 신규 '받아넘김의 방패'는 **다른 것**이다(이름·자료 id·효과 모두)
	var old_d: Dictionary = PCatalog.equipment_def("reprisal_shield")
	var new_d: Dictionary = PCatalog.equipment_def(EQ_GUARD)
	ok("3절 [6]: 폐기 '반격 방패'(reprisal_shield)와 신규 '받아넘김의 방패'(counter_guard)는 자료 id·이름·효과가 다르다",
		String(old_d.name) != String(new_d.name) and PCatalog.equipment_retired("reprisal_shield")
		and not PCatalog.equipment_retired(EQ_GUARD) and not (new_d.eff as Dictionary).has("reprisal")
		and not (old_d as Dictionary).has("grantsSkill"))

	# **장비를 벗으면 발동하지 않는다**(재사용 시간도 소비하지 않는다)
	var st_off := mk("eq_flashcut", {})
	var fired: bool = PSkills.cast(st_off, "q")
	ok("5절: 그 장비를 착용하지 않으면 발동하지 않고 **재사용 시간도 소비하지 않는다**",
		not fired and st_off.eq_act.is_empty() and is_zero_approx(float(st_off.player.special_cd)))

	var st_on := armed("eq_flashcut")
	ok("5절: 착용하면 발동한다(같은 빌드·같은 기술)", PSkills.cast(st_on, "q") and not st_on.eq_act.is_empty())

	# 슬롯 조건은 일반 기술과 똑같이 적용된다 — 재사용 시계는 그 칸의 표를 읽는다
	ok("5절: 재사용 시간은 그 칸의 기술 표(cooldown[0])를 그대로 쓴다",
		near(PSkills.cd_of(st_on, "q"), float((PCatalog.skills().eq_flashcut.cooldown as Array)[0])),
		str(PSkills.cd_of(st_on, "q")))

	# E 칸에서도 같은 기술이 그대로 동작한다(칸이 기술을 정하지 않는다)
	var g_e: Dictionary = PGrowth.new_growth("sword")
	g_e.skills.q = null
	g_e.skills.e = { "id": "eq_flashcut", "level": 1, "variant": null }
	var run_e: Dictionary = PBuild.empty_run_like(g_e)
	(run_e.equipment as Dictionary).weapon = EQ_BLADE
	# 방패에 '시전자의 방패'를 함께 끼운다 — **E 사용 시** 보호막이라는 슬롯 조건이 장비 기술에도 걸려야 한다
	(run_e.equipment as Dictionary).shield = "caster_shield"
	var st_e := CombatState.new({ "build": PBuild.derive(run_e), "seed": 1, "arena": "clearing",
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st_e.spawn_hold = true
	st_e.player.attack_timer = 1.0e9
	var sh0: float = float(st_e.player.shield)
	var cast_e: bool = PSkills.cast(st_e, "e")
	ok("5절: **칸이 기술을 정하지 않는다** — E에 넣어도 그대로 발동하고 E 시계를 쓴다",
		cast_e and not st_e.eq_act.is_empty() and float(st_e.player.e_cd) > 0.0 and is_zero_approx(float(st_e.player.special_cd)))
	ok("5절: 슬롯 조건('E 사용 시' 시전자의 방패)은 **장비 기술에도 그대로** 걸린다 — 고정 성능이 상호작용을 무시한다는 뜻이 아니다",
		float(st_e.player.shield) > sh0 and int(st_e.stats.e_uses) == 1,
		"보호막 %s → %s" % [str(sh0), str(st_e.player.shield)])

# ---------- [4] 찰나 가르기 ----------
func sec1_flashcut() -> void:
	var T := tune("eq_flashcut")

	# 충전 중: 제자리 · 무적 아님 · 실제로 맞는다
	var st := armed("eq_flashcut")
	var x0: float = float(st.player.x)
	PSkills.cast(st, "q")
	run_steps(st, 0.2, inp(false, false, false, 1.0, 0.0)) # 이동 입력을 줘도 제자리
	var moved_while_charging: float = absf(float(st.player.x) - x0)
	var hp0: float = float(st.player.hp)
	var landed: bool = st.damage_player(10.0, "wolf:bite", null)
	ok("[4] 충전 중에는 **제자리에서** 방향만 고른다(이동 입력을 줘도 움직이지 않는다)",
		moved_while_charging < 0.001, str(moved_while_charging))
	ok("[4] 충전 중에는 **공격받을 수 있다**(무적이 아니다)",
		landed and float(st.player.hp) < hp0 and not PSkills.eq_invuln(st),
		"hp %s → %s" % [str(hp0), str(st.player.hp)])

	# 놓으면 순간 이동 + 경로의 적을 한 번씩 · 큰 적도 한 번
	var st2 := armed("eq_flashcut")
	var mid := dummy(st2, 120.0, 0.0)
	var big := dummy(st2, 200.0, 0.0)
	big.r = 60.0 # 아주 큰 적: 경로를 길게 덮는다
	var far := dummy(st2, 400.0, 0.0) # 사거리(240) 밖
	var mid0: float = float(mid.hp)
	var big0: float = float(big.hp)
	var far0: float = float(far.hp)
	PSkills.cast(st2, "q")
	st2.step(inp(true), STEP) # 재입력 = 즉시 발동
	var dmg: float = float((PCatalog.skills().eq_flashcut.damage as Array)[0])
	ok("[4] 경로의 적을 **한 번씩** 벤다(적 몸은 관통한다)",
		near(mid0 - float(mid.hp), dmg) and near(far0 - float(far.hp), 0.0),
		"가운데 %s / 사거리 밖 %s" % [str(mid0 - float(mid.hp)), str(far0 - float(far.hp))])
	ok("[4] **큰 적이라는 이유로 같은 발동에 여러 번 맞지 않는다**(반지름 60이어도 1회)",
		near(big0 - float(big.hp), dmg), str(big0 - float(big.hp)))
	ok("[4] 순간 이동 거리 = 표의 값(장애물이 없을 때)",
		near(float(st2.player.x) - 400.0, float(T.len), 1.0), str(float(st2.player.x) - 400.0))

	# 발동하는 짧은 순간에만 무적
	ok("[4] **발동하는 짧은 순간에만 무적**이다", PSkills.eq_invuln(st2) and not st2.damage_player(10.0, "wolf:bite", null))
	run_steps(st2, float(T.blink) + 2.0 * STEP)
	ok("[4] 그 순간이 지나면 무적이 **남지 않는다**(상태가 비고 다시 맞는다)",
		st2.eq_act.is_empty() and not PSkills.eq_invuln(st2) and st2.damage_player(10.0, "wolf:bite", null))

	# 벽·바위 앞에서 멈춘다
	var st3 := armed("eq_flashcut")
	st3.obstacles = [{ "id": "r1", "type": "rock", "x": float(st3.player.x) + 120.0, "y": float(st3.player.y), "r": 40.0 }]
	PSkills.cast(st3, "q")
	st3.step(inp(true), STEP)
	var dx3: float = float(st3.player.x) - 400.0
	ok("[4] **벽·바위·나무는 통과하지 않고 장애물 앞 유효한 위치에서 멈춘다**",
		dx3 > 0.0 and dx3 < float(T.len) - 40.0 and st3.valid_pos(float(st3.player.x), float(st3.player.y), float(st3.player.r)),
		"이동 %s (표 %s)" % [str(dx3), str(T.len)])

	# 충전 중 Space로 취소 — 재사용 시간도 돌려받는다
	var st4 := armed("eq_flashcut")
	PSkills.cast(st4, "q")
	var cd_charging: float = float(st4.player.special_cd)
	st4.step(inp(false, false, true), STEP)
	ok("[4] **충전 중 Space로 취소**된다 — 상태가 사라지고 재사용 시간을 돌려받는다",
		st4.eq_act.is_empty() and is_zero_approx(float(st4.player.special_cd)) and cd_charging > 0.0,
		"취소 전 %s → 취소 후 %s" % [str(cd_charging), str(st4.player.special_cd)])
	ok("[4] 취소한 그 단계에 **회피가 대신 나가지 않는다**(같은 Space가 두 가지로 쓰이지 않는다)",
		not bool(st4.player.dodge_active) and int(st4.stats.dodges) == 0)

	# 최대 충전 시간이면 자동으로 나간다(입력이 끊겨도 충전이 남지 않는다)
	var st5 := armed("eq_flashcut")
	PSkills.cast(st5, "q")
	run_steps(st5, float(T.charge) + float(T.blink) + 4.0 * STEP)
	ok("[4] 입력이 끊겨도 **최대 충전 시간**에 자동으로 나가고 충전이 남지 않는다",
		st5.eq_act.is_empty() and float(st5.player.x) > 400.0, str(st5.player.x))

	# 유지 상태를 함께 주는 입력 경로에서는 '놓는 순간' 나간다
	var st6 := armed("eq_flashcut")
	PSkills.cast(st6, "q")
	st6.step(inp_hold(true), STEP)
	st6.step(inp_hold(true), STEP)
	var before_release: bool = not st6.eq_act.is_empty() and String(st6.eq_act.phase) == "charge"
	st6.step(inp_hold(false), STEP)
	ok("[4] 유지 상태를 주는 입력에서는 **놓는 순간** 발동한다",
		before_release and (st6.eq_act.is_empty() or String(st6.eq_act.phase) == "blink") and float(st6.player.x) > 400.0,
		str(st6.player.x))

# ---------- [5] 낙성 강하 ----------
func sec2_meteor() -> void:
	var T := tune("eq_meteor")
	var dmg: float = float((PCatalog.skills().eq_meteor.damage as Array)[0])

	# 발동 뒤 착지점을 계속 추적해 바꾸지 않는다
	var st := armed("eq_meteor")
	PSkills.cast(st, "q")
	run_steps(st, 0.1)
	st.step(inp(true), STEP) # 놓는다 → 여기서 착지점 확정
	var tx: float = float(st.eq_act.tx)
	var ty: float = float(st.eq_act.ty)
	st.player.face = PI # 도약 중 반대쪽을 봐도
	run_steps(st, 0.15)
	var still: bool = near(float(st.eq_act.tx), tx, 0.001) and near(float(st.eq_act.ty), ty, 0.001)
	ok("[5] **발동 뒤 착지점을 계속 추적해 바꾸지 않는다**(도약 중 방향을 돌려도 그대로)",
		still, "확정 (%s, %s)" % [str(tx), str(ty)])

	# 무적 범위가 표에 적힌 그대로다 — '공중이라 무적'이 아니다
	var st2 := armed("eq_meteor")
	PSkills.cast(st2, "q")
	st2.step(inp(true), STEP)
	run_steps(st2, float(T.invuln_to) * 0.5)
	var iv_mid: bool = PSkills.eq_invuln(st2)
	run_steps(st2, float(T.invuln_to) * 0.5 + 2.0 * STEP)
	var iv_late: bool = PSkills.eq_invuln(st2)
	ok("[5] 도약 무적 구간을 **명시적으로** 지킨다: %s~%s초 무적, 내려찍는 마지막 %s초는 피격 가능"
		% [str(T.invuln_from), str(T.invuln_to), str(float(T.leap) - float(T.invuln_to))],
		iv_mid and not iv_late, "중간 %s / 후반 %s" % [str(iv_mid), str(iv_late)])
	ok("[5] 충전 중에는 무적이 아니다('공중'과 무관하게 무적을 암묵적으로 주지 않는다)",
		not PSkills.eq_invuln(armed("eq_meteor")))

	# 유효하지 않은 지형에 착지하지 않는다
	var st3 := armed("eq_meteor")
	st3.obstacles = [{ "id": "r1", "type": "rock", "x": float(st3.player.x) + float(T.range), "y": float(st3.player.y), "r": 70.0 }]
	PSkills.cast(st3, "q")
	st3.step(inp(true), STEP)
	var aimed_valid: bool = st3.valid_pos(float(st3.eq_act.tx), float(st3.eq_act.ty), float(st3.player.r))
	run_steps(st3, float(T.leap) + 4.0 * STEP)
	ok("[5] **유효하지 않은 지형에 착지하지 않는다**(장애물 자리를 겨눠도 유효한 자리로 당겨진다)",
		aimed_valid and st3.valid_pos(float(st3.player.x), float(st3.player.y), float(st3.player.r)) and st3.eq_act.is_empty())

	# 중심 강타와 바깥 충격파는 배타적 — 한 적이 두 번 맞지 않는다
	var st4 := armed("eq_meteor")
	var core := dummy(st4, float(T.range), 0.0)
	var ring := dummy(st4, float(T.range) + float(T.core_r) + 30.0, 0.0)
	var out := dummy(st4, float(T.range) + float(T.wave_r) + 80.0, 0.0)
	var c0: float = float(core.hp)
	var r0: float = float(ring.hp)
	var o0: float = float(out.hp)
	var pins := [[core, core.x, core.y], [ring, ring.x, ring.y], [out, out.x, out.y]]
	PSkills.cast(st4, "q")
	st4.step(inp(true), STEP)
	run_steps_pinned(st4, float(T.leap) + 4.0 * STEP, inp(), pins)
	ok("[5] 중심은 강타, 바깥은 약한 충격파이고 **한 적이 둘 다 맞지 않는다**",
		near(c0 - float(core.hp), dmg) and near(r0 - float(ring.hp), dmg * float(T.wave_mult)) and near(o0 - float(out.hp), 0.0),
		"중심 %s / 바깥 %s / 범위 밖 %s" % [str(c0 - float(core.hp)), str(r0 - float(ring.hp)), str(o0 - float(out.hp))])

# ---------- [6] 받아치기 ----------
func sec3_riposte() -> void:
	var T := tune("eq_riposte")
	var dmg: float = float((PCatalog.skills().eq_riposte.damage as Array)[0])

	# 정면 직접 타격 1회를 막고 강한 반격 1회 — 같은 창으로 두 번 막지 않는다
	var st := armed("eq_riposte")
	var front := dummy(st, 60.0, 0.0)
	var h0: float = float(front.hp)
	var hp0: float = float(st.player.hp)
	PSkills.cast(st, "q")
	var blocked: bool = st.damage_player(20.0, "wolf:bite", front)
	var counter: float = h0 - float(front.hp)
	var hp_after_block: float = float(st.player.hp)
	st.player.hit_prot = 0.0
	var second: bool = st.damage_player(20.0, "wolf:bite", front) # 방어가 끝났으므로 이번에는 들어간다
	ok("[6] 정면 직접 타격을 **한 번 막고 강한 부채꼴 반격**이 나간다",
		not blocked and near(hp_after_block, hp0) and near(counter, dmg),
		"반격 %s (기대 %s) · 체력 %s → %s" % [str(counter), str(dmg), str(hp0), str(hp_after_block)])
	ok("[6] **같은 공격 한 번으로 반격이 중복 발생하지 않는다** — 막는 즉시 방어가 끝난다",
		st.eq_guard.is_empty() and second and near(h0 - float(front.hp), dmg),
		"누적 반격 %s" % str(h0 - float(front.hp)))
	ok("[6] 반격 계측이 1회만 오른다", int((st.stats.equip_procs as Dictionary).get("counter_guard", 0)) == 1)

	# 등 뒤는 막지 않는다
	var st2 := armed("eq_riposte")
	var back := dummy(st2, -60.0, 0.0)
	PSkills.cast(st2, "q")
	var back_hit: bool = st2.damage_player(20.0, "wolf:bite", back)
	ok("[6] **정면**만 막는다(등 뒤 타격은 그대로 들어간다)", back_hit and not st2.eq_guard.is_empty())

	# 장판·지속 피해는 막지 않는다
	var st3 := armed("eq_riposte")
	var hp3: float = float(st3.player.hp)
	PSkills.cast(st3, "q")
	st3.zone_damage(9.0)
	var zone_took: bool = float(st3.player.hp) < hp3
	st3.player.hit_prot = 0.0
	var hp3b: float = float(st3.player.hp)
	var attacker3 := dummy(st3, 60.0, 0.0)
	st3.damage_player(7.0, "frostzone", attacker3)
	ok("[6] **장판·지속 피해는 막지 않는다**(공통 장판 경로와 바닥 지대 둘 다)",
		zone_took and float(st3.player.hp) < hp3b and not st3.eq_guard.is_empty(),
		"장판 %s / 바닥 지대 %s" % [str(zone_took), str(float(st3.player.hp) < hp3b)])

	# 투사체에도 대응한다(정면·발사자 있음)
	var st4 := armed("eq_riposte")
	var shooter := dummy(st4, 90.0, 0.0)
	PSkills.cast(st4, "q")
	var arrow_blocked: bool = st4.damage_player(12.0, "arrow", shooter)
	ok("[6] 정면 **투사체**에도 대응한다", not arrow_blocked and st4.eq_guard.is_empty())

	# 오래 눌러도 지속 방어하지 않는다 — 고정 시간이고 유지 입력을 아예 읽지 않는다
	var st5 := armed("eq_riposte")
	PSkills.cast(st5, "q")
	var push_t := dummy(st5, 40.0, 0.0)
	var p0: float = float(push_t.hp)
	run_steps(st5, float(T.guard) - 4.0 * STEP, inp_hold(true))
	var alive_guard: bool = not st5.eq_guard.is_empty()
	run_steps(st5, 8.0 * STEP, inp_hold(true))
	ok("[6] **오래 눌러도 지속 방어하지 않는다**(유지 입력과 무관하게 %s초에 끝난다)" % str(T.guard),
		alive_guard and st5.eq_guard.is_empty(), "유지 입력 중에도 종료됨")
	ok("[6] 못 막으면 **약한 방패 밀치기**로 끝난다",
		near(p0 - float(push_t.hp), dmg * float(T.push_mult)),
		"밀치기 %s (기대 %s)" % [str(p0 - float(push_t.hp)), str(dmg * float(T.push_mult))])

# ---------- [7] 되짚는 궤적 ----------
func sec4_retrace() -> void:
	var T := tune("eq_retrace")
	var dmg: float = float((PCatalog.skills().eq_retrace.damage as Array)[0])

	# 첫 입력에는 재사용 시간이 걸리지 않는다
	var st := armed("eq_retrace")
	PSkills.cast(st, "q")
	ok("[7] 첫 입력은 **기록만** 시작하고 재사용 시간을 걸지 않는다",
		not st.eq_trail.is_empty() and is_zero_approx(float(st.player.special_cd)))

	# 이동하며 기록 → 재입력 → 거슬러 돌아오며 경로의 적을 친다. **적 하나는 귀환 한 번당 한 번만**
	var st2 := armed("eq_retrace")
	PSkills.cast(st2, "q")
	var mark_x: float = float(st2.player.x)
	var target := dummy(st2, 40.0, 0.0) # 표시한 자리 바로 옆 — 왕복해도 한 번만 맞아야 한다
	var t0: float = float(target.hp)
	run_steps(st2, 0.5, inp(false, false, false, 1.0, 0.0))
	run_steps(st2, 0.5, inp(false, false, false, -1.0, 0.0)) # 같은 적 주변을 여러 번 지난다
	run_steps(st2, 0.5, inp(false, false, false, 1.0, 0.0))
	var pts_n: int = (st2.eq_trail.pts as Array).size()
	st2.step(inp(true), STEP) # 재입력 = 귀환
	var cd_after: float = float(st2.player.special_cd)
	run_steps(st2, 1.0)
	ok("[7] 재입력하면 기록한 길을 거슬러 돌아와 **표시한 자리 근처**에서 끝난다",
		st2.eq_act.is_empty() and absf(float(st2.player.x) - mark_x) < 40.0,
		"표시 %s → 귀환 %s (기록 %d점)" % [str(mark_x), str(st2.player.x), pts_n])
	ok("[7] **적 하나는 귀환 한 번당 한 번만** 맞는다(같은 적 주변을 여러 번 돌아도 중복 없음)",
		near(t0 - float(target.hp), dmg), "받은 피해 %s (기대 %s)" % [str(t0 - float(target.hp)), str(dmg)])
	ok("[7] 재사용 시간은 **귀환할 때** 걸린다", cd_after > 0.0, str(cd_after))

	# 기록 시간·길이가 유한하다 + 만료 처리
	var st3 := armed("eq_retrace")
	PSkills.cast(st3, "q")
	run_steps(st3, float(T.record) + 4.0 * STEP, inp(false, false, false, 1.0, 0.0))
	ok("[7] **기록 시간이 유한하다** — 만료되면 기록이 사라지고 그때 재사용 시간이 걸린다",
		st3.eq_trail.is_empty() and float(st3.player.special_cd) > 0.0, str(st3.player.special_cd))

	var st3b := armed("eq_retrace")
	PSkills.cast(st3b, "q")
	run_steps(st3b, float(T.record) - 0.2, inp(false, false, false, 1.0, 0.0))
	ok("[7] **기록 길이가 유한하다**(최대 %d점을 넘지 않는다)" % int(T.max_pts),
		(st3b.eq_trail.pts as Array).size() <= int(T.max_pts), str((st3b.eq_trail.pts as Array).size()))

	# 기록 뒤 지형이 달라져도 벽을 뚫지 않는다
	var st4 := armed("eq_retrace")
	PSkills.cast(st4, "q")
	var start_x: float = float(st4.player.x)
	run_steps(st4, 0.8, inp(false, false, false, 1.0, 0.0))
	var far_x: float = float(st4.player.x)
	# 기록한 뒤에 길 한가운데에 바위가 생겼다
	st4.obstacles = [{ "id": "r1", "type": "rock", "x": (start_x + far_x) * 0.5, "y": float(st4.player.y), "r": 40.0 }]
	st4.step(inp(true), STEP)
	run_steps(st4, 1.0)
	ok("[7] **기록 후 지형이 달라져도 벽을 뚫거나 유효하지 않은 위치로 가지 않는다**(막히면 그 자리에서 끝난다)",
		st4.eq_act.is_empty() and st4.valid_pos(float(st4.player.x), float(st4.player.y), float(st4.player.r))
		and float(st4.player.x) > (start_x + far_x) * 0.5,
		"바위 %s / 최종 %s" % [str((start_x + far_x) * 0.5), str(st4.player.x)])

# ---------- [8] 결정 관 ----------
func sec5_icetomb() -> void:
	var T := tune("eq_icetomb")

	# 갇힘: 피해를 막고 이동이 멈춘다(장판도 막힌다)
	var st := armed("eq_icetomb")
	PSkills.cast(st, "q")
	var hp0: float = float(st.player.hp)
	var x0: float = float(st.player.x)
	run_steps(st, 0.2, inp(false, false, false, 1.0, 0.0))
	var took: bool = st.damage_player(25.0, "wolf:bite", null)
	st.zone_damage(9.0)
	ok("[8] 갇혀 있는 동안 **피해를 막고 이동이 멈춘다**(장판 피해도 막는다)",
		not took and near(float(st.player.hp), hp0) and near(float(st.player.x), x0, 0.001) and PSkills.eq_invuln(st),
		"hp %s / x %s" % [str(st.player.hp), str(st.player.x)])
	ok("[8] 갇힘 중에는 회피도 나가지 않는다",
		int(st.stats.dodges) == 0 and not bool(st.player.dodge_active))

	# 새 공격만 멈춘다: 자동기술은 발사하지 않지만 **이미 예약된 지연 효과는 흐른다**
	var st2 := armed("eq_icetomb", "sword", true)
	dummy(st2, 60.0, 0.0)
	run_steps(st2, 1.0)
	var atk_before: int = int(st2.stats.attacks)
	var ticked := [0]
	st2.delayed.append({ "t": 0.15, "fn": func(): ticked[0] = 1 })
	PSkills.cast(st2, "q")
	run_steps(st2, 0.6)
	var atk_during: int = int(st2.stats.attacks)
	PSkills.eq_release(st2, "test")
	run_steps(st2, 1.0)
	ok("[8] 갇힘 중에는 자동기술이 **새 공격을 시작하지 않는다**",
		atk_during == atk_before and atk_before > 0, "%d → %d" % [atk_before, atk_during])
	ok("[8] 그동안에도 **이미 예약된 지연 효과는 그대로 흐른다**(설치된 것과 새 공격을 구분한다)",
		ticked[0] == 1)
	ok("[8] 해제한 뒤에는 자동기술이 다시 나간다", int(st2.stats.attacks) > atk_during, str(st2.stats.attacks))

	# 해제하면 주변 적에게 냉기 부여 + 무적이 남지 않는다
	var st3 := armed("eq_icetomb")
	var near_e := dummy(st3, 80.0, 0.0)
	var far_e := dummy(st3, float(T.r) + 200.0, 0.0)
	PSkills.cast(st3, "q")
	run_steps(st3, 0.2)
	st3.step(inp(true), STEP) # 재입력 = 해제
	ok("[8] 놓으면 해제되며 **주변 적에게 냉기**를 준다(사거리 밖은 그대로)",
		int(near_e.get("chill_n", 0)) == int(T.chill) and float(near_e.chill) > 0.0 and int(far_e.get("chill_n", 0)) == 0,
		"가까이 %d / 멀리 %d" % [int(near_e.get("chill_n", 0)), int(far_e.get("chill_n", 0))])
	ok("[8] 해제하면 **무적이 남지 않는다**",
		st3.eq_act.is_empty() and not PSkills.eq_invuln(st3) and st3.damage_player(10.0, "wolf:bite", null))

	# 최대 유지 시간이 유한하다
	var st4 := armed("eq_icetomb")
	PSkills.cast(st4, "q")
	run_steps(st4, float(T.max) + 4.0 * STEP)
	ok("[8] **최대 유지 시간이 유한하다**(입력이 끊겨도 %s초에 스스로 풀린다)" % str(T.max),
		st4.eq_act.is_empty() and not PSkills.eq_invuln(st4))

	# 버튼 취소(Space)로도 무적이 남지 않는다
	var st5 := armed("eq_icetomb")
	PSkills.cast(st5, "q")
	run_steps(st5, 0.1)
	st5.step(inp(false, false, true), STEP)
	ok("[8] **버튼 취소(Space) 뒤에도 무적 상태가 남지 않는다**",
		st5.eq_act.is_empty() and not PSkills.eq_invuln(st5) and st5.damage_player(10.0, "wolf:bite", null))

# ---------- [9] 유예의 시계 ----------
func sec6_reprieve() -> void:
	var T := tune("eq_reprieve")

	# 받은 피해의 일부만 즉시 들어가고 나머지는 예정으로 잡힌다
	var st := armed("eq_reprieve")
	PSkills.cast(st, "q")
	var hp0: float = float(st.player.hp)
	st.damage_player(20.0, "wolf:bite", null)
	var now_taken: float = hp0 - float(st.player.hp)
	var deferred: float = float(st.eq_debt.amount)
	ok("[9] 받은 피해의 일부를 **예정된 피해로 표시**하고 나머지만 즉시 깎는다",
		near(deferred, 20.0 * float(T.frac)) and near(now_taken, 20.0 - deferred),
		"즉시 %s / 예정 %s" % [str(now_taken), str(deferred)])
	ok("[9] **방어를 두 번 적용하지 않는다**: 즉시분 + 예정분 = 경감이 끝난 그 값 하나",
		near(now_taken + deferred, 20.0), str(now_taken + deferred))

	# 이미 막힌 피해는 예정으로 잡히지 않는다
	var st2 := armed("eq_reprieve")
	PSkills.cast(st2, "q")
	st2.player.invuln_t = 0.5
	st2.damage_player(30.0, "wolf:bite", null)
	ok("[9] **이미 막힌 피해를 예정 피해로 잡지 않는다**(무적으로 막힌 타격은 잡히지 않는다)",
		is_zero_approx(float(st2.eq_debt.amount)), str(st2.eq_debt.amount))

	# 상한이 있다
	var st3 := armed("eq_reprieve")
	PSkills.cast(st3, "q")
	for i in 8:
		st3.player.hit_prot = 0.0
		st3.player.hp = float(st3.player.hp_max)
		st3.damage_player(30.0, "wolf:bite", null)
	ok("[9] 예정 피해에 **상한**이 있다(최대 체력의 %d%%)" % int(float(T.cap) * 100.0),
		float(st3.eq_debt.amount) <= float(st3.player.hp_max) * float(T.cap) + 0.05,
		"%s / 상한 %s" % [str(st3.eq_debt.amount), str(float(st3.player.hp_max) * float(T.cap))])

	# 주무기 직접 타격으로 지워지고, 보조·지속 피해로는 지워지지 않는다
	var st4 := armed("eq_reprieve")
	PSkills.cast(st4, "q")
	st4.damage_player(20.0, "wolf:bite", null)
	var d0: float = float(st4.eq_debt.amount)
	var e4 := dummy(st4, 60.0, 0.0)
	st4.damage_enemy(e4, 10.0, { "src": { "weapon_id": "sword", "weapon": { "damage": 10.0 }, "direct": true } })
	var after_main: float = float(st4.eq_debt.amount)
	st4.damage_enemy(e4, 10.0, { "cause": "zone_tick", "src": { "extra": true, "direct": false, "tag": "common:ember" } })
	st4.damage_enemy(e4, 10.0, { "dot": "burn", "src": { "direct": false, "tag": "dot:burn" } })
	var after_other: float = float(st4.eq_debt.amount)
	ok("[9] 효과 중 **주무기로 실제 피해를 주면 예정 피해 일부를 지운다**",
		near(d0 - after_main, 10.0 * float(T.erase)) and after_main > 0.0,
		"%s → %s" % [str(d0), str(after_main)])
	ok("[9] **보조무기·지속 피해만으로는 자동으로 지워지지 않는다**",
		near(after_other, after_main), "%s → %s" % [str(after_main), str(after_other)])

	# 정산: 끝나면 남은 예정 피해가 실제로 들어간다
	var st5 := armed("eq_reprieve")
	PSkills.cast(st5, "q")
	st5.damage_player(20.0, "wolf:bite", null)
	var pending5: float = float(st5.eq_debt.amount)
	var hp5: float = float(st5.player.hp)
	run_steps(st5, float(T.dur) + 4.0 * STEP)
	ok("[9] 끝나면 **남은 예정 피해를 정산한다**",
		st5.eq_debt.is_empty() and near(hp5 - float(st5.player.hp), pending5),
		"예정 %s / 실제 %s" % [str(pending5), str(hp5 - float(st5.player.hp))])

	# 재사용으로 조용히 사라지지 않는다 — 먼저 정산하고 새로 시작한다
	var st6 := armed("eq_reprieve")
	PSkills.cast(st6, "q")
	st6.damage_player(20.0, "wolf:bite", null)
	var pending6: float = float(st6.eq_debt.amount)
	var hp6: float = float(st6.player.hp)
	st6.player.special_cd = 0.0
	PSkills.cast(st6, "q") # 재사용
	ok("[9] **재사용으로 예정 피해가 조용히 삭제되지 않는다**(먼저 정산하고 새로 시작한다)",
		near(hp6 - float(st6.player.hp), pending6) and is_zero_approx(float(st6.eq_debt.amount)),
		"정산 %s (예정 %s)" % [str(hp6 - float(st6.player.hp)), str(pending6)])

	# 장비 해제로도 조용히 사라지지 않는다
	var st7 := armed("eq_reprieve")
	PSkills.cast(st7, "q")
	st7.damage_player(20.0, "wolf:bite", null)
	var pending7: float = float(st7.eq_debt.amount)
	var hp7: float = float(st7.player.hp)
	var g7: Dictionary = PGrowth.new_growth("sword")
	g7.skills.q = { "id": "eq_reprieve", "level": 1, "variant": null }
	st7.rebuild(PBuild.derive(PBuild.empty_run_like(g7))) # 장비를 벗은 빌드
	ok("[9] **장비 해제로도 예정 피해가 조용히 삭제되지 않는다**(그 자리에서 정산한다)",
		st7.eq_debt.is_empty() and near(hp7 - float(st7.player.hp), pending7),
		"정산 %s (예정 %s)" % [str(hp7 - float(st7.player.hp)), str(pending7)])

	# 전투 종료로도 조용히 사라지지 않는다
	var st8 := armed("eq_reprieve")
	PSkills.cast(st8, "q")
	st8.damage_player(20.0, "wolf:bite", null)
	var pending8: float = float(st8.eq_debt.amount)
	var hp8: float = float(st8.player.hp)
	st8.status = "timeout"
	PSkills.eq_on_combat_end(st8)
	ok("[9] **전투 종료로도 예정 피해가 조용히 삭제되지 않는다**",
		st8.eq_debt.is_empty() and near(hp8 - float(st8.player.hp), pending8),
		"정산 %s (예정 %s)" % [str(hp8 - float(st8.player.hp)), str(pending8)])

	# 승리가 확정된 뒤의 정산은 이미 이긴 전투를 뒤집지 않는다(체력 1 미만으로 내리지 않는다)
	var st9 := armed("eq_reprieve")
	PSkills.cast(st9, "q")
	st9.eq_debt.amount = 9999.0
	st9.status = "won"
	PSkills.eq_on_combat_end(st9)
	ok("[9] 승리 확정 뒤의 정산은 체력을 **1 미만으로 내리지 않는다**(이긴 전투를 사후 정산으로 뒤집지 않는다)",
		float(st9.player.hp) >= 1.0 and not bool(st9.player.dead), str(st9.player.hp))

# ---------- 7절 연계 자격 ----------
func sec7_eligibility() -> void:
	var causes: Array = ["eq_slash", "eq_meteor_core", "eq_meteor_wave", "eq_riposte", "eq_retrace", "eq_icetomb"]
	var known := true
	for c in causes:
		if not PSupport.known_cause(String(c)):
			known = false
	ok("7절: 여섯 경로 이름이 **자격표의 어휘**로 등록되어 있다(모르는 이름으로 조용히 지나가지 않는다)", known)

	var effects: Array = ["frost_shatter", "shock_bonus", "shock_discharge", "crow_mark", "plague_host_burst"]
	var all_denied := true
	var opened := ""
	for eff in effects:
		for c in causes:
			if PSupport.eligible(String(eff), String(c)):
				all_denied = false
				opened += "%s←%s " % [String(eff), String(c)]
	ok("7절: 여섯 경로 어느 것도 **파쇄·감전 후속·방전 충전·까마귀 표적·숙주 파열**을 열지 않는다(승인 없이 연쇄를 열지 않았다)",
		all_denied, opened)

	ok("7절: **[8] 결정 관의 냉기만은 막지 않는다** — 냉기 → 빙결 → 주무기 파쇄 연계를 실제로 연다",
		PSupport.eligible("frost_stack", "eq_icetomb"))

	# 실제 전투에서도 같은 결론인가: 얼어붙은 적을 장비 기술로 때려도 파쇄가 나지 않는다
	var st := armed("eq_flashcut")
	var e := dummy(st, 120.0, 0.0)
	st.add_chill_stack(e, st.frost_need())
	var frozen: bool = st.is_frozen(e)
	PSkills.cast(st, "q")
	st.step(inp(true), STEP)
	ok("7절(실제 경로): 얼어붙은 적을 [4]로 베어도 **파쇄가 나지 않는다**(주무기만 깬다는 확정 유지)",
		frozen and st.is_frozen(e) and not bool(e.get("freeze_broke", false)))

	# 결정 관의 냉기는 실제로 빙결까지 이어진다
	var st2 := armed("eq_icetomb")
	var e2 := dummy(st2, 60.0, 0.0)
	var need: int = st2.frost_need()
	var rounds: int = int(ceil(float(need) / float(tune("eq_icetomb").get("chill", 2))))
	for i in rounds:
		st2.player.special_cd = 0.0
		PSkills.cast(st2, "q")
		st2.step(inp(true), STEP)
	ok("7절(실제 경로): [8]의 냉기는 **실제로 빙결까지 이어진다**(요구 %d중첩)" % need,
		st2.is_frozen(e2), "중첩 %d" % int(e2.get("chill_n", 0)))

	# 추가 타격이 자기 자신을 재귀 호출하지 않는다: 적 하나에 정확히 한 번만 피해가 들어간다
	var st3 := armed("eq_meteor")
	var e3 := dummy(st3, float(tune("eq_meteor").range), 0.0)
	var hp3: float = float(e3.hp)
	PSkills.cast(st3, "q")
	st3.step(inp(true), STEP)
	run_steps(st3, float(tune("eq_meteor").leap) + 4.0 * STEP)
	ok("검증: 추가 타격이 **자기 자신을 재귀 호출하지 않는다**(중심 강타 정확히 1회분)",
		near(hp3 - float(e3.hp), float((PCatalog.skills().eq_meteor.damage as Array)[0])),
		str(hp3 - float(e3.hp)))

# ---------- 취소·화면 전환·장비 해제 뒤에 상태가 남지 않는다 ----------
func sec8_cleanup() -> void:
	# 화면 전환(전환 구간)에 들어가면 충전·무적·기록·방어가 남지 않는다
	for sid in ["eq_flashcut", "eq_meteor", "eq_icetomb"]:
		var st := armed(String(sid))
		PSkills.cast(st, "q")
		run_steps(st, 0.1)
		PSkills.eq_on_transition(st)
		ok("검증 9) 화면 전환 뒤 %s의 **충전·무적 상태가 남지 않는다**" % String(sid),
			st.eq_act.is_empty() and not PSkills.eq_invuln(st) and st.damage_player(5.0, "wolf:bite", null))

	var st_tr := armed("eq_retrace")
	PSkills.cast(st_tr, "q")
	run_steps(st_tr, 0.2, inp(false, false, false, 1.0, 0.0))
	PSkills.eq_on_transition(st_tr)
	ok("검증 9) 화면 전환 뒤 [7]의 **기록이 남지 않고** 재사용 시간이 걸린다",
		st_tr.eq_trail.is_empty() and float(st_tr.player.special_cd) > 0.0)

	var st_g := armed("eq_riposte")
	PSkills.cast(st_g, "q")
	PSkills.eq_on_transition(st_g)
	ok("검증 9) 화면 전환 뒤 [6]의 **방어 창이 남지 않는다**", st_g.eq_guard.is_empty())

	# 실제 step 경로(전환 구간)로도 같은 결과인가
	var st_step := armed("eq_icetomb")
	PSkills.cast(st_step, "q")
	st_step.duel_stage = "growth"
	st_step.step(inp(), STEP)
	ok("검증 9) 실제 step의 전환 구간에서도 갇힘이 풀리고 **무적이 남지 않는다**",
		st_step.in_transition() and st_step.eq_act.is_empty() and not PSkills.eq_invuln(st_step))

	# 장비를 벗으면 진행 중인 것도 끝난다
	var st_un := armed("eq_icetomb")
	PSkills.cast(st_un, "q")
	var g: Dictionary = PGrowth.new_growth("sword")
	g.skills.q = { "id": "eq_icetomb", "level": 1, "variant": null }
	st_un.rebuild(PBuild.derive(PBuild.empty_run_like(g)))
	ok("검증: **장비를 벗으면 효과가 남지 않는다**(진행 중이던 갇힘·무적이 끝난다)",
		st_un.eq_act.is_empty() and not PSkills.eq_invuln(st_un) and st_un.damage_player(5.0, "wolf:bite", null))
	ok("검증: 장비를 벗으면 그 뒤로 발동도 되지 않는다",
		not PSkills.cast(st_un, "q") and st_un.eq_act.is_empty())

	# 아무 장비 기술도 쓰지 않는 회차에서는 이 상태들이 처음부터 끝까지 비어 있다(기준 전투 보존)
	var plain := mk("slowfield", {})
	dummy(plain, 100.0, 0.0)
	run_steps(plain, 1.0, inp(true))
	ok("기준 전투 보존: 장비 기술을 쓰지 않으면 네 상태가 **전부 비어 있다**",
		plain.eq_act.is_empty() and plain.eq_trail.is_empty() and plain.eq_guard.is_empty() and plain.eq_debt.is_empty())

	# 화면: 새 기술을 그리는 갈래가 있고 **규칙이 만든 값**을 읽는가
	var f := FileAccess.open("res://scripts/game/render.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	ok("화면: 장비 기술 갈래가 있고 규칙 상태를 직접 읽는다",
		src.find("\"eq_slash\":") >= 0 and src.find("\"eq_slam\":") >= 0 and src.find("\"eq_tomb_break\":") >= 0
		and src.find("static func draw_eq_skill(") >= 0 and src.find("st.eq_act") >= 0
		and src.find("st.eq_trail") >= 0 and src.find("st.eq_guard") >= 0 and src.find("st.eq_debt") >= 0
		and src.find("draw_eq_skill(ci, st)") >= 0)

# ==================================================================
# 9. 집중이 장비 기술에도 걸린다(2026-09-10 지시 2절) — **실측** 재사용
# ==================================================================
## 사용자 지적: "자료에서 읽어 비교하는 검사만으로 실제 쿨다운까지 증명되지 않는다."
## 그래서 여기서는 전투를 실제로 굴려 **쓴 뒤 다시 쓸 수 있게 되는 시각**을 센다.
## 일반 수동 기술 6종의 같은 측정은 tests/qe_tests.gd에 있다.
##
## 함께 못박는 것
##  · Q에 두든 E에 두든 배율이 같다 · 표시 재사용(PSkills.cd_of)과 실제가 같다.
##  · 집중이 붙어도 장비 기술은 **여전히 레벨·개조가 없다**(성장 후보에 나오지 않는다).
##  · 무적·방어 지속시간은 집중과 무관하게 그대로다.
##  · 각 기술의 **재사용 시작 시점**(준비/발동/유지/종료/재입력)을 실제 상태로 확인한다.

## 집중 lv를 얹고 그 기술을 그 칸에 넣은 전장(그 기술을 주는 장비를 착용한다)
func mk_focus(sid: String, slot: String, focus_lv: int) -> CombatState:
	var row: Array = ROWS[sid]
	var g: Dictionary = PGrowth.new_growth("sword")
	g.skills.q = { "id": (sid if slot == "q" else "slowfield"), "level": 1, "variant": null }
	g.skills.e = { "id": sid, "level": 1, "variant": null } if slot == "e" else null
	g.passives = { "focus": focus_lv }
	var run: Dictionary = PBuild.empty_run_like(g)
	(run.equipment as Dictionary)[String(row[1])] = String(row[0])
	var b: Dictionary = PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "arena": "clearing",
		"waves": [], "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.face = 0.0
	st.player.attack_timer = 1.0e9
	dummy(st, 120.0, 0.0)
	dummy(st, -120.0, 40.0)
	return st

func uses_of(st: CombatState, slot: String) -> int:
	return int(st.stats.special_uses) if slot == "q" else int(st.stats.e_uses)

## 그 칸의 키를 매 단계 누르며 **사용 횟수가 두 번 오르는 사이**를 센다(선언값을 읽지 않는다)
func recast_gap(sid: String, slot: String, focus_lv: int) -> Dictionary:
	var st := mk_focus(sid, slot, focus_lv)
	var press := inp(slot == "q", slot == "e")
	var n1 := -1
	var n2 := -1
	var n := 0
	while n < int(round(40.0 / STEP)):
		var before := uses_of(st, slot)
		st.step(press, STEP)
		n += 1
		if uses_of(st, slot) > before:
			if n1 < 0:
				n1 = n
			else:
				n2 = n
				break
	return { "gap": float(n2 - n1) * STEP if n1 > 0 and n2 > 0 else -1.0,
		"decl": PSkills.cd_of(st, slot), "status": String(st.status) }

func sec9_focus() -> void:
	print("\n[9] 집중 × 장비 기술 — 실측 재사용")
	var SK := PCatalog.skills()
	var mults := [1.0, 0.9, 0.8, 0.7]
	var rows := []
	var lv_ok := true
	var qe_ok := true
	var decl_ok := true
	for sid in PSkills.EQ_IDS:
		var base: float = float(SK[String(sid)].cooldown[0])
		for lv in 4:
			var rq := recast_gap(String(sid), "q", lv)
			var re := recast_gap(String(sid), "e", lv)
			var want: float = base * float(mults[lv])
			rows.append("%s Lv%d Q %.3f E %.3f (기대 %.3f)" % [sid, lv, float(rq.gap), float(re.gap), want])
			# [7] 되짚는 궤적은 첫 입력이 아니라 **귀환 시점**에 재사용이 걸린다 → 한두 단계 늦다.
			# 그래서 허용 오차를 세 단계(0.025초)로 둔다. 재사용 시작 시점은 아래에서 따로 못박는다
			if absf(float(rq.gap) - want) > 3.0 * STEP or absf(float(re.gap) - want) > 3.0 * STEP:
				lv_ok = false
			if absf(float(rq.gap) - float(re.gap)) > 3.0 * STEP:
				qe_ok = false
			if absf(float(rq.decl) - want) > 1e-6 or absf(float(re.decl) - want) > 1e-6:
				decl_ok = false
	ok("2절 집중: 장비 기술 6종의 **실측 재사용**이 표 × (1.0/0.9/0.8/0.7)와 같다", lv_ok, " · ".join(rows))
	ok("2절 집중: **Q에 두든 E에 두든 배율이 같다** — 같은 기술·같은 레벨에서 실측이 일치한다", qe_ok)
	ok("2절 집중: **표시 재사용 시간(PSkills.cd_of)과 실제 재사용이 같다**", decl_ok)

	# 집중은 장비 기술의 '레벨업'이 아니다 — 레벨은 1 그대로이고 성장 후보에도 나오지 않는다
	var lvl_ok := true
	var cand_ok := true
	for sid2 in PSkills.EQ_IDS:
		var st2 := mk_focus(String(sid2), "q", 3)
		var sk = st2.build.skills.get("q")
		if sk == null or int(sk.level) != 1:
			lvl_ok = false
		var run2: Dictionary = PBuild.empty_run_like(st2.build.growth)
		(run2.equipment as Dictionary)[String((ROWS[String(sid2)] as Array)[1])] = String((ROWS[String(sid2)] as Array)[0])
		for c in PGrowth.candidates(run2, { "pool": "level" }):
			if String(c.id) == String(sid2):
				cand_ok = false
	ok("2절 집중을 장비 기술의 **레벨업으로 취급하지 않는다** — 레벨은 1 그대로다", lvl_ok)
	ok("2절 집중이 붙어도 장비 기술은 성장 후보(레벨·변형)에 나오지 않는다", cand_ok)

	# 무적·방어 지속시간은 집중과 무관하다
	var T_tomb := tune("eq_icetomb")
	var inv_rows := []
	var inv_ok := true
	for lv3 in [0, 3]:
		var st3 := mk_focus("eq_icetomb", "q", lv3)
		PSkills.cast(st3, "q")
		var n3 := 0
		while n3 < int(round(4.0 / STEP)) and PSkills.eq_invuln(st3):
			st3.step(inp(), STEP)
			n3 += 1
		inv_rows.append("집중 Lv%d 무적 %.3f초" % [lv3, float(n3) * STEP])
		if absf(float(n3) * STEP - float(T_tomb.get("max", 1.2))) > 2.0 * STEP:
			inv_ok = false
	var guard_rows := []
	for lv4 in [0, 3]:
		var st4 := mk_focus("eq_riposte", "q", lv4)
		PSkills.cast(st4, "q")
		var n4 := 0
		while n4 < int(round(4.0 / STEP)) and not st4.eq_guard.is_empty():
			st4.step(inp(), STEP)
			n4 += 1
		guard_rows.append("집중 Lv%d 방어 창 %.3f초" % [lv4, float(n4) * STEP])
		if absf(float(n4) * STEP - float(tune("eq_riposte").get("guard", 0.45))) > 2.0 * STEP:
			inv_ok = false
	ok("2절 집중은 **무적·방어 지속시간을 늘리지 않는다**([8] 갇힘 · [6] 방어 창)",
		inv_ok, " · ".join(inv_rows) + " · " + " · ".join(guard_rows))

	# 재사용 시작 시점(준비/발동/유지/종료/재입력)을 실제 상태로 확인한다
	print("\n[9-2] 각 장비 기술의 재사용 시작 시점")
	var when_rows := []
	var when_ok := true
	for sid3 in PSkills.EQ_IDS:
		var st5 := mk_focus(String(sid3), "q", 0)
		PSkills.cast(st5, "q")
		var left := PSkills.cd_left(st5, "q")
		var phase := String(st5.eq_act.get("phase", "")) if not st5.eq_act.is_empty() else ""
		var want_now: bool = String(sid3) != "eq_retrace" # [7]만 첫 입력에 걸지 않는다
		when_rows.append("%s 첫 입력 직후 남은 재사용 %.2f (단계 '%s')" % [sid3, left, phase])
		if (left > 0.0) != want_now:
			when_ok = false
	ok("2절 재사용 시작 시점: [4][5]는 **준비(충전) 시작**, [6][8][9]는 **발동 순간**에 걸리고, [7]만 첫 입력에 걸지 않는다",
		when_ok, " · ".join(when_rows))

	# [4][5] 충전을 Space로 취소하면 재사용을 돌려받는다(집중이 붙어도 같다)
	var refund_ok := true
	for sid4 in ["eq_flashcut", "eq_meteor"]:
		var st6 := mk_focus(String(sid4), "q", 3)
		PSkills.cast(st6, "q")
		st6.step(inp(false, false, true), STEP)
		if PSkills.cd_left(st6, "q") > 0.0 or not st6.eq_act.is_empty():
			refund_ok = false
	ok("2절 [4][5] 충전 중 Space 취소는 재사용을 돌려준다(집중 Lv3에서도 같다)", refund_ok)

	# [7] 되짚는 궤적: 첫 입력에는 안 걸리고 **귀환** 또는 **기록 만료**에 걸린다
	var st7 := mk_focus("eq_retrace", "q", 3)
	PSkills.cast(st7, "q")
	var before7 := PSkills.cd_left(st7, "q")
	st7.step(inp(true), STEP)   # 같은 칸 재입력 = 귀환
	var after7 := PSkills.cd_left(st7, "q")
	var st8 := mk_focus("eq_retrace", "q", 3)
	PSkills.cast(st8, "q")
	var n8 := 0
	while n8 < int(round(6.0 / STEP)) and st8.eq_trail.is_empty() == false:
		st8.step(inp(), STEP)
		n8 += 1
	ok("2절 [7] 되짚는 궤적: 첫 입력에는 재사용이 걸리지 않고 **재입력(귀환)** 또는 **기록 만료**에 걸린다 — 집중 배율은 그때 적용된다",
		is_equal_approx(before7, 0.0) and absf(after7 - 12.0 * 0.7) <= 2.0 * STEP
			and absf(PSkills.cd_left(st8, "q") - 12.0 * 0.7) <= 2.0 * STEP,
		"귀환 %.3f · 만료(%.2f초) %.3f · 기대 %.3f" % [after7, float(n8) * STEP, PSkills.cd_left(st8, "q"), 12.0 * 0.7])

	# 장비를 벗었다 다시 껴도(전투 중 빌드 재계산) 남은 재사용이 초기화되지 않는다
	var keep_rows := []
	var keep_ok := true
	for sid5 in ["eq_flashcut", "eq_icetomb", "eq_reprieve"]:
		var st9 := mk_focus(String(sid5), "q", 0)
		PSkills.cast(st9, "q")
		for i in 120:
			st9.step(inp(), STEP)
		var left0 := PSkills.cd_left(st9, "q")
		var row5: Array = ROWS[String(sid5)]
		var g9: Dictionary = PGrowth.new_growth("sword")
		g9.skills.q = { "id": String(sid5), "level": 1, "variant": null }
		g9.passives = { "focus": 3 }
		var run9: Dictionary = PBuild.empty_run_like(g9)
		(run9.equipment as Dictionary)[String(row5[1])] = String(row5[0])
		st9.rebuild(PBuild.derive(run9))
		var left1 := PSkills.cd_left(st9, "q")
		keep_rows.append("%s %.3f → %.3f" % [sid5, left0, left1])
		if not is_equal_approx(left0, left1) or left1 <= 0.0:
			keep_ok = false
	ok("2절 장착·해제·빌드 재계산으로 **재사용 시간이 초기화되지 않는다**", keep_ok, " · ".join(keep_rows))

	# [8] 결정 관 + 집중: 무적을 빈틈 없이 반복할 수 있는가(다른 재사용 감소와 겹칠 때까지 본다)
	print("\n[9-3] 결정 관 + 집중: 무적을 빈틈 없이 반복할 수 있는가")
	var gap_rows := []
	var gapless := false
	var combos := [[0, 1.0], [3, 1.0], [3, 0.85], [3, 0.85 * 0.85]]
	for combo in combos:
		var r := tomb_cycle(int(combo[0]), float(combo[1]))
		gap_rows.append("집중 Lv%d × %.4f → 재사용 %.2f · 무적 비율 %.1f%% · 최소 빈틈 %.2f초" % [
			int(combo[0]), float(combo[1]), float(r.cd), float(r.invuln_frac) * 100.0, float(r.gap_min)])
		if float(r.gap_min) <= 0.0 or float(r.invuln_frac) >= 0.5:
			gapless = true
	ok("2절 [8] 결정 관은 집중 Lv3에 다른 재사용 감소(시간의 샘·박자)를 다 겹쳐도 **빈틈 없이 반복되지 않는다**",
		not gapless, " · ".join(gap_rows) + " · 한 번의 무적 %.2f초" % float(T_tomb.get("max", 1.2)))

## 결정 관을 반복해서 쓰는 30초 동안 무적인 시간의 비율과 무적 사이의 최소 빈틈.
## cd_mult는 집중 밖의 다른 재사용 감소(시간의 샘 0.85 · 보스 보상 박자 0.85)를 겹쳐 보기 위한 자리다
func tomb_cycle(focus_lv: int, cd_mult: float) -> Dictionary:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.skills.q = { "id": "eq_icetomb", "level": 1, "variant": null }
	g.passives = { "focus": focus_lv }
	var run: Dictionary = PBuild.empty_run_like(g)
	(run.equipment as Dictionary)["shield"] = "crystal_coffin"
	if not is_equal_approx(cd_mult, 1.0):
		run["buffs"] = { "skillCd": cd_mult }
	var b: Dictionary = PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "arena": "clearing",
		"waves": [], "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.attack_timer = 1.0e9
	dummy(st, 200.0, 0.0)
	var total := int(round(30.0 / STEP))
	var inv_n := 0
	var uses := 0
	var gap_now := 0
	var gap_min := 999999
	for i in total:
		# 결정 관은 '누르면 갇히고 최대 시간까지 유지'다. 준비되는 즉시 한 번 누르고 그 뒤에는 손을 뗀다
		var ready: bool = PSkills.cd_left(st, "q") <= 0.0 and st.eq_act.is_empty()
		var before := int(st.stats.special_uses)
		st.step(inp(ready), STEP)
		if int(st.stats.special_uses) > before:
			uses += 1
		if PSkills.eq_invuln(st):
			inv_n += 1
			if gap_now > 0:
				gap_min = mini(gap_min, gap_now)
			gap_now = 0
		elif uses > 0:
			gap_now += 1
	return { "invuln_frac": float(inv_n) / float(total), "uses": uses,
		"gap_min": float(gap_min) * STEP if gap_min < 999999 else -1.0,
		"cd": float(b.special_cd) }
