class_name PBoss2
extends RefCounted
## 신규 보스 2종 행동(HTML boss2.js 이식): 봉인 수호자(guardian)·예언을 먹는 자(eater). PBoss.update가 boss_id로 여기로 넘긴다.
## 공통: 준비 → 확정 → 실행 → 빈틈. 감속장(time_factor)은 모든 단계에 적용. 완전 무적·체력 구간 피해 상한 없음.
## 개체 필드: history[], actions, wait_t, approach_t, marks[{x,y,r,explode_at,done}], lanes[{ang,fired}], lane_idx, trail[{x,y,t}], trail_t, summon_budget, last_summon, shock_left, devices[적 dict](guardian)

const COMMITTED: Array = ["sweep_lock", "shock_lock", "mark_wait", "lanes_lock", "lanes_fire", "wide_lock"]

static func cfg_of(e: Dictionary) -> Dictionary:
	return PCatalog.boss_def(String(e.get("boss_id", "boss")))

static func is_committed(e: Dictionary) -> bool:
	return String(e.get("state", "")) in COMMITTED or PBoss3.is_committed(e) or PBoss4.is_committed(e)

## 행동이 끝났을 때: 연계가 남아 있으면 빈틈 대신 짧은 이동 구간으로 잇고, 아니면 연계 전체의 빈틈을 한 번 준다(PBoss 공통 엔진)
static func to_recover(st: CombatState, e: Dictionary, dur: float) -> void:
	if PBoss.chain_continue(st, e):
		return
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = PBoss.chain_end_recover(e, dur)
	PBoss.chain_reset(e)
	st.text(e.x, e.y - e.r - 30.0, "빈틈!", "#ffd166")

static func to_approach(_st: CombatState, e: Dictionary) -> void:
	e.state = "approach"
	e.state_t = 0.0
	e.approach_t = 0.0

static func allies_committed(st: CombatState) -> bool:
	for o in st.enemies:
		if not o.dead and not o.boss and not o.structure and st.is_committed(o):
			return true
	return false

# ---------- 설정(스폰 시) ----------
static func init(st: CombatState, e: Dictionary) -> void:
	if PBoss3.has(String(e.boss_id)): # 신규 보스 6종은 PBoss3
		PBoss3.init(st, e)
		return
	var cfg := cfg_of(e)
	e.history = []
	e.actions = 0
	e.wait_t = 0.0
	e.approach_t = 0.0
	e.marks = []
	e.lanes = []
	e.lane_idx = 0
	e.trail = []
	e.trail_t = 0.0
	e.summon_budget = int(cfg.summon.budget) if cfg.has("summon") else 0
	e.last_summon = -999.0
	e.shock_left = 0
	PBoss.chain_init(e)
	if String(e.boss_id) == "guardian":
		var D: Dictionary = cfg.devices
		e.devices = []
		var others: Array = [{ "x": e.x, "y": e.y }, { "x": st.player.x, "y": st.player.y }]
		for i in int(D.count):
			var p := PObjectives.place(st, 20.0, float(D.minGap), 150.0, others)
			others.append(p)
			var d := st.spawn_enemy("seal_device", float(p.x), float(p.y))
			d.timer = float(D.first) + float(i) * 1.5
			d.device_index = i
			(e.devices as Array).append(d)

