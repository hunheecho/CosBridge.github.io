extends Node
## 자동 로드: 설정 데이터 로딩·버전·비교 설정. 규칙(CombatState)은 여기서 만든 설정 사전만 받는다.
## 비교 설정(회피 방식·재사용, 편성, 동시 돌진 제한)은 전투 중 바꾸지 않고 다음 재시작(new_combat)에만 적용된다.

const VERSION := "godot-1.1.0"
const HTML_SOURCE := "html v0.8.0 (ee10fc7)"
const DATA_PATH := "res://data/first_fight.json"
## 화면 글꼴. 저장소에 함께 들어 있고(2026-09-09), 두 내보내기(웹·윈도우)에 모두 담긴다.
## 웹(브라우저)에는 운영체제 글꼴이 없어서 이 파일이 빠지면 한글이 전부 네모(□)로 나온다 — docs/WEB_BUILD.md §2 참고.
## 파일이 없어도 게임은 돌아간다(_apply_ui_font가 아무것도 하지 않고, PC는 엔진이 운영체제 글꼴로 대신 그린다).
const UI_FONT_PATH := "res://assets/fonts/ui.ttf"
## 글꼴 라이선스 전문(내보내기에 함께 담긴다. 설정 화면의 고지가 이 경로를 가리킨다).
const UI_FONT_LICENSE_PATH := "res://assets/fonts/OFL.txt"
## 화면에 그대로 띄우는 짧은 고지. OFL 1.1은 저작권 표시와 라이선스를 함께 배포하라고 요구한다.
const UI_FONT_NOTICE := "글꼴 Noto Sans KR (c) 2014-2021 Adobe · SIL Open Font License 1.1"
## 제목 화면 아래 줄에 덧붙이는 한 마디(자리가 좁아 더 짧다).
const UI_FONT_NOTICE_SHORT := "글꼴 Noto Sans KR · OFL 1.1"
var config: Dictionary = {}
var last_seed: int = 7
# 다음 재시작에 적용될 비교 설정(기본값은 데이터의 값)
var dodge_mode: String = "hold"
var dodge_cooldown: float = 1.5
var formation_id: String = "x5"
var dash_max: int = 2

func _ready() -> void:
	_apply_ui_font()
	config = load_config()
	if not config.is_empty():
		dodge_mode = String(config.player.dodge.mode)
		dodge_cooldown = float(config.player.dodge.cooldown)
		formation_id = String(config.formation_default)
		dash_max = int(config.enemies.wolf.dash.max_concurrent)

## 글꼴 깔기: 파일이 있을 때만. 없으면 아무것도 하지 않는다(PC는 엔진이 운영체제 글꼴로 대신 그린다).
## project.godot의 gui/theme/custom_font가 이미 같은 일을 하지만, 이 함수를 남겨 둔다 —
## 자동 로드보다 먼저 도는 엔진 초기화에 기대지 않고 코드에서도 한 번 더 확실히 못 박기 위해서다(같은 값이라 덮어써도 무해).
## 두 군데를 모두 바꿔야 한다 — 한 쪽만 바꾸면 화면 절반이 네모로 남는다:
##   ① 기본 테마의 default_font — Label·Button·RichTextLabel 같은 Control이 실제로 읽는 곳.
##      ThemeDB.fallback_font만 바꿔서는 기본 테마가 먼저 걸려 바뀌지 않는다(4.7에서 확인).
##   ② ThemeDB.fallback_font — 직접 그리는 쪽(PRender.font(), PTouchControls._draw())이 읽는 곳.
func _apply_ui_font() -> void:
	if not ResourceLoader.exists(UI_FONT_PATH):
		return
	var f := load(UI_FONT_PATH)
	if not (f is Font):
		return
	ThemeDB.get_default_theme().default_font = f
	ThemeDB.fallback_font = f

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
	return CombatState.first_fight(current_config(), seed_v)

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
