class_name PSupportB
extends RefCounted
## 보조무기 B조: ⑩ 역병 나비 · ⑪ 가시 갑각 · ⑫ 도깨비 인형.
## 공통 규칙(발동 자격표·제압 저항·경감 순서)은 PSupport에 있고 여기서는 그것만 쓴다.
## 수치는 data/supports.json에 있고 전부 **시험값**이다 — 여기 숫자를 적지 않는다.
##
## 이 파일이 지키는 규칙(자세한 설명은 docs/SUPPORT_B.md):
##  1. 재귀 증식 금지. 시간이 아니라 **경로**로 가른다.
##     - 독 전염: PSupport.eligible("plague_spread", 경로) + 세대 상한 PSupport.gen_max("plague_spread").
##       전염은 지속 시간을 최대치로 되돌리지 않고 **죽은 개체의 남은 시간을 물려받는다**.
##     - 가시 반격: PSupport.eligible("thorns_reflect", 경로). 반사가 반사를 부르지 못하게 재진입까지 막는다.
##  2. 피해 출처를 보존한다. 이 조가 주는 모든 피해는 _hit() 한 곳을 지나며
##     독(support:plague:poison) · 전염(support:plague:spread) · 파열(support:plague:burst) ·
##     반격(support:thorns:reflect) · 독가시(support:thorns:venom) · 인형 폭발(support:doll:blast)로 따로 기록된다.
##  3. 인형은 강제 이동·끌어당기기를 하지 않는다. 유인은 "그 적이 노릴 대상"을 바꾸는 것뿐이고
##     이미 방향이 확정된 공격·돌진(st.is_committed)은 절대 바꾸지 않는다.
##  4. 남은 인형·독은 소유 보조가 사라지거나 전투가 끝나면 무료 중복 효과가 되지 않게 정리한다.

const KINDS := ["plague", "thorns", "doll"]

# ---------- 적 공격의 경로 이름(자격표 어휘) ----------
## 반사 자신(순환 금지). combat_state.damage_player의 src 문자열로 들어온다
const REFLECT_SRC := ["reflect", "support:thorns:reflect"]
## 장판·폭발(가시 반격 없음)
const ZONE_SRC := ["zone", "frostzone", "hazard", "blast", "elite_spore",
	"boss_rubble", "boss_ring", "boss_rockfall", "boss_icepath", "boss_mark"]
## 적 투사체(가시 반격 없음). 투사체는 pr.kind가 그대로 src가 된다
const PROJ_SRC := ["arrow", "hex", "shock", "boss_bolt", "boss_icebolt", "boss_spore_shot"]

## 독 정산 기본 간격(초). data에 tick이 없을 때만 쓰는 되돌림 값
const TICK_FALLBACK := 0.5

static func handles(kind: String) -> bool:
	return KINDS.has(kind)

# ---------- 상태 보관 ----------
## st.support 안의 이 조 전용 칸. A조(까마귀·방울·분신·바람)와 키가 겹치지 않는다
static func _slot(st: CombatState, key: String, init: Dictionary) -> Dictionary:
	if not st.support.has(key):
		st.support[key] = init
	var d: Dictionary = st.support[key]
	return d

static func plague_stat(st: CombatState) -> Dictionary:
	return _slot(st, "plague", { "applied": 0, "spreads": 0, "bursts": 0, "max_gen": 0, "spread_blocked": 0,
		"dmg": { "poison": 0.0, "spread": 0.0, "burst": 0.0, "venom": 0.0 } })

static func thorns_stat(st: CombatState) -> Dictionary:
	return _slot(st, "thorns", { "cd": 0.0, "busy": false, "cuts": 0, "reduced": 0.0,
		"reflects": 0, "reflect_hits": 0, "skipped_path": 0, "skipped_cd": 0, "skipped_blocked": 0,
		"dmg": { "reflect": 0.0 } })

static func doll_stat(st: CombatState) -> Dictionary:
	return _slot(st, "doll", { "placed": 0, "lured": 0, "absorbed": 0, "absorbed_dmg": 0.0,
		"blasts": 0, "expired": 0, "broken": 0, "no_room": 0, "dmg": { "blast": 0.0 } })

