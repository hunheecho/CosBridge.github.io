extends SceneTree
## 일반 수동 기술(Q/E)의 **고유 피해 출처**와 그 연계 자격 검사(화면 없음).
## 실행: python tools/run_suites.py --suites skill_cause_tests --jobs 1
##      (직접: godot --headless --path prophecy_godot -s tests/skill_cause_tests.gd)
##
## 왜 생겼는가 — `PSkills.hit`이 경로 이름(cause)을 적지 않아, 주인(weapon_id)이 없는
## 수동 기술의 피해가 `PSupport.cause_of`의 마지막 줄(`main_extra if indirect else main_direct`)에서
## **전부 main_extra로 떨어졌다.** main_extra는 자격표에서 "주무기가 낸 타격"을 뜻하므로
## 수동 기술이 **파쇄를 터뜨릴 자격을 잘못 얻고 있었다**(실측: 낙뢰로 얼어붙은 적의 빙결이 풀렸다).
##
## 무엇을 못박는가(2026-09-10 사용자 확정)
##  1. 일반 수동 기술은 **기술별 고유 경로 이름**을 적는다(skill_*). 장비 기술 eq_* 와 **합치지 않는다.**
##  2. 일반 수동 기술: 흡혈 **불허** · 파쇄 **불허**(기존 합의 범위로 바로잡음) · 숙주 파열 **불허 유지**.
##  3. 감전 후속·까마귀 표적은 **미결정**이다 — allow에 넣지 않았고 deny에도 넣지 않았다.
##     자격표 기본 규칙(allow 목록이 비어 있지 않은데 이름이 없으면 불허)에 따라 **결과적으로 불허**다.
##  4. 장비 기술 넷의 파쇄·숙주 파열 자격은 **그대로**이고 흡혈은 여전히 불허다.
##  5. 주무기와 승인된 추가 공격(기본 공격·개조 추가 타격·메아리/일제·공성 착탄점 충격)은 **흡혈이 나온다.**
##
## **cause 문자열을 손으로 넣는 검사로 끝내지 않는다** — 아래 2·3·4·5·6절은 기술을 실제로 발동시키고
## 체력·회복·지표를 값으로 잰다. 대조군을 같은 전장에서 함께 잡아 "장치가 꺼져서 0"과 구분한다.
##
## 수치는 전부 시험값이다(data/growth.json · data/supports.json). 사람이 승인한 밸런스가 아니다.

const STEP := 1.0 / 120.0

## 일반 수동 기술의 고유 경로 이름(정본은 PSkills.SKILL_CAUSE와 data/supports.json eligibility.causes)
const SKILL_CAUSES := ["skill_strike", "skill_gust", "skill_bladestorm", "skill_gravity", "skill_ward", "skill_other"]
## 실제로 피해를 주는 수동 기술(감속장은 피해 경로가 없고, 수호 결계는 개조 '맥동'에서만 때린다)
const ATTACK_SKILLS := ["strike", "gust", "bladestorm", "gravity"]
## 장비 기술 여섯의 경로 이름(자격이 열린 다섯 + 닫힌 하나)
const EQ_OPEN := ["eq_slash", "eq_meteor_core", "eq_meteor_wave", "eq_riposte", "eq_retrace"]
const EQ_SHUT := ["eq_icetomb"]
const EQ_SKILL_OF := {
	"eq_slash": "eq_flashcut", "eq_meteor_core": "eq_meteor", "eq_meteor_wave": "eq_meteor",
	"eq_riposte": "eq_riposte", "eq_retrace": "eq_retrace", "eq_icetomb": "eq_icetomb",
}

var results := []
## 전후 차이표에 찍을 실측값(이름 → 값). 규칙에는 영향이 없다
var measured := {}

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func note(key: String, value: String) -> void:
	measured[key] = value

# ---------- 시험실 ----------
## 원하는 기술을 Q에 넣은 빈 전장. 자동기술은 기본으로 꺼 둔다(수동 기술의 피해만 남기려고).
## supports = [[보조 id, 레벨, [개조...]], ...] · passives = { 패시브 id: 레벨 }
func lab(q_id: String, variant: String = "", weapon: String = "sword", auto: bool = false,
		supports: Array = [], passives: Dictionary = {}, commons: Dictionary = {},
		rewards: Array = [], equip: Dictionary = {}, main_mods: Array = []) -> CombatState:
	var g: Dictionary = PGrowth.new_growth(weapon)
	g.weapons = [{ "id": weapon, "level": 3, "mods": main_mods.duplicate() }]
	g.skills.q = { "id": q_id, "level": 1, "variant": (variant if variant != "" else null) } if q_id != "" else null
	for r in supports:
		(g.weapons as Array).append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	for k in passives:
		(g.passives as Dictionary)[String(k)] = int(passives[k])
	for k2 in commons:
		(g.commons as Dictionary)[String(k2)] = int(commons[k2])
	g.bossRewards = rewards.duplicate()
	var run: Dictionary = PBuild.empty_run_like(g)
	for slot in equip:
		(run.equipment as Dictionary)[String(slot)] = String(equip[slot])
	var b: Dictionary = PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "arena": "clearing",
		"waves": [], "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.face = 0.0
	# 회복이 최대 체력에 막혀 0이 되면 '자격이 없어 0'과 구분되지 않는다. 체력을 크게 비워 둔다
	st.player.hp_max = 1.0e7
	st.player.hp = 1.0
	if not auto:
		st.player.attack_timer = 1.0e9 # 자동기술 정지 훅(PWeapons.update가 읽는다)
	return st

