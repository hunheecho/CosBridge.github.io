extends SceneTree
## 밸런스·편성·경제 개편 회귀(지시 2~5·8~10·15). 사용자 결정과 시험값을 구분해 검사한다.
## 사용자 결정: 첫날 25 → 10일차 수준 75, 등급 교체 구조, 금화 약 -30%, 무료 이득 사건의 지나치기 제거, 남는 시간 출격 경로.
## 시험값: 중간 날짜 수, 막별 동시 상한, 역할별 목표 시간·체력, 보스 체력, 반복 탐험 비용.
## 실행: godot --headless --path prophecy_godot -s tests/balance_tests.gd (user:// 사용 없음)

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 경로는 기본 테마로 고정한다(시드마다 경로가 달라 편성 id가 바뀌는 것을 막는다)
func run_with(seed_v: int, opts: Dictionary = {}) -> Dictionary:
	var o := { "route": [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)] }
	for k in opts:
		o[k] = opts[k]
	return PRun.new_run(seed_v, "sword", "", o)

func sortie_of(run: Dictionary, rid: String, day: int, fid: String) -> Dictionary:
	return { "regionId": rid, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 7, "day": day, "slot": 0, "variant": null, "formationId": fid }

func _init() -> void:
	# ---------- 지시 2: 일정 식별 ----------
	var acts := run_with(11)
	var trio := run_with(11, { "mode": "trio" })
	ok("새 회차 기본은 10일 본편(acts, 관문 4/7/10)", String(acts.mode) == "acts" and int(PRun.mode_def(acts).days) == 10 and PRun.schedule_short(acts) == "본편 · 10일", PRun.schedule_label(acts))
	ok("옛 7일 회차는 '이전 회차 · 7일 일정'으로 구분 표시(조용히 10일로 늘리지 않는다)", PRun.schedule_short(trio) == "이전 회차 · 7일 일정" and int(PRun.mode_def(trio).days) == 7 and PRun.schedule_label(trio).find("관문 3/5/7") >= 0, PRun.schedule_label(trio))
	ok("저장 dict만으로도 같은 판정(계속하기 버튼 라벨용)", PRun.schedule_short_of_save({ "mode": "trio" }) == "이전 회차 · 7일 일정" and PRun.schedule_short_of_save({ "mode": "acts" }) == "본편 · 10일")
	ok("결과·검증 기록용 설정 한 줄에 일정·밀도·동시 상한·밸런스·시드", PRun.settings_record(acts).find("본편 · 10일") >= 0 and PRun.settings_record(acts).find("밀도") >= 0 and PRun.settings_record(acts).find("동시 상한") >= 0, PRun.settings_record(acts))

	# ---------- 지시 3: 날짜별 총 등장 수 ----------
	var tbl := []
	for d in range(1, 11):
		tbl.append(PPacing.day_total(d, 1))
	ok("날짜별 총 등장 수(사용자 결정 25 → 75): 1~10일 25/30/35/40/45/50/55/60/70/75", tbl == [25, 30, 35, 40, 45, 50, 55, 60, 70, 75], str(tbl))
	ok("핵심(비용 2칸) 장소는 +7%: 9일차 75 — 일반 탐험 마지막 날에 '10일차 수준'을 실제로 만난다", PPacing.day_total(9, 2) == 75 and PPacing.day_total(1, 2) == 27, "%d/%d" % [PPacing.day_total(9, 2), PPacing.day_total(1, 2)])
	var r1 := run_with(12)
	var p1 := String(PRun.route_theme(r1, 1).places[0].id)
	var st_first := PFlow.make_encounter(r1, sortie_of(r1, p1, 1, "t1a_first"))
	ok("승인된 첫날 기준 전투 보존: 늑대 25·동시 12(날짜 표·막별 상한이 덮어쓰지 않는다)", (st_first.formation.units as Array).size() == 25 and int(st_first.formation.alive_cap) == 12 and int(st_first.formation.godot_counts.wolf) == 25)
	var r9 := run_with(12)
	r9.day = 9 # 날짜 예산·막별 상한은 회차의 실제 날짜에서 나온다
	r9.stage = 2
	r9.bossesDone = ["boss", "guardian"]
	var day9 := PFlow.make_encounter(r9, sortie_of(r9, String(PRun.route_theme(r9, 3).places[1].id), 9, "t3a_mixed"))
	ok("9일차 핵심 장소 = 75마리, 총 등장 수와 동시 생존 수는 다르다(동시 18)", (day9.formation.units as Array).size() == 75 and int(day9.formation.alive_cap) == 18, "%d/%d" % [(day9.formation.units as Array).size(), int(day9.formation.alive_cap)])
	ok("10일차는 최종 관문 전용이라 일반 출격 장소가 없다", PRun.places_for(r1, 10).is_empty())
	# 경험치·금화가 개체 수에 비례해 늘지 않는다
	var xp1 := 0.0
	for t in st_first.formation.html_counts:
		xp1 += float(st_first.formation.xp_map[t]) * float(st_first.formation.godot_counts[t])
	var xp9 := 0.0
	for t in day9.formation.html_counts:
		xp9 += float(day9.formation.xp_map[t]) * float(day9.formation.godot_counts[t])
	# 같은 편성을 1일차(27마리)와 9일차(75마리)로 만들어 비교: 개체 수는 2.8배지만 전투 경험치 예산은 그대로여야 한다
	var r_early := run_with(12)
	r_early.day = 1
	r_early.stage = 2
	r_early.bossesDone = ["boss", "guardian"]
	var early := PFlow.make_encounter(r_early, sortie_of(r_early, String(PRun.route_theme(r_early, 3).places[1].id), 1, "t3a_mixed"))
	var xp_early := 0.0
	for t in early.formation.html_counts:
		xp_early += float(early.formation.xp_map[t]) * float(early.formation.godot_counts[t])
	ok("보상 예산 먼저·개체별 배분: 같은 편성의 개체 수가 27 → 75로 늘어도 전투 경험치 예산은 같다(비례 증가 없음)", (early.formation.units as Array).size() == 27 and (day9.formation.units as Array).size() == 75 and is_equal_approx(snapped(xp_early, 0.01), snapped(xp9, 0.01)), "27마리 %.2f / 75마리 %.2f" % [xp_early, xp9])
	ok("승인된 첫 전투의 경험치 예산 9.0 그대로", is_equal_approx(snapped(xp1, 0.01), 9.0), "%.2f" % xp1)
	# 밀도 배율 이중 적용 없음
	ok("밀도 세트(×5)를 날짜 표에 다시 곱하지 않는다", is_equal_approx(float(day9.formation.multiplier), 1.0))

	# ---------- 지시 3: 막별 동시 상한과 대조군 ----------
	ok("막별 동시 상한(시험값) 1막 12·2막 15·3막 18", PPacing.alive_cap(1, 99) == 12 and PPacing.alive_cap(2, 99) == 15 and PPacing.alive_cap(3, 99) == 18)
	var legacy := run_with(12, { "alive_cap_set": "legacy" })
	legacy.day = 9
	legacy.stage = 2
	legacy.bossesDone = ["boss", "guardian"]
	var st_leg := PFlow.make_encounter(legacy, sortie_of(legacy, String(PRun.route_theme(legacy, 3).places[1].id), 9, "t3a_mixed"))
	ok("legacy 대조군은 템플릿 상한을 그대로 쓴다(증가 전후 비교용)", int(st_leg.formation.alive_cap) == 12 and (st_leg.formation.units as Array).size() == 75, "%d" % int(st_leg.formation.alive_cap))

	# ---------- 지시 4: 혼합 편성 ----------
	var bad_share := []
	var T := PCatalog.themes()
	for tid in T:
		var th: Dictionary = T[tid]
		for f in (th.formations.normal as Array) + (th.formations.risk as Array):
			var sup := 0.0
			for c in f.comp:
				if PPacing.is_support(String(c.type)):
					sup += float(c.share)
			if sup > 0.5 + 1e-6:
				bad_share.append("%s/%s %.2f" % [String(tid), String(f.id), sup])
	ok("지원·통제 역할이 편성의 과반인 템플릿 없음(포자 단독 편성 제거)", bad_share.is_empty(), str(bad_share))
	var shaman_no_escort := []
	for tid in T:
		var th2: Dictionary = T[tid]
		for f in (th2.formations.normal as Array) + (th2.formations.risk as Array):
			var has_shaman := false
			var has_melee := false
			for c in f.comp:
				if String(c.type) == "shaman":
					has_shaman = true
				if PPacing.is_melee(String(c.type)):
					has_melee = true
			if has_shaman and not has_melee:
				shaman_no_escort.append("%s/%s" % [String(tid), String(f.id)])
	ok("주술사가 있는 편성에는 실제로 치료할 근접 호위가 함께 있다", shaman_no_escort.is_empty(), str(shaman_no_escort))
	# 등장 순서: 근접 호위 먼저, 지원만 뒤로 몰리지 않음
	var r5 := run_with(12)
	r5.day = 5
	var mixed := PFlow.make_encounter(r5, sortie_of(r5, String(PRun.route_theme(r5, 1).places[0].id), 5, "t1a_wolves"))
	var units: Array = mixed.formation.units
	var first_half_sup := 0
	var second_half_sup := 0
	for i in units.size():
		if PPacing.is_support(String(units[i])):
			if i < units.size() / 2:
				first_half_sup += 1
			else:
				second_half_sup += 1
	ok("지원 적이 대기열 뒤쪽에만 몰리지 않는다(앞 절반에도 등장)", first_half_sup > 0 and absi(first_half_sup - second_half_sup) <= maxi(2, int(units.size() * 0.1)), "앞 %d / 뒤 %d" % [first_half_sup, second_half_sup])
	ok("대기열 첫 자리는 근접(궁수·주술사가 근접 압박 뒤에서 나오도록)", not PPacing.is_support(String(units[0])), String(units[0]))
	# 승인된 첫 전투는 한 종류라 순서가 바뀌지 않는다
	ok("한 종류 편성(기준 전투)은 순서를 바꾸지 않는다", PFormation.mix_squads(["wolf", "wolf", "wolf"]) == ["wolf", "wolf", "wolf"])

	# ---------- 지시 4: 적 장판 상한 ----------
	var stz := PFlow.make_encounter(r1, sortie_of(r1, p1, 1, "t1a_first"))
	for i in 15:
		stz.add_zone("spore", 100.0 + float(i) * 10.0, 100.0, 20.0, 9.0, 1.0)
	var ez := 0
	for z in stz.zones:
		if PPacing.is_enemy_zone(String(z.type)):
			ez += 1
	ok("적 장판 총량 상한 10: 죽은 적이 남긴 장판이 쌓여도 화면을 덮지 않는다(플레이어 장판은 대상 아님)", ez <= PPacing.max_enemy_zones() and PPacing.max_enemy_zones() == 10, "%d" % ez)

	# ---------- 지시 5: 역할별 고정 체력표 ----------
	ok("등급 교체 구조: 늑대 일반 30 → 붉은 150 → 변이 330(붉은 개체는 막이 바뀌어도 같은 체력)", PPacing.tier_hp("wolf", "normal") == 30.0 and PPacing.tier_hp("wolf", "red") == 150.0 and PPacing.tier_hp("wolf", "apex") == 330.0)
	ok("늑대 배율을 다른 적에 그대로 복제하지 않는다(역할별): 궁수 135 · 방패병 270 · 잠복충 54", PPacing.tier_hp("archer", "red") == 135.0 and PPacing.tier_hp("shieldbearer", "red") == 270.0 and PPacing.tier_hp("burrower", "red") == 54.0)
	var inverted := []
	for tp in PPacing.tier_table():
		if tp == "note":
			continue
		var n0 := PPacing.tier_hp(String(tp), "normal")
		if PPacing.tier_hp(String(tp), "red") < n0 or PPacing.tier_hp(String(tp), "apex") < PPacing.tier_hp(String(tp), "red"):
			inverted.append(String(tp))
	ok("등급 역전 없음(상위 등급이 하위보다 약하지 않다)", inverted.is_empty(), str(inverted))
	ok("체력표는 고정값이다: 기준 DPS × 역할 목표 시간으로 미리 계산했고 실행 중 플레이어 DPS를 읽지 않는다", is_equal_approx(PPacing.ref_dps(2) * PPacing.target_sec("melee_main"), 149.6) and PPacing.ref_dps(1) == 22.0, "%.1f" % (PPacing.ref_dps(2) * PPacing.target_sec("melee_main")))
	ok("정예는 등급이 아니라 막으로 오른다: 1막 120(기존 유지) · 2막 545 · 3막 1200", PPacing.elite_hp("wolf_alpha", 1) == 120.0 and PPacing.elite_hp("wolf_alpha", 2) == 545.0 and PPacing.elite_hp("wolf_alpha", 3) == 1200.0)
	# 실제 생성에도 적용되는가(막 전달 포함)
	var st_hp := CombatState.new({ "build": PRun.build(r1), "hp": 100.0, "seed": 1, "waves": [], "arena": "clearing", "region_id": "lab", "act": 3 })
	st_hp.spawn_hold = true
	var wr := st_hp.spawn_enemy("wolf", 300.0, 300.0, false, "red")
	var wa := st_hp.spawn_enemy("wolf", 320.0, 300.0, false, "apex")
	var el := st_hp.spawn_enemy("wolf_alpha", 340.0, 300.0)
	ok("전투 생성에 표가 실제 적용(3막): 붉은 150 · 변이 330 · 정예 1200", is_equal_approx(float(wr.hp), 150.0) and is_equal_approx(float(wa.hp), 330.0) and is_equal_approx(float(el.hp), 1200.0), "%.0f/%.0f/%.0f" % [float(wr.hp), float(wa.hp), float(el.hp)])
	ok("보스 체력 오버레이(시험값): 가시갈기 6000 · 봉인 수호자 15000 · 예언을 먹는 자 18000", PRun.boss_hp(r1, "boss") == 6000.0 and PRun.boss_hp(r1, "guardian") == 15000.0 and PRun.boss_hp(r1, "eater") == 18000.0, "%.0f" % PRun.boss_hp(r1, "boss"))

	# ---------- 지시 10: 금화 약 -30% ----------
	ok("새로 지급하는 금화 ×0.7(최종 1회): 100 → 70", PPacing.gold_award(100) == 70 and PPacing.gold_mult() == 0.7)
	var rg := run_with(13)
	var gold0: int = int(rg.gold)
	var s_g := sortie_of(rg, p1, 1, "t1a_first")
	var rw := PRun.roll_reward(rg, s_g, PRng.new(5), { "chestGold": 100, "eliteKilled": false })
	ok("전리품·상자 금화에 감축이 적용된다", int(rw.chestGold) == 70 and int(rw.gold) > 0)
	var before_sell: int = int(rg.gold)
	rg.mats["pelt"] = 2
	PRun.sell(rg, "pelt", 1)
	ok("판매금은 감축 대상이 아니다(이중 감축 방지): 늑대 가죽 15 그대로", int(rg.gold) - before_sell == int(PCatalog.materials()["pelt"].sell), "%d" % (int(rg.gold) - before_sell))
	ok("기존 지갑 잔액은 건드리지 않는다", gold0 == int(PCatalog.config().START_GOLD))

	# ---------- 지시 8: 남는 시간 출격 ----------
	var r8 := run_with(14)
	r8.day = 3
	PSortie.cards_for(r8)
	var cards := PSortie.cards_for(r8)
	for c in cards:
		c.done = true
	r8.hours = 2
	var reps := PSortie.repeat_cards(r8)
	ok("오늘의 카드를 모두 끝내고 시간이 남으면 '일반 탐험'으로 나갈 수 있다(1칸)", reps.size() == cards.size() and int(reps[0].timeCost) == 1 and String(reps[0].label) == "일반 탐험", "%d장" % reps.size())
	ok("반복 탐험은 임무 목표·보상 예약이 없다(임무 보상 재지급 없음)", String(reps[0].objective) == "clear" and reps[0].rewardKind == null and int(reps[0].fallbackGold) == 0)
	var acts_ids := PFlow.actions(r8).map(func(a): return String(a.id))
	ok("행동 목록에 반복 탐험이 나온다", acts_ids.has("sortie:" + String(reps[0].id)), str(acts_ids.filter(func(i): return i.begins_with("sortie:"))))
	var hours_before: int = int(r8.hours)
	var s_rep := PSortie.start(r8, String(reps[0].id))
	ok("반복 탐험 출격: 시간 1칸 지불, repeat 표시, 사건 없음", not s_rep.is_empty() and int(r8.hours) == hours_before - 1 and bool(s_rep.repeat))
	# 휴식 구분
	var r8b := run_with(15)
	r8b.day = 3
	for c in PSortie.cards_for(r8b):
		c.done = true
	r8b.hours = 0
	ok("나갈 수 있는 출격이 없으면 any_departure false(휴식이 강제인지 구분)", not PRun.any_departure(r8b))
	var r8c := run_with(16)
	ok("카드가 남아 있으면 any_departure true(선택해서 쉰 휴식)", PRun.any_departure(r8c))

	# ---------- 지시 9: 사건·제단 ----------
	ok("무료 이득만 있는 보급 사건에는 '지나친다'가 없다", PPacing.event_no_skip("supply") and not PPacing.event_no_skip("merchant") and not PPacing.event_no_skip("weapon_altar"))
	ok("제단 이름이 대상과 효과를 드러낸다: 적 치유 제단 · 소환 제단 · 저주 제단", String(PCatalog.enemy("altar_heal").name) == "적 치유 제단" and String(PCatalog.enemy("altar_reinforce").name) == "소환 제단" and String(PCatalog.enemy("altar_hazard").name) == "저주 제단")
	ok("제단마다 짧은 효과 한 줄(장문 설명 대신)", PPacing.enemy_short("altar_heal").find("파괴하면 멈춤") >= 0 and PPacing.enemy_short("altar_reinforce") != "" and PPacing.enemy_short("altar_hazard") != "")

	# ---------- 지시 15: 통계 ----------
	var stx := PFlow.make_encounter(r1, sortie_of(r1, p1, 1, "t1a_first"))
	stx.note_mod("split", "proc")
	stx.note_mod("split", "hit", 12.5)
	stx.note_mod("returning", "proc")
	var mr := stx.mod_report()
	ok("개조 계측: 발동과 적중을 구분(빗나간 발동은 피해 0으로 남지 않고 hits가 0)", int(mr.split.procs) == 1 and int(mr.split.hits) == 1 and is_equal_approx(float(mr.split.damage), 12.5) and int(mr.returning.procs) == 1 and int(mr.returning.hits) == 0)
	ok("값이 없는 개조는 표에 넣지 않는다(0으로 미발동처럼 보이지 않게)", not mr.has("cross"))
	stx.status = "won"
	PStats.record(r1, stx, { "kind": "sortie", "regionId": p1, "day": 1 })
	var V := PStats.views(r1)
	ok("통계 보기에 최근 전투가 추가되고, 보호막 흡수·회복이 체력 손실과 분리 기록된다", V.has("recent") and (V.all as Dictionary).has("absorbed") and (V.all as Dictionary).has("healed"))
	ok("개조별 이번 런 발동/적중/피해 행", PStats.mod_rows(V.all).size() >= 1 and String(PStats.mod_rows(V.all)[0].id) != "")
	var ver := PStats.verify(r1)
	var all_ok := true
	for v in ver:
		if not bool(v.ok):
			all_ok = false
	ok("통계 산술 검증(출처 합 = 총합, 분류 합 = 총합) 유지", all_ok)

	var fails := results.filter(func(r): return not r[0])
	print("\n%d/%d 통과" % [results.size() - fails.size(), results.size()])
	quit(0 if fails.is_empty() else 1)
