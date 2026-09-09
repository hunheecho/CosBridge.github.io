class_name PTouchControls
extends Control
## 가로 화면 터치 오버레이: 왼쪽 가상 스틱(끌기 영역, 누른 자리가 중심) + 오른쪽 버튼(회피 = 누르는 동안 유지·짧게 탭, Q, E). 그림은 도형만.
## 터치 index마다 어느 조작을 잡았는지 기억하므로(스틱 1개 + 버튼별 1개) 스틱을 움직여도 잡고 있는 회피가 풀리지 않고, 왼손 이동 + 오른손 유지 회피·Q·E 동시 입력이 된다.
## 켜지는 조건: DisplayServer.is_touchscreen_available() 또는 PROPHECY_TOUCH=1(PC 시험: 마우스 왼쪽 버튼을 터치 1개로 취급). 기본(PC)은 숨김.
## 행동은 PInputRouter(가상 스틱·유지·누름)로만 전달하고, 재사용 대기 채움은 CombatState.player.dodge_cd / special_cd / e_cd를 읽기만 한다. 규칙 수치 없음.
## 봇 조작·일시정지·비전투에서는 받지 않는다(active()).
##
## 크기(2026-09-09, 사용자가 실제 폰으로 플레이한 뒤의 지시): 조작이 너무 작다.
##   조이스틱 **바깥 반지름 2배**, 회피·Q·E는 각각 **반지름 1.5배**(면적 배율이 아니다).
##   손잡이·글자도 같은 배율로 키우고, 그림과 터치 판정을 **한 함수에서** 낸다(draw_geometry() → _draw와 handle_touch가 같은 값을 본다).
##   확대해도 이동 속도·회피 거리·재사용 대기는 그대로다: 스틱 벡터는 STICK_R로 정규화하므로 '끝까지 민' 값이 확대 전후 같고(입력 시험 H7),
##   CombatState는 그 벡터를 PGeom.norm으로 다시 정규화해 **방향만** 쓴다. 규칙(scripts/rules/**)은 한 줄도 건드리지 않는다.
##
## 배치는 layout()이 안전 영역(노치 제외)에서 시스템 제스처 여백까지 더 들인 뒤 계산한다. docs/TOUCH_CONTROLS.md에 근거와 검사 목록을 적었다.

# ---------- 크기: 확대 전 값(BASE_*)과 배율을 함께 남긴다. 시험이 배율을 그대로 못 박는다 ----------
const BASE_STICK_R := 64.0        # 확대 전 스틱 바깥 반지름
const BASE_KNOB_R := 22.0         # 확대 전 손잡이 반지름
const BASE_BTN_DODGE_R := 48.0    # 확대 전 회피 반지름(지름 96)
const BASE_BTN_SMALL_R := 38.0    # 확대 전 Q·E 반지름(지름 76)
const STICK_SCALE := 2.0          # 사용자 지시: 조이스틱 바깥 반지름 2배
const BTN_SCALE := 1.5            # 사용자 지시: 회피·Q·E 반지름 1.5배

const STICK_R := BASE_STICK_R * STICK_SCALE          # 128 — 그림 반지름이자 '최대 편차' 기준(정규화 분모)
const KNOB_R := BASE_KNOB_R * STICK_SCALE            # 44
const BTN_DODGE_R := BASE_BTN_DODGE_R * BTN_SCALE    # 72 (지름 144)
const BTN_SMALL_R := BASE_BTN_SMALL_R * BTN_SCALE    # 57 (지름 114)
const BTN_BUILD_R := 30.0         # '빌드' 버튼(지름 60): 조작 버튼이 아니라 확대 대상이 아니다. 위쪽 구석에 따로 둔다

# 글자 크기(읽기 좋게 같은 배율로). 확대 전 값은 주석의 왼쪽 숫자다
const FS_DODGE := 24              # 16 × 1.5
const FS_SMALL := 27              # 18 × 1.5
const FS_CD := 20                 # 13 × 1.5(반올림) — 남은 초
const FS_NONE := 17               # 11 × 1.5(반올림) — '미보유'
const FS_MOVE := 24               # 12 × 2(스틱과 같은 배율) — '이동' 안내
const FS_BUILD := 14              # 빌드 버튼(확대 대상 아님)

