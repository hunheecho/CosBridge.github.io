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
	var kill_mult: float = float(st.opts.get("xp_kill_mult", 0.3)) # 처치 경험치 배율(사용자 채택 ×0.3, D08). 회차가 run.balance로 넘긴다
	var counts_order := []   # 분대 편성용: comp 순서를 지킨 종류 목록(정예·구조물 제외)
	var counts := {}
	var duel := {}
	for wave in waves:
		for g in wave:
			var type := String(g.type)
			var d := PCatalog.enemy(type)
			var n: int = int(g.n)
			var scaled: bool = not bool(d.get("elite", false)) and not bool(d.get("boss", false)) and not bool(d.get("structure", false)) and not g.has("ref")
			var m_t: float = float(by_type.get(type, mult))
			var total: int = int(round(float(n) * m_t)) if scaled else n # 테마 템플릿(ref 있음)은 최종 수를 명시: 배율 이중 적용 없음
			# 경험치 예산 이관(budget_from): 다른 종류의 자리를 대신 차지한 개체(일반 정예·결투 상대)는
			# **그 종류의 단위값 기준으로** 예산을 받는다. 그래야 종류를 바꿔도 전투 경험치 예산이 그대로다.
			var ref_v: float = (float(g.ref) if g.has("ref") else float(n))
			if g.has("budget_from"):
				var u_from := PGrowth.xp_value_unit(String(g.budget_from), false, region_id, kill_mult)
				var u_this := PGrowth.xp_value_unit(type, false, region_id, kill_mult)
				if u_this > 0.0:
					ref_v = ref_v * u_from / u_this
			html_counts[type] = float(html_counts.get(type, 0.0)) + ref_v # ref = 경험치 예산의 HTML 상당 수
			godot_counts[type] = int(godot_counts.get(type, 0)) + total
			if bool(g.get("duel", false)): # 결투 상대: 대기열에 넣지 않고 일반 전투가 끝난 뒤 따로 등장한다
				duel = { "type": type, "n": total }
				continue
			if not counts.has(type):
				counts[type] = 0
				counts_order.append(type)
			counts[type] = int(counts[type]) + total
			for i in total:
				units.append(type)
	var squads := []
	var spec: Dictionary = D.get("squad", {})
	if not spec.is_empty() and units.size() > 1: # 분대 편성(지시 3): 역할이 갖춰진 묶음으로 순서를 만든다
		var built := build_squads(counts_order, counts, spec)
		units = built.units
		squads = built.squads
	elif bool(D.get("squad_mix", false)): # 본편 테마 편성에만. 승인된 기준 전투·옛 지역 일정은 기존 순서 그대로
		units = mix_squads(units)
	var tiers := assign_tiers(units, st.opts.get("tier_mix", { "normal": 1.0 }))
	apply_tiers_to_squads(squads, tiers)
	var xp_map := {}
	for type in html_counts:
		var unit := PGrowth.xp_value_unit(type, false, region_id, kill_mult)
		xp_map[type] = round(unit * float(html_counts[type]) / float(maxi(1, int(godot_counts[type]))) * 10000.0) / 10000.0
	if not (override.get("alive_cap", null) == null): # 템플릿이 준 동시 상한·종류별 상한
		D.alive_cap = int(override.alive_cap)
	return { "units": units, "tiers": tiers, "squads": squads, "duel": duel, "alive_cap": int(D.alive_cap), "tail_boost": bool(D.get("tail_boost", false)), "group": int(D.group), "interval": float(D.interval), "type_caps": D.get("type_alive_cap", {}).duplicate(), "xp_map": xp_map, "html_counts": html_counts, "godot_counts": godot_counts, "multiplier": mult, "xp_default_scale": 1.0 / mult, "tier_counts": tier_counts(tiers) }