# ---------- 패턴 선택 ----------
## 지금 거리·재사용에서 고를 수 있는 후보 [[이름, 가중치], ...] (PBoss 연계 엔진도 이 목록을 본다)
## 먹는 자: 표식이 남아 있는 동안에는 새 '표식'을 겹치지 않는다. 다만 잔여 표식(지난 위치·공개 예고) 때문에
## 보스가 몇 초씩 아무것도 하지 않던 문제를 없애려고, 표식 대기 중에도 markBusy에 적힌 행동만은 이을 수 있다.
static func candidates(st: CombatState, e: Dictionary) -> Array:
	var cfg := cfg_of(e)
	var B := PBoss.beh_e(e)
	var p := st.player
	var d := PGeom.dist(e.x, e.y, p.x, p.y)
	var los: bool = not st.los_blocked(e.x, e.y, p.x, p.y)
	var cands: Array = []
	if String(e.boss_id) == "guardian":
		if d <= float(cfg.sweep.maxDist) and los:
			cands.append(["sweep", float(cfg.weights.sweep)])
		if d >= float(cfg.shock.minDist) and d <= float(cfg.shock.maxDist):
			cands.append(["shock", float(cfg.weights.shock)])
		PBoss4.extra_candidates(st, e, cands) # 신규 패턴(§11-A)
		return cands
	var busy: bool = not (e.get("marks", []) as Array).is_empty()
	var allow: Array = B.get("markBusy", [])
	if busy and allow.is_empty():
		return [] # 개편 전 규칙: 표식이 남아 있으면 새 패턴 없음
	if not busy:
		cands.append(["mark", float(cfg.weights.mark)])
	if d >= PBoss.pat_num(e, cfg, "lanes", "minDist", 0.0) and (not busy or allow.has("lanes")):
		cands.append(["lanes", float(cfg.weights.lanes)])
	if d <= float(cfg.wide.maxDist) and (not busy or allow.has("wide")):
		cands.append(["wide", float(cfg.weights.wide)])
	if can_summon(st, e) and (not busy or allow.has("summon")):
		cands.append(["summon", float(cfg.weights.summon)])
	PBoss4.extra_candidates(st, e, cands) # 신규 패턴(§11-A)
	return cands

static func choose(st: CombatState, e: Dictionary) -> String:
	var cfg := cfg_of(e)
	var p := st.player
	var d := PGeom.dist(e.x, e.y, p.x, p.y)
	if int(e.actions) == 0:
		return "shock" if String(e.boss_id) == "guardian" else "lanes"
	var cov := PBoss.cover_take(st, e) # 엄폐 대응(지형 파괴)이 예약돼 있으면 그것이 먼저
	if cov != "":
		return cov
	var forced := PBoss.chain_take(st, e) # 연계로 예약된 후속 행동이 먼저
	if forced != "":
		return forced
	var cands := candidates(st, e)
	if String(e.boss_id) == "guardian" and cands.is_empty():
		return "sweep" if d <= float(cfg.sweep.maxDist) else "shock"
	return PBoss._pick_weighted(st, e.history, cands)

static func can_summon(st: CombatState, e: Dictionary) -> bool:
	var cfg := cfg_of(e)
	if not cfg.has("summon"):
		return false
	var S: Dictionary = cfg.summon
	return int(e.summon_budget) > 0 and (st.t - float(e.last_summon)) >= float(S.interval) and PBoss.summoned_alive(st) < int(S.cap)

static func begin(st: CombatState, e: Dictionary, pat: String) -> void:
	var cfg := cfg_of(e)
	e.actions = int(e.actions) + 1
	var h: Array = e.history
	h.append(pat)
	if h.size() > 6:
		h.pop_front()
	e.state_t = 0.0
	e.wait_t = 0.0
	PBoss.chain_note_begin(e, cfg, pat)
	st.note_attack(e, "prepare")
	st.metrics.patterns[pat] = int(st.metrics.patterns.get(pat, 0)) + 1
	if PBoss4.has_pattern(e, pat): # 신규 패턴(§11-A)
		PBoss4.begin(st, e, pat)
		return
	if pat == "sweep":
		e.state = "sweep_aim"
	elif pat == "shock":
		e.state = "shock_aim"
		e.shock_left = int(cfg.shock.count[mini(2, int(e.phase) - 1)])
	elif pat == "mark":
		e.state = "mark_cast"
	elif pat == "lanes":
		e.state = "lanes_warn"
		var a1 := atan2(st.player.y - e.y, st.player.x - e.x)
		e.lanes = [{ "ang": a1, "fired": false }, { "ang": a1 + float(cfg.lanes.secondDeg) * PI / 180.0, "fired": false }]
		e.lane_idx = 0
	elif pat == "wide":
		e.state = "wide_aim"
	elif pat == "summon":
		e.state = "summon"
		e.last_summon = st.t
		st.ev("boss_howl")

## 직선 충격파: 방향 고정, 파동(적 투사체)이 날아간다. 감속장 안에서는 파동도 느려짐(투사체 규칙)
static func fire_shock(st: CombatState, e: Dictionary, ang: float, S: Dictionary) -> void:
	var width := float(S.width)
	var speed := float(S.speed)
	var pr_shock := { "owner": "enemy", "kind": "shock", "shooter": e, "x": e.x + cos(ang) * e.r, "y": e.y + sin(ang) * e.r, "vx": cos(ang) * speed, "vy": sin(ang) * speed, "r": width / 2.0, "dmg": float(S.damage), "ttl": float(S.len) / speed, "angle": ang, "width": width, "dead": false, "hits": {} }
	CombatState.stamp_projectile(e, pr_shock)
	st.projectiles.append(pr_shock)
	st.ev("boss_sweep")

