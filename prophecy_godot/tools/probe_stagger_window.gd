extends SceneTree
## 적**마다** 얼마나 오래 연달아 행동하지 못했는지 잰다.
##
## 왜 따로 만들었나(사용자 지시 2026-09-09):
## 앞선 보고에서 "경직을 켠 쪽이 적 공격 실행 수가 오히려 늘었으니 경직 과잉은 없다"고 적었다.
## 그건 **총합**이다. 총합이 늘어도 특정 한 마리가 오래 묶여 있을 수 있으므로 증명이 되지 않는다.
## 그래서 여기서는 총합이 아니라 **개체별 연속 행동 불능 구간**을 본다.
##
## 행동 불능 = 그 프레임에 CombatState가 그 적의 행동 갱신을 건너뛴 것. 두 가지뿐이다.
##   · 경성 빙결(is_hard_frozen)  · 연계 완성 경직(is_staggered)
## 결빙(soft)은 패턴을 멈추지 않으므로 세지 않는다.
##
## 실행: godot --headless --path prophecy_godot -s tools/probe_stagger_window.gd

const STEP := 1.0 / 120.0
const SEC := 60.0
const SEEDS := [1, 2]

## stagger_tests의 계측 팔과 **같은 편성**을 쓴다(다른 것을 재면 앞 기록과 견줄 수 없다)
const ARMS := [
	{ "id": "sword_orb_ember", "main": "sword",
		"weapons": [["sword", 4, ["scar"]], ["orb", 3, ["conduct"]], ["ember", 3, []]],
		"commons": { "ember": 1, "flare": 1 },
		"wave": [{ "type": "wolf", "n": 4 }, { "type": "archer", "n": 2 }, { "type": "shieldbearer", "n": 1 }] },
	{ "id": "spear_wind_plague", "main": "spear",
		"weapons": [["spear", 4, []], ["wind", 3, ["focused"]], ["plague", 3, ["burst"]]], "commons": {},
		"wave": [{ "type": "wolf_alpha", "n": 2 }, { "type": "shieldbearer", "n": 3 }, { "type": "wolf", "n": 3 }] },
	{ "id": "hammer_frost_crow", "main": "hammer",
		"weapons": [["hammer", 4, ["shockwave"]], ["frost", 3, []], ["crow", 3, ["hunt"]]], "commons": {},
		"wave": [{ "type": "wolf_alpha", "n": 2 }, { "type": "shieldbearer", "n": 3 }, { "type": "wolf", "n": 3 }] },
]

func build_of(arm: Dictionary) -> Dictionary:
	var g: Dictionary = PGrowth.new_growth(String(arm.main))
	g.weapons = []
	for r in (arm.weapons as Array):
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	for k in (arm.commons as Dictionary):
		(g.commons as Dictionary)[String(k)] = int((arm.commons as Dictionary)[k])
	return PBuild.derive(PBuild.empty_run_like(g))

