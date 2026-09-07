class_name PObserve
extends RefCounted
## 관측 계층(docs/BOT_FRAMEWORK.md §관측 경계): CombatState → 화면에 실제로 그려지는 것만 담은 읽기 전용 스냅샷.
## 모든 값은 스칼라·문자열·새 Dictionary/Array(깊은 복사)라 원본 상태 참조가 남지 않는다. 봇·계측은 이 사전만 읽는다.
## 담는 것: 적(위치·반지름·등급·상태 이름·체력 막대 비율·좌우 방향), 예고 도형(render.gd draw_telegraphs와 같은 수치: 부채꼴/통로/원/직선),
##   적 투사체(위치·속도·반지름), 바닥 지역(종류·위치·반지름·표시되는 남은 시간), 목표물, 지형, 자기 상태(체력·보호막·재사용·회피), 보스 막대, 시간,
##   등장 예고(화면의 spawnwarn/pawwarn 효과), 조작 규칙(회피 거리·시간·재사용, 이동 속도, 자동기술 사거리 = 기술 설명상 성능).
## 담지 않는 것: 다음 공격의 난수 결과, 아직 예고되지 않은 착탄 지점·방향, 숨은 적(hidden), 미등장 대기열(pending) 좌표, 예고에 표시되지 않는 내부 타이머(재사용·ready_t·dash_ready_at 등),
##   최종 충돌 결과, 규칙 엔진을 미리 실행해 얻은 정답. 화면에 없는 정확한 발동 시각도 주지 않는다(예고 진행률 prog와 화면에 글자로 표시되는 남은 초 shown_left만).
## 위협 = {attack_id, enemy_id, type, kind: "sector"|"corridor"|"circle"|"lane", phase: "warn"|"lock"|"active", prog, x, y, ang, r, half, len, w, harm: "damage"|"slow", shown_left, rev, label}.
## attack_id = "e<적 id>#<attack_n>"(공격 시작마다 combat_state/enemies가 올리는 번호) + 부분 접미사(:lane0 등), 지역은 "zone:<종류>:<x>:<y>", 투사체는 추적기가 준 "proj:<n>".
## rev(수정 번호)는 take()를 쓰는 추적 인스턴스가 붙이며, 그려지는 기하(각도 0.5°·위치 1px·단계)가 바뀔 때만 오른다.

const VERSION := "observe-1"
const LANE_W := 40.0        # 화면의 선 예고(궁수·주술사 조준선)에는 폭이 없으므로 봇은 화살 반지름+플레이어 반지름 기준 폭 40을 가정한다(PBot과 같은 값)
const PROJ_LOOK := 220.0    # 날아가는 투사체의 진행 방향 외삽 길이(공개 정보의 제한적 외삽)
const ARCHER_LANE_LEN := 2000.0

var _geom_key: Dictionary = {}   # attack_id → 마지막 기하 키(추적 인스턴스)
var _rev: Dictionary = {}        # attack_id → 수정 번호
var _proj_track: Array = []      # [{id, x, y, vx, vy}] 투사체 동일성 추적(위치 외삽 일치)
var _proj_next: int = 1

