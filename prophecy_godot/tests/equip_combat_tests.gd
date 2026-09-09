extends SceneTree
## 신규 전투 효과형 장비 4종 검사(화면 없음).
## 실행: python tools/run_suites.py --suites equip_combat_tests --jobs 1
##      (직접: godot --headless --path prophecy_godot -s tests/equip_combat_tests.gd)
##
## 대상(docs/SPEC_EQUIP_SKILLBANK.md 3절 [1][2][3][10] · docs/EQUIP_COMBAT.md)
##  [1]  공성 망치머리(siege_hammerhead) — 전투망치 착탄 뒤 전방 균열
##  [2]  겹번개 도선(stormwire)          — 일반 감전 추가 피해를 같은 적에게 1회 복제
##  [3]  서리 결정 흉갑(frostcrest_armor) — 빙결 요구 냉기 중첩 5 → 4
##  [10] 잔영 허물(afterimage_cloak)     — 회피 출발점의 잔영이 '아직 겨누는 중인 적'만 흔든다
##
## 여기서 못박는 것
##  1. 장비를 끼지 않으면 **아무것도 달라지지 않는다**(기준 전투 지문 보존).
##  2. [1] 최초 착탄에 맞은 적이 균열에 **다시** 맞고, 한 번의 균열에는 **한 번만** 맞는다.
##     피해 기준은 **최초 타격의 명목 공격 피해**이며 잃은 체력·과잉 피해와 무관하다.
##  3. [2] 복제는 자기 자신을 다시 부르지 않고, **방전 충전 횟수에 포함되지 않으며**, 큰 방전을 복제하지 않는다.
##  4. [3] 요구량만 줄고 **재빙결 제한·보스 결빙(soft)** 은 그대로다. 바닥값 아래로는 내려가지 않는다.
##  5. [10] 확정된 공격은 안 바뀌고, 잔영이 광역 피해를 **대신 받지 않으며**, 회피 수치가 하나도 안 바뀐다.
##
## 수치는 전부 **첫 시험값**이다(data/world.json · data/meta.json · data/supports.json).
## 사용자가 승인한 밸런스가 아니다.

const STEP := 1.0 / 120.0
const EQ_HAMMER := "siege_hammerhead"
const EQ_SHOCK := "stormwire"
const EQ_FROST := "frostcrest_armor"
const EQ_CLOAK := "afterimage_cloak"

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 시험실 ----------
## ids = [[자동기술 id, 레벨, [개조...]], ...] · equip = { weapon/armor/shield: 장비 id }
func lab(ids: Array, equip: Dictionary = {}, main_weapon: String = "sword", seed_v: int = 1) -> CombatState:
	var g: Dictionary = PGrowth.new_growth(main_weapon)
	g.weapons = []
	for r in ids:
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	var run: Dictionary = PBuild.empty_run_like(g)
	var eqd: Dictionary = run.equipment
	for slot in equip:
		eqd[String(slot)] = String(equip[slot])
	var b: Dictionary = PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [], "arena": "clearing", "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.attack_timer = 1.0e9 # 자동 발사 정지(PWeapons.update가 읽는다)
	return st

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

func dummy(st: CombatState, dx: float, dy: float = 0.0, hp: float = 1000000.0) -> Dictionary:
	var e: Dictionary = st.spawn_enemy("wolf", float(st.player.x) + dx, float(st.player.y) + dy)
	e.hp = hp
	e.hp_max = hp
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

## 자동 발사를 끈 상태에서 지연 효과(전투망치 내려찍기 등)만 진행한다
func advance_delayed(st: CombatState, seconds: float) -> void:
	for i in int(round(seconds / STEP)):
		PWeapons.update(st, STEP)

func hit_as(st: CombatState, e: Dictionary, o: Dictionary, amount: float = 1.0) -> void:
	st.damage_enemy(e, amount, o)

func main_direct() -> Dictionary:
	return { "src": { "weapon_id": "sword", "direct": true } }

func near(a: float, b: float, tol: float = 0.06) -> bool:
	return absf(a - b) <= tol

func procs(st: CombatState, key: String) -> float:
	return PSupport.metered(st, "orb", key)

