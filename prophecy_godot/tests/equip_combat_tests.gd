extends SceneTree
## 신규 전투 효과형 장비 4종 검사(화면 없음).
## 실행: python tools/run_suites.py --suites equip_combat_tests --jobs 1
##      (직접: godot --headless --path prophecy_godot -s tests/equip_combat_tests.gd)
##
## 대상(docs/SPEC_EQUIP_SKILLBANK.md 3절 [1][2][3][10] · docs/EQUIP_COMBAT.md)
##  [1]  공성 망치머리(siege_hammerhead) — 전투망치 착탄점에 짧은 간격 뒤 추가 충격 1회(전방 균열은 없앴다)
##  [2]  겹번개 도선(stormwire)          — 일반 감전 추가 피해를 같은 적에게 1회 복제
##  [3]  서리 결정 흉갑(frostcrest_armor) — 빙결 요구 냉기 중첩 5 → 4
##  [10] 잔영 허물(afterimage_cloak)     — 회피 출발점의 잔영이 '아직 겨누는 중인 적'만 흔든다
##
## 여기서 못박는 것
##  1. 장비를 끼지 않으면 **아무것도 달라지지 않는다**(기준 전투 지문 보존).
##  2. [1] 최초 착탄에 맞은 적이 추가 충격에 **다시** 맞고, 한 번의 추가 충격에는 **한 번만** 맞는다.
##     피해 기준은 **최초 타격의 명목 공격 피해**이며 잃은 체력·과잉 피해와 무관하다.
##     터지는 자리는 **최초 착탄점 고정**이고, 같은 빙결을 본타와 추가 충격이 두 번 파쇄하지 않는다.
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
	sec1_hammer_focus()
	sec2_shock_echo()
	sec3_frost_req()
	sec4_afterimage()
	sec5_defs()
	sec6_focus_vs_aftershock()
	sec7_echo_no_burst()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- [1] 공성 망치머리 ----------
## 착탄점 = 플레이어에서 앞으로 100(사거리 110 안). 본타 반경 80 · 준비 0.45.
## 추가 충격(시험값): 지연 0.25초 · 반경 = 본타 반경 × 0.65 = 52 · 피해 = 최초 타격의 50%.
##   A = 착탄점(본타 + 추가 충격)  ·  B = 착탄점에서 앞으로 120(옛 전방 균열 길이 170 안 — 지금은 아무것도 안 맞아야 한다)
const FOCUS_DELAY := 0.25
const FOCUS_RMULT := 0.65

func hammer_stats() -> Dictionary:
	return wep(lab([["hammer", 1, []]], {}, "hammer"), "hammer").stats

## [st, A가 잃은 체력, B가 잃은 체력]
func hammer_case(equip: Dictionary, mods: Array = [], seconds: float = 1.0) -> Array:
	var st := lab([["hammer", 1, mods.duplicate()]], equip, "hammer")
	var a := dummy(st, 100.0, 0.0)
	var b := dummy(st, 220.0, 0.0)
	var hp_a0: float = float(a.hp)
	var hp_b0: float = float(b.hp)
	PWeapons.fire(st, wep(st, "hammer"), a, false)
	advance_delayed(st, seconds) # 준비 0.45 + 후속(추가 충격 0.25 · 여진 0.6)이 모두 끝날 만큼 돌린다
	return [st, hp_a0 - float(a.hp), hp_b0 - float(b.hp)]

