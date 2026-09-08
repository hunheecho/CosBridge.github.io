class_name PBot
extends RefCounted
## 봇 입력(시험·영상용). 사람 입력과 같은 {mx,my,dodge_press,dodge_held,special,skill_e}를 만든다. 규칙 우회·즉시 종료·접촉 무시 처리 없음.
## 정책(policy):
##  - "stand": 제자리에서 자동 공격만(입력 없음). 밀도 비교의 기준선.
##  - "active": 확정된 돌진 통로 안이면 옆으로 회피(press, 끝날 때까지 held → 최대 거리), 물기 고정/유효 구간의 부채꼴 안이면 옆으로 회피,
##              위협이 없으면 가장 가까운 적에게 접근, 200 안에 2마리 이상이면 Q. (v2: 물기 회피 추가. v1은 돌진 통로만)
##  - "aggressive|balanced|survival|idle|aware|still": HTML bot.js POLICIES 이식(아래 POLICIES). 읽는 정보는 화면에 보이는 것만(적 상태·예고 각도·확정 방향·바닥 지역·투사체·체력·재사용).
## 판단 주기 DECIDE_STEPS=5스텝(HTML DECIDE_STEPS와 동일). 단발 입력(회피·Q·E)은 판단이 붙은 단계에서만 나가고, 다음 판단 전까지 이동 입력만 유지된다.
## HTML `dodge:true`는 판단 단계의 dodge_press와, 회피가 끝날 때까지의 dodge_held로 옮긴다.
## "stand"/"active"는 밀도 보고서(docs/DENSITY_REPORT.md)·tests/run_tests.gd가 의존하므로 동작을 바꾸지 않는다.

const STEP := 1.0 / 120.0
const DECIDE_STEPS := 5
const BACKLINE := ["shaman", "archer", "frostcaller", "spider"]
const CHOICE_ORDER := ["weapon_new", "skill_new", "weapon_mod", "weapon_level", "common", "skill_level", "skill_variant", "passive", "boss_reward"]

