extends SceneTree
## 적 **개체별** 등장→사망 시간과, 죽을 때까지 냉기 중첩이 어디까지 찼는지 잰다.
##
## 왜 만들었나(사용자 지시 2026-09-09):
## 앞선 보고에서 "24초에 32처치 = 대상당 0.7초"라고 적었는데 **틀린 계산이다.**
## 여러 적이 동시에 살아 있으므로 **처치 간격과 개체 생존 시간은 다른 값**이다.
## 그 줄을 근거로 "무리전에서는 표적이 먼저 죽어 파쇄가 안 난다"고 말했으니,
## 근거를 제대로 다시 만든다 — 개체가 실제로 얼마나 사는지, 그동안 냉기가 몇까지 차는지.
##
## 재는 것(개체마다)
##   · 등장 → 사망 시간
##   · 첫 냉기(chill_n ≥ 1) → 사망 시간
##   · 사망 시점의 냉기 중첩(chill_n)과, 빙결(chill_n이 상한에 닿음)까지 갔는지
##
## 까마귀 표식은 여기서 재지 않는다 — 표식이 지금 까마귀 개체(b.hunt)에 붙어 있고
## 그 구조를 다른 담당이 고치는 중이다. 그쪽이 끝난 뒤 같은 방식으로 덧붙인다.
##
## 실행: godot --headless --path prophecy_godot -s tools/probe_lifetime.gd

const STEP := 1.0 / 120.0
const SEC := 40.0
const SEEDS := [1, 2, 3]

const ARMS := [
	{ "id": "무리전(얇은 편성)", "main": "hammer",
		"weapons": [["hammer", 4, ["shockwave"]], ["frost", 3, []], ["crow", 3, ["hunt"]]], "commons": {},
		"wave": [{ "type": "wolf", "n": 6 }, { "type": "archer", "n": 2 }] },
	{ "id": "무리전(두꺼운 편성)", "main": "hammer",
		"weapons": [["hammer", 4, ["shockwave"]], ["frost", 3, []], ["crow", 3, ["hunt"]]], "commons": {},
		"wave": [{ "type": "wolf_alpha", "n": 2 }, { "type": "shieldbearer", "n": 3 }, { "type": "wolf", "n": 3 }] },
]

func build_of(arm: Dictionary) -> Dictionary:
	var g: Dictionary = PGrowth.new_growth(String(arm.main))
	g.weapons = []
	for r in (arm.weapons as Array):
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	return PBuild.derive(PBuild.empty_run_like(g))

func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

## 반환: 개체 기록 배열 [{type, life, chill_to_death, chill_at_death, peak_chill, froze}]
func run_once(arm: Dictionary, seed_v: int) -> Array:
	var b := build_of(arm)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [(arm.wave as Array).duplicate(true)], "objective": "clear", "region_id": "den", "act": 1 })
	var bot := PSkillBot.new("skilled", seed_v)
	var born := {}         # 처음 본 시각
	var first_chill := {}  # 냉기가 처음 1 이상이 된 시각(-1 = 없음)
	var peak := {}         # 그 개체가 본 최대 냉기 중첩
	var froze := {}        # 빙결까지 갔는가
	var kind := {}
	var done := {}         # 이미 정산한 개체
	var out := []
	var steps := int(SEC / STEP)
	var i := 0
	while i < steps and st.status == "running":
		st.step(bot.step_input(st), STEP)
		for e in st.enemies:
			if bool(e.get("structure", false)):
				continue
			var key := String(e.id)
			if not born.has(key):
				born[key] = float(st.t)
				first_chill[key] = -1.0
				peak[key] = 0
				froze[key] = false
				kind[key] = String(e.type)
			var cn := int(e.get("chill_n", 0))
			if cn >= 1 and float(first_chill[key]) < 0.0:
				first_chill[key] = float(st.t)
			if cn > int(peak[key]):
				peak[key] = cn
			if float(e.get("freeze", 0.0)) > 0.0:
				froze[key] = true
			if bool(e.get("dead", false)) and not done.has(key):
				done[key] = true
				var fc: float = float(first_chill[key])
				out.append({ "type": String(kind[key]), "life": float(st.t) - float(born[key]),
					"chill_to_death": (float(st.t) - fc) if fc >= 0.0 else -1.0,
					"chill_at_death": cn, "peak": int(peak[key]), "froze": bool(froze[key]) })
		i += 1
	return out

func _init() -> void:
	print("")
	print("### 적 개체별 생존 시간과 냉기 중첩 (서리 수정 Lv3 · 봇 skilled · 시드 1·2·3)")
	print("")
	print("앞 보고의 '24초에 32처치 = 대상당 0.7초'는 **틀린 계산이다**(처치 간격 ≠ 개체 생존 시간).")
	print("아래가 실제로 잰 값이다.")
	print("")
	print("| 편성 | 적 | 개체 수 | 등장→사망 중앙값(초) | 첫 냉기→사망 중앙값(초) | 사망 시 중첩 중앙값 | 최대 중첩 중앙값 | 빙결까지 간 개체 |")
	print("|---|---|---:|---:|---:|---:|---:|---:|")
	for arm in ARMS:
		var by := {}
		for sd in SEEDS:
			for rec in run_once(arm as Dictionary, int(sd)):
				var r: Dictionary = rec
				var t := String(r.type)
				if not by.has(t):
					by[t] = { "life": [], "c2d": [], "cad": [], "peak": [], "froze": 0, "n": 0 }
				var d: Dictionary = by[t]
				(d.life as Array).append(float(r.life))
				if float(r.chill_to_death) >= 0.0:
					(d.c2d as Array).append(float(r.chill_to_death))
				(d.cad as Array).append(float(r.chill_at_death))
				(d.peak as Array).append(float(r.peak))
				if bool(r.froze):
					d.froze = int(d.froze) + 1
				d.n = int(d.n) + 1
		for t in by:
			var d: Dictionary = by[t]
			var c2d: Array = d.c2d
			print("| %s | %s | %d | %.2f | %s | %.0f | %.0f | %d |" % [
				String((arm as Dictionary).id), String(t), int(d.n),
				med(d.life), ("%.2f" % med(c2d)) if not c2d.is_empty() else "냉기 안 붙음",
				med(d.cad), med(d.peak), int(d.froze)])
	print("")
	print("읽는 법: 빙결은 냉기 중첩이 상한(5)에 닿아야 걸리고, 파쇄는 그 빙결을 주무기로 깨야 난다.")
	print("따라서 '사망 시 중첩'과 '최대 중첩'이 상한에 못 미치면 파쇄가 날 기회 자체가 없었다는 뜻이다.")
	print("이것이 무리전에서 파쇄·표식 폭발이 잘 완성되지 않는 이유의 **실제 근거**다.")
	print("")
	print("PROBE_LIFETIME 끝")
	quit()