func sec1_hammer_focus() -> void:
	var hs := hammer_stats()
	var dmg: float = float(hs.damage)
	var rad: float = float(hs.radius)
	var frad: float = rad * FOCUS_RMULT

	# 확정 수치는 그대로다(바꾸지 않았다)
	ok("[1] 망치 확정 수치 불변: 반경 %s · 사거리 %s · 피해 %s · 주기 %s · 준비 %s" % [str(rad), str(hs.range), str(dmg), str(hs.interval), str(hs.get("windup", 0.0))],
		is_equal_approx(rad, 80.0) and is_equal_approx(float(hs.range), 110.0) and is_equal_approx(dmg, 30.0)
		and is_equal_approx(float(hs.interval), 1.4) and is_equal_approx(float(hs.get("windup", 0.0)), 0.45))

	var off := hammer_case({})
	var st_off: CombatState = off[0]
	ok("[1] 장비 없음: 착탄 원 안의 적만 본타 1회, 앞쪽 적은 0",
		near(float(off[1]), dmg) and is_zero_approx(float(off[2])) and not (st_off.stats.equip_procs as Dictionary).has(EQ_HAMMER),
		"A %s / B %s (본타 %s)" % [str(off[1]), str(off[2]), str(dmg)])

	var on := hammer_case({ "weapon": EQ_HAMMER })
	var st_on: CombatState = on[0]
	ok("[1] 착탄점 적 = 본타 + 추가 충격 = 본타×1.5(30이면 45.0)",
		near(float(on[1]), dmg * 1.5), "A %s (기대 %s)" % [str(on[1]), str(dmg * 1.5)])
	ok("[1] **전방 균열이 사라졌다**: 착탄점 앞 120(옛 균열 길이 170 안)의 적은 0을 받는다",
		is_zero_approx(float(on[2])), "B %s (기대 0)" % str(on[2]))
	ok("[1] 내려찍기 1회 = 추가 충격 1회(계측)", int((st_on.stats.equip_procs as Dictionary).get(EQ_HAMMER, 0)) == 1)
	ok("[1] 타격 수도 정확히 2회다(본타 1 + 추가 충격 1). 같은 적을 더 때리지 않는다",
		int((st_on.metrics.hits as Dictionary).get("hammer", 0)) == 2,
		"타격 %d" % int((st_on.metrics.hits as Dictionary).get("hammer", 0)))

	# 추가 충격 1회에 **큰 적도 한 번만** 맞는다(몸집이 반경을 다 덮어도 한 번이다)
	var st_big := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var big := dummy(st_big, 100.0, 0.0)
	big.r = 60.0
	var hp_big: float = float(big.hp)
	PWeapons.fire(st_big, wep(st_big, "hammer"), big, false)
	advance_delayed(st_big, 1.0)
	ok("[1] 추가 충격 1회에 **몸집 큰 적(r=60)도 한 번만** 맞는다: 본타×1.5 정확히",
		near(hp_big - float(big.hp), dmg * 1.5) and int((st_big.metrics.hits as Dictionary).get("hammer", 0)) == 2,
		"%s (기대 %s) · 타격 %d회" % [str(hp_big - float(big.hp)), str(dmg * 1.5), int((st_big.metrics.hits as Dictionary).get("hammer", 0))])

	# 과잉 피해를 다시 피해량으로 쓰지 않는다: 본타로 즉사한 적이 있어도 살아남은 적의 추가 충격은 명목값 그대로다
	var st2 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var a2 := dummy(st2, 100.0, 0.0, dmg * 0.4) # 본타 한 방에 죽는다(과잉 피해 = 본타 × 0.6)
	var c2 := dummy(st2, 100.0, 30.0) # 같은 착탄 원 안에서 살아남는 적
	var hp_c2: float = float(c2.hp)
	PWeapons.fire(st2, wep(st2, "hammer"), a2, false)
	advance_delayed(st2, 1.0)
	ok("[1] **즉사시켜 과잉 피해가 나도** 추가 충격 피해는 명목값 그대로다(본타×1.5)",
		bool(a2.dead) and near(hp_c2 - float(c2.hp), dmg * 1.5),
		"살아남은 적 %s (기대 %s)" % [str(hp_c2 - float(c2.hp)), str(dmg * 1.5)])

	# 피해 배율이 두 겹으로 곱해지지 않는다: 추가분은 정확히 본타의 0.5배다
	ok("[1] 피해 배율 중복 없음: 추가 충격분 = 본타 × 0.5 정확히",
		near(float(on[1]) - dmg, dmg * 0.5), "추가분 %s (기대 %s)" % [str(float(on[1]) - dmg), str(dmg * 0.5)])

	# ---- 위치 고정: 추가 충격 직전에 플레이어·적을 옮겨도 착탄점 그대로 ----
	var st5 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var ax: float = float(st5.player.x) + 100.0
	var ay: float = float(st5.player.y)
	var a5 := dummy(st5, 100.0, 0.0)
	var hp_a5: float = float(a5.hp)
	PWeapons.fire(st5, wep(st5, "hammer"), a5, false)
	advance_delayed(st5, 0.5) # 본타는 끝났고(0.45) 추가 충격은 아직(0.45 + 0.25 = 0.70)
	var after_land: float = hp_a5 - float(a5.hp)
	# 예고 표시가 **판정에 쓸 값 그대로**인가(자리·반지름·수명 = 지연시간)
	var warn := {}
	for f in st5.effects:
		if String(f.kind) == "focuswarn":
			warn = f
	ok("[1] 표시 = 판정: 예고(focuswarn)의 자리·반지름·수명이 실제 판정값과 같다(착탄점 · %s · %s초)" % [str(frad), str(FOCUS_DELAY)],
		not warn.is_empty() and near(float(warn.x), ax, 0.001) and near(float(warn.y), ay, 0.001)
		and near(float(warn.r), frad, 0.001) and near(float(warn.ttl), FOCUS_DELAY, 0.001),
		"예고 %s" % str(warn))
	ok("[1] 지연시간 전에는 아직 터지지 않는다: 0.5초 시점에서 A는 본타 1회분만 잃었다",
		near(after_land, dmg) and not (st5.stats.equip_procs as Dictionary).has(EQ_HAMMER),
		"A %s (기대 %s)" % [str(after_land), str(dmg)])
	# 이제 플레이어도 적도 옮긴다
	a5.x = ax + 400.0
	a5.y = ay
	st5.player.x = ax + 400.0
	st5.player.y = ay
	var c5 := dummy(st5, -400.0, 0.0) # 옮긴 플레이어 기준 -400 = 원래 착탄점 그 자리
	var hp_c5: float = float(c5.hp)
	advance_delayed(st5, 0.4)
	ok("[1] **위치 고정**: 추가 충격 전에 플레이어·적을 옮겨도 터지는 자리는 최초 착탄점 그대로다",
		near(hp_a5 - float(a5.hp), after_land) and near(hp_c5 - float(c5.hp), dmg * 0.5)
		and int((st5.stats.equip_procs as Dictionary).get(EQ_HAMMER, 0)) == 1,
		"옮긴 적 추가분 %s(기대 0) / 착탄점 새 적 %s(기대 %s)" % [str(hp_a5 - float(a5.hp) - after_land), str(hp_c5 - float(c5.hp)), str(dmg * 0.5)])

	# ---- 파쇄: 자격은 유지하되 같은 빙결을 두 번 깨지 않는다 ----
	# (가) 추가 충격도 파쇄를 터뜨릴 자격이 있다 — 본타 뒤에 언 적을 추가 충격이 깬다
	var st6 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var e6 := dummy(st6, 100.0, 0.0)
	PWeapons.fire(st6, wep(st6, "hammer"), e6, false)
	advance_delayed(st6, 0.5) # 본타는 끝났다
	for i in st6.frost_need():
		st6.add_chill_stack(e6, 1, {})
	var froze6: bool = st6.is_frozen(e6)
	advance_delayed(st6, 0.4)
	ok("[1] **파쇄 자격 유지**: 본타 뒤에 언 적을 추가 충격이 깬다(파쇄 1회)",
		froze6 and is_equal_approx(PSupport.metered(st6, "frost", "shatters"), 1.0),
		"빙결 %s / 파쇄 %s" % [str(froze6), str(PSupport.metered(st6, "frost", "shatters"))])
	ok("[1] 자격표: 추가 충격 경로(main_extra)는 파쇄 자격이 있다 — 새 경로 이름을 만들지 않았다",
		PSupport.eligible("frost_shatter", "main_extra") and PSupport.eligible("frost_shatter", "main_direct"))

	# ---- 연계 자격(7절): 추가 충격은 개조 '전방 충격파'·'여진'과 **같은 main_extra** 다. 새 경로 이름을 만들지 않았다 ----
	ok("[1] 경로 분류: 추가 충격(direct:false · 주무기 hammer)은 main_extra로 분류된다",
		PSupport.cause_of(st_on, { "weapon": "hammer", "hit": { "src": { "weapon_id": "hammer", "direct": false } } }) == "main_extra"
		and PSupport.cause_of(st_on, { "weapon": "hammer", "hit": { "src": { "weapon_id": "hammer", "direct": true } } }) == "main_direct",
		PSupport.cause_of(st_on, { "weapon": "hammer", "hit": { "src": { "weapon_id": "hammer", "direct": false } } }))
	ok("[1] 자격표(7절): main_extra는 파쇄·감전 후속·까마귀 표적·숙주 파열을 부르고, **방전 충전은 직접 올리지 못한다**",
		PSupport.eligible("frost_shatter", "main_extra")
		and PSupport.eligible("shock_bonus", "main_extra")
		and PSupport.eligible("crow_mark", "main_extra")
		and PSupport.eligible("plague_host_burst", "main_extra")
		and not PSupport.eligible("shock_discharge", "main_extra")
		and not PSupport.eligible("echo_copy", "main_extra"))

	# 감전 후속을 실제로 부르는가(값으로) · 방전 충전은 그 후속이 올린다(간접)
	var st9 := lab([["hammer", 1, []], ["orb", 1, ["conduct"]]], { "weapon": EQ_HAMMER }, "hammer")
	var e9 := dummy(st9, 100.0, 0.0)
	PWeapons.fire(st9, wep(st9, "hammer"), e9, false)
	advance_delayed(st9, 0.5) # 본타는 감전 없는 적을 때렸다
	var sp0: float = PSupport.metered(st9, "orb", "shock_procs")
	e9.conduct = float(PCatalog.support_tuning("orb").get("shockDur", 2.0)) # 본타 뒤에 감전이 걸렸다
	advance_delayed(st9, 0.4) # 추가 충격
	ok("[1] 연계: 추가 충격이 **감전 후속을 실제로 부른다**(충격파·여진과 같은 경로) · 방전 충전은 그 후속이 1 올린다",
		is_zero_approx(sp0) and is_equal_approx(PSupport.metered(st9, "orb", "shock_procs"), 1.0) and int(st9.support_charge) == 1,
		"본타 뒤 후속 %s → 추가 충격 뒤 후속 %s · 충전 %d" % [str(sp0), str(PSupport.metered(st9, "orb", "shock_procs")), int(st9.support_charge)])

	# (나) 같은 빙결을 본타와 추가 충격이 **두 번** 깨지 않는다
	var st7 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var e7 := dummy(st7, 100.0, 0.0)
	for i in st7.frost_need():
		st7.add_chill_stack(e7, 1, {})
	var froze7: bool = st7.is_frozen(e7)
	PWeapons.fire(st7, wep(st7, "hammer"), e7, false)
	advance_delayed(st7, 0.5)
	var sh_after_land: float = PSupport.metered(st7, "frost", "shatters")
	advance_delayed(st7, 0.4)
	ok("[1] **같은 빙결을 두 번 파쇄하지 않는다**: 본타가 깨면 추가 충격은 안 깬다(파쇄 1회 그대로)",
		froze7 and is_equal_approx(sh_after_land, 1.0) and is_equal_approx(PSupport.metered(st7, "frost", "shatters"), 1.0)
		and not st7.is_frozen(e7) and float(e7.get("refreeze_t", 0.0)) > 0.0
		and int((st7.stats.equip_procs as Dictionary).get(EQ_HAMMER, 0)) == 1,
		"본타 뒤 %s / 추가 충격 뒤 %s · 재빙결 제한 %s" % [str(sh_after_land), str(PSupport.metered(st7, "frost", "shatters")), str(e7.get("refreeze_t", 0.0))])

	# ---- 개조와 함께 썼을 때 ----
	# 전방 충격파: 앞으로 뻗는 몫은 개조가, 착탄점에 모으는 몫은 장비가 맡는다(둘이 각자 제 역할)
	var sw := hammer_case({ "weapon": EQ_HAMMER }, ["shockwave"])
	ok("[1] **전방 충격파 개조와 함께**: 앞의 적은 충격파만(본타×0.6), 착탄점 적은 본타 + 충격파 + 추가 충격",
		near(float(sw[2]), dmg * 0.6) and near(float(sw[1]), dmg * (1.0 + 0.6 + 0.5)),
		"앞 %s(기대 %s) / 착탄점 %s(기대 %s)" % [str(sw[2]), str(dmg * 0.6), str(sw[1]), str(dmg * (1.0 + 0.6 + 0.5))])
	# 여진: 같은 역할이 아니라 **각각 따로** 터진다(합치지도 지우지도 않는다)
	var af := hammer_case({ "weapon": EQ_HAMMER }, ["aftershock"], 1.5) # 여진은 착탄 0.45 + 0.6 = 1.05초에 온다
	ok("[1] **여진 개조와 함께**: 둘을 합치거나 지우지 않는다 — 착탄점 적 = 본타 + 여진 0.5 + 추가 충격 0.5",
		near(float(af[1]), dmg * 2.0), "착탄점 %s (기대 %s)" % [str(af[1]), str(dmg * 2.0)])

	# 전투망치가 없으면 작동하지 않는다
	var st3 := lab([["sword", 1, []]], { "weapon": EQ_HAMMER }, "sword")
	var e3 := dummy(st3, 50.0, 0.0)
	PWeapons.fire(st3, wep(st3, "sword"), e3, false)
	advance_delayed(st3, 1.0)
	ok("[1] **망치가 없으면 작동하지 않는다**: 검으로 때려도 추가 충격이 나지 않는다",
		not (st3.stats.equip_procs as Dictionary).has(EQ_HAMMER))
	var d3: Dictionary = PCatalog.equipment_def(EQ_HAMMER)
	ok("[1] 그 조건이 **장비 설명과 상점 문구(short·desc)** 에 적혀 있다",
		String(d3.short).find("전투망치") >= 0 and String(d3.desc).find("전투망치가 없으면") >= 0, String(d3.short))
	ok("[1] 장비 정의에 옛 균열 값(len·w)이 남아 있지 않고, 새 값(지연·반경 배율)이 자료에 있다",
		not (d3.eff.hammerFocus as Dictionary).has("len") and not (d3.eff.hammerFocus as Dictionary).has("w")
		and near(float((d3.eff.hammerFocus as Dictionary).delay), FOCUS_DELAY, 0.001)
		and near(float((d3.eff.hammerFocus as Dictionary).radiusMult), FOCUS_RMULT, 0.001)
		and near(float((d3.eff.hammerFocus as Dictionary).mult), 0.5, 0.001), str(d3.eff.hammerFocus))

	# 준비 중 회피 취소 = 본타도 추가 충격도 없다(§2 취소 규칙)
	var st4 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var a4 := dummy(st4, 100.0, 0.0)
	var hp_a4: float = float(a4.hp)
	PWeapons.fire(st4, wep(st4, "hammer"), a4, false)
	PWeapons.cancel_windup(st4)
	advance_delayed(st4, 1.0)
	ok("[1] 준비 중 회피로 취소하면 본타도 추가 충격도 일어나지 않는다",
		is_zero_approx(hp_a4 - float(a4.hp)) and not (st4.stats.equip_procs as Dictionary).has(EQ_HAMMER))

	# 밀어내기·경직은 본타만 준다(한 번의 내려찍기가 제압을 두 번 걸지 않는다)
	var st8 := lab([["hammer", 1, []]], { "weapon": EQ_HAMMER }, "hammer")
	var e8 := dummy(st8, 100.0, 0.0)
	PWeapons.fire(st8, wep(st8, "hammer"), e8, false)
	advance_delayed(st8, 0.5)
	var x_land: float = float(e8.x)
	advance_delayed(st8, 0.4)
	ok("[1] 밀어내기·경직은 **본타만** 준다: 추가 충격은 적을 더 밀지 않는다",
		near(float(e8.x), x_land, 0.001) and int((st8.stats.equip_procs as Dictionary).get(EQ_HAMMER, 0)) == 1,
		"착탄 직후 x %s → 추가 충격 뒤 x %s" % [str(x_land), str(e8.x)])

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
		EQ_HAMMER: ["weapon", "eliteDirect", "hammerFocus"],
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
	ok("화면: 추가 충격 예고·폭발(focuswarn·focusblast)·잔영(draw_afterimage)·잔영 소멸(afterimage_pop) 갈래가 있고 규칙 값을 읽는다",
		src.find("\"focuswarn\":") >= 0 and src.find("\"focusblast\":") >= 0 and src.find("\"afterimage_pop\":") >= 0
		and src.find("static func draw_afterimage(") >= 0 and src.find("st.afterimage") >= 0
		and src.find("draw_afterimage(ci, st)") >= 0)
	ok("화면: **옛 전방 균열 갈래(crack)가 남아 있지 않다**", src.find("\"crack\":") < 0)

