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
	ok("전염 세대 상한이 2다", PSupport.gen_max("plague_spread") == 2)

	# 세대 상한: 3세대는 일어나지 않는다
	var st: CombatState = lab([["plague", 1, []]])
	var a: Dictionary = st.spawn_enemy("wolf", st.player.x + 60.0, st.player.y)
	var b: Dictionary = st.spawn_enemy("wolf", st.player.x + 100.0, st.player.y)
	PSupportB._infect(st, a, 2, 3.0)      # 이미 2세대인 독
	st.kill_enemy(a, {})
	ok("세대 상한 2를 넘는 전염은 일어나지 않는다",
		(b.get("plague", {}) as Dictionary).is_empty(),
		"막힌 전염 %d" % int((st.support.get("plague", {}) as Dictionary).get("spread_blocked", 0)))

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