## 추적 인스턴스: 스냅샷 + 위협별 rev(기하 변경 횟수) + 투사체 id 유지. full=false면 지각에 필요한 부분(시간·자기 상태·위협·투사체)만 만든다(판단 단계가 아닐 때의 비용 절감)
func take(st: CombatState, full: bool = true) -> Dictionary:
	var snap := snapshot(st, full)
	# 발사자가 없는 투사체의 id: 이전 위치 + 속도×dt 와 일치하면 같은 투사체(발사자가 있으면 e<id>#<n>:proj<i>로 이미 붙어 있다)
	var dt: float = 1.0 / 120.0
	var next_track: Array = []
	for pr in snap.projectiles:
		if String(pr.id) != "":
			continue
		var found := -1
		for i in _proj_track.size():
			var q: Dictionary = _proj_track[i]
			if absf(float(q.vx) - float(pr.vx)) > 1e-6 or absf(float(q.vy) - float(pr.vy)) > 1e-6:
				continue
			var ex: float = float(q.x) + float(q.vx) * dt
			var ey: float = float(q.y) + float(q.vy) * dt
			if PGeom.dist(ex, ey, float(pr.x), float(pr.y)) <= 3.0 + absf(float(q.vx)) * dt: # 감속장 안(tf 0.4)은 예측보다 느리므로 여유
				found = i
				break
		var pid: String
		if found >= 0:
			pid = String(_proj_track[found].id)
			_proj_track.remove_at(found)
		else:
			pid = "proj:%d" % _proj_next
			_proj_next += 1
		pr.id = pid
		next_track.append({ "id": pid, "x": float(pr.x), "y": float(pr.y), "vx": float(pr.vx), "vy": float(pr.vy) })
	_proj_track = next_track
	# 발사자 없는 투사체 위협의 attack_id를 추적 id로(threats_of는 st.projectiles와 같은 순서로 넣는다)
	var pi := 0
	for th in snap.threats:
		if String(th.attack_id) == "proj:":
			while pi < snap.projectiles.size() and String(snap.projectiles[pi].shooter_attack) != "":
				pi += 1
			if pi < snap.projectiles.size():
				th.attack_id = String(snap.projectiles[pi].id)
				pi += 1
	# rev: 기하 키가 바뀐 위협만 증가
	var seen := {}
	for th in snap.threats:
		var id := String(th.attack_id)
		seen[id] = true
		var key := geom_key(th)
		if not _geom_key.has(id):
			_rev[id] = 0
		elif String(_geom_key[id]) != key:
			_rev[id] = int(_rev[id]) + 1
		_geom_key[id] = key
		th.rev = int(_rev[id])
	for id in _geom_key.keys():
		if not seen.has(id):
			_geom_key.erase(id)
			_rev.erase(id)
	return snap

## 그려지는 기하 키(각도 0.5°, 위치·길이 1px, 단계)
static func geom_key(th: Dictionary) -> String:
	return "%s|%d|%d|%d|%d|%d|%d|%d|%s" % [String(th.kind), int(round(float(th.x))), int(round(float(th.y))), int(round(float(th.get("ang", 0.0)) * 360.0 / PI)), int(round(float(th.get("r", 0.0)))), int(round(float(th.get("half", 0.0)) * 100.0)), int(round(float(th.get("len", 0.0)))), int(round(float(th.get("w", 0.0)))), String(th.phase)]

