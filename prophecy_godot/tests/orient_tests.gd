extends SceneTree
## 화면 방향(세로/가로)·전체화면 시험(headless, 실제 main.tscn 인스턴스).
## 실행: python tools/run_suites.py --suites orient_tests --jobs 1 (APPDATA·LOCALAPPDATA를 격리해 준다)
##
## 확인하는 것
##  A. 제목 화면에 '전체화면으로 시작' 버튼이 있고 눌린다(웹이 아니어도 오류가 없다)
##  B. 전체화면·방향 고정이 실패해도 게임이 계속 돈다
##  C. 세로 크기로 바꾸면 '가로로 돌려 달라'는 안내가 뜬다
##  D. 전투 중 세로로 바뀌면 일시정지되고, 여러 프레임을 굴려도 체력·적·전투 시간이 하나도 바뀌지 않는다
##  E. 세로 전환 순간 눌려 있던 입력(대기 누름·가상 스틱·터치 버튼)이 해제된다
##  F. 가로로 돌아와도 자동 재개하지 않는다 — '계속'을 눌러야 재개된다
##  G. 전체화면에서 나온 상태를 흉내내면 다시 들어가는 버튼이 나타난다
##  H. 화면 크기가 바뀌면 screen_metrics_changed 신호가 온다(조작 크기·자리 담당이 받는 창구)
##  I. PC 가로 창 기본 경로 회귀(안내막 없음 · Esc 일시정지/재개 그대로 · 기본 버튼 그대로)
##
## 창을 세로로 줄이는 것으로 폰 회전을 대신한다(판정은 화면 크기 비율뿐이라 같은 상태가 된다).
## 사람 입력 합성이 아니다: 버튼의 pressed 신호와 터치 오버레이의 공개 함수로 같은 코드 경로를 부른다.

var results := []
var metrics_seen := []   # screen_metrics_changed로 받은 값(H)

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

func _wait(n: int) -> void:
	for i in n:
		await process_frame

## 창 크기를 바꾼다(= 폰 회전·주소창 표시). size_changed → main._on_viewport_resized 경로를 그대로 탄다
func _resize(w: int, h: int) -> void:
	root.size = Vector2i(w, h)
	await _wait(2)

## 보이는 버튼을 글자로 찾는다
func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.is_visible_in_tree() and String((node as Button).text).find(text) >= 0:
		return node as Button
	for c in node.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

## 전투 상태 지문: 시간·단계·체력·적 배치(해시). 하나라도 달라지면 값이 달라진다
func _fight_sig(st: CombatState) -> String:
	return "t=%.4f step=%d hp=%.4f 적=%d 배치=%s" % [st.t, st.step_n, float(st.player.hp), (st.enemies as Array).size(), str(st.enemies).sha256_text().substr(0, 12)]

## 화면 프레임 대신 고정 간격으로 전투를 굴린다(멈춰 있으면 combat_view._process가 곧바로 돌아간다)
func _run_frames(view: Node, n: int, dt: float = 0.1) -> void:
	for i in n:
		view._process(dt)

func _on_metrics(m: Dictionary) -> void:
	metrics_seen.append(m)

