class_name PGrowth
extends RefCounted
## 성장(HTML growth.js 이식): 경험치·레벨, 무기/공용/패시브/기술 슬롯, 선택지 생성(시드 결정적), 카드 설명. 회차 dict(run)의 run.growth를 다룬다.
## growth dict: { level, xp, pendingLevelUps, choiceSeq, pendingOffer(null|dict), lastKind, weapons[{id,level,mods[]}], commons{}, passives{}, skills{q{id,level,variant},e|null},
##   bossRewards[], steer(null|{kind,cardId,regionId,day,fallbackGold}), picks{}, log[], pendingDeepPick, pendingBossPick, pendingMissionPick, pendingEventPick }

static func G() -> Dictionary: return PCatalog.growth()

static func new_growth(start_weapon: String = "sword") -> Dictionary:
	return {
		"level": 1, "xp": 0.0, "pendingLevelUps": 0, "choiceSeq": 0, "pendingOffer": null, "lastKind": null,
		"structure": STRUCTURE, # 주무기 1 + 공통 보조 2. 이 표시가 없는 저장은 옛 구조("v1")로 본다
		"weapons": [{ "id": start_weapon, "level": 1, "mods": [] }],
		"commons": {}, "passives": {}, "skills": { "q": { "id": "slowfield", "level": 1, "variant": null }, "e": null },
		"bossRewards": [], "steer": null,
		"picks": { "weapon_new": 0, "weapon_level": 0, "weapon_mod": 0, "common": 0, "skill_new": 0, "skill_level": 0, "skill_variant": 0, "passive": 0, "skip": 0 },
		"log": [], "pendingDeepPick": null, "pendingBossPick": null, "pendingMissionPick": null, "pendingEventPick": null,
	}

# ---------- 경험치 ----------
static func xp_need(level: int) -> int:
	var X: Dictionary = G().XP
	var k := level - 1
	return int(round(float(X.base) + float(X.step) * k + float(X.get("quad", 0.0)) * k * k))

## 경험치 추가. 오른 레벨 수를 돌려주고 pendingLevelUps에 누적한다(여러 레벨 한 번에 가능). 소수 누적(0.01 단위)
static func add_xp(g: Dictionary, amount: float) -> int:
	var max_lv: int = int(G().XP.maxLevel)
	if amount <= 0.0 or int(g.level) >= max_lv:
		return 0
	g.xp = round((float(g.xp) + amount) * 100.0) / 100.0
	var gained := 0
	while int(g.level) < max_lv and float(g.xp) >= float(xp_need(int(g.level))):
		g.xp = float(g.xp) - float(xp_need(int(g.level)))
		g.level = int(g.level) + 1
		gained += 1
	g.pendingLevelUps = int(g.pendingLevelUps) + gained
	return gained

## 처치 경험치(HTML 단위 1마리 기준): 기본값 × 지역 배율 × 처치 배율. 밀도 모델의 마리당 값은 CombatState가 예산으로 나눈다
static func xp_value_unit(type: String, summoned: bool, region_id: String, kill_mult: float) -> float:
	var v: Dictionary = G().XP_VALUE
	var mult: float = float(G().REGION_XP_MULT.get(region_id, 1.0)) if region_id != "" else 1.0
	var tp := PCatalog.theme_places()
	if tp.has(region_id):
		mult = float(tp[region_id].get("xp_mult", 1.0))
	var base: float = float(v.summoned) if summoned else float(v.get(type, 5.0))
	return round(base * mult * kill_mult * 100.0) / 100.0

# ---------- 조회 ----------
static func weapon_of(g: Dictionary, id: String) -> Dictionary:
	for w in g.weapons:
		if String(w.id) == id:
			return w
	return {}

static func has_common(g: Dictionary, id: String) -> bool:
	return int(g.commons.get(id, 0)) > 0

static func common_count(g: Dictionary) -> int:
	var n := 0
	for k in g.commons:
		if int(g.commons[k]) > 0:
			n += 1
	return n

static func passive_count(g: Dictionary) -> int:
	var n := 0
	for k in g.passives:
		if int(g.passives[k]) > 0:
			n += 1
	return n

static func has_projectile_weapon(g: Dictionary) -> bool:
	for w in g.weapons:
		var k := String(PCatalog.weapon(String(w.id)).kind)
		if k in ["homing", "bolt", "beam"] or (w.mods as Array).has("crescent") or (w.mods as Array).has("launch"):
			return true
	return false

static func has_fire_source(g: Dictionary) -> bool:
	return has_common(g, "ember") or not weapon_of(g, "ember").is_empty()

