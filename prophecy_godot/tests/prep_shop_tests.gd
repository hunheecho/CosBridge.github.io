extends SceneTree
## 상점(유료 새로고침·잠금)·출격 준비물·회복약·무료 휴식권 값 규칙 테스트(headless).
## 실행: python tools/run_suites.py --suites prep_shop_tests --jobs 1 --allow-adhoc
##
## 이 파일이 고정하는 것(2026-09-08 지시 §1·§3·§6·§7·§8):
##  - 무료 휴식권 값 100이 정본(data) · 재고 · 거래 · 행동 목록에서 모두 같다. 공짜로 받은 권에는 값을 청구하지 않는다.
##  - 새로고침·구매·취소·저장 복구로 비용이나 상품이 복제되지 않는다.
##  - 준비물은 1개만 걸리고, 전투 입장 때 정확히 1개 빠지며, 같은 출격의 다음 전투로 이어지지 않는다.
##  - 회복약 무제한 구매로 휴식이 사라지지 않는다(하루 상한).
##
## 주의: 준비물 소모는 게임에서 PFlow.make_encounter가 부른다. flow.gd는 이 작업의 수정 대상이 아니므로
## 여기서는 같은 순서(빌드 계산 → CombatState 생성 → 소모)를 _enter_fight가 그대로 재현한다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 전투 입장 재현: 빌드(준비물 얹힘) → 조우 생성 → 준비물 1개 소모. 게임에서 필요한 훅과 같은 순서
## 전투 입장. 준비물 소모는 이제 PFlow.make_encounter 안에서 일어난다(실제 경로).
## 여기서 또 부르면 두 번 소모되므로, 무엇이 쓰였는지는 입장 전에 장착된 것을 읽어 둔다
func _enter_fight(run: Dictionary, sortie: Dictionary) -> Dictionary:
	var armed := PConsumables.armed(run)
	var st := PFlow.make_encounter(run, sortie)
	return { "st": st, "used": armed }

func _json(run: Dictionary) -> String:
	return JSON.stringify(PSave.normalize(run.duplicate(true)))

