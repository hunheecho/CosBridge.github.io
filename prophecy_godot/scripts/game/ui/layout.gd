class_name PLayout
extends RefCounted
## 화면 비율·안전 영역·터치 대상 크기 헬퍼(표시 계층 전용, 규칙 수치 없음).
## 기준 설계 크기는 960×640이고 project.godot의 stretch(canvas_items · expand)로 창이 넓거나 높으면 canvas가 그만큼 늘어난다(줄어들지는 않는다).
## - safe_rect(): DisplayServer.get_display_safe_area()(화면 px)를 창 위치·stretch 변환으로 canvas 좌표에 옮긴 것. PC(창)는 보통 canvas 전체.
## - aspect_bucket(): wide(≥2.0, 예 2340×1080) · standard(16:9·16:10) · narrow(<1.5, 예 1024×768 → canvas 960×720).
## 화면들은 여기서 준 여백·열 비율·최소 버튼 높이만 쓰고, 좌표를 직접 계산하지 않는다.

const BASE_W := 960.0
const BASE_H := 640.0
const WIDE_RATIO := 2.0
const NARROW_RATIO := 1.5
const TOUCH_TARGET := 72.0     # 터치 대상 한 변 최소(px, canvas)
const TOUCH_BUTTON_H := 44.0   # 터치일 때 일반 버튼 최소 높이

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

## 버튼 최소 높이(터치면 44, 아니면 0 = 기본)
static func button_min_height() -> float:
	return TOUCH_BUTTON_H if is_touch() else 0.0

## 큰 행동 버튼(출격·입장 등)의 최소 높이
static func primary_button_height() -> float:
	return 56.0 if is_touch() else 44.0
