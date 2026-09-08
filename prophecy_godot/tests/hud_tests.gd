extends SceneTree
## 전투 HUD·아이콘 매핑 시험(headless, 실제 main.tscn 인스턴스).
## 실행: python tools/run_suites.py --suites hud_tests (APPDATA·LOCALAPPDATA를 격리해 준다)
##
## 확인하는 것
##  A. ID→아이콘 매핑이 실제 게임 데이터 ID와 맞는지, 누락 목록이 기계 판독 형태로 나오는지(다른 효과 아이콘 재사용이 없는지)
##  B. 전장 HUD가 조작 아이콘 Space/Q/E 3칸 + 상단 체력만 남기는지(자동기술·개조·공용·패시브·장비는 전장에 없다)
##  C. 조작 아이콘의 4가지 상태 구분(미보유 / 사용 불가 / 재사용 대기 = 흑백+남은 초 / 준비됨)
##  D. 준비 완료 신호가 false→true 1회만 나고 일시정지·화면 재구성·불러오기·새 전투에 다시 나지 않는지
##  E. 전체 빌드는 일시정지의 '내 빌드'(PBuildDetail)에서 볼 수 있는지(자동기술·개조·Q/E·공용·패시브·장비)
##  F. 3택: 내 빌드 보기 · 상세를 열고 닫아도 재추첨·자동 선택·전투 재개가 없는지 · 재사용 시간 전/후 표시(계산식은 상세)
##  G. 전투 결과 화면에 크고 분명한 '계속' 버튼이 있고 세부 통계가 접혀 있는지
##  H. 창 크기를 바꿔도 HUD가 목표 표시·상단 띠·화면 가장자리를 가리지 않는지
##  I. 표시 계층이 전투 결과를 바꾸지 않는지(같은 시드 · HUD 갱신 유무로 결과 동일, st.rng 미사용)
## 키보드·마우스 입력 합성은 하지 않는다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

## 기준 전투 설정(자동 로드 Game 없이 — 헤드리스 -s 시험 경로)
func _cfg() -> Dictionary:
	return preload("res://scripts/game/game.gd").load_config()

# ---------- 트리 검사 도우미 ----------
func _count_text(node: Node, needle: String) -> int:
	var n := 0
	if node is RichTextLabel and String((node as RichTextLabel).text).find(needle) >= 0:
		n += 1
	if node is Label and String((node as Label).text).find(needle) >= 0:
		n += 1
	if node is Button and String((node as Button).text).find(needle) >= 0:
		n += 1
	for c in node.get_children():
		n += _count_text(c, needle)
	return n

func _find_button(node: Node, needle: String) -> Button:
	if node is Button and String((node as Button).text).find(needle) >= 0:
		return node as Button
	for c in node.get_children():
		var b := _find_button(c, needle)
		if b != null:
			return b
	return null

## 하위 트리의 PIconTile을 style별로 센다
func _tiles_by_style(node: Node, out: Dictionary) -> void:
	if node is PIconTile:
		var k := int((node as PIconTile).style)
		out[k] = int(out.get(k, 0)) + 1
	for c in node.get_children():
		_tiles_by_style(c, out)

