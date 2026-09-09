extends SceneTree
## 손가락 스크롤(PTouchScroll) 시험. 실행:
##   godot --headless --path prophecy_godot -s tests/scroll_tests.gd   (PROPHECY_TOUCH=1 이 있어야 한다)
##
## 무엇을 확인할 수 있고 무엇을 못 하는가 — 먼저 읽어라
## ----------------------------------------------------
## 헤드리스에는 창도 터치 화면도 없다. 그래서 여기서 하는 것은 **모의**다:
## 사람 손가락 대신 `InputEventScreenTouch` / `InputEventScreenDrag` 객체를 만들어
## **사람 입력과 똑같은 함수**(PTouchScroll.handle / step)에 넣는다. 실제 안드로이드에서
## 손가락 감각이 어떤지는 이 시험이 답하지 못한다 — 그건 실기 확인 몫이다.
##
## 대신 이 시험이 실제로 잡는 것: 2026-09-09에 계측으로 확인한 "한 칸씩만 움직인다"의 원인
## (밀어 넣은 취소 사건이 우리 `_input`으로 되돌아와 끌기 상태를 지우던 것)과
## 1px 미만 이동이 잘려 나가던 것. 둘 다 아래 A·B 절이 회귀로 붙잡는다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

# ---------- 도구 ----------
## 밀어 넣은 취소 사건이 정말로 뷰포트에 들어갔는지 옆에서 지켜보는 눈
class CancelSpy extends Node:
	var seen := []
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var t := event as InputEventScreenTouch
			if t.canceled:
				seen.append(t.position)

