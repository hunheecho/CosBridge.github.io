class_name PBuild
extends RefCounted
## 회차 상태(성장·장비·강화·임시 강화) → 전투에서 쓰는 실제 수치(HTML build.js + growth.js derive 이식). 중복 적용을 막기 위해 항상 여기서만 계산한다.
## 빌드 dict: { hp_max, shield, speed_mult, toughness, exposed_mult, skill_cd_mult, special_cd, damage_mult, mastery_mult, interval_mult, range_mult, width_mult, duration_mult,
##   forge, forge_mult, equip{eff 합산}, equip_ids[], weapons[파생 stats], commons{}, passives{}, skills{q,e}, boss_rewards[], growth(참조), level, has(id) 대신 has_common(b,id) }
## 영구 특성(run.traits가 있을 때만 키 추가): traits[], trait_shield, q_cd_mult, e_cd_mult, heal_mult, trait_dot_mult, trait_dot_dur,
##   trait_dmg{near_dist,near_mult,far_dist,far_mult,focus_id,focus_up,focus_down,link_window,link_mult,link_skill_mult,direct_mult}

static func has_common(b: Dictionary, id: String) -> bool:
	return int(b.commons.get(id, 0)) > 0

static func empty_run_like(growth: Dictionary) -> Dictionary:
	return { "growth": growth, "equipment": { "weapon": null, "armor": null, "shield": null }, "forge": 0, "buffs": {} }

## levelScale 항목 하나를 레벨 lv(1부터)에 적용한다. { "mult": [...] } 은 곱, { "add": [...] } 은 합.
## 배열이 짧으면 마지막 값을 쓴다(상한을 넘겨도 조용히 커지지 않게)
static func level_scaled(v: float, spec: Dictionary, lv: int) -> float:
	var out := v
	if spec.has("mult"):
		var a: Array = spec.mult
		out *= float(a[clampi(lv - 1, 0, a.size() - 1)])
	if spec.has("add"):
		var a2: Array = spec.add
		out += float(a2[clampi(lv - 1, 0, a2.size() - 1)])
	return out

## 무기 파생 수치(HTML Growth.weaponStats)
## 그 자동기술에 적용되는 대장간 강화 배율. 없으면 1.0
static func forge_mult_of(b: Dictionary, weapon_id: String) -> float:
	if PGrowth.growth_legacy:
		return 1.0   # 옛 구조에서는 대장간이 전체 강화라 b.damage_mult 쪽에 들어간다
	var by: Dictionary = b.get("forge_by_skill", {})
	var lv: int = int(by.get(weapon_id, 0))
	if lv <= 0:
		return 1.0
	var mults: Array = PCatalog.shop().forgeMult
	return 1.0 + float(mults[mini(lv, mults.size() - 1)])