const STICK_ZONE_W := 0.45        # 왼쪽 끌기 영역 비율(안전 영역 너비)
const MOUSE_IDX := 100            # 마우스를 터치로 취급할 때의 index
const HUD_H := 44.0               # 상단 띠 높이(그 아래부터 조작을 놓는다)
const EDGE_PAD := 20.0            # 조작 버튼과 안전 영역 가장자리 사이
const BTN_GAP := 14.0             # 버튼 사이 최소 빈 틈(손가락 하나가 두 버튼에 걸치지 않게)
const GUIDE_PAD := 16.0           # 안내 원과 끌기 영역 가장자리 사이
const BUILD_PAD := 14.0           # 빌드 버튼과 안전 영역 오른쪽·위 사이

const LABELS := { "dodge": "회피", "special": "Q", "e": "E" }
const RING_READY := Color(0.9, 0.85, 0.5, 0.9)   # 준비됨: 컬러(금색) 꽉 찬 고리
const RING_WAIT := Color(0.6, 0.75, 0.9, 0.8)    # 재사용 대기: 채워지는 고리 + 남은 초(회귀: 색·뜻 그대로)

var router: PInputRouter = null
var view: Node = null          # CombatView(running · paused · bot · st · driver)
var enabled := false
var mouse_as_touch := false
var gesture_pad := PLayout.GESTURE_PAD  # 시스템 제스처 여백(시험이 노치·제스처 값을 바꿔 넣는다)

var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO

# ---------- 방향 버튼(설정에서 스틱 대신 고를 수 있다) ----------
## 상·하·좌·우 넷. 둘을 함께 누르면 대각이 된다 — **키보드 WASD와 완전히 같은 8방향**이다.
## 규칙에는 스틱과 똑같이 방향 벡터 하나로 전달된다(대각은 정규화해 속도가 빨라지지 않게).
## 손가락 하나가 두 칸에 걸쳐도 **가까운 하나만** 잡는다(pick_at과 같은 원칙).
const DPAD_DIRS := { "up": Vector2(0.0, -1.0), "down": Vector2(0.0, 1.0),
	"left": Vector2(-1.0, 0.0), "right": Vector2(1.0, 0.0) }
const DPAD_ARROW := { "up": "▲", "down": "▼", "left": "◀", "right": "▶" }
var _dpad_pos: Dictionary = {}
var _dpad_idx: Dictionary = { "up": -1, "down": -1, "left": -1, "right": -1 }

func dpad_on() -> bool:
	return PLayout.is_dpad()

func dpad_center(dir: String) -> Vector2:
	return _dpad_pos.get(dir, Vector2.ZERO)

func dpad_held(dir: String) -> bool:
	return int(_dpad_idx.get(dir, -1)) >= 0

## 지금 눌린 방향 버튼들을 하나의 이동 벡터로 합친다(대각은 정규화 — 대각이 더 빠르면 안 된다)
func _dpad_vector() -> Vector2:
	var v := Vector2.ZERO
	for d in DPAD_DIRS:
		if dpad_held(String(d)):
			v += Vector2(DPAD_DIRS[d])
	return v.normalized() if v.length() > 0.0 else Vector2.ZERO

func _dpad_push() -> void:
	if router != null:
		router.set_virtual_move(_dpad_vector())

## 방향 버튼 중 좌표에 걸리는 것(가장 가까운 하나). 없으면 ""
func _dpad_at(pos: Vector2) -> String:
	var best := ""
	var bd := INF
	for d in _dpad_pos:
		var c: Vector2 = _dpad_pos[d]
		var dist := pos.distance_to(c)
		if dist <= BTN_SMALL_R and dist < bd:
			bd = dist
			best = String(d)
	return best
var _btn_idx: Dictionary = { "dodge": -1, "special": -1, "e": -1 }
var _btn_pos: Dictionary = {}
var _zone := Rect2()
var _guide := Vector2.ZERO      # 손을 떼고 있을 때 그리는 안내 원의 중심(끌기 영역 안에 통째로 들어간다)
var _build_pos := Vector2.ZERO  # '내 빌드' 버튼 중심(모바일에서 전체 빌드를 여는 유일한 길)
var reserve_top := 0.0          # 상단에 빌드 HUD가 놓인 높이(px). 스틱 끌기 영역이 빌드 아이콘과 겹치지 않게 그만큼 내린다
var _full := Rect2(0.0, 0.0, PLayout.BASE_W, PLayout.BASE_H)   # 받은 안전 영역 그대로(화면 밖 판정에 쓴다)
var _safe := Rect2(0.0, 0.0, PLayout.BASE_W, PLayout.BASE_H)   # 제스처 여백까지 들인 것(조작을 놓는 영역)

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

