extends SceneTree
## 냉기 기본 특성(둔화 → 냉기 중첩 → 빙결 → 주무기 파쇄)과 서리 개조 3종 검사(화면 없음).
## 실행: python tools/run_suites.py --suites frost_tests
##      (직접: godot --headless --path prophecy_godot -s tests/frost_tests.gd)
##
## 무엇을 못박는가(사용자 확정 2026-09-09 · docs/FROST.md · docs/FROST_CONTRACT.md)
##  1. 냉기 중첩은 **실제 적중 이벤트**로만 오른다. 프레임만 굴려서는 절대 오르지 않는다.
##  2. 5중첩 → 일반 적 빙결(hard). 이동도 공격도 실제로 멈춘다(위치·상태로 확인).
##  3. 정예 빙결 시간 < 일반 적 빙결 시간.
##  4. 보스는 결빙(soft)이라 이동·공격이 멈추지 않고 패턴 단계·예고 타이머도 초기화되지 않는다.
##  5. 파쇄를 터뜨리는 것은 **주무기 공격뿐**이다(지속 피해·장판·보조·지뢰는 못 깬다).
##  6. 주무기 개조가 만든 직접 추가 타격은 자격표대로 깰 수 있다.
##  7. 한 번의 빙결에 파쇄는 한 번. 같은 프레임 다중 적중에서도 중복 정산되지 않는다.
##  8. 파쇄 추가 피해·파편은 냉기를 쌓지 않고 다른 빙결을 파쇄하지 않는다(재귀 차단).
##  9. 파쇄·빙결 종료 뒤 중첩 0 + 재빙결 제한.
## 10. 얼린 적의 예고와 실제 공격 판정이 어긋나지 않는다(빙결 중에는 예고가 진행되지 않는다).
## 11. 서리 개조 3종이 각각 다른 지표를 움직인다.
## 12. **개조를 하나도 고르지 않아도** 빙결과 파쇄가 일어난다.
## 13. 옛 저장의 개조 id가 그대로 남고 조용히 삭제·재추첨되지 않는다.
##
## 수치는 전부 **시험값**이다(data/supports.json tuning.frost). 사람이 승인한 밸런스가 아니다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 시험실 ----------
## ids = [[무기 id, 레벨, [개조...]], ...]. auto=false면 자동기술을 끈다(적중 이벤트를 손으로만 만든다)
func lab(ids: Array = [], seed_v: int = 1, commons: Dictionary = {}, auto: bool = false) -> CombatState:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = []
	for r in ids:
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	for k in commons:
		(g.commons as Dictionary)[String(k)] = int(commons[k])
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [], "arena": "clearing", "region_id": "lab", "act": 1 })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 480.0
	st.player.y = 300.0
	if not auto:
		st.player.attack_timer = 1.0e9 # 자동기술 정지 훅(PWeapons.update가 읽는다)
	return st

func mob(st: CombatState, type: String, dx: float, dy: float, hp: float = 1.0e6) -> Dictionary:
	var e: Dictionary = st.spawn_enemy(type, st.player.x + dx, st.player.y + dy)
	e.hp = hp
	e.hp_max = hp
	return e

## 플레이어를 계속 살려 두고 진행한다(연계 전체를 보기 위해)
func play(st: CombatState, seconds: float) -> void:
	for i in int(round(seconds / STEP)):
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"

## 적을 제자리에 묶어 두고 진행한다(기하가 흔들리지 않아야 개조 비교가 성립한다)
func play_static(st: CombatState, pinned: Array, seconds: float) -> void:
	var home := []
	for e in pinned:
		home.append([float(e.x), float(e.y)])
	for i in int(round(seconds / STEP)):
		for k in pinned.size():
			pinned[k].x = home[k][0]
			pinned[k].y = home[k][1]
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"

func meter(st: CombatState, key: String) -> float:
	return PSupport.metered(st, "frost", key)

# ---------- 적중 이벤트 흉내(경로별) ----------
## 냉기를 실은 적중. 피해 0이라 적이 죽지 않는다 — 중첩·빙결만 본다
func cold_hit(st: CombatState, e: Dictionary, wid: String = "frost") -> void:
	st.damage_enemy(e, 0.0, { "chill": 2.0, "src": { "weapon_id": wid, "direct": true } })

