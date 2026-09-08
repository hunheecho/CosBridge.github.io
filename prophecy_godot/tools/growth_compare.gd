extends SceneTree
## 성장 구조 변경 전후 비교(화면 없음):
##   godot --headless --path prophecy_godot -s tools/growth_compare.gd
## 결과: docs/sim/GROWTH_COMPARE.md
##
## 같은 **성장 선택 예산**에서 네 정책을 만든다.
##   A 단일기술 고수 : 첫 기술만 끝까지. 다 올린 뒤에는 공용·패시브·Q를 데이터 순서로 소진
##   B 분산          : 세 자동기술에 균등
##   C 연계          : 두 자동기술 + 공용
##   D 집중우선      : 첫 기술을 먼저 완성하되, 그 뒤에는 **생존·다수 처리에 도움이 되는 보조**를
##                     골라 쓰고 마지막에 둘째 기술을 얻는다(2026-09-08 검토 §1 반영)
##
## 경제 조건도 둘로 나눈다(검토 §2 반영):
##   무강화        : 대장간 강화를 사지 않는다
##   동일 금화 강화: 모든 정책에 **같은 금화**를 주고 합법 조건(보스 처치 개방·비용 단계)으로 산다.
##                   대장간이 "고른 자동기술 하나"에만 붙는 변경의 영향이 여기서 드러난다.
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
## 예산 단계별로 주는 금화와 그 시점까지 넘은 관문 수(대장간 개방 조건).
## 모든 정책에 **같은 값**을 준다 — 차이는 "어느 기술에 붙이느냐"뿐이다.
const ECONOMY := { 5: [90, 0], 10: [250, 1], 15: [490, 2], 20: [490, 3] }

## 정책대로 대장간 강화를 산다. 합법 조건(개방·비용·잔액)을 그대로 따르고, 못 사면 멈춘다
func buy_forge(run: Dictionary, policy: String, budget: int) -> Array:
	var eco: Array = ECONOMY.get(budget, [0, 0])
	run.gold = int(eco[0])
	var done := []
	for i in int(eco[1]):
		done.append("boss%d" % i)
	run.bossesDone = done
	var bought := []
	var guard := 0
	while guard < 12:
		guard += 1
		var ws: Array = run.growth.weapons
		if ws.is_empty():
			break
		var wid := String(ws[0].id)
		match policy:
			"B":   # 분산: 강화 단계가 가장 낮은 기술에
				var lo: Dictionary = ws[0]
				for w in ws:
					if PRun.forge_level_of(run, String(w.id)) < PRun.forge_level_of(run, String(lo.id)):
						lo = w
				wid = String(lo.id)
			"C":   # 연계: 앞의 두 기술에 번갈아
				var lo2: Dictionary = ws[0]
				for i in mini(2, ws.size()):
					if PRun.forge_level_of(run, String(ws[i].id)) < PRun.forge_level_of(run, String(lo2.id)):
						lo2 = ws[i]
				wid = String(lo2.id)
			_:     # A·D 집중: 첫 기술에 전부
				wid = String(ws[0].id)
		var F := PRun.forge_next(run, wid)
		if F.is_empty() or not bool(F.open) or not bool(F.affordable):
			break
		if not PRun.forge_upgrade(run, wid):
			break
		bought.append(wid)
	return bought

func build_growth(policy: String, start: Dictionary, budget: int) -> Dictionary:
	var run := PRun.new_run(SEED, String(start.id))
	var g: Dictionary = run.growth
	var used := 0
	var guard := 0
	var blocked := {}          # 규칙이 거부한 선택은 다시 내지 않는다(무한 반복 방지)
	while used < budget and guard < 400:
		guard += 1
		var want := _next_choice(policy, g, start, blocked)
		if want.is_empty():
			break
		if PGrowth.apply_choice(run, want):
			used += 1
		else:
			blocked[JSON.stringify(want)] = true
	return { "run": run, "used": used }

## 같은 성장에 경제 조건만 얹는다(무강화 / 동일 금화 강화)
func with_economy(policy: String, start: Dictionary, budget: int, forge: bool) -> Dictionary:
	var gb := build_growth(policy, start, budget)
	var bought := []
	if forge:
		bought = buy_forge(gb.run, policy, budget)
	return { "run": gb.run, "used": int(gb.used), "forge_bought": bought }

