class_name PSkillBankScreen
extends PScreen
## 기술 편성 — 스킬 창고와 Q/E 배치(2026-09-10 §6·§7).
##
## 여기서 하는 일은 **거점에서 시간·금화 없이** 되는 네 가지뿐이다.
##   ① 창고의 일반 기술을 Q나 E에 넣기
##   ② Q·E의 일반 기술을 창고로 빼기(레벨·변형을 그대로 안고 간다)
##   ③ Q와 E를 한 번에 맞바꾸기
##   ④ 착용 장비가 주는 **장비 기술**을 Q나 E에 배치하기
##
## 화면이 규칙을 만들지 않는다. 판정·이동은 전부 PGrowth(place_skill·store_skill·swap_qe)가 하고
## 여기서는 그 결과를 그린다. 특히:
##   - 장비를 벗어도 배치는 지우지 않는다. '지금 사용 불가'라고 적고 **직접 다른 기술을 고르게** 한다.
##   - 임의의 일반 기술을 자동으로 넣지 않는다(§6).
##   - 장비 기술에는 'Lv1/3' 같은 성장 표시를 붙이지 않는다. '장비 기술 · 성장 없음'이다(§5).
##   - 전투 중에는 열리지 않는다(PGrowth.bank_edit_reason). 재사용 시간을 우회할 길이 없다.

func refresh() -> void:
	clear_all()
	close_confirm()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	top.add_child(PUi.rich("[b]기술 편성[/b] [color=#9ea8b8]거점에서 시간·금화 없이 · 몇 번을 바꿔도 값이 들지 않습니다[/color]", 22))
	var why := PGrowth.bank_edit_reason(r)
	if why != "":
		top.add_child(PUi.rich("[color=#ff8c73]%s[/color]" % PGlossaryTip.esc(why), 14))
	var cols := two_cols(0.5)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	var b := PBuild.derive(r)
	for slot in PGrowth.SKILL_SLOTS:
		left.add_child(_slot_card(r, b, String(slot)))
	var swap_ok: bool = why == "" and (r.growth.skills.get("q", null) != null or r.growth.skills.get("e", null) != null)
	var sw := PUi.button("Q와 E 맞바꾸기", func(): main.swap_qe_skills(), swap_ok, 15)
	sw.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	left.add_child(sw)
	left.add_child(PUi.rich("[color=#9ea8b8]맞바꿔도 레벨·변형은 그 기술을 따라갑니다. 재사용 시간은 전투에서만 흐르므로 편성으로 초기화되지 않습니다.[/color]", 12))
	right.add_child(_bank_card(r, why == ""))
	right.add_child(_equip_card(r, why == ""))
	# 시험 전용(PROPHECY_EQUIP_SKILL_DEMO=1일 때만 나타난다). 장비 기술을 주는 **장비 정의**는 다른 담당의 몫이라
	# 아직 자료에 없다. 이 갈래(소유·보관·배치)를 실제 버튼으로 확인하려고 시험용 장비 하나를 가방에 넣는 버튼이다.
	if PCatalog.equip_skill_demo():
		var have: bool = PRun.owns_equip_type(r, PCatalog.DEMO_EQUIP_ID)
		right.add_child(PUi.button("[시험 전용] 시험용 각인검을 가방에 넣기", func(): main.grant_demo_equip(), not have, 13))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	bottom.add_child(PUi.button("장비", func(): main.show("equip"), true, 14))
	default_button = back

## Q 또는 E 한 칸. 무엇이 들어 있고, 지금 쓸 수 있는지, 빼면 어디로 가는지를 한 자리에 적는다
func _slot_card(r: Dictionary, b: Dictionary, slot: String) -> Control:
	var g: Dictionary = r.growth
	var sk = g.skills.get(slot, null)
	var SK := PCatalog.skills()
	var c := PUi.card("%s 칸" % slot.to_upper(), PUi.CARD, 17)
	var box: VBoxContainer = c.box
	if sk == null:
		box.add_child(PUi.rich("[color=#6a7078]비어 있음[/color] [color=#9ea8b8]— 오른쪽에서 넣을 기술을 직접 고르세요.[/color]", 15))
		return c.panel
	var sid := String(sk.id)
	var d: Dictionary = SK.get(sid, {})
	var eq := PGrowth.is_equip_skill(sid)
	var blocked := PGrowth.slot_blocked_reason(r, slot)
	var head := "[b]%s[/b]" % PGlossaryTip.esc(String(d.get("name", sid)))
	if eq:
		head += "  [color=#9ea8b8]장비 기술 · 성장 없음[/color]"
	else:
		var vname := ""
		if sk.get("variant", null) != null:
			vname = " · 변형 %s" % String((d.get("variants", {}) as Dictionary).get(String(sk.variant), {}).get("name", String(sk.variant)))
		head += "  [color=#9ea8b8]Lv%d / %d%s[/color]" % [int(sk.level), int(PGrowth.G().SLOTS.skillMax), PGlossaryTip.esc(vname)]
	box.add_child(PUi.rich(head, 16))
	if blocked != "":
		box.add_child(PUi.rich("[color=#ff8c73]지금 사용 불가 — %s[/color]" % PGlossaryTip.esc(blocked), 13))
	else:
		PUi.kv(box, "재사용", "[b]%s초[/b]" % PUi.fmt(PBuildDetail.cd_of_build(b, slot)), 13)
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.get("desc", ""))), 13))
	var can_edit: bool = PGrowth.bank_edit_reason(r) == ""
	var label := "칸에서 내리기 (장비 기술은 창고에 남지 않습니다)" if eq else "창고로 빼기 (레벨·변형 그대로 보관)"
	var btn := PUi.button(label, func(): main.store_skill(slot), can_edit, 14)
	btn.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	box.add_child(btn)
	return c.panel

