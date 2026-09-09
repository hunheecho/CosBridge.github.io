class_name PSupportA
extends RefCounted
## 보조무기 A조: ⑥ 추격 까마귀 · ⑦ 수호 방울 · ⑧ 잔영 분신 · ⑨ 바람 정령.
## 공통 규칙(발동 자격표·제압 저항·경감 순서)은 PSupport에 있고 여기서는 그것만 쓴다.
## 수치는 data/supports.json에 있고 전부 시험값이다 — 여기 숫자를 적지 않는다.
##
## 확정한 규칙은 docs/SUPPORT_A.md에 한 곳으로 모아 두었다. 요약:
##  - 까마귀 표적은 **주무기 직접 타격**으로만 새로 지정된다(PSupport.eligible("crow_mark", ...)).
##    지정 뒤 hold초 동안은 본체가 다른 적을 때려도 안 바뀐다. 표적이 죽거나 사거리 밖으로 나갈 때만 자동으로 옮긴다.
##  - 방울은 **차단이 경감보다 먼저**다(PSupport.on_player_damage 순서). 차단하면 0을 돌려준다.
##    무엇이 차단 가능한지는 data/supports.json bell.base.incoming이 정본이고, 목록에 없으면 차단하지 않는다.
##  - 분신은 주무기 **기본** 공격만 따라 하고(PSupport.eligible("echo_copy", ...)), 자기 위치에서 사거리·모양·적중을 다시 판정한다.
##    분신의 타격 경로 이름은 "echo_direct"라 자격표가 분신의 분신을 막는다.
##  - 바람의 밀어내기 거리는 반드시 PSupport.knock_dist를 거치고 st.move_swept로 민다(벽·바위 안으로 안 들어간다).
##    잔바람은 **밀어낸 경로가 아니라 돌풍이 지나간 자리**(부채꼴의 축)에 남으므로, 밀어내기 저항이 0인
##    보스에게도 장판이 생긴다. 둔화는 겹친 조각 중 가장 센 하나만 PSupport.stack_slow에 넣어
##    최저 속도 아래로 내려가지 않게 하고, 조각이 겹쳤다는 이유로 무제한 중첩되지도 않게 한다.
##
## 수명 규칙(공통): 까마귀·분신·잔바람 장판은 (1) 제 수명이 다하거나 (2) 그 보조가 장착 목록에서 빠지거나
## (3) 전투가 끝나면 즉시 사라진다. 레벨업(st.rebuild → PWeapons.refresh)은 무기 항목을 유지하므로 개체도 유지되고,
## 보조가 교체되면 다음 갱신에서 옛 개체·장판이 전부 지워진다. 전투 시작 때는 PSupport.init_state가 st.support를 비운다.

const KINDS := ["crow", "bell", "echo", "wind"]

static func handles(kind: String) -> bool:
	return KINDS.has(kind)

# ---------- 0. 공통 도우미 ----------
## 장착한 보조의 전투용 항목(PWeapons.init이 만든 dict: stats·timer·count…). 없으면 {}
static func _wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

static func _new_state(id: String) -> Dictionary:
	match id:
		"crow":
			return { "birds": [], "target": null, "alt": null, "hold": 0.0, "next_bonus": 0.0,
				"marks": 0, "retargets": 0, "strikes": 0, "damage": 0.0, "switch_procs": 0 }
		"bell":
			return { "charges": -1, "rt": 0.0, "blocked": 0, "blocked_damage": 0.0,
				"guarded": 0, "reduced": 0.0, "reflects": 0, "reflect_damage": 0.0 }
		"echo":
			# last_count = 주무기 id → 마지막으로 복제한 발사 번호. 같은 공격의 여러 적중이 분신을 여럿 만들지 않게 한다.
			# 무기별로 따로 기억한다 — 옛 저장처럼 주무기 계열이 여러 개일 때 서로의 번호를 지워 버리지 않게
			return { "clones": [], "trail": [], "last_count": {}, "busy": false,
				"spawned": 0, "strikes": 0, "damage": 0.0, "fizzles": 0 }
		"wind":
			return { "blasts": 0, "pushed": 0, "push_total": 0.0, "push_max": 0.0,
				"gusts": 0, "slowed": 0, "slow_sec": 0.0, "slow_min": 1.0 }
	return {}

## 그 보조의 전투 중 상태(없으면 만든다). st.support는 전투 시작 때 PSupport.init_state가 비운다
static func _state(st: CombatState, id: String) -> Dictionary:
	var S: Dictionary = st.support
	if not S.has(id):
		S[id] = _new_state(id)
	return S[id]

static func _peek(st: CombatState, id: String) -> Dictionary:
	var S: Dictionary = st.support
	return S[id] if S.has(id) else {}

## 지금 들어온 적 피해가 자격표의 어느 경로인가.
## 판정은 반드시 PSupport.cause_of를 거친다(자격표 어휘의 정본이 한 곳이어야 하므로).
## 여기서는 그 함수가 읽는 모양({cause, weapon})으로 바꿔 줄 뿐이다:
##  - opt.cause가 이미 있으면 그대로 쓴다(내가 만든 타격은 항상 cause를 적어 보낸다).
##  - 지속 피해(opt.dot)는 "dot".
##  - 직접 타격이 아닌 파생 피해(src.extra 또는 direct:false)는 주무기 개조면 "main_extra", 그 밖(장판 틱·공용 효과)이면 "zone_tick".
##  - 나머지는 무기 id만 넘겨 주무기/보조를 가르게 한다.
static func _cause(st: CombatState, opt: Dictionary) -> String:
	var sr: Dictionary = opt.get("src", {})
	var wid := String(sr.get("weapon_id", ""))
	var o := {}
	if opt.has("cause"):
		o["cause"] = String(opt.cause)
	elif opt.has("dot"):
		o["cause"] = "dot"
	elif bool(sr.get("extra", false)) or not bool(sr.get("direct", true)):
		o["cause"] = "main_extra" if PCatalog.is_main_weapon(wid) else "zone_tick"
	if wid != "":
		o["weapon"] = wid
	return PSupport.cause_of(st, o)

