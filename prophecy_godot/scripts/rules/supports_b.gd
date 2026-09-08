class_name PSupportB
extends RefCounted
## 보조무기 B조: ⑩ 역병 나비 · ⑪ 가시 갑각 · ⑫ 도깨비 인형.
## 공통 규칙(발동 자격표·제압 저항·경감 순서)은 PSupport에 있고 여기서는 그것만 쓴다.
## 수치는 data/supports.json에 있고 전부 시험값이다.
##
## 아직 구현하지 않았다. 세 보조 모두 impl:false라 성장 후보·상점에 나오지 않는다.

const KINDS := ["plague", "thorns", "doll"]

static func handles(kind: String) -> bool:
	return KINDS.has(kind)

static func fire(_st: CombatState, _w: Dictionary, _target: Dictionary, _echoed: bool) -> bool:
	return false

static func update(_st: CombatState, _dt: float) -> void:
	pass

static func on_player_damage(_st: CombatState, amount: float, _src: String, _attacker) -> float:
	return amount

static func after_player_damage(_st: CombatState, _amount: float, _src: String, _attacker) -> void:
	pass

static func on_enemy_hit(_st: CombatState, _e: Dictionary, _opt: Dictionary, _dmg: float) -> void:
	pass

static func on_enemy_death(_st: CombatState, _e: Dictionary, _opt: Dictionary) -> void:
	pass

## 인형 유인 대상. {}이면 평소대로 플레이어를 노린다
static func lure_target(_st: CombatState, _e: Dictionary) -> Dictionary:
	return {}
