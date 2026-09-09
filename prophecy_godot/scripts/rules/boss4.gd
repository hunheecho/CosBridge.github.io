class_name PBoss4
extends RefCounted
## 보스 9종 **신규 공격 패턴 18개**(§11-A). 기존 패턴은 하나도 고치지 않고 여기에만 새로 만든다.
##
## 왜 만드는가(사용자 지시): 기존 패턴은 "멀리서 같은 방향으로 걸으며 자동 공격"하는 플레이를 흔들지 못했다.
## 기존 공격은 대부분 **지금 서 있는 자리**를 겨눈다 — 같은 속도로 계속 걸으면 예고가 뒤로 흘러 전부 빗나간다.
## 여기 18개는 전부 **관측된 이동**(지난 프레임의 실제 위치 변화)을 써서 **가는 쪽**을 겨누거나 **길목을 막는다**.
##   · 입력을 미리 읽지 않는다. observe()가 보는 것은 화면에 이미 그려진 위치 변화뿐이다.
##   · 관측은 평활 시간(leadTau)만큼 늦다 — **방향을 바꾸면 예측이 빗나간다**. 이것이 회피 수단이다.
##   · 확정(*_lock)에 들어가면 각·자리·목표가 굳고 보스는 **더 이상 따라오지 않는다**(추적 확정 금지).
##   · 모든 연계는 마지막에 recover(빈틈)로 끝난다 — 피하거나 방향을 바꾼 뒤 반드시 반격 창이 온다.
##   · 무적·강제 생존·체력 구간 피해 상한을 만들지 않는다. 새 판정은 전부 예고가 먼저 뜬다.
##
## 숫자는 코드에 두지 않는다. 전부 data/boss_behavior.json의 <보스>.newPatterns.<패턴>에 있고 **전부 시험값**이다.
## 상태 이름은 모두 "nx_"로 시작한다 — PBoss.update가 이 접두사만 보고 여기로 넘긴다(보스 9종 공통 한 곳).

## 관측 이동 속도의 상한(초당). 회피 순간의 순간 속도(150/0.26초)가 예측을 튀게 하지 않도록 자른다.
## 값 자체는 data(leadCap)에서 읽고, 없을 때의 기본값만 여기 둔다(플레이어 기본 이동 220).
const LEAD_CAP_DEF := 260.0
const LEAD_TAU_DEF := 0.22

