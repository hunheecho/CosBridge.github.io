extends SceneTree
## '연계 완성' 경직 검사(화면 없음).
## 실행: python tools/run_suites.py --suites stagger_tests
##      (직접: godot --headless --path prophecy_godot -s tests/stagger_tests.gd)
##
## 무엇을 못박는가(사용자 지시 2026-09-09 · docs/STAGGER.md)
##  1. 신규 경직을 일으키는 것은 **네 순간뿐**이다: 빙결 파쇄 · 불꽃 파열의 처치 폭발 ·
##     감전 누적 방전 · 까마귀 표식 폭발. 목록은 data/supports.json stagger.sources가 정본이다.
##  2. 일반 공격·장판 지속 피해·평소 감전 후속(shock_bonus)·파쇄 파편에는 경직이 **없다**.
##     룬 지뢰 연계는 사용자 지시로 **보류**라 목록에 없다.
##  3. 파쇄의 경직과 남은 빙결은 **동시에 흐르고 시간을 합산하지 않는다.**
##     빙결이 끝난 뒤로 미루거나 예약하지도 않는다.
##  4. 감전 방전·표식 폭발은 **최대 중첩에 닿은 그 타격에서 정확히 한 번** 터지고 중첩을 0으로 되돌린다.
##  5. 폭발이 낸 후속 피해가 **자기 중첩·자기 폭발을 다시 만들지 않는다**(자격표가 정본).
##  6. 네 연계가 적마다 **재경직 제한 하나를 함께 쓴다.** 번갈아 무한 경직시킬 수 없다.
##  7. 경직이 막혀도 **피해·중첩 소비·폭발은 그대로 처리된다.**
##  8. 보스는 피해를 받되 이번 신규 경직으로 **행동이 멈추지 않는다.**
##  9. 저프레임·큰 dt에서 중첩·폭발·경직이 복제되지 않는다.
## 10. 신규 경직은 적 상태 기계의 상태 이름 "stagger"(빈틈)와 **다른 것**이며 치명타 창을 열지 않는다.
## 11. 기존 전투망치 경직은 그대로 남아 있다(제거하지 않았다).
## 12. 이미 실행 중인 돌진·도약은 끊지 않는다. 예고는 끊지 않고 **멈췄다가 이어 간다**.
##
## 수치는 전부 **시험값**이다(data/supports.json stagger · tuning.orb · weapons.crow.base).
## 사람이 승인한 밸런스가 아니다.

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
		st.player.attack_timer = 1.0e9
	return st

## 보스 시험실(가시갈기). 등장 연출이 끝난 뒤부터 본다
func boss_lab(ids: Array = [["sword", 1, []], ["frost", 1, []]]) -> CombatState:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = []
	for r in ids:
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 5, "arena": "clearing", "boss": true, "boss_id": "boss",
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1.0e6 })
	st.boss.beh_off = true
	st.player.attack_timer = 1.0e9
	return st

func mob(st: CombatState, type: String, dx: float, dy: float, hp: float = 1.0e6) -> Dictionary:
	var e: Dictionary = st.spawn_enemy(type, st.player.x + dx, st.player.y + dy)
	e.hp = hp
	e.hp_max = hp
	return e

func play(st: CombatState, seconds: float, step: float = STEP) -> void:
	for i in int(round(seconds / step)):
		st.step({}, step)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

# ---------- 경로별 적중 흉내 ----------
func main_direct() -> Dictionary:
	return { "src": { "weapon_id": "sword", "direct": true } }

func cold_hit(st: CombatState, e: Dictionary) -> void:
	st.damage_enemy(e, 0.0, { "chill": 2.0, "src": { "weapon_id": "frost", "direct": true } })

## 중첩이 가득 차 얼 때까지 냉기 적중을 반복한다. 실제로 얼었으면 true
func freeze_by_hits(st: CombatState, e: Dictionary) -> bool:
	for i in int(st.frost_cfg().get("stackMax", 5)):
		cold_hit(st, e)
	return st.is_frozen(e)

# ---------- 계측 읽기 ----------
func tries(st: CombatState, src: String) -> int:
	return int((st.stagger_stats.tries as Dictionary).get(src, 0))

func applied(st: CombatState, src: String) -> int:
	return int((st.stagger_stats.applied as Dictionary).get(src, 0))

func blocked(st: CombatState, why: String) -> int:
	return int((st.stagger_stats.blocked as Dictionary).get(why, 0))

func bursts(st: CombatState, src: String) -> int:
	return int((st.stagger_stats.bursts as Dictionary).get(src, 0))

func fx_count(st: CombatState, kind: String) -> int:
	var n := 0
	for f in st.effects:
		if String(f.get("kind", "")) == kind:
			n += 1
	return n

func _init() -> void:
	sec0_contract()
	sec1_shatter()
	sec2_flare()
	sec3_discharge()
	sec4_crow()
	sec5_shared_cooldown()
	sec6_boss()
	sec7_no_stagger()
	sec8_frames()
	sec9_hammer_and_crit()
	sec11_wind_slam()
	sec12_plague_host()
	sec13_overlap()
	sec10_measure()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 0. 자료 계약 ----------
func sec0_contract() -> void:
	var S := PCatalog.link_stagger()
	ok("경직 시험값이 자료에 있다(코드에 숫자를 두지 않는다)",
		not S.is_empty() and S.has("sources") and S.has("sec") and S.has("cooldownSec"), str(S.keys()))
	ok("모든 시험값에 근거가 적혀 있다", String(S.get("why", "")) != "")
	var srcs: Array = S.get("sources", [])
	ok("경직을 일으킬 수 있는 것은 여섯 이름뿐이다(파쇄·불꽃 파열·감전 방전·표식 폭발·돌풍 충돌·숙주 파열)",
		srcs.size() == 6 and srcs.has("frost_shatter") and srcs.has("flare_burst")
		and srcs.has("shock_discharge") and srcs.has("crow_burst")
		and srcs.has("wind_slam") and srcs.has("plague_burst"), str(srcs))
	ok("일반 공격·장판 틱·평소 감전 후속·파쇄 파편은 목록에 없다",
		not srcs.has("main_direct") and not srcs.has("zone_tick")
		and not srcs.has("shock_bonus") and not srcs.has("frost_shard"))
	var scope: Dictionary = S.get("targetScope", {})
	ok("여섯 출처 모두 경직 대상 범위가 표에 적혀 있다",
		scope.size() == srcs.size() and scope.has("wind_slam") and scope.has("plague_burst"), str(scope.keys()))
	ok("룬 지뢰 연계는 보류라 목록에 없다", not srcs.has("mine_blast"))
	var sec: Dictionary = S.get("sec", {})
	ok("일반 몬스터 경직이 사용자가 준 창(0.10~0.15초) 안이다",
		float(sec.get("normal", 0.0)) >= 0.10 and float(sec.get("normal", 0.0)) <= 0.15,
		"%.3f초" % float(sec.get("normal", 0.0)))
	ok("정예·특수정예 경직이 사용자가 준 창(0.05~0.08초) 안이다",
		float(sec.get("elite", 0.0)) >= 0.05 and float(sec.get("elite", 0.0)) <= 0.08,
		"%.3f초" % float(sec.get("elite", 0.0)))
	ok("보스는 0초다(행동 정지 없음)", is_zero_approx(float(sec.get("boss", 1.0))))
	ok("재경직 제한이 약 0.8초다", is_equal_approx(float(S.get("cooldownSec", 0.0)), 0.8),
		"%.2f초" % float(S.get("cooldownSec", 0.0)))
	# 자격표에 새 경로 어휘가 등록되어 있는가(모르는 이름은 eligible이 조용히 통과시킨다)
	for c in ["flare_burst", "shock_discharge", "crow_burst", "wind_slam", "plague_burst"]:
		ok("자격표 어휘에 %s가 등록되어 있다" % c, PSupport.known_cause(c))
	# ⑤⑥의 재귀 차단은 **기존 자격표**만 쓴다(새 장치를 만들지 않았다)
	var EF: Dictionary = PCatalog.eligibility().get("effects", {})
	ok("자격표에 돌풍 충돌·숙주 파열 항목이 있다",
		EF.has("wind_slam") and EF.has("plague_host_burst"), str(EF.keys()))
	ok("돌풍 충돌은 돌풍의 직접 타격에서만 열리고 자기 자신을 막는다",
		PSupport.eligible("wind_slam", "support_direct")
		and not PSupport.eligible("wind_slam", "wind_slam")
		and not PSupport.eligible("wind_slam", "zone_tick")
		and not PSupport.eligible("wind_slam", "dot"))
	ok("숙주 파열은 주무기 처치에서만 열리고 독 틱·자기 자신을 막는다",
		PSupport.eligible("plague_host_burst", "main_direct")
		and PSupport.eligible("plague_host_burst", "main_extra")
		and not PSupport.eligible("plague_host_burst", "dot")
		and not PSupport.eligible("plague_host_burst", "plague_burst")
		and not PSupport.eligible("plague_host_burst", "support_direct")
		and not PSupport.eligible("plague_host_burst", "zone_tick"))
	ok("독 전염은 예전처럼 죽음의 경로를 가리지 않는다(기존 규칙을 좁히지 않았다)",
		PSupport.eligible("plague_spread", "dot") and PSupport.eligible("plague_spread", "support_direct")
		and PSupport.eligible("plague_spread", "plague_burst"))
	# 목록 밖 이름으로는 아무 일도 일어나지 않는다
	var st := lab([["sword", 1, []]])
	var e := mob(st, "wolf", 200.0, 0.0)
	ok("목록 밖 출처로 부르면 경직이 걸리지 않는다(시도로도 세지 않는다)",
		not st.apply_stagger(e, "main_direct") and tries(st, "main_direct") == 0
		and is_zero_approx(float(e.stagger_t)) and blocked(st, "source") == 1)

