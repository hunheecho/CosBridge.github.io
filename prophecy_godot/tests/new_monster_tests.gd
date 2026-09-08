extends SceneTree
## 신규 일반 몬스터 3종(흡혈 박쥐·불씨 도마뱀·도약 두꺼비)과 일반 정예 확장 10종 규칙 검사(화면 없음).
## 실행: python tools/run_suites.py --suites new_monster_tests
##      (직접: godot --headless --path prophecy_godot -s tests/new_monster_tests.gd)
##
## 무엇을 보는가
##  ① 박쥐: 접근 → 공격 → 이탈이 실제로 **순환**한다 / 예고 없이 피해를 주지 않는다 / **회복 기능이 없다**.
##  ② 도마뱀: 준비 중 멈춘다 / 불줄기가 **입에서 이어진다** / 회전 속도 상한 / **잔류 장판 없음** /
##     지속 피해가 **정한 틱 간격** / 화염이 끝난 뒤 빈틈.
##  ③ 두꺼비: 착지 위치가 확정 뒤 안 바뀐다 / 바위 안·맵 밖에 안 떨어진다 /
##     여러 마리가 탈출로를 동시에 다 덮지 않는다 / 착지 후 빈틈.
##  ④ 일반 정예 10종: 각자 **자기 고유 행동을 실제로 실행한다**(상태 전이·실행 계측으로 확인) —
##     이름·색만 바꾼 것이 아니고, **체력만 올린 것도 아니다**(같은 바탕의 일반 개체와 한 연계의 행동 수가 다르다).
##     세계 변화 등급(붉은·상위 변이) 배율이 정예 체력 위에 겹쳐 곱해지지 않는지도 함께 본다.
##
## 여기 수치는 전부 **시험값**이다(사람이 재미·밸런스를 확인한 값이 아니다). 정본은 data/pacing.json.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func near(a: float, b: float, tol: float = 0.02) -> bool:
	return absf(a - b) <= tol

# ---------- 시험실 ----------
## 적이 저절로 나오지 않고 자동 공격도 없는 빈 전장(적 규칙만 본다)
func lab(seed_v: int = 1, act: int = 1, arena: String = "clearing") -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": arena, "region_id": "lab", "act": act })
	st.spawn_hold = true
	st.weapons = [] # 자동기술 정지: 적 행동만 관찰한다
	return st

func put(st: CombatState, type: String, x: float, y: float, tier: String = "normal") -> Dictionary:
	return st.spawn_enemy(type, x, y, false, tier)

## 한 단계 진행(플레이어를 계속 살려 둔다 — 연계 전체를 보기 위해)
func tick(st: CombatState, input: Dictionary = {}) -> void:
	st.step(input, STEP)
	st.player.hp = st.player.hp_max
	st.player.dead = false
	if st.status == "lost":
		st.status = "running"

## 상태 전이 순서를 기록하며 진행(같은 상태가 이어지면 한 번만 적는다)
func trace(st: CombatState, e: Dictionary, seconds: float) -> Array:
	var out := [String(e.state)]
	for i in int(round(seconds / STEP)):
		tick(st)
		if String(e.state) != String(out[out.size() - 1]):
			out.append(String(e.state))
	return out

## 상태 s가 나올 때까지 진행. 도달 시각(-1 = 못 봄)
func until(st: CombatState, e: Dictionary, s: String, max_sec: float = 15.0) -> float:
	for i in int(round(max_sec / STEP)):
		if String(e.state) == s:
			return st.t
		tick(st)
	return -1.0

## 그 상태가 이어진 시간(-1 = 못 봄 / 끝나지 않음)
func dur_of(st: CombatState, e: Dictionary, s: String, max_sec: float = 15.0) -> float:
	var t0 := until(st, e, s, max_sec)
	if t0 < 0.0:
		return -1.0
	for i in int(round(max_sec / STEP)):
		tick(st)
		if String(e.state) != s:
			return st.t - t0
	return -1.0

## 이 출처로 실제로 맞은 횟수
func hits_of(st: CombatState, src: String) -> int:
	return int(st.metrics.taken_hits.get(src, 0))

## 플레이어가 이번 단계에 어떤 출처로든 맞았는가를 세기 위한 합계
func hits_total(st: CombatState) -> int:
	var n := 0
	for k in st.metrics.taken_hits:
		n += int(st.metrics.taken_hits[k])
	return n

