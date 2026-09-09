class_name PLayout
extends RefCounted
## 화면 비율·안전 영역·터치 대상 크기 헬퍼(표시 계층 전용, 규칙 수치 없음).
## 기준 설계 크기는 960×640이고 project.godot의 stretch(canvas_items · expand)로 창이 넓거나 높으면 canvas가 그만큼 늘어난다(줄어들지는 않는다).
## - safe_rect(): DisplayServer.get_display_safe_area()(화면 px)를 창 위치·stretch 변환으로 canvas 좌표에 옮긴 것. PC(창)는 보통 canvas 전체.
## - aspect_bucket(): wide(≥2.0, 예 2340×1080) · standard(16:9·16:10) · narrow(<1.5, 예 1024×768 → canvas 960×720).
## 화면들은 여기서 준 여백·열 비율·최소 버튼 높이만 쓰고, 좌표를 직접 계산하지 않는다.
##
## 다른 화면(전체화면 전환·가로 고정·세로 안내·일시정지)이 물어볼 창구는 아래 넷이다(docs/TOUCH_CONTROLS.md):
##   screen_size(vp)     지금 canvas 크기(주소창이 나타나거나 전체화면·회전으로 바뀐 뒤의 값)
##   safe_insets(vp)     보이는 영역 대비 안전 영역이 잘려 나간 양 {left, top, right, bottom}(노치·상태 표시줄)
##   touch_safe_rect(vp) 안전 영역에서 시스템 제스처 여백까지 더 들인 '터치 조작을 놓아도 되는' 영역
##   orientation(vp)     "landscape" | "portrait"(세로 안내를 띄울지 판단)

const BASE_W := 960.0
const BASE_H := 640.0
const WIDE_RATIO := 2.0
const NARROW_RATIO := 1.5
const TOUCH_TARGET := 72.0     # 터치 대상 한 변 최소(px, canvas)
const TOUCH_BUTTON_H := 44.0   # 터치일 때 일반 버튼 최소 높이
const GESTURE_PAD := 16.0      # 시스템 제스처(홈 표시줄·가장자리 스와이프)를 피해 터치 조작을 안쪽으로 들이는 여백(canvas px)

static func is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.get_environment("PROPHECY_TOUCH") == "1"

static func aspect_bucket(size: Vector2) -> String:
	if size.y <= 0.0:
		return "standard"
	var ratio: float = size.x / size.y
	if ratio >= WIDE_RATIO:
		return "wide"
	if ratio < NARROW_RATIO:
		return "narrow"
	return "standard"

static func bucket_of(vp: Viewport) -> String:
	if vp == null:
		return "standard"
	return aspect_bucket(vp.get_visible_rect().size)

## 안전 영역(canvas 좌표). 창이 아니거나 값이 이상하면 보이는 영역 전체
static func safe_rect(vp: Viewport) -> Rect2:
	if vp == null:
		return Rect2(0.0, 0.0, BASE_W, BASE_H)
	var vis: Rect2 = vp.get_visible_rect()
	if not (vp is Window):
		return vis
	var win: Window = vp as Window
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var wrect := Rect2i(win.position, win.size)
	return map_safe(vis, wrect, safe, vp.get_final_transform())

## 순수 계산(헤드리스 시험용): 화면 px 안전 영역 → 창 안 px → canvas 좌표. canvas_to_window = Viewport.get_final_transform()
static func map_safe(vis: Rect2, window_px: Rect2i, safe_px: Rect2i, canvas_to_window: Transform2D) -> Rect2:
	var inter: Rect2i = window_px.intersection(safe_px)
	if inter.size.x <= 0 or inter.size.y <= 0:
		return vis
	var local := Rect2(Vector2(inter.position - window_px.position), Vector2(inter.size))
	var inv: Transform2D = canvas_to_window.affine_inverse()
	var a: Vector2 = inv * local.position
	var b: Vector2 = inv * local.end
	var r: Rect2 = Rect2(a, b - a).abs().intersection(vis)
	if r.size.x < vis.size.x * 0.5 or r.size.y < vis.size.y * 0.5:
		return vis # 비정상 값(창이 화면 밖 등) 방어: 전체 사용
	return r

# ---------- 다른 화면이 쓰는 창구(전체화면·가로 고정·세로 안내·일시정지 담당용) ----------

## 지금 canvas 크기(주소창 표시 여부·전체화면 전환·회전 뒤의 값). 창이 없으면 기준 설계 크기
static func screen_size(vp: Viewport) -> Vector2:
	return vp.get_visible_rect().size if vp != null else Vector2(BASE_W, BASE_H)

