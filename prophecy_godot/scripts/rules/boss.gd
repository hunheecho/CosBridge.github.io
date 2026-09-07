class_name PBoss
extends RefCounted
## 보스 '가시갈기 — 숲의 왕' 행동(HTML boss.js 이식). CombatState.update_enemies가 boss 개체에 대해 update를 부른다.
## 봉인 수호자(guardian)·예언을 먹는 자(eater)는 boss_id로 PBoss2에 넘긴다.
## 상태 이름·시간·판정·fx 종류·문구·이벤트는 HTML과 같다. 좌표 쌍은 [x, y] 배열, 지점은 {x, y} 사전.

## 가시갈기 설정(PA.BOSS)
static func _B() -> Dictionary:
	return PCatalog.boss_defs().boss

## 보스별 설정(PA.BOSS_DEFS[e.bossId]) — 없으면 가시갈기
static func cfg_of(e: Dictionary) -> Dictionary:
	return PCatalog.boss_def(String(e.get("boss_id", "boss")))

static func spawn(st: CombatState, x: float, y: float, boss_id: String) -> Dictionary:
	if boss_id == "":
		boss_id = "boss"
	var e := st.spawn_enemy(boss_id, x, y)
	e.boss_id = boss_id
	e.boss = true
	e.phase = 1
	e.phase_pending = 0
	e.state = "intro"
	e.state_t = 0.0
	e.actions = 0
	e.history = []
	e.last_howl = -999.0
	e.dash_seq = 1
	e.dash_total = 1
	e.dash_dist = 0.0
	e.dash_end = []
	e.dash_len = 0.0
	e.hit_done = false
	e.wait_t = 0.0
	e.approach_t = 0.0
	e.land = {}
	e.leap_from = {}
	e.leap_k = 0.0
	e.stagger_after_land = false
	e.exposed = false
	st.boss = e
	if boss_id != "boss":
		PBoss2.init(st, e)
	return e

# ---------- 판단 보조 ----------
static func wolf_attacking(st: CombatState) -> bool:
	for e in st.enemies:
		if not e.dead and not e.boss and (e.type == "wolf" or e.type == "wolf_alpha") and (e.state == "crouch" or e.state == "lock" or e.state == "dash"):
			return true
	return false

static func boss_committed(e: Dictionary) -> bool:
	return e.state == "sweep_lock" or e.state == "dash_lock" or e.state == "dash" or e.state == "pounce_lock" or e.state == "leap" or PBoss2.is_committed(e)

static func summoned_alive(st: CombatState) -> int:
	var n := 0
	for e in st.enemies:
		if not e.dead and bool(e.get("summoned", false)):
			n += 1
	return n

static func is_exposed(e: Dictionary) -> bool:
	return e.state == "recover" or e.state == "stagger"

## 돌진 경로: 장애물·벽까지의 실제 종료점(예고와 실제가 같은 계산을 쓴다). 반환 {len, end: [x, y]}
static func dash_path(st: CombatState, e: Dictionary, ang: float, max_dist: float) -> Dictionary:
	var dx := cos(ang) * max_dist
	var dy := sin(ang) * max_dist
	var t := 1.0
	var x1: float = e.x + dx
	var y1: float = e.y + dy
	var wx := clampf(x1, e.r, st.arena_w - e.r)
	var wy := clampf(y1, e.r, st.arena_h - e.r)
	if wx != x1 or wy != y1:
		var tx: float = (wx - e.x) / dx if wx != x1 else 1.0
		var ty: float = (wy - e.y) / dy if wy != y1 else 1.0
		t = maxf(0.0, minf(t, minf(tx, ty)))
	var sw := st.sweep_circle(e.x, e.y, x1, y1, e.r)
	if sw[1] >= 0 and sw[0] < t:
		t = sw[0]
	return { "len": max_dist * t, "end": [e.x + dx * t, e.y + dy * t] }

## 덮쳐찍기 착지점: 보스 몸이 들어가는 빈 공간으로 보정. 반환 {x, y}
static func landing_for(st: CombatState, e: Dictionary, tx: float, ty: float) -> Dictionary:
	var r: float = e.r
	var cx := clampf(tx, r + 4.0, st.arena_w - r - 4.0)
	var cy := clampf(ty, r + 4.0, st.arena_h - r - 4.0)
	var vp := st.nearest_valid_pos(cx, cy, r, 300.0)
	if vp.is_empty():
		return { "x": e.x, "y": e.y }
	return { "x": vp[0], "y": vp[1] }

