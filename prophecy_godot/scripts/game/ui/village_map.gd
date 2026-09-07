class_name PVillageMap
extends Control
## 거점 마을 그림(도형만, 외부 에셋·픽셀아트 없음): 대장간 · 상점 · 장비 · 통계·기록 · 휴식 건물 실루엣이 큰 클릭/탭 영역(≥72px)이다.
## 건물마다 투명 Button을 얹어 클릭·탭·키보드 포커스·비활성 표시를 Control이 처리하고, 실루엣은 _draw()가 그린다. 캐릭터가 걸어가는 연출은 없다(사용자 지시).
## 어떤 화면을 여는지는 picked(id) 신호를 받은 거점 화면(base.gd)이 정한다. 규칙 수치 없음.

signal picked(id: String)

const BUILDINGS := [
	{ "id": "forge", "label": "대장간", "x": 0.03, "w": 0.19 },
	{ "id": "shop", "label": "상점", "x": 0.24, "w": 0.19 },
	{ "id": "equip", "label": "장비", "x": 0.45, "w": 0.17 },
	{ "id": "stats", "label": "통계·기록", "x": 0.64, "w": 0.18 },
	{ "id": "rest", "label": "휴식", "x": 0.84, "w": 0.14 },
]
const TOP := 0.16      # 건물 영역 시작(높이 비율)
const GROUND := 0.86   # 지면 선(높이 비율)

var _buttons: Dictionary = {}   # id → Button
var _zones: Dictionary = {}     # id → Rect2

func _init() -> void: # 버튼은 트리에 들어가기 전(set_state 호출 전)에 만든다
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b in BUILDINGS:
		var id := String(b.id)
		var btn := Button.new()
		btn.text = String(b.label)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		btn.add_theme_color_override("font_hover_color", Color(1, 0.92, 0.6))
		btn.add_theme_color_override("font_pressed_color", Color(1, 0.92, 0.6))
		btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
		btn.pressed.connect(func(): picked.emit(id))
		btn.mouse_entered.connect(queue_redraw)
		btn.mouse_exited.connect(queue_redraw)
		btn.focus_entered.connect(queue_redraw)
		btn.focus_exited.connect(queue_redraw)
		add_child(btn)
		_buttons[id] = btn

func _ready() -> void:
	_relayout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()

func zone(id: String) -> Rect2:
	return _zones.get(id, Rect2())

func button(id: String) -> Button:
	return _buttons.get(id, null)

## 건물 버튼의 사용 가능 여부와 라벨(휴식: "휴식 → 오후" 등)
func set_state(id: String, enabled: bool, label: String = "") -> void:
	var b: Button = _buttons.get(id, null)
	if b == null:
		return
	b.disabled = not enabled
	if label != "":
		b.text = label
	queue_redraw()

func _relayout() -> void:
	var W: float = size.x
	var H: float = size.y
	if W <= 0.0 or H <= 0.0:
		return
	var top: float = H * TOP
	var h: float = maxf(PLayout.TOUCH_TARGET, H * (GROUND - TOP) + 22.0) # 지면 아래 라벨 줄까지 포함
	for b in BUILDINGS:
		var id := String(b.id)
		var x: float = W * float(b.x)
		var w: float = maxf(PLayout.TOUCH_TARGET, W * float(b.w))
		var rect := Rect2(x, top, w, h)
		_zones[id] = rect
		var btn: Button = _buttons[id]
		btn.position = rect.position
		btn.size = rect.size
		# 글자를 건물 아래(지면 아래 줄)에 두기 위해 위 여백을 크게 준 투명 스타일
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.content_margin_top = maxf(0.0, h - 26.0)
		sb.content_margin_bottom = 2.0
		sb.content_margin_left = 2.0
		sb.content_margin_right = 2.0
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus", sb)
		btn.add_theme_stylebox_override("disabled", sb)
	queue_redraw()

# ---------- 그리기 ----------
func _draw() -> void:
	var W: float = size.x
	var H: float = size.y
	if W <= 0.0 or H <= 0.0:
		return
	var ground_y: float = H * GROUND
	# 하늘·먼 산·지면
	draw_rect(Rect2(0, 0, W, ground_y), Color(0.11, 0.14, 0.2))
	draw_rect(Rect2(0, 0, W, ground_y * 0.55), Color(0.13, 0.17, 0.25))
	var hills := PackedVector2Array([Vector2(0, ground_y), Vector2(0, ground_y * 0.62), Vector2(W * 0.18, ground_y * 0.42), Vector2(W * 0.36, ground_y * 0.58), Vector2(W * 0.55, ground_y * 0.38), Vector2(W * 0.74, ground_y * 0.56), Vector2(W * 0.9, ground_y * 0.44), Vector2(W, ground_y * 0.6), Vector2(W, ground_y)])
	draw_colored_polygon(hills, Color(0.15, 0.2, 0.2))
	draw_rect(Rect2(0, ground_y, W, H - ground_y), Color(0.2, 0.24, 0.17))
	draw_rect(Rect2(0, ground_y - 3.0, W, 3.0), Color(0.3, 0.36, 0.24))
	# 길(마을을 가로지르는 밝은 띠)
	draw_rect(Rect2(0, ground_y - 14.0, W, 10.0), Color(0.32, 0.28, 0.2, 0.7))
	for b in BUILDINGS:
		var id := String(b.id)
		var z: Rect2 = _zones.get(id, Rect2())
		if z.size.x <= 0.0:
			continue
		var btn: Button = _buttons[id]
		var lit: bool = (btn.is_hovered() or btn.has_focus() or btn.button_pressed) and not btn.disabled
		var dim: bool = btn.disabled
		_draw_building(id, Rect2(z.position.x + 4.0, z.position.y, z.size.x - 8.0, ground_y - z.position.y), lit, dim)
		if lit:
			draw_rect(Rect2(z.position.x + 1.0, z.position.y - 2.0, z.size.x - 2.0, z.size.y + 2.0), Color(1, 0.9, 0.5, 0.9), false, 2.0)

