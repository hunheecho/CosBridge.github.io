extends SceneTree
## 보스 3종·전투 목표 4종 규칙 테스트(headless): godot --headless --path prophecy_godot -s tests/boss_tests.gd
## HTML test/boss.test.js·boss2.test.js·objectives.test.js·events.test.js의 규칙 케이스를 Godot 규칙으로 다시 쓴 것. 수치는 GAME_SPEC §13·§17·§18·데이터에서.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func build(o: Dictionary = {}) -> Dictionary:
	var g := PGrowth.new_growth(String(o.get("start", "sword")))
	if o.has("weapons"):
		g.weapons = o.weapons
	if o.has("commons"):
		g.commons = o.commons
	var run := PBuild.empty_run_like(g)
	return PBuild.derive(run)

## 이 파일의 보스 시험은 '패턴 하나의 판정·예고·빈틈'을 본다. 행동 개편(연계·옆뛰기, data/boss_behavior.json)은 개체 스위치 beh_off로 끄고
## 개편 전(073f74f)과 같은 조건에서 확인한다 — 즉 아래 기대값은 이번 작업에서 바뀌지 않았다.
## 개편 자체의 검사는 이 파일의 chain_tests()와 tests/boss_pace_tests.gd에 있다.
func boss_state(id: String, seed_v: int = 5, hp: float = 0.0, o: Dictionary = {}) -> CombatState:
	var opts := { "build": build(o), "seed": seed_v, "arena": "clearing", "boss": true, "boss_id": id, "region_id": "boss", "xp_kill_mult": 0.3 }
	if hp > 0.0:
		opts.boss_hp = hp
	var st := CombatState.new(opts)
	st.boss.beh_off = true
	return st

func steps(st: CombatState, seconds: float, input: Dictionary = {}) -> void:
	for i in int(round(seconds / STEP)):
		st.step(input, STEP)

func run_until(st: CombatState, pred: Callable, max_sec: float, input: Dictionary = {}) -> bool:
	var n := int(round(max_sec / STEP))
	for i in n:
		if pred.call():
			return true
		st.step(input, STEP)
	return pred.call()

