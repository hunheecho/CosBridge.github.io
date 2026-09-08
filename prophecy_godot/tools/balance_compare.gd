extends SceneTree
## 개편 원인 분리 비교(지시 17 ⑤⑥). 같은 경로·시드·영구 성장 조건에서 다음 축을 나눠 잰다.
##  변형(PROPHECY_PACING): off(개편 전) / counts(적 수·동시 상한·혼합 편성만) / hp(적·보스 체력표만) / full(통합)
##  성장: 정상 / 3일차 이후 성장 중단
##  조작: 기존 정책(balanced) + 실력 봇(novice·regular·skilled)
## 기록: 완주 여부·마지막 날·레벨·전투 시간·받은 피해·휴식(선택/강제)·금화·지원 적만 남은 시간·후반 1~2마리 시간·대상 없는 대기·동시 최대.
## 봇은 가상 조작 모델이고 사람 보정 미완료다. 어떤 값도 사람이 승인한 균형값이 아니다.
## 결과: docs/sim/BALANCE_COMPARE.md + BALANCE_COMPARE_JSON
## 환경 변수: PROPHECY_SIM_SEEDS("1,2") PROPHECY_SIM_BOTS("balanced,regular,skilled") PROPHECY_CMP_VARIANTS("off,counts,hp,full") PROPHECY_SIM_STOPDAY("3")

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func run_one(seed_v: int, bot: String, stop_day: int, route: Array) -> Dictionary:
	var o := { "start": "sword", "bot_policy": bot, "max_retries": 3, "route": route }
	if stop_day > 0:
		o.stop_day = stop_day
	return PRunBot.simulate(seed_v, "gradual", o)

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1,2").split(","):
		seeds.append(int(s))
	var bots := _env("PROPHECY_SIM_BOTS", "balanced,regular,skilled").split(",")
	var variants := _env("PROPHECY_CMP_VARIANTS", "off,counts,hp,full").split(",")
	var stop_day := int(_env("PROPHECY_SIM_STOPDAY", "3"))
	var route := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)]
	var cur := PPacing.variant()
	var rows := []
	var t0 := Time.get_ticks_msec()
	for v in variants:
		OS.set_environment("PROPHECY_PACING", String(v))
		for bot in bots:
			for seed_v in seeds:
				for stop in [0, stop_day]:
					var rec := run_one(seed_v, String(bot), stop, route)
					var status := "cleared" if bool(rec.get("cleared", false)) else String(rec.get("stopReason", "?"))
					rows.append({ "variant": String(v), "bot": String(bot), "seed": seed_v, "stop": stop, "status": status,
						"day": int(rec.get("day", 0)), "level": int(rec.get("level", 0)), "combatMin": rec.get("combatMin", 0),
						"taken": int(round(float(rec.get("taken", 0)))), "bossTaken": int(round(float(rec.get("bossTaken", 0)))),
						"restChosen": int(rec.get("restChosen", 0)), "restForced": int(rec.get("restForced", 0)),
						"gold": int(rec.get("gold", 0)), "goldSpent": int(rec.get("goldSpent", 0)),
						"losses": int(rec.get("losses", 0)), "timeouts": int(rec.get("timeouts", 0)),
						"supportOnly": rec.get("supportOnlySec", 0), "thinTail": rec.get("thinTailSec", 0), "noTarget": rec.get("noTargetSec", 0), "maxAlive": int(rec.get("maxAlive", 0)),
						"boss": String(rec.get("boss", "")) })
					printerr("cmp: %s %s seed %d stop %d → %s (day %d lv %d taken %d)" % [String(v), String(bot), seed_v, stop, status, int(rows[rows.size() - 1].day), int(rows[rows.size() - 1].level), int(rows[rows.size() - 1].taken)])
	OS.set_environment("PROPHECY_PACING", cur)
	var md := "# 개편 원인 분리 비교 (%s)\n\n" % Game.VERSION
	md += "생성: `tools/balance_compare.gd`. 경로 고정 %s · 시드 %s · 전략 gradual · 영구 성장 없음.\n" % [str(route), str(seeds)]
	md += "축: **변형**(off 개편 전 / counts 적 수·동시 상한·혼합 편성만 / hp 적·보스 체력표만 / full 통합) × **봇**(balanced 기존 정책, novice·regular·skilled 실력 프로필) × **성장**(정상 / %d일차 중단).\n" % stop_day
	md += "금화 감축·반복 탐험·사건·제단은 모든 변형에 공통 적용된다(비교 축이 아니다). **봇 결과는 가상 조작 모델이며 사람 보정 미완료 — 밸런스 승인이 아니다.**\n\n"
	md += "| 변형 | 봇 | 시드 | 성장 | 결과 | 마지막 날 | Lv | 전투분 | 받은 피해 | 보스 피해 | 휴식(선택/강제) | 금화 | 패배 | 지원만(초) | 후반 1~2(초) | 대상 없음(초) | 동시 최대 |\n"
	md += "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in rows:
		md += "| %s | %s | %d | %s | %s | %d | %d | %s | %d | %d | %d/%d | %d | %d | %s | %s | %s | %d |\n" % [
			String(r.variant), String(r.bot), int(r.seed), ("정상" if int(r.stop) == 0 else "%d일 중단" % int(r.stop)), String(r.status),
			int(r.day), int(r.level), str(r.combatMin), int(r.taken), int(r.bossTaken), int(r.restChosen), int(r.restForced), int(r.gold), int(r.losses),
			str(r.supportOnly), str(r.thinTail), str(r.noTarget), int(r.maxAlive)]
	md += "\n## 변형별 요약(평균)\n\n| 변형 | 완주 | 평균 마지막 날 | 평균 Lv | 평균 전투분 | 평균 받은 피해 | 평균 금화 | 강제 휴식 | 지원만(초) | 후반 1~2(초) |\n|---|---|---|---|---|---|---|---|---|---|\n"
	for v in variants:
		var sel := rows.filter(func(r): return String(r.variant) == String(v))
		if sel.is_empty():
			continue
		var n := float(sel.size())
		var cl := sel.filter(func(r): return String(r.status) == "cleared").size()
		var day := 0.0
		var lv := 0.0
		var cm := 0.0
		var tk := 0.0
		var gd := 0.0
		var rf := 0.0
		var so := 0.0
		var tt := 0.0
		for r in sel:
			day += float(r.day)
			lv += float(r.level)
			cm += float(r.combatMin)
			tk += float(r.taken)
			gd += float(r.gold)
			rf += float(r.restForced)
			so += float(r.supportOnly)
			tt += float(r.thinTail)
		md += "| %s | %d/%d | %.1f | %.1f | %.1f | %.0f | %.0f | %.1f | %.1f | %.1f |\n" % [String(v), cl, sel.size(), day / n, lv / n, cm / n, tk / n, gd / n, rf / n, so / n, tt / n]
	md += "\n읽는 법: off와 counts의 차이는 적 수·동시 상한·혼합 편성에서만 나오고, off와 hp의 차이는 체력표에서만 나온다. full은 둘 다다. "
	md += "보스 행동 개편은 별도 축이며 `docs/sim/BOSS_PACE.md`에서 잰다. 봇이 이겼다고 체력을 올리거나 졌다고 내리지 않는다.\n"
	md += "\n실행 벽시계: %.1f초.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var fa := FileAccess.open(_env("PROPHECY_SIM_OUT", "res://docs/sim/BALANCE_COMPARE.md"), FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("BALANCE_COMPARE_JSON " + JSON.stringify(rows))
	quit()
