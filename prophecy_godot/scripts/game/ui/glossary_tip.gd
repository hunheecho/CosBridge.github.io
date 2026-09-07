class_name PGlossaryTip
extends Control
## 용어 사전 툴팁 층(GAME_SPEC §19.11, HTML glossary.js 이식). 본문의 {{id}}는 밑줄 링크([url=id])가 되고,
## 마우스를 올리면 툴팁(short + body), 클릭하면 고정(중첩 가능, 최대 4단계), Esc·바깥 클릭으로 닫힌다. 툴팁은 항상 창 안에 놓인다.
## 전투 중에는 고정(클릭)한 툴팁이 있을 때만 정지한다(pin_count_changed 신호를 main이 받는다). 마우스 이동만으로는 정지하지 않는다.
## 용어 데이터는 data/glossary.json(PCatalog.glossary())만 읽는다.

signal pin_count_changed(n: int)

const TIP_W := 340.0
const MAX_PIN := 4

static var layer: PGlossaryTip = null

var _hover: Dictionary = {}      # {panel, id}
var _pinned: Array = []          # [{panel, id}]
var _hover_grace: float = -1.0   # 링크에서 마우스가 떠난 뒤 남은 유예(<0 = 링크 위)
var _link_click_frame: int = -1
var _outside_click_frame: int = -1

static func G() -> Dictionary: return PCatalog.glossary()

static func has_term(id: String) -> bool: return G().has(id)

## BBCode 특수문자 보호
static func esc(s: String) -> String:
	return s.replace("[", "[lb]")

## 본문의 {{id}}를 용어 링크로 바꾼다(없는 id는 이름 그대로). BBCode는 그대로 두므로 데이터 문자열은 호출자가 esc()로 감싼다
static func markup(text: String) -> String:
	if text.find("{{") < 0:
		return text
	var out := ""
	var i := 0
	while true:
		var a := text.find("{{", i)
		if a < 0:
			out += text.substr(i)
			break
		var b := text.find("}}", a)
		if b < 0:
			out += text.substr(i)
			break
		out += text.substr(i, a - i)
		out += term(text.substr(a + 2, b - a - 2), "")
		i = b + 2
	return out

## 밑줄 용어. text가 비어 있으면 사전의 이름
static func term(id: String, text: String = "") -> String:
	var d: Dictionary = G().get(id, {})
	if d.is_empty():
		return esc(text if text != "" else id)
	return "[url=%s]%s[/url]" % [id, esc(text if text != "" else String(d.name))]

## RichTextLabel의 링크 신호를 툴팁 층에 연결한다
static func bind(rtl: RichTextLabel) -> void:
	if layer == null:
		return
	rtl.meta_hover_started.connect(layer._on_hover_start)
	rtl.meta_hover_ended.connect(layer._on_hover_end)
	rtl.meta_clicked.connect(layer._on_click)

func _ready() -> void:
	layer = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	set_process_input(true)

func pin_count() -> int:
	return _pinned.size()

func has_any() -> bool:
	return not _hover.is_empty() or not _pinned.is_empty()

# ---------- 툴팁 만들기 ----------
func _make_tip(id: String, pinned: bool) -> PanelContainer:
	var d: Dictionary = G()[id]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.09, 0.11, 0.14, 0.98), 6, 8, Color(0.6, 0.8, 1.0, 0.8) if pinned else Color(0.4, 0.45, 0.55, 0.8)))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.custom_minimum_size = Vector2(TIP_W, 0)
	p.size = Vector2(TIP_W, 0)
	var v := PUi.vbox(4)
	p.add_child(v)
	var head := PUi.hbox(6)
	var name_l := PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [esc(String(d.name)), esc(String(d.short))], 13)
	head.add_child(name_l)
	if pinned:
		var close := PUi.button("×", func(): _close_from(p), true, 12)
		close.custom_minimum_size = Vector2(22, 22)
		close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		head.add_child(close)
	v.add_child(head)
	var body := PUi.rich(String(d.body), 12)
	v.add_child(body)
	var rel: Array = d.get("related", [])
	if rel.size() > 0:
		var parts := []
		for r in rel:
			parts.append(term(String(r), ""))
		v.add_child(PUi.rich("[color=#9ea8b8]관련:[/color] " + " · ".join(parts), 11))
	if not pinned:
		v.add_child(PUi.rich("[color=#6a7078]클릭하면 고정 · Esc로 닫기[/color]", 10))
	add_child(p)
	return p

