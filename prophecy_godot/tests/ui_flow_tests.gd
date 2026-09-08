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
	main._on_finished(main.view.st.summary())

# ---------- 이동 불능 회귀(2026-09-08 "9일차에 움직이지 않아 죽었다" 보고) ----------
## 실제 원인: 테마 경기장의 시작 위치가 바위 중심과 같아(예: abyss_center, 9일차 t3a_center)
## 플레이어가 바위 표면에 붙은 채 시작하고, 접촉 탈출 규칙이 없으면 어느 방향으로도 못 움직였다.
## 아래 검사는 (1) 모든 테마 경기장에서 8방향 걷기가 되는지, (2) 실제 화면 경로(CombatView._process →
## PInputRouter.poll → PStepDriver.frame)로 걸어지는지, (3) 3택·일시정지·설정·빌드 상세·포커스·터치를
## 거친 뒤에도 이동이 살아 있는지를 본다.

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
	# 시작 위치가 바위 안인 경기장은 남아 있다(themes.json은 player, combat_state.gd는 playerStart를 읽는다).
	# 규칙 파일이 아니라 데이터·규칙 담당 몫이므로 여기서는 '알고 있는 목록'으로 고정해 새로 늘어나는 것만 잡는다.
	var known := ["fort_wall/r5", "mine_tunnel/r5", "abyss_center/r1", "blood_path/r3", "citadel_corridor/r5"]
	var extra := spawn_in_rock.filter(func(x): return not known.has(x))
	ok("시작 위치가 장애물 안인 경기장이 더 늘지 않았다(알려진 5곳)", extra.is_empty(), "겹침=" + str(spawn_in_rock) + " 새로 늘어난 것=" + str(extra))
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
	ok("9일차 경기장(abyss_center): 시작이 바위와 겹쳐도 화면 경로로 걸어진다", moved > 20.0, "시작 겹침 %.1fpx · 이동 %.1fpx" % [ov, moved])
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
	ok("그 상태로 종료 → 계속하기: 거점, 시간 2칸, 성장 유지", main.screen == "base" and int(main.run.hours) == 2 and int(main.run.growth.level) == level0)
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
	# 같은 상황을 실제 거점 화면으로: 카드 안의 '일반 탐험' 버튼을 찾아 눌러 본다(규칙 함수 직접 호출 아님)
	main.run.hours = 2
	main.run.phase = "prep"
	main.sortie = {}
	for c2 in PSortie.cards_for(main.run):
		c2.done = true
	main.show("base")
	await process_frame
	var base_screen: Node = main.screens["base"]
	var rep_btn := _find_button(base_screen, PPacing.repeat_label())
	ok("거점 화면: 완료한 장소 카드 안에 '일반 탐험' 버튼이 실제로 보인다", rep_btn != null and rep_btn.is_visible_in_tree() and not rep_btn.disabled, ("없음" if rep_btn == null else rep_btn.text))
	var rep_n := _count_buttons(base_screen, PPacing.repeat_label())
	var inside: bool = rep_btn != null and _sibling_button(rep_btn, "오늘 완료") != null # 같은 카드 상자 안(= 새 카드 더미가 아니다)
	ok("새 카드 더미가 아니라 완료한 기존 장소 카드 안에 들어간다", inside and rep_n == 2, "일반 탐험 버튼 %d개 · 같은 카드 안=%s" % [rep_n, str(inside)])
	if rep_btn != null:
		var hb2: int = int(main.run.hours)
		rep_btn.pressed.emit() # 실제 버튼 누름
		await process_frame
		ok("거점 화면 버튼을 누르면 전투가 시작되고 시간 1칸이 줄어든다", main.screen == "combat" and not main.sortie.is_empty() and bool(main.sortie.get("repeat", false)) and int(main.run.hours) == hb2 - 1,
			"screen=%s hours=%d→%d" % [main.screen, hb2, int(main.run.hours)])
		ok("일반 탐험 전투에는 사건·임무 보상이 없다", main.sortie.get("event", null) == null and not bool(main.sortie.get("mission", false)) and String(main.sortie.get("objective", "clear")) == "clear")
		main.view.running = false
	else:
		ok("거점 화면 버튼을 누르면 전투가 시작되고 시간 1칸이 줄어든다", false, "버튼을 못 찾음")
		ok("일반 탐험 전투에는 사건·임무 보상이 없다", false, "버튼을 못 찾음")
	# 시간이 없으면 같은 버튼이 이유와 함께 비활성이어야 한다(카드는 그대로, 선택지만 잠긴다)
	main.run.hours = 0
	main.sortie = {}
	main.show("base")
	await process_frame
	var off_btn := _find_button(main.screens["base"], PPacing.repeat_label())
	ok("시간이 없으면 '일반 탐험' 버튼은 이유와 함께 비활성", off_btn != null and off_btn.disabled and off_btn.text.find("시간 부족") >= 0, ("없음" if off_btn == null else off_btn.text))
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