## 정책별 다음 선택. 실제 후보 목록에서 고른다(합법 자격만)
func _next_choice(policy: String, g: Dictionary, start: Dictionary, blocked: Dictionary = {}) -> Dictionary:
	var c := _next_choice_raw(policy, g, start)
	if not c.is_empty() and blocked.has(JSON.stringify(c)):
		return {}          # 이 정책으로는 더 쓸 수 있는 선택이 없다
	return c

func _next_choice_raw(policy: String, g: Dictionary, start: Dictionary) -> Dictionary:
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
		"D":   # 집중우선: 첫 기술 완성 → 생존·다수 처리 보조 → 마지막에 둘째 기술
			var w1: Dictionary = ws[0]
			var md1 := _mod_choice(g, String(w1.id))
			if not md1.is_empty():
				return md1
			if int(w1.level) < 5:
				return { "kind": "weapon_level", "id": String(w1.id) }
			var sup := _support_choice(g)
			if not sup.is_empty():
				return sup
			if ws.size() < 2:
				return { "kind": "weapon_new", "id": String(set_ids[1]) }
			var w2: Dictionary = ws[1]
			var md2 := _mod_choice(g, String(w2.id))
			if not md2.is_empty():
				return md2
			if int(w2.level) < 5:
				return { "kind": "weapon_level", "id": String(w2.id) }
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

## 집중우선 정책이 쓰는 보조 선택. 데이터 순서가 아니라 **생존·다수 처리에 도움이 되는 것**을 먼저 고른다.
## (검토 지적: 기존 A는 공용·패시브를 데이터 순서로 소진해 방어·제어·범위 투자의 가치가 드러나지 않았다)
const SUPPORT_ORDER := [
	["passive", "vitality"],    # 생존
	["passive", "toughness"],   # 생존
	["common", "wide"],         # 다수 처리
	["common", "reach"],        # 다수 처리·안전 거리
	["passive", "mobility"],    # 회피·위치
	["skill_level", "q"],       # 제어(감속장)
	["passive", "haste"],
	["passive", "mastery"],
]

func _support_choice(g: Dictionary) -> Dictionary:
	var S: Dictionary = PCatalog.growth().SLOTS
	for pair in SUPPORT_ORDER:
		var kind := String(pair[0])
		var id := String(pair[1])
		match kind:
			"passive":
				var pl: int = int(g.passives.get(id, 0))
				if pl < int(S.passiveMax) and (pl > 0 or (g.passives as Dictionary).size() < int(S.passives)):
					return { "kind": "passive", "id": id }
			"common":
				var cd: Dictionary = PCatalog.commons().get(id, {})
				if cd.is_empty() or not bool(cd.get("impl", false)):
					continue
				var cl: int = int(g.commons.get(id, 0))
				if cl < int(cd.max) and (cl > 0 or (g.commons as Dictionary).size() < int(S.commons)):
					return { "kind": "common", "id": id }
			"skill_level":
				var q = g.skills.get("q")
				if q != null and int(q.level) < int(S.skillMax):
					return { "kind": "skill_level", "slot": "q", "id": String(q.id) }
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
	var q = g.skills.get("q")
	if q != null and int(q.level) < int(S.skillMax):
		return { "kind": "skill_level", "slot": "q", "id": String(q.id) }
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
## DPS로 잴 수 없는 것(검토 §1 반영): 생존·다수 처리·제어. 별도 함수로 잰다
const EXTRA := ["생존(받은 피해)", "다수 처리(초)", "제어 포함 DPS"]

## 실제 적 체력으로 무리를 상대한다. 봇이 조작하고, 몇 초 만에 정리하는지 잰다.
## 다 못 잡으면 남은 수를 함께 적는다(무한대로 늘어난 값을 평균에 넣지 않는다)
func measure_clear(run: Dictionary, seconds: float) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": SEED,
		"waves": [[{ "type": "wolf", "n": 1 }]], "objective": "clear", "region_id": "forest",
		"pool": ["wolf"], "run": run })
	st.spawn_hold = true
	for e in st.enemies:
		e.dead = true
	st.pending.clear()
	var px: float = st.player.x
	var py: float = st.player.y
	for i in 8:   # 실제 체력 그대로(일반 등급)
		st.spawn_enemy("wolf", px + 120.0 + float(i % 4) * 45.0, py - 60.0 + float(i / 4) * 120.0)
	st.player.hp = 1.0e9      # 생존이 아니라 '정리 시간'만 본다
	st.player.hp_max = 1.0e9
	var bot := PSkillBot.new("skilled", SEED)
	var n := int(seconds / STEP)
	var killed := 0
	for i in n:
		st.step(bot.step_input(st), STEP)
		killed = int(st.stats.kills)
		if killed >= 8:
			break
	return { "sec": snapped(st.t, 0.01), "killed": killed, "left": 8 - killed }

