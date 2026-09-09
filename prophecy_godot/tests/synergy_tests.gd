extends SceneTree
## 시너지 연결 검사(화면 없음).
## 실행: python tools/run_suites.py --suites synergy_tests
##      (직접: godot --headless --path prophecy_godot -s tests/synergy_tests.gd)
##
## 무엇을 보는가
## -------------
## **설명상 연결되는 효과가 실제로 함께 도는가**를 본다. 개별 보조의 동작은 support_a/b_tests가 이미 본다.
## 여기서는 **효과끼리의 연결**만 본다.
##
## 막아야 할 것과 허용해야 할 것을 구분한다
## ---------------------------------------
## 막을 것은 네 가지뿐이다 — 같은 적의 **사망 중복 정산** · 감전의 **자기 호출** ·
## 반사의 **자기 호출** · 분신의 **무한 복제**.
## 다른 적이 실제로 죽어 다음 처치 효과를 일으키는 것은 **정상이고 재미의 핵심**이므로
## 이 검사는 그것이 **여전히 일어나는지도 함께 단언한다**(연쇄를 통째로 막아 버리는 회귀를 잡기 위해서다).
##
## 결함은 고치지 않고 기록한다
## ---------------------------
## 규칙 코드(`scripts/**`)와 `data/**`는 이 담당의 소유가 아니다. 명세와 어긋나는 것을 찾으면
## `DEFECT` 줄로 기대·실제·재현을 남기고 **단언으로 실패시키지 않는다**(고칠 수 없는 곳을 빨갛게 두면
## 다른 담당의 회귀 신호가 묻힌다). 전체 목록은 `docs/SYNERGY.md` 3절에 있다.
##
## 수치는 전부 시험값이다(data/supports.json · data/main_weapons.json).

const STEP := 1.0 / 120.0
var results := []
var defects := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 명세와 어긋나지만 이 담당이 고칠 수 없는 것. 실패로 세지 않고 기록만 한다
func defect(id: String, name: String, expect: String, actual: String, repro: String) -> void:
	defects += 1
	print("DEFECT %s %s — 기대 %s / 실제 %s / 재현 %s" % [id, name, expect, actual, repro])

# ---------- 시험실 ----------
func lab(ids: Array, seed_v: int = 1, commons: Dictionary = {}) -> CombatState:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = []
	for r in ids:
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	for k in commons:
		(g.commons as Dictionary)[String(k)] = int(commons[k])
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = []
	return st

func tick(st: CombatState, dt: float) -> void:
	var keep := []
	for d in st.delayed:
		d.t = float(d.t) - dt
		if float(d.t) <= 0.0:
			(d.fn as Callable).call()
		else:
			keep.append(d)
	st.delayed = keep
	PSupport.update(st, dt)
	st.update_projectiles(dt)

func run_for(st: CombatState, sec: float) -> void:
	for i in int(round(sec / STEP)):
		tick(st, STEP)

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

func dummy(st: CombatState, dx: float, dy: float = 0.0, hp: float = 100000.0) -> Dictionary:
	var e: Dictionary = st.spawn_enemy("wolf", st.player.x + dx, st.player.y + dy)
	e.hp = hp
	e.hp_max = hp
	return e

func procs(st: CombatState) -> int:
	return int(PSupport.metered(st, "orb", "shock_procs"))

## 번개 구체를 함께 달고, 표적에 연쇄가 거는 것과 같은 값으로 감전을 걸어 둔 시험실
func shock_lab(ids: Array, ahead: float = 60.0) -> Array:
	var full: Array = [["orb", 1, []]]
	for i in ids:
		full.append(i)
	var st: CombatState = lab(full)
	var e: Dictionary = dummy(st, ahead)
	e.conduct = float(PCatalog.support_tuning("orb").get("shockDur", 2.0))
	return [st, e]

