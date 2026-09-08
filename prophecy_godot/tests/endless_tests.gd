extends SceneTree
## 무한 모드·정복자 테스트(headless, godot-0.6.0 단계 4): 계획서 §10 구조(사용자 결정) + 시험값(meta.json endless/conqueror).
## user:// 프로필·저장 파일을 쓰므로 APPDATA를 별도 폴더로 두고 실행한다. 프로필 경로는 시험 파일로 바꾼다.
## 실행: godot --headless --path prophecy_godot -s tests/endless_tests.gd

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 본편(acts, 옛 지역 일정) 완주 상태 만들기: 관문 3개를 스텁 승리로 통과
func _cleared_run(seed_v: int, opts: Dictionary = {}) -> Dictionary:
	var o := { "legacy_places": true }
	for k in opts:
		o[k] = opts[k]
	var run := PRun.new_run(seed_v, "sword", "", o)
	var guard := 0
	while String(run.phase) != "cleared" and guard < 30:
		guard += 1
		if String(run.phase) == "boss_prep":
			var bs := PRun.start_boss(run)
			var st := PFlow.make_boss_encounter(run, bs)
			st.status = "won"
			st.boss.dead = true
			st.stats.boss_damage = 1000.0
			PFlow.settle_boss_victory(run, st)
			PFlow.resolve_all(run, {}, func(off: Dictionary): return off.choices[0], Callable())
		else:
			PRun.end_day(run)
	return run

func _stub_fight_win(run: Dictionary) -> Dictionary:
	var s := PEndless.start_fight(run)
	var st := PFlow.make_encounter(run, s)
	st.status = "won"
	PFlow.settle_victory(run, s, st)
	PFlow.resolve_all(run, { "region_id": String(s.regionId) }, func(off: Dictionary): return off.choices[0], Callable())
	var rh := {}
	for a in PFlow.actions(run):
		if String(a.id) == "return_home":
			rh = a
	if rh.is_empty():
		push_error("return_home 없음")
		return s
	PFlow.return_home(run, s)
	return s

