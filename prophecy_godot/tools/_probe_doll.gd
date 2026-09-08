extends SceneTree
## 검수 지적 재현: 인형이 본체에서 멀면 가로채기가 아예 안 되는가
func run_at(dist: float) -> Dictionary:
	var run := PRun.new_run(4, "hammer")
	PGrowth.apply_choice(run, { "kind": "weapon_new", "id": "doll" })
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 4,
		"waves": [[{ "type": "wolf", "n": 6 }]], "objective": "clear", "region_id": "den", "run": run })
	var w := {}
	for x in st.weapons:
		if String(x.id) == "doll":
			w = x
	PSupport.fire(st, w, st.enemies[0], false)
	var d := PSupportB.doll_of(st)
	if not d.is_empty():
		d.x = float(st.player.x) + dist
		d.y = float(st.player.y)
	var bot := PSkillBot.new("novice", 4)
	var i := 0
	while i < 120 * 25 and st.status == "running":
		st.step(bot.step_input(st), 1.0 / 120.0)
		i += 1
	var m: Dictionary = st.support.get("doll", {})
	return { "dist": dist, "lured": int(m.get("lured", 0)), "absorbed": int(m.get("absorbed", 0)),
		"absorbed_dmg": float(m.get("absorbed_dmg", 0.0)), "taken": float(st.stats.damage_taken) }
func _init() -> void:
	for dd in [60.0, 120.0, 200.0]:
		var r := run_at(dd)
		print("인형 거리 %3d → 유인 %d · 대신 받음 %d회(%.0f) · 본체 피해 %.0f" % [int(r.dist), int(r.lured), int(r.absorbed), float(r.absorbed_dmg), float(r.taken)])
	quit()
