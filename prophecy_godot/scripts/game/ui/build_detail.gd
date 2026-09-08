class_name PBuildDetail
extends Control
## '내 빌드'(전체 빌드 보기). 전투 중에는 일시정지 화면·Tab·터치의 '빌드' 버튼에서, 거점에서는 상세 보기에서 같은 내용을 연다.
## 전장 HUD에는 조작 아이콘만 남기므로(사람 플레이 뒤 요구 2026-09-08) 자동기술·개조·Q/E·공용·패시브·장비는 여기서 확인한다.
##
## 표시: 자동기술 3칸(아이콘·이름·Lv·수치) → 붙은 개조(아이콘 + 효과 한 문장) → 수동 기술 Q/E(재사용 시간) → 공용 증강·패시브 → 장비.
## 이번 전투 발동/적중/피해 같은 숫자는 '이번 전투 기록'을 켰을 때만 나온다(기본 화면을 숫자로 채우지 않는다).
## 숫자는 st.mod_report()가 준 것만 쓴다. 기록이 없는 개조는 0이 아니라 "—"로 적는다(미발동을 0으로 오인시키지 않는다).
## 전투 중에 열 때는 main이 공통 일시정지·입력 초기화 경로(view.set_paused)를 쓴다. 이 패널은 규칙을 진행시키지 않는다.

signal closed()

var _panel: PanelContainer
var _box: VBoxContainer
var _build: Dictionary = {}
var _report: Dictionary = {}
var _where := ""
var _stats_open := false      # 개조별 이번 전투 숫자를 펼쳤는가(기본 접힘)

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
	_build = build
	_report = report
	_where = title_extra
	_stats_open = false
	_render()
	visible = true

func _render() -> void:
	PUi.clear(_box)
	var build := _build
	var report := _report
	var head := PUi.hbox(10)
	head.add_child(PUi.rich("[b]내 빌드[/b] [color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(_where), 22))
	head.add_child(PUi.spacer())
	var close_btn := PUi.button("닫기 (Esc)", func(): close(), true, 15)
	close_btn.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
	head.add_child(close_btn)
	_box.add_child(head)
	var G := PCatalog.growth()
	var S: Dictionary = G.SLOTS
	var weapons: Array = build.get("weapons", [])
	var g: Dictionary = build.get("growth", {})
	if PGrowth.is_v2(g):
		# 새 구조: 주무기 1칸과 보조 2칸을 따로 보여 준다. 상한도 자리마다 다르다
		var R := PCatalog.slot_rules()
		var mains: Array = weapons.filter(func(w): return PCatalog.is_main_weapon(String(w.id)))
		var sups: Array = weapons.filter(func(w): return not PCatalog.is_main_weapon(String(w.id)))
		_box.add_child(PUi.rich("[b]주무기 %d/%d[/b]" % [mains.size(), int(R.get("main", 1))], 17))
		for i in maxi(int(R.get("main", 1)), mains.size()):
			if i < mains.size():
				_box.add_child(_weapon_card(mains[i], report, int(R.get("mainMax", 5)), int(R.get("mainMods", 2))))
			else:
				_box.add_child(_empty_slot("주무기 — 빈 슬롯"))
		_box.add_child(PUi.rich("[b]보조무기 %d/%d[/b] [color=#9ea8b8]각 Lv%d · 개조 %d[/color]" % [sups.size(), int(R.get("supports", 2)), int(R.get("supportMax", 3)), int(R.get("supportMods", 1))], 17))
		for i in maxi(int(R.get("supports", 2)), sups.size()):
			if i < sups.size():
				_box.add_child(_weapon_card(sups[i], report, int(R.get("supportMax", 3)), int(R.get("supportMods", 1))))
			else:
				_box.add_child(_empty_slot("보조무기 %d — 빈 슬롯" % (i + 1)))
	else:
		# 옛 저장(자동기술 3칸): 그 회차는 옛 구조 그대로 보여 준다
		_box.add_child(PUi.rich("[b]%s %d/%d[/b] [color=#9ea8b8](옛 구조 회차)[/color]" % [PGlossaryTip.term("auto_skill", "자동기술"), weapons.size(), int(S.weapons)], 17))
		for i in maxi(int(S.weapons), weapons.size()):
			if i < weapons.size():
				_box.add_child(_weapon_card(weapons[i], report, int(S.weaponMax), int(S.weaponMods)))
			else:
				_box.add_child(_empty_slot("자동기술 %d — 빈 슬롯" % (i + 1)))
	_box.add_child(_manual_card(build))
	_box.add_child(_common_card(build))
	_box.add_child(_equip_card(build))
	if not report.is_empty():
		var t := PUi.button("이번 전투 기록 닫기 ▼" if _stats_open else "이번 전투 기록 보기 ▶ (개조별 발동·적중·피해)", func(): _stats_open = not _stats_open; _render(), true, 14)
		t.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		_box.add_child(t)

func _empty_slot(text: String) -> Control:
	var ec := PUi.card("", PUi.CARD_OFF)
	(ec.box as VBoxContainer).add_child(PUi.rich("[color=#6a7078]%s[/color]" % text, 14))
	return ec.panel

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
	col.add_child(PUi.rich("[b]%s[/b] Lv%d/%d" % [PGlossaryTip.term("w:" + wid, String(wd.name)), int(wd.level), lv_max], 17))
	col.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PUi.weapon_stats_text(wd), 14))
	head.add_child(col)
	box.add_child(head)
	var mods: Array = wd.get("mods", [])
	box.add_child(PUi.rich("[color=#9ea8b8]%s %d/%d[/color]" % [PGlossaryTip.term("mod", "개조"), mods.size(), mod_max], 13))
	for j in mod_max:
		if j < mods.size():
			box.add_child(_mod_row(wid, String(mods[j]), report))
		else:
			var er := PUi.hbox(8)
			var et := PIconTile.new("", PIconTile.STYLE_MOD)
			et.empty = true
			et.set_icon_px(30.0, 30.0, 0)
			er.add_child(et)
			er.add_child(PUi.rich("[color=#6a7078]빈 개조 칸[/color]", 13))
			box.add_child(er)
	return c.panel

