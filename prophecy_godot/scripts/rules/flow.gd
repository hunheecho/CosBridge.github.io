class_name PFlow
extends RefCounted
## 회차 진행 공유 흐름(HTML flow.js 이식): 조우 생성·정산·다음 선택을 화면과 회차 봇이 같은 함수로 처리한다.
## 화면은 결과를 표시하고 선택을 전달할 뿐, 보상·경험치·3택의 규칙은 여기서만 결정된다. actions(run)은 거점에서 지금 가능한 행동 목록(F1 재발 방지: UI·봇 공용).

## KD-7 대조군 스위치(전후 비교 전용, 게임 기본값 아님). PROPHECY_CLEAR_DONE=0 이면 목표 'clear' 카드의
## 완료 표시를 찍지 않던 **옛 규칙**으로 돌아간다 — 일반 탐험이 열리지 않고, 같은 카드를 정상 비용으로
## 몇 번이든 다시 나가며 사건·이용권이 매번 새로 굴렀던 그 상태다.
## 기본값은 지금 규칙(켜짐)이다. PROPHECY_PACING·PROPHECY_LEGACY_PLACES와 같은 자리의 장치다.
## 도구가 한 프로세스 안에서 두 규칙을 번갈아 재려면 이 변수를 직접 바꿨다가 되돌린다
## (tools/repeat_income_probe.gd). 규칙 코드는 아래 settle_victory 한 곳에서만 읽는다.
static var clear_done_on := OS.get_environment("PROPHECY_CLEAR_DONE") != "0"

## 조우 시드: 출격 시드 + 조우 순번×1000 + (더 깊이 7)
static func encounter_seed(sortie: Dictionary) -> int:
	return int(sortie.seed) + int(sortie.get("encounters", 0)) * 1000 + (7 if bool(sortie.get("deep", false)) else 0)