func _init() -> void:
	sec1_hammer_crack()
	sec2_shock_echo()
	sec3_frost_req()
	sec4_afterimage()
	sec5_defs()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- [1] 공성 망치머리 ----------
## 착탄점 = 플레이어에서 앞으로 100(사거리 110 안). 반경 80.
##   A = 착탄점(본타 + 균열)  ·  B = 착탄점에서 앞으로 120(원 밖 · 균열 길이 170 안)
func hammer_case(equip: Dictionary) -> Array:
	var st := lab([["hammer", 1, []]], equip, "hammer")
	var a := dummy(st, 100.0, 0.0)
	var b := dummy(st, 220.0, 0.0)
	var hp_a0: float = float(a.hp)
	var hp_b0: float = float(b.hp)
	PWeapons.fire(st, wep(st, "hammer"), a, false)
	advance_delayed(st, 1.0)
	return [st, hp_a0 - float(a.hp), hp_b0 - float(b.hp)]

func sec1_hammer_crack() -> void:
	var dmg: float = float(wep(lab([["hammer", 1, []]], {}, "hammer"), "hammer").stats.damage)

	var off := hammer_case({})
	var st_off: CombatState = off[0]
	ok("[1] 장비 없음: 착탄 원 안의 적만 본타 1회, 원 밖의 적은 0(균열 없음)",
		near(float(off[1]), dmg) and is_zero_approx(float(off[2])) and not (st_off.stats.equip_procs as Dictionary).has(EQ_HAMMER),
		"A %s / B %s (본타 %s)" % [str(off[1]), str(off[2]), str(dmg)])

	var on := hammer_case({ "weapon": EQ_HAMMER })
	var st_on: CombatState = on[0]
	ok("[1] 최초 착탄에 맞은 적이 **균열에 다시 맞는다**: A = 본타 + 본타×0.5",
		near(float(on[1]), dmg * 1.5), "A %s (기대 %s)" % [str(on[1]), str(dmg * 1.5)])
	ok("[1] 한 번의 균열에 같은 적은 **한 번만** 맞는다: 원 밖 B = 본타×0.5 정확히(2배가 아니다)",
		near(float(on[2]), dmg * 0.5), "B %s (기대 %s)" % [str(on[2]), str(dmg * 0.5)])
	ok("[1] 균열 피해 기준은 **최초 타격의 명목 피해**다: 본타를 맞은 A의 추가분 = 본타를 안 맞은 B의 피해",
		near(float(on[1]) - dmg, float(on[2])), "A 추가분 %s / B %s" % [str(float(on[1]) - dmg), str(on[2])])
	ok("[1] 내려찍기 1회 = 균열 1회(계측)", int((st_on.stats.equip_procs as Dictionary).get(EQ_HAMMER, 0)) == 1)

	# 과잉 피해를 다시 피해량으로 쓰지 않는다: 본타로 즉사한(과잉 피해가 큰) 적이 있어도 균열 피해는 그대로다
	var st2 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var a2 := dummy(st2, 100.0, 0.0, dmg * 0.4) # 본타 한 방에 죽는다(과잉 피해 = 본타 × 0.6)
	var b2 := dummy(st2, 220.0, 0.0)
	var hp_b2: float = float(b2.hp)
	PWeapons.fire(st2, wep(st2, "hammer"), a2, false)
	advance_delayed(st2, 1.0)
	ok("[1] 과잉 피해를 다시 피해량으로 쓰지 않는다: A가 즉사해도 B의 균열 피해는 본타×0.5 그대로",
		bool(a2.dead) and near(hp_b2 - float(b2.hp), dmg * 0.5), "B %s (기대 %s)" % [str(hp_b2 - float(b2.hp)), str(dmg * 0.5)])

	# 전투망치가 없으면 작동하지 않는다
	var st3 := lab([["sword", 1, []]], { "weapon": EQ_HAMMER }, "sword")
	var e3 := dummy(st3, 50.0, 0.0)
	PWeapons.fire(st3, wep(st3, "sword"), e3, false)
	advance_delayed(st3, 1.0)
	ok("[1] **망치가 없으면 작동하지 않는다**: 검으로 때려도 균열이 나지 않는다",
		not (st3.stats.equip_procs as Dictionary).has(EQ_HAMMER))
	var d3: Dictionary = PCatalog.equipment_def(EQ_HAMMER)
	ok("[1] 그 조건이 **장비 설명과 상점 문구(short·desc)** 에 적혀 있다",
		String(d3.short).find("전투망치") >= 0 and String(d3.desc).find("전투망치가 없으면") >= 0, String(d3.short))

	# 준비 중 회피 취소 = 본타도 균열도 없다(§2 취소 규칙)
	var st4 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var a4 := dummy(st4, 100.0, 0.0)
	var b4 := dummy(st4, 220.0, 0.0)
	var hp_a4: float = float(a4.hp)
	var hp_b4: float = float(b4.hp)
	PWeapons.fire(st4, wep(st4, "hammer"), a4, false)
	PWeapons.cancel_windup(st4)
	advance_delayed(st4, 1.0)
	ok("[1] 준비 중 회피로 취소하면 본타도 균열도 일어나지 않는다",
		is_zero_approx(hp_a4 - float(a4.hp)) and is_zero_approx(hp_b4 - float(b4.hp))
		and not (st4.stats.equip_procs as Dictionary).has(EQ_HAMMER))

