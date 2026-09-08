class_name PStats
extends RefCounted
## 런 누적 피해 통계(HTML stats.js 이식). 전투 정산 시 st.metrics(실제 체력 감소 기준, 과잉 피해 제외)를 출처별로 기록하고
## 출처별 유효 피해·비중·DPS(기술 보유 시간 기준)·분류별·보스 전용 보기를 만든다. 저장 파일에 남는다.
## 출처 키(docs/PORT_CONVENTIONS.md): weapon:<id> · dot:burn@<src> · dot:bleed@<src> · skill:q · skill:<e> · common:<id> · reward:<id> · other

const CATS := { "direct": "직접 공격", "projectile": "투사체", "ground": "바닥 지대", "dot": "지속 피해", "skill": "Q/E", "extra": "추가 효과" }

static func _r1(v: float) -> float: return round(v * 10.0) / 10.0

## 지속 피해 원천 이름: 무기 id → 무기 이름, 공용 증강 id → 증강 이름, 그 외 그대로
static func _src_name(src: String) -> String:
	if PCatalog.weapons().has(src):
		return String(PCatalog.weapons()[src].name)
	if PCatalog.commons().has(src):
		return String(PCatalog.commons()[src].name)
	return src

## 지속 피해 원천(dot:*@<src>)의 보유 시간 키(F4): 원천이 자동기술이면 weapon:<id>, E 기술이면 skill:<id>, Q면 skill:q, 공용 증강이면 common:<id>, 그 외("common"·"" 등)는 전투 시간 전체.
## 정책: DPS 분모 = 원천을 보유한 실제 전투 시간(획득~제거). 제거 뒤 남아 있던 지속 효과의 피해는 같은 분모에 포함한다(분모를 늘리지 않음). 획득 전 시간은 절대 포함하지 않는다.
static func _owner_key(src: String) -> String:
	if src == "":
		return ""
	if PCatalog.weapons().has(src):
		return "weapon:" + src
	if src == "q" or src == "slowfield":
		return "skill:q"
	if PCatalog.skills().has(src):
		return "skill:" + src
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
			return { "name": base + (("(" + _src_name(src) + ")") if src != "" else ""), "cat": "dot", "skill": _owner_key(src) }
		"skill":
			if id == "q" or id == "slowfield":
				return { "name": "감속장(Q)", "cat": "skill", "skill": "skill:q" }
			var SK := PCatalog.skills()
			return { "name": (String(SK[id].name) + "(E)") if SK.has(id) else id, "cat": "skill", "skill": key }
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
