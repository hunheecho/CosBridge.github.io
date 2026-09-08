class_name PBuildDetail
extends Control
## 빌드 상세(펼친 기술 상세). 전투 중·거점에서 같은 내용을 보여 준다(PC는 가리키면 짧은 설명, 여기서는 고정 패널 · 모바일은 탭).
## 표시: 자동기술 3칸(아이콘·이름·Lv·수치) → 붙은 개조(아이콘 + 효과 한 문장 + 이번 전투 발동/적중/피해) → 공용 증강·패시브(적용 연결) → 장비(별도 영역).
##
## 숫자는 st.mod_report()가 준 것만 쓴다. 기록이 없는 개조는 0이 아니라 "—"로 적는다(미발동을 0으로 오인시키지 않는다).
## 전투 중에 열 때는 main이 공통 일시정지·입력 초기화 경로(view.set_paused)를 쓴다. 이 패널은 규칙을 진행시키지 않는다.

signal closed()

var _panel: PanelContainer
var _box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.74)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.1, 0.12, 0.15, 0.98), 8, 12, Color(0.5, 0.6, 0.75, 0.9)))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var sc := PUi.scroll()
	_panel.add_child(sc)
	_box = PUi.vbox(8)
	sc.add_child(_box)
	visible = false
	_apply_safe()

func _apply_safe() -> void:
	if not is_inside_tree():
		return
	var m := PLayout.margins(get_viewport(), 24, 40)
	_panel.offset_left = float(m.left)
	_panel.offset_top = float(m.top)
	_panel.offset_right = -float(m.right)
	_panel.offset_bottom = -float(m.bottom)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_apply_safe()

func is_open() -> bool:
	return visible

func close() -> void:
	visible = false
	closed.emit()

## build = PBuild.derive(run) 결과, report = st.mod_report()({} 가능), title_extra = 화면 이름
func open_with(build: Dictionary, report: Dictionary, title_extra: String) -> void:
	PUi.clear(_box)
	var head := PUi.hbox(10)
	head.add_child(PUi.rich("[b]빌드 상세[/b] [color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(title_extra), 20))
	head.add_child(PUi.spacer())
	var close_btn := PUi.button("닫기 (Esc)", func(): close(), true, 14)
	close_btn.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
	head.add_child(close_btn)
	_box.add_child(head)
	var G := PCatalog.growth()
	var S: Dictionary = G.SLOTS
	var weapons: Array = build.get("weapons", [])
	_box.add_child(PUi.rich("[b]%s %d/%d[/b] [color=#9ea8b8]각 기술 밑의 아이콘이 그 기술에 붙은 개조입니다[/color]" % [PGlossaryTip.term("auto_skill", "자동기술"), weapons.size(), int(S.weapons)], 16))
	for i in int(S.weapons):
		if i < weapons.size():
			_box.add_child(_weapon_card(weapons[i], report, int(S.weaponMax), int(S.weaponMods)))
		else:
			var ec := PUi.card("", PUi.CARD_OFF)
			(ec.box as VBoxContainer).add_child(PUi.rich("[color=#6a7078]자동기술 %d — 빈 슬롯 (레벨업 또는 상점)[/color]" % (i + 1), 13))
			_box.add_child(ec.panel)
	_box.add_child(_manual_card(build))
	_box.add_child(_common_card(build))
	_box.add_child(_equip_card(build))
	visible = true

func _icon_strip(keys: Array, px: float) -> Control:
	var h := PUi.hbox(4)
	h.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for k in keys:
		var t := PIconTile.new(String(k), PIconTile.STYLE_SMALL)
		t.set_icon_px(px, px, 0)
		h.add_child(t)
	return h

func _weapon_card(wd: Dictionary, report: Dictionary, lv_max: int, mod_max: int) -> Control:
	var wid := String(wd.id)
	var c := PUi.card("")
	var box: VBoxContainer = c.box
	var head := PUi.hbox(10)
	var tile := PIconTile.new(PIcons.weapon_key(wid), PIconTile.STYLE_AUTO)
	tile.set_icon_px(56.0, 56.0, 0)
	head.add_child(tile)
	var col := PUi.vbox(2)
	col.add_child(PUi.rich("[b]%s[/b] Lv%d/%d" % [PGlossaryTip.term("w:" + wid, String(wd.name)), int(wd.level), lv_max], 16))
	var rng_txt := (" · 사거리 %d" % int(round(float(wd.range)))) if float(wd.get("range", 0.0)) > 0.0 else ""
	col.add_child(PUi.rich("[color=#9ea8b8]피해 %s · 주기 %s초%s[/color]" % [PUi.fmt(float(wd.damage)), PUi.fmt(float(wd.interval)), rng_txt], 12))
	head.add_child(col)
	box.add_child(head)
	var mods: Array = wd.get("mods", [])
	box.add_child(PUi.rich("[color=#9ea8b8]%s %d/%d[/color]" % [PGlossaryTip.term("mod", "개조"), mods.size(), mod_max], 12))
	for j in mod_max:
		if j < mods.size():
			box.add_child(_mod_row(wid, String(mods[j]), report))
		else:
			var er := PUi.hbox(8)
			var et := PIconTile.new("", PIconTile.STYLE_MOD)
			et.empty = true
			et.set_icon_px(30.0, 30.0, 0)
			er.add_child(et)
			er.add_child(PUi.rich("[color=#6a7078]빈 개조 칸[/color]", 12))
			box.add_child(er)
	return c.panel

## 개조 한 줄: 아이콘 + 이름 + 효과 한 문장 + 이번 전투 발동/적중/피해(기록 없으면 —)
func _mod_row(wid: String, mid: String, report: Dictionary) -> Control:
	var W := PCatalog.weapons()
	var md: Dictionary = W[wid].mods[mid] if W.has(wid) and (W[wid].mods as Dictionary).has(mid) else {}
	var row := PUi.hbox(8)
	var t := PIconTile.new(PIcons.mod_key(wid, mid), PIconTile.STYLE_MOD)
	t.set_icon_px(30.0, 30.0, 0)
	row.add_child(t)
	var col := PUi.vbox(1)
	col.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(md.get("name", mid))), PGlossaryTip.esc(String(md.get("desc", "")))], 12))
	col.add_child(PUi.rich("[color=#9ea8b8]이번 전투[/color] %s" % _mod_stat_text(mid, report), 12))
	row.add_child(col)
	return row