func _place(p: PanelContainer, at: Vector2) -> void:
	var vs := get_viewport_rect().size
	var sz := p.get_combined_minimum_size()
	sz.x = maxf(sz.x, TIP_W)
	var x := at.x + 8.0
	var y := at.y + 18.0
	if x + sz.x > vs.x - 8.0:
		x = maxf(8.0, vs.x - 8.0 - sz.x)
	if y + sz.y > vs.y - 8.0:
		y = maxf(8.0, at.y - 8.0 - sz.y)
	if y < 8.0:
		y = 8.0
	p.position = Vector2(x, y)

func _clamp_all() -> void:
	var vs := get_viewport_rect().size
	var all := []
	if not _hover.is_empty():
		all.append(_hover.panel)
	for t in _pinned:
		all.append(t.panel)
	for pp in all:
		var p: PanelContainer = pp
		var sz := p.size
		var pos := p.position
		pos.x = clampf(pos.x, 8.0, maxf(8.0, vs.x - 8.0 - sz.x))
		pos.y = clampf(pos.y, 8.0, maxf(8.0, vs.y - 8.0 - sz.y))
		p.position = pos

func _pinned_has(id: String) -> bool:
	for t in _pinned:
		if String(t.id) == id:
			return true
	return false

func _remove_hover() -> void:
	if _hover.is_empty():
		return
	(_hover.panel as Node).queue_free()
	_hover = {}
	_hover_grace = -1.0

# ---------- 링크 신호 ----------
func _on_hover_start(meta: Variant) -> void:
	var id := String(meta)
	if not has_term(id) or _pinned_has(id):
		return
	if not _hover.is_empty() and String(_hover.id) == id:
		_hover_grace = -1.0
		return
	_remove_hover()
	var p := _make_tip(id, false)
	_hover = { "panel": p, "id": id }
	_hover_grace = -1.0
	_place(p, get_viewport().get_mouse_position())

func _on_hover_end(_meta: Variant) -> void:
	if not _hover.is_empty():
		_hover_grace = 0.35

func _on_click(meta: Variant) -> void:
	var id := String(meta)
	if not has_term(id):
		return
	_link_click_frame = Engine.get_process_frames()
	if _pinned_has(id):
		return
	var at := get_viewport().get_mouse_position()
	if not _hover.is_empty() and String(_hover.id) == id:
		at = (_hover.panel as Control).position - Vector2(8.0, 18.0)
		_remove_hover()
	if _pinned.size() >= MAX_PIN:
		_pop_last()
	var p := _make_tip(id, true)
	_pinned.append({ "panel": p, "id": id })
	_place(p, at)
	pin_count_changed.emit(_pinned.size())

# ---------- 닫기 ----------
func _pop_last() -> void:
	if _pinned.is_empty():
		return
	var t: Dictionary = _pinned.pop_back()
	(t.panel as Node).queue_free()

func close_last() -> bool:
	if not _hover.is_empty():
		_remove_hover()
		return true
	if _pinned.is_empty():
		return false
	_pop_last()
	pin_count_changed.emit(_pinned.size())
	return true

func close_all() -> void:
	_remove_hover()
	var had := _pinned.size() > 0
	while not _pinned.is_empty():
		_pop_last()
	if had:
		pin_count_changed.emit(0)

## 고정 툴팁 하나를 닫으면 그 뒤에 열린 것도 같이 닫힌다(HTML과 동일)
func _close_from(p: PanelContainer) -> void:
	var idx := -1
	for i in _pinned.size():
		if _pinned[i].panel == p:
			idx = i
	if idx < 0:
		return
	while _pinned.size() > idx:
		_pop_last()
	pin_count_changed.emit(_pinned.size())

func _inside_any(pos: Vector2) -> bool:
	if not _hover.is_empty() and (_hover.panel as Control).get_global_rect().has_point(pos):
		return true
	for t in _pinned:
		if (t.panel as Control).get_global_rect().has_point(pos):
			return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if not _pinned.is_empty() and not _inside_any(event.position):
			_outside_click_frame = Engine.get_process_frames()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and has_any():
		close_last()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	var frame := Engine.get_process_frames()
	# 바깥 클릭(링크 클릭이 아닌): 모두 닫기. 링크 클릭은 같은 프레임에 _on_click이 먼저 기록한다
	if _outside_click_frame == frame and _link_click_frame != frame:
		_outside_click_frame = -1
		close_all()
	elif _outside_click_frame >= 0 and _outside_click_frame < frame:
		_outside_click_frame = -1
	if not _hover.is_empty() and _hover_grace >= 0.0:
		var inside := (_hover.panel as Control).get_global_rect().has_point(get_viewport().get_mouse_position())
		if inside:
			_hover_grace = 0.2
		else:
			_hover_grace -= dt
			if _hover_grace < 0.0:
				_remove_hover()
	_clamp_all()