## 정책 정의(문서용 name/doc 포함). react_at은 예고 진행률(0~1)로, 그 이상 진행된 예고에만 반응한다.
const POLICIES := {
	"aggressive": { "id": "aggressive", "name": "공격 우선", "react_at": 1.0, "dodge_locked": true, "zone_margin": 0.0, "keep_dist": 40.0, "retreat_hp": 0.0, "q_min_enemies": 2, "e_min_enemies": 1, "e_range": 200.0, "give_up": "never",
		"doc": { "period": "40ms(일반)·헤드리스 5스텝", "reads": "확정(lock/dash/leap)된 예고와 투사체만, 바닥 지역은 무시", "target": "가장 가까운 적(표식이 있으면 표식)", "q": "200 안 적 2마리 이상 또는 보스 빈틈", "e": "200 안 적 1마리 이상", "dodge": "확정 예고 통로/원 안에 있을 때", "terrain": "Combat.steerDir 접선 우회", "give_up": "없음(항상 접근)" } },
	"balanced": { "id": "balanced", "name": "균형", "react_at": 0.4, "dodge_locked": true, "zone_margin": 30.0, "keep_dist": 55.0, "retreat_hp": 0.25, "q_min_enemies": 3, "e_min_enemies": 2, "e_range": 200.0, "give_up": "hp<25%면 예고 없는 순간에만 접근",
		"doc": { "period": "40ms(일반)·헤드리스 5스텝", "reads": "준비 40% 이상 진행된 예고·확정·투사체·바닥 지역·구름 예고", "target": "궁수·주술사·서리술사 같은 후열 우선, 없으면 가장 가까운 적", "q": "200 안 적 3마리 이상 또는 보스 빈틈·돌진 확정", "e": "200 안 적 2마리 이상", "dodge": "확정 예고 안에 있을 때", "terrain": "Combat.steerDir 접선 우회", "give_up": "체력 25% 미만이면 예고가 없을 때만 접근" } },
	"survival": { "id": "survival", "name": "생존 우선", "react_at": 0.0, "dodge_locked": true, "zone_margin": 60.0, "keep_dist": 90.0, "retreat_hp": 0.5, "q_min_enemies": 1, "e_min_enemies": 1, "e_range": 160.0, "give_up": "hp<50%면 이탈, 위협 없을 때만 사거리까지 접근",
		"doc": { "period": "40ms(일반)·헤드리스 5스텝", "reads": "모든 준비 단계 예고·투사체·바닥 지역(여유 60)", "target": "가장 가까운 적을 사거리 끝에서", "q": "위협이 확정된 적이 200 안에 1마리 이상", "e": "160 안 적 1마리 이상(결계·돌풍은 방어용)", "dodge": "확정 예고 안 또는 근접 적 60 안", "terrain": "Combat.steerDir 접선 우회", "give_up": "체력 50% 미만이면 모든 적에서 이탈(시간 초과 가능 — 성공으로 집계하지 않음)" } },
	"idle": { "id": "idle", "name": "제자리(자동 공격만)", "react_at": 9.0, "dodge_locked": false, "zone_margin": 0.0, "keep_dist": 0.0, "retreat_hp": 0.0, "q_min_enemies": 99, "e_min_enemies": 99, "e_range": 0.0, "give_up": "없음", "no_move": true, "no_skills": true,
		"doc": { "period": "—", "reads": "아무것도 읽지 않음", "target": "없음", "q": "사용 안 함", "e": "사용 안 함", "dodge": "없음", "terrain": "없음", "give_up": "없음" } },
	"aware": { "id": "aware", "name": "기술 특성 이해(균형+거리)", "react_at": 0.4, "dodge_locked": true, "zone_margin": 30.0, "keep_dist": 55.0, "retreat_hp": 0.25, "q_min_enemies": 3, "e_min_enemies": 2, "e_range": 200.0, "give_up": "균형과 동일", "aware": true,
		"doc": { "period": "40ms(일반)·헤드리스 5스텝", "reads": "균형과 동일", "target": "균형과 동일", "q": "균형과 동일", "e": "균형과 동일", "dodge": "균형과 동일", "terrain": "균형과 동일", "give_up": "균형과 동일. 차이: 회전 칼날만 있으면 살 중간(반지름 55%)에 적을 두고, 관통창은 근접 약화 구간(사거리 45%) 밖을 유지" } },
	"still": { "id": "still", "name": "제자리(Q/E만)", "react_at": 9.0, "dodge_locked": false, "zone_margin": 0.0, "keep_dist": 0.0, "retreat_hp": 0.0, "q_min_enemies": 1, "e_min_enemies": 1, "e_range": 220.0, "give_up": "없음", "no_move": true,
		"doc": { "period": "40ms(일반)·헤드리스 5스텝", "reads": "아무것도 읽지 않음", "target": "없음(이동 없음)", "q": "220 안 적 1마리 이상 또는 보스 빈틈", "e": "220 안 적 1마리 이상", "dodge": "없음", "terrain": "없음", "give_up": "없음" } },
}

var policy: String = "active"
var last: Dictionary = { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false }
## HTML 정책의 기억(mem): steer(조향 상태), last(마지막 판단), last_n
var mem: Dictionary = {}

func _init(pol: String = "active") -> void:
	policy = pol

## 정책 표(보고서용 name/doc 포함). "stand"/"active"는 Godot 전용 정책이라 표에 없다.
static func policies() -> Dictionary:
	return POLICIES

func step_input(st: CombatState) -> Dictionary:
	if policy == "stand":
		return { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false }
	if policy == "active":
		if st.step_n % 5 != 0:
			return { "mx": last.mx, "my": last.my, "dodge_press": false, "dodge_held": bool(last.dodge_held) or st.player.dodge_active, "special": false }
		last = decide(st)
		return last
	# HTML stepInput: 이번에 실행될 단계 번호(step 호출 전)가 DECIDE_STEPS의 배수일 때만 판단
	var n: int = st.step_n
	var ml: Dictionary = mem.get("last", {})
	if ml.is_empty() or n % DECIDE_STEPS == 0:
		var d := decide_policy(st)
		mem.last = d
		mem.last_n = n
		return d
	return { "mx": ml.mx, "my": ml.my, "dodge_press": false, "dodge_held": bool(ml.dodge_held) or st.player.dodge_active, "special": false, "skill_e": false }

