extends SceneTree
## 특수 정예 7종을 **실제 출격 편성 안에서** 2·3막으로 재는 계측 도구(합격/불합격 판정이 아니다).
##
## 실행
##   python tools/run_suites.py --suites elite_placement_measure --allow-adhoc
##   (직접: godot --headless --path prophecy_godot -s tests/elite_placement_measure.gd)
##
## 부분 실행(바꾼 것만 작게 먼저 확인할 때) — tools/subset.gd
##   PROPHECY_SUBSET="act=2;elite=elite_fang" python tools/run_suites.py --suites elite_placement_measure --allow-adhoc
##   축: act(2·3) / elite(정예 종류) / seed / mode(single·pair)
##   부분 실행이면 결과가 docs/sim/ELITE_PLACEMENT_PARTIAL.md로 나간다(전체 결과 파일을 덮어쓰지 않는다).
##
## 무엇을 재는가(사용자 지시)
##   ① 살아서 실행한 공격 수(개체별 e.executed — 죽기 전에 실제로 판정까지 간 공격)
##   ② 고유 연계를 몇 번 시작/완주했는가
##   ③ 플레이어가 그 정예에게서 받은 피해(공격자별로 나눠 센다 — 같은 전투의 일반 적과 섞이지 않는다)
##   ④ 처치 시간(그 개체가 등장해서 죽을 때까지)
## **봇 승패는 통과 조건이 아니다.** 통과 조건은 "측정이 실제로 이루어졌는가"뿐이다(docs/BOT_FRAMEWORK.md).
##
## 편성은 손으로 만들지 않는다. data/themes.json → PRun.formation_waves → PFlow.encounter_opts라는
## 실제 경로를 그대로 지나므로, 표의 수치는 게임에서 그 편성으로 나갔을 때의 값이다.
## 예외는 'single' 열뿐이다: 정예 2마리 편성(3막 위험)에서 1마리만 남기고 지운 **비교용** 실행이며,
## 데이터를 바꾼 것이 아니라 측정에서만 뺀 것이다.

const STEP := 1.0 / 120.0
const MAX_SEC := 300.0
const SEEDS := [1, 2, 3]
const POLICY := "balanced"
## 그 막까지 사람이 보통 쌓았을 성장 선택 수(보통 수준 투자). tools/hp_effect_report.gd와 같은 기준
const PICKS_BY_DAY := { 5: 12, 9: 22 }
const DAY_OF_ACT := { 2: 5, 3: 9 }

## 연계 판별: [시작 상태, 완주로 볼 상태들]. tests/elites_bot_measure.gd와 같은 표를 쓴다
const COMBO := {
	"elite_archer": ["aim", ["fan_lock"]],
	"elite_blademaster": ["dash1_aim", ["slam_aim"]],
	"elite_fang": ["bite_aim", ["leap"]],
	"elite_plaguecaller": ["throw_aim", ["swell"]],
	"elite_chainbreaker": ["chain_aim", ["slam_lock", "retract"]],
	"elite_standard": ["plant_aim", ["plant_aim", "slash_aim"]],
	"elite_miner": ["dive", ["erupt"]],
}

var results := []
var sub: PSubset = null

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 공격자별 피해 기록기 ----------
## CombatState.recorder 자리에 꽂아 "누가 때렸는가"로 피해를 나눈다.
## metrics.taken은 공격 이름(src)으로만 나뉘어서 같은 전투의 정예 2종을 구분하지 못한다.
class ByAttacker extends RefCounted:
	var taken: Dictionary = {}   # 적 종류 → 실제로 깎인 체력
	var hits: Dictionary = {}    # 적 종류 → 맞은 횟수
	func on_step_begin(_st, _input) -> void: pass
	func on_step_end(_st) -> void: pass
	func on_reject(_st, _amount: float, _src: String, _attacker, _reason: String) -> void: pass
	func on_hit(_st, d: Dictionary) -> void:
		var a = d.get("attacker", null)
		if a == null or not (a is Dictionary):
			return
		var tp := String((a as Dictionary).get("type", ""))
		taken[tp] = float(taken.get(tp, 0.0)) + float(d.get("effective", 0.0))
		hits[tp] = int(hits.get(tp, 0)) + 1