func hit_as(st: CombatState, e: Dictionary, o: Dictionary, amount: float = 1.0) -> void:
	st.damage_enemy(e, amount, o)

func main_direct() -> Dictionary:
	return { "src": { "weapon_id": "sword", "direct": true } }

func main_extra() -> Dictionary:
	return { "src": { "weapon_id": "sword", "direct": true, "extra": true } }

func support_direct() -> Dictionary:
	return { "src": { "weapon_id": "blades", "direct": true } }

func zone_tick() -> Dictionary:
	return { "src": { "weapon_id": "ember", "direct": false, "extra": true } }

func dot_hit() -> Dictionary:
	return { "src": { "extra": true, "direct": false }, "dot": "burn", "dot_src": "common" }

func mine_blast() -> Dictionary:
	return { "cause": "mine", "ground": true, "src": { "weapon_id": "mine", "direct": true } }

## 중첩이 가득 차 얼 때까지 냉기 적중을 반복한다. 실제로 얼었으면 true
func freeze_by_hits(st: CombatState, e: Dictionary) -> bool:
	var mx := int(st.frost_cfg().get("stackMax", 5))
	for i in mx:
		cold_hit(st, e)
	return st.is_frozen(e)

func _init() -> void:
	var F := PCatalog.support_tuning("frost")

	# ---------- 0. 자료 계약 ----------
	ok("냉기 시험값이 자료에 있다(코드에 숫자를 두지 않는다)",
		not F.is_empty() and F.has("stackMax") and F.has("freezeSec") and F.has("refreezeSec") and F.has("shards"),
		str(F.keys()))
	ok("모든 시험값에 근거가 적혀 있다", String(F.get("why", "")) != "")

	# ---------- 1. 중첩은 적중 이벤트당 1. 프레임으로는 오르지 않는다 ----------
	var st := lab([["frost", 1, []]])
	var w1 := mob(st, "wolf", 260.0, 0.0)
	cold_hit(st, w1)
	ok("냉기 적중 1회 = 중첩 1", int(w1.chill_n) == 1, "중첩 %d" % int(w1.chill_n))
	for i in 100:
		st.step({}, STEP)
	ok("같은 상태로 프레임만 100번 굴려도 중첩이 오르지 않는다", int(w1.chill_n) == 1, "중첩 %d" % int(w1.chill_n))
	cold_hit(st, w1)
	cold_hit(st, w1)
	ok("적중을 두 번 더하면 중첩 3", int(w1.chill_n) == 3, "중첩 %d" % int(w1.chill_n))
	# 여러 냉기 공급원이 같은 타격에 겹쳐도 피해 이벤트 하나는 중첩 1이다
	var st_two := lab([["frost", 1, []]], 1, { "frost": 1 })
	var w_two := mob(st_two, "wolf", 260.0, 0.0)
	st_two.damage_enemy(w_two, 0.0, { "chill": 2.0, "src": { "weapon_id": "sword", "direct": true } })
	ok("공용 증강 '얼음 파편'과 냉기 탄환이 같은 타격에 겹쳐도 중첩은 1(중복 적중 금지)",
		int(w_two.chill_n) == 1, "중첩 %d" % int(w_two.chill_n))

	# ---------- 2. 5중첩 → 일반 적 빙결(hard). 이동·공격이 멈춘다 ----------
	st = lab([["frost", 1, []]])
	var wf := mob(st, "wolf", 300.0, 0.0)
	play(st, 0.6)
	var moved_before: float = PGeom.dist(wf.x, wf.y, st.player.x + 300.0, 300.0 - 300.0 + st.player.y)
	var x_before: float = float(wf.x)
	play(st, 0.5)
	ok("얼기 전 늑대는 실제로 다가온다(대조군)", absf(float(wf.x) - x_before) > 1.0,
		"이동 %.1f (초기 이탈 %.1f)" % [absf(float(wf.x) - x_before), moved_before])
	ok("5중첩에 도달하면 일반 적이 빙결된다(hard)",
		freeze_by_hits(st, wf) and String(wf.freeze_kind) == "hard",
		"freeze %.2f kind %s" % [float(wf.freeze), String(wf.freeze_kind)])
	var fx_freeze := false
	for f in st.effects:
		if String(f.get("kind", "")) == "freeze_on" and String(f.get("freeze_kind", "")) == "hard":
			fx_freeze = true
	ok("빙결 순간 화면 신호 freeze_on(hard)을 낸다(계약 3절)", fx_freeze)
	var fx0: float = float(wf.x)
	var fy0: float = float(wf.y)
	var state0 := String(wf.state)
	var state_t0: float = float(wf.state_t)
	play(st, 0.5) # 빙결 지속(일반 1.0초) 안쪽
	ok("빙결 중에는 이동이 멈춘다(위치 불변)",
		is_equal_approx(float(wf.x), fx0) and is_equal_approx(float(wf.y), fy0),
		"(%.2f,%.2f) → (%.2f,%.2f)" % [fx0, fy0, float(wf.x), float(wf.y)])
	ok("빙결 중에는 행동이 멈춘다(상태·상태 시간 불변 = 공격 준비도 진행되지 않는다)",
		String(wf.state) == state0 and is_equal_approx(float(wf.state_t), state_t0),
		"%s(%.3f) → %s(%.3f)" % [state0, state_t0, String(wf.state), float(wf.state_t)])
	ok("빙결 중 이동 속도 배율이 0이다(갱신 밖에서 움직이는 경로도 막는다)",
		is_zero_approx(st.enemy_speed_mult(wf)))
	play(st, 0.7)
	ok("빙결이 끝나면 다시 움직인다", not st.is_frozen(wf) and absf(float(wf.x) - fx0) > 0.5,
		"이동 %.1f" % absf(float(wf.x) - fx0))

	# ---------- 3. 정예 빙결 시간 < 일반 적 빙결 시간 ----------
	st = lab([["frost", 1, []]])
	var n_normal := mob(st, "wolf", 260.0, 0.0)
	var n_elite := mob(st, "wolf_alpha", -260.0, 0.0)
	freeze_by_hits(st, n_normal)
	freeze_by_hits(st, n_elite)
	ok("정예 빙결 시간 < 일반 적 빙결 시간",
		float(n_elite.freeze) < float(n_normal.freeze) and float(n_elite.freeze) > 0.0,
		"정예 %.2f초 < 일반 %.2f초" % [float(n_elite.freeze), float(n_normal.freeze)])
	ok("일반 적 빙결은 약 1초(사용자 출발점)", is_equal_approx(float(n_normal.freeze), 1.0), "%.2f초" % float(n_normal.freeze))
	ok("일반·정예 모두 hard(이동·공격 정지)", String(n_normal.freeze_kind) == "hard" and String(n_elite.freeze_kind) == "hard")

	# ---------- 4. 보스: 결빙(soft) — 멈추지 않고 패턴도 초기화되지 않는다 ----------
	var bo := boss_lab()
	var bz: Dictionary = bo.boss
	play(bo, 3.0)
	var b_state := String(bz.state)
	var b_state_t: float = float(bz.state_t)
	var b_x: float = float(bz.x)
	freeze_by_hits(bo, bz)
	ok("보스는 결빙(soft)이다", st_frozen_soft(bo, bz), "kind %s freeze %.2f" % [String(bz.freeze_kind), float(bz.freeze)])
	ok("결빙은 보스의 패턴 단계를 초기화하지 않는다(같은 단계에서 이어 간다)",
		String(bz.state) == b_state and float(bz.state_t) >= b_state_t,
		"%s(%.3f) → %s(%.3f)" % [b_state, b_state_t, String(bz.state), float(bz.state_t)])
	var b_t0: float = float(bz.state_t)
	var b_x0: float = float(bz.x)
	var b_y0: float = float(bz.y)
	play(bo, 0.4)
	ok("결빙 중에도 보스의 예고 타이머가 계속 흐른다(취소·초기화 없음)",
		float(bz.state_t) > b_t0 or String(bz.state) != b_state,
		"%s(%.3f) → %s(%.3f)" % [b_state, b_t0, String(bz.state), float(bz.state_t)])
	ok("결빙 중에도 보스는 움직인다(이동·공격 정지 없음)",
		PGeom.dist(b_x0, b_y0, float(bz.x), float(bz.y)) > 0.5 or String(bz.state) != b_state,
		"이동 %.2f (시작 x %.1f)" % [PGeom.dist(b_x0, b_y0, float(bz.x), float(bz.y)), b_x])
	ok("보스는 빙결 정지 판정에 걸리지 않는다", not bo.is_hard_frozen(bz) and bo.enemy_speed_mult(bz) > 0.0)
	# 결빙 중에도 파쇄 추가 피해와 파편은 발생한다
	var hp_before: float = float(bz.hp)
	var sh_before := meter(bo, "shatters")
	hit_as(bo, bz, main_direct(), 1.0)
	ok("보스의 결빙도 주무기로 파쇄된다(추가 피해 발생)",
		meter(bo, "shatters") == sh_before + 1.0 and float(bz.hp) < hp_before - 1.0,
		"체력 %.1f → %.1f" % [hp_before, float(bz.hp)])

	# ---------- 5. 무엇이 파쇄를 터뜨리고 무엇이 못 터뜨리는가 ----------
	ok("자격표에 파쇄 규칙이 있고 이유가 적혀 있다",
		(PCatalog.eligibility().get("effects", {}) as Dictionary).has("frost_shatter")
		and String(PCatalog.eligibility().effects.frost_shatter.get("why", "")) != "")
	ok("자격표: 주무기 직접 타격은 파쇄한다", PSupport.eligible("frost_shatter", "main_direct"))
	ok("자격표: 지속 피해·장판·보조 공격·지뢰 폭발은 파쇄하지 못한다",
		not PSupport.eligible("frost_shatter", "dot") and not PSupport.eligible("frost_shatter", "zone_tick")
		and not PSupport.eligible("frost_shatter", "support_direct") and not PSupport.eligible("frost_shatter", "mine_blast"))
	ok("자격표: 잔영 분신의 모방 타격은 파쇄하지 못한다(보조가 낸 타격이다)",
		not PSupport.eligible("frost_shatter", "echo_direct"))
	ok("자격표: 파쇄 추가 피해·얼음 파편은 다시 파쇄하지 못한다(순환 금지)",
		not PSupport.eligible("frost_shatter", "frost_shatter") and not PSupport.eligible("frost_shatter", "frost_shard"))
	# 실제 전투에서도 같은지 경로별로 따로 확인한다
	ok("실제 전투: 주무기 직접 타격이 파쇄를 일으킨다", shatter_case(main_direct()))
	ok("실제 전투: 지속 피해(출혈·화상)는 파쇄하지 못한다", not shatter_case(dot_hit()))
	ok("실제 전투: 장판 지속 피해는 파쇄하지 못한다", not shatter_case(zone_tick()))
	ok("실제 전투: 보조무기의 직접 공격은 파쇄하지 못한다", not shatter_case(support_direct()))
	ok("실제 전투: 지뢰 폭발은 파쇄하지 못한다", not shatter_case(mine_blast()))
	# 얼린 그 타격은 깨뜨리지 않는다 — 그러지 않으면 냉기를 실은 주무기 한 방이 얼리자마자 같은 호출에서
	# 깨 버려 빙결이 한 프레임도 보이지 않는다('얼리고 → 내가 깬다'의 두 박자가 사라진다)
	var st_same := lab([["sword", 1, []]], 1, { "frost": 1 })
	var e_same := mob(st_same, "wolf", 260.0, 0.0)
	for i in int(st_same.frost_cfg().get("stackMax", 5)):
		st_same.damage_enemy(e_same, 0.0, main_direct())
	ok("냉기를 실은 주무기 타격이 얼렸다면 **그 타격은** 깨뜨리지 않는다(빙결이 남는다)",
		st_same.is_frozen(e_same) and meter(st_same, "shatters") == 0.0,
		"freeze %.2f · 파쇄 %.0f회" % [float(e_same.freeze), meter(st_same, "shatters")])
	hit_as(st_same, e_same, main_direct(), 1.0)
	ok("다음 주무기 타격이 그 빙결을 깨뜨린다", meter(st_same, "shatters") == 1.0)

	# ---------- 6. 주무기 개조가 만든 직접 추가 타격 ----------
	ok("자격표: 주무기 개조가 만든 직접 추가 타격은 파쇄한다", PSupport.eligible("frost_shatter", "main_extra"))
	ok("실제 전투: 주무기 개조가 만든 직접 추가 타격이 파쇄를 일으킨다", shatter_case(main_extra()))

	# ---------- 7. 한 번의 빙결에 파쇄는 한 번 ----------
	st = lab([["frost", 1, []]])
	var s1 := mob(st, "wolf", 260.0, 0.0)
	freeze_by_hits(st, s1)
	hit_as(st, s1, main_direct(), 1.0)
	var after_one := meter(st, "shatters")
	hit_as(st, s1, main_direct(), 1.0) # 같은 프레임의 두 번째 적중
	hit_as(st, s1, main_direct(), 1.0) # 세 번째
	ok("같은 프레임 다중 적중에서도 파쇄는 한 번만 정산된다",
		after_one == 1.0 and meter(st, "shatters") == 1.0, "%.0f회" % meter(st, "shatters"))
	ok("파쇄가 나면 빙결이 해제된다", not st.is_frozen(s1))

	# ---------- 8. 파쇄 추가 피해·파편의 재귀 차단 ----------
	st = lab([["frost", 1, []]])
	var a1 := mob(st, "wolf", 240.0, 0.0)
	var a2 := mob(st, "wolf", 240.0, 40.0)   # 파편 반경(80) 안
	freeze_by_hits(st, a1)
	freeze_by_hits(st, a2)
	var stacks_before := meter(st, "chill_stacks")
	var a2_freeze: float = float(a2.freeze)
	hit_as(st, a1, main_direct(), 1.0)
	ok("파쇄 추가 피해와 파편은 냉기를 다시 쌓지 않는다",
		meter(st, "chill_stacks") == stacks_before, "%.0f → %.0f" % [stacks_before, meter(st, "chill_stacks")])
	ok("파편은 옆에서 얼어 있는 다른 적을 파쇄하지 못한다(연쇄 파쇄 금지)",
		meter(st, "shatters") == 1.0 and st.is_frozen(a2) and not bool(a2.freeze_broke),
		"파쇄 %.0f회 · 옆 적 freeze %.2f(전 %.2f) broke %s" % [meter(st, "shatters"), float(a2.freeze), a2_freeze, str(bool(a2.freeze_broke))])
	ok("파편은 실제로 옆 적을 맞혔다(연쇄만 막고 피해까지 없앤 것이 아니다)",
		meter(st, "shard_hits") >= 1.0 and meter(st, "shard_dmg") > 0.0,
		"%.0f회 · %.1f 피해" % [meter(st, "shard_hits"), meter(st, "shard_dmg")])
	var fx_sh := {}
	for f in st.effects:
		if String(f.get("kind", "")) == "shatter":
			fx_sh = f
	ok("화면 신호 shatter의 파편 수 = 실제 판정에 쓰인 수(장식 파편을 그리지 않는다)",
		not fx_sh.is_empty() and float(fx_sh.get("shards", -1.0)) == meter(st, "shard_hits"),
		"신호 %s · 실제 %.0f" % [str(fx_sh.get("shards", "없음")), meter(st, "shard_hits")])
	ok("자격표: 얼음 파편은 감전 후속·까마귀 표적·분신 모방을 부르지 못한다(재귀 경로 명시)",
		not PSupport.eligible("shock_bonus", "frost_shard") and not PSupport.eligible("crow_mark", "frost_shard")
		and not PSupport.eligible("echo_copy", "frost_shard"))
	ok("자격표: 파편이 낸 처치도 독 전염은 정상 발동한다(처치는 무엇으로 죽였든 전염된다)",
		PSupport.eligible("plague_spread", "frost_shard"))

	# ---------- 9. 파쇄·빙결 종료 뒤 중첩 0 + 재빙결 제한 ----------
	st = lab([["frost", 1, []]])
	var r1 := mob(st, "wolf", 260.0, 0.0)
	freeze_by_hits(st, r1)
	hit_as(st, r1, main_direct(), 1.0)
	ok("파쇄 뒤 중첩 0 · 재빙결 제한이 걸린다",
		int(r1.chill_n) == 0 and float(r1.refreeze_t) > 0.0,
		"중첩 %d · 제한 %.2f초" % [int(r1.chill_n), float(r1.refreeze_t)])
	ok("재빙결 제한 중에는 중첩이 가득 차도 곧바로 다시 얼지 않는다",
		not freeze_by_hits(st, r1), "freeze %.2f" % float(r1.freeze))
	play(st, float(F.get("refreezeSec", 3.0)) + 0.1)
	ok("재빙결 제한이 풀린 뒤 새 냉기 적중으로 다시 얼 수 있다", freeze_by_hits(st, r1))
	# 파쇄 없이 시간이 다 되어 풀린 경우도 같다
	st = lab([["frost", 1, []]])
	var r2 := mob(st, "wolf", 260.0, 0.0)
	freeze_by_hits(st, r2)
	play(st, float(F.get("freezeSec", {}).get("normal", 1.0)) + 0.1)
	ok("빙결이 시간으로 끝나도 중첩 0 · 재빙결 제한이 걸린다",
		not st.is_frozen(r2) and int(r2.chill_n) == 0 and float(r2.refreeze_t) > 0.0,
		"중첩 %d · 제한 %.2f초" % [int(r2.chill_n), float(r2.refreeze_t)])

	# ---------- 10. 예고와 실제 공격 판정이 어긋나지 않는다 ----------
	st = lab([["frost", 1, []]])
	var ar := mob(st, "archer", 280.0, 0.0, 1.0e6)
	var got_lock := false
	for i in int(round(4.0 / STEP)):
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		if String(ar.state) == "lock":
			got_lock = true
			break
	ok("궁수가 조준을 확정(lock)하는 상태까지 갔다(예고 시험 준비)", got_lock, String(ar.state))
	var lock_dir: float = float(ar.dir)
	var lock_t: float = float(ar.state_t)
	var arrows_before := enemy_arrows(st)
	freeze_by_hits(st, ar)
	play(st, 0.5)
	ok("빙결 중에는 예고가 진행되지 않는다(상태·상태 시간·확정 방향 모두 그대로)",
		String(ar.state) == "lock" and is_equal_approx(float(ar.state_t), lock_t) and is_equal_approx(float(ar.dir), lock_dir),
		"lock(%.3f, %.4f) → %s(%.3f, %.4f)" % [lock_t, lock_dir, String(ar.state), float(ar.state_t), float(ar.dir)])
	ok("빙결 중에는 예고된 공격이 나가지 않는다", enemy_arrows(st) == arrows_before,
		"%d → %d" % [arrows_before, enemy_arrows(st)])
	# 해제 뒤에 예고한 그 방향으로 실제 화살이 나간다
	var fired := {}
	for i in int(round(2.0 / STEP)):
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		for pr in st.projectiles:
			if String(pr.get("owner", "")) == "enemy" and String(pr.get("kind", "")) == "arrow" and fired.is_empty():
				fired = pr
		if not fired.is_empty():
			break
	ok("빙결이 풀리면 **예고한 그 방향**으로 실제 판정이 난다(예고와 판정이 어긋나지 않는다)",
		not fired.is_empty() and absf(PGeom.ang_diff(float(fired.angle), lock_dir)) < 1e-6,
		"예고 %.4f · 실제 %s" % [lock_dir, ("없음" if fired.is_empty() else "%.4f" % float(fired.angle))])

	# ---------- 11. 서리 개조 3종이 각각 다른 지표를 움직인다 ----------
	var base_wide := wide_case([])
	var fan_wide := wide_case(["fan"])
	var ground_wide := wide_case(["ground"])
	ok("넓은 빙결(fan): 냉기 중첩을 받은 **서로 다른 적의 수**가 늘어난다",
		fan_wide > base_wide and fan_wide >= 3.0, "기본 %.0f마리 → 넓은 빙결 %.0f마리" % [base_wide, fan_wide])
	ok("넓은 빙결이 아닌 개조는 적의 수를 늘리지 않는다",
		ground_wide <= base_wide, "빠른 빙결 %.0f마리 vs 기본 %.0f마리" % [ground_wide, base_wide])
	var base_fast := fast_case([])
	var ground_fast := fast_case(["ground"])
	var fan_fast := fast_case(["fan"])
	ok("빠른 빙결(ground): 같은 대상이 **더 빨리** 언다",
		ground_fast > 0.0 and ground_fast < base_fast,
		"기본 %.2f초 → 빠른 빙결 %.2f초" % [base_fast, ground_fast])
	ok("빠른 빙결이 아닌 개조는 같은 대상의 빙결 속도를 바꾸지 않는다",
		is_equal_approx(fan_fast, base_fast), "넓은 빙결 %.2f초 vs 기본 %.2f초" % [fan_fast, base_fast])
	var base_sh := shatter_case_metrics([])
	var boost_sh := shatter_case_metrics(["shatter"])
	ok("파쇄 강화(shatter): 파편 수와 주변 피해가 늘어난다",
		boost_sh[0] > base_sh[0] and boost_sh[1] > base_sh[1],
		"기본 파편 %.0f개·%.1f 피해 → 강화 %.0f개·%.1f 피해" % [base_sh[0], base_sh[1], boost_sh[0], boost_sh[1]])
	ok("파쇄 강화는 단일 대상 추가 피해를 바꾸지 않는다(역할이 '파편과 주변 피해'다)",
		is_equal_approx(base_sh[2], boost_sh[2]), "기본 %.1f vs 강화 %.1f" % [base_sh[2], boost_sh[2]])

	# ---------- 12. 개조 없이도 빙결·파쇄가 일어난다 ----------
	st = lab([["frost", 1, []]])
	ok("서리 수정에 개조가 하나도 없다(기본 상태 확인)", (st.build.weapons[0].mods as Array).is_empty())
	var z1 := mob(st, "wolf", 260.0, 0.0)
	var froze := freeze_by_hits(st, z1)
	hit_as(st, z1, main_direct(), 1.0)
	ok("개조를 하나도 고르지 않아도 빙결과 파쇄가 일어난다(기본 기능이 개조 전용으로 빠지지 않았다)",
		froze and meter(st, "shatters") == 1.0 and meter(st, "shard_hits") >= 0.0,
		"빙결 %s · 파쇄 %.0f회" % [str(froze), meter(st, "shatters")])
	# 서리 수정을 들지 않고 공용 증강 '얼음 파편'만 있어도 언다(냉기 공급원이 하나면 충분하다)
	var st_c := lab([["sword", 1, []]], 1, { "frost": 1 })
	var c1 := mob(st_c, "wolf", 260.0, 0.0)
	for i in int(st_c.frost_cfg().get("stackMax", 5)):
		st_c.damage_enemy(c1, 0.0, main_direct())
	ok("공용 증강 '얼음 파편'만 있어도(보조 없이) 냉기가 쌓여 언다", st_c.is_frozen(c1),
		"중첩 %d · freeze %.2f" % [int(c1.chill_n), float(c1.freeze)])

	# ---------- 13. 옛 저장 호환: 개조 id를 지우지도 다시 뽑지도 않는다 ----------
	var M := PCatalog.mods_of("frost")
	ok("서리 개조 id 3개가 그대로다(fan·shatter·ground) — 옛 저장이 가리키는 id가 사라지지 않았다",
		M.has("fan") and M.has("shatter") and M.has("ground") and M.size() == 3, str(M.keys()))
	ok("역할에 맞게 이름이 바뀌었다(넓은 빙결·파쇄 강화·빠른 빙결)",
		String(M.fan.name) == "넓은 빙결" and String(M.shatter.name) == "파쇄 강화" and String(M.ground.name) == "빠른 빙결",
		"%s / %s / %s" % [String(M.fan.name), String(M.shatter.name), String(M.ground.name)])
	ok("옛 이름을 기록으로 남겨 두었다(서리 부채·깨지는 수정·차가운 바닥)",
		String(M.fan.get("was", "")) == "서리 부채" and String(M.shatter.get("was", "")) == "깨지는 수정"
		and String(M.ground.get("was", "")) == "차가운 바닥")
	ok("세 개조 모두 구현 표시가 있다(그림·설명만 있는 상태로 지급되지 않는다)",
		bool(M.fan.impl) and bool(M.shatter.impl) and bool(M.ground.impl))
	var old_run := PRun.new_run(11, "sword")
	(old_run.growth as Dictionary).weapons = [
		{ "id": "sword", "level": 3, "mods": ["cross"] },
		{ "id": "frost", "level": 2, "mods": ["fan"] }]
	var back: Dictionary = JSON.parse_string(JSON.stringify(old_run))
	var kept := []
	for w in (back.growth as Dictionary).weapons:
		if String(w.id) == "frost":
			kept = (w.mods as Array).duplicate()
	ok("옛 저장을 읽어도 서리 개조 id가 그대로 남는다(조용히 삭제되지 않는다)", kept == ["fan"], str(kept))
	var db: Dictionary = PBuild.derive(back)
	var derived := []
	for w in (db.weapons as Array):
		if String(w.id) == "frost":
			derived = (w.mods as Array).duplicate()
	ok("파생 수치에도 그 개조가 그대로 실린다", derived == ["fan"], str(derived))
	var again := false
	for c in PGrowth.candidates(back, { "pool": "level" }):
		if String(c.kind) == "weapon_mod" and String(c.id) == "frost" and String(c.get("mod", "")) == "fan":
			again = true
	ok("이미 가진 개조를 다시 추첨 후보로 내놓지 않는다", not again)

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 시험 상황 ----------
## 보스 시험실(가시갈기). 등장 연출이 끝난 뒤부터 본다
func boss_lab() -> CombatState:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = [{ "id": "sword", "level": 1, "mods": [] }, { "id": "frost", "level": 1, "mods": [] }]
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 5, "arena": "clearing", "boss": true, "boss_id": "boss",
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1.0e6 })
	st.boss.beh_off = true
	st.player.attack_timer = 1.0e9
	return st

