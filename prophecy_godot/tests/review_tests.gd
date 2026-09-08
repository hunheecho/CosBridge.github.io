extends SceneTree
## **자체 교차 검수 전용 시험**(2026-09-09). 규칙·자료 코드는 하나도 고치지 않는다.
## 실행: godot --headless --path prophecy_godot -s tests/review_tests.gd
##
## 왜 따로 만들었나
## ---------------
## 기존 스위트는 `PSupport.eligible("shock_bonus", "mine_blast")`처럼 **자격표를 직접 물어보는** 단언이 많다.
## 그것은 자료 파일이 자기 자신과 일치한다는 것만 증명한다 — 실제 전투 코드가 그 표를 **부르는지**,
## 부를 때 **올바른 경로 이름**을 넘기는지는 증명하지 않는다.
## 그래서 여기서는 되도록 **실제 피해 경로**(fire_chain · explode_mine · damage_player · st.step)를 그대로 태우고
## 결과 계수기로 단언한다.
##
## 단언 이름 규칙
##   [명세] — 문서·자료가 그렇다고 적은 것
##   [실측] — 판정이 아니라 수치를 남기는 줄(항상 통과. 보고서에 옮긴다)

const STEP := 1.0 / 120.0
var results := []
var notes := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func measure(name: String, text: String) -> void:
	notes.append([name, text])
	print("MEASURE " + name + " — " + text)

func near(a: float, b: float, tol: float = 0.05) -> bool:
	return absf(a - b) <= tol