# ---------- 회차·빌드 ----------
## 그 날짜까지의 성장(두 자동기술 + 개조 + 공용·패시브). tools/hp_effect_report.gd와 같은 규칙
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
	run.stage = act - 1   # 넘은 관문 수 = 막 - 1
	grow(run, int(PICKS_BY_DAY.get(day, 12)))
	return run

## 실제 출격과 같은 조우 옵션. drop_second면 정예 두 번째 마리를 측정에서만 뺀다(1마리 비교용)
func encounter(run: Dictionary, place_id: String, formation_id: String, seed_v: int, drop_second: bool) -> CombatState:
	var sortie := { "regionId": place_id, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 },
		"encounters": 0, "seed": int(run.seed) * 131 + seed_v * 17 + int(run.day), "day": int(run.day),
		"slot": 0, "variant": null, "formationId": formation_id }
	var o := PFlow.encounter_opts(run, sortie)
	if drop_second:
		var left := 1
		for w in (o.waves as Array):
			for g in w:
				if not bool(PCatalog.enemy(String(g.type)).get("elite", false)):
					continue
				var keep: int = mini(left, int(g.n))
				left -= keep
				g.n = keep
				if g.has("ref"):
					g.ref = float(keep)
	return CombatState.new(o)

# ---------- 한 번 실행 ----------
## 반환: { by_type: {정예종류 → {n, executed, combos, finishes, ttk[], killed, taken, hits}}, status, sec, spawned, elite_alive_max }
func run_once(run: Dictionary, place_id: String, formation_id: String, seed_v: int, drop_second: bool) -> Dictionary:
	var st := encounter(run, place_id, formation_id, seed_v, drop_second)
	var rec := ByAttacker.new()
	st.recorder = rec
	var bot := PBot.new(POLICY)
	var track := []          # 추적 중인 정예 개체
	var by_type := {}
	var elite_alive_max := 0
	var n := 0
	while st.status == "running" and n < int(MAX_SEC / STEP):
		st.step(bot.step_input(st), STEP)
		n += 1
		var alive := 0
		for e in st.enemies:
			if not PEnemiesNew.is_elite(String(e.type)):
				continue
			if not bool(e.dead):
				alive += 1
			if not e.has("_m_i"): # 새로 나온 정예: 추적 시작
				e["_m_i"] = track.size()
				track.append({ "e": e, "type": String(e.type), "last": String(e.state), "combos": 0, "finishes": 0,
					"spawn_t": float(st.t), "death_t": -1.0 })
		elite_alive_max = maxi(elite_alive_max, alive)
		for r in track:
			var e: Dictionary = r.e
			var cs: Array = COMBO.get(String(r.type), ["", []])
			if String(e.state) != String(r.last):
				if String(e.state) == String(cs[0]) and String(r.last) == "approach":
					r.combos = int(r.combos) + 1
				if (cs[1] as Array).has(String(e.state)):
					r.finishes = int(r.finishes) + 1
				r.last = String(e.state)
			if bool(e.dead) and float(r.death_t) < 0.0:
				r.death_t = float(st.t)
	for r in track:
		var tp := String(r.type)
		if not by_type.has(tp):
			by_type[tp] = { "n": 0, "executed": 0, "combos": 0, "finishes": 0, "ttk": [], "killed": 0,
				"taken": float(rec.taken.get(tp, 0.0)), "hits": int(rec.hits.get(tp, 0)) }
		var b: Dictionary = by_type[tp]
		b.n = int(b.n) + 1
		b.executed = int(b.executed) + int((r.e as Dictionary).get("executed", 0))
		b.combos = int(b.combos) + int(r.combos)
		b.finishes = int(b.finishes) + int(r.finishes)
		if float(r.death_t) >= 0.0:
			b.killed = int(b.killed) + 1
			(b.ttk as Array).append(float(r.death_t) - float(r.spawn_t))
	var spawned := 0
	for k in (st.metrics.enemies as Dictionary):
		spawned += int(st.metrics.enemies[k].get("spawned", 0))
	return { "by_type": by_type, "status": st.status, "sec": float(st.t), "spawned": spawned,
		"elite_alive_max": elite_alive_max, "taken_all": float(st.stats.damage_taken), "xp": float(st.stats.xp) }

func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