## 밀어내기·경직을 받지 않는 상태인가(combat_state.knock_enemy와 같은 기준).
## 확정된 돌진·도약·예고 중에는 위치를 강제로 바꾸지 않는다 — 예고와 실제 판정이 어긋나지 않게.
static func _immovable(e: Dictionary) -> bool:
	if bool(e.get("structure", false)) or bool(e.get("airborne", false)) or bool(e.get("hidden", false)):
		return true
	return String(e.get("state", "")) in ["dash", "leap", "charge", "under", "warn"]

# ---------- 1. 발사 관문 ----------
## PWeapons가 주기마다 부른다. 처리했으면 true.
## 방울·분신은 주기 발사가 없다(방울 = 피격 순간, 분신 = 주무기 기본 공격 뒤).
## 그래도 true를 돌려준다 — "이 kind는 A조가 맡았다"는 뜻이고, 아무 일도 하지 않는 것이 정상 동작이다.
static func fire(st: CombatState, w: Dictionary, _target: Dictionary, _echoed: bool) -> bool:
	match String(w.stats.kind):
		"crow":
			_crow_fire(st, w)
			return true
		"wind":
			_wind_fire(st, w)
			return true
		"bell", "echo":
			return true
	return false

# ---------- 2. 매 프레임 갱신 ----------
static func update(st: CombatState, dt: float) -> void:
	if st.status != "running":
		purge_all(st) # 전투가 끝나면 남은 개체·장판을 즉시 치운다(다음 전투로 새어 나가지 않게)
		return
	_crow_update(st, dt)
	_bell_update(st, dt)
	_echo_update(st, dt)
	_wind_update(st, dt)

## A조 네 보조의 개체·장판·상태를 전부 지운다(전투 종료·시험용).
## B조(역병·갑각·인형)의 st.support 항목은 건드리지 않는다
static func purge_all(st: CombatState) -> void:
	for id in KINDS:
		_purge(st, id)

## 그 보조가 남긴 개체·장판을 지우고 상태 항목도 없앤다.
## 상태 항목이 없으면 그 보조는 이번 전투에서 아무것도 만든 적이 없으므로 훑지 않는다
## (장착하지 않은 보조 때문에 매 프레임 장판 목록을 다시 만들지 않게)
static func _purge(st: CombatState, id: String) -> void:
	var S: Dictionary = st.support
	if not S.has(id):
		return
	if id == "wind":
		var keep := []
		for z in st.zones:
			if String(z.type) != "windgust":
				keep.append(z)
		st.zones = keep
	S.erase(id)

# ---------- 3. ⑥ 추격 까마귀 ----------
## 표적 규칙(확정):
##  1) 표적은 주무기 직접 타격으로만 새로 지정된다. 보조·장판·독·반사·분신 타격으로는 바뀌지 않는다(자격표 crow_mark).
##  2) 지정 뒤 hold초 동안은 본체가 다른 적을 때려도 표적이 그대로다. 같은 적을 다시 때리면 유지 시간만 다시 채운다.
##  3) 표적이 죽거나 사거리(range) 밖으로 나가면 그때만 자동으로 옮긴다:
##     플레이어에게서 사거리 안이고 가림 없는 가장 가까운 적. 그런 적이 없으면 표적을 비우고 대기한다.
##     표적이 한 번도 없었던 상태에서는 스스로 찾지 않는다 — 주무기가 먼저 맞혀야 시작한다.
static func _crow_bird_count(st: CombatState, w: Dictionary) -> int:
	var s: Dictionary = w.stats
	if PSupport.has_mod(st, "crow", "twin"):
		return maxi(1, int(s.twinCount))
	return maxi(1, int(s.count))

static func _crow_update(st: CombatState, dt: float) -> void:
	var w := _wep(st, "crow")
	if w.is_empty():
		_purge(st, "crow")
		return
	var S := _state(st, "crow")
	var s: Dictionary = w.stats
	var p := st.player
	S.hold = maxf(0.0, float(S.hold) - dt)
	# 표적 유효성: 죽었거나 사거리 밖이면 규칙 3)으로 옮긴다
	if S.target != null:
		var tg: Dictionary = S.target
		if bool(tg.dead) or PGeom.dist(p.x, p.y, tg.x, tg.y) > float(s.range) + float(tg.r):
			_crow_retarget(st, S, s, int(tg.id))
	if S.alt != null:
		var al: Dictionary = S.alt
		if bool(al.dead) or PGeom.dist(p.x, p.y, al.x, al.y) > float(s.range) + float(al.r):
			S.alt = null
	# 쌍둥이의 두 번째 까마귀는 첫 표적과 **다른** 적을 문다(표적이 있을 때만 움직인다)
	var n := _crow_bird_count(st, w)
	if n > 1 and S.target != null and S.alt == null:
		S.alt = _crow_pick(st, s, int((S.target as Dictionary).id))
	if n <= 1:
		S.alt = null
	var birds: Array = S.birds
	while birds.size() < n:
		birds.append({ "x": p.x, "y": p.y, "hunt": 0 })
	while birds.size() > n:
		birds.pop_back()
	for i in birds.size():
		var b: Dictionary = birds[i]
		var goal := _crow_goal(st, S, s, i)
		var d := PGeom.dist(float(b.x), float(b.y), float(goal[0]), float(goal[1]))
		var stp := float(s.speed) * dt
		if d <= stp or d < 1e-6:
			b.x = float(goal[0])
			b.y = float(goal[1])
		else:
			b.x = float(b.x) + (float(goal[0]) - float(b.x)) / d * stp
			b.y = float(b.y) + (float(goal[1]) - float(b.y)) / d * stp

