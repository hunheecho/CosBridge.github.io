extends SceneTree
## 테마 경로(10일·3막) 규칙 테스트(headless): 카탈로그 정합성, 경로 추첨·고정, 장소·편성 템플릿(배율 이중 적용 없음·예산), 전장, 보상 태그, 관문 보스 연동, 미리보기.
## 기준: prophecy-act-themes-plan-20260907 §4·§5·§6·§8(구조는 사용자 결정, 수치는 시험값). 구현된 테마 = 보스가 구현된 테마(3 → 6 → 9).

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func sortie_of(run: Dictionary, region: String, day: int, fid: String = "", risk: bool = false) -> Dictionary:
	run.day = day
	var s := { "regionId": region, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 9, "day": day, "slot": 1, "variant": null }
	if fid != "":
		s.formationId = fid
	if risk:
		s.mission = true
		s.objective = "hunt"
		s.risk = "reinforce"
	return s

func _init() -> void:
	var T := PCatalog.themes()
	# ---------- 카탈로그 정합성(계획서 §12 정적 검증) ----------
	var per_act := { 1: 0, 2: 0, 3: 0 }
	var bad := []
	for tid in T:
		var t: Dictionary = T[tid]
		per_act[int(t.act)] = int(per_act[int(t.act)]) + 1
		if (t.places as Array).size() != 2 or int((t.places as Array)[0].cost) != 1 or int((t.places as Array)[1].cost) != 2:
			bad.append(tid + ":places")
		if (t.formations.normal as Array).size() < 3 or (t.formations.risk as Array).size() < 1:
			bad.append(tid + ":formations")
		for p in t.places:
			if PCatalog.arena(String(p.arena)).is_empty():
				bad.append(tid + ":arena:" + String(p.arena))
		for f in (t.formations.normal as Array) + (t.formations.risk as Array):
			for c in f.comp:
				if PCatalog.enemy(String(c.type)).is_empty() or bool(PCatalog.enemy(String(c.type)).get("elite", false)):
					bad.append(tid + ":type:" + String(c.type))
	ok("테마 9종: 막마다 3, 장소 2(1칸·2칸), 일반 편성 3 + 위험 1, 전장 존재, 일반 적만(정예는 elites 필드)", T.size() == 9 and per_act[1] == 3 and per_act[2] == 3 and per_act[3] == 3 and bad.is_empty(), str(bad))
	var impl := []
	for act in [1, 2, 3]:
		impl.append(PRun.themes_for_act(act))
	var n_impl: int = impl[0].size() + impl[1].size() + impl[2].size()
	ok("구현된 테마(보스 정의 존재) 막마다 1개 이상, 총 %d(3·6·9 단계)" % n_impl, impl[0].size() >= 1 and impl[1].size() >= 1 and impl[2].size() >= 1, str(impl))
	ok("기본 테마(사냥 숲·붉은 의식터·시간의 심연)는 기존 보스로 항상 구현", PRun.theme_implemented("act1_hunt_forest") and PRun.theme_implemented("act2_crimson_ritual") and PRun.theme_implemented("act3_temporal_abyss"))
	# ---------- 경로 추첨·고정 ----------
	var run := PRun.new_run(61, "sword")
	ok("새 회차 경로 3개(막별 1테마), 막 순서대로, 구현된 테마만", (run.route as Array).size() == 3 and int(PCatalog.theme(String(run.route[0])).act) == 1 and int(PCatalog.theme(String(run.route[1])).act) == 2 and int(PCatalog.theme(String(run.route[2])).act) == 3 and (run.route as Array).all(func(t): return PRun.theme_implemented(String(t))), str(run.route))
	ok("같은 시드 = 같은 경로(재추첨 없음), 보스 계획 = 경로 테마의 보스", PRun.new_run(61, "sword").route == run.route and (run.bossPlan as Array).map(func(b): return String(b)) == (run.route as Array).map(func(t): return String(PCatalog.theme(String(t)).boss)), str(run.bossPlan))
	var routes_seen := {}
	for s in range(100, 130):
		routes_seen[str(PRun.new_run(s, "sword").route)] = true
	var n_routes: int = impl[0].size() * impl[1].size() * impl[2].size()
	ok("30시드에서 서로 다른 경로 수 ≤ 가능 경로 수(%d), 후보가 2개 이상인 막이 있으면 2가지 이상" % n_routes, routes_seen.size() <= n_routes and (n_routes == 1 or routes_seen.size() >= 2), str(routes_seen.keys()))
	var forced := PRun.new_run(62, "sword", "", { "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	ok("검증 메뉴 경로 지정(opts.route)은 합법적 테마면 그대로", forced.route == ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"])
	var bad_route := PRun.new_run(63, "sword", "", { "route": ["act3_temporal_abyss", "act1_hunt_forest", "nope"] })
	ok("잘못된 막 배정·미구현 테마 지정은 무시하고 시드 추첨으로", int(PCatalog.theme(String(bad_route.route[0])).act) == 1 and int(PCatalog.theme(String(bad_route.route[2])).act) == 3)
	ok("trio(옛 7일) 회차는 경로 없음(기존 지역 일정)", (PRun.new_run(64, "sword", "", { "mode": "trio" }).route as Array).is_empty() and PRun.places_for(PRun.new_run(64, "sword", "", { "mode": "trio" }), 1) == ["forest", "ridge"])
	# ---------- 장소·일정 ----------
	var th1 := PRun.route_theme(forced, 1)
	var p1 := String(th1.places[0].id)
	var p2 := String(th1.places[1].id)
	ok("1~3일차 장소 = 1막 테마의 두 장소(1칸·2칸), 10일차 없음", PRun.places_for(forced, 1) == [p1, p2] and PRun.places_for(forced, 3) == [p1, p2] and PRun.places_for(forced, 10).is_empty() and PRun.place_cost(p1) == 1 and PRun.place_cost(p2) == 2)
	ok("장소 이름·보상·전장이 지역 규칙으로 읽힌다", String(PRun.region(p1).name) == "숲길" and int(PRun.region(p1).reward.gold[0]) == 30 and PRun.region_arena(p1, forced) == "clearing" and PRun.region_arena(String(PRun.route_theme(forced, 2).places[1].id), forced) == "ritual_center")
	ok("상단 표시: '1막 · 사냥 숲', 관문 준비 미리보기에 다음 테마 이름", PRun.act_label(forced, 1) == "1막 · 사냥 숲")
	for i in 3:
		PRun.end_day(forced)
	var ap := PRun.act_preview(forced)
	ok("4일차 관문 미리보기: 2막 테마(붉은 의식터) 장소 2·대표 적·보스 봉인 수호자", String(ap.theme.id) == "act2_crimson_ritual" and (ap.places as Array).size() == 2 and String(ap.gate.id) == "guardian", "theme=%s places=%s gate=%s" % [str(ap.get("theme", {}).get("id", "")), str(ap.get("places", [])), str(ap.get("gate", {}))])
	# ---------- 편성 템플릿: 최종 수 명시, 배율 이중 적용 없음, 예산 ----------
	var r5 := PRun.new_run(65, "sword", "", { "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	var opts1 := PRun.formation_options(p1, 2)
	ok("숲길 편성 후보(2일차) = 일반 템플릿 3(위험 아님)", opts1.size() == 3 and String(opts1[0].id) == "t1a_wolves")
	var opts_d1 := PRun.formation_options(p1, 1)
	ok("첫날 숲길은 승인된 기준 전투 템플릿 하나로 고정(t1a_first)", opts_d1.size() == 1 and String(opts_d1[0].id) == "t1a_first")
	var r_first := PRun.new_run(67, "sword", "", { "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	var c_first: Dictionary = PSortie.cards_for(r_first)[0]
	var s_first := PSortie.start(r_first, String(c_first.id))
	var st_first := PFlow.make_encounter(r_first, s_first)
	var xp_first := 0.0
	for t in st_first.formation.html_counts:
		xp_first += float(st_first.formation.xp_map[t]) * float(st_first.formation.godot_counts[t])
	ok("첫날 새벽 숲길 출격 = 늑대 25·동시 12·경험치 예산 9.0(D33 보존), 전장 공터", String(c_first.formationId) == "t1a_first" and (st_first.formation.units as Array).size() == 25 and int(st_first.formation.godot_counts.wolf) == 25 and int(st_first.formation.alive_cap) == 12 and is_equal_approx(snapped(xp_first, 0.01), 9.0) and st_first.arena_id == "clearing", "units %d cap %d xp %.2f" % [(st_first.formation.units as Array).size(), int(st_first.formation.alive_cap), xp_first])
	var st1 := PFlow.make_encounter(r5, sortie_of(r5, p1, 1, "t1a_wolves"))
	var f1: Dictionary = st1.formation
	ok("숲길 '늑대 무리 + 궁수'(1일차): 전체 25 = 날짜 예산표(사용자 결정 25), 늑대 20·궁수 5(0.8/0.2), 동시 12(1막 상한), 궁수 상한 3, 배율 1(밀도 세트 무시)", (f1.units as Array).size() == 25 and int(f1.godot_counts.wolf) == 20 and int(f1.godot_counts.archer) == 5 and int(f1.alive_cap) == 12 and int(f1.type_caps.get("archer", 0)) == 3 and is_equal_approx(float(f1.multiplier), 1.0), str(f1.godot_counts) + " cap %d" % int(f1.alive_cap))
	r5.densitySet = "roles"
	var st1b := PFlow.make_encounter(r5, sortie_of(r5, p1, 1, "t1a_wolves"))
	ok("밀도 세트 roles를 골라도 테마 템플릿 수는 같다(이중 적용 없음)", (st1b.formation.units as Array).size() == 25)
	r5.densitySet = ""
	var xp1 := 0.0
	for t in f1.html_counts:
		xp1 += float(f1.xp_map[t]) * float(f1.godot_counts[t])
	ok("경험치 예산 = 기준 9(늑대 7.2 상당 + 궁수 1.8 상당) × 단위값: 늑대 6×1×0.3×7.2 + 궁수 7×1×0.3×1.8 = 16.74", is_equal_approx(snapped(xp1, 0.01), 16.74), "%.2f" % xp1)
	var st2 := PFlow.make_encounter(r5, sortie_of(r5, p2, 2, "t1a_boar"))
	ok("사냥터 안쪽(2칸, 2일차) '늑대 + 멧돼지': 전체 32 = 30×1.07(핵심 장소 +7%), 동시 12(1막), 전장 forest", (st2.formation.units as Array).size() == 32 and int(st2.formation.alive_cap) == 12 and st2.arena_id == "forest", "%d/%d" % [(st2.formation.units as Array).size(), int(st2.formation.alive_cap)])
	var opts_r := PRun.formation_options(p1, 1, true)
	ok("위험 임무 카드는 위험 템플릿(우두머리 포함)", opts_r.size() == 1 and String(opts_r[0].id) == "t1a_risk")
	# 카드 생성: 테마 장소 카드에 편성 이름, 같은 장소 직전 편성 회피
	r5.day = 2
	r5.cards = null
	var cards := PSortie.cards_for(r5)
	ok("2일차 카드 2장 = 숲길·사냥터 안쪽, 편성 이름 있음", cards.size() == 2 and String(cards[0].regionId) == p1 and String(cards[1].regionId) == p2 and String(cards[0].formationName) != "", str(cards.map(func(c): return [c.regionId, c.formationId])))
	# 세계 변화 등급은 템플릿에도 적용
	r5.bossesDone = ["boss", "guardian"]
	r5.stage = 2
	var st3 := PFlow.make_encounter(r5, sortie_of(r5, String(PRun.route_theme(r5, 3).places[0].id), 7, "t3a_archer_burrow"))
	var t3n: int = (st3.formation.units as Array).size()
	ok("3막 템플릿(7일차 1칸 = 55): 2차 변화라 일반 0, 붉은 60%·변이 40%", int(st3.formation.tier_counts.get("normal", 0)) == 0 and t3n == 55 and int(st3.formation.tier_counts.get("red", 0)) + int(st3.formation.tier_counts.get("apex", 0)) == t3n and int(st3.formation.tier_counts.get("red", 0)) > int(st3.formation.tier_counts.get("apex", 0)), "%d %s" % [t3n, str(st3.formation.tier_counts)])
	# 날짜별 총 등장 수(사용자 결정 25 → 75): 1일 25 … 9일 70, 9일차 핵심 장소 75. 10일차는 최종 관문 전용이라 일반 전투 없음
	var day_tbl := []
	for d in range(1, 10):
		day_tbl.append(PPacing.day_total(d, 1))
	ok("날짜 예산표 1~9일: 25/30/35/40/45/50/55/60/70, 9일차 핵심(2칸) 75", day_tbl == [25, 30, 35, 40, 45, 50, 55, 60, 70] and PPacing.day_total(9, 2) == 75, str(day_tbl))
	ok("막별 동시 상한(시험값) 1막 12·2막 15·3막 18, legacy 대조군은 템플릿 값 유지", PPacing.alive_cap(1, 99) == 12 and PPacing.alive_cap(2, 99) == 15 and PPacing.alive_cap(3, 99) == 18 and PPacing.alive_cap(2, 99, "legacy") == 99)
		# 보상 태그 1.15
	var run_t := PRun.new_run(66, "sword", "", { "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	run_t.growth.pendingLevelUps = 1
	var cands := PGrowth.candidates(run_t, { "pool": "level", "region_id": p1 })
	var matched := cands.filter(func(c): return bool(c.get("regionMatch", false)))
	var w_m: float = PGrowth.weight_of(run_t.growth, matched[0]) if matched.size() > 0 else 0.0
	var w_same: float = float(PCatalog.growth().WEIGHTS.base.get(String(matched[0].kind), 1.0)) * (float(PCatalog.growth().WEIGHTS.early.get(String(matched[0].kind), 1.0)) if int(run_t.growth.level) <= int(PCatalog.growth().WEIGHTS.early.untilLevel) and PCatalog.growth().WEIGHTS.early.has(String(matched[0].kind)) else 1.0) if matched.size() > 0 else 0.0
	ok("테마 장소 후보의 태그 일치 가중치 = 기본 × 1.15(지역 태그 보정과 이중 곱 없음)", matched.size() > 0 and is_equal_approx(w_m, w_same * 1.15), "%.3f vs %.3f" % [w_m, w_same * 1.15])
	# 재료·사건 보급소
	ok("장소 재료: 숲길 가죽 1~2, 사냥터 안쪽 송곳니 0~1(정예 보상 후보)", (PRun.region(p1).reward.mats as Dictionary).has("pelt") and (PRun.region(p2).reward.mats as Dictionary).has("fang"))
	# 봇 완주(경로 고정, 기존 보스)
	var rec := PRunBot.simulate(2, "gradual", { "start": "sword", "bot_policy": "balanced", "max_retries": 3, "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	# 봇 승패는 통과 조건이 아니다(2026-09-08 체력·성장 개편 뒤 값은 전부 시험값이며, 봇이 지는 것 자체는 결함이 아니다).
	# 여기서 보는 것은 구조다: 회차가 날짜를 진행하고, 관문에서 실제로 싸우고, 규칙대로 끝나는가.
	ok("봇 gradual 시드 2, 기본 3테마 경로: 날짜 진행·관문 교전·규칙대로 종료(승패는 조건 아님)",
		int(rec.get("day", 0)) >= 4 and String(rec.get("boss", "")) != "" and (bool(rec.get("cleared", false)) or String(rec.get("boss", "")).contains("lost")),
		JSON.stringify({ "cleared": rec.get("cleared"), "day": rec.get("day"), "level": rec.get("level"), "boss": rec.get("boss", "") }))
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
