extends SceneTree
## 패시브 교체(회피 숙련·흡혈)와 집중의 **실측** 표를 뽑는 계측 도구. 규칙을 하나도 고치지 않고 읽기만 한다.
## 실행: godot --headless --path prophecy_godot -s tools/pass_probe.gd
##
## 왜 있는가 — 사용자 지적: "자료에서 읽어 비교하는 검사만으로 실제 쿨다운까지 증명되지 않는다."
## 그래서 여기서는 **전투를 실제로 굴려** 쓴 뒤 다시 쓸 수 있게 되는 시각을 센다.
## 선언값(PBuild.derive·PSkills.cd_of)은 참고로 같은 줄에 적어 두 값이 어긋나면 바로 보이게 한다.
##
## 표 넷:
##  A 회피 재사용 — 주무기 5종 × 회피 숙련 Lv0~3. 거리·이동 시간·무적이 그대로인지 함께 잰다.
##  B 흡혈 — 출처별 자격, 초과 피해 제외, 소수점 누적, 최대 체력 상한, 보스·다수.
##  C 집중 — 일반 6종 + 장비 6종 × Lv0~3 × Q/E. 실제 재사용 가능 시각.
##  D 결정 관 + 집중 Lv3의 무적 반복 간격.
##
## 여기 숫자는 전부 첫 시험값이다. 사용자가 승인한 밸런스가 아니다.

const STEP := 1.0 / 120.0
const MAIN_WEAPONS := ["daggers", "sword", "spear", "hammer", "bow"]

## 장비 기술 → 그 기술을 주는 장비[부위, 장비 id]. tests/eq_skill_tests.gd ROWS와 같은 표다
const EQ_ROWS := {
	"eq_flashcut": ["weapon", "instant_blade"],
	"eq_meteor": ["weapon", "falling_star_maul"],
	"eq_riposte": ["shield", "counter_guard"],
	"eq_retrace": ["armor", "retrace_greaves"],
	"eq_icetomb": ["shield", "crystal_coffin"],
	"eq_reprieve": ["armor", "reprieve_coat"],
}
const NORMAL_SKILLS := ["slowfield", "gust", "bladestorm", "strike", "gravity", "ward"]

# ---------- 시험실 ----------
func growth_of(weapon: String, q_id: String, e_id: String, passives: Dictionary) -> Dictionary:
	var g := PGrowth.new_growth(weapon, q_id if q_id != "" else "slowfield")
	g.weapons = [{ "id": weapon, "level": 1, "mods": [] }]
	g.skills.q = { "id": q_id, "level": 1, "variant": null } if q_id != "" else null
	g.skills.e = { "id": e_id, "level": 1, "variant": null } if e_id != "" else null
	for k in passives:
		g.passives[String(k)] = int(passives[k])
	return g

func run_of(weapon: String, q_id: String, e_id: String, passives: Dictionary, equip: Dictionary) -> Dictionary:
	var run := PBuild.empty_run_like(growth_of(weapon, q_id, e_id, passives))
	for slot in equip:
		(run.equipment as Dictionary)[String(slot)] = String(equip[slot])
	return run

## 적이 저절로 나오지 않는 빈 전장. auto=false면 자동공격을 끈다(무엇이 원인인지 갈라지게)
func mk(weapon: String, q_id: String, e_id: String, passives: Dictionary = {}, equip: Dictionary = {}, auto: bool = false) -> CombatState:
	var b := PBuild.derive(run_of(weapon, q_id, e_id, passives, equip))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "arena": "clearing",
		"waves": [], "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.face = 0.0
	if not auto:
		st.player.attack_timer = 1.0e9
	return st

func dummy(st: CombatState, dx: float, dy: float = 0.0, hp: float = 1.0e7, type_id: String = "wolf") -> Dictionary:
	var e: Dictionary = st.spawn_enemy(type_id, float(st.player.x) + dx, float(st.player.y) + dy)
	e.hp = hp
	e.hp_max = hp
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

func inp(q: bool = false, e: bool = false, dodge: bool = false, mx: float = 0.0) -> Dictionary:
	return { "mx": mx, "my": 0.0, "dodge_press": dodge, "dodge_held": false, "special": q, "skill_e": e }

func f2(v: float) -> String:
	return "%.3f" % v

