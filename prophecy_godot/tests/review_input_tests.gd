extends SceneTree
## **자체 교차 검수 — UI 버튼을 실제 입력 경로로 확인한다**(2026-09-09). 규칙·자료는 고치지 않는다.
## 실행: godot --headless --path prophecy_godot -s tests/review_input_tests.gd
##      (user:// 저장을 쓰므로 APPDATA를 격리한 환경에서 돌린다)
##
## 이 시험이 무엇을 할 수 있고 무엇을 못 하는가 — **먼저 읽어라**
## ------------------------------------------------------------
## 헤드리스(`DisplayServer=headless`)에는 창이 없다(`window_get_size() == (0,0)`).
## 그래서 `Viewport.push_input`으로 넣은 **마우스 사건은 GUI로 전달되지 않는다**(실측: 버튼 한가운데를
## 눌러도 `pressed`가 0회). 반면 **키보드 사건은 전달된다**(실측: Enter로 화면이 base → combat으로 바뀐다).
##
## 그래서 세 층으로 나눠 확인한다. 각 단언 이름에 어느 층인지 적는다.
##   [실키입력] 진짜 InputEventKey를 뷰포트에 넣어 확인 — 사람 입력과 같은 경로
##   [클릭가능] 버튼이 실제로 누를 수 있는 상태인가(보임·크기>0·뷰포트 안·비활성 아님·위를 덮은 층 없음)
##   [신호경로] 마우스를 못 넣으므로 `pressed` 신호로 동작만 확인 — **사람 입력 검증이 아니다**
##
## 기존 UI 스위트는 세 번째 층만 쓴다. 두 번째 층(버튼이 정말 눌릴 수 있는 자리인가)은 어디에도 없었다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

# ---------- 도우미 ----------
func find_btn(node: Node, part: String, need_enabled: bool = true) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and String((node as Button).text).find(part) >= 0:
		if not need_enabled or not (node as Button).disabled:
			return node as Button
	for ch in node.get_children():
		var f := find_btn(ch, part, need_enabled)
		if f != null:
			return f
	return null

## 이 버튼 위를 덮고 있는(입력을 먹는) 보이는 층이 있는가.
## 버튼을 완전히 덮으면서 MOUSE_FILTER_STOP인 Control을 찾는다
func covered_by(rootn: Node, b: Button) -> String:
	var r := b.get_global_rect()
	var found := ""
	var walk := func(n: Node, self_ref: Callable) -> void:
		if n is Control:
			var c := n as Control
			if c != b and c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP \
					and not b.is_ancestor_of(c) and not c.is_ancestor_of(b) \
					and c.get_global_rect().encloses(r) and c.get_global_rect().get_area() > r.get_area():
				found = String(c.get_path())
		for ch in n.get_children():
			self_ref.call(ch, self_ref)
	walk.call(rootn, walk)
	return found

## 이 버튼이 스크롤 영역 안에 있는가(화면 밖 좌표여도 스크롤로 도달할 수 있다)
func in_scroll(b: Node) -> bool:
	var n: Node = b.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false

## 버튼이 실제로 누를 수 있는 상태인가
func clickable(rootn: Node, b: Button) -> Dictionary:
	var r := b.get_global_rect()
	var vp := root.get_visible_rect()
	var cover := covered_by(rootn, b)
	var scroll := in_scroll(b)
	var reachable: bool = vp.intersects(r) or scroll
	return {
		"ok": b.is_visible_in_tree() and r.size.x > 0.0 and r.size.y > 0.0 and reachable
			and b.mouse_filter != Control.MOUSE_FILTER_IGNORE and not b.disabled and cover == "",
		"why": "보임=%s 크기=%s 뷰포트안=%s 스크롤영역=%s filter=%d 비활성=%s 덮임=%s"
			% [str(b.is_visible_in_tree()), str(r.size), str(vp.intersects(r)), str(scroll), int(b.mouse_filter), str(b.disabled), ("없음" if cover == "" else cover)] }

## 진짜 키 사건을 뷰포트에 넣는다
func key(kc: int) -> void:
	for st in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.physical_keycode = kc
		ev.pressed = st
		root.push_input(ev)