static func can_howl(st: CombatState, e: Dictionary) -> bool:
	var H: Dictionary = _B().howl
	return (st.t - float(e.last_howl)) >= float(H.interval) and summoned_alive(st) < int(H.maxWolves)

## 가중치 추첨. 같은 행동 세 번 연속 금지. 없으면 ""
static func choose_pattern(st: CombatState, e: Dictionary) -> String:
	var cfg := _B()
	var p := st.player
	var d := PGeom.dist(e.x, e.y, p.x, p.y)
	var los: bool = not st.los_blocked(e.x, e.y, p.x, p.y)
	var cands: Array = []
	if int(e.actions) == 0:
		return "dash" # 첫 공격은 단일 돌진
	var h: Array = e.history
	if h.size() == 1 and String(h[0]) == "dash" and can_howl(st, e):
		return "howl" # 첫 돌진 뒤 첫 소환
	if d <= float(cfg.sweep.maxDist) and los:
		cands.append(["sweep", float(cfg.weights.sweep)])
	if d >= float(cfg.dash.minDist) and d <= float(cfg.dash.maxDist) and los:
		cands.append(["dash", float(cfg.weights.dash)])
	if int(e.phase) >= 2 and d >= float(cfg.pounce.minDist):
		cands.append(["pounce", float(cfg.weights.pounce)])
	if can_howl(st, e):
		cands.append(["howl", float(cfg.weights.howl)])
	return _pick_weighted(st, h, cands)

## 가중치 추첨 공통(PBoss2도 쓴다): 직전 2회가 같은 행동이면 그 행동은 후보에서 뺀다
static func _pick_weighted(st: CombatState, h: Array, cands: Array) -> String:
	var last2 := ""
	if h.size() >= 2 and String(h[h.size() - 1]) == String(h[h.size() - 2]):
		last2 = String(h[h.size() - 1])
	var pool: Array = []
	for c in cands:
		if String(c[0]) != last2:
			pool.append(c)
	var use: Array = pool if pool.size() > 0 else cands
	if use.is_empty():
		return ""
	var sum := 0.0
	for c in use:
		sum += float(c[1])
	var r: float = st.rng.next() * sum
	for c in use:
		r -= float(c[1])
		if r <= 0.0:
			return String(c[0])
	return String(use[use.size() - 1][0])

static func begin(st: CombatState, e: Dictionary, pattern: String) -> void:
	e.actions = int(e.actions) + 1
	var h: Array = e.history
	h.append(pattern)
	if h.size() > 6:
		h.pop_front()
	st.metrics.patterns[pattern] = int(st.metrics.patterns.get(pattern, 0)) + 1
	e.state_t = 0.0
	e.hit_done = false
	e.wait_t = 0.0
	st.note_attack(e, "prepare")
	if pattern == "sweep":
		e.state = "sweep_aim"
	elif pattern == "dash":
		e.state = "dash_aim"
		e.dash_seq = 1
		e.dash_total = 2 if int(e.phase) >= 3 else 1
	elif pattern == "pounce":
		e.state = "pounce_aim"
	elif pattern == "howl":
		e.state = "howl"
		e.last_howl = st.t
		st.ev("boss_howl")

static func to_recover(st: CombatState, e: Dictionary, dur: float) -> void:
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = dur
	st.text(e.x, e.y - e.r - 30.0, "빈틈!", "#ffd166")

static func to_approach(_st: CombatState, e: Dictionary) -> void:
	e.state = "approach"
	e.state_t = 0.0
	e.approach_t = 0.0

# ---------- 단계 ----------
## 체력선을 처음 통과할 때 회복 구슬 생성. 단계 적용은 현재 행동이 끝난 뒤(phase_pending)
static func check_phase(st: CombatState, e: Dictionary) -> void:
	var ratio: float = float(e.hp) / float(e.hp_max)
	var ph: Array = cfg_of(e).phases
	for i in ph.size():
		var want: int = i + 2
		if ratio <= float(ph[i]) and not st.orbs_spawned.has(want):
			st.orbs_spawned[want] = true
			spawn_orb(st, e)
			if int(e.phase_pending) < want and int(e.phase) < want:
				e.phase_pending = want