## 까마귀 i가 지금 가려는 자리. 표적이 있으면 그 위, 없으면 플레이어 곁을 도는 자리
static func _crow_goal(st: CombatState, S: Dictionary, s: Dictionary, i: int) -> Array:
	var tgt = S.target if i == 0 else S.alt
	if tgt != null and not bool((tgt as Dictionary).dead):
		var t2: Dictionary = tgt
		return [float(t2.x), float(t2.y)]
	var p := st.player
	var a := float(i) * PI + st.t * 1.6
	return [float(p.x) + cos(a) * float(s.idleOrbit), float(p.y) + sin(a) * float(s.idleOrbit)]

## 규칙 3)의 다음 대상: 플레이어 사거리 안·가림 없는 가장 가까운 적(except_id 제외). 없으면 {}
static func _crow_pick(st: CombatState, s: Dictionary, except_id: int) -> Variant:
	var p := st.player
	var best = null
	var bd := INF
	for e in st.alive_targets():
		if int(e.id) == except_id or bool(e.get("structure", false)):
			continue
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d > float(s.range) + float(e.r) or d >= bd:
			continue
		if not PWeapons.reachable(st, p.x, p.y, e):
			continue
		bd = d
		best = e
	return best

static func _crow_retarget(st: CombatState, S: Dictionary, s: Dictionary, lost_id: int) -> void:
	var nx = _crow_pick(st, s, lost_id)
	S.target = nx
	S.hold = float(s.hold) if nx != null else 0.0
	if nx != null:
		S.retargets = int(S.retargets) + 1
	_crow_reset_hunt(S, 0)

static func _crow_reset_hunt(S: Dictionary, idx: int) -> void:
	var birds: Array = S.birds
	if idx >= 0 and idx < birds.size():
		(birds[idx] as Dictionary).hunt = 0

## 주기마다의 쪼기. 표적 위에 도착한 까마귀만 실제로 쫀다(날아가는 동안은 빗나간 것과 같다)
static func _crow_fire(st: CombatState, w: Dictionary) -> void:
	var S := _state(st, "crow")
	var s: Dictionary = w.stats
	var birds: Array = S.birds
	var twin := PSupport.has_mod(st, "crow", "twin")
	var hunt := PSupport.has_mod(st, "crow", "hunt")
	var swap := PSupport.has_mod(st, "crow", "switch")
	for i in birds.size():
		var b: Dictionary = birds[i]
		var tgt = S.target if i == 0 else S.alt
		if tgt == null:
			continue
		var e: Dictionary = tgt
		if bool(e.dead):
			continue
		if PGeom.dist(float(b.x), float(b.y), float(e.x), float(e.y)) > float(s.contact) + float(e.r):
			continue
		var mult := 1.0
		var mid := ""
		if twin:
			mult *= float(s.twinMult)
			if i > 0:
				mid = "twin"
				st.note_mod("twin", "proc")
		if hunt:
			var stage: int = mini(int(b.hunt), int(s.huntMax))
			if stage > 0:
				mult *= 1.0 + float(s.huntStep) * float(stage)
				if mid == "":
					mid = "hunt"
					st.note_mod("hunt", "proc")
			b.hunt = mini(int(b.hunt) + 1, int(s.huntMax))
		if swap and i == 0 and float(S.next_bonus) > 0.0:
			mult *= float(S.next_bonus)
			S.next_bonus = 0.0
			S.switch_procs = int(S.switch_procs) + 1
			mid = "switch"
			st.note_mod("switch", "proc")
		var opt := { "cause": "support_direct", "dir": PGeom.norm(float(e.x) - float(b.x), float(e.y) - float(b.y)),
			"knock": 0.0, "from": { "x": float(b.x), "y": float(b.y) } }
		if mid != "":
			opt["mod"] = mid
		st.metrics.cause_fires["crow"] = int(st.metrics.cause_fires.get("crow", 0)) + 1
		var dealt := PWeapons.dmg_to(st, e, w, mult, opt)
		S.strikes = int(S.strikes) + 1
		S.damage = float(S.damage) + dealt

# ---------- 4. ⑦ 수호 방울 ----------
## 무엇이 차단 가능한가는 data/supports.json bell.base.incoming이 정본이다.
## 목록에 없는 공격은 **차단하지 않는다**(안전 기본값). 자격표와 반대 방향인 이유는
## 모르는 공격을 조용히 막아 주면 "왜 안 죽었는지"를 못 찾기 때문이다.
static func incoming_cause(w: Dictionary, src: String) -> String:
	var inc: Dictionary = (w.stats as Dictionary).get("incoming", {})
	if (inc.get("projectile", []) as Array).has(src):
		return "enemy_projectile"
	if (inc.get("zone", []) as Array).has(src):
		return "enemy_zone"
	return "enemy_melee"

static func blockable(w: Dictionary, src: String) -> bool:
	var inc: Dictionary = (w.stats as Dictionary).get("incoming", {})
	return (inc.get("blockable", []) as Array).has(src)

static func bell_max(st: CombatState, w: Dictionary) -> int:
	var s: Dictionary = w.stats
	var n := int(s.charges)
	if PSupport.has_mod(st, "bell", "layered"):
		n += int(s.layeredCharges)
	return maxi(1, n)

static func bell_recharge(st: CombatState, w: Dictionary) -> float:
	var s: Dictionary = w.stats
	var r := float(s.recharge)
	if PSupport.has_mod(st, "bell", "layered"):
		r *= float(s.layeredRecharge)
	return maxf(0.05, r)

static func _bell_init(st: CombatState, S: Dictionary, w: Dictionary) -> void:
	var cap := bell_max(st, w)
	if int(S.charges) < 0:
		S.charges = cap
		S.rt = bell_recharge(st, w)
	elif int(S.charges) > cap: # 개조가 빠지거나 레벨이 내려가면 상한까지만 남긴다
		S.charges = cap