## 무상태 스냅샷(rev = 0, 발사자 없는 투사체 id는 빈 문자열). 봇은 보통 추적 인스턴스의 take()를 쓴다. full=false면 시간·자기 상태·위협·투사체만
static func snapshot(st: CombatState, full: bool = true) -> Dictionary:
	var p: Dictionary = st.player
	var out := {
		"version": VERSION, "full": full, "t": float(st.t), "step_n": int(st.step_n), "status": String(st.status), "mode": String(st.mode), "intro": float(st.intro) > 0.0,
		"arena_w": float(st.arena_w), "arena_h": float(st.arena_h),
		"player": { "x": float(p.x), "y": float(p.y), "r": float(p.r), "hp": float(p.hp), "hp_max": float(p.hp_max), "shield": float(p.shield),
			"dodge_cd": float(p.dodge_cd), "dodge_active": bool(p.dodge_active), "dodge_dist": float(p.dodge_dist), "special_cd": float(p.special_cd), "e_cd": float(p.get("e_cd", 0.0)),
			"face": float(p.face), "moving": bool(p.moving), "hurt": float(p.flash) > 0.0, "has_e": st.build.has("skills") and st.build.skills.get("e") != null,
			"e_id": (String(st.build.skills.e.id) if (st.build.has("skills") and st.build.skills.get("e") != null) else "") },
		"rules": {},
		"enemies": [], "threats": [], "projectiles": [], "zones": [], "objects": [], "obstacles": [], "pickups": [], "spawn_warns": [],
		"boss": {}, "field": {},
	}
	threats_of(st, out.threats)
	var proj_n := {}
	for pr in st.projectiles:
		if String(pr.get("owner", "")) != "enemy" or bool(pr.get("dead", false)):
			continue
		var sa := _shooter_attack(pr, proj_n)
		out.projectiles.append({ "kind": String(pr.kind), "x": float(pr.x), "y": float(pr.y), "vx": float(pr.vx), "vy": float(pr.vy), "r": float(pr.r), "w": float(pr.get("width", float(pr.r) * 2.0)), "id": sa, "shooter_attack": sa })
	if not full:
		return out
	out.rules = rules_of(st)
	for ob in st.obstacles:
		out.obstacles.append({ "id": String(ob.id), "type": String(ob.type), "x": float(ob.x), "y": float(ob.y), "r": float(ob.r) })
	for e in st.enemies:
		if bool(e.dead) or bool(e.get("hidden", false)):
			continue # 죽은 적·지하 잠복(hidden)은 화면에 몸이 없다
		out.enemies.append({ "id": int(e.id), "type": String(e.type), "tier": String(e.get("tier", "normal")), "x": float(e.x), "y": float(e.y), "r": float(e.r),
			"face_x": float(e.get("face_x", 1.0)), "state": String(e.state), "hp_frac": (float(e.hp) / float(e.hp_max)) if float(e.hp_max) > 0.0 else 0.0,
			"boss": bool(e.get("boss", false)), "elite": bool(e.get("elite", false)), "structure": bool(e.get("structure", false)), "exposed": String(e.state) == "recover" or String(e.state) == "stagger" })
	for z in st.zones:
		out.zones.append({ "type": String(z.type), "x": float(z.x), "y": float(z.y), "r": float(z.r), "life": (float(z.ttl) / float(z.max_ttl)) if float(z.max_ttl) > 0.0 else 0.0,
			"order": int(z.get("order", 0)), "armed": bool(z.get("armed", true)), "tag": String(z.get("tag", "")), "shown_left": shown_zone_left(z) })
	for o in st.objects:
		out.objects.append({ "kind": String(o.get("kind", "")), "x": float(o.x), "y": float(o.y), "r": float(o.get("r", 0.0)), "done": bool(o.get("freed", false)) or bool(o.get("done", false)) })
	for k in st.pickups:
		if not bool(k.taken):
			out.pickups.append({ "kind": String(k.kind), "x": float(k.x), "y": float(k.y), "r": float(k.r) })
	for f in st.effects:
		var kind := String(f.kind)
		if kind == "spawnwarn" or kind == "pawwarn":
			out.spawn_warns.append({ "x": float(f.x), "y": float(f.y), "type": String(f.get("type", "")), "left": maxf(0.0, float(f.ttl) - float(f.t)) })
	if not st.field.is_empty():
		out.field = { "x": float(st.field.x), "y": float(st.field.y), "r": float(st.field.r), "ttl": float(st.field.ttl) }
	if not st.boss.is_empty():
		var bz: Dictionary = st.boss
		out.boss = { "id": int(bz.id), "boss_id": String(bz.get("boss_id", "boss")), "hp_frac": (float(bz.hp) / float(bz.hp_max)) if float(bz.hp_max) > 0.0 else 0.0, "phase": int(bz.get("phase", 1)), "state": String(bz.state), "dead": bool(bz.dead), "x": float(bz.x), "y": float(bz.y), "r": float(bz.r) }
	return out

## 조작 규칙(조작법 화면·HUD에 표시되는 값): 회피·이동 속도·자동기술 사거리
static func rules_of(st: CombatState) -> Dictionary:
	var P: Dictionary = st.cfg.player
	var D: Dictionary = P.dodge
	var rng_ := 0.0
	var orbit_only: bool = st.weapons.size() > 0
	for w in st.weapons:
		var s: Dictionary = w.stats
		var k := String(s.get("kind", ""))
		var rr: float = float(s.get("radius", 0.0)) if k == "orbit" else float(s.get("range", 0.0))
		if k != "orbit" and rr == 0.0:
			rr = 60.0
		rr = maxf(rr, 0.0)
		if rr > rng_:
			rng_ = rr
		if k != "orbit" and k != "mine":
			orbit_only = false
	return { "dodge_mode": String(D.mode), "dodge_distance": float(D.distance), "dodge_min": float(D.get("min_distance", D.distance)), "dodge_duration": float(D.duration), "dodge_cooldown": float(D.cooldown) * float(st.build.dodge_cd_mult),
		"speed": float(P.speed) * float(st.build.speed_mult), "weapon_range": (rng_ if rng_ > 0.0 else 80.0), "orbit_only": orbit_only, "q_cooldown": float(P.slowfield.cooldown) }

