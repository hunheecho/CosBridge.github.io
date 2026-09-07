class_name PObjectives
extends RefCounted
## 전투 목표 4종(정예 추적·제단 파괴·봉인 해제·포로 구출) 진행 규칙(HTML objectives.js 이식). CombatState._init/step에서 호출된다.
## 구조물(제단)은 적 목록(structure)에, 우리·봉인 지점·출구·포로는 st.objects에 둔다. 사람·봇 공용(입력과 무관).
## st.obj(Dictionary) 키: type, risk(""=없음), done, done_t(-1=미완), target_text, reinforce{budget,cap,interval,timer,pool[],spawned}({}=없음)
##  hunt: elite({}=없음), elite_total, elite_killed, reinforce_fired / altars: altars[적 dict] / seal: points[{x,y}], stage, stages, progress, total, paused, hit_pause, move_warn_t
##  rescue: cages, freed, active({}=없음) / 위험 지형: terrain{timer,interval,warn,ttl,r,dmg,lanes}
## st.objects 항목: {kind:"seal", x,y,r,active,moving,next{}} · {kind:"cage", x,y,r,progress,total,freed,id} · {kind:"exit", x,y,r,open} · {kind:"prisoner", x,y,r,id,gone,steer_side,steer_t}
## 지점은 {x, y} 사전으로 다룬다(place/edge_exit의 others도 {x, y} 사전 배열. [x, y] 배열도 받아준다).

static func is_objective(id: String) -> bool:
	return PCatalog.objectives().has(id)

static func spec(st: CombatState) -> Dictionary:
	return PCatalog.objectives().get(st.objective, {})

static func _xy(o) -> Array:
	if typeof(o) == TYPE_ARRAY:
		return [float(o[0]), float(o[1])]
	return [float(o.x), float(o.y)]

# ---------- 배치(지형 검사): 장애물 밖·플레이어에서 떨어진 곳·서로 떨어진 곳 ----------
## others: {x, y} 사전(또는 [x, y]) 배열. 반환 {x, y}
static func place(st: CombatState, r: float, min_gap: float, min_player_gap: float, others: Array, tries: int = 40) -> Dictionary:
	var pad := 70.0
	var best: Dictionary = {}
	var best_score := -1.0
	for i in tries:
		var x: float = st.rng.range_f(pad, st.arena_w - pad)
		var y: float = st.rng.range_f(pad, st.arena_h - pad)
		var vp := st.nearest_valid_pos(x, y, r + 6.0, 80.0)
		if vp.is_empty():
			continue
		var dp := PGeom.dist(vp[0], vp[1], st.player.x, st.player.y)
		if dp < min_player_gap:
			continue
		var ok := true
		var min_d := INF
		for o in others:
			var oxy := _xy(o)
			var d := PGeom.dist(vp[0], vp[1], oxy[0], oxy[1])
			if d < min_gap:
				ok = false
				break
			if d < min_d:
				min_d = d
		if not ok:
			continue
		var score := minf(min_d, dp)
		if score > best_score:
			best_score = score
			best = { "x": vp[0], "y": vp[1] }
		if others.is_empty():
			break
	if best.is_empty(): # 조건을 만족하는 위치가 없으면 조건을 완화(무한 대기 방지): 유효 위치만 보장
		var i := 0
		while i < 60 and best.is_empty():
			var vp2 := st.nearest_valid_pos(st.rng.range_f(pad, st.arena_w - pad), st.rng.range_f(pad, st.arena_h - pad), r + 6.0, 120.0)
			if not vp2.is_empty() and PGeom.dist(vp2[0], vp2[1], st.player.x, st.player.y) >= r + 60.0:
				best = { "x": vp2[0], "y": vp2[1] }
			i += 1
	if best.is_empty():
		best = { "x": st.arena_w / 2.0, "y": 80.0 }
	return best