# ---------- 1. ① 빙결 파쇄 ----------
func sec1_shatter() -> void:
	var st := lab([["frost", 1, []]])
	var e := mob(st, "wolf", 260.0, 0.0)
	ok("전제: 냉기 적중으로 얼렸다", freeze_by_hits(st, e))
	var fr_left: float = float(e.freeze)
	st.damage_enemy(e, 1.0, main_direct()) # 주무기 타격 → 파쇄
	ok("승인된 주무기 타격이 파쇄를 실제로 발동시켰다",
		bursts(st, "frost_shatter") == 1 and PSupport.metered(st, "frost", "shatters") == 1.0)
	ok("파쇄가 발동한 그 순간 본체에 경직이 걸린다",
		applied(st, "frost_shatter") == 1 and float(e.stagger_t) > 0.0,
		"경직 %.3f초" % float(e.stagger_t))
	var dur := float(e.stagger_t)
	ok("경직 길이가 자료의 일반 몬스터 값과 같다(코드가 따로 정하지 않는다)",
		is_equal_approx(dur, float(PCatalog.link_stagger().sec.normal)), "%.3f초" % dur)
	# 파쇄는 빙결을 해제한다. 남은 빙결과 합산되지 않았음을 길이로 확인한다
	ok("남은 빙결 시간이 경직에 더해지지 않았다(합산 금지)",
		dur < fr_left and is_equal_approx(dur, float(PCatalog.link_stagger().sec.normal)),
		"남은 빙결 %.2f초 · 경직 %.3f초" % [fr_left, dur])
	ok("파쇄가 빙결을 끝냈다(경직 시간을 빙결 뒤로 미루지 않는다)", not st.is_frozen(e))
	ok("경직이 실제로 걸린 순간에만 화면 신호를 낸다", fx_count(st, "stagger_hit") == 1)
	# 경직 중에는 행동이 멈추고, 끝나면 하던 자리에서 이어 간다
	var s0 := String(e.state)
	var t0: float = float(e.state_t)
	var x0: float = float(e.x)
	play(st, dur * 0.5)
	ok("경직 중에는 상태·상태 시간이 멈춘다(공격 준비가 취소·재시작되지 않는다)",
		String(e.state) == s0 and is_equal_approx(float(e.state_t), t0),
		"%s(%.3f) → %s(%.3f)" % [s0, t0, String(e.state), float(e.state_t)])
	ok("경직 중에는 스스로 움직이지 않는다", is_equal_approx(float(e.x), x0))
	play(st, dur)
	# 늑대의 접근 상태는 state_t를 쌓지 않으므로(0.3.1 규칙) '다시 움직이는가'로 본다.
	# 예고가 취소·재시작되지 않는다는 것은 위의 '상태·상태 시간이 멈춘다'와 아래 궁수 시험이 함께 못박는다
	ok("경직이 끝나면 다시 움직인다(취소·초기화가 아니라 이어 감)",
		is_zero_approx(float(e.stagger_t)) and absf(float(e.x) - x0) > 0.5,
		"%s · 이동 %.2f" % [String(e.state), absf(float(e.x) - x0)])
	# 예고가 어긋나지 않는다: 조준을 확정한 궁수를 경직시켜도 상태·확정 각도가 그대로 이어진다
	var sa := lab([["sword", 1, []]])
	var ar := mob(sa, "archer", 200.0, 0.0)
	play(sa, 3.0)
	var a_state := String(ar.state)
	var a_t: float = float(ar.state_t)
	var a_dir: float = float(ar.dir)
	sa.apply_stagger(ar, "crow_burst")
	play(sa, float(PCatalog.link_stagger().sec.normal) * 0.5)
	ok("경직 중 궁수의 예고가 진행되지 않는다(상태·상태 시간·확정 방향 그대로)",
		String(ar.state) == a_state and is_equal_approx(float(ar.state_t), a_t) and is_equal_approx(float(ar.dir), a_dir),
		"%s(%.3f) → %s(%.3f)" % [a_state, a_t, String(ar.state), float(ar.state_t)])
	play(sa, 0.3)
	ok("경직이 풀리면 예고가 **멈춘 자리에서** 이어 간다(처음부터 다시가 아니다)",
		float(ar.state_t) > a_t or String(ar.state) != a_state,
		"%s(%.3f)" % [String(ar.state), float(ar.state_t)])
	ok("경직이 끝난 뒤에 재경직 제한이 시작된다",
		float(e.stagger_cd) > 0.0 and float(e.stagger_cd) <= float(PCatalog.link_stagger().cooldownSec),
		"제한 %.2f초" % float(e.stagger_cd))
	# 빙결과 경직은 동시에 흐른다: 얼어 있는 채로 경직을 걸어 두 시간이 함께 줄어드는지 본다
	var st2 := lab([["frost", 1, []]])
	var e2 := mob(st2, "wolf", 260.0, 0.0)
	freeze_by_hits(st2, e2)
	e2.stagger_t = 0.10
	var fz0: float = float(e2.freeze)
	play(st2, 0.05)
	ok("빙결 중에도 경직 시간이 함께 흐른다(빙결이 끝나기를 기다리지 않는다)",
		float(e2.stagger_t) < 0.10 and float(e2.freeze) < fz0,
		"빙결 %.3f → %.3f · 경직 %.3f" % [fz0, float(e2.freeze), float(e2.stagger_t)])
	# 파편은 주변 적에게 경직을 옮기지 않는다(이번 기본안: 본체만)
	var st3 := lab([["frost", 1, []]])
	var c0 := mob(st3, "wolf", 260.0, 0.0)
	var c1 := mob(st3, "wolf", 260.0, 40.0)
	freeze_by_hits(st3, c0)
	var hp1: float = float(c1.hp)
	st3.damage_enemy(c0, 1.0, main_direct())
	ok("파편은 주변 적을 실제로 때린다(대조군)", float(c1.hp) < hp1,
		"피해 %.1f" % (hp1 - float(c1.hp)))
	ok("파편을 맞은 주변 적에게는 경직이 옮지 않는다(본체만)",
		is_zero_approx(float(c1.stagger_t)) and applied(st3, "frost_shatter") == 1)
	# 한 번의 빙결에 파쇄는 한 번 → 경직도 한 번
	var before_ap := applied(st3, "frost_shatter")
	st3.damage_enemy(c0, 1.0, main_direct())
	ok("한 번의 빙결에서 파쇄가 두 번 나지 않으므로 경직도 두 번 나지 않는다",
		applied(st3, "frost_shatter") == before_ap and bursts(st3, "frost_shatter") == 1)

