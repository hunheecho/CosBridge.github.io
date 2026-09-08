class_name PScreen
extends Control
## 화면 공통 뼈대: 배경 + 여백 + (상단 줄 · 스크롤 본문 · 하단 줄). 각 화면은 _build()에서 고정 틀을, refresh()에서 회차 상태로 내용을 다시 만든다.
## 화면은 규칙을 계산하지 않는다: main(회차 흐름)과 PRun/PBuild/PGrowth/PFlow가 준 값을 표시하고, 버튼은 main의 함수를 부른다.

var main: Node = null
var root: VBoxContainer
var top: VBoxContainer
var body: VBoxContainer
var bottom: HBoxContainer
var scroll: ScrollContainer
var default_button: Button = null
var _margin: MarginContainer          # 여백 = 기본(14·10) + 안전 영역 밖(PLayout.margins)
var _bucket := ""                      # 마지막 refresh 때의 화면 비율 묶음(wide/standard/narrow)
var _modal: Control                    # 확인 창 층(휴식·판매·구매 뒤 선택 — 모든 화면 공용)
var _modal_box: VBoxContainer
var _modal_token := 0                  # 확인 창마다 새 번호. 확정하면 번호가 올라 그 창의 버튼은 모두 무효가 된다(중복 클릭 방지)
var _modal_prev_default: Button = null # 확인 창을 열기 전의 기본 버튼(취소하면 Enter가 원래 행동으로 돌아간다)

func setup(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = PUi.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = margin
	_apply_safe_margins()
	add_child(margin)
	root = PUi.vbox(8)
	margin.add_child(root)
	top = PUi.vbox(6)
	root.add_child(top)
	scroll = PUi.scroll()
	root.add_child(scroll)
	body = PUi.vbox(8)
	scroll.add_child(body)
	bottom = PUi.hbox(10)
	root.add_child(bottom)
	_make_modal()
	_build()

# ---------- 확인 창(모든 화면 공용) ----------
## 결정 전에 무엇이 오가는지 보여 주고, 취소하면 아무것도 바뀌지 않는다(사용자 지시 2026-09-09).
## 확정은 한 번만 실행된다 — 창마다 번호를 매기고 확정 순간 번호를 올려, 같은 창의 버튼이 다시 눌려도 아무 일도 하지 않는다.
func _make_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.1, 0.12, 0.15, 0.98), 8, 16, Color(0.5, 0.6, 0.75, 0.9)))
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	_modal_box = PUi.vbox(8)
	panel.add_child(_modal_box)
	_modal.visible = false
	add_child(_modal)

func confirm_open() -> bool:
	return _modal != null and _modal.visible

func close_confirm() -> void:
	_modal_token += 1
	if _modal != null and _modal.visible:
		_modal.visible = false
		if _modal_prev_default != null and is_instance_valid(_modal_prev_default):
			default_button = _modal_prev_default # 취소 뒤 Enter가 원래 주 행동으로 돌아간다
	_modal_prev_default = null

## title = 큰 물음 줄, fill(box) = 결정에 필요한 내용(비용·전후 수치·부작용), actions = [{text, cb}]
## 취소 버튼은 항상 마지막에 붙는다.
func open_confirm(title: String, fill: Callable, actions: Array, cancel_text: String = "취소 (Esc)") -> void:
	PUi.clear(_modal_box)
	if not _modal.visible: # 창 안에서 다른 창으로 넘어갈 때는 처음의 기본 버튼을 그대로 들고 간다
		_modal_prev_default = default_button
	_modal_token += 1
	var tok := _modal_token
	_modal_box.add_child(PUi.rich("[b]%s[/b]" % title, 20))
	if fill.is_valid():
		fill.call(_modal_box)
	var row := PUi.hbox(8)
	var first: Button = null
	for a in actions:
		var act: Dictionary = a
		var cb: Callable = act.cb
		var btn := PUi.button(String(act.text), func(): _confirm_run(tok, cb), true, 15)
		btn.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		row.add_child(btn)
		if first == null:
			first = btn
	row.add_child(PUi.button(cancel_text, func(): close_confirm(), true, 15))
	_modal_box.add_child(row)
	default_button = first
	_modal.visible = true

