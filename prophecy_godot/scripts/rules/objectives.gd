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

# ---------- 임무 개편 조정값(2026-09-08, 전부 시험값 — 사람이 승인한 균형값이 아니다) ----------
## 원래 이 표는 data/missions.json에 있어야 하지만 그 파일은 이번 작업의 담당 밖이라 여기에 둔다(보고에 기록).
## PROPHECY_OBJ=off 로 실행하면 개편 전 규칙 그대로 돌아간다(전후 비교 전용 스위치).
## base_from_encounter: 임무도 일반 전투와 같은 날짜 예산 편성(PRun.encounter_waves)·동시 상한을 쓴다.
##   개편 전에는 목표 규칙이 편성을 통째로 덮어써 "지역 적 2마리 × 밀도 배율 = 10마리"만 나왔다(원인 ①).
## reinforce.floor: 전장에 움직이는 적이 이 수보다 적으면 간격을 기다리지 않고 부족분을 채운다(빈 전장 방지).
## reinforce.gate_base: 목표 진행 없이 열리는 예산 비율(나머지는 진행률로 열린다 — 무한 파밍 방지).
## cap 0 = 편성의 동시 생존 상한(막별 12/15/18)을 그대로 쓴다.
const TUNE := {
	"base_from_encounter": true,
	"reinforce": {
		"seal": { "budget": 12, "interval": 3.0, "first": 1.2, "cap": 0, "floor": 4, "gate_base": 0.4, "floor_gap": 1.5 },
		"rescue": { "budget": 12, "interval": 3.5, "first": 1.5, "cap": 0, "floor": 4, "gate_base": 0.4, "floor_gap": 1.5 },
		"altars": { "budget": 8, "interval": 5.0, "cap": 0, "floor": 3, "gate_base": 0.5, "floor_gap": 2.0 },
		"hunt": { "cap": 0, "floor": 3, "gate_base": 1.0, "floor_gap": 2.0 },
	},
	"altar": {
		"hp_by_act": [220.0, 300.0, 380.0], # 제단 체력(막별). 개편 전 90은 첫 접근 한 번에 부서졌다(원인 ②)
		"hp_per_weapon_level": 0.06,        # 빌드가 강해진 만큼 올린다(레벨-1 + 대장간 단계 합 1당 +6%)
		"first_show": 1.2,                  # 첫 효과 발동까지(초): 무엇을 하는 제단인지 부수기 전에 보인다
		"guard_n": 2,                       # 제단마다 붙는 호위(첫 등장 편성에 포함, 제단 주변에서 시작)
		"guard_r": 90.0,
		"min_player_gap": 260.0,            # 시작 위치에서 바로 닿지 않게(개편 전 170)
	},
}

## "full"(기본) | "off"(개편 전 규칙). 환경 변수 PROPHECY_OBJ가 우선한다
static func variant() -> String:
	var v := OS.get_environment("PROPHECY_OBJ")
	return v if v != "" else "full"

static func on() -> bool:
	return variant() != "off"

static func tune(section: String, key: String, def: float) -> float:
	if not on():
		return def
	var s: Dictionary = TUNE.get(section, {})
	return float(s.get(key, def))

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
## cfg = data/missions.json의 목표별 reinforce. obj_id를 주면 개편 조정값(TUNE.reinforce)이 덮어쓴다.
## alive_cap = 편성의 동시 생존 상한(cap 0일 때 쓴다)
static func make_reinforce(cfg: Dictionary, pool: Array, obj_id: String = "", alive_cap: int = 0) -> Dictionary:
	if cfg.is_empty():
		return {}
	var R := { "budget": int(cfg.budget), "cap": int(cfg.cap), "interval": float(cfg.interval), "timer": float(cfg.first) if cfg.has("first") else float(cfg.interval), "pool": pool.duplicate(), "spawned": 0, "log": new_rlog() }
	R.budget_total = int(R.budget)
	if not on() or obj_id == "":
		return R
	var T: Dictionary = (TUNE.reinforce as Dictionary).get(obj_id, {})
	if T.is_empty():
		return R
	if T.has("budget"):
		R.budget = int(T.budget)
	if T.has("interval"):
		R.interval = float(T.interval)
	if T.has("first"):
		R.timer = float(T.first)
	if T.has("cap"):
		var c: int = int(T.cap)
		R.cap = c if c > 0 else maxi(int(cfg.cap), alive_cap)
	R.floor = int(T.get("floor", 0))
	R.floor_gap = float(T.get("floor_gap", 1.5))
	R.floor_cd = 0.0
	R.gate_base = float(T.get("gate_base", 1.0))
	R.budget_total = int(R.budget)
	return R

