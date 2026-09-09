extends SceneTree
## 전투 말미·압박 규칙 검사(화면 없음).
## 실행: python tools/run_suites.py --suites enemy_pace_tests
##      (직접: godot --headless --path prophecy_godot -s tests/enemy_pace_tests.gd)
##
## 무엇을 보는가 — 2026-09-09 사람 관찰("전투 말미가 지루하다")에 대한 규칙 쪽 대응
##  ① **동시 위험 공격 상한**이 실제로 걸린다(적 생존 수와 분리된다).
##  ② 상한은 **새 공격만** 막는다 — 이미 시작한 예고를 끊지 않는다.
##  ③ 적을 지우거나 자동 처치하지 않는다(문제를 숨기지 않는다).
##  ④ **늑대 계열은 막지 않는다** — 0.3.1 규칙과 승인된 첫 전투(D33) 보존.
##  ⑤ 보스전에는 적용하지 않는다(그쪽은 overlap_limit 담당).
##  ⑥ 종류별 동시 생존 상한 제안표(data/pacing.json)가 앞뒤가 맞는다.
##
## 실제 편성에서 잰 말미 수치는 여기가 아니라 tools/tail_probe.gd다(계측이지 판정이 아니다).

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 적이 저절로 나오지 않고 자동 공격도 없는 빈 전장(적 규칙만 본다)
func lab(seed_v: int = 1, act: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": act })
	st.spawn_hold = true
	st.weapons = []
	return st

## 플레이어 둘레에 n마리를 고리로 놓는다
func ring(st: CombatState, type: String, n: int, radius: float) -> Array:
	var out := []
	for i in n:
		var a: float = float(i) / float(n) * TAU
		out.append(st.spawn_enemy(type, st.player.x + cos(a) * radius, st.player.y + sin(a) * radius))
	return out

## seconds 만큼 진행하며 동시 위험 공격 수의 최고치를 기록한다(플레이어는 죽지 않게 눌러 둔다)
func play_watch(st: CombatState, seconds: float) -> Dictionary:
	var n := int(round(seconds / STEP))
	var max_danger := 0
	var entered := {}   # 예고에 들어간 개체 id
	var executed := {}  # 실제 실행까지 간 개체 id
	var stuck := {}     # 마지막 순간에도 예고 중이던 개체 id
	for i in n:
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		var d := 0
		stuck = {}
		for e in st.enemies:
			if e.dead or bool(e.get("structure", false)):
				continue
			if PEnemiesNew.danger_busy(e):
				d += 1
				entered[int(e.id)] = true
				stuck[int(e.id)] = true
			if int(e.get("executed", 0)) > 0:
				executed[int(e.id)] = true
		max_danger = maxi(max_danger, d)
	return { "max_danger": max_danger, "entered": entered.size(), "executed": executed.size(), "stuck": stuck.size(), "alive": st.alive_units() }

func _init() -> void:
	var C: Dictionary = PCatalog.pacing().get("danger_limit", {})

	# --- ① 표가 있고 켜져 있다 ---
	var by: Dictionary = C.get("by_act", {})
	ok("동시 위험 공격 상한 표가 켜져 있고 1·2·3막 값이 있다(시험값, data/pacing.json danger_limit)",
		bool(C.get("enabled", false)) and by.has("1") and by.has("2") and by.has("3"),
		"1막 %s · 2막 %s · 3막 %s" % [str(by.get("1", "없음")), str(by.get("2", "없음")), str(by.get("3", "없음"))])

	# --- ② 상한이 실제로 걸린다: 상한보다 많은 방패병을 붙여도 동시 위험 공격은 상한을 넘지 않는다 ---
	for act in [1, 2, 3]:
		var cap: int = int(by[str(act)])
		var st := lab(1, act)
		ring(st, "shieldbearer", cap + 5, 120.0)
		var w := play_watch(st, 8.0)
		ok("%d막: 방패병 %d마리를 붙여도 동시 위험 공격은 상한 %d를 넘지 않는다(적 생존 수와 분리)" % [act, cap + 5, cap],
			int(w.max_danger) <= cap and int(w.max_danger) > 0,
			"최고 동시 위험 공격 %d / 상한 %d · 살아 있는 적 %d마리" % [int(w.max_danger), cap, int(w.alive)])

	# --- ③ 새 공격만 막는다: 이미 시작한 예고는 끊기지 않고 실행까지 간다 ---
	var st_k := lab(2, 1)
	ring(st_k, "shieldbearer", 12, 120.0)
	var wk := play_watch(st_k, 8.0)
	ok("상한은 **새 공격만** 막는다 — 예고에 들어간 개체는 끊기지 않고 실행까지 간다(마지막 순간 예고 중인 개체는 제외)",
		int(wk.executed) + int(wk.stuck) >= int(wk.entered) and int(wk.entered) > 0,
		"예고 %d마리 · 실행 %d마리 · 끝난 순간 예고 중 %d마리" % [int(wk.entered), int(wk.executed), int(wk.stuck)])

	# --- ④ 적을 지우거나 자동 처치하지 않는다 ---
	var st_n := lab(3, 2)
	var many := ring(st_n, "boar", 14, 220.0)
	var n0 := st_n.alive_units()
	play_watch(st_n, 6.0)
	var dead_n := 0
	for e in many:
		if e.dead:
			dead_n += 1
	ok("문제를 숨기지 않는다: 상한이 걸려도 적을 지우거나 자동 처치하지 않는다",
		st_n.alive_units() == n0 and dead_n == 0 and int(st_n.stats.kills) == 0,
		"등장 %d마리 → 살아 있음 %d마리 · 처치 %d" % [n0, st_n.alive_units(), int(st_n.stats.kills)])

	# --- ⑤ 늑대 계열은 세기만 하고 막지 않는다(0.3.1 규칙·D33 보존) ---
	var cap1: int = int(by["1"])
	var st_w := lab(4, 1)
	ring(st_w, "wolf", cap1 + 6, 60.0)
	var ww := play_watch(st_w, 6.0)
	ok("늑대 계열은 상한에 걸리지 않는다(0.3.1 규칙·승인된 첫 전투 D33 보존) — 상한 %d를 넘겨 물 수 있다" % cap1,
		int(ww.max_danger) > cap1,
		"늑대 %d마리에서 최고 동시 위험 공격 %d(상한 %d)" % [cap1 + 6, int(ww.max_danger), cap1])

	# --- ⑥ 보스전에는 적용하지 않는다(그쪽은 overlap_limit 담당) ---
	var st_b := lab(5, 1)
	var busy := ring(st_b, "shieldbearer", cap1 + 2, 120.0)
	for e in busy:
		e.state = "bash_aim" # 전부 위험 공격 중으로 만든다
		e.state_t = 0.0
	var probe := st_b.spawn_enemy("shieldbearer", st_b.player.x + 300.0, st_b.player.y)
	var blocked_normal: bool = not PEnemiesNew.may_start(st_b, probe, STEP)
	st_b.mode = "boss"
	var allowed_boss: bool = PEnemiesNew.may_start(st_b, probe, STEP)
	st_b.mode = "fight"
	ok("보스전에는 이 상한을 적용하지 않는다(overlap_limit·wolf_may_attack이 이미 담당)",
		blocked_normal and allowed_boss,
		"일반 전투 %s · 보스전 %s" % ["막힘" if blocked_normal else "안 막힘", "통과" if allowed_boss else "막힘"])

	# --- ⑦ 세는 범위: 신규 8종·정예 + 늑대·궁수·포자 ---
	var st_c := lab(6, 1)
	var counted := true
	var missing := []
	for tp in ["boar", "shieldbearer", "shaman", "bomber", "burrower", "spider", "frostcaller", "rogue", "wolf", "archer", "spore"]:
		var e := st_c.spawn_enemy(tp, st_c.player.x + 400.0, st_c.player.y)
		var states: Array = PEnemiesNew.COMMITTED.get(tp, PEnemiesNew.LEGACY_DANGER.get(tp, []))
		if states.is_empty():
			counted = false
			missing.append(tp)
			continue
		e.state = String(states[0])
		if not PEnemiesNew.danger_busy(e):
			counted = false
			missing.append(tp)
		e.dead = true
	ok("동시 위험 공격은 신규 8종·특수 정예뿐 아니라 늑대 계열·궁수·포자도 **센다**(막지는 않는다)",
		counted, str(missing))

	# --- ⑧ 종류별 동시 생존 상한 제안표(아직 미연결)가 앞뒤가 맞는다 ---
	var P: Dictionary = PCatalog.pacing().get("type_alive_cap_proposal", {})
	var share: Dictionary = P.get("share_by_type", {})
	var bad := []
	for tp in share:
		if PCatalog.enemies().has(String(tp)):
			if float(share[tp]) <= 0.0 or float(share[tp]) > 1.0:
				bad.append("%s 비율 %s" % [String(tp), str(share[tp])])
		else:
			bad.append("%s 없는 적" % String(tp))
	ok("종류별 동시 생존 상한 제안표: 종류가 모두 실제 적이고 비율이 0~1이며 최소값 2 이상(아직 읽는 코드가 없다 — docs/ENEMY_FEEDBACK.md의 훅 목록)",
		bad.is_empty() and share.size() > 0 and int(P.get("min_cap", 0)) >= 2,
		"%d종 · 최소 %d %s" % [share.size(), int(P.get("min_cap", 0)), str(bad)])

	lizard_tail_tests()

	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# =========================================================================
# §12 도마뱀 말미 등장(2026-09-10). 네 가지를 **구분해서** 본다:
#   ㉠ 종류별 동시 생존 상한 · ㉡ 등장 간격 · ㉢ 분대 이월 · ㉣ 위험 공격 제한
# 이 넷은 서로 다른 규칙이고, 말미가 늘어진 원인은 그중 **㉠ 하나**였다.
# =========================================================================
func lizard_tail_tests() -> void:
	print("")
	print("[§12 도마뱀 말미 등장] 종류별 생존 상한 · 등장 간격 · 분대 이월 · 위험 공격 제한을 구분해 본다")
	var P: Dictionary = PCatalog.pacing().get("type_alive_cap_proposal", {})
	var share: Dictionary = P.get("share_by_type", {})
	# ㉠ 누락 확인: 이 표에 도마뱀이 없으면 편성표의 고정값(2)에 묶인다
	ok("§12 ㉠ 종류별 생존 상한 비율표에 **도마뱀(lizard)**이 들어 있다(2026-09-10 이전에는 빠져 있었다)",
		share.has("lizard"), "lizard %s · bat %s · toad %s" % [str(share.get("lizard", "없음")), str(share.get("bat", "없음")), str(share.get("toad", "없음"))])
	var missing: Array = []
	for t in ["lizard", "bat", "toad"]:
		if not share.has(String(t)):
			missing.append(String(t))
	ok("§12 ㉠ 신규 일반 3종이 모두 표에 있다(같은 이유로 함께 빠져 있었다)", missing.is_empty(), str(missing))

	# ㉠ 실제 계산: 2막 동시 상한 15에서 편성표 고정값 2가 비율로 커진다
	var caps := PPacing.type_alive_cap({ "lizard": 2, "shieldbearer": 3, "shaman": 1 }, 15)
	ok("§12 ㉠ 2막(동시 상한 15) 도마뱀 상한 2 → %d(비율 %.2f). 총 등장 수·경험치는 건드리지 않는다" % [int(caps.lizard), float(share.get("lizard", 0.0))],
		int(caps.lizard) > 2 and int(caps.lizard) == maxi(2, int(round(15.0 * float(share.lizard)))),
		"보정 뒤 %s" % str(caps))
	ok("§12 ㉠ 편성에 없는 종류를 새로 만들지 않는다(표에 있어도 0이면 그대로 0)",
		not PPacing.type_alive_cap({ "shieldbearer": 3 }, 15).has("lizard"))

	# ㉣ 위험 공격 제한: 종류별 동시 상한이 **따로** 있다(생존 상한을 올려도 동시 화염이 부풀지 않게)
	var DL: Dictionary = PCatalog.pacing().get("danger_limit", {})
	var by_type: Dictionary = DL.get("by_type", {})
	ok("§12 ㉣ 종류별 **동시 위험 공격** 상한이 따로 있고 도마뱀이 %s로 묶여 있다" % str(by_type.get("lizard", "없음")),
		by_type.has("lizard") and int(by_type.lizard) >= 1,
		"전체 상한 by_act %s · 종류별 %s" % [str(DL.get("by_act", {})), str(by_type)])
	ok("§12 ㉣ 표에 없는 종류는 상한이 없다(기존 동작 그대로)", PEnemiesNew.danger_type_max("boar") >= 9999)

	# ㉣ 실제로 걸린다: 도마뱀 6마리를 둘러 세워도 동시에 불을 뿜는 수가 상한을 넘지 않는다
	var st := lab(3, 2)
	var lz := ring(st, "lizard", 6, 210.0)
	var seen := play_watch(st, 12.0)
	var maxfire := 0
	var st2 := lab(3, 2)
	var lz2 := ring(st2, "lizard", 6, 210.0)
	for i in int(round(12.0 / STEP)):
		st2.step({}, STEP)
		st2.player.hp = st2.player.hp_max
		st2.player.dead = false
		if st2.status == "lost":
			st2.status = "running"
		var n := 0
		for e in st2.enemies:
			if not bool(e.dead) and PEnemiesNew.danger_busy(e):
				n += 1
		maxfire = maxi(maxfire, n)
	ok("§12 ㉣ 도마뱀 %d마리를 둘러 세워도 동시에 불을 준비·분사하는 수가 상한 %d를 넘지 않는다 — **피할 수 없는 동시 화염**을 만들지 않는다" % [lz2.size(), int(by_type.get("lizard", 9999))],
		maxfire <= int(by_type.get("lizard", 9999)), "관찰한 최고 동시 수 %d (첫 관찰 %d마리)" % [maxfire, int(seen.get("max_danger", 0))])
	ok("§12 ㉣ 상한은 **새 공격만** 막는다 — 여전히 모두가 번갈아 공격한다(굶는 개체가 없다)",
		int(seen.get("entered", 0)) >= lz.size() - 1, "예고에 들어간 개체 %d/%d" % [int(seen.get("entered", 0)), lz.size()])

	# ㉡·㉢은 다른 규칙이라는 것을 값으로 남긴다(이번에 바꾸지 않았다)
	var SP: Dictionary = PCatalog.pacing().get("spawn", {})
	ok("§12 ㉡ 등장 간격·㉢ 분대 이월은 **이번에 바꾸지 않았다**(말미 원인은 ㉠이었다)",
		is_equal_approx(float(SP.get("tail_group_mult", 0.0)), 1.5) and bool(SP.get("squad_mixing", false)),
		"말미 묶음 배율 %.1f · 분대 혼합 %s" % [float(SP.get("tail_group_mult", 0.0)), str(SP.get("squad_mixing", false))])
