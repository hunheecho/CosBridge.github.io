extends SceneTree
## 세계 변화 단계 × 밀도 세트 비교(헤드리스 봇): godot --headless --path prophecy_godot -s tools/stage_compare.gd → docs/sim/STAGE_COMPARE.md + STAGE_COMPARE_JSON
## 지시문 §7 필수 비교: uniform_x5/roles × 변화 전/1차/2차 편성에서 등급·정예·투사체·지면 위험의 최대 동시 수, 승률·받은 피해·전투 시간.
## 빌드는 단계에 맞는 실험실 프리셋(stage1/2/3)으로 고정(성장 차이를 배제하고 편성 차이만 본다). 봇 결과는 규칙 비교용이며 사람 난이도 승인이 아니다.
## 환경 변수: PROPHECY_SIM_SEEDS("1,2,3") PROPHECY_SIM_BOT("balanced") PROPHECY_STAGE_SORTIES("forest:2,ridge:3,den:5,deep:6")

const STEP := 1.0 / 120.0
const MAX_SEC := 240.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func make_run(seed_v: int, preset: Dictionary, density: String) -> Dictionary:
	var gw: Dictionary = preset.growth
	var first := String((gw.weapons as Array)[0].id)
	var run := PRun.new_run(seed_v, first, "", { "density_set": density })
	var g: Dictionary = run.growth
	var ws := []
	for w in gw.weapons:
		ws.append({ "id": String(w.id), "level": int(w.level), "mods": (w.mods as Array).duplicate() if w.has("mods") else [] })
	g.weapons = ws
	var cm := {}
	for k in gw.get("commons", {}):
		cm[String(k)] = int(gw.commons[k])
	g.commons = cm
	var ps := {}
	for k in gw.get("passives", {}):
		ps[String(k)] = int(gw.passives[k])
	g.passives = ps
	if gw.has("e"):
		g.skills.e = { "id": String(gw.e.id), "level": int(gw.e.level), "variant": (String(gw.e.variant) if gw.e.get("variant", null) != null else null) }
	if gw.has("q"):
		g.skills.q.level = int(gw.q.get("level", 1))
		g.skills.q.variant = String(gw.q.variant) if gw.q.get("variant", null) != null else null
	var eq: Dictionary = preset.get("equipment", {})
	for slot in eq:
		if eq[slot] != null and PCatalog.equipment().has(String(eq[slot])):
			run.equipment[String(slot)] = String(eq[slot])
	var gear: Dictionary = preset.get("gear", {})
	run.forge = int(preset.get("forge", gear.get("upgrade", 0)))
	run.hp = float(PRun.build(run).hp_max)
	return run

