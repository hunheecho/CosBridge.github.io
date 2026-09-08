class_name PBoss
extends RefCounted
## 보스 '가시갈기 — 숲의 왕' 행동(HTML boss.js 이식). CombatState.update_enemies가 boss 개체에 대해 update를 부른다.
## 봉인 수호자(guardian)·예언을 먹는 자(eater)는 boss_id로 PBoss2에 넘긴다.
## 상태 이름·시간·판정·fx 종류·문구·이벤트는 HTML과 같다. 좌표 쌍은 [x, y] 배열, 지점은 {x, y} 사전.

## 가시갈기 설정(PA.BOSS)
static func _B() -> Dictionary:
	return PCatalog.boss_defs().boss

## 이번 행동 개편의 새 조정값(data/boss_behavior.json). PCatalog(공용 카탈로그)를 건드리지 않고 여기서만 읽는다.
## 파일이 없으면 모든 개편이 꺼진 것과 같다(원래 행동). 숫자는 코드에 두지 않는다 — 전부 이 파일에 있다.
static var _behavior: Dictionary = {}
static func behavior() -> Dictionary:
	if not _behavior.is_empty():
		return _behavior
	var f := FileAccess.open("res://data/boss_behavior.json", FileAccess.READ)
	if f == null:
		_behavior = { "enabled": false }
		return _behavior
	var parsed = JSON.parse_string(f.get_as_text())
	_behavior = parsed if typeof(parsed) == TYPE_DICTIONARY else { "enabled": false }
	return _behavior

## 보스별 개편 설정. 없으면 빈 사전(원래 행동 유지)
static func beh_of(boss_id: String) -> Dictionary:
	var B := behavior()
	if not bool(B.get("enabled", false)):
		return {}
	var bs: Dictionary = B.get("bosses", {})
	return bs.get(boss_id, {})

## 개체별 개편 설정. e.beh_off = true면 이 개체만 개편 전(073f74f) 행동으로 돌아간다.
## 패턴 자체의 판정·예고·빈틈을 확인하는 단위 시험(boss_tests·boss3_tests)이 연계·옆뛰기와 섞이지 않게 하는 스위치다.
static func beh_e(e: Dictionary) -> Dictionary:
	if bool(e.get("beh_off", false)):
		return {}
	return beh_of(String(e.get("boss_id", "boss")))

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
	chain_init(e)
	st.boss = e
	if boss_id != "boss":
		PBoss2.init(st, e)
	return e

# ---------- 연계(chain)·옆 뛰기(hop) 공통 엔진: 보스 9종이 함께 쓴다 ----------
## 설계(사용자 요청 §6): 작은 행동마다 긴 빈틈을 주지 않는다. 한 행동이 끝나면 짧은 이동 구간(link)만 두고 다음 행동으로 잇고,
## 연계 전체가 끝난 시점에 한 번, 원래보다 조금 더 긴 빈틈(확실한 공격 기회)을 준다.
## 예고는 연계 첫 공격에서 데이터의 원래 값 그대로다. 후속타만 예고 진행이 빨라지며 그것도 followWarnMin 하한을 지킨다.
## (모든 예고·빈틈을 같은 비율로 줄이는 방식은 쓰지 않는다.)

static func chain_cfg(e: Dictionary) -> Dictionary:
	return beh_e(e).get("chain", {})

## 이번 단계에서 한 연계에 넣을 수 있는 최대 행동 수
static func chain_max(e: Dictionary) -> int:
	var C := chain_cfg(e)
	if C.is_empty():
		return 1
	var arr: Array = C.get("maxByPhase", [1, 1, 1])
	return int(arr[mini(arr.size() - 1, maxi(0, int(e.get("phase", 1)) - 1))])

## 패턴의 원래 예고(준비 + 방향 고정) 합. 보스 정의의 같은 이름 키에서 읽는다(코드에 숫자를 두지 않는다)
static func pattern_warn(cfg: Dictionary, pat: String) -> float:
	if not cfg.has(pat) or typeof(cfg[pat]) != TYPE_DICTIONARY:
		return 0.0
	var d: Dictionary = cfg[pat]
	# 준비 구간 키 우선순위 aim → cast → warn. (낙석의 warn은 예고가 아니라 '떨어지기까지의 시간'이라 뒤에 둔다)
	var a := float(d.get("aim", d.get("cast", d.get("warn", 0.0))))
	return a + float(d.get("lock", 0.0))

## 지금 상태가 '예고(준비·방향 고정)' 구간인가 — 실행·빈틈·접근·소환 채널·옆 이동은 아니다
static func is_warn_state(s: String) -> bool:
	return s.ends_with("_aim") or s.ends_with("_lock") or s.ends_with("_warn") or s.ends_with("_cast") or s == "dash_reaim" or s == "dash_relock"

