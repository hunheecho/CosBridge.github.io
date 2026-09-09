class_name PStats
extends RefCounted
## 런 누적 피해 통계(HTML stats.js 이식). 전투 정산 시 st.metrics(실제 체력 감소 기준, 과잉 피해 제외)를 출처별로 기록하고
## 출처별 유효 피해·비중·DPS(기술 보유 시간 기준)·분류별·보스 전용 보기를 만든다. 저장 파일에 남는다.
## 출처 키(docs/PORT_CONVENTIONS.md): weapon:<id> · dot:burn@<src> · dot:bleed@<src> · skill:q(감속장) · skill:<기술 id> · common:<id> · reward:<id> · other
##
## 수동 기술 키는 **슬롯이 아니라 기술 id**로 정한다(2026-09-10 §7: Q와 E가 같은 6종을 공유한다).
## 감속장만 예전 기록과 같은 "skill:q"를 그대로 쓴다 — 옛 저장의 통계가 이름을 잃지 않게 하기 위해서다.

const CATS := { "direct": "직접 공격", "projectile": "투사체", "ground": "바닥 지대", "dot": "지속 피해", "skill": "Q/E", "extra": "추가 효과" }

## 수동 기술 id → 통계·보유 시간 키. 감속장은 옛 기록과 같은 "skill:q"(슬롯이 아니라 이름표다)
static func skill_key(id: String) -> String:
	return "skill:q" if id == "slowfield" or id == "q" else "skill:" + id

static func _r1(v: float) -> float: return round(v * 10.0) / 10.0

## 지속 피해 원천 이름: 무기 id → 무기 이름, 공용 증강 id → 증강 이름, 그 외 그대로
static func _src_name(src: String) -> String:
	if PCatalog.weapons().has(src):
		return String(PCatalog.weapons()[src].name)
	if PCatalog.commons().has(src):
		return String(PCatalog.commons()[src].name)
	return src

## 출처 키 규약의 **정본**(§15). 원천 id(자동기술·기술·공용 증강) → 통계가 쓰는 owner 키.
## 자동기술이면 weapon:<id>, E 기술이면 skill:<id>, Q면 skill:q, 공용 증강이면 common:<id>, 모르는 것은 ""(= 전투 시간 전체).
## **화면은 절대 "weapon:" 같은 접두사를 손으로 붙이지 않는다** — 그렇게 짜깁기한 곳이 대장간 피해 비중이었고
## `String(g.owner) == "orb"` 비교가 늘 거짓이라 기여도가 항상 0%로 나왔다. 규약이 바뀌면 이 함수 하나만 바뀐다.
## 같은 id가 자동기술이면서 공용 증강이기도 하면(frost·ember) **자동기술이 이긴다** — 옛 규약 그대로 둔다(기록 호환).
## 정책: DPS 분모 = 원천을 보유한 실제 전투 시간(획득~제거). 제거 뒤 남아 있던 지속 효과의 피해는 같은 분모에 포함한다(분모를 늘리지 않음). 획득 전 시간은 절대 포함하지 않는다.
static func owner_key(src: String) -> String:
	if src == "":
		return ""
	if PCatalog.weapons().has(src):
		return "weapon:" + src
	if src == "q" or src == "slowfield":
		return "skill:q"
	if PCatalog.skills().has(src):
		return skill_key(src)
	if PCatalog.commons().has(src):
		return "common:" + src
	return ""