# ---------- 2. ② 불꽃 파열(처치 폭발) ----------
func sec2_flare() -> void:
	var st := lab([["ember", 1, []]], 1, { "ember": 1, "flare": 1 })
	var dying := mob(st, "wolf", 200.0, 0.0, 10.0)
	var near := mob(st, "wolf", 200.0, 40.0)
	var far := mob(st, "wolf", 200.0, 600.0)
	st.add_zone("fire", float(dying.x), float(dying.y), 60.0, 5.0, 0.0)
	var hp_near: float = float(near.hp)
	st.damage_enemy(dying, 9999.0, main_direct())
	ok("불길 위 처치로 불꽃 파열이 실제로 일어났다", bursts(st, "flare_burst") == 1)
	ok("폭발 피해를 실제로 받은 살아 있는 적에게 경직이 걸린다",
		float(near.hp) < hp_near and float(near.stagger_t) > 0.0 and applied(st, "flare_burst") == 1,
		"피해 %.1f · 경직 %.3f" % [hp_near - float(near.hp), float(near.stagger_t)])
	ok("폭발 범위 밖의 적은 피해도 경직도 받지 않는다",
		is_zero_approx(float(far.stagger_t)) and is_equal_approx(float(far.hp), float(far.hp_max)))
	# 불씨 장판의 일반 틱에는 경직이 없다
	var st2 := lab([["ember", 1, []]], 1, { "ember": 1, "flare": 1 })
	var z := mob(st2, "wolf", 200.0, 0.0)
	st2.add_zone("fire", float(z.x), float(z.y), 60.0, 3.0, 20.0)
	play(st2, 2.0)
	ok("불씨 장판의 설치·일반 틱에는 경직이 없다",
		is_zero_approx(float(z.stagger_t)) and applied(st2, "flare_burst") == 0 and float(z.hp) < float(z.hp_max),
		"장판 피해 %.1f" % (float(z.hp_max) - float(z.hp)))
	# 여러 폭발이 같은 적에게 이어져도 적별 재경직 제한을 함께 쓴다
	var st3 := lab([["ember", 1, []]], 1, { "ember": 1, "flare": 1 })
	var t3 := mob(st3, "wolf", 200.0, 0.0)
	for i in 2:
		var d3 := mob(st3, "wolf", 200.0, 20.0, 10.0)
		st3.add_zone("fire", float(d3.x), float(d3.y), 60.0, 5.0, 0.0)
		st3.damage_enemy(d3, 9999.0, main_direct())
	ok("연달아 터진 두 폭발이 같은 적을 두 번 경직시키지 않는다(재경직 제한 공유)",
		bursts(st3, "flare_burst") == 2 and applied(st3, "flare_burst") == 1
		and tries(st3, "flare_burst") == 2 and blocked(st3, "already") + blocked(st3, "cooldown") >= 1,
		"폭발 %d · 시도 %d · 발동 %d" % [bursts(st3, "flare_burst"), tries(st3, "flare_burst"), applied(st3, "flare_burst")])
	ok("경직이 막혀도 두 번째 폭발의 피해는 그대로 들어갔다(공격 효과를 취소하지 않는다)",
		float(t3.hp) < float(t3.hp_max), "받은 피해 %.1f" % (float(t3.hp_max) - float(t3.hp)))

# ---------- 3. ③ 감전 누적 방전 ----------
func sec3_discharge() -> void:
	var T := PCatalog.support_tuning("orb")
	var need := int(T.get("chargeNeed", 3))
	ok("감전 누적의 유지 시간이 자료에 있다(연타가 끊기면 사라진다)", T.has("chargeTtl"))
	ok("자격표: 감전 누적을 올리는 것은 감전 후속뿐이다",
		PSupport.eligible("shock_discharge", "shock_bonus")
		and not PSupport.eligible("shock_discharge", "zone_tick")
		and not PSupport.eligible("shock_discharge", "dot"))
	ok("자격표: 방전이 자기 자신을 다시 부르지 못한다(순환 금지)",
		not PSupport.eligible("shock_discharge", "shock_discharge")
		and not PSupport.eligible("shock_bonus", "shock_discharge"))
	var st := lab([["orb", 1, ["conduct"]], ["sword", 1, []]])
	var e := mob(st, "wolf", 60.0, 0.0)
	var other := mob(st, "wolf", 60.0, 40.0)
	var charges := []
	for i in need:
		e.conduct = float(T.get("shockDur", 2.0))
		st.damage_enemy(e, 1.0, main_direct())
		charges.append(int(st.support_charge))
	ok("감전 후속을 이을 때마다 누적이 한 칸씩 오른다(한 타격에 한 칸)",
		charges.slice(0, need - 1) == range(1, need), str(charges))
	ok("최대 중첩에 닿은 **그 타격에서** 방전이 정확히 한 번 터진다",
		bursts(st, "shock_discharge") == 1 and PSupport.metered(st, "orb", "discharges") == 1.0,
		"방전 %d회" % bursts(st, "shock_discharge"))
	ok("방전 뒤 누적이 0으로 초기화된다", int(st.support_charge) == 0 and is_zero_approx(st.support_charge_t))
	ok("방전에 맞은 살아 있는 적에게 경직이 걸린다",
		applied(st, "shock_discharge") >= 1 and (float(e.stagger_t) > 0.0 or float(other.stagger_t) > 0.0),
		"발동 %d회" % applied(st, "shock_discharge"))
	ok("방전이 감전을 다시 걸지 않는다(자기 호출 금지)", is_zero_approx(float(e.conduct)))
	ok("방전 자체가 누적을 다시 쌓지 않는다", int(st.support_charge) == 0)
	ok("방전이 터진 순간에만 화면 신호를 낸다", fx_count(st, "discharge") == 1)
	# 평소 감전 후속에는 경직이 없다
	var st2 := lab([["orb", 1, []], ["sword", 1, []]])
	var e2 := mob(st2, "wolf", 60.0, 0.0)
	for i in 6:
		e2.conduct = float(T.get("shockDur", 2.0))
		st2.damage_enemy(e2, 1.0, main_direct())
	ok("평소 감전 추가 피해(축전 없음)에는 경직이 없다",
		PSupport.metered(st2, "orb", "shock_procs") >= 3.0 and is_zero_approx(float(e2.stagger_t))
		and applied(st2, "shock_discharge") == 0 and bursts(st2, "shock_discharge") == 0,
		"감전 후속 %d회" % int(PSupport.metered(st2, "orb", "shock_procs")))
	# 유지 시간이 지나면 누적이 한 번에 0으로 떨어진다
	var st3 := lab([["orb", 1, ["conduct"]], ["sword", 1, []]])
	var e3 := mob(st3, "wolf", 60.0, 0.0)
	e3.conduct = float(T.get("shockDur", 2.0))
	st3.damage_enemy(e3, 1.0, main_direct())
	ok("전제: 누적이 하나 쌓였다", int(st3.support_charge) == 1)
	play(st3, float(T.get("chargeTtl", 3.0)) + 0.2)
	ok("연타가 끊기면 누적이 **한 번에** 0으로 떨어진다(1씩 줄지 않는다)",
		int(st3.support_charge) == 0 and bursts(st3, "shock_discharge") == 0)

# ---------- 4. ④ 까마귀 표식 폭발 ----------
func sec4_crow() -> void:
	ok("자격표: 표식을 쌓는 것은 까마귀의 쪼기뿐이다(주무기 타격은 표적만 지정한다)",
		PSupport.eligible("crow_burst", "support_direct")
		and not PSupport.eligible("crow_burst", "main_direct")
		and not PSupport.eligible("crow_burst", "crow_burst"))
	ok("자격표: 표식 폭발이 표적을 새로 지정하지 못한다(스스로 중첩을 리셋하지 않는다)",
		not PSupport.eligible("crow_mark", "crow_burst"))
	ok("자격표: 표식 폭발이 감전 후속·냉기 중첩·분신 모방을 부르지 못한다",
		not PSupport.eligible("shock_bonus", "crow_burst") and not PSupport.eligible("frost_stack", "crow_burst")
		and not PSupport.eligible("echo_copy", "crow_burst"))
	var st := lab([["sword", 1, []], ["crow", 1, []]])
	var cw := wep(st, "crow")
	var s: Dictionary = cw.stats
	var mx := int(s.get("markMax", 8))
	ok("표식 상한(markMax)이 피해 단계 상한(huntMax)보다 크다(개조의 +60%가 톱니로 잘리지 않는다)",
		mx > int(s.huntMax), "표식 %d · 단계 %d" % [mx, int(s.huntMax)])
	var e := mob(st, "wolf", 120.0, 0.0)
	var near := mob(st, "wolf", 120.0, 30.0)
	st.damage_enemy(e, 1.0, main_direct()) # 주무기 직접 타격이 표적을 지정한다
	PSupport.update(st, 1.0)               # 까마귀가 표적 위로 간다
	var S: Dictionary = (st.support as Dictionary).crow
	ok("전제: 주무기가 맞힌 적이 까마귀 표적이 되었다", S.target != null and int((S.target as Dictionary).id) == int(e.id))
	var marks := []
	var hp_near: float = float(near.hp)
	for i in mx:
		PWeapons.fire(st, cw, e, false)
		marks.append(int((S.birds[0] as Dictionary).mark))
	ok("쪼기 한 번에 표식이 정확히 한 칸 오른다", marks.slice(0, mx - 1) == range(1, mx), str(marks))
	ok("최대 표식에 닿은 **그 쪼기에서** 폭발이 정확히 한 번 난다",
		bursts(st, "crow_burst") == 1 and int(S.bursts) == 1, "폭발 %d회" % bursts(st, "crow_burst"))
	ok("폭발 뒤 표식이 0으로 초기화된다", int((S.birds[0] as Dictionary).mark) == 0)
	ok("표적 본체에 경직이 걸린다",
		applied(st, "crow_burst") == 1 and float(e.stagger_t) > 0.0, "경직 %.3f초" % float(e.stagger_t))
	ok("주변 적은 폭발 피해만 받고 경직은 받지 않는다(단일 대상 완성형)",
		float(near.hp) < hp_near and is_zero_approx(float(near.stagger_t)),
		"주변 피해 %.1f" % (hp_near - float(near.hp)))
	ok("폭발이 터진 순간에만 화면 신호를 낸다", fx_count(st, "crow_burst") == 1)
	ok("폭발이 표적을 갈아 치우지 않는다(자기 중첩을 다시 쌓지 않는다)",
		S.target != null and int((S.target as Dictionary).id) == int(e.id))
	# 폭발 뒤에도 계속 쌓여 다시 터진다(1부터 다시)
	for i in mx:
		PWeapons.fire(st, cw, e, false)
	ok("표적을 유지하면 표식이 1부터 다시 쌓여 두 번째 폭발이 난다", bursts(st, "crow_burst") == 2)
	# 표적이 바뀌면 표식이 초기화된다(기존 초기화 경로를 그대로 쓴다)
	var st2 := lab([["sword", 1, []], ["crow", 1, []]])
	var cw2 := wep(st2, "crow")
	var a2 := mob(st2, "wolf", 120.0, 0.0)
	var b2 := mob(st2, "wolf", -120.0, 0.0)
	st2.damage_enemy(a2, 1.0, main_direct())
	PSupport.update(st2, 1.0)
	var S2: Dictionary = (st2.support as Dictionary).crow
	for i in 3:
		PWeapons.fire(st2, cw2, a2, false)
	ok("전제: 표식이 3칸 쌓였다", int((S2.birds[0] as Dictionary).mark) == 3)
	PSupport.update(st2, float(cw2.stats.hold) + 0.2)
	st2.damage_enemy(b2, 1.0, main_direct())
	PSupport.update(st2, 0.1)
	ok("표적이 바뀌면 표식이 0으로 초기화된다(기존 규칙 그대로)",
		int((S2.birds[0] as Dictionary).mark) == 0 and int((S2.target as Dictionary).id) == int(b2.id))

