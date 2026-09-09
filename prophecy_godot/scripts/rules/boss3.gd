class_name PBoss3
extends RefCounted
## 신규 관문 보스 6종(계획 문서 §7, data/bosses_new.json 시험값): 성문 파수장(gate_warden)·포자 어미(spore_matriarch)·굴착 거수(excavation_behemoth)·
## 서리 추적자(frost_stalker)·핏빛 사냥왕(blood_hunt_king)·종말의 집행관(doom_executor). PBoss.spawn/update/boss_committed/in_danger·PBoss2.threats가 boss_id로 여기로 넘긴다.
## 공통: 준비(aim/warn/cast, 플레이어 추적) → 확정(lock, 방향·위치 고정) → 실행 → 빈틈(recover). 감속장(time_factor)은 준비·이동·실행·빈틈 진행(adv)에 적용.
## 완전 무적·순간이동·체력 구간 피해 상한 없음. 모든 직접 공격은 st.damage_player(dmg, "boss_<pattern>", e). threats()가 봇·화면이 보는 예고 도형을 같은 기하로 돌려준다.
## 개체 필드(지연 초기화): history[], actions, wait_t, approach_t, guard_real, dash_seq, dash_total, dash_len, dash_end[], dash_dist, hit_done, burrow_plan[], marks[], shot_left, shot_timer,
##   ring_gap, ring_r, ring_half, rocks[], rubble_tick, lanes[], side_dir[], side_t, slashes[], slash_idx, guard_t, face, summon_budget, last_summon