## 출처 키 → {name, cat, skill}. skill은 보유 시간(activeT) 키("" = 전투 시간 전체). 저장 기록에 activeT 키가 없는 옛 전투 기록은 전투 시간 전체로 계산한다
static func classify(key: String) -> Dictionary:
	var sep := key.find(":")
	var kind := key.substr(0, sep) if sep >= 0 else key
	var id := key.substr(sep + 1) if sep >= 0 else ""
	match kind:
		"weapon":
			var W := PCatalog.weapons()
			var d: Dictionary = W[id] if W.has(id) else {}
			return { "name": String(d.get("name", id)), "cat": String(d.get("category", "direct")), "skill": key }
		"dot":
			var at := id.find("@")
			var dk := id.substr(0, at) if at >= 0 else id
			var src := id.substr(at + 1) if at >= 0 else ""
			var base := "화상" if dk == "burn" else ("출혈" if dk == "bleed" else dk)
			return { "name": base + (("(" + _src_name(src) + ")") if src != "" else ""), "cat": "dot", "skill": owner_key(src) }
		"skill":
			# 이름에 슬롯을 붙이지 않는다: 같은 기술이 Q에도 E에도 올 수 있다(§7)
			if id == "q" or id == "slowfield":
				return { "name": "감속장", "cat": "skill", "skill": "skill:q" }
			var SK := PCatalog.skills()
			return { "name": String(SK[id].name) if SK.has(id) else id, "cat": "skill", "skill": key }
		"common":
			var CM := PCatalog.commons()
			return { "name": String(CM[id].name) if CM.has(id) else id, "cat": "extra", "skill": key }
		"reward":
			var BR := PCatalog.boss_rewards()
			return { "name": String(BR[id].name) if BR.has(id) else id, "cat": "extra", "skill": key }
	return { "name": "기타" if key == "other" else key, "cat": "extra", "skill": "" }

## 정산 1회: 같은 전투를 두 번 기록하지 않는다(st.stats_recorded). meta = {kind, regionId|bossId, day, won?}
static func record(run: Dictionary, st: CombatState, meta: Dictionary = {}) -> Dictionary:
	if st == null or st.stats_recorded:
		return {}
	st.stats_recorded = true
	if run.get("dmgStats", null) == null:
		run.dmgStats = { "combats": [], "byKey": {} }
	var dmg := {}
	var total := 0.0
	for k in st.metrics.dmg:
		dmg[String(k)] = _r1(float(st.metrics.dmg[k]))
		total += float(st.metrics.dmg[k])
	var boss_dmg: float = _r1(float(st.stats.boss_damage)) if not st.boss.is_empty() else 0.0
	var active := {}
	for k in st.active_t:
		active[String(k)] = float(st.active_t[k])
	var rec := { "elapsed": round(st.t * 100.0) / 100.0, "dmg": dmg, "total": _r1(total), "bossDamage": boss_dmg,
		"taken": _r1(float(st.stats.damage_taken)), "takenNominal": _r1(float(st.stats.damage_taken_nominal)),
		"absorbed": _r1(float(st.stats.absorbed)), "healed": _r1(float(st.stats.healed)), # 보호막 흡수·회복·실제 체력 손실을 분리해 기록(지시 15)
		"mods": st.mod_report(), # 개조별 이번 전투 발동/적중/피해(지시 12·15). 값이 없는 개조는 들어 있지 않다
		"kills": int(st.stats.kills), "activeT": active, "status": st.status, "won": st.status == "won" }
	for k in meta:
		rec[k] = meta[k]
	(run.dmgStats.combats as Array).append(rec)
	return rec