## 지금 살아 있는 인형. 없거나 자격을 잃었으면 {}
## (보조를 바꿨거나 전투가 끝났으면 인형은 없는 것으로 본다 — 남은 인형이 공짜로 계속 일하지 않게)
static func doll_of(st: CombatState) -> Dictionary:
	if not st.support.has("doll_obj"):
		return {}
	var d: Dictionary = st.support["doll_obj"]
	if d.is_empty() or bool(d.get("gone", false)):
		return {}
	if st.status != "running" or not PSupport.equipped(st, "doll"):
		return {}
	return d

## 이 조가 주는 피해 배율(무기 base.damage를 쓰지 않는 보조라 여기서 공용 증강을 곱한다).
## 레벨업 강화는 data/supports.json levelScale이 이미 w.stats에 넣어 두었다
static func _dmg_scale(st: CombatState, wid: String) -> float:
	return float(st.build.get("damage_mult", 1.0)) * PBuild.forge_mult_of(st.build, wid)

## 이 조의 모든 피해가 지나는 한 곳. 출처(tag)·경로(cause)·개조 귀속을 함께 남긴다.
## o = { wid, tag, cause, row(집계 칸), stat(집계 dict), mod, knock, dir }
static func _hit(st: CombatState, e: Dictionary, amount: float, o: Dictionary) -> float:
	if e.dead or amount <= 0.0:
		return 0.0
	var src := { "weapon_id": String(o.wid), "direct": false, "extra": true, "tag": String(o.tag) }
	if String(o.get("mod", "")) != "":
		src["mod"] = String(o.mod)
	var opt := { "src": src, "cause": String(o.cause), "knock": float(o.get("knock", 0.0)), "dir": o.get("dir", []) }
	var dealt: float = st.damage_enemy(e, amount, opt)
	var row := String(o.get("row", ""))
	if row != "":
		var stat: Dictionary = o.stat
		var box: Dictionary = stat.dmg
		box[row] = float(box.get(row, 0.0)) + dealt
	return dealt

# ---------- 1. 발사 ----------
static func fire(st: CombatState, w: Dictionary, target: Dictionary, _echoed: bool) -> bool:
	match String(w.stats.kind):
		"plague":
			return _fire_plague(st, w, target)
		"thorns":
			return true # 수동 보조라 발사가 없다(base.range = 0이라 평소에는 여기까지 오지도 않는다)
		"doll":
			return _fire_doll(st, w, target)
	return false

# ---------- 2. 갱신 ----------
static func update(st: CombatState, dt: float) -> void:
	_tick_plague(st, dt)
	var T := thorns_stat(st)
	if float(T.cd) > 0.0:
		T.cd = maxf(0.0, float(T.cd) - dt)
	_tick_doll(st, dt)

# ---------- 3. 전투 훅 ----------
## 순서: (1) 차단 — 도깨비 인형이 자리로 막아 대신 맞는다 → (2) 경감 — 가시 갑각 근접 경감.
## 차단이 먼저다. 0을 돌려주면 완전히 막힌 것이고 뒤 계산(강인함·장비·보호막)도, 가시 반격도 하지 않는다
static func on_player_damage(st: CombatState, amount: float, src: String, attacker) -> float:
	var cause := hit_cause(st, src, attacker)
	var v := _doll_intercept(st, amount, cause, attacker)
	if v <= 0.0:
		return 0.0
	if cause == "enemy_melee" and PSupport.equipped(st, "thorns"):
		var s := PSupport.stats_of(st, "thorns")
		var cut: float = clampf(float(s.get("reduce", 0.0)), 0.0, float(s.get("reduceCap", 0.4)))
		var after: float = round(v * (1.0 - cut) * 10.0) / 10.0
		var T := thorns_stat(st)
		T.cuts = int(T.cuts) + 1
		T.reduced = float(T.reduced) + (v - after)
		v = after
	return v

