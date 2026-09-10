extends SceneTree
## 장비 개체·장비 강화·상점 4칸·대장간 세 대상 구분의 **실제 화면 검사**(§8·§10 이 갈래 몫).
## 규칙 계층은 meta_tests가 본다. 여기서는 **화면에 있는 진짜 버튼을 눌러서** 결과를 확인한다.
## godot --path prophecy_godot -s tests/equip_ui_tests.gd
## PROPHECY_SHOT=<폴더>를 주면 각 단계의 PNG도 남긴다(창 모드에서만 — 헤드리스는 그리지 않는다).

var results := []
var shot_dir := ""

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _count_text(node: Node, needle: String) -> int:
	var n := 0
	if node is RichTextLabel and (node as RichTextLabel).text.find(needle) >= 0:
		n += 1
	if node is Button and (node as Button).text.find(needle) >= 0:
		n += 1
	if node is Label and (node as Label).text.find(needle) >= 0:
		n += 1
	for c in node.get_children():
		n += _count_text(c, needle)
	return n

## 화면에 실제로 보이고 눌리는 버튼만 찾는다(숨은 노드를 눌러 '되는 것처럼' 만들지 않기 위해서다)
func _button(node: Node, needle: String, only_enabled: bool = true) -> Button:
	if node is Button:
		var b := node as Button
		if b.text.find(needle) >= 0 and b.is_visible_in_tree() and (not only_enabled or not b.disabled):
			return b
	for c in node.get_children():
		var r := _button(c, needle, only_enabled)
		if r != null:
			return r
	return null

## 한 줄(HBox) 안에서 **그 항목의 버튼**을 찾는다. 같은 글자의 버튼이 여러 줄에 있을 때
## 엉뚱한 줄을 눌러 '되는 것처럼' 만들지 않기 위해서다(가장 안쪽 = 가장 작은 줄을 고른다)
func _row_button(node: Node, row_text: String, btn_text: String) -> Button:
	var best: Button = null
	var best_n := 1 << 30
	for hb in _all_hbox(node):
		if _count_text(hb, row_text) == 0:
			continue
		var b := _button(hb, btn_text)
		if b == null:
			continue
		var n := _node_count(hb)
		if n < best_n:
			best_n = n
			best = b
	return best

func _all_hbox(node: Node) -> Array:
	var out := []
	if node is HBoxContainer:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_hbox(c))
	return out

func _node_count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _node_count(c)
	return n

## 화면에 실제로 그려진 글자를 그대로 로그에 남긴다(헤드리스에서는 PNG를 못 남기므로 이것이 '캡처'다)
func _dump(node: Node, title: String) -> void:
	print("---- 화면 캡처: %s ----" % title)
	_dump_walk(node, 0)
	print("---- 캡처 끝: %s ----" % title)

