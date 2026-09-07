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
static func boss_action_text() -> Dictionary: return _load("config").boss_action_text
static func keys_text() -> String: return String(_load("config").keys_text)
static func weapons() -> Dictionary: return _load("weapons").weapons
static func startable() -> Array: return _load("weapons").startable
static func startable_all() -> Array: return _load("weapons").startable_all
static func growth() -> Dictionary: return _load("growth").growth
static func commons() -> Dictionary: return _load("growth").commons
static func passives() -> Dictionary: return _load("growth").passives
static func skills() -> Dictionary: return _load("growth").skills
static func e_skills() -> Array: return _load("growth").e_skills
static func boss_rewards() -> Dictionary: return _load("growth").boss_rewards
static func region_tags() -> Dictionary: return _load("growth").region_tags
static func region_tag_text() -> Dictionary: return _load("growth").region_tag_text
static func enemies() -> Dictionary: return _load("enemies").enemies
static func boss_defs() -> Dictionary: return _load("enemies").boss_defs
static func boss_hp_sets() -> Dictionary: return _load("enemies").boss_hp_sets
static func run_modes() -> Dictionary: return _load("enemies").run_modes
static func world() -> Dictionary: return _load("world")
static func equipment() -> Dictionary: return _load("world").equipment
static func shop() -> Dictionary: return _load("world").shop
static func regions() -> Array: return _load("world").regions
static func materials() -> Dictionary: return _load("world").materials
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
static func services() -> Dictionary: return _load("missions").services
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
	_cache["glossary_merged"] = out
	return out
static func first_fight() -> Dictionary: return _load("first_fight")

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
static func is_crafted(id: String) -> bool:
	return crafted_equipment().has(id)

static func enemy(type: String) -> Dictionary:
	var E := enemies()
	if E.has(type):
		return E[type]
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
