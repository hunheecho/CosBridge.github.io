class_name PEnemiesNew
extends RefCounted
## (임시 스텁 — 신규 8종은 이식 중) HTML enemies.js: 멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적

static func has(_type: String) -> bool: return false
static func update(_st: CombatState, _e: Dictionary, _dt: float) -> void: pass
static func is_committed(_e: Dictionary) -> bool: return false
static func shield_mult(_st: CombatState, _e: Dictionary, _opt: Dictionary) -> float: return 1.0
static func on_damaged(_st: CombatState, _e: Dictionary, _dmg: float, _opt: Dictionary) -> void: pass
static func detonate(_st: CombatState, _z: Dictionary) -> void: pass
static func threats(_st: CombatState, _e: Dictionary, _out: Array) -> void: pass
static func zone_threats(_st: CombatState, _out: Array) -> void: pass