## 건물 실루엣: 종류별 도형(벽·지붕·표지). rect = 건물이 차지하는 영역(아래 변이 지면)
func _draw_building(id: String, r: Rect2, lit: bool, dim: bool) -> void:
	var wall := Color(0.3, 0.27, 0.24) if not dim else Color(0.2, 0.2, 0.2)
	var roof := Color(0.45, 0.28, 0.2) if not dim else Color(0.28, 0.25, 0.24)
	var win := Color(1.0, 0.85, 0.45, 0.9 if lit else 0.6) if not dim else Color(0.5, 0.5, 0.5, 0.4)
	if lit:
		wall = wall.lightened(0.15)
		roof = roof.lightened(0.15)
	var x: float = r.position.x
	var y0: float = r.position.y
	var w: float = r.size.x
	var gy: float = r.end.y
	var body_top: float = y0 + r.size.y * 0.42
	match id:
		"forge": # 낮고 넓은 벽 + 굴뚝 + 모루
			draw_rect(Rect2(x, body_top, w, gy - body_top), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, body_top), Vector2(x + w * 0.5, y0 + r.size.y * 0.18), Vector2(x + w + 4.0, body_top)]), roof)
			draw_rect(Rect2(x + w * 0.68, y0 + r.size.y * 0.05, w * 0.12, body_top - y0 - r.size.y * 0.05), wall.darkened(0.2))
			draw_rect(Rect2(x + w * 0.15, body_top + (gy - body_top) * 0.3, w * 0.3, (gy - body_top) * 0.45), Color(0.95, 0.45, 0.2, 0.85 if lit else 0.6)) # 화덕
			draw_rect(Rect2(x + w * 0.58, gy - 16.0, w * 0.28, 6.0), Color(0.15, 0.15, 0.17)) # 모루
			draw_rect(Rect2(x + w * 0.66, gy - 10.0, w * 0.12, 10.0), Color(0.15, 0.15, 0.17))
		"shop": # 차양(줄무늬) + 진열대
			draw_rect(Rect2(x, body_top, w, gy - body_top), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(x, body_top), Vector2(x + w * 0.5, y0 + r.size.y * 0.22), Vector2(x + w, body_top)]), roof)
			var stripes: int = 5
			var sw: float = w / stripes
			for i in stripes:
				draw_rect(Rect2(x + i * sw, body_top + 4.0, sw, (gy - body_top) * 0.3), Color(0.85, 0.3, 0.3) if i % 2 == 0 else Color(0.95, 0.9, 0.8))
			draw_rect(Rect2(x + w * 0.12, gy - (gy - body_top) * 0.45, w * 0.76, (gy - body_top) * 0.45 - 4.0), win)
		"equip": # 탑 모양 + 방패 표지
			draw_rect(Rect2(x + w * 0.1, y0 + r.size.y * 0.25, w * 0.8, gy - y0 - r.size.y * 0.25), wall)
			for i in 4:
				draw_rect(Rect2(x + w * 0.1 + i * (w * 0.8 / 4.0), y0 + r.size.y * 0.17, w * 0.8 / 8.0, r.size.y * 0.1), wall)
			var cx: float = x + w * 0.5
			var cy: float = body_top + (gy - body_top) * 0.45
			var sr: float = minf(w * 0.22, (gy - body_top) * 0.3)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - sr, cy - sr), Vector2(cx + sr, cy - sr), Vector2(cx + sr, cy + sr * 0.3), Vector2(cx, cy + sr * 1.2), Vector2(cx - sr, cy + sr * 0.3)]), Color(0.55, 0.65, 0.8, 0.9 if lit else 0.7))
			draw_line(Vector2(cx, cy - sr + 3.0), Vector2(cx, cy + sr * 1.0), Color(0.2, 0.25, 0.35), 2.0)
		"stats": # 게시판(기둥 2 + 판자) + 기록 줄
			var px: float = x + w * 0.12
			draw_rect(Rect2(px, body_top, 6.0, gy - body_top), wall.darkened(0.2))
			draw_rect(Rect2(x + w * 0.88 - 6.0, body_top, 6.0, gy - body_top), wall.darkened(0.2))
			var by: float = y0 + r.size.y * 0.3
			draw_rect(Rect2(x + w * 0.05, by, w * 0.9, (gy - by) * 0.62), Color(0.5, 0.42, 0.3) if not dim else wall)
			for i in 3:
				draw_rect(Rect2(x + w * 0.14, by + 8.0 + i * 9.0, w * (0.7 - 0.15 * i), 3.0), Color(0.95, 0.92, 0.85, 0.85 if lit else 0.6))
		"rest": # 집 + 달·창문
			draw_rect(Rect2(x, body_top, w, gy - body_top), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 3.0, body_top), Vector2(x + w * 0.5, y0 + r.size.y * 0.2), Vector2(x + w + 3.0, body_top)]), roof)
			draw_rect(Rect2(x + w * 0.2, body_top + (gy - body_top) * 0.3, w * 0.22, (gy - body_top) * 0.3), win)
			draw_rect(Rect2(x + w * 0.58, body_top + (gy - body_top) * 0.3, w * 0.22, (gy - body_top) * 0.3), win)
			draw_circle(Vector2(x + w * 0.85, y0 + r.size.y * 0.08), 6.0, Color(0.95, 0.95, 0.8, 0.8 if not dim else 0.3))
		_:
			draw_rect(r, wall)