## 조우 생성 옵션(일반 조우, CombatState opts snake_case). 보스는 make_boss_encounter
static func encounter_opts(run: Dictionary, sortie: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var region := String(sortie.regionId)
	var deep: bool = bool(sortie.get("deep", false))
	var mission: bool = bool(sortie.get("mission", false))
	var risk: String = String(sortie.risk) if (mission and sortie.get("risk", null) != null) else ""
	var pool := []
	for t in PRun.region_enemies(region, run):
		if not bool(PCatalog.enemy(String(t)).get("elite", false)):
			pool.append(String(t))
	var o := {
		"build": PRun.build(run), "hp": float(run.hp), "seed": encounter_seed(sortie),
		"waves": PRun.encounter_waves(region, deep, run, sortie),
		"objective": (String(sortie.objective) if mission else PRun.encounter_objective(region, deep, run)),
		"arena": (String(sortie.arena) if sortie.has("arena") else PRun.region_arena(region, run)),
		"hp_mult": PRun.hp_mult_for(run, region, deep), "region_id": region, "risk": risk,
		"mission": ({ "cardId": String(sortie.get("cardId", "")), "objective": String(sortie.objective), "risk": risk } if mission else {}),
		"pool": pool, "chest": true, "xp_kill_mult": PRun.kill_xp_mult(run), "lab_text": PRun.layout_text(run), "run": run,
		"density": (PRun.theme_density_override(region, String(sortie.get("formationId", "")), int(PRun.act_of(run).get("id", 1)), String(run.get("aliveCapSet", ""))) if PRun.is_theme_place(region) else PCatalog.density_set(String(run.get("densitySet", "")))), # 테마 장소는 템플릿 상한(배율 이중 적용 없음), 그 외 밀도 세트
		"tier_mix": PRun.tier_mix(run), "world_stage": PRun.world_stage(run), "act": int(PRun.act_of(run).get("id", 1)), # 막(정예 체력·역할별 고정 체력표) # 세계 변화 등급 비율(관문 완료에서 도출)
		"duel": PRun.duel_cfg(), # 특수 정예 결투 설정(전환 조건·연출 시간·고유 소환). 결투 상대 자체는 waves 안에 duel 표시로 들어 있다
	}
	if sortie.get("eventFight", null) != null:
		var fo := PEvents.fight_opts(run, sortie)
		for k in fo:
			o[k] = fo[k]
	for k in extra:
		o[k] = extra[k]
	return o

## 임시 강화(시간의 샘)는 이 전투 내내 적용되고 정산 때 소비. 전투 시작 시 보류 출격 상태 해제
static func make_encounter(run: Dictionary, sortie: Dictionary, extra: Dictionary = {}) -> CombatState:
	var st := CombatState.new(encounter_opts(run, sortie, extra))
	if (run.get("buffs", {}) as Dictionary).has("skillCd"):
		st.temp_buff = "skillCd"
	consume_stored_shield(run)
	PConsumables.consume_for_fight(run)   # 출격 준비물은 전투 입장에서 1회 소모(빌드는 위에서 이미 계산됐다)
	run.pendingSortie = null
	return st

## 재생의 여행복이 저장한 초과 회복분(run.storedShield)은 전투 시작 빌드에 들어간 뒤 소비된다(다음 전투 1회)
static func consume_stored_shield(run: Dictionary) -> void:
	if float(run.get("storedShield", 0.0)) > 0.0:
		run.storedShield = 0.0

static func consume_buff(run: Dictionary, st: CombatState) -> void:
	if st != null and st.temp_buff == "skillCd" and run.has("buffs") and (run.buffs as Dictionary).has("skillCd"):
		(run.buffs as Dictionary).erase("skillCd")

static func _kind_of(sortie: Dictionary) -> String:
	return "deep" if bool(sortie.get("deep", false)) else ("mission" if bool(sortie.get("mission", false)) else "sortie")

## 조우 승리 정산(정확히 1회): 전리품 굴림 → 출격 전리품 반영 → 원정대의 갑옷 회복(C7: 승리마다 1회) → 지역 경험치 → 사건 굴림 → 심층 보상 → 통계
static func settle_victory(run: Dictionary, sortie: Dictionary, st: CombatState) -> Dictionary:
	if st == null or st.status != "won":
		push_error("승리 정산 자격 없음: status=" + (st.status if st != null else "null"))
		return {}
	if st.settled != "":
		push_error("이미 정산된 전투(" + st.settled + ")")
		return {}
	st.settled = "won"
	consume_buff(run, st)
	if st.duel_stage != "" and st.duel_stage != "done": # 특수 정예전이 끝나기 전에는 출격 승리를 먼저 처리하지 않는다
		push_error("특수 정예전 미완료 상태의 승리 정산: " + st.duel_stage)
		return {}
	var elite_killed: bool = st.status == "won" and st.objective == "elite"
	for e in st.enemies:
		if bool(e.elite) and bool(e.dead) and not PRun.is_common_elite(String(e.type)): # 일반 정예는 특수 정예 추가 금화 대상이 아니다
			elite_killed = true
	var reward := PRun.roll_reward(run, sortie, st.rng, { "chestGold": int(st.stats.chest_gold), "eliteKilled": elite_killed })
	if sortie.get("eventFight", null) != null: # 사건 추가 전투: 전리품 없음, 서비스만
		reward.gold = 0
		reward.mats = {}
		reward.chestGold = 0
		reward.eventFight = String(sortie.eventFight)
		PEvents.on_fight_win(run, sortie)
	if bool(sortie.get("deep", false)) and sortie.get("deepGoldMult", null) != null: # 봉인된 전리품: 밝혀진 보상(1회)
		reward.gold = int(round(float(reward.gold) * float(sortie.deepGoldMult)))
		reward.sealedLoot = true
		sortie.deepGoldMult = null
	if bool(sortie.get("mission", false)): # 임무: 재료 대신 종류 지정 3택(금화는 유지, 위험 조건이면 ×1.25)
		reward.mats = {}
		if sortie.get("risk", null) != null:
			reward.gold = int(round(float(reward.gold) * PRun.risk_reward_mult(run)))
		reward.mission = true
		reward.missionPick = PSortie.on_mission_win(run, sortie)
	elif clear_done_on and not bool(sortie.get("repeat", false)) and not bool(sortie.get("endless", false)) and sortie.get("eventFight", null) == null:
		PSortie.on_clear_win(run, sortie) # 목표 'clear' 카드도 완료로 남긴다(보상 없음). 반복 탐험·무한·사건 전투는 카드가 아니다
	PRun.apply_encounter_result(run, sortie, "won", reward, float(st.player.hp))
	var heal := PRun.on_victory_heal(run)
	if heal > 0.0:
		reward.heal = heal
	reward.xp = 0.0 if reward.has("eventFight") else PRun.region_bonus_xp(run, String(sortie.regionId), bool(sortie.get("deep", false)))
	PGrowth.add_xp(run.growth, float(reward.xp))
	if not reward.has("eventFight") and sortie.get("event", null) == null and not bool(sortie.get("endless", false)) and not bool(sortie.get("repeat", false)):
		sortie.event = PEvents.roll(run, sortie) # 탐험 사건: 출격당 최대 1회, 시드 결정적(무한 전투에는 사건 없음)
	run.pendingSortie = sortie # 전투 뒤 안전 화면 상태를 저장
	var deep_pick: bool = bool(PCatalog.growth().get("DEEP_PICK", false))
	if bool(sortie.get("deep", false)) and deep_pick and not bool(sortie.get("deepPicked", false)):
		sortie.deepPicked = true
		run.growth.pendingDeepPick = { "regionId": String(sortie.regionId), "key": "%d:%d" % [int(sortie.seed), int(sortie.encounters)] }
	if bool(sortie.get("deep", false)) and not deep_pick:
		reward.deep = PRun.apply_deep_reward(run, sortie) # v0.8: 표시된 심층 보상을 미정산 전리품에 얹음(귀환 시 정산)
	PStats.record(run, st, { "kind": _kind_of(sortie), "regionId": String(sortie.regionId), "day": int(run.day) })
	return reward

static func settle_defeat(run: Dictionary, sortie: Dictionary, st: CombatState) -> void:
	if st == null or not (st.status == "lost" or st.status == "timeout"):
		push_error("패배 정산 자격 없음: status=" + (st.status if st != null else "null"))
		return
	if st.settled != "":
		push_error("이미 정산된 전투(" + st.settled + ")")
		return
	st.settled = "lost"
	consume_buff(run, st)
	PStats.record(run, st, { "kind": _kind_of(sortie), "regionId": String(sortie.regionId), "day": int(run.day), "won": false })
	PRun.apply_encounter_result(run, sortie, "lost", {}, 0.0)
	PRun.defeat(run, sortie)
	run.pendingSortie = null

## 보스전(회차 관문): 단계별 보스·체력 후보. 입장 스냅샷은 PRun.start_boss가 만든다
static func make_boss_encounter(run: Dictionary, sortie: Dictionary) -> CombatState:
	var b := PRun.build(run)
	var boss_id := String(sortie.get("bossId", "boss"))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": int(sortie.seed), "boss": true, "boss_id": boss_id, "boss_hp": PRun.boss_hp(run, boss_id),
		"arena": "clearing", "region_id": "boss", "xp_kill_mult": PRun.kill_xp_mult(run), "run": run, "act": int(PRun.act_of(run).get("id", 1)) })
	if (run.get("buffs", {}) as Dictionary).has("skillCd"):
		st.temp_buff = "skillCd"
	consume_stored_shield(run)
	PConsumables.consume_for_fight(run)   # 출격 준비물은 전투 입장에서 1회 소모(빌드는 위에서 이미 계산됐다)
	run.pendingSortie = null
	return st

