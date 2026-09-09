extends SceneTree
## 주무기 1 + 보조 2를 가진 실제 실행 화면을 띄우고 거점 '현재 빌드'를 캡처한다
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.new_run_opts = { "seed": 4021 }
	main.start_run("hammer")
	# 실제 성장 경로로 보조 둘을 얻고 레벨을 올린다(상태를 손으로 만들지 않는다)
	var g: Dictionary = main.run.growth
	var want := ["blades", "frost"]
	for wid in want:
		PGrowth.apply_choice(main.run, { "kind": "weapon_new", "id": wid })
	PGrowth.apply_choice(main.run, { "kind": "weapon_level", "id": "hammer" })
	PGrowth.apply_choice(main.run, { "kind": "weapon_level", "id": "blades" })
	main.sortie = {}
	main.show("base")
	await process_frame
	await process_frame
	var out := OS.get_environment("CAP_DIR")
	for w in g.weapons:
		print("빌드: %s Lv%d/%d · 개조 %d/%d · %s" % [String(w.id), int(w.level),
			PGrowth.level_cap(g, String(w.id)), (w.mods as Array).size(), PGrowth.mod_cap(g, String(w.id)),
			("주무기" if PCatalog.is_main_weapon(String(w.id)) else "보조")])
	if out != "":
		var img := get_root().get_texture().get_image()
		img.save_png(out + "/build_960x640.png")
		print("저장: " + out + "/build_960x640.png")
	quit()