# ================================================================
# A. 회피 재사용 — 주무기 5종 × 회피 숙련 Lv0~3
# ================================================================
## 회피 한 번을 실제로 굴려서 잰다: 재사용이 풀리는 시각·이동이 끝나는 시각·이동 거리·무적이 끝나는 시각.
## hold=true면 끝까지 눌러 최대 거리(150)까지 간다
func dodge_probe(weapon: String, mastery_lv: int, hold: bool = true) -> Dictionary:
	var st := mk(weapon, "slowfield", "", { "dodge_mastery": mastery_lv })
	var press := { "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": hold, "special": false, "skill_e": false }
	var keep := { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": hold, "special": false, "skill_e": false }
	var x0: float = float(st.player.x)
	var y0: float = float(st.player.y)
	st.step(press, STEP)
	var move_n := 1 if st.player.dodge_active else 0
	var inv_n := 1 if float(st.player.invuln_t) > 0.0 else 0
	var cd_n := -1
	var n := 1
	while n < 2000:
		st.step(keep, STEP)
		n += 1
		if st.player.dodge_active:
			move_n = n
		if float(st.player.invuln_t) > 0.0:
			inv_n = n
		if cd_n < 0 and float(st.player.dodge_cd) <= 0.0:
			cd_n = n
		if cd_n >= 0 and not st.player.dodge_active and float(st.player.invuln_t) <= 0.0:
			break
	return { "cd": float(cd_n) * STEP, "move": float(move_n) * STEP, "invuln": float(inv_n) * STEP,
		"dist": PGeom.dist(x0, y0, float(st.player.x), float(st.player.y)),
		"set_cd": float(st.player.dodge_cd_time), "set_inv": float(st.player.dodge_invuln_time),
		"mult": float(st.build.dodge_cd_mult) }

## 회피를 한 번 더 실제로 쓸 수 있게 되는 시각(계속 누르면서 두 번째 회피가 나가는 단계를 센다)
func dodge_recast(weapon: String, mastery_lv: int) -> float:
	var st := mk(weapon, "slowfield", "", { "dodge_mastery": mastery_lv })
	var press := { "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": false, "special": false, "skill_e": false }
	var n1 := -1
	var n2 := -1
	var n := 0
	while n < 2000:
		var before := int(st.stats.dodges)
		st.step(press, STEP)
		n += 1
		if int(st.stats.dodges) > before:
			if n1 < 0:
				n1 = n
			else:
				n2 = n
				break
	return float(n2 - n1) * STEP if n1 > 0 and n2 > 0 else -1.0

func table_dodge() -> void:
	print("\n=== A. 회피 재사용 실측 (주무기 5종 × 회피 숙련 Lv0~3) ===")
	print("무기      Lv 선언(표×배율)  실측 재사용  다시 회피까지  이동시간  거리    무적")
	for wid in MAIN_WEAPONS:
		for lv in 4:
			var pr := dodge_probe(String(wid), lv)
			var want: float = float(pr.set_cd) * float(pr.mult)
			print("%-9s %d  %s        %s      %s      %s   %6.1f  %s" % [
				String(wid), lv, f2(want), f2(float(pr.cd)), f2(dodge_recast(String(wid), lv)),
				f2(float(pr.move)), float(pr.dist), f2(float(pr.invuln))])
	print("\n-- 짧은 탭(누르자마자 뗌): 이동은 짧아도 무적은 무기 값 그대로 --")
	for wid2 in MAIN_WEAPONS:
		var t0 := dodge_probe(String(wid2), 0, false)
		var t3 := dodge_probe(String(wid2), 3, false)
		print("%-9s Lv0 이동 %s/거리 %5.1f/무적 %s · Lv3 이동 %s/거리 %5.1f/무적 %s" % [
			String(wid2), f2(float(t0.move)), float(t0.dist), f2(float(t0.invuln)),
			f2(float(t3.move)), float(t3.dist), f2(float(t3.invuln))])

# ================================================================
# B. 흡혈
# ================================================================
## 그 출처의 피해 opt 한 벌(게임이 실제로 만드는 모양 그대로)
func src_opts(st: CombatState) -> Array:
	var w: Dictionary = st.weapons[0] if (st.weapons as Array).size() > 0 else {}
	var ws: Dictionary = w.get("stats", {}) if not w.is_empty() else {}
	var wid := String(w.get("id", "sword"))
	return [
		["주무기 기본 타격(main_direct)", { "src": { "weapon": ws, "weapon_id": wid, "level": 1, "direct": true } }],
		["주무기 개조 추가 타격(main_extra)", { "src": { "weapon": ws, "weapon_id": wid, "direct": false, "extra": true, "mod": "cross" } }],
		["공용 '메아리' 추가 타격(main_extra)", { "cause": "main_extra", "src": { "weapon": ws, "weapon_id": wid, "direct": true } }],
		["보조무기 직접 타격(support_direct)", { "src": { "weapon_id": "blades", "direct": true } }],
		["장판 틱(zone_tick)", { "cause": "zone_tick", "src": { "weapon_id": wid, "direct": false, "extra": true } }],
		["화상·출혈·독(dot)", { "src": { "extra": true, "direct": false }, "dot": "burn", "dot_src": "common" }],
		["수동 기술(감속장·낙뢰 등)", { "src": { "skill": true, "direct": false, "skill_id": "strike" } }],
		["장비 기술 [4] 찰나 가르기(eq_slash)", { "cause": "eq_slash", "src": { "skill": true, "direct": false, "skill_id": "eq_flashcut" } }],
		["장비 기술 [5] 낙성 강하 중심(eq_meteor_core)", { "cause": "eq_meteor_core", "src": { "skill": true, "direct": false, "skill_id": "eq_meteor" } }],
		["장비 기술 [6] 받아치기(eq_riposte)", { "cause": "eq_riposte", "src": { "skill": true, "direct": false, "skill_id": "eq_riposte" } }],
		["장비 기술 [7] 되짚는 궤적(eq_retrace)", { "cause": "eq_retrace", "src": { "skill": true, "direct": false, "skill_id": "eq_retrace" } }],
		["지뢰 폭발(mine_blast)", { "src": { "weapon_id": "mine", "direct": true } }],
		["파쇄 추가 피해(frost_shatter)", { "cause": "frost_shatter", "src": { "extra": true, "direct": false, "tag": "frost:shatter" } }],
		["감전 후속(shock_bonus)", { "cause": "shock_bonus", "src": { "weapon_id": "orb", "direct": false } }],
		["불꽃 파열(flare_burst)", { "cause": "flare_burst", "src": { "extra": true, "direct": false, "tag": "common:flare" } }],
		["가시 반격(reflect)", { "cause": "reflect", "src": { "extra": true, "direct": false } }],
	]

## 한 출처로 피해 한 번을 넣고 회복량을 잰다
func heal_by(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary) -> float:
	var before: float = float(st.player.hp)
	st.damage_enemy(e, dmg, opt)
	return float(st.player.hp) - before

func table_lifesteal() -> void:
	print("\n=== B. 흡혈 ===")
	var L: Dictionary = PCatalog.growth().LIFESTEAL
	print("자격 경로: %s · 제외 경로 %d종" % [str(L.eligible), (L.denied as Array).size()])
	print("\n-- B1. 출처별 자격(검 Lv3 흡혈 1.5% · 피해 100 · 적 체력 넉넉함) --")
	print("출처                                        피해  회복    자격")
	var st := mk("sword", "slowfield", "", { "lifesteal": 3 })
	st.player.hp = 10.0
	for row in src_opts(st):
		var e := dummy(st, 60.0, 0.0, 1.0e7)
		st.player.hp = 10.0
		var got := heal_by(st, e, 100.0, (row[1] as Dictionary).duplicate(true))
		print("%-42s  100  %s  %s" % [String(row[0]), f2(got), "적격" if got > 0.0 else "비적격"])
		e.dead = true

	print("\n-- B2. 초과 피해 제외(체력 10인 적에게 100 피해) --")
	for lvv in [1, 2, 3]:
		for wid in ["sword", "bow"]:
			var st2 := mk(String(wid), "slowfield", "", { "lifesteal": lvv })
			st2.player.hp = 10.0
			var e2 := dummy(st2, 60.0, 0.0, 10.0)
			var got2 := heal_by(st2, e2, 100.0, { "src": { "weapon": st2.weapons[0].stats, "weapon_id": String(wid), "direct": true } })
			print("%-8s Lv%d 비율 %.4f · 깎은 체력 10 · 회복 %s (100×비율이면 %s였을 것)" % [
				String(wid), lvv, float(st2.build.lifesteal), f2(got2), f2(100.0 * float(st2.build.lifesteal))])

	print("\n-- B3. 소수점 유지(약한 연타 누적) --")
	for wid3 in ["sword", "bow"]:
		var st3 := mk(String(wid3), "slowfield", "", { "lifesteal": 1 })
		st3.player.hp = 10.0
		var e3 := dummy(st3, 60.0, 0.0, 1.0e7)
		var o3 := { "src": { "weapon": st3.weapons[0].stats, "weapon_id": String(wid3), "direct": true } }
		var each := 0.0
		for i in 40:
			var b3: float = float(st3.player.hp)
			st3.damage_enemy(e3, 6.0, o3.duplicate(true))
			if i == 0:
				each = float(st3.player.hp) - b3
		print("%-8s 6 피해 × 40회 · 1회 회복 %s(정수로 버렸다면 0) · 누적 %s · 흡혈 집계 %s" % [
			String(wid3), f2(each), f2(float(st3.player.hp) - 10.0), f2(float(st3.stats.lifesteal))])

	print("\n-- B4. 최대 체력 상한 · 사망 되돌리기 없음 --")
	var st4 := mk("sword", "slowfield", "", { "lifesteal": 3 })
	var e4 := dummy(st4, 60.0, 0.0, 1.0e7)
	st4.player.hp = float(st4.player.hp_max)
	var o4 := { "src": { "weapon": st4.weapons[0].stats, "weapon_id": "sword", "direct": true } }
	st4.damage_enemy(e4, 1000.0, o4.duplicate(true))
	print("가득 찬 체력 %.1f/%.1f 에서 1000 피해 → %.1f (넘치지 않음)" % [float(st4.player.hp), float(st4.player.hp_max), float(st4.player.hp)])
	st4.player.hp = 0.0
	st4.damage_enemy(e4, 1000.0, o4.duplicate(true))
	print("체력 0에서 1000 피해 → %.1f (사망을 되돌리지 않음)" % float(st4.player.hp))

	print("\n-- B5. 보스·정예·다수·소환 --")
	for tid in ["wolf", "wolf_alpha"]:
		var st5 := mk("sword", "slowfield", "", { "lifesteal": 3 })
		st5.player.hp = 10.0
		var e5 := dummy(st5, 60.0, 0.0, 1.0e7, String(tid))
		var g5 := heal_by(st5, e5, 100.0, { "src": { "weapon": st5.weapons[0].stats, "weapon_id": "sword", "direct": true } })
		print("%-12s 100 피해 → 회복 %s" % [String(tid), f2(g5)])
	var st6 := mk("sword", "slowfield", "", { "lifesteal": 3 })
	st6.player.hp = 10.0
	var many := []
	for i in 6:
		many.append(dummy(st6, 50.0 + float(i) * 10.0, 0.0, 1.0e7))
	var o6 := { "src": { "weapon": st6.weapons[0].stats, "weapon_id": "sword", "direct": true } }
	for e6 in many:
		st6.damage_enemy(e6, 100.0, o6.duplicate(true))
	print("적 6마리에게 각각 100 피해 → 총 회복 %s (마리마다 따로 정산)" % f2(float(st6.player.hp) - 10.0))

	print("\n-- B6. 실제 전투 경로(자동공격을 켜고 5초) --")
	for wid4 in MAIN_WEAPONS:
		var st7 := mk(String(wid4), "slowfield", "", { "lifesteal": 3 }, {}, true)
		st7.player.hp = 10.0
		dummy(st7, 60.0, 0.0, 1.0e7)
		for i in int(round(5.0 / STEP)):
			st7.step(inp(), STEP)
		print("%-9s 5초 · 준 피해 %.1f · 흡혈 회복 %s · 체력 %.3f" % [
			String(wid4), float(st7.stats.get("damage_dealt", 0.0)) if st7.stats.has("damage_dealt") else _total_dmg(st7),
			f2(float(st7.stats.lifesteal)), float(st7.player.hp)])

func _total_dmg(st: CombatState) -> float:
	var s := 0.0
	for k in st.metrics.dmg:
		s += float(st.metrics.dmg[k])
	return s

# ================================================================
# C. 집중 — 일반 6종 + 장비 6종 × Lv0~3 × Q/E
# ================================================================
func uses_of(st: CombatState, slot: String) -> int:
	return int(st.stats.special_uses) if slot == "q" else int(st.stats.e_uses)

## **실제로 쓴 뒤 다시 쓸 수 있게 되는 시각**(초). 그 칸의 키를 매 단계 누르고 사용 횟수가 오르는 단계를 센다.
## 두 번째 사용이 나온 단계 - 첫 사용이 나온 단계. 선언값을 읽지 않는다
func recast_gap(sid: String, slot: String, focus_lv: int, weapon: String = "sword", limit: float = 40.0) -> Dictionary:
	var q_id := sid if slot == "q" else ""
	var e_id := sid if slot == "e" else ""
	var equip := {}
	if EQ_ROWS.has(sid):
		var row: Array = EQ_ROWS[sid]
		equip[String(row[0])] = String(row[1])
	# 장비 기술을 E에 두려면 Q에도 무언가 있어야 자연스럽다 — 비워 두면 Q 입력이 아무 일도 하지 않는다(계측에 영향 없음)
	var st := mk(weapon, q_id, e_id, { "focus": focus_lv }, equip)
	dummy(st, 120.0, 0.0)
	dummy(st, -120.0, 40.0)
	var press := inp(slot == "q", slot == "e")
	var n1 := -1
	var n2 := -1
	var n := 0
	var lim := int(round(limit / STEP))
	while n < lim:
		var before := uses_of(st, slot)
		st.step(press, STEP)
		n += 1
		if uses_of(st, slot) > before:
			if n1 < 0:
				n1 = n
			else:
				n2 = n
				break
	var decl: float = PSkills.cd_of(st, slot)
	return { "gap": float(n2 - n1) * STEP if n1 > 0 and n2 > 0 else -1.0, "decl": decl,
		"status": String(st.status), "first": float(n1) * STEP }

func table_focus() -> void:
	print("\n=== C. 집중 실측 재사용 (일반 6종 + 장비 6종 × Lv0~3 × Q/E) ===")
	var SK := PCatalog.skills()
	print("기술            칸 Lv0 선언/실측   Lv1 선언/실측   Lv2 선언/실측   Lv3 선언/실측")
	var all_ids: Array = NORMAL_SKILLS.duplicate()
	all_ids.append_array(PSkills.EQ_IDS)
	for sid in all_ids:
		for slot in ["q", "e"]:
			var line := "%-15s %s " % [String(SK[String(sid)].name), String(slot).to_upper()]
			for lv in 4:
				var r := recast_gap(String(sid), String(slot), lv)
				line += " %s/%s " % [f2(float(r.decl)), f2(float(r.gap))]
			print(line)

func table_swap() -> void:
	print("\n=== C2. Q/E 교환·장착/해제·저장 복구로 재사용이 초기화되지 않는가 ===")
	# 전투 중 레벨업 재계산(rebuild)은 실제로 일어난다. 그때 시계가 살아 있는지 본다
	for sid in ["gust", "eq_flashcut"]:
		var equip := {}
		if EQ_ROWS.has(String(sid)):
			var row: Array = EQ_ROWS[String(sid)]
			equip[String(row[0])] = String(row[1])
		var st := mk("sword", String(sid), "", { "focus": 0 }, equip)
		dummy(st, 120.0, 0.0)
		st.step(inp(true), STEP)
		for i in 120:
			st.step(inp(), STEP)
		var left0 := PSkills.cd_left(st, "q")
		st.rebuild(PBuild.derive(run_of("sword", String(sid), "", { "focus": 3 }, equip)))
		var left1 := PSkills.cd_left(st, "q")
		print("%-14s 1초 뒤 남은 재사용 %s → 전투 중 빌드 재계산(집중 0→3) 뒤 %s · 선언 %s" % [
			String(sid), f2(left0), f2(left1), f2(PSkills.cd_of(st, "q"))])
	# 거점에서의 Q/E 교환은 전투 밖이라 시계 자체가 없다. 교환 **뒤** 전투의 실측을 Q·E 양쪽으로 적는다
	print("교환 뒤 실측(같은 기술을 칸만 바꿔 다시 잰다):")
	for sid2 in ["gust", "ward", "eq_riposte", "eq_icetomb"]:
		var rq := recast_gap(String(sid2), "q", 2)
		var re := recast_gap(String(sid2), "e", 2)
		print("  %-14s 집중 Lv2 · Q %s · E %s · 선언 %s/%s" % [String(sid2), f2(float(rq.gap)), f2(float(re.gap)), f2(float(rq.decl)), f2(float(re.decl))])

# ================================================================
# D. 결정 관 + 집중 — 무적을 빈틈 없이 반복할 수 있는가
# ================================================================
## 결정 관을 최대(1.2초)까지 유지하며 반복할 때, 무적인 시간의 비율과 무적 사이의 빈틈
func tomb_cycle(focus_lv: int, extra_cd_mult: float = 1.0) -> Dictionary:
	var equip := { "shield": "crystal_coffin" }
	var run := run_of("sword", "eq_icetomb", "", { "focus": focus_lv }, equip)
	if not is_equal_approx(extra_cd_mult, 1.0):
		(run.buffs as Dictionary)["skillCd"] = extra_cd_mult # 시간의 샘(다음 전투 1회) — 다른 재사용 감소와 겹칠 때
	var b := PBuild.derive(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "arena": "clearing",
		"waves": [], "region_id": "lab", "act": 1,
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.obstacles = []
	st.player.x = 400.0
	st.player.y = 300.0
	st.player.attack_timer = 1.0e9
	dummy(st, 200.0, 0.0)
	var total := int(round(30.0 / STEP))
	var inv_n := 0
	var uses := 0
	var gap_now := 0
	var gap_min := 999999
	var press := inp(true)
	var idle := inp()
	for i in total:
		# 결정 관은 '누르면 갇히고, 최대 시간까지 유지'다. 매 단계 누르면 다음 단계에 곧바로 풀리므로
		# **최대 유지**를 재려면 첫 단계만 누르고 그 뒤에는 손을 뗀다
		var before := int(st.stats.special_uses)
		st.step(press if PSkills.cd_left(st, "q") <= 0.0 and st.eq_act.is_empty() else idle, STEP)
		if int(st.stats.special_uses) > before:
			uses += 1
		if PSkills.eq_invuln(st):
			inv_n += 1
			if gap_now > 0:
				gap_min = mini(gap_min, gap_now)
			gap_now = 0
		elif uses > 0:
			gap_now += 1
	return { "invuln_frac": float(inv_n) / float(total), "uses": uses,
		"gap_min": float(gap_min) * STEP if gap_min < 999999 else -1.0,
		"cd": float(b.special_cd) }

func table_tomb() -> void:
	print("\n=== D. 결정 관 + 집중: 무적을 빈틈 없이 반복할 수 있는가(30초) ===")
	print("조건                          재사용   사용횟수  무적 비율  무적 사이 최소 빈틈")
	for lv in 4:
		var r := tomb_cycle(lv)
		print("집중 Lv%d                      %s   %6d   %6.1f%%   %s초" % [
			lv, f2(float(r.cd)), int(r.uses), float(r.invuln_frac) * 100.0, f2(float(r.gap_min))])
	var r2 := tomb_cycle(3, 0.85)
	print("집중 Lv3 + 시간의 샘(-15%%)     %s   %6d   %6.1f%%   %s초" % [
		f2(float(r2.cd)), int(r2.uses), float(r2.invuln_frac) * 100.0, f2(float(r2.gap_min))])
	var r3 := tomb_cycle(3, 0.85 * 0.85)
	print("집중 Lv3 + 샘 + 박자(-15%% 2회)  %s   %6d   %6.1f%%   %s초" % [
		f2(float(r3.cd)), int(r3.uses), float(r3.invuln_frac) * 100.0, f2(float(r3.gap_min))])
	print("(결정 관 최대 유지 %.2f초 — data/growth.json skills.eq_icetomb.tune.max)" % float(PSkills.eq_tune("eq_icetomb").get("max", 1.2)))
	print("\n-- 방어 성격 기술 셋: 한 번의 보호 길이 vs **실측** 최소 재사용(집중 Lv3) --")
	print("기술            보호 길이  실측 재사용(Lv3)  최대 보호 비율  빈틈")
	var guard_rows := [
		["eq_icetomb", float(PSkills.eq_tune("eq_icetomb").get("max", 1.2)), "완전 무적"],
		["eq_riposte", float(PSkills.eq_tune("eq_riposte").get("guard", 0.45)), "정면 방어 창"],
		["eq_reprieve", float(PSkills.eq_tune("eq_reprieve").get("dur", 3.0)), "피해 유예 창"],
	]
	for row in guard_rows:
		var sid := String(row[0])
		var dur := float(row[1])
		var r := recast_gap(sid, "q", 3)
		var gap := float(r.gap) - dur
		print("%-14s %s   %s        %5.1f%%      %s초 %s" % [
			String(PCatalog.skills()[sid].name), f2(dur), f2(float(r.gap)),
			dur / maxf(0.001, float(r.gap)) * 100.0, f2(gap), String(row[2])])

# ================================================================
func _init() -> void:
	print("# pass_probe — 회피 숙련·흡혈·집중 실측 (전부 첫 시험값)")
	table_dodge()
	table_lifesteal()
	table_focus()
	table_swap()
	table_tomb()
	print("\n# 끝")
	quit(0)