# ---------- 5. 공통 재경직 제한 ----------
func sec5_shared_cooldown() -> void:
	var st := lab([["sword", 1, []]])
	var e := mob(st, "wolf", 200.0, 0.0)
	var S := PCatalog.link_stagger()
	ok("서로 다른 연계도 첫 경직만 걸린다(효과별로 따로 제한을 두지 않는다 · 여섯이 하나를 함께 쓴다)",
		st.apply_stagger(e, "frost_shatter") and not st.apply_stagger(e, "flare_burst")
		and not st.apply_stagger(e, "shock_discharge") and not st.apply_stagger(e, "crow_burst")
		and not st.apply_stagger(e, "wind_slam") and not st.apply_stagger(e, "plague_burst"))
	ok("막힌 다섯 번도 **시도**로는 세어 남는다(조건 충족과 실제 발동을 가른다)",
		tries(st, "flare_burst") == 1 and tries(st, "shock_discharge") == 1 and tries(st, "crow_burst") == 1
		and tries(st, "wind_slam") == 1 and tries(st, "plague_burst") == 1
		and applied(st, "flare_burst") == 0 and applied(st, "wind_slam") == 0
		and applied(st, "plague_burst") == 0)
	play(st, float(S.sec.normal) + 0.02)
	ok("경직이 끝나자마자 다른 연계가 곧바로 다시 걸지 못한다(재경직 제한)",
		not st.apply_stagger(e, "flare_burst") and blocked(st, "cooldown") >= 1,
		"제한 %.2f초 남음" % float(e.stagger_cd))
	play(st, float(S.cooldownSec) + 0.05)
	ok("제한이 풀리면 다시 걸린다", st.apply_stagger(e, "flare_burst") and applied(st, "flare_burst") == 1)
	# 시간이 누적·갱신되지 않는다
	var st2 := lab([["sword", 1, []]])
	var e2 := mob(st2, "wolf", 200.0, 0.0)
	st2.apply_stagger(e2, "frost_shatter")
	var d0: float = float(e2.stagger_t)
	st2.apply_stagger(e2, "crow_burst")
	ok("이미 경직 중이면 시간이 누적되거나 갱신되지 않는다",
		is_equal_approx(float(e2.stagger_t), d0) and blocked(st2, "already") >= 1, "%.3f초" % float(e2.stagger_t))
	# 총 경직 시간 계측
	var st3 := lab([["sword", 1, []]])
	var e3 := mob(st3, "wolf", 200.0, 0.0)
	st3.apply_stagger(e3, "frost_shatter")
	play(st3, 0.5)
	ok("총 경직 시간이 걸린 길이만큼만 쌓인다(계측)",
		absf(float(st3.stagger_stats.sec) - float(PCatalog.link_stagger().sec.normal)) < 0.02,
		"%.3f초" % float(st3.stagger_stats.sec))

# ---------- 6. 보스 ----------
func sec6_boss() -> void:
	var bo := boss_lab()
	var bz: Dictionary = bo.boss
	play(bo, 3.0)
	ok("전제: 보스가 등장 연출을 끝내고 움직인다", String(bz.state) != "" and not bool(bz.dead))
	var hp0: float = float(bz.hp)
	var s0 := String(bz.state)
	var t0: float = float(bz.state_t)
	var x0: float = float(bz.x)
	var y0: float = float(bz.y)
	freeze_by_hits(bo, bz)
	bo.damage_enemy(bz, 1.0, main_direct()) # 결빙 중인 보스를 주무기로 때린다 → 파쇄
	ok("보스도 파쇄의 정상 피해를 받는다", float(bz.hp) < hp0, "피해 %.1f" % (hp0 - float(bz.hp)))
	ok("보스에게는 신규 경직이 걸리지 않는다(시도는 남고 발동은 0)",
		tries(bo, "frost_shatter") >= 1 and applied(bo, "frost_shatter") == 0
		and is_zero_approx(float(bz.get("stagger_t", 0.0))) and blocked(bo, "boss") >= 1)
	play(bo, 0.4)
	ok("보스는 이번 신규 경직으로 행동이 멈추지 않는다(상태 진행·이동 계속)",
		float(bz.state_t) > t0 or String(bz.state) != s0
		or PGeom.dist(x0, y0, float(bz.x), float(bz.y)) > 0.5,
		"%s(%.3f) → %s(%.3f)" % [s0, t0, String(bz.state), float(bz.state_t)])
	ok("보스 경직 길이 계산은 0을 돌려준다(제압 저항표와 같은 뜻)",
		is_zero_approx(bo.stagger_dur_for(bz)) and PSupport.resist_mult("stagger", bz) <= 0.0)

# ---------- 7. 경직을 주지 않는 것들 ----------
func sec7_no_stagger() -> void:
	var st := lab([["sword", 1, []], ["frost", 1, []]])
	var e := mob(st, "wolf", 200.0, 0.0)
	for i in 12:
		st.damage_enemy(e, 5.0, main_direct())
	ok("일반 공격(주무기 직접 타격)에는 경직이 없다",
		is_zero_approx(float(e.stagger_t)) and (st.stagger_stats.applied as Dictionary).is_empty(),
		"발동 %s" % str(st.stagger_stats.applied))
	# 장판 지속 피해
	var st2 := lab([["ember", 1, []]], 1, { "ember": 1 })
	var e2 := mob(st2, "wolf", 200.0, 0.0)
	st2.add_zone("fire", float(e2.x), float(e2.y), 60.0, 3.0, 20.0)
	play(st2, 2.0)
	ok("장판 지속 피해에는 경직이 없다",
		is_zero_approx(float(e2.stagger_t)) and (st2.stagger_stats.applied as Dictionary).is_empty()
		and float(e2.hp) < float(e2.hp_max))
	# 화상·출혈 같은 지속 피해
	var st3 := lab([["sword", 1, []]])
	var e3 := mob(st3, "wolf", 200.0, 0.0)
	e3.burn = { "t": 2.0, "dps": 8.0, "tick": 0.0, "src": "common" }
	play(st3, 1.5)
	ok("지속 피해(화상)에는 경직이 없다",
		is_zero_approx(float(e3.stagger_t)) and (st3.stagger_stats.applied as Dictionary).is_empty())
	# 이미 실행 중인 돌진은 끊지 않는다
	var st4 := lab([["sword", 1, []]])
	var e4 := mob(st4, "wolf", 200.0, 0.0)
	e4.state = "dash"
	ok("이미 실행 중인 돌진은 경직으로 끊지 않는다(시도는 남는다)",
		st4.in_move_pattern(e4) and not st4.apply_stagger(e4, "frost_shatter")
		and tries(st4, "frost_shatter") == 1 and blocked(st4, "move") == 1)
	e4.state = "aim"
	ok("예고(aim)는 끊지 않는 상태가 아니다 — 멈췄다가 이어 가는 쪽이다",
		not st4.in_move_pattern(e4) and st4.apply_stagger(e4, "frost_shatter"))
	# 구조물·공중의 적
	var st5 := lab([["sword", 1, []]])
	var e5 := mob(st5, "wolf", 200.0, 0.0)
	e5.airborne = true
	ok("공중의 적에게는 걸리지 않는다", not st5.apply_stagger(e5, "flare_burst") and blocked(st5, "target") == 1)

