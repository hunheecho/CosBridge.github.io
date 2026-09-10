extends SceneTree
## **실제 화면 버튼으로 한 회차를 끝까지 잇는다.** scenes/main.tscn 을 진짜로 띄우고 버튼을 누른다.
## 실행: python tools/run_suites.py --suites ui_chain_tests --jobs 1
##
## 왜 있는가 — 사용자 지적(2026-09-10):
##   "현재 검사는 규칙 함수를 직접 호출하는 연결 검사다. 이를 실제 화면 버튼 조작 완료로 보고하지 마라."
##   "교환 전 전투 객체의 옛 Q 시계가 그대로라는 검사만으로 끝내지 마라. 실제 허용된 편성 변경 경로를 거친 뒤,
##    기술이 옮겨진 슬롯에서 재시전을 시도해 우회가 없는지 확인해라."
##   "전투 중 편성 변경이 금지라면 그 차단도 실제 경로에서 확인해라(화면의 버튼이 실제로 막히는지)."
##
## 잇는 순서(사용자 지시문 §3 그대로)
##   구매 → 강화 → 제작 → 착용 → 전투 발동 → 거점 → 교체 → 일반 스킬 창고 보관 → 장비 기술 Q 배치
##   → Q/E 교환 → 저장 → 이어하기 → (옮겨진 슬롯에서 재시전) → 장비 해제 → 일반 스킬 재배치
##
## **눌렀다고 적은 것은 전부 실제로 누른 것이다.** 누른 버튼 이름은 끝에 순서대로 모아 출력한다(PRESS 줄).
## 규칙 계층에 값을 넣은 자리는 **[주입]** 이라고 적는다. 상점이 같은 종류를 두 번 팔지 않고,
## 오늘 재고·제작법 해금은 운과 진행도가 정하므로 정상 경로만으로는 만들 수 없는 상태가 있다.
##
## 무엇을 확인할 수 없는가 — **브라우저(웹 빌드) 확인과 안드로이드 실기 확인은 여기서 하지 않는다.**
## 여기 모바일 확인은 PROPHECY_TOUCH=1 + 좁은 캔버스(640×360)에서 **화면 계층이 만드는 실제 버튼**을
## 재는 것이다. 실제 손가락 감각·실기 성능은 이 검사가 답하지 못한다.

var results := []
var presses := []      # 실제로 누른 버튼 글자(순서대로)
var injections := []   # 규칙 계층에 값을 넣은 자리

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func inject(what: String) -> void:
	injections.append(what)
	print("[주입] " + what)

# ---------- 화면에서 실제로 보이는 것만 찾는다 ----------
func vis_btn(node: Node, part: String, need_enabled: bool = true) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button:
		var b := node as Button
		if b.text.find(part) >= 0 and (not need_enabled or not b.disabled):
			return b
	for c in node.get_children():
		var f := vis_btn(c, part, need_enabled)
		if f != null:
			return f
	return null