const IDS: Array = ["gate_warden", "spore_matriarch", "excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]
## 확정·실행 상태(늑대 돌진 금지·회복 구슬 배치 판단에 쓰인다). 준비 상태(aim/warn/cast)와 옆 이동·방어 자세는 포함하지 않는다
const COMMITTED: Array = ["guard_lock", "breach_lock", "breach", "bsweep_lock", "bolts_lock", "shot_wait", "ring_lock", "ring", "spray_lock",
	"burrow_lock", "burrow", "rock_wait", "bolt_lock", "path_lock", "dash_lock", "dash", "dash_reaim", "dash_relock", "claw_lock", "slash_lock", "slash_gap", "gstrike_lock"]

static func has(id: String) -> bool:
	return IDS.has(id)

static func cfg_of(e: Dictionary) -> Dictionary:
	return PCatalog.boss_def(String(e.get("boss_id", "boss")))

static func is_committed(e: Dictionary) -> bool:
	return has(String(e.get("boss_id", ""))) and String(e.get("state", "")) in COMMITTED

## 준비 단계(예고 진행 중)인가 — 표시·통계용
static func is_preparing(e: Dictionary) -> bool:
	var s := String(e.get("state", ""))
	return s.ends_with("_aim") or s == "slash_warn" or s == "shot_cast" or s == "rock_cast" or s == "sidestep" or s == "guard"

## 행동이 끝났을 때: 연계가 남아 있으면 빈틈 대신 짧은 이동 구간으로 잇고, 아니면 연계 전체의 빈틈을 한 번 준다(PBoss 공통 엔진)
static func to_recover(st: CombatState, e: Dictionary, dur: float, label: String = "빈틈!") -> void:
	if PBoss.chain_continue(st, e):
		return
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = PBoss.chain_end_recover(e, dur)
	PBoss.chain_reset(e)
	st.text(e.x, e.y - e.r - 30.0, label, "#ffd166")

static func to_approach(_st: CombatState, e: Dictionary) -> void:
	e.state = "approach"
	e.state_t = 0.0
	e.approach_t = 0.0

## 현재 향하는 방향(준비 중엔 추적 각, 확정 뒤엔 고정 각)
static func facing(e: Dictionary) -> float:
	var s := String(e.state)
	if s == "guard":
		return float(e.get("face", 0.0))
	if s.ends_with("_aim") or s == "dash_reaim":
		return float(e.aim_angle)
	return float(e.dir)

# ---------- 설정(스폰 시) ----------
static func init(st: CombatState, e: Dictionary) -> void:
	var cfg := cfg_of(e)
	e.history = []
	e.actions = 0
	e.wait_t = 0.0
	e.approach_t = 0.0
	e.guard_real = 0.0
	e.dash_seq = 1
	e.dash_total = 1
	e.dash_len = 0.0
	e.dash_end = []
	e.dash_dist = 0.0
	e.hit_done = false
	e.burrow_plan = []
	e.marks = []
	e.shot_left = 0
	e.shot_timer = 0.0
	e.ring_gap = 0.0
	e.ring_r = 0.0
	e.ring_half = 0.0
	e.rocks = []
	e.rubble_tick = 0.0
	e.lanes = []
	e.side_dir = [1.0, 0.0]
	e.slashes = []
	e.slash_idx = 0
	e.guard_t = 0.0
	e.dash_ob = {}
	e.face = atan2(st.player.y - e.y, st.player.x - e.x)
	e.summon_budget = int(cfg.summon.budget) if cfg.has("summon") else 0
	e.last_summon = -999.0
	PBoss.chain_init(e)
	# 호위(늑대가 아닌 소환)의 동시 위험 행동 한도: CombatState.may_attack이 읽는 overlap_limit(이 보스전에만). 늑대는 wolf_may_attack이 보스 확정 여부를 본다
	var ov: Dictionary = cfg.get("overlap", {})
	if ov.has("allyLimit"):
		st.overlap_limit = int(ov.allyLimit)

# ---------- 판단 보조 ----------
static func can_summon(st: CombatState, e: Dictionary) -> bool:
	var cfg := cfg_of(e)
	if not cfg.has("summon"):
		return false
	var S: Dictionary = cfg.summon
	return int(e.summon_budget) > 0 and (st.t - float(e.last_summon)) >= float(S.interval) and PBoss.summoned_alive(st) < int(S.cap)

static func _last(e: Dictionary) -> String:
	var h: Array = e.history
	return String(h[h.size() - 1]) if h.size() > 0 else ""

## 돌진 경로(임의 시작점): 벽·장애물까지 실제 종료점(예고와 실제가 같은 계산). 반환 {len, end:[x,y], ob}
## ob = 경로를 잘라 세운 장애물({}이면 벽이나 끝까지 감). 성문 파수장의 '돌파 충돌 파괴'가 이것을 쓴다
static func path_from(st: CombatState, x0: float, y0: float, r: float, ang: float, max_dist: float) -> Dictionary:
	var dx := cos(ang) * max_dist
	var dy := sin(ang) * max_dist
	var t := 1.0
	var x1 := x0 + dx
	var y1 := y0 + dy
	var wx := clampf(x1, r, st.arena_w - r)
	var wy := clampf(y1, r, st.arena_h - r)
	if wx != x1 or wy != y1:
		var tx: float = (wx - x0) / dx if wx != x1 else 1.0
		var ty: float = (wy - y0) / dy if wy != y1 else 1.0
		t = maxf(0.0, minf(t, minf(tx, ty)))
	var sw := st.sweep_circle(x0, y0, x1, y1, r)
	var ob: Dictionary = {}
	if sw[1] >= 0 and sw[0] < t:
		t = sw[0]
		ob = st.obstacles[int(sw[1])]
	return { "len": max_dist * t, "end": [x0 + dx * t, y0 + dy * t], "ob": ob }

## 부채꼴 직접 공격(장애물 가림 적용). 맞으면 true
static func arc_attack(st: CombatState, e: Dictionary, ang: float, R: float, half: float, dmg: float, src: String, color: String = "") -> bool:
	var p := st.player
	var hit := false
	if PGeom.in_arc(e.x, e.y, R, ang, half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
		hit = st.damage_player(dmg, src, e)
	var f := { "kind": "bosssweep", "x": e.x, "y": e.y, "angle": ang, "r": R, "half": half, "ttl": 0.3 }
	if color != "":
		f.color = color
	st.fx(f)
	st.ev("boss_sweep")
	st.note_attack(e, "execute")
	return hit

## 적 투사체 발사(kind = 피해 출처 문자열). 감속장 안에서는 투사체도 느려진다(투사체 규칙)
static func fire(st: CombatState, e: Dictionary, ang: float, S: Dictionary, kind: String) -> Dictionary:
	var speed := float(S.speed)
	var pr := { "owner": "enemy", "kind": kind, "shooter": e, "x": e.x + cos(ang) * e.r, "y": e.y + sin(ang) * e.r, "vx": cos(ang) * speed, "vy": sin(ang) * speed,
		"r": float(S.r), "dmg": float(S.damage), "ttl": float(S.len) / speed, "angle": ang, "width": float(S.get("width", float(S.r) * 2.0)), "dead": false, "hits": {} }
	CombatState.stamp_projectile(e, pr)
	st.projectiles.append(pr)
	return pr

## 직선 돌진 한 단계 진행(거리 기준: 감속되어도 확정 경로·거리 그대로). 반환 true = 끝(길이 도달·충돌)
static func dash_step(st: CombatState, e: Dictionary, speed: float, dmg: float, src: String, dt: float, tf: float) -> bool:
	var p := st.player
	var remain: float = maxf(0.0, float(e.dash_len) - float(e.dash_dist))
	var stp: float = minf(speed * tf * dt, remain)
	var x0: float = e.x
	var y0: float = e.y
	var mv := st.move_swept(e, cos(float(e.dir)) * stp, sin(float(e.dir)) * stp)
	e.dash_dist = float(e.dash_dist) + PGeom.dist(e.x, e.y, x0, y0)
	if not bool(e.hit_done) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
		e.hit_done = true
		e.bite_t = 0.0
		st.ev("bite")
		st.damage_player(dmg, src, e)
	return float(e.dash_dist) >= float(e.dash_len) - 1e-6 or String(mv.hit) != "" or stp <= 1e-9

static func lock_dash(st: CombatState, e: Dictionary, dist: float) -> void:
	e.dir = e.aim_angle
	var path := path_from(st, e.x, e.y, e.r, float(e.dir), dist)
	e.dash_len = float(path.len)
	e.dash_end = path.end
	e.dash_ob = path.get("ob", {}) # 돌파를 세운 장애물(성문 파수장의 충돌 파괴 대상)
	e.dash_dist = 0.0
	e.hit_done = false
	st.ev("boss_lock")

# ---------- 패턴 선택 ----------
## 최소 거리를 못 채운 돌파 계열도, 옆으로 뛰어 스스로 거리를 만들 수 있으면 후보로 남긴다(boss_behavior.json hop.patterns).
## 가까이 붙은 상대에게 후보가 한 종류만 남는 문제(파수장 방패 자세 / 거수 낙석 / 추적자 얼음길 / 사냥왕 발톱)를 없앤다.
static func _hop_ok(e: Dictionary, pat: String) -> bool:
	return (PBoss.hop_cfg(e).get("patterns", []) as Array).has(pat)

## 지금 거리·단계·재사용에서 고를 수 있는 후보 [[이름, 가중치], ...] (PBoss 연계 엔진도 이 목록을 본다)
static func candidates(st: CombatState, e: Dictionary) -> Array:
	var cfg := cfg_of(e)
	var p := st.player
	var d := PGeom.dist(e.x, e.y, p.x, p.y)
	var los: bool = not st.los_blocked(e.x, e.y, p.x, p.y)
	var W: Dictionary = cfg.weights
	var cands: Array = []
	match String(e.boss_id):
		"gate_warden":
			if d <= float(cfg.guard.maxDist):
				cands.append(["guard", float(W.guard)])
			# 시선이 막혀 후보에서 빠지던 행동은, 그 보스의 지형 파괴가 지목한 행동일 때만 되살린다(PBoss.los_ok)
			if d <= float(cfg.breach.maxDist) and PBoss.los_ok(e, los, "breach") and (d >= float(cfg.breach.minDist) or _hop_ok(e, "breach")):
				cands.append(["breach", float(W.breach)])
			if los and (d >= float(cfg.bolts.minDist) or _hop_ok(e, "bolts")):
				cands.append(["bolts", float(W.bolts)])
		"spore_matriarch":
			# 착탄 대기 중에는 새 포자 탄을 겹치지 않는다. markBusy에 적힌 행동만 이을 수 있다(잔여 예고가 모든 출구를 막지 않게)
			var busy: bool = not (e.marks as Array).is_empty()
			var allow: Array = PBoss.beh_e(e).get("markBusy", [])
			if busy and allow.is_empty():
				return []
			if not busy:
				cands.append(["shot", float(W.shot)])
			if d <= float(cfg.ring.maxDist) and (not busy or allow.has("ring")):
				cands.append(["ring", float(W.ring)])
			if d <= float(cfg.spray.maxDist) and los and (not busy or allow.has("spray")):
				cands.append(["spray", float(W.spray)])
			if can_summon(st, e) and (not busy or allow.has("summon")):
				cands.append(["summon", float(W.summon)])
		"excavation_behemoth":
			if d <= float(cfg.burrow.maxDist) and PBoss.los_ok(e, los, "burrow") and (d >= float(cfg.burrow.minDist) or _hop_ok(e, "burrow")):
				cands.append(["burrow", float(W.burrow)])
			cands.append(["rockfall", float(W.rockfall)])
			if can_summon(st, e):
				cands.append(["summon", float(W.summon)])
		"frost_stalker":
			if los and (d >= float(cfg.bolt.minDist) or _hop_ok(e, "bolt")):
				cands.append(["bolt", float(W.bolt)])
			if d >= 80.0:
				cands.append(["icepath", float(W.icepath)])
			if d <= float(cfg.dash.maxDist) and los and (d >= float(cfg.dash.minDist) or _hop_ok(e, "dash")):
				cands.append(["dash", float(W.dash)])
		"blood_hunt_king":
			# 발톱은 준비 중에 달려들 수 있으므로 후보 거리를 개편값으로 넓힐 수 있다(사거리 자체는 그대로)
			if d <= PBoss.pat_num(e, cfg, "claw", "maxDist", 220.0) and PBoss.los_ok(e, los, "claw"):
				cands.append(["claw", float(W.claw)])
			if d <= float(cfg.dash.maxDist) and los and (d >= float(cfg.dash.minDist) or _hop_ok(e, "dash")):
				cands.append(["dash", float(W.dash)])
			if can_summon(st, e):
				cands.append(["summon", float(W.summon)])
		"doom_executor":
			cands.append(["slash", float(W.slash)])
			# 회전 방어 자세는 스스로 걸어서 다가가는 행동이므로 사거리 제한을 개편값으로 넓힐 수 있다
			if d <= PBoss.pat_num(e, cfg, "guard", "maxDist", 9999.0):
				cands.append(["guard", float(W.guard)])
			if can_summon(st, e):
				cands.append(["summon", float(W.summon)])
	return cands

static func choose(st: CombatState, e: Dictionary) -> String:
	var cfg := cfg_of(e)
	var p := st.player
	var d := PGeom.dist(e.x, e.y, p.x, p.y)
	var los: bool = not st.los_blocked(e.x, e.y, p.x, p.y)
	var bid := String(e.boss_id)
	if int(e.actions) == 0: # 첫 행동은 보스마다 정해져 있다(BOSSES.md)
		match bid:
			"gate_warden": return "bolts" if d >= float(cfg.bolts.minDist) else "guard"
			"spore_matriarch": return "shot"
			"excavation_behemoth": return "rockfall"
			"frost_stalker": return "bolt"
			"blood_hunt_king": return "dash"
			"doom_executor": return "slash"
	var cov := PBoss.cover_take(st, e) # 엄폐 대응(지형 파괴)이 예약돼 있으면 그것이 먼저
	if cov != "":
		return cov
	var forced := PBoss.chain_take(st, e) # 연계로 예약된 후속 행동이 먼저
	if forced != "":
		return forced
	# 원래의 고정 연계(BOSSES.md 후반 변주)는 그대로 둔다
	if bid == "frost_stalker" and int(e.phase) >= 2 and _last(e) == "icepath" and d >= float(cfg.dash.minDist) and d <= float(cfg.dash.maxDist) and los:
		return "dash"
	if bid == "doom_executor" and int(e.phase) >= 2 and _last(e) == "slash" and can_summon(st, e):
		return "summon"
	var cands := candidates(st, e)
	if cands.is_empty():
		match bid:
			"gate_warden": return "guard" if d < 220.0 else "bolts"
			"frost_stalker": return "icepath"
			"blood_hunt_king": return "claw" if d < 300.0 else "dash"
	return PBoss._pick_weighted(st, e.history, cands)

static func begin(st: CombatState, e: Dictionary, pat: String) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	e.actions = int(e.actions) + 1
	var h: Array = e.history
	h.append(pat)
	if h.size() > 6:
		h.pop_front()
	e.state_t = 0.0
	e.wait_t = 0.0
	e.hit_done = false
	PBoss.chain_note_begin(e, cfg, pat)
	PBoss.hop_note_begin(st, e, cfg, pat)
	st.note_attack(e, "prepare")
	st.metrics.patterns[pat] = int(st.metrics.patterns.get(pat, 0)) + 1
	e.aim_angle = atan2(p.y - e.y, p.x - e.x)
	match pat:
		"guard":
			if String(e.boss_id) == "doom_executor":
				e.state = "guard"
				e.guard_t = 0.0
				e.guard_real = 0.0
				e.face = e.aim_angle
				st.text(e.x, e.y - e.r - 30.0, "방어 자세(정면만 경감)", "#c8b8ff")
			else:
				e.state = "guard_aim"
				e.guard_real = 0.0
				st.text(e.x, e.y - e.r - 30.0, "방패 자세(정면만 경감)", "#bcd0ff")
		"breach":
			e.state = "breach_aim"
		"bolts":
			e.state = "bolts_aim"
		"shot":
			e.state = "shot_cast"
			e.shot_left = int(cfg.shot.count[mini(2, int(e.phase) - 1)])
			e.shot_timer = 0.0
		"ring":
			e.state = "ring_aim"
			e.ring_gap = st.rng.next() * TAU
			e.ring_half = PGeom.deg(float(cfg.ring.gapDeg[mini(2, int(e.phase) - 1)])) / 2.0
			e.ring_r = 0.0
		"spray":
			e.state = "spray_aim"
		"burrow":
			e.state = "burrow_aim"
			e.dash_seq = 1
			e.dash_total = 2 if int(e.phase) >= 2 else 1
			e.burrow_plan = []
		"rockfall":
			e.state = "rock_cast"
			e.rocks = []
		"bolt":
			e.state = "bolt_aim"
		"icepath":
			e.state = "path_aim"
			e.lanes = []
		"dash":
			if String(e.boss_id) == "frost_stalker":
				e.state = "sidestep"
				var side: float = 1.0 if st.rng.next() < 0.5 else -1.0
				e.side_dir = [-sin(e.aim_angle) * side, cos(e.aim_angle) * side]
			else:
				e.state = "dash_aim"
			e.dash_seq = 1
			e.dash_total = 2 if String(e.boss_id) == "blood_hunt_king" else 1
		"claw":
			e.state = "claw_aim"
		"slash":
			e.state = "slash_warn"
			e.slashes = [{ "x": p.x, "order": 1, "fired": false, "fixed": false }]
			e.slash_idx = 0
		"summon":
			e.state = "summon"
			e.last_summon = st.t
			st.ev("boss_howl")

# ---------- 갱신 ----------
static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	# 예고 배속은 연계 후속타의 준비·고정 구간에만(실행·빈틈·접근 제외). 감속장(tf)은 모든 구간에 그대로 적용된다
	var adv := dt * tf * PBoss.prep_speed(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	var bid := String(e.boss_id)
	if bid == "spore_matriarch":
		update_marks(st, e)
	if bid == "excavation_behemoth":
		update_rocks(st, e, dt)
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
				e.face = atan2(p.y - e.y, p.x - e.x)
				if float(e.approach_t) >= PBoss.min_approach(e, cfg):
					var pat := choose(st, e)
					if pat != "":
						# 겹침 제한(보스 쪽): 소환·호위가 확정·실행 중이면 큰 공격을 잠시 미룬다(최대 bossWaitMax)
						if pat != "summon" and (PBoss2.allies_committed(st) or PBoss.wolf_attacking(st)) and float(e.wait_t) < float(cfg.overlap.bossWaitMax):
							e.wait_t = float(e.wait_t) + adv
						else:
							PBoss.chain_arm(e) # 스스로 고른 행동만 연계로 이어진다
							begin(st, e, pat)
		"roar":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.roar):
				to_approach(st, e)
		"recover":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(e.recover_dur):
				to_approach(st, e)
		"stagger":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.stagger):
				to_approach(st, e)
		"summon":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.summon.duration):
				summon(st, e)
				st.note_attack(e, "execute")
				# 호위 호출은 주공격의 보조: 부른 직후 보스도 바로 다음 행동으로 잇고, 이을 것이 없으면 짧은 빈틈으로 끝난다
				PBoss.summon_end(st, e)
		_:
			match bid:
				"gate_warden": update_warden(st, e, dt, adv, tf)
				"spore_matriarch": update_matriarch(st, e, dt, adv, tf, sm)
				"excavation_behemoth": update_behemoth(st, e, dt, adv, tf)
				"frost_stalker": update_stalker(st, e, dt, adv, tf, sm)
				"blood_hunt_king": update_hunt_king(st, e, dt, adv, tf)
				"doom_executor": update_executor(st, e, dt, adv, tf, sm)
	st.push_out(e) # 굴착·돌진 중에도 지형 통과 없음(몸이 보이는 돌파)