## 집계: filter(rec) -> bool (null이면 전부) → { rows[{key,name,cat,amount,share,active,dps}], total, elapsed, taken, takenNominal, cats{}, n, dpsAll }
static func aggregate(run: Dictionary, filter: Variant = null) -> Dictionary:
	var list := []
	for r in run.get("dmgStats", {}).get("combats", []):
		if filter == null or bool((filter as Callable).call(r)):
			list.append(r)
	var sum := {}
	var act := {}
	var total := 0.0
	var elapsed := 0.0
	var taken := 0.0
	var taken_nom := 0.0
	var absorbed := 0.0
	var healed := 0.0
	var mods := {}
	for r in list:
		elapsed += float(r.elapsed)
		absorbed += float(r.get("absorbed", 0.0))
		healed += float(r.get("healed", 0.0))
		for mid in r.get("mods", {}):
			var m: Dictionary = r.mods[mid]
			if not mods.has(mid):
				mods[mid] = { "procs": 0, "hits": 0, "damage": 0.0 }
			var acc: Dictionary = mods[mid]
			acc.procs = int(acc.procs) + int(m.get("procs", 0))
			acc.hits = int(acc.hits) + int(m.get("hits", 0))
			acc.damage = float(acc.damage) + float(m.get("damage", 0.0))
		taken += float(r.taken)
		taken_nom += float(r.get("takenNominal", r.taken))
		for k in r.dmg:
			sum[k] = float(sum.get(k, 0.0)) + float(r.dmg[k])
			total += float(r.dmg[k])
		for k in r.get("activeT", {}):
			act[k] = float(act.get(k, 0.0)) + float(r.activeT[k])
	var rows := []
	for k in sum:
		var c := classify(String(k))
		var active: float = float(act[c.skill]) if (String(c.skill) != "" and act.has(c.skill)) else elapsed
		rows.append({ "key": String(k), "name": String(c.name), "cat": String(c.cat), "owner": String(c.skill), "amount": _r1(float(sum[k])), "share": (round(float(sum[k]) / total * 1000.0) / 10.0) if total > 0.0 else 0.0,
			"active": _r1(active), "dps": _r1(float(sum[k]) / active) if active > 0.0 else 0.0 })
	rows.sort_custom(func(a, b): return float(a.amount) > float(b.amount))
	var cats := {}
	for r in rows:
		cats[r.cat] = _r1(float(cats.get(r.cat, 0.0)) + float(r.amount))
	for mid in mods:
		mods[mid].damage = _r1(float(mods[mid].damage))
	return { "rows": rows, "total": _r1(total), "elapsed": _r1(elapsed), "taken": _r1(taken), "takenNominal": _r1(taken_nom), "absorbed": _r1(absorbed), "healed": _r1(healed), "mods": mods, "cats": cats, "n": list.size(), "dpsAll": _r1(total / elapsed) if elapsed > 0.0 else 0.0 }

## 기술별 묶음(F4): owner(weapon:<id>·skill:<id>·common:<id>)마다 직접 + 파생(지속 피해) 합과 보유 시간 기준 DPS. owner가 없는 행은 "other"
static func by_owner(agg: Dictionary) -> Array:
	var groups := {}
	for r in agg.rows:
		var o: String = String(r.get("owner", "")) if String(r.get("owner", "")) != "" else "other"
		if not groups.has(o):
			groups[o] = { "owner": o, "amount": 0.0, "direct": 0.0, "derived": 0.0, "active": float(r.active), "rows": [] }
		var g: Dictionary = groups[o]
		g.amount += float(r.amount)
		if String(r.key) == o:
			g.direct += float(r.amount)
		else:
			g.derived += float(r.amount)
		(g.rows as Array).append(String(r.key))
	var out := []
	for o in groups:
		var g: Dictionary = groups[o]
		g.amount = _r1(float(g.amount))
		g.direct = _r1(float(g.direct))
		g.derived = _r1(float(g.derived))
		g.dps = _r1(float(g.amount) / float(g.active)) if float(g.active) > 0.0 else 0.0
		out.append(g)
	out.sort_custom(func(a, b): return float(a.amount) > float(b.amount))
	return out

## owner 키 하나의 묶음(by_owner 결과 중 하나). 없으면 {} — "기록이 아예 없다"와 "피해가 0이다"를 부르는 쪽이 구분할 수 있게 한다
static func owner_group(agg: Dictionary, owner: String) -> Dictionary:
	if owner == "":
		return {}
	for g in by_owner(agg):
		if String(g.owner) == owner:
			return g
	return {}

