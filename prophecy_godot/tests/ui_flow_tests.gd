extends SceneTree
## 화면 계층 흐름 테스트(headless, 실제 main.tscn 인스턴스): 저장 체크포인트·HUD 표시가 규칙 계약과 맞는지.
## 실행: APPDATA를 별도 폴더로 두고 godot --headless --path prophecy_godot -s tests/ui_flow_tests.gd (user:// 저장을 쓰므로 실제 사용자 프로필에서 돌리지 않는다)
## 준비 단계에서 전투 결과를 상태 주입(status="won")으로 만든 곳은 그렇게 표기한다 — 사람/봇 승리 주장이 아니다. 키보드·마우스 입력 합성 없음.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

func _win(main: Node) -> void: # 상태 주입: 진행 중 전투를 승리로 끝낸다
	main.view.running = false
	main.view.st.status = "won"
	main.view.st.player.hp = 70.0
	# 결투가 예정된 편성이면 규칙이 "특수 정예전 미완료 상태의 승리 정산"으로 막는다(정상 동작).
	# 여기서는 승리 **뒤의 흐름**만 보므로 결투를 끝난 것으로 표시해 규칙과 앞뒤를 맞춘다.
	# 이걸 빼면 로그에 진짜 오류가 아닌 ERROR가 남아 실제 결함을 가린다.
	main.view.st.mark_duel_done_for_test()
	main._on_finished(main.view.st.summary())

# ---------- 이동 불능 회귀(2026-09-08 "9일차에 움직이지 않아 죽었다" 보고) ----------
## 실제 원인: 테마 경기장의 시작 위치가 바위 중심과 같아(예: abyss_center, 9일차 t3a_center)
## 플레이어가 바위 표면에 붙은 채 시작하고, 접촉 탈출 규칙이 없으면 어느 방향으로도 못 움직였다.
## 아래 검사는 (1) 모든 테마 경기장에서 8방향 걷기가 되는지, (2) 실제 화면 경로(CombatView._process →
## PInputRouter.poll → PStepDriver.frame)로 걸어지는지, (3) 3택·일시정지·설정·빌드 상세·포커스·터치를
## 거친 뒤에도 이동이 살아 있는지를 본다.

## **실제 UI 경로 하나로** 임무 완료 → 거점 복귀 → 일반 탐험 출발까지 확인한다.
## 카드에 done을 찍거나 규칙 함수를 직접 부르지 않는다 — 화면의 버튼을 누르고 전투를 실제로 이긴다.
##
## 일반 탐험은 **오늘 카드를 다 끝낸 뒤** 남는 시간에 열린다(PSortie.repeat_cards).
## 그래서 한 판만 이기고 확인하면 "버튼이 없다"가 나오는데, 그건 결함이 아니라 아직 카드가 남은 것이다.
## 여기서는 오늘 카드를 전부 실제로 이겨서 끝낸다.

## 출격 버튼 하나를 눌러 실제로 이기고 거점까지 돌아온다. 왜 멈췄는지 알 수 있게 사유 문자열을 돌려준다
func _one_sortie_to_base(main: Node) -> String:
	var bs: Node = main.screens["base"]
	var go: Button = _vis_enabled_button(bs, "출격 (")
	if go == null:
		return "출격 버튼 없음"
	go.pressed.emit()
	await process_frame
	if main.screen != "combat":
		return "출격을 눌렀는데 전투로 안 감(screen=%s)" % main.screen
	main.view.bot = main.make_bot("skilled") # 이 검사의 목적은 승패가 아니라 '승리 뒤 흐름'이다
	var frames := 0
	while main.view.st != null and String(main.view.st.status) == "running" and frames < 60 * 300:
		main.view._process(1.0 / 60.0)
		frames += 1
	if main.view.st == null:
		return "전투 상태가 사라짐"
	if String(main.view.st.status) != "won":
		return "봇이 못 이김(status=%s %.0f초)" % [String(main.view.st.status), float(frames) / 60.0]
	# 승리 뒤 정산·보상 화면 전환에는 몇 프레임이 더 필요하다
	var wait := 0
	while main.screen == "combat" and wait < 60 * 20:
		main.view._process(1.0 / 60.0)
		if wait % 6 == 0:
			await process_frame
		wait += 1
	await process_frame
	for i in 12:
		if main.screen == "base":
			return ""
		if main.choice != null and main.choice.visible: # 3택은 첫 후보를 고른다(사람과 같은 경로)
			var pick: Button = _vis_enabled_button(main.choice, "")
			if pick != null:
				pick.pressed.emit()
			await process_frame
			continue
		var scr: Node = main.screens.get(main.screen, null)
		if scr == null:
			return "알 수 없는 화면 %s" % main.screen
		var nxt: Button = _vis_enabled_button(scr, "귀환")
		if nxt == null:
			nxt = _vis_enabled_button(scr, "계속")
		if nxt == null:
			nxt = _vis_enabled_button(scr, "")
		if nxt == null:
			return "%s 화면에서 누를 버튼이 없음" % main.screen
		nxt.pressed.emit()
		await process_frame
	return "귀환까지 못 감(screen=%s)" % main.screen

