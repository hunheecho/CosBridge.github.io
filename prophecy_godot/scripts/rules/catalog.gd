class_name PCatalog
extends RefCounted
## 데이터 카탈로그(res://data/*.json) 1회 로드·캐시. HTML src/*_data.js를 tools/port_export_data.js로 내보낸 값이며 코드에 숫자를 두지 않는다.
## 규칙 코드는 이 사전을 읽기만 한다(수정 금지). JSON 숫자는 float이므로 정수는 int()로 받는다.

static var _cache: Dictionary = {}

static func _load(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := "res://data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("데이터 없음: " + path)
		_cache[name] = {}
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("파싱 실패: " + path)
		_cache[name] = {}
		return {}
	_cache[name] = parsed
	return parsed

static func reset() -> void:
	_cache = {}

static func config() -> Dictionary: return _load("config").config
static func arenas() -> Dictionary: return _load("config").arenas
static func blade_spoke() -> Dictionary: return _load("config").blade_spoke
## 보스 행동 문구: config.json(기존 3종) + bosses_new.json(신규 6종 상태명)을 합친 사전(1회 캐시)
static func boss_action_text() -> Dictionary:
	if _cache.has("boss_action_text_merged"):
		return _cache["boss_action_text_merged"]
	var out: Dictionary = (_load("config").boss_action_text as Dictionary).duplicate()
	for k in bosses_new().get("boss_action_text", {}):
		if not out.has(k):
			out[k] = bosses_new().boss_action_text[k]
	_cache["boss_action_text_merged"] = out
	return out
static func keys_text() -> String: return String(_load("config").keys_text)
## 자동기술 정의: weapons.json(생성 파일) + supports.json(손으로 정한 새 보조 7종)을 합친 사전(1회 캐시).
## supports.json 쪽이 같은 id를 가지면 그쪽이 이긴다 — 손으로 정한 값이 생성 값을 덮는다는 뜻이다.
## 주무기 5종은 main_weapons.json이 **항목만** 겹쳐 쓴다(통째로 바꾸지 않는다 — 이름·태그·개조 목록은 생성 값 그대로).
static func weapons() -> Dictionary:
	if _cache.has("weapons_merged"):
		return _cache["weapons_merged"]
	var out: Dictionary = (_load("weapons").weapons as Dictionary).duplicate(true)
	for k in supports().get("weapons", {}):
		out[k] = (supports().weapons[k] as Dictionary).duplicate(true)
	for k in main_weapons().get("weapons", {}):
		out[k] = _overlay(out.get(k, {}), main_weapons().weapons[k])
	_cache["weapons_merged"] = out
	return out

## 사전 겹쳐 쓰기: 양쪽 다 사전인 항목은 안으로 들어가 항목별로 덮고, 그 밖에는 새 값이 이긴다
static func _overlay(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over:
		if typeof(over[k]) == TYPE_DICTIONARY and typeof(out.get(k, null)) == TYPE_DICTIONARY:
			out[k] = _overlay(out[k], over[k])
		else:
			out[k] = over[k]
	return out

## 새 구조에서 시작 선택은 주무기만이다. supports.json이 목록을 갖고 있으면 그것을 쓴다(옛 목록은 회전 칼날을 포함한다)
static func startable() -> Array: return supports().get("startable", _load("weapons").startable)
static func startable_all() -> Array: return supports().get("startableAll", _load("weapons").startable_all)
static func startable_legacy() -> Array: return _load("weapons").startable
static func startable_all_legacy() -> Array: return _load("weapons").startable_all

# ---------- 주무기·보조무기 분리(data/supports.json) ----------
static func supports() -> Dictionary: return _load("supports")
## 주무기 5종의 손으로 정한 값(data/main_weapons.json, 전부 시험값). weapons()가 겹쳐 읽는다
static func main_weapons() -> Dictionary: return _load("main_weapons")
## 자동기술의 역할. 표에 없으면 보조로 본다(새로 추가된 자동기술이 주무기 자리를 말없이 차지하지 않게)
static func weapon_role(id: String) -> String:
	return String(supports().get("roles", {}).get(id, "support"))
static func is_main_weapon(id: String) -> bool: return weapon_role(id) == "main"
static func slot_rules() -> Dictionary: return supports().get("slots", {})
static func level_scale() -> Dictionary: return supports().get("levelScale", {})
static func eligibility() -> Dictionary: return supports().get("eligibility", {})
static func support_resist() -> Dictionary: return supports().get("resist", {})
## '연계 완성' 경직표(sources·sec·cooldownSec). CombatState.apply_stagger만 읽는다
static func link_stagger() -> Dictionary: return supports().get("stagger", {})
## 기존 보조 5종의 손으로 정한 값(생성 파일을 고치지 않기 위한 겹쳐쓰기). 전부 시험값
static func support_tuning(id: String) -> Dictionary:
	return supports().get("tuning", {}).get(id, {})
static func growth() -> Dictionary: return _load("growth").growth
static func commons() -> Dictionary: return _load("growth").commons
static func passives() -> Dictionary: return _load("growth").passives
## 수동 기술 정의: growth.json의 **일반 수동 기술 6종** + meta.json equip_skills의 **장비 기술**(id가 "eq_"로 시작).
## 두 목록을 여기서 합치는 이유: 재사용 시간·이름을 읽는 자리(PBuild·PSkills·화면)가 사전 하나만 보면 되게 하려는 것이다.
## **합쳤다고 같은 종류가 되는 것은 아니다** — 장비 기술은 e_skills(보상·상점 후보 목록)에 들어가지 않고,
## 레벨업·개조·창고 보관 대상도 아니다(§5). 그 구분은 PGrowth.is_equip_skill 한 곳에서 판정한다.
static func skills() -> Dictionary:
	if _cache.has("skills_merged"):
		return _cache["skills_merged"]
	var out: Dictionary = (_load("growth").skills as Dictionary).duplicate(true)
	for k in equip_skill_defs():
		out[String(k)] = equip_skill_defs()[k]
	_cache["skills_merged"] = out
	return out

## 장비 기술 정의만. **정본은 data/growth.json의 skills 중 id가 "eq_"로 시작하는 것**이다.
##
## 2026-09-10 통합에서 잡은 결함: 두 갈래가 같은 기술에 **서로 다른 id**를 붙였다.
##   장비가 주는 것(grantsSkill) : eq_meteor · eq_icetomb · eq_reprieve
##   창고가 등록한 것             : eq_meteordrop · eq_crystalcoffin · eq_reprieveclock
## 정의가 두 곳(growth.json · meta.json)에 각각 있어 6종 중 3종이 이어지지 않았다.
## 창고 쪽은 장비가 아직 없던 때의 임시 등록이었고, 전투 구현과 grantsSkill이 쓰는 것은
## 짧은 쪽(합의한 규약)이다. 그래서 **정의를 growth.json 한 곳으로 모으고**
## meta.json의 병행 정의는 비웠다. 앞으로 기술을 늘려도 한 곳만 고치면 된다.
static func equip_skill_defs() -> Dictionary:
	if _cache.has("equip_skill_defs"):
		return _cache["equip_skill_defs"]
	var out := {}
	var GS: Dictionary = _load("growth").skills
	for k in GS:
		if String(k).begins_with("eq_"):
			out[String(k)] = GS[k]
	_cache["equip_skill_defs"] = out
	return out

## 이 장비 기술을 주는 장비 종류 id. 없으면 "". 방향은 **장비 → 기술**(grantsSkill) 하나뿐이다
static func equipment_granting(skill_id: String) -> String:
	for id in equipment():
		if String((equipment()[id] as Dictionary).get("grantsSkill", "")) == skill_id:
			return String(id)
	for id in crafted_equipment():
		if typeof(crafted_equipment()[id]) != TYPE_DICTIONARY:
			continue
		if String((crafted_equipment()[id] as Dictionary).get("grantsSkill", "")) == skill_id:
			return String(id)
	return ""

static func e_skills() -> Array: return _load("growth").e_skills
static func boss_rewards() -> Dictionary: return _load("growth").boss_rewards
static func region_tags() -> Dictionary: return _load("growth").region_tags
static func region_tag_text() -> Dictionary: return _load("growth").region_tag_text
## 적 정의: enemies.json + 신규 보스 6종의 몸체(boss:true, spawn_enemy가 읽는 name·r·hp·speed·color). 기존 3종 보스도 같은 방식으로 enemies에 있다
static func enemies() -> Dictionary:
	if _cache.has("enemies_merged"):
		return _cache["enemies_merged"]
	var out: Dictionary = (_load("enemies").enemies as Dictionary).duplicate()
	for k in bosses_new().get("bosses", {}):
		if not out.has(k):
			var b: Dictionary = bosses_new().bosses[k]
			out[k] = { "name": String(b.name), "role": String(b.title), "r": float(b.r), "hp": float(b.hp), "speed": float(b.speed), "color": String(b.color), "boss": true, "readme": "신규 관문 보스(bosses_new.json, 시험값)" }
	# 신규 일반 3종(흡혈 박쥐·불씨 도마뱀·도약 두꺼비)과 일반 정예 확장은 data/pacing.json의
	# enemy_tuning에 정의가 있고 PEnemiesNew가 만든다. **여기서 합쳐야** 전투가 시작되기 전
	# 편성 조회·경험치·시험 경로에서도 같은 사전을 본다(전에는 전투 첫 프레임에야 등록됐다).
	for k in PEnemiesNew.extra_defs(out):
		if not out.has(k):
			out[k] = PEnemiesNew.extra_defs(out)[k]
	# **화면에 보이는 설명도 겹침 파일이 덮는다.**
	# 값(frontMult 등)은 PEnemiesNew.dv가 pacing.json enemy_tuning을 먼저 보는데,
	# readme·role은 화면이 정의 사전을 직접 읽어서 겹침이 닿지 않았다.
	# 그래서 방패병 정면 감소를 85%→70%로 바꾼 뒤에도 설명만 "15%만 들어간다"로 남아 있었다
	# (2026-09-09 사람 지적). 값과 설명이 어긋나지 않게 여기서 함께 덮는다.
	var tune: Dictionary = pacing().get("enemy_tuning", {})
	for k in tune:
		if not out.has(String(k)):
			continue
		var t: Dictionary = tune[k]
		for disp in ["readme", "role", "name"]:
			if t.has(disp):
				(out[String(k)] as Dictionary)[disp] = t[disp]
	_cache["enemies_merged"] = out
	return out
## 신규 보스 6종(bosses_new.json, 손으로 작성 — 시험값). enemies.json의 기존 3종 정의는 그대로 두고 아래 boss_defs/boss_hp_sets가 합친다
static func bosses_new() -> Dictionary: return _load("bosses_new")
static func boss_defs() -> Dictionary:
	if _cache.has("boss_defs_merged"):
		return _cache["boss_defs_merged"]
	var out: Dictionary = (_load("enemies").boss_defs as Dictionary).duplicate()
	for k in bosses_new().get("bosses", {}):
		if not out.has(k):
			out[k] = bosses_new().bosses[k]
	_cache["boss_defs_merged"] = out
	return out
static func boss_hp_sets() -> Dictionary:
	if _cache.has("boss_hp_sets_merged"):
		return _cache["boss_hp_sets_merged"]
	var out := {}
	var base: Dictionary = _load("enemies").boss_hp_sets
	for s in base:
		out[s] = (base[s] as Dictionary).duplicate()
	for s in bosses_new().get("boss_hp_sets", {}):
		if not out.has(s):
			out[s] = {}
		for b in bosses_new().boss_hp_sets[s]:
			if not (out[s] as Dictionary).has(b):
				out[s][b] = bosses_new().boss_hp_sets[s][b]
	_cache["boss_hp_sets_merged"] = out
	return out
static func run_modes() -> Dictionary: return _load("enemies").run_modes
static func world() -> Dictionary: return _load("world")
## 장비 사전. 평소에는 data/world.json 그대로다.
##
## 시험 전용 겹쳐쓰기(PROPHECY_EQUIP_SKILL_DEMO=1): 장비 기술 6종을 주는 **장비 정의**는 다른 담당의 몫이라
## 아직 자료에 없다. 그런데 '소유 / 창고 보관 / Q·E 배치 / 장비 착용' 네 상태를 **실제 화면에서 눌러**
## 확인하려면 grantsSkill을 가진 장비가 하나는 있어야 한다. 그래서 시험용 장비 한 개를 코드 안에만 두고
## 환경 변수로만 켠다 — data/world.json·data/meta.json의 장비 정의는 건드리지 않는다.
## 환경 변수가 없으면 사전에 **하나도 들어가지 않아** 평소 동작·저장·시험이 전과 완전히 같다.
const DEMO_EQUIP_ENV := "PROPHECY_EQUIP_SKILL_DEMO"
const DEMO_EQUIP_ID := "demo_flashcut_blade"

static func equip_skill_demo() -> bool:
	return OS.get_environment(DEMO_EQUIP_ENV) != ""

static func equipment() -> Dictionary:
	var EQ: Dictionary = _load("world").equipment
	if equip_skill_demo() and not EQ.has(DEMO_EQUIP_ID):
		EQ[DEMO_EQUIP_ID] = {
			"name": "시험용 각인검", "slot": "weapon",
			"short": "시험 전용 · 착용 중 장비 기술 '찰나 가르기'를 쓸 수 있다",
			"desc": "시험 전용 장비다(환경 변수로만 나타난다). 착용하면 장비 기술 '찰나 가르기'를 Q나 E에 배치할 수 있다.",
			"eff": {}, "grantsSkill": "eq_flashcut",
		}
	return EQ
static func shop() -> Dictionary: return _load("world").shop
static func regions() -> Array: return _load("world").regions
static func materials() -> Dictionary: return _load("world").materials
## 밸런스 오버레이(손으로 작성, 내보내기 아님 — PPacing이 읽는다)
static func pacing() -> Dictionary: return _load("pacing")
static func density() -> Dictionary: return _load("world").density
static func world_stages() -> Dictionary: return _load("world").get("world_stages", {})
static func tier(id: String) -> Dictionary:
	var T: Dictionary = world_stages().get("tiers", {})
	return T[id] if T.has(id) else { "name": "일반", "hp": 1.0, "dmg": 1.0 }
## 밀도 세트 override(Q1 비교 후보): 이름이 없거나 기본 세트면 {}(density 루트 값 그대로)
static func density_set(name: String) -> Dictionary:
	var D: Dictionary = _load("world").density
	var sets: Dictionary = D.get("sets", {})
	if name == "" or not sets.has(name) or name == String(D.get("set_default", "")):
		return {}
	var out := {}
	var S: Dictionary = sets[name]
	for k in S:
		if k != "name" and k != "role_class":
			out[k] = S[k]
	out["set_name"] = name
	return out
static func missions() -> Dictionary: return _load("missions")
static func objectives() -> Dictionary: return _load("missions").objectives
static func structures() -> Dictionary: return _load("missions").structures
static func services() -> Dictionary:
	if _cache.has("services_merged"):
		return _cache["services_merged"]
	var src: Dictionary = _load("missions").services
	var out := {}
	for k in src: # 표시 이름·설명 오버레이(용어 통일: 개조 변경권). 내보내기 산출물은 그대로 둔다
		var v: Dictionary = (src[k] as Dictionary).duplicate()
		v.name = PPacing.service_name(String(k), String(v.get("name", k)))
		v.desc = PPacing.service_desc(String(k), String(v.get("desc", "")))
		out[k] = v
	_cache["services_merged"] = out
	return out
static func mission_rules() -> Dictionary: return _load("missions").missions
static func events() -> Dictionary: return _load("missions").events
static func event_ids() -> Array: return _load("missions").event_ids
static func balance() -> Dictionary: return _load("balance")
static func balance_sets() -> Dictionary: return _load("balance").balance_sets
static func difficulty() -> Dictionary: return _load("balance").difficulty
static func layouts() -> Dictionary: return _load("balance").layouts
static func lab() -> Dictionary: return _load("balance").lab
static func lab_combos() -> Array: return _load("balance").lab_combos
## 용어 사전: 내보낸 glossary.json + 손으로 쓴 meta.json glossary(영구 성장·특성·제작 전용 장비)를 합친 사전(1회 캐시)
static func glossary() -> Dictionary:
	if _cache.has("glossary_merged"):
		return _cache["glossary_merged"]
	var out: Dictionary = (_load("glossary").glossary as Dictionary).duplicate()
	for k in meta().get("glossary", {}):
		if not out.has(k):
			out[k] = meta().glossary[k]
	for k in out: # 용어 오버레이(개조 변경권 통일)
		var ov := PPacing.glossary_override(String(k))
		if not ov.is_empty():
			var e: Dictionary = (out[k] as Dictionary).duplicate()
			for f in ov:
				e[f] = ov[f]
			out[k] = e
	_cache["glossary_merged"] = out
	return out
static func first_fight() -> Dictionary: return _load("first_fight")
## 실력 프로필 봇(bots.json, 손으로 작성한 시험값 — 사람 보정 미완료, docs/BOT_FRAMEWORK.md)
static func bots() -> Dictionary: return _load("bots")
static func bot_profiles() -> Dictionary: return _load("bots").get("profiles", {})

# ---------- 영구 성장·해금·제작(meta.json, 손으로 작성 — 시험값) ----------
static func meta() -> Dictionary: return _load("meta")
static func meta_levels() -> Dictionary: return meta().levels
static func meta_records() -> Dictionary: return meta().records
## 회차 구조별 기록 규칙(10일 본편은 하루 2/3 기록): { name, day_win: float, day_max, boss_first, clear }
static func meta_records_for(mode: String) -> Dictionary:
	var base: Dictionary = meta().records
	var out := { "name": String(base.name), "day_win": float(base.get("day_win", 1)), "day_max": int(base.get("day_max", 6)), "boss_first": int(base.get("boss_first", 2)), "clear": int(base.get("clear", 2)) }
	var bm: Dictionary = base.get("by_mode", {})
	if bm.has(mode):
		var o: Dictionary = bm[mode]
		if o.has("day_win_frac"):
			out.day_win = float(o.day_win_frac[0]) / float(o.day_win_frac[1])
		elif o.has("day_win"):
			out.day_win = float(o.day_win)
		if o.has("day_max"):
			out.day_max = int(o.day_max)
	return out
static func run_mode_default() -> String: return String(_load("enemies").get("run_mode_default", "trio"))
static func meta_unlocks() -> Dictionary: return meta().unlocks
static func meta_profiles() -> Dictionary: return meta().profiles
static func meta_endless() -> Dictionary: return meta().get("endless", {})
static func meta_conqueror() -> Dictionary: return meta().get("conqueror", {})
static func challenges() -> Dictionary: return meta().challenges
static func traits() -> Dictionary: return meta().traits
static func trait_defs() -> Dictionary: return meta().traits.defs
static func trait_rows() -> Array: return meta().traits.rows
## 제작 전용 장비 6종(world.json equipment에는 넣지 않는다 — 상점·심층 후보에서 제외)
static func crafted_equipment() -> Dictionary:
	if _cache.has("crafted_equipment"):
		return _cache["crafted_equipment"]
	var out := {}
	var CE: Dictionary = meta().get("crafted_equipment", {})
	for k in CE:
		if String(k) != "note":
			out[String(k)] = CE[k]
	_cache["crafted_equipment"] = out
	return out
## 제작법: id → {equipment[], mats{}, fee}
static func recipe(id: String) -> Dictionary:
	var CE := crafted_equipment()
	return CE[id].recipe if CE.has(id) else {}
## 장비 정의(일반 12 + 제작 6). 없으면 {}
static func equipment_def(id: String) -> Dictionary:
	var EQ := equipment()
	if EQ.has(id):
		return EQ[id]
	var CE := crafted_equipment()
	if CE.has(id):
		return CE[id]
	push_error("알 수 없는 장비: " + id)
	return {}
## **회차를 시작해도 되는 자료가 실제로 섰는가.**
## _load 는 실패하면 빈 사전을 돌려주고 게임은 그대로 진행한다 — 그러면 장비·무기가 전부
## '없는 것'이 되어 빌드 계산 아래에서 죽는다. 그 상태로는 **회차에 들어가지 않는 것**이 맞다.
## 없는 장비를 저장에서 빼는 처리(PSave)도 이 판정이 참일 때만 한다 —
## 자료가 안 섰는데 정리하면 멀쩡한 장비를 지운다.
## 비어 있으면 무엇이 비었는지 사람 말로 돌려준다. 정상이면 빈 문자열.
static func data_problem() -> String:
	var missing: Array = []
	if (equipment() as Dictionary).is_empty():
		missing.append("장비")
	if (weapons() as Dictionary).is_empty():
		missing.append("자동기술")
	if (skills() as Dictionary).is_empty():
		missing.append("수동 기술")
	if (enemies() as Dictionary).is_empty():
		missing.append("적")
	if missing.is_empty():
		return ""
	return "게임 자료를 읽지 못했습니다(%s). 회차를 시작할 수 없습니다 — 저장은 그대로 둡니다." % ", ".join(missing)

static func data_ready() -> bool:
	return data_problem() == ""

## 이 장비 id 가 지금 자료에 있는가. **오류를 내지 않고** 묻기만 한다
## (PSave 가 저장을 불러올 때 없는 장비를 걸러내는 데 쓴다)
static func equipment_known(id: String) -> bool:
	return equipment().has(id) or crafted_equipment().has(id)

static func is_crafted(id: String) -> bool:
	return crafted_equipment().has(id)

## 폐기 장비(§1, 2026-09-10): 반격 방패·연계 방패. 자료 정의는 **지우지 않는다** —
## 기존 저장에 든 것을 아무 보상 없이 삭제하지 않기 위해서다(이전 처리는 미확정, 사용자 결정 대기).
## 여기서 true면 **신규 유입**(상점 진열·제작 후보·보상 후보)에서만 뺀다.
static func equipment_retired(id: String) -> bool:
	return bool(equipment_def(id).get("retired", false))

## **지금 제작할 수 있는 제작법 전부**(폐기 제외). 2026-09-10 사용자 확정:
## "제작 가능 총계는 **실제 활성 목록에서** 계산해라. 4나 5를 고정값으로 박지 마라."
## → 화면·도감·검사 어디서도 개수를 손으로 적지 않고 이 한 곳을 부른다.
## 자료에 제작 장비를 하나 더 넣으면 총계가 저절로 는다(폐기로 표시하면 저절로 준다).
## **보유·달성 기록과는 다른 값이다** — 옛 저장이 가진 폐기 제작법의 기록은 여기서 빠져도 지워지지 않는다.
static func active_crafted_ids() -> Array:
	var out: Array = []
	for id in crafted_equipment():
		var cid := String(id)
		if not equipment_retired(cid):
			out.append(cid)
	return out

static func active_crafted_count() -> int:
	return active_crafted_ids().size()

## 강화 단계(+0~+2)를 반영한 장비 효과 사전. upgrade 표에 적힌 항목만 값을 바꾸고,
## 표에 없는 것은 +0 값 그대로다(횟수·단계·지속·재사용·무적 시간은 표에 넣지 않는다 — §4).
## 경로 표기: "reduce"는 eff.reduce, "bigHit.reduce"는 eff.bigHit.reduce를 뜻한다(사전은 복제해서 고친다)
static func equipment_eff(id: String, plus: int) -> Dictionary:
	var d := equipment_def(id)
	var eff: Dictionary = d.get("eff", {})
	var up: Dictionary = d.get("upgrade", {})
	if plus <= 0 or up.is_empty():
		return eff
	var out: Dictionary = eff.duplicate(true)
	for path in up:
		var arr: Array = up[path]
		if arr.is_empty():
			continue
		var v: float = float(arr[clampi(plus - 1, 0, arr.size() - 1)])
		var parts := String(path).split(".", false)
		var node := out
		var okp := true
		for i in parts.size() - 1:
			var k := String(parts[i])
			if typeof(node.get(k, null)) != TYPE_DICTIONARY:
				okp = false
				break
			node = node[k]
		if okp:
			node[String(parts[parts.size() - 1])] = v
	return out

static func enemy(type: String) -> Dictionary:
	var E := enemies()
	if E.has(type):
		var e: Dictionary = E[type]
		var nm := PPacing.enemy_name(type, "")
		if nm != "" and String(e.get("name", "")) != nm: # 표시 이름 오버레이(제단 이름 통일). 1회만 바꾸고 캐시에 남긴다
			e = e.duplicate()
			e.name = nm
			E[type] = e
		return e
	push_error("알 수 없는 적: " + type)
	return {}

static func weapon(id: String) -> Dictionary:
	var W := weapons()
	if W.has(id):
		return W[id]
	push_error("알 수 없는 자동기술: " + id)
	return {}

## 테마(10일·3막): data/themes.json. 장소(place)는 지역 사전과 같은 모양이라 지역 규칙(비용·보상·태그·재료·전장)을 그대로 쓴다
static func themes() -> Dictionary: return _load("themes").get("themes", {})
static func theme(id: String) -> Dictionary:
	var T := themes()
	return T[id] if T.has(id) else {}
static func theme_places() -> Dictionary:
	var out := {}
	for tid in themes():
		for p in (themes()[tid] as Dictionary).places:
			var d: Dictionary = (p as Dictionary).duplicate()
			d.theme = String(tid)
			out[String(d.id)] = d
	return out
static func theme_of_place(place_id: String) -> String:
	var P := theme_places()
	return String(P[place_id].theme) if P.has(place_id) else ""
static func theme_arenas() -> Dictionary: return _load("themes").get("arenas", {})
static func theme_reward_weight() -> float: return float(_load("themes").get("reward_weight", 1.15))
static func act_default_theme(act: int) -> String: return String((_load("themes").get("act_default", {}) as Dictionary).get(str(act), ""))

## 특수 정예 배치표(data/elites.json). 어느 막·어떤 편성에 어떤 정예를 넣을 수 있는지의 정본이다.
## 수치(체력·행동)는 여기가 아니라 data/enemies.json·data/pacing.json에 있다.
static func elites() -> Dictionary: return _load("elites").get("elites", {})
static func elite_def(id: String) -> Dictionary:
	var E := elites()
	return E[id] if E.has(id) else {}
static func elite_placement() -> Dictionary: return _load("elites").get("placement", {})
## 그 막에서 한 전투에 넣을 수 있는 정예 마리 수 상한(없으면 1)
static func elite_max_per_fight(act: int) -> int:
	var M: Dictionary = elite_placement().get("max_elites_per_fight", {})
	return int(M.get(str(clampi(act, 1, 3)), 1))

static func region(id: String) -> Dictionary:
	for r in regions():
		if String(r.id) == id:
			return r
	var P := theme_places()
	return P[id] if P.has(id) else {}

## 전장(기존 config.arenas + 테마 전장)
static func arena(id: String) -> Dictionary:
	var A := arenas()
	if A.has(id):
		return A[id]
	var TA := theme_arenas()
	return TA[id] if TA.has(id) else {}

static func boss_def(id: String) -> Dictionary:
	var B := boss_defs()
	return B[id] if B.has(id) else B.boss

static func mods_of(weapon_id: String) -> Dictionary:
	return weapon(weapon_id).get("mods", {})