## 움직이지도 때리지도 않는 표적(기하가 흔들리면 무엇을 쟀는지 알 수 없다)
func dummy(st: CombatState, dx: float, dy: float = 0.0, hp: float = 1000000.0, type_id: String = "wolf") -> Dictionary:
	var e: Dictionary = st.spawn_enemy(type_id, float(st.player.x) + dx, float(st.player.y) + dy)
	e.hp = hp
	e.hp_max = hp
	e.speed = 0.0
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

func shatters(st: CombatState) -> float:
	return PSupport.metered(st, "frost", "shatters")

func healed(st: CombatState) -> float:
	return float(st.stats.get("lifesteal", 0.0))

func steal_base(st: CombatState) -> float:
	return float(st.stats.get("lifesteal_base", 0.0))

func marks(st: CombatState) -> int:
	return int(((st.support as Dictionary).get("crow", {}) as Dictionary).get("marks", 0))

func shock_procs(st: CombatState) -> float:
	return PSupport.metered(st, "orb", "shock_procs")

func infected(e: Dictionary) -> bool:
	return not (e.get("plague", {}) as Dictionary).is_empty()

## 그 적을 그 자리에서 얼린다. 실제로 얼었으면 true
func freeze(st: CombatState, e: Dictionary) -> bool:
	st.add_chill_stack(e, st.frost_need())
	return st.is_frozen(e)

## 전투 규칙 전체를 굴리되 표적을 제자리에 묶어 둔다(pins = [[적, x, y], ...])
func run_pinned(st: CombatState, seconds: float, pins: Array) -> void:
	for i in int(round(seconds / STEP)):
		st.step({}, STEP)
		for row in pins:
			var e: Dictionary = row[0]
			e.x = float(row[1])
			e.y = float(row[2])

## **기술을 실제로 발동시키고** 그 기술의 피해가 처음 들어간 순간의 상태를 잡는다.
## 돌려주는 것: dmg 깎인 체력 · frozen 그 순간 빙결이 남아 있었는가 · shatters 파쇄 누계 · fired 발동했는가
func cast_and_hurt(st: CombatState, e: Dictionary, pins: Array, max_sec: float = 1.6) -> Dictionary:
	var hp0: float = float(e.hp)
	var fired: bool = PSkills.cast(st, "q")
	var frozen := st.is_frozen(e)
	var shat := shatters(st)
	var hit := false
	for i in int(round(max_sec / STEP)):
		st.step({}, STEP)
		for row in pins:
			var pe: Dictionary = row[0]
			pe.x = float(row[1])
			pe.y = float(row[2])
		if float(e.hp) < hp0:
			frozen = st.is_frozen(e)
			shat = shatters(st)
			hit = true
			break
	return { "dmg": hp0 - float(e.hp), "frozen": frozen, "shatters": shat, "fired": fired, "hit": hit }

## 주무기 기본 타격 한 대(대조군에서 쓴다 — 게임이 실제로 만드는 출처 모양 그대로)
func main_blow(st: CombatState, e: Dictionary, dmg: float = 30.0) -> void:
	st.damage_enemy(e, dmg, { "src": { "weapon_id": "sword", "direct": true } })

## 장비 기술이 실제로 쓰는 피해 함수 그대로
func eq_blow(st: CombatState, e: Dictionary, cause: String, dmg: float = 5.0) -> void:
	PSkills.eq_hit(st, e, dmg, String(EQ_SKILL_OF[cause]), cause, {})

func _init() -> void:
	sec0_vocab()
	sec1_attack_skills()
	sec2_quiet_skills()
	sec3_main_weapon()
	sec4_equip_skills()
	sec5_undecided()
	sec6_host_burst()
	sec7_table()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ==================================================================