# ---------- 성문 파수장 ----------
static func update_warden(st: CombatState, e: Dictionary, dt: float, adv: float, tf: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var G: Dictionary = cfg.guard
	var B: Dictionary = cfg.breach
	match e.state:
		"guard_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.guard_real = float(e.guard_real) + dt
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(G.aim):
				e.state = "guard_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"guard_lock":
			e.guard_real = float(e.guard_real) + dt
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(G.lock):
				arc_attack(st, e, float(e.dir), float(G.radius), PGeom.deg(float(G.arcDeg)) / 2.0, float(G.damage), "boss_shove")
				to_recover(st, e, float(G.recover), "방패 내림 — 빈틈!")
		"breach_aim":
			PBoss.hop_step(st, e, adv) # 옆으로 뛰어 스스로 돌파 거리를 만든다(예고 각은 계속 추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(B.aim):
				e.state = "breach_lock"
				e.state_t = 0.0
				lock_dash(st, e, float(B.dist))
		"breach_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(B.lock):
				e.state = "breach"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"breach":
			if dash_step(st, e, float(B.speed), float(B.damage), "boss_breach", dt, tf):
				# 성문 파수장의 지형 파괴: **방패로 들이받아 부순다**. 예고된 돌파 선을 세운 그 장애물 하나만
				var bob: Dictionary = e.get("dash_ob", {})
				if not bob.is_empty():
					PBoss.break_do(st, e, [st.obstacles.find(bob)], "gate_warden:breach")
					e.dash_ob = {}
				if int(e.phase) >= 2:
					e.state = "bsweep_aim"
					e.state_t = 0.0
					e.aim_angle = atan2(p.y - e.y, p.x - e.x)
					st.text(e.x, e.y - e.r - 30.0, "넓은 휩쓸기 준비", "#ff9f43")
				else:
					to_recover(st, e, float(B.recover), "방패 내림 — 빈틈!")
		"bsweep_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(B.sweep.aim):
				e.state = "bsweep_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"bsweep_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(B.sweep.lock):
				arc_attack(st, e, float(e.dir), float(B.sweep.radius), PGeom.deg(float(B.sweep.arcDeg)) / 2.0, float(B.sweep.damage), "boss_bsweep")
				to_recover(st, e, float(B.sweep.recover), "방패 내림 — 긴 빈틈!")
		"bolts_aim":
			PBoss.hop_step(st, e, adv) # 옆·뒤로 물러나며 사격 거리를 만든다
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.bolts.aim):
				e.state = "bolts_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"bolts_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.bolts.lock):
				var S: Dictionary = cfg.bolts
				var n: int = int(S.count)
				for i in n:
					fire(st, e, float(e.dir) + PGeom.deg(float(S.spreadDeg)) * (float(i) - float(n - 1) / 2.0), S, "boss_bolt")
				st.ev("shoot")
				st.note_attack(e, "execute")
				to_recover(st, e, float(S.recover))

