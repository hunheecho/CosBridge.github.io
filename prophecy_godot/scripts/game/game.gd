extends Node
## 자동 로드: 설정 데이터 로딩·버전·비교 설정. 규칙(CombatState)은 여기서 만든 설정 사전만 받는다.
## 비교 설정(회피 방식·재사용 대기)은 전투 중 바꾸지 않고 다음 재시작(new_combat)에만 적용된다.

const VERSION := "godot-0.2.0"
const HTML_SOURCE := "html v0.8.0 (ee10fc7)"
const DATA_PATH := "res://data/first_fight.json"
var config: Dictionary = {}
var last_seed: int = 7
# 다음 재시작에 적용될 회피 설정(기본값은 데이터의 값: hold · 1.5초)
var dodge_mode: String = "hold"
var dodge_cooldown: float = 1.5

func _ready() -> void:
	config = load_config()
	if not config.is_empty():
		dodge_mode = String(config.player.dodge.mode)
		dodge_cooldown = float(config.player.dodge.cooldown)

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

## 기본 데이터에 선택한 회피 설정만 덮어쓴 설정 사본(규칙은 이 사본만 본다)
static func config_with_dodge(base: Dictionary, mode: String, cooldown: float) -> Dictionary:
	var c: Dictionary = base.duplicate(true)
	c.player.dodge.mode = mode
	c.player.dodge.cooldown = cooldown
	return c

func new_combat(seed_v: int) -> CombatState:
	last_seed = seed_v
	return CombatState.new(config_with_dodge(config, dodge_mode, dodge_cooldown), seed_v)

static func dodge_mode_name(mode: String) -> String:
	return "누르는 시간에 따른 거리 조절" if mode == "hold" else "고정 거리(기존)"

## 어떤 설정 사전의 회피 설정 한 줄(HUD·결과·검증 패널이 실제 적용된 값에서 파생)
static func dodge_text(c: Dictionary) -> String:
	var D: Dictionary = c.player.dodge
	var dist := ("%d~%d" % [int(D.min_distance), int(D.distance)]) if String(D.mode) == "hold" else str(int(D.distance))
	return "회피 %s %s · 재사용 %.1f초" % [dodge_mode_name(String(D.mode)), dist, float(D.cooldown)]

func settings_text(c: Dictionary = {}) -> String:
	if c.is_empty():
		c = config_with_dodge(config, dodge_mode, dodge_cooldown)
	var w: Dictionary = c.weapon
	return "%s · 원본 %s · 검격 Lv%d 피해 %s 주기 %s초 · 늑대 체력 %s · %s · 시드 %d" % [VERSION, HTML_SOURCE, int(w.level), str(w.damage), str(w.interval), str(c.enemies.wolf.hp), dodge_text(c), last_seed]
