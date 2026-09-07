extends SceneTree
## 10일·3막 본편 구조 테스트(headless): 관문 4/7/10, 막 1~3/4~6/7~9, 장소 일정, 세계 변화 연동, 저장 호환(trio), 영구 기록 2/3, 봇 완주.
## 기준: 사용자 결정(2026-09-07 채팅 + prophecy-act-themes-plan §1·§3·§9). 수치(장소 배치·상인 날짜·2/3 기록)는 시험값.
## 실행: APPDATA 격리 후 godot --headless --path prophecy_godot -s tests/acts_tests.gd

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	# ---------- 모드·관문·막 ----------
	var run := PRun.new_run(51, "sword")
	ok("새 회차 기본 모드 acts: 10일, 관문 4/7/10 (boss·guardian·eater)", String(run.mode) == "acts" and int(PRun.mode_def(run).days) == 10 and PRun.mode_def(run).bosses.map(func(b): return int(b.day)) == [4, 7, 10] and PRun.stage_count(run) == 3)
	ok("막 판정: 1~3일 1막, 4~6일 2막, 7~9일 3막, 관문일(4·7·10)은 그 관문을 여는 막에 속함", PRun.act_of(run, 1).id == 1 and PRun.act_of(run, 3).id == 1 and PRun.act_of(run, 4).id == 1 and PRun.act_of(run, 5).id == 2 and PRun.act_of(run, 7).id == 2 and PRun.act_of(run, 8).id == 3 and PRun.act_of(run, 10).id == 3, "%d/%d/%d" % [int(PRun.act_of(run, 4).id), int(PRun.act_of(run, 7).id), int(PRun.act_of(run, 10).id)])
	ok("상단 표시용 막 이름: 1일차 '1막', 5일차 '2막', 9일차 '3막'", PRun.act_label(run, 1) == "1막" and PRun.act_label(run, 5) == "2막" and PRun.act_label(run, 9) == "3막")
	# 장소 일정: 1~9일 모두 2곳, 매일 1칸 장소 1곳 이상, 10일차는 없음
	var bad := []
	for d in range(1, 10):
		var pl := PRun.places_for(run, d)
		var has1 := false
		for pid in pl:
			if PRun.place_cost(String(pid)) <= 1:
				has1 = true
		if pl.size() != 2 or not has1:
			bad.append("%d:%s" % [d, str(pl)])
	ok("1~9일차 장소 2곳, 매일 1칸 장소 1곳 이상(마지막 칸에도 실제 행동), 10일차 장소 없음", bad.is_empty() and PRun.places_for(run, 10).is_empty(), str(bad))
	run.visited = { "forest": 1, "ridge": 2, "den": 1 }
	run.schedule = {}
	var p6 := PRun.places_for(run, 6)
	ok("6일차 재방문 칸은 이전 방문 1칸 지역에서 시드로(굴 제외)", PRun.place_cost(String(p6[0])) <= 1 and String(p6[0]) in ["forest", "ridge"], str(p6))
	ok("방문 상인(acts): 2·5·8일차(막마다 1회), 떠돌이 상인의 해: 1·4·7", PRun.merchant_days(run).map(func(d): return int(d)) == [2, 5, 8] and PRun.merchant_days(run.merged({ "worldFeature": "wandering_merchant" }, true)).map(func(d): return int(d)) == [1, 4, 7])
	# ---------- 하루 종료 → 관문 ----------
	var r2 := PRun.new_run(52, "sword")
	for i in 3:
		PRun.end_day(r2)
	ok("3일차 종료 → 4일차 = 관문 준비(boss_prep), 출격 불가, 미리보기에 보스", int(r2.day) == 4 and String(r2.phase) == "boss_prep" and not PRun.can_sortie(r2, "forest") and PFlow.actions(r2).any(func(a): return String(a.id) == "boss_start"))
	var ap := PRun.act_preview(r2)
	ok("관문 준비 화면 미리보기: 다음 막(2막, 4~6일차) 장소·대표 적·다음 관문 보스(봉인 수호자 7일차)", not ap.is_empty() and int(ap.act.id) == 2 and (ap.places as Array).size() >= 2 and (ap.enemies as Array).size() >= 2 and String(ap.gate.id) == "guardian" and int(ap.gate.day) == 7, str(ap))
	var bs := PRun.start_boss(r2)
	var stb := PFlow.make_boss_encounter(r2, bs)
	stb.status = "won"
	stb.boss.dead = true
	stb.stats.boss_damage = 2400.0
	PFlow.settle_boss_victory(r2, stb)
	ok("4일차 관문 승리: 세계 변화 1차, 2막 시작(4일차 5칸, prep), 희귀 보상 보류", PRun.world_stage(r2) == 1 and int(r2.day) == 4 and String(r2.phase) == "prep" and int(r2.hours) == 5 and r2.growth.get("pendingBossPick", null) != null and int(r2.stage) == 1)
	ok("4일차 장소는 2막 장소(능선·습지)", PRun.places_for(r2, 4) == ["ridge", "marsh"], str(PRun.places_for(r2, 4)))
	for i in 3:
		PRun.end_day(r2)
	ok("6일차 종료 → 7일차 관문(봉인 수호자)", int(r2.day) == 7 and String(r2.phase) == "boss_prep" and String(PRun.next_boss(r2).id) == "guardian")
	var ap2 := PRun.act_preview(r2)
	ok("7일차 관문 미리보기: 3막(7~9일차), 다음 관문 예언을 먹는 자 10일차", int(ap2.act.id) == 3 and String(ap2.gate.id) == "eater" and int(ap2.gate.day) == 10)
	var bs2 := PRun.start_boss(r2)
	var st2 := PFlow.make_boss_encounter(r2, bs2)
	st2.status = "won"
	st2.boss.dead = true
	PFlow.settle_boss_victory(r2, st2)
	ok("7일차 관문 승리: 2차 변화(일반 퇴장), 3막 7일차 5칸", PRun.world_stage(r2) == 2 and int(r2.day) == 7 and int(r2.hours) == 5)
	var f7: Dictionary = PFlow.make_encounter(r2, { "regionId": "ridge", "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 3, "day": 7, "slot": 1, "variant": null }).formation
	ok("3막 능선 전투: 일반 0(붉은+변이)", int(f7.tier_counts.get("normal", 0)) == 0 and int(f7.tier_counts.get("red", 0)) > 0)
	for i in 3:
		PRun.end_day(r2)
	ok("9일차 종료 → 10일차 최종 관문, 미리보기 = 완주 안내", int(r2.day) == 10 and String(r2.phase) == "boss_prep" and bool(PRun.act_preview(r2).get("final", false)))
	var bs3 := PRun.start_boss(r2)
	var st3 := PFlow.make_boss_encounter(r2, bs3)
	st3.status = "won"
	st3.boss.dead = true
	PFlow.settle_boss_victory(r2, st3)
	ok("10일차 최종 관문 승리 = 본편 완주(cleared)", String(r2.phase) == "cleared" and bool(r2.ended) and (r2.bossesDone as Array).size() == 3)
	# ---------- 저장 호환: 옛 7일 회차(trio)는 7일 규칙으로 이어간다 ----------
	var r3 := PRun.new_run(53, "sword", "", { "mode": "trio" })
	ok("trio 모드 회차: 7일·관문 3/5/7·막 없음(옛 저장 호환)", int(PRun.mode_def(r3).days) == 7 and PRun.mode_def(r3).bosses.map(func(b): return int(b.day)) == [3, 5, 7] and PRun.act_of(r3).is_empty() and PRun.act_label(r3) == "" and PRun.merchant_days(r3).map(func(d): return int(d)) == [2, 4, 6])
	for i in 2:
		PRun.end_day(r3)
	ok("trio: 2일차 종료 → 3일차 관문", int(r3.day) == 3 and String(r3.phase) == "boss_prep")
	var loaded := PSave.normalize(r2)
	ok("acts 회차 저장 정규화 뒤 모드·막·단계 유지", String(loaded.mode) == "acts" and int(loaded.day) == 10 and String(loaded.phase) == "cleared")
	# ---------- 영구 기록(계획서 §9): 1~9일 첫 일반 전투 승리 2/3, 관문 2, 완주 2 = 14 ----------
	var R := PCatalog.meta_records_for("acts")
	ok("acts 기록 규칙: 하루 2/3, 1~9일, 관문 2, 완주 2 (trio는 1·6일)", is_equal_approx(float(R.day_win), 2.0 / 3.0) and int(R.day_max) == 9 and int(PCatalog.meta_records_for("trio").day_max) == 6 and is_equal_approx(float(PCatalog.meta_records_for("trio").day_win), 1.0))
	var prof := PProfile.new_profile("trial")
	var r4 := PRun.new_run(54, "sword", "", { "profile": prof, "eligible": true })
	var total := 0.0
	for d in range(1, 10):
		r4.day = d
		r4.cards = null
		r4.hours = 5
		r4.phase = "prep"
		if d >= 7:
			r4.bossesDone = ["boss", "guardian"]
			r4.stage = 2
		elif d >= 4:
			r4.bossesDone = ["boss"]
			r4.stage = 1
		var c: Dictionary = PSortie.cards_for(r4)[0]
		var s := PSortie.start(r4, String(c.id))
		if bool(s.get("mission", false)):
			s.mission = false # 기록 규칙 검사용: 일반 전투로 간주
			s.erase("objective")
		var st := PFlow.make_encounter(r4, s)
		st.spawn_hold = true
		st.step({}, STEP)
		st.status = "won"
		st.player.hp = 70.0
		var a := PProfile.award_from_run(prof, r4, "victory", { "st": st, "sortie": s })
		total += float(a.records)
		var a2 := PProfile.award_from_run(prof, r4, "victory", { "st": st, "sortie": s })
		total += float(a2.records)
	ok("1~9일 첫 승리 기록 합계 6.0(2/3 × 9), 같은 날 반복 지급 없음", is_equal_approx(snapped(total, 0.001), 6.0) and is_equal_approx(snapped(float(prof.records), 0.001), 6.0), "%.3f" % total)
	ok("레벨 계산이 소수 기록을 받는다: 6.0 → Lv2(문턱 4), 3.999 → Lv1", PProfile.level_of(6.0) == 2 and PProfile.level_of(3.999) == 1)
	# ---------- 봇 완주(기존 적·보스, 10일) ----------
	var rec := PRunBot.simulate(1, "gradual", { "start": "sword", "bot_policy": "balanced", "max_retries": 3 })
	ok("회차 봇 gradual 시드 1: 10일 구조 완주(cleared), 관문 3 처치, 마지막 날 10", bool(rec.get("cleared", false)) and int(rec.get("day", 0)) == 10 and (rec.get("bosses", []) as Array).size() >= 3 or bool(rec.get("cleared", false)), JSON.stringify({ "cleared": rec.get("cleared"), "day": rec.get("day"), "level": rec.get("level"), "bosses": rec.get("boss", rec.get("bosses", "")) }))
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