## 실제로 피해가 들어간 뒤. 막힌 공격(amount 0)에는 반격하지 않는다
static func after_player_damage(st: CombatState, amount: float, src: String, attacker) -> void:
	if not PSupport.equipped(st, "thorns"):
		return
	var T := thorns_stat(st)
	if amount <= 0.0:
		T.skipped_blocked = int(T.skipped_blocked) + 1
		return
	if bool(T.busy):
		return # 반사가 반사를 부르는 순환 금지(자격표와 별개로 재진입까지 막는다)
	var cause := hit_cause(st, src, attacker)
	if not PSupport.eligible("thorns_reflect", cause):
		T.skipped_path = int(T.skipped_path) + 1
		return
	if float(T.cd) > 0.0:
		T.skipped_cd = int(T.skipped_cd) + 1
		return
	var s := PSupport.stats_of(st, "thorns")
	if s.is_empty():
		return
	T.cd = float(s.get("cooldown", 0.6))
	T.busy = true
	_reflect(st, s, attacker)
	T.busy = false

static func on_enemy_hit(_st: CombatState, _e: Dictionary, _opt: Dictionary, _dmg: float) -> void:
	pass

## 죽음이 방아쇠인 효과: 역병 파열 → 독 전염 순서로 정산한다(같은 죽음으로 두 번 터지지 않는다)
static func on_enemy_death(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	var pg: Dictionary = e.get("plague", {})
	if pg.is_empty() or bool(pg.get("done", false)):
		return
	pg.done = true      # 같은 죽음으로 두 번 정산하지 않는다
	e["plague"] = {}    # 죽은 개체의 독은 여기서 끝난다
	var P := plague_stat(st)
	var burst_frac := 0.0
	# (1) 역병 파열: 남은 독 피해의 일부를 즉시 방출
	if bool(pg.get("burst", false)) and PSupport.equipped(st, "plague"):
		var remain: float = maxf(0.0, float(pg.t)) * float(pg.dps)
		var amount: float = remain * float(pg.get("burst_frac", 0.0))
		if amount > 0.0:
			burst_frac = float(pg.get("burst_frac", 0.0))
			P.bursts = int(P.bursts) + 1
			st.note_mod("burst", "proc")
			st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": float(pg.burst_r), "ttl": 0.3, "color": "#8ee06a" })
			for o in st.alive_targets():
				if o == e or o.dead:
					continue
				if PGeom.dist(o.x, o.y, e.x, e.y) > float(pg.burst_r) + float(o.r):
					continue
				if st.los_blocked(e.x, e.y, o.x, o.y):
					continue
				_hit(st, o, amount, { "wid": "plague", "tag": "support:plague:burst", "cause": "plague_burst",
					"row": "burst", "stat": P, "mod": "burst", "dir": PGeom.norm(o.x - e.x, o.y - e.y) })
	# (2) 독 전염
	if not bool(pg.get("spread", true)):
		return # 독가시가 묻힌 독은 전염 자격이 없다(설계 확정)
	if not PSupport.equipped(st, "plague"):
		return
	if not PSupport.eligible("plague_spread", _death_cause(st, opt)):
		P.spread_blocked = int(P.spread_blocked) + 1
		return
	var gmax := PSupport.gen_max("plague_spread")
	var gen: int = int(pg.gen) + 1
	if gmax >= 0 and gen > gmax:
		P.spread_blocked = int(P.spread_blocked) + 1
		return
	# 남은 시간을 물려받는다(최대치로 되돌리지 않는다). 파열로 터뜨린 몫은 빼고 넘긴다
	var inherit: float = maxf(0.0, float(pg.t)) * (1.0 - burst_frac)
	if inherit <= 0.01:
		return
	var cands := []
	for o in st.alive_targets():
		if o == e or o.dead or bool(o.get("structure", false)):
			continue
		if PGeom.dist(o.x, o.y, e.x, e.y) > float(pg.spread_r) + float(o.r):
			continue
		if st.los_blocked(e.x, e.y, o.x, o.y):
			continue
		cands.append(o)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := PGeom.dist(a.x, a.y, e.x, e.y)
		var db := PGeom.dist(b.x, b.y, e.x, e.y)
		if is_equal_approx(da, db):
			return int(a.id) < int(b.id)
		return da < db)
	var n: int = mini(int(pg.spread_n), cands.size())
	if n <= 0:
		return
	st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": float(pg.spread_r), "ttl": 0.25, "color": "#a6e05a" })
	for i in n:
		var o: Dictionary = cands[i]
		_infect(st, o, gen, inherit)
		P.spreads = int(P.spreads) + 1

