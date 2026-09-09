extends SceneTree
## 회전 칼날(§5)·불씨 정령(§6) 시험(화면 없음):
##   python tools/run_suites.py --suites blades_ember_tests
##
## 무엇을 못 박는가
##  ① 회전 칼날: 기본 칼날 3개 · 개조 '네 번째 칼날'이 3 → 4 · 레벨이나 개조가 개수를 **다시 더하지 않는다** ·
##     칼날 간격과 개체별 적중 제한 · **개수 말고는 아무 수치도 바뀌지 않았다**.
##  ② 불씨 정령: 착탄 자리를 **발사 순간에 확정**하고 비행 중 추적하지 않는다 · 비행 속도는 기준값의 40% ·
##     느려진 만큼 던지는 연출이 착탄 전에 사라지지 않는다 · 피해·범위·지속·주기는 그대로 ·
##     고정 / 이동 / 둔화 표적의 적중률을 **전후로 나눠 잰다**.
##
## 수치는 전부 시험값이다(data/supports.json). 사람이 승인한 밸런스가 아니다.
## 마지막의 EMBER_HIT_MEASURE 줄은 통과 판정이 아니라 **측정**이다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 시험실 ----------
## 장애물 없는 빈 전장에 그 보조무기만 든 전투(적은 저절로 나오지 않는다)
func lab(weapon_id: String, level: int = 1, mods: Array = [], seed_v: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.weapons = [{ "id": weapon_id, "level": level, "mods": mods.duplicate() }]
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "arena": "forest", "waves": [],
		"region_id": "lab", "obstacles": [], "objective": "clear" })
	st.spawn_hold = true
	st.player.x = 480.0
	st.player.y = 300.0
	return st

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

func put(st: CombatState, x: float, y: float, type_id: String = "wolf") -> Dictionary:
	var e := st.spawn_enemy(type_id, x, y)
	e.hp = 999999.0
	e.hp_max = 999999.0
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

func dmg_of(st: CombatState, weapon_id: String) -> float:
	var total := 0.0
	for k in (st.metrics.dmg as Dictionary):
		if String(k).begins_with("weapon:" + weapon_id) or String(k).ends_with("@" + weapon_id):
			total += float(st.metrics.dmg[k])
	return total

## 자료의 값을 설명에 적히는 모양으로(소수점 뒤의 0은 뗀다)
func numtext(v: float) -> String:
	var s := "%.2f" % v
	if s.find(".") >= 0:
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s

func says(text: String, piece: String) -> bool:
	return text.find(piece) >= 0

func gloss_body(weapon_id: String) -> String:
	return String((PCatalog.glossary().get("w:" + weapon_id, {}) as Dictionary).get("body", ""))

func mod_name(weapon_id: String, mod_id: String) -> String:
	return String(((PCatalog.weapon(weapon_id).get("mods", {}) as Dictionary).get(mod_id, {}) as Dictionary).get("name", ""))

func mod_desc(weapon_id: String, mod_id: String) -> String:
	return String(((PCatalog.weapon(weapon_id).get("mods", {}) as Dictionary).get(mod_id, {}) as Dictionary).get("desc", ""))

