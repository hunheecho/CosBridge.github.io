extends SceneTree
## 배치 확인 캡처(창 필요, headless 아님): 창 크기(--resolution WxH)별로 거점·빌드 상세·툴팁·상점·3택·전투(사람 경로, 입력 없음)·일시정지 화면을 PNG로 저장하고
## 넘침(가로 스크롤 필요 여부·HUD 오른쪽 끝)을 LAYOUT_CHECK 줄로 출력한다. PROPHECY_TOUCH=1이면 전투 화면에 터치 오버레이가 그려진다.
## 실행(APPDATA 격리): PROPHECY_SHOTS=<폴더> godot --path prophecy_godot --resolution 1280x720 -s tools/layout_shots.gd
## 화면 함수를 스크립트가 부르는 것이지 사람 입력이 아니다(PORT_NOTES §12-4와 같은 구분).

var dir := ""
var tag := ""
var fails := 0

func _init() -> void:
	call_deferred("_run")

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(dir.path_join("%s_%s.png" % [tag, name]))
	print("LAYOUT_SHOT ", tag, " ", name, " ", img.get_width(), "x", img.get_height())

## 화면(PScreen)의 본문이 가로로 넘치지 않는지: 스크롤 안 본문의 최소 너비 ≤ 스크롤 너비
func _check_screen(main: Node, name: String) -> void:
	var s = main.screens[main.screen]
	var need: float = s.body.get_combined_minimum_size().x
	var have: float = s.scroll.size.x
	var top_need: float = s.top.get_combined_minimum_size().x
	var top_have: float = s.top.size.x
	var okv: bool = need <= have + 0.5 and top_need <= top_have + 0.5
	if not okv:
		fails += 1
	print("LAYOUT_CHECK ", tag, " ", name, " ok=", okv, " body_min=", int(need), "/", int(have), " top_min=", int(top_need), "/", int(top_have))

func _check_hud(main: Node) -> void:
	var vis: Rect2 = root.get_visible_rect()
	var obj: Control = main.hud.get_node("Objective")
	var stg: Control = main.hud.get_node("Settings")
	var bar: Control = main.hud.get_node("Bar")
	var okv: bool = obj.offset_right <= vis.end.x and stg.offset_bottom <= vis.end.y and bar.offset_right >= vis.end.x - 0.5 and main.view.position.x >= 0.0
	if not okv:
		fails += 1
	print("LAYOUT_CHECK ", tag, " hud ok=", okv, " objective_right=", obj.offset_right, " canvas=", vis.size, " view_pos=", main.view.position)

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	dir = OS.get_environment("PROPHECY_SHOTS")
	if dir == "":
		dir = OS.get_user_data_dir().path_join("layout_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await _wait(3)
	var ws: Vector2i = DisplayServer.window_get_size()
	tag = "%dx%d" % [ws.x, ws.y]
	print("LAYOUT window=", ws, " canvas=", root.get_visible_rect().size, " bucket=", PLayout.bucket_of(root), " safe=", PLayout.safe_rect(root), " touch=", PLayout.is_touch())
	_snap("00_title")
	_check_screen(main, "title")
	main.start_run("sword")
	await _wait(3)
	_snap("10_base")
	_check_screen(main, "base")
	var base = main.screens["base"]
	base._toggle_build_detail()
	await _wait(2)
	_snap("10b_base_detail")
	_check_screen(main, "base_detail")
	base._toggle_build_detail()
	await _wait(1)
	main.tips._on_click("auto_skill")
	await _wait(2)
	_snap("10c_base_tooltip")
	main.tips.close_all()
	main.show("shop")
	await _wait(2)
	_snap("14_shop")
	_check_screen(main, "shop")
	main.show("equip")
	await _wait(2)
	_snap("16_equip")
	_check_screen(main, "equip")
	main.go_base()
	main.run.growth.pendingLevelUps = 1
	main.open_choice(PFlow.next_offer(main.run))
	await _wait(2)
	_snap("13_choice")
	main.choice.close()
	main.run.growth.pendingLevelUps = 0
	main.go_base()
	await _wait(1)
	base._open_endday()
	await _wait(2)
	_snap("18a_endday_confirm")
	base.on_escape()
	main.start_fight(false) # 기준 전투, 사람 입력 경로(입력은 없음) → PROPHECY_TOUCH=1이면 오버레이 표시
	await _wait(90)
	_snap("11_combat")
	_check_hud(main)
	main.set_pause(true)
	await _wait(2)
	_snap("21_pause")
	main.set_pause(false)
	# 세로 안내막(회전 뒤 '계속' + '전체화면으로 다시 들어가기'). 표시만 켠다 — 실제 회전이 아니라 그리기 확인용
	main.orient.apply(false, true, true)
	await _wait(2)
	_snap("22_orient_veil")
	main.orient.apply(false, false, true)
	await _wait(1)
	main.view.running = false
	main.go_title()
	await _wait(1)
	print("LAYOUT_DONE ", tag, " fails=", fails)
	main.queue_free()
	await _wait(1)
	PSave.clear()
	quit(0 if fails == 0 else 1)
