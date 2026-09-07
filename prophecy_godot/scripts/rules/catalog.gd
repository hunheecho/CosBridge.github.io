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
static func glossary() -> Dictionary: return _load("glossary").glossary
static func first_fight() -> Dictionary: return _load("first_fight")

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

static func region(id: String) -> Dictionary:
	for r in regions():
		if String(r.id) == id:
			return r
	return {}

static func boss_def(id: String) -> Dictionary:
	var B := boss_defs()
	return B[id] if B.has(id) else B.boss

static func mods_of(weapon_id: String) -> Dictionary:
	return weapon(weapon_id).get("mods", {})