# ---------- 불씨: 한 번 던져 보고 결과를 돌려준다 ----------
## 표적을 dist만큼 떨어뜨려 놓고 속도 speed로 옆으로 걷게 하면서 불씨를 한 번 던진다.
## 돌려주는 값: 비행 시간 · 던지기 연출 수명 · 착탄 좌표 · 표적이 실제로 입은 피해
func ember_throw(dist: float, speed: float, seed_v: int) -> Dictionary:
	var st := lab("ember", 1, [], seed_v)
	st.player.attack_timer = 1.0e8 # 자동 발사를 끈다(원할 때만 한 번 던진다). 지연 효과·장판은 그대로 흐른다
	var ex: float = st.player.x + dist
	var ey: float = st.player.y
	var e := put(st, ex, ey)
	var w := wep(st, "ember")
	PWeapons.fire(st, w, e, false)
	var throw_fx := {}
	for f in st.effects:
		if String(f.kind) == "emberthrow":
			throw_fx = f
	var land := [float(throw_fx.get("x", 0.0)), float(throw_fx.get("y", 0.0))]
	var flight: float = float(throw_fx.get("flight", -1.0))
	var fx_alive_at_landing := false
	var n := 0
	var land_n := int(round(flight / STEP))
	while n < 480: # 4초: 비행 + 불길 지속 2.5초
		st.step({}, STEP)
		n += 1
		e.x = ex + speed * float(n) * STEP # 옆이 아니라 **쏜 방향에서 더 멀어지는 쪽**으로 걷는다
		e.y = ey
		e.vx = 0.0
		e.vy = 0.0
		if n == land_n - 1: # 착탄 직전 단계에도 던지는 불씨가 화면에 남아 있어야 한다
			for f in st.effects:
				if String(f.kind) == "emberthrow":
					fx_alive_at_landing = true
	return { "flight": flight, "fx_ttl": float(throw_fx.get("ttl", -1.0)), "land": land,
		"fx_alive_at_landing": fx_alive_at_landing, "dmg": dmg_of(st, "ember"),
		"aim": [ex, ey] }

## 비행 속도 배율(data/supports.json tuning.ember.flight.speedMult)을 잠깐 바꿔 놓는다.
## **시험에서만** 쓴다 — 너프 전후를 같은 코드로 재기 위해서다. 잰 뒤 반드시 되돌린다.
func set_speed_mult(v: float) -> float:
	var fl: Dictionary = PCatalog.supports().tuning.ember.flight
	var old: float = float(fl.speedMult)
	fl.speedMult = v
	return old

