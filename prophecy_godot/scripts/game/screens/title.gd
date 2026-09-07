class_name PTitleScreen
extends PScreen
## 제목 화면: 새 회차 / 계속하기 / 검증 메뉴 / 조작법 / 설정 / 종료. 기본 화면에는 개발용 설명을 두지 않는다(PROJECT_CONTEXT §4, D11).
## 검증 메뉴(접힘): 기준 전투(첫 전투, 0.3.1 D33) · 시작 기술 첫 전투 비교 · 관문 빌드 보스전 · 봇 회차 데모.

var _verify_open := false
var _confirm_new := false
var _seed_spin: SpinBox
var _bot_check: CheckBox
var _menu: VBoxContainer

func _build() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	_menu = PUi.vbox(8)
	_menu.custom_minimum_size = Vector2(520, 0)
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_menu)

func refresh() -> void:
	PUi.clear(_menu)
	PUi.clear(bottom)
	var saved := PSave.load() if PSave.exists() else {}
	var h := PUi.label("예언의 시간표 (가칭)", 36)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(h)
	var sub := PUi.label("마검사의 준비 기간 — 액션 로그라이트", 14, PUi.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(sub)
	_menu.add_child(PUi.spacer(8))
	if _confirm_new:
		var c := PUi.card("새 회차를 시작할까요?", PUi.CARD_BOSS)
		(c.box as VBoxContainer).add_child(PUi.rich("기존 저장(진행 중인 회차)이 덮어씌워집니다.", 13))
		var row := PUi.hbox(8)
		row.add_child(PUi.button("새 회차 시작", _on_new_confirm, true, 15))
		row.add_child(PUi.button("돌아가기", _on_back, true, 15))
		(c.box as VBoxContainer).add_child(row)
		_menu.add_child(c.panel)
		return
	var cont_txt := "계속하기"
	if not saved.is_empty():
		cont_txt = "계속하기  (%d일차 · Lv %d · 금화 %d · 저장 %s)" % [int(saved.get("day", 1)), int(saved.growth.level), int(saved.get("gold", 0)), "v%d" % int(saved.get("version", 0))]
	var cont := PUi.button(cont_txt, func(): main.continue_run(), not saved.is_empty(), 18)
	_menu.add_child(cont)
	var newb := PUi.button("새 회차", _on_new, true, 18)
	_menu.add_child(newb)
	default_button = cont if not saved.is_empty() else newb
	var p: Dictionary = main.profile
	var meta_txt := "영구 성장"
	if not p.is_empty():
		var PK := PCatalog.meta_profiles()
		meta_txt = "영구 성장  (%s · Lv %d · 특성 %d개)" % [String(PK[String(p.kind)].name), PProfile.level(p), PProfile.selected_traits(p).size()]
	_menu.add_child(PUi.button(meta_txt, func(): main.show_meta(), true, 15))
	_menu.add_child(PUi.button("검증 메뉴 " + ("▾" if _verify_open else "▸"), _toggle_verify, true, 15))
	if _verify_open:
		_menu.add_child(_verify_panel())
	_menu.add_child(PUi.button("조작법", func(): main.show_controls(true), true, 15))
	_menu.add_child(PUi.button("설정", func(): main.open_settings(), true, 15))
	_menu.add_child(PUi.button("종료", func(): get_tree().quit(), true, 15))
	_menu.add_child(PUi.spacer(6))
	var bal := String(PCatalog.balance().balance_default)
	var BS := PCatalog.balance_sets()
	var bal_name := String(BS[bal].name) if BS.has(bal) else bal
	var line := "%s · %s" % [PUi.version(), bal_name]
	if not saved.is_empty():
		line += " · 저장 회차: %s · 시드 %d" % [PUi.balance_name(saved), int(saved.seed)]
	var foot := PUi.label(line, 11, PUi.DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(foot)

func _on_new() -> void:
	if PSave.exists():
		_confirm_new = true
		refresh()
	else:
		main.new_run_flow()

func _on_new_confirm() -> void:
	_confirm_new = false
	main.new_run_flow()

func _on_back() -> void:
	_confirm_new = false
	refresh()

func _toggle_verify() -> void:
	_verify_open = not _verify_open
	refresh()

func _verify_panel() -> Control:
	var c := PUi.card("검증 메뉴 [color=#9ea8b8](검증용 회차는 현재 저장을 덮어쓰고 기록에 남지 않음)[/color]", PUi.CARD, 13)
	var box: VBoxContainer = c.box
	var row0 := PUi.hbox(8)
	row0.add_child(PUi.label("시드", 13, Color.WHITE, false))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 1.0
	_seed_spin.max_value = 99999.0
	_seed_spin.value = float(main.seed_v)
	_seed_spin.value_changed.connect(func(v: float): main.seed_v = int(v))
	row0.add_child(_seed_spin)
	_bot_check = CheckBox.new()
	_bot_check.text = "봇 조작으로 보기 (같은 규칙·같은 행동 형식)"
	_bot_check.button_pressed = bool(main.use_bot)
	_bot_check.add_theme_font_size_override("font_size", 12)
	row0.add_child(_bot_check)
	box.add_child(row0)
	var ff := PCatalog.first_fight()
	var ff_txt := "기준 전투 (첫 전투, 0.3.1 D33 · 근교 숲 · 검격 Lv%d · 늑대)" % int(ff.weapon.level)
	box.add_child(PUi.button(ff_txt, func(): main.start_fight(_bot_check.button_pressed), true, 13))
	box.add_child(PUi.rich("[color=#9ea8b8]시작 기술 첫 전투 비교[/color] (새 회차 1일차 첫 숲 카드, 같은 시드)", 12))
	var row1 := PUi.hbox(6)
	for wid in PCatalog.startable():
		var id := String(wid)
		var nm := String(PCatalog.weapon(id).name)
		row1.add_child(PUi.button(nm, func(): main.quick_start_fight(id, _bot_check.button_pressed), true, 13))
	box.add_child(row1)
	box.add_child(PUi.rich("[color=#9ea8b8]관문 빌드 보스전[/color] (시험실 프리셋 빌드로 보스 입장)", 12))
	var row2 := PUi.hbox(6)
	var BUILDS: Dictionary = PCatalog.lab().BUILDS
	for key in ["stage1", "stage2", "stage3"]:
		if BUILDS.has(key):
			var k := String(key)
			row2.add_child(PUi.button(String(BUILDS[k].stage), func(): main.quick_boss_fight(k, _bot_check.button_pressed), true, 13))
	box.add_child(row2)
	box.add_child(PUi.button("봇 회차 데모 (선택: 봇이 새 회차를 첫 관문까지 진행)", func(): main.bot_demo(), true, 12))
	box.add_child(PUi.rich("[color=#6a7078]검증 정보·비교 설정은 전투 중 F3 패널.[/color]", 11))
	return c.panel

func on_escape() -> bool:
	if _confirm_new or _verify_open:
		_confirm_new = false
		_verify_open = false
		refresh()
		return true
	return false
