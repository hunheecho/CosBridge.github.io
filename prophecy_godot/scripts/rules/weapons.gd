class_name PWeapons
extends RefCounted
## 자동기술 엔진(HTML weapons.js 이식): 장착 자동기술 최대 3개가 각자 주기로 자동 공격한다. 피해 출처(무기·레벨·직접/추가)를 추적해 공용 효과가 정확히 한 번씩 적용되게 한다.
## 판정 범주: direct(장애물 가림) / projectile(장애물 충돌) / ground(바닥 범위). 검격 타이밍은 godot-0.3.1(첫 공격 0.25, 음수 잔여 이월, 대상 없으면 0.05)과 같다.

static func init(st: CombatState) -> Array:
	var list := []
	var i := 0
	for s in st.build.weapons:
		list.append({ "stats": s, "id": String(s.id), "timer": 0.25 + float(i) * 0.2, "count": 0, "orbit": 0.0, "launch_t": 0.0, "last_hit": {}, "echo": {}, "blade_pos": [] })
		i += 1
	return list

## 전투 중 성장 반영: 타이머·상태 유지, 수치만 갱신, 새 무기 추가
static func refresh(st: CombatState) -> void:
	var old: Array = st.weapons
	var out := []
	for s in st.build.weapons:
		var prev := {}
		for w in old:
			if String(w.id) == String(s.id):
				prev = w
		if not prev.is_empty():
			prev.stats = s
			out.append(prev)
		else:
			out.append({ "stats": s, "id": String(s.id), "timer": 0.3, "count": 0, "orbit": 0.0, "launch_t": 0.0, "last_hit": {}, "echo": {}, "blade_pos": [] })
	st.weapons = out