# 0. 어휘·자격표 계약
# ==================================================================
func sec0_vocab() -> void:
	var EF: Dictionary = (PCatalog.eligibility().get("effects", {}) as Dictionary)
	var CA: Dictionary = (PCatalog.eligibility().get("causes", {}) as Dictionary)

	# (가) 새 이름이 자격표 어휘로 등록돼 있다 — 모르는 이름으로 조용히 지나가지 않는다
	var known := true
	var missing := []
	for c in SKILL_CAUSES:
		if not PSupport.known_cause(String(c)):
			known = false
			missing.append(String(c))
	ok("0-1: 일반 수동 기술의 경로 이름이 **자격표 어휘로 등록**돼 있다", known,
		("빠진 이름 " + str(missing)) if not known else str(SKILL_CAUSES))

	# (나) **장비 기술과 합치지 않았다** — 이름이 겹치지 않고 묶음 이름도 만들지 않았다
	var merged := false
	for c in SKILL_CAUSES:
		if String(c).begins_with("eq_"):
			merged = true
	for c2 in (EQ_OPEN + EQ_SHUT):
		if SKILL_CAUSES.has(String(c2)):
			merged = true
	ok("0-2: **장비 기술 넷과 같은 출처로 합치지 않았다**(이름이 겹치지 않는다)", not merged)
	ok("0-3: **묶음 경로 이름을 만들지 않았다**(기술별 출처를 남긴다)",
		not PSupport.known_cause("skill_direct") and not PSupport.known_cause("manual_skill")
		and not PSupport.known_cause("skill") and not PSupport.known_cause("equip_skill_direct"))

	# (다) 규칙 코드가 그 이름을 어디서 가져오는가 — 정본은 PSkills.SKILL_CAUSE 한 곳이다
	var map_ok := true
	var map_rows := []
	for sid in (ATTACK_SKILLS + ["ward"]):
		var c3: String = PSkills.skill_cause(String(sid))
		map_rows.append("%s→%s" % [String(sid), c3])
		if not SKILL_CAUSES.has(c3) or c3 == "skill_other":
			map_ok = false
	ok("0-4: 기술 id → 경로 이름 대응이 **한 곳(PSkills.SKILL_CAUSE)**에 있고 기술마다 다르다",
		map_ok and PSkills.SKILL_CAUSE.size() == 5, " · ".join(map_rows))
	ok("0-5: 표에 없는 기술 id는 **안전망 이름(skill_other)**으로 떨어진다(main_extra로 새지 않는다)",
		PSkills.skill_cause("nonexistent_skill_id") == "skill_other")

	# (라) 파쇄·숙주 파열은 **deny에 명시**했다(우연히 통과하지 않는다)
	var FS: Dictionary = EF.get("frost_shatter", {})
	var PH: Dictionary = EF.get("plague_host_burst", {})
	var fs_deny: Array = FS.get("deny", [])
	var ph_deny: Array = PH.get("deny", [])
	var listed := true
	for c4 in SKILL_CAUSES:
		if not fs_deny.has(String(c4)) or not ph_deny.has(String(c4)):
			listed = false
		if (FS.get("allow", []) as Array).has(String(c4)) or (PH.get("allow", []) as Array).has(String(c4)):
			listed = false
	ok("0-6: 파쇄·숙주 파열 자격표의 **deny에 여섯 이름이 명시**돼 있다(allow에는 없다)", listed)

	# (마) 흡혈은 denied에 명시했다
	var L: Dictionary = PCatalog.growth().get("LIFESTEAL", {})
	var ls_deny: Array = L.get("denied", [])
	var ls_ok := true
	for c5 in SKILL_CAUSES:
		if not ls_deny.has(String(c5)) or (L.get("eligible", []) as Array).has(String(c5)):
			ls_ok = false
	ok("0-7: 흡혈 자격표의 **denied에 여섯 이름이 명시**돼 있다", ls_ok)

	# (바) **미결정**: 감전 후속·까마귀 표적은 allow에도 deny에도 넣지 않았다.
	#      자격표 기본 규칙(allow가 비어 있지 않은데 이름이 없으면 불허)으로 결과는 불허다
	var SB: Dictionary = EF.get("shock_bonus", {})
	var CM: Dictionary = EF.get("crow_mark", {})
	# 2026-09-10 사용자 확정: 감전 후속·까마귀 표적 **둘 다 일반 수동 기술은 제외**.
	# 그전에는 합의 문구에 근거가 없어 allow·deny 어디에도 안 적고 미결정으로 두었다(그때도 결과는 불허).
	# 확정이 온 뒤로는 **deny 에 명시**해야 한다 — 결과가 같아도 '우연히 막혀 있다'와 '막기로 정했다'는
	# 다른 사실이고, 나중에 분류가 바뀌어도 이 줄이 있으면 조용히 열리지 않는다.
	var denied_named := true
	var not_allowed := true
	var eff_shut := true
	for c6 in SKILL_CAUSES:
		for T in [SB, CM]:
			var d: Dictionary = T
			if not (d.get("deny", []) as Array).has(String(c6)):
				denied_named = false
			if (d.get("allow", []) as Array).has(String(c6)):
				not_allowed = false
		if PSupport.eligible("shock_bonus", String(c6)) or PSupport.eligible("crow_mark", String(c6)):
			eff_shut = false
	ok("0-8: **확정** — 감전 후속·까마귀 표적의 deny 에 수동 기술 경로가 전부 명시돼 있다", denied_named,
		"감전 후속 deny %s" % str(SB.get("deny", [])))
	ok("0-8b: allow 에는 넣지 않았다(허용으로 뒤집히지 않는다)", not_allowed)
	ok("0-9: 실제 자격 조회도 **불허**다", eff_shut,
		"감전 후속 allow %s · 까마귀 allow %s" % [str(SB.get("allow", [])), str(CM.get("allow", []))])
	var why_sb := String(SB.get("why", ""))
	var why_cm := String(CM.get("why", ""))
	ok("0-10: 두 항목의 why 에 **제외 확정**이 적혀 있다(2026-09-10 사용자 확정)",
		why_sb.find("제외한다") >= 0 and why_cm.find("제외한다") >= 0)

	# (사) 자격표 조회 결과 한 줄 요약(값으로 남긴다)
	var rows := []
	for c7 in SKILL_CAUSES:
		rows.append("%s 파쇄%s·숙주%s·흡혈%s·감전%s·까마귀%s" % [String(c7),
			str(PSupport.eligible("frost_shatter", String(c7))),
			str(PSupport.eligible("plague_host_burst", String(c7))),
			str(PBuild.lifesteal_eligible(String(c7))),
			str(PSupport.eligible("shock_bonus", String(c7))),
			str(PSupport.eligible("crow_mark", String(c7)))])
	var all_shut := true
	for c8 in SKILL_CAUSES:
		if PSupport.eligible("frost_shatter", String(c8)) or PSupport.eligible("plague_host_burst", String(c8)) \
				or PBuild.lifesteal_eligible(String(c8)) or PSupport.eligible("shock_bonus", String(c8)) \
				or PSupport.eligible("crow_mark", String(c8)):
			all_shut = false
	ok("0-11: 다섯 연계 전부 **닫혀 있다**(자격표 조회)", all_shut, " · ".join(rows))
	ok("0-12: 어휘 설명(causes)에 새 이름의 뜻이 적혀 있다",
		String(CA.get("skill_strike", "")) != "" and String(CA.get("skill_other", "")) != "")

	# (아) 자격표가 아는 어휘로만 판단이 이뤄지는가 — 어휘 밖 이름은 cause_of가 되묻는다
	ok("0-13: 새 이름은 **어휘 안**이라 되묻기(known_cause 보정)에 걸리지 않는다",
		PSupport.known_cause(PSkills.skill_cause("strike")))

