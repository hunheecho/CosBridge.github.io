extends SceneTree
## 회차 계층 규칙 테스트(headless): godot --headless --path prophecy_godot -s tests/run_layer_tests.gd
## HTML test/run.test.js·flow·events·objectives(카드)·abuse_v08·balance_v08(통계) 케이스를 Godot 규칙으로 다시 쓴 것. 기대값은 GAME_SPEC §19·데이터에서.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 전투 없이 승리/패배 상태를 만든다(정산 규칙만 본다)
func fake_fight(run: Dictionary, sortie: Dictionary, won: bool, hp_left: float = 80.0) -> CombatState:
	var st := PFlow.make_encounter(run, sortie)
	st.spawn_hold = true
	st.step({}, STEP)
	st.status = "won" if won else "lost"
	st.player.hp = hp_left if won else 0.0
	return st

func _init() -> void:
	var C := PCatalog.config()
	# ---------- 시작 상태(HTML 154·162) ----------
	var run := PRun.new_run(1, "sword")
	var g: Dictionary = run.growth
	ok("새 회차: 1일차 새벽 5칸, 체력 100, 금화 60, 검 Lv1·Q Lv1·E 없음·장비 없음·강화 0, acts(10일), balance test03(경험치 ×0.3), 적 체력 base", int(run.day) == 1 and int(run.hours) == 5 and float(run.hp) == 100.0 and int(run.gold) == 60 and g.weapons.size() == 1 and String(g.weapons[0].id) == "sword" and g.skills.e == null and run.equipment.armor == null and int(run.forge) == 0 and String(run.mode) == "acts" and String(run.balance) == "test03" and is_equal_approx(PRun.kill_xp_mult(run), 0.3) and String(run.difficulty) == "base")
	var cards := PSortie.cards_for(run)
	ok("1일차 카드 2장 = 오늘의 장소(숲·능선), 전멸만(임무는 2일차부터), 시드 결정적·저장 필드", cards.size() == 2 and String(cards[0].regionId) == "forest" and String(cards[1].regionId) == "ridge" and String(cards[0].objective) == "clear" and String(cards[1].objective) == "clear" and run.cards != null, str(cards.map(func(c): return c.id)))
	var acts := PFlow.actions(run)
	var ids := acts.map(func(a): return String(a.id))
	ok("행동 목록(UI·봇 공용): 카드 2·휴식·하루 종료·상점·구매·기술·교체·강화 포함, 관문 입장 없음", ids.has("sortie:d1c1") and ids.has("sortie:d1c2") and ids.has("rest") and ids.has("end_day") and ids.has("shop_open") and ids.has("forge_upgrade") and not ids.has("boss_start"), str(ids))
	# ---------- 상점 재고(HTML 1·150) ----------
	var stock := PRun.stock(run)
	var st2 := PRun.stock(run)
	ok("상점: 하루 시드 재고 장비 2 + 기술 1, 다시 열어도 동일", (stock.equipment as Array).size() == 2 and stock.skill != null and str(stock.equipment) == str(st2.equipment) and int(stock.skill.price) == 180, str(stock.equipment))
	var eq0 := String(stock.equipment[0])
	ok("금화 60으로는 장비(120~140)를 살 수 없다", not PRun.can_buy_equipment(run, eq0, "stock"))
	run.gold = 500
	ok("구매 가능 → 구매·장착, 같은 장비 중복 구매 불가, 재고 판매 기록 유지", PRun.can_buy_equipment(run, eq0, "stock") and PRun.buy_equipment(run, eq0, true, "stock") and PRun.owns_equip(run, eq0) and not PRun.can_buy_equipment(run, eq0, "stock") and (PRun.stock(run).sold as Array).has(eq0), "gold %d equip %s bag %s" % [int(run.gold), str(run.equipment), str(run.bag)])
	var slot0 := String(PCatalog.equipment()[eq0].slot)
	var price0 := PRun.equip_price(eq0)
	ok("가격표: 무기 140·갑옷 120·방패 120, 판매 35/30/30", int(run.gold) == 500 - price0 and price0 == int(PCatalog.shop().price[slot0]) and PRun.sell_price(eq0) == int(PCatalog.shop().sellPrice[slot0]))
	PRun.unequip_item(run, slot0)
	PRun.equip_item(run, eq0)
	PRun.unequip_item(run, slot0)
	var gold_before := int(run.gold)
	PRun.sell_equipment(run, eq0)
	ok("탈착 반복으로 금화가 새지 않고 판매는 판매가만큼 1회", int(run.gold) == gold_before + PRun.sell_price(eq0) and not PRun.owns_equip(run, eq0) and (run.bag as Array).is_empty())
	run.bag.append("vitality_coat")
	PRun.equip_item(run, "vitality_coat")
	run.hp = 120.0
	PRun.unequip_item(run, "armor")
	ok("생명력의 외투 해제 시 현재 체력이 최대(100)를 넘지 않게 잘리고, 장착해도 회복 없음", float(run.hp) == 100.0)
	run.bag = []
	# ---------- 기술 구매·교체(HTML 2·151) ----------
	var sk: Dictionary = stock.skill
	ok("새 자동기술 180: 슬롯 남아 있으면 구매 가능", PRun.can_buy_skill(run) and String(sk.kind) == "weapon")
	var g_before := int(run.gold)
	PRun.buy_skill(run)
	ok("구매 뒤 자동기술 2개(Lv1, 개조 없음), 금화 -180, 재고 판매됨", g.weapons.size() == 2 and int(g.weapons[1].level) == 1 and int(run.gold) == g_before - 180 and not PRun.can_buy_skill(run))
	g.weapons[0] = { "id": "sword", "level": 3, "mods": ["cross"] }
	var q := PRun.swap_quote(run, "weapon", 0)
	ok("교체 견적: 120 + (3−1)×40 + 개조 1×80 = 280, 옵션은 미보유 자동기술만", int(q.price) == 280 and int(q.modCount) == 1 and not (q.options as Array).has("sword") and not (q.options as Array).has(String(g.weapons[1].id)), str(q))
	var gold_q := int(run.gold)
	ok("잘못된 개조·중복 개조·미보유 옵션은 실패하고 상태 불변", PRun.apply_swap(run, "weapon", 0, "spear", ["nope"]) == -1 and PRun.apply_swap(run, "weapon", 0, "spear", ["returning", "returning"]) == -1 and PRun.apply_swap(run, "weapon", 0, "sword", []) == -1 and int(run.gold) == gold_q and String(g.weapons[0].id) == "sword")
	run.gold = 100
	ok("금화 부족이면 교체 실패·상태 불변", PRun.apply_swap(run, "weapon", 0, "spear", ["returning"]) == -1 and String(g.weapons[0].id) == "sword")
	run.gold = 500
	var paid := PRun.apply_swap(run, "weapon", 0, "spear", ["returning"])
	ok("교체 확정: 관통창 Lv3·개조 1(귀환 검기), 금화 -280, 옛 기술 없음", paid == 280 and String(g.weapons[0].id) == "spear" and int(g.weapons[0].level) == 3 and g.weapons[0].mods == ["returning"] and int(run.gold) == 220 and PGrowth.weapon_of(g, "sword").is_empty())
	# ---------- 대장간(HTML 152·3) ----------
	var F := PRun.forge_next(run)
	ok("대장간 1단계 90, 시작부터 개방; 2단계는 보스 1 처치 뒤", int(F.lv) == 1 and int(F.cost) == 90 and bool(F.open))
	PRun.forge_upgrade(run)
	var F2 := PRun.forge_next(run)
	ok("강화 뒤 forge 1, 자동기술 피해 ×1.1, 2단계(160)는 잠김", int(run.forge) == 1 and is_equal_approx(float(PBuild.derive(run).forge_mult), 1.1) and int(F2.cost) == 160 and not bool(F2.open) and int(run.gold) == 130)
	var mods_before: Array = (g.weapons[0].mods as Array).duplicate()
	run.gold = 200
	var off_mc := PFlow.mod_change(run, "spear", "returning")
	ok("개조 변경 140: 개조를 떼고 같은 기술의 다른 개조 3택(귀환 제외), 금화 선차감", not off_mc.is_empty() and (off_mc.choices as Array).size() >= 1 and int(run.gold) == 60 and (g.weapons[0].mods as Array).is_empty() and (off_mc.choices as Array).all(func(c): return String(c.id) == "spear" and String(c.mod) != "returning"), str(off_mc.get("choices", [])))
	PFlow.cancel_paid_change(run, off_mc)
	ok("받지 않음: 원래 개조 복구 + 금화 환불, 제시 해제", g.weapons[0].mods == mods_before and int(run.gold) == 200 and g.pendingOffer == null)
	# ---------- 출격·정산(HTML 137·155·156·9) ----------
	run = PRun.new_run(3, "sword")
	g = run.growth
	var c1: Dictionary = PSortie.cards_for(run)[0]
	var sortie := PSortie.start(run, String(c1.id))
	ok("출격: 카드 시간 차감(숲 1칸), sortieCount 1, 시드 = seed×131 + 회차 출격수×17 + 일차, 새벽 변주 소규모 순찰", int(run.hours) == 4 and int(run.sortieCount) == 1 and int(sortie.seed) == 3 * 131 + 17 + 1 and sortie.variant != null and String(sortie.variant.name) == "소규모 순찰", str(sortie))
	var waves := PRun.encounter_waves("forest", false, run, sortie)
	ok("새벽 변주: 마지막 웨이브 없음 → 늑대 2+3(밀도 ×5 = 25마리)", waves.size() == 2 and int(waves[1][0].n) == 3)
	var dwaves := PRun.encounter_waves("forest", true, run, {})
	var last: Array = dwaves[dwaves.size() - 1]
	ok("더 깊이: 웨이브마다 +1, 마지막에 우두머리", int(dwaves[0][0].n) == 3 and last.any(func(gw): return String(gw.type) == "wolf_alpha"))
	var hm := PRun.hp_mult_for(run, "forest", false)
	run.day = 4
	var hm4 := PRun.hp_mult_for(run, "den", false)
	run.day = 1
	ok("체력 배율: 기본 ×1, 4일차부터 정예 ×1.25(체력만)", is_equal_approx(float(hm.normal), 1.0) and is_equal_approx(float(hm4.elite), 1.25) and is_equal_approx(float(hm4.normal), 1.0))
	var stw := fake_fight(run, sortie, true, 70.0)
	var reward := PFlow.settle_victory(run, sortie, stw)
	var rg: Dictionary = PCatalog.region("forest").reward
	ok("승리 정산: 금화는 지역 범위(30~45)×새벽 0.8 안, 지역 경험치 10×0.3=3, 체력 70 반영, 전리품은 미정산(run.gold 60 그대로)", int(reward.gold) >= int(round(float(rg.gold[0]) * 0.8)) and int(reward.gold) <= int(round(float(rg.gold[1]) * 0.8)) and is_equal_approx(float(reward.xp), 3.0) and float(run.hp) == 70.0 and int(run.gold) == 60 and int(sortie.loot.gold) == int(reward.gold), str(reward))
	ok("정산 뒤 pendingSortie 저장, 행동 목록은 더 깊이/귀환(또는 사건)", run.pendingSortie != null and PFlow.actions(run).any(func(a): return String(a.kind) in ["deep_explore", "return_home", "event"]))
	if sortie.get("event", null) != null:
		PEvents.resolve(run, sortie, "leave")
	var gold_before2 := int(run.gold)
	PFlow.return_home(run, sortie)
	var gold_after := int(run.gold)
	PRun.return_to_base(run, sortie)
	ok("귀환 정산 1회: 금화 반영, 두 번 정산해도 변화 없음", gold_after == gold_before2 + int(reward.gold) and int(run.gold) == gold_after and run.pendingSortie == null)
	# 패배
	var c2: Dictionary = PSortie.cards_for(run)[1]
	var sortie2 := PSortie.start(run, String(c2.id))
	var stl := fake_fight(run, sortie2, false)
	var gold_pre := int(run.gold)
	PFlow.settle_defeat(run, sortie2, stl)
	ok("일반 패배: 미정산 전리품 상실·남은 하루 상실 → 다음 날 새벽 정상 체력, 정산 금화 유지", int(run.day) == 2 and int(run.hours) == 5 and float(run.hp) == 100.0 and int(run.gold) == gold_pre and bool(sortie2.lost), "day %d hours %d gold %d" % [int(run.day), int(run.hours), int(run.gold)])
	# 휴식·하루 종료·관문(HTML 154·34)
	run.hp = 40.0
	PRun.rest(run)
	ok("휴식: 1칸 소모·완전 회복, 가득 차도 가능", int(run.hours) == 4 and float(run.hp) == 100.0 and PRun.can_rest(run))
	PRun.end_day(run) # 3일차
	var prev := PRun.preview_next_day(run)
	ok("3일차 종료 전 미리보기 = 4일차 관문(가시갈기) — 10일 본편", prev.has("boss") and String(prev.boss) == "boss", str(prev))
	PRun.end_day(run)
	ok("4일차 = 관문: phase boss_prep, 출격 불가, 행동 목록에 boss_start", String(run.phase) == "boss_prep" and not PRun.can_sortie(run, "ridge") and PFlow.actions(run).any(func(a): return String(a.id) == "boss_start"))
	# ---------- 보스 스냅샷·재도전·승리(HTML 6·35·118) ----------
	run.gold = 300
	var bs := PRun.start_boss(run)
	ok("보스 입장: 체력 완전 회복, 스냅샷(성장·금화·장비·강화), 시드 = seed×997+7+stage×31, 체력 후보 3500(pacing 오버레이 시험값, 재측정 뒤 조정)", float(run.hp) == 100.0 and run.bossEntry != null and int(bs.seed) == 3 * 997 + 7 and String(bs.bossId) == "boss" and int(PRun.boss_hp(run, "boss")) == 3500)
	var stb := PFlow.make_boss_encounter(run, bs)
	ok("보스 전투 생성: 보스 체력 3500, 공터, 소환 대기 없음", stb.boss.hp == 3500 and stb.arena_id == "clearing" and stb.spawn_total == 0)
	run.gold = 999
	PGrowth.add_xp(g, 100.0)
	stb.status = "lost"
	PFlow.settle_boss_defeat(run, stb)
	ok("보스 패배: 금화·성장 입장 시점으로 복구, 재도전 1회, 하루 손실 없음", int(run.gold) == 300 and int(run.growth.level) == 1 and int(run.bossRetries) == 1 and String(run.phase) == "boss_prep" and int(run.day) == 4)
	g = run.growth
	var bs2 := PRun.start_boss(run)
	ok("재도전은 같은 시드", int(bs2.seed) == int(bs.seed))
	var stb2 := PFlow.make_boss_encounter(run, bs2)
	stb2.status = "won"
	stb2.boss.dead = true
	stb2.stats.boss_damage = 3500
	stb2.player.hp = 55.0
	var rec := PFlow.settle_boss_victory(run, stb2)
	ok("보스 승리: 기록 1회, 다음 단계 해금(stage 1, prep, 5칸, 체력 회복), 희귀 보상 보류, 재도전 0", not rec.is_empty() and int(run.stage) == 1 and String(run.phase) == "prep" and int(run.hours) == 5 and float(run.hp) == 100.0 and run.growth.get("pendingBossPick", null) != null and int(run.bossRetries) == 0 and run.bossRecords.has("boss"))
	var off_b: Variant = PFlow.next_offer(run)
	ok("희귀 보상 3택(pool boss): 후보 2~3(유효 + 범용, 검만 있으면 범용 2개뿐 = HTML 동일), 저장된 제시 = 같은 제시", not off_b.is_empty() and String(off_b.pool) == "boss" and (off_b.choices as Array).size() >= 2 and (off_b.choices as Array).size() <= 3 and PFlow.next_offer(run) == off_b, str(off_b.get("choices", [])))
	PFlow.resolve_offer(run, off_b, off_b.choices[0])
	ok("희귀 보상 적용 뒤 제시 소비(다시 나오지 않음)", g.bossRewards.size() == 1 and PFlow.next_offer(run) == null and g.get("pendingBossPick", null) == null)
	# ---------- 성장 예약(HTML 8·138·139) ----------
	run = PRun.new_run(5, "sword")
	g = run.growth
	run.day = 2
	run.cards = null
	var cards2 := PSortie.cards_for(run)
	var mission_card := {}
	for c in cards2:
		if String(c.objective) != "clear":
			mission_card = c
	ok("2일차 카드: 최소 1장에 임무 목표(사냥/제단/봉인/구조), 보상 종류·대체 금화 표시", not mission_card.is_empty() and mission_card.rewardKind != null and int(mission_card.fallbackGold) > 0, str(cards2.map(func(c): return c.objective)))
	var ms := PSortie.start(run, String(mission_card.id))
	var stm := fake_fight(run, ms, true)
	var rw := PFlow.settle_victory(run, ms, stm)
	var steered: bool = g.get("steer", null) != null
	var picked_service: bool = g.get("pendingMissionPick", null) != null
	ok("임무 승리: 예약(steer) 또는 서비스 3택 보류, 재료 없음, 카드 완료", (steered or picked_service or rw.has("missionPick")) and bool(mission_card.done) and (rw.mats as Dictionary).is_empty(), str(rw))
	if steered:
		var kinds: Array = PCatalog.mission_rules().kindPools.get(String(g.steer.kind), [String(g.steer.kind)])
		g.pendingLevelUps = 1
		var off_s := PGrowth.generate_offer(run, { "pool": "level" })
		var all_kind: bool = (off_s.choices as Array).all(func(c): return kinds.has(String(c.kind)))
		ok("예약된 종류로 다음 레벨업 제시가 한정되고 1회 소비", all_kind and off_s.get("steer", null) != null, str(off_s.choices))
		PFlow.resolve_offer(run, off_s, off_s.choices[0])
		ok("선택 뒤 예약 해제", g.get("steer", null) == null)
	if ms.get("event", null) != null:
		PEvents.resolve(run, ms, "leave")
	PFlow.return_home(run, ms)
	ok("완료한 임무 카드는 다시 시작할 수 없다(하루 1회)", not PSortie.can_start(run, PSortie.card(run, String(mission_card.id))))
	# ---------- 심층 미리보기(F5)·더 깊이(HTML 106) ----------
	run = PRun.new_run(8, "sword")
	var cd: Dictionary = PSortie.cards_for(run)[0]
	var sd := PSortie.start(run, String(cd.id))
	var std := fake_fight(run, sd, true)
	PFlow.settle_victory(run, sd, std)
	if sd.get("event", null) != null:
		PEvents.resolve(run, sd, "leave")
	var pv1 := PRun.deep_preview(run, sd)
	var pv2 := PRun.deep_preview(run, sd)
	var kinds_seen := {}
	for s in range(20, 40):
		var r2 := PRun.new_run(s, "sword")
		var c3: Dictionary = PSortie.cards_for(r2)[0]
		var s3 := PSortie.start(r2, String(c3.id))
		kinds_seen[String(PRun.deep_preview(r2, s3).reward.kind)] = true
	ok("심층 미리보기: 같은 출격은 같은 보상(재현), 시드가 다르면 종류가 다양(2종 이상)", str(pv1.reward) == str(pv2.reward) and kinds_seen.size() >= 2, str(kinds_seen.keys()))
	ok("더 깊이 가능(시간 3칸 남음), 시작하면 +1칸·deep 표시", PRun.can_deep_explore(run, sd) and PRun.deep_explore(run, sd) and bool(sd.deep) and int(run.hours) == 3)
	var st_deep := fake_fight(run, sd, true)
	var rw_deep := PFlow.settle_victory(run, sd, st_deep)
	ok("심층 승리: 표시된 보상이 전리품에 1회 얹히고 귀환만 가능", rw_deep.has("deep") and bool(sd.deepRewarded) and PFlow.must_return(sd))
	# ---------- 사건(HTML 94~100) ----------
	var found := {}
	for s in range(100, 160):
		var r3 := PRun.new_run(s, "sword")
		var c4: Dictionary = PSortie.cards_for(r3)[0]
		var s4 := PSortie.start(r3, String(c4.id))
		var st4 := fake_fight(r3, s4, true, 60.0)
		PFlow.settle_victory(r3, s4, st4)
		if s4.get("event", null) != null:
			var evd: Dictionary = s4.event
			var opts := PEvents.options(r3, s4)
			found[String(evd.id)] = opts.size()
			var again: Variant = PEvents.roll(r3, s4)
			if again != null:
				found["dup"] = true
	ok("사건: 60시드에서 3종 이상 등장, 출격당 1회(이미 있으면 재굴림 없음), 선택지 2개 이상", found.size() >= 3 and not found.has("dup") and found.values().all(func(v): return typeof(v) != TYPE_INT or int(v) >= 2), str(found))
	# 보급소·시간의 샘 정산 1회
	var r5 := PRun.new_run(9, "sword")
	var c5: Dictionary = PSortie.cards_for(r5)[0]
	var s5 := PSortie.start(r5, String(c5.id))
	var st5 := fake_fight(r5, s5, true, 60.0)
	PFlow.settle_victory(r5, s5, st5)
	s5.event = { "id": "supply", "seed": 1, "resolved": false, "choice": null }
	var loot_g := int(s5.loot.gold)
	var res := PEvents.resolve(r5, s5, "loot")
	ok("보급소 물자: 출격 전리품 금화 +40(귀환 시 확정), 정산 1회·재선택 불가", int(s5.loot.gold) == loot_g + 40 and String(res.next) == "after" and bool(s5.event.resolved) and PEvents.options(r5, s5).is_empty() == false)
	var r6 := PRun.new_run(9, "sword")
	var c6: Dictionary = PSortie.cards_for(r6)[0]
	var s6 := PSortie.start(r6, String(c6.id))
	PFlow.settle_victory(r6, s6, fake_fight(r6, s6, true, 60.0))
	s6.event = { "id": "time_spring", "seed": 1, "resolved": false, "choice": null }
	PEvents.resolve(r6, s6, "buff")
	var b6 := PBuild.derive(r6)
	ok("시간의 샘: 다음 전투 1회 Q/E 재사용 ×0.7(빌드 파생에 반영), 정산 때 소비", r6.buffs.has("skillCd") and is_equal_approx(float(b6.special_cd), 14.0 * 0.7))
	var st6 := PFlow.make_encounter(r6, { "regionId": "forest", "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 77, "day": 1, "slot": 0, "variant": null })
	PFlow.consume_buff(r6, st6)
	ok("전투 시작 뒤 강화 소비", not r6.buffs.has("skillCd") and st6.temp_buff == "skillCd")
	# ---------- 저장·복구(HTML 157·7·101) ----------
	var r7 := PRun.new_run(11, "blades")
	r7.growth.pendingLevelUps = 1
	var off7: Variant = PFlow.next_offer(r7)
	ok("저장: 보류 3택이 있는 상태로 저장 성공", PSave.save(r7) and PSave.exists())
	var loaded := PSave.load()
	ok("복구: 핵심 상태 동일(정규화 뒤 JSON 일치), 같은 제시가 다시 나오고 두 번 적용되지 않음", not loaded.is_empty() and JSON.stringify(PSave.normalize(r7)) == JSON.stringify(loaded) and JSON.stringify(PFlow.next_offer(loaded).choices) == JSON.stringify(off7.choices) and int(loaded.growth.pendingLevelUps) == 1, "len %d/%d" % [JSON.stringify(PSave.normalize(r7)).length(), JSON.stringify(loaded).length()])
	PSave.clear()
	ok("저장 삭제 뒤 계속하기 불가", not PSave.exists() and PSave.load().is_empty())
	# ---------- 피해 통계(HTML 12) ----------
	var r8 := PRun.new_run(12, "sword")
	var c8: Dictionary = PSortie.cards_for(r8)[0]
	var s8 := PSortie.start(r8, String(c8.id))
	var st8 := PFlow.make_encounter(r8, s8)
	for i in 600:
		st8.step({}, STEP)
	st8.status = "won"
	PFlow.settle_victory(r8, s8, st8)
	PFlow.settle_victory(r8, s8, st8)
	var views := PStats.views(r8)
	var ver := PStats.verify(r8)
	ok("통계: 전투 1회만 기록(중복 정산 없음), 출처 합 = 총합, 4 보기 검증 통과, 받은 피해 유효/명목 분리", (r8.dmgStats.combats as Array).size() == 1 and ver.all(func(v): return bool(v.ok)) and views.all.rows.size() >= 1 and (r8.dmgStats.combats[0] as Dictionary).has("takenNominal"), str(ver))
	# ---------- F6(Codex 검수): 정산 정확히 1회·자격 ----------
	var r9 := PRun.new_run(13, "sword")
	var s9 := PSortie.start(r9, String(PSortie.cards_for(r9)[0].id))
	var st9 := fake_fight(r9, s9, true, 70.0)
	var rw9 := PFlow.settle_victory(r9, s9, st9)
	var snap9 := { "gold": int(s9.loot.gold), "xp": float(r9.growth.xp), "wins": int(r9.stats.wins), "enc": int(s9.encounters), "hp": float(r9.hp) }
	var rw9b := PFlow.settle_victory(r9, s9, st9)
	ok("같은 전투 승리 정산 2회째는 {} 반환·전리품/경험치/승리 수/조우 수 불변, 통계 1건", rw9b.is_empty() and not rw9.is_empty() and int(s9.loot.gold) == snap9.gold and is_equal_approx(float(r9.growth.xp), snap9.xp) and int(r9.stats.wins) == snap9.wins and int(s9.encounters) == snap9.enc and (r9.dmgStats.combats as Array).size() == 1, str(snap9))
	PFlow.settle_defeat(r9, s9, st9)
	ok("승리 전투를 패배 정산에 넘겨도 무시(하루 손실 없음)", int(r9.day) == 1 and int(r9.hours) == 4 and (r9.dmgStats.combats as Array).size() == 1)
	var r9c := PRun.new_run(13, "sword")
	var s9c := PSortie.start(r9c, String(PSortie.cards_for(r9c)[0].id))
	var st9c := fake_fight(r9c, s9c, false)
	var rw9c := PFlow.settle_victory(r9c, s9c, st9c)
	ok("패배(lost) 전투는 승리 정산 자격 없음: {} 반환, 금화·경험치 불변", rw9c.is_empty() and int(s9c.loot.gold) == 0 and float(r9c.growth.xp) == 0.0 and st9c.settled == "")
	PFlow.settle_defeat(r9c, s9c, st9c)
	var day9 := int(r9c.day)
	PFlow.settle_defeat(r9c, s9c, st9c)
	ok("패배 정산 2회째 무시(다음 날로 두 번 넘어가지 않음)", int(r9c.day) == day9 and day9 == 2 and st9c.settled == "lost")
	# ---------- F4(Codex 검수): 지속 피해 DPS 분모 = 원천 기술 보유 시간 ----------
	var r10 := PRun.new_run(14, "sword")
	r10.dmgStats = { "combats": [{ "elapsed": 20.0, "dmg": { "weapon:daggers": 100.0, "dot:bleed@daggers": 100.0, "dot:burn@ember": 40.0, "common:frost": 10.0 }, "total": 250.0, "taken": 0.0, "activeT": { "weapon:sword": 20.0, "weapon:daggers": 5.0, "weapon:ember": 10.0, "common:frost": 8.0 }, "kind": "sortie", "won": true }], "byKey": {} }
	var agg10 := PStats.aggregate(r10)
	var by_key := {}
	for row in agg10.rows:
		by_key[String(row.key)] = row
	ok("쌍검 출혈: 분모 = 쌍검 보유 5초 → DPS 20(직접과 같은 분모), 화상(불씨)는 불씨 보유 10초 → 4, 얼음 파편은 자기 보유 8초 → 1.25", is_equal_approx(float(by_key["dot:bleed@daggers"].dps), 20.0) and is_equal_approx(float(by_key["dot:bleed@daggers"].active), 5.0) and is_equal_approx(float(by_key["dot:burn@ember"].dps), 4.0) and is_equal_approx(float(by_key["common:frost"].dps), 1.3), str(by_key["dot:bleed@daggers"]))
	var grp := PStats.by_owner(agg10)
	var dag := {}
	for gr in grp:
		if String(gr.owner) == "weapon:daggers":
			dag = gr
	ok("기술별 묶음: 쌍검 = 직접 100 + 파생(출혈) 100 = 200, 보유 5초 → DPS 40", not dag.is_empty() and is_equal_approx(float(dag.direct), 100.0) and is_equal_approx(float(dag.derived), 100.0) and is_equal_approx(float(dag.dps), 40.0), str(dag))
	r10.dmgStats.combats[0].erase("activeT")
	var agg10b := PStats.aggregate(r10)
	var old_row := {}
	for row in agg10b.rows:
		if String(row.key) == "dot:bleed@daggers":
			old_row = row
	ok("activeT가 없는 옛 기록은 전투 시간 전체(20초)로 계산(오류 없음)", is_equal_approx(float(old_row.active), 20.0) and is_equal_approx(float(old_row.dps), 5.0))
	var r11 := PRun.new_run(15, "sword")
	r11.growth.commons = { "frost": 1 }
	r11.growth.bossRewards = ["vigor"]
	var s11 := PSortie.start(r11, String(PSortie.cards_for(r11)[0].id))
	var st11 := PFlow.make_encounter(r11, s11)
	st11.spawn_hold = true
	for i in 120:
		st11.step({}, STEP)
	ok("전투 중 공용 증강·희귀 보상 보유 시간이 기록된다(1초)", is_equal_approx(snapped(float(st11.active_t.get("common:frost", 0.0)), 0.01), 1.0) and is_equal_approx(snapped(float(st11.active_t.get("reward:vigor", 0.0)), 0.01), 1.0), str(st11.active_t))
	# ---------- 밀도 세트(Q1 비교 후보): 역할별 배율, 경험치 예산 보존 ----------
	var ru := PRun.new_run(21, "sword")
	var rr := PRun.new_run(21, "sword")
	rr.densitySet = "roles"
	var so := { "regionId": "ridge", "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 5, "day": 1, "slot": 1, "variant": null }
	var fu: Dictionary = PFlow.make_encounter(ru, so).formation
	var fr: Dictionary = PFlow.make_encounter(rr, so).formation
	var xp_u := 0.0
	var xp_r := 0.0
	for t in fu.html_counts:
		xp_u += float(fu.xp_map[t]) * float(fu.godot_counts[t])
		xp_r += float(fr.xp_map[t]) * float(fr.godot_counts[t])
	ok("밀도 세트 roles: 능선 1일차 궁수 7→14(×2)·늑대 4→20(×5), 동시 상한·종류별 상한은 일괄 세트와 같음", int(fr.godot_counts.archer) == 14 and int(fr.godot_counts.wolf) == 20 and int(fu.godot_counts.archer) == 35 and int(fr.alive_cap) == int(fu.alive_cap) and str(fr.type_caps) == str(fu.type_caps), str(fr.godot_counts))
	ok("경험치 예산 보존: 두 세트의 처치 경험치 합이 같고(HTML 예산), 궁수 1마리 값은 roles에서 ÷2·uniform에서 ÷5", is_equal_approx(xp_u, xp_r) and is_equal_approx(float(fr.xp_map.archer) * 2.0, float(fu.xp_map.archer) * 5.0), "xp %.3f vs %.3f" % [xp_u, xp_r])
	var rd := PRun.new_run(21, "sword")
	rd.densitySet = "roles"
	rd.day = 3
	var sd3 := { "regionId": "den", "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 5, "day": 3, "slot": 1, "variant": null }
	var fd: Dictionary = PFlow.make_encounter(rd, sd3).formation
	ok("정예(우두머리)는 두 세트 모두 ×1이고 경험치 단위값은 HTML 값 그대로(일반 적 ÷ 규칙과 분리)", int(fd.godot_counts.wolf_alpha) == 1 and is_equal_approx(float(fd.xp_map.wolf_alpha), PGrowth.xp_value_unit("wolf_alpha", false, "den", 0.3)), str(fd.xp_map))
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