## 파수장 방패·집행관 방어 자세: 예고된 자세 동안, 정면 부채꼴 안에서 온 직접 공격만 (1-reduce). 옆·뒤·바닥·추가·기술·지속 피해는 정상. 실시간 상한(maxReal) 뒤에는 경감 없음
static func shield_mult(st: CombatState, e: Dictionary, opt: Dictionary) -> float:
	var bid := String(e.get("boss_id", ""))
	if not has(bid):
		return 1.0
	var cfg := cfg_of(e)
	var s := String(e.state)
	var G: Dictionary
	var face_ang: float
	if bid == "gate_warden" and (s == "guard_aim" or s == "guard_lock"):
		G = cfg.guard
		face_ang = float(e.aim_angle) if s == "guard_aim" else float(e.dir)
	elif bid == "doom_executor" and s == "guard":
		G = cfg.guard
		face_ang = float(e.get("face", 0.0))
	else:
		return 1.0
	if float(e.get("guard_real", 0.0)) > float(G.maxReal):
		return 1.0
	var sr: Dictionary = opt.get("src", {})
	if not bool(sr.get("direct", true)) or bool(sr.get("extra", false)) or bool(sr.get("skill", false)) or opt.has("dot"):
		return 1.0
	var from: Dictionary = opt.get("from", st.player)
	var a: float = atan2(float(from.y) - e.y, float(from.x) - e.x)
	if absf(PGeom.ang_diff(face_ang, a)) <= PGeom.deg(float(G.frontDeg)) / 2.0:
		return 1.0 - float(G.reduce)
	return 1.0

## 방패 경감이 지금 유효한가(표시용)
static func guard_active(e: Dictionary) -> bool:
	var bid := String(e.get("boss_id", ""))
	if not has(bid):
		return false
	var s := String(e.state)
	var on: bool = (bid == "gate_warden" and (s == "guard_aim" or s == "guard_lock")) or (bid == "doom_executor" and s == "guard")
	return on and float(e.get("guard_real", 0.0)) <= float(cfg_of(e).guard.maxReal)

# ---------- 포자 어미 ----------
static func update_matriarch(st: CombatState, e: Dictionary, dt: float, adv: float, _tf: float, sm: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var S: Dictionary = cfg.shot
	var R: Dictionary = cfg.ring
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match e.state:
		"shot_cast":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(S.cast):
				_place_shot(st, e, 1)
				e.shot_left = int(e.shot_left) - 1
				e.shot_timer = float(S.gap)
				e.state = "shot_wait"
				e.state_t = 0.0
				st.ev("boss_lock")
		"shot_wait":
			e.state_t = float(e.state_t) + adv
			if int(e.shot_left) > 0:
				e.shot_timer = float(e.shot_timer) - adv
				if float(e.shot_timer) <= 0.0:
					_place_shot(st, e, (e.marks as Array).size() + 1)
					e.shot_left = int(e.shot_left) - 1
					e.shot_timer = float(S.gap)
			elif (e.marks as Array).is_empty():
				to_recover(st, e, float(S.recover))
			elif PBoss.chain_early(st, e, "shot", float(e.state_t)):
				pass # 다음 행동으로 넘어갔다(남은 포자 탄은 계속 제 시각에 떨어진다)
		"ring_aim":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(R.aim):
				e.state = "ring_lock"
				e.state_t = 0.0
				st.ev("boss_lock")
		"ring_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(R.lock):
				e.state = "ring"
				e.state_t = 0.0
				e.ring_r = e.r
				e.hit_done = false
				st.note_attack(e, "execute")
				st.ev("boss_land")
		"ring":
			e.ring_r = float(e.ring_r) + float(R.speed) * adv
			if not bool(e.hit_done) and ring_hits(e, float(R.width), p.x, p.y, p.r):
				e.hit_done = true
				st.damage_player(float(R.damage), "boss_ring", e)
			if float(e.ring_r) >= float(R.maxR):
				to_recover(st, e, float(R.recover))
		"spray_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			if dist > float(cfg.spray.radius) * 0.6:
				st.approach(e, p.x, p.y, float(cfg.speed) * sm, dt) # 느린 몸통 접근
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.spray.aim):
				e.state = "spray_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"spray_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.spray.lock):
				arc_attack(st, e, float(e.dir), float(cfg.spray.radius), PGeom.deg(float(cfg.spray.arcDeg)) / 2.0, float(cfg.spray.damage), "boss_spray", "#c090ff")
				to_recover(st, e, float(cfg.spray.recover), "분사 뒤 정지 — 빈틈!")

static func _place_shot(st: CombatState, e: Dictionary, order: int) -> void:
	var S: Dictionary = cfg_of(e).shot
	var p := st.player
	# 파괴 자격이 포자 탄에 걸려 있으면("저 나무를 삭힌다!") 착탄 원이 그 나무를 덮을 만큼만 조준을 옮긴다.
	# 예고 원과 실제 착탄이 같은 값이라 화면에 뜬 원이 곧 삭을 자리다. 개수·시각·반지름은 그대로
	var sp: Array = PBoss.break_point(st, e, "shot", p.x, p.y, float(S.r))
	(e.marks as Array).append({ "x": float(sp[0]), "y": float(sp[1]), "r": float(S.r), "land_at": st.t + float(S.delay), "order": order, "done": false })
	st.text(float(sp[0]), float(sp[1]) - 30.0, "포자 탄 %d" % order, "#e0c0ff")

## 고리 판정: 띠(ring_r ± width/2) 안이고 빈 구간 밖일 때만. 빈 구간은 플레이어 중심 각 기준(그림과 같은 각도)
static func ring_hits(e: Dictionary, width: float, px: float, py: float, pr: float) -> bool:
	var d := PGeom.dist(e.x, e.y, px, py)
	if absf(d - float(e.ring_r)) > width / 2.0 + pr:
		return false
	var a := atan2(py - e.y, px - e.x)
	return absf(PGeom.ang_diff(float(e.ring_gap), a)) > float(e.ring_half)

## 포자 탄 착탄: 정해진 시각에 표시된 원. 감속장은 착탄 시계를 늦추지 않는다(위치 기반 예고, 먹는 자 표식과 같은 규칙). 잔류 구름은 상한·수명 제한
static func update_marks(st: CombatState, e: Dictionary) -> void:
	var S: Dictionary = cfg_of(e).shot
	var p := st.player
	var keep: Array = []
	for mk in e.marks:
		if st.t < float(mk.land_at):
			keep.append(mk)
			continue
		mk.done = true
		# 포자 어미의 지형 파괴: **포자 부식**. 예고된 착탄 원 안의 **나무만** 삭아 무너진다(바위는 삭지 않는다).
		# 피해 판정보다 먼저 일어나므로 화면에서 먼저 읽힌다
		PBoss.break_do(st, e, PTerrain.pick_circle(st.arena_w, st.arena_h, st.obstacles, float(mk.x), float(mk.y), float(mk.r), PBoss.breaker_of(e).get("types", [])), "spore_matriarch:shot")
		if PGeom.dist(float(mk.x), float(mk.y), p.x, p.y) <= float(mk.r) + p.r:
			st.damage_player(float(S.damage), "boss_spore_shot", e)
		st.fx({ "kind": "burst", "x": float(mk.x), "y": float(mk.y), "r": float(mk.r), "ttl": 0.35, "color": "#c080ff" })
		st.ev("explode")
		st.note_attack(e, "execute")
		var clouds := 0
		for z in st.zones:
			if z.type == "spore" and String(z.get("owner", "")) == "boss":
				clouds += 1
		if clouds < int(S.cloudCap):
			var z := st.add_zone("spore", float(mk.x), float(mk.y), float(mk.r) * 0.8, float(S.cloudTtl), float(S.cloudDmg))
			z.owner = "boss"
	e.marks = keep