## 바닥 지역에 글자로 표시되는 남은 시간(거미줄 진행 호·서리 순번·제단 예고 진행). 숫자 초가 표시되는 것은 없으므로 -1
static func shown_zone_left(_z: Dictionary) -> float:
	return -1.0

## 발사자가 있는 투사체의 공격 부분 id("e<id>#<n>:proj<i>", 같은 공격의 몇 번째 투사체인지 counts로 센다). 발사자가 없으면 ""
static func _shooter_attack(pr: Dictionary, counts: Dictionary) -> String:
	var sh = pr.get("shooter")
	if sh == null or typeof(sh) != TYPE_DICTIONARY or not sh.has("id"):
		return ""
	var base := "e%d#%d" % [int(sh.id), int(sh.get("attack_n", 0))]
	var i: int = int(counts.get(base, 0))
	counts[base] = i + 1
	return "%s:proj%d" % [base, i]

static func _th(out: Array, e: Dictionary, sub: String, kind: String, phase: String, prog: float, d: Dictionary) -> Dictionary:
	var th := { "attack_id": "e%d#%d%s" % [int(e.id), int(e.get("attack_n", 0)), sub], "enemy_id": int(e.id), "type": String(e.type), "kind": kind, "phase": phase, "prog": clampf(prog, 0.0, 1.0),
		"x": float(e.x), "y": float(e.y), "ang": 0.0, "r": 0.0, "half": 0.0, "len": 0.0, "w": 0.0, "harm": "damage", "shown_left": -1.0, "rev": 0, "label": String(e.state) }
	for k in d:
		th[k] = d[k]
	out.append(th)
	return th

