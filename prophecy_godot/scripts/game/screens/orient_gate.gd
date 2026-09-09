class_name POrientGate
extends Control
## 화면 방향·전체화면 안내막(표시 전용). 규칙 수치도, 조작 버튼 자리도 여기서 정하지 않는다.
## 무엇을 보일지는 main이 정해 apply()로 넘기고, 이 파일은 그것을 그리기만 한다.
##
## 세 가지 모습만 있다.
##  ① 세로: 화면 전체를 덮고 "휴대폰을 가로로 돌려주세요".
##  ② 가로로 돌아왔지만 아직 멈춰 있음: 화면 전체를 덮고 '계속' 버튼 — 저절로 재개하지 않는다.
##  ③ 그 밖에 전체화면에서 빠져나온 상태: 화면을 덮지 않고 오른쪽 위에 '전체화면' 버튼만.
##     (2026-09-09 사용자 피드백 "너무 작다" 이후로 이 버튼은 더 이상 '작은 구석 버튼'이 아니다 — corner_metrics 참고)
##
## 세로/가로 판정(is_portrait)은 화면 크기 비율만 본다. 회전 사건이 없는 PC에서도 창을 세로로 줄이면
## 폰을 세로로 돌린 것과 같은 상태가 된다(그래서 헤드리스 검사가 가능하다).

signal resume_pressed        # '계속'을 눌렀다(실제 재개는 main이 한다)
signal fullscreen_pressed    # '전체화면으로 다시 들어가기'를 눌렀다

const TITLE_PORTRAIT := "휴대폰을 가로로 돌려주세요"
const TITLE_PAUSED := "전투를 멈춰 두었습니다"
const RESUME_TEXT := "계속"
const FS_TEXT := "전체화면으로 다시 들어가기"
const CORNER_TEXT := "전체화면"

# ---------- 전체화면 버튼 크기(2026-09-09 사용자 피드백: "전체화면으로 키우는 버튼이 너무 작다") ----------
## 아래 숫자는 **시험값**이다. 사용자가 실제 폰에서 보고 정할 최종 수치는 아직 없다.
##
## 왜 예전 값(108×34 · 글자 13)이 작았나: 캔버스 높이 640이 폰 가로 화면 높이 전체가 된다.
## 화면이 CSS 360px이면 캔버스 1px = 0.5625 CSS px이라 34px 버튼이 **19 CSS px**, 글자 13px이 **7 CSS px**이 된다.
## 손가락 권장치(≈48 CSS px)의 절반도 안 됐다.
## 그래서 높이를 화면 높이의 14.4%(캔버스 92 → 약 52 CSS px), 글자를 28(약 16 CSS px)로 잡았다.
##
## 자리: 오른쪽 위지만 **상단 띠(목표·체력) 아래**다. 화면 맨 위는 브라우저 주소창·노치와 겹칠 수 있어 피한다.
## 낮은 화면에서는 잘리지 않게 화면 높이에 맞춰 함께 줄어든다.
const CORNER_TOUCH_H := 92.0      # 터치 최대 높이(canvas px)
const CORNER_TOUCH_W := 202.0     # 터치 최대 너비
const CORNER_TOUCH_FS := 28       # 터치 최대 글자 크기
const CORNER_MIN_H := 52.0        # 낮은 화면에서도 이 아래로는 줄이지 않는다
const CORNER_MIN_W := 120.0
const CORNER_MIN_FS := 16
const CORNER_TOP := 52.0          # 안전 영역 위에서 내려오는 양 = 상단 띠 44 + 여유 8
const CORNER_PC_SIZE := Vector2(108.0, 34.0)   # PC는 예전 그대로(불필요한 변경 금지)
const CORNER_PC_FS := 13
const CORNER_BG := Color(0.95, 0.80, 0.30, 0.97)        # 배경과 확실히 갈리는 금색 판
const CORNER_BG_ON := Color(1.0, 0.88, 0.45, 0.99)
const CORNER_BG_DOWN := Color(0.80, 0.66, 0.22, 0.99)
const CORNER_LINE := Color(0.10, 0.09, 0.03, 0.95)
const CORNER_FG := Color(0.08, 0.07, 0.02, 1.0)

