class_name PSupportA
extends RefCounted
## 보조무기 A조: ⑥ 추격 까마귀 · ⑦ 수호 방울 · ⑧ 잔영 분신 · ⑨ 바람 정령.
## 공통 규칙(발동 자격표·제압 저항·경감 순서)은 PSupport에 있고 여기서는 그것만 쓴다.
## 수치는 data/supports.json에 있고 전부 시험값이다.
##
## 아직 구현하지 않았다. 네 보조 모두 impl:false라 성장 후보·상점에 나오지 않는다.

const KINDS := ["crow", "bell", "echo", "wind"]

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
