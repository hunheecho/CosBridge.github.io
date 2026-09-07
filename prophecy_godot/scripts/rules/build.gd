class_name PBuild
extends RefCounted
## 회차 상태(성장·장비·강화·임시 강화) → 전투에서 쓰는 실제 수치(HTML build.js + growth.js derive 이식). 중복 적용을 막기 위해 항상 여기서만 계산한다.
## 빌드 dict: { hp_max, shield, speed_mult, toughness, exposed_mult, skill_cd_mult, special_cd, damage_mult, mastery_mult, interval_mult, range_mult, width_mult, duration_mult,
##   forge, forge_mult, equip{eff 합산}, equip_ids[], weapons[파생 stats], commons{}, passives{}, skills{q,e}, boss_rewards[], growth(참조), level, has(id) 대신 has_common(b,id) }

static func has_common(b: Dictionary, id: String) -> bool:
	return int(b.commons.get(id, 0)) > 0

static func empty_run_like(growth: Dictionary) -> Dictionary:
	return { "growth": growth, "equipment": { "weapon": null, "armor": null, "shield": null }, "forge": 0, "buffs": {} }

## 무기 파생 수치(HTML Growth.weaponStats)
static func weapon_stats(b: Dictionary, w: Dictionary) -> Dictionary:
	var d := PCatalog.weapon(String(w.id))
	var base: Dictionary = d.base
	if String(w.id) == "spear" and b.has("spear_override"):
		base = base.duplicate()
		for k in b.spear_override:
			base[k] = b.spear_override[k] # 밸런스 세트의 창 후보(근접 약화·주기, test03 시험값 — PORT_BASELINE C9)
	var G := PCatalog.growth()
	var lv: int = mini(int(w.level), int(G.SLOTS.weaponMax))
	var lv_mult: float = float(G.LEVEL_MULT[lv - 1])
	var s := base.duplicate(true)
	s.id = String(w.id)
	s.level = int(w.level)
	s.mods = (w.mods as Array).duplicate()
	s.def = d
	s.kind = String(d.kind)
	s.name = String(d.name)
	s.damage = float(base.damage) * lv_mult * float(b.damage_mult)
	s.interval = float(base.interval) * float(b.interval_mult)
	if bool(d.reach) and base.has("range"):
		s.range = float(base.range) * float(b.range_mult)
	if bool(d.width):
		if base.has("arcDeg"):
			s.arcDeg = minf(360.0, float(base.arcDeg) * float(b.width_mult))
		if base.has("width"):
			s.width = float(base.width) * float(b.width_mult)
		if base.has("radius"):
			s.radius = float(base.radius) * float(b.width_mult)
		if base.has("trigger"):
			s.trigger = float(base.trigger) * float(b.width_mult)
	if String(d.kind) == "arc" and bool(d.width):
		s.range = float(s.get("range", base.range)) * (1.0 + (float(b.width_mult) - 1.0) * 0.5)
	# snake_case 별칭(규칙 코드가 쓰는 이름)
	s.arc_deg = float(s.get("arcDeg", 0.0))
	s.hit_gap = float(s.get("hitGap", 0.0))
	s.knock = float(s.get("knock", 0.0))
	s.range = float(s.get("range", 0.0))
	return s