## 지원병 계측(원인 분리용, 규칙에 영향 없음): 왜 지원이 안 나왔는지 이유별로 센다.
## try = 간격이 차서 시도한 횟수 / cap_block·budget_block·gate_block = 막힌 이유 / spawned = 실제 예약 수 /
## floor_fire = 인구 하한 때문에 간격을 건너뛰고 채운 횟수 / empty_sec = 전장에 적이 하나도 없던 시간
static func new_rlog() -> Dictionary:
	return { "try": 0, "spawned": 0, "cap_block": 0, "budget_block": 0, "gate_block": 0, "floor_fire": 0, "first_t": -1.0, "last_t": -1.0, "empty_sec": 0.0, "thin_sec": 0.0 }

static func active_enemies(st: CombatState) -> int:
	return st.alive_units() + st.pending.size()

## 구조물(제단·봉인 장치)을 뺀 전장 인구. 인구 하한 판단은 "때릴 수 있는 움직이는 적"만 센다
static func field_units(st: CombatState) -> int:
	var n := 0
	for e in st.enemies:
		if not e.dead and not bool(e.get("structure", false)) and not bool(e.get("hidden", false)):
			n += 1
	return n + st.pending.size()

## 지원 예산 해금 비율(무한 파밍 금지): 목표를 진행할수록 열린다.
## 목표를 진행하지 않고 제자리에서 적만 잡는 동안에는 첫 몫(base)까지만 나온다 — 반복 보상이 무한해지지 않는다.
static func unlocked_budget(st: CombatState, R: Dictionary) -> int:
	var total: int = int(R.get("budget_total", R.budget))
	var base: float = float(R.get("gate_base", 1.0))
	if base >= 1.0:
		return total
	var ratio: float = clampf(progress_ratio(st), 0.0, 1.0)
	return int(ceil(float(total) * (base + (1.0 - base) * ratio)))

## 목표 진행률 0~1(지원 예산 해금·표시 공용). 목표별로 뜻이 다르다
static func progress_ratio(st: CombatState) -> float:
	var o := st.obj
	if o.is_empty():
		return 0.0
	if bool(o.get("done", false)):
		return 1.0
	match st.objective:
		"seal":
			return float(o.get("progress", 0.0)) / maxf(0.001, float(o.get("total", 1.0)))
		"rescue":
			var c := float(o.get("freed", 0)) / maxf(1.0, float(o.get("cages", 1)))
			var ac: Dictionary = o.get("active", {})
			if not ac.is_empty() and not bool(ac.get("freed", false)):
				c += (float(ac.progress) / maxf(0.001, float(ac.total))) / maxf(1.0, float(o.get("cages", 1)))
			return minf(1.0, c)
		"altars":
			var alive := 0
			for a in o.get("altars", []):
				if not a.dead:
					alive += 1
			return 1.0 - float(alive) / 3.0
		"hunt":
			var el: Dictionary = o.get("elite", {})
			if el.is_empty() or bool(el.get("dead", false)):
				return 1.0 if int(o.get("elite_killed", 0)) > 0 else 0.0
			return 1.0 - float(el.hp) / maxf(1.0, float(el.hp_max))
	return 0.0