## 출구: 플레이어·우리에서 가장 먼 가장자리 지점(유효 위치). away: {x, y} 배열
static func edge_exit(st: CombatState, away: Array) -> Dictionary:
	var w := st.arena_w
	var h := st.arena_h
	var cands: Array = [[60.0, h / 2.0], [w - 60.0, h / 2.0], [w / 2.0, 60.0], [w / 2.0, h - 60.0]]
	var best: Dictionary = {}
	var bs := -1.0
	for c in cands:
		var vp := st.nearest_valid_pos(float(c[0]), float(c[1]), 40.0, 80.0)
		if vp.is_empty():
			continue
		var s := INF
		for o in away:
			var oxy := _xy(o)
			s = minf(s, PGeom.dist(vp[0], vp[1], oxy[0], oxy[1]))
		if s > bs:
			bs = s
			best = { "x": vp[0], "y": vp[1] }
	if best.is_empty():
		best = { "x": w / 2.0, "y": 60.0 }
	return best

# ---------- 지원병(유한 예산·동시 상한) ----------
static func make_reinforce(cfg: Dictionary, pool: Array) -> Dictionary:
	if cfg.is_empty():
		return {}
	return { "budget": int(cfg.budget), "cap": int(cfg.cap), "interval": float(cfg.interval), "timer": float(cfg.first) if cfg.has("first") else float(cfg.interval), "pool": pool.duplicate(), "spawned": 0 }

static func active_enemies(st: CombatState) -> int:
	return st.alive_units() + st.pending.size()

static func reinforce(st: CombatState, R: Dictionary, dt: float, n: int = 0) -> int:
	if R.is_empty() or int(R.budget) <= 0:
		return 0
	R.timer = float(R.timer) - dt
	if float(R.timer) > 0.0:
		return 0
	R.timer = float(R.interval)
	var k := 0
	var want: int = n if n > 0 else 1
	var pool: Array = R.pool
	while k < want and int(R.budget) > 0 and active_enemies(st) < int(R.cap):
		var type := String(pool[int(R.spawned) % pool.size()])
		st.queue_wave([{ "type": type, "n": 1 }])
		R.budget = int(R.budget) - 1
		R.spawned = int(R.spawned) + 1
		k += 1
	if k > 0:
		st.ev("reinforce", { "n": k })
	return k

## 지역 적 종류(정예 제외). opts.pool이 회차의 지역 목록(PA.Run.regionEnemies 대체). 없으면 늑대
static func pool_for(opts: Dictionary) -> Array:
	var src: Array = opts.get("pool", [])
	var list: Array = []
	for t in src:
		var d := PCatalog.enemy(String(t))
		if not d.is_empty() and not bool(d.get("elite", false)):
			list.append(String(t))
	if list.is_empty():
		return ["wolf"]
	return list

