extends SceneTree
## 성장 구조 변경 전후 비교(화면 없음):
##   godot --headless --path prophecy_godot -s tools/growth_compare.gd
## 결과: docs/sim/GROWTH_COMPARE.md
##
## 같은 **성장 선택 예산**에서 세 정책을 만든다.
##   A 집중  : 한 자동기술에 몰아 투자
##   B 분산  : 세 자동기술에 균등
##   C 연계  : 두 자동기술 + 공용
## 선택 1개 = 예산 1. 새 무기 획득·레벨·개조·공용·패시브가 모두 같은 예산에서 경쟁한다.
## 개조는 새 구조에서 자동기술 Lv2(첫 개조)·Lv4(둘째 개조)부터 자격이 생긴다 — 예산이 맞아도
## 자격이 없으면 고를 수 없다. 예산에 맞지 않는 완성 빌드는 만들지 않는다.
##
## 옛 구조는 PROPHECY_GROWTH_LEGACY=1로 같은 프로세스 안에서 재현한다(레벨 배율 1/1.2/1.4/1.6/1.8,
## 개조 자격 없음, 대장간 전체 강화).
##
## **여기 나오는 값은 사람이 승인한 균형이 아니다.** 적 체력을 이 비율로 곱하지 않는다.

const STEP := 1.0 / 120.0
const SECONDS := 20.0
const SEED := 11
const BUDGETS := [5, 10, 15, 20]

## 시작 자동기술 조합(사용자 사용 조합 포함)
const STARTS := [
	{ "id": "sword", "set": ["sword", "daggers", "hammer"] },
	{ "id": "spear", "set": ["spear", "bow", "frost"] },
	{ "id": "blades", "set": ["blades", "orb", "mine"] },
	{ "id": "ember", "set": ["ember", "spear", "orb"] },   # 사용자 조합: 불씨·창·번개(구슬)
]

var rows := []

## 예산 안에서 정책대로 성장을 쌓는다. 실제 규칙(PGrowth.apply)을 그대로 쓴다.
## 못 고르는 선택(자격 미달·상한)은 건너뛰고 다음 후보로 간다. 예산은 실제로 성공한 선택만 센다.
func build_growth(policy: String, start: Dictionary, budget: int) -> Dictionary:
	var run := PRun.new_run(SEED, String(start.id))
	var g: Dictionary = run.growth
	var used := 0
	var guard := 0
	while used < budget and guard < 400:
		guard += 1
		var want := _next_choice(policy, g, start)
		if want.is_empty():
			break
		if PGrowth.apply_choice(run, want):
			used += 1
	return { "run": run, "used": used }

## 정책별 다음 선택. 실제 후보 목록에서 고른다(합법 자격만)
func _next_choice(policy: String, g: Dictionary, start: Dictionary) -> Dictionary:
	var ws: Array = g.weapons
	var set_ids: Array = start.set
	match policy:
		"A":   # 집중: 첫 기술 레벨 → 자격이 생기면 개조 → 그 다음 다시 레벨
			var w0: Dictionary = ws[0]
			var m := _mod_choice(g, String(w0.id))
			if not m.is_empty():
				return m
			if int(w0.level) < 5:
				return { "kind": "weapon_level", "id": String(w0.id) }
			return _common_choice(g)
		"B":   # 분산: 세 기술을 갖추고 레벨을 고르게
			if ws.size() < 3:
				for id in set_ids:
					if not _has(ws, String(id)):
						return { "kind": "weapon_new", "id": String(id) }
			var lo: Dictionary = ws[0]
			for w in ws:
				if int(w.level) < int(lo.level):
					lo = w
			var m2 := _mod_choice(g, String(lo.id))
			if not m2.is_empty():
				return m2
			if int(lo.level) < 5:
				return { "kind": "weapon_level", "id": String(lo.id) }
			return _common_choice(g)
		_:     # C 연계: 두 기술 + 공용
			if ws.size() < 2:
				return { "kind": "weapon_new", "id": String(set_ids[1]) }
			var lo2: Dictionary = ws[0]
			for i in mini(2, ws.size()):
				if int(ws[i].level) < int(lo2.level):
					lo2 = ws[i]
			var m3 := _mod_choice(g, String(lo2.id))
			if not m3.is_empty():
				return m3
			if int(lo2.level) < 5:
				return { "kind": "weapon_level", "id": String(lo2.id) }
			return _common_choice(g)