# ---------- 굴착 거수 ----------
static func update_behemoth(st: CombatState, e: Dictionary, dt: float, adv: float, tf: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var B: Dictionary = cfg.burrow
	var RK: Dictionary = cfg.rockfall
	match e.state:
		"burrow_aim":
			PBoss.hop_step(st, e, adv) # 몸을 틀어 스스로 굴착 거리를 만든다(예고 각은 계속 추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(B.aim):
				e.state = "burrow_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				# 굴착 거수의 지형 파괴: **멈추지 않고 관통한다**. 방향을 확정하는 순간 경로 위의 엄폐물이 먼저 부서지고,
				# 그 뒤에 길어진 경로를 예고로 보여 준 다음(lock 0.4초) 돌파가 시작된다 — 파괴가 피해 판정보다 먼저 읽힌다
				PBoss.break_do(st, e, PTerrain.pick_segment(st.arena_w, st.arena_h, st.obstacles, e.x, e.y,
					e.x + cos(float(e.dir)) * float(B.dist), e.y + sin(float(e.dir)) * float(B.dist), e.r, PBoss.breaker_of(e).get("types", [])), "excavation_behemoth:burrow")
				# 두 방향을 순서대로 미리 확정(2단계~): 첫 경로 끝에서 그 순간 플레이어 방향
				var plan: Array = []
				var p1 := path_from(st, e.x, e.y, e.r, float(e.dir), float(B.dist))
				plan.append({ "x": e.x, "y": e.y, "ang": float(e.dir), "len": float(p1.len), "end": p1.end })
				if int(e.dash_total) >= 2:
					var ex: float = float(p1.end[0])
					var ey: float = float(p1.end[1])
					var a2 := atan2(p.y - ey, p.x - ex)
					var p2 := path_from(st, ex, ey, e.r, a2, float(B.dist))
					plan.append({ "x": ex, "y": ey, "ang": a2, "len": float(p2.len), "end": p2.end })
				e.burrow_plan = plan
				e.dash_len = float(plan[0].len)
				e.dash_end = plan[0].end
				e.dash_dist = 0.0
				e.hit_done = false
				st.ev("boss_lock")
		"burrow_lock":
			e.state_t = float(e.state_t) + adv
			var lk: float = float(B.lock) if int(e.dash_seq) == 1 else float(B.lock2)
			if float(e.state_t) >= lk:
				e.state = "burrow"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"burrow":
			if dash_step(st, e, float(B.speed), float(B.damage), "boss_burrow", dt, tf):
				if int(e.dash_seq) < int(e.dash_total):
					e.dash_seq = int(e.dash_seq) + 1
					var nxt: Dictionary = e.burrow_plan[int(e.dash_seq) - 1]
					e.dir = float(nxt.ang)
					e.dash_len = float(nxt.len)
					e.dash_end = nxt.end
					e.dash_dist = 0.0
					e.hit_done = false
					e.state = "burrow_lock"
					e.state_t = 0.0
					st.text(e.x, e.y - e.r - 30.0, "굴착 2/2", "#ff9f43")
				else:
					to_recover(st, e, float(B.doubleRecover) if int(e.dash_total) > 1 else float(B.recover), "잔해에 멈춤 — 빈틈!")
		"rock_cast":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(RK.cast):
				_place_rocks(st, e)
				e.state = "rock_wait"
				e.state_t = 0.0
				st.ev("boss_lock")
				st.ev("hazard_warn")
		"rock_wait":
			e.state_t = float(e.state_t) + adv
			var pending := false
			for rk in e.rocks:
				if not bool(rk.done):
					pending = true
			if not pending:
				to_recover(st, e, float(RK.recover))
			elif PBoss.chain_early(st, e, "rockfall", float(e.state_t)):
				pass # 다음 행동으로 넘어갔다(남은 낙석은 계속 제 시각에 떨어진다)

## 낙석 세 구역: 플레이어가 움직이는 방향(안 움직이면 보스→플레이어 방향)으로 1→2→3 줄지어. 낙하 시각은 명시적 순차(warn + i·gap). 출구 검사로 모든 방향이 막히면 옆으로 옮기거나 생략
static func _place_rocks(st: CombatState, e: Dictionary) -> void:
	var RK: Dictionary = cfg_of(e).rockfall
	var p := st.player
	var mv_ang: float = p.face if bool(p.moving) else atan2(p.y - e.y, p.x - e.x)
	var rocks: Array = []
	for i in int(RK.count):
		var cx: float = p.x + cos(mv_ang) * float(RK.spacing) * float(i)
		var cy: float = p.y + sin(mv_ang) * float(RK.spacing) * float(i)
		var cand: Dictionary = _rock_candidate(st, e, cx, cy, float(RK.r), rocks, mv_ang)
		if cand.is_empty():
			continue
		cand.land_at = st.t + float(RK.warn) + float(rocks.size()) * float(RK.gap)
		cand.order = rocks.size() + 1
		cand.done = false
		rocks.append(cand)
	e.rocks = rocks

static func _rock_candidate(st: CombatState, e: Dictionary, cx: float, cy: float, r: float, rocks: Array, mv_ang: float) -> Dictionary:
	var RK: Dictionary = cfg_of(e).rockfall
	var offs: Array = [[0.0, 0.0], [1.0, 0.0], [-1.0, 0.0]]
	for o in offs:
		var x: float = clampf(cx + (-sin(mv_ang)) * float(o[0]) * (r + 30.0), r, st.arena_w - r)
		var y: float = clampf(cy + cos(mv_ang) * float(o[0]) * (r + 30.0), r, st.arena_h - r)
		var trial: Dictionary = { "x": x, "y": y, "r": r }
		var all: Array = rocks.duplicate()
		all.append(trial)
		if exits_open(st, e, all) >= int(RK.minExits):
			return trial
	return {}

## 플레이어 주위 16방향 중 probe 거리 지점이 위험(낙석 예고·잔해)에 덮이지 않은 방향 수
static func exits_open(st: CombatState, e: Dictionary, rocks: Array) -> int:
	var RK: Dictionary = cfg_of(e).rockfall
	var p := st.player
	var probe := float(RK.probe)
	var dangers: Array = rocks.duplicate()
	for z in st.zones:
		if z.type == "rubble":
			dangers.append({ "x": z.x, "y": z.y, "r": z.r })
	var free := 0
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var x: float = p.x + cos(a) * probe
		var y: float = p.y + sin(a) * probe
		if x < p.r or y < p.r or x > st.arena_w - p.r or y > st.arena_h - p.r:
			continue
		var blocked := false
		for d in dangers:
			if PGeom.dist(float(d.x), float(d.y), x, y) <= float(d.r) + p.r:
				blocked = true
				break
		if not blocked:
			free += 1
	return free

## 낙석 착지(정해진 시각, 순차) + 잔해 피해(0.5초마다, 서 있을 때만). 감속장은 착지 시계를 늦추지 않는다(위치 기반 예고)
static func update_rocks(st: CombatState, e: Dictionary, dt: float) -> void:
	var RK: Dictionary = cfg_of(e).rockfall
	var p := st.player
	for rk in e.rocks:
		if bool(rk.done) or st.t < float(rk.land_at):
			continue
		rk.done = true
		if PGeom.dist(float(rk.x), float(rk.y), p.x, p.y) <= float(rk.r) + p.r:
			st.damage_player(float(RK.damage), "boss_rockfall", e)
		st.fx({ "kind": "bossland", "x": float(rk.x), "y": float(rk.y), "r": float(rk.r), "ttl": 0.45 })
		st.ev("boss_land")
		st.note_attack(e, "execute")
		var z := st.add_zone("rubble", float(rk.x), float(rk.y), float(rk.r), float(RK.rubbleTtl), float(RK.rubbleDmg))
		z.owner = "boss"
	e.rubble_tick = float(e.rubble_tick) - dt
	if float(e.rubble_tick) <= 0.0:
		e.rubble_tick = 0.0
		for z in st.zones:
			if z.type == "rubble" and PGeom.dist(z.x, z.y, p.x, p.y) <= z.r + p.r * 0.5:
				if st.damage_player(float(z.dmg), "boss_rubble", e):
					e.rubble_tick = float(RK.rubbleTick)
				break

# ---------- 서리 추적자 ----------
static func update_stalker(st: CombatState, e: Dictionary, dt: float, adv: float, tf: float, _sm: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var D: Dictionary = cfg.dash
	var I: Dictionary = cfg.icepath
	match e.state:
		"bolt_aim":
			PBoss.hop_step(st, e, adv) # 옆·뒤로 미끄러지며 사격 거리를 만든다
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.bolt.aim):
				e.state = "bolt_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"bolt_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(cfg.bolt.lock):
				fire(st, e, float(e.dir), cfg.bolt, "boss_icebolt")
				st.ev("shoot")
				st.note_attack(e, "execute")
				to_recover(st, e, float(cfg.bolt.recover))
		"path_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(I.aim):
				e.state = "path_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				e.lanes = lane_angles(e, I)
				st.ev("boss_lock")
		"path_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(I.lock):
				# 서리 추적자의 지형 파괴: **얼려서 깨뜨린다**. 예고된 세 줄이 지나는 엄폐물이 피해 판정보다 먼저 부서진다
				var bk: Array = []
				for la in e.lanes:
					for bi in PTerrain.pick_segment(st.arena_w, st.arena_h, st.obstacles, e.x, e.y,
						e.x + cos(float(la)) * float(I.len), e.y + sin(float(la)) * float(I.len), float(I.width) / 2.0, PBoss.breaker_of(e).get("types", [])):
						if not bk.has(bi):
							bk.append(bi)
				PBoss.break_do(st, e, bk, "frost_stalker:icepath")
				var hit := false
				for a in e.lanes:
					if not hit and PGeom.in_beam(e.x, e.y, float(a), float(I.len), float(I.width), p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
						hit = st.damage_player(float(I.damage), "boss_icepath", e)
					lay_ice(st, e, float(a), I)
				st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": e.r + 20.0, "ttl": 0.3, "color": "#bfefff" })
				st.ev("shatter")
				st.note_attack(e, "execute")
				to_recover(st, e, float(I.recover))
		"sidestep":
			# 옆으로 이동: 몸은 그대로 맞는다(무적 없음). 감속장 안에서는 느리게
			var spd: float = float(D.sideDist) / float(D.side)
			st.move_swept(e, float(e.side_dir[0]) * spd * adv, float(e.side_dir[1]) * spd * adv)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.side):
				e.state = "dash_aim"
				e.state_t = 0.0
		"dash_aim":
			PBoss.hop_step(st, e, adv) # 옆 이동에 더해, 거리가 모자라면 한 번 더 스스로 거리를 만든다
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.aim):
				e.state = "dash_lock"
				e.state_t = 0.0
				lock_dash(st, e, float(D.dist))
		"dash_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.lock):
				e.state = "dash"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"dash":
			if dash_step(st, e, float(D.speed), float(D.damage), "boss_dash", dt, tf):
				to_recover(st, e, float(D.recover))