static func spawn_orb(st: CombatState, e: Dictionary) -> void:
	var cfg: Dictionary = cfg_of(e).orb
	var p := st.player
	var best: Dictionary = {}
	var bd := INF
	var ring := float(cfg.ring)
	var orb_r := float(cfg.r)
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var x: float = e.x + cos(a) * ring
		var y: float = e.y + sin(a) * ring
		if not st.valid_pos(x, y, orb_r):
			continue
		if PGeom.dist(x, y, e.x, e.y) < e.r + orb_r + 30.0:
			continue
		if in_danger(st, e, { "x": x, "y": y }):
			continue
		var d := PGeom.dist(x, y, p.x, p.y)
		if d < bd:
			bd = d
			best = { "x": x, "y": y }
	if best.is_empty():
		var vp := st.nearest_valid_pos(p.x + 80.0, p.y, orb_r, 300.0)
		best = { "x": vp[0], "y": vp[1] } if not vp.is_empty() else { "x": p.x, "y": p.y }
	st.pickups.append({ "kind": "heal", "x": best.x, "y": best.y, "r": orb_r, "amount": float(floor(p.hp_max * float(cfg.healRatio))), "t": 0.0, "taken": false })
	st.text(best.x, best.y - 24.0, "회복 구슬", "#9cffb0")

## 현재 위험 예고 한가운데인가(돌진 통로·휩쓸기 부채꼴·착지 원). pt = {x, y}
static func in_danger(st: CombatState, e: Dictionary, pt: Dictionary) -> bool:
	if String(e.get("boss_id", "boss")) != "boss":
		return PBoss2.in_danger(st, e, pt)
	var cfg := _B()
	var px := float(pt.x)
	var py := float(pt.y)
	if (e.state == "dash_lock" or e.state == "dash") and not (e.dash_end as Array).is_empty():
		return PGeom.in_beam(e.x, e.y, float(e.dir), float(e.dash_len), (e.r + 14.0) * 2.0, px, py, 14.0)
	if e.state == "sweep_aim" or e.state == "sweep_lock":
		var ang: float = float(e.aim_angle) if e.state == "sweep_aim" else float(e.dir)
		return PGeom.in_arc(e.x, e.y, float(cfg.sweep.radius), ang, float(cfg.sweep.arcDeg) * PI / 360.0, px, py, 14.0)
	if (e.state == "pounce_lock" or e.state == "leap") and not (e.land as Dictionary).is_empty():
		return PGeom.dist(float(e.land.x), float(e.land.y), px, py) <= float(cfg.pounce.radius) + 14.0
	return false

