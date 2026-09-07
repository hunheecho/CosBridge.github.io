class_name PChoiceOverlay
extends Control
## 3택 오버레이(레벨업·임무 보상·보스 희귀 보상·지역 보상·개조/변형 변경, HTML levelCards). 열려 있는 동안 다른 입력을 막는다(배경이 마우스를 삼킨다).
## 카드 내용은 PGrowth.describe(run, choice)가 준 것만 보여 준다(수치 계산 없음). 전투 중 정지는 main이 한다.

signal picked(key: String)
signal skipped()
signal rerolled()

var offer: Dictionary = {}
var _panel: PanelContainer
var _box: VBoxContainer
var _bg: ColorRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.72)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.1, 0.12, 0.15, 0.98), 8, 12, Color(0.5, 0.6, 0.75, 0.9)))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 24.0
	_panel.offset_top = 40.0
	_panel.offset_right = -24.0
	_panel.offset_bottom = -40.0
	add_child(_panel)
	_box = PUi.vbox(8)
	_panel.add_child(_box)
	visible = false

func is_open() -> bool:
	return visible

func open(run: Dictionary, off: Dictionary) -> void:
	offer = off
	PUi.clear(_box)
	var pool := String(off.get("pool", "level"))
	var g: Dictionary = run.growth
	var title := ""
	match pool:
		"boss": title = "보스 희귀 보상"
		"deep": title = "지역 보상 선택"
		"mission":
			var kt: Dictionary = PCatalog.mission_rules().kindText
			title = "%s · %s" % [("개조·변형 변경" if off.get("paidChange", null) != null else "임무 보상"), String(kt.get(String(off.get("missionKind", "")), "3택"))]
		_:
			title = "레벨 업! Lv %d" % int(g.level)
			if int(g.pendingLevelUps) > 1:
				title += " (남은 선택 %d)" % int(g.pendingLevelUps)
			if off.get("steer", null) != null:
				title += "  [color=#ffe066]예약: %s[/color]" % PSortie.kind_name(String(off.steer))
	_box.add_child(PUi.rich("[b]%s[/b]" % title, 22))
	var rid = off.get("regionId", null)
	if rid != null and String(rid) != "" and pool != "boss":
		_box.add_child(PUi.rich("[color=#9ea8b8]지역 계열: %s[/color]" % PGlossaryTip.esc(String(PCatalog.region_tag_text().get(String(rid), "—"))), 12))
	var row := PUi.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(row)
	var choices: Array = off.get("choices", [])
	if choices.is_empty():
		row.add_child(PUi.rich("[color=#9ea8b8]제시할 수 있는 후보가 없습니다.[/color]", 14))
	for c in choices:
		var ch: Dictionary = c
		var d := PGrowth.describe(run, ch)
		var card := PUi.card("", PUi.CARD_ON if bool(d.regionMatch) else PUi.CARD)
		var p: PanelContainer = card.panel
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var b: VBoxContainer = card.box
		b.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.esc(String(d.title)), 15))
		b.add_child(PUi.rich("[color=#9ea8b8]%s[/color]%s" % [PGlossaryTip.esc(String(d.type)), "  [color=#ffe066]지역 계열[/color]" if bool(d.regionMatch) else ""], 12))
		var sc := PUi.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var inner := PUi.vbox(4)
		sc.add_child(inner)
		inner.add_child(PUi.rich(PGlossaryTip.esc(String(d.change)), 14))
		PUi.kv(inner, "단계", PGlossaryTip.esc(String(d.stage)), 12)
		PUi.kv(inner, "적용", PGlossaryTip.esc(String(d.scope)), 12)
		PUi.kv(inner, "슬롯", PGlossaryTip.esc(String(d.slot)), 12)
		b.add_child(sc)
		var key := String(ch.key)
		var btn := PUi.button("선택", func(): picked.emit(key), true, 15)
		b.add_child(btn)
		row.add_child(p)
	var bottom := PUi.hbox(10)
	_box.add_child(bottom)
	if pool == "level":
		bottom.add_child(PUi.button("건너뛰기 (금화 +%d)" % int(PCatalog.config().SKIP_AUGMENT_GOLD), func(): skipped.emit(), true, 13))
		if PRun.has_service(run, "reroll"):
			bottom.add_child(PUi.button("제시 재선택권 사용 (남은 %d)" % int(run.services.reroll), func(): rerolled.emit(), true, 13))
	elif pool == "deep" or pool == "mission":
		bottom.add_child(PUi.button("받지 않음", func(): skipped.emit(), true, 13))
	visible = true

func close() -> void:
	offer = {}
	visible = false
