class_name PSortie
extends RefCounted
## 출격 카드(하루 2장 = 오늘의 장소, 시드 확정·저장)와 임무 보상 규칙(HTML sortie.js 이식). 화면·봇 공용.
## 카드 dict: { id, day, regionId, objective, risk(null|String), rewardKind(null|String), rewardTarget, fallbackGold, timeCost, enemies[], first, done, attempts, linked, variantSlot(null|int), variantName(null|String) }

static func M() -> Dictionary: return PCatalog.mission_rules()

static func card_seed(run: Dictionary, day: int) -> int:
	return (int(run.seed) * 7 + day * 1009 + 13) & 0xFFFFFFFF

## 보상 종류의 유효성: 현재 성장 상태에서 그 종류의 후보가 1개 이상
static func kind_valid(run: Dictionary, kind: String) -> bool:
	if kind == "gold":
		return true
	if kind == "service":
		return PCatalog.services().size() > 0
	var pools: Array = M().kindPools.get(kind, [])
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if pools.has(String(c.kind)):
			return true
	return false

static func reward_kind_for(run: Dictionary, objective: String) -> String:
	for k in M().rewardByObjective.get(objective, []):
		if kind_valid(run, String(k)):
			return String(k)
	return "gold"

## 보상 대상 요약(카드 표시용)
static func reward_target(run: Dictionary, kind: String) -> String:
	var g: Dictionary = run.growth
	var W := PCatalog.weapons()
	var S: Dictionary = PCatalog.growth().SLOTS
	var parts := []
	match kind:
		"weapon_level":
			for w in g.weapons:
				if int(w.level) < int(S.weaponMax):
					parts.append("%s Lv%d→%d" % [String(W[String(w.id)].name), int(w.level), int(w.level) + 1])
			return " / ".join(parts)
		"weapon_mod":
			for w in g.weapons:
				if (w.mods as Array).size() >= int(S.weaponMods):
					continue
				var has_open := false
				var mods: Dictionary = W[String(w.id)].mods
				for mid in mods:
					if bool(mods[mid].impl) and not (w.mods as Array).has(String(mid)):
						has_open = true
				if has_open:
					parts.append("%s 개조 %d/%d" % [String(W[String(w.id)].name), (w.mods as Array).size(), int(S.weaponMods)])
			return " / ".join(parts)
		"skill":
			# **Q가 감속장이라는 가정을 쓰지 않는다**(2026-09-10, §7). Q·E 두 칸에 어떤 기술이든
			# 들어갈 수 있으므로 실제로 장착한 기술 이름을 적는다. 빈 칸은 '습득'으로 안내한다
			var qs = g.skills.get("q", null)
			var es = g.skills.get("e", null)
			var SK := PCatalog.skills()
			var names := []
			if qs != null and SK.has(String(qs.id)):
				names.append("%s 강화/변형" % String(SK[String(qs.id)].name))
			if es != null and SK.has(String(es.id)):
				names.append("%s 강화/변형" % String(SK[String(es.id)].name))
			else:
				names.append("수동 기술 습득")
			return " · ".join(names)
		"common":
			return "공통 증강"
		"service":
			for id in PCatalog.services():
				parts.append(String(PCatalog.services()[id].name))
			return " / ".join(parts)
	return ""

static func regions_for(day: int) -> Array:
	var out := []
	for r in PCatalog.regions():
		if int(M().regionFromDay.get(String(r.id), 1)) <= day:
			out.append(r)
	return out

## 현재 빌드와의 연결: 보상 종류가 소유 무기·기술에 직접 적용되는가
static func build_linked(run: Dictionary, kind: String) -> bool:
	return kind == "weapon_level" or kind == "weapon_mod" or (kind == "skill" and run.growth.skills.get("e", null) != null)