func _init() -> void:
	sec1_shock()
	sec2_echo()
	sec3_plague()
	sec4_reflect()
	sec5_chain_allowed()
	sec6_resonance()
	sec7_supply_chain()
	sec8_mod_coverage()
	sec9_spread_gen_knob()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("기록한 결함(단언 실패로 세지 않음): %d" % defects)
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 1. 감전 후속 ----------
func sec1_shock() -> void:
	# 자격표가 정본이다
	ok("자격표: 감전 후속은 주무기 직접·주무기 개조 추가·보조 직접·분신 모방에서 발동한다",
		PSupport.eligible("shock_bonus", "main_direct") and PSupport.eligible("shock_bonus", "main_extra")
		and PSupport.eligible("shock_bonus", "support_direct") and PSupport.eligible("shock_bonus", "echo_direct"))
	ok("자격표: 감전 후속이 자기 자신·장판·독·반사·지뢰/인형 폭발·역병 파열에서는 발동하지 않는다",
		not PSupport.eligible("shock_bonus", "shock_bonus") and not PSupport.eligible("shock_bonus", "zone_tick")
		and not PSupport.eligible("shock_bonus", "dot") and not PSupport.eligible("shock_bonus", "reflect")
		and not PSupport.eligible("shock_bonus", "mine_blast") and not PSupport.eligible("shock_bonus", "doll_blast")
		and not PSupport.eligible("shock_bonus", "plague_burst"))

	# 기본 연쇄가 감전을 부여한다(사용자 확정). 개조 '축전'을 고르지 않아도 걸려야 한다
	var st0: CombatState = lab([["orb", 1, []]])
	var t0: Dictionary = dummy(st0, 80.0)
	PWeapons.fire(st0, wep(st0, "orb"), t0, false)
	ok("번개 구체의 기본 연쇄가 감전을 건다(축전 없이도)", float(t0.conduct) > 0.0, "conduct=%s" % str(float(t0.conduct)))

	# 주무기 직접 타격이 감전 후속을 터뜨린다
	var a: Array = shock_lab([["sword", 1, []]])
	var sta: CombatState = a[0]
	PWeapons.fire(sta, wep(sta, "sword"), a[1], false)
	ok("주무기 직접 타격이 감전 후속을 터뜨린다", procs(sta) == 1, "발동 %d" % procs(sta))

	# 보조 직접 타격도 터뜨린다
	var b: Array = shock_lab([["wind", 1, []]], 90.0)
	var stb: CombatState = b[0]
	PWeapons.fire(stb, wep(stb, "wind"), b[1], false)
	ok("보조 직접 타격(바람 정령)이 감전 후속을 터뜨린다", procs(stb) >= 1, "발동 %d" % procs(stb))

	# 분신의 모방 타격이 감전을 발동시킨다(사용자 지시의 대표 연결)
	var c: Array = shock_lab([["sword", 1, []], ["echo", 1, []]], 20.0)
	var stc: CombatState = c[0]
	var ce: Dictionary = c[1]
	wep(stc, "sword").count = 1
	PWeapons.fire(stc, wep(stc, "sword"), ce, false)
	var before: int = procs(stc)
	ce.conduct = 2.0
	run_for(stc, 1.2)
	ok("잔영 분신의 모방 타격이 감전을 발동시킨다", procs(stc) - before >= 1,
		"모방 뒤 발동 %d · 모방 타격 %d" % [procs(stc) - before, int((stc.support.get("echo", {}) as Dictionary).get("strikes", 0))])

	# 감전 후속 자신은 감전을 다시 부르지 않는다(자기 호출 금지) — 한 번의 감전은 한 번만 터진다
	ok("감전 후속이 자기 자신을 다시 부르지 않는다(한 번의 감전 = 한 번의 후속)", procs(sta) == 1, "발동 %d" % procs(sta))

	# 축전: 감전 후속을 chargeNeed번 쌓으면 방전. 방전은 감전을 다시 걸지 않는다
	var T: Dictionary = PCatalog.support_tuning("orb")
	var need: int = int(T.get("chargeNeed", 3))
	var std: CombatState = lab([["orb", 1, ["conduct"]], ["sword", 1, []]])
	var de: Dictionary = dummy(std, 60.0)
	var dw: Dictionary = wep(std, "sword")
	for i in need:
		de.conduct = 2.0
		dw.count = int(dw.count) + 1
		PWeapons.fire(std, dw, de, false)
	ok("축전: 감전 후속 %d회에 방전이 한 번 일어난다" % need,
		int(PSupport.metered(std, "orb", "discharges")) == 1, "방전 %d" % int(PSupport.metered(std, "orb", "discharges")))
	ok("축전의 방전이 감전을 다시 걸지 않는다(자기 호출 금지)", float(de.conduct) == 0.0, "conduct=%s" % str(float(de.conduct)))
	var stn: CombatState = lab([["orb", 1, []], ["sword", 1, []]])
	var ne: Dictionary = dummy(stn, 60.0)
	var nw: Dictionary = wep(stn, "sword")
	for i in need + 1:
		ne.conduct = 2.0
		nw.count = int(nw.count) + 1
		PWeapons.fire(stn, nw, ne, false)
	ok("축전을 고르지 않았으면 방전이 일어나지 않는다",
		int(PSupport.metered(stn, "orb", "discharges")) == 0)

	# 장판 틱·독·반사·역병 파열·인형 폭발로는 감전이 터지지 않는다(실제 경로)
	ok("장판 틱으로는 감전 후속이 터지지 않는다", _shock_via_zone() == 0)
	ok("독으로는 감전 후속이 터지지 않는다", _shock_via_dot() == 0)
	ok("가시 반격으로는 감전 후속이 터지지 않는다", _shock_via_reflect() == 0)
	ok("역병 파열로는 감전 후속이 터지지 않는다", _shock_via_burst() == 0)

	# ----- 결함 기록(고치지 않는다) -----
	if _shock_via_mine() > 0:
		defect("SYN-1", "지뢰 폭발이 감전 후속을 터뜨린다",
			"자격표 deny(mine_blast)대로 발동 0", "발동 %d" % _shock_via_mine(),
			"tools/synergy_probe.gd 1절 `지뢰 폭발(룬 지뢰)` 줄. 원인: PWeapons.on_hit이 PSupport.cause_of에 피해 opt를 넘기지 않아 cause \"mine\"이 사라지고 보조 직접으로 읽힌다")
	if _shock_via_scar() == 0:
		defect("SYN-2", "주무기 개조의 추가 타격이 감전 후속을 못 터뜨린다(잔류 검흔·여진·날아가는 검광)",
			"자격표 allow(main_extra)대로 발동", "발동 0",
			"tools/synergy_probe.gd 1절 `검 잔류 검흔`·`망치 여진` 줄. 원인: PWeapons.on_hit이 자격표보다 먼저 src.direct를 보고 막는다. 같은 main_extra라도 교차 검격·귀환 검기는 direct 표시가 살아 있어 터진다")

