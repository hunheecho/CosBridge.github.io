extends SceneTree
## 10일 회차 성장 체크포인트 측정(지시 17 ④, 지시 5의 기준 DPS 근거).
## 출발 / 1막 말 / 2막 초 / 2막 말 / 3막 말에서 실제 빌드 전체를 기록하고, 같은 조건의 정지 단일 표적 DPS를 잰다.
## 레벨 숫자만 맞춘 비교가 아니라 그 시점의 실제 growth·장비·강화를 그대로 쓴다.
##
## 측정 방식(검토 문서 §3과 같은 조건): 30초, 중심 거리 80, 반지름 42, 체력 1e7 허수아비, 이동·회피·Q·E 없음, 장애물 없음.
## 넉백으로 표적이 밀리지 않게 매 단계 위치를 고정한다. 이것은 고정 조건 시험이며 사람 조작 재현이 아니다.
## 관문은 성장 곡선을 끝까지 보려고 스텁 승리로 통과시킨다(측정용 장치 — 보스 난이도 판정이 아니다).
##
## 결과: docs/sim/GROWTH_CHECKPOINTS.md + GROWTH_CHECKPOINTS_JSON
## 환경 변수: PROPHECY_SIM_SEEDS("1,2,3") PROPHECY_SIM_START("sword") PROPHECY_SIM_STRAT("gradual") PROPHECY_SIM_BOT("balanced") PROPHECY_SIM_ROUTE("a,b,c")

const STEP := 1.0 / 120.0
const MEASURE_SEC := 30.0
const TARGET_DIST := 80.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

## 정지 단일 표적 DPS: 그 시점의 실제 빌드로 30초. 표적은 매 단계 제자리 고정
func stationary_dps(run: Dictionary) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 1, "waves": [], "arena": "clearing", "region_id": "lab", "xp_kill_mult": 0.0, "chest": false })
	st.spawn_hold = true
	var p := st.player
	var e := st.spawn_enemy("wolf", p.x + TARGET_DIST, p.y)
	e.hp = 1.0e7
	e.hp_max = 1.0e7
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	var tx: float = e.x
	var ty: float = e.y
	var idle := { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }
	var n := int(MEASURE_SEC / STEP)
	for i in n:
		st.step(idle, STEP)
		e.x = tx
		e.y = ty
		e.vx = 0.0
		e.vy = 0.0
	var dealt: float = 1.0e7 - float(e.hp)
	var by_src := {}
	for k in st.metrics.dmg:
		by_src[String(k)] = round(float(st.metrics.dmg[k]) / MEASURE_SEC * 100.0) / 100.0
	return { "dps": round(dealt / MEASURE_SEC * 100.0) / 100.0, "dealt": round(dealt), "by_src": by_src, "mods": st.mod_report() }