## 완결된 연계 목록: approach를 떠나 approach로 돌아올 때까지 지나간 상태들(중복 제거, 순서 보존)
func chains(st: CombatState, e: Dictionary, seconds: float) -> Array:
	var out: Array = []
	var cur: Array = []
	var last := String(e.state)
	for i in int(round(seconds / STEP)):
		tick(st)
		var s := String(e.state)
		if s == last:
			continue
		last = s
		if s == "approach":
			if not cur.is_empty():
				out.append(cur)
				cur = []
			continue
		if not cur.has(s):
			cur.append(s)
	return out

## 그 상태를 담은 연계 하나(없으면 빈 배열)
func chain_with(list: Array, state: String) -> Array:
	for c in list:
		if (c as Array).has(state):
			return c
	return []

## 가장 긴 연계(일반 개체 쪽에 가장 유리하게 견주기 위해)
func longest_chain(list: Array) -> Array:
	var best: Array = []
	for c in list:
		if (c as Array).size() > best.size():
			best = c
	return best

func _init() -> void:
	# 새 종류 정의를 적 사전에 등록한다. 실제 게임에서는 PEnemies.update가 부르지만(그리고 정본 훅은
	# PCatalog.enemies()가 PEnemiesNew.extra_defs()를 합치는 것이다) 여기서는 소환이 먼저라 직접 부른다
	PEnemiesNew.ensure_defs()
	ok("새 종류 12종이 적 사전에 등록된다(생성 파일 data/enemies.json은 손대지 않는다)",
		PCatalog.enemies().has("bat") and PCatalog.enemies().has("lizard") and PCatalog.enemies().has("toad") and PCatalog.enemies().has("toad_elite"))
	bat_tests()
	lizard_tests()
	toad_tests()
	common_elite_tests()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ================= ① 흡혈 박쥐 =================
func bat_tests() -> void:
	var D := PEnemiesNew.tuning("bat")

	# --- 접근 → 공격 → 이탈이 실제로 순환한다 ---
	var st := lab()
	var bat := put(st, "bat", st.player.x + 150.0, st.player.y)
	var tr := trace(st, bat, 14.0)
	var order := ["approach", "bite_aim", "bite", "leave", "hover"]
	var cycles := 0
	var i := 0
	while i + order.size() <= tr.size():
		var all_match := true
		for k in order.size():
			if String(tr[i + k]) != String(order[k]):
				all_match = false
				break
		if all_match:
			cycles += 1
			i += order.size()
		else:
			i += 1
	ok("박쥐: 접근 → 공격(예고·물기) → 이탈 → 선회가 **순환**한다(14초에 %d바퀴 · 전이 %s)" % [cycles, str(tr.slice(0, 11))],
		cycles >= 2)
	var after_bite := []
	for j in range(tr.size() - 1):
		if String(tr[j]) == "bite":
			after_bite.append(String(tr[j + 1]))
	var leave_always := not after_bite.is_empty()
	for s in after_bite:
		if String(s) != "leave":
			leave_always = false
	ok("박쥐: 늑대처럼 붙어 걷지 않는다 — 물기 뒤에는 **반드시 이탈(leave)**이 온다(%d번 모두 %s)" % [after_bite.size(), str(after_bite.slice(0, 4))],
		leave_always)

	# --- 예고 없이 피해를 주지 않는다 ---
	var st2 := lab(2)
	var bat2 := put(st2, "bat", st2.player.x + 26.0, st2.player.y) # 처음부터 몸이 겹칠 만큼 붙여 둔다
	var hit_states := {}
	for j in int(round(16.0 / STEP)):
		var any0 := hits_total(st2)
		tick(st2)
		if hits_total(st2) > any0:
			hit_states[String(bat2.state)] = int(hit_states.get(String(bat2.state), 0)) + 1
	ok("박쥐: **빠르다고 무예고 접촉 피해를 주지 않는다** — 피해가 들어간 순간의 상태는 예고를 지난 물기(bite)뿐이다(%s)" % str(hit_states),
		hit_states.size() == 1 and hit_states.has("bite"))
	ok("박쥐: 짧아도 예고가 있다(biteAim %.2f초 > 0) — 접근·이탈·선회 중에는 판정 자체가 없다" % float(D.biteAim),
		float(D.biteAim) > 0.0 and hits_of(st2, "bat_bite") > 0)

	# --- 회복 기능이 없다 ---
	var def := PCatalog.enemy("bat")
	var heal_keys := []
	for k in def:
		var ks := String(k).to_lower()
		if ks.contains("heal") or ks.contains("lifesteal") or ks.contains("drain") or ks.contains("leech"):
			heal_keys.append(String(k))
	ok("박쥐: **정의에 회복 항목이 없다** — 이름만 보고 흡혈 회복을 임의로 넣지 않았다(회복 수치는 사용자 결정 사항. 넣을 때 필요한 값은 docs/MONSTERS.md에만 적었다)",
		heal_keys.is_empty(), str(heal_keys))
	var st3 := lab(3)
	var bat3 := put(st3, "bat", st3.player.x + 40.0, st3.player.y)
	bat3.hp = float(bat3.hp_max) * 0.4
	var hp_start: float = bat3.hp
	var hp_top: float = bat3.hp
	for j in int(round(20.0 / STEP)):
		tick(st3)
		hp_top = maxf(hp_top, float(bat3.hp))
	ok("박쥐: 여러 번 물어도 **체력이 한 번도 오르지 않는다**(시작 %.1f · 최고 %.1f · 물기 %d회)" % [hp_start, hp_top, hits_of(st3, "bat_bite")],
		hp_top <= hp_start + 1e-6 and hits_of(st3, "bat_bite") > 0)

