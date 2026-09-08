extends SceneTree
## 주무기·보조무기 슬롯 구조와 저장 호환(화면 없음):
##   godot --headless --path prophecy_godot -s tests/slots_tests.gd
##
## 확정된 구조(사용자 지시 1절):
##  - 주무기 1개. 최대 Lv5, 개조 최대 2개. 개조 자격은 Lv2에 첫 번째, Lv4에 두 번째.
##  - 공통 보조 2개. 각각 최대 Lv3, 개조 최대 1개. 개조 자격은 그 보조의 Lv2.
##  - 개조 자격이 열려도 자동 지급하지 않는다(성장 선택을 따로 쓴다).
##  - 주무기와 보조는 개별적으로 오른다. 한 선택으로 다른 무기까지 오르지 않는다.
##
## 저장 호환(6절): 옛 회차는 옛 구조 그대로 끝까지 마칠 수 있다. 무기를 지우거나 하나를 골라 주지 않는다.
## 여기 나오는 수치는 전부 시험값이며 사람이 승인한 밸런스가 아니다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 새 구조 회차
func mk_v2(start: String = "sword") -> Dictionary:
	return PRun.new_run(11, start)

## 옛 구조 저장 흉내: structure 표시가 없고 주무기 계열이 여러 개 들어 있다
func mk_v1() -> Dictionary:
	var run := PRun.new_run(11, "sword")
	var g: Dictionary = run.growth
	g.erase("structure")
	g.weapons = [{ "id": "sword", "level": 3, "mods": ["cross"] }, { "id": "spear", "level": 2, "mods": [] }, { "id": "bow", "level": 1, "mods": [] }]
	return run

## JSON 숫자는 float으로 들어온다. 자격 레벨 비교는 정수로 맞춘다
func _ints(a: Array) -> Array:
	var out := []
	for x in a:
		out.append(int(x))
	return out

func kinds_of(run: Dictionary) -> Dictionary:
	var out := {}
	for c in PGrowth.candidates(run, { "pool": "level" }):
		out[String(c.kind)] = int(out.get(String(c.kind), 0)) + 1
	return out

func has_cand(run: Dictionary, kind: String, id: String, mod_id: String = "") -> bool:
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if String(c.kind) == kind and String(c.id) == id and (mod_id == "" or String(c.get("mod", "")) == mod_id):
			return true
	return false