func vis_btn_exact(node: Node, text: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and (node as Button).text == text and not (node as Button).disabled:
		return node as Button
	for c in node.get_children():
		var f := vis_btn_exact(c, text)
		if f != null:
			return f
	return null

func node_count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += node_count(c)
	return n

func all_containers(node: Node) -> Array:
	var out := []
	if node is Container:
		out.append(node)
	for c in node.get_children():
		out.append_array(all_containers(c))
	return out

## 그 항목(row_text)이 적힌 **가장 작은 묶음** 안의 버튼. 같은 글자의 버튼이 여러 줄에 있을 때
## 엉뚱한 줄을 눌러 '되는 것처럼' 만들지 않기 위해서다
func row_btn(node: Node, row_text: String, btn_text: String) -> Button:
	var best: Button = null
	var best_n := 1 << 30
	for box in all_containers(node):
		if txt(box, row_text) == 0:
			continue
		var b := vis_btn(box, btn_text)
		if b == null:
			continue
		var n := node_count(box)
		if n < best_n:
			best_n = n
			best = b
	return best

func txt(node: Node, needle: String) -> int:
	if node is Control and not (node as Control).is_visible_in_tree():
		return 0
	var n := 0
	if node is RichTextLabel and String((node as RichTextLabel).text).find(needle) >= 0:
		n += 1
	if node is Label and String((node as Label).text).find(needle) >= 0:
		n += 1
	if node is Button and String((node as Button).text).find(needle) >= 0:
		n += 1
	for c in node.get_children():
		n += txt(c, needle)
	return n

## **실제로 누른다.** 누른 글자를 기록에 남긴다. 못 누르면 false
func tap(node: Node, part: String) -> bool:
	var b := vis_btn(node, part)
	if b == null:
		return false
	presses.append(b.text)
	print("  누름 ▶ " + b.text)
	b.pressed.emit()
	return true

func tap_row(node: Node, row_text: String, part: String) -> bool:
	var b := row_btn(node, row_text, part)
	if b == null:
		return false
	presses.append(b.text)
	print("  누름 ▶ [%s] %s" % [row_text, b.text])
	b.pressed.emit()
	return true

func scr(main: Node) -> Node:
	return main.screens.get(main.screen, null)

func _init() -> void:
	call_deferred("_run")

# ============================================================================
func _run() -> void:
	var udir := OS.get_user_data_dir()
	if udir.find("userdata__") < 0 and udir.find("prophecy_test_runs") < 0:
		printerr("격리되지 않은 저장 폴더에서는 돌리지 않는다(사람 저장을 덮어쓴다): %s" % udir)
		printerr("python tools/run_suites.py --suites ui_chain_tests --jobs 1 로 돌려라.")
		quit(3)
		return
	root.size = Vector2i(960, 640)
	PProfile.use_path("user://prophecy_profile_ui_chain_v1.json")
	PProfile.clear()
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.profile = PProfile.load("legacy")
	inject("프로필 legacy — 해금 제한 없이 재고·제작법이 열린 상태에서 시작한다")
	main.use_bot = false
	main.new_run_opts = { "seed": 4021 }
	inject("시드 4021 고정 — 시간 기반 시드로 검사가 날마다 흔들리지 않게")
	main.start_run("sword")
	await process_frame
	var r: Dictionary = main.run
	r.gold = 9000
	r.bossesDone = ["b1", "b2"]
	for mk in (PCatalog.materials() as Dictionary):
		(r.mats as Dictionary)[String(mk)] = 20
	if r.has("unlocks"):
		r.unlocks.recipes = ["crystal_coffin"]
	r.growth.skills.q = { "id": "slowfield", "level": 3, "variant": "follow" }
	r.growth.skills.e = { "id": "strike", "level": 2, "variant": null }
	inject("금화 9000 · 관문 2돌파 · 재료 20씩 · 제작법 crystal_coffin · 출발 편성(Q 감속장 Lv3 변형 follow · E 낙뢰 Lv2)")
	_stock_in(r, "instant_blade")
	_stock_in(r, "emergency_shield")
	_stock_in(r, "chrono_staff")
	inject("오늘 재고에 instant_blade · emergency_shield · chrono_staff 를 끼워 넣는다(상점은 같은 종류를 두 번 팔지 않고 재고는 추첨이라 정상 경로로 만들 수 없다)")
	main.show("base")
	await process_frame

	var s1: Dictionary = await _step1_buy(main, r)
	if not bool(s1.ok):
		return _finish()
	var blade: String = String(s1.blade)
	await _step2_upgrade(main, r, blade)
	var coffin: String = await _step3_craft(main, r)
	if coffin == "":
		return _finish()
	await _step4_wear(main, r, blade, coffin)
	await _step5_combat(main, r)
	await _step6_swap_equip(main, r, blade)
	await _step7_bank_and_place(main, r)
	await _step8_swap_qe_save_load(main, r)
	await _step9_recast_moved_slot(main, r)
	await _step10_unequip_and_restore(main, r)
	await _step11_mobile(main, r)
	_finish()

func _stock_in(r: Dictionary, type_id: String) -> void:
	var st := PRun.stock(r)
	if not (st.equipment as Array).has(type_id):
		(st.equipment as Array).append(type_id)

# ---------- [1] 구매 ----------
func _step1_buy(main: Node, r: Dictionary) -> Dictionary:
	print("\n[1] 구매 — 거점 '상점' 버튼 → 상점 카드의 '구매 (' → '가방에 넣기'")
	var gold0 := int(r.gold)
	ok("거점에서 '상점' 버튼을 눌러 상점이 열린다", await _press_and_wait(main, main.screens["base"], "상점", "shop"), main.screen)
	if main.screen != "shop":
		return { "ok": false, "blade": "" }
	var shop: Node = main.screens["shop"]
	ok("상점 카드에 기본 능력치·고유 효과가 갈라 적혀 있다",
		txt(shop, "기본 능력치") >= 1 and txt(shop, "고유 효과") >= 1)
	ok("'찰나의 검' 줄의 '구매 (' 버튼을 눌렀다", tap_row(shop, "찰나의 검", "구매 ("))
	await process_frame
	shop = main.screens["shop"]
	ok("확인 창이 뜨고 아직 금화가 빠지지 않았다", txt(shop, "살까요?") == 1 and int(r.gold) == gold0,
		"금화 %d" % int(r.gold))
	ok("'가방에 넣기'를 눌렀다", tap(shop, "가방에 넣기"))
	await process_frame
	var blade := ""
	for u in r.bag:
		if PRun.equip_type_of(String(u)) == "instant_blade":
			blade = String(u)
	ok("찰나의 검이 **개체 id**로 가방에 들어왔고 금화가 실제로 줄었다",
		blade != "" and blade.find("#") > 0 and int(r.gold) < gold0,
		"%s · 금화 %d → %d" % [blade, gold0, int(r.gold)])
	shop = main.screens["shop"]
	ok("'비상 방패' 줄의 '구매 (' 버튼을 눌렀다(제작 재료)", tap_row(shop, "비상 방패", "구매 ("))
	await process_frame
	shop = main.screens["shop"]
	ok("'가방에 넣기'를 눌렀다(재료 방패)", tap(shop, "가방에 넣기"))
	await process_frame
	var have_shield := false
	for u2 in r.bag:
		if PRun.equip_type_of(String(u2)) == "emergency_shield":
			have_shield = true
	ok("재료 방패가 가방에 들어왔다", have_shield, str(r.bag))
	return { "ok": blade != "", "blade": blade }

# ---------- [2] 강화 ----------
func _step2_upgrade(main: Node, r: Dictionary, blade: String) -> void:
	print("\n[2] 강화 — 상점 하단 '대장간' → '+1로 강화' → '강화한다 ('")
	ok("'대장간' 버튼을 눌러 대장간이 열린다",
		await _press_and_wait(main, main.screens["shop"], "대장간", "forge"), main.screen)
	var forge: Node = main.screens["forge"]
	var g0 := int(r.gold)
	ok("'찰나의 검' 줄의 '+1로 강화' 버튼을 눌렀다", tap_row(forge, "찰나의 검", "+1로 강화"))
	await process_frame
	forge = main.screens["forge"]
	ok("확인 창을 거친다(누르기만 하면 금화가 빠지지 않는다)",
		txt(forge, "강화할까요?") == 1 and int(r.gold) == g0 and PRun.equip_plus_of(r, blade) == 0)
	ok("'강화한다 (' 를 눌렀다", tap(forge, "강화한다 ("))
	await process_frame
	ok("그 개체가 +1이 되고 금화가 빠졌다",
		PRun.equip_plus_of(r, blade) == 1 and int(r.gold) < g0,
		"+%d · 금화 %d → %d" % [PRun.equip_plus_of(r, blade), g0, int(r.gold)])

# ---------- [3] 제작 ----------
func _step3_craft(main: Node, r: Dictionary) -> String:
	print("\n[3] 제작 — 대장간 '결정 관' 줄의 '미리보기' → '확정 후 보관'")
	var forge: Node = main.screens["forge"]
	ok("'결정 관' 줄의 '미리보기' 버튼을 눌렀다", tap_row(forge, "결정 관", "미리보기"))
	await process_frame
	forge = main.screens["forge"]
	ok("확인 창이 소비할 장비와 비용을 적는다",
		txt(forge, "소비할 장비") >= 1 and txt(forge, "비상 방패") >= 1)
	var g0 := int(r.gold)
	ok("'확정 후 보관'을 눌렀다", tap(forge, "확정 후 보관"))
	await process_frame
	var coffin := ""
	for u in r.bag:
		if PRun.equip_type_of(String(u)) == "crystal_coffin":
			coffin = String(u)
	var src_gone := true
	for u2 in r.bag:
		if PRun.equip_type_of(String(u2)) == "emergency_shield":
			src_gone = false
	ok("결정 관이 개체로 만들어지고 재료 방패는 사라졌다",
		coffin != "" and src_gone and int(r.gold) < g0,
		"%s · 금화 %d → %d" % [coffin, g0, int(r.gold)])
	return coffin

# ---------- [4] 착용 ----------
func _step4_wear(main: Node, r: Dictionary, blade: String, coffin: String) -> void:
	print("\n[4] 착용 — 대장간 하단 '장비' → 가방 줄 '선택' → '지금 장착'")
	ok("'장비' 버튼을 눌러 장비 화면이 열린다",
		await _press_and_wait(main, main.screens["forge"], "장비", "equip"), main.screen)
	var eq: Node = main.screens["equip"]
	ok("착용 전에는 그 장비 기술이 없다",
		not PGrowth.granted_skill_ids(r).has("eq_flashcut"), str(PGrowth.granted_skill_ids(r)))
	ok("'찰나의 검' 줄의 '선택'을 눌렀다", tap_row(eq, "찰나의 검", "선택"))
	await process_frame
	eq = main.screens["equip"]
	ok("고른 창이 '장비 기술 · 찰나 가르기'와 '착용 중일 때만'을 적는다",
		txt(eq, "찰나 가르기") >= 1 and txt(eq, "착용 중일 때만") >= 1)
	ok("'지금 장착'을 눌렀다", tap(eq, "지금 장착"))
	await process_frame
	ok("착용하면 장비 기술이 생긴다(착용 ≠ 배치 — Q·E는 그대로다)",
		PGrowth.granted_skill_ids(r).has("eq_flashcut")
		and PGrowth.skill_id_in(r.growth, "q") == "slowfield",
		"%s / Q=%s" % [str(PGrowth.granted_skill_ids(r)), PGrowth.skill_id_in(r.growth, "q")])
	eq = main.screens["equip"]
	ok("'결정 관' 줄의 '선택'을 눌렀다", tap_row(eq, "결정 관", "선택"))
	await process_frame
	ok("'지금 장착'을 눌렀다(방패 칸)", tap(main.screens["equip"], "지금 장착"))
	await process_frame
	ok("두 장비가 각각 자기 칸에 들어가 기술 둘을 준다",
		String(r.equipment.get("weapon", "")) == blade and String(r.equipment.get("shield", "")) == coffin
		and PGrowth.granted_skill_ids(r).has("eq_flashcut") and PGrowth.granted_skill_ids(r).has("eq_icetomb"),
		str(PGrowth.granted_skill_ids(r)))
	# 복제 금지: 장비 기술은 보상 후보에도, 영구 보유(창고)에도 들어가지 않는다
	var cand_eq: Array = []
	for c in PGrowth.candidates(r):
		var cid := String((c as Dictionary).get("id", ""))
		if cid.begins_with("eq_"):
			cand_eq.append(cid)
	ok("장비 기술이 일반 보상 후보로 복제되지 않는다", cand_eq.is_empty(), str(cand_eq))
	var bank_eq: Array = []
	for bid in PGrowth.bank_ids(r.growth):
		if String(bid).begins_with("eq_"):
			bank_eq.append(String(bid))
	ok("장비 기술이 영구 보유(창고)로 복제되지 않는다", bank_eq.is_empty(), str(PGrowth.bank_ids(r.growth)))

# ---------- [5] 전투 발동 ----------
func _step5_combat(main: Node, r: Dictionary) -> void:
	print("\n[5] 전투 발동 — 거점 '출격 (' → 전투 화면의 **터치 Q 버튼**을 실제로 눌러 발동")
	ok("'거점으로 (Esc)' 버튼을 눌러 거점으로 돌아온다(키에 기대지 않는 길이 있다)",
		await _press_and_wait(main, main.screens["equip"], "거점으로", "base"), main.screen)
	var bs: Node = main.screens["base"]
	ok("거점에 '출격 (' 버튼이 있고 눌린다", tap(bs, "출격 ("))
	await process_frame
	ok("전투 화면으로 갔다", main.screen == "combat", main.screen)
	if main.screen != "combat":
		return
	var st: CombatState = main.view.st
	st.intro = 0.0
	inject("전투 도입 연출(intro)만 0으로 — 연출이지 규칙이 아니다")
	var tc = main.touch
	tc.layout(PLayout.safe_rect(root))
	ok("터치 조작이 켜져 있다(PROPHECY_TOUCH=1)", bool(tc.enabled) and tc.active(),
		"enabled=%s active=%s" % [str(tc.enabled), str(tc.active())])
	var qc: Vector2 = tc.button_center("special")
	ok("Q 버튼 자리가 화면 안이고 그 자리를 누르면 Q로 잡힌다", tc.pick_at(qc) == "special",
		"자리 %s → %s" % [str(qc), tc.pick_at(qc)])
	var cd0 := PSkills.cd_left(st, "q")
	ok("전투에 들어온 순간 Q 재사용 시계가 0에서 시작한다(전투 진입 초기화)",
		is_equal_approx(cd0, 0.0), "%.2f초" % cd0)
	tc.handle_touch(11, qc, true)
	presses.append("[전투 터치] Q")
	print("  누름 ▶ [전투 터치] Q")
	tc.handle_touch(11, qc, false)
	for i in 6:
		main.view._process(1.0 / 60.0)
	ok("터치 Q로 지금 Q에 든 **일반 기술(감속장)** 이 실제로 발동했다 — 감속장이 깔렸다",
		not st.field.is_empty() and int(st.stats.get("field_uses", 0)) >= 1,
		"감속장 %s · 사용 %d회" % [("깔림" if not st.field.is_empty() else "없음"), int(st.stats.get("field_uses", 0))])
	ok("발동 뒤 재사용 시계가 돈다(재사용 정책: 쓰면 그 슬롯 시계가 찬다)",
		PSkills.cd_left(st, "q") > 0.0, "%.2f초" % PSkills.cd_left(st, "q"))
	# ---- 전투 중 편성 변경 차단을 **화면 경로**에서 확인한다 ----
	var edit_btn := vis_btn(main, "기술 편성")
	ok("전투 중에는 화면 어디에도 '기술 편성' 버튼이 보이지 않는다(눌 수 있는 길이 없다)",
		edit_btn == null, "찾은 버튼: %s" % ("없음" if edit_btn == null else edit_btn.text))
	main.set_pause(true)
	await process_frame
	var edit_btn2 := vis_btn(main, "기술 편성")
	var pause_items: Array = []
	for b in _all_buttons(main.pause_panel):
		pause_items.append((b as Button).text)
	ok("일시정지 화면에도 편성으로 가는 버튼이 없다",
		edit_btn2 == null, "일시정지 버튼 목록 %s" % str(pause_items))
	main.set_pause(false)
	await process_frame
	var reason := PGrowth.bank_edit_reason(r)
	ok("규칙 계층의 편성 잠금 사유(참고 값) — 지금 phase=%s 이므로 사유는 '%s'"
		% [String(r.get("phase", "")), ("(없음 — 열려 있다)" if reason == "" else reason)],
		true, "이 줄은 판정이 아니라 관측이다. 결함 보고는 요약에 적는다")
	# ---- 봇에게 넘겨 전투를 끝내고 거점까지 실제 버튼으로 돌아온다 ----
	var why: String = await _finish_sortie(main)
	ok("전투를 끝내고 실제 버튼으로 거점까지 돌아왔다", why == "" and main.screen == "base",
		"화면 %s%s" % [main.screen, (" · 멈춘 이유: " + why) if why != "" else ""])

func _all_buttons(node: Node) -> Array:
	var out := []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_buttons(c))
	return out