static func lane_angles(e: Dictionary, I: Dictionary) -> Array:
	var out: Array = []
	var n: int = int(I.lanes)
	for i in n:
		out.append(float(e.dir) + PGeom.deg(float(I.spreadDeg)) * (float(i) - float(n - 1) / 2.0))
	return out

## 얼음길 한 줄: 줄을 따라 빙판 원을 놓는다(장애물 안은 생략). 동시 상한을 넘으면 오래된 것부터 지운다. 빙판은 플레이어 이동 속도만 줄인다(CombatState.update_player)
static func lay_ice(st: CombatState, e: Dictionary, ang: float, I: Dictionary) -> void:
	var s: float = e.r + float(I.iceStep) * 0.5
	while s <= float(I.len):
		var x: float = e.x + cos(ang) * s
		var y: float = e.y + sin(ang) * s
		s += float(I.iceStep)
		if not st.valid_pos(x, y, 0.0):
			continue
		var z := st.add_zone("ice", x, y, float(I.iceR), float(I.iceTtl), 0.0)
		z.slow = float(I.slow)
		z.owner = "boss"
	var ice: Array = []
	for z in st.zones:
		if z.type == "ice":
			ice.append(z)
	var over: int = ice.size() - int(I.iceCap)
	for i in maxi(0, over):
		ice[i].ttl = 0.0