## 보스 승리 정산(정확히 1회): 통계 → 원정대의 갑옷 회복(C7) → 처치 기록·다음 단계·희귀 보상 보류
static func settle_boss_victory(run: Dictionary, st: CombatState) -> Dictionary:
	if st == null or st.status != "won" or st.settled != "":
		push_error("보스 승리 정산 자격 없음/중복")
		return {}
	st.settled = "boss_won"
	consume_buff(run, st)
	PStats.record(run, st, { "kind": "boss", "bossId": st.boss_id, "day": int(run.day), "won": true })
	run.hp = maxf(0.0, float(st.player.hp))
	var heal := PRun.on_victory_heal(run)
	var rec := PEndless.boss_victory(run, st.stats) if PEndless.active(run) else PRun.boss_victory(run, st.stats)
	if heal > 0.0:
		rec.heal = heal
	run.pendingSortie = null
	return rec

static func settle_boss_defeat(run: Dictionary, st: CombatState) -> void:
	if st == null or not (st.status == "lost" or st.status == "timeout") or st.settled != "":
		push_error("보스 패배 정산 자격 없음/중복")
		return
	st.settled = "boss_lost"
	consume_buff(run, st)
	PStats.record(run, st, { "kind": "boss", "bossId": st.boss_id, "day": int(run.day), "won": false })
	if PEndless.active(run):
		PEndless.over(run, "boss_lost" if st.status == "lost" else "timeout") # 무한: 구간 보스 패배 = 종료
	else:
		PRun.boss_defeat(run)
	run.pendingSortie = null

## 다음에 제시할 선택(순서 고정): 보류 제시 → 미처리 레벨업 → 임무 보상 3택 → 보스 희귀 보상 → 사건 보상 → 더 깊이 지역 3택 → null
static func next_offer(run: Dictionary, ctx: Dictionary = {}) -> Variant:
	var g: Dictionary = run.growth
	var rid = ctx.get("region_id", null)
	if g.get("pendingOffer", null) != null:
		return g.pendingOffer
	if int(g.pendingLevelUps) > 0:
		return PGrowth.generate_offer(run, { "pool": "level", "region_id": (String(rid) if rid != null else "") })
	if g.get("pendingMissionPick", null) != null:
		var off = PSortie.mission_offer(run)
		return off if off != null else next_offer(run, ctx)
	if g.get("pendingBossPick", null) != null:
		var bp: Dictionary = g.pendingBossPick
		g.pendingBossPick = null
		var off := PGrowth.generate_offer(run, { "pool": "boss", "bossId": String(bp.bossId), "stage": int(bp.stage) })
		if (off.choices as Array).is_empty():
			g.pendingOffer = null
			PRun.add_log(run, "희귀 보상: 적용 가능한 후보 없음(제시 생략)")
			g.bossPickNone = int(g.get("bossPickNone", 0)) + 1
			return next_offer(run, ctx)
		return off
	if g.get("pendingEventPick", null) != null:
		var ep: Dictionary = g.pendingEventPick
		g.pendingEventPick = null
		var off := PGrowth.generate_offer(run, { "pool": "mission", "kinds": [String(ep.kind)], "region_id": String(ep.regionId), "missionKind": String(ep.kind), "event": true })
		if (off.choices as Array).is_empty():
			g.pendingOffer = null
			return next_offer(run, ctx)
		return off
	if g.get("pendingDeepPick", null) != null:
		var drid := String(g.pendingDeepPick.regionId)
		g.pendingDeepPick = null
		var off := PGrowth.generate_offer(run, { "pool": "deep", "region_id": drid })
		if (off.choices as Array).is_empty():
			g.pendingOffer = null
			g.deepPickNone = int(g.get("deepPickNone", 0)) + 1
			PRun.add_log(run, "지역 보상: 남은 후보 없음(제시 생략)")
			return next_offer(run, ctx)
		return off
	return null

