extends SceneTree
## 밀도 적용 현황표: 밀도 세트(일괄 ×5 기본 / roles 비교 후보)별로 지역 × 날짜 × 시간대(변주) × 더 깊이의 HTML 편성 → Godot 편성(종류별 전체 수·동시 상한·역할별 상한·배율·경험치·금화)을 표로 만든다.
## 실행: godot --headless --path prophecy_godot -s tools/formation_table.gd → docs/FORMATION_TABLE.md
## 값은 규칙 코드(PRun.encounter_waves → PFormation.from_waves, PFlow.encounter_opts)에서 그대로 읽는다(표를 위해 따로 계산하지 않음).

const REGIONS := ["forest", "ridge", "marsh", "den", "deep"]

func _init() -> void:
	var D := PCatalog.density()
	var SETS: Dictionary = D.get("sets", {})
	var md := "# 밀도 적용 현황 (godot-%s, PORT_BASELINE C4/Q1 잠정 규칙)\n\n" % Game.VERSION
	md += "생성: `tools/formation_table.gd`. 공통 규칙: 일반 적 전체 수 = HTML 웨이브 합 × 배율(정예 `elite`·구조물·보스 소환은 ×1), 동시 생존 상한 %d, 묶음 %d마리·간격 %.1f초, 종류별 동시 상한 %s (없는 종류는 전체 상한만). 경험치는 **종류별로** HTML 예산(단위값 × HTML 수)을 그 종류의 Godot 개체 수로 나눠 지급하므로 배율이 달라도 전투 전체 예산이 같다(정예는 ×1이라 단위값 그대로). 금화는 지역 범위 × 시간대 배율(전투 승리 시 굴림). 적 체력 배율은 지역 ×1, 4일차부터 정예 ×1.25.\n\n" % [int(D.alive_cap), int(D.group), float(D.interval), JSON.stringify(D.type_alive_cap)]
	var WS := PCatalog.world_stages()
	md += "세계 변화(사용자 합의 2026-09-07, 수치는 Codex 시험 제안): %s. 등급 %s. 마지막 열은 같은 편성을 1차(일반/붉은)·2차(붉은/변이)로 배정했을 때의 수(정예는 항상 일반, 경험치 예산 불변). 2단계부터 위험 임무 출격에 정예 +%d(잠정).\n\n" % [String(WS.get("note", "")), JSON.stringify(WS.get("tiers", {})), int(WS.get("risk_elite_extra", 1))]
	md += "위험 공격 동시 제한(전투 규칙): 늑대 돌진 동시 %d(준비·고정·실행 합산, 우두머리·소환 늑대 포함) · 보스전 소환 늑대 겹침 1 · 원거리(궁수 3·서리술사 2·포자 3·주술사 1·폭탄 3)·돌파(멧돼지 2)·지하(잠복충 2)·거미 2·도적 3·방패병 3·우두머리 2는 위 종류별 동시 상한이 곧 동시 공격 상한이다. **관찰 항목**: 동시 생존 상한은 잔류 투사체·거미줄·서리 장판·포자 구름의 수를 제한하지 않으므로 후반 전투(굴 5~6일, 심층)에서 이들이 얼마나 겹치는지는 별도 관찰이 필요하다(미측정).\n" % [int(PCatalog.enemy("wolf").dash.max_concurrent)]
	for set_id in ["", "roles"]:
		var set_key: String = String(set_id) if String(set_id) != "" else String(D.get("set_default", "uniform_x5"))
		var S: Dictionary = SETS.get(set_key, {})
		md += "\n## 밀도 세트 `%s` — %s%s\n\n" % [set_key, String(S.get("name", "")), (" (기본, 현재 비교 설정 — 최종 편성으로 확정하지 않음)" if set_id == "" else " (비교 후보, 2026-09-07 사용자 Q1 답변. 동시 상한은 같음)")]
		if S.has("role_class"):
			md += "| 종류 | 역할(실제 행동 기준) | 배율 | 근거 |\n|---|---|---|---|\n"
			var RC: Dictionary = S.role_class
			var MT: Dictionary = S.get("multiplier_by_type", {})
			for t in RC:
				md += "| %s | %s | ×%s | %s |\n" % [String(PCatalog.enemy(t).name), String(RC[t].role), str(MT.get(t, 1)), String(RC[t].reason)]
			md += "\n"
		md += "| 지역 | 일차 | 시간대(변주) | 더 깊이 | HTML 편성(웨이브 합) | Godot 전체 수 | 합계 HTML→Godot(배율) | 동시 상한 | 적용되는 종류별 상한 | 전투 경험치 예산(처치+지역) | 금화 | 적 체력 | 등급 1차(일반/붉은) · 2차(붉은/변이) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
		md += _rows(set_id)
	md += "\n관문 보스전: 편성 배율 적용 없음(보스 1 + 패턴 소환: 가시갈기 늑대 소환 2마리씩·겹침 1, 봉인 수호자 장치 3, 예언을 먹는 자 소환). 보스 체력 세트 hi = %s.\n" % JSON.stringify(PCatalog.boss_hp_sets()["hi"])
	var fa := FileAccess.open("res://docs/FORMATION_TABLE.md", FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print(md)
	quit()

func _rows(set_id: String) -> String:
	var W := PCatalog.world()
	var slots: Array = W.time_slots
	var md := ""
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
					if set_id != "":
						run.densitySet = set_id
					var sortie := { "regionId": rid, "deep": deep, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": 7, "day": day, "slot": maxi(0, int(v.slot)), "variant": (null if int(v.slot) < 0 else v) }
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
					var S1: Dictionary = PCatalog.world_stages().stages[1].mix
					var S2: Dictionary = PCatalog.world_stages().stages[2].mix
					var t1 := PFormation.tier_counts(PFormation.assign_tiers(f.units, S1))
					var t2 := PFormation.tier_counts(PFormation.assign_tiers(f.units, S2))
					md += "| %s | %d | %s | %s | %s | %s | %d → %d (×%.2f) | %d | %s | %.2f (처치 %.2f + 지역 %.2f) | %d~%d ×%.2f | 일반 ×%.2f 정예 ×%.2f | %d/%d · %d/%d |\n" % [String(r.name), day, slot_txt, ("예(+1/웨이브, 정예)" if deep else "-"), " · ".join(hc), " · ".join(gc), html_total, godot_total, float(godot_total) / maxf(1.0, float(html_total)), int(f.alive_cap), (" · ".join(caps) if caps.size() > 0 else "-"), xp + bonus, xp, bonus, int(r.reward.gold[0]), int(r.reward.gold[1]), gm, float(hm.normal), float(hm.elite), int(t1.get("normal", 0)), int(t1.get("red", 0)), int(t2.get("red", 0)), int(t2.get("apex", 0))]
	return md