# ==================================================================
# 1. 공격 수동 기술 — 실제로 발동시켜 잰다
# ==================================================================
## 얼어붙은 적에게 실제로 발동 → 체력이 **실제로 줄고** · 흡혈 0 · 파쇄 없음(빙결 유지)
## 대조군: 같은 전장에서 주무기 직접 타격 한 대 → 파쇄가 나고 흡혈도 나온다
func sec1_attack_skills() -> void:
	var rows := []
	var all_ok := true
	for sid in ATTACK_SKILLS:
		var st := lab(String(sid), "", "sword", false, [], { "lifesteal": 3 })
		var e := dummy(st, 90.0, 0.0)
		var froze: bool = freeze(st, e)
		var r := cast_and_hurt(st, e, [[e, float(e.x), float(e.y)]])
		var got := healed(st)
		rows.append("%s 피해 %.1f·파쇄 %.0f·빙결 %s·흡혈 %.4f"
			% [String(sid), float(r.dmg), float(r.shatters), str(r.frozen), got])
		if not (froze and bool(r.hit) and float(r.dmg) > 0.0 and is_zero_approx(float(r.shatters))
				and bool(r.frozen) and is_zero_approx(got)):
			all_ok = false
	ok("1-1: **공격 수동 기술 4종을 실제로 발동** — 체력은 줄고 · 파쇄 0 · 빙결 유지 · 흡혈 0",
		all_ok, " · ".join(rows))
	note("공격 수동 기술 4종(낙뢰·돌풍·중력핵·칼날 폭풍)", " · ".join(rows))

	# 대조군: 같은 전장·같은 얼어붙은 적을 주무기가 때리면 파쇄와 흡혈이 **실제로 난다**
	var stc := lab("strike", "", "sword", false, [], { "lifesteal": 3 })
	var ec := dummy(stc, 90.0, 0.0)
	var froze_c: bool = freeze(stc, ec)
	var r_c := cast_and_hurt(stc, ec, [[ec, float(ec.x), float(ec.y)]])
	var after_skill: float = healed(stc)
	var stc2 := lab("strike", "", "sword", false, [], { "lifesteal": 3 })
	var ec2 := dummy(stc2, 90.0, 0.0)
	var froze_c2: bool = freeze(stc2, ec2)
	main_blow(stc2, ec2, 30.0)
	ok("1-2: **대조군** — 같은 전장의 같은 얼어붙은 적을 주무기가 때리면 파쇄 1회·흡혈 > 0",
		froze_c and froze_c2 and is_zero_approx(float(r_c.shatters)) and is_zero_approx(after_skill)
		and is_equal_approx(shatters(stc2), 1.0) and healed(stc2) > 0.0 and not stc2.is_frozen(ec2),
		"수동 기술: 파쇄 %.0f·흡혈 %.4f  →  주무기: 파쇄 %.0f·흡혈 %.4f"
			% [float(r_c.shatters), after_skill, shatters(stc2), healed(stc2)])
	note("대조군(주무기 직접 타격 1대)", "파쇄 %.0f · 흡혈 %.4f" % [shatters(stc2), healed(stc2)])

	# 수호 결계 '맥동' 개조의 피해도 같은 취급이다(비공격 기술의 유일한 피해 경로)
	var stw := lab("ward", "pulse", "sword", false, [], { "lifesteal": 3 })
	var ew := dummy(stw, 70.0, 0.0)
	var froze_w: bool = freeze(stw, ew)
	var rw := cast_and_hurt(stw, ew, [[ew, float(ew.x), float(ew.y)]], 2.0)
	ok("1-3: 수호 결계 개조 '맥동'의 피해도 **파쇄 0 · 흡혈 0**(피해는 실제로 들어간다)",
		froze_w and bool(rw.hit) and float(rw.dmg) > 0.0 and is_zero_approx(float(rw.shatters))
		and bool(rw.frozen) and is_zero_approx(healed(stw)),
		"피해 %.1f · 파쇄 %.0f · 빙결 %s · 흡혈 %.4f" % [float(rw.dmg), float(rw.shatters), str(rw.frozen), healed(stw)])

	# 얼지 않은 적에게 써도 결론은 같다(빙결이 없어서 0인 것이 아니다)
	var stn := lab("gust", "", "sword", false, [], { "lifesteal": 3 })
	var en := dummy(stn, 90.0, 0.0)
	var rn := cast_and_hurt(stn, en, [[en, float(en.x), float(en.y)]])
	ok("1-4: 얼지 않은 적에게도 피해는 들어가고 흡혈은 0이다",
		bool(rn.hit) and float(rn.dmg) > 0.0 and is_zero_approx(healed(stn)) and is_zero_approx(steal_base(stn)),
		"피해 %.1f · 흡혈 %.4f · 자격 기준값 %.1f" % [float(rn.dmg), healed(stn), steal_base(stn)])

	# 실제 발동 경로가 그 이름을 적는가 — 원인별 집계(metrics.cause_dmg)로 확인한다.
	# 고치기 전에는 이 칸이 "zone"이었다(이름 없는 파생 피해). 자격 판정에서는 main_extra로 읽혔다
	var stm := lab("strike", "", "sword", false, [], {})
	var em := dummy(stm, 90.0, 0.0)
	var rm := cast_and_hurt(stm, em, [[em, float(em.x), float(em.y)]])
	var cd: Dictionary = stm.metrics.cause_dmg
	ok("1-5: 실제 발동한 낙뢰의 피해가 **skill_strike 칸에 쌓인다**(이름 없는 zone 칸이 아니다)",
		bool(rm.hit) and float(cd.get("skill_strike", 0.0)) > 0.0
		and is_zero_approx(float(cd.get("zone", 0.0))) and is_zero_approx(float(cd.get("main_extra", 0.0))),
		"skill_strike %.1f · zone %.1f · main_extra %.1f · 전체 %s" % [float(cd.get("skill_strike", 0.0)),
			float(cd.get("zone", 0.0)), float(cd.get("main_extra", 0.0)), str(cd.keys())])

	# 자격 판정이 실제로 쓰는 경로 이름(CombatState.frost_cause_of)도 같은 이름인가 —
	# 원인별 집계와 자격 판정이 서로 다른 이름을 쓰면 표를 읽어도 무슨 일이 나는지 알 수 없다
	var probe_opt := { "cause": PSkills.skill_cause("strike"), "src": { "skill": true, "direct": false, "skill_id": "strike" } }
	ok("1-6: 자격 판정 경로(frost_cause_of)도 **같은 이름**을 돌려준다",
		stm.frost_cause_of(probe_opt) == "skill_strike", stm.frost_cause_of(probe_opt))