## 하루 카드 = 오늘의 장소 2곳. 1일차 단순 전멸, missionFromDay부터 임무 목표(시드 확정), riskFromDay부터 위험 조건.
## 임무 보상은 다음 자연 레벨업의 종류를 정하는 예약(steer). 이미 예약이 있으면 카드에 금화 대체가 표시된다
static func generate(run: Dictionary, day: int) -> Array:
	var rng := PRng.new(card_seed(run, day))
	var places := PRun.places_for(run, day)
	var out := []
	var objs: Array = (PCatalog.missions().objective_ids as Array).duplicate()
	var SCH: Dictionary = PCatalog.world().schedule
	var steer_map: Dictionary = PCatalog.world().mission_steer
	for i in places.size():
		var rid := String(places[i])
		var obj := "clear"
		if rid != "deep" and day >= int(SCH.missionFromDay) and (i == 0 or rng.next() < 0.5):
			var oi := rng.int_range(0, objs.size() - 1)
			obj = String(objs[oi])
			objs.remove_at(oi)
		var risk = null
		if obj != "clear" and day >= int(SCH.riskFromDay) and rng.next() < PRun.risk_chance(run):
			risk = String(M().risks[rng.int_range(0, (M().risks as Array).size() - 1)])
		var kind = null
		if obj != "clear":
			kind = String(steer_map.get(obj, "gold"))
		var variant := PRun.slot_variant(rid, 0)
		if variant.is_empty(): variant = PRun.slot_variant(rid, 2)
		if variant.is_empty(): variant = PRun.slot_variant(rid, 3)
		if variant.is_empty(): variant = PRun.slot_variant(rid, 4)
		out.append({ "id": "d%dc%d" % [day, i + 1], "day": day, "regionId": rid, "objective": obj, "risk": risk, "rewardKind": kind,
			"rewardTarget": (reward_target(run, String(kind)) if kind != null else ""), "fallbackGold": int(M().goldFallback.get(rid, int(PRun.region(rid).reward.gold[0]))), "timeCost": PRun.place_cost(rid),
			"enemies": main_enemies(run, rid, obj, (String(risk) if risk != null else "")), "first": obj != "clear" and int(run.get("missionsDone", {}).get(obj, 0)) == 0,
			"done": false, "attempts": 0, "linked": (build_linked(run, String(kind)) if kind != null else false),
			"variantSlot": (int(variant.slot) if not variant.is_empty() else null), "variantName": (String(variant.name) if not variant.is_empty() else null) })
		var fm := pick_formation(run, rid, day, rng, risk != null) # 사전 편성(역할 조합): 카드마다 정수 1개 소비, 같은 지역의 직전 편성 회피(테마 장소: 위험 조건이면 위험 템플릿)
		out[out.size() - 1].formationId = String(fm.id)
		out[out.size() - 1].formationName = String(fm.name)
		out[out.size() - 1].formationDesc = String(fm.get("desc", ""))
		out[out.size() - 1].formationKind = String(fm.get("kind", ""))
	# 특수 정예 결투 배정(할 일 4·5): 하루의 카드가 모두 정해진 뒤 한 장에만 붙인다.
	# **난수를 쓰지 않는다** — 자리표로 정하므로 시드·저장이 그대로 재현되고, 카드에 저장하므로 복구해도 같은 강적이다.
	PRun.assign_duel(run, day, out)
	return out

## 편성 대안 선택: 대안이 1개(기본뿐)면 rng를 소비하지 않는다(첫날 숲 카드는 0.4.2와 동일). 직전에 같은 지역에서 쓴 편성은 제외
static func pick_formation(run: Dictionary, region_id: String, day: int, rng: PRng, risk: bool = false) -> Dictionary:
	var opts := PRun.formation_options(region_id, day, risk)
	if opts.size() <= 1:
		return opts[0]
	var last := String((run.get("lastFormation", {}) as Dictionary).get(region_id, ""))
	var pool := []
	for o in opts:
		if String(o.id) != last:
			pool.append(o)
	if pool.is_empty():
		pool = opts
	return pool[rng.int_range(0, pool.size() - 1)]

## 출격 카드의 **사전 표시**: 이 카드로 나가면 강적(정예)을 만나는가, 만난다면 그 대가로 무엇을 더 받는가.
## 화면(scripts/game/screens/base.gd)과 봇이 같은 함수를 읽는다. 실제 편성(PRun.encounter_waves)에서 세므로
## 표시와 실제가 어긋날 수 없다. 반환: { present, types[], names[], reward, text }
static func elite_notice(run: Dictionary, c: Dictionary) -> Dictionary:
	var rid := String(c.get("regionId", ""))
	var types := []
	var names := []
	var n := 0
	var v: Dictionary = PRun.slot_variant(rid, PRun.slot_index(run)) if int(run.get("hours", 0)) > 0 else {}
	for w in PRun.encounter_waves(rid, false, run, { "formationId": String(c.get("formationId", "base")), "variant": (v if not v.is_empty() else null) }):
		for g in w:
			if not bool(PCatalog.enemy(String(g.type)).get("elite", false)) or int(g.n) <= 0:
				continue
			if PRun.is_common_elite(String(g.type)): # 일반 정예는 특수 정예 예고·추가 금화의 대상이 아니다
				continue
			n += int(g.n)
			if not types.has(String(g.type)):
				types.append(String(g.type))
				names.append("%s%s" % [String(PCatalog.enemy(String(g.type)).name), ("×%d" % int(g.n)) if int(g.n) > 1 else ""])
	if n <= 0:
		return { "present": false, "types": [], "names": [], "reward": "", "text": "" }
	var rw := elite_reward_text(run, rid)
	return { "present": true, "types": types, "names": names, "count": n,
		"reward": rw, "text": "강적 출현 · %s · 보상 %s" % [" · ".join(names), rw] }