func _init() -> void:
	var R := PCatalog.slot_rules()

	# ---------- 1. 자료 계약 ----------
	ok("슬롯 규칙이 데이터에 있다: 주무기 1·Lv5·개조 2(자격 2,4) · 보조 2·Lv3·개조 1(자격 2)",
		int(R.main) == 1 and int(R.mainMax) == 5 and int(R.mainMods) == 2 and _ints(R.modUnlockMain) == [2, 4]
		and int(R.supports) == 2 and int(R.supportMax) == 3 and int(R.supportMods) == 1 and _ints(R.modUnlockSupport) == [2],
		JSON.stringify(R))
	var W := PCatalog.weapons()
	var sup := []
	var main := []
	for wid in W:
		if PCatalog.is_main_weapon(String(wid)):
			main.append(String(wid))
		else:
			sup.append(String(wid))
	ok("무기 명단: 주무기 5종 · 보조 12종", main.size() == 5 and sup.size() == 12, "%s / %d" % [str(main), sup.size()])
	var mod_n := 0
	for wid in sup:
		mod_n += (W[wid].get("mods", {}) as Dictionary).size()
	ok("보조 12종의 개조 후보가 종당 3개, 합쳐 36개", mod_n == 36, "%d개" % mod_n)
	var excluded := ["chain_weapon", "turret", "crusher", "scythe", "banner"]
	var found := []
	for x in excluded:
		if W.has(x):
			found.append(x)
	ok("이번 명단에서 뺀 것(사슬·수정 포탑·파쇄 정령·수확 낫·전투 깃발)이 들어와 있지 않다", found.is_empty(), str(found))

	# ---------- 2. 새 회차의 시작 상태 ----------
	var run := mk_v2()
	var g: Dictionary = run.growth
	ok("새 회차는 새 구조 표시를 갖는다", PGrowth.is_v2(g) and PGrowth.structure_of(g) == "v2")
	ok("시작은 주무기 1개뿐(보조 0개)", PGrowth.main_weapons(g).size() == 1 and PGrowth.support_weapons(g).size() == 0)
	ok("시작 선택 목록은 주무기만이다(회전 칼날이 시작 선택에 없다)",
		PCatalog.startable().all(func(x): return PCatalog.is_main_weapon(String(x))) and not (PCatalog.startable() as Array).has("blades"),
		str(PCatalog.startable()))

	# ---------- 3. 주무기: Lv5 · 개조 자격 Lv2/Lv4 ----------
	var w0: Dictionary = g.weapons[0]
	ok("주무기 Lv1에는 개조 후보가 없다", PGrowth.mod_quota_of(g, w0) == 0 and int(kinds_of(run).get("weapon_mod", 0)) == 0)
	w0.level = 2
	ok("주무기 Lv2에서 개조 자격 1개(자동 지급이 아니라 후보로만 나온다)",
		PGrowth.mod_quota_of(g, w0) == 1 and (w0.mods as Array).is_empty() and int(kinds_of(run).get("weapon_mod", 0)) > 0)
	(w0.mods as Array).append("cross")
	w0.level = 3
	ok("개조 1개를 가진 Lv3 주무기는 두 번째 개조 후보가 없다",
		PGrowth.mod_quota_of(g, w0) == 1 and int(kinds_of(run).get("weapon_mod", 0)) == 0)
	w0.level = 4
	ok("주무기 Lv4에서 두 번째 개조 자격", PGrowth.mod_quota_of(g, w0) == 2 and int(kinds_of(run).get("weapon_mod", 0)) > 0)
	w0.level = 5
	ok("주무기 레벨 상한 5: Lv5에서는 레벨 후보가 없다", PGrowth.level_cap(g, "sword") == 5 and not has_cand(run, "weapon_level", "sword"))
	ok("주무기 Lv5에서 레벨 선택을 적용해도 오르지 않는다", not PGrowth.apply_choice(run, { "kind": "weapon_level", "id": "sword" }) and int(w0.level) == 5)
	(w0.mods as Array).append("scar")
	ok("주무기 개조 상한 2: 세 번째 개조는 후보에도 없고 적용도 안 된다",
		int(kinds_of(run).get("weapon_mod", 0)) == 0 and not PGrowth.apply_choice(run, { "kind": "weapon_mod", "id": "sword", "mod": "crescent" }))

	# ---------- 4. 새 자동기술은 보조만 ----------
	var run2 := mk_v2()
	var g2: Dictionary = run2.growth
	var new_ids := []
	for c in PGrowth.candidates(run2, { "pool": "level" }):
		if String(c.kind) == "weapon_new":
			new_ids.append(String(c.id))
	ok("새 자동기술 후보에 주무기가 섞이지 않는다", new_ids.size() > 0 and new_ids.all(func(x): return not PCatalog.is_main_weapon(String(x))), str(new_ids))
	ok("주무기를 하나 더 얻으려 해도 거부된다", not PGrowth.apply_choice(run2, { "kind": "weapon_new", "id": "spear" }) and PGrowth.main_weapons(g2).size() == 1)
	ok("보조 1개 획득", PGrowth.apply_choice(run2, { "kind": "weapon_new", "id": "blades" }) and PGrowth.support_weapons(g2).size() == 1)
	ok("보조 2개 획득", PGrowth.apply_choice(run2, { "kind": "weapon_new", "id": "orb" }) and PGrowth.support_weapons(g2).size() == 2)
	ok("보조 상한 2: 세 번째 보조는 후보에 없고 적용도 안 된다",
		int(kinds_of(run2).get("weapon_new", 0)) == 0 and not PGrowth.apply_choice(run2, { "kind": "weapon_new", "id": "frost" }),
		str(PGrowth.support_weapons(g2).size()))

	# ---------- 5. 보조: Lv3 · 개조 자격 Lv2 · 개조 1개 ----------
	var sw: Dictionary = PGrowth.weapon_of(g2, "blades")
	ok("보조 레벨 상한은 3", PGrowth.level_cap(g2, "blades") == 3)
	ok("보조 Lv1에는 개조 후보가 없다", PGrowth.mod_quota_of(g2, sw) == 0 and not has_cand(run2, "weapon_mod", "blades"))
	var before_main := int((g2.weapons[0] as Dictionary).level)
	var before_orb := int(PGrowth.weapon_of(g2, "orb").level)
	var lv_ok := PGrowth.apply_choice(run2, { "kind": "weapon_level", "id": "blades" })
	ok("보조 레벨업은 그 보조만 올린다(다른 무기는 그대로)",
		lv_ok and int(sw.level) == 2 and int((g2.weapons[0] as Dictionary).level) == before_main and int(PGrowth.weapon_of(g2, "orb").level) == before_orb)
	var blade_mods := []
	for c in PGrowth.candidates(run2, { "pool": "level" }):
		if String(c.kind) == "weapon_mod" and String(c.id) == "blades":
			blade_mods.append(String(c.mod))
	blade_mods.sort()
	ok("보조 Lv2에서 개조 자격 1개 · 후보는 그 보조의 3개 중에서만 나온다",
		PGrowth.mod_quota_of(g2, sw) == 1 and blade_mods == ["dual", "launch", "serrated"], str(blade_mods))
	var mod_ok := PGrowth.apply_choice(run2, { "kind": "weapon_mod", "id": "blades", "mod": "dual" })
	ok("보조 개조 상한 1: 하나 고르면 나머지 후보가 사라진다",
		mod_ok and not has_cand(run2, "weapon_mod", "blades") and not PGrowth.apply_choice(run2, { "kind": "weapon_mod", "id": "blades", "mod": "launch" }))
	PGrowth.apply_choice(run2, { "kind": "weapon_level", "id": "blades" })
	ok("보조 Lv3이 상한: Lv3에서는 레벨 후보가 없다",
		int(sw.level) == 3 and not has_cand(run2, "weapon_level", "blades") and not PGrowth.apply_choice(run2, { "kind": "weapon_level", "id": "blades" }))

	# ---------- 6. 보조 레벨업은 역할에 맞는 성능을 올린다 ----------
	var LS := PCatalog.level_scale()
	var only_damage := []
	for wid in W:
		if PCatalog.is_main_weapon(String(wid)):
			continue
		var sc: Dictionary = LS.get(String(wid), {})
		if sc.is_empty() or (sc.size() == 1 and sc.has("damage")):
			only_damage.append(String(wid))
	ok("보조 12종 모두 피해 말고 역할 항목이 하나 이상 오른다", only_damage.is_empty(), str(only_damage))
	var b3 := PBuild.derive(run2)
	var blade_s := {}
	for x in b3.weapons:
		if String(x.id) == "blades":
			blade_s = x
	var g_lv1 := PGrowth.new_growth("sword")
	g_lv1.weapons.append({ "id": "blades", "level": 1, "mods": [] })
	var b1 := PBuild.derive(PBuild.empty_run_like(g_lv1))
	var blade1 := {}
	for x in b1.weapons:
		if String(x.id) == "blades":
			blade1 = x
	ok("회전 칼날 Lv1→Lv3에서 피해와 반지름이 함께 오른다",
		float(blade_s.damage) > float(blade1.damage) and float(blade_s.radius) > float(blade1.radius),
		"피해 %.1f→%.1f 반지름 %.1f→%.1f" % [float(blade1.damage), float(blade_s.damage), float(blade1.radius), float(blade_s.radius)])

	# ---------- 7. 옛 저장 호환 ----------
	var runv1 := mk_v1()
	var gv1: Dictionary = runv1.growth
	ok("표시가 없는 옛 저장은 옛 구조로 읽힌다", not PGrowth.is_v2(gv1) and PGrowth.structure_of(gv1) == "v1")
	ok("옛 저장의 주무기 계열 3개를 지우지 않는다", (gv1.weapons as Array).size() == 3, str((gv1.weapons as Array).size()))
	ok("옛 저장에서는 주무기 계열도 예전처럼 Lv5까지 오른다", PGrowth.level_cap(gv1, "spear") == 5 and has_cand(runv1, "weapon_level", "spear"))
	var sp_old := PGrowth.weapon_of(gv1, "spear")
	ok("옛 저장의 개조 자격은 예전 규칙(Lv2·Lv4, 무기당 2개)",
		PGrowth.mod_cap(gv1, "spear") == 2 and PGrowth.mod_quota_of(gv1, sp_old) == 1)
	ok("옛 저장은 슬롯이 다 차서 새 자동기술 후보가 없다(3/3)", int(kinds_of(runv1).get("weapon_new", 0)) == 0)
	var gv1b := (mk_v1().growth as Dictionary)
	gv1b.weapons = [{ "id": "sword", "level": 1, "mods": [] }]
	var runv1b := PBuild.empty_run_like(gv1b)
	runv1b.growth = gv1b
	var v1_new := []
	for c in PGrowth.candidates({ "growth": gv1b, "seed": 1, "gold": 0 }, { "pool": "level" }):
		if String(c.kind) == "weapon_new":
			v1_new.append(String(c.id))
	ok("옛 저장에서는 주무기 계열도 계속 새 자동기술 후보로 나온다(옛 규칙 그대로)",
		v1_new.has("spear") or v1_new.has("bow") or v1_new.has("hammer"), str(v1_new))

	# ---------- 8. 저장·복구를 지나도 구조가 유지된다 ----------
	var txt := JSON.stringify(run2)
	var back: Dictionary = JSON.parse_string(txt)
	ok("직렬화 뒤에도 새 구조 표시가 남는다", PGrowth.is_v2(back.growth as Dictionary))
	ok("직렬화 뒤에도 상한이 그대로다",
		PGrowth.level_cap(back.growth, "blades") == 3 and PGrowth.mod_cap(back.growth, "sword") == 2)

	# ---------- 9. 상한을 넘긴 저장값은 계산에서만 잘라 쓴다 ----------
	var gover := PGrowth.new_growth("sword")
	gover.weapons.append({ "id": "blades", "level": 5, "mods": ["dual", "launch"] })
	var bover := PBuild.derive(PBuild.empty_run_like(gover))
	var bl_over := {}
	for x in bover.weapons:
		if String(x.id) == "blades":
			bl_over = x
	ok("보조가 Lv5로 저장돼 있어도 계산은 Lv3까지만 쓴다(저장값은 그대로 둔다)",
		is_equal_approx(float(bl_over.damage), float(blade_s.damage)) and int((gover.weapons[1] as Dictionary).level) == 5,
		"%.2f vs %.2f" % [float(bl_over.damage), float(blade_s.damage)])

	# ---------- 10. 옛 구조 저장을 실제로 저장·복구하고 계속 진행할 수 있다 ----------
	# 규칙 계층뿐 아니라 저장 파일을 거쳐도 옛 회차가 옛 구조 그대로 굴러가야 한다(사용자 지시 6절).
	PSave.clear()
	var runsave := mk_v1()
	runsave.gold = 500
	PSave.save(runsave)
	var loaded := PSave.load()
	var gl: Dictionary = loaded.growth
	ok("저장·복구를 거쳐도 옛 회차는 옛 구조다", not PGrowth.is_v2(gl) and (gl.weapons as Array).size() == 3)
	ok("옛 회차도 성장 선택을 계속 적용할 수 있다(창 레벨업)",
		PGrowth.apply_choice(loaded, { "kind": "weapon_level", "id": "spear" }) and int(PGrowth.weapon_of(gl, "spear").level) == 3)
	var bl := PBuild.derive(loaded)
	ok("옛 회차의 빌드 계산이 정상이다(자동기술 3개 전부 파생됨)", (bl.weapons as Array).size() == 3)
	var acts := PFlow.actions(loaded)
	ok("옛 회차도 거점 행동 목록이 비어 있지 않다(상점·대장간 등)", (acts as Array).size() > 0, "%d개" % (acts as Array).size())
	PSave.clear()

	# ---------- 11. 새 회차도 저장·복구 뒤 상한이 유지된다 ----------
	var run3 := mk_v2()
	PGrowth.apply_choice(run3, { "kind": "weapon_new", "id": "blades" })
	PGrowth.apply_choice(run3, { "kind": "weapon_new", "id": "orb" })
	PSave.save(run3)
	var l3 := PSave.load()
	ok("새 회차 저장·복구 뒤에도 세 번째 보조는 못 얻는다",
		not PGrowth.apply_choice(l3, { "kind": "weapon_new", "id": "frost" }) and PGrowth.support_weapons(l3.growth).size() == 2)
	ok("새 회차 저장·복구 뒤에도 주무기는 하나뿐이다",
		not PGrowth.apply_choice(l3, { "kind": "weapon_new", "id": "bow" }) and PGrowth.main_weapons(l3.growth).size() == 1)
	PSave.clear()

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
