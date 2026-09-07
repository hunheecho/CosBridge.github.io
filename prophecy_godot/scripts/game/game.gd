extends Node
## 자동 로드: 설정 데이터 로딩·버전. 규칙(CombatState)은 여기서 만든 설정 사전만 받는다.

const VERSION := "godot-0.1.0"
const HTML_SOURCE := "html v0.8.0 (ee10fc7)"
const DATA_PATH := "res://data/first_fight.json"
var config: Dictionary = {}
var last_seed: int = 7

func _ready() -> void:
	config = load_config()

static func load_config() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("first_fight.json 없음")
		return {}
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("first_fight.json 파싱 실패")
		return {}
	return parsed

func new_combat(seed_v: int) -> CombatState:
	last_seed = seed_v
	return CombatState.new(config, seed_v)

func settings_text() -> String:
	var w: Dictionary = config.weapon
	return "%s · 원본 %s · 검격 Lv%d 피해 %s 주기 %s초 · 늑대 체력 %s · 시드 %d" % [VERSION, HTML_SOURCE, int(w.level), str(w.damage), str(w.interval), str(config.enemies.wolf.hp), last_seed]