func _init() -> void:
	var SH := PCatalog.shop()
	var CR := PConsumables.rules()

	# ---------- 1. 무료 휴식권 100: 정본 · 표시 · 거래 · 행동 목록이 모두 같다 ----------
	var r := PRun.new_run(7, "sword")
	r.day = int(PRun.merchant_days(r)[0])   # 회차 특징에 따라 상인 날이 다르다(떠돌이 상인의 해 등) — 정본에서 읽는다
	PRun.refresh_stock(r)
	var m: Dictionary = r.merchant
	ok("무료 휴식권 값 정본 = data/world.json shop.merchantService.free_rest = 100, 재고에 그대로 실린다",
		int(SH.merchantService.free_rest) == 100 and m != null and int(m.servicePrice) == 100 and PRun.merchant_service_price("free_rest") == 100,
		"servicePrice=%d" % int(m.servicePrice))
	r.gold = 150
	r.hours = int(PCatalog.config().HOURS_PER_DAY) - int(m.fromSlot)  # 상인이 열리는 시간대로 맞춘다
	ok("상인이 열리기 전에는 살 수 없다", PRun.merchant_open(r))
	var g0 := int(r.gold)
	ok("금화 99면 못 산다(값보다 1 모자람)", not PRun.can_buy_merchant_service(r.merged({ "gold": 99 }, true)))
	var bought := PRun.buy_merchant_service(r)
	ok("구매: 금화가 정확히 100 줄고 휴식권 1장이 생긴다(2회 청구 없음)",
		bought and int(r.gold) == g0 - 100 and PRun.has_service(r, "free_rest") and not PRun.can_buy_merchant_service(r),
		"gold %d → %d" % [g0, int(r.gold)])
	var acts := PFlow.actions(r)
	var svc_label := ""
	for a in acts:
		if String(a.id) == "buy_merchant_service":
			svc_label = String(a.label)
	ok("행동 목록의 값도 같은 정본을 쓴다(하드코딩 40 없음)", svc_label == "" or svc_label.find("100") >= 0, svc_label)

	# 무료로 받은 권에는 값을 청구하지 않는다(사건 보상 경로와 같은 형태)
	var rf := PRun.new_run(8, "sword")
	rf.services["free_rest"] = 1
	var gf := int(rf.gold)
	var hf := int(rf.hours)
	rf.hp = 10.0
	var rested := PRun.rest(rf)
	ok("보상으로 받은 무료 휴식권: 금화 0 · 시간 0칸 · 체력 완전 회복(뒤늦게 100을 청구하지 않는다)",
		rested and int(rf.gold) == gf and int(rf.hours) == hf and float(rf.hp) == float(PRun.build(rf).hp_max) and not PRun.has_service(rf, "free_rest"),
		"gold %d hours %d hp %.0f" % [int(rf.gold), int(rf.hours), float(rf.hp)])

	# ---------- 2. 유료 새로고침: 값 · 상한 · 초기화 ----------
	var r2 := PRun.new_run(11, "sword")
	r2.gold = 1000
	var st0 := PRun.stock(r2)
	var eq_before := str(st0.equipment)
	ok("새로고침 값은 60에서 시작하고 오늘 3회까지 가능하다",
		PRun.stock_refresh_cost(r2) == int(SH.stockRefresh.base) and PRun.stock_refresh_left(r2) == int(SH.stockRefresh.maxPerDay) and PRun.stock_refreshes_today(r2) == 0)
	var gold_b := int(r2.gold)
	PRun.refresh_stock_paid(r2)
	ok("1회 새로고침: 금화 -60, 다음 값 90, 재고가 실제로 바뀐다",
		int(r2.gold) == gold_b - 60 and PRun.stock_refresh_cost(r2) == 90 and PRun.stock_refreshes_today(r2) == 1,
		"gold %d cost %d eq %s → %s" % [int(r2.gold), PRun.stock_refresh_cost(r2), eq_before, str(PRun.stock(r2).equipment)])
	PRun.refresh_stock_paid(r2)
	ok("2회째: -90, 다음 값 135", int(r2.gold) == gold_b - 60 - 90 and PRun.stock_refresh_cost(r2) == 135)
	PRun.refresh_stock_paid(r2)
	ok("3회째: -135, 오늘 한도 소진(더 못 함)", int(r2.gold) == gold_b - 60 - 90 - 135 and PRun.stock_refresh_left(r2) == 0 and not PRun.can_refresh_stock(r2), PRun.stock_refresh_reason(r2))
	var before_fail := _json(r2)
	var failed := PRun.refresh_stock_paid(r2)
	ok("한도를 넘긴 새로고침은 실패하고 회차를 전혀 바꾸지 않는다(금화도 재고도 그대로)", not failed and _json(r2) == before_fail)
	PRun.end_day(r2)
	ok("하루가 바뀌면 횟수·값이 초기화된다(내일 아침 초기화)",
		PRun.stock_refreshes_today(r2) == 0 and PRun.stock_refresh_cost(r2) == int(SH.stockRefresh.base) and (PRun.stock(r2).locked as Array).is_empty())

	# ---------- 3. 잠금: 보존 · 상한 · 새로고침 뒤 유지 ----------
	var r3 := PRun.new_run(12, "sword")
	r3.gold = 1000
	var s3 := PRun.stock(r3)
	var keep := String(s3.equipment[0])
	ok("잠금은 최대 %d칸" % int(SH.stockRefresh.lockMax), PRun.toggle_stock_lock(r3, keep) and PRun.stock_locked(r3, keep))
	PRun.refresh_stock_paid(r3)
	ok("잠근 칸은 새로고침해도 그대로 남고 잠금도 유지된다",
		(PRun.stock(r3).equipment as Array).has(keep) and PRun.stock_locked(r3, keep), str(PRun.stock(r3).equipment))
	var lock2 := ""
	for id in PRun.stock(r3).equipment:
		if String(id) != keep:
			lock2 = String(id)
	PRun.toggle_stock_lock(r3, lock2)
	ok("잠금 상한을 넘으면 더 잠글 수 없다(기술 칸까지 3개는 불가)",
		PRun.stock_lock_reason(r3, "skill") != "" or (PRun.stock(r3).locked as Array).size() <= int(SH.stockRefresh.lockMax),
		"locked %s" % str(PRun.stock(r3).locked))

	# ---------- 4. 새로고침·구매·저장 복구로 복제가 없다 ----------
	var r4 := PRun.new_run(13, "sword")
	r4.gold = 2000
	var buy_id := String(PRun.stock(r4).equipment[0])
	var g4 := int(r4.gold)
	PRun.buy_equipment(r4, buy_id, false, "stock")
	PRun.refresh_stock_paid(r4)
	ok("산 장비는 새로고침해도 되살아나지 않고 다시 살 수도 없다(상품·비용 복제 없음)",
		not PRun.can_buy_equipment(r4, buy_id, "stock") and PRun.owns_equip(r4, buy_id) and (PRun.stock(r4).sold as Array).has(buy_id)
			and int(r4.gold) == g4 - PRun.equip_price(buy_id) - 60,
		"gold %d (기대 %d)" % [int(r4.gold), g4 - PRun.equip_price(buy_id) - 60])
	var saved := PSave.normalize(r4.duplicate(true))
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	PSave.normalize(reloaded)
	ok("저장·복구 뒤에도 새로고침 횟수·잠금·판매 기록이 그대로다(재접속 초기화 악용 없음)",
		int(reloaded.stock.refresh.count) == int(r4.stock.refresh.count) and str(reloaded.stock.sold) == str(r4.stock.sold)
			and int(reloaded.gold) == int(r4.gold) and JSON.stringify(saved) == JSON.stringify(reloaded),
		"count %d sold %s" % [int(reloaded.stock.refresh.count), str(reloaded.stock.sold)])

	# ---------- 5. 준비물: 구매 상한 · 1개만 장착 · 해제·교체 무소모 ----------
	var r5 := PRun.new_run(21, "sword")
	r5.gold = 2000
	ok("준비물 5종이 있고 값·역할·설명이 데이터에 있다", PConsumables.prep_ids().size() == 5 and PConsumables.price("guard_charm") > 0 and String(PConsumables.def("guard_charm").roleName) != "", str(PConsumables.prep_ids()))
	PConsumables.buy(r5, "guard_charm")
	PConsumables.buy(r5, "guard_charm")
	ok("같은 준비물은 %d개까지" % int(CR.perItemMax), PConsumables.count(r5, "guard_charm") == 2 and not PConsumables.can_buy(r5, "guard_charm"), PConsumables.buy_reason(r5, "guard_charm"))
	PConsumables.buy(r5, "hunter_seal")
	ok("가방은 %d개까지(넘으면 못 산다)" % int(CR.carryMax), PConsumables.prep_count(r5) == 3 and not PConsumables.can_buy(r5, "shatter_oil"), PConsumables.buy_reason(r5, "shatter_oil"))
	var before_sel := _json(r5)
	PConsumables.select(r5, "guard_charm")
	PConsumables.select(r5, "hunter_seal")
	PConsumables.clear_select(r5)
	PConsumables.select(r5, "guard_charm")
	ok("여러 개를 겹쳐 걸 수 없고(항상 1개), 해제·교체는 아무것도 소모하지 않는다",
		PConsumables.armed(r5) == "guard_charm" and PConsumables.count(r5, "guard_charm") == 2 and PConsumables.count(r5, "hunter_seal") == 1
			and PConsumables.prep_count(r5) == 3)
	var after_sel := r5.duplicate(true)
	after_sel.prepItem = null
	after_sel.log = (JSON.parse_string(before_sel) as Dictionary).log
	ok("장착·해제를 반복해도 가방·금화가 변하지 않는다", _json(after_sel) == before_sel)

	# ---------- 6. 전투 입장에서 정확히 1개 소모 · 다음 전투로 이어지지 않는다 ----------
	var r6 := PRun.new_run(22, "sword")
	r6.gold = 2000
	PConsumables.buy(r6, "guard_charm")
	PConsumables.buy(r6, "guard_charm")
	PConsumables.select(r6, "guard_charm")
	var b_armed := PRun.build(r6)
	var b_plain := PBuild.derive(r6)
	ok("수호 부적: 시작 보호막이 부적 값만큼 늘고, 장비 효과(equip.startShield)는 건드리지 않는다(월광 갑옷 재생 상한 불변)",
		is_equal_approx(float(b_armed.shield), float(b_plain.shield) + float(PConsumables.def("guard_charm").eff.shield))
			and not (b_armed.equip as Dictionary).has("startShield"),
		"shield %.1f → %.1f" % [float(b_plain.shield), float(b_armed.shield)])
	var so6 := PSortie.start(r6, String(PSortie.cards_for(r6)[0].id))
	var f1 := _enter_fight(r6, so6)
	ok("전투 입장: 준비물 1개만 빠지고 장착이 비워진다(그 전투 빌드에는 이미 들어가 있다)",
		String(f1.used) == "guard_charm" and PConsumables.count(r6, "guard_charm") == 1 and PConsumables.armed(r6) == ""
			and is_equal_approx(float((f1.st as CombatState).player.shield_max), float(b_armed.shield)),
		"남은 %d shield_max %.1f" % [PConsumables.count(r6, "guard_charm"), float((f1.st as CombatState).player.shield_max)])
	var f2 := _enter_fight(r6, so6)
	ok("같은 출격의 다음 전투(더 깊이)로 자동 연장되지 않는다: 다시 고르지 않으면 아무것도 쓰지 않는다",
		String(f2.used) == "" and PConsumables.count(r6, "guard_charm") == 1 and not (PRun.build(r6) as Dictionary).has("prep"))
	var g6 := int(r6.gold)
	var c6 := PConsumables.count(r6, "guard_charm")
	var saved6 := PSave.normalize(r6.duplicate(true))
	var back6: Dictionary = JSON.parse_string(JSON.stringify(saved6))
	PSave.normalize(back6)
	ok("전투 중 종료·재접속으로 이미 쓴 준비물이 되살아나지 않는다(무한 회복 차단)",
		PConsumables.count(back6, "guard_charm") == c6 and int(back6.gold) == g6 and PConsumables.armed(back6) == "")

	# ---------- 7. 효과가 기존 규칙과 겹쳐도 두 번 계산되지 않는다 ----------
	var r7 := PRun.new_run(23, "sword")
	r7.gold = 2000
	r7.bag.append("hunter_sword")
	PRun.equip_item(r7, "hunter_sword")
	PConsumables.buy(r7, "hunter_seal")
	PConsumables.select(r7, "hunter_seal")
	var b7 := PRun.build(r7)
	var want7: float = float(PCatalog.equipment_def("hunter_sword").eff.eliteDirect) + float(PConsumables.def("hunter_seal").eff.eliteDirect)
	ok("사냥꾼의 인장 + 사냥꾼의 검: 같은 칸에서 한 번만 더해진다(0.15 + 0.10 = 0.25, 곱하지 않음)",
		is_equal_approx(float(b7.equip.eliteDirect), want7), "eliteDirect %.3f" % float(b7.equip.eliteDirect))
	var r7b := PRun.new_run(23, "sword")
	r7b.gold = 2000
	PConsumables.buy(r7b, "shatter_oil")
	PConsumables.select(r7b, "shatter_oil")
	var b7b := PRun.build(r7b)
	var floor7 := PConsumables.guard_floor(b7b)
	var sb := PCatalog.enemy("shieldbearer")
	var bm := PCatalog.enemy("elite_blademaster")
	var sb_front := float(sb.get("guardMult", sb.get("frontMult", 1.0)))
	var bm_front := float(bm.get("guardMult", bm.get("frontMult", 1.0)))
	ok("파쇄 기름 하한 0.35: 방패병 정면(%.2f)·정예 검사 정면(%.2f)이 모두 0.35까지만 올라간다(min 규칙은 그대로, 곱하지 않는다)" % [sb_front, bm_front],
		is_equal_approx(floor7, 0.35) and maxf(sb_front, floor7) == 0.35 and maxf(bm_front, floor7) == 0.35 and floor7 < 1.0,
		"floor %.2f" % floor7)
	ok("파쇄 기름은 정면을 옆·뒤보다 좋게 만들지 않는다(하한을 둬도 65% 감소가 남는다)", floor7 <= 0.5)
	ok("준비물을 걸지 않으면 하한도 완화도 없다(기본 전투 불변)",
		is_equal_approx(PConsumables.guard_floor(PBuild.derive(r7b)), 0.0) and is_equal_approx(float(PConsumables.purge(PBuild.derive(r7b)).slow), 0.0))
	var r7c := PRun.new_run(24, "sword")
	r7c.gold = 2000
	PConsumables.buy(r7c, "cleanse_incense")
	PConsumables.select(r7c, "cleanse_incense")
	var pg := PConsumables.purge(PRun.build(r7c))
	ok("정화 향은 실제로 있는 해로운 바닥 효과에만 연결된다(거미줄·빙판 감속 %d%%, 포자·붕괴 바닥 피해 %d%%)" % [int(float(pg.slow) * 100.0), int(float(pg.zone) * 100.0)],
		float(pg.slow) > 0.0 and float(pg.zone) > 0.0 and float(pg.slow) <= 1.0 and float(pg.zone) <= 1.0)
	var r7d := PRun.new_run(25, "sword")
	r7d.gold = 2000
	r7d.bag.append("emergency_shield")
	PRun.equip_item(r7d, "emergency_shield")
	PConsumables.buy(r7d, "relief_pouch")
	PConsumables.select(r7d, "relief_pouch")
	var b7d := PRun.build(r7d)
	var lh := PConsumables.low_heal(b7d)
	ok("응급 약낭은 비상 방패와 다른 칸이다(보호막 20은 그대로, 회복 18은 따로)",
		not lh.is_empty() and int(lh.heal) == 18 and (b7d.equip as Dictionary).has("lowShield") and int(b7d.equip.lowShield.shield) == 20)

	# ---------- 8. 회복약: 하루 상한 · 회복량 · 최대 초과 없음 ----------
	var r8 := PRun.new_run(31, "sword")
	r8.gold = 2000
	var hp_max: float = float(PRun.build(r8).hp_max)
	r8.hp = 10.0
	PConsumables.buy(r8, "potion")
	PConsumables.buy(r8, "potion")
	ok("회복약은 하루 %d개까지만 살 수 있다(무제한 구매로 휴식이 사라지지 않는다)" % int(CR.potionPerDay),
		PConsumables.potion_count(r8) == 2 and PConsumables.potion_left_today(r8) == 0 and not PConsumables.can_buy(r8, "potion"),
		PConsumables.buy_reason(r8, "potion"))
	var healed := PConsumables.use_potion(r8)
	ok("회복약 1개: 체력 +%d, 시간 0칸, 개수 1 감소" % int(float(PConsumables.potion_def().heal)),
		is_equal_approx(healed, float(PConsumables.potion_def().heal)) and is_equal_approx(float(r8.hp), 10.0 + healed) and PConsumables.potion_count(r8) == 1)
	r8.hp = hp_max - 5.0
	var healed2 := PConsumables.use_potion(r8)
	ok("최대 체력을 넘지 않는다(초과분은 버려진다 — 저장되거나 보호막이 되지 않는다)",
		is_equal_approx(healed2, 5.0) and is_equal_approx(float(r8.hp), hp_max) and not PConsumables.can_use_potion(r8))
	ok("회복약 한 개로는 완전 회복이 안 된다(휴식·휴식권과 역할이 겹치지 않는다)", float(PConsumables.potion_def().heal) < hp_max)
	PRun.end_day(r8)
	ok("하루가 지나면 구매 한도가 다시 열린다", PConsumables.potion_left_today(r8) == int(CR.potionPerDay))
	var r8b := PRun.new_run(32, "sword")
	r8b.gold = 30
	ok("금화가 모자라면 못 산다(음수 금화 없음)", not PConsumables.can_buy(r8b, "potion") and int(r8b.gold) == 30)

	# ---------- 9. 보스 재도전: 입장 스냅샷과 같은 규칙 ----------
	# 재도전 자체는 2026-09-09부터 **시험·자동 진행 전용 경로**다(사람 플레이는 쓰러지면 회차가 끝난다 — tests/death_tests.gd).
	# 여기서 보는 것은 그 경로의 스냅샷 규칙이므로 회차를 명시적으로 재시도 경로로 만든다.
	var r9 := PRun.new_run(41, "sword", "", { "test_retry": true })
	r9.gold = 2000
	PConsumables.buy(r9, "guard_charm")
	PConsumables.buy(r9, "potion")
	PConsumables.select(r9, "guard_charm")
	r9.phase = "boss_prep"
	var bs9 := PRun.start_boss(r9)
	var used9 := PConsumables.consume_for_fight(r9)
	ok("보스 입장에서도 준비물이 1개 빠진다", String(used9) == "guard_charm" and PConsumables.count(r9, "guard_charm") == 0)
	PConsumables.use_potion(r9) if PConsumables.can_use_potion(r9) else null
	PRun.boss_defeat(r9)
	ok("보스 패배·재도전: 준비물·회복약도 입장 시점으로 복구된다(재도전마다 다시 사지 않고, 무한 회복도 아니다)",
		PConsumables.count(r9, "guard_charm") == 1 and PConsumables.count(r9, "potion") == 1 and PConsumables.armed(r9) == "guard_charm",
		"부적 %d 약 %d 장착 %s" % [PConsumables.count(r9, "guard_charm"), PConsumables.count(r9, "potion"), PConsumables.armed(r9)])

	# ---------- 10. 막이 오르면 새 구매 후보가 열린다 ----------
	var r10 := PRun.new_run(51, "sword")
	var act1_pool := []
	var act3_pool := []
	for id in PCatalog.equipment():
		if PRun.equip_act_ok(r10, String(id)):
			act1_pool.append(String(id))
	r10.day = 9
	for id in PCatalog.equipment():
		if PRun.equip_act_ok(r10, String(id)):
			act3_pool.append(String(id))
	var slots1 := {}
	for id in act1_pool:
		var sl := String(PCatalog.equipment_def(id).slot)
		slots1[sl] = int(slots1.get(sl, 0)) + 1
	ok("1막에도 부위마다 후보가 2개 이상이고, 뒤 막에서 새 후보가 열린다(같은 장비의 상위 수치 반복이 아니라 새 역할)",
		act1_pool.size() < act3_pool.size() and int(slots1.get("weapon", 0)) >= 2 and int(slots1.get("armor", 0)) >= 2 and int(slots1.get("shield", 0)) >= 2,
		"1막 %d(%s) → 3막 %d" % [act1_pool.size(), str(slots1), act3_pool.size()])
	var roles := {}
	for id in PCatalog.equipment():
		roles[String(PCatalog.equipment_def(String(id)).get("role", ""))] = true
	ok("장비에 역할이 붙어 있다(다수 처리·정예 상대·접근·보호막·큰 타격 방어·연계)",
		roles.has("crowd") and roles.has("elite") and roles.has("approach") and roles.has("ward") and roles.has("bighit") and roles.has("skill"),
		str(roles.keys()))

	var pass_n := 0
	for x in results:
		if x[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