## 창고: 지금 편성에 없는 **보유 일반 기술**. 여기 있는 동안에는 어떤 전투 효과도 내지 않는다
func _bank_card(r: Dictionary, can_edit: bool) -> Control:
	var g: Dictionary = r.growth
	var SK := PCatalog.skills()
	var bank := PGrowth.bank_ro(g)
	var c := PUi.card("기술 창고 [color=#9ea8b8]%d개 · 보관 중에는 전투에 나오지 않습니다[/color]" % bank.size(), PUi.CARD, 17)
	var box: VBoxContainer = c.box
	if bank.is_empty():
		box.add_child(PUi.rich("[color=#6a7078]비어 있음[/color] [color=#9ea8b8]— Q나 E의 일반 기술을 빼면 여기에 그대로 보관됩니다.[/color]", 14))
		return c.panel
	for be in bank:
		var sid := String(be.id)
		var d: Dictionary = SK.get(sid, {})
		var vname := ""
		if be.get("variant", null) != null:
			vname = " · 변형 %s" % String((d.get("variants", {}) as Dictionary).get(String(be.variant), {}).get("name", String(be.variant)))
		# 이름 줄과 버튼 줄을 **나눠** 둔다. 한 줄에 다 넣으면 좁은 화면에서 버튼이 오른쪽 밖으로 잘린다
		var name_row := PUi.hbox(8)
		name_row.add_child(PUi.icon_of(PIcons.e_key(sid, be.get("variant", null)), 30.0, "", "", 0.0, 0))
		var nl := PUi.rich("[b]%s[/b] [color=#9ea8b8]Lv%d%s[/color]" % [PGlossaryTip.esc(String(d.get("name", sid))), int(be.get("level", 1)), PGlossaryTip.esc(vname)], 15)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(nl)
		box.add_child(name_row)
		var row := PUi.hbox(8)
		for slot in PGrowth.SKILL_SLOTS:
			var sl := String(slot)
			var dup: bool = PGrowth.skill_id_in(g, "e" if sl == "q" else "q") == sid
			var pb := PUi.button("%s에 넣기" % sl.to_upper(), func(): main.place_skill(sl, sid), can_edit and not dup, 13)
			pb.custom_minimum_size = Vector2(0, PLayout.button_min_height())
			pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pb)
		box.add_child(row)
	return c.panel

## 착용 장비가 주는 장비 기술. **착용으로 '사용 가능'해지는 것과 Q/E에 '배치'하는 것은 다르다**(§6)
func _equip_card(r: Dictionary, can_edit: bool) -> Control:
	var g: Dictionary = r.growth
	var SK := PCatalog.skills()
	var ids := PGrowth.granted_skill_ids(r)
	var c := PUi.card("장비 기술 [color=#9ea8b8]착용 중인 장비가 주는 것 · 레벨업·개조 없음[/color]", PUi.CARD, 17)
	var box: VBoxContainer = c.box
	if ids.is_empty():
		box.add_child(PUi.rich("[color=#6a7078]지금 착용한 장비가 주는 기술이 없습니다.[/color] [color=#9ea8b8]장비를 끼면 여기에 나타나고, 그때 Q나 E에 [b]직접 배치[/b]합니다.[/color]", 14))
		return c.panel
	for sid_v in ids:
		var sid := String(sid_v)
		var d: Dictionary = SK.get(sid, {})
		box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]장비 기술 · 성장 없음[/color]" % PGlossaryTip.esc(String(d.get("name", sid))), 15))
		var row := PUi.hbox(8)
		for slot in PGrowth.SKILL_SLOTS:
			var sl := String(slot)
			var here: bool = PGrowth.skill_id_in(g, sl) == sid
			var dup: bool = PGrowth.skill_id_in(g, "e" if sl == "q" else "q") == sid
			var pb := PUi.button(("%s에 배치됨" % sl.to_upper()) if here else ("%s에 배치" % sl.to_upper()),
				func(): main.place_skill(sl, sid), can_edit and not here and not dup, 13)
			pb.custom_minimum_size = Vector2(0, PLayout.button_min_height())
			pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pb)
		box.add_child(row)
	box.add_child(PUi.rich("[color=#9ea8b8]장비를 벗으면 그 기술은 쓸 수 없게 되지만 [b]배치는 그대로 남습니다[/b]. 창고의 기술이 자동으로 들어오지 않으니 직접 골라 넣으세요.[/color]", 12))
	return c.panel
