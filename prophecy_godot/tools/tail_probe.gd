extends SceneTree
## **전투 말미 계측 도구**(합격/불합격 판정이 아니다 — 수치를 남기는 것이 전부다).
##
## 왜 있는가
##   사람 관찰: "멧돼지만 남으면 조금씩 등장해 전투가 지루하게 길어진다."
##   원인을 짐작하지 않고 **재기 위해** 만들었다. 재는 것은 두 가지가 핵심이다.
##     ① 적이 1~2마리만 남아 있는 시간
##     ② 자리가 비었는데(동시 상한에 여유가 있는데) 다음 적을 기다린 시간
##   그리고 그 대기가 **왜** 생겼는지를 가르기 위해 아래를 함께 센다.
##     · 종류별 동시 생존 상한에 막혀 아무도 못 나온 시간(cap_block)
##     · 살아 있는 적이 한 종류뿐인 시간(종류별로 분해 — 멧돼지만 남는지 확인)
##     · 실제로 이동/돌진 중인 적과 멀리서 대기하는 적의 구분(far_idle)
##     · 편성 대기열의 뒤쪽 4분의 1에 어떤 종류가 몰려 있는지
##
## 실행
##   python tools/run_suites.py --suites tail_probe
##   (직접: godot --headless --path prophecy_godot -s tools/tail_probe.gd)
##
## 부분 실행(tools/subset.gd) — 축: act(1·2·3) / formation(편성 id) / seed
##   PROPHECY_SUBSET="act=2;formation=t2c_boar_archer" python tools/run_suites.py --suites tail_probe
##   부분이면 결과가 docs/sim/TAIL_PROBE_PARTIAL.md로 나간다(전체 결과 파일을 덮어쓰지 않는다).
##
## 수정 전후 비교
##   PROPHECY_TAIL_TAG="before" 로 한 번, "after"로 한 번 돌리면 파일 이름이 갈린다(같은 시드를 그대로 쓴다).
##
## 편성은 손으로 만들지 않는다. data/themes.json → PRun.formation_waves → PFlow.encounter_opts라는
## **실제 출격 경로**를 그대로 지나므로 표의 수치는 게임에서 그 편성으로 나갔을 때의 값이다.
## 플레이어는 계측 전용으로 죽지 않게 눌러 둔다(전투 말미까지 관찰하는 것이 목적이라서다 — 봇 승패는 재지 않는다).

const STEP := 1.0 / 120.0
const SAMPLE_EVERY := 6      # 20Hz 표본(계측 전용. 규칙·난수에 영향 없음)
const MAX_SEC := 420.0
const SEEDS := [1, 2, 3]
const POLICY := "balanced"
const NEAR_DIST := 320.0     # 이 거리 안이면 '붙어 싸우는 중'으로 본다(멧돼지 engageDist와 같은 값)
## 그 막까지 사람이 보통 쌓았을 성장 선택 수(tools/hp_effect_report.gd·tests/elite_placement_measure.gd와 같은 기준)
const PICKS_BY_DAY := { 1: 0, 5: 12, 9: 22 }
const DAY_OF_ACT := { 1: 1, 2: 5, 3: 9 }

## 재는 편성. 멧돼지가 든 편성 4개 + 대조군 2개(멧돼지 없음)
const CASES := [
	{ "id": "t1a_boar", "act": 1, "theme": "act1_hunt_forest", "place": "t1a_path", "note": "1막 멧돼지 30%" },
	{ "id": "t1a_wolves", "act": 1, "theme": "act1_hunt_forest", "place": "t1a_path", "note": "대조군: 멧돼지 없음" },
	{ "id": "t2c_boar_archer", "act": 2, "theme": "act2_frozen_pass", "place": "t2c_snow", "note": "2막 멧돼지 50% + 궁수 50%" },
	{ "id": "t2c_frost_boar", "act": 2, "theme": "act2_frozen_pass", "place": "t2c_snow", "note": "2막 멧돼지 60%" },
	{ "id": "t3b_wolf_boar", "act": 3, "theme": "act3_blood_hunt", "place": "t3b_redpath", "note": "3막 멧돼지 30%" },
	{ "id": "t3a_archer_burrow", "act": 3, "theme": "act3_temporal_abyss", "place": "t3a_rim", "note": "대조군: 궁수·잠복충(상한 3·2)" },
]

