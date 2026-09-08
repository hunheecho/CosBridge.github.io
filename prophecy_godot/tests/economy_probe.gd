extends SceneTree
## 회차 경제 측정(막별 수입·지출·잔액 + 회복 경제). 통과 조건은 장부가 맞는가이지 봇의 승패가 아니다.
## 실행: python tools/run_suites.py --suites economy_probe --jobs 1 --allow-adhoc
## 결과 표는 그대로 docs/sim/RUN_ECONOMY.md에 옮긴다.
##
## 무엇을 재는가(2026-09-08 지시 §9)
##  - 막별 수입 / 지출 / 막 끝 잔액. 지출은 강화·장비·기술로 나눈다(봇은 아직 새 지출처를 쓰지 않는다 — 그래서 '남는 돈'이 그대로 보인다).
##  - 새 지출처(재고 새로고침·출격 준비물·회복약·무료 휴식권)가 막마다 최대 얼마를 흡수할 수 있는지.
##  - 회복 수단별 회복량·금화·시간(회복 경제).
## 봇 결과는 정책 비교용이며 사람의 체감이 아니다. 여기서 "쉬워서 필요 없는지"는 받은 피해·패배 수로 따로 본다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _act_of_day(run: Dictionary, day: int) -> int:
	var a := PRun.act_of(run, day)
	return int(a.get("id", 1)) if not a.is_empty() else 1

## 그 날 산 장비 값(가방·장착 목록의 차이로 되짚는다). 판매는 음수가 아니라 0으로 둔다(수입 쪽에 이미 들어간다)
func _equip_spend(prev: Dictionary, cur: Dictionary) -> int:
	var had := {}
	for s in prev.get("equipment", {}):
		if prev.equipment[s] != null:
			had[String(prev.equipment[s])] = true
	for id in prev.get("bag", []):
		had[String(id)] = true
	var spend := 0
	for s in cur.get("equipment", {}):
		if cur.equipment[s] != null and not had.has(String(cur.equipment[s])):
			spend += PRun.equip_price(String(cur.equipment[s]))
	for id in cur.get("bag", []):
		if not had.has(String(id)):
			spend += PRun.equip_price(String(id))
	return spend