## 이 적이 지금 노려야 할 대상(도깨비 인형 유인). {}이면 평소대로 플레이어를 노린다.
## **이미 방향이 확정된 공격·돌진은 여기서 바뀌지 않는다** — 확정 상태면 무조건 {}를 돌려준다
static func lure_target(st: CombatState, e: Dictionary) -> Dictionary:
	var d := doll_of(st)
	if d.is_empty():
		return {}
	if e.dead or not (d.lured as Dictionary).has(e.id):
		return {}
	if st.is_committed(e):
		return {}
	return { "x": float(d.x), "y": float(d.y), "r": float(d.r), "doll": true }

# ---------- ⑩ 역병 나비 ----------
static func _fire_plague(st: CombatState, w: Dictionary, target: Dictionary) -> bool:
	var s: Dictionary = w.stats
	var p := st.player
	var dist := PGeom.dist(p.x, p.y, target.x, target.y)
	var fly: float = clampf(dist / maxf(1.0, float(s.speed)), 0.05, 1.5)
	st.fx({ "kind": "burst", "x": p.x, "y": p.y, "r": 14.0, "ttl": 0.2, "color": "#a6e05a" })
	var tg: Dictionary = target
	PWeapons.later(st, fly, func() -> void:
		if tg.dead or bool(tg.get("hidden", false)) or not PSupport.equipped(st, "plague"):
			return
		st.fx({ "kind": "burst", "x": tg.x, "y": tg.y, "r": 16.0, "ttl": 0.25, "color": "#a6e05a" })
		_infect(st, tg, 0, -1.0))
	st.ev("shoot")
	return true

## 독을 건다. gen=0은 나비가 직접 붙인 것(새 출처라 세대를 0으로 되돌린다),
## gen>=1은 전염이며 inherit_t(죽은 개체의 남은 시간)를 물려받는다
static func _infect(st: CombatState, e: Dictionary, gen: int, inherit_t: float) -> void:
	var s := PSupport.stats_of(st, "plague")
	if s.is_empty() or e.dead:
		return
	var mods: Array = s.mods
	var wide: bool = mods.has("wide")
	var deep: bool = mods.has("deep")
	var dps: float = float(s.dps) * _dmg_scale(st, "plague")
	if wide:
		dps *= float(s.get("wideDps", 1.0))
	if deep:
		dps *= float(s.get("deepDps", 1.0))
	var dur: float = float(s.dur) * float(st.build.get("duration_mult", 1.0)) * float(st.build.get("trait_dot_dur", 1.0))
	var targets: int = int(s.spreadMax)
	if wide:
		targets += int(s.get("wideMaxAdd", 0))
	if deep:
		targets = mini(targets, int(s.get("deepMaxCap", 1)))
	var r: float = float(s.spread)
	if wide:
		r = float(s.get("wideSpread", r))
	if deep:
		r = float(s.get("deepSpread", r))
	var mod_id := ""
	if wide:
		mod_id = "wide"
	elif deep:
		mod_id = "deep"
	if gen > 0 and mod_id != "":
		st.note_mod(mod_id, "proc")
	_apply_poison(st, e, {
		"dps": dps, "t": (dur if inherit_t < 0.0 else inherit_t), "max": dur, "gap": float(s.get("tick", TICK_FALLBACK)),
		"gen": gen, "reset_gen": gen == 0, "spread": true, "spread_r": r, "spread_n": targets,
		"burst": mods.has("burst"), "burst_frac": float(s.get("burstFrac", 0.0)), "burst_r": float(s.get("burstR", 0.0)),
		"tag": ("support:plague:poison" if gen == 0 else "support:plague:spread"),
		"row": ("poison" if gen == 0 else "spread"), "mod": mod_id,
	})