## 봇에게 넘겨 이기고, 보상·3택은 사람과 같은 버튼 경로로 넘긴다. 멈추면 사유를 돌려준다
func _finish_sortie(main: Node) -> String:
	main.view.bot = main.make_bot("skilled")
	var frames := 0
	while main.view.st != null and String(main.view.st.status) == "running" and frames < 60 * 300:
		main.view._process(1.0 / 60.0)
		frames += 1
	if main.view.st == null:
		return "전투 상태가 사라짐"
	if String(main.view.st.status) != "won":
		return "봇이 못 이김(status=%s %.0f초)" % [String(main.view.st.status), float(frames) / 60.0]
	var wait := 0
	while main.screen == "combat" and wait < 60 * 20:
		main.view._process(1.0 / 60.0)
		if wait % 6 == 0:
			await process_frame
		wait += 1
	await process_frame
	for i in 30:
		if main.screen == "base":
			return ""
		if main.choice != null and main.choice.visible:
			var pick := vis_btn(main.choice, "선택")
			if pick == null:
				pick = vis_btn(main.choice, "계속")
			if pick == null:
				pick = vis_btn(main.choice, "건너뛰기")
			if pick == null:
				pick = vis_btn(main.choice, "받지 않음")
			if pick == null:
				print("  · 3택 판이 켜져 있는데 고를 버튼이 없다(화면에 보이는가=%s) — 버튼 %s"
					% [str((main.choice as Control).is_visible_in_tree()), str(_visible_button_texts(main.choice))])
				return "3택 판이 켜져 있는데 고를 버튼이 없다"
			presses.append("[3택] " + pick.text)
			print("  누름 ▶ [3택] " + pick.text)
			pick.pressed.emit()
			await process_frame
			continue
		var s: Node = main.screens.get(main.screen, null)
		if s == null:
			return "알 수 없는 화면 %s" % main.screen
		var nxt := vis_btn(s, "귀환")
		if nxt == null:
			nxt = vis_btn(s, "계속")
		if nxt == null:
			nxt = vis_btn(s, "선택하기")
		if nxt == null:
			return "%s 화면에서 누를 버튼이 없음 — 보이는 버튼 %s" % [main.screen, str(_visible_button_texts(s))]
		presses.append(nxt.text)
		print("  누름 ▶ " + nxt.text)
		nxt.pressed.emit()
		await process_frame
	return "귀환까지 못 감(screen=%s · 보이는 버튼 %s)" % [main.screen, str(_visible_button_texts(scr(main)))]