func _run() -> void:
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await _resize(960, 640) # PC 가로 창 기준
	await _wait(2)
	main.screen_metrics_changed.connect(_on_metrics)
	var gate: POrientGate = main.orient

	# ---------- A. 제목 화면 '전체화면으로 시작' ----------
	ok("A0 시작은 가로 · 안내막 없음", main.screen == "title" and not main.is_portrait() and not gate.veil_visible(), "screen=%s vis=%s" % [main.screen, root.get_visible_rect().size])
	var title_scr = main.screens["title"]
	var fs_btn := _find_button(title_scr, PTitleScreen.FULLSCREEN_TEXT)
	ok("A1 제목 화면에 '%s' 버튼이 있고 눌 수 있다" % PTitleScreen.FULLSCREEN_TEXT, fs_btn != null and not fs_btn.disabled and fs_btn.is_visible_in_tree())
	var default_before: Button = title_scr.default_button
	ok("A2 Enter 기본 버튼은 그대로다(새로 생긴 버튼이 가로채지 않는다)", default_before != null and default_before != fs_btn, "기본=%s" % (default_before.text if default_before != null else "없음"))
	if fs_btn != null:
		fs_btn.pressed.emit() # 사용자 제스처 안에서 바로 요청하는 그 경로
	await _wait(2)
	var fres: Dictionary = main.last_fullscreen_result
	ok("A3 눌러도 오류 없이 지나가고 화면은 제목 그대로(회차가 시작되지 않는다)", main.screen == "title" and not fres.is_empty(), "결과=%s screen=%s" % [str(fres), main.screen])
	ok("A4 웹이 아니면 전체화면·방향 고정을 건너뛴다(조용히)", not bool(fres.get("web", true)) and String(fres.get("orientation", "")) == "건너뜀", str(fres))
	ok("A5 요청 사실은 남는다(다시 들어가는 버튼의 조건)", main.fullscreen_wanted() and not main.fullscreen_active())

	# ---------- B. 실패해도 게임이 계속 돈다 ----------
	main.new_run_flow()
	await _wait(2)
	ok("B1 전체화면 실패 뒤에도 새 회차 흐름이 정상(시작 선택 화면)", main.screen == "pick_start")
	main.start_run("sword")
	await _wait(2)
	ok("B2 회차 시작·거점 진입 정상(오류 화면 없음)", main.screen == "base" and not main.run.is_empty())

	# ---------- C. 세로 안내(전투 밖) ----------
	await _resize(480, 900)
	ok("C1 세로 크기 → 세로로 판정", main.is_portrait() and POrientGate.is_portrait(root.get_visible_rect().size), "canvas=%s" % root.get_visible_rect().size)
	ok("C2 '휴대폰을 가로로 돌려주세요' 안내가 화면을 덮는다", gate.veil_visible() and gate.message_text().find("가로") >= 0, gate.message_text())
	ok("C3 전투 중이 아니면 '계속' 버튼은 없다", not gate.resume_visible())
	await _resize(960, 640)
	ok("C4 가로로 되돌리면 안내가 사라진다", not main.is_portrait() and not gate.veil_visible())

	# ---------- D·E. 전투 중 세로 → 일시정지 · 입력 해제 ----------
	main.start_fight(false) # 기준 전투(D33 경로, 봇 없음)
	await _wait(2)
	var view = main.view
	var st: CombatState = view.st
	st.intro = 0.0 # 도입 연출을 건너뛰고 바로 적이 움직이게 한다(hud_tests와 같은 준비)
	ok("D0 전투 시작(사람 조작·가로)", main.screen == "combat" and view.running and not view.paused and st != null)
	var sig_start := _fight_sig(st)
	_run_frames(view, 12) # 대조군: 멈추지 않았을 때는 실제로 진행한다
	var sig_live := _fight_sig(st)
	ok("D1 대조군: 멈추지 않으면 전투가 진행한다(적도 움직인다)", sig_live != sig_start and st.step_n > 0 and st.status == "running" and (st.enemies as Array).size() > 0, "%s → %s" % [sig_start, sig_live])
	# 눌려 있던 입력을 만든다(가상 스틱 + 회피 버튼 유지)
	var touch = main.touch
	touch.enabled = true
	touch.layout(PLayout.safe_rect(root))
	var zone: Rect2 = touch.zone_rect()
	var stick_pos: Vector2 = zone.position + Vector2(60.0, zone.size.y - 60.0)
	touch.handle_touch(0, stick_pos, true)
	touch.handle_drag(0, stick_pos + Vector2(64.0, 0.0))
	touch.handle_touch(1, touch.button_center("dodge"), true)
	var held_ok: bool = touch.stick_held() and touch.button_held("dodge") and view.router.virtual_held and view.router.virtual_move != Vector2.ZERO
	ok("E0 세로로 바뀌기 직전: 스틱과 회피 버튼을 잡고 있다", held_ok, "스틱=%s 회피=%s 이동=%s" % [str(touch.stick_held()), str(view.router.virtual_held), str(view.router.virtual_move)])
	await _resize(480, 900) # ← 전투 중 세로 전환
	ok("D2 전투 중 세로 → 일시정지(이미 있는 일시정지 경로)", main.orient_paused and view.paused and main.is_portrait())
	ok("D3 안내막이 세로 안내로 덮는다", gate.veil_visible() and gate.message_text().find("가로") >= 0)
	ok("E1 눌려 있던 입력이 모두 해제된다(스틱·회피 유지·대기 누름)",
		not touch.stick_held() and not touch.button_held("dodge") and not view.router.virtual_held
		and view.router.virtual_move == Vector2.ZERO and not view.driver.press_pending and not view.driver.special_pending,
		"스틱=%s 회피유지=%s 이동=%s 대기누름=%s" % [str(touch.stick_held()), str(view.router.virtual_held), str(view.router.virtual_move), str(view.driver.press_pending)])
	var sig_paused := _fight_sig(st)
	var t_paused: float = st.t
	var hp_paused: float = float(st.player.hp)
	var enemies_paused := str(st.enemies)
	_run_frames(view, 40) # 여러 프레임(4초분)을 굴린다
	await _wait(3)        # 화면 프레임도 지나가게 둔다
	ok("D4 세로인 동안 여러 프레임을 굴려도 전투 시간·체력·적 배치가 하나도 바뀌지 않는다",
		_fight_sig(st) == sig_paused and is_equal_approx(st.t, t_paused) and is_equal_approx(float(st.player.hp), hp_paused) and str(st.enemies) == enemies_paused,
		"%s → %s" % [sig_paused, _fight_sig(st)])
	ok("D5 그 사이 전투가 끝나 버린 것도 아니다(멈춰 있을 뿐)", st.status == "running" and view.running and main.screen == "combat")

	# ---------- F. 가로 복귀 → 자동 재개 없음 ----------
	await _resize(960, 640)
	ok("F1 가로로 돌아와도 여전히 멈춰 있다(자동 재개 없음)", view.paused and main.orient_paused and not main.is_portrait())
	ok("F2 이때 '계속' 버튼이 나온다", gate.veil_visible() and gate.resume_visible(), "안내막=%s 계속=%s" % [str(gate.veil_visible()), str(gate.resume_visible())])
	_run_frames(view, 20)
	ok("F3 '계속'을 누르기 전에는 프레임을 굴려도 그대로다", _fight_sig(st) == sig_paused, _fight_sig(st))
	main.set_pause(false) # Esc 재개를 시도해도 세로 정지는 풀리지 않는다
	ok("F4 Esc 재개로는 풀리지 않는다('계속' 전용)", view.paused and main.orient_paused)
	gate.resume_button().pressed.emit()
	await _wait(2)
	ok("F5 '계속'을 누르면 재개되고 안내막이 사라진다", not view.paused and not main.orient_paused and not gate.veil_visible())
	ok("F6 재개 순간 옛 누름이 되살아나지 않는다", not view.driver.press_pending and not view.router.virtual_held)
	_run_frames(view, 10)
	ok("F7 재개 뒤에는 전투가 다시 진행한다", _fight_sig(st) != sig_paused, _fight_sig(st))

	# ---------- G. 전체화면에서 나온 상태 ----------
	main.note_fullscreen_state(true)
	await _wait(1)
	ok("G1 전체화면 중에는 '다시 들어가기' 버튼이 없다", main.fullscreen_active() and not gate.fullscreen_visible())
	main.note_fullscreen_state(false) # 브라우저의 fullscreenchange로 빠져나온 것을 흉내
	await _wait(1)
	ok("G2 전체화면에서 나오면 다시 들어가는 버튼이 나타난다", not main.fullscreen_active() and gate.fullscreen_visible() and gate.fullscreen_button() != null)
	var back_btn: Button = gate.fullscreen_button()
	if back_btn != null:
		back_btn.pressed.emit()
	await _wait(2)
	ok("G3 그 버튼을 눌러도 오류 없이 지나가고 전투가 그대로 이어진다", main.screen == "combat" and view.running and not main.last_fullscreen_result.is_empty(), str(main.last_fullscreen_result))

	# ---------- H. 화면 크기 신호 ----------
	metrics_seen.clear()
	await _resize(480, 900)
	var got_portrait := false
	for m in metrics_seen:
		if bool((m as Dictionary).get("portrait", false)):
			got_portrait = true
	ok("H1 세로로 바뀌면 screen_metrics_changed가 온다", metrics_seen.size() > 0 and got_portrait, "신호 %d개" % metrics_seen.size())
	var last_m: Dictionary = metrics_seen[metrics_seen.size() - 1] if metrics_seen.size() > 0 else {}
	ok("H2 신호에 보이는 영역·안전 영역·세로 여부·비율 묶음·전체화면·터치가 들어 있다",
		last_m.has("visible") and last_m.has("safe") and last_m.has("portrait") and last_m.has("bucket") and last_m.has("fullscreen") and last_m.has("touch"),
		str(last_m))
	ok("H3 main.screen_metrics()도 같은 값을 준다(창구)", String(main.screen_metrics().get("bucket", "")) == String(last_m.get("bucket", "-")))

	# ---------- I. PC 가로 창 회귀 ----------
	await _resize(960, 640)
	main.orient_resume()
	await _wait(2)
	ok("I1 가로 창에서는 안내막도 세로 판정도 없다", not main.is_portrait() and not gate.veil_visible() and not main.orient_paused)
	ok("I2 비율 묶음은 예전과 같다(960×640 = standard)", PLayout.aspect_bucket(root.get_visible_rect().size) == "standard", str(root.get_visible_rect().size))
	main.set_pause(true)
	ok("I3 Esc 일시정지 경로 그대로(정지·일시정지 화면)", view.paused and main.pause_panel.visible)
	main.set_pause(false)
	ok("I4 Esc 재개 경로 그대로", not view.paused and not main.pause_panel.visible)
	main.go_title()
	await _wait(2)
	ok("I5 제목으로 돌아가면 세로 대기 상태도 남지 않는다", main.screen == "title" and not main.orient_paused and not gate.veil_visible())

	main.view.running = false
	main.queue_free()
	await _wait(2)
	PSave.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