# ---------- 갱신 ----------
static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	if bool(e.get("dummy", false)): # 허수아비(시험실): 행동 없음
		e.anim_t = float(e.get("anim_t", 0.0)) + dt
		return
	if String(e.get("boss_id", "boss")) != "boss":
		PBoss2.update(st, e, dt)
		return
	var cfg := _B()
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	var adv := dt * tf
	match e.state:
		"intro":
			e.state_t = float(e.state_t) + dt
			if float(e.state_t) >= float(cfg.intro):
				to_approach(st, e)
		"approach":
			e.state_t = float(e.state_t) + adv
			e.approach_t = float(e.approach_t) + adv
			if int(e.phase_pending) > int(e.phase):
				# 단계 전환은 행동 사이에서만
				e.phase = int(e.phase_pending)
				e.state = "roar"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 40.0, "추격 단계" if int(e.phase) == 2 else "마지막 맹공", "#ff9f43")
				st.ev("boss_roar", { "phase": int(e.phase) })
				st.phase_events.append(int(e.phase))
			else:
				if dist > float(cfg.stopDist):
					st.approach(e, p.x, p.y, float(cfg.speed) * sm, dt)
				if float(e.approach_t) >= float(cfg.minApproach):
					var pat := choose_pattern(st, e)
					if pat != "":
						# 겹침 제한: 늑대가 돌진 중이면 큰 공격을 잠시 미룬다(최대 bossWaitMax)
						if pat != "howl" and wolf_attacking(st) and float(e.wait_t) < float(cfg.overlap.bossWaitMax):
							e.wait_t = float(e.wait_t) + adv
						else:
							begin(st, e, pat)
		"roar":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.roar):
				to_approach(st, e)
		"sweep_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.sweep.aim):
				e.state = "sweep_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"sweep_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.sweep.lock):
				# 판정: 표시된 부채꼴과 동일. 직접 공격이므로 장애물 가림 적용
				var half := float(cfg.sweep.arcDeg) * PI / 360.0
				if PGeom.in_arc(e.x, e.y, float(cfg.sweep.radius), float(e.dir), half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
					st.damage_player(float(cfg.sweep.damage), "boss_sweep", e)
				st.fx({ "kind": "bosssweep", "x": e.x, "y": e.y, "angle": float(e.dir), "r": float(cfg.sweep.radius), "half": half, "ttl": 0.3 })
				st.ev("boss_sweep")
				st.note_attack(e, "execute")
				to_recover(st, e, float(cfg.sweep.recover))
		"dash_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			var aim_t: float = float(cfg.dash.second.aim) if int(e.dash_seq) == 2 else float(cfg.dash.aim)
			if float(e.state_t) >= aim_t:
				e.state = "dash_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				var path := dash_path(st, e, float(e.dir), float(cfg.dash.dist))
				e.dash_len = float(path.len)
				e.dash_end = path.end
				e.dash_dist = 0.0
				e.hit_done = false
				st.ev("boss_lock")
		"dash_lock":
			e.state_t = float(e.state_t) + adv
			var lock_t: float = float(cfg.dash.second.lock) if int(e.dash_seq) == 2 else float(cfg.dash.lock)
			if float(e.state_t) >= lock_t:
				e.state = "dash"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"dash":
			# 거리 기준 진행: 감속되어도 확정된 경로와 거리는 그대로
			var remain: float = maxf(0.0, float(e.dash_len) - float(e.dash_dist))
			var stp: float = minf(float(cfg.dash.speed) * tf * dt, remain)
			var x0: float = e.x
			var y0: float = e.y
			var mv := st.move_swept(e, cos(float(e.dir)) * stp, sin(float(e.dir)) * stp)
			e.dash_dist = float(e.dash_dist) + PGeom.dist(e.x, e.y, x0, y0)
			if not bool(e.hit_done) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
				e.hit_done = true
				e.bite_t = 0.0
				st.ev("bite")
				st.damage_player(float(cfg.dash.damage), "boss_dash", e)
			if float(e.dash_dist) >= float(e.dash_len) - 1e-6 or String(mv.hit) != "" or stp <= 1e-9:
				if int(e.dash_seq) < int(e.dash_total):
					e.dash_seq = int(e.dash_seq) + 1
					e.state = "dash_aim"
					e.state_t = 0.0
					st.text(e.x, e.y - e.r - 30.0, "연속 돌진 2/2", "#ff9f43")
				else:
					to_recover(st, e, float(cfg.dash.doubleRecover) if int(e.dash_total) > 1 else float(cfg.dash.recover))
		"howl":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.howl.duration):
				summon(st, e)
				st.note_attack(e, "execute")
				to_approach(st, e)
				e.approach_t = 0.0
		"pounce_aim":
			e.land = landing_for(st, e, p.x, p.y)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.pounce.aim):
				e.state = "pounce_lock"
				e.state_t = 0.0
				e.land = landing_for(st, e, p.x, p.y)
				st.ev("boss_lock")
		"pounce_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.pounce.lock):
				e.state = "leap"
				e.state_t = 0.0
				e.leap_from = { "x": e.x, "y": e.y }
				e.leap_k = 0.0
				e.airborne = true
				st.note_attack(e, "execute")
		"leap":
			e.leap_k = minf(1.0, float(e.leap_k) + adv / float(cfg.pounce.leap))
			var k := float(e.leap_k)
			var lf: Dictionary = e.leap_from
			var land: Dictionary = e.land
			e.x = float(lf.x) + (float(land.x) - float(lf.x)) * k
			e.y = float(lf.y) + (float(land.y) - float(lf.y)) * k
			if k >= 1.0:
				e.airborne = false
				e.x = float(land.x)
				e.y = float(land.y)
				# 지면 충격: 표시된 원 범위. 장애물 가림 없음
				if PGeom.dist(e.x, e.y, p.x, p.y) <= float(cfg.pounce.radius) + p.r:
					st.damage_player(float(cfg.pounce.damage), "boss_pounce", e)
				st.fx({ "kind": "bossland", "x": e.x, "y": e.y, "r": float(cfg.pounce.radius), "ttl": 0.45 })
				st.ev("boss_land")
				if bool(e.stagger_after_land):
					e.stagger_after_land = false
					e.state = "stagger"
					e.state_t = 0.0
				else:
					to_recover(st, e, float(cfg.pounce.recover))
		"recover":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(e.recover_dur):
				to_approach(st, e)
		"stagger":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.stagger):
				to_approach(st, e)
	if e.state != "leap":
		st.push_out(e)