## report에 항목이 없으면 0이 아니라 —. 발동(효과 생성)과 적중(실제 유효 피해)을 구분해 적는다
func _mod_stat_text(mid: String, report: Dictionary) -> String:
	if report.is_empty() or not report.has(mid):
		return "[color=#6a7078]발동 — · 적중 — · 피해 —[/color]"
	var m: Dictionary = report[mid]
	return "발동 [b]%d[/b] · 적중 [b]%d[/b] · 피해 [b]%s[/b]" % [int(m.get("procs", 0)), int(m.get("hits", 0)), PUi.fmt(float(m.get("damage", 0.0)))]

func _manual_card(build: Dictionary) -> Control:
	var c := PUi.card("수동 기술")
	var box: VBoxContainer = c.box
	var SK := PCatalog.skills()
	for slot in ["q", "e"]:
		var sk = build.skills.get(slot, null)
		var row := PUi.hbox(8)
		if sk == null:
			var et := PIconTile.new("", PIconTile.STYLE_MANUAL)
			et.empty = true
			et.set_icon_px(40.0, 40.0, 0)
			row.add_child(et)
			row.add_child(PUi.rich("[b]E[/b] [color=#6a7078]미보유 — 사용할 수 없는 빈 슬롯[/color]", 13))
		else:
			var sid := String(sk.id)
			var d: Dictionary = SK[sid]
			var key := "skill:slowfield" if slot == "q" else PIcons.e_key(sid, sk.get("variant", null))
			var t := PIconTile.new(key, PIconTile.STYLE_MANUAL)
			t.set_icon_px(40.0, 40.0, 0)
			row.add_child(t)
			var vtxt := (" · 변형 " + String(d.variants[String(sk.variant)].name)) if sk.get("variant", null) != null else ""
			row.add_child(PUi.rich("[b]%s[/b] %s Lv%d%s [color=#9ea8b8]%s[/color]" % [String(d.key), PGlossaryTip.esc(String(d.name)), int(sk.level), vtxt, PGlossaryTip.esc(String(d.get("desc", "")))], 13))
		box.add_child(row)
	var dr := PUi.hbox(8)
	var dt := PIconTile.new("action:dodge", PIconTile.STYLE_MANUAL)
	dt.set_icon_px(40.0, 40.0, 0)
	dr.add_child(dt)
	dr.add_child(PUi.rich("[b]Space[/b] 회피 [color=#9ea8b8]무적은 회피 이동 중에만[/color]", 13))
	box.add_child(dr)
	return c.panel