# ---------- 설정 읽기 ----------
static func pats(e: Dictionary) -> Dictionary:
	var d: Variant = PBoss.beh_e(e).get("newPatterns", {})
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func cfg(e: Dictionary, pat: String) -> Dictionary:
	var d: Variant = pats(e).get(pat, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func has_pattern(e: Dictionary, pat: String) -> bool:
	return pats(e).has(pat)

## 지금 진행 중인 새 패턴의 설정
static func cur(e: Dictionary) -> Dictionary:
	return cfg(e, String(e.get("nx_pat", "")))

## 이 개체가 지금 새 패턴 상태인가(PBoss.update의 분기 하나가 9종 전부를 여기로 넘긴다)
static func owns(e: Dictionary) -> bool:
	return String(e.get("state", "")).begins_with("nx_")

## 확정·실행 중(늑대 돌진 금지·회복 구슬 배치가 본다). 준비(*_aim)와 몸만 움직이는 구간은 포함하지 않는다
static func is_committed(e: Dictionary) -> bool:
	var s := String(e.get("state", ""))
	if not s.begins_with("nx_"):
		return false
	return s.ends_with("_lock") or s == "nx_leap_fly" or s == "nx_spray_on"

## 새 패턴의 원래 예고 합(연계 후속타 배속의 하한 계산이 읽는다)
static func pattern_warn(e: Dictionary, pat: String) -> float:
	var d := cfg(e, pat)
	if d.is_empty():
		return 0.0
	return float(d.get("aim", d.get("cast", d.get("warn", 0.0)))) + float(d.get("lock", 0.0))

# ---------- 관측(입력을 읽지 않는다) ----------
## 매 프레임 호출. 지난 프레임의 **실제 위치 변화**만으로 플레이어의 이동을 추정한다.
## 평활 시간 leadTau 때문에 추정은 늘 조금 늦다 — 방향을 바꾸면 그만큼 예측이 빗나간다(회피 수단).
static func observe(st: CombatState, e: Dictionary, dt: float) -> void:
	var p := st.player
	var last: Array = e.get("nx_plast", [])
	if dt > 1e-6 and last.size() == 2:
		var vx: float = (float(p.x) - float(last[0])) / dt
		var vy: float = (float(p.y) - float(last[1])) / dt
		var cap := LEAD_CAP_DEF
		var tau := LEAD_TAU_DEF
		var B := PBoss.beh_e(e)
		if B.has("leadCap"):
			cap = float(B.leadCap)
		if B.has("leadTau"):
			tau = float(B.leadTau)
		var sp: float = sqrt(vx * vx + vy * vy)
		if sp > cap and sp > 1e-6:
			vx = vx / sp * cap
			vy = vy / sp * cap
		var k: float = clampf(dt / maxf(0.01, tau), 0.0, 1.0)
		e.nx_pvx = float(e.get("nx_pvx", 0.0)) * (1.0 - k) + vx * k
		e.nx_pvy = float(e.get("nx_pvy", 0.0)) * (1.0 - k) + vy * k
	e.nx_plast = [float(p.x), float(p.y)]

## 겨눠야 할 시간(초) = **남은 예고 시간 + 도달 시간**.
## 이것을 빼먹으면(도달 시간만 겨누면) 확정 구간 동안 플레이어가 더 걸어가 버려 직선 보행자에게도 빗나간다.
## fly = 탄·몸이 날아가는 시간, hold = 지금부터 발사·타격까지 남은 확정 시간
static func lead_t(hold: float, fly: float, cap: float) -> float:
	return minf(hold + fly, cap)

## 날아가는 것(탄·바위)의 겨눔점: 도달 시간이 '목표가 얼마나 멀어지는가'에 다시 달려 있으므로 두어 번 되풀이해 맞춘다.
## hold = 지금부터 발사까지 남은 확정 시간, speed = 탄속, cap = 겨눔 상한(초)
static func lead_shot(st: CombatState, e: Dictionary, hold: float, speed: float, cap: float) -> Array:
	var t: float = hold
	var lp: Array = [float(st.player.x), float(st.player.y)]
	for i in 6: # 느린 탄(굴러가는 바위)일수록 수렴이 느리다
		lp = lead(st, e, t)
		t = minf(hold + PGeom.dist(e.x, e.y, float(lp[0]), float(lp[1])) / maxf(1.0, speed), cap)
	return lead(st, e, t)

## t초 뒤 예상 위치(관측 속도 그대로 직선 연장). 전장 안으로 자른다
static func lead(st: CombatState, e: Dictionary, t: float) -> Array:
	var p := st.player
	var x: float = clampf(float(p.x) + float(e.get("nx_pvx", 0.0)) * t, 24.0, st.arena_w - 24.0)
	var y: float = clampf(float(p.y) + float(e.get("nx_pvy", 0.0)) * t, 24.0, st.arena_h - 24.0)
	return [x, y]

## 관측된 이동 방향(거의 멈춰 있으면 보스 → 플레이어 방향)
static func move_ang(st: CombatState, e: Dictionary) -> float:
	var vx := float(e.get("nx_pvx", 0.0))
	var vy := float(e.get("nx_pvy", 0.0))
	if sqrt(vx * vx + vy * vy) < 30.0:
		return atan2(float(st.player.y) - e.y, float(st.player.x) - e.x)
	return atan2(vy, vx)

# ---------- 공통 처리 ----------
static func _recover(st: CombatState, e: Dictionary, dur: float, label: String) -> void:
	if PBoss.chain_continue(st, e):
		return
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = PBoss.chain_end_recover(e, dur)
	PBoss.chain_reset(e)
	st.text(e.x, e.y - e.r - 30.0, label, "#ffd166")

## 부채꼴 직접 공격(장애물 가림 적용 — 새 패턴도 벽 관통이 아니다)
static func _arc_hit(st: CombatState, e: Dictionary, ang: float, R: float, half: float, dmg: float, src: String, color: String) -> void:
	var p := st.player
	if PGeom.in_arc(e.x, e.y, R, ang, half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
		st.damage_player(dmg, src, e)
	var f: Dictionary = { "kind": "bosssweep", "x": e.x, "y": e.y, "angle": ang, "r": R, "half": half, "ttl": 0.3 }
	if color != "":
		f.color = color
	st.fx(f)
	st.ev("boss_sweep")
	st.note_attack(e, "execute")

## 원 판정(바닥 충격·폭발). 바닥 판정이라 장애물 가림 없음 — 대신 예고 원이 먼저 뜬다
static func _circle_hit(st: CombatState, e: Dictionary, x: float, y: float, r: float, dmg: float, src: String, color: String) -> void:
	var p := st.player
	if PGeom.dist(x, y, p.x, p.y) <= r + p.r:
		st.damage_player(dmg, src, e)
	var f: Dictionary = { "kind": "bossland", "x": x, "y": y, "r": r, "ttl": 0.4 }
	if color != "":
		f.color = color
	st.fx(f)
	st.ev("boss_land")

## 적 투사체 한 발(추적 없음 — 발사 뒤에는 직선으로만 간다)
static func _fire(st: CombatState, e: Dictionary, ang: float, S: Dictionary, kind: String) -> Dictionary:
	var speed: float = float(S.get("speed", 500.0))
	var pr: Dictionary = { "owner": "enemy", "kind": kind, "shooter": e,
		"x": e.x + cos(ang) * e.r, "y": e.y + sin(ang) * e.r,
		"vx": cos(ang) * speed, "vy": sin(ang) * speed,
		"r": float(S.get("r", 8.0)), "dmg": float(S.get("damage", 10.0)),
		"ttl": float(S.get("len", 600.0)) / speed, "angle": ang,
		"width": float(S.get("width", float(S.get("r", 8.0)) * 2.0)), "dead": false, "hits": {} }
	CombatState.stamp_projectile(e, pr)
	st.projectiles.append(pr)
	return pr

## 예고된 폭발 하나 예약(뿌리 벽·미래 표식이 함께 쓴다). 정해진 시각에 tick()이 터뜨린다
static func _add_blast(e: Dictionary, x: float, y: float, r: float, at: float, dmg: float, order: int, src: String, color: String) -> void:
	var arr: Array = e.get("nx_blasts", [])
	arr.append({ "x": x, "y": y, "r": r, "at": at, "dmg": dmg, "order": order, "src": src, "color": color, "warn": 0.0 })
	e.nx_blasts = arr

## 플레이어 주위 16방향 중 예고에 덮이지 않은 방향 수(탈출 경로가 남아 있는지 확인용)
static func free_dirs(st: CombatState, blasts: Array, probe: float) -> int:
	var p := st.player
	var free := 0
	for i in 16:
		var a: float = float(i) / 16.0 * TAU
		var x: float = float(p.x) + cos(a) * probe
		var y: float = float(p.y) + sin(a) * probe
		if x < p.r or y < p.r or x > st.arena_w - p.r or y > st.arena_h - p.r:
			continue
		var blocked := false
		for b in blasts:
			if PGeom.dist(float(b.x), float(b.y), x, y) <= float(b.r) + float(p.r):
				blocked = true
				break
		if not blocked:
			free += 1
	return free

# ---------- 후보·시작 ----------
## 지금 거리·단계·잔여 예고에서 고를 수 있는 새 패턴을 cands에 더한다(보스 9종 공통)
static func extra_candidates(st: CombatState, e: Dictionary, cands: Array) -> void:
	var P := pats(e)
	if P.is_empty():
		return
	var p := st.player
	var d: float = PGeom.dist(e.x, e.y, p.x, p.y)
	var los: bool = not st.los_blocked(e.x, e.y, p.x, p.y)
	var busy: bool = not (e.get("marks", []) as Array).is_empty()
	var allow: Array = PBoss.beh_e(e).get("markBusy", [])
	for k in P:
		var name := String(k)
		var o: Dictionary = P[name]
		if busy and not allow.has(name):
			continue # 잔여 예고(표식·포자 탄)가 남아 있으면 겹치지 않는다
		if int(e.get("phase", 1)) < int(o.get("minPhase", 1)):
			continue
		if d < float(o.get("minDist", 0.0)) or d > float(o.get("maxDist", 9999.0)):
			continue
		if bool(o.get("needLos", true)) and not los:
			continue
		cands.append([name, float(o.get("w", 1.0))])

## PBoss/PBoss2/PBoss3의 begin()이 공통 기록(history·metrics·연계)을 마친 뒤 부른다
static func begin(st: CombatState, e: Dictionary, pat: String) -> void:
	var d := cfg(e, pat)
	e.nx_pat = pat
	e.nx_i = 0
	e.nx_side = 1.0 if st.rng.next() < 0.5 else -1.0
	e.nx_land = {}
	e.nx_tick = 0.0
	e.state_t = 0.0
	e.hit_done = false
	var label := String(d.get("label", ""))
	if label != "":
		st.text(e.x, e.y - e.r - 34.0, label, String(d.get("labelColor", "#ffd9b0")))
	match String(d.get("engine", "")):
		"march": e.state = "nx_march_aim"
		"leap": e.state = "nx_leap_aim"
		"volley": e.state = "nx_volley_aim"
		"wall": e.state = "nx_wall_cast"
		"foremark": e.state = "nx_fore_cast"
		"boulder": e.state = "nx_boul_aim"
		"mspray": e.state = "nx_spray_aim"
		"flank": e.state = "nx_flank_side"
		"drive": e.state = "nx_drive_run"
		_:
			e.state = "approach"
			e.approach_t = 0.0

# ---------- 상태와 무관하게 도는 것(예약된 폭발·잔상·바위 파열) ----------
## 매 프레임 보스 9종 전부에 대해 돈다. 보스가 다음 행동으로 넘어가도 **예고된 것은 제 시각에** 일어난다.
## 감속장은 위치 기반 예고의 시계를 늦추지 않는다(기존 표식·낙석과 같은 규칙).
static func tick(st: CombatState, e: Dictionary, dt: float) -> void:
	var blasts: Array = e.get("nx_blasts", [])
	if not blasts.is_empty():
		var keep: Array = []
		for b in blasts:
			if st.t < float(b.at):
				keep.append(b)
				continue
			_circle_hit(st, e, float(b.x), float(b.y), float(b.r), float(b.dmg), String(b.src), String(b.color))
			st.note_attack(e, "execute")
		e.nx_blasts = keep
	var echoes: Array = e.get("nx_echo", [])
	if not echoes.is_empty():
		var keep2: Array = []
		for h in echoes:
			if st.t < float(h.at):
				keep2.append(h)
				continue
			# 잔상: 본체가 지나간 자리에서 같은 궤적을 늦게 반복한다. 그 자리에 머무르면 맞는다
			var p := st.player
			if PGeom.in_arc(float(h.x), float(h.y), float(h.r), float(h.ang), float(h.half), p.x, p.y, p.r):
				st.damage_player(float(h.dmg), "boss_nx_echo", e)
			st.fx({ "kind": "bosssweep", "x": float(h.x), "y": float(h.y), "angle": float(h.ang), "r": float(h.r), "half": float(h.half), "ttl": 0.3, "color": "#c080ff" })
			st.ev("boss_sweep")
			st.note_attack(e, "execute")
		e.nx_echo = keep2
	var bl: Dictionary = e.get("nx_boulder", {})
	if not bl.is_empty() and bool(bl.get("dead", false)):
		e.nx_boulder = {}
		var d := cur(e)
		var sd: Dictionary = e.get("nx_bshard", {})
		if not sd.is_empty():
			# 바위가 멈춘(부서진) 자리에서 좌우 사선으로 파편 둘. 파열 자리는 확정 시점에 이미 예고돼 있었다
			var ang: float = atan2(float(bl.get("vy", 0.0)), float(bl.get("vx", 1.0)))
			var spread: float = PGeom.deg(float(sd.get("shardDeg", 55.0)))
			st.fx({ "kind": "bossland", "x": float(bl.x), "y": float(bl.y), "r": float(d.get("burstR", 60.0)), "ttl": 0.35 })
			st.ev("explode")
			for s in [1.0, -1.0]:
				var pr := _fire(st, e, ang + spread * float(s), sd, "boss_nx_shard")
				pr.r = float(sd.get("r", 10.0))
			e.nx_bshard = {}
	if float(e.get("nx_tick", 0.0)) > 0.0:
		e.nx_tick = maxf(0.0, float(e.nx_tick) - dt)

# ---------- 갱신 ----------
static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	var d := cur(e)
	if d.is_empty(): # 설정이 사라졌다(자료를 지웠다) — 안전하게 접근으로 되돌린다
		e.state = "approach"
		e.state_t = 0.0
		e.approach_t = 0.0
		return
	var tf := st.time_factor(e)
	var adv: float = dt * tf * PBoss.prep_speed(e)
	var sm := st.enemy_speed_mult(e)
	match String(d.get("engine", "")):
		"march": _march(st, e, d, dt, adv, sm)
		"leap": _leap(st, e, d, adv)
		"volley": _volley(st, e, d, dt, adv, sm)
		"wall": _wall(st, e, d, dt, adv, sm)
		"foremark": _foremark(st, e, d, adv)
		"boulder": _boulder(st, e, d, dt, adv, sm)
		"mspray": _mspray(st, e, d, dt, adv, sm)
		"flank": _flank(st, e, d, dt, adv, sm)
		"drive": _drive(st, e, d, dt, adv, sm)
	if String(e.state) != "nx_leap_fly":
		st.push_out(e)

## 보스 걸음(예고 구간에서만 쓴다). 확정 뒤에는 아무도 이 함수를 부르지 않는다.
## mult는 보스 기본 이동 속도의 배수다
static func _walk(st: CombatState, e: Dictionary, tx: float, ty: float, mult: float, stop: float, dt: float, sm: float) -> void:
	if mult <= 0.0:
		return
	_walk_px(st, e, tx, ty, float(PBoss.cfg_of(e).speed) * mult, stop, dt, sm)

## 초당 픽셀로 지정한 걸음. **밀고 들어오는 속도**를 보스마다 배수로 환산하지 않고 그대로 적는다 —
## 이 값이 플레이어 걸음(220)을 넘어야 "같은 방향으로 걷기만 하는" 상대를 실제로 따라잡는다(전부 시험값).
static func _walk_px(st: CombatState, e: Dictionary, tx: float, ty: float, px: float, stop: float, dt: float, sm: float) -> void:
	if px <= 0.0 or PGeom.dist(e.x, e.y, tx, ty) <= stop:
		return
	st.approach(e, tx, ty, px * sm, dt)

# ---------- ① 전진 연타(march) ----------
## 걸어 들어오며 좌·우로 번갈아 치고 마지막에 크게 한 번. 단순 후퇴를 압박하고, 옆으로 돌아 들어가면 빗나간다.
## 각 타는 **따로** 예고(추적)와 확정(고정)을 거친다 — 확정 뒤에는 멈춰서 친다(따라오지 않는다).
static func _march(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	var p := st.player
	var n: int = int(d.get("hits", 3))
	var i: int = int(e.get("nx_i", 0))
	var last: bool = i >= n - 1
	var aim_t: float = float(d.get("finalAim", 0.75)) if last else float(d.get("aim", 0.5))
	var lock_t: float = float(d.get("finalLock", 0.3)) if last else float(d.get("lock", 0.2))
	var R: float = float(d.get("finalRadius", 190.0)) if last else float(d.get("radius", 150.0))
	var half: float = PGeom.deg(float(d.get("finalArcDeg", 200.0)) if last else float(d.get("arcDeg", 110.0))) / 2.0
	var dmg: float = float(d.get("finalDamage", 20.0)) if last else float(d.get("damage", 12.0))
	var off: float = 0.0
	if not last:
		off = PGeom.deg(float(d.get("offDeg", 42.0))) * (float(e.get("nx_side", 1.0)) if i % 2 == 0 else -float(e.get("nx_side", 1.0)))
	match String(e.state):
		"nx_march_aim":
			# 예고 중에는 **밀고 들어온다**(단순 후퇴를 압박). 겨누는 곳은 지금 자리가 아니라 확정 시간 뒤의 자리다.
			# 확정(_lock)에 들어가면 이 걸음이 멈춘다 — 확정 뒤에는 따라오지 않는다
			_walk_px(st, e, p.x, p.y, float(d.get("chargeSpeed", 0.0)), R * float(d.get("closeFrac", 0.6)), dt, sm)
			var lp0 := lead(st, e, lead_t(lock_t, 0.0, float(d.get("leadMax", 0.5))))
			e.aim_angle = atan2(float(lp0[1]) - e.y, float(lp0[0]) - e.x) + off
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= aim_t:
				e.state = "nx_march_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_march_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= lock_t:
				_arc_hit(st, e, float(e.dir), R, half, dmg, String(d.get("src", "boss_nx_march")), String(d.get("color", "")))
				_note_echo(e, d, float(e.dir), R, half, dmg, st.t)
				e.nx_i = i + 1
				if last:
					_recover(st, e, float(d.get("recover", 1.6)), String(d.get("endText", "연타 끝 — 빈틈!")))
				else:
					e.state = "nx_march_aim"
					e.state_t = 0.0
					st.note_attack(e, "prepare") # 다음 타도 새로 예고·확정된다(예고 하나 = 공격 하나)

## 잔향(예언을 먹는 자): 방금 친 궤적을 그 자리에 남겨 늦게 한 번 더 되풀이한다
static func _note_echo(e: Dictionary, d: Dictionary, ang: float, R: float, half: float, dmg: float, now: float) -> void:
	var E: Dictionary = d.get("echo", {})
	if E.is_empty():
		return
	var arr: Array = e.get("nx_echo", [])
	arr.append({ "x": e.x, "y": e.y, "ang": ang, "r": R, "half": half,
		"at": now + float(E.get("delay", 0.8)), "dmg": dmg * float(E.get("dmgMult", 0.6)) })
	e.nx_echo = arr

# ---------- ② 길목 덮치기·추격 도약(leap) ----------
## 착지 원을 **가는 쪽**에 놓는다. 같은 방향으로 계속 걸으면 정확히 밟히고, 방향을 바꾸거나 멈추면 빗나간다.
## 착지 뒤 후속(몸통 공격·밀치기)이 정면에 붙으므로, 착지를 피한 뒤 정면에 머무르면 후속에 맞는다.
static func _leap(st: CombatState, e: Dictionary, d: Dictionary, adv: float) -> void:
	var p := st.player
	var A: Dictionary = d.get("after", {})
	match String(e.state):
		"nx_leap_aim":
			# 착지 원은 '확정 뒤 + 날아가는 동안' 플레이어가 갈 자리에 놓인다
			var lp := lead(st, e, lead_t(float(d.get("lock", 0.3)), float(d.get("fly", 0.42)), float(d.get("leadMax", 1.2))))
			e.nx_land = PBoss.landing_for(st, e, float(lp[0]), float(lp[1]))
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("aim", 0.8)):
				e.state = "nx_leap_lock"
				e.state_t = 0.0
				st.ev("boss_lock")
		"nx_leap_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("lock", 0.3)):
				e.state = "nx_leap_fly"
				e.state_t = 0.0
				e.nx_from = { "x": e.x, "y": e.y }
				e.nx_k = 0.0
				e.airborne = true
				st.note_attack(e, "execute")
		"nx_leap_fly":
			e.nx_k = minf(1.0, float(e.get("nx_k", 0.0)) + adv / maxf(0.01, float(d.get("fly", 0.42))))
			var k: float = float(e.nx_k)
			var f: Dictionary = e.get("nx_from", { "x": e.x, "y": e.y })
			var land: Dictionary = e.get("nx_land", { "x": e.x, "y": e.y })
			e.x = float(f.x) + (float(land.x) - float(f.x)) * k
			e.y = float(f.y) + (float(land.y) - float(f.y)) * k
			if k >= 1.0:
				e.airborne = false
				e.x = float(land.x)
				e.y = float(land.y)
				_circle_hit(st, e, e.x, e.y, float(d.get("radius", 110.0)), float(d.get("damage", 16.0)), String(d.get("src", "boss_nx_leap")), String(d.get("color", "")))
				if A.is_empty():
					_recover(st, e, float(d.get("recover", 1.5)), String(d.get("endText", "착지 뒤 — 빈틈!")))
				else:
					e.state = "nx_leap_aaim"
					e.state_t = 0.0
					e.aim_angle = atan2(p.y - e.y, p.x - e.x)
					st.note_attack(e, "prepare")
					st.text(e.x, e.y - e.r - 30.0, String(A.get("label", "후속 — 정면")), "#ff9f43")
		"nx_leap_aaim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(A.get("aim", 0.45)):
				e.state = "nx_leap_alock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_leap_alock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(A.get("lock", 0.25)):
				_arc_hit(st, e, float(e.dir), float(A.get("radius", 140.0)), PGeom.deg(float(A.get("arcDeg", 120.0))) / 2.0,
					float(A.get("damage", 14.0)), String(A.get("src", "boss_nx_leap2")), String(d.get("color", "")))
				_recover(st, e, float(d.get("recover", 1.6)), String(d.get("endText", "후속 뒤 — 빈틈!")))

# ---------- ③ 전진 연사·교차 사격(volley) ----------
## 각 발이 **따로** 조준·확정된다. 조준은 탄이 날아갈 시간만큼 앞을 겨눈다 — 같은 속도로 계속 걸으면 맞는다.
## 확정된 발은 재조준하지 않는다. 두 번째 발은 **그동안 달라진 움직임**을 새로 관측해 다시 겨눈다.
static func _volley(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	var p := st.player
	var n: int = int(d.get("shots", 3))
	var i: int = int(e.get("nx_i", 0))
	match String(e.state):
		"nx_volley_aim":
			_walk_px(st, e, p.x, p.y, float(d.get("walk", 0.0)), float(d.get("stopDist", 140.0)), dt, sm)
			var speed: float = maxf(1.0, float(d.get("speed", 540.0))) / maxf(0.01, float(d.get("leadMult", 1.0)))
			var lp := lead_shot(st, e, float(d.get("lock", 0.22)), speed, float(d.get("leadMax", 1.2)))
			e.aim_angle = atan2(float(lp[1]) - e.y, float(lp[0]) - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("aim", 0.5)):
				e.state = "nx_volley_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_volley_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("lock", 0.22)):
				_fire(st, e, float(e.dir), d, String(d.get("kind", "boss_nx_bolt")))
				st.ev("shoot")
				st.note_attack(e, "execute")
				e.nx_i = i + 1
				if i + 1 >= n:
					_recover(st, e, float(d.get("recover", 1.4)), String(d.get("endText", "연사 끝 — 빈틈!")))
				else:
					e.state = "nx_volley_aim"
					e.state_t = 0.0
					st.note_attack(e, "prepare")

# ---------- ④ 퇴로 차단 벽(wall) ----------
## 가는 쪽 **앞을 가로질러** 예고 원을 늘어놓고 한쪽 끝부터 순서대로 터뜨린다.
## 늦게 터지는 반대쪽 끝과 본체 쪽은 열려 있다 — 방향을 바꾸면 빠져나갈 수 있다(탈출 방향 수를 배치 때 확인한다).
static func _wall(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	var p := st.player
	var F: Dictionary = d.get("follow", {})
	match String(e.state):
		"nx_wall_cast":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("cast", 0.7)):
				_place_wall(st, e, d)
				st.ev("boss_lock")
				st.ev("hazard_warn")
				if F.is_empty():
					e.state = "nx_wall_wait"
					e.state_t = 0.0
				else:
					e.state = "nx_wall_faim" if String(F.get("kind", "shock")) == "shock" else "nx_wall_laim"
					e.state_t = 0.0
					st.note_attack(e, "prepare")
					st.text(e.x, e.y - e.r - 30.0, String(F.get("label", "본체 후속")), "#ff9f43")
		"nx_wall_wait":
			e.state_t = float(e.state_t) + adv
			if (e.get("nx_blasts", []) as Array).is_empty():
				_recover(st, e, float(d.get("recover", 1.5)), String(d.get("endText", "벽이 다 터졌다 — 빈틈!")))
			elif float(d.get("chainAfter", -1.0)) >= 0.0 and float(e.state_t) >= float(d.chainAfter) and PBoss.chain_continue(st, e):
				pass # 남은 벽은 제 시각에 계속 터진다
		"nx_wall_faim": # 본체 충격파를 **시간차로** 잇는다(벽과 같은 순간에 겹치지 않게 followAfter만큼 늦다)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(F.get("aim", 0.6)):
				e.state = "nx_wall_flock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_wall_flock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(F.get("lock", 0.3)):
				_fire(st, e, float(e.dir), F, String(F.get("kind2", "boss_nx_shock")))
				st.ev("boss_sweep")
				st.note_attack(e, "execute")
				_recover(st, e, float(d.get("recover", 1.6)), String(d.get("endText", "협공 끝 — 빈틈!")))
		"nx_wall_laim": # 본체가 찌르며 다가온다(예고 중에만 걸어온다)
			_walk_px(st, e, p.x, p.y, float(F.get("walk", 240.0)), float(F.get("radius", 170.0)) * 0.6, dt, sm)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(F.get("aim", 0.55)):
				e.state = "nx_wall_llock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_wall_llock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(F.get("lock", 0.28)):
				_arc_hit(st, e, float(e.dir), float(F.get("radius", 170.0)), PGeom.deg(float(F.get("arcDeg", 60.0))) / 2.0,
					float(F.get("damage", 18.0)), String(F.get("src", "boss_nx_lunge")), String(d.get("color", "")))
				_recover(st, e, float(d.get("recover", 1.7)), String(d.get("endText", "찌르기 뒤 — 빈틈!")))

static func _place_wall(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	var p := st.player
	var mv := move_ang(st, e)
	var n: int = int(d.get("segments", 4))
	var warn: float = float(d.get("warn", 0.9))
	var gap: float = float(d.get("gap", 0.2))
	# 벽은 '폭발이 한창일 때' 플레이어가 있을 자리를 가로질러 놓인다(첫 폭발과 마지막 폭발의 가운데 시각).
	# 첫 폭발 시각만 겨누면 순서가 뒤쪽인 조각이 터질 즈음 플레이어가 이미 지나가 버린다
	var lp := lead(st, e, minf(warn + gap * float(n - 1) * 0.5, float(d.get("leadMax", 1.2))))
	var seg_r: float = float(d.get("segR", 56.0))
	var spacing: float = float(d.get("spacing", 92.0))
	var nx: float = -sin(mv)
	var ny: float = cos(mv)
	var side: float = float(e.get("nx_side", 1.0)) # 어느 끝부터 터질지(양쪽 번갈아 나오도록 시작 때 정했다)
	var made: Array = []
	for i in n:
		var k: float = (float(i) - float(n - 1) / 2.0) * spacing
		var x: float = clampf(float(lp[0]) + nx * k, seg_r, st.arena_w - seg_r)
		var y: float = clampf(float(lp[1]) + ny * k, seg_r, st.arena_h - seg_r)
		made.append({ "x": x, "y": y, "r": seg_r, "k": k })
	# 순서: 한쪽 끝부터. 반대쪽 끝은 가장 늦게 터진다 — 그쪽이 실제 탈출구다
	made.sort_custom(func(a, b): return float(a.k) * side < float(b.k) * side)
	# 탈출 방향이 minExits보다 적으면 **가장 늦게 터질 끝부터** 지운다(모든 출구를 막지 않는다)
	while made.size() > 1 and free_dirs(st, made, float(d.get("probe", 110.0))) < int(d.get("minExits", 4)):
		made.pop_back()
	for i in made.size():
		var m: Dictionary = made[i]
		_add_blast(e, float(m.x), float(m.y), float(m.r), st.t + warn + float(i) * gap,
			float(d.get("damage", 16.0)), i + 1, String(d.get("src", "boss_nx_wall")), String(d.get("color", "")))
	st.note_attack(e, "execute")
	if made.is_empty():
		st.text(p.x, p.y - 40.0, "길이 열려 있다", "#9cffb0")

# ---------- ⑤ 미래 표식(foremark) ----------
## 지난 자리를 터뜨리는 기존 표식과 반대로 **가는 쪽 앞**을 터뜨린다.
## 한 발이 터지면 그때의 움직임을 **새로 관측해** 다음 자리를 다시 예고한다(미리 전부 확정하지 않는다).
static func _foremark(st: CombatState, e: Dictionary, d: Dictionary, adv: float) -> void:
	var i: int = int(e.get("nx_i", 0))
	match String(e.state):
		"nx_fore_cast":
			var need: float = float(d.get("cast", 0.6)) if i == 0 else float(d.get("recast", 0.4))
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= need:
				# 표식은 '터질 때(delay 뒤)' 플레이어가 있을 자리에 놓인다 — 지난 자리를 터뜨리는 기존 표식의 반대다
				var lp := lead(st, e, minf(float(d.get("delay", 0.8)), float(d.get("leadMax", 1.2))))
				_add_blast(e, float(lp[0]), float(lp[1]), float(d.get("r", 66.0)), st.t + float(d.get("delay", 0.8)),
					float(d.get("damage", 16.0)), i + 1, String(d.get("src", "boss_nx_fore")), String(d.get("color", "#c080ff")))
				e.nx_i = i + 1
				e.state = "nx_fore_wait"
				e.state_t = 0.0
				st.ev("boss_lock")
				st.note_attack(e, "execute")
		"nx_fore_wait":
			e.state_t = float(e.state_t) + adv
			if not (e.get("nx_blasts", []) as Array).is_empty():
				return
			if i < int(d.get("count", 3)):
				e.state = "nx_fore_cast"
				e.state_t = 0.0
				st.note_attack(e, "prepare")
			else:
				_recover(st, e, float(d.get("recover", 1.5)), String(d.get("endText", "표식 끝 — 빈틈!")))

# ---------- ⑥ 암석 굴리기(boulder) ----------
## 가는 쪽을 향해 큰 바위를 굴린다. 낙석 세 원(원 밖으로 나가기)과 달리 **선을 옆으로 벗어나야** 한다.
## 바위가 멈추는 자리(벽·엄폐물·사거리 끝)는 확정 시점에 계산해 예고에 함께 띄우고, 그 자리에서 파편 둘이 사선으로 튄다.
static func _boulder(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	match String(e.state):
		"nx_boul_aim":
			_walk_px(st, e, st.player.x, st.player.y, float(d.get("walk", 0.0)), float(d.get("stopDist", 200.0)), dt, sm)
			var lp := lead_shot(st, e, float(d.get("lock", 0.3)), maxf(1.0, float(d.get("speed", 330.0))), float(d.get("leadMax", 1.8)))
			e.aim_angle = atan2(float(lp[1]) - e.y, float(lp[0]) - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("aim", 0.8)):
				e.state = "nx_boul_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				var path := PBoss3.path_from(st, e.x, e.y, float(d.get("r", 30.0)), float(e.dir), float(d.get("len", 620.0)))
				e.nx_burst = path.end
				st.ev("boss_lock")
		"nx_boul_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("lock", 0.3)):
				var pr := _fire(st, e, float(e.dir), d, String(d.get("kind", "boss_nx_boulder")))
				e.nx_boulder = pr
				e.nx_bshard = d.get("shard", {})
				st.ev("boss_land")
				st.note_attack(e, "execute")
				_recover(st, e, float(d.get("recover", 1.8)), String(d.get("endText", "바위를 밀고 멈춤 — 빈틈!")))

# ---------- ⑦ 이동 분사(mspray) ----------
## 전진하며 길게 분사한다. **선회가 느려서**(turnRate) 옆을 지나 뒤로 빠지면 분사에서 벗어난다.
## 계속 같은 방향으로 걸으면 분사 안에 남아 연속으로 맞는다.
static func _mspray(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	var p := st.player
	match String(e.state):
		"nx_spray_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("aim", 0.7)):
				e.state = "nx_spray_on"
				e.state_t = 0.0
				e.dir = e.aim_angle
				e.nx_tick = 0.0
				st.ev("boss_lock")
				st.note_attack(e, "execute")
		"nx_spray_on":
			var want: float = atan2(p.y - e.y, p.x - e.x)
			var turn: float = PGeom.deg(float(d.get("turnDeg", 55.0))) * adv
			e.dir = float(e.dir) + clampf(PGeom.ang_diff(float(e.dir), want), -turn, turn)
			_walk_px(st, e, p.x, p.y, float(d.get("walk", 120.0)), float(d.get("radius", 260.0)) * 0.4, dt, sm)
			e.state_t = float(e.state_t) + adv
			if float(e.get("nx_tick", 0.0)) <= 0.0:
				e.nx_tick = float(d.get("tick", 0.45))
				var half: float = PGeom.deg(float(d.get("arcDeg", 62.0))) / 2.0
				if PGeom.in_arc(e.x, e.y, float(d.get("radius", 260.0)), float(e.dir), half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
					st.damage_player(float(d.get("damage", 9.0)), String(d.get("src", "boss_nx_spray")), e)
				st.fx({ "kind": "bosssweep", "x": e.x, "y": e.y, "angle": float(e.dir), "r": float(d.get("radius", 260.0)), "half": half, "ttl": 0.25, "color": String(d.get("color", "#c090ff")) })
			if float(e.state_t) >= float(d.get("dur", 2.0)):
				_recover(st, e, float(d.get("recover", 1.6)), String(d.get("endText", "분사 끝 — 빈틈!")))

# ---------- ⑧ 측면 추격(flank) ----------
## 먼저 옆으로 붙는다(예고 아님 — 몸만 움직이고 그대로 맞는다). 그 뒤 **따로 예고**를 거쳐 사선으로 벤다.
static func _flank(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	var p := st.player
	var hold: float = float(d.get("holdDist", 130.0))
	match String(e.state):
		"nx_flank_side":
			# 옆으로 **돌아 붙는다**: 제자리 옆걸음이 아니라 플레이어 둘레를 도는 이동이라 거리가 벌어지지 않는다.
			# 예고가 아니라 몸만 움직이는 구간이다(무적 없음 — 그대로 맞는다)
			var a: float = atan2(e.y - p.y, e.x - p.x) + PGeom.deg(float(d.get("orbitDeg", 55.0))) * float(e.get("nx_side", 1.0))
			var tx: float = p.x + cos(a) * hold
			var ty: float = p.y + sin(a) * hold
			_walk_px(st, e, tx, ty, float(d.get("sideSpeed", 300.0)), 6.0, dt, sm)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("side", 0.45)):
				e.state = "nx_flank_aim"
				e.state_t = 0.0
				st.note_attack(e, "prepare") # 옆 이동이 아니라 **여기서부터** 예고다
				st.text(e.x, e.y - e.r - 30.0, String(d.get("aimText", "사선 베기 준비")), "#bfefff")
		"nx_flank_aim":
			_walk_px(st, e, p.x, p.y, float(d.get("walk", 240.0)), hold * 0.7, dt, sm)
			var lp := lead(st, e, lead_t(float(d.get("lock", 0.25)), 0.0, float(d.get("leadMax", 0.5))))
			e.aim_angle = atan2(float(lp[1]) - e.y, float(lp[0]) - e.x) + PGeom.deg(float(d.get("offDeg", 22.0))) * float(e.get("nx_side", 1.0))
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("aim", 0.55)):
				e.state = "nx_flank_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_flank_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("lock", 0.25)):
				_arc_hit(st, e, float(e.dir), float(d.get("radius", 200.0)), PGeom.deg(float(d.get("arcDeg", 70.0))) / 2.0,
					float(d.get("damage", 16.0)), String(d.get("src", "boss_nx_flank")), String(d.get("color", "#bfefff")))
				_recover(st, e, float(d.get("recover", 1.4)), String(d.get("endText", "사선 베기 뒤 — 빈틈!")))

# ---------- ⑨ 몰이 사냥(drive) ----------
## 본체가 **가는 쪽 앞**으로 크게 돌아 들어가 진로를 막고, 그 자리에서 정면을 친다.
## 늑대를 부를 수 있으면 앞쪽에 함께 세운다. **소환 예산이 끝났거나 늑대가 없어도** 본체 행동만으로 성립한다.
static func _drive(st: CombatState, e: Dictionary, d: Dictionary, dt: float, adv: float, sm: float) -> void:
	var p := st.player
	match String(e.state):
		"nx_drive_run":
			if float(e.state_t) <= 0.0:
				_drive_herd(st, e, d)
			var lp := lead(st, e, float(d.get("leadT", 0.9)))
			_walk_px(st, e, float(lp[0]), float(lp[1]), float(d.get("cutSpeed", 300.0)), float(d.get("holdDist", 60.0)), dt, sm)
			e.state_t = float(e.state_t) + adv
			var there: bool = PGeom.dist(e.x, e.y, float(lp[0]), float(lp[1])) <= float(d.get("holdDist", 60.0))
			if float(e.state_t) >= float(d.get("cut", 1.1)) or there:
				e.state = "nx_drive_aim"
				e.state_t = 0.0
				st.note_attack(e, "prepare")
				st.text(e.x, e.y - e.r - 30.0, String(d.get("aimText", "길목을 막고 친다")), "#ff9f43")
		"nx_drive_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("aim", 0.6)):
				e.state = "nx_drive_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("boss_lock")
		"nx_drive_lock":
			e.state_t = float(e.state_t) + adv
			if float(e.state_t) >= float(d.get("lock", 0.3)):
				_arc_hit(st, e, float(e.dir), float(d.get("radius", 185.0)), PGeom.deg(float(d.get("arcDeg", 150.0))) / 2.0,
					float(d.get("damage", 19.0)), String(d.get("src", "boss_nx_drive")), String(d.get("color", "")))
				_recover(st, e, float(d.get("recover", 1.7)), String(d.get("endText", "몰이 끝 — 빈틈!")))

## 늑대를 진행 방향 앞쪽에 세운다(있을 때만). 예산·동시 상한·등장 예고는 기존 소환 규칙 그대로다
static func _drive_herd(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	if not bool(d.get("herd", true)) or not PBoss3.can_summon(st, e):
		return
	PBoss3._summon_arc(st, e, move_ang(st, e), PGeom.deg(float(d.get("herdDeg", 80.0))), false)
	e.last_summon = st.t

# ---------- 위협 도형(봇·화면 공용 기하) ----------
## 화면이 그리는 것 = 봇이 보는 것 = 실제 판정. 새 패턴도 예외가 없다
static func threats(st: CombatState, e: Dictionary, out: Array) -> void:
	var d := cur(e)
	var s := String(e.state)
	var stt := float(e.get("state_t", 0.0))
	for b in e.get("nx_blasts", []):
		var left: float = maxf(0.0, float(b.at) - st.t)
		out.append({ "kind": "circle", "e": e, "x": float(b.x), "y": float(b.y), "r": float(b.r) + 8.0,
			"prog": clampf(1.0 - left / 1.2, 0.0, 1.0), "locked": left < 0.45, "order": int(b.order), "nx": true })
	for h in e.get("nx_echo", []):
		var left2: float = maxf(0.0, float(h.at) - st.t)
		out.append({ "kind": "arc", "e": e, "x": float(h.x), "y": float(h.y), "ang": float(h.ang), "r": float(h.r),
			"half": float(h.half), "prog": clampf(1.0 - left2 / 1.0, 0.0, 1.0), "locked": true, "nx": true, "echo": true })
	var bl: Dictionary = e.get("nx_boulder", {})
	if not bl.is_empty() and not bool(bl.get("dead", false)):
		var bp: Array = e.get("nx_burst", [])
		if bp.size() == 2:
			out.append({ "kind": "circle", "e": e, "x": float(bp[0]), "y": float(bp[1]), "r": float(d.get("burstR", 60.0)),
				"prog": 1.0, "locked": true, "nx": true })
	if d.is_empty() or not s.begins_with("nx_"):
		return
	var locked: bool = s.ends_with("_lock")
	var ang: float = float(e.dir) if locked else float(e.get("aim_angle", 0.0))
	match s:
		"nx_march_aim", "nx_march_lock":
			var n: int = int(d.get("hits", 3))
			var last: bool = int(e.get("nx_i", 0)) >= n - 1
			var R: float = float(d.get("finalRadius", 190.0)) if last else float(d.get("radius", 150.0))
			var half: float = PGeom.deg(float(d.get("finalArcDeg", 200.0)) if last else float(d.get("arcDeg", 110.0))) / 2.0
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": R, "half": half,
				"prog": clampf(stt / maxf(0.001, float(d.get("finalAim", 0.75)) if last else float(d.get("aim", 0.5))), 0.0, 1.0),
				"locked": locked, "order": int(e.get("nx_i", 0)) + 1, "nx": true })
		"nx_leap_aim", "nx_leap_lock", "nx_leap_fly":
			var land: Dictionary = e.get("nx_land", {})
			if not land.is_empty():
				out.append({ "kind": "circle", "e": e, "x": float(land.x), "y": float(land.y), "r": float(d.get("radius", 110.0)),
					"prog": clampf(stt / maxf(0.001, float(d.get("aim", 0.8))), 0.0, 1.0) if s == "nx_leap_aim" else 1.0,
					"locked": s != "nx_leap_aim", "nx": true })
		"nx_leap_aaim", "nx_leap_alock":
			var A: Dictionary = d.get("after", {})
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": float(A.get("radius", 140.0)),
				"half": PGeom.deg(float(A.get("arcDeg", 120.0))) / 2.0,
				"prog": clampf(stt / maxf(0.001, float(A.get("aim", 0.45))), 0.0, 1.0), "locked": locked, "nx": true })
		"nx_volley_aim", "nx_volley_lock":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": ang, "len": float(d.get("len", 620.0)),
				"w": float(d.get("width", 18.0)) + 26.0, "prog": clampf(stt / maxf(0.001, float(d.get("aim", 0.5))), 0.0, 1.0),
				"locked": locked, "order": int(e.get("nx_i", 0)) + 1, "nx": true })
		"nx_wall_faim", "nx_wall_flock":
			var F: Dictionary = d.get("follow", {})
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": ang, "len": float(F.get("len", 560.0)),
				"w": float(F.get("width", 30.0)) + 26.0, "prog": clampf(stt / maxf(0.001, float(F.get("aim", 0.6))), 0.0, 1.0),
				"locked": locked, "nx": true })
		"nx_wall_laim", "nx_wall_llock":
			var F2: Dictionary = d.get("follow", {})
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": float(F2.get("radius", 170.0)),
				"half": PGeom.deg(float(F2.get("arcDeg", 60.0))) / 2.0,
				"prog": clampf(stt / maxf(0.001, float(F2.get("aim", 0.55))), 0.0, 1.0), "locked": locked, "nx": true })
		"nx_boul_aim", "nx_boul_lock":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": ang, "len": float(d.get("len", 620.0)),
				"w": float(d.get("r", 30.0)) * 2.0 + 26.0, "prog": clampf(stt / maxf(0.001, float(d.get("aim", 0.8))), 0.0, 1.0),
				"locked": locked, "nx": true })
			if locked:
				var bp2: Array = e.get("nx_burst", [])
				if bp2.size() == 2:
					out.append({ "kind": "circle", "e": e, "x": float(bp2[0]), "y": float(bp2[1]), "r": float(d.get("burstR", 60.0)),
						"prog": 1.0, "locked": true, "nx": true })
		"nx_spray_aim", "nx_spray_on":
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y,
				"ang": float(e.get("aim_angle", 0.0)) if s == "nx_spray_aim" else float(e.dir),
				"r": float(d.get("radius", 260.0)), "half": PGeom.deg(float(d.get("arcDeg", 62.0))) / 2.0,
				"prog": clampf(stt / maxf(0.001, float(d.get("aim", 0.7))), 0.0, 1.0), "locked": s == "nx_spray_on", "nx": true })
		"nx_flank_aim", "nx_flank_lock":
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": float(d.get("radius", 200.0)),
				"half": PGeom.deg(float(d.get("arcDeg", 70.0))) / 2.0,
				"prog": clampf(stt / maxf(0.001, float(d.get("aim", 0.55))), 0.0, 1.0), "locked": locked, "nx": true })
		"nx_drive_aim", "nx_drive_lock":
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": float(d.get("radius", 185.0)),
				"half": PGeom.deg(float(d.get("arcDeg", 150.0))) / 2.0,
				"prog": clampf(stt / maxf(0.001, float(d.get("aim", 0.6))), 0.0, 1.0), "locked": locked, "nx": true })

## 회복 구슬 배치용: 새 패턴의 예고 안인가
static func in_danger(st: CombatState, e: Dictionary, pt: Dictionary) -> bool:
	var out: Array = []
	threats(st, e, out)
	var pp := { "x": float(pt.x), "y": float(pt.y), "r": 14.0 }
	for th in out:
		if PBot.inside(th, pp):
			return true
	return false
