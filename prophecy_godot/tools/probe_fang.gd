extends SceneTree
## 조사 전용(임시): 피의 송곳니(elite_fang)의 패턴이 실제로 보이는가.
##   godot --headless --path prophecy_godot -s tools/probe_fang.gd
## 규칙·수치를 하나도 바꾸지 않는다.
##
## ㉠/㉡/㉢을 가르려고 정예 개체마다 다음을 잰다(실제 출격 편성 · 1·2·3막):
##  - 등장 → 첫 예고(_aim 진입)까지, 등장 → 첫 **고유** 패턴까지, 등장 → 죽을 때까지
##  - 패턴(상태)별 진입 횟수와 그때의 체력 %
##  - **화면에 예고가 떠 있던 총 시간**(_aim·_lock·guard·swell·warn 상태에 머문 시간 합)
##    = scripts/game/render.gd draw_elite의 telling 조건과 같은 상태 집합
##  - 죽기 전에 고유 패턴을 한 번이라도 보여 줬는가

const STEP := 1.0 / 120.0
const MAX_SEC := 200.0
const SEEDS := [1, 2, 3]
const POLICY := "balanced"
const PICKS_BY_DAY := { 2: 4, 5: 12, 9: 22 }
const DAY_OF_ACT := { 1: 2, 2: 5, 3: 9 }

## 그 정예의 '고유 패턴' = 도감·설명이 그 적을 설명할 때 쓰는 동작(다른 적에게 없는 것).
## elite_fang은 도약이다("측면으로 돌아 물기 → 이탈 → 도약"의 마지막). 물기는 늑대·도적도 한다.
const SIGNATURE := {
	"elite_archer": ["fan_aim"],
	"elite_blademaster": ["dash1_aim", "guard"],
	"elite_fang": ["leap_aim"],
	"elite_plaguecaller": ["throw_aim"],
	"elite_chainbreaker": ["chain_aim"],
	"elite_standard": ["plant_aim"],
	"elite_miner": ["dive"],
}
## 첫 예고로 치는 상태(무엇이든 예고가 뜬 순간)
func is_tel(s: String) -> bool:
	return s.ends_with("_aim") or s.ends_with("_lock") or s == "guard" or s == "swell" or s == "warn"

func grow(run: Dictionary, picks: int) -> void:
	var g: Dictionary = run.growth
	var used := 0
	var guard := 0
	var blocked := {}
	while used < picks and guard < 200:
		guard += 1
		var c := {}
		var ws: Array = g.weapons
		var lo: Dictionary = ws[0]
		for i in mini(2, ws.size()):
			if int(ws[i].level) < int(lo.level):
				lo = ws[i]
		var wid := String(lo.id)
		var w := PGrowth.weapon_of(g, wid)
		if (w.mods as Array).size() < PGrowth.mod_quota(int(w.level)):
			for mid in (PCatalog.weapon(wid).get("mods", {}) as Dictionary):
				if bool(PCatalog.weapon(wid).mods[mid].get("impl", false)) and not (w.mods as Array).has(String(mid)):
					c = { "kind": "weapon_mod", "id": wid, "mod": String(mid) }
					break
		if c.is_empty() and int(lo.level) < 5:
			c = { "kind": "weapon_level", "id": wid }
		if c.is_empty() and ws.size() < 2:
			c = { "kind": "weapon_new", "id": "spear" }
		if c.is_empty():
			for cid in PCatalog.commons():
				var cd: Dictionary = PCatalog.commons()[cid]
				var cl: int = int(g.commons.get(cid, 0))
				if bool(cd.impl) and cl < int(cd.max) and (cl > 0 or (g.commons as Dictionary).size() < 3):
					c = { "kind": "common", "id": String(cid) }
					break
		if c.is_empty():
			for pid in PCatalog.passives():
				var pd: Dictionary = PCatalog.passives()[pid]
				var pl: int = int(g.passives.get(pid, 0))
				if pl < int(pd.max) and (pl > 0 or (g.passives as Dictionary).size() < 4):
					c = { "kind": "passive", "id": String(pid) }
					break
		if c.is_empty() or blocked.has(JSON.stringify(c)):
			break
		if PGrowth.apply_choice(run, c):
			used += 1
		else:
			blocked[JSON.stringify(c)] = true
	run.hp = float(PRun.build(run).hp_max)

func make_run(seed_v: int, act: int, theme_id: String) -> Dictionary:
	var route := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)]
	route[act - 1] = theme_id
	var run := PRun.new_run(seed_v, "sword", "", { "route": route })
	var day := int(DAY_OF_ACT[act])
	run.day = day
	run.stage = act - 1
	grow(run, int(PICKS_BY_DAY.get(day, 4)))
	return run

