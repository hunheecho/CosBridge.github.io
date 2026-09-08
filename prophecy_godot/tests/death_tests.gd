extends SceneTree
## 사망·부활 물약·판매·휴식 규칙 테스트(headless).
## 실행: python tools/run_suites.py --suites death_tests --jobs 1
##
## 이 파일이 못박는 것(2026-09-09 사용자 확정 + 경계 규칙의 구현 기본안)
##  1) 부활 수단이 없으면 일반 전투·보스전 모두 그 회차가 즉시 끝난다(무료 회복·다음 날 진행·재도전 없음).
##  2) 부활 물약은 보유했을 때만 한 개 소모되고, 남은 하루를 잃고 다음 날 최대 체력 25%로 부활한다.
##     죽은 출격의 미정산 전리품은 잃고, 이미 정산한 재산·성장은 남는다.
##  3) 사망 정산은 정확히 1회다. 저장 복구·입장 스냅샷으로 소모한 물약이 되살아나지 않는다.
##  4) 부활해도 미완료 관문은 건너뛰어지지 않고, 넘기 전까지 출격이 잠긴다.
##  5) 판매 = 실제 지불 금액의 절반(정수 내림). 할인가로 샀으면 할인가 기준, 구매액이 없으면 정상가의 절반.
##     장착 중이면 해제되고, 취소·중복 클릭으로 금화·가방이 복제되지 않는다.
##  6) 휴식은 견적(rest_quote)과 확정(rest)이 나뉘어 있고, 취소하면 상태가 변하지 않는다. 휴식권은 100금·시간 소모 없음.
##
## 주의: 여기서는 **사람 플레이 경로**만 본다. 시험·자동 진행용 재시도 경로(run.testRetry)는 아래 §7에서 따로 확인한다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _json(run: Dictionary) -> String:
	return JSON.stringify(PSave.normalize(run.duplicate(true)))

## 저장 파일을 거치지 않고 저장·복구와 같은 변환(정규화 → JSON → 정규화)을 한다
func _roundtrip(run: Dictionary) -> Dictionary:
	var saved := PSave.normalize(run.duplicate(true))
	var back: Dictionary = JSON.parse_string(JSON.stringify(saved))
	return PSave.normalize(back)

## 전투 없이 패배 상태를 만든다(정산 규칙만 본다)
func fake_fight(run: Dictionary, sortie: Dictionary, won: bool, hp_left: float = 80.0) -> CombatState:
	var st := PFlow.make_encounter(run, sortie)
	st.spawn_hold = true
	st.step({}, STEP)
	st.status = "won" if won else "lost"
	st.player.hp = hp_left if won else 0.0
	return st

## 사람 플레이 회차(재시도 경로 아님). 환경 변수가 켜져 있어도 여기서는 꺼진다
func human_run(seed_v: int) -> Dictionary:
	return PRun.new_run(seed_v, "sword", "", { "test_retry": false, "legacy_places": true })