static func _bell_update(st: CombatState, dt: float) -> void:
	var w := _wep(st, "bell")
	if w.is_empty():
		_purge(st, "bell")
		return
	var S := _state(st, "bell")
	_bell_init(st, S, w)
	var cap := bell_max(st, w)
	if int(S.charges) < cap:
		S.rt = float(S.rt) - dt
		if float(S.rt) <= 0.0:
			S.charges = int(S.charges) + 1
			S.rt = bell_recharge(st, w)
			st.ev("bell_ready")
	else:
		S.rt = bell_recharge(st, w)
	# 표시용 표식: 지금 날아오는 적 투사체가 막을 수 있는 것인지, 지금 막을 방울이 남았는지.
	# 규칙에는 쓰지 않는다(화면·봇이 읽는다). 화면이 이 값을 읽어 다르게 그리는 일은 render.gd 몫이다 — docs/SUPPORT_A.md '필요한 훅'.
	for pr in st.projectiles:
		if String(pr.get("owner", "")) == "enemy":
			var can := blockable(w, String(pr.kind))
			pr["bell_blockable"] = can
			pr["bell_guard"] = can and int(S.charges) > 0

## 플레이어가 맞기 직전. 차단이 경감보다 먼저이고, 0을 돌려주면 완전히 막힌 것이다
static func on_player_damage(st: CombatState, amount: float, src: String, attacker) -> float:
	if amount <= 0.0:
		return amount
	var w := _wep(st, "bell")
	if w.is_empty():
		return amount
	var S := _state(st, "bell")
	_bell_init(st, S, w)
	var s: Dictionary = w.stats
	var kind := incoming_cause(w, src)
	var p := st.player
	# ① 차단(투사체). 방울 하나를 소모하고 피해를 전부 없앤다
	if kind == "enemy_projectile" and blockable(w, src) and int(S.charges) > 0:
		S.charges = int(S.charges) - 1
		S.blocked = int(S.blocked) + 1
		S.blocked_damage = float(S.blocked_damage) + amount
		st.fx({ "kind": "bell_block", "x": p.x, "y": p.y, "r": 34.0, "ttl": 0.3 })
		st.text(p.x, p.y - 46.0, "방울 차단!", "#9fd8ff")
		st.ev("bell_block")
		if PSupport.has_mod(st, "bell", "reflect"):
			_bell_reflect(st, w, S, attacker)
		return 0.0
	# ② 근접 수호(개조). 투사체 차단과 **같은 충전**을 쓴다. 큰 타격 한 번에 대비하는 방식이라
	#    가시 갑각(반복적 근접 대응)과 달리 방울이 없으면 아무 일도 하지 않는다
	if kind == "enemy_melee" and PSupport.has_mod(st, "bell", "guard") and int(S.charges) > 0:
		S.charges = int(S.charges) - 1
		S.guarded = int(S.guarded) + 1
		var cut := amount * float(s.guardCut)
		S.reduced = float(S.reduced) + cut
		st.note_mod("guard", "proc")
		st.fx({ "kind": "bell_guard", "x": p.x, "y": p.y, "r": 30.0, "ttl": 0.3 })
		st.text(p.x, p.y - 46.0, "근접 수호", "#9fd8ff")
		st.ev("bell_guard")
		return maxf(0.0, amount - cut)
	return amount

## 되돌림: 막은 투사체를 **복사하지 않는다**. 방울의 자기 피해(data bell.base.damage, 시험값)로 반격탄을 쏜다
static func _bell_reflect(st: CombatState, w: Dictionary, S: Dictionary, attacker) -> void:
	if attacker == null:
		return
	var e: Dictionary = attacker
	if bool(e.get("dead", true)):
		return
	var s: Dictionary = w.stats
	var p := st.player
	var d := PGeom.dist(p.x, p.y, float(e.x), float(e.y))
	if d > float(s.reflectRange):
		return
	var a := atan2(float(e.y) - p.y, float(e.x) - p.x)
	var sp := float(s.reflectSpeed)
	st.note_mod("reflect", "proc")
	PWeapons.proj(st, w, { "kind": "bellshot", "x": p.x, "y": p.y, "vx": cos(a) * sp, "vy": sin(a) * sp,
		"r": float(s.reflectR), "ttl": float(s.reflectRange) / sp, "dmg_mult": 1.0,
		"target": e, "turn": 3.0, "speed": sp, "angle": a, "mod": "reflect",
		"opt": { "direct": false, "cause": "support_direct", "mod": "reflect", "knock": 0.0 } })
	S.reflects = int(S.reflects) + 1

# ---------- 5. ⑧ 잔영 분신 ----------
## 생성 규칙(확정, 전부 data/supports.json echo.base):
##  - 기본형: 공격 방향의 **반대쪽** offset 자리에 선다. 움직이지 않고 ttl 뒤 사라진다. 1회 타격.
##  - 교차 잔영(cross): 공격 방향에 **수직**으로 crossOffset 자리에 선다. 좌·우를 번갈아 쓴다. 1회 타격.
##  - 잔류 잔영(residual): 플레이어가 residualBack초 전에 있던 자리에 남는다. residualTtl 동안 residualInterval마다 최대 residualHits번.
##  - 추격 잔영(chase): 플레이어 자리에서 생겨 대상을 chaseSpeed로 따라간다. 플레이어에게서 chaseLeash 밖으로는 못 나가고,
##    chaseTtl 동안 chaseInterval마다 최대 chaseHits번. 대상이 죽으면 그 자리에서 사라진다.
##  - 어느 형태든 **분신이 선 자리**에서 대상을 다시 고르고(주무기 사거리·가림을 분신 기준으로 판정) 그 자리에서 공격 모양을 만든다.
##  - 동시 분신은 maxClones까지. 넘으면 가장 오래된 것부터 지운다(옛 개체가 쌓여 무료 중복 효과가 되지 않게).
static func _echo_update(st: CombatState, dt: float) -> void:
	var w := _wep(st, "echo")
	if w.is_empty():
		_purge(st, "echo")
		return
	var S := _state(st, "echo")
	var s: Dictionary = w.stats
	var p := st.player
	# 지나온 자리 기록(잔류 잔영이 읽는다). trailSec보다 오래된 것은 버린다
	var trail: Array = S.trail
	trail.append({ "t": st.t, "x": float(p.x), "y": float(p.y) })
	while trail.size() > 0 and st.t - float((trail[0] as Dictionary).t) > float(s.trailSec):
		trail.pop_front()
	var clones: Array = S.clones
	var keep := []
	for c in clones:
		var cd: Dictionary = c
		cd.t = float(cd.t) + dt
		if float(cd.t) < float(cd.delay):
			keep.append(cd)
			continue
		if String(cd.form) == "chase":
			if not _echo_chase_move(st, cd, s, dt):
				continue # 대상이 사라졌다 → 이 분신도 사라진다
		if float(cd.t) >= float(cd.next):
			cd.next = float(cd.t) + float(cd.interval)
			if _echo_strike(st, S, cd, w):
				cd.hits = int(cd.hits) + 1
		if int(cd.hits) < int(cd.max_hits) and float(cd.t) < float(cd.delay) + float(cd.ttl):
			keep.append(cd)
	S.clones = keep

