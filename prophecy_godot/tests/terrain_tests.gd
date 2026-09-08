extends SceneTree
## 랜덤 지형(사용자 요구 7) 검사: godot --headless --path prophecy_godot -s tests/terrain_tests.gd
##
## 무엇을 확인하나
##  1. 개수·점유 면적의 상한/하한
##  2. 통로 폭(플레이어 지름 28px보다 넉넉한가) — 정확값(두 장애물 틈)과 격자값 둘 다
##  3. 시작 지점·적 등장 지점의 여유 공간(시작 위치가 장애물 안이면 실패)
##  4. 고립 없음(닿을 수 있는 자유 공간 비율)
##  5. 봉인·제단·우리·출구 등 필수 목표에 전부 도달 가능(실제 목표 전투 상태로 확인)
##  6. 적 등장 지점 8곳에서 플레이어까지 실제로 접근된다(steer_dir·move_swept 경로)
##  7. 같은 시드 재현 / 저장한 배치 복원 / 시드가 다르면 배치도 다르다
##  8. 승인된 기준 전투(first_fight)·보스 전장의 고정 지형은 그대로다
##  9. 지형 추첨이 전투 난수(st.rng)를 소비하지 않는다
## 10. KD-3: 테마 경기장 14곳의 playerStart가 실제로 쓰이고, 시작 위치가 장애물 안인 곳이 없다
## 11. 파괴되는 지형(보스 엄폐물 파괴)·정예 돌무더기를 놓을 여지
##
## 부분 실행: PROPHECY_SUBSET=2 처럼 축을 줄이면 시드·전장을 잘라 빠르게 확인한다(PSubset).
## 여기 나오는 상한·하한은 전부 **시험값**이며 사람이 승인한 균형값이 아니다.

const W := 960.0
const H := 600.0
const STEP := 1.0 / 60.0

var results := []
var sub: PSubset

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func base_build() -> Dictionary:
	return PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword")))

## 지형 추첨을 켠 일반 전투 상태(편성 없음 — 지형만 본다)
func mk(arena: String, seed_v: int, random: bool = true, extra: Dictionary = {}) -> CombatState:
	var o := { "build": base_build(), "seed": seed_v, "arena": arena, "objective": "clear",
		"region_id": "forest", "xp_kill_mult": 0.0, "terrain_random": random,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } }
	for k in extra:
		o[k] = extra[k]
	return CombatState.new(o)

## 목표 전투 상태(봉인·제단·포로 구출). PObjectives가 장애물이 정해진 뒤에 목표를 놓는다
func mk_obj(arena: String, seed_v: int, objective: String, random: bool = true) -> CombatState:
	return CombatState.new({ "build": base_build(), "seed": seed_v, "arena": arena, "objective": objective,
		"region_id": "forest", "pool": ["wolf"], "xp_kill_mult": 0.3, "terrain_random": random })

func arena_def(id: String) -> Dictionary:
	return PCatalog.arena(id)

func base_obstacles(id: String) -> Array:
	return arena_def(id).get("obstacles", [])

func start_of(id: String) -> Dictionary:
	return PTerrain.arena_start(arena_def(id), W, H)

## 목표 지점 목록(봉인 지점·제단·우리·출구·포로)
func goal_points(st: CombatState) -> Array:
	var pts := []
	for p in st.obj.get("points", []):
		pts.append({ "x": float(p.x), "y": float(p.y), "what": "봉인 지점" })
	for e in st.obj.get("altars", []):
		pts.append({ "x": float(e.x), "y": float(e.y), "what": "제단" })
	for o in st.objects:
		pts.append({ "x": float(o.x), "y": float(o.y), "what": String(o.kind) })
	return pts

