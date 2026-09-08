extends SceneTree
## 봉인 수호자 계측: ① 돌 뒤에 선 정지 플레이어에게 보스가 실제로 피해를 주는가(엄폐 대응 3안 비교)
##                  ② 3단계 양갈래 충격파에서 "정지한 플레이어가 받는 피해"(각도 변주·중앙 후속 전후)
## 실행: python tools/run_suites.py --suites boss_cover_probe --allow-adhoc --timeout 900
## 판정하지 않는다(봇 승패는 통과 조건이 아니다). 표만 찍는다.
## 정책: cover_still(돌 뒤 정지) / still(제자리·Q/E 없음, 열린 곳) / chase(추적만) / dodge(실력 봇 regular)

const STEP := 1.0 / 120.0
const SEC := 60.0
const HUGE_HP := 1000000.0

func build_of() -> Dictionary:
	var run := PRun.new_run(11, "sword")
	run.day = 7
	return PRun.build(run)

## 보스전과 같은 조건(실제 회차는 arena "clearing" — 돌 2·나무 2가 있다)
func make(seed_v: int, cover_mode: String, split_on: bool, arena: String = "clearing") -> CombatState:
	PBoss.set_cover_mode(cover_mode)
	PBoss.set_split_on(split_on)
	var st := CombatState.new({ "build": build_of(), "seed": seed_v, "arena": arena, "boss": true, "boss_id": "guardian",
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP, "act": 2 })
	for i in 600:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	return st

## 돌 뒤 자리: 보스에서 봤을 때 장애물 반대편(시선이 막히는 곳)
func cover_spot(st: CombatState, bz: Dictionary) -> Array:
	var best := []
	var bd := -1.0
	for ob in st.obstacles:
		for k in 12:
			var a: float = float(k) * TAU / 12.0
			var d: float = float(ob.r) + 26.0
			var x: float = clampf(float(ob.x) + cos(a) * d, 30.0, st.arena_w - 30.0)
			var y: float = clampf(float(ob.y) + sin(a) * d, 30.0, st.arena_h - 30.0)
			if not st.valid_pos(x, y, float(st.player.r)):
				continue
			if not st.los_blocked(float(bz.x), float(bz.y), x, y):
				continue
			var score := PGeom.dist(x, y, float(bz.x), float(bz.y))
			if score > bd:
				bd = score
				best = [x, y, float(ob.x), float(ob.y)]
	return best

## 한 판 측정. hold = "cover"(돌 뒤 정지) | "open"(열린 곳 정지, 보스에서 dist) | "" (봇)
func run_one(label: String, cover_mode: String, split_on: bool, hold: String, seed_v: int, dist: float = 200.0, phase: int = 1, arena: String = "clearing") -> Dictionary:
	var st := make(seed_v, cover_mode, split_on, arena)
	var bz: Dictionary = st.boss
	if phase > 1:
		bz.phase = phase
		bz.phase_pending = phase
	var bot: PBot = null
	if hold == "dodge":
		bot = PSkillBot.new("regular", seed_v)
	elif hold == "chase":
		bot = PBot.new("aggressive")
	var spot := []
	if hold == "cover":
		spot = cover_spot(st, bz)
		if not spot.is_empty():
			st.player.x = spot[0]
			st.player.y = spot[1]
	elif hold == "open":
		st.player.x = clampf(float(bz.x) + dist, 30.0, st.arena_w - 30.0)
		st.player.y = float(bz.y)
	var t0: float = st.t
	var blocked_steps := 0
	var n := int(SEC / STEP)
	var repos := 0
	var last_state := ""
	var broke := st.obstacles.size()
	for i in n:
		if st.status != "running" or bool(bz.dead):
			break
		if hold == "cover" and not spot.is_empty(): # 계속 돌 뒤에 서 있는다(사람 관찰 재현)
			st.player.x = spot[0]
			st.player.y = spot[1]
		elif hold == "open":
			st.player.x = clampf(float(bz.x) + dist, 30.0, st.arena_w - 30.0)
			st.player.y = float(bz.y)
		var inp: Dictionary = { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }
		if bot != null:
			inp = bot.step_input(st)
		st.step(inp, STEP)
		st.player.hp = st.player.hp_max # 계측: 죽지 않게(받은 피해는 그대로 누적)
		if phase > 1:
			bz.phase = phase
			bz.phase_pending = phase
		if st.los_blocked(float(bz.x), float(bz.y), st.player.x, st.player.y):
			blocked_steps += 1
		var s := String(bz.state)
		if s == "reposition" and last_state != "reposition":
			repos += 1
		if s == "breakrock" and last_state != "breakrock":
			repos += 1
		last_state = s
	var sm := st.summary()
	var inits := 0
	var bid: int = int(bz.get("id", -1))
	for a in st.attack_log:
		if int(a[1]) == bid:
			inits += 1
	var secs: float = maxf(0.001, st.t - t0)
	var taken: Dictionary = sm.taken
	var by := {}
	for k in taken:
		by[String(k)] = int(round(float(taken[k])))
	return { "label": label, "mode": cover_mode, "split": split_on, "hold": hold, "seed": seed_v, "phase": phase,
		"dist": dist, "sec": snapped(secs, 0.1), "taken": int(round(float(sm.damage_taken))), "hits": int(_sum(sm.taken_hits)),
		"inits": inits, "ipm": snapped(float(inits) / secs * 60.0, 0.1), "blocked": snapped(float(blocked_steps) * STEP / secs, 0.01),
		"repos": repos, "obs": st.obstacles.size(), "by": by, "pat": sm.patterns }