## 제시된 선택을 적용(choice) 또는 건너뜀(null). 레벨업 건너뜀은 금화, 유료 변경 건너뜀은 원복·환불, 그 외는 제시만 닫힘
static func resolve_offer(run: Dictionary, offer: Dictionary, choice: Variant) -> void:
	if choice != null:
		PGrowth.apply_choice(run, choice)
	elif String(offer.pool) == "level":
		PGrowth.skip_choice(run)
	elif offer.get("paidChange", null) != null:
		cancel_paid_change(run, offer)
	else:
		run.growth.pendingOffer = null

## 헤드리스: 남은 선택을 봇 정책으로 전부 처리. pick(offer) -> choice|null, on_pick(offer, choice)
static func resolve_all(run: Dictionary, ctx: Dictionary, pick: Callable, on_pick: Callable = Callable()) -> int:
	var guard := 0
	var n := 0
	while true:
		var off = next_offer(run, ctx)
		if off == null or guard > 200:
			break
		guard += 1
		var c = pick.call(off) if (off.choices as Array).size() > 0 else null
		resolve_offer(run, off, c)
		n += 1
		if on_pick.is_valid():
			on_pick.call(off, c)
	return n

## 거점 서비스: 제시 재선택(레벨업 3택 1회) — 순번을 넘겨 다른 제시. 실패 시 {}
static func reroll_offer(run: Dictionary) -> Dictionary:
	var g: Dictionary = run.growth
	var off = g.get("pendingOffer", null)
	if off == null or String(off.pool) != "level" or not PRun.has_service(run, "reroll"):
		push_error("재선택 불가")
		return {}
	PRun.use_service(run, "reroll")
	var rid = off.get("regionId", null)
	g.pendingOffer = null
	g.choiceSeq = int(g.choiceSeq) + 1
	g.picks.reroll = int(g.picks.get("reroll", 0)) + 1
	return PGrowth.generate_offer(run, { "pool": "level", "region_id": (String(rid) if rid != null else "") })

static func _mod_candidates(run: Dictionary, weapon_id: String, mod_id: String) -> Array:
	var out := []
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if String(c.kind) == "weapon_mod" and String(c.id) == weapon_id and String(c.get("mod", "")) != mod_id:
			out.append(c)
	return out

## 거점 서비스: 개조 교체 — 개조 1개를 떼고 그 무기의 다른 개조 3택. 후보가 없으면 되돌리고 권 유지({})
## 그 개조를 바꿀 수 있는 후보가 있는가(화면이 버튼을 끌 때 쓰는 공개 판정 — 상태를 바꾸지 않는다)
static func mod_change_available(run: Dictionary, weapon_id: String, mod_id: String) -> bool:
	return not _mod_candidates(run, weapon_id, mod_id).is_empty()

static func mod_swap_offer(run: Dictionary, weapon_id: String, mod_id: String) -> Dictionary:
	var g: Dictionary = run.growth
	var w := PGrowth.weapon_of(g, weapon_id)
	if w.is_empty() or not (w.mods as Array).has(mod_id) or not PRun.has_service(run, "mod_swap") or g.get("pendingOffer", null) != null:
		push_error("교체 불가")
		return {}
	var orig: Array = (w.mods as Array).duplicate()
	(w.mods as Array).erase(mod_id)
	if _mod_candidates(run, weapon_id, mod_id).is_empty():
		w.mods = orig
		return {}
	PRun.use_service(run, "mod_swap")
	if not g.has("swappedOut"): g.swappedOut = []
	(g.swappedOut as Array).append(weapon_id + ":" + mod_id)
	var off := PGrowth.generate_offer(run, { "pool": "mission", "kinds": ["weapon_mod"], "missionKind": "weapon_mod", "region_id": "", "weapon_only": weapon_id, "exclude_mod": mod_id })
	if (off.choices as Array).is_empty():
		g.pendingOffer = null
		(w.mods as Array).append(mod_id)
		run.services.mod_swap = int(run.services.get("mod_swap", 0)) + 1
		return {}
	return off

