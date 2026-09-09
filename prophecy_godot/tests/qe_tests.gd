extends SceneTree
## 수동 기술 Q/E 구조(§7) · 보유 조건과 보상(§8) · 감속장의 적 투사체 감속(§9) · 결투 연속 처리(KD-12) 검사(화면 없음).
## 실행: python tools/run_suites.py --suites qe_tests --jobs 1
##
## 무엇을 못박는가
##  §7  ① Q와 E는 **같은 6종**을 공유한다(감속장·돌풍·칼날 폭풍·낙뢰·중력핵·수호 결계)
##      ② 시작은 고른 기술 1개가 **Q에 Lv1**, E는 **빈칸**. 감속장을 강제로 지급하지 않는다
##      ③ 이미 Q에 가진 기술은 E 신규 후보에서 빠진다(후보 생성·선택 확정·상점 교체 모두)
##      ④ 재사용·성장·변형·통계는 **그 칸에 든 기술**을 기준으로 처리한다
##      ⑤ 감속장도 E로 얻을 수 있다
##      ⑥ 옛 저장(q.id가 없던 시절)은 감속장으로 되살아나고 레벨·변형이 보존된다
##  §8  감속장 없음 / Q에 있음 / E에 있음 / 교환으로 사라짐 네 경우의 보상 자격
##      + 자격 때문에 후보가 줄어도 3택이 비지 않는다 · 정상 소진과 생성 오류를 가른다
##      + 이미 가진 장비·증강을 지우지 않고 **미충족 상태를 설명**한다
##  §9  감속장 안 적 투사체 40% · 밖은 원래 속도 · 겹쳐도 1회 · 사거리 보존 · 아군 투사체 그대로
##      + 사슬 집행자의 사슬은 투사체 목록을 쓰지 않는다(적용 여부를 여기서 명시한다)
##  KD-12 결투가 예정된 만큼 **차례로** 나온다(동시 등장 없음) · 총 등장 수·경험치 예산 불변
##
## 여기 수치는 전부 기존 자료값이며 이 검사에서 새로 정한 밸런스가 아니다.

const STEP := 1.0 / 120.0
const MAX_SEC := 240.0

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 시험실 ----------
## Q·E에 원하는 기술을 넣은 성장 dict. e_id가 ""면 E는 빈칸
func growth_of(q_id: String, e_id: String = "", weapon: String = "sword") -> Dictionary:
	var g := PGrowth.new_growth(weapon, q_id)
	if e_id != "":
		g.skills.e = { "id": e_id, "level": 1, "variant": null }
	return g

## 실제 회차 dict(금화·상점·장비 칸이 있는 것). 교체·상점 견적도 같은 것을 쓴다
func run_of(q_id: String, e_id: String = "", weapon: String = "sword") -> Dictionary:
	var r := PRun.new_run(1, weapon)
	r.growth.skills.q = { "id": q_id, "level": 1, "variant": null }
	r.growth.skills.e = { "id": e_id, "level": 1, "variant": null } if e_id != "" else null
	return r

