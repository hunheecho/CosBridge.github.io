class_name PChoiceOverlay
extends Control
## 3택 오버레이(레벨업·임무 보상·보스 희귀 보상·지역 보상·개조/변형 변경, HTML levelCards). 열려 있는 동안 다른 입력을 막는다(배경이 마우스를 삼킨다).
## 카드 내용은 PGrowth.describe(run, choice)가 준 것만 보여 준다(수치 계산 없음). 전투 중 정지는 main이 한다.
##
## 사람 플레이 뒤 요구(2026-09-08):
##  - 선택 중에 지금 보유한 빌드를 볼 수 있어야 한다('내 빌드 보기' — 기술별 개조와 공용·패시브를 구분해서).
##  - 상세를 보고 같은 3택으로 돌아와도 재추첨·자동 선택·전투 재개가 없어야 한다.
##    → 상세·빌드 보기는 오버레이를 닫지 않고 같은 offer를 그대로 다시 그린다(_render). 후보 생성(PGrowth.generate_offer)은 절대 다시 부르지 않는다.
##  - 카드 기본 화면은 이름 · 핵심 효과 · 전/후만. 단계·적용 범위·슬롯·계산식은 카드의 '상세'에 둔다.

signal picked(key: String)
signal skipped()
signal rerolled()

var offer: Dictionary = {}
var _run: Dictionary = {}
var _detail := ""             # 상세를 펼친 카드의 key("" = 없음)
var _build_open := false      # '내 빌드 보기'를 펼쳤는가
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
	_run = run
	_detail = ""
	_build_open = false
	_render()
	visible = true

## 같은 3택을 다시 그린다(상세 열기·닫기, 내 빌드 보기). 후보·난수·저장은 건드리지 않는다
func _render() -> void:
	PUi.clear(_box)
	var run := _run
	var off := offer
	var pool := String(off.get("pool", "level"))
	var g: Dictionary = run.get("growth", {})
	var title := ""
	match pool:
		"boss": title = "보스 희귀 보상"
		"deep": title = "지역 보상 선택"
		"mission":
			var kt: Dictionary = PCatalog.mission_rules().kindText
			title = "%s · %s" % [("개조·변형 변경" if off.get("paidChange", null) != null else "임무 보상"), String(kt.get(String(off.get("missionKind", "")), "3택"))]
		_:
			title = "레벨 업! Lv %d" % int(g.get("level", 1))
			if int(g.get("pendingLevelUps", 0)) > 1:
				title += " (남은 선택 %d)" % int(g.pendingLevelUps)
			if off.get("steer", null) != null:
				title += "  [color=#ffe066]예약: %s[/color]" % PSortie.kind_name(String(off.steer))
	var head := PUi.hbox(10)
	head.add_child(PUi.rich("[b]%s[/b]" % title, 22))
	head.add_child(PUi.spacer())
	# 선택을 취소하거나 다시 뽑지 않고, 지금 보유한 빌드만 펼쳐 본다
	var bbtn := PUi.button("내 빌드 닫기 ▼" if _build_open else "내 빌드 보기 ▶", func(): _build_open = not _build_open; _render(), true, 15)
	bbtn.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	head.add_child(bbtn)
	_box.add_child(head)
	var rid = off.get("regionId", null)
	if rid != null and String(rid) != "" and pool != "boss":
		_box.add_child(PUi.rich("[color=#9ea8b8]지역 계열: %s[/color]" % PGlossaryTip.esc(String(PCatalog.region_tag_text().get(String(rid), "—"))), 13))
	if _build_open:
		_box.add_child(_build_view(run))
	var row := PUi.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(row)
	var choices: Array = off.get("choices", [])
	if choices.is_empty():
		row.add_child(PUi.rich("[color=#9ea8b8]제시할 수 있는 후보가 없습니다.[/color]", 15))
	for c in choices:
		row.add_child(_card(run, c))
	var bottom := PUi.hbox(10)
	_box.add_child(bottom)
	if pool == "level":
		bottom.add_child(PUi.button("건너뛰기 (금화 +%d)" % int(PCatalog.config().SKIP_AUGMENT_GOLD), func(): skipped.emit(), true, 14))
		if PRun.has_service(run, "reroll"):
			bottom.add_child(PUi.button("제시 재선택권 사용 (남은 %d)" % int(run.services.reroll), func(): rerolled.emit(), true, 14))
	elif pool == "deep" or pool == "mission":
		bottom.add_child(PUi.button("받지 않음", func(): skipped.emit(), true, 14))

