class_name PGlossaryTip
extends Control
## 용어 사전 툴팁 층(GAME_SPEC §19.11, HTML glossary.js 이식). 본문의 {{id}}는 밑줄 링크([url=id])가 되고,
## 마우스를 올리면 툴팁(short + body), 클릭하면 고정(중첩 가능, 최대 4단계), Esc·바깥 클릭으로 닫힌다. 툴팁은 항상 안전 영역(PLayout.safe_rect) 안에 놓인다.
## 터치(hover 없음): 밑줄 용어를 탭하면 고정 툴팁이 열리고, 같은 용어를 다시 탭하거나 바깥을 탭하면 닫힌다(마우스도 같은 규칙). hover만으로 닿는 정보는 없다.
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
		var cs: float = 36.0 if PLayout.is_touch() else 22.0 # 터치면 닫기 대상도 크게
		close.custom_minimum_size = Vector2(cs, cs)
		close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		head.add_child(close)
	v.add_child(head)
	var body_text := String(d.body)
	if id.begins_with("w:"):
		var made := weapon_body(id.substr(2))
		if made != "":
			body_text = made
	var body := PUi.rich(body_text, 13)
	v.add_child(body)
	var rel: Array = d.get("related", [])
	if rel.size() > 0:
		var parts := []
		for r in rel:
			parts.append(term(String(r), ""))
		v.add_child(PUi.rich("[color=#9ea8b8]관련:[/color] " + " · ".join(parts), 11))
	if not pinned:
		v.add_child(PUi.rich("[color=#6a7078]클릭하면 고정 · Esc로 닫기[/color]", 10))
	elif PLayout.is_touch():
		v.add_child(PUi.rich("[color=#6a7078]용어를 다시 누르거나 바깥을 누르면 닫힘[/color]", 10))
	add_child(p)
	return p

## 자동기술 툴팁 본문: 기본 공격 / 현재 개조 / 추가 효과 / 수치로 문단을 나눈다.
## 지금 붙어 있지 않은 개조는 절대 '현재 개조'와 섞지 않는다(아직 없는 효과를 지금 효과처럼 읽지 않게).
## 현재 빌드는 회차(main.cur_run)를 읽기만 한다 — 없으면 카탈로그 기본값만 적는다.
static func weapon_body(wid: String) -> String:
	var W := PCatalog.weapons()
	if not W.has(wid):
		return ""
	var d: Dictionary = W[wid]
	var run := _run_of_layer()
	var owned: Array = []
	var ws: Dictionary = {}
	var level := 0
	if not run.is_empty():
		var b := PBuild.derive(run)
		for w in b.get("weapons", []):
			if String(w.id) == wid:
				ws = w
				owned = (w.get("mods", []) as Array).duplicate()
				level = int(w.level)
	var out: Array = []
	out.append("[b]기본 공격[/b]")
	var base: Dictionary = d.get("base", {})
	out.append(PUi.weapon_base_text(base)) # 연타 수·간격까지: "피해 6"처럼 실제 화력을 절반으로 읽게 하지 않는다
	out.append("[b]현재 개조[/b]")
	if owned.is_empty():
		out.append("[color=#6a7078]%s[/color]" % ("아직 없음" if not run.is_empty() else "회차 밖 — 보유 개조 없음"))
	else:
		for m in owned:
			var mid := String(m)
			out.append("· [b]%s[/b] %s" % [esc(String(d.mods[mid].name)), esc(String(d.mods[mid].get("desc", "")))])
	var rest: Array = []
	for mid2 in d.mods:
		if owned.has(String(mid2)) or not bool(d.mods[mid2].get("impl", false)):
			continue
		rest.append("· %s %s" % [esc(String(d.mods[mid2].name)), esc(String(d.mods[mid2].get("desc", "")))])
	if rest.size() > 0:
		out.append("[b]추가 효과[/b] [color=#9ea8b8]아직 붙어 있지 않은 개조 후보[/color]")
		for line in rest:
			out.append("[color=#9ea8b8]%s[/color]" % String(line))
	if not ws.is_empty():
		out.append("[b]수치[/b] [color=#9ea8b8]지금 내 빌드[/color]")
		out.append("Lv%d · [b]%s[/b]" % [level, PUi.weapon_stats_text(ws)])
	return "\n".join(out)

## 툴팁 층이 붙어 있는 화면에서 진행 중인 회차를 읽는다(읽기 전용, 없으면 {})
static func _run_of_layer() -> Dictionary:
	if layer == null or not layer.is_inside_tree():
		return {}
	var n: Node = layer
	while n != null:
		if n.has_method("cur_run"):
			var r = n.call("cur_run")
			return r if typeof(r) == TYPE_DICTIONARY else {}
		n = n.get_parent()
	return {}

func _bounds() -> Rect2:
	return PLayout.safe_rect(get_viewport()) if is_inside_tree() else Rect2(0.0, 0.0, PLayout.BASE_W, PLayout.BASE_H)

func _place(p: PanelContainer, at: Vector2) -> void:
	var b := _bounds()
	var sz := p.get_combined_minimum_size()
	sz.x = maxf(sz.x, TIP_W)
	var x := at.x + 8.0
	var y := at.y + 18.0
	if x + sz.x > b.end.x - 8.0:
		x = maxf(b.position.x + 8.0, b.end.x - 8.0 - sz.x)
	if y + sz.y > b.end.y - 8.0:
		y = maxf(b.position.y + 8.0, at.y - 8.0 - sz.y)
	if y < b.position.y + 8.0:
		y = b.position.y + 8.0
	p.position = Vector2(x, y)

func _clamp_all() -> void:
	var b := _bounds()
	var all := []
	if not _hover.is_empty():
		all.append(_hover.panel)
	for t in _pinned:
		all.append(t.panel)
	for pp in all:
		var p: PanelContainer = pp
		var sz := p.size
		var pos := p.position
		pos.x = clampf(pos.x, b.position.x + 8.0, maxf(b.position.x + 8.0, b.end.x - 8.0 - sz.x))
		pos.y = clampf(pos.y, b.position.y + 8.0, maxf(b.position.y + 8.0, b.end.y - 8.0 - sz.y))
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
	if _pinned_has(id): # 이미 고정된 용어를 다시 클릭/탭 → 그 툴팁(과 그 뒤에 연 것)을 닫는다(터치의 열기/닫기 경로)
		for t in _pinned:
			if String(t.id) == id:
				_close_from(t.panel)
				return
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
	elif event is InputEventScreenTouch and event.pressed: # 터치(마우스 에뮬레이션이 꺼져 있어도) 바깥 탭 = 닫기
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
