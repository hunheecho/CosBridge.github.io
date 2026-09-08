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
	# 제단 이름·짧은 효과 / 개조 변경권 용어
	ok("제단 이름이 효과를 말한다(적 치유·소환·저주)", String(PCatalog.enemy("altar_heal").name) == "적 치유 제단" and String(PCatalog.enemy("altar_reinforce").name) == "소환 제단" and String(PCatalog.enemy("altar_hazard").name) == "저주 제단")
	ok("이용권 용어가 '개조 변경권'으로 통일(기술 교체와 구분)", String(PCatalog.services()["mod_swap"].name) == "개조 변경권" and String(PCatalog.glossary()["voucher"].short).find("개조 변경권") >= 0)
	# 무료 이득 사건: 지나치기 없음
	var s_ev := PSortie.start(r7, "d1c1") if not PSortie.card(r7, "d1c1").is_empty() else {}
	r7.pendingSortie = { "regionId": String(PRun.places_for(r7)[0]), "loot": { "gold": 0, "mats": {} }, "encounters": 1, "event": { "id": "supply", "seed": 1, "resolved": false }, "settled": false }
	var ev_ids := PEvents.options(r7, r7.pendingSortie).map(func(o): return String(o.id))
	ok("무료 보급 사건에는 '지나친다'가 없다(이득만 있는 선택)", not ev_ids.has("leave") and ev_ids.has("loot"), str(ev_ids))
	r7.pendingSortie = null
	main.queue_free()
	await process_frame
	PSave.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
