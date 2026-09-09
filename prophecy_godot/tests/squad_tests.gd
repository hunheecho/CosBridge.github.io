extends SceneTree
## 분대 편성·협공·특수 정예 결투 규칙 검사(headless).
##
## 무엇을 못박는가
##   ① 테마마다 **행동 목적이 다른 협공 3개**가 있고 주역·비중·함께 나오는 적이 서로 다르다
##   ② 등장 단위가 **분대**다(앞에서 접근 / 뒤에서 지원 / 측면·시간차) — 지원만 있는 분대를 만들지 않는다
##   ③ 다음 분대가 앞 분대의 전멸을 기다리지 않고 **겹쳐** 들어간다 · 종류 상한 때문에 막히지 않는다
##   ④ 총 등장 수·경험치 예산이 개편 전과 **같다** · 시드·저장이 같으면 편성이 재현된다
##   ⑤ 일반 전투가 끝난 뒤 대기열에서 적이 뒤늦게 나오지 않는다
##   ⑥ **특수 정예 결투**: 전환 조건 · 일반 증원 0 · 고유 소환 귀속과 상한 · 처치 순서 · 정산 1회
##
## 여기 있는 수치는 **시험값**이며 사람이 승인한 균형값이 아니다. 봇 승패는 통과 조건이 아니다.
## 재미(편성이 실제로 재미있는가)는 이 검사로 확인되지 않는다 — 그것은 사람이 보는 항목이다.
## 실행: python tools/run_suites.py --suites squad_tests --jobs 1

const STEP := 1.0 / 120.0
const MAX_SEC := 240.0
const DAY_OF_ACT := { 1: 1, 2: 5, 3: 9 }

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func make_run(seed_v: int, act: int, theme_id: String) -> Dictionary:
	var route := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)]
	route[act - 1] = theme_id
	var run := PRun.new_run(seed_v, "sword", "", { "route": route })
	run.day = int(DAY_OF_ACT[act])
	run.stage = act - 1
	return run

func sortie_of(place_id: String, formation_id: String, seed_v: int, duel_type: String = "") -> Dictionary:
	return { "regionId": place_id, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 },
		"encounters": 0, "seed": seed_v, "day": 1, "slot": 0, "variant": null,
		"formationId": formation_id, "duelType": duel_type }

func encounter(run: Dictionary, place_id: String, formation_id: String, seed_v: int, duel_type: String = "", no_squad: bool = false) -> CombatState:
	var o := PFlow.encounter_opts(run, sortie_of(place_id, formation_id, seed_v, duel_type))
	if no_squad: # 대조군: 분대 편성을 끄고 옛 순서(비례 섞기)로 만든다
		(o.density as Dictionary).erase("squad")
	return CombatState.new(o)

## 전투를 끝까지(또는 제한 시간까지) 돌린다. 계측 전용으로 플레이어는 죽지 않는다
func play(st: CombatState, sec: float = MAX_SEC) -> Dictionary:
	var bot := PBot.new("balanced")
	var n := 0
	var limit := int(sec / STEP)
	var late_spawn := 0     # 일반 전투 종료(spawned_all) 뒤에 늘어난 등장 수
	var spawned_all_at := -1
	var support_only := 0.0
	while st.status == "running" and n < limit:
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		n += 1
		if bool(st.spawned_all):
			if spawned_all_at < 0:
				spawned_all_at = int(st.spawn_count)
			elif int(st.spawn_count) > spawned_all_at:
				late_spawn += int(st.spawn_count) - spawned_all_at
				spawned_all_at = int(st.spawn_count)
	if st.status == "running":
		st.delayed.clear()
	support_only = float(st.stats.support_only_sec)
	return { "status": String(st.status), "sec": float(st.t), "late_spawn": late_spawn, "support_only": support_only }

## 이 웨이브의 전투 경험치 예산(XP_VALUE 단위). PFormation.from_waves 와 같은 산식이다:
## budget_from 이 있는 개체(일반 정예·결투 상대)는 **자리를 대신한 종류의 단위값**으로 센다
func wave_budget(waves: Array) -> float:
	var XPV: Dictionary = PCatalog.growth().XP_VALUE
	var s := 0.0
	for wave in waves:
		for g in wave:
			var u: float = float(XPV.get(String(g.type), 5.0))
			var ref: float = float(g.get("ref", float(g.n)))
			if g.has("budget_from"):
				u = float(XPV.get(String(g.budget_from), 5.0))
			s += u * ref
	return s

func wave_count(waves: Array) -> int:
	var n := 0
	for wave in waves:
		for g in wave:
			n += int(g.n)
	return n

func lead_pair(f: Dictionary) -> String:
	var comp: Array = (f.comp as Array).duplicate()
	comp.sort_custom(func(a, b): return float(a.share) > float(b.share))
	var out := []
	for i in mini(2, comp.size()):
		out.append(String(comp[i].type))
	return "+".join(out)

