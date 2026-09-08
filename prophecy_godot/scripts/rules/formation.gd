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
	if bool(D.get("squad_mix", false)): # 본편 테마 편성에만. 승인된 기준 전투·옛 지역 일정은 기존 순서 그대로
		units = mix_squads(units)
	var tiers := assign_tiers(units, st.opts.get("tier_mix", { "normal": 1.0 }))
	var xp_map := {}
	var kill_mult: float = float(st.opts.get("xp_kill_mult", 0.3)) # 처치 경험치 배율(사용자 채택 ×0.3, D08). 회차가 run.balance로 넘긴다
	for type in html_counts:
		var unit := PGrowth.xp_value_unit(type, false, region_id, kill_mult)
		xp_map[type] = round(unit * float(html_counts[type]) / float(maxi(1, int(godot_counts[type]))) * 10000.0) / 10000.0
	if not (override.get("alive_cap", null) == null): # 템플릿이 준 동시 상한·종류별 상한
		D.alive_cap = int(override.alive_cap)
	return { "units": units, "tiers": tiers, "alive_cap": int(D.alive_cap), "tail_boost": bool(D.get("tail_boost", false)), "group": int(D.group), "interval": float(D.interval), "type_caps": D.get("type_alive_cap", {}).duplicate(), "xp_map": xp_map, "html_counts": html_counts, "godot_counts": godot_counts, "multiplier": mult, "xp_default_scale": 1.0 / mult, "tier_counts": tier_counts(tiers) }

## 혼합 분대 배치(지시 4): 종류별 수는 그대로 두고 등장 순서만 비율에 맞춰 고르게 섞는다.
## 같은 묶음에 근접 호위와 지원 적이 함께 나오고, 마지막에 지원 적만 하나씩 충원되는 순서를 없앤다.
## 묶음의 첫 자리는 근접이 남아 있으면 근접이 먼저 나온다(궁수·주술사가 근접 압박 뒤에서 쏘도록).
## 정예·구조물은 원래 순서(뒤쪽)를 지킨다. 한 종류만 있는 편성(승인된 첫 전투)은 그대로다.
static func mix_squads(units: Array) -> Array:
	if not PPacing.squad_mixing() or units.size() <= 1:
		return units
	var order := []
	var queues := {}
	var tail := [] # 정예·구조물: 순서 보존(정예는 마지막)
	for u in units:
		var tp := String(u)
		var d := PCatalog.enemy(tp)
		if bool(d.get("elite", false)) or bool(d.get("structure", false)) or bool(d.get("boss", false)):
			tail.append(tp)
			continue
		if not queues.has(tp):
			queues[tp] = 0
			order.append(tp)
		queues[tp] = int(queues[tp]) + 1
	if order.size() <= 1:
		return units
	var total := 0
	for tp in order:
		total += int(queues[tp])
	var emitted := {}
	for tp in order:
		emitted[tp] = 0
	var out := []
	var group_n: int = maxi(1, int(PCatalog.density().get("group", 3)))
	var max_support: int = maxi(1, int(floor(float(group_n) * PPacing.support_share_per_group())))
	var in_group := 0
	var support_in_group := 0
	while out.size() < total:
		var best := ""
		var best_score := -1.0
		var best_support := false
		for tp in order:
			if int(emitted[tp]) >= int(queues[tp]):
				continue
			var sup := PPacing.is_support(tp)
			if sup and support_in_group >= max_support:
				continue # 한 묶음의 지원 적 비율 상한
			if in_group == 0 and sup and _has_melee_left(order, queues, emitted):
				continue # 묶음의 첫 자리는 근접 호위 먼저
			# 비례 공정 배분: 아직 덜 낸 종류를 먼저(같으면 편성 순서)
			var share: float = float(queues[tp]) / float(total)
			var score: float = share * float(out.size() + 1) - float(emitted[tp])
			if score > best_score + 1e-9:
				best_score = score
				best = tp
				best_support = sup
		if best == "":
			for tp in order: # 상한 때문에 못 고르면 묶음을 끊고 다시 시도
				if int(emitted[tp]) < int(queues[tp]):
					best = tp
					best_support = PPacing.is_support(tp)
					break
			if best == "":
				break
			in_group = 0
			support_in_group = 0
		out.append(best)
		emitted[best] = int(emitted[best]) + 1
		in_group += 1
		if best_support:
			support_in_group += 1
		if in_group >= group_n:
			in_group = 0
			support_in_group = 0
	for tp in tail:
		out.append(tp)
	return out

static func _has_melee_left(order: Array, queues: Dictionary, emitted: Dictionary) -> bool:
	for tp in order:
		if int(emitted[tp]) < int(queues[tp]) and not PPacing.is_support(String(tp)):
			return true
	return false

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
