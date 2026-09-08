extends SceneTree
## 막·테마 색 정본(data/palette.json)과 적 예고 대비 시험(headless).
## 실행: python tools/run_suites.py --suites palette_tests --jobs 1 --allow-adhoc
##
## 확인하는 것
##  A. 색 정본이 실제 테마 목록(data/themes.json)과 1:1로 맞는지, 막 기본값 3벌이 다 있는지
##  B. 막 색감 방향(사용자 결정): 1막 초록 → 2막 연주황 → 3막 붉은 주황, 채도는 낮게
##  C. 같은 막 안에서도 테마 9종의 바닥·수관 색이 서로 달라 테마 차이가 남는지
##  D. **3막 배경 위에서 붉은 예고가 묻히지 않는지를 수치로**: 배경(비네트 중앙까지 얹은 실제 색) 대비
##     예고 채움·테두리·합성색의 상대 명도비(WCAG). 기준값은 palette.json의 contrast에 적혀 있다.
##  E. 테두리 밑 어두운 겹이 밝은 테두리와 충분히 갈라지는지(형태 대비)
##  F. 배경·예고 색이 render.gd에 다시 하드코딩되지 않았는지(정본 한 곳 유지)
##  G. 색 고르기 규칙: 테마 덮어쓰기가 막 기본값 위에 얹히고, 모르는 테마(보스 전투 등)는 막 기본값으로 떨어지는지

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

# ---------- 상대 명도비(WCAG 2.x) ----------
static func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)

static func lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)