## 지원병 예약. floor(인구 하한)에 미치지 못하면 간격을 기다리지 않고 부족분을 한 번에 채운다.
## 예산은 유한하고 목표 진행률로 열린다(멍하니 서 있게 두지 않되, 무한 파밍도 막는다).
static func reinforce(st: CombatState, R: Dictionary, dt: float, n: int = 0) -> int:
	if R.is_empty():
		return 0
	var L: Dictionary = R.get("log", {})
	if L.is_empty():
		L = new_rlog()
		R.log = L
	var units := field_units(st)
	R.timer = float(R.timer) - dt
	var floor_n: int = int(R.get("floor", 0))
	var deficit: int = maxi(0, floor_n - units)
	# 인구 하한은 "기본 편성이 더 내보낼 것이 없을 때"만 쓴다(기본 편성이 채우는 중이면 그쪽을 기다린다)
	var queue_done: bool = int(st.spawn_count) >= int(st.spawn_total)
	var forced: bool = deficit > 0 and queue_done and float(R.get("floor_cd", 0.0)) <= 0.0 and n <= 0
	R.floor_cd = maxf(0.0, float(R.get("floor_cd", 0.0)) - dt)
	if float(R.timer) > 0.0 and not forced:
		return 0
	if not forced:
		R.timer = float(R.interval)
	L.try = int(L.try) + 1
	if int(R.budget) <= 0:
		L.budget_block = int(L.budget_block) + 1
		if forced:
			R.floor_cd = float(R.get("floor_gap", 1.5))
		return 0
	if int(R.spawned) >= unlocked_budget(st, R):
		L.gate_block = int(L.gate_block) + 1
		if forced:
			R.floor_cd = float(R.get("floor_gap", 1.5))
		return 0
	var k := 0
	var want: int = n if n > 0 else maxi(1, deficit)
	var pool: Array = R.pool
	var cap: int = int(R.cap)
	while k < want and int(R.budget) > 0 and int(R.spawned) < unlocked_budget(st, R) and active_enemies(st) < cap:
		var type := String(pool[int(R.spawned) % pool.size()])
		st.queue_wave([{ "type": type, "n": 1 }])
		R.budget = int(R.budget) - 1
		R.spawned = int(R.spawned) + 1
		k += 1
	if k == 0 and active_enemies(st) >= cap:
		L.cap_block = int(L.cap_block) + 1
		if forced:
			R.floor_cd = float(R.get("floor_gap", 1.5))
	if k > 0:
		L.spawned = int(L.spawned) + k
		if float(L.first_t) < 0.0:
			L.first_t = st.t
		L.last_t = st.t
		if forced:
			L.floor_fire = int(L.floor_fire) + 1
			R.floor_cd = float(R.get("floor_gap", 1.5))
		st.ev("reinforce", { "n": k })
	return k

## 임무의 기본 편성. 개편에서는 일반 전투와 같은 날짜 예산 편성(opts.waves, PRun.encounter_waves)을 그대로 쓴다.
## 정예·보스·구조물은 목표 규칙이 따로 정하므로 여기서 뺀다(정예 수 규칙은 그대로 유지된다).
## opts.waves가 없으면(단위 시험·직접 생성) 개편 전처럼 지역 적 fallback_n마리만 낸다.
static func base_waves(opts: Dictionary, pool: Array, fallback_n: int) -> Array:
	var src: Array = opts.get("waves", [])
	if on() and bool(TUNE.base_from_encounter) and not src.is_empty():
		var out: Array = []
		for w in src:
			var g2: Array = []
			for g in w:
				var d := PCatalog.enemy(String(g.type))
				if bool(d.get("elite", false)) or bool(d.get("boss", false)) or bool(d.get("structure", false)):
					continue
				g2.append((g as Dictionary).duplicate())
			if not g2.is_empty():
				out.append(g2)
		if not out.is_empty():
			return out
	return [[{ "type": String(pool[0]), "n": fallback_n }]]