# ---------- 6. [1] × 개조 '여진' 병용: 출처를 나눠 센다(2026-09-10 사용자 확정 4절) ----------
## 사용자 확정: **둘을 모두 유지하고 병용을 허용한다.** 유사하다는 이유로 지우거나 재설계하지 않는다.
## 대신 **혼동하지 않게 계측 출처를 나눈다** — 여진은 개조 계측 mod_stats["aftershock"],
## 이 장비는 mod_stats["equip:siege_hammerhead"]다(id의 "equip:"이 장비라는 표시).
## 연계 자격은 둘 다 그대로 main_extra이고 **피해·시점·대상 판정은 하나도 바꾸지 않았다**(계측만 더했다).
func mod_row(st: CombatState, id: String) -> Dictionary:
	return (st.mod_stats as Dictionary).get(id, { "procs": 0, "hits": 0, "damage": 0.0 })

## 내려찍기 한 번을 단계별로 굴리며 **언제·얼마를** 때렸는지 모은다. [[초, 피해], ...]
func strike_timeline(mods: Array, equip: Dictionary, seconds: float) -> Array:
	var st := lab([["hammer", 1, mods.duplicate()]], equip, "hammer")
	var a := dummy(st, 100.0, 0.0)
	PWeapons.fire(st, wep(st, "hammer"), a, false)
	var events := []
	for i in int(round(seconds / STEP)):
		var hp_b: float = float(a.hp)
		PWeapons.update(st, STEP)
		if float(a.hp) < hp_b - 1e-6:
			events.append([float(i + 1) * STEP, hp_b - float(a.hp)])
	return [st, events]