func _run() -> void:
	PSave.clear()
	# ---------- A. 아이콘 매핑·누락 목록 ----------
	var cov := PIcons.coverage()
	var have: Array = cov.have
	var missing: Array = cov.missing
	ok("아이콘 표 로드: 임시 20종이 모두 실제 게임 ID로 매핑됨", (PIcons.data().map as Dictionary).size() == 20 and have.size() == 20, "map=%d have=%d" % [(PIcons.data().map as Dictionary).size(), have.size()])
	var W := PCatalog.weapons()
	var all_w := true
	for wid in W:
		if not PIcons.has(PIcons.weapon_key(String(wid))):
			all_w = false
	ok("자동기술 10종 전부 아이콘 있음", all_w and W.size() == 10, "weapons=%d" % W.size())
	var main_mods := [["sword", "cross"], ["sword", "scar"], ["spear", "split"], ["spear", "returning"], ["frost", "fan"], ["frost", "shatter"]]
	var all_m := true
	for pair in main_mods:
		if not PIcons.has(PIcons.mod_key(String(pair[0]), String(pair[1]))):
			all_m = false
	ok("주요 개조 6종(교차·잔류·분열·귀환·부채·수정) 아이콘 있음", all_m)
	ok("회피·Q 감속장·E 수호 결계·공용 메아리 아이콘 있음", PIcons.has("action:dodge") and PIcons.has("skill:slowfield") and PIcons.has("skill:q") and PIcons.has("skill:e:ward") and PIcons.has("common:echo"))
	# 서로 다른 ID가 같은 그림 파일을 가리키면 오인이 생긴다(별칭으로 같은 효과를 가리키는 것은 정상)
	var files := {}
	var dup := ""
	for k in PIcons.data().map:
		var f := String(PIcons.data().map[k].file)
		if files.has(f):
			dup = f
		files[f] = k
	ok("한 그림 파일이 두 효과에 배정되지 않음(오인 금지)", dup == "", dup)
	# 아이콘이 없는 ID는 has()=false여야 하고, 이름은 카탈로그의 실제 한국어 이름이어야 한다
	var no_icon_ok: bool = not PIcons.has(PIcons.mod_key("sword", "crescent")) and PIcons.name_of(PIcons.mod_key("sword", "crescent")) == String(W.sword.mods.crescent.name)
	ok("미제작 개조는 아이콘 없음 + 실제 이름 반환(다른 아이콘 대체 안 함)", no_icon_ok, PIcons.name_of(PIcons.mod_key("sword", "crescent")))
	var missing_named := true
	for m in missing:
		if String(m.name) == "" or String(m.name) == String(m.key):
			missing_named = false
	ok("누락 목록이 기계 판독 형태(키·종류·실제 이름) %d건" % missing.size(), missing.size() > 0 and missing_named, "예: " + (str(missing[0]) if missing.size() > 0 else "-"))
	ok("누락 목록 문서 생성(docs/sim/ICON_COVERAGE.md)", PIcons.write_coverage_doc())
	# 흑백 아이콘은 같은 그림에서 만든다(다른 그림으로 바꾸지 않는다)
	var gray := PIcons.texture_gray("skill:slowfield", true)
	ok("재사용 대기용 흑백 아이콘이 같은 키에서 만들어짐(없는 키는 null)", gray != null and PIcons.texture_gray("mod:sword:crescent", true) == null)

	# ---------- 화면 계층 준비 ----------
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	# 저장된 실제 빌드: 자동기술 2개(검 Lv2 + 교차/잔류, 관통창 Lv1 + 분열) + 장비 + E
	main.start_run("sword")
	var g: Dictionary = main.run.growth
	g.weapons = [{ "id": "sword", "level": 2, "mods": ["cross", "scar"] }, { "id": "spear", "level": 1, "mods": ["split"] }]
	g.skills.e = { "id": "ward", "level": 1, "variant": null }
	g.commons.echo = 1
	main.run.bag = ["guardian_armor"]
	PRun.equip_item(main.run, "guardian_armor")
	main.save_run()
	main.run.cards = null
	main.start_sortie_card(String(PSortie.cards_for(main.run)[0].id))
	main.view.running = false      # 규칙 진행은 시험이 직접 한다(사람·봇 조작 아님)
	main.view.st.intro = 0.0
	var st: CombatState = main.view.st
	main._update_hud()
	main._layout_hud()
	await process_frame
	var hud: PCombatHud = main.build_hud
	ok("HUD 인스턴스가 전투 화면에 붙어 있음", hud != null and hud.is_inside_tree() and main.screen == "combat")

	# ---------- B. 전장 HUD = 조작 아이콘 3칸 + 상단 체력만 ----------
	var styles := {}
	_tiles_by_style(hud, styles)
	var only_manual: bool = int(styles.get(PIconTile.STYLE_MANUAL, 0)) == 3 and int(styles.get(PIconTile.STYLE_AUTO, 0)) == 0 and int(styles.get(PIconTile.STYLE_MOD, 0)) == 0 and int(styles.get(PIconTile.STYLE_EQUIP, 0)) == 0 and int(styles.get(PIconTile.STYLE_SMALL, 0)) == 0
	ok("전장 HUD에는 조작 아이콘 3칸만(자동기술·개조·공용/패시브·장비 칸 없음)", only_manual, str(styles))
	ok("남은 3칸이 Space · Q · E", hud.manual_tile("dodge") != null and hud.manual_tile("q") != null and hud.manual_tile("e") != null and hud.manual_tile("dodge").key_label == "Space" and hud.manual_tile("q").key_label == "Q" and hud.manual_tile("e").key_label == "E")
	ok("전장 HUD에 자동기술·장비 이름이 글자로도 남지 않음", _count_text(hud, "빈 슬롯") == 0 and _count_text(hud, "장비") == 0 and _count_text(hud, "공용") == 0)
	# 상단 체력: 옛 막대·글자는 숨기고 빨간 막대 + 큰 숫자로 다시 그린다. 보호막은 따로 표시
	var hp_node: Control = main.get_node("UI/HUD/HP")
	var sh_node: Control = main.get_node("UI/HUD/Shield")
	var hptext: Control = main.get_node("UI/HUD/HPText")
	st.player.shield = 18.0
	st.player.shield_max = 30.0
	main._update_hud()
	var health = hud._health
	ok("옛 상단 체력 막대·글자는 숨김(보호막 막대까지)", not hp_node.visible and not sh_node.visible and not hptext.visible)
	ok("새 체력 표시: 체력과 보호막을 분리해 들고 있다", health != null and is_equal_approx(float(health.hp), float(st.player.hp)) and is_equal_approx(float(health.shield), 18.0) and bool(health.has_shield()), "hp=%s shield=%s" % [str(health.hp), str(health.shield)])
	st.player.shield = 0.0
	main._update_hud()
	ok("보호막이 0이면 보호막 표시가 사라진다(체력 감소와 혼동 없음)", not bool(health.has_shield()))

	# ---------- C. 조작 아이콘 4가지 상태 ----------
	st.player.dodge_cd = 0.0
	st.player.special_cd = 2.5
	main._update_hud()
	var qt: PIconTile = hud.manual_tile("q")
	var dt: PIconTile = hud.manual_tile("dodge")
	var et: PIconTile = hud.manual_tile("e")
	ok("준비됨 = ready(컬러) · 재사용 대기 = cooldown", hud.ability_state("dodge") == PIconTile.ST_READY and hud.ability_state("q") == PIconTile.ST_COOLDOWN, "dodge=%s q=%s" % [hud.ability_state("dodge"), hud.ability_state("q")])
	ok("재사용 대기 중에는 흑백 + 남은 초, 준비됨은 컬러", qt.is_gray() and is_equal_approx(qt.cd_left, 2.5) and qt.cd_ratio > 0.0 and not dt.is_gray() and dt.cd_left <= 0.0)
	ok("준비됨은 짧은 테두리 점등만(계속 깜박이지 않음)", dt.flash_k() >= 0.0 and dt.state == PIconTile.ST_READY)
	# 사용 불가: 규칙이 실제로 입력을 받지 않는 동안(등장 연출). 미보유·재사용 대기와 다른 표시여야 한다
	var fired_pre := []
	hud.ready_signal.connect(func(a: String): fired_pre.append(a))
	st.intro = 1.0
	main._update_hud()
	ok("등장 연출 중에는 사용 불가(unusable) — 미보유·재사용 대기와 다른 상태", hud.ability_state("dodge") == PIconTile.ST_UNUSABLE and hud.ability_state("q") == PIconTile.ST_UNUSABLE, "dodge=%s q=%s" % [hud.ability_state("dodge"), hud.ability_state("q")])
	st.intro = 0.0
	main._update_hud()
	ok("연출이 끝나도 준비 소리는 나지 않는다(재사용 대기 종료만 알린다)", fired_pre.is_empty() and hud.ability_state("dodge") == PIconTile.ST_READY, str(fired_pre))
	# 미보유 E: 빌드에서 E를 빼고 다시 그린다
	var e_backup = st.build.skills.e
	st.build.skills.e = null
	main._update_hud()
	ok("E 미보유 → state = none, 빈 칸 + '미보유'", hud.ability_state("e") == PIconTile.ST_NONE and et.empty and et.title == "미보유", hud.ability_state("e"))
	st.build.skills.e = e_backup
	st.player.e_cd = 0.0
	main._update_hud()
	ok("E 보유 시 아이콘·이름 표시 + 준비됨", et.key == "skill:e:ward" and et.title == String(PCatalog.skills().ward.name) and hud.ability_state("e") == PIconTile.ST_READY, et.key)

	# ---------- 개조 점등은 실제 이벤트 시각으로만(자체 타이머 없음) ----------
	st.t = 5.0
	st.note_mod("cross", "proc")
	var proc_t: float = float(st.mod_stats.cross.last_proc_t)
	var probe := PIconTile.new("mod:sword:cross", PIconTile.STYLE_MOD)
	probe.now_t = 5.0
	probe.flash_t = proc_t
	ok("개조 점등은 st.mod_stats.last_proc_t 기준", is_equal_approx(proc_t, 5.0) and probe.flash_k() > 0.0)
	probe.now_t = 5.0 + PIconTile.FLASH_DUR + 0.05
	ok("점등은 1회로 끝난다(반복 점멸 없음)", probe.flash_k() == 0.0)
	probe.free()
	var rep := st.mod_report()
	var bd0 := PBuildDetail.new()
	var dash_ok: bool = bd0._mod_stat_text("split", rep).find("—") >= 0 and bd0._mod_stat_text("cross", rep).find("발동 [b]1[/b]") >= 0
	bd0.free()
	ok("개조 통계: 발동 1·적중 0을 구분하고, 기록 없는 개조는 0이 아니라 '—'", int(rep.cross.procs) == 1 and int(rep.cross.hits) == 0 and not rep.has("split") and dash_ok)

	# ---------- D. 준비 완료 신호: false→true 1회 ----------
	var fired := []
	hud.ready_signal.connect(func(a: String): fired.append(a))
	st.player.dodge_cd = 1.0
	st.player.special_cd = 1.0
	st.player.e_cd = 1.0
	hud.sync_ready_silent(st)      # 새 전투·복구와 같은 경로: 현재값으로 조용히 맞춘다
	main._update_hud()
	ok("대기 중 상태 동기화에서는 신호 없음", fired.is_empty() and not bool(hud.ready_state().dodge))
	st.player.dodge_cd = 0.0
	main._update_hud()
	ok("회피 재사용 대기 종료(false→true) → 신호 1회", fired == ["dodge"], str(fired))
	main._update_hud()
	main._update_hud()
	ok("계속 준비 상태여도 신호는 다시 나지 않음", fired == ["dodge"], str(fired))
	main.set_pause(true)
	main._update_hud()
	main.set_pause(false)
	main._update_hud()
	ok("일시정지·재개로 준비 알림이 다시 터지지 않음", fired == ["dodge"], str(fired))
	main._layout_hud()
	hud.relayout(PLayout.safe_rect(main.get_viewport()))
	main._update_hud()
	ok("화면 재배치(HUD 재구성)로도 다시 터지지 않음", fired == ["dodge"], str(fired))
	main.show("combat")            # 화면 진입 = sync_ready_silent 경로
	main._update_hud()
	ok("화면 다시 열기(저장 복구와 같은 경로)로도 다시 터지지 않음", fired == ["dodge"], str(fired))
	st.player.special_cd = 0.0
	main._update_hud()
	ok("Q가 준비되면 Q 신호가 따로 1회", fired == ["dodge", "q"], str(fired))
	ok("능력마다 다른 소리 이름", String(PCombatHud.READY_SOUND.dodge) != String(PCombatHud.READY_SOUND.q) and String(PCombatHud.READY_SOUND.q) != String(PCombatHud.READY_SOUND.e))
	# 다른 전투(새 CombatState)로 바뀌어도, 이미 준비된 기술에 알림이 터지지 않는다
	var fired_n := fired.size()
	var st2 := CombatState.first_fight(_cfg(), 7)
	st2.intro = 0.0
	hud.update_from(st2)
	hud.update_from(st2)
	ok("새 전투 상태로 바뀌어도 준비 알림이 터지지 않음(저장 복구 포함)", fired.size() == fired_n, str(fired))
	hud.update_from(st)
	# 소리를 꺼도 읽을 수 있어야 한다: 남은 초 + 가림막
	st.player.special_cd = 2.5
	main._update_hud()
	ok("소리 없이도 읽힘: 쿨다운 가림막 비율 + 남은 초 표시", qt.cd_ratio > 0.0 and is_equal_approx(qt.cd_left, 2.5))

	# ---------- E. 전체 빌드 = 일시정지의 '내 빌드' ----------
	main.set_pause(true)
	var pause_build_btn := _find_button(main.get_node("UI/Pause"), "빌드")
	ok("일시정지 화면에 '내 빌드'를 여는 버튼이 있다(마우스·터치 경로)", pause_build_btn != null, "" if pause_build_btn == null else pause_build_btn.text)
	main.set_pause(false)
	main.view.running = true       # 전투가 진행 중인 상태에서 열어 '안전한 일시정지'를 확인한다
	main.open_build_detail()
	var bd: PBuildDetail = main.build_detail
	var bstyles := {}
	_tiles_by_style(bd, bstyles)
	ok("'내 빌드'가 열리고 전투가 안전하게 멈춘다", bd.is_open() and bool(main.view.paused))
	ok("'내 빌드'에 자동기술·개조·수동(Q/E)·장비 칸이 모두 있다", int(bstyles.get(PIconTile.STYLE_AUTO, 0)) >= 2 and int(bstyles.get(PIconTile.STYLE_MOD, 0)) >= 3 and int(bstyles.get(PIconTile.STYLE_MANUAL, 0)) >= 3 and int(bstyles.get(PIconTile.STYLE_EQUIP, 0)) == 3, str(bstyles))
	ok("'내 빌드'에 공용 증강·패시브가 기술 개조와 구분된 항목으로 있다", _count_text(bd, "공용 증강") >= 1 and _count_text(bd, String(PCatalog.commons().echo.name)) >= 1)
	ok("'내 빌드' 제목이 사용자 말('내 빌드')이고 개발자 설명이 없다", _count_text(bd, "내 빌드") >= 1 and _count_text(bd, "자동기술 슬롯과 다른 영역") == 0)
	ok("'내 빌드'가 Q/E 최종 재사용 시간을 적는다", _count_text(bd, "재사용") >= 1)
	# 개조별 이번 전투 숫자는 기본 접힘 → 눌러야 나온다
	var stat_btn := _find_button(bd, "이번 전투 기록 보기")
	ok("개조별 이번 전투 숫자는 기본 접힘(펼치는 버튼이 있다)", stat_btn != null and _count_text(bd, "발동 [b]") == 0)
	if stat_btn != null:
		stat_btn.pressed.emit()
		ok("펼치면 개조별 발동·적중·피해가 나온다", _count_text(bd, "발동") >= 1)
	bd.close()
	ok("'내 빌드'를 닫으면 전투가 이어진다(따로 재개 조작 필요 없음)", not bd.is_open() and not bool(main.view.paused))
	main.view.running = false
	await process_frame

	# ---------- F. 3택: 내 빌드 보기 · 상세 · 재추첨 없음 ----------
	main.run.growth.pendingLevelUps = 1
	var opened: bool = main.offer_pending_level_ups()
	await process_frame
	var ch: PChoiceOverlay = main.choice
	ok("전투 중 3택이 열리고 전투가 멈춘다", opened and ch.is_open() and bool(main.view.paused))
	var keys_before := []
	for c in ch.offer.choices:
		keys_before.append(String(c.key))
	var run_before := JSON.stringify(main.run)
	var save_before := JSON.stringify(PSave.load())
	var rng_before: int = int(st.rng._a)
	var step_before: int = st.step_n
	var t_before: float = st.t
	var build_btn := _find_button(ch, "내 빌드 보기")
	ok("3택 화면에 '내 빌드 보기'가 있다(선택 중에도 보유 빌드 확인)", build_btn != null)
	if build_btn != null:
		build_btn.pressed.emit()
		await process_frame
	var cstyles := {}
	_tiles_by_style(ch, cstyles)
	ok("펼친 내 빌드에 기술별 개조와 공용·패시브가 구분돼 보인다", _count_text(ch, "지금 내 빌드") >= 1 and _count_text(ch, "공용 증강 · 패시브") >= 1 and int(cstyles.get(PIconTile.STYLE_MOD, 0)) >= 3)
	var keys_mid := []
	for c in ch.offer.choices:
		keys_mid.append(String(c.key))
	ok("내 빌드를 펼쳐도 후보가 다시 뽑히지 않는다", keys_mid == keys_before, "%s vs %s" % [str(keys_before), str(keys_mid)])
	# 상세 열기 → 닫기: 같은 3택으로 돌아온다
	var det_btn := _find_button(ch, "상세 보기")
	ok("각 후보에 '상세 보기'가 있다(공식·단계는 여기로)", det_btn != null)
	if det_btn != null:
		det_btn.pressed.emit()
		await process_frame
	ok("상세를 펼쳐도 3택이 그대로 열려 있고 전투는 계속 멈춰 있다", ch.is_open() and bool(main.view.paused) and _count_text(ch, "상세 닫기") == 1)
	var close_det := _find_button(ch, "상세 닫기")
	if close_det != null:
		close_det.pressed.emit()
		await process_frame
	var keys_after := []
	for c in ch.offer.choices:
		keys_after.append(String(c.key))
	ok("상세를 보고 돌아와도 재추첨 없음(같은 후보 3장)", keys_after == keys_before, "%s vs %s" % [str(keys_before), str(keys_after)])
	ok("상세를 보고 돌아와도 자동 선택이 없다(회차·저장 그대로)", JSON.stringify(main.run) == run_before and JSON.stringify(PSave.load()) == save_before)
	ok("상세를 보고 돌아와도 전투가 재개되지 않는다(단계·시각·난수 그대로)", bool(main.view.paused) and st.step_n == step_before and is_equal_approx(st.t, t_before) and int(st.rng._a) == rng_before)
	ok("3택 기본 화면은 접혀 있다(카드마다 '상세 보기'만, 펼친 상세·계산식 없음)", _count_text(ch, "상세 보기") == (ch.offer.choices as Array).size() and _count_text(ch, "상세 닫기") == 0 and _count_text(ch, "계산식") == 0, "상세보기=%d" % _count_text(ch, "상세 보기"))
	# 쿨다운 표시: 최종 재사용 시간의 전/후만 크게, 계산식은 상세
	var q_choice := { "kind": "skill_level", "id": "slowfield", "slot": "q", "key": "test_q_level" }
	var cd := PChoiceOverlay.cd_change(main.run, q_choice)
	var b_now := PBuild.derive(main.run)
	var q_lv: int = int(main.run.growth.skills.q.level)
	var raw: Array = PCatalog.skills().slowfield.cooldown
	ok("선택 카드의 Q 재사용 전/후가 규칙이 낸 최종 값과 같다", not cd.is_empty() and is_equal_approx(float(cd.before), float(b_now.special_cd)) and float(cd.after) < float(cd.before), str(cd))
	ok("계산 규칙은 그대로 읽기만 한다(감속장 레벨별 기본 %s)" % str(raw), is_equal_approx(float(b_now.special_cd), maxf(1.0, float(raw[mini(3, q_lv) - 1]) * float(b_now.skill_cd_mult) * float(b_now.get("q_cd_mult", 1.0)))), "special_cd=%s" % str(b_now.special_cd))
	ok("계산식은 카드 상세에만 있다(기본 화면에는 전/후 숫자만)", String(cd.formula).find("×") >= 0 and _count_text(ch, "계산식") == 0)
	main.close_choice()
	main.run.growth.pendingLevelUps = 0
	await process_frame

	# ---------- H. 창 크기를 바꿔도 HUD·적 예고가 가리지 않는다 ----------
	# 경기장(적 예고를 그리는 곳)의 화면 위치는 main._layout_hud과 같은 식으로 구한다(창 크기를 실제로 바꾸지 않고 4종을 본다).
	var obj_l: Control = main.get_node("UI/HUD/Objective")
	var aw: float = float(main.view.st.arena_w)
	var ah: float = float(main.view.st.arena_h)
	var bad := []
	var cover := []
	for sz in [Vector2(960, 640), Vector2(1280, 640), Vector2(2340, 1080), Vector2(1024, 768)]:
		var safe := Rect2(Vector2.ZERO, sz)
		hud.relayout(safe)
		var mr: Rect2 = hud.manual_rect()
		var hr: Rect2 = hud.health_rect()
		var objr := Rect2(Vector2(obj_l.offset_left, obj_l.offset_top), Vector2(obj_l.offset_right - obj_l.offset_left, obj_l.offset_bottom - obj_l.offset_top))
		if mr.size.y > 0.0:
			if mr.intersects(objr) or mr.position.y < 40.0 or mr.end.y > safe.end.y or mr.end.x > safe.end.x:
				bad.append("조작 %s @%s" % [str(mr), str(sz)])
			if mr.size.y > 96.0:
				bad.append("조작 묶음이 너무 큼 %s @%s" % [str(mr.size), str(sz)])
		if hr.intersects(objr) or hr.end.y > 40.0 + 6.0:
			bad.append("체력 %s @%s" % [str(hr), str(sz)])
		# 경기장이 화면 밖으로 잘리면 가장자리의 예고를 못 본다
		var arena := Rect2(Vector2(round((sz.x - aw) / 2.0), round(40.0 + maxf(0.0, (sz.y - 40.0 - ah) / 2.0))), Vector2(aw, ah))
		if arena.position.x < 0.0 or arena.position.y < 0.0 or arena.end.x > sz.x or arena.end.y > sz.y:
			bad.append("경기장이 화면 밖 %s @%s" % [str(arena), str(sz)])
		# HUD가 경기장(=예고가 나오는 면)을 덮는 비율
		var area: float = arena.size.x * arena.size.y
		var covered := 0.0
		for r in [mr, hr]:
			var it: Rect2 = r.intersection(arena)
			if it.size.x > 0.0 and it.size.y > 0.0:
				covered += it.size.x * it.size.y
		var frac: float = covered / maxf(1.0, area)
		cover.append("%dx%d %.1f%%" % [int(sz.x), int(sz.y), frac * 100.0])
		if frac > 0.15:
			bad.append("HUD가 경기장의 %.1f%%를 덮음 @%s" % [frac * 100.0, str(sz)])
	ok("여러 창 크기에서 HUD가 목표 표시·상단 띠·화면 밖을 침범하지 않음", bad.is_empty(), "; ".join(bad))
	ok("화면 4종에서 경기장(적 예고 면)이 잘리지 않고 HUD가 덮는 비율이 15% 이내", bad.is_empty(), ", ".join(cover))
	hud.relayout(PLayout.safe_rect(main.get_viewport()))

	# ---------- G. 전투 결과 화면: 요약 곁의 큰 '계속' + 접힌 세부 통계 ----------
	main.view.running = false
	main.view.st.status = "won"
	main._on_finished(main.view.st.summary())
	await process_frame
	var rw: Node = main.screens["reward"]
	var cont := _find_button(rw, "계속")
	ok("전투 결과 화면이 열리고 크고 분명한 '계속' 버튼이 있다", main.screen == "reward" and cont != null and cont.get_theme_font_size("font_size") >= 18, "" if cont == null else "%s size=%d" % [cont.text, cont.get_theme_font_size("font_size")])
	var rs: PScreen = rw
	var in_scroll := false
	var n2: Node = cont
	while n2 != null and n2 != rw:
		if n2 == rs.scroll:
			in_scroll = true
		n2 = n2.get_parent()
	ok("'계속'은 요약 바로 아래에 있고, 스크롤 밖에도 같은 버튼이 있다", rs.default_button == cont and _count_text(rw, "계속") >= 2)
	ok("세부 통계는 기본 접힘(끝까지 내려야 진행하는 구조 없음)", _find_button(rw, "세부 통계 보기") != null and _find_button(rw, "세부 통계 닫기") == null and _count_text(rw, "피해 출처") == 0)
	var stat2 := _find_button(rw, "세부 통계 보기")
	if stat2 != null:
		stat2.pressed.emit()
		await process_frame
		ok("세부 통계를 펼쳐도 '계속' 버튼은 그대로 남는다", _find_button(rw, "세부 통계 닫기") != null and _find_button(rw, "계속") != null and _count_text(rw, "계속") >= 2)

	# ---------- I. 표시가 전투 결과를 바꾸지 않는다 ----------
	var plain := _sim(11, false, null)
	var with_hud := _sim(11, true, hud)
	ok("같은 시드: HUD를 매 프레임 갱신해도 전투 결과가 같다", JSON.stringify(plain) == JSON.stringify(with_hud), "kills %s vs %s" % [str(plain.kills), str(with_hud.kills)])
	ok("표시 계층(render·HUD·아이콘·화면)에 st.rng 사용 없음", _no_rng_in_display(), _rng_hits())
	# 미리보기는 회차·난수·저장을 바꾸지 않는다
	var off2 := PGrowth.generate_offer(main.run, { "pool": "level" })
	var before_run := JSON.stringify(main.run)
	var before_save := JSON.stringify(PSave.load())
	var lines := []
	for c in off2.choices:
		lines.append(PChoiceOverlay.preview_line(main.run, c))
		lines.append(PChoiceOverlay.icon_key(c))
		lines.append(str(PChoiceOverlay.cd_change(main.run, c)))
	var any_line := false
	for l in lines:
		if String(l) != "":
			any_line = true
	ok("선택 카드 미리보기·아이콘 키가 만들어짐", any_line and (off2.choices as Array).size() > 0)
	ok("미리보기 뒤 회차 상태 불변(경험치·성장·금화)", JSON.stringify(main.run) == before_run)
	ok("미리보기 뒤 저장 파일 불변", JSON.stringify(PSave.load()) == before_save)

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