## 편성에서 앞쪽 n마리를 빼서 그 종류 목록을 돌려준다(제단 호위처럼 "다른 곳에서 시작하는" 적).
## 총 등장 수·경험치 예산은 그대로 두고 시작 위치만 바꾸는 방법이다.
static func take_units(f: Dictionary, n: int) -> Array:
	var units: Array = f.get("units", [])
	var tiers: Array = f.get("tiers", [])
	var out: Array = []
	var i := 0
	while out.size() < n and i < units.size():
		var d := PCatalog.enemy(String(units[i]))
		if bool(d.get("elite", false)) or bool(d.get("boss", false)) or bool(d.get("structure", false)):
			i += 1
			continue
		out.append([String(units[i]), String(tiers[i]) if i < tiers.size() else "normal"])
		units.remove_at(i)
		if i < tiers.size():
			tiers.remove_at(i)
	return out

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
	var altar_spots: Array = [] # 제단 호위 배치용(편성 확정 뒤에 세운다)
	if st.objective == "hunt":
		# 웨이브 1: 호위 + 정예. 정예는 처음부터 등장(숨지 않음)
		var escort_type := String(pool[0])
		waves = base_waves(opts, pool, int(S.escortN))
		(waves[waves.size() - 1] as Array).append({ "type": String(S.eliteType), "n": 1 })
		o.reinforce = make_reinforce(S.reinforce, pool, "hunt", int(st.formation.get("alive_cap", 0)))
		o.reinforce.timer = 0.0
		o.reinforce_fired = false
		o.elite = {}
		o.elite_total = 0
		o.elite_killed = 0
	elif st.objective == "altars":
		waves = base_waves(opts, pool, 2)
		var others: Array = []
		o.altars = []
		var gap_p: float = tune("altar", "min_player_gap", float(S.minPlayerGap))
		for kind in ["heal", "hazard", "reinforce"]:
			var p := place(st, 22.0, float(S.minGap), gap_p, others)
			others.append(p)
			var e := st.spawn_enemy("altar_" + String(kind), float(p.x), float(p.y))
			e.altar = String(kind)
			e.timer = float(S.heal.interval) if kind == "heal" else (2.5 if kind == "hazard" else float(S.reinforce.interval))
			if on(): # 첫 효과를 빨리 보여준다: 무슨 제단인지 알기 전에 부서지지 않게(원인 ②)
				e.timer = tune("altar", "first_show", 1.2) + float(others.size() - 1) * 0.5
			e.budget = float(S.heal.budget) if kind == "heal" else (float(S.reinforce.budget) if kind == "reinforce" else INF)
			altar_hp(st, e)
			(o.altars as Array).append(e)
			altar_spots.append(p)
		o.reinforce = make_reinforce(S.reinforce, pool, "altars", int(st.formation.get("alive_cap", 0)))
	elif st.objective == "seal":
		waves = base_waves(opts, pool, 2)
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
		o.reinforce = make_reinforce(S.reinforce, pool, "seal", int(st.formation.get("alive_cap", 0)))
	elif st.objective == "rescue":
		waves = base_waves(opts, pool, 2)
		var c1 := place(st, 26.0, float(S.minGap), 150.0, [])
		var c2 := place(st, 26.0, float(S.minGap), 150.0, [c1])
		var ex := edge_exit(st, [c1, c2, { "x": st.player.x, "y": st.player.y }])
		o.cages = int(S.cages)
		o.freed = 0
		o.active = {}
		st.objects.append({ "kind": "cage", "x": float(c1.x), "y": float(c1.y), "r": 26.0, "progress": 0.0, "total": float(S.time), "freed": false, "id": 1 })
		st.objects.append({ "kind": "cage", "x": float(c2.x), "y": float(c2.y), "r": 26.0, "progress": 0.0, "total": float(S.time), "freed": false, "id": 2 })
		st.objects.append({ "kind": "exit", "x": float(ex.x), "y": float(ex.y), "r": float(S.exitR), "open": false })
		o.reinforce = make_reinforce(S.reinforce, pool, "rescue", int(st.formation.get("alive_cap", 0)))
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
	# HTML 웨이브 → 밀도 편성(정예 호위 반영 뒤에 변환). 개편에서는 일반 전투와 같은 밀도 설정(막별 동시 상한·묶음·혼합 분대)을 쓴다
	var dens: Dictionary = opts.get("density", {}) if on() else {}
	var f := PFormation.from_waves(waves, dens, st.region_id, st)
	# 제단 호위: 편성에서 빼서 제단 옆에 세운다(총 등장 수·경험치 예산은 그대로, 시작 위치만 다르다)
	var guards: Array = []
	if st.objective == "altars" and on() and not altar_spots.is_empty():
		guards = take_units(f, int(TUNE.altar.guard_n) * altar_spots.size())
	st.set_formation(f)
	st.spawn_total = (f.units as Array).size()
	if not guards.is_empty():
		var gr: float = tune("altar", "guard_r", 90.0)
		for i in guards.size():
			var spot: Dictionary = altar_spots[i % altar_spots.size()]
			var a: float = st.rng.range_f(0.0, TAU)
			var gp := st.nearest_valid_pos(float(spot.x) + cos(a) * gr, float(spot.y) + sin(a) * gr, 16.0, 120.0)
			if gp.is_empty():
				gp = [float(spot.x) + cos(a) * gr, float(spot.y) + sin(a) * gr]
			st.spawn_enemy(String(guards[i][0]), gp[0], gp[1], false, String(guards[i][1]))
	st.spawned_all = false

