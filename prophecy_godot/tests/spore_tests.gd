extends SceneTree
## 포자 괴물(spore) 결함 수정 검사(화면 없음).
## 실행: python tools/run_suites.py --suites spore_tests
##      (직접: godot --headless --path prophecy_godot -s tests/spore_tests.gd)
##
## 무엇을 못박는가(docs/SPORE_FIX.md와 같은 순서)
##  1. 가만히 선 플레이어에게 포자가 접근해 **실제로 폭발(구름) 피해를 준다**. 수정 전 동작(대조군)에서는 안 맞는다.
##  2. 준비를 시작하면 그 자리에 멈추고, 예고 중 플레이어가 움직여도 폭발 중심이 따라오지 않는다.
##  3. 몸이 겹치면 개체별 접촉 피해가 들어가고, 1초 안에 같은 포자에게 두 번 맞지 않는다(매 프레임 피해 없음).
##  4. 포자 3기와 동시에 겹치면 3배로 맞는다(첫 피해가 나머지를 지우지 않는다).
##  5. 회피 무적 중에는 접촉 피해를 안 맞는다.
##  6. 다른 공격(늑대 물기 등)의 기존 공통 피격 보호는 그대로다(전역으로 제거되지 않았다).
##  7. 포자 접촉과 일반 공격이 같은 프레임에 겹칠 때의 처리 순서가 정한 대로다.
##
## 수치는 모두 **시험값**이다(사용자 제시 첫 시험값: 접근 거리 = 폭발 반경의 절반, 접촉 피해 3, 재타격 간격 1초).
## 사람이 승인한 균형값이 아니다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func near(a: float, b: float, tol: float = 0.02) -> bool:
	return absf(a - b) <= tol

