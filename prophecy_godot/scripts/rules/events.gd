class_name PEvents
extends RefCounted
## 탐험 사건 6종(HTML events.js 이식): 전투 뒤 안전 화면, 출격당 최대 1회. 시드로 생성·저장(run.pendingSortie)·재현. 비용·보상은 정확히 1회 정산. 화면·봇 공용.
## HTML의 `valid` 람다는 데이터에서 빠졌으므로 여기(_valid)에 같은 조건으로 둔다.
## 사건 dict: { id, seed, resolved, choice(null|String), cardId?, fromRisk?, toRisk?, service? }

static func E() -> Dictionary: return PCatalog.events()

static func altar_cost(run: Dictionary) -> int:
	return int(round(float(PRun.build(run).hp_max) * float(E().weapon_altar.hpCost)))

## 위험 조건 교체 후보: [null] + risks 중 현재와 다른 것, seed로 선택
static func next_risk(cur: Variant, seed_v: int) -> Variant:
	var list := [null]
	for r in PCatalog.mission_rules().risks:
		list.append(String(r))
	var out := []
	for r in list:
		if not (r == null and cur == null) and not (r != null and cur != null and String(r) == String(cur)):
			out.append(r)
	return out[seed_v % out.size()]

## HTML EVENTS[id].valid(run, sortie)
static func _valid(id: String, run: Dictionary, s: Dictionary) -> bool:
	match id:
		"weapon_altar":
			return PSortie.kind_valid(run, "weapon_mod") and float(altar_cost(run)) < float(run.hp) - 1.0
		"supply":
			var last: int = -9 if run.get("lastSupplyDay", null) == null else int(run.lastSupplyDay)
			return int(run.day) - last >= 2
		"merchant":
			return not bool(s.get("mission", false)) and not bool(s.get("deep", false)) and float(run.hp) >= float(PRun.build(run).hp_max) * 0.35
		"time_spring":
			return true
		"sealed_loot":
			return not bool(s.get("deep", false)) and not bool(s.get("mission", false)) and PRun.can_deep_explore(run, s)
		"scout":
			return not _other_cards(run, s).is_empty()
	return false

static func _other_cards(run: Dictionary, s: Dictionary) -> Array:
	var out := []
	var cid := String(s.get("cardId", ""))
	for c in PSortie.cards_for(run):
		if not bool(c.done) and String(c.id) != cid:
			out.append(c)
	return out

## 사건 생성(결정적): 출격 시드 기준. 같은 출격에서 다시 굴려도 같은 결과. 직전 사건과 같은 종류는 피한다. 없으면 null
static func roll(run: Dictionary, sortie: Dictionary) -> Variant:
	if sortie.get("event", null) != null or bool(sortie.get("deep", false)) or sortie.get("eventFight", null) != null:
		return null
	var rng := PRng.new((int(sortie.seed) * 13 + 101 + int(sortie.get("encounters", 0)) * 7) & 0xFFFFFFFF)
	if rng.next() >= float(E().chance):
		return null
	var valid := []
	var last = run.get("lastEvent", null)
	for id in PCatalog.event_ids():
		if _valid(String(id), run, sortie) and not (last != null and String(last) == String(id)):
			valid.append(String(id))
	if valid.is_empty():
		return null
	var id: String = valid[rng.int_range(0, valid.size() - 1)]
	var ev := { "id": id, "seed": rng.int_range(0, 1000000000), "resolved": false, "choice": null }
	if id == "scout":
		var cards := _other_cards(run, sortie)
		var c: Dictionary = cards[int(ev.seed) % cards.size()]
		ev.cardId = String(c.id)
		ev.fromRisk = c.risk
		ev.toRisk = next_risk(c.risk, int(ev.seed) >> 3)
	if id == "merchant":
		ev.service = String(E().merchant.services[int(ev.seed) % 2])
	return ev

static func _risk_text(r: Variant) -> String:
	return String(PCatalog.mission_rules().riskText[String(r)]) if r != null else "없음"