func _repeat_after_real_sortie(main: Node) -> void:
	main.new_run_opts = { "seed": 4021 } # **시드를 고정한다.** 안 하면 시간 기반 시드라 검사가 흔들린다
	main.start_run("sword")
	await process_frame
	main.sortie = {}
	main.show("base")
	await process_frame
	# 일반 탐험은 "출격을 한 번 마치면" 열린다(TOWN_UI.md·PSortie.repeat_cards: 완료한 카드마다 1장).
	# 그러니 오늘 카드를 다 이길 필요는 없다 — **한 판을 실제로 이기고 거점까지 돌아오면 된다.**
	var why: String = await _one_sortie_to_base(main)
	var done_n := 0
	for c in PSortie.cards_for(main.run):
		if bool(c.get("done", false)):
			done_n += 1
	ok("실제 경로 ①~④ 출격 → 전투 승리 → 보상 '계속' → 거점 복귀가 실제 버튼으로 이어진다",
		why == "" and main.screen == "base",
		"화면 %s%s" % [main.screen, (" · 멈춘 이유: " + why) if why != "" else ""])
	ok("실제 경로 ④-2 이긴 출격의 카드가 실제로 완료로 남는다(목표가 'clear'인 평범한 출격도)",
		done_n >= 1, "완료 표시된 카드 %d장" % done_n)
	if why != "" or main.screen != "base":
		ok("실제 경로 ⑤ 남은 시간으로 일반 탐험을 실제로 출발한다", false, "앞 단계에서 멈춤: " + why)
		return
	var bs2: Node = main.screens["base"]
	var rname0 := PPacing.repeat_label()
	var rep0: Button = _vis_enabled_button(bs2, rname0)
	var left: int = int(main.run.hours)
	ok("실제 경로 ⑤ 출격을 한 판 마치고 시간이 남으면 '%s' 버튼이 실제로 눌린다" % rname0,
		rep0 != null and left > 0 and done_n >= 1,
		"남은 시간 %d · 완료 카드 %d · 버튼 %s" % [left, done_n, str(rep0 != null)])
	if rep0 == null:
		return
	var h1: int = int(main.run.hours)
	var gold1: int = int(main.run.gold)
	rep0.pressed.emit()
	await process_frame
	ok("실제 경로 ⑥ '%s'이 전투를 시작하고 시간 1칸을 쓴다" % rname0,
		main.screen == "combat" and bool(main.sortie.get("repeat", false)) and int(main.run.hours) == h1 - 1,
		"screen=%s hours=%d→%d repeat=%s" % [main.screen, h1, int(main.run.hours), str(main.sortie.get("repeat", false))])
	ok("실제 경로 ⑦ 일반 탐험에는 사건이 붙지 않는다(이용권·사건 재지급 금지)",
		main.sortie.get("event", null) == null, "event=%s gold=%d" % [str(main.sortie.get("event", null)), gold1])
	if main.view != null:
		main.view.running = false

## 같은 상태를 매번 새로 만들어 8방향으로 0.5초씩 걷고 최소 이동량(px)을 돌려준다
func _walk_min(st: CombatState) -> float:
	var worst := 99999.0
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
		var s := CombatState.new(st.opts)
		s.intro = 0.0        # 상태 주입: 도입 연출을 건너뛴다(연출만, 규칙 아님)
		s.spawn_hold = true  # 적 등장 정지: 이동만 본다
		var x0: float = s.player.x
		var y0: float = s.player.y
		for i in 60:
			s.step({ "mx": float(d[0]), "my": float(d[1]) }, 1.0 / 120.0)
		worst = minf(worst, PGeom.dist(x0, y0, s.player.x, s.player.y))
	return worst

## 실제 화면 경로로 걷기: 가상 스틱에 방향을 넣고 CombatView._process를 돌린다(키보드와 같은 poll 경로)
func _view_walk(main: Node, dir: Vector2, frames: int = 30) -> float:
	var st: CombatState = main.view.st
	st.intro = 0.0
	st.spawn_hold = true
	main.view.router.set_virtual_move(dir)
	var x0: float = st.player.x
	var y0: float = st.player.y
	for i in frames:
		main.view._process(1.0 / 60.0)
	main.view.router.set_virtual_move(Vector2.ZERO)
	return PGeom.dist(x0, y0, st.player.x, st.player.y)

