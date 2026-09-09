extends SceneTree
## 조사 전용(임시): 룬 지뢰가 '어디서' 세지는가.
##   godot --headless --path prophecy_godot -s tools/probe_mine.gd
## 규칙·수치를 하나도 바꾸지 않는다. 읽는 값만 쓴다.
##
## ① 겹침: 같은 적이 여러 폭발에 연달아 맞는가(폭발당 적중 수 = cause_hits/cause_fires)
## ② 자리잡기 비용: 지뢰가 놓인 자리와 플레이어 자리의 거리(st.mines를 매 단계 읽는다)
## ③ 출처별 비중: data/balance.json lab.BUILDS의 기존 조합으로, 같은 씨앗·같은 편성에서
##    지뢰 있는 빌드 vs 지뢰만 뺀 빌드. balance.json은 읽기만 하고 지뢰는 **측정에서만** 뺀다.

const STEP := 1.0 / 120.0
const MAX_SEC := 90.0
const SEEDS := [1, 2, 3]

var md := []

# ---------- 지뢰 중심 조합(성장 규칙 그대로 키운다) ----------
## tools/combo_probe.gd의 대표 조합 `sword_ember_mine`과 같은 투자 배분이다.
## 개조는 자격이 열린 뒤에만 고른다(PGrowth.mod_quota_of).
func run_mine_focus(seed_v: int, drop_mine: bool, swap: String = "mine") -> Dictionary:
	var run := PRun.new_run(seed_v, "sword")
	PGrowth.apply_choice(run, { "kind": "weapon_new", "id": "ember" })
	if not drop_mine:
		PGrowth.apply_choice(run, { "kind": "weapon_new", "id": swap })
	for i in 4:
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": "sword" })
	for sid in (["ember", swap] if not drop_mine else ["ember"]):
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": String(sid) })
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": String(sid) })
	for w in (run.growth.weapons as Array):
		var wid := String(w.id)
		var quota := PGrowth.mod_quota_of(run.growth, w)
		for mid in PCatalog.weapon(wid).get("mods", {}):
			if (w.mods as Array).size() >= quota:
				break
			if bool(PCatalog.weapon(wid).mods[mid].get("impl", false)):
				PGrowth.apply_choice(run, { "kind": "weapon_mod", "id": wid, "mod": String(mid) })
	run.hp = float(PRun.build(run).hp_max)
	return run

# ---------- lab 빌드 → 회차 ----------
func run_of(build_id: String, seed_v: int, drop_mine: bool) -> Dictionary:
	if build_id == "mine_focus":
		return run_mine_focus(seed_v, drop_mine)
	var bd: Dictionary = (PCatalog.lab().BUILDS as Dictionary)[build_id]
	var run := PRun.new_run(seed_v, "sword")
	var g: Dictionary = run.growth
	g.weapons = []
	g.commons = {}
	g.passives = {}
	g.skills = { "q": g.skills.q, "e": null }
	for w in (bd.growth as Dictionary).get("weapons", []):
		if drop_mine and String(w.id) == "mine":
			continue
		g.weapons.append({ "id": String(w.id), "level": int(w.level), "mods": (w.get("mods", []) as Array).duplicate() })
	for cid in (bd.growth as Dictionary).get("commons", {}):
		g.commons[String(cid)] = int(bd.growth.commons[cid])
	for pid in (bd.growth as Dictionary).get("passives", {}):
		g.passives[String(pid)] = int(bd.growth.passives[pid])
	var e = (bd.growth as Dictionary).get("e", null)
	if e != null:
		g.skills.e = { "id": String(e.id), "level": int(e.level), "variant": e.get("variant", null) }
	var q = (bd.growth as Dictionary).get("q", null)
	if q != null:
		g.skills.q = { "id": "slowfield", "level": int(q.level), "variant": q.get("variant", null) }
	for rw in (bd.growth as Dictionary).get("bossRewards", []):
		(g.bossRewards as Array).append(String(rw))
	var gear: Dictionary = bd.get("gear", {})
	if gear.has("upgrade"):
		run.forge = int(gear.upgrade)
	run.hp = float(PRun.build(run).hp_max)
	return run

