class_name PSkillBot
extends PBot
## 실력 프로필 봇(가상 조작 모델 — 실제 초보/평균/상위 플레이어가 아니다. 사람 보정 미완료). 프로필 값은 data/bots.json(시험값), 규칙은 docs/BOT_FRAMEWORK.md.
## 기존 PBot 정책(stand/active/aggressive/balanced/…)은 그대로 두고 step_input만 덮어쓴다. PStepDriver·PBot.run_combat이 PBot로 받으므로 그대로 꽂힌다.
## 흐름(지시문 §4): CombatState → PObserve.take(읽기 전용 스냅샷) → 지각(새 위협 인식 지연·추적 갱신 지연, 봇 RNG) → 판단(간격마다) → 입력 {mx,my,dodge_press,dodge_held,special,skill_e}.
## - 인식 지연은 attack_id마다 1회 표본(봇 seed). 추적 중 기하가 바뀌어도 인식을 다시 시작하지 않고 추적 갱신 지연 뒤에만 새 기하를 안다(그 사이 봇이 아는 기하는 오래된 복사본).
## - 주의력: 공통 긴급도(안에 있음 > 단계 > 도형까지 거리)로 상위 N개만 고려. 숨은 정보로 '정답 공격'을 골라 주지 않는다.
## - 회피: 후보 방향 중 고려한 위협 도형의 합집합에서 벗어나는 가장 짧은 방향, 지형에 막히는 방향 제외, 방향 오차는 판단당 1회 표본. 누름 길이는 실제 게임 회피 규칙(70~150·hold)을 스냅샷 rules에서 읽어 조작 타이머로만 정한다.
## - Q/E는 모든 프로필 같은 단순 규칙(200 안 3마리 Q, E 보유·200 안 2마리). 자동 공격은 게임이 한다. 실력 비교는 이동·회피 차이만 본다.
## - 재사용 표시가 판단 간격의 절반 이하로 남았으면 미리 누른다(사람처럼 조금 이른 누름 → 게임이 거절, 계측에 '재사용 중 거절'로 남는다).

const BOT_VERSION := "skillbot-0.1" # STEP은 PBot.STEP(1/120)

var profile_id: String = "regular"
var prof: Dictionary = {}
var common: Dictionary = {}
var traits: Dictionary = {}
var bot_seed: int = 1
var brng: PRng
var observer := PObserve.new()
var decide_steps: int = 12
var track_steps: int = 12
var recog_lo: int = 24
var recog_hi: int = 42
var known: Dictionary = {}       # attack_id → {first_step, recog_step, seen_step, geom, tracked_step, inside_seen, input_step}
var next_decide: int = 0
var hold_until: int = -1         # 회피 누름 유지 종료 단계(조작 타이머). 1<<30 = 끝날 때까지
var out_last: Dictionary = { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }
var escape_id: String = ""       # 지금 벗어나려는 위협
var inside_ids: Array = []       # 마지막 판단에서 플레이어를 담고 있던(고려한) 위협
var steer_mem: Dictionary = { "steer_side": 0, "steer_t": 0.0 }
var lat: Dictionary = { "recog_ms": [], "first_input_ms": [], "decisions": 0, "dodge_reqs": [], "rng_draws": 0, "threats_seen": 0, "threats_inside": 0 }
var last_snap: Dictionary = {}

func _init(pid: String = "regular", seed_v: int = 1, opts: Dictionary = {}) -> void:
	super("skill:" + pid)
	profile_id = pid
	var B := PCatalog.bots()
	var P: Dictionary = B.get("profiles", {})
	prof = (P[pid] as Dictionary).duplicate(true) if P.has(pid) else (P.get("regular", {}) as Dictionary).duplicate(true)
	common = (B.get("common", {}) as Dictionary).duplicate(true)
	for k in B.get("traits", {}):
		if String(k) != "note":
			traits[String(k)] = bool(B.traits[k].get("default", false))
	for k in opts.get("traits", {}):
		traits[String(k)] = bool(opts.traits[k])
	for k in opts.get("overrides", {}):
		prof[String(k)] = opts.overrides[k]
	bot_seed = seed_v if seed_v != 0 else 1
	brng = PRng.new(bot_seed)
	decide_steps = maxi(1, int(round(float(prof.get("decide_ms", 100)) / 1000.0 / STEP)))
	track_steps = maxi(1, int(round(float(prof.get("track_ms", 100)) / 1000.0 / STEP)))
	var rr: Array = prof.get("recog_ms", [200, 350])
	recog_lo = int(round(float(rr[0]) / 1000.0 / STEP))
	recog_hi = int(round(float(rr[1]) / 1000.0 / STEP))
	lat.decide_ms = float(prof.get("decide_ms", 100))
	lat.profile = pid
	lat.bot_seed = bot_seed

