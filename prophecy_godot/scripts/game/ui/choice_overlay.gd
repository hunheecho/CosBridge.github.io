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
	add_child(_panel)
	_box = PUi.vbox(8)
	_panel.add_child(_box)
	visible = false
	_apply_safe()

## 패널 = 안전 영역 안쪽 24·40 여백(PLayout). 창 크기가 바뀌면 다시 맞춘다
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
		# 아이콘 줄: 새 효과의 큰 아이콘 + (붙는 상위 기술의 작은 아이콘). 문장보다 먼저 '무엇이 어디에 붙는지'를 보인다
		var irow := PUi.hbox(8)
		irow.alignment = BoxContainer.ALIGNMENT_BEGIN
		irow.add_child(PUi.icon_of(icon_key(ch), 56.0, "", "", 132.0))
		var parent_key := parent_icon_key(ch)
		if parent_key != "":
			var pcol := PUi.vbox(1)
			pcol.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			pcol.add_child(PUi.rich("[color=#9ea8b8]붙는 곳[/color]", 10))
			pcol.add_child(PUi.icon_of(parent_key, 30.0, "", "", 0.0, 0))
			irow.add_child(pcol)
		b.add_child(irow)
		b.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.esc(String(d.title)), 15))
		b.add_child(PUi.rich("[color=#9ea8b8]%s[/color]%s" % [PGlossaryTip.esc(String(d.type)), "  [color=#ffe066]지역 계열[/color]" if bool(d.regionMatch) else ""], 12))
		var sc := PUi.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var inner := PUi.vbox(4)
		sc.add_child(inner)
		inner.add_child(PUi.rich(PGlossaryTip.esc(String(d.change)), 14))
		var pv := preview_line(run, ch)
		if pv != "":
			PUi.kv(inner, "적용 전 → 후", pv, 12)
		PUi.kv(inner, "단계", PGlossaryTip.esc(String(d.stage)), 12)
		PUi.kv(inner, "적용", PGlossaryTip.esc(String(d.scope)), 12)
		PUi.kv(inner, "슬롯", PGlossaryTip.esc(String(d.slot)), 12)
		b.add_child(sc)
		var key := String(ch.key)
		var btn := PUi.button("선택", func(): picked.emit(key), true, 15)
		btn.custom_minimum_size = Vector2(0, PLayout.primary_button_height()) # 터치 대상 크기
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

# ---------- 아이콘·미리보기(표시 전용) ----------
## 후보 하나의 아이콘 키. 아이콘이 없으면 PIconTile이 중립 자리표시 + 실제 이름을 그린다(다른 효과 아이콘 재사용 금지)
static func icon_key(c: Dictionary) -> String:
	var kind := String(c.get("kind", ""))
	var id := String(c.get("id", ""))
	match kind:
		"weapon_new", "weapon_level":
			return PIcons.weapon_key(id)
		"weapon_mod":
			return PIcons.mod_key(id, String(c.get("mod", "")))
		"common":
			return "common:" + id
		"passive":
			return "passive:" + id
		"skill_new", "skill_level":
			return "skill:slowfield" if String(c.get("slot", "")) == "q" else PIcons.e_key(id)
		"skill_variant":
			return "skill:slowfield" if String(c.get("slot", "")) == "q" else PIcons.e_key(id, String(c.get("variant", "")))
		"boss_reward":
			return "reward:" + id
	return ""

## 이 후보가 '어디에 붙는지'(상위 기술)의 작은 아이콘 키. 붙을 곳이 없으면 ""
static func parent_icon_key(c: Dictionary) -> String:
	var kind := String(c.get("kind", ""))
	match kind:
		"weapon_mod", "weapon_level":
			return PIcons.weapon_key(String(c.get("id", "")))
		"skill_variant", "skill_level":
			return "skill:slowfield" if String(c.get("slot", "")) == "q" else PIcons.e_key(String(c.get("id", "")))
	return ""

## 변경 전/후 한 줄(실제 규칙 PBuild.preview_with_choice을 격리 사본에 적용해 얻는다).
## 본 전투·경험치·난수·저장은 절대 진행되지 않는다(run.duplicate(true) 사본만 쓴다).
static func preview_line(run: Dictionary, c: Dictionary) -> String:
	if run.is_empty():
		return ""
	var kind := String(c.get("kind", ""))
	var before := PBuild.derive(run)
	var after := PBuild.preview_with_choice(run, c)
	match kind:
		"weapon_mod", "weapon_level", "weapon_new":
			var wid := String(c.get("id", ""))
			var w0 := _find_w(before, wid)
			var w1 := _find_w(after, wid)
			if w1.is_empty():
				return ""
			var mods0: int = (w0.get("mods", []) as Array).size() if not w0.is_empty() else 0
			var mods1: int = (w1.get("mods", []) as Array).size()
			if w0.is_empty():
				return "새 슬롯 · 피해 %s · 주기 %s초" % [PUi.fmt(float(w1.damage)), PUi.fmt(float(w1.interval))]
			return "피해 %s → %s · 개조 %d → %d" % [PUi.fmt(float(w0.damage)), PUi.fmt(float(w1.damage)), mods0, mods1]
		"passive", "common":
			var parts: Array = []
			if not is_equal_approx(float(before.hp_max), float(after.hp_max)):
				parts.append("최대 체력 %d → %d" % [int(float(before.hp_max)), int(float(after.hp_max))])
			if not is_equal_approx(float(before.damage_mult), float(after.damage_mult)):
				parts.append("피해 ×%s → ×%s" % [PUi.fmt(float(before.damage_mult)), PUi.fmt(float(after.damage_mult))])
			if not is_equal_approx(float(before.speed_mult), float(after.speed_mult)):
				parts.append("이동 ×%s → ×%s" % [PUi.fmt(float(before.speed_mult)), PUi.fmt(float(after.speed_mult))])
			if not is_equal_approx(float(before.range_mult), float(after.range_mult)):
				parts.append("사거리 ×%s → ×%s" % [PUi.fmt(float(before.range_mult)), PUi.fmt(float(after.range_mult))])
			if not is_equal_approx(float(before.width_mult), float(after.width_mult)):
				parts.append("범위 ×%s → ×%s" % [PUi.fmt(float(before.width_mult)), PUi.fmt(float(after.width_mult))])
			if not is_equal_approx(float(before.interval_mult), float(after.interval_mult)):
				parts.append("주기 ×%s → ×%s" % [PUi.fmt(float(before.interval_mult)), PUi.fmt(float(after.interval_mult))])
			return " · ".join(parts)
	return ""

static func _find_w(b: Dictionary, id: String) -> Dictionary:
	for s in b.get("weapons", []):
		if String(s.id) == id:
			return s
	return {}