# ==================================================================
# 2. 비공격 수동 기술 — 고유 효과는 정상 발생, 흡혈 없음
# ==================================================================
func sec2_quiet_skills() -> void:
	# 감속장: 장판이 실제로 생기고 그 안의 적이 실제로 느려진다
	var st := lab("slowfield", "", "sword", false, [], { "lifesteal": 3 })
	var e := dummy(st, 60.0, 0.0)
	e.speed = 60.0
	var mult_before: float = st.enemy_speed_mult(e)
	var fired: bool = PSkills.cast(st, "q")
	var field_on: bool = not st.field.is_empty()
	var mult_after: float = st.enemy_speed_mult(e)
	run_pinned(st, 0.3, [[e, float(e.x), float(e.y)]])
	ok("2-1: **감속장을 실제로 발동** — 장판이 생기고 안의 적이 실제로 느려진다 · 흡혈 0",
		fired and field_on and mult_after < mult_before and is_zero_approx(healed(st))
		and int(st.stats.get("field_uses", 0)) >= 1,
		"속도 배율 %.2f → %.2f · 사용 %d회 · 흡혈 %.4f"
			% [mult_before, mult_after, int(st.stats.get("field_uses", 0)), healed(st)])
	note("감속장(비공격)", "속도 배율 %.2f → %.2f · 흡혈 %.4f" % [mult_before, mult_after, healed(st)])

	# 수호 결계: 보호막이 실제로 붙는다
	var st2 := lab("ward", "", "sword", false, [], { "lifesteal": 3 })
	dummy(st2, 90.0, 0.0)
	var sh0: float = float(st2.player.shield)
	var fired2: bool = PSkills.cast(st2, "q")
	var sh1: float = float(st2.player.shield)
	run_pinned(st2, 0.3, [])
	ok("2-2: **수호 결계를 실제로 발동** — 보호막이 실제로 붙는다 · 흡혈 0",
		fired2 and sh1 > sh0 and is_zero_approx(healed(st2)),
		"보호막 %.1f → %.1f · 흡혈 %.4f" % [sh0, sh1, healed(st2)])
	note("수호 결계(비공격)", "보호막 %.1f → %.1f · 흡혈 %.4f" % [sh0, sh1, healed(st2)])

	# 감속장은 피해 경로가 없으므로 경로 이름도 없다(장비 [9] 유예의 시계와 같은 기준)
	ok("2-3: 감속장은 **피해 경로 이름 자체가 없다**(피해를 주지 않는 기술에 이름을 만들지 않았다)",
		not PSupport.known_cause("skill_slowfield") and not PSkills.SKILL_CAUSE.has("slowfield"))

# ==================================================================
# 3. 주무기와 승인된 추가 공격 — 실제로 발동시켜 흡혈이 나온다
# ==================================================================
## 대조군을 같은 전장에서 함께 잡는다: 보조무기(회전 칼날·번개 구체)는 같은 판에서 0이다.
## 경로별 [적중 수, 깎은 체력, 실제 회복]을 흡혈 감사(CombatState.lifesteal_audit)에서 뽑는다.
## '자격이 없어 0'과 '아예 때리지 못해 0'을 값으로 가르기 위한 것이다. 규칙에는 영향이 없다
func path_row(st: CombatState, cause: String) -> Array:
	var row: Dictionary = (st.stats.lifesteal_paths as Dictionary).get(cause, {})
	if row.is_empty():
		return [0, 0.0, 0.0]
	return [int(row.hits), float(row.eff), float(row.healed)]

## 그 경로 안에서 **출처 이름에 key가 들어간 것들**만 합친다([적중, 깎은 체력, 회복])
func path_src(st: CombatState, cause: String, key: String) -> Array:
	var row: Dictionary = (st.stats.lifesteal_paths as Dictionary).get(cause, {})
	var out := [0, 0.0, 0.0]
	if row.is_empty():
		return out
	for s in (row.srcs as Dictionary):
		if String(s).find(key) < 0:
			continue
		var cell: Array = (row.srcs as Dictionary)[s]
		out[0] = int(out[0]) + int(cell[0])
		out[1] = float(out[1]) + float(cell[1])
		out[2] = float(out[2]) + float(cell[2])
	return out