# ---------- 거점 UI 재구성(2026-09-09): 문구를 세지 않고 실제 버튼을 눌러 확인한다 ----------
## 여기서 확인하는 것
##  ① 시간이 남으면 출격·일반 탐험 버튼이 실제로 눌리고 시간이 준다(남은 시간 1~5칸 전부)
##  ② 일반 탐험은 완료 카드 안의 보충 설명이 아니라 자기 영역에 있다
##  ③ 시간이 없으면 '다음 날로'가 한 곳에만 크게 있고, 상점은 실제로 열리며 휴식 버튼은 숨지 않는다(휴식권이 있으면 눌린다)
##  ④ 휴식·판매·구매는 확인 창을 거치고, 취소하면 체력·시간·금화·가방이 그대로다
##  ⑤ 구매 확인 창에서 '지금 장착'과 '가방에 넣기'가 모두 동작한다
##  ⑥ 상세 설명은 버튼을 눌러야 열린다(마우스를 올리기만 해서는 열리지 않는다)
##  ⑦ 판매 확정은 중복 클릭해도 한 번만 반영된다
func _town_ui_tests(main: Node) -> void:
	PSave.clear()
	main.new_run_opts = {}
	main.start_run("sword")
	var r: Dictionary = main.run
	r.gold = 2000
	main.sortie = {}
	main.show("base")
	await process_frame
	var bs: Node = main.screens["base"]
	# ① 출격 버튼이 실제로 눌린다
	var go := _vis_enabled_button(bs, "출격 (")
	var h0: int = int(r.hours)
	var went := false
	if go != null:
		go.pressed.emit()
		await process_frame
		went = main.screen == "combat" and int(r.hours) < h0
		main.view.running = false
	ok("거점: 시간이 남으면 '출격' 버튼이 실제로 눌리고 전투가 시작된다", went, "hours %d → %d · screen=%s" % [h0, int(r.hours), main.screen])
	# ②-0 **실제 UI 경로로** 임무 완료 → 거점 복귀 → 남은 시간으로 일반 탐험 출발까지.
	# 사용자 지적: "버튼 존재나 내부 함수 호출만으로 완료 처리하지 마라."
	# 앞선 검사는 카드에 done을 찍어 두고 버튼만 눌렀다. 여기서는 **전투를 실제로 이겨서** 돌아온다.
	await _repeat_after_real_sortie(main)

	# ② 오늘 카드를 다 끝낸 뒤 남는 시간: '일반 탐험'이 자기 영역에서 눌린다
	main.sortie = {}
	main.run.phase = "prep"
	main.run.hours = 2
	for c in PSortie.cards_for(main.run):
		c.done = true
	main.show("base")
	await process_frame
	bs = main.screens["base"]
	var rname := PPacing.repeat_label()
	var rep := _vis_enabled_button(bs, rname)
	ok("거점: 완료 뒤 남는 시간에 '%s' 버튼이 보이고 눌린다" % rname, rep != null, "없거나 비활성")
	var ctext := _card_text(rep) if rep != null else ""
	ok("'%s'은 완료 카드 밑의 보충 설명이 아니라 자기 영역에 있다" % rname,
		rep != null and ctext.find("오늘 완료") < 0 and ctext.find("임무 보상·사건·이용권은 없습니다") >= 0, ctext.substr(0, 120))
	if rep != null:
		var hb: int = int(main.run.hours)
		rep.pressed.emit()
		await process_frame
		ok("'%s' 버튼을 누르면 전투가 시작되고 시간 1칸이 준다" % rname,
			main.screen == "combat" and bool(main.sortie.get("repeat", false)) and int(main.run.hours) == hb - 1,
			"screen=%s hours=%d→%d" % [main.screen, hb, int(main.run.hours)])
		ok("일반 탐험 전투에는 사건·임무 보상이 없다", main.sortie.get("event", null) == null and not bool(main.sortie.get("mission", false)) and String(main.sortie.get("objective", "clear")) == "clear")
		main.view.running = false
	else:
		ok("'%s' 버튼을 누르면 전투가 시작되고 시간 1칸이 준다" % rname, false, "버튼을 못 찾음")
		ok("일반 탐험 전투에는 사건·임무 보상이 없다", false, "버튼을 못 찾음")
	# 남은 시간 1~5칸 어디에서도 '나갈 수 없는' 상태가 생기지 않는지 실제 버튼으로 훑는다
	var stuck := []
	for h in [1, 2, 3, 4, 5]:
		main.sortie = {}
		main.run.phase = "prep"
		main.run.hours = h
		for c2 in PSortie.cards_for(main.run):
			c2.done = true
		main.show("base")
		await process_frame
		var b3 := _vis_button(main.screens["base"], rname)
		if b3 == null or b3.disabled:
			stuck.append("%d칸: %s" % [h, "버튼 없음" if b3 == null else b3.text])
	ok("오늘 카드를 다 끝낸 뒤 남은 시간 1~5칸 어디서나 '%s'이 눌린다(시간이 남는데 못 나가는 상태 없음)" % rname, stuck.is_empty(), "; ".join(stuck))
	# ③ 시간이 없을 때
	main.sortie = {}
	main.run.phase = "prep"
	main.run.hours = 0
	main.run.services = {}
	main.show("base")
	await process_frame
	bs = main.screens["base"]
	var nextday := _vis_enabled_button(bs, "다음 날로")
	ok("시간이 없으면 '다음 날로'가 크게 보인다", nextday != null and nextday.get_theme_font_size("font_size") >= 18, "" if nextday == null else "%s size=%d" % [nextday.text, nextday.get_theme_font_size("font_size")])
	ok("'다음 날로'와 '하루 종료'를 여러 곳에 흩어놓지 않는다(한 곳뿐)",
		_count_buttons(bs, "다음 날로") == 1 and _count_buttons(bs, "하루 종료 →") == 0,
		"다음날로 %d · 하루종료 %d" % [_count_buttons(bs, "다음 날로"), _count_buttons(bs, "하루 종료 →")])
	var vshop: Button = bs.village.button("shop")
	ok("시간이 없어도 상점 버튼은 그대로 눌린다", vshop != null and not vshop.disabled)
	if vshop != null:
		vshop.pressed.emit()
		await process_frame
		ok("시간이 없어도 상점 화면이 실제로 열린다", main.screen == "shop", main.screen)
		main.go_base()
		await process_frame
	else:
		ok("시간이 없어도 상점 화면이 실제로 열린다", false, "버튼 없음")
	bs = main.screens["base"]
	# 휴식은 규칙(PRun.can_rest)이 시간 1칸을 요구한다. 버튼을 숨기지는 않고 이유와 함께 남긴다
	var vrest: Button = bs.village.button("rest")
	ok("시간이 없어도 휴식 버튼은 화면에 남는다(규칙이 막을 때만 비활성)", vrest != null and vrest.is_visible_in_tree() and vrest.disabled)
	main.run.services = { "free_rest": 1 }
	main.run.hp = 40.0
	main.show("base")
	await process_frame
	bs = main.screens["base"]
	vrest = bs.village.button("rest")
	ok("휴식권이 있으면 시간이 0칸이어도 휴식 버튼이 눌린다", vrest != null and not vrest.disabled and vrest.text.find(PUi.rest_ticket_name()) >= 0, "" if vrest == null else vrest.text)
	# ④ 휴식 확인 창: 소모·회복 전후를 적고, 취소하면 아무것도 바뀌지 않는다
	var hp_max := int(float(PBuild.derive(main.run).hp_max))
	vrest.pressed.emit()
	await process_frame
	bs = main.screens["base"]
	var rest_ok := _vis_button(bs, "휴식한다")
	ok("휴식은 확인 창을 거치고 소모·회복 전후 체력을 적는다",
		rest_ok != null and _vis_text(bs, "%d → %d" % [40, hp_max]) >= 1 and _vis_text(bs, PUi.rest_ticket_note()) >= 1,
		"창=%s" % str(rest_ok != null))
	var gold_b: int = int(main.run.gold)
	var hp_b: float = float(main.run.hp)
	var tickets: int = int(main.run.services.get("free_rest", 0))
	_vis_button(bs, "취소 (Esc)").pressed.emit()
	await process_frame
	ok("휴식을 취소하면 체력·휴식권·금화가 그대로다",
		is_equal_approx(float(main.run.hp), hp_b) and int(main.run.services.get("free_rest", 0)) == tickets and int(main.run.gold) == gold_b)
	main.screens["base"].village.button("rest").pressed.emit()
	await process_frame
	_vis_button(main.screens["base"], "휴식한다").pressed.emit()
	await process_frame
	ok("휴식을 확정하면 체력이 회복되고 휴식권 1장이 준다",
		float(main.run.hp) > hp_b and int(main.run.services.get("free_rest", 0)) == tickets - 1,
		"hp %.0f → %.0f · 권 %d" % [hp_b, float(main.run.hp), int(main.run.services.get("free_rest", 0))])
	# ⑥ 거점 '현재 빌드' 아이콘: 눌러야 짧은 정보가 열리고, 긴 조건은 '상세 설명'을 한 번 더 눌러야 나온다
	main.run.hours = 3
	main.show("base")
	await process_frame
	bs = main.screens["base"]
	var wbtn := _tile_button(bs, PIcons.weapon_key("sword"))
	ok("거점 '현재 빌드'의 무기 아이콘이 눌리는 버튼이다(PC 클릭·터치 탭 같은 경로)", wbtn != null)
	wbtn.mouse_entered.emit()
	await process_frame
	ok("아이콘에 마우스를 올리기만 하면 아무것도 열리지 않는다", not bs.confirm_open())
	wbtn.pressed.emit()
	await process_frame
	bs = main.screens["base"]
	ok("아이콘을 누르면 짧은 정보와 관련 행동이 열린다",
		bs.confirm_open() and _vis_text(bs, "붙은 개조") >= 1 and _vis_button(bs, "상세 설명") != null and _vis_button(bs, "대장간에서") != null)
	ok("긴 조건·후보 목록은 '상세 설명'을 눌러야 나온다", _vis_text(bs, "아직 붙지 않은 개조 후보") == 0)
	_vis_button(bs, "상세 설명").pressed.emit()
	await process_frame
	bs = main.screens["base"]
	ok("'상세 설명'을 누르면 소제목으로 나뉜 긴 설명이 열린다(한 문단으로 이어 붙이지 않는다)",
		_vis_text(bs, "아직 붙지 않은 개조 후보") == 1 and _vis_text(bs, "기본값") == 1)
	var g_keep: int = int(main.run.gold)
	_vis_button(bs, "닫기 (Esc)").pressed.emit()
	await process_frame
	ok("아이콘 창을 닫아도 회차 상태가 바뀌지 않는다", not main.screens["base"].confirm_open() and int(main.run.gold) == g_keep)
	# 무기 표기: 연타 수가 빠진 "피해 6"을 쓰지 않는다
	var rd: Dictionary = PRun.new_run(1, "sword")
	rd.growth.weapons = [{ "id": "daggers", "level": 1, "mods": [] }]
	var wsd: Dictionary = PBuild.derive(rd).weapons[0]
	ok("연타가 있는 무기는 '6 × 3연타'처럼 실제 공격 구조를 보여 준다(연타 수가 빠진 '피해 6' 금지)",
		PUi.weapon_damage_text(wsd).find("× 3연타") >= 0 and PUi.weapon_stats_text(wsd).find("간격") >= 0, PUi.weapon_stats_text(wsd))
	# ⑤⑥⑦ 장비 화면: 고른 창에 장착·상세·판매가 모이고, 상세는 눌러야 열린다
	for sl in PCatalog.world().equip_slots:
		main.run.equipment[String(sl)] = null
	main.run.bag = ["guardian_armor"]
	main.show("equip")
	await process_frame
	var es: Node = main.screens["equip"]
	var sel := _vis_button(es, "선택")
	ok("장비 목록은 고르는 버튼만 두고 판매·전후 수치를 줄마다 반복하지 않는다",
		sel != null and _vis_text(es, "판매 +") == 0 and _vis_text(es, "장착하면") == 0, "선택=%s" % str(sel != null))
	# 마우스를 올리기만 해서는 아무것도 열리지 않는다
	sel.mouse_entered.emit()
	await process_frame
	ok("마우스를 올리기만 하면 상세·행동 창이 열리지 않는다", not es.confirm_open())
	sel.pressed.emit()
	await process_frame
	es = main.screens["equip"]
	ok("장비를 고른 창에 장착·상세 설명·판매가 모여 있다",
		_vis_button(es, "지금 장착") != null and _vis_button(es, "상세 설명") != null and _vis_button(es, "판매 (+") != null)
	ok("상세 설명은 버튼을 눌러야 열린다(누르기 전에는 긴 조건이 없다)", _vis_text(es, "교체 규칙") == 0)
	_vis_button(es, "상세 설명").pressed.emit()
	await process_frame
	es = main.screens["equip"]
	ok("상세 설명을 누르면 소제목으로 나뉜 긴 설명이 열린다", _vis_text(es, "교체 규칙") == 1 and _vis_text(es, "되팔 때") == 1)
	# 판매 확인 창: 받을 금액 · 취소하면 그대로 · 중복 클릭해도 한 번만
	# 판매가의 정본은 PRun.sell_quote다(구매액의 절반, 구매액이 없으면 정상가의 절반).
	# 옛 PRun.sell_price는 정상가의 1/4이던 시절의 함수라 여기서 쓰지 않는다
	var price := int(PRun.sell_quote(main.run, "guardian_armor").gold)
	var g0: int = int(main.run.gold)
	var bag0: int = (main.run.bag as Array).size()
	_vis_button(es, "판매 (+").pressed.emit()
	await process_frame
	es = main.screens["equip"]
	ok("판매는 받을 금액을 적은 확인 창을 거친다",
		_vis_button(es, "판매한다") != null and _vis_text(es, "판매할까요?") == 1 and _vis_text(es, "+%d금" % price) >= 1)
	_vis_button(es, "취소 (Esc)").pressed.emit()
	await process_frame
	ok("판매를 취소하면 금화·가방이 그대로다", int(main.run.gold) == g0 and (main.run.bag as Array).size() == bag0)
	es = main.screens["equip"]
	_vis_button(es, "선택").pressed.emit()
	await process_frame
	es = main.screens["equip"]
	_vis_button(es, "판매 (+").pressed.emit()
	await process_frame
	es = main.screens["equip"]
	var yes := _vis_button(es, "판매한다")
	yes.pressed.emit()
	yes.pressed.emit() # 중복 클릭
	await process_frame
	ok("판매 확정은 중복 클릭해도 한 번만 반영된다(금화·가방 복제 없음)",
		int(main.run.gold) == g0 + price and (main.run.bag as Array).size() == bag0 - 1,
		"gold %d → %d · 가방 %d → %d" % [g0, int(main.run.gold), bag0, (main.run.bag as Array).size()])
	# ⑤ 상점: 구매 → '지금 장착 / 가방에 넣기'
	main.run.gold = 2000
	main.show("shop")
	await process_frame
	var ss: Node = main.screens["shop"]
	var stock_ids: Array = PRun.stock(main.run).equipment
	var e0 := String(stock_ids[0])
	var slot0 := String(PCatalog.equipment_def(e0).slot)
	var buy := _vis_enabled_button(ss, "구매 (")
	ok("상점: 장비는 '구매' 버튼 하나로 시작한다(구매 후 장착/보관을 미리 나눠 두지 않는다)",
		buy != null and _vis_text(ss, "구매 후 장착") == 0, "" if buy == null else buy.text)
	buy.pressed.emit()
	await process_frame
	ss = main.screens["shop"]
	ok("구매를 누르면 '지금 장착 / 가방에 넣기'가 뜬다",
		_vis_button(ss, "지금 장착") != null and _vis_button(ss, "가방에 넣기") != null and _vis_text(ss, "살까요?") == 1)
	var g1: int = int(main.run.gold)
	_vis_button(ss, "취소 (Esc)").pressed.emit()
	await process_frame
	ok("구매를 취소하면 금화·가방이 그대로다", int(main.run.gold) == g1 and not PRun.owns_equip(main.run, e0))
	ss = main.screens["shop"]
	_vis_enabled_button(ss, "구매 (").pressed.emit()
	await process_frame
	ss = main.screens["shop"]
	_vis_button(ss, "지금 장착").pressed.emit()
	await process_frame
	ok("'지금 장착'을 누르면 그 부위에 실제로 장착되고 금화가 준다",
		main.run.equipment.get(slot0, null) != null and String(main.run.equipment[slot0]) == e0 and int(main.run.gold) < g1,
		"%s=%s gold=%d" % [slot0, str(main.run.equipment.get(slot0, null)), int(main.run.gold)])
	ss = main.screens["shop"]
	var g2: int = int(main.run.gold)
	var bag_n: int = (main.run.bag as Array).size()
	var buy2 := _vis_enabled_button(ss, "구매 (")
	if buy2 != null:
		buy2.pressed.emit()
		await process_frame
		ss = main.screens["shop"]
		_vis_button(ss, "가방에 넣기").pressed.emit()
		await process_frame
		ok("'가방에 넣기'를 누르면 가방에 들어가고 장착은 그대로다",
			(main.run.bag as Array).size() == bag_n + 1 and String(main.run.equipment[slot0]) == e0 and int(main.run.gold) < g2,
			"가방 %d → %d" % [bag_n, (main.run.bag as Array).size()])
	else:
		ok("'가방에 넣기'를 누르면 가방에 들어가고 장착은 그대로다", false, "살 수 있는 재고가 없음")
	main.run = {}
	main.sortie = {}
	PSave.clear()

