extends SceneTree
## 수동 기술 E '돌풍'의 자동조준 시험(화면 없음): python tools/run_suites.py --suites gust_tests --jobs 1
##
## 무엇을 못박는가 — 사용자가 정한 조준 규칙(2026-09-09, docs/FEEDBACK_2026-09-09.md ①절):
##  ① 쓰는 순간 **실제 사거리·지형 조건을 통과한 가까운 적**을 향해 나간다.
##  ② **이동 방향이 그 조준각을 덮어쓰지 않는다**(이번 수정의 핵심).
##  ③ 그런 적이 없으면 **마지막 바라보던 방향**으로 나간다(오류 없이).
##  ④ 벽 뒤의 적·사거리 밖의 적·구조물·공중의 적을 고르지 않는다.
##  ⑤ **표시(부채꼴)와 실제 판정이 같은 각**을 쓴다.
##  ⑥ 거리·폭·피해·재사용·밀어내기는 이번 수정에서 **바뀌지 않았다**(값으로 못박는다).
##  ⑦ PC와 모바일에 **같은 기본 조준 규칙**이 적용된다(새 조준 버튼·드래그를 만들지 않았다).
##
## 수치는 전부 기존 자료값(data/growth.json의 skills.gust)이고 여기서 새로 정한 밸런스가 아니다.
## 방향이 없는 회오리(whirl) 변형은 조준 규칙의 대상이 아니라 여기서 다루지 않는다.
##
## 시험 장치에 관한 사실 두 가지(어림이 아니라 규칙에서 온다):
##  - 한 단계의 순서는 update_player(이동 → cast_e) → update_enemies다(combat_state.gd:2550~).
##    그래서 사용 순간의 적 자리 = 단계 시작 시점의 자리이고, 플레이어만 한 단계 이동한 자리다.
##    기대각은 항상 **효과가 남긴 자리(fx.x·fx.y)** 기준으로 계산하므로 어림값이 끼지 않는다.
##  - 자동공격은 꺼 둔다. 자동공격도 p.face를 덮어쓰므로(weapons.gd:176 등) 켜 두면 무엇이 원인인지 갈라지지 않는다.

const STEP := 1.0 / 120.0
const PX := 400.0   # 플레이어 시작 자리(960×600 전장 안쪽)
const PY := 400.0

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 돌풍 E를 든 전투. 적은 저절로 등장하지 않고(spawn_hold) 장애물도 시험이 직접 준다.
func mk(o: Dictionary = {}) -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.skills.e = { "id": "gust", "level": int(o.get("level", 1)), "variant": o.get("variant", null) }
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 1, "arena": "clearing",
		"obstacles": o.get("obstacles", []),
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.player.x = PX
	st.player.y = PY
	st.player.attack_timer = 1.0e8
	return st

## 장애물 하나(둥근 바위). CombatState.new가 읽는 모양 그대로
func rock(x: float, y: float, r: float) -> Dictionary:
	return { "id": "t_rock", "type": "rock", "x": x, "y": y, "r": r }

## 공격하지 않는 표적(물기·돌진 예약을 사실상 무한으로 밀어 둔다)
func dummy(st: CombatState, x: float, y: float, type_id: String = "wolf") -> Dictionary:
	var e := st.spawn_enemy(type_id, x, y)
	e.hp = 99999.0
	e.hp_max = 99999.0
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

## 플레이어에서 거리 dist·각도 deg인 자리에 표적 하나
func dummy_at(st: CombatState, dist: float, deg_v: float, type_id: String = "wolf") -> Dictionary:
	var a := PGeom.deg(deg_v)
	return dummy(st, st.player.x + cos(a) * dist, st.player.y + sin(a) * dist, type_id)

## 방금 나간 돌풍의 표시 효과(부채꼴). 화면이 그리는 바로 그 자료다(render.gd의 "gust")
func gust_fx(st: CombatState) -> Dictionary:
	var out := {}
	for f in st.effects:
		if String(f.get("kind", "")) == "gust" and f.has("angle"):
			out = f
	return out

## 사용 순간의 자리·조준을 시험이 직접 정할 때(이동 없이 한 번 쓴다)
func cast_now(st: CombatState) -> Dictionary:
	st.effects.clear()
	PSkills.cast_e(st)
	return gust_fx(st)

