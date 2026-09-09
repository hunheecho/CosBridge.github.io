extends SceneTree
## 보조무기 B조(⑩ 역병 나비 · ⑪ 가시 갑각 · ⑫ 도깨비 인형) 규칙 검사(화면 없음).
## 실행: python tools/run_suites.py --suites support_b_tests
##      (직접: godot --headless --path prophecy_godot -s tests/support_b_tests.gd)
##
## 무엇을 보는가 — **피해만 보지 않는다. 역할별 지표로 단언한다.**
##  1. 역병: 전염이 실제로 일어나는가 · 세대가 2를 넘지 않는가 · 전염이 지속 시간을 최대치로 되돌리지 않는가 ·
##     파열이 같은 죽음으로 두 번 정산되지 않는가 · 독/전염/파열 피해가 출처별로 따로 남는가.
##  2. 갑각: 받은 피해 감소량 · 반격 횟수와 피해 · 원거리·장판에는 반격 없음 · 반사가 반사를 부르지 않음 ·
##     막힌 공격에는 반격 없음 · 다른 경감과의 계산 순서.
##  3. 인형: 대신 받아낸 공격 수 · 유인한 적 수 · 동시에 하나 · 보스 유인 불가 · 확정된 돌진 불변 ·
##     수명 종료와 예고 뒤 폭발.
##  4. 공통: 전투가 끝나거나 보조를 바꾸면 남은 인형이 사라진다.
##
## 수치는 전부 시험값이다(data/supports.json). 사람이 승인한 밸런스가 아니다.
## 마지막 절은 통과 판정이 아니라 **측정**이다(인형이 대신 받아낸 공격 수) — 결과는 docs/SUPPORT_B.md에 적는다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func near(a: float, b: float, tol: float = 0.05) -> bool:
	return absf(a - b) <= tol