# ---------- 공통 ----------
static func src(w: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var s := { "weapon": w.stats, "weapon_id": String(w.id), "level": int(w.stats.level), "direct": true }
	for k in extra:
		s[k] = extra[k]
	return s

static func reachable(st: CombatState, fx0: float, fy0: float, e: Dictionary) -> bool:
	return not st.los_blocked(fx0, fy0, e.x, e.y)

## 대상: 표식 우선(사거리 안·가림 없음) → 가장 가까운 가림 없는 적
static func pick_target(st: CombatState, w: Dictionary, range_v: float, need_los: bool) -> Dictionary:
	var p := st.player
	var mk = st.mark_target
	if mk != null and not mk.dead and not bool(mk.get("hidden", false)) and PGeom.dist(p.x, p.y, mk.x, mk.y) <= range_v + mk.r and (not need_los or reachable(st, p.x, p.y, mk)):
		return mk
	var best := {}
	var bd := INF
	for e in st.alive_targets():
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d > range_v + e.r:
			continue
		if need_los and not reachable(st, p.x, p.y, e):
			continue
		if d < bd:
			bd = d
			best = e
	return best

static func dmg_to(st: CombatState, e: Dictionary, w: Dictionary, mult: float, opt: Dictionary) -> float:
	st.metrics.hits[w.id] = int(st.metrics.hits.get(w.id, 0)) + 1
	st.stats.hits += 1
	var o := opt.duplicate()
	o.src = src(w, opt.get("src_extra", {}))
	if opt.has("direct"):
		o.src.direct = bool(opt.direct)
	if opt.has("mod") and String(opt.mod) != "":
		o.src["mod"] = String(opt.mod) # 개조 귀속(계측 전용)
	return st.damage_enemy(e, float(w.stats.damage) * mult, o)

## 원형 범위 직접 공격(가림 적용, ground면 무시)
static func hit_circle(st: CombatState, w: Dictionary, cx: float, cy: float, r: float, mult: float, opt: Dictionary) -> int:
	var n := 0
	for e in st.alive_targets():
		if PGeom.dist(cx, cy, e.x, e.y) <= r + e.r and (bool(opt.get("ground", false)) or reachable(st, cx, cy, e)):
			var o := opt.duplicate()
			o.dir = PGeom.norm(e.x - cx, e.y - cy)
			o["from"] = { "x": cx, "y": cy }
			dmg_to(st, e, w, mult, o)
			n += 1
	return n

static func hit_arc(st: CombatState, w: Dictionary, fx0: float, fy0: float, angle: float, R: float, half: float, mult: float, opt: Dictionary) -> int:
	var n := 0
	for e in st.alive_targets():
		if PGeom.in_arc(fx0, fy0, R, angle, half, e.x, e.y, e.r) and reachable(st, fx0, fy0, e):
			var o := opt.duplicate()
			o.dir = PGeom.norm(e.x - fx0, e.y - fy0)
			o.knock = float(w.stats.knock)
			o["from"] = { "x": fx0, "y": fy0 }
			dmg_to(st, e, w, mult, o)
			n += 1
	return n

static func hit_beam(st: CombatState, w: Dictionary, fx0: float, fy0: float, angle: float, L: float, W: float, mult: float, opt: Dictionary) -> Array:
	var list := []
	for e in st.alive_targets():
		if PGeom.in_beam(fx0, fy0, angle, L, W, e.x, e.y, e.r) and reachable(st, fx0, fy0, e):
			list.append(e)
	list.sort_custom(func(a, b): return PGeom.dist(fx0, fy0, a.x, a.y) < PGeom.dist(fx0, fy0, b.x, b.y))
	var s: Dictionary = w.stats
	var hit := []
	var n := 0
	for e in list:
		if s.has("maxTargets") and n >= int(s.maxTargets):
			break
		var mm := mult
		if s.has("sweetFrom") and PGeom.dist(fx0, fy0, e.x, e.y) < L * float(s.sweetFrom):
			mm *= float(s.get("sweetMult", 0.5))
		var o := opt.duplicate()
		o.dir = [cos(angle), sin(angle)]
		o.knock = float(s.knock)
		o["from"] = { "x": fx0, "y": fy0 }
		dmg_to(st, e, w, mm, o)
		hit.append(e)
		n += 1
	return hit

static func proj(st: CombatState, w: Dictionary, o: Dictionary) -> Dictionary:
	var pr := { "owner": "player", "weapon": w, "r": 4.0, "ttl": 2.0, "hits": {}, "dmg_mult": 1.0, "opt": {}, "dead": false, "target": null, "boomerang": {}, "pierce": false, "ricochet": 0, "turn": 0.0, "speed": 0.0 }
	for k in o:
		pr[k] = o[k]
	st.projectiles.append(pr)
	return pr

static func later(st: CombatState, t: float, fn: Callable) -> void:
	st.delayed.append({ "t": t, "fn": fn })

# ---------- 무기별 발사 ----------
static func fire(st: CombatState, w: Dictionary, target: Dictionary, echoed: bool) -> void:
	match String(w.stats.kind):
		"arc": fire_arc(st, w, target, echoed)
		"beam": fire_beam(st, w, target, echoed)
		"melee": fire_melee(st, w, target, echoed)
		"homing": fire_homing(st, w, target, echoed)
		"heavy": fire_heavy(st, w, target, echoed)
		"chain": fire_chain(st, w, target, echoed)
		"bolt": fire_bolt(st, w, target, echoed)
		"ember": fire_ember(st, w, target, echoed)

static func fire_arc(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var p := st.player
	var s: Dictionary = w.stats
	var ang := atan2(target.y - p.y, target.x - p.x)
	var half := float(s.arc_deg) * PI / 360.0
	p.face = ang
	p.swing_t = 0.0
	p.swing_form = "arc"
	p.swing_angle = ang
	st.fx({ "kind": "arc", "x": p.x, "y": p.y, "angle": ang, "r": float(s.range), "half": half, "ttl": 0.16 })
	hit_arc(st, w, p.x, p.y, ang, float(s.range), half, 1.0, {})
	var mods: Array = s.mods
	if mods.has("cross") and int(w.count) % 3 == 0:
		var a2 := ang + PI
		st.note_mod("cross", "proc")
		st.fx({ "kind": "arc", "x": p.x, "y": p.y, "angle": a2, "r": float(s.range), "half": half, "ttl": 0.16, "mod": "cross" })
		hit_arc(st, w, p.x, p.y, a2, float(s.range), half, 1.0, { "mod": "cross" })
	if mods.has("crescent"):
		var sx: float = p.x + cos(ang) * float(s.range) * 0.8
		var sy: float = p.y + sin(ang) * float(s.range) * 0.8
		proj(st, w, { "kind": "crescent", "x": sx, "y": sy, "vx": cos(ang) * 420.0, "vy": sin(ang) * 420.0, "r": 16.0, "ttl": 120.0 / 420.0, "pierce": true, "dmg_mult": 0.6, "angle": ang, "opt": { "direct": false } })
	if mods.has("scar"):
		var cx: float = p.x
		var cy: float = p.y
		st.fx({ "kind": "scar_mark", "x": cx, "y": cy, "angle": ang, "r": float(s.range), "half": half, "ttl": 0.5, "mod": "scar" }) # 남는 흔적(무해한 표시) — 후속 피해는 0.5초 뒤
		later(st, 0.5, func():
			st.note_mod("scar", "proc")
			st.fx({ "kind": "scar", "x": cx, "y": cy, "angle": ang, "r": float(s.range), "half": half, "ttl": 0.25, "mod": "scar" })
			hit_arc(st, w, cx, cy, ang, float(s.range), half, 0.5, { "direct": false, "mod": "scar" }))
	st.ev("swing", { "form": "arc" })

static func fire_beam(st: CombatState, w: Dictionary, target: Dictionary, echoed: bool) -> void:
	var p := st.player
	var s: Dictionary = w.stats
	var ang := atan2(target.y - p.y, target.x - p.x)
	var L := st.beam_length(p.x, p.y, ang, float(s.range))
	var W := float(s.width)
	p.face = ang
	p.swing_t = 0.0
	p.swing_form = "beam"
	p.swing_angle = ang
	st.fx({ "kind": "beam", "x": p.x, "y": p.y, "angle": ang, "len": L, "w": W, "ttl": 0.18 })
	var hit := hit_beam(st, w, p.x, p.y, ang, L, W, 1.0, {})
	var mods: Array = s.mods
	if mods.has("brand"):
		for e in hit:
			e.brand = int(e.brand) + 1
			if int(e.brand) >= 4:
				e.brand = 0
				st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": 60.0, "ttl": 0.3, "color": "#ffd166" })
				st.text(e.x, e.y - e.r - 30.0, "표식 폭발!", "#ffd166")
				hit_circle(st, w, e.x, e.y, 60.0, 1.5, { "direct": false })
	if mods.has("split") and hit.size() > 0:
		var h: Dictionary = hit[0]
		st.note_mod("split", "proc")
		st.fx({ "kind": "split_node", "x": h.x, "y": h.y, "angle": ang, "ttl": 0.25, "mod": "split" }) # 첫 명중 지점의 분기 결절(표시 전용, 판정 없음)
		for da in [-0.6, 0.6]:
			proj(st, w, { "kind": "shard", "x": h.x, "y": h.y, "vx": cos(ang + da) * 340.0, "vy": sin(ang + da) * 340.0, "r": 4.0, "ttl": 0.5, "dmg_mult": 0.4, "mod": "split", "opt": { "direct": false, "mod": "split" } })
	if mods.has("returning") and not echoed:
		var fx0: float = p.x
		var fy0: float = p.y
		later(st, 0.35, func():
			var ex: float = fx0 + cos(ang) * L
			var ey: float = fy0 + sin(ang) * L
			st.note_mod("returning", "proc")
			st.fx({ "kind": "beam", "x": ex, "y": ey, "angle": ang + PI, "len": L, "w": W, "ttl": 0.18, "mod": "returning", "returning": true })
			hit_beam(st, w, ex, ey, ang + PI, L, W, 1.0, { "no_mods": true, "mod": "returning" }))
	st.ev("swing", { "form": "beam" })

static func fire_melee(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	var hits: int = int(s.hits)
	var one := func(i: int):
		var tg: Dictionary = pick_target(st, w, float(s.range), true) if target.dead else target
		if tg.is_empty():
			return
		var ang := atan2(tg.y - p.y, tg.x - p.x)
		p.face = ang
		p.swing_t = 0.0
		p.swing_form = "arc"
		p.swing_angle = ang
		var half := float(s.arc_deg) * PI / 360.0
		st.fx({ "kind": "dagger", "x": p.x, "y": p.y, "angle": ang, "r": float(s.range), "half": half, "ttl": 0.12, "side": i })
		if i == hits - 1 and (s.mods as Array).has("flank"):
			for da in [PI / 2.0, -PI / 2.0]:
				st.fx({ "kind": "arc", "x": p.x, "y": p.y, "angle": ang + da, "r": float(s.range) * 1.3, "half": 0.9, "ttl": 0.14 })
				hit_arc(st, w, p.x, p.y, ang + da, float(s.range) * 1.3, 0.9, 1.0, {})
		hit_arc(st, w, p.x, p.y, ang, float(s.range), half, 1.0, { "bleed": 2.0 } if (s.mods as Array).has("bleed") else {})
	one.call(0)
	for i in range(1, hits):
		var idx := i
		later(st, float(s.hit_gap) * float(i), func(): one.call(idx))
	st.ev("swing", { "form": "melee" })

static func fire_homing(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	var ang := atan2(target.y - p.y, target.x - p.x)
	var angles: Array = [ang - 0.35, ang, ang + 0.35] if (s.mods as Array).has("spread") else [ang]
	for a in angles:
		proj(st, w, { "kind": "arrow_h", "x": p.x, "y": p.y, "vx": cos(a) * float(s.speed), "vy": sin(a) * float(s.speed), "r": 5.0, "ttl": (float(s.range) / float(s.speed)) * 1.4, "target": target, "turn": float(s.turn), "speed": float(s.speed), "pierce": (s.mods as Array).has("pierce"), "ricochet": 1 if (s.mods as Array).has("ricochet") else 0, "angle": a })
	p.face = ang
	st.ev("shoot")

static func fire_heavy(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	var d := PGeom.dist(p.x, p.y, target.x, target.y)
	var ang := atan2(target.y - p.y, target.x - p.x)
	var ix: float = p.x + cos(ang) * minf(d, float(s.range))
	var iy: float = p.y + sin(ang) * minf(d, float(s.range))
	p.face = ang
	p.swing_t = 0.0
	p.swing_form = "heavy"
	p.swing_angle = ang
	if (s.mods as Array).has("pull"):
		for e in st.alive_targets():
			if not e.boss and not bool(e.airborne) and PGeom.dist(e.x, e.y, ix, iy) <= 90.0 + e.r:
				var n := PGeom.norm(ix - e.x, iy - e.y)
				st.move_swept(e, n[0] * 30.0, n[1] * 30.0)
	st.fx({ "kind": "impact", "x": ix, "y": iy, "r": float(s.radius), "ttl": 0.3 })
	hit_circle(st, w, ix, iy, float(s.radius), 1.0, { "knock": float(s.knock) })
	if (s.mods as Array).has("shockwave"):
		st.fx({ "kind": "beam", "x": ix, "y": iy, "angle": ang, "len": 160.0, "w": 50.0, "ttl": 0.2 })
		hit_beam(st, w, ix, iy, ang, 160.0, 50.0, 0.6, { "direct": false })
	if (s.mods as Array).has("aftershock"):
		later(st, 0.6, func():
			st.fx({ "kind": "impact", "x": ix, "y": iy, "r": float(s.radius), "ttl": 0.3, "after": true })
			hit_circle(st, w, ix, iy, float(s.radius), 0.5, { "direct": false, "ground": true }))
	st.ev("boss_land")

static func fire_chain(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	var visited := {}
	var pts := [{ "x": p.x, "y": p.y }]
	var zap := func(e: Dictionary, mult: float):
		var from: Dictionary = pts[pts.size() - 1]
		visited[e.id] = true
		pts.append({ "x": e.x, "y": e.y })
		dmg_to(st, e, w, mult, { "knock": 0.0, "from": from })
		if (s.mods as Array).has("conduct"):
			e.conduct = 2.0
	var next := func(from: Dictionary) -> Dictionary:
		var best := {}
		var bd := INF
		for e in st.alive_targets():
			if visited.has(e.id):
				continue
			var d := PGeom.dist(from.x, from.y, e.x, e.y)
			if d <= float(s.hop) + e.r and d < bd and reachable(st, from.x, from.y, e):
				bd = d
				best = e
		return best
	zap.call(target, 1.0)
	var first := target
	if (s.mods as Array).has("fork"):
		var branches := []
		for k in 2:
			var n: Dictionary = next.call(first)
			if not n.is_empty():
				zap.call(n, 1.0)
				branches.append(n)
		for b in branches:
			var cur: Dictionary = b
			for h in range(1, int(ceil(float(s.hops) / 2.0))):
				var n2: Dictionary = next.call(cur)
				if n2.is_empty():
					break
				zap.call(n2, 1.0)
				cur = n2
	else:
		var cur: Dictionary = first
		for h in range(1, int(s.hops)):
			var n3: Dictionary = next.call(cur)
			if n3.is_empty():
				break
			zap.call(n3, 1.0)
			cur = n3
	if (s.mods as Array).has("loop") and not first.dead and visited.size() > 1:
		pts.append({ "x": first.x, "y": first.y })
		dmg_to(st, first, w, 1.0, { "knock": 0.0, "loop": true })
	st.fx({ "kind": "chain", "pts": pts, "ttl": 0.22 })
	st.ev("shoot")

static func fire_bolt(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	var ang := atan2(target.y - p.y, target.x - p.x)
	var has_fan: bool = (s.mods as Array).has("fan")
	var angles: Array = [ang - 0.44, ang, ang + 0.44] if has_fan else [ang]
	if has_fan:
		st.note_mod("fan", "proc") # 부채: 가운데는 기본 발사, 양옆 2발이 개조의 기여분
	for a in angles:
		var side: bool = has_fan and absf(a - ang) > 1e-6
		proj(st, w, { "kind": "bolt", "x": p.x, "y": p.y, "vx": cos(a) * float(s.speed), "vy": sin(a) * float(s.speed), "r": 5.0, "ttl": float(s.range) / float(s.speed), "chill": float(s.chill), "angle": a, "mod": ("fan" if side else ""), "shatter": (s.mods as Array).has("shatter"), "ground": (s.mods as Array).has("ground") })
	st.ev("shoot")

static func fire_ember(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> void:
	var s: Dictionary = w.stats
	var tx: float = target.x + st.rng.range_f(-20.0, 20.0)
	var ty: float = target.y + st.rng.range_f(-20.0, 20.0)
	var zones_l: Array = [[tx, ty, float(s.radius)]]
	if (s.mods as Array).has("scatter"):
		zones_l = [[tx, ty, float(s.radius) * 0.7], [tx + 40.0, ty - 30.0, float(s.radius) * 0.7], [tx - 40.0, ty + 30.0, float(s.radius) * 0.7]]
	if (s.mods as Array).has("trail"):
		var ang := atan2(ty - st.player.y, tx - st.player.x)
		for i in [1, 2]:
			zones_l.append([tx - cos(ang) * 40.0 * float(i), ty - sin(ang) * 40.0 * float(i), float(s.radius) * 0.8])
	st.fx({ "kind": "emberthrow", "x0": st.player.x, "y0": st.player.y, "x": tx, "y": ty, "ttl": 0.3 })
	var dm: float = float(st.build.duration_mult) * float(st.build.get("trait_dot_dur", 1.0)) # 특성 '지속 전문화': 불길 지속시간(없으면 ×1.0)
	later(st, 0.3, func():
		for zz in zones_l:
			var pos := st.nearest_valid_pos(zz[0], zz[1], 0.0, 60.0)
			if pos.is_empty():
				continue
			var z := st.add_zone("fire", pos[0], pos[1], zz[2], float(s.ttl) * dm, float(s.damage))
			z.weapon = w
			z.extended = 0.0)
	st.ev("shoot")

static func fire_mine(st: CombatState, w: Dictionary) -> bool:
	var s: Dictionary = w.stats
	var p := st.player
	var n := 0
	for mn in st.mines:
		if mn.weapon == w:
			n += 1
	if n >= int(s.max):
		return false
	var pos := st.nearest_valid_pos(p.x, p.y, 8.0, 40.0)
	if pos.is_empty():
		return false
	st.mines.append({ "weapon": w, "x": pos[0], "y": pos[1], "r": float(s.trigger), "arm": float(s.arm), "t": 0.0, "dead": false })
	return true

# ---------- 갱신 ----------
static func update(st: CombatState, dt: float) -> void:
	var p := st.player
	var b := st.build
	if st.delayed.size() > 0:
		var keep := []
		for d in st.delayed:
			d.t = float(d.t) - dt
			if float(d.t) <= 0.0:
				(d.fn as Callable).call()
			else:
				keep.append(d)
		st.delayed = keep
	if float(st.player.get("attack_timer", 0.0)) >= 1.0e8:
		return # 테스트·시연 훅(첫 전투 호환): player.attack_timer를 아주 크게 두면 자동기술을 끈다
	var CV: Dictionary = PCatalog.growth().COMMON_VALUES
	for w in st.weapons:
		var s: Dictionary = w.stats
		if String(s.kind) == "orbit":
			update_orbit(st, w, dt)
			continue
		if not (w.echo as Dictionary).is_empty():
			w.echo.t = float(w.echo.t) - dt
			if float(w.echo.t) <= 0.0:
				var e: Dictionary = w.echo
				w.echo = {}
				if not e.target.dead:
					fire(st, w, e.target, true)
				st.text(p.x, p.y - 40.0, "메아리", "#dcd6ff")
		w.timer = float(w.timer) - dt
		if float(w.timer) > 0.0:
			continue
		if String(s.kind) == "mine":
			if fire_mine(st, w):
				w.timer = maxf(-float(s.interval) * 0.5, float(w.timer)) + float(s.interval)
				w.count = int(w.count) + 1
			else:
				w.timer = 0.2
			continue
		var target: Dictionary = pick_ember_target(st, w) if String(s.kind) == "ember" else pick_target(st, w, float(s.range), true)
		if target.is_empty():
			w.timer = 0.05
			continue
		w.timer = maxf(-float(s.interval) * 0.5, float(w.timer)) + float(s.interval)
		w.count = int(w.count) + 1
		fire(st, w, target, false)
		if PBuild.has_common(b, "echo") and int(w.count) % int(CV.echoEvery) == 0:
			w.echo = { "t": float(CV.echoDelay), "target": target }
	update_mines(st, dt)

static func pick_ember_target(st: CombatState, w: Dictionary) -> Dictionary:
	var p := st.player
	var list := []
	for e in st.alive_targets():
		if PGeom.dist(p.x, p.y, e.x, e.y) <= float(w.stats.range):
			list.append(e)
	if list.is_empty():
		return {}
	return list[int(floor(st.rng.next() * float(list.size())))]

static func update_orbit(st: CombatState, w: Dictionary, dt: float) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	w.orbit = float(w.orbit) + float(s.angular) * dt
	var BS := PCatalog.blade_spoke()
	var count: int = int(s.count) + (1 if (s.mods as Array).has("dual") else 0)
	var R := float(s.radius)
	var inner: float = R * float(BS.innerFrac)
	w.blade_pos = []
	for i in count:
		var a: float = float(w.orbit) + float(i) * TAU / float(count)
		w.blade_pos.append({ "x": p.x + cos(a) * R, "y": p.y + sin(a) * R, "a": a, "ix": p.x + cos(a) * inner, "iy": p.y + sin(a) * inner })
	var CV: Dictionary = PCatalog.growth().COMMON_VALUES
	for bp in w.blade_pos:
		for e in st.alive_targets():
			if PGeom.dist_seg(e.x, e.y, bp.ix, bp.iy, bp.x, bp.y) > float(BS.hitR) + e.r:
				continue
			var last: float = float(w.last_hit.get(e.id, -9.0))
			if st.t - last < float(s.hit_gap):
				continue
			if not reachable(st, p.x, p.y, e):
				continue
			w.last_hit[e.id] = st.t
			w.count = int(w.count) + 1
			var o := { "dir": PGeom.norm(e.x - p.x, e.y - p.y), "knock": float(s.knock), "from": { "x": bp.x, "y": bp.y } }
			if (s.mods as Array).has("serrated"):
				o.bleed = 1.5
			dmg_to(st, e, w, 1.0, o)
			if PBuild.has_common(st.build, "echo") and int(w.count) % int(CV.echoEvery) == 0:
				var ee: Dictionary = e
				later(st, float(CV.echoDelay), func():
					if not ee.dead:
						dmg_to(st, ee, w, 1.0, { "direct": true, "no_echo": true }))
	if (s.mods as Array).has("launch"):
		w.launch_t = float(w.launch_t) + dt
		if float(w.launch_t) >= 3.0:
			var tg := pick_target(st, w, 240.0, true)
			if not tg.is_empty():
				w.launch_t = 0.0
				proj(st, w, { "kind": "blade", "x": p.x, "y": p.y, "vx": 0.0, "vy": 0.0, "r": 12.0, "ttl": 3.0, "boomerang": { "tx": tg.x, "ty": tg.y, "phase": 0, "speed": 520.0 }, "pierce": true, "dmg_mult": 1.2 })

static func update_mines(st: CombatState, dt: float) -> void:
	for mn in st.mines:
		if bool(mn.dead):
			continue
		mn.t = float(mn.t) + dt
		if float(mn.arm) > 0.0:
			mn.arm = float(mn.arm) - dt
			continue
		var s: Dictionary = mn.weapon.stats
		if (s.mods as Array).has("lure"):
			for e in st.alive_targets():
				if not e.boss and not bool(e.airborne):
					var dd := PGeom.dist(e.x, e.y, mn.x, mn.y)
					if dd <= 70.0 + e.r and dd > float(mn.r):
						var n := PGeom.norm(mn.x - e.x, mn.y - e.y)
						st.move_swept(e, n[0] * 40.0 * dt, n[1] * 40.0 * dt)
		for e in st.alive_targets():
			if not bool(e.airborne) and PGeom.dist(e.x, e.y, mn.x, mn.y) <= float(mn.r) + e.r:
				explode_mine(st, mn)
				break
	var keep := []
	for mn in st.mines:
		if not bool(mn.dead):
			keep.append(mn)
	st.mines = keep

static func explode_mine(st: CombatState, mn: Dictionary) -> void:
	if bool(mn.dead):
		return
	mn.dead = true
	var w: Dictionary = mn.weapon
	var s: Dictionary = w.stats
	st.fx({ "kind": "mineburst", "x": mn.x, "y": mn.y, "r": float(s.radius), "ttl": 0.35 })
	var o := { "ground": true, "knock": 30.0 }
	if (s.mods as Array).has("frosttrap"):
		o.chill = 2.0
	hit_circle(st, w, mn.x, mn.y, float(s.radius), 1.0, o)
	if (s.mods as Array).has("chain"):
		for other in st.mines:
			if not bool(other.dead) and other != mn and PGeom.dist(other.x, other.y, mn.x, mn.y) <= 90.0:
				var oo: Dictionary = other
				later(st, 0.15, func(): explode_mine(st, oo))
	st.ev("explode")

# ---------- 투사체 적중(combat.update_projectiles에서 호출). true면 투사체 소멸 ----------
static func on_projectile_hit(st: CombatState, pr: Dictionary, e: Dictionary) -> bool:
	if (pr.hits as Dictionary).has(e.id):
		return false
	pr.hits[e.id] = true
	var opt := { "dir": PGeom.norm(pr.vx, pr.vy), "knock": 10.0, "from": { "x": pr.x, "y": pr.y } }
	for k in pr.get("opt", {}):
		opt[k] = pr.opt[k]
	if String(pr.get("mod", "")) != "" and not opt.has("mod"):
		opt["mod"] = String(pr.mod) # 개조가 만든 투사체의 적중·피해를 그 개조에 귀속(출처 행은 그대로)
	if pr.has("chill") and float(pr.chill) > 0.0:
		opt.chill = float(pr.chill)
	if pr.kind == "shard_common":
		st.damage_enemy(e, float(pr.dmg), { "dir": opt.dir, "knock": 10.0, "src": { "extra": true, "direct": false, "tag": String(pr.get("tag", "common:frost")) } })
		return true
	var w: Dictionary = pr.weapon
	dmg_to(st, e, w, float(pr.dmg_mult), opt)
	if pr.kind == "bolt":
		if bool(pr.get("shatter", false)):
			st.note_mod("shatter", "proc")
			st.fx({ "kind": "shatter_burst", "x": e.x, "y": e.y, "ttl": 0.25, "mod": "shatter" }) # 파열 순간(표시 전용, 판정은 파편)
			for i in 3:
				var a := atan2(pr.vy, pr.vx) + float(i - 1) * 0.7
				proj(st, w, { "kind": "shard", "x": e.x, "y": e.y, "vx": cos(a) * 300.0, "vy": sin(a) * 300.0, "r": 3.0, "ttl": 0.4, "dmg_mult": 0.4, "mod": "shatter", "opt": { "direct": false, "mod": "shatter" }, "hits": { e.id: true } })
		if bool(pr.get("ground", false)):
			var z := st.add_zone("coldground", e.x, e.y, 40.0, 2.0 * float(st.build.duration_mult), 0.0)
			z.weapon = w
		return true
	if pr.kind == "arrow_h" and int(pr.ricochet) > 0:
		pr.ricochet = int(pr.ricochet) - 1
		var best := {}
		var bd := INF
		for o in st.alive_targets():
			if o == e or (pr.hits as Dictionary).has(o.id):
				continue
			var d := PGeom.dist(e.x, e.y, o.x, o.y)
			if d <= 160.0 and d < bd:
				bd = d
				best = o
		if not best.is_empty():
			pr.target = best
			pr.dmg_mult = float(pr.dmg_mult) * 0.7
			var a2 := atan2(best.y - pr.y, best.x - pr.x)
			pr.vx = cos(a2) * float(pr.speed)
			pr.vy = sin(a2) * float(pr.speed)
			return false
	return not bool(pr.pierce)

## 투사체 이동 보정(추적·부메랑)
static func steer_projectile(st: CombatState, pr: Dictionary, dt: float) -> void:
	if pr.get("target") != null and float(pr.get("turn", 0.0)) > 0.0:
		if pr.target.dead:
			pr.target = null
			return
		var want := atan2(pr.target.y - pr.y, pr.target.x - pr.x)
		var cur := atan2(pr.vy, pr.vx)
		var d := PGeom.ang_diff(cur, want)
		var a := cur + maxf(-float(pr.turn) * dt, minf(float(pr.turn) * dt, d))
		pr.vx = cos(a) * float(pr.speed)
		pr.vy = sin(a) * float(pr.speed)
	var bm: Dictionary = pr.get("boomerang", {})
	if not bm.is_empty():
		var p := st.player
		var gx: float = float(bm.tx) if int(bm.phase) == 0 else p.x
		var gy: float = float(bm.ty) if int(bm.phase) == 0 else p.y
		var a := atan2(gy - pr.y, gx - pr.x)
		pr.vx = cos(a) * float(bm.speed)
		pr.vy = sin(a) * float(bm.speed)
		if PGeom.dist(pr.x, pr.y, gx, gy) < 18.0:
			if int(bm.phase) == 0:
				bm.phase = 1
				pr.hits = {}
			else:
				pr.dead = true

# ---------- 적중·처치 훅(combat.damage_enemy / kill_enemy에서 호출) ----------
static func on_hit(st: CombatState, e: Dictionary, opt: Dictionary, _dmg: float) -> void:
	var sr: Dictionary = opt.get("src", {})
	var b := st.build
	if bool(sr.get("direct", true)) and sr.has("weapon_id"):
		# 전도 표식: 번개 외 무기의 직접 공격이 표식 적을 치면 작은 전기 폭발(구체 피해의 40%)
		if float(e.conduct) > 0.0 and String(sr.weapon_id) != "orb" and not bool(opt.get("no_conduct", false)):
			var orb := {}
			for w in st.weapons:
				if String(w.id) == "orb":
					orb = w
			if not orb.is_empty():
				e.conduct = 0.0
				st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": 50.0, "ttl": 0.25, "color": "#bfe8ff" })
				for o in st.alive_targets():
					if PGeom.dist(o.x, o.y, e.x, e.y) <= 50.0 + o.r:
						st.damage_enemy(o, float(orb.stats.damage) * 0.4, { "src": src(orb, { "direct": false }), "no_conduct": true })
		# 무기 공명(보스 보상): 서로 다른 무기 3종이 4초 안에 같은 적 → 폭발(적당 6초 간격)
		if (b.boss_rewards as Array).has("resonance"):
			e.resonance[String(sr.weapon_id)] = st.t
			var recent := 0
			for k in e.resonance:
				if st.t - float(e.resonance[k]) <= 4.0:
					recent += 1
			if recent >= 3 and st.t - float(e.resonance_t) >= 6.0:
				e.resonance_t = st.t
				e.resonance = {}
				st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": 70.0, "ttl": 0.35, "color": "#ffe066" })
				st.text(e.x, e.y - e.r - 34.0, "무기 공명!", "#ffe066")
				for o in st.alive_targets():
					if PGeom.dist(o.x, o.y, e.x, e.y) <= 70.0 + o.r:
						st.damage_enemy(o, 40.0 * float(b.mastery_mult), { "src": { "extra": true, "direct": false, "tag": "reward:resonance" }, "no_conduct": true })

static func on_kill(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	var sr: Dictionary = opt.get("src", {})
	var b := st.build
	if String(sr.get("weapon_id", "")) == "daggers":
		for w in st.weapons:
			if String(w.id) == "daggers" and (w.stats.mods as Array).has("pursuit"):
				var best := {}
				var bd := INF
				for o in st.alive_targets():
					var d := PGeom.dist(e.x, e.y, o.x, o.y)
					if d <= 200.0 and d < bd:
						bd = d
						best = o
				if not best.is_empty():
					var a := atan2(best.y - e.y, best.x - e.x)
					proj(st, w, { "kind": "blade", "x": e.x, "y": e.y, "vx": cos(a) * 480.0, "vy": sin(a) * 480.0, "r": 6.0, "ttl": 0.6, "dmg_mult": 0.8, "opt": { "direct": false } })
	for w in st.weapons:
		if String(w.id) == "ember" and (w.stats.mods as Array).has("reignite"):
			for z in st.zones:
				if z.type == "fire" and z.get("weapon") == w and PGeom.dist(z.x, z.y, e.x, e.y) <= z.r + e.r and float(z.get("extended", 0.0)) < 4.5:
					z.ttl += 1.5
					z.extended = float(z.get("extended", 0.0)) + 1.5
	if (b.boss_rewards as Array).has("seed"):
		for o in st.alive_targets():
			if PGeom.dist(o.x, o.y, e.x, e.y) <= 90.0 + o.r:
				if float(e.chill) > 0.0:
					o.chill = maxf(float(o.chill), float(e.chill) / 2.0)
				if not e.burn.is_empty() and float(e.burn.t) > 0.0:
					if o.burn.is_empty() or float(o.burn.t) < float(e.burn.t) / 2.0:
						o.burn = { "t": float(e.burn.t) / 2.0, "dps": float(e.burn.dps), "tick": 0.0, "src": String(e.burn.get("src", "common")) }
				if not e.bleed.is_empty() and float(e.bleed.t) > 0.0:
					if o.bleed.is_empty() or float(o.bleed.t) < float(e.bleed.t) / 2.0:
						o.bleed = { "t": float(e.bleed.t) / 2.0, "dps": float(e.bleed.dps), "tick": 0.0, "src": String(e.bleed.get("src", "weapon")) }

## 일제 공격(보스 보상): E 사용 시 장착 무기 즉시 1회(공전·지뢰 제외)
static func volley(st: CombatState) -> void:
	for w in st.weapons:
		var s: Dictionary = w.stats
		if String(s.kind) == "orbit" or String(s.kind) == "mine":
			continue
		var tg: Dictionary = pick_ember_target(st, w) if String(s.kind) == "ember" else pick_target(st, w, float(s.range), true)
		if not tg.is_empty():
			w.count = int(w.count) + 1
			fire(st, w, tg, true)