## 화면용 한 묶음(§15): 원천 하나(자동기술 id 등)가 **이 회차 전체 기록**에서 낸 유효 피해와 비중.
## 대장간과 통계 화면이 **같은 범위**(필터 없는 aggregate = 통계 화면의 '런 전체')를 보게 하려고 여기서 한 번에 만든다.
## amount = 직접(키가 owner와 같은 행) + 파생(그 기술에 귀속된 지속 피해·개조 등) — by_owner의 기존 합산 정책 그대로다.
## state 는 **세 가지 서로 다른 사정**을 갈라 준다(문구를 섞지 않기 위해서다):
##   "no_record" 정산된 전투 기록 자체가 없다      "no_metric" 전투는 있는데 출처별 피해가 하나도 안 남았다(계측 누락)
##   "zero"      기록은 있는데 이 원천의 피해가 0   "ok"        실제 비중이 있다
static func owner_share(run: Dictionary, src: String) -> Dictionary:
	var agg := aggregate(run)
	var owner := owner_key(src)
	var g := owner_group(agg, owner)
	var total := float(agg.total)
	var amount := float(g.get("amount", 0.0))
	var state := "ok"
	if int(agg.n) <= 0:
		state = "no_record"
	elif total <= 0.0:
		state = "no_metric"
	elif amount <= 0.0:
		state = "zero"
	return { "owner": owner, "state": state, "n": int(agg.n), "total": _r1(total), "amount": _r1(amount),
		"direct": _r1(float(g.get("direct", 0.0))), "derived": _r1(float(g.get("derived", 0.0))),
		"share": (round(amount / total * 1000.0) / 10.0) if total > 0.0 else 0.0 }

## 보기: 전체 / 보스전(성공) / 보스전(실패한 도전) / 일반 출격 / 최근 전투(지시 15)
static func views(run: Dictionary) -> Dictionary:
	var combats: Array = run.get("dmgStats", {}).get("combats", [])
	var last_i: int = combats.size() - 1
	return {
		"all": aggregate(run),
		"boss": aggregate(run, func(r): return String(r.get("kind", "")) == "boss" and bool(r.won)),
		"bossFailed": aggregate(run, func(r): return String(r.get("kind", "")) == "boss" and not bool(r.won)),
		"sortie": aggregate(run, func(r): return String(r.get("kind", "")) != "boss"),
		"recent": aggregate(run, func(r): return combats.find(r) == last_i),
	}

## 보스별 보기(지시 15): bossId → 집계. 처치 기록이 있는 보스만
static func boss_views(run: Dictionary) -> Dictionary:
	var out := {}
	for r in run.get("dmgStats", {}).get("combats", []):
		var bid := String(r.get("bossId", ""))
		if String(r.get("kind", "")) != "boss" or bid == "":
			continue
		if out.has(bid):
			continue
		out[bid] = aggregate(run, func(x): return String(x.get("bossId", "")) == bid)
	return out

## 개조별 이번 런 발동/적중/피해(지시 12). 표시용 — 값이 없는 개조는 넣지 않는다(0으로 미발동처럼 보이지 않게)
static func mod_rows(agg: Dictionary) -> Array:
	var out := []
	var M: Dictionary = agg.get("mods", {})
	for mid in M:
		var m: Dictionary = M[mid]
		out.append({ "id": String(mid), "procs": int(m.procs), "hits": int(m.hits), "damage": float(m.damage) })
	out.sort_custom(func(a, b): return float(a.damage) > float(b.damage))
	return out

## 검증: 출처 합 = 총합, 분류 합 = 총합(반올림 오차 허용). [{view, ok, total, rowSum, catSum}]
static func verify(run: Dictionary) -> Array:
	var out := []
	var V := views(run)
	for name in V:
		var a: Dictionary = V[name]
		var row_sum := 0.0
		for r in a.rows:
			row_sum += float(r.amount)
		var cat_sum := 0.0
		for c in a.cats:
			cat_sum += float(a.cats[c])
		var tol: float = 0.5 * maxf(1.0, float((a.rows as Array).size()))
		out.append({ "view": String(name), "ok": absf(row_sum - float(a.total)) <= tol and absf(cat_sum - float(a.total)) <= tol, "total": float(a.total), "rowSum": _r1(row_sum), "catSum": _r1(cat_sum) })
	return out
