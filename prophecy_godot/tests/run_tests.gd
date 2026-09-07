extends SceneTree
## 규칙 테스트(화면 없음): godot --headless --path prophecy_godot -s tests/run_tests.gd
## 화면·입력 장치 없이 CombatState만 실행한다. 결과는 표준 출력 PASS/FAIL, 종료 코드.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func cfg() -> Dictionary:
	return preload("res://scripts/game/game.gd").load_config()

func mk(seed_v: int = 1) -> CombatState:
	return CombatState.new(cfg(), seed_v)

func steps(st: CombatState, seconds: float, input: Dictionary = {}, dt: float = STEP) -> void:
	var n := int(round(seconds / dt))
	for i in n:
		st.step(input, dt)

## 적이 등장하지 않는 상태(승리 판정도 나지 않게: 웨이브 1개를 무한히 미룬다)
func no_enemies(st: CombatState) -> void:
	st.waves = [[{ "type": "wolf", "n": 1 }]]
	st.wave_timer = 1.0e9

func _init() -> void:
	var c := cfg()
	ok("데이터 로드: 검 12/0.55/95, 늑대 30/150, 웨이브 2", c.weapon.damage == 12 and c.weapon.interval == 0.55 and c.enemies.wolf.hp == 30 and c.waves.size() == 2)
	# 1. 이동 속도: 1초 이동 거리 220
	var st := mk()
	no_enemies(st)
	var x0: float = st.player.x
	for i in 120:
		st.step({ "mx": 1.0, "my": 0.0 }, STEP)
	ok("이동: 1초 오른쪽 이동 거리 220", is_equal_approx(st.player.x - x0, 220.0), "%.3f" % (st.player.x - x0))
	# 2. 회피 거리·무적·재사용
	st = mk(); no_enemies(st)
	var y0: float = st.player.y
	st.step({ "mx": 0.0, "my": -1.0, "dodge": true }, STEP)
	var invul: bool = st.player.dodge_active
	var hp0: float = st.player.hp
	st.damage_player(50.0, "test")
	var no_dmg: bool = st.player.hp == hp0 and st.stats.perfect_dodges == 1
	for i in 60:
		st.step({}, STEP)
	var dist_moved: float = y0 - st.player.y
	ok("회피: 위로 150 이동, 무적 중 피해 0(회피! 판정), 재사용 0.9초 시작", invul and no_dmg and absf(dist_moved - 150.0) < 1.0 and st.player.dodge_cd > 0.0 and st.player.dodge_cd <= 0.9, "거리 %.2f cd %.2f" % [dist_moved, st.player.dodge_cd])
	st.step({ "dodge": true }, STEP)
	ok("회피 재사용 중에는 다시 회피 불가", not st.player.dodge_active)
	for i in 120:
		st.step({}, STEP)
	st.step({ "dodge": true }, STEP)
	ok("0.9초 뒤 회피 가능", st.player.dodge_active)
	# 3. 늑대: 접근 → 준비(0.6) → 확정(0.15) → 돌진(0.32, 256) → 빈틈(0.9). 확정 뒤 플레이어를 추적하지 않음. 예고 통로 = 실제 판정
	st = mk(); no_enemies(st)
	st.player.y = 585.0
	var w := st.spawn_enemy("wolf", st.player.x, 200.0) # 돌진 256이 벽·플레이어에 닿지 않는 배치
	w.state = "crouch"; w.state_t = 0.0 # 접근 단계를 건너뛰고 준비부터(접근하면 돌진 끝이 벽에 닿는다)
	var seen := { "approach": true }
	var dir_at_lock := -99.0
	var dash_start := []
	var dash_end := []
	for i in 600:
		st.step({}, STEP)
		seen[w.state] = true
		if w.state == "lock" and dir_at_lock == -99.0:
			dir_at_lock = w.dir
			st.player.x += 200.0 # 확정 뒤 플레이어가 옆으로 크게 이동
		if w.state == "dash" and dash_start.is_empty():
			dash_start = [w.x, w.y]
		if w.state == "recover" and dash_end.is_empty():
			dash_end = [w.x, w.y]
			break
	var dash_len := PGeom.dist(dash_start[0], dash_start[1], dash_end[0], dash_end[1]) if dash_start.size() == 2 and dash_end.size() == 2 else -1.0
	ok("늑대 상태 순서 approach→crouch→lock→dash→recover", seen.has("crouch") and seen.has("lock") and seen.has("dash") and seen.has("recover"))
	ok("확정된 방향은 바뀌지 않는다(플레이어가 옆으로 200 이동해도 dir 동일)", absf(PGeom.ang_diff(dir_at_lock, w.dir)) < 1e-9, "%.4f vs %.4f" % [dir_at_lock, w.dir])
	ok("돌진 거리 = 800 × 0.32 = 256 (장애물 없을 때)", absf(dash_len - 256.0) < 2.0, "%.2f" % dash_len)
	ok("옆으로 피했으니 물리지 않음, 빈틈 상태", st.player.hp == st.player.hp_max and w.state == "recover")
	# 3b. 예고 방향·폭 = 실제 판정: 통로 안(폭 e.r+p.r)에 있으면 물림, 밖이면 안 물림
	for offset in [20.0, 40.0]:
		st = mk(); no_enemies(st)
		var w2 := st.spawn_enemy("wolf", 480.0, 350.0)
		w2.state = "lock"; w2.dir = -PI / 2.0; w2.state_t = 0.0 # 위로 확정
		st.player.x = 480.0 + offset; st.player.y = 200.0; st.player.hit_prot = 0.0
		for i in 120:
			st.step({}, STEP)
		var expect_hit: bool = float(offset) < (14.0 + 14.0)
		ok("돌진 통로 판정: 옆 오프셋 %d → %s" % [int(offset), "물림" if expect_hit else "안 물림"], (st.player.hp < st.player.hp_max) == expect_hit, "hp %.0f" % st.player.hp)
	# 4. 장애물: 이동·돌진 차단
	st = mk(); no_enemies(st)
	st.player.x = 285.0 - 42.0 - 14.0 - 30.0; st.player.y = 220.0
	for i in 120:
		st.step({ "mx": 1.0 }, STEP)
	ok("바위가 플레이어 이동을 막는다(바위 중심까지 거리 ≥ 42+14)", PGeom.dist(st.player.x, st.player.y, 285.0, 220.0) >= 56.0 - 0.01 and st.player.x < 285.0, "%.2f" % PGeom.dist(st.player.x, st.player.y, 285.0, 220.0))
	st = mk(); no_enemies(st)
	var w3 := st.spawn_enemy("wolf", 285.0, 220.0 - 42.0 - 14.0 - 120.0)
	w3.state = "lock"; w3.dir = PI / 2.0; w3.state_t = 0.0
	st.player.x = 285.0; st.player.y = 220.0 + 42.0 + 14.0 + 40.0
	for i in 120:
		st.step({}, STEP)
	ok("바위가 돌진을 막고 뒤의 플레이어는 안전, 늑대는 바위 앞에서 정지 → 빈틈", st.player.hp == st.player.hp_max and w3.y < 220.0 - 42.0 and w3.state == "recover", "wolf y %.1f state %s" % [w3.y, w3.state])
	# 5. 감속장: 안의 적 준비 진행 40%, 밖은 100%, 종료 후 해제
	st = mk(); no_enemies(st)
	var w4 := st.spawn_enemy("wolf", st.player.x, st.player.y - 100.0)
	w4.state = "crouch"; w4.state_t = 0.0
	st.step({ "special": true }, STEP)
	var t1: float = w4.state_t
	ok("감속장 안 준비 진행 = dt × 0.4", absf(t1 - STEP * 0.4) < 1e-9 and not st.field.is_empty() and st.player.special_cd == 14.0, "%.5f" % t1)
	var far := st.spawn_enemy("wolf", 50.0, 50.0)
	far.state = "crouch"; far.state_t = 0.0
	st.step({}, STEP)
	ok("감속장 밖 준비 진행 = dt", absf(far.state_t - STEP) < 1e-9)
	for i in 400:
		st.step({}, STEP)
	ok("3초 뒤 감속장 해제", st.field.is_empty())
	# 6. 적 0마리지만 다음 웨이브가 남으면 승리하지 않음 / 전멸 시 승리 1회
	st = mk(3)
	for i in 240:
		st.step({}, STEP)
	for e in st.alive_enemies():
		st.damage_enemy(e, 9999.0, "test")
	st.step({}, STEP)
	ok("1웨이브 전멸 뒤에도 2웨이브가 남으면 계속(running)", st.status == "running" and st.remaining().waves_left == 1, "%s waves_left %d" % [st.status, st.remaining().waves_left])
	for i in 400:
		st.step({}, STEP)
		for e in st.alive_enemies():
			st.damage_enemy(e, 9999.0, "test")
	var wins := 0
	for ev in st.events:
		if ev == "win":
			wins += 1
	ok("모든 웨이브 전멸 → 승리, 승리 이벤트 1회", st.status == "won" and wins == 1, "%s wins %d" % [st.status, wins])
	# 7. 패배: 체력 0 → lost 1회, 이후 시간 정지
	st = mk(); no_enemies(st)
	st.damage_player(60.0, "t"); st.player.hit_prot = 0.0; st.damage_player(60.0, "t")
	var t_after: float = st.t
	st.step({}, STEP)
	ok("체력 0 → 패배, 이후 전투 시간 정지", st.status == "lost" and st.player.hp == 0.0 and st.t == t_after)
	# 8. 피격 보호 0.6초: 연속 피해 1회만
	st = mk(); no_enemies(st)
	st.damage_player(10.0, "a"); st.damage_player(10.0, "b")
	ok("피격 보호 0.6초 동안 추가 피해 없음", st.player.hp == 90.0)
	# 9. 초과 피해 제외: 체력 30 늑대에 100 피해 → 유효 30
	st = mk(); no_enemies(st)
	var w5 := st.spawn_enemy("wolf", 100.0, 100.0)
	st.damage_enemy(w5, 100.0, "weapon:sword")
	ok("유효 피해에 초과 피해 미포함(30)", is_equal_approx(st.metrics.dmg["weapon:sword"], 30.0) and w5.dead)
	# 10. 검격 주기 0.55: 5초 동안 공격 횟수 9~10, 빈틈 배율 1.5
	st = mk(); no_enemies(st)
	var w6 := st.spawn_enemy("wolf", st.player.x + 60.0, st.player.y)
	w6.hp = 99999.0; w6.state = "recover"; w6.def = w6.def.duplicate(); w6.def.recover = 999.0
	for i in 600:
		st.step({}, STEP)
		w6.x = st.player.x + 60.0; w6.y = st.player.y
	ok("검격: 5초 동안 공격 9~10회, 빈틈 1회 피해 18", st.stats.attacks >= 9 and st.stats.attacks <= 10 and is_equal_approx(st.metrics.dmg["weapon:sword"] / float(st.stats.hits), 18.0), "attacks %d hits %d dmg %.1f" % [st.stats.attacks, st.stats.hits, st.metrics.dmg["weapon:sword"]])
	# 11. 결정성: 같은 시드·같은 입력 열 → 같은 결과 (봇 입력)
	var a := run_bot(5)
	var b := run_bot(5)
	ok("같은 시드·같은 행동 → 같은 결과", JSON.stringify(a) == JSON.stringify(b), "%s %ss" % [a.status, str(a.elapsed)])
	# 12. 프레임률 독립: 봇 입력을 120fps 기준으로 기록한 뒤 다른 프레임 묶음(2단계/프레임)으로 재실행해도 같다(고정 단계이므로 프레임 크기 무관)
	var seq := []
	var st_r := mk(11)
	var bot := PBot.new()
	while st_r.status == "running" and seq.size() < 120 * 90:
		var inp := bot.step_input(st_r)
		seq.append(inp)
		st_r.step(inp, STEP)
	var st_p := mk(11)
	for i in seq.size():
		st_p.step(seq[i], STEP)
	ok("기록된 행동 열 재실행 = 같은 결과(프레임 묶음과 무관, 고정 단계)", JSON.stringify(st_r.summary()) == JSON.stringify(st_p.summary()), "%s %ss kills %d" % [st_r.status, str(st_r.elapsed if st_r.has_method("x") else st_r.t), st_r.stats.kills])
	# 13. 피해 총합 = 실제 체력 감소(초과 제외)
	var st_d := mk(21)
	var bot2 := PBot.new()
	var spawned_hp := 0.0
	var seen_ids := {}
	for i in 120 * 60:
		if st_d.status != "running":
			break
		st_d.step(bot2.step_input(st_d), STEP)
		for e in st_d.enemies:
			if not seen_ids.has(e.id):
				seen_ids[e.id] = e
	var lost := 0.0
	for id in seen_ids:
		var e: Dictionary = seen_ids[id]
		lost += e.hp_max - maxf(0.0, e.hp)
	var dealt := 0.0
	for k in st_d.metrics.dmg:
		dealt += st_d.metrics.dmg[k]
	ok("출처별 유효 피해 합 = 적 체력 감소 합", absf(lost - dealt) < 0.6, "lost %.1f dealt %.1f (%s)" % [lost, dealt, st_d.status])
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

func run_bot(seed_v: int) -> Dictionary:
	var st := mk(seed_v)
	var bot := PBot.new()
	var n := 0
	while st.status == "running" and n < 120 * 120:
		st.step(bot.step_input(st), STEP)
		n += 1
	return st.summary()
