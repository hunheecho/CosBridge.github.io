extends SceneTree
## 화면을 막는 창은 **언제나 나갈 수 있어야 한다** — 그리고 그것을 **버튼을 실제로 눌러서** 확인한다.
## 실행: python tools/run_suites.py --suites overlay_tests
##
## 왜 있는가 — 사람 플레이 보고(2026-09-09):
##   "포로 구출했는데 또 봉인돼서 화면 아무것도 누를 수 없는 상태가 되냐고."
##   "모바일에서 화면에 버튼을 감추지 마. esc 같은 건 데스크탑에서나 할 수 있지
##    모바일에선 버튼 없으면 아예 안 된다고."
##
## 사용자 지시(2026-09-09): **'버튼 존재'와 '실제로 탈출 가능'을 구분할 것.**
## 예전 판은 버튼 **이름만** 봤다. 이름이 있어도 눌렀을 때 창이 안 닫히거나 다음이 안 이어지면
## 사람에게는 똑같이 갇힌 화면이다. 그래서 이 파일은 네 갈래로 나뉜다:
##
##   ① 창 단독(헤드리스): pool별 탈출구를 **눌러서** 신호(skipped/picked)가 실제로 나는지
##   ② 실제 화면 경로(main.tscn): 눌러서 **창이 닫히고**(is_open()==false)
##      **전투 입력 관문이 풀리고**(view.paused==false) 다음 보상·거점 이동·전투 재개가 이어지는지
##   ③ 증상 재현: 포로 구출(rescue) → 보상 → 계속 → 다음 진행. 그리고 그다음이 봉인(seal)인 경로
##   ④ 빈 후보의 사유 구분: 정상 소진 / 생성 오류 / 미정의 pool 이 각각 어디에 남는지
##
## ③은 통과/실패 판정 위에 **재현 여부를 그대로 적는 기록(REPRO 줄)** 을 함께 남긴다.

var results := []
var _skips := 0          # 창 단독 검사에서 skipped 신호가 난 횟수
var _picks: Array = []   # 창 단독 검사에서 picked 신호로 온 key

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 판정이 아니라 서술. 재현이 됐는지 안 됐는지를 있는 그대로 남긴다
func repro(line: String) -> void:
	print("REPRO " + line)

func _init() -> void:
	call_deferred("_run")

# ---------- 트리 도우미 ----------
func _all_buttons(node: Node, out: Array) -> Array:
	if node is Button:
		var b := node as Button
		if not b.disabled:
			out.append(String(b.text))
	for ch in node.get_children():
		_all_buttons(ch, out)
	return out