func check(rootn: Node, label: String, part: String) -> Button:
	var b := find_btn(rootn, part)
	if b == null:
		var dis := find_btn(rootn, part, false)
		var why := "활성 버튼을 못 찾았다(글자 '%s')" % part
		if dis != null:
			why = "비활성 버튼만 있다: \"%s\"" % String(dis.text)
		ok("[클릭가능] '%s' 버튼이 지금 화면에 눌릴 수 있는 상태로 있다" % label, false, why)
		return null
	var c := clickable(rootn, b)
	ok("[클릭가능] '%s' 버튼이 지금 화면에 눌릴 수 있는 상태로 있다" % label, bool(c.ok), String(c.why))
	return b

func _run() -> void:
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.size = Vector2i(960, 1024) # 헤드리스에는 창이 없어 뷰포트를 직접 세운다(레이아웃을 실제 크기로 잰다)
	root.add_child(main)
	await process_frame

	# ---------- 0. 이 시험의 한계를 먼저 기록한다 ----------
	ok("[한계] 헤드리스에는 창이 없어 마우스 사건을 GUI에 넣을 수 없다(키보드는 된다)",
		DisplayServer.get_name() == "headless",
		"DisplayServer=%s · window_size=%s → 아래 [신호경로] 항목은 사람 마우스 입력 검증이 아니다"
			% [DisplayServer.get_name(), str(DisplayServer.window_get_size())])

	main.start_run("sword")
	await process_frame
	await process_frame

	# ---------- 1. 출격: 실제 키 입력으로 ----------
	var b_sortie := check(main, "출격", "출격 (")
	var h0: int = int(main.run.hours)
	var scr0 := String(main.screen)
	key(KEY_ENTER)
	await process_frame
	await process_frame
	ok("[실키입력] 거점에서 Enter를 실제 키 사건으로 넣으면 출격이 시작되고 시간이 준다",
		String(main.screen) == "combat" and int(main.run.hours) < h0,
		"화면 %s → %s · 시간 %d → %d" % [scr0, String(main.screen), h0, int(main.run.hours)])

	# 전투를 승리로 끝낸다(상태 주입 — 사람·봇 승리 주장이 아니다)
	if String(main.screen) == "combat":
		main.view.running = false
		main.view.st.status = "won"
		main.view.st.player.hp = 70.0
		main._on_finished(main.view.st.summary())
		await process_frame
		await process_frame

	# ---------- 2. 계속: 보상 화면에서 실제 키 입력으로 ----------
	var b_next := check(main, "계속", "계속")
	var scr1 := String(main.screen)
	var guard := 0
	while String(main.screen) != "base" and guard < 12:
		var before := String(main.screen)
		key(KEY_ENTER)
		await process_frame
		await process_frame
		if String(main.screen) == before:
			break
		guard += 1
	ok("[실키입력] 보상·정산 화면에서 Enter만으로 거점까지 실제로 돌아온다",
		String(main.screen) == "base", "화면 %s → %s (Enter %d회)" % [scr1, String(main.screen), guard])

	# ---------- 3. 일반 탐험 ----------
	# 반복 탐험 카드는 '그 장소의 출격을 한 번 마쳐야' 열린다. Enter 기본 경로는 사건 화면에서
	# 추가 전투로 갈라지므로, 여기서는 귀환을 명시적으로 마친 뒤 버튼 상태를 본다
	if main.run.get("pendingSortie", null) != null or main.get("sortie") != null:
		main.return_home()
		await process_frame
	main.go_base()
	await process_frame
	await process_frame
	var b_again := check(main, "일반 탐험", "일반 탐험")
	if b_again != null:
		var h1: int = int(main.run.hours)
		b_again.pressed.emit()
		await process_frame
		await process_frame
		ok("[신호경로] '일반 탐험'을 누르면 전투가 시작되고 시간이 준다",
			String(main.screen) == "combat" and int(main.run.hours) < h1,
			"화면=%s · 시간 %d→%d" % [String(main.screen), h1, int(main.run.hours)])
		if String(main.screen) == "combat":
			main.view.running = false
			main.view.st.status = "won"
			main._on_finished(main.view.st.summary())
			await process_frame
			var g2 := 0
			while String(main.screen) != "base" and g2 < 12:
				var before2 := String(main.screen)
				key(KEY_ENTER)
				await process_frame
				await process_frame
				if String(main.screen) == before2:
					break
				g2 += 1

	# ---------- 4. 휴식(확인 창) ----------
	main.run.hp = 40.0
	main.go_base()
	await process_frame
	await process_frame
	var b_rest := check(main, "휴식", "휴식")
	if b_rest != null:
		b_rest.pressed.emit()
		await process_frame
		await process_frame
		var b_yes := find_btn(main, "휴식한다")
		ok("[신호경로] '휴식'을 누르면 **확인 창**이 먼저 뜬다(바로 회복되지 않는다)",
			b_yes != null and is_equal_approx(float(main.run.hp), 40.0),
			"확인 버튼=%s · 체력 %.1f" % [str(b_yes != null), float(main.run.hp)])
		if b_yes != null:
			var cy := clickable(main, b_yes)
			ok("[클릭가능] 확인 창의 '휴식한다'가 눌릴 수 있는 상태다", bool(cy.ok), String(cy.why))
			b_yes.pressed.emit()
			await process_frame
			await process_frame
			ok("[신호경로] 확인해야 실제로 회복된다", float(main.run.hp) > 40.0,
				"체력 40.0 → %.1f" % float(main.run.hp))

	# ---------- 5. 장착 ----------
	main.run.gold = 9999
	main.show("shop")
	await process_frame
	await process_frame
	var b_buy := check(main, "구매", "구매 (")
	if b_buy != null:
		b_buy.pressed.emit()
		await process_frame
		await process_frame
		var b_eq := find_btn(main, "지금 장착")
		ok("[신호경로] '구매' 뒤 확인 창에 '지금 장착'이 나온다", b_eq != null)
		if b_eq != null:
			var ce := clickable(main, b_eq)
			ok("[클릭가능] '지금 장착'이 눌릴 수 있는 상태다", bool(ce.ok), String(ce.why))
			var eq0 := JSON.stringify(main.run.equipment)
			var bag0 := JSON.stringify(main.run.bag)
			b_eq.pressed.emit()
			await process_frame
			await process_frame
			ok("[신호경로] '지금 장착'을 누르면 장착 또는 가방 내용이 실제로 바뀐다",
				JSON.stringify(main.run.equipment) != eq0 or JSON.stringify(main.run.bag) != bag0,
				"장착 %s → %s" % [eq0, JSON.stringify(main.run.equipment)])

	# ---------- 6. 판매 ----------
	main.show("shop")
	await process_frame
	await process_frame
	var b_sell := check(main, "판매", "판매 +")
	if b_sell != null:
		var g0: int = int(main.run.gold)
		b_sell.pressed.emit()
		await process_frame
		await process_frame
		var b_ok := find_btn(main, "판매한다")
		ok("[신호경로] '판매'를 누르면 **확인 창**이 먼저 뜬다(바로 팔리지 않는다)",
			b_ok != null and int(main.run.gold) == g0,
			"확인 버튼=%s · 금화 %d" % [str(b_ok != null), int(main.run.gold)])
		if b_ok != null:
			b_ok.pressed.emit()
			await process_frame
			await process_frame
			ok("[신호경로] 확인해야 실제로 팔린다", int(main.run.gold) > g0,
				"금화 %d → %d" % [g0, int(main.run.gold)])

	# ---------- 7. 화면에 적힌 판매가가 규칙과 같은가 ----------
	var SH: Dictionary = PCatalog.shop()
	var shown_w := int((SH.get("sellPrice", {}) as Dictionary).get("weapon", -1))
	var buy_w := int((SH.get("price", {}) as Dictionary).get("weapon", 0))
	var real_w := int(floor(float(buy_w) * 0.5))
	ok("[명세] 상점 상세의 '되팔 때' 안내가 실제 판매가(구매액의 절반)와 같다",
		shown_w == real_w, "화면 안내 %d금 · 규칙상 %d금(구매 %d금의 절반) — shop.gd:236이 옛 고정표를 읽는다"
			% [shown_w, real_w, buy_w])

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