func _init() -> void:
	var T := PCatalog.themes()

	# ================= 1. 테마별 대표 협공 3개 =================
	var same_goal := []
	var same_pair := []
	var no_kind := []
	var one_kind := []
	for tid in T:
		var t: Dictionary = T[tid]
		var goals := {}
		var pairs := {}
		var kinds := {}
		for f in (t.formations.normal as Array):
			var g := String(f.get("goal", ""))
			if g == "" or goals.has(g):
				same_goal.append("%s/%s" % [tid, String(f.id)])
			goals[g] = true
			var p := lead_pair(f)
			if pairs.has(p):
				same_pair.append("%s/%s(%s)" % [tid, String(f.id), p])
			pairs[p] = true
			var k := String(f.get("kind", ""))
			if k == "":
				no_kind.append("%s/%s" % [tid, String(f.id)])
			kinds[k] = true
		if kinds.size() < 2:
			one_kind.append(tid)
	ok("테마마다 협공 3개의 **행동 목적(goal)**이 서로 다르다", same_goal.is_empty(), str(same_goal))
	ok("협공 3개의 주역 조합(비중 1·2위 종류)이 테마 안에서 겹치지 않는다", same_pair.is_empty(), str(same_pair))
	ok("모든 편성이 리듬(kind = swarm 무리 처리 / coop 협공 / strong 강적)을 선언한다", no_kind.is_empty(), str(no_kind))
	ok("한 테마의 세 편성이 같은 리듬만 반복하지 않는다(2가지 이상)", one_kind.is_empty(), str(one_kind))

	# 막이 다르면 대표 협공도 다르다(집중 경로 세 막)
	var focus := ["act1_hunt_forest", "act2_frozen_pass", "act3_twisted_citadel"]
	var by_theme := {}
	var dup_across := []
	for tid in focus:
		for f in (PCatalog.theme(tid).formations.normal as Array):
			var p := lead_pair(f)
			if by_theme.has(p):
				dup_across.append("%s ↔ %s (%s)" % [tid, String(by_theme[p]), p])
			by_theme[p] = tid
	ok("세 막(사냥 숲·얼어붙은 협곡·뒤틀린 성채)의 대표 협공이 서로 겹치지 않는다", dup_across.is_empty(), str(dup_across))

	# 등장 종류 수(사용자 기준: 짧은 탐험 3종 안팎 / 보통 4종 안팎 / 깊은 곳 4~5종)
	var kinds_bad := []
	for tid in T:
		var t2: Dictionary = T[tid]
		for f in (t2.formations.normal as Array):
			var n: int = (f.comp as Array).size()
			if n < 2 or n > 5:
				kinds_bad.append("%s %d종" % [String(f.id), n])
	ok("편성마다 등장 **종류** 수가 2~5(전체 개체 수와 다른 값이다)", kinds_bad.is_empty(), str(kinds_bad))

	# ================= 2. 분대 구조 =================
	var squad_bad := []
	var support_only_squad := []
	var order_bad := []
	var no_front := []
	for tid in T:
		var t3: Dictionary = T[tid]
		for kind in ["normal", "risk"]:
			for f in (t3.formations[kind] as Array):
				if (f.get("squad", {}) as Dictionary).is_empty():
					squad_bad.append(String(f.id))
					continue
				var slots: Dictionary = (f.squad as Dictionary).get("slots", {})
				var has_front := false
				for c in PRun.comp_effective(f):
					if String(slots.get(String(c.type), "front")) == "front":
						has_front = true
				if not has_front:
					no_front.append(String(f.id))
				var run := make_run(3, int(t3.act), tid)
				var pid := String((t3.places as Array)[0].id)
				var st := encounter(run, pid, String(f.id), 7)
				var sqs: Array = st.formation.get("squads", [])
				if sqs.is_empty():
					squad_bad.append(String(f.id) + ":분대없음")
					continue
				var total := 0
				for sq in sqs:
					total += (sq.members as Array).size()
					var sq_front := false
					for m in (sq.members as Array):
						if String(m.slot) == "front":
							sq_front = true
					if not sq_front and (sq.members as Array).size() > 0:
						support_only_squad.append("%s/%s" % [String(f.id), str((sq.members as Array).size())])
				if total != (st.formation.units as Array).size():
					order_bad.append("%s 분대 합 %d != 전체 %d" % [String(f.id), total, (st.formation.units as Array).size()])
	ok("모든 편성이 분대(squad)를 만든다", squad_bad.is_empty(), str(squad_bad))
	ok("모든 편성에 '앞에서 접근'하는 자리(front)가 있다 — 지원·측면만으로 이루어진 편성이 없다", no_front.is_empty(), str(no_front))
	ok("지원만으로 이루어진 분대가 없다(지원병을 혼자 보내지 않는다)", support_only_squad.is_empty(), str(support_only_squad))
	ok("분대 구성원의 합이 편성 전체 수와 같다(분대로 나눠도 총 등장 수가 변하지 않는다)", order_bad.is_empty(), str(order_bad))

	# ================= 3. 총 등장 수·경험치 예산 불변 =================
	var XPV: Dictionary = PCatalog.growth().XP_VALUE
	var budget_bad := []
	for tid in T:
		var t4: Dictionary = T[tid]
		for kind in ["normal", "risk"]:
			for f in (t4.formations[kind] as Array):
				for pi in 2:
					var pk := "p1" if pi == 0 else "p2"
					var pid2 := String((t4.places as Array)[pi].id)
					for day in [1, 5, 9]:
						var wv := PRun.template_waves(f, pk, day, PRun.place_cost(pid2))
						var bud := wave_budget(wv)
						var n_all := wave_count(wv)
						var target: float = float((f.get("xp_units", {}) as Dictionary).get(pk, 0.0)) + float(int(f.get("elites", 0))) * float(XPV.get("wolf_alpha", 30.0))
						if absf(bud - target) > 0.01:
							budget_bad.append("%s/%s/%d일 %.2f != %.2f" % [String(f.id), pk, day, bud, target])
						var want: int = PPacing.day_total(day, PRun.place_cost(pid2)) + int(f.get("elites", 0))
						if n_all != want:
							budget_bad.append("%s/%s/%d일 수 %d != %d" % [String(f.id), pk, day, n_all, want])
	ok("편성을 바꿔도 **총 등장 수와 전투 경험치 예산이 개편 전과 같다**(36편성 × 2장소 × 3날짜)", budget_bad.is_empty(), str(budget_bad.slice(0, 6)))

	# 결투 상대는 일반 적 1마리를 대신한다 — 수도 예산도 늘지 않는다
	var duel_bad := []
	for tid in focus:
		var t5: Dictionary = PCatalog.theme(tid)
		var f0: Dictionary = (t5.formations.normal as Array)[0]
		var base := PRun.template_waves(f0, "p1", int(DAY_OF_ACT[int(t5.act)]), 1)
		for dt in PRun.duel_types_for(tid):
			var wd := PRun.template_waves(f0, "p1", int(DAY_OF_ACT[int(t5.act)]), 1, false, String(dt))
			if wave_count(base) != wave_count(wd) or absf(wave_budget(base) - wave_budget(wd)) > 0.01:
				duel_bad.append("%s/%s 수 %d→%d 예산 %.2f→%.2f" % [tid, String(dt), wave_count(base), wave_count(wd), wave_budget(base), wave_budget(wd)])
	ok("결투 상대는 **일반 적 1마리를 대신한다** — 총 등장 수·경험치 예산이 늘지 않는다", duel_bad.is_empty(), str(duel_bad))

	# ================= 4. 재현(시드·저장) =================
	var r_a := make_run(11, 2, "act2_frozen_pass")
	var r_b := make_run(11, 2, "act2_frozen_pass")
	var st_a := encounter(r_a, "t2c_snow", "t2c_frost_wolf", 21)
	var st_b := encounter(r_b, "t2c_snow", "t2c_frost_wolf", 21)
	var same_units: bool = (st_a.formation.units as Array) == (st_b.formation.units as Array)
	var log_a := []
	var log_b := []
	for sq in (st_a.formation.squads as Array):
		for m in (sq.members as Array):
			log_a.append("%s:%s" % [String(m.type), String(m.slot)])
	for sq in (st_b.formation.squads as Array):
		for m in (sq.members as Array):
			log_b.append("%s:%s" % [String(m.type), String(m.slot)])
	ok("같은 시드·같은 카드 = 같은 분대 편성(저장·복구 재현)", same_units and log_a == log_b, "%d/%d" % [log_a.size(), log_b.size()])

	# 카드에 저장된 결투 상대가 저장·복구 뒤에도 같다(난수를 쓰지 않으므로 다시 만들어도 같다)
	var r_c := make_run(12, 1, "act1_hunt_forest")
	r_c.day = 2
	r_c.cards = null
	var cards1 := PSortie.cards_for(r_c).duplicate(true)
	r_c.cards = null
	var cards2 := PSortie.cards_for(r_c)
	var duel_same := true
	for i in cards1.size():
		if String(cards1[i].get("duelType", "")) != String(cards2[i].get("duelType", "")):
			duel_same = false
	ok("결투 상대 배정이 재현된다(난수를 쓰지 않는다 — 시드·저장이 그대로다)", duel_same, str(cards1.map(func(c): return String(c.get("duelType", "-")))))

	# 한 막에서 서로 다른 두 종류의 특수 정예를 만날 기회가 있다(막 안 3일 × 카드 2장).
	# 기회는 두 곳에서 온다: **결투**(비위험 카드)와 **편성 안의 특수 정예**(위험 카드).
	# 하루가 통째로 위험 카드가 되어도 그 카드에서 특수 정예를 만나므로 기회 자체는 남는다.
	var few := []
	var duel_few := []
	for seed_v in [7, 13, 21]:
		for tid in T:
			var t6: Dictionary = T[tid]
			var seen := {}
			var seen_duel := {}
			var run6 := make_run(seed_v, int(t6.act), tid)
			for d in (PRun.act_of(run6).get("days", []) as Array):
				run6.day = int(d)
				run6.cards = null
				for c in PSortie.cards_for(run6):
					var dt2 := String(c.get("duelType", ""))
					if dt2 != "":
						seen[dt2] = true
						seen_duel[dt2] = true
					# §13: 편성 템플릿이 배정한 특수 정예도 **결투**로 나온다(카드의 duelType 만 세면 안 된다).
					# 그 카드에는 결투가 이미 있으므로 assign_duel 이 결투를 겹쳐 붙이지 않는다(1대1).
					for tp4 in PRun.scheduled_special_elites(String(c.regionId), String(c.get("formationId", "base"))):
						seen_duel[String(tp4)] = true
					for tp in (PSortie.elite_notice(run6, c).get("types", []) as Array):
						seen[String(tp)] = true
			if seen.size() < 2:
				few.append("시드 %d %s %d종" % [seed_v, tid, seen.size()])
			if seen_duel.is_empty():
				duel_few.append("시드 %d %s" % [seed_v, tid])
	ok("막마다 **서로 다른 두 종류 이상**의 특수 정예를 만날 기회가 배정된다(1막 포함, 시드 3개)", few.is_empty(), str(few))
	ok("막마다 결투 기회가 최소 한 번은 배정된다", duel_few.is_empty(), str(duel_few))

	# ================= 5. 실제 전투: 겹침·막힘·말미 =================
	var run_f := make_run(5, 2, "act2_frozen_pass")
	var st_f := encounter(run_f, "t2c_snow", "t2c_boar_archer", 31)
	var res_f := play(st_f)
	ok("분대 전환·종류 상한 때문에 전투가 막히지 않는다(전체 등장 완료·승리)",
		String(res_f.status) == "won" and int(st_f.spawn_count) == int(st_f.spawn_total),
		"%s %d/%d" % [String(res_f.status), int(st_f.spawn_count), int(st_f.spawn_total)])
	ok("일반 전투 종료 뒤 대기열에서 적이 뒤늦게 나오지 않는다", int(res_f.late_spawn) == 0, "늦은 등장 %d" % int(res_f.late_spawn))
	ok("다음 분대가 앞 분대의 전멸을 기다리지 않는다(겹쳐 투입된 분대가 절반 이상)",
		int(st_f.stats.squad_overlaps) * 2 >= int(st_f.stats.squad_pushes) and int(st_f.stats.squad_pushes) > 0,
		"겹침 %d / 전체 %d" % [int(st_f.stats.squad_overlaps), int(st_f.stats.squad_pushes)])

	# 멧돼지만 남는 대기 전후 비교(대조군 = 분대 편성 끔)
	var run_g := make_run(5, 2, "act2_frozen_pass")
	var st_g := encounter(run_g, "t2c_snow", "t2c_boar_archer", 31, "", true)
	var res_g := play(st_g)
	ok("분대 편성이 '지원 적만 남은 시간'을 늘리지 않는다(대조군 대비)",
		float(res_f.support_only) <= float(res_g.support_only) + 1.0,
		"분대 %.1f초 / 대조군 %.1f초" % [float(res_f.support_only), float(res_g.support_only)])
	ok("분대 편성이 전투 말미의 '1~2마리 대기'를 늘리지 않는다(대조군 대비)",
		float(st_f.stats.thin_tail_sec) <= float(st_g.stats.thin_tail_sec) + 1.0,
		"분대 %.1f초 / 대조군 %.1f초" % [float(st_f.stats.thin_tail_sec), float(st_g.stats.thin_tail_sec)])

	# 지원 적이 근접 호위와 함께 살아 있는가(홀로 남는 시간이 전투의 20% 미만)
	ok("지원 적이 아군과 함께 살아서 행동한다(지원만 남은 시간이 전투의 20% 미만)",
		float(st_f.stats.support_only_sec) < float(st_f.t) * 0.2 + 0.1,
		"%.1f초 / 전투 %.1f초" % [float(st_f.stats.support_only_sec), float(st_f.t)])

	# ================= 6. 특수 정예 결투 =================
	var run_d := make_run(5, 1, "act1_hunt_forest")
	var st_d := encounter(run_d, "t1a_path", "t1a_wolves", 41, "elite_fang")
	var bot := PBot.new("balanced")
	var n := 0
	var reinforce := 0
	var at_cleanup := {}
	var spawn_mark := -1
	var won_frame := {}
	while st_d.status == "running" and n < int(MAX_SEC / STEP):
		var prev_stage := String(st_d.duel_stage)
		st_d.step(bot.step_input(st_d), STEP)
		st_d.player.hp = st_d.player.hp_max
		st_d.player.dead = false
		n += 1
		if prev_stage == "normal" and String(st_d.duel_stage) == "cleanup":
			at_cleanup = { "queued": int(st_d.spawn_total) - int(st_d.spawn_count), "pending": st_d.pending.size(), "alive": st_d.alive_units(), "carry": st_d.squad_carry.size() }
		if String(st_d.duel_stage) != "" and String(st_d.duel_stage) != "normal":
			if spawn_mark < 0:
				spawn_mark = int(st_d.spawn_count)
			elif int(st_d.spawn_count) > spawn_mark:
				reinforce += int(st_d.spawn_count) - spawn_mark
				spawn_mark = int(st_d.spawn_count)
		if String(st_d.status) == "won" and won_frame.is_empty():
			var alive_sum := 0
			for e in st_d.enemies:
				if not e.dead and not bool(e.get("structure", false)):
					alive_sum += 1
			won_frame = { "alive": alive_sum, "pending": st_d.pending.size(), "pending_loss": bool(st_d.pending_loss), "stage": String(st_d.duel_stage) }
	ok("전환 조건: 일반 몬스터 생존 0 · 등장 예고 0 · 미등장 예약 0일 때만 결투로 넘어간다",
		not at_cleanup.is_empty() and int(at_cleanup.queued) == 0 and int(at_cleanup.pending) == 0 and int(at_cleanup.alive) == 0 and int(at_cleanup.carry) == 0, str(at_cleanup))
	ok("결투 중 **일반 편성의 추가 증원이 0이다**", reinforce == 0, "증원 %d" % reinforce)
	ok("결투 상대를 쓰러뜨려야 출격 승리가 난다(일반 전투 종료를 승리로 먼저 처리하지 않는다)",
		String(st_d.status) == "won" and String(st_d.duel_stage) == "done" and st_d.duel_enemy != null and bool(st_d.duel_enemy.dead),
		"%s/%s" % [String(st_d.status), String(st_d.duel_stage)])
	ok("승리 프레임 경계: 결투 주체 처치와 같은 프레임에 남은 적 0 · 예고 0 · 보류 패배 해제",
		not won_frame.is_empty() and int(won_frame.alive) == 0 and int(won_frame.pending) == 0 and not bool(won_frame.pending_loss), str(won_frame))

	# 결투 중 정산은 아직 불가(일반 전투 종료를 출격 승리로 먼저 처리하지 않는다)
	var run_e := make_run(6, 1, "act1_hunt_forest")
	var st_e := encounter(run_e, "t1a_path", "t1a_wolves", 42, "elite_fang")
	st_e.status = "won" # 강제로 승리 상태만 만들어 놓고 결투가 남아 있을 때 정산을 시도한다
	var early := PFlow.settle_victory(run_e, sortie_of("t1a_path", "t1a_wolves", 42, "elite_fang"), st_e)
	ok("특수 정예전이 남아 있으면 출격 승리 정산이 거부된다", (early as Dictionary).is_empty())

	# 고유 소환: 출처 귀속 · 상한 · 경험치 0
	# 소환하는 특수 정예(군단 기수)는 1막 버려진 요새 후보다. 짧은 전투로 소환·정리·정산까지 본다
	var run_s := make_run(7, 1, "act1_abandoned_fort")
	var st_s := encounter(run_s, "t1b_wall", "t1b_shield_archer", 43, "elite_standard")
	var n2 := 0
	var max_sum_alive := 0
	while st_s.status == "running" and n2 < int(MAX_SEC / STEP):
		st_s.step(bot.step_input(st_s), STEP)
		st_s.player.hp = st_s.player.hp_max
		st_s.player.dead = false
		n2 += 1
		if String(st_s.duel_stage) == "duel":
			max_sum_alive = maxi(max_sum_alive, st_s.duel_summon_alive())
	var cfg_s: Dictionary = (PRun.duel_cfg().get("summon", {}) as Dictionary).get("elite_standard", {})
	var owned := true
	var xp_zero := true
	for e in st_s.enemies:
		if bool(e.get("duel_summon", false)):
			if String(e.get("summon_owner", "")) != "elite_standard":
				owned = false
			if st_s.xp_for(e) != 0.0:
				xp_zero = false
	ok("특수 정예가 **자기 기술로 부르는 소환수**가 실제로 나오고 출처가 그 정예에게 귀속된다(군단 기수 부하 소환 유지)",
		int(st_s.stats.duel_summons) > 0 and owned, "소환 %d · 귀속 %s" % [int(st_s.stats.duel_summons), str(owned)])
	ok("소환 수·동시 상한을 지킨다(총 %d · 동시 %d)" % [int(cfg_s.get("max_total", 0)), int(cfg_s.get("max_alive", 0))],
		int(st_s.stats.duel_summons) <= int(cfg_s.get("max_total", 0)) and max_sum_alive <= int(cfg_s.get("max_alive", 0)),
		"총 %d · 동시 최대 %d" % [int(st_s.stats.duel_summons), max_sum_alive])
	ok("귀속 소환물은 경험치를 주지 않는다(무한 보상 파밍 금지)", xp_zero)
	ok("결투 주체를 처치하면 남은 소환물이 추가 보상 없이 정리된다",
		String(st_s.status) != "won" or int(st_s.duel_summon_alive()) == 0,
		"남은 소환물 %d · 정리 %d" % [int(st_s.duel_summon_alive()), int(st_s.stats.duel_summons_cleared)])

	# 정산 1회(보상·물약·성장 중복 없음)
	if String(st_s.status) == "won":
		var srt := sortie_of("t1b_wall", "t1b_shield_archer", 43, "elite_standard")
		var gold0 := int(run_s.gold)
		var rw1 := PFlow.settle_victory(run_s, srt, st_s)
		var gold1 := int(run_s.gold)
		var rw2 := PFlow.settle_victory(run_s, srt, st_s)
		ok("결투 승리 정산은 정확히 1회다(보상·물약·성장 중복 없음)",
			not (rw1 as Dictionary).is_empty() and (rw2 as Dictionary).is_empty() and int(run_s.gold) == gold1 and gold1 >= gold0,
			"금화 %d → %d" % [gold0, int(run_s.gold)])
	else:
		ok("결투 승리 정산은 정확히 1회다(보상·물약·성장 중복 없음) — 이번 시드는 결투까지 가지 못해 건너뜀", true, String(st_s.status))

	special_elite_tests()

	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ================= 7. 특수 정예는 언제나 결투다(§13, 2026-09-09 사용자 확정) =================