## 안전 영역 기준 배치(주소창 등장·전체화면·회전으로 크기가 바뀔 때마다 다시 부른다 → 그림과 터치 좌표가 같이 옮겨간다).
## 오른손 엄지는 오른쪽 아래 모서리를 축으로 움직이므로 회피(가장 크고 가장 자주 쓴다)를 모서리에 두고,
## Q는 그 왼쪽, E는 Q 위에 쌓는다. E를 회피 위에 두면 낮은 가로 화면에서 위쪽 '빌드' 버튼과 부딪힌다.
## 작은 버튼(Q·E)은 회피와 **아래를 맞춘다**: 그만큼 E 위쪽 여유가 생겨 상단 띠 밑으로 들어가지 않는다.
func layout(safe: Rect2) -> void:
	_full = safe
	_safe = PLayout.inset_rect(safe, gesture_pad)
	var top: float = maxf(_safe.position.y, safe.position.y + HUD_H + reserve_top)
	var bx: float = _safe.end.x - EDGE_PAD - BTN_DODGE_R
	var by: float = _safe.end.y - EDGE_PAD - BTN_DODGE_R
	var qx: float = bx - (BTN_DODGE_R + BTN_SMALL_R + BTN_GAP)
	var qy: float = _safe.end.y - EDGE_PAD - BTN_SMALL_R
	_btn_pos = {
		"dodge": Vector2(bx, by),
		"special": Vector2(qx, qy),
		"e": Vector2(qx, qy - (BTN_SMALL_R * 2.0 + BTN_GAP)),
	}
	# '빌드': 오른쪽 위(조작 버튼 묶음에서 가장 먼 구석). 누르면 전투를 안전하게 일시정지하고 '내 빌드'를 연다
	_build_pos = Vector2(_safe.end.x - BUILD_PAD - BTN_BUILD_R, top + 10.0 + BTN_BUILD_R)
	# 끌기 영역: 왼쪽 비율만큼 쓰되 안내 원이 통째로 들어갈 만큼은 확보하고, 가장 왼쪽 버튼 앞에서 끊는다(영역과 버튼이 겹치지 않게)
	var want: float = maxf(_safe.size.x * STICK_ZONE_W, STICK_R * 2.0 + GUIDE_PAD * 2.0)
	var limit: float = (qx - BTN_SMALL_R - BTN_GAP) - _safe.position.x
	_zone = Rect2(_safe.position.x, top, maxf(0.0, minf(want, limit)), maxf(0.0, _safe.end.y - top))
	_guide = _guide_center()
	# 방향 버튼 십자: 안내 원이 있던 자리를 그대로 쓴다(왼손 엄지가 닿던 곳).
	# 칸 사이 간격은 버튼 지름 + 최소 틈이라 손가락 하나가 두 칸에 걸치지 않는다.
	var step: float = BTN_SMALL_R * 2.0 + BTN_GAP
	var cx: float = clampf(_guide.x, _zone.position.x + step + BTN_SMALL_R, maxf(_zone.position.x + step + BTN_SMALL_R, _zone.end.x - step - BTN_SMALL_R))
	var cy: float = clampf(_guide.y, top + step + BTN_SMALL_R, maxf(top + step + BTN_SMALL_R, _safe.end.y - EDGE_PAD - step - BTN_SMALL_R))
	_dpad_pos = {
		"up": Vector2(cx, cy - step),
		"down": Vector2(cx, cy + step),
		"left": Vector2(cx - step, cy),
		"right": Vector2(cx + step, cy),
	}