## 선택지(화면·봇 공용): [{id, name, cost, effect, enabled}]
static func options(run: Dictionary, sortie: Dictionary) -> Array:
	var out := []
	var ev = sortie.get("event", null)
	if ev == null:
		return out
	var b := PRun.build(run)
	var hp: float = float(run.hp)
	var hp_max: float = float(b.hp_max)
	match String(ev.id):
		"weapon_altar":
			var cost := altar_cost(run)
			out.append({ "id": "pay", "name": "체력 %d을 바치고 개조 3택" % cost, "cost": "체력 -%d (%d → %d)" % [cost, int(hp), int(hp) - cost], "effect": "보유 무기 개조 3택(유효 후보만)", "enabled": hp - float(cost) > 1.0 and PSortie.kind_valid(run, "weapon_mod") })
			out.append({ "id": "leave", "name": "지나친다", "cost": "없음", "effect": "없음", "enabled": true })
		"supply":
			var heal := int(round(hp_max * float(E().supply.heal)))
			var mat := _supply_mat(String(sortie.regionId))
			out.append({ "id": "heal", "name": "치료 (+%d)" % heal, "cost": "없음", "effect": "체력 %d → %d" % [int(hp), int(minf(hp_max, hp + float(heal)))], "enabled": hp < hp_max })
			out.append({ "id": "loot", "name": "물자 (금화 +%d%s)" % [int(E().supply.gold), (", " + String(PCatalog.materials()[mat].name) + " +1") if mat != "" else ""], "cost": "없음", "effect": "이번 출격 전리품에 추가(귀환 시 확정)", "enabled": true })
			out.append({ "id": "leave", "name": "지나친다", "cost": "없음", "effect": "없음", "enabled": true })
		"merchant":
			var S: Dictionary = PCatalog.services().get(String(ev.service), {})
			out.append({ "id": "fight", "name": "상인을 구한다 (추가 전투)", "cost": "지역 웨이브 + 정예 1, 체력 회복 없음(%d/%d), 패배 시 이번 출격 전리품 상실" % [int(hp), int(hp_max)],
				"effect": "승리 시 해금: %s — %s. 새 전리품·재료 없음" % [String(S.get("name", ev.service)), String(S.get("desc", ""))], "enabled": true })
			out.append({ "id": "leave", "name": "지나친다", "cost": "없음", "effect": "없음", "enabled": true })
		"time_spring":
			var has_buff: bool = (run.get("buffs", {}) as Dictionary).has("skillCd")
			out.append({ "id": "buff", "name": "샘물을 마신다 (다음 전투 강화)", "cost": "없음", "effect": "다음 전투 1회: 감속장·E 재사용 ×0.7", "enabled": not has_buff })
			out.append({ "id": "heal", "name": "치료를 받는다 (1시간)", "cost": "시간 -1 (%d → %d)" % [int(run.hours), int(run.hours) - 1], "effect": "체력 %d → %d" % [int(hp), int(hp_max)], "enabled": int(run.hours) >= int(E().time_spring.hours) and hp < hp_max })
			out.append({ "id": "leave", "name": "지나친다", "cost": "없음", "effect": "없음", "enabled": true })
		"sealed_loot":
			var tag_text := String(PCatalog.region_tag_text().get(String(sortie.regionId), ""))
			out.append({ "id": "fight", "name": "봉인을 깨러 간다 (더 깊이 탐험, 1시간)", "cost": "시간 -1 (%d → %d), 적 수 +1·마지막에 정예" % [int(run.hours), int(run.hours) - 1],
				"effect": "밝혀진 보상: 금화 ×%d(더 깊이 ×%s 위에) + 지역 보상 3택 1회 (%s)" % [int(E().sealed_loot.goldMult), str(float(PCatalog.config().DEEP_REWARD_MULT)), tag_text], "enabled": PRun.can_deep_explore(run, sortie) })
			out.append({ "id": "leave", "name": "전리품을 가지고 귀환", "cost": "없음", "effect": "현재 전리품 유지", "enabled": true })
		"scout":
			var c := PSortie.card(run, String(ev.cardId))
			var label: String = ("%s · %s" % [String(PRun.region(String(c.regionId)).name), PSortie.objective_name(String(c.objective))]) if not c.is_empty() else String(ev.cardId)
			var to_txt := _risk_text(ev.toRisk) + ((" (금화 ×%s)" % str(float(PCatalog.mission_rules().riskRewardMult))) if ev.toRisk != null else "")
			out.append({ "id": "swap", "name": "카드 교체: %s" % label, "cost": "없음", "effect": "위험 조건 %s → %s" % [_risk_text(ev.fromRisk), to_txt], "enabled": not c.is_empty() and not bool(c.done) })
			out.append({ "id": "leave", "name": "듣지 않는다", "cost": "없음", "effect": "없음", "enabled": true })
	return out

## 보급소 재료: 지역 보상 재료 중 송곳니가 아닌 첫 종류("" = 없음)
static func _supply_mat(region_id: String) -> String:
	for k in PRun.region(region_id).reward.mats:
		if String(k) != "fang":
			return String(k)
	return ""

