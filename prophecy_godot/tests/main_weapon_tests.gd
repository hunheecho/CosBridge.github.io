extends SceneTree
## 주무기 5종의 구분 시험(화면 없음): python tools/run_suites.py --suites main_weapon_tests --jobs 1
##
## 여기서 못박는 것(사용자가 확정한 역할). 수치는 전부 시험값이고(data/main_weapons.json)
## 사람이 승인한 밸런스가 아니다.
##  검      — 짧은 거리의 넓은 부채꼴. 가까이 몰린 적을 자주 벤다.
##  관통창  — 긴 거리의 **매우 좁은** 직선. 여러 적을 꿰려면 적을 일렬로 세워야 한다.
##  쌍검    — 매우 짧은 리치·좁은 폭. 대신 같은 성장 투자에서 단일 대상 지속 화력이 1위다.
##  전투망치 — 준비 → 착탄 위치 확정 → 내려찍기. 피해 원의 중심은 플레이어가 아니라 착탄점이다.
##            밀어내기·경직은 data/supports.json 저항표를 쓴다(보스는 0 = 강제 이동·경직 없음).
##  추적궁  — 이동하며 유지하는 원거리. 근접에서는 위력이 크게 떨어진다.

const STEP := 1.0 / 120.0
const ENEMY_R := 14.0   # 늑대 반지름(data/enemies.json)
const THEORY_DIST := 45.0  # '붙어 있는' 거리(주무기 5종 모두 사거리 안, 쌍검 62가 가장 짧다)
const THEORY_SEC := 30.0   # 이론 DPS 측정 창(tools/dps_probe.gd와 같은 값)
const TARGET_RATIO := 1.5  # 사용자 확정: 쌍검 이론 단일 대상 DPS ≥ 검 × 1.5
const GROWTH_LEVELS := [1, 3, 5]

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 주무기 하나만 든 전투(적 등장 없음, 장애물 없음, 플레이어는 전장 가운데 고정)
func mk(weapon_id: String, mods: Array = [], level: int = 1) -> CombatState:
	var g := PGrowth.new_growth(weapon_id)
	g.weapons = [{ "id": weapon_id, "level": level, "mods": mods.duplicate() }]
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 1, "arena": "clearing", "obstacles": [],
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.player.x = 300.0
	st.player.y = 300.0
	return st

## 자동 발사를 끈 전투: 시험이 원할 때만 한 번 쏜다(지연 효과는 그대로 진행된다 — PWeapons.update 참고)
func mk_manual(weapon_id: String, mods: Array = []) -> CombatState:
	var st := mk(weapon_id, mods)
	st.player.attack_timer = 1.0e8
	return st