## 안내 원 중심: 끌기 영역의 왼쪽 아래에 두되 원이 영역 밖으로 나가지 않게 가둔다(보이는 원 = 누를 수 있는 자리)
func _guide_center() -> Vector2:
	var lo := Vector2(_zone.position.x + STICK_R, _zone.position.y + STICK_R)
	var hi := Vector2(maxf(lo.x, _zone.end.x - STICK_R), maxf(lo.y, _zone.end.y - STICK_R))
	var want := Vector2(_zone.position.x + GUIDE_PAD + STICK_R, _zone.end.y - GUIDE_PAD - STICK_R)
	return Vector2(clampf(want.x, lo.x, hi.x), clampf(want.y, lo.y, hi.y))

func zone_rect() -> Rect2:
	return _zone

## 조작을 놓는 영역(안전 영역 − 제스처 여백)과 받은 안전 영역 그대로. 시험·다른 화면이 읽는다
func safe_area() -> Rect2:
	return _safe

func full_area() -> Rect2:
	return _full

func guide_center() -> Vector2:
	return _guide

func build_button_center() -> Vector2:
	return _build_pos

## 전투 중 '내 빌드' 열기(모바일 경로). main의 공통 경로를 쓰므로 전투는 안전하게 멈춘다
func _open_build() -> void:
	var m: Node = view.get_parent() if view != null else null
	if m != null and m.has_method("open_build_detail"):
		m.call("open_build_detail")

func button_center(kind: String) -> Vector2:
	return _btn_pos.get(kind, Vector2.ZERO)

## 조작 버튼 반지름 정본. 그림(_draw → draw_geometry)과 터치 판정(handle_touch)이 **둘 다 이 함수만** 쓴다
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

## 창이 뒤로 가거나 앱이 멈추면 뗌 이벤트가 오지 않는다: 이동·버튼 눌림이 남지 않게 스스로 놓는다
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.canceled:
			handle_cancel(t.index)   # 시스템이 터치를 가져갔다(제스처·전화 등) → 잡고 있던 것을 모두 놓는다
		else:
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

## 이 자리에서 집을 조작("" = 없음). 원이 서로 겹치지 않지만, 그래도 **가장 깊이 들어간 하나만** 고른다
## (한 번의 터치로 두 기술이 나가지 않게 하는 마지막 빗장)
func pick_at(pos: Vector2) -> String:
	var pick := ""
	var best := 0.0
	var bd: float = pos.distance_to(_build_pos) - BTN_BUILD_R
	if bd <= 0.0:
		pick = "build"
		best = bd
	for k in _btn_pos:
		var kind := String(k)
		var c: Vector2 = _btn_pos[kind]
		var d: float = pos.distance_to(c) - button_radius(kind)
		if d <= 0.0 and (pick == "" or d < best):
			pick = kind
			best = d
	return pick

## 터치 시작/끝(시험에서도 직접 부른다). 누름은 active()일 때만 받고, 뗌은 항상 처리한다
func handle_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		_release(idx)
		return
	if not active():
		return
	var pick := pick_at(pos)
	if pick == "build":
		_open_build()
		return
	if pick != "":
		if int(_btn_idx[pick]) < 0:
			_btn_idx[pick] = idx
			router.virtual_press(pick, view.driver) # 탭 = 누름 1회(다음 단계에서 1번 소비)
			if pick == "dodge":
				router.set_virtual_held(true)       # 누르는 동안 유지(길이=거리)
		return                                      # 버튼 위의 터치는 스틱을 잡지 않는다
	if dpad_on():
		var d := _dpad_at(pos)
		if d != "" and int(_dpad_idx[d]) < 0:
			_dpad_idx[d] = idx
			_dpad_push()
		return                                      # 방향 버튼 방식에서는 스틱을 잡지 않는다
	if _stick_idx < 0 and _zone.has_point(pos):
		_stick_idx = idx
		_stick_origin = pos
		_stick_pos = pos
		router.set_virtual_move(Vector2.ZERO)

## 끌기: 스틱을 잡은 index만 이동 벡터를 바꾼다. 버튼은 손가락이 벗어나도 뗄 때까지 유지.
## 손가락이 안전 영역(화면) 밖으로 빠지면 뗌 이벤트를 못 받을 수 있어 스스로 놓는다(이동이 눌린 채 남지 않게).
func handle_drag(idx: int, pos: Vector2) -> void:
	if idx != _stick_idx or router == null:
		return
	if not _full.has_point(pos):
		_release(idx)
		return
	_stick_pos = pos
	router.set_virtual_move(PInputRouter.stick_vector(pos - _stick_origin, STICK_R))