# ---------- 설정 ----------
static func setup(st: CombatState, opts: Dictionary) -> void:
	var S := spec(st)
	if S.is_empty():
		return
	var risk := String(opts.get("risk", ""))
	var pool := pool_for(opts)
	var o: Dictionary = { "type": st.objective, "risk": risk, "done": false, "done_t": -1.0, "target_text": "" }
	st.obj = o
	var waves: Array = []
	if st.objective == "hunt":
		# 웨이브 1: 호위 + 정예. 정예는 처음부터 등장(숨지 않음)
		var escort_type := String(pool[0])
		waves = [[{ "type": escort_type, "n": int(S.escortN) }, { "type": String(S.eliteType), "n": 1 }]]
		o.reinforce = make_reinforce(S.reinforce, pool)
		o.reinforce.timer = 0.0
		o.reinforce_fired = false
		o.elite = {}
		o.elite_total = 0
		o.elite_killed = 0
	elif st.objective == "altars":
		waves = [[{ "type": String(pool[0]), "n": 2 }]]
		var others: Array = []
		o.altars = []
		for kind in ["heal", "hazard", "reinforce"]:
			var p := place(st, 22.0, float(S.minGap), float(S.minPlayerGap), others)
			others.append(p)
			var e := st.spawn_enemy("altar_" + String(kind), float(p.x), float(p.y))
			e.altar = String(kind)
			e.timer = float(S.heal.interval) if kind == "heal" else (2.5 if kind == "hazard" else float(S.reinforce.interval))
			e.budget = float(S.heal.budget) if kind == "heal" else (float(S.reinforce.budget) if kind == "reinforce" else INF)
			(o.altars as Array).append(e)
		o.reinforce = make_reinforce(S.reinforce, pool)
	elif st.objective == "seal":
		waves = [[{ "type": String(pool[0]), "n": 2 }]]
		var p1 := place(st, float(S.r), float(S.minGap), 120.0, [])
		var p2 := place(st, float(S.r), float(S.minGap), 120.0, [p1])
		o.points = [p1, p2]
		o.stage = 1
		o.stages = int(S.stages)
		o.progress = 0.0
		o.total = float(S.time)
		o.paused = false
		o.hit_pause = 0.0
		o.move_warn_t = 0.0
		st.objects.append({ "kind": "seal", "x": float(p1.x), "y": float(p1.y), "r": float(S.r), "active": true, "moving": false, "next": {} })
		o.reinforce = make_reinforce(S.reinforce, pool)
	elif st.objective == "rescue":
		waves = [[{ "type": String(pool[0]), "n": 2 }]]
		var c1 := place(st, 26.0, float(S.minGap), 150.0, [])
		var c2 := place(st, 26.0, float(S.minGap), 150.0, [c1])
		var ex := edge_exit(st, [c1, c2, { "x": st.player.x, "y": st.player.y }])
		o.cages = int(S.cages)
		o.freed = 0
		o.active = {}
		st.objects.append({ "kind": "cage", "x": float(c1.x), "y": float(c1.y), "r": 26.0, "progress": 0.0, "total": float(S.time), "freed": false, "id": 1 })
		st.objects.append({ "kind": "cage", "x": float(c2.x), "y": float(c2.y), "r": 26.0, "progress": 0.0, "total": float(S.time), "freed": false, "id": 2 })
		st.objects.append({ "kind": "exit", "x": float(ex.x), "y": float(ex.y), "r": float(S.exitR), "open": false })
		o.reinforce = make_reinforce(S.reinforce, pool)
	# 위험 조건(카드): 지원병 증가 = 예산 ×1.5(동시 상한 동일) / 정예 호위 = 첫 웨이브에 정예 1 추가 / 위험 지형 = 주기적 바닥 위험(안전 통로 보장)
	if risk == "reinforce" and not (o.reinforce as Dictionary).is_empty():
		o.reinforce.budget = int(round(float(o.reinforce.budget) * 1.5))
	if risk == "escort" and not waves.is_empty(): # 정예 호위: 첫 웨이브에 정예 1 추가(정예 추적이면 정예 2마리 → 전부 처치해야 종료)
		var w0: Array = waves[0]
		var g0: Dictionary = {}
		for g in w0:
			if String(g.type) == "wolf_alpha":
				g0 = g
				break
		if not g0.is_empty():
			g0.n = int(g0.n) + 1
		else:
			w0.append({ "type": "wolf_alpha", "n": 1 })
	if risk == "hazard":
		o.terrain = { "timer": 6.0, "interval": 7.0, "warn": 1.2, "ttl": 1.6, "r": 60.0, "dmg": 10.0, "lanes": 3 }
	var WS := PCatalog.world_stages() # 세계 변화 2단계부터 위험 조건이 붙은 임무에 정예 +1(잠정, 일부 위험 전투에만 — 모든 전투 2정예 아님)
	if risk != "" and not waves.is_empty() and int(st.opts.get("world_stage", 0)) >= int(WS.get("risk_elite_from_stage", 99)):
		var wl: Array = waves[0]
		var gl: Dictionary = {}
		for g in wl:
			if String(g.type) == "wolf_alpha":
				gl = g
				break
		if not gl.is_empty():
			gl.n = int(gl.n) + int(WS.get("risk_elite_extra", 1))
		else:
			wl.append({ "type": "wolf_alpha", "n": int(WS.get("risk_elite_extra", 1)) })
	# HTML 웨이브 → 밀도 편성(정예 호위 반영 뒤에 변환)
	st.set_formation(PFormation.from_waves(waves, {}, st.region_id, st))
	st.spawned_all = false

# ---------- 바닥 위험(예고 → 지역). 항상 안전 통로를 남긴다 ----------
## 목표 지점(봉인·우리·출구·제단)을 덮는 위험은 만들지 않는다(모든 목표 지점을 막지 않음)
static func covers_objective(st: CombatState, x: float, y: float, r: float) -> bool:
	for o in st.objects:
		if not bool(o.get("gone", false)) and not bool(o.get("freed", false)):
			var orr: float = float(o.get("r", 0.0))
			if orr <= 0.0:
				orr = 20.0
			if PGeom.dist(float(o.x), float(o.y), x, y) <= r + orr:
				return true
	for e in st.enemies:
		if e.structure and not e.dead and PGeom.dist(e.x, e.y, x, y) <= r + e.r:
			return true
	return false