## Fisher-Yates(HTML PA.rng.shuffle과 같은 소비 순서). 새 배열을 돌려준다
static func shuffle(st: CombatState, arr: Array) -> Array:
	var b: Array = arr.duplicate()
	var i: int = b.size() - 1
	while i > 0:
		var j: int = int(floor(st.rng.next() * float(i + 1)))
		var tmp: Variant = b[i]
		b[i] = b[j]
		b[j] = tmp
		i -= 1
	return b

static func _pending_summoned(st: CombatState) -> int:
	var n := 0
	for s in st.pending:
		if bool(s.get("summoned", false)):
			n += 1
	return n

## 무리 소환: 발자국 예고 뒤 늑대 등장(pending에 summoned 표시 → CombatState가 grace를 준다)
static func summon(st: CombatState, e: Dictionary) -> void:
	var cfg: Dictionary = _B().howl
	var p := st.player
	var room: int = int(cfg.maxWolves) - summoned_alive(st) - _pending_summoned(st)
	var n: int = mini(int(cfg.count), maxi(0, room))
	# 후보를 체계적으로 훑는다(벽 옆·플레이어 근처에서도 자리를 찾도록). 플레이어 160 안, 장애물 안, 전장 밖 제외.
	var wr := float(PCatalog.enemy("wolf").r)
	var cands: Array = []
	var rings: Array = [float(cfg.ring[0]), float(cfg.ring[1]), float(cfg.ring[1]) + 50.0, float(cfg.ring[1]) + 100.0]
	for rr in rings:
		for i in 16:
			var a: float = float(i) / 16.0 * TAU + st.rng.range_f(-0.1, 0.1)
			var x: float = e.x + cos(a) * float(rr)
			var y: float = e.y + sin(a) * float(rr)
			if not st.valid_pos(x, y, wr):
				continue
			cands.append({ "x": x, "y": y, "dp": PGeom.dist(x, y, p.x, p.y), "ring": float(rr) })
	var pool: Array = []
	for c in cands:
		if float(c.dp) >= 160.0:
			pool.append(c)
	if pool.size() < n:
		pool = []
		for c in cands:
			if float(c.dp) >= 110.0:
				pool.append(c)
	# 가까운 링 우선, 같은 링은 무작위(안정 정렬: 링 순서대로 모은다)
	var shuffled := shuffle(st, pool)
	pool = []
	for rr in rings:
		for c in shuffled:
			if float(c.ring) == float(rr):
				pool.append(c)
	var placed := 0
	for c in pool:
		if placed >= n:
			break
		var near := false
		for s in st.pending:
			if PGeom.dist(float(s.x), float(s.y), float(c.x), float(c.y)) < wr * 2.0 + 4.0:
				near = true
				break
		if near:
			continue
		st.pending.append({ "type": "wolf", "x": float(c.x), "y": float(c.y), "t": float(cfg.warn), "summoned": true })
		st.fx({ "kind": "pawwarn", "x": float(c.x), "y": float(c.y), "ttl": float(cfg.warn), "type": "wolf" })
		placed += 1
	if placed > 0:
		st.ev("wave", { "summon": true })

## 방벽 파열: 진행 중 공격을 끊고 비틀거림. 도약 중이면 착지 후 적용
static func stagger(st: CombatState, e: Dictionary) -> void:
	if e.dead:
		return
	if e.state == "leap":
		e.stagger_after_land = true
		return
	e.state = "stagger"
	e.state_t = 0.0
	e.bite_t = 0.0
	st.text(e.x, e.y - e.r - 30.0, "비틀거림!", "#7ef2ff")