# ---------- "active" 정책(Godot 전용, 변경 금지) ----------
func decide(st: CombatState) -> Dictionary:
	var p := st.player
	var mx := 0.0
	var my := 0.0
	var dodge := false
	var special := false
	var threatened := false
	for e in st.alive_enemies():
		var d: Dictionary = e.def
		if not PEnemies.is_wolf(d):
			continue # 늑대 규칙(물기·돌진)만 읽는다. 다른 적은 'aware' 정책이 다룬다(D33 기준 봇 동작은 늑대만 있어 변화 없음)
		if e.state == "lock" or e.state == "dash":
			var L := float(d.dash.dash_speed) * float(d.dash.dash_time)
			var ex: float = e.x + cos(e.dir) * L
			var ey: float = e.y + sin(e.dir) * L
			if PGeom.seg_circle(e.x, e.y, ex, ey, p.x, p.y, p.r + e.r + 10.0):
				threatened = true
				var side := [-sin(e.dir), cos(e.dir)]
				var rel: float = (p.x - e.x) * side[0] + (p.y - e.y) * side[1]
				var s := 1.0 if rel >= 0.0 else -1.0
				mx += side[0] * s
				my += side[1] * s
				if e.state == "lock":
					dodge = true
		elif e.state == "bite_lock" or e.state == "bite_hit":
			var dist := PGeom.dist(e.x, e.y, p.x, p.y)
			if dist <= float(d.bite.reach) + 24.0:
				var ang := atan2(p.y - e.y, p.x - e.x)
				if absf(PGeom.ang_diff(ang, e.dir)) <= float(d.bite.arc_deg) * PI / 360.0 + 0.35:
					threatened = true
					var side2 := [-sin(e.dir), cos(e.dir)]
					var rel2: float = (p.x - e.x) * side2[0] + (p.y - e.y) * side2[1]
					var s2 := 1.0 if rel2 >= 0.0 else -1.0
					mx += side2[0] * s2
					my += side2[1] * s2
					if e.state == "bite_lock":
						dodge = true
	if not threatened:
		var best := {}
		var bd := INF
		for e in st.alive_enemies():
			var dd := PGeom.dist(p.x, p.y, e.x, e.y)
			if dd < bd:
				bd = dd
				best = e
		if not best.is_empty() and bd > 60.0:
			var n := st.steer_dir({ "x": p.x, "y": p.y, "r": p.r, "steer_side": 0, "steer_t": 0.0 }, best.x, best.y)
			mx = n[0]
			my = n[1]
	var near := 0
	for e in st.alive_enemies():
		if PGeom.dist(p.x, p.y, e.x, e.y) < 200.0:
			near += 1
	if near >= 2 and p.special_cd <= 0.0:
		special = true
	var n2 := PGeom.norm(mx, my)
	return { "mx": n2[0], "my": n2[1], "dodge_press": dodge, "dodge_held": dodge or p.dodge_active, "special": special }

# ---------- 위협 도형(HTML bot.threats) ----------
## {kind:"beam", x,y,ang,len,w, prog(0~1), locked} | {kind:"circle", x,y,r, prog, locked} | {kind:"arc", x,y,ang,r,half, prog, locked} | {kind:"zone", x,y,r}
## 적 개체가 있는 위협은 e, 적 투사체는 proj=true
static func threats(st: CombatState) -> Array:
	var out: Array = []
	var p := st.player
	for e in st.enemies:
		if e.dead:
			continue
		var d: Dictionary = e.def
		if bool(e.get("boss", false)):
			boss_threats(st, e, out)
			continue
		if e.type == "wolf" or e.type == "wolf_alpha":
			var D: Dictionary = d.dash
			if e.state == "crouch":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.aim_angle), "len": float(D.dash_speed) * float(D.dash_time) + 40.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": float(e.state_t) / float(D.crouch), "locked": false })
			elif e.state == "lock" or e.state == "dash":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir), "len": float(D.dash_speed) * float(D.dash_time) + 40.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": 1.0, "locked": true })
		elif e.type == "archer":
			if e.state == "aim":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.aim_angle), "len": 2000.0, "w": 40.0, "prog": float(e.state_t) / float(d.aim), "locked": false })
			elif e.state == "lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir), "len": 2000.0, "w": 40.0, "prog": 1.0, "locked": true })
		elif e.type == "spore":
			if e.state == "swell":
				var pr: float = float(e.state_t) / float(d.swell)
				out.append({ "kind": "circle", "e": e, "x": e.x, "y": e.y, "r": float(d.cloudR), "prog": pr, "locked": pr > 0.6 })
		else:
			PEnemies.threats(st, e, out)
	for pr in st.projectiles:
		if pr.owner == "enemy":
			out.append({ "kind": "beam", "x": pr.x, "y": pr.y, "ang": atan2(float(pr.vy), float(pr.vx)), "len": 220.0, "w": 40.0 + float(pr.r) * 2.0, "prog": 1.0, "locked": true, "proj": true })
	# 바닥 지역: 포자 구름(HTML bot이 직접 추가) + 서리 지역·거미줄(HTML Enemies.zoneThreats). Godot의 PEnemies.zone_threats가 둘 다 넣는다
	PEnemies.zone_threats(st, out)
	PObjectives.threats(st, out) # 바닥 위험(목표·봉인 장치)
	return out