static func profile_ids() -> Array:
	var out := []
	for k in PCatalog.bot_profiles():
		out.append(String(k))
	return out

## 보고서 머리말용 프로필 값(코드가 아니라 데이터에서)
static func profile_table() -> Dictionary:
	return PCatalog.bot_profiles().duplicate(true)

## 프로필·공통 규칙 해시(캐시 키)
static func profile_hash() -> String:
	return JSON.stringify(PCatalog.bots()).sha256_text().substr(0, 16)

# ---------- 입력(사람과 같은 형식) ----------
func step_input(st: CombatState) -> Dictionary:
	var snap := observer.take(st, int(st.step_n) >= next_decide) # 판단 단계에만 전체 스냅샷, 그 외에는 지각용 부분 스냅샷
	var inp := step_snapshot(snap)
	if st.recorder != null: # 계측에 '그 순간 봇이 인식한 위험'을 넘긴다(피격 태그용). 규칙에는 영향 없음
		st.recorder.bot_ctx = bot_context(snap)
	return inp

## 스냅샷만으로 입력을 만든다(미래 정보 누출 검사는 이 함수에 같은 스냅샷을 넣어 확인한다)
func step_snapshot(snap: Dictionary) -> Dictionary:
	var n: int = int(snap.step_n) # 이번에 실행될 단계 번호는 n+1이지만 판단 주기 계산에는 현재 값이면 충분하다
	perceive(snap, n)
	var p: Dictionary = snap.player
	if n >= next_decide and bool(snap.get("full", true)):
		last_snap = snap
		next_decide = n + decide_steps
		out_last = decide_skill(snap, n)
		lat.decisions = int(lat.decisions) + 1
		return out_last
	return { "mx": float(out_last.mx), "my": float(out_last.my), "dodge_press": false, "dodge_held": bool(p.dodge_active) and n < hold_until, "special": false, "skill_e": false }

## 계측 문맥: 인식한 위협·벗어나려는 위협·안에 있다고 본 위협·마지막 입력
func bot_context(snap: Dictionary) -> Dictionary:
	var perceived := {}
	var n: int = int(snap.step_n)
	for id in known:
		var k: Dictionary = known[id]
		if int(k.recog_step) <= n:
			perceived[id] = int(k.recog_step)
	return { "step": n, "perceived": perceived, "escape_id": escape_id, "inside": inside_ids.duplicate(), "moving": absf(float(out_last.mx)) + absf(float(out_last.my)) > 0.0, "profile": profile_id }