## 상태 공급원 판정(공통, F5): 개조 ID가 아니라 카탈로그 태그(weapons.json mods[].tags: "bleed")로 판단한다.
## 출혈 공급원 = tags에 bleed가 있는 개조(쌍검 출혈 칼날, 회전 칼날 톱날). 화상 공급원 = 불붙은 공격·불씨 정령·잔불 걸음. 냉기 = 얼음 파편.
## 그 레벨에서 가질 수 있는 개조 수(시험값): 기본 0, 자격 레벨 2에서 1, 4에서 2.
## 슬롯 상한(SLOTS.weaponMods)을 넘지 않는다. 기존 저장이 이미 더 많이 갖고 있으면 줄이지 않는다
## 옛 성장 구조 재현(전후 비교 전용): PROPHECY_GROWTH_LEGACY=1이면 레벨 배율 1/1.2/1.4/1.6/1.8,
## 개조 자격 없음(Lv1부터 2개), 대장간은 전체 강화. 게임 기본값이 아니다.
static var growth_legacy := OS.get_environment("PROPHECY_GROWTH_LEGACY") != ""
const LEGACY_LEVEL_MULT := [1.0, 1.2, 1.4, 1.6, 1.8]

# ---------- 주무기·보조무기 분리(2026-09-08) ----------
## 새 회차의 구조 표시. 이 값이 growth.structure에 저장되고, 표시가 없는 옛 저장은 "v1"이다.
const STRUCTURE := "v2"

## 이 회차가 어느 구조인지. **옛 회차는 옛 구조 그대로 끝까지 마칠 수 있다**(사용자 지시 6절).
## 새 구조는 새 회차부터 적용된다. 저장을 열 때 무기를 지우거나 하나를 골라 주는 일은 하지 않는다.
static func structure_of(g: Dictionary) -> String:
	return String(g.get("structure", "v1"))

static func is_v2(g: Dictionary) -> bool:
	return structure_of(g) == "v2"

## 자동기술 하나의 레벨 상한. v1은 전부 5, v2는 주무기 5 / 보조 3
static func level_cap(g: Dictionary, weapon_id: String) -> int:
	var S: Dictionary = G().SLOTS
	if not is_v2(g):
		return int(S.weaponMax)
	var R := PCatalog.slot_rules()
	return int(R.get("mainMax", 5)) if PCatalog.is_main_weapon(weapon_id) else int(R.get("supportMax", 3))

## 자동기술 하나의 개조 상한. v1은 전부 2, v2는 주무기 2 / 보조 1
static func mod_cap(g: Dictionary, weapon_id: String) -> int:
	var S: Dictionary = G().SLOTS
	if not is_v2(g):
		return int(S.weaponMods)
	var R := PCatalog.slot_rules()
	return int(R.get("mainMods", 2)) if PCatalog.is_main_weapon(weapon_id) else int(R.get("supportMods", 1))

## 개조 자격 레벨 목록. v1은 growth.json의 MOD_UNLOCK_LEVEL, v2는 주무기 [2,4] / 보조 [2]
static func mod_unlock_levels(g: Dictionary, weapon_id: String) -> Array:
	if not is_v2(g):
		return G().get("MOD_UNLOCK_LEVEL", [])
	var R := PCatalog.slot_rules()
	return R.get("modUnlockMain", [2, 4]) if PCatalog.is_main_weapon(weapon_id) else R.get("modUnlockSupport", [2])

## 지금 그 자동기술이 가질 수 있는 개조 수. 자격이 열려도 자동 지급이 아니라 후보로 나타날 뿐이다
static func mod_quota_of(g: Dictionary, w: Dictionary) -> int:
	var wid := String(w.id)
	var cap := mod_cap(g, wid)
	if growth_legacy:
		return cap
	var ul := mod_unlock_levels(g, wid)
	if ul.is_empty():
		return cap
	var n := 0
	for need in ul:
		if int(w.level) >= int(need):
			n += 1
	return mini(n, cap)

static func main_weapons(g: Dictionary) -> Array:
	return (g.weapons as Array).filter(func(w): return PCatalog.is_main_weapon(String(w.id)))

static func support_weapons(g: Dictionary) -> Array:
	return (g.weapons as Array).filter(func(w): return not PCatalog.is_main_weapon(String(w.id)))

## 새 자동기술을 하나 더 가질 수 있는지. v2에서 주무기는 회차 중에 늘지 않는다(시작에 고른 1개).
## **옛 저장이 주무기 계열을 여러 개 갖고 있어도 지우지 않는다** — 더 늘지 않을 뿐이다.
static func can_take_weapon(g: Dictionary, weapon_id: String) -> bool:
	if not weapon_of(g, weapon_id).is_empty():
		return false
	if not is_v2(g):
		return g.weapons.size() < int(G().SLOTS.weapons)
	var R := PCatalog.slot_rules()
	if PCatalog.is_main_weapon(weapon_id):
		return main_weapons(g).size() < int(R.get("main", 1))
	return support_weapons(g).size() < int(R.get("supports", 2))

static func mod_quota(level: int) -> int:
	var G := G()
	if growth_legacy:
		return int(G.SLOTS.weaponMods)
	var ul: Array = G.get("MOD_UNLOCK_LEVEL", [])
	var cap: int = int(G.SLOTS.weaponMods)
	if ul.is_empty():
		return cap
	var n := 0
	for need in ul:
		if level >= int(need):
			n += 1
	return mini(n, cap)