func sec3_main_weapon() -> void:
	# 3-1. **한 전장에서 전부 켜고 실제로 굴린다** — 주무기 기본 공격 · 주무기 개조 '날아가는 검광'의
	#      추가 타격 · 공용 '메아리' · 보스 보상 '일제 공격' · 보조무기(회전 칼날·번개 구체)를 함께 둔다.
	#      대조군이 같은 전장 안에 있다: 보조는 실제로 때리지만 회복이 0이어야 한다
	CombatState.lifesteal_audit = true
	var st := lab("slowfield", "", "sword", true, [["blades", 3, []], ["orb", 3, []]],
		{ "lifesteal": 3 }, { "echo": 1 }, ["volley"], {}, ["crescent"])
	var e := dummy(st, 70.0, 0.0, 1.0e9)
	var e_far := dummy(st, 150.0, 40.0, 1.0e9)
	run_pinned(st, 8.0, [[e, float(e.x), float(e.y)], [e_far, float(e_far.x), float(e_far.y)]])
	CombatState.lifesteal_audit = false
	var md := path_row(st, "main_direct")
	var mx := path_row(st, "main_extra")
	var sd := path_row(st, "support_direct")
	ok("3-1: **주무기 기본 공격을 실제로 굴려** 흡혈이 나온다",
		int(md[0]) > 0 and float(md[2]) > 0.0,
		"main_direct 적중 %d · 깎은 체력 %.1f · 회복 %.4f" % [int(md[0]), float(md[1]), float(md[2])])
	note("주무기 기본 공격(8초 자동)", "적중 %d · 회복 %.4f" % [int(md[0]), float(md[2])])
	ok("3-2: **승인된 추가 공격**(개조 추가 타격·메아리·일제 공격이 반복한 주무기 공격)도 흡혈이 나온다",
		int(mx[0]) > 0 and float(mx[2]) > 0.0,
		"main_extra 적중 %d · 깎은 체력 %.1f · 회복 %.4f" % [int(mx[0]), float(mx[1]), float(mx[2])])
	note("추가 공격(개조·메아리·일제, 8초)", "적중 %d · 회복 %.4f" % [int(mx[0]), float(mx[2])])
	ok("3-3: **대조군(같은 전장)** — 보조무기는 실제로 때리지만 회복은 0이다",
		int(sd[0]) > 0 and is_zero_approx(float(sd[2])),
		"support_direct 적중 %d · 깎은 체력 %.1f · 회복 %.4f" % [int(sd[0]), float(sd[1]), float(sd[2])])
	note("보조무기 대조군(같은 전장 8초)", "적중 %d · 깎은 체력 %.1f · 회복 %.4f" % [int(sd[0]), float(sd[1]), float(sd[2])])

	# 3-4. **실측**: 메아리·일제 공격이 반복한 **보조무기** 공격은 main_extra 칸에 들어오지만 회복이 0인가.
	#      흡혈 자격표의 require_main_weapon이 아직 무엇을 막고 있는지를 값으로 남긴다
	var orb_cell := path_src(st, "main_extra", "orb")
	var sword_cell := path_src(st, "main_extra", "sword")
	ok("3-4: **실측** — main_extra 칸에 들어온 **보조무기(orb) 공격은 회복 0**, 같은 칸의 주무기 것은 회복 > 0",
		int(orb_cell[0]) > 0 and is_zero_approx(float(orb_cell[2]))
		and int(sword_cell[0]) > 0 and float(sword_cell[2]) > 0.0,
		"orb [적중 %d/깎은 체력 %.1f/회복 %.4f] · sword [적중 %d/깎은 체력 %.1f/회복 %.4f]"
			% [int(orb_cell[0]), float(orb_cell[1]), float(orb_cell[2]),
				int(sword_cell[0]), float(sword_cell[1]), float(sword_cell[2])])
	note("메아리가 반복한 보조무기(orb)", "적중 %d · 회복 %.4f" % [int(orb_cell[0]), float(orb_cell[2])])

	# 3-5. 그러므로 require_main_weapon 조건은 **아직 역할이 남아 있어 그대로 둔다**
	var L: Dictionary = PCatalog.growth().get("LIFESTEAL", {})
	ok("3-5: 흡혈 자격표의 **require_main_weapon(main_extra)은 그대로 남아 있다**",
		(L.get("require_main_weapon", []) as Array).has("main_extra"))
	ok("3-6: 그 조건이 실제로 막는 것이 남아 있다 — **주인이 보조무기인 main_extra**는 여전히 불허",
		not PBuild.lifesteal_eligible("main_extra", "orb") and PBuild.lifesteal_eligible("main_extra", "sword")
		and not PBuild.lifesteal_eligible("main_extra", ""),
		"orb %s · sword %s · 주인 없음 %s" % [str(PBuild.lifesteal_eligible("main_extra", "orb")),
			str(PBuild.lifesteal_eligible("main_extra", "sword")), str(PBuild.lifesteal_eligible("main_extra", ""))])

	# 3-7. 장비 '공성 망치머리'의 착탄점 추가 충격(전투망치) — 실제로 굴려 흡혈이 나오는가
	CombatState.lifesteal_audit = true
	var st3 := lab("slowfield", "", "hammer", true, [], { "lifesteal": 3 }, {}, [], { "weapon": "siege_hammerhead" })
	var e3 := dummy(st3, 60.0, 0.0, 1.0e9)
	run_pinned(st3, 8.0, [[e3, float(e3.x), float(e3.y)]])
	CombatState.lifesteal_audit = false
	var siege := path_src(st3, "main_extra", "siege")
	ok("3-7: 장비 **공성 망치머리의 착탄점 추가 충격**도 실제로 발동해 흡혈이 나온다",
		int(siege[0]) > 0 and float(siege[2]) > 0.0 and healed(st3) > 0.0,
		"착탄 충격 [적중 %d/깎은 체력 %.1f/회복 %.4f] · 전투 전체 회복 %.4f"
			% [int(siege[0]), float(siege[1]), float(siege[2]), healed(st3)])
	note("공성 망치머리 착탄 충격(8초)", "적중 %d · 회복 %.4f" % [int(siege[0]), float(siege[2])])

	# 3-8. 수동 기술이 그 전장에 섞여 있어도 main_extra 칸으로 들어오지 않는다(이번 수정의 요점)
	CombatState.lifesteal_audit = true
	var st4 := lab("strike", "", "sword", true, [], { "lifesteal": 3 })
	var e4 := dummy(st4, 80.0, 0.0, 1.0e9)
	for i in 3:
		PSkills.set_cd_left(st4, "q", 0.0)
		PSkills.cast(st4, "q")
		run_pinned(st4, 1.0, [[e4, float(e4.x), float(e4.y)]])
	CombatState.lifesteal_audit = false
	var sk_row := path_row(st4, "skill_strike")
	var mx4 := path_src(st4, "main_extra", "skill")
	ok("3-8: 같은 전장에서 쓴 **수동 기술은 skill_strike 칸으로 들어오고 회복은 0**(main_extra 칸에 섞이지 않는다)",
		int(sk_row[0]) > 0 and is_zero_approx(float(sk_row[2])) and int(mx4[0]) == 0
		and float(path_row(st4, "main_direct")[2]) > 0.0,
		"skill_strike [적중 %d/깎은 체력 %.1f/회복 %.4f] · main_extra 안의 기술 출처 %d개 · 주무기 회복 %.4f"
			% [int(sk_row[0]), float(sk_row[1]), float(sk_row[2]), int(mx4[0]), float(path_row(st4, "main_direct")[2])])
	note("수동 기술(자동 공격과 같은 전장)", "적중 %d · 깎은 체력 %.1f · 회복 %.4f"
		% [int(sk_row[0]), float(sk_row[1]), float(sk_row[2])])