# ---------- 핏빛 사냥왕 ----------
static func update_hunt_king(st: CombatState, e: Dictionary, dt: float, adv: float, tf: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var D: Dictionary = cfg.dash
	var C: Dictionary = cfg.claw
	match e.state:
		"claw_aim":
			# 발톱은 준비 중에 달려들며 친다(이동 중 공격). 예고 부채꼴은 보스 몸을 따라오므로 화면·봇이 보는 것과 실제가 같다
			if PGeom.dist(e.x, e.y, p.x, p.y) > float(C.radius) * PBoss.pat_num(e, cfg, "claw", "closeFrac", 9.0):
				st.approach(e, p.x, p.y, float(cfg.speed) * st.enemy_speed_mult(e) * PBoss.pat_num(e, cfg, "claw", "rushMult", 1.0), dt)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(C.aim):
				e.state = "claw_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"claw_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(C.lock):
				# 핏빛 사냥왕의 지형 파괴: **숨은 곳째 찢는다**. 예고된 부채꼴 안의 엄폐물이 피해 판정보다 먼저 사라진다
				PBoss.break_do(st, e, PTerrain.pick_arc(st.arena_w, st.arena_h, st.obstacles, e.x, e.y, float(e.dir), float(C.radius), PGeom.deg(float(C.arcDeg)) / 2.0, PBoss.breaker_of(e).get("types", [])), "blood_hunt_king:claw")
				arc_attack(st, e, float(e.dir), float(C.radius), PGeom.deg(float(C.arcDeg)) / 2.0, float(C.damage), "boss_claw")
				to_recover(st, e, float(C.recover))
		"dash_aim":
			PBoss.hop_step(st, e, adv) # 옆으로 뛰어 스스로 돌진 거리를 만든다(예고 각은 계속 추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.aim):
				e.state = "dash_lock"
				e.state_t = 0.0
				lock_dash(st, e, float(D.dist))
		"dash_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.lock):
				e.state = "dash"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"dash":
			if dash_step(st, e, float(D.speed), float(D.damage), "boss_dash", dt, tf):
				if int(e.dash_seq) < int(e.dash_total):
					e.dash_seq = int(e.dash_seq) + 1
					e.state = "dash_reaim" # 재조준: 이 자리(재조준 표식)에서 새 방향을 찾는다
					e.state_t = 0.0
					e.aim_angle = atan2(p.y - e.y, p.x - e.x)
					st.text(e.x, e.y - e.r - 30.0, "재조준 2/2", "#ff9f43")
				else:
					to_recover(st, e, float(D.recover), "연속 돌진 끝 — 긴 빈틈!")
		"dash_reaim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.reaim):
				e.state = "dash_relock"
				e.state_t = 0.0
				lock_dash(st, e, float(D.dist)) # 새 방향 고정 시점: 여기서만 확정된다
				st.text(e.x, e.y - e.r - 30.0, "방향 고정!", "#ff7070")
		"dash_relock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(D.relock):
				e.state = "dash"
				e.state_t = 0.0
				st.note_attack(e, "execute")

# ---------- 종말의 집행관 ----------
## 3막 관문(종말의 집행관) 위치 변주 — 사용자 평가가 좋은 방향을 보존하는 '제한적' 변주(시험값, data/boss_behavior.json gapStep).
## 절단선 1번과 2번 사이(gap)에 보스만 옆으로 파고든다. 절단선은 플레이어 x를 기준으로 놓이므로
## 예고 시간·선 위치·피해·빈틈은 하나도 바뀌지 않는다(기존 대응 '좌우로 한 걸음'은 그대로 통한다).
## 바뀌는 것은 연계 다음 행동(큰 베기·호위 호출)이 오는 방향뿐이다. 예고 없는 새 판정은 만들지 않는다.
static func gap_step(st: CombatState, e: Dictionary, dt: float, sm: float) -> void:
	var V: Dictionary = PBoss.beh_e(e).get("gapStep", {})
	if V.is_empty():
		return
	var p := st.player
	var a: float = atan2(p.y - e.y, p.x - e.x) + PI / 2.0 * float(e.get("gap_side", 1.0))
	var spd: float = float(V.get("speed", 150.0)) * sm
	st.move_swept(e, cos(a) * spd * dt, sin(a) * spd * dt, true)

static func update_executor(st: CombatState, e: Dictionary, dt: float, adv: float, _tf: float, sm: float) -> void:
	var cfg := cfg_of(e)
	var p := st.player
	var SL: Dictionary = cfg.slash
	var G: Dictionary = cfg.guard
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match e.state:
		"slash_warn":
			var s0: Dictionary = e.slashes[0]
			# 예고 중엔 따라온다. 파괴 자격이 절단선에 걸려 있으면("선 위의 모든 것을 벤다!")
			# 지목한 엄폐물이 띠 안에 들어올 만큼만 선을 옮긴다 — 예고 선과 실제 판정이 같은 값이다
			s0.x = PBoss.break_column_x(st, e, "slash", p.x, float(SL.width) / 2.0)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(SL.warn):
				s0.fixed = true
				e.state = "slash_lock"
				e.state_t = 0.0
				st.ev("boss_lock")
		"slash_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(SL.lock):
				var sl: Dictionary = e.slashes[int(e.slash_idx)]
				var half: float = float(SL.width) / 2.0
				# 종말의 집행관의 지형 파괴: **세로 절단선이 지형째 가른다**. 예고된 선 위의 엄폐물이 피해 판정보다 먼저 갈라진다
				PBoss.break_do(st, e, PTerrain.pick_column(st.arena_w, st.arena_h, st.obstacles, float(sl.x), float(SL.width), PBoss.breaker_of(e).get("types", [])), "doom_executor:slash")
				if absf(p.x - float(sl.x)) <= half + p.r:
					st.damage_player(float(SL.damage), "boss_slash", e)
				sl.fired = true
				st.fx({ "kind": "slashline", "x": float(sl.x), "y": 0.0, "w": float(SL.width), "h": st.arena_h, "ttl": 0.3, "order": int(sl.order) })
				st.ev("boss_sweep")
				st.note_attack(e, "execute")
				e.slash_idx = int(e.slash_idx) + 1
				if int(e.slash_idx) < int(SL.count):
					# 2번 선은 1번이 떨어지는 순간 고정(시간차 gap+lock). 순서 번호·색이 다르다.
					# 파괴 자격이 남아 있으면(1번이 지목한 것을 못 갈랐다) 2번 선도 그 엄폐물을 띠 안에 넣을 만큼만 옮긴다
					(e.slashes as Array).append({ "x": PBoss.break_column_x(st, e, "slash", p.x, half),
						"order": int(e.slash_idx) + 1, "fired": false, "fixed": true })
					e.state = "slash_gap"
					e.state_t = 0.0
					e.gap_side = 1.0 if int(e.actions) % 2 == 0 else -1.0 # 번갈아(난수 소비 없음)
				else:
					to_recover(st, e, float(SL.recover))
		"slash_gap":
			e.state_t = float(e.state_t) + adv
			gap_step(st, e, dt, sm)
			if float(e.state_t) >= PBoss.pat_num(e, cfg, "slash", "gap", float(SL.gap)):
				e.state = "slash_lock"
				e.state_t = 0.0
				st.ev("boss_lock")
		"guard":
			# 천천히 회전하는 정면 방어 자세: 정면 직접 피해만 경감(shield_mult). 느리게 다가온다. 상한 dur(진행) / maxReal(실시간)
			e.guard_real = float(e.guard_real) + dt
			var want: float = atan2(p.y - e.y, p.x - e.x)
			var diff := PGeom.ang_diff(float(e.face), want)
			var max_turn: float = float(G.turnRate) * adv
			e.face = float(e.face) + clampf(diff, -max_turn, max_turn)
			if dist > float(G.strike.radius) * 0.6:
				st.approach(e, p.x, p.y, float(cfg.speed) * float(G.speedMult) * sm, dt)
			e.guard_t = float(e.guard_t) + adv
			var close: bool = dist <= float(G.strike.radius) and absf(diff) < PGeom.deg(30.0)
			# 자세 유지 시간은 '걸어오는 시간'이지 예고가 아니다 — 개편값으로 줄일 수 있다(큰 베기의 예고 0.5/0.3은 그대로)
			var g_dur := PBoss.pat_num(e, cfg, "guard", "dur", float(G.dur))
			var g_min := PBoss.pat_num(e, cfg, "guard", "minDur", float(G.minDur))
			if float(e.guard_t) >= g_dur or (float(e.guard_t) >= g_min and close):
				e.state = "gstrike_aim"
				e.state_t = 0.0
				e.aim_angle = float(e.face)
		"gstrike_aim":
			e.guard_real = float(e.guard_real) + dt
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(G.strike.aim):
				e.state = "gstrike_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"gstrike_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(G.strike.lock):
				arc_attack(st, e, float(e.dir), float(G.strike.radius), PGeom.deg(float(G.strike.arcDeg)) / 2.0, float(G.strike.damage), "boss_gstrike", "#c8b8ff")
				to_recover(st, e, float(G.recover), "자세 해제 — 빈틈!")

# ---------- 소환 ----------
static func summon(st: CombatState, e: Dictionary) -> void:
	var bid := String(e.boss_id)
	if bid == "blood_hunt_king" and int(e.phase) >= 2:
		_summon_arc(st, e, atan2(e.y - st.player.y, e.x - st.player.x) + (PI / 2.0 if st.rng.next() < 0.5 else -PI / 2.0), PGeom.deg(float(cfg_of(e).summon.flankDeg)), false)
	elif bid == "doom_executor":
		_summon_arc(st, e, atan2(e.y - st.player.y, e.x - st.player.x), PGeom.deg(float(cfg_of(e).summon.sideDeg)) * 2.0, true)
	else:
		PBoss2.summon(st, e)

## 플레이어 주위 호(center_ang ± span/2)의 링에 배치. two_sides=true면 양 끝(두 방향)에 하나씩. 상한·예산·간격은 PBoss2.summon과 같은 규칙
static func _summon_arc(st: CombatState, e: Dictionary, center_ang: float, span: float, two_sides: bool) -> void:
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
		while i < 8 and placed < n:
			var a: float
			if two_sides:
				a = center_ang + (span / 2.0) * (1.0 if (placed + i) % 2 == 0 else -1.0) + floor(float(i) / 2.0) * 0.25
			else:
				a = center_ang - span / 2.0 + span * (float(i) + 0.5) / 8.0
			var x: float = p.x + cos(a) * float(rr)
			var y: float = p.y + sin(a) * float(rr)
			var type := String(pool[(int(e.summon_budget) + placed) % pool.size()])
			i += 1
			if not st.valid_pos(x, y, float(PCatalog.enemy(type).r)) or PGeom.dist(x, y, p.x, p.y) < 110.0:
				continue
			var near := false
			for s in st.pending:
				if PGeom.dist(float(s.x), float(s.y), x, y) < 40.0:
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

# ---------- 위협 도형(봇·화면 공용 기하) ----------
## out에 {kind:"beam"|"circle"|"arc"|"zone", e, x, y, ang, len, w, r, half, prog, locked, label, order} 추가
static func threats(st: CombatState, bz: Dictionary, out: Array) -> void:
	var cfg := cfg_of(bz)
	var p := st.player
	var s := String(bz.state)
	var st_t := float(bz.state_t)
	var bid := String(bz.boss_id)
	match bid:
		"gate_warden":
			if s == "guard_aim" or s == "guard_lock":
				var G: Dictionary = cfg.guard
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": facing(bz), "r": float(G.radius) + 20.0, "half": PGeom.deg(float(G.arcDeg)) / 2.0 + 0.2, "prog": (st_t / float(G.aim)) if s == "guard_aim" else 1.0, "locked": s == "guard_lock" })
			if s == "breach_aim":
				var B: Dictionary = cfg.breach
				var path := path_from(st, bz.x, bz.y, bz.r, float(bz.aim_angle), float(B.dist))
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "len": float(path.len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": st_t / float(B.aim), "locked": false })
			if s == "breach_lock" or s == "breach":
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "len": float(bz.dash_len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": 1.0, "locked": true })
			if s == "bsweep_aim" or s == "bsweep_lock":
				var SW: Dictionary = cfg.breach.sweep
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": facing(bz), "r": float(SW.radius) + 30.0, "half": PGeom.deg(float(SW.arcDeg)) / 2.0 + 0.2, "prog": (st_t / float(SW.aim)) if s == "bsweep_aim" else 1.0, "locked": s == "bsweep_lock" })
			if s == "bolts_aim" or s == "bolts_lock":
				var BL: Dictionary = cfg.bolts
				var n: int = int(BL.count)
				for i in n:
					var a: float = facing(bz) + PGeom.deg(float(BL.spreadDeg)) * (float(i) - float(n - 1) / 2.0)
					out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": a, "len": float(BL.len), "w": float(BL.width) + 30.0, "prog": (st_t / float(BL.aim)) if s == "bolts_aim" else 1.0, "locked": s == "bolts_lock", "order": i + 1 })
		"spore_matriarch":
			for mk in bz.marks:
				out.append({ "kind": "circle", "e": bz, "x": float(mk.x), "y": float(mk.y), "r": float(mk.r) + 10.0, "prog": minf(1.0, 1.0 - (float(mk.land_at) - st.t) / float(cfg.shot.delay)), "locked": float(mk.land_at) - st.t < 0.5, "order": int(mk.order) })
			if s == "ring_aim" or s == "ring_lock" or s == "ring":
				var R: Dictionary = cfg.ring
				var rr: float = float(bz.ring_r) + float(R.width) / 2.0 if s == "ring" else float(R.maxR)
				# 빈 구간을 뺀 호(봇은 부채꼴 바깥으로 달아난다). 빈 구간 자체는 기하로 노출: gap_ang·gap_half
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.ring_gap) + PI, "r": rr + 10.0, "half": PI - float(bz.ring_half), "prog": (st_t / float(R.aim)) if s == "ring_aim" else 1.0, "locked": s != "ring_aim", "gap_ang": float(bz.ring_gap), "gap_half": float(bz.ring_half), "ring": true })
			if s == "spray_aim" or s == "spray_lock":
				var SP: Dictionary = cfg.spray
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": facing(bz), "r": float(SP.radius) + 20.0, "half": PGeom.deg(float(SP.arcDeg)) / 2.0 + 0.2, "prog": (st_t / float(SP.aim)) if s == "spray_aim" else 1.0, "locked": s == "spray_lock" })
		"excavation_behemoth":
			var B: Dictionary = cfg.burrow
			if s == "burrow_aim":
				var path := path_from(st, bz.x, bz.y, bz.r, float(bz.aim_angle), float(B.dist))
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "len": float(path.len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": st_t / float(B.aim), "locked": false, "order": 1 })
			if s == "burrow_lock" or s == "burrow":
				var plan: Array = bz.burrow_plan
				for i in plan.size():
					if i < int(bz.dash_seq) - 1:
						continue
					var pl: Dictionary = plan[i]
					var ox: float = bz.x if i == int(bz.dash_seq) - 1 else float(pl.x)
					var oy: float = bz.y if i == int(bz.dash_seq) - 1 else float(pl.y)
					out.append({ "kind": "beam", "e": bz, "x": ox, "y": oy, "ang": float(pl.ang), "len": float(pl.len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": 1.0, "locked": true, "order": i + 1 })
			for rk in bz.rocks:
				if not bool(rk.done):
					out.append({ "kind": "circle", "e": bz, "x": float(rk.x), "y": float(rk.y), "r": float(rk.r) + 10.0, "prog": minf(1.0, 1.0 - (float(rk.land_at) - st.t) / float(cfg.rockfall.warn)), "locked": float(rk.land_at) - st.t < 0.5, "order": int(rk.order) })
		"frost_stalker":
			var D: Dictionary = cfg.dash
			if s == "bolt_aim" or s == "bolt_lock":
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": facing(bz), "len": float(cfg.bolt.len), "w": float(cfg.bolt.width) + 30.0, "prog": (st_t / float(cfg.bolt.aim)) if s == "bolt_aim" else 1.0, "locked": s == "bolt_lock" })
			if s == "path_aim" or s == "path_lock":
				var I: Dictionary = cfg.icepath
				var angs: Array = bz.lanes if s == "path_lock" else lane_angles({ "dir": float(bz.aim_angle) }, I)
				for i in angs.size():
					out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(angs[i]), "len": float(I.len), "w": float(I.width) + 20.0, "prog": (st_t / float(I.aim)) if s == "path_aim" else 1.0, "locked": s == "path_lock", "order": i + 1 })
			if s == "dash_aim":
				var path := path_from(st, bz.x, bz.y, bz.r, float(bz.aim_angle), float(D.dist))
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "len": float(path.len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": st_t / float(D.aim), "locked": false })
			if s == "dash_lock" or s == "dash":
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "len": float(bz.dash_len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": 1.0, "locked": true })
		"blood_hunt_king":
			var D: Dictionary = cfg.dash
			if s == "claw_aim" or s == "claw_lock":
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": facing(bz), "r": float(cfg.claw.radius) + 30.0, "half": PGeom.deg(float(cfg.claw.arcDeg)) / 2.0 + 0.2, "prog": (st_t / float(cfg.claw.aim)) if s == "claw_aim" else 1.0, "locked": s == "claw_lock" })
			if s == "dash_aim" or s == "dash_reaim":
				var path := path_from(st, bz.x, bz.y, bz.r, float(bz.aim_angle), float(D.dist))
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "len": float(path.len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": st_t / (float(D.aim) if s == "dash_aim" else float(D.reaim)), "locked": false, "order": int(bz.dash_seq), "reaim": s == "dash_reaim" })
			if s == "dash_lock" or s == "dash_relock" or s == "dash":
				out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "len": float(bz.dash_len) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": 1.0, "locked": true, "order": int(bz.dash_seq) })
		"doom_executor":
			var SL: Dictionary = cfg.slash
			if s == "slash_warn" or s == "slash_lock" or s == "slash_gap":
				for i in (bz.slashes as Array).size():
					var sl: Dictionary = bz.slashes[i]
					if bool(sl.fired):
						continue
					var cur: bool = i == int(bz.slash_idx)
					var pr: float = 1.0
					if s == "slash_warn":
						pr = st_t / float(SL.warn)
					elif s == "slash_gap":
						pr = st_t / float(SL.gap)
					out.append({ "kind": "beam", "e": bz, "x": float(sl.x), "y": 0.0, "ang": PI / 2.0, "len": st.arena_h, "w": float(SL.width) + 20.0, "prog": pr if cur else 0.3, "locked": bool(sl.fixed) and cur and s == "slash_lock", "order": int(sl.order) })
			if s == "guard":
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.face), "r": float(cfg.guard.strike.radius), "half": PGeom.deg(float(cfg.guard.frontDeg)) / 2.0, "prog": 0.0, "locked": false, "guard": true })
			if s == "gstrike_aim" or s == "gstrike_lock":
				var K: Dictionary = cfg.guard.strike
				out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": facing(bz), "r": float(K.radius) + 30.0, "half": PGeom.deg(float(K.arcDeg)) / 2.0 + 0.2, "prog": (st_t / float(K.aim)) if s == "gstrike_aim" else 1.0, "locked": s == "gstrike_lock" })
	for z in st.zones:
		if z.type == "rubble":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r, "rubble": true })

## 회복 구슬 배치용: 지금 예고·실행 중인 위험 안인가. pt = {x, y}
static func in_danger(st: CombatState, e: Dictionary, pt: Dictionary) -> bool:
	var out: Array = []
	threats(st, e, out)
	var pp := { "x": float(pt.x), "y": float(pt.y), "r": 14.0 }
	for th in out:
		if String(th.kind) == "arc" and bool(th.get("guard", false)):
			continue
		if PBot.inside(th, pp):
			return true
	return false