## 확정 한 번만: 이 창의 번호가 아직 살아 있을 때만 처리하고, 처리하면서 번호를 올린다
func _confirm_run(tok: int, cb: Callable) -> void:
	if tok != _modal_token:
		return
	_modal_token += 1
	_modal.visible = false
	if cb.is_valid():
		cb.call()

## 판매 확인 창(거점 아이콘·장비 화면·상점이 같은 창을 쓴다).
## 받을 금액을 그대로 적고, 장착 중이면 해제된다는 것을 함께 말한다. 취소하면 금화·가방·장착이 그대로다.
## 확정은 한 번만 실행되므로 중복 클릭으로 같은 장비가 두 번 팔리지 않는다.
func open_sell_confirm(id: String) -> void:
	var r := run()
	if r.is_empty():
		return
	var nm := PRun.equip_name(id)
	var price := PRun.sell_price(id)
	open_confirm("%s%s %d금에 판매할까요?" % [PGlossaryTip.esc(nm), PUi.josa(nm, "을", "를"), price],
		_sell_body.bind(r, id, price), [{ "text": "판매한다", "cb": func(): main.sell_equipment(id) }])

func _sell_body(box: VBoxContainer, r: Dictionary, id: String, price: int) -> void:
	var slot := ""
	for sl in PCatalog.world().equip_slots:
		var s := String(sl)
		if r.equipment.get(s, null) != null and String(r.equipment[s]) == id:
			slot = s
	PUi.kv(box, "받을 금액", "[color=#ffd966][b]+%d금[/b][/color] [color=#9ea8b8](금화 %d → %d)[/color]" % [price, int(r.gold), int(r.gold) + price], 15)
	if slot != "":
		var dup: Dictionary = r.duplicate(true)
		PRun.unequip_item(dup, slot)
		box.add_child(PUi.rich("[color=#ff8c73]지금 %s 칸에 장착 중입니다 — 팔면 해제됩니다.[/color]" % PUi.slot_name(slot), 14))
		PUi.kv(box, "해제하면", PUi.diff_text(PBuild.derive(r), PBuild.derive(dup)), 13)
	else:
		PUi.kv(box, "있는 곳", "[b]%s[/b]" % PGlossaryTip.term("bag", "가방"), 14)
	box.add_child(PUi.rich("[color=#9ea8b8]취소하면 금화·가방·장착이 그대로입니다. 판 장비는 되사올 수 없습니다.[/color]", 12))

func run() -> Dictionary:
	return main.run

func _build() -> void:
	pass

func refresh() -> void:
	pass

func on_enter() -> void:
	default_button = null
	_apply_safe_margins()
	_bucket = bucket()
	refresh()
	scroll.scroll_vertical = 0

## 화면 비율 묶음(PLayout): 화면들이 열 비율·마을 높이를 고를 때 쓴다
func bucket() -> String:
	return PLayout.bucket_of(get_viewport()) if is_inside_tree() else "standard"

func _apply_safe_margins() -> void:
	if _margin == null or not is_inside_tree():
		return
	PLayout.apply_margins(_margin, get_viewport(), 14, 10)

## 창 크기 변경: 여백 갱신, 비율 묶음이 바뀐 보이는 화면은 다시 만든다
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and _margin != null:
		_apply_safe_margins()
		if visible and _bucket != "" and bucket() != _bucket:
			_bucket = bucket()
			refresh()

## Esc: 화면 안의 하위 상태를 닫았으면 true. 확인 창이 열려 있으면 먼저 닫는다(아무것도 바뀌지 않는다)
func on_escape() -> bool:
	if confirm_open():
		close_confirm()
		return true
	return false

func clear_all() -> void:
	PUi.clear(top)
	PUi.clear(body)
	PUi.clear(bottom)

func heading(text: String, sub: String = "") -> void:
	top.add_child(PUi.rich("[b]%s[/b]%s" % [text, ("  [color=#9ea8b8]%s[/color]" % sub) if sub != "" else ""], 22))

## 두 칸 가로 배치(왼쪽 넓게)
func two_cols(left_ratio: float = 0.55) -> Dictionary:
	var h := PUi.hbox(12)
	var l := PUi.vbox(8)
	l.size_flags_stretch_ratio = left_ratio
	var r := PUi.vbox(8)
	r.size_flags_stretch_ratio = 1.0 - left_ratio
	h.add_child(l)
	h.add_child(r)
	body.add_child(h)
	return { "left": l, "right": r }