## 독 부여 공통. 더 강한 독(dps가 큰 쪽)이 이기고, 같으면 남은 시간만 늘린다.
## 어느 쪽이든 **최대 지속을 넘지 않는다** — 전염이 지속 시간을 무한히 늘리지 못하게 하는 곳이다
static func _apply_poison(st: CombatState, e: Dictionary, po: Dictionary) -> void:
	if e.dead or bool(e.get("structure", false)):
		return
	var t_new: float = minf(float(po.t), float(po.max))
	if t_new <= 0.0:
		return
	var cur: Dictionary = e.get("plague", {})
	var out: Dictionary
	if cur.is_empty() or float(po.dps) > float(cur.dps) + 1e-6:
		out = po.duplicate(true)
		out["t"] = minf(maxf(float(cur.get("t", 0.0)), t_new), float(po.max))
		out["tick"] = float(cur.get("tick", float(po.gap)))
		out["done"] = false
		if not bool(po.get("reset_gen", false)) and not cur.is_empty():
			out["gen"] = maxi(int(cur.get("gen", 0)), int(po.gen))
		e["plague"] = out
	else:
		out = cur
		out["t"] = minf(maxf(float(cur.t), t_new), float(cur.max))
		if bool(po.get("reset_gen", false)):
			out["gen"] = int(po.gen)
		else:
			out["gen"] = maxi(int(cur.get("gen", 0)), int(po.gen))
	var P := plague_stat(st)
	P.applied = int(P.applied) + 1
	P.max_gen = maxi(int(P.max_gen), int(out.gen))
	st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": 10.0, "ttl": 0.18, "color": "#a6e05a" })

## 독 정산. 화상·출혈과 같은 방식(0.5초 간격, 지속 특성 배율 적용)이지만 출처는 따로 남긴다
static func _tick_plague(st: CombatState, dt: float) -> void:
	var P := plague_stat(st)
	var mult: float = float(st.build.get("trait_dot_mult", 1.0))
	for e in st.alive_targets():
		if e.dead:
			continue
		var pg: Dictionary = e.get("plague", {})
		if pg.is_empty():
			continue
		pg.t = float(pg.t) - dt
		pg.tick = float(pg.get("tick", 0.0)) - dt
		if float(pg.tick) <= 0.0:
			var gap: float = float(pg.get("gap", TICK_FALLBACK))
			pg.tick = gap
			_hit(st, e, float(pg.dps) * gap * mult, { "wid": String(pg.get("wid", "plague")), "tag": String(pg.tag),
				"cause": "dot", "row": String(pg.row), "stat": P, "mod": String(pg.get("mod", "")) })
		if e.dead:
			continue
		if float(pg.t) <= 0.0:
			e["plague"] = {}

# ---------- ⑪ 가시 갑각 ----------
## 적 공격이 어느 경로로 왔는가. 자격표 어휘(enemy_melee / enemy_projectile / enemy_zone / reflect)로 바꾼다.
## 알려진 목록으로 먼저 가르고, 모르는 출처는 **실제로 가시가 닿는 거리 안인지**로 판정한다
## — 모르는 원거리 공격을 근접으로 오인해 반격이 새지 않게 한다
static func hit_cause(st: CombatState, src: String, attacker) -> String:
	if REFLECT_SRC.has(src):
		return "reflect"
	if ZONE_SRC.has(src):
		return "enemy_zone"
	if PROJ_SRC.has(src):
		return "enemy_projectile"
	if attacker == null:
		return "enemy_zone"
	var att: Dictionary = attacker
	var p := st.player
	var reach := 95.0
	var s := PSupport.stats_of(st, "thorns")
	if not s.is_empty():
		reach = float(s.get("thornRange", reach))
	if PGeom.dist(p.x, p.y, float(att.x), float(att.y)) <= float(att.get("r", 0.0)) + float(p.r) + reach:
		return "enemy_melee"
	return "enemy_projectile"

