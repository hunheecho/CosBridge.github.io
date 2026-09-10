extends SceneTree
## **이것은 규칙 호출 검사다. 화면 버튼을 하나도 누르지 않는다.**
## 실행: python tools/run_suites.py --suites equip_chain_tests --jobs 1
##
## 무엇을 하고 무엇을 하지 않는가 — 사용자 지적(2026-09-10)으로 범위를 바로잡았다:
##   "현재 검사는 규칙 함수를 직접 호출하는 연결 검사다.
##    이를 **실제 화면 버튼 조작 완료로 보고하지 마라.**"
##   여기서 부르는 것은 PRun·PGrowth·PSave·PSkills 의 규칙 함수뿐이다. scenes/main.tscn 을 띄우지 않는다.
##   **실제 화면 버튼 경로**는 tests/ui_chain_tests.gd 가 같은 순서를 버튼으로 이어서 확인한다.
##   **장비 기술 6종 각각의 전투 발동**(무엇을 맞혔고 무엇이 바뀌었는지)은 tests/eq_fire_tests.gd 가
##   **적을 세워 놓고** 값으로 확인한다. 이 파일의 [6]은 그 대신이 아니다(아래 [6] 머리말 참고).
##
## 이 파일이 실제로 덮는 것 — **연결의 존재**와 **한 회차 안에서의 앞뒤 관계**다:
##   [0] 장비 기술 6종에 각각 실제 장비가 붙어 있는가(연결 존재 확인)
##   [1]~[9] 구매·강화·제작·착용·보관·배치·교환·저장·해제가 서로 어긋나지 않는가
##
## 왜 있는가 — 사용자 지시(2026-09-10):
##   "구조는 우리 설계와 맞아. 현재는 '각 갈래 완료·통합 전'이고,
##    실제 장비 6종을 연결한 검수가 남아 있어."
##
## 갈래별 검사(bank_tests 등)는 **시험용 장비(demo_flashcut_blade)** 로 규칙만 확인한다.
## 여기서는 자료에 실제로 있는 장비만 쓴다:
##   상점에서 사는 것  instant_blade(eq_flashcut) · falling_star_maul(eq_meteor)
##                     counter_guard(eq_riposte) · retrace_greaves(eq_retrace)
##   제작으로 만드는 것 crystal_coffin(eq_icetomb) · reprieve_coat(eq_reprieve)
##
## 한 줄로 잇는 순서(지시문 §6):
##   구매 → 강화 → 제작 → 착용 → 전투 발동 → 거점 → 교체 → 창고 보관
##   → 장비 기술 Q 배치 → Q/E 교환 → 저장 → 이어하기 → 해제 → 일반 스킬 재배치
##
## 여기 수치는 전부 기존 자료값이다. 이 검사가 새로 정한 밸런스는 없다.

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 자료에서 읽은 '기술을 주는 장비' 표. 검사가 이름을 손으로 적지 않게 한다
func granting_map() -> Dictionary:
	var out := {}
	for sid in ["eq_flashcut", "eq_meteor", "eq_riposte", "eq_retrace", "eq_icetomb", "eq_reprieve"]:
		out[sid] = PCatalog.equipment_granting(String(sid))
	return out

## 재고에 없는 장비를 살 수 있게 그 종류를 오늘 재고에 끼워 넣는다.
## (운에 맡기면 검사가 어떤 날은 저절로 통과한다 — equip_ui_tests 와 같은 방식)
func stock_in(run: Dictionary, type_id: String) -> void:
	var st := PRun.stock(run)
	if not (st.equipment as Array).has(type_id):
		(st.equipment as Array).append(type_id)

func mk_run() -> Dictionary:
	var r := PRun.new_run(1, "sword")
	r.gold = 99999
	r.bossesDone = ["a", "b", "c"] # 강화 단계를 전부 연다(관문 돌파 수로 열린다)
	for mk in (PCatalog.materials() as Dictionary):
		(r.mats as Dictionary)[String(mk)] = 20
	return r

