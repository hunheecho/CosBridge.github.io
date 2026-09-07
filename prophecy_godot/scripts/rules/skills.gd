class_name PSkills
extends RefCounted
## 수동 기술(HTML skills.js 이식): Q 감속장(레벨·변형 3) + E 선택 기술(5종, 레벨·변형). 기술 피해에는 무기 숙련이 적용되지 않는다.
## 감속장 수치(반지름·지속·감속)는 cfg.player.slowfield(첫 전투 호환), 재사용은 build.special_cd(레벨·집중·박자·샘).

static func init(st: CombatState) -> void:
	st.skill_state = { "storm": {}, "gravity": {}, "ward": {}, "target": null, "field2": {} }
	st.player.e_cd = 0.0

static func cd_of(st: CombatState, slot: String) -> float:
	var sk = st.build.skills.get(slot)
	if sk == null:
		return 0.0
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	return float(d.cooldown[mini(3, int(sk.level)) - 1]) * float(st.build.skill_cd_mult)

static func sdmg(st: CombatState, slot: String) -> float:
	var sk = st.build.skills.get(slot)
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	if d.has("damage"):
		return float(d.damage[mini(3, int(sk.level)) - 1])
	return 0.0

static func hit(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary = {}) -> float:
	var o := opt.duplicate()
	var eid := String(st.build.skills.e.id) if st.build.skills.get("e") != null else "e"
	o.src = { "skill": true, "direct": false, "skill_id": eid }
	return st.damage_enemy(e, dmg, o)

# ---------- Q 감속장 ----------
static func cast_q(st: CombatState) -> void:
	var p := st.player
	var S: Dictionary = st.cfg.player.slowfield
	var b := st.build
	var sk = b.skills.get("q")
	var variant: String = String(sk.variant) if sk != null and sk.get("variant") != null else ""
	if not st.field.is_empty():
		st.end_field()
	var dur := float(S.duration) * float(b.duration_mult)
	if variant == "split":
		st.field = { "x": p.x, "y": p.y, "r": 100.0, "ttl": dur, "max_ttl": dur, "follow": false }
		var far := {}
		var bd := INF
		for e in st.alive_targets():
			var d := PGeom.dist(e.x, e.y, p.x, p.y)
			if d > 60.0 and d < bd:
				bd = d
				far = e
		st.skill_state.field2 = { "x": far.x, "y": far.y, "r": 100.0, "ttl": dur, "max_ttl": dur } if not far.is_empty() else {}
	else:
		st.field = { "x": p.x, "y": p.y, "r": float(S.radius), "ttl": dur, "max_ttl": dur, "follow": variant == "follow" }
	p.special_cd = maxf(1.0, float(b.special_cd))
	st.stats.special_uses += 1
	st.ev("special")
	st.text(p.x, p.y - 50.0, "감속장", "#a9d8ff")

static func on_field_end(st: CombatState, f: Dictionary) -> void:
	var sk = st.build.skills.get("q")
	if sk != null and sk.get("variant") != null and String(sk.variant) == "echo":
		st.add_zone("slowecho", f.x, f.y, f.r, 1.5, 0.0)
	st.skill_state.field2 = {}

static func in_field2(st: CombatState, ox: float, oy: float, orad: float) -> bool:
	if st.skill_state.is_empty():
		return false
	var f: Dictionary = st.skill_state.get("field2", {})
	return not f.is_empty() and PGeom.dist(f.x, f.y, ox, oy) <= f.r + orad

# ---------- E ----------
static func auto_target(st: CombatState, range_v: float) -> Dictionary:
	var p := st.player
	var mk = st.mark_target
	if mk != null and not mk.dead and PGeom.dist(p.x, p.y, mk.x, mk.y) <= range_v + mk.r:
		return mk
	var alive := st.alive_targets()
	for e in alive:
		if e.elite and PGeom.dist(p.x, p.y, e.x, e.y) <= range_v + e.r:
			return e
	var best := {}
	var bd := INF
	for e in alive:
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d <= range_v + e.r and d < bd:
			bd = d
			best = e
	return best

static func cluster(st: CombatState, range_v: float) -> Dictionary:
	var p := st.player
	var list := []
	for e in st.alive_targets():
		if not e.boss and PGeom.dist(p.x, p.y, e.x, e.y) <= range_v:
			list.append(e)
	if list.is_empty():
		var tg := auto_target(st, range_v)
		return { "x": tg.x, "y": tg.y } if not tg.is_empty() else {}
	var sx := 0.0
	var sy := 0.0
	for e in list:
		sx += e.x
		sy += e.y
	return { "x": sx / float(list.size()), "y": sy / float(list.size()) }

static func push_enemy(st: CombatState, e: Dictionary, dir: Array, amount: float) -> void:
	if e.boss or bool(e.airborne):
		return
	st.move_swept(e, dir[0] * amount, dir[1] * amount)
	if e.state == "dash":
		e.state = "recover"
		e.state_t = 0.0