# ---------- 시험실 ----------
## ids = [[무기 id, 레벨, [개조...]], ...]. 적은 저절로 나오지 않고 장애물도 없다
func lab(ids: Array, seed_v: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.weapons = []
	for row in ids:
		g.weapons.append({ "id": String(row[0]), "level": int(row[1]), "mods": (row[2] as Array).duplicate() })
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = []
	return st

func put(st: CombatState, type: String, x: float, y: float) -> Dictionary:
	return st.spawn_enemy(type, x, y)

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

## st.step 없이 보조 규칙만 진행(적 위치가 그대로 유지된다)
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

func run_for(st: CombatState, sec: float) -> void:
	for i in int(round(sec / STEP)):
		tick(st, STEP)

func procs(st: CombatState) -> float:
	return PSupport.metered(st, "orb", "shock_procs")

## 보조별 내부 계수기는 PSupport.update가 돌 때만 표준 지표로 옮겨진다.
## 시험이 st.step / PSupport.update 없이 규칙 함수만 부를 때는 여기서 직접 맞춰 준다
func sync(st: CombatState) -> void:
	PSupport.sync_meters(st)

func shocks(st: CombatState) -> float:
	return PSupport.metered(st, "orb", "shocks")

func _init() -> void:
	s1_shock()
	s2_echo()
	s3_plague()
	s4_reflect()
	s5_normal_chain()
	s6_doll()
	s7_daggers_dps()
	s8_shieldbearer()
	s9_spore()
	s10_save_compat()
	print("--- 실측 %d줄 ---" % notes.size())
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ================= 1. 감전 연계와 자기 호출 =================
func s1_shock() -> void:
	print("--- 1. 감전(번개 구체) ---")

	# 1-1. 개조 없이 기본 연쇄만으로 감전이 붙는가 — 실제 fire_chain 경로
	var st := lab([["orb", 1, []]])
	var a := put(st, "wolf", st.player.x + 120.0, st.player.y)
	PWeapons.fire(st, wep(st, "orb"), a, false)
	ok("[명세] 개조 없이도 번개 구체의 **기본 연쇄**가 감전을 건다(축전 불필요)",
		float(a.conduct) > 0.0, "conduct=%.2f · shocks=%.0f" % [float(a.conduct), shocks(st)])

	# 1-2. 감전된 적을 주무기가 직접 때리면 추가 번개
	# (여기부터는 감전 상태를 손으로 세운다 — 연쇄가 옆 적까지 감전시켜 셈이 흐려지는 것을 막는다)
	var st2 := lab([["sword", 1, []], ["orb", 1, []]])
	var b := put(st2, "wolf", st2.player.x + 60.0, st2.player.y)
	var b2 := put(st2, "wolf", st2.player.x + 80.0, st2.player.y)
	b.conduct = 99.0
	var p0 := procs(st2)
	st2.damage_enemy(b, 1.0, { "src": PWeapons.src(wep(st2, "sword")) })
	ok("[명세] 감전된 적을 **주무기**가 직접 때리면 추가 번개가 터진다",
		procs(st2) - p0 >= 1.0, "shock_procs %.0f→%.0f · 이웃 hp %.1f" % [p0, procs(st2), float(b2.hp)])

	# 1-3. 보조무기의 직접 타격으로도 터진다(자격표 support_direct)
	var st3 := lab([["blades", 1, []], ["orb", 1, []]])
	var c := put(st3, "wolf", st3.player.x + 60.0, st3.player.y)
	c.conduct = 99.0
	var p3 := procs(st3)
	st3.damage_enemy(c, 1.0, { "src": PWeapons.src(wep(st3, "blades")) })
	ok("[명세] 감전된 적을 **보조**가 직접 때려도 추가 번개가 터진다",
		procs(st3) - p3 >= 1.0, "shock_procs %.0f→%.0f" % [p3, procs(st3)])

	# 1-4. 감전 후속이 자기 자신을 다시 발동시키지 않는다.
	# 감전된 적 4마리를 서로 붙여 둔다 — 자기 호출이 있으면 한 번의 주무기 타격으로 폭발이 연쇄한다
	var st4 := lab([["sword", 1, []], ["orb", 1, []]])
	var group := []
	for i in 4:
		var e := put(st4, "wolf", st4.player.x + 60.0 + float(i) * 18.0, st4.player.y)
		e.conduct = 5.0 # 4마리 전부 감전 상태로 고정
		group.append(e)
	var p4 := procs(st4)
	st4.damage_enemy(group[0], 1.0, { "src": PWeapons.src(wep(st4, "sword")) })
	ok("[명세] 감전 추가 피해가 **자기 자신을 다시 발동시키지 않는다**(붙어 있는 감전 적 4마리, 주무기 1타 → 후속 1회)",
		near(procs(st4) - p4, 1.0), "shock_procs 증가 %.0f (기대 1)" % [procs(st4) - p4])

	# 1-5. 장판 틱으로는 안 터진다 — combat_state.update_zones가 실제로 넘기는 opt를 그대로 쓴다
	var st5 := lab([["ember", 1, []], ["orb", 1, []]])
	var d := put(st5, "wolf", st5.player.x + 60.0, st5.player.y)
	d.conduct = 99.0
	var p5 := procs(st5)
	var ew := wep(st5, "ember")
	st5.damage_enemy(d, 3.0, { "src": { "weapon": ew.stats, "weapon_id": "ember", "direct": false, "extra": true } })
	ok("[명세] **장판 틱**으로는 감전 후속이 터지지 않는다", near(procs(st5) - p5, 0.0),
		"shock_procs 증가 %.0f" % [procs(st5) - p5])

	# 1-6. 독(dot)으로는 안 터진다 — 역병 나비의 실제 독 정산 경로
	var st6 := lab([["plague", 1, []], ["orb", 1, []]])
	var f := put(st6, "wolf", st6.player.x + 60.0, st6.player.y)
	f.conduct = 99.0
	PSupport.fire(st6, wep(st6, "plague"), f, false)
	var p6 := procs(st6)
	run_for(st6, 3.0) # 나비가 붙고 독이 여러 번 정산된다
	ok("[명세] **독 지속 피해**로는 감전 후속이 터지지 않는다(실제 역병 정산 경로)",
		near(procs(st6) - p6, 0.0),
		"shock_procs 증가 %.0f · 독 피해 %.1f" % [procs(st6) - p6, PSupport.metered(st6, "plague", "dot_dmg")])

	# 1-7. 역병 파열로는 안 터진다. 감염돼 죽는 적(g1)과 감전된 이웃(g2)을 갈라 둔다
	var st7 := lab([["plague", 1, ["burst"]], ["orb", 1, []]])
	var g1 := put(st7, "wolf", st7.player.x + 60.0, st7.player.y)
	var g2 := put(st7, "wolf", st7.player.x + 78.0, st7.player.y)
	PSupport.fire(st7, wep(st7, "plague"), g1, false)
	run_for(st7, 1.5)
	g1.conduct = 0.0 # g1은 감전이 아니다(죽이는 타격이 후속을 부르지 않게)
	g2.conduct = 99.0 # 파열 반경 안의 이웃만 감전 상태
	var p7 := procs(st7)
	st7.damage_enemy(g1, 1.0e6, { "src": { "weapon_id": "plague", "direct": false, "extra": true }, "cause": "dot" })
	sync(st7)
	ok("[명세] **역병 파열**로는 감전 후속이 터지지 않는다",
		PSupport.metered(st7, "plague", "bursts") >= 1.0 and near(procs(st7) - p7, 0.0),
		"파열 %.0f회 · shock_procs 증가 %.0f" % [PSupport.metered(st7, "plague", "bursts"), procs(st7) - p7])

	# 1-8. **지뢰 폭발**로는 안 터져야 한다(자료 deny 목록에 mine_blast가 있다) — 실제 explode_mine 경로
	var st8 := lab([["mine", 1, []], ["orb", 1, []]])
	var h := put(st8, "wolf", st8.player.x + 60.0, st8.player.y)
	h.conduct = 99.0
	var mw := wep(st8, "mine")
	st8.mines.append({ "weapon": mw, "x": float(h.x), "y": float(h.y), "r": float(mw.stats.trigger), "arm": 0.0, "t": 9.0, "dead": false })
	var p8 := procs(st8)
	PWeapons.explode_mine(st8, st8.mines[0])
	ok("[명세] **지뢰 폭발**로는 감전 후속이 터지지 않는다(supports.json deny: mine_blast)",
		near(procs(st8) - p8, 0.0),
		"shock_procs 증가 %.0f (기대 0)" % [procs(st8) - p8])

	# 1-9. 인형 폭발로는 안 터진다
	var st9 := lab([["doll", 1, ["firework"]], ["orb", 1, []]])
	var i1 := put(st9, "wolf", st9.player.x + 90.0, st9.player.y)
	i1.conduct = 99.0
	PSupport.fire(st9, wep(st9, "doll"), i1, false)
	var p9 := procs(st9)
	var dobj: Dictionary = st9.support.get("doll_obj", {})
	if not dobj.is_empty():
		dobj.x = float(i1.x)
		dobj.y = float(i1.y)
		dobj.ttl = 0.001
	run_for(st9, 2.0)
	ok("[명세] **인형 폭발**로는 감전 후속이 터지지 않는다",
		near(procs(st9) - p9, 0.0),
		"폭발 %.0f회 · shock_procs 증가 %.0f" % [float((st9.support.get("doll", {}) as Dictionary).get("blasts", 0)), procs(st9) - p9])

# ================= 2. 잔영 분신 =================
func s2_echo() -> void:
	print("--- 2. 잔영 분신 ---")

	# 2-1. 주무기 기본 공격이 분신을 만든다
	var st := lab([["sword", 1, []], ["echo", 1, []]])
	var a := put(st, "wolf", st.player.x + 60.0, st.player.y)
	PWeapons.fire(st, wep(st, "sword"), a, false)
	var sp1 := float((st.support.get("echo", {}) as Dictionary).get("spawned", 0))
	ok("[명세] 주무기 **기본** 공격이 분신을 만든다", sp1 >= 1.0, "spawned=%.0f" % sp1)

	# 2-2. 지뢰 폭발(보조 경로)은 분신을 만들지 않는다 — 실제 explode_mine
	var st2 := lab([["sword", 1, []], ["echo", 1, []], ["mine", 1, []]])
	var b := put(st2, "wolf", st2.player.x + 60.0, st2.player.y)
	var mw := wep(st2, "mine")
	st2.mines.append({ "weapon": mw, "x": float(b.x), "y": float(b.y), "r": float(mw.stats.trigger), "arm": 0.0, "t": 9.0, "dead": false })
	var before := float((st2.support.get("echo", {}) as Dictionary).get("spawned", 0))
	PWeapons.explode_mine(st2, st2.mines[0])
	var after := float((st2.support.get("echo", {}) as Dictionary).get("spawned", 0))
	ok("[명세] 지뢰 폭발(보조 경로)은 분신을 만들지 않는다", near(after - before, 0.0),
		"spawned %.0f→%.0f" % [before, after])

	# 2-3. 분신이 분신을 만들지 않는다 — 분신이 실제로 때릴 때까지 돌린다.
	# 분신은 공격 방향의 **반대쪽** offset(72)에 생기므로, 적을 가까이 두어야 분신 사거리 안에 들어온다
	var st3 := lab([["sword", 1, []], ["echo", 1, []]])
	var c := put(st3, "wolf", st3.player.x + 18.0, st3.player.y)
	c.hp = 1.0e9
	PWeapons.fire(st3, wep(st3, "sword"), c, false)
	var S3: Dictionary = st3.support.get("echo", {})
	var spawn_before := float(S3.get("spawned", 0))
	run_for(st3, 1.5) # delay 0.35초 뒤 분신이 실제로 때린다
	var strikes := float(S3.get("strikes", 0))
	var spawn_after := float(S3.get("spawned", 0))
	ok("[명세] 분신이 실제로 타격하고, 그 타격이 **또 분신을 만들지 않는다**",
		strikes >= 1.0 and near(spawn_after - spawn_before, 0.0),
		"타격 %.0f회 · 헛돎 %.0f회 · spawned %.0f→%.0f" % [strikes, float(S3.get("fizzles", 0)), spawn_before, spawn_after])

	# 2-4. 한 번의 공격에 분신 하나(적 여럿을 맞혀도)
	var st4 := lab([["sword", 1, []], ["echo", 1, []]])
	for i in 4:
		put(st4, "wolf", st4.player.x + 50.0, st4.player.y - 30.0 + float(i) * 20.0)
	var t0: Dictionary = st4.enemies[0]
	PWeapons.fire(st4, wep(st4, "sword"), t0, false)
	var sp4 := float((st4.support.get("echo", {}) as Dictionary).get("spawned", 0))
	ok("[명세] 한 번의 공격이 적 여럿을 맞혀도 분신은 하나", near(sp4, 1.0), "spawned=%.0f" % sp4)

	# 2-5. 분신의 타격이 감전을 발동시킨다(자격표가 echo_direct를 허용한다)
	var st5 := lab([["sword", 1, []], ["echo", 1, []], ["orb", 1, []]])
	var e5 := put(st5, "wolf", st5.player.x + 18.0, st5.player.y)
	e5.hp = 1.0e9
	e5.conduct = 99.0
	var pb := procs(st5)
	PWeapons.fire(st5, wep(st5, "sword"), e5, false)
	e5.conduct = 99.0 # 본체 타격이 소모한 감전을 되돌려 분신 타격만 본다
	var pmid := procs(st5)
	run_for(st5, 1.5)
	ok("[명세] **분신의 직접 타격**이 감전 후속을 발동시킨다",
		procs(st5) - pmid >= 1.0, "본체 후 %.0f → 분신 후 %.0f" % [pmid - pb, procs(st5) - pmid])

# ================= 3. 독 전염·파열 =================
func s3_plague() -> void:
	print("--- 3. 역병 나비 ---")

	# 3-1. 전염 세대가 2를 넘지 않는다 — 한 줄로 세운 적 5마리를 차례로 죽인다
	var st := lab([["plague", 1, []]])
	var line := []
	for i in 5:
		line.append(put(st, "wolf", st.player.x + 120.0 + float(i) * 60.0, st.player.y))
	PSupport.fire(st, wep(st, "plague"), line[0], false)
	run_for(st, 0.6)
	var max_gen := 0
	for k in 5:
		var alive: Dictionary = line[k]
		if not bool(alive.get("dead", false)) and not (alive.get("plague", {}) as Dictionary).is_empty():
			max_gen = maxi(max_gen, int((alive.plague as Dictionary).get("gen", 0)))
		st.damage_enemy(alive, 1.0e6, { "src": { "weapon_id": "sword", "direct": true }, "cause": "main_direct" })
		run_for(st, 0.2)
		for o in line:
			if not bool(o.get("dead", false)) and not (o.get("plague", {}) as Dictionary).is_empty():
				max_gen = maxi(max_gen, int((o.plague as Dictionary).get("gen", 0)))
	ok("[명세] 독 전염 세대가 **2를 넘지 않는다**", max_gen <= PSupport.gen_max("plague_spread"),
		"관측 최대 세대 %d (상한 %d) · 전염 %.0f회" % [max_gen, PSupport.gen_max("plague_spread"), PSupport.metered(st, "plague", "spreads")])

	# 3-2. 파열이 같은 죽음으로 두 번 정산되지 않는다 — on_enemy_death를 일부러 다시 부른다
	var st2 := lab([["plague", 1, ["burst"]]])
	var a := put(st2, "wolf", st2.player.x + 150.0, st2.player.y)
	put(st2, "wolf", st2.player.x + 170.0, st2.player.y)
	PSupport.fire(st2, wep(st2, "plague"), a, false)
	run_for(st2, 1.0)
	st2.damage_enemy(a, 1.0e6, { "src": { "weapon_id": "sword", "direct": true }, "cause": "main_direct" })
	sync(st2)
	var burst1 := PSupport.metered(st2, "plague", "bursts")
	PSupport.on_enemy_death(st2, a, { "src": { "weapon_id": "sword", "direct": true }, "cause": "main_direct" })
	sync(st2)
	var burst2 := PSupport.metered(st2, "plague", "bursts")
	ok("[명세] 파열이 **같은 죽음으로 두 번 정산되지 않는다**", burst1 >= 1.0 and near(burst2, burst1),
		"첫 정산 %.0f · 같은 개체 재호출 뒤 %.0f" % [burst1, burst2])

# ================= 4. 가시 반격 =================
func s4_reflect() -> void:
	print("--- 4. 가시 갑각 ---")

	# 4-1. 근접 피격에 반격한다(실제 damage_player 경로)
	var st := lab([["thorns", 1, []]])
	var a := put(st, "wolf", st.player.x + 30.0, st.player.y)
	st.player.hit_prot = 0.0
	st.damage_player(10.0, "wolf_bite", a)
	sync(st)
	var r1 := PSupport.metered(st, "thorns", "reflects")
	ok("[명세] 근접 피격에 가시 반격이 발동한다", r1 >= 1.0, "반격 %.0f회 · 적 hp %.1f" % [r1, float(a.hp)])

	# 4-2. **막힌 공격(피해 0)에는 반격하지 않는다** — 회피 무적 중
	var st2 := lab([["thorns", 1, []]])
	var b := put(st2, "wolf", st2.player.x + 30.0, st2.player.y)
	st2.player.hit_prot = 0.0
	st2.player.dodge_active = 1.0 # 회피 무적
	var before := PSupport.metered(st2, "thorns", "reflects")
	st2.damage_player(10.0, "wolf_bite", b)
	PSupport.sync_meters(st2)
	ok("[명세] **막힌 공격(피해 0)에는 반격하지 않는다**",
		near(PSupport.metered(st2, "thorns", "reflects") - before, 0.0),
		"반격 증가 %.0f · 플레이어 hp %.1f" % [PSupport.metered(st2, "thorns", "reflects") - before, float(st2.player.hp)])

	# 4-3. 반사가 반사를 부르지 않는다 — 반격 피해를 적에게 넣어도 새 반격이 생기지 않는다
	var st3 := lab([["thorns", 1, []]])
	var c := put(st3, "wolf", st3.player.x + 30.0, st3.player.y)
	st3.player.hit_prot = 0.0
	st3.damage_enemy(c, 1.0, { "src": { "weapon_id": "thorns", "direct": false, "extra": true, "tag": "support:thorns:reflect" }, "cause": "reflect" })
	PSupport.sync_meters(st3)
	ok("[명세] 반사 피해가 또 반사를 부르지 않는다",
		near(PSupport.metered(st3, "thorns", "reflects"), 0.0),
		"반격 %.0f회" % PSupport.metered(st3, "thorns", "reflects"))

	# 4-4. 원거리·장판 피격에는 반격이 없다
	var st4 := lab([["thorns", 1, []]])
	var d := put(st4, "wolf", st4.player.x + 300.0, st4.player.y)
	st4.player.hit_prot = 0.0
	st4.damage_player(10.0, "arrow", d)
	PSupport.sync_meters(st4)
	ok("[명세] 원거리 투사체 피격에는 가시 반격이 없다",
		near(PSupport.metered(st4, "thorns", "reflects"), 0.0),
		"반격 %.0f회" % PSupport.metered(st4, "thorns", "reflects"))

# ================= 5. 정상 연쇄는 살아 있는가 =================
func s5_normal_chain() -> void:
	print("--- 5. 정상 연쇄 ---")

	# 5-1. 다른 적이 실제로 죽어 다음 효과(전염)를 일으킨다 — 막으면 안 되는 연쇄
	var st := lab([["plague", 1, []]])
	var a := put(st, "wolf", st.player.x + 150.0, st.player.y)
	var b := put(st, "wolf", st.player.x + 200.0, st.player.y)
	PSupport.fire(st, wep(st, "plague"), a, false)
	run_for(st, 0.6)
	st.damage_enemy(a, 1.0e6, { "src": { "weapon_id": "sword", "direct": true }, "cause": "main_direct" })
	sync(st)
	ok("[명세] **정상 연쇄는 막지 않는다** — 감염된 적이 죽으면 옆 적에게 실제로 옮는다",
		not (b.get("plague", {}) as Dictionary).is_empty(),
		"전염 %.0f회 · 옆 적 감염=%s" % [PSupport.metered(st, "plague", "spreads"), str(not (b.get("plague", {}) as Dictionary).is_empty())])

	# 5-2. 처치 연계(쌍검 추격 칼날)가 살아 있다 — 죽음이 다음 투사체를 만든다
	var st2 := lab([["daggers", 1, ["pursuit"]]])
	var c := put(st2, "wolf", st2.player.x + 40.0, st2.player.y)
	put(st2, "wolf", st2.player.x + 120.0, st2.player.y)
	var pr0 := st2.projectiles.size()
	st2.damage_enemy(c, 1.0e6, { "src": PWeapons.src(wep(st2, "daggers")) })
	ok("[명세] **처치 연계는 막지 않는다** — 적이 죽으면 추격 칼날이 다음 적에게 날아간다",
		st2.projectiles.size() > pr0, "투사체 %d→%d" % [pr0, st2.projectiles.size()])

# ================= 6. 도깨비 인형 =================
## 인형을 플레이어에게서 dist만큼 떨어뜨려 놓고, 유인 명단에 오른 적을 **인형 바로 옆**에 세운 뒤
## 실제 근접 피격 경로(damage_player)를 태운다. 돌려주는 값: [대신 받은 횟수, 남은 인형 체력, 부서진 횟수]
func doll_case(dist: float) -> Array:
	var st := lab([["doll", 1, []]])
	var w := put(st, "wolf", st.player.x + 100.0, st.player.y)
	PSupport.fire(st, wep(st, "doll"), w, false)
	run_for(st, 0.2) # 유인 명단이 채워진다
	var d: Dictionary = st.support.get("doll_obj", {})
	if d.is_empty():
		return [-1.0, -1.0, -1.0]
	d.x = st.player.x + dist
	d.y = st.player.y
	w.x = float(d.x) + 10.0
	w.y = float(d.y)
	st.player.hit_prot = 0.0
	st.player.hp = st.player.hp_max
	st.damage_player(float(d.hp) + 5.0, "wolf_bite", w) # 인형 체력보다 큰 한 방
	var D: Dictionary = st.support.get("doll", {})
	var left: float = float((st.support.get("doll_obj", {}) as Dictionary).get("hp", 0.0))
	return [float(D.get("absorbed", 0)), left, float(D.get("broken", 0))]

func s6_doll() -> void:
	print("--- 6. 도깨비 인형 ---")

	# 실제 전투(st.step)에서 인형이 맞고 체력이 줄고 부서지는가
	var g := PGrowth.new_growth("sword")
	g.weapons = [{ "id": "sword", "level": 1, "mods": [] }, { "id": "doll", "level": 1, "mods": [] }]
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 7, "waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = []
	for i in 6:
		var e := st.spawn_enemy("wolf", st.player.x + 220.0 + float(i) * 10.0, st.player.y - 60.0 + float(i) * 24.0)
		e.hp = 1.0e6 # 인형이 일하는지만 본다(적을 죽이는 속도는 이 시험의 대상이 아니다)
	var min_hp := 1.0e9
	var saw_hp_drop := false
	var start_hp := -1.0
	for i in int(round(40.0 / STEP)):
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status != "running":
			st.status = "running"
		var d: Dictionary = st.support.get("doll_obj", {})
		if not d.is_empty():
			if start_hp < 0.0:
				start_hp = float(d.hp)
			min_hp = minf(min_hp, float(d.hp))
			if float(d.hp) < start_hp:
				saw_hp_drop = true
	var D: Dictionary = st.support.get("doll", {})
	var placed := float(D.get("placed", 0))
	var lured := float(D.get("lured", 0))
	var absorbed := float(D.get("absorbed", 0))
	var absorbed_dmg := float(D.get("absorbed_dmg", 0.0))
	var broken := float(D.get("broken", 0))
	measure("인형 40초 실전(늑대 6)", "설치 %.0f · 유인 %.0f · 대신 받음 %.0f회(%.1f 피해) · 부서짐 %.0f · 최저 체력 %.1f" % [placed, lured, absorbed, absorbed_dmg, broken, (min_hp if min_hp < 1.0e9 else -1.0)])
	ok("[명세] 인형이 **실제로 맞아 체력이 줄어든다**(이동 목표만 바뀌는 것이 아니다)",
		saw_hp_drop and absorbed >= 1.0,
		"대신 받음 %.0f회 · 받은 피해 %.1f · 체력 감소 관측=%s" % [absorbed, absorbed_dmg, str(saw_hp_drop)])
	measure("인형이 실전에서 부서지는가", "부서짐 %.0f회 — 40초 동안 수명(8초)이 먼저 끝나 파괴에 이르지 않았다" % broken)

	# **인형이 대신 받는 판정이 인형 위치가 아니라 '플레이어와 적의 거리'에 걸려 있는가.**
	# 같은 배치(적이 인형 바로 옆)에서 인형만 가깝게/멀게 두고 두 번 잰다
	var r_near := doll_case(60.0)
	var r_far := doll_case(200.0)
	measure("인형 가로채기와 거리", "인형이 플레이어에게서 60px일 때 대신 받음 %.0f회(인형 체력 %.1f) · 200px일 때 %.0f회(인형 체력 %.1f)" % [r_near[0], r_near[1], r_far[0], r_far[1]])
	ok("[명세] 인형은 **자기 옆에서 맞는 공격**을 대신 받는다 — 인형이 본체에서 멀어도 마찬가지여야 한다",
		r_far[0] >= 1.0,
		"가까울 때 %.0f회 / 멀 때 %.0f회 (멀 때 0이면 판정이 인형이 아니라 플레이어 거리를 본다)" % [r_near[0], r_far[0]])

	ok("[명세] 인형 체력이 다 깎이면 **실제로 부서진다**", r_near[2] >= 1.0,
		"가까운 배치에서 한 방 큰 피해 → 부서짐 %.0f회" % r_near[2])

	# 보스는 유인되지 않는다
	ok("[명세] 보스는 유인 저항 0이라 인형에 끌리지 않는다",
		not PSupport.tauntable({ "boss": true }) and PSupport.tauntable({}),
		"보스 tauntable=%s" % str(PSupport.tauntable({ "boss": true })))

# ================= 7. 쌍검 단일 대상 DPS =================
func theory_dps(wid: String, level: int, mods: Array, sec: float = 20.0) -> float:
	var g := PGrowth.new_growth(wid)
	g.weapons = [{ "id": wid, "level": level, "mods": mods.duplicate() }]
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 1, "waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = []
	var px: float = st.player.x
	var py: float = st.player.y
	var e := st.spawn_enemy("wolf", px + 45.0, py)
	e.hp = 1.0e9
	e.hp_max = 1.0e9
	var hp0: float = e.hp
	for i in int(round(sec / STEP)):
		# 표적과 플레이어를 고정해 전부 적중시킨다(이론 DPS)
		st.player.x = px
		st.player.y = py
		st.player.hp = st.player.hp_max
		st.player.dead = false
		e.x = px + 45.0
		e.y = py
		e.state = "approach"
		st.step({}, STEP)
		if st.status != "running":
			st.status = "running"
	return (hp0 - float(e.hp)) / sec

func s7_daggers_dps() -> void:
	print("--- 7. 쌍검 vs 검 단일 대상 DPS ---")
	var rows := [[1, []], [1, ["scar"]], [3, []], [5, []]]
	var worst := 99.0
	var worst_desc := ""
	for r in rows:
		var lv := int(r[0])
		var sw_mods: Array = r[1]
		var dg_mods: Array = ([] if sw_mods.is_empty() else ["bleed"])
		var sw := theory_dps("sword", lv, sw_mods)
		var dg := theory_dps("daggers", lv, dg_mods)
		var ratio := dg / maxf(sw, 0.0001)
		measure("이론 단일 대상 DPS Lv%d 개조%d" % [lv, sw_mods.size()],
			"검 %.2f · 쌍검 %.2f · 비율 %.3f" % [sw, dg, ratio])
		if ratio < worst:
			worst = ratio
			worst_desc = "Lv%d 개조%d (검 %.2f · 쌍검 %.2f)" % [lv, sw_mods.size(), sw, dg]
	ok("[명세] 사용자 확정: **같은 레벨·개조 투자**에서 쌍검 단일 대상 DPS ≥ 검 ×1.5",
		worst >= 1.5, "가장 나쁜 경우 비율 %.3f — %s" % [worst, worst_desc])

# ================= 8. 방패병 정면 70% =================
func s8_shieldbearer() -> void:
	print("--- 8. 방패병 ---")
	var T := PEnemiesNew.tuning("shieldbearer")
	ok("[명세] 자료의 정면 배율이 0.30(70% 감소)이다 — 0.15(85%)가 아니다",
		near(float(T.get("frontMult", -1.0)), 0.30, 0.001),
		"frontMult=%s (data/enemies.json 원본은 %s)" % [str(T.get("frontMult", "없음")), str(PCatalog.enemy("shieldbearer").get("frontMult", "없음"))])

	# 실제 주무기(검) 경로로 정면·측면을 때려 본다
	var st := lab([["sword", 5, []]])
	var sb := put(st, "shieldbearer", st.player.x + 60.0, st.player.y)
	sb.hp = 1.0e7
	sb.hp_max = 1.0e7
	sb.state = "approach"
	sb.face = PI # 플레이어(왼쪽)를 본다
	var hp_a: float = sb.hp
	PWeapons.fire(st, wep(st, "sword"), sb, false)
	var front_dmg: float = hp_a - float(sb.hp)
	sb.face = 0.0 # 등을 보인다
	var hp_b: float = sb.hp
	PWeapons.fire(st, wep(st, "sword"), sb, false)
	var back_dmg: float = hp_b - float(sb.hp)
	var cut := 1.0 - front_dmg / maxf(back_dmg, 0.0001)
	measure("검 실타격 방패병", "정면 %.1f · 후면 %.1f · 감소율 %.1f%%" % [front_dmg, back_dmg, cut * 100.0])
	ok("[명세] 실제 주무기 타격에서 정면 감소가 **70%**다(85%가 아니다)", near(cut, 0.70, 0.02),
		"감소율 %.1f%% (정면 %.1f / 후면 %.1f)" % [cut * 100.0, front_dmg, back_dmg])

	# 화면 표시와 판정이 맞는가(SHIELDBEARER.md §8-3이 남겨 둔 항목)
	var src_txt := FileAccess.get_file_as_string("res://scripts/game/render.gd")
	var draws_open_on_aim := src_txt.contains("stt == \"bash_aim\" or stt == \"bash\" or stt == \"recover\"")
	ok("[명세] 화면이 `bash_aim`(준비 중)에 방패를 **닫힌 것으로** 그린다(규칙과 일치)",
		not draws_open_on_aim, "render.gd가 bash_aim을 '열림'으로 그린다=%s" % str(draws_open_on_aim))

# ================= 9. 포자 =================
func s9_spore() -> void:
	print("--- 9. 포자 괴물 ---")
	var SC := PEnemies.spore_cfg()
	var sd := PCatalog.enemy("spore")
	var want: float = maxf(float(sd.cloudR) * float(SC.approach_frac), float(sd.r) + 14.0)

	# 실제 전투: 가만히 선 플레이어에게 포자 1기가 접근해 실제로 맞히는가
	var st := lab([])
	st.weapons = []
	st.player.hp_max = 100000.0
	st.player.hp = 100000.0
	var e := put(st, "spore", st.player.x + 320.0, st.player.y)
	var min_d := 1.0e9
	var hp0: float = st.player.hp
	for i in int(round(20.0 / STEP)):
		st.step({}, STEP)
		st.player.dead = false
		if st.status != "running":
			st.status = "running"
		if not bool(e.dead):
			min_d = minf(min_d, PGeom.dist(float(e.x), float(e.y), st.player.x, st.player.y))
	var taken: float = hp0 - float(st.player.hp)
	measure("포자 1기 20초(정지 플레이어)", "최소 접근 거리 %.1f (준비 거리 기대 ≈%.1f · 구름 반경 %.1f) · 받은 피해 %.1f" % [min_d, want, float(sd.cloudR), taken])
	ok("[명세] 포자가 **실제로 접근해서 맞힌다**(닿지 않는 거리에서 멈추지 않는다)",
		min_d <= float(sd.cloudR) and taken > 0.0,
		"최소 거리 %.1f ≤ 구름 반경 %.1f · 받은 피해 %.1f" % [min_d, float(sd.cloudR), taken])

	# 대조군: 수정 전 동작(PROPHECY_SPORE_LEGACY)에서는 정말로 안 맞았는지 — 지금 실행에서는 확인만
	measure("포자 접근 규칙", "준비 시작 거리 = max(cloudR×%.2f, 포자r+플레이어r) = %.1f · 구름 판정 한계 %.1f" % [float(SC.approach_frac), want, float(sd.cloudR) + 7.0])

	# 여러 포자의 접촉 피해가 하나로 뭉개지지 않는다
	var st2 := lab([])
	st2.weapons = []
	var pack := []
	for i in 3:
		pack.append(put(st2, "spore", st2.player.x + 8.0 + float(i) * 3.0, st2.player.y + float(i) * 3.0))
	st2.player.hit_prot = 0.0
	st2.player.hp = st2.player.hp_max
	var php := float(st2.player.hp)
	st2.step({}, STEP)
	var lost := php - float(st2.player.hp)
	var each := float(SC.contact_damage)
	ok("[명세] 여러 포자의 접촉 피해가 **하나로 뭉개지지 않는다**(3기 겹침 = 개체당 피해 × 3)",
		near(lost, each * 3.0, 0.6), "받은 피해 %.1f (개체당 %.1f × 3 = %.1f)" % [lost, each, each * 3.0])

# ================= 10. 저장 호환(옛 구조) =================
func s10_save_compat() -> void:
	print("--- 10. 저장 호환 ---")
	var new_g := PGrowth.new_growth("sword")
	var old_g := PGrowth.new_growth("sword")
	old_g.erase("structure") # 옛 저장에는 이 표시가 없다
	ok("[명세] 구조 표시가 없는 저장은 옛 구조(v1)로 읽는다",
		PGrowth.structure_of(old_g) == "v1" and PGrowth.structure_of(new_g) == "v2",
		"옛 %s / 새 %s" % [PGrowth.structure_of(old_g), PGrowth.structure_of(new_g)])
	var new_cap := PGrowth.level_cap(new_g, "blades")
	var old_cap := PGrowth.level_cap(old_g, "blades")
	var new_mod := PGrowth.mod_cap(new_g, "blades")
	var old_mod := PGrowth.mod_cap(old_g, "blades")
	ok("[명세] 옛 저장은 **옛 상한**(보조도 Lv5·개조 2)으로 끝까지 굴러간다",
		old_cap == 5 and old_mod == 2 and new_cap == 3 and new_mod == 1,
		"옛: Lv%d·개조%d / 새: Lv%d·개조%d" % [old_cap, old_mod, new_cap, new_mod])