func fight(run: Dictionary, region: String, day: int, stage: int, pol: String, seed_v: int, risk: bool) -> Dictionary:
	run.day = day
	run.bossesDone = [] if stage == 0 else (["boss"] if stage == 1 else ["boss", "guardian"])
	run.stage = stage
	run.hp = float(PRun.build(run).hp_max)
	var s := { "regionId": region, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": seed_v * 977 + day, "day": day, "slot": 1, "variant": null }
	if risk:
		s.mission = true
		s.objective = "hunt"
		s.risk = "reinforce"
	var st := PFlow.make_encounter(run, s)
	var bot := PBot.new(pol)
	var n := 0
	while st.status == "running" and n < int(MAX_SEC / STEP):
		st.step(bot.step_input(st), STEP)
		n += 1
	var f: Dictionary = st.formation
	var elites := 0
	for u in f.units:
		if bool(PCatalog.enemy(String(u)).get("elite", false)):
			elites += 1
	return { "status": st.status, "elapsed": snapped(st.t, 0.1), "taken": snapped(st.stats.damage_taken, 0.1), "hp": snapped(st.player.hp, 0.1), "kills": st.stats.kills, "total": (f.units as Array).size(),
		"red": int(f.tier_counts.get("red", 0)), "apex": int(f.tier_counts.get("apex", 0)), "elites": elites,
		"max_alive": st.stats.max_alive, "max_dash": st.stats.max_dash_states, "max_proj": st.stats.max_enemy_projectiles, "max_zones": st.stats.max_enemy_zones, "max_webs": st.stats.max_webs,
		"dodges": st.stats.dodges, "q": st.stats.special_uses, "e": st.stats.e_uses }

func _avg(list: Array, key: String) -> float:
	var s := 0.0
	for r in list:
		s += float(r[key])
	return snapped(s / maxf(1.0, float(list.size())), 0.1)

func _max(list: Array, key: String) -> int:
	var m := 0
	for r in list:
		m = maxi(m, int(r[key]))
	return m

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1,2,3").split(","):
		seeds.append(int(s))
	var pol := _env("PROPHECY_SIM_BOT", "balanced")
	var sorties := []
	for s in _env("PROPHECY_STAGE_SORTIES", "forest:2,ridge:3,den:5,deep:6").split(","):
		var p := s.split(":")
		sorties.append([String(p[0]), int(p[1])])
	var BUILDS: Dictionary = PCatalog.lab().BUILDS
	var preset_for := { 0: "stage1", 1: "stage2", 2: "stage3" }
	var WS := PCatalog.world_stages()
	var rows := []
	var md := "# 세계 변화 단계 × 밀도 세트 비교 (%s, 봇 %s, 시드 %s)\n\n" % [Game.VERSION, pol, str(seeds)]
	md += "생성: `tools/stage_compare.gd`. 빌드는 단계별 실험실 프리셋(변화 전 stage1 / 1차 stage2 / 2차 stage3)으로 고정해 편성 차이만 본다. 등급 %s. 봇 결과는 규칙·계측 비교용이며 사람 난이도·재미 승인이 아니다. `max_proj/max_zones/max_webs` = 적 투사체·장판(포자·서리·제단)·거미줄의 최대 동시 수(동시 생존 상한이 제한하지 않는 것, 사용자 관찰 항목).\n\n" % JSON.stringify(WS.get("tiers", {}))
	md += "| 밀도 세트 | 단계 | 출격 | 위험 임무 | 전체 수(붉은/변이/정예) | 승률 | 시간 평균 | 받은 피해 평균 | 남은 체력 평균 | 최대 생존 | 최대 돌진상태 | 최대 투사체 | 최대 장판 | 최대 거미줄 | 회피/Q/E 평균 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for density in ["", "roles"]:
		var dname: String = "uniform_x5" if String(density) == "" else String(density)
		for stage in [0, 1, 2]:
			for so in sorties:
				for risk in [false, true]:
					if risk and stage < 2:
						continue # 위험 임무 정예 +1은 2단계부터
					var res := []
					for seed_v in seeds:
						var run := make_run(seed_v, BUILDS[preset_for[stage]], density)
						var r := fight(run, so[0], so[1], stage, pol, seed_v, risk)
						r.density = dname
						r.stage = stage
						r.region = so[0]
						r.day = so[1]
						r.risk = risk
						res.append(r)
						rows.append(r)
					var wins := 0
					for r in res:
						if String(r.status) == "won":
							wins += 1
					var f0: Dictionary = res[0]
					md += "| %s | %d %s | %s %d일차 | %s | %d (%d/%d/%d) | %d/%d | %.1f초 | %.1f | %.1f | %d | %d | %d | %d | %d | %.1f/%.1f/%.1f |\n" % [dname, stage, String(WS.stages[stage].name), String(PRun.region(so[0]).name), so[1], ("정예+1" if risk else "-"), int(f0.total), int(f0.red), int(f0.apex), int(f0.elites), wins, res.size(), _avg(res, "elapsed"), _avg(res, "taken"), _avg(res, "hp"), _max(res, "max_alive"), _max(res, "max_dash"), _max(res, "max_proj"), _max(res, "max_zones"), _max(res, "max_webs"), _avg(res, "dodges"), _avg(res, "q"), _avg(res, "e")]
					printerr("stage_compare: %s stage%d %s risk=%s wins %d/%d" % [dname, stage, so[0], str(risk), wins, res.size()])
	var fa := FileAccess.open("res://docs/sim/STAGE_COMPARE.md", FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("STAGE_COMPARE_JSON " + JSON.stringify(rows))
	quit()