func _shock_via_zone() -> int:
	var a: Array = shock_lab([["ember", 1, []]], 120.0)
	var st: CombatState = a[0]
	var e: Dictionary = a[1]
	PWeapons.fire(st, wep(st, "ember"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	for i in int(3.0 / STEP):
		tick(st, STEP)
		st.update_zones(STEP)
	return procs(st) - before

func _shock_via_dot() -> int:
	var a: Array = shock_lab([["plague", 1, []]], 120.0)
	var st: CombatState = a[0]
	var e: Dictionary = a[1]
	PWeapons.fire(st, wep(st, "plague"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	run_for(st, 3.0)
	return procs(st) - before

func _shock_via_reflect() -> int:
	var a: Array = shock_lab([["thorns", 1, []]], 40.0)
	var st: CombatState = a[0]
	var e: Dictionary = a[1]
	var before: int = procs(st)
	e.conduct = 2.0
	PSupport.after_player_damage(st, 10.0, "wolf:bite", e)
	return procs(st) - before

func _shock_via_burst() -> int:
	var a: Array = shock_lab([["plague", 1, ["burst"]]], 80.0)
	var st: CombatState = a[0]
	var near: Dictionary = a[1]
	var victim: Dictionary = st.spawn_enemy("wolf", float(near.x) - 40.0, float(near.y))
	near.conduct = 2.0
	PSupportB._infect(st, victim, 0, -1.0)
	var before: int = procs(st)
	st.kill_enemy(victim, {})
	return procs(st) - before

func _shock_via_mine() -> int:
	var a: Array = shock_lab([["mine", 1, []]], 30.0)
	var st: CombatState = a[0]
	var e: Dictionary = a[1]
	e.conduct = 2.0
	PWeapons.fire_mine(st, wep(st, "mine"))
	var before: int = procs(st)
	for i in int(2.0 / STEP):
		PWeapons.update_mines(st, STEP)
		if st.mines.is_empty():
			break
	return procs(st) - before

func _shock_via_scar() -> int:
	var a: Array = shock_lab([["sword", 1, ["scar"]]], 60.0)
	var st: CombatState = a[0]
	var e: Dictionary = a[1]
	PWeapons.fire(st, wep(st, "sword"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	run_for(st, 0.7)
	return procs(st) - before

# ---------- 2. 잔영 분신 ----------
func sec2_echo() -> void:
	var st: CombatState = lab([["sword", 1, []], ["echo", 1, []]])
	var e: Dictionary = dummy(st, 60.0)
	var w: Dictionary = wep(st, "sword")
	w.count = 1
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": true } }, 1.0)
	var S: Dictionary = st.support.get("echo", {})
	ok("주무기 기본 타격이 분신을 하나 만든다", int(S.get("spawned", 0)) == 1)
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": true } }, 1.0)
	ok("같은 공격의 두 번째 적중은 분신을 더 만들지 않는다", int(S.get("spawned", 0)) == 1)
	w.count = 2
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": false, "mod": "scar" }, "cause": "main_extra" }, 1.0)
	ok("주무기 개조의 추가 타격은 복제하지 않는다", int(S.get("spawned", 0)) == 1)
	w.count = 3
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": true, "echo": true }, "cause": "echo_direct" }, 1.0)
	ok("분신의 타격은 분신을 만들지 않는다(무한 복제 금지)", int(S.get("spawned", 0)) == 1)

	# 실제 프레임 경로에서도 늘지 않는다
	var st2: CombatState = lab([["sword", 3, []], ["echo", 3, []]])
	for i in 6:
		dummy(st2, 30.0 + float(i) * 20.0, 0.0, 4000.0)
	for i in int(20.0 / STEP):
		PWeapons.update(st2, STEP)
	var S2: Dictionary = st2.support.get("echo", {})
	var cap: int = int(PSupport.stats_of(st2, "echo").get("maxClones", 6))
	ok("20초 실제 경로: 동시 분신 수가 상한을 넘지 않는다",
		(S2.get("clones", []) as Array).size() <= cap,
		"분신 %d ≤ 상한 %d" % [(S2.get("clones", []) as Array).size(), cap])
	ok("20초 실제 경로: 분신 생성 수 ≤ 주무기 발사 수",
		int(S2.get("spawned", 0)) <= int(wep(st2, "sword").count) and int(S2.get("spawned", 0)) > 0,
		"생성 %d · 발사 %d" % [int(S2.get("spawned", 0)), int(wep(st2, "sword").count)])

# ---------- 3. 독 전염과 역병 파열 ----------
func sec3_plague() -> void:
	ok("전염 자격은 죽음의 출처를 가리지 않는다(모든 경로 허용)",
		PSupport.eligible("plague_spread", "main_direct") and PSupport.eligible("plague_spread", "dot")
		and PSupport.eligible("plague_spread", "plague_burst"))
	# 2026-09-09 시험값 2 → 3(사용자 승인). 상한 자체가 비교의 축이라 단언도 새 값에 맞춘다 —
	# 2/3/4 비교표는 docs/sim/SPREAD_PROBE.md에 그대로 남아 있고 여기서 다시 재지 않는다.
	# 이 단언의 뜻은 "권장값이 실제로 자료에 들어갔다"이고, 아래 두 검사가 "그 상한이 지켜진다"를 본다.
	var gmax := PSupport.gen_max("plague_spread")
	ok("전염 세대 상한이 3이다(시험값 2 → 3)", gmax == 3, "gen_max=%d" % gmax)

	# 세대 상한: 상한 세대인 독은 더 옮지 않는다(무한 재귀 방지가 상한을 올려도 그대로인가)
	var st: CombatState = lab([["plague", 1, []]])
	var a: Dictionary = st.spawn_enemy("wolf", st.player.x + 60.0, st.player.y)
	var b: Dictionary = st.spawn_enemy("wolf", st.player.x + 100.0, st.player.y)
	PSupportB._infect(st, a, gmax, 3.0)      # 이미 상한 세대인 독
	st.kill_enemy(a, {})
	ok("세대 상한(%d)을 넘는 전염은 일어나지 않는다" % gmax,
		(b.get("plague", {}) as Dictionary).is_empty(),
		"막힌 전염 %d" % int((st.support.get("plague", {}) as Dictionary).get("spread_blocked", 0)))

	# 정상적인 연쇄는 막지 않는다: 상한 바로 아래 세대는 한 번 더 옮아야 한다
	var st1b: CombatState = lab([["plague", 1, []]])
	var a1b: Dictionary = st1b.spawn_enemy("wolf", st1b.player.x + 60.0, st1b.player.y)
	var b1b: Dictionary = st1b.spawn_enemy("wolf", st1b.player.x + 100.0, st1b.player.y)
	PSupportB._infect(st1b, a1b, gmax - 1, 3.0)
	st1b.kill_enemy(a1b, {})
	var got1b: Dictionary = b1b.get("plague", {})
	ok("상한 바로 아래 세대(%d)의 독은 정상적으로 한 번 더 옮는다" % (gmax - 1),
		not got1b.is_empty() and int(got1b.get("gen", -1)) == gmax,
		"받은 세대 %d" % int(got1b.get("gen", -1)))

	# 같은 죽음으로 파열이 두 번 정산되지 않는다
	var st2: CombatState = lab([["plague", 1, ["burst"]]])
	var v: Dictionary = st2.spawn_enemy("wolf", st2.player.x + 60.0, st2.player.y)
	var n: Dictionary = dummy(st2, 100.0)
	PSupportB._infect(st2, v, 0, -1.0)
	var hp0: float = float(n.hp)
	st2.kill_enemy(v, {})
	var hp1: float = float(n.hp)
	PSupport.on_enemy_death(st2, v, {})
	var hp2: float = float(n.hp)
	ok("역병 파열이 실제로 주변에 피해를 준다", hp0 - hp1 > 0.0, "피해 %s" % str(snappedf(hp0 - hp1, 0.1)))
	ok("같은 죽음으로 역병 파열이 두 번 정산되지 않는다", is_zero_approx(hp1 - hp2),
		"두 번째 호출 피해 %s · 파열 횟수 %d" % [str(snappedf(hp1 - hp2, 0.1)),
			int((st2.support.get("plague", {}) as Dictionary).get("bursts", 0))])

	# 독가시의 독은 전염·파열 자격이 없다
	var st3: CombatState = lab([["thorns", 1, ["venom"]], ["plague", 1, []]])
	# t2는 반격 부채꼴(사거리 95) 밖이면서 전염 반경(110) 안에 세운다 —
	# 반격에 직접 맞아서 독이 묻는 것과 전염을 구분하기 위해서다
	var t1: Dictionary = st3.spawn_enemy("wolf", st3.player.x + 40.0, st3.player.y)
	var t2: Dictionary = st3.spawn_enemy("wolf", st3.player.x + 140.0, st3.player.y)
	PSupport.after_player_damage(st3, 10.0, "wolf:bite", t1)
	ok("독가시가 반격에 맞은 적에게만 독을 묻힌다(부채꼴 밖은 안 묻는다)",
		not (t1.get("plague", {}) as Dictionary).is_empty() and (t2.get("plague", {}) as Dictionary).is_empty())
	st3.kill_enemy(t1, {})
	ok("독가시가 묻힌 독은 전염되지 않는다", (t2.get("plague", {}) as Dictionary).is_empty())

# ---------- 4. 가시 반격 ----------
func sec4_reflect() -> void:
	ok("자격표: 반격은 적의 근접 타격에서만 발동하고 반사 자신에서는 발동하지 않는다",
		PSupport.eligible("thorns_reflect", "enemy_melee") and not PSupport.eligible("thorns_reflect", "reflect")
		and not PSupport.eligible("thorns_reflect", "enemy_projectile") and not PSupport.eligible("thorns_reflect", "enemy_zone"))
	var st: CombatState = lab([["thorns", 3, []]])
	var e: Dictionary = dummy(st, 40.0)
	PSupport.after_player_damage(st, 10.0, "wolf:bite", e)
	var r1: int = int((st.support.get("thorns", {}) as Dictionary).get("reflects", 0))
	PSupport.after_player_damage(st, 10.0, "reflect", e)
	var r2: int = int((st.support.get("thorns", {}) as Dictionary).get("reflects", 0))
	ok("근접 피격에 반격한다", r1 == 1, "반격 %d" % r1)
	ok("반사가 반사를 부르지 않는다(자기 호출 금지)", r2 == r1, "반사 경로 뒤 반격 %d" % r2)
	var st2: CombatState = lab([["thorns", 3, []]])
	var e2: Dictionary = dummy(st2, 300.0)
	PSupport.after_player_damage(st2, 10.0, "arrow", e2)
	PSupport.after_player_damage(st2, 10.0, "zone", null)
	ok("투사체·장판 피격에는 반격하지 않는다",
		int((st2.support.get("thorns", {}) as Dictionary).get("reflects", 0)) == 0)
	var st3: CombatState = lab([["thorns", 3, []]])
	var e3: Dictionary = dummy(st3, 40.0)
	PSupport.after_player_damage(st3, 0.0, "wolf:bite", e3)
	ok("막힌 공격(피해 0)에는 반격하지 않는다",
		int((st3.support.get("thorns", {}) as Dictionary).get("reflects", 0)) == 0)

# ---------- 5. 정상 연쇄는 살아 있어야 한다 ----------
## 자기 호출을 막으려다 **다른 적이 죽어 다음 효과가 도는 것**까지 막으면 재미가 사라진다.
## 사용자가 유일하게 만족감을 느낀 불꽃 파열이 그 기준점이라 여기서 못박는다.
func sec5_chain_allowed() -> void:
	var st: CombatState = lab([["ember", 3, []], ["sword", 3, []]], 1, { "ember": 1, "flare": 1 })
	var mob := []
	for i in 10:
		var e: Dictionary = st.spawn_enemy("wolf", st.player.x - 60.0 + float(i % 5) * 44.0, st.player.y - 20.0 + float(i / 5) * 44.0)
		e.hp = 12.0
		e.hp_max = 12.0
		mob.append(e)
	var z: Dictionary = st.add_zone("fire", float(mob[2].x), float(mob[2].y), 150.0, 12.0, 6.0)
	z.weapon = wep(st, "ember")
	run_for(st, 0.5)
	st.kill_enemy(mob[0], {})
	var chain: int = int(st.stats.kills) - 1
	ok("불꽃 파열의 연쇄가 살아 있다(한 마리를 죽이면 주변이 이어서 죽는다)", chain >= 3,
		"직접 처치 1 · 연쇄 처치 %d" % chain)

	# 독 전염도 다른 적의 죽음으로 계속 이어진다(세대 2까지)
	var st2: CombatState = lab([["plague", 3, []]])
	var pack := []
	for i in 6:
		var e2: Dictionary = st2.spawn_enemy("wolf", st2.player.x - 40.0 + float(i) * 34.0, st2.player.y)
		e2.hp = 1.0
		e2.hp_max = 1.0
		pack.append(e2)
	PSupportB._infect(st2, pack[2], 0, -1.0)
	run_for(st2, 0.5)
	st2.kill_enemy(pack[2], {})
	run_for(st2, 12.0)
	var P: Dictionary = st2.support.get("plague", {})
	ok("독 전염의 연쇄가 살아 있다(한 마리의 죽음이 다음 감염을 부른다)", int(P.get("spreads", 0)) >= 2,
		"전염 %d · 세대 상한에 막힌 죽음 %d" % [int(P.get("spreads", 0)), int(P.get("spread_blocked", 0))])

# ---------- 6. 무기 공명 자격 ----------
func sec6_resonance() -> void:
	var cases := [
		[["sword", "orb", "ember"], true, "공격 보조 2"],
		[["sword", "bell", "thorns"], false, "방어 보조 2"],
		[["sword", "doll", "thorns"], false, "소환·방어 보조"],
		[["sword", "echo", "bell"], false, "공격 1 + 방어 1"],
		[["sword", "crow", "plague"], true, "공격 보조 2"],
	]
	for c in cases:
		var g: Dictionary = PGrowth.new_growth(String((c[0] as Array)[0]))
		g.weapons = []
		for wid in (c[0] as Array):
			g.weapons.append({ "id": String(wid), "level": 1, "mods": [] })
		var applies: bool = PGrowth.boss_reward_applies(g, "resonance")
		ok("무기 공명 후보 자격 — %s(%s)" % [" + ".join(c[0]), String(c[2])], applies == bool(c[1]),
			"공격 출처 %d" % PGrowth.attack_source_count(g))

# ---------- 7. 공급 → 소비 사슬 ----------
## 상태를 **공급**하는 곳과 그것을 **받아 추가 효과를 내는** 곳을 따로 단언한다.
## 공급만 있고 소비가 없는 상태(냉기·독)는 여기서 "공급은 된다"까지만 못박는다 —
## 소비가 없다는 사실 자체는 결함이 아니라 설계 공백이므로 docs/SUPPORT_MATRIX.md 5절에 적었다.
func sec7_supply_chain() -> void:
	# (가) 냉기 공급원 셋이 실제로 냉기를 건다
	var st: CombatState = lab([["frost", 1, []]])
	var e: Dictionary = dummy(st, 120.0)
	PWeapons.fire(st, wep(st, "frost"), e, false)
	run_for(st, 1.0)
	ok("서리 수정의 탄환이 냉기를 건다", float(e.chill) > 0.0, "chill=%s" % str(snappedf(float(e.chill), 0.01)))

	var st2: CombatState = lab([["frost", 1, ["ground"]]])
	var e2: Dictionary = dummy(st2, 120.0)
	PWeapons.fire(st2, wep(st2, "frost"), e2, false)
	run_for(st2, 1.0)
	var cold := 0
	for z in st2.zones:
		if String((z as Dictionary).type) == "coldground":
			cold += 1
	ok("차가운 바닥이 냉기 장판을 남긴다", cold >= 1, "냉기 장판 %d개" % cold)

	var st3: CombatState = lab([["mine", 1, ["frosttrap"]]])
	var e3: Dictionary = dummy(st3, 30.0)
	PWeapons.fire_mine(st3, wep(st3, "mine"))
	for i in int(2.0 / STEP):
		PWeapons.update_mines(st3, STEP)
		if st3.mines.is_empty():
			break
	ok("서리 함정(룬 지뢰)이 냉기를 건다", float(e3.chill) > 0.0, "chill=%s" % str(snappedf(float(e3.chill), 0.01)))

	# (나) 냉기의 소비: 이동 속도가 실제로 느려진다
	var slowed := st3.enemy_speed_mult(e3)
	ok("냉기를 받은 적의 이동 속도 배율이 1보다 작다", slowed < 1.0, "배율 %s" % str(snappedf(slowed, 0.01)))

	# (다) 바람의 잔바람 둔화는 **냉기와 다른 경로**다(같은 '둔화'로 보이지만 e.chill을 쓰지 않는다).
	# 이 단언이 깨지면 두 경로가 하나로 합쳐진 것이므로 docs/SUPPORT_MATRIX.md SM-3을 다시 읽어야 한다
	var st4: CombatState = lab([["wind", 1, ["lingering"]]])
	var e4: Dictionary = dummy(st4, 60.0)
	PWeapons.fire(st4, wep(st4, "wind"), e4, false)
	run_for(st4, 0.5)
	var gusts := 0
	for z in st4.zones:
		if String((z as Dictionary).type) == "windgust":
			gusts += 1
	ok("잔바람이 둔화 장판을 남긴다", gusts >= 1, "잔바람 %d개" % gusts)
	ok("잔바람의 둔화는 냉기(e.chill)를 쓰지 않는다", is_zero_approx(float(e4.chill)),
		"chill=%s (0이 아니면 두 둔화 경로가 합쳐진 것이다)" % str(snappedf(float(e4.chill), 0.01)))

	# (라) 독 공급: 나비의 독과 독가시의 독은 **전염 자격이 다르다**
	var st5: CombatState = lab([["plague", 1, []]])
	var v1: Dictionary = dummy(st5, 120.0)
	PWeapons.fire(st5, wep(st5, "plague"), v1, false)
	run_for(st5, 1.0)
	var pg1: Dictionary = v1.get("plague", {})
	ok("역병 나비의 독은 전염 자격이 있다", not pg1.is_empty() and bool(pg1.get("spread", false)))
	var st6: CombatState = lab([["thorns", 1, ["venom"]]])
	var v2: Dictionary = dummy(st6, 40.0)
	PSupport.after_player_damage(st6, 10.0, "wolf:bite", v2)
	var pg2: Dictionary = v2.get("plague", {})
	ok("독가시의 독은 전염 자격이 없다", not pg2.is_empty() and not bool(pg2.get("spread", true)))

	# (마) 자격표 어휘: 회전 칼날 접촉은 '보조 직접 타격'으로 읽혀야 감전 후속을 터뜨린다
	var st7: CombatState = lab([["blades", 1, []]])
	ok("자격표 어휘: 회전 칼날 접촉(orbit)은 보조 직접 타격이다",
		PSupport.cause_of(st7, { "weapon": "blades" }) == "support_direct",
		"cause=%s" % PSupport.cause_of(st7, { "weapon": "blades" }))

# ---------- 8. 개조 36개가 자료와 코드에 모두 있는가 ----------
## '구현 누락'과 '설계만 있음'을 자료 쪽에서 확인한다. 코드 쪽 확인은 docs/SUPPORT_MATRIX.md 4절 표에 있다.
const SUPPORT_IDS := ["blades", "orb", "frost", "ember", "mine", "crow", "bell", "echo", "wind", "plague", "thorns", "doll"]

func sec8_mod_coverage() -> void:
	var total := 0
	var missing := []
	var not_impl := []
	for id in SUPPORT_IDS:
		var W: Dictionary = PCatalog.weapon(String(id))
		if W.is_empty():
			missing.append(String(id))
			continue
		if not bool(W.get("impl", false)):
			not_impl.append(String(id))
		var mods: Dictionary = W.get("mods", {})
		for m in mods:
			total += 1
			if not bool((mods[m] as Dictionary).get("impl", false)):
				not_impl.append("%s.%s" % [String(id), String(m)])
	ok("보조 12종이 모두 카탈로그에 있다", missing.is_empty(), "빠진 것: %s" % str(missing))
	ok("보조 개조가 36개다", total == 36, "실제 %d개" % total)
	ok("보조 12종·개조 36개가 모두 impl:true다", not_impl.is_empty(), "impl:false: %s" % str(not_impl))

	# 자격표의 다섯 효과가 전부 표에 있는가(설계만 있고 이름이 사라진 항목을 잡는다).
	# 실제 호출 여부는 1~4절이 경로로 확인한다
	var E: Dictionary = PCatalog.eligibility().get("effects", {})
	for eff in ["shock_bonus", "plague_spread", "thorns_reflect", "echo_copy", "crow_mark"]:
		ok("자격표에 %s가 있다" % eff, E.has(eff))

	# 보조마다 개조를 켜면 그 개조가 실제로 수치·상태를 바꾸는가(대표 셋)
	var stc: CombatState = lab([["crow", 1, ["twin"]]])
	var n_twin := PSupportA._crow_bird_count(stc, wep(stc, "crow"))
	ok("쌍둥이 까마귀를 켜면 까마귀가 2마리가 된다", n_twin == 2, "마리 수 %d" % n_twin)

	var stb: CombatState = lab([["bell", 1, ["layered"]]])
	var stb0: CombatState = lab([["bell", 1, []]])
	var cap1 := PSupportA.bell_max(stb, wep(stb, "bell"))
	var cap0 := PSupportA.bell_max(stb0, wep(stb0, "bell"))
	var rc1 := PSupportA.bell_recharge(stb, wep(stb, "bell"))
	var rc0 := PSupportA.bell_recharge(stb0, wep(stb0, "bell"))
	ok("겹울림을 켜면 방울 저장 상한이 늘고 충전이 느려진다", cap1 > cap0 and rc1 > rc0,
		"방울 %d→%d · 충전 %s→%s" % [cap0, cap1, str(snappedf(rc0, 0.01)), str(snappedf(rc1, 0.01))])

	var stp: CombatState = lab([["plague", 1, ["deep"]]])
	var vp: Dictionary = dummy(stp, 120.0)
	PSupportB._infect(stp, vp, 0, -1.0)
	var stp0: CombatState = lab([["plague", 1, []]])
	var vp0: Dictionary = dummy(stp0, 120.0)
	PSupportB._infect(stp0, vp0, 0, -1.0)
	var d1: Dictionary = vp.get("plague", {})
	var d0: Dictionary = vp0.get("plague", {})
	ok("깊은 맹독을 켜면 독이 세지고 전염 대상이 줄어든다",
		not d1.is_empty() and not d0.is_empty()
		and float(d1.dps) > float(d0.dps) and int(d1.spread_n) <= int(d0.spread_n),
		"독 %s→%s · 대상 %d→%d" % [str(snappedf(float(d0.get("dps", 0.0)), 0.1)), str(snappedf(float(d1.get("dps", 0.0)), 0.1)),
			int(d0.get("spread_n", 0)), int(d1.get("spread_n", 0))])

	# ----- SM-2 회귀: 유인 룬도 등급 저항을 지킨다(2026-09-09 고침) -----
	# 예전에는 보스만 빼고 정예를 일반 적과 똑같이 끌어당겼다(1.5초에 18px).
	# 위치를 강제로 바꾸는 것은 전부 PSupport.knock_dist를 거쳐야 한다 — 바람 정령과 같은 규칙이다.
	# 지뢰는 플레이어 발밑에 깔린다. 폭발 조건(trigger + 반지름) 밖, 유인 반경(70) 안에 세운다.
	# 준비 시간(arm 0.5초)이 지나야 당기기 시작한다. **0.6초만 굴린다** —
	# 오래 굴리면 일반 적이 지뢰 반지름에 닿아 멈춰(거리 제한) 배율 비교가 깨진다
	var pulled := {}
	for tp in ["wolf", "elite_fang"]:
		var stm: CombatState = lab([["mine", 1, ["lure"]]])
		var tgt: Dictionary = stm.spawn_enemy(String(tp), stm.player.x + 64.0, stm.player.y)
		tgt.hp = 99999.0
		PWeapons.fire_mine(stm, wep(stm, "mine"))
		var tx0: float = float(tgt.x)
		for i in int(0.6 / STEP):
			PWeapons.update_mines(stm, STEP)
			if stm.mines.is_empty():
				break
		pulled[String(tp)] = absf(float(tgt.x) - tx0)
		if String(tp) == "elite_fang":
			ok("정예로 세운 시험 대상이 실제로 정예다(SM-2 조건)", bool(tgt.get("elite", false)))
	var pull_n: float = float(pulled.get("wolf", 0.0))
	var pull_e: float = float(pulled.get("elite_fang", 0.0))
	ok("유인 룬: 일반 적은 끌려온다", pull_n > 1.0, "%.1fpx(0.6초 중 준비 0.5초를 뺀 0.1초)" % pull_n)
	ok("유인 룬: 정예는 등급 저항만큼 덜 끌려온다(바람 정령과 같은 규칙)",
		pull_e > 0.0 and pull_e < pull_n - 0.1, "정예 %.2fpx < 일반 %.2fpx" % [pull_e, pull_n])
	var km: float = float((PCatalog.support_resist().get("knock", {}) as Dictionary).get("elite", 1.0))
	ok("유인 룬: 저항 배율이 자격표(supports.json resist.knock.elite)와 맞는다",
		absf(pull_e - pull_n * km) < maxf(0.15, pull_n * 0.06),
		"정예 %.2f · 기대 %.2f(=%.2f×%.2f)" % [pull_e, pull_n * km, pull_n, km])

# ---------- 9. 전염 세대 상한이 실제로 달린 손잡이인가 ----------
## `data/supports.json`은 읽기만 한다. 메모리에 올라온 자격표의 gen_max만 잠시 바꾸고 되돌린다.
## **값을 바꾸자는 것이 아니라, 그 손잡이가 실제로 사슬 길이를 정하는지**를 못박는 검사다.
## 비교표와 권장안은 docs/sim/SPREAD_PROBE.md와 docs/SYNERGY.md에 있다.
func sec9_spread_gen_knob() -> void:
	var eff: Dictionary = (PCatalog.eligibility().get("effects", {}) as Dictionary).get("plague_spread", {})
	var saved := int(eff.get("gen_max", 2))
	var got := {}
	for gm in [2, 4]:
		eff["gen_max"] = gm
		got[gm] = _spread_pack(0.3)
	eff["gen_max"] = saved
	ok("세대 상한을 2에서 4로 올리면 전염이 실제로 더 이어진다",
		int((got[4] as Dictionary).spreads) > int((got[2] as Dictionary).spreads),
		"전염 %d → %d · 도달 세대 %d → %d" % [int((got[2] as Dictionary).spreads), int((got[4] as Dictionary).spreads),
			int((got[2] as Dictionary).max_gen), int((got[4] as Dictionary).max_gen)])
	ok("세대 상한 2에서는 2세대를 넘지 않는다", int((got[2] as Dictionary).max_gen) <= 2,
		"도달 세대 %d" % int((got[2] as Dictionary).max_gen))
	ok("검사가 끝난 뒤 자격표의 세대 상한이 원래 값으로 돌아왔다",
		PSupport.gen_max("plague_spread") == saved, "gen_max=%d" % PSupport.gen_max("plague_spread"))

	# 상한을 올려도 **남은 시간 상속**이라는 두 번째 제동 장치는 그대로여야 한다.
	# 온전한 체력의 적에게는 상한을 올려도 사슬이 길어지지 않는다는 것을 못박는다
	# (앞선 보고의 '상한 2가 연쇄를 70% 깎는다'가 한 조건에서만 나온 값이라는 근거이기도 하다)
	var full := {}
	for gm in [2, 4]:
		eff["gen_max"] = gm
		full[gm] = _spread_pack(1.0)
	eff["gen_max"] = saved
	ok("온전한 체력의 적에게는 세대 상한을 올려도 사슬이 길어지지 않는다(제동 장치가 남은 시간이다)",
		int((full[2] as Dictionary).spreads) == int((full[4] as Dictionary).spreads),
		"전염 %d(상한 2) 대 %d(상한 4) — 다르면 상속 규칙이 바뀐 것이다" % [
			int((full[2] as Dictionary).spreads), int((full[4] as Dictionary).spreads)])

	# 전염은 지속 시간을 최대치로 되돌리지 않는다(무한 연장 금지)
	var st3: CombatState = lab([["plague", 1, []]])
	var a3: Dictionary = st3.spawn_enemy("wolf", st3.player.x + 60.0, st3.player.y)
	var b3: Dictionary = dummy(st3, 100.0)
	PSupportB._infect(st3, a3, 0, -1.0)
	run_for(st3, 2.0)
	var left: float = float((a3.plague as Dictionary).t)
	st3.kill_enemy(a3, {})
	var pb: Dictionary = b3.get("plague", {})
	ok("전염이 지속 시간을 최대치로 되돌리지 않고 남은 시간을 물려받는다",
		not pb.is_empty() and float(pb.t) <= left + 1e-3 and float(pb.t) < float(pb.max) - 1e-3,
		"물려준 남은 시간 %s → 받은 시간 %s (최대 %s)" % [str(snappedf(left, 0.01)),
			str(snappedf(float(pb.get("t", 0.0)), 0.01)), str(snappedf(float(pb.get("max", 0.0)), 0.01))])

## 늑대 16마리를 4×4 밀집으로 세우고 가운데 하나만 감염시킨 뒤 그 하나를 처치한다.
## hp_frac은 시작 체력 비율(0.3 = 주무기가 이미 긁어 놓은 상태, 1.0 = 온전)
func _spread_pack(hp_frac: float) -> Dictionary:
	var st: CombatState = lab([["plague", 3, []]])
	var pack := []
	for iy in 4:
		for ix in 4:
			var e: Dictionary = st.spawn_enemy("wolf", 380.0 + float(ix) * 70.0, 220.0 + float(iy) * 70.0)
			e.hp = float(e.hp_max) * hp_frac
			pack.append(e)
	PSupportB._infect(st, pack[5], 0, -1.0)
	run_for(st, 0.5)
	st.kill_enemy(pack[5], {})
	run_for(st, 14.0)
	var P: Dictionary = st.support.get("plague", {})
	var dead := 0
	for e in pack:
		if bool(e.dead):
			dead += 1
	return { "spreads": int(P.get("spreads", 0)), "max_gen": int(P.get("max_gen", 0)),
		"blocked": int(P.get("spread_blocked", 0)), "dead": dead }