## 예고 진행 배속(연계 첫 공격은 1.0). 예고 구간에만 적용되고 실행·빈틈·접근에는 적용되지 않는다
static func prep_speed(e: Dictionary) -> float:
	if not is_warn_state(String(e.get("state", ""))):
		return 1.0
	return float(e.get("warn_speed", 1.0))

static func chain_init(e: Dictionary) -> void:
	e.chain_i = 0
	e.chain_next = ""
	e.warn_speed = 1.0
	e.hop_left = 0.0
	e.hop_dir = [0.0, 0.0]
	e.chain_ok = false
	e.chain_live = false

static func chain_reset(e: Dictionary) -> void:
	e.chain_i = 0
	e.chain_next = ""
	e.warn_speed = 1.0

## approach의 판단으로 행동을 시작할 때 표시한다. 규칙 밖에서 상태를 직접 넣은 행동(시험·디버그)은 연계로 이어지지 않는다
static func chain_arm(e: Dictionary) -> void:
	e.chain_ok = true

## begin()에서 호출: 연계 번호를 올리고, 후속타면 예고 배속을 정한다(하한 followWarnMin 이상으로만)
static func chain_note_begin(e: Dictionary, cfg: Dictionary, pat: String) -> void:
	e.chain_live = bool(e.get("chain_ok", false))
	e.chain_ok = false
	e.chain_i = int(e.get("chain_i", 0)) + 1
	var C := chain_cfg(e)
	var sp := 1.0
	if not C.is_empty() and int(e.chain_i) >= 2:
		var base := pattern_warn(cfg, pat)
		var lo := float(C.get("followWarnMin", 0.5))
		if base > lo:
			sp = minf(float(C.get("followWarnSpeed", 1.0)), base / lo)
	e.warn_speed = maxf(1.0, sp)

## 이번 보스가 지금 거리·단계·재사용으로 고를 수 있는 후보 [[이름, 가중치], ...]
static func live_candidates(st: CombatState, e: Dictionary) -> Array:
	var bid := String(e.get("boss_id", "boss"))
	if bid == "boss":
		return candidates(st, e)
	if PBoss3.has(bid):
		return PBoss3.candidates(st, e)
	return PBoss2.candidates(st, e)

## 연계표에서 다음 행동을 뽑는다. 지금 못 하는 행동은 제외하고, 같은 행동 3연속 금지도 그대로 적용
static func chain_pick(st: CombatState, e: Dictionary) -> String:
	var C := chain_cfg(e)
	var follow: Dictionary = C.get("follow", {})
	var h: Array = e.get("history", [])
	var last := ""
	if h.size() > 0:
		last = String(h[h.size() - 1])
	var live: Array = []
	for c in live_candidates(st, e):
		live.append(String(c[0]))
	# 직전 행동에 맞춘 연계표를 먼저 보고, 지금 할 수 있는 것이 없으면 공통 후보("*")로 내려간다
	var pool := _chain_pool(follow.get(last, []), live)
	if pool.is_empty():
		pool = _chain_pool(follow.get("*", []), live)
	if pool.is_empty():
		return ""
	return _pick_weighted(st, h, pool)

static func _chain_pool(want: Array, live: Array) -> Array:
	var pool: Array = []
	for w in want:
		if live.has(String(w[0])):
			pool.append([String(w[0]), float(w[1])])
	return pool

## 착탄·낙하를 기다리는 상태(표식·포자 탄·낙석)는 정해진 시각에 스스로 진행된다(update_marks/update_rocks).
## 첫 예고가 자리를 잡은 뒤에는 보스가 서서 기다리지 않고 다음 행동으로 이을 수 있다 — chainAfter 초 뒤부터.
static func chain_early(st: CombatState, e: Dictionary, pat: String, state_t: float) -> bool:
	var o: Dictionary = beh_e(e).get(pat, {})
	if not o.has("chainAfter") or state_t < float(o.chainAfter):
		return false
	return chain_continue(st, e)

## 소환·호효로 연계가 끝나는 경우에도 빈틈을 준다(연계 끝에는 반드시 확실한 공격 기회가 온다)
static func summon_end(st: CombatState, e: Dictionary) -> void:
	if chain_continue(st, e):
		return
	var C := chain_cfg(e)
	if C.is_empty():
		chain_reset(e)
		e.state = "approach"
		e.state_t = 0.0
		e.approach_t = 0.0
		return
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = chain_end_recover(e, float(C.get("summonRecover", 0.9)))
	chain_reset(e)
	st.text(e.x, e.y - e.r - 30.0, "빈틈!", "#ffd166")