# ---------- 배치표 읽기 ----------
## data/themes.json에서 "정예를 쓰는 편성 × 장소"를 전부 뽑는다. 손으로 적은 목록이 아니라 실제 데이터다.
func slots_for_act(act: int) -> Array:
	var out := []
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		if int(t.act) != act:
			continue
		var places: Array = t.places
		for kind in ["normal", "risk"]:
			for f in (t.formations[kind] as Array):
				if int(f.get("elites", 0)) <= 0:
					continue
				for pi in places.size():
					var pk := "p1" if pi == 0 else "p2"
					out.append({ "act": act, "theme": String(tid), "theme_name": String(t.name),
						"place": String(places[pi].id), "place_name": String(places[pi].name), "pk": pk,
						"formation": String(f.id), "formation_name": String(f.name), "kind": String(kind),
						"elites": int(f.elites), "types": PRun.elite_types_for(f, pk, false) })
	return out

func line_of(r: Dictionary, tp: String) -> String:
	var b: Dictionary = r.by_type.get(tp, {})
	if b.is_empty():
		return "| — | — | — | — |"
	return "| %d | %d | %d / %d | %.0f |" % [int(b.n), int(b.executed), int(b.combos), int(b.finishes), float(b.taken)]

func _init() -> void:
	sub = PSubset.new()
	var acts: Array = sub.pick("act", [2, 3])
	var seeds: Array = sub.pick("seed", SEEDS)
	var modes: Array = sub.pick("mode", ["single", "pair"])
	var want_elites: Array = sub.pick("elite", PEnemiesNew.ELITE_TYPES)

	var md := []
	md.append(sub.describe("특수 정예 7종 — 실제 편성 안에서의 2·3막 측정"))
	md.append("봇 정책 `%s` · 시드 %s 중앙값 · 최대 %d초 · 빌드는 그 막까지의 보통 성장(%s 선택)." % [POLICY, str(seeds), int(MAX_SEC), str(PICKS_BY_DAY)])
	md.append("")
	md.append("**봇 승패는 통과 조건이 아니다.** 편성·체력·수는 data/themes.json과 data/pacing.json 그대로이며, 이 도구는 아무것도 바꾸지 않는다.")
	md.append("")

	var measured := 0
	var no_attack := []
	var under_two := []
	var slots_all := []
	for a in acts:
		slots_all.append_array(slots_for_act(int(a)))

	# ---------- 1. 1마리씩 ----------
	if modes.has("single"):
		md.append("## 1. 정예 1마리 — 실제 편성 안(정예 2마리 편성은 1마리만 남기고 잰 비교값)")
		md.append("")
		md.append("| 막 | 장소 | 편성 | 정예 | 체력 | 처치 시간(초) | 살아서 실행한 공격 | 연계 시작/완주 | 그 정예에게 받은 피해 | 전투 전체 받은 피해 | 전투 전체(초·등장 수) |")
		md.append("|---|---|---|---|---:|---:|---:|---:|---:|---:|---|")
		for s in slots_all:
			var tp := String((s.types as Array)[0])
			if not want_elites.has(tp):
				continue
			var ttks := []
			var exs := []
			var cbs := []
			var fns := []
			var tks := []
			var secs := []
			var spw := []
			var alls := []
			var killed := 0
			for sd in seeds:
				var run := make_run(int(sd), int(s.act), String(s.theme))
				var r := run_once(run, String(s.place), String(s.formation), int(sd), true)
				measured += 1
				var b: Dictionary = r.by_type.get(tp, {})
				if b.is_empty():
					continue
				exs.append(float(b.executed))
				cbs.append(float(b.combos))
				fns.append(float(b.finishes))
				tks.append(float(b.taken))
				secs.append(float(r.sec))
				spw.append(float(r.spawned))
				alls.append(float(r.taken_all))
				if int(b.killed) > 0:
					killed += 1
					ttks.append(med(b.ttk))
				else:
					ttks.append(MAX_SEC)
			if exs.is_empty():
				continue
			var mt := med(ttks)
			md.append("| %d | %s(%s) | %s | %s | %.0f | %s | %.0f | %.0f / %.0f | %.0f | %.0f | %.0f초 · %.0f마리 |" % [
				int(s.act), String(s.place_name), String(s.pk), String(s.formation_name), String(PCatalog.enemy(tp).name),
				PPacing.elite_hp(tp, int(s.act)), ("%.1f" % mt) if mt < MAX_SEC else "미처치",
				med(exs), med(cbs), med(fns), med(tks), med(alls), med(secs), med(spw)])
			if med(exs) < 1.0:
				no_attack.append("%d막 %s/%s" % [int(s.act), String(s.formation), tp])
			if med(fns) < 2.0:
				under_two.append("%d막 %s %s 완주 %.0f회" % [int(s.act), String(s.place), tp, med(fns)])
		md.append("")

	# ---------- 2. 조합(정예 2마리) ----------
	if modes.has("pair"):
		md.append("## 2. 조합 — 편성이 정한 정예 2마리를 그대로")
		md.append("")
		md.append("| 막 | 장소 | 편성 | 조합 | 정예 | 마리 | 살아서 실행한 공격 | 연계 시작/완주 | 그 정예에게 받은 피해 | 동시 생존 정예 최대 | 전투 전체 |")
		md.append("|---|---|---|---|---|---:|---:|---:|---:|---:|---|")
		for s in slots_all:
			if int(s.elites) < 2:
				continue
			var types: Array = s.types
			var hit := false
			for tp in types:
				if want_elites.has(String(tp)):
					hit = true
			if not hit:
				continue
			var runs := []
			for sd in seeds:
				var run := make_run(int(sd), int(s.act), String(s.theme))
				runs.append(run_once(run, String(s.place), String(s.formation), int(sd), false))
				measured += 1
			var names := []
			for tp in types:
				names.append(String(PCatalog.enemy(String(tp)).name))
			var seen := {}
			for tp in types:
				var t := String(tp)
				if seen.has(t):
					continue
				seen[t] = true
				var exs2 := []
				var cbs2 := []
				var fns2 := []
				var tks2 := []
				var ns := []
				var mx := []
				var secs2 := []
				for r in runs:
					var b: Dictionary = r.by_type.get(t, {})
					if b.is_empty():
						continue
					exs2.append(float(b.executed))
					cbs2.append(float(b.combos))
					fns2.append(float(b.finishes))
					tks2.append(float(b.taken))
					ns.append(float(b.n))
					mx.append(float(r.elite_alive_max))
					secs2.append(float(r.sec))
				if exs2.is_empty():
					continue
				md.append("| %d | %s(%s) | %s | %s | %s | %.0f | %.0f | %.0f / %.0f | %.0f | %.0f | %.0f초 |" % [
					int(s.act), String(s.place_name), String(s.pk), String(s.formation_name), " + ".join(names),
					String(PCatalog.enemy(t).name), med(ns), med(exs2), med(cbs2), med(fns2), med(tks2), med(mx), med(secs2)])
				if med(fns2) < 2.0:
					under_two.append("%d막 %s %s(조합) 완주 %.0f회" % [int(s.act), String(s.place), t, med(fns2)])
		md.append("")

	md.append("## 3. 관찰")
	md.append("")
	md.append("- 맞기 전에 녹아 사라진 조합(살아서 실행한 공격 0회): **%s**" % ("없다" if no_attack.is_empty() else ", ".join(no_attack)))
	md.append("- 고유 연계를 2회 미만 완주한 조합(체력·간격 조정 후보): **%s**" % ("없다" if under_two.is_empty() else ", ".join(under_two)))
	md.append("- 봇 승패는 판정이 아니다. 위 표의 '전투 전체'는 편성 전체를 끝내는 데 걸린 시간이다.")
	md.append("")

	var path := sub.out_path("res://docs/sim/ELITE_PLACEMENT.md")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(md))
		f.close()
	print("\n".join(md))
	print("")
	print("결과 파일: %s" % path)

	ok("측정이 실제로 이루어졌다(실행 %d회)" % measured, measured > 0, sub.summary())
	ok("모든 정예가 살아서 공격을 실행한다(맞기 전에 녹아 사라지지 않는다)", no_attack.is_empty(), str(no_attack))
	ok("[관찰] 고유 연계 2회 완주 — 미달은 조정 후보이며 판정이 아니다", true, str(under_two) if not under_two.is_empty() else "모든 조합 2회 이상")

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