# ---------- 갱신 ----------
static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	if PBoss3.has(String(e.boss_id)):
		PBoss3.update(st, e, dt)
		return
	var cfg := cfg_of(e)
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	# 예고 배속은 연계 후속타의 준비·고정 구간에만(실행·빈틈·접근 제외). 감속장(tf)은 모든 구간에 그대로 적용된다
	var adv := dt * tf * PBoss.prep_speed(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	var bid := String(e.boss_id)
	# 플레이어 위치 기록(표식용, 공개 정보)
	if bid == "eater":
		var M: Dictionary = cfg.mark
		e.trail_t = float(e.trail_t) + dt
		if float(e.trail_t) >= float(M.sample):
			e.trail_t = 0.0
			var trail: Array = e.trail
			trail.append({ "x": p.x, "y": p.y, "t": st.t })
			var keep: int = int(ceil(float(M.history) / float(M.sample))) + 1
			while trail.size() > keep:
				trail.pop_front()
		update_marks(st, e, dt)
	if bid == "guardian":
		update_devices(st, e, dt)
	match e.state:
		"intro":
			e.state_t = float(e.state_t) + dt
			if float(e.state_t) >= float(cfg.intro):
				to_approach(st, e)
		"approach":
			e.state_t = float(e.state_t) + adv
			e.approach_t = float(e.approach_t) + adv
			if int(e.phase_pending) > int(e.phase):
				PBoss.chain_reset(e)
				e.phase = int(e.phase_pending)
				e.state = "roar"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 40.0, "2단계" if int(e.phase) == 2 else "마지막 단계", "#ff9f43")
				st.ev("boss_roar", { "phase": int(e.phase) })
				st.phase_events.append({ "t": st.t, "phase": int(e.phase) })
			else:
				if dist > float(cfg.stopDist):
					st.approach(e, p.x, p.y, float(cfg.speed) * sm, dt)
				if float(e.approach_t) >= PBoss.min_approach(e, cfg):
					var pat := choose(st, e)
					if pat != "":
						if pat != "summon" and allies_committed(st) and float(e.wait_t) < float(cfg.overlap.bossWaitMax):
							e.wait_t = float(e.wait_t) + adv
						else:
							PBoss.chain_arm(e) # 스스로 고른 행동만 연계로 이어진다
							begin(st, e, pat)
		"roar":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.roar):
				to_approach(st, e)
		# 봉인 수호자
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
				var half := float(cfg.sweep.arcDeg) * PI / 360.0
				if PGeom.in_arc(e.x, e.y, float(cfg.sweep.radius), float(e.dir), half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
					st.damage_player(float(cfg.sweep.damage), "boss_sweep", e)
				st.fx({ "kind": "bosssweep", "x": e.x, "y": e.y, "angle": float(e.dir), "r": float(cfg.sweep.radius), "half": half, "ttl": 0.3 })
				st.ev("boss_sweep")
				st.note_attack(e, "execute")
				to_recover(st, e, float(cfg.sweep.recover))
		"shock_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.shock.aim):
				e.state = "shock_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"shock_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.shock.lock):
				var S: Dictionary = cfg.shock
				if int(e.shock_left) >= 2:
					fire_shock(st, e, float(e.dir) - float(S.spread), S)
					fire_shock(st, e, float(e.dir) + float(S.spread), S)
				else:
					fire_shock(st, e, float(e.dir), S)
				st.note_attack(e, "execute")
				to_recover(st, e, float(S.recover))
		# 예언을 먹는 자
		"mark_cast":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.mark.cast):
				var M: Dictionary = cfg.mark
				var n: int = int(M.count[mini(2, int(e.phase) - 1)])
				var pts: Array = []
				for q in e.trail: # 시전 시점 기준 0.5초 이상 지난 위치만(현재 위치 제외)
					if st.t - float(q.t) >= float(M.sample):
						pts.append(q)
				pts = pts.slice(maxi(0, pts.size() - n))
				var marks: Array = []
				for i in pts.size():
					var q: Dictionary = pts[i]
					marks.append({ "x": float(q.x), "y": float(q.y), "r": float(M.r), "explode_at": st.t + float(M.delay) + float(i) * float(M.gap), "done": false })
				if marks.is_empty():
					marks = [{ "x": p.x, "y": p.y, "r": float(M.r), "explode_at": st.t + float(M.delay), "done": false }]
				# 파괴 자격이 표식에 걸려 있으면("지난 자리를 통째로 먹는다!") 지목한 장애물에 **가장 가까운 표식 하나만**
				# 그 장애물을 덮을 만큼 옮긴다. 나머지 표식과 개수·시각·반지름은 그대로다
				_aim_break_mark(st, e, marks, float(M.r))
				e.marks = marks
				e.state = "mark_wait"
				e.state_t = 0.0
				st.note_attack(e, "execute")
				st.ev("boss_lock")
		"mark_wait":
			e.state_t = float(e.state_t) + adv
			# 표식은 정해진 시각에 스스로 터진다(update_marks). 보스가 그 앞에서 몇 초씩 서 있지 않고 다음 행동으로 이을 수 있다
			if (e.marks as Array).is_empty():
				to_recover(st, e, float(cfg.mark.recover))
			elif PBoss.chain_early(st, e, "mark", float(e.state_t)):
				pass # 다음 행동으로 넘어갔다(남은 표식은 계속 제 시각에 터진다)
		"lanes_warn":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.lanes.warn):
				e.state = "lanes_lock"
				e.state_t = 0.0
				st.ev("boss_lock")
		"lanes_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.lanes.lock):
				var L: Dictionary = cfg.lanes
				var lanes: Array = e.lanes
				var ln: Dictionary = lanes[int(e.lane_idx)]
				fire_shock(st, e, float(ln.ang), L)
				ln.fired = true
				st.note_attack(e, "execute")
				e.lane_idx = int(e.lane_idx) + 1
				if int(e.lane_idx) < lanes.size():
					e.state = "lanes_fire"
					e.state_t = 0.0
				else:
					to_recover(st, e, float(L.recover))
		"lanes_fire":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.lanes.gap):
				e.state = "lanes_lock"
				e.state_t = 0.0
		"wide_aim":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.wide.aim):
				e.state = "wide_lock"
				e.state_t = 0.0
				st.ev("boss_lock")
		"wide_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.wide.lock):
				var R: float = float(cfg.wide.radius[mini(2, int(e.phase) - 1)])
				if PGeom.dist(e.x, e.y, p.x, p.y) <= R + p.r:
					st.damage_player(float(cfg.wide.damage), "boss_wide", e)
				st.fx({ "kind": "bossland", "x": e.x, "y": e.y, "r": R, "ttl": 0.5 })
				st.ev("boss_land")
				st.note_attack(e, "execute")
				to_recover(st, e, float(cfg.wide.recover))
		"summon":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.summon.duration):
				summon(st, e)
				st.note_attack(e, "execute")
				# 소환은 주공격의 보조: 부른 직후 보스도 바로 다음 행동으로 잇고, 이을 것이 없으면 짧은 빈틈으로 끝난다
				PBoss.summon_end(st, e)
		"recover":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(e.recover_dur):
				to_approach(st, e)
		"stagger":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.stagger):
				to_approach(st, e)
	st.push_out(e)

