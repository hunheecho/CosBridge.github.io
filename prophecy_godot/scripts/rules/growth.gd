class_name PGrowth
extends RefCounted
## 성장(HTML growth.js 이식): 경험치·레벨, 무기/공용/패시브/기술 슬롯, 선택지 생성(시드 결정적), 카드 설명. 회차 dict(run)의 run.growth를 다룬다.
## growth dict: { level, xp, pendingLevelUps, choiceSeq, pendingOffer(null|dict), lastKind, weapons[{id,level,mods[]}], commons{}, passives{}, skills{q{id,level,variant},e|null},
##   bossRewards[], steer(null|{kind,cardId,regionId,day,fallbackGold}), picks{}, log[], pendingDeepPick, pendingBossPick, pendingMissionPick, pendingEventPick }

static func G() -> Dictionary: return PCatalog.growth()

## 시작 성장. start_skill = **Q에 장착할 수동 기술 1개**(시작 화면에서 고른다, §7).
## 기본값을 "slowfield"로 둔 이유: 도구·봇·시험·첫 전투가 값을 주지 않을 때 예전과 같은 빌드를 만들기 위해서다.
## 사람이 실제로 시작하는 경로(PMain.start_run)는 **언제나 고른 기술을 넘긴다** — 감속장을 강제로 지급하지 않는다.
static func new_growth(start_weapon: String = "sword", start_skill: String = "slowfield") -> Dictionary:
	return {
		"level": 1, "xp": 0.0, "pendingLevelUps": 0, "choiceSeq": 0, "pendingOffer": null, "lastKind": null,
		"structure": STRUCTURE, # 주무기 1 + 공통 보조 2. 이 표시가 없는 저장은 옛 구조("v1")로 본다
		"weapons": [{ "id": start_weapon, "level": 1, "mods": [] }],
		"commons": {}, "passives": {}, "skills": { "q": { "id": (start_skill if PCatalog.skills().has(start_skill) else "slowfield"), "level": 1, "variant": null }, "e": null },
		"bank": [], # 스킬 창고(§6): Q/E에서 뺀 **일반** 수동 기술을 레벨·변형째 보관한다. 새 회차는 비어 있다
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
	# 신규 종류는 data/pacing.json의 xp_value_extra에서 읽는다(생성 파일 growth.json을 고치지 않는다).
	# 이 겹쳐쓰기가 없으면 새 적이 전부 기본 5로 떨어져 편성의 경험치 예산이 조용히 어긋난다
	var extra: Dictionary = PCatalog.pacing().get("xp_value_extra", {})
	var base: float = float(v.summoned) if summoned else float(extra.get(type, v.get(type, 5.0)))
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

## 투사체를 쏘는 자동기술이 하나라도 있는가('시간의 복제'가 복제할 것이 있는지).
## 무기 종류(kind)를 손으로 나열하지 않고 카탈로그의 분류(category)를 본다 —
## 새 보조가 늘 때마다 여기 목록을 고쳐야 하는 상태였고, 실제로 추격 까마귀·역병 나비가 빠져 있었다.
static func has_projectile_weapon(g: Dictionary) -> bool:
	for w in g.weapons:
		var d := PCatalog.weapon(String(w.id))
		if String(d.get("category", "")) == "projectile":
			return true
		if String(d.kind) in ["homing", "bolt", "beam"]:
			return true
		if (w.mods as Array).has("crescent") or (w.mods as Array).has("launch"):
			return true
		if String(w.id) == "bell" and (w.mods as Array).has("reflect"):
			return true # 되돌림 반격탄도 투사체다
	return false

## 직접 피해를 내는 자동기술의 수. 방어·소환 전용 보조(수호 방울·가시 갑각·도깨비 인형)는 세지 않는다.
## '무기 공명'처럼 **서로 다른 공격 출처**를 요구하는 보상의 자격 판정에 쓴다.
static func attack_source_count(g: Dictionary) -> int:
	var n := 0
	for w in g.weapons:
		var cat := String(PCatalog.weapon(String(w.id)).get("category", "direct"))
		if cat != "guard" and cat != "summon":
			n += 1
	return n

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

## 이 성장의 **주무기 기본 회피 재사용 시간**(초). 표는 data/config.json PLAYER.dodge.byWeapon 하나뿐이고
## 여기서는 읽기만 한다(전투도 CombatState.resolve_dodge에서 같은 표를 읽는다 — 값이 두 곳에 적히지 않게).
## 주무기가 없으면 공통 기본값. 카드 미리보기가 회피 재사용을 적을 때 쓴다
static func dodge_cd_base(g: Dictionary) -> float:
	var D: Dictionary = PCatalog.config().PLAYER.dodge
	var by: Dictionary = D.get("byWeapon", {})
	for w in main_weapons(g):
		var row: Dictionary = by.get(String((w as Dictionary).id), {})
		if not row.is_empty():
			return float(row.get("cooldown", D.cooldown))
	return float(D.cooldown)

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

# ---------- 수동 기술 Q/E 공용 도우미(2026-09-10 §7) ----------
## 두 칸 이름. 화면·규칙·통계가 같은 순서를 쓴다
const SKILL_SLOTS := ["q", "e"]

## 고를 수 있는 수동 기술 6종. data/growth.json e_skills가 정본이며 감속장도 여기 들어 있다
static func manual_skill_ids() -> Array:
	var out: Array = (PCatalog.e_skills() as Array).duplicate()
	if not out.has("slowfield"):
		out.append("slowfield") # 자료가 옛 형태(5종)라도 감속장은 언제나 고를 수 있어야 한다
	return out

## 그 기술이 든 칸("q"|"e"). 없으면 ""
static func skill_slot_of(g: Dictionary, id: String) -> String:
	for s in SKILL_SLOTS:
		var sk = g.get("skills", {}).get(s, null)
		if sk != null and String(sk.id) == id:
			return String(s)
	return ""

## Q나 E에 그 기술이 있는가(= "감속장 사용 시" 같은 **기술 조건**의 판정)
static func has_skill(g: Dictionary, id: String) -> bool:
	return skill_slot_of(g, id) != ""

## 그 칸의 기술 id("" = 비어 있음)
static func skill_id_in(g: Dictionary, slot: String) -> String:
	var sk = g.get("skills", {}).get(slot, null)
	return String(sk.id) if sk != null else ""

# ================= 스킬 창고와 장비 기술(§5·§6·§7, 2026-09-10) =================
## 네 상태를 코드에서 이렇게 가른다. **서로 다른 곳을 읽는다 — 하나를 다른 하나로 대신하지 않는다.**
##   보유(일반 수동 기술) : Q·E 칸에 있거나 창고(growth.bank)에 있다  → owns_manual_skill
##   창고 보관            : growth.bank 배열 안에만 있다               → in_bank / bank
##   Q·E 배치             : growth.skills.q / .e 에 들어 있다           → skill_id_in / has_skill
##   장비 착용            : run.equipment 의 어느 칸이 그 장비 개체다   → granted_skill_ids
##
## 그래서 "창고에 있는 감속장"은 has_skill이 절대 true가 되지 않고(창고는 skills를 건드리지 않는다),
## "장비 기술이 배치돼 있지만 장비를 벗은 상태"는 배치는 남고 usable_skill만 null이 된다.
const EQUIP_SKILL_PREFIX := "eq_"

## 이 기술 id가 **장비 기술**인가(규약: eq_ 로 시작한다 — 다른 담당과 합의한 유일한 판정 기준).
## 장비 기술 = 레벨 없음 · 개조 없음 · 보상 후보 아님 · 창고에 보관하지 않음 · 착용 중에만 사용 가능.
static func is_equip_skill(id: String) -> bool:
	return id.begins_with(EQUIP_SKILL_PREFIX)

## 창고 배열(없으면 **만들어서** 돌려준다 — 넣고 빼는 쪽에서만 쓴다). 항목은 **일반 수동 기술만** [{ id, level, variant }]
static func bank(g: Dictionary) -> Array:
	if typeof(g.get("bank", null)) != TYPE_ARRAY:
		g.bank = []
	return g.bank

## 읽기 전용 조회. 옛 저장(bank 키가 없는 회차)을 **조회만으로 바꾸지 않는다** — 빈 배열로 본다
static func bank_ro(g: Dictionary) -> Array:
	var v = g.get("bank", null)
	return v if typeof(v) == TYPE_ARRAY else []

static func bank_ids(g: Dictionary) -> Array:
	var out := []
	for e in bank_ro(g):
		out.append(String(e.id))
	return out

static func in_bank(g: Dictionary, id: String) -> bool:
	return bank_ids(g).has(id)

## 창고에서 그 기술 항목을 찾는다(없으면 {}). 돌려주는 것은 **배열 안의 그 사전 자체**다
static func bank_entry(g: Dictionary, id: String) -> Dictionary:
	for e in bank_ro(g):
		if String(e.id) == id:
			return e
	return {}

## 그 **일반** 수동 기술을 이 회차에서 가지고 있는가(배치 중이거나 창고에 있거나).
## 새 기술 획득 후보를 막는 자리가 이것을 본다 — 창고에 있는 것을 다시 '새 기술'로 주면 중복 소유가 된다
static func owns_manual_skill(g: Dictionary, id: String) -> bool:
	return has_skill(g, id) or in_bank(g, id)

## 지금 **착용 중인 장비**가 주는 장비 기술 id 목록.
## 두 통로를 합집합으로 본다(둘 중 하나만 있어도 동작한다 — 담당이 나뉘어 있기 때문이다):
##   ① 장비 정의의 grantsSkill: "eq_xxx"  ← 다른 담당이 넣는 정본
##   ② 장비 기술 정의의 grantedBy: [장비 종류 id...]  ← 이 갈래가 쓰는 보조 통로
## 가방에 든 장비는 세지 않는다. **착용**만이 자격이다(§6: 사용 가능 ≠ 배치).
static func granted_skill_ids(run: Dictionary) -> Array:
	var out := []
	var eq = run.get("equipment", null)
	if typeof(eq) != TYPE_DICTIONARY:
		return out
	var worn := []
	for slot in eq:
		if eq[slot] != null:
			worn.append(PRun.equip_type_of(String(eq[slot])))
	for t in worn:
		var d := PCatalog.equipment_def(String(t))
		var gs := String(d.get("grantsSkill", ""))
		if gs != "" and not out.has(gs):
			out.append(gs)
	var ES := PCatalog.equip_skill_defs()
	for sid in ES:
		if out.has(String(sid)):
			continue
		for t2 in (ES[sid] as Dictionary).get("grantedBy", []):
			if worn.has(String(t2)):
				out.append(String(sid))
				break
	return out

## 이 장비 기술을 **지금 쓸 수 있는가**(그 기술을 주는 장비를 착용 중인가)
static func equip_skill_granted(run: Dictionary, skill_id: String) -> bool:
	return granted_skill_ids(run).has(skill_id)

## 그 칸의 기술을 지금 쓸 수 없는 이유 한 줄. 쓸 수 있으면 ""(빈 칸도 "").
## **배치를 지우지 않는다** — 장비를 다시 끼면 아무 조작 없이 그대로 되살아난다(§6).
static func slot_blocked_reason(run: Dictionary, slot: String) -> String:
	var g: Dictionary = run.get("growth", {})
	var sid := skill_id_in(g, slot)
	if sid == "" or not is_equip_skill(sid):
		return ""
	if equip_skill_granted(run, sid):
		return ""
	var nm := String(PCatalog.skills().get(sid, {}).get("name", sid))
	return "%s은(는) 그 장비를 착용해야 씁니다. 지금은 장비를 벗어 사용할 수 없습니다(배치는 그대로 남아 있습니다)." % nm

## 그 칸에서 **실제로 쓸 수 있는** 기술(없으면 null). 전투가 보는 값은 언제나 이것이다.
## 배치(growth.skills)와 갈라 두는 이유: 장비를 벗어도 배치는 지우지 않되 전투에서는 나가지 않게 하려는 것.
static func usable_skill(run: Dictionary, slot: String):
	var g: Dictionary = run.get("growth", {})
	var sk = g.get("skills", {}).get(slot, null)
	if sk == null:
		return null
	if is_equip_skill(String(sk.id)) and not equip_skill_granted(run, String(sk.id)):
		return null
	return sk

# ---------- 편성(거점에서만, 시간·금화 소모 없음) ----------
## 편성을 지금 바꿀 수 있는가. 못 바꾸면 이유 한 줄.
## **전투 중에는 절대 열지 않는다** — 재사용 시간 시계(player.special_cd·e_cd)는 CombatState 안에만 있고,
## 거점에서 편성을 바꿔도 그 시계는 존재하지 않는다. 그래서 장착·해제·Q/E 교환으로 재사용을 초기화하거나
## 짧은 쪽으로 바꾸는 구멍이 생기지 않는다(§6). 전투 중 교체 기능은 만들지 않았다.
static func bank_edit_reason(run: Dictionary) -> String:
	# **전투가 진행 중이면 먼저 막는다**(KD-13, 2026-09-10).
	# 예전에는 run.phase 하나만 봤는데, 전투 중에도 phase 는 "prep" 그대로다
	# (PSortie.start 가 phase 를 바꾸지 않는다). 그래서 규칙 계층은 아무것도 막지 않았고,
	# 실제로 막고 있던 것은 "전투 화면에 편성 버튼이 없다"는 사실뿐이었다 —
	# 누가 전투 HUD 나 일시정지에 버튼을 하나 붙이면 그대로 뚫린다.
	# 이 표시는 PFlow.make_encounter/make_boss_encounter 가 세우고 정산·귀환이 내린다.
	# 저장에는 남기지 않는다(PSave 가 항상 false 로 정규화한다) — 전투 도중 종료하면
	# 이어하기는 거점으로 돌아오므로, 표시가 남아 편성이 영영 잠기면 안 된다.
	if bool(run.get("inCombat", false)):
		return "전투 중에는 기술 편성을 바꿀 수 없습니다."
	var phase := String(run.get("phase", "prep"))
	if phase == "prep" or phase == "boss_prep":
		return ""
	return "거점(또는 관문 준비)에서만 기술 편성을 바꿀 수 있습니다."

## 창고에 넣는다(일반 기술만). 장비 기술은 창고에 **영구 복제되지 않는다** — 그냥 배치에서 빠진다
static func _to_bank(g: Dictionary, sk) -> void:
	if sk == null:
		return
	var sid := String(sk.id)
	if is_equip_skill(sid):
		return # 장비 기술은 소유물이 아니다(장비가 소유물이다). 창고에 넣지 않는다
	if in_bank(g, sid):
		return # 같은 기술이 창고에 두 번 들어가지 않는다
	bank(g).append({ "id": sid, "level": int(sk.get("level", 1)), "variant": sk.get("variant", null) })

## 그 칸을 비우고 든 기술을 창고로 보낸다(일반 기술이면). 바뀐 것이 없으면 false
static func store_skill(run: Dictionary, slot: String) -> bool:
	if bank_edit_reason(run) != "":
		push_error(bank_edit_reason(run)); return false
	if not SKILL_SLOTS.has(slot):
		push_error("알 수 없는 칸: " + slot); return false
	var g: Dictionary = run.growth
	var sk = g.get("skills", {}).get(slot, null)
	if sk == null:
		return false
	_to_bank(g, sk)
	g.skills[slot] = null
	return true

## 그 칸에 기술을 배치한다. id는 **창고에 있는 일반 기술** 또는 **착용 장비가 주는 장비 기술**.
## - 원래 그 칸에 있던 일반 기술은 **창고로 간다**(레벨·변형을 그대로 안고 간다. 삭제하지 않는다).
## - 같은 기술을 Q와 E에 **중복 배치하지 않는다**(장비 기술도 예외가 아니다).
## - **임의로 다른 기술을 자동 선택하지 않는다** — 이 함수는 부른 쪽이 고른 것 하나만 넣는다.
static func place_skill(run: Dictionary, slot: String, id: String) -> bool:
	if bank_edit_reason(run) != "":
		push_error(bank_edit_reason(run)); return false
	if not SKILL_SLOTS.has(slot):
		push_error("알 수 없는 칸: " + slot); return false
	var g: Dictionary = run.growth
	var other := "e" if slot == "q" else "q"
	if skill_id_in(g, other) == id:
		push_error("같은 기술을 두 칸에 둘 수 없습니다: " + id); return false
	if skill_id_in(g, slot) == id:
		return false # 이미 그 칸에 있다(아무 일도 하지 않는다)
	var entry := {}
	if is_equip_skill(id):
		if not equip_skill_granted(run, id):
			push_error("그 장비를 착용해야 배치할 수 있습니다: " + id); return false
		# 장비 기술은 레벨·개조가 없다. **기존 Q/E의 레벨·변형을 계승하지 않는다**(§5)
		entry = { "id": id, "level": 1, "variant": null }
	else:
		if not PCatalog.skills().has(id):
			push_error("알 수 없는 기술: " + id); return false
		var be := bank_entry(g, id)
		if be.is_empty():
			push_error("창고에 없는 기술입니다: " + id); return false
		# 보관해 둔 레벨·변형을 **그대로** 되돌린다(§7: 다시 배치하면 복구된다)
		entry = { "id": id, "level": int(be.get("level", 1)), "variant": be.get("variant", null) }
		(bank(g) as Array).erase(be)
	_to_bank(g, g.get("skills", {}).get(slot, null))
	g.skills[slot] = entry
	return true

## Q와 E를 한 번에 맞바꾼다(§6). 레벨·변형·고유 상태는 **그 기술을 따라간다**.
## 재사용 시간은 전투 밖에 존재하지 않으므로 이 조작으로 초기화되거나 짧은 쪽으로 바뀌지 않는다.
static func swap_qe(run: Dictionary) -> bool:
	if bank_edit_reason(run) != "":
		push_error(bank_edit_reason(run)); return false
	var g: Dictionary = run.growth
	var q = g.get("skills", {}).get("q", null)
	var e = g.get("skills", {}).get("e", null)
	if q == null and e == null:
		return false
	g.skills.q = e
	g.skills.e = q
	return true

## 지금 배치할 수 있는 것들(화면이 그대로 그린다).
## { bank: [{id,name,level,variant,...}], equip: [{id,name,...}] } — 이미 다른 칸에 든 것은 blocked로 표시한다
static func placeable(run: Dictionary, slot: String) -> Dictionary:
	var g: Dictionary = run.growth
	var other := "e" if slot == "q" else "q"
	var SK := PCatalog.skills()
	var out := { "bank": [], "equip": [] }
	for be in bank_ro(g):
		var sid := String(be.id)
		var d: Dictionary = SK.get(sid, {})
		(out.bank as Array).append({ "id": sid, "name": String(d.get("name", sid)), "level": int(be.get("level", 1)),
			"variant": be.get("variant", null), "blocked": skill_id_in(g, other) == sid })
	for sid2 in granted_skill_ids(run):
		var d2: Dictionary = SK.get(String(sid2), {})
		(out.equip as Array).append({ "id": String(sid2), "name": String(d2.get("name", sid2)),
			"blocked": skill_id_in(g, other) == String(sid2), "placed": skill_id_in(g, slot) == String(sid2) })
	return out

## 변형 해금 표의 종류. 감속장 변형은 **어느 칸에 있든** 옛 q_variants 표를 그대로 쓴다
## (프로필에 이미 쌓인 해금을 슬롯이 바뀌었다는 이유로 버리지 않기 위해서다). 나머지 5종은 e_variants.
static func variant_unlock_cat(skill_id: String) -> String:
	return "q_variants" if skill_id == "slowfield" else "e_variants"

## 장비 효과가 **지금 빌드에서 동작하지 않는 이유** 한 줄. 동작하면 ""(§8).
##
## 왜 삭제가 아니라 설명인가: 사용자 지시대로 **이미 가진 효과나 장비를 조용히 지우지 않는다.**
## 감속장을 E로 교환해 잃으면 시간술사의 지팡이는 가방에 그대로 남고, 화면이 "지금은 발동하지 않는다"고 말한다.
## 다시 감속장을 얻으면 아무 조작 없이 되살아난다.
##
## eff 키 → 조건
##   fieldDirect·fieldTaken·fieldMark·fieldRegen : 감속장(Q·E 어디든) 보유
##   eShield                                     : E 칸에 수동 기술 보유(슬롯 조건)
##   relay                                       : Q·E 두 칸 모두 보유(Q 뒤 4초 안에 E — 슬롯 조건)
static func equip_inactive_reason(g: Dictionary, equip_id: String) -> String:
	var d := PCatalog.equipment_def(equip_id)
	return equip_eff_inactive_reason(g, d.get("eff", {})) if not d.is_empty() else ""

## 같은 판정을 장비 정의(eff)만 가지고 한다 — 화면이 id를 들고 있지 않은 자리에서 쓴다
static func equip_eff_inactive_reason(g: Dictionary, eff: Dictionary) -> String:
	for k in ["fieldDirect", "fieldTaken", "fieldMark", "fieldRegen"]:
		if eff.has(k) and not has_skill(g, "slowfield"):
			return "지금 빌드에 감속장이 없어 효과가 나오지 않습니다(Q나 E에 감속장을 넣으면 그대로 되살아납니다)."
	if eff.has("eShield") and g.get("skills", {}).get("e", null) == null:
		return "E 칸이 비어 있어 발동하지 않습니다(E에 수동 기술을 넣으면 되살아납니다)."
	if eff.has("relay") and (g.get("skills", {}).get("e", null) == null or g.get("skills", {}).get("q", null) == null):
		return "Q와 E 두 칸이 모두 차 있어야 발동합니다(Q를 쓴 뒤 창 안에 E를 쓰는 효과입니다)."
	return ""

## 같은 판정을 **회차 전체**로 한다. 장비를 벗어 지금 쓸 수 없는 장비 기술이 든 칸은 '빈 칸'으로 센다 —
## 그러지 않으면 쓰지도 못하는 장비 기술이 E에 박혀 있다는 이유로 '시전자의 방패'가 켜져 있다고 잘못 말한다.
## 창고에 든 기술은 어느 쪽에서도 '사용 중'으로 세지 않는다(창고는 skills를 건드리지 않는다 — §7).
static func equip_inactive_reason_run(run: Dictionary, equip_id: String) -> String:
	var d := PCatalog.equipment_def(equip_id)
	return equip_eff_inactive_reason_run(run, d.get("eff", {})) if not d.is_empty() else ""

static func equip_eff_inactive_reason_run(run: Dictionary, eff: Dictionary) -> String:
	var g: Dictionary = run.get("growth", {})
	var base := equip_eff_inactive_reason(g, eff)
	if base != "":
		return base
	if eff.has("eShield") and usable_skill(run, "e") == null:
		return "E 칸의 장비 기술을 지금 쓸 수 없어(장비를 벗었습니다) 발동하지 않습니다."
	if eff.has("relay") and (usable_skill(run, "q") == null or usable_skill(run, "e") == null):
		return "Q와 E 두 칸이 모두 지금 쓸 수 있어야 발동합니다(장비를 벗은 칸은 세지 않습니다)."
	return ""

static func has_bleed_source(g: Dictionary) -> bool:
	for w in g.weapons:
		for m in w.mods:
			if weapon_mod_has_tag(String(w.id), String(m), "bleed"):
				return true
	return false

## 보유한 상태 공급원 이름 목록(희귀 보상 설명·장비 호환 안내가 같은 기준을 쓴다)
static func has_poison_source(g: Dictionary) -> bool:
	for w in g.weapons:
		if String(w.id) == "plague":
			return true
		if String(w.id) == "thorns" and (w.mods as Array).has("venom"):
			return true
	return false

static func status_sources(g: Dictionary) -> Array:
	var out := []
	if has_common(g, "frost") or not weapon_of(g, "frost").is_empty():
		out.append("냉기")
	if has_common(g, "burn") or has_fire_source(g):
		out.append("화상")
	if has_bleed_source(g):
		out.append("출혈")
	if has_poison_source(g):
		out.append("독")
	return out

static func has_dot_source(g: Dictionary) -> bool:
	return not status_sources(g).is_empty()

static func boss_reward_applies(g: Dictionary, id: String) -> bool:
	match id:
		# 무기 공명은 **서로 다른 자동기술 3종이 같은 적을 4초 안에 때려야** 터진다(PWeapons.on_hit).
		# 새 구조에서 자리는 주무기 1 + 보조 2로 딱 3개다. 그런데 수호 방울·가시 갑각·도깨비 인형은
		# 직접 피해를 내지 않으므로, 그 셋을 골랐으면 **영원히 발동할 수 없다.**
		# 그래서 '공격 출처가 3개 이상 될 수 있는가'로 자격을 본다(사용자 지시 5절:
		# 방어 보조를 골랐다는 이유로 작동하지 않는 보상을 설명 없이 제시하지 않는다).
		"resonance": return attack_source_count(g) >= 3
		"seed": return has_dot_source(g)
		# 시간의 복제는 **감속장 조건**이다(감속장을 통과하는 투사체를 복제한다).
		# Q에 있든 E에 있든 되고, 감속장이 아예 없으면 발동할 수 없으므로 후보에서 뺀다(§8).
		"clone": return has_projectile_weapon(g) and has_skill(g, "slowfield")
		# 일제 공격은 **슬롯 조건**이다(E 사용 시). 감속장과는 무관하다
		"volley": return g.skills.get("e") != null
	return true

static func _requires_ok(g: Dictionary, d: Dictionary) -> bool:
	if not d.has("requiresAny"):
		return true
	for r in d.requiresAny:
		var req := String(r)
		if req == "common:ember" and has_common(g, "ember"):
			return true
		if req == "weapon:ember" and not weapon_of(g, "ember").is_empty():
			return true
		# 수동 기술 보유 전제(§8): "skill:<기술 id>" — Q에 있든 E에 있든 만족한다.
		# 감속장 전용 증강(시간 저축·정지된 칼날)이 감속장 없는 빌드에 나오지 않게 하는 자리다
		if req.begins_with("skill:") and has_skill(g, req.substr(6)):
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
	# 새 수동 기술은 **E 칸이 비어 있을 때만** 후보가 된다(§7: 시작은 Q 하나, E는 빈칸).
	# **이미 Q에 가진 기술은 후보에서 뺀다** — 같은 기술을 두 칸에 둘 수 없다. 감속장도 후보에 들어간다.
	if g.skills.get("e") == null:
		var q_id := skill_id_in(g, "q")
		for id in manual_skill_ids():
			var sid := String(id)
			if not SK.has(sid) or not bool(SK[sid].impl) or sid == q_id:
				continue
			if is_equip_skill(sid) or in_bank(g, sid):
				continue # 장비 기술은 새 기술 후보가 아니고, 창고에 든 것은 이미 보유다(무료로 다시 배치하면 된다)
			if not PProfile.run_unlock_ok(run, "e_skills", sid):
				continue
			push.call({ "kind": "skill_new", "id": sid, "tags": [] })
	for slot in SKILL_SLOTS:
		var sk = g.skills.get(slot)
		if sk == null:
			continue
		# **장비 기술은 레벨업·개조 후보에 섞이지 않는다**(§5). 칸을 차지하고 있어도 성장 대상이 아니다.
		# 화면에서 숨기는 것이 아니라 후보 생성 자체에서 뺀다(확정 쪽 apply_choice에서도 다시 막는다).
		if is_equip_skill(String(sk.id)):
			continue
		if not SK.has(String(sk.id)):
			continue
		var d: Dictionary = SK[String(sk.id)]
		if int(sk.level) < int(S.skillMax):
			push.call({ "kind": "skill_level", "id": String(sk.id), "slot": slot, "tags": [] })
		if sk.get("variant") == null:
			# 변형 해금은 **칸이 아니라 기술**을 따른다(감속장 변형은 어느 칸에 있어도 q_variants 표)
			var vcat := variant_unlock_cat(String(sk.id))
			for vid in d.get("variants", {}):
				if not bool(d.variants[vid].impl):
					continue
				if vcat == "q_variants" and not PProfile.run_unlock_ok(run, "q_variants", String(vid)):
					continue
				if vcat == "e_variants" and not PProfile.run_unlock_ok(run, "e_variants", String(sk.id), String(vid)):
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
		# **신규 획득 후보에서 뺀 패시브**(data/growth.json "offer": false — 빈틈 포착·지속력).
		# 막는 것은 레벨 0에서 새로 얻는 길뿐이다. 이미 보유한 회차는 레벨업 후보가 그대로 나오고
		# 효과 계산(PBuild.derive)도 그대로다 — 기존 저장의 보유분을 조용히 삭제·치환하지 않기 위해서다(§1 기존 저장)
		if lv == 0 and not bool(d.get("offer", true)):
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

# ---------- 빈 후보의 사유 구분(2026-09-09 사용자 지시) ----------
## apply_choice가 아는 선택 종류 전부. 여기 없는 종류를 임무 3택으로 요청하면 **생성 오류**다
const CHOICE_KINDS := ["weapon_new", "weapon_level", "weapon_mod", "common", "skill_new", "skill_level", "skill_variant", "passive", "service", "boss_reward"]

## 이 pool이 애초에 자료에서 몇 개를 가져올 수 있는가(보유·상한을 보기 전의 원재료 수).
## 0이면 자료가 비어 있다는 뜻이고, 그것은 정상 소진이 아니라 **생성 오류**다.
## { total: int, what: String, text: String(사람 말 한 줄) }
##
## **여기서 candidates()를 다시 부르지 않는다.** 후보 생성 도중에 후보 생성을 다시 부르면
## 종료할 때 프로세스가 죽었다(2026-09-09: run_tests·acts_tests가 단언은 전부 통과하고
## 종료 코드 3221225477로 끝났다 — 그것은 통과가 아니라 종료 실패다).
## 여기서 알고 싶은 것은 '자료가 비었나'뿐이므로 카탈로그 크기만 센다.
static func _pool_stock(_run: Dictionary, ctx: Dictionary) -> Dictionary:
	var pool_name := String(ctx.get("pool", "level"))
	if pool_name == "boss":
		var BR := PCatalog.boss_rewards()
		var n := 0
		for id in BR:
			if bool((BR[id] as Dictionary).get("impl", false)):
				n += 1
		return { "total": n, "what": "보스 희귀 보상",
			"text": "받을 수 있는 희귀 보상이 없습니다(이미 받았거나 지금 빌드에 적용되지 않습니다)." }
	if pool_name == "deep":
		return { "total": PCatalog.weapons().size() + PCatalog.commons().size() + PCatalog.passives().size(), "what": "지역 보상",
			"text": "이 지역 계열에 맞는 후보가 없습니다." }
	if pool_name == "mission":
		var kinds: Array = ctx.get("kinds", [])
		var n2 := 0
		var names := []
		for k in kinds:
			names.append(String(k))
			match String(k):
				"service": n2 += PCatalog.services().size()
				"common": n2 += PCatalog.commons().size()
				"passive": n2 += PCatalog.passives().size()
				"skill_new", "skill_level", "skill_variant": n2 += PCatalog.skills().size()
				_: n2 += PCatalog.weapons().size()
		return { "total": n2, "what": "임무 보상(%s)" % ", ".join(names),
			"text": "이 임무 보상으로 지금 줄 수 있는 것이 없습니다(전부 최대치이거나 이미 보유)." }
	return { "total": PCatalog.weapons().size() + PCatalog.commons().size() + PCatalog.passives().size() + PCatalog.skills().size(),
		"what": "레벨업 후보", "text": "더 올릴 것이 없습니다(자동기술·증강·기술이 모두 최대치입니다)." }

## 빈 후보를 **정상 소진 / 생성 오류**로 가른다. 화면은 text를 사람 말 한 줄로 보인다.
##  - "ok"        : 후보가 있다
##  - "exhausted" : 정말 더 줄 것이 없다 → 조용히 '계속'이 맞다
##  - "error"     : 후보가 있어야 하는데 0이 됐다(자료·요청·추첨 문제) → **기록을 남긴다**
static func empty_reason(run: Dictionary, ctx: Dictionary, draw_n: int, picked_n: int) -> Dictionary:
	if picked_n > 0:
		return { "code": "ok", "text": "" }
	var pool_name := String(ctx.get("pool", "level"))
	if pool_name == "mission":
		var kinds: Array = ctx.get("kinds", [])
		if kinds.is_empty():
			return { "code": "error", "text": "임무 보상의 종류가 비어 있습니다(요청 자체가 잘못됐습니다)." }
		var unknown := []
		for k in kinds:
			if not CHOICE_KINDS.has(String(k)):
				unknown.append(String(k))
		if not unknown.is_empty():
			return { "code": "error", "text": "알 수 없는 보상 종류입니다: %s" % ", ".join(unknown) }
	if draw_n > 0:
		return { "code": "error", "text": "후보 %d개가 있었는데 추첨에서 하나도 뽑히지 않았습니다." % draw_n }
	var stock := _pool_stock(run, ctx)
	if int(stock.total) <= 0:
		return { "code": "error", "text": "이 종류의 보상이 자료에 하나도 없습니다(%s)." % String(stock.what) }
	return { "code": "exhausted", "text": String(stock.text) }

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
	var draw_n: int = pool.size()   # 추첨에 들어간 후보 수(빈 결과의 사유를 가를 때 쓴다)
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
	# **빈 목록을 그냥 내보내지 않는다.** 정상 소진(더 줄 것이 없다)과 생성 오류(있어야 하는데 0이 됐다)를 갈라
	# 사유를 실어 보낸다. 화면은 그 이유를 사람 말 한 줄로 보이고, 오류만 기록을 남긴다.
	# (2026-09-09 사용자 지시: "오류 때문에 받을 보상이 사라졌는데 '계속'으로 조용히 폐기하지 마라.")
	var reason := empty_reason(run, ctx, draw_n, choices.size())
	var code := String(reason.code)
	if code == "error":
		var msg := "보상 후보 생성 오류(%s): %s" % [pool_name, String(reason.text)]
		push_error(msg)
		PRun.add_log(run, msg)
		g.offerErrors = int(g.get("offerErrors", 0)) + 1
		if not g.has("offerErrorLog"):
			g.offerErrorLog = []
		(g.offerErrorLog as Array).append("%s|%s" % [pool_name, String(reason.text)])
	elif code == "exhausted":
		g.offerExhausted = int(g.get("offerExhausted", 0)) + 1
	g.pendingOffer = { "seq": int(g.choiceSeq), "pool": pool_name, "regionId": ctx.get("region_id", null), "steer": steer_kind, "choices": choices,
		"reason": code, "reasonText": String(reason.text) }
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
			# **확정에서도 다시 막는다**(§8: 후보 생성과 선택 확정 양쪽에서 자격 확인).
			# 후보 목록을 지나 들어와도(옛 화면·저장된 조작·도구) 같은 기술을 두 칸에 두지 않는다
			if skill_id_in(g, "q") == String(choice.id):
				push_error("이미 Q에 가진 기술입니다: " + String(choice.id)); return false
			# 확정에서도 막는다: 장비 기술은 '새 수동 기술'로 얻는 것이 아니고(장비를 착용해 쓴다),
			# 창고에 든 기술은 이미 보유라 다시 지급하면 중복 소유가 된다(§5·§6)
			if is_equip_skill(String(choice.id)):
				push_error("장비 기술은 보상으로 얻지 않습니다: " + String(choice.id)); return false
			if in_bank(g, String(choice.id)):
				push_error("이미 창고에 보관 중인 기술입니다: " + String(choice.id)); return false
			if not PProfile.run_unlock_ok(run, "e_skills", String(choice.id)):
				push_error("해금되지 않은 기술입니다: " + String(choice.id)); return false
			g.skills.e = { "id": String(choice.id), "level": 1, "variant": null }
		"skill_level":
			var sk = g.skills.get(String(choice.slot))
			if sk == null or String(sk.id) != String(choice.id) or int(sk.level) >= int(S.skillMax):
				push_error("기술 레벨"); return false
			if is_equip_skill(String(choice.id)):
				push_error("장비 기술은 레벨업하지 않습니다: " + String(choice.id)); return false
			sk.level = int(sk.level) + 1
		"skill_variant":
			var sk = g.skills.get(String(choice.slot))
			if sk == null or String(sk.id) != String(choice.id) or sk.get("variant") != null:
				push_error("기술 변형"); return false
			if is_equip_skill(String(choice.id)):
				push_error("장비 기술은 개조(변형)하지 않습니다: " + String(choice.id)); return false
			# 확정에서도 해금 자격을 다시 본다(기술 교환 뒤 남아 있던 옛 후보를 그대로 받지 않게)
			var vcat2 := variant_unlock_cat(String(choice.id))
			var vok: bool = PProfile.run_unlock_ok(run, "q_variants", String(choice.variant)) if vcat2 == "q_variants" else PProfile.run_unlock_ok(run, "e_variants", String(choice.id), String(choice.variant))
			if not vok:
				push_error("해금되지 않은 변형입니다: %s %s" % [String(choice.id), String(choice.variant)]); return false
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

## 소수 둘째 자리까지(끝의 0은 지운다). 0.25%처럼 0.1 단위로 반올림하면 값이 바뀌어 보이는 자리에 쓴다
static func _fmt2(n: float) -> String:
	return str(snapped(n, 0.01))

## 소수 셋째 자리까지. 회피 재사용(0.855초 같은 값)이 "0.9"로 뭉개지지 않게
static func _fmt3(n: float) -> String:
	return str(snapped(n, 0.001))

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
			out.title = "수동 기술 습득: %s" % String(d.name); out.type = "수동 기술"; out.stage = "E 칸 비어 있음 → 장착"; out.change = String(d.desc)
			out.scope = "재사용 %s초" % _fmt(float(d.cooldown[0]) * float(before.skill_cd_mult) * float(before.get("e_cd_mult", 1.0))); out.slot = "수동 기술 E 칸"
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
			out.scope = "%s 칸의 %s" % [String(c.slot).to_upper(), String(d.name)]; out.slot = "슬롯 소비 없음"
		"skill_variant":
			var d: Dictionary = PCatalog.skills()[String(c.id)]
			var v: Dictionary = d.variants[String(c.variant)]
			out.title = "%s 변형: %s" % [String(d.name), String(v.name)]; out.type = "기술 변형"; out.stage = "변형 없음 → 선택(기술당 1개)"; out.change = String(v.desc); out.scope = "%s 칸의 %s" % [String(c.get("slot", "")).to_upper(), String(d.name)]; out.slot = "변형 슬롯 1/1"
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
				"focus": ch += " · Q 재사용 %s → %s초" % [_fmt(float(before.special_cd)), _fmt(float(after.special_cd))]
				"exploit": ch += " · 빈틈 ×%s → ×%s" % [_fmt(float(before.exposed_mult)), _fmt(float(after.exposed_mult))]
				# 회피 재사용은 **주무기 표 × 배율**이다. 화면이 숫자를 지어내지 않게 규칙과 같은 곳(자료 표)에서 읽어 곱한다.
				# 소수 셋째 자리까지 적는다 — 0.1초 단위로 반올림하면 쌍검 0.900 → 0.855가 "0.9 → 0.9"로 보여 변화가 사라진다
				"dodge_mastery":
					var dodge_base := dodge_cd_base(g)
					ch += " · 회피 재사용 %s → %s초 (거리·이동·무적 그대로)" % [
						_fmt3(dodge_base * float(before.get("dodge_cd_mult", 1.0))), _fmt3(dodge_base * float(after.get("dodge_cd_mult", 1.0)))]
				# 궁은 레벨당 0.25%라 소수 둘째 자리까지 적는다(0.1% 단위로 반올림하면 0.25가 0.3으로 보인다)
				"lifesteal": ch += " · 주무기 직접 타격이 깎은 체력의 %s%% → %s%% 회복" % [
					_fmt2(float(before.get("lifesteal", 0.0)) * 100.0), _fmt2(float(after.get("lifesteal", 0.0)) * 100.0)]
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
				"resonance":
					var atk := []
					for w in g.weapons:
						var cat := String(PCatalog.weapon(String(w.id)).get("category", "direct"))
						if cat != "guard" and cat != "summon":
							atk.append(wname.call(String(w.id)))
					out.scope = "적용: %s%s" % ["·".join(atk) if atk.size() > 0 else "없음",
						" (직접 피해를 내는 자동기술 3종이 같은 적을 4초 안에 때려야 발동 — 지금 %d종)" % atk.size() if atk.size() < 3 else ""]
				"seed":
					var srcs := status_sources(g)
					out.scope = "적용: %s" % ("·".join(srcs) if srcs.size() > 0 else "상태 이상 없음")
				"clone":
					var cslot := skill_slot_of(g, "slowfield")
					out.scope = ("적용: 투사체 자동기술 · 감속장(%s 칸) 안을 지나는 투사체가 1회 복제" % cslot.to_upper()) if cslot != "" else "적용 없음: 지금 빌드에 감속장이 없습니다"
				"volley": out.scope = "적용: E 칸 %s · E 사용 시 자동기술이 즉시 1회씩 추가 공격(Q 사용은 해당 없음)" % (String(PCatalog.skills()[String(g.skills.e.id)].name) if g.skills.get("e") != null else "없음(E 칸이 비어 있어 발동하지 않습니다)")
				"vigor": out.scope = "적용: 캐릭터 전체 · 최대 체력 %d → %d" % [int(before.hp_max), int(before.hp_max) + 25]
				"tempo": out.scope = "적용: Q 재사용 %s → %s초%s" % [_fmt(float(before.special_cd)), _fmt(float(before.special_cd) * 0.85), ", E 재사용도 15% 감소" if g.skills.get("e") != null else ""]
				_: out.scope = "모든 자동기술·기술"
			out.slot = "별도 보관(슬롯 소비 없음)"
	return out
