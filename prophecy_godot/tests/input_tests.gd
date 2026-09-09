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

# ---------- 모바일 조작 배치 점검 도구(H절) ----------
## 조작 원 목록 [이름, 중심, 반지름]. 스틱 끌기 영역은 사각형이라 따로 본다
static func _circles(tc: PTouchControls) -> Array:
	var out := []
	for kind in ["dodge", "special", "e"]:
		out.append([kind, tc.button_center(kind), PTouchControls.button_radius(kind)])
	out.append(["build", tc.build_button_center(), PTouchControls.BTN_BUILD_R])
	return out

## 원과 사각형이 겹치는가(사각형에서 가장 가까운 점까지의 거리가 반지름보다 작으면 겹친다)
static func _circle_hits_rect(c: Vector2, r: float, rect: Rect2) -> bool:
	var near := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return near.distance_to(c) < r - 0.001

## 배치 문제 목록(비면 통과): ① 안전 영역 밖으로 잘림 ② 조작끼리 겹침(버튼 사이 빈 틈 BTN_GAP 미만 포함)
## ③ 스틱 끌기 영역과 버튼이 겹침 ④ 안내 원이 끌기 영역 밖(그림만 있고 누를 수 없는 자리)
static func _layout_problems(tc: PTouchControls, safe: Rect2, tag: String) -> Array:
	var bad := []
	var cs := _circles(tc)
	var zone: Rect2 = tc.zone_rect()
	var gap_min: float = PTouchControls.BTN_GAP
	for i in range(cs.size()):
		var a: Array = cs[i]
		var ac: Vector2 = a[1]
		var ar: float = a[2]
		if ac.x - ar < safe.position.x - 0.001 or ac.y - ar < safe.position.y - 0.001 or ac.x + ar > safe.end.x + 0.001 or ac.y + ar > safe.end.y + 0.001:
			bad.append("%s %s 잘림 %s r%.0f" % [tag, String(a[0]), str(ac), ar])
		if _circle_hits_rect(ac, ar, zone):
			bad.append("%s %s 가 스틱 영역과 겹침" % [tag, String(a[0])])
		for j in range(i + 1, cs.size()):
			var b: Array = cs[j]
			var bc: Vector2 = b[1]
			var br: float = b[2]
			var gap: float = ac.distance_to(bc) - ar - br
			if gap < gap_min - 0.001:
				bad.append("%s %s↔%s 빈 틈 %.2f < %.0f" % [tag, String(a[0]), String(b[0]), gap, gap_min])
	if not safe.encloses(zone):
		bad.append("%s 스틱 영역이 안전 영역 밖 %s ⊄ %s" % [tag, str(zone), str(safe)])
	var g: Vector2 = tc.guide_center()
	var R: float = PTouchControls.STICK_R
	if g.x - R < zone.position.x - 0.001 or g.y - R < zone.position.y - 0.001 or g.x + R > zone.end.x + 0.001 or g.y + R > zone.end.y + 0.001:
		bad.append("%s 안내 원(%s r%.0f)이 끌기 영역 %s 밖" % [tag, str(g), R, str(zone)])
	return bad