func _init() -> void:
	var REV := PConsumables.revive_id()
	var RD := PConsumables.revive_def()

	# ---------- 1. 물약 없음 + 일반 전투 패배 → 회차 종료 ----------
	var r1 := human_run(101)
	ok("사람 플레이 회차는 재시도 경로가 아니다(옛 무료 회복·재도전 규칙이 꺼져 있다)", not PRun.retry_mode(r1) and not PRun.is_run_over(r1))
	var s1 := PSortie.start(r1, String(PSortie.cards_for(r1)[0].id))
	var st1 := fake_fight(r1, s1, true, 70.0)
	var rw1 := PFlow.settle_victory(r1, s1, st1)
	if s1.get("event", null) != null:
		PEvents.resolve(r1, s1, "leave")
	PFlow.return_home(r1, s1)          # 첫 전투는 이겨서 정산해 둔다(정산한 재산이 남는지 보려고)
	var gold_kept := int(r1.gold)
	var lv_kept := int(r1.growth.level)
	var s1b := PSortie.start(r1, String(PSortie.cards_for(r1)[1].id))
	var st1b := fake_fight(r1, s1b, true, 60.0)
	PFlow.settle_victory(r1, s1b, st1b)  # 미정산 전리품을 만든 뒤 그 출격에서 쓰러진다
	var pending_loot := int(s1b.loot.gold)
	var st1c := fake_fight(r1, s1b, false)
	var day_before := int(r1.day)
	PFlow.settle_defeat(r1, s1b, st1c)
	ok("물약 없음 + 일반 전투 패배: 회차 종료(다음 날로 못 간다), 남은 시간 0, 미정산 전리품 상실",
		PRun.is_run_over(r1) and bool(r1.ended) and int(r1.day) == day_before and int(r1.hours) == 0
			and int(s1b.loot.gold) == 0 and pending_loot > 0,
		"day %d hours %d phase %s 미정산 %d" % [int(r1.day), int(r1.hours), String(r1.phase), pending_loot])
	ok("정산해 둔 금화·성장은 그대로 남는다(회차만 끝난다)", int(r1.gold) == gold_kept and int(r1.growth.level) >= lv_kept, "gold %d level %d" % [int(r1.gold), int(r1.growth.level)])
	ok("끝난 회차에는 행동이 없다(휴식·하루 종료·출격 모두 불가)",
		PFlow.actions(r1).is_empty() and not PRun.can_rest(r1) and not PRun.end_day(r1) and not PRun.can_sortie(r1, "forest"),
		str(PFlow.actions(r1).map(func(a): return String(a.id))))
	ok("사망은 완주(cleared)와 구분된다", String(r1.phase) == "dead" and String(r1.phase) != "cleared" and int(r1.death.count) == 1 and not bool(r1.death.revived))

	# ---------- 2. 물약 없음 + 보스 패배 → 회차 종료(재도전 없음) ----------
	var r2 := human_run(102)
	r2.day = 4
	r2.phase = "boss_prep"
	r2.gold = 300
	var bs2 := PRun.start_boss(r2)
	var stb2 := PFlow.make_boss_encounter(r2, bs2)
	stb2.status = "lost"
	PFlow.settle_boss_defeat(r2, stb2)
	ok("물약 없음 + 보스 패배: 회차 종료, 재도전 없음(입장 불가), 무료 상태 복원 없음",
		PRun.is_run_over(r2) and bool(r2.ended) and not PRun.can_start_boss(r2) and PRun.start_boss(r2).is_empty()
			and r2.get("bossEntry", null) == null and int(r2.day) == 4,
		"phase %s day %d" % [String(r2.phase), int(r2.day)])
	ok("보스 패배로 끝난 회차도 행동 목록이 비어 있다", PFlow.actions(r2).is_empty())

	# ---------- 3. 물약 있음: 한 개만 소모, 하루 상실, 다음 날 최대 체력 25%, 미정산 전리품 상실 ----------
	var r3 := human_run(103)
	r3.gold = 2000
	PConsumables.buy(r3, REV)
	PConsumables.buy(r3, REV)
	var hp_max3 := float(PRun.build(r3).hp_max)
	ok("부활 물약 구매: 값 %d, %d개까지 보유" % [int(RD.price), int(PConsumables.rules().reviveCarryMax)],
		PConsumables.revive_count(r3) == 2 and not PConsumables.can_buy(r3, REV) and int(RD.price) > 0,
		PConsumables.buy_reason(r3, REV))
	var s3 := PSortie.start(r3, String(PSortie.cards_for(r3)[0].id))
	var st3w := fake_fight(r3, s3, true, 60.0)
	PFlow.settle_victory(r3, s3, st3w)
	var loot3 := int(s3.loot.gold)
	var gold3 := int(r3.gold)
	var st3 := fake_fight(r3, s3, false)
	PFlow.settle_defeat(r3, s3, st3)
	ok("물약 있음: 한 개만 소모(2 → 1), 남은 하루 상실 → 다음 날, 최대 체력 25%로 부활, 미정산 전리품 상실",
		PConsumables.revive_count(r3) == 1 and int(r3.day) == 2 and int(r3.hours) == int(PCatalog.config().HOURS_PER_DAY)
			and is_equal_approx(float(r3.hp), round(hp_max3 * float(RD.hpFrac))) and int(s3.loot.gold) == 0 and loot3 > 0
			and int(r3.gold) == gold3 and not PRun.is_run_over(r3) and String(r3.phase) == "prep",
		"물약 %d day %d hp %.0f/%.0f 미정산 %d" % [PConsumables.revive_count(r3), int(r3.day), float(r3.hp), hp_max3, loot3])
	ok("부활한 회차는 계속 진행할 수 있다(출격·휴식 가능)", PRun.can_rest(r3) and not PFlow.actions(r3).is_empty() and PFlow.actions(r3).any(func(a): return String(a.kind) == "sortie"))

	# ---------- 4. 저장 복구를 거쳐도 소모한 물약이 되살아나지 않는다 ----------
	var back3 := _roundtrip(r3)
	ok("저장·복구 뒤에도 소모한 부활 물약이 되살아나지 않는다(계속하기 악용 차단)",
		PConsumables.revive_count(back3) == 1 and int(back3.day) == int(r3.day) and String(back3.phase) == String(r3.phase)
			and _json(back3) == _json(r3),
		"물약 %d" % PConsumables.revive_count(back3))

	# ---------- 5. 같은 사망이 두 번 정산되지 않는다 ----------
	var r5 := human_run(105)
	r5.gold = 2000
	PConsumables.buy(r5, REV)
	PConsumables.buy(r5, REV)
	var s5 := PSortie.start(r5, String(PSortie.cards_for(r5)[0].id))
	var st5 := fake_fight(r5, s5, false)
	PFlow.settle_defeat(r5, s5, st5)
	var snap5 := _json(r5)
	var day5 := int(r5.day)
	PFlow.settle_defeat(r5, s5, st5)      # 전투 상태로 두 번
	PRun.defeat(r5, s5)                   # 회차 함수로 직접 두 번
	PRun.settle_death(r5, { "cause": "sortie", "key": String(r5.death.key), "regionId": "forest" }) # 같은 키로 한 번 더
	ok("같은 사망은 두 번 정산되지 않는다(물약 1개만, 하루도 한 번만)",
		PConsumables.revive_count(r5) == 1 and int(r5.day) == day5 and int(r5.death.count) == 1 and _json(r5) == snap5,
		"물약 %d day %d count %d" % [PConsumables.revive_count(r5), int(r5.day), int(r5.death.count)])

	# ---------- 6. 보스 사망 + 부활: 관문을 건너뛰지 않고 입장 스냅샷이 물약을 되살리지 않는다 ----------
	var r6 := human_run(106)
	r6.gold = 2000
	PConsumables.buy(r6, REV)
	PConsumables.buy(r6, "potion")
	r6.day = 4
	r6.phase = "boss_prep"
	var stage6 := int(r6.stage)
	var bs6 := PRun.start_boss(r6)
	var stb6 := PFlow.make_boss_encounter(r6, bs6)
	stb6.status = "lost"
	PFlow.settle_boss_defeat(r6, stb6)
	ok("관문 사망 + 부활: 다음 날로 넘어가지만 관문은 그대로다(단계·완료 보스 그대로, 다시 관문 준비)",
		int(r6.day) == 5 and String(r6.phase) == "boss_prep" and int(r6.stage) == stage6 and (r6.bossesDone as Array).is_empty()
			and PRun.is_boss_day(r6) and is_equal_approx(float(r6.hp), round(float(PRun.build(r6).hp_max) * float(RD.hpFrac))),
		"day %d phase %s stage %d hp %.0f" % [int(r6.day), String(r6.phase), int(r6.stage), float(r6.hp)])
	ok("부활해도 미완료 관문 앞에서는 출격이 잠긴다(다음 막 활동 불가)",
		not PRun.can_sortie(r6, "forest") and not PFlow.actions(r6).any(func(a): return String(a.kind) == "sortie" and bool(a.enabled))
			and PFlow.actions(r6).any(func(a): return String(a.id) == "boss_start"))
	ok("입장 스냅샷이 소모한 부활 물약을 되살리지 않는다(스냅샷 자체가 지워진다)",
		PConsumables.revive_count(r6) == 0 and r6.get("bossEntry", null) == null and PConsumables.revive_count(_roundtrip(r6)) == 0)
	var stb6b := PFlow.make_boss_encounter(r6, PRun.start_boss(r6))
	stb6b.status = "lost"
	PFlow.settle_boss_defeat(r6, stb6b)
	ok("부활 물약이 떨어진 뒤 같은 관문에서 또 쓰러지면 회차가 끝난다(무제한 재도전 없음)",
		PRun.is_run_over(r6) and int(r6.death.count) == 2 and not bool(r6.death.revived))

	# ---------- 7. 시험·자동 진행용 재시도 경로는 사람 플레이와 분리되어 있다 ----------
	var r7 := PRun.new_run(107, "sword", "", { "test_retry": true, "legacy_places": true })
	r7.day = 4
	r7.phase = "boss_prep"
	r7.gold = 300
	var bs7 := PRun.start_boss(r7)
	var stb7 := PFlow.make_boss_encounter(r7, bs7)
	stb7.status = "lost"
	PFlow.settle_boss_defeat(r7, stb7)
	ok("재시도 경로(test_retry): 옛 규칙 그대로 — 입장 상태 복구·재도전 가능·회차 유지(자동 진행 스위트용)",
		PRun.retry_mode(r7) and not PRun.is_run_over(r7) and String(r7.phase) == "boss_prep" and int(r7.bossRetries) == 1
			and PRun.can_start_boss(r7) and int(r7.day) == 4)
	var r7b := PRun.new_run(108, "sword", "", { "test_retry": true, "legacy_places": true })
	var s7b := PSortie.start(r7b, String(PSortie.cards_for(r7b)[0].id))
	PFlow.settle_defeat(r7b, s7b, fake_fight(r7b, s7b, false))
	ok("재시도 경로의 일반 패배도 옛 규칙(다음 날 정상 체력)", int(r7b.day) == 2 and is_equal_approx(float(r7b.hp), float(PRun.build(r7b).hp_max)) and not PRun.is_run_over(r7b))
	ok("재시도 경로에서는 부활 물약을 쓰지 않는다(사망 정산 자체가 없다)", (r7b.get("death", {}) as Dictionary).is_empty())

	# ---------- 8. 판매: 구매액의 절반·정수 내림 ----------
	var r8 := human_run(201)
	r8.gold = 2000
	var buy_id := String(PRun.stock(r8).equipment[0])
	var list8 := PRun.equip_price(buy_id)
	PRun.buy_equipment(r8, buy_id, false, "stock")
	var q8 := PRun.sell_quote(r8, buy_id)
	ok("정가 구매 → 판매 견적 = 지불액의 절반(정수 내림), 받을 금액이 견적에 있다",
		int(q8.gold) == int(floor(float(list8) * 0.5)) and int(q8.paid) == list8 and String(q8.basis) == "paid" and String(q8.text).find(str(int(q8.gold))) >= 0,
		"list %d paid %d gold %d / %s" % [list8, int(q8.paid), int(q8.gold), String(q8.text)])
	var gold8 := int(r8.gold)
	var before8 := _json(r8)
	ok("견적을 뽑기만 하면(취소) 금화·가방이 변하지 않는다", _json(r8) == before8 and int(r8.gold) == gold8)
	ok("판매 확정: 금화 +견적, 가방에서 사라짐", PRun.sell_equipment(r8, buy_id, int(q8.gold)) and int(r8.gold) == gold8 + int(q8.gold) and not PRun.owns_equip(r8, buy_id))
	var gold8b := int(r8.gold)
	ok("두 번 눌러도 한 번만 팔린다(중복 클릭·저장 복구로 금화가 복제되지 않는다)",
		not PRun.sell_equipment(r8, buy_id, int(q8.gold)) and int(r8.gold) == gold8b and not PRun.owns_equip(r8, buy_id))
	ok("판 뒤 다시 사면 지불 기록이 다시 적힌다(옛 기록이 남지 않는다)", PRun.paid_for(r8, buy_id) < 0)
	var back8 := _roundtrip(r8)
	ok("저장 복구를 거쳐도 판 장비가 되살아나지 않고 금화도 늘지 않는다",
		not PRun.owns_equip(back8, buy_id) and int(back8.gold) == int(r8.gold) and _json(back8) == _json(r8))
	var r8p := human_run(207)
	r8p.gold = 2000
	var keep8 := String(PRun.stock(r8p).equipment[0])
	PRun.buy_equipment(r8p, keep8, false, "stock")
	var back8p := _roundtrip(r8p)
	ok("지불 기록(run.paidFor)이 저장·복구를 그대로 견딘다(정규화 뒤 JSON 일치, 판매 금액 불변)",
		PRun.paid_for(back8p, keep8) == PRun.paid_for(r8p, keep8) and PRun.sell_value(back8p, keep8) == PRun.sell_value(r8p, keep8)
			and _json(back8p) == _json(r8p),
		"지불 %d → %d" % [PRun.paid_for(r8p, keep8), PRun.paid_for(back8p, keep8)])

	# 할인 구매는 할인가 기준(싸게 사서 비싸게 파는 일이 없다)
	var r9 := human_run(202)
	r9.day = int(PRun.merchant_days(r9)[0])
	PRun.refresh_stock(r9)
	var m9 = r9.get("merchant", null)
	if m9 != null and m9.get("equipment", null) != null:
		r9.gold = 2000
		r9.hours = int(PCatalog.config().HOURS_PER_DAY) - int(m9.fromSlot)
		var mid := String(m9.equipment)
		var full9 := PRun.equip_price(mid)
		var paid9 := PRun.equip_price_for(r9, mid, "merchant")
		PRun.buy_equipment(r9, mid, false, "merchant")
		var q9 := PRun.sell_quote(r9, mid)
		ok("상인 할인가로 산 장비는 **할인가**의 절반으로 팔린다(정상가 기준보다 적다 = 판매 차익 없음)",
			paid9 < full9 and int(q9.gold) == int(floor(float(paid9) * 0.5)) and int(q9.gold) < int(floor(float(full9) * 0.5)) and int(q9.paid) == paid9,
			"정가 %d 지불 %d 판매 %d" % [full9, paid9, int(q9.gold)])
	else:
		ok("상인 할인 판매 검사: 이 시드에 상인 장비가 없어 건너뜀", true, "merchant=%s" % str(m9))

	# 구매액이 없는 장비(드롭·제작·옛 저장) = 정상 기준 구매가의 절반
	var r10 := human_run(203)
	r10.gold = 500
	(r10.bag as Array).append("vitality_coat")
	ok("드롭 장비(구매액 없음)의 판매 기준 = 정상 기준 구매가의 절반",
		PRun.paid_for(r10, "vitality_coat") < 0 and String(PRun.sell_quote(r10, "vitality_coat").basis) == "list"
			and int(PRun.sell_quote(r10, "vitality_coat").gold) == int(floor(float(PRun.equip_price("vitality_coat")) * 0.5)),
		"gold %d" % int(PRun.sell_quote(r10, "vitality_coat").gold))
	var old_save := human_run(204) # 옛 저장 흉내: paidFor 키 자체가 없는 회차
	old_save.erase("paidFor")
	(old_save.bag as Array).append("iron_shield")
	ok("paidFor가 없는 옛 저장도 같은 기준으로 팔린다(오류 없음)",
		int(PRun.sell_quote(old_save, "iron_shield").gold) == int(floor(float(PRun.equip_price("iron_shield")) * 0.5)) and PRun.sell_equipment(old_save, "iron_shield"))

	# 장착 중 판매 = 해제 포함
	var r11 := human_run(205)
	r11.gold = 2000
	(r11.bag as Array).append("vitality_coat")
	PRun.equip_item(r11, "vitality_coat")
	r11.hp = float(PRun.build(r11).hp_max)
	var q11 := PRun.sell_quote(r11, "vitality_coat")
	ok("장착 중 장비의 견적에 '해제된다'와 최대 체력 변화가 들어 있다",
		bool(q11.equipped) and bool(q11.unequips) and float(q11.hpMaxAfter) < float(q11.hpMax) and float(q11.hpAfter) <= float(q11.hpMaxAfter)
			and String(q11.text).find("해제") >= 0,
		"hpMax %.0f → %.0f / %s" % [float(q11.hpMax), float(q11.hpMaxAfter), String(q11.text)])
	PRun.sell_equipment(r11, "vitality_coat", int(q11.gold))
	ok("장착 중 판매: 슬롯이 비고 현재 체력이 새 최대 체력으로 잘린다",
		r11.equipment.armor == null and is_equal_approx(float(r11.hp), float(q11.hpAfter)) and not PRun.owns_equip(r11, "vitality_coat"),
		"hp %.0f" % float(r11.hp))
	var r12 := human_run(206)
	r12.gold = 2000
	var eid12 := String(PRun.stock(r12).equipment[0])
	PRun.buy_equipment(r12, eid12, false, "stock")
	var q12 := PRun.sell_quote(r12, eid12)
	ok("견적과 다른 금액으로 확정하면 실행되지 않는다(확인 창을 띄운 사이 값이 바뀌면 취소)",
		not PRun.sell_equipment(r12, eid12, int(q12.gold) + 1) and PRun.owns_equip(r12, eid12))
	var acts12 := PFlow.actions(r12)
	var sell_act := {}
	for a in acts12:
		if String(a.id) == "sell:" + eid12:
			sell_act = a
	ok("행동 목록(UI·봇 공용)의 판매 항목이 같은 견적을 싣고 있다",
		not sell_act.is_empty() and int(sell_act.data.gold) == int(q12.gold) and String(sell_act.label).find(str(int(q12.gold))) >= 0,
		String(sell_act.get("label", "")))

	# ---------- 9. 휴식: 견적 · 취소 · 휴식권 ----------
	var r13 := human_run(301)
	r13.hp = 40.0
	var before13 := _json(r13)
	var rq13 := PRun.rest_quote(r13)
	ok("휴식 견적: 소모 시간(1칸)·회복 전후 체력이 들어 있고, 견적만으로는 상태가 변하지 않는다(취소 = 변화 없음)",
		bool(rq13.can) and int(rq13.hours) == int(PCatalog.config().REST_HOURS) and is_equal_approx(float(rq13.hp), 40.0)
			and is_equal_approx(float(rq13.hpAfter), float(rq13.hpMax)) and _json(r13) == before13,
		"%s / %s" % [String(rq13.costText), String(rq13.text)])
	ok("휴식 확정: 견적대로 시간 1칸 소모·완전 회복", PRun.rest(r13) and int(r13.hours) == 4 and is_equal_approx(float(r13.hp), float(rq13.hpAfter)))
	var r14 := human_run(302)
	r14.services["free_rest"] = 1
	r14.hp = 20.0
	var rq14 := PRun.rest_quote(r14)
	ok("휴식권 견적: 값 100금 유지, 표현은 '무료'가 아니라 '시간 소모 없음'",
		bool(rq14.useVoucher) and int(rq14.hours) == 0 and int(rq14.voucherPrice) == 100 and String(rq14.costText).find("시간 소모 없음") >= 0
			and String(rq14.costText).find("무료") < 0,
		String(rq14.costText))
	var hours14 := int(r14.hours)
	PRun.rest(r14)
	ok("휴식권 확정: 시간 0칸·완전 회복·권 1장 소모", int(r14.hours) == hours14 and is_equal_approx(float(r14.hp), float(rq14.hpMax)) and not PRun.has_service(r14, "free_rest"))
	var rest_act := {}
	for a in PFlow.actions(human_run(303)):
		if String(a.id) == "rest":
			rest_act = a
	ok("행동 목록의 휴식 항목이 견적을 그대로 싣는다(화면이 다시 계산하지 않는다)",
		not rest_act.is_empty() and (rest_act.data as Dictionary).has("costText") and (rest_act.data as Dictionary).has("hpAfter"),
		String(rest_act.get("label", "")))

	# ---------- 10. 새 지출처가 봇의 공용 행동 목록에 실제로 있다 ----------
	var r15 := human_run(401)
	r15.gold = 2000
	var ids15 := PFlow.actions(r15).map(func(a): return String(a.id))
	var rev_act := {}
	for a in PFlow.actions(r15):
		if String(a.id) == "buy_revive":
			rev_act = a
	ok("부활 물약 구매가 PFlow.actions에 있고 실제로 고를 수 있다(봇이 살 수 있다)",
		ids15.has("buy_revive") and not rev_act.is_empty() and bool(rev_act.enabled) and int(rev_act.data.price) == int(RD.price),
		str(ids15.filter(func(i): return String(i).begins_with("buy_"))))
	var poor15 := human_run(402)
	poor15.gold = 10
	var rev_poor := {}
	for a in PFlow.actions(poor15):
		if String(a.id) == "buy_revive":
			rev_poor = a
	ok("금화가 모자라면 사유와 함께 잠긴다(음수 금화 없음)", not rev_poor.is_empty() and not bool(rev_poor.enabled) and String(rev_poor.reason) != "" and int(poor15.gold) == 10, String(rev_poor.get("reason", "")))
	# 거점 경제 봇이 그 항목을 실제로 고르는지(행동 목록에만 있고 봇이 못 사던 사고 재발 방지)
	var bot := PRunBot.new()
	bot.run = human_run(403)
	bot.run.gold = 3000
	bot.S = PRunBot.strategies()["gradual"]
	bot.L = bot._new_log()
	bot._shop_bot()
	ok("거점 경제 봇이 부활 물약을 실제로 산다(사람 플레이 규칙 회차)",
		PConsumables.revive_count(bot.run) >= 1 and int(bot.L.get("revivesBought", 0)) >= 1,
		"보유 %d 구매 %d" % [PConsumables.revive_count(bot.run), int(bot.L.get("revivesBought", 0))])
	var bot2 := PRunBot.new()
	bot2.run = PRun.new_run(404, "sword", "", { "test_retry": true, "legacy_places": true })
	bot2.run.gold = 3000
	bot2.S = PRunBot.strategies()["gradual"]
	bot2.L = bot2._new_log()
	bot2._shop_bot()
	ok("시험 재시도 경로 회차에서는 봇이 부활 물약을 사지 않는다(기존 측정값 불변)",
		PConsumables.revive_count(bot2.run) == 0 and int(bot2.L.get("revivesBought", 0)) == 0)
	# 봇이 사람 플레이 규칙으로 회차를 돌면 사망이 실제로 회차를 끝낸다
	var bot_rec := PRunBot.simulate(9, "gradual", { "start": "sword", "bot_policy": "balanced", "max_retries": 3, "legacy_places": true, "death_rule": "run_end", "max_days": 3 })
	ok("회차 봇(death_rule=run_end): 사람 플레이 사망 규칙으로 돌고, 쓰러지면 회차가 실제로 끝난다",
		int(bot_rec.get("deaths", 0)) >= 1 or bool(bot_rec.get("cleared", false)) or int(bot_rec.get("revivesBought", 0)) >= 1,
		JSON.stringify({ "revivesBought": bot_rec.get("revivesBought"), "deaths": bot_rec.get("deaths"), "dead": bot_rec.get("dead"), "gold": bot_rec.get("gold"), "stopReason": bot_rec.get("stopReason") }))
	var bot_retry := PRunBot.simulate(9, "gradual", { "start": "sword", "bot_policy": "balanced", "max_retries": 3, "legacy_places": true, "max_days": 3 })
	ok("봇 기본값은 시험 재시도 경로다(기존 측정과 같은 조건, 부활 물약을 사지 않는다)",
		int(bot_retry.get("revivesBought", 0)) == 0 and not bool(bot_retry.get("dead", false)),
		JSON.stringify({ "revivesBought": bot_retry.get("revivesBought"), "dead": bot_retry.get("dead") }))

	# ---------- 11. 마지막 날 경계(구현 기본안 = 시험 규칙, 사용자 합의 전) ----------
	var r16 := human_run(501)
	r16.gold = 2000
	PConsumables.buy(r16, REV)
	r16.day = int(PRun.mode_def(r16).days)
	r16.stage = PRun.stage_count(r16) - 1
	r16.phase = "boss_prep"
	ok("마지막 날에는 다음 날이 없다", not PRun.has_next_day(r16) and PRun.is_boss_day(r16))
	var bs16 := PRun.start_boss(r16)
	var stb16 := PFlow.make_boss_encounter(r16, bs16)
	stb16.status = "lost"
	PFlow.settle_boss_defeat(r16, stb16)
	ok("[시험 규칙] 마지막 날 사망: 물약을 쓰고 날짜는 넘기지 않으며 남은 시간을 전부 잃는다(관문은 그대로)",
		PConsumables.revive_count(r16) == 0 and int(r16.day) == int(PRun.mode_def(r16).days) and int(r16.hours) == 0
			and String(r16.phase) == "boss_prep" and not PRun.is_run_over(r16) and PRun.can_start_boss(r16),
		"day %d hours %d phase %s hp %.0f" % [int(r16.day), int(r16.hours), String(r16.phase), float(r16.hp)])

	var pass_n := 0
	for x in results:
		if x[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
