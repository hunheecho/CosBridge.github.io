extends SceneTree
## 제작 재료 접근성·경제 기회비용 측정(실제 회차 경로, 회차 봇). 초안 §7·사용자 지시(2026-09-07 4단계): "제작 재료 접근성과 경제 기회비용도 실제 회차 경로로 확인".
## 강제 재료 지급 없음. 봇은 제작을 하지 않으므로(기존 거점 봇: 기술·강화·장비만) 결과는 "회차 중·끝에 손에 있던 재료·장비로 어떤 제작이 가능했는가"이며 사람 플레이 기록이 아니다.
## 비용 = 수수료 + 소비 장비의 판매가(기회비용) + 재료 판매 포기분(초안: 수수료만 보고 판단하지 않는다). 결과: docs/sim/CRAFT_ECONOMY.md + CRAFT_ECONOMY_JSON
## 환경 변수: PROPHECY_SIM_SEEDS("1,2") PROPHECY_SIM_BOT("balanced") PROPHECY_SIM_START("sword") PROPHECY_SIM_STRAT("gradual") PROPHECY_CRAFT_ROUTES("all" = 테마 9종이 모두 들어가는 경로 9개 | a,b,c;d,e,f) PROPHECY_SIM_OUT("res://docs/sim/CRAFT_ECONOMY.md")

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _routes() -> Array:
	var spec := _env("PROPHECY_CRAFT_ROUTES", "all")
	var out := []
	if spec != "all":
		for r in spec.split(";"):
			out.append(Array(r.split(",")).map(func(t): return String(t)))
		return out
	var A1 := PRun.themes_for_act(1)
	var A2 := PRun.themes_for_act(2)
	var A3 := PRun.themes_for_act(3)
	var base := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)]
	out.append(base)
	for t in A1:
		if String(t) != String(base[0]):
			out.append([String(t), String(base[1]), String(base[2])])
	for t in A2:
		if String(t) != String(base[1]):
			out.append([String(base[0]), String(t), String(base[2])])
	for t in A3:
		if String(t) != String(base[2]):
			out.append([String(base[0]), String(base[1]), String(t)])
	var alt1 := A1.filter(func(t): return String(t) != String(base[0]))
	var alt2 := A2.filter(func(t): return String(t) != String(base[1]))
	var alt3 := A3.filter(func(t): return String(t) != String(base[2]))
	for i in mini(alt1.size(), mini(alt2.size(), alt3.size())): # 대체 테마끼리 묶인 경로(재료 성향이 다른 조합)
		out.append([String(alt1[i]), String(alt2[i]), String(alt3[i])])
	return out

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1,2").split(","):
		seeds.append(int(s))
	var pol := _env("PROPHECY_SIM_BOT", "balanced")
	var start := _env("PROPHECY_SIM_START", "sword")
	var strat := _env("PROPHECY_SIM_STRAT", "gradual") # gradual(기본) | deep(더 깊이 적극: 정예 → 송곳니) | mission | risky …
	var routes := _routes()
	var CE := PCatalog.crafted_equipment()
	var M := PCatalog.materials()
	var rows := []
	var reach := {} # recipe → { full, partial, matsN, matsBy, matsBy7 }
	for id in CE:
		reach[String(id)] = { "full": 0, "partial": 0, "matsN": 0, "matsBy": 0, "matsBy7": 0 }
	var t0 := Time.get_ticks_msec()
	var md := "# 제작 재료 접근성·경제 기회비용 (%s, 봇 %s, 전략 %s, 시작 %s, 시드 %s)\n\n" % [Game.VERSION, pol, strat, start, str(seeds)]
	md += "생성: `tools/craft_economy.gd`. 회차 봇(전략 %s)이 실제 경로를 완주한 뒤 손에 남은 재료·장비·금화로 제작 6종의 도달 가능성을 센다. 봇은 제작하지 않으며(거점 봇 규칙: 기술·강화·장비 구매만) 강제 재료 지급도 없다. 송곳니는 정예 처치에서만 나오므로 위험 조건 임무·더 깊이·강적의 흔적을 받지 않는 gradual 전략은 송곳니 0이다(deep 전략 표와 비교). 사람 플레이 기록이 아니다.\n\n" % strat
	md += "## 제작법과 비용 (초안: 수수료 + 소비 장비 판매 기본가 + 재료 판매 포기분)\n\n| 제작품 | 재료 장비 | 재료 | 수수료 | 소비 장비 판매 기본가 | 재료 판매 포기분 | 실제 비용 합계 |\n|---|---|---|---|---|---|---|\n"
	var cost_of := {}
	for id in CE:
		var d: Dictionary = CE[id]
		var rc: Dictionary = d.recipe
		var eq_sell := 0
		var eq_names := []
		for e in rc.get("equipment", []):
			eq_sell += PRun.sell_base_list(String(e)) # 승인된 판매 계산(구매가 × sellRate). 옛 고정표 아님
			eq_names.append(PRun.equip_name(String(e)))
		var mat_sell := 0
		var mat_names := []
		for m in rc.get("mats", {}):
			mat_sell += int(M[m].sell) * int(rc.mats[m])
			mat_names.append("%s %d" % [String(M[m].name), int(rc.mats[m])])
		var fee := int(rc.get("fee", 0))
		cost_of[String(id)] = fee + eq_sell + mat_sell
		md += "| %s | %s | %s | %d | %d | %d | %d |\n" % [String(d.name), ", ".join(eq_names), ", ".join(mat_names), fee, eq_sell, mat_sell, fee + eq_sell + mat_sell]
	md += "\n## 회차별 결과\n\n| 경로 | 시드 | 결과 | Lv | 최종 금화 | 금화 수입(최종+지출) | 가죽/철/포자/송곳니 | 즉시 제작 가능(종료 시) | 재료 일부 | 재료 충족 일차(장비 제외) | 구매 장비 |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in routes:
		var names := "→".join((r as Array).map(func(t): return String(PCatalog.theme(String(t)).get("name", t))))
		for seed_v in seeds:
			var rec := PRunBot.simulate(seed_v, strat, { "start": start, "bot_policy": pol, "max_retries": 3, "route": r })
			var status := "cleared" if bool(rec.get("cleared", false)) else String(rec.get("stopReason", rec.get("bossStatus", "?")))
			var mats: Dictionary = rec.get("mats", {})
			var cr: Array = rec.get("craftable", [])
			var pt: Array = rec.get("craftPartial", [])
			for id in cr:
				reach[String(id)].full += 1
			for id in pt:
				reach[String(id)].partial += 1
			var income := int(rec.get("gold", 0)) + int(rec.get("goldSpent", 0))
			var eq_parts := []
			for eid in rec.get("equipBought", []):
				eq_parts.append(PRun.equip_name(String(eid)))
			var eq_txt := ", ".join(eq_parts) if not eq_parts.is_empty() else "-"
			var by_day: Array = rec.get("matsByDay", [])
			var first_day := {} # 제작법별 재료(장비 제외)가 처음 충족된 날(하루 종료 시점 기준)
			var fd_parts := []
			for id in CE:
				var rc: Dictionary = CE[id].recipe
				var fd := 0
				for snap in by_day:
					var okm := true
					for m in rc.get("mats", {}):
						if int((snap.mats as Dictionary).get(m, 0)) < int(rc.mats[m]):
							okm = false
					if okm:
						fd = int(snap.day)
						break
				first_day[String(id)] = fd
				if fd > 0:
					reach[String(id)].matsBy = int(reach[String(id)].matsBy) + fd
					reach[String(id)].matsN = int(reach[String(id)].matsN) + 1
					if fd <= 6:
						reach[String(id)].matsBy7 = int(reach[String(id)].matsBy7) + 1
					fd_parts.append("%s %d일" % [String(CE[id].name), fd])
			rows.append({ "route": r, "seed": seed_v, "status": status, "level": int(rec.get("level", 0)), "gold": int(rec.get("gold", 0)), "income": income, "mats": mats, "craftable": cr, "partial": pt, "equipment": eq_txt, "matsFirstDay": first_day })
			md += "| %s | %d | %s | %d | %d | %d | %d/%d/%d/%d | %s | %s | %s | %s |\n" % [names, seed_v, status, int(rec.get("level", 0)), int(rec.get("gold", 0)), income, int(mats.get("pelt", 0)), int(mats.get("iron", 0)), int(mats.get("spore", 0)), int(mats.get("fang", 0)), ", ".join(cr.map(func(i): return String(CE[i].name))) if not cr.is_empty() else "-", ", ".join(pt.map(func(i): return String(CE[i].name))) if not pt.is_empty() else "-", ", ".join(fd_parts) if not fd_parts.is_empty() else "-", eq_txt]
			printerr("craft_economy: %s seed %d → %s craftable=%s partial=%s mats=%s" % [names, seed_v, status, str(cr), str(pt), str(mats)])
	var n := rows.size()
	md += "\n## 도달 가능성 요약 (%d회차)\n\n| 제작품 | 즉시 제작 가능 회차(종료 시) | 재료 일부 회차 | 재료(장비 제외) 충족 회차 | 재료 충족 평균 일차 | 7일차 관문 전(6일차까지) 충족 | 실제 비용 | 평균 금화 수입 대비 |\n|---|---|---|---|---|---|---|---|\n" % n
	var income_sum := 0
	for row in rows:
		income_sum += int(row.income)
	var avg_income: float = float(income_sum) / maxf(1.0, float(n))
	for id in CE:
		var rr: Dictionary = reach[String(id)]
		var mn := int(rr.matsN)
		md += "| %s | %d/%d | %d/%d | %d/%d | %s | %d/%d | %d | %.0f%% |\n" % [String(CE[id].name), int(rr.full), n, int(rr.partial), n, mn, n, ("%.1f" % (float(rr.matsBy) / float(mn))) if mn > 0 else "-", int(rr.matsBy7), n, int(cost_of[String(id)]), 100.0 * float(cost_of[String(id)]) / maxf(1.0, avg_income)]
	md += "\n읽는 법: '즉시 제작 가능'은 회차 종료 시점(10일차 관문 뒤)에 재료 장비·재료·금화가 모두 있는 경우. '재료 충족 일차'는 재료만(장비 제외) 처음 모인 하루 종료 시점이라 재료 장비 구매 여부는 별도다(봇은 빈 슬롯 우선으로 장비를 사며 특정 장비를 노리지 않는다). 송곳니는 정예 처치에서만 나온다. 제작이 0회여도 결함이 아니며(초안: 1회차 제작 0~2회 관찰 목표), 재료를 파는 편이 이득인지는 '실제 비용 합계 vs 제작품 효과'를 사람이 판단할 항목이다.\n실행 벽시계: %.1f초.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var fa := FileAccess.open(_env("PROPHECY_SIM_OUT", "res://docs/sim/CRAFT_ECONOMY.md"), FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("CRAFT_ECONOMY_JSON " + JSON.stringify(rows))
	quit()