func st_frozen_soft(st: CombatState, e: Dictionary) -> bool:
	return st.is_frozen(e) and String(e.freeze_kind) == "soft"

## 이 경로로 때리면 파쇄가 나는가. 빙결시켜 두고 한 번 때린다
func shatter_case(o: Dictionary) -> bool:
	var st := lab([["frost", 1, []]])
	var e := mob(st, "wolf", 260.0, 0.0)
	if not freeze_by_hits(st, e):
		return false
	hit_as(st, e, o, 1.0)
	return meter(st, "shatters") >= 1.0

## 개조별 파쇄 결과 [파편 수, 파편 피해, 단일 대상 추가 피해]
func shatter_case_metrics(mods: Array) -> Array:
	var st := lab([["frost", 2, mods]])
	var e := mob(st, "wolf", 240.0, 0.0)
	# 파편 반경 안에 넉넉히 세워 둔다(강화 전 3개 · 강화 후 6개를 모두 채울 수 있게)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		mob(st, "wolf", 240.0 + cos(a) * 44.0, sin(a) * 44.0)
	freeze_by_hits(st, e)
	var hp0: float = float(e.hp)
	hit_as(st, e, main_direct(), 1.0)
	var self_extra: float = hp0 - float(e.hp) - 1.0 # 때린 피해 1을 뺀 나머지가 파쇄 추가 피해다
	return [meter(st, "shard_hits"), meter(st, "shard_dmg"), self_extra]