## 두 색의 상대 명도비(1.0 = 같음, 21.0 = 검정 대 흰색)
static func ratio(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## fg를 알파 a로 bg 위에 얹었을 때의 색
static func over(fg: Color, bg: Color, a: float) -> Color:
	return Color(fg.r * a + bg.r * (1.0 - a), fg.g * a + bg.g * (1.0 - a), fg.b * a + bg.b * (1.0 - a), 1.0)

## 화면에서 배경이 가장 밝아지는 곳(비네트 중앙)의 실제 색 — 예고에 가장 불리한 배경이다
static func bg_of(P: Dictionary) -> Color:
	var ground := Color.html(String(P.get("ground", "#2b3a25")))
	var vig := Color.html(String(P.get("vignette", "#5a783c")))
	return over(vig, ground, float(P.get("vignette_a", 0.2)))

func _run() -> void:
	PRender.palette_reset()
	var D := PRender.palette_data()
	var acts: Dictionary = D.get("acts", {})
	var themes: Dictionary = D.get("themes", {})
	var CT: Dictionary = D.get("contrast", {})

	# ---------- A. 정본이 실제 테마 목록과 맞는지 ----------
	var real: Array = PCatalog.themes().keys()
	real.sort()
	var mine: Array = themes.keys()
	mine.sort()
	ok("색 정본에 막 기본값 3벌(1·2·3막)이 있다", acts.has("1") and acts.has("2") and acts.has("3"), str(acts.keys()))
	ok("색 정본의 테마 %d종이 data/themes.json의 테마와 정확히 같다" % mine.size(), mine == real, "정본=%s / 실제=%s" % [str(mine), str(real)])
	var act_match := true
	for tid in themes:
		if int((themes[tid] as Dictionary).get("act", 0)) != int(PCatalog.themes()[tid].act):
			act_match = false
	ok("테마마다 적힌 막 번호가 실제 테마의 막과 같다", act_match)

	# ---------- B. 막 색감 방향(1막 초록 → 2막 연주황 → 3막 붉은 주황) ----------
	var g1 := Color.html(String(acts["1"].ground))
	var g2 := Color.html(String(acts["2"].ground))
	var g3 := Color.html(String(acts["3"].ground))
	ok("1막 바닥은 초록 쪽(G가 가장 크다) %s" % String(acts["1"].ground), g1.g > g1.r and g1.g > g1.b)
	ok("2막 바닥은 따뜻한 흙색(R > G > B) %s" % String(acts["2"].ground), g2.r > g2.g and g2.g > g2.b)
	ok("3막 바닥은 붉은 쪽(2막보다 R−G 차이가 크다) %s" % String(acts["3"].ground), (g3.r - g3.g) > (g2.r - g2.g), "3막 %.3f > 2막 %.3f" % [g3.r - g3.g, g2.r - g2.g])
	var sat_ok := true
	var sat_txt := []
	for a in ["1", "2", "3"]:
		var c := Color.html(String(acts[a].ground))
		sat_txt.append("%s막 채도 %.2f" % [a, c.s])
		if c.s > 0.45:
			sat_ok = false
	ok("세 막 모두 바닥 채도가 낮다(≤0.45 — 눈이 덜 피로하게)", sat_ok, ", ".join(sat_txt))

	# ---------- C. 같은 막 안에서도 테마 차이가 남는지 ----------
	var by_act := { 1: [], 2: [], 3: [] }
	for tid in themes:
		by_act[int(themes[tid].act)].append(tid)
	var distinct := true
	for a in by_act:
		var seen := {}
		for tid in by_act[a]:
			var P := PRender.palette_for(int(a), String(tid))
			var key := "%s|%s" % [String(P.ground), String(P.canopy)]
			if seen.has(key):
				distinct = false
			seen[key] = tid
	ok("같은 막 안에서 테마 3종의 바닥·수관 색이 서로 다르다(막 색감은 유지, 테마 차이는 보존)", distinct)

	# ---------- D·E. 예고 대비(수치) ----------
	var fill_a := float(CT.get("fill_alpha", 0.55))
	var min_fill := float(CT.get("min_fill_ratio", 3.0))
	var min_edge := float(CT.get("min_edge_ratio", 4.5))
	var min_comp := float(CT.get("min_composite_ratio", 1.7))
	var min_dark := float(CT.get("min_dark_vs_edge_ratio", 7.0))
	var act3_edge := float(CT.get("act3_min_edge_ratio", 6.0))
	var bad := []
	var rows := []
	var worst := { 1: [99.0, 99.0, 99.0], 2: [99.0, 99.0, 99.0], 3: [99.0, 99.0, 99.0] }
	var ids: Array = themes.keys()
	ids.sort()
	for tid in ids:
		var a := int(themes[tid].act)
		var P := PRender.palette_for(a, String(tid))
		var bg := bg_of(P)
		var fill := Color.html(String(P.tele_fill))
		var edge := Color.html(String(P.tele_edge))
		var dark := Color.html(String(P.tele_dark))
		var rf := ratio(fill, bg)
		var re := ratio(edge, bg)
		var rc := ratio(over(fill, bg, fill_a), bg)
		var rd := ratio(edge, dark)
		rows.append("%d막 %-22s 배경 #%s · 채움 %.2f · 테두리 %.2f · 합성(α%.2f) %.2f · 어두운겹 %.2f" % [a, tid, bg.to_html(false), rf, re, fill_a, rc, rd])
		worst[a] = [minf(worst[a][0], rf), minf(worst[a][1], re), minf(worst[a][2], rc)]
		if rf < min_fill:
			bad.append("%s 채움 %.2f<%.2f" % [tid, rf, min_fill])
		if re < min_edge:
			bad.append("%s 테두리 %.2f<%.2f" % [tid, re, min_edge])
		if rc < min_comp:
			bad.append("%s 합성 %.2f<%.2f" % [tid, rc, min_comp])
		if rd < min_dark:
			bad.append("%s 어두운겹 %.2f<%.2f" % [tid, rd, min_dark])
		if a == 3 and re < act3_edge:
			bad.append("3막 %s 테두리 %.2f<%.2f" % [tid, re, act3_edge])
	for r in rows:
		print("  " + r)
	ok("모든 막·테마에서 예고 대비가 기준 이상(채움≥%.1f · 테두리≥%.1f · 합성≥%.2f · 어두운겹≥%.1f)" % [min_fill, min_edge, min_comp, min_dark], bad.is_empty(), "; ".join(bad))
	ok("3막 예고 테두리 대비가 세 막 중 가장 높다(붉은 배경에서 가장 안 묻힌다)", worst[3][1] > worst[1][1] and worst[3][1] > worst[2][1],
		"1막 %.2f · 2막 %.2f · 3막 %.2f" % [worst[1][1], worst[2][1], worst[3][1]])
	ok("3막 예고 채움·합성 대비도 기준을 넉넉히 넘는다", worst[3][0] >= min_fill and worst[3][2] >= min_comp,
		"채움 %.2f · 합성 %.2f" % [worst[3][0], worst[3][2]])

	# ---------- F. 정본 한 곳 유지(하드코딩 감소) ----------
	var fa := FileAccess.open("res://scripts/game/render.gd", FileAccess.READ)
	var src := fa.get_as_text() if fa != null else ""
	var tele_start := src.find("static func draw_telegraphs(")
	var tele_end := src.find("# ---------- 투사체 ----------")
	var tele_src := src.substr(tele_start, maxi(0, tele_end - tele_start))
	var leaks := []
	for lit in ["rgba(255, 60, 60,", "rgba(255, 80, 80,", "rgba(255, 120, 120,", "C(\"#ff7070\")", "C(\"#ffd9b0\")"]:
		if tele_src.find(lit) >= 0:
			leaks.append(lit)
	ok("적 예고 구간에 위험색 하드코딩이 남아 있지 않다(전부 palette.json)", leaks.is_empty() and tele_start > 0, "; ".join(leaks))
	var forest_start := src.find("static func draw_forest(")
	var forest_end := src.find("# ---------- 장애물")
	var forest_src := src.substr(forest_start, maxi(0, forest_end - forest_start))
	ok("숲 바닥 구간의 색이 전부 정본에서 온다(옛 초록 하드코딩 없음)", forest_src.find("C(\"#2b3a25\")") < 0 and forest_src.find("C(\"#4f7a34\")") < 0 and forest_src.find("pc(\"ground\"") >= 0)

	# ---------- G. 색 고르기 규칙 ----------
	var p_forest := PRender.palette_for(1, "act1_hunt_forest")
	var p_fort := PRender.palette_for(1, "act1_abandoned_fort")
	var p_boss := PRender.palette_for(3, "boss")
	ok("테마 덮어쓰기가 막 기본값 위에 얹힌다(요새는 돌 색만 다르고 나머지는 1막 기본값)",
		String(p_fort.stone) != String(p_forest.stone) and String(p_fort.tele_fill) == String(acts["1"].tele_fill))
	ok("모르는 테마(보스 전투 region_id=boss)는 그 막 기본값을 쓴다", String(p_boss.ground) == String(acts["3"].ground) and int(p_boss.act) == 3)
	var st := CombatState.first_fight(preload("res://scripts/game/game.gd").load_config(), 3)
	st.act = 2
	st.region_id = "act2_frozen_pass"
	var used := PRender.use_palette(st)
	ok("전투 상태(act·region_id)로 색 한 벌이 정해진다", String(used.ground) == String((themes["act2_frozen_pass"] as Dictionary).ground) and int(used.act) == 2, String(used.ground))

	# ---------- H. 세 막 모두 실제로 그려 본다(예고 두 겹 테두리 경로까지) ----------
	# 몬스터 12종 + 보스를 한 화면에 두고 각 막 색으로 그린다. 그리는 중 오류가 나면 실행기가 SCRIPT ERROR로 잡는다.
	var view: Node2D = Node2D.new()
	view.set_script(load("res://scripts/game/combat_view.gd"))
	view.position = Vector2(0, 40)
	root.add_child(view)
	await process_frame
	var drawn := []
	for pair in [[1, "act1_hunt_forest"], [2, "act2_frozen_pass"], [3, "act3_blood_hunt"]]:
		var sd := _demo_state(int(pair[0]), String(pair[1]))
		view.set("st", sd)
		view.set("decor", PRender.make_decor(sd))
		view.set("running", false)
		for i in 3:
			view.queue_redraw()
			await process_frame
		drawn.append("%d막 %s(적 %d·연출 %d)" % [int(pair[0]), String(pair[1]), sd.enemies.size(), sd.effects.size()])
	ok("세 막 색으로 실제 전투 화면을 그려도 오류가 없다", drawn.size() == 3, " · ".join(drawn))
	view.set("running", false)
	view.queue_free()
	await process_frame

	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

## 예고·연출이 두루 나오는 시연 상태(막·테마만 바꿔 같은 장면을 세 번 그린다)
func _demo_state(act: int, theme_id: String) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var st := CombatState.new({ "build": PBuild.derive(PBuild.empty_run_like(g)), "seed": 3, "arena": "clearing", "boss": true, "boss_id": "guardian" })
	st.act = act
	st.region_id = theme_id
	var spawns := [["wolf", 150.0, 150.0], ["wolf_alpha", 820.0, 140.0], ["archer", 120.0, 330.0], ["spore", 860.0, 300.0],
		["boar", 200.0, 520.0], ["shieldbearer", 380.0, 300.0], ["shaman", 560.0, 250.0], ["bomber", 760.0, 500.0],
		["burrower", 500.0, 400.0], ["spider", 620.0, 540.0], ["frostcaller", 860.0, 460.0], ["rogue", 330.0, 560.0]]
	for s in spawns:
		st.spawn_enemy(String(s[0]), float(s[1]), float(s[2]))
	for i in 200:
		st.step({}, 1.0 / 120.0)
	st.spawn_hold = true
	# 타격 연출·위험 장판도 함께 그린다
	st.fx({ "kind": "spark", "x": 400.0, "y": 300.0, "ttl": 0.22, "crit": true, "angle": 0.7 })
	st.fx({ "kind": "death", "x": 450.0, "y": 320.0, "r": 14.0, "ttl": 0.4, "color": "#9aa0a8" })
	st.fx({ "kind": "hitflash", "x": 480.0, "y": 340.0, "ttl": 0.25 })
	st.fx({ "kind": "impact", "x": 500.0, "y": 360.0, "r": 70.0, "ttl": 0.3 })
	st.add_zone("hazard", 300.0, 420.0, 90.0, 2.0, 5.0)
	return st
