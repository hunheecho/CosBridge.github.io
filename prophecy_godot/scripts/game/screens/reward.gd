class_name PRewardScreen
extends PScreen
## 전투 승리(HTML reward): 정산(PFlow.settle_victory) 결과 — 금화·재료·지역 경험치·임무 보상·심층 보상 — 와 전투 요약(시간·처치·받은 피해·피해 출처 상위 5).

func refresh() -> void:
	clear_all()
	var r := run()
	var rw: Dictionary = main.last_reward
	var sm: Dictionary = main.last_summary
	if r.is_empty() or rw.is_empty():
		return
	var s: Dictionary = main.sortie
	var g: Dictionary = r.growth
	heading("%s · 전투 승리" % PGlossaryTip.esc(String(PRun.region(String(s.get("regionId", "forest"))).name)))
	top.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(PUi.settings_short(r)), 11))
	var c := PUi.card("보상 [color=#9ea8b8](귀환 시 거점에 반영)[/color]")
	var box: VBoxContainer = c.box
	var mats := PUi.mats_text(rw.get("mats", {}))
	var line := "금화 [color=#ffd966][b]+%d[/b][/color]" % int(rw.gold)
	if int(rw.get("chestGold", 0)) > 0:
		line += " (보급 상자 +%d 포함)" % int(rw.chestGold)
	if mats != "":
		line += " · " + PGlossaryTip.esc(mats)
	line += " · 지역 경험치 [color=#ffd966][b]+%s[/b][/color]" % str(rw.get("xp", 0.0))
	if bool(rw.get("mission", false)):
		var mp = rw.get("missionPick", false)
		if typeof(mp) == TYPE_BOOL and mp == true:
			line += " · [b]임무 완료: 보상 3택은 다음 단계에서[/b]"
		elif typeof(mp) == TYPE_DICTIONARY:
			var mpd: Dictionary = mp
			line += " · [b]임무 완료: %s[/b]" % (("금화 +%d 대체" % int(mpd.gold)) if mpd.has("gold") else ("다음 레벨업 예약 · %s" % PSortie.kind_name(String(mpd.steer))))
		else:
			line += " · 임무(오늘 이미 완료: 추가 3택 없음)"
	if rw.has("eventFight"):
		line += " · 사건 추가 전투: 전리품 없음(서비스 해금)"
	if bool(rw.get("sealedLoot", false)):
		line += " · 봉인된 전리품(금화 ×2)"
	box.add_child(PUi.rich(line, 14))
	if rw.get("deep", null) != null:
		box.add_child(PUi.rich("%s 보상: [b]%s[/b] [color=#9ea8b8](전리품에 추가됨, 귀환 때 정산)[/color]" % [PGlossaryTip.term("deep", "더 깊이"), PGlossaryTip.esc(String(rw.deep.text))], 13))
	if float(rw.get("heal", 0.0)) > 0.0:
		box.add_child(PUi.rich("[color=#9fe89f]승리 회복(장비): 체력 +%d[/color]" % int(float(rw.heal)), 12))
	var award_txt := PProfile.award_text(main.last_profile_award)
	if award_txt != "":
		box.add_child(PUi.rich("[color=#ffe066]%s[/color]" % PGlossaryTip.esc(award_txt), 12))
	box.add_child(PUi.rich("[color=#9ea8b8]처치 %d%s · 받은 피해 %d · %d초 · 전투 중 경험치 %s · 레벨업 %d회 (Lv %d) · 체력 %d / %d[/color]" % [int(sm.get("kills", 0)), (" (감속장 안 %d)" % int(sm.get("saving_kills", 0))) if int(sm.get("saving_kills", 0)) > 0 else "", int(float(sm.get("damage_taken", 0.0))), int(round(float(sm.get("elapsed", 0.0)))), str(sm.get("xp", 0.0)), int(sm.get("level_ups", 0)), int(g.level), int(float(r.hp)), int(float(PBuild.derive(r).hp_max))], 12))
	body.add_child(c.panel)
	# 피해 출처 상위 5
	var dmg: Dictionary = sm.get("dmg", {})
	if not dmg.is_empty():
		var keys := dmg.keys()
		keys.sort_custom(func(a, b): return float(dmg[a]) > float(dmg[b]))
		var total := 0.0
		for k in keys:
			total += float(dmg[k])
		var dc := PUi.card("피해 출처 [color=#9ea8b8]상위 5 · 유효 피해[/color]", PUi.CARD, 13)
		for i in mini(5, keys.size()):
			var k := String(keys[i])
			var cl := PStats.classify(k)
			(dc.box as VBoxContainer).add_child(PUi.rich("%s [color=#9ea8b8]%s[/color]  [b]%s[/b] (%d%%)" % [PGlossaryTip.esc(String(cl.name)), String(PStats.CATS.get(String(cl.cat), cl.cat)), PUi.fmt(float(dmg[k])), int(round(float(dmg[k]) / maxf(1.0, total) * 100.0))], 12))
		body.add_child(dc.panel)
	var taken: Dictionary = sm.get("taken", {})
	if not taken.is_empty():
		var parts := []
		for k in taken:
			parts.append("%s %s" % [String(k), PUi.fmt(float(taken[k]))])
		body.add_child(PUi.rich("[color=#9ea8b8]받은 피해 출처: %s[/color]" % PGlossaryTip.esc(", ".join(parts)), 11))
	if int(g.pendingLevelUps) > 0:
		var lc := PUi.card("미처리 레벨업 %d" % int(g.pendingLevelUps), PUi.CARD_BOSS)
		(lc.box as VBoxContainer).add_child(PUi.rich("조우 종료와 동시에 오른 레벨입니다. 지금 선택합니다.", 13))
		(lc.box as VBoxContainer).add_child(PUi.button("선택하기", func(): main.offer_pending_level_ups(), true, 14))
		body.add_child(lc.panel)
	var next := PUi.button("다음 (Enter)", func(): main.after_reward(), true, 16)
	bottom.add_child(next)
	default_button = next