func _visible_button_texts(node: Node) -> Array:
	var out := []
	if node is Control and not (node as Control).is_visible_in_tree():
		return out
	if node is Button and not (node as Button).disabled:
		out.append((node as Button).text)
	for c in node.get_children():
		out.append_array(_visible_button_texts(c))
	return out

# ---------- [6] 거점 → 교체 ----------
func _step6_swap_equip(main: Node, r: Dictionary, blade: String) -> void:
	print("\n[6] 교체 — 장비 화면에서 무기를 '시간술사의 지팡이'로 갈아 낀다")
	if main.screen != "base":
		ok("교체 단계의 전제(거점에 있다)", false, main.screen)
		return
	ok("거점 '상점' 버튼을 눌렀다", await _press_and_wait(main, main.screens["base"], "상점", "shop"), main.screen)
	var shop: Node = main.screens["shop"]
	ok("'시간술사의 지팡이' 줄의 '구매 (' 를 눌렀다", tap_row(shop, "시간술사의 지팡이", "구매 ("))
	await process_frame
	ok("'가방에 넣기'를 눌렀다", tap(main.screens["shop"], "가방에 넣기"))
	await process_frame
	ok("'장비' 버튼을 눌러 장비 화면이 열린다",
		await _press_and_wait(main, main.screens["shop"], "장비", "equip"), main.screen)
	var eq: Node = main.screens["equip"]
	ok("'시간술사의 지팡이' 줄의 '선택'을 눌렀다", tap_row(eq, "시간술사의 지팡이", "선택"))
	await process_frame
	ok("'지금 장착'을 눌러 무기를 교체했다", tap(main.screens["equip"], "지금 장착"))
	await process_frame
	ok("옛 무기가 가방으로 가고 그 개체의 +1이 그대로다",
		(r.bag as Array).has(blade) and PRun.equip_plus_of(r, blade) == 1
		and PRun.equip_type_of(String(r.equipment.get("weapon", ""))) == "chrono_staff",
		"가방 %s(+%d) · 무기 %s" % [blade, PRun.equip_plus_of(r, blade), str(r.equipment.get("weapon", ""))])
	ok("교체로 사라진 장비의 기술은 더 이상 쓸 수 없다(찰나 가르기)",
		not PGrowth.granted_skill_ids(r).has("eq_flashcut")
		and PGrowth.granted_skill_ids(r).has("eq_icetomb"),
		str(PGrowth.granted_skill_ids(r)))
	# 지금은 감속장이 **Q 칸에** 있으므로 시간술사의 지팡이 효과가 켜져 있어야 한다(창고 검사의 대조군)
	ok("대조군 — 감속장이 Q에 있는 동안에는 지팡이 효과가 켜져 있다",
		PGrowth.equip_inactive_reason_run(r, "chrono_staff") == "",
		"사유 '%s'" % PGrowth.equip_inactive_reason_run(r, "chrono_staff"))