## 실제 위협 앞에서 얼마나 버티는가. 봇이 조작하고 받은 피해를 잰다(체력은 정상)
func measure_survive(run: Dictionary, seconds: float) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": SEED,
		"waves": [[{ "type": "wolf", "n": 1 }]], "objective": "clear", "region_id": "forest",
		"pool": ["wolf"], "run": run })
	st.spawn_hold = true
	for e in st.enemies:
		e.dead = true
	st.pending.clear()
	var px: float = st.player.x
	var py: float = st.player.y
	for i in 4:
		st.spawn_enemy("wolf", px + 200.0, py - 60.0 + float(i) * 40.0)
	for i in 2:
		st.spawn_enemy("archer", px + 320.0, py - 40.0 + float(i) * 80.0)
	# 적이 죽으면 압박이 사라져 '받은 피해 0'만 나온다. 여기서는 **버티는 능력**만 보려고
	# 표적을 죽지 않게 두고 20초 동안 받은 피해를 잰다(플레이어 체력은 실제 값 그대로).
	for e in st.enemies:
		if not e.dead:
			e.hp = 1.0e9
			e.hp_max = 1.0e9
	# 회피를 잘하는 봇으로 재면 무엇에 투자했든 받은 피해가 0에 붙어 차이가 안 난다.
	# 여기서 보려는 것은 **방어 투자의 가치**이므로 회피하지 않는 정책으로 재고,
	# 받은 피해를 최대 체력 대비 비율로 돌려준다(체력·강인함에 투자한 빌드가 낮게 나와야 정상).
	var bot := PBot.new("stand")
	var n := int(seconds / STEP)
	for i in n:
		if st.status != "running":
			break
		st.step(bot.step_input(st), STEP)
	var hpm: float = maxf(1.0, float(st.player.hp_max))
	return { "taken": snapped(float(st.stats.damage_taken), 0.1),
		"taken_frac": snapped(float(st.stats.damage_taken) / hpm * 100.0, 0.1),
		"hp_left": snapped(maxf(0.0, float(st.player.hp)), 0.1),
		"dead": st.status == "lost", "sec": snapped(st.t, 0.01) }

func _init() -> void:
	for legacy in [true, false]:
		PGrowth.growth_legacy = legacy
		for start in STARTS:
			for policy in ["A", "B", "C", "D"]:
				for budget in BUDGETS:
					for forge in [false, true]:
						var gb := with_economy(policy, start, budget, forge)
						for scen in SCENARIOS:
							var m := measure(gb.run, scen)
							rows.append({ "legacy": legacy, "start": String(start.id), "policy": policy,
								"budget": budget, "used": int(gb.used), "scen": scen, "forge": forge,
								"dps": snapped(float(m.dps), 0.01), "forge_bought": (gb.forge_bought as Array).size(),
								"levels": _level_str(gb.run), "mods": _mod_count(gb.run) })
						var cl := measure_clear(gb.run, 40.0)
						var sv := measure_survive(gb.run, 20.0)
						rows.append({ "legacy": legacy, "start": String(start.id), "policy": policy,
							"budget": budget, "used": int(gb.used), "scen": "다수 처리(초)", "forge": forge,
							"dps": float(cl.sec), "killed": int(cl.killed), "left": int(cl.left),
							"forge_bought": (gb.forge_bought as Array).size(),
							"levels": _level_str(gb.run), "mods": _mod_count(gb.run) })
						rows.append({ "legacy": legacy, "start": String(start.id), "policy": policy,
							"budget": budget, "used": int(gb.used), "scen": "생존(받은 피해)", "forge": forge,
							"dps": float(sv.taken_frac), "taken": float(sv.taken), "dead": bool(sv.dead),
							"forge_bought": (gb.forge_bought as Array).size(),
							"levels": _level_str(gb.run), "mods": _mod_count(gb.run) })
						printerr("done ", "old" if legacy else "new", " ", start.id, " ", policy, " ", budget, " forge=", forge)
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

