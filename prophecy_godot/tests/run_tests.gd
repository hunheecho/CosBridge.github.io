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

## 적이 등장하지 않는 상태(소환 멈춤: 예약하지 않은 적이 남아 승리 판정도 나지 않는다)
func no_enemies(st: CombatState) -> void:
	st.spawn_hold = true

## 늑대 1마리를 놓고 공격을 못 하게(재사용 대기 무한) — 이동·충돌·검격 시험용
func passive_wolf(st: CombatState, x: float, y: float) -> Dictionary:
	var w := st.spawn_enemy("wolf", x, y)
	w.bite_cd = 1.0e9
	w.dash_ready_at = 1.0e9
	return w

## 검격을 끈 상태(물기·돌진 규칙만 볼 때). 검격 넉백 40이 물기 준비 중인 늑대를 사거리(44) 밖으로 밀어내는 상호작용은 E1n에서 따로 확인한다
func no_sword(st: CombatState) -> void:
	st.player.attack_timer = 1.0e9

func mk_formation(fid: String, seed_v: int = 1, dmax: int = 2) -> CombatState:
	var G := preload("res://scripts/game/game.gd")
	return CombatState.new(G.config_with(cfg(), "hold", 1.5, fid, dmax), seed_v)

func _init() -> void:
	var c := cfg()
	ok("데이터 로드: 검 12/0.55/95, 늑대 30/150, 편성 3(기본 x5 25마리)", c.weapon.damage == 12 and c.weapon.interval == 0.55 and c.enemies.wolf.hp == 30 and c.formations.size() == 3 and c.formation_default == "x5" and c.formations.x5.total == 25)
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
	# 6. 화면의 적이 0이어도 예약하지 않은 적·등장 대기가 남으면 승리하지 않음 / 전멸 시 승리 1회
	st = mk_formation("base", 3)
	for i in 130:
		st.step({}, STEP) # 0.4 + 0.6초: 첫 묶음 2마리 등장
	for e in st.alive_enemies():
		st.damage_enemy(e, 9999.0, "test")
	st.step({}, STEP)
	ok("첫 묶음 전멸 뒤에도 남은 예약이 있으면 계속(running)", st.status == "running" and st.remaining().total == 3 and st.alive_enemies().is_empty(), "%s 남은 %d" % [st.status, st.remaining().total])
	for i in 1200:
		st.step({}, STEP)
		for e in st.alive_enemies():
			st.damage_enemy(e, 9999.0, "test")
	var wins := 0
	for ev in st.events:
		if ev == "win":
			wins += 1
	ok("예정 5마리 전부 등장·전멸 → 승리, 승리 이벤트 1회", st.status == "won" and wins == 1, "%s wins %d" % [st.status, wins])
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
	var w5 := passive_wolf(st, 100.0, 100.0)
	st.damage_enemy(w5, 100.0, "weapon:sword")
	ok("유효 피해에 초과 피해 미포함(30)", is_equal_approx(st.metrics.dmg["weapon:sword"], 30.0) and w5.dead)
	# 10. 검격 주기 0.55: 5초 동안 공격 횟수 9~10, 빈틈 배율 1.5
	st = mk(); no_enemies(st)
	var w6 := passive_wolf(st, st.player.x + 60.0, st.player.y)
	w6.hp = 99999.0; w6.state = "recover"; w6.def = w6.def.duplicate(true); w6.def.dash.recover = 999.0
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
	# ---------- 늑대 물기·돌진·동시 제한·밀도(docs/RULES.md §늑대·§밀도) ----------
	var WB: Dictionary = cfg().enemies.wolf.bite
	var WD: Dictionary = cfg().enemies.wolf.dash
	# E1. 가까우면 물기: 사거리(44) 안에 두면 물기 준비 → 고정 → 유효 → 빈틈, 유효 구간에 1회 피해 12
	st = mk(); no_enemies(st)
	var e1k := st.spawn_enemy("wolf", st.player.x + 40.0, st.player.y)
	e1k.bite_cd = 0.0; e1k.dash_ready_at = 1.0e9
	var seen1k := {}
	for i in 120:
		st.step({}, STEP)
		seen1k[e1k.state] = true
	ok("E1n (관찰) 검격이 켜져 있으면 넉백 40으로 물기 준비 중 늑대가 사거리 44 밖으로 밀려 물기가 빗나간다(피해 0)", seen1k.has("bite_hit") and st.player.hp == 100.0, "hp %.0f" % st.player.hp)
	st = mk(); no_enemies(st); no_sword(st)
	var e1 := st.spawn_enemy("wolf", st.player.x + 40.0, st.player.y)
	e1.bite_cd = 0.0; e1.dash_ready_at = 0.0
	var seen1 := {}
	var hp_e1: float = st.player.hp
	for i in 120:
		st.step({}, STEP)
		seen1[e1.state] = true
	ok("E1 가까우면 물기: 준비→고정→유효→빈틈, 피해 12 한 번", seen1.has("bite_track") and seen1.has("bite_lock") and seen1.has("bite_hit") and seen1.has("bite_recover") and not seen1.has("crouch") and st.player.hp == hp_e1 - 12.0 and st.metrics.enemies.wolf.bite_hits == 1, "%s hp %.0f" % [str(seen1.keys()), st.player.hp])
	# E2. 적당한 거리(70~170)면 돌진(첫 지연 경과·재사용 가능·자리 있음)
	st = mk(); no_enemies(st)
	var e2 := st.spawn_enemy("wolf", st.player.x, st.player.y - 120.0)
	e2.dash_ready_at = 0.0
	st.step({}, STEP)
	ok("E2 적당한 거리·조건 충족 → 돌진 준비(crouch)", e2.state == "crouch" and st.metrics.enemies.wolf.dashes_prepared == 1, e2.state)
	# E3. 돌진 재사용 대기 중에는 접근해서 물기
	st = mk(); no_enemies(st)
	var e3 := st.spawn_enemy("wolf", st.player.x, st.player.y - 120.0)
	e3.dash_ready_at = 0.0; e3.dash_cd = 8.0; e3.bite_cd = 0.0
	var seen3 := {}
	for i in 240:
		st.step({}, STEP)
		seen3[e3.state] = true
	ok("E3 돌진 대기 중: 접근 뒤 물기(돌진 없음)", seen3.has("bite_hit") and not seen3.has("crouch"), str(seen3.keys()))
	# E4. 공격 시작 뒤 전환 없음: 물기 준비 중 플레이어가 멀어져도 물기 절차를 마친다(돌진으로 바꾸지 않음), 돌진 준비 중 가까워져도 돌진
	st = mk(); no_enemies(st)
	var e4 := st.spawn_enemy("wolf", st.player.x + 40.0, st.player.y)
	e4.bite_cd = 0.0; e4.dash_ready_at = 0.0
	st.step({}, STEP)
	var started_bite: bool = e4.state == "bite_track"
	st.player.x -= 150.0 # 멀어짐
	var seen4 := {}
	for i in 100:
		st.step({}, STEP)
		seen4[e4.state] = true
	ok("E4a 물기 시작 뒤 멀어져도 물기 절차 유지(돌진 전환 없음, 빗나감)", started_bite and seen4.has("bite_hit") and seen4.has("bite_recover") and not seen4.has("crouch") and st.player.hp == 100.0, str(seen4.keys()))
	st = mk(); no_enemies(st)
	var e4b := st.spawn_enemy("wolf", st.player.x, st.player.y - 120.0)
	e4b.dash_ready_at = 0.0; e4b.bite_cd = 0.0
	st.step({}, STEP)
	st.player.y = e4b.y + 30.0 # 돌진 준비 중 바로 옆으로
	var seen4b := {}
	for i in 100:
		st.step({}, STEP)
		seen4b[e4b.state] = true
	ok("E4b 돌진 준비 뒤 가까워져도 물기로 바꾸지 않음", seen4b.has("lock") and not seen4b.has("bite_track"), str(seen4b.keys()))
	# E5. 방향 고정 뒤 옆·뒤로 빠지면 맞지 않음(판정 = 예고 부채꼴)
	var side_ok := true
	for offset in [[0.0, 60.0], [0.0, -60.0], [-70.0, 0.0]]:
		var s5 := mk(); s5.spawn_hold = true
		var e5 := s5.spawn_enemy("wolf", s5.player.x - 40.0, s5.player.y) # 왼쪽에서 오른쪽을 물려 함
		e5.bite_cd = 0.0; e5.dash_ready_at = 1.0e9
		while e5.state != "bite_lock" and s5.step_n < 200:
			s5.step({}, STEP)
		s5.player.x += float(offset[0]); s5.player.y += float(offset[1])
		for i in 60:
			s5.step({}, STEP)
		if s5.player.hp != 100.0 or s5.metrics.enemies.wolf.bites_executed != 1:
			side_ok = false
	ok("E5 방향 고정 뒤 위/아래/뒤로 빠지면 물기 빗나감(피해 0)", side_ok)
	var s5c := mk(); s5c.spawn_hold = true
	var e5c := s5c.spawn_enemy("wolf", s5c.player.x - 40.0, s5c.player.y)
	e5c.bite_cd = 0.0; e5c.dash_ready_at = 1.0e9
	while e5c.state != "bite_lock" and s5c.step_n < 200:
		s5c.step({}, STEP)
	s5c.player.x -= 8.0 # 부채꼴 안에 그대로
	for i in 60:
		s5c.step({}, STEP)
	ok("E5 부채꼴 안에 남으면 맞음(피해 12)", s5c.player.hp == 88.0)
	# E6. 물기 1회에 중복 피해 없음: 유효 구간 내내 안에 있어도 피해 12 한 번, 피격 보호는 공용
	st = mk(); no_enemies(st); no_sword(st)
	var e6 := st.spawn_enemy("wolf", st.player.x + 40.0, st.player.y)
	e6.bite_cd = 0.0; e6.dash_ready_at = 1.0e9
	st.player.hit_prot = 0.0
	for i in 120:
		st.step({}, STEP)
	ok("E6 물기 유효 구간 12단계 동안 피해 12 한 번", st.player.hp == 88.0 and st.metrics.enemies.wolf.bite_hits == 1)
	# E7. 돌진 뒤 빈틈 0.9초에는 물기 불가(바로 옆에 있어도), 빈틈 뒤 접근·물기 가능
	st = mk(); no_enemies(st); no_sword(st)
	var e7 := st.spawn_enemy("wolf", st.player.x + 40.0, st.player.y)
	e7.state = "recover"; e7.state_t = 0.0; e7.bite_cd = 0.0; e7.dash_cd = 8.0
	var no_bite_in_recover := true
	for i in int(round(0.9 / STEP)) - 1:
		st.step({}, STEP)
		if e7.state != "recover":
			no_bite_in_recover = false
	for i in 60:
		st.step({}, STEP)
	ok("E7 돌진 빈틈 0.9초 동안 물기 없음, 빈틈 뒤 물기", no_bite_in_recover and st.metrics.enemies.wolf.bites_prepared >= 1, "bites_prepared %d" % st.metrics.enemies.wolf.bites_prepared)
	# E8. 재사용 대기 경계: 물기 1.2초는 유효 종료 시점부터(빈틈 0.4 포함), 돌진 8초는 돌진 종료 시점부터(빈틈 0.9 포함)
	st = mk(); no_enemies(st); no_sword(st)
	var e8 := st.spawn_enemy("wolf", st.player.x + 40.0, st.player.y)
	e8.bite_cd = 0.0; e8.dash_ready_at = 1.0e9
	while e8.state != "bite_recover" and st.step_n < 200:
		st.step({}, STEP)
	var cd_at_recover_start: float = e8.bite_cd
	var n8 := 0
	while e8.bite_cd > 0.0 and n8 < 500:
		st.step({}, STEP)
		n8 += 1
	ok("E8a 물기 재사용 1.2초 = 빈틈 시작 시 1.2, 144단계 뒤 0(빈틈 0.4 포함)", is_equal_approx(cd_at_recover_start, 1.2) and n8 == 144, "%.3f %d단계" % [cd_at_recover_start, n8])
	st = mk(); no_enemies(st); no_sword(st)
	var e8b := st.spawn_enemy("wolf", st.player.x, 200.0)
	st.player.y = 585.0
	e8b.state = "lock"; e8b.state_t = 0.0; e8b.dir = PI / 2.0
	while e8b.state != "recover" and st.step_n < 200:
		st.step({}, STEP)
	var dcd0: float = e8b.dash_cd
	var n8b := 0
	while e8b.dash_cd > 0.0 and n8b < 2000:
		st.step({}, STEP)
		n8b += 1
	ok("E8b 돌진 재사용 8초 = 돌진 종료 시 8.0, 960단계 뒤 0(빈틈 0.9 포함)", is_equal_approx(dcd0, 8.0) and n8b == 960, "%.3f %d단계" % [dcd0, n8b])
	# E9. 감속장 안에서는 재사용 대기가 적 시간 배율(0.4)로 줄어든다 — 밖보다 빨라지는 역전 없음
	st = mk(); no_enemies(st)
	var e9 := passive_wolf(st, st.player.x + 100.0, st.player.y)
	e9.bite_cd = 1.0; e9.dash_cd = 8.0
	var e9o := passive_wolf(st, 60.0, 60.0)
	e9o.bite_cd = 1.0; e9o.dash_cd = 8.0
	st.step({ "special": true }, STEP)
	for i in 119:
		st.step({}, STEP)
	ok("E9 감속장 안 1초: 물기 대기 1.0→0.6, 돌진 8.0→7.6 / 밖: 0.0, 7.0", absf(e9.bite_cd - 0.6) < 1e-6 and absf(e9.dash_cd - 7.6) < 1e-6 and e9o.bite_cd == 0.0 and absf(e9o.dash_cd - 7.0) < 1e-6, "in %.3f/%.3f out %.3f/%.3f" % [e9.bite_cd, e9.dash_cd, e9o.bite_cd, e9o.dash_cd])
	# E10. 동시 돌진 제한 2: 준비·고정·돌진 합계가 2를 넘지 않음, 준비 중 사망 시 자리 반환, 자리 얻지 못한 늑대는 예고 없이 접근
	st = mk(); no_enemies(st); no_sword(st)
	var pack := []
	for i in 6:
		var wi := st.spawn_enemy("wolf", 330.0 + 60.0 * i, 400.0) # 플레이어(480,500)에서 100~180
		wi.dash_ready_at = 0.0
		wi.bite_cd = 1.0e9
		pack.append(wi)
	var max_ds := 0
	var killed_in_crouch := false
	for i in 400:
		st.step({}, STEP)
		max_ds = maxi(max_ds, st.dash_states_count())
		if not killed_in_crouch:
			for wi in pack:
				if wi.state == "crouch":
					st.damage_enemy(wi, 9999.0, "test")
					killed_in_crouch = true
					break
	ok("E10 동시 돌진 ≤ 2, 준비 중 사망해도 다른 늑대가 자리를 받아 계속 돌진", max_ds == 2 and killed_in_crouch and st.metrics.enemies.wolf.dashes_prepared >= 3, "max %d prepared %d" % [max_ds, st.metrics.enemies.wolf.dashes_prepared])
	var s10 := mk_formation("x5", 1, 3); s10.spawn_hold = true; no_sword(s10)
	for i in 6:
		var wi := s10.spawn_enemy("wolf", 330.0 + 60.0 * i, 400.0)
		wi.dash_ready_at = 0.0
		wi.bite_cd = 1.0e9
	var max3 := 0
	for i in 200:
		s10.step({}, STEP)
		max3 = maxi(max3, s10.dash_states_count())
	ok("E10 비교 설정 동시 돌진 3", max3 == 3, "max %d" % max3)
	# E11. 첫 돌진 지연 2~5초(생성 시 1회), 같은 시드·같은 입력이면 공격 순서(attack_log) 재현
	var s11 := mk_formation("x5", 4)
	var delays_ok := true
	for i in 600:
		s11.step({}, STEP)
		for e in s11.alive_enemies():
			var dly: float = e.dash_ready_at - e.spawn_t
			if dly < 2.0 - 1e-9 or dly > 5.0 + 1e-9:
				delays_ok = false
	var s11b := mk_formation("x5", 4)
	for i in 600:
		s11b.step({}, STEP)
	ok("E11 첫 돌진 지연 2~5초, 같은 시드 → 같은 공격 순서(%d건)" % s11.attack_log.size(), delays_ok and s11.attack_log.size() > 0 and JSON.stringify(s11.attack_log) == JSON.stringify(s11b.attack_log))
	# E12. 밀도: 25/50마리 정확히 등장, 동시 생존+대기 ≤ 상한, 대기가 남았을 때 조기 승리 없음
	for pair in [["x5", 25, 12], ["x10", 50, 20], ["base", 5, 5]]:
		var s12 := mk_formation(String(pair[0]), 2)
		var cap_ok := true
		var early_win := false
		var n12 := 0
		while s12.status == "running" and n12 < 120 * 200:
			s12.step({}, STEP)
			n12 += 1
			if s12.alive_enemies().size() + s12.pending.size() > int(pair[2]):
				cap_ok = false
			for e in s12.alive_enemies():
				st.damage_enemy(e, 9999.0, "test") if false else s12.damage_enemy(e, 9999.0, "test")
			if s12.status == "won" and (s12.spawn_count < int(pair[1]) or not s12.pending.is_empty()):
				early_win = true
		ok("E12 %s: 정확히 %d 등장, 생존+대기 ≤ %d, 조기 승리 없음" % [pair[0], int(pair[1]), int(pair[2])], s12.status == "won" and s12.metrics.enemies.wolf.spawned == int(pair[1]) and cap_ok and not early_win, "%s spawned %d" % [s12.status, s12.metrics.enemies.wolf.spawned])
	# E13. 소환 위치: 플레이어에서 100 이상, 장애물 밖, 경계 안
	var s13 := mk_formation("x10", 6)
	var pos_ok := true
	var min_pd := 1.0e9
	for i in 120 * 40:
		s13.step({}, STEP)
		for e in s13.enemies:
			if e.spawn_t == s13.t and not e.dead:
				var dpp := PGeom.dist(e.x, e.y, s13.player.x, s13.player.y)
				min_pd = minf(min_pd, dpp)
				if dpp < 100.0 or not s13.valid_pos(e.x, e.y, e.r):
					pos_ok = false
		if s13.status != "running":
			break
	ok("E13 소환 위치: 플레이어와 100 이상(최소 %.0f), 장애물·경계 밖 없음" % min_pd, pos_ok and s13.metrics.enemies.wolf.spawned >= 20)
	# E14. 다수 겹침: 늑대 12마리를 플레이어와 같은 좌표에 → 좌표 유한, 플레이어 밀림 ≤ 120/s, 장애물·경계 안 아님, 접촉 피해 없음
	st = mk(); no_enemies(st)
	for i in 12:
		var wi := passive_wolf(st, st.player.x, st.player.y)
	var max_v := 0.0
	var finite := true
	var pxp: float = st.player.x
	var pyp: float = st.player.y
	for i in 240:
		st.step({}, STEP)
		var vv := PGeom.dist(pxp, pyp, st.player.x, st.player.y) / STEP
		max_v = maxf(max_v, vv)
		pxp = st.player.x; pyp = st.player.y
		for e in st.alive_enemies():
			if not is_finite(e.x) or not is_finite(e.y):
				finite = false
	ok("E14 같은 좌표 12마리: 좌표 유한, 플레이어 밀림 최대 %.0f/s ≤ 120, 장애물 밖, 접촉 피해 0" % max_v, finite and max_v <= 120.0 + 1e-6 and st.valid_pos(st.player.x, st.player.y, st.player.r) and st.player.hp == 100.0)
	# E15. 접촉만으로 피해 없음: 늑대(공격 불가)가 2초 동안 몸을 붙여도 피해 0
	st = mk(); no_enemies(st)
	var e15 := passive_wolf(st, st.player.x + 20.0, st.player.y)
	for i in 240:
		st.step({}, STEP)
		e15.x = st.player.x + 20.0; e15.y = st.player.y
	ok("E15 접촉·겹침 2초 피해 0(피해는 물기·돌진 판정만)", st.player.hp == 100.0 and st.stats.damage_taken == 0.0)
	# E16. 여러 늑대의 물기가 같은 순간 겹쳐도 피격 보호 0.6초(공용)로 체력은 12만 줄어든다
	st = mk(); no_enemies(st)
	for i in 3:
		var wi := st.spawn_enemy("wolf", st.player.x + 40.0 * cos(float(i) * 2.0), st.player.y + 40.0 * sin(float(i) * 2.0))
		wi.bite_cd = 0.0; wi.dash_ready_at = 1.0e9
	for i in 60:
		st.step({}, STEP)
	ok("E16 물기 3개 동시: 피해 12 한 번(피격 보호 0.6초 공용), 실행 3회", st.player.hp == 88.0 and st.metrics.enemies.wolf.bites_executed == 3 and st.metrics.enemies.wolf.bite_hits == 1, "hp %.0f exec %d hits %d" % [st.player.hp, st.metrics.enemies.wolf.bites_executed, st.metrics.enemies.wolf.bite_hits])
	# E17. 회피 무적 중 물기·돌진 모두 회피(회피! 판정): 유효 구간 직전에 회피를 시작해 무적 상태로 판정을 지난다
	st = mk(); no_enemies(st); no_sword(st)
	var e17 := st.spawn_enemy("wolf", st.player.x - 40.0, st.player.y)
	e17.bite_cd = 0.0; e17.dash_ready_at = 1.0e9
	while not (e17.state == "bite_lock" and e17.state_t + STEP >= float(WB.lock) - 1e-9) and st.step_n < 200:
		st.step({}, STEP)
	st.player.face = -PI / 2.0 # 위로 회피(늑대 부채꼴 안에서 출발)
	st.step({ "dodge_press": true, "dodge_held": true }, STEP)
	var entered_hit: bool = e17.state == "bite_hit"
	for i in 3:
		st.step({ "dodge_held": true }, STEP) # 유효 구간의 판정을 무적 상태로 지난다
	var bite_dodged: bool = entered_hit and st.player.hp == 100.0 and st.stats.perfect_dodges == 1
	for i in 40:
		st.step({}, STEP)
	var e17d := st.spawn_enemy("wolf", st.player.x, st.player.y - 90.0)
	e17d.state = "lock"; e17d.state_t = 0.0; e17d.dir = PI / 2.0; e17d.bite_cd = 1.0e9
	st.player.dodge_cd = 0.0
	while e17d.state != "dash" and st.step_n < 400:
		st.step({}, STEP)
	for i in 8:
		st.step({}, STEP) # 돌진 8단계(53px) 진행: 다음 단계들에 플레이어를 지난다
	st.player.face = 0.0
	st.step({ "dodge_press": true, "dodge_held": true }, STEP)
	for i in 6:
		st.step({ "dodge_held": true }, STEP)
	ok("E17 회피 무적 중 물기·돌진 모두 피해 0(회피! 2회)", bite_dodged and st.player.hp == 100.0 and st.stats.perfect_dodges == 2, "bite %s hp %.0f perfect %d" % [str(bite_dodged), st.player.hp, st.stats.perfect_dodges])
	# E18. 받은 피해 출처 합 = 체력 감소, 물기/돌진 출처 구분
	var s18 := mk_formation("x5", 9)
	var b18 := PBot.new("stand")
	var n18 := 0
	while s18.status == "running" and n18 < 120 * 120:
		s18.step(b18.step_input(s18), STEP)
		n18 += 1
	var taken_sum := 0.0
	for k in s18.metrics.taken:
		taken_sum += s18.metrics.taken[k]
	var lost18: float = 100.0 - s18.player.hp
	ok("E18 받은 피해 출처 합(%s) = 총 유효 피해 %.1f = 체력 감소 %.0f (%s, 명목 %.0f; 사망 시 우회 없음)" % [str(s18.metrics.taken), s18.stats.damage_taken, lost18, s18.status, s18.stats.damage_taken_nominal], absf(taken_sum - lost18) < 1e-6 and absf(s18.stats.damage_taken - lost18) < 1e-6 and s18.player.hp >= 0.0)
	# E20. 체력 100에서 피해 12를 피격 보호가 끝난 뒤 9번: 체력 0·패배, 유효 피해 합 100(마지막 타격 4), 명목 108. 사망 뒤 추가 피해 집계 없음
	st = mk(); no_enemies(st)
	var applied20 := 0
	for i in 9:
		st.player.hit_prot = 0.0
		if st.damage_player(12.0, "wolf:bite"):
			applied20 += 1
	var after_death_taken: float = st.stats.damage_taken
	st.player.hit_prot = 0.0
	var extra20 := st.damage_player(12.0, "wolf:dash")
	ok("E20 12 피해 ×9: 체력 0·패배, 유효 100(출처 %s), 명목 108, 사망 뒤 추가 집계 없음" % str(st.metrics.taken), applied20 == 9 and st.status == "lost" and st.player.hp == 0.0 and st.stats.damage_taken == 100.0 and st.stats.damage_taken_nominal == 108.0 and float(st.metrics.taken.get("wolf:bite", 0.0)) == 100.0 and not extra20 and st.stats.damage_taken == after_death_taken and not st.metrics.taken.has("wolf:dash"), "hp %.0f taken %.1f nominal %.1f" % [st.player.hp, st.stats.damage_taken, st.stats.damage_taken_nominal])
	# E21. 마지막 타격 직전 체력 4에서 피해 12: 해당 출처의 유효 피해 증가량 4
	st = mk(); no_enemies(st)
	st.player.hp = 4.0
	st.damage_player(12.0, "wolf:dash")
	ok("E21 체력 4에서 피해 12: 출처 wolf:dash 유효 4, 총 4, 명목 12", float(st.metrics.taken.get("wolf:dash", 0.0)) == 4.0 and st.stats.damage_taken == 4.0 and st.stats.damage_taken_nominal == 12.0 and st.player.hp == 0.0 and st.status == "lost", str(st.metrics.taken))
	# E22. 물기·돌진이 섞여도 출처별 합 = 총 유효 피해 = 체력 감소 (물기 7회 84 → 돌진 12 → 물기 12는 유효 4)
	st = mk(); no_enemies(st)
	for i in 7:
		st.player.hit_prot = 0.0
		st.damage_player(12.0, "wolf:bite")
	st.player.hit_prot = 0.0
	st.damage_player(12.0, "wolf:dash")
	st.player.hit_prot = 0.0
	st.damage_player(12.0, "wolf:bite")
	var sum22 := 0.0
	for k in st.metrics.taken:
		sum22 += st.metrics.taken[k]
	ok("E22 물기·돌진 혼합: 출처별 %s 합 %.0f = 총 %.0f = 체력 감소 %.0f" % [str(st.metrics.taken), sum22, st.stats.damage_taken, 100.0 - st.player.hp], sum22 == 100.0 and st.stats.damage_taken == 100.0 and st.player.hp == 0.0 and float(st.metrics.taken.get("wolf:bite", 0.0)) == 88.0 and float(st.metrics.taken.get("wolf:dash", 0.0)) == 12.0 and st.stats.damage_taken_nominal == 108.0)
	# E23. 회피 무적·피격 보호로 거부된 공격은 유효·명목 어느 집계에도 남지 않는다
	st = mk(); no_enemies(st)
	st.step({ "dodge_press": true, "dodge_held": true }, STEP)
	var rej_dodge := st.damage_player(12.0, "wolf:bite")
	for i in 40:
		st.step({}, STEP)
	st.damage_player(12.0, "wolf:bite") # 유효 1회(피격 보호 시작)
	var rej_prot := st.damage_player(12.0, "wolf:dash")
	ok("E23 회피 무적·피격 보호 거부 시 집계 없음: 유효 12, 명목 12, 출처 물기만", not rej_dodge and not rej_prot and st.stats.damage_taken == 12.0 and st.stats.damage_taken_nominal == 12.0 and not st.metrics.taken.has("wolf:dash") and st.stats.perfect_dodges == 1, "taken %s nominal %.0f hp %.0f" % [str(st.metrics.taken), st.stats.damage_taken_nominal, st.player.hp])
	# E19. 경험치 예산: 5/25/50마리 모두 전멸 시 합계 9.0(소수 누적, 손실 없음), 마리당 1.8/0.36/0.18
	var xp_ok := true
	var xp_detail := []
	for fid in ["base", "x5", "x10"]:
		var sx := mk_formation(fid, 2)
		var nx := 0
		while sx.status == "running" and nx < 120 * 200:
			sx.step({}, STEP)
			nx += 1
			for e in sx.alive_enemies():
				sx.damage_enemy(e, 9999.0, "test")
		xp_detail.append("%s %.4f(마리당 %.2f)" % [fid, sx.stats.xp, sx.xp_per_kill()])
		if absf(sx.stats.xp - 9.0) > 1e-9 or sx.status != "won":
			xp_ok = false
	ok("E19 경험치 예산 9.0 일치: " + " / ".join(xp_detail), xp_ok)
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
