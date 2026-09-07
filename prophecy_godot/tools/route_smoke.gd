extends SceneTree
## 27경로 기술 스모크(계획서 §12 실행 비교): 구현된 테마 조합 전부 × 시작 기술 × 시드를 회차 봇(gradual/balanced)으로 완주 시도.
## 실패는 보스 패배·일반전 패배·진행 정체·기술 오류로 구분한다. 봇이 이겼다고 밸런스 승인이 아니다. 결과: docs/sim/ROUTE_SMOKE.md + ROUTE_SMOKE_JSON
## 환경 변수: PROPHECY_SIM_SEEDS("1") PROPHECY_ROUTE_STARTS("sword") PROPHECY_SIM_BOT("balanced") PROPHECY_ROUTE_LIMIT(경로 수 상한, 0=전부)

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1").split(","):
		seeds.append(int(s))
	var starts := _env("PROPHECY_ROUTE_STARTS", "sword").split(",")
	var pol := _env("PROPHECY_SIM_BOT", "balanced")
	var limit := int(_env("PROPHECY_ROUTE_LIMIT", "0"))
	var A1 := PRun.themes_for_act(1)
	var A2 := PRun.themes_for_act(2)
	var A3 := PRun.themes_for_act(3)
	var routes := []
	for a in A1:
		for b in A2:
			for c in A3:
				routes.append([String(a), String(b), String(c)])
	if limit > 0 and routes.size() > limit:
		routes = routes.slice(0, limit)
	var rows := []
	var md := "# 경로 스모크 (%s, 봇 %s, 시드 %s, 시작 %s)\n\n생성: `tools/route_smoke.gd`. 구현된 테마(보스 정의 존재)만 조합: 1막 %d × 2막 %d × 3막 %d = %d경로(목표 27). 봇 결과는 기술 스모크이며 사람 난이도·밸런스 승인이 아니다. 실패 구분: boss_lost(보스 패배·재도전 소진) / lost(일반전 패배로 정체) / stalled(진행 정체) / error(스크립트 오류).\n\n" % [Game.VERSION, pol, str(seeds), str(starts), A1.size(), A2.size(), A3.size(), routes.size()]
	md += "| 경로 | 시작 | 시드 | 결과 | 마지막 날 | 레벨 | 전투분 | 보스(초) | 패배 | 휴식 | 금화 | 제작 가능 재료(정산) |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	var t0 := Time.get_ticks_msec()
	for r in routes:
		var names := "%s→%s→%s" % [String(PCatalog.theme(r[0]).name), String(PCatalog.theme(r[1]).name), String(PCatalog.theme(r[2]).name)]
		for w in starts:
			for seed_v in seeds:
				var rec := PRunBot.simulate(seed_v, "gradual", { "start": String(w), "bot_policy": pol, "max_retries": 3, "route": r })
				var status := "cleared" if bool(rec.get("cleared", false)) else String(rec.get("stopReason", rec.get("bossStatus", "?")))
				var mats := str(rec.get("mats", ""))
				rows.append({ "route": r, "start": String(w), "seed": seed_v, "status": status, "day": int(rec.get("day", 0)), "level": int(rec.get("level", 0)), "combatMin": rec.get("combatMin", 0), "boss": rec.get("boss", ""), "losses": rec.get("losses", 0), "rests": rec.get("rests", 0), "gold": rec.get("gold", 0) })
				md += "| %s | %s | %d | %s | %d | %d | %s | %s | %s | %s | %s | %s |\n" % [names, String(w), seed_v, status, int(rec.get("day", 0)), int(rec.get("level", 0)), str(rec.get("combatMin", "")), str(rec.get("boss", "")), str(rec.get("losses", "")), str(rec.get("rests", "")), str(rec.get("gold", "")), mats]
				printerr("route_smoke: %s %s seed %d → %s (day %d)" % [names, String(w), seed_v, status, int(rec.get("day", 0))])
	md += "\n실행 벽시계: %.1f초. 미구현 테마(보스 없음)는 후보에서 제외되어 표에 없다.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var fa := FileAccess.open("res://docs/sim/ROUTE_SMOKE.md", FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("ROUTE_SMOKE_JSON " + JSON.stringify(rows))
	quit()