## 가시 반격. 기본은 때린 방향의 좁은 부채꼴, '집중 가시'는 더 좁고 강하게, '가시 폭발'은 주변 원형
static func _reflect(st: CombatState, s: Dictionary, attacker) -> void:
	var p := st.player
	var ang := 0.0
	if attacker != null:
		var att: Dictionary = attacker
		ang = atan2(float(att.y) - p.y, float(att.x) - p.x)
	var mods: Array = s.mods
	var mult := 1.0
	var half: float = float(s.get("thornDeg", 60.0)) * PI / 360.0
	var reach: float = float(s.get("thornRange", 95.0))
	var circle := false
	var mod_id := ""
	if mods.has("focused"):
		mult = float(s.get("focusedMult", 1.0))
		half = float(s.get("focusedDeg", 20.0)) * PI / 360.0
		mod_id = "focused"
	elif mods.has("burst"):
		mult = float(s.get("burstMult", 1.0))
		reach = float(s.get("burstR", reach))
		circle = true
		mod_id = "burst"
	var dmg: float = float(s.thorn) * mult * _dmg_scale(st, "thorns")
	var T := thorns_stat(st)
	T.reflects = int(T.reflects) + 1
	if mod_id != "":
		st.note_mod(mod_id, "proc")
	if circle:
		st.fx({ "kind": "burst", "x": p.x, "y": p.y, "r": reach, "ttl": 0.22, "color": "#cfd6a0" })
	else:
		st.fx({ "kind": "arc", "x": p.x, "y": p.y, "angle": ang, "r": reach, "half": half, "ttl": 0.14 })
	var venom: bool = mods.has("venom")
	for e in st.alive_targets():
		if e.dead:
			continue
		var inside := false
		if circle:
			inside = PGeom.dist(p.x, p.y, e.x, e.y) <= reach + float(e.r)
		else:
			inside = PGeom.in_arc(p.x, p.y, reach, ang, half, e.x, e.y, float(e.r))
		if not inside or st.los_blocked(p.x, p.y, e.x, e.y):
			continue
		_hit(st, e, dmg, { "wid": "thorns", "tag": "support:thorns:reflect", "cause": "reflect",
			"row": "reflect", "stat": T, "mod": mod_id, "dir": PGeom.norm(e.x - p.x, e.y - p.y) })
		T.reflect_hits = int(T.reflect_hits) + 1
		if venom and not e.dead:
			_venom(st, e, s)

## 독가시: 반격 가시에 독을 묻힌다. **역병 나비의 전염·파열 자격이 없다**(spread=false)
static func _venom(st: CombatState, e: Dictionary, s: Dictionary) -> void:
	st.note_mod("venom", "proc")
	var dur: float = float(s.get("venomDur", 3.0)) * float(st.build.get("duration_mult", 1.0)) * float(st.build.get("trait_dot_dur", 1.0))
	_apply_poison(st, e, {
		"dps": float(s.get("venomDps", 0.0)) * _dmg_scale(st, "thorns"), "t": dur, "max": dur,
		"gap": TICK_FALLBACK, "gen": 0, "reset_gen": false, "spread": false, "spread_r": 0.0, "spread_n": 0,
		"burst": false, "burst_frac": 0.0, "burst_r": 0.0,
		"tag": "support:thorns:venom", "row": "venom", "mod": "venom", "wid": "thorns",
	})

# ---------- ⑫ 도깨비 인형 ----------
static func _fire_doll(st: CombatState, w: Dictionary, target: Dictionary) -> bool:
	if not doll_of(st).is_empty():
		return true # 동시에 하나만 유지한다. 이번 주기는 건너뛰고 다음 주기에 다시 시도
	var s: Dictionary = w.stats
	var p := st.player
	var D := doll_stat(st)
	var ang := 0.0
	if not target.is_empty():
		ang = atan2(target.y - p.y, target.x - p.x) # 적 쪽에 세워야 미끼가 된다
	var want_x: float = p.x + cos(ang) * float(s.place)
	var want_y: float = p.y + sin(ang) * float(s.place)
	var rr: float = float(s.get("dollR", 26.0))
	var pos := st.nearest_valid_pos(want_x, want_y, rr, 90.0)
	if pos.is_empty():
		D.no_room = int(D.no_room) + 1
		return true # 유효한 자리가 없으면 세우지 않는다(벽 안에 밀어 넣지 않는다)
	var mods: Array = s.mods
	var hp: float = float(s.hp)
	var ttl: float = float(s.dur) * float(st.build.get("duration_mult", 1.0))
	if mods.has("tough"):
		hp *= float(s.get("toughHp", 1.0))
		ttl *= float(s.get("toughDur", 1.0))
		st.note_mod("tough", "proc")
	st.support["doll_obj"] = {
		"x": float(pos[0]), "y": float(pos[1]), "r": rr, "hp": hp, "hp_max": hp,
		"ttl": ttl, "t": 0.0, "gone": false, "lured": {}, "done": {}, "hits": 0,
	}
	D.placed = int(D.placed) + 1
	st.fx({ "kind": "burst", "x": float(pos[0]), "y": float(pos[1]), "r": rr, "ttl": 0.3, "color": "#ffd166" })
	st.text(float(pos[0]), float(pos[1]) - rr - 18.0, "도깨비 인형", "#ffd166")
	st.ev("shoot")
	return true