# ---------- 8. 저프레임·큰 dt ----------
func sec8_frames() -> void:
	# 경직 중에 프레임만 굴려도 중첩·폭발이 생기지 않는다
	var st := lab([["frost", 1, []]])
	var e := mob(st, "wolf", 260.0, 0.0)
	freeze_by_hits(st, e)
	st.damage_enemy(e, 1.0, main_direct())
	var ap0 := applied(st, "frost_shatter")
	var bu0 := bursts(st, "frost_shatter")
	play(st, 3.0)
	ok("프레임만 굴려서는 경직·폭발이 늘어나지 않는다",
		applied(st, "frost_shatter") == ap0 and bursts(st, "frost_shatter") == bu0)
	# 큰 dt 한 번에 경직이 통째로 끝나고 제한이 정확히 한 번 걸린다
	var st2 := lab([["sword", 1, []]])
	var e2 := mob(st2, "wolf", 200.0, 0.0)
	st2.apply_stagger(e2, "frost_shatter")
	st2.step({}, 0.5) # 저프레임 한 걸음(경직 0.12초보다 훨씬 크다)
	ok("큰 dt 한 걸음에 경직이 끝나고 재경직 제한이 정확히 한 번 걸린다",
		is_zero_approx(float(e2.stagger_t)) and float(e2.stagger_cd) > 0.0
		and float(e2.stagger_cd) <= float(PCatalog.link_stagger().cooldownSec),
		"제한 %.3f초" % float(e2.stagger_cd))
	ok("총 경직 시간이 실제 길이를 넘지 않는다(큰 dt로 부풀지 않는다)",
		float(st2.stagger_stats.sec) <= float(PCatalog.link_stagger().sec.normal) + 0.001,
		"%.3f초" % float(st2.stagger_stats.sec))
	# 같은 프레임에 방전이 두 번 터지지 않는다
	var st3 := lab([["orb", 1, ["conduct"]], ["sword", 1, []]])
	var e3 := mob(st3, "wolf", 60.0, 0.0)
	var need := int(PCatalog.support_tuning("orb").get("chargeNeed", 3))
	for i in need * 2:
		e3.conduct = 2.0
		st3.damage_enemy(e3, 1.0, main_direct())
	ok("감전 후속 %d회 두 묶음에 방전이 정확히 두 번 난다(복제 없음)" % need,
		bursts(st3, "shock_discharge") == 2 and int(st3.support_charge) == 0,
		"방전 %d회 · 남은 누적 %d" % [bursts(st3, "shock_discharge"), int(st3.support_charge)])

# ---------- 9. 기존 망치 경직·치명타 창 ----------
func sec9_hammer_and_crit() -> void:
	var R := PCatalog.support_resist()
	ok("기존 제압 저항표의 경직 항목이 그대로 있다(전투망치 경직을 제거하지 않았다)",
		(R as Dictionary).has("stagger") and float((R.stagger as Dictionary).get("normal", 0.0)) > 0.0
		and is_zero_approx(float((R.stagger as Dictionary).get("boss", 1.0))))
	var st := lab([["hammer", 1, []]])
	var e := mob(st, "boar", 60.0, 0.0)
	var hs := wep(st, "hammer")
	PWeapons.heavy_control(st, e, hs.stats, float(e.x), float(e.y), 0.0)
	ok("전투망치가 여전히 적을 빈틈(recover) 상태로 만든다",
		String(e.state) == "recover" and float(e.recover_dur) > 0.0,
		"%s · %.2f초" % [String(e.state), float(e.recover_dur)])
	ok("전투망치 경직은 신규 경직 필드를 쓰지 않는다(서로 다른 것이다)",
		is_zero_approx(float(e.stagger_t)) and (st.stagger_stats.applied as Dictionary).is_empty())
	# 신규 경직은 치명타 창을 열지 않는다
	var st2 := lab([["sword", 1, []]])
	var a2 := mob(st2, "wolf", 200.0, 0.0)
	var b2 := mob(st2, "wolf", -200.0, 0.0)
	a2.state = "idle"
	b2.state = "idle"
	st2.apply_stagger(a2, "frost_shatter")
	var hp_a: float = float(a2.hp)
	var hp_b: float = float(b2.hp)
	st2.damage_enemy(a2, 20.0, main_direct())
	st2.damage_enemy(b2, 20.0, main_direct())
	ok("신규 경직은 치명타 창(빈틈 피해 배율)을 열지 않는다",
		is_equal_approx(hp_a - float(a2.hp), hp_b - float(b2.hp)),
		"경직 중 %.1f vs 평소 %.1f" % [hp_a - float(a2.hp), hp_b - float(b2.hp)])
	ok("신규 경직은 적 상태 기계의 상태 이름을 바꾸지 않는다(빈틈 'stagger'와 다른 것)",
		String(a2.state) == "idle" and float(a2.stagger_t) > 0.0)

# ---------- 11. ⑤ 돌풍 → 장애물 충돌 ----------
## 시험실: 플레이어(480,300) 오른쪽 640에 바위 하나. 늑대(반지름 14)를 540에 놓으면
## 압축 돌풍이 240px 밀려 하지만 바위 표면(586)에서 멈춘다 — 밀려간 46, 막힌 194.
func wind_lab(rock: bool = true) -> CombatState:
	var st := lab([["sword", 1, []], ["wind", 1, ["focused"]]])
	if rock:
		st.obstacles = [{ "id": "rock_t", "type": "rock", "x": 640.0, "y": 300.0, "r": 40.0 }]
	return st

func wind_state(st: CombatState) -> Dictionary:
	return (st.support as Dictionary).get("wind", {})