const NOTE_PORTRAIT_PAUSED := "세로로 바뀌는 순간 전투를 멈추고 누르고 있던 조작을 놓았습니다.\n보이지 않는 동안에는 피해를 받지 않습니다. 가로로 돌리면 '계속' 버튼이 나옵니다."
const NOTE_PORTRAIT := "이 게임은 가로 화면에 맞춰 만들었습니다. 폰을 가로로 돌려 주세요."
const NOTE_PAUSED := "세로로 돌아가 있는 동안 멈춰 두었습니다. 저절로 다시 시작하지 않습니다 — 준비되면 '계속'을 누르세요."

## 전체화면 버튼의 자리·크기·글자 크기(순수 계산. 시험이 헤드리스에서 그대로 확인한다).
## 터치가 아니면 예전 값을 그대로 돌려준다 — **PC 화면은 하나도 바뀌지 않는다.**
static func corner_metrics(safe: Rect2, touch: bool) -> Dictionary:
	if not touch:
		return {
			"rect": Rect2(Vector2(safe.end.x - 116.0, safe.position.y + 4.0), CORNER_PC_SIZE),
			"font": CORNER_PC_FS,
		}
	var h: float = clampf(safe.size.y * 0.145, CORNER_MIN_H, CORNER_TOUCH_H)
	var w: float = clampf(h * 2.2, CORNER_MIN_W, CORNER_TOUCH_W)
	var fs: int = int(round(clampf(h * 0.30, float(CORNER_MIN_FS), float(CORNER_TOUCH_FS))))
	# 위: 상단 띠(목표·체력 줄, 높이 44) **아래**로 내린다 — 화면 맨 위는 브라우저 주소창·노치와 겹칠 수 있다.
	# 아래: 화면 밖으로 잘리지 않게 가둔다
	var top: float = safe.position.y + CORNER_TOP
	top = minf(top, maxf(safe.position.y, safe.end.y - h))
	var x: float = maxf(safe.position.x, safe.end.x - PLayout.GESTURE_PAD - w)
	return { "rect": Rect2(Vector2(x, top), Vector2(w, h)), "font": fs }

var _veil: Control
var _title: Label
var _note: Label
var _resume: Button
var _veil_fs: Button
var _corner: Button
var _safe := Rect2(0.0, 0.0, PLayout.BASE_W, PLayout.BASE_H)

## 세로인가(순수 함수). 너비보다 높이가 크면 세로. 크기를 못 읽으면(0 이하) 세로로 보지 않는다
static func is_portrait(size: Vector2) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	return size.y > size.x

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # 안내막이 꺼져 있을 때 아래 화면의 입력을 막지 않는다
	_build_veil()
	_build_corner()
	apply(false, false, false)