static func weapon_mod_has_tag(weapon_id: String, mod_id: String, tag: String) -> bool:
	var W := PCatalog.weapons()
	if not W.has(weapon_id):
		return false
	var mods: Dictionary = W[weapon_id].get("mods", {})
	if not mods.has(mod_id):
		return false
	return (mods[mod_id].get("tags", []) as Array).has(tag)

static func has_bleed_source(g: Dictionary) -> bool:
	for w in g.weapons:
		for m in w.mods:
			if weapon_mod_has_tag(String(w.id), String(m), "bleed"):
				return true
	return false

## 보유한 상태 공급원 이름 목록(희귀 보상 설명·장비 호환 안내가 같은 기준을 쓴다)
static func status_sources(g: Dictionary) -> Array:
	var out := []
	if has_common(g, "frost"):
		out.append("냉기")
	if has_common(g, "burn") or has_fire_source(g):
		out.append("화상")
	if has_bleed_source(g):
		out.append("출혈")
	return out

static func has_dot_source(g: Dictionary) -> bool:
	return not status_sources(g).is_empty()

static func boss_reward_applies(g: Dictionary, id: String) -> bool:
	match id:
		"resonance": return g.weapons.size() >= 2
		"seed": return has_dot_source(g)
		"clone": return has_projectile_weapon(g)
		"volley": return g.skills.get("e") != null
	return true

static func _requires_ok(g: Dictionary, d: Dictionary) -> bool:
	if not d.has("requiresAny"):
		return true
	for r in d.requiresAny:
		if String(r) == "common:ember" and has_common(g, "ember"):
			return true
		if String(r) == "weapon:ember" and not weapon_of(g, "ember").is_empty():
			return true
	return false

static func _applies_ok(g: Dictionary, d: Dictionary) -> bool:
	if not d.has("applies"):
		return true
	for w in g.weapons:
		var wd := PCatalog.weapon(String(w.id))
		if String(d.applies) == "width" and bool(wd.width):
			return true
		if String(d.applies) == "reach" and bool(wd.reach):
			return true
	return false