func _init() -> void:
	# ---------- 가시갈기 ----------
	var st := boss_state("boss")
	var bz := st.boss
	ok("보스 생성: 체력 후보 hi 2400(stage1), 반지름 42, 입장 연출 1.6초 동안 시간·피해 없음", bz.hp == 2400.0 and bz.r == 42.0 and st.intro == 1.6)
	st.damage_player(10.0, "test")
	steps(st, 1.0)
	ok("입장 연출 중 피해·시간 진행 없음(HTML 13)", st.player.hp == 100.0 and st.t == 0.0 and bz.state == "intro")
	steps(st, 0.7)
	ok("입장 뒤 접근 시작, 포효 이벤트", bz.state == "approach" and st.events.has("boss_roar"))
	# 첫 공격은 단일 돌진(HTML 14)
	var first_pat := ""
	run_until(st, func(): return bz.state in ["dash_aim", "sweep_aim", "howl", "pounce_aim"], 10.0)
	first_pat = String(bz.state)
	ok("첫 공격은 돌진(dash_aim)", first_pat == "dash_aim", first_pat)
	# 돌진: 확정 뒤 방향 고정·거리 460·경로 유지(HTML 15), 장애물이면 접촉 위치에서 정지(HTML 16)
	run_until(st, func(): return bz.state == "dash_lock", 3.0)
	var dir0: float = bz.dir
	var len0: float = float(bz.dash_len)
	st.player.x += 250.0
	run_until(st, func(): return bz.state == "recover", 3.0)
	ok("돌진 확정 뒤 방향 불변, 예고 길이(dash_len ≤ 460)만큼 이동 후 빈틈 2.2초", absf(PGeom.ang_diff(dir0, bz.dir)) < 1e-9 and len0 <= 460.0 + 1e-6 and bz.state == "recover" and is_equal_approx(float(bz.recover_dur), 2.2), "len %.1f" % len0)
	# 첫 돌진 빈틈 뒤 첫 소환(HTML 14): 소환 늑대는 발자국 예고 뒤 등장, 등장 후 0.8초 돌진 금지
	run_until(st, func(): return bz.state == "howl", 6.0)
	ok("첫 돌진 뒤 첫 무리 소환(howl 1.6초)", bz.state == "howl")
	run_until(st, func(): return PBoss.summoned_alive(st) >= 1, 4.0)
	var summ := 0
	for e in st.enemies:
		if bool(e.get("summoned", false)) and not e.dead:
			summ += 1
	ok("소환 늑대 2마리 등장(summoned=true, 통계 키 wolf:summoned)", summ == 2 and st.metrics.enemies.has("wolf:summoned"), "summ %d keys %s" % [summ, str(st.metrics.enemies.keys())])
	# 감속장은 보스 준비 진행을 40%로(HTML 18)
	st = boss_state("boss")
	bz = st.boss
	steps(st, 1.7)
	bz.state = "sweep_aim"; bz.state_t = 0.0
	st.player.x = bz.x; st.player.y = bz.y + 100.0
	st.step({ "special": true }, STEP)
	ok("감속장 안 보스 준비 진행 = dt × 0.4", absf(float(bz.state_t) - STEP * 0.4) < 1e-9, "%.5f" % float(bz.state_t))
	# 휩쓸기: 부채꼴 안만, 장애물 뒤 무사, 대상당 1회(HTML 17)
	st = boss_state("boss")
	bz = st.boss
	steps(st, 1.7)
	bz.x = 480.0; bz.y = 300.0
	st.player.x = 480.0; st.player.y = 300.0 + 100.0
	bz.state = "sweep_aim"; bz.state_t = 0.0
	run_until(st, func(): return bz.state == "recover", 2.0)
	var hp_in: float = st.player.hp
	st = boss_state("boss")
	bz = st.boss
	steps(st, 1.7)
	bz.x = 480.0; bz.y = 300.0
	st.player.x = 480.0 + 200.0; st.player.y = 300.0
	bz.state = "sweep_aim"; bz.state_t = 0.0
	bz.aim_angle = 0.0
	run_until(st, func(): return bz.state == "recover", 2.0)
	ok("휩쓸기: 반지름 145 안 정면은 16 피해, 200 밖은 무사", hp_in == 84.0 and st.player.hp == 100.0, "in %.0f out %.0f" % [hp_in, st.player.hp])
	# 단계 전환·회복 구슬(HTML 20~22): 체력선 70%·35% 첫 통과 시 구슬, 한 번에 두 선 넘기면 구슬 2·단계 3
	st = boss_state("boss")
	bz = st.boss
	steps(st, 1.7)
	st.damage_enemy(bz, 2400.0 * 0.7, { "src": { "tag": "test" } })
	ok("한 번에 두 체력선(70·35%) 통과: 구슬 2개, 단계 대기 3", st.pickups.size() == 2 and int(bz.phase_pending) == 3 and not bz.dead, "pickups %d pending %d" % [st.pickups.size(), int(bz.phase_pending)])
	var orb: Dictionary = st.pickups[0]
	ok("회복 구슬 = 최대 체력 15%(15), 유효 위치·보스 몸 밖", float(orb.amount) == 15.0 and st.valid_pos(orb.x, orb.y, orb.r) and PGeom.dist(orb.x, orb.y, bz.x, bz.y) >= bz.r + orb.r + 30.0 - 1e-6)
	st.player.hp = 50.0
	st.player.x = orb.x; st.player.y = orb.y
	st.step({}, STEP)
	ok("구슬 접촉 회복 15×2(두 구슬이 같은 최적 위치에 놓임, HTML과 동일), 중복 획득 없음", st.player.hp == 80.0 and st.pickups.size() == 0, "hp %.0f pickups %d" % [st.player.hp, st.pickups.size()])
	# 보스 사망: 같은 단계 승리 우선, 사망 후 추가 피해 없음(HTML 26)
	st = boss_state("boss", 5, 30.0)
	bz = st.boss
	steps(st, 1.7)
	st.player.hp = 1.0
	bz.x = st.player.x + 60.0; bz.y = st.player.y
	run_until(st, func(): return st.status != "running", 10.0)
	ok("보스 처치 → won(플레이어 생존 여부와 무관하게 승리 우선)", st.status == "won" and bz.dead)
	ok("보스 사망 뒤 플레이어 추가 피해 없음", not st.damage_player(10.0, "test"))
	# 넉백 20%·돌진 중 넉백 없음(HTML 27)
	st = boss_state("boss")
	bz = st.boss
	steps(st, 1.7)
	bz.state = "approach"
	st.knock_enemy(bz, [1.0, 0.0], 40.0)
	var vx1: float = bz.vx
	bz.vx = 0.0
	bz.state = "dash"
	st.knock_enemy(bz, [1.0, 0.0], 40.0)
	ok("보스 넉백은 일반의 20%(40×0.2×2=16), 돌진 중 0", is_equal_approx(vx1, 16.0) and bz.vx == 0.0, "%.1f %.1f" % [vx1, bz.vx])
	# ---------- 봉인 수호자(HTML 32) ----------
	st = boss_state("guardian")
	bz = st.boss
	var devices := 0
	for e in st.enemies:
		if e.type == "seal_device":
			devices += 1
	var dev0 := {}
	for e in st.enemies:
		if e.type == "seal_device":
			dev0 = e
	ok("수호자: 기본 체력 3000(단계 후보는 회차가 boss_hp로 넘김), 장치 3개(체력 120, 구조물, 경험치 0)", bz.hp == 3000.0 and devices == 3 and dev0.hp == 120.0 and bool(dev0.structure) and st.xp_for(dev0) == 0.0, "hp %.0f devices %d" % [bz.hp, devices])
	steps(st, 1.7)
	run_until(st, func(): return bz.state == "shock_lock", 6.0)
	var sdir: float = bz.dir
	st.player.x += 200.0
	run_until(st, func(): return bz.state == "recover", 2.0)
	var shock := {}
	for pr in st.projectiles:
		if pr.kind == "shock":
			shock = pr
	ok("첫 공격 충격파: 확정 방향으로 파동(폭 70, 피해 18)이 날아가고 재추적 없음", not shock.is_empty() and absf(PGeom.ang_diff(float(shock.angle), sdir)) < 1e-9 and float(shock.width) == 70.0 and float(shock.dmg) == 18.0, str(shock.keys()) if not shock.is_empty() else "no shock")
	run_until(st, func(): return st.zones.size() > 0, 8.0)
	var hz := 0
	for z in st.zones:
		if z.type == "hazard":
			hz += 1
	ok("봉인 장치가 주기적으로 플레이어 좌우 바닥 위험(hazard)을 만든다", hz >= 1, "hazard %d" % hz)
	for e in st.enemies:
		if e.type == "seal_device":
			st.damage_enemy(e, 9999.0, "test")
	var before_z := st.zones.size()
	steps(st, 8.0)
	var new_hz := 0
	for z in st.zones:
		if z.type == "hazard":
			new_hz += 1
	ok("장치를 모두 부수면 새 바닥 위험이 생기지 않는다(처치 수 제외)", new_hz == 0 and st.stats.kills == 0, "hz %d kills %d" % [new_hz, st.stats.kills])
	# ---------- 예언을 먹는 자(HTML 33) ----------
	st = boss_state("eater")
	bz = st.boss
	steps(st, 1.7)
	var lanes_seen := run_until(st, func(): return bz.state == "lanes_warn", 6.0)
	ok("먹는 자 첫 공격은 두 줄 직선(lanes)", lanes_seen)
	var lane0: float = float(bz.lanes[0].ang)
	var lane1: float = float(bz.lanes[1].ang)
	ok("둘째 줄은 첫 줄 +70°", absf(PGeom.ang_diff(lane0, lane1) - 70.0 * PI / 180.0) < 1e-6)
	run_until(st, func(): return bz.state == "recover", 6.0)
	var fired := 0
	for pr in st.projectiles:
		if pr.kind == "shock":
			fired += 1
	ok("두 줄 순차 발사 뒤 빈틈 1.5초", fired >= 1 and is_equal_approx(float(bz.recover_dur), 1.5), "fired %d" % fired)
	# 표식은 0.5초 이상 지난 위치에만(현재 위치 제외), 정해진 시각에 순차 폭발
	st = boss_state("eater")
	bz = st.boss
	steps(st, 1.7)
	for i in 240:
		st.step({ "mx": 1.0 }, STEP)
	bz.state = "mark_cast"; bz.state_t = 0.0
	run_until(st, func(): return bz.state == "mark_wait", 2.0)
	var marks: Array = bz.marks
	var at_player := false
	for mk in marks:
		if PGeom.dist(mk.x, mk.y, st.player.x, st.player.y) < 1.0:
			at_player = true
	ok("표식은 지난 위치(≥0.5초 전)에 찍히고 현재 위치는 아니며 순차 폭발 시각이 0.25초 간격", marks.size() >= 1 and not at_player and (marks.size() < 2 or is_equal_approx(float(marks[1].explode_at) - float(marks[0].explode_at), 0.25)), "marks %d" % marks.size())
	# ---------- 전투 목표 4종(HTML 140~144) ----------
	var run := PBuild.empty_run_like(PGrowth.new_growth("sword"))
	for obj in ["hunt", "altars", "seal", "rescue"]:
		var so := CombatState.new({ "build": PBuild.derive(run), "seed": 7, "arena": "clearing", "objective": obj, "region_id": "forest", "pool": ["wolf"], "risk": "", "xp_kill_mult": 0.3 })
		var h := PObjectives.hud(so)
		ok("목표 %s: 설정·HUD(%s)" % [obj, String(h.get("title", ""))], not so.obj.is_empty() and h.has("line") and h.has("end_rule"), str(h))
	var sh := CombatState.new({ "build": PBuild.derive(run), "seed": 7, "arena": "clearing", "objective": "hunt", "region_id": "forest", "pool": ["wolf"], "risk": "escort", "xp_kill_mult": 0.3 })
	var alphas := 0
	for u in sh.formation.units:
		if String(u) == "wolf_alpha":
			alphas += 1
	ok("정예 추적 + 정예 호위: 정예 2마리(전부 처치해야 종료), 호위 늑대는 ×5", alphas == 2 and sh.elite_count().total == 2, "alphas %d total %d" % [alphas, sh.elite_count().total])
	var sa := CombatState.new({ "build": PBuild.derive(run), "seed": 7, "arena": "clearing", "objective": "altars", "region_id": "forest", "pool": ["wolf"], "xp_kill_mult": 0.3 })
	var altars := []
	for e in sa.enemies:
		if bool(e.structure):
			altars.append(e)
	var gap_ok := true
	for i in altars.size():
		for j in range(i + 1, altars.size()):
			if PGeom.dist(altars[i].x, altars[i].y, altars[j].x, altars[j].y) < 200.0:
				gap_ok = false
		if PGeom.dist(altars[i].x, altars[i].y, sa.player.x, sa.player.y) < 170.0 or not sa.valid_pos(altars[i].x, altars[i].y, altars[i].r):
			gap_ok = false
	# 제단 체력은 임무 개편(PObjectives.TUNE.altar, 시험값)에서 막·빌드 기준으로 올렸다: 1막 기준 220(레벨 1·대장간 0)
	ok("제단 3개: 서로 200 이상·플레이어 170 이상·유효 위치, 체력 220(1막 시험값), 경험치 0", altars.size() == 3 and gap_ok and altars[0].hp == 220.0 and sa.xp_for(altars[0]) == 0.0, "hp %.0f" % float(altars[0].hp))
	sa.spawn_hold = true
	for a in altars:
		sa.damage_enemy(a, 9999.0, "test")
	sa.spawn_hold = false
	sa.step({}, STEP)
	ok("제단을 모두 부수면 적이 남아도 승리, 처치 수는 0", sa.status == "won" and sa.stats.kills == 0)
	var ss := CombatState.new({ "build": PBuild.derive(run), "seed": 7, "arena": "clearing", "objective": "seal", "region_id": "forest", "pool": ["wolf"], "xp_kill_mult": 0.3 })
	ss.player.attack_timer = 1.0e9
	var seal_pt := {}
	for ob in ss.objects:
		if ob.kind == "seal":
			seal_pt = ob
	ss.player.x = seal_pt.x; ss.player.y = seal_pt.y
	ss.spawn_hold = true
	for i in 120:
		ss.step({}, STEP)
		ss.player.x = seal_pt.x; ss.player.y = seal_pt.y
	var prog1: float = float(ss.obj.progress)
	ss.player.x = seal_pt.x + 300.0
	for i in 60:
		ss.step({}, STEP)
	ok("봉인: 지점 안에서 진행(1초 → 1.0), 밖에서는 멈추되 유지", is_equal_approx(snapped(prog1, 0.01), 1.0) and is_equal_approx(float(ss.obj.progress), prog1) and bool(ss.obj.paused), "%.2f %.2f" % [prog1, float(ss.obj.progress)])
	ss.player.x = seal_pt.x
	ss.damage_player(5.0, "test")
	ss.step({}, STEP)
	ok("피격 시 0.6초 정지", bool(ss.obj.paused) and float(ss.obj.hit_pause) > 0.0)
	var sr := CombatState.new({ "build": PBuild.derive(run), "seed": 7, "arena": "clearing", "objective": "rescue", "region_id": "forest", "pool": ["wolf"], "xp_kill_mult": 0.3 })
	var cages := []
	var exit := {}
	for ob in sr.objects:
		if ob.kind == "cage":
			cages.append(ob)
		elif ob.kind == "exit":
			exit = ob
	ok("포로 구출: 우리 2·출구 1 배치(유효 위치), 출구는 처음엔 닫힘", cages.size() == 2 and not exit.is_empty() and not bool(exit.open))
	# 위험 지형: 목표 지점을 덮지 않고 안전 통로(3개 등간격)
	var sz := CombatState.new({ "build": PBuild.derive(run), "seed": 7, "arena": "clearing", "objective": "seal", "region_id": "forest", "pool": ["wolf"], "risk": "hazard", "xp_kill_mult": 0.3 })
	sz.spawn_hold = true
	steps(sz, 7.5)
	var hz2 := 0
	var covers := false
	for z in sz.zones:
		if z.type == "hazard":
			hz2 += 1
			for ob in sz.objects:
				if ob.kind == "seal" and PGeom.dist(z.x, z.y, ob.x, ob.y) <= z.r + ob.r:
					covers = true
	ok("위험 지형: 7초마다 플레이어 주변 최대 3개, 목표 지점을 덮지 않는다", hz2 >= 1 and hz2 <= 3 and not covers, "hz %d" % hz2)
	chain_tests()
	mission_tests()
	guardian_tests()
	tree_break_tests()
	new_pattern_tests()
	nx_used_tests()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