## 입력 취소(InputEventScreenTouch.canceled·시스템 제스처): 그 손가락이 잡고 있던 것을 모두 놓는다
func handle_cancel(idx: int) -> void:
	_release(idx)

func _release(idx: int) -> void:
	if idx == _stick_idx:
		_stick_idx = -1
		if router != null:
			router.set_virtual_move(Vector2.ZERO)
	var dpad_changed := false
	for d in _dpad_idx:
		if int(_dpad_idx[d]) == idx:
			_dpad_idx[d] = -1
			dpad_changed = true
	if dpad_changed:
		_dpad_push()          # 남은 방향만으로 다시 계산한다(대각에서 하나만 떼면 직선이 된다)
	for k in _btn_idx:
		if int(_btn_idx[k]) == idx:
			_btn_idx[k] = -1
			if String(k) == "dodge" and router != null:
				router.set_virtual_held(false)

func release_all() -> void:
	_stick_idx = -1
	for k in _btn_idx:
		_btn_idx[k] = -1
	for d in _dpad_idx:
		_dpad_idx[d] = -1
	if router != null:
		router.reset()

## 재사용 대기 채움 0..1(1 = 준비됨). HUD(_update_hud)와 같은 식
## 남은 재사용 대기(초). 표시 전용
func _cd_left(kind: String) -> float:
	if view == null:
		return 0.0
	var st: CombatState = view.st
	if st == null:
		return 0.0
	var p: Dictionary = st.player
	match kind:
		"dodge": return maxf(0.0, float(p.dodge_cd))
		"special": return maxf(0.0, float(p.special_cd))
		"e": return maxf(0.0, float(p.get("e_cd", 0.0)))
	return 0.0

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
## 그림 규격 한 곳. _draw는 여기서 낸 값만 쓰고, 시험은 이 값을 터치 판정(button_radius·STICK_R)과 맞대 본다.
## → '그림만 커지고 판정은 그대로'가 생길 수 없다.
func draw_geometry() -> Dictionary:
	var held: bool = _stick_idx >= 0
	var origin: Vector2 = _stick_origin if held else _guide
	var knob: Vector2 = origin
	if held:
		var off: Vector2 = _stick_pos - _stick_origin
		if off.length() > STICK_R:
			off = off.normalized() * STICK_R
		knob = origin + off
	var fill := { "dodge": 1.0, "special": 1.0, "e": 0.0, "has_e": false }
	if view != null and view.st != null:
		fill = cooldown_fill(view.st)
	var dpad := {}
	if dpad_on():
		for d in _dpad_pos:
			dpad[String(d)] = {
				"center": _dpad_pos[d],
				"radius": BTN_SMALL_R,
				"held": dpad_held(String(d)),
				"arrow": String(DPAD_ARROW[d]),
			}
	var btns := {}
	for k in _btn_pos:
		var kind := String(k)
		var ready: float = float(fill[kind])
		var usable: bool = kind != "e" or bool(fill.has_e)
		var left: float = _cd_left(kind)
		var cd_text := ""
		var cd_font: int = FS_CD
		if not usable:
			cd_text = "미보유"
			cd_font = FS_NONE
		elif ready < 1.0 and left > 0.05:
			cd_text = "%.1f" % left
		btns[kind] = {
			"center": _btn_pos[kind],
			"radius": button_radius(kind),
			"held": button_held(kind),
			"ready": ready,
			"usable": usable,
			"label": String(LABELS[kind]),
			"font": FS_DODGE if kind == "dodge" else FS_SMALL,
			"ring": RING_READY if ready >= 1.0 else RING_WAIT,
			"cd_text": cd_text,
			"cd_font": cd_font,
		}
	return {
		"stick": {
			"origin": origin, "radius": STICK_R, "knob": knob, "knob_radius": KNOB_R,
			"held": held, "label_font": FS_MOVE,
			"label_y": minf(origin.y + STICK_R + float(FS_MOVE) + 2.0, _safe.end.y - 4.0),
		},
		"buttons": btns, "dpad": dpad,
		"build": { "center": _build_pos, "radius": BTN_BUILD_R, "font": FS_BUILD },
	}