func build_text(run: Dictionary) -> String:
	var g: Dictionary = run.growth
	var ws := []
	for w in g.weapons:
		ws.append("%s Lv%d%s" % [String(PCatalog.weapon(String(w.id)).name), int(w.level), ("[" + "+".join((w.mods as Array).map(func(m): return String(PCatalog.weapons()[String(w.id)].mods[m].name))) + "]") if (w.mods as Array).size() > 0 else ""])
	var eq := []
	for slot in run.equipment:
		if run.equipment[slot] != null:
			eq.append(PRun.equip_name(String(run.equipment[slot])))
	var cm := []
	for c in g.get("commons", {}):
		if int(g.commons[c]) > 0:
			cm.append("%s%d" % [String(PCatalog.commons()[String(c)].name), int(g.commons[c])])
	return "%s · Q Lv%d%s · 공용 %s · 강화 %d · 장비 %s" % [", ".join(ws), int(g.skills.q.level),
		(" · E %s Lv%d" % [String(PCatalog.skills()[String(g.skills.e.id)].name), int(g.skills.e.level)]) if g.skills.get("e", null) != null else "",
		(", ".join(cm) if cm.size() > 0 else "없음"), int(run.forge), (", ".join(eq) if eq.size() > 0 else "없음")]

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1,2,3").split(","):
		seeds.append(int(s))
	var start := _env("PROPHECY_SIM_START", "sword")
	var strat := _env("PROPHECY_SIM_STRAT", "gradual")
	var pol := _env("PROPHECY_SIM_BOT", "balanced")
	var route := []
	if _env("PROPHECY_SIM_ROUTE", "") != "":
		for t in _env("PROPHECY_SIM_ROUTE", "").split(","):
			route.append(String(t))
	# 체크포인트: 출발(1일차 시작) / 1막 말(3일 끝) / 2막 초(4일 관문 직후) / 2막 말(6일 끝) / 3막 말(9일 끝)
	var points := [{ "id": "start", "name": "출발", "day": 0 }, { "id": "act1_end", "name": "1막 말", "day": 3 },
		{ "id": "act2_begin", "name": "2막 초", "day": 4 }, { "id": "act2_end", "name": "2막 말", "day": 6 }, { "id": "act3_end", "name": "3막 말", "day": 9 }]
	var rows := []
	var t0 := Time.get_ticks_msec()
	for seed_v in seeds:
		for pt in points:
			var o := { "start": start, "bot_policy": pol, "max_retries": 3, "stub_gates": true }
			if not route.is_empty():
				o.route = route
			if int(pt.day) > 0:
				o.max_days = int(pt.day)
			var run: Dictionary
			if int(pt.day) == 0:
				run = PRun.new_run(seed_v, start, "", { "route": route })
			else:
				var rec := PRunBot.simulate(seed_v, strat, o)
				run = rec.get("run_state", {})
			if run.is_empty():
				printerr("체크포인트 실패: seed %d %s" % [seed_v, String(pt.name)])
				continue
			var m := stationary_dps(run)
			var row := { "seed": seed_v, "point": String(pt.id), "name": String(pt.name), "day": int(run.get("day", 1)), "level": int(run.growth.level),
				"dps": float(m.dps), "by_src": m.by_src, "build": build_text(run), "gold": int(run.get("gold", 0)) }
			rows.append(row)
			printerr("checkpoint: seed %d %s day %d Lv%d → DPS %.1f" % [seed_v, String(pt.name), int(row.day), int(row.level), float(row.dps)])
	# 집계
	var by_point := {}
	for r in rows:
		var k := String(r.point)
		if not by_point.has(k):
			by_point[k] = []
		(by_point[k] as Array).append(r)
	var md := "# 10일 회차 성장 체크포인트 · 정지 단일 표적 DPS (%s)\n\n" % Game.VERSION
	md += "생성: `tools/growth_checkpoints.gd`. 시드 %s · 시작 %s · 전략 %s · 봇 %s · 경로 %s.\n" % [str(seeds), start, strat, pol, ("시드 추첨" if route.is_empty() else str(route))]
	md += "측정 조건은 검토 문서 §3과 같다: 30초 · 중심 거리 80 · 정지 허수아비(체력 1e7) · 이동/회피/Q/E 없음 · 매 단계 표적 위치 고정. **고정 조건 시험이며 사람 조작·실전 DPS가 아니다.**\n"
	md += "성장 곡선을 끝까지 보기 위해 관문은 스텁 승리로 통과시켰다(측정용 장치, 보스 난이도 판정 아님). 모든 값은 시험값이다.\n\n"
	md += "| 체크포인트 | 시드 | 일차 | Lv | 정지 DPS | 빌드 |\n|---|---|---|---|---|---|\n"
	for pt in points:
		for r in by_point.get(String(pt.id), []):
			md += "| %s | %d | %d | %d | %.1f | %s |\n" % [String(r.name), int(r.seed), int(r.day), int(r.level), float(r.dps), String(r.build)]
	md += "\n## 체크포인트 평균(적 체력표의 기준 DPS 근거)\n\n| 체크포인트 | 평균 Lv | 평균 정지 DPS | 표본 |\n|---|---|---|---|\n"
	var avg := {}
	for pt in points:
		var arr: Array = by_point.get(String(pt.id), [])
		if arr.is_empty():
			continue
		var lv := 0.0
		var dp := 0.0
		for r in arr:
			lv += float(r.level)
			dp += float(r.dps)
		var a := dp / float(arr.size())
		avg[String(pt.id)] = round(a * 10.0) / 10.0
		md += "| %s | %.1f | %.1f | %d |\n" % [String(pt.name), lv / float(arr.size()), a, arr.size()]
	md += "\n읽는 법: 역할별 체력표(`data/pacing.json` enemy_hp)의 `ref_dps.act2`는 2막 초~말 구간, `act3`은 3막 말 구간의 이 값을 기준으로 잡는다. "
	md += "적 체력 = 기준 DPS × 역할별 목표 집중 시간이며, 실행 중 플레이어 DPS를 읽어 맞추지 않는 고정 표다.\n"
	md += "\n실행 벽시계: %.1f초.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var fa := FileAccess.open(_env("PROPHECY_SIM_OUT", "res://docs/sim/GROWTH_CHECKPOINTS.md"), FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("GROWTH_CHECKPOINTS_JSON " + JSON.stringify({ "rows": rows, "avg": avg }))
	quit()