## 가시갈기(boss_id "boss") 위협. 다른 보스는 PBoss2.threats
static func boss_threats(st: CombatState, bz: Dictionary, out: Array) -> void:
	var bid := String(bz.get("boss_id", ""))
	if bid != "" and bid != "boss":
		PBoss2.threats(st, bz, out)
		return
	var cfg: Dictionary = PCatalog.boss_defs().boss
	var p := st.player
	var s := String(bz.state)
	if s == "dash_aim":
		out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "len": float(cfg.dash.dist) + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": float(bz.state_t) / float(cfg.dash.aim), "locked": false })
	if s == "dash_lock" or s == "dash":
		var dl: float = float(bz.get("dash_len", 0.0))
		if dl == 0.0:
			dl = float(cfg.dash.dist)
		out.append({ "kind": "beam", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "len": dl + 40.0, "w": (bz.r + p.r) * 2.0 + 40.0, "prog": 1.0, "locked": true })
	if s == "sweep_aim":
		out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.aim_angle), "r": float(cfg.sweep.radius) + 30.0, "half": float(cfg.sweep.arcDeg) * PI / 360.0 + 0.2, "prog": float(bz.state_t) / float(cfg.sweep.aim), "locked": false })
	if s == "sweep_lock":
		out.append({ "kind": "arc", "e": bz, "x": bz.x, "y": bz.y, "ang": float(bz.dir), "r": float(cfg.sweep.radius) + 30.0, "half": float(cfg.sweep.arcDeg) * PI / 360.0 + 0.2, "prog": 1.0, "locked": true })
	if s == "pounce_aim" or s == "pounce_lock" or s == "leap":
		var land: Dictionary = bz.get("land", {})
		if not land.is_empty():
			out.append({ "kind": "circle", "e": bz, "x": float(land.x), "y": float(land.y), "r": float(cfg.pounce.radius) + 40.0, "prog": (float(bz.state_t) / float(cfg.pounce.aim)) if s == "pounce_aim" else 1.0, "locked": s != "pounce_aim" })

static func inside(th: Dictionary, p: Dictionary) -> bool:
	var k := String(th.kind)
	if k == "beam":
		return PGeom.in_beam(float(th.x), float(th.y), float(th.ang), float(th.len), float(th.w), p.x, p.y, p.r)
	if k == "circle" or k == "zone":
		return PGeom.dist(float(th.x), float(th.y), p.x, p.y) <= float(th.r) + p.r
	if k == "arc":
		return PGeom.in_arc(float(th.x), float(th.y), float(th.r), float(th.ang), float(th.half), p.x, p.y, p.r)
	return false

## 위협에서 벗어나는 방향 [x, y]
static func escape_dir(th: Dictionary, p: Dictionary) -> Array:
	if String(th.kind) == "beam":
		var ang := float(th.ang)
		var sx := -sin(ang)
		var sy := cos(ang)
		var rel: float = (p.x - float(th.x)) * sx + (p.y - float(th.y)) * sy
		var s := 1.0 if rel >= 0.0 else -1.0
		return [sx * s, sy * s]
	var n := PGeom.norm(p.x - float(th.x), p.y - float(th.y))
	if n[0] != 0.0 or n[1] != 0.0:
		return n
	return [1.0, 0.0]

# ---------- 대상 선택 ----------
static func _alive_visible(st: CombatState) -> Array:
	var out: Array = []
	for e in st.enemies:
		if not e.dead and not bool(e.get("hidden", false)):
			out.append(e)
	return out