## 화면의 예고 도형(render.gd draw_telegraphs/draw_boss_telegraphs/draw_zones/draw_projectiles와 같은 수치). out에 위협 사전을 추가
static func threats_of(st: CombatState, out: Array) -> void:
	var p: Dictionary = st.player
	var pr_: float = float(p.r)
	for e in st.enemies:
		if bool(e.dead):
			continue
		var d: Dictionary = e.def
		var type := String(e.type)
		var stt := String(e.state)
		if bool(e.get("boss", false)):
			_boss_threats(st, e, out)
			continue
		if PEnemies.is_wolf(d):
			var B: Dictionary = d.bite
			var D: Dictionary = d.dash
			if stt == "bite_track" or stt == "bite_lock" or stt == "bite_hit":
				var ang: float = float(e.aim_angle) if stt == "bite_track" else float(e.dir)
				var ph := "warn" if stt == "bite_track" else ("lock" if stt == "bite_lock" else "active")
				_th(out, e, "", "sector", ph, float(e.state_t) / float(B.track) if stt == "bite_track" else 1.0, { "ang": ang, "r": float(B.reach), "half": float(B.arc_deg) * PI / 360.0, "label": "bite" })
			elif stt == "crouch" or stt == "lock" or stt == "dash":
				var ang2: float = float(e.aim_angle) if stt == "crouch" else float(e.dir)
				var L: float = float(D.dash_speed) * float(D.dash_time)
				var ph2 := "warn" if stt == "crouch" else ("lock" if stt == "lock" else "active")
				var need: float = float(D.get("second_crouch", D.crouch)) if int(e.get("dash_left", 1)) < int(D.get("dashes", 1)) else float(D.crouch)
				if stt == "dash": # 통로는 그려지지 않지만 달리는 몸과 방향은 보인다: 남은 거리만큼 외삽
					L = maxf(0.0, float(D.dash_speed) * (float(D.dash_time) - float(e.state_t)))
				_th(out, e, "", "corridor", ph2, (float(e.state_t) / need) if stt == "crouch" else 1.0, { "ang": ang2, "len": L, "w": (float(e.r) + pr_) * 2.0, "label": "dash" })
		elif type == "archer":
			if stt == "aim" or stt == "lock":
				_th(out, e, "", "lane", "warn" if stt == "aim" else "lock", (float(e.state_t) / float(d.aim)) if stt == "aim" else 1.0, { "ang": float(e.aim_angle) if stt == "aim" else float(e.dir), "len": ARCHER_LANE_LEN, "w": LANE_W, "label": "arrow" })
		elif type == "spore":
			if stt == "swell":
				_th(out, e, "", "circle", "warn", float(e.state_t) / float(d.swell), { "r": float(d.cloudR), "label": "spore" })
		elif type == "boar":
			if stt == "charge_aim":
				var pv: Dictionary = e.get("preview", {})
				var plen: float = float(pv["len"]) if not pv.is_empty() else float(d.chargeDist)
				_th(out, e, "", "corridor", "warn", float(e.state_t) / float(d.aim), { "ang": float(e.aim_angle), "len": plen, "w": (float(e.r) + pr_) * 2.0, "label": "charge" })
			elif stt == "charge_lock" or stt == "charge":
				var cl: float = float(e.get("charge_len", 0.0))
				if cl <= 0.0:
					cl = float(d.chargeDist)
				if stt == "charge":
					cl = maxf(0.0, cl - float(e.get("charge_dist", 0.0)))
				_th(out, e, "", "corridor", "lock" if stt == "charge_lock" else "active", 1.0, { "ang": float(e.dir), "len": cl, "w": (float(e.r) + pr_) * 2.0, "label": "charge" })
		elif type == "shieldbearer" and stt == "bash_aim":
			var k: float = float(e.state_t) / float(d.aim)
			_th(out, e, "", "sector", "lock" if k > 0.6 else "warn", k, { "ang": float(e.get("face", 0.0)), "r": float(d.bashRange) + float(d.lunge), "half": float(d.bashDeg) * PI / 360.0, "label": "bash" })
		elif type == "shaman" and stt == "hex_aim":
			var k2: float = float(e.state_t) / float(d.hexAim)
			_th(out, e, "", "lane", "lock" if k2 > 0.7 else "warn", k2, { "ang": float(e.aim_angle), "len": 600.0, "w": LANE_W, "label": "hex" })
		elif type == "bomber" and stt == "fuse":
			var fuse: float = float(d.fuse)
			_th(out, e, "", "circle", "lock", float(e.state_t) / fuse, { "r": float(d.blastR), "shown_left": maxf(0.0, fuse - float(e.state_t)), "label": "blast" })
		elif type == "burrower" and stt == "warn" and e.has("emerge_at"):
			var at: Array = e.emerge_at
			_th(out, e, "", "circle", "lock", float(e.state_t) / float(d.warn), { "x": float(at[0]), "y": float(at[1]), "r": float(d.emergeR), "label": "emerge" })
		if (type == "burrower" or type == "spider") and stt == "bite_aim":
			var k3: float = float(e.state_t) / float(d.biteAim)
			_th(out, e, "", "sector", "lock" if k3 > 0.6 else "warn", k3, { "ang": float(e.aim_angle), "r": float(d.biteRange) + float(e.r), "half": float(d.biteDeg) * PI / 360.0, "label": "bite" })
		if type == "spider" and stt == "web_aim" and e.has("web_at"):
			var wat: Array = e.web_at
			_th(out, e, "", "circle", "warn", float(e.state_t) / float(d.webAim), { "x": float(wat[0]), "y": float(wat[1]), "r": float(d.webR), "harm": "slow", "label": "web" })
		if type == "frostcaller" and stt == "cast" and e.has("cast_pts"):
			var pts: Array = e.cast_pts
			for i in pts.size():
				var pt: Array = pts[i]
				_th(out, e, ":pt%d" % i, "circle", "warn", float(e.state_t) / float(d.castAim), { "x": float(pt[0]), "y": float(pt[1]), "r": float(d.zoneR), "label": "frost%d" % (i + 1) })
		if type == "rogue" and (stt == "slash1_aim" or stt == "slash2_aim"):
			var first: bool = stt == "slash1_aim"
			var k4: float = float(e.state_t) / (float(d.aim1) if first else float(d.aim2))
			_th(out, e, ":s1" if first else ":s2", "sector", "lock" if k4 > 0.5 else "warn", k4, { "ang": float(e.aim_angle), "r": float(d.slashRange) + float(e.r), "half": float(d.slashDeg) * PI / 360.0, "label": "slash" })
	# 적 투사체: 위치·속도가 보이므로 진행 방향으로 제한적 외삽(직선 통로). 발사자가 보이면 그 공격 인스턴스의 부분(e<id>#<n>:proj<i>)
	var proj_n := {}
	for pr in st.projectiles:
		if String(pr.get("owner", "")) != "enemy" or bool(pr.get("dead", false)):
			continue
		var sa := _shooter_attack(pr, proj_n)
		var th := { "attack_id": sa if sa != "" else "proj:", "enemy_id": (int(pr.shooter.id) if sa != "" else -1), "type": String(pr.kind), "kind": "lane", "phase": "active", "prog": 1.0, "x": float(pr.x), "y": float(pr.y), "ang": atan2(float(pr.vy), float(pr.vx)), "r": 0.0, "half": 0.0,
			"len": PROJ_LOOK, "w": float(pr.get("width", float(pr.r) * 2.0)) + 4.0, "harm": "damage", "shown_left": -1.0, "rev": 0, "label": String(pr.kind) }
		out.append(th)
	# 바닥 지역: 포자 구름·제단/붕괴 위험(예고 중 포함)·서리 지역(순번·터지기 직전 붉은 테두리)·거미줄(걷기 50%)
	for z in st.zones:
		var zt := String(z.type)
		var zid := "zone:%s:%d:%d" % [zt, int(round(float(z.x))), int(round(float(z.y)))]
		if zt == "spore":
			out.append({ "attack_id": zid, "enemy_id": -1, "type": zt, "kind": "circle", "phase": "active", "prog": 1.0, "x": float(z.x), "y": float(z.y), "ang": 0.0, "r": float(z.r), "half": 0.0, "len": 0.0, "w": 0.0, "harm": "damage", "shown_left": -1.0, "rev": 0, "label": "spore" })
		elif zt == "hazard":
			var armed := bool(z.get("armed", false))
			var k5: float = minf(1.0, float(z.get("t", 0.0)) / maxf(0.001, float(z.get("warn", 1.0))))
			out.append({ "attack_id": zid, "enemy_id": -1, "type": zt, "kind": "circle", "phase": "active" if armed else ("lock" if k5 > 0.7 else "warn"), "prog": 1.0 if armed else k5, "x": float(z.x), "y": float(z.y), "ang": 0.0, "r": float(z.r), "half": 0.0, "len": 0.0, "w": 0.0, "harm": "damage", "shown_left": -1.0, "rev": 0, "label": "hazard" })
		elif zt == "frostzone":
			var life: float = (float(z.ttl) / float(z.max_ttl)) if float(z.max_ttl) > 0.0 else 0.0
			out.append({ "attack_id": zid, "enemy_id": -1, "type": zt, "kind": "circle", "phase": "lock" if float(z.ttl) < 0.45 else "warn", "prog": 1.0 - life, "x": float(z.x), "y": float(z.y), "ang": 0.0, "r": float(z.r), "half": 0.0, "len": 0.0, "w": 0.0, "harm": "damage", "shown_left": -1.0, "rev": 0, "label": "frost%d" % int(z.get("order", 0)) })
		elif zt == "web":
			out.append({ "attack_id": zid, "enemy_id": -1, "type": zt, "kind": "circle", "phase": "active", "prog": 1.0, "x": float(z.x), "y": float(z.y), "ang": 0.0, "r": float(z.r), "half": 0.0, "len": 0.0, "w": 0.0, "harm": "slow", "shown_left": -1.0, "rev": 0, "label": "web" })