## 패턴의 거리 설정(개편값이 있으면 그것, 없으면 보스 정의의 값)
static func pat_num(e: Dictionary, cfg: Dictionary, pat: String, key: String, def: float) -> float:
	var o: Dictionary = beh_e(e).get(pat, {})
	if o.has(key):
		return float(o[key])
	var c: Dictionary = cfg.get(pat, {})
	return float(c.get(key, def))

## 빈틈 대신 연계를 이어갈 수 있으면 짧은 이동 구간(approach)으로 바꾸고 true.
## 이 구간에도 보스는 계속 움직인다(연계 사이에 몇 초씩 멈춰 서지 않는다).
static func chain_continue(st: CombatState, e: Dictionary) -> bool:
	var C := chain_cfg(e)
	if C.is_empty() or not bool(e.get("chain_live", false)) or int(e.get("chain_i", 0)) >= chain_max(e):
		return false
	var nxt := chain_pick(st, e)
	if nxt == "":
		return false
	e.chain_next = nxt
	e.state = "approach"
	e.state_t = 0.0
	e.wait_t = 0.0
	e.approach_t = maxf(0.0, min_approach(e, cfg_of(e)) - float(C.get("linkGap", 0.1)))
	return true

## 연계가 끝난 뒤의 빈틈: 연계가 길었으면 원래 빈틈 + endRecoverAdd
static func chain_end_recover(e: Dictionary, dur: float) -> float:
	var C := chain_cfg(e)
	if C.is_empty() or int(e.get("chain_i", 0)) < int(C.get("endBonusFrom", 99)):
		return dur
	return dur + float(C.get("endRecoverAdd", 0.0))

## approach에서 다음 행동을 고를 때: 연계로 예약된 행동이 아직 가능하면 그것을 쓴다
static func chain_take(st: CombatState, e: Dictionary) -> String:
	var nxt := String(e.get("chain_next", ""))
	if nxt == "":
		return ""
	e.chain_next = ""
	for c in live_candidates(st, e):
		if String(c[0]) == nxt:
			return nxt
	return ""

## 행동 사이 대기(minApproach): 개편값이 있으면 그것(대기 단축은 예고 단축이 아니다)
static func min_approach(e: Dictionary, cfg: Dictionary) -> float:
	var B := beh_e(e)
	return float(B.get("minApproach", cfg.minApproach))

## 옆으로 뛰어 스스로 돌진 거리를 만든다: 예고 없이 몸만 움직이고(무적 없음) 준비(*_aim) 구간 안에서 일어난다.
## 예고 각은 계속 플레이어를 따라가므로 화면·봇이 보는 예고와 실제가 같다.
static func hop_cfg(e: Dictionary) -> Dictionary:
	return beh_e(e).get("hop", {})

## begin()에서 호출: 이 패턴의 최소 거리를 못 채웠으면 옆 이동을 예약한다
static func hop_note_begin(st: CombatState, e: Dictionary, cfg: Dictionary, pat: String) -> void:
	e.hop_left = 0.0
	var H := hop_cfg(e)
	var pats: Array = H.get("patterns", [])
	if not pats.has(pat):
		return
	var sub: Dictionary = cfg.get(pat, {})
	var need := float(sub.get("minDist", 0.0))
	var p := st.player
	if PGeom.dist(e.x, e.y, p.x, p.y) >= need:
		return
	var a := atan2(p.y - e.y, p.x - e.x)
	var side: float = 1.0 if st.rng.next() < 0.5 else -1.0
	var back := float(H.get("back", 0.0)) # 옆 + 약간 뒤(스스로 거리를 만든다)
	var hx := -sin(a) * side - cos(a) * back
	var hy := cos(a) * side - sin(a) * back
	var hn: float = maxf(0.001, sqrt(hx * hx + hy * hy))
	e.hop_dir = [hx / hn, hy / hn]
	e.hop_left = float(H.get("time", 0.4))
	st.text(e.x, e.y - e.r - 30.0, String(H.get("text", "옆으로!")), "#ffd166")

## 준비(*_aim) 상태에서 매 단계 호출: 남은 시간만큼 옆으로 이동(감속장 안에서는 느리게)
static func hop_step(st: CombatState, e: Dictionary, adv: float) -> void:
	if float(e.get("hop_left", 0.0)) <= 0.0:
		return
	var H := hop_cfg(e)
	var use: float = minf(adv, float(e.hop_left))
	e.hop_left = float(e.hop_left) - use
	var spd := float(H.get("speed", 220.0))
	var dir: Array = e.hop_dir
	st.move_swept(e, float(dir[0]) * spd * use, float(dir[1]) * spd * use)

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