## 강적을 잡았을 때 추가로 받는 것(카드에 미리 보여 줄 짧은 문구). 중복 지급 금지 규칙을 그대로 읽는다:
## 이미 정예 조건부 재료를 주는 장소는 그 재료를 말하고, 그렇지 않은 장소만 추가 금화를 말한다.
## 출격 **전에** 보여 줄 결투 예고("마지막에 강적이 나타난다"). 카드에 저장된 duelType 을 그대로 읽으므로
## 표시와 실제가 어긋날 수 없다. 표시는 다른 담당이 그리고 여기서는 자료만 내보낸다.
##
## §13(2026-09-09): 결투 상대는 카드가 붙인 것만이 아니다 — **편성 템플릿이 배정한 특수 정예도 결투로 나온다**
## (그런 카드에는 assign_duel 이 결투를 겹쳐 붙이지 않는다). 카드의 duelType 만 읽으면 실제로는 결투가 있는데
## 예고가 비어 있었다. 실제 편성이 내보내는 것을 그대로 읽어 표시와 실제가 어긋나지 않게 한다.
static func duel_notice(run: Dictionary, c: Dictionary) -> Dictionary:
	var rid := String(c.get("regionId", ""))
	var dt := String(c.get("duelType", ""))
	if dt == "":
		var sched := PRun.scheduled_special_elites(rid, String(c.get("formationId", "base")))
		if not sched.is_empty():
			dt = String(sched[0])
	return PRun.duel_notice(run, rid, dt)

static func elite_reward_text(run: Dictionary, region_id: String) -> String:
	var cfg: Dictionary = PCatalog.pacing().get("elite_reward", {})
	var skip := String(cfg.get("skip_if_mat", ""))
	var mats: Dictionary = PRun.region(region_id).get("reward", {}).get("mats", {})
	if skip != "" and mats.has(skip):
		return "%s(정예 처치 시)" % String(PCatalog.materials()[skip].name)
	var g := PPacing.gold_award(PRun.elite_bonus_gold(run, region_id, true))
	return ("금화 +%d" % g) if g > 0 else "추가 없음"

static func main_enemies(run: Dictionary, region_id: String, objective: String, risk: String) -> Array:
	var base := []
	for t in PRun.region_enemies(region_id, run):
		if not bool(PCatalog.enemy(String(t)).get("elite", false)):
			base.append(String(t))
	base = base.slice(0, 3)
	if objective == "hunt" or risk == "escort" or region_id == "deep":
		base.append(String(PCatalog.objectives().hunt.eliteType))
	var out := []
	for t in base:
		if not out.has(t):
			out.append(t)
	return out.slice(0, 4)

## 오늘의 카드(없거나 날짜가 다르면 생성해 저장 필드에 둔다). 다시 굴리기 없음
static func cards_for(run: Dictionary) -> Array:
	if run.get("cards", null) == null or int(run.cards.day) != int(run.day):
		run.cards = { "day": int(run.day), "list": generate(run, int(run.day)) }
	return run.cards.list

static func card(run: Dictionary, id: String) -> Dictionary:
	for c in cards_for(run):
		if String(c.id) == id:
			return c
	return {}

static func can_start(run: Dictionary, c: Dictionary) -> bool:
	if c.is_empty():
		return false
	if bool(c.get("repeat", false)):
		return PRun.can_sortie(run, String(c.regionId), int(c.timeCost))
	return not bool(c.done) and PRun.can_sortie(run, String(c.regionId))