static func _boss_threats(st: CombatState, bz: Dictionary, out: Array) -> void:
	var cfg := PBoss.cfg_of(bz)
	var stt := String(bz.state)
	var p: Dictionary = st.player
	var pr_: float = float(p.r)
	var st_t: float = float(bz.state_t)
	if (stt == "sweep_aim" or stt == "sweep_lock") and cfg.has("sweep"):
		var locked: bool = stt == "sweep_lock"
		_th(out, bz, "", "sector", "lock" if locked else "warn", 1.0 if locked else st_t / float(cfg.sweep.aim), { "ang": float(bz.dir) if locked else float(bz.aim_angle), "r": float(cfg.sweep.radius), "half": float(cfg.sweep.arcDeg) * PI / 360.0, "label": "sweep" })
	if (stt == "dash_aim" or stt == "dash_lock" or stt == "dash") and cfg.has("dash"):
		var locked2: bool = stt != "dash_aim"
		var ang: float = float(bz.dir) if locked2 else float(bz.aim_angle)
		var plen: float
		if locked2:
			plen = float(bz.get("dash_len", 0.0))
			if stt == "dash":
				plen = maxf(0.0, plen - float(bz.get("dash_dist", 0.0)))
		else:
			plen = float(PBoss.dash_path(st, bz, ang, float(cfg.dash.dist))["len"]) # 화면도 같은 dash_path로 통로 끝을 그린다
		var aim_t: float = float(cfg.dash.second.aim) if int(bz.get("dash_seq", 1)) == 2 else float(cfg.dash.aim)
		_th(out, bz, "", "corridor", "active" if stt == "dash" else ("lock" if locked2 else "warn"), 1.0 if locked2 else st_t / aim_t, { "ang": ang, "len": plen, "w": (float(bz.r) + pr_) * 2.0, "label": "dash" })
	var land: Dictionary = bz.get("land", {})
	if (stt == "pounce_aim" or stt == "pounce_lock" or stt == "leap") and not land.is_empty() and cfg.has("pounce"):
		_th(out, bz, "", "circle", "warn" if stt == "pounce_aim" else ("lock" if stt == "pounce_lock" else "active"), (st_t / float(cfg.pounce.aim)) if stt == "pounce_aim" else 1.0, { "x": float(land.x), "y": float(land.y), "r": float(cfg.pounce.radius), "label": "pounce" })
	if (stt == "shock_aim" or stt == "shock_lock") and cfg.has("shock"):
		var S: Dictionary = cfg.shock
		var locked3: bool = stt == "shock_lock"
		var ang3: float = float(bz.dir) if locked3 else float(bz.aim_angle)
		var k: float = 1.0 if locked3 else st_t / float(S.aim)
		if int(bz.get("shock_left", 0)) >= 2:
			_th(out, bz, ":shock0", "corridor", "lock" if locked3 else "warn", k, { "ang": ang3 - float(S.spread), "len": float(S.len), "w": float(S.width), "label": "shock" })
			_th(out, bz, ":shock1", "corridor", "lock" if locked3 else "warn", k, { "ang": ang3 + float(S.spread), "len": float(S.len), "w": float(S.width), "label": "shock" })
		else:
			_th(out, bz, "", "corridor", "lock" if locked3 else "warn", k, { "ang": ang3, "len": float(S.len), "w": float(S.width), "label": "shock" })
	if (stt == "lanes_warn" or stt == "lanes_lock" or stt == "lanes_fire") and cfg.has("lanes"):
		var L: Dictionary = cfg.lanes
		var lanes: Array = bz.get("lanes", [])
		for i in lanes.size():
			var ln: Dictionary = lanes[i]
			if bool(ln.get("fired", false)):
				continue
			var locked4: bool = stt != "lanes_warn" and i == int(bz.get("lane_idx", 0))
			_th(out, bz, ":lane%d" % i, "corridor", "lock" if locked4 else "warn", minf(1.0, st_t / float(L.warn)) if stt == "lanes_warn" else 1.0, { "ang": float(ln.ang), "len": float(L.len), "w": float(L.width), "label": "lane" })
	if cfg.has("mark"):
		var marks: Array = bz.get("marks", [])
		for i in marks.size():
			var mk: Dictionary = marks[i]
			if bool(mk.get("done", false)):
				continue
			var left: float = maxf(0.0, float(mk.explode_at) - st.t) # 화면에 남은 초가 글자로 표시된다
			_th(out, bz, ":mark%d" % i, "circle", "lock" if left < 0.4 else "warn", 1.0 - minf(1.0, left / maxf(0.001, float(cfg.mark.delay))), { "x": float(mk.x), "y": float(mk.y), "r": float(mk.r), "shown_left": left, "label": "mark" })
	if (stt == "wide_aim" or stt == "wide_lock") and cfg.has("wide"):
		var rad: Array = cfg.wide.radius
		var R: float = float(rad[mini(2, int(bz.get("phase", 1)) - 1)])
		_th(out, bz, "", "circle", "lock" if stt == "wide_lock" else "warn", (st_t / float(cfg.wide.aim)) if stt == "wide_aim" else 1.0, { "r": R, "label": "wide" })

