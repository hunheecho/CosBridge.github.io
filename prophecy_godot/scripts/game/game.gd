extends Node
## 자동 로드: 설정 데이터 로딩·버전·비교 설정. 규칙(CombatState)은 여기서 만든 설정 사전만 받는다.
## 비교 설정(회피 방식·재사용, 편성, 동시 돌진 제한)은 전투 중 바꾸지 않고 다음 재시작(new_combat)에만 적용된다.

const VERSION := "godot-0.3.1"
const HTML_SOURCE := "html v0.8.0 (ee10fc7)"
const DATA_PATH := "res://data/first_fight.json"
var config: Dictionary = {}
var last_seed: int = 7
# 다음 재시작에 적용될 비교 설정(기본값은 데이터의 값)
var dodge_mode: String = "hold"
var dodge_cooldown: float = 1.5
var formation_id: String = "x5"
var dash_max: int = 2

func _ready() -> void:
	config = load_config()
	if not config.is_empty():
		dodge_mode = String(config.player.dodge.mode)
		dodge_cooldown = float(config.player.dodge.cooldown)
		formation_id = String(config.formation_default)
		dash_max = int(config.enemies.wolf.dash.max_concurrent)

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

## 기본 데이터에 선택한 비교 설정만 덮어쓴 설정 사본(규칙은 이 사본만 본다)
static func config_with(base: Dictionary, mode: String, cooldown: float, formation: String, dmax: int) -> Dictionary:
	var c: Dictionary = base.duplicate(true)
	c.player.dodge.mode = mode
	c.player.dodge.cooldown = cooldown
	c.formation_id = formation
	c.formation = c.formations[formation].duplicate(true)
	c.enemies.wolf.dash.max_concurrent = dmax
	return c

static func config_with_dodge(base: Dictionary, mode: String, cooldown: float) -> Dictionary:
	return config_with(base, mode, cooldown, String(base.formation_default), int(base.enemies.wolf.dash.max_concurrent))

func current_config() -> Dictionary:
	return config_with(config, dodge_mode, dodge_cooldown, formation_id, dash_max)

func new_combat(seed_v: int) -> CombatState:
	last_seed = seed_v
	return CombatState.new(current_config(), seed_v)

static func dodge_mode_name(mode: String) -> String:
	return "누르는 시간에 따른 거리 조절" if mode == "hold" else "고정 거리(기존)"

## 어떤 설정 사전의 회피 설정 한 줄(HUD·결과·검증 패널이 실제 적용된 값에서 파생)
static func dodge_text(c: Dictionary) -> String:
	var D: Dictionary = c.player.dodge
	var dist := ("%d~%d" % [int(D.min_distance), int(D.distance)]) if String(D.mode) == "hold" else str(int(D.distance))
	return "회피 %s %s · 재사용 %.1f초" % [dodge_mode_name(String(D.mode)), dist, float(D.cooldown)]

static func formation_text(c: Dictionary) -> String:
	var F: Dictionary = c.formation
	return "%s(전체 %d · 동시 %d · 묶음 %d · 간격 %.1f초) · 동시 돌진 %d" % [String(F.name), int(F.total), int(F.alive_cap), int(F.group), float(F.interval), int(c.enemies.wolf.dash.max_concurrent)]

func settings_text(c: Dictionary = {}) -> String:
	if c.is_empty():
		c = current_config()
	var w: Dictionary = c.weapon
	var wolf: Dictionary = c.enemies.wolf
	return "%s · 원본 %s · 검격 Lv%d 피해 %s 주기 %s초 · 늑대 체력 %s 물기 %s/돌진 %s · %s · %s · 시드 %d" % [VERSION, HTML_SOURCE, int(w.level), str(w.damage), str(w.interval), str(wolf.hp), str(wolf.bite.damage), str(wolf.dash.damage), formation_text(c), dodge_text(c), last_seed]

## HUD 하단용 짧은 설정 줄(한 줄에 들어가게)
func settings_short(c: Dictionary) -> String:
	var w: Dictionary = c.weapon
	var wolf: Dictionary = c.enemies.wolf
	var F: Dictionary = c.formation
	var D: Dictionary = c.player.dodge
	var dodge := ("회피 조절 %d~%d" % [int(D.min_distance), int(D.distance)]) if String(D.mode) == "hold" else ("회피 고정 %d" % int(D.distance))
	return "%s · 검격 %s/%s초 · 늑대 %s 물기 %s/돌진 %s · %s 전체 %d 동시 %d 돌진 %d · %s/%.1f초 · 시드 %d" % [VERSION, str(w.damage), str(w.interval), str(wolf.hp), str(wolf.bite.damage), str(wolf.dash.damage), String(F.name), int(F.total), int(F.alive_cap), int(wolf.dash.max_concurrent), dodge, float(D.cooldown), last_seed]