# ---------- 시험실 ----------
## 적이 저절로 나오지 않고 자동 공격도 없는 빈 전장(적 규칙만 본다). 장애물도 없앤다 — 접근 경로를 곧게 둔다
func lab(seed_v: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": 1 })
	st.spawn_hold = true
	st.weapons = []      # 자동기술 정지: 적 행동만 관찰한다
	st.obstacles = []    # 장애물 없음: 접근이 막혀서 안 맞는 것과 구분한다
	st.player.x = 480.0
	st.player.y = 300.0
	return st

## seconds 만큼 진행하며 플레이어를 계속 살려 둔다(연계 전체를 보기 위해). 피해 계측(metrics)은 그대로 쌓인다
func play(st: CombatState, seconds: float, input: Dictionary = {}) -> void:
	for i in int(round(seconds / STEP)):
		st.step(input, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"

func hits_of(st: CombatState, src: String) -> int:
	return int(st.metrics.taken_hits.get(src, 0))

func taken_of(st: CombatState, src: String) -> float:
	return float(st.metrics.taken.get(src, 0.0))

## 몸을 계속 겹쳐 둔 채 진행한다(겹침 해소가 밀어내도 접촉 상태를 유지 — 접촉 규칙만 본다)
func play_overlapped(st: CombatState, spores: Array, seconds: float, dodge: bool = false) -> void:
	for i in int(round(seconds / STEP)):
		for e in spores:
			e.x = st.player.x
			e.y = st.player.y
		if dodge: # 회피 무적을 제자리에서 유지(이동 0)
			st.player.dodge_active = true
			st.player.dodge_dx = 0.0
			st.player.dodge_dy = 0.0
			st.player.dodge_t = 0.0
			st.player.dodge_dist = 0.0
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"

## 포자 1기가 멀리서 접근해 구름을 만들 때까지 진행. [멈춘 거리, 구름 피해 횟수, 구름 중심과 플레이어 거리]
func approach_case(legacy: bool) -> Array:
	PEnemies.spore_legacy = legacy
	var st := lab()
	var sp := st.spawn_enemy("spore", 480.0 + 300.0, 300.0)
	var stop_dist := -1.0
	var cloud := {}
	for i in int(round(14.0 / STEP)):
		st.step({}, STEP) # 플레이어는 가만히 서 있다(입력 없음)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		if stop_dist < 0.0 and String(sp.state) == "swell":
			stop_dist = PGeom.dist(sp.x, sp.y, st.player.x, st.player.y)
		if cloud.is_empty():
			for z in st.zones:
				if String(z.type) == "spore":
					cloud = z
	PEnemies.spore_legacy = false
	var cd := PGeom.dist(float(cloud.get("x", -9999.0)), float(cloud.get("y", -9999.0)), st.player.x, st.player.y) if not cloud.is_empty() else -1.0
	return [stop_dist, hits_of(st, "zone"), cd]

func _init() -> void:
	var D: Dictionary = PCatalog.enemy("spore")
	var CFG: Dictionary = PEnemies.spore_cfg()
	var cloud_r := float(D.cloudR)
	var contact_dmg := float(CFG.get("contact_damage", 3.0))
	var contact_gap := float(CFG.get("contact_interval", 1.0))

	# ---------- 0. 시험값이 표(data/pacing.json)에서 온다 ----------
	ok("시험값이 data/pacing.json 겹쳐쓰기에서 온다(접근 비율 %.2f · 접촉 피해 %.0f · 재타격 간격 %.1f초)" % [float(CFG.get("approach_frac", -1.0)), contact_dmg, contact_gap],
		not CFG.is_empty() and near(float(CFG.get("approach_frac", -1.0)), 0.5) and near(contact_dmg, 3.0) and near(contact_gap, 1.0))

	var st0 := lab()
	var probe := st0.spawn_enemy("spore", 800.0, 300.0)
	var engage := PEnemies.spore_engage_dist(st0, probe)
	var bodies: float = float(probe.r) + float(st0.player.r)
	ok("준비를 시작하는 거리 = 폭발 반경의 절반(%.0f = %.0f × 0.5)이고 몸 크기(%.0f)보다 가깝게 요구하지 않는다" % [engage, cloud_r, bodies],
		near(engage, maxf(cloud_r * 0.5, bodies)) and near(engage, 40.0) and engage >= bodies,
		"cloudR %.0f · 폭발 반경보다 안쪽 %s" % [cloud_r, str(engage < cloud_r)])
	ok("수정 전 접근 거리(engageDist %.0f)는 폭발 반경(%.0f)보다 멀었다 — 결함의 원인" % [float(D.engageDist), cloud_r],
		float(D.engageDist) > cloud_r)

	# ---------- 1. 가만히 선 플레이어가 실제로 맞는다(+ 수정 전 대조군) ----------
	var fixed := approach_case(false)
	var legacy := approach_case(true)
	ok("가만히 선 플레이어에게 포자가 접근해 실제로 폭발 피해를 준다(멈춘 거리 %.1f, 구름 피해 %d회)" % [float(fixed[0]), int(fixed[1])],
		int(fixed[1]) > 0 and float(fixed[0]) > 0.0 and float(fixed[0]) <= cloud_r,
		"구름 중심-플레이어 거리 %.1f (반경 %.0f)" % [float(fixed[2]), cloud_r])
	ok("대조군(PROPHECY_SPORE_LEGACY, 수정 전 동작): 같은 상황에서 한 번도 맞지 않는다(멈춘 거리 %.1f, 구름 피해 %d회)" % [float(legacy[0]), int(legacy[1])],
		int(legacy[1]) == 0 and float(legacy[0]) > cloud_r,
		"구름 중심-플레이어 거리 %.1f > 반경 %.0f" % [float(legacy[2]), cloud_r])
	ok("기본값은 수정 후 동작(환경 변수 없이 대조군이 아니다)", not PEnemies.spore_legacy)

	# ---------- 2. 준비를 시작하면 그 자리에 멈추고 중심이 따라오지 않는다 ----------
	var st2 := lab()
	var sp2 := st2.spawn_enemy("spore", 480.0 + 120.0, 300.0)
	for i in int(round(8.0 / STEP)): # 준비(swell)에 들어갈 때까지
		if String(sp2.state) == "swell":
			break
		st2.step({}, STEP)
	var center := PEnemies.spore_swell_center(sp2)
	var body0 := [float(sp2.x), float(sp2.y)]
	var th := []
	PEnemies.threats(st2, sp2, th)
	var th_at_center: bool = th.size() == 1 and near(float(th[0].x), float(center[0]), 0.01) and near(float(th[0].y), float(center[1]), 0.01) and near(float(th[0].r), cloud_r, 0.01)
	# 예고 중에 플레이어가 포자 반대쪽으로 달아난다(몸으로 밀지 않는 방향이라 겹침 해소와 섞이지 않는다).
	# 수정 전이라면 폭발 중심은 애초에 사거리 밖이었고, 여기서는 '따라오는가'만 본다
	var cloud2 := {}
	for i in int(round(1.6 / STEP)):
		st2.player.x = clampf(st2.player.x - 120.0 * STEP, 30.0, 930.0)
		st2.step({ "mx": -1.0, "my": 0.0 }, STEP)
		for z in st2.zones:
			if String(z.type) == "spore":
				cloud2 = z
		if not cloud2.is_empty():
			break
	var moved := PGeom.dist(float(body0[0]), float(body0[1]), float(sp2.x), float(sp2.y))
	var fled := PGeom.dist(float(center[0]), float(center[1]), st2.player.x, st2.player.y)
	ok("준비를 시작하면 그 자리에 멈춘다(예고 %.1f초 동안 몸이 움직인 거리 %.2f px)" % [float(D.swell), moved], moved < 1.0)
	ok("예고 원이 고정된 폭발 중심에 그려진다(범위 %.0f)" % cloud_r, th_at_center,
		"예고 (%.1f, %.1f) r %.0f" % [float(th[0].x) if th.size() == 1 else -1.0, float(th[0].y) if th.size() == 1 else -1.0, float(th[0].r) if th.size() == 1 else -1.0])
	ok("예고 중 플레이어가 움직여도 폭발 중심이 따라오지 않는다(구름 중심 = 준비 시작 자리, 그 사이 플레이어는 %.0f px 밖으로 달아났다)" % fled,
		not cloud2.is_empty() and near(float(cloud2.x), float(center[0]), 0.01) and near(float(cloud2.y), float(center[1]), 0.01) and fled > cloud_r,
		"중심 (%.1f, %.1f) / 준비 자리 (%.1f, %.1f) / 플레이어 (%.1f, %.1f)" % [float(cloud2.get("x", -1.0)), float(cloud2.get("y", -1.0)), float(center[0]), float(center[1]), st2.player.x, st2.player.y])

	# ---------- 3. 몸이 겹치면 접촉 피해 · 1초 안에 두 번은 없다 ----------
	var st3 := lab()
	var sp3 := st3.spawn_enemy("spore", 480.0, 300.0)
	play_overlapped(st3, [sp3], 0.9)
	var n_09 := hits_of(st3, PEnemies.SPORE_CONTACT_SRC)
	play_overlapped(st3, [sp3], 1.6) # 합계 2.5초
	var n_25 := hits_of(st3, PEnemies.SPORE_CONTACT_SRC)
	ok("몸이 겹치면 접촉 피해가 들어간다(0.9초 동안 %d회 × %.0f)" % [n_09, contact_dmg], n_09 >= 1)
	ok("같은 포자에게 %.1f초 안에 두 번 맞지 않는다(매 프레임 피해 없음): 0.9초 동안 %d회(108단계)" % [contact_gap, n_09], n_09 == 1)
	ok("재타격 간격 %.1f초마다 다시 맞는다: 2.5초 동안 %d회(예상 3)" % [contact_gap, n_25], n_25 == 3,
		"누적 피해 %.1f" % taken_of(st3, PEnemies.SPORE_CONTACT_SRC))
	ok("접촉 피해는 개체당 %.0f이다(2.5초 누적 %.1f = %d회 × %.0f)" % [contact_dmg, taken_of(st3, PEnemies.SPORE_CONTACT_SRC), n_25, contact_dmg],
		near(taken_of(st3, PEnemies.SPORE_CONTACT_SRC), contact_dmg * float(n_25), 0.01))

	# ---------- 4. 포자 3기와 동시에 겹치면 3배(첫 피해가 나머지를 지우지 않는다) ----------
	var st4 := lab()
	var three := [st4.spawn_enemy("spore", 480.0, 300.0), st4.spawn_enemy("spore", 481.0, 300.0), st4.spawn_enemy("spore", 482.0, 300.0)]
	play_overlapped(st4, three, 0.5)
	ok("포자 3기와 동시에 겹치면 3배로 맞는다(0.5초 동안 %d회 · %.1f 피해 = 3 × %.0f)" % [hits_of(st4, PEnemies.SPORE_CONTACT_SRC), taken_of(st4, PEnemies.SPORE_CONTACT_SRC), contact_dmg],
		hits_of(st4, PEnemies.SPORE_CONTACT_SRC) == 3 and near(taken_of(st4, PEnemies.SPORE_CONTACT_SRC), contact_dmg * 3.0, 0.01))
	ok("첫 피해가 만든 공통 보호가 나머지 포자의 피해를 지우지 않는다(접촉만 면제)",
		st4.player.hit_prot > 0.0 and not st4.hit_protected(PEnemies.SPORE_CONTACT_SRC, three[0]) and st4.hit_protected("wolf:bite", three[0]),
		"보호 잔여 %.3f초" % st4.player.hit_prot)

	# ---------- 5. 회피 무적 중에는 접촉 피해가 없다 ----------
	var st5 := lab()
	var sp5 := st5.spawn_enemy("spore", 480.0, 300.0)
	play_overlapped(st5, [sp5], 0.5, true)
	var dodged := hits_of(st5, PEnemies.SPORE_CONTACT_SRC)
	var pd := int(st5.stats.perfect_dodges)
	st5.player.dodge_active = false
	play_overlapped(st5, [sp5], 0.7) # 합계 1.2초 — 재타격 간격 1.0초가 지난 뒤
	ok("회피 무적 중에는 접촉 피해를 안 맞고, 재타격 간격이 지난 뒤 다시 맞는다(무적 0.5초 %d회 → 1.2초 시점 %d회)" % [dodged, hits_of(st5, PEnemies.SPORE_CONTACT_SRC)],
		dodged == 0 and hits_of(st5, PEnemies.SPORE_CONTACT_SRC) == 1)
	ok("회피 무적 중 접촉도 개체별 간격을 소모한다(0.5초=60단계 겹침에 완벽 회피 %d회 — 매 프레임 아님)" % pd, pd == 1)

	# ---------- 6. 다른 공격의 기존 공통 피격 보호는 그대로다 ----------
	var st6 := lab()
	var w6 := st6.spawn_enemy("wolf", 500.0, 300.0)
	st6.player.hit_prot = 0.5
	var wolf_blocked: bool = not st6.damage_player(10.0, "wolf:bite", w6)
	var arrow_blocked: bool = not st6.damage_player(10.0, "archer:arrow", null)
	var contact_through: bool = st6.damage_player(contact_dmg, PEnemies.SPORE_CONTACT_SRC, w6)
	ok("공통 피격 보호가 전역으로 제거되지 않았다: 보호 중 늑대 물기·화살은 그대로 막힌다",
		wolf_blocked and arrow_blocked and st6.hit_protected("wolf:bite", w6) and st6.hit_protected("archer:arrow", null))
	ok("면제는 포자 접촉(%s) 하나뿐이다: 보호 중에도 접촉 피해만 들어간다" % PEnemies.SPORE_CONTACT_SRC,
		contact_through and hits_of(st6, PEnemies.SPORE_CONTACT_SRC) == 1 and hits_of(st6, "wolf:bite") == 0)
	# CombatState.hit_protected()는 순환 참조 때문에 상수 대신 글자를 직접 쓴다 — 두 값이 어긋나면 면제가 조용히 풀린다
	ok("면제 이름이 규칙 코드와 어긋나지 않는다(PEnemies.SPORE_CONTACT_SRC = \"spore:contact\")",
		PEnemies.SPORE_CONTACT_SRC == "spore:contact" and not st6.hit_protected("spore:contact", null) and st6.hit_protected("spore", null))
	var st6b := lab()
	var w6b := st6b.spawn_enemy("wolf", 500.0, 300.0)
	ok("보호가 없을 때 늑대 물기는 정상으로 들어가고, 그 뒤 0.6초 동안 두 번째 물기는 막힌다(기존 규칙 유지)",
		st6b.damage_player(10.0, "wolf:bite", w6b) and near(st6b.player.hit_prot, float(st6b.cfg.player.hit_protect), 0.001) and not st6b.damage_player(10.0, "wolf:bite", w6b),
		"보호 %.2f초" % float(st6b.cfg.player.hit_protect))

	# ---------- 7. 같은 프레임 처리 순서 ----------
	# 규칙: 적은 st.enemies 순서대로 갱신되고, 접촉 피해는 그 포자 갱신의 맨 처음에 계산된다.
	#       접촉 피해는 공통 보호를 읽지 않지만 세우기는 한다 → 뒤따르는 일반 공격은 막힌다.
	var order := []
	for spore_first in [true, false]:
		var st7 := lab()
		var sp7: Dictionary = {}
		var w7: Dictionary = {}
		if spore_first:
			sp7 = st7.spawn_enemy("spore", 480.0, 300.0)
			w7 = st7.spawn_enemy("wolf", 500.0, 300.0)
		else:
			w7 = st7.spawn_enemy("wolf", 500.0, 300.0)
			sp7 = st7.spawn_enemy("spore", 480.0, 300.0)
		sp7.x = st7.player.x # 몸 접촉
		sp7.y = st7.player.y
		w7.state = "bite_hit" # 같은 프레임에 물기 판정이 나도록 확정 상태로 둔다
		w7.state_t = 0.0
		w7.bite_hit_done = false
		w7.dir = atan2(st7.player.y - w7.y, st7.player.x - w7.x)
		st7.step({}, STEP)
		order.append([hits_of(st7, PEnemies.SPORE_CONTACT_SRC), hits_of(st7, "wolf:bite")])
	ok("같은 프레임 · 포자가 목록에서 앞설 때: 접촉 %d회가 먼저 들어가 공통 보호를 세우고 늑대 물기 %d회는 막힌다" % [int(order[0][0]), int(order[0][1])],
		int(order[0][0]) == 1 and int(order[0][1]) == 0)
	ok("같은 프레임 · 늑대가 목록에서 앞설 때: 물기 %d회가 먼저 들어가 보호를 세워도 접촉 %d회는 그대로 들어간다" % [int(order[1][1]), int(order[1][0])],
		int(order[1][1]) == 1 and int(order[1][0]) == 1)
	ok("정리한 순서: 회피 무적 → (st.enemies 순서) 포자 접촉 → 일반 공격 공통 보호 → 프레임 끝 구름(zone_tick %.1f초)" % float(st0.cfg.player.get("zone_tick", 0.5)),
		near(float(st0.cfg.player.get("zone_tick", 0.5)), 0.5))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