# ---------- 기하(봇·계측 공용, 스냅샷만 읽는다) ----------
## 원(px,py,pr)이 위협 도형 안에 있는가. margin은 도형을 그만큼 키운다
static func inside(th: Dictionary, px: float, py: float, pr: float, margin: float = 0.0) -> bool:
	var k := String(th.kind)
	var x := float(th.x)
	var y := float(th.y)
	if k == "circle":
		return PGeom.dist(x, y, px, py) <= float(th.r) + pr + margin
	if k == "sector":
		return PGeom.in_arc(x, y, float(th.r) + margin, float(th.ang), float(th.half) + (margin / maxf(20.0, float(th.r))), px, py, pr)
	if k == "corridor" or k == "lane":
		return PGeom.in_beam(x, y, float(th.ang), float(th.len) + margin, float(th.w) + margin * 2.0, px, py, pr)
	return false

## 도형 경계까지의 대략 거리(안이면 0). 주의력 정렬용
static func dist_to(th: Dictionary, px: float, py: float, pr: float) -> float:
	if inside(th, px, py, pr):
		return 0.0
	var k := String(th.kind)
	var x := float(th.x)
	var y := float(th.y)
	var d := PGeom.dist(x, y, px, py)
	if k == "circle":
		return maxf(0.0, d - float(th.r) - pr)
	if k == "sector":
		var a := atan2(py - y, px - x)
		var da := absf(PGeom.ang_diff(float(th.ang), a))
		var radial := maxf(0.0, d - float(th.r) - pr)
		var tang := maxf(0.0, da - float(th.half)) * minf(d, float(th.r))
		return sqrt(radial * radial + tang * tang)
	var ca := cos(float(th.ang))
	var sa := sin(float(th.ang))
	var along := (px - x) * ca + (py - y) * sa
	var side := absf(-(px - x) * sa + (py - y) * ca)
	var dx := 0.0
	if along < 0.0:
		dx = -along
	elif along > float(th.len):
		dx = along - float(th.len)
	var dy := maxf(0.0, side - float(th.w) / 2.0 - pr)
	return sqrt(dx * dx + dy * dy)

