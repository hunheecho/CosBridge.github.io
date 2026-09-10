extends SceneTree
## **장비 기술 6종을 하나씩 실제로 발동시켜 효과가 드러나는지 값으로 본다.**
## 실행: python tools/run_suites.py --suites eq_fire_tests --jobs 1
##
## 이 검사가 무엇인지 먼저 못박는다 — **규칙 호출 검사다. 화면 버튼을 누르지 않는다.**
## 화면 버튼 경로는 tests/ui_chain_tests.gd · tests/bank_ui_tests.gd · tests/equip_ui_tests.gd 가 본다.
## 여기서 하는 것은 전투 규칙(PSkills.cast · PSkills.eq_take_input · PSkills.eq_update)을 직접 부르는 일이다.
##
## 왜 생겼는가 — 사용자 지적(2026-09-10):
##   "결정 관 한 종의 **빈 전장** 발동만으로 6종 전투 검증을 대신하지 마라.
##    6종 각각을 효과가 실제로 드러나는 장면에서, **적을 세워 놓고** 확인해라."
## 그때까지 equip_chain_tests 의 [6]은 적이 없는 전장에서 결정 관 하나만 눌러 보고
## "발동했다 · 재사용 시계가 돈다"만 봤다. 무엇을 맞혔는지·무엇이 바뀌었는지는 아무도 안 봤다.
##
## 6종과 '효과가 드러나는 장면'
##   [4] eq_flashcut 찰나 가르기 — 앞의 적을 베고 순간 이동한다      → 적 체력 감소 + 사람 좌표 이동
##   [5] eq_meteor   낙성 강하   — 착탄점 중심/바깥이 갈린다          → 중심 적과 바깥 적의 피해가 다르다
##   [6] eq_riposte  받아치기    — 정면 공격을 막고 되받아친다        → 사람 체력 그대로 + 적 체력 감소
##   [7] eq_retrace  되짚는 궤적 — 지나온 길로 돌아온다              → 사람이 출발점으로 · 길 위의 적이 맞는다
##   [8] eq_icetomb  결정 관     — 갇혀서 피해를 막고 냉기를 준다      → 갇힘 중 피해 0 + 해제 뒤 적 냉기 중첩
##   [9] eq_reprieve 유예의 시계 — 피해를 미뤘다가 정산한다          → 즉시 체력 감소가 줄고 뒤늦게 빠진다
##
## 여기 수치는 전부 자료값(data/growth.json skills.<id>.tune·damage)이다. 이 검사가 정한 밸런스는 없다.
## 사람·봇의 승리 주장이 아니다 — 적은 전부 **움직이지 않는 표적**(물기 시계를 멈춘 늑대)이다.

const STEP := 1.0 / 120.0

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 시험실 ----------
## 그 장비 하나만 착용하고, 그 장비 기술 하나만 slot 칸에 둔 전장을 만든다.
## 자동기술·주무기 자동 발사는 꺼 둔다(장비 기술이 낸 값만 남기려고).
func lab(sid: String, equip_type: String, slot: String = "q") -> CombatState:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = []
	g.skills = { "q": null, "e": null }
	(g.skills as Dictionary)[slot] = { "id": sid, "level": 1, "variant": null }
	var run: Dictionary = PBuild.empty_run_like(g)
	var d: Dictionary = PCatalog.equipment_def(equip_type)
	(run.equipment as Dictionary)[String(d.get("slot", "weapon"))] = equip_type
	var b: Dictionary = PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1,
		"waves": [], "arena": "clearing", "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 300.0
	st.player.y = 300.0
	st.player.face = 0.0
	st.player.attack_timer = 1.0e9
	return st

## 움직이지 않는 표적. 죽지 않게 체력을 크게 준다(죽으면 목록에서 빠져 뒤 판정이 흐려진다)
func target(st: CombatState, x: float, y: float) -> Dictionary:
	var e: Dictionary = st.spawn_enemy("wolf", x, y)
	e.hp = 100000.0
	e.hp_max = 100000.0
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	e.speed = 0.0
	return e

## 진행 중인 장비 기술만 굴린다(적은 움직이지 않는다 — 이 검사는 적의 인공지능을 보지 않는다)
func advance(st: CombatState, seconds: float) -> void:
	for i in int(round(seconds / STEP)):
		PSkills.eq_update(st, STEP)

## 실제 입력 계약({special}/{skill_e})으로 그 칸을 한 번 누른다
func press(st: CombatState, slot: String) -> void:
	PSkills.eq_take_input(st, { "special": slot == "q", "skill_e": slot == "e" })

