extends SceneTree
## 입력 라우터·터치 오버레이·배치 헬퍼·거점 마을 시험(headless).
## 실행: APPDATA를 별도 폴더로 두고 godot --headless --path prophecy_godot -s tests/input_tests.gd (마을 시험이 실제 main.tscn과 user:// 저장을 쓴다)
## - 키보드 경로: PInputRouter.poll()이 godot-0.4.3 combat_view.gd의 인라인 코드(_old_poll, 같은 식)와 같은 값을 준다.
## - 누름은 PStepDriver에 기록되어 다음 단계에서 정확히 1번 소비된다(프레임 독립).
## - 가상 스틱(데드존·정규화)·유지 회피는 스틱 이동과 무관·터치 index별 추적·재사용 대기 매핑.
## 사람 입력 합성이 아니다: Input.action_press와 InputEvent 객체로 같은 코드 경로를 부른다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 화면 안에서 보이는 버튼을 글자로 찾는다(숨은 옛 확인 창의 버튼을 잡지 않는다)
func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.is_visible_in_tree() and String((node as Button).text).find(text) >= 0:
		return node as Button
	for c in node.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

func _init() -> void:
	call_deferred("_run")

## godot-0.4.3 combat_view.gd _process의 인라인 입력 코드(비교 기준)
static func _old_poll() -> Dictionary:
	var mx := 0.0
	var my := 0.0
	if Input.is_action_pressed("move_left"):
		mx -= 1.0
	if Input.is_action_pressed("move_right"):
		mx += 1.0
	if Input.is_action_pressed("move_up"):
		my -= 1.0
	if Input.is_action_pressed("move_down"):
		my += 1.0
	return { "mx": mx, "my": my, "held": Input.is_action_pressed("dodge") }

static func _same(a: Dictionary, b: Dictionary) -> bool:
	return float(a.mx) == float(b.mx) and float(a.my) == float(b.my) and bool(a.held) == bool(b.held)

static func _act(name: String, pressed: bool) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = pressed
	return ev

static func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "dodge"]:
		Input.action_release(a)

func _new_state() -> CombatState:
	var G := preload("res://scripts/game/game.gd")
	var cfg: Dictionary = G.config_with(G.load_config(), "hold", 1.5, "x5", 2)
	var st := CombatState.first_fight(cfg, 1)
	st.spawn_hold = true
	st.intro = 0.0
	return st

## 터치 오버레이가 보는 최소한의 전투 화면 대역(running·paused·bot·driver·st)
class FakeView extends Node:
	var running := true
	var paused := false
	var bot = null
	var driver := PStepDriver.new()
	var st: CombatState = null