# ---------- [2] 겹번개 도선 ----------
## 감전된 적 e1(앞 60)과 그 옆 e2(앞 60 · 옆 45 — 감전 후속 반경 50 안).
## 주무기 직접 타격을 손으로 한 번 넣어 감전 후속을 터뜨린다.
func shock_case(equip: Dictionary, mods: Array = []) -> Array:
	var st := lab([["orb", 1, mods.duplicate()]], equip)
	var e1 := dummy(st, 60.0, 0.0)
	var e2 := dummy(st, 60.0, 45.0)
	e1.conduct = float(PCatalog.support_tuning("orb").get("shockDur", 2.0))
	var h1: float = float(e1.hp)
	var h2: float = float(e2.hp)
	hit_as(st, e1, main_direct(), 1.0)
	return [st, h1 - float(e1.hp), h2 - float(e2.hp), e1, e2]

func sec2_shock_echo() -> void:
	var T := PCatalog.support_tuning("orb")
	var bonus: float = float(wep(lab([["orb", 1, []]]), "orb").stats.damage) * float(T.get("bonusMult", 0.4))

	var off := shock_case({})
	ok("[2] 장비 없음: 감전 후속은 반경 안 모두에게 1회씩",
		near(float(off[1]), 1.0 + bonus) and near(float(off[2]), bonus),
		"맞은 적 %s / 옆 적 %s (후속 %s)" % [str(off[1]), str(off[2]), str(bonus)])

	var on := shock_case({ "weapon": EQ_SHOCK })
	var st_on: CombatState = on[0]
	ok("[2] 장비 있음: **같은 적에게만** 후속 피해가 한 번 더 들어간다",
		near(float(on[1]), 1.0 + bonus * 2.0), "맞은 적 %s (기대 %s)" % [str(on[1]), str(1.0 + bonus * 2.0)])
	ok("[2] 반경 안의 **다른 적에게는 복제가 가지 않는다**",
		near(float(on[2]), bonus), "옆 적 %s (기대 %s)" % [str(on[2]), str(bonus)])
	ok("[2] 복제가 **자기 자신을 다시 부르지 않는다**: 감전 후속 발동 수는 1 그대로(폭주 없음)",
		is_equal_approx(procs(st_on, "shock_procs"), 1.0) and is_equal_approx(procs(off[0], "shock_procs"), 1.0),
		"장비 %s / 무장비 %s" % [str(procs(st_on, "shock_procs")), str(procs(off[0], "shock_procs"))])
	ok("[2] 복제는 감전을 다시 걸지 않는다(no_conduct)", is_zero_approx(float((on[3] as Dictionary).conduct)))
	ok("[2] 복제 1회 = 계측 1회", int((st_on.stats.equip_procs as Dictionary).get(EQ_SHOCK, 0)) == 1)

	# 자격표(data/supports.json)가 정본이다 — 새 장치를 만들지 않았다
	ok("[2] 자격표: 복제는 **일반 감전 후속에서만** 생긴다",
		PSupport.eligible("shock_echo", "shock_bonus")
		and not PSupport.eligible("shock_echo", "shock_echo")
		and not PSupport.eligible("shock_echo", "shock_discharge")
		and not PSupport.eligible("shock_echo", "zone_tick")
		and not PSupport.eligible("shock_echo", "main_direct"))
	ok("[2] 자격표: 복제 경로(shock_echo)는 감전 후속·파쇄·냉기 중첩·까마귀 표적·분신 모방을 부르지 못한다",
		not PSupport.eligible("shock_bonus", "shock_echo") and not PSupport.eligible("frost_shatter", "shock_echo")
		and not PSupport.eligible("frost_stack", "shock_echo") and not PSupport.eligible("crow_mark", "shock_echo")
		and not PSupport.eligible("echo_copy", "shock_echo") and not PSupport.eligible("plague_host_burst", "shock_echo"))
	ok("[2] 자격표: 복제는 **방전 충전 횟수에 포함되지 않는다**(shock_discharge.deny)",
		not PSupport.eligible("shock_discharge", "shock_echo"))

	# 방전 충전: 감전 후속 1회 = 충전 1. 장비가 있어도 그대로다
	var c_off := shock_case({}, ["conduct"])
	var c_on := shock_case({ "weapon": EQ_SHOCK }, ["conduct"])
	ok("[2] 축전(방전 충전): 감전 후속 1회 = 충전 1. **장비가 있어도 같다**",
		int((c_off[0] as CombatState).support_charge) == 1 and int((c_on[0] as CombatState).support_charge) == 1,
		"무장비 %d / 장비 %d" % [int((c_off[0] as CombatState).support_charge), int((c_on[0] as CombatState).support_charge)])

	# 큰 방전 폭발은 복제하지 않는다: chargeNeed번 터뜨려도 방전 횟수는 1
	var need := int(T.get("chargeNeed", 3))
	var st_d := lab([["orb", 1, ["conduct"]]], { "weapon": EQ_SHOCK })
	var ed := dummy(st_d, 60.0, 0.0)
	for i in need:
		ed.conduct = float(T.get("shockDur", 2.0))
		hit_as(st_d, ed, main_direct(), 1.0)
	ok("[2] **큰 방전 폭발은 복제하지 않는다**: 충전 %d회 → 방전 1회" % need,
		is_equal_approx(procs(st_d, "discharges"), 1.0) and int(st_d.support_charge) == 0,
		"방전 %s" % str(procs(st_d, "discharges")))

	# 번개 구체의 기본 수치는 그대로다(§17)
	ok("[2] 번개 구체 기본 수치를 이 장비 때문에 낮추지 않았다(bonusMult 0.4 · bonusR 50 · chargeNeed 3)",
		is_equal_approx(float(T.get("bonusMult", 0.0)), 0.4) and is_equal_approx(float(T.get("bonusR", 0.0)), 50.0)
		and int(T.get("chargeNeed", 0)) == 3)

