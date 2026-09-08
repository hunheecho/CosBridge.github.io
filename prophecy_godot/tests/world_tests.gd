extends SceneTree
## 세계 변화(붉은 달) 규칙 테스트(headless): godot --headless --path prophecy_godot -s tests/world_tests.gd
## 기대값은 사용자 합의(2026-09-07 지시문 §3)와 world.json world_stages(시험값)에서 도출. 구현 결과에 맞추지 않았다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func sortie_of(run: Dictionary, region: String, day: int, extra: Dictionary = {}) -> Dictionary:
	run.day = day
	var s := { "regionId": region, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 9, "day": day, "slot": 1, "variant": null }
	for k in extra:
		s[k] = extra[k]
	return s

func _init() -> void:
	var WS := PCatalog.world_stages()
	var TR: Dictionary = WS.tiers
	# ---------- 단계 도출: 실제 관문 완료에서만 ----------
	var run := PRun.new_run(31, "sword")
	ok("새 회차: 변화 전(0)", PRun.world_stage(run) == 0 and String(PRun.world_stage_def(run).name) == "변화 전")
	run.day = 6
	ok("날짜만 6일차가 되어도 관문을 안 깼으면 0(단순 day 증가로 전환 없음)", PRun.world_stage(run) == 0)
	run.bossesDone = ["boss"]
	ok("첫 관문(가시갈기) 완료 → 1차 변화(붉은 달)", PRun.world_stage(run) == 1 and String(PRun.world_stage_def(run).name) == "붉은 달")
	run.bossesDone = ["boss", "guardian"]
	ok("두 번째 관문(봉인 수호자) 완료 → 2차 변화", PRun.world_stage(run) == 2)
	run.bossesDone = ["guardian"]
	ok("순서가 어긋난 완료 기록(첫 관문 없이 두 번째만)은 0(도출 규칙은 순서를 요구)", PRun.world_stage(run) == 0)
	run.bossesDone = ["boss", "guardian", "eater"]
	ok("최종 보스 뒤에도 2단계 유지(3단계 없음)", PRun.world_stage(run) == 2)
	run.worldStages = false
	ok("worldStages=false 회차(옛 저장·비교용)는 항상 0", PRun.world_stage(run) == 0)
	# 전환 정확히 1회: boss_victory가 기록을 남기고, 재도전·재정산은 단계를 바꾸지 않는다
	var r2 := PRun.new_run(32, "sword")
	r2.day = 4
	r2.phase = "boss_prep"
	var bs := PRun.start_boss(r2)
	var stb := PFlow.make_boss_encounter(r2, bs)
	stb.status = "won"
	stb.boss.dead = true
	stb.stats.boss_damage = 2400.0
	var rec := PFlow.settle_boss_victory(r2, stb)
	ok("관문 승리 기록에 세계 변화 1회 기록(worldStage 1), 로그에 '세계 변화'", int(rec.get("worldStage", 0)) == 1 and PRun.world_stage(r2) == 1 and (r2.log as Array).any(func(l): return String(l).contains("세계 변화")), str(rec.get("worldStageName", "")))
	var rec2 := PFlow.settle_boss_victory(r2, stb)
	ok("같은 전투 재정산은 거부되고 단계 1 유지(중복 전환 없음)", rec2.is_empty() and PRun.world_stage(r2) == 1)
	# ---------- 등급 배정(편성) ----------
	var r3 := PRun.new_run(33, "sword")
	var f0: Dictionary = PFlow.make_encounter(r3, sortie_of(r3, "forest", 1)).formation
	ok("변화 전: 숲 1일차 45마리 전부 일반(붉은 0·변이 0) — 첫 전투 보존", int(f0.tier_counts.get("normal", 0)) == 45 and int(f0.tier_counts.get("red", 0)) == 0 and int(f0.tier_counts.get("apex", 0)) == 0, str(f0.tier_counts))
	r3.bossesDone = ["boss"]
	var f1: Dictionary = PFlow.make_encounter(r3, sortie_of(r3, "forest", 1)).formation
	ok("1차: 늑대 45 → 일반 27·붉은 18(60:40, 정수)", int(f1.tier_counts.get("normal", 0)) == 27 and int(f1.tier_counts.get("red", 0)) == 18, str(f1.tier_counts))
	var first_red := -1
	for i in (f1.tiers as Array).size():
		if String(f1.tiers[i]) == "red":
			first_red = i
			break
	ok("등장 순서 앞쪽이 일반, 뒤쪽이 붉은(첫 붉은 개체 인덱스 27)", first_red == 27)
	var f1d: Dictionary = PFlow.make_encounter(r3, sortie_of(r3, "den", 3)).formation
	var elite_tiers := []
	for i in (f1d.units as Array).size():
		if String(f1d.units[i]) == "wolf_alpha":
			elite_tiers.append(String(f1d.tiers[i]))
	ok("정예(늑대 우두머리)는 등급 배정 제외(항상 normal), 궁수 10 → 일반 6·붉은 4", elite_tiers == ["normal"] and int(f1d.tier_counts.get("red", 0)) == 16 + 4, str(f1d.tier_counts))
	r3.bossesDone = ["boss", "guardian"]
	var f2: Dictionary = PFlow.make_encounter(r3, sortie_of(r3, "forest", 6)).formation
	ok("2차: 옛 지역(숲 6일차) 재방문도 일반 0 — 붉은 60 + 변이 40(정예 1은 normal)", int(f2.tier_counts.get("normal", 0)) == 1 and int(f2.tier_counts.get("red", 0)) + int(f2.tier_counts.get("apex", 0)) == 60, str(f2.tier_counts))
	var f2f: Dictionary = PFlow.make_encounter(r3, sortie_of(r3, "forest", 1)).formation
	ok("2차 숲 1일차 편성: 늑대 45 → 붉은 27·변이 18", int(f2f.tier_counts.get("red", 0)) == 27 and int(f2f.tier_counts.get("apex", 0)) == 18, str(f2f.tier_counts))
	# 경험치 예산: 등급과 무관
	var budget := func(f: Dictionary) -> float:
		var s := 0.0
		for t in f.html_counts:
			s += float(f.xp_map[t]) * float(f.godot_counts[t])
		return s
	ok("전투 경험치 예산은 0/1/2차에서 같다(숲 1일차 16.2)", is_equal_approx(budget.call(f0), budget.call(f1)) and is_equal_approx(budget.call(f1), budget.call(f2f)) and is_equal_approx(budget.call(f0), 16.2), "%.2f/%.2f/%.2f" % [budget.call(f0), budget.call(f1), budget.call(f2f)])
	# ---------- 등급 수치(시험값): 체력·피해만, 속도·예고 그대로 ----------
	var r4 := PRun.new_run(34, "sword")
	r4.bossesDone = ["boss"]
	var st := PFlow.make_encounter(r4, sortie_of(r4, "forest", 1))
	st.spawn_hold = true
	var en := st.spawn_enemy("wolf", 300.0, 300.0, false, "red")
	var ea := st.spawn_enemy("wolf", 400.0, 300.0, false, "apex")
	var e0 := st.spawn_enemy("wolf", 500.0, 300.0, false, "normal")
	ok("붉은 늑대: 역할별 고정 체력표(H3 321 = H2 262 × √1.50), 피해 배율 1.10, 이름 접두 '붉은 ', 속도 동일", is_equal_approx(float(en.hp), PPacing.tier_hp("wolf", "red")) and is_equal_approx(float(en.tier_dmg), float(TR.red.dmg)) and String(en.name).begins_with("붉은") and float(en.def.speed) == float(e0.def.speed), "%s hp %.1f" % [String(en.name), float(en.hp)])
	ok("변이 늑대: 고정 체력표(H3 791 = H2 612 × √1.67), 피해 배율 1.20", is_equal_approx(float(ea.hp), PPacing.tier_hp("wolf", "apex")) and is_equal_approx(float(ea.tier_dmg), float(TR.apex.dmg)))
	# 2026-09-08 2차 상향: 일반 늑대는 본편에서 48(1막 기준 DPS 22 × 주력 근접 2.2초). 승인된 첫 전투의 30과는 다른 값이며 그쪽은 따로 보존한다
	ok("등급 교체 구조(사용자 결정): 일반 48 < 붉은 321 < 변이 791, 붉은 개체는 막이 바뀌어도 같은 체력(3막에서 상대적으로 쉬워지고 변이가 주력 위협)", float(e0.hp) == 48.0 and float(en.hp) < float(ea.hp) and PPacing.tier_hp("wolf", "red") == 321.0)
	var ref_st := CombatState.first_fight(preload("res://scripts/game/game.gd").load_config(), 1)
	var ref_wolf := ref_st.spawn_enemy("wolf", 300.0, 300.0)
	ok("승인된 첫 전투는 본편 체력 시험값을 적용하지 않는다(과거 비교용 고정): 기준 전투 늑대 30", is_equal_approx(float(ref_wolf.hp), 30.0), "%.1f" % float(ref_wolf.hp))
	ok("역할별로 다른 체력(성장 보정 뒤): 궁수 붉은 296 · 방패병 붉은 570 — 늑대 배율을 그대로 복제하지 않는다", PPacing.tier_hp("archer", "red") == 296.0 and PPacing.tier_hp("shieldbearer", "red") == 570.0 and PPacing.tier_hp("archer", "red") != PPacing.tier_hp("wolf", "red"))
	st.intro = 0.0
	st.damage_player(12.0, "wolf:bite", en)
	ok("붉은 늑대 물기 12 → 13.2(피해 ×1.10), 유효·명목 모두 13.2", is_equal_approx(st.stats.damage_taken, 13.2) and is_equal_approx(st.stats.damage_taken_nominal, 13.2), "%.1f" % st.stats.damage_taken)
	st.player.hit_prot = 0.0
	st.damage_player(12.0, "wolf:bite", e0)
	ok("일반 늑대는 12 그대로(합 25.2)", is_equal_approx(st.stats.damage_taken, 25.2))
	ok("등급 등장 집계: red 1·apex 1", int(st.stats.tier_spawned.get("red", 0)) == 1 and int(st.stats.tier_spawned.get("apex", 0)) == 1)
	st.kill_enemy(en, {})
	ok("등급 처치 집계: red 1", int(st.stats.tier_kills.get("red", 0)) == 1)
	var sm := st.summary()
	ok("요약에 world_stage·tier_spawned·tier_kills·잔류 투사체/장판/거미줄 최대치 포함", int(sm.world_stage) == 1 and sm.has("tier_kills") and sm.has("max_enemy_projectiles") and sm.has("max_enemy_zones") and sm.has("max_webs"))
	# 같은 붉은 개체는 1차·2차에서 같은 수치
	var r5 := PRun.new_run(35, "sword")
	r5.bossesDone = ["boss", "guardian"]
	var st5 := PFlow.make_encounter(r5, sortie_of(r5, "forest", 1))
	st5.spawn_hold = true
	var en5 := st5.spawn_enemy("wolf", 300.0, 300.0, false, "red")
	ok("2차의 붉은 늑대도 체력 37.5·피해 ×1.10(1차와 동일)", is_equal_approx(float(en5.hp), float(en.hp_max)) and is_equal_approx(float(en5.tier_dmg), float(en.tier_dmg)))
	# 4일차 정예 ×1.25는 등급과 별개로 유지, 날짜 체력 세트는 제외
	var r6 := PRun.new_run(36, "sword")
	r6.dayHpSet = "dayA"
	r6.day = 5
	var hm := PRun.hp_mult_for(r6, "den", false)
	ok("세계 변화 회차: 날짜 체력 세트(dayA 1.35)는 적용하지 않음 → 일반 ×1, 정예 ×1.25", is_equal_approx(float(hm.normal), 1.0) and is_equal_approx(float(hm.elite), 1.25), str(hm))
	r6.worldStages = false
	var hm2 := PRun.hp_mult_for(r6, "den", false)
	ok("worldStages=false면 날짜 세트가 다시 적용된다(비교용) → 5일차 dayA 일반 ×1.5", is_equal_approx(float(hm2.normal), 1.5), str(hm2))
	# ---------- 위험 임무 정예 +1 (2단계부터, 일부 전투만) ----------
	var r7 := PRun.new_run(37, "sword")
	r7.bossesDone = ["boss"]
	var s7 := sortie_of(r7, "ridge", 3, { "mission": true, "objective": "hunt", "risk": "reinforce" })
	var e1: int = int(PFlow.make_encounter(r7, s7).elite_count().total)
	r7.bossesDone = ["boss", "guardian"]
	var e2: int = int(PFlow.make_encounter(r7, s7).elite_count().total)
	ok("1차 위험 임무(정예 추적·지원병 증가): 정예 1, 2차: 정예 +1 = 2 (임무 편성은 목표 규칙이 만들므로 그 경로에 적용)", e1 == 1 and e2 == 2, "%d/%d" % [e1, e2])
	var s7n := sortie_of(r7, "ridge", 3, { "mission": true, "objective": "hunt" })
	ok("2차라도 위험 조건 없는 임무는 정예 추가 없음(1)", PFlow.make_encounter(r7, s7n).elite_count().total == 1)
	var s7c := sortie_of(r7, "ridge", 3)
	ok("2차 일반 출격(임무 아님)은 정예 추가 없음", PFlow.make_encounter(r7, s7c).elite_count().total == 0)
	# ---------- 보스전·기준 전투에는 등급 없음 ----------
	var r8 := PRun.new_run(38, "sword")
	r8.bossesDone = ["boss", "guardian"]
	r8.day = 7
	r8.phase = "boss_prep"
	r8.stage = 2
	var bs8 := PRun.start_boss(r8)
	var st8 := PFlow.make_boss_encounter(r8, bs8)
	var w8 := st8.spawn_enemy("wolf", 200.0, 200.0, true)
	ok("보스전 소환 늑대는 등급 없음(normal). 체력은 본편 일반 시험값 48", String(w8.tier) == "normal" and is_equal_approx(float(w8.hp), 48.0))
	var ff := CombatState.first_fight(PCatalog.first_fight(), 7)
	for i in 600:
		ff.step({}, STEP)
	ok("기준 전투(D33): 등급 등장 0", ff.stats.tier_spawned.is_empty() and (ff.formation.get("tiers", []) as Array).all(func(t): return String(t) == "normal"))
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
