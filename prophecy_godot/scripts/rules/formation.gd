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
			var scaled: bool = not bool(d.get("elite", false)) and not bool(d.get("boss", false)) and not bool(d.get("structure", false))
			var m_t: float = float(by_type.get(type, mult))
			var total: int = int(round(float(n) * m_t)) if scaled else n
			html_counts[type] = int(html_counts.get(type, 0)) + n
			godot_counts[type] = int(godot_counts.get(type, 0)) + total
			for i in total:
				units.append(type)
	var xp_map := {}
	var kill_mult: float = float(st.opts.get("xp_kill_mult", 0.3)) # 처치 경험치 배율(사용자 채택 ×0.3, D08). 회차가 run.balance로 넘긴다
	for type in html_counts:
		var unit := PGrowth.xp_value_unit(type, false, region_id, kill_mult)
		xp_map[type] = round(unit * float(html_counts[type]) / float(maxi(1, int(godot_counts[type]))) * 10000.0) / 10000.0
	return { "units": units, "alive_cap": int(D.alive_cap), "group": int(D.group), "interval": float(D.interval), "type_caps": D.get("type_alive_cap", {}).duplicate(), "xp_map": xp_map, "html_counts": html_counts, "godot_counts": godot_counts, "multiplier": mult, "xp_default_scale": 1.0 / mult }

## 편성 요약 문자열(HUD·보고서)
static func describe(f: Dictionary) -> String:
	var parts := []
	for type in f.get("godot_counts", {}):
		parts.append("%s %d" % [String(PCatalog.enemy(type).name), int(f.godot_counts[type])])
	return "%s · 전체 %d · 동시 %d · 묶음 %d · 간격 %.1f초" % [", ".join(parts), (f.units as Array).size(), int(f.alive_cap), int(f.group), float(f.interval)]