# ================= ② 불씨 도마뱀 =================
func lizard_tests() -> void:
	var D := PEnemiesNew.tuning("lizard")

	# --- 준비 중 멈춘다 ---
	var st := lab()
	var lz := put(st, "lizard", st.player.x + 200.0, st.player.y)
	if until(st, lz, "flame_aim", 20.0) < 0.0:
		ok("도마뱀: 화염 준비 상태에 들어간다", false)
		return
	var x0: float = lz.x
	var y0: float = lz.y
	var moved := 0.0
	var guard := 0
	while (String(lz.state) == "flame_aim" or String(lz.state) == "flame_lock") and guard < 2000:
		guard += 1
		tick(st, { "mx": -1.0, "my": 0.0 }) # 플레이어가 움직여도 도마뱀은 멈춰 있어야 한다
		moved = maxf(moved, PGeom.dist(x0, y0, lz.x, lz.y))
	ok("도마뱀: **준비 중(입이 밝아지는 flame_aim·flame_lock) 멈춘다** — 그 사이 움직인 거리 %.3f px" % moved, moved < 0.5)

	# --- 불줄기가 입에서 이어진다 / 회전 상한 / 잔류 장판 없음 ---
	var zones0 := st.zones.size()
	var mouth_err := 0.0
	var turn_max := 0.0
	var prev_dir: float = lz.dir
	var flame_steps := 0
	var beam_min := 1e9
	guard = 0
	var orbit: float = atan2(st.player.y - lz.y, st.player.x - lz.x)
	while String(lz.state) == "flame" and guard < 2000:
		guard += 1
		# 플레이어를 도마뱀 둘레로 **아주 빠르게**(초당 3 rad) 돌린다. 즉시 따라잡으면 여기서 걸린다
		orbit += 3.0 * STEP
		st.player.x = clampf(lz.x + cos(orbit) * 150.0, 30.0, st.arena_w - 30.0)
		st.player.y = clampf(lz.y + sin(orbit) * 150.0, 30.0, st.arena_h - 30.0)
		tick(st)
		flame_steps += 1
		var seg := PEnemiesNew.flame_seg(st, lz, float(lz.dir))
		mouth_err = maxf(mouth_err, absf(PGeom.dist(float(seg[0]), float(seg[1]), lz.x, lz.y) - float(lz.r)))
		beam_min = minf(beam_min, float(seg[2]))
		turn_max = maxf(turn_max, absf(PGeom.ang_diff(prev_dir, float(lz.dir))) / STEP)
		prev_dir = lz.dir
	ok("도마뱀: 불줄기가 **입에서 이어진다**(시작점과 몸 중심의 거리 = 반지름 %.0f · 오차 %.5f px · %d단계 관측)" % [float(lz.r), mouth_err, flame_steps],
		mouth_err < 1e-3 and flame_steps > 0)
	ok("도마뱀: 불줄기 **자체가 공격 범위**다 — 길이는 장애물까지로 끊긴다(최소 %.0f ≤ 정의 %.0f)" % [beam_min, float(D.flameLen)],
		beam_min > 0.0 and beam_min <= float(D.flameLen) + 1e-6)
	ok("도마뱀: **회전 속도 상한**을 넘지 않는다(플레이어를 초당 3 rad로 돌려도 잰 최고 %.3f ≤ flameTurn %.2f rad/s) — 갑자기 뒤집거나 즉시 따라잡지 않는다" % [turn_max, float(D.flameTurn)],
		turn_max > 0.0 and turn_max <= float(D.flameTurn) + 1e-3)
	ok("도마뱀: 화염이 **잔류 장판을 남기지 않는다**(유지 중·종료 직후 장판 수 %d → %d)" % [zones0, st.zones.size()],
		st.zones.size() == zones0)

	# --- 화염 종료 뒤 빈틈 ---
	var st4 := lab(4)
	var lz4 := put(st4, "lizard", st4.player.x + 200.0, st4.player.y)
	var rec := dur_of(st4, lz4, "recover", 25.0)
	ok("도마뱀: 화염이 끝나면 **반격할 빈틈**이 있다(잰 값 %.2f초 = 시험값 recover %.2f)" % [rec, float(D.recover)],
		rec > 0.0 and near(rec, float(D.recover), 0.03))

	# --- 지속 피해가 정한 틱 간격 ---
	var st5 := lab(5)
	var lz5 := put(st5, "lizard", st5.player.x + 200.0, st5.player.y)
	if until(st5, lz5, "flame", 25.0) < 0.0:
		ok("도마뱀: 화염 유지 상태에 들어간다", false)
		return
	var tick_times := []
	var last := hits_of(st5, "lizard_flame")
	guard = 0
	while String(lz5.state) == "flame" and guard < 2000:
		guard += 1
		# 플레이어를 불줄기 안에 붙잡아 둔다(입에서 이어지는 선 위에 세운다)
		var seg := PEnemiesNew.flame_seg(st5, lz5, float(lz5.dir))
		st5.player.x = float(seg[0]) + cos(float(lz5.dir)) * (float(seg[2]) * 0.5)
		st5.player.y = float(seg[1]) + sin(float(lz5.dir)) * (float(seg[2]) * 0.5)
		tick(st5)
		var now := hits_of(st5, "lizard_flame")
		if now > last:
			last = now
			tick_times.append(st5.t)
	var gaps := []
	for j in range(1, tick_times.size()):
		gaps.append(snappedf(float(tick_times[j]) - float(tick_times[j - 1]), 0.001))
	var gap_ok := not gaps.is_empty()
	for g in gaps:
		if not near(float(g), float(D.flameTick), 0.03):
			gap_ok = false
	ok("도마뱀: 지속 피해가 **정한 틱 간격**(flameTick %.2f초)으로만 들어간다 — 잰 간격 %s(피해 %d회)" % [float(D.flameTick), str(gaps), tick_times.size()],
		gap_ok and tick_times.size() >= 3)
	ok("도마뱀: 틱 간격이 공통 피격 보호(%.2f초)보다 커서 정한 틱이 보호에 먹혀 사라지지 않는다" % float(st5.cfg.player.hit_protect),
		float(D.flameTick) > float(st5.cfg.player.hit_protect))