func fmt_events(events: Array) -> String:
	var out := []
	for r in events:
		out.append("%.2f초 %.1f" % [float(r[0]), float(r[1])])
	return " · ".join(out)

func sec6_focus_vs_aftershock() -> void:
	var dmg: float = float(hammer_stats().damage)

	# (가) 장비만: 본타(준비 0.45) + 추가 충격(+0.25)
	var only_eq := strike_timeline([], { "weapon": EQ_HAMMER }, 1.6)
	var st_eq: CombatState = only_eq[0]
	var ev_eq: Array = only_eq[1]
	ok("[1] 장비만: 타격 2회 — 본타 0.45초 %s · 추가 충격 0.70초 %s" % [str(dmg), str(dmg * 0.5)],
		ev_eq.size() == 2 and near(float(ev_eq[0][0]), 0.45, 0.02) and near(float(ev_eq[0][1]), dmg)
		and near(float(ev_eq[1][0]), 0.70, 0.02) and near(float(ev_eq[1][1]), dmg * 0.5),
		fmt_events(ev_eq))

	# (나) 여진만: 본타(0.45) + 여진(+0.6)
	var only_af := strike_timeline(["aftershock"], {}, 1.6)
	var st_af: CombatState = only_af[0]
	var ev_af: Array = only_af[1]
	ok("[1] 여진만: 타격 2회 — 본타 0.45초 %s · 여진 1.05초 %s" % [str(dmg), str(dmg * 0.5)],
		ev_af.size() == 2 and near(float(ev_af[0][0]), 0.45, 0.02) and near(float(ev_af[0][1]), dmg)
		and near(float(ev_af[1][0]), 1.05, 0.02) and near(float(ev_af[1][1]), dmg * 0.5),
		fmt_events(ev_af))

	# (다) 병용: **셋 다 제 시점에 제 피해로** 온다. 합치지도 지우지도 않았다
	var both := strike_timeline(["aftershock"], { "weapon": EQ_HAMMER }, 1.6)
	var st_both: CombatState = both[0]
	var ev_both: Array = both[1]
	ok("[1]+여진 **병용**: 타격 3회 — 본타 0.45초 %s · 추가 충격 0.70초 %s · 여진 1.05초 %s(합치지도 지우지도 않았다)"
			% [str(dmg), str(dmg * 0.5), str(dmg * 0.5)],
		ev_both.size() == 3
		and near(float(ev_both[0][0]), 0.45, 0.02) and near(float(ev_both[0][1]), dmg)
		and near(float(ev_both[1][0]), 0.70, 0.02) and near(float(ev_both[1][1]), dmg * 0.5)
		and near(float(ev_both[2][0]), 1.05, 0.02) and near(float(ev_both[2][1]), dmg * 0.5),
		fmt_events(ev_both))

	# (라) **계측 출처가 갈린다** — 병용해도 서로의 칸에 섞이지 않는다
	var m_eq: Dictionary = mod_row(st_both, "equip:" + EQ_HAMMER)
	var m_af: Dictionary = mod_row(st_both, "aftershock")
	ok("[1]+여진 **계측 출처 분리**: 장비 %s / 여진 %s — 각각 발동 1·적중 1·피해 %s이고 섞이지 않는다"
			% ["equip:" + EQ_HAMMER, "aftershock", str(dmg * 0.5)],
		int(m_eq.procs) == 1 and int(m_eq.hits) == 1 and near(float(m_eq.damage), dmg * 0.5)
		and int(m_af.procs) == 1 and int(m_af.hits) == 1 and near(float(m_af.damage), dmg * 0.5),
		"장비 %s / 여진 %s" % [str(m_eq), str(m_af)])
	ok("[1] 장비만 켰을 때 **여진 칸은 비어 있다**(반대도 같다)",
		int(mod_row(st_eq, "aftershock").procs) == 0 and int(mod_row(st_eq, "equip:" + EQ_HAMMER).procs) == 1
		and int(mod_row(st_af, "equip:" + EQ_HAMMER).procs) == 0 and int(mod_row(st_af, "aftershock").procs) == 1,
		"장비만 %s / 여진만 %s" % [str(mod_row(st_eq, "aftershock")), str(mod_row(st_af, "equip:" + EQ_HAMMER))])

	# (마) 병용해도 **같은 빙결은 한 번만** 깨진다(본타가 깨면 나머지 둘은 깨뜨릴 빙결이 없다)
	var st7 := lab([["hammer", 1, ["aftershock"]]], { "weapon": EQ_HAMMER }, "hammer")
	var e7 := dummy(st7, 100.0, 0.0)
	for i in st7.frost_need():
		st7.add_chill_stack(e7, 1, {})
	var froze7: bool = st7.is_frozen(e7)
	PWeapons.fire(st7, wep(st7, "hammer"), e7, false)
	advance_delayed(st7, 1.6)
	ok("[1]+여진 병용에서도 **같은 빙결의 파쇄는 1회뿐**이다(파쇄 가능 타격이 셋이어도)",
		froze7 and is_equal_approx(PSupport.metered(st7, "frost", "shatters"), 1.0)
		and float(e7.get("refreeze_t", 0.0)) > 0.0,
		"빙결 %s · 파쇄 %s · 재빙결 제한 %s" % [str(froze7), str(PSupport.metered(st7, "frost", "shatters")), str(e7.get("refreeze_t", 0.0))])