## 사용자 재현: 시드 71618(전투 시드) · 7일차 · 의식 중심부에서 **사슬 집행자와 일반 도마뱀이 동시에 살아 있었다.**
## 원인은 하나가 아니라 배정 경로가 여럿이었다는 것이다:
##   ① template_waves 가 elite_types_for(...)로 고른 특수 정예를 **표시 없이** 일반 웨이브에 넣었다
##   ② 더 깊이 탐험이 정예 없는 편성에 강한 정예를 **표시 없이** 덧붙였다
##   ③ ①·②와 카드 결투가 서로를 몰라 같은 종류를 **두 번** 배정하기도 했다
## 그래서 판정을 한 곳(PRun.is_special_elite)으로 모으고, 웨이브를 만드는 쪽과 편성으로 바꾸는 쪽
## **양쪽에서** 걸러 낸다. 일반 정예·늑대 우두머리는 규칙상 일반 전투에 함께 나와도 되므로 건드리지 않는다.
func special_elite_tests() -> void:
	var T := PCatalog.themes()
	var leaked := []        # 일반 등장 목록에 섞인 특수 정예
	var two_duels := []     # 한 전투에 결투가 둘 이상(1대1 위반)
	var dup := []           # 같은 종류를 두 번 배정(중복 배정)
	var count_bad := []     # 총 등장 수가 규칙과 다르다
	var seen_duel := {}     # 7종 전수 표: 결투로 실제 배정된 종류
	var checked := 0
	for tid in T:
		var t: Dictionary = T[tid]
		var act := int(t.act)
		var run := make_run(1234, act, String(tid))
		for pi in 2:
			var rid := String((t.places as Array)[pi].id)
			var pk := "p1" if pi == 0 else "p2"
			for f in ((t.formations.normal as Array) + (t.formations.risk as Array)):
				for deep in [false, true]:
					for dt in ["", String(PRun.duel_types_for(String(tid))[0])]:
						checked += 1
						var srt := sortie_of(rid, String(f.id), 71, dt)
						srt.deep = bool(deep)
						var waves := PRun.encounter_waves(rid, bool(deep), run, srt)
						var types := {}
						var duel_n := 0
						for w in waves:
							for g in w:
								var tp := String(g.type)
								if not PRun.is_special_elite(tp) or int(g.n) <= 0:
									continue
								types[tp] = int(types.get(tp, 0)) + int(g.n)
								if not bool(g.get("duel", false)):
									leaked.append("%s/%s/%s%s → %s" % [rid, String(f.id), pk, ("+더깊이" if deep else ""), tp])
								else:
									duel_n += int(g.n)
									seen_duel[tp] = true
						for tp2 in types:
							if int(types[tp2]) > 1:
								dup.append("%s/%s%s → %s ×%d" % [rid, String(f.id), ("+더깊이" if deep else ""), String(tp2), int(types[tp2])])
						# 결투 수는 **배정 표가 정한 특수 정예 수**를 넘지 않는다(카드 결투가 겹쳐 늘지 않는다).
						# 3막 위험 편성처럼 배정 표가 2종을 지정한 곳만 2가 되고, 그때는 순서대로 1대1로 상대한다.
						var planned_n: int = PRun.scheduled_special_elites(rid, String(f.id), bool(deep)).size()
						if duel_n > maxi(1, planned_n):
							two_duels.append("%s/%s%s → 결투 %d(배정 %d)" % [rid, String(f.id), ("+더깊이" if deep else ""), duel_n, planned_n])
						# 총 등장 수: 일반 전투는 '날짜 예산표 + 정예 자리'다(결투 상대는 일반 적 1마리를 대신하므로 늘지 않는다)
						if not deep:
							var want := PPacing.day_total(int(run.day), PRun.place_cost(rid))
							if want <= 0:
								want = int(f.sizes[pk].total)
							want += int(f.get("elites", 0))
							if wave_count(waves) != want:
								count_bad.append("%s/%s%s %d != %d" % [rid, String(f.id), (" 결투" if dt != "" else ""), wave_count(waves), want])
	ok("특수 정예가 **일반 등장 목록에 섞이지 않는다** — 모든 테마·편성·장소·더 깊이·결투 조합 %d가지" % checked,
		leaked.is_empty(), str(leaked.slice(0, 6)))
	ok("결투 수가 배정 표를 넘지 않는다 — 카드 결투가 편성의 특수 정예 위에 겹치지 않는다(1대1)",
		two_duels.is_empty(), str(two_duels.slice(0, 6)))

	# 배정 표가 특수 정예 2종을 지정한 편성(3막 위험)은 **순서대로** 대기열에 선다.
	# 전투 규칙(CombatState, 다른 담당)은 지금 대기열의 첫 상대만 처리한다 — docs/KNOWN_DEFECTS.md KD-12.
	var order_bad := []
	var pair_seen := 0
	for tid2 in T:
		var t2: Dictionary = T[tid2]
		var run_p := make_run(77, int(t2.act), String(tid2))
		for f2 in (t2.formations.risk as Array):
			var want_order: Array = PRun.scheduled_special_elites(String((t2.places as Array)[1].id), String(f2.id))
			if want_order.size() < 2:
				continue
			pair_seen += 1
			var st_p := encounter(run_p, String((t2.places as Array)[1].id), String(f2.id), 81)
			var got_order := []
			for d in (st_p.formation.get("duels", []) as Array):
				got_order.append(String(d.type))
			if str(got_order) != str(want_order) or String(st_p.duel_type) != String(want_order[0]):
				order_bad.append("%s/%s %s != %s (첫 상대 %s)" % [String(tid2), String(f2.id), str(got_order), str(want_order), String(st_p.duel_type)])
	ok("특수 정예가 둘 예정된 편성은 **배정 표 순서대로** 결투 대기열에 서고 첫 상대부터 1대1로 붙는다(%d개 편성)" % pair_seen,
		order_bad.is_empty() and pair_seen > 0, str(order_bad))
	ok("같은 특수 정예를 한 전투에 두 번 배정하지 않는다(중복 배정 금지)", dup.is_empty(), str(dup.slice(0, 6)))
	ok("결투가 붙어도 총 등장 수가 '날짜 예산 + 정예 자리' 그대로다(적을 지우거나 늘리지 않는다)",
		count_bad.is_empty(), str(count_bad.slice(0, 6)))
	var missing := []
	for tp3 in PCatalog.elites():
		if not seen_duel.has(String(tp3)):
			missing.append(String(tp3))
	ok("특수 정예 **7종 전부**가 실제로 결투로 배정된다", missing.is_empty() and seen_duel.size() >= 7,
		"결투로 나온 종류 %d종 · 빠진 종류 %s" % [seen_duel.size(), str(missing)])

	# --- 옛 저장·도구가 넘긴 duel_type 이 편성의 특수 정예와 겹쳐도 결투는 하나다 ---
	# (§13 이전에 저장된 회차의 카드에는 편성이 이미 특수 정예를 내보내는데도 duelType 이 붙어 있을 수 있다)
	var run_o := make_run(3, 2, "act2_crimson_ritual")
	var conflict := PRun.scheduled_special_elites("t2a_altar", "t2a_risk")
	var w_o := PRun.encounter_waves("t2a_altar", false, run_o, sortie_of("t2a_altar", "t2a_risk", 64, "elite_plaguecaller"))
	var w_o_plain := PRun.encounter_waves("t2a_altar", false, run_o, sortie_of("t2a_altar", "t2a_risk", 64, ""))
	var duel_o := 0
	for w in w_o:
		for g in w:
			if bool(g.get("duel", false)) and int(g.n) > 0:
				duel_o += int(g.n)
	ok("편성이 이미 특수 정예를 내보내면 옛 duel_type 이 와도 결투는 하나다(총 수·예산도 그대로)",
		duel_o == 1 and wave_count(w_o) == wave_count(w_o_plain) and is_equal_approx(wave_budget(w_o), wave_budget(w_o_plain)),
		"편성 배정=%s · 결투 %d · 수 %d/%d · 예산 %.1f/%.1f" % [str(conflict), duel_o, wave_count(w_o), wave_count(w_o_plain), wave_budget(w_o), wave_budget(w_o_plain)])

	# --- 일반 정예·늑대 우두머리는 일반 전투에 그대로 나온다(특수 정예와 구분) ---
	var run_w := make_run(5, 1, "act1_hunt_forest")
	var f_w := PFormation.from_waves([[{ "type": "wolf", "n": 3 }, { "type": "wolf_alpha", "n": 1 }]], {}, "forest", encounter(run_w, "t1a_path", "t1a_wolves", 51))
	ok("늑대 우두머리(옛 정예)는 일반 등장 목록에 남는다 — 특수 정예만 결투로 뺀다",
		(f_w.units as Array).has("wolf_alpha") and (f_w.duels as Array).is_empty(), str(f_w.duels))

	# --- 안전망: 표시가 빠진 채 들어와도 편성이 걸러 낸다(어떤 배정 경로에서도) ---
	var f_x := PFormation.from_waves([[{ "type": "wolf", "n": 3 }, { "type": "elite_chainbreaker", "n": 1 }]], {}, "t2a_altar", encounter(run_w, "t1a_path", "t1a_wolves", 52))
	var mixed_x := (f_x.units as Array).has("elite_chainbreaker")
	ok("결투 표시가 빠진 특수 정예도 편성이 결투로 돌린다(마지막 안전망)",
		not mixed_x and (f_x.duels as Array).size() == 1 and String((f_x.duel as Dictionary).get("type", "")) == "elite_chainbreaker",
		"units에 섞임=%s · 대기열=%s" % [str(mixed_x), str(f_x.duels)])

	# --- 임무 전투: 결투가 붙지 않고 특수 정예도 들어오지 않는다(KD-11과 §13이 함께 지켜진다) ---
	var run_m := make_run(9, 2, "act2_crimson_ritual")
	var mission_bad := []
	for obj in (PCatalog.missions().objective_ids as Array):
		var srt_m := sortie_of("t2a_altar", "t2a_risk", 61, "")
		srt_m.mission = true
		srt_m.objective = String(obj)
		srt_m.risk = null
		var st_m := CombatState.new(PFlow.encounter_opts(run_m, srt_m))
		for u in (st_m.formation.get("units", []) as Array):
			if PRun.is_special_elite(String(u)):
				mission_bad.append("%s → %s" % [String(obj), String(u)])
		if String(st_m.duel_type) != "":
			mission_bad.append("%s 에 결투 %s" % [String(obj), String(st_m.duel_type)])
	ok("임무 전투에는 특수 정예도 결투도 들어오지 않는다", mission_bad.is_empty(), str(mission_bad))

	# --- 사건 추가 전투(강적의 흔적·상인)도 같은 규칙을 지킨다 ---
	var event_bad := []
	for ev_id in ["challenge", "trace"]:
		var srt_e := sortie_of("t2a_altar", "t2a_red_wolves", 62, "")
		srt_e.eventFight = String(ev_id)
		var st_e2 := CombatState.new(PFlow.encounter_opts(run_m, srt_e))
		for u2 in (st_e2.formation.get("units", []) as Array):
			if PRun.is_special_elite(String(u2)):
				event_bad.append("%s → %s" % [String(ev_id), String(u2)])
	ok("사건 추가 전투(강적의 흔적·상인)에서도 특수 정예는 결투로만 나온다", event_bad.is_empty(), str(event_bad))

	# --- 저장 복구: 저장했다 불러와도 같은 결투·같은 편성이다(난수를 쓰지 않는다) ---
	# 실제로 결투가 붙은 날을 찾아서 검사한다(관문일·임무 카드만 있는 날에는 결투가 붙지 않는다)
	var run_s2 := make_run(544, 2, "act2_crimson_ritual")
	var duel_assigned := false
	for sd in [544, 3, 11, 21]:
		for dd in [4, 5, 6]:
			if duel_assigned:
				continue
			var r_try := make_run(int(sd), 2, "act2_crimson_ritual")
			r_try.day = int(dd)
			r_try.cards = null
			for c0 in PSortie.cards_for(r_try):
				if String(c0.get("duelType", "")) != "":
					duel_assigned = true
			if duel_assigned:
				run_s2 = r_try
	var cards_before := PSortie.cards_for(run_s2)
	var before := []
	for c in cards_before:
		before.append("%s:%s" % [String(c.regionId), String(c.get("duelType", ""))])
	var json_txt := JSON.stringify(PSave.normalize(run_s2.duplicate(true)))
	var loaded: Dictionary = JSON.parse_string(json_txt)
	PSave.normalize(loaded)
	var after := []
	for c2 in PSortie.cards_for(loaded):
		after.append("%s:%s" % [String(c2.regionId), String(c2.get("duelType", ""))])
	var srt_b := sortie_of(String(cards_before[0].regionId), String(cards_before[0].get("formationId", "base")), 63, String(cards_before[0].get("duelType", "")))
	var w_b := PRun.encounter_waves(String(cards_before[0].regionId), false, run_s2, srt_b)
	var w_a := PRun.encounter_waves(String(cards_before[0].regionId), false, loaded, srt_b)
	ok("저장·복구해도 결투 배정과 편성이 그대로다(실제로 결투가 붙은 날로 검사)",
		duel_assigned and str(before) == str(after) and wave_count(w_b) == wave_count(w_a) and is_equal_approx(wave_budget(w_b), wave_budget(w_a)),
		"%s → %s · 수 %d/%d · 예산 %.1f/%.1f" % [str(before), str(after), wave_count(w_b), wave_count(w_a), wave_budget(w_b), wave_budget(w_a)])