func _vis_enabled_button(node: Node, part: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and String((node as Button).text).find(part) >= 0 and not (node as Button).disabled:
		return node as Button
	for ch in node.get_children():
		var f := _vis_enabled_button(ch, part)
		if f != null:
			return f
	return null

## 보이고 눌리는 **아무** 버튼(글자를 가리지 않는다).
## 주의: Godot의 String.find("")는 -1이라 빈 문자열을 needle로 준 '아무 버튼' 검색은 항상 실패한다.
## 그 함정 때문에 실제로는 버튼이 있는 화면을 '갇혔다'로 잘못 읽었다(2026-09-09).
func _any_enabled_button(node: Node) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and not (node as Button).disabled:
		return node as Button
	for ch in node.get_children():
		var f := _any_enabled_button(ch)
		if f != null:
			return f
	return null

## 글자가 정확히 같은 버튼(부분 일치로 '제시 재선택권'·'선택하기'를 잘못 집지 않게)
func _button_exact(node: Node, text: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and String((node as Button).text) == text and not (node as Button).disabled:
		return node as Button
	for ch in node.get_children():
		var f := _button_exact(ch, text)
		if f != null:
			return f
	return null

## 보이는 글자에 needle이 몇 번 나오는가(숨은 층은 세지 않는다)
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
	for ch in node.get_children():
		n += _vis_text(ch, needle)
	return n

## text_needle을 담은 **가장 작은 부분트리** 안의 버튼(카드가 여러 장일 때 원하는 카드의 버튼을 집는다)
func _card_button(node: Node, text_needle: String, btn_needle: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if _vis_text(node, text_needle) == 0:
		return null
	for ch in node.get_children():
		var b := _card_button(ch, text_needle, btn_needle)
		if b != null:
			return b
	return _vis_enabled_button(node, btn_needle)

## 버튼이 하나도 없는 화면을 만났을 때 **왜 그런지**를 남긴다(원인 없이 '갇혔다'만 적지 않는다)
func _why_dead(main: Node, scr: Node) -> String:
	var parts := []
	parts.append("보임=%s" % str((scr as Control).is_visible_in_tree()))
	parts.append("모든 버튼(비활성 포함)=%s" % str(_all_buttons_any(scr, [])))
	if main.screen == "reward":
		parts.append("last_reward 비었나=%s" % str((main.last_reward as Dictionary).is_empty()))
		if main.view != null and main.view.st != null:
			parts.append("전투 상태 status=%s duel_type='%s' duel_stage='%s' settled='%s'" % [String(main.view.st.status), String(main.view.st.duel_type), String(main.view.st.duel_stage), String(main.view.st.settled)])
	if main.screen == "event":
		var s: Dictionary = main.sortie
		var ev = s.get("event", null) if not s.is_empty() else null
		parts.append("sortie 비었나=%s · event=%s" % [str(s.is_empty()), (str(ev) if ev != null else "없음")])
		if ev != null:
			var names := []
			for o in PEvents.options(main.run, s):
				names.append("%s(%s)" % [String(o.id), str(bool(o.enabled))])
			parts.append("선택지=%s" % str(names))
	return " · ".join(parts)

func _all_buttons_any(node: Node, out: Array) -> Array:
	if node is Button:
		out.append("%s%s" % [String((node as Button).text), ("[비활성]" if (node as Button).disabled else ("[숨김]" if not (node as Button).is_visible_in_tree() else ""))])
	for ch in node.get_children():
		_all_buttons_any(ch, out)
	return out

## 3택 창에서 **나갈 수 있는 조작**: 카드 고르기 또는 건너뛰기·받지 않음·계속.
## '내 빌드 보기'·'상세 보기'는 창을 닫지 않으므로 여기에 넣지 않는다
func _exit_button(ov: Node) -> Button:
	for t in ["계속", "받지 않음"]:
		var b := _button_exact(ov, t)
		if b != null:
			return b
	var sk := _vis_enabled_button(ov, "건너뛰기")
	if sk != null:
		return sk
	return _button_exact(ov, "선택")

func _on_skip_signal() -> void:
	_skips += 1

func _on_pick_signal(k: String) -> void:
	_picks.append(k)

# =========================================================================
func _run() -> void:
	PSave.clear()
	var run := PRun.new_run(7, "sword")

	# ---------- ① 창 단독: 탈출구를 **눌러서** 신호가 실제로 나는지 ----------
	var ov := PChoiceOverlay.new()
	root.add_child(ov)
	await process_frame
	ov.skipped.connect(_on_skip_signal)
	ov.picked.connect(_on_pick_signal)
	for pool in ["level", "boss", "mission", "deep", "새로_생긴_이름"]:
		ov.open(run, { "pool": pool, "choices": [] })
		var texts := _all_buttons(ov, [])
		var btn := _exit_button(ov)
		var before := _skips
		if btn != null:
			btn.pressed.emit()
		ok("① 후보가 비어도 **눌러서** 나가는 조작이 실제로 동작한다 — pool=%s" % pool,
			btn != null and _skips == before + 1 and ov.has_exit(),
			"누른 버튼 '%s' · 붙어 있던 버튼 %s" % [(String(btn.text) if btn != null else "없음"), str(texts)])
	# '내 빌드 보기'만으로는 나갈 길이 아니다 — 눌러도 신호가 나지 않는다
	ov.open(run, { "pool": "boss", "choices": [] })
	var build_btn := _vis_enabled_button(ov, "내 빌드 보기")
	var s0 := _skips
	if build_btn != null:
		build_btn.pressed.emit()
	ok("① '내 빌드 보기'는 눌러도 나가지지 않는다(탈출구로 세지 않는 이유)",
		build_btn != null and _skips == s0, "skips %d → %d" % [s0, _skips])
	# 후보가 있으면 카드의 '선택'이 나갈 길이다 — 눌러서 picked 신호와 key를 확인한다
	var off0 := PGrowth.generate_offer(run, { "pool": "level", "region_id": "" })
	var keys0: Array = []
	for c in (off0.get("choices", []) as Array):
		keys0.append(String(c.key))
	ov.open(run, off0)
	var pick_btn := _button_exact(ov, "선택")
	_picks.clear()
	if pick_btn != null:
		pick_btn.pressed.emit()
	ok("① 후보가 있으면 카드의 '선택'을 눌러 picked 신호가 실제 후보 key로 난다",
		pick_btn != null and _picks.size() == 1 and keys0.has(String(_picks[0])),
		"신호 %s · 후보 %s" % [str(_picks), str(keys0)])
	ov.queue_free()
	await process_frame

	# ---------- ② 실제 화면 경로(main.tscn): 눌러서 창이 닫히고 흐름이 이어진다 ----------
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.new_run_opts = { "seed": 4021 }   # 시드 고정(시간 기반 시드로 흔들리지 않게)
	main.start_run("sword")
	await process_frame
	main.run.cards = null
	main.start_sortie_card(String(PSortie.cards_for(main.run)[0].id))
	await process_frame
	main.view.running = false               # 규칙 진행은 검사가 직접 한다(사람·봇 조작 아님)
	main.view.st.intro = 0.0
	ok("② 전투 화면에 들어와 있다", main.screen == "combat" and main.view.st != null, "screen=%s" % main.screen)

	# ②-1 전투 중 레벨업 3택: 카드를 눌러 창이 닫히고 전투가 재개되는가
	main.run.growth.pendingLevelUps = 1
	var off1 = PFlow.next_offer(main.run)
	main.open_choice(off1)
	await process_frame
	ok("②-1 3택이 열리면 전투 입력 관문이 잠긴다(view.paused)", main.choice.is_open() and main.view.paused,
		"open=%s paused=%s" % [str(main.choice.is_open()), str(main.view.paused)])
	var lv_before := int(main.run.growth.level)
	var picks_before := int((main.run.growth.log as Array).size())
	var pb := _button_exact(main.choice, "선택")
	if pb != null:
		pb.pressed.emit()
	await process_frame
	ok("②-1 카드를 **눌러서** 창이 닫히고 전투가 재개된다(입력 관문 해제)",
		pb != null and not main.choice.is_open() and not main.view.paused and main.screen == "combat",
		"open=%s paused=%s screen=%s" % [str(main.choice.is_open()), str(main.view.paused), main.screen])
	ok("②-1 선택이 실제로 적용됐다(성장 기록이 늘고 pendingOffer가 풀린다)",
		int((main.run.growth.log as Array).size()) == picks_before + 1 and main.run.growth.get("pendingOffer", null) == null,
		"기록 %d → %d · lv %d" % [picks_before, int((main.run.growth.log as Array).size()), lv_before])

	# ②-2 미처리 레벨업이 남아 있으면 **다음 3택이 이어서 뜬다**(닫고 끝이 아니다)
	main.run.growth.pendingLevelUps = 2
	main.open_choice(PFlow.next_offer(main.run))
	await process_frame
	var pb2 := _button_exact(main.choice, "선택")
	var had2 := pb2 != null    # 누른 뒤에는 창을 다시 그리며 버튼이 해제되므로 미리 적어 둔다
	if pb2 != null:
		pb2.pressed.emit()
	await process_frame
	ok("②-2 남은 레벨업이 있으면 누른 뒤 **다음 3택이 이어서 열린다**",
		had2 and main.choice.is_open() and int(main.run.growth.pendingLevelUps) >= 1,
		"open=%s 남은 %d" % [str(main.choice.is_open()), int(main.run.growth.pendingLevelUps)])
	# ②-3 '건너뛰기'도 실제로 나가진다(금화가 들어오고 전투가 재개된다)
	var gold_before := int(main.run.gold)
	var skip_btn := _vis_enabled_button(main.choice, "건너뛰기")
	if skip_btn != null:
		skip_btn.pressed.emit()
	await process_frame
	main.run.growth.pendingLevelUps = 0
	if main.choice.is_open():
		var c2 := _exit_button(main.choice)
		if c2 != null:
			c2.pressed.emit()
		await process_frame
	ok("②-3 '건너뛰기'를 눌러 창이 닫히고 금화가 들어온다",
		skip_btn != null and int(main.run.gold) > gold_before and not main.choice.is_open(),
		"금화 %d → %d · open=%s" % [gold_before, int(main.run.gold), str(main.choice.is_open())])

	# ②-4 **후보가 빈 3택**(사용자 증상의 화면)을 실제 전투 위에 띄우고 눌러서 빠져나온다
	main.open_choice({ "pool": "boss", "choices": [] })
	await process_frame
	ok("②-4 후보가 빈 창도 전투 입력을 막는다(그래서 탈출구가 없으면 갇힌다)",
		main.choice.is_open() and main.view.paused)
	var cont := _exit_button(main.choice)
	if cont != null:
		cont.pressed.emit()
	await process_frame
	ok("②-4 후보가 비어도 **눌러서** 창이 닫히고 전투 입력 관문이 풀린다",
		cont != null and not main.choice.is_open() and not main.view.paused and main.screen == "combat",
		"누른 버튼 '%s' · open=%s paused=%s" % [(String(cont.text) if cont != null else "없음"), str(main.choice.is_open()), str(main.view.paused)])
	# ②-5 창이 뜬 채로 남는 옛 결함: 제안이 아예 빈 사전이어도 창은 닫혀야 한다
	main.open_choice({})
	await process_frame
	ok("②-5 빈 사전은 애초에 창이 열리지 않는다", not main.choice.is_open())

	# ---------- ③ 증상 재현: 포로 구출 → 보상 → 계속 → 다음 진행 ----------
	var r1 := await _play_mission(main, "rescue")
	repro("포로 구출(rescue): %s" % String(r1.text))
	ok("③ 포로 구출 완료 뒤 보상·3택을 지나 다음 진행까지 **버튼만으로** 도달한다",
		bool(r1.reached), String(r1.text))
	var r2 := await _play_mission(main, "seal")
	repro("봉인 해제(seal): %s" % String(r2.text))
	ok("③ 봉인 해제 완료 뒤에도 보상·3택을 지나 다음 진행까지 도달한다",
		bool(r2.reached), String(r2.text))
	# 사용자가 말한 순서 그대로: 포로 구출을 끝낸 **그 회차에서 이어서** 봉인 임무를 나간다
	var r3 := await _play_two_missions(main)
	repro("포로 구출 → 이어서 봉인: %s" % String(r3.text))
	ok("③ 포로 구출 **다음에 봉인 임무**로 이어져도 갇히지 않는다", bool(r3.reached), String(r3.text))

	# ③-4 **실제로 재현된 잠김의 회귀 검사.**
	# 임무 전투(포로 구출·봉인 해제)에 특수 정예 결투가 배정되면 status="won"인데 duel_stage가 "normal"로 남고,
	# PFlow.settle_victory가 정산을 거부한다(전투 규칙 쪽 승리 판정 문제 — 이 담당 범위 밖).
	# 그때 보상 화면은 **아무것도 그리지 않아 버튼이 0개**가 된다 = 사람이 보고한 "아무것도 누를 수 없는 상태".
	# 여기서 못박는 것: 그 화면으로 보내지 않는다 · 그리고 **조용히 폐기하지 않고 기록을 남긴다.**
	main.new_run_opts = { "seed": 4021 }
	main.start_run("sword")
	await process_frame
	main.run.cards = null
	main.start_sortie_card(String(PSortie.cards_for(main.run)[0].id))
	await process_frame
	main.view.running = false
	var st4: CombatState = main.view.st
	st4.duel_type = "elite_archer"     # 결투가 배정된 카드의 실제 상태를 그대로 재현(상태 주입)
	st4.duel_stage = "normal"
	st4.status = "won"
	st4.player.hp = 50.0
	var fails0 := int(main.run.get("settleFailures", 0))
	main._on_finished(st4.summary())
	await process_frame
	var dead_screen: bool = main.screen == "reward" and (main.last_reward as Dictionary).is_empty()
	ok("③-4 정산이 거부돼도 **버튼 0개인 보상 화면**으로 보내지 않는다",
		not dead_screen and main.screen == "base" and _any_enabled_button(main.screens["base"]) != null,
		"screen=%s · last_reward 비었나=%s" % [main.screen, str((main.last_reward as Dictionary).is_empty())])
	ok("③-4 사라진 보상을 **조용히 폐기하지 않는다**(회차 기록 + 실패 회수)",
		int(main.run.get("settleFailures", 0)) == fails0 + 1 and str(main.run.get("log", [])).contains("전투 정산 실패"),
		"실패 %d → %d · 기록=%s" % [fails0, int(main.run.get("settleFailures", 0)), str(main.run.get("log", []))])

	# ---------- ④ 빈 후보의 사유: 정상 소진 / 생성 오류 / 미정의 pool ----------
	# ④-1 정상 소진: 보스 희귀 보상을 전부 받은 상태 → 조용히 '계속'이 맞다(오류 기록 없음)
	var runx := PRun.new_run(3, "sword")
	var gx: Dictionary = runx.growth
	for id in PCatalog.boss_rewards():
		(gx.bossRewards as Array).append(String(id))
	var offx := PGrowth.generate_offer(runx, { "pool": "boss" })
	ok("④-1 정상 소진: 빈 후보에 사유 'exhausted'가 실려 온다",
		(offx.choices as Array).is_empty() and String(offx.get("reason", "")) == "exhausted" and String(offx.get("reasonText", "")) != "",
		"reason=%s · %s" % [String(offx.get("reason", "")), String(offx.get("reasonText", ""))])
	ok("④-1 정상 소진은 오류로 세지 않는다(offerErrors 0, 회차 기록에 '생성 오류' 없음)",
		int(gx.get("offerErrors", 0)) == 0 and int(gx.get("offerExhausted", 0)) == 1
		and not str(runx.get("log", [])).contains("생성 오류"),
		"errors=%d exhausted=%d" % [int(gx.get("offerErrors", 0)), int(gx.get("offerExhausted", 0))])
	# ④-2 생성 오류: 모르는 보상 종류를 요청 → 조용히 폐기하지 않고 기록을 남긴다
	var rune := PRun.new_run(3, "sword")
	var ge: Dictionary = rune.growth
	var offe := PGrowth.generate_offer(rune, { "pool": "mission", "kinds": ["없는_보상_종류"], "missionKind": "없는_보상_종류", "region_id": "" })
	ok("④-2 생성 오류: 빈 후보에 사유 'error'가 실리고 무엇이 잘못됐는지 적힌다",
		(offe.choices as Array).is_empty() and String(offe.get("reason", "")) == "error"
		and String(offe.get("reasonText", "")).contains("없는_보상_종류"),
		"reason=%s · %s" % [String(offe.get("reason", "")), String(offe.get("reasonText", ""))])
	ok("④-2 생성 오류는 **회차 기록과 회수**에 남는다(조용한 폐기 아님)",
		int(ge.get("offerErrors", 0)) == 1 and str(rune.get("log", [])).contains("보상 후보 생성 오류")
		and (ge.get("offerErrorLog", []) as Array).size() == 1,
		"errors=%d log=%s" % [int(ge.get("offerErrors", 0)), str(rune.get("log", []))])
	# ④-3 화면은 그 이유를 사람 말 한 줄로 보인다
	var ov2 := PChoiceOverlay.new()
	root.add_child(ov2)
	await process_frame
	ov2.open(rune, offe)
	ok("④-3 화면이 생성 오류 사유를 한 줄로 보인다",
		String(ov2.note()).contains("생성 오류") and _vis_text(ov2, "없는_보상_종류") > 0, String(ov2.note()))
	ov2.open(runx, offx)
	ok("④-3 정상 소진은 오류 표시 없이 사유만 보인다",
		String(ov2.note()) != "" and not String(ov2.note()).contains("생성 오류"), String(ov2.note()))
	# ④-4 미정의 pool: 기록을 남기고, 그래도 나갈 길은 있다
	var runp := PRun.new_run(3, "sword")
	ov2.open(runp, { "pool": "낯선_보상_종류", "choices": [] })
	var pexit := _exit_button(ov2)
	ok("④-4 미정의 pool은 **기록을 남긴다**(회차 기록 + 화면 한 줄)",
		String(ov2.note()).contains("낯선_보상_종류") and str(runp.get("log", [])).contains("알 수 없는 보상 종류"),
		"note=%s log=%s" % [String(ov2.note()), str(runp.get("log", []))])
	ok("④-4 미정의 pool이어도 나갈 길은 남는다(모바일에서 갇히지 않는다)",
		pexit != null and ov2.has_exit(), "버튼 %s" % str(_all_buttons(ov2, [])))
	ov2.queue_free()

	main.queue_free()
	await process_frame
	PSave.clear()
	var pass_n := results.filter(func(x): return bool(x[0])).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(1 if pass_n != results.size() else 0)

# =========================================================================
# ③ 재현 장치: 임무 카드 하나를 실제 버튼으로 출격 → 전투 → 보상 → 3택 → 다음 진행
# =========================================================================

## 어떤 시드·날짜에 그 목표의 카드가 **실제로 나갈 수 있는 상태로** 생기는지 규칙에게 물어본다.
## 카드를 손으로 만들지 않는다. 관문 날·시간 부족으로 버튼이 꺼져 있으면 그 날은 세지 않는다
func _startable_day(r: Dictionary, day: int, objective: String) -> String:
	r.day = day
	r.hours = 5
	r.phase = "prep"
	r.cards = null
	if PRun.is_boss_day(r):
		return ""
	for c in PSortie.cards_for(r):
		if String(c.objective) == objective and PSortie.can_start(r, c):
			return String(c.id)
	return ""

func _find_card(objective: String) -> Dictionary:
	for s in range(1, 200):
		var r := PRun.new_run(s, "sword")
		for d in range(2, 10):
			var cid := _startable_day(r, d, objective)
			if cid != "":
				return { "seed": s, "day": d, "cardId": cid }
	return {}

## 한 회차 안에서 **포로 구출 → (나중 날) 봉인**을 둘 다 실제로 나갈 수 있는 시드를 찾는다
func _find_pair() -> Dictionary:
	for s in range(1, 200):
		var r := PRun.new_run(s, "sword")
		for d1 in range(2, 9):
			if _startable_day(r, d1, "rescue") == "":
				continue
			for d2 in range(d1 + 1, 10):
				if _startable_day(r, d2, "seal") != "":
					return { "seed": s, "rescueDay": d1, "sealDay": d2 }
			break
	return {}

## 그 목표의 임무를 실제로 나갈 수 있는 상태의 회차를 만든다(카드는 규칙이 만든 그대로)
func _setup_run(main: Node, objective: String) -> Dictionary:
	var found := _find_card(objective)
	if found.is_empty():
		return {}
	main.new_run_opts = { "seed": int(found.seed) }
	main.start_run("sword")
	await process_frame
	main.sortie = {}
	main.run.day = int(found.day)
	main.run.hours = 5
	main.run.phase = "prep"
	main.run.cards = null
	# 봇이 임무를 끝낼 만한 빌드(승패 자체는 이 검사의 목적이 아니다 — 승리 **뒤의 흐름**을 본다)
	main.run.growth.weapons = [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "blades", "level": 3, "mods": ["dual"] }]
	main.run.hp = float(PBuild.derive(main.run).hp_max)
	main.show("base")
	await process_frame
	return found

## 전투를 끝낸다. 봇이 이기면 "bot", 못 이기면 상태 주입으로 승리시키고 "inject"를 돌려준다
func _finish_fight(main: Node) -> String:
	main.view.bot = PBot.new("skilled")
	var frames := 0
	while main.view.st != null and String(main.view.st.status) == "running" and frames < 60 * 240:
		main.view._process(1.0 / 60.0)
		frames += 1
	if main.view.st == null:
		return "lost"
	if String(main.view.st.status) != "won":
		# 봇이 못 이겼다. 이 검사는 승패가 아니라 **승리 뒤 화면 흐름**을 보므로 상태 주입으로 승리시킨다.
		# (사람·봇의 승리 주장이 아니다 — 보고서에 그대로 적는다)
		main.view.running = false
		main.view.st.status = "won"
		main.view.st.player.hp = maxf(1.0, float(main.view.st.player.hp))
		main.view.st.mark_duel_done_for_test()
		main._on_finished(main.view.st.summary())
		return "inject"
	var wait := 0
	while main.screen == "combat" and wait < 60 * 20:
		main.view._process(1.0 / 60.0)
		if wait % 6 == 0:
			await process_frame
		wait += 1
	return "bot"

## 전투 뒤부터 거점까지 **화면의 버튼만 눌러서** 간다. 막히면 어디서 왜 막혔는지 문자열로 돌려준다
func _walk_to_base(main: Node) -> Dictionary:
	var trail := []
	var last := ""
	var same := 0
	for step in 40:
		await process_frame
		if main.screen == "base":
			return { "stuck": "", "trail": trail }
		var here := ""
		var btn: Button = null
		if main.choice != null and main.choice.is_open():
			here = "3택(%s, 후보 %d)" % [String(main.choice.offer.get("pool", "?")), (main.choice.offer.get("choices", []) as Array).size()]
			btn = _exit_button(main.choice)
			if btn == null:
				return { "stuck": "%s 창에 누를 수 있는 조작이 하나도 없다(버튼: %s)" % [here, str(_all_buttons(main.choice, []))], "trail": trail }
		else:
			here = main.screen
			var scr = main.screens.get(main.screen, null)
			if scr == null:
				return { "stuck": "알 수 없는 화면 %s" % main.screen, "trail": trail }
			for t in ["귀환", "계속", "받지 않음", "떠난다", "듣지 않는다", "지나친다", "확인"]:
				btn = _vis_enabled_button(scr, t)
				if btn != null:
					break
			if btn == null:
				btn = _any_enabled_button(scr)
			if btn == null:
				return { "stuck": "%s 화면에서 누를 버튼이 없다 · %s" % [main.screen, _why_dead(main, scr)], "trail": trail }
		trail.append("%s → [%s]" % [here, String(btn.text)])
		if here == last:
			same += 1
			if same >= 6:
				return { "stuck": "%s에서 같은 자리를 6번 눌러도 진행되지 않는다" % here, "trail": trail }
		else:
			same = 0
			last = here
		btn.pressed.emit()
	return { "stuck": "40번 눌러도 거점에 못 갔다(마지막 화면 %s)" % main.screen, "trail": trail }

## 목표 하나를 처음부터 끝까지: 출격 버튼 → 전투 → 보상 → 3택 → 거점
func _play_mission(main: Node, objective: String) -> Dictionary:
	var found: Dictionary = await _setup_run(main, objective)
	if found.is_empty():
		return { "reached": false, "text": "%s 목표의 카드를 어떤 시드에서도 못 찾았다" % objective }
	var obj_name := PSortie.objective_name(objective)
	var go := _card_button(main.screens["base"], obj_name, "출격 (")
	if go == null:
		return { "reached": false, "text": "거점에서 '%s' 카드의 출격 버튼을 못 찾았다(seed %d, %d일차)" % [obj_name, int(found.seed), int(found.day)] }
	go.pressed.emit()
	await process_frame
	if main.screen != "combat":
		return { "reached": false, "text": "출격을 눌렀는데 전투로 안 갔다(screen=%s)" % main.screen }
	var how: String = await _finish_fight(main)
	if how == "lost":
		return { "reached": false, "text": "전투 상태가 사라졌다" }
	var w: Dictionary = await _walk_to_base(main)
	var sf := int(main.run.get("settleFailures", 0))
	var head := "seed %d, %d일차 %s · 승리 경로 %s%s" % [int(found.seed), int(found.day), obj_name,
		("실제 봇 승리" if how == "bot" else "상태 주입 승리(봇이 못 이김)"),
		(" · **정산 거부 %d회(보상 지급 안 됨, 기록 남김)**" % sf) if sf > 0 else ""]
	if String(w.stuck) != "":
		return { "reached": false, "text": "%s · **갇힘**: %s · 지나온 자리 %s" % [head, String(w.stuck), str(w.trail)] }
	return { "reached": true, "text": "%s · 갇히지 않음 · 지나온 자리 %s" % [head, str(w.trail)] }

## 사용자가 말한 순서: 포로 구출을 끝낸 **같은 회차에서 이어서** 봉인 임무를 나간다
func _play_two_missions(main: Node) -> Dictionary:
	var pair := _find_pair()
	if pair.is_empty():
		return { "reached": false, "text": "한 회차에서 포로 구출 → 봉인을 둘 다 나갈 수 있는 시드를 못 찾았다" }
	main.new_run_opts = { "seed": int(pair.seed) }
	main.start_run("sword")
	await process_frame
	main.sortie = {}
	main.run.day = int(pair.rescueDay)
	main.run.hours = 5
	main.run.phase = "prep"
	main.run.cards = null
	main.run.growth.weapons = [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "blades", "level": 3, "mods": ["dual"] }]
	main.run.hp = float(PBuild.derive(main.run).hp_max)
	main.show("base")
	await process_frame
	var go := _card_button(main.screens["base"], PSortie.objective_name("rescue"), "출격 (")
	if go == null:
		return { "reached": false, "text": "포로 구출 카드의 출격 버튼을 못 찾았다(seed %d, %d일차)" % [int(pair.seed), int(pair.rescueDay)] }
	go.pressed.emit()
	await process_frame
	var how1: String = await _finish_fight(main)
	var w1: Dictionary = await _walk_to_base(main)
	if String(w1.stuck) != "":
		return { "reached": false, "text": "포로 구출 뒤에 **갇힘**: %s · %s" % [String(w1.stuck), str(w1.trail)] }
	# 같은 회차 그대로 봉인 임무 날짜로 넘어간다(회차·성장·보류 상태는 그대로 이어진다)
	main.run.day = int(pair.sealDay)
	main.run.hours = 5
	main.run.phase = "prep"
	main.run.cards = null
	main.run.hp = float(PBuild.derive(main.run).hp_max)
	main.show("base")
	await process_frame
	var seal_name := PSortie.objective_name("seal")
	var go2 := _card_button(main.screens["base"], seal_name, "출격 (")
	if go2 == null:
		return { "reached": false, "text": "포로 구출 뒤 같은 회차에서 봉인 카드의 출격 버튼을 못 찾았다(seed %d, %d일차) · 앞 단계는 통과: %s" % [int(pair.seed), int(pair.sealDay), str(w1.trail)] }
	go2.pressed.emit()
	await process_frame
	if main.screen != "combat":
		return { "reached": false, "text": "봉인 임무 출격을 눌렀는데 전투로 안 갔다(screen=%s)" % main.screen }
	var how2: String = await _finish_fight(main)
	var w2: Dictionary = await _walk_to_base(main)
	var head := "포로 구출(%s) → 봉인(%s)" % [how1, how2]
	if String(w2.stuck) != "":
		return { "reached": false, "text": "%s · 봉인 뒤 **갇힘**: %s · %s" % [head, String(w2.stuck), str(w2.trail)] }
	return { "reached": true, "text": "%s · 두 번 다 갇히지 않음 · %s / %s" % [head, str(w1.trail), str(w2.trail)] }