# ---------- [7] 일반 스킬 창고 보관 → 장비 기술 Q 배치 ----------
func _step7_bank_and_place(main: Node, r: Dictionary) -> void:
	print("\n[7] 창고 보관 → 장비 기술 Q 배치 — 기술 편성 화면의 버튼으로")
	ok("'기술 편성' 버튼을 눌러 편성 화면이 열린다",
		await _press_and_wait(main, main.screens["equip"], "기술 편성", "skillbank"), main.screen)
	var sb: Node = main.screens["skillbank"]
	var lv_before := int(r.growth.skills.q.level)
	var var_before := String(r.growth.skills.q.variant) if r.growth.skills.q.variant != null else ""
	ok("'창고로 빼기 (레벨·변형 그대로 보관)'를 눌렀다", tap_row(sb, "Q 칸", "창고로 빼기"))
	await process_frame
	sb = main.screens["skillbank"]
	var be := PGrowth.bank_entry(r.growth, "slowfield")
	ok("감속장이 레벨 %d · 변형 '%s' 그대로 창고로 갔다" % [lv_before, var_before],
		not be.is_empty() and int(be.get("level", 0)) == lv_before
		and String(be.get("variant", "")) == var_before, str(be))
	ok("창고에 넣었다고 Q 칸이 임의의 다른 기술로 채워지지 않는다",
		PGrowth.skill_id_in(r.growth, "q") == "", "Q=%s" % PGrowth.skill_id_in(r.growth, "q"))
	# **창고에만 있는 감속장은 관련 효과를 켜지 않는다**
	ok("창고에만 있는 감속장은 '보유'로 세지 않는다(has_skill 거짓 · in_bank 참)",
		not PGrowth.has_skill(r.growth, "slowfield") and PGrowth.in_bank(r.growth, "slowfield"))
	var why_off := PGrowth.equip_inactive_reason_run(r, "chrono_staff")
	ok("그래서 감속장 조건 장비(시간술사의 지팡이)의 효과가 꺼진다 — 화면이 이유를 말한다",
		why_off.find("감속장이 없어") >= 0, "사유 '%s'" % why_off)
	ok("'Q에 배치'를 눌러 장비 기술(결정 관)을 Q에 넣었다", tap_row(sb, "결정 관", "Q에 배치"))
	await process_frame
	sb = main.screens["skillbank"]
	ok("Q가 장비 기술이 됐다", PGrowth.skill_id_in(r.growth, "q") == "eq_icetomb",
		"Q=%s" % PGrowth.skill_id_in(r.growth, "q"))
	ok("장비 기술에는 성장 표시를 붙이지 않는다('장비 기술 · 성장 없음')",
		txt(sb, "장비 기술 · 성장 없음") >= 1 and txt(sb, "Lv1 / 3") == 0)
	ok("창고에는 여전히 감속장만 있다(장비 기술이 복제되지 않는다)",
		PGrowth.bank_ids(r.growth) == ["slowfield"], str(PGrowth.bank_ids(r.growth)))
	ok("같은 장비 기술을 E에도 넣는 버튼은 잠겨 있다(중복 배치 금지)",
		row_btn(sb, "결정 관", "E에 배치") == null, "잠김 표시 %d" % txt(sb, "Q에 배치됨"))

