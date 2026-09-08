extends SceneTree
## 임무(봉인·제단) 측정 도구: 지원 예산·간격·동시 상한·출현 대기·출현 실패·처치 속도를 각각 나눠 찍는다.
## 실행: python tools/run_suites.py --suites mission_probe --allow-adhoc --timeout 900
##   개편 전 값과 비교: PROPHECY_OBJ=off 를 넣고 같은 명령(공통 실행기는 임시 스위트에 환경을 넣지 않으므로 직접 실행 시에만)
## 이 파일은 통과/실패를 판정하지 않는다. 숫자를 표로 찍는 계측 도구다(봇 승패는 통과 조건이 아니다).
## 정책: still(제자리·Q/E) / chase(목표로 이동만·회피 없음) / dodge(실력 봇 regular, 회피 포함)

const STEP := 1.0 / 120.0
const MAX_SEC := 60.0
const SNAP := 29.6 # 사람 플레이 관찰 시점

func build_of(day: int) -> Dictionary:
	var run := PRun.new_run(11, "sword")
	run.day = day
	return PRun.build(run)

## 실제 회차 경로와 같은 조우 옵션(날짜 예산 편성·밀도·막)을 만든다. 임무 카드 = mission true
func mission_state(objective: String, day: int, seed_v: int, region: String = "") -> CombatState:
	var run := PRun.new_run(seed_v, "sword")
	run.day = day
	run.hp = float(PRun.build(run).hp_max)
	var rid := region
	if rid == "":
		var cards: Array = PSortie.cards_for(run)
		rid = String(cards[0].regionId)
	var s := { "regionId": rid, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0,
		"seed": seed_v * 977 + day, "day": day, "slot": 1, "variant": null,
		"mission": true, "objective": objective, "risk": null, "cardId": "probe" }
	return PFlow.make_encounter(run, s, { "fixed_build": true })

## 목표 지점으로 걸어가는 정책(회피 없음). PObjectives.bot_goal이 주는 지점을 그대로 쓴다
func chase_input(st: CombatState) -> Dictionary:
	var p := st.player
	var g := PObjectives.bot_goal(st)
	var mx := 0.0
	var my := 0.0
	if g.is_empty() and st.objective == "altars":
		var t := PObjectives.bot_target(st)
		if not t.is_empty():
			g = { "x": float(t.x), "y": float(t.y), "r": 40.0 }
	if not g.is_empty():
		var dx: float = float(g.x) - p.x
		var dy: float = float(g.y) - p.y
		var d: float = maxf(1.0, sqrt(dx * dx + dy * dy))
		if d > float(g.get("r", 20.0)):
			mx = dx / d
			my = dy / d
	return { "mx": mx, "my": my, "dodge_press": false, "dodge_held": false, "special": true, "skill_e": true }

func run_one(objective: String, day: int, seed_v: int, pol: String) -> Dictionary:
	var st := mission_state(objective, day, seed_v)
	var bot: PBot = null
	if pol == "dodge":
		bot = PSkillBot.new("regular", seed_v)
	elif pol == "still":
		bot = PBot.new("still")
	var series := []
	var n := 0
	var snap := {}
	var kills0 := 0
	var last_t := 0.0
	while st.status == "running" and n < int(MAX_SEC / STEP):
		var inp: Dictionary = chase_input(st) if bot == null else bot.step_input(st)
		st.step(inp, STEP)
		for a in (st.obj as Dictionary).get("altars", []):
			if bool(a.dead) and not a.has("probe_death_t"):
				a.probe_death_t = st.t
		st.player.hp = st.player.hp_max # 계측 전용: 전장 인구·진행률을 60초까지 보기 위해 죽지 않게 한다(피해 누적은 그대로 기록)
		n += 1
		if n % 60 == 0: # 0.5초마다 시계열
			var alive := 0
			var support := 0
			for e in st.enemies:
				if e.dead or bool(e.get("structure", false)) or bool(e.get("hidden", false)):
					continue
				alive += 1
			var R: Dictionary = (st.obj as Dictionary).get("reinforce", {})
			var L: Dictionary = R.get("log", {})
			support = int(R.get("spawned", 0)) # 목표 지원 + 증원 제단이 부른 수(둘 다 R.spawned를 올린다)
			var row := { "t": snapped(st.t, 0.1), "alive": alive, "pending": st.pending.size(),
				"sup_spawned": support, "budget": int(R.get("budget", 0)), "queued": maxi(0, st.spawn_total - st.spawn_count),
				"prog": snapped(PObjectives.progress_ratio(st), 0.001), "kills": int(st.stats.kills), "hp": int(round(float(st.player.hp))) }
			series.append(row)
			if snap.is_empty() and st.t >= SNAP:
				snap = row.duplicate()
		last_t = st.t
	if st.status == "running":
		st.status = "timeout"
		st.delayed.clear()
	var R2: Dictionary = (st.obj as Dictionary).get("reinforce", {})
	var L2: Dictionary = R2.get("log", {})
	var altars := []
	for a in (st.obj as Dictionary).get("altars", []):
		altars.append({ "kind": String(a.altar), "hp_max": int(round(float(a.hp_max))), "dead": bool(a.dead),
			"death_t": snapped(float(a.get("probe_death_t", -1.0)), 0.1),
			"fx": int(a.get("fx_n", 0)), "first_fx": snapped(float(a.get("first_fx_t", -1.0)), 0.1),
			"fx_before_death": int(a.get("fx_n", 0)) if not bool(a.dead) else int(a.get("fx_n", 0)) })
	return { "obj": objective, "day": day, "seed": seed_v, "pol": pol, "status": st.status, "sec": snapped(last_t, 0.1),
		"total": st.spawn_total, "cap": int(st.formation.get("alive_cap", 0)), "group": int(st.formation.get("group", 0)),
		"interval": float(st.formation.get("interval", 0.0)),
		"snap": snap, "series": series, "kills": int(st.stats.kills), "taken": int(round(float(st.stats.damage_taken))),
		"prog": snapped(PObjectives.progress_ratio(st), 0.001),
		"rein": { "budget0": int(R2.get("budget_total", 0)), "left": int(R2.get("budget", 0)), "spawned": int(L2.get("spawned", 0)),
			"try": int(L2.get("try", 0)), "cap_block": int(L2.get("cap_block", 0)), "budget_block": int(L2.get("budget_block", 0)),
			"gate_block": int(L2.get("gate_block", 0)), "floor_fire": int(L2.get("floor_fire", 0)),
			"first_t": snapped(float(L2.get("first_t", -1.0)), 0.1), "empty_sec": snapped(float(L2.get("empty_sec", 0.0)), 0.1),
			"thin_sec": snapped(float(L2.get("thin_sec", 0.0)), 0.1), "cap_cfg": int(R2.get("cap", 0)), "interval_cfg": float(R2.get("interval", 0.0)) },
		"altars": altars,
		"pace": { "support_only": snapped(float(st.stats.support_only_sec), 0.1), "thin_tail": snapped(float(st.stats.thin_tail_sec), 0.1), "no_target": snapped(float(st.stats.no_target_sec), 0.1) } }