## run dict(growth·equipment·forge·buffs)에서 빌드 계산. growth 전용이면 empty_run_like(growth)를 넘긴다
static func derive(run: Dictionary) -> Dictionary:
	var C := PCatalog.config()
	var G := PCatalog.growth()
	var g: Dictionary = run.growth
	var PV: Dictionary = G.PASSIVE_VALUES
	var CV: Dictionary = G.COMMON_VALUES
	var p: Dictionary = g.get("passives", {})
	var eq: Dictionary = run.get("equipment", { "weapon": null, "armor": null, "shield": null })
	var EQ := PCatalog.equipment()
	var equip := {}
	var equip_ids := []
	for slot in ["weapon", "armor", "shield"]:
		var id = eq.get(slot, null)
		if id != null and EQ.has(String(id)):
			equip_ids.append(String(id))
			for k in EQ[String(id)].eff:
				equip[k] = EQ[String(id)].eff[k]
	var forge: int = mini(3, int(run.get("forge", 0)))
	var forge_mults: Array = PCatalog.shop().forgeMult
	var b := {
		"hp_max": float(C.PLAYER.hp) + float(equip.get("hpMax", 0.0)),
		"shield": float(equip.get("startShield", 0.0)),
		"exposed_mult": float(C.PLAYER.exposedMult),
		"skill_cd_mult": 1.0, "dodge_cd_mult": 1.0,
		"forge": forge, "forge_mult": 1.0 + float(forge_mults[forge]),
		"equip": equip, "equip_ids": equip_ids,
		"growth": g, "level": int(g.level),
	}
	var BS := PCatalog.balance_sets()
	var bal := String(run.get("balance", "current"))
	if BS.has(bal) and BS[bal].has("spear") and not (BS[bal].spear as Dictionary).is_empty():
		b.spear_override = BS[bal].spear
	b.mastery_mult = 1.0 + float(PV.mastery) * float(p.get("mastery", 0))
	b.damage_mult = b.forge_mult * b.mastery_mult
	b.interval_mult = 1.0 - float(PV.haste) * float(p.get("haste", 0))
	var reach_lv: int = int(g.get("commons", {}).get("reach", 0))
	var wide_lv: int = int(g.get("commons", {}).get("wide", 0))
	b.range_mult = float(CV.reach[reach_lv - 1]) if reach_lv > 0 else 1.0
	b.width_mult = float(CV.wide[wide_lv - 1]) if wide_lv > 0 else 1.0
	b.hp_max += float(PV.vitality) * float(p.get("vitality", 0))
	b.speed_mult = 1.0 + float(PV.mobility) * float(p.get("mobility", 0))
	b.toughness = float(PV.toughness) * float(p.get("toughness", 0))
	b.exposed_mult = float(b.exposed_mult) + float(PV.exploit) * float(p.get("exploit", 0))
	b.duration_mult = 1.0 + float(PV.persistence) * float(p.get("persistence", 0))
	b.skill_cd_mult = (1.0 - float(PV.focus) * float(p.get("focus", 0))) * float(b.skill_cd_mult)
	var rewards: Array = g.get("bossRewards", [])
	if rewards.has("tempo"):
		b.skill_cd_mult *= 0.85
	if rewards.has("vigor"):
		b.hp_max += 25.0
	var buffs: Dictionary = run.get("buffs", {})
	if buffs.has("skillCd"):
		b.skill_cd_mult *= float(buffs.skillCd) # 시간의 샘: 다음 전투 1회
	if equip.has("speed"):
		b.speed_mult *= 1.0 + float(equip.speed)
	if equip.has("reach"):
		b.range_mult *= 1.0 + float(equip.reach)
		b.width_mult *= 1.0 + float(equip.reach)
	b.weapons = []
	for w in g.weapons:
		b.weapons.append(weapon_stats(b, w))
	b.commons = g.get("commons", {}).duplicate()
	b.passives = p.duplicate()
	b.skills = { "q": g.skills.q.duplicate() if g.skills.get("q") != null else null, "e": g.skills.e.duplicate() if g.skills.get("e") != null else null }
	b.boss_rewards = rewards.duplicate()
	var q = g.skills.get("q")
	var qlv: int = mini(3, int(q.level)) if q != null else 1
	var qcd: float = float(PCatalog.skills().slowfield.cooldown[qlv - 1])
	b.special_cd = maxf(1.0, qcd * float(b.skill_cd_mult))
	return b

## 카드 미리보기: 선택을 적용한 뒤의 파생 수치
static func preview_with_choice(run: Dictionary, choice: Dictionary) -> Dictionary:
	var r: Dictionary = run.duplicate(true)
	PGrowth.apply_choice(r, choice, true)
	return derive(r)