## 넓이 지표: 8초 동안 냉기 중첩을 받은 **서로 다른 적의 수**.
## 부채꼴 세 방향(-0.44 / 0 / +0.44 라디안)에 한 마리씩 세워 두고 자동 발사를 그대로 굴린다.
## 가운데를 조금 더 가깝게(190 vs 200) 둔다 — 세 마리가 정확히 같은 거리면 부동소수 오차로
## 조준 대상이 바뀌어 시험이 흔들린다(실제로 그렇게 흔들렸다)
func wide_case(mods: Array) -> float:
	var st := lab([["frost", 1, mods]], 7, {}, true)
	var pin := [mob(st, "wolf", 190.0, 0.0)]
	for a in [-0.44, 0.44]:
		pin.append(mob(st, "wolf", cos(a) * 200.0, sin(a) * 200.0))
	play_static(st, pin, 8.0)
	return meter(st, "chill_targets")

## 속도 지표: 대상 한 마리를 **처음 얼리기까지** 걸린 시간(초). 못 얼리면 -1
func fast_case(mods: Array) -> float:
	var st := lab([["frost", 1, mods]], 7, {}, true)
	var e := mob(st, "wolf", 200.0, 0.0)
	var home := [float(e.x), float(e.y)]
	for i in int(round(12.0 / STEP)):
		e.x = home[0]
		e.y = home[1]
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		if st.is_frozen(e):
			return st.t
	return -1.0

func enemy_arrows(st: CombatState) -> int:
	var n := 0
	for pr in st.projectiles:
		if String(pr.get("owner", "")) == "enemy" and String(pr.get("kind", "")) == "arrow":
			n += 1
	return n