## 반환: 지역 dict, 만들지 못하면 {}
static func hazard_at(st: CombatState, x: float, y: float, r: float, warn: float, ttl: float, dmg: float, tag: String = "hazard") -> Dictionary:
	var vp := st.nearest_valid_pos(x, y, 0.0, 60.0)
	if vp.is_empty():
		return {}
	if covers_objective(st, vp[0], vp[1], r):
		return {}
	var z := st.add_zone("hazard", vp[0], vp[1], r, warn + ttl, dmg)
	z.warn = warn
	z.armed = false
	z.tag = tag if tag != "" else "hazard"
	return z

## 플레이어 주위 n개, 간격 균등: n개 사이의 빈 각도가 안전 통로. cfg = {warn, ttl, dmg}
static func ring_hazards(st: CombatState, cx: float, cy: float, n: int, dist: float, r: float, cfg: Dictionary, tag: String, base_ang: float) -> Array:
	var out: Array = []
	for i in n:
		var a: float = base_ang + float(i) * (TAU / float(n))
		var z := hazard_at(st, cx + cos(a) * dist, cy + sin(a) * dist, r, float(cfg.warn), float(cfg.ttl), float(cfg.dmg), tag)
		if not z.is_empty():
			out.append(z)
	return out

# ---------- 진행 ----------
static func _find_object(st: CombatState, kind: String) -> Dictionary:
	for o in st.objects:
		if String(o.kind) == kind:
			return o
	return {}

