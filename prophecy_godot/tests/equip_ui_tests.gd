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
	var other := ""
	for id in PRun.stock(r).equipment:
		var tid := String(id)
		if String(PCatalog.equipment_def(tid).slot) == slot0 and not PRun.owns_equip_type(r, tid):
			other = tid
	if other == "":
		ok("§10 ③ 같은 부위의 다른 장비가 오늘 재고에 없어 화면으로 확인하지 못했다", false, "slot %s" % slot0)
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
