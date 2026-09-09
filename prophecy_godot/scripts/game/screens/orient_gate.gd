class_name POrientGate
extends Control
## 화면 방향·전체화면 안내막(표시 전용). 규칙 수치도, 조작 버튼 자리도 여기서 정하지 않는다.
## 무엇을 보일지는 main이 정해 apply()로 넘기고, 이 파일은 그것을 그리기만 한다.
##
## 세 가지 모습만 있다.
##  ① 세로: 화면 전체를 덮고 "휴대폰을 가로로 돌려주세요".
##  ② 가로로 돌아왔지만 아직 멈춰 있음: 화면 전체를 덮고 '계속' 버튼 — 저절로 재개하지 않는다.
##  ③ 그 밖에 전체화면에서 빠져나온 상태: 화면을 덮지 않고 오른쪽 위 구석에 작은 '전체화면' 버튼만.
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
const NOTE_PORTRAIT_PAUSED := "세로로 바뀌는 순간 전투를 멈추고 누르고 있던 조작을 놓았습니다.\n보이지 않는 동안에는 피해를 받지 않습니다. 가로로 돌리면 '계속' 버튼이 나옵니다."
const NOTE_PORTRAIT := "이 게임은 가로 화면에 맞춰 만들었습니다. 폰을 가로로 돌려 주세요."
const NOTE_PAUSED := "세로로 돌아가 있는 동안 멈춰 두었습니다. 저절로 다시 시작하지 않습니다 — 준비되면 '계속'을 누르세요."

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
	_veil_fs = PUi.button(FS_TEXT, _on_fullscreen, true, 15)
	_veil_fs.custom_minimum_size = Vector2(0.0, PLayout.primary_button_height())
	row.add_child(_veil_fs)
	add_child(_veil)

func _build_corner() -> void:
	_corner = PUi.button(CORNER_TEXT, _on_fullscreen, true, 13)
	_corner.name = "CornerFullscreen"
	_corner.set_anchors_preset(Control.PRESET_TOP_LEFT) # 자리는 layout()이 안전 영역으로 정한다
	add_child(_corner)
	layout(_safe)

func _on_resume() -> void:
	resume_pressed.emit()

func _on_fullscreen() -> void:
	fullscreen_pressed.emit()

## 안전 영역이 바뀌면(주소창 표시·전체화면 전환·회전) 구석 버튼을 다시 놓는다
func layout(safe: Rect2) -> void:
	_safe = safe
	if _corner == null:
		return
	_corner.offset_left = safe.end.x - 116.0
	_corner.offset_top = safe.position.y + 4.0
	_corner.offset_right = safe.end.x - 8.0
	_corner.offset_bottom = safe.position.y + 38.0

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
