class_name PEquipScreen
extends PScreen
## 장비(HTML shop 'bag' 탭). 2026-09-09 재구성 — 목록에는 무엇이 있는지만 두고,
## 장착·해제·상세·판매는 **장비 하나를 고른 창**에 모은다(목록마다 판매 버튼과 전후 수치를 길게 반복하지 않는다).
## 교체하면 원래 장비가 가방으로 간다는 것은 그 창에 짧게 적는다. 판매는 확인 창(PScreen.open_sell_confirm)을 거친다.
## 비교 수치(최대 체력·이동 등)는 복제한 run에 실제로 장착·해제해 PBuild.derive로 계산한다(규칙은 건드리지 않는다).

func refresh() -> void:
	clear_all()
	close_confirm()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	top.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]거점에서만 무료 교체[/color]" % PGlossaryTip.term("equipment", "장비"), 22))
	var b := PBuild.derive(r)
	var cols := two_cols(0.5)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	var cur := PUi.card("장착 중 [color=#9ea8b8]최대 체력 %d · 이동 ×%s · 시작 보호막 %d[/color]" % [int(float(b.hp_max)), PUi.fmt(float(b.speed_mult)), int(float(b.shield))])
	var cbox: VBoxContainer = cur.box
	cbox.add_child(PUi.equip_icon_row(r, 40.0, Callable(self, "_pick_slot")))
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var id = r.equipment.get(slot, null)
		var row := PUi.hbox(8)
		row.add_child(PUi.rich("[color=#9ea8b8]%s[/color]  %s" % [PUi.slot_name(slot), (PUi.equip_line(String(id)) if id != null else "[color=#6a7078]비어 있음[/color]")], 15))
		if id != null:
			var eid := String(id)
			var pick := PUi.button("선택", func(): _open_item(eid), true, 13)
			pick.custom_minimum_size = Vector2(0, PLayout.button_min_height())
			row.add_child(pick)
		cbox.add_child(row)
	left.add_child(cur.panel)
	var bag := PUi.card("%s [color=#9ea8b8]%d개 · 고르면 장착·해제·상세·판매를 한 곳에서 합니다[/color]" % [PGlossaryTip.term("bag", "가방"), (r.bag as Array).size()])
	var bbox: VBoxContainer = bag.box
	if (r.bag as Array).is_empty():
		bbox.add_child(PUi.rich("[color=#6a7078]가방 비어 있음[/color]", 14))
	for id in r.bag:
		var bid := String(id)
		var d: Dictionary = PCatalog.equipment_def(bid)
		var row := PUi.hbox(8)
		row.add_child(PUi.icon_of("equip:" + bid, 30.0, "", "", 0.0, 0))
		row.add_child(PUi.rich("%s [color=#9ea8b8](%s)[/color]" % [PUi.equip_line(bid), PUi.slot_name(String(d.slot))], 15))
		var pick := PUi.button("선택", func(): _open_item(bid), true, 13)
		pick.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		row.add_child(pick)
		bbox.add_child(row)
	right.add_child(bag.panel)
	# 출격 준비물은 장비 칸을 쓰지 않는다(전투 1회용). 여기서는 무엇이 걸려 있는지만 보이고 고르는 것은 거점에서 한다
	var prep := PUi.card("출격 준비물 [color=#9ea8b8]장비 칸과 별개 · 다음 전투 1회[/color]", PUi.CARD, 15)
	var pbox: VBoxContainer = prep.box
	var armed := PConsumables.armed(r)
	if armed == "":
		pbox.add_child(PUi.rich("[color=#6a7078]장착 없음[/color] [color=#9ea8b8]· 가방 %d개 · 거점에서 1개를 고릅니다[/color]" % PConsumables.prep_count(r), 14))
	else:
		pbox.add_child(PUi.rich("[b]%s[/b] — %s" % [PConsumables.name_of(armed), PGlossaryTip.esc(PConsumables.effect_line(armed))], 14))
	if PConsumables.potion_count(r) > 0:
		pbox.add_child(PUi.rich("[color=#9ea8b8]회복약 %d개 (거점에서 사용, 체력 +%d)[/color]" % [PConsumables.potion_count(r), int(float(PConsumables.potion_def().heal))], 13))
	right.add_child(prep.panel)
	right.add_child(PUi.build_panel(r))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	bottom.add_child(PUi.button("상점", func(): main.show("shop"), true, 14))
	bottom.add_child(PUi.button("대장간", func(): main.show("forge"), true, 14))
	default_button = back

func _pick_slot(_kind: String, slot: String) -> void:
	var id = run().equipment.get(slot, null)
	if id == null:
		return
	_open_item(String(id))

## 장비 하나를 고른 창: 장착(또는 해제) · 상세 · 판매를 여기에 모은다. 상세는 눌러야 열린다
func _open_item(id: String, detail: bool = false) -> void:
	var r := run()
	var d: Dictionary = PCatalog.equipment_def(id)
	var slot := String(d.slot)
	var worn: bool = r.equipment.get(slot, null) != null and String(r.equipment[slot]) == id
	var acts := []
	if worn:
		acts.append({ "text": "해제 (가방으로)", "cb": func(): main.unequip_item(slot) })
	else:
		acts.append({ "text": "지금 장착", "cb": func(): main.equip_item(id) })
	if not detail:
		acts.append({ "text": "상세 설명", "cb": func(): _open_item(id, true) })
	acts.append({ "text": "판매 (+%d금)" % int(PRun.sell_quote(main.run, id).gold), "cb": func(): open_sell_confirm(id) })
	open_confirm(String(d.name), _item_body.bind(r, id, worn, detail), acts, "닫기 (Esc)")

func _item_body(box: VBoxContainer, r: Dictionary, id: String, worn: bool, detail: bool) -> void:
	var d: Dictionary = PCatalog.equipment_def(id)
	var slot := String(d.slot)
	PUi.kv(box, "부위", "[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PUi.slot_name(slot), "장착 중" if worn else "가방"], 15)
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 14))
	var dup: Dictionary = r.duplicate(true)
	if worn:
		PRun.unequip_item(dup, slot)
		PUi.kv(box, "해제하면", PUi.diff_text(PBuild.derive(r), PBuild.derive(dup)), 13)
	else:
		PRun.equip_item(dup, id)
		PUi.kv(box, "장착하면", PUi.diff_text(PBuild.derive(r), PBuild.derive(dup)), 13)
		var cur = r.equipment.get(slot, null)
		if cur != null:
			box.add_child(PUi.rich("[color=#9ea8b8]지금 낀 %s은(는) 가방으로 갑니다.[/color]" % PGlossaryTip.esc(PRun.equip_name(String(cur))), 13))
	if not detail:
		return
	box.add_child(PUi.rich("[b]자세한 효과[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 13))
	box.add_child(PUi.rich("[b]되팔 때[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]%d금 · 장착 중이면 해제한 뒤 팝니다. 판 장비는 되사올 수 없습니다.[/color]" % int(PRun.sell_quote(main.run, id).gold), 13))
	box.add_child(PUi.rich("[b]교체 규칙[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]같은 부위에는 하나만 낍니다. 새로 끼면 원래 장비는 가방으로 가고, 거점에서는 몇 번을 바꿔도 값이 들지 않습니다.[/color]", 13))