# ---------- 지각 ----------
func perceive(snap: Dictionary, n: int) -> void:
	var seen := {}
	var new_ids := []
	for th in snap.threats:
		var id := String(th.attack_id)
		seen[id] = true
		if not known.has(id):
			new_ids.append(id)
			continue
		var k: Dictionary = known[id]
		k.seen_step = n
		if int(k.inside_first) < 0 and String(th.harm) == "damage" and PObserve.inside(th, float(snap.player.x), float(snap.player.y), float(snap.player.r)):
			k.inside_first = n # 이 위협이 처음으로 플레이어를 담은 단계(최초 입력 지연의 기준: 예고 시작과 담김 중 늦은 쪽)
		if n >= int(k.recog_step) and n - int(k.tracked_step) >= track_steps: # 추적 갱신: 지연 뒤에만 새 기하를 안다(인식은 다시 시작하지 않는다)
			k.geom = th.duplicate(true)
			k.tracked_step = n
	new_ids.sort() # 봇 난수 소비 순서를 단계 안에서 확정
	for id in new_ids:
		var th: Dictionary = {}
		for t in snap.threats:
			if String(t.attack_id) == id:
				th = t
				break
		# 같은 공격 인스턴스의 새 부분(예: 조준선 e5#2 → 날아가는 화살 e5#2:proj0, 2번째 직선 :lane1)은 이미 인식한 공격을 이어받는다(인식 지연 재시작 없음)
		var base: String = id.split(":")[0]
		var parent: Dictionary = {}
		if id.find(":") >= 0:
			for kid in known:
				if String(kid).split(":")[0] == base:
					parent = known[kid]
					break
		var ins0: int = n if (String(th.harm) == "damage" and PObserve.inside(th, float(snap.player.x), float(snap.player.y), float(snap.player.r))) else -1
		if not parent.is_empty():
			known[id] = { "first_step": n, "recog_step": maxi(n, int(parent.recog_step)), "seen_step": n, "geom": th.duplicate(true), "tracked_step": n, "inside_seen": false, "input_step": -1, "inside_first": ins0 }
			continue
		var delay: int = recog_lo + int(floor(brng.next() * float(recog_hi - recog_lo + 1)))
		lat.rng_draws = int(lat.rng_draws) + 1
		delay = clampi(delay, recog_lo, recog_hi)
		known[id] = { "first_step": n, "recog_step": n + delay, "seen_step": n, "geom": th.duplicate(true), "tracked_step": n, "inside_seen": false, "input_step": -1, "inside_first": ins0 }
		(lat.recog_ms as Array).append(snapped(float(delay) * STEP * 1000.0, 0.1))
		lat.threats_seen = int(lat.threats_seen) + 1
	for id in known.keys(): # 화면에서 사라진 위협: 인식 대기 중이었으면 입력 없이 버린다
		if not seen.has(id):
			known.erase(id)

## 인식 완료·아직 보이는 위협의(봇이 아는) 기하 목록
func perceived_threats(n: int) -> Array:
	var out := []
	for id in known:
		var k: Dictionary = known[id]
		if n >= int(k.recog_step):
			out.append(k.geom)
	out.sort_custom(func(a, b): return String(a.attack_id) < String(b.attack_id))
	return out

# ---------- 판단 ----------
static func _phase_w(th: Dictionary) -> float:
	var ph := String(th.phase)
	if ph == "active":
		return 2.0
	if ph == "lock":
		return 1.5
	return float(th.prog)

func urgency(th: Dictionary, p: Dictionary) -> float:
	var margin := float(common.get("safety_margin", 6.0))
	var ins := PObserve.inside(th, float(p.x), float(p.y), float(p.r), margin)
	var d := PObserve.dist_to(th, float(p.x), float(p.y), float(p.r))
	var harm_w := 1.0 if String(th.harm) == "damage" else 0.3
	return (3.0 if ins else 0.0) + _phase_w(th) + 1.0 / (1.0 + d / 100.0) * harm_w

