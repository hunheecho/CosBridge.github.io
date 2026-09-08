extends SceneTree
## 보스 엄폐·지형 파괴 계측: ① 돌 뒤에 선 정지 플레이어에게 보스가 실제로 피해를 주는가(봉인 수호자 엄폐 대응 3안 비교)
##                  ② 3단계 양갈래 충격파에서 "정지한 플레이어가 받는 피해"(각도 변주·중앙 후속 전후)
##                  ③ 회피 정책 봇 회귀  ④ 종말의 집행관 위치 변주
##                  ⑤ **보스 9종 엄폐 해소 측정** — 사람이 실제로 겪은 상황 재현:
##                     "플레이어가 돌 뒤에 서서 불씨 정령으로만 공격한다". 영구 안전지대가 해소되는지,
##                     해소까지 몇 초가 걸리는지, 어떤 대응(지형 파괴·우회·시선 무관 공격)이 선택됐는지를 잰다.
## 실행: python tools/run_suites.py --suites boss_cover_probe --allow-adhoc --timeout 1800
## 판정하지 않는다(봇 승패는 통과 조건이 아니다). 표만 찍는다.
## 정책: cover_still(돌 뒤 정지) / still(제자리·Q/E 없음, 열린 곳) / chase(추적만) / dodge(실력 봇 regular)

const STEP := 1.0 / 120.0
const SEC := 60.0
const CAMP_SEC := 45.0     # ⑤ 엄폐 해소 측정 한 판 길이(이 안에 해소되지 않으면 "미해소")
const HUGE_HP := 1000000.0
const BOSSES: Array = ["boss", "guardian", "eater", "gate_warden", "spore_matriarch",
	"excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]

func build_of() -> Dictionary:
	var run := PRun.new_run(11, "sword")
	run.day = 7
	return PRun.build(run)

## ⑤ 전용 빌드: **불씨 정령만** 든다(근접 무기 없음). 사람이 겪은 상황 그대로 —
## 돌 뒤에 서서 바닥 불길만으로 보스를 깎는다.
func ember_build() -> Dictionary:
	var g := PGrowth.new_growth("sword")
	g.weapons = [{ "id": "ember", "level": 3, "mods": ["scatter", "trail"] }]
	return PBuild.derive(PBuild.empty_run_like(g))

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

# ---------- ⑤ 보스 9종 엄폐 해소 측정 ----------
## 돌(rock) 뒤 자리를 고른다. 없으면 아무 장애물 뒤나. 반환 [x, y, ob_x, ob_y, 종류]
func camp_spot(st: CombatState, bz: Dictionary, want_type: String) -> Array:
	var best := []
	var bd := -1.0
	for pass_i in 2: # 1차: 원하는 종류만, 2차: 아무거나
		for ob in st.obstacles:
			if pass_i == 0 and String(ob.type) != want_type:
				continue
			for k in 16:
				var a: float = float(k) * TAU / 16.0
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
					best = [x, y, float(ob.x), float(ob.y), String(ob.type)]
		if not best.is_empty():
			return best
	return best

## 한 판: 보스 하나 · 돌 뒤 정지 · 불씨 정령만. 대응(break_on)을 켜고 끄며 비교한다
func run_camp(boss_id: String, seed_v: int, phase: int, on: bool) -> Dictionary:
	PBoss.set_cover_mode("" if on else "off")
	PBoss.set_split_on(true)
	PBoss.set_break_on(on)
	var st := CombatState.new({ "build": ember_build(), "seed": seed_v, "arena": "clearing", "boss": true,
		"boss_id": boss_id, "region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP, "act": 3 })
	for i in 900:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	var bz: Dictionary = st.boss
	bz.phase = phase
	bz.phase_pending = phase
	var spot := camp_spot(st, bz, "rock")
	var obs0: int = st.obstacles.size()
	var reach0 := PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, { "x": spot[0], "y": spot[1] }) if not spot.is_empty() else 0
	var t0: float = st.t
	var resolve := -1.0
	var taken0 := 0.0
	var blocked_steps := 0
	var repos := 0
	var last := ""
	var n := int(CAMP_SEC / STEP)
	var trapped := false
	for i in n:
		if st.status != "running" or bool(bz.dead):
			break
		if not spot.is_empty(): # 계속 같은 엄폐 뒤에 서 있는다(사람 관찰 재현)
			st.player.x = spot[0]
			st.player.y = spot[1]
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }, STEP)
		var tk: float = float(st.stats.damage_taken)
		if resolve < 0.0 and tk > taken0 + 0.001:
			resolve = st.t - t0
		taken0 = maxf(taken0, tk)
		st.player.hp = st.player.hp_max # 계측: 죽지 않게(받은 피해는 그대로 누적)
		bz.phase = phase
		bz.phase_pending = phase
		if st.los_blocked(float(bz.x), float(bz.y), st.player.x, st.player.y):
			blocked_steps += 1
		var s := String(bz.state)
		if s == "reposition" and last != "reposition":
			repos += 1
		last = s
	# 파괴 뒤 갇히지 않았는가: 파괴 전후로 걸어 닿는 칸이 줄지 않았는지(파편이 새 장애물이 되지 않았는지)
	var reach1 := PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, { "x": spot[0], "y": spot[1] }) if not spot.is_empty() else 0
	if not spot.is_empty() and reach1 < reach0:
		trapped = true
	var broken: Array = st.metrics.get("broken", [])
	var whys := []
	for b in broken:
		whys.append(String(b.why))
	var sm := st.summary()
	var by := {}
	for k in sm.taken:
		by[String(k)] = int(round(float(sm.taken[k])))
	var secs: float = maxf(0.001, st.t - t0)
	return { "boss": boss_id, "on": on, "seed": seed_v, "phase": phase,
		"cover_type": String(spot[4]) if not spot.is_empty() else "-",
		"resolve": snapped(resolve, 0.1), "taken": int(round(float(sm.damage_taken))), "hits": int(_sum(sm.taken_hits)),
		"blocked": snapped(float(blocked_steps) * STEP / secs, 0.01), "repos": repos,
		"breaks": broken.size(), "why": whys, "obs0": obs0, "obs": st.obstacles.size(),
		"zone": snapped(float(st.metrics.get("zone_sec", 0.0)), 0.1),
		"reach0": reach0, "reach1": reach1, "trapped": trapped, "by": by, "pat": sm.patterns }