var results := []
var sub: PSubset = null

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 회차·빌드(tests/elite_placement_measure.gd와 같은 규칙) ----------
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
	grow(run, int(PICKS_BY_DAY.get(day, 12)))
	return run

func encounter(run: Dictionary, place_id: String, formation_id: String, seed_v: int) -> CombatState:
	var sortie := { "regionId": place_id, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 },
		"encounters": 0, "seed": int(run.seed) * 131 + seed_v * 17 + int(run.day), "day": int(run.day),
		"slot": 0, "variant": null, "formationId": formation_id }
	return CombatState.new(PFlow.encounter_opts(run, sortie))

# ---------- 한 전투 재기 ----------
## 반환: 아래 표의 한 줄(초 단위는 전부 실제 측정 시간)
func run_once(case: Dictionary, seed_v: int) -> Dictionary:
	var run := make_run(seed_v, int(case.act), String(case.theme))
	var st := encounter(run, String(case.place), String(case.id), seed_v)
	var bot := PBot.new(POLICY)
	var units0: Array = (st.formation.units as Array).duplicate()
	var caps: Dictionary = st.formation.get("type_caps", {})
	var cap_all: int = int(st.formation.get("alive_cap", 0))

	var tail12 := 0.0        # 살아 있는 적이 1~2마리인 시간
	var tail12_late := 0.0   # 그중 등장이 모두 끝난 뒤(진짜 잔당 처리)
	var room_wait := 0.0     # 자리가 비었는데 다음 적을 기다린 시간
	var cap_block := 0.0     # 그중 **종류별 상한** 때문에 아무도 못 나온 시간
	var one_type := 0.0      # 살아 있는 적이 한 종류뿐인 시간
	var one_type_by := {}    # 그 시간의 종류별 분해
	var alive_sum := 0.0
	var alive_n := 0
	var max_alive := 0
	var far_sum := 0.0       # 멀리서 대기하는 적 비율의 시간 합
	var far_n := 0
	var danger_sum := 0.0    # 동시 위험 공격 수(예고~실행 중인 적 수)의 시간 합
	var max_danger := 0
	var dt_s := STEP * float(SAMPLE_EVERY)

	var n := 0
	var limit := int(MAX_SEC / STEP)
	while st.status == "running" and n < limit:
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max # 계측 전용: 전투 말미까지 보기 위해 죽지 않게 한다(규칙·난수와 무관)
		st.player.dead = false
		n += 1
		if n % SAMPLE_EVERY != 0:
			continue
		var alive := 0
		var far := 0
		var danger := 0
		var types := {}
		for e in st.enemies:
			if e.dead or bool(e.get("structure", false)) or bool(e.get("hidden", false)):
				continue
			alive += 1
			types[String(e.type)] = true
			# '실제로 싸우는 중' = 위험 행동 중이거나 플레이어 가까이. 그 밖은 멀리서 대기 중
			var busy := PEnemies.is_committed(e)
			if busy:
				danger += 1
			if not busy and PGeom.dist(e.x, e.y, st.player.x, st.player.y) > NEAR_DIST:
				far += 1
		danger_sum += float(danger)
		max_danger = maxi(max_danger, danger)
		alive_sum += float(alive)
		alive_n += 1
		max_alive = maxi(max_alive, alive)
		if alive > 0:
			far_sum += float(far) / float(alive)
			far_n += 1
			if types.size() == 1:
				one_type += dt_s
				var only := String(types.keys()[0])
				one_type_by[only] = float(one_type_by.get(only, 0.0)) + dt_s
		if alive >= 1 and alive <= 2:
			tail12 += dt_s
			if bool(st.spawned_all):
				tail12_late += dt_s
		# 자리가 비었는데 기다리는가(등장이 남아 있을 때만 뜻이 있다)
		var queued: int = maxi(0, int(st.spawn_total) - int(st.spawn_count))
		var room: int = cap_all - st.alive_units() - st.pending.size()
		if queued > 0 and room > 0:
			room_wait += dt_s
			if not _any_pickable(st, caps):
				cap_block += dt_s

	var status := String(st.status)
	if status == "running":
		status = "timeout"
		st.delayed.clear()
	var sm := st.summary()
	return {
		"case": String(case.id), "act": int(case.act), "seed": seed_v, "status": status,
		"sec": snapped(float(st.t), 0.1), "spawn_total": int(st.spawn_total), "spawned": int(st.spawn_count),
		"kills": int(st.stats.kills), "alive_cap": cap_all, "type_caps": caps.duplicate(),
		"group": int(st.formation.get("group", 0)), "interval": float(st.formation.get("interval", 0.0)),
		"tail12_sec": snapped(tail12, 0.1), "tail12_late_sec": snapped(tail12_late, 0.1),
		"room_wait_sec": snapped(room_wait, 0.1), "cap_block_sec": snapped(cap_block, 0.1),
		"one_type_sec": snapped(one_type, 0.1), "one_type_by": _round_map(one_type_by),
		"avg_alive": snapped(alive_sum / float(maxi(1, alive_n)), 0.01), "max_alive": max_alive,
		"avg_danger": snapped(danger_sum / float(maxi(1, alive_n)), 0.01), "max_danger": max_danger,
		"far_idle_frac": snapped(far_sum / float(maxi(1, far_n)), 0.001),
		"queue_tail": _tail_mix(units0), "counts": (st.formation.get("godot_counts", {}) as Dictionary).duplicate(),
		"support_only_sec": float(sm.get("support_only_sec", 0.0)),
	}