func _move_tests(main: Node) -> void:
	PSave.clear()
	main.new_run_opts = {}
	main.start_run("sword")
	var rm: Dictionary = main.run
	var so := PSortie.start(rm, String(PSortie.cards_for(rm)[0].id))
	main.view.running = false
	# ① 모든 테마 경기장: 시작 위치가 장애물 안이어도 8방향으로 걸을 수 있어야 한다
	var stuck := []
	var spawn_in_rock := []
	for aid in PCatalog.theme_arenas():
		var s2 := so.duplicate(true)
		s2.arena = String(aid)
		var stt := PFlow.make_encounter(rm, s2)
		for ob in stt.obstacles:
			if PGeom.dist(float(ob.x), float(ob.y), stt.player.x, stt.player.y) < float(ob.r) + float(stt.player.r):
				spawn_in_rock.append("%s/%s" % [String(aid), String(ob.id)])
		if _walk_min(stt) < 1.0:
			stuck.append(String(aid))
	ok("모든 테마 경기장에서 8방향 걷기가 된다(장애물 접촉 탈출 규칙)", stuck.is_empty(), "막힌 경기장: " + str(stuck))
	# KD-3 닫힘(2026-09-08): themes.json의 키를 playerStart로 맞추고 combat_state.gd가 player도 함께 읽는다.
	# 고치기 전에는 아래 5곳이 시작 위치가 바위 안이었다. 이제 0곳이어야 한다(다시 늘면 여기서 잡힌다).
	var was := ["fort_wall/r5", "mine_tunnel/r5", "abyss_center/r1", "blood_path/r3", "citadel_corridor/r5"]
	ok("시작 위치가 장애물 안인 경기장이 없다(KD-3 수정 전 5곳: %s)" % str(was), spawn_in_rock.is_empty(), "겹침=" + str(spawn_in_rock))
	# ② 9일차 실제 경기장(abyss_center)에서 화면 경로로 걷기
	var s9 := so.duplicate(true)
	s9.arena = "abyss_center"
	var st9 := PFlow.make_encounter(rm, s9)
	main.view.start_state(st9, null)
	main.show("combat")
	var ov := 0.0
	for ob in st9.obstacles:
		ov = maxf(ov, float(ob.r) + float(st9.player.r) - PGeom.dist(float(ob.x), float(ob.y), st9.player.x, st9.player.y))
	var moved := _view_walk(main, Vector2(1, 0))
	ok("9일차 경기장(abyss_center): 화면 경로로 걸어진다(시작 겹침 0px여야 한다)", moved > 20.0 and ov <= 0.0, "시작 겹침 %.1fpx · 이동 %.1fpx" % [ov, moved])
	var diag: Dictionary = main.view.move_diag()
	ok("이동 진단이 입력·이동량·이유를 남긴다", diag.has("입력") and diag.has("이동") and diag.has("이유") and (diag["전투"] as Dictionary).has("탈출예외"), JSON.stringify(diag.get("이유", [])))
	# ③ 레벨업 3택을 열고 고른 뒤 이동이 살아 있는가
	main.run.growth.pendingLevelUps = 1
	var off = PFlow.next_offer(main.run)
	main.open_choice(off)
	var paused_in_choice: bool = main.view.paused
	main._on_pick(String(off.choices[0].key))
	ok("3택 종료 뒤 전투 재개(선택 중에는 정지, 닫으면 해제)", paused_in_choice and not main.view.paused and _view_walk(main, Vector2(0, 1)) > 20.0)
	# ④ 일시정지 → 조작법 → 설정 → 닫기
	main.set_pause(true)
	main.show_controls(true)
	main.open_settings()
	main.settings_panel.close()
	main._on_settings_closed()
	main.controls_panel.visible = false
	main.set_pause(false)
	ok("일시정지·조작법·설정을 닫으면 이동이 돌아온다", not main.view.paused and _view_walk(main, Vector2(-1, 0)) > 20.0)
	# ⑤ 빌드 상세(Tab) 열고 닫기
	main.open_build_detail()
	var paused_in_detail: bool = main.view.paused
	main.build_detail.close()
	ok("빌드 상세를 닫으면 이동이 돌아온다", paused_in_detail and not main.view.paused and _view_walk(main, Vector2(0, -1)) > 20.0)
	# ⑥ 용어 팝업 고정 → 해제
	main._on_tip_pins(1)
	var paused_in_tip: bool = main.view.paused
	main._on_tip_pins(0)
	ok("용어 팝업을 닫으면 이동이 돌아온다", paused_in_tip and not main.view.paused and _view_walk(main, Vector2(1, 1)) > 20.0)
	# ⑦ 창 포커스 상실 → 복귀(대기 입력·가상 스틱은 버려지지만 이동 자체는 살아 있어야 한다)
	main.view.router.set_virtual_move(Vector2(1, 0))
	main.view._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var cleared: bool = main.view.router.virtual_move == Vector2.ZERO
	main.view._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	ok("포커스 상실 시 대기 입력이 비워지고, 복귀 뒤 이동이 된다", cleared and _view_walk(main, Vector2(-1, -1)) > 20.0)
	# ⑧ 터치 오버레이: 스틱을 잡았다가 놓으면 가상 이동이 남지 않는다(잠금 잔존 방지)
	main.touch.enabled = true
	main.touch.layout(Rect2(0.0, 0.0, 960.0, 640.0)) # 헤드리스에서도 스틱 영역이 정해지게 고정
	main.touch.handle_touch(1, main.touch.zone_rect().position + Vector2(30, 30), true)
	main.touch.handle_drag(1, main.touch.zone_rect().position + Vector2(90, 30))
	var held_move: Vector2 = main.view.router.virtual_move
	main.touch.handle_touch(1, main.touch.zone_rect().position + Vector2(90, 30), false)
	ok("터치 스틱을 놓으면 이동 입력이 남지 않는다(키보드 전환 시 방해 없음)", held_move != Vector2.ZERO and main.view.router.virtual_move == Vector2.ZERO, "잡았을 때 %s → 놓은 뒤 %s" % [str(held_move), str(main.view.router.virtual_move)])
	main.touch.release_all()
	main.touch.enabled = PLayout.is_touch()
	ok("터치를 거친 뒤에도 키보드 경로로 이동이 된다", _view_walk(main, Vector2(0, 1)) > 20.0)
	# ⑨ 이동 배율·상태: 이동 배율이 0이면 진단이 그 이유를 말한다(규칙은 바꾸지 않는다)
	var keep: float = float(main.view.st.build.speed_mult)
	main.view.st.build.speed_mult = 0.0
	var frozen := _view_walk(main, Vector2(1, 0), 10)
	var reasons: Array = main.view.move_diag().get("이유", [])
	main.view.st.build.speed_mult = keep
	var said := false
	for r in reasons:
		if String(r).find("이동 속도 0") >= 0:
			said = true
	ok("이동 배율이 0이면 진단이 '이동 속도 0'을 이유로 남긴다", frozen < 1.0 and said, str(reasons))
	main.view.running = false
	main.view.st = null
	main.run = {}
	main.sortie = {}
	PSave.clear()