func _init() -> void:
	# ==================================================================
	# 1. 회전 칼날(§5) — 기본 3 · 개조 4 · 중복 가산 없음
	# ==================================================================
	var bd: Dictionary = PCatalog.weapon("blades").base
	ok("§5 회전 칼날의 기본 칼날 수가 3이다(자료 값)", int(bd.count) == 3, "count %d" % int(bd.count))
	var blade_rows := []
	var count_ok := true
	for lv in [1, 2, 3]:
		for mods in [[], ["dual"]]:
			var st := lab("blades", int(lv), mods)
			var e := put(st, st.player.x + 400.0, st.player.y) # 멀리 둬서 접촉 피해가 끼어들지 않게
			var _unused := e
			st.step({}, STEP)
			var n_blades: int = (wep(st, "blades").blade_pos as Array).size()
			var want: int = 3 + (1 if (mods as Array).has("dual") else 0)
			blade_rows.append("Lv%d%s %d" % [lv, ("+개조" if (mods as Array).has("dual") else ""), n_blades])
			if n_blades != want:
				count_ok = false
	ok("§5 실제로 도는 칼날 수: 기본 3 · 개조 '네 번째 칼날' 4 · 레벨(1~3)이 개수를 다시 더하지 않는다",
		count_ok, " · ".join(blade_rows))

	# 칼날 간격: 3개면 120°, 4개면 90°(같은 궤도에 고르게)
	var gap_ok := true
	var gap_rows := []
	for mods2 in [[], ["dual"]]:
		var st2 := lab("blades", 1, mods2)
		st2.step({}, STEP)
		var bp: Array = wep(st2, "blades").blade_pos
		var want_gap: float = TAU / float(bp.size())
		for i in bp.size():
			var a0: float = float((bp[i] as Dictionary).a)
			var a1: float = float((bp[(i + 1) % bp.size()] as Dictionary).a)
			if absf(absf(PGeom.ang_diff(a0, a1)) - minf(want_gap, TAU - want_gap)) > 1e-6:
				gap_ok = false
		gap_rows.append("%d개 → %.0f°" % [bp.size(), want_gap * 180.0 / PI])
	ok("§5 칼날은 같은 궤도에 고르게 놓인다(3개 120° · 4개 90°)", gap_ok, " · ".join(gap_rows))

	# 개체별 적중 제한(hitGap 0.35초): 같은 적을 그 안에 두 번 베지 않는다
	var st_gap := lab("blades", 1)
	var ge := put(st_gap, st_gap.player.x + float(bd.radius) * 0.7, st_gap.player.y)
	var hits_1s := 0
	for i in 120:
		st_gap.step({}, STEP)
		ge.x = st_gap.player.x + float(bd.radius) * 0.7
		ge.y = st_gap.player.y
		ge.vx = 0.0
		ge.vy = 0.0
	hits_1s = int(st_gap.metrics.hits.get("blades", 0))
	var max_hits: int = int(ceil(1.0 / float(bd.hitGap)))
	ok("§5 개체별 적중 제한이 지켜진다: 칼날이 3개여도 같은 적은 1초에 최대 %d번만 맞는다(hitGap %.2f초)" % [max_hits, float(bd.hitGap)],
		hits_1s <= max_hits and hits_1s >= 1, "1초 동안 %d번" % hits_1s)

	# 개수 말고는 아무 수치도 바뀌지 않았다
	ok("§5 개수 외 수치는 그대로다(피해 %.0f · 주기 %.2f · 반지름 %.0f · 회전 %.1f · 적중 제한 %.2f · 밀어내기 %.0f)" % [
			float(bd.damage), float(bd.interval), float(bd.radius), float(bd.angular), float(bd.hitGap), float(bd.knock)],
		is_equal_approx(float(bd.damage), 10.0) and is_equal_approx(float(bd.interval), 0.35)
			and is_equal_approx(float(bd.radius), 78.0) and is_equal_approx(float(bd.angular), 3.2)
			and is_equal_approx(float(bd.hitGap), 0.35) and is_equal_approx(float(bd.knock), 20.0))
	# 레벨 강화표에 개수가 없다(레벨이 개수를 몰래 더하지 못한다)
	ok("§5 레벨 강화표(levelScale.blades)에 개수 항목이 없다 — 기본 3을 레벨이 다시 더할 자리가 없다",
		not (PCatalog.level_scale().get("blades", {}) as Dictionary).has("count"),
		str((PCatalog.level_scale().get("blades", {}) as Dictionary).keys()))

	# 이름·설명이 새 기본값과 맞는가
	ok("§5 칼날 추가 개조의 이름이 '네 번째 칼날'이다(옛 이름 '세 번째 칼날'은 기본 3과 맞지 않는다)",
		mod_name("blades", "dual") == "네 번째 칼날", "이름 '%s'" % mod_name("blades", "dual"))
	ok("§5 그 개조 설명이 3개 → 4개를 적는다", says(mod_desc("blades", "dual"), "3개 → 4개"), mod_desc("blades", "dual"))
	ok("§5 용어 사전이 칼날 %d개를 적고 옛 이름을 쓰지 않는다" % int(bd.count),
		says(gloss_body("blades"), "칼날 " + numtext(float(bd.count)) + "개")
			and says(gloss_body("blades"), "네 번째 칼날")
			and not says(gloss_body("blades"), "세 번째 칼날"), gloss_body("blades"))

	# ==================================================================
	# 2. 불씨 정령(§6) — 착탄 확정 · 느린 비행 · 추적 없음
	# ==================================================================
	var eb: Dictionary = PCatalog.weapon("ember").base
	var fl: Dictionary = PCatalog.support_tuning("ember").get("flight", {})
	var base_speed: float = float(eb.range) / float(fl.baseSec)
	var new_speed: float = base_speed * float(fl.speedMult)
	ok("§6 비행 속도가 기준값의 40%%다(기준 %.1f/초 = 사거리 %.0f ÷ %.2f초 → 지금 %.1f/초)" % [base_speed, float(eb.range), float(fl.baseSec), new_speed],
		is_equal_approx(float(fl.speedMult), 0.4) and is_equal_approx(float(fl.baseSec), 0.3))
	ok("§6 피해·장판 범위·지속시간·공격 주기는 그대로다(피해 %.0f · 반지름 %.0f · 지속 %.1f초 · 주기 %.1f초)" % [
			float(eb.damage), float(eb.radius), float(eb.ttl), float(eb.interval)],
		is_equal_approx(float(eb.damage), 5.0) and is_equal_approx(float(eb.radius), 34.0)
			and is_equal_approx(float(eb.ttl), 2.5) and is_equal_approx(float(eb.interval), 1.6)
			and is_equal_approx(float(eb.tick), 0.4))

	# 비행 시간이 거리에 비례하고, 던지기 연출이 착탄 전에 사라지지 않는다
	var flight_rows := []
	var flight_ok := true
	for dist in [60.0, 150.0, 260.0]:
		var r := ember_throw(float(dist), 0.0, 3)
		var want_flight: float = PGeom.dist(480.0, 300.0, float(r.land[0]), float(r.land[1])) / new_speed
		flight_rows.append("거리 %.0f → %.3f초" % [dist, r.flight])
		if absf(float(r.flight) - want_flight) > 1e-6 or absf(float(r.fx_ttl) - float(r.flight)) > 1e-9 or not bool(r.fx_alive_at_landing):
			flight_ok = false
	ok("§6 비행 시간 = 거리 ÷ 속도이고, 던지는 연출의 수명이 비행 시간과 같아 **착탄 전에 사라지지 않는다**",
		flight_ok, " · ".join(flight_rows) + " (사거리 끝 0.75초 = 예전 0.3초의 2.5배)")

	# 착탄 자리는 발사 순간에 확정된다: 던진 뒤 표적이 걸어 나가도 불길은 그 자리에 생긴다
	var st_fix := lab("ember", 1, [], 5)
	st_fix.player.attack_timer = 1.0e8
	var fx0: float = st_fix.player.x + 200.0
	var fy0: float = st_fix.player.y
	var fe := put(st_fix, fx0, fy0)
	PWeapons.fire(st_fix, wep(st_fix, "ember"), fe, false)
	var warn_land := []
	for f in st_fix.effects:
		if String(f.kind) == "emberthrow":
			warn_land = [float(f.x), float(f.y)]
	for i in 120:
		st_fix.step({}, STEP)
		fe.x = fx0 + 300.0 # 던진 직후 멀리 이동
		fe.y = fy0
		fe.vx = 0.0
		fe.vy = 0.0
	var zone_pos := []
	for z in st_fix.zones:
		if String(z.type) == "fire":
			zone_pos = [float(z.x), float(z.y)]
	ok("§6 착탄 자리는 던지는 순간에 확정된다: 표적이 300 걸어 나가도 불길은 던질 때 겨눈 자리에 생긴다",
		zone_pos.size() == 2 and PGeom.dist(float(zone_pos[0]), float(zone_pos[1]), float(warn_land[0]), float(warn_land[1])) < 1.0
			and PGeom.dist(float(zone_pos[0]), float(zone_pos[1]), float(fe.x), float(fe.y)) > 200.0,
		"불길 (%.0f, %.0f) · 예고 (%.0f, %.0f) · 표적 (%.0f, %.0f)" % [zone_pos[0], zone_pos[1], warn_land[0], warn_land[1], fe.x, fe.y])
	ok("§6 걸어 나간 표적은 아무 피해도 입지 않는다 — 끝까지 쫓아가 맞히지 않는다",
		is_zero_approx(dmg_of(st_fix, "ember")), "%.2f" % dmg_of(st_fix, "ember"))

	# 장애물 규칙을 우회하지 않는다: 바위 안으로는 불길이 생기지 않고 가까운 성한 자리로 밀린다
	var rock := { "id": "rockA", "type": "rock", "x": 700.0, "y": 300.0, "r": 42.0 }
	var st_ob := lab("ember", 1, [], 9)
	st_ob.obstacles = [rock]
	st_ob.player.attack_timer = 1.0e8
	var oe := put(st_ob, 700.0, 300.0) # 바위 한가운데를 겨눈다
	PWeapons.fire(st_ob, wep(st_ob, "ember"), oe, false)
	for i in 180:
		st_ob.step({}, STEP)
		oe.x = 700.0
		oe.y = 300.0
		oe.vx = 0.0
		oe.vy = 0.0
	var ob_zone := []
	for z in st_ob.zones:
		if String(z.type) == "fire":
			ob_zone = [float(z.x), float(z.y)]
	ok("§6 장애물 규칙은 그대로다: 바위 한가운데를 겨눠도 불길이 바위 안에 생기지 않는다(가까운 성한 자리로 밀린다)",
		ob_zone.is_empty() or PGeom.dist(float(ob_zone[0]), float(ob_zone[1]), float(rock.x), float(rock.y)) >= float(rock.r) - 0.01,
		("불길 없음" if ob_zone.is_empty() else "불길 (%.0f, %.0f) · 바위 중심에서 %.1f (반지름 %.0f)" % [ob_zone[0], ob_zone[1], PGeom.dist(float(ob_zone[0]), float(ob_zone[1]), float(rock.x), float(rock.y)), float(rock.r)]))

	# ---------- 고정 / 이동 / 둔화 표적의 적중률(전후) ----------
	# '전'은 예전의 '거리와 무관하게 늘 0.3초 뒤 착탄'을 그대로 재현한다.
	#  같은 거리 d에서 그렇게 되려면 speedMult = d / 사거리 로 두면 된다(비행 = d ÷ (사거리/0.3 × d/사거리) = 0.3초).
	var wolf_speed: float = float(PCatalog.enemies().wolf.speed)
	var cases := [["고정", 0.0], ["이동(늑대 속도 %.0f)" % wolf_speed, wolf_speed], ["둔화(속도 40%)", wolf_speed * 0.4]]
	var probe_dist := 200.0
	var trials := 12
	var measure_rows := []
	var before_rates := []
	var after_rates := []
	for phase in [0, 1]:
		var restore := set_speed_mult(probe_dist / float(eb.range) if phase == 0 else 0.4)
		for c in cases:
			var hit := 0
			for t in trials:
				var r2 := ember_throw(probe_dist, float((c as Array)[1]), int(t) + 1)
				if float(r2.dmg) > 0.0:
					hit += 1
			var rate := float(hit) / float(trials) * 100.0
			if phase == 0:
				before_rates.append(rate)
			else:
				after_rates.append(rate)
		var _r := set_speed_mult(restore)
	for i in cases.size():
		measure_rows.append("%s %.0f%% → %.0f%%" % [String((cases[i] as Array)[0]), float(before_rates[i]), float(after_rates[i])])
	print("EMBER_HIT_MEASURE 거리 %.0f · %d회씩 · 적중률 전 → 후: %s" % [probe_dist, trials, " | ".join(measure_rows)])
	ok("§6 고정 표적에는 예전과 똑같이 맞는다(느려져도 멈춘 적은 놓치지 않는다)",
		is_equal_approx(float(after_rates[0]), 100.0) and is_equal_approx(float(before_rates[0]), 100.0),
		"고정 %.0f%% → %.0f%%" % [float(before_rates[0]), float(after_rates[0])])
	ok("§6 이동하는 표적에는 확실히 약해진다(이 변경의 목적)",
		float(after_rates[1]) < float(before_rates[1]) and float(after_rates[1]) <= 25.0,
		"이동 %.0f%% → %.0f%%" % [float(before_rates[1]), float(after_rates[1])])
	ok("§6 둔화된 표적은 이동보다 잘 맞는다(밀집·둔화 조합의 값어치)",
		float(after_rates[2]) >= float(after_rates[1]),
		"둔화 %.0f%% → %.0f%% (이동 %.0f%%)" % [float(before_rates[2]), float(after_rates[2]), float(after_rates[1])])
	ok("§6 용어 사전·짧은 설명이 '느리게 날아가고 착탄 자리를 쫓지 않는다'를 적는다",
		says(gloss_body("ember"), "발사 순간") or says(gloss_body("ember"), "던지는 순간"),
		gloss_body("ember"))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