# ---------- [3] 서리 결정 흉갑 ----------
func sec3_frost_req() -> void:
	var st_off := lab([["frost", 1, []]])
	var st_on := lab([["frost", 1, []]], { "armor": EQ_FROST })
	var base := int(st_off.frost_cfg().get("stackMax", 5))
	ok("[3] 요구 중첩: 장비 없음 %d · 장비 있음 %d(5 → 4는 첫 시험값)" % [base, st_on.frost_need()],
		st_off.frost_need() == base and st_on.frost_need() == base - 1 and st_on.frost_need() == 4,
		"무장비 %d / 장비 %d" % [st_off.frost_need(), st_on.frost_need()])

	var e_off := dummy(st_off, 80.0)
	var e_on := dummy(st_on, 80.0)
	for i in 4:
		st_off.add_chill_stack(e_off, 1, {})
		st_on.add_chill_stack(e_on, 1, {})
	ok("[3] 4중첩: 장비가 있으면 얼고, 없으면 아직 얼지 않는다",
		st_on.is_frozen(e_on) and not st_off.is_frozen(e_off))
	st_off.add_chill_stack(e_off, 1, {})
	ok("[3] 장비가 없으면 5중첩에서 얼린다(기존 규칙 불변)", st_off.is_frozen(e_off))
	ok("[3] 일반 적은 이동·공격이 멈추는 **빙결**(hard)이다", st_on.is_hard_frozen(e_on))

	# 재빙결 제한 유지
	e_on["freeze"] = 0.001
	st_on._tick_frost(e_on, 0.01)
	var refreeze := float(st_on.frost_cfg().get("refreezeSec", 3.0))
	ok("[3] 빙결이 끝나면 중첩 0 + **재빙결 제한이 그대로 걸린다**",
		not st_on.is_frozen(e_on) and int(e_on.get("chill_n", -1)) == 0 and near(float(e_on.refreeze_t), refreeze, 0.02),
		"제한 %s(기대 %s)" % [str(e_on.refreeze_t), str(refreeze)])
	for i in 8:
		st_on.add_chill_stack(e_on, 1, {})
	ok("[3] 제한이 남아 있는 동안에는 요구 중첩을 채워도 **다시 얼지 않는다**(무한 빙결 방지)",
		not st_on.is_frozen(e_on), "중첩 %d" % int(e_on.get("chill_n", 0)))

	# 보스는 결빙(soft) — 행동 정지와 구분한다
	var st_b := lab([["frost", 1, []]], { "armor": EQ_FROST })
	var boss := dummy(st_b, 90.0)
	boss.boss = true
	for i in 4:
		st_b.add_chill_stack(boss, 1, {})
	ok("[3] 보스는 같은 4중첩에서도 **결빙(soft)**: 이동·공격은 멈추지 않는다",
		st_b.is_frozen(boss) and not st_b.is_hard_frozen(boss) and String(boss.freeze_kind) == "soft",
		String(boss.get("freeze_kind", "")))

	# 바닥값: 감소량을 아무리 키워도 요구량이 바닥값 아래로 내려가지 않는다
	var st_c := lab([["frost", 1, []]], { "armor": EQ_FROST })
	(st_c.build.equip as Dictionary)["frostReq"] = { "reduce": 99, "min": 4 }
	ok("[3] **바닥값이 있어 계속 깎이지 않는다**: 감소량을 99로 키워도 요구량은 4",
		st_c.frost_need() == 4, "요구 %d" % st_c.frost_need())
	var d3: Dictionary = PCatalog.equipment_def(EQ_FROST)
	ok("[3] 장비 정의의 감소 단계는 고정값 1이다(강화로 오르는 자리가 없다)",
		int((d3.eff.frostReq as Dictionary).reduce) == 1 and int((d3.eff.frostReq as Dictionary).min) == 4)