func encounter(run: Dictionary, place_id: String, formation_id: String, seed_v: int) -> CombatState:
	var sortie := { "regionId": place_id, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 },
		"encounters": 0, "seed": int(run.seed) * 131 + seed_v * 17 + int(run.day), "day": int(run.day),
		"slot": 0, "variant": null, "formationId": formation_id }
	return CombatState.new(PFlow.encounter_opts(run, sortie))

## 실제 편성 한 판. 정예 개체별 기록을 돌려준다
func run_once(run: Dictionary, place_id: String, formation_id: String, seed_v: int) -> Array:
	var st := encounter(run, place_id, formation_id, seed_v)
	var bot := PBot.new(POLICY)
	var track := []
	var n := 0
	while st.status == "running" and n < int(MAX_SEC / STEP):
		st.step(bot.step_input(st), STEP)
		n += 1
		for e in st.enemies:
			if not PEnemiesNew.is_elite(String(e.type)):
				continue
			if not e.has("_p_i"):
				e["_p_i"] = track.size()
				track.append({ "e": e, "type": String(e.type), "last": String(e.state), "spawn_t": float(st.t),
					"death_t": -1.0, "first_tel": -1.0, "first_sig": -1.0, "sig_hp": -1.0,
					"states": {}, "tel_sec": 0.0, "hp_at": {}, "crowd": [] })
		# 이 단계에 예고를 띄우고 있는 적의 수(정예·일반 모두). '내 예고가 다른 예고에 묻히는가'의 분모다
		var tel_now := 0
		for e in st.enemies:
			if bool(e.dead) or bool(e.get("structure", false)):
				continue
			if PEnemiesNew.is_committed(e):
				tel_now += 1
		for r in track:
			var e: Dictionary = r.e
			if bool(e.dead):
				if float(r.death_t) < 0.0:
					r.death_t = float(st.t)
				continue
			var s := String(e.state)
			if is_tel(s):
				r.tel_sec = float(r.tel_sec) + STEP
				(r.crowd as Array).append(float(tel_now - 1))
			if s != String(r.last):
				(r.states as Dictionary)[s] = int((r.states as Dictionary).get(s, 0)) + 1
				var hp_pct: float = 100.0 * float(e.hp) / maxf(1.0, float(e.hp_max))
				if not (r.hp_at as Dictionary).has(s):
					(r.hp_at as Dictionary)[s] = hp_pct
				if is_tel(s) and float(r.first_tel) < 0.0:
					r.first_tel = float(st.t) - float(r.spawn_t)
				if (SIGNATURE.get(String(r.type), []) as Array).has(s) and float(r.first_sig) < 0.0:
					r.first_sig = float(st.t) - float(r.spawn_t)
					r.sig_hp = hp_pct
				r.last = s
	var out := []
	for r in track:
		var e: Dictionary = r.e
		out.append({ "type": String(r.type), "hp0": float(e.hp_max),
			"ttk": (float(r.death_t) - float(r.spawn_t)) if float(r.death_t) >= 0.0 else -1.0,
			"first_tel": float(r.first_tel), "first_sig": float(r.first_sig), "sig_hp": float(r.sig_hp),
			"tel_sec": float(r.tel_sec), "states": (r.states as Dictionary).duplicate(),
			"hp_at": (r.hp_at as Dictionary).duplicate(),
			"crowd": avg(r.crowd),
			"executed": int(e.get("executed", 0)), "alive_end": not bool(e.dead),
			"fight_sec": float(st.t), "fight_status": String(st.status) })
	return out

func avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

func fmt(v: float, unit: String = "초") -> String:
	return "—" if v < 0.0 else "%.1f%s" % [v, unit]

# ---------- 배치표(data/themes.json 그대로) ----------
func slots_all() -> Array:
	var out := []
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		var places: Array = t.places
		for kind in ["normal", "risk"]:
			for f in (t.formations[kind] as Array):
				if int(f.get("elites", 0)) <= 0:
					continue
				out.append({ "act": int(t.act), "theme": String(tid), "place": String(places[0].id),
					"place_name": String(places[0].name), "formation": String(f.id), "formation_name": String(f.name),
					"kind": String(kind), "types": PRun.elite_types_for(f, "p1", false),
					"comp": f.get("comp", []) })
	return out