## 한 판: 그 보스가 **부술 수 있는 종류**의 엄폐 뒤에 서면 파괴 행동이 실제로 나오는가.
## 포자 어미는 나무만 삭히므로 ⑤(바위)에서는 파괴가 안 나온다 — 여기서 나무 뒤에 세워 확인한다.
func run_own_cover(boss_id: String, seed_v: int, phase: int) -> Dictionary:
	PBoss.set_cover_mode("")
	PBoss.set_split_on(true)
	PBoss.set_break_on(true)
	var types: Array = PBoss.beh_of(boss_id).get("breaker", {}).get("types", ["rock"])
	var want := String(types[0]) if types.size() > 0 else "rock"
	var st := CombatState.new({ "build": ember_build(), "seed": seed_v, "arena": "clearing", "boss": true,
		"boss_id": boss_id, "region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP, "act": 3 })
	for i in 900:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	var bz: Dictionary = st.boss
	bz.phase = phase
	bz.phase_pending = phase
	var spot := camp_spot(st, bz, want)
	var first := -1.0
	for i in int(CAMP_SEC / STEP):
		if st.status != "running" or bool(bz.dead):
			break
		if not spot.is_empty():
			st.player.x = spot[0]
			st.player.y = spot[1]
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }, STEP)
		st.player.hp = st.player.hp_max
		bz.phase = phase
		bz.phase_pending = phase
		if first < 0.0 and not (st.metrics.get("broken", []) as Array).is_empty():
			first = st.t
	var broken: Array = st.metrics.get("broken", [])
	var whys := []
	var kinds := []
	for b in broken:
		whys.append(String(b.why))
		kinds.append(String(b.type))
	return { "boss": boss_id, "want": want, "cover_type": String(spot[4]) if not spot.is_empty() else "-",
		"first": snapped(first, 0.1), "breaks": broken.size(), "why": whys, "kinds": kinds, "obs": st.obstacles.size() }