# ---------- [10] 잔영 허물 ----------
func dodge_once(st: CombatState) -> void:
	st.step({ "dodge_press": true, "dodge_held": false }, STEP)

func sec4_afterimage() -> void:
	# 회피 수치는 하나도 바뀌지 않는다(방금 확정된 값)
	var want := { "daggers": [0.9, 0.36], "sword": [1.1, 0.32], "spear": [1.3, 0.28], "hammer": [1.6, 0.32], "bow": [2.2, 0.26] }
	var same := true
	var detail := ""
	for wid in want:
		var a := lab([[String(wid), 1, []]], {}, String(wid))
		var b := lab([[String(wid), 1, []]], { "armor": EQ_CLOAK }, String(wid))
		var row: Array = want[wid]
		if not (near(float(a.player.dodge_cd_time), float(row[0]), 0.001) and near(float(b.player.dodge_cd_time), float(row[0]), 0.001)
				and near(float(a.player.dodge_invuln_time), float(row[1]), 0.001) and near(float(b.player.dodge_invuln_time), float(row[1]), 0.001)
				and is_equal_approx(float(a.cfg.player.dodge.distance), float(b.cfg.player.dodge.distance))
				and is_equal_approx(float(a.cfg.player.dodge.duration), float(b.cfg.player.dodge.duration))
				and is_equal_approx(float(a.build.dodge_cd_mult), float(b.build.dodge_cd_mult))):
			same = false
			detail = "%s cd %s/%s invuln %s/%s" % [String(wid), str(a.player.dodge_cd_time), str(b.player.dodge_cd_time),
				str(a.player.dodge_invuln_time), str(b.player.dodge_invuln_time)]
	ok("[10] **무기별 회피 재사용·무적·거리·이동시간이 하나도 바뀌지 않는다**(쌍검 0.9/0.36 · 검 1.1/0.32 · 창 1.3/0.28 · 망치 1.6/0.32 · 활 2.2/0.26)",
		same, detail)

	# 장비가 없으면 잔영 자체가 없다
	var st_off := lab([["sword", 1, []]])
	dodge_once(st_off)
	ok("[10] 장비 없음: 회피해도 잔영이 생기지 않는다", (st_off.afterimage as Dictionary).is_empty())

	var st := lab([["sword", 1, []]], { "armor": EQ_CLOAK })
	var x0: float = float(st.player.x)
	var y0: float = float(st.player.y)
	var e := dummy(st, 160.0, 0.0)
	e.state = "approach"
	dodge_once(st)
	var ai: Dictionary = st.afterimage
	ok("[10] 회피하면 **출발점**에 잔영이 생긴다", not ai.is_empty() and near(float(ai.x), x0, 0.001) and near(float(ai.y), y0, 0.001),
		"잔영 %s / 출발 (%s, %s)" % [str(ai.get("x", "?")), str(x0), str(y0)])

	# 아직 겨누는 중인 적만 잔영을 겨눈다
	e.state = "bite_track"
	var t_aim: Dictionary = st.target_of(e)
	ok("[10] **아직 겨누는 중인 적**(bite_track)은 잔영을 겨눈다",
		near(float(t_aim.x), float(ai.x), 0.001) and bool(t_aim.get("lure", false)))
	e.state = "bite_lock"
	var t_lock: Dictionary = st.target_of(e)
	ok("[10] **이미 방향이 확정된 공격**(bite_lock)은 바뀌지 않는다: 실제 플레이어를 겨눈다",
		near(float(t_lock.x), float(st.player.x), 0.001) and not bool(t_lock.get("lure", false)))
	e.state = "dash"
	var t_run: Dictionary = st.target_of(e)
	ok("[10] **실행 중인 공격**(dash)도 바뀌지 않는다", near(float(t_run.x), float(st.player.x), 0.001))

	# 잔영은 피해를 대신 받지 않는다(광역 포함)
	e.state = "approach"
	st.player.invuln_t = 0.0
	st.player.hit_prot = 0.0
	var hp0: float = float(st.player.hp)
	st.zone_damage(9.0) # 장판 = 광역 피해 경로
	st.player.hit_prot = 0.0
	st.damage_player(11.0, "test")
	ok("[10] 잔영은 **피해를 대신 받지 않는다**: 장판·직격 피해가 그대로 들어간다",
		near(hp0 - float(st.player.hp), 20.0, 0.2) and not (st.afterimage as Dictionary).is_empty(),
		"잃은 체력 %s (기대 20)" % str(hp0 - float(st.player.hp)))

	# 잔영은 공격 한 번을 받으면 사라진다
	e.state = "bite_track"
	st.target_of(e) # 이 적이 잔영을 겨눈다
	e.state = "bite_lock" # 공격을 확정했다 = 그 공격은 잔영을 향해 나갔다
	st.update_afterimage(STEP)
	ok("[10] 잔영은 **공격 한 번을 받으면 사라진다**", (st.afterimage as Dictionary).is_empty())

	# 보스에게는 통하지 않는다(기존 유인 저항표 그대로) · 정예는 절반
	var st_b := lab([["sword", 1, []]], { "armor": EQ_CLOAK })
	var bo := dummy(st_b, 160.0, 0.0)
	bo.boss = true
	bo.state = "aim"
	var bx: float = float(bo.x)
	var by: float = float(bo.y)
	dodge_once(st_b)
	var tb: Dictionary = st_b.target_of(bo)
	ok("[10] 보스는 잔영을 겨누지 않는다(제압 저항표 taunt.boss = 0)",
		near(float(tb.x), float(st_b.player.x), 0.001) and is_zero_approx(PSupport.resist_mult("taunt", bo)))
	ok("[10] 잔영은 적을 **강제로 움직이지 않는다**: 보스 좌표가 그대로다",
		near(float(bo.x), bx, 0.001) and near(float(bo.y), by, 0.001))
	# 정예는 절반만 흔들린다: 창의 60% 지점에서 일반 적은 아직 잔영을, 정예는 이미 본체를 겨눈다
	var el := dummy(st_b, 200.0, 0.0)
	el.elite = true
	el.state = "aim"
	var nm := dummy(st_b, 240.0, 0.0)
	nm.state = "aim"
	var ai_b: Dictionary = st_b.afterimage
	var dx0: float = float(ai_b.x)
	ok("[10] 창이 열려 있는 동안에는 정예도 일반 적도 잔영을 겨눈다",
		near(float(st_b.target_of(el).x), dx0, 0.001) and near(float(st_b.target_of(nm).x), dx0, 0.001))
	ai_b.t = float(ai_b.dur) * 0.6
	ok("[10] 정예는 **절반만** 흔들린다(taunt.elite = 0.5): 창의 60%에서 정예는 본체를, 일반 적은 아직 잔영을 겨눈다",
		near(float(st_b.target_of(el).x), float(st_b.player.x), 0.001) and near(float(st_b.target_of(nm).x), dx0, 0.001),
		"정예 %s / 일반 %s / 잔영 %s" % [str(st_b.target_of(el).x), str(st_b.target_of(nm).x), str(dx0)])
	ai_b.t = float(ai_b.dur) + 0.01
	ok("[10] 수명이 다하면 일반 적도 더는 잔영을 겨누지 않는다",
		near(float(st_b.target_of(nm).x), float(st_b.player.x), 0.001))