## 적이 저절로 나오지 않는 빈 전장(자동공격도 끈다 — 무엇이 원인인지 갈라지게)
func mk(q_id: String, e_id: String = "", weapon: String = "sword") -> CombatState:
	var b := PBuild.derive(run_of(q_id, e_id, weapon))
	var st := CombatState.new({ "build": b, "seed": 1, "arena": "clearing",
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.player.x = 480.0
	st.player.y = 300.0
	st.player.attack_timer = 1.0e8
	return st

func dummy(st: CombatState, x: float, y: float, type_id: String = "wolf") -> Dictionary:
	var e := st.spawn_enemy(type_id, x, y)
	e.hp = 99999.0
	e.hp_max = 99999.0
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

## 후보 종류별 개수
func kinds_of(run: Dictionary) -> Dictionary:
	var out := {}
	for c in PGrowth.candidates(run, { "pool": "level" }):
		out[String(c.kind)] = int(out.get(c.kind, 0)) + 1
	return out

func has_candidate(run: Dictionary, kind: String, id: String) -> bool:
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if String(c.kind) == kind and String(c.id) == id:
			return true
	return false

## 적 투사체 한 발(적 코드가 실제로 만드는 모양 그대로)
func enemy_shot(x: float, y: float, vx: float, ttl_v: float = 4.0) -> Dictionary:
	return { "owner": "enemy", "kind": "arrow", "shooter": null, "x": x, "y": y, "vx": vx, "vy": 0.0,
		"r": 4.0, "dmg": 0.0, "ttl": ttl_v, "angle": 0.0, "dead": false, "hits": {} }

func player_shot(x: float, y: float, vx: float, ttl_v: float = 4.0) -> Dictionary:
	return { "owner": "player", "kind": "test_shot", "x": x, "y": y, "vx": vx, "vy": 0.0,
		"r": 4.0, "dmg": 0.0, "ttl": ttl_v, "angle": 0.0, "dead": false, "hits": {}, "weapon": null }

## 감속장을 손으로 편다(기술 발동 경로를 거치지 않고 기하만 만든다)
func put_field(st: CombatState, x: float, y: float, r: float = 150.0) -> void:
	st.field = { "x": x, "y": y, "r": r, "ttl": 99.0, "max_ttl": 99.0, "follow": false }

# ================================================================
func _init() -> void:
	print("# qe_tests")

	# ================= §7 구조 =================
	print("\n[1] Q/E가 같은 6종을 공유한다")
	var ids := PGrowth.manual_skill_ids()
	var SK := PCatalog.skills()
	var want := ["slowfield", "gust", "bladestorm", "strike", "gravity", "ward"]
	var all_there := true
	for w in want:
		if not ids.has(w) or not SK.has(w) or not bool(SK[w].impl):
			all_there = false
	ok("수동 기술 목록이 6종이고 감속장이 그 안에 있다", ids.size() == 6 and all_there, str(ids))

	var g_def := PGrowth.new_growth("sword")
	ok("도구·봇처럼 고르지 않는 경로의 기본값은 예전 그대로 Q 감속장 · E 빈칸(기준 전투 보존)",
		String(g_def.skills.q.id) == "slowfield" and int(g_def.skills.q.level) == 1 and g_def.skills.get("e") == null)
	var g_pick := PGrowth.new_growth("sword", "gust")
	ok("고른 기술이 Q에 Lv1으로 들어간다 · E는 빈칸 · 감속장을 강제로 주지 않는다",
		String(g_pick.skills.q.id) == "gust" and int(g_pick.skills.q.level) == 1 and g_pick.skills.get("e") == null and not PGrowth.has_skill(g_pick, "slowfield"))

	print("\n[2] 재사용 시계는 칸, 내용은 기술")
	var b_gust := PBuild.derive(run_of("gust"))
	var b_slow := PBuild.derive(run_of("slowfield"))
	ok("Q 재사용은 **그 칸의 기술 표**를 읽는다(돌풍 Lv1 = 8초, 감속장 Lv1 = 14초)",
		is_equal_approx(float(b_gust.special_cd), 8.0) and is_equal_approx(float(b_slow.special_cd), 14.0),
		"%s / %s" % [str(b_gust.special_cd), str(b_slow.special_cd)])

	var st_qe := mk("gust", "slowfield")
	dummy(st_qe, 560.0, 300.0)
	var cast_q_ok: bool = PSkills.cast(st_qe, "q")
	var gust_fx := false
	for f in st_qe.effects:
		if String(f.get("kind", "")) == "gust":
			gust_fx = true
	ok("Q에 공격기(돌풍)를 두면 Q 입력으로 돌풍이 나가고 Q 시계가 8초로 찬다",
		cast_q_ok and gust_fx and is_equal_approx(float(st_qe.player.special_cd), 8.0), "%s" % str(st_qe.player.special_cd))
	var cast_e_ok: bool = PSkills.cast(st_qe, "e")
	ok("**감속장도 E로 얻어 쓸 수 있다** — E 입력으로 장이 펴지고 E 시계가 14초로 찬다",
		cast_e_ok and not st_qe.field.is_empty() and is_equal_approx(float(st_qe.field.r), 150.0) and is_equal_approx(float(st_qe.player.e_cd), 14.0),
		"field %s · e_cd %s" % [str(st_qe.field.get("r", 0)), str(st_qe.player.e_cd)])
	ok("두 칸의 시계는 서로 독립이다(하나를 써도 다른 칸이 줄지 않는다)",
		is_equal_approx(float(st_qe.player.special_cd), 8.0) and is_equal_approx(float(st_qe.player.e_cd), 14.0))
	ok("통계 출처는 칸이 아니라 기술이다: 감속장은 skill:q, 돌풍은 skill:gust",
		PStats.skill_key("slowfield") == "skill:q" and PStats.skill_key("gust") == "skill:gust" and String(PStats.classify("skill:q").name) == "감속장" and String(PStats.classify("skill:gust").name) == "돌풍")

	# 감속장 변형(잔향)이 E에 있어도 동작한다 — 종료 처리도 칸을 찾아간다
	var st_echo := mk("gust", "slowfield")
	st_echo.build.skills.e.variant = "echo"
	PSkills.cast(st_echo, "e")
	st_echo.field.ttl = 0.001
	st_echo.step({}, STEP)
	var echo_zone := false
	for z in st_echo.zones:
		if String(z.type) == "slowecho":
			echo_zone = true
	ok("감속장 변형(시간의 잔향)이 **E에 있어도** 종료 뒤 잔향 지대를 남긴다", echo_zone and st_echo.field.is_empty())

	print("\n[3] 이미 가진 기술은 다시 나오지 않는다")
	var r_gust := run_of("gust")
	ok("Q가 돌풍이면 신규 후보에 돌풍이 없고 나머지 5종은 있다(감속장 포함)",
		not has_candidate(r_gust, "skill_new", "gust") and has_candidate(r_gust, "skill_new", "slowfield") and int(kinds_of(r_gust).get("skill_new", 0)) == 5,
		str(kinds_of(r_gust)))
	var dup_ok := PGrowth.apply_choice(r_gust, { "kind": "skill_new", "id": "gust" }, true)
	ok("확정 단계에서도 같은 기술을 두 칸에 두지 않는다(후보를 지나 들어와도 거부)", not dup_ok and r_gust.growth.skills.get("e") == null)
	var take_ok := PGrowth.apply_choice(r_gust, { "kind": "skill_new", "id": "slowfield" })
	ok("E에 감속장을 실제로 장착할 수 있다", take_ok and String(r_gust.growth.skills.e.id) == "slowfield")
	var sq := PRun.swap_quote(r_gust, "e", 0)
	ok("상점 기술 교체 후보에도 Q에 가진 기술(돌풍)이 나오지 않는다",
		not (sq.options as Array).has("gust") and not (sq.options as Array).has("slowfield") and (sq.options as Array).size() == 4, str(sq.options))

	print("\n[4] 성장은 칸별로, 해금은 기술별로")
	var r_lv := run_of("gust", "slowfield")
	var lv_ok := PGrowth.apply_choice(r_lv, { "kind": "skill_level", "id": "gust", "slot": "q" })
	var lv_ok2 := PGrowth.apply_choice(r_lv, { "kind": "skill_level", "id": "slowfield", "slot": "e" })
	ok("칸마다 따로 레벨이 오른다(Q 돌풍 2 · E 감속장 2)",
		lv_ok and lv_ok2 and int(r_lv.growth.skills.q.level) == 2 and int(r_lv.growth.skills.e.level) == 2)
	var v_ok := PGrowth.apply_choice(r_lv, { "kind": "skill_variant", "id": "slowfield", "slot": "e", "variant": "follow" })
	ok("감속장 변형은 **E에 있어도** 감속장 변형 해금표를 그대로 쓴다",
		v_ok and String(r_lv.growth.skills.e.variant) == "follow" and PGrowth.variant_unlock_cat("slowfield") == "q_variants" and PGrowth.variant_unlock_cat("gust") == "e_variants")
	var b_lv := PBuild.derive(r_lv)
	ok("올린 레벨이 재사용에 반영된다(돌풍 Lv2 = 7초 · 감속장 Lv2 = 12초)",
		is_equal_approx(float(b_lv.special_cd), 7.0) and is_equal_approx(PBuildDetail.cd_of_build(b_lv, "e"), 12.0),
		"%s / %s" % [str(b_lv.special_cd), str(PBuildDetail.cd_of_build(b_lv, "e"))])

	print("\n[5] 옛 저장 보존")
	# 옛 저장에는 growth.q에 id가 없었다(감속장 고정이었다). 레벨·변형은 그대로 살아나야 한다
	var old_q := { "level": 3, "variant": "follow" }
	var restored := { "id": String(old_q.get("id", "slowfield")), "level": int(old_q.get("level", 1)), "variant": old_q.get("variant", null) }
	ok("옛 저장의 Q(감속장 Lv3 · 동행하는 시간)는 id가 없어도 감속장으로 되살아나고 레벨·변형이 보존된다",
		String(restored.id) == "slowfield" and int(restored.level) == 3 and String(restored.variant) == "follow")
	var g_old := PGrowth.new_growth("sword")
	g_old.skills.q = restored
	g_old.skills.e = { "id": "ward", "level": 2, "variant": "pulse" }
	var b_old := PBuild.derive(PBuild.empty_run_like(g_old))
	ok("옛 저장 그대로 계산하면 예전과 같은 값이 나온다(감속장 Lv3 = 10초 · 결계 Lv2 = 12초)",
		is_equal_approx(float(b_old.special_cd), 10.0) and is_equal_approx(PBuildDetail.cd_of_build(b_old, "e"), 12.0),
		"%s / %s" % [str(b_old.special_cd), str(PBuildDetail.cd_of_build(b_old, "e"))])

	# ================= §8 보유 조건과 보상 =================
	print("\n[6] 감속장 없음 / Q에 있음 / E에 있음 / 교환으로 사라짐")
	var cases := [
		["감속장 없음", run_of("gust", "ward", "bow"), false],
		["Q에 있음", run_of("slowfield", "ward", "bow"), true],
		["E에 있음", run_of("gust", "slowfield", "bow"), true],
	]
	for row in cases:
		var label := String(row[0])
		var rr: Dictionary = row[1]
		var want_ok: bool = bool(row[2])
		var saving := has_candidate(rr, "common", "saving")
		var stasis := has_candidate(rr, "common", "stasis")
		var clone := PGrowth.boss_reward_applies(rr.growth, "clone")
		var why := PGrowth.equip_inactive_reason(rr.growth, "chrono_staff")
		ok("[%s] 감속장 전용 증강(시간 저축·정지된 칼날)·희귀 보상(시간의 복제)·시간술사의 지팡이 자격 = %s" % [label, "있음" if want_ok else "없음"],
			saving == want_ok and stasis == want_ok and clone == want_ok and ((why == "") == want_ok),
			"저축 %s · 칼날 %s · 복제 %s · 지팡이 사유 '%s'" % [str(saving), str(stasis), str(clone), why])

	# 교환으로 사라짐: E의 감속장을 다른 기술로 바꾼다(가진 증강·장비는 지우지 않는다)
	var r_sw := run_of("gust", "slowfield", "bow")
	r_sw.growth.commons["saving"] = 1
	r_sw.equipment.weapon = "chrono_staff"
	r_sw.gold = 9999
	var swapped := PRun.apply_swap(r_sw, "e", 0, "ward")
	ok("[교환으로 사라짐] E의 감속장을 수호 결계로 바꿀 수 있다", swapped >= 0 and String(r_sw.growth.skills.e.id) == "ward")
	ok("[교환으로 사라짐] 이미 가진 '시간 저축'과 시간술사의 지팡이를 **지우지 않는다**",
		int(r_sw.growth.commons.get("saving", 0)) == 1 and String(r_sw.equipment.weapon) == "chrono_staff")
	ok("[교환으로 사라짐] 그 대신 지금은 효과가 없다고 **설명한다** · 새 후보에서도 감속장 전용은 빠진다",
		PGrowth.equip_inactive_reason(r_sw.growth, "chrono_staff") != "" and not has_candidate(r_sw, "common", "stasis") and not PGrowth.boss_reward_applies(r_sw.growth, "clone"))
	ok("[교환으로 사라짐] 감속장은 다시 얻을 수 있는 후보로 되돌아온다(E 교체 후보에 있음)",
		(PRun.swap_quote(r_sw, "e", 0).options as Array).has("slowfield"))

	print("\n[7] 자격 때문에 3택이 비지 않는다 · 정상 소진과 오류를 가른다")
	var r_off := run_of("gust", "ward", "bow")
	r_off.seed = 7
	r_off.growth.level = 3
	var off := PGrowth.generate_offer(r_off, { "pool": "level" })
	ok("감속장이 없어도 레벨업 3택은 3장이 나오고 사유는 'ok'다(빈 창의 계속 버튼이 아니다)",
		(off.choices as Array).size() == 3 and String(off.reason) == "ok", "%d장 · %s" % [(off.choices as Array).size(), String(off.reason)])
	var slow_only := false
	for c in off.choices:
		if String(c.kind) == "common" and String(c.id) in ["saving", "stasis"]:
			slow_only = true
	ok("그 3택에 감속장 전용 증강이 섞이지 않는다", not slow_only)
	var r_err := run_of("gust", "ward", "bow")
	var er := PGrowth.empty_reason(r_err, { "pool": "mission", "kinds": ["nonexistent_kind"] }, 0, 0)
	ok("알 수 없는 보상 종류는 **생성 오류**로 구분된다(정상 소진이 아니다)", String(er.code) == "error", str(er))
	var er2 := PGrowth.empty_reason(r_err, { "pool": "level" }, 0, 0)
	ok("자료가 있는데 후보만 다 떨어진 경우는 **정상 소진**이다", String(er2.code) == "exhausted", str(er2))

	# ================= §9 감속장의 적 투사체 감속 =================
	print("\n[8] 감속장 안의 적 투사체는 40%")
	var sp := 200.0
	var st_in := mk("slowfield")
	put_field(st_in, 300.0, 100.0)
	st_in.projectiles.append(enemy_shot(300.0, 100.0, sp))
	var x0_in: float = float(st_in.projectiles[0].x)
	var ttl0_in: float = float(st_in.projectiles[0].ttl)
	st_in.update_projectiles(STEP)
	var d_in: float = float(st_in.projectiles[0].x) - x0_in
	var dttl_in: float = ttl0_in - float(st_in.projectiles[0].ttl)

	var st_out := mk("slowfield")
	st_out.projectiles.append(enemy_shot(300.0, 100.0, sp))
	var x0_out: float = float(st_out.projectiles[0].x)
	st_out.update_projectiles(STEP)
	var d_out: float = float(st_out.projectiles[0].x) - x0_out
	ok("장 안의 적 투사체는 원래 속도의 40%다", absf(d_in - d_out * 0.4) < 1e-6, "안 %.5f / 밖 %.5f" % [d_in, d_out])
	ok("느려지면 수명도 같은 비율로 흐른다(사거리가 줄지 않는다)", absf(dttl_in - STEP * 0.4) < 1e-9, "%.6f" % dttl_in)

	# 겹친 감속장(분할 변형의 두 번째 장까지 같은 자리) — 중복 적용 없음
	var st_ov := mk("slowfield")
	put_field(st_ov, 300.0, 100.0)
	st_ov.skill_state.field2 = { "x": 300.0, "y": 100.0, "r": 100.0, "ttl": 99.0, "max_ttl": 99.0 }
	st_ov.projectiles.append(enemy_shot(300.0, 100.0, sp))
	var x0_ov: float = float(st_ov.projectiles[0].x)
	st_ov.update_projectiles(STEP)
	var d_ov: float = float(st_ov.projectiles[0].x) - x0_ov
	ok("감속장이 겹쳐도 감속은 한 번만 적용된다(0.4이지 0.16이 아니다)", absf(d_ov - d_in) < 1e-9, "겹침 %.5f / 하나 %.5f" % [d_ov, d_in])

	# 장을 나오면 곧바로 원래 속도
	var st_exit := mk("slowfield")
	put_field(st_exit, 100.0, 100.0, 60.0)
	st_exit.projectiles.append(enemy_shot(100.0, 100.0, sp))
	var seq := []
	for i in 240:
		var xb: float = float(st_exit.projectiles[0].x)
		st_exit.update_projectiles(STEP)
		if st_exit.projectiles.is_empty():
			break
		seq.append(float(st_exit.projectiles[0].x) - xb)
	var slow_first: bool = seq.size() > 5 and absf(float(seq[0]) - d_out * 0.4) < 1e-6
	var fast_last: bool = seq.size() > 5 and absf(float(seq[seq.size() - 1]) - d_out) < 1e-6
	ok("장을 벗어나면 원래 속도로 돌아온다(들어갈 때만 느리다)", slow_first and fast_last,
		"첫 %.5f / 끝 %.5f / 기준 %.5f" % [float(seq[0]) if seq.size() > 0 else 0.0, float(seq[seq.size() - 1]) if seq.size() > 0 else 0.0, d_out])

	# 사거리 보존: ttl = 사거리/속도로 정한 투사체(보스 파동 모양)가 장 안에서도 같은 거리를 난다
	var reach := func(inside: bool) -> float:
		var s := mk("slowfield")
		if inside:
			put_field(s, 300.0, 100.0, 4000.0) # 경로 전체를 덮는 장
		s.projectiles.append(enemy_shot(300.0, 100.0, sp, 300.0 / sp))
		var start: float = 300.0
		var last: float = 300.0
		for i in 4000:
			if s.projectiles.is_empty():
				break
			last = float(s.projectiles[0].x)
			s.update_projectiles(STEP)
		return last - start
	var reach_in: float = reach.call(true)
	var reach_out: float = reach.call(false)
	ok("수명이 사거리로 정해진 투사체는 감속장 안에서도 **같은 거리**를 난다", absf(reach_in - reach_out) < 1.0,
		"안 %.1f / 밖 %.1f" % [reach_in, reach_out])

	# 아군 투사체는 그대로
	var st_pl := mk("slowfield")
	put_field(st_pl, 300.0, 100.0)
	st_pl.projectiles.append(player_shot(300.0, 100.0, sp))
	var x0_pl: float = float(st_pl.projectiles[0].x)
	st_pl.update_projectiles(STEP)
	var d_pl: float = float(st_pl.projectiles[0].x) - x0_pl
	ok("**아군 투사체는 감속하지 않는다**", absf(d_pl - d_out) < 1e-9, "%.5f / %.5f" % [d_pl, d_out])

	# 즉시 판정·바닥 지대는 투사체가 아니다(투사체 목록에 들어가지 않는다)
	var st_zone := mk("slowfield")
	st_zone.add_zone("spore", 300.0, 100.0, 40.0, 2.0, 5.0)
	ok("바닥 지대·즉시 판정은 투사체로 취급하지 않는다(투사체 목록이 비어 있다)", st_zone.projectiles.is_empty() and st_zone.zones.size() == 1)

	# 사슬 집행자: 사슬은 투사체 목록을 쓰지 않는다 — 이 규칙의 적용 대상이 아니다
	var st_ch := mk("slowfield")
	var ch := dummy(st_ch, 620.0, 300.0, "elite_chainbreaker")
	ch.state = "chain_lock"
	ch.state_t = 99.0
	ch.dir = PI
	ch.chain_len = 260.0
	ch.chain_d = 0.0
	var chain_proj := 0
	for i in 60:
		st_ch.step({}, STEP)
		chain_proj += st_ch.projectiles.size()
	ok("사슬 집행자의 사슬은 **투사체가 아니다**(projectiles에 없다) — 투사체 감속 규칙의 대상이 아니며 시전자 기준 시간 배율만 받는다",
		chain_proj == 0, "투사체 %d발" % chain_proj)

	# ================= KD-12 결투 연속 처리 =================
	print("\n[9] 결투가 예정된 수만큼 차례로 나온다")
	var st_d := mk("slowfield")
	var f := PFormation.from_waves([[{ "type": "wolf", "n": 1 }], [{ "type": "elite_fang", "n": 1, "duel": true }], [{ "type": "elite_standard", "n": 1, "duel": true }]], {}, "forest", st_d)
	ok("편성이 결투 상대 2명을 순서대로 넘긴다(대기열에는 넣지 않는다)",
		(f.duels as Array).size() == 2 and String(f.duel.type) == "elite_fang" and not (f.units as Array).has("elite_fang"),
		str(f.duels))
	st_d.set_formation(f)
	st_d.spawn_hold = false
	var seen := []            # 등장한 결투 상대 종류(순서)
	var max_duel_alive := 0
	var n := 0
	while st_d.status == "running" and n < int(MAX_SEC / STEP):
		st_d.step({}, STEP)
		st_d.player.hp = st_d.player.hp_max
		st_d.player.dead = false
		n += 1
		# 지금 화면에 있는 결투 상대를 적어 둔다(같은 상대가 이어지면 한 번만)
		var alive_duel := 0
		for e in st_d.enemies:
			if e.dead or not bool(e.get("duel_boss", false)):
				continue
			alive_duel += 1
			var tp := String(e.type)
			if seen.is_empty() or String(seen[seen.size() - 1]) != tp:
				seen.append(tp)
		max_duel_alive = maxi(max_duel_alive, alive_duel)
		# 시험 진행용: 살아 있는 적을 그 자리에서 처치한다(전투 실력이 아니라 흐름을 본다)
		for e in st_d.enemies:
			if not e.dead:
				st_d.damage_enemy(e, 99999.0)
	ok("**두 번째 결투 상대가 실제로 나온다**(KD-12): 등장 순서 = 편성 순서", seen == ["elite_fang", "elite_standard"], str(seen))
	ok("1대1 원칙 유지: 결투 상대가 동시에 둘 이상 살아 있지 않는다", max_duel_alive <= 1, "최대 %d" % max_duel_alive)
	ok("둘을 다 쓰러뜨려야 승리다 · 결투 처리 수 2", String(st_d.status) == "won" and String(st_d.duel_stage) == "done" and int(st_d.stats.get("duels_done", 0)) == 2,
		"%s/%s/%d" % [String(st_d.status), String(st_d.duel_stage), int(st_d.stats.get("duels_done", 0))])
	ok("총 등장 수·경험치 예산은 편성이 정한 그대로다(결투 상대는 대기열 밖이라 spawn_total이 늘지 않는다)",
		int(st_d.spawn_total) == (f.units as Array).size() and (f.xp_map as Dictionary).has("elite_fang") and (f.xp_map as Dictionary).has("elite_standard"),
		"spawn_total %d / units %d" % [int(st_d.spawn_total), (f.units as Array).size()])

	# 실제 3막 위험 편성에도 결투 상대가 2명 예정돼 있다
	var route := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), "act3_temporal_abyss"]
	var run3 := PRun.new_run(5, "sword", "", { "route": route })
	run3.day = 9
	run3.stage = 2
	var o3 := PFlow.encounter_opts(run3, { "regionId": "t3a_rim", "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 },
		"encounters": 0, "seed": 41, "day": 9, "slot": 0, "variant": null, "formationId": "t3a_risk", "duelType": "" })
	var st3 := CombatState.new(o3)
	ok("3막 위험 편성(t3a_risk)은 특수 정예 2종을 결투로 예정한다 — 이제 둘 다 나온다",
		(st3.duel_queue as Array).size() == 2 and String(st3.duel_type) == String((st3.duel_queue[0] as Dictionary).type),
		str(st3.duel_queue))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