func _init() -> void:
	var mode := "off" if PObjectives.variant() == "off" else "full"
	print("== 임무 계측 (개편 %s) ==" % ("끔(개편 전)" if mode == "off" else "켬"))
	var rows := []
	for objective in ["seal", "altars", "hunt", "rescue"]:
		for day in [2, 5]:
			for pol in ["still", "chase", "dodge"]:
				rows.append(run_one(objective, day, 3, pol))
	print("\n| 목표 | 날짜 | 정책 | 총 등장 | 동시 상한 | 29.6초 살아있는 적 | 29.6초 진행률 | 29.6초 지원 등장 | 60초 처치 | 받은 피해 | 결과 |")
	print("|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		var s: Dictionary = r.snap
		print("| %s | %d일 | %s | %d | %d | %s | %s | %s | %d | %d | %s |" % [String(r.obj), int(r.day), String(r.pol), int(r.total), int(r.cap),
			str(s.get("alive", "-")), str(s.get("prog", "-")), str(s.get("sup_spawned", "-")), int(r.kills), int(r.taken), String(r.status)])
	print("\n### 지원병 원인 분리(60초)")
	print("| 목표 | 날짜 | 정책 | 예산 | 남음 | 등장 | 시도 | 상한에 막힘 | 예산 없음 | 진행 잠금 | 하한 보충 | 첫 지원 | 빈 전장(초) | 적 ≤2(초) |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		var q: Dictionary = r.rein
		print("| %s | %d일 | %s | %d | %d | %d | %d | %d | %d | %d | %d | %s | %s | %s |" % [String(r.obj), int(r.day), String(r.pol),
			int(q.budget0), int(q.left), int(q.spawned), int(q.try), int(q.cap_block), int(q.budget_block), int(q.gate_block), int(q.floor_fire),
			str(q.first_t), str(q.empty_sec), str(q.thin_sec)])
	print("\n### 제단: 체력·첫 효과 시각·낸 효과 수·파괴 시각(60초)")
	print("| 날짜 | 정책 | 제단 | 체력 | 첫 효과(초) | 낸 효과 | 파괴(초) |")
	print("|---|---|---|---|---|---|---|")
	for r in rows:
		if String(r.obj) != "altars":
			continue
		for a in r.altars:
			print("| %d일 | %s | %s | %d | %s | %d | %s |" % [int(r.day), String(r.pol), PObjectives.altar_text(String(a.kind)), int(a.hp_max), str(a.first_fx), int(a.fx), (str(a.death_t) if bool(a.dead) else "살아있음")])
	print("\n### 시간축(봉인·회피 정책 seed 3, 2일차): t / 적 / 진행률")
	for r in rows:
		if String(r.obj) == "seal" and String(r.pol) == "dodge" and int(r.day) == 2:
			var line := ""
			for row in r.series:
				if int(round(float(row.t) * 2.0)) % 4 == 0: # 2초 간격
					line += "%s:%d/%s  " % [str(row.t), int(row.alive), str(row.prog)]
			print(line)
	print("\nJSON " + JSON.stringify(rows))
	# 계측 도구다(승패는 판정하지 않는다). 공통 실행기가 요구하는 요약 줄 = 모든 조합이 끝까지 돌았는지만 본다
	var okn := 0
	for r in rows:
		if not (r.series as Array).is_empty():
			okn += 1
	print("%d/%d PASS" % [okn, rows.size()])
	quit(0 if okn == rows.size() else 1)