# ---------- [8] Q/E 교환 → 저장 → 이어하기 ----------
func _step8_swap_qe_save_load(main: Node, r: Dictionary) -> void:
	print("\n[8] Q/E 교환 → '저장 후 종료' → 제목 '계속하기'")
	var sb: Node = main.screens["skillbank"]
	ok("'Q와 E 맞바꾸기'를 눌렀다", tap(sb, "Q와 E 맞바꾸기"))
	await process_frame
	ok("장비 기술이 E로, 낙뢰가 Q로 옮겨졌다",
		PGrowth.skill_id_in(r.growth, "e") == "eq_icetomb" and PGrowth.skill_id_in(r.growth, "q") == "strike",
		"Q=%s E=%s" % [PGrowth.skill_id_in(r.growth, "q"), PGrowth.skill_id_in(r.growth, "e")])
	var lv_e := int(r.growth.skills.q.level)
	ok("옮겨간 일반 기술의 레벨이 따라간다(낙뢰 Lv%d)" % lv_e, lv_e == 2, "Lv%d" % lv_e)
	ok("'거점으로 (Esc)'를 눌러 거점으로 왔다",
		await _press_and_wait(main, main.screens["skillbank"], "거점으로", "base"), main.screen)
	var bank_before := PGrowth.bank_ids(r.growth).duplicate()
	var be_before := PGrowth.bank_entry(r.growth, "slowfield").duplicate()
	ok("거점 '저장 후 종료'를 눌렀다", tap(main.screens["base"], "저장 후 종료"))
	await process_frame
	ok("제목 화면으로 갔고 저장 파일이 생겼다", main.screen == "title" and PSave.exists(), main.screen)
	ok("제목의 '계속하기'를 눌렀다", tap(main.screens["title"], "계속하기"))
	await process_frame
	var r2: Dictionary = main.run
	ok("이어하기 뒤 편성이 그대로다(Q=낙뢰 · E=결정 관)",
		PGrowth.skill_id_in(r2.growth, "q") == "strike" and PGrowth.skill_id_in(r2.growth, "e") == "eq_icetomb",
		"Q=%s E=%s" % [PGrowth.skill_id_in(r2.growth, "q"), PGrowth.skill_id_in(r2.growth, "e")])
	var be_after := PGrowth.bank_entry(r2.growth, "slowfield")
	ok("이어하기 뒤에도 창고의 감속장 레벨·변형이 보존된다 — %s → %s" % [str(be_before), str(be_after)],
		PGrowth.bank_ids(r2.growth) == bank_before
		and int(be_after.get("level", 0)) == int(be_before.get("level", -1))
		and String(be_after.get("variant", "")) == String(be_before.get("variant", "")))
	var bank_eq: Array = []
	for bid in PGrowth.bank_ids(r2.growth):
		if String(bid).begins_with("eq_"):
			bank_eq.append(String(bid))
	ok("저장·이어하기를 지나도 장비 기술이 창고로 복제되지 않는다", bank_eq.is_empty(), str(PGrowth.bank_ids(r2.growth)))