func _find(legacy: bool, start: String, policy: String, budget: int, scen: String, forge: bool = false) -> Dictionary:
	for r in rows:
		if bool(r.legacy) == legacy and String(r.start) == start and String(r.policy) == policy \
				and int(r.budget) == budget and String(r.scen) == scen and bool(r.get("forge", false)) == forge:
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
	var md := "# 성장 구조 변경 전후 비교 (같은 선택 예산 · 같은 금화)\n\n"
	md += "생성: `tools/growth_compare.gd` (%s, Godot %s). 표적 고정·%0.0f초·시드 %d·플레이어 이동 없음(DPS 상황).\n" % [OS.get_name(), Engine.get_version_info().string, SECONDS, SEED]
	md += "**옛 구조** = 레벨 배율 1/1.2/1.4/1.6/1.8 · 개조 자격 없음 · 대장간 전체 강화(`PROPHECY_GROWTH_LEGACY=1`).\n"
	md += "**새 구조** = 레벨 배율 1/1.35/1.8/2.35/3.0 · 개조 자격 Lv2·Lv4 · 대장간은 고른 자동기술 하나.\n\n"
	md += "> 이 표의 값은 **사람이 승인한 균형이 아니다.** 적 체력을 이 비율로 곱하지 않는다.\n\n"
	md += "## 정책 네 가지\n\n"
	md += "| 정책 | 내용 |\n|---|---|\n"
	md += "| A 단일기술 고수 | 첫 기술만 끝까지. 다 올린 뒤에는 공용·패시브·Q를 데이터 순서로 소진 |\n"
	md += "| B 분산 | 세 자동기술에 균등 |\n"
	md += "| C 연계 | 두 자동기술 + 공용 |\n"
	md += "| D 집중우선 | 첫 기술을 먼저 완성하고, 그 뒤 생존·다수 처리 보조를 골라 쓴 다음 둘째 기술 |\n\n"
	md += "A와 D를 나눈 이유: A는 보조를 **데이터 순서로** 고르기 때문에 방어·제어·범위 투자의 가치가 드러나지 않는다(2026-09-08 검토 §1).\n\n"
	md += "## 경제 조건\n\n"
	md += "모든 정책에 **같은 금화**를 준다. 예산 5 → 90금 · 관문 0, 10 → 250금 · 관문 1, 15 → 490금 · 관문 2, 20 → 490금 · 관문 3.\n"
	md += "대장간 개방 조건과 비용 단계는 실제 규칙 그대로다. 차이는 **어느 자동기술에 붙이느냐**뿐이다.\n\n"
	md += "## 상황별 DPS: 무강화 → 동일 금화 강화 (새 구조)\n\n"
	md += "| 시작 | 정책 | 예산 | 산 강화 | 정지 단일 | 혼합 다수 | 정예 |\n|---|---|---:|---:|---|---|---|\n"
	for start in STARTS:
		for policy in ["A", "B", "C", "D"]:
			for budget in BUDGETS:
				var n0 := _find(false, String(start.id), policy, budget, "정지 단일", false)
				var n1 := _find(false, String(start.id), policy, budget, "정지 단일", true)
				var m0 := _find(false, String(start.id), policy, budget, "혼합 다수", false)
				var m1 := _find(false, String(start.id), policy, budget, "혼합 다수", true)
				var e0 := _find(false, String(start.id), policy, budget, "정예", false)
				var e1 := _find(false, String(start.id), policy, budget, "정예", true)
				if n0.is_empty() or n1.is_empty():
					continue
				md += "| %s | %s | %d | %d | %.1f → %.1f | %.1f → %.1f | %.1f → %.1f |\n" % [String(start.id), policy, budget,
					int(n1.get("forge_bought", 0)), float(n0.dps), float(n1.dps), float(m0.dps), float(m1.dps), float(e0.dps), float(e1.dps)]
	md += "\n## 정책 비교: 무엇을 잘하고 무엇이 남는가 (새 구조 · 동일 금화 강화)\n\n"
	md += "| 예산 | 정책 | 정지 단일 DPS | 다수 처리(초) | 방어 가치: 회피 없이 20초 받은 피해(최대 체력 %) |\n|---:|---|---:|---|---:|\n"
	for budget in BUDGETS:
		for policy in ["A", "B", "C", "D"]:
			var d1 := []
			var c1 := []
			var s1 := []
			for start in STARTS:
				var a := _find(false, String(start.id), policy, budget, "정지 단일", true)
				var b := _find(false, String(start.id), policy, budget, "다수 처리(초)", true)
				var c := _find(false, String(start.id), policy, budget, "생존(받은 피해)", true)
				if not a.is_empty():
					d1.append(float(a.dps))
				if not b.is_empty():
					c1.append(float(b.dps))
				if not c.is_empty():
					s1.append(float(c.dps))
			var left_txt := ""
			for start in STARTS:
				var b2 := _find(false, String(start.id), policy, budget, "다수 처리(초)", true)
				if not b2.is_empty() and int(b2.get("left", 0)) > 0:
					left_txt = " (미처치 있음)"
					break
			md += "| %d | %s | %.1f | %.1f%s | %.0f |\n" % [budget, policy, _median(d1), _median(c1), left_txt, _median(s1)]
	md += "\n다수 처리는 실제 체력의 늑대 8마리를 정리한 시간이다(40초 안에 못 잡으면 '미처치 있음').\n"
	md += "방어 가치는 늑대 4 + 궁수 2(죽지 않는 표적) 앞에서 **회피하지 않고** 20초 버틴 뒤 받은 피해를 최대 체력 대비 비율로 적은 것이다.\n"
	md += "\n> **이 열은 지금 쓸모가 없다.** 죽지 않는 적 6마리 앞에서 회피 없이 20초를 버티면 어떤 빌드든 최대 체력을 다 잃어 값이 100%에 붙는다(포화).\n"
	md += "> 앞서 회피 잘하는 봇으로 쟀을 때는 반대로 거의 다 0에 붙었다. **두 극단 사이의 조건을 아직 찾지 못했다** — 방어 투자의 가치는 이 표로 판단하지 않는다.\n"
	md += "> 다음에 시도할 것: 적 수를 줄이고(2~3마리) 시간을 늘리거나, 회피를 일부만 하는 정책으로 재거나, 실제 출격 편성에서 연속 출격 잔여 체력으로 대신 본다(`docs/sim/HP_EFFECT.md` §3이 그 방식이다).\n"
	md += "\n## 상황별 보정비 R (모든 시작·정책·예산의 중앙값, 동일 금화 강화 조건)\n\n"
	md += "R = 새 구조 DPS 중앙값 ÷ 옛 구조 DPS 중앙값. **이 값을 그대로 적 체력에 곱하지 않는다.**\n\n"
	md += "| 상황 | 옛 중앙값 | 새 중앙값 | R | 표본 R 범위 |\n|---|---:|---:|---:|---|\n"
	for scen in SCENARIOS:
		var olds := []
		var news := []
		var ratios := []
		for start in STARTS:
			for policy in ["A", "B", "C", "D"]:
				for budget in BUDGETS:
					var a := _find(true, String(start.id), policy, budget, scen, true)
					var bb := _find(false, String(start.id), policy, budget, scen, true)
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
	md += "\n## 예산 단계별 R (동일 금화 강화 조건)\n\n"
	md += "| 예산 | R 중앙값 | 범위 |\n|---:|---:|---|\n"
	for budget in BUDGETS:
		var rs := []
		for start in STARTS:
			for policy in ["A", "B", "C", "D"]:
				for scen in SCENARIOS:
					var a2 := _find(true, String(start.id), policy, budget, scen, true)
					var b2 := _find(false, String(start.id), policy, budget, scen, true)
					if a2.is_empty() or b2.is_empty() or float(a2.dps) <= 0.0:
						continue
					rs.append(float(b2.dps) / float(a2.dps))
		rs.sort()
		md += "| %d | %.2f | %.2f ~ %.2f |\n" % [budget, _median(rs),
			(rs[0] if not rs.is_empty() else 0.0), (rs[rs.size() - 1] if not rs.is_empty() else 0.0)]
	md += "\n## 읽는 법\n\n"
	md += "- **R < 1이면 새 구조에서 화력이 낮아진 것이다.** 개조 자격이 뒤로 밀리고 대장간이 한 기술에만 붙기 때문이며, 이때 적 체력을 내리지 말고 먼저 압박이 어떻게 달라졌는지 본다.\n"
	md += "- 무리·주력·지원·중장갑·정예를 **한 계수로 묶지 않는다.** 상황별 R이 다르면 다른 이유가 있다.\n"
	md += "- DPS만으로 정책 우열을 말하지 않는다. 다수 처리·생존을 함께 본다.\n"
	md += "- 보스는 이 표에 없다. 보스는 패턴 도달·정지 전략·회피 빌드로 따로 잰다.\n"
	var f := FileAccess.open("res://docs/sim/GROWTH_COMPARE.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