func _init() -> void:
	sub = PSubset.new({
		"seeds": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
		"arenas": (PCatalog.theme_arenas().keys() as Array) + ["clearing", "pillars", "forest"],
	})
	print(sub.describe("랜덤 지형 검사"))
	print("상한·하한(시험값): " + PTerrain.limits_text())

	# ---------- 1. 여러 시드 × 여러 전장으로 뽑아 조건을 전부 검사 ----------
	var lays := []          # [arena, seed, layout]
	var t0 := Time.get_ticks_msec()
	for aid in sub.axis("arenas"):
		var st_p := start_of(String(aid))
		for sd in sub.axis("seeds"):
			lays.append([String(aid), int(sd), PTerrain.generate(String(aid), W, H, base_obstacles(String(aid)), st_p, int(sd))])
	var gen_ms := Time.get_ticks_msec() - t0

	var bad_bounds := []
	var bad_pass := []
	var bad_start := []
	var bad_iso := []
	var bad_reach := []
	var fallbacks := []
	var min_pair := INF
	var min_grid := INF
	var min_wall := INF
	var min_start := INF
	var min_iso := 1.0
	var min_free := 1.0
	var cnt_lo := 99
	var cnt_hi := 0
	var area_lo := 1.0
	var area_hi := 0.0
	for row in lays:
		var tag := "%s/%d" % [row[0], row[1]]
		var lay: Dictionary = row[2]
		var ck: Dictionary = lay.check
		if bool(lay.fallback):
			fallbacks.append(tag)
			continue
		cnt_lo = mini(cnt_lo, int(ck.count))
		cnt_hi = maxi(cnt_hi, int(ck.count))
		area_lo = minf(area_lo, float(ck.area_ratio))
		area_hi = maxf(area_hi, float(ck.area_ratio))
		min_pair = minf(min_pair, float(ck.pair_gap))
		min_grid = minf(min_grid, float(ck.pass_grid))
		min_wall = minf(min_wall, float(ck.wall_gap))
		min_start = minf(min_start, float(ck.start_clear))
		min_iso = minf(min_iso, float(ck.iso_ratio))
		min_free = minf(min_free, float(ck.free22))
		if int(ck.count) < int(PTerrain.LIMITS.count_min) or int(ck.count) > int(PTerrain.LIMITS.count_max) \
			or float(ck.area_ratio) < float(PTerrain.LIMITS.area_min) or float(ck.area_ratio) > float(PTerrain.LIMITS.area_max):
			bad_bounds.append(tag)
		if float(ck.pair_gap) < float(PTerrain.LIMITS.pass_w) or float(ck.pass_grid) < float(PTerrain.LIMITS.pass_grid) \
			or float(ck.wall_gap) < float(PTerrain.LIMITS.wall_gap):
			bad_pass.append(tag)
		if float(ck.start_clear) < float(PTerrain.LIMITS.start_clear):
			bad_start.append(tag)
		if float(ck.iso_ratio) < float(PTerrain.LIMITS.iso_ratio):
			bad_iso.append(tag)
		if float(ck.entry_min) == 0.0 or float(ck.exit_min) == 0.0:
			bad_reach.append(tag)

	var n := lays.size()
	ok("추첨 %d개(전장 %d × 시드 %d)가 전부 안전 기본 배치로 떨어지지 않았다" % [n, sub.count("arenas"), sub.count("seeds")],
		fallbacks.is_empty(), "기본 배치로 떨어진 것: %d개 %s · 생성 %d ms(%.0f ms/개)" % [fallbacks.size(), str(fallbacks.slice(0, 5)), gen_ms, float(gen_ms) / maxf(1.0, float(n))])
	ok("개수·면적이 상한/하한 안이다", bad_bounds.is_empty(),
		"개수 %d~%d(허용 %d~%d) · 면적 %.2f~%.2f%%(허용 %.1f~%.1f%%) · 벗어남 %s" % [cnt_lo, cnt_hi, int(PTerrain.LIMITS.count_min), int(PTerrain.LIMITS.count_max),
			area_lo * 100.0, area_hi * 100.0, float(PTerrain.LIMITS.area_min) * 100.0, float(PTerrain.LIMITS.area_max) * 100.0, str(bad_bounds.slice(0, 5))])
	ok("통로 폭이 플레이어 지름(28px)보다 넉넉하다", bad_pass.is_empty(),
		"두 장애물 틈 최소 %.1f(하한 %.0f) · 격자 통로 폭 최소 %.0f(하한 %.0f) · 벽 틈 최소 %.1f(하한 %.0f) · 벗어남 %s" % [
			min_pair, float(PTerrain.LIMITS.pass_w), min_grid, float(PTerrain.LIMITS.pass_grid), min_wall, float(PTerrain.LIMITS.wall_gap), str(bad_pass.slice(0, 5))])
	ok("시작 지점에 여유가 있다(장애물 안에서 시작하지 않는다)", bad_start.is_empty(),
		"시작 여유 최소 %.1f(하한 %.0f) · 벗어남 %s" % [min_start, float(PTerrain.LIMITS.start_clear), str(bad_start.slice(0, 5))])
	ok("고립된 자유 공간이 없다", bad_iso.is_empty(),
		"닿는 자유 칸 비율 최소 %.4f(하한 %.3f) · 벗어남 %s" % [min_iso, float(PTerrain.LIMITS.iso_ratio), str(bad_iso.slice(0, 5))])
	ok("적 등장 지점 8곳·출구 후보 4곳이 전부 시작 지점과 이어진다", bad_reach.is_empty(), "벗어남 " + str(bad_reach.slice(0, 5)))
	ok("정예 '균열 채굴자'가 돌무더기를 놓을 자유 공간이 남는다(반지름 22 기준 40% 이상)", min_free >= 0.40,
		"자유 칸 비율 최소 %.2f" % min_free)

	# ---------- 2. 재현성·다양성·저장 복원 ----------
	var same := true
	var diff_layouts := {}
	var a0 := String(sub.axis("arenas")[0])
	for sd in sub.axis("seeds"):
		var l1 := PTerrain.generate(a0, W, H, base_obstacles(a0), start_of(a0), int(sd))
		var l2 := PTerrain.generate(a0, W, H, base_obstacles(a0), start_of(a0), int(sd))
		if JSON.stringify(l1.obstacles) != JSON.stringify(l2.obstacles):
			same = false
		diff_layouts[JSON.stringify(l1.obstacles)] = true
	ok("같은 시드는 같은 배치를 만든다", same, "전장 %s · 시드 %d개" % [a0, sub.count("seeds")])
	ok("시드가 다르면 배치도 달라진다(다양성)", diff_layouts.size() >= mini(3, sub.count("seeds")),
		"서로 다른 배치 %d개 / 시드 %d개" % [diff_layouts.size(), sub.count("seeds")])

	var sA := mk(a0, 4321)
	var sB := mk(a0, 4321)
	ok("전투 상태를 두 번 만들어도 지형이 같다", JSON.stringify(sA.obstacles) == JSON.stringify(sB.obstacles),
		"장애물 %d개" % sA.obstacles.size())
	var sC := CombatState.new({ "build": base_build(), "seed": 999, "arena": a0, "objective": "clear",
		"region_id": "forest", "xp_kill_mult": 0.0, "terrain": sA.terrain,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	ok("저장한 배치를 그대로 되살린다(시드가 달라도 저장본이 이긴다)",
		JSON.stringify(sC.obstacles) == JSON.stringify(sA.obstacles),
		"저장본 장애물 %d개 · 복원 %d개" % [(sA.terrain.obstacles as Array).size(), sC.obstacles.size()])

	# ---------- 3. 전투 난수를 건드리지 않는다 ----------
	var rand_on := mk(a0, 77, true)
	var rand_off := mk(a0, 77, false)
	var seq_on := []
	var seq_off := []
	for i in 8:
		seq_on.append(rand_on.rng.next())
		seq_off.append(rand_off.rng.next())
	ok("지형 추첨이 전투 난수(st.rng)를 소비하지 않는다", seq_on == seq_off,
		"장애물 %d개 vs %d개 · 난수 앞 8개 %s" % [rand_on.obstacles.size(), rand_off.obstacles.size(), "동일" if seq_on == seq_off else "다름"])
	ok("추첨이 실제로 지형을 바꾼다(끈 상태와 다르다)", rand_on.obstacles.size() != rand_off.obstacles.size() or JSON.stringify(rand_on.obstacles) != JSON.stringify(rand_off.obstacles))

	# ---------- 4. 승인된 기준 전투·보스 전장은 그대로 ----------
	PTerrain.env_on = true # 환경 변수로 켠 것과 같은 상태로 두고 확인한다
	var G := preload("res://scripts/game/game.gd")
	var cfg: Dictionary = G.load_config()
	var ffs := CombatState.first_fight(cfg, 1)
	var ff_same := ffs.obstacles.size() == (cfg.obstacles as Array).size()
	if ff_same:
		for i in ffs.obstacles.size():
			var a: Dictionary = ffs.obstacles[i]
			var b: Dictionary = cfg.obstacles[i]
			if String(a.id) != String(b.id) or absf(float(a.x) - float(b.x)) > 1e-6 or absf(float(a.y) - float(b.y)) > 1e-6 or absf(float(a.r) - float(b.r)) > 1e-6:
				ff_same = false
	ok("승인된 기준 전투(first_fight)의 고정 지형은 그대로다", ff_same and ffs.terrain.is_empty(),
		"장애물 %d개 · terrain %s" % [ffs.obstacles.size(), "없음" if ffs.terrain.is_empty() else "생성됨"])

	var bst := CombatState.new({ "build": base_build(), "seed": 5, "arena": "clearing", "boss": true, "boss_id": "boss",
		"region_id": "boss", "xp_kill_mult": 0.3 })
	var boss_base: Array = base_obstacles("clearing")
	ok("보스 전장은 별도 규칙 — 지금 배치를 유지한다", bst.obstacles.size() == boss_base.size() and bst.terrain.is_empty(),
		"보스 전장 장애물 %d개(뼈대 %d개)" % [bst.obstacles.size(), boss_base.size()])
	PTerrain.env_on = false

	# ---------- 5. KD-3: 테마 경기장의 시작 위치 ----------
	var no_start := []
	var in_rock := []
	var mismatched := []
	for aid in PCatalog.theme_arenas():
		var ad: Dictionary = PCatalog.theme_arenas()[aid]
		if not ad.has("playerStart"):
			no_start.append(String(aid))
			continue
		var stt := mk(String(aid), 1, false) # 고정 지형(추첨 끔)으로 본다
		var want: Dictionary = ad.playerStart
		if absf(float(stt.player.x) - float(want.x)) > 1e-6 or absf(float(stt.player.y) - float(want.y)) > 1e-6:
			mismatched.append("%s(%d,%d≠%d,%d)" % [String(aid), int(stt.player.x), int(stt.player.y), int(want.x), int(want.y)])
		for obb in stt.obstacles:
			if PGeom.dist(float(obb.x), float(obb.y), float(stt.player.x), float(stt.player.y)) < float(obb.r) + float(stt.player.r):
				in_rock.append("%s/%s" % [String(aid), String(obb.id)])
	ok("KD-3: 테마 경기장 14곳이 전부 playerStart 키를 쓴다", no_start.is_empty(), "빠진 곳: " + str(no_start))
	ok("KD-3: 전투가 실제로 그 시작 위치를 쓴다(기본값 480,300으로 떨어지지 않는다)", mismatched.is_empty(), "어긋난 곳: " + str(mismatched))
	ok("KD-3: 시작 위치가 장애물 안인 경기장이 0곳이다(고치기 전 5곳)", in_rock.is_empty(), "겹침: " + str(in_rock))

	# ---------- 6. 필수 목표 도달 가능(실제 목표 전투 상태) ----------
	var unreachable := []
	var invalid := []
	var goal_n := 0
	for aid in sub.axis("arenas"):
		for objective in ["seal", "altars", "rescue"]:
			var so := mk_obj(String(aid), int(sub.axis("seeds")[0]) + 100, String(objective))
			var pts := goal_points(so)
			goal_n += pts.size()
			var rs := PTerrain.reachable_all(so.arena_w, so.arena_h, so.obstacles, { "x": so.player.x, "y": so.player.y }, pts, 14.0, 46.0)
			for i in pts.size():
				if not bool(rs[i]):
					unreachable.append("%s/%s/%s" % [String(aid), String(objective), String(pts[i].what)])
				if not so.valid_pos(float(pts[i].x), float(pts[i].y), 14.0):
					invalid.append("%s/%s/%s" % [String(aid), String(objective), String(pts[i].what)])
	ok("봉인·제단·우리·출구 등 필수 목표 %d곳에 전부 도달 가능하다" % goal_n, unreachable.is_empty(), "못 닿는 곳: " + str(unreachable.slice(0, 6)))
	ok("목표가 놓인 자리가 전부 설 수 있는 자리다", invalid.is_empty(), "장애물과 겹친 곳: " + str(invalid.slice(0, 6)))

	# ---------- 7. 적 접근 경로(실제 조향·이동 규칙으로) ----------
	var stuck := []
	var worst := 0.0
	for aid in sub.axis("arenas"):
		var sc2 := mk(String(aid), int(sub.axis("seeds")[0]) + 200)
		sc2.spawn_hold = true
		for q in PTerrain.entry_points():
			var e := sc2.spawn_enemy("wolf", float(q[0]), float(q[1]))
			var d0 := PGeom.dist(e.x, e.y, sc2.player.x, sc2.player.y)
			for i in 900: # 15초 · 속도 120 → 1800px(전장 대각선보다 길다)
				sc2.approach(e, sc2.player.x, sc2.player.y, 120.0, STEP)
			var d1 := PGeom.dist(e.x, e.y, sc2.player.x, sc2.player.y)
			worst = maxf(worst, d1)
			if d1 > 40.0:
				stuck.append("%s (%d,%d) %.0f→%.0f" % [String(aid), int(q[0]), int(q[1]), d0, d1])
			sc2.enemies.clear()
	ok("적이 등장 지점 8곳 어디서든 플레이어까지 접근한다", stuck.is_empty(),
		"가장 먼 최종 거리 %.1fpx · 막힌 경우 %s" % [worst, str(stuck.slice(0, 5))])

	# ---------- 8. 파괴되는 지형(보스 '엄폐물 파괴')과 돌무더기 ----------
	var broke_bad := []
	for aid in sub.axis("arenas"):
		var lay := PTerrain.generate(String(aid), W, H, base_obstacles(String(aid)), start_of(String(aid)), int(sub.axis("seeds")[0]) + 300)
		var obs: Array = lay.obstacles
		for k in obs.size():
			var rest := obs.duplicate(true)
			rest.remove_at(k)
			var ck2 := PTerrain.check(W, H, rest, start_of(String(aid)), PTerrain.entry_points(), PTerrain.exit_points(W, H))
			if float(ck2.iso_ratio) < float(PTerrain.LIMITS.iso_ratio) or float(ck2.entry_min) == 0.0 or float(ck2.exit_min) == 0.0:
				broke_bad.append("%s/-%s" % [String(aid), String(obs[k].id)])
	ok("장애물이 하나 부서져도 고립·도달이 나빠지지 않는다(보스 엄폐물 파괴)", broke_bad.is_empty(), "나빠진 경우: " + str(broke_bad.slice(0, 5)))

	var rubble_ok := true
	var rubble_note := ""
	for aid in sub.axis("arenas"):
		var sr := mk(String(aid), int(sub.axis("seeds")[0]) + 400)
		var spot := sr.nearest_valid_pos(sr.arena_w / 2.0, sr.arena_h / 2.0, 22.0, 200.0)
		if spot.is_empty():
			rubble_ok = false
			rubble_note += String(aid) + " "
	ok("돌무더기(반지름 18)를 놓을 자리를 전장마다 찾을 수 있다", rubble_ok, rubble_note)

	# ---------- 9. 부분 실행 도우미 ----------
	var s2 := PSubset.new({ "seeds": [1, 2, 3], "arenas": ["a", "b"] })
	ok("PSubset: 환경 변수가 없으면 전체 실행이고 보고서 경로를 바꾸지 않는다",
		(not s2.partial) == (OS.get_environment("PROPHECY_SUBSET") == "" and OS.get_environment("PROPHECY_SEEDS") == "" and OS.get_environment("PROPHECY_ARENAS") == ""),
		s2.describe("자체 확인"))
	ok("PSubset: 부분 실행이면 보고서를 _PARTIAL로 돌린다", sub.out_path("res://docs/TERRAIN_REPORT.md").ends_with("_PARTIAL.md") == sub.partial,
		sub.out_path("res://docs/TERRAIN_REPORT.md"))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