func decide_skill(snap: Dictionary, n: int) -> Dictionary:
	var p: Dictionary = snap.player
	var px := float(p.x)
	var py := float(p.y)
	var pr := float(p.r)
	var margin := float(common.get("safety_margin", 6.0))
	var all_th := perceived_threats(n)
	var scored := []
	for th in all_th:
		scored.append([urgency(th, p), th])
	scored.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] > b[0]
		return String(a[1].attack_id) < String(b[1].attack_id))
	var att: int = 1 if bool(traits.get("nearest_only", false)) else int(prof.get("attention", 4))
	var consider := []
	for i in mini(att, scored.size()):
		consider.append(scored[i][1])
	var inside := []
	# 반응 문턱(모든 프로필 공통, 공개 정보만): 추적 중인 예고(warn)는 진행률이 warn_react_prog 이상일 때, 남은 초가 표시되는 예고는 그 초가 shown_react_sec 이하일 때만 '벗어날 위협'으로 본다.
	# 조준선은 플레이어를 따라오므로 항상 즉시 비키면 거리를 좁힐 수 없다(궁수에게 영원히 비켜 서기만 함). 문턱 전에는 접근을 계속한다
	var gate := float(common.get("warn_react_prog", 0.4))
	var gate_sec := float(common.get("shown_react_sec", 0.9))
	for th in consider:
		if String(th.harm) != "damage" or not PObserve.inside(th, px, py, pr, margin):
			continue
		var waiting: bool = (float(th.shown_left) > gate_sec) if float(th.shown_left) >= 0.0 else (String(th.phase) == "warn" and float(th.prog) < gate)
		if waiting:
			continue
		inside.append(th)
	inside_ids = []
	for th in inside:
		inside_ids.append(String(th.attack_id))
		var k: Dictionary = known.get(String(th.attack_id), {})
		if not k.is_empty():
			k.inside_seen = true
	var mv := [0.0, 0.0]
	var dodge := false
	var press_len := ""
	var rules: Dictionary = snap.rules
	if not inside.is_empty():
		escape_id = String(inside[0].attack_id)
		var esc := pick_escape(consider, snap, margin)
		var dir: Array = esc.dir
		var d_free: float = float(esc.d_free)
		# 화면 예고 진행률로 대략적 도달 시간 추정(정확한 발동 시각은 받지 않는다)
		var est_left := INF
		for th in inside:
			var left: float
			if float(th.shown_left) >= 0.0:
				left = float(th.shown_left)
			elif String(th.phase) == "active":
				left = 0.0
			elif String(th.phase) == "lock":
				left = float(common.get("lock_est_sec", 0.15))
			else:
				left = (1.0 - float(th.prog)) * float(common.get("warn_est_sec", 0.6))
			est_left = minf(est_left, left)
		var walk_reach: float = float(rules.speed) * est_left * float(common.get("walk_factor", 0.8))
		var slack: float = float(prof.get("decide_ms", 100)) / 1000.0 * float(common.get("press_slack_frac", 0.5))
		var can_dodge: bool = not bool(p.dodge_active) and float(p.dodge_cd) <= slack
		var greedy: bool = bool(traits.get("greedy_attack", false)) and est_left > float(common.get("lock_est_sec", 0.15)) + 0.05
		if greedy:
			mv = [0.0, 0.0]
		elif d_free <= walk_reach and d_free < INF:
			mv = dir
		elif can_dodge:
			dodge = true
			mv = dir
			press_len = press_policy(d_free, rules)
		else:
			mv = dir if d_free < INF else esc.dir
		if dodge or (mv[0] != 0.0 or mv[1] != 0.0):
			var err_deg := float(prof.get("angle_err_deg", 8.0))
			var err: float = brng.range_f(-err_deg, err_deg) * PI / 180.0 # 판단당 1회 표본(매 단계 흔들지 않는다)
			lat.rng_draws = int(lat.rng_draws) + 1
			var a: float = atan2(float(mv[1]), float(mv[0])) + err
			mv = [cos(a), sin(a)]
			for th in inside: # 최초 입력 지연 측정: 이 위협이 화면에 나타난 뒤 봇이 처음 그것 때문에 입력을 바꾼 단계
				var k2: Dictionary = known.get(String(th.attack_id), {})
				if not k2.is_empty() and int(k2.input_step) < 0:
					k2.input_step = n
					var ref_step: int = maxi(int(k2.first_step), int(k2.inside_first)) # 예고 시작과 '플레이어를 담기 시작' 중 늦은 쪽부터 잰다
					(lat.first_input_ms as Array).append(snapped(float(n - ref_step) * STEP * 1000.0, 0.1))
					lat.threats_inside = int(lat.threats_inside) + 1
	else:
		escape_id = ""
		mv = approach(snap, consider)
	# Q/E(공통 단순 규칙)
	var special := false
	var skill_e := false
	var near := 0
	var near_e := 0
	for e in snap.enemies:
		if bool(e.structure):
			continue
		var d := PGeom.dist(float(e.x), float(e.y), px, py)
		if d < float(common.get("near_dist", 200.0)):
			near += 1
		if d < float(common.get("e_range", 200.0)):
			near_e += 1
	var boss_near: bool = not snap.boss.is_empty() and not bool(snap.boss.dead) and PGeom.dist(float(snap.boss.x), float(snap.boss.y), px, py) < float(common.get("boss_q_dist", 180.0))
	var hoard := bool(traits.get("hoard_qe", false))
	if float(p.special_cd) <= 0.0 and (near >= int(common.get("q_min_near", 3)) or boss_near):
		special = not hoard or float(p.hp) < float(p.hp_max) * 0.5
	if bool(p.has_e) and float(p.e_cd) <= 0.0 and near_e >= (4 if hoard else int(common.get("e_min_near", 2))):
		skill_e = true
		if String(p.e_id) == "ward" and inside.is_empty() and float(p.hp) > float(p.hp_max) * 0.7:
			skill_e = false
	if dodge:
		var hs := hold_steps_for(press_len, rules)
		hold_until = (1 << 30) if hs < 0 else n + hs
		(lat.dodge_reqs as Array).append({ "step": n, "press": press_len, "hold_steps": hs, "dir": [snapped(mv[0], 0.001), snapped(mv[1], 0.001)], "escape": escape_id })
	return { "mx": mv[0], "my": mv[1], "dodge_press": dodge, "dodge_held": dodge or (bool(p.dodge_active) and n < hold_until), "special": special, "skill_e": skill_e }