static func _tick_doll(st: CombatState, dt: float) -> void:
	if not st.support.has("doll_obj"):
		return
	var d: Dictionary = st.support["doll_obj"]
	if d.is_empty() or bool(d.get("gone", false)):
		return
	# 보조를 바꿨거나 전투가 끝나면 **폭발 없이** 사라진다(무료 중복 효과 금지)
	if st.status != "running" or not PSupport.equipped(st, "doll"):
		d.gone = true
		st.support.erase("doll_obj")
		return
	var s := PSupport.stats_of(st, "doll")
	d.t = float(d.t) + dt
	d.ttl = float(d.ttl) - dt
	_lure_update(st, d, s, dt)
	if (s.mods as Array).has("fleeing") and (d.lured as Dictionary).size() > 0:
		_doll_flee(st, d, s, dt)
	if float(d.ttl) <= 0.0:
		var D := doll_stat(st)
		D.expired = int(D.expired) + 1
		_doll_end(st, d, s, "expire")

## 유인 명단 갱신. 강제 이동은 없다 — 명단에 오른 적이 '노릴 대상'만 바뀐다(PSupportB.lure_target).
## 등급 유인 저항(resist.taunt)은 확률이 아니라 **붙잡아 두는 시간**으로 쓴다: 정예는 절반, 보스는 0(=아예 안 걸린다)
static func _lure_update(st: CombatState, d: Dictionary, s: Dictionary, dt: float) -> void:
	var lured: Dictionary = d.lured
	var done: Dictionary = d.done
	var drop := []
	for id in lured:
		lured[id] = float(lured[id]) - dt
		if float(lured[id]) <= 0.0:
			drop.append(id)
	for id in drop:
		lured.erase(id)
		done[id] = true # 한 인형이 같은 적을 계속 붙잡아 두지 않는다
	var cap: int = int(s.get("maxLure", 0))
	if lured.size() >= cap:
		return
	var reach: float = float(s.get("range", 0.0))
	var hold: float = float(s.get("lureHold", 0.0))
	var cands := []
	for e in st.alive_targets():
		if e.dead or bool(e.get("structure", false)):
			continue
		if lured.has(e.id) or done.has(e.id):
			continue
		if not PSupport.tauntable(e):
			continue # 보스는 유인 저항 0이라 절대 끌리지 않는다
		if st.is_committed(e):
			continue # 이미 시작된 공격·돌진의 확정 방향을 인형 생성으로 바꾸지 않는다
		if PGeom.dist(e.x, e.y, float(d.x), float(d.y)) > reach + float(e.r):
			continue
		if st.los_blocked(float(d.x), float(d.y), e.x, e.y):
			continue
		cands.append(e)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := PGeom.dist(a.x, a.y, float(d.x), float(d.y))
		var db := PGeom.dist(b.x, b.y, float(d.x), float(d.y))
		if is_equal_approx(da, db):
			return int(a.id) < int(b.id)
		return da < db)
	var D := doll_stat(st)
	for e in cands:
		if lured.size() >= cap:
			break
		lured[e.id] = hold * PSupport.resist_mult("taunt", e)
		D.lured = int(D.lured) + 1

## 도망치는 인형: 플레이어에게서 멀어지는 **유효한** 방향으로만 움직인다(벽·장애물 안으로 들어가지 않는다)
static func _doll_flee(st: CombatState, d: Dictionary, s: Dictionary, dt: float) -> void:
	var p := st.player
	var n := PGeom.norm(float(d.x) - p.x, float(d.y) - p.y)
	var base := atan2(n[1], n[0])
	var step: float = float(s.get("fleeSpeed", 0.0)) * dt
	if step <= 0.0:
		return
	for off in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var a: float = base + float(off)
		var nx: float = float(d.x) + cos(a) * step
		var ny: float = float(d.y) + sin(a) * step
		if st.valid_pos(nx, ny, float(d.r)):
			d.x = nx
			d.y = ny
			return