func wep(st: CombatState, weapon_id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == weapon_id:
			return w
	return {}

func stats_of(weapon_id: String) -> Dictionary:
	return mk(weapon_id).build.weapons[0]

## 공격하지 않는 표적
func dummy(st: CombatState, x: float, y: float, hp: float = 999999.0, type_id: String = "wolf") -> Dictionary:
	var e := st.spawn_enemy(type_id, x, y)
	e.hp = hp
	e.hp_max = hp
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

func at(st: CombatState, dist: float, deg: float) -> Array:
	var a := PGeom.deg(deg)
	return [st.player.x + cos(a) * dist, st.player.y + sin(a) * dist]

func steps_pinned(st: CombatState, seconds: float, pins: Array, input: Dictionary = {}) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		st.step(input, STEP)
		for pin in pins:
			var e: Dictionary = pin[0]
			e.x = float(pin[1]); e.y = float(pin[2]); e.vx = 0.0; e.vy = 0.0

## 자동 발사를 끈 상태에서 지연 효과(전투망치의 내려찍기 등)만 진행시킨다. 적은 스스로 움직이지 않는다
func advance_delayed(st: CombatState, seconds: float) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		PWeapons.update(st, STEP)

## 한 번 쏘고 그 결과가 다 들어올 때까지 기다린다. 맞은 횟수를 돌려준다
func fire_once(st: CombatState, weapon_id: String, target: Dictionary, wait: float = 1.0) -> int:
	var before: int = int(st.stats.hits)
	PWeapons.fire(st, wep(st, weapon_id), target, false)
	advance_delayed(st, wait)
	return int(st.stats.hits) - before

func dmg_of(st: CombatState, weapon_id: String) -> float:
	return float(st.metrics.dmg.get("weapon:" + weapon_id, 0.0))

## 표적 하나에 붙어서 seconds 동안 넣은 총 피해(같은 레벨·같은 성장 투자, 같은 거리)
func sustained(weapon_id: String, dist: float, seconds: float = 12.0, level: int = 1) -> float:
	var st := mk(weapon_id, [], level)
	var pos := at(st, dist, 0.0)
	var e := dummy(st, pos[0], pos[1])
	steps_pinned(st, seconds, [[e, pos[0], pos[1]]])
	return dmg_of(st, weapon_id)

## 이론 단일 대상 DPS(움직이지 않는 표적 하나에 붙어서 전부 적중할 때 초당 피해).
## 30초로 재는 이유: 짧은 창으로 재면 무기마다 발사 수가 반올림되어 비율이 흔들린다
## (12초면 검 22회·쌍검 16회라 소수 자리가 튄다). 측정 방식은 tools/dps_probe.gd와 같다
func theory_dps(weapon_id: String, level: int) -> float:
	return sustained(weapon_id, THEORY_DIST, THEORY_SEC, level) / THEORY_SEC

func _init() -> void:
	var sw := stats_of("sword")
	var sp := stats_of("spear")
	var dg := stats_of("daggers")
	var hm := stats_of("hammer")
	var bw := stats_of("bow")

	# ---------- 1. 관통창의 유효 폭이 검의 부채꼴 유효 폭보다 확실히 좁다 ----------
	# 유효 폭 = 적(반지름 14)이 실제로 맞는 좌우 통로 폭.
	#   창(직선): 판정 폭 + 적 지름          (PGeom.in_beam: |옆거리| <= 폭/2 + 반지름)
	#   검(부채꼴): 2 × 거리 × sin(반각) + 적 지름
	var half_sw: float = float(sw.arc_deg) * PI / 360.0
	var d_cmp := 85.0
	var spear_lane: float = float(sp.width) + 2.0 * ENEMY_R
	var sword_lane: float = 2.0 * d_cmp * sin(half_sw) + 2.0 * ENEMY_R
	ok("같은 레벨·같은 성장 투자에서 창의 유효 폭 %.1f은 검이 거리 %.0f에서 덮는 폭 %.1f의 3분의 1도 안 된다" % [spear_lane, d_cmp, sword_lane],
		spear_lane * 3.0 < sword_lane, "창 폭 %.1f(판정 %.1f) · 검 폭 %.1f(반각 %.1f°)" % [spear_lane, float(sp.width), sword_lane, half_sw * 180.0 / PI])
	var sword_span: float = 2.0 * d_cmp * sin(half_sw)
	ok("적 크기를 빼고 무기 자체의 폭만 보면 차이는 더 크다: 창 %.1f 대 검 %.1f(약 %.1f배)" % [float(sp.width), sword_span, sword_span / float(sp.width)],
		float(sp.width) * 9.0 < sword_span)
	ok("창의 판정 폭은 14다(생성 파일 44를 main_weapons.json이 덮는다 — 시험값)", is_equal_approx(float(sp.width), 14.0), "%.1f" % float(sp.width))
	ok("창은 검보다 멀리 닿는다(사거리 230 대 95) — 좁아진 대신 남는 장점", float(sp.range) > float(sw.range) * 2.0,
		"창 %.0f · 검 %.0f" % [float(sp.range), float(sw.range)])

	# ---------- 2. 일렬 3기는 창으로 한 번에, 부채꼴 3기는 못 맞힌다(검은 반대) ----------
	var st_line := mk_manual("spear")
	var line_e := []
	for i in 3:
		var p := at(st_line, 90.0 + 60.0 * float(i), 0.0)
		line_e.append(dummy(st_line, p[0], p[1]))
	var spear_line: int = fire_once(st_line, "spear", line_e[0])
	ok("일렬로 선 적 3기는 창 한 번에 모두 맞는다(3회 적중)", spear_line == 3, "적중 %d" % spear_line)

	var st_line_sw := mk_manual("sword")
	var line_sw := []
	for i in 3:
		var p := at(st_line_sw, 90.0 + 60.0 * float(i), 0.0)
		line_sw.append(dummy(st_line_sw, p[0], p[1]))
	var sword_line: int = fire_once(st_line_sw, "sword", line_sw[0])
	ok("같은 일렬 3기를 검은 한 번에 다 못 벤다(사거리 95 밖은 닿지 않는다)", sword_line == 1, "적중 %d" % sword_line)

	var fan_deg := [-20.0, 0.0, 20.0]
	var st_fan := mk_manual("spear")
	var fan_e := []
	for dv in fan_deg:
		var p := at(st_fan, d_cmp, float(dv))
		fan_e.append(dummy(st_fan, p[0], p[1]))
	var spear_fan: int = fire_once(st_fan, "spear", fan_e[1])
	ok("부채꼴로 흩어진 적 3기(거리 85, ±20°)는 창 한 번에 하나만 맞는다", spear_fan == 1, "적중 %d" % spear_fan)

	var st_fan_sw := mk_manual("sword")
	var fan_sw := []
	for dv in fan_deg:
		var p := at(st_fan_sw, d_cmp, float(dv))
		fan_sw.append(dummy(st_fan_sw, p[0], p[1]))
	var sword_fan: int = fire_once(st_fan_sw, "sword", fan_sw[1])
	ok("같은 부채꼴 3기를 검은 한 번에 모두 벤다", sword_fan == 3, "적중 %d" % sword_fan)

	# 창의 방향은 고른 대상 쪽으로 한 번 정할 뿐이고, 발사 뒤 좌우로 보정하지 않는다
	var st_aim := mk_manual("spear")
	var pa := at(st_aim, 150.0, 0.0)
	var side_p := at(st_aim, 150.0, 25.0)
	var aim_target := dummy(st_aim, pa[0], pa[1])
	var aim_side := dummy(st_aim, side_p[0], side_p[1])
	fire_once(st_aim, "spear", aim_target)
	ok("창은 고른 대상 방향으로만 나간다(옆으로 25° 벗어난 적은 자동 보정으로 끌려 들어오지 않는다)",
		float(aim_target.hp) < float(aim_target.hp_max) and is_equal_approx(float(aim_side.hp), float(aim_side.hp_max)))

	# ---------- 3. 쌍검이 단일 대상 지속 화력 1위 ----------
	var near := 45.0
	var sus := {}
	for wid in ["sword", "spear", "daggers", "hammer", "bow"]:
		sus[wid] = sustained(String(wid), near)
	var best := ""
	for wid in sus:
		if best == "" or float(sus[wid]) > float(sus[best]):
			best = String(wid)
	var second := 0.0
	for wid in sus:
		if String(wid) != "daggers":
			second = maxf(second, float(sus[wid]))
	var report := []
	for wid in ["sword", "spear", "daggers", "hammer", "bow"]:
		report.append("%s %.0f" % [String(wid), float(sus[wid])])
	ok("붙어서(거리 45) 12초 동안 한 적에게 준 총 피해는 쌍검이 1위다", best == "daggers", ", ".join(report))
	ok("쌍검의 단일 대상 지속 화력은 2위보다 15% 이상 높다(근접 위험의 보상)",
		float(sus["daggers"]) > second * 1.15, "쌍검 %.0f · 2위 %.0f" % [float(sus["daggers"]), second])
	ok("마무리 일격 배율이 자료에 있다(3연타의 마지막만 더 무겁다 — 시험값)", float(dg.get("finalMult", 1.0)) > 1.0,
		"finalMult %.2f" % float(dg.get("finalMult", 1.0)))
	ok("쌍검의 리치는 주무기 5종 중 가장 짧다", float(dg.range) < float(sw.range) and float(dg.range) < float(hm.range),
		"쌍검 %.0f · 검 %.0f · 망치 %.0f" % [float(dg.range), float(sw.range), float(hm.range)])

	# ---------- 3-2. 같은 투자에서 쌍검의 이론 단일 대상 DPS ≥ 검 × 1.5 (사용자 확정) ----------
	# '같은 투자' = 같은 레벨 · 개조 없음 · 장비 없음 · 대장간 강화 없음(둘 다 mk()의 기본 빌드).
	# 성장 구간 Lv1/Lv3/Lv5를 각각 못박는다. 레벨 배율은 두 무기에 같은 표(growth.json LEVEL_MULT)가
	# 곱해지므로 비율은 레벨과 무관해야 하고, 그 사실 자체도 여기서 확인된다.
	var LM: Array = PCatalog.growth().LEVEL_MULT
	var sword_floor: float = float(sw.damage) / float(sw.interval) # 검의 이론 DPS 기준선(Lv1 = 12/0.55)
	var ratio_rows := []
	var ratios := []
	for lv_v in GROWTH_LEVELS:
		var lv := int(lv_v)
		var dps_sw: float = theory_dps("sword", lv)
		var dps_dg: float = theory_dps("daggers", lv)
		var ratio: float = dps_dg / dps_sw if dps_sw > 0.0 else 0.0
		ratios.append(ratio)
		ratio_rows.append("Lv%d %.3f배" % [lv, ratio])
		ok("Lv%d 같은 투자(개조·장비·대장간 없음)에서 쌍검의 이론 단일 대상 DPS %.2f는 검 %.2f의 %.1f배 이상이다" % [lv, dps_dg, dps_sw, TARGET_RATIO],
			ratio >= TARGET_RATIO, "쌍검 %.2f ÷ 검 %.2f = %.3f배" % [dps_dg, dps_sw, ratio])
		# 검을 약화해서 비율을 맞추지 않았다는 확인: 검의 절대 수치가 레벨 배율대로 유지된다
		var want_sw: float = sword_floor * float(LM[lv - 1])
		ok("검 Lv%d의 이론 단일 대상 DPS %.2f는 내려가지 않았다(피해 %.0f ÷ 주기 %.2f × 레벨 배율 %.2f = %.2f 이상)" % [lv, dps_sw, float(sw.damage), float(sw.interval), float(LM[lv - 1]), want_sw],
			dps_sw >= want_sw - 1e-6, "%.3f ≥ %.3f" % [dps_sw, want_sw])
	var ratio_lo: float = INF
	var ratio_hi: float = -INF
	for r in ratios:
		ratio_lo = minf(ratio_lo, float(r))
		ratio_hi = maxf(ratio_hi, float(r))
	ok("비율은 레벨에 따라 흔들리지 않는다(같은 레벨 배율표가 두 무기에 똑같이 곱해진다 — 세 레벨의 차이 %.4f)" % (ratio_hi - ratio_lo),
		ratio_hi - ratio_lo < 0.01, ", ".join(ratio_rows))
	# 검의 기본 수치 자체를 못박는다 — 비율을 검 약화로 맞추면 이 줄이 먼저 깨진다
	ok("검의 기본 수치는 그대로다(피해 12 · 주기 0.55 · 사거리 95 · 부채꼴 110°)",
		is_equal_approx(float(sw.damage), 12.0) and is_equal_approx(float(sw.interval), 0.55)
			and is_equal_approx(float(sw.range), 95.0) and is_equal_approx(float(sw.arc_deg), 110.0),
		"피해 %.1f · 주기 %.2f · 사거리 %.0f · %.0f°" % [float(sw.damage), float(sw.interval), float(sw.range), float(sw.arc_deg)])

	# ---------- 3-3. 카드·빌드 화면이 "6 × 3연타"로 적을 수 있는 파생 수치가 있는가 ----------
	# 화면 코드는 이 작업의 소유가 아니다. 여기서는 **읽을 값이 파생 수치에 실제로 있는지**만 못박는다
	# (docs/MAIN_WEAPONS.md의 '표기 자료' 절이 무엇을 읽으면 되는지 적는다).
	ok("쌍검의 파생 수치에 연타 수(hits)가 있다 — 카드가 '피해 %s × %d연타'로 적을 수 있다" % [str(snapped(float(dg.damage), 0.1)), int(dg.get("hits", 0))],
		dg.has("hits") and int(dg.hits) == 3, "hits %s" % str(dg.get("hits", null)))
	ok("쌍검의 파생 수치에 연타 간격(hit_gap %.2f초)이 있다 — 3연타가 %.2f초 동안 이어진다" % [float(dg.get("hit_gap", 0.0)), float(dg.get("hit_gap", 0.0)) * 2.0],
		dg.has("hit_gap") and float(dg.hit_gap) > 0.0, "hit_gap %s · hitGap %s" % [str(dg.get("hit_gap", null)), str(dg.get("hitGap", null))])
	ok("마무리 배율(finalMult)도 파생 수치에 남아 있다 — 마지막 일격만 더 무겁다고 적을 수 있다",
		dg.has("finalMult") and float(dg.finalMult) > 1.0, "finalMult %s" % str(dg.get("finalMult", null)))
	var cycle_dmg: float = float(dg.damage) * (float(int(dg.hits) - 1) + float(dg.finalMult))
	ok("연타 표기와 한 주기 피해가 맞는다: %.1f × %d연타(마지막 ×%.2f) = %.1f, 초당 %.2f" % [float(dg.damage), int(dg.hits), float(dg.finalMult), cycle_dmg, cycle_dmg / float(dg.interval)],
		absf(cycle_dmg / float(dg.interval) - theory_dps("daggers", 1)) < 1.0,
		"계산 %.2f · 측정 %.2f" % [cycle_dmg / float(dg.interval), theory_dps("daggers", 1)])
	# 리치·폭은 이번 상향으로도 그대로다(사거리를 늘려 해결하지 않았다는 확인)
	ok("쌍검의 리치 62·폭 70°는 그대로다(사거리를 늘려 화력을 맞추지 않았다)",
		is_equal_approx(float(dg.range), 62.0) and is_equal_approx(float(dg.arc_deg), 70.0),
		"사거리 %.0f · %.0f°" % [float(dg.range), float(dg.arc_deg)])

	# ---------- 4. 전투망치: 예고 → 착탄 위치 확정 → 내려찍기 ----------
	var st_h := mk_manual("hammer")
	var tp := at(st_h, float(hm.range), 0.0)
	var h_target := dummy(st_h, tp[0], tp[1])
	PWeapons.fire(st_h, wep(st_h, "hammer"), h_target, false)
	var warn := {}
	for f in st_h.effects:
		if String(f.kind) == "strikewarn":
			warn = f
	ok("준비 단계에 내려찍을 자리가 예고로 보인다(점선 원 strikewarn, 판정과 같은 반지름)",
		not warn.is_empty() and is_equal_approx(float(warn.get("r", -1.0)), float(hm.radius))
			and absf(float(warn.get("x", 0.0)) - tp[0]) < 0.01,
		"예고 %s" % str(warn))
	ok("준비 중에는 아직 피해가 없다", is_equal_approx(dmg_of(st_h, "hammer"), 0.0))
	advance_delayed(st_h, float(hm.windup) + 0.02)
	ok("준비(%.2f초)가 끝나면 그 자리에 내려찍혀 피해가 들어간다" % float(hm.windup), dmg_of(st_h, "hammer") > 0.0,
		"%.1f" % dmg_of(st_h, "hammer"))

	# 위치가 준비 시작에 확정된다: 예고 뒤 적이 걸어 나가면 빗나간다
	var st_miss := mk_manual("hammer")
	var mp := at(st_miss, float(hm.range), 0.0)
	var runner := dummy(st_miss, mp[0], mp[1])
	PWeapons.fire(st_miss, wep(st_miss, "hammer"), runner, false)
	runner.x = mp[0] + float(hm.radius) + ENEMY_R + 60.0   # 예고 원 밖으로 걸어 나간다
	advance_delayed(st_miss, float(hm.windup) + 0.02)
	ok("착탄 위치는 준비 시작에 확정된다(예고 뒤 밖으로 나간 적은 안 맞는다)",
		is_equal_approx(dmg_of(st_miss, "hammer"), 0.0) and is_equal_approx(float(runner.hp), float(runner.hp_max)))

	# 피해 원의 중심은 플레이어가 아니라 착탄점
	var st_c := mk_manual("hammer")
	var cp := at(st_c, float(hm.range), 0.0)
	var far_p := at(st_c, float(hm.range) + 60.0, 0.0)
	var back_p := at(st_c, 30.0, 180.0)
	var c_target := dummy(st_c, cp[0], cp[1])
	var c_far := dummy(st_c, far_p[0], far_p[1])
	var c_back := dummy(st_c, back_p[0], back_p[1])
	fire_once(st_c, "hammer", c_target, float(hm.windup) + 0.1)
	ok("망치의 피해 원은 착탄점 중심이다: 플레이어에서 먼 쪽(거리 %.0f) 적은 맞고 뒤쪽(거리 30) 적은 안 맞는다" % (float(hm.range) + 60.0),
		float(c_far.hp) < float(c_far.hp_max) and is_equal_approx(float(c_back.hp), float(c_back.hp_max)),
		"먼 쪽 %.0f/%.0f · 뒤쪽 %.0f/%.0f" % [float(c_far.hp), float(c_far.hp_max), float(c_back.hp), float(c_back.hp_max)])
	ok("플레이어 중심이었다면 결과가 반대였다(뒤쪽 30 < 반지름 %.0f, 먼 쪽 %.0f > 반지름)" % [float(hm.radius), float(hm.range) + 60.0],
		30.0 < float(hm.radius) + ENEMY_R and float(hm.range) + 60.0 > float(hm.radius) + ENEMY_R)

	# ---------- 5. 밀어내기·경직: 일반은 밀리고 보스는 위치가 전혀 바뀌지 않는다 ----------
	var st_k := mk_manual("hammer")
	var kp := at(st_k, float(hm.range), 0.0)
	var normal_e := dummy(st_k, kp[0], kp[1])
	var nx0: float = normal_e.x
	var ny0: float = normal_e.y
	fire_once(st_k, "hammer", normal_e, float(hm.windup) + 0.1)
	var moved := PGeom.dist(nx0, ny0, normal_e.x, normal_e.y)
	ok("망치는 일반 적을 착탄점 반대 방향으로 밀어낸다(거리 %.1f = knockDist %.0f × 일반 저항 1.0)" % [moved, float(hm.knockDist)],
		moved > 1.0 and absf(moved - PSupport.knock_dist(float(hm.knockDist), normal_e)) < 0.5, "%.2f" % moved)
	ok("일반 적은 경직된다(다음 공격 금지 %.2f초 = stagger %.2f × 저항 1.0)" % [float(normal_e.get("grace", 0.0)), float(hm.stagger)],
		absf(float(normal_e.get("grace", 0.0)) - float(hm.stagger) * PSupport.resist_mult("stagger", normal_e)) < 1e-6)

	var st_b := mk_manual("hammer")
	var bp := at(st_b, float(hm.range), 0.0)
	var boss_e := st_b.spawn_enemy("boss", bp[0], bp[1])
	boss_e.boss_id = "boss"
	boss_e.hp = 1.0e7
	boss_e.hp_max = 1.0e7
	var bx0: float = boss_e.x
	var by0: float = boss_e.y
	var bstate := String(boss_e.state)
	fire_once(st_b, "hammer", boss_e, float(hm.windup) + 0.1)
	ok("보스는 망치에 맞아도 위치가 전혀 바뀌지 않는다(밀어내기 저항 0)",
		is_equal_approx(boss_e.x, bx0) and is_equal_approx(boss_e.y, by0), "(%.3f, %.3f) → (%.3f, %.3f)" % [bx0, by0, boss_e.x, boss_e.y])
	ok("보스는 경직되지도 않는다(무한 제압 금지)",
		is_zero_approx(float(boss_e.get("grace", 0.0))) and String(boss_e.state) == bstate)
	ok("보스도 피해는 그대로 받는다(제압만 막힌다)", float(boss_e.hp) < float(boss_e.hp_max),
		"%.1f" % (float(boss_e.hp_max) - float(boss_e.hp)))

	# 끌어당기는 망치(개조)도 강제 위치 이동이라 같은 저항표를 쓴다
	var st_pull := mk_manual("hammer", ["pull"])
	var pp := at(st_pull, float(hm.range), 0.0)
	var pull_boss := st_pull.spawn_enemy("boss", float(pp[0]) + 95.0, float(pp[1]))
	pull_boss.boss_id = "boss"
	pull_boss.hp = 1.0e7
	pull_boss.hp_max = 1.0e7
	var pbx: float = pull_boss.x
	var pby: float = pull_boss.y
	var pull_target := dummy(st_pull, float(pp[0]), float(pp[1]))
	fire_once(st_pull, "hammer", pull_target, float(hm.windup) + 0.1)
	ok("끌어당기는 망치도 보스를 끌지 못한다(끌어당김 역시 저항표를 따른다)",
		is_equal_approx(pull_boss.x, pbx) and is_equal_approx(pull_boss.y, pby), "(%.3f, %.3f)" % [pull_boss.x, pull_boss.y])

	var st_el := mk_manual("hammer")
	var ep := at(st_el, float(hm.range), 0.0)
	var elite_e := dummy(st_el, ep[0], ep[1], 999999.0, "wolf_alpha")
	var ex0: float = elite_e.x
	fire_once(st_el, "hammer", elite_e, float(hm.windup) + 0.1)
	var el_moved: float = absf(elite_e.x - ex0)
	ok("정예는 밀리긴 하되 일반보다 덜 밀린다(저항표 그대로)",
		el_moved > 0.0 and el_moved < moved - 0.5 and absf(el_moved - PSupport.knock_dist(float(hm.knockDist), elite_e)) < 0.5,
		"정예 %.2f < 일반 %.2f" % [el_moved, moved])
	ok("정예의 경직도 저항만큼 짧다",
		absf(float(elite_e.get("grace", 0.0)) - float(hm.stagger) * PSupport.resist_mult("stagger", elite_e)) < 1e-6,
		"%.3f초" % float(elite_e.get("grace", 0.0)))

	# 늑대 계열이 아닌 적은 빈틈(경직) 상태로 들어간다
	var st_bo := mk_manual("hammer")
	var op := at(st_bo, float(hm.range), 0.0)
	var boar := dummy(st_bo, op[0], op[1], 999999.0, "boar")
	fire_once(st_bo, "hammer", boar, float(hm.windup) + 0.1)
	ok("늑대가 아닌 적은 준비 동작이 끊기고 빈틈에 빠진다(빈틈 길이도 저항을 따른다)",
		String(boar.state) == "recover" and absf(float(boar.recover_dur) - float(hm.stagger)) < 1e-6,
		"상태 %s · 빈틈 %.2f초" % [String(boar.state), float(boar.recover_dur)])

	ok("망치는 검처럼 자주 휘두르지 않는다(초당 공격 %.2f회 대 검 %.2f회)" % [1.0 / float(hm.interval), 1.0 / float(sw.interval)],
		float(hm.interval) > float(sw.interval) * 2.0)
	var sword_area_ps: float = (float(sw.arc_deg) / 360.0) * PI * float(sw.range) * float(sw.range) / float(sw.interval)
	var hammer_area_ps: float = PI * float(hm.radius) * float(hm.radius) / float(hm.interval)
	ok("망치가 초당 덮는 범위(%.0f)는 검(%.0f)보다 좁다 — 넓게 자주 휘두르는 무기가 아니다" % [hammer_area_ps, sword_area_ps],
		hammer_area_ps < sword_area_ps)

	# ---------- 6. 추적궁: 이동 중에도 공격 유지 · 근접에서는 약하다 ----------
	var far_d := 200.0
	var st_move := mk("bow")
	var bp2 := at(st_move, far_d, -90.0)
	var b_target := dummy(st_move, bp2[0], bp2[1])
	var zig := 0
	var n_move := int(round(6.0 / STEP))
	for i in n_move:
		zig = 1 if (i / 60) % 2 == 0 else -1   # 0.5초마다 좌우로 방향을 바꾸며 계속 이동
		st_move.step({ "mx": float(zig), "my": 0.0 }, STEP)
		b_target.x = bp2[0]; b_target.y = bp2[1]; b_target.vx = 0.0; b_target.vy = 0.0
	var bow_moving := dmg_of(st_move, "bow")

	var st_stand := mk("bow")
	var b_stand := dummy(st_stand, bp2[0], bp2[1])
	steps_pinned(st_stand, 6.0, [[b_stand, bp2[0], bp2[1]]])
	var bow_still := dmg_of(st_stand, "bow")
	ok("추적궁은 이동 중에도 공격을 유지한다(6초 동안 움직이며 %.0f · 서서 %.0f)" % [bow_moving, bow_still],
		bow_moving > 0.0 and bow_moving >= bow_still * 0.85, "이동 %.1f · 정지 %.1f" % [bow_moving, bow_still])

	var st_sw_move := mk("sword")
	var sp2 := at(st_sw_move, far_d, -90.0)
	var s_target := dummy(st_sw_move, sp2[0], sp2[1])
	steps_pinned(st_sw_move, 6.0, [[s_target, sp2[0], sp2[1]]])
	ok("같은 거리(200)에서 근접 주무기(검)는 한 번도 때리지 못한다 — 이것이 원거리 유지의 값어치다",
		is_equal_approx(dmg_of(st_sw_move, "sword"), 0.0))

	var bow_near := float(sus["bow"])
	var bow_far := sustained("bow", 250.0)
	ok("추적궁은 근접(45)에서 원거리(250)보다 약하다: %.0f 대 %.0f (근접 약화 %.0f 안쪽 ×%.2f)" % [bow_near, bow_far, float(bw.closeFrom), float(bw.closeMult)],
		bow_near < bow_far * 0.7, "근접 %.1f · 원거리 %.1f" % [bow_near, bow_far])
	ok("근접에서 추적궁의 지속 화력은 쌍검의 절반도 안 된다(순간 화력 약점)",
		bow_near * 2.0 < float(sus["daggers"]), "궁 %.0f · 쌍검 %.0f" % [bow_near, float(sus["daggers"])])

	# ---------- 7. 기존 개조가 구분을 지우지 않는다 ----------
	var ct: Dictionary = PWeapons.mod_tune(sw, "crescent", {})
	var crescent_reach: float = float(sw.range) * 0.8 + float(ct.travel)
	ok("날아가는 검광의 도달 거리 %.0f는 검 사거리 %.0f의 1.4배를 넘지 않는다(검을 원거리 무기로 만들지 않는다)" % [crescent_reach, float(sw.range)],
		crescent_reach <= float(sw.range) * 1.4, "%.0f ≤ %.0f" % [crescent_reach, float(sw.range) * 1.4])
	ok("날아가는 검광은 창 사거리 근처까지 가지 않는다", crescent_reach < float(sp.range) * 0.7,
		"검광 %.0f · 창 %.0f" % [crescent_reach, float(sp.range)])

	var pt: Dictionary = PWeapons.mod_tune(sp, "split", {})
	var st_split := mk_manual("spear", ["split"])
	var split_pins := []
	var split_e := []
	for dv in fan_deg:
		var p := at(st_split, d_cmp, float(dv))
		var e := dummy(st_split, float(p[0]), float(p[1]))
		split_e.append(e)
		split_pins.append([e, float(p[0]), float(p[1])])
	# 예전 값(사선 0.6rad · 170)이라면 파편이 지나갔을 자리에 미끼를 둔다. 지금 값이면 닿지 않아야 한다
	var decoy := []
	for sgn in [-1.0, 1.0]:
		var dx: float = d_cmp + cos(0.6) * 100.0
		var dy: float = float(sgn) * sin(0.6) * 100.0
		var e2 := dummy(st_split, st_split.player.x + dx, st_split.player.y + dy)
		decoy.append(e2)
		split_pins.append([e2, st_split.player.x + dx, st_split.player.y + dy])
	PWeapons.fire(st_split, wep(st_split, "spear"), split_e[1], false)
	steps_pinned(st_split, 1.0, split_pins) # 파편이 실제로 날아가게 진행한다(자동 발사는 꺼 둔 상태)
	var split_hit := 0
	for e in split_e:
		if float(e.hp) < float(e.hp_max):
			split_hit += 1
	var decoy_hit := 0
	for e in decoy:
		if float(e.hp) < float(e.hp_max):
			decoy_hit += 1
	ok("분열 창날을 달아도 부채꼴 3기 중 하나만 맞는다(좁은 폭이라는 약점을 개조가 지우지 않는다)", split_hit == 1,
		"맞은 적 %d" % split_hit)
	ok("예전 사선(0.6rad·170)이라면 파편이 닿았을 좌우 자리의 적은 이제 맞지 않는다", decoy_hit == 0, "맞은 미끼 %d" % decoy_hit)
	var split_side: float = float(pt.travel) * sin(float(pt.spread))
	ok("분열 창날이 벗어나는 좌우 거리 %.1f는 관통 통로 반폭 %.1f 안이다" % [split_side, spear_lane / 2.0],
		split_side <= spear_lane / 2.0)

	# ---------- 8. 저항표를 코드가 아니라 자료에서 가져온다 ----------
	ok("망치의 밀어내기·경직은 data/supports.json 저항표를 그대로 쓴다(보스 0 · 정예 감소 · 일반 1.0)",
		is_zero_approx(PSupport.resist_mult("knock", { "boss": true }))
			and is_zero_approx(PSupport.resist_mult("stagger", { "boss": true }))
			and PSupport.resist_mult("knock", { "elite": true }) < 1.0
			and is_equal_approx(PSupport.resist_mult("knock", {}), 1.0))
	ok("망치는 속도 충격(knock)을 쓰지 않는다 — 그 경로는 보스도 knockMult만큼 밀려 공통 규칙을 지키지 못한다",
		is_zero_approx(float(hm.knock)) and float(hm.knockDist) > 0.0,
		"knock %.0f · knockDist %.0f" % [float(hm.knock), float(hm.knockDist)])

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