## 후보 카드 한 장: 아이콘 · 이름 · 핵심 효과 · 전/후 · [선택] · [상세]
func _card(run: Dictionary, c: Variant) -> Control:
	var ch: Dictionary = c
	var d := PGrowth.describe(run, ch)
	var key := String(ch.key)
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
		pcol.add_child(PUi.rich("[color=#9ea8b8]붙는 곳[/color]", 11))
		pcol.add_child(PUi.icon_of(parent_key, 30.0, "", "", 0.0, 0))
		irow.add_child(pcol)
	b.add_child(irow)
	b.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.esc(String(d.title)), 18))
	b.add_child(PUi.rich("[color=#9ea8b8]%s[/color]%s" % [PGlossaryTip.esc(String(d.type)), "  [color=#ffe066]지역 계열[/color]" if bool(d.regionMatch) else ""], 13))
	b.add_child(PUi.rich(PGlossaryTip.esc(String(d.change)), 15))
	# 재사용 시간이 바뀌는 후보: 최종 시간의 전 → 후만 크게(계산식은 상세에)
	var cd := cd_change(run, ch)
	if not cd.is_empty():
		b.add_child(PUi.rich("[color=#9ea8b8]재사용[/color]  [b]%s초[/b] [color=#ffe066]→[/color] [b]%s초[/b]" % [PUi.fmt(float(cd.before)), PUi.fmt(float(cd.after))], 20))
	var pv := preview_line(run, ch)
	if pv != "":
		b.add_child(PUi.rich("[color=#9ea8b8]적용 전 → 후[/color]  %s" % pv, 14))
	b.add_child(PUi.spacer())
	var btn := PUi.button("선택", func(): picked.emit(key), true, 17)
	btn.custom_minimum_size = Vector2(0, PLayout.primary_button_height()) # 터치 대상 크기
	b.add_child(btn)
	# 상세: 같은 3택 위에서 펼치고 접는다(닫아도 다시 뽑지 않는다)
	var open_now: bool = _detail == key
	var dt := PUi.button("상세 닫기 ▼" if open_now else "상세 보기 ▶", func(): _detail = ("" if open_now else key); _render(), true, 13)
	dt.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	b.add_child(dt)
	if open_now:
		var sc := PUi.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var inner := PUi.vbox(4)
		sc.add_child(inner)
		PUi.kv(inner, "단계", PGlossaryTip.esc(String(d.stage)), 13)
		PUi.kv(inner, "적용", PGlossaryTip.esc(String(d.scope)), 13)
		PUi.kv(inner, "슬롯", PGlossaryTip.esc(String(d.slot)), 13)
		if not cd.is_empty():
			PUi.kv(inner, "계산식", PGlossaryTip.esc(String(cd.formula)), 13)
		b.add_child(sc)
	return p

## 지금 보유한 빌드(선택 중 확인용): 기술별 개조와 공용·패시브를 구분해서 보여 준다
func _build_view(run: Dictionary) -> Control:
	var c := PUi.card("지금 내 빌드 [color=#9ea8b8]기술 아래 = 그 기술의 개조[/color]", PUi.CARD_OFF, 15)
	var box: VBoxContainer = c.box
	box.add_child(PUi.build_icon_row(run, 40.0, 24.0))
	var g: Dictionary = run.get("growth", {})
	var qe := []
	var SK := PCatalog.skills()
	var b := PBuild.derive(run)
	for slot in ["q", "e"]:
		var sk = g.get("skills", {}).get(slot, null)
		if sk == null:
			qe.append("[b]E[/b] [color=#6a7078]미보유[/color]")
			continue
		var d: Dictionary = SK[String(sk.id)]
		qe.append("[b]%s[/b] %s Lv%d [color=#9ea8b8]재사용 %s초[/color]" % [String(d.key), PGlossaryTip.esc(String(d.name)), int(sk.level), PUi.fmt(PBuildDetail.cd_of_build(b, String(slot)))])
	box.add_child(PUi.rich(" · ".join(qe), 14))
	box.add_child(PUi.rich("[color=#9ea8b8]공용 증강 · 패시브[/color] [color=#6a7078](기술 개조와 별개 — 모든 자동기술에 적용)[/color]", 13))
	box.add_child(PUi.common_icon_row(run, 26.0))
	return c.panel

func close() -> void:
	offer = {}
	_run = {}
	_detail = ""
	_build_open = false
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

## 수동 기술 재사용 시간의 전 → 후({} = 이 후보로는 바뀌지 않음).
## 계산은 규칙(PBuild.derive · PBuild.preview_with_choice)이 낸 값을 읽기만 한다 — 표시를 쉽게 하려고 계산 규칙을 바꾸지 않는다.
## formula: 어떤 기본값에 어떤 배율이 곱해졌는지(감속장 Lv별 기본 [14,12,10]초 × 집중 등).
static func cd_change(run: Dictionary, c: Dictionary) -> Dictionary:
	if run.is_empty():
		return {}
	var kind := String(c.get("kind", ""))
	var slot := String(c.get("slot", ""))
	var slots: Array = []
	match kind:
		"skill_new", "skill_level", "skill_variant":
			slots = [slot] if slot != "" else ["q", "e"]
		"passive", "common", "boss_reward":
			slots = ["q", "e"] # 집중·박자 등 배율이 바뀌는 후보
		_:
			return {}
	var before := PBuild.derive(run)
	var after := PBuild.preview_with_choice(run, c)
	for s in slots:
		var sl := String(s)
		var b0 := PBuildDetail.cd_of_build(before, sl)
		var b1 := PBuildDetail.cd_of_build(after, sl)
		if b1 <= 0.0 or is_equal_approx(b0, b1):
			continue
		return { "slot": sl, "before": b0, "after": b1, "formula": _cd_formula(after, sl) }
	return {}

## 계산식 한 줄: 기본(레벨별) × 배율 = 최종. 값은 모두 규칙이 낸 것을 읽어 적는다
static func _cd_formula(b: Dictionary, slot: String) -> String:
	var sk = b.get("skills", {}).get(slot, null)
	if sk == null:
		return ""
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	var lv: int = mini(3, int(sk.level))
	var base: float = float(d.cooldown[lv - 1])
	var slot_mult: float = float(b.get("q_cd_mult", 1.0)) if slot == "q" else float(b.get("e_cd_mult", 1.0))
	var mult: float = float(b.get("skill_cd_mult", 1.0)) * slot_mult
	var levels := []
	for v in d.cooldown:
		levels.append(PUi.fmt(float(v)))
	return "%s Lv%d 기본 %s초(레벨별 %s) × 배율 %s = %s초" % [String(d.name), int(sk.level), PUi.fmt(base), "/".join(levels), PUi.fmt(mult), PUi.fmt(PBuildDetail.cd_of_build(b, slot))]

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