## 누름 길이 정책: novice "max" = 항상 끝까지, "smart" = 빠져나갈 거리로 짧음/중간/김
func press_policy(d_free: float, _rules: Dictionary) -> String:
	if bool(traits.get("long_dodge", false)) or String(prof.get("press", "smart")) == "max":
		return "long"
	if d_free <= float(common.get("press_short_max", 75.0)):
		return "short"
	if d_free <= float(common.get("press_medium_max", 115.0)):
		return "medium"
	return "long"

## 요청 누름 시간(단계). 실제 거리는 게임의 회피 규칙이 정한다(최소 거리·충돌·최대 거리). -1 = 끝날 때까지
func hold_steps_for(press_len: String, rules: Dictionary) -> int:
	if press_len == "long" or String(rules.dodge_mode) != "hold":
		return -1
	if press_len == "short":
		return 0 # 누른 단계에 바로 뗌 → 최소 거리
	var spd: float = float(rules.dodge_distance) / maxf(1e-6, float(rules.dodge_duration))
	var target: float = (float(rules.dodge_min) + float(rules.dodge_distance)) * 0.5
	return maxi(1, int(ceil(target / spd / STEP)))

## 회피 방향 후보 중 고려한 위협 합집합을 가장 짧게 벗어나는 방향. 지형(경계·장애물)에 먼저 막히는 후보는 제외. 반환 {dir, d_free, blocked}
func pick_escape(consider: Array, snap: Dictionary, margin: float) -> Dictionary:
	var p: Dictionary = snap.player
	var px := float(p.x)
	var py := float(p.y)
	var pr := float(p.r)
	var nd: int = int(prof.get("dodge_dirs", 8))
	var step_px := float(common.get("escape_sample_px", 10.0))
	var max_px := float(common.get("escape_max_px", 150.0))
	var best_dir := [0.0, 0.0]
	var best_d := INF
	var best_clear := -INF
	var fallback := [0.0, 0.0]
	var fallback_score := -INF
	var enemies: Array = snap.enemies
	for i in nd:
		var a := float(i) / float(nd) * TAU
		var dx := cos(a)
		var dy := sin(a)
		var d := step_px
		var d_free := INF
		var blocked := false
		while d <= max_px + 1e-6:
			var x := px + dx * d
			var y := py + dy * d
			if not PObserve.valid_pos(snap, x, y, pr):
				blocked = true
				break
			var ins := false
			for th in consider:
				if String(th.harm) == "damage" and PObserve.inside(th, x, y, pr, margin):
					ins = true
					break
			if not ins:
				d_free = d
				break
			d += step_px
		var clear := INF # 후보 끝점에서 가장 가까운 적까지 거리(동률이면 더 트인 쪽)
		var ex := px + dx * minf(d_free, max_px)
		var ey := py + dy * minf(d_free, max_px)
		for e in enemies:
			if bool(e.structure):
				continue
			clear = minf(clear, PGeom.dist(float(e.x), float(e.y), ex, ey))
		if not blocked and d_free < INF:
			if d_free < best_d - 1e-6 or (absf(d_free - best_d) <= 1e-6 and clear > best_clear):
				best_d = d_free
				best_dir = [dx, dy]
				best_clear = clear
		elif not blocked and clear > fallback_score: # 어느 방향도 못 벗어나면 가장 트인 방향
			fallback_score = clear
			fallback = [dx, dy]
	if best_d < INF:
		return { "dir": best_dir, "d_free": best_d, "blocked": false }
	if fallback[0] == 0.0 and fallback[1] == 0.0:
		fallback = [1.0, 0.0]
	return { "dir": fallback, "d_free": INF, "blocked": true }