func fight(run: Dictionary, waves: Array, seed_v: int, act: int) -> CombatState:
	return CombatState.new({ "build": PRun.build(run), "hp": float(run.hp), "seed": seed_v,
		"waves": waves, "objective": "clear", "region_id": "lab", "arena": "clearing", "act": act, "run": run })

func run_fight(run: Dictionary, waves: Array, seed_v: int, pol: String, act: int) -> Dictionary:
	var st := fight(run, waves, seed_v, act)
	var bot := PBot.new(pol)
	var place_d := []          # 지뢰가 놓인 자리 ↔ 플레이어 자리 거리
	var gaps := []             # 연달아 놓인 지뢰 사이 거리(연쇄 폭발 범위 90과 비교)
	var last_pos: Array = []
	var known := 0
	var per_enemy := {}        # 적 id → 이 적을 덮은 폭발 수(전 생애)
	var burst_log := {}        # 적 id → 그 적을 덮은 폭발 시각들
	var n := int(MAX_SEC / STEP)
	for i in n:
		if st.status != "running":
			break
		st.step(bot.step_input(st), STEP)
		if st.mines.size() > known:
			for k in range(known, st.mines.size()):
				var mn: Dictionary = st.mines[k]
				place_d.append(PGeom.dist(float(mn.x), float(mn.y), float(st.player.x), float(st.player.y)))
				if not last_pos.is_empty():
					gaps.append(PGeom.dist(float(mn.x), float(mn.y), float(last_pos[0]), float(last_pos[1])))
				last_pos = [float(mn.x), float(mn.y)]
		known = st.mines.size()
		# 이번 단계에 생긴 폭발 표시(mineburst)만 본다. 반지름은 실제 판정과 같은 값이 fx에 들어 있다
		for f in st.effects:
			if String(f.get("kind", "")) != "mineburst" or float(f.t) > STEP * 1.5:
				continue
			for e in st.alive_targets():
				if PGeom.dist(float(f.x), float(f.y), float(e.x), float(e.y)) <= float(f.r) + float(e.r):
					var eid := int(e.id)
					per_enemy[eid] = int(per_enemy.get(eid, 0)) + 1
					if not burst_log.has(eid):
						burst_log[eid] = []
					(burst_log[eid] as Array).append(float(st.t))
	# 0.5초 창 안에 같은 적을 덮은 폭발 수의 최댓값
	var max_window := 0
	var multi := 0
	for eid in burst_log:
		var ts: Array = burst_log[eid]
		if int(per_enemy.get(eid, 0)) >= 2:
			multi += 1
		for a in ts.size():
			var c := 0
			for b in ts.size():
				if float(ts[b]) >= float(ts[a]) and float(ts[b]) - float(ts[a]) <= 0.5:
					c += 1
			max_window = maxi(max_window, c)
	var dmg: Dictionary = st.metrics.dmg
	var total := 0.0
	for k in dmg:
		total += float(dmg[k])
	return { "sec": float(st.t), "status": String(st.status), "kills": int(st.stats.kills),
		"total": total, "dmg": dmg.duplicate(), "taken": float(st.stats.damage_taken),
		"cause_dmg": (st.metrics.cause_dmg as Dictionary).duplicate(),
		"cause_hits": (st.metrics.cause_hits as Dictionary).duplicate(),
		"cause_fires": (st.metrics.cause_fires as Dictionary).duplicate(),
		"place_d": place_d, "gaps": gaps, "per_enemy": per_enemy, "multi": multi, "max_window": max_window,
		"covered": per_enemy.size() }

func avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

