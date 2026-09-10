extends SceneTree
## 스킬 창고와 Q/E 편성 · 장비 기술의 소유·보관·배치 자격(2026-09-10 §5·§6·§7) 검사(화면 없음).
## 실행: python tools/run_suites.py --suites bank_tests --jobs 1
##
## 무엇을 못박는가 — 네 상태를 **서로 다른 곳**에서 읽는다는 것
##   보유 : Q·E에 있거나 창고에 있다      (PGrowth.owns_manual_skill)
##   보관 : growth.bank 안에만 있다        (PGrowth.in_bank)
##   배치 : growth.skills.q/.e             (PGrowth.skill_id_in)
##   착용 : run.equipment의 장비가 grantsSkill을 준다 (PGrowth.granted_skill_ids)
##
##  4) 일반 Q Lv3+변형 보유 → 장비 기술로 교체 → 창고에서 원래 레벨·변형 유지
##  5) 장비 해제 → 장비 기술 사용 불가(배치는 남는다) → 창고에서 꺼내 다시 전투 사용
##  6) Q/E 맞바꾸기 → 입력·재사용 시간이 새 배치와 일치
##  7) 저장/이어하기 뒤 창고·Q/E 편성 보존
##  8) 장비 기술이 레벨업·개조 후보에 섞이지 않음(후보 생성·선택 확정 양쪽)
##  + 장착·해제·Q/E 교환으로 재사용 시간이 초기화되지 않음
##  + 보관 스킬의 효과가 미편성 상태에서 전투에 적용되지 않음
##  + 장비 기술이 일반 스킬로 창고에 영구 복제되지 않음
##  + 옛 저장(bank 키가 없는 회차) 보존
##
## 여기 수치는 전부 기존 자료값이며 이 검사에서 새로 정한 밸런스가 아니다.
## 시험용 장비(demo_flashcut_blade)는 **환경 변수로만 나타나는 코드 안의 정의**다(data/*.json 아님).

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

const DEMO := "demo_flashcut_blade"
const EQSK := "eq_flashcut"

## 시험용 회차: Q에 감속장 Lv3·변형 'follow', E에 낙뢰 Lv2. 가방에 시험용 각인검
func mk_run() -> Dictionary:
	var r := PRun.new_run(1, "sword")
	r.growth.skills.q = { "id": "slowfield", "level": 3, "variant": "follow" }
	r.growth.skills.e = { "id": "strike", "level": 2, "variant": null }
	r.gold = 9999
	(r.bag as Array).append(PRun.equip_new_uid(r, DEMO))
	return r

func bank_of(r: Dictionary) -> Array:
	return PGrowth.bank_ro(r.growth)