## 위협이 없을 때: 가장 가까운(보스 우선) 적에게 유지 거리까지 접근, 너무 가까우면 물러남. 활성 지역 안으로 걸어 들어가지 않는다
func approach(snap: Dictionary, consider: Array) -> Array:
	var p: Dictionary = snap.player
	var px := float(p.x)
	var py := float(p.y)
	var pr := float(p.r)
	var target := {}
	var bd := INF
	if not snap.boss.is_empty() and not bool(snap.boss.dead):
		target = snap.boss
		bd = PGeom.dist(float(target.x), float(target.y), px, py)
	else:
		for e in snap.enemies:
			if bool(e.structure):
				continue
			var d := PGeom.dist(float(e.x), float(e.y), px, py)
			if d < bd:
				bd = d
				target = e
	if target.is_empty():
		return [0.0, 0.0]
	var rules: Dictionary = snap.rules
	var want: float = float(common.get("keep_dist", 55.0))
	if bool(rules.orbit_only):
		want = float(rules.weapon_range) * 0.9
	if bool(target.get("boss", false)) or target.has("boss_id"):
		want = float(target.r) + (40.0 if String(target.get("state", "")) in ["recover", "stagger"] else float(rules.weapon_range) * 0.7)
	var mv := [0.0, 0.0]
	var tx := float(target.x)
	var ty := float(target.y)
	if bd > want + 10.0:
		if float(steer_mem.get("steer_t", 0.0)) > 0.0:
			steer_mem.steer_t = float(steer_mem.steer_t) - float(prof.get("decide_ms", 100)) / 1000.0
		mv = PObserve.steer(snap, px, py, pr, tx, ty, steer_mem) if (snap.obstacles as Array).size() > 0 else PGeom.norm(tx - px, ty - py)
	elif bd < want - 30.0:
		var n := PGeom.norm(tx - px, ty - py)
		mv = [-n[0], -n[1]]
	if mv[0] == 0.0 and mv[1] == 0.0:
		return mv
	# 앞 30px가 고려 중인 활성 지역(장판) 안이면 비켜 간다
	var zm := float(common.get("zone_margin", 24.0))
	for rot in [0.0, 0.8, -0.8, 1.6, -1.6]:
		var a: float = atan2(float(mv[1]), float(mv[0])) + float(rot)
		var cx := px + cos(a) * 30.0
		var cy := py + sin(a) * 30.0
		var bad := false
		for th in consider:
			if String(th.harm) == "damage" and String(th.phase) == "active" and String(th.kind) == "circle" and PObserve.inside(th, cx, cy, pr, zm):
				bad = true
				break
		if not bad:
			return [cos(a), sin(a)]
	return [0.0, 0.0]

# ---------- 지연·조작 통계 ----------
static func _pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return -1.0
	var s := arr.duplicate()
	s.sort()
	var idx := int(floor(q * float(s.size() - 1)))
	return float(s[clampi(idx, 0, s.size() - 1)])

static func _avg(arr: Array) -> float:
	if arr.is_empty():
		return -1.0
	var t := 0.0
	for v in arr:
		t += float(v)
	return t / float(arr.size())

## 보고서용 지연 통계: 판단 간격, 인식 지연(위협별), 실제 최초 입력 지연(예고 시작 → 첫 입력 변경)
func latency_report() -> Dictionary:
	var r: Array = lat.recog_ms
	var f: Array = lat.first_input_ms
	return { "profile": profile_id, "bot_seed": bot_seed, "bot_version": BOT_VERSION, "decide_ms": float(lat.decide_ms), "decisions": int(lat.decisions), "rng_draws": int(lat.rng_draws),
		"threats_seen": int(lat.threats_seen), "threats_inside": int(lat.threats_inside),
		"recog_n": r.size(), "recog_avg_ms": snapped(_avg(r), 0.1), "recog_p50_ms": _pct(r, 0.5), "recog_min_ms": (_pct(r, 0.0)), "recog_max_ms": (_pct(r, 1.0)),
		"first_input_n": f.size(), "first_input_avg_ms": snapped(_avg(f), 0.1), "first_input_p50_ms": _pct(f, 0.5), "first_input_p90_ms": _pct(f, 0.9), "first_input_max_ms": _pct(f, 1.0),
		"dodge_reqs": (lat.dodge_reqs as Array).size(), "press_short": _count_press("short"), "press_medium": _count_press("medium"), "press_long": _count_press("long") }

func _count_press(kind: String) -> int:
	var n := 0
	for d in lat.dodge_reqs:
		if String(d.press) == kind:
			n += 1
	return n