# ---------- [9] 옮겨진 슬롯에서 재시전 ----------
## 사용자 지시 §2: "실제 허용된 편성 변경 경로를 거친 뒤, 기술이 옮겨진 슬롯에서 재시전을 시도해
## 우회가 없는지 확인해라." 여기서 **새 전투에 들어가 E 버튼을 실제로 누른다.**
func _step9_recast_moved_slot(main: Node, r: Dictionary) -> void:
	print("\n[9] 옮겨진 슬롯(E)에서 재시전 — 새 출격 → 전투 화면 **터치 E 버튼**")
	var r2: Dictionary = main.run
	if main.screen != "base":
		main.show("base")
		await process_frame
	r2.hp = float(PBuild.derive(r2).hp_max)
	inject("두 번째 출격 전 체력을 가득 채운다 — 이 단계에서 보는 것은 '옮겨진 슬롯에서 다시 시전되는가'이지 봇의 승패가 아니다")
	var bs: Node = main.screens["base"]
	if not tap(bs, "출격 ("):
		ok("새 전투로 들어갈 '출격 (' 버튼이 있다", false, "오늘 남은 카드·시간 %d" % int(r2.hours))
		return
	await process_frame
	ok("새 전투로 들어갔다", main.screen == "combat", main.screen)
	if main.screen != "combat":
		return
	var st: CombatState = main.view.st
	st.intro = 0.0
	var tc = main.touch
	tc.layout(PLayout.safe_rect(root))
	var q_cd := PSkills.cd_left(st, "q")
	var e_cd := PSkills.cd_left(st, "e")
	ok("**전투 진입 초기화 정책** — 새 전투는 Q·E 재사용이 둘 다 0에서 시작한다(앞 전투의 시계를 이어받지 않는다)",
		is_equal_approx(q_cd, 0.0) and is_equal_approx(e_cd, 0.0), "Q %.2f초 · E %.2f초" % [q_cd, e_cd])
	var ec: Vector2 = tc.button_center("e")
	ok("E 버튼 자리를 누르면 E로 잡힌다", tc.pick_at(ec) == "e", "자리 %s → %s" % [str(ec), tc.pick_at(ec)])
	tc.handle_touch(21, ec, true)
	presses.append("[전투 터치] E")
	print("  누름 ▶ [전투 터치] E")
	tc.handle_touch(21, ec, false)
	for i in 6:
		main.view._process(1.0 / 60.0)
	var fired: bool = not st.eq_act.is_empty() and String(st.eq_act.get("id", "")) == "eq_icetomb"
	ok("옮겨진 E 칸에서 장비 기술(결정 관)이 실제로 발동했다",
		fired and String(st.eq_act.get("slot", "")) == "e",
		"진행 중 %s(칸 %s)" % [String(st.eq_act.get("id", "없음")), String(st.eq_act.get("slot", "-"))])
	# 진행 중에 같은 칸을 다시 눌러도 새로 발동하지 않는다(우회 없음)
	tc.handle_touch(22, ec, true)
	presses.append("[전투 터치] E(진행 중 재입력)")
	tc.handle_touch(22, ec, false)
	for i in 4:
		main.view._process(1.0 / 60.0)
	var e_cd2 := PSkills.cd_left(st, "e")
	ok("**재사용 정책** — 발동을 마치면 그 칸 시계가 찬다. 그동안 다시 눌러도 새로 나가지 않는다",
		st.eq_act.is_empty() and e_cd2 > 0.0, "E 재사용 %.2f초 · 진행 중 %s" % [e_cd2, str(st.eq_act)])
	tc.handle_touch(23, ec, true)
	presses.append("[전투 터치] E(대기 중 재입력)")
	tc.handle_touch(23, ec, false)
	for i in 4:
		main.view._process(1.0 / 60.0)
	ok("재사용 대기 중에는 아무 일도 일어나지 않는다(편성을 옮겨도 시계를 우회할 길이 없다)",
		st.eq_act.is_empty() and PSkills.cd_left(st, "e") > 0.0,
		"E 재사용 %.2f초" % PSkills.cd_left(st, "e"))
	var why: String = await _finish_sortie(main)
	ok("두 번째 전투도 실제 버튼으로 거점까지 이어진다", why == "" and main.screen == "base",
		"화면 %s%s" % [main.screen, (" · 멈춘 이유: " + why) if why != "" else ""])

# ---------- [10] 장비 해제 → 일반 스킬 재배치 ----------
func _step10_unequip_and_restore(main: Node, _r: Dictionary) -> void:
	print("\n[10] 장비 해제 → 일반 스킬 재배치")
	var r2: Dictionary = main.run
	if main.screen != "base":
		main.show("base")
		await process_frame
	ok("거점 '장비' 버튼을 눌렀다",
		await _press_and_wait(main, main.screens["base"], "장비", "equip"), main.screen)
	var eq: Node = main.screens["equip"]
	ok("'결정 관' 줄의 '선택'을 눌렀다", tap_row(eq, "결정 관", "선택"))
	await process_frame
	ok("'해제 (가방으로)'를 눌렀다", tap(main.screens["equip"], "해제 (가방으로)"))
	await process_frame
	ok("벗으면 그 장비 기술을 더 이상 쓸 수 없다",
		not PGrowth.granted_skill_ids(r2).has("eq_icetomb"), str(PGrowth.granted_skill_ids(r2)))
	ok("배치는 조용히 지워지지 않는다(E 칸에 그대로 남아 있다)",
		PGrowth.skill_id_in(r2.growth, "e") == "eq_icetomb")
	var b_off: Dictionary = PBuild.derive(r2)
	ok("전투가 보는 값에서는 그 칸이 비어 있다(벗으면 전투에 나오지 않는다)",
		b_off.skills.get("e", null) == null, str(b_off.skills.get("e", null)))
	ok("'기술 편성' 버튼을 눌렀다",
		await _press_and_wait(main, main.screens["equip"], "기술 편성", "skillbank"), main.screen)
	var sb: Node = main.screens["skillbank"]
	ok("화면이 '지금 사용 불가'라고 말한다(조용히 지우지 않는다)", txt(sb, "지금 사용 불가") >= 1)
	ok("창고의 감속장이 자동으로 들어가지 않았다(임의 선택 금지)",
		PGrowth.in_bank(r2.growth, "slowfield") and PGrowth.skill_id_in(r2.growth, "e") == "eq_icetomb")
	var be := PGrowth.bank_entry(r2.growth, "slowfield").duplicate()
	ok("창고의 '감속장 E에 넣기'를 눌렀다", tap_row(sb, "감속장", "E에 넣기"))
	await process_frame
	var back = r2.growth.skills.get("e", null)
	ok("재배치하면 보관해 둔 레벨·변형이 그대로 복구된다 — 창고 %s → 칸 %s" % [str(be), str(back)],
		back != null and String(back.id) == "slowfield"
		and int(back.level) == int(be.get("level", -1))
		and String(back.variant) == String(be.get("variant", "")),
		str(back))
	ok("다시 배치한 기술은 창고에서 빠진다", not PGrowth.in_bank(r2.growth, "slowfield"),
		str(PGrowth.bank_ids(r2.growth)))
	ok("장비 기술은 끝까지 창고·보상 후보 어디에도 복제되지 않았다",
		not PGrowth.bank_ids(r2.growth).any(func(i): return String(i).begins_with("eq_")),
		str(PGrowth.bank_ids(r2.growth)))