# ---------- 장비 정의(2절: 기본 능력치 하나 + 고유 효과) ----------
func sec5_defs() -> void:
	var rows := {
		EQ_HAMMER: ["weapon", "eliteDirect", "hammerCrack"],
		EQ_SHOCK: ["weapon", "reach", "shockEcho"],
		EQ_FROST: ["armor", "hpMax", "frostReq"],
		EQ_CLOAK: ["armor", "speed", "afterimage"],
	}
	var all_ok := true
	var bad := ""
	for id in rows:
		var d: Dictionary = PCatalog.equipment_def(String(id))
		var row: Array = rows[id]
		var eff: Dictionary = d.get("eff", {})
		if d.is_empty() or String(d.slot) != String(row[0]) or eff.size() != 2 or not eff.has(String(row[1])) or not eff.has(String(row[2])):
			all_ok = false
			bad += "%s(%s) " % [String(id), str(eff.keys())]
	ok("2절: 네 장비 모두 **기본 능력치 하나 + 고유 효과 하나**이고 부위가 배정표와 같다", all_ok, bad)
	ok("2절: 새 장비는 기존 슬롯 3개(무기·갑옷·방패) 안에만 있다 — 슬롯을 늘리지 않았다",
		(PCatalog.world().equip_slots as Array).size() == 3)
	ok("1절: 신규 3종은 일반 장비, 잔영 허물은 제작 장비다",
		PCatalog.equipment().has(EQ_HAMMER) and PCatalog.equipment().has(EQ_SHOCK) and PCatalog.equipment().has(EQ_FROST)
		and not PCatalog.equipment().has(EQ_CLOAK) and PCatalog.is_crafted(EQ_CLOAK)
		and (PCatalog.recipe(EQ_CLOAK).equipment as Array) == ["traveler_armor"])
	var gl: Dictionary = PCatalog.glossary()
	ok("용어 사전에 네 장비 항목이 있다",
		gl.has("eq:" + EQ_HAMMER) and gl.has("eq:" + EQ_SHOCK) and gl.has("eq:" + EQ_FROST) and gl.has("eq:" + EQ_CLOAK))
	# 화면: 새 효과를 그리는 갈래가 있고 **규칙이 만든 값**을 읽는가(render_tests와 같은 방식의 원본 확인)
	var f := FileAccess.open("res://scripts/game/render.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	ok("화면: 균열(crack)·잔영(draw_afterimage)·잔영 소멸(afterimage_pop) 갈래가 있고 규칙 값을 읽는다",
		src.find("\"crack\":") >= 0 and src.find("\"afterimage_pop\":") >= 0
		and src.find("static func draw_afterimage(") >= 0 and src.find("st.afterimage") >= 0
		and src.find("draw_afterimage(ci, st)") >= 0)