## 개조 한 줄: 아이콘 + 이름 + 효과 한 문장. 이번 전투 숫자는 펼쳤을 때만(기록 없으면 —)
func _mod_row(wid: String, mid: String, report: Dictionary) -> Control:
	var W := PCatalog.weapons()
	var md: Dictionary = W[wid].mods[mid] if W.has(wid) and (W[wid].mods as Dictionary).has(mid) else {}
	var row := PUi.hbox(8)
	var t := PIconTile.new(PIcons.mod_key(wid, mid), PIconTile.STYLE_MOD)
	t.set_icon_px(30.0, 30.0, 0)
	row.add_child(t)
	var col := PUi.vbox(1)
	col.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(md.get("name", mid))), PGlossaryTip.esc(String(md.get("desc", "")))], 14))
	if _stats_open:
		col.add_child(PUi.rich("[color=#9ea8b8]이번 전투[/color] %s" % _mod_stat_text(mid, report), 13))
	row.add_child(col)
	return row

## report에 항목이 없으면 0이 아니라 —. 발동(효과 생성)과 적중(실제 유효 피해)을 구분해 적는다
func _mod_stat_text(mid: String, report: Dictionary) -> String:
	if report.is_empty() or not report.has(mid):
		return "[color=#6a7078]발동 — · 적중 — · 피해 —[/color]"
	var m: Dictionary = report[mid]
	return "발동 [b]%d[/b] · 적중 [b]%d[/b] · 피해 [b]%s[/b]" % [int(m.get("procs", 0)), int(m.get("hits", 0)), PUi.fmt(float(m.get("damage", 0.0)))]