## 실제 한 단계(이동 입력 → cast_e)를 그대로 밟아 한 번 쓴다
func step_cast(st: CombatState, mx: float, my: float) -> Dictionary:
	st.effects.clear()
	st.step({ "mx": mx, "my": my, "skill_e": true }, STEP)
	return gust_fx(st)

## 효과가 남긴 발사 자리에서 그 적을 보는 각(기대값)
func want_ang(fx: Dictionary, e: Dictionary) -> float:
	return atan2(float(e.y) - float(fx.y), float(e.x) - float(fx.x))

func near_ang(a: float, b: float, tol_deg: float = 1.0) -> bool:
	return absf(PGeom.ang_diff(a, b)) <= PGeom.deg(tol_deg)

func dg(a: float) -> float:
	return rad_to_deg(a)

func hurt(e: Dictionary) -> float:
	return float(e.hp_max) - float(e.hp)

func _init() -> void:
	var SKD: Dictionary = PCatalog.skills()["gust"]
	var dmg_tab: Array = SKD.damage
	var cd_tab: Array = SKD.cooldown

	# ---------- ① 조준: 유효한 가까운 적을 향한다 ----------
	print("\n[1] 조준 대상")
	var st := mk()
	var e_left := dummy_at(st, 120.0, 180.0)
	st.player.face = 0.0                                     # 오른쪽을 보고 서 있다(적은 왼쪽)
	var fx := cast_now(st)
	ok("제자리: 보던 방향(0도)이 아니라 적 쪽(180도)으로 나가고 그 적이 맞았다",
		not fx.is_empty() and near_ang(float(fx.angle), PI) and hurt(e_left) > 0.0,
		"각 %.1f도 · 피해 %.1f" % [dg(float(fx.get("angle", 0.0))), hurt(e_left)])

	st = mk()
	var e_far := dummy_at(st, 160.0, 90.0)
	var e_near := dummy_at(st, 60.0, 200.0)
	fx = cast_now(st)
	ok("둘 다 유효하면 더 가까운 적(60px, 200도)을 고른다",
		near_ang(float(fx.angle), want_ang(fx, e_near)) and hurt(e_near) > 0.0 and hurt(e_far) == 0.0,
		"각 %.1f도 · 가까운 적 피해 %.1f · 먼 적 피해 %.1f" % [dg(float(fx.angle)), hurt(e_near), hurt(e_far)])

	# ---------- ② 이동 방향이 조준을 덮지 않는다(이번 수정의 핵심) ----------
	print("\n[2] 이동 중 · 후퇴 중")
	st = mk()
	var e_l := dummy_at(st, 120.0, 180.0)
	fx = step_cast(st, 1.0, 0.0)                             # 적을 등지고 오른쪽으로 달리며 사용
	ok("이동 중: face가 이동 방향(0도)으로 덮여도 돌풍은 적 쪽(180도)으로 나간다",
		not fx.is_empty() and near_ang(float(fx.angle), want_ang(fx, e_l)) and near_ang(float(st.player.face), 0.0),
		"돌풍 %.1f도 · face %.1f도" % [dg(float(fx.get("angle", 0.0))), dg(float(st.player.face))])
	ok("이동 중에 조준한 그 적이 실제로 맞았다", hurt(e_l) > 0.0, "받은 피해 %.1f" % hurt(e_l))

	st = mk()
	var e_r := dummy_at(st, 120.0, 0.0)
	fx = step_cast(st, -1.0, 0.0)                            # 적에게서 도망치며(후퇴) 사용
	ok("후퇴 중: 도망치는 뒤쪽(180도)이 아니라 적 쪽(0도)으로 나가고 그 적이 맞았다",
		not fx.is_empty() and near_ang(float(fx.angle), want_ang(fx, e_r)) and near_ang(float(st.player.face), PI) and hurt(e_r) > 0.0,
		"돌풍 %.1f도 · face %.1f도 · 피해 %.1f" % [dg(float(fx.get("angle", 0.0))), dg(float(st.player.face)), hurt(e_r)])

	var worst := 0.0
	var faces := []
	for dir_deg in [0.0, 90.0, 180.0, 270.0, 45.0]:          # 이동 방향 5가지를 돌아가며
		var s2 := mk()
		var t2 := dummy_at(s2, 130.0, 90.0)
		var a2 := PGeom.deg(float(dir_deg))
		var f2 := step_cast(s2, cos(a2), sin(a2))
		worst = maxf(worst, absf(PGeom.ang_diff(float(f2.angle), want_ang(f2, t2))))
		faces.append(dg(float(s2.player.face)))
	ok("이동 방향 5가지(0·90·180·270·45도) 어느 쪽으로 달려도 조준각은 같은 적을 가리킨다",
		worst <= PGeom.deg(0.5), "최대 오차 %.3f도 · 그때의 face %s" % [dg(worst), str(faces)])

	# ---------- ③ 적이 없으면 마지막 바라보던 방향 ----------
	print("\n[3] 적이 없을 때")
	st = mk()
	st.player.face = PGeom.deg(30.0)
	fx = cast_now(st)
	ok("적이 하나도 없으면 마지막 바라보던 방향(30도) 그대로 나간다(오류 없음)",
		not fx.is_empty() and is_equal_approx(float(fx.angle), PGeom.deg(30.0)), "각 %.2f도" % dg(float(fx.get("angle", 0.0))))
	ok("적이 없어도 사용은 성립한다(재사용 대기가 걸리고 사용 횟수가 늘었다)",
		float(st.player.e_cd) > 0.0 and int(st.stats.e_uses) == 1,
		"재사용 %.1f초 · 사용 %d회" % [float(st.player.e_cd), int(st.stats.e_uses)])

	# ---------- ④ 유효한 적이 아닌 것: 사거리 밖 · 벽 뒤 · 구조물 · 공중 ----------
	print("\n[4] 유효한 적 판정")
	st = mk()
	st.player.face = PGeom.deg(-90.0)
	var e_out := dummy_at(st, 250.0, 0.0)                     # 170 + 14 = 184 밖
	fx = cast_now(st)
	ok("사거리 밖(250px)의 적은 고르지 않는다 — 마지막 방향(-90도)으로 나가고 그 적은 맞지도 않았다",
		is_equal_approx(float(fx.angle), PGeom.deg(-90.0)) and hurt(e_out) == 0.0, "각 %.1f도" % dg(float(fx.angle)))

	st = mk()
	var e_edge := dummy_at(st, 180.0, 0.0)                    # 180 ≤ 170 + 적 반지름 14 → 유효
	fx = cast_now(st)
	ok("사거리 경계(180px ≤ 170 + 적 반지름 14)는 유효한 적이다",
		near_ang(float(fx.angle), 0.0) and hurt(e_edge) > 0.0,
		"각 %.1f도 · 피해 %.1f" % [dg(float(fx.angle)), hurt(e_edge)])

	# 벽 뒤 적(가까움) + 트인 적(멀다) → 트인 적을 고른다
	st = mk({ "obstacles": [rock(PX - 60.0, PY, 20.0)] })
	var e_behind := dummy(st, PX - 120.0, PY)                 # 바위 너머, 거리 120
	var e_open := dummy(st, PX, PY + 150.0)                   # 트여 있음, 거리 150
	ok("시험 전제: 왼쪽 적은 실제로 가려져 있고 아래쪽 적은 트여 있다",
		st.los_blocked(PX, PY, float(e_behind.x), float(e_behind.y)) and not st.los_blocked(PX, PY, float(e_open.x), float(e_open.y)))
	fx = cast_now(st)
	ok("벽 뒤의 더 가까운 적(120px)을 두고 트인 먼 적(150px)을 고른다",
		near_ang(float(fx.angle), PI / 2.0), "각 %.1f도" % dg(float(fx.angle)))
	ok("벽 뒤의 적은 맞지 않았고 트인 적만 맞았다(가림 검사는 판정에도 그대로 걸린다)",
		hurt(e_behind) == 0.0 and hurt(e_open) > 0.0,
		"벽 뒤 %.1f · 트인 쪽 %.1f" % [hurt(e_behind), hurt(e_open)])

	st = mk({ "obstacles": [rock(PX - 60.0, PY, 20.0)] })
	st.player.face = PGeom.deg(20.0)
	var only_behind := dummy(st, PX - 120.0, PY)
	fx = cast_now(st)
	ok("벽 뒤 적만 있으면 그쪽으로 돌지 않고 마지막 방향(20도)으로 나간다",
		is_equal_approx(float(fx.angle), PGeom.deg(20.0)) and hurt(only_behind) == 0.0,
		"각 %.1f도" % dg(float(fx.angle)))

	st = mk()
	st.player.face = PGeom.deg(-45.0)
	var e_struct := dummy_at(st, 90.0, 0.0, "elite_rubble")
	fx = cast_now(st)
	ok("구조물(잔해)은 조준 대상이 아니다 — 마지막 방향(-45도)으로 나간다",
		bool(e_struct.get("structure", false)) and is_equal_approx(float(fx.angle), PGeom.deg(-45.0)),
		"각 %.1f도" % dg(float(fx.angle)))

	st = mk()
	var e_air := dummy_at(st, 90.0, 0.0)
	e_air.airborne = true
	var e_ground := dummy_at(st, 150.0, 180.0)
	fx = cast_now(st)
	ok("공중에 뜬 적(밀어낼 수 없다)을 두고 땅에 있는 먼 적을 고른다",
		near_ang(float(fx.angle), want_ang(fx, e_ground)) and hurt(e_ground) > 0.0,
		"각 %.1f도" % dg(float(fx.angle)))

	# ---------- ⑤ 표시와 판정이 같은 각을 쓴다 ----------
	print("\n[5] 표시 = 판정")
	st = mk({ "obstacles": [rock(PX - 70.0, PY - 70.0, 22.0)] })
	var ring := []
	for i in 12:
		ring.append(dummy_at(st, 90.0 + 8.0 * float(i), float(i) * 30.0))
	var snap := []
	for e in ring:
		snap.append([float(e.x), float(e.y), float(e.r)])
	var aim_before := PSkills.gust_angle(st)
	var px0: float = st.player.x
	var py0: float = st.player.y
	fx = cast_now(st)
	var mismatch := 0
	for i in ring.size():
		var s: Array = snap[i]
		var drawn: bool = PGeom.in_beam(float(fx.x), float(fx.y), float(fx.angle), float(fx["len"]), float(fx["w"]), float(s[0]), float(s[1]), float(s[2]))
		if drawn:
			drawn = not st.los_blocked(float(fx.x), float(fx.y), float(s[0]), float(s[1]))
		if drawn != (hurt(ring[i]) > 0.0):
			mismatch += 1
	ok("적 12마리 중 '그려진 부채꼴 안'과 '실제로 맞은 적'이 한 마리도 어긋나지 않는다", mismatch == 0, "어긋남 %d마리" % mismatch)
	ok("표시 부채꼴의 자리·길이·폭이 판정과 같다(자리 = 사용 순간의 플레이어)",
		is_equal_approx(float(fx.x), px0) and is_equal_approx(float(fx.y), py0)
		and is_equal_approx(float(fx["len"]), PSkills.GUST_LEN) and is_equal_approx(float(fx["w"]), PSkills.GUST_W))
	ok("표시 부채꼴의 각이 조준 함수가 고른 각과 정확히 같다",
		is_equal_approx(float(fx.angle), aim_before), "표시 %.5f · 조준 %.5f" % [float(fx.angle), aim_before])

	st = mk({ "level": 3, "variant": "windpath" })
	var e_wp := dummy_at(st, 120.0, 180.0)
	fx = step_cast(st, 1.0, 0.0)
	var zone_off := 0
	var zone_n := 0
	for z in st.zones:
		if String(z.type) != "windpath":
			continue
		if PGeom.dist(float(z.x), float(z.y), float(fx.x), float(fx.y)) <= 5.0:
			continue                                          # 첫 조각은 발사 자리라 방향이 없다
		zone_n += 1
		if not near_ang(atan2(float(z.y) - float(fx.y), float(z.x) - float(fx.x)), float(fx.angle), 2.0):
			zone_off += 1
	ok("바람길(변형)의 바람 자리도 이동 방향이 아니라 같은 조준각 위에 놓인다",
		zone_n > 0 and zone_off == 0 and near_ang(float(fx.angle), want_ang(fx, e_wp)),
		"자리 %d개 중 어긋남 %d개 · 각 %.1f도" % [zone_n, zone_off, dg(float(fx.angle))])

	# ---------- ⑥ 이번 수정에서 바뀌지 않은 값 ----------
	print("\n[6] 거리·폭·피해·재사용 불변")
	ok("부채꼴 거리 170 · 폭 120 그대로",
		is_equal_approx(PSkills.GUST_LEN, 170.0) and is_equal_approx(PSkills.GUST_W, 120.0),
		"%.1f · %.1f" % [PSkills.GUST_LEN, PSkills.GUST_W])
	ok("자료값 피해 10/14/18 · 재사용 8/7/6초 그대로",
		float(dmg_tab[0]) == 10.0 and float(dmg_tab[1]) == 14.0 and float(dmg_tab[2]) == 18.0
		and float(cd_tab[0]) == 8.0 and float(cd_tab[1]) == 7.0 and float(cd_tab[2]) == 6.0,
		"피해 %s · 재사용 %s" % [str(dmg_tab), str(cd_tab)])

	for lv in [1, 2, 3]:
		var s3 := mk({ "level": lv })
		var t3 := dummy(s3, PX + 100.0, PY)
		cast_now(s3)
		var want_push := 140.0 + 30.0 * float(lv - 1)
		ok("Lv%d: 한 대 피해 %.0f · 재사용 %.0f초 · 밀어낸 거리 %.0f" % [lv, float(dmg_tab[lv - 1]), float(cd_tab[lv - 1]), want_push],
			is_equal_approx(hurt(t3), float(dmg_tab[lv - 1])) and is_equal_approx(float(s3.player.e_cd), float(cd_tab[lv - 1]))
			and is_equal_approx(float(t3.x) - (PX + 100.0), want_push),
			"피해 %.2f · 재사용 %.2f · 밀림 %.2f" % [hurt(t3), float(s3.player.e_cd), float(t3.x) - (PX + 100.0)])

	var s4 := mk()
	var lined := []
	for i in 5:
		lined.append(dummy(s4, PX + 30.0 + 30.0 * float(i), PY))
	cast_now(s4)
	var hit_n := 0
	for e in lined:
		if hurt(e) > 0.0:
			hit_n += 1
	ok("한 줄로 선 5마리(30~150px)가 한 번에 모두 부채꼴에 들어온다(범위가 좁아지지 않았다)", hit_n == 5, "%d마리" % hit_n)

	# ---------- ⑦ PC·모바일 같은 규칙 ----------
	print("\n[7] PC · 모바일")
	var pc := mk()
	var pc_e := dummy_at(pc, 120.0, 150.0)
	var pc_fx := step_cast(pc, 1.0, 0.0)                      # 키보드·패드: 8방향(오른쪽)
	var mb := mk()
	var mb_e := dummy_at(mb, 120.0, 150.0)
	var mb_fx := step_cast(mb, 0.6427, -0.766)                # 모바일 가상 스틱: 연속값(위 오른쪽 50도)
	ok("같은 배치라면 키보드 8방향이든 모바일 가상 스틱 연속값이든 같은 적을 겨눈다(조준 버튼을 새로 만들지 않았다)",
		near_ang(float(pc_fx.angle), want_ang(pc_fx, pc_e)) and near_ang(float(mb_fx.angle), want_ang(mb_fx, mb_e))
		and not near_ang(float(pc.player.face), float(mb.player.face), 5.0),
		"PC %.2f도 · 모바일 %.2f도 (face는 %.0f도 대 %.0f도로 다르다)" % [
			dg(float(pc_fx.angle)), dg(float(mb_fx.angle)), dg(float(pc.player.face)), dg(float(mb.player.face))])

	# ---------- ⑧ 용어 사전이 바뀐 규칙을 적는다 ----------
	print("\n[8] 설명")
	var gl: Dictionary = PCatalog.glossary().get("e:gust", {})
	var txt := String(gl.get("short", "")) + " " + String(gl.get("body", ""))
	ok("용어 사전이 자동 조준과 '적이 없으면 바라보던 방향'을 적고 길이·폭은 그대로 적는다",
		txt.find("가까운 적") >= 0 and txt.find("바라보던 방향") >= 0 and txt.find("170") >= 0 and txt.find("120") >= 0)

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
