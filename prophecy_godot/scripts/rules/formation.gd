class_name PFormation
extends RefCounted
## 편성(밀도 모델, PORT_BASELINE C4 잠정 규칙): HTML 웨이브 [[{type,n}],...]를 "종류별 전체 수 · 동시 생존 상한 · 묶음 · 간격 · 역할별 상한"으로 바꾼다.
## 일반 적은 전체 수 × multiplier(숲 1일차 새벽 5마리 → 25마리 = ×5, D33 기준 전투), 정예·구조물·보스는 그대로. 경험치 예산은 HTML 편성 기준으로 고정(마리당 = 단위값 / multiplier).
## 순서: 웨이브 순서대로 대기열에 넣어 "정예는 마지막" 같은 구성이 유지된다(종류별 상한에 걸리면 뒤 것을 먼저 꺼내되 순서는 보존).

static func from_waves(waves: Array, override: Dictionary, region_id: String, st: CombatState) -> Dictionary:
	var D := PCatalog.density().duplicate(true)
	for k in override:
		D[k] = override[k]
	var mult := float(D.multiplier)
	var by_type: Dictionary = D.get("multiplier_by_type", {}) # 역할별 배율 후보(Q1 비교 세트). 없으면 일괄 배율
	var units := []
	var html_counts := {}
	var godot_counts := {}
	for wave in waves:
		for g in wave:
			var type := String(g.type)
			var d := PCatalog.enemy(type)
			var n: int = int(g.n)
			var scaled: bool = not bool(d.get("elite", false)) and not bool(d.get("boss", false)) and not bool(d.get("structure", false)) and not g.has("ref")
			var m_t: float = float(by_type.get(type, mult))
			var total: int = int(round(float(n) * m_t)) if scaled else n # 테마 템플릿(ref 있음)은 최종 수를 명시: 배율 이중 적용 없음
			html_counts[type] = float(html_counts.get(type, 0.0)) + (float(g.ref) if g.has("ref") else float(n)) # ref = 경험치 예산의 HTML 상당 수
			godot_counts[type] = int(godot_counts.get(type, 0)) + total
			for i in total:
				units.append(type)
	var tiers := assign_tiers(units, st.opts.get("tier_mix", { "normal": 1.0 }))
	var xp_map := {}
	var kill_mult: float = float(st.opts.get("xp_kill_mult", 0.3)) # 처치 경험치 배율(사용자 채택 ×0.3, D08). 회차가 run.balance로 넘긴다
	for type in html_counts:
		var unit := PGrowth.xp_value_unit(type, false, region_id, kill_mult)
		xp_map[type] = round(unit * float(html_counts[type]) / float(maxi(1, int(godot_counts[type]))) * 10000.0) / 10000.0
	if not (override.get("alive_cap", null) == null): # 템플릿이 준 동시 상한·종류별 상한
		D.alive_cap = int(override.alive_cap)
	return { "units": units, "tiers": tiers, "alive_cap": int(D.alive_cap), "group": int(D.group), "interval": float(D.interval), "type_caps": D.get("type_alive_cap", {}).duplicate(), "xp_map": xp_map, "html_counts": html_counts, "godot_counts": godot_counts, "multiplier": mult, "xp_default_scale": 1.0 / mult, "tier_counts": tier_counts(tiers) }

## 등급 배정(세계 변화, 사용자 합의 2026-09-07): 종류별로 정수 편성. mix 비율 순서(normal→red→apex)로 등장 순서의 앞쪽이 낮은 등급, 뒤쪽이 높은 등급.
## 정예·구조물·보스는 항상 "normal"(등급은 정예와 별개). 경험치 단위값은 등급과 무관(예산 고정).
static func assign_tiers(units: Array, mix: Dictionary) -> Array:
	var order := ["normal", "red", "apex"]
	var per_type := {}
	for i in units.size():
		var t := String(units[i])
		if not per_type.has(t):
			per_type[t] = []
		(per_type[t] as Array).append(i)
	var tiers := []
	tiers.resize(units.size())
	for i in units.size():
		tiers[i] = "normal"
	for t in per_type:
		var d := PCatalog.enemy(t)
		var idxs: Array = per_type[t]
		if bool(d.get("elite", false)) or bool(d.get("boss", false)) or bool(d.get("structure", false)):
			continue
		var n := idxs.size()
		var counts := {}
		var assigned := 0
		var last_key := "normal"
		for k in order: # 정수 배정: 비율×n 반올림, 마지막 등급이 나머지를 받는다
			if not mix.has(k) or float(mix[k]) <= 0.0:
				continue
			counts[k] = int(round(float(mix[k]) * float(n)))
			assigned += counts[k]
			last_key = k
		counts[last_key] = int(counts.get(last_key, 0)) + (n - assigned)
		var pos := 0
		for k in order:
			if not counts.has(k):
				continue
			for j in int(counts[k]):
				if pos < n:
					tiers[idxs[pos]] = k
					pos += 1
	return tiers

static func tier_counts(tiers: Array) -> Dictionary:
	var out := {}
	for t in tiers:
		out[String(t)] = int(out.get(String(t), 0)) + 1
	return out

## 편성 요약 문자열(HUD·보고서)
static func describe(f: Dictionary) -> String:
	var parts := []
	for type in f.get("godot_counts", {}):
		parts.append("%s %d" % [String(PCatalog.enemy(type).name), int(f.godot_counts[type])])
	var tc: Dictionary = f.get("tier_counts", {})
	var tier_txt := ""
	if int(tc.get("red", 0)) > 0 or int(tc.get("apex", 0)) > 0:
		tier_txt = " · 붉은 %d · 변이 %d" % [int(tc.get("red", 0)), int(tc.get("apex", 0))]
	return "%s · 전체 %d · 동시 %d · 묶음 %d · 간격 %.1f초%s" % [", ".join(parts), (f.units as Array).size(), int(f.alive_cap), int(f.group), float(f.interval), tier_txt]