static func weapon_stats(b: Dictionary, w: Dictionary) -> Dictionary:
	var d := PCatalog.weapon(String(w.id))
	var base: Dictionary = d.base
	if String(w.id) == "spear" and b.has("spear_override"):
		base = base.duplicate()
		for k in b.spear_override:
			base[k] = b.spear_override[k] # 밸런스 세트의 창 후보(근접 약화·주기, test03 시험값 — PORT_BASELINE C9)
	var G := PCatalog.growth()
	var g: Dictionary = b.get("growth", {})
	# 레벨 상한은 역할을 따른다: 옛 구조는 전부 5, 새 구조는 주무기 5 / 보조 3.
	# 저장에 상한보다 높은 레벨이 남아 있어도 계산에서만 잘라 쓴다(저장값을 깎지 않는다)
	var lv: int = mini(int(w.level), PGrowth.level_cap(g, String(w.id)))
	# 레벨 강화표는 data/supports.json levelScale이 기본이고, **무기 정의 안에 levelScale이 있으면 그쪽이 이긴다**
	# (data/main_weapons.json이 겹쳐 쓴 값). 한 무기의 레벨 곡선만 바꾸려고 공용 배율을 건드리지 않기 위한 자리다
	var scale: Dictionary = PCatalog.level_scale().get(String(w.id), {})
	var own_scale: Dictionary = d.get("levelScale", {})
	if not own_scale.is_empty():
		scale = scale.duplicate(true)
		for k in own_scale:
			scale[k] = own_scale[k]
	var lv_mult: float = float(PGrowth.LEGACY_LEVEL_MULT[lv - 1]) if PGrowth.growth_legacy else float(G.LEVEL_MULT[lv - 1])
	var dmg_scale: Dictionary = scale.get("damage", {})
	# set = 그 레벨의 기본 피해를 **절대값**으로 정한다(곱셈 오차 없이 표 그대로).
	# 여기서 base 자체를 갈아 끼우므로 아래 damage_mult·대장간 강화는 예전과 똑같이 곱해진다
	if dmg_scale.has("set") and not PGrowth.growth_legacy:
		var arr: Array = dmg_scale["set"]
		base = base.duplicate()
		base.damage = float(arr[clampi(lv - 1, 0, arr.size() - 1)])
		lv_mult = 1.0
	elif scale.has("damage") and not PGrowth.growth_legacy:
		lv_mult = level_scaled(1.0, scale.damage, lv)
	var s := base.duplicate(true)
	s.id = String(w.id)
	s.level = int(w.level)
	s.mods = (w.mods as Array).duplicate()
	s.def = d
	s.kind = String(d.kind)
	s.name = String(d.name)
	# 대장간 강화(2026-09-08 시험값): 전체 강화가 아니라 **고른 자동기술 하나**에 투자한다.
	# b.forge_by_skill[무기 id] 단계의 배율을 그 무기 피해에만 곱한다.
	# 옛 저장(전체 강화 run.forge)은 derive에서 모든 무기에 같은 단계를 넣어 화력을 그대로 보존한다.
	s.damage = float(base.damage) * lv_mult * float(b.damage_mult) * forge_mult_of(b, String(w.id))
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
	# 보조 레벨업의 역할별 강화(data/supports.json levelScale, 전부 시험값).
	# 모든 보조를 피해 증가 하나로 처리하지 않는다는 지시(1절)를 여기서 지킨다.
	# 폭·사거리 공용 증강을 먼저 곱한 **뒤** 적용한다 — 순서를 바꾸면 같은 값이 두 번 곱해진다.
	for sk in scale:
		var key := String(sk)
		if key == "damage" or not s.has(key):
			continue
		s[key] = level_scaled(float(s[key]), scale[key], lv)
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
	var equip := {}
	var equip_ids := []
	for slot in ["weapon", "armor", "shield"]:
		var id = eq.get(slot, null)
		if id == null:
			continue
		var ed := PCatalog.equipment_def(String(id)) # 일반 12 + 제작 6(제작품은 재료 장비 효과를 이어받지 않고 자기 eff만)
		if not ed.is_empty():
			equip_ids.append(String(id))
			for k in ed.eff:
				equip[k] = ed.eff[k]
	var forge: int = mini(3, int(run.get("forge", 0)))
	var forge_mults: Array = PCatalog.shop().forgeMult
	# 무기별 대장간 강화 표. 새 회차는 run.forgeBySkill을 쓰고, 옛 저장(run.forge만 있는 회차)은
	# 그 단계를 모든 자동기술에 그대로 넣어 화력을 보존한다(조용히 약해지지 않게).
	var forge_by_skill := {}
	var fbs = run.get("forgeBySkill", null)
	if typeof(fbs) == TYPE_DICTIONARY:
		for k in (fbs as Dictionary):
			forge_by_skill[String(k)] = int((fbs as Dictionary)[k])
	elif forge > 0:
		for w0 in g.get("weapons", []):
			forge_by_skill[String(w0.id)] = forge
	var b := {
		"hp_max": float(C.PLAYER.hp) + float(equip.get("hpMax", 0.0)),
		"shield": float(equip.get("startShield", 0.0)),
		"exposed_mult": float(C.PLAYER.exposedMult),
		"skill_cd_mult": 1.0, "dodge_cd_mult": 1.0,
		"forge": forge, "forge_mult": (1.0 + float(forge_mults[forge])) if PGrowth.growth_legacy else 1.0, # 전체 강화 자리는 비운다(무기별로 옮겼다). 옛 구조 재현에서만 쓴다
		"forge_by_skill": forge_by_skill, "forge_legacy": typeof(run.get("forgeBySkill", null)) != TYPE_DICTIONARY and forge > 0,
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
	# 정복자(run.conqueror, 새 회차에서 고정 — 시험값 meta.json conqueror). 포인트가 없으면 키가 없어 기준 빌드(D33)와 같다.
	# 체력은 기본 체력에만 비율(패시브·장비·보스 보상은 그대로 더함), 공격은 damage_mult(공용 강화·숙련 자리)에 1회, 이동은 speed_mult에 1회
	var cq: Dictionary = run.get("conqueror", {}) if typeof(run.get("conqueror", {})) == TYPE_DICTIONARY else {}
	if not cq.is_empty():
		var CE := PProfile.conqueror_effects(cq)
		b.conqueror = cq.duplicate()
		b.conq_hp = float(C.PLAYER.hp) * float(CE.hp)
		b.hp_max += b.conq_hp
		b.conq_damage_mult = 1.0 + float(CE.damage)
		b.damage_mult = float(b.damage_mult) * float(b.conq_damage_mult)
		b.speed_mult = float(b.speed_mult) * (1.0 + float(CE.speed))
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
	if equip.has("overflowShield") and float(run.get("storedShield", 0.0)) > 0.0:
		b.shield += minf(float(equip.overflowShield.max), float(run.storedShield)) # 재생의 여행복: 저장된 초과 회복분(전투 시작 시 소비, PFlow.make_encounter)
	# 영구 특성(run.traits, 새 회차에서 고정 — 시험값 meta.json). 특성이 없으면 어떤 키도 추가하지 않아 기준 전투(D33)와 같은 빌드가 된다
	var traits: Array = run.get("traits", [])
	if not traits.is_empty():
		var TE := PProfile.trait_effects(traits)
		b.traits = traits.duplicate()
		if TE.has("startShield"):
			b.shield += float(TE.startShield) # 별도 출처(방호 준비)
			b.trait_shield = float(TE.startShield)
		if TE.has("speed"):
			b.speed_mult *= 1.0 + float(TE.speed)
		if TE.has("interval"):
			b.interval_mult *= 1.0 - float(TE.interval)
		if TE.has("qCd"):
			b.q_cd_mult = 1.0 - float(TE.qCd)
		if TE.has("eCd"):
			b.e_cd_mult = 1.0 - float(TE.eCd)
		if TE.has("healMult"):
			b.heal_mult = 1.0 + float(TE.healMult)
		if TE.has("dotMult"):
			b.trait_dot_mult = 1.0 + float(TE.dotMult)
		if TE.has("dotDur"):
			b.trait_dot_dur = 1.0 + float(TE.dotDur)
		var td := {}
		if TE.has("nearMult"):
			td.near_dist = float(TE.nearDist)
			td.near_mult = 1.0 + float(TE.nearMult)
		if TE.has("farMult"):
			td.far_dist = float(TE.farDist)
			td.far_mult = 1.0 + float(TE.farMult)
		if TE.has("focusUp"):
			td.focus_id = String(run.get("startWeapon", String(g.weapons[0].id) if (g.weapons as Array).size() > 0 else ""))
			td.focus_up = 1.0 + float(TE.focusUp)
			td.focus_down = 1.0 - float(TE.focusDown)
		if TE.has("linkMult"):
			td.link_window = float(TE.linkWindow)
			td.link_mult = 1.0 + float(TE.linkMult)
			td.link_skill_mult = 1.0 - float(TE.linkSkillDown)
		if TE.has("directDown"):
			td.direct_mult = 1.0 - float(TE.directDown)
		if not td.is_empty():
			b.trait_dmg = td
	b.weapons = []
	for w in g.weapons:
		b.weapons.append(weapon_stats(b, w))
	b.commons = g.get("commons", {}).duplicate()
	b.passives = p.duplicate()
	b.skills = { "q": g.skills.q.duplicate() if g.skills.get("q") != null else null, "e": g.skills.e.duplicate() if g.skills.get("e") != null else null }
	b.boss_rewards = rewards.duplicate()
	# Q 슬롯의 재사용 시간. **그 칸에 든 기술의 표**를 읽는다 — 예전에는 감속장 표를 고정으로 읽었는데,
	# Q와 E가 같은 6종을 공유하게 되면서(§7) 그 가정이 틀렸다. Q가 비어 있으면 0(쓸 것이 없다).
	var q = g.skills.get("q")
	if q == null:
		b.special_cd = 0.0
		return b
	var SKC := PCatalog.skills()
	var qid := String(q.id)
	var qcd_tbl: Array = SKC[qid].cooldown if SKC.has(qid) else SKC.slowfield.cooldown
	var qlv: int = mini(qcd_tbl.size(), maxi(1, int(q.level)))
	var qcd: float = float(qcd_tbl[qlv - 1])
	b.special_cd = maxf(1.0, qcd * float(b.skill_cd_mult) * float(b.get("q_cd_mult", 1.0)))
	return b

## 카드 미리보기: 선택을 적용한 뒤의 파생 수치
static func preview_with_choice(run: Dictionary, choice: Dictionary) -> Dictionary:
	var r: Dictionary = run.duplicate(true)
	PGrowth.apply_choice(r, choice, true)
	return derive(r)