func near(a: float, b: float, tol: float = 0.05) -> bool:
	return absf(a - b) <= tol

func _init() -> void:
	sec_flashcut()
	sec_meteor()
	sec_riposte()
	sec_retrace()
	sec_icetomb()
	sec_reprieve()
	var pass_n := 0
	for row in results:
		if bool(row[0]):
			pass_n += 1
	print("\n%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- [4] 찰나 가르기 — 대상 적중 ----------
func sec_flashcut() -> void:
	print("\n[4] eq_flashcut 찰나 가르기 — 앞의 적을 베고 순간 이동한다")
	var st := lab("eq_flashcut", "instant_blade", "q")
	var want := float((PCatalog.skills()["eq_flashcut"].damage as Array)[0])
	var T := PSkills.eq_tune("eq_flashcut")
	var on_path := target(st, 400.0, 300.0)   # 경로 위(앞 100)
	var off_path := target(st, 300.0, 200.0)  # 옆으로 100 — 폭 44의 절반 밖
	var hp_on: float = float(on_path.hp)
	var hp_off: float = float(off_path.hp)
	var x0: float = float(st.player.x)
	ok("착용한 장비가 이 기술을 준다", PSkills.eq_granted(st, "eq_flashcut"),
		str(st.build.equip_types))
	ok("발동한다(충전 시작)", PSkills.cast(st, "q") and String(st.eq_act.get("phase", "")) == "charge",
		str(st.eq_act.get("phase", "없음")))
	ok("충전 중에는 무적이 아니다(3절 [4])", not PSkills.eq_invuln(st))
	advance(st, 0.2)
	press(st, "q") # 같은 칸 재입력 = 놓기 → 여기서 방향이 확정되고 나간다
	var moved := float(st.player.x) - x0
	var dmg_on := hp_on - float(on_path.hp)
	var dmg_off := hp_off - float(off_path.hp)
	ok("경로 위 적이 실제로 맞았다 — 피해 %.1f(자료값 %.1f)" % [dmg_on, want], near(dmg_on, want),
		"체력 %.1f → %.1f" % [hp_on, float(on_path.hp)])
	ok("경로 밖 적은 맞지 않았다", near(dmg_off, 0.0), "피해 %.1f" % dmg_off)
	ok("사람이 앞으로 순간 이동했다 — %.1fpx(자료값 len %.1f)" % [moved, float(T.get("len", 240.0))],
		near(moved, float(T.get("len", 240.0)), 1.0), "x %.1f → %.1f" % [x0, float(st.player.x)])
	ok("나간 직후 짧은 무적이 켜진다", PSkills.eq_invuln(st), str(st.eq_act.get("phase", "없음")))
	advance(st, 0.3)
	ok("무적은 상태와 함께 사라진다(남지 않는다)", st.eq_act.is_empty() and not PSkills.eq_invuln(st))

# ---------- [5] 낙성 강하 — 착탄 적중 ----------
func sec_meteor() -> void:
	print("\n[5] eq_meteor 낙성 강하 — 착탄점 중심과 바깥이 갈린다")
	var st := lab("eq_meteor", "falling_star_maul", "q")
	var T := PSkills.eq_tune("eq_meteor")
	var want := float((PCatalog.skills()["eq_meteor"].damage as Array)[0])
	var wave_want := want * float(T.get("wave_mult", 0.35))
	var range_v := float(T.get("range", 220.0))
	var core := target(st, 300.0 + range_v, 300.0)            # 착탄점 위
	var edge := target(st, 300.0 + range_v + 120.0, 300.0)    # 착탄점에서 120 — 충격파 반경 150 안
	var far := target(st, 300.0 + range_v + 300.0, 300.0)     # 충격파 밖
	var hp_c: float = float(core.hp)
	var hp_e: float = float(edge.hp)
	var hp_f: float = float(far.hp)
	var y0: float = float(st.player.y)
	ok("발동한다(충전 시작 · 착지점을 고른다)",
		PSkills.cast(st, "q") and (st.eq_act.get("aim", []) as Array).size() == 2, str(st.eq_act.get("aim", [])))
	advance(st, 0.2)
	press(st, "q") # 놓는 순간 착지점이 확정된다
	ok("도약이 시작됐다(공중)", PSkills.eq_airborne(st), String(st.eq_act.get("phase", "없음")))
	advance(st, float(T.get("leap", 0.45)) + 0.1)
	var landed_x: float = float(st.player.x)
	var d_core := hp_c - float(core.hp)
	var d_edge := hp_e - float(edge.hp)
	var d_far := hp_f - float(far.hp)
	ok("사람이 착탄점으로 옮겨졌다 — x %.1f(자료값 사거리 %.1f)" % [landed_x, range_v],
		near(landed_x, 300.0 + range_v, 1.0), "y %.1f → %.1f" % [y0, float(st.player.y)])
	ok("중심 적이 강타를 맞았다 — %.1f(자료값 %.1f)" % [d_core, want], near(d_core, want),
		"체력 %.1f → %.1f" % [hp_c, float(core.hp)])
	ok("바깥 적은 충격파만 맞았다 — %.1f(자료값 %.1f = %.1f×%.2f)" % [d_edge, wave_want, want, float(T.get("wave_mult", 0.35))],
		near(d_edge, wave_want), "체력 %.1f → %.1f" % [hp_e, float(edge.hp)])
	ok("중심과 바깥은 배타적이다(중심 적이 충격파를 겹쳐 맞지 않았다)", d_core > d_edge and near(d_core, want))
	ok("충격파 밖 적은 맞지 않았다", near(d_far, 0.0), "피해 %.1f" % d_far)

# ---------- [6] 받아치기 — 방어(받아넘김) ----------
func sec_riposte() -> void:
	print("\n[6] eq_riposte 받아치기 — 정면 공격을 막고 되받아친다")
	var st := lab("eq_riposte", "counter_guard", "e")
	var want := float((PCatalog.skills()["eq_riposte"].damage as Array)[0])
	var front := target(st, 400.0, 300.0)   # 정면(반격 반경 130 안)
	var back := target(st, 200.0, 300.0)    # 등 뒤(반격 부채꼴 밖)
	var hp0: float = float(st.player.hp)
	var hp_f: float = float(front.hp)
	var hp_b: float = float(back.hp)
	ok("발동한다(방어 창이 열린다)", PSkills.cast(st, "e") and not st.eq_guard.is_empty(),
		"창 %.2f초" % float(st.eq_guard.get("t", 0.0)))
	var blocked: bool = not st.damage_player(12.0, "bite", front)
	ok("정면에서 온 공격을 막았다 — 사람 체력이 한 점도 안 줄었다", blocked and near(float(st.player.hp), hp0),
		"체력 %.1f → %.1f" % [hp0, float(st.player.hp)])
	var d_f := hp_f - float(front.hp)
	var d_b := hp_b - float(back.hp)
	ok("정면 적에게 반격이 들어갔다 — %.1f(자료값 %.1f)" % [d_f, want], near(d_f, want),
		"체력 %.1f → %.1f" % [hp_f, float(front.hp)])
	ok("등 뒤 적은 반격을 맞지 않았다", near(d_b, 0.0), "피해 %.1f" % d_b)
	ok("한 번 막으면 방어 창이 그 자리에서 닫힌다(반격이 두 번 나가지 않는다)", st.eq_guard.is_empty())
	ok("막은 횟수가 기록에 남는다",
		int((st.stats.equip_procs as Dictionary).get("counter_guard", 0)) == 1,
		str(st.stats.equip_procs))
	# 등 뒤에서 온 공격은 막지 않는다(막는 방향은 바라보는 쪽뿐이다)
	var st2 := lab("eq_riposte", "counter_guard", "e")
	var rear := target(st2, 200.0, 300.0)
	var hp2: float = float(st2.player.hp)
	PSkills.cast(st2, "e")
	st2.player.hit_prot = 0.0
	var hit2: bool = st2.damage_player(12.0, "bite", rear)
	ok("등 뒤에서 온 공격은 막지 못한다(체력이 줄었다)", hit2 and float(st2.player.hp) < hp2,
		"체력 %.1f → %.1f" % [hp2, float(st2.player.hp)])
	# 장판·바닥 지대는 막지 않는다
	var st3 := lab("eq_riposte", "counter_guard", "e")
	var hp3: float = float(st3.player.hp)
	PSkills.cast(st3, "e")
	var hit3: bool = st3.damage_player(9.0, "zone", null)
	ok("공격자가 없는 바닥 피해는 막지 않는다", hit3 and float(st3.player.hp) < hp3,
		"체력 %.1f → %.1f" % [hp3, float(st3.player.hp)])

# ---------- [7] 되짚는 궤적 — 이동/귀환 ----------
func sec_retrace() -> void:
	print("\n[7] eq_retrace 되짚는 궤적 — 지나온 길로 돌아온다")
	var st := lab("eq_retrace", "retrace_greaves", "q")
	var want := float((PCatalog.skills()["eq_retrace"].damage as Array)[0])
	var x0: float = float(st.player.x)
	var on_way := target(st, 400.0, 300.0)   # 지나갈 길 위
	var aside := target(st, 400.0, 200.0)    # 길에서 100 옆(적중 반경 34 밖)
	var hp_w: float = float(on_way.hp)
	var hp_a: float = float(aside.hp)
	ok("첫 입력은 기록만 시작한다(재사용을 아직 걸지 않는다)",
		PSkills.cast(st, "q") and not st.eq_trail.is_empty() and near(PSkills.cd_left(st, "q"), 0.0),
		"재사용 %.2f초" % PSkills.cd_left(st, "q"))
	# 오른쪽으로 240px 걸어간다(기록이 점을 쌓는다)
	for i in 120:
		st.player.x = float(st.player.x) + 2.0
		PSkills.eq_update(st, STEP)
	var pts: int = (st.eq_trail.get("pts", []) as Array).size()
	var x_far: float = float(st.player.x)
	ok("걸어간 길이 점으로 기록됐다 — %d점" % pts, pts >= 5, "x %.1f → %.1f" % [x0, x_far])
	press(st, "q") # 재입력 = 귀환
	ok("귀환이 시작됐다", not st.eq_act.is_empty() and String(st.eq_act.get("phase", "")) == "return",
		String(st.eq_act.get("phase", "없음")))
	ok("귀환을 시작할 때 재사용 시간이 걸린다", PSkills.cd_left(st, "q") > 0.0,
		"%.2f초" % PSkills.cd_left(st, "q"))
	advance(st, 1.5)
	var x_back: float = float(st.player.x)
	var d_w := hp_w - float(on_way.hp)
	var d_a := hp_a - float(aside.hp)
	ok("사람이 출발점으로 돌아왔다 — x %.1f → %.1f → %.1f" % [x0, x_far, x_back],
		st.eq_act.is_empty() and absf(x_back - x0) <= 8.0)
	ok("길 위의 적이 맞았다 — %.1f(자료값 %.1f)" % [d_w, want], near(d_w, want),
		"체력 %.1f → %.1f" % [hp_w, float(on_way.hp)])
	ok("길에서 벗어난 적은 맞지 않았다", near(d_a, 0.0), "피해 %.1f" % d_a)
	ok("한 번 귀환에 같은 적이 두 번 맞지 않는다", near(d_w, want), "%.1f" % d_w)

# ---------- [8] 결정 관 — 가둠 ----------
func sec_icetomb() -> void:
	print("\n[8] eq_icetomb 결정 관 — 갇혀서 막고, 풀리며 냉기를 준다")
	var st := lab("eq_icetomb", "crystal_coffin", "q")
	var T := PSkills.eq_tune("eq_icetomb")
	var inside := target(st, 300.0 + 60.0, 300.0)                       # 반경 130 안
	var outside := target(st, 300.0 + float(T.get("r", 130.0)) + 200.0, 300.0) # 밖
	var hp0: float = float(st.player.hp)
	ok("발동한다(갇힘)", PSkills.cast(st, "q") and PSkills.eq_holds_attacks(st),
		String(st.eq_act.get("id", "없음")))
	ok("갇힘 중에는 무적이다", PSkills.eq_invuln(st))
	var blocked: bool = not st.damage_player(30.0, "bite", inside)
	ok("갇힘 중 받은 공격이 체력을 깎지 못했다", blocked and near(float(st.player.hp), hp0),
		"체력 %.1f → %.1f" % [hp0, float(st.player.hp)])
	ok("갇힘 중에는 새 공격을 시작하지 않는다(자동기술 정지 표시)", PSkills.eq_holds_attacks(st))
	var chill_before := int(inside.get("chill_n", 0))
	advance(st, 0.3)
	press(st, "q") # 재입력 = 해제
	ok("해제하면 갇힘이 끝나고 무적도 그 자리에서 사라진다",
		st.eq_act.is_empty() and not PSkills.eq_invuln(st))
	var chill_after := int(inside.get("chill_n", 0))
	ok("반경 안 적에게 냉기 중첩이 붙었다 — %d → %d(자료값 chill %d)"
		% [chill_before, chill_after, int(T.get("chill", 2))],
		chill_after >= chill_before + 1 and float(inside.get("chill", 0.0)) > 0.0,
		"냉기 남은 시간 %.2f초" % float(inside.get("chill", 0.0)))
	ok("반경 밖 적에게는 아무 일도 없다",
		int(outside.get("chill_n", 0)) == 0 and near(float(outside.get("chill", 0.0)), 0.0),
		"중첩 %d · 시간 %.2f" % [int(outside.get("chill_n", 0)), float(outside.get("chill", 0.0))])
	st.player.hit_prot = 0.0
	var hp1: float = float(st.player.hp)
	var hit_now: bool = st.damage_player(15.0, "bite", inside)
	ok("해제 뒤에는 다시 맞는다(무적이 남지 않는다)", hit_now and float(st.player.hp) < hp1,
		"체력 %.1f → %.1f" % [hp1, float(st.player.hp)])

# ---------- [9] 유예의 시계 — 유예 ----------
func sec_reprieve() -> void:
	print("\n[9] eq_reprieve 유예의 시계 — 피해를 미뤘다가 정산한다")
	var st := lab("eq_reprieve", "reprieve_coat", "q")
	var T := PSkills.eq_tune("eq_reprieve")
	var foe := target(st, 380.0, 300.0)
	st.player.shield = 0.0 # 보호막이 있으면 '미룬 값'과 '깎인 값'이 섞인다
	var hp0: float = float(st.player.hp)
	ok("발동한다(예정 피해 장부가 열린다)", PSkills.cast(st, "q") and not st.eq_debt.is_empty(),
		"유지 %.1f초 · 상한 %.1f" % [float(st.eq_debt.get("t", 0.0)), float(st.eq_debt.get("cap", 0.0))])
	var raw := 20.0
	var moved_want: float = round(raw * float(T.get("frac", 0.6)) * 10.0) / 10.0
	st.damage_player(raw, "bite", foe)
	var lost_now := hp0 - float(st.player.hp)
	var debt := float(st.eq_debt.get("amount", 0.0))
	ok("받은 피해의 일부가 예정으로 넘어갔다 — 즉시 %.1f · 예정 %.1f(자료값 비율 %.2f)"
		% [lost_now, debt, float(T.get("frac", 0.6))],
		near(debt, moved_want) and near(lost_now, raw - moved_want),
		"체력 %.1f → %.1f" % [hp0, float(st.player.hp)])
	# 주무기 직접 타격으로 예정 피해가 지워진다
	var eff: float = st.damage_enemy(foe, 10.0, { "src": { "weapon_id": "sword", "direct": true } })
	var debt2 := float(st.eq_debt.get("amount", 0.0))
	var erase_want: float = minf(debt, eff * float(T.get("erase", 0.5)))
	ok("주무기 직접 타격이 예정 피해를 지운다 — %.1f → %.1f(지운 값 %.1f · 준 피해 %.1f)"
		% [debt, debt2, debt - debt2, eff],
		near(debt2, round((debt - erase_want) * 10.0) / 10.0),
		"경로 판정 %s" % st.frost_cause_of({ "src": { "weapon_id": "sword", "direct": true } }))
	# 시간이 다 되면 남은 예정 피해가 실제로 빠진다(조용히 사라지지 않는다)
	var hp1: float = float(st.player.hp)
	advance(st, float(T.get("dur", 3.0)) + 0.2)
	var settled := hp1 - float(st.player.hp)
	ok("정산 시각에 남은 예정 피해가 실제로 빠졌다 — %.1f(장부 %.1f)" % [settled, debt2],
		st.eq_debt.is_empty() and near(settled, debt2),
		"체력 %.1f → %.1f" % [hp1, float(st.player.hp)])
	# 장비를 벗으면 남은 예정 피해가 조용히 사라지지 않고 정산된다
	var st2 := lab("eq_reprieve", "reprieve_coat", "q")
	st2.player.shield = 0.0
	var foe2 := target(st2, 380.0, 300.0)
	PSkills.cast(st2, "q")
	st2.damage_player(20.0, "bite", foe2)
	var debt3 := float(st2.eq_debt.get("amount", 0.0))
	var hp2: float = float(st2.player.hp)
	st2.build.equip_types = []
	PSkills.eq_on_rebuild(st2)
	ok("장비를 벗으면 남은 예정 피해가 조용히 사라지지 않고 그 자리에서 정산된다 — %.1f"
		% [hp2 - float(st2.player.hp)],
		st2.eq_debt.is_empty() and near(hp2 - float(st2.player.hp), debt3),
		"예정 %.1f · 체력 %.1f → %.1f" % [debt3, hp2, float(st2.player.hp)])