static func update(st: CombatState, dt: float) -> void:
	var S := spec(st)
	var o := st.obj
	if S.is_empty() or o.is_empty() or st.status != "running":
		return
	var p := st.player
	if o.has("terrain"):
		var T: Dictionary = o.terrain
		T.timer = float(T.timer) - dt
		if float(T.timer) <= 0.0:
			T.timer = float(T.interval)
			ring_hazards(st, p.x, p.y, int(T.lanes), 120.0, float(T.r), T, "terrain", p.face + PI / float(int(T.lanes)))
			st.ev("hazard_warn")
	if st.objective == "hunt":
		var ec := st.elite_count()
		o.elite_total = int(ec.total)
		o.elite_killed = int(ec.killed)
		if (o.elite as Dictionary).is_empty() or bool(o.elite.dead): # 살아 있는 정예를 차례로 추적
			for e in st.enemies:
				if e.elite and not e.structure and not e.dead:
					o.elite = e
					break
		var el: Dictionary = o.elite
		if not el.is_empty() and not bool(el.dead):
			var d := PGeom.dist(el.x, el.y, p.x, p.y)
			el.leash = (float(el.get("leash", 0.0)) + dt) if d > float(S.leashDist) else 0.0
			el.leash_boost = float(S.leashSpeed) if float(el.leash) > 1.0 else 1.0 # 멀어지면 접근 가속(배회 금지)
			if not bool(o.reinforce_fired) and float(el.hp) <= float(el.hp_max) * float(S.reinforce.atHp):
				o.reinforce_fired = true
				o.reinforce.timer = 0.0
				reinforce(st, o.reinforce, dt, int(o.reinforce.budget))
		# 처치형 임무: 정예 전부 + 남은 적 전멸(지원병 포함). 정예가 50% 전에 죽어 지원이 오지 않았다면 그대로 종료
		var rm := st.remaining()
		if int(ec.total) > 0 and int(ec.killed) >= int(ec.total) and int(rm.total) == 0:
			finish(st)
	elif st.objective == "altars":
		var all_dead := true
		for a in o.altars:
			if a.dead:
				continue
			all_dead = false
			a.timer = float(a.timer) - dt
			if float(a.timer) > 0.0:
				continue
			var kind := String(a.altar)
			if kind == "heal":
				a.timer = float(S.heal.interval)
				if float(a.budget) > 0.0:
					var tgt := heal_target(st, a, float(S.heal.range))
					if not tgt.is_empty():
						var amt: float = minf(float(S.heal.amount), minf(float(a.budget), float(tgt.hp_max) - float(tgt.hp)))
						tgt.hp = float(tgt.hp) + amt
						a.budget = float(a.budget) - amt
						st.fx({ "kind": "healbeam", "x": a.x, "y": a.y, "tx": tgt.x, "ty": tgt.y, "ttl": 0.5 })
						st.text(tgt.x, tgt.y - tgt.r - 10.0, "+" + str(int(round(amt))), "#8ee6a0")
						st.ev("altar_heal")
			elif kind == "hazard":
				var H: Dictionary = S.hazard
				a.timer = float(H.interval)
				ring_hazards(st, p.x, p.y, int(H.n), float(H.dist), float(H.r), H, "altar", p.face + PI / 2.0)
				st.ev("hazard_warn")
			elif kind == "reinforce":
				a.timer = float(S.reinforce.interval)
				if float(a.budget) > 0.0 and active_enemies(st) < int(S.reinforce.cap):
					var R: Dictionary = o.reinforce
					var pool: Array = R.pool
					var type := String(pool[int(R.spawned) % pool.size()])
					st.queue_wave([{ "type": type, "n": 1 }])
					a.budget = float(a.budget) - 1.0
					R.spawned = int(R.spawned) + 1
					st.ev("reinforce", { "n": 1 })
		if all_dead:
			finish(st)
	elif st.objective == "seal":
		reinforce(st, o.reinforce, dt)
		var z := _find_object(st, "seal")
		if float(o.hit_pause) > 0.0:
			o.hit_pause = float(o.hit_pause) - dt
		if float(o.move_warn_t) > 0.0:
			o.move_warn_t = float(o.move_warn_t) - dt
			if float(o.move_warn_t) <= 0.0:
				var p2: Dictionary = o.points[1]
				z.x = float(p2.x)
				z.y = float(p2.y)
				z.moving = false
				st.ev("seal_moved")
			o.paused = true
		else:
			var inside: bool = PGeom.dist(float(z.x), float(z.y), p.x, p.y) <= float(z.r)
			o.paused = (not inside) or float(o.hit_pause) > 0.0
			if not bool(o.paused):
				o.progress = minf(float(o.total), float(o.progress) + dt)
				if int(o.stage) == 1 and float(o.progress) >= float(o.total) / 2.0:
					o.stage = 2
					o.move_warn_t = float(S.moveWarn)
					z.moving = true
					z.next = o.points[1]
					st.ev("seal_move_warn")
			if float(o.progress) >= float(o.total):
				finish(st)
	elif st.objective == "rescue":
		reinforce(st, o.reinforce, dt)
		var exit_o := _find_object(st, "exit")
		o.active = {}
		var cages: Array = []
		for c in st.objects:
			if String(c.kind) == "cage":
				cages.append(c)
		var new_prisoners: Array = []
		for c in cages:
			if bool(c.freed):
				continue
			if PGeom.dist(float(c.x), float(c.y), p.x, p.y) <= float(S.near) + p.r:
				c.progress = minf(float(c.total), float(c.progress) + dt)
				o.active = c
				if float(c.progress) >= float(c.total):
					c.freed = true
					o.freed = int(o.freed) + 1
					new_prisoners.append({ "kind": "prisoner", "x": float(c.x), "y": float(c.y), "r": 10.0, "id": int(c.id), "gone": false, "steer_side": 0, "steer_t": 0.0 })
					st.text(float(c.x), float(c.y) - 40.0, "풀려났다!", "#9cffb0")
					st.ev("rescued", { "n": int(o.freed) })
		for pr in new_prisoners:
			st.objects.append(pr)
		for pr in st.objects: # 포로는 출구로 스스로 이동(적은 무시, 호위 불필요)
			if String(pr.kind) == "prisoner" and not bool(pr.gone):
				var mv := st.steer_dir(pr, float(exit_o.x), float(exit_o.y))
				pr.x = float(pr.x) + mv[0] * float(S.prisonerSpeed) * dt
				pr.y = float(pr.y) + mv[1] * float(S.prisonerSpeed) * dt
				if PGeom.dist(float(pr.x), float(pr.y), float(exit_o.x), float(exit_o.y)) <= 18.0:
					pr.gone = true
		if int(o.freed) >= int(o.cages):
			exit_o.open = true
			if PGeom.dist(float(exit_o.x), float(exit_o.y), p.x, p.y) <= float(exit_o.r):
				finish(st)