## 인형이 대신 맞는다. 조건은 **위치**다. 유인 명단에 오른 적의 근접 공격이고 둘 중 하나일 때만:
##   (가) 그 적이 인형의 접촉 범위 안에 있다 — 인형 옆에서 인형을 때리고 있는 상태.
##   (나) 인형이 그 적과 플레이어를 잇는 선 위, 그것도 적 쪽에 서 있다 — 몸으로 막는 상태.
## 순간 이동·끌어당기기가 아니라 자리로 막는 것이라 이미 확정된 공격도 인형이 대신 맞을 수 있다
static func _doll_intercept(st: CombatState, amount: float, cause: String, attacker) -> float:
	if cause != "enemy_melee" or attacker == null:
		return amount
	var d := doll_of(st)
	if d.is_empty():
		return amount
	var att: Dictionary = attacker
	if not (d.lured as Dictionary).has(att.id):
		return amount
	var p := st.player
	var s := PSupport.stats_of(st, "doll")
	var contact: float = float(d.r) + float(att.get("r", 0.0)) + float(s.get("contact", 0.0))
	var near: bool = PGeom.dist(float(att.x), float(att.y), float(d.x), float(d.y)) <= contact
	var online: bool = PGeom.dist_seg(float(d.x), float(d.y), float(att.x), float(att.y), p.x, p.y) <= float(d.r) \
		and PGeom.dist(float(att.x), float(att.y), float(d.x), float(d.y)) <= PGeom.dist(float(att.x), float(att.y), p.x, p.y)
	if not near and not online:
		return amount
	var D := doll_stat(st)
	D.absorbed = int(D.absorbed) + 1
	D.absorbed_dmg = float(D.absorbed_dmg) + amount
	d.hits = int(d.hits) + 1
	d.hp = float(d.hp) - amount
	st.fx({ "kind": "burst", "x": float(d.x), "y": float(d.y), "r": float(d.r), "ttl": 0.2, "color": "#ffd166" })
	if float(d.hp) <= 0.0:
		D.broken = int(D.broken) + 1
		_doll_end(st, d, PSupport.stats_of(st, "doll"), "broken")
	return 0.0

## 인형 소멸. '폭죽 인형'이면 짧은 예고 뒤에 터진다(예고 없이 즉발하지 않는다)
static func _doll_end(st: CombatState, d: Dictionary, s: Dictionary, why: String) -> void:
	if bool(d.get("gone", false)):
		return
	d.gone = true
	st.support.erase("doll_obj")
	st.fx({ "kind": "death", "x": float(d.x), "y": float(d.y), "r": float(d.r), "ttl": 0.35, "color": "#ffd166" })
	if s.is_empty() or not (s.mods as Array).has("firework"):
		return
	if why != "broken" and why != "expire":
		return
	var bx: float = float(d.x)
	var by: float = float(d.y)
	var br: float = float(s.get("blastR", 0.0))
	var bd: float = float(s.get("blastDmg", 0.0)) * _dmg_scale(st, "doll")
	var warn: float = float(s.get("blastWarn", 0.4))
	st.note_mod("firework", "proc")
	st.fx({ "kind": "strikewarn", "x": bx, "y": by, "r": br, "ttl": warn }) # 예고(무해한 표시)
	st.text(bx, by - 24.0, "폭죽!", "#ffd166")
	PWeapons.later(st, warn, func() -> void:
		if st.status != "running":
			return
		var D := doll_stat(st)
		D.blasts = int(D.blasts) + 1
		st.fx({ "kind": "impact", "x": bx, "y": by, "r": br, "ttl": 0.3 })
		st.ev("explode")
		for e in st.alive_targets():
			if e.dead or PGeom.dist(e.x, e.y, bx, by) > br + float(e.r):
				continue
			if st.los_blocked(bx, by, e.x, e.y):
				continue
			_hit(st, e, bd, { "wid": "doll", "tag": "support:doll:blast", "cause": "doll_blast",
				"row": "blast", "stat": D, "mod": "firework", "knock": 30.0, "dir": PGeom.norm(e.x - bx, e.y - by) }))

# ---------- 도우미 ----------
## 죽음을 만든 피해가 어느 경로였는가(전염 자격 판정용). 판단은 PSupport.cause_of 한 곳에서만 한다
static func _death_cause(st: CombatState, opt: Dictionary) -> String:
	var o := {}
	var sr: Dictionary = opt.get("src", {})
	if opt.has("cause"):
		o["cause"] = String(opt.cause)
	if sr.has("weapon_id"):
		o["weapon"] = String(sr.weapon_id)
	return PSupport.cause_of(st, o)