func _dump_walk(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is RichTextLabel and String((node as RichTextLabel).text).strip_edges() != "":
		print(pad, "· ", String((node as RichTextLabel).text))
	elif node is Label and String((node as Label).text).strip_edges() != "":
		print(pad, "· ", String((node as Label).text))
	elif node is Button:
		print(pad, "[버튼] ", String((node as Button).text), (" (잠김)" if (node as Button).disabled else ""))
	for c in node.get_children():
		_dump_walk(c, depth + 1)

func _shot(main: Node, name: String) -> void:
	if shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(shot_dir.path_join(name + ".png"))
	print("SHOT ", name, " ", img.get_width(), "x", img.get_height())

func _init() -> void:
	shot_dir = OS.get_environment("PROPHECY_SHOT")
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
	_run.call_deferred()

func _run() -> void:
	PProfile.use_path("user://prophecy_profile_equip_ui_v1.json")
	PProfile.clear()
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.profile = PProfile.load("legacy") # 해금 제한 없이 재고·제작법이 열린 프로필
	main.use_bot = false
	main.start_run("sword")
	await process_frame
	var r: Dictionary = main.run
	r.gold = 4000
	r.bossesDone = ["b1", "b2"] # 관문 2돌파 = 장비 강화 +1·+2가 모두 열린 상태
	PRun.refresh_stock(r)

	# ---------- 상점: 진열 4칸 ----------
	main.show("shop")
	await process_frame
	var shop: Node = main.screens["shop"]
	ok("상점 재고에 장비가 4개 진열된다(§8: 2 → 4)", (PRun.stock(r).equipment as Array).size() == 4, str(PRun.stock(r).equipment))
	ok("상점 카드 4장이 '구매 (' 버튼과 함께 그려진다", _count_text(shop, "구매 (") >= 4, "구매 버튼 %d" % _count_text(shop, "구매 ("))
	ok("상점 카드가 기본 능력치와 고유 효과를 갈라 적는다(§8)", _count_text(shop, "기본 능력치") >= 4 and _count_text(shop, "고유 효과") >= 4)
	ok("상점 카드가 요구 조건과 현재 장비를 따로 적는다(§8)", _count_text(shop, "요구 조건") >= 1 and _count_text(shop, "지금 ") >= 1)
	_shot(main, "s1_shop_4slots")

	# ---------- 실제 버튼으로 구매 → 장착 ----------
	var gold0 := int(r.gold)
	var buy := _button(shop, "구매 (")
	ok("상점에 누를 수 있는 구매 버튼이 있다", buy != null)
	if buy == null:
		_finish()
		return
	buy.pressed.emit()
	await process_frame
	shop = main.screens["shop"]
	ok("구매를 누르면 확인 창이 뜬다(아직 금화가 빠지지 않는다)", _count_text(shop, "살까요?") == 1 and int(r.gold) == gold0)
	var cancel := _button(shop, "취소")
	if cancel != null:
		cancel.pressed.emit()
		await process_frame
	ok("구매를 취소하면 금화·가방이 그대로다(§10 취소 확인)", int(r.gold) == gold0 and (r.bag as Array).is_empty())
	shop = main.screens["shop"]
	_button(shop, "구매 (").pressed.emit()
	await process_frame
	shop = main.screens["shop"]
	_button(shop, "지금 장착").pressed.emit()
	await process_frame
	var worn := String(r.equipment.get("weapon", "")) if r.equipment.get("weapon", null) != null else (String(r.equipment.get("armor", "")) if r.equipment.get("armor", null) != null else String(r.equipment.get("shield", "")))
	ok("'지금 장착'을 눌러 실제로 장착되고 개체 id가 붙는다", worn != "" and worn.find("#") > 0 and int(r.gold) < gold0, "%s gold %d" % [worn, int(r.gold)])
	var slot0 := String(PCatalog.equipment_def(PRun.equip_type_of(worn)).slot)

	# ---------- 대장간: 세 대상 구분 + 장비 강화 버튼 ----------
	main.show("forge")
	await process_frame
	var forge: Node = main.screens["forge"]
	ok("대장간이 세 대상을 이름으로 갈라 적는다(§8): 장비 강화 · 장비 제작 · 자동기술 강화·개조",
		_count_text(forge, "장비 강화") >= 2 and _count_text(forge, "장비 제작") >= 1 and _count_text(forge, "자동기술 강화·개조") >= 1,
		"장비강화 %d · 장비제작 %d · 자동기술 %d" % [_count_text(forge, "장비 강화"), _count_text(forge, "장비 제작"), _count_text(forge, "자동기술 강화·개조")])
	ok("장비 강화 칸이 '자동기술 강화가 아니다'라고 못 박는다", _count_text(forge, "장비 강화가 아닙니다") >= 1)
	_shot(main, "s2_forge_three")
	var g1 := int(r.gold)
	var up := _button(forge, "+1로 강화")
	ok("대장간에 누를 수 있는 '+1로 강화' 버튼이 있다", up != null)
	if up != null:
		up.pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		ok("강화도 확인 창을 거친다(누르기만 하면 금화가 빠지지 않는다)", _count_text(forge, "강화할까요?") == 1 and int(r.gold) == g1 and PRun.equip_plus_of(r, worn) == 0)
		_shot(main, "s3_forge_upgrade_confirm")
		var c2 := _button(forge, "취소")
		if c2 != null:
			c2.pressed.emit()
			await process_frame
		ok("강화를 취소하면 금화·단계가 그대로다(§10 취소 확인)", int(r.gold) == g1 and PRun.equip_plus_of(r, worn) == 0)
		forge = main.screens["forge"]
		_button(forge, "+1로 강화").pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		_button(forge, "강화한다 (").pressed.emit()
		await process_frame
		ok("확정을 누르면 그 개체가 +1이 되고 금화가 표대로 빠진다",
			PRun.equip_plus_of(r, worn) == 1 and int(r.gold) == g1 - 70, "plus %d gold %d" % [PRun.equip_plus_of(r, worn), int(r.gold)])
		forge = main.screens["forge"]
		ok("강화 뒤 대장간 목록이 그 장비를 +1로 보여 준다", _count_text(forge, "[b]+1[/b]") >= 1 or _count_text(forge, "지금 +1") >= 1)
		_shot(main, "s4_forge_after_upgrade")

	# ---------- 장비 화면: 해제 → 재착용해도 강화 유지 ----------
	main.show("equip")
	await process_frame
	var eq: Node = main.screens["equip"]
	ok("장비 화면이 강화 단계를 이름 옆에 보여 준다", _count_text(eq, "[b]+1[/b]") >= 1)
	var pick := _button(eq, "선택")
	ok("장비 화면에 '선택' 버튼이 있다", pick != null)
	if pick != null:
		pick.pressed.emit()
		await process_frame
		eq = main.screens["equip"]
		var un := _button(eq, "해제 (가방으로)")
		ok("고른 장비 창에 해제 버튼이 있다", un != null)
		if un != null:
			un.pressed.emit()
			await process_frame
			ok("해제해도 가방 안 그 개체의 강화가 그대로다(§10 ②)",
				(r.bag as Array).has(worn) and PRun.equip_plus_of(r, worn) == 1 and r.equipment.get(slot0, null) == null)
			eq = main.screens["equip"]
			_button(eq, "선택").pressed.emit()
			await process_frame
			eq = main.screens["equip"]
			var re_eq := _button(eq, "지금 장착")
			if re_eq != null:
				re_eq.pressed.emit()
				await process_frame
				ok("재착용하면 같은 개체·같은 강화(+1)로 돌아온다(§10 ②)",
					String(r.equipment.get(slot0, "")) == worn and PRun.equip_plus_of(r, worn) == 1)
			_shot(main, "s5_equip_plus_kept")

	# ---------- 다른 장비를 사서 껴도 강화가 따라가지 않는다(§10 ③) ----------
	main.show("shop")
	await process_frame
	shop = main.screens["shop"]
	# 오늘 재고에 같은 부위 장비가 둘 있어야만 확인되던 검사라 **날마다 흔들렸다**(시드를 안 고정한다).
	# 확인하려는 것은 '새 장비를 껴도 옛 장비의 강화가 따라가지 않는다'이지 재고 추첨이 아니다.
	# 그래서 재고에 없으면 **자료에서 같은 부위 장비를 골라 그날 재고에 넣는다**(상점 화면 경로는 그대로 쓴다)
	var other := ""
	for id in PRun.stock(r).equipment:
		var tid := String(id)
		if String(PCatalog.equipment_def(tid).slot) == slot0 and not PRun.owns_equip_type(r, tid):
			other = tid
	if other == "":
		for id in PCatalog.equipment():
			var tid2 := String(id)
			if String(PCatalog.equipment_def(tid2).slot) == slot0 and not PRun.owns_equip_type(r, tid2):
				other = tid2
				(PRun.stock(r).equipment as Array).append(tid2)
				main.show("shop")
				await process_frame
				shop = main.screens["shop"]
				break
	if other == "":
		ok("§10 ③ 자료에 같은 부위의 다른 장비가 아예 없다(이 검사의 전제가 깨졌다)", false, "slot %s" % slot0)
	else:
		var before_plus := PRun.equip_plus_of(r, worn)
		main.buy_equipment(other, true, "stock")
		await process_frame
		var now := String(r.equipment[slot0])
		ok("새 장비를 껴도 이전 장비의 강화가 따라오지 않는다(§10 ③)",
			now != worn and PRun.equip_type_of(now) == other and PRun.equip_plus_of(r, now) == 0 and PRun.equip_plus_of(r, worn) == before_plus and (r.bag as Array).has(worn),
			"새 %s(+%d) / 옛 %s(+%d)" % [now, PRun.equip_plus_of(r, now), worn, PRun.equip_plus_of(r, worn)])

	# ---------- 저장/이어하기 뒤 보존(§10 ⑦) ----------
	main.save_run()
	var loaded := PSave.load()
	ok("저장·이어하기 뒤에도 장비 개체와 강화가 그대로다(§10 ⑦)",
		PRun.equip_plus_of(loaded, worn) == PRun.equip_plus_of(r, worn) and JSON.stringify(PSave.normalize(r)) == JSON.stringify(loaded))

	# ---------- 판매 뒤 가방에 남지 않는다 ----------
	main.show("shop")
	await process_frame
	shop = main.screens["shop"]
	var n_before := PRun.equip_instances(r).size()
	var gold_s := int(r.gold)
	var sell := _button(shop, "판매 +")
	ok("상점 판매 목록에 판매 버튼이 있다", sell != null)
	if sell != null:
		sell.pressed.emit()
		await process_frame
		shop = main.screens["shop"]
		ok("판매도 확인 창을 거친다(누르기만 하면 아무것도 팔리지 않는다)",
			_count_text(shop, "판매할까요?") == 1 and PRun.equip_instances(r).size() == n_before and int(r.gold) == gold_s)
		var yes := _button(shop, "판매한다")
		ok("확인 창에 확정 버튼이 있다", yes != null, str(yes))
		if yes != null:
			yes.pressed.emit()
			await process_frame
			# 개체가 정확히 하나만 사라지고, 같은 개체 id가 가방·슬롯 어디에도 남지 않는다
			var after := PRun.equip_instances(r)
			var dup_left := 0
			var uids := {}
			for inst in after:
				if uids.has(String((inst as Dictionary).uid)):
					dup_left += 1
				uids[String((inst as Dictionary).uid)] = true
			ok("판매 확정 뒤 개체가 정확히 하나 사라지고 같은 장비가 가방에 남지 않는다",
				after.size() == n_before - 1 and dup_left == 0 and int(r.gold) > gold_s,
				"개체 %d → %d, 금화 %d → %d" % [n_before, after.size(), gold_s, int(r.gold)])
	# ---------- 제작 강화 계승(2026-09-10 사용자 확정)을 **실제 버튼으로** 확인한다 ----------
	# 재료·제작법은 회차에 주입한다(상점이 같은 종류를 두 번 팔지 않아 정상 경로로는 만들 수 없는 상태다).
	# 그 뒤의 강화·미리보기·취소·확정은 **전부 화면의 진짜 버튼**을 눌러서 한다.
	r.gold = 3000
	r.mats.iron = 2
	r.mats.pelt = 3
	r.mats.spore = 2
	# 앞선 검사가 무엇을 사 두었는지에 따라 '같은 종류 몇 개'가 흔들리므로 **여기서 장비 상태를 비운다**
	# (앞 검사들의 판정은 이미 끝났다. 이 아래는 제작 계승만 본다)
	r.bag = []
	for sl in (r.equipment as Dictionary).keys():
		r.equipment[sl] = null
	if r.has("unlocks"):
		r.unlocks.recipes = ["moon_armor", "renewal_coat", "reprieve_coat"]
	# ① 재료 하나(수호자의 갑옷)만 가방에 둔다 → 이 줄의 '+1로 강화'가 유일해진다
	var gu1 := PRun.equip_new_uid(r, "guardian_armor")
	(r.bag as Array).append(gu1)
	main.show("forge")
	await process_frame
	forge = main.screens["forge"]
	var up_g := _row_button(forge, "수호자의 갑옷", "+1로 강화")
	ok("재료 장비 줄에 '+1로 강화' 버튼이 있다", up_g != null)
	if up_g != null:
		up_g.pressed.emit()
		await process_frame
		_button(main.screens["forge"], "강화한다 (").pressed.emit()
		await process_frame
		ok("재료 장비를 실제 버튼으로 +1까지 강화했다", PRun.equip_plus_of(r, gu1) == 1, "plus %d" % PRun.equip_plus_of(r, gu1))
	# ② 미리보기 버튼을 눌러 확인창을 연다 — 소비 개체·단계·결과·비용이 실제로 보이는지
	forge = main.screens["forge"]
	var pv_btn := _row_button(forge, "월광 갑옷", "미리보기")
	ok("월광 갑옷 줄에 '미리보기' 버튼이 있다", pv_btn != null)
	if pv_btn != null:
		pv_btn.pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		_dump(forge, "제작 확인창(재료 +1 → 결과 +1 계승)")
		_shot(main, "s6_craft_inherit_confirm")
		ok("확인창에 **소비할 장비 개체와 그 강화 단계**가 보인다",
			_count_text(forge, "소비할 장비") >= 1 and _count_text(forge, "수호자의 갑옷") >= 1 and _count_text(forge, gu1) >= 1 and _count_text(forge, "[b]+1[/b]") >= 1,
			"소비줄 %d · 개체 %d" % [_count_text(forge, "소비할 장비"), _count_text(forge, gu1)])
		ok("확인창에 **결과 장비와 계승 단계**가 보인다",
			_count_text(forge, "재료의 강화를 그대로 계승") >= 1 and _count_text(forge, "물려받습니다") >= 1)
		ok("확인창에 **재료·금화 비용**과 '강화 비용을 다시 받지 않는다'가 보인다",
			_count_text(forge, "재료·수수료") >= 1 and _count_text(forge, "금화 80") >= 1 and _count_text(forge, "다시 받지 않습니다") >= 1)
		# 취소 = 아무것도 소비하지 않는다
		var gold_c := int(r.gold)
		_button(forge, "취소 (Esc)").pressed.emit()
		await process_frame
		ok("제작을 취소하면 금화·재료·강화 상태가 그대로다",
			int(r.gold) == gold_c and int(r.mats.iron) == 2 and (r.bag as Array).has(gu1) and PRun.equip_plus_of(r, gu1) == 1)
		# 확정 → 결과가 같은 단계로 나오고, 강화 비용을 다시 받지 않는다(수수료만 빠진다)
		forge = main.screens["forge"]
		_row_button(forge, "월광 갑옷", "미리보기").pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		var gold_k := int(r.gold)
		_button(forge, "확정 후 보관").pressed.emit()
		await process_frame
		var moon_u := ""
		for id in r.bag:
			if PRun.equip_type_of(String(id)) == "moon_armor":
				moon_u = String(id)
		ok("확정: 완성품이 재료와 **같은 +1**로 나오고, 빠진 금화는 수수료 80뿐이다(강화 비용 재청구 없음)",
			moon_u != "" and PRun.equip_plus_of(r, moon_u) == 1 and gold_k - int(r.gold) == 80 and not (r.bag as Array).has(gu1),
			"결과 %s(+%d) · 금화 %d → %d" % [moon_u, PRun.equip_plus_of(r, moon_u), gold_k, int(r.gold)])
		_shot(main, "s7_craft_inherit_done")
	# ③ 재료 +2 → 결과 +2 (강화도 실제 버튼으로 두 번)
	var ex1 := PRun.equip_new_uid(r, "expedition_armor")
	(r.bag as Array).append(ex1)
	main.show("forge")
	await process_frame
	forge = main.screens["forge"]
	var up_e1 := _row_button(forge, "원정대의 갑옷", "+1로 강화")
	if up_e1 != null:
		up_e1.pressed.emit()
		await process_frame
		_button(main.screens["forge"], "강화한다 (").pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		var up_e2 := _row_button(forge, "원정대의 갑옷", "+2로 강화")
		if up_e2 != null:
			up_e2.pressed.emit()
			await process_frame
			_button(main.screens["forge"], "강화한다 (").pressed.emit()
			await process_frame
	ok("재료 장비를 실제 버튼으로 +2까지 올렸다", PRun.equip_plus_of(r, ex1) == 2, "plus %d" % PRun.equip_plus_of(r, ex1))
	forge = main.screens["forge"]
	var pv2 := _row_button(forge, "재생의 여행복", "미리보기")
	ok("재생의 여행복 줄에 '미리보기' 버튼이 있다", pv2 != null)
	if pv2 != null:
		pv2.pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		_dump(forge, "제작 확인창(재료 +2 → 결과 +2 계승)")
		var gold_k2 := int(r.gold)
		_button(forge, "확정 후 보관").pressed.emit()
		await process_frame
		var rn_u := ""
		for id in r.bag:
			if PRun.equip_type_of(String(id)) == "renewal_coat":
				rn_u = String(id)
		ok("재료 +2로 제작하면 결과도 +2다(수수료 80만 빠진다)",
			rn_u != "" and PRun.equip_plus_of(r, rn_u) == 2 and gold_k2 - int(r.gold) == 80,
			"결과 %s(+%d) · 금화 %d → %d" % [rn_u, PRun.equip_plus_of(r, rn_u), gold_k2, int(r.gold)])
	# ④ 같은 종류 2개 중 하나만 재료로 쓰면 나머지와 그 강화가 그대로다
	var v1 := PRun.equip_new_uid(r, "vitality_coat")
	var v2 := PRun.equip_new_uid(r, "vitality_coat")
	(r.bag as Array).append(v1)
	(r.bag as Array).append(v2)
	PRun.upgrade_equip(r, v2) # 한쪽만 +2로(줄이 같은 이름이라 버튼으로는 구분되지 않는다 — 여기만 규칙 계층 주입)
	PRun.upgrade_equip(r, v2)
	main.show("forge")
	await process_frame
	forge = main.screens["forge"]
	var pv3 := _row_button(forge, "유예의 외투", "미리보기")
	ok("유예의 외투 줄에 '미리보기' 버튼이 있다", pv3 != null)
	if pv3 != null:
		pv3.pressed.emit()
		await process_frame
		forge = main.screens["forge"]
		_dump(forge, "제작 확인창(같은 종류 2개 중 소비 대상 구분)")
		ok("확인창이 **어느 개체를 태우고 무엇이 남는지** 구분해 적는다",
			_count_text(forge, "같은 종류 2개 중") >= 1 and _count_text(forge, v1) >= 1 and _count_text(forge, v2) >= 1,
			"안내 %d · 소비 %s · 잔여 %s" % [_count_text(forge, "같은 종류 2개 중"), v1, v2])
		_button(forge, "확정 후 보관").pressed.emit()
		await process_frame
		ok("재료로 쓴 개체만 사라지고 나머지 개체와 그 강화(+2)는 그대로다",
			not (r.bag as Array).has(v1) and (r.bag as Array).has(v2) and PRun.equip_plus_of(r, v2) == 2,
			"남은 %s(+%d)" % [v2, PRun.equip_plus_of(r, v2)])
	PSave.clear()
	PProfile.clear()
	_finish()

func _finish() -> void:
	var pass_n := 0
	for x in results:
		if x[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