func _init() -> void:
	print("[0] 연결 존재 확인(규칙 호출) — 장비 기술 6종에 각각 실제 장비가 붙어 있다")
	print("     ※ 이것은 '자료의 연결이 있다'까지다. 각 기술이 전투에서 실제로 무엇을 하는지는")
	print("        tests/eq_fire_tests.gd 가 적을 세워 놓고 값으로 확인한다.")
	var gm := granting_map()
	var missing: Array = []
	for sid in gm:
		if String(gm[sid]) == "" or not PCatalog.equipment_known(String(gm[sid])):
			missing.append(sid)
	ok("장비 기술 6종에 각각 실제 장비가 붙어 있다", missing.is_empty(), str(gm))
	if not missing.is_empty():
		print("%d/%d PASS" % [pass_n, pass_n + fail_n])
		quit(1)
		return

	var run := mk_run()

	print("\n[1] 구매 — 실제 상점 통로로 산다")
	var shield_src := "emergency_shield" # 결정 관의 재료
	stock_in(run, shield_src)
	stock_in(run, "counter_guard")
	var gold0 := int(run.gold)
	ok("재료 방패를 살 수 있다", PRun.can_buy_equipment(run, shield_src))
	PRun.buy_equipment(run, shield_src, false)
	PRun.buy_equipment(run, "counter_guard", false)
	var src_uid := ""
	for u in run.bag:
		if PRun.equip_type_of(String(u)) == shield_src:
			src_uid = String(u)
	ok("산 것이 **개체 id**로 들어온다(종류 문자열이 아니다)", src_uid.find("#") >= 0, src_uid)
	ok("금화가 실제로 줄었다", int(run.gold) < gold0, "%d → %d" % [gold0, int(run.gold)])

	print("\n[2] 강화 — 개체에 붙는다")
	var paid_up := 0
	var steps := 0
	while PRun.can_upgrade_equip(run, src_uid):
		var q := PRun.equip_upgrade_next(run, src_uid)
		paid_up += int(q.cost)
		PRun.upgrade_equip(run, src_uid, int(q.cost))
		steps += 1
	var src_plus := PRun.equip_plus_of(run, src_uid)
	ok("강화가 붙었다", src_plus > 0, "+%d (%d단계, %d금)" % [src_plus, steps, paid_up])
	var other_uid := ""
	for u2 in run.bag:
		if PRun.equip_type_of(String(u2)) == "counter_guard":
			other_uid = String(u2)
	ok("같은 회차의 **다른 개체**는 강화가 옮지 않는다",
		PRun.equip_plus_of(run, other_uid) == 0, other_uid)

	print("\n[3] 제작 — 강화 계승과 재료 소비")
	var made := String(gm["eq_icetomb"]) # crystal_coffin
	var bag_before: int = (run.bag as Array).size()
	ok("제작할 수 있다", PRun.can_craft(run, made), made)
	PRun.craft(run, made, true, false)
	var made_uid := ""
	for u3 in run.bag:
		if PRun.equip_type_of(String(u3)) == made:
			made_uid = String(u3)
	ok("완성품이 개체로 들어왔다", made_uid != "", made_uid)
	ok("재료로 쓴 **그 개체만** 사라졌다",
		not PRun.has_equip_uid(run, src_uid) and PRun.has_equip_uid(run, other_uid),
		"가방 %d → %d" % [bag_before, (run.bag as Array).size()])
	ok("제작 강화 계승 — 재료 +%d 가 결과로 이어진다" % src_plus,
		PRun.equip_plus_of(run, made_uid) == src_plus,
		"재료 +%d → 결과 +%d" % [src_plus, PRun.equip_plus_of(run, made_uid)])
	var nxt := PRun.equip_upgrade_next(run, made_uid)
	ok("계승한 단계의 강화 비용을 **다시 받지 않는다**(다음 견적이 그 단계 다음이다)",
		nxt.is_empty() or int(nxt.plus) == src_plus,
		str(nxt.get("plus", "최대")))

	print("\n[4] 착용 — 착용해야 장비 기술이 생긴다")
	ok("착용 전에는 그 기술이 없다",
		not PGrowth.granted_skill_ids(run).has("eq_icetomb"), str(PGrowth.granted_skill_ids(run)))
	PRun.equip_item(run, made_uid)
	ok("착용하면 장비 기술이 생긴다",
		PGrowth.granted_skill_ids(run).has("eq_icetomb"), str(PGrowth.granted_skill_ids(run)))

	print("\n[5] 창고 보관 → 장비 기술 Q 배치")
	var q_before = run.growth.skills.get("q", null)
	var q_id_before := "" if q_before == null else String(q_before.id)
	PGrowth.place_skill(run, "q", "eq_icetomb")
	ok("Q에 장비 기술이 들어갔다", PGrowth.skill_id_in(run.growth, "q") == "eq_icetomb")
	if q_id_before != "":
		ok("원래 Q에 있던 일반 기술은 **창고로 갔다**(사라지지 않는다)",
			PGrowth.in_bank(run.growth, q_id_before), q_id_before)
	ok("장비 기술은 창고에 복제되지 않는다",
		not PGrowth.in_bank(run.growth, "eq_icetomb"), str(PGrowth.bank_ids(run.growth)))

	print("\n[6] 재사용 시계 — **결정 관 한 종만**, 적이 없는 전장에서 시계만 본다")
	print("     ※ 6종 전투 검증이 아니다. 여기서 보는 것은 '발동하면 시계가 돌고 연타가 막힌다'뿐이고,")
	print("        무엇을 맞혔는지·무엇이 바뀌었는지는 보지 않는다(적이 없다).")
	print("        6종 각각의 적중·방어·귀환·가둠·유예는 tests/eq_fire_tests.gd 가 확인한다.")
	var st := _mk_combat(run)
	ok("쓰기 전에는 재사용 대기가 없다", PSkills.cd_left(st, "q") <= 0.0, str(PSkills.cd_left(st, "q")))
	var fired := PSkills.cast(st, "q")
	ok("장비 기술이 실제로 발동했다", fired)
	var cd_after := PSkills.cd_left(st, "q")
	ok("발동 뒤 재사용 대기가 생긴다", cd_after > 0.0, "%.2f초" % cd_after)
	ok("연달아 다시 쓰이지 않는다", not PSkills.cast(st, "q"))

	print("\n[7] Q/E 교환 — 교환 **전** 전투 객체의 옛 시계가 그대로다(여기까지만이다)")
	print("     ※ 이것만으로 '우회가 없다'고 끝내지 않는다. 실제 편성 변경 경로를 거친 뒤")
	print("        **새 전투에 들어가 옮겨진 슬롯에서 재시전**해 보는 것은 tests/ui_chain_tests.gd 가 한다.")
	PGrowth.swap_qe(run)
	ok("교환하면 Q와 E가 바뀐다", PGrowth.skill_id_in(run.growth, "e") == "eq_icetomb",
		"q=%s e=%s" % [PGrowth.skill_id_in(run.growth, "q"), PGrowth.skill_id_in(run.growth, "e")])
	ok("거점 조작이 전투의 재사용 시계를 초기화하지 않는다",
		is_equal_approx(PSkills.cd_left(st, "q"), cd_after), "%.2f" % PSkills.cd_left(st, "q"))

	print("\n[8] 저장 → 이어하기")
	var bank_before := PGrowth.bank_ids(run.growth).duplicate()
	var plus_before := PRun.equip_plus_of(run, made_uid)
	var saved := PSave.save(run)
	ok("저장이 실제로 됐다(격리된 저장 자리)", saved, PSave.write_blocked())
	var back := PSave.load()
	ok("이어하기가 회차를 돌려준다", not back.is_empty())
	ok("강화 단계가 살아남았다", PRun.equip_plus_of(back, made_uid) == plus_before,
		"+%d → +%d" % [plus_before, PRun.equip_plus_of(back, made_uid)])
	ok("착용 장비 개체 id가 그대로다",
		String(back.equipment.get("shield", "")) == made_uid, str(back.equipment))
	ok("창고 내용이 그대로다", PGrowth.bank_ids(back.growth) == bank_before,
		"%s vs %s" % [str(bank_before), str(PGrowth.bank_ids(back.growth))])
	ok("Q/E 편성이 그대로다", PGrowth.skill_id_in(back.growth, "e") == "eq_icetomb",
		"q=%s e=%s" % [PGrowth.skill_id_in(back.growth, "q"), PGrowth.skill_id_in(back.growth, "e")])

	print("\n[9] 해제 → 장비 기술은 못 쓰고, 일반 기술은 다시 배치된다")
	PRun.unequip_item(back, "shield")
	ok("해제하면 그 장비 기술이 없어진다",
		not PGrowth.granted_skill_ids(back).has("eq_icetomb"), str(PGrowth.granted_skill_ids(back)))
	ok("배치 자체는 남는다(조용히 지우지 않는다)",
		PGrowth.skill_id_in(back.growth, "e") == "eq_icetomb")
	var st2 := _mk_combat(back)
	ok("장비를 벗으면 그 기술이 발동하지 않는다", not PSkills.cast(st2, "e"))
	var re_id := "" if bank_before.is_empty() else String(bank_before[0])
	if re_id != "":
		PGrowth.place_skill(back, "e", re_id)
		ok("창고의 일반 기술을 그 칸에 다시 배치할 수 있다",
			PGrowth.skill_id_in(back.growth, "e") == re_id, re_id)
		ok("다시 배치한 일반 기술은 창고에서 빠진다",
			not PGrowth.in_bank(back.growth, re_id), str(PGrowth.bank_ids(back.growth)))
	else:
		ok("창고에 되돌릴 일반 기술이 있었다(이 검사의 전제)", false, "창고가 비어 있다")

	print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)

## 적이 나오지 않는 **빈 전장**. 여기서 알 수 있는 것은 재사용 시계와 발동 여부뿐이다 —
## 효과가 무엇을 맞혔는지는 알 수 없다. 그 확인은 tests/eq_fire_tests.gd 가 표적을 세워 놓고 한다
func _mk_combat(r: Dictionary) -> CombatState:
	var st := CombatState.new({ "build": PBuild.derive(r), "seed": 1, "arena": "clearing",
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.player.x = 480.0
	st.player.y = 300.0
	st.player.attack_timer = 1.0e8
	return st