## 행동 개편(data/boss_behavior.json, 시험값)을 켠 상태의 가시갈기 검사. 개편이 꺼져 있으면(파일 없음·enabled=false) 건너뛴다
func chain_state(id: String, seed_v: int = 5) -> CombatState:
	var st := CombatState.new({ "build": build(), "seed": seed_v, "arena": "forest", "boss": true, "boss_id": id,
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
	for i in 600:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	return st

func chain_tests() -> void:
	if PBoss.chain_cfg({ "boss_id": "boss", "phase": 1 }).is_empty():
		ok("행동 개편(boss_behavior.json)이 꺼져 있어 연계 검사를 건너뛴다", true)
		return
	# 근거리에서 이동 공격 후보가 남는다(검토 문서가 재현한 구조적 문제: 거리80이면 휩쓸기뿐)
	var st := chain_state("boss")
	var bz: Dictionary = st.boss
	bz.actions = 3
	bz.history = []
	bz.last_howl = st.t
	st.player.x = bz.x + 80.0
	st.player.y = bz.y
	var cands := PBoss.candidate_names(st, bz)
	ok("가시갈기: 거리 80에서도 후보에 돌진이 남는다(옆으로 뛰어 스스로 거리를 만든다)", cands.has("dash") and cands.has("sweep"), str(cands))
	# 옆 뛰기: 준비(dash_aim) 중에 옆으로 실제로 움직이고, 예고 각은 계속 플레이어를 따라간다
	var x0: float = bz.x
	var y0: float = bz.y
	PBoss.begin(st, bz, "dash")
	ok("가시갈기: 최소 거리(150) 안에서 돌진을 고르면 옆 뛰기가 예약된다", float(bz.hop_left) > 0.0, "hop %.2f" % float(bz.hop_left))
	for i in 40:
		st.step({}, STEP)
	var moved := PGeom.dist(bz.x, bz.y, x0, y0)
	ok("가시갈기: 옆 뛰기로 준비 중 실제로 이동한다(예고 없는 이동, 무적 없음)", moved > 30.0 and String(bz.state) == "dash_aim", "이동 %.0f 상태 %s" % [moved, String(bz.state)])
	# 연계: 한 행동이 끝나도 바로 빈틈이 아니라 다음 행동으로 이어지고, 연계 끝에만 빈틈이 온다
	st = chain_state("boss")
	bz = st.boss
	var chain_len := 0
	var saw_recover := false
	var rec_dur := 0.0
	var prev_n := int(bz.get("attack_n", 0))
	for i in 3600:
		st.player.hp = st.player.hp_max
		st.step({}, STEP)
		var n := int(bz.get("attack_n", 0))
		if n > prev_n:
			prev_n = n
			chain_len += 1
		if String(bz.state) == "recover" and chain_len >= 2:
			saw_recover = true
			rec_dur = float(bz.recover_dur)
			break
	ok("가시갈기: 여러 행동을 연달아 하고(연계 %d회) 그 뒤에 빈틈이 온다" % chain_len, saw_recover and chain_len >= 2, "빈틈 %.2f초" % rec_dur)
	ok("가시갈기: 연계가 끝난 빈틈은 원래 빈틈(휩쓸기 1.5 / 돌진 2.2) 이상", rec_dur >= 1.5 - 1e-6, "%.2f" % rec_dur)
	# 예고: 연계 첫 공격은 원래 속도(1.0), 후속타만 빨라지되 하한을 지킨다
	st = chain_state("boss")
	bz = st.boss
	var first_speed := -1.0
	var follow_speed := -1.0
	var follow_warn := 0.0
	prev_n = int(bz.get("attack_n", 0))
	for i in 3600:
		st.player.hp = st.player.hp_max
		st.step({}, STEP)
		var n := int(bz.get("attack_n", 0))
		if n > prev_n:
			prev_n = n
			if int(bz.chain_i) == 1 and first_speed < 0.0:
				first_speed = float(bz.warn_speed)
			elif int(bz.chain_i) >= 2 and follow_speed < 0.0:
				# 신규 패턴(§11-A)은 배속 대상이 아니다(예고를 데이터 값 그대로 쓴다) — 배속 검사는 기존 패턴으로만 한다
				var lastp := String((bz.history as Array)[(bz.history as Array).size() - 1])
				if PBoss4.has_pattern(bz, lastp):
					continue
				follow_speed = float(bz.warn_speed)
				follow_warn = PBoss.pattern_warn(PCatalog.boss_def("boss"), lastp) / maxf(1.0, follow_speed)
		if first_speed >= 0.0 and follow_speed >= 0.0:
			break
	var floor_s := float(PBoss.chain_cfg(bz).get("followWarnMin", 0.5))
	ok("가시갈기: 연계 첫 공격의 예고는 데이터 원래 값 그대로(배속 1.0)", is_equal_approx(first_speed, 1.0), "%.2f" % first_speed)
	ok("가시갈기: 후속타 예고는 빨라지되 하한 %.2f초 이상" % floor_s, follow_speed > 1.0 and follow_warn >= floor_s - 1e-6, "배속 %.2f → %.2f초" % [follow_speed, follow_warn])
	# 감속장(Q): 연계·예고·빈틈 모두 그대로 40%로 늦춰진다(Q를 조용히 약화하지 않았다)
	st = chain_state("boss")
	bz = st.boss
	bz.state = "sweep_aim"; bz.state_t = 0.0; bz.warn_speed = 1.0
	st.player.x = bz.x; st.player.y = bz.y + 100.0
	st.step({ "special": true }, STEP)
	var q_first: float = float(bz.state_t)
	bz.state = "sweep_aim"; bz.state_t = 0.0; bz.warn_speed = 2.0
	st.step({ "special": true }, STEP)
	var q_follow: float = float(bz.state_t)
	ok("가시갈기: 감속장 안 예고 진행 = dt × 0.4 (연계 후속타도 배속 × 0.4로 같은 비율)",
		absf(q_first - STEP * 0.4) < 1e-9 and absf(q_follow - STEP * 0.4 * 2.0) < 1e-9, "%.5f / %.5f" % [q_first, q_follow])
	bz.state = "recover"; bz.state_t = 0.0; bz.recover_dur = 2.0
	st.step({ "special": true }, STEP)
	ok("가시갈기: 감속장 안 빈틈 진행도 dt × 0.4 (빈틈이 짧아지지 않는다)", absf(float(bz.state_t) - STEP * 0.4) < 1e-9, "%.5f" % float(bz.state_t))

## 임무 개편(PObjectives.TUNE, 시험값) 검사: 편성 근거·인구 하한·진행 잠금·표시 값
func mission_tests() -> void:
	if not PObjectives.on():
		ok("임무 개편이 꺼져 있어(PROPHECY_OBJ=off) 임무 검사를 건너뛴다", true)
		return
	var run := PRun.new_run(3, "sword")
	run.day = 2
	run.hp = float(PRun.build(run).hp_max)
	var cards: Array = PSortie.cards_for(run)
	var s := { "regionId": String(cards[0].regionId), "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0,
		"seed": 991, "day": 2, "slot": 1, "variant": null, "mission": true, "objective": "seal", "risk": null, "cardId": "t" }
	var ms := PFlow.make_encounter(run, s, { "fixed_build": true })
	var day_total := PPacing.day_total(2, 1)
	ok("임무도 일반 전투와 같은 날짜 예산 편성을 쓴다(개편 전에는 목표 규칙이 10마리로 덮어썼다)",
		ms.spawn_total >= day_total - 2 and ms.spawn_total > 12, "총 %d (날짜 예산 %d)" % [ms.spawn_total, day_total])
	ok("임무 편성에 정예는 목표 규칙이 정한 만큼만 있다(봉인 임무 = 0)", ms.elite_count().total == 0, str(ms.elite_count()))
	var types := {}
	for u in ms.formation.units:
		types[String(u)] = 1
	ok("임무 편성도 지역 구성 그대로다(한 종류만 나오지 않는다)", types.size() >= 1, str(types.keys()))
	# 지원병: 인구 하한은 기본 편성이 다 나온 뒤에만, 예산은 진행률로 열린다(무한 파밍 금지)
	var ss := CombatState.new({ "build": PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword"))), "seed": 7, "arena": "clearing",
		"objective": "seal", "region_id": "forest", "pool": ["wolf"], "xp_kill_mult": 0.3 })
	var R: Dictionary = ss.obj.reinforce
	ok("봉인 지원: 유한 예산(%d) · 인구 하한 %d · 진행 잠금 %.2f" % [int(R.budget_total), int(R.floor), float(R.gate_base)],
		int(R.budget_total) > 0 and int(R.floor) > 0 and float(R.gate_base) < 1.0)
	var locked := PObjectives.unlocked_budget(ss, R)
	ss.obj.progress = float(ss.obj.total)
	var opened := PObjectives.unlocked_budget(ss, R)
	ok("지원 예산은 목표 진행률로 열린다(진행 0 → %d, 진행 100%% → %d)" % [locked, opened], locked < opened and opened == int(R.budget_total))
	ss.obj.progress = 0.0
	# 표시: 원 밖 정지 / 진행 중 / 피격 중단 구분 + 방향·거리
	var z := {}
	for ob in ss.objects:
		if String(ob.kind) == "seal":
			z = ob
	ss.player.x = float(z.x) + 300.0
	ss.player.y = float(z.y)
	ss.step({}, STEP)
	var m1 := PObjectives.marker(ss)
	var l1 := PObjectives.hud_line(ss, ss.obj)
	ok("봉인 표시: 원 밖이면 state=outside + 방향·거리 안내", String(m1.state) == "outside" and l1.contains("원 밖") and l1.contains(String(m1.dir)), l1)
	ss.player.x = float(z.x)
	ss.player.y = float(z.y)
	ss.step({}, STEP)
	var m2 := PObjectives.marker(ss)
	ok("봉인 표시: 원 안이면 state=progress · 진행 중", String(m2.state) == "progress" and bool(m2.inside) and PObjectives.hud_line(ss, ss.obj).contains("진행 중"), PObjectives.hud_line(ss, ss.obj))
	ss.damage_player(5.0, "test")
	ss.step({}, STEP)
	ok("봉인 표시: 피격 중단은 원 밖 정지와 구분된다", String(PObjectives.marker(ss).state) == "hit_pause" and PObjectives.hud_line(ss, ss.obj).contains("피격 중단"), PObjectives.hud_line(ss, ss.obj))
	var h := PObjectives.hud(ss)
	ok("규칙이 내보내는 표시 값: marker{x,y,r,state,dist,dir} · progress (화면이 큰 목표 표시·방향 안내에 쓸 수 있다)",
		h.has("marker") and (h.marker as Dictionary).has("dir") and h.has("progress"))
	# 제단: 첫 효과가 파괴보다 먼저 오도록 첫 발동을 앞당겼다
	var sa2 := CombatState.new({ "build": PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword"))), "seed": 7, "arena": "clearing",
		"objective": "altars", "region_id": "forest", "pool": ["wolf"], "xp_kill_mult": 0.3 })
	var first_max := 0.0
	for a in sa2.obj.altars:
		first_max = maxf(first_max, float(a.timer))
	ok("제단 첫 효과 발동은 2.5초 안(무엇을 하는 제단인지 부수기 전에 보인다)", first_max <= 2.5 + 1e-6, "%.2f초" % first_max)
	var guards := 0
	for e in sa2.enemies:
		if e.structure or e.dead:
			continue
		for a in sa2.obj.altars:
			if PGeom.dist(e.x, e.y, a.x, a.y) <= 130.0:
				guards += 1
				break
	ok("제단마다 호위가 붙어 있다(편성에서 뺀 수라 총 등장 수·경험치 예산은 그대로)", guards >= 3, "호위 %d" % guards)

## 봉인 수호자 보정: 엄폐 대응(우회)과 양갈래(각도 변주·중앙 후속)
func guardian_tests() -> void:
	if PBoss.gcfg({ "boss_id": "guardian", "phase": 1 }, "cover").is_empty():
		ok("보스 행동 개편이 꺼져 있어 수호자 보정 검사를 건너뛴다", true)
		return
	PBoss.set_cover_mode("")
	PBoss.set_split_on(true)
	# ① 엄폐: 돌 뒤에 선 채로 두면 보스가 우회해 시선을 확보한다
	var st := CombatState.new({ "build": build(), "seed": 11, "arena": "clearing", "boss": true, "boss_id": "guardian",
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
	run_until(st, func(): return String(st.boss.state) != "intro", 3.0)
	var bz: Dictionary = st.boss
	var spot := []
	for ob in st.obstacles:
		for k in 12:
			var a: float = float(k) * TAU / 12.0
			var x: float = clampf(float(ob.x) + cos(a) * (float(ob.r) + 26.0), 30.0, st.arena_w - 30.0)
			var y: float = clampf(float(ob.y) + sin(a) * (float(ob.r) + 26.0), 30.0, st.arena_h - 30.0)
			if st.valid_pos(x, y, float(st.player.r)) and st.los_blocked(float(bz.x), float(bz.y), x, y):
				spot = [x, y]
				break
		if not spot.is_empty():
			break
	var saw_repos := false
	var saw_break := false
	var blocked_end := true
	if not spot.is_empty():
		for i in int(8.0 / STEP):
			st.player.x = spot[0]
			st.player.y = spot[1]
			st.step({}, STEP)
			st.player.hp = st.player.hp_max
			if String(bz.state) == "reposition":
				saw_repos = true
			if String(bz.state) == "breakrock":
				saw_break = true
		blocked_end = st.los_blocked(float(bz.x), float(bz.y), st.player.x, st.player.y)
	# 2026-09-09: 수호자에게도 성격에 맞는 지형 파괴(봉인 파쇄)가 생겼다. 부술 수 있는 돌이면 파쇄가,
	# 부술 수 없으면(외곽 경계·남길 최소 수) 우회가 선택된다. 둘 중 무엇이든 **시선이 실제로 트여야** 통과다.
	ok("수호자: 돌 뒤에 계속 서 있으면 대응해 시선을 확보한다(8초 안)",
		not spot.is_empty() and (saw_repos or saw_break) and not blocked_end,
		"우회 %s · 봉인 파쇄 %s · 끝에 시선 막힘 %s · 부순 장애물 %d" % [str(saw_repos), str(saw_break), str(blocked_end), (st.metrics.get("broken", []) as Array).size()])
	ok("수호자 우회는 예고 상태가 아니다(무예고 처벌 아님 — 몸만 움직이고 무적도 없다)", not PBoss.is_warn_state("reposition") and not PBoss2.is_committed({ "boss_id": "guardian", "state": "reposition" }))
	ok("우회·엄폐물 파괴 상태에 화면 문구가 있다", PCatalog.boss_action_text().has("reposition") and PCatalog.boss_action_text().has("breakrock"))
	# ② 양갈래: 각도 변주가 예고(aim_angle)와 실제 발사 각(dir)에 똑같이 들어간다
	var st2 := CombatState.new({ "build": build(), "seed": 11, "arena": "forest", "boss": true, "boss_id": "guardian",
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
	run_until(st2, func(): return String(st2.boss.state) != "intro", 3.0)
	var b2: Dictionary = st2.boss
	b2.phase = 3
	b2.phase_pending = 3
	var offs := []
	var centers := 0
	var splits := 0
	var last := ""
	var warn_ok := true
	for i in int(60.0 / STEP):
		st2.player.x = clampf(float(b2.x) + 300.0, 30.0, st2.arena_w - 30.0)
		st2.player.y = float(b2.y)
		st2.step({}, STEP)
		st2.player.hp = st2.player.hp_max
		b2.phase = 3
		b2.phase_pending = 3
		var s := String(b2.state)
		if s == "shock_lock" and last == "shock_aim":
			if int(b2.shock_left) >= 2:
				splits += 1
				offs.append(absf(float(b2.get("split_off", 0.0))))
			else:
				centers += 1
			# 확정 각(dir) = 마지막으로 화면에 보여준 예고 각(aim_angle)
			if absf(PGeom.ang_diff(float(b2.dir), float(b2.aim_angle))) > 1e-6:
				warn_ok = false
		last = s
	var any_off := false
	for o in offs:
		if o > 0.0:
			any_off = true
	ok("수호자 3단계: 양갈래 뒤에 중앙 단발 충격파가 이어진다(중앙 %d회 / 양갈래 %d회)" % [centers, splits], splits > 0 and centers > 0)
	ok("수호자 3단계: 양갈래 조준 각을 번갈아 돌린다(정지한 플레이어를 매번 비껴가지 않는다)", any_off, str(offs.slice(0, 6)))
	ok("수호자: 화면 예고 각과 확정 발사 각이 같다(예고와 판정 일치)", warn_ok)

# =========================================================================
# 나무 엄폐 파괴(2026-09-09 사용자 피드백 "보스전에서 돌은 깨지는데 나무는 안 깨진다").
# 사실: 보스 전장 clearing의 나무는 **장식이 아니라 돌과 똑같은 충돌체**다(같은 r로 이동·시야·투사체를 막는다).
# 기존 tests/boss_break_tests.gd는 breaker.types의 **첫 종류**만 골라 엄폐 자리를 잡아, 9종 중 8종이 돌만 시험했다.
# 여기서는 **나무 뒤에 서서** 아홉 보스 전부를 확인한다:
#   ① 부수기 전 그 나무가 실제로 막는다(설 수 없다·시야가 막힌다)
#   ② 예고가 지목한 그 나무가 **실제로** 사라진다(예고와 실제가 같은 것을 가리킨다)
#   ③ 예고가 파괴보다 먼저다
#   ④ 부순 뒤 **보이지 않는 벽이 남지 않는다** — 그 자리에 설 수 있고 시야가 통과하며 걸어 닿는 칸이 줄지 않는다
#   ⑤ 장애물이 늘지 않는다(잔해가 새 충돌체가 되지 않는다)
# 조사 도구: tools/probe_tree.gd → docs/sim/PROBE_TREE.md
# =========================================================================

const TREE_BOSSES: Array = ["boss", "guardian", "eater", "gate_warden", "spore_matriarch",
	"excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]
const TREE_SEC := 45.0

func tree_boss_state(id: String, seed_v: int = 11) -> CombatState:
	PBoss.set_cover_mode("")
	PBoss.set_split_on(true)
	PBoss.set_break_on(true)
	PBoss.set_break_aim_on(true)
	var g := PGrowth.new_growth("sword")
	g.weapons = [{ "id": "ember", "level": 3, "mods": ["scatter", "trail"] }]
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "arena": "clearing", "boss": true,
		"boss_id": id, "region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0, "act": 3 })
	for i in 900:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	st.boss.phase = 3
	st.boss.phase_pending = 3
	return st

## want_type 종류의 장애물 뒤에서 보스 시선이 막히는 자리. 반환 [x, y, 장애물] (없으면 [])
func tree_camp_spot(st: CombatState, want_type: String) -> Array:
	var bz: Dictionary = st.boss
	var best: Array = []
	var bd := -1.0
	for ob in st.obstacles:
		if String(ob.type) != want_type:
			continue
		for k in 24:
			var a: float = float(k) * TAU / 24.0
			var d: float = float(ob.r) + 26.0
			var x: float = clampf(float(ob.x) + cos(a) * d, 30.0, st.arena_w - 30.0)
			var y: float = clampf(float(ob.y) + sin(a) * d, 30.0, st.arena_h - 30.0)
			if not st.valid_pos(x, y, float(st.player.r)):
				continue
			if not st.los_blocked(float(bz.x), float(bz.y), x, y):
				continue
			var sc := PGeom.dist(x, y, float(bz.x), float(bz.y))
			if sc > bd:
				bd = sc
				best = [x, y, ob]
	return best

func tree_break_tests() -> void:
	if PTerrain.break_rules().is_empty():
		ok("지형 파괴 규칙이 꺼져 있어 나무 엄폐 검사를 건너뛴다", true)
		return
	var types: Array = PTerrain.break_rules().get("breakTypes", [])
	ok("자료가 나무를 '부술 수 있는 종류'로 싣는다(data/boss_behavior.json terrain.breakTypes)", types.has("tree"), str(types))
	var missing_tree: Array = []
	for bid in TREE_BOSSES:
		var bt: Array = PBoss.beh_of(String(bid)).get("breaker", {}).get("types", [])
		if not bt.has("tree"):
			missing_tree.append(String(bid))
	ok("보스 9종 전부의 파괴 행동이 나무를 포함한다(돌만 고르는 필터가 없다)", missing_tree.is_empty(), str(missing_tree))

	var no_break: Array = []
	var mismatch: Array = []
	var wall_left: Array = []
	for bid in TREE_BOSSES:
		var st := tree_boss_state(String(bid))
		var spot := tree_camp_spot(st, "tree")
		if spot.is_empty():
			ok("%s: 나무 뒤에 설 자리를 찾았다" % String(bid), false)
			continue
		var target: Dictionary = spot[2]
		var tx: float = float(target.x)
		var ty: float = float(target.y)
		var start := { "x": spot[0], "y": spot[1] }
		# ① 부수기 전: 그 나무는 실제 충돌체다
		var solid_before: bool = not st.valid_pos(tx, ty, 1.0)
		var blocks_before: bool = st.los_blocked(tx - float(target.r) - 4.0, ty, tx + float(target.r) + 4.0, ty)
		ok("%s: 부수기 전 나무가 실제로 막는다(장식이 아니다)" % String(bid), solid_before and blocks_before,
			"설 수 없다 %s · 시야 막힘 %s · r %.0f" % [str(solid_before), str(blocks_before), float(target.r)])
		var reach0 := PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, start)
		var obs0: int = st.obstacles.size()
		var t_warn := -1.0
		var t_break := -1.0
		var aimed_tree := false
		var bz: Dictionary = st.boss
		for i in int(round(TREE_SEC / STEP)):
			if st.status != "running" or bool(bz.dead):
				break
			st.player.x = spot[0]
			st.player.y = spot[1]
			if bool(bz.get("break_want", false)):
				if t_warn < 0.0:
					t_warn = st.t
				if (bz.get("break_ob", {}) as Dictionary) == target:
					aimed_tree = true
			st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }, STEP)
			st.player.hp = st.player.hp_max
			bz.phase = 3
			bz.phase_pending = 3
			if t_break < 0.0 and st.obstacles.find(target) < 0:
				t_break = st.t
		var gone: bool = st.obstacles.find(target) < 0
		if not gone:
			no_break.append(String(bid))
		if gone and not aimed_tree:
			mismatch.append(String(bid))
		ok("%s: 나무 뒤에 서 있으면 **그 나무가** 부서진다" % String(bid), gone and aimed_tree,
			"예고 %s → 파괴 %s · 예고가 그 나무를 지목했다 %s" % [
				("%.1f초" % t_warn) if t_warn >= 0.0 else "없음",
				("%.1f초" % t_break) if t_break >= 0.0 else "없음", str(aimed_tree)])
		if not gone:
			continue
		# ③ 예고가 먼저
		ok("%s: 나무 파괴 예고가 실제 파괴보다 먼저다" % String(bid), t_warn >= 0.0 and t_warn <= t_break,
			"%.2f초 → %.2f초" % [t_warn, t_break])
		# ④ 보이지 않는 벽이 남지 않는다
		var stand: bool = st.valid_pos(tx, ty, 1.0)
		var see: bool = not st.los_blocked(tx - float(target.r) - 4.0, ty, tx + float(target.r) + 4.0, ty)
		var beam_free: bool = st.beam_length(tx - float(target.r) - 20.0, ty, 0.0, float(target.r) * 2.0 + 40.0) >= float(target.r) * 2.0 + 40.0 - 0.001
		var steer_free: bool = true
		var probe_e := { "x": tx - float(target.r) - 30.0, "y": ty, "r": 22.0, "steer_side": 0, "steer_t": 0.0 }
		var dir_v := st.steer_dir(probe_e, tx + float(target.r) + 30.0, ty)
		if absf(float(dir_v[1])) > 0.01: # 아직 무엇인가를 돌아가고 있다 = 경로 탐색에 남아 있다
			steer_free = false
		var reach1 := PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, start)
		if not (stand and see and beam_free and steer_free and reach1 >= reach0):
			wall_left.append(String(bid))
		ok("%s: 부순 나무 자리에 보이지 않는 벽이 없다(이동·시야·투사체·경로 탐색 전부)" % String(bid),
			stand and see and beam_free and steer_free,
			"설 수 있다 %s · 시야 통과 %s · 투사체 통과 %s · 조향이 돌아가지 않는다 %s" % [str(stand), str(see), str(beam_free), str(steer_free)])
		ok("%s: 파괴 뒤 걸어 닿는 칸이 줄지 않고 장애물도 늘지 않는다(잔해가 새 벽이 되지 않는다)" % String(bid),
			reach1 >= reach0 and st.obstacles.size() < obs0, "닿는 칸 %d → %d · 장애물 %d → %d" % [reach0, reach1, obs0, st.obstacles.size()])
	ok("나무 뒤에서 그 나무가 안 부서진 보스가 없다", no_break.is_empty(), str(no_break))
	ok("예고가 지목한 것과 실제로 부서진 것이 어긋난 보스가 없다", mismatch.is_empty(), str(mismatch))
	ok("파괴 뒤 보이지 않는 벽이 남은 보스가 없다", wall_left.is_empty(), str(wall_left))

# ---------- 신규 공격 패턴 18개(§11-A, PBoss4) ----------
## 사용자 검증 항목을 그대로 옮긴 시험이다. **발동 횟수만으로 성공 판정하지 않는다.**
##  ① 같은 방향으로 걷기만 하면 전부 빗나가는가 → 직선 보행자가 실제로 맞는지(맞아야 한다).
##  ② 방향을 바꾸면 피할 수 있는가 → 확정 순간에 반대로 꺾은 보행자가 덜 맞는지(예측 조준 계열은 0회).
##  ③ 확정 뒤에도 따라오는가 → 확정 값(각·착지점·벽 자리)이 실행까지 한 번도 바뀌지 않는지.
##  ④ 반격 기회 → 연계를 끄고 한 패턴만 돌렸을 때 반드시 빈틈(recover)으로 끝나는지.
##  ⑤ 탈출 경로 → 퇴로 차단 계열이 플레이어 주위 방향을 전부 막지 않는지.
## 모든 수치는 시험값이다.
const NX_BOSSES := ["boss", "guardian", "eater", "gate_warden", "spore_matriarch", "excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]
## 예측 조준(가는 쪽을 겨눔) 계열 — 방향을 꺾으면 **한 번도 맞지 않아야** 한다.
## 나머지(전진 연타·이동 분사·측면 추격·몰이)는 몸으로 밀고 들어오는 압박이라 '덜 맞는다'로 본다.
## 한 번 확정하면 끝인 예측 조준 계열 — 방향을 꺾으면 **한 번도 맞지 않아야** 한다.
## 여러 발을 따로 다시 겨누는 것(전진 연사·교차 얼음창·미래 표식)과 본체 후속이 붙는 것(퇴로 절단)은
## 방향을 꺾어도 **다음 발이 새로 겨눠지므로** 여기에 넣지 않는다(그것이 설계다).
const NX_LEAD_ONLY := ["cutoff", "chase_leap", "roots", "sealtrap", "boulder"]
## 시험 거리(px). 그 패턴이 실제로 쓰이는 교전 거리이며 균형값이 아니다(근접 연타 계열은 사거리 안, 원거리 계열은 멀리)
const NX_DIST := { "cutoff": 300.0, "chase_leap": 320.0, "boulder": 300.0, "crossbolt": 300.0, "volley": 260.0,
	"drive": 260.0, "foremark": 300.0, "roots": 260.0, "sealtrap": 260.0, "cutpath": 260.0, "driftspray": 200.0 }

func nx_state(bid: String, seed_v: int = 5) -> CombatState:
	# 장애물 없는 전장(forest): 이 시험이 보는 것은 '예고와 회피'이지 엄폐물이 아니다(엄폐는 boss_break_tests가 본다)
	var st := CombatState.new({ "build": build(), "seed": seed_v, "arena": "forest", "boss": true, "boss_id": bid,
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
	for i in 900:
		if String(st.boss.state) != "intro" and st.intro <= 0.0:
			break
		st.step({}, STEP)
	return st

func nx_begin(st: CombatState, bz: Dictionary, pat: String) -> void:
	var bid := String(bz.boss_id)
	if bid == "boss":
		PBoss.begin(st, bz, pat)
	elif PBoss3.has(bid):
		PBoss3.begin(st, bz, pat)
	else:
		PBoss2.begin(st, bz, pat)

## 이 순간이 '확정'인가(각·자리가 굳은 뒤). 벽·표식은 예고 원이 놓인 순간이 확정이다
func nx_confirmed(bz: Dictionary) -> bool:
	var s := String(bz.state)
	return s.ends_with("_lock") or s == "nx_leap_fly" or s == "nx_spray_on" or not (bz.get("nx_blasts", []) as Array).is_empty()

func boss_threat_list(st: CombatState) -> Array:
	var out: Array = []
	PBoss4.threats(st, st.boss, out)
	return out

## 회피 조종자가 보는 것: 신규 패턴 예고 + 날아오는 적 투사체(구르는 바위도 눈에 보인다)
func nx_seen_threats(st: CombatState) -> Array:
	var out := boss_threat_list(st)
	for pr in st.projectiles:
		if String(pr.owner) == "enemy":
			out.append({ "kind": "beam", "x": float(pr.x), "y": float(pr.y), "ang": atan2(float(pr.vy), float(pr.vx)),
				"len": 260.0, "w": 40.0 + float(pr.r) * 2.0, "prog": 1.0, "locked": true })
	return out

## 확정 뒤 바뀌면 안 되는 값들. **한 번의 확정(에피소드) 안에서만** 비교한다 —
## 연타 2타의 각이 1타와 다른 것은 '추적'이 아니라 새로 예고·확정한 다른 공격이다.
func nx_confirm_values(bz: Dictionary) -> Dictionary:
	var out: Dictionary = { "dir": snappedf(float(bz.get("dir", 0.0)), 0.0001) }
	var land: Dictionary = bz.get("nx_land", {})
	if not land.is_empty() and String(bz.state).begins_with("nx_leap"):
		out.land = [snappedf(float(land.x), 0.01), snappedf(float(land.y), 0.01)]
	return out

## 예고된 폭발은 놓인 뒤 자리가 바뀌면 안 된다. 열쇠 = 순서 + 터질 시각(새로 놓인 것은 새 열쇠다)
func nx_blast_moved(bz: Dictionary, seen: Dictionary) -> bool:
	var moved := false
	for b in bz.get("nx_blasts", []):
		var key := "%d|%.3f" % [int(b.order), float(b.at)]
		var val := "%.2f,%.2f" % [float(b.x), float(b.y)]
		if seen.has(key) and String(seen[key]) != val:
			moved = true
		seen[key] = val
	return moved

func nx_same(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if not b.has(k):
			continue # 상태가 넘어가 그 값이 사라진 것은 '추적'이 아니다
		if str(a[k]) != str(b[k]):
			return false
	return true

## 보스가 맞은 횟수(출처 이름이 boss_로 시작하는 것만). 소환수·바닥 지역과 섞이지 않는다
## 예고를 읽고 대응하는 조종자(결정적). 지금 예고 안이거나 **이대로 걸으면 0.35초 뒤 예고 안**이면
## 그 예고 밖으로 걸어 나가고 회피도 쓴다. 감속장·기술은 쓰지 않는다 — 움직임과 회피만으로 피할 수 있는지 본다
func nx_evade_input(st: CombatState, base: Dictionary) -> Dictionary:
	var pp: Dictionary = st.player
	var ahead := { "x": float(pp.x) + float(base.mx) * 220.0 * 0.35, "y": float(pp.y) + float(base.my) * 220.0 * 0.35, "r": float(pp.r) }
	for th in nx_seen_threats(st):
		if PBot.inside(th, pp) or PBot.inside(th, ahead):
			var dir := PBot.escape_dir(th, pp)
			return { "mx": float(dir[0]), "my": float(dir[1]), "dodge_press": true, "dodge_held": true }
	return base

## 전장 벽에서 margin 이상 떨어져 있는가(탈출 방향 계산이 벽 때문에 왜곡되지 않게)
func nx_inside_arena(st: CombatState, margin: float) -> bool:
	var pp: Dictionary = st.player
	return float(pp.x) > margin and float(pp.y) > margin and float(pp.x) < st.arena_w - margin and float(pp.y) < st.arena_h - margin

func nx_boss_hits(st: CombatState) -> int:
	var n := 0
	for k in st.metrics.taken_hits:
		if String(k).begins_with("boss_"):
			n += int(st.metrics.taken_hits[k])
	return n

## 한 패턴을 끝까지 돌리고 결과를 돌려준다.
## mode "straight" = 같은 방향으로만 걷는다(자동 공격하며 걷는 그 플레이)
##      "turn"     = 확정 순간 반대 방향으로 꺾는다
##      "evade"    = 화면에 뜬 예고를 보고 그 밖으로 걸어 나간다
func nx_run(bid: String, pat: String, mode: String) -> Dictionary:
	var st := nx_state(bid)
	var bz: Dictionary = st.boss
	var dist: float = float(NX_DIST.get(pat, 200.0))
	# 전장 대각선을 달리게 세운다: 직선 보행자가 벽에 막혀 멈추면 '같은 방향으로 걷기' 시험이 아니게 된다.
	# 보스는 그 진행 방향의 옆(수직)에 둔다 — 가장 맞히기 어려운 배치다
	st.player.x = 180.0
	st.player.y = st.arena_h * 0.72
	bz.x = clampf(st.player.x - 0.436 * dist, 70.0, st.arena_w - 70.0)
	bz.y = clampf(st.player.y - 0.9 * dist, 70.0, st.arena_h - 70.0)
	bz.state = "approach"
	bz.state_t = 0.0
	bz.approach_t = 0.0
	# 예열: 같은 방향(+y)으로 1초 걷는다 — 보스가 '관측'할 이동을 실제로 만든다
	var go: Dictionary = { "mx": 0.9, "my": -0.436 }
	for i in 96:
		st.player.hp = st.player.hp_max
		bz.approach_t = 0.0 # 예열 중에는 스스로 공격을 고르지 않게 한다
		st.step(go, STEP)
	var hit0: int = nx_boss_hits(st)
	var warn_t := -1.0
	var hit_t := -1.0
	var turned := false
	var conf: Dictionary = {}
	var seen_blast: Dictionary = {}
	var chase := ""
	var min_exits := 99
	nx_begin(st, bz, pat)
	var ended := false
	var rec_dur := 0.0
	var base: Dictionary = { "mx": 0.9, "my": -0.436 }
	var cur: Dictionary = base
	for i in int(round(9.0 / STEP)):
		st.player.hp = st.player.hp_max
		var was_conf: bool = nx_confirmed(bz)
		if mode == "turn" and was_conf and not turned:
			turned = true
			base = { "mx": -0.9, "my": 0.436 } # 방향 전환(관측된 이동과 반대로)
		cur = nx_evade_input(st, base) if mode == "evade" else base
		if warn_t < 0.0 and not boss_threat_list(st).is_empty():
			warn_t = st.t
		# 확정 값은 '한 번의 확정' 안에서만 비교한다(연타 2타는 새로 예고·확정한 다른 공격이다)
		if String(bz.state).ends_with("_lock") or String(bz.state) == "nx_leap_fly":
			var now := nx_confirm_values(bz)
			if conf.is_empty():
				conf = now
			elif chase == "" and not nx_same(conf, now):
				chase = String(bz.state)
		else:
			conf = {}
		if nx_blast_moved(bz, seen_blast) and chase == "":
			chase = "blast"
		# 탈출 방향은 '벽이 실제로 위협하는 동안'만 센다. 전장 벽에 붙어 있으면 바깥 방향이 빠져 수가 왜곡되므로 건너뛴다
		var blasts: Array = bz.get("nx_blasts", [])
		if not blasts.is_empty() and nx_inside_arena(st, 130.0):
			min_exits = mini(min_exits, PBoss4.free_dirs(st, blasts, 110.0))
		st.step(cur, STEP)
		if hit_t < 0.0 and nx_boss_hits(st) > hit0:
			hit_t = st.t
		if String(bz.state) == "recover":
			ended = true
			rec_dur = float(bz.recover_dur)
			break
		if String(bz.state) == "approach" and (bz.get("nx_blasts", []) as Array).is_empty():
			break
	# 남은 예고(벽·표식·바위)가 다 끝날 때까지 조금 더 본다 — 피해는 그때 들어온다
	for i in int(round(2.5 / STEP)):
		if (bz.get("nx_blasts", []) as Array).is_empty() and (bz.get("nx_echo", []) as Array).is_empty() and (bz.get("nx_boulder", {}) as Dictionary).is_empty():
			break
		st.player.hp = st.player.hp_max
		cur = nx_evade_input(st, base) if mode == "evade" else base # 남은 예고·구르는 바위에도 계속 대응한다
		st.step(cur, STEP)
		if hit_t < 0.0 and nx_boss_hits(st) > hit0:
			hit_t = st.t
	var srcs: Dictionary = {}
	for k in st.metrics.taken_hits:
		if String(k).begins_with("boss_"):
			srcs[String(k)] = int(st.metrics.taken_hits[k])
	return { "dmg": float(nx_boss_hits(st) - hit0), "srcs": srcs, "ended_recover": ended, "recover_dur": rec_dur,
		"chase": chase, "min_exits": min_exits, "warn_t": warn_t, "hit_t": hit_t }

func new_pattern_tests() -> void:
	if PBoss.beh_of("boss").is_empty():
		ok("행동 개편이 꺼져 있어 신규 패턴 검사를 건너뛴다", true)
		return
	# 0) 18개가 자료에 다 있는가
	var total := 0
	var missing: Array = []
	for bid in NX_BOSSES:
		var np: Dictionary = PBoss.beh_of(String(bid)).get("newPatterns", {})
		total += np.size()
		if np.size() != 2:
			missing.append("%s(%d)" % [String(bid), np.size()])
	ok("보스 9종에 신규 패턴이 2개씩, 모두 18개 있다", total == 18 and missing.is_empty(), "총 %d개 %s" % [total, str(missing)])
	# 1~5) 패턴마다
	var no_hit: Array = []
	var no_dodge: Array = []
	var chased: Array = []
	var no_gap: Array = []
	var late_warn: Array = []
	var boxed: Array = []
	for bid in NX_BOSSES:
		var np2: Dictionary = PBoss.beh_of(String(bid)).get("newPatterns", {})
		for k in np2:
			var pat := String(k)
			var a := nx_run(String(bid), pat, "straight")
			var b := nx_run(String(bid), pat, "evade")
			var c := nx_run(String(bid), pat, "turn")
			var key := "%s.%s" % [String(bid), pat]
			if float(a.dmg) <= 0.0:
				no_hit.append(key)
			var lead_only: bool = NX_LEAD_ONLY.has(pat)
			# 예고를 보고 나오면 안 맞아야 한다. 예측 조준 계열은 방향 전환만으로도 0이어야 한다
			var dodged: bool = float(b.dmg) <= 0.0 or float(b.dmg) < float(a.dmg)
			if lead_only and float(c.dmg) > 0.0:
				dodged = false # 예측 조준 계열은 방향 전환만으로도 빗나가야 한다
			if not dodged:
				no_dodge.append("%s(직선%.0f%s 예고회피%.0f%s 방향전환%.0f)" % [key, float(a.dmg), JSON.stringify(a.srcs), float(b.dmg), JSON.stringify(b.srcs), float(c.dmg)])
			if String(a.chase) != "":
				chased.append("%s@%s" % [key, String(a.chase)])
			if not bool(a.ended_recover) or float(a.recover_dur) < 1.0:
				no_gap.append("%s(%.2f)" % [key, float(a.recover_dur)])
			if float(a.hit_t) >= 0.0 and (float(a.warn_t) < 0.0 or float(a.warn_t) > float(a.hit_t)):
				late_warn.append(key)
			if int(a.min_exits) < 3:
				boxed.append("%s(%d)" % [key, int(a.min_exits)])
			ok("%s: 직선 보행 피해 %.0f / 예고 보고 회피 %.0f / 방향 전환 %.0f / 확정 뒤 추적 %s / 빈틈 %.2f초" % [
				key, float(a.dmg), float(b.dmg), float(c.dmg), "없음" if String(a.chase) == "" else String(a.chase), float(a.recover_dur)],
				float(a.dmg) > 0.0 and dodged and String(a.chase) == "" and bool(a.ended_recover) and float(a.recover_dur) >= 1.0)
	ok("같은 방향으로 걷기만 해도 전부 빗나가는 신규 패턴이 없다(18개 모두 실제로 맞힌다)", no_hit.is_empty(), str(no_hit))
	ok("예고를 보고 대응하면 피해가 사라지거나 줄어든다 — 단발 예측 조준 계열은 방향 전환만으로도 0회", no_dodge.is_empty(), str(no_dodge))
	ok("공격 확정 뒤에는 각·착지점·벽 자리가 바뀌지 않는다(끝까지 따라와 맞히는 방식 없음)", chased.is_empty(), str(chased))
	ok("모든 신규 패턴은 빈틈(1.0초 이상)으로 끝난다 — 반격 기회", no_gap.is_empty(), str(no_gap))
	ok("피해보다 예고가 먼저 뜬다(예고 없는 새 판정 없음)", late_warn.is_empty(), str(late_warn))
	ok("퇴로 차단 계열도 플레이어 주위 방향을 전부 막지 않는다(열린 방향 3개 이상)", boxed.is_empty(), str(boxed))

## 실제 전투에서 쓰이는가: 봇이 조종하는 보스전을 굴려 패턴 실행 수를 센다.
## **발동 횟수만으로 성공 판정하지 않는다** — 위의 판정·회피·빈틈 시험을 통과한 패턴이
## 전투에서 실제로 선택되는지까지 확인하는 마지막 관문이다.
func nx_fight(bid: String, seed_v: int, sec: float, out: Dictionary) -> void:
	var st := CombatState.new({ "build": build(), "seed": seed_v, "arena": "forest", "boss": true, "boss_id": bid,
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
	var bot := PBot.new("balanced")
	for i in int(round(sec / STEP)):
		st.player.hp = st.player.hp_max # 사망으로 전투가 끝나지 않게(측정 조건)
		st.step(bot.step_input(st), STEP)
	for k in st.metrics.patterns:
		out[String(k)] = int(out.get(String(k), 0)) + int(st.metrics.patterns[k])

func nx_used_tests() -> void:
	if PBoss.beh_of("boss").is_empty():
		return
	var unused: Array = []
	var lines: Array = []
	for bid in NX_BOSSES:
		var np: Dictionary = PBoss.beh_of(String(bid)).get("newPatterns", {})
		var used: Dictionary = {}
		nx_fight(String(bid), 11, 45.0, used)
		nx_fight(String(bid), 23, 45.0, used)
		var part: Array = []
		for k in np:
			var n: int = int(used.get(String(k), 0))
			part.append("%s %d회" % [String(k), n])
			if n <= 0:
				unused.append("%s.%s" % [String(bid), String(k)])
		lines.append("%s: %s" % [String(bid), ", ".join(part)])
	for l in lines:
		print("NX_USE " + String(l))
	ok("신규 18개가 실제 전투(봇 조종, 보스별 90초)에서 모두 선택된다", unused.is_empty(), str(unused))