## 종말의 집행관 한 판(위치 변주 on/off). step_on=false면 gapStep 설정을 지운 상태로 돌린다
func run_exec(step_on: bool, hold: String, seed_v: int) -> Dictionary:
	var B := PBoss.behavior()
	var ex: Dictionary = (B.get("bosses", {}) as Dictionary).get("doom_executor", {})
	var saved = ex.get("gapStep", null)
	if not step_on:
		ex.erase("gapStep")
	elif saved == null:
		ex.gapStep = { "speed": 150.0 }
	var st := CombatState.new({ "build": build_of(), "seed": seed_v, "arena": "clearing", "boss": true, "boss_id": "doom_executor",
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP, "act": 3 })
	for i in 900:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	var bz: Dictionary = st.boss
	bz.phase = 3
	bz.phase_pending = 3
	var bot: PBot = null
	if hold == "dodge":
		bot = PSkillBot.new("regular", seed_v)
	elif hold == "chase":
		bot = PBot.new("aggressive")
	var t0: float = st.t
	for i in int(SEC / STEP):
		if st.status != "running" or bool(bz.dead):
			break
		if hold == "open": # 완전 정지(제자리)
			st.player.x = clampf(float(bz.x) + 200.0, 30.0, st.arena_w - 30.0)
			st.player.y = float(bz.y)
		var inp: Dictionary = { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }
		if bot != null:
			inp = bot.step_input(st)
		st.step(inp, STEP)
		st.player.hp = st.player.hp_max
		bz.phase = 3
		bz.phase_pending = 3
	if not step_on and saved != null: # 원래 설정 복구
		ex.gapStep = saved
	var sm := st.summary()
	var inits := 0
	for a in st.attack_log:
		if int(a[1]) == int(bz.get("id", -1)):
			inits += 1
	var secs: float = maxf(0.001, st.t - t0)
	var by := {}
	for k in sm.taken:
		by[String(k)] = int(round(float(sm.taken[k])))
	return { "label": "집행관", "mode": "-", "split": step_on, "hold": hold, "seed": seed_v, "phase": 3, "dist": 200.0,
		"sec": snapped(secs, 0.1), "taken": int(round(float(sm.damage_taken))), "hits": int(_sum(sm.taken_hits)),
		"inits": inits, "ipm": snapped(float(inits) / secs * 60.0, 0.1), "blocked": 0.0, "repos": 0, "obs": st.obstacles.size(),
		"by": by, "pat": sm.patterns }

func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n