# ---------- ① 겹침: 한 적이 겹친 폭발에 몇 번 맞는가 ----------
## 지뢰 N개를 **한 자리에 모아 두고** 적 하나를 그 위에 세운다. 손으로 피해를 넣지 않는다 —
## PWeapons.update_mines가 접촉을 보고 explode_mine을 부르는 실제 경로 그대로다.
## 플레이어는 멀리 떼어 두어 자동 설치된 지뢰가 이 측정에 섞이지 않게 한다(0.6초만 돌린다).
func overlap_test(n_mines: int) -> Dictionary:
	var run := run_of("late_hammer", 1, false)
	var st := fight(run, [[]], 1, 3)
	st.spawn_hold = true
	var w := {}
	for ww in st.weapons:
		if String(ww.stats.kind) == "mine":
			w = ww
	if w.is_empty():
		return {}
	var cx: float = clampf(float(st.player.x) + 420.0, 60.0, float(st.arena_w) - 60.0)
	var cy: float = clampf(float(st.player.y) + 300.0, 60.0, float(st.arena_h) - 60.0)
	var e := st.spawn_enemy("wolf", cx, cy)
	e.hp = 1.0e7
	e.hp_max = 1.0e7
	for i in n_mines:
		# 실제 설치와 같은 형식(PWeapons.fire_mine이 넣는 항목 그대로). 겹치도록 같은 자리에 둔다
		st.mines.append({ "weapon": w, "x": cx, "y": cy, "r": float(w.stats.trigger), "arm": 0.0, "t": 0.0, "dead": false })
	var bot := PBot.new("idle")
	for i in int(0.6 / STEP):
		st.step(bot.step_input(st), STEP)
	return { "mines": n_mines, "dmg": float((st.metrics.cause_dmg as Dictionary).get("mine", 0.0)),
		"hits": int((st.metrics.cause_hits as Dictionary).get("mine", 0)),
		"blasts": int((st.metrics.cause_fires as Dictionary).get("mine", 0)),
		"base": float(w.stats.damage), "radius": float(w.stats.radius), "trigger": float(w.stats.trigger), "max": int(w.stats.max) }