## 남는 시간용 반복 탐험 카드(지시 8): 오늘 완료한 같은 장소로 다시 나간다.
## 임무 목표·임무 보상·사건·이용권은 다시 주지 않는다. 시간(1칸)과 전투 위험은 그대로 지불한다.
static func repeat_cards(run: Dictionary) -> Array:
	var out := []
	if not PPacing.repeat_enabled() or String(run.get("phase", "")) != "prep" or PRun.is_boss_day(run):
		return out
	var cost := PPacing.repeat_cost()
	if int(run.hours) < cost:
		return out
	for c in cards_for(run):
		if not bool(c.done):
			continue
		var rid := String(c.regionId)
		out.append({ "id": String(c.id) + ":again", "day": int(run.day), "regionId": rid, "objective": "clear", "risk": null,
			"rewardKind": null, "rewardTarget": "", "fallbackGold": 0, "timeCost": cost, "repeat": true,
			"enemies": (c.enemies as Array).duplicate(), "first": false, "done": false, "attempts": int(c.get("repeatAttempts", 0)), "linked": false,
			"formationId": String(c.get("formationId", "base")), "formationName": String(c.get("formationName", "기본")), "formationDesc": String(c.get("formationDesc", "")),
			"formationKind": String(c.get("formationKind", "")), "duelType": "", "duelName": "", # 반복 탐험에는 결투를 붙이지 않는다(추가 보상 반복 지급 금지)
			"variantSlot": null, "variantName": null, "label": PPacing.repeat_label() })
	return out

## 오늘의 카드 + 반복 탐험 카드(행동 목록·화면 공용)
static func all_cards(run: Dictionary) -> Array:
	var out: Array = cards_for(run).duplicate()
	out.append_array(repeat_cards(run))
	return out

## 카드 출격: 지역 출격과 같은 비용·시드 규칙 + 카드 정보. 목표 'clear'는 일반 출격(임무 아님). 불가하면 {}
static func start(run: Dictionary, id: String) -> Dictionary:
	var c := card(run, id)
	if c.is_empty() and id.ends_with(":again"): # 반복 탐험 카드(오늘의 카드 목록에는 없다)
		for rc in repeat_cards(run):
			if String(rc.id) == id:
				c = rc
				break
	if not can_start(run, c):
		push_error("임무 시작 불가: " + id)
		return {}
	var s := PRun.start_sortie(run, String(c.regionId), int(c.get("timeCost", 0)) if bool(c.get("repeat", false)) else 0)
	if s.is_empty():
		return {}
	s.cardId = String(c.id)
	s.formationId = String(c.get("formationId", "base"))
	s.formationName = String(c.get("formationName", "기본"))
	s.formationKind = String(c.get("formationKind", ""))
	s.duelType = String(c.get("duelType", "")) # 카드에 저장된 결투 상대(저장·복구해도 같다)
	if not run.has("lastFormation") or run.lastFormation == null:
		run.lastFormation = {}
	run.lastFormation[String(c.regionId)] = s.formationId
	c.attempts = int(c.attempts) + 1
	if bool(c.get("repeat", false)):
		s.repeat = true # 반복 탐험: 사건·임무 보상 없음(정상 전투 전리품만)
		var base_id := String(c.id).replace(":again", "")
		var bc := card(run, base_id)
		if not bc.is_empty():
			bc.repeatAttempts = int(bc.get("repeatAttempts", 0)) + 1
		PRun.add_log(run, "%s: %s (시간 -%d)" % [String(PRun.region(String(c.regionId)).name), PPacing.repeat_label(), int(c.timeCost)])
		return s
	if String(c.objective) != "clear":
		s.objective = String(c.objective)
		s.risk = c.risk
		s.mission = true
	return s

## 예약 상태 표시: 카드의 보상이 예약으로 들어갈지, 금화 대체가 될지
static func steer_state(run: Dictionary, c: Dictionary) -> Dictionary:
	if c.get("rewardKind", null) == null:
		return { "text": "전리품만", "gold": true }
	var kind := String(c.rewardKind)
	if kind == "service":
		return { "text": "완료 즉시 3택", "gold": false }
	var g: Dictionary = run.growth
	if g.get("steer", null) != null:
		return { "text": "이미 예약 있음(%s) → 금화 +%d 대체" % [kind_name(String(g.steer.kind)), int(c.fallbackGold)], "gold": true }
	if not kind_valid(run, kind):
		return { "text": "유효 후보 없음 → 금화 +%d 대체" % int(c.fallbackGold), "gold": true }
	return { "text": "다음 레벨업을 %s로 예약" % kind_name(kind), "gold": false }

static func kind_name(kind: String) -> String:
	return String({ "weapon_level": "자동기술 레벨", "weapon_mod": "자동기술 개조", "skill": "Q/E 강화", "service": "거점 서비스", "common": "공용 증강" }.get(kind, kind))