## 보이는 영역 대비 안전 영역이 잘려 나간 양(canvas px). 노치·상태 표시줄이 있는 쪽만 0보다 크다
static func safe_insets(vp: Viewport) -> Dictionary:
	if vp == null:
		return { "left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0 }
	var vis: Rect2 = vp.get_visible_rect()
	var safe: Rect2 = safe_rect(vp)
	return {
		"left": maxf(0.0, safe.position.x - vis.position.x),
		"top": maxf(0.0, safe.position.y - vis.position.y),
		"right": maxf(0.0, vis.end.x - safe.end.x),
		"bottom": maxf(0.0, vis.end.y - safe.end.y),
	}

## 시스템 제스처 여백(canvas px). 터치 화면일 때만 들인다(PC HUD 크기는 그대로 둔다)
static func gesture_pad() -> float:
	return GESTURE_PAD if is_touch() else 0.0

## 순수 계산(헤드리스 시험용): 사각형을 네 변에서 pad만큼 들인다. 여백이 사각형보다 크면 원래대로 둔다
static func inset_rect(r: Rect2, pad: float) -> Rect2:
	if pad <= 0.0 or r.size.x <= pad * 2.0 or r.size.y <= pad * 2.0:
		return r
	return Rect2(r.position + Vector2(pad, pad), r.size - Vector2(pad * 2.0, pad * 2.0))

## 터치 조작을 놓아도 되는 영역 = 안전 영역(노치 밖) − 시스템 제스처 여백
static func touch_safe_rect(vp: Viewport) -> Rect2:
	return inset_rect(safe_rect(vp), gesture_pad())

## 화면 방향("landscape" | "portrait"). 세로 안내를 띄울지 판단하는 쪽이 쓴다
static func orientation(vp: Viewport) -> String:
	var s: Vector2 = screen_size(vp)
	return "portrait" if s.y > s.x else "landscape"

static func is_landscape(vp: Viewport) -> bool:
	return orientation(vp) == "landscape"

## 화면 여백: 기본 여백 + (보이는 영역과 안전 영역의 차). {left, top, right, bottom}
static func margins(vp: Viewport, base_side: int = 14, base_tb: int = 10) -> Dictionary:
	if vp == null:
		return { "left": base_side, "top": base_tb, "right": base_side, "bottom": base_tb }
	var vis: Rect2 = vp.get_visible_rect()
	var safe: Rect2 = safe_rect(vp)
	return {
		"left": base_side + int(round(maxf(0.0, safe.position.x - vis.position.x))),
		"top": base_tb + int(round(maxf(0.0, safe.position.y - vis.position.y))),
		"right": base_side + int(round(maxf(0.0, vis.end.x - safe.end.x))),
		"bottom": base_tb + int(round(maxf(0.0, vis.end.y - safe.end.y))),
	}

static func apply_margins(mc: MarginContainer, vp: Viewport, base_side: int = 14, base_tb: int = 10) -> void:
	var m := margins(vp, base_side, base_tb)
	mc.add_theme_constant_override("margin_left", int(m.left))
	mc.add_theme_constant_override("margin_right", int(m.right))
	mc.add_theme_constant_override("margin_top", int(m.top))
	mc.add_theme_constant_override("margin_bottom", int(m.bottom))

## 두 열 배치의 왼쪽 비율(넓을수록 왼쪽(마을·카드)을 넓게)
static func left_ratio(bucket: String) -> float:
	match bucket:
		"wide": return 0.6
		"narrow": return 0.55
		_: return 0.57

## 거점 마을 그림의 높이(canvas px)
static func village_height(bucket: String) -> float:
	match bucket:
		"wide": return 200.0
		"narrow": return 220.0
		_: return 180.0

## 화면 글자·버튼 확대 배율.
##
## 왜 필요한가(2026-09-09 사람 플레이 보고, 친구): "모바일로 하기엔 버튼이 넘 작고 글자도 안 보임".
## 이 게임은 캔버스 960x640을 화면에 맞춰 **줄여서** 그린다(stretch canvas_items).
## 폰 가로처럼 짧은 화면에서는 그 축소율이 0.5배 아래로 내려가, 13px 글자가 실제로는 7px가 된다.
## 그래서 **축소율의 역수만큼** 글자·버튼을 키워 실제 화면에서의 크기를 되돌린다.
##
## 터치가 아니면 1.0이다 — **PC 화면은 하나도 바뀌지 않는다.**
## 상한 1.6배: 그 이상 키우면 한 줄에 들어가던 글이 넘쳐 배치가 깨진다(직접 확인한 값).
const UI_SCALE_MAX := 1.6
static func ui_scale(vp: Viewport) -> float:
	if not is_touch() or vp == null:
		return 1.0
	var cv := vp.get_visible_rect().size
	if cv.y <= 0.0:
		return 1.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 1.0
	var eff := float(win.y) / cv.y      # 캔버스 1단위가 실제 몇 px로 그려지는가
	if eff >= 1.0:
		return 1.0
	return clampf(1.0 / eff, 1.0, UI_SCALE_MAX)

## 지금 배율(화면이 크기를 바꿀 때 main이 넣어 준다). 정적이라 PUi가 인자 없이 읽는다
static var _ui_scale := 1.0
static func set_ui_scale(v: float) -> void:
	_ui_scale = clampf(v, 1.0, UI_SCALE_MAX)
static func cur_ui_scale() -> float:
	return _ui_scale

## 글자 크기 하나를 지금 배율로 바꾼다. 화면 코드는 전부 이걸 지난다
static func fs(size: int) -> int:
	return int(round(float(size) * _ui_scale))

## 버튼 최소 높이(터치면 44, 아니면 0 = 기본). 배율을 함께 적용한다
static func button_min_height() -> float:
	return TOUCH_BUTTON_H * _ui_scale if is_touch() else 0.0

## 큰 행동 버튼(출격·입장 등)의 최소 높이
static func primary_button_height() -> float:
	return 56.0 * _ui_scale if is_touch() else 44.0
