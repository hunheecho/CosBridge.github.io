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

	# ---------- 12. 회차를 끝까지 굴려도 상한이 깨지지 않는다 ----------
	# 규칙 단위 시험만으로는 상점 교체·대장간 개조 변경·임무 보상 같은 **다른 경로**가 상한을 넘기는지 못 잡는다.
	# 실제 회차를 한 번 끝까지 굴려서 성장 상태의 불변식을 확인한다.
	var sim := PRunBot.simulate(21, "matched", {})
	var rs = sim.get("run_state", null)
	var broke := []
	if rs != null and typeof(rs) == TYPE_DICTIONARY:
		var gs: Dictionary = (rs as Dictionary).growth
		for w in gs.weapons:
			if (w.mods as Array).size() > PGrowth.mod_cap(gs, String(w.id)):
				broke.append("%s 개조 %d > %d" % [String(w.id), (w.mods as Array).size(), PGrowth.mod_cap(gs, String(w.id))])
			if int(w.level) > PGrowth.level_cap(gs, String(w.id)):
				broke.append("%s 레벨 %d > %d" % [String(w.id), int(w.level), PGrowth.level_cap(gs, String(w.id))])
		if PGrowth.main_weapons(gs).size() > 1:
			broke.append("주무기 %d개" % PGrowth.main_weapons(gs).size())
		if PGrowth.support_weapons(gs).size() > 2:
			broke.append("보조 %d개" % PGrowth.support_weapons(gs).size())
	else:
		broke.append("회차 상태를 못 읽었다")
	ok("회차를 끝까지 굴려도 주무기 1·보조 2·레벨·개조 상한이 깨지지 않는다", broke.is_empty(), str(broke))

	# ---------- 13. 대장간 '기술 교체'가 주무기 ↔ 보조를 넘나들지 않는다 ----------
	# 2026-09-09 발견: PRun.swap_quote가 후보를 **보유하지 않은 모든 자동기술**로 냈다.
	# 그래서 주무기(Lv5·개조 2)를 보조로 바꿀 수 있었고, 그러면 보조가 Lv5·개조 2개(상한은 Lv3·개조 1)에
	# 주무기 0개·보조 3개인 회차가 됐다. 슬롯 불변식 검사(§12)는 회차 봇이 교체를 쓰지 않아 이 구멍을 못 잡았다.
	# 막을 곳은 두 군데다: ① 후보를 만들 때 ② 확정할 때(후보를 지나 들어와도 거부).
	var runsw := mk_v2()
	var gsw: Dictionary = runsw.growth
	gsw.weapons = [{ "id": "sword", "level": 5, "mods": ["cross", "scar"] }, { "id": "blades", "level": 3, "mods": ["dual"] }]
	runsw.gold = 2000
	var q_main := PRun.swap_quote(runsw, "weapon", 0)
	var q_sup := PRun.swap_quote(runsw, "weapon", 1)
	var main_opts: Array = q_main.options
	var sup_opts: Array = q_sup.options
	ok("① 주무기 자리의 교체 후보는 주무기뿐이다",
		main_opts.size() > 0 and main_opts.all(func(x): return PCatalog.is_main_weapon(String(x))), str(main_opts))
	ok("① 보조 자리의 교체 후보는 보조뿐이다",
		sup_opts.size() > 0 and sup_opts.all(func(x): return not PCatalog.is_main_weapon(String(x))), str(sup_opts))
	ok("① 견적이 자리 이름·상한을 함께 알려 준다(화면이 계산하지 않게)",
		String(q_main.role) == "main" and int(q_main.levelCap) == 5 and int(q_main.modCap) == 2
		and String(q_sup.role) == "support" and int(q_sup.levelCap) == 3 and int(q_sup.modCap) == 1,
		"%s/%s" % [str(q_main.role), str(q_sup.role)])
	# ② 확정에서도 막힌다 — 그리고 실패에는 금화가 한 푼도 나가지 않는다
	var gold0 := int(runsw.gold)
	var cross1 := PRun.apply_swap(runsw, "weapon", 0, "bell", [])          # 주무기 자리에 보조
	var cross2 := PRun.apply_swap(runsw, "weapon", 1, "spear", [])         # 보조 자리에 주무기
	ok("② 확정 단계도 주무기 ↔ 보조 교차 교체를 거부한다(-1)", cross1 == -1 and cross2 == -1, "%d / %d" % [cross1, cross2])
	ok("② 거부된 교체에는 금화가 나가지 않고 무기도 그대로다",
		int(runsw.gold) == gold0 and String(gsw.weapons[0].id) == "sword" and String(gsw.weapons[1].id) == "blades",
		"금화 %d → %d · %s" % [gold0, int(runsw.gold), str([String(gsw.weapons[0].id), String(gsw.weapons[1].id)])])
	ok("② 교차 교체가 막히니 주무기 1 · 보조 2 구조가 유지된다",
		PGrowth.main_weapons(gsw).size() == 1 and PGrowth.support_weapons(gsw).size() == 1)
	# ③ 정상 교환(주무기 → 다른 주무기): 슬롯·레벨·개조 상한과 금화 처리를 확인한다
	var new_main := String(main_opts[0])
	var mod_ids := []
	for mid in (W[new_main].mods as Dictionary):
		if bool(W[new_main].mods[mid].impl) and mod_ids.size() < int(q_main.modCount):
			mod_ids.append(String(mid))
	var gold1 := int(runsw.gold)
	var paid := PRun.apply_swap(runsw, "weapon", 0, new_main, mod_ids)
	var w_new: Dictionary = gsw.weapons[0]
	ok("③ 같은 자리(주무기 → 주무기) 교환은 정상 처리된다",
		paid == int(q_main.price) and String(w_new.id) == new_main, "%d금 · %s" % [paid, String(w_new.id)])
	ok("③ 교환 뒤 슬롯 수가 그대로다(주무기 1 · 보조 1)",
		PGrowth.main_weapons(gsw).size() == 1 and PGrowth.support_weapons(gsw).size() == 1 and (gsw.weapons as Array).size() == 2)
	ok("③ 교환 뒤 레벨·개조가 새 자리의 상한 안이다(주무기 Lv5 / 개조 2)",
		int(w_new.level) == 5 and int(w_new.level) <= PGrowth.level_cap(gsw, new_main)
		and (w_new.mods as Array).size() == 2 and (w_new.mods as Array).size() <= PGrowth.mod_cap(gsw, new_main),
		"Lv%d · 개조 %d/%d" % [int(w_new.level), (w_new.mods as Array).size(), PGrowth.mod_cap(gsw, new_main)])
	ok("③ 교환 뒤 개조 수가 그 레벨의 개조 자격 안이다(Lv5 주무기 = 2개까지)",
		(w_new.mods as Array).size() <= PGrowth.mod_quota_of(gsw, w_new),
		"개조 %d · 자격 %d" % [(w_new.mods as Array).size(), PGrowth.mod_quota_of(gsw, w_new)])
	ok("③ 금화는 **정확히 한 번** 견적만큼만 빠진다(이중 차감·미차감 없음)",
		int(runsw.gold) == gold1 - int(q_main.price), "%d → %d (견적 %d)" % [gold1, int(runsw.gold), int(q_main.price)])
	# ④ 보조 → 보조 교환도 같은 규칙(레벨 3 · 개조 1 상한 안)
	var q_sup2 := PRun.swap_quote(runsw, "weapon", 1)
	var new_sup := String((q_sup2.options as Array)[0])
	var smods := []
	for mid2 in (W[new_sup].mods as Dictionary):
		if bool(W[new_sup].mods[mid2].impl) and smods.size() < int(q_sup2.modCount):
			smods.append(String(mid2))
	var gold2 := int(runsw.gold)
	var paid2 := PRun.apply_swap(runsw, "weapon", 1, new_sup, smods)
	var s_new: Dictionary = gsw.weapons[1]
	ok("④ 보조 → 보조 교환: 레벨 3 · 개조 1 상한을 넘지 않는다",
		paid2 == int(q_sup2.price) and int(s_new.level) <= PGrowth.level_cap(gsw, new_sup)
		and (s_new.mods as Array).size() <= PGrowth.mod_cap(gsw, new_sup),
		"%s Lv%d · 개조 %d" % [String(s_new.id), int(s_new.level), (s_new.mods as Array).size()])
	ok("④ 보조 교환에도 금화가 한 번만 빠진다", int(runsw.gold) == gold2 - int(q_sup2.price),
		"%d → %d (견적 %d)" % [gold2, int(runsw.gold), int(q_sup2.price)])
	# 상한 확인은 **평범한 반복문**으로 쓴다. 회차 사전을 붙잡는 람다를 여기 두면 종료할 때 프로세스가 죽는다
	# (2026-09-09 확인: 58/58 통과 뒤 종료 코드 3221225477. 단언은 통과해도 그것은 종료 실패다)
	var caps_ok := true
	for w2 in (gsw.weapons as Array):
		if int(w2.level) > PGrowth.level_cap(gsw, String(w2.id)) or (w2.mods as Array).size() > PGrowth.mod_cap(gsw, String(w2.id)):
			caps_ok = false
	ok("④ 두 번 교환한 뒤에도 주무기 1 · 보조 1이고 모든 상한이 지켜진다",
		PGrowth.main_weapons(gsw).size() == 1 and PGrowth.support_weapons(gsw).size() == 1 and caps_ok,
		str(gsw.weapons))
	# ⑤ 옛 저장(v1)은 옛 규칙 그대로 — 자리 구분이 없으므로 아무 자동기술로나 바꾼다(6절)
	var runv1c := mk_v1()
	var q_v1 := PRun.swap_quote(runv1c, "weapon", 0)
	var v1_opts: Array = q_v1.options
	ok("⑤ 옛 저장은 교체 후보를 좁히지 않는다(옛 구조 그대로 끝까지)",
		v1_opts.any(func(x): return PCatalog.is_main_weapon(String(x))) and v1_opts.any(func(x): return not PCatalog.is_main_weapon(String(x))),
		"%d개" % v1_opts.size())

	# ---------- 14. 상한·자격이 **저장 복구 · 개조 변경 · 보상** 경로에서도 지켜진다 ----------
	# §13은 후보 생성과 확정(교환)만 봤다. 여기서는 §13이 보지 않던 세 경로를 본다.
	# 사용자 의심("Lv1 번개 구체에서 전도 표식을 얻었다")에 대한 답도 여기 있다: 자격 판정은
	# **레벨업 3택·임무 보상·개조 변경** 세 경로가 모두 PGrowth.mod_quota_of 하나를 쓰므로
	# 어느 경로로도 Lv1 무기에 개조가 붙지 않는다. (그 저장의 실제 기록은 획득 → 레벨업 → 개조 순서였다.)

	# ⑥ 저장 복구: 저장했다 불러와도 자리 구분·상한·자격이 그대로다
	var run_sv := mk_v2()
	var g_sv: Dictionary = run_sv.growth
	g_sv.weapons = [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "orb", "level": 2, "mods": [] }]
	run_sv.gold = 2000
	var before_caps := []
	for w3 in (g_sv.weapons as Array):
		before_caps.append("%s:%d/%d/%d" % [String(w3.id), PGrowth.level_cap(g_sv, String(w3.id)), PGrowth.mod_cap(g_sv, String(w3.id)), PGrowth.mod_quota_of(g_sv, w3)])
	var q_before: Array = PRun.swap_quote(run_sv, "weapon", 1).options
	var loaded_sv: Dictionary = JSON.parse_string(JSON.stringify(PSave.normalize(run_sv.duplicate(true))))
	PSave.normalize(loaded_sv)
	var g_ld: Dictionary = loaded_sv.growth
	var after_caps := []
	for w4 in (g_ld.weapons as Array):
		after_caps.append("%s:%d/%d/%d" % [String(w4.id), PGrowth.level_cap(g_ld, String(w4.id)), PGrowth.mod_cap(g_ld, String(w4.id)), PGrowth.mod_quota_of(g_ld, w4)])
	var q_after: Array = PRun.swap_quote(loaded_sv, "weapon", 1).options
	ok("⑥ 저장·복구해도 상한·개조 자격이 같다(구조 표시가 사라지지 않는다)",
		str(before_caps) == str(after_caps) and PGrowth.is_v2(g_ld), "%s → %s" % [str(before_caps), str(after_caps)])
	ok("⑥ 저장·복구해도 교환 후보가 자리를 넘지 않는다(보조 자리 = 보조뿐)",
		str(q_before) == str(q_after) and q_after.size() > 0 and q_after.all(func(x): return not PCatalog.is_main_weapon(String(x))),
		"%d개" % q_after.size())
	var runv1s := mk_v1()
	var loaded_v1: Dictionary = JSON.parse_string(JSON.stringify(PSave.normalize(runv1s.duplicate(true))))
	PSave.normalize(loaded_v1)
	ok("⑥ 옛 저장(v1)은 복구해도 옛 구조 그대로다(새 상한을 소급하지 않는다)",
		not PGrowth.is_v2(loaded_v1.growth) and (loaded_v1.growth.weapons as Array).size() == 3,
		"구조 %s · 무기 %d개" % [PGrowth.structure_of(loaded_v1.growth), (loaded_v1.growth.weapons as Array).size()])

	# ⑥-3 상한을 넘긴 상태를 불러와도 **더 늘리지 않는다**(옛 결함이 남긴 저장의 방어선)
	var run_over := mk_v2()
	var g_over: Dictionary = run_over.growth
	g_over.weapons = [{ "id": "sword", "level": 5, "mods": ["cross", "scar"] }, { "id": "orb", "level": 5, "mods": ["conduct", "fork"] }]
	var grow_more := []
	for c3 in PGrowth.candidates(run_over, { "pool": "level" }):
		if String(c3.get("id", "")) == "orb" and (String(c3.kind) == "weapon_level" or String(c3.kind) == "weapon_mod"):
			grow_more.append(String(c3.kind))
	var forced_lv := PGrowth.apply_choice(run_over, { "kind": "weapon_level", "id": "orb" }, true)
	var forced_md := PGrowth.apply_choice(run_over, { "kind": "weapon_mod", "id": "orb", "mod": "loop" }, true)
	ok("⑥ 상한을 넘긴 옛 상태를 불러와도 그 무기를 **더 올리거나 개조를 더 주지 않는다**",
		grow_more.is_empty() and not forced_lv and not forced_md, str(grow_more))

	# ⑦ 개조 변경(대장간·개조 변경권): 개수를 늘리지 않고 자격 안에서만 바뀐다
	var run_mc := mk_v2()
	var g_mc: Dictionary = run_mc.growth
	g_mc.weapons = [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "orb", "level": 2, "mods": [] }]
	run_mc.gold = 2000
	var gold_mc := int(run_mc.gold)
	var off_mc := PFlow.mod_change(run_mc, "sword", "cross")
	var w_mc: Dictionary = g_mc.weapons[0]
	var mc_ok := true
	if (off_mc as Dictionary).is_empty():
		mc_ok = int(run_mc.gold) == gold_mc # 후보가 없으면 아무것도 차감하지 않는다
	else:
		var pick_mc: Dictionary = (off_mc.choices as Array)[0]
		PGrowth.apply_choice(run_mc, pick_mc)
		g_mc.pendingOffer = null
		mc_ok = (w_mc.mods as Array).size() == 1 and int(run_mc.gold) < gold_mc
	ok("⑦ 개조 변경은 개조 **수를 늘리지 않는다**(1개 → 1개)",
		mc_ok and (w_mc.mods as Array).size() <= PGrowth.mod_quota_of(g_mc, w_mc),
		"개조 %d · 자격 %d · 금화 %d → %d" % [(w_mc.mods as Array).size(), PGrowth.mod_quota_of(g_mc, w_mc), gold_mc, int(run_mc.gold)])
	var gold_mc2 := int(run_mc.gold)
	var bad_mc := PFlow.mod_change(run_mc, "orb", "conduct") # 갖고 있지 않은 개조를 바꾸려 한다
	ok("⑦ 갖고 있지 않은 개조는 변경할 수 없고 금화도 나가지 않는다",
		(bad_mc as Dictionary).is_empty() and int(run_mc.gold) == gold_mc2, "금화 %d → %d" % [gold_mc2, int(run_mc.gold)])

	# ⑧ 보상 경로: Lv1 무기에는 **어떤 경로로도** 개조가 붙지 않는다(자격 Lv2)
	var run_new1 := mk_v2()
	var g_new1: Dictionary = run_new1.growth
	g_new1.weapons = [{ "id": "sword", "level": 1, "mods": [] }, { "id": "orb", "level": 1, "mods": [] }]
	var new1_mod := []
	for c4 in PGrowth.candidates(run_new1, { "pool": "level" }):
		if String(c4.kind) == "weapon_mod":
			new1_mod.append("%s:%s" % [String(c4.id), String(c4.get("mod", ""))])
	var off_new1 := PGrowth.generate_offer(run_new1, { "pool": "mission", "kinds": ["weapon_mod"], "missionKind": "weapon_mod", "region_id": "" })
	var new1_offer := []
	for c5 in (off_new1.choices as Array):
		if String(c5.kind) == "weapon_mod":
			new1_offer.append("%s:%s" % [String(c5.id), String(c5.get("mod", ""))])
	g_new1.pendingOffer = null
	var forced_new1 := PGrowth.apply_choice(run_new1, { "kind": "weapon_mod", "id": "orb", "mod": "conduct" }, true)
	ok("⑧ Lv1 무기에는 레벨업 3택에도 임무 보상에도 개조 후보가 없다(자격 Lv2 · 번개 구체는 보조)",
		new1_mod.is_empty() and new1_offer.is_empty(), "3택 %s · 보상 %s" % [str(new1_mod), str(new1_offer)])
	ok("⑧ 후보를 지나 들어와도 Lv1 무기의 개조는 거부된다(확정 단계 방어)", not forced_new1)
	# 자격이 열리는 지점: 보조는 Lv2에서 1개까지, 주무기는 Lv2에 1개 · Lv4에 2개
	var quota_line := []
	for lv in [1, 2, 3, 4, 5]:
		var wm := { "id": "sword", "level": lv, "mods": [] }
		var ws := { "id": "orb", "level": mini(lv, 3), "mods": [] }
		quota_line.append("Lv%d 주%d/보%d" % [lv, PGrowth.mod_quota_of(g_new1, wm), PGrowth.mod_quota_of(g_new1, ws)])
	ok("⑧ 개조 자격이 주무기 Lv2·Lv4 / 보조 Lv2 그대로다",
		PGrowth.mod_quota_of(g_new1, { "id": "sword", "level": 1, "mods": [] }) == 0
		and PGrowth.mod_quota_of(g_new1, { "id": "sword", "level": 2, "mods": [] }) == 1
		and PGrowth.mod_quota_of(g_new1, { "id": "sword", "level": 4, "mods": [] }) == 2
		and PGrowth.mod_quota_of(g_new1, { "id": "orb", "level": 1, "mods": [] }) == 0
		and PGrowth.mod_quota_of(g_new1, { "id": "orb", "level": 2, "mods": [] }) == 1
		and PGrowth.mod_quota_of(g_new1, { "id": "orb", "level": 3, "mods": [] }) == 1,
		", ".join(quota_line))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
