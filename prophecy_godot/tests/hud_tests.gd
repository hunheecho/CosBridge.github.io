extends SceneTree
## 전투 HUD·아이콘 매핑 시험(headless, 실제 main.tscn 인스턴스).
## 실행: APPDATA·LOCALAPPDATA를 별도 폴더로 두고 PROPHECY_LEGACY_PLACES=1 godot --headless --path prophecy_godot -s tests/hud_tests.gd
##
## 확인하는 것
##  A. ID→아이콘 매핑이 실제 게임 데이터 ID와 맞는지, 누락 목록이 기계 판독 형태로 나오는지(다른 효과 아이콘 재사용이 없는지)
##  B. HUD가 저장된 실제 빌드(자동기술 3 + 붙은 개조 + 장비)를 읽는지, 장비가 자동기술 칸과 분리돼 있는지
##  C. 개조 아이콘 점등이 st.mod_stats[...].last_proc_t로만 움직이는지(자체 타이머 없음)
##  D. 준비 완료 신호가 false→true 1회만 나고 일시정지·화면 재구성·불러오기에 다시 나지 않는지
##  E. 선택 미리보기가 회차·난수·저장을 건드리지 않는지
## 키보드·마우스 입력 합성은 하지 않는다. 전투 결과를 주장하지 않는다(상태 주입은 그렇게 표기).

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

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
	await process_frame
	var hud: PCombatHud = main.build_hud
	ok("HUD 인스턴스가 전투 화면에 붙어 있음", hud != null and hud.is_inside_tree() and main.screen == "combat")

	# ---------- B. HUD가 실제 저장 빌드를 읽는가 ----------
	var t0: PIconTile = hud._auto_tiles[0].tile
	var t1: PIconTile = hud._auto_tiles[1].tile
	var t2: PIconTile = hud._auto_tiles[2].tile
	ok("자동기술 1칸 = 검 Lv2 (아이콘 키·이름·레벨이 저장 빌드와 같음)", t0.key == "weapon:sword" and t0.title == String(PCatalog.weapon("sword").name) and t0.sub == "Lv2/%d" % int(PCatalog.growth().SLOTS.weaponMax) and not t0.empty, "%s %s %s" % [t0.key, t0.title, t0.sub])
	ok("자동기술 2칸 = 관통창 Lv1", t1.key == "weapon:spear" and not t1.empty, t1.key)
	ok("자동기술 3칸 = 아직 미보유 → 빈 테두리", t2.empty and t2.key == "")
	var m00: PIconTile = hud._auto_tiles[0].mods[0]
	var m01: PIconTile = hud._auto_tiles[0].mods[1]
	var m10: PIconTile = hud._auto_tiles[1].mods[0]
	var m11: PIconTile = hud._auto_tiles[1].mods[1]
	ok("검 밑의 개조 2칸 = 교차 검격 · 잔류 검흔(붙은 기술 아래에만)", m00.key == "mod:sword:cross" and m01.key == "mod:sword:scar")
	ok("관통창 밑 = 분열 창날 1개 + 빈 개조 칸 1개", m10.key == "mod:spear:split" and m11.empty and m11.key == "")
	# 공용 증강은 기술 칸에 복제되지 않는다
	var echo_in_mods := false
	for row in hud._auto_tiles:
		for mt in row.mods:
			if String((mt as PIconTile).key).begins_with("common:"):
				echo_in_mods = true
	ok("공용 증강(메아리)이 기술 개조 칸에 복제되지 않음", not echo_in_mods and hud._common_row.get_child_count() > 0)
	# 장비는 자동기술 칸과 다른 부모(별도 영역)
	var eq_tile: PIconTile = hud._equip_tiles[1].tile
	var eq_sep: bool = eq_tile.get_parent() != t0.get_parent() and eq_tile.get_parent() != hud._auto_row
	ok("장비 영역이 자동기술 칸과 분리(다른 부모 컨테이너·별도 배경)", eq_sep and String(hud._equip_tiles[1].slot) == "armor" and eq_tile.key == "equip:guardian_armor", eq_tile.key)
	ok("장착하지 않은 무기·방패 슬롯은 빈 칸(장비 무기 ≠ 자동기술 검)", (hud._equip_tiles[0].tile as PIconTile).empty and (hud._equip_tiles[2].tile as PIconTile).empty)
	var e_tile: PIconTile = hud._manual["e"]
	ok("E 보유 시 아이콘·이름 표시", not e_tile.empty and e_tile.key == "skill:e:ward" and e_tile.title == String(PCatalog.skills().ward.name), e_tile.key)

	# ---------- C. 개조 점등은 last_proc_t로만 ----------
	ok("발동 기록 전에는 개조 점등 없음", m00.flash_k() == 0.0 and float(st.mod_stats.get("cross", {}).get("last_proc_t", -1.0)) < 0.0)
	st.t = 5.0
	st.note_mod("cross", "proc")   # 실제 발동 기록(규칙이 하는 것과 같은 경로)
	main._update_hud()
	ok("발동 직후 그 개조 칸만 점등(교차 O · 잔류 X · 분열 X)", m00.flash_k() > 0.0 and m01.flash_k() == 0.0 and m10.flash_k() == 0.0, "cross=%.2f scar=%.2f split=%.2f" % [m00.flash_k(), m01.flash_k(), m10.flash_k()])
	ok("점등 세기가 last_proc_t 기준", is_equal_approx(m00.flash_t, 5.0) and is_equal_approx(m00.now_t, 5.0))
	st.t = 5.0 + PIconTile.FLASH_DUR + 0.05
	main._update_hud()
	ok("점등은 1회로 끝난다(반복 점멸 없음)", m00.flash_k() == 0.0)
	var rep := st.mod_report()
	var bd := PBuildDetail.new()
	var dash_ok: bool = bd._mod_stat_text("split", rep).find("—") >= 0 and bd._mod_stat_text("cross", rep).find("발동 [b]1[/b]") >= 0
	bd.free()
	ok("빌드 상세의 개조 통계: 발동 1·적중 0을 구분하고, 기록 없는 개조는 0이 아니라 '—'", int(rep.cross.procs) == 1 and int(rep.cross.hits) == 0 and not rep.has("split") and dash_ok)

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
	# 소리를 꺼도 읽을 수 있어야 한다: 남은 초 + 가림막
	st.player.special_cd = 2.5
	main._update_hud()
	var qt: PIconTile = hud._manual["q"]
	ok("소리 없이도 읽힘: 쿨다운 가림막 비율 + 남은 초 표시", qt.cd_ratio > 0.0 and is_equal_approx(qt.cd_left, 2.5))

	# ---------- E. 미리보기는 회차·난수·저장을 바꾸지 않는다 ----------
	var off := PGrowth.generate_offer(main.run, { "pool": "level" })
	var before_run := JSON.stringify(main.run)
	var before_save := JSON.stringify(PSave.load())
	var rng_before: int = int(st.rng._a) # mulberry32 내부 상태(소비되면 값이 바뀐다)
	var step_before: int = st.step_n
	var t_before: float = st.t
	var lines := []
	for c in off.choices:
		lines.append(PChoiceOverlay.preview_line(main.run, c))
		lines.append(PChoiceOverlay.icon_key(c))
	var any_line := false
	for l in lines:
		if String(l) != "":
			any_line = true
	ok("선택 카드 미리보기·아이콘 키가 만들어짐", any_line and (off.choices as Array).size() > 0)
	ok("미리보기 뒤 회차 상태 불변(경험치·성장·금화)", JSON.stringify(main.run) == before_run)
	ok("미리보기 뒤 저장 파일 불변", JSON.stringify(PSave.load()) == before_save)
	ok("미리보기가 전투를 진행시키지 않음(단계·시각 불변)", st.step_n == step_before and is_equal_approx(st.t, t_before))
	ok("미리보기가 전투 난수를 소비하지 않음", int(st.rng._a) == rng_before, "before=%d after=%d" % [rng_before, int(st.rng._a)])
	# 표시 코드가 전투 난수를 쓰지 않는지 원본에서도 확인한다
	ok("표시 계층(render·HUD·아이콘·화면)에 st.rng 사용 없음", _no_rng_in_display(), _rng_hits())

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
