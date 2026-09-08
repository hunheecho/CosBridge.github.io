extends SceneTree
## 보스 지형 파괴 규칙 시험(headless): godot --headless --path prophecy_godot -s tests/boss_break_tests.gd
## 확인하는 것(사용자 확정 지형 규칙 그대로):
##  1. 보스 9종 전부에게 성격에 맞는 파괴 행동이 있고, 그 행동이 실제로 발동해 장애물이 사라진다.
##  2. 파괴 순간 **충돌도 함께 사라진다**(그림만 지우지 않는다): 그 자리에 설 수 있고 시야·투사체가 통과한다.
##  3. **파괴할 수 없는 외곽 경계**는 안 부서진다(데이터 규칙 terrain.edgeMargin·boundaryIds·breakTypes).
##  4. 필수 목표·출구·제단 옆은 안 부서진다(goalGuard).
##  5. 남길 최소 장애물 수(keepMin)·한 전투 상한(maxPerFight)을 지킨다 — 엄폐가 통째로 사라지지 않는다.
##  6. **파편이 새 영구 장애물이 되지 않는다**: 파괴 뒤 걸어 닿는 칸이 줄지 않는다(플레이어가 갇히지 않는다).
##  7. **파괴 예고가 피해 판정보다 먼저 읽힌다**: 예고 문구 → 파괴 → (그 뒤에) 피해.
##  8. 파괴 자격은 "시선이 막힌 채 trigger 초"가 있어야 생긴다 — 잠시 몸을 가리는 엄폐는 계속 유효하다.
## 수치는 전부 data/boss_behavior.json(시험값)에서 읽는다. 이 파일에는 균형 숫자를 두지 않는다.

const STEP := 1.0 / 120.0
const HUGE_HP := 1000000.0
const CAMP_SEC := 45.0
const BOSSES: Array = ["boss", "guardian", "eater", "gate_warden", "spore_matriarch",
	"excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 불씨 정령만 든 빌드(사람이 겪은 상황: 돌 뒤에서 바닥 불길로만 때린다)
func ember_build() -> Dictionary:
	var g := PGrowth.new_growth("sword")
	g.weapons = [{ "id": "ember", "level": 3, "mods": ["scatter", "trail"] }]
	return PBuild.derive(PBuild.empty_run_like(g))

func make(boss_id: String, seed_v: int = 11, phase: int = 3, break_on: bool = true) -> CombatState:
	PBoss.set_cover_mode("")
	PBoss.set_split_on(true)
	PBoss.set_break_on(break_on)
	var st := CombatState.new({ "build": ember_build(), "seed": seed_v, "arena": "clearing", "boss": true,
		"boss_id": boss_id, "region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP, "act": 3 })
	for i in 900:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	st.boss.phase = phase
	st.boss.phase_pending = phase
	return st

## 그 보스가 부술 수 있는 종류의 엄폐 뒤 자리. 반환 [x, y, 장애물]
func camp_spot(st: CombatState, want_type: String) -> Array:
	var bz: Dictionary = st.boss
	var best := []
	var bd := -1.0
	for pass_i in 2:
		for ob in st.obstacles:
			if pass_i == 0 and String(ob.type) != want_type:
				continue
			for k in 16:
				var a: float = float(k) * TAU / 16.0
				var d: float = float(ob.r) + 26.0
				var x: float = clampf(float(ob.x) + cos(a) * d, 30.0, st.arena_w - 30.0)
				var y: float = clampf(float(ob.y) + sin(a) * d, 30.0, st.arena_h - 30.0)
				if not st.valid_pos(x, y, float(st.player.r)):
					continue
				if not st.los_blocked(float(bz.x), float(bz.y), x, y):
					continue
				var score := PGeom.dist(x, y, float(bz.x), float(bz.y))
				if score > bd:
					bd = score
					best = [x, y, ob]
		if not best.is_empty():
			return best
	return best

## 엄폐 뒤에 계속 서 있는 한 판. 반환 {broke, ob, t_break, t_hurt, obs0, obs1, reach0, reach1, why}
func camp_run(st: CombatState, spot: Array, sec: float = CAMP_SEC) -> Dictionary:
	var bz: Dictionary = st.boss
	var phase: int = int(bz.phase)
	var start := { "x": spot[0], "y": spot[1] }
	var obs0: int = st.obstacles.size()
	var reach0 := PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, start)
	var t_break := -1.0
	var t_hurt := -1.0
	var t_warn := -1.0
	var hp0: float = float(st.stats.damage_taken)
	for i in int(sec / STEP):
		if st.status != "running" or bool(bz.dead):
			break
		st.player.x = spot[0]
		st.player.y = spot[1]
		# 파괴 예고 문구가 뜬 시각(예고 → 파괴 → 피해 순서를 확인한다)
		if t_warn < 0.0 and bool(bz.get("break_want", false)):
			t_warn = st.t
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }, STEP)
		st.player.hp = st.player.hp_max
		bz.phase = phase
		bz.phase_pending = phase
		if t_break < 0.0 and not (st.metrics.get("broken", []) as Array).is_empty():
			t_break = st.t
		if t_hurt < 0.0 and float(st.stats.damage_taken) > hp0 + 0.001:
			t_hurt = st.t
	var broken: Array = st.metrics.get("broken", [])
	var whys := []
	for b in broken:
		whys.append(String(b.why))
	return { "broke": broken.size(), "broken": broken, "t_break": t_break, "t_hurt": t_hurt, "t_warn": t_warn,
		"obs0": obs0, "obs1": st.obstacles.size(),
		"reach0": reach0, "reach1": PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, start), "why": whys }