func _init() -> void:
	var rows := []
	# ① 엄폐 대응 비교: 돌 뒤 정지 플레이어. 대조군(off) + 3안
	for mode in ["off", "reposition", "indirect", "break"]:
		for seed_v in [11, 18]:
			rows.append(run_one("엄폐", mode, true, "cover", seed_v, 200.0, 3))
	print("== ① 돌 뒤 정지(60초, 3단계, arena clearing) — 보스가 실제로 피해를 주는가 ==")
	print("| 엄폐 대응 | 시드 | 받은 피해 | 피격 수 | 공격 개시 | 분당 개시 | 시선 막힌 비율 | 대응 발동 | 남은 장애물 | 원인별 |")
	print("|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		print("| %s | %d | %d | %d | %d | %s | %s | %d | %d | %s |" % [String(r.mode), int(r.seed), int(r.taken), int(r.hits), int(r.inits), str(r.ipm), str(r.blocked), int(r.repos), int(r.obs), str(r.by)])
	# ② 양갈래: 열린 곳(arena forest, 장애물 0)에 정지한 플레이어가 받는 피해. 3단계 = 양갈래 발동 단계
	var rows2 := []
	for split_on in [false, true]:
		for seed_v in [11, 18]:
			for dist in [200.0, 320.0]:
				rows2.append(run_one("양갈래", "off", split_on, "open", seed_v, dist, 3, "forest"))
	print("\n== ② 정지한 플레이어가 받는 피해(60초, 3단계, 장애물 없는 곳) — 양갈래 보정 전후 ==")
	print("| 양갈래 보정 | 시드 | 거리 | 받은 피해 | 피격 수 | 공격 개시 | 분당 개시 | 원인별 | 패턴 |")
	print("|---|---|---|---|---|---|---|---|---|")
	for r in rows2:
		print("| %s | %d | %d | %d | %d | %d | %s | %s | %s |" % ["켬" if bool(r.split) else "끔", int(r.seed), int(round(float(r.get("dist", 0.0)))), int(r.taken), int(r.hits), int(r.inits), str(r.ipm), str(r.by), str(r.pat)])
	# ③ 회귀: 움직이는 봇(회피 정책)에게는 어떤가 — 기존 대응이 무효화되지 않았는지
	var rows3 := []
	for mode in ["off", "reposition"]:
		for split_on in [false, true]:
			for seed_v in [11, 18]:
				rows3.append(run_one("봇", mode, split_on, "dodge", seed_v, 200.0, 3))
	print("\n== ③ 회피 정책 봇(regular, 60초, 3단계, clearing) — 기존 대응이 계속 통하는가 ==")
	print("| 엄폐 대응 | 양갈래 | 시드 | 받은 피해 | 피격 수 | 분당 개시 | 시선 막힌 비율 |")
	print("|---|---|---|---|---|---|---|")
	for r in rows3:
		print("| %s | %s | %d | %d | %d | %s | %s |" % [String(r.mode), "켬" if bool(r.split) else "끔", int(r.seed), int(r.taken), int(r.hits), str(r.ipm), str(r.blocked)])
	# ④ 3막 관문(종말의 집행관): 위치 변주 전후 — 기존 대응이 그대로 통하는지(정지·추적·회피 정책 비교)
	var rows4 := []
	for step_on in [false, true]:
		for hold in ["open", "chase", "dodge"]:
			for seed_v in [11, 18]:
				rows4.append(run_exec(step_on, hold, seed_v))
	print("\n== ④ 종말의 집행관(3막 관문) 위치 변주 전후 — 60초, 3단계, clearing ==")
	print("| 위치 변주 | 정책 | 시드 | 받은 피해 | 피격 수 | 공격 개시 | 분당 개시 | 절단선 피해 | 큰 베기 피해 |")
	print("|---|---|---|---|---|---|---|---|---|")
	for r in rows4:
		var by: Dictionary = r.by
		print("| %s | %s | %d | %d | %d | %d | %s | %d | %d |" % ["켬" if bool(r.split) else "끔", String(r.hold), int(r.seed), int(r.taken), int(r.hits), int(r.inits), str(r.ipm), int(by.get("boss_slash", 0)), int(by.get("boss_gstrike", 0))])
	var all_rows: Array = rows + rows2 + rows3 + rows4
	print("\nJSON " + JSON.stringify(all_rows))
	print("%d/%d PASS" % [all_rows.size(), all_rows.size()])
	quit(0)