## 추격 잔영 이동. 대상이 살아 있으면 true
static func _echo_chase_move(st: CombatState, c: Dictionary, s: Dictionary, dt: float) -> bool:
	var tgt = c.target
	if tgt == null or bool((tgt as Dictionary).dead):
		return false
	var e: Dictionary = tgt
	var d := PGeom.dist(float(c.x), float(c.y), float(e.x), float(e.y))
	var stp := float(s.chaseSpeed) * dt
	if d > float(s.chaseContact) and d > 1e-6:
		var k := minf(1.0, stp / d)
		c.x = float(c.x) + (float(e.x) - float(c.x)) * k
		c.y = float(c.y) + (float(e.y) - float(c.y)) * k
	# 활동 범위: 플레이어에게서 chaseLeash 밖으로는 못 나간다
	var p := st.player
	var dl := PGeom.dist(p.x, p.y, float(c.x), float(c.y))
	var leash := float(s.chaseLeash)
	if dl > leash and dl > 1e-6:
		c.x = p.x + (float(c.x) - p.x) / dl * leash
		c.y = p.y + (float(c.y) - p.y) / dl * leash
	return true

## 주무기의 기본 공격 한 번을 분신 자리에서 다시 만든다. 실제로 대상이 있었으면 true
static func _echo_strike(st: CombatState, S: Dictionary, c: Dictionary, w: Dictionary) -> bool:
	var mw := _wep(st, String(c.weapon))
	if mw.is_empty():
		return false
	var ms: Dictionary = mw.stats
	var cx := float(c.x)
	var cy := float(c.y)
	var rr := float(ms.range)
	# 분신 자리에서 대상을 다시 고른다(본체 자리에서 겹쳐 일어난 것처럼 보이면 안 된다)
	var tgt = c.target if String(c.form) == "chase" else null
	if tgt == null:
		tgt = _echo_pick(st, cx, cy, rr)
	elif bool((tgt as Dictionary).dead) or PGeom.dist(cx, cy, float((tgt as Dictionary).x), float((tgt as Dictionary).y)) > rr + float((tgt as Dictionary).r):
		tgt = null
	if tgt == null:
		S.fizzles = int(S.fizzles) + 1
		return false
	var e: Dictionary = tgt
	var ang := atan2(float(e.y) - cy, float(e.x) - cx)
	var share := float(c.share)
	var opt := { "cause": "echo_direct", "direct": true, "src_extra": { "echo": true }, "knock": 0.0 }
	if String(c.mod_id) != "":
		opt["mod"] = String(c.mod_id)
	var before := float(st.metrics.cause_dmg.get("echo_direct", 0.0))
	S.busy = true # 분신의 타격이 다시 분신을 만들지 않게(경로 이름 echo_direct로도 막히지만 이중으로 잠근다)
	st.metrics.cause_fires["echo_direct"] = int(st.metrics.cause_fires.get("echo_direct", 0)) + 1
	st.fx({ "kind": "echo_clone", "x": cx, "y": cy, "angle": ang, "ttl": 0.22, "mod": String(c.mod_id) })
	match String(ms.kind):
		"arc":
			PWeapons.hit_arc(st, mw, cx, cy, ang, rr, float(ms.arc_deg) * PI / 360.0, share, opt)
		"melee":
			var hits: int = maxi(1, int(ms.get("hits", 1)))
			for i in hits:
				PWeapons.hit_arc(st, mw, cx, cy, ang, rr, float(ms.arc_deg) * PI / 360.0, share, opt)
		"beam":
			PWeapons.hit_beam(st, mw, cx, cy, ang, st.beam_length(cx, cy, ang, rr), float(ms.width), share, opt)
		"heavy":
			var d2 := PGeom.dist(cx, cy, float(e.x), float(e.y))
			var ix := cx + cos(ang) * minf(d2, rr)
			var iy := cy + sin(ang) * minf(d2, rr)
			PWeapons.hit_circle(st, mw, ix, iy, float(ms.radius), share, opt)
		"homing":
			var po := opt.duplicate()
			PWeapons.proj(st, mw, { "kind": "arrow_h", "x": cx, "y": cy, "vx": cos(ang) * float(ms.speed), "vy": sin(ang) * float(ms.speed),
				"r": 5.0, "ttl": (rr / float(ms.speed)) * 1.4, "target": e, "turn": float(ms.turn), "speed": float(ms.speed), "angle": ang,
				"dmg_mult": share, "opt": po })
		_:
			PWeapons.dmg_to(st, e, mw, share, opt)
	S.busy = false
	S.strikes = int(S.strikes) + 1
	S.damage = float(S.damage) + (float(st.metrics.cause_dmg.get("echo_direct", 0.0)) - before)
	return true