func _draw() -> void:
	if not active():
		return
	var f: Font = ThemeDB.fallback_font
	var g: Dictionary = draw_geometry()
	# 방향 버튼 방식: 스틱 자리에 십자 넷을 그린다(키보드 WASD와 같은 8방향)
	if dpad_on():
		for k in (g.dpad as Dictionary):
			var d: Dictionary = (g.dpad as Dictionary)[k]
			var dc: Vector2 = d.center
			var dr: float = float(d.radius)
			var on: bool = bool(d.held)
			draw_circle(dc, dr, Color(1, 1, 1, 0.30 if on else 0.12))
			draw_arc(dc, dr, 0.0, TAU, 48, Color(1, 1, 1, 0.85 if on else 0.40), 2.0)
			var aw: float = f.get_string_size(String(d.arrow), HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS_SMALL).x
			draw_string(f, Vector2(dc.x - aw * 0.5, dc.y + FS_SMALL * 0.36), String(d.arrow),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, FS_SMALL, Color(1, 1, 1, 0.95 if on else 0.6))
		_draw_action_buttons(f, g)
		return
	# 스틱: 누르고 있으면 누른 자리, 아니면 영역 왼쪽 아래의 안내 원
	var s: Dictionary = g.stick
	var origin: Vector2 = s.origin
	var sr: float = float(s.radius)
	var held: bool = bool(s.held)
	var alpha: float = 0.35 if held else 0.16
	draw_circle(origin, sr, Color(1, 1, 1, alpha * 0.35))
	draw_arc(origin, sr, 0.0, TAU, 64, Color(1, 1, 1, alpha), 2.0)
	var knob: Vector2 = s.knob
	draw_circle(knob, float(s.knob_radius), Color(1, 1, 1, alpha + 0.2))
	if not held:
		draw_string(f, Vector2(origin.x - sr, float(s.label_y)), "이동", HORIZONTAL_ALIGNMENT_CENTER, sr * 2.0, int(s.label_font), Color(1, 1, 1, 0.5))
	_draw_action_buttons(f, g)

## 회피·Q·E·빌드 그리기. 스틱 방식과 방향 버튼 방식이 **같은 함수**를 쓴다
## (이동 방식을 바꿔도 오른쪽 조작은 한 글자도 달라지지 않는다)
func _draw_action_buttons(f: Font, g: Dictionary) -> void:
	# 버튼: 재사용 대기 = 채워지는 고리 + 남은 초, 준비됨 = 꽉 찬 금색 고리(HUD 아이콘의 흑백/컬러와 같은 뜻)
	var btns: Dictionary = g.buttons
	for k in btns:
		var b: Dictionary = btns[k]
		var c: Vector2 = b.center
		var r: float = float(b.radius)
		var usable: bool = bool(b.usable)
		var ready: float = float(b.ready)
		var bheld: bool = bool(b.held)
		var ring: Color = b.ring
		draw_circle(c, r, Color(0.08, 0.1, 0.13, 0.75 if usable else 0.4))
		if ready > 0.0 and usable:
			draw_arc(c, r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * ready, 64, ring, 6.0)
		draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.9 if bheld else 0.45), 3.0 if bheld else 1.5)
		if bheld:
			draw_circle(c, r - 8.0, Color(1, 1, 1, 0.12))
		var fs: int = int(b.font)
		draw_string(f, Vector2(c.x - r, c.y + fs * 0.35), String(b.label), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.95 if usable else 0.45))
		# 남은 초(소리 없이도 준비 상태를 읽을 수 있게) 또는 '미보유'
		var cd_text := String(b.cd_text)
		if cd_text != "":
			draw_string(f, Vector2(c.x - r, c.y + r - 8.0), cd_text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(b.cd_font), Color(1, 1, 1, 0.85 if usable else 0.45))
	# '빌드' 버튼: 전체 빌드(자동기술·개조·Q/E·공용·패시브·장비)는 모바일에서도 여기로 연다
	var bd: Dictionary = g.build
	var bc: Vector2 = bd.center
	var br: float = float(bd.radius)
	draw_circle(bc, br, Color(0.08, 0.1, 0.13, 0.7))
	draw_arc(bc, br, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 1.5)
	draw_string(f, Vector2(bc.x - br, bc.y + 5.0), "빌드", HORIZONTAL_ALIGNMENT_CENTER, br * 2.0, int(bd.font), Color(1, 1, 1, 0.9))