static func cast_e(st: CombatState) -> bool:
	var p := st.player
	var b := st.build
	var sk = b.skills.get("e")
	if sk == null:
		return false
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	var v: String = String(sk.variant) if sk.get("variant") != null else ""
	var dmg := sdmg(st, "e")
	var S := st.skill_state
	var lv := mini(3, int(sk.level))
	match String(sk.id):
		"gust":
			var ang: float = p.face
			if v == "whirl":
				st.fx({ "kind": "gust", "x": p.x, "y": p.y, "r": 130.0, "whirl": true, "ttl": 0.3 })
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, p.x, p.y) <= 130.0 + e.r:
						hit(st, e, dmg)
						push_enemy(st, e, PGeom.norm(e.x - p.x, e.y - p.y), 140.0 + 30.0 * float(lv - 1))
			else:
				st.fx({ "kind": "gust", "x": p.x, "y": p.y, "angle": ang, "len": 170.0, "w": 120.0, "ttl": 0.3 })
				for e in st.alive_targets():
					if PGeom.in_beam(p.x, p.y, ang, 170.0, 120.0, e.x, e.y, e.r) and not st.los_blocked(p.x, p.y, e.x, e.y):
						hit(st, e, dmg)
						push_enemy(st, e, [cos(ang), sin(ang)], 140.0 + 30.0 * float(lv - 1))
			if v == "windpath":
				for i in 3:
					var pos := st.nearest_valid_pos(p.x + cos(ang) * 55.0 * float(i), p.y + sin(ang) * 55.0 * float(i), 0.0, 60.0)
					if not pos.is_empty():
						st.add_zone("windpath", pos[0], pos[1], 40.0, 3.0, 0.0)
		"bladestorm":
			S.storm = { "x": p.x, "y": p.y, "t": 1.2, "tick": 0.0, "r": 70.0 if v == "condensed" else 110.0, "dmg": dmg * (1.8 if v == "condensed" else 1.0), "advancing": v == "advancing", "dir": [cos(p.face), sin(p.face)] }
		"strike":
			var tg := auto_target(st, 260.0)
			if tg.is_empty():
				return false
			var at := { "x": tg.x, "y": tg.y }
			st.fx({ "kind": "strikewarn", "x": at.x, "y": at.y, "r": 45.0, "ttl": 0.25 })
			st.text(at.x, at.y - 30.0, "낙뢰", "#fff3a0")
			st.delayed.append({ "t": 0.25, "fn": func():
				bolt_at(st, at, 45.0, dmg)
				if v == "chain":
					var others := []
					for e in st.alive_targets():
						var dd := PGeom.dist(e.x, e.y, at.x, at.y)
						if dd <= 150.0 and dd > 20.0 and others.size() < 2:
							others.append(e)
					for o in others:
						var oa := { "x": o.x, "y": o.y }
						st.delayed.append({ "t": 0.15, "fn": func(): bolt_at(st, oa, 40.0, dmg * 0.5) })
				if v == "storm":
					var z := st.add_zone("storm", at.x, at.y, 50.0, 2.0, dmg * 0.3)
					z.tick = 0.5 })
		"gravity":
			var c := cluster(st, 260.0)
			if c.is_empty():
				return false
			S.gravity = { "x": c.x, "y": c.y, "t": 1.2, "hold": 1.0 if v == "orbit" else 0.0, "r": 140.0, "pull": 90.0 * float(d.pull[lv - 1]), "dps": dmg, "tick": 0.0, "collapse": v == "collapse", "dmg": dmg }
		"ward":
			var amt := float(d.shield[lv - 1])
			S.ward = { "t": 4.0, "amt": amt, "fortress": v == "fortress", "pulse": v == "pulse", "pulse_t": 0.0 }
			p.ward_shield = float(p.ward_shield) + amt
			p.shield += amt
			p.shield_max = maxf(p.shield_max, p.shield)
			st.fx({ "kind": "burst", "x": p.x, "y": p.y, "r": 40.0, "ttl": 0.3, "color": "#7ef2ff" })
	p.e_cd = cd_of(st, "e")
	st.stats.e_uses += 1
	var EQ: Dictionary = b.equip
	if EQ.has("eShield") and st.caster_cd <= 0.0:
		st.caster_cd = float(EQ.eShield.cd)
		var prev: float = float(st.caster_shield.amt) if not st.caster_shield.is_empty() else 0.0
		p.shield = p.shield - prev + float(EQ.eShield.shield)
		st.caster_shield = { "amt": float(EQ.eShield.shield), "t": float(EQ.eShield.dur) }
		p.shield_max = maxf(p.shield_max, p.shield)
		st.stats.equip_procs.caster_shield = int(st.stats.equip_procs.get("caster_shield", 0)) + 1
	st.ev("skill_e", { "id": String(sk.id) })
	st.text(p.x, p.y - 62.0, String(d.name), "#ffe9a8")
	if (b.boss_rewards as Array).has("volley"):
		PWeapons.volley(st)
	return true