## 노치·제스처 여백을 넣은 안전 영역(화면 px 아니라 canvas 좌표)
static func _notched(sz: Vector2) -> Rect2:
	return Rect2(24.0, 10.0, sz.x - 24.0 - 16.0, sz.y - 10.0 - 12.0)

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
	# 확대 뒤(2026-09-09): 안전 영역에서 제스처 여백 16을 들인 뒤 그 왼쪽 45%(928×0.45 = 417.6)가 끌기 영역이다
	ok("E1 스틱 영역 = (안전 영역 − 제스처 여백)의 왼쪽 45%, 상단 띠 아래", zone.position == Vector2(16.0, 44.0) and is_equal_approx(zone.size.x, 417.6) and is_equal_approx(zone.end.y, 624.0), str(zone))
	var dc := tc.button_center("dodge")
	var qc := tc.button_center("special")
	var ec := tc.button_center("e")
	var RD: float = PTouchControls.BTN_DODGE_R
	var RS: float = PTouchControls.BTN_SMALL_R
	ok("E2 버튼 지름 ≥ 72(회피 144, Q·E 114), 모두 안전 영역 안", RD * 2.0 >= 72.0 and RS * 2.0 >= 72.0 and dc.x + RD <= 944.0 and dc.y + RD <= 624.0 and qc.x - RS >= zone.end.x and ec.y - RS >= 44.0, "dodge=%s q=%s e=%s" % [dc, qc, ec])
	ok("E3 버튼끼리 겹치지 않음", dc.distance_to(qc) >= RD + RS and dc.distance_to(ec) >= RD + RS and qc.distance_to(ec) >= RS * 2.0)
	ok("E4 active(): 진행 중·봇 없음·정지 아님", tc.active())
	tc.handle_touch(0, Vector2(150.0, 400.0), true)
	ok("E5 왼쪽 영역 터치 0 → 스틱 잡음, 이동 0", tc.stick_held() and r2.virtual_move == Vector2.ZERO)
	tc.handle_drag(0, Vector2(150.0 + PTouchControls.STICK_R, 400.0))
	ok("E6 끌기 +바깥 반지름(128px) → 이동 (1,0)", r2.virtual_move.is_equal_approx(Vector2(1.0, 0.0)), str(r2.virtual_move))
	tc.handle_touch(1, dc, true)
	ok("E7 터치 1로 회피 버튼 → 누름 기록 + 유지 true", tc.button_held("dodge") and r2.virtual_held and fake.driver.press_pending)
	tc.handle_drag(0, Vector2(150.0, 400.0 - PTouchControls.STICK_R))
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
	tc.handle_touch(0, Vector2(150.0, 400.0 - PTouchControls.STICK_R), false)
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
	# ---------- H. 모바일 조작 확대(사용자가 실제 폰으로 플레이한 뒤의 지시, 2026-09-09) ----------
	# H1 배율은 **반지름** 기준이다(면적이 아니다). 확대 전 값은 touch_controls.gd의 BASE_*에 남아 있다
	ok("H1 조이스틱 바깥 반지름 정확히 2배 · 회피/Q/E 정확히 1.5배(반지름 기준)",
		PTouchControls.BASE_STICK_R == 64.0 and PTouchControls.STICK_R == PTouchControls.BASE_STICK_R * 2.0 and PTouchControls.STICK_R == 128.0
		and PTouchControls.BASE_BTN_DODGE_R == 48.0 and PTouchControls.BTN_DODGE_R == PTouchControls.BASE_BTN_DODGE_R * 1.5 and PTouchControls.BTN_DODGE_R == 72.0
		and PTouchControls.BASE_BTN_SMALL_R == 38.0 and PTouchControls.BTN_SMALL_R == PTouchControls.BASE_BTN_SMALL_R * 1.5 and PTouchControls.BTN_SMALL_R == 57.0
		and PTouchControls.KNOB_R == PTouchControls.BASE_KNOB_R * 2.0 and PTouchControls.KNOB_R == 44.0,
		"스틱 %.0f · 손잡이 %.0f · 회피 %.0f · Q·E %.0f" % [PTouchControls.STICK_R, PTouchControls.KNOB_R, PTouchControls.BTN_DODGE_R, PTouchControls.BTN_SMALL_R])
	ok("H1b 아이콘·숫자 글자도 같은 배율(회피 16→24 · Q·E 18→27 · 남은 초 13→20 · 미보유 11→17 · '이동' 12→24)",
		PTouchControls.FS_DODGE == 24 and PTouchControls.FS_SMALL == 27 and PTouchControls.FS_CD == 20 and PTouchControls.FS_NONE == 17 and PTouchControls.FS_MOVE == 24)
	var fake2 := FakeView.new()
	fake2.st = _new_state()
	root.add_child(fake2)
	var tc2 := PTouchControls.new()
	root.add_child(tc2)
	tc2.enabled = true
	var r3 := PInputRouter.new()
	tc2.bind(fake2, r3)
	tc2.gesture_pad = PLayout.GESTURE_PAD
	tc2.layout(Rect2(0.0, 0.0, 960.0, 640.0))
	await process_frame
	# H2 그림 반지름 = 터치 판정 반지름(둘 중 하나만 커지지 않았다). 판정은 실제 터치로 확인한다
	var g2 := tc2.draw_geometry()
	var draw_ok := true
	var hit_ok := true
	var hit_note := ""
	for kind in ["dodge", "special", "e"]:
		var spec: Dictionary = g2.buttons[kind]
		var r: float = PTouchControls.button_radius(kind)
		if not is_equal_approx(float(spec.radius), r):
			draw_ok = false
		var c: Vector2 = tc2.button_center(kind)
		tc2.handle_touch(60, c + Vector2(r - 0.5, 0.0), true)
		var inside: bool = tc2.button_held(kind)
		tc2.handle_touch(60, c, false)
		tc2.handle_touch(61, c + Vector2(r + 1.5, 0.0), true)
		var outside: bool = tc2.button_held(kind)
		tc2.handle_touch(61, c, false)
		if not inside or outside:
			hit_ok = false
		hit_note += "%s 안=%s 밖=%s " % [kind, str(inside), str(outside)]
	var gs2: Dictionary = g2.stick
	ok("H2 그림 반지름 = 터치 판정 반지름(버튼 3종 · 스틱)", draw_ok and hit_ok and is_equal_approx(float(gs2.radius), PTouchControls.STICK_R), hit_note)
	tc2.release_all()
	# H3 PC(키보드) HUD 크기 회귀: 터치 확대와 무관하게 조작 아이콘 3칸은 그대로다
	var pchud := PCombatHud.new()
	pchud.touch_mode = false
	root.add_child(pchud)
	await process_frame
	pchud.relayout(Rect2(0.0, 0.0, 960.0, 640.0))
	var mrow: Rect2 = pchud.manual_rect()
	# 확대 전과 같은 값이어야 한다: 아이콘 px은 비율 묶음별 narrow 44 · standard 48 · wide 52,
	# 칸 폭 = 아이콘 + 10, 칸 높이 = 아이콘 + 8 + 14(이름 한 줄), 3칸 사이 간격 8 두 번.
	var bk: String = PLayout.bucket_of(pchud.get_viewport())
	var icon_px: float = 48.0
	if bk == "narrow":
		icon_px = 44.0
	elif bk == "wide":
		icon_px = 52.0
	var expect_row := Vector2((icon_px + 10.0) * 3.0 + 16.0, icon_px + 22.0)
	ok("H3 PC 키보드 HUD 크기 불변(%s: 아이콘 %.0f → 칸 %.0f×%.0f → 줄 %s)" % [bk, icon_px, icon_px + 10.0, icon_px + 22.0, str(expect_row)], mrow.size.is_equal_approx(expect_row), str(mrow.size))
	ok("H3b PC 버튼 최소 크기 규격도 그대로(터치 대상 72 · 버튼 44 · 큰 버튼 PC 44)",
		PLayout.TOUCH_TARGET == 72.0 and PLayout.TOUCH_BUTTON_H == 44.0 and PLayout.primary_button_height() == (56.0 if PLayout.is_touch() else 44.0))
	# H4·H5 작은 가로 화면 전수: 겹침·잘림
	var sizes := [Vector2(640, 360), Vector2(720, 360), Vector2(854, 400), Vector2(960, 440), Vector2(1280, 540)]
	var probs := []
	var seen := []
	for sz in sizes:
		var rect_all := Rect2(Vector2.ZERO, sz)
		var tag := "%dx%d" % [int(sz.x), int(sz.y)]
		tc2.gesture_pad = 0.0
		tc2.layout(rect_all)
		probs += _layout_problems(tc2, rect_all, tag + " 여백0")
		tc2.gesture_pad = PLayout.GESTURE_PAD
		tc2.layout(rect_all)
		probs += _layout_problems(tc2, rect_all, tag + " 제스처16")
		seen.append(tag)
	var cut := []
	var ovl := []
	for m in probs:
		if String(m).find("잘림") >= 0:
			cut.append(m)
		else:
			ovl.append(m)
	ok("H4 확대 뒤에도 어떤 두 조작 영역도 겹치지 않는다(%s)" % " · ".join(seen), ovl.is_empty(), " / ".join(ovl))
	ok("H5 확대 뒤에도 안전 영역 밖으로 잘리지 않는다(같은 크기 목록)", cut.is_empty(), " / ".join(cut))
	# H6 노치·제스처 여백을 준 상태에서도 4·5가 성립한다
	var probs6 := []
	for sz in sizes:
		var notch := _notched(sz)
		tc2.gesture_pad = PLayout.GESTURE_PAD
		tc2.layout(notch)
		probs6 += _layout_problems(tc2, notch, "%dx%d 노치+제스처" % [int(sz.x), int(sz.y)])
	ok("H6 노치(좌24·우16·상10·하12) + 제스처 여백 16에서도 겹침·잘림 없음", probs6.is_empty(), " / ".join(probs6))
	# H7 이동 속도 불변의 근거: '끝까지 민' 입력 벡터가 확대 전후 같다
	var v_before := PInputRouter.stick_vector(Vector2(PTouchControls.BASE_STICK_R, 0.0), PTouchControls.BASE_STICK_R)
	var v_after := PInputRouter.stick_vector(Vector2(PTouchControls.STICK_R, 0.0), PTouchControls.STICK_R)
	var d_before := PInputRouter.stick_vector(Vector2(-0.6, 0.8) * PTouchControls.BASE_STICK_R, PTouchControls.BASE_STICK_R)
	var d_after := PInputRouter.stick_vector(Vector2(-0.6, 0.8) * PTouchControls.STICK_R, PTouchControls.STICK_R)
	ok("H7 손잡이를 끝까지 민 입력 벡터가 확대 전후 같다(최대 편차 기준을 반지름과 함께 키웠다)",
		v_before == v_after and v_after.is_equal_approx(Vector2(1.0, 0.0)) and d_before.is_equal_approx(d_after) and is_equal_approx(d_after.length(), 1.0),
		"%s = %s · 대각 %s" % [str(v_before), str(v_after), str(d_after)])
	tc2.gesture_pad = PLayout.GESTURE_PAD
	tc2.layout(Rect2(0.0, 0.0, 960.0, 640.0))
	var zp := Vector2(150.0, 400.0)
	tc2.handle_touch(70, zp, true)
	tc2.handle_drag(70, zp + Vector2(PTouchControls.STICK_R, 0.0))
	var real_full: Vector2 = r3.virtual_move
	tc2.handle_drag(70, zp + Vector2(PTouchControls.STICK_R * 3.0, 0.0))
	var over_full: Vector2 = r3.virtual_move
	var knob: Vector2 = tc2.draw_geometry().stick.knob
	ok("H7b 실제 경로도 같다: 반지름만큼 밀면 (1,0), 더 밀어도 (1,0)이고 손잡이는 반지름에서 멈춘다",
		real_full.is_equal_approx(Vector2(1.0, 0.0)) and over_full.is_equal_approx(Vector2(1.0, 0.0)) and is_equal_approx(knob.distance_to(zp), PTouchControls.STICK_R),
		"%s · %s · 손잡이 %.1f" % [str(real_full), str(over_full), knob.distance_to(zp)])
	ok("H7c 규칙은 이동 벡터를 PGeom.norm으로 다시 정규화한다(방향만 쓴다) → 스틱 크기는 속도에 닿지 않는다",
		PGeom.norm(1.0, 0.0) == PGeom.norm(0.5, 0.0) and PGeom.norm(0.3, 0.4) == PGeom.norm(0.6, 0.8))
	# H8 이동을 누른 채 회피·Q·E를 각각 쓸 수 있다(동시 입력 3가지)
	var dc2 := tc2.button_center("dodge")
	var qc2 := tc2.button_center("special")
	var ec2 := tc2.button_center("e")
	tc2.handle_drag(70, zp + Vector2(PTouchControls.STICK_R, 0.0))
	fake2.driver.reset()
	tc2.handle_touch(71, dc2, true)
	var both_dodge: bool = r3.virtual_move.is_equal_approx(Vector2(1.0, 0.0)) and r3.virtual_held and fake2.driver.press_pending
	tc2.handle_touch(71, dc2, false)
	fake2.driver.reset()
	tc2.handle_touch(72, qc2, true)
	var both_q: bool = r3.virtual_move.is_equal_approx(Vector2(1.0, 0.0)) and fake2.driver.special_pending and tc2.stick_held()
	tc2.handle_touch(72, qc2, false)
	fake2.driver.reset()
	tc2.handle_touch(73, ec2, true)
	var both_e: bool = r3.virtual_move.is_equal_approx(Vector2(1.0, 0.0)) and fake2.driver.e_pending and tc2.stick_held()
	tc2.handle_touch(73, ec2, false)
	ok("H8 이동을 누른 채 회피·Q·E가 각각 눌린다", both_dodge and both_q and both_e, "회피=%s Q=%s E=%s" % [str(both_dodge), str(both_q), str(both_e)])
	# H9 한 번의 터치가 두 버튼을 누르지 않는다(가장 가까운 하나만)
	var pairs := [["dodge", "special"], ["dodge", "e"], ["special", "e"], ["dodge", "build"], ["e", "build"]]
	var two_hit := []
	for pr in pairs:
		var an := String(pr[0])
		var bn := String(pr[1])
		var ac: Vector2 = tc2.build_button_center() if an == "build" else tc2.button_center(an)
		var bc: Vector2 = tc2.build_button_center() if bn == "build" else tc2.button_center(bn)
		var ar: float = PTouchControls.BTN_BUILD_R if an == "build" else PTouchControls.button_radius(an)
		var br: float = PTouchControls.BTN_BUILD_R if bn == "build" else PTouchControls.button_radius(bn)
		var mid: Vector2 = (ac + bc) * 0.5
		if mid.distance_to(ac) <= ar and mid.distance_to(bc) <= br:
			two_hit.append("%s↔%s 가운데가 둘 다 안" % [an, bn])
		fake2.driver.reset()
		tc2.handle_touch(74, mid, true)
		var held_n := 0
		for kind in ["dodge", "special", "e"]:
			if tc2.button_held(kind):
				held_n += 1
		if held_n > 1:
			two_hit.append("%s↔%s 가운데 터치로 %d개 눌림" % [an, bn, held_n])
		tc2.handle_touch(74, mid, false)
	ok("H9 버튼 사이 어디를 눌러도 두 기술이 동시에 나가지 않는다(가장 깊이 들어간 하나만)", two_hit.is_empty(), " / ".join(two_hit))
	# H10 손가락이 영역 밖으로 나가거나 입력이 취소되면 이동·버튼 눌림이 남지 않는다
	tc2.release_all()
	tc2.handle_touch(80, zp, true)
	tc2.handle_drag(80, zp + Vector2(PTouchControls.STICK_R, 0.0))
	tc2.handle_touch(81, dc2, true)
	var before_cancel: bool = tc2.stick_held() and tc2.button_held("dodge") and r3.virtual_move != Vector2.ZERO and r3.virtual_held
	tc2.handle_cancel(80)
	var stick_gone: bool = not tc2.stick_held() and r3.virtual_move == Vector2.ZERO and tc2.button_held("dodge")
	tc2.handle_cancel(81)
	var btn_gone: bool = not tc2.button_held("dodge") and not r3.virtual_held
	ok("H10 입력 취소(touch canceled): 그 손가락이 잡은 것만 풀리고 이동·눌림이 남지 않는다", before_cancel and stick_gone and btn_gone)
	tc2.handle_touch(82, zp, true)
	tc2.handle_drag(82, zp + Vector2(PTouchControls.STICK_R, 0.0))
	tc2.handle_drag(82, Vector2(-8.0, 400.0)) # 손가락이 화면(안전 영역) 왼쪽 밖으로 빠졌다
	var off_screen: bool = not tc2.stick_held() and r3.virtual_move == Vector2.ZERO
	tc2.handle_touch(83, zp, true)
	tc2.handle_touch(84, dc2, true)
	tc2._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var focus_gone: bool = not tc2.stick_held() and not tc2.button_held("dodge") and r3.virtual_move == Vector2.ZERO and not r3.virtual_held
	ok("H10b 손가락이 화면 밖으로 빠지거나 창이 뒤로 가면 스스로 놓는다", off_screen and focus_gone, "밖=%s 포커스=%s" % [str(off_screen), str(focus_gone)])
	# H11 화면 크기가 바뀌면(주소창 등장·전체화면·회전) 조작 자리와 터치 좌표를 다시 잡는다
	tc2.release_all()
	tc2.layout(Rect2(0.0, 0.0, 960.0, 640.0))
	var old_dodge := tc2.button_center("dodge")
	var old_zone := tc2.zone_rect()
	tc2.layout(Rect2(0.0, 0.0, 960.0, 540.0)) # 주소창이 나타나 화면이 낮아졌다
	var new_dodge := tc2.button_center("dodge")
	tc2.handle_touch(90, old_dodge, true)
	var stale: bool = tc2.button_held("dodge")
	tc2.handle_touch(90, old_dodge, false)
	tc2.handle_touch(91, new_dodge, true)
	var fresh: bool = tc2.button_held("dodge")
	tc2.handle_touch(91, new_dodge, false)
	tc2.layout(Rect2(0.0, 0.0, 1280.0, 540.0)) # 가로로 회전(더 넓어짐)
	var wide_zone := tc2.zone_rect()
	ok("H11 화면 크기가 바뀌면 조작 자리와 터치 판정이 함께 옮겨간다(옛 자리는 더 이상 눌리지 않는다)",
		new_dodge != old_dodge and not stale and fresh and wide_zone.size.x > old_zone.size.x,
		"회피 %s → %s · 영역 폭 %.1f → %.1f" % [str(old_dodge), str(new_dodge), old_zone.size.x, wide_zone.size.x])
	# H12 쿨다운 중 흑백 · 준비 시 컬러 · 준비 알림(회귀)
	var st3 := _new_state()
	st3.player.dodge_cd = 0.0
	st3.player.special_cd = 2.5
	pchud.sync_ready_silent(st3)
	pchud.update_from(st3)
	var qtile: PIconTile = pchud.manual_tile("q")
	var dtile: PIconTile = pchud.manual_tile("dodge")
	ok("H12 HUD 회귀: 재사용 대기 = 흑백 + 남은 초, 준비 = 컬러",
		pchud.ability_state("dodge") == PIconTile.ST_READY and pchud.ability_state("q") == PIconTile.ST_COOLDOWN and qtile.is_gray() and not dtile.is_gray() and is_equal_approx(qtile.cd_left, 2.5),
		"dodge=%s q=%s" % [pchud.ability_state("dodge"), pchud.ability_state("q")])
	var fired2 := []
	pchud.ready_signal.connect(func(a): fired2.append(a))
	st3.player.special_cd = 0.0
	pchud.update_from(st3)
	pchud.update_from(st3)
	ok("H12b 준비 알림은 false→true 순간에만 1회(그대로)", fired2 == ["q"], str(fired2))
	fake2.st.player.dodge_cd = 0.0
	fake2.st.player.special_cd = 2.5
	var g3 := tc2.draw_geometry()
	var bd3: Dictionary = g3.buttons["dodge"]
	var bq3: Dictionary = g3.buttons["special"]
	var be3: Dictionary = g3.buttons["e"]
	var ring_d: Color = bd3.ring
	var ring_q: Color = bq3.ring
	ok("H12c 터치 버튼도 같은 뜻: 준비 = 금색 꽉 찬 고리, 대기 = 채워지는 고리 + 남은 초, E 미보유 = '미보유'",
		ring_d == PTouchControls.RING_READY and float(bd3.ready) >= 1.0 and String(bd3.cd_text) == ""
		and ring_q == PTouchControls.RING_WAIT and float(bq3.ready) < 1.0 and String(bq3.cd_text) == "2.5"
		and not bool(be3.usable) and String(be3.cd_text) == "미보유",
		"회피=%s Q=%s(%s) E=%s" % [String(bd3.cd_text), String(bq3.cd_text), str(float(bq3.ready)), String(be3.cd_text)])
	tc2.queue_free()
	fake2.queue_free()
	pchud.queue_free()
	await process_frame
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