func sec11_wind_slam() -> void:
	# 11-1. 실제로 바위에 부딪히면 추가 피해 + 경직
	var st := wind_lab()
	var e := mob(st, "wolf", 60.0, 0.0, 400.0)
	var x0: float = float(e.x)
	var hp0: float = float(e.hp)
	PWeapons.fire(st, wep(st, "wind"), e, false)
	var S := wind_state(st)
	ok("돌풍이 밀어 바위에 부딪히면 충돌 피해가 들어간다",
		int(S.slams) == 1 and float(e.hp) < hp0 and float(e.x) > x0,
		"충돌 %d회 · %.1f → %.1f · x %.0f → %.0f" % [int(S.slams), hp0, float(e.hp), x0, float(e.x)])
	ok("충돌은 연계 폭발로 세어지고 경직이 실제로 걸린다",
		bursts(st, "wind_slam") == 1 and applied(st, "wind_slam") == 1 and float(e.stagger_t) > 0.0,
		"폭발 %d · 발동 %d · 남은 경직 %.3f초" % [bursts(st, "wind_slam"), applied(st, "wind_slam"), float(e.stagger_t)])
	# 11-2. 벽에 이미 붙은 적에게는 다음 돌풍이 충돌을 만들지 않는다
	var slam_dmg1: float = float(S.slam_dmg)
	var flush0: int = int(S.slam_flush)
	# 적을 걷게 두면 바위에서 떨어져 나가므로(그때의 두 번째 충돌은 정당하다) **자리를 그대로 두고**
	# 경직·재경직 제한만 손으로 풀어 다시 분다. 즉 "바위에 붙은 채로 또 맞는" 상황만 남긴다
	e["stagger_t"] = 0.0
	e["stagger_cd"] = 0.0
	PWeapons.fire(st, wep(st, "wind"), e, false)
	ok("이미 벽·바위에 붙은 적에게는 다음 돌풍이 충돌 피해를 만들지 않는다(평소 돌풍 피해는 그대로)",
		int(S.slams) == 1 and int(S.slam_flush) > flush0
		and is_equal_approx(float(S.slam_dmg), slam_dmg1) and applied(st, "wind_slam") == 1,
		"충돌 %d회(그대로) · 붙어서 거른 %d회 · 충돌 피해 합 %.1f" % [int(S.slams), int(S.slam_flush), float(S.slam_dmg)])
	# 11-3. 장애물이 없는 쪽으로 밀면 기존 밀어내기만 남는다
	var st2 := wind_lab(false)
	var e2 := mob(st2, "wolf", 60.0, 0.0, 400.0)
	var hp2: float = float(e2.hp)
	var x2: float = float(e2.x)
	PWeapons.fire(st2, wep(st2, "wind"), e2, false)
	var S2 := wind_state(st2)
	var pushed: float = float(e2.x) - x2
	ok("장애물이 없는 곳으로 밀었을 때는 기존 밀어내기만 적용한다",
		int(S2.slams) == 0 and int(S2.slam_open) == 1 and pushed > 100.0
		and bursts(st2, "wind_slam") == 0 and is_zero_approx(float(e2.stagger_t)),
		"밀어낸 거리 %.0f · 충돌 %d회" % [pushed, int(S2.slams)])
	ok("충돌 피해만 빠지고 돌풍의 평소 피해는 그대로 들어간다", float(e2.hp) < hp2,
		"%.1f → %.1f" % [hp2, float(e2.hp)])
	# 11-4. 세 관문과 '한 번의 밀어내기당 1회'를 직접 확인한다
	var st3 := wind_lab()
	var w3 := wep(st3, "wind")
	var s3: Dictionary = w3.stats
	var S3 := PSupportA._state(st3, "wind")
	S3.blasts = 7
	var g1 := mob(st3, "wolf", 60.0, 0.0, 400.0)
	PSupportA._wind_slam(st3, w3, S3, s3, g1, { "hit": "", "t": 1.0 }, 240.0, 240.0)
	ok("막히지 않은 이동은 충돌이 아니다", int(S3.slams) == 0 and int(S3.slam_open) == 1)
	var g2 := mob(st3, "wolf", 60.0, 40.0, 400.0)
	PSupportA._wind_slam(st3, w3, S3, s3, g2, { "hit": "rock_t", "t": 0.02 }, 240.0, 5.0)
	ok("밀려간 거리가 모자라면(이미 붙어 있으면) 충돌이 아니다",
		int(S3.slams) == 0 and int(S3.slam_flush) == 1)
	var g3 := mob(st3, "wolf", 60.0, 80.0, 400.0)
	PSupportA._wind_slam(st3, w3, S3, s3, g3, { "hit": "rock_t", "t": 0.98 }, 240.0, 235.0)
	ok("막힌 거리가 모자라면(스친 것) 충돌이 아니다",
		int(S3.slams) == 0 and int(S3.slam_graze) == 1)
	var g4 := mob(st3, "wolf", 60.0, 120.0, 400.0)
	var hp4: float = float(g4.hp)
	PSupportA._wind_slam(st3, w3, S3, s3, g4, { "hit": "rock_t", "t": 0.4 }, 240.0, 100.0)
	var after4: float = float(g4.hp)
	PSupportA._wind_slam(st3, w3, S3, s3, g4, { "hit": "rock_t", "t": 0.4 }, 240.0, 100.0)
	ok("한 번의 밀어내기가 같은 적에게 충돌 피해를 두 번 만들지 않는다",
		int(S3.slams) == 1 and after4 < hp4 and is_equal_approx(float(g4.hp), after4),
		"충돌 %d회 · %.1f → %.1f" % [int(S3.slams), hp4, float(g4.hp)])
	# 11-5. 밀치기 면역인 보스에게는 이동·충돌을 억지로 적용하지 않는다
	var st4 := wind_lab()
	var bz := mob(st4, "boss", 60.0, 0.0, 1.0e6)
	var bx: float = float(bz.x)
	var bhp: float = float(bz.hp)
	PWeapons.fire(st4, wep(st4, "wind"), bz, false)
	var S4 := wind_state(st4)
	ok("밀치기 면역인 보스에게는 이동·충돌 효과를 억지로 적용하지 않는다",
		is_equal_approx(float(bz.x), bx) and int(S4.slams) == 0 and int(S4.slam_checked) == 0
		and is_zero_approx(float(bz.get("stagger_t", 0.0))),
		"x %.1f → %.1f · 충돌 판정 %d회" % [bx, float(bz.x), int(S4.slam_checked)])
	ok("보스도 돌풍의 정상 피해는 그대로 받는다", float(bz.hp) < bhp, "피해 %.1f" % (bhp - float(bz.hp)))
	# 11-5b. 저프레임·큰 dt로 굴려도 충돌·경직이 복제되지 않는다(발사 자체를 막아 놓고 본다)
	var st6 := wind_lab()
	var e6 := mob(st6, "wolf", 60.0, 0.0, 400.0)
	PWeapons.fire(st6, wep(st6, "wind"), e6, false)
	var S6 := wind_state(st6)
	var slams6: int = int(S6.slams)
	var ap6: int = applied(st6, "wind_slam")
	wep(st6, "wind").timer = 1.0e9 # 다음 돌풍이 불지 않게 막고 프레임만 굴린다
	for i in 6:
		st6.step({}, 0.5)
	ok("큰 dt로 굴려도 충돌·경직이 복제되지 않는다(충돌은 밀어내기 이벤트 안에서만 난다)",
		int(S6.slams) == slams6 and applied(st6, "wind_slam") == ap6 and slams6 == 1,
		"충돌 %d회 · 발동 %d회" % [int(S6.slams), applied(st6, "wind_slam")])
	# 11-6. 개조를 고르지 않으면 충돌 자체가 없다
	var st5 := lab([["sword", 1, []], ["wind", 1, []]])
	st5.obstacles = [{ "id": "rock_t", "type": "rock", "x": 640.0, "y": 300.0, "r": 40.0 }]
	var e5 := mob(st5, "wolf", 60.0, 0.0, 400.0)
	PWeapons.fire(st5, wep(st5, "wind"), e5, false)
	var S5 := wind_state(st5)
	ok("압축 돌풍을 고르지 않으면 충돌 판정 자체가 없다",
		int(S5.get("slam_checked", 0)) == 0 and bursts(st5, "wind_slam") == 0
		and is_zero_approx(float(e5.stagger_t)))

# ---------- 12. ⑥ 역병 → 숙주 파열 ----------
## 적을 움직이지 않고 보조 규칙만 굴린다(기하가 그대로 유지된다 — support_b_tests와 같은 방식)
func quiet_tick(st: CombatState, sec: float) -> void:
	for i in int(round(sec / STEP)):
		var keep := []
		for d in st.delayed:
			d.t = float(d.t) - STEP
			if float(d.t) <= 0.0:
				(d.fn as Callable).call()
			else:
				keep.append(d)
		st.delayed = keep
		PSupport.update(st, STEP)

func plague_lab() -> CombatState:
	return lab([["sword", 1, []], ["plague", 1, ["burst"]]])

func infected(e: Dictionary) -> bool:
	return not (e.get("plague", {}) as Dictionary).is_empty()

func sec12_plague_host() -> void:
	# 12-1. 주무기 처치로 터진다 — 주변에 즉시 피해 + 경직
	var st := plague_lab()
	var host := mob(st, "wolf", 120.0, 0.0, 200.0)
	var near1 := mob(st, "wolf", 150.0, 30.0, 400.0)
	PSupport.fire(st, wep(st, "plague"), host, false)
	quiet_tick(st, 1.2)
	ok("전제: 숙주에게 독이 걸렸다", infected(host))
	var P: Dictionary = PSupportB.plague_stat(st)
	var hp_n: float = float(near1.hp)
	st.damage_enemy(host, 1.0e6, main_direct())
	ok("감염된 적을 주무기로 처치하면 숙주 파열이 터진다",
		int(P.bursts) == 1 and float(near1.hp) < hp_n and bursts(st, "plague_burst") == 1,
		"파열 %d회 · 이웃 %.1f → %.1f" % [int(P.bursts), hp_n, float(near1.hp)])
	ok("파열 피해를 받은 살아 있는 적이 짧게 경직된다",
		applied(st, "plague_burst") == 1 and float(near1.stagger_t) > 0.0,
		"발동 %d · 남은 경직 %.3f초" % [applied(st, "plague_burst"), float(near1.stagger_t)])
	# 12-2. 독 틱으로 죽으면 파열은 열리지 않지만 전염은 그대로 일어난다
	var st2 := plague_lab()
	var h2 := mob(st2, "wolf", 120.0, 0.0, 2.0)
	var n2 := mob(st2, "wolf", 150.0, 30.0, 400.0)
	PSupport.fire(st2, wep(st2, "plague"), h2, false)
	quiet_tick(st2, 4.0) # 독 틱만으로 죽을 때까지
	var P2: Dictionary = PSupportB.plague_stat(st2)
	ok("전제: 숙주가 독 틱으로 죽었다", bool(h2.dead))
	ok("독이 끝내 죽인 경우에는 숙주 파열이 열리지 않는다",
		int(P2.bursts) == 0 and int(P2.burst_blocked) >= 1 and bursts(st2, "plague_burst") == 0
		and is_zero_approx(float(n2.stagger_t)),
		"파열 %d회 · 막힘 %d회" % [int(P2.bursts), int(P2.burst_blocked)])
	ok("그때에도 독 전염은 예전처럼 일어난다(전염과 숙주 파열을 구분한다)",
		int(P2.spreads) >= 1 and infected(n2), "전염 %d회" % int(P2.spreads))
	# 12-3. 보조무기 처치에는 자격이 없다
	var st3 := plague_lab()
	var h3 := mob(st3, "wolf", 120.0, 0.0, 200.0)
	var n3 := mob(st3, "wolf", 150.0, 30.0, 400.0)
	PSupport.fire(st3, wep(st3, "plague"), h3, false)
	quiet_tick(st3, 1.2)
	var P3: Dictionary = PSupportB.plague_stat(st3)
	var hp3: float = float(n3.hp)
	st3.damage_enemy(h3, 1.0e6, { "cause": "support_direct", "src": { "weapon_id": "plague", "direct": true } })
	ok("보조무기가 마지막 일격이면 숙주 파열이 열리지 않는다",
		int(P3.bursts) == 0 and int(P3.burst_blocked) >= 1 and is_equal_approx(float(n3.hp), hp3))
	# 12-4. 파열 피해가 다시 파열을 부르지 않는다(재귀 차단)
	var st4 := plague_lab()
	var h4 := mob(st4, "wolf", 120.0, 0.0, 200.0)
	var n4 := mob(st4, "wolf", 150.0, 20.0, 4.0) # 파열 피해로 죽을 만큼 얇게
	PSupport.fire(st4, wep(st4, "plague"), h4, false)
	quiet_tick(st4, 1.2)
	PSupport.fire(st4, wep(st4, "plague"), n4, false)
	quiet_tick(st4, 1.2)
	ok("전제: 두 마리 모두 감염됐다", infected(h4) and infected(n4))
	var P4: Dictionary = PSupportB.plague_stat(st4)
	st4.damage_enemy(h4, 1.0e6, main_direct())
	ok("파열 피해로 죽은 감염된 적은 다시 파열하지 않는다(연쇄 금지)",
		bool(n4.dead) and int(P4.bursts) == 1 and int(P4.burst_blocked) >= 1,
		"파열 %d회 · 막힘 %d회" % [int(P4.bursts), int(P4.burst_blocked)])
	# 12-5. 남은 독 피해의 비율·상한이 실제로 적용된다
	var st5 := plague_lab()
	var h5 := mob(st5, "wolf", 120.0, 0.0, 200.0)
	var n5 := mob(st5, "wolf", 150.0, 20.0, 1.0e6)
	PSupport.fire(st5, wep(st5, "plague"), h5, false)
	quiet_tick(st5, 1.2)
	var pg5: Dictionary = h5.get("plague", {})
	var remain: float = maxf(0.0, float(pg5.t)) * float(pg5.dps)
	var want: float = minf(remain * float(pg5.burst_frac), float(pg5.get("burst_cap", 0.0)))
	var hp5: float = float(n5.hp)
	st5.damage_enemy(h5, 1.0e6, main_direct())
	var dealt: float = hp5 - float(n5.hp)
	ok("숙주 파열 피해 = 남은 독 피해 × 비율(상한 적용)",
		absf(dealt - want) < 0.6 and want > 0.0,
		"남은 독 %.1f × %.2f → 기대 %.1f · 실제 %.1f (상한 %.0f)" % [remain, float(pg5.burst_frac), want, dealt, float(pg5.get("burst_cap", 0.0))])
	ok("죽음이 독 칸을 지운 뒤에도 계산에 쓴 값은 보존된다(지역 변수 pg)",
		not infected(h5) and int(PSupportB.plague_stat(st5).bursts) == 1)

	# 12-6. 저프레임·큰 dt로 굴려도 파열·경직이 복제되지 않는다
	var P5b: Dictionary = PSupportB.plague_stat(st5)
	var ap5: int = applied(st5, "plague_burst")
	for i in 6:
		st5.step({}, 0.5)
	ok("큰 dt로 굴려도 숙주 파열·경직이 복제되지 않는다(파열은 죽음 이벤트 안에서만 난다)",
		int(P5b.bursts) == 1 and applied(st5, "plague_burst") == ap5,
		"파열 %d회 · 발동 %d회" % [int(P5b.bursts), applied(st5, "plague_burst")])