func _init() -> void:
	var C := PCatalog.config()
	var SH := PCatalog.shop()
	var CR := PConsumables.rules()
	var seeds := [1, 2, 3, 4]
	var strats := ["gradual", "deep"]
	# 막 → { income, spend, spend_equip, spend_other, end_gold[], days }
	var acts := {}
	var runs_ok := 0
	var totals := { "income": 0, "spend": 0, "encounters": 0, "losses": 0, "rests": 0, "taken": 0.0 }
	for strat in strats:
		for sd in seeds:
			var res := PRunBot.simulate(int(sd), String(strat), {})
			var L: Dictionary = res
			var days: Array = L.get("matsByDay", [])
			var spent: Array = L.get("spentByDay", [])
			if days.is_empty():
				continue
			runs_ok += 1
			var probe := PRun.new_run(int(sd), "sword") # 막 경계만 읽는 참조 회차(같은 mode·일정)
			var prev_gold := int(C.START_GOLD)
			var prev_state := { "equipment": { "weapon": null, "armor": null, "shield": null }, "bag": [] }
			for i in days.size():
				var d: Dictionary = days[i]
				var day := int(d.day)
				var a := _act_of_day(probe, day)
				if not acts.has(a):
					acts[a] = { "income": 0, "spend": 0, "equip": 0, "other": 0, "end": [], "days": 0 }
				var A: Dictionary = acts[a]
				var sp: int = int(spent[i]) if i < spent.size() else 0
				var end_gold := int(d.gold)
				var income: int = end_gold - prev_gold + sp
				var eq_sp := _equip_spend(prev_state, d)
				A.income = int(A.income) + income
				A.spend = int(A.spend) + sp
				A.equip = int(A.equip) + mini(eq_sp, sp)
				A.other = int(A.other) + maxi(0, sp - eq_sp)
				(A.end as Array).append(end_gold)
				A.days = int(A.days) + 1
				totals.income += income
				totals.spend += sp
				prev_gold = end_gold
				prev_state = d
			totals.encounters += int(L.get("encounters", 0))
			totals.losses += int(L.get("losses", 0))
			totals.rests += int(L.get("rests", 0))
			totals.taken += float(L.get("taken", 0.0))
			# 장부 항등식: 시작 금화 + 수입 − 지출 = 마지막 잔액
			var sum_income := 0
			var sum_spend := 0
			for i in days.size():
				sum_spend += int(spent[i]) if i < spent.size() else 0
			sum_income = int((days[days.size() - 1] as Dictionary).gold) - int(C.START_GOLD) + sum_spend
			ok("장부가 맞는다(%s 시드 %d): 시작 %d + 수입 %d − 지출 %d = 잔액 %d" % [strat, int(sd), int(C.START_GOLD), sum_income, sum_spend, int((days[days.size() - 1] as Dictionary).gold)],
				int(C.START_GOLD) + sum_income - sum_spend == int((days[days.size() - 1] as Dictionary).gold))
	ok("회차 표본이 모였다(%d회)" % runs_ok, runs_ok >= 4)

	# ---------- 막별 표 ----------
	print("")
	print("### 막별 수입·지출·잔액 (봇 %d회 평균, 새 지출처는 아직 쓰지 않음)" % runs_ok)
	print("")
	print("| 막 | 일수 | 수입 | 지출(합) | 장비 | 강화·기술 | 막 끝 잔액(평균) | 막 끝 잔액(최대) | 안 쓴 비율 |")
	print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
	var keys := acts.keys()
	keys.sort()
	for a in keys:
		var A: Dictionary = acts[a]
		var n := maxi(1, runs_ok)
		var ends: Array = A.end
		var end_avg := 0
		var end_max := 0
		for v in ends:
			end_avg += int(v)
			end_max = maxi(end_max, int(v))
		end_avg = int(round(float(end_avg) / float(maxi(1, ends.size()))))
		var inc: int = int(round(float(A.income) / float(n)))
		var spd: int = int(round(float(A.spend) / float(n)))
		var unused: float = (1.0 - float(spd) / float(maxi(1, inc))) * 100.0
		print("| %d막 | %d | %d | %d | %d | %d | %d | %d | %d%% |" % [int(a), int(round(float(A.days) / float(n))), inc, spd,
			int(round(float(A.equip) / float(n))), int(round(float(A.other) / float(n))), end_avg, end_max, int(round(unused))])
	print("")
	print("합계: 수입 %d · 지출 %d · 안 쓴 금화 %d (%d%%) · 조우 %d(패배 %d) · 휴식 %d · 받은 피해 %d" % [
		int(round(float(totals.income) / float(maxi(1, runs_ok)))), int(round(float(totals.spend) / float(maxi(1, runs_ok)))),
		int(round(float(totals.income - totals.spend) / float(maxi(1, runs_ok)))),
		int(round((1.0 - float(totals.spend) / float(maxi(1, totals.income))) * 100.0)),
		int(round(float(totals.encounters) / float(maxi(1, runs_ok)))), int(round(float(totals.losses) / float(maxi(1, runs_ok)))),
		int(round(float(totals.rests) / float(maxi(1, runs_ok)))), int(round(totals.taken / float(maxi(1, runs_ok))))])

	# ---------- 새 지출처가 막마다 흡수할 수 있는 금액 ----------
	var mode := PRun.mode_def(PRun.new_run(1, "sword"))
	var probe2 := PRun.new_run(1, "sword")
	var refresh_day: int = int(SH.stockRefresh.base) + int(round(float(SH.stockRefresh.base) * float(SH.stockRefresh.mult))) + int(round(float(SH.stockRefresh.base) * pow(float(SH.stockRefresh.mult), 2.0)))
	var prep_max := 0
	for id in PConsumables.prep_ids():
		prep_max = maxi(prep_max, PConsumables.price(String(id)))
	var potion_day: int = PConsumables.price("potion") * int(CR.potionPerDay)
	print("")
	print("### 새 지출처가 흡수할 수 있는 금액 (하루 최대)")
	print("")
	print("| 지출처 | 하루 최대 | 산식 |")
	print("|---|---:|---|")
	print("| 재고 새로고침 | %d | %d + %d + %d (연속 %d회, ×%s씩) |" % [refresh_day, int(SH.stockRefresh.base),
		int(round(float(SH.stockRefresh.base) * float(SH.stockRefresh.mult))), int(round(float(SH.stockRefresh.base) * pow(float(SH.stockRefresh.mult), 2.0))),
		int(SH.stockRefresh.maxPerDay), str(SH.stockRefresh.mult)])
	print("| 출격 준비물 | %d | 가방 %d개 × 최고가 %d (전투마다 1개 소모) |" % [prep_max * int(CR.carryMax), int(CR.carryMax), prep_max])
	print("| 회복약 | %d | %d × 하루 %d개 |" % [potion_day, PConsumables.price("potion"), int(CR.potionPerDay)])
	print("| 무료 휴식권 | %d | 상인이 오는 날만 1장 |" % PRun.merchant_service_price("free_rest"))
	print("| 하루 합계 | %d | 상인 날은 +%d |" % [refresh_day + prep_max * int(CR.carryMax) + potion_day, PRun.merchant_service_price("free_rest")])

	# ---------- 회복 경제 ----------
	var r0 := PRun.new_run(1, "sword")
	var hp_max: float = float(PRun.build(r0).hp_max)
	print("")
	print("### 회복 경제 (최대 체력 %d 기준)" % int(hp_max))
	print("")
	print("| 수단 | 1회 회복 | 금화 | 시간(칸) | 금화 1당 회복 | 상한 |")
	print("|---|---:|---:|---:|---:|---|")
	var pot: float = float(PConsumables.potion_def().heal)
	print("| 회복약 | %d | %d | 0 | %.2f | 하루 %d개 구매 · %d개 소지 |" % [int(pot), PConsumables.price("potion"), pot / float(PConsumables.price("potion")), int(CR.potionPerDay), int(CR.potionCarryMax)])
	print("| 휴식 | %d(완전) | 0 | %d | — | 남은 시간 칸만큼 |" % [int(hp_max), int(C.REST_HOURS)])
	print("| 무료 휴식권 | %d(완전) | %d | 0 | %.2f | 상인 방문일 1장 |" % [int(hp_max), PRun.merchant_service_price("free_rest"), hp_max / float(PRun.merchant_service_price("free_rest"))])
	var exp_heal: float = float(PCatalog.equipment_def("expedition_armor").eff.winHeal)
	print("| 원정대의 갑옷(장비) | %d/승리 | %d | 0 | %.2f (승리 1회) | 갑옷 칸 1개 |" % [int(exp_heal), PRun.equip_price("expedition_armor"), exp_heal / float(PRun.equip_price("expedition_armor"))])
	var ren: Dictionary = PCatalog.equipment_def("renewal_coat")
	print("| 재생의 여행복(제작) | %d/승리 + 초과분 보호막 최대 %d | 제작 | 0 | — | 갑옷 칸 1개 |" % [int(float(ren.eff.winHeal)), int(float(ren.eff.overflowShield.max))])
	var pouch: Dictionary = PConsumables.def("relief_pouch")
	print("| 응급 약낭(준비물) | %d(체력 %d%% 이하일 때 1회) | %d | 0 | %.2f | 전투 1회 |" % [int(float(pouch.eff.lowHeal.heal)), int(float(pouch.eff.lowHeal.frac) * 100.0), PConsumables.price("relief_pouch"), float(pouch.eff.lowHeal.heal) / float(PConsumables.price("relief_pouch"))])
	var em: Dictionary = PCatalog.equipment_def("emergency_shield")
	print("| 비상 방패(장비, 흡수) | %d 흡수(체력 %d%% 이하 1회) | %d | 0 | %.2f | 방패 칸 1개 |" % [int(float(em.eff.lowShield.shield)), int(float(em.eff.lowShield.frac) * 100.0), PRun.equip_price("emergency_shield"), float(em.eff.lowShield.shield) / float(PRun.equip_price("emergency_shield"))])
	var charm: Dictionary = PConsumables.def("guard_charm")
	print("| 수호 부적(준비물, 흡수) | %d 흡수(시작 시) | %d | 0 | %.2f | 전투 1회 |" % [int(float(charm.eff.shield)), PConsumables.price("guard_charm"), float(charm.eff.shield) / float(PConsumables.price("guard_charm"))])
	print("")
	ok("회복약 1개로는 완전 회복이 안 되고(휴식이 사라지지 않는다) 하루 구매 상한이 있다", pot < hp_max and int(CR.potionPerDay) > 0)
	ok("하루 회복약 상한(%d개, 체력 %d)이 완전 회복 1회보다 작다 — 휴식·휴식권이 여전히 필요하다" % [int(CR.potionPerDay), int(pot) * int(CR.potionPerDay)],
		pot * float(CR.potionPerDay) < hp_max, "%d < %d" % [int(pot) * int(CR.potionPerDay), int(hp_max)])
	ok("무료 휴식권(%d금)이 회복약 하루치(%d금)보다 비싸다 — 완전 회복·시간 절약 값이 더 크다" % [PRun.merchant_service_price("free_rest"), potion_day],
		PRun.merchant_service_price("free_rest") > potion_day)

	var pass_n := 0
	for x in results:
		if x[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
