extends SceneTree
## HTML 대조 시나리오(화면 없음): 같은 조건에서 이동·회피·돌진 거리, 공격 주기, 1회 피해, 감속 효과를 측정해 JSON으로 출력한다.
## HTML 쪽은 prophecy_action_prototype/tools/port_compare_html.js가 같은 측정을 한다. 사용: godot --headless --path prophecy_godot -s tools/compare_scenario.gd

const STEP := 1.0 / 120.0

func _init() -> void:
	# HTML 대조는 옛 회피 규칙(고정 150·재사용 0.9)으로 잰다. 재사용 시작 시점은 Godot이 '출발 순간', HTML은 '종료 시점'이라 dodge_cd_after만 다른 것이 정상(RULES.md §회피)
	var cfg: Dictionary = preload("res://scripts/game/game.gd").config_with_dodge(preload("res://scripts/game/game.gd").load_config(), "fixed", 0.9)
	var out := {}
	# 이동 1초
	var st := CombatState.first_fight(cfg, 1); st.spawn_hold = true
	var x0: float = st.player.x
	for i in 120:
		st.step({ "mx": 1.0 }, STEP)
	out["move_1s"] = snapped(st.player.x - x0, 0.001)
	# 대각 이동 1초(정규화)
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	x0 = st.player.x
	var y0: float = st.player.y
	for i in 120:
		st.step({ "mx": 1.0, "my": -1.0 }, STEP)
	out["move_diag_1s"] = snapped(PGeom.dist(x0, y0, st.player.x, st.player.y), 0.001)
	# 회피 거리·무적 시간·재사용
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	y0 = st.player.y
	st.step({ "my": -1.0, "dodge_press": true, "dodge_held": true }, STEP)
	var inv_steps := 0
	while st.player.dodge_active and inv_steps < 200:
		st.step({ "dodge_held": true }, STEP)
		inv_steps += 1
	out["dodge_dist"] = snapped(y0 - st.player.y, 0.001)
	out["dodge_invuln_steps"] = inv_steps + 1
	out["dodge_cd_after"] = snapped(st.player.dodge_cd, 0.0001)
	# 늑대 돌진 거리·준비/확정/돌진/빈틈 시간(스텝 수)
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	var w := st.spawn_enemy("wolf", 480.0, 200.0)
	st.player.y = 585.0
	w.state = "crouch"; w.state_t = 0.0
	var counts := { "crouch": 0, "lock": 0, "dash": 0, "recover": 0 }
	var sx: float = 0.0
	var sy: float = 0.0
	for i in 600:
		var before: String = w.state
		if before == "dash" and counts.dash == 0:
			sx = w.x; sy = w.y
		st.step({}, STEP)
		if counts.has(before):
			counts[before] += 1
		if w.state == "approach" and before == "recover":
			break
	out["wolf_steps"] = counts
	out["wolf_dash_dist"] = snapped(PGeom.dist(sx, sy, w.x, w.y), 0.01)
	# 공격 주기·1회 피해·빈틈 배율
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	var e := st.spawn_enemy("wolf", st.player.x + 60.0, st.player.y)
	e.hp = 99999.0; e.bite_cd = 1.0e9; e.dash_ready_at = 1.0e9 # 공격하지 않는 표적(검격 주기만 잰다)
	var hit_times := []
	var last_hits := 0
	for i in 600:
		st.step({}, STEP)
		e.x = st.player.x + 60.0; e.y = st.player.y
		if st.stats.hits > last_hits:
			hit_times.append(snapped(st.t, 0.0001))
			last_hits = st.stats.hits
	out["attack_times"] = hit_times
	out["hit_damage_normal"] = snapped(st.metrics.dmg["weapon:sword"] / float(st.stats.hits), 0.01)
	e.state = "recover"
	var before_d: float = st.metrics.dmg["weapon:sword"]
	var before_h: int = st.stats.hits
	for i in 80:
		st.step({}, STEP)
		e.x = st.player.x + 60.0; e.y = st.player.y; e.state = "recover"; e.state_t = 0.0
	out["hit_damage_exposed"] = snapped((st.metrics.dmg["weapon:sword"] - before_d) / float(st.stats.hits - before_h), 0.01)
	# 감속: 안에서 늑대 접근 속도·준비 진행
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	var s1 := st.spawn_enemy("wolf", 480.0, 100.0)
	st.player.y = 560.0
	st.step({ "special": true }, STEP)
	st.field.x = 480.0; st.field.y = 100.0 # 늑대 위치에 감속장
	var ya: float = s1.y
	for i in 60:
		st.step({}, STEP)
	out["wolf_move_0_5s_in_field"] = snapped(s1.y - ya, 0.01)
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	var s2 := st.spawn_enemy("wolf", 480.0, 100.0)
	st.player.y = 560.0
	ya = s2.y
	for i in 60:
		st.step({}, STEP)
	out["wolf_move_0_5s_free"] = snapped(s2.y - ya, 0.01)
	# 늑대 물기 피해·피격 보호
	st = CombatState.first_fight(cfg, 1); st.spawn_hold = true
	st.damage_player(float(cfg.enemies.wolf.dash.damage), "wolf:dash")
	out["wolf_bite_damage"] = snapped(st.player.hp_max - st.player.hp, 0.01)
	out["hit_protect"] = cfg.player.hit_protect
	print("COMPARE_JSON " + JSON.stringify(out))
	quit()