# ================= ③ 도약 두꺼비 =================
func toad_tests() -> void:
	var D := PEnemiesNew.tuning("toad")

	# --- 착지 위치가 확정 뒤 안 바뀐다 / 공중에서 따라 꺾지 않는다 ---
	var st := lab()
	var td := put(st, "toad", st.player.x + 220.0, st.player.y)
	if until(st, td, "leap_warn", 20.0) < 0.0:
		ok("두꺼비: 착지 예고(확정) 상태에 들어간다", false)
		return
	var locked: Array = (td.leap_at as Array).duplicate()
	var drift := 0.0
	var guard := 0
	while (String(td.state) == "leap_warn" or String(td.state) == "leap") and guard < 2000:
		guard += 1
		st.player.x = clampf(st.player.x + 260.0 * STEP, 40.0, st.arena_w - 40.0) # 확정 뒤 플레이어가 크게 달아난다
		tick(st)
		if td.has("leap_at"):
			var at: Array = td.leap_at
			drift = maxf(drift, PGeom.dist(float(locked[0]), float(locked[1]), float(at[0]), float(at[1])))
	var land_err := PGeom.dist(float(locked[0]), float(locked[1]), td.x, td.y)
	ok("두꺼비: 착지 위치가 **확정 뒤 바뀌지 않는다**(예고·공중 내내 움직인 거리 %.5f px)" % drift, drift < 1e-6)
	ok("두꺼비: **공중에서 플레이어를 따라 꺾지 않는다** — 확정한 자리에 그대로 내려앉는다(오차 %.5f px)" % land_err, land_err < 1e-3)

	# --- 착지 후 빈틈 ---
	var rec := dur_of(st, td, "recover", 25.0)
	ok("두꺼비: 착지 후 **빈틈**이 있다(잰 값 %.2f초 = 시험값 recover %.2f)" % [rec, float(D.recover)],
		rec > 0.0 and near(rec, float(D.recover), 0.03))

	# --- 바위 안·맵 밖 금지 / 여러 마리가 탈출로를 다 덮지 않는다 ---
	var st2 := lab(7, 1, "pillars")
	ok("두꺼비 검사 전장에 장애물이 있다(바위 안 착지 검사가 의미를 갖게)", st2.obstacles.size() > 0, "%d개" % st2.obstacles.size())
	var toads := []
	for i in 4:
		var a: float = float(i) / 4.0 * TAU
		toads.append(put(st2, "toad",
			clampf(st2.player.x + cos(a) * 190.0, 40.0, st2.arena_w - 40.0),
			clampf(st2.player.y + sin(a) * 190.0, 40.0, st2.arena_h - 40.0)))
	var bad_spot := []
	var worst_exits := 99
	var leaps := 0
	var probe := float(D.probe)
	var need := int(D.minExits)
	for j in int(round(45.0 / STEP)):
		tick(st2, { "mx": 1.0 if (j / 90) % 2 == 0 else -1.0, "my": 0.0 }) # 좌우로 흔들어 여러 자리에서 도약이 나오게 한다
		var dangers := []
		for td2 in toads:
			if bool(td2.dead) or not td2.has("leap_at"):
				continue
			var s := String(td2.state)
			if s != "leap_warn" and s != "leap":
				continue
			if s == "leap_warn" and float(td2.state_t) <= STEP:
				leaps += 1
			var at: Array = td2.leap_at
			dangers.append({ "x": float(at[0]), "y": float(at[1]), "r": float(D.landR) })
			if not st2.valid_pos(float(at[0]), float(at[1]), float(td2.r)):
				bad_spot.append("(%.0f,%.0f)" % [float(at[0]), float(at[1])])
		if not dangers.is_empty():
			worst_exits = mini(worst_exits, PEnemiesNew._exits_open(st2, dangers, probe))
	ok("두꺼비: 확정된 착지 자리가 언제나 **유효 위치**다(바위 안·맵 밖이 아니다) — 어긋난 자리 %d개 %s" % [bad_spot.size(), str(bad_spot.slice(0, 5))],
		bad_spot.is_empty() and leaps > 0)
	ok("두꺼비 %d마리: 확정된 착지 원들이 **탈출로를 동시에 다 덮지 않는다**(플레이어 주위 16방향 중 최소 %d방향 열림 ≥ 상한 %d · 도약 %d회 관측)" % [toads.size(), worst_exits, need, leaps],
		worst_exits >= need)

	# --- 규칙이 실제로 '막는' 쪽도 확인한다: 이미 사방이 덮인 상황에서는 도약을 고르지 않는다 ---
	## 위 검사는 실제 전투에서 조건이 깨지지 않음을 보이고, 이 검사는 조건이 깨질 상황을 일부러 만들어
	## **규칙이 자리를 거절하는지**를 본다(빈 배열 = 도약 취소). 둘이 함께 있어야 통과가 우연이 아니다.
	var st3 := lab(9)
	var probe2 := float(D.probe)
	var blockers := []
	for i in 8: # 플레이어 둘레 8방향을 착지 원으로 미리 덮어 둔다
		var a: float = float(i) / 8.0 * TAU
		var b := put(st3, "toad", clampf(st3.player.x + cos(a) * 240.0, 40.0, st3.arena_w - 40.0), clampf(st3.player.y + sin(a) * 240.0, 40.0, st3.arena_h - 40.0))
		b.state = "leap_warn"
		b.state_t = 0.0
		b.leap_at = [st3.player.x + cos(a) * probe2, st3.player.y + sin(a) * probe2]
		blockers.append(b)
	var probe_dangers := []
	for b in blockers:
		var at: Array = b.leap_at
		probe_dangers.append({ "x": float(at[0]), "y": float(at[1]), "r": float(D.landR) })
	var covered := PEnemiesNew._exits_open(st3, probe_dangers, probe2)
	var late := put(st3, "toad", st3.player.x + 150.0, st3.player.y)
	var spot := PEnemiesNew.leap_spot(st3, late)
	ok("두꺼비: 이미 탈출 방향이 %d개뿐(상한 %d 미만)인 상황에서는 **도약할 자리를 고르지 않는다**(취소) — 억지로 내려앉지 않는다" % [covered, need],
		covered < need and spot.is_empty(), str(spot))