## 수동 기술: 회피(Space) · Q · E. 전장 아이콘과 같은 순서로 두고 최종 재사용 시간을 적는다
func _manual_card(build: Dictionary) -> Control:
	var c := PUi.card("수동 기술 [color=#9ea8b8]Space · Q · E[/color]", PUi.CARD, 16)
	var box: VBoxContainer = c.box
	var dr := PUi.hbox(8)
	var dt := PIconTile.new("action:dodge", PIconTile.STYLE_MANUAL)
	dt.set_icon_px(40.0, 40.0, 0)
	dr.add_child(dt)
	dr.add_child(PUi.rich("[b]Space[/b] 회피 [color=#9ea8b8]무적은 회피 이동 중에만[/color]", 14))
	box.add_child(dr)
	var SK := PCatalog.skills()
	for slot in ["q", "e"]:
		var sk = build.skills.get(slot, null)
		var row := PUi.hbox(8)
		if sk == null:
			var et := PIconTile.new("", PIconTile.STYLE_MANUAL)
			et.empty = true
			et.set_icon_px(40.0, 40.0, 0)
			row.add_child(et)
			row.add_child(PUi.rich("[b]E[/b] [color=#6a7078]미보유[/color]", 14))
		else:
			var sid := String(sk.id)
			var d: Dictionary = SK[sid]
			var key := "skill:slowfield" if slot == "q" else PIcons.e_key(sid, sk.get("variant", null))
			var t := PIconTile.new(key, PIconTile.STYLE_MANUAL)
			t.set_icon_px(40.0, 40.0, 0)
			row.add_child(t)
			var vtxt := (" · 변형 " + String(d.variants[String(sk.variant)].name)) if sk.get("variant", null) != null else ""
			var col := PUi.vbox(1)
			col.add_child(PUi.rich("[b]%s[/b] %s Lv%d%s" % [String(d.key), PGlossaryTip.esc(String(d.name)), int(sk.level), vtxt], 15))
			col.add_child(PUi.rich("[color=#9ea8b8]재사용[/color] [b]%s초[/b] [color=#9ea8b8]%s[/color]" % [PUi.fmt(cd_of_build(build, String(slot))), PGlossaryTip.esc(String(d.get("desc", "")))], 13))
			row.add_child(col)
		box.add_child(row)
	return c.panel

## 빌드의 최종 재사용 시간(초). 규칙(PSkills.cd_of / PBuild.derive)이 이미 계산한 값을 읽기만 한다
static func cd_of_build(build: Dictionary, slot: String) -> float:
	var sk = build.get("skills", {}).get(slot, null)
	if sk == null:
		return 0.0
	if slot == "q":
		return float(build.get("special_cd", 0.0))
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	return float(d.cooldown[mini(3, int(sk.level)) - 1]) * float(build.get("skill_cd_mult", 1.0)) * float(build.get("e_cd_mult", 1.0))

## 공용 증강·패시브: 아이콘 1개씩만 두고, 적용되는 기술은 여기서 연결해 보여 준다(기술 칸에 복제하지 않는다)
func _common_card(build: Dictionary) -> Control:
	var g: Dictionary = build.get("growth", {})
	var c := PUi.card("%s · %s [color=#9ea8b8]모든 자동기술에 함께 적용[/color]" % [PGlossaryTip.term("common", "공용 증강"), PGlossaryTip.term("passive", "패시브")], PUi.CARD, 16)
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
		col.add_child(PUi.rich("[b]%s[/b]%s [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(d.name)), (" %d/%d" % [int(g.commons[k]), int(d.max)]) if int(d.max) > 1 else "", PGlossaryTip.esc(String(d.get("desc", "")))], 14))
		col.add_child(PUi.rich("[color=#9ea8b8]적용: %s[/color]" % PGlossaryTip.esc(applies), 12))
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
		row2.add_child(PUi.rich("[b]%s[/b] %d/%d [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(d2.name)), int(g.passives[k]), int(d2.max), PGlossaryTip.esc(String(d2.get("desc", "")))], 14))
		box.add_child(row2)
	if not any:
		box.add_child(PUi.rich("[color=#6a7078]없음[/color]", 13))
	return c.panel

func _equip_card(build: Dictionary) -> Control:
	var c := PUi.card("%s [color=#9ea8b8]무기 · 방어구 · 방패[/color]" % PGlossaryTip.term("equipment", "장비"), PUi.CARD, 16)
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
		row.add_child(PUi.rich("[color=#9ea8b8]%s[/color]  %s" % [PUi.slot_name(slot), (PUi.equip_line(found) if found != "" else "[color=#6a7078]비어 있음[/color]")], 14))
		box.add_child(row)
	return c.panel