func _init() -> void:
	OS.set_environment(PCatalog.DEMO_EQUIP_ENV, "1") # 시험용 장비 정의를 켠다(코드 안에만 있는 정의)
	PCatalog.reset()

	print("\n[1] 네 상태의 분리 · 새 회차")
	var r0 := PRun.new_run(1, "sword")
	r0.growth = PGrowth.new_growth("sword", "gust") # 시작 화면에서 고른 기술이 Q에 들어가는 경로
	ok("새 회차: 창고는 비어 있고 고른 기술이 Q에, E는 빈칸", bank_of(r0).is_empty()
		and String(r0.growth.skills.q.id) == "gust" and r0.growth.skills.get("e", null) == null)
	ok("장비 기술 판정은 id 규약 하나로 한다(eq_ 로 시작)", PGrowth.is_equip_skill(EQSK) and not PGrowth.is_equip_skill("slowfield"))
	ok("장비 기술 정의는 일반 기술 목록(e_skills)에 들어 있지 않다",
		not (PCatalog.e_skills() as Array).has(EQSK) and PCatalog.skills().has(EQSK),
		"e_skills %s" % str(PCatalog.e_skills()))
	ok("장비 기술 6종이 모두 등록돼 있고 전부 eq_ 로 시작한다", _all_eq_prefixed(), str(PCatalog.equip_skill_defs().keys()))

	print("\n[2] 착용해야 '사용 가능' · 배치는 따로 (§6)")
	var r := mk_run()
	ok("가방에만 있으면 장비 기술이 나타나지 않는다(착용만이 자격이다)", PGrowth.granted_skill_ids(r).is_empty())
	var uid := String(r.bag[0])
	PRun.equip_item(r, uid)
	ok("착용하면 장비 기술이 '사용 가능' 목록에 나타난다", PGrowth.granted_skill_ids(r) == [EQSK], str(PGrowth.granted_skill_ids(r)))
	ok("착용만으로는 Q·E에 **배치되지 않는다**(자동으로 들어가지 않는다)",
		String(r.growth.skills.q.id) == "slowfield" and String(r.growth.skills.e.id) == "strike")

	print("\n[3] 검증 4) 장비 기술로 교체해도 창고가 원래 레벨·변형을 지킨다")
	var b_before := PBuild.derive(r)
	var cd_before := float(b_before.special_cd)
	var placed := PGrowth.place_skill(r, "q", EQSK)
	ok("Q에 장비 기술을 배치할 수 있다", placed and String(r.growth.skills.q.id) == EQSK)
	var be := PGrowth.bank_entry(r.growth, "slowfield")
	ok("원래 Q의 감속장은 **삭제되지 않고 창고로** 간다 — Lv3·변형 'follow' 그대로",
		not be.is_empty() and int(be.level) == 3 and String(be.variant) == "follow", str(be))
	ok("창고에 있는 감속장은 '사용 중'이 아니다(기술 조건이 켜지지 않는다)",
		not PGrowth.has_skill(r.growth, "slowfield") and not PGrowth.boss_reward_applies(r.growth, "clone")
		and PGrowth.equip_inactive_reason_run(r, "chrono_staff") != "")
	ok("보유는 유지된다(창고에 있으므로 새 기술 후보·상점 진열로 다시 나오지 않는다)",
		PGrowth.owns_manual_skill(r.growth, "slowfield") and not PProfile.run_unlock_ok(r, "e_skills", "slowfield"))
	ok("장비 기술은 기존 Q의 레벨·변형을 **계승하지 않는다**(Lv1 고정 · 변형 없음)",
		int(r.growth.skills.q.level) == 1 and r.growth.skills.q.get("variant", null) == null)
	var b_eq := PBuild.derive(r)
	# 재사용 값을 **숫자로 박지 않는다.** 통합에서 두 갈래가 같은 기술에 다른 값을 잡아
	# (창고 8초 · 전투 구현 10초) 여기서 깨졌다. 정본은 자료(data/growth.json)이므로
	# 자료에서 읽어 비교한다 — 시험값을 조정해도 이 단언은 따라간다
	var eq_cd_want: float = float((PCatalog.skills()[EQSK].cooldown as Array)[0])
	ok("전투가 보는 Q도 장비 기술로 바뀐다 · 재사용은 **그 기술 자료의 표**를 쓴다(%.1f초)" % eq_cd_want,
		String(b_eq.skills.q.id) == EQSK and is_equal_approx(float(b_eq.special_cd), eq_cd_want),
		"%s / %s (전 %s)" % [String(b_eq.skills.q.id), str(b_eq.special_cd), str(cd_before)])

	print("\n[4] 검증 8) 장비 기술이 레벨업·개조 후보에 섞이지 않는다")
	r.growth.level = 4
	var kinds := {}
	for c in PGrowth.candidates(r, { "pool": "level" }):
		if String(c.kind).begins_with("skill_"):
			kinds["%s:%s" % [String(c.kind), String(c.id)]] = true
	var eq_in_cand := false
	for k in kinds:
		if String(k).find(EQSK) >= 0:
			eq_in_cand = true
	ok("후보 생성에 장비 기술의 레벨업·변형·신규가 하나도 없다", not eq_in_cand, str(kinds.keys()))
	var lv_forced: bool = PGrowth.apply_choice(r, { "kind": "skill_level", "id": EQSK, "slot": "q" }, true)
	var v_forced: bool = PGrowth.apply_choice(r, { "kind": "skill_variant", "id": EQSK, "slot": "q", "variant": "follow" }, true)
	var r_e := mk_run()
	r_e.growth.skills.e = null # E를 비워 둔다 — '슬롯이 차서'가 아니라 '장비 기술이라서' 거부되는 것을 본다
	var new_forced: bool = PGrowth.apply_choice(r_e, { "kind": "skill_new", "id": EQSK }, true)
	ok("후보를 지나 들어와도 **확정에서 거부**한다(레벨업·변형·새 기술 셋 다)",
		not lv_forced and not v_forced and not new_forced and int(r.growth.skills.q.level) == 1)
	var r_b := mk_run()
	r_b.growth.skills.e = null
	PGrowth.bank(r_b.growth).append({ "id": "slowfield", "level": 3, "variant": "follow" })
	r_b.growth.skills.q = { "id": "gust", "level": 1, "variant": null }
	var bank_dup: bool = PGrowth.apply_choice(r_b, { "kind": "skill_new", "id": "slowfield" }, true)
	ok("창고에 든 기술을 '새 기술'로 다시 주지 않는다(중복 소유 차단)", not bank_dup)
	ok("상점 E 교체는 장비 기술 칸을 대상으로 삼지 않는다", PRun.swap_quote(r, "e", 0).is_empty() == false
		and PRun.swap_quote(_with_eq_in_e(), "e", 0).is_empty())

	print("\n[5] 검증 5) 장비를 벗으면 사용 불가 · 배치와 창고는 남는다")
	PRun.unequip_item(r, "weapon")
	var b_off := PBuild.derive(r)
	ok("배치는 그대로 남는다(조용히 지우지 않는다)", String(r.growth.skills.q.id) == EQSK)
	ok("전투에서는 쓸 수 없다: 빌드의 Q가 비고 재사용 시간도 계산하지 않는다",
		b_off.skills.q == null and is_equal_approx(float(b_off.special_cd), 0.0) and PGrowth.usable_skill(r, "q") == null)
	ok("왜 못 쓰는지 한 줄로 설명한다", PGrowth.slot_blocked_reason(r, "q") != "", PGrowth.slot_blocked_reason(r, "q"))
	ok("창고의 감속장 Lv3·변형은 그대로 있다(장비를 벗었다고 삭제하지 않는다)",
		int(PGrowth.bank_entry(r.growth, "slowfield").level) == 3)
	ok("임의의 일반 기술을 **자동으로 넣지 않는다**(Q는 여전히 그 장비 기술이고 창고는 그대로)",
		String(r.growth.skills.q.id) == EQSK and bank_of(r).size() == 1)
	var back := PGrowth.place_skill(r, "q", "slowfield")
	var b_back := PBuild.derive(r)
	ok("창고에서 직접 꺼내 Q에 다시 넣으면 **레벨·변형이 복구**된다(Lv3 · follow · 재사용 10초)",
		back and int(r.growth.skills.q.level) == 3 and String(r.growth.skills.q.variant) == "follow"
		and is_equal_approx(float(b_back.special_cd), cd_before) and is_equal_approx(float(b_back.special_cd), 10.0),
		str(b_back.special_cd))
	ok("장비 기술은 창고에 **영구 복제되지 않는다**(칸에서 내려가면 그냥 사라진다)",
		not PGrowth.in_bank(r.growth, EQSK) and bank_of(r).size() == 0, str(PGrowth.bank_ids(r.growth)))

	print("\n[6] 검증 6) Q와 E 맞바꾸기")
	var r2 := mk_run()
	var b2a := PBuild.derive(r2)
	var q_cd := float(b2a.special_cd)
	var e_cd := PBuildDetail.cd_of_build(b2a, "e")
	ok("맞바꾸기 전: Q 감속장 Lv3(10초) · E 낙뢰 Lv2(8초)",
		is_equal_approx(q_cd, 10.0) and is_equal_approx(e_cd, 8.0), "%s / %s" % [str(q_cd), str(e_cd)])
	PGrowth.swap_qe(r2)
	var b2b := PBuild.derive(r2)
	ok("맞바꾸면 기술이 칸을 바꾸고 레벨·변형이 **그 기술을 따라간다**",
		String(r2.growth.skills.q.id) == "strike" and int(r2.growth.skills.q.level) == 2
		and String(r2.growth.skills.e.id) == "slowfield" and int(r2.growth.skills.e.level) == 3
		and String(r2.growth.skills.e.variant) == "follow")
	ok("재사용 시간도 새 배치를 따라간다(Q 8초 · E 10초) — 짧은 쪽으로 바뀌는 구멍이 없다",
		is_equal_approx(float(b2b.special_cd), 8.0) and is_equal_approx(PBuildDetail.cd_of_build(b2b, "e"), 10.0),
		"%s / %s" % [str(b2b.special_cd), str(PBuildDetail.cd_of_build(b2b, "e"))])
	ok("같은 기술을 두 칸에 두지 않는다(창고에서 꺼낼 때도, 장비 기술도)",
		not PGrowth.place_skill(r2, "q", "slowfield") and _dup_equip_blocked())

	print("\n[7] 재사용 시간 우회가 없다 · 전투 중에는 편성을 열지 않는다")
	var r3 := mk_run()
	r3.phase = "combat"
	ok("전투 중에는 배치·보관·맞바꾸기가 모두 거부된다(사유를 돌려준다)",
		PGrowth.bank_edit_reason(r3) != "" and not PGrowth.store_skill(r3, "q")
		and not PGrowth.swap_qe(r3) and not PGrowth.place_skill(r3, "e", "slowfield"),
		PGrowth.bank_edit_reason(r3))
	var r4 := mk_run()
	var st := _mk_combat(r4)
	PSkills.cast(st, "q")
	var left_before := PSkills.cd_left(st, "q")
	PGrowth.swap_qe(r4) # 거점 조작(전투 상태와 다른 dict)이 전투 시계를 건드리지 않는다
	ok("편성 조작은 전투의 재사용 시계(player.special_cd)를 건드리지 않는다",
		is_equal_approx(PSkills.cd_left(st, "q"), left_before) and left_before > 0.0, str(left_before))

	print("\n[8] 보관 스킬은 미편성 상태에서 전투에 적용되지 않는다")
	var r5 := PRun.new_run(1, "sword")
	r5.growth.skills.q = { "id": "slowfield", "level": 3, "variant": null }
	r5.equipment.weapon = "chrono_staff" # 옛 저장 형식(종류 문자열)도 그대로 읽힌다
	PGrowth.store_skill(r5, "q")
	var b5 := PBuild.derive(r5)
	ok("감속장을 창고에 넣으면 Q가 비고 감속장 조건 장비가 '지금 효과 없음'이 된다",
		b5.skills.q == null and not PGrowth.has_skill(r5.growth, "slowfield")
		and PGrowth.equip_inactive_reason_run(r5, "chrono_staff") != "")
	ok("그래도 장비·창고는 지우지 않는다(다시 배치하면 그대로 되살아난다)",
		String(r5.equipment.weapon) == "chrono_staff" and PGrowth.in_bank(r5.growth, "slowfield"))
	PGrowth.place_skill(r5, "e", "slowfield")
	ok("E에 넣어도 감속장 조건은 만족한다(칸 조건이 아니라 기술 조건이다)",
		PGrowth.has_skill(r5.growth, "slowfield") and PGrowth.equip_inactive_reason_run(r5, "chrono_staff") == ""
		and int(r5.growth.skills.e.level) == 3)

	print("\n[9] 검증 7) 저장/이어하기 보존 · 옛 저장")
	var r6 := mk_run()
	PRun.equip_item(r6, String(r6.bag[0]))
	PGrowth.place_skill(r6, "q", EQSK)
	var txt := JSON.stringify(PSave.normalize(r6.duplicate(true)))
	var loaded: Dictionary = PSave.normalize(JSON.parse_string(txt))
	var lb := PGrowth.bank_ro(loaded.growth)
	ok("저장 → 불러오기 뒤 창고(레벨·변형)와 Q/E 배치가 그대로다",
		lb.size() == 1 and String(lb[0].id) == "slowfield" and int(lb[0].level) == 3 and String(lb[0].variant) == "follow"
		and String(loaded.growth.skills.q.id) == EQSK and String(loaded.growth.skills.e.id) == "strike",
		txt.substr(0, 0))
	ok("불러온 회차에서도 장비 착용 자격이 그대로 판정된다", PGrowth.granted_skill_ids(loaded) == [EQSK])
	var old_g := PGrowth.new_growth("sword", "slowfield")
	old_g.erase("bank") # 옛 저장에는 bank 키가 없다
	var old_run := { "growth": old_g, "equipment": { "weapon": null, "armor": null, "shield": null }, "bag": [], "forge": 0, "buffs": {}, "phase": "prep" }
	var b_old := PBuild.derive(old_run)
	ok("옛 저장(bank 키 없음)은 조회만으로 바뀌지 않고 예전과 같은 값을 낸다(감속장 Lv1 = 14초)",
		PGrowth.bank_ro(old_g).is_empty() and not old_g.has("bank") and is_equal_approx(float(b_old.special_cd), 14.0),
		str(b_old.special_cd))
	PGrowth.store_skill(old_run, "q")
	ok("옛 저장도 창고를 그때 만들어 쓴다(기존 Q의 레벨·변형을 잃지 않는다)",
		PGrowth.in_bank(old_g, "slowfield") and int(PGrowth.bank_entry(old_g, "slowfield").level) == 1)

	print("\n[10] grantedBy 통로(장비 정의에 grantsSkill이 아직 없을 때)")
	var defs := PCatalog.equip_skill_defs()
	(defs["eq_riposte"] as Dictionary).grantedBy = ["iron_shield"]
	var r7 := PRun.new_run(1, "sword")
	r7.equipment.shield = "iron_shield"
	ok("기술 정의의 grantedBy만으로도 착용 자격이 잡힌다(두 통로의 합집합)",
		PGrowth.granted_skill_ids(r7).has("eq_riposte"))
	(defs["eq_riposte"] as Dictionary).grantedBy = []

	var pass_n := 0
	for row in results:
		if bool(row[0]):
			pass_n += 1
	print("\n%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

func _all_eq_prefixed() -> bool:
	var d := PCatalog.equip_skill_defs()
	if d.size() != 6:
		return false
	for k in d:
		if not PGrowth.is_equip_skill(String(k)):
			return false
	return true

## E에 장비 기술이 든 회차(상점 교체 대상에서 빠지는지 보려고)
func _with_eq_in_e() -> Dictionary:
	var r := mk_run()
	PRun.equip_item(r, String(r.bag[0]))
	PGrowth.place_skill(r, "e", EQSK)
	return r

## 같은 장비 기술을 두 칸에 두려는 시도가 막히는가
func _dup_equip_blocked() -> bool:
	var r := mk_run()
	PRun.equip_item(r, String(r.bag[0]))
	PGrowth.place_skill(r, "q", EQSK)
	return not PGrowth.place_skill(r, "e", EQSK)

## 적이 나오지 않는 빈 전장(재사용 시계만 본다)
func _mk_combat(r: Dictionary) -> CombatState:
	var st := CombatState.new({ "build": PBuild.derive(r), "seed": 1, "arena": "clearing",
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.player.x = 480.0
	st.player.y = 300.0
	st.player.attack_timer = 1.0e8
	return st
