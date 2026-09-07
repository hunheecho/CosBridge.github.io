class_name PBossResultScreen
extends PScreen
## 보스전 결과(HTML bossDefeat / bossVictory(비최종)): 패배 = 재도전(입장 스냅샷 복구) · 최종 준비 · 제목. 승리 = 기록 + 다음 단계 해금 → 거점.
## 최종 보스 승리는 run_result 화면이 맡는다.

func refresh() -> void:
	clear_all()
	var r := run()
	var sm: Dictionary = main.last_summary
	if r.is_empty():
		return
	var won: bool = String(sm.get("status", "")) == "won"
	if not won:
		var B := PRun.next_boss_cfg(r)
		heading("[color=#ff8c73]쓰러졌다[/color]")
		top.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(PUi.settings_short(r)), 11))
		body.add_child(PUi.rich("%s에게 패배했습니다. 준비 기간의 성과는 그대로입니다. 같은 장비·무기·증강으로 바로 다시 도전할 수 있습니다." % PGlossaryTip.esc(String(B.name)), 14))
		body.add_child(PUi.rich("[color=#9ea8b8]재도전은 입장 시점의 상태로 복구됩니다: 레벨·경험치·전투 중 선택은 입장 전으로, 체력·회피·감속장·E는 초기화, 보스·소환·구슬은 처음부터.[/color]", 12))
		body.add_child(PUi.rich("[color=#9ea8b8]전투 %d초 · 보스에게 준 피해 %d / %d · 감속장 %d회 · 재도전 %d회[/color]" % [int(round(float(sm.get("elapsed", 0.0)))), int(float(sm.get("boss_damage", 0.0))), int(PRun.boss_hp(r, String(B.id))), int(sm.get("special_uses", 0)), int(r.get("bossRetries", 0))], 12))
		var retry := PUi.button("같은 준비로 재도전 (Enter)", func(): main.start_boss(), PRun.can_start_boss(r), 16)
		body.add_child(retry)
		body.add_child(PUi.button("최종 준비 화면으로", func(): main.go_base(), true, 14))
		body.add_child(PUi.button("제목으로", func(): main.go_title(), true, 14))
		default_button = retry
		return
	var rec: Dictionary = main.last_record if not main.last_record.is_empty() else r.get("lastBossClear", {})
	var B2 := PCatalog.boss_def(String(rec.get("bossId", "boss")))
	heading("%d단계 돌파" % int(r.get("stage", 0)))
	top.add_child(PUi.rich("[b]%s — %s 처치[/b]" % [PGlossaryTip.esc(String(B2.name)), PGlossaryTip.esc(String(B2.get("title", "")))], 18))
	top.add_child(PUi.rich("[color=#9ea8b8]%s · 보스 최대 체력 %d[/color]" % [PGlossaryTip.esc(PUi.settings_short(r)), int(PRun.boss_hp(r, String(B2.id)))], 11))
	var c := PUi.card("기록")
	(c.box as VBoxContainer).add_child(PUi.rich("전투 시간 [b]%s초[/b] · 재도전 [b]%d회[/b] · Lv %d" % [str(rec.get("time", 0.0)), int(rec.get("retries", 0)), int(r.growth.level)], 13))
	(c.box as VBoxContainer).add_child(PUi.rich("감속장 사용 [b]%d[/b]회 · 보스에게 준 총피해 [b]%d[/b]%s" % [int(sm.get("special_uses", 0)), int(float(sm.get("boss_damage", 0.0))), (" · 원정대의 갑옷 체력 +%d" % int(float(rec.heal))) if rec.has("heal") else ""], 13))
	body.add_child(c.panel)
	var nb := PRun.next_boss(r)
	var g: Dictionary = r.growth
	var pick: bool = g.get("pendingBossPick", null) != null or (g.get("pendingOffer", null) != null and String(g.pendingOffer.pool) == "boss")
	var n := PUi.card("다음 단계 해금", PUi.CARD_BOSS)
	(n.box as VBoxContainer).add_child(PUi.rich("%d일차의 %d시간이 시작됩니다. %s%s" % [int(r.day), int(PCatalog.config().HOURS_PER_DAY), ("다음 보스 [b]%s[/b]은(는) %d일차 시작에 옵니다." % [PGlossaryTip.esc(String(PRun.next_boss_cfg(r).name)), int(nb.day)]) if not nb.is_empty() else "", " [b]희귀 보상 3택[/b]이 거점에서 제시됩니다(1회, 저장됨)." if pick else ""], 13))
	body.add_child(n.panel)
	var go := PUi.button("거점으로 (오늘 시간 시작) (Enter)", func(): main.go_base(), true, 16)
	body.add_child(go)
	default_button = go