# ---------- 13. 겹침: **실제 행동 재개 시각**을 잰다 ----------
## 왜 재는가: "더해지지 않고 밀린다"는 말로는 아무것도 밝혀지지 않는다. **밀리면 실제 행동 불능 시간이 늘어난다.**
## 그래서 말이 아니라 시각을 잰다 — 망치 빈틈만 / 신규 경직만 / 둘 다 / 빙결까지.
##
## 왜 밀리는가(코드 구조):
##  · 망치 경직은 적 **상태 기계**를 쓴다(e.state="recover" + recover_dur). 남은 시간은 PEnemies.update 안에서만 준다.
##  · 신규 경직(e.stagger_t)은 **행동 갱신을 통째로 건너뛴다.** 그동안 recover의 시계가 아예 돌지 않는다.
##  · 빙결(hard)도 같은 이유로 recover의 시계를 멈춘다. 반대로 신규 경직은 빙결보다 **앞에서** 줄어들어 함께 흐른다.
## **여기서 고치지 않는다**(사용자 지시: 제시까지). 지금 값을 못박아 두어 나중에 달라지면 드러나게 한다.
const OVERLAP_LIMIT := 6.0

## 그 적이 **행동을 재개하는 시각**(초). 빙결·신규 경직·망치 빈틈이 모두 풀린 첫 순간.
## 재개하지 못하면 상한을 돌려준다
func resume_time(st: CombatState, e: Dictionary) -> float:
	var t := 0.0
	while t < OVERLAP_LIMIT:
		if not st.is_hard_frozen(e) and not st.is_staggered(e) and String(e.state) != "recover":
			return t
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		t += STEP
	return OVERLAP_LIMIT

## 멧돼지 하나만 있는 시험실(빈틈 값이 정의에 있는 적 · 늑대가 아니라 grace 경로를 타지 않는다).
## 주무기는 손으로만 쏘고, 적은 죽지 않을 만큼 두껍다
func overlap_lab() -> Array:
	var st := lab([["hammer", 1, []], ["frost", 1, []]])
	var e := mob(st, "boar", 220.0, 0.0, 1.0e7)
	return [st, e]

func hammer_hit(st: CombatState, e: Dictionary) -> void:
	PWeapons.heavy_control(st, e, (wep(st, "hammer").stats as Dictionary), float(e.x), float(e.y), 0.0)

func sec13_overlap() -> void:
	var S := PCatalog.link_stagger()
	var stag_sec := float((S.sec as Dictionary).normal)
	# ① 망치 빈틈만
	var l1 := overlap_lab()
	var st1: CombatState = l1[0]
	var e1: Dictionary = l1[1]
	hammer_hit(st1, e1)
	var hammer_dur: float = float(e1.recover_dur)
	var t_hammer := resume_time(st1, e1)
	# ② 신규 연계 경직만
	var l2 := overlap_lab()
	var st2: CombatState = l2[0]
	var e2: Dictionary = l2[1]
	st2.apply_stagger(e2, "frost_shatter")
	var t_link := resume_time(st2, e2)
	# ③ 둘 다 같은 순간에
	var l3 := overlap_lab()
	var st3: CombatState = l3[0]
	var e3: Dictionary = l3[1]
	hammer_hit(st3, e3)
	st3.apply_stagger(e3, "frost_shatter")
	var t_both := resume_time(st3, e3)
	# ④ 빙결까지 셋
	var l4 := overlap_lab()
	var st4: CombatState = l4[0]
	var e4: Dictionary = l4[1]
	var froze := freeze_by_hits(st4, e4)
	var freeze_dur: float = st4.freeze_dur_for(e4)
	hammer_hit(st4, e4)
	st4.apply_stagger(e4, "frost_shatter")
	var t_all := resume_time(st4, e4)
	print("STAGGER_OVERLAP 겹침 | 행동 재개(초) | 각 효과의 길이(초)")
	print("STAGGER_OVERLAP 망치 빈틈만 | %.3f | 망치 %.2f" % [t_hammer, hammer_dur])
	print("STAGGER_OVERLAP 신규 경직만 | %.3f | 경직 %.2f" % [t_link, stag_sec])
	print("STAGGER_OVERLAP 둘 다 | %.3f | 망치 %.2f + 경직 %.2f" % [t_both, hammer_dur, stag_sec])
	print("STAGGER_OVERLAP 빙결까지 | %.3f | 빙결 %.2f + 망치 %.2f + 경직 %.2f" % [t_all, freeze_dur, hammer_dur, stag_sec])
	ok("전제: 빙결까지 겹친 팔에서 실제로 얼었다", froze)
	ok("① 망치 빈틈만: 행동 재개가 망치 빈틈 길이와 같다", absf(t_hammer - hammer_dur) < 0.05,
		"%.3f초 (망치 %.2f)" % [t_hammer, hammer_dur])
	ok("② 신규 경직만: 행동 재개가 경직 길이와 같다", absf(t_link - stag_sec) < 0.05,
		"%.3f초 (경직 %.2f)" % [t_link, stag_sec])
	ok("③ 둘 다: **겹치지 않고 직렬로 이어진다** — 재개 시각이 두 길이의 합이다(의도치 않은 연장)",
		absf(t_both - (hammer_dur + stag_sec)) < 0.05 and t_both > t_hammer + 0.02,
		"%.3f초 (망치 %.2f + 경직 %.2f = %.2f · 겹쳤다면 %.2f)" % [t_both, hammer_dur, stag_sec, hammer_dur + stag_sec, maxf(hammer_dur, stag_sec)])
	ok("④ 빙결까지: 신규 경직만 빙결과 **함께 흐르고**, 망치 빈틈은 빙결 뒤로 밀린다",
		absf(t_all - (freeze_dur + hammer_dur)) < 0.06,
		"%.3f초 (빙결 %.2f + 망치 %.2f = %.2f · 셋을 다 더하면 %.2f)" %
			[t_all, freeze_dur, hammer_dur, freeze_dur + hammer_dur, freeze_dur + hammer_dur + stag_sec])
	ok("기존 망치 경직을 제거하지 않았다(빈틈 길이가 그대로 살아 있다)", hammer_dur > 0.0)