## 한 판. 반환 {sec, kills, max_run, worst, ratio_max, ratio_mean, n, staggers}
func run_once(arm: Dictionary, seed_v: int, stagger_on: bool) -> Dictionary:
	var b := build_of(arm)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [(arm.wave as Array).duplicate(true)], "objective": "clear", "region_id": "den", "act": 1 })
	var bot := PSkillBot.new("skilled", seed_v)
	# 적별 누적. key = e.id
	var alive := {}      # 살아 있던 시간
	var down := {}       # 행동 불능이던 시간
	var cur := {}        # 지금 이어지고 있는 불능 구간
	var best := {}       # 그 적의 가장 긴 연속 불능 구간
	var kind := {}       # 종류 이름(누가 가장 오래 묶였는지 보려고)
	var steps := int(SEC / STEP)
	var i := 0
	while i < steps and st.status == "running":
		if not stagger_on:
			for e in st.enemies:
				e["stagger_cd"] = 999.0
		st.step(bot.step_input(st), STEP)
		if not stagger_on:
			for e in st.enemies:
				e["stagger_cd"] = 999.0
		for e in st.enemies:
			if bool(e.get("dead", false)) or bool(e.get("structure", false)):
				continue
			var key := String(e.id)
			kind[key] = String(e.type)
			alive[key] = float(alive.get(key, 0.0)) + STEP
			var stuck: bool = st.is_staggered(e) or st.is_hard_frozen(e)
			if stuck:
				down[key] = float(down.get(key, 0.0)) + STEP
				cur[key] = float(cur.get(key, 0.0)) + STEP
				if float(cur[key]) > float(best.get(key, 0.0)):
					best[key] = float(cur[key])
			else:
				cur[key] = 0.0
		i += 1
	# 가장 나쁜 개체를 찾는다
	var max_run := 0.0
	var worst := "—"
	var ratio_max := 0.0
	var ratio_sum := 0.0
	var n := 0
	for key in best:
		if float(best[key]) > max_run:
			max_run = float(best[key])
			worst = String(kind.get(key, "?"))
	for key in alive:
		if float(alive[key]) < 0.5:
			continue # 너무 짧게 산 개체는 비율이 튄다
		var r: float = float(down.get(key, 0.0)) / float(alive[key])
		ratio_sum += r
		ratio_max = maxf(ratio_max, r)
		n += 1
	var ap := 0
	for k in (st.stagger_stats.applied as Dictionary):
		ap += int((st.stagger_stats.applied as Dictionary)[k])
	return { "sec": snappedf(float(st.t), 0.01), "kills": int(st.stats.kills),
		"max_run": snappedf(max_run, 0.001), "worst": worst,
		"ratio_max": snappedf(ratio_max, 0.001), "ratio_mean": snappedf(ratio_sum / maxf(1.0, float(n)), 0.001),
		"n": n, "staggers": ap, "sec_stag": snappedf(float(st.stagger_stats.sec), 0.001) }

func _init() -> void:
	print("")
	print("### 적별 연속 행동 불능 구간 (경성 빙결 + 연계 완성 경직. 결빙은 세지 않는다)")
	print("")
	print("| 편성 | 시드 | 경직 | 소요(초) | 처치 | 실제 경직 | 총 경직(초) | **최장 연속 불능(초)** | 그 개체 | 최악 개체 불능 비율 | 평균 불능 비율 | 잰 개체 수 |")
	print("|---|---:|---|---:|---:|---:|---:|---:|---|---:|---:|---:|")
	var worst_overall := 0.0
	for arm in ARMS:
		for sd in SEEDS:
			for on in [false, true]:
				var r := run_once(arm as Dictionary, int(sd), bool(on))
				if bool(on):
					worst_overall = maxf(worst_overall, float(r.max_run))
				print("| %s | %d | %s | %.2f | %d | %d | %.3f | **%.3f** | %s | %.1f%% | %.1f%% | %d |" % [
					String((arm as Dictionary).id), int(sd), ("켬" if bool(on) else "끔"),
					float(r.sec), int(r.kills), int(r.staggers), float(r.sec_stag),
					float(r.max_run), String(r.worst),
					float(r.ratio_max) * 100.0, float(r.ratio_mean) * 100.0, int(r.n)])
	print("")
	print("경직을 켠 팔의 **최장 연속 불능 구간 = %.3f초**." % worst_overall)
	print("판단 기준(시험값): 한 번의 경직이 일반 0.12초·정예 0.06초이고 재경직 제한이 0.8초이므로,")
	print("연달아 묶이더라도 한 구간이 0.2초를 넘으면 여러 효과가 이어 붙었다는 뜻이다.")
	print("빙결(1.0초)이 함께 걸린 구간은 그보다 길 수 있다 — 그건 냉기 규칙이지 경직 과잉이 아니다.")
	print("")
	print("PROBE_STAGGER_WINDOW 끝")
	quit()
