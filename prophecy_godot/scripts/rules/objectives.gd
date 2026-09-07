class_name PObjectives
extends RefCounted
## (임시 스텁 — 목표 4종은 이식 중) HTML objectives.js

static func is_objective(_id: String) -> bool: return false
static func setup(_st: CombatState, _opts: Dictionary) -> void: pass
static func update(_st: CombatState, _dt: float) -> void: pass
static func check(_st: CombatState) -> bool: return false
static func on_player_hit(_st: CombatState) -> void: pass
static func zone_damage(_st: CombatState, _z: Dictionary, _p: Dictionary) -> float: return 0.0