## 제단 체력(막·빌드 기준, 시험값). 개편 전에는 어떤 막·어떤 빌드에서도 90 고정이라
## 효과를 한 번 보기도 전에 첫 접근에서 부서졌다. 구조물이라 일반 적 체력표(HP_TABLE_2)의 대상이 아니다.
static func altar_hp(st: CombatState, e: Dictionary) -> void:
	if not on():
		return
	var tbl: Array = TUNE.altar.hp_by_act
	var base: float = float(tbl[clampi(st.act, 1, tbl.size()) - 1])
	var lv: int = maxi(0, int(st.build.get("level", 1)) - 1) + int(st.build.get("forge", 0))
	var hp: float = base * (1.0 + float(TUNE.altar.hp_per_weapon_level) * float(lv))
	e.hp = hp
	e.hp_max = hp

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
	# 계측(규칙 영향 없음): 전장이 비어 있던 시간·적 2마리 이하였던 시간. 목표 4종 모두 같은 자리에서 센다
	var RL: Dictionary = (o.get("reinforce", {}) as Dictionary).get("log", {})
	if not RL.is_empty():
		var fu := field_units(st)
		if fu == 0:
			RL.empty_sec = float(RL.empty_sec) + dt
		if fu <= 2:
			RL.thin_sec = float(RL.thin_sec) + dt
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
		reinforce(st, o.reinforce, dt) # 인구 하한 보충(증원 제단과 별개 예산). 기본 편성이 다 나온 뒤 전장이 비면 채운다
		var all_dead := true
		for a in o.altars:
			if a.dead:
				if not bool(a.get("altar_msg", false)): # 부수면 그 효과가 멈춘다는 것을 화면에서 읽히게 한다
					a.altar_msg = true
					st.text(a.x, a.y - a.r - 16.0, "%s 멈춤" % altar_text(String(a.altar)), "#ffd166")
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
						note_altar_fx(st, a)
					elif on():
						a.timer = minf(float(a.timer), 1.0) # 대상이 없으면 곧 다시 본다(첫 효과가 계속 미뤄지지 않게)
			elif kind == "hazard":
				var H: Dictionary = S.hazard
				a.timer = float(H.interval)
				ring_hazards(st, p.x, p.y, int(H.n), float(H.dist), float(H.r), H, "altar", p.face + PI / 2.0)
				st.ev("hazard_warn")
				note_altar_fx(st, a)
				if on():
					st.text(a.x, a.y - a.r - 16.0, "위험 지역!", "#ff8a5c")
			elif kind == "reinforce":
				a.timer = float(S.reinforce.interval)
				# 동시 상한은 임무 편성 상한을 따른다(개편 전 고정 4는 일반 편성과 겹쳐 한 번도 발동하지 않았다)
				var cap: int = int((o.reinforce as Dictionary).get("cap", S.reinforce.cap)) if on() else int(S.reinforce.cap)
				var R: Dictionary = o.reinforce
				var AL: Dictionary = R.get("log", {})
				if not AL.is_empty():
					AL.try = int(AL.try) + 1
				if float(a.budget) > 0.0 and active_enemies(st) < cap:
					var pool: Array = R.pool
					var type := String(pool[int(R.spawned) % pool.size()])
					st.queue_wave([{ "type": type, "n": 1 }])
					a.budget = float(a.budget) - 1.0
					R.spawned = int(R.spawned) + 1
					st.ev("reinforce", { "n": 1 })
					note_altar_fx(st, a)
					if not AL.is_empty():
						AL.spawned = int(AL.spawned) + 1
						if float(AL.first_t) < 0.0:
							AL.first_t = st.t
						AL.last_t = st.t
					if on():
						st.text(a.x, a.y - a.r - 16.0, "증원!", "#c9a2ff")
				else:
					if not AL.is_empty():
						if float(a.budget) <= 0.0:
							AL.budget_block = int(AL.budget_block) + 1
						else:
							AL.cap_block = int(AL.cap_block) + 1
					if on() and float(a.budget) > 0.0:
						a.timer = minf(float(a.timer), 1.5) # 상한에 막혔으면 곧 다시 본다(예산이 남았을 때만)
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
## 계측(규칙 영향 없음): 제단이 효과를 낸 횟수·첫 효과 시각. "효과를 보기 전에 부서졌는가"를 세는 데 쓴다
static func note_altar_fx(st: CombatState, a: Dictionary) -> void:
	a.fx_n = int(a.get("fx_n", 0)) + 1
	if not a.has("first_fx_t"):
		a.first_fx_t = st.t