# ---------- [11] 모바일(좁은 화면 · 터치) ----------
func _step11_mobile(main: Node, _r: Dictionary) -> void:
	print("\n[11] 모바일 — 640×360 좁은 화면에서 보이는가·눌리는가·스크롤·닫기")
	root.size = Vector2i(640, 360)
	await process_frame
	await process_frame
	ok("터치 판정이 켜져 있다(PROPHECY_TOUCH=1)", PLayout.is_touch())
	var sb: Node = main.screens["skillbank"]
	main.show("skillbank")
	await process_frame
	sb = main.screens["skillbank"]
	var vis: Rect2 = root.get_visible_rect()
	# 필수 조작: 맞바꾸기 · 창고 넣기 · 닫기
	var must := ["Q와 E 맞바꾸기", "거점으로", "장비"]
	var bad: Array = []
	for m in must:
		var b := vis_btn(sb, String(m))
		if b == null:
			bad.append("%s 없음/잠김" % m)
			continue
		var rect := b.get_global_rect()
		if rect.size.y < 36.0:
			bad.append("%s 높이 %.0f" % [m, rect.size.y])
		if rect.position.x < vis.position.x - 0.5 or rect.end.x > vis.end.x + 0.5:
			bad.append("%s 가로 밖(%s)" % [m, str(rect)])
	ok("좁은 화면에서도 필수 버튼이 보이고 터치 크기를 지킨다", bad.is_empty(), " / ".join(bad))
	ok("설명 글이 함께 보인다(버튼만 남지 않는다)",
		txt(sb, "기술 창고") >= 1 and txt(sb, "재사용") >= 1)
	# 닫기 경로: 키(Esc)에 기대지 않고 버튼으로 나갈 수 있는가
	var back := vis_btn(sb, "거점으로")
	ok("편성 화면의 닫기 경로가 버튼으로 열려 있다(글자에 Esc가 적혀 있어도 버튼 자체가 눌린다)", back != null,
		"" if back == null else back.text)
	ok("'장비' 버튼을 눌러 장비 화면으로 넘어간다(좁은 화면에서도 화면 이동이 눌린다)",
		await _press_and_wait(main, sb, "장비", "equip"), main.screen)
	# 아이콘·스크롤은 목록이 실제로 긴 장비 화면에서 본다
	var eqs: Node = main.screens["equip"]
	var icons := _count_textures(eqs)
	ok("아이콘이 실제로 그려진다 — %d개" % icons, icons >= 1)
	var sc: ScrollContainer = (eqs as PScreen).scroll
	var ts: PTouchScroll = (eqs as PScreen).touch_scroll
	var maxs := ts.max_scroll()
	var moved := 0.0
	if maxs > 1.0:
		ts.stop()
		sc.scroll_vertical = 0
		ts.sync()
		var p := Vector2(160.0, 250.0)
		ts.handle(_touch_ev(0, p, true))
		for i in 8:
			p += Vector2(0.0, -18.0)
			ts.handle(_drag_ev(0, p, Vector2(0.0, -18.0)))
		ts.handle(_touch_ev(0, p, false))
		moved = float(sc.scroll_vertical)
	ok("좁은 화면에서 목록이 넘치고 손가락으로 실제로 밀어 내려진다 — %.0fpx(넘침 %.0f)" % [moved, maxs],
		maxs > 1.0 and moved > 0.0, "넘침이 1px 이하면 스크롤 자체가 필요 없다는 뜻이다")
	var back2 := vis_btn(eqs, "거점으로")
	ok("장비 화면에도 키 없이 나가는 버튼이 있다", back2 != null, "" if back2 == null else back2.text)
	ok("그 버튼을 실제로 눌러 거점으로 나갔다",
		await _press_and_wait(main, eqs, "거점으로", "base"), main.screen)
	# 전투 조작도 좁은 화면 안에 들어오는가
	var tc = main.touch
	tc.layout(PLayout.safe_rect(root))
	var out: Array = []
	for kind in ["dodge", "special", "e"]:
		var c: Vector2 = tc.button_center(String(kind))
		var rad := PTouchControls.button_radius(String(kind))
		if c.x - rad < vis.position.x - 0.5 or c.x + rad > vis.end.x + 0.5 or c.y - rad < vis.position.y - 0.5 or c.y + rad > vis.end.y + 0.5:
			out.append("%s %s(r=%.0f)" % [kind, str(c), rad])
		elif tc.pick_at(c) != String(kind):
			out.append("%s 가운데를 눌러도 안 잡힘(%s)" % [kind, tc.pick_at(c)])
	ok("좁은 화면에서도 회피·Q·E 버튼이 화면 안에 있고 눌린다", out.is_empty(), " / ".join(out))
	root.size = Vector2i(960, 640)
	await process_frame

func _count_textures(node: Node) -> int:
	var n := 0
	if node is Control and not (node as Control).is_visible_in_tree():
		return 0
	if node is TextureRect and (node as TextureRect).texture != null:
		n += 1
	if node is PIconTile:
		n += 1
	for c in node.get_children():
		n += _count_textures(c)
	return n

func _touch_ev(idx: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	return t

func _drag_ev(idx: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	d.relative = rel
	return d

## 버튼을 누르고 화면이 실제로 바뀔 때까지 기다린다
func _press_and_wait(main: Node, node: Node, part: String, want_screen: String) -> bool:
	if not tap(node, part):
		return false
	await process_frame
	await process_frame
	return main.screen == want_screen

func _finish() -> void:
	var pass_n := 0
	for row in results:
		if bool(row[0]):
			pass_n += 1
	print("\n---- 실제로 누른 버튼(%d개) ----" % presses.size())
	for i in presses.size():
		print("  %2d. %s" % [i + 1, String(presses[i])])
	print("---- 규칙 계층 주입(%d곳) ----" % injections.size())
	for x in injections:
		print("  · " + String(x))
	print("\n%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
