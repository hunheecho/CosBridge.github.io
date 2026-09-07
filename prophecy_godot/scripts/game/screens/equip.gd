class_name PEquipScreen
extends PScreen
## 장비(HTML shop 'bag' 탭): 3슬롯 현재 장비 · 가방 · 장착/해제/판매. 비교 수치(최대 체력·이동)는 복제한 run에 장착해 PBuild.derive로 계산한다.

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	top.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]교체는 거점에서 무료. 출격 중에는 바꿀 수 없습니다. 최대 체력이 줄면 현재 체력도 줄고, 늘어도 회복되지 않습니다.[/color]" % PGlossaryTip.term("equipment", "장비"), 20))
	var b := PBuild.derive(r)
	var cols := two_cols(0.5)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	var cur := PUi.card("장착 중 [color=#9ea8b8]최대 체력 %d · 이동 ×%s · 시작 보호막 %d[/color]" % [int(float(b.hp_max)), PUi.fmt(float(b.speed_mult)), int(float(b.shield))])
	var cbox: VBoxContainer = cur.box
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var id = r.equipment.get(slot, null)
		var row := PUi.hbox(8)
		if id == null:
			row.add_child(PUi.rich("[color=#9ea8b8]%s[/color]  [color=#6a7078]비어 있음[/color]" % PUi.slot_name(slot), 13))
		else:
			var eid := String(id)
			var v := PUi.vbox(2)
			v.add_child(PUi.rich("[color=#9ea8b8]%s[/color]  %s" % [PUi.slot_name(slot), PUi.equip_line(eid)], 13))
			v.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(PCatalog.equipment()[eid].desc)), 11))
			v.add_child(PUi.rich("[color=#9ea8b8]해제하면: %s[/color]" % _compare_unequip(r, slot), 11))
			row.add_child(v)
			var bcol := PUi.vbox(4)
			bcol.size_flags_horizontal = Control.SIZE_SHRINK_END
			bcol.add_child(PUi.button("해제", func(): main.unequip_item(slot), true, 12))
			bcol.add_child(PUi.button("판매 +%d" % PRun.sell_price(eid), func(): main.sell_equipment(eid), true, 12))
			row.add_child(bcol)
		cbox.add_child(row)
	left.add_child(cur.panel)
	var bag := PUi.card("%s [color=#9ea8b8]%d개[/color]" % [PGlossaryTip.term("bag", "가방"), (r.bag as Array).size()])
	var bbox: VBoxContainer = bag.box
	if (r.bag as Array).is_empty():
		bbox.add_child(PUi.rich("[color=#6a7078]가방 비어 있음 (상점에서 구매 후 보관하면 여기에 옵니다)[/color]", 12))
	for id in r.bag:
		var bid := String(id)
		var d: Dictionary = PCatalog.equipment()[bid]
		var row := PUi.hbox(8)
		var v := PUi.vbox(2)
		v.add_child(PUi.rich("%s [color=#9ea8b8](%s)[/color]" % [PUi.equip_line(bid), PUi.slot_name(String(d.slot))], 13))
		v.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 11))
		v.add_child(PUi.rich("[color=#9ea8b8]장착하면: %s[/color]" % _compare_equip(r, bid), 11))
		row.add_child(v)
		var bcol := PUi.vbox(4)
		bcol.size_flags_horizontal = Control.SIZE_SHRINK_END
		bcol.add_child(PUi.button("장착", func(): main.equip_item(bid), true, 12))
		bcol.add_child(PUi.button("판매 +%d" % PRun.sell_price(bid), func(): main.sell_equipment(bid), true, 12))
		row.add_child(bcol)
		bbox.add_child(row)
	right.add_child(bag.panel)
	right.add_child(PUi.build_panel(r))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	bottom.add_child(PUi.button("상점", func(): main.show("shop"), true, 14))
	bottom.add_child(PUi.button("대장간", func(): main.show("forge"), true, 14))
	default_button = back

## 복제 run에 실제로 장착/해제해 파생 수치 전후를 비교한다(장비 효과 계산은 PBuild만)
static func _diff_text(before: Dictionary, after: Dictionary) -> String:
	var parts := []
	parts.append("최대 체력 %d → %d" % [int(float(before.hp_max)), int(float(after.hp_max))])
	parts.append("이동 ×%s → ×%s" % [PUi.fmt(float(before.speed_mult)), PUi.fmt(float(after.speed_mult))])
	if float(before.shield) != float(after.shield):
		parts.append("시작 보호막 %d → %d" % [int(float(before.shield)), int(float(after.shield))])
	if float(before.range_mult) != float(after.range_mult):
		parts.append("사거리 ×%s → ×%s" % [PUi.fmt(float(before.range_mult)), PUi.fmt(float(after.range_mult))])
	var cur_slot_swap := ""
	return " · ".join(parts) + cur_slot_swap

func _compare_equip(r: Dictionary, id: String) -> String:
	var before := PBuild.derive(r)
	var dup: Dictionary = r.duplicate(true)
	PRun.equip_item(dup, id)
	var after := PBuild.derive(dup)
	var d: Dictionary = PCatalog.equipment()[id]
	var cur = r.equipment.get(String(d.slot), null)
	var swap := (" · %s은(는) 가방으로" % String(PCatalog.equipment()[String(cur)].name)) if cur != null else ""
	return _diff_text(before, after) + swap

func _compare_unequip(r: Dictionary, slot: String) -> String:
	var before := PBuild.derive(r)
	var dup: Dictionary = r.duplicate(true)
	PRun.unequip_item(dup, slot)
	return _diff_text(before, PBuild.derive(dup))