## 같은 시드의 기준 전투를 봇으로 끝까지 진행한다. hud_on이면 매 프레임 HUD 표시 갱신을 함께 돌린다
## (표시 계층이 규칙에 끼어들지 않는지 = UI 변경 전후 결과가 같은지 확인하는 경로).
func _sim(seed_v: int, hud_on: bool, hud: PCombatHud) -> Dictionary:
	var st := CombatState.first_fight(_cfg(), seed_v)
	var bot := PBot.new()
	var n := 0
	while st.status == "running" and n < 120 * 120:
		st.step(bot.step_input(st), 1.0 / 120.0)
		if hud_on and hud != null and n % 4 == 0:
			hud.update_from(st)
		n += 1
	return st.summary()

## scripts/game/** 전부에서 전투 난수(st.rng / state.rng)를 쓰는 곳이 없어야 한다(표시가 규칙 난수를 소비하면 같은 입력이 달라진다)
const DISPLAY_DIRS := ["res://scripts/game", "res://scripts/game/ui", "res://scripts/game/screens"]

func _rng_hits() -> String:
	var hits := []
	for d in DISPLAY_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if not String(f).ends_with(".gd"):
				continue
			var fa := FileAccess.open(String(d) + "/" + String(f), FileAccess.READ)
			if fa == null:
				continue
			var text := fa.get_as_text()
			var n := 0
			for line in text.split("\n"):
				n += 1
				var s := String(line)
				if s.strip_edges().begins_with("#"):
					continue
				if s.find("st.rng") >= 0 or s.find("state.rng") >= 0 or s.find(".rng.") >= 0:
					hits.append("%s:%d" % [String(f), n])
	return ", ".join(hits)

func _no_rng_in_display() -> bool:
	return _rng_hits() == ""