## 파괴 자격이 표식에 걸려 있을 때, 지목한 장애물에 가장 가까운 표식 하나를 그 장애물이 판정 안에 들어올 만큼만 옮긴다.
## 표식 수·터지는 시각·반지름은 그대로다. 자격이 없으면 아무것도 하지 않는다(개편 전과 같다).
static func _aim_break_mark(st: CombatState, e: Dictionary, marks: Array, r: float) -> void:
	var ob := PBoss.break_target(st, e, "mark")
	if ob.is_empty() or marks.is_empty():
		return
	var best: int = 0
	var bd := INF
	for i in marks.size():
		var mk: Dictionary = marks[i]
		var d: float = PGeom.dist(float(mk.x), float(mk.y), float(ob.x), float(ob.y))
		if d < bd:
			bd = d
			best = i
	var tgt: Dictionary = marks[best]
	var np: Array = PBoss.break_point(st, e, "mark", float(tgt.x), float(tgt.y), r)
	tgt.x = float(np[0])
	tgt.y = float(np[1])

## 표식 폭발: 공개된 위치, 정해진 시각에 순차. 감속장은 표식 시계를 늦추지 않는다(위치 기반 예고이므로 회피 여유가 이미 큼)
static func update_marks(st: CombatState, e: Dictionary, _dt: float) -> void:
	var p := st.player
	var dmg := float(cfg_of(e).mark.damage)
	for mk in e.marks:
		if bool(mk.done) or st.t < float(mk.explode_at):
			continue
		mk.done = true
		# 먹는 자의 지형 파괴: **표식 폭발이 그 자리를 통째로 먹는다**. 공개된 표식 원 안의 엄폐물이 피해 판정보다 **먼저** 사라진다
		PBoss.break_do(st, e, PTerrain.pick_circle(st.arena_w, st.arena_h, st.obstacles, float(mk.x), float(mk.y), float(mk.r), PBoss.breaker_of(e).get("types", [])), "eater:mark")
		if PGeom.dist(float(mk.x), float(mk.y), p.x, p.y) <= float(mk.r) + p.r:
			st.damage_player(dmg, "boss_mark")
		st.fx({ "kind": "burst", "x": float(mk.x), "y": float(mk.y), "r": float(mk.r), "ttl": 0.35, "color": "#c080ff" })
		st.ev("explode")
	var keep: Array = []
	for mk in e.marks:
		if not bool(mk.done):
			keep.append(mk)
	e.marks = keep

