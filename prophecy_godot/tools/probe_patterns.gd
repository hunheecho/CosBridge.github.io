extends SceneTree
## §11-B 신규 공격 패턴 14개가 **실제 전투에서 쓰이는가**를 재는 계측 도구(판정하지 않는다).
## 실행: godot --headless --path prophecy_godot -s tools/probe_patterns.gd
##
## 무엇을 재는가
##  · 주무기별(활 = 거리를 두고 걸으며 쏘는 놀이 / 검 = 붙어서 치는 놀이) 패턴 발동 횟수
##  · 패턴이 **시작 조건을 만족한 시간**(초)과 실제 발동 횟수를 나란히 — 0회가 '조건이 안 섰다'인지 '조건은 섰는데 안 골랐다'인지 가른다
##  · 정예와 플레이어 사이 거리의 분포(패턴 시작 조건이 거리라서)
## 적을 죽지 않게 붙들어 둔다(계측 전용). 규칙·수치는 하나도 바꾸지 않는다.

const STEP := 1.0 / 120.0
const SEC := 45.0
const WEAPONS := ["bow", "sword"]

func fight(tp: String, wid: String, seed_v: int) -> Dictionary:
	var g := PGrowth.new_growth(wid)
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": 1, "fixed_build": true })
	st.spawn_hold = true
	var e := st.spawn_enemy(tp, st.player.x + 300.0, st.player.y)
	e.hp_max = 1.0e6
	e.hp = e.hp_max
	var bot := PBot.new("balanced")
	var open := {}      # 패턴 id → 시작 조건이 서 있던 시간(초)
	var ready := {}     # 패턴 id → 재사용이 끝나 있던 시간(초)
	var appr := 0.0     # approach 상태(패턴을 고를 수 있는 상태)에 있던 시간
	var dsum := 0.0
	var dmin := 9999.0
	var dmax := 0.0
	var n := int(round(SEC / STEP))
	for i in n:
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		var dd := PGeom.dist(e.x, e.y, st.player.x, st.player.y)
		dsum += dd
		dmin = minf(dmin, dd)
		dmax = maxf(dmax, dd)
		if String(e.state) == "approach":
			appr += STEP
		for row in PEnemiesNew.NEW_PATTERNS.get(tp, []):
			var r: Dictionary = row
			var id := String(r.id)
			if float(e.get(String(r.cd), 9.0)) <= 0.0:
				ready[id] = float(ready.get(id, 0.0)) + STEP
				if String(e.state) == "approach":
					open[id] = float(open.get(id, 0.0)) + STEP
	return { "uses": PEnemiesNew.pattern_uses(e).duplicate(), "open": open, "ready": ready,
		"appr": appr, "dmean": dsum / float(n), "dmin": dmin, "dmax": dmax }

func _init() -> void:
	print("[§11-B 신규 패턴 계측] 정예 1마리 대 봇 '균형' · 주무기 %s · %.0f초 · 시드 1" % [str(WEAPONS), SEC])
	print("")
	print("| 정예 | 주무기 | 거리(최소/평균/최대) | approach 시간 | 패턴 | 재사용 준비된 시간 | approach에서 준비된 시간 | 발동 |")
	print("|---|---|---|---:|---|---:|---:|---:|")
	for tp in PEnemiesNew.ELITE_TYPES:
		var t := String(tp)
		var nm := String(PCatalog.enemy(t).name)
		for wid in WEAPONS:
			var r := fight(t, String(wid), 1)
			for row in PEnemiesNew.NEW_PATTERNS.get(t, []):
				var pr: Dictionary = row
				var id := String(pr.id)
				print("| %s | %s | %.0f / %.0f / %.0f | %.1f초 | %s | %.1f초 | %.1f초 | %d회 |" % [
					nm, String(wid), float(r.dmin), float(r.dmean), float(r.dmax), float(r.appr), id,
					float((r.ready as Dictionary).get(id, 0.0)), float((r.open as Dictionary).get(id, 0.0)),
					int((r.uses as Dictionary).get(id, 0))])
	print("")
	print("읽는 법: '재사용 준비된 시간'은 길고 'approach에서 준비된 시간'이 0에 가까우면 — 그 정예가 다른 연계에 묶여 approach로 돌아오지 못한 것이다.")
	print("둘 다 길고 발동이 0이면 — 거리 조건이 서지 않은 것이다(거리 칸을 보라).")
	quit(0)
