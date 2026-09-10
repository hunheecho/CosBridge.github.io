extends SceneTree
## 기술 편성 화면을 **실제 버튼으로** 끝까지 눌러 보는 검사(main.tscn 인스턴스).
## 실행: python tools/run_suites.py --suites bank_ui_tests --jobs 1
## 캡처까지 남기려면 창을 띄우고 돌린다:
##   PROPHECY_EQUIP_SKILL_DEMO=1 PROPHECY_BANK_SHOTS=1 <godot> --path prophecy_godot -s tests/bank_ui_tests.gd
##   (헤드리스에서는 그림이 없으므로 캡처를 건너뛴다 — 단언은 그대로 돈다.)
##
## 규칙 함수를 직접 부르지 않는다. 거점 → 기술 편성 → 장비 → 다시 기술 편성을 **버튼을 눌러** 오간다.
## 시작 상태(Q 감속장 Lv3·변형, E 낙뢰 Lv2)만 상태 주입이다 — 레벨업 3택을 여기서 다시 확인하지 않기 때문이다.
## 그렇게 표기한다: 승리·성장 주장이 아니라 **편성 조작의 출발선**이다.

var results := []
var shots := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

# ---------- 화면에서 실제로 보이는 버튼·글자 ----------
func btn(node: Node, part: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and (node as Button).text.find(part) >= 0 and not (node as Button).disabled:
		return node as Button
	for ch in node.get_children():
		var f := btn(ch, part)
		if f != null:
			return f
	return null

## 글자가 **정확히** 같은 버튼(이동용 버튼을 고를 때. "장비"는 "장비 기술은 창고에..."에도 들어 있다)
func btn_exact(node: Node, text: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and (node as Button).text == text and not (node as Button).disabled:
		return node as Button
	for ch in node.get_children():
		var f := btn_exact(ch, text)
		if f != null:
			return f
	return null

## 보이지만 **눌리지 않는** 버튼도 찾는다(중복 배치 금지가 실제로 잠겨 있는지 볼 때)
func btn_any(node: Node, part: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and (node as Button).text.find(part) >= 0:
		return node as Button
	for ch in node.get_children():
		var f := btn_any(ch, part)
		if f != null:
			return f
	return null

func txt(node: Node, needle: String) -> int:
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
		n += txt(c, needle)
	return n

func shot(name: String) -> void:
	if OS.get_environment("PROPHECY_BANK_SHOTS") == "" or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://docs/captures")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/bank_%02d_%s.png" % [dir, shots, name])
	shots += 1
	print("SHOT ", name)

func _run() -> void:
	OS.set_environment(PCatalog.DEMO_EQUIP_ENV, "1") # 시험용 장비(코드 안 정의)를 켠다
	PCatalog.reset()
	# **안전 장치.** 이 검사는 user://의 회차 저장을 지우고 다시 쓴다. 격리된 APPDATA가 아니면
	# 사람이 진행 중인 회차를 덮어쓴다 — 실제로 2026-09-10에 그 사고를 냈다(창을 띄워 돌리다가).
	# tools/run_suites.py는 스위트마다 APPDATA를 따로 준다(userdata__<스위트>__...).
	# 그 표시가 없으면 아무것도 건드리지 않고 끝낸다.
	var udir := OS.get_user_data_dir()
	if udir.find("userdata__") < 0 and udir.find("prophecy_test_runs") < 0:
		printerr("격리되지 않은 저장 폴더에서는 돌리지 않는다(사람 저장을 덮어쓴다): %s" % udir)
		printerr("python tools/run_suites.py --suites bank_ui_tests --jobs 1 로 돌리거나, APPDATA를 임시 폴더로 두고 돌려라.")
		quit(3)
		return
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.new_run_opts = { "seed": 4021 } # 시드 고정(시간 기반 시드로 흔들리지 않게)
	main.start_run("sword")
	await process_frame
	# 상태 주입(출발선): Q 감속장 Lv3·변형 '동행하는 시간' · E 낙뢰 Lv2
	main.run.growth.skills.q = { "id": "slowfield", "level": 3, "variant": "follow" }
	main.run.growth.skills.e = { "id": "strike", "level": 2, "variant": null }
	main.show("base")
	await process_frame

	print("\n[1] 거점 → 기술 편성 (버튼)")
	var open_b: Button = btn(main.screens["base"], "기술 편성")
	ok("거점에 '기술 편성' 버튼이 있고 눌린다", open_b != null)
	if open_b == null:
		return _finish()
	open_b.pressed.emit()
	await process_frame
	ok("기술 편성 화면이 열린다", main.screen == "skillbank", main.screen)
	var sb: Node = main.screens["skillbank"]
	ok("Q 감속장 Lv3 · E 낙뢰가 화면에 보이고 창고는 비어 있다",
		txt(sb, "Lv3 / 3") >= 1 and txt(sb, "낙뢰") >= 1 and txt(sb, "비어 있음") >= 1)
	await shot("01_start")

	print("\n[2] 시험용 장비를 받아 실제로 착용한다 (버튼)")
	var demo_b: Button = btn(sb, "시험용 각인검")
	ok("시험 전용 버튼이 보인다(PROPHECY_EQUIP_SKILL_DEMO=1일 때만)", demo_b != null)
	if demo_b == null:
		return _finish()
	demo_b.pressed.emit()
	await process_frame
	ok("가방에 시험용 각인검이 들어왔다", (main.run.bag as Array).size() == 1)
	btn_exact(main.screens["skillbank"], "장비").pressed.emit()
	await process_frame
	var eq: Node = main.screens["equip"]
	btn(eq, "선택").pressed.emit()
	await process_frame
	ok("장비 창에 '장비 기술 · 찰나 가르기'와 '착용 중일 때만 사용'이 적혀 있다",
		txt(eq, "찰나 가르기") >= 1 and txt(eq, "착용 중일 때만") >= 1)
	var wear: Button = btn(eq, "지금 장착")
	ok("'지금 장착' 버튼이 눌린다", wear != null)
	if wear == null:
		return _finish()
	wear.pressed.emit()
	await process_frame
	ok("착용했다 · 그래도 Q·E는 그대로다(착용 ≠ 배치)",
		String(main.run.equipment.weapon).begins_with("demo_flashcut_blade")
		and String(main.run.growth.skills.q.id) == "slowfield" and String(main.run.growth.skills.e.id) == "strike")

	print("\n[3] 검증 4) Q에 장비 기술을 배치 → 감속장 Lv3·변형이 창고로")
	btn(eq, "기술 편성").pressed.emit()
	await process_frame
	sb = main.screens["skillbank"]
	ok("장비 기술 칸에 '찰나 가르기 · 장비 기술 · 성장 없음'이 보인다",
		txt(sb, "찰나 가르기") >= 1 and txt(sb, "장비 기술 · 성장 없음") >= 1)
	var place_q: Button = btn(sb, "Q에 배치")
	ok("'Q에 배치' 버튼이 눌린다", place_q != null)
	if place_q == null:
		return _finish()
	place_q.pressed.emit()
	await process_frame
	sb = main.screens["skillbank"]
	var be := PGrowth.bank_entry(main.run.growth, "slowfield")
	ok("Q가 찰나 가르기가 되고 감속장은 **Lv3·변형 그대로 창고에** 있다",
		String(main.run.growth.skills.q.id) == "eq_flashcut" and int(be.get("level", 0)) == 3 and String(be.get("variant", "")) == "follow",
		str(be))
	ok("창고 칸에 '감속장 Lv3'이 실제로 보인다", txt(sb, "Lv3") >= 1 and txt(sb, "기술 창고") >= 1)
	ok("장비 기술에는 'Lv1/3' 같은 성장 표시를 붙이지 않는다", txt(sb, "Lv1 / 3") == 0)
	ok("같은 장비 기술을 E에도 넣는 버튼은 잠겨 있다(중복 배치 금지)",
		btn(sb, "E에 배치") == null and btn_any(sb, "Q에 배치됨") != null)
	await shot("02_equip_skill_in_q")

	print("\n[4] 검증 6) Q와 E 맞바꾸기 (버튼)")
	btn(sb, "Q와 E 맞바꾸기").pressed.emit()
	await process_frame
	sb = main.screens["skillbank"]
	var b_sw: Dictionary = PBuild.derive(main.run)
	ok("맞바꾼 뒤 Q=낙뢰 Lv2(8초) · E=찰나 가르기(8초) — 표시와 재사용이 새 배치와 일치",
		String(main.run.growth.skills.q.id) == "strike" and String(main.run.growth.skills.e.id) == "eq_flashcut"
		and is_equal_approx(float(b_sw.special_cd), 8.0) and is_equal_approx(PBuildDetail.cd_of_build(b_sw, "e"), 8.0),
		"%s / %s" % [str(b_sw.special_cd), str(PBuildDetail.cd_of_build(b_sw, "e"))])
	btn(sb, "Q와 E 맞바꾸기").pressed.emit() # 원래대로 되돌린다
	await process_frame
	sb = main.screens["skillbank"]

	print("\n[5] 검증 5) 장비 해제 → 사용 불가 → 창고에서 직접 꺼내 다시 쓴다 (버튼)")
	btn_exact(sb, "장비").pressed.emit()
	await process_frame
	eq = main.screens["equip"]
	btn(eq, "선택").pressed.emit()
	await process_frame
	btn(eq, "해제").pressed.emit()
	await process_frame
	var b_off: Dictionary = PBuild.derive(main.run)
	ok("벗으면 전투에서 Q를 쓸 수 없다(빌드의 Q가 비고 재사용 0) · 배치는 그대로 남는다",
		b_off.skills.q == null and is_equal_approx(float(b_off.special_cd), 0.0)
		and String(main.run.growth.skills.q.id) == "eq_flashcut")
	btn(main.screens["equip"], "기술 편성").pressed.emit()
	await process_frame
	sb = main.screens["skillbank"]
	ok("화면이 '지금 사용 불가'라고 말한다(조용히 지우지 않는다)", txt(sb, "지금 사용 불가") >= 1)
	ok("창고의 감속장 Lv3은 그대로 있고 자동으로 들어가지 않았다",
		txt(sb, "Lv3") >= 1 and String(main.run.growth.skills.q.id) == "eq_flashcut")
	await shot("03_equip_removed")
	var take: Button = btn(sb, "Q에 넣기")
	ok("창고의 '감속장 Q에 넣기' 버튼이 눌린다", take != null)
	if take == null:
		return _finish()
	take.pressed.emit()
	await process_frame
	sb = main.screens["skillbank"]
	var b_back: Dictionary = PBuild.derive(main.run)
	ok("다시 꺼내면 Lv3·변형이 복구되고 재사용도 10초로 돌아온다",
		String(main.run.growth.skills.q.id) == "slowfield" and int(main.run.growth.skills.q.level) == 3
		and String(main.run.growth.skills.q.variant) == "follow" and is_equal_approx(float(b_back.special_cd), 10.0),
		str(b_back.special_cd))
	ok("장비 기술은 창고에 남지 않았다(일반 스킬로 복제되지 않는다)",
		not PGrowth.in_bank(main.run.growth, "eq_flashcut") and PGrowth.bank_ro(main.run.growth).is_empty())
	await shot("04_restored")

	print("\n[6] 검증 7) 저장 → 이어하기 뒤 편성 보존")
	# 다시 착용하고 장비 기술을 E에 둔 채 저장한다
	btn_exact(sb, "장비").pressed.emit()
	await process_frame
	btn(main.screens["equip"], "선택").pressed.emit()
	await process_frame
	btn(main.screens["equip"], "지금 장착").pressed.emit()
	await process_frame
	btn(main.screens["equip"], "기술 편성").pressed.emit()
	await process_frame
	btn(main.screens["skillbank"], "E에 배치").pressed.emit()
	await process_frame
	main.save_run()
	var disk := PSave.load()
	var db := PGrowth.bank_ro(disk.growth)
	ok("저장 파일에 창고(낙뢰 Lv2)와 Q/E 배치가 그대로 들어 있다",
		String(disk.growth.skills.q.id) == "slowfield" and int(disk.growth.skills.q.level) == 3
		and String(disk.growth.skills.e.id) == "eq_flashcut"
		and db.size() == 1 and String(db[0].id) == "strike" and int(db[0].level) == 2,
		"%s / %s" % [str(disk.growth.skills.e), str(db)])
	main.go_title()
	await process_frame
	main.continue_run()
	await process_frame
	main.show("skillbank")
	await process_frame
	sb = main.screens["skillbank"]
	ok("이어하기 뒤 화면에도 같은 편성·창고가 보인다",
		String(main.run.growth.skills.e.id) == "eq_flashcut" and txt(sb, "낙뢰") >= 1 and txt(sb, "기술 창고") >= 1)
	await shot("05_reloaded")
	_finish()

func _finish() -> void:
	var pass_n := 0
	for row in results:
		if bool(row[0]):
			pass_n += 1
	print("\n%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