# ---------- 시험실 ----------
## 적이 저절로 나오지 않고 장애물도 없는 빈 전장. 주무기는 없다(보조 규칙만 본다).
## ids = [[보조 id, 레벨, [개조...]], ...]
func lab(ids: Array, seed_v: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.weapons = []
	for row in ids:
		g.weapons.append({ "id": String(row[0]), "level": int(row[1]), "mods": (row[2] as Array).duplicate() })
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = [] # 가림 없는 자리에서 규칙만 본다(시야 판정은 별도 시험의 몫)
	return st

func put(st: CombatState, type: String, x: float, y: float) -> Dictionary:
	return st.spawn_enemy(type, x, y)

## 적을 움직이지 않고 보조 규칙만 진행한다(st.step을 쓰지 않으므로 기하가 그대로 유지된다).
## PWeapons.update의 지연 효과 처리와 같은 규칙을 쓴다
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

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

## 주무기 직접 타격으로 확실히 죽인다(전염 자격 판정이 죽음의 경로를 보게 한다)
func slay(st: CombatState, e: Dictionary) -> void:
	st.damage_enemy(e, 1.0e6, { "src": { "weapon_id": "sword", "direct": true }, "cause": "main_direct" })

func hurt(st: CombatState, amount: float, src: String, att) -> void:
	st.player.hit_prot = 0.0 # 공통 피격 보호를 지나 규칙 자체를 본다
	st.player.hp = st.player.hp_max
	st.damage_player(amount, src, att)

func _init() -> void:
	section_plague()
	section_thorns()
	section_doll()
	section_cleanup()
	section_doll_measure()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 1. ⑩ 역병 나비 ----------
func section_plague() -> void:
	print("--- 1. 역병 나비 ---")
	# 1-1. 나비가 붙으면 독이 걸리고 실제로 피해를 준다
	var st := lab([["plague", 1, []]])
	var p := st.player
	var a := put(st, "wolf", p.x + 150.0, p.y)
	var hp0: float = a.hp
	PSupport.fire(st, wep(st, "plague"), a, false)
	run_for(st, 1.2)
	var pg: Dictionary = a.get("plague", {})
	ok("나비가 붙으면 독이 걸린다(세대 0)", not pg.is_empty() and int(pg.gen) == 0, "남은 %.2f초" % float(pg.get("t", 0.0)))
	ok("독이 실제로 피해를 준다", a.hp < hp0, "%.1f → %.1f" % [hp0, a.hp])
	var P := PSupportB.plague_stat(st)
	ok("독 피해가 '독' 칸에 기록된다", float((P.dmg as Dictionary).poison) > 0.0, "%.1f" % float((P.dmg as Dictionary).poison))

	# 1-2. 전염: 감염된 적이 죽으면 주변으로 옮는다
	var st2 := lab([["plague", 1, []]])
	var b1 := put(st2, "wolf", 400.0, 300.0)
	var b2 := put(st2, "wolf", 470.0, 300.0)
	PSupport.fire(st2, wep(st2, "plague"), b1, false)
	run_for(st2, 1.0)
	slay(st2, b1)
	var pg2: Dictionary = b2.get("plague", {})
	ok("감염된 적이 죽으면 주변 적에게 독이 옮는다", not pg2.is_empty() and int(pg2.gen) == 1, str(pg2.get("gen", -1)))

	# 1-3. 전염은 지속 시간을 최대치로 되돌리지 않는다(남은 시간을 물려받는다)
	var st3 := lab([["plague", 1, []]])
	var c1 := put(st3, "wolf", 400.0, 300.0)
	var c2 := put(st3, "wolf", 470.0, 300.0)
	PSupport.fire(st3, wep(st3, "plague"), c1, false)
	run_for(st3, 1.6) # 나비가 날아가 붙을 때까지(거리/속도, 최대 1.5초)
	var full: float = float((c1.get("plague", {}) as Dictionary).max)
	run_for(st3, 3.0)
	var left: float = float((c1.get("plague", {}) as Dictionary).t)
	slay(st3, c1)
	var got: float = float((c2.get("plague", {}) as Dictionary).get("t", -1.0))
	ok("전염은 남은 시간을 물려받고 최대치로 초기화되지 않는다",
		got > 0.0 and got <= left + 0.01 and got < full - 0.5, "물려받음 %.2f · 원래 남은 %.2f · 최대 %.2f" % [got, left, full])

	# 1-4. 전염 세대가 상한을 넘지 않는다(무한 증식 금지).
	# 2026-09-09: 상한이 시험값 2 → 3으로 바뀌었다. 사슬 길이를 숫자로 박아 두면 값이 바뀔 때마다 이 검사가
	# 값을 따라다니게 되므로 **상한에서 줄 길이를 만든다** — 상한+2마리를 세우면 마지막 한 마리가 '더 안 옮는다'를 본다
	var gmax := PSupport.gen_max("plague_spread")
	var st4 := lab([["plague", 1, []]])
	var line := []
	for i in gmax + 2:
		line.append(put(st4, "wolf", 300.0 + 100.0 * float(i), 300.0))
	PSupport.fire(st4, wep(st4, "plague"), line[0], false)
	run_for(st4, 1.6)
	var gens := [_gen_of(line[0])]
	for i in gmax + 1:
		slay(st4, line[i])
		gens.append(_gen_of(line[i + 1]))
	var P4 := PSupportB.plague_stat(st4)
	var chain_ok := true
	for i in gmax + 1:
		if int(gens[i]) != i: # 0세대부터 상한 세대까지 한 칸씩 정상으로 이어져야 한다
			chain_ok = false
	ok("전염 세대가 상한(%d)을 넘지 않는다" % gmax,
		chain_ok and int(P4.max_gen) == gmax,
		"세대 기록 %s · 최대 %d" % [str(gens), int(P4.max_gen)])
	var last: Dictionary = line[gmax + 1]
	ok("세대 상한에 닿은 독은 더 이상 옮지 않는다",
		int(gens[gmax + 1]) < 0 and (last.get("plague", {}) as Dictionary).is_empty(), str(gens))

	# 1-5. 역병 파열: 같은 죽음으로 두 번 정산되지 않는다
	var st5 := lab([["plague", 1, ["burst"]]])
	var d1 := put(st5, "wolf", 400.0, 300.0)
	var d2 := put(st5, "wolf", 450.0, 300.0)
	PSupport.fire(st5, wep(st5, "plague"), d1, false)
	run_for(st5, 2.2) # 나비가 붙고 독이 최소 한 번 정산될 때까지
	var hp_before: float = d2.hp
	slay(st5, d1)
	var P5 := PSupportB.plague_stat(st5)
	var bursts1: int = int(P5.bursts)
	var hp_after: float = d2.hp
	PSupport.on_enemy_death(st5, d1, {}) # 같은 죽음을 한 번 더 정산하려고 해 본다
	ok("역병 파열이 주변에 즉시 피해를 준다", bursts1 == 1 and hp_after < hp_before, "파열 %d회 · %.1f → %.1f" % [bursts1, hp_before, hp_after])
	ok("같은 죽음으로 파열이 두 번 정산되지 않는다", int(P5.bursts) == 1 and near(d2.hp, hp_after, 0.001), "%d회" % int(P5.bursts))

	# 1-6. 독·전염·파열 피해가 출처별로 따로 기록된다
	run_for(st5, 2.0)
	var box: Dictionary = P5.dmg
	var rows_ok: bool = float(box.poison) > 0.0 and float(box.spread) > 0.0 and float(box.burst) > 0.0
	var m: Dictionary = st5.metrics.dmg
	var tags_ok: bool = m.has("support:plague:poison") and m.has("support:plague:spread") and m.has("support:plague:burst")
	ok("독·전염·파열 피해가 출처별로 따로 기록된다", rows_ok and tags_ok,
		"독 %.1f · 전염 %.1f · 파열 %.1f" % [float(box.poison), float(box.spread), float(box.burst)])

	# 1-7. 개조가 실제로 수치를 바꾼다(넓은 전염 · 깊은 맹독)
	var wide_r := _spread_radius_of(["wide"])
	var deep_r := _spread_radius_of(["deep"])
	var base_r := _spread_radius_of([])
	ok("넓은 전염은 전염 범위를 넓히고 깊은 맹독은 좁힌다", wide_r > base_r and deep_r < base_r,
		"기본 %.0f · 넓은 %.0f · 깊은 %.0f" % [base_r, wide_r, deep_r])
	var base_dps := _dps_of([])
	ok("깊은 맹독은 독 피해를 올리고 넓은 전염은 낮춘다", _dps_of(["deep"]) > base_dps and _dps_of(["wide"]) < base_dps,
		"기본 %.2f · 깊은 %.2f · 넓은 %.2f" % [base_dps, _dps_of(["deep"]), _dps_of(["wide"])])

func _gen_of(e: Dictionary) -> int:
	return int((e.get("plague", {}) as Dictionary).get("gen", -1))

func _spread_radius_of(mods: Array) -> float:
	var st := lab([["plague", 1, mods]])
	var e := put(st, "wolf", 400.0, 300.0)
	PSupport.fire(st, wep(st, "plague"), e, false)
	run_for(st, 1.0)
	return float((e.get("plague", {}) as Dictionary).get("spread_r", 0.0))

func _dps_of(mods: Array) -> float:
	var st := lab([["plague", 1, mods]])
	var e := put(st, "wolf", 400.0, 300.0)
	PSupport.fire(st, wep(st, "plague"), e, false)
	run_for(st, 1.0)
	return float((e.get("plague", {}) as Dictionary).get("dps", 0.0))

# ---------- 2. ⑪ 가시 갑각 ----------
func section_thorns() -> void:
	print("--- 2. 가시 갑각 ---")
	# 2-1. 근접 경감: 받은 피해가 실제로 줄어든다
	var plain := lab([])
	var pe := put(plain, "wolf", plain.player.x + 40.0, plain.player.y)
	hurt(plain, 20.0, "wolf:bite", pe)
	var taken_plain: float = plain.stats.damage_taken
	var st := lab([["thorns", 1, []]])
	var att := put(st, "wolf", st.player.x + 40.0, st.player.y)
	hurt(st, 20.0, "wolf:bite", att)
	var taken: float = st.stats.damage_taken
	var T := PSupportB.thorns_stat(st)
	var s := PSupport.stats_of(st, "thorns")
	ok("근접 피해가 실제로 줄어든다(경감 %.0f%%)" % (float(s.reduce) * 100.0),
		taken < taken_plain and near(taken, 20.0 * (1.0 - float(s.reduce)), 0.11),
		"갑각 %.1f vs 없음 %.1f · 줄인 양 %.1f" % [taken, taken_plain, float(T.reduced)])

	# 2-2. 반격 횟수·피해
	ok("근접 피격에 가시 반격이 나간다", int(T.reflects) == 1 and float((T.dmg as Dictionary).reflect) > 0.0,
		"반격 %d회 · 적중 %d · 피해 %.1f" % [int(T.reflects), int(T.reflect_hits), float((T.dmg as Dictionary).reflect)])

	# 2-3. 원거리·장판 피격에는 반격이 없다
	var st2 := lab([["thorns", 1, []]])
	var far := put(st2, "wolf", st2.player.x + 400.0, st2.player.y)
	hurt(st2, 10.0, "arrow", far)
	var T2 := PSupportB.thorns_stat(st2)
	var after_proj: int = int(T2.reflects)
	hurt(st2, 10.0, "zone", null)
	var after_zone: int = int(T2.reflects)
	ok("적 투사체에는 반격이 없다", after_proj == 0, "%d회" % after_proj)
	ok("적 장판에는 반격이 없다", after_zone == 0, "%d회" % after_zone)
	ok("원거리 피격은 근접 경감도 받지 않는다", int(T2.cuts) == 0, "경감 %d회" % int(T2.cuts))

	# 2-4. 반사가 반사를 부르지 않는다
	var st3 := lab([["thorns", 1, []]])
	var near_e := put(st3, "wolf", st3.player.x + 40.0, st3.player.y)
	PSupport.after_player_damage(st3, 9.0, "reflect", near_e)
	var T3 := PSupportB.thorns_stat(st3)
	ok("반사 피해가 또 반사를 부르지 않는다(순환 금지)", int(T3.reflects) == 0 and int(T3.skipped_path) == 1, "반격 %d회" % int(T3.reflects))

	# 2-5. 막힌 공격(피해 0)에는 반격이 없다
	PSupport.after_player_damage(st3, 0.0, "wolf:bite", near_e)
	ok("막힌 공격에는 반격이 없다", int(T3.reflects) == 0 and int(T3.skipped_blocked) == 1, "반격 %d회" % int(T3.reflects))

	# 2-6. 반격 대기시간: 대기 중에는 나가지 않고, 지나면 다시 나간다
	var st4 := lab([["thorns", 1, []]])
	var a4 := put(st4, "wolf", st4.player.x + 40.0, st4.player.y)
	hurt(st4, 10.0, "wolf:bite", a4)
	hurt(st4, 10.0, "wolf:bite", a4)
	var T4 := PSupportB.thorns_stat(st4)
	var during: int = int(T4.reflects)
	run_for(st4, float(PSupport.stats_of(st4, "thorns").cooldown) + 0.05)
	hurt(st4, 10.0, "wolf:bite", a4)
	ok("반격은 대기시간 동안 한 번만 나간다", during == 1 and int(T4.reflects) == 2,
		"대기 중 %d회 · 대기 뒤 %d회 (대기 %.2f초)" % [during, int(T4.reflects), float(PSupport.stats_of(st4, "thorns").cooldown)])

	# 2-7. 다른 경감과 겹칠 때 계산 순서: 보조 경감 → 강인함 → 체력
	var st5 := lab([["thorns", 1, []]])
	st5.build.toughness = 0.5
	var a5 := put(st5, "wolf", st5.player.x + 40.0, st5.player.y)
	hurt(st5, 20.0, "wolf:bite", a5)
	var s5 := PSupport.stats_of(st5, "thorns")
	var want: float = round(round(20.0 * (1.0 - float(s5.reduce)) * 10.0) / 10.0 * (1.0 - 0.5) * 10.0) / 10.0
	ok("갑각 경감이 강인함보다 **먼저** 계산된다(순서 고정)", near(float(st5.stats.damage_taken), want, 0.051),
		"실제 %.1f · 정해진 순서대로면 %.1f" % [float(st5.stats.damage_taken), want])

	# 2-8. 경감 상한: 이 보조 몫의 경감은 상한을 넘지 않는다
	var st6 := lab([["thorns", 3, []]])
	var s6 := PSupport.stats_of(st6, "thorns")
	s6.reduce = 0.95 # 상한 검사(저장·성장으로는 나올 수 없는 값을 일부러 넣는다)
	var a6 := put(st6, "wolf", st6.player.x + 40.0, st6.player.y)
	hurt(st6, 20.0, "wolf:bite", a6)
	ok("근접 경감은 상한(%.2f)을 넘지 않는다" % float(s6.reduceCap),
		near(float(st6.stats.damage_taken), 20.0 * (1.0 - float(s6.reduceCap)), 0.11),
		"%.1f (상한대로면 %.1f)" % [float(st6.stats.damage_taken), 20.0 * (1.0 - float(s6.reduceCap))])

	# 2-9. 개조: 집중 가시(좁고 강함) · 가시 폭발(넓고 약함) · 독가시(전염 자격 없음)
	var one_focus := _reflect_probe(["focused"])
	var one_base := _reflect_probe([])
	var one_burst := _reflect_probe(["burst"])
	ok("집중 가시는 한 대상 피해가 기본보다 크다", one_focus.dmg > one_base.dmg,
		"기본 %.1f · 집중 %.1f" % [one_base.dmg, one_focus.dmg])
	ok("가시 폭발은 뒤쪽 적까지 맞히고 단일 피해는 작다", int(one_burst.hits) > int(one_base.hits) and one_burst.dmg < one_base.dmg,
		"기본 적중 %d(%.1f) · 폭발 적중 %d(%.1f)" % [int(one_base.hits), one_base.dmg, int(one_burst.hits), one_burst.dmg])
	# v2는 반격 사거리(95) 밖이지만 v1의 전염 반경(110) 안이다 — 전염만 따로 본다
	var st7 := lab([["thorns", 1, ["venom"]], ["plague", 1, []]])
	var v1 := put(st7, "wolf", st7.player.x + 40.0, st7.player.y)
	var v2 := put(st7, "wolf", st7.player.x + 130.0, st7.player.y)
	hurt(st7, 10.0, "wolf:bite", v1)
	var vpg: Dictionary = v1.get("plague", {})
	ok("독가시는 반격 가시에 독을 묻힌다", not vpg.is_empty() and String(vpg.tag) == "support:thorns:venom", str(vpg.get("tag", "없음")))
	ok("독가시의 독은 전염 자격이 없다(spread=false)", not bool(vpg.get("spread", true)))
	slay(st7, v1)
	ok("독가시로 죽은 적은 주변에 독을 옮기지 않는다", (v2.get("plague", {}) as Dictionary).is_empty(),
		str((v2.get("plague", {}) as Dictionary).get("tag", "없음")))

## 앞쪽 적 하나 · 뒤쪽 적 하나를 두고 반격을 한 번 받는다. { dmg(앞쪽이 받은 피해), hits(맞은 수) }
func _reflect_probe(mods: Array) -> Dictionary:
	var st := lab([["thorns", 1, mods]])
	var p := st.player
	var front := put(st, "wolf", p.x + 40.0, p.y)
	var back := put(st, "wolf", p.x - 60.0, p.y)
	var f0: float = front.hp
	var b0: float = back.hp
	hurt(st, 10.0, "wolf:bite", front)
	var T := PSupportB.thorns_stat(st)
	return { "dmg": f0 - front.hp, "back": b0 - back.hp, "hits": int(T.reflect_hits) }

# ---------- 3. ⑫ 도깨비 인형 ----------
func section_doll() -> void:
	print("--- 3. 도깨비 인형 ---")
	# 3-1. 동시에 하나만
	var st := lab([["doll", 1, []]])
	var p := st.player
	var e1 := put(st, "wolf", p.x + 160.0, p.y)
	PSupport.fire(st, wep(st, "doll"), e1, false)
	PSupport.fire(st, wep(st, "doll"), e1, false)
	var D := PSupportB.doll_stat(st)
	ok("인형은 동시에 하나만 유지된다", int(D.placed) == 1 and not PSupportB.doll_of(st).is_empty(), "%d개 세움" % int(D.placed))

	# 3-2. 유인 대상 수 제한 · 보스는 끌리지 않는다
	var st2 := lab([["doll", 1, []]])
	var p2 := st2.player
	var mob := []
	for i in 6:
		mob.append(put(st2, "wolf", p2.x + 150.0 + 10.0 * float(i), p2.y + 10.0 * float(i)))
	var bz := put(st2, "wolf", p2.x + 150.0, p2.y - 40.0)
	bz.boss = true
	PSupport.fire(st2, wep(st2, "doll"), mob[0], false)
	tick(st2, STEP)
	var d2 := PSupportB.doll_of(st2)
	var s2 := PSupport.stats_of(st2, "doll")
	ok("유인 대상 수가 상한(%d)을 넘지 않는다" % int(s2.maxLure), (d2.lured as Dictionary).size() <= int(s2.maxLure),
		"%d마리" % (d2.lured as Dictionary).size())
	ok("보스는 인형에 유인되지 않는다", not (d2.lured as Dictionary).has(bz.id) and PSupport.lure_target(st2, bz).is_empty())
	ok("유인된 적은 인형을 노린다(강제 이동이 아니라 대상만 바뀐다)",
		not PSupport.lure_target(st2, mob[0]).is_empty() and (d2.lured as Dictionary).has(mob[0].id))

	# 3-3. 이미 확정된 돌진 방향은 인형이 바꾸지 않는다
	mob[0].state = "dash"
	ok("이미 확정된 돌진 중인 적은 인형으로 방향이 바뀌지 않는다", PSupport.lure_target(st2, mob[0]).is_empty(), "상태 dash")
	mob[0].state = "approach"
	ok("확정이 풀리면 다시 인형을 노린다", not PSupport.lure_target(st2, mob[0]).is_empty())

	# 3-4. 정예는 일반보다 짧게 붙잡힌다(등급 유인 저항)
	var st3 := lab([["doll", 1, []]])
	var p3 := st3.player
	var norm := put(st3, "wolf", p3.x + 150.0, p3.y)
	var elite := put(st3, "wolf", p3.x + 150.0, p3.y + 30.0)
	elite.elite = true
	PSupport.fire(st3, wep(st3, "doll"), norm, false)
	tick(st3, STEP)
	var d3 := PSupportB.doll_of(st3)
	var lured3: Dictionary = d3.lured
	ok("정예는 일반보다 짧게 붙잡힌다(유인 저항 %.2f)" % PSupport.resist_mult("taunt", elite),
		lured3.has(norm.id) and lured3.has(elite.id) and float(lured3[elite.id]) < float(lured3[norm.id]),
		"일반 %.2f초 · 정예 %.2f초" % [float(lured3.get(norm.id, 0.0)), float(lured3.get(elite.id, 0.0))])

	# 3-5. 대신 받아낸 공격: 인형 옆에서 때리는 적의 근접 공격을 인형이 받는다
	var st4 := lab([["doll", 1, []]])
	var p4 := st4.player
	var a4 := put(st4, "wolf", p4.x + 60.0, p4.y)
	PSupport.fire(st4, wep(st4, "doll"), a4, false)
	var d4 := PSupportB.doll_of(st4)
	d4.x = p4.x + 62.0 # 인형이 그 적 옆에 서 있는 상황을 기하로 고정한다
	d4.y = p4.y
	tick(st4, STEP)
	var hp4: float = st4.player.hp
	hurt(st4, 12.0, "wolf:bite", a4)
	var D4 := PSupportB.doll_stat(st4)
	ok("인형 옆의 적이 때린 근접 공격을 인형이 대신 받는다",
		int(D4.absorbed) == 1 and near(float(st4.player.hp), hp4, 0.001) and float(d4.hp) < float(d4.hp_max),
		"대신 받음 %d회 %.1f · 인형 체력 %.1f/%.1f" % [int(D4.absorbed), float(D4.absorbed_dmg), float(d4.hp), float(d4.hp_max)])
	var T4 := PSupportB.thorns_stat(st4)
	ok("인형이 막은 공격에는 갑각 경감·가시 반격이 걸리지 않는다(차단이 먼저)",
		int(T4.cuts) == 0 and int(T4.reflects) == 0)

	# 3-6. 인형이 부서지면 사라진다
	var st5 := lab([["doll", 1, []]])
	var p5 := st5.player
	var a5 := put(st5, "wolf", p5.x + 60.0, p5.y)
	PSupport.fire(st5, wep(st5, "doll"), a5, false)
	var d5 := PSupportB.doll_of(st5)
	d5.x = p5.x + 62.0
	d5.y = p5.y
	tick(st5, STEP)
	for i in 20:
		hurt(st5, 20.0, "wolf:bite", a5)
	var D5 := PSupportB.doll_stat(st5)
	ok("인형은 체력이 다하면 부서져 사라진다", PSupportB.doll_of(st5).is_empty() and int(D5.broken) == 1,
		"대신 받은 %d회 · 부서짐 %d" % [int(D5.absorbed), int(D5.broken)])

	# 3-7. 수명이 다하면 사라진다 · 폭죽 인형은 예고 뒤에 터진다
	var st6 := lab([["doll", 1, ["firework"]]])
	var p6 := st6.player
	var a6 := put(st6, "wolf", p6.x + 120.0, p6.y)
	PSupport.fire(st6, wep(st6, "doll"), a6, false)
	var s6 := PSupport.stats_of(st6, "doll")
	var d6 := PSupportB.doll_of(st6)
	a6.x = float(d6.x) + 20.0
	a6.y = float(d6.y)
	run_for(st6, float(s6.dur) + 0.02) # 수명이 다하는 순간까지만
	var gone: bool = PSupportB.doll_of(st6).is_empty()
	var hp6: float = a6.hp
	var D6 := PSupportB.doll_stat(st6)
	var blast_yet: int = int(D6.blasts)
	run_for(st6, float(s6.blastWarn) + 0.02)
	ok("인형은 수명이 다하면 사라진다", gone and int(D6.expired) == 1)
	ok("폭죽 인형은 예고 뒤에 터진다(예고 중에는 피해 없음)",
		blast_yet == 0 and int(D6.blasts) == 1 and float((D6.dmg as Dictionary).blast) > 0.0,
		"예고 %.2f초 · 예고 중 폭발 %d회 · 예고 뒤 %d회 · 폭발 피해 %.1f" % [float(s6.blastWarn), blast_yet, int(D6.blasts), float((D6.dmg as Dictionary).blast)])

	# 3-8. 질긴 인형 · 도망치는 인형
	var st7 := lab([["doll", 1, ["tough"]]])
	PSupport.fire(st7, wep(st7, "doll"), put(st7, "wolf", st7.player.x + 150.0, st7.player.y), false)
	var d7 := PSupportB.doll_of(st7)
	var st8 := lab([["doll", 1, []]])
	PSupport.fire(st8, wep(st8, "doll"), put(st8, "wolf", st8.player.x + 150.0, st8.player.y), false)
	var d8 := PSupportB.doll_of(st8)
	ok("질긴 인형은 체력·지속이 더 길다", float(d7.hp_max) > float(d8.hp_max) and float(d7.ttl) > float(d8.ttl),
		"질긴 %.0f체력/%.1f초 · 기본 %.0f체력/%.1f초" % [float(d7.hp_max), float(d7.ttl), float(d8.hp_max), float(d8.ttl)])
	var st9 := lab([["doll", 1, ["fleeing"]]])
	var p9 := st9.player
	PSupport.fire(st9, wep(st9, "doll"), put(st9, "wolf", p9.x + 200.0, p9.y), false)
	var d9 := PSupportB.doll_of(st9)
	var far0 := PGeom.dist(p9.x, p9.y, float(d9.x), float(d9.y))
	run_for(st9, 1.0)
	var far1 := PGeom.dist(p9.x, p9.y, float(d9.x), float(d9.y))
	ok("도망치는 인형은 플레이어에게서 멀어진다", far1 > far0 + 10.0, "%.0f → %.0f" % [far0, far1])

# ---------- 4. 공통: 남은 인형·독 정리 ----------
func section_cleanup() -> void:
	print("--- 4. 남은 것 정리 ---")
	var st := lab([["doll", 1, []]])
	PSupport.fire(st, wep(st, "doll"), put(st, "wolf", st.player.x + 150.0, st.player.y), false)
	ok("인형이 세워져 있다", not PSupportB.doll_of(st).is_empty())
	st.status = "won"
	st.mark_duel_done_for_test() # 결투가 예정된 편성이면 그것도 이긴 것으로 본다(승리 정산 규칙과 앞뒤를 맞춘다)
	ok("전투가 끝나면 남은 인형이 사라진다", PSupportB.doll_of(st).is_empty())

	var st2 := lab([["doll", 1, []]])
	PSupport.fire(st2, wep(st2, "doll"), put(st2, "wolf", st2.player.x + 150.0, st2.player.y), false)
	st2.weapons = [] # 보조 교체(성장·재구성)
	tick(st2, STEP)
	ok("보조를 바꾸면 남은 인형이 사라진다(공짜 중복 효과 금지)",
		PSupportB.doll_of(st2).is_empty() and not st2.support.has("doll_obj"))

	# 보조가 사라지면 새 전염도 일어나지 않는다(이미 걸린 독은 남은 시간까지만)
	var st3 := lab([["plague", 1, []]])
	var e1 := put(st3, "wolf", 400.0, 300.0)
	var e2 := put(st3, "wolf", 450.0, 300.0)
	PSupport.fire(st3, wep(st3, "plague"), e1, false)
	run_for(st3, 1.0)
	st3.weapons = []
	slay(st3, e1)
	ok("보조가 사라진 뒤에는 전염이 일어나지 않는다", (e2.get("plague", {}) as Dictionary).is_empty())

	# 새 전투는 st.support가 비어서 시작한다(옛 인형이 넘어오지 않는다)
	var st4 := lab([["doll", 1, []]])
	ok("새 전투는 남은 보조 상태 없이 시작한다", st4.support.is_empty() or not st4.support.has("doll_obj"))

# ---------- 5. 측정: 인형이 대신 받아낸 공격(통과 판정 아님) ----------
## 같은 시드·같은 편성으로 (가) 인형 없음 (나) 인형 있음(지금 그대로) (다) 인형 있음 + 유인 훅 흉내
## 를 돌려 **대신 받아낸 공격 수·유인한 적 수·본체가 받은 피해**를 비교한다.
##
## 2026-09-09 통합에서 유인 훅이 실제로 붙었다(CombatState.approach가 목표를 인형 자리로 바꾼다).
## 그래서 (나)가 이미 유인을 포함한다. (다)는 시험 안에서 좌표를 한 번 더 밀어 주는 흉내라
## 이제 (나)와 거의 같아야 정상이고, 어느 쪽이 더 크든 문제가 아니다.
## 남겨 두는 이유는 훅이 **끊겼을 때** 이 자리에서 바로 드러나게 하려는 것이다.
func section_doll_measure() -> void:
	print("--- 5. 인형 측정(통과 판정 아님) ---")
	var a := _fight_once([], false)
	var b := _fight_once(["doll"], false)
	var c := _fight_once(["doll"], true)
	print("DOLL_MEASURE %s" % JSON.stringify({ "없음": a, "인형(지금)": b, "인형(유인 훅 흉내)": c }))
	ok("측정이 실제로 돌았다(전투가 진행되고 기록이 남았다)", int(a.steps) > 0 and int(b.steps) > 0 and int(c.steps) > 0,
		"단계 %d/%d/%d" % [int(a.steps), int(b.steps), int(c.steps)])
	ok("인형이 실제로 적을 유인한다(유인한 적 수 > 0)", int(b.lured) > 0, "유인 %d마리 · 대신 받음 %d회" % [int(b.lured), int(b.absorbed)])
	ok("유인 훅이 실제로 붙어 있다(인형을 놓으면 본체가 받는 피해가 줄어든다)",
		float(b.taken) < float(a.taken) and int(b.absorbed) > 0,
		"없음 %.0f(%d대) · 인형 %.0f(%d대) · 대신 받음 %d회" % [float(a.taken), int(a.taken_hits), float(b.taken), int(b.taken_hits), int(b.absorbed)])
	ok("훅 흉내를 더해도 결과가 크게 달라지지 않는다(훅이 이미 붙었다는 뜻)",
		absi(int(c.absorbed) - int(b.absorbed)) <= 2, "지금 %d회 · 훅 흉내 %d회" % [int(b.absorbed), int(c.absorbed)])

func _fight_once(ids: Array, emulate_hook: bool) -> Dictionary:
	var g := PGrowth.new_growth("sword")
	for id in ids:
		g.weapons.append({ "id": String(id), "level": 1, "mods": [] })
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var units := []
	for i in 20:
		units.append("wolf")
	var st := CombatState.new({ "build": b, "seed": 7, "arena": "clearing", "region_id": "lab", "fixed_build": true,
		"formation": { "units": units, "alive_cap": 6, "group": 2, "interval": 1.2, "type_caps": {} },
		"xp_map": { "wolf": 0.0 }, "objective": "clear" })
	# 세 조건 모두 같은 시드·같은 편성·같은 정책이다(차이는 인형과 유인 훅뿐)
	var bot := PBot.new("balanced")
	var n := 0
	var max_n := int(round(90.0 / STEP))
	while st.status == "running" and n < max_n:
		# 없는 훅을 **시험에서만** 흉내 낸다: 유인된 적의 접근 대상을 플레이어에서 인형으로 통째로 바꾼다.
		# (단계 전 자리를 기억했다가 단계 뒤 되돌리고 인형 쪽으로 다시 걷게 한다 — 두 번 걷지 않게)
		var saved := {}
		if emulate_hook:
			for e in st.alive_enemies():
				var tgt := PSupport.lure_target(st, e)
				if not tgt.is_empty():
					saved[e.id] = [float(e.x), float(e.y), float(tgt.x), float(tgt.y)]
		st.step(bot.step_input(st), STEP)
		if not saved.is_empty():
			for e in st.alive_enemies():
				if not saved.has(e.id) or st.is_committed(e):
					continue
				var row: Array = saved[e.id]
				e.x = row[0]
				e.y = row[1]
				st.approach(e, float(row[2]), float(row[3]), float(e.def.speed), STEP)
		n += 1
	var D := PSupportB.doll_stat(st)
	return { "steps": n, "status": String(st.status), "kills": int(st.stats.kills),
		"taken": snapped(float(st.stats.damage_taken), 0.1), "taken_hits": int(st.metrics.taken_hits.get("wolf:bite", 0)) + int(st.metrics.taken_hits.get("wolf:dash", 0)),
		"attacks": int(st.stats.attacks), "hits": int(st.stats.hits),
		"placed": int(D.placed), "lured": int(D.lured), "absorbed": int(D.absorbed),
		"absorbed_dmg": snapped(float(D.absorbed_dmg), 0.1), "broken": int(D.broken), "expired": int(D.expired) }