func _has(ws: Array, id: String) -> bool:
	for w in ws:
		if String(w.id) == id:
			return true
	return false

## 지금 자격이 있는 개조 하나. 없으면 {}
func _mod_choice(g: Dictionary, wid: String) -> Dictionary:
	var w := PGrowth.weapon_of(g, wid)
	if w.is_empty() or (w.mods as Array).size() >= PGrowth.mod_quota(int(w.level)):
		return {}
	var d := PCatalog.weapon(wid)
	for mid in (d.get("mods", {}) as Dictionary):
		if not bool(d.mods[mid].get("impl", false)) or (w.mods as Array).has(String(mid)):
			continue
		return { "kind": "weapon_mod", "id": wid, "mod": String(mid) }
	return {}

## 남는 예산을 쓰는 순서: 공용 → 패시브 → Q 레벨 → 새 기술.
## 이렇게 해야 '집중' 정책도 같은 예산을 끝까지 쓴다(예산이 남으면 비교가 어긋난다)
func _common_choice(g: Dictionary) -> Dictionary:
	for id in PCatalog.commons():
		var d: Dictionary = PCatalog.commons()[id]
		if not bool(d.impl):
			continue
		var clv: int = int(g.commons.get(id, 0))
		if clv >= int(d.max):
			continue
		if clv == 0 and (g.commons as Dictionary).size() >= int(PCatalog.growth().SLOTS.commons):
			continue   # 공용 슬롯 상한(3). 새 공용을 더 못 넣는다
		return { "kind": "common", "id": String(id) }
	var S: Dictionary = PCatalog.growth().SLOTS
	for pid in PCatalog.growth().PASSIVE_VALUES:
		var lv: int = int(g.passives.get(pid, 0))
		if lv < int(S.passiveMax) and (lv > 0 or (g.passives as Dictionary).size() < int(S.passives)):
			return { "kind": "passive", "id": String(pid) }
	var q: Dictionary = g.skills.get("q", {})
	if not q.is_empty() and int(q.level) < int(S.skillMax):
		return { "kind": "skill_level", "id": "q" }
	for wid in PCatalog.weapons():
		if (g.weapons as Array).size() < int(S.weapons) and not _has(g.weapons, String(wid)):
			return { "kind": "weapon_new", "id": String(wid) }
	return {}

# ---------- 측정 상황 ----------
## 상황별로 표적을 세우고 그 시간 동안 준 피해를 잰다. 사거리 밖 0 DPS 같은 조건은 쓰지 않는다
func measure(run: Dictionary, scen: String) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": SEED,
		"waves": [[{ "type": "wolf", "n": 1 }]], "objective": "clear", "region_id": "forest",
		"pool": ["wolf"], "run": run })
	st.spawn_hold = true
	for e in st.enemies:
		e.dead = true
	st.pending.clear()
	st.player.hp = 1.0e9
	st.player.hp_max = 1.0e9
	var targets := []
	var px: float = st.player.x
	var py: float = st.player.y
	match scen:
		"정지 단일":
			targets.append(st.spawn_enemy("wolf", px + 90.0, py))
		"이동 표적":
			targets.append(st.spawn_enemy("archer", px + 150.0, py))   # 거리를 유지하며 움직인다
		"혼합 다수":
			for i in 6:
				targets.append(st.spawn_enemy("wolf", px + 80.0 + float(i % 3) * 45.0, py - 40.0 + float(i / 3) * 80.0))
			for i in 2:
				targets.append(st.spawn_enemy("archer", px + 220.0, py - 30.0 + float(i) * 60.0))
		"방패병 정면":
			var sb := st.spawn_enemy("shieldbearer", px + 100.0, py)
			sb.face = PI     # 방패 판정은 e.face를 본다. PI = 플레이어(왼쪽) 쪽
			sb.dir = PI
			sb.aim_angle = PI
			targets.append(sb)
		"방패병 측후방":
			var sb2 := st.spawn_enemy("shieldbearer", px + 100.0, py)
			sb2.face = 0.0   # 등을 보인다
			sb2.dir = 0.0
			sb2.aim_angle = 0.0
			targets.append(sb2)
		"지원 호위":
			targets.append(st.spawn_enemy("shaman", px + 200.0, py))
			targets.append(st.spawn_enemy("archer", px + 210.0, py + 40.0))
			for i in 2:
				targets.append(st.spawn_enemy("wolf", px + 90.0, py - 30.0 + float(i) * 60.0))
		"정예":
			targets.append(st.spawn_enemy("wolf_alpha", px + 110.0, py))
		"보스":
			targets.append(st.spawn_enemy("wolf", px + 110.0, py))   # 보스 상황은 별도 도구에서 잰다(여기서는 대용 표적)
	var frozen := []
	for e in targets:
		e.hp = 1.0e9
		e.hp_max = 1.0e9
		frozen.append([float(e.x), float(e.y)])
	st.metrics = CombatState._new_metrics()
	var n := int(SECONDS / STEP)
	var lock_face: bool = scen.begins_with("방패병")
	var face_v: float = float(targets[0].get("face", 0.0)) if lock_face and not targets.is_empty() else 0.0
	var hold_pos: bool = scen != "이동 표적"
	for i in n:
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }, STEP)
		# 측정 조건 유지(규칙 변경이 아니라 이 도구 안에서만): 표적을 제자리에 두고 방패 방향을 고정한다.
		# 적 이동 속도는 공유 정의(e.def)에 있어 개체별로 끌 수 없기 때문에 위치를 되돌리는 방식을 쓴다
		for j in targets.size():
			var e: Dictionary = targets[j]
			if e.dead:
				continue
			if hold_pos:
				e.x = frozen[j][0]
				e.y = frozen[j][1]
			if lock_face:
				e.face = face_v
	var total := 0.0
	for k in (st.metrics.dmg as Dictionary):
		total += float(st.metrics.dmg[k])
	return { "dps": total / SECONDS, "total": total }

