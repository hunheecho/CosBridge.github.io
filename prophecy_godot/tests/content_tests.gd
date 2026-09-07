extends SceneTree
## 반복 콘텐츠 규칙 테스트(headless): 회차 특징·사전 편성·선택형 위험 전투·보스 계획·밀도 세트 선택·Q4 표시 일치.
## 기대값은 사용자 합의 방향(2026-09-07 지시문 §4)과 world.json/missions.json 시험값에서 도출.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func fake_win(run: Dictionary, sortie: Dictionary, hp_left: float = 80.0) -> CombatState:
	var st := PFlow.make_encounter(run, sortie)
	st.spawn_hold = true
	st.step({}, STEP)
	st.status = "won"
	st.player.hp = hp_left
	return st

func _init() -> void:
	var W := PCatalog.world()
	# ---------- 회차 특징 ----------
	var seen := {}
	for s in range(1, 40):
		seen[PRun.pick_world_feature(s)] = true
	ok("회차 특징: 시드에 따라 3종 모두 등장", seen.size() == 3, str(seen.keys()))
	var r1 := PRun.new_run(41, "sword")
	var f1 := PRun.world_feature(r1)
	ok("새 회차에 특징 1개 확정·한 줄 설명 있음", not f1.is_empty() and String(f1.line).length() > 5, str(f1.get("id", "")))
	ok("같은 시드 = 같은 특징(재접속 재추첨 없음: 저장 필드만 읽음)", String(PRun.new_run(41, "sword").worldFeature) == String(r1.worldFeature) and String(PSave.normalize(r1).worldFeature) == String(r1.worldFeature))
	var rm := PRun.new_run(1, "sword")
	rm.worldFeature = "wandering_merchant"
	ok("떠돌이 상인의 해(10일 본편): 방문 상인 1·4·7일차(기본 2·5·8)", PRun.merchant_days(rm).map(func(d): return int(d)) == [1, 4, 7] and PRun.merchant_days(PRun.new_run(1, "sword").merged({ "worldFeature": "misty_season" }, true)).map(func(d): return int(d)) == [2, 5, 8])
	rm.day = 1
	rm.stock = null
	PRun.refresh_stock(rm)
	ok("1일차에 방문 상인이 생성된다(기본 회차는 2·4·6)", rm.merchant != null and int(rm.merchant.day) == 1)
	var rr := PRun.new_run(1, "sword")
	rr.worldFeature = "bounty_year"
	ok("위험한 의뢰의 해: 위험 확률 0.75·보상 ×1.35 (기본 0.5·×1.25)", is_equal_approx(PRun.risk_chance(rr), 0.75) and is_equal_approx(PRun.risk_reward_mult(rr), 1.35) and is_equal_approx(PRun.risk_chance(PRun.new_run(2, "sword").merged({ "worldFeature": "misty_season" }, true)), 0.5))
	var re := PRun.new_run(1, "sword")
	re.worldFeature = "misty_season"
	ok("안개 낀 계절: 보급소·정찰자 가중치 2, 시간의 샘 0(제외), 그 외 1", is_equal_approx(PRun.event_weight(re, "supply"), 2.0) and is_equal_approx(PRun.event_weight(re, "time_spring"), 0.0) and is_equal_approx(PRun.event_weight(re, "merchant"), 1.0))
	var spring := 0
	var rolls := 0
	for s in range(200, 260):
		var r3 := PRun.new_run(s, "sword")
		r3.worldFeature = "misty_season"
		var c3: Dictionary = PSortie.cards_for(r3)[0]
		var s3 := PSortie.start(r3, String(c3.id))
		var ev = PEvents.roll(r3, s3)
		if ev != null:
			rolls += 1
			if String(ev.id) == "time_spring":
				spring += 1
	ok("안개 낀 계절 60시드: 사건은 나오되 시간의 샘은 0회", rolls > 5 and spring == 0, "rolls %d spring %d" % [rolls, spring])
	ok("핵심 일정 불변: 특징이 있어도 관문 4/7/10·하루 5칸·경험치 ×0.3 그대로", int(PRun.next_boss(rr).day) == 4 and int(rr.hours) == 5 and is_equal_approx(PRun.kill_xp_mult(rr), 0.3))
	# ---------- 사전 편성(역할 조합) ----------
	var FS: Dictionary = W.formation_sets
	var missing := []
	for rid in ["forest", "ridge", "marsh", "den", "deep"]:
		for dk in W.day_waves[rid]:
			if rid == "forest" and String(dk) == "1":
				continue
			if (FS[rid] as Dictionary).get(String(dk), []).size() < 2:
				missing.append(rid + ":" + String(dk))
	ok("접근 가능한 모든 지역·날짜 정의에 대안 편성 2개 이상(첫날 숲 제외)", missing.is_empty(), str(missing))
	ok("첫날 숲은 기본 편성만(승인된 첫 전투 고정)", PRun.formation_options("forest", 1).size() == 1)
	ok("숲 2일차 대안: 기본·포위·원거리 호위", PRun.formation_options("forest", 2).map(func(o): return String(o.id)) == ["base", "siege", "escort"])
	var r4 := PRun.new_run(1, "sword")
	var c4: Dictionary = PSortie.cards_for(r4)[0]
	ok("1일차 숲 카드는 기본 편성(0.4.2와 같은 카드 시드 소비)", String(c4.formationId) == "base" and String(c4.regionId) == "forest")
	var s4 := PSortie.start(r4, String(c4.id))
	var st4 := PFlow.make_encounter(r4, s4)
	ok("첫 전투 편성 보존: 새벽 소규모 순찰 늑대 25", (st4.formation.units as Array).size() == 25 and int(st4.formation.godot_counts.wolf) == 25)
	var kinds := {}
	for s in range(300, 340):
		var r5 := PRun.new_run(s, "sword")
		r5.day = 2
		r5.cards = null
		for c in PSortie.cards_for(r5):
			if String(c.regionId) == "forest":
				kinds[String(c.formationId)] = int(kinds.get(String(c.formationId), 0)) + 1
	ok("2일차 숲 카드 40시드: 기본·포위·원거리 호위 모두 등장", kinds.has("base") and kinds.has("siege") and kinds.has("escort"), str(kinds))
	var r6 := PRun.new_run(5, "sword")
	r6.day = 2
	r6.cards = null
	r6.lastFormation = { "forest": "siege" }
	var repeat := false
	for s in range(400, 440):
		var r7 := PRun.new_run(s, "sword")
		r7.day = 2
		r7.cards = null
		r7.lastFormation = { "forest": "siege" }
		for c in PSortie.cards_for(r7):
			if String(c.regionId) == "forest" and String(c.formationId) == "siege":
				repeat = true
	ok("같은 지역의 직전 편성(포위)은 다음 카드에서 제외된다(연속 같은 편성 회피)", not repeat)
	var r8 := PRun.new_run(9, "sword")
	r8.day = 2
	r8.cards = null
	var cf: Dictionary = {}
	for c in PSortie.cards_for(r8):
		if String(c.regionId) == "forest":
			cf = c
	cf.formationId = "escort"
	cf.formationName = "원거리 호위"
	r8.hours = 4 # 아침 출발(새벽 변주의 '마지막 웨이브 없음'을 피해 편성 전체를 본다)
	var s8 := PSortie.start(r8, String(cf.id))
	var w8 := PRun.encounter_waves("forest", false, r8, s8)
	var archers := 0
	var total := 0
	for wave in w8:
		for g in wave:
			total += int(g.n)
			if String(g.type) == "archer":
				archers += int(g.n)
	ok("원거리 호위 편성으로 출격: 궁수 5·합계 11(기본과 같은 합계), 직전 편성 기록", archers == 5 and total == 11 and String(r8.lastFormation.forest) == "escort" and String(s8.formationId) == "escort", "archers %d total %d" % [archers, total])
	# ---------- 선택형 위험 전투(강적의 흔적) ----------
	var r9 := PRun.new_run(12, "sword")
	var c9: Dictionary = PSortie.cards_for(r9)[0]
	var s9 := PSortie.start(r9, String(c9.id))
	PFlow.settle_victory(r9, s9, fake_win(r9, s9, 80.0))
	s9.event = { "id": "challenge", "seed": 5, "resolved": false, "choice": null }
	var opts := PEvents.options(r9, s9)
	var fo: Dictionary = opts[0]
	ok("강적의 흔적 선택지: 맞선다/지나친다, 선택 전에 보상(×1.6)·시간 없음·미정산 손실을 표시", opts.size() == 2 and String(fo.id) == "fight" and String(fo.cost).contains("시간 소모 없음") and String(fo.cost).contains("상실") and String(fo.effect).contains("×1.6"), str(fo))
	r9.hp = 40.0
	ok("체력 50% 미만이면 강적의 흔적이 굴려지지 않는다(유효 조건)", not PEvents._valid("challenge", r9, s9))
	r9.hp = 80.0
	var hours9 := int(r9.hours)
	var res := PEvents.resolve(r9, s9, "fight")
	var fo9 := PEvents.fight_opts(r9, s9)
	var elites := 0
	for wave in fo9.waves:
		for g in wave:
			if String(g.type) == "wolf_alpha":
				elites += int(g.n)
	ok("맞선다: 추가 전투(정예 +2, 등급 1단계 위 = 붉은 40%), 시간 소모 없음", String(res.next) == "fight" and elites == 2 and int(r9.hours) == hours9 and is_equal_approx(float(fo9.tier_mix.get("red", 0.0)), 0.4) and int(fo9.world_stage) == 1, str(fo9.tier_mix))
	var stc := PFlow.make_encounter(r9, s9)
	ok("강적 전투 편성에 붉은 개체가 섞인다(변화 전 회차라도 한 단계 위)", int(stc.formation.tier_counts.get("red", 0)) > 0 and int(stc.formation.tier_counts.get("apex", 0)) == 0, str(stc.formation.tier_counts))
	var gold_before := int(s9.loot.gold)
	stc.spawn_hold = true
	stc.step({}, STEP)
	stc.status = "won"
	stc.player.hp = 60.0
	var rw := PFlow.settle_victory(r9, s9, stc)
	ok("강적 승리: 이번 출격 전리품 ×1.6(반올림), 새 전리품 없음, 지역 3택 보류 1회", int(s9.loot.gold) == int(round(gold_before * 1.6)) and int(rw.gold) == 0 and r9.growth.get("pendingDeepPick", null) != null and bool(s9.eventFightDone), "gold %d → %d" % [gold_before, int(s9.loot.gold)])
	ok("봇 정책: 위험 전략·체력 60% 이상이면 맞선다, 신중은 지나친다", PEvents.bot_choose(r9, { "event": { "id": "challenge" }, "loot": { "gold": 0 } }, "risky") == "fight" and PEvents.bot_choose(r9, { "event": { "id": "challenge" }, "loot": { "gold": 0 } }, "cautious") == "leave")
	# ---------- 보스 계획 ----------
	var r10 := PRun.new_run(3, "sword")
	ok("보스 계획: 관문 3개 후보에서 확정(현재 후보 1개씩 = boss/guardian/eater), 다음 보스는 계획을 따른다", (r10.bossPlan as Array) == ["boss", "guardian", "eater"] and String(PRun.next_boss(r10).id) == "boss" and int(PRun.next_boss(r10).day) == 4)
	r10.bossPlan = ["guardian", "boss", "eater"]
	ok("계획이 바뀌면 다음 보스 id가 바뀌고 관문 날짜·체력 키는 관문 순서를 따른다", String(PRun.next_boss(r10).id) == "guardian" and int(PRun.next_boss(r10).day) == 4 and String(PRun.next_boss(r10).hpKey) == "stage1")
	# ---------- 밀도 세트 선택(비교 회차) ----------
	var rd := PRun.new_run(1, "sword", "", { "density_set": "roles" })
	ok("새 회차 옵션 density_set=roles → run.densitySet", String(rd.densitySet) == "roles")
	var cd: Dictionary = PSortie.cards_for(rd)[0]
	var sd := PSortie.start(rd, String(cd.id))
	var std := PFlow.make_encounter(rd, sd)
	ok("roles 세트라도 첫날 새벽 숲은 늑대 25(늑대 ×5 동일)", (std.formation.units as Array).size() == 25)
	# ---------- Q4: 표시 슬롯 = 실제 출발 슬롯 ----------
	var lst := PRun.slot_variants_list("marsh")
	var evening := false
	for v in lst:
		if int(v.slot) == 4:
			evening = true
	ok("습지 변주 목록에 저녁(4) 없음: 저녁 포자는 오후(3)로 이동한 슬롯으로만 표시", not evening and lst.any(func(v): return int(v.slot) == 3 and v.has("remappedFrom")), str(lst.map(func(v): return [int(v.slot), String(v.name)])))
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