func _init() -> void:
	md.append("# 조사: 룬 지뢰 측정")
	md.append("")
	md.append("생성 `tools/probe_mine.gd` · 단계 %0.4f초 · 상한 %d초 · 시드 %s. **규칙·수치를 바꾸지 않았다.**" % [STEP, int(MAX_SEC), str(SEEDS)])
	md.append("")

	# ---------- 파생 수치 ----------
	md.append("## 1. 파생 수치(late_hammer 조합에서 실제로 계산된 값)")
	md.append("")
	md.append("| 항목 | 값 |")
	md.append("|---|---:|")
	var r0 := run_of("late_hammer", 1, false)
	var b0 := PRun.build(r0)
	for s in (b0.weapons as Array):
		if String(s.id) != "mine":
			continue
		md.append("| 기본 피해(base 22 × 레벨 × 강화) | %.1f |" % float(s.damage))
		md.append("| 폭발 반지름(base 70 × 폭 증강) | %.1f |" % float(s.radius))
		md.append("| 밟는 반지름(base 30 × 폭 증강) | %.1f |" % float(s.trigger))
		md.append("| 설치 주기(초) | %.2f |" % float(s.interval))
		md.append("| 동시 설치 상한 | %d |" % int(s.max))
	md.append("")

	# ---------- ① 겹침 ----------
	md.append("## 2. 폭발이 겹치면 같은 적이 여러 번 맞는가")
	md.append("")
	md.append("같은 자리에 지뢰 N개를 두고 적 1마리(체력 1000만)가 밟게 한다. 손으로 피해를 넣지 않고 `PWeapons.update_mines`가 실제로 터뜨린다.")
	md.append("")
	md.append("| 겹쳐 둔 지뢰 | 폭발 수 | 그 적이 맞은 횟수 | 총 피해 | 1개일 때 대비 |")
	md.append("|---:|---:|---:|---:|---:|")
	var base_d := 0.0
	for n in [1, 2, 3, 5, 8]:
		var r := overlap_test(int(n))
		if r.is_empty():
			continue
		if int(n) == 1:
			base_d = float(r.dmg)
		md.append("| %d | %d | %d | %.1f | ×%.2f |" % [int(n), int(r.blasts), int(r.hits), float(r.dmg), float(r.dmg) / maxf(0.01, base_d)])
	md.append("")
	md.append("실전 전투(밀집 편성, 시드 3개)에서 **한 적이 여러 폭발에 맞은** 정도:")
	md.append("")
	md.append("| 시드 | 폭발이 덮은 적 수 | 2회 이상 맞은 적 | 0.5초 안에 한 적을 덮은 폭발 최대 |")
	md.append("|---:|---:|---:|---:|")
	var waves_ov: Array = [[{ "type": "wolf", "n": 5 }, { "type": "rogue", "n": 3 }, { "type": "archer", "n": 2 }]]
	for sd in SEEDS:
		var rr := run_fight(run_of("late_hammer", int(sd), false), waves_ov.duplicate(true), int(sd), "balanced", 3)
		md.append("| %d | %d | %d | %d |" % [int(sd), int(rr.covered), int(rr.multi), int(rr.max_window)])
	md.append("")

	# ---------- ② 자리잡기 ----------
	md.append("## 3. 자리잡기 비용 — 지뢰는 어디에 놓이는가")
	md.append("")
	var waves3: Array = [[{ "type": "wolf", "n": 5 }, { "type": "rogue", "n": 3 }, { "type": "archer", "n": 2 }]]
	var pd := []
	var gp := []
	var cause_ratio := []
	var chain_ok := 0
	for sd in SEEDS:
		var rr := run_fight(run_of("late_hammer", int(sd), false), waves3.duplicate(true), int(sd), "balanced", 3)
		pd.append_array(rr.place_d)
		gp.append_array(rr.gaps)
		var bl: float = float((rr.cause_fires as Dictionary).get("mine", 0))
		var hh: float = float((rr.cause_hits as Dictionary).get("mine", 0))
		if bl > 0.0:
			cause_ratio.append(hh / bl)
	for g in gp:
		if float(g) <= 90.0:
			chain_ok += 1
	pd.sort()
	md.append("| 항목 | 값 |")
	md.append("|---|---:|")
	md.append("| 설치 횟수(시드 3개 합) | %d |" % pd.size())
	md.append("| 설치 자리 ↔ 플레이어 자리 거리 · 평균 | %.2f px |" % avg(pd))
	md.append("| 같은 값 · 최댓값 | %.2f px |" % (float(pd[pd.size() - 1]) if not pd.is_empty() else 0.0))
	md.append("| 연달아 놓인 지뢰 사이 거리 · 평균 | %.0f px |" % avg(gp))
	md.append("| 그중 연쇄 폭발 범위(90) 안 | %d / %d (%.0f%%) |" % [chain_ok, gp.size(), 100.0 * float(chain_ok) / maxf(1.0, float(gp.size()))])
	md.append("| 실전 전투에서 폭발 1회당 적중 수 | %.2f |" % avg(cause_ratio))
	md.append("")

	# ---------- ③ 출처별 비중 ----------
	md.append("## 4. 출처별 유효 피해 비중 — 지뢰 있음 vs 없음(같은 씨앗·같은 편성)")
	md.append("")
	md.append("| 빌드 | 편성 | 지뢰 | 시드 | 결과 | 전투 시간 | 총 피해 | **지뢰 몫** | 주무기 몫 | 그 밖 | 처치 | 받은 피해 |")
	md.append("|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|")
	var scen := [
		{ "id": "밀집(늑대 5·도적 3·궁수 2)", "waves": waves3, "act": 3 },
		{ "id": "소수(늑대 3)", "waves": [[{ "type": "wolf", "n": 3 }]], "act": 3 },
	]
	var builds := [{ "id": "late_hammer", "main": "weapon:hammer" }, { "id": "mine_focus", "main": "weapon:sword" }]
	var summary := {}
	for bid in builds:
		for sc in scen:
			for drop in [false, true]:
				for sd in SEEDS:
					var run := run_of(String(bid.id), int(sd), bool(drop))
					var r := run_fight(run, (sc.waves as Array).duplicate(true), int(sd), "balanced", int(sc.act))
					var dmg: Dictionary = r.dmg
					var mine_d: float = float(dmg.get("weapon:mine", 0.0))
					var main_d: float = float(dmg.get(String(bid.main), 0.0))
					var rest: float = float(r.total) - mine_d - main_d
					md.append("| %s | %s | %s | %d | %s | %.1f초 | %.0f | **%.0f (%.0f%%)** | %.0f (%.0f%%) | %.0f | %d | %.0f |" % [
						String(bid.id), String(sc.id), ("뺌" if drop else "있음"), int(sd), String(r.status), float(r.sec), float(r.total),
						mine_d, 100.0 * mine_d / maxf(1.0, float(r.total)),
						main_d, 100.0 * main_d / maxf(1.0, float(r.total)), rest, int(r.kills), float(r.taken)])
					var key := "%s|%s|%s" % [String(bid.id), String(sc.id), ("뺌" if drop else "있음")]
					if not summary.has(key):
						summary[key] = { "share": [], "sec": [], "kills": [] }
					(summary[key].share as Array).append(100.0 * mine_d / maxf(1.0, float(r.total)))
					(summary[key].sec as Array).append(float(r.sec))
					(summary[key].kills as Array).append(float(r.kills))
	md.append("")
	md.append("| 빌드·편성·지뢰 | 지뢰 몫 평균 | 전투 시간 평균 | 처치 평균 |")
	md.append("|---|---:|---:|---:|")
	for key in summary:
		md.append("| %s | %.0f%% | %.1f초 | %.1f |" % [String(key), avg(summary[key].share), avg(summary[key].sec), avg(summary[key].kills)])
	md.append("")

	# ---------- ④ 다른 보조와의 상대 비중 ----------
	md.append("## 5. 같은 자리를 다른 보조로 바꿨을 때 — 상대 비중")
	md.append("")
	md.append("검 Lv5 + 불씨 Lv3 + **X Lv3(개조 1)**. 같은 씨앗·같은 편성(밀집). X만 바꾼다.")
	md.append("")
	md.append("| 두 번째 보조 X | X의 유효 피해(평균) | X의 몫 | 총 피해 | 전투 시간 | 받은 피해 |")
	md.append("|---|---:|---:|---:|---:|---:|")
	var swaps := ["mine", "blades", "orb", "frost", "crow", "wind", "plague"]
	for sw in swaps:
		if not bool(PCatalog.weapon(String(sw)).get("impl", false)):
			continue
		var xs := []
		var sh := []
		var tt := []
		var ss := []
		var tk := []
		for sd in SEEDS:
			var run := run_mine_focus(int(sd), false, String(sw))
			var r := run_fight(run, waves3.duplicate(true), int(sd), "balanced", 3)
			var xd: float = float((r.dmg as Dictionary).get("weapon:" + String(sw), 0.0))
			xs.append(xd)
			sh.append(100.0 * xd / maxf(1.0, float(r.total)))
			tt.append(float(r.total))
			ss.append(float(r.sec))
			tk.append(float(r.taken))
		md.append("| %s(%s) | %.0f | **%.0f%%** | %.0f | %.1f초 | %.0f |" % [
			String(PCatalog.weapon(String(sw)).name), String(sw), avg(xs), avg(sh), avg(tt), avg(ss), avg(tk)])
	md.append("")
	md.append("보조는 역할이 서로 다르다(막기·둔화·유인은 피해로 나타나지 않는다). 이 표는 **피해 몫만** 비교한 것이다.")
	md.append("")
	var fa := FileAccess.open("res://docs/sim/PROBE_MINE.md", FileAccess.WRITE)
	fa.store_string("\n".join(md) + "\n")
	fa.close()
	print("\n".join(md))
	print("PROBE_MINE_DONE")
	quit()
