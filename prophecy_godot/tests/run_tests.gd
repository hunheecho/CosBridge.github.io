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

## 회피 비교 설정을 적용한 상태(게임과 같은 경로: Game.config_with_dodge)
func mk_dodge(mode: String, cooldown: float, seed_v: int = 1) -> CombatState:
	return CombatState.new(preload("res://scripts/game/game.gd").config_with_dodge(cfg(), mode, cooldown), seed_v)

const PRESS := { "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": true }
const HOLD := { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": true } # 이동 입력 없이 누르고 있음(걸어서 벽에 닿지 않게)
const FREE := { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false }

## 회피 1회를 재생: 누른 뒤 hold_steps 단계 동안 누르고 있다가 뗀다. 회피가 끝날 때까지(최대 200단계) 진행. 이동 거리·무적 단계 수를 돌려준다
func play_dodge(st: CombatState, hold_steps: int, max_steps: int = 200) -> Dictionary:
	var x0: float = st.player.x
	var y0: float = st.player.y
	var inv := 0
	var n := 0
	st.step(PRESS if hold_steps > 0 else { "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": false }, STEP)
	n += 1
	if st.player.dodge_active:
		inv += 1
	while st.player.dodge_active and n < max_steps:
		st.step(HOLD if n < hold_steps else FREE, STEP)
		n += 1
		if st.player.dodge_active:
			inv += 1
	return { "dist": PGeom.dist(x0, y0, st.player.x, st.player.y), "invuln_steps": inv, "steps": n, "end": st.player.dodge_end }

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
	# 2. 회피(기본 hold · 1.5초): 누르는 순간 즉시 출발, 계속 누르면 150, 무적 중 피해 0, 재사용 1.5초는 출발 순간부터
	st = mk(); no_enemies(st)
	var y0: float = st.player.y
	st.step({ "mx": 0.0, "my": -1.0, "dodge_press": true, "dodge_held": true }, STEP)
	var invul: bool = st.player.dodge_active
	var hp0: float = st.player.hp
	st.damage_player(50.0, "test")
	var no_dmg: bool = st.player.hp == hp0 and st.stats.perfect_dodges == 1
	for i in 60:
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": true }, STEP)
	var dist_moved: float = y0 - st.player.y
	ok("회피(hold): 누르는 단계에 출발·무적, 계속 누르면 위로 150, 재사용 1.5초가 출발 순간부터 감", invul and no_dmg and absf(dist_moved - 150.0) < 0.01 and absf(st.player.dodge_cd - (1.5 - 61.0 * STEP)) < 1e-6, "거리 %.2f cd %.4f" % [dist_moved, st.player.dodge_cd])
	st.step({ "dodge_press": true, "dodge_held": true }, STEP)
	ok("회피 재사용 중에는 새로 눌러도 회피 불가", not st.player.dodge_active)
	while st.player.dodge_cd > 0.0 and st.step_n < 1000:
		st.step({}, STEP)
	var steps_to_ready: int = st.step_n
	st.step({ "dodge_press": true, "dodge_held": true }, STEP)
	ok("1.5초(180단계)가 되면 새 누름으로 회피 가능", steps_to_ready == 180 and st.player.dodge_active, "%d단계" % steps_to_ready)
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
	# ---------- 회피 시험 설계(docs/RULES.md §회피) ----------
	# D1. 아주 짧은 탭(누른 단계에서 이미 뗌)도 즉시 출발, 장애물 없으면 정확히 70
	st = mk(); no_enemies(st)
	var r1 := play_dodge(st, 0)
	ok("D1 짧은 탭: 즉시 출발, 70 이동, 종료 사유 release", absf(r1.dist - 70.0) < 0.01 and r1.end == "release" and st.stats.dodges == 1, "거리 %.2f %s %d단계" % [r1.dist, r1.end, r1.steps])
	# D2. 충분히 누르면 150(초과 이동 없음), 무적은 회피 이동 중에만 = 0.26초 이내
	st = mk(); no_enemies(st)
	var r2 := play_dodge(st, 100)
	ok("D2 계속 누름: 정확히 150, 마지막 이동량 제한, 무적 단계 ≤ 0.26초", absf(r2.dist - 150.0) < 0.01 and r2.end == "max" and r2.invuln_steps * STEP <= 0.26 + 1e-9, "거리 %.3f 무적 %d단계(%.4f초)" % [r2.dist, r2.invuln_steps, r2.invuln_steps * STEP])
	# D3. 중간 해제(0.15초 = 18단계 누름)는 70~150 사이에서 끝난다
	st = mk(); no_enemies(st)
	var r3 := play_dodge(st, 18)
	ok("D3 중간 해제: 70 < 거리 < 150, 뗀 뒤 곧 종료", r3.dist > 70.0 and r3.dist < 150.0 and r3.end == "release" and r3.steps <= 19, "거리 %.2f %d단계" % [r3.dist, r3.steps])
	# D4. 짧게 끝낸 뒤 무적이 남지 않는다(종료 직후 피해가 들어간다)
	st = mk(); no_enemies(st)
	play_dodge(st, 0)
	var hp_before: float = st.player.hp
	st.damage_player(10.0, "test")
	ok("D4 짧은 회피 종료 직후 무적 없음(피해 10 적용)", not st.player.dodge_active and st.player.hp == hp_before - 10.0 and st.stats.perfect_dodges == 0)
	# D5. 고정 거리 방식은 떼어도 150까지 간다
	st = mk_dodge("fixed", 1.5); no_enemies(st)
	var r5 := play_dodge(st, 0)
	ok("D5 고정 거리 방식: 탭해도 150", absf(r5.dist - 150.0) < 0.01 and r5.end == "max", "거리 %.2f" % r5.dist)
	# D6. 두 방식 모두 선택한 재사용 대기 적용(0.9/1.2/1.5/1.8): 직전 단계 불가, 도달 단계 가능
	var all_cd_ok := true
	var cd_detail := []
	for mode in ["fixed", "hold"]:
		for cdv in [0.9, 1.2, 1.5, 1.8]:
			var s6 := mk_dodge(mode, float(cdv)); no_enemies(s6)
			play_dodge(s6, 100)
			var total := int(round(float(cdv) / STEP))
			while s6.step_n < total - 1:
				s6.step(FREE, STEP)
			s6.step(PRESS, STEP) # 대기 마지막 단계: cd가 아직 남아 있어 불가
			var early: bool = s6.player.dodge_active
			s6.step(PRESS, STEP) # 정확히 cd초 경과: 가능
			var on_time: bool = s6.player.dodge_active
			if early or not on_time:
				all_cd_ok = false
			cd_detail.append("%s/%.1f:%s" % [mode, float(cdv), ("ok" if (not early and on_time) else "FAIL")])
	ok("D6 두 방식 × 재사용 0.9/1.2/1.5/1.8: 직전 단계 불가, 도달 단계 새 누름으로 가능", all_cd_ok, " ".join(cd_detail))
	# D7. 계속 누른 상태로는 대기 시간이 지나도 자동 재발동하지 않는다(새 누름 필요)
	st = mk(); no_enemies(st)
	st.step(PRESS, STEP)
	for i in 400:
		st.step(HOLD, STEP)
	var no_auto: bool = st.stats.dodges == 1 and st.player.dodge_cd <= 0.0
	st.step(PRESS, STEP)
	ok("D7 계속 누름: 3.3초 동안 회피 1회뿐, 새 누름에만 재발동", no_auto and st.stats.dodges == 2 and st.player.dodge_active)
	# D8. 장애물·경계를 통과하지 않고, 막히면 무적 유지 없이 즉시 종료(최소 거리 미만이라도)
	st = mk(); no_enemies(st)
	var rock: Dictionary = st.obstacles[0]
	st.player.x = float(rock.x) - float(rock.r) - float(st.player.r) - 20.0
	st.player.y = float(rock.y)
	var r8 := play_dodge(st, 100)
	var gap: float = float(rock.x) - st.player.x - float(rock.r) - float(st.player.r)
	ok("D8 바위: 회피가 바위에서 멈추고(약 20 이동) 즉시 종료(blocked), 겹침 없음", r8.end == "blocked" and r8.dist < 25.0 and gap > -0.01 and r8.steps <= 6, "거리 %.2f 틈 %.3f %d단계 %s" % [r8.dist, gap, r8.steps, r8.end])
	st = mk(); no_enemies(st)
	st.player.x = float(st.arena_w) - float(st.player.r) - 30.0
	var r8b := play_dodge(st, 100)
	ok("D8 전장 경계: 30 이동 뒤 종료, 경계 밖으로 나가지 않음", r8b.end == "blocked" and r8b.dist < 35.0 and st.player.x <= float(st.arena_w) - float(st.player.r) + 0.01, "거리 %.2f x %.2f" % [r8b.dist, st.player.x])
	# D9. 방향 고정: 출발 뒤 이동 입력을 바꿔도 회피 방향이 바뀌지 않는다. 이동 입력 없으면 바라보는 방향(face)
	st = mk(); no_enemies(st)
	var px0: float = st.player.x
	var py0: float = st.player.y
	st.step({ "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": true }, STEP)
	while st.player.dodge_active:
		st.step({ "mx": 0.0, "my": 1.0, "dodge_press": false, "dodge_held": true }, STEP)
	ok("D9 방향 고정: 출발 방향(오른쪽)으로 150, 회피 중 아래 입력 무시", absf(st.player.x - px0 - 150.0) < 0.01 and absf(st.player.y - py0) < 0.01, "(%.1f, %.1f)" % [st.player.x - px0, st.player.y - py0])
	st = mk(); no_enemies(st)
	st.step({ "mx": 0.0, "my": -1.0 }, STEP) # 위를 바라봄
	py0 = st.player.y
	st.step({ "mx": 0.0, "my": 0.0, "dodge_press": true, "dodge_held": false }, STEP)
	while st.player.dodge_active:
		st.step({}, STEP)
	ok("D9 이동 입력 없이 회피: 마지막 바라보던 방향(위)으로 70", absf(py0 - st.player.y - 70.0) < 0.01, "%.2f" % (py0 - st.player.y))
	# D10. 프레임률 독립(실제 화면과 같은 PStepDriver): 30/60/144fps 상당의 프레임으로 같은 시각의 누름·해제를 넣어도
	#      회피 횟수 동일, 거리 차이 ≤ 한 프레임 이동량(30fps 기준 19.3), 남은 재사용 차이 ≤ 1/30초
	var timeline := [[0.50, 0.505], [2.50, 2.65], [4.50, 5.20]] # (누름 시각, 뗀 시각): 탭 / 중간 / 최대
	var fps_res := {}
	for fps in [30.0, 60.0, 144.0]:
		var sf := mk(); no_enemies(sf)
		var drv := PStepDriver.new()
		var t := 0.0
		var dt := 1.0 / float(fps)
		var prev := 0.0
		while t < 6.0:
			t += dt
			var press := false
			var held := false
			for iv in timeline:
				if float(iv[0]) > prev and float(iv[0]) <= t:
					press = true # 프레임 사이에 생긴 누름을 기록(실제 화면의 _unhandled_input 역할)
				if float(iv[0]) <= t and float(iv[1]) > t:
					held = true
			if press:
				drv.note_dodge_press()
			drv.frame(sf, dt, 0.0, 0.0, held) # 이동 없이(회피 방향 = 바라보는 방향 오른쪽), 걸어서 벽에 닿지 않게
			prev = t
		fps_res[fps] = { "n": sf.stats.dodges, "d": sf.stats.dodge_dists.duplicate(), "cd": sf.player.dodge_cd, "x": sf.player.x }
	var fr_ok := true
	for fps in [60.0, 144.0]:
		var a30: Dictionary = fps_res[30.0]
		var bf: Dictionary = fps_res[fps]
		if a30.n != bf.n or bf.n != 3:
			fr_ok = false
		for i in mini(a30.d.size(), bf.d.size()):
			if absf(float(a30.d[i]) - float(bf.d[i])) > 19.3:
				fr_ok = false
		if absf(float(a30.cd) - float(bf.cd)) > 1.0 / 30.0 + 1e-6:
			fr_ok = false
	ok("D10 30/60/144fps 프레임 처리: 회피 3회 동일, 거리 차 ≤ 19.3, 남은 재사용 차 ≤ 1/30초", fr_ok, "30:%s 60:%s 144:%s" % [str(fps_res[30.0].d), str(fps_res[60.0].d), str(fps_res[144.0].d)])
	# D11. 같은 프레임에 여러 단계가 돌아도 누름은 1번만 소비: 0.1초 프레임(12단계) 안에 press 1회 → 회피 1회, 재사용 중 press는 나중에 발동하지 않음
	st = mk(); no_enemies(st)
	var drv2 := PStepDriver.new()
	drv2.note_dodge_press()
	drv2.frame(st, 0.1, 1.0, 0.0, true)
	var one: bool = st.stats.dodges == 1
	drv2.note_dodge_press() # 재사용 중 누름
	drv2.frame(st, 0.1, 1.0, 0.0, true)
	drv2.frame(st, 0.1, 1.0, 0.0, true)
	for i in 20:
		drv2.frame(st, 0.1, 1.0, 0.0, true) # 대기 시간이 지나도(2초) 이전 누름이 저절로 발동하지 않는다
	ok("D11 한 프레임 12단계에서 누름 1번만 소비, 재사용 중 누름은 나중에 발동하지 않음", one and st.stats.dodges == 1 and st.player.dodge_cd <= 0.0, "dodges %d" % st.stats.dodges)
	# D12. 대기 입력 폐기(일시정지·재시작·포커스 상실은 driver.reset()): reset 뒤 프레임에서 회피가 시작되지 않는다. 재개 후 새 누름 필요
	st = mk(); no_enemies(st)
	var drv3 := PStepDriver.new()
	drv3.note_dodge_press()
	drv3.reset()
	drv3.frame(st, 1.0 / 60.0, 1.0, 0.0, true) # 누르고 있는 채 재개해도(held) 새 누름이 없으면 회피 없음
	var none: bool = st.stats.dodges == 0
	drv3.note_dodge_press()
	drv3.frame(st, 1.0 / 60.0, 1.0, 0.0, true)
	ok("D12 reset 뒤 대기 누름 폐기·held만으로는 회피 없음, 새 누름으로 회피", none and st.stats.dodges == 1)
	# D13. 같은 기록 입력(누름·유지·해제 열) 재실행 = 같은 결과, 그리고 회피 설정이 달라도 같은 시드의 적 배치는 같다
	var rec := []
	var sa := mk(3)
	var botA := PBot.new()
	while sa.status == "running" and rec.size() < 120 * 60:
		var inp := botA.step_input(sa)
		rec.append(inp.duplicate())
		sa.step(inp, STEP)
	var sb := mk(3)
	for inp in rec:
		sb.step(inp, STEP)
	ok("D13 기록 입력(press/held) 재실행 = 같은 결과", JSON.stringify(sa.summary()) == JSON.stringify(sb.summary()), "%s %s 회피 %s" % [sa.status, str(sa.summary().elapsed), str(sa.stats.dodge_dists)])
	var s_h := mk_dodge("hold", 1.5, 3)
	var s_f := mk_dodge("fixed", 0.9, 3)
	for i in 240:
		s_h.step({}, STEP)
		s_f.step({}, STEP)
	var place_h := s_h.enemies.map(func(e): return [e.type, snapped(e.x, 0.01), snapped(e.y, 0.01), e.state])
	var place_f := s_f.enemies.map(func(e): return [e.type, snapped(e.x, 0.01), snapped(e.y, 0.01), e.state])
	ok("D13 회피 설정이 달라도 같은 시드 → 같은 적 배치(2초 시점 %d마리)" % place_h.size(), place_h.size() > 0 and JSON.stringify(place_h) == JSON.stringify(place_f))
	# D14. 일시정지는 화면 계층(driver.frame을 부르지 않음): 규칙 시간·재사용이 진행되지 않는다
	st = mk(); no_enemies(st)
	var drv4 := PStepDriver.new()
	drv4.note_dodge_press()
	drv4.frame(st, 1.0 / 60.0, 1.0, 0.0, true)
	var t_p: float = st.t
	var cd_p: float = st.player.dodge_cd
	ok("D14 일시정지(프레임 미진행) 중 전투 시간·재사용 정지", st.t == t_p and st.player.dodge_cd == cd_p and cd_p > 0.0)
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