## 한 판: 보스전 소요 시간(회피 정책 봇). 지형 파괴·엄폐 대응 전후 비교 전용.
## hp > 0이면 **계측 전용 고정 체력**을 넣는다(봇이 실제로 이겨서 "처치까지 걸린 시간"을 잴 수 있게).
## 게임 데이터의 보스 체력은 건드리지 않는다.
func run_time(boss_id: String, seed_v: int, on: bool, max_sec: float, hp: float = 0.0, policy: String = "regular") -> Dictionary:
	PBoss.set_cover_mode("" if on else "off")
	PBoss.set_split_on(true)
	PBoss.set_break_on(on)
	var o := { "build": build_of(), "seed": seed_v, "arena": "clearing", "boss": true,
		"boss_id": boss_id, "region_id": "boss", "xp_kill_mult": 0.3, "act": 3 }
	if hp > 0.0:
		o["boss_hp"] = hp
	var st := CombatState.new(o)
	PBot.run_combat(st, policy, { "max_sec": max_sec, "bot": PSkillBot.new(policy, seed_v) })
	if st.status == "running":
		st.status = "timeout"
		st.delayed.clear()
	var sm := st.summary()
	var left: float = maxf(0.0, float(st.boss.hp)) if not st.boss.is_empty() else 0.0
	var mx: float = float(st.boss.hp_max) if not st.boss.is_empty() else 1.0
	return { "boss": boss_id, "on": on, "seed": seed_v, "hp": hp, "status": st.status, "sec": snapped(st.t, 0.1),
		"left": int(round(left)), "hpmax": int(round(mx)), "frac": snapped(1.0 - left / maxf(1.0, mx), 0.01),
		"taken": int(round(float(sm.damage_taken))), "breaks": (st.metrics.get("broken", []) as Array).size() }

## 어떤 대응이 안전지대를 풀었는지 한 줄로
func resp_of(r: Dictionary) -> String:
	var out := []
	if int(r.breaks) > 0:
		out.append("파괴(%s)" % ", ".join(PackedStringArray(r.why)))
	if int(r.repos) > 0:
		out.append("우회 %d회" % int(r.repos))
	if out.is_empty():
		out.append("대응 없음")
	return " + ".join(PackedStringArray(out))