## 가장 많이 다친 적(구조물·지하 제외, 사거리 안). 없으면 {}
static func heal_target(st: CombatState, a: Dictionary, rng_: float) -> Dictionary:
	var best: Dictionary = {}
	var bs := 0.0
	for e in st.enemies:
		if e.dead or e.structure or bool(e.hidden) or float(e.hp) >= float(e.hp_max) or PGeom.dist(e.x, e.y, a.x, a.y) > rng_:
			continue
		var miss: float = 1.0 - float(e.hp) / float(e.hp_max)
		if miss > bs:
			bs = miss
			best = e
	return best

static func finish(st: CombatState) -> void:
	var o := st.obj
	if o.is_empty() or bool(o.done):
		return
	o.done = true
	o.done_t = st.t

## 승패 판정: CombatState.check_objective에서 호출. 같은 단계에서 목표 달성과 사망이 겹치면 승리 우선(보스전 규칙과 동일)
static func check(st: CombatState) -> bool:
	return not st.obj.is_empty() and bool(st.obj.get("done", false))

## 피해를 받으면 봉인 진행 잠시 정지(제자리에서 맞으며 버티기 금지)
static func on_player_hit(st: CombatState) -> void:
	if not st.obj.is_empty() and st.objective == "seal":
		st.obj.hit_pause = float(spec(st).hitPause)

# ---------- 바닥 위험 지역 갱신(CombatState.update_zones에서 호출): 예고 후 무장, 무장 중 플레이어 피해 ----------
static func zone_damage(st: CombatState, z: Dictionary, p: Dictionary) -> float:
	if not bool(z.get("armed", false)):
		if float(z.t) >= float(z.get("warn", 0.0)):
			z.armed = true
			st.ev("hazard_arm")
		return 0.0
	return float(z.dmg) if PGeom.dist(float(z.x), float(z.y), float(p.x), float(p.y)) <= float(z.r) + float(p.r) * 0.5 else 0.0

# ---------- 표시 ----------
## 목표별 진행 문구(HTML PA.OBJECTIVES[*].hud)
static func hud_line(st: CombatState, o: Dictionary) -> String:
	if st.objective == "hunt":
		var killed: int = int(o.get("elite_killed", 0))
		var total: int = int(o.get("elite_total", 0))
		if total == 0:
			total = 1
		var s := "정예 %d / %d 처치" % [killed, total]
		var el: Dictionary = o.get("elite", {})
		if not el.is_empty() and not bool(el.dead):
			s += " · 체력 %d / %d" % [int(maxf(0.0, ceil(float(el.hp)))), int(round(float(el.hp_max)))]
		if not bool(o.get("reinforce_fired", false)):
			s += " · 지원 대기"
		return s
	if st.objective == "altars":
		var alive := 0
		for a in o.altars:
			if not a.dead:
				alive += 1
		return "남은 제단 %d / 3" % alive
	if st.objective == "seal":
		var s2 := "봉인 %d%% · %d/%d단계" % [int(floor(float(o.progress) / float(o.total) * 100.0)), int(o.stage), int(o.stages)]
		if bool(o.paused):
			s2 += " · 정지"
		return s2
	if st.objective == "rescue":
		if int(o.freed) >= int(o.cages):
			return "출구로 이동"
		var s3 := "구출 %d / %d" % [int(o.freed), int(o.cages)]
		var ac: Dictionary = o.get("active", {})
		if not ac.is_empty():
			s3 += " · %d%%" % int(floor(float(ac.progress) / float(ac.total) * 100.0))
		return s3
	return ""

## 반환 {title, line, risk(""=없음), end_rule}. 목표가 아니면 {}
static func hud(st: CombatState) -> Dictionary:
	var S := spec(st)
	var o := st.obj
	if S.is_empty() or o.is_empty():
		return {}
	var line := hud_line(st, o)
	var R: Dictionary = o.get("reinforce", {})
	if not R.is_empty() and int(R.budget) > 0 and st.objective != "hunt":
		line += " · 지원 %d" % int(R.budget)
	var risk := String(o.get("risk", ""))
	var risk_text := ""
	if risk != "":
		risk_text = String(PCatalog.mission_rules().riskText.get(risk, ""))
	return { "title": "목적: " + String(S.short), "line": line, "risk": risk_text, "end_rule": "정예·지원병 전멸 시 종료" if st.objective == "hunt" else "목표 달성 시 종료(남은 적 무시)" }