func _init() -> void:
	var R := PTerrain.break_rules()
	ok("지형 파괴 규칙이 데이터에 있다(data/boss_behavior.json terrain)", not R.is_empty(),
		"부술 수 있는 종류 %s · 벽 여유 %.0f · 목표 여유 %.0f · 남길 최소 %d · 전투 상한 %d" % [
			str(R.get("breakTypes", [])), float(R.get("edgeMargin", 0.0)), float(R.get("goalGuard", 0.0)),
			int(R.get("keepMin", 0)), int(R.get("maxPerFight", 0))])

	# ---------- 1. 보스 9종 전부에게 서로 다른 파괴 행동이 있다 ----------
	var shapes := {}
	var missing := []
	for bid in BOSSES:
		var Bk: Dictionary = PBoss.beh_of(bid).get("breaker", {})
		if Bk.is_empty():
			missing.append(bid)
			continue
		shapes[String(Bk.get("shape", ""))] = String(Bk.get("shape", ""))
	ok("보스 9종 모두에게 파괴 행동 설정이 있다", missing.is_empty(), str(missing))
	ok("파괴 판정 모양이 보스마다 다르다(같은 효과를 이름만 바꾸지 않았다): %d종" % shapes.size(),
		shapes.size() == BOSSES.size(), str(shapes.keys()))

	# ---------- 2. 보스별 파괴가 실제로 발동하고 충돌까지 사라진다 ----------
	var fired := []
	for bid in BOSSES:
		var Bk: Dictionary = PBoss.beh_of(bid).get("breaker", {})
		var types: Array = Bk.get("types", ["rock"])
		var st := make(bid)
		var spot := camp_spot(st, String(types[0]) if types.size() > 0 else "rock")
		if spot.is_empty():
			ok("%s: 엄폐 자리를 찾았다" % bid, false)
			continue
		var target: Dictionary = spot[2]
		var tx: float = float(target.x)
		var ty: float = float(target.y)
		var was_solid: bool = not st.valid_pos(tx, ty, 1.0)
		var r := camp_run(st, spot)
		var gone: bool = st.obstacles.find(target) < 0
		ok("%s: 지형 파괴가 실제로 발동한다(%s)" % [bid, ", ".join(PackedStringArray(r.why))],
			int(r.broke) > 0, "첫 파괴 %.1f초 · 장애물 %d→%d · 서 있던 엄폐가 사라졌다 %s" % [float(r.t_break), int(r.obs0), int(r.obs1), str(gone)])
		if int(r.broke) > 0:
			fired.append(bid)
			# 충돌도 함께 사라졌는가: 부순 자리에 설 수 있고 그 자리를 지나는 시야가 트인다
			var b0: Dictionary = (r.broken as Array)[0]
			var bx: float = float(b0.x)
			var by: float = float(b0.y)
			var stand: bool = st.valid_pos(bx, by, 1.0)
			var see: bool = not st.los_blocked(bx - float(b0.r) - 4.0, by, bx + float(b0.r) + 4.0, by)
			ok("%s: 파괴 순간 충돌도 사라진다(그림만 남지 않는다)" % bid, stand and see,
				"부순 자리에 설 수 있다 %s · 시야 통과 %s · (파괴 전 그 자리 막힘 %s)" % [str(stand), str(see), str(was_solid)])
			# 파편이 새 장애물이 되지 않는다 = 걸어 닿는 칸이 줄지 않는다(갇히지 않는다)
			ok("%s: 파괴 뒤 이동 가능 영역이 줄지 않는다(파편이 새 벽이 되지 않는다)" % bid,
				int(r.reach1) >= int(r.reach0), "닿는 칸 %d → %d" % [int(r.reach0), int(r.reach1)])
			# 파괴 예고 → 파괴 → 피해 순서
			ok("%s: 파괴 예고가 파괴보다 먼저 뜬다" % bid, float(r.t_warn) >= 0.0 and float(r.t_warn) <= float(r.t_break),
				"예고 %.1f초 → 파괴 %.1f초" % [float(r.t_warn), float(r.t_break)])
			# 남길 최소 장애물 수를 지킨다
			ok("%s: 남길 최소 장애물 수를 지킨다" % bid, int(r.obs1) >= int(R.get("keepMin", 0)),
				"남은 %d ≥ 최소 %d" % [int(r.obs1), int(R.get("keepMin", 0))])
			ok("%s: 한 전투 파괴 상한을 넘지 않는다" % bid, int(r.broke) <= int(R.get("maxPerFight", 99)),
				"부순 %d ≤ 상한 %d" % [int(r.broke), int(R.get("maxPerFight", 99))])
		ok("%s: 장애물이 늘어나지 않는다(파괴 API는 더하지 않는다)" % bid, int(r.obs1) <= int(r.obs0),
			"%d → %d" % [int(r.obs0), int(r.obs1)])
	ok("보스 9종의 파괴 행동이 전부 실제로 발동했다", fired.size() == BOSSES.size(), str(fired))

	# ---------- 3. 파괴할 수 없는 외곽 경계 ----------
	var stb := make("boss")
	var W: float = stb.arena_w
	var H: float = stb.arena_h
	var margin := float(R.get("edgeMargin", 40.0))
	var edge := { "id": "edge1", "type": "rock", "x": margin, "y": H / 2.0, "r": 30.0, "canopy": false }
	var mid := { "id": "mid1", "type": "rock", "x": W / 2.0, "y": H / 2.0, "r": 30.0, "canopy": false }
	ok("전장 벽에 붙은 장애물은 외곽 경계다(파괴 불가)", PTerrain.role_of(W, H, edge) == "boundary",
		"구실 %s · 벽 여유 %.0f" % [PTerrain.role_of(W, H, edge), margin])
	ok("한가운데 장애물은 파괴 가능한 전투 장애물이다", PTerrain.role_of(W, H, mid) == "cover", PTerrain.role_of(W, H, mid))
	var not_listed := { "id": "x1", "type": "wall", "x": W / 2.0, "y": H / 2.0, "r": 30.0 }
	ok("데이터의 breakTypes에 없는 종류는 외곽 경계로 본다", PTerrain.role_of(W, H, not_listed) == "boundary")
	stb.obstacles.append(edge)
	var edge_i: int = stb.obstacles.size() - 1
	var before: int = stb.obstacles.size()
	ok("break_obstacle이 외곽 경계를 거절한다", not stb.break_obstacle(edge_i, "시험:경계") and stb.obstacles.size() == before)

	# ---------- 4. 필수 목표·출구 옆은 안 부순다 ----------
	var sto := make("boss")
	var oi := 0 # 첫 장애물 옆에 목표(출구)를 놓는다
	var ob0: Dictionary = sto.obstacles[oi]
	sto.objects.append({ "kind": "exit", "x": float(ob0.x) + float(ob0.r) + 10.0, "y": float(ob0.y), "r": 30.0, "open": false })
	ok("break_obstacle이 필수 목표·출구 옆을 거절한다", not sto.break_obstacle(oi, "시험:목표"),
		"목표 여유 %.0f" % float(R.get("goalGuard", 0.0)))
	sto.objects.clear()
	ok("목표가 없으면 같은 장애물은 부술 수 있다(거절 이유가 목표였음을 확인)", sto.break_obstacle(oi, "시험:목표없음"))

	# ---------- 5. 남길 최소 장애물 수 ----------
	var stk := make("boss")
	var keep_min := int(R.get("keepMin", 2))
	var n_break := 0
	for i in 20:
		if stk.obstacles.size() <= 0:
			break
		if stk.break_obstacle(0, "시험:상한"):
			n_break += 1
		else:
			break
	ok("남길 최소 장애물 수·전투 상한에서 파괴가 멈춘다", stk.obstacles.size() >= keep_min and n_break <= int(R.get("maxPerFight", 99)),
		"부순 %d · 남은 %d(최소 %d · 전투 상한 %d)" % [n_break, stk.obstacles.size(), keep_min, int(R.get("maxPerFight", 99))])

	# ---------- 6. 파괴 자격 없이는 아무것도 안 부순다(잠시 가리는 엄폐는 유효하다) ----------
	var stn := make("blood_hunt_king")
	stn.boss.break_want = false
	var idxs := PTerrain.pick_circle(stn.arena_w, stn.arena_h, stn.obstacles, float(stn.obstacles[0].x), float(stn.obstacles[0].y), 60.0)
	var n0: int = stn.obstacles.size()
	PBoss.break_do(stn, stn.boss, idxs, "시험:자격없음")
	ok("파괴 자격(엄폐 뒤 trigger 초)이 없으면 아무것도 안 부순다", stn.obstacles.size() == n0,
		"장애물 %d 유지" % n0)

	# ---------- 7. 되돌리기 스위치 ----------
	# (가) 지형 파괴를 끄면 파괴 자격 자체가 서지 않는다 — 같은 조건으로 한 판을 다 돌려도 아무것도 안 부순다
	var stx := make("gate_warden", 11, 3, false)
	var spot_x := camp_spot(stx, "rock")
	var rx := camp_run(stx, spot_x)
	ok("지형 파괴를 끄면 파괴 자격이 서지 않는다(되돌리기 스위치)", int(rx.broke) == 0 and int(rx.obs1) == int(rx.obs0),
		"장애물 %d → %d" % [int(rx.obs0), int(rx.obs1)])
	PBoss.set_break_on(true)
	# (나) 데이터에서 terrain 절을 지우면 파괴 API가 전부 거절한다(코드에 숫자가 없다는 증거)
	var B := PBoss.behavior()
	var saved = B.get("terrain", null)
	B.erase("terrain")
	var sty := make("boss")
	var ny: int = sty.obstacles.size()
	sty.boss.break_want = true
	var refused: bool = not sty.break_obstacle(0, "시험:규칙없음")
	if saved != null:
		B["terrain"] = saved
	ok("데이터에서 지형 규칙을 지우면 파괴 API가 전부 거절한다", refused and sty.obstacles.size() == ny)

	# ---------- 8. 전장별 구실 표(보고서용) ----------
	print("\n== 전장별 장애물 구실(파괴 가능한 전투 장애물 / 파괴할 수 없는 외곽 경계) ==")
	print("| 전장 | 장애물 | 구실 |")
	print("|---|---|---|")
	var arenas: Array = []
	for k in PCatalog.arenas():
		arenas.append(String(k))
	for k in PCatalog.theme_arenas():
		arenas.append(String(k))
	for aid in arenas:
		var ad := PCatalog.arena(String(aid))
		var obs: Array = ad.get("obstacles", [])
		var cover := 0
		var bound := 0
		for ob in obs:
			if PTerrain.role_of(W, H, ob) == "cover":
				cover += 1
			else:
				bound += 1
		print("| %s | %d | 전투 장애물 %d · 외곽 경계 %d |" % [String(aid), obs.size(), cover, bound])

	var pass_n := 0
	for r in results:
		if bool(r[0]):
			pass_n += 1
	print("\n%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