## 화면 트리에서 글자를 포함하는 Button 찾기(실제 UI 경로 검사용)
func _find_button(node: Node, part: String) -> Button:
	if node is Button and (node as Button).text.find(part) >= 0:
		return node as Button
	for ch in node.get_children():
		var f := _find_button(ch, part)
		if f != null:
			return f
	return null

func _count_buttons(node: Node, part: String) -> int:
	var n := 1 if (node is Button and (node as Button).text.find(part) >= 0) else 0
	for ch in node.get_children():
		n += _count_buttons(ch, part)
	return n

## 같은 부모(카드 상자) 안의 다른 버튼
func _sibling_button(btn: Button, part: String) -> Button:
	var p := btn.get_parent()
	if p == null:
		return null
	for ch in p.get_children():
		if ch is Button and (ch as Button).text.find(part) >= 0:
			return ch as Button
	return null

## 지금 실제로 보이는 Button만 찾는다(닫아 둔 확인 창의 옛 버튼을 잡지 않게)
func _vis_button(node: Node, part: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and (node as Button).text.find(part) >= 0:
		return node as Button
	for ch in node.get_children():
		var f := _vis_button(ch, part)
		if f != null:
			return f
	return null

## 보이면서 눌리는 Button(비활성 카드의 같은 이름 버튼을 건너뛴다)
func _vis_enabled_button(node: Node, part: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and (node as Button).text.find(part) >= 0 and not (node as Button).disabled:
		return node as Button
	for ch in node.get_children():
		var f := _vis_enabled_button(ch, part)
		if f != null:
			return f
	return null

## 지금 보이는 글자에서 needle이 몇 번 나오는가(숨은 층은 세지 않는다)
func _vis_text(node: Node, needle: String) -> int:
	if node is Control and not (node as Control).is_visible_in_tree():
		return 0
	var n := 0
	if node is RichTextLabel and String((node as RichTextLabel).text).find(needle) >= 0:
		n += 1
	if node is Label and String((node as Label).text).find(needle) >= 0:
		n += 1
	if node is Button and String((node as Button).text).find(needle) >= 0:
		n += 1
	for c in node.get_children():
		n += _vis_text(c, needle)
	return n

## 아이콘 칸(PIconTile)을 감싼 버튼 찾기: 아이콘을 실제로 누를 수 있는지 확인하는 경로
func _tile_button(node: Node, key: String) -> Button:
	if node is Button:
		for ch in node.get_children():
			if ch is PIconTile and String((ch as PIconTile).key) == key:
				return node as Button
	for c in node.get_children():
		var b := _tile_button(c, key)
		if b != null:
			return b
	return null

## 이 버튼이 들어 있는 카드(가장 가까운 PanelContainer) 안의 글자 전부
func _card_text(btn: Node) -> String:
	var n: Node = btn
	while n != null and not (n is PanelContainer):
		n = n.get_parent()
	return _all_text(n) if n != null else ""

func _all_text(node: Node) -> String:
	var s := ""
	if node is RichTextLabel:
		s += String((node as RichTextLabel).text) + "\n"
	if node is Label:
		s += String((node as Label).text) + "\n"
	if node is Button:
		s += String((node as Button).text) + "\n"
	for c in node.get_children():
		s += _all_text(c)
	return s

func _reopen(main: Node) -> void: # 저장 파일만 남기고 다시 연 상황 = 제목 → 계속하기(추가 저장 없음)
	main.view.running = false
	main.go_title()
	main.continue_run()

func _run() -> void:
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	# ---------- F1: 심층 전투 도중 종료 ----------
	main.start_run("sword")
	main.start_sortie_card("d1c1")
	var hours_in_combat: int = int(main.run.hours)
	var disk := PSave.load()
	ok("전투 시작 체크포인트: 디스크 저장에 pendingSortie 없음, 출격 비용은 지불됨(4칸)", disk.get("pendingSortie", null) == null and int(disk.hours) == 4 and hours_in_combat == 4)
	_win(main)
	main.sortie.event = { "id": "supply", "seed": 1, "resolved": true, "choice": "leave" }
	var loot_before: int = int(main.sortie.loot.gold)
	ok("승리 뒤 안전 화면 저장에는 pendingSortie 있음(전리품 %d)" % loot_before, PSave.load().get("pendingSortie", null) != null and loot_before > 0)
	main.deep_explore()
	ok("더 깊이 시작: 체크포인트에 pendingSortie 없음, 시간 3칸", PSave.load().get("pendingSortie", null) == null and int(PSave.load().hours) == 3 and main.screen == "combat")
	var gold0: int = int(main.run.gold)
	var level0: int = int(main.run.growth.level)
	_reopen(main)
	ok("심층 전투 도중 종료 → 계속하기: 거점으로 복구, 미정산 전리품 상실(금화 불변), 시간 3칸 유지", main.screen == "base" and main.run.get("pendingSortie", null) == null and int(main.run.gold) == gold0 and int(main.run.hours) == 3 and int(main.run.growth.level) == level0, "screen=%s gold=%d hours=%d" % [main.screen, int(main.run.gold), int(main.run.hours)])
	# ---------- F1: 전투 중 레벨업 선택 뒤 자동 저장 ----------
	main.start_sortie_card("d1c2")
	main.run.growth.pendingLevelUps = 1
	var off = PFlow.next_offer(main.run)
	main.open_choice(off)
	main._on_pick(String(off.choices[0].key))
	ok("전투 중 3택 선택 뒤 자동 저장: pendingSortie 없음, 선택은 저장됨(성장 유지)", PSave.load().get("pendingSortie", null) == null and int(PSave.load().growth.level) == int(main.run.growth.level) and int(PSave.load().growth.pendingLevelUps) == 0)
	_reopen(main)
	# 남는 시간 1칸: 5 - d1c1(숲길 1칸) - 더 깊이(1칸) - d1c2(사냥터 안쪽 **2칸**) = 1.
	# 2026-09-09 기대값 정정: 예전 일정은 1일차가 forest·ridge(둘 다 1칸)라 2칸이 남았다.
	# 막 테마 경로가 들어오면서 1일차 둘째 장소가 t1a_core(themes.json cost 2)로 바뀌었다 —
	# 규칙이 바뀐 것이지 흐름이 깨진 것이 아니므로 기대값을 실제 비용표에 맞춘다.
	var c2_cost := PRun.place_cost(String(PSortie.card(main.run, "d1c2").get("regionId", "")))
	ok("그 상태로 종료 → 계속하기: 거점, 시간 %d칸(=3-둘째 카드 %d칸), 성장 유지" % [3 - c2_cost, c2_cost],
		main.screen == "base" and int(main.run.hours) == 3 - c2_cost and int(main.run.growth.level) == level0,
		"screen=%s hours=%d level=%d(기대 %d)" % [main.screen, int(main.run.hours), int(main.run.growth.level), level0])
	# ---------- F1: 사건 추가 전투 ----------
	main.run.hours = 5
	main.run.day = 2
	main.run.cards = null
	var picked := ""
	for c in PSortie.cards_for(main.run):
		if PSortie.can_start(main.run, c):
			picked = String(c.id)
			break
	main.start_sortie_card(picked)
	_win(main)
	main.run.hp = 100.0
	main.sortie.event = { "id": "merchant", "seed": 3, "resolved": false, "choice": null, "service": "free_rest" }
	var opts := PEvents.options(main.run, main.sortie)
	var fight_opt := ""
	for o in opts:
		if String(o.get("next", "")) == "fight" or String(o.id) in ["fight", "open"]:
			fight_opt = String(o.id)
	if fight_opt != "":
		main.event_choice(fight_opt)
		ok("사건 추가 전투 시작: 체크포인트에 pendingSortie 없음", main.screen == "combat" and PSave.load().get("pendingSortie", null) == null)
		var g2: int = int(main.run.gold)
		_reopen(main)
		ok("사건 전투 도중 종료 → 거점 복구, 전리품 미반영", main.screen == "base" and int(main.run.gold) == g2)
	else:
		ok("사건 추가 전투 선택지 확인(갇힌 상인)", false, str(opts))
	# ---------- F1: 보스전 도중 종료 ----------
	main.run.day = 4
	main.run.phase = "boss_prep"
	main.run.hours = 5
	main.start_boss()
	ok("보스 입장 체크포인트: pendingSortie 없음·phase boss_prep 유지", main.screen == "combat" and PSave.load().get("pendingSortie", null) == null and String(PSave.load().phase) == "boss_prep")
	_reopen(main)
	ok("보스전 도중 종료 → 거점(관문 준비), 재도전 수 0, 하루 손실 없음", main.screen == "base" and String(main.run.phase) == "boss_prep" and int(main.run.bossRetries) == 0 and int(main.run.day) == 4)
	# ---------- F2: 수호 결계 HUD ----------
	main.run = PRun.new_run(1, "sword")
	main.run.growth.skills.e = { "id": "ward", "level": 1, "variant": null }
	main.run.cards = null
	main.start_sortie_card(String(PSortie.cards_for(main.run)[0].id))
	main.view.running = false
	main.view.st.intro = 0.0
	var cast: bool = PSkills.cast_e(main.view.st)
	main._update_hud()
	var hud: String = main.get_node("UI/HUD/HPText").text
	ok("수호 결계 30: 실제 보호막 30, HUD '보호막 30'(구성분 중복 합산 없음)", cast and is_equal_approx(main.view.st.player.shield, 30.0) and hud.ends_with("보호막 30"), hud)
	main.view.st.damage_player(12.0, "wolf:bite")
	main._update_hud()
	hud = main.get_node("UI/HUD/HPText").text
	ok("부분 흡수 뒤: 보호막 18, HUD '보호막 18', 체력 100", is_equal_approx(main.view.st.player.shield, 18.0) and hud.ends_with("보호막 18") and main.view.st.player.hp == 100.0, hud)
	main.run = PRun.new_run(1, "sword")
	main.run.growth.skills.e = { "id": "ward", "level": 1, "variant": null }
	main.run.equipment.armor = "guardian_armor"
	main.run.bag = ["guardian_armor"]
	main.run.cards = null
	main.start_sortie_card(String(PSortie.cards_for(main.run)[0].id))
	main.view.running = false
	main.view.st.intro = 0.0
	PSkills.cast_e(main.view.st)
	main._update_hud()
	hud = main.get_node("UI/HUD/HPText").text
	ok("수호자의 갑옷 15 + 수호 결계 30 = 보호막 45(HUD 동일)", is_equal_approx(main.view.st.player.shield, 45.0) and hud.ends_with("보호막 45"), hud)
	main.view.st.spawn_hold = true # 적 소환 정지: 만료만 본다
	for i in 600: # 5초: 결계 4초 만료
		main.view.st.step({}, 1.0 / 120.0)
	main._update_hud()
	hud = main.get_node("UI/HUD/HPText").text
	ok("결계 만료 뒤: 결계분 제거, 갑옷 보호막 15만 남고 HUD도 15", is_equal_approx(main.view.st.player.shield, 15.0) and hud.ends_with("보호막 15"), hud + " shield=%.1f ward=%.1f" % [main.view.st.player.shield, main.view.st.player.ward_shield])
	main.view.running = false
	# ---------- 0.7.0 새 경로(지시 17 ③): 실제 화면 함수로 확인 ----------
	PSave.clear()
	main.new_run_opts = {}
	main.start_run("sword")
	var r7: Dictionary = main.run
	ok("새 회차 UI 경로 = 본편 10일·관문 4/7/10", String(r7.mode) == "acts" and int(PRun.mode_def(r7).days) == 10 and PRun.schedule_short(r7) == "본편 · 10일" and PRun.next_boss(r7).day == 4, PRun.schedule_label(r7))
	main.save_run()
	var saved7 := PSave.load()
	ok("계속하기 라벨이 저장의 실제 일정을 말한다", PRun.schedule_short_of_save(saved7) == "본편 · 10일" and PRun.schedule_short_of_save({ "mode": "trio" }) == "이전 회차 · 7일 일정")
	# 오늘 카드를 모두 끝낸 뒤 남는 시간 → 일반 탐험 재출격
	for c in PSortie.cards_for(r7):
		c.done = true
	r7.hours = 2
	var rep_ids := PFlow.actions(r7).filter(func(a): return bool(a.data.get("repeat", false))).map(func(a): return String(a.id))
	ok("카드를 다 끝내고 시간이 남으면 행동 목록에 '일반 탐험'이 있다(강제 휴식 아님)", rep_ids.size() >= 1 and PRun.any_departure(r7), str(rep_ids))
	var h_before: int = int(r7.hours)
	main.start_sortie_card(String(rep_ids[0]).replace("sortie:", ""))
	ok("일반 탐험 출격이 실제로 진행되고 시간 1칸을 쓴다", not main.sortie.is_empty() and bool(main.sortie.get("repeat", false)) and int(r7.hours) == h_before - 1)
	main.view.running = false
	main.run.hours = 2
	# 제단 이름·짧은 효과 / 개조 변경권 용어
	ok("제단 이름이 효과를 말한다(적 치유·소환·저주)", String(PCatalog.enemy("altar_heal").name) == "적 치유 제단" and String(PCatalog.enemy("altar_reinforce").name) == "소환 제단" and String(PCatalog.enemy("altar_hazard").name) == "저주 제단")
	ok("이용권 용어가 '개조 변경권'으로 통일(기술 교체와 구분)", String(PCatalog.services()["mod_swap"].name) == "개조 변경권" and String(PCatalog.glossary()["voucher"].short).find("개조 변경권") >= 0)
	# 무료 이득 사건: 지나치기 없음
	var s_ev := PSortie.start(r7, "d1c1") if not PSortie.card(r7, "d1c1").is_empty() else {}
	r7.pendingSortie = { "regionId": String(PRun.places_for(r7)[0]), "loot": { "gold": 0, "mats": {} }, "encounters": 1, "event": { "id": "supply", "seed": 1, "resolved": false }, "settled": false }
	var ev_ids := PEvents.options(r7, r7.pendingSortie).map(func(o): return String(o.id))
	ok("무료 보급 사건에는 '지나친다'가 없다(이득만 있는 선택)", not ev_ids.has("leave") and ev_ids.has("loot"), str(ev_ids))
	r7.pendingSortie = null
	await _town_ui_tests(main)
	_move_tests(main)
	main.queue_free()
	await process_frame
	PSave.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