# ---------- 10. 실전 비교(기록). 합격 판정이 아니라 수치를 남긴다 ----------
## 같은 성장 예산·편성·시드·봇을 유지하고 **신규 경직만** 켜고 끈 두 팔을 돌린다.
## 끈 팔은 매 걸음 모든 적의 재경직 제한을 크게 세워 경직이 걸리지 못하게 한다 —
## 피해·중첩·폭발은 그대로 돌아가므로 "경직이 막혀도 공격 효과는 처리된다"가 실전에서도 지켜지는지 함께 본다.
## **이 수치는 승인된 밸런스가 아니고 재미의 검증도 아니다.**
const MEASURE_SEC := 60.0
## wave = 그 팔이 상대하는 편성. 두 팔(경직 켬/끔)이 **완전히 같은 것**을 쓴다.
## 파쇄·표식 폭발은 한 대상을 오래 붙잡아야 완성되므로 얇은 늑대 무리로는 한 번도 나지 않는다 —
## 그래서 그 팔에는 체력이 큰 편성(정예 늑대·방패병)을 준다. **3막 체력·H3 체력표는 건드리지 않았다.**
const MEASURE_ARMS := [
	{ "id": "hammer_frost_crow", "main": "hammer",
		"weapons": [["hammer", 4, ["shockwave"]], ["frost", 3, []], ["crow", 3, ["hunt"]]], "commons": {},
		"wave": [{ "type": "wolf_alpha", "n": 2 }, { "type": "shieldbearer", "n": 3 }, { "type": "wolf", "n": 3 }],
		"why": "파쇄 경직 + 표식 폭발 경직. 기존 전투망치 경직과 겹치는 유일한 편성이다" },
	{ "id": "sword_orb_ember", "main": "sword",
		"weapons": [["sword", 4, ["scar"]], ["orb", 3, ["conduct"]], ["ember", 3, []]],
		"commons": { "ember": 1, "flare": 1 },
		"wave": [{ "type": "wolf", "n": 4 }, { "type": "archer", "n": 2 }, { "type": "shieldbearer", "n": 1 }],
		"why": "감전 누적 방전 경직 + 불꽃 파열 경직" },
	{ "id": "sword_wind_plague", "main": "sword",
		"weapons": [["sword", 4, ["scar"]], ["wind", 3, ["focused"]], ["plague", 3, ["burst"]]], "commons": {},
		"wave": [{ "type": "wolf", "n": 4 }, { "type": "archer", "n": 2 }, { "type": "shieldbearer", "n": 1 }],
		"why": "⑤ 돌풍 충돌 경직 + ⑥ 숙주 파열 경직. 장애물은 전장이 만든 것을 그대로 쓴다(손으로 놓지 않았다)" },
	{ "id": "spear_wind_plague", "main": "spear",
		"weapons": [["spear", 4, []], ["wind", 3, ["focused"]], ["plague", 3, ["burst"]]], "commons": {},
		"wave": [{ "type": "wolf_alpha", "n": 2 }, { "type": "shieldbearer", "n": 3 }, { "type": "wolf", "n": 3 }],
		"why": "같은 둘을 **체력이 큰 편성**에서 본다 — 얇은 무리에서는 밀기 전에 죽어 충돌이 잘 나지 않는다" },
	{ "id": "boss_frost_crow", "main": "hammer",
		"weapons": [["hammer", 4, ["shockwave"]], ["frost", 3, []], ["crow", 3, ["hunt"]]], "commons": {},
		"wave": [], "boss": true,
		"why": "**한 대상을 오래 붙잡는** 경우. 무리전에서는 표적이 먼저 죽어 파쇄·표식 폭발이 완성되지 않는다. 보스는 피해만 받고 경직이 없어야 한다" },
]

func measure_build(arm: Dictionary) -> Dictionary:
	var g: Dictionary = PGrowth.new_growth(String(arm.main))
	g.weapons = []
	for r in (arm.weapons as Array):
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	for k in (arm.commons as Dictionary):
		(g.commons as Dictionary)[String(k)] = int((arm.commons as Dictionary)[k])
	return PBuild.derive(PBuild.empty_run_like(g))

## 적이 실제로 판정을 낸 공격 수(예고만 하고 끝난 것은 세지 않는다)
func attacks_executed(st: CombatState) -> int:
	var n := 0
	for k in (st.metrics.enemies as Dictionary):
		n += int((st.metrics.enemies[k] as Dictionary).get("executed", 0))
	return n

func measure_run(arm: Dictionary, seed_v: int, stagger_on: bool) -> Dictionary:
	var b := measure_build(arm)
	var st: CombatState
	if bool(arm.get("boss", false)):
		st = CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v, "arena": "clearing",
			"boss": true, "boss_id": "boss", "region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 4000.0 })
	else:
		st = CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
			"waves": [(arm.wave as Array).duplicate(true)],
			"objective": "clear", "region_id": "den", "act": 1 })
	var bot := PSkillBot.new("skilled", seed_v)
	var steps := int(MEASURE_SEC / STEP)
	var i := 0
	while i < steps and st.status == "running":
		if not stagger_on:
			for e in st.enemies:
				e["stagger_cd"] = 999.0
		st.step(bot.step_input(st), STEP)
		if not stagger_on:
			for e in st.enemies:
				e["stagger_cd"] = 999.0
		i += 1
	var tr := 0
	var ap := 0
	var bu := 0
	for k in (st.stagger_stats.tries as Dictionary):
		tr += int((st.stagger_stats.tries as Dictionary)[k])
	for k in (st.stagger_stats.applied as Dictionary):
		ap += int((st.stagger_stats.applied as Dictionary)[k])
	for k in (st.stagger_stats.bursts as Dictionary):
		bu += int((st.stagger_stats.bursts as Dictionary)[k])
	PSupport.sync_meters(st)
	var link := "빙결 %d · 파쇄 %d · 까마귀쪼기 %d · 표식폭발 %d · 감전후속 %d · 방전 %d · 불꽃파열 %d" % [
		int(PSupport.metered(st, "frost", "freezes")), int(PSupport.metered(st, "frost", "shatters")),
		int(PSupport.metered(st, "crow", "hits")), int(PSupport.metered(st, "crow", "bursts")),
		int(PSupport.metered(st, "orb", "shock_procs")), int(PSupport.metered(st, "orb", "discharges")),
		int(PSupport.metered(st, "common", "flare_bursts"))]
	# ⑤⑥은 표준 지표에 칸이 없어 상태 dict에서 바로 읽는다(조건 충족과 실제 발동을 가르는 칸까지 함께).
	var W: Dictionary = (st.support as Dictionary).get("wind", {})
	var PG: Dictionary = (st.support as Dictionary).get("plague", {})
	if not W.is_empty() or not PG.is_empty():
		link += " · 돌풍 %d(밀어냄 %d · 충돌 %d · 빈곳 %d · 붙어서거름 %d · 스침 %d)" % [
			int(W.get("blasts", 0)), int(W.get("pushed", 0)), int(W.get("slams", 0)),
			int(W.get("slam_open", 0)), int(W.get("slam_flush", 0)), int(W.get("slam_graze", 0))]
		link += " · 숙주파열 %d(자격없어 막힘 %d) · 전염 %d" % [
			int(PG.get("bursts", 0)), int(PG.get("burst_blocked", 0)), int(PG.get("spreads", 0))]
	return { "status": String(st.status), "sec": snappedf(float(st.t), 0.01), "kills": int(st.stats.kills),
		"taken": snappedf(float(st.stats.damage_taken), 0.1), "attacks": attacks_executed(st),
		"tries": tr, "applied": ap, "bursts": bu, "sec_stag": snappedf(float(st.stagger_stats.sec), 0.001),
		"by": (st.stagger_stats.applied as Dictionary).duplicate(), "link": link }

func sec10_measure() -> void:
	print("STAGGER_MEASURE 편성 | 시드 | 경직 | 상태 | 소요(초) | 처치 | 받은 피해 | 적 공격 실행 | 조건 충족 | 실제 발동 | 폭발 | 총 경직(초)")
	var off_applied := 0
	for arm in MEASURE_ARMS:
		for sd in [1, 2]:
			for on in [false, true]:
				var r := measure_run(arm, sd, on)
				if not on:
					off_applied += int(r.applied)
				print("STAGGER_MEASURE %s | %d | %s | %s | %.2f | %d | %.1f | %d | %d | %d | %d | %.3f" % [
					String(arm.id), sd, ("켬" if on else "끔"), String(r.status), float(r.sec), int(r.kills),
					float(r.taken), int(r.attacks), int(r.tries), int(r.applied), int(r.bursts), float(r.sec_stag)])
				if on:
					print("STAGGER_MEASURE   └ 연계 발동: %s" % String(r.link))
					print("STAGGER_MEASURE   └ 출처별 실제 경직: %s" % str(r.by))
	ok("비교 팔에서 경직을 막아도 연계 폭발은 그대로 일어났다(공격 효과를 취소하지 않는다)",
		off_applied == 0)