## 스냅샷 지형: CombatState.valid_pos와 같은 규칙(경계·장애물 +2)
static func valid_pos(snap: Dictionary, x: float, y: float, r: float) -> bool:
	if x < r or x > float(snap.arena_w) - r or y < r or y > float(snap.arena_h) - r:
		return false
	for ob in snap.obstacles:
		if PGeom.dist(x, y, float(ob.x), float(ob.y)) < float(ob.r) + r + 2.0:
			return false
	return true

## 장애물을 돌아가는 방향(CombatState.steer_dir와 같은 접선 규칙, 조향 기억은 mem{steer_side, steer_t})
static func steer(snap: Dictionary, x: float, y: float, r: float, tx: float, ty: float, mem: Dictionary) -> Array:
	var dx := tx - x
	var dy := ty - y
	var dist := sqrt(dx * dx + dy * dy)
	if dist < 1e-6:
		return [0.0, 0.0]
	var d := [dx / dist, dy / dist]
	var blocker := {}
	var best_along := INF
	for ob in snap.obstacles:
		var R: float = float(ob.r) + r + 6.0
		var ox: float = float(ob.x) - x
		var oy: float = float(ob.y) - y
		var along: float = ox * d[0] + oy * d[1]
		if along <= 0.0 or along > minf(dist, 200.0) + R:
			continue
		var side: float = absf(-ox * d[1] + oy * d[0])
		if side < R and along < best_along:
			best_along = along
			blocker = ob
	if blocker.is_empty():
		mem.steer_side = 0
		return d
	var ox2: float = float(blocker.x) - x
	var oy2: float = float(blocker.y) - y
	var od := sqrt(ox2 * ox2 + oy2 * oy2)
	var R2: float = float(blocker.r) + r + 6.0
	var cross: float = d[0] * oy2 - d[1] * ox2
	if int(mem.get("steer_side", 0)) == 0 or float(mem.get("steer_t", 0.0)) <= 0.0:
		mem.steer_side = -1 if cross > 0.0 else 1
		mem.steer_t = 0.8
	var side_sign := float(mem.steer_side)
	if od <= R2 + 0.5:
		var nx := ox2 / od
		var ny := oy2 / od
		return [-ny * side_sign, nx * side_sign]
	var base := atan2(oy2, ox2)
	var off := asin(minf(1.0, R2 / od))
	var ang := base + off * side_sign
	return [cos(ang), sin(ang)]