## 선택 적용(정확히 1회). 반환: { next: "after" | "fight" | "deep" | "offer" }. 실패 시 {}
static func resolve(run: Dictionary, sortie: Dictionary, opt_id: String) -> Dictionary:
	var ev = sortie.get("event", null)
	if ev == null or bool(ev.resolved):
		push_error("사건 없음/이미 처리")
		return {}
	var opt := {}
	for o in options(run, sortie):
		if String(o.id) == opt_id:
			opt = o
	if opt.is_empty() or not bool(opt.enabled):
		push_error("선택 불가: " + opt_id)
		return {}
	ev.resolved = true
	ev.choice = opt_id
	run.lastEvent = String(ev.id)
	run.eventsResolved = int(run.get("eventsResolved", 0)) + 1
	var g: Dictionary = run.growth
	g.picks.event = int(g.picks.get("event", 0)) + 1
	var b := PRun.build(run)
	var id := String(ev.id)
	if opt_id == "leave":
		PRun.add_log(run, "%s: 지나침" % String(E()[id].name))
		return { "next": "after" }
	match id:
		"weapon_altar":
			var cost := altar_cost(run)
			run.hp = maxf(1.0, float(run.hp) - float(cost))
			g.pendingEventPick = { "kind": "weapon_mod", "regionId": String(sortie.regionId), "key": "%s:%d" % [id, int(sortie.seed)] }
			PRun.add_log(run, "무기 제단: 체력 -%d, 개조 3택" % cost)
			return { "next": "offer" }
		"supply":
			if opt_id == "heal":
				run.hp = minf(float(b.hp_max), float(run.hp) + float(int(round(float(b.hp_max) * float(E().supply.heal)))))
				PRun.add_log(run, "보급소: 치료")
			else:
				var mat := _supply_mat(String(sortie.regionId))
				sortie.loot.gold = int(sortie.loot.gold) + int(E().supply.gold)
				if mat != "":
					sortie.loot.mats[mat] = int(sortie.loot.mats.get(mat, 0)) + 1
				PRun.add_log(run, "보급소: 금화 +%d" % int(E().supply.gold))
			run.lastSupplyDay = int(run.day)
			return { "next": "after" }
		"merchant":
			sortie.eventFight = "merchant"
			sortie.eventService = String(ev.service)
			return { "next": "fight" }
		"time_spring":
			if opt_id == "buff":
				if not run.has("buffs") or run.buffs == null: run.buffs = {}
				run.buffs.skillCd = float(E().time_spring.cdBuff)
				PRun.add_log(run, "시간의 샘: 다음 전투 재사용 ×0.7")
			else:
				run.hours = int(run.hours) - int(E().time_spring.hours)
				run.hp = float(b.hp_max)
				PRun.add_log(run, "시간의 샘: 치료(1시간)")
			return { "next": "after" }
		"sealed_loot":
			PRun.deep_explore(run, sortie)
			sortie.deepGoldMult = float(E().sealed_loot.goldMult)
			PRun.add_log(run, "봉인된 전리품: 더 깊이 탐험")
			return { "next": "deep" }
		"scout":
			var c := PSortie.card(run, String(ev.cardId))
			c.risk = ev.toRisk
			c.enemies = PSortie.main_enemies(run, String(c.regionId), String(c.objective), (String(c.risk) if c.risk != null else ""))
			PRun.add_log(run, "정찰자: %s 카드 위험 조건 교체" % String(PRun.region(String(c.regionId)).name))
			return { "next": "after" }
	return { "next": "after" }

## 상인 추가 전투: 지역 웨이브 + 정예(더 깊이와 같은 구성), 전멸 목표, 전리품 없음. CombatState opts 덮어쓰기(snake_case)
static func fight_opts(run: Dictionary, sortie: Dictionary) -> Dictionary:
	var waves := PRun.encounter_waves(String(sortie.regionId), true, run)
	return { "waves": waves, "objective": "clear", "seed": int(sortie.seed) + 9000 + int(sortie.get("encounters", 0)) * 1000, "event_fight": String(sortie.eventFight) }

## 추가 전투 승리 정산(PFlow.settle_victory에서): 서비스 해금만
static func on_fight_win(run: Dictionary, sortie: Dictionary) -> void:
	if String(sortie.get("eventFight", "")) == "merchant" and not bool(sortie.get("eventFightDone", false)):
		sortie.eventFightDone = true
		if not run.has("services") or run.services == null: run.services = {}
		var sv := String(sortie.eventService)
		run.services[sv] = int(run.services.get(sv, 0)) + 1
		PRun.add_log(run, "상인 구출: %s 해금" % String(PCatalog.services()[sv].name))
	sortie.eventFight = null

## 봇 선택 정책(회차 시뮬레이션): risky는 전투·제단, cautious는 치료, 기본은 무료 이득만
static func bot_choose(run: Dictionary, sortie: Dictionary, strat: String) -> String:
	var enabled := {}
	for o in options(run, sortie):
		if bool(o.enabled):
			enabled[String(o.id)] = true
	var ev = sortie.get("event", null)
	if ev == null:
		return "leave"
	var risky := strat == "risky" or strat == "deep"
	var cautious := strat == "cautious"
	var hp: float = float(run.hp)
	var hp_max: float = float(PRun.build(run).hp_max)
	match String(ev.id):
		"weapon_altar": return "pay" if (risky and hp > hp_max * 0.6 and enabled.has("pay")) else "leave"
		"supply":
			if cautious and enabled.has("heal"): return "heal"
			return "heal" if (hp < hp_max * 0.5 and enabled.has("heal")) else "loot"
		"merchant": return "fight" if (risky and enabled.has("fight")) else "leave"
		"time_spring":
			if cautious and enabled.has("heal") and hp < hp_max * 0.6: return "heal"
			return "buff" if enabled.has("buff") else "leave"
		"sealed_loot": return "fight" if (risky and enabled.has("fight") and hp >= hp_max * 0.5) else "leave"
		"scout": return "swap" if (enabled.has("swap") and ev.toRisk == null) else "leave"
	return "leave"