static func bolt_at(st: CombatState, at: Dictionary, r: float, dmg: float) -> void:
	st.fx({ "kind": "strike", "x": at.x, "y": at.y, "r": r, "ttl": 0.3 })
	for e in st.alive_targets():
		if PGeom.dist(e.x, e.y, at.x, at.y) <= r + e.r:
			hit(st, e, dmg)
	st.ev("explode")

static func update(st: CombatState, dt: float) -> void:
	var p := st.player
	var S := st.skill_state
	if S.is_empty():
		return
	if p.e_cd > 0.0:
		p.e_cd = maxf(0.0, p.e_cd - dt)
	if not st.field.is_empty() and bool(st.field.get("follow", false)):
		st.field.x = p.x
		st.field.y = p.y
	var f2: Dictionary = S.get("field2", {})
	if not f2.is_empty():
		f2.ttl = float(f2.ttl) - dt
		if float(f2.ttl) <= 0.0:
			S.field2 = {}
	var sk = st.build.skills.get("e")
	if sk != null and (String(sk.id) == "strike" or String(sk.id) == "gravity") and p.e_cd <= 0.0:
		var tg: Dictionary = auto_target(st, 260.0) if String(sk.id) == "strike" else cluster(st, 260.0)
		S.target = { "x": tg.x, "y": tg.y } if not tg.is_empty() else null
	else:
		S.target = null
	var storm: Dictionary = S.get("storm", {})
	if not storm.is_empty():
		storm.t = float(storm.t) - dt
		if bool(storm.advancing):
			storm.x += storm.dir[0] * 150.0 * dt
			storm.y += storm.dir[1] * 150.0 * dt
		else:
			storm.x = p.x
			storm.y = p.y
		storm.tick = float(storm.tick) - dt
		if float(storm.tick) <= 0.0:
			storm.tick = 0.2
			for e in st.alive_targets():
				if PGeom.dist(e.x, e.y, storm.x, storm.y) <= float(storm.r) + e.r:
					hit(st, e, float(storm.dmg), { "dir": PGeom.norm(e.x - storm.x, e.y - storm.y), "knock": 8.0 })
		if float(storm.t) <= 0.0:
			S.storm = {}
	var g: Dictionary = S.get("gravity", {})
	if not g.is_empty():
		g.t = float(g.t) - dt
		var active: bool = float(g.t) > -float(g.hold)
		for e in st.alive_targets():
			if e.boss or bool(e.airborne):
				continue
			var dd := PGeom.dist(e.x, e.y, g.x, g.y)
			if dd <= float(g.r) + e.r and dd > 8.0:
				var n := PGeom.norm(g.x - e.x, g.y - e.y)
				st.move_swept(e, n[0] * float(g.pull) * dt, n[1] * float(g.pull) * dt)
		g.tick = float(g.tick) - dt
		if float(g.tick) <= 0.0 and float(g.t) > 0.0:
			g.tick = 0.25
			for e in st.alive_targets():
				if PGeom.dist(e.x, e.y, g.x, g.y) <= float(g.r) + e.r:
					hit(st, e, float(g.dps) * 0.25)
		if not active:
			if bool(g.collapse):
				st.fx({ "kind": "burst", "x": g.x, "y": g.y, "r": 100.0, "ttl": 0.35, "color": "#c9a0ff" })
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, g.x, g.y) <= 100.0 + e.r:
						hit(st, e, float(g.dmg) * 3.0, { "dir": PGeom.norm(e.x - g.x, e.y - g.y), "knock": 60.0 })
				st.ev("explode")
			S.gravity = {}
	var w: Dictionary = S.get("ward", {})
	if not w.is_empty():
		w.t = float(w.t) - dt
		if bool(w.fortress):
			for e in st.alive_targets():
				if PGeom.dist(e.x, e.y, p.x, p.y) <= 60.0 + e.r:
					push_enemy(st, e, PGeom.norm(e.x - p.x, e.y - p.y), 30.0 * dt)
		if bool(w.pulse):
			w.pulse_t = float(w.pulse_t) - dt
			if float(w.pulse_t) <= 0.0:
				w.pulse_t = 0.8
				st.fx({ "kind": "spin", "x": p.x, "y": p.y, "r": 110.0, "ttl": 0.2 })
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, p.x, p.y) <= 110.0 + e.r and not st.los_blocked(p.x, p.y, e.x, e.y):
						hit(st, e, 8.0, { "dir": PGeom.norm(e.x - p.x, e.y - p.y), "knock": 10.0 })
		if float(w.t) <= 0.0:
			var rest := minf(p.shield, float(p.ward_shield))
			p.shield -= rest
			p.ward_shield = 0.0
			S.ward = {}

## 결계 보호막이 피해로 줄면 잔여량 추적
static func on_shield_damaged(st: CombatState, used: float) -> void:
	var p := st.player
	if float(p.ward_shield) > 0.0:
		p.ward_shield = maxf(0.0, float(p.ward_shield) - used)
