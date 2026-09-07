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
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
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
	_build()

func run() -> Dictionary:
	return main.run

func _build() -> void:
	pass

func refresh() -> void:
	pass

func on_enter() -> void:
	default_button = null
	refresh()
	scroll.scroll_vertical = 0

## Esc: 화면 안의 하위 상태를 닫았으면 true
func on_escape() -> bool:
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
