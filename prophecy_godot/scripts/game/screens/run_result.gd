class_name PRunResultScreen
extends PScreen
## 회차 결과(HTML bossVictory 최종): 보스 기록·재도전·레벨·날짜·자동기술·장비 + 피해 통계 4보기(PStats.views). 새 회차 / 제목 / 이번 빌드로 다시 도전.

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	var g: Dictionary = r.growth
	var stages := PRun.stage_count(r)
	var cleared: bool = String(r.phase) == "cleared"
	var main_cleared: bool = cleared or bool(r.get("mainCleared", false))
	heading(("회차 완주." if stages > 1 else "예언의 날을 넘겼다.") if main_cleared else "회차 결과")
	top.add_child(PUi.rich("[color=#6a7078]%s[/color]" % PGlossaryTip.esc(PRun.settings_record(r)), 11)) # 지시 2: 결과·검증 기록에 실제 일정·밀도·상한·밸런스·시드
	top.add_child(PUi.rich("[color=#9ea8b8]%s · %d일차 · 출격 %d회 · 전투 %d(승 %d · 패 %d)[/color]" % [PGlossaryTip.esc(PUi.settings_short(r)), int(r.day), int(r.get("sortieCount", 0)), int(r.stats.encounters), int(r.stats.wins), int(r.stats.losses)], 12))
	var c := PUi.card("회차 결과")
	var box: VBoxContainer = c.box
	var wn := []
	for w in g.weapons:
		wn.append("%s Lv%d" % [String(PCatalog.weapon(String(w.id)).name), int(w.level)])
	var e = g.skills.get("e", null)
	box.add_child(PUi.rich("Lv %d · 자동기술: [b]%s[/b] · Q Lv%d%s" % [int(g.level), ", ".join(wn), int(g.skills.q.level), (" · E %s Lv%d" % [String(PCatalog.skills()[String(e.id)].name), int(e.level)]) if e != null else ""], 13))
	var eq := []
	for sl in PCatalog.world().equip_slots:
		var id = r.equipment.get(String(sl), null)
		if id != null:
			eq.append(PRun.equip_name(String(id)))
	box.add_child(PUi.rich("장비: [b]%s[/b]%s · 금화 %d" % [(", ".join(eq) if eq.size() > 0 else "없음"), (" · 공용 공격 강화 %d단계" % int(r.forge)) if int(r.forge) > 0 else "", int(r.gold)], 13))
	var recs: Dictionary = r.get("bossRecords", {})
	for k in recs:
		var rec: Dictionary = recs[k]
		box.add_child(PUi.rich("[b]%s[/b]: %s초 · 재도전 %d회 · Lv %d · 보스에게 준 피해 %d · %d일차" % [PGlossaryTip.esc(String(PCatalog.boss_def(String(rec.get("bossId", "boss"))).name)), str(rec.get("time", 0.0)), int(rec.get("retries", 0)), int(rec.get("level", 0)), int(float(rec.get("bossDamage", 0.0))), int(rec.get("day", 0))], 13))
	if recs.is_empty():
		box.add_child(PUi.rich("[color=#9ea8b8]보스 처치 기록 없음[/color]", 13))
	var award_txt := PProfile.award_text(main.last_profile_award)
	if award_txt != "":
		box.add_child(PUi.rich("[color=#ffe066]%s[/color]" % PGlossaryTip.esc(award_txt), 12))
	var crafted: Array = r.get("crafted", [])
	if not crafted.is_empty():
		var cn := []
		for id in crafted:
			cn.append(PRun.equip_name(String(id)))
		box.add_child(PUi.rich("[color=#9ea8b8]이번 회차 제작: %s (완성품·재료는 회차와 함께 소멸)[/color]" % PGlossaryTip.esc(", ".join(cn)), 12))
	var ES := PEndless.summary(r)
	if not ES.is_empty(): # 무한 모드 요약(본편 완주와 별도)
		var ec := PUi.card("%s [color=#9ea8b8]%s[/color]" % [PGlossaryTip.term("endless", "무한 모드"), ("종료: " + PGlossaryTip.esc(PEndless.reason_name(String(ES.reason)))) if bool(ES.over) else "진행 중"], PUi.CARD_ON, 14)
		(ec.box as VBoxContainer).add_child(PUi.rich("%d구간 도달 · 전투 승 %d · 구간 보스 %d · Lv %d → %d" % [int(ES.segment), int(ES.wins), int(ES.bossesWon), int(ES.startLevel), int(ES.level)], 13))
		for rec in ES.rows:
			(ec.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]%d구간 %s: %s초 · 보스 체력 ×%.2f · 보스에게 준 피해 %d[/color]" % [int(rec.segment), PGlossaryTip.esc(String(PCatalog.boss_def(String(rec.bossId)).name)), str(rec.time), float(rec.bossHpMult), int(rec.bossDamage)], 12))
		body.add_child(ec.panel)
	var R := PSave.load_records()
	var fc = R.get("first_clear", null)
	if fc != null:
		box.add_child(PUi.rich("[color=#9ea8b8]첫 완주 기록: %s초 (시드 %d)[/color]" % [str(fc.get("time", 0.0)), int(fc.get("seed", 0))], 12))
	body.add_child(c.panel)
	var combats: Array = r.get("dmgStats", {}).get("combats", [])
	if not combats.is_empty():
		var V := PStats.views(r)
		for pair in [["all", "전체"], ["boss", "보스전(성공)"], ["bossFailed", "보스전(실패한 도전)"], ["sortie", "일반 출격"]]:
			var sc := PUi.card("")
			(sc.box as VBoxContainer).add_child(PUi.stats_table(V[String(pair[0])], String(pair[1])))
			body.add_child(sc.panel)
	if cleared and PEndless.can_start(r):
		var eb := PUi.button("현재 빌드로 계속 (무한 모드)", func(): main.start_endless(), true, 14)
		eb.tooltip_text = "본편 완주 기록·영구 보상은 이미 확정. 무한에서 패배해도 취소되지 않음(시험값)"
		bottom.add_child(eb)
	if cleared:
		bottom.add_child(PUi.button("이번 빌드로 보스 다시 도전", func(): main.start_boss(), PRun.can_start_boss(r), 14))
	var nb := PUi.button("새 회차 시작", func(): main.new_run_flow(), true, 14)
	bottom.add_child(nb)
	bottom.add_child(PUi.button("제목으로", func(): main.go_title(), true, 14))
	default_button = nb