func _touch(idx: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	return t

func _drag(idx: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	d.relative = rel
	return d

## 시험대: 스크롤 하나 + 긴 목록(버튼 100줄) + 붙여 둔 PTouchScroll
func _rig(rows: int = 100) -> Dictionary:
	var host := Control.new()
	host.size = Vector2(960, 640)
	root.add_child(host)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.position = Vector2.ZERO
	sc.size = Vector2(400, 300)
	host.add_child(sc)
	var box := VBoxContainer.new()
	sc.add_child(box)
	for i in range(rows):
		var b := Button.new()
		b.text = "줄 %d" % i
		b.custom_minimum_size = Vector2(0, 40)
		box.add_child(b)
	var ts := PTouchScroll.attach(host, sc)
	return { "host": host, "scroll": sc, "ts": ts }

func _settle(n: int = 3) -> void:
	for i in range(n):
		await process_frame

## 관성이 멎을 때까지 프레임을 굴리고, 그동안 움직인 거리를 돌려준다
func _coast(ts: PTouchScroll, sc: ScrollContainer, max_frames: int = 600) -> float:
	var start := float(sc.scroll_vertical)
	for i in range(max_frames):
		if ts.velocity() == 0.0:
			break
		ts.step(1.0 / 60.0)
	return absf(float(sc.scroll_vertical) - start)

func _run() -> void:
	if not PLayout.is_touch():
		print("FAIL 준비 — PROPHECY_TOUCH=1 없이 돌렸다. 이 스위트는 터치 경로를 본다")
		print("0/1 PASS")
		quit(1)
		return

	# ---------- A. 되돌아온 취소 사건이 끌기를 죽이지 않는다(진짜 원인의 회귀) ----------
	var r := _rig()
	var sc: ScrollContainer = r.scroll
	var ts: PTouchScroll = r.ts
	await _settle()
	ok("준비 목록이 창보다 길다", ts.max_scroll() > 1000.0, "max=%.0f" % ts.max_scroll())

	var spy := CancelSpy.new()
	root.add_child(spy)
	ts.handle(_touch(0, Vector2(100, 250), true))
	var p := Vector2(100, 250)
	var trace := []
	for i in range(10):
		p += Vector2(0, -20)
		ts.handle(_drag(0, p, Vector2(0, -20)))
		trace.append(sc.scroll_vertical)
	ok("A1 한 번 눌러 열 번 끌면 열 번 다 움직인다(예전엔 한 칸에서 멈췄다)",
		sc.scroll_vertical == 200, "자취=%s (참값 200)" % str(trace))
	ok("A2 끌기로 판정한 순간 버튼에 취소가 실제로 들어갔다", spy.seen.size() == 1, "취소 %d건" % spy.seen.size())
	ok("A3 취소 사건의 자리가 손가락 자리 그대로다(좌표가 다시 변환되지 않는다)",
		spy.seen.size() == 1 and (spy.seen[0] as Vector2).is_equal_approx(Vector2(100, 230)),
		str(spy.seen))
	ok("A4 취소를 보낸 뒤에도 여전히 끌고 있는 중이다", ts.is_dragging())
	ts.handle(_touch(0, p, false))
	ok("A5 손을 떼면 끌기가 끝난다", not ts.is_dragging())

	# ---------- B. 소수점이 버려지지 않는다 ----------
	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 250), true))
	ts.handle(_drag(0, Vector2(100, 230), Vector2(0, -20)))   # 문턱을 넘긴다
	var base := sc.scroll_vertical
	var q := Vector2(100, 230)
	for i in range(10):
		q += Vector2(0, -0.4)
		ts.handle(_drag(0, q, Vector2(0, -0.4)))
	var moved := sc.scroll_vertical - base
	ok("B1 0.4px씩 열 번 끌면 4px 가까이 움직인다", absf(float(moved) - 4.0) <= 1.0, "%dpx 움직였다(참값 4)" % moved)
	var old := 0
	for i in range(10):
		old = int(old) - int(-0.4)
	ok("B2 (참고) 옛 식 int(relative.y)로는 같은 끌기가 0px이었다", old == 0, "옛 식 = %dpx" % old)
	ts.handle(_touch(0, q, false))

	# ---------- C. 12px 문턱: 탭은 살아 있다 ----------
	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	var press := ts.handle(_touch(0, Vector2(100, 250), true))
	ok("C1 누름은 삼키지 않는다(탭이 그대로 버튼에 간다)", not press)
	var small := ts.handle(_drag(0, Vector2(100, 242), Vector2(0, -8)))
	ok("C2 8px만 움직이면 스크롤하지 않는다", not small and sc.scroll_vertical == 0 and not ts.is_dragging(),
		"scroll=%d dragging=%s" % [sc.scroll_vertical, str(ts.is_dragging())])
	var spy2 := CancelSpy.new()
	root.add_child(spy2)
	var big := ts.handle(_drag(0, Vector2(100, 236), Vector2(0, -6)))   # 처음 자리에서 14px
	ok("C3 12px을 넘으면 끌기로 바뀌고 우리가 사건을 삼킨다", big and ts.is_dragging())
	ok("C4 그때 버튼에 취소가 간다", spy2.seen.size() == 1, "취소 %d건" % spy2.seen.size())
	ts.handle(_touch(0, Vector2(100, 236), false))
	spy2.queue_free()

	# ---------- D. 관성 ----------
	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 290), true))
	var fp := Vector2(100, 290)
	for i in range(4):                       # 프레임마다 30px = 1800px/초
		fp += Vector2(0, -30)
		ts.handle(_drag(0, fp, Vector2(0, -30)))
		ts.step(1.0 / 60.0)
	ts.handle(_touch(0, fp, false))
	var v_fast := ts.velocity()
	var slide_fast := _coast(ts, sc)
	ok("D1 빠르게 끌고 떼면 뗀 뒤에도 한참 더 미끄러진다", slide_fast > 100.0,
		"뗄 때 %.0fpx/초 → %.0fpx 더 갔다" % [v_fast, slide_fast])
	ok("D2 그러다 스스로 멎는다", ts.velocity() == 0.0)

	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 290), true))
	var sp := Vector2(100, 290)
	sp += Vector2(0, -14)
	ts.handle(_drag(0, sp, Vector2(0, -14)))   # 문턱만 넘긴다
	ts.step(1.0 / 60.0)
	for i in range(4):                         # 프레임마다 1px = 60px/초
		sp += Vector2(0, -1)
		ts.handle(_drag(0, sp, Vector2(0, -1)))
		ts.step(1.0 / 60.0)
	ts.handle(_touch(0, sp, false))
	var v_slow := ts.velocity()
	var slide_slow := _coast(ts, sc)
	ok("D3 느리게 끌고 떼면 거의 미끄러지지 않는다", slide_slow < 5.0,
		"뗄 때 %.0fpx/초 → %.1fpx" % [v_slow, slide_slow])
	ok("D4 빠른 쪽이 느린 쪽보다 훨씬 많이 미끄러진다", slide_fast > slide_slow * 20.0,
		"%.0f vs %.1f" % [slide_fast, slide_slow])

	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 290), true))
	var tp := Vector2(100, 290)
	for i in range(4):
		tp += Vector2(0, -30)
		ts.handle(_drag(0, tp, Vector2(0, -30)))
		ts.step(1.0 / 60.0)
	ts.handle(_touch(0, tp, false))
	ts.step(1.0 / 60.0)
	ts.step(1.0 / 60.0)
	var mid := sc.scroll_vertical
	ts.handle(_touch(0, Vector2(100, 200), true))   # 미끄러지는 중에 손가락을 댄다
	ts.step(1.0 / 60.0)
	ok("D5 미끄러지는 중에 손을 대면 그 자리에 선다", ts.velocity() == 0.0 and absf(float(sc.scroll_vertical) - float(mid)) <= 1.0,
		"%d → %d" % [mid, sc.scroll_vertical])
	ts.handle(_touch(0, Vector2(100, 200), false))

	# ---------- E. 경계 ----------
	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 100), true))
	var up := Vector2(100, 100)
	for i in range(20):
		up += Vector2(0, 40)
		ts.handle(_drag(0, up, Vector2(0, 40)))
	ok("E1 맨 위에서 더 끌어 올려도 0 아래로 내려가지 않는다", sc.scroll_vertical == 0 and ts.position_f() == 0.0,
		"scroll=%d pos=%.1f" % [sc.scroll_vertical, ts.position_f()])
	ts.handle(_touch(0, up, false))
	var mx := int(ts.max_scroll())
	ts.stop()
	sc.scroll_vertical = mx
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 250), true))
	var dn := Vector2(100, 250)
	for i in range(20):
		dn += Vector2(0, -40)
		ts.handle(_drag(0, dn, Vector2(0, -40)))
	ok("E2 맨 아래에서 더 끌어 내려도 최대값을 넘지 않는다", sc.scroll_vertical == mx and int(ts.position_f()) == mx,
		"scroll=%d max=%d" % [sc.scroll_vertical, mx])
	ts.handle(_touch(0, dn, false))
	ok("E3 경계에 막힌 끌기는 관성도 남기지 않는다", _coast(ts, sc) < 1.0)

	# ---------- F. 방향 바꾸기 ----------
	ts.stop()
	sc.scroll_vertical = 400
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 250), true))
	var cp := Vector2(100, 250)
	for i in range(5):
		cp += Vector2(0, -20)
		ts.handle(_drag(0, cp, Vector2(0, -20)))
	var after_down := sc.scroll_vertical
	for i in range(5):
		cp += Vector2(0, 20)
		ts.handle(_drag(0, cp, Vector2(0, 20)))     # 손을 떼지 않고 반대로
	ok("F1 손을 떼지 않고 방향을 바꾸면 그대로 따라온다",
		after_down == 500 and sc.scroll_vertical == 400, "400 → %d → %d" % [after_down, sc.scroll_vertical])
	ts.handle(_touch(0, cp, false))

	# ---------- G. 여러 손가락 ----------
	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 250), true))
	ts.handle(_drag(0, Vector2(100, 230), Vector2(0, -20)))
	ts.handle(_touch(1, Vector2(300, 100), true))     # 두 번째 손가락이 끼어든다
	ok("G1 두 번째 손가락은 스크롤을 가져가지 못한다", ts.is_dragging())
	var ignored := ts.handle(_drag(1, Vector2(300, 40), Vector2(0, -60)))
	ok("G2 두 번째 손가락의 끌기는 무시한다", not ignored and sc.scroll_vertical == 20, "scroll=%d" % sc.scroll_vertical)
	ts.handle(_drag(0, Vector2(100, 210), Vector2(0, -20)))
	ok("G3 첫 손가락은 계속 끈다", sc.scroll_vertical == 40, "scroll=%d" % sc.scroll_vertical)
	ts.handle(_touch(1, Vector2(300, 40), false))     # 두 번째 손가락을 떼도
	ts.handle(_drag(0, Vector2(100, 190), Vector2(0, -20)))
	ok("G4 두 번째 손가락을 떼도 첫 손가락의 끌기는 그대로다", sc.scroll_vertical == 60, "scroll=%d" % sc.scroll_vertical)
	ts.handle(_touch(0, Vector2(100, 190), false))

	# ---------- H. 손을 뗀 뒤에 눌림이 남지 않는다 ----------
	ok("H1 뗀 뒤에는 끌기 상태가 아니다", not ts.is_dragging())
	var stale := ts.handle(_drag(0, Vector2(100, 100), Vector2(0, -90)))
	ok("H2 뗀 뒤 들어온 끌기는 아무 것도 하지 않는다", not stale and sc.scroll_vertical == 60, "scroll=%d" % sc.scroll_vertical)
	ts.handle(_touch(0, Vector2(100, 250), true))
	ts.handle(_drag(0, Vector2(100, 230), Vector2(0, -20)))
	ok("H3 다시 누르면 다시 끌린다", sc.scroll_vertical == 80, "scroll=%d" % sc.scroll_vertical)
	ts.handle(_touch(0, Vector2(100, 230), false))

	# ---------- I. 화면이 바뀌면 관성이 멈춘다 ----------
	ts.stop()
	sc.scroll_vertical = 0
	ts.sync()
	ts.handle(_touch(0, Vector2(100, 290), true))
	var ip := Vector2(100, 290)
	for i in range(4):
		ip += Vector2(0, -30)
		ts.handle(_drag(0, ip, Vector2(0, -30)))
		ts.step(1.0 / 60.0)
	ts.handle(_touch(0, ip, false))
	ok("I1 뗀 직후에는 관성이 있다", ts.velocity() != 0.0, "%.0fpx/초" % ts.velocity())
	var host: Control = r.host
	host.visible = false                              # 화면이 바뀌었다
	ts.step(1.0 / 60.0)
	ok("I2 화면이 보이지 않게 되면 관성이 사라진다", ts.velocity() == 0.0 and not ts.is_dragging())
	var frozen := sc.scroll_vertical
	for i in range(10):
		ts.step(1.0 / 60.0)
	ok("I3 그 뒤로는 저절로 움직이지 않는다", sc.scroll_vertical == frozen, "%d → %d" % [frozen, sc.scroll_vertical])
	host.visible = true

	# ---------- J. 터치가 아니면(PC) 이 경로가 아예 돌지 않는다 ----------
	ts.stop()
	sc.scroll_vertical = 100
	ts.sync()
	OS.set_environment("PROPHECY_TOUCH", "")
	ok("J0 준비 이 환경에서 PLayout.is_touch()가 꺼진다", not PLayout.is_touch())
	var pc_press := ts.handle(_touch(0, Vector2(100, 250), true))
	var pc_drag := ts.handle(_drag(0, Vector2(100, 150), Vector2(0, -100)))
	ok("J1 PC에서는 손가락 사건을 하나도 삼키지 않는다", not pc_press and not pc_drag)
	ok("J2 PC에서는 스크롤 값을 건드리지 않는다(휠은 ScrollContainer가 그대로 맡는다)",
		sc.scroll_vertical == 100, "scroll=%d" % sc.scroll_vertical)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	ok("J3 마우스 휠 사건은 어느 쪽에서도 삼키지 않는다", not ts.handle(wheel))
	OS.set_environment("PROPHECY_TOUCH", "1")
	ok("J4 준비 터치를 다시 켠다", PLayout.is_touch())
	ok("J5 터치에서도 마우스 휠은 우리가 건드리지 않는다", not ts.handle(wheel))
	ts.handle(_touch(0, Vector2(100, 250), true))
	ok("J6 터치를 다시 켜면 손가락 끌기가 다시 돈다",
		ts.handle(_drag(0, Vector2(100, 230), Vector2(0, -20))) and sc.scroll_vertical == 120,
		"scroll=%d" % sc.scroll_vertical)
	ts.handle(_touch(0, Vector2(100, 230), false))
	ts.stop()
	spy.queue_free()
	r.host.queue_free()
	await _settle()

	# ---------- K. 진짜 화면(PScreen)에 붙어 있다 · 보던 자리 유지 ----------
	var s := PScreen.new()
	s.visible = true
	root.add_child(s)
	s.setup(null)
	for i in range(80):
		s.body.add_child(PUi.button("항목 %d" % i, Callable(), true, 14))
	await _settle(4)
	ok("K1 화면 뼈대가 손가락 스크롤을 붙여 둔다(화면 14개 전부 같은 길)",
		s.touch_scroll != null and s.touch_scroll.get_parent() == s)
	ok("K2 그 화면에서도 목록이 창보다 길다", s.touch_scroll.max_scroll() > 100.0, "max=%.0f" % s.touch_scroll.max_scroll())
	var srect := s.scroll.get_global_rect()
	var sp0 := srect.position + srect.size * 0.5
	s.touch_scroll.handle(_touch(0, sp0, true))
	for i in range(10):
		sp0 += Vector2(0, -20)
		s.touch_scroll.handle(_drag(0, sp0, Vector2(0, -20)))
	ok("K3 실제 화면에서도 한 번 눌러 열 번 끌면 다 움직인다", s.scroll.scroll_vertical == 200,
		"scroll=%d" % s.scroll.scroll_vertical)
	s.touch_scroll.handle(_touch(0, sp0, false))
	s.touch_scroll.stop()

	s.scroll.scroll_vertical = 200
	s.touch_scroll.sync()
	s.clear_all()                                  # 목록을 다시 그린다(= 팔기 눌렀을 때 하는 일)
	for i in range(80):
		s.body.add_child(PUi.button("항목 %d" % i, Callable(), true, 14))
	await _settle(6)
	ok("K4 다시 그려도 보던 자리가 그대로다('팔기'를 눌러도 맨 위로 안 튄다)",
		s.scroll.scroll_vertical == 200, "scroll=%d" % s.scroll.scroll_vertical)
	ok("K5 되살린 자리를 손가락 스크롤도 같은 값으로 본다", s.touch_scroll.position_f() == 200.0,
		"pos=%.1f" % s.touch_scroll.position_f())

	s.touch_scroll._velocity = 900.0               # 미끄러지는 중에
	s.on_enter()                                   # 다른 화면에서 들어온다
	ok("K6 화면에 새로 들어오면 맨 위에서 시작하고 관성이 남지 않는다",
		s.scroll.scroll_vertical == 0 and s.touch_scroll.velocity() == 0.0,
		"scroll=%d v=%.0f" % [s.scroll.scroll_vertical, s.touch_scroll.velocity()])
	ok("K7 확인 창이 열려 있으면 뒤쪽 목록이 새로 끌리지 않는다", _blocked_by_confirm(s))
	s.queue_free()
	await _settle()

	# ---------- L. 실제 브라우저(폰 가로)에서 잡은 것: 관성이 사실상 없던 이유 ----------
	## 2026-09-09, 내보낸 웹 빌드를 진짜 크롬에 띄우고 CDP로 진짜 터치를 보내 계측했다.
	## 빠른 쓸기 뒤 목록이 **한 px도 더 가지 않았다**(1.5초 동안 자리 155.6 그대로).
	## 원인은 프레임마다 속도를 재고 지수 평활(0.65)을 건 것이었다: 손가락 사건이 없는 프레임마다
	## 속도가 0.35배로 줄어(520 → 182 → 64 → 22px/초) 뗄 때 남는 값이 없었다.
	## 브라우저는 화면 갱신과 터치 표본의 주기가 달라 그런 프레임이 늘 섞인다.
	## 아래 세 시험이 그 상황을 그대로 재현한다(위 D절은 사건이 프레임마다 있는 경우만 봤다).
	var r2 := _rig()
	var sc2: ScrollContainer = r2.scroll
	var ts2: PTouchScroll = r2.ts
	await _settle()
	ok("L0 붙여 둔 장치가 스스로 프레임을 받는다(_process — 시험이 step을 대신 부르지 않아도 돈다)",
		ts2.is_processing())

	ts2.handle(_touch(0, Vector2(100, 290), true))
	var lp := Vector2(100, 290)
	for i in range(5):
		lp += Vector2(0, -40)
		ts2.handle(_drag(0, lp, Vector2(0, -40)))
		for j in range(3):                     # 손가락 사건이 없는 프레임 셋(브라우저에서 실제로 이렇게 온다)
			ts2.step(1.0 / 60.0)
	ts2.handle(_touch(0, lp, false))
	var v_gap := ts2.velocity()
	var slide_gap := _coast(ts2, sc2)
	ok("L1 프레임 사이에 손가락 사건이 없어도 관성이 살아 있다", slide_gap > 100.0,
		"뗄 때 %.0fpx/초 → %.0fpx 더 갔다" % [v_gap, slide_gap])

	ts2.stop()
	sc2.scroll_vertical = 0
	ts2.sync()
	ts2.handle(_touch(0, Vector2(100, 290), true))
	var hp := Vector2(100, 290)
	for i in range(4):
		hp += Vector2(0, -40)
		ts2.handle(_drag(0, hp, Vector2(0, -40)))
		ts2.step(1.0 / 60.0)
	for i in range(15):                        # 손가락을 붙인 채 0.25초 멈춰 있다가 뗀다
		ts2.step(1.0 / 60.0)
	ts2.handle(_touch(0, hp, false))
	ok("L2 떼기 전에 손가락을 멈추면 던지지 않는다(붙잡아 세운 뒤 떼는 동작)",
		ts2.velocity() == 0.0 and _coast(ts2, sc2) < 2.0, "%.0fpx/초" % ts2.velocity())

	ts2.stop()
	sc2.scroll_vertical = 0
	ts2.sync()
	ts2.step(1.0 / 60.0)
	ts2.handle(_touch(0, Vector2(100, 290), true))
	var bp := Vector2(100, 290)
	for i in range(5):
		bp += Vector2(0, -20)
		ts2.handle(_drag(0, bp, Vector2(0, -20)))   # 프레임을 굴리지 않는다 = 한 프레임에 다 들어온 경우
	ts2.handle(_touch(0, bp, false))
	var v_burst := ts2.velocity()
	ok("L3 사건이 한 프레임에 몰려도 던진다(시간 폭 0으로 나누지 않는다)",
		_coast(ts2, sc2) > 100.0, "뗄 때 %.0fpx/초" % v_burst)
	ts2.stop()
	r2.host.queue_free()
	await _settle()

	var pass_n := 0
	for res in results:
		if res[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

## 확인 창을 열어 두면 새 끌기가 시작되지 않는가
func _blocked_by_confirm(s: PScreen) -> bool:
	var rect := s.scroll.get_global_rect()
	var pos := rect.position + rect.size * 0.5
	s.open_confirm("시험", Callable(), [])
	var before := s.scroll.scroll_vertical
	s.touch_scroll.handle(_touch(0, pos, true))
	s.touch_scroll.handle(_drag(0, pos + Vector2(0, -40), Vector2(0, -40)))
	var held := s.scroll.scroll_vertical == before and not s.touch_scroll.is_dragging()
	s.close_confirm()
	s.touch_scroll.stop()
	return held