# ---------- 후보 생성 ----------
## ctx: { pool: "level"|"deep"|"boss"|"mission", region_id, kinds[], weapon_only, exclude_mod }
## 해금 순서(사용자 지시 §5): 해금 자격(run.unlocks 스냅샷, PProfile.run_unlock_ok) → 보유·호환·상한·전제 → 유형 가중치(generate_offer) → 유형 안 추첨.
## unlocks 키가 없는 회차(봇·시험실·옛 저장)는 전부 열린 것으로 본다. 보유 기술의 개조는 그 기술 안에서만 추첨한다(미보유 기술의 개조는 후보가 아님)
static func candidates(run: Dictionary, ctx: Dictionary = {}) -> Array:
	var g: Dictionary = run.growth
	var S: Dictionary = G().SLOTS
	var out := []
	var region := String(ctx.get("region_id", ""))
	var tags: Array = PCatalog.region_tags().get(region, [])
	var tp := PCatalog.theme_places()
	if tp.has(region): # 테마 장소: 장소 태그(계획서 §8 약한 성향)
		tags = tp[region].get("tags", [])
	var push := func(c: Dictionary):
		if not c.has("tags"):
			c.tags = []
		var rm := false
		for tg in c.tags:
			if tags.has(tg):
				rm = true
		c.regionMatch = rm
		c.themeMatch = tp.has(region)
		out.append(c)
	var pool := String(ctx.get("pool", "level"))
	if pool == "boss":
		var BR := PCatalog.boss_rewards()
		for id in BR:
			var d: Dictionary = BR[id]
			if not bool(d.impl) or bool(d.get("generic", false)) or (g.bossRewards as Array).has(id):
				continue
			if not boss_reward_applies(g, String(id)):
				continue
			push.call({ "kind": "boss_reward", "id": String(id), "tags": d.get("tags", []) })
		if out.size() < 3:
			for id in BR:
				var d: Dictionary = BR[id]
				if bool(d.get("generic", false)) and bool(d.impl) and not (g.bossRewards as Array).has(id):
					push.call({ "kind": "boss_reward", "id": String(id), "tags": [], "generic": true })
		return out
	var W := PCatalog.weapons()
	# 새 자동기술: v2에서는 **보조만** 늘어난다(주무기는 시작에 고른 1개). v1은 예전대로 3개까지 아무거나
	for id in W:
		var d: Dictionary = W[id]
		if not bool(d.impl) or not can_take_weapon(g, String(id)):
			continue
		if not PProfile.run_unlock_ok(run, "weapons", String(id)):
			continue
		push.call({ "kind": "weapon_new", "id": String(id), "role": PCatalog.weapon_role(String(id)), "tags": d.get("tags", []) })
	for w in g.weapons:
		if not W.has(String(w.id)):
			continue # 옛 저장에만 있는 자동기술: 후보로 올리지 않고 그대로 둔다(지우지 않는다)
		var d: Dictionary = W[String(w.id)]
		var role := PCatalog.weapon_role(String(w.id))
		if int(w.level) < level_cap(g, String(w.id)):
			push.call({ "kind": "weapon_level", "id": String(w.id), "role": role, "tags": d.get("tags", []) })
		# 개조 자격 레벨(2026-09-08 시험값): 주무기는 Lv2·Lv4에서 하나씩, 보조는 그 보조의 Lv2에서 하나.
		# 자동 지급이 아니라 그때부터 후보로 나타난다. 기존 저장의 이미 얻은 개조는 회수하지 않는다.
		if (w.mods as Array).size() < mod_quota_of(g, w):
			for mid in d.mods:
				var md: Dictionary = d.mods[mid]
				if not bool(md.impl) or (w.mods as Array).has(mid):
					continue
				if not PProfile.run_unlock_ok(run, "mods", String(w.id), String(mid)):
					continue
				push.call({ "kind": "weapon_mod", "id": String(w.id), "mod": String(mid), "role": role, "tags": md.get("tags", []) })
	var CM := PCatalog.commons()
	for id in CM:
		var d: Dictionary = CM[id]
		if not bool(d.impl):
			continue
		if not PProfile.run_unlock_ok(run, "commons", String(id)):
			continue
		var lv: int = int(g.commons.get(id, 0))
		if lv >= int(d.max):
			continue
		if lv == 0 and common_count(g) >= int(S.commons):
			continue
		if not _applies_ok(g, d):
			continue
		if not _requires_ok(g, d):
			continue
		push.call({ "kind": "common", "id": String(id), "tags": d.get("tags", []) })
	var SK := PCatalog.skills()
	if g.skills.get("e") == null:
		for id in PCatalog.e_skills():
			if bool(SK[id].impl) and PProfile.run_unlock_ok(run, "e_skills", String(id)):
				push.call({ "kind": "skill_new", "id": String(id), "tags": [] })
	for slot in ["q", "e"]:
		var sk = g.skills.get(slot)
		if sk == null:
			continue
		var d: Dictionary = SK[String(sk.id)]
		if int(sk.level) < int(S.skillMax):
			push.call({ "kind": "skill_level", "id": String(sk.id), "slot": slot, "tags": [] })
		if sk.get("variant") == null:
			for vid in d.get("variants", {}):
				if not bool(d.variants[vid].impl):
					continue
				if slot == "q" and not PProfile.run_unlock_ok(run, "q_variants", String(vid)):
					continue
				if slot == "e" and not PProfile.run_unlock_ok(run, "e_variants", String(sk.id), String(vid)):
					continue
				push.call({ "kind": "skill_variant", "id": String(sk.id), "slot": slot, "variant": String(vid), "tags": [] })
	var PS := PCatalog.passives()
	for id in PS:
		var d: Dictionary = PS[id]
		if not bool(d.impl):
			continue
		var lv: int = int(g.passives.get(id, 0))
		if lv >= int(d.max):
			continue
		if lv == 0 and passive_count(g) >= int(S.passives):
			continue
		push.call({ "kind": "passive", "id": String(id), "tags": [] })
	if pool == "deep":
		return out.filter(func(c): return bool(c.regionMatch))
	if pool == "mission":
		var kinds: Array = ctx.get("kinds", [])
		if kinds.has("service"):
			for id in PCatalog.services():
				push.call({ "kind": "service", "id": String(id), "tags": [] })
			return out.filter(func(c): return String(c.kind) == "service")
		var wo := String(ctx.get("weapon_only", ""))
		var ex := String(ctx.get("exclude_mod", ""))
		return out.filter(func(c): return kinds.has(String(c.kind)) and (wo == "" or String(c.id) == wo) and (ex == "" or String(c.get("mod", "")) != ex))
	return out

static func weight_of(g: Dictionary, c: Dictionary) -> float:
	var Wt: Dictionary = G().WEIGHTS
	var w: float = float(Wt.base.get(c.kind, 1.0))
	if int(g.level) <= int(Wt.early.untilLevel) and Wt.early.has(c.kind):
		w *= float(Wt.early[c.kind])
	if bool(c.get("regionMatch", false)):
		w *= float(Wt.regionTag) if not bool(c.get("themeMatch", false)) else PCatalog.theme_reward_weight() # 테마 장소는 1.15(§8)로 통합, 이중 곱 없음
	if bool(c.get("generic", false)):
		w *= 0.5
	if g.get("lastKind") != null and String(g.lastKind) == String(c.kind) and (String(c.kind) == "weapon_level" or String(c.kind) == "passive"):
		w *= float(Wt.repeatPenalty)
	return w

static func key_of(c: Dictionary) -> String:
	return String(c.kind) + ":" + String(c.id) + ((":" + String(c.mod)) if c.has("mod") else "") + ((":" + String(c.variant)) if c.has("variant") else "")