static func _nearest(list: Array, p: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for e in list:
		var d := PGeom.dist(float(e.x), float(e.y), p.x, p.y)
		if d < bd:
			bd = d
			best = e
	return best

## 표식 → 보스 → 목표 우선 대상(제단·정예) → 후열(균형·aware) → 가장 가까운 적. 없으면 {}
static func pick_target(st: CombatState, pol: Dictionary) -> Dictionary:
	var p := st.player
	var alive := _alive_visible(st)
	if alive.is_empty():
		return {}
	if st.mark_target != null and not bool(st.mark_target.dead):
		return st.mark_target
	if not st.boss.is_empty() and not bool(st.boss.dead):
		return st.boss
	if not st.obj.is_empty():
		var ot := PObjectives.bot_target(st)
		if not ot.is_empty():
			return ot
	if String(pol.id) == "balanced" or bool(pol.get("aware", false)):
		var back: Array = []
		for e in alive:
			if BACKLINE.has(String(e.type)):
				back.append(e)
		if not back.is_empty():
			return _nearest(back, p)
	return _nearest(alive, p)

static func weapon_range(st: CombatState) -> float:
	var r := 0.0
	for w in st.weapons:
		var s: Dictionary = w.stats
		var rr: float = float(s.get("radius", 0.0)) if String(s.get("kind", "")) == "orbit" else float(s.get("range", 0.0))
		if String(s.get("kind", "")) != "orbit" and rr == 0.0:
			rr = 60.0
		if rr > r:
			r = rr
	return r if r != 0.0 else 80.0

# ---------- 판단(HTML bot.decide) ----------
## 반환 {mx,my,dodge_press,dodge_held,special,skill_e}
func decide_policy(st: CombatState) -> Dictionary:
	var pol: Dictionary = POLICIES.get(policy, POLICIES.balanced)
	var pid := String(pol.id)
	var aware := bool(pol.get("aware", false))
	var p := st.player
	if not mem.has("steer"):
		mem.steer = { "x": 0.0, "y": 0.0, "r": p.r, "steer_side": 0, "steer_t": 0.0 }
	var mv: Array = [0.0, 0.0]
	var dodge := false
	var special := false
	var skill_e := false
	var threatened := false
	var locked_near := false
	var alive := _alive_visible(st)
	var hp_ratio: float = p.hp / p.hp_max
	var zone_margin := float(pol.zone_margin)
	var react_at := float(pol.react_at)
	# 1) 위협 회피(정책의 반응 시점 이상 진행된 예고만)
	var ex := 0.0
	var ey := 0.0
	var n := 0
	for th in threats(st):
		var kind := String(th.kind)
		if kind == "zone":
			if zone_margin > 0.0 and PGeom.dist(float(th.x), float(th.y), p.x, p.y) <= float(th.r) + zone_margin:
				var dz := escape_dir(th, p)
				ex += dz[0]
				ey += dz[1]
				n += 1
			continue
		var locked := bool(th.get("locked", false))
		if float(th.get("prog", 0.0)) < react_at and not locked:
			continue
		# **조준 중인 사격선은 피할 수 없다.** 궁수·주술사의 조준선은 발사 전까지 플레이어를
		# 계속 따라오므로 옆으로 비켜도 조준이 따라온다. 그런데도 비키면 거리를 못 좁혀
		# 전투가 늘어지고, 궁수가 여럿이면 항상 누군가 조준 중이라 접근 자체를 못 한다.
		# 방향이 확정된 뒤(locked)에만 옆걸음이 실제로 통하므로 그때만 피한다.
		# 돌진 통로도 beam이지만 그쪽은 발사 전 예고에서 이미 방향이 굳으므로 locked로 들어온다.
		# 사격선은 길이가 매우 길다(2000). 늑대 돌진 통로는 실제 돌진 거리라 짧으므로 구분된다.
		if kind == "beam" and not locked and float(th.get("len", 0.0)) >= 1000.0:
			continue
		var near: bool = (PGeom.dist(float(th.x), float(th.y), p.x, p.y) <= float(th.r) + zone_margin + p.r) if kind == "circle" else inside(th, p)
		if not near:
			continue
		var d := escape_dir(th, p)
		ex += d[0]
		ey += d[1]
		n += 1
		threatened = true
		var proj := bool(th.get("proj", false))
		if locked and bool(pol.dodge_locked) and not proj:
			dodge = true
		if locked and proj:
			dodge = true
		if locked and th.has("e") and PGeom.dist(float(th.e.x), float(th.e.y), p.x, p.y) < 200.0:
			locked_near = true
	if n > 0:
		var dn := PGeom.norm(ex, ey)
		mv = dn if (dn[0] != 0.0 or dn[1] != 0.0) else [1.0, 0.0]
	# 2) 접근·이탈. 목표 지점(봉인·우리·출구)이 있으면 위협이 없을 때 그쪽으로(적은 자동 공격이 처리)
	var goal: Dictionary = PObjectives.bot_goal(st) if not st.obj.is_empty() else {}
	var target := pick_target(st, pol)
	var retreat_hp := float(pol.retreat_hp)
	if not threatened and n == 0 and not goal.is_empty() and not (pid == "survival" and hp_ratio < retreat_hp):
		var s: Dictionary = mem.steer
		s.x = p.x
		s.y = p.y
		if float(s.steer_t) > 0.0:
			s.steer_t = float(s.steer_t) - 0.04
		mv = st.steer_dir(s, float(goal.x), float(goal.y)) if st.obstacles.size() > 0 else PGeom.norm(float(goal.x) - p.x, float(goal.y) - p.y)
	elif not threatened and n == 0 and not target.is_empty():
		var tx := float(target.x)
		var ty := float(target.y)
		var d := PGeom.dist(tx, ty, p.x, p.y)
		var to_t := PGeom.norm(tx - p.x, ty - p.y)
		var is_boss := bool(target.get("boss", false))
		var rng_ := weapon_range(st)
		var orbit_only: bool = st.weapons.size() > 0 # 공전 칼날만 있으면 궤도(반지름)에 적이 걸치도록 거리를 둔다
		for w in st.weapons:
			var k := String(w.stats.get("kind", ""))
			if k != "orbit" and k != "mine":
				orbit_only = false
				break
		var want: float
		if is_boss:
			want = float(target.r) + 40.0 if PBoss.is_exposed(target) else float(target.r) + rng_ * 0.7
		else:
			want = maxf(float(pol.keep_dist), maxf(rng_ * 0.85 if pid == "survival" else 0.0, rng_ * 0.9 if orbit_only else 0.0))
		if aware: # 기술 특성 이해: 칼날 살 중간·창 근접 약화 구간 밖
			var beam: Dictionary = {}
			for w in st.weapons:
				if String(w.stats.get("kind", "")) == "beam":
					beam = w
					break
			if orbit_only:
				want = float(target.r) + rng_ * 0.55 if is_boss else rng_ * 0.55
			elif not beam.is_empty() and not is_boss:
				var bs: Dictionary = beam.stats
				var sweet: float = float(bs.get("sweetFrom", 0.0))
				if sweet == 0.0:
					sweet = 0.45
				want = maxf(want, float(bs.range) * sweet + 20.0)
		if pid == "survival" and hp_ratio < retreat_hp: # 생존 우선: 체력이 낮으면 이탈
			want = 260.0
		if (pid == "balanced" or aware) and hp_ratio < retreat_hp:
			var busy := false
			for e in alive:
				if e.state != "approach" and e.state != "recover":
					busy = true
					break
			if busy:
				want = maxf(want, 160.0)
		if pid == "survival": # 근접 위협에서 굴러 나감
			for e in alive:
				if e.state != "approach" and e.state != "recover" and e.state != "stagger" and PGeom.dist(float(e.x), float(e.y), p.x, p.y) < 60.0:
					dodge = true
					break
		if d > want + 10.0:
			var s2: Dictionary = mem.steer
			s2.x = p.x
			s2.y = p.y
			if float(s2.steer_t) > 0.0:
				s2.steer_t = float(s2.steer_t) - 0.04
			mv = st.steer_dir(s2, tx, ty) if st.obstacles.size() > 0 else to_t
		elif d < want - 30.0:
			mv = [-to_t[0], -to_t[1]]
	# 3) Q/E
	var near200 := 0
	for e in alive:
		if PGeom.dist(float(e.x), float(e.y), p.x, p.y) < 200.0:
			near200 += 1
	var bz := st.boss
	if p.special_cd <= 0.0:
		if not bz.is_empty() and not bool(bz.dead) and (bz.state == "recover" or bz.state == "dash_lock") and PGeom.dist(float(bz.x), float(bz.y), p.x, p.y) < 180.0:
			special = true
		if (locked_near or (near200 >= 1 and threatened)) if pid == "survival" else near200 >= int(pol.q_min_enemies):
			special = true
	var es = st.build.skills.get("e") if st.build.has("skills") else null
	if es != null and p.e_cd <= 0.0:
		var near_e := 0
		var e_range := float(pol.e_range)
		for e in alive:
			if PGeom.dist(float(e.x), float(e.y), p.x, p.y) < e_range:
				near_e += 1
		if near_e >= int(pol.e_min_enemies):
			skill_e = true
		if String(es.id) == "ward" and pid != "survival" and not threatened and hp_ratio > 0.7:
			skill_e = false
	if bool(pol.get("no_move", false)): # 제자리 정책: 이동·회피 없음(보스 비교 기준선)
		var no_skills := bool(pol.get("no_skills", false))
		return { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": p.dodge_active, "special": false if no_skills else special, "skill_e": false if no_skills else skill_e }
	return { "mx": mv[0], "my": mv[1], "dodge_press": dodge, "dodge_held": dodge or p.dodge_active, "special": special, "skill_e": skill_e }

# ---------- 헤드리스 실행 보조 ----------
## 단계마다 step_input. opts: {max_sec(180), bot(PBot, 기억 이어가기), on_level_up(Callable(st))}. st.metrics.far_frac(길찾기 실패 진단) 기록
static func run_combat(st: CombatState, policy_id: String, opts: Dictionary = {}) -> CombatState:
	var dt := STEP
	var max_n := int(round(float(opts.get("max_sec", 180.0)) / dt))
	var n := 0
	var bot: PBot = opts.bot if opts.has("bot") and opts.bot is PBot else PBot.new(policy_id)
	var far_steps := 0
	var alive_steps := 0
	while st.status == "running" and n < max_n:
		var inp := bot.step_input(st)
		st.step(inp, dt)
		n += 1
		if n % 12 == 0: # 길찾기 실패 진단: 적이 살아 있는데 모든 적과 300 이상 떨어진 시간 비율(시간 초과의 원인 구분용)
			var p := st.player
			var near := false
			var any := false
			for e in st.enemies:
				if e.dead or bool(e.get("hidden", false)):
					continue
				any = true
				if PGeom.dist(float(e.x), float(e.y), p.x, p.y) < 300.0:
					near = true
					break
			if any:
				alive_steps += 1
				if not near:
					far_steps += 1
		if opts.has("on_level_up") and st.level_ups > 0:
			st.level_ups = 0
			(opts.on_level_up as Callable).call(st)
	st.metrics.far_frac = (round(float(far_steps) / float(alive_steps) * 100.0) / 100.0) if alive_steps > 0 else 0.0
	return st

## 브라우저 프레임 재현(검증용): 프레임마다 dt를 누적하고 고정 단계를 실행한다(main.frame과 같은 규칙: 12단계 상한, 초과분 버림)
static func frame_loop(st: CombatState, policy_id: String, fps: float, opts: Dictionary = {}) -> CombatState:
	var dt := STEP
	var bot := PBot.new(policy_id)
	var acc := 0.0
	var frames := 0
	var max_frames := int(round(float(opts.get("max_sec", 180.0)) * fps))
	while st.status == "running" and frames < max_frames:
		acc += minf(0.1, 1.0 / fps)
		var guard := 0
		while acc >= dt and guard < 12:
			guard += 1
			st.step(bot.step_input(st), dt)
			acc -= dt
		if guard >= 12:
			acc = 0.0
		frames += 1
	return st

## 성장 모드에서 봇의 카드 선택: 새 무기 > E 습득 > 무기 방식 > 무기 레벨 > 나머지 순, 같은 순위면 시드 난수. 선택지가 없으면 {}
static func pick_choice(offer: Dictionary, seed: int) -> Dictionary:
	var cs: Array = offer.get("choices", [])
	if cs.is_empty():
		return {}
	var best := 1 << 30
	for c in cs:
		var idx := CHOICE_ORDER.find(String(c.kind))
		if idx < best:
			best = idx
	var pool: Array = []
	for c in cs:
		if CHOICE_ORDER.find(String(c.kind)) == best:
			pool.append(c)
	var sv: int = seed if seed != 0 else 1
	var r := PRng.new((sv + int(offer.get("seq", 0)) * 13) & 0xFFFFFFFF)
	return pool[int(floor(r.next() * float(pool.size())))]