func _init() -> void:
	var md := []
	md.append("# 조사: 피의 송곳니와 특수 정예 7종 — 패턴이 보이는가")
	md.append("")
	md.append("생성 `tools/probe_fang.gd` · 봇 `%s` · 시드 %s · 단계 %0.4f초 · 상한 %d초. **규칙·수치를 바꾸지 않았다.**" % [POLICY, str(SEEDS), STEP, int(MAX_SEC)])
	md.append("편성·체력·수는 data/themes.json·data/pacing.json 그대로. **봇 승패는 판정이 아니다.**")
	md.append("")

	# ---------- 1. 자료에 적힌 예고 창 ----------
	md.append("## 1. 자료에 적힌 예고 창(data/enemies.json)")
	md.append("")
	md.append("| 정예 | 이동 속도 | 예고 시간(초) | 가장 짧은 예고 |")
	md.append("|---|---:|---|---:|")
	var aim_keys := ["aim", "reaim", "fanAim", "aim1", "aim2", "slamAim", "biteAim", "leapAim", "throwAim", "burstAim",
		"chainAim", "sweepAim", "plantAim", "slashAim", "warn", "dive"]
	for tp in PEnemiesNew.ELITE_TYPES:
		var d: Dictionary = PCatalog.enemy(String(tp))
		var parts := []
		var mn := 99.0
		for k in aim_keys:
			if d.has(k):
				parts.append("%s %.2f" % [String(k), float(d[k])])
				mn = minf(mn, float(d[k]))
		md.append("| %s | %.0f | %s | **%.2f** |" % [String(d.name), float(d.speed), " · ".join(parts), mn])
	md.append("")

	# ---------- 2. 실제 편성 측정 ----------
	md.append("## 2. 실제 편성 안에서 — 등장부터 무엇이 언제 보이는가")
	md.append("")
	md.append("| 막 | 편성 | 정예 | 체력 | 처치까지 | 첫 예고까지 | **첫 고유 패턴까지** | 그때 체력 | 예고가 떠 있던 총 시간 | 실행한 공격 | 죽기 전 고유 패턴 |")
	md.append("|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|")
	var by_type := {}
	for sl in slots_all():
		for sd in SEEDS:
			var run := make_run(int(sd), int(sl.act), String(sl.theme))
			var recs := run_once(run, String(sl.place), String(sl.formation), int(sd))
			for r in recs:
				var key := "%d|%s|%s" % [int(sl.act), String(sl.formation), String(r.type)]
				if not by_type.has(key):
					by_type[key] = { "act": int(sl.act), "formation_name": String(sl.formation_name), "type": String(r.type),
						"hp0": float(r.hp0), "ttk": [], "first_tel": [], "first_sig": [], "sig_hp": [], "tel_sec": [],
						"crowd": [], "exec": [], "no_sig": 0, "n": 0, "states": {} }
				var B: Dictionary = by_type[key]
				B.n = int(B.n) + 1
				B.hp0 = float(r.hp0)
				if float(r.ttk) >= 0.0:
					(B.ttk as Array).append(float(r.ttk))
				if float(r.first_tel) >= 0.0:
					(B.first_tel as Array).append(float(r.first_tel))
				if float(r.first_sig) >= 0.0:
					(B.first_sig as Array).append(float(r.first_sig))
					(B.sig_hp as Array).append(float(r.sig_hp))
				else:
					B.no_sig = int(B.no_sig) + 1
				(B.tel_sec as Array).append(float(r.tel_sec))
				(B.crowd as Array).append(float(r.crowd))
				(B.exec as Array).append(float(r.executed))
				for s in (r.states as Dictionary):
					(B.states as Dictionary)[s] = int((B.states as Dictionary).get(s, 0)) + int(r.states[s])
	for key in by_type:
		var B: Dictionary = by_type[key]
		md.append("| %d | %s | %s | %.0f | %s | %s | **%s** | %s | %s | %.1f | %d/%d 회 못 보여 줌 |" % [
			int(B.act), String(B.formation_name), String(PCatalog.enemy(String(B.type)).name), float(B.hp0),
			fmt(avg(B.ttk) if not (B.ttk as Array).is_empty() else -1.0),
			fmt(avg(B.first_tel) if not (B.first_tel as Array).is_empty() else -1.0),
			fmt(avg(B.first_sig) if not (B.first_sig as Array).is_empty() else -1.0),
			("—" if (B.sig_hp as Array).is_empty() else "%.0f%%" % avg(B.sig_hp)),
			fmt(avg(B.tel_sec)), avg(B.exec), int(B.no_sig), int(B.n)])
	md.append("")

	# ---------- 3. 정예별 요약(막을 합쳐서) ----------
	md.append("## 3. 정예별 요약 — '유독 안 보이는 것'이 송곳니뿐인가")
	md.append("")
	md.append("| 정예 | 개체 수 | 처치까지(평균) | 첫 고유 패턴까지 | 고유 패턴을 못 보여 준 비율 | **예고가 떠 있던 총 시간** | 그 비율(처치 시간 대비) | **예고 1회가 떠 있는 평균 길이** | 그때 함께 떠 있던 다른 예고(평균) | 상태 진입 횟수 |")
	md.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")
	var agg := {}
	for key in by_type:
		var B: Dictionary = by_type[key]
		var tp := String(B.type)
		if not agg.has(tp):
			agg[tp] = { "n": 0, "no_sig": 0, "ttk": [], "sig": [], "tel": [], "crowd": [], "states": {} }
		var A: Dictionary = agg[tp]
		A.n = int(A.n) + int(B.n)
		A.no_sig = int(A.no_sig) + int(B.no_sig)
		(A.ttk as Array).append_array(B.ttk)
		(A.sig as Array).append_array(B.first_sig)
		(A.tel as Array).append_array(B.tel_sec)
		(A.crowd as Array).append_array(B.crowd)
		for s in (B.states as Dictionary):
			(A.states as Dictionary)[s] = int((A.states as Dictionary).get(s, 0)) + int(B.states[s])
	for tp in PEnemiesNew.ELITE_TYPES:
		if not agg.has(String(tp)):
			continue
		var A: Dictionary = agg[String(tp)]
		var stn := []
		for s in (A.states as Dictionary):
			stn.append("%s %d" % [String(s), int(A.states[s])])
		stn.sort()
		var ttk_avg: float = avg(A.ttk) if not (A.ttk as Array).is_empty() else -1.0
		var tel_entries := 0
		for s2 in (A.states as Dictionary):
			if is_tel(String(s2)):
				tel_entries += int(A.states[s2])
		var per_tel: float = (avg(A.tel) * float(A.n)) / maxf(1.0, float(tel_entries))
		md.append("| %s | %d | %s | %s | %d/%d | **%s** | %s | **%.2f초** | %.1f | %s |" % [
			String(PCatalog.enemy(String(tp)).name), int(A.n),
			fmt(ttk_avg),
			fmt(avg(A.sig) if not (A.sig as Array).is_empty() else -1.0),
			int(A.no_sig), int(A.n), fmt(avg(A.tel)),
			("—" if ttk_avg <= 0.0 else "%.0f%%" % (100.0 * avg(A.tel) / ttk_avg)),
			per_tel, avg(A.crowd), " · ".join(stn)])
	md.append("")

	# ---------- 4. 송곳니가 서 있는 자리(주변 적과의 구분) ----------
	md.append("## 4. 송곳니가 나오는 편성의 이웃 — 구분이 되는가")
	md.append("")
	md.append("| 막 | 편성 | 함께 나오는 일반 적(비중) | 그 적들이 하는 것 |")
	md.append("|---:|---|---|---|")
	for sl in slots_all():
		if not (sl.types as Array).has("elite_fang"):
			continue
		var parts := []
		for c in (sl.comp as Array):
			parts.append("%s %.0f%%" % [String(PCatalog.enemy(String(c.type)).name), 100.0 * float(c.share)])
		var roles := []
		for c in (sl.comp as Array):
			roles.append("%s: %s" % [String(PCatalog.enemy(String(c.type)).name), String(PCatalog.enemy(String(c.type)).get("role", "?"))])
		md.append("| %d | %s | %s | %s |" % [int(sl.act), String(sl.formation_name), " · ".join(parts), " · ".join(roles)])
	md.append("")
	md.append("| 비교 항목 | 피의 송곳니 | 늑대 | 쌍날 도적 |")
	md.append("|---|---|---|---|")
	var fg: Dictionary = PCatalog.enemy("elite_fang")
	var wo: Dictionary = PCatalog.enemy("wolf")
	var ro: Dictionary = PCatalog.enemy("rogue")
	md.append("| 색 | `%s` | `%s` | `%s` |" % [String(fg.color), String(wo.color), String(ro.color)])
	md.append("| 판정 반지름 | %.0f | %.0f | %.0f |" % [float(fg.r), float(wo.r), float(ro.r)])
	md.append("| 이동 속도 | %.0f | %.0f | %.0f |" % [float(fg.speed), float(wo.speed), float(ro.speed)])
	md.append("| 측면으로 도는가 | flankDist %.0f / offset %.0f | 아니오(정면 돌진) | flankDist %.0f / offset %.0f |" % [
		float(fg.flankDist), float(fg.flankOffset), float(ro.flankDist), float(ro.flankOffset)])
	md.append("| 근접 물기 예고 | %.2f초 · %.0f° | %.2f초(물기 track) · %.0f° | %.2f초 · %.0f° |" % [
		float(fg.biteAim), float(fg.biteDeg), float((wo.bite as Dictionary).track), float((wo.bite as Dictionary).arc_deg),
		float(ro.aim1), float(ro.slashDeg)])
	md.append("")

	var fa := FileAccess.open("res://docs/sim/PROBE_FANG.md", FileAccess.WRITE)
	fa.store_string("\n".join(md) + "\n")
	fa.close()
	print("\n".join(md))
	print("PROBE_FANG_DONE")
	quit()