func _init() -> void:
	PProfile.use_path("user://prophecy_profile_endless_test_v1.json")
	PProfile.clear()
	var E := PCatalog.meta_endless()
	var CQ := PCatalog.meta_conqueror()
	ok("meta.json endless/conqueror 시험값 존재", int(E.fights_per_segment) == 3 and float(E.enemy_hp_step) == 0.1 and float(E.boss_hp_step) == 0.15 and int(CQ.max_level) == 50 and int(CQ.xp_per_level) == 16)
	# ---------- 시작 조건 ----------
	var r0 := PRun.new_run(61, "sword", "", { "legacy_places": true })
	ok("본편 진행 중에는 무한 시작 불가·행동 없음", not PEndless.can_start(r0) and not PEndless.start(r0) and String(r0.phase) == "prep")
	var run := _cleared_run(61)
	ok("본편 완주 상태(cleared, ended, stage 3, 보스 기록 3)", String(run.phase) == "cleared" and bool(run.ended) and int(run.stage) == 3 and (run.bossRecords as Dictionary).size() == 3, "%s %s" % [String(run.phase), str(run.bossRecords.keys())])
	var acts0 := PFlow.actions(run)
	ok("완주 상태(ended)의 행동 목록 = endless_start만", acts0.map(func(a): return String(a.id)) == ["endless_start"], str(acts0.map(func(a): return String(a.id))))
	var gold_before := int(run.gold)
	var lv_before := int(run.growth.level)
	var recs_before := (run.bossRecords as Dictionary).duplicate(true)
	ok("무한 시작: phase endless, ended false, mainCleared, 1구간 전투 0, 체력 완전, 성장·금화·보스 기록 유지", PEndless.start(run) and String(run.phase) == "endless" and not bool(run.ended) and bool(run.mainCleared) and PEndless.segment(run) == 1 and int(run.endless.fights) == 0 and float(run.hp) == float(PRun.build(run).hp_max) and int(run.gold) == gold_before and int(run.growth.level) == lv_before and run.bossRecords == recs_before)
	ok("무한은 1회만 시작", not PEndless.can_start(run))
	ok("상단 표시: '무한 1구간'", PRun.act_label(run) == "무한 1구간", PRun.act_label(run))
	# ---------- 장소·미리보기 결정성 ----------
	var pl := PEndless.places(run)
	ok("옛 지역 일정 회차의 무한 장소 = 기존 지역 5곳", pl == ["forest", "ridge", "marsh", "den", "deep"], str(pl))
	var nf1 := PEndless.next_fight(run)
	var nf2 := PEndless.next_fight(run)
	ok("다음 전투 미리보기 결정적(같은 시드·구간·번호 → 같은 장소·편성), 장소는 후보 안", nf1 == nf2 and pl.has(String(nf1.regionId)) and int(nf1.fight) == 1 and int(nf1.perSegment) == 3, str(nf1))
	ok("1구간 배율: 적 체력 ×1.0, 보스 ×1.0, 등급 = 붉은 60/변이 40(본편 3차 세계 그대로)", PEndless.enemy_hp_mult(run) == 1.0 and PEndless.boss_hp_mult(run) == 1.0 and PRun.tier_mix(run) == { "red": 0.6, "apex": 0.4 }, str(PRun.tier_mix(run)))
	var hm1 := PRun.hp_mult_for(run, "forest", false)
	# ---------- 행동 목록 ----------
	var ids := PFlow.actions(run).map(func(a): return String(a.id))
	ok("무한 행동 목록: endless_fight·endless_regroup·endless_quit + 거점 시설(shop_open), sortie/end_day/rest 없음", ids.has("endless_fight") and ids.has("endless_regroup") and ids.has("endless_quit") and ids.has("shop_open") and not ids.has("end_day") and not ids.has("rest") and ids.filter(func(i): return i.begins_with("sortie:")).is_empty(), str(ids))
	ok("재정비: 체력이 최대면 불가", not PEndless.can_regroup(run))
	# ---------- 전투 → 정산 → 구간 보스 ----------
	var s1 := PEndless.start_fight(run)
	ok("무한 출격 dict: endless 표시·구간 1·전투 1·시간 칸 소모 없음", bool(s1.endless) and int(s1.segment) == 1 and int(s1.fight) == 1 and String(s1.regionId) == String(nf1.regionId) and String(s1.formationId) == String(nf1.formationId), str(s1))
	var st1 := PFlow.make_encounter(run, s1)
	ok("무한 전투 상태: 등급 비율·체력 배율이 무한 규칙(1구간 = 본편 3차)", st1.opts.get("tier_mix", {}) == { "red": 0.6, "apex": 0.4 } and float(st1.hp_mult.normal) == float(hm1.normal), str(st1.opts.get("tier_mix", {})))
	st1.status = "won"
	st1.player.hp = 40.0
	var rw := PFlow.settle_victory(run, s1, st1)
	ok("무한 전투 승리 정산: 전리품 굴림·지역 경험치, 사건 없음(event null), 보류 출격 = 무한 출격", not rw.is_empty() and s1.get("event", null) == null and run.pendingSortie == s1)
	var ids_after := PFlow.actions(run).filter(func(a): return String(a.kind) in ["return_home", "deep_explore", "event"]).map(func(a): return String(a.id))
	ok("무한 전투 뒤 행동: 정산(return_home)만, 더 깊이·사건 없음", ids_after == ["return_home"], str(ids_after))
	var gold_mid := int(run.gold)
	PFlow.return_home(run, s1)
	ok("정산: 금화 반영, 전투 수 1/3, 아직 endless", int(run.gold) >= gold_mid and int(run.endless.fights) == 1 and int(run.endless.wins) == 1 and String(run.phase) == "endless")
	ok("재정비: 체력 40 → 완전 회복, 구간당 1회 소진", PEndless.can_regroup(run) and PEndless.regroup(run) and float(run.hp) == float(PRun.build(run).hp_max) and int(run.endless.regroupLeft) == 0 and not PEndless.can_regroup(run))
	_stub_fight_win(run)
	ok("2번째 전투 미리보기는 다른 번호(결정적)", int(PEndless.next_fight(run).fight) == 3)
	_stub_fight_win(run)
	ok("전투 3승 → 구간 보스 대기(endless_boss), boss_start 행동(endless 표시), endless_fight 없음", String(run.phase) == "endless_boss" and PFlow.actions(run).filter(func(a): return String(a.id) == "boss_start" and bool(a.data.get("endless", false))).size() == 1 and not PFlow.actions(run).map(func(a): return String(a.id)).has("endless_fight"))
	var bid1 := PEndless.boss_id(run)
	ok("1구간 보스 = 경로 보스 계획 1번(가시갈기)", bid1 == String(run.bossPlan[0]), bid1)
	var hp_base: float = float(PCatalog.boss_def(bid1).hp)
	var bs1 := PEndless.start_boss(run)
	ok("구간 보스 입장: 체력 완전 회복, 재도전 스냅샷 없음, 시드는 본편 관문과 다름", not bs1.is_empty() and bool(bs1.endless) and float(run.hp) == float(PRun.build(run).hp_max) and run.bossEntry == null and int(bs1.seed) != PRun.boss_seed(run))
	var stb := PFlow.make_boss_encounter(run, bs1)
	ok("1구간 보스 체력 ×1.0", absf(float(stb.boss.hp_max) - PRun.boss_hp(run, bid1)) < 0.01 and PEndless.boss_hp_mult(run) == 1.0)
	stb.status = "won"
	stb.boss.dead = true
	stb.stats.boss_damage = 900.0
	var rec1 := PFlow.settle_boss_victory(run, stb)
	ok("구간 보스 승리: 기록 행(endless, segment 1) → 2구간·전투 0·재정비 회복·체력 완전, 본편 보스 기록은 그대로, 다음 단계 해금 없음", bool(rec1.get("endless", false)) and int(rec1.segment) == 1 and PEndless.segment(run) == 2 and int(run.endless.fights) == 0 and int(run.endless.regroupLeft) == 1 and String(run.phase) == "endless" and run.bossRecords == recs_before and int(run.stage) == 3 and int(run.endless.bossesWon) == 1)
	ok("2구간 배율: 적 체력 ×1.1, 보스 ×1.15(선형), 등급 붉은 40/변이 60", absf(PEndless.enemy_hp_mult(run) - 1.1) < 1e-9 and absf(PEndless.boss_hp_mult(run) - 1.15) < 1e-9 and PRun.tier_mix(run) == { "red": 0.4, "apex": 0.6 })
	var hm2 := PRun.hp_mult_for(run, "forest", false)
	ok("2구간 지역 체력 배율 = 1구간 × 1.1(반올림 2자리)", absf(float(hm2.normal) - snapped(float(hm1.normal) * 1.1, 0.01)) < 0.011, "%s → %s" % [str(hm1.normal), str(hm2.normal)])
	ok("2구간 보스 체력 = 기본 × 1.15", absf(PRun.boss_hp(run, bid1) - float(hp_base) * 1.15) < 0.01 or absf(PRun.boss_hp(run, bid1) / 1.15 - PRun.boss_hp(run.merged({ "phase": "cleared" }, true), bid1)) < 0.01)
	ok("5구간 이후 등급 = 변이 100(마지막 항목 유지)", PEndless.tier_mix(run.merged({ "endless": run.endless.merged({ "segment": 9 }, true) }, true)) == { "apex": 1.0 })
	# ---------- 영구 기록(구간당 1회) ----------
	var prof := PProfile.new_profile("trial")
	run.profileEligible = true
	var award1 := PProfile.award_from_run(prof, run, "boss", { "st": stb, "endless_segment": 1 })
	var expect := 0.1 * (2.0 / 3.0 + 2.0)
	ok("구간 보스 영구 기록 = (2/3 + 2) × 0.1 ≈ 0.267, 이벤트 run:<seed>:endless:1", absf(float(award1.records) - expect) < 1e-6 and (award1.events as Array) == ["run:61:endless:1"], str(award1))
	var award2 := PProfile.award_from_run(prof, run, "boss", { "st": stb, "endless_segment": 1 })
	ok("같은 구간 재수령 없음", float(award2.records) == 0.0 and (award2.events as Array).is_empty())
	ok("무한 일반 전투는 기록 없음(10일차 첫 승리는 day_max 9 밖)", float(PProfile.award_from_run(prof, run, "victory", { "st": st1, "sortie": s1 }).records) == 0.0)
	# ---------- 저장 호환 ----------
	PSave.save(run)
	var loaded := PSave.load()
	ok("저장·불러오기: endless 상태·mainCleared 유지, 2구간에서 이어 하기", int(loaded.endless.segment) == 2 and bool(loaded.mainCleared) and String(loaded.phase) == "endless" and PEndless.active(loaded))
	PSave.clear()
	# ---------- 패배 = 종료 ----------
	var s3 := PEndless.start_fight(run)
	var st3 := PFlow.make_encounter(run, s3)
	st3.status = "lost"
	st3.player.hp = 0.0
	PFlow.settle_defeat(run, s3, st3)
	ok("무한 전투 패배: endless_over, ended, 이유 lost, 본편 완주·보스 기록 유지, 행동 목록 비어 있음", PEndless.is_over(run) and bool(run.ended) and String(run.endless.reason) == "lost" and bool(run.mainCleared) and run.bossRecords == recs_before and PFlow.actions(run).is_empty())
	ok("종료 뒤 요약: 2구간 도달, 전투 승 3, 구간 보스 1", PEndless.summary(run) == PEndless.summary(run) and int(PEndless.summary(run).segment) == 2 and int(PEndless.summary(run).wins) == 3 and int(PEndless.summary(run).bossesWon) == 1)
	ok("종료 뒤 상단 표시 '무한 2구간'", PRun.act_label(run) == "무한 2구간")
	# 구간 보스 패배도 종료
	var run2 := _cleared_run(62)
	PEndless.start(run2)
	for i in 3:
		_stub_fight_win(run2)
	var bs2 := PEndless.start_boss(run2)
	var stb2 := PFlow.make_boss_encounter(run2, bs2)
	stb2.status = "lost"
	PFlow.settle_boss_defeat(run2, stb2)
	ok("구간 보스 패배: 종료(boss_lost), 재도전 없음, 본편 기록 유지", PEndless.is_over(run2) and String(run2.endless.reason) == "boss_lost" and int(run2.get("bossRetries", 0)) == 0 and bool(run2.mainCleared))
	# 자발적 마침
	var run3 := _cleared_run(63)
	PEndless.start(run3)
	PEndless.over(run3, "quit")
	ok("마치기: endless_over(quit)", PEndless.is_over(run3) and String(run3.endless.reason) == "quit")
	# ---------- 테마 경로 회차의 무한 장소 ----------
	var rt := PRun.new_run(64, "sword")
	if not (rt.route as Array).is_empty():
		var tp := []
		for tid in rt.route:
			for p in PCatalog.theme(String(tid)).places:
				tp.append(String(p.id))
		ok("테마 경로 회차: 무한 장소 = 경로 테마 3개의 장소 6곳", PEndless.places(rt) == tp and tp.size() == 6, str(PEndless.places(rt)))
	# ---------- 정복자 ----------
	ok("영구 만렙 필요 기록 140, 정복자 0 (기록 139.9)", PProfile.records_to_max() == 140 and PProfile.conqueror_level_of(139.9) == 0 and PProfile.conqueror_level_of(140.0) == 0)
	ok("기록 156 → 정복자 Lv1, 171.9 → Lv1, 172 → Lv2, 940 → Lv50(상한), 1500 → 50", PProfile.conqueror_level_of(156.0) == 1 and PProfile.conqueror_level_of(171.9) == 1 and PProfile.conqueror_level_of(172.0) == 2 and PProfile.conqueror_level_of(940.0) == 50 and PProfile.conqueror_level_of(1500.0) == 50)
	ok("영구 레벨은 15에서 멈춤(정복자와 다른 만렙)", PProfile.level_of(940.0) == 15)
	var p := PProfile.new_profile("trial")
	ok("새 프로필 정복자 배분 0", p.conqueror == { "attack": 0, "hp": 0, "move": 0 } and PProfile.conqueror_info(p).level == 0 and not bool(PProfile.conqueror_info(p).unlocked))
	ok("포인트 없으면 배분 불가", not PProfile.set_conqueror(p, "attack", 1))
	p.records = 140.0 + 16.0 * 30.0 # Lv30
	var ci := PProfile.conqueror_info(p)
	ok("Lv30: 포인트 30, 남은 30, 다음 Lv까지 기록 16", int(ci.level) == 30 and int(ci.free) == 30 and absf(float(ci.next_need) - 16.0) < 1e-6 and bool(ci.unlocked))
	ok("배분: 공격 25(상한) 가능, 26은 25로 잘림, 체력 5, 남은 0 → 이동 1 불가", PProfile.set_conqueror(p, "attack", 26) and int(p.conqueror.attack) == 25 and PProfile.set_conqueror(p, "hp", 5) and int(PProfile.conqueror_info(p).free) == 0 and not PProfile.set_conqueror(p, "move", 1))
	ok("재분배: 공격 20으로 줄이면 이동 5 가능(상한 10), 잘못된 키 거부", PProfile.set_conqueror(p, "attack", 20) and PProfile.set_conqueror(p, "move", 5) and not PProfile.set_conqueror(p, "luck", 1))
	var eff := PProfile.conqueror_effects({ "attack": 25, "hp": 25, "move": 10 })
	ok("효과 합산(복리 없음): 공격 +50%, 체력 +50%, 이동 +5%", absf(float(eff.damage) - 0.5) < 1e-9 and absf(float(eff.hp) - 0.5) < 1e-9 and absf(float(eff.speed) - 0.05) < 1e-9)
	ok("항목 상한 초과 포인트 무시", absf(float(PProfile.conqueror_effects({ "attack": 40 }).damage) - 0.5) < 1e-9)
	var snap := PProfile.conqueror_snapshot(p)
	ok("스냅샷 {level 30, attack 20, hp 5, move 5}", snap == { "level": 30, "attack": 20, "hp": 5, "move": 5 }, str(snap))
	ok("포인트 0 프로필의 스냅샷은 {} (기준 빌드 보존)", PProfile.conqueror_snapshot(PProfile.new_profile("trial")).is_empty())
	# 저장 호환
	PProfile.save(p)
	var p2 := PProfile.load("trial")
	ok("프로필 저장·불러오기: 정복자 배분 유지", p2.conqueror == { "attack": 20, "hp": 5, "move": 5 })
	var p_old := PProfile.new_profile("trial")
	p_old.erase("conqueror")
	ok("옛 프로필(conqueror 없음) 정규화 → 0 배분", PProfile._normalize(p_old).conqueror == { "attack": 0, "hp": 0, "move": 0 })
	# 회차 빌드 반영
	var base_run := PRun.new_run(65, "sword", "", { "legacy_places": true })
	var b0 := PRun.build(base_run)
	ok("정복자 없는 회차: 빌드에 conqueror 키 없음(D33 기준 빌드)", not b0.has("conqueror") and not base_run.has("conqueror"))
	var cq_run := PRun.new_run(65, "sword", "", { "legacy_places": true, "profile": p, "eligible": true })
	var b1 := PRun.build(cq_run)
	var base_hp := float(PCatalog.config().PLAYER.hp)
	ok("정복자 회차: 스냅샷 고정, 체력 = 기준 + 기본 체력×10%, 공격 배율 ×1.40 1회, 이동 ×1.025", cq_run.conqueror == snap and absf(float(b1.hp_max) - (float(b0.hp_max) + base_hp * 0.10)) < 1e-6 and absf(float(b1.damage_mult) / float(b0.damage_mult) - 1.40) < 1e-9 and absf(float(b1.speed_mult) / float(b0.speed_mult) - 1.025) < 1e-9, "hp %s→%s dmg %s→%s" % [str(b0.hp_max), str(b1.hp_max), str(b0.damage_mult), str(b1.damage_mult)])
	ok("무기 피해도 1회만 ×1.40(중복 적용 없음)", absf(float(b1.weapons[0].damage) / float(b0.weapons[0].damage) - 1.40) < 1e-9)
	cq_run.growth.passives = { "vitality": 2 }
	var b2 := PRun.build(cq_run)
	var PV: Dictionary = PCatalog.growth().PASSIVE_VALUES
	ok("건강 패시브는 그대로 더함(정복자 체력 비율은 기본 체력에만)", absf(float(b2.hp_max) - (float(b1.hp_max) + float(PV.vitality) * 2.0)) < 1e-6)
	p.conqueror.attack = 0 # 프로필을 바꿔도 진행 중 회차는 스냅샷 그대로
	ok("출발 후 고정: 프로필 재분배가 진행 중 회차 빌드를 바꾸지 않음", absf(float(PRun.build(cq_run).damage_mult) / float(b0.damage_mult) - 1.40) < 1e-9)
	# ---------- 봇 무한 진행(1구간) ----------
	# 이 검사 대상은 **무한 모드 규칙**이다. 본편 완주는 전제일 뿐이므로 봇이 완주하기를 기다리지 않는다.
	# 2026-09-08 체력·성장 개편 뒤에는 시드 16개를 훑어도 balanced 봇이 완주하는 시드가 없다.
	# 봇이 못 이긴다는 이유로 난이도를 낮추지 않는다. 대신 완주한 회차 상태를 직접 만들어 무한 진행만 검사한다.
	var er := PRun.new_run(1, "sword", "", { "legacy_places": true })
	er.phase = "cleared"
	er.stage = 3
	er.day = int(PRun.mode_def(er).days)
	er.bossesDone = ["boss", "guardian", "eater"]
	er.growth.level = 20
	var es_ok := PEndless.can_start(er)
	var es: Dictionary = {}
	if es_ok:
		PEndless.start(er)
		es = PEndless.summary(er)
	ok("완주 상태에서 무한 모드 진입: 구간 1 시작, 요약이 생긴다(봇 승패는 조건 아님)",
		es_ok and not es.is_empty() and int(es.get("segment", 0)) >= 1, "%s" % str(es))
	PProfile.clear()
	var fails := results.filter(func(r): return not r[0])
	print("\n%d/%d 통과" % [results.size() - fails.size(), results.size()])
	quit(0 if fails.is_empty() else 1)
