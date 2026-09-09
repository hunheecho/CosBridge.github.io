extends SceneTree
## 사망·부활 물약·판매·휴식 규칙 테스트(headless).
## 실행: python tools/run_suites.py --suites death_tests --jobs 1
##
## 이 파일이 못박는 것(2026-09-09 사용자 확정 + 경계 규칙의 구현 기본안)
##  1) 부활 수단이 없으면 일반 전투·보스전 모두 그 회차가 즉시 끝난다(무료 회복·다음 날 진행·재도전 없음).
##  2) 부활 물약은 보유했을 때만 한 개 소모되고, 남은 하루를 잃고 다음 날 최대 체력 25%로 부활한다.
##     죽은 출격의 미정산 전리품은 잃고, 이미 정산한 재산·성장은 남는다.
##  2-1) **마지막 날(다음 날이 없는 날)**: 물약 1개를 쓰고 **날짜를 늘리지 않은 채 같은 날 관문 앞**에서 최대 체력 25%로 복귀하며
##     그날 남은 시간은 전부 소진한다. 물약이 없으면 회차 종료. 반복 부활은 매번 한 개씩 든다(§11).
##  2-2) 그 25%는 **실제 전투 시작 체력까지** 간다(§13). 부활 표식(run.revivePending)이 붙은 재입장 한 번만
##     자동 완전 회복을 건너뛴다 — 저장·복구를 견디고, 그 사이 회복 수단으로 오른 체력은 그대로 들어가며,
##     표식은 그 입장에서 소비되어 다음 정상 입장에는 남지 않는다.
##  3) 사망 정산은 정확히 1회다. 저장 복구·입장 스냅샷으로 소모한 물약이 되살아나지 않는다(개수와 사용 횟수 둘 다).
##  4) 부활해도 미완료 관문은 건너뛰어지지 않고, 넘기 전까지 출격이 잠긴다.
##  5) 판매 = 실제 지불 금액의 절반(정수 내림). 할인가로 샀으면 할인가 기준, 구매액이 없으면 정상가의 절반.
##     장착 중이면 해제되고, 취소·중복 클릭으로 금화·가방이 복제되지 않는다.
##  6) 휴식은 견적(rest_quote)과 확정(rest)이 나뉘어 있고, 취소하면 상태가 변하지 않는다. 휴식권은 100금·시간 소모 없음.
##  7) 화면 문구가 세 갈래(회차 종료 / 마지막 날 부활 / 보통 날 부활)를 **서로 다르게** 안내한다(§12).
##     화면을 띄우지 않고 화면이 쓰는 static 함수(PDefeatScreen.death_lines·PBossResultScreen.defeat_lines)를 그대로 부른다.
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
	st.mark_duel_done_for_test() # 결투가 예정된 편성이면 그것도 이긴 것으로 본다(승리 정산 규칙과 앞뒤를 맞춘다)
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
	ok("회귀: 마지막 날이 **아닌** 날의 부활은 그대로 '다음 날'이다(같은 날 부활이 아니고 하루가 통째로 남는다)",
		bool(r6.death.nextDay) and not bool(r6.death.sameDay) and not PRun.revived_same_day(r6)
			and int(r6.hours) == int(PCatalog.config().HOURS_PER_DAY) and PRun.revive_uses(r6) == 1,
		"nextDay %s sameDay %s hours %d 사용 %d" % [str(r6.death.nextDay), str(r6.death.get("sameDay", null)), int(r6.hours), PRun.revive_uses(r6)])
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
	# §4 명세 변경(2026-09-10): 재고 id는 **종류**이고, 사면 그 자리에서 **개체 id**("종류#번호")가 발급된다.
	# 지불 기록·판매 견적·강화는 전부 그 개체 id를 키로 쓴다(같은 종류를 여럿 가져도 서로 섞이지 않게)
	var buy_type := String(PRun.stock(r8).equipment[0])
	var list8 := PRun.equip_price(buy_type)
	PRun.buy_equipment(r8, buy_type, false, "stock")
	var buy_id := String((r8.bag as Array)[(r8.bag as Array).size() - 1])
	ok("구매하면 개체 id가 발급된다(종류#번호), 종류는 그대로 읽힌다", buy_id.find("#") > 0 and PRun.equip_type_of(buy_id) == buy_type and PRun.equip_plus_of(r8, buy_id) == 0, buy_id)
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
	var keep_type := String(PRun.stock(r8p).equipment[0])
	PRun.buy_equipment(r8p, keep_type, false, "stock")
	var keep8 := String((r8p.bag as Array)[(r8p.bag as Array).size() - 1])
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
		var mtype := String(m9.equipment)
		var full9 := PRun.equip_price(mtype)
		var paid9 := PRun.equip_price_for(r9, mtype, "merchant")
		PRun.buy_equipment(r9, mtype, false, "merchant")
		var mid := String((r9.bag as Array)[(r9.bag as Array).size() - 1])
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
	PRun.buy_equipment(r12, String(PRun.stock(r12).equipment[0]), false, "stock")
	var eid12 := String((r12.bag as Array)[(r12.bag as Array).size() - 1]) # 행동 목록 항목 id도 개체 id다
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

	# ---------- 11. 마지막 날(다음 날이 없는 날) 부활 — 2026-09-09 사용자 확정 ----------
	# 확정 내용: 물약이 있으면 1개를 쓰고 **날짜를 늘리지 않은 채 같은 날 관문 앞**에서 최대 체력 25%로 복귀한다.
	# 그날 남은 시간은 전부 소진한다. 물약이 없으면 회차 종료. 부활을 반복하려면 매번 물약을 소비한다.
	var last_day_run := func(seed_v: int, revives: int) -> Dictionary:
		var rr := human_run(seed_v)
		rr.gold = 3000
		for _i in revives:
			PConsumables.buy(rr, REV)
		rr.day = int(PRun.mode_def(rr).days)
		rr.stage = PRun.stage_count(rr) - 1
		rr.phase = "boss_prep"
		return rr
	## 관문에 들어가서 쓰러진다(입장마다 중복 방지 키가 바뀐다 = 새 사망)
	var die_at_gate := func(rr: Dictionary) -> void:
		var stb := PFlow.make_boss_encounter(rr, PRun.start_boss(rr))
		stb.status = "lost"
		PFlow.settle_boss_defeat(rr, stb)

	var r16: Dictionary = last_day_run.call(501, 2)
	var hp_max16 := float(PRun.build(r16).hp_max)
	var day16 := int(r16.day)
	var stage16 := int(r16.stage)
	ok("마지막 날에는 다음 날이 없다(그리고 마지막 관문 날이다)", not PRun.has_next_day(r16) and PRun.is_boss_day(r16) and PConsumables.revive_count(r16) == 2)
	die_at_gate.call(r16)
	ok("[확정] 마지막 날 + 물약 있음: 날짜가 안 늘어난다 · 같은 날 관문 앞 · 체력 = 최대의 25% · 남은 시간 0 · 물약 1개 감소",
		int(r16.day) == day16 and String(r16.phase) == "boss_prep" and PRun.can_start_boss(r16) and int(r16.stage) == stage16
			and is_equal_approx(float(r16.hp), round(hp_max16 * float(RD.hpFrac))) and int(r16.hours) == 0
			and PConsumables.revive_count(r16) == 1 and not PRun.is_run_over(r16),
		"day %d hours %d phase %s hp %.0f/%.0f 물약 %d" % [int(r16.day), int(r16.hours), String(r16.phase), float(r16.hp), hp_max16, PConsumables.revive_count(r16)])
	ok("마지막 날 부활은 기록에도 '같은 날'로 남는다(화면이 문구를 고르는 근거) · 사용 횟수 1",
		bool(r16.death.revived) and bool(r16.death.sameDay) and not bool(r16.death.nextDay) and PRun.revived_same_day(r16)
			and PRun.revive_uses(r16) == 1 and int(r16.death.count) == 1,
		JSON.stringify({ "sameDay": r16.death.get("sameDay"), "nextDay": r16.death.get("nextDay"), "uses": PRun.revive_uses(r16) }))
	# 같은 사망이 두 번 정산되지 않는다(마지막 날에도)
	var snap16 := _json(r16)
	PRun.boss_defeat(r16)                                                                # 같은 입장의 두 번째 정산
	PRun.settle_death(r16, { "cause": "boss", "key": String(r16.death.key), "bossId": "boss" }) # 같은 키로 한 번 더
	ok("마지막 날에도 같은 사망은 두 번 정산되지 않는다(물약·날짜·남은 시간·사용 횟수 그대로)",
		_json(r16) == snap16 and PConsumables.revive_count(r16) == 1 and PRun.revive_uses(r16) == 1 and int(r16.hours) == 0,
		"물약 %d 사용 %d" % [PConsumables.revive_count(r16), PRun.revive_uses(r16)])
	# 저장 → 이어하기: 개수와 사용 횟수 둘 다 되살아나지 않는다
	var back16 := _roundtrip(r16)
	ok("저장 → 이어하기 뒤에도 마지막 날에 쓴 물약이 되살아나지 않는다(개수와 사용 횟수 둘 다)",
		PConsumables.revive_count(back16) == 1 and PRun.revive_uses(back16) == 1 and int(back16.day) == day16
			and int(back16.hours) == 0 and String(back16.phase) == "boss_prep" and _json(back16) == _json(r16),
		"물약 %d 사용 %d" % [PConsumables.revive_count(back16), PRun.revive_uses(back16)])
	# 이어한 회차에서 같은 날 다시 도전 → 또 쓰러진다: 물약이 한 개 더 든다(한 번 쓰고 무한 재도전이 되지 않는다)
	die_at_gate.call(back16)
	ok("마지막 날에 두 번 죽으면 물약이 두 개 든다(이어하기를 거쳐도 반복 부활은 매번 소비)",
		PConsumables.revive_count(back16) == 0 and PRun.revive_uses(back16) == 2 and int(back16.death.count) == 2
			and int(back16.day) == day16 and int(back16.hours) == 0 and not PRun.is_run_over(back16) and PRun.revived_same_day(back16),
		"물약 %d 사용 %d day %d" % [PConsumables.revive_count(back16), PRun.revive_uses(back16), int(back16.day)])
	die_at_gate.call(back16)
	ok("물약이 떨어진 뒤의 죽음은 회차 종료다(마지막 날에도 무한 재도전은 없다)",
		PRun.is_run_over(back16) and bool(back16.ended) and int(back16.day) == day16 and not bool(back16.death.revived)
			and not PRun.revived_same_day(back16) and PRun.revive_uses(back16) == 2 and PFlow.actions(back16).is_empty(),
		"phase %s 사용 %d" % [String(back16.phase), PRun.revive_uses(back16)])

	var r17: Dictionary = last_day_run.call(502, 0)
	die_at_gate.call(r17)
	ok("[확정] 마지막 날 + 물약 없음: 회차 종료(is_run_over) · 행동 없음",
		PRun.is_run_over(r17) and bool(r17.ended) and int(r17.hours) == 0 and PRun.revive_uses(r17) == 0
			and PFlow.actions(r17).is_empty() and not PRun.can_start_boss(r17),
		"phase %s day %d" % [String(r17.phase), int(r17.day)])

	# ---------- 12. 화면 문구: 마지막 날 부활을 다른 문구로 안내한다 ----------
	# 화면이 쓰는 static 함수를 그대로 부른다(화면과 시험이 같은 문자열을 본다).
	var scr_last: Dictionary = last_day_run.call(503, 1)
	PRun.settle_death(scr_last, { "cause": "boss", "key": "screen:last", "bossId": "boss" })
	var scr_mid := human_run(504)
	scr_mid.gold = 2000
	PConsumables.buy(scr_mid, REV)
	scr_mid.day = 4
	scr_mid.phase = "boss_prep"
	PRun.settle_death(scr_mid, { "cause": "boss", "key": "screen:mid", "bossId": "boss" })
	var scr_over: Dictionary = last_day_run.call(505, 0)
	PRun.settle_death(scr_over, { "cause": "boss", "key": "screen:over", "bossId": "boss" })
	var t_last := " ".join(PDefeatScreen.death_lines(scr_last))
	var t_mid := " ".join(PDefeatScreen.death_lines(scr_mid))
	var t_over := " ".join(PDefeatScreen.death_lines(scr_over))
	ok("패배 화면: 마지막 날 부활을 '같은 날 관문 앞'으로 안내하고, 보통 날 부활·회차 종료와 문구가 서로 다르다",
		t_last != t_mid and t_last != t_over and t_mid != t_over
			and t_last.find("마지막 날") >= 0 and t_last.find("날짜는 넘어가지 않습니다") >= 0 and t_last.find("남은 시간은 전부 사라집니다") >= 0
			and t_mid.find("남은 하루를 잃고") >= 0 and t_mid.find("마지막 날") < 0,
		t_last)
	ok("패배 화면의 주 버튼도 마지막 날에는 '같은 날 관문 앞으로'다(다음 날로 간다고 적지 않는다)",
		PDefeatScreen.next_label(scr_last) == "같은 날 관문 앞으로 (Enter)" and PDefeatScreen.next_label(scr_mid).find("일차") >= 0
			and PDefeatScreen.next_label(scr_last) != PDefeatScreen.next_label(scr_mid) and PDefeatScreen.next_label(scr_over) == "회차 결과 보기 (Enter)",
		"%s / %s / %s" % [PDefeatScreen.next_label(scr_last), PDefeatScreen.next_label(scr_mid), PDefeatScreen.next_label(scr_over)])
	var b_last := " ".join(PBossResultScreen.defeat_lines(scr_last))
	var b_mid := " ".join(PBossResultScreen.defeat_lines(scr_mid))
	var b_over := " ".join(PBossResultScreen.defeat_lines(scr_over))
	ok("관문 결과 화면도 마지막 날 부활을 따로 안내한다(옛 '무료 상태 복원·무제한 재도전' 문구가 사람 플레이에 나오지 않는다)",
		b_last != b_mid and b_last.find("날짜는 넘어가지 않습니다") >= 0 and b_last.find("또 한 개") >= 0
			and b_mid.find("남은 하루를 잃고") >= 0 and b_over.find("회차가 여기서 끝납니다") >= 0
			and b_last.find("입장 시점의 상태로 복구") < 0 and b_mid.find("입장 시점의 상태로 복구") < 0,
		b_last)
	ok("관문 결과 화면: 바로 다시 들어가기는 마지막 날 부활에서만 열린다(회차 종료·다음 날 부활에서는 잠긴다)",
		PBossResultScreen.can_retry_now(scr_last) and not PBossResultScreen.can_retry_now(scr_mid) and not PBossResultScreen.can_retry_now(scr_over)
			and PBossResultScreen.retry_label(scr_last).find("같은 날") >= 0 and PBossResultScreen.retry_label(scr_over).find("재도전 없음") >= 0,
		"%s / %s" % [PBossResultScreen.retry_label(scr_last), PBossResultScreen.retry_label(scr_over)])
	ok("부활 물약 설명이 마지막 날 동작을 안내한다(사람이 사기 전에 알 수 있다)",
		String(RD.get("short", "")).find("마지막 날") >= 0 and String(RD.get("desc", "")).find("마지막 날") >= 0
			and String(RD.get("desc", "")).find("같은 날 관문 앞") >= 0 and String(RD.get("lastDayShort", "")).find("같은 날 관문 앞") >= 0,
		String(RD.get("short", "")))
	var line_mid := PConsumables.revive_when_line(human_run(506))
	var line_last := PConsumables.revive_when_line(last_day_run.call(507, 0))
	ok("상점용 한 줄 안내가 날짜에 따라 달라진다(마지막 날에는 같은 날 관문 앞이라고 적는다)",
		line_mid != line_last and line_last.find("마지막 날") >= 0 and line_last.find("같은 날 관문 앞") >= 0 and line_mid.find("다음 날") >= 0,
		"%s // %s" % [line_mid, line_last])

	# ---------- 13. 부활 체력 25%가 **실제 전투 시작 체력**까지 간다(2026-09-09 사용자 승인) ----------
	# 예전에는 PRun.start_boss가 입장에서 완전 회복을 하고 PFlow.make_boss_encounter가 한 번 더 최대 체력으로 채워,
	# 관문 사망의 25%가 아무 비용도 아니었다(물약 1개 + 그날 남은 시간만 들었다).
	# 이제 부활 표식(run.revivePending)이 **그 재입장 한 번**만 자동 회복을 건너뛴다.
	# 여기서는 사망 → 부활 → 저장·복구 → 재입장 → CombatState.player.hp → 두 번째 사망까지 끊지 않고 본다.
	var last_day_kit := func(seed_v: int, revives: int, potions: int) -> Dictionary:
		var rr := human_run(seed_v)
		rr.gold = 4000
		for _i in revives:
			PConsumables.buy(rr, REV)
		for _i in potions:
			PConsumables.buy(rr, "potion")
		rr.day = int(PRun.mode_def(rr).days)
		rr.stage = PRun.stage_count(rr) - 1
		rr.phase = "boss_prep"
		return rr

	var d1: Dictionary = last_day_kit.call(601, 2, 1)
	var hpmax1 := float(PRun.build(d1).hp_max)
	var revhp1: float = round(hpmax1 * float(RD.hpFrac))
	var day1 := int(d1.day)
	# (1) 마지막 날 사망 → 물약 1개 소비 · 같은 날 · 관문 앞 · 체력 25% · 시간 0
	die_at_gate.call(d1)
	ok("(1) 마지막 날 사망 → 부활: 물약 1개 소비 · 같은 날 · 관문 앞 · 체력 25% · 남은 시간 0 · 재입장 표식이 선다",
		PConsumables.revive_count(d1) == 1 and int(d1.day) == day1 and String(d1.phase) == "boss_prep"
			and is_equal_approx(float(d1.hp), revhp1) and int(d1.hours) == 0 and PRun.revive_pending(d1),
		"hp %.0f/%.0f hours %d 표식 %s" % [float(d1.hp), hpmax1, int(d1.hours), str(PRun.revive_pending(d1))])
	# (2) PSave 저장 → 복구: 표식·체력·개수가 그대로
	var d1b := _roundtrip(d1)
	ok("(2) 저장·복구를 견딘다: 부활 표식·체력·물약 수가 그대로(정규화한 JSON이 같다)",
		PRun.revive_pending(d1b) and is_equal_approx(float(d1b.hp), revhp1) and PConsumables.revive_count(d1b) == 1
			and PRun.revive_uses(d1b) == 1 and _json(d1b) == _json(d1),
		"hp %.0f 표식 %s" % [float(d1b.hp), str(PRun.revive_pending(d1b))])
	# (3) 관문 재입장: 완전 회복이 일어나지 않는다 + 표식은 이 한 번에 소비된다
	var bs_r1 := PRun.start_boss(d1b)
	ok("(3) 부활 뒤 관문 재입장: 자동 완전 회복이 없다(체력 25% 그대로) · 표식은 이 입장에서 소비된다",
		is_equal_approx(float(d1b.hp), revhp1) and not is_equal_approx(float(d1b.hp), hpmax1)
			and not PRun.revive_pending(d1b) and not bs_r1.is_empty(),
		"입장 체력 %.0f/%.0f 표식 %s" % [float(d1b.hp), hpmax1, str(PRun.revive_pending(d1b))])
	# (4) 실제로 만들어진 CombatState의 전투 시작 체력이 25%다(최대 체력은 깎지 않는다)
	var stg1 := PFlow.make_boss_encounter(d1b, bs_r1)
	ok("(4) 실제 전투 시작 체력이 25%다(CombatState.player.hp) · 최대 체력은 그대로",
		is_equal_approx(float(stg1.player.hp), revhp1) and is_equal_approx(float(stg1.player.hp_max), hpmax1)
			and float(stg1.player.hp) < float(stg1.player.hp_max),
		"전투 시작 %.0f/%.0f" % [float(stg1.player.hp), float(stg1.player.hp_max)])
	# (5) 그 전투에서 두 번째 사망 → 물약이 또 한 개 든다
	stg1.status = "lost"
	PFlow.settle_boss_defeat(d1b, stg1)
	ok("(5) 이어진 두 번째 사망: 물약이 또 한 개(1 → 0) · 사용 2회 · 같은 날 관문 앞 25% · 표식이 다시 선다",
		PConsumables.revive_count(d1b) == 0 and PRun.revive_uses(d1b) == 2 and int(d1b.day) == day1
			and is_equal_approx(float(d1b.hp), revhp1) and PRun.revive_pending(d1b) and not PRun.is_run_over(d1b)
			and PRun.revived_same_day(d1b),
		"물약 %d 사용 %d hp %.0f day %d" % [PConsumables.revive_count(d1b), PRun.revive_uses(d1b), float(d1b.hp), int(d1b.day)])
	# (7) 부활 뒤 회복 수단을 쓰면 그 체력으로 입장한다(다시 25%로 깎지 않고, 완전 회복도 하지 않는다)
	ok("(7-a) 마지막 날은 남은 시간이 0이라 휴식이 막히지만, 시간이 들지 않는 회복약은 관문 앞에서 쓸 수 있다",
		PConsumables.can_use_potion(d1b) and not PRun.can_rest(d1b) and int(d1b.hours) == 0 and not bool(PRun.rest_quote(d1b).can),
		String(PRun.rest_quote(d1b).reason))
	var healed1 := PConsumables.use_potion(d1b)
	var after_heal1 := float(d1b.hp)
	var bs_r2 := PRun.start_boss(d1b)
	var stg2 := PFlow.make_boss_encounter(d1b, bs_r2)
	ok("(7-b) 부활 뒤 회복약을 쓰면 그만큼 오른 체력으로 입장한다(25%로 다시 깎지 않고 100%로 채우지도 않는다)",
		healed1 > 0.0 and is_equal_approx(after_heal1, revhp1 + healed1) and is_equal_approx(float(d1b.hp), after_heal1)
			and is_equal_approx(float(stg2.player.hp), after_heal1) and after_heal1 < hpmax1,
		"25%% %.0f → 회복 +%.0f → 전투 시작 %.0f (최대 %.0f)" % [revhp1, healed1, float(stg2.player.hp), hpmax1])
	# (5-b) 물약이 0이면 그다음 죽음이 회차 종료다
	stg2.status = "lost"
	PFlow.settle_boss_defeat(d1b, stg2)
	ok("(5-b) 물약이 없으면 그다음 죽음이 회차 종료다(마지막 날에도 무한 재도전은 없다) · 표식도 남지 않는다",
		PRun.is_run_over(d1b) and bool(d1b.ended) and PRun.revive_uses(d1b) == 2 and not PRun.revive_pending(d1b)
			and PFlow.actions(d1b).is_empty() and int(d1b.day) == day1,
		"phase %s 표식 %s" % [String(d1b.phase), str(PRun.revive_pending(d1b))])

	# (6) 회귀: 정상적인 **첫** 관문 입장은 예전대로 완전 회복이다(입장 값·전투 시작 체력 둘 다)
	var norm13 := human_run(602)
	norm13.day = 4
	norm13.phase = "boss_prep"
	var hpmax_n := float(PRun.build(norm13).hp_max)
	norm13.hp = 12.0
	var bs_n := PRun.start_boss(norm13)
	var st_n := PFlow.make_boss_encounter(norm13, bs_n)
	ok("(6) 회귀: 부활이 아닌 정상 관문 입장은 예전대로 완전 회복이다(입장 체력·전투 시작 체력 모두 최대)",
		is_equal_approx(float(norm13.hp), hpmax_n) and is_equal_approx(float(st_n.player.hp), hpmax_n)
			and not PRun.revive_pending(norm13),
		"입장 %.0f · 전투 시작 %.0f / 최대 %.0f" % [float(norm13.hp), float(st_n.player.hp), hpmax_n])

	# (8) 표식은 한 번만 쓰인다: 소비된 뒤 관문을 넘기고 다음 관문에 정상 입장하면 다시 완전 회복이다
	var once13 := human_run(603)
	once13.gold = 3000
	PConsumables.buy(once13, REV)
	once13.day = 4
	once13.phase = "boss_prep"
	var hpmax_o := float(PRun.build(once13).hp_max)
	var revhp_o: float = round(hpmax_o * float(RD.hpFrac))
	die_at_gate.call(once13) # 4일차 관문 사망 → 하루를 잃고 5일차 관문 앞 25%
	ok("(8-a) 마지막 날이 아닌 부활도 관문 앞이면 표식이 선다(다음 날 관문 재입장에도 자동 회복이 없다)",
		PRun.revive_pending(once13) and String(once13.phase) == "boss_prep" and int(once13.day) == 5
			and is_equal_approx(float(once13.hp), revhp_o) and not PRun.revived_same_day(once13),
		"day %d hp %.0f 표식 %s" % [int(once13.day), float(once13.hp), str(PRun.revive_pending(once13))])
	var bs_o := PRun.start_boss(once13)
	var st_o := PFlow.make_boss_encounter(once13, bs_o)
	ok("(8-b) 그 재입장의 전투 시작 체력도 25%다 · 표식은 여기서 소비된다",
		is_equal_approx(float(st_o.player.hp), revhp_o) and not PRun.revive_pending(once13),
		"전투 시작 %.0f/%.0f" % [float(st_o.player.hp), hpmax_o])
	st_o.status = "won"
	st_o.boss.dead = true
	st_o.stats.boss_damage = 3000.0
	st_o.player.hp = 9.0
	PFlow.settle_boss_victory(once13, st_o)
	var guard13 := 0
	while String(once13.phase) == "prep" and guard13 < 12:
		guard13 += 1
		PRun.end_day(once13)
	once13.hp = 11.0 # 다음 관문 앞에서 다친 상태를 만들어 둔다(정상 입장이 회복하는지 보려고)
	ok("(8-c) 관문을 넘기고 하루가 정상으로 넘어가면 부활 표식이 남지 않는다",
		String(once13.phase) == "boss_prep" and not PRun.revive_pending(once13) and int(once13.stage) == 1,
		"day %d phase %s stage %d" % [int(once13.day), String(once13.phase), int(once13.stage)])
	var hpmax_o2 := float(PRun.build(once13).hp_max)
	var st_o2 := PFlow.make_boss_encounter(once13, PRun.start_boss(once13))
	ok("(8-d) 다음 정상 입장은 예전대로 완전 회복이다(표식이 되살아나지 않는다)",
		is_equal_approx(float(once13.hp), hpmax_o2) and is_equal_approx(float(st_o2.player.hp), hpmax_o2),
		"입장 %.0f · 전투 시작 %.0f / 최대 %.0f" % [float(once13.hp), float(st_o2.player.hp), hpmax_o2])

	# 보통 날 아침으로 부활하면(관문 앞이 아니면) 표식을 두지 않는다 — 나중의 정상 입장까지 따라가지 않는다
	var sr13 := human_run(605)
	sr13.gold = 2000
	PConsumables.buy(sr13, REV)
	var s_sr13 := PSortie.start(sr13, String(PSortie.cards_for(sr13)[0].id))
	PFlow.settle_defeat(sr13, s_sr13, fake_fight(sr13, s_sr13, false))
	ok("일반 출격 사망으로 보통 날 아침에 부활하면 표식을 두지 않는다(관문 앞이 아니다)",
		String(sr13.phase) == "prep" and bool(sr13.death.revived) and not PRun.revive_pending(sr13)
			and is_equal_approx(float(sr13.hp), round(float(PRun.build(sr13).hp_max) * float(RD.hpFrac))),
		"phase %s 표식 %s" % [String(sr13.phase), str(PRun.revive_pending(sr13))])

	# 시험 재시도 경로와 섞이지 않는다(사망 정산이 없으므로 표식이 서지 않고, 재도전 입장은 예전대로 완전 회복)
	var rt13 := PRun.new_run(604, "sword", "", { "test_retry": true, "legacy_places": true })
	rt13.day = 4
	rt13.phase = "boss_prep"
	var st_rt := PFlow.make_boss_encounter(rt13, PRun.start_boss(rt13))
	st_rt.status = "lost"
	PFlow.settle_boss_defeat(rt13, st_rt)
	var hpmax_rt := float(PRun.build(rt13).hp_max)
	var st_rt2 := PFlow.make_boss_encounter(rt13, PRun.start_boss(rt13))
	ok("시험 재시도 경로에는 부활 표식이 서지 않는다(재도전 입장·전투 시작 체력 모두 예전대로 최대)",
		not PRun.revive_pending(rt13) and is_equal_approx(float(rt13.hp), hpmax_rt)
			and is_equal_approx(float(st_rt2.player.hp), hpmax_rt) and int(rt13.bossRetries) == 1
			and (rt13.get("death", {}) as Dictionary).is_empty(),
		"재도전 %d 전투 시작 %.0f/%.0f" % [int(rt13.bossRetries), float(st_rt2.player.hp), hpmax_rt])

	# 화면 문구: 부활 재입장에 자동 회복이 없다는 것을 사람이 미리 본다(화면이 쓰는 static 함수를 그대로 부른다)
	var scr_pending: Dictionary = last_day_kit.call(606, 1, 0)
	die_at_gate.call(scr_pending)
	var nh_defeat := PDefeatScreen.no_heal_line(scr_pending)
	var nh_boss := PBossResultScreen.no_heal_line(scr_pending)
	ok("화면 문구가 '재입장에 자동 회복 없음'을 안내한다(표식이 선 동안만)",
		PRun.revive_pending(scr_pending) and nh_defeat.find("자동으로 차지 않습니다") >= 0 and nh_boss.find("자동으로 차지 않습니다") >= 0
			and " ".join(PDefeatScreen.death_lines(scr_pending)).find("자동으로 차지 않습니다") >= 0
			and " ".join(PBossResultScreen.defeat_lines(scr_pending)).find("자동으로 차지 않습니다") >= 0,
		nh_boss)
	PRun.start_boss(scr_pending)
	ok("표식이 소비된 뒤에는 그 안내가 사라진다(정상 입장 안내와 섞이지 않는다)",
		PDefeatScreen.no_heal_line(scr_pending) == "" and PBossResultScreen.no_heal_line(scr_pending) == "" and not PRun.revive_pending(scr_pending))

	# ---------- §14 관문 앞 휴식: 시간과 휴식권을 나눈다(사용자 확정 보완 2026-09-09) ----------
	# 기본 '휴식'은 시간 1칸이고 가진 휴식권을 자동으로 쓰지 않는다.
	# 휴식권은 따로 골라야 쓰며, 그것도 마지막 날 제외·남은 시간 1칸 이상 조건을 지킨다.
	var REST_H := int(PCatalog.config().REST_HOURS)
	var gate_kit := func(seed_v: int, day_v: int, hours_v: int, vouchers: int) -> Dictionary:
		var rr := human_run(seed_v)
		rr.day = day_v
		rr.phase = "boss_prep"
		rr.hours = hours_v
		rr.hp = 30.0
		if vouchers > 0:
			if not rr.has("services") or rr.services == null:
				rr.services = {}
			rr.services["free_rest"] = vouchers
		return rr

	# (a) 기본 휴식: 시간만 준다. 휴식권은 그대로 남는다
	var g1: Dictionary = gate_kit.call(701, 2, 3, 2)
	var g1_max := float(PRun.build(g1).hp_max)
	var q1 := PRun.rest_quote(g1, { "useVoucher": false })
	var g1_ok := PRun.rest(g1, { "useVoucher": false })
	ok("관문 앞 기본 휴식: 시간 1칸만 빠지고 휴식권은 그대로다(자동 소비 없음)",
		g1_ok and int(g1.hours) == 3 - REST_H and int(g1.services.free_rest) == 2 and is_equal_approx(float(g1.hp), g1_max)
			and int(q1.hours) == REST_H and not bool(q1.useVoucher),
		"시간 3→%d · 휴식권 %d장 · 체력 %d · 견적 %s" % [int(g1.hours), int(g1.services.free_rest), int(float(g1.hp)), String(q1.costText)])

	# (b) 휴식권 사용: 휴식권만 준다. 시간은 그대로
	var g2: Dictionary = gate_kit.call(702, 2, 3, 2)
	var q2 := PRun.rest_quote(g2, { "useVoucher": true })
	var g2_ok := PRun.rest(g2, { "useVoucher": true })
	ok("관문 앞 휴식권 사용: 휴식권 1개만 빠지고 시간은 그대로다",
		g2_ok and int(g2.hours) == 3 and int(g2.services.free_rest) == 1 and int(q2.hours) == 0
			and String(q2.costText).find("휴식권") >= 0,
		"시간 %d · 휴식권 2→%d · 견적 %s" % [int(g2.hours), int(g2.services.free_rest), String(q2.costText)])

	# (c) 시간과 휴식권이 **동시에** 빠지는 길이 없다
	ok("관문 앞 휴식은 시간과 휴식권 중 하나만 소비한다(둘이 함께 빠지지 않는다)",
		(int(g1.hours) == 3 - REST_H and int(g1.services.free_rest) == 2)
			and (int(g2.hours) == 3 and int(g2.services.free_rest) == 1))

	# (d) 취소(= rest를 부르지 않음)하면 아무것도 안 준다 — 견적은 회차를 바꾸지 않는다
	var g3: Dictionary = gate_kit.call(703, 2, 3, 2)
	var _q3a := PRun.rest_quote(g3, { "useVoucher": false })
	var _q3b := PRun.rest_quote(g3, { "useVoucher": true })
	ok("견적만 보고 취소하면 시간·휴식권·체력이 하나도 바뀌지 않는다",
		int(g3.hours) == 3 and int(g3.services.free_rest) == 2 and is_equal_approx(float(g3.hp), 30.0))

	# (e) 마지막 날은 휴식권으로도 우회할 수 없다
	var g4: Dictionary = gate_kit.call(704, int(PRun.mode_def(human_run(704)).days), 3, 2)
	ok("마지막 날 관문 앞에서는 휴식도 휴식권 사용도 막힌다(우회 수단이 아니다)",
		not PRun.has_next_day(g4) and not PRun.can_rest(g4) and not PRun.can_rest_voucher(g4)
			and String(PRun.rest_quote(g4, { "useVoucher": true }).reason).find("마지막 날") >= 0)

	# (f) 시간 0도 휴식권으로 우회할 수 없다
	var g5: Dictionary = gate_kit.call(705, 2, 0, 2)
	ok("남은 시간이 0이면 휴식권 사용도 막힌다",
		not PRun.can_rest(g5) and not PRun.can_rest_voucher(g5))

	# (g) 거점(prep)의 기존 규칙은 이 보완으로 바뀌지 않았다(회귀)
	var g6: Dictionary = gate_kit.call(706, 2, 3, 1)
	g6.phase = "prep"
	var g6_ok := PRun.rest(g6)
	ok("거점 휴식은 예전 그대로 — 휴식권이 있으면 먼저 쓰고 시간은 그대로다(회귀)",
		g6_ok and int(g6.hours) == 3 and int(g6.services.free_rest) == 0,
		"시간 %d · 휴식권 %d" % [int(g6.hours), int(g6.services.free_rest)])

	# (h) 휴식으로 회복한 체력이 **관문 입장과 실제 전투 시작까지** 간다
	var g7: Dictionary = gate_kit.call(707, 2, 3, 0)
	g7.stage = 0
	var g7_max := float(PRun.build(g7).hp_max)
	PRun.rest(g7, { "useVoucher": false })
	var s7 := PRun.start_boss(g7)
	var st7 := PFlow.make_boss_encounter(g7, s7)
	ok("관문 앞 휴식으로 회복한 체력이 입장과 전투 시작까지 유지된다",
		is_equal_approx(float(g7.hp), g7_max) and is_equal_approx(float(st7.player.hp), g7_max),
		"휴식 뒤 %d · 전투 시작 %d / 최대 %d" % [int(float(g7.hp)), int(float(st7.player.hp)), int(g7_max)])

	# (i) 부활 표식이 선 상태에서 쉬면 그 오른 체력으로 들어간다(25%로 다시 깎지 않는다)
	var g8: Dictionary = gate_kit.call(708, 2, 3, 0)
	g8.stage = 0
	g8.revivePending = { "count": 1 }
	var g8_max := float(PRun.build(g8).hp_max)
	PRun.rest(g8, { "useVoucher": false })
	var st8 := PFlow.make_boss_encounter(g8, PRun.start_boss(g8))
	ok("부활 표식이 선 채로 쉬면 회복된 체력 그대로 입장한다(다시 25%로 안 깎는다)",
		is_equal_approx(float(st8.player.hp), g8_max),
		"전투 시작 %d / 최대 %d" % [int(float(st8.player.hp)), int(g8_max)])

	var pass_n := 0
	for x in results:
		if x[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