## 목표가 'clear'인 **평범한 출격도 이기면 그 카드를 완료로 남긴다.**
## 임무 카드는 아래 on_mission_win이 보상과 함께 완료를 찍지만, clear 카드에는 그 경로가 없어서
## 카드가 영영 완료되지 않았다 — 완료 카드가 접히지도 않고('오늘 완료  숲 · 능선'),
## 남는 시간의 '일반 탐험'도 열리지 않았다(repeat_cards는 완료한 카드만 대상으로 한다).
## 같은 카드를 정상 비용으로 계속 다시 나갈 수 있어 **사건·이용권이 반복 지급되는 구멍**이기도 했다.
## 2026-09-09 실제 UI 확인(tests/ui_flow_tests.gd '실제 경로')에서 발견. 보상은 건드리지 않고 완료 표시만 한다.
static func on_clear_win(run: Dictionary, sortie: Dictionary) -> bool:
	var c := card(run, String(sortie.get("cardId", "")))
	if c.is_empty() or bool(c.done) or String(c.objective) != "clear":
		return false
	c.done = true
	return true

## 임무 승리 정산(PFlow.settle_victory에서): 카드 완료 → 서비스는 즉시 3택 보류, 그 외는 단일 예약(steer). 예약이 이미 있으면 금화 대체.
## 반환: false(임무 아님/이미 완료) | true(서비스 3택 보류) | {gold} | {steer}
static func on_mission_win(run: Dictionary, sortie: Dictionary) -> Variant:
	var c := card(run, String(sortie.get("cardId", "")))
	if c.is_empty() or bool(c.done) or String(c.objective) == "clear":
		return false
	c.done = true
	if not run.has("missionsDone"): run.missionsDone = {}
	run.missionsDone[String(c.objective)] = int(run.missionsDone.get(c.objective, 0)) + 1
	var g: Dictionary = run.growth
	var kind := String(c.rewardKind)
	if kind == "service":
		g.pendingMissionPick = { "cardId": String(c.id), "kind": kind, "regionId": String(c.regionId), "fallbackGold": int(c.fallbackGold), "key": "%d:%d" % [int(sortie.seed), int(sortie.get("encounters", 0))] }
		return true
	if g.get("steer", null) != null or not kind_valid(run, kind):
		run.gold = int(run.gold) + int(c.fallbackGold)
		g.missionGoldFallbacks = int(g.get("missionGoldFallbacks", 0)) + 1
		PRun.add_log(run, "임무 보상: %s 금화 +%d" % ["예약이 이미 있어" if g.get("steer", null) != null else "유효 후보가 없어", int(c.fallbackGold)])
		return { "gold": int(c.fallbackGold) }
	g.steer = { "kind": kind, "cardId": String(c.id), "regionId": String(c.regionId), "day": int(run.day), "fallbackGold": int(c.fallbackGold) }
	PRun.add_log(run, "임무 보상: 다음 레벨업을 %s로 예약" % kind_name(kind))
	return { "steer": kind }

## 임무 보상 제시(서비스 종류만 남음): 유효 후보가 없으면 정해진 금화로 대체. 제시가 없으면 null
static func mission_offer(run: Dictionary) -> Variant:
	var g: Dictionary = run.growth
	var mp = g.get("pendingMissionPick", null)
	if mp == null:
		return null
	g.pendingMissionPick = null
	var kind := String(mp.kind) if kind_valid(run, String(mp.kind)) else "gold"
	if kind == "gold":
		run.gold = int(run.gold) + int(mp.fallbackGold)
		PRun.add_log(run, "임무 보상: 유효한 후보가 없어 금화 +%d" % int(mp.fallbackGold))
		g.missionGoldFallbacks = int(g.get("missionGoldFallbacks", 0)) + 1
		return null
	var off := PGrowth.generate_offer(run, { "pool": "mission", "kinds": M().kindPools[kind], "region_id": String(mp.regionId), "missionKind": kind })
	if (off.choices as Array).is_empty():
		g.pendingOffer = null
		run.gold = int(run.gold) + int(mp.fallbackGold)
		PRun.add_log(run, "임무 보상: 후보 없음 → 금화 +%d" % int(mp.fallbackGold))
		g.missionGoldFallbacks = int(g.get("missionGoldFallbacks", 0)) + 1
		return null
	return off

static func objective_name(id: String) -> String:
	var O := PCatalog.objectives()
	if O.has(id):
		return String(O[id].name)
	return "정예 포함 전멸" if id == "elite" else "전멸"