func _run() -> void:
	var STEP: float = PStepDriver.STEP
	# ---------- A. 키보드 경로 = 0.4.3 인라인 코드 ----------
	var router := PInputRouter.new()
	_release_all()
	ok("A1 대기: 라우터 = 옛 코드 = (0,0,false)", _same(router.poll(), _old_poll()) and float(router.poll().mx) == 0.0 and not bool(router.poll().held))
	Input.action_press("move_left")
	Input.action_press("move_up")
	Input.action_press("dodge")
	var p := router.poll()
	ok("A2 왼쪽+위+회피 유지: (-1,-1,true), 옛 코드와 동일", _same(p, _old_poll()) and float(p.mx) == -1.0 and float(p.my) == -1.0 and bool(p.held), str(p))
	Input.action_press("move_right")
	p = router.poll()
	ok("A3 왼쪽+오른쪽 동시 = 0(합), 옛 코드와 동일", _same(p, _old_poll()) and float(p.mx) == 0.0, str(p))
	_release_all()
	Input.action_press("move_down")
	p = router.poll()
	ok("A4 아래만: (0,1,false)", _same(p, _old_poll()) and float(p.my) == 1.0 and not bool(p.held))
	_release_all()
	ok("A5 모두 뗌: (0,0,false)", _same(router.poll(), _old_poll()) and float(router.poll().my) == 0.0)
	# ---------- B. 누름 기록·1회 소비(프레임 독립) ----------
	var driver := PStepDriver.new()
	var st := _new_state()
	router.handle_event(_act("dodge", true), driver)
	ok("B1 회피 누름 이벤트 → driver.press_pending, preview.dodge_press", driver.press_pending and bool(router.preview(driver).dodge_press) and not bool(router.preview(driver).dodge_held))
	var n := driver.frame(st, STEP * 5.0 + 0.0001, 0.0, 0.0, false)
	ok("B2 한 프레임 5단계: 누름은 첫 단계에서 1번만 소비(회피 1회 시작, pending 해제)", n == 5 and not driver.press_pending and int(st.stats.dodges) == 1 and bool(st.player.dodge_active), "n=%d dodges=%d" % [n, int(st.stats.dodges)])
	driver.frame(st, STEP * 3.0 + 0.0001, 0.0, 0.0, false)
	ok("B3 다음 프레임: 새 누름 없음 → 회피 수 그대로", int(st.stats.dodges) == 1)
	router.handle_event(_act("dodge", false), driver)
	ok("B4 뗌 이벤트는 누름으로 기록되지 않음", not driver.press_pending)
	var echo := InputEventKey.new()
	echo.keycode = KEY_SPACE
	echo.pressed = true
	echo.echo = true
	router.handle_event(echo, driver)
	ok("B5 키 반복(echo)은 무시", not driver.press_pending)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	router.handle_event(key, driver)
	ok("B6 실제 키(Space) 누름은 InputMap을 거쳐 기록", driver.press_pending)
	driver.reset()
	router.handle_event(_act("slowfield", true), driver)
	router.handle_event(_act("skill_e", true), driver)
	var pv := router.preview(driver)
	ok("B7 Q·E 누름 → special·skill_e 미리 보기 true", bool(pv.special) and bool(pv.skill_e) and not bool(pv.dodge_press))
	driver.frame(st, STEP + 0.0001, 0.0, 0.0, false)
	ok("B8 한 단계 뒤 Q·E pending 해제, Q 사용 1회", not driver.special_pending and not driver.e_pending and int(st.stats.special_uses) == 1, "q=%d" % int(st.stats.special_uses))
	# ---------- C. 가상 스틱 벡터 ----------
	var z := PInputRouter.stick_vector(Vector2(10.0, 0.0), 64.0)
	ok("C1 데드존 안(0.156 < 0.2) → 0", z == Vector2.ZERO and PInputRouter.stick_vector(Vector2.ZERO, 64.0) == Vector2.ZERO)
	var full := PInputRouter.stick_vector(Vector2(64.0, 0.0), 64.0)
	ok("C2 반지름 끝 → (1,0)", full.is_equal_approx(Vector2(1.0, 0.0)), str(full))
	var over := PInputRouter.stick_vector(Vector2(0.0, 300.0), 64.0)
	ok("C3 반지름 밖 → 길이 1로 자름, 방향 유지", over.is_equal_approx(Vector2(0.0, 1.0)), str(over))
	var half := PInputRouter.stick_vector(Vector2(0.0, -38.4), 64.0)
	ok("C4 중간(0.6) → 데드존 뒤 재매핑 0.5", half.is_equal_approx(Vector2(0.0, -0.5)), str(half))
	var diag := PInputRouter.stick_vector(Vector2(64.0, 64.0), 64.0)
	ok("C5 대각선 → 정규화된 방향(0.707,0.707)", diag.is_equal_approx(Vector2(1.0, 1.0).normalized()), str(diag))
	# ---------- D. 라우터 가상 상태 합성 ----------
	router.set_virtual_move(Vector2(0.5, 0.0))
	p = router.poll()
	ok("D1 가상 스틱(0.5,0), 키보드 없음 → mx 0.5, held false", float(p.mx) == 0.5 and float(p.my) == 0.0 and not bool(p.held))
	router.set_virtual_held(true)
	Input.action_press("move_left")
	p = router.poll()
	ok("D2 키보드 왼쪽 + 가상 스틱 0.5 + 가상 유지 → (-0.5, 0, true)", float(p.mx) == -0.5 and bool(p.held), str(p))
	_release_all()
	router.virtual_press("dodge", driver)
	ok("D3 가상 회피 누름 → press_pending", driver.press_pending)
	driver.reset()
	router.reset()
	p = router.poll()
	ok("D4 reset: 가상 상태 폐기 → (0,0,false)", float(p.mx) == 0.0 and not bool(p.held))
	# ---------- E. 터치 오버레이(멀티터치) ----------
	var fake := FakeView.new()
	fake.st = _new_state()
	root.add_child(fake)
	var tc := PTouchControls.new()
	root.add_child(tc)
	tc.enabled = true
	var r2 := PInputRouter.new()
	tc.bind(fake, r2)
	tc.layout(Rect2(0.0, 0.0, 960.0, 640.0))
	await process_frame
	var zone := tc.zone_rect()
	ok("E1 스틱 영역 = 안전 영역 왼쪽 45%, HUD 아래", zone.position == Vector2(0.0, 44.0) and is_equal_approx(zone.size.x, 432.0) and is_equal_approx(zone.end.y, 640.0), str(zone))
	var dc := tc.button_center("dodge")
	var qc := tc.button_center("special")
	var ec := tc.button_center("e")
	ok("E2 버튼 지름 ≥ 72(회피 96, Q·E 76), 모두 안전 영역 안", PTouchControls.button_radius("dodge") * 2.0 >= 72.0 and PTouchControls.button_radius("special") * 2.0 >= 72.0 and dc.x + 48.0 <= 960.0 and dc.y + 48.0 <= 640.0 and qc.x - 38.0 >= zone.end.x and ec.y - 38.0 >= 44.0, "dodge=%s q=%s e=%s" % [dc, qc, ec])
	ok("E3 버튼끼리 겹치지 않음", dc.distance_to(qc) >= 48.0 + 38.0 and dc.distance_to(ec) >= 48.0 + 38.0 and qc.distance_to(ec) >= 76.0)
	ok("E4 active(): 진행 중·봇 없음·정지 아님", tc.active())
	tc.handle_touch(0, Vector2(150.0, 400.0), true)
	ok("E5 왼쪽 영역 터치 0 → 스틱 잡음, 이동 0", tc.stick_held() and r2.virtual_move == Vector2.ZERO)
	tc.handle_drag(0, Vector2(214.0, 400.0))
	ok("E6 끌기 +64px → 이동 (1,0)", r2.virtual_move.is_equal_approx(Vector2(1.0, 0.0)), str(r2.virtual_move))
	tc.handle_touch(1, dc, true)
	ok("E7 터치 1로 회피 버튼 → 누름 기록 + 유지 true", tc.button_held("dodge") and r2.virtual_held and fake.driver.press_pending)
	tc.handle_drag(0, Vector2(150.0, 336.0))
	ok("E8 스틱을 움직여도(터치 0) 회피 유지는 그대로(터치 1)", r2.virtual_move.is_equal_approx(Vector2(0.0, -1.0)) and r2.virtual_held and tc.button_held("dodge"), str(r2.virtual_move))
	var st2: CombatState = fake.st
	var pv2 := r2.preview(fake.driver)
	ok("E9 다음 단계 입력 = {mx 0, my -1, dodge_press true, dodge_held true}", float(pv2.mx) == 0.0 and float(pv2.my) == -1.0 and bool(pv2.dodge_press) and bool(pv2.dodge_held))
	var a := r2.poll()
	fake.driver.frame(st2, STEP * 2.0 + 0.0001, float(a.mx), float(a.my), bool(a.held))
	ok("E10 프레임 뒤: 누름 1회 소비(pending 해제)·유지는 계속·회피 시작", not fake.driver.press_pending and r2.virtual_held and int(st2.stats.dodges) == 1)
	tc.handle_touch(1, Vector2(dc.x + 30.0, dc.y), false)
	ok("E11 터치 1 뗌 → 유지 해제, 스틱은 그대로", not r2.virtual_held and not tc.button_held("dodge") and tc.stick_held() and r2.virtual_move.is_equal_approx(Vector2(0.0, -1.0)))
	fake.driver.reset()
	tc.handle_touch(2, ec, true)
	ok("E12 터치 2로 E 탭 → e_pending", fake.driver.e_pending and tc.button_held("e"))
	tc.handle_touch(2, ec, false)
	ok("E13 E 뗌 → 버튼 해제, pending은 소비 전까지 유지", not tc.button_held("e") and fake.driver.e_pending)
	tc.handle_touch(3, qc, true)
	ok("E14 터치 3으로 Q → special_pending", fake.driver.special_pending)
	tc.handle_touch(3, qc, false)
	tc.handle_touch(4, Vector2(300.0, 300.0), true)
	ok("E15 스틱을 잡은 채 영역에 두 번째 터치 → 무시(스틱 1개)", tc.stick_held() and r2.virtual_move.is_equal_approx(Vector2(0.0, -1.0)))
	tc.handle_touch(4, Vector2(300.0, 300.0), false)
	tc.handle_touch(5, Vector2(700.0, 300.0), true)
	ok("E16 오른쪽 빈 곳 터치 → 스틱도 버튼도 아님", tc.stick_held() and not tc.button_held("dodge") and not tc.button_held("special") and not tc.button_held("e"))
	tc.handle_touch(5, Vector2(700.0, 300.0), false)
	tc.handle_touch(0, Vector2(150.0, 336.0), false)
	ok("E17 터치 0 뗌 → 스틱 해제, 이동 0", not tc.stick_held() and r2.virtual_move == Vector2.ZERO)
	fake.driver.reset()
	fake.paused = true
	tc.handle_touch(6, dc, true)
	ok("E18 정지 중 누름은 받지 않음", not tc.button_held("dodge") and not fake.driver.press_pending and not r2.virtual_held)
	fake.paused = false
	tc.handle_touch(7, dc, true)
	fake.paused = true
	await process_frame
	ok("E19 잡은 채 정지되면 _process가 모두 해제(가상 상태 폐기)", not tc.button_held("dodge") and not r2.virtual_held)
	fake.paused = false
	st2.player.dodge_cd = 0.75
	st2.player.special_cd = float(st2.cfg.player.slowfield.cooldown)
	var fill := PTouchControls.cooldown_fill(st2)
	ok("E20 재사용 채움: 회피 0.75/1.5 → 0.5, Q 방금 씀 → 0, E 없음 → has_e false", is_equal_approx(float(fill.dodge), 0.5) and is_equal_approx(float(fill.special), 0.0) and not bool(fill.has_e) and float(fill.e) == 0.0, str(fill))
	st2.player.dodge_cd = 0.0
	st2.player.special_cd = 0.0
	fill = PTouchControls.cooldown_fill(st2)
	ok("E21 대기 0 → 채움 1", is_equal_approx(float(fill.dodge), 1.0) and is_equal_approx(float(fill.special), 1.0))
	tc.queue_free()
	fake.queue_free()
	# ---------- F. 배치 헬퍼 ----------
	ok("F1 비율 묶음: 2340×1080 wide · 1280×720 standard · 1024×768 narrow · 1920×1200 standard · 960×640 standard", PLayout.aspect_bucket(Vector2(2340, 1080)) == "wide" and PLayout.aspect_bucket(Vector2(1280, 720)) == "standard" and PLayout.aspect_bucket(Vector2(1024, 768)) == "narrow" and PLayout.aspect_bucket(Vector2(1920, 1200)) == "standard" and PLayout.aspect_bucket(Vector2(960, 640)) == "standard")
	var scale := 1080.0 / 640.0 # 2340×1080 창: canvas_items+expand → 배율 1.6875, canvas 1386.67×640
	var vis := Rect2(0.0, 0.0, 2340.0 / scale, 640.0)
	var xf := Transform2D(0.0, Vector2.ZERO).scaled(Vector2(scale, scale))
	var safe := PLayout.map_safe(vis, Rect2i(0, 0, 2340, 1080), Rect2i(80, 0, 2180, 1080), xf)
	ok("F2 왼쪽 80px 노치 → canvas 안전 영역 x 47.4, 너비 1291.9, 높이 640", is_equal_approx(safe.position.x, 80.0 / scale) and is_equal_approx(safe.size.x, 2180.0 / scale) and is_equal_approx(safe.size.y, 640.0) and safe.position.y == 0.0, str(safe))
	var none := PLayout.map_safe(vis, Rect2i(0, 0, 2340, 1080), Rect2i(), xf)
	ok("F3 안전 영역 정보 없음(빈 사각형) → 보이는 영역 전체", none == vis)
	var whole := PLayout.map_safe(vis, Rect2i(100, 100, 2340, 1080), Rect2i(0, 0, 3840, 2160), xf)
	ok("F4 창이 화면 안전 영역 안에 있으면 전체", whole == vis, str(whole))
	var off := PLayout.map_safe(vis, Rect2i(0, 0, 2340, 1080), Rect2i(2000, 0, 340, 1080), xf)
	ok("F5 비정상(절반 미만) → 전체로 방어", off == vis)
	ok("F6 열 비율·마을 높이: wide 0.6/200 · standard 0.57/180 · narrow 0.55/220", PLayout.left_ratio("wide") == 0.6 and PLayout.village_height("wide") == 200.0 and PLayout.left_ratio("standard") == 0.57 and PLayout.village_height("narrow") == 220.0)
	# ---------- G. 거점 마을(실제 main.tscn, headless) ----------
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.start_run("sword")
	await process_frame
	await process_frame
	var base = main.screens["base"]
	var vm: PVillageMap = base.village
	ok("G1 새 회차 → 거점에 마을 그림(PVillageMap) 있음", main.screen == "base" and vm != null and is_instance_valid(vm))
	var all_big := true
	var zones := ""
	for id in ["forge", "shop", "equip", "stats", "rest"]:
		var zr: Rect2 = vm.zone(id)
		zones += "%s=%s " % [id, zr.size]
		if zr.size.x < 72.0 or zr.size.y < 72.0:
			all_big = false
	ok("G2 건물 5개 모두 클릭/탭 영역 ≥ 72px", all_big and vm.size.x > 0.0, zones)
	ok("G3 휴식 건물 라벨 = 다음 시간대, 사용 가능 = PRun.can_rest", vm.button("rest").text.begins_with("휴식") and vm.button("rest").disabled == (not PRun.can_rest(main.run)), vm.button("rest").text)
	vm.button("shop").pressed.emit()
	ok("G4 상점 건물 → 상점 화면(같은 main.show)", main.screen == "shop")
	main.go_base()
	await process_frame
	vm = base.village
	vm.button("forge").pressed.emit()
	ok("G5 대장간 건물 → 대장간 화면", main.screen == "forge")
	main.go_base()
	await process_frame
	base.village.button("stats").pressed.emit()
	ok("G6 통계·기록 건물 → 통계 화면", main.screen == "stats")
	main.go_base()
	await process_frame
	base.village.button("equip").pressed.emit()
	ok("G7 장비 건물 → 장비 화면", main.screen == "equip")
	main.go_base()
	await process_frame
	var hours0: int = int(main.run.hours)
	base.village.button("rest").pressed.emit()
	await process_frame
	# 휴식은 이제 **확인 창**을 거친다(사용자 확정, 2026-09-09). 버튼을 누른 것만으로 시간이 줄지 않는다
	var rest_ok: Button = _find_button(base, "휴식한다")
	ok("G8 휴식 건물 → 확인 창(누른 것만으로 시간이 줄지 않는다)",
		rest_ok != null and main.screen == "base" and int(main.run.hours) == hours0,
		"창=%s hours %d" % [str(rest_ok != null), int(main.run.hours)])
	if rest_ok != null:
		rest_ok.pressed.emit()
		await process_frame
	ok("G8b 확정하면 PRun.rest(시간 1칸 소비), 거점 유지",
		main.screen == "base" and int(main.run.hours) == hours0 - 1, "hours %d→%d" % [hours0, int(main.run.hours)])
	base._toggle_build_detail()
	await process_frame
	ok("G9 빌드 '상세' 토글 → 전체 패널 펼침(거점 유지)", base._build_detail_open and main.screen == "base" and base.village != null)
	base._open_endday()
	ok("G10 하루 종료 확인 창은 그대로(자동 진행 경로)", base._confirm.visible and base.default_button != null)
	ok("G11 Esc → 확인 창 닫힘", base.on_escape() and not base._confirm.visible)
	main.view.running = false
	main.queue_free()
	await process_frame
	PSave.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