# ---------- 7. [2] 겹번개 도선: 복제 처치로는 숙주 파열이 나지 않는다 ----------
## 사용자 확정: **복제한 감전 피해로 적을 처치해도 숙주 파열은 발생하지 않는다.**
## 이미 그렇게 돼 있으므로 이것은 구현이 아니라 **확인**이다 — 값으로 증명하고 검사로 못박는다.
func quiet_tick(st: CombatState, sec: float) -> void:
	for i in int(round(sec / STEP)):
		var keep := []
		for d in st.delayed:
			d.t = float(d.t) - STEP
			if float(d.t) <= 0.0:
				(d.fn as Callable).call()
			else:
				keep.append(d)
		st.delayed = keep
		PSupport.update(st, STEP)

func sec7_echo_no_burst() -> void:
	var T := PCatalog.support_tuning("orb")
	var bonus: float = float(wep(lab([["orb", 1, []]]), "orb").stats.damage) * float(T.get("bonusMult", 0.4))

	var st := lab([["orb", 1, []], ["plague", 1, ["burst"]]], { "weapon": EQ_SHOCK })
	var host := dummy(st, 60.0, 0.0, 400.0)
	var near1 := dummy(st, 60.0, 45.0, 400.0) # 감전 후속 반경(50)·파열 반경(90) 안
	PSupport.fire(st, wep(st, "plague"), host, false)
	quiet_tick(st, 1.2)
	var P: Dictionary = PSupportB.plague_stat(st)
	var infected: bool = not (host.get("plague", {}) as Dictionary).is_empty()
	# **복제가 마지막 일격이 되도록** 체력을 맞춘다: 본타 1.0 + 감전 후속 bonus 를 견디고, 복제 bonus 에 죽는다
	host.hp = 1.0 + bonus + 0.5
	host.conduct = float(T.get("shockDur", 2.0))
	hit_as(st, host, main_direct(), 1.0)
	ok("[2] 전제: 감염된 적이 **복제 피해로 죽었다**(본타·감전 후속으로는 죽지 않았다)",
		infected and bool(host.dead) and int((st.stats.equip_procs as Dictionary).get(EQ_SHOCK, 0)) == 1,
		"복제 %d회 · 사망 %s" % [int((st.stats.equip_procs as Dictionary).get(EQ_SHOCK, 0)), str(host.dead)])
	ok("[2] **복제 처치로는 숙주 파열이 나지 않는다**(자격표 plague_host_burst.deny의 shock_echo)",
		int(P.bursts) == 0 and int(P.burst_blocked) >= 1 and is_zero_approx(float(near1.stagger_t)),
		"파열 %d · 막힘 %d · 이웃 경직 %.3f초" % [int(P.bursts), int(P.burst_blocked), float(near1.stagger_t)])
	ok("[2] 그때에도 **독 전염은 그대로 일어난다**(전염과 파열의 발동을 구분한다)",
		int(P.spreads) >= 1 and not (near1.get("plague", {}) as Dictionary).is_empty(),
		"전염 %d회" % int(P.spreads))
