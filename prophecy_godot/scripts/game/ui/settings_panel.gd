class_name PSettingsPanel
extends Control
## 설정 오버레이(음량 슬라이더·음소거). /root/Audio(PAudio)가 있으면 그 값을 읽고 쓴다. 없으면 표시만 하고 아무 것도 하지 않는다.

signal closed()

var _vol: HSlider
var _mute: CheckBox
var _shake: CheckBox   # 강한 타격 시 화면 흔들림(끄기 가능, user://render_prefs.json에 저장)
var _note: RichTextLabel
var _font_note: RichTextLabel   # 글꼴 라이선스 고지(OFL 1.1). 값이 바뀌지 않아 만들 때 한 번만 채운다.

func _audio() -> Node:
	return get_node_or_null("/root/Audio")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.1, 0.12, 0.15, 0.98), 8, 16, Color(0.5, 0.6, 0.75, 0.9)))
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var v := PUi.vbox(10)
	panel.add_child(v)
	v.add_child(PUi.rich("[b]설정[/b]", 22))
	var row := PUi.hbox(8)
	row.add_child(PUi.label("음량", 14, Color.WHITE, false))
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 100.0
	_vol.step = 1.0
	_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol.value_changed.connect(func(vv: float):
		var a := _audio()
		if a != null:
			a.set_volume(vv / 100.0))
	row.add_child(_vol)
	v.add_child(row)
	_mute = CheckBox.new()
	_mute.text = "음소거"
	_mute.toggled.connect(func(on: bool):
		var a := _audio()
		if a != null:
			a.set_muted(on))
	v.add_child(_mute)
	_shake = CheckBox.new()
	_shake.text = "강한 타격 시 화면 흔들림"
	_shake.button_pressed = PRender.shake_on()
	_shake.toggled.connect(func(on: bool): PRender.set_shake(on))
	v.add_child(_shake)
	_note = PUi.rich("", 11, PUi.DIM)
	v.add_child(_note)
	# 글꼴 고지: SIL OFL 1.1이 저작권 표시와 라이선스를 함께 배포하라고 요구한다.
	# 전문은 내보내기에 함께 담기는 assets/fonts/OFL.txt에 있고, 여기서는 그 경로까지 알려 준다.
	_font_note = PUi.rich("%s\n전문: %s" % [PUi.font_notice(), PUi.font_license_path()], 11, PUi.DIM)
	v.add_child(_font_note)
	v.add_child(PUi.button("닫기 (Esc)", func(): close(), true, 14))
	visible = false

func open() -> void:
	var a := _audio()
	if a != null:
		_vol.set_value_no_signal(float(a.volume) * 100.0)
		_mute.set_pressed_no_signal(bool(a.muted))
		_note.text = "소리는 합성음(외부 파일 없음). 값은 user://audio_prefs.json에 저장됩니다."
	else:
		_note.text = "오디오 노드(/root/Audio)가 없어 값이 적용되지 않습니다."
	visible = true

func close() -> void:
	var a := _audio()
	if a != null and a.has_method("save_prefs"):
		a.save_prefs()
	visible = false
	closed.emit()