## 대장간: 개조 변경(140금 또는 개조 변경권). 후보가 없으면 아무것도 차감하지 않는다({}). 3택 '받지 않음'은 cancel_paid_change로 원복·환불
static func mod_change(run: Dictionary, weapon_id: String, mod_id: String) -> Dictionary:
	var g: Dictionary = run.growth
	var w := PGrowth.weapon_of(g, weapon_id)
	if w.is_empty() or not (w.mods as Array).has(mod_id) or g.get("pendingOffer", null) != null:
		push_error("변경 불가")
		return {}
	var cost := PRun.mod_change_cost(run)
	if not bool(cost.voucher) and int(run.gold) < int(cost.gold):
		push_error("금화 부족")
		return {}
	var orig: Array = (w.mods as Array).duplicate()
	(w.mods as Array).erase(mod_id)
	if _mod_candidates(run, weapon_id, mod_id).is_empty():
		w.mods = orig
		return {}
	if bool(cost.voucher):
		PRun.use_service(run, "mod_swap")
	else:
		run.gold = int(run.gold) - int(cost.gold)
	var off := PGrowth.generate_offer(run, { "pool": "mission", "kinds": ["weapon_mod"], "missionKind": "weapon_mod", "region_id": "", "weapon_only": weapon_id, "exclude_mod": mod_id })
	off.paidChange = { "kind": "mod", "weaponId": weapon_id, "modId": mod_id, "cost": cost, "orig": orig }
	g.picks.modChange = int(g.picks.get("modChange", 0)) + 1
	return off

static func variant_change(run: Dictionary) -> Dictionary:
	var g: Dictionary = run.growth
	var e = g.skills.get("e", null)
	if e == null or e.get("variant", null) == null or g.get("pendingOffer", null) != null:
		push_error("변경 불가")
		return {}
	var cost := PRun.variant_change_cost(run)
	if not bool(cost.voucher) and int(run.gold) < int(cost.gold):
		push_error("금화 부족")
		return {}
	var old := String(e.variant)
	e.variant = null
	var cands := []
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if String(c.kind) == "skill_variant" and String(c.get("slot", "")) == "e" and String(c.get("variant", "")) != old:
			cands.append(c)
	if cands.is_empty():
		e.variant = old
		return {}
	if bool(cost.voucher):
		PRun.use_service(run, "mod_swap")
	else:
		run.gold = int(run.gold) - int(cost.gold)
	var off := PGrowth.generate_offer(run, { "pool": "mission", "kinds": ["skill_variant"], "missionKind": "skill", "region_id": "" })
	var filtered := []
	for c in off.choices:
		if String(c.get("slot", "")) == "e" and String(c.get("variant", "")) != old:
			filtered.append(c)
	off.choices = filtered
	off.paidChange = { "kind": "variant", "old": old, "cost": cost }
	g.picks.variantChange = int(g.picks.get("variantChange", 0)) + 1
	return off

## 유료 변경 3택을 받지 않음: 원래 개조/변형 복구 + 비용 환불(개조 변경권 포함)
static func cancel_paid_change(run: Dictionary, offer: Dictionary) -> bool:
	var pc = offer.get("paidChange", null)
	if pc == null:
		return false
	var g: Dictionary = run.growth
	if String(pc.kind) == "mod":
		var w := PGrowth.weapon_of(g, String(pc.weaponId))
		if not w.is_empty() and not (w.mods as Array).has(String(pc.modId)):
			w.mods = (pc.orig as Array).duplicate() if pc.get("orig", null) != null else (w.mods as Array) + [String(pc.modId)]
	elif String(pc.kind) == "variant" and g.skills.get("e", null) != null and g.skills.e.get("variant", null) == null:
		g.skills.e.variant = String(pc.old)
	if bool(pc.cost.voucher):
		run.services.mod_swap = int(run.services.get("mod_swap", 0)) + 1
	else:
		run.gold = int(run.gold) + int(pc.cost.gold)
	g.pendingOffer = null
	return true

## 전투 뒤 안전 화면의 다음 단계(화면·봇 공용): 남은 선택 → 미처리 사건 → 다음 행동(after)
static func after_combat_step(run: Dictionary, sortie: Dictionary) -> String:
	if next_offer(run, { "region_id": String(sortie.regionId) }) != null:
		return "offer"
	var ev = sortie.get("event", null)
	if ev != null and not bool(ev.resolved):
		return "event"
	return "after"

## 심층 승리 뒤에는 귀환만
static func must_return(sortie: Dictionary) -> bool:
	return not sortie.is_empty() and bool(sortie.get("deep", false)) and bool(sortie.get("deepRewarded", false))

static func return_home(run: Dictionary, sortie: Dictionary) -> void:
	PRun.return_to_base(run, sortie)
	run.pendingSortie = null
	PEndless.after_fight(run, sortie) # 무한 전투면 구간 전투 수 증가(보스 대기 전환)

# ---------- 행동 목록(UI·회차 봇 공용) ----------
static func _act(id: String, kind: String, label: String, enabled: bool, reason: String = "", data: Dictionary = {}) -> Dictionary:
	return { "id": id, "kind": kind, "label": label, "enabled": enabled, "reason": reason, "data": data }

static func _has_pending_offer(g: Dictionary) -> bool:
	return g.get("pendingOffer", null) != null or int(g.get("pendingLevelUps", 0)) > 0 or g.get("pendingMissionPick", null) != null \
		or g.get("pendingBossPick", null) != null or g.get("pendingEventPick", null) != null or g.get("pendingDeepPick", null) != null