const SCENARIOS := ["정지 단일", "이동 표적", "혼합 다수", "방패병 정면", "방패병 측후방", "지원 호위", "정예"]

func _init() -> void:
	for legacy in [true, false]:
		PGrowth.growth_legacy = legacy
		for start in STARTS:
			for policy in ["A", "B", "C"]:
				for budget in BUDGETS:
					var gb := build_growth(policy, start, budget)
					for scen in SCENARIOS:
						var m := measure(gb.run, scen)
						rows.append({ "legacy": legacy, "start": String(start.id), "policy": policy,
							"budget": budget, "used": int(gb.used), "scen": scen,
							"dps": snapped(float(m.dps), 0.01),
							"levels": _level_str(gb.run), "mods": _mod_count(gb.run) })
					printerr("done ", "old" if legacy else "new", " ", start.id, " ", policy, " ", budget)
	PGrowth.growth_legacy = false
	print("GROWTH_COMPARE_JSON " + JSON.stringify(rows))
	_write_md()
	quit()

func _level_str(run: Dictionary) -> String:
	var out := []
	for w in run.growth.weapons:
		out.append("%s%d" % [String(w.id).substr(0, 2), int(w.level)])
	return "/".join(out)

func _mod_count(run: Dictionary) -> int:
	var n := 0
	for w in run.growth.weapons:
		n += (w.mods as Array).size()
	return n

func _find(legacy: bool, start: String, policy: String, budget: int, scen: String) -> Dictionary:
	for r in rows:
		if bool(r.legacy) == legacy and String(r.start) == start and String(r.policy) == policy and int(r.budget) == budget and String(r.scen) == scen:
			return r
	return {}

static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	var m: int = b.size() / 2
	return float(b[m]) if b.size() % 2 == 1 else (float(b[m - 1]) + float(b[m])) * 0.5

