class_name PBoss
extends RefCounted
## (임시 스텁 — 보스는 이식 중) HTML boss.js

static func cfg_of(e: Dictionary) -> Dictionary: return PCatalog.boss_def(String(e.get("boss_id", "boss")))
static func spawn(st: CombatState, x: float, y: float, boss_id: String) -> Dictionary:
	var e := st.spawn_enemy(boss_id, x, y); e.boss_id = boss_id; e.boss = true; e.state = "intro"; st.boss = e; return e
static func update(_st: CombatState, _e: Dictionary, _dt: float) -> void: pass
static func check_phase(_st: CombatState, _e: Dictionary) -> void: pass
static func stagger(_st: CombatState, _e: Dictionary) -> void: pass
static func is_exposed(e: Dictionary) -> bool: return e.state == "recover" or e.state == "stagger"
static func boss_committed(_e: Dictionary) -> bool: return false
static func summoned_alive(st: CombatState) -> int:
	var n := 0
	for e in st.enemies:
		if not e.dead and bool(e.get("summoned", false)): n += 1
	return n
static func dash_path(st: CombatState, e: Dictionary, ang: float, max_dist: float) -> Dictionary:
	var dx := cos(ang) * max_dist; var dy := sin(ang) * max_dist; var t := 1.0
	var x1: float = e.x + dx; var y1: float = e.y + dy
	var wx := clampf(x1, e.r, st.arena_w - e.r); var wy := clampf(y1, e.r, st.arena_h - e.r)
	if wx != x1 or wy != y1:
		var tx: float = (wx - e.x) / dx if wx != x1 else 1.0; var ty: float = (wy - e.y) / dy if wy != y1 else 1.0
		t = maxf(0.0, minf(t, minf(tx, ty)))
	var sw := st.sweep_circle(e.x, e.y, x1, y1, e.r)
	if sw[1] >= 0 and sw[0] < t: t = sw[0]
	return { "len": max_dist * t, "end": [e.x + dx * t, e.y + dy * t] }
