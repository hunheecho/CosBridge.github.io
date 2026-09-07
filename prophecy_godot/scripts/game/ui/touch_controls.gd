class_name PTouchControls
extends Control
## 가로 화면 터치 오버레이: 왼쪽 가상 스틱(끌기 영역, 누른 자리가 중심) + 오른쪽 버튼(회피 = 누르는 동안 유지·짧게 탭, Q, E). 그림은 도형만.
## 터치 index마다 어느 조작을 잡았는지 기억하므로(스틱 1개 + 버튼별 1개) 스틱을 움직여도 잡고 있는 회피가 풀리지 않고, 왼손 이동 + 오른손 유지 회피·Q·E 동시 입력이 된다.
## 켜지는 조건: DisplayServer.is_touchscreen_available() 또는 PROPHECY_TOUCH=1(PC 시험: 마우스 왼쪽 버튼을 터치 1개로 취급). 기본(PC)은 숨김.
## 행동은 PInputRouter(가상 스틱·유지·누름)로만 전달하고, 재사용 대기 채움은 CombatState.player.dodge_cd / special_cd / e_cd를 읽기만 한다. 규칙 수치 없음.
## 봇 조작·일시정지·비전투에서는 받지 않는다(active()).

const STICK_R := 64.0        # 스틱 반지름(canvas px)
const STICK_ZONE_W := 0.45   # 왼쪽 끌기 영역 비율(안전 영역 너비)
const BTN_DODGE_R := 48.0    # 지름 96 ≥ 72
const BTN_SMALL_R := 38.0    # 지름 76 ≥ 72
const MOUSE_IDX := 100       # 마우스를 터치로 취급할 때의 index
const HUD_H := 44.0

var router: PInputRouter = null
var view: Node = null          # CombatView(running · paused · bot · st · driver)
var enabled := false
var mouse_as_touch := false

var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_idx: Dictionary = { "dodge": -1, "special": -1, "e": -1 }
var _btn_pos: Dictionary = {}
var _zone := Rect2()
var _safe := Rect2(0.0, 0.0, PLayout.BASE_W, PLayout.BASE_H)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	enabled = PLayout.is_touch()
	mouse_as_touch = enabled and not DisplayServer.is_touchscreen_available()
	set_process(true) # enabled는 안에서 검사(시험·설정 변경으로 뒤늦게 켜져도 동작)
	set_process_unhandled_input(true)
	layout(PLayout.safe_rect(get_viewport()))
	get_viewport().size_changed.connect(func(): layout(PLayout.safe_rect(get_viewport())))

func bind(v: Node, r: PInputRouter) -> void:
	view = v
	router = r

## 안전 영역 기준 배치: 왼쪽 45%(HUD 아래)가 스틱 영역, 오른쪽 아래 모서리에 회피(큰 원)·Q(왼쪽)·E(위)
func layout(safe: Rect2) -> void:
	_safe = safe
	var top: float = safe.position.y + HUD_H
	_zone = Rect2(safe.position.x, top, safe.size.x * STICK_ZONE_W, maxf(0.0, safe.end.y - top))
	var bx: float = safe.end.x - 28.0 - BTN_DODGE_R
	var by: float = safe.end.y - 28.0 - BTN_DODGE_R
	_btn_pos = {
		"dodge": Vector2(bx, by),
		"special": Vector2(bx - BTN_DODGE_R - BTN_SMALL_R - 20.0, by + 6.0),
		"e": Vector2(bx - 26.0, by - BTN_DODGE_R - BTN_SMALL_R - 20.0),
	}

func zone_rect() -> Rect2:
	return _zone

func button_center(kind: String) -> Vector2:
	return _btn_pos.get(kind, Vector2.ZERO)

static func button_radius(kind: String) -> float:
	return BTN_DODGE_R if kind == "dodge" else BTN_SMALL_R

## 지금 터치 입력을 받는 상태인가(전투 진행 중 · 봇 아님 · 정지 아님)
func active() -> bool:
	if not enabled or view == null or router == null or not is_visible_in_tree():
		return false
	return bool(view.running) and not bool(view.paused) and view.bot == null

func stick_held() -> bool:
	return _stick_idx >= 0

func button_held(kind: String) -> bool:
	return int(_btn_idx.get(kind, -1)) >= 0

func _process(_dt: float) -> void:
	if not enabled:
		return
	if not active():
		if _stick_idx >= 0 or button_held("dodge") or button_held("special") or button_held("e"):
			release_all()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		handle_touch(t.index, t.position, t.pressed)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		handle_drag(d.index, d.position)
	elif mouse_as_touch and event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			handle_touch(MOUSE_IDX, mb.position, mb.pressed)
	elif mouse_as_touch and event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _stick_idx == MOUSE_IDX:
			handle_drag(MOUSE_IDX, mm.position)