func _write_md() -> void:
	var md := "# 성장 구조 변경 전후 비교 (같은 선택 예산)\n\n"
	md += "생성: `tools/growth_compare.gd` (%s, Godot %s). 표적 고정·%0.0f초·시드 %d·플레이어 이동 없음.\n" % [OS.get_name(), Engine.get_version_info().string, SECONDS, SEED]
	md += "**옛 구조** = 레벨 배율 1/1.2/1.4/1.6/1.8 · 개조 자격 없음 · 대장간 전체 강화(`PROPHECY_GROWTH_LEGACY=1`).\n"
	md += "**새 구조** = 레벨 배율 1/1.35/1.8/2.35/3.0 · 개조 자격 Lv2·Lv4 · 대장간은 고른 자동기술 하나.\n\n"
	md += "> 이 표의 값은 **사람이 승인한 균형이 아니다.** 적 체력을 이 비율로 곱하지 않는다.\n\n"
	md += "## 선택 예산별 빌드 상태\n\n| 시작 | 정책 | 예산 | 구조 | 실제 사용 | 레벨 | 개조 수 |\n|---|---|---:|---|---:|---|---:|\n"
	for start in STARTS:
		for policy in ["A", "B", "C"]:
			for budget in BUDGETS:
				for legacy in [true, false]:
					var r := _find(legacy, String(start.id), policy, budget, "정지 단일")
					if r.is_empty():
						continue
					md += "| %s | %s | %d | %s | %d | %s | %d |\n" % [String(start.id), policy, budget,
						"옛" if legacy else "새", int(r.used), String(r.levels), int(r.mods)]
	md += "\n## 상황별 DPS (옛 → 새, 비 R)\n\n"
	md += "| 시작 | 정책 | 예산 | " + " | ".join(SCENARIOS) + " |\n|---|---|---:|" + "---|".repeat(SCENARIOS.size()) + "\n"
	for start in STARTS:
		for policy in ["A", "B", "C"]:
			for budget in BUDGETS:
				var cells := []
				for scen in SCENARIOS:
					var a := _find(true, String(start.id), policy, budget, scen)
					var bb := _find(false, String(start.id), policy, budget, scen)
					if a.is_empty() or bb.is_empty():
						cells.append("-")
						continue
					var ra: float = float(a.dps)
					var rb: float = float(bb.dps)
					cells.append("%.1f→%.1f (%.2f)" % [ra, rb, (rb / ra) if ra > 0.0 else 0.0])
				md += "| %s | %s | %d | %s |\n" % [String(start.id), policy, budget, " | ".join(cells)]
	md += "\n## 상황별 보정비 R (모든 시작·정책·예산의 중앙값)\n\n"
	md += "R = 새 구조 DPS 중앙값 ÷ 옛 구조 DPS 중앙값. **이 값을 그대로 적 체력에 곱하지 않는다.**\n\n"
	md += "| 상황 | 옛 중앙값 | 새 중앙값 | R | 표본 R 범위 |\n|---|---:|---:|---:|---|\n"
	for scen in SCENARIOS:
		var olds := []
		var news := []
		var ratios := []
		for start in STARTS:
			for policy in ["A", "B", "C"]:
				for budget in BUDGETS:
					var a := _find(true, String(start.id), policy, budget, scen)
					var bb := _find(false, String(start.id), policy, budget, scen)
					if a.is_empty() or bb.is_empty():
						continue
					olds.append(float(a.dps))
					news.append(float(bb.dps))
					if float(a.dps) > 0.0:
						ratios.append(float(bb.dps) / float(a.dps))
		ratios.sort()
		md += "| %s | %.1f | %.1f | **%.2f** | %.2f ~ %.2f |\n" % [scen, _median(olds), _median(news),
			(_median(news) / _median(olds)) if _median(olds) > 0.0 else 0.0,
			(ratios[0] if not ratios.is_empty() else 0.0), (ratios[ratios.size() - 1] if not ratios.is_empty() else 0.0)]
	md += "\n## 읽는 법\n\n"
	md += "- **R < 1이면 새 구조에서 화력이 낮아진 것이다.** 개조 자격이 뒤로 밀리고 대장간이 한 기술에만 붙기 때문이며, 이때 적 체력을 내리지 말고 먼저 압박이 어떻게 달라졌는지 본다.\n"
	md += "- 무리·주력·지원·중장갑·정예를 **한 계수로 묶지 않는다.** 상황별 R이 다르면 다른 이유가 있다.\n"
	md += "- 집중 정책(A)이 분산(B)보다 빨리 죽이는 이점은 그대로 둔다. 최강 빌드에 모든 적을 맞추지 않는다.\n"
	md += "- 보스는 이 표에 없다. 보스는 패턴 도달·정지 전략·회피 빌드로 따로 잰다.\n"
	var f := FileAccess.open("res://docs/sim/GROWTH_COMPARE.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