## 지금 가능한 행동 전부: [{id, kind, label, enabled, reason, data}]. 전투 뒤 안전 화면(run.pendingSortie)이면 그 단계의 행동, 아니면 거점 행동
static func actions(run: Dictionary) -> Array:
	var out := []
	var phase := String(run.phase)
	if bool(run.get("ended", false)): # 끝난 회차: 본편 완주 상태에서 무한 시작만 가능(PEndless.start가 ended를 다시 연다)
		if phase == "cleared" and PEndless.can_start(run):
			out.append(_act("endless_start", "endless_start", "현재 빌드로 계속 (무한 모드)", true, "", { "fights": PEndless.fights_per_segment() }))
		return out
	var g: Dictionary = run.growth
	if _has_pending_offer(g):
		out.append(_act("continue_offer", "continue_offer", "보류 중인 3택 진행", true))
	var ps = run.get("pendingSortie", null)
	if ps != null: # 전투 뒤 안전 화면
		var sortie: Dictionary = ps
		var step := after_combat_step(run, sortie)
		if step == "event":
			for o in PEvents.options(run, sortie):
				out.append(_act("event:" + String(o.id), "event", String(o.name), bool(o.enabled), "", { "opt_id": String(o.id), "cost": String(o.cost), "effect": String(o.effect) }))
			return out
		if step == "offer":
			return out
		if sortie.get("eventFight", null) != null:
			out.append(_act("event_fight", "event_fight", "사건 추가 전투 시작", true, "", { "event_fight": String(sortie.eventFight) }))
			return out
		if bool(sortie.get("endless", false)): # 무한 전투 뒤: 더 깊이 없음, 정산만
			out.append(_act("return_home", "return_home", "전리품 정산 (다음 전투 준비)", true))
			return out
		var must := must_return(sortie)
		var can_deep := PRun.can_deep_explore(run, sortie) and not must
		out.append(_act("deep_explore", "deep_explore", "더 깊이 탐험 (+1칸)", can_deep, ("심층 승리 뒤에는 귀환만" if must else ("시간 부족/임무/이미 탐험" if not can_deep else "")), (PRun.deep_preview(run, sortie) if can_deep else {})))
		out.append(_act("return_home", "return_home", "전리품을 가지고 귀환", true))
		return out
	if phase == "endless" or phase == "endless_boss": # 무한 모드(PEndless): 전투 선택 / 재정비 / 구간 보스 / 마침. 거점 시설은 아래 공용 목록
		var E := PEndless.state(run)
		if phase == "endless":
			var nf := PEndless.next_fight(run)
			out.append(_act("endless_fight", "endless_fight", "무한 %d구간 전투 %d/%d: %s · %s" % [int(nf.segment), int(nf.fight), int(nf.perSegment), String(nf.name), String(nf.formationName)], true, "", nf))
			out.append(_act("endless_regroup", "endless_regroup", "재정비 (체력 완전 회복, 남은 %d회)" % int(E.get("regroupLeft", 0)), PEndless.can_regroup(run), "" if PEndless.can_regroup(run) else ("체력이 이미 최대" if int(E.get("regroupLeft", 0)) > 0 else "이번 구간 재정비 소진")))
		else:
			var bid := PEndless.boss_id(run)
			out.append(_act("boss_start", "boss_start", "무한 %d구간 보스 입장: %s" % [int(E.segment), String(PCatalog.boss_def(bid).name)], true, "", { "boss_id": bid, "endless": true, "segment": int(E.segment) }))
		out.append(_act("endless_quit", "endless_quit", "무한 모드 마치기 (기록 확정)", true))
	if phase == "boss_prep" or phase == "cleared":
		var nb := PRun.next_boss(run)
		out.append(_act("boss_start", "boss_start", "보스 입장: %s" % (String(PCatalog.boss_def(String(nb.id)).name) if not nb.is_empty() else "보스"), PRun.can_start_boss(run), "", { "boss_id": (String(nb.id) if not nb.is_empty() else "boss"), "stage": int(run.get("stage", 0)) }))
	if phase == "prep":
		for c in PSortie.all_cards(run):
			var ok := PSortie.can_start(run, c)
			var reason := ""
			if bool(c.done) and not bool(c.get("repeat", false)): reason = "완료한 카드"
			elif PRun.is_boss_day(run): reason = "관문 날"
			elif int(run.hours) < int(c.timeCost): reason = "시간 부족(%d칸 필요)" % int(c.timeCost)
			if bool(c.get("repeat", false)): # 남는 시간 반복 탐험(임무 보상·사건 없음)
				out.append(_act("sortie:" + String(c.id), "sortie", "%s · %s · %d칸" % [String(PRun.region(String(c.regionId)).name), String(c.get("label", "일반 탐험")), int(c.timeCost)], ok, reason, { "card_id": String(c.id), "region_id": String(c.regionId), "objective": "clear", "risk": null, "repeat": true, "time_cost": int(c.timeCost) }))
				continue
			var label := "%s · %s%s" % [String(PRun.region(String(c.regionId)).name), PSortie.objective_name(String(c.objective)), (" · " + String(PCatalog.mission_rules().riskText[String(c.risk)])) if c.get("risk", null) != null else ""]
			out.append(_act("sortie:" + String(c.id), "sortie", label, ok, reason, { "card_id": String(c.id), "region_id": String(c.regionId), "objective": String(c.objective), "risk": c.get("risk", null), "time_cost": int(c.timeCost), "steer": PSortie.steer_state(run, c) }))
		var rq := PRun.rest_quote(run) # 확인 창 견적을 그대로 실어 보낸다(화면은 계산하지 않는다). 확정은 PRun.rest
		out.append(_act("rest", "rest", "휴식 (체력 회복 → %s · %s)" % [String(rq.slotAfter), String(rq.costText)], bool(rq.can), String(rq.reason), rq))
		out.append(_act("end_day", "end_day", "하루 종료", true, "", PRun.preview_next_day(run)))
	# 거점 전용(출격·전투 중 불가): 상점·대장간·장비
	out.append(_act("shop_open", "shop_open", "상점", true))
	var st := PRun.stock(run)
	for id in st.equipment:
		var eid := String(id)
		var ok := PRun.can_buy_equipment(run, eid, "stock")
		var price := PRun.equip_price_for(run, eid, "stock")
		var reason := "" if ok else (("판매됨" if (st.sold as Array).has(eid) else ("보유 중" if PRun.owns_equip(run, eid) else "금화 부족(%d)" % price)))
		out.append(_act("buy_equipment:" + eid, "buy_equipment", "%s 구매 (%d)" % [PRun.equip_name(eid), price], ok, reason, { "id": eid, "from": "stock", "price": price }))
	if PRun.merchant_open(run):
		var m: Dictionary = run.merchant
		if m.get("equipment", null) != null:
			var eid := String(m.equipment)
			var ok := PRun.can_buy_equipment(run, eid, "merchant")
			var price := PRun.equip_price_for(run, eid, "merchant")
			out.append(_act("buy_equipment:" + eid + ":merchant", "buy_equipment", "%s 구매 (%d, 상인 할인)" % [PRun.equip_name(eid), price], ok, "" if ok else "판매됨/보유/금화 부족", { "id": eid, "from": "merchant", "price": price }))
		out.append(_act("buy_merchant_service", "buy_merchant_service", "%s 구매 (%d)" % [String(PCatalog.services()[String(m.service)].name), int(m.servicePrice)], PRun.can_buy_merchant_service(run), "", { "service": String(m.service), "price": int(m.servicePrice) }))
	if st.get("skill", null) != null:
		var sk: Dictionary = st.skill
		var nm := String(PCatalog.weapons()[String(sk.id)].name) if String(sk.kind) == "weapon" else String(PCatalog.skills()[String(sk.id)].name)
		out.append(_act("buy_skill", "buy_skill", "%s 획득 (%d)" % [nm, int(sk.price)], PRun.can_buy_skill(run), "" if PRun.can_buy_skill(run) else "판매됨/슬롯 없음/금화 부족", { "kind": String(sk.kind), "id": String(sk.id), "price": int(sk.price) }))
	for slot in run.equipment:
		if run.equipment[slot] != null:
			var eid := String(run.equipment[slot])
			out.append(_act("unequip:" + String(slot), "unequip", "%s 해제" % PRun.equip_name(eid), true, "", { "slot": String(slot), "id": eid }))
			var sq := PRun.sell_quote(run, eid)
			out.append(_act("sell:" + eid, "sell", "%s 판매 (+%d)" % [PRun.equip_name(eid), int(sq.gold)], bool(sq.can), String(sq.get("reason", "")), sq))
	for id in run.bag:
		var eid := String(id)
		out.append(_act("equip:" + eid, "equip", "%s 장착" % PRun.equip_name(eid), true, "", { "id": eid, "slot": String(PCatalog.equipment_def(eid).slot) }))
		var sqb := PRun.sell_quote(run, eid)
		out.append(_act("sell:" + eid, "sell", "%s 판매 (+%d)" % [PRun.equip_name(eid), int(sqb.gold)], bool(sqb.can), String(sqb.get("reason", "")), sqb))
	for mid in run.mats:
		if int(run.mats[mid]) > 0:
			out.append(_act("sell_mat:" + String(mid), "sell_mat", "%s 판매 (+%d)" % [String(PCatalog.materials()[String(mid)].name), int(PCatalog.materials()[String(mid)].sell)], true, "", { "mat_id": String(mid), "n": int(run.mats[mid]) }))
	for i in (g.weapons as Array).size():
		var q := PRun.swap_quote(run, "weapon", i)
		if not q.is_empty():
			out.append(_act("swap:weapon:%d" % i, "swap", "%s 교체 (%d)" % [String(PCatalog.weapons()[String(g.weapons[i].id)].name), int(q.price)], bool(q.affordable) and (q.options as Array).size() > 0, "" if bool(q.affordable) else "금화 부족", q))
	if g.skills.get("e", null) != null:
		var q := PRun.swap_quote(run, "e", 0)
		if not q.is_empty():
			out.append(_act("swap:e", "swap", "E 교체 (%d)" % int(q.price), bool(q.affordable) and (q.options as Array).size() > 0, "" if bool(q.affordable) else "금화 부족", q))
	# 대장간 강화는 자동기술 하나를 골라 투자한다(2026-09-08 시험값). 기술마다 행동을 낸다
	for w in run.get("growth", {}).get("weapons", []):
		var Fw := PRun.forge_next(run, String(w.id))
		if Fw.is_empty():
			continue
		out.append(_act("forge_upgrade:" + String(w.id), "forge_upgrade",
			"%s 강화 %d단계 (%d)" % [String(PCatalog.weapon(String(w.id)).name), int(Fw.weaponLv), int(Fw.cost)],
			bool(Fw.open) and bool(Fw.affordable),
			("보스 %d 처치 후 개방" % int(Fw.afterBoss)) if not bool(Fw.open) else ("" if bool(Fw.affordable) else "금화 부족"), Fw))

	# 새 지출처도 공용 행동 목록에 넣는다. 화면에만 있으면 봇이 쓸 수 없어
	# "금화가 남는다"는 측정이 '봇이 살 수 없는 것'을 남은 돈으로 세게 된다(2026-09-08).
	var rf := PRun.stock_refresh_cost(run)
	if rf > 0:
		var rf_ok := PRun.stock_refresh_reason(run) == ""
		out.append(_act("shop_refresh", "shop_refresh", "재고 새로고침 (%d)" % rf, rf_ok,
			PRun.stock_refresh_reason(run), { "cost": rf }))
	for cid in PConsumables.prep_ids():
		var cprice := PConsumables.price(String(cid))
		var creason := PConsumables.buy_reason(run, String(cid))
		out.append(_act("buy_consumable:" + String(cid), "buy_consumable",
			"%s 구매 (%d)" % [PConsumables.name_of(String(cid)), cprice], creason == "", creason,
			{ "id": String(cid), "price": cprice }))
		if PConsumables.count(run, String(cid)) > 0 and PConsumables.armed(run) != String(cid):
			var sreason := PConsumables.select_reason(run, String(cid))
			out.append(_act("arm_consumable:" + String(cid), "arm_consumable",
				"%s 장착" % PConsumables.name_of(String(cid)), sreason == "", sreason, { "id": String(cid) }))
	var pot := PConsumables.potion_def()
	if not pot.is_empty():
		var preason := PConsumables.buy_reason(run, "potion")
		out.append(_act("buy_potion", "buy_potion", "회복약 구매 (%d)" % int(pot.price),
			preason == "", preason, { "price": int(pot.price) }))
		out.append(_act("use_potion", "use_potion", "회복약 사용 (+%d)" % int(pot.heal),
			PConsumables.can_use_potion(run), "" if PConsumables.can_use_potion(run) else "쓸 수 없음",
			{ "heal": int(pot.heal) }))
	# 부활 물약: 사망 = 회차 종료 규칙의 유일한 대비책이라 봇도 살 수 있어야 한다(새 지출처가 행동 목록에 없어 봇이 못 사던 사고 재발 방지)
	var rev := PConsumables.revive_def()
	if not rev.is_empty():
		var rid := PConsumables.revive_id()
		var rreason := PConsumables.buy_reason(run, rid)
		out.append(_act("buy_revive", "buy_revive", "%s 구매 (%d, 보유 %d)" % [PConsumables.name_of(rid), int(rev.price), PConsumables.revive_count(run)],
			rreason == "", rreason, { "id": rid, "price": int(rev.price), "have": PConsumables.revive_count(run) }))
	var no_offer: bool = g.get("pendingOffer", null) == null
	var mc := PRun.mod_change_cost(run)
	for w in g.weapons:
		for m in w.mods:
			var ok: bool = no_offer and (bool(mc.voucher) or int(run.gold) >= int(mc.gold)) and not _mod_candidates(run, String(w.id), String(m)).is_empty()
			out.append(_act("mod_change:%s:%s" % [String(w.id), String(m)], "mod_change", "%s 개조 변경: %s (%s)" % [String(PCatalog.weapons()[String(w.id)].name), String(PCatalog.weapons()[String(w.id)].mods[String(m)].name), "변경권 사용" if bool(mc.voucher) else str(int(mc.gold))], ok, "" if ok else "후보 없음/금화 부족/제시 중", { "weapon_id": String(w.id), "mod_id": String(m), "cost": mc }))
	var e = g.skills.get("e", null)
	if e != null and e.get("variant", null) != null:
		var vc := PRun.variant_change_cost(run)
		var ok: bool = no_offer and (bool(vc.voucher) or int(run.gold) >= int(vc.gold))
		out.append(_act("variant_change", "variant_change", "E 변형 변경 (%s)" % ("변경권 사용" if bool(vc.voucher) else "%dG로 변경" % int(vc.gold)), ok, "" if ok else "금화 부족/제시 중", { "cost": vc }))
	return out