## 자동 공격 대상 표시: 첫 무기 기준 가장 가까운 대상(표식 우선) — 제단인지 적인지. 없으면 {}
static func auto_target(st: CombatState) -> Dictionary:
	var p := st.player
	var rng_ := 0.0
	for w in st.weapons:
		var stt: Dictionary = w.stats
		var wr: float = float(stt.get("range", 0.0))
		if wr == 0.0:
			wr = float(stt.get("radius", 0.0))
		if wr == 0.0:
			wr = 60.0
		rng_ = maxf(rng_, wr)
	if st.mark_target != null and typeof(st.mark_target) == TYPE_DICTIONARY:
		var mk: Dictionary = st.mark_target
		if not bool(mk.dead) and PGeom.dist(p.x, p.y, mk.x, mk.y) <= rng_ + float(mk.r):
			return mk
	var best: Dictionary = {}
	var bd := INF
	for e in st.enemies:
		if e.dead or bool(e.hidden):
			continue
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d <= rng_ + float(e.r) and d < bd:
			bd = d
			best = e
	return best

## 봇: 목표를 위한 이동 지점(적 위협이 없을 때 향한다). {x, y, r} 또는 {}
static func bot_goal(st: CombatState) -> Dictionary:
	var o := st.obj
	if o.is_empty() or bool(o.done):
		return {}
	var p := st.player
	if st.objective == "seal":
		var z := _find_object(st, "seal")
		if z.is_empty():
			return {}
		var tgt: Dictionary = z.next if bool(z.moving) and not (z.next as Dictionary).is_empty() else z
		if PGeom.dist(float(tgt.x), float(tgt.y), p.x, p.y) > float(z.r) * 0.6:
			return { "x": float(tgt.x), "y": float(tgt.y), "r": float(z.r) * 0.6 }
		return {}
	if st.objective == "rescue":
		if int(o.freed) >= int(o.cages):
			var ex := _find_object(st, "exit")
			return { "x": float(ex.x), "y": float(ex.y), "r": float(ex.r) * 0.5 }
		var near := float(PCatalog.objectives().rescue.near)
		var best: Dictionary = {}
		var bd := INF
		for c in st.objects:
			if String(c.kind) == "cage" and not bool(c.freed):
				var d := PGeom.dist(float(c.x), float(c.y), p.x, p.y)
				if d < bd:
					bd = d
					best = c
		if not best.is_empty() and bd > near * 0.7:
			return { "x": float(best.x), "y": float(best.y), "r": near * 0.7 }
		return {}
	return {}

## 봇: 우선 대상(적 dict) 또는 {}
static func bot_target(st: CombatState) -> Dictionary:
	var o := st.obj
	if o.is_empty() or bool(o.done):
		return {}
	var p := st.player
	if st.objective == "altars":
		for e in st.enemies:
			if not e.dead and not e.structure and not bool(e.hidden) and PGeom.dist(e.x, e.y, p.x, p.y) < 90.0:
				return {}
		var best: Dictionary = {}
		var bd := INF
		for a in o.altars:
			if a.dead:
				continue
			var d := PGeom.dist(a.x, a.y, p.x, p.y)
			if d < bd:
				bd = d
				best = a
		return best
	if st.objective == "hunt":
		var el: Dictionary = o.get("elite", {})
		if not el.is_empty() and not bool(el.dead):
			for e in st.enemies:
				if not e.dead and not e.structure and not bool(e.hidden) and e != el and PGeom.dist(e.x, e.y, p.x, p.y) < 70.0:
					return {}
			return el
	return {}

## 봇 위협: 바닥 위험(예고 중 포함)
static func threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "hazard":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r })

static func text(st: CombatState) -> String:
	var S := spec(st)
	if not S.is_empty():
		return String(S.short)
	return "정예 처치" if st.objective == "elite" else "전멸"