## 분대 편성(지시 3). **종류별 총 수는 그대로 두고 등장 순서와 묶음만 만든다.**
##
## 왜 있는가: 개별 몬스터를 한 마리씩 독립 추첨해 줄 세우면 "앞에서 접근 / 뒤에서 지원 / 측면·시간차"라는
## 관계가 생기지 않는다. 여기서 만드는 분대는 그 관계를 자리(slot)와 시간차(delay)로 갖는다.
##
## spec(템플릿 data/themes.json 의 squad):
##   size          — 한 분대의 최대 인원
##   slots         — 종류 → front(앞에서 접근) | support(뒤에서 지원) | flank(측면·시간차)
##   delay         — 자리 → 같은 분대 안에서 늦게 도착하는 초
##   stage_weight  — 종류 → [초반, 중반, 후반] 비중. **없으면 구간을 두지 않는다**(모든 출격에 세 구간을 강제하지 않는다)
##
## 규칙: 분대의 첫 자리는 front 가 남아 있으면 front · 한 분대의 support 비율 상한(PPacing.support_share_per_group)
## · 구간 끝에 support 만 남으면 앞 분대에 붙인다(지원병을 혼자 보내지 않는다).
static func build_squads(order: Array, counts: Dictionary, spec: Dictionary) -> Dictionary:
	var size: int = maxi(1, int(spec.get("size", 4)))
	var slots: Dictionary = spec.get("slots", {})
	var delay: Dictionary = spec.get("delay", {})
	var sw: Dictionary = spec.get("stage_weight", {})
	var max_support: int = maxi(1, int(floor(float(size) * PPacing.support_share_per_group())))
	var stage_ids := ["open", "core", "late"] if not sw.is_empty() else ["all"]
	var per_stage := []
	for si in stage_ids.size():
		per_stage.append({})
	for tp in order:
		var n: int = int(counts[tp])
		if stage_ids.size() == 1:
			(per_stage[0] as Dictionary)[tp] = n
			continue
		var w: Array = sw.get(tp, [1.0, 1.0, 1.0])
		var sum_w := 0.0
		for x in w:
			sum_w += maxf(0.0, float(x))
		var assigned := 0
		var rema := []
		for si in stage_ids.size():
			var raw: float = (float(w[si]) / sum_w * float(n)) if sum_w > 0.0 else (float(n) / float(stage_ids.size()))
			var k := int(floor(raw))
			(per_stage[si] as Dictionary)[tp] = k
			assigned += k
			rema.append([raw - float(k), si])
		rema.sort_custom(func(a, b): return float(a[0]) > float(b[0])) # 나머지는 소수부가 큰 구간부터(총 수 보존)
		var left := n - assigned
		var ri := 0
		while left > 0:
			var si2: int = int(rema[ri % rema.size()][1])
			(per_stage[si2] as Dictionary)[tp] = int((per_stage[si2] as Dictionary)[tp]) + 1
			left -= 1
			ri += 1
	var squads := []
	var units := []
	for si in stage_ids.size():
		var rem: Dictionary = per_stage[si]
		var stage := String(stage_ids[si])
		while true:
			var total_left := 0
			for tp in order:
				total_left += int(rem.get(tp, 0))
			if total_left <= 0:
				break
			var sq := { "stage": stage, "members": [] }
			var sup_n := 0
			while (sq.members as Array).size() < size:
				var pick := _pick_member(order, rem, slots, sq, sup_n, max_support)
				if pick == "":
					break
				var slot := String(slots.get(pick, "front"))
				rem[pick] = int(rem[pick]) - 1
				(sq.members as Array).append({ "type": pick, "slot": slot, "delay": float(delay.get(slot, 0.0)), "tier": "normal" })
				if slot == "support":
					sup_n += 1
			if (sq.members as Array).is_empty(): # 상한 때문에 한 명도 못 골랐다면 남은 것을 그대로 낸다(수를 잃지 않는다)
				for tp in order:
					if int(rem.get(tp, 0)) > 0:
						var sl := String(slots.get(tp, "front"))
						rem[tp] = int(rem[tp]) - 1
						(sq.members as Array).append({ "type": tp, "slot": sl, "delay": float(delay.get(sl, 0.0)), "tier": "normal" })
						break
			squads.append(sq)
	_spread_supportless(squads) # 지원만 남은 분대를 앞 분대들에 나눠 붙인다(지원병을 혼자 보내지 않는다)
	for sq in squads:
		for m in sq.members:
			units.append(String(m.type))
	return { "units": units, "squads": squads }

## 앞에서 접근하는 적이 하나도 없는 분대를 없앤다. 그 구성원을 **front 가 있는 분대들에 돌아가며** 붙여
## 한 분대가 지나치게 커지지 않게 한다. 종류별 수는 그대로다(총 등장 수 불변).
static func _spread_supportless(squads: Array) -> void:
	var hosts := []
	for sq in squads:
		for m in (sq.members as Array):
			if String(m.slot) == "front":
				hosts.append(sq)
				break
	if hosts.is_empty():
		return
	var keep := []
	var hi := 0
	for sq in squads:
		if hosts.has(sq):
			keep.append(sq)
			continue
		for m in (sq.members as Array):
			(hosts[hi % hosts.size()].members as Array).append(m)
			hi += 1
	squads.clear()
	squads.append_array(keep)

## 이 분대에 넣을 다음 한 마리. 첫 자리는 front 우선, support 는 분대 상한까지만.
## 같은 조건이면 **아직 많이 남은 종류**를 먼저(편성 비율이 구간 안에서 유지된다). 난수를 쓰지 않는다.
static func _pick_member(order: Array, rem: Dictionary, slots: Dictionary, sq: Dictionary, sup_n: int, max_support: int) -> String:
	var first: bool = (sq.members as Array).is_empty()
	var best := ""
	var best_n := -1
	for tp in order:
		var n: int = int(rem.get(tp, 0))
		if n <= 0:
			continue
		var slot := String(slots.get(tp, "front"))
		if slot == "support" and sup_n >= max_support:
			continue
		if first and slot != "front" and _has_slot_left(order, rem, slots, "front"):
			continue # 분대의 첫 자리는 앞에서 접근하는 적
		if n > best_n:
			best_n = n
			best = tp
	return best # "" = 상한 때문에 더 넣을 수 없다(분대를 끊는다)

static func _has_slot_left(order: Array, rem: Dictionary, slots: Dictionary, slot: String) -> bool:
	for tp in order:
		if int(rem.get(tp, 0)) > 0 and String(slots.get(tp, "front")) == slot:
			return true
	return false

## 등급 배정 결과를 분대 구성원에게 옮긴다(units 와 분대 구성원은 같은 순서다)
static func apply_tiers_to_squads(squads: Array, tiers: Array) -> void:
	var i := 0
	for sq in squads:
		for m in sq.members:
			if i < tiers.size():
				m.tier = String(tiers[i])
			i += 1

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