# ================= ④ 일반 정예 확장 10종 =================
## [정예, 바탕, 확장 상태, 더한 행동 한 줄]
const ELITE_CHECK := [
	["boar_elite", "boar", "shock_aim", "돌진 끝 예고된 짧은 충격파"],
	["archer_elite", "archer", "shot2_lock", "조준 후 빠른 두 발 사격"],
	["shieldbearer_elite", "shieldbearer", "push_aim", "방패 타격 뒤 짧은 전진 공격"],
	["spider_elite", "spider", "web2_aim", "두 방향 거미줄"],
	["spore_elite", "spore", "residue_aim", "본체 폭발 뒤 제한된 작은 포자 구역 잔류"],
	["rogue_elite", "rogue", "slash3_aim", "접근 베기 뒤 측면 이동과 후속 베기"],
	["burrower_elite", "burrower", "rewarn", "짧은 재잠복 뒤 두 번째 위치를 예고해 다시 출현"],
	["toad_elite", "toad", "slam_aim", "착지 뒤 한 차례 예고된 지면 충격"],
	["frostcaller_elite", "frostcaller", "cast2_aim", "두 지점 순차 공격"],
]

func common_elite_tests() -> void:
	# --- 표 자체 ---
	ok("일반 정예 확장 표에 10종이 있다(늑대 우두머리 + 새 9종)", PEnemiesNew.COMMON_ELITES.size() == 10,
		str(PEnemiesNew.COMMON_ELITES.keys()))
	ok("일반 정예는 **특수 정예 7종과 다른 계층**이다(ELITE_TYPES와 겹치지 않는다)",
		PEnemiesNew.COMMON_ELITES.keys().filter(func(k): return PEnemiesNew.is_elite(String(k))).is_empty())
	ok("늑대 우두머리는 **이미 있는 정예**라 확장 구조에 등록만 했다(더한 행동 없음) — 0.3.1 늑대 규칙과 D33 기준 전투가 그대로다",
		PEnemiesNew.extra_states("wolf_alpha").is_empty() and String((PEnemiesNew.COMMON_ELITES["wolf_alpha"] as Dictionary)["from"]) == "" and PEnemies.is_wolf(PCatalog.enemy("wolf_alpha")))
	ok("늑대 우두머리는 이름·색만 다른 늑대가 아니다(돌진 %d회 vs 늑대 %d회)" % [int((PCatalog.enemy("wolf_alpha").dash as Dictionary).get("dashes", 1)), int((PCatalog.enemy("wolf").dash as Dictionary).get("dashes", 1))],
		int((PCatalog.enemy("wolf_alpha").dash as Dictionary).get("dashes", 1)) > int((PCatalog.enemy("wolf").dash as Dictionary).get("dashes", 1)))

	# --- 정의가 바탕에서 복사되고 새 행동 값만 덮였는가(이름·색만 바꾼 것이 아닌가) ---
	var def_bad := []
	var name_only := []
	for row in ELITE_CHECK:
		var tp := String(row[0])
		var base := String(row[1])
		var d: Dictionary = PCatalog.enemy(tp)
		var bd: Dictionary = PCatalog.enemy(base)
		if PEnemiesNew.base_type(tp) != base or not bool(d.get("elite", false)):
			def_bad.append(tp)
		for k in bd: # 바탕의 행동 값이 하나도 빠지지 않아야 한다(바탕 규칙을 그대로 굴리기 때문)
			if not d.has(k):
				def_bad.append("%s에 바탕 값 %s 없음" % [tp, String(k)])
		var diff := 0 # 이름·역할·색·크기·체력·속도를 뺀 실제 행동 값이 몇 개나 새로 생겼는가
		for k in d:
			var ks := String(k)
			if ks == "name" or ks == "role" or ks == "color" or ks == "r" or ks == "hp" or ks == "speed" or ks == "elite" or ks == "readme":
				continue
			if not bd.has(k) or bd[k] != d[k]:
				diff += 1
		if diff <= 0:
			name_only.append(tp)
	ok("일반 정예 9종의 정의가 바탕 몬스터에서 복사된 뒤 새 행동 값으로 덮인다(elite 표식 포함)", def_bad.is_empty(), str(def_bad))
	ok("**이름·색만 바꾼 것이 아니다** — 9종 모두 바탕에 없던 행동 값을 가진다", name_only.is_empty(), str(name_only))

	# --- 각 정예가 자기 고유 행동을 실제로 실행한다 ---
	for row in ELITE_CHECK:
		var tp := String(row[0])
		var extra := String(row[2])
		var what := String(row[3])
		var st := lab(11)
		var e := put(st, tp, st.player.x + 210.0, st.player.y)
		var reached := until(st, e, extra, 40.0) >= 0.0
		var exec0 := int(st.metrics_for(e).executed)
		var prep := int(st.metrics_for(e).prepared)
		var guard := 0
		while reached and PEnemiesNew.extra_busy(e) and guard < 2000: # 확장 구간이 끝나는 순간이 실행 시점이다
			guard += 1
			tick(st)
		var exec_d := int(st.metrics_for(e).executed) - exec0
		ok("%s: 고유 행동을 **실제로 실행한다** — %s(확장 상태 %s 도달 %s · 그 구간에서 실행 %d회 · 그때까지 예고 %d회)" % [String(PCatalog.enemy(tp).name), what, extra, str(reached), exec_d, prep],
			reached and exec_d >= 1 and prep >= 2)

	# --- 체력만 올린 것이 아니다: 같은 바탕의 일반 개체와 한 연계의 행동 수가 다르다 ---
	for row in ELITE_CHECK:
		var tp := String(row[0])
		var base := String(row[1])
		var extra := String(row[2])
		var ste := lab(11)
		var ee := put(ste, tp, ste.player.x + 210.0, ste.player.y)
		var ce := chain_with(chains(ste, ee, 40.0), extra)
		var stb := lab(11)
		var eb := put(stb, base, stb.player.x + 210.0, stb.player.y)
		var cb := longest_chain(chains(stb, eb, 40.0)) # 일반 개체 쪽에 가장 유리한(가장 긴) 연계와 견준다
		ok("%s: **체력만 올린 것이 아니다** — 한 연계의 행동 수가 일반 %s보다 많다(%d개 %s > %d개 %s)" % [String(PCatalog.enemy(tp).name), String(PCatalog.enemy(base).name), ce.size(), str(ce), cb.size(), str(cb)],
			not ce.is_empty() and ce.size() > cb.size())

	# --- 확장 상태도 '위험 공격 중'으로 센다(동시 위험 공격 상한이 확장으로 새지 않는다) ---
	var danger_bad := []
	for row in ELITE_CHECK:
		var cs := PEnemiesNew.committed_states(String(row[0]))
		if not cs.has(String(row[2])) or cs.size() <= PEnemiesNew.committed_states(String(row[1])).size():
			danger_bad.append(String(row[0]))
	ok("일반 정예 9종: 확장 상태도 **동시 위험 공격 상한**에 함께 센다(danger_limit이 확장으로 새는 구멍이 없다)",
		danger_bad.is_empty(), str(danger_bad))

	# --- 체력: 세계 변화 등급 배율이 정예 체력 위에 겹쳐 곱해지지 않는다 ---
	var tier_bad := []
	var hp_row := []
	for row in ELITE_CHECK:
		var tp := String(row[0])
		var st := lab(13, 3)
		var n := put(st, tp, 200.0, 200.0, "normal")
		var r := put(st, tp, 250.0, 200.0, "red")
		var a := put(st, tp, 300.0, 200.0, "apex")
		if not (is_equal_approx(float(n.hp), float(r.hp)) and is_equal_approx(float(n.hp), float(a.hp))):
			tier_bad.append("%s %.0f/%.0f/%.0f" % [tp, float(n.hp), float(r.hp), float(a.hp)])
		if not is_equal_approx(float(n.hp), PPacing.elite_hp(tp, 3)):
			tier_bad.append("%s 표와 다름(%.0f != %.0f)" % [tp, float(n.hp), PPacing.elite_hp(tp, 3)])
		hp_row.append("%s %.0f" % [tp, float(n.hp)])
	ok("일반 정예 9종: **붉은·상위 변이 배율이 겹쳐 곱해지지 않는다** — 등급이 달라도 막별 표(elite_by_act)의 절대값 그대로다(3막: %s)" % ", ".join(hp_row),
		tier_bad.is_empty(), str(tier_bad))

	# --- 바탕의 사용자 확정값을 그대로 물려받는가(방패병 정면 감소) ---
	## 정예 정의는 data/enemies.json의 바탕 값을 복사하는데, 거기에는 확정 전 값(frontMult 0.15)이 남아 있다.
	## build_def가 바탕의 겹쳐쓰기(data/pacing.json enemy_tuning.shieldbearer)까지 함께 물려받아야
	## 정예만 혼자 옛 값(85% 감소)을 쓰는 일이 없다.
	var st_sb := lab(14)
	var sb := put(st_sb, "shieldbearer", 700.0, 300.0)
	var sbe := put(st_sb, "shieldbearer_elite", 760.0, 300.0)
	sb.face = 0.0
	sbe.face = 0.0
	ok("돌격 방패병: 정면 감소가 **바탕 방패병의 사용자 확정값 그대로**다(정예 %.2f = 일반 %.2f · enemies.json의 옛 값 %.2f가 아니다)" % [PEnemiesNew.dv(sbe, "frontMult", 1.0), PEnemiesNew.dv(sb, "frontMult", 1.0), float(PCatalog.enemy("shieldbearer").frontMult)],
		is_equal_approx(PEnemiesNew.dv(sbe, "frontMult", 1.0), PEnemiesNew.dv(sb, "frontMult", 1.0)) and is_equal_approx(PEnemiesNew.dv(sbe, "frontMult", 1.0), 0.30))
	var guard_states := { "approach": true, "bash_aim": true, "bash": false, "push_aim": false, "recover": false }
	var guard_bad := []
	for s in guard_states:
		sbe.state = String(s)
		if PEnemiesNew.guard_closed(sbe) != bool(guard_states[s]):
			guard_bad.append(String(s))
	sbe.state = "approach"
	ok("돌격 방패병: 방패가 열리는 구간이 바탕과 같고, **확장이 끼운 전진 공격 준비(push_aim)도 열린 구간**이다 — 반격 창이 짧아지지 않는다",
		guard_bad.is_empty(), str(guard_bad))

	# --- 계층이 뒤집히지 않는다: 바탕 일반 개체 < 일반 정예 < 특수 정예 ---
	var layer_bad := []
	for row in ELITE_CHECK:
		var tp := String(row[0])
		var base := String(row[1])
		var base_hp := PPacing.tier_hp(base, "normal")
		if base_hp <= 0.0:
			base_hp = float(PCatalog.enemy(base).hp)
		if PPacing.elite_hp(tp, 1) <= base_hp:
			layer_bad.append("%s ≤ %s" % [tp, base])
		if PPacing.elite_hp(tp, 1) >= PPacing.elite_hp("elite_blademaster", 1):
			layer_bad.append("%s ≥ 특수 정예 검사" % tp)
	ok("일반 정예 9종의 1막 체력이 계층을 지킨다(바탕 일반 개체보다 위 · 가장 두꺼운 특수 정예보다 아래)",
		layer_bad.is_empty(), str(layer_bad))
