extends SceneTree
## 3일차 성장 중단 빌드 vs 정상 성장 비교 — 실력별 조작 봇(novice/regular/skilled, PSkillBot) + 기존 정책(balanced) 기준.
## 사용자 지시(2026-09-07 4단계): "3일차 성장 중단 빌드와 정상 성장 빌드를 새 실력별 봇으로 비교. 받은 피해·휴식 횟수·보스전 공격 패턴·완주 시간을 보고. 봇이 이겼다고 체력부터 올리지 말 것".
## 봇은 가상 조작 모델이며 사람 보정 미완료(docs/BOT_FRAMEWORK.md). 어떤 수치도 밸런스 승인이 아니다. 결과: docs/sim/STOP3_SKILL.md + STOP3_SKILL_JSON
## 환경 변수: PROPHECY_SIM_SEEDS("1,2,3") PROPHECY_SIM_BOTS("balanced,novice,regular,skilled") PROPHECY_SIM_START("sword") PROPHECY_SIM_STOPDAY("3") PROPHECY_SIM_ROUTE("" = 시드 추첨 경로 | a,b,c) PROPHECY_SIM_OUT("res://docs/sim/STOP3_SKILL.md")

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _pat_text(p: Dictionary) -> String:
	var keys := p.keys()
	keys.sort_custom(func(a, b): return int(p[a]) > int(p[b]))
	var parts := []
	for k in keys.slice(0, 4):
		parts.append("%s %d" % [String(k), int(p[k])])
	return " · ".join(parts)

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1,2,3").split(","):
		seeds.append(int(s))
	var bots := _env("PROPHECY_SIM_BOTS", "balanced,novice,regular,skilled").split(",")
	var start := _env("PROPHECY_SIM_START", "sword")
	var stop_day := int(_env("PROPHECY_SIM_STOPDAY", "3"))
	var route := []
	if _env("PROPHECY_SIM_ROUTE", "") != "":
		for t in _env("PROPHECY_SIM_ROUTE", "").split(","):
			route.append(String(t))
	var rows := []
	var t0 := Time.get_ticks_msec()
	var md := "# 3일차 성장 중단 vs 정상 성장 — 실력별 봇 비교 (%s)\n\n" % Game.VERSION
	md += "생성: `tools/stop3_skill.gd`. 전략 gradual, 시작 %s, 시드 %s, 성장 중단일 %d(그 날 이후 출격 없음·상점만), 경로 %s. 봇: %s — novice/regular/skilled는 **가상 조작 모델(사람 보정 미완료)**, balanced는 기존 정책(비교 기준). 봇 결과는 사람 난이도·밸런스 승인이 아니며, 봇이 이긴다고 체력·수치를 올리지 않는다(사용자 지시).\n\n" % [start, str(seeds), stop_day, ("시드 추첨" if route.is_empty() else str(route)), str(bots)]
	md += "| 봇 | 시드 | 성장 | 결과 | 마지막 날 | Lv | 받은 피해(일반) | 휴식 | 패배 | 시간초과 | 전투분 | 보스(초·결과) | 보스 받은 피해 | 보스 패턴 상위 | 경로 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for b in bots:
		for seed_v in seeds:
			for stop in [0, stop_day]:
				var o := { "start": start, "bot_policy": String(b), "max_retries": 3, "stop_day": stop }
				if not route.is_empty():
					o.route = route
				var rec := PRunBot.simulate(seed_v, "gradual", o)
				var status := "cleared" if bool(rec.get("cleared", false)) else String(rec.get("stopReason", rec.get("bossStatus", "?")))
				var pats: Dictionary = rec.get("bossPatterns", {})
				var row := { "bot": String(b), "seed": seed_v, "stop": stop, "status": status, "day": int(rec.get("day", 0)), "level": int(rec.get("level", 0)), "taken": int(round(float(rec.get("taken", 0)))), "rests": int(rec.get("rests", 0)), "losses": int(rec.get("losses", 0)), "timeouts": int(rec.get("timeouts", 0)), "combatMin": rec.get("combatMin", 0), "boss": String(rec.get("boss", "")), "bossTaken": int(round(float(rec.get("bossTaken", 0)))), "bossSec": int(rec.get("bossSec", 0)), "patterns": pats, "route": rec.get("route", []) }
				rows.append(row)
				md += "| %s | %d | %s | %s | %d | %d | %d | %d | %d | %d | %s | %s | %d | %s | %s |\n" % [String(b), seed_v, ("정상" if stop == 0 else "%d일 중단" % stop), status, int(row.day), int(row.level), int(row.taken), int(row.rests), int(row.losses), int(row.timeouts), str(row.combatMin), String(row.boss), int(row.bossTaken), _pat_text(pats), "→".join((row.route as Array).map(func(t): return String(PCatalog.theme(String(t)).get("name", t))))]
				printerr("stop3_skill: %s seed %d stop %d → %s (day %d lv %d taken %d)" % [String(b), seed_v, stop, status, int(row.day), int(row.level), int(row.taken)])
	# 봇별 요약(정상 vs 중단)
	md += "\n## 봇별 요약 (평균)\n\n| 봇 | 성장 | 완주 | 평균 Lv | 평균 받은 피해(일반) | 평균 휴식 | 평균 보스 받은 피해 | 평균 보스 초 |\n|---|---|---|---|---|---|---|---|\n"
	for b in bots:
		for stop in [0, stop_day]:
			var sel := rows.filter(func(r): return String(r.bot) == String(b) and int(r.stop) == stop)
			if sel.is_empty():
				continue
			var n := float(sel.size())
			var cl := sel.filter(func(r): return String(r.status) == "cleared").size()
			var lv := 0.0
			var tk := 0.0
			var rs := 0.0
			var bt := 0.0
			var bs := 0.0
			for r in sel:
				lv += float(r.level)
				tk += float(r.taken)
				rs += float(r.rests)
				bt += float(r.bossTaken)
				bs += float(r.bossSec)
			md += "| %s | %s | %d/%d | %.1f | %.0f | %.1f | %.0f | %.0f |\n" % [String(b), ("정상" if stop == 0 else "%d일 중단" % stop), cl, sel.size(), lv / n, tk / n, rs / n, bt / n, bs / n]
	md += "\n읽는 법: '받은 피해'는 일반 전투 합계, '보스 받은 피해'는 관문 전투 합계(재도전 포함). 중단 빌드가 완주하면 후반이 봇에게 느슨하다는 뜻이지 사람에게도 그렇다는 뜻은 아니다. 완주 실패의 원인(보스 패배·시간 초과·정체)은 결과 열로 구분한다.\n실행 벽시계: %.1f초.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var fa := FileAccess.open(_env("PROPHECY_SIM_OUT", "res://docs/sim/STOP3_SKILL.md"), FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("STOP3_SKILL_JSON " + JSON.stringify(rows))
	quit()