## 공용 증강·패시브: 아이콘 1개씩만 두고, 적용되는 기술은 여기서 연결해 보여 준다(기술 칸에 복제하지 않는다)
func _common_card(build: Dictionary) -> Control:
	var g: Dictionary = build.get("growth", {})
	var c := PUi.card("%s · %s [color=#9ea8b8]기술 개조와 분리 — 아이콘을 기술마다 복제하지 않습니다[/color]" % [PGlossaryTip.term("common", "공용 증강"), PGlossaryTip.term("passive", "패시브")])
	var box: VBoxContainer = c.box
	var wnames := []
	for w in build.get("weapons", []):
		wnames.append(String(w.name))
	var applies := ", ".join(wnames) if wnames.size() > 0 else "없음"
	var CM := PCatalog.commons()
	var any := false
	for k in g.get("commons", {}):
		if int(g.commons[k]) <= 0:
			continue
		any = true
		var d: Dictionary = CM[String(k)]
		var row := PUi.hbox(8)
		var t := PIconTile.new("common:" + String(k), PIconTile.STYLE_SMALL)
		t.set_icon_px(28.0, 28.0, 0)
		row.add_child(t)
		var col := PUi.vbox(1)
		col.add_child(PUi.rich("[b]%s[/b]%s [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(d.name)), (" %d/%d" % [int(g.commons[k]), int(d.max)]) if int(d.max) > 1 else "", PGlossaryTip.esc(String(d.get("desc", "")))], 12))
		col.add_child(PUi.rich("[color=#9ea8b8]적용 대상(현재 빌드 자동기술): %s[/color]" % PGlossaryTip.esc(applies), 11))
		row.add_child(col)
		box.add_child(row)
	var PS := PCatalog.passives()
	for k in g.get("passives", {}):
		if int(g.passives[k]) <= 0:
			continue
		any = true
		var d2: Dictionary = PS[String(k)]
		var row2 := PUi.hbox(8)
		var t2 := PIconTile.new("passive:" + String(k), PIconTile.STYLE_SMALL)
		t2.set_icon_px(28.0, 28.0, 0)
		row2.add_child(t2)
		row2.add_child(PUi.rich("[b]%s[/b] %d/%d [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(d2.name)), int(g.passives[k]), int(d2.max), PGlossaryTip.esc(String(d2.get("desc", "")))], 12))
		box.add_child(row2)
	if not any:
		box.add_child(PUi.rich("[color=#6a7078]없음[/color]", 12))
	return c.panel

func _equip_card(build: Dictionary) -> Control:
	var c := PUi.card("%s [color=#9ea8b8]자동기술 슬롯과 다른 영역 — 무기/갑옷/방패[/color]" % PGlossaryTip.term("equipment", "장비"))
	var box: VBoxContainer = c.box
	var eq_ids: Array = build.get("equip_ids", [])
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var found := ""
		for id in eq_ids:
			var d := PCatalog.equipment_def(String(id))
			if not d.is_empty() and String(d.get("slot", "")) == slot:
				found = String(id)
		var row := PUi.hbox(8)
		var t := PIconTile.new(("equip:" + found) if found != "" else "", PIconTile.STYLE_EQUIP)
		t.empty = found == ""
		t.set_icon_px(32.0, 32.0, 0)
		row.add_child(t)
		row.add_child(PUi.rich("[color=#9ea8b8]%s[/color]  %s" % [PUi.slot_name(slot), (PUi.equip_line(found) if found != "" else "[color=#6a7078]비어 있음[/color]")], 13))
		box.add_child(row)
	return c.panel