# ==================================================================
# 4. 승인된 장비 기술 넷 — 파쇄·숙주 자격 정상, 흡혈 없음
# ==================================================================
func sec4_equip_skills() -> void:
	# 4-1. 다섯 경로 각각으로 얼어붙은 적을 실제로 때린다 → 파쇄 1회, 흡혈 0
	var open_ok := true
	var rows := []
	for c in EQ_OPEN:
		var st := lab("slowfield", "", "sword", false, [], { "lifesteal": 3 })
		var e := dummy(st, 90.0, 0.0)
		var froze: bool = freeze(st, e)
		eq_blow(st, e, String(c), 5.0)
		rows.append("%s 파쇄 %.0f·흡혈 %.4f" % [String(c), shatters(st), healed(st)])
		if not (froze and is_equal_approx(shatters(st), 1.0) and is_zero_approx(healed(st))):
			open_ok = false
	ok("4-1: **장비 기술 넷의 다섯 경로는 파쇄 자격 그대로** · 흡혈은 여전히 0", open_ok, " · ".join(rows))
	note("장비 기술 4종(다섯 경로)", " · ".join(rows))

	# 4-2. 닫아 둔 둘은 그대로 닫혀 있다
	var st2 := lab("slowfield", "", "sword", false, [], { "lifesteal": 3 })
	var e2 := dummy(st2, 90.0, 0.0)
	var froze2: bool = freeze(st2, e2)
	eq_blow(st2, e2, "eq_icetomb", 5.0)
	ok("4-2: **결정 관은 닫힌 채다**(파쇄 0 · 빙결 유지) · 유예의 시계는 경로 이름 자체가 없다",
		froze2 and is_zero_approx(shatters(st2)) and st2.is_frozen(e2)
		and is_zero_approx(healed(st2)) and not PSupport.known_cause("eq_reprieve"),
		"파쇄 %.0f · 빙결 %s" % [shatters(st2), str(st2.is_frozen(e2))])

	# 4-3. **실제 발동 경로**: 장비를 착용하고 [4] 찰나 가르기를 실제로 써서 파쇄가 나는지 본다
	var st3 := lab("eq_flashcut", "", "sword", false, [], { "lifesteal": 3 }, {}, [], { "weapon": "instant_blade" })
	var e3 := dummy(st3, 120.0, 0.0)
	var froze3: bool = freeze(st3, e3)
	var hp3: float = float(e3.hp)
	PSkills.cast(st3, "q")
	st3.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": true, "skill_e": false }, STEP)
	ok("4-3: **장비를 끼고 [4] 찰나 가르기를 실제로 발동** — 파쇄 1회 · 흡혈 0(수동 기술과 다른 결론)",
		froze3 and float(e3.hp) < hp3 and is_equal_approx(shatters(st3), 1.0)
		and not st3.is_frozen(e3) and is_zero_approx(healed(st3)),
		"피해 %.1f · 파쇄 %.0f · 흡혈 %.4f" % [hp3 - float(e3.hp), shatters(st3), healed(st3)])