## 터치 시작/끝(시험에서도 직접 부른다). 누름은 active()일 때만 받고, 뗌은 항상 처리한다
func handle_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		_release(idx)
		return
	if not active():
		return
	for k in _btn_pos:
		var kind := String(k)
		if int(_btn_idx[kind]) < 0 and pos.distance_to(_btn_pos[kind]) <= button_radius(kind):
			_btn_idx[kind] = idx
			router.virtual_press(kind, view.driver) # 탭 = 누름 1회(다음 단계에서 1번 소비)
			if kind == "dodge":
				router.set_virtual_held(true)       # 누르는 동안 유지(길이=거리)
			return
	if _stick_idx < 0 and _zone.has_point(pos):
		_stick_idx = idx
		_stick_origin = pos
		_stick_pos = pos
		router.set_virtual_move(Vector2.ZERO)

## 끌기: 스틱을 잡은 index만 이동 벡터를 바꾼다. 버튼은 손가락이 벗어나도 뗄 때까지 유지
func handle_drag(idx: int, pos: Vector2) -> void:
	if idx != _stick_idx or router == null:
		return
	_stick_pos = pos
	router.set_virtual_move(PInputRouter.stick_vector(pos - _stick_origin, STICK_R))

func _release(idx: int) -> void:
	if idx == _stick_idx:
		_stick_idx = -1
		if router != null:
			router.set_virtual_move(Vector2.ZERO)
	for k in _btn_idx:
		if int(_btn_idx[k]) == idx:
			_btn_idx[k] = -1
			if String(k) == "dodge" and router != null:
				router.set_virtual_held(false)

func release_all() -> void:
	_stick_idx = -1
	for k in _btn_idx:
		_btn_idx[k] = -1
	if router != null:
		router.reset()

## 재사용 대기 채움 0..1(1 = 준비됨). HUD(_update_hud)와 같은 식
static func cooldown_fill(st: CombatState) -> Dictionary:
	var p: Dictionary = st.player
	var P: Dictionary = st.cfg.player
	var dcd: float = float(P.dodge.cooldown)
	var qcd: float = float(st.build.special_cd) if st.build.has("special_cd") else float(P.slowfield.cooldown)
	var out := {
		"dodge": 1.0 - clampf(float(p.dodge_cd) / maxf(0.01, dcd), 0.0, 1.0),
		"special": 1.0 - clampf(float(p.special_cd) / maxf(0.01, qcd), 0.0, 1.0),
		"e": 0.0, "has_e": false,
	}
	if st.build.skills.get("e", null) != null:
		var ecd: float = PSkills.cd_of(st, "e")
		out.e = 1.0 - clampf(float(p.get("e_cd", 0.0)) / maxf(0.01, ecd), 0.0, 1.0)
		out.has_e = true
	return out

# ---------- 그리기(읽기 전용) ----------
func _draw() -> void:
	if not active():
		return
	var f: Font = ThemeDB.fallback_font
	# 스틱: 누르고 있으면 누른 자리, 아니면 영역 왼쪽 아래의 안내 원
	var origin: Vector2 = _stick_origin if _stick_idx >= 0 else Vector2(_zone.position.x + 40.0 + STICK_R, _zone.end.y - 40.0 - STICK_R)
	var alpha: float = 0.35 if _stick_idx >= 0 else 0.16
	draw_circle(origin, STICK_R, Color(1, 1, 1, alpha * 0.35))
	draw_arc(origin, STICK_R, 0.0, TAU, 48, Color(1, 1, 1, alpha), 2.0)
	var knob: Vector2 = origin
	if _stick_idx >= 0:
		var off: Vector2 = _stick_pos - _stick_origin
		if off.length() > STICK_R:
			off = off.normalized() * STICK_R
		knob = origin + off
	draw_circle(knob, 22.0, Color(1, 1, 1, alpha + 0.2))
	if _stick_idx < 0:
		draw_string(f, Vector2(origin.x - STICK_R, origin.y + STICK_R + 16.0), "이동", HORIZONTAL_ALIGNMENT_CENTER, STICK_R * 2.0, 12, Color(1, 1, 1, 0.5))
	# 버튼
	var fill := { "dodge": 1.0, "special": 1.0, "e": 0.0, "has_e": false }
	if view.st != null:
		fill = cooldown_fill(view.st)
	var labels := { "dodge": "회피", "special": "Q", "e": "E" }
	for k in _btn_pos:
		var kind := String(k)
		var c: Vector2 = _btn_pos[kind]
		var r: float = button_radius(kind)
		var held: bool = button_held(kind)
		var ready: float = float(fill[kind])
		var usable: bool = kind != "e" or bool(fill.has_e)
		draw_circle(c, r, Color(0.08, 0.1, 0.13, 0.75 if usable else 0.4))
		if ready > 0.0 and usable:
			draw_arc(c, r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * ready, 48, Color(0.9, 0.85, 0.5, 0.9) if ready >= 1.0 else Color(0.6, 0.75, 0.9, 0.8), 6.0)
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 if held else 0.45), 3.0 if held else 1.5)
		if held:
			draw_circle(c, r - 8.0, Color(1, 1, 1, 0.12))
		var size: int = 16 if kind == "dodge" else 18
		draw_string(f, Vector2(c.x - r, c.y + size * 0.35), String(labels[kind]), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size, Color(1, 1, 1, 0.95 if usable else 0.45))