func _build_veil() -> void:
	_veil = Control.new()
	_veil.name = "Veil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP # 덮는 동안에는 아래 화면이 눌리지 않는다
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.add_child(center)
	var box := PUi.vbox(14)
	box.custom_minimum_size = Vector2(520.0, 0.0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(box)
	_title = PUi.label(TITLE_PORTRAIT, 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_note = PUi.label(NOTE_PORTRAIT, 15, PUi.DIM)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	var row := PUi.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_resume = PUi.button(RESUME_TEXT, _on_resume, true, 20)
	_resume.custom_minimum_size = Vector2(200.0, PLayout.primary_button_height())
	row.add_child(_resume)
	# 안내막 안의 '다시 들어가기'도 구석 버튼과 **같은 수준**으로 크게 한다(사용자 지시). PC는 예전 그대로
	_veil_fs = PUi.button(FS_TEXT, _on_fullscreen, true, 22 if PLayout.is_touch() else 15)
	if PLayout.is_touch():
		_veil_fs.custom_minimum_size = Vector2(360.0, CORNER_TOUCH_H)
		_resume.custom_minimum_size = Vector2(220.0, CORNER_TOUCH_H)
		_resume.add_theme_font_size_override("font_size", CORNER_TOUCH_FS)
		paint(_veil_fs)
	else:
		_veil_fs.custom_minimum_size = Vector2(0.0, PLayout.primary_button_height())
	row.add_child(_veil_fs)
	add_child(_veil)

## 전체화면 버튼 겉모습: 배경과 확실히 갈리는 금색 판 + 어두운 글자 + 넉넉한 안쪽 여백.
## 전투 화면(어두운 띠·초록 전장) 어디에 놓여도 눈에 들어와야 한다. 다른 화면이 쓸 수 있게 공개한다
static func paint(b: Button, fs: int = CORNER_TOUCH_FS) -> void:
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", CORNER_FG)
	b.add_theme_color_override("font_hover_color", CORNER_FG)
	b.add_theme_color_override("font_pressed_color", CORNER_FG)
	b.add_theme_color_override("font_focus_color", CORNER_FG)
	var pad_x: float = maxf(16.0, float(fs) * 0.9)
	var pad_y: float = maxf(10.0, float(fs) * 0.6)
	for pair in [["normal", CORNER_BG], ["hover", CORNER_BG_ON], ["pressed", CORNER_BG_DOWN], ["focus", CORNER_BG_ON], ["disabled", CORNER_BG]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = pair[1]
		sb.border_color = CORNER_LINE
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = pad_x
		sb.content_margin_right = pad_x
		sb.content_margin_top = pad_y
		sb.content_margin_bottom = pad_y
		b.add_theme_stylebox_override(String(pair[0]), sb)

func _build_corner() -> void:
	_corner = PUi.button(CORNER_TEXT, _on_fullscreen, true, CORNER_PC_FS)
	_corner.name = "CornerFullscreen"
	_corner.set_anchors_preset(Control.PRESET_TOP_LEFT) # 자리는 layout()이 안전 영역으로 정한다
	if PLayout.is_touch():
		paint(_corner)
	add_child(_corner)
	layout(_safe)

func _on_resume() -> void:
	resume_pressed.emit()

func _on_fullscreen() -> void:
	fullscreen_pressed.emit()

## 안전 영역이 바뀌면(주소창 표시·전체화면 전환·회전) 구석 버튼을 다시 놓는다.
## 크기·글자도 여기서 다시 정한다 — 주소창이 뜨고 지며 화면 높이가 바뀌어도 잘리지 않게
func layout(safe: Rect2) -> void:
	_safe = safe
	if _corner == null:
		return
	var m: Dictionary = corner_metrics(safe, PLayout.is_touch())
	var r: Rect2 = m.rect
	_corner.offset_left = r.position.x
	_corner.offset_top = r.position.y
	_corner.offset_right = r.end.x
	_corner.offset_bottom = r.end.y
	if PLayout.is_touch():
		paint(_corner, int(m.font))
	else:
		_corner.add_theme_font_size_override("font_size", int(m.font))

## 전체화면 버튼이 차지한 자리(보이든 안 보이든 늘 같은 값). 조작 열·전장 배치가 이 아래를 쓴다
func corner_rect() -> Rect2:
	var m: Dictionary = corner_metrics(_safe, PLayout.is_touch())
	var r: Rect2 = m.rect
	return r

## main이 정한 상태를 그대로 그린다.
##  portrait         = 지금 세로다
##  waiting_resume   = 세로 때문에 멈춘 전투가 아직 '계속'을 기다린다
##  offer_fullscreen = 전체화면을 쓰다가 빠져나온 상태다(다시 들어가는 길을 보여 준다)
func apply(portrait: bool, waiting_resume: bool, offer_fullscreen: bool) -> void:
	var veil_on: bool = portrait or waiting_resume
	if _veil != null:
		_veil.visible = veil_on
	if _corner != null:
		_corner.visible = offer_fullscreen and not veil_on
	if not veil_on:
		return
	_title.text = TITLE_PORTRAIT if portrait else TITLE_PAUSED
	if portrait:
		_note.text = NOTE_PORTRAIT_PAUSED if waiting_resume else NOTE_PORTRAIT
	else:
		_note.text = NOTE_PAUSED
	_resume.visible = waiting_resume and not portrait # 세로에서는 '계속'을 주지 않는다
	_veil_fs.visible = offer_fullscreen

# ---------- 상태 읽기(검사·다른 화면용) ----------
func veil_visible() -> bool:
	return _veil != null and _veil.visible

func resume_visible() -> bool:
	return veil_visible() and _resume != null and _resume.visible

func fullscreen_visible() -> bool:
	return (_corner != null and _corner.visible) or (veil_visible() and _veil_fs != null and _veil_fs.visible)

func resume_button() -> Button:
	return _resume

## 지금 눌 수 있는 전체화면 버튼(구석 또는 안내막 안). 없으면 null
func fullscreen_button() -> Button:
	if _corner != null and _corner.visible:
		return _corner
	if veil_visible() and _veil_fs != null and _veil_fs.visible:
		return _veil_fs
	return null

func message_text() -> String:
	return _title.text if _title != null else ""