# ==================================================================
# 5. 미결정 둘(감전 후속·까마귀 표적) — 실제 경로에서도 0이다
# ==================================================================
## 합의 문구에 근거가 없어 **명시적 허용을 확정하지 않았다.** 결과가 어떻게 나오는지는 값으로 남긴다.
func sec5_undecided() -> void:
	var T := PCatalog.support_tuning("orb")

	# 5-1. 감전 후속: 감전된 적을 수동 기술로 때려도 후속이 터지지 않는다(주무기로는 터진다)
	var st := lab("strike", "", "sword", false, [["orb", 1, ["conduct"]]], {})
	var e := dummy(st, 90.0, 0.0)
	e.conduct = float(T.get("shockDur", 2.0))
	var r := cast_and_hurt(st, e, [[e, float(e.x), float(e.y)]])
	var by_skill: float = shock_procs(st)
	var chg_skill: int = int(st.support_charge)
	e.conduct = float(T.get("shockDur", 2.0))
	main_blow(st, e, 5.0)
	ok("5-1: **미결정(불허 결과)** — 수동 기술로는 감전 후속도 방전 충전도 없다(주무기로는 터진다)",
		bool(r.hit) and is_zero_approx(by_skill) and chg_skill == 0
		and is_equal_approx(shock_procs(st), 1.0) and int(st.support_charge) == 1,
		"수동 기술 뒤 후속 %.0f·충전 %d → 주무기 1대 뒤 후속 %.0f·충전 %d"
			% [by_skill, chg_skill, shock_procs(st), int(st.support_charge)])
	note("감전 후속(낙뢰 실제 발동)", "%.0f회 (대조군 주무기 %.0f회)" % [by_skill, shock_procs(st)])

	# 5-2. 까마귀 표적: 수동 기술로 때린 적은 지정되지 않는다(주무기로 때린 적은 된다)
	var st2 := lab("strike", "", "sword", false, [["crow", 1, []]], {})
	var a2 := dummy(st2, 90.0, 0.0)
	var b2 := dummy(st2, 90.0, 70.0)
	var r2 := cast_and_hurt(st2, a2, [[a2, float(a2.x), float(a2.y)], [b2, float(b2.x), float(b2.y)]])
	var marks_skill: int = marks(st2)
	var target_skill = ((st2.support as Dictionary).get("crow", {}) as Dictionary).get("target", null)
	main_blow(st2, b2, 5.0)
	var S2: Dictionary = (st2.support as Dictionary).get("crow", {})
	var target_main = S2.get("target", null)
	ok("5-2: **미결정(불허 결과)** — 수동 기술로 때린 적은 까마귀 표적이 되지 않는다(주무기로 때린 적은 된다)",
		bool(r2.hit) and marks_skill == 0 and target_skill == null
		and target_main != null and int((target_main as Dictionary).id) == int(b2.id) and marks(st2) == 1,
		"수동 기술 뒤 지정 %d회 → 주무기 1대 뒤 지정 %d회" % [marks_skill, marks(st2)])
	note("까마귀 지정(낙뢰 실제 발동)", "%d회 (대조군 주무기 %d회)" % [marks_skill, marks(st2)])

# ==================================================================
# 6. 숙주 파열 — 수동 기술 처치로는 열리지 않는다(전염은 그대로)
# ==================================================================
func sec6_host_burst() -> void:
	var st := lab("strike", "", "sword", false, [["plague", 1, ["burst"]]], {})
	var host := dummy(st, 90.0, 0.0, 6.0)
	var near1 := dummy(st, 110.0, 30.0, 4000.0)
	PSupport.fire(st, wep(st, "plague"), host, false)
	run_pinned(st, 1.2, [[host, float(host.x), float(host.y)], [near1, float(near1.x), float(near1.y)]])
	var P: Dictionary = PSupportB.plague_stat(st)
	var was_infected: bool = infected(host)
	var hp_n: float = float(near1.hp)
	var r := cast_and_hurt(st, host, [[host, float(host.x), float(host.y)], [near1, float(near1.x), float(near1.y)]], 2.0)
	ok("6-1: **수동 기술로 감염된 적을 실제로 처치해도 숙주 파열은 0이다**(불허 유지)",
		was_infected and bool(host.dead) and int(P.bursts) == 0 and int(P.burst_blocked) >= 1
		and is_equal_approx(float(near1.hp), hp_n),
		"처치 %s · 파열 %d회 · 막힘 %d회 · 이웃 체력 %.1f(그대로 %.1f)"
			% [str(r.hit), int(P.bursts), int(P.burst_blocked), float(near1.hp), hp_n])
	ok("6-2: 그때에도 **독 전염은 그대로 일어난다**(전염과 파열을 구분한다)",
		int(P.spreads) >= 1 and infected(near1), "전염 %d회" % int(P.spreads))
	note("숙주 파열(낙뢰로 감염 적 처치)", "%d회(막힘 %d) · 전염 %d회" % [int(P.bursts), int(P.burst_blocked), int(P.spreads)])

	# 대조군: 같은 전장에서 주무기로 처치하면 파열이 실제로 난다
	var st2 := lab("strike", "", "sword", false, [["plague", 1, ["burst"]]], {})
	var host2 := dummy(st2, 90.0, 0.0, 6.0)
	var near2 := dummy(st2, 110.0, 30.0, 4000.0)
	PSupport.fire(st2, wep(st2, "plague"), host2, false)
	run_pinned(st2, 1.2, [[host2, float(host2.x), float(host2.y)], [near2, float(near2.x), float(near2.y)]])
	var P2: Dictionary = PSupportB.plague_stat(st2)
	var hp_n2: float = float(near2.hp)
	main_blow(st2, host2, 1.0e6)
	ok("6-3: **대조군** — 같은 전장에서 주무기로 처치하면 숙주 파열이 실제로 난다",
		bool(host2.dead) and int(P2.bursts) == 1 and float(near2.hp) < hp_n2,
		"파열 %d회 · 이웃 %.1f → %.1f" % [int(P2.bursts), hp_n2, float(near2.hp)])
	note("숙주 파열 대조군(주무기 처치)", "%d회" % int(P2.bursts))

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

# ==================================================================
# 7. 실측표 — 보고서에 그대로 옮길 값
# ==================================================================
func sec7_table() -> void:
	print("\n=== 수동 기술 고유 출처: 같은 조건에서 잰 값 ===")
	var names := measured.keys()
	names.sort()
	for k in names:
		print("%-34s %s" % [String(k), String(measured[k])])
	print("=== 표 끝 ===\n")
	ok("7-1: 실측표를 남겼다", measured.size() >= 10, "%d줄" % measured.size())