## 지금 거리·단계·재사용에서 고를 수 있는 행동 후보 [[이름, 가중치], ...]
## 개편(사용자 요청 §6-2): 돌진은 최소 거리를 못 채워도 후보다 — 옆으로 뛰어 스스로 거리를 만든 뒤 돌진한다.
## 따라서 가까이 붙은 상대에게도 휩쓸기 말고 이동 공격 후보가 남는다.
static func candidates(st: CombatState, e: Dictionary) -> Array:
	var cfg := _B()
	var B := beh_e(e)
	var p := st.player
	var d := PGeom.dist(e.x, e.y, p.x, p.y)
	var los: bool = not st.los_blocked(e.x, e.y, p.x, p.y)
	var cands: Array = []
	if d <= float(cfg.sweep.maxDist) and los:
		cands.append(["sweep", float(cfg.weights.sweep)])
	var hop_dash: bool = (hop_cfg(e).get("patterns", []) as Array).has("dash")
	if d <= float(cfg.dash.maxDist) and los and (d >= float(cfg.dash.minDist) or hop_dash):
		cands.append(["dash", float(cfg.weights.dash)])
	var Bp: Dictionary = B.get("pounce", {})
	if int(e.phase) >= int(Bp.get("minPhase", 2)) and d >= float(Bp.get("minDist", cfg.pounce.minDist)):
		cands.append(["pounce", float(cfg.weights.pounce)])
	if can_howl(st, e):
		cands.append(["howl", float(cfg.weights.howl)])
	return cands

## 후보 이름만(시험·계측용)
static func candidate_names(st: CombatState, e: Dictionary) -> Array:
	var out: Array = []
	for c in candidates(st, e):
		out.append(String(c[0]))
	return out

## 가중치 추첨. 같은 행동 세 번 연속 금지. 없으면 ""
static func choose_pattern(st: CombatState, e: Dictionary) -> String:
	if int(e.actions) == 0:
		return "dash" # 첫 공격은 단일 돌진
	var forced := chain_take(st, e) # 연계로 예약된 후속 행동이 먼저
	if forced != "":
		return forced
	var h: Array = e.history
	if h.size() == 1 and String(h[0]) == "dash" and can_howl(st, e):
		return "howl" # 첫 돌진 뒤 첫 소환
	return _pick_weighted(st, h, candidates(st, e))

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
	chain_note_begin(e, cfg_of(e), pattern)
	hop_note_begin(st, e, cfg_of(e), pattern)
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

## 행동이 끝났을 때: 연계가 남아 있으면 빈틈 대신 짧은 이동 구간으로 잇고, 아니면 연계 전체의 빈틈을 한 번 준다
static func to_recover(st: CombatState, e: Dictionary, dur: float) -> void:
	if chain_continue(st, e):
		return
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = chain_end_recover(e, dur)
	chain_reset(e)
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
	# 예고 배속은 연계 후속타의 준비·고정 구간에만 붙는다(실행·빈틈·접근은 그대로). 감속장(tf)은 모든 구간에 그대로
	var adv := dt * tf * prep_speed(e)
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
				chain_reset(e)
				e.phase = int(e.phase_pending)
				e.state = "roar"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 40.0, "추격 단계" if int(e.phase) == 2 else "마지막 맹공", "#ff9f43")
				st.ev("boss_roar", { "phase": int(e.phase) })
				st.phase_events.append(int(e.phase))
			else:
				if dist > float(cfg.stopDist):
					st.approach(e, p.x, p.y, float(cfg.speed) * sm, dt)
				if float(e.approach_t) >= min_approach(e, cfg):
					var pat := choose_pattern(st, e)
					if pat != "":
						# 겹침 제한: 늑대가 돌진 중이면 큰 공격을 잠시 미룬다(최대 bossWaitMax)
						if pat != "howl" and wolf_attacking(st) and float(e.wait_t) < float(cfg.overlap.bossWaitMax):
							e.wait_t = float(e.wait_t) + adv
						else:
							chain_arm(e) # 스스로 고른 행동만 연계로 이어진다
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
			hop_step(st, e, adv) # 옆으로 뛰어 스스로 돌진 거리를 만든다(예고 각은 계속 추적)
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
				# 소환은 주공격의 보조: 늑대를 부른 직후 보스도 바로 공격으로 잇는다(늑대만 기다리지 않는다).
				# 이을 것이 없으면 짧은 빈틈으로 끝난다(연계 끝에는 반드시 공격 기회가 온다)
				summon_end(st, e)
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
					chain_reset(e)
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
	chain_reset(e) # 방벽 파열은 연계를 끊는다
	e.state = "stagger"
	e.state_t = 0.0
	e.bite_t = 0.0
	st.text(e.x, e.y - e.r - 30.0, "비틀거림!", "#7ef2ff")