## 지금 대기열에서 종류별 상한에 걸리지 않고 꺼낼 수 있는 적이 하나라도 있는가
## (combat_state.update_spawner의 고르기 규칙을 **읽기만** 해서 그대로 흉내 낸다)
func _any_pickable(st: CombatState, caps: Dictionary) -> bool:
	var units: Array = st.formation.units
	var i: int = int(st.spawn_count)
	while i < units.size():
		var tp := String(units[i])
		if st.alive_count_of(tp) < int(caps.get(tp, 9999)):
			return true
		i += 1
	return false

## 편성 대기열 뒤쪽 4분의 1의 종류 분포(말미에 어떤 종류가 몰리는가)
func _tail_mix(units: Array) -> Dictionary:
	var out := {}
	var from: int = int(float(units.size()) * 0.75)
	for i in range(from, units.size()):
		var tp := String(units[i])
		out[tp] = int(out.get(tp, 0)) + 1
	return out

func _round_map(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		out[String(k)] = snapped(float(m[k]), 0.1)
	return out

func _median(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var v := vals.duplicate()
	v.sort()
	return float(v[v.size() / 2])

func _sum_maps(rows: Array, key: String) -> Dictionary:
	var out := {}
	for r in rows:
		for k in (r[key] as Dictionary):
			out[String(k)] = float(out.get(String(k), 0.0)) + float((r[key] as Dictionary)[k])
	var res := {}
	for k in out:
		res[k] = snapped(float(out[k]) / float(maxi(1, rows.size())), 0.1)
	return res

func _fmt_map(m: Dictionary) -> String:
	var parts := []
	for k in m:
		parts.append("%s %s" % [String(k), str(m[k])])
	return ", ".join(parts) if not parts.is_empty() else "—"

# ---------- 정예 늑대 처치 시간(3막) ----------
## 사용자 관찰: "3막 정예 늑대가 오래 걸린다." **체력은 이번에 바꾸지 않았다**(사용자가 새 증강 비교 뒤에 결정한다).
## 관찰을 수치로 보존하려고 지금 상태 그대로 잰다. 정예 1마리 · 그 막까지의 보통 성장 빌드 · 봇.
const TTK_TYPES := ["elite_fang", "wolf_alpha"]
const TTK_MAX_SEC := 150.0

func ttk_once(type: String, seed_v: int, act: int) -> Dictionary:
	var run := make_run(seed_v, act, PCatalog.act_default_theme(act))
	var st := CombatState.new({ "build": PRun.build(run), "hp": float(run.hp), "seed": seed_v, "waves": [],
		"arena": "clearing", "region_id": "lab", "act": act, "fixed_build": true })
	st.spawn_hold = true
	var e := st.spawn_enemy(type, st.player.x + 300.0, st.player.y)
	var hp0: float = e.hp
	var bot := PBot.new(POLICY)
	var n := 0
	var limit := int(TTK_MAX_SEC / STEP)
	while not bool(e.dead) and n < limit:
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max # 계측 전용: 봇 승패가 아니라 처치 시간을 본다
		st.player.dead = false
		if st.status != "running":
			st.status = "running"
		n += 1
	st.delayed.clear()
	return { "type": type, "act": act, "seed": seed_v, "hp": snapped(hp0, 1.0),
		"ttk": snapped(float(st.t), 0.1) if bool(e.dead) else -1.0 }

func _init() -> void:
	sub = PSubset.new()
	var parts: Array = sub.pick("part", ["tail", "ttk"])
	var acts: Array = sub.pick("act", [1, 2, 3])
	var seeds: Array = sub.pick("seed", SEEDS)
	var case_ids := []
	for c in CASES:
		case_ids.append(String(c.id))
	var want: Array = sub.pick("formation", case_ids)
	var tag := OS.get_environment("PROPHECY_TAIL_TAG")

	var md := []
	md.append(sub.describe("전투 말미 계측 — 적이 1~2마리 남은 시간과 등장 대기%s" % ((" [%s]" % tag) if tag != "" else "")))
	md.append("봇 정책 `%s` · 시드 %s · 최대 %d초 · 표본 %dHz. **플레이어는 계측 전용으로 죽지 않게 눌렀다**(말미까지 보는 것이 목적)." % [POLICY, str(seeds), int(MAX_SEC), int(1.0 / (STEP * SAMPLE_EVERY))])
	md.append("편성은 `data/themes.json → PRun.formation_waves → PFlow.encounter_opts` 실제 경로 그대로다.")
	md.append("")

	var all_rows := []
	var ttk_rows := []
	var measured := 0
	for c in CASES:
		if not parts.has("tail") or not want.has(String(c.id)) or not acts.has(int(c.act)):
			continue
		var rows := []
		for s in seeds:
			var r := run_once(c, int(s))
			rows.append(r)
			all_rows.append(r)
			measured += 1
		var t12 := []
		var t12l := []
		var rw := []
		var cb := []
		var ot := []
		var secs := []
		var avg := []
		var far := []
		var dg_avg := []
		var dg_max := 0
		var timeouts := 0
		for r in rows:
			dg_avg.append(float(r.avg_danger))
			dg_max = maxi(dg_max, int(r.max_danger))
			t12.append(float(r.tail12_sec))
			t12l.append(float(r.tail12_late_sec))
			rw.append(float(r.room_wait_sec))
			cb.append(float(r.cap_block_sec))
			ot.append(float(r.one_type_sec))
			secs.append(float(r.sec))
			avg.append(float(r.avg_alive))
			far.append(float(r.far_idle_frac))
			if String(r.status) == "timeout":
				timeouts += 1
		var head: Dictionary = rows[0]
		md.append("## %s — %s (%d막 · %s)" % [String(c.id), String(c.note), int(c.act), String(c.place)])
		md.append("")
		md.append("- 편성: 전체 %d마리 · 동시 상한 **%d** · 묶음 %d · 간격 %.1f초 · 종류별 상한 **%s**" % [int(head.spawn_total), int(head.alive_cap), int(head.group), float(head.interval), _fmt_map(head.type_caps)])
		md.append("- 종류별 수: %s · 대기열 뒤 1/4: **%s**" % [_fmt_map(head.counts), _fmt_map(head.queue_tail)])
		md.append("")
		md.append("| 항목 | 중앙값 |")
		md.append("|---|---:|")
		md.append("| 전투 길이 | %.1f초 |" % _median(secs))
		md.append("| **적이 1~2마리만 남은 시간** | **%.1f초** |" % _median(t12))
		md.append("| 그중 등장이 다 끝난 뒤(잔당 처리) | %.1f초 |" % _median(t12l))
		md.append("| **자리가 비었는데 다음 적을 기다린 시간** | **%.1f초** |" % _median(rw))
		md.append("| 그중 종류별 상한에 막힌 시간 | %.1f초 |" % _median(cb))
		md.append("| 살아 있는 적이 한 종류뿐인 시간 | %.1f초 |" % _median(ot))
		md.append("| 평균 동시 생존 (상한 %d) | %.2f마리 |" % [int(head.alive_cap), _median(avg)])
		md.append("| **동시 위험 공격 수** 평균 / 최대 | %.2f / %d |" % [_median(dg_avg), dg_max])
		md.append("| 멀리서 대기하는 적 비율 | %.1f%% |" % (_median(far) * 100.0))
		md.append("| 시간 초과(전투가 안 끝남) | %d/%d회 |" % [timeouts, rows.size()])
		md.append("")
		var by := _sum_maps(rows, "one_type_by")
		md.append("한 종류만 남은 시간의 종류별 분해(시드 평균): **%s**" % _fmt_map(by))
		md.append("")

	if parts.has("ttk"):
		md.append("## 정예 늑대 처치 시간 — **체력은 이번에 바꾸지 않았다**")
		md.append("")
		md.append("사용자 관찰(3막 정예 늑대가 오래 걸린다)을 지금 상태 그대로 재서 보존한다. 정예 1마리 · 그 막까지의 보통 성장 빌드 · 봇 `%s` · 최대 %d초." % [POLICY, int(TTK_MAX_SEC)])
		md.append("")
		md.append("| 정예 | 막 | 체력 | 처치 시간(중앙값) |")
		md.append("|---|---:|---:|---:|")
		for tp in TTK_TYPES:
			for act in [1, 2, 3]:
				if not acts.has(act):
					continue
				var ts := []
				var hp := 0.0
				for s2 in seeds:
					var r2 := ttk_once(String(tp), int(s2), act)
					ttk_rows.append(r2)
					measured += 1
					hp = float(r2.hp)
					ts.append(float(r2.ttk) if float(r2.ttk) > 0.0 else TTK_MAX_SEC)
				var mt := _median(ts)
				md.append("| %s | %d막 | %.0f | %s |" % [String(PCatalog.enemy(String(tp)).name), act, hp, ("%.1f초" % mt) if mt < TTK_MAX_SEC else "미처치(%d초)" % int(TTK_MAX_SEC)])
		md.append("")

	var path := sub.out_path("res://docs/sim/TAIL_PROBE%s.md" % (("_" + tag.to_upper()) if tag != "" else ""))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(md))
		f.close()
	print("\n".join(md))
	print("")
	print("결과 파일: %s" % path)
	print("TAIL_PROBE_JSON " + JSON.stringify({ "tag": tag, "partial": sub.partial(), "rows": all_rows, "ttk": ttk_rows }))

	ok("측정이 실제로 이루어졌다(실행 %d회)" % measured, measured > 0, sub.summary())
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
