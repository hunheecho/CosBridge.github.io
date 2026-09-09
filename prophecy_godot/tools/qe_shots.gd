extends SceneTree
## 수동 기술 Q/E 화면 확인 캡처(창 필요, headless 아님).
## 실제 화면의 **버튼 노드를 찾아 눌러** 시작 흐름(주무기 → 수동 기술 → Q Lv1)을 지나가고,
## 거점 빌드 패널·전투 HUD·장비 창(감속장 미보유 안내)까지 PNG로 남긴다.
## 화면 함수를 부르는 것이 아니라 **그 버튼에 실제로 묶인 콜백**을 발신한다(PORT_NOTES §12-4의 구분).
##
## 실행: PROPHECY_SHOTS=<폴더> godot --path prophecy_godot --resolution 1280x720 -s tools/qe_shots.gd

var dir := ""
var step := 0

func _init() -> void:
	call_deferred("_run")

func _snap(name: String) -> void:
	step += 1
	var img := root.get_texture().get_image()
	var path := dir.path_join("%02d_%s.png" % [step, name])
	img.save_png(path)
	print("QE_SHOT ", path, " ", img.get_width(), "x", img.get_height())

func _wait(n: int) -> void:
	for i in n:
		await process_frame

## 화면 안에서 글자가 들어간 버튼 하나(먼저 찾은 것)
func _btn(node: Node, needle: String) -> Button:
	if node is Button and String((node as Button).text).find(needle) >= 0:
		return node
	for c in node.get_children():
		var b := _btn(c, needle)
		if b != null:
			return b
	return null

func _texts(node: Node, needle: String) -> int:
	var n := 0
	if node is RichTextLabel and (node as RichTextLabel).get_parsed_text().find(needle) >= 0:
		n += 1
	if node is Label and String((node as Label).text).find(needle) >= 0:
		n += 1
	if node is Button and String((node as Button).text).find(needle) >= 0:
		n += 1
	for c in node.get_children():
		n += _texts(c, needle)
	return n

func _press(main: Node, needle: String) -> bool:
	var s = main.screens[main.screen]
	var b := _btn(s, needle)
	if b == null:
		print("QE_PRESS_FAIL ", needle, " (화면 ", main.screen, ")")
		return false
	b.pressed.emit()
	print("QE_PRESS ", needle)
	return true

func _run() -> void:
	dir = OS.get_environment("PROPHECY_SHOTS")
	if dir == "":
		dir = OS.get_user_data_dir().path_join("qe_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await _wait(3)

	# ---------- ① 주무기 선택 ----------
	main.new_run_flow()
	await _wait(3)
	print("QE_STATE screen=", main.screen)
	_snap("pick_weapon")
	print("QE_CHECK 1/2 표시 =", _texts(main.screens["pick_start"], "주무기 선택 (1/2)"),
		" 주무기버튼 =", _texts(main.screens["pick_start"], "이 주무기로 (다음)"))
	if not _press(main, "이 주무기로 (다음)"):
		quit(1)
		return
	await _wait(3)

	# ---------- ② 수동 기술 선택 ----------
	print("QE_STATE screen=", main.screen)
	_snap("pick_skill")
	var ps = main.screens["pick_start"]
	print("QE_CHECK 2/2 표시 =", _texts(ps, "수동 기술 선택 (2/2)"),
		" 기술버튼 =", _texts(ps, "이 기술로 시작"),
		" 감속장 =", _texts(ps, "감속장"), " 돌풍 =", _texts(ps, "돌풍"),
		" 후보 =", str(ps.start_skill_options()))
	# 되돌아가기(취소·뒤로)를 실제로 눌러 본다
	if _press(main, "주무기 다시 고르기"):
		await _wait(3)
		print("QE_CHECK 뒤로 → 1/2 표시 =", _texts(main.screens["pick_start"], "주무기 선택 (1/2)"), " 회차 시작됨 =", not main.run.is_empty())
		_snap("back_to_weapon")
		_press(main, "이 주무기로 (다음)")
		await _wait(3)

	# 감속장이 아닌 기술(돌풍)을 고른다 — 감속장을 강제로 주지 않는다는 것을 화면에서 본다
	ps = main.screens["pick_start"]
	var pick: Button = null
	for c in ps.body.get_children():
		for card in c.get_children():
			if _texts(card, "돌풍") > 0:
				pick = _btn(card, "이 기술로 시작")
	if pick == null:
		print("QE_PRESS_FAIL 돌풍 카드")
		quit(1)
		return
	pick.pressed.emit()
	print("QE_PRESS 돌풍 · 이 기술로 시작")
	await _wait(4)

	# ---------- ③ 거점: Q에 돌풍 Lv1 · E 비어 있음 ----------
	print("QE_STATE screen=", main.screen, " q=", main.run.growth.skills.q, " e=", main.run.growth.skills.get("e"))
	_snap("base_after_start")
	main.show("equip")
	await _wait(3)
	print("QE_CHECK 장비 화면 수동기술줄 Q =", _texts(main.screens["equip"], "Q"), " 보조무기 구분 =", _texts(main.screens["equip"], "보조"))
	_snap("equip_build_panel")

	# 감속장 미보유 안내: 시간술사의 지팡이를 가방에 넣고 창을 연다
	main.run.bag.append("chrono_staff")
	main.show("equip")
	await _wait(3)
	var eq = main.screens["equip"]
	eq._open_item("chrono_staff", true)
	await _wait(3)
	print("QE_CHECK 시간술사의 지팡이 '지금은 효과 없음' =", _texts(main.screens["equip"], "지금은 효과 없음"),
		" 사유 =", PGrowth.equip_inactive_reason(main.run.growth, "chrono_staff"))
	_snap("equip_inactive_note")
	main.screens["equip"].close_confirm()
	await _wait(2)

	# ---------- ④ 기준 전투(첫 전투)는 예전 그대로 Q 감속장이다(D33 보존 확인) ----------
	main.show("base")
	await _wait(2)
	main.use_bot = true
	main.start_fight(true)
	await _wait(60)
	print("QE_CHECK 기준 전투 HUD Q =", main.get_node("UI/HUD/QText").text)
	_snap("first_fight_hud")
	main.go_base()
	await _wait(3)

	# ---------- ⑤ 실제 출격 전투 HUD: Q가 돌풍으로 보인다 ----------
	main.use_bot = true
	if not _press(main, "출격 ("):
		print("QE_PRESS_FAIL 출격 버튼")
	await _wait(90)
	print("QE_STATE screen=", main.screen)
	if main.screen == "combat" and main.view != null and main.view.st != null:
		print("QE_CHECK 출격 HUD Q =", main.get_node("UI/HUD/QText").text, " / E =", main.get_node("UI/HUD/EText").text,
			" build.q =", main.view.st.build.skills.q)
	_snap("combat_hud_q_gust")

	# ---------- ⑥ E에 감속장을 넣어 본다(감속장도 E로) ----------
	if main.view != null and main.view.st != null:
		main.run.growth.skills.e = { "id": "slowfield", "level": 1, "variant": null }
		main.view.st.build = PRun.build(main.run)
		await _wait(30)
		print("QE_CHECK E에 감속장 · HUD Q =", main.get_node("UI/HUD/QText").text, " / E =", main.get_node("UI/HUD/EText").text)
		_snap("combat_hud_e_slowfield")
	print("QE_DONE")
	quit(0)