## 분신 자리에서 사거리 안·가림 없는 가장 가까운 적
static func _echo_pick(st: CombatState, cx: float, cy: float, rr: float) -> Variant:
	var best = null
	var bd := INF
	for e in st.alive_targets():
		var d := PGeom.dist(cx, cy, e.x, e.y)
		if d > rr + float(e.r) or d >= bd:
			continue
		if not PWeapons.reachable(st, cx, cy, e):
			continue
		bd = d
		best = e
	return best

## 주무기의 기본 공격 뒤 분신을 만든다. 한 번의 공격에 한 개만 만든다(같은 공격의 여러 적중이 분신을 여러 개 만들지 않게)
static func _echo_on_main_hit(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	var w := _wep(st, "echo")
	if w.is_empty():
		return
	var S := _state(st, "echo")
	if bool(S.busy):
		return
	if not PSupport.eligible("echo_copy", _cause(st, opt)):
		return
	var sr: Dictionary = opt.get("src", {})
	var wid := String(sr.get("weapon_id", ""))
	if wid == "" or not PCatalog.is_main_weapon(wid):
		return
	var mw := _wep(st, wid)
	if mw.is_empty():
		return
	var seen: Dictionary = S.last_count
	if int(seen.get(wid, -1)) == int(mw.count):
		return
	seen[wid] = int(mw.count)
	_echo_spawn(st, S, w, wid, e)

static func _echo_spawn(st: CombatState, S: Dictionary, w: Dictionary, wid: String, e: Dictionary) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	var ang := atan2(float(e.y) - p.y, float(e.x) - p.x)
	var form := ""
	var mid := ""
	for m in ["cross", "residual", "chase"]:
		if PSupport.has_mod(st, "echo", String(m)):
			form = String(m)
			mid = String(m)
			break
	var cx: float = p.x
	var cy: float = p.y
	var ttl := float(s.ttl)
	var itv := 999.0
	var max_hits := 1
	var share := float(s.share)
	var tgt = null
	match form:
		"cross":
			var side := 1.0 if int(S.spawned) % 2 == 0 else -1.0
			cx = p.x + cos(ang + PI / 2.0) * float(s.crossOffset) * side
			cy = p.y + sin(ang + PI / 2.0) * float(s.crossOffset) * side
		"residual":
			var back := _echo_trail_pos(S, st.t - float(s.residualBack), p)
			cx = float(back[0])
			cy = float(back[1])
			ttl = float(s.residualTtl)
			itv = float(s.residualInterval)
			max_hits = int(s.residualHits)
			share *= float(s.residualShare)
		"chase":
			ttl = float(s.chaseTtl)
			itv = float(s.chaseInterval)
			max_hits = int(s.chaseHits)
			share *= float(s.chaseShare)
			tgt = e
		_:
			cx = p.x - cos(ang) * float(s.offset)
			cy = p.y - sin(ang) * float(s.offset)
	# 분신은 걸어 다니는 개체가 아니지만 바위·벽 안에 서면 판정이 이상해진다. 가까운 유효 지점으로 옮긴다
	var pos := st.nearest_valid_pos(cx, cy, 0.0, 90.0)
	if not pos.is_empty():
		cx = float(pos[0])
		cy = float(pos[1])
	var clones: Array = S.clones
	while clones.size() >= maxi(1, int(s.maxClones)):
		clones.pop_front()
	clones.append({ "x": cx, "y": cy, "t": 0.0, "delay": float(s.delay), "ttl": ttl, "interval": itv,
		"next": float(s.delay), "hits": 0, "max_hits": max_hits, "share": share,
		"form": form, "mod_id": mid, "weapon": wid, "target": tgt })
	S.spawned = int(S.spawned) + 1
	if mid != "":
		st.note_mod(mid, "proc")

## 지나온 자리에서 want 시각에 가장 가까운 기록. 기록이 없으면 지금 자리
static func _echo_trail_pos(S: Dictionary, want: float, p: Dictionary) -> Array:
	var trail: Array = S.trail
	var best := [float(p.x), float(p.y)]
	var bd := INF
	for r in trail:
		var rd: Dictionary = r
		var d := absf(float(rd.t) - want)
		if d < bd:
			bd = d
			best = [float(rd.x), float(rd.y)]
	return best

# ---------- 6. ⑨ 바람 정령 ----------
## 밀어내기는 반드시 PSupport.knock_dist(거리, 적)를 거친다 — 정예는 저항, 보스는 0이다.
## 실제 이동은 st.move_swept이라 벽·바위 안으로 들어가지 않는다(닿으면 그 자리에서 멈춘다).
## 쌍검처럼 붙어서 싸우는 주무기에는 적을 떼어 놓는 불편이 그대로 남는다 — 보정하지 않는다.
static func _wind_arc(s: Dictionary, want_deg: float) -> float:
	# 개조가 쓰는 절대 각도에도 공용 폭 증강 비율을 그대로 물려준다
	var b: Dictionary = (s.def as Dictionary).base
	var base_arc := float(b.get("arcDeg", 0.0))
	if base_arc <= 0.0:
		return want_deg
	return want_deg * (float(s.arcDeg) / base_arc)

static func _wind_fire(st: CombatState, w: Dictionary) -> void:
	var s: Dictionary = w.stats
	var p := st.player
	# 발동 조건: trigger 안에 적이 있어야 돌풍이 분다. 아니면 주기를 소모하지 않고 곧 다시 본다
	var near := {}
	var nd := INF
	for e in st.alive_targets():
		if bool(e.get("structure", false)):
			continue
		var d := PGeom.dist(p.x, p.y, e.x, e.y)
		if d <= float(s.trigger) + float(e.r) and d < nd:
			nd = d
			near = e
	if near.is_empty():
		return # 발동 거리(trigger) 안에 적이 없으면 이번 주기는 불지 않는다 — 빗나간 발사와 같다
	var S := _state(st, "wind")
	var arc := float(s.arcDeg)
	var kmul := 1.0
	var mid := ""
	if PSupport.has_mod(st, "wind", "broad"):
		arc = _wind_arc(s, float(s.broadArc))
		kmul = float(s.broadKnock)
		mid = "broad"
	elif PSupport.has_mod(st, "wind", "focused"):
		arc = _wind_arc(s, float(s.focusedArc))
		kmul = float(s.focusedKnock)
		mid = "focused"
	var ang := atan2(float(near.y) - p.y, float(near.x) - p.x)
	var half := arc * PI / 360.0
	var rr := float(s.range)
	var linger := PSupport.has_mod(st, "wind", "lingering")
	S.blasts = int(S.blasts) + 1
	st.metrics.cause_fires["wind"] = int(st.metrics.cause_fires.get("wind", 0)) + 1
	st.fx({ "kind": "wind_gust", "x": p.x, "y": p.y, "angle": ang, "r": rr, "half": half, "ttl": 0.2, "mod": mid })
	if mid != "":
		st.note_mod(mid, "proc")
	# 잔바람은 **돌풍이 지나간 자리**에 남는다(2026-09-09 BP-1, 사용자 승인).
	# 예전에는 '밀어낸 경로'에만 남겨서, 밀어내기 저항이 0인 보스에게는 한 조각도 안 생겼다.
	# 이제는 적이 밀리든 아니든 **부채꼴의 축**(플레이어 → 조준 방향 × range) 위에 놓는다.
	# 축을 고른 이유: 조각 수가 **적 수와 무관**하게 한 번의 돌풍당 gustPerBlast로 고정된다.
	# 맞은 적의 자리마다 놓으면 밀집 전투에서 조각이 적 수만큼 늘어(상한 gustMax에 더 자주 닿아)
	# 보스전을 고치려던 변경이 무리전 강화로 새어 나간다 — 사거리·조각 수를 보상 삼아 늘리지 않는다.
	if linger:
		_wind_trail(st, S, s, p.x, p.y, p.x + cos(ang) * rr, p.y + sin(ang) * rr)
	# 부채꼴 판정은 공용 기하를 그대로 쓰되 피해와 밀어내기를 **따로** 준다.
	# PWeapons.hit_arc은 무기의 knock을 속도 넉백으로 넣어 버려서 등급 저항을 건너뛰기 때문이다
	var targets := []
	for e in st.alive_targets():
		if PGeom.in_arc(p.x, p.y, rr, ang, half, e.x, e.y, e.r) and PWeapons.reachable(st, p.x, p.y, e):
			targets.append(e)
	for t in targets:
		var e2: Dictionary = t
		var opt := { "cause": "support_direct", "dir": PGeom.norm(float(e2.x) - p.x, float(e2.y) - p.y),
			"knock": 0.0, "from": { "x": p.x, "y": p.y } }
		if mid != "":
			opt["mod"] = mid
		PWeapons.dmg_to(st, e2, w, 1.0, opt)
		if bool(e2.dead) or _immovable(e2):
			continue
		var want := PSupport.knock_dist(float(s.knock) * kmul, e2)
		if want <= 0.0:
			continue # 보스는 0이라 위치가 강제로 바뀌지 않는다
		var n := PGeom.norm(float(e2.x) - p.x, float(e2.y) - p.y)
		if absf(float(n[0])) + absf(float(n[1])) < 1e-9:
			continue
		var x0 := float(e2.x)
		var y0 := float(e2.y)
		st.move_swept(e2, float(n[0]) * want, float(n[1]) * want)
		var moved := PGeom.dist(x0, y0, float(e2.x), float(e2.y))
		if moved <= 0.0:
			continue
		S.pushed = int(S.pushed) + 1
		S.push_total = float(S.push_total) + moved
		S.push_max = maxf(float(S.push_max), moved)
	st.ev("shoot")

## 돌풍이 지나간 자리(부채꼴의 축)에 잔바람을 남긴다.
## 놓는 곳: (x0,y0)에서 (x1,y1)까지를 n등분한 점들 — 지금 호출자는 플레이어 자리 → 조준 방향으로 range만큼.
## 간격: seg/n. n = clamp(seg/gustStep + 1, 1, gustPerBlast)이므로 실제 간격은 언제나 gustStep 이하다.
## 최대 수: 한 번의 돌풍당 gustPerBlast개, 전장 전체로 gustMax개(넘으면 오래된 것부터 지운다).
static func _wind_trail(st: CombatState, S: Dictionary, s: Dictionary, x0: float, y0: float, x1: float, y1: float) -> void:
	var seg := PGeom.dist(x0, y0, x1, y1)
	var n := clampi(int(seg / maxf(1.0, float(s.gustStep))) + 1, 1, maxi(1, int(s.gustPerBlast)))
	for i in n:
		var f := float(i + 1) / float(n)
		var z := st.add_zone("windgust", x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, float(s.gustR), float(s.gustTtl), 0.0)
		z["slow"] = float(s.gustSlow)
		z["weapon_id"] = "wind"
		S.gusts = int(S.gusts) + 1
	_wind_cap_gusts(st, maxi(1, int(s.gustMax)))

static func _wind_cap_gusts(st: CombatState, cap: int) -> void:
	var idx := []
	for i in st.zones.size():
		if String((st.zones[i] as Dictionary).type) == "windgust":
			idx.append(i)
	var over := idx.size() - cap
	var drop := {}
	for i in over:
		drop[idx[i]] = true
	if drop.is_empty():
		return
	var keep := []
	for i in st.zones.size():
		if not drop.has(i):
			keep.append(st.zones[i])
	st.zones = keep

## 잔바람 둔화. **한 적에게는 겹친 조각 중 가장 센 것 하나만 적용한다**(2026-09-09 BP-1).
## 조각을 돌풍의 축에 놓으면서 연달아 분 돌풍이 같은 줄에 겹쳐 쌓이게 됐다 —
## 겹친 수만큼 곱해 겹치면 서 있기만 해도 곧바로 바닥(slow_floor)에 닿아, 조각이 겹쳤다는 이유만으로
## 둔화가 무제한 중첩된다. 그래서 겹침은 세지 않고 가장 센 조각 하나를 PSupport.stack_slow에 통과시킨다
## (등급 저항과 최저 이동 속도 바닥은 그 함수가 그대로 적용한다).
## 겹쳐도 PSupport.slow_floor 아래로 내려가지 않는다.
## 이동 속도 배율을 읽는 공용 훅이 없어(enemy_speed_mult는 냉기·감속장만 본다)
## **직전 프레임에 실제로 움직인 거리**의 (1 - 배율)만큼을 되돌리는 방식으로 늦춘다.
## st.move_swept로 되돌리므로 벽·바위를 뚫지 않고, 서 있는 적은 아무 영향이 없다.
static func _wind_update(st: CombatState, dt: float) -> void:
	var w := _wep(st, "wind")
	if w.is_empty():
		_purge(st, "wind")
		return
	if not PSupport.has_mod(st, "wind", "lingering"):
		return
	var S := _state(st, "wind")
	var gusts := []
	for z in st.zones:
		if String((z as Dictionary).type) == "windgust":
			gusts.append(z)
	if gusts.is_empty() or dt <= 0.0:
		return
	for e in st.alive_targets():
		if bool(e.get("structure", false)) or bool(e.get("airborne", false)):
			continue
		var top := 0.0 # 겹친 조각 중 가장 센 둔화 비율 하나만 고른다(조각 수를 세지 않는다)
		for g in gusts:
			var z2: Dictionary = g
			if PGeom.dist(float(z2.x), float(z2.y), e.x, e.y) <= float(z2.r) + float(e.r):
				top = maxf(top, float(z2.get("slow", 0.0)))
		var mult := 1.0
		if top > 0.0:
			mult = PSupport.stack_slow(1.0, top, e)
		if mult >= 0.999:
			e["wind_slow_on"] = false
			continue
		# **두 가지를 따로 센다.** 예전에는 `slowed`가 '둔화 중인 적 × 프레임'이라
		# 서리 수정의 `slows`('새로 둔화가 걸린 횟수')와 같은 이름표를 쓰면서 뜻이 달랐다
		# (같은 전투에서 바람 2261.5 · 서리 13.5 — 단위가 달라 세 자릿수 차이가 났다).
		# 이제 `slowed`는 **새로 둔화된 적의 수**, `slow_sec`는 **둔화 적·초**다. 2026-09-09 대표 조합 검수 BP-2.
		S.slow_sec = float(S.slow_sec) + dt
		if not bool(e.get("wind_slow_on", false)):
			e["wind_slow_on"] = true
			S.slowed = int(S.slowed) + 1
		S.slow_min = minf(float(S.slow_min), mult)
		var dx := float(e.x) - float(e.get("last_x", e.x))
		var dy := float(e.y) - float(e.get("last_y", e.y))
		if absf(dx) + absf(dy) > 1e-6:
			st.move_swept(e, -dx * (1.0 - mult), -dy * (1.0 - mult))

# ---------- 7. 전투 훅 ----------
static func after_player_damage(_st: CombatState, _amount: float, _src: String, _attacker) -> void:
	pass # A조에는 되받아치기가 없다(가시 갑각은 B조)

static func on_enemy_hit(st: CombatState, e: Dictionary, opt: Dictionary, _dmg: float) -> void:
	_crow_on_hit(st, e, opt)
	_echo_on_main_hit(st, e, opt)

## 까마귀 표적 지정. 자격은 자격표 한 곳(crow_mark)이 정한다
static func _crow_on_hit(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	var w := _wep(st, "crow")
	if w.is_empty():
		return
	if not PSupport.eligible("crow_mark", _cause(st, opt)):
		return
	var S := _state(st, "crow")
	var s: Dictionary = w.stats
	if S.target != null and int((S.target as Dictionary).id) == int(e.id):
		S.hold = float(s.hold) # 같은 적을 계속 때리면 유지 시간만 다시 채운다
		return
	if float(S.hold) > 0.0 and S.target != null and not bool((S.target as Dictionary).dead):
		return # 유지 시간 동안에는 본체가 다른 적을 때려도 표적이 흔들리지 않는다
	S.target = e
	S.hold = float(s.hold)
	S.marks = int(S.marks) + 1
	_crow_reset_hunt(S, 0)

static func on_enemy_death(st: CombatState, e: Dictionary, _opt: Dictionary) -> void:
	var S := _peek(st, "crow")
	if not S.is_empty():
		if S.target != null and int((S.target as Dictionary).id) == int(e.id):
			var w := _wep(st, "crow")
			if not w.is_empty() and PSupport.has_mod(st, "crow", "switch"):
				S.next_bonus = float(w.stats.switchMult) # 먹잇감 전환: 다음 표적 첫 공격이 강해진다
			S.hold = 0.0
			_crow_reset_hunt(S, 0)
			# 표적을 여기서 비우지 않는다. 죽은 표적을 그대로 두면 다음 갱신이 규칙 3)의
			# 자동 재지정(사거리 안·가림 없는 가장 가까운 적)을 그대로 태운다 — 규칙이 한 곳에만 있게 한다
		if S.alt != null and int((S.alt as Dictionary).id) == int(e.id):
			S.alt = null
	var E := _peek(st, "echo")
	if not E.is_empty():
		# 추격 잔영은 대상이 죽으면 사라진다. 여기서는 표시만 지우고 실제 제거는 다음 갱신이 한다
		# (지금 이 함수는 분신의 타격 도중에도 불릴 수 있어 clones 배열을 갈아 끼우면 갱신 순회와 어긋난다)
		for c in E.clones:
			var cd: Dictionary = c
			var tgt = cd.target
			if tgt != null and int((tgt as Dictionary).id) == int(e.id):
				cd.target = null
