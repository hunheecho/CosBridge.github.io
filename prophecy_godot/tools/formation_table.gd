extends SceneTree
## 밀도 적용 현황표: 지역 × 날짜 × 시간대(변주) × 더 깊이별로 HTML 편성 → Godot 편성(종류별 전체 수·동시 상한·역할별 상한·배율·경험치·금화)을 표로 만든다.
## 실행: godot --headless --path prophecy_godot -s tools/formation_table.gd → docs/FORMATION_TABLE.md
## 값은 규칙 코드(PRun.encounter_waves → PFormation.from_waves, PFlow.encounter_opts)에서 그대로 읽는다(표를 위해 따로 계산하지 않음).

const REGIONS := ["forest", "ridge", "marsh", "den", "deep"]

func _init() -> void:
	var W := PCatalog.world()
	var D := PCatalog.density()
	var slots: Array = W.time_slots
	var md := "# 밀도 적용 현황 (godot-%s, PORT_BASELINE C4/Q1 잠정 규칙)\n\n" % Game.VERSION
	md += "생성: `tools/formation_table.gd`. 규칙: 일반 적 전체 수 = HTML 웨이브 합 × %.0f(정예 `elite`·구조물·보스 제외 → ×1), 동시 생존 상한 %d, 묶음 %d마리·간격 %.1f초, 종류별 동시 상한 %s (없는 종류는 전체 상한만). 경험치 예산은 HTML 편성 기준(처치 1마리 = HTML 단위값 ÷ 배율)이라 개체 수에 비례하지 않는다. 금화는 지역 범위 × 시간대 배율(전투 승리 시 굴림). 적 체력 배율은 지역 ×1, 4일차부터 정예 ×1.25.\n\n" % [float(D.multiplier), int(D.alive_cap), int(D.group), float(D.interval), JSON.stringify(D.type_alive_cap)]
	md += "위험 공격 동시 제한(전투 규칙): 늑대 돌진 동시 %d(준비·고정·실행 합산, 우두머리·소환 늑대 포함) · 보스전 소환 늑대 겹침 1 · 원거리(궁수 3·서리술사 2·포자 3·주술사 1·폭탄 3)·돌파(멧돼지 2)·지하(잠복충 2)·거미 2·도적 3·방패병 3·우두머리 2는 위 종류별 동시 상한이 곧 동시 공격 상한이다.\n\n" % [int(PCatalog.enemy("wolf").dash.max_concurrent)]
	md += "| 지역 | 일차 | 시간대(변주) | 더 깊이 | HTML 편성(웨이브 합) | Godot 전체 수 | 합계 HTML→Godot(배율) | 동시 상한 | 적용되는 종류별 상한 | 전투 경험치 예산(처치+지역) | 금화 | 적 체력 |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for rid in REGIONS:
		var DW: Dictionary = W.day_waves[rid]
		var days := DW.keys()
		days.sort_custom(func(a, b): return int(a) < int(b))
		for dk in days:
			var day := int(dk)
			var variants := [{ "slot": -1 }]
			for s in 5:
				var v := PRun.slot_variant(rid, s)
				if not v.is_empty():
					variants.append(v)
			for v in variants:
				for deep in [false, true]:
					if deep and int(v.slot) >= 0:
						continue
					var run := PRun.new_run(1, "sword")
					run.day = day
					var sortie := { "regionId": rid, "deep": deep, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 7, "day": day, "slot": maxi(0, int(v.slot)), "variant": (null if int(v.slot) < 0 else v) }
					var waves := PRun.encounter_waves(rid, deep, run, sortie)
					var st := PFlow.make_encounter(run, sortie)
					var f: Dictionary = st.formation
					var html_total := 0
					var godot_total := 0
					var hc := []
					var gc := []
					var caps := []
					var xp := 0.0
					for t in f.html_counts:
						html_total += int(f.html_counts[t])
						godot_total += int(f.godot_counts[t])
						hc.append("%s %d" % [String(PCatalog.enemy(t).name), int(f.html_counts[t])])
						gc.append("%s %d" % [String(PCatalog.enemy(t).name), int(f.godot_counts[t])])
						if (f.type_caps as Dictionary).has(t):
							caps.append("%s %d" % [String(PCatalog.enemy(t).name), int(f.type_caps[t])])
						xp += float(f.xp_map[t]) * float(f.godot_counts[t])
					var bonus := PRun.region_bonus_xp(run, rid, deep)
					var r := PCatalog.region(rid)
					var gm: float = float(v.get("goldMult", 1.0)) if int(v.slot) >= 0 else 1.0
					var hm := PRun.hp_mult_for(run, rid, deep)
					var slot_txt := "기본" if int(v.slot) < 0 else "%s(%s%s)" % [String(slots[int(v.slot)]), String(v.name), (" ← 저녁에서 이동" if v.has("remappedFrom") else "")]
					md += "| %s | %d | %s | %s | %s | %s | %d → %d (×%.2f) | %d | %s | %.2f (처치 %.2f + 지역 %.2f) | %d~%d ×%.2f | 일반 ×%.2f 정예 ×%.2f |\n" % [String(r.name), day, slot_txt, ("예(+1/웨이브, 정예)" if deep else "-"), " · ".join(hc), " · ".join(gc), html_total, godot_total, float(godot_total) / maxf(1.0, float(html_total)), int(f.alive_cap), (" · ".join(caps) if caps.size() > 0 else "-"), xp + bonus, xp, bonus, int(r.reward.gold[0]), int(r.reward.gold[1]), gm, float(hm.normal), float(hm.elite)]
	md += "\n관문 보스전: 편성 배율 적용 없음(보스 1 + 패턴 소환: 가시갈기 늑대 소환 2마리씩·겹침 1, 봉인 수호자 장치 3, 예언을 먹는 자 소환). 보스 체력 세트 hi = %s.\n" % JSON.stringify(PCatalog.boss_hp_sets()["hi"])
	var fa := FileAccess.open("res://docs/FORMATION_TABLE.md", FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print(md)
	quit()