## 시드 결정적 3택(HTML generateOffer). 같은 seq는 같은 결과. 성장 예약(steer)은 level 풀에만 적용, 후보가 없으면 금화 대체(기록)
static func generate_offer(run: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var g: Dictionary = run.growth
	var pool_name := String(ctx.get("pool", "level"))
	if g.get("pendingOffer") != null and String(g.pendingOffer.pool) == pool_name:
		return g.pendingOffer
	var pool := candidates(run, ctx)
	var steer_kind = null
	if g.get("steer") != null and pool_name == "level":
		var kinds: Array = PCatalog.mission_rules().kindPools.get(String(g.steer.kind), [String(g.steer.kind)])
		var sub := pool.filter(func(c): return kinds.has(String(c.kind)))
		if sub.size() > 0:
			pool = sub
			steer_kind = String(g.steer.kind)
		else:
			var fb: int = int(g.steer.get("fallbackGold", 0))
			run.gold = int(run.get("gold", 0)) + fb
			if run.has("log"):
				PRun.add_log(run, "성장 예약(%s): 유효 후보 없음 → 금화 +%d" % [String(g.steer.kind), fb])
			g.steerFallbacks = int(g.get("steerFallbacks", 0)) + 1
			g.steer = null
	var rng := PRng.new((int(run.seed) * 7919 + int(g.choiceSeq) * 104729 + int(g.level) * 31) & 0xFFFFFFFF)
	var picked := []
	var remaining := pool.duplicate()
	# 유형 가중치와 유형 안 후보 분리(meta.json offer.kind_normalized, 사용자 지시 §5): 후보 가중치 = 유형 가중치 × 후보 보정 ÷ 그 유형의 남은 후보 수.
	# 해금으로 새 기술 후보가 늘어도 '새 기술' 유형의 총 출현 확률은 그대로이고, 보유 기술의 개조 확률도 희석되지 않는다
	var normalize: bool = bool((PCatalog.meta().get("offer", {}) as Dictionary).get("kind_normalized", false))
	while picked.size() < 3 and remaining.size() > 0:
		var sum := 0.0
		var ws := []
		var kind_n := {}
		if normalize:
			for c in remaining:
				kind_n[c.kind] = int(kind_n.get(c.kind, 0)) + 1
		for c in remaining:
			var w := weight_of(g, c)
			if normalize:
				w /= float(kind_n[c.kind])
			ws.append(w)
			sum += w
		var r := rng.next() * sum
		var idx := remaining.size() - 1
		for i in remaining.size():
			r -= ws[i]
			if r <= 0.0:
				idx = i
				break
		var c: Dictionary = remaining[idx]
		remaining.remove_at(idx)
		# 같은 무기의 레벨업·개조가 한 화면에 둘 이상 나오지 않게(임무·교체 3택은 같은 무기의 개조 여러 개 허용 — R-CODEX-03)
		if pool_name != "mission":
			var dup := false
			for pc in picked:
				if String(pc.kind) == String(c.kind) and String(pc.id) == String(c.id):
					dup = true
			if dup:
				continue
		picked.append(c)
	var choices := []
	for c in picked:
		var cc: Dictionary = c.duplicate()
		cc.key = key_of(c)
		choices.append(cc)
	g.pendingOffer = { "seq": int(g.choiceSeq), "pool": pool_name, "regionId": ctx.get("region_id", null), "steer": steer_kind, "choices": choices }
	g.choiceSeq = int(g.choiceSeq) + 1
	return g.pendingOffer

## 선택 적용. dry=true면 미리보기(카운터·pendingOffer를 건드리지 않음). 규칙 위반은 push_error 후 false
static func apply_choice(run: Dictionary, choice: Dictionary, dry: bool = false) -> bool:
	var g: Dictionary = run.growth
	var S: Dictionary = G().SLOTS
	var kind := String(choice.kind)
	match kind:
		"weapon_new":
			if not can_take_weapon(g, String(choice.id)):
				push_error("무기 슬롯"); return false
			g.weapons.append({ "id": String(choice.id), "level": 1, "mods": [] })
		"weapon_level":
			var w := weapon_of(g, String(choice.id))
			if w.is_empty() or int(w.level) >= level_cap(g, String(choice.id)):
				push_error("무기 레벨"); return false
			w.level = int(w.level) + 1
		"weapon_mod":
			var w := weapon_of(g, String(choice.id))
			if w.is_empty() or (w.mods as Array).size() >= mod_quota_of(g, w) or (w.mods as Array).has(String(choice.mod)):
				push_error("전용 증강"); return false
			(w.mods as Array).append(String(choice.mod))
		"common":
			var d: Dictionary = PCatalog.commons()[String(choice.id)]
			var lv: int = int(g.commons.get(choice.id, 0))
			if lv >= int(d.max) or (lv == 0 and common_count(g) >= int(S.commons)):
				push_error("공통 증강"); return false
			if not _requires_ok(g, d):
				push_error("전제 미충족"); return false
			if not _applies_ok(g, d):
				push_error("적용 대상 없음"); return false
			g.commons[String(choice.id)] = lv + 1
		"skill_new":
			if g.skills.get("e") != null:
				push_error("E 슬롯"); return false
			g.skills.e = { "id": String(choice.id), "level": 1, "variant": null }
		"skill_level":
			var sk = g.skills.get(String(choice.slot))
			if sk == null or String(sk.id) != String(choice.id) or int(sk.level) >= int(S.skillMax):
				push_error("기술 레벨"); return false
			sk.level = int(sk.level) + 1
		"skill_variant":
			var sk = g.skills.get(String(choice.slot))
			if sk == null or String(sk.id) != String(choice.id) or sk.get("variant") != null:
				push_error("기술 변형"); return false
			sk.variant = String(choice.variant)
		"passive":
			var d: Dictionary = PCatalog.passives()[String(choice.id)]
			var lv: int = int(g.passives.get(choice.id, 0))
			if lv >= int(d.max) or (lv == 0 and passive_count(g) >= int(S.passives)):
				push_error("패시브"); return false
			g.passives[String(choice.id)] = lv + 1
			if String(choice.id) == "vitality":
				run.hp = float(run.get("hp", 0.0)) + float(G().PASSIVE_VALUES.vitality)
		"boss_reward":
			if (g.bossRewards as Array).has(String(choice.id)):
				push_error("중복"); return false
			(g.bossRewards as Array).append(String(choice.id))
			if String(choice.id) == "vigor":
				run.hp = float(run.get("hp", 0.0)) + 25.0
		"service":
			if not PCatalog.services().has(String(choice.id)):
				push_error("알 수 없는 서비스"); return false
			if not run.has("services"):
				run.services = {}
			run.services[String(choice.id)] = int(run.services.get(choice.id, 0)) + 1
		_:
			push_error("알 수 없는 선택 " + kind); return false
	if dry:
		return true
	g.picks[kind] = int(g.picks.get(kind, 0)) + 1
	g.lastKind = kind
	(g.log as Array).append(key_of(choice))
	if g.get("pendingOffer") != null and String(g.pendingOffer.pool) == "level":
		g.pendingLevelUps = maxi(0, int(g.pendingLevelUps) - 1)
	if g.get("pendingOffer") != null and g.pendingOffer.get("steer") != null:
		g.steer = null
		g.picks.steered = int(g.picks.get("steered", 0)) + 1
	g.pendingOffer = null
	return true

static func skip_choice(run: Dictionary) -> void:
	var g: Dictionary = run.growth
	g.picks.skip = int(g.picks.get("skip", 0)) + 1
	if g.get("pendingOffer") != null and String(g.pendingOffer.pool) == "level":
		g.pendingLevelUps = maxi(0, int(g.pendingLevelUps) - 1)
	if g.get("pendingOffer") != null and g.pendingOffer.get("steer") != null:
		g.steer = null
	g.pendingOffer = null
	run.gold = int(run.get("gold", 0)) + int(PCatalog.config().SKIP_AUGMENT_GOLD)

# ---------- 카드 설명(실제 파생 계산 재사용) ----------
static func _fmt(n: float) -> String:
	return str(snapped(n, 0.1))

## 보조 레벨업이 올리는 항목의 화면 이름(data/supports.json levelScale의 키)
const LEVEL_STAT_NAMES := {
	"radius": "반지름", "hops": "연쇄 횟수", "chill": "냉기 지속", "ttl": "장판 지속", "max": "설치 상한",
	"hold": "표적 유지", "charges": "방울 수", "recharge": "충전 시간", "share": "분신 피해 비율",
	"knock": "밀어내기", "dps": "독 피해", "spreadMax": "전염 대상", "thorn": "반격 피해",
	"reduce": "근접 경감", "hp": "인형 체력", "dur": "지속 시간",
}
static func _level_stat_name(k: String) -> String:
	return String(LEVEL_STAT_NAMES.get(k, k))

static func describe(run: Dictionary, c: Dictionary) -> Dictionary:
	var S: Dictionary = G().SLOTS
	var g: Dictionary = run.growth
	var before := PBuild.derive(run)
	var after := PBuild.preview_with_choice(run, c)
	var W := PCatalog.weapons()
	var wname := func(id: String) -> String: return String(W[id].name)
	var out := { "kind": String(c.kind), "key": key_of(c), "tags": c.get("tags", []), "regionMatch": bool(c.get("regionMatch", false)), "title": "", "type": "", "stage": "", "change": "", "scope": "", "slot": "" }
	var find_w := func(b: Dictionary, id: String) -> Dictionary:
		for s in b.weapons:
			if String(s.id) == id:
				return s
		return {}
	match String(c.kind):
		"weapon_new":
			var d: Dictionary = W[String(c.id)]
			var s: Dictionary = find_w.call(after, String(c.id))
			var nrole := PCatalog.weapon_role(String(c.id))
			var ncap := int(S.weapons)
			var nhave: int = g.weapons.size()
			var nword := "자동기술"
			if is_v2(g):
				var sup := nrole == "support"
				ncap = int(PCatalog.slot_rules().get("supports", 2)) if sup else int(PCatalog.slot_rules().get("main", 1))
				nhave = support_weapons(g).size() if sup else main_weapons(g).size()
				nword = "보조" if sup else "주무기"
			out.title = "새 %s: %s" % [nword, String(d.name)]
			out.type = "%s 획득" % nword
			out.stage = "%s %d/%d → %d/%d" % [nword, nhave, ncap, nhave + 1, ncap]
			out.change = String(d.desc)
			var kt: String = String({ "beam": "관통", "orbit": "공전", "chain": "연쇄" }.get(String(d.kind), "고유 방식"))
			out.scope = "기본 피해 %s · 주기 %s초 · 1레벨부터 %s" % [_fmt(float(s.damage)), _fmt(float(s.interval)), kt]
			out.slot = "%s 슬롯 %d/%d" % [nword, nhave + 1, ncap]
		"weapon_level":
			var w := weapon_of(g, String(c.id))
			var s1: Dictionary = find_w.call(before, String(c.id))
			var s2: Dictionary = find_w.call(after, String(c.id))
			var lrole := PCatalog.weapon_role(String(c.id))
			out.title = "%s %d→%d" % [wname.call(String(c.id)), int(w.level), int(w.level) + 1]
			out.type = ("보조 레벨" if lrole == "support" else "주무기 레벨") if is_v2(g) else "자동기술 레벨"
			out.stage = "%d → %d / %d" % [int(w.level), int(w.level) + 1, level_cap(g, String(c.id))]
			out.change = "기본 피해 %s → %s" % [_fmt(float(s1.damage)), _fmt(float(s2.damage))]
			# 보조 레벨업은 피해만 올리지 않는다(지시 1절). 무엇이 같이 오르는지 카드에 적는다
			var lscale: Dictionary = PCatalog.level_scale().get(String(c.id), {})
			for sk in lscale:
				if String(sk) == "damage" or not s1.has(sk):
					continue
				out.change += " · %s %s → %s" % [_level_stat_name(String(sk)), _fmt(float(s1[sk])), _fmt(float(s2.get(sk, s1[sk])))]
			out.scope = "이 자동기술만"; out.slot = "슬롯 소비 없음"
		"weapon_mod":
			var w := weapon_of(g, String(c.id))
			var md: Dictionary = W[String(c.id)].mods[String(c.mod)]
			out.title = "%s 개조: %s" % [wname.call(String(c.id)), String(md.name)]; out.type = "개조"
			var mcap := mod_cap(g, String(c.id))
			out.stage = "개조 슬롯 %d/%d → %d/%d" % [(w.mods as Array).size(), mcap, (w.mods as Array).size() + 1, mcap]
			out.change = String(md.desc); out.scope = "%s만" % wname.call(String(c.id))
			out.slot = "%s 개조 슬롯 %d/%d" % [wname.call(String(c.id)), (w.mods as Array).size() + 1, mcap]
		"common":
			var d: Dictionary = PCatalog.commons()[String(c.id)]
			var lv: int = int(g.commons.get(c.id, 0))
			out.title = "공용: %s%s" % [String(d.name), (" %d→%d" % [lv, lv + 1]) if int(d.max) > 1 else ""]; out.type = "공용 증강"
			out.stage = ("%d → %d / %d" % [lv, lv + 1, int(d.max)]) if int(d.max) > 1 else ("보유" if lv > 0 else "획득")
			out.change = String(d.desc)
			var targets := []
			for w in g.weapons:
				if not d.has("applies") or _applies_ok({ "weapons": [w] }, d):
					targets.append(wname.call(String(w.id)))
			out.scope = "적용: %s (나중에 얻는 자동기술도 자동)" % (", ".join(targets) if targets.size() > 0 else "없음")
			if String(c.id) == "wide" or String(c.id) == "reach":
				for ex in before.weapons:
					if _applies_ok({ "weapons": [{ "id": ex.id, "mods": [] }] }, d):
						var ex2: Dictionary = find_w.call(after, String(ex.id))
						if String(c.id) == "wide":
							if float(ex.get("arcDeg", 0.0)) > 0.0:
								out.change += " · %s 각도 %d° → %d°" % [wname.call(String(ex.id)), int(round(float(ex.arcDeg))), int(round(float(ex2.arcDeg)))]
							elif float(ex.get("width", 0.0)) > 0.0:
								out.change += " · %s 폭 %d → %d" % [wname.call(String(ex.id)), int(round(float(ex.width))), int(round(float(ex2.width)))]
							elif float(ex.get("radius", 0.0)) > 0.0:
								out.change += " · %s 반지름 %d → %d" % [wname.call(String(ex.id)), int(round(float(ex.radius))), int(round(float(ex2.radius)))]
						else:
							out.change += " · %s 사거리 %d → %d" % [wname.call(String(ex.id)), int(round(float(ex.range))), int(round(float(ex2.range)))]
						break
			out.slot = "슬롯 소비 없음(단계 상승)" if lv > 0 else "공용 슬롯 %d/%d" % [common_count(g) + 1, int(S.commons)]
		"skill_new":
			var d: Dictionary = PCatalog.skills()[String(c.id)]
			out.title = "E 기술 습득: %s" % String(d.name); out.type = "수동 기술"; out.stage = "E 슬롯 비어 있음 → 장착"; out.change = String(d.desc)
			out.scope = "재사용 %s초" % _fmt(float(d.cooldown[0]) * float(before.skill_cd_mult)); out.slot = "E 슬롯"
		"skill_level":
			var sk: Dictionary = g.skills[String(c.slot)]
			var d: Dictionary = PCatalog.skills()[String(c.id)]
			out.title = "%s %d→%d" % [String(d.name), int(sk.level), int(sk.level) + 1]; out.type = "기술 레벨"
			out.stage = "%d → %d / %d" % [int(sk.level), int(sk.level) + 1, int(S.skillMax)]
			var cd1 := float(d.cooldown[int(sk.level) - 1]) * float(before.skill_cd_mult)
			var cd2 := float(d.cooldown[int(sk.level)]) * float(before.skill_cd_mult)
			out.change = "재사용 %s초 → %s초" % [_fmt(cd1), _fmt(cd2)]
			if d.has("damage"):
				out.change += " · 피해 %d → %d" % [int(d.damage[int(sk.level) - 1]), int(d.damage[int(sk.level)])]
			elif d.has("shield"):
				out.change += " · 흡수 %d → %d" % [int(d.shield[int(sk.level) - 1]), int(d.shield[int(sk.level)])]
			out.scope = "%s 기술" % String(d.key); out.slot = "슬롯 소비 없음"
		"skill_variant":
			var d: Dictionary = PCatalog.skills()[String(c.id)]
			var v: Dictionary = d.variants[String(c.variant)]
			out.title = "%s 변형: %s" % [String(d.name), String(v.name)]; out.type = "기술 변형"; out.stage = "변형 없음 → 선택(기술당 1개)"; out.change = String(v.desc); out.scope = "%s 기술" % String(d.key); out.slot = "변형 슬롯 1/1"
		"passive":
			var d: Dictionary = PCatalog.passives()[String(c.id)]
			var lv: int = int(g.passives.get(c.id, 0))
			out.title = "%s %d→%d" % [String(d.name), lv, lv + 1]; out.type = "패시브"; out.stage = "%d → %d / %d" % [lv, lv + 1, int(d.max)]
			var ch := String(d.desc)
			var w0: Dictionary = before.weapons[0]
			var w0b: Dictionary = after.weapons[0]
			match String(c.id):
				"vitality": ch += " · 최대 체력 %d → %d" % [int(before.hp_max), int(after.hp_max)]
				"mastery": ch += " · %s 피해 %s → %s" % [wname.call(String(w0.id)), _fmt(float(w0.damage)), _fmt(float(w0b.damage))]
				"haste": ch += " · %s 주기 %s → %s초" % [wname.call(String(w0.id)), _fmt(float(w0.interval)), _fmt(float(w0b.interval))]
				"focus": ch += " · 감속장 %s → %s초" % [_fmt(float(before.special_cd)), _fmt(float(after.special_cd))]
				"exploit": ch += " · 빈틈 ×%s → ×%s" % [_fmt(float(before.exposed_mult)), _fmt(float(after.exposed_mult))]
			out.change = ch; out.scope = "캐릭터 전체"
			out.slot = "슬롯 소비 없음" if lv > 0 else "패시브 슬롯 %d/%d" % [passive_count(g) + 1, int(S.passives)]
		"service":
			var d: Dictionary = PCatalog.services()[String(c.id)]
			var n: int = int(run.get("services", {}).get(c.id, 0))
			out.title = "거점 서비스: %s" % String(d.name); out.type = "거점 서비스"; out.stage = ("보유 %d → %d회" % [n, n + 1]) if n > 0 else "획득(1회)"; out.change = String(d.desc); out.scope = "이번 회차 거점에서 사용"; out.slot = "슬롯 소비 없음"
		"boss_reward":
			var d: Dictionary = PCatalog.boss_rewards()[String(c.id)]
			out.title = "보스 보상: %s" % String(d.name); out.type = "희귀 보상(범용)" if bool(d.get("generic", false)) else "희귀 보상"; out.stage = "획득(회차 동안 유지)"; out.change = String(d.desc)
			var wn := []
			for w in g.weapons:
				wn.append(wname.call(String(w.id)))
			match String(c.id):
				"resonance": out.scope = "적용: %s%s" % ["·".join(wn), " (자동기술 3종이 되면 발동)" if g.weapons.size() < 3 else ""]
				"seed":
					var srcs := status_sources(g)
					out.scope = "적용: %s" % ("·".join(srcs) if srcs.size() > 0 else "상태 이상 없음")
				"clone": out.scope = "적용: 투사체 자동기술 · 감속장 안을 지나는 투사체가 1회 복제"
				"volley": out.scope = "적용: E %s · E 사용 시 자동기술이 즉시 1회씩 추가 공격" % (String(PCatalog.skills()[String(g.skills.e.id)].name) if g.skills.get("e") != null else "없음")
				"vigor": out.scope = "적용: 캐릭터 전체 · 최대 체력 %d → %d" % [int(before.hp_max), int(before.hp_max) + 25]
				"tempo": out.scope = "적용: 감속장 %s → %s초%s" % [_fmt(float(before.special_cd)), _fmt(float(before.special_cd) * 0.85), ", E 재사용도 15% 감소" if g.skills.get("e") != null else ""]
				_: out.scope = "모든 자동기술·기술"
			out.slot = "별도 보관(슬롯 소비 없음)"
	return out