## 봉인 장치: 살아 있는 장치마다 주기적으로 플레이어 좌우에 바닥 위험. 동시 위험 상한
static func update_devices(st: CombatState, e: Dictionary, dt: float) -> void:
	var cfg := cfg_of(e)
	var D: Dictionary = cfg.devices
	var p := st.player
	for d in e.devices:
		if d.dead:
			continue
		d.timer = float(d.timer) - dt
		if float(d.timer) > 0.0:
			continue
		d.timer = float(D.interval)
		var hz := 0
		for z in st.zones:
			if z.type == "hazard":
				hz += 1
		if hz >= int(cfg.overlap.maxHazardZones):
			continue
		PObjectives.ring_hazards(st, p.x, p.y, int(D.n), float(D.dist), float(D.r), D, "device", p.face + PI / 2.0 + float(int(d.device_index)) * 0.6)
		st.ev("hazard_warn")

static func summon(st: CombatState, e: Dictionary) -> void:
	var S: Dictionary = cfg_of(e).summon
	var p := st.player
	var pend := 0
	for s in st.pending:
		if bool(s.get("summoned", false)):
			pend += 1
	var n: int = mini(int(S.count), mini(int(e.summon_budget), int(S.cap) - PBoss.summoned_alive(st) - pend))
	if n <= 0:
		return
	var placed := 0
	var pool: Array = S.pool
	var rings: Array = [float(S.ring[0]), float(S.ring[1]), float(S.ring[1]) + 60.0]
	for rr in rings:
		var i := 0
		while i < 12 and placed < n:
			var a: float = float(i) / 12.0 * TAU + st.rng.range_f(-0.1, 0.1)
			var x: float = e.x + cos(a) * float(rr)
			var y: float = e.y + sin(a) * float(rr)
			var type := String(pool[(int(e.summon_budget) + placed) % pool.size()])
			i += 1
			if not st.valid_pos(x, y, float(PCatalog.enemy(type).r)) or PGeom.dist(x, y, p.x, p.y) < 150.0:
				continue
			var near := false
			for s in st.pending:
				if PGeom.dist(float(s.x), float(s.y), x, y) < 30.0:
					near = true
					break
			if near:
				continue
			st.pending.append({ "type": type, "x": x, "y": y, "t": float(S.warn), "summoned": true })
			st.fx({ "kind": "pawwarn", "x": x, "y": y, "ttl": float(S.warn), "type": type })
			placed += 1
	e.summon_budget = int(e.summon_budget) - placed
	if placed > 0:
		st.ev("wave", { "summon": true })