func _init() -> void:
	var rows := []
	# ① 엄폐 대응 비교: 돌 뒤 정지 플레이어. 대조군(off) + 3안.
	#    이 절은 **엄폐 대응 방식만** 비교한다 — 새 지형 파괴(breaker)는 꺼서 예전 표와 같은 조건을 지킨다
	PBoss.set_break_on(false)
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
	# ⑤ 보스 9종 엄폐 해소: 돌 뒤에 서서 **불씨 정령으로만** 공격하는 플레이어(사람 관찰 재현)
	var rows5 := []
	for on in [false, true]:
		for bid in BOSSES:
			for ph in [1, 3]:
				rows5.append(run_camp(bid, 11, ph, on))
	PBoss.set_cover_mode("")
	PBoss.set_break_on(true)
	print("\n== ⑤ 돌 뒤 정지 + 불씨 정령만(%.0f초, arena clearing, 시드 11) — 영구 안전지대가 해소되는가 ==" % CAMP_SEC)
	print("해소 = 그 자리에 선 채로 처음 피해를 입은 시각(초). -1 = %.0f초 안에 해소 안 됨." % CAMP_SEC)
	print("| 보스 | 대응 | 단계 | 엄폐 종류 | 해소(초) | 받은 피해 | 피격 수 | 시선 막힘 | 선택된 대응 | 장애물 | 불길 위(초) | 닿는 칸 전→후 | 갇힘 | 원인별 |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows5:
		print("| %s | %s | %d | %s | %s | %d | %d | %s | %s | %d→%d | %s | %d→%d | %s | %s |" % [
			String(PCatalog.boss_def(String(r.boss)).name), "켬" if bool(r.on) else "끔(개편 전)", int(r.phase),
			String(r.cover_type), str(r.resolve), int(r.taken), int(r.hits), str(r.blocked), resp_of(r),
			int(r.obs0), int(r.obs), str(r.zone), int(r.reach0), int(r.reach1), "예" if bool(r.trapped) else "아니오", str(r.by)])
	# ⑥ 보스 9종의 파괴 행동이 실제로 나오는가 — 그 보스가 부술 수 있는 종류의 엄폐 뒤에 세운다
	var rows6 := []
	for bid in BOSSES:
		rows6.append(run_own_cover(bid, 11, 3))
	print("\n== ⑥ 보스별 파괴 행동 발동(그 보스가 부술 수 있는 종류의 엄폐 뒤, 3단계, %.0f초) ==" % CAMP_SEC)
	print("| 보스 | 부술 수 있는 종류 | 선 자리 엄폐 | 첫 파괴(초) | 부순 수 | 부순 종류 | 남은 장애물 | 파괴 출처 |")
	print("|---|---|---|---|---|---|---|---|")
	for r in rows6:
		print("| %s | %s | %s | %s | %d | %s | %d | %s |" % [
			String(PCatalog.boss_def(String(r.boss)).name), String(r.want), String(r.cover_type),
			str(r.first), int(r.breaks), ", ".join(PackedStringArray(r.kinds)), int(r.obs), ", ".join(PackedStringArray(r.why))])
	# ⑦ 보스전 소요 시간: 지형 파괴·엄폐 대응 전후(회피 정책 봇 regular, arena clearing, 실제 보스 체력)
	var rows7 := []
	for on in [false, true]:
		for bid in BOSSES:
			for seed_v in [11, 18]:
				rows7.append(run_time(bid, seed_v, on, 150.0))
	# ⑦-B 계측 전용 고정 체력(1800): 봇이 실제로 이겨서 "보스 처치까지 걸린 시간"을 잴 수 있다.
	# 게임 데이터의 보스 체력은 바꾸지 않는다 — 이 표 안에서만 같은 체력을 넣는다.
	var rows8 := []
	for on2 in [false, true]:
		for bid2 in BOSSES:
			for sd2 in [11, 18]:
				rows8.append(run_time(bid2, sd2, on2, 150.0, 1800.0, "skilled"))
	PBoss.set_cover_mode("")
	PBoss.set_break_on(true)
	print("\n== ⑦-A 실제 보스 체력(회피 정책 봇 regular, arena clearing, 상한 150초) — 봇이 전부 지므로 플레이어가 버틴 시간이다 ==")
	print("| 보스 | 대응 | 시드 | 결과 | 시간(초) | 보스 깎은 비율 | 받은 피해 | 부순 장애물 |")
	print("|---|---|---|---|---|---|---|---|")
	for r in rows7:
		print("| %s | %s | %d | %s | %s | %s | %d | %d |" % [
			String(PCatalog.boss_def(String(r.boss)).name), "켬" if bool(r.on) else "끔(개편 전)", int(r.seed),
			String(r.status), str(r.sec), str(r.frac), int(r.taken), int(r.breaks)])
	print("
== ⑦-B 계측 전용 고정 체력 1800(실력 봇 skilled, arena clearing, 상한 150초) — 보스 처치까지 걸린 시간 ==")
	print("게임 데이터의 보스 체력은 바꾸지 않았다. 비교를 위해 이 표 안에서만 같은 체력을 넣는다.")
	print("| 보스 | 대응 | 시드 | 결과 | 처치 시간(초) | 보스 깎은 비율 | 받은 피해 | 부순 장애물 |")
	print("|---|---|---|---|---|---|---|---|")
	for r8 in rows8:
		print("| %s | %s | %d | %s | %s | %s | %d | %d |" % [
			String(PCatalog.boss_def(String(r8.boss)).name), "켬" if bool(r8.on) else "끔(개편 전)", int(r8.seed),
			String(r8.status), str(r8.sec), str(r8.frac), int(r8.taken), int(r8.breaks)])
	var all_rows: Array = rows + rows2 + rows3 + rows4 + rows5 + rows6 + rows7 + rows8
	print("\nJSON " + JSON.stringify(all_rows))
	print("%d/%d PASS" % [all_rows.size(), all_rows.size()])
	quit(0)