## 제단 효과 이름(한 줄 표시·파괴 문구 공용)
static func altar_text(kind: String) -> String:
	match kind:
		"heal": return "치료"
		"hazard": return "위험 지역"
		"reinforce": return "증원"
	return kind

## 8방위 안내 문구(화면 밖·먼 목표를 가리킬 때 쓴다)
static func dir_text(dx: float, dy: float) -> String:
	var a: float = atan2(dy, dx)
	var i: int = int(round(a / (PI / 4.0))) & 7
	return ["오른쪽", "오른쪽 아래", "아래", "왼쪽 아래", "왼쪽", "왼쪽 위", "위", "오른쪽 위"][i]

## 지금 향해야 할 목표 지점(큰 목표 표시·방향 안내용 내보내기 값).
## 화면(scripts/game/**)이 읽어 쓸 수 있게 규칙이 내보내는 값이다. 반환 {} = 표시할 지점 없음.
## {kind, x, y, r, state, ratio, dist, dir, inside, next{x,y}}
##  state: "outside"(원 밖 정지) | "progress"(진행 중) | "hit_pause"(피격 중단) | "moving"(지점 이동 예고) | "target"(부술 대상) | "done"
static func marker(st: CombatState) -> Dictionary:
	var o := st.obj
	if o.is_empty():
		return {}
	var p := st.player
	if bool(o.get("done", false)):
		return { "kind": st.objective, "x": p.x, "y": p.y, "r": 0.0, "state": "done", "ratio": 1.0, "dist": 0.0, "dir": "", "inside": true, "next": {} }
	var m := {}
	if st.objective == "seal":
		var z := _find_object(st, "seal")
		if z.is_empty():
			return {}
		var d := PGeom.dist(float(z.x), float(z.y), p.x, p.y)
		var inside: bool = d <= float(z.r)
		var stt := "progress"
		if float(o.get("move_warn_t", 0.0)) > 0.0:
			stt = "moving"
		elif float(o.get("hit_pause", 0.0)) > 0.0:
			stt = "hit_pause"
		elif not inside:
			stt = "outside"
		m = { "kind": "seal", "x": float(z.x), "y": float(z.y), "r": float(z.r), "state": stt,
			"ratio": float(o.progress) / maxf(0.001, float(o.total)), "dist": d, "dir": dir_text(float(z.x) - p.x, float(z.y) - p.y),
			"inside": inside, "next": z.get("next", {}) }
	elif st.objective == "rescue":
		var tgt := _find_object(st, "exit") if int(o.get("freed", 0)) >= int(o.get("cages", 2)) else {}
		if tgt.is_empty():
			var bd := INF
			for c in st.objects:
				if String(c.kind) == "cage" and not bool(c.freed):
					var dd := PGeom.dist(float(c.x), float(c.y), p.x, p.y)
					if dd < bd:
						bd = dd
						tgt = c
		if tgt.is_empty():
			return {}
		var near: float = float(spec(st).get("near", 72.0)) if String(tgt.kind) == "cage" else float(tgt.r)
		var d2 := PGeom.dist(float(tgt.x), float(tgt.y), p.x, p.y)
		var ac: Dictionary = o.get("active", {})
		m = { "kind": String(tgt.kind), "x": float(tgt.x), "y": float(tgt.y), "r": near,
			"state": ("progress" if not ac.is_empty() else ("target" if String(tgt.kind) == "exit" else "outside")),
			"ratio": progress_ratio(st), "dist": d2, "dir": dir_text(float(tgt.x) - p.x, float(tgt.y) - p.y), "inside": d2 <= near, "next": {} }
	elif st.objective == "altars":
		var best: Dictionary = {}
		var bd2 := INF
		for a in o.get("altars", []):
			if a.dead:
				continue
			var dd2 := PGeom.dist(a.x, a.y, p.x, p.y)
			if dd2 < bd2:
				bd2 = dd2
				best = a
		if best.is_empty():
			return {}
		m = { "kind": "altar", "x": float(best.x), "y": float(best.y), "r": float(best.r), "state": "target",
			"ratio": progress_ratio(st), "dist": bd2, "dir": dir_text(float(best.x) - p.x, float(best.y) - p.y), "inside": false, "next": {} }
	elif st.objective == "hunt":
		var el: Dictionary = o.get("elite", {})
		if el.is_empty() or bool(el.dead):
			return {}
		var d3 := PGeom.dist(el.x, el.y, p.x, p.y)
		m = { "kind": "elite", "x": float(el.x), "y": float(el.y), "r": float(el.r), "state": "target",
			"ratio": progress_ratio(st), "dist": d3, "dir": dir_text(float(el.x) - p.x, float(el.y) - p.y), "inside": false, "next": {} }
	return m

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
		var kinds: Array = []
		for a in o.altars:
			if not a.dead:
				alive += 1
				kinds.append(altar_text(String(a.altar)))
		if not on() or kinds.is_empty():
			return "남은 제단 %d / 3" % alive
		return "남은 제단 %d / 3 (%s)" % [alive, ", ".join(kinds)]
	if st.objective == "seal":
		var s2 := "봉인 %d%% · %d/%d단계" % [int(floor(float(o.progress) / float(o.total) * 100.0)), int(o.stage), int(o.stages)]
		if not on():
			if bool(o.paused):
				s2 += " · 정지"
			return s2
		# 정지 이유를 나눠서 알려준다(원 밖 / 피격 중단 / 이동 예고)와 원까지의 방향·거리
		var m := marker(st)
		match String(m.get("state", "")):
			"outside":
				s2 += " · 원 밖 정지 — %s %d 이동" % [String(m.dir), int(round(float(m.dist)))]
			"hit_pause":
				s2 += " · 피격 중단"
			"moving":
				s2 += " · 지점 이동 예고 — %s" % String(m.dir)
			"progress":
				s2 += " · 진행 중"
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
	# marker·progress·state는 화면(큰 목표 표시·현장 게이지·방향 안내)이 읽을 수 있게 규칙이 내보내는 값이다.
	# 지금 화면은 title·line·risk만 읽으므로 표시에는 쓰이지 않는다(보고에 기록).
	var m := marker(st)
	return { "title": "목적: " + String(S.short), "line": line, "risk": risk_text,
		"end_rule": "정예·지원병 전멸 시 종료" if st.objective == "hunt" else "목표 달성 시 종료(남은 적 무시)",
		"marker": m, "progress": progress_ratio(st), "state": String(m.get("state", "")) }

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