## 현재 위험 예고 안인가(회복 구슬 배치용). pt = {x, y}
static func in_danger(st: CombatState, e: Dictionary, pt: Dictionary) -> bool:
	if PBoss3.has(String(e.get("boss_id", ""))):
		return PBoss3.in_danger(st, e, pt)
	var cfg := cfg_of(e)
	var px := float(pt.x)
	var py := float(pt.y)
	if (e.state == "sweep_aim" or e.state == "sweep_lock") and cfg.has("sweep"):
		var ang: float = float(e.aim_angle) if e.state == "sweep_aim" else float(e.dir)
		return PGeom.in_arc(e.x, e.y, float(cfg.sweep.radius), ang, float(cfg.sweep.arcDeg) * PI / 360.0, px, py, 14.0)
	if (e.state == "shock_aim" or e.state == "shock_lock") and cfg.has("shock"):
		var ang2: float = float(e.aim_angle) if e.state == "shock_aim" else float(e.dir)
		return PGeom.in_beam(e.x, e.y, ang2, float(cfg.shock.len), float(cfg.shock.width) + 28.0, px, py, 14.0)
	for mk in e.get("marks", []):
		if PGeom.dist(float(mk.x), float(mk.y), px, py) <= float(mk.r) + 14.0:
			return true
	if (e.state == "wide_aim" or e.state == "wide_lock") and cfg.has("wide"):
		return PGeom.dist(e.x, e.y, px, py) <= float(cfg.wide.radius[mini(2, int(e.phase) - 1)]) + 14.0
	if e.state == "lanes_warn" or e.state == "lanes_lock" or e.state == "lanes_fire":
		for l in e.lanes:
			if not bool(l.fired) and PGeom.in_beam(e.x, e.y, float(l.ang), float(cfg.lanes.len), float(cfg.lanes.width) + 28.0, px, py, 14.0):
				return true
	return false

## 봇 위협 도형. out에 {kind, e, x, y, ang, len, w, r, half, prog, locked} 추가
static func threats(st: CombatState, bz: Dictionary, out: Array) -> void:
	if PBoss3.has(String(bz.get("boss_id", ""))):
		PBoss3.threats(st, bz, out)
		return
	var cfg := cfg_of(bz)
	if bz.state == "sweep_aim":
		out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "r": float(cfg.sweep.radius) + 30.0, "half": float(cfg.sweep.arcDeg) * PI / 360.0 + 0.2, "prog": float(bz.state_t) / float(cfg.sweep.aim), "locked": false })
	if bz.state == "sweep_lock":
		out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "r": float(cfg.sweep.radius) + 30.0, "half": float(cfg.sweep.arcDeg) * PI / 360.0 + 0.2, "prog": 1.0, "locked": true })
	if bz.state == "shock_aim":
		out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "len": float(cfg.shock.len), "w": float(cfg.shock.width) + 30.0 + (200.0 if int(bz.shock_left) >= 2 else 0.0), "prog": float(bz.state_t) / float(cfg.shock.aim), "locked": false })
	if bz.state == "shock_lock":
		out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "len": float(cfg.shock.len), "w": float(cfg.shock.width) + 30.0 + (200.0 if int(bz.shock_left) >= 2 else 0.0), "prog": 1.0, "locked": true })
	for mk in bz.get("marks", []):
		out.append({ "kind": "circle", "e": bz, "x": float(mk.x), "y": float(mk.y), "r": float(mk.r) + 10.0, "prog": minf(1.0, 1.0 - (float(mk.explode_at) - st.t) / float(cfg.mark.delay)), "locked": float(mk.explode_at) - st.t < 0.6 })
	if bz.state == "lanes_warn" or bz.state == "lanes_lock" or bz.state == "lanes_fire":
		for l in bz.lanes:
			if not bool(l.fired):
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(l.ang), "len": float(cfg.lanes.len), "w": float(cfg.lanes.width) + 30.0, "prog": (float(bz.state_t) / float(cfg.lanes.warn)) if bz.state == "lanes_warn" else 1.0, "locked": bz.state != "lanes_warn" })
	if bz.state == "wide_aim" or bz.state == "wide_lock":
		out.append({ "kind": "circle", "e": bz, "x": bz.x, "y": bz.y, "r": float(cfg.wide.radius[mini(2, int(bz.phase) - 1)]) + 30.0, "prog": (float(bz.state_t) / float(cfg.wide.aim)) if bz.state == "wide_aim" else 1.0, "locked": bz.state == "wide_lock" })
