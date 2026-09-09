class_name PBossResultScreen
extends PScreen
## 보스전 결과(HTML bossDefeat / bossVictory(비최종)): 패배 = 사망 정산 결과 안내 · 최종 준비 · 제목. 승리 = 기록 + 다음 단계 해금 → 거점.
## 최종 보스 승리는 run_result 화면이 맡는다.
##
## 관문 패배 문구는 static으로 뽑아 두었다(defeat_lines·retry_label) — 화면과 시험이 같은 문자열을 본다.
## 무료 상태 복원·무제한 재도전은 사람 플레이에서 없어졌고(2026-09-09 확정), 마지막 날 부활은 "다음 날"이 아니라
## **같은 날 관문 앞**이라 문구가 따로다(사람이 날짜를 착각하지 않게).

## 관문 패배 안내. 네 갈래가 서로 다른 문구다: 시험 재시도 경로 / 회차 종료 / 마지막 날 부활(같은 날) / 보통 날 부활(다음 날)
static func defeat_lines(r: Dictionary) -> Array:
	if PRun.retry_mode(r): # 시험·자동 진행 경로(사람 플레이 아님): 옛 규칙 그대로
		return ["[color=#9ea8b8]시험 재시도 경로입니다. 재도전은 입장 시점의 상태로 복구됩니다: 레벨·경험치·전투 중 선택은 입장 전으로, 체력·회피·감속장·E는 초기화, 보스·소환·구슬은 처음부터.[/color]"]
	if PRun.is_run_over(r):
		return [
			"[color=#ff8c73]부활 수단이 없어 이번 회차가 여기서 끝납니다.[/color] 다음 회차는 처음부터 시작합니다.",
			"[color=#9ea8b8]부활 물약을 가지고 있었다면 최대 체력 25%로 관문 앞에 다시 설 수 있었습니다.[/color]",
		]
	if PRun.revived_same_day(r): # 마지막 날: 날짜를 넘기지 않고 같은 날 관문 앞
		var last_lines := [
			"[b]부활 물약 1개를 썼습니다.[/b] 마지막 날이라 [b]날짜는 넘어가지 않습니다[/b] — [b]같은 %d일차 관문 앞[/b]에서 [b]최대 체력의 25%%[/b]로 다시 섭니다." % int(r.get("day", 1)),
			"[color=#9ea8b8]대신 오늘 남은 시간은 전부 사라졌습니다(휴식·상점 없이 관문만 남습니다). 다시 쓰러지면 부활 물약이 또 한 개 듭니다 — 남은 %d개.[/color]" % PConsumables.revive_count(r),
		]
		var nh_last := no_heal_line(r)
		if nh_last != "":
			last_lines.append(nh_last)
		return last_lines
	if bool((r.get("death", {}) as Dictionary).get("revived", false)):
		var lines := [
			"[b]부활 물약 1개를 썼습니다.[/b] 남은 하루를 잃고 [b]%d일차 관문 앞[/b]에 [b]최대 체력의 25%%[/b]로 다시 섭니다." % int(r.get("day", 1)),
			"[color=#9ea8b8]관문은 그대로 남아 있어 다음 막은 열리지 않습니다 · 남은 부활 물약 %d개.[/color]" % PConsumables.revive_count(r),
		]
		var nh := no_heal_line(r)
		if nh != "":
			lines.append(nh)
		return lines
	return []

## 부활로 관문 앞에 섰을 때만 붙는 한 줄. 재입장에는 자동 회복이 없다(PRun.revive_pending이 true인 동안)
static func no_heal_line(r: Dictionary) -> String:
	if not PRun.revive_pending(r):
		return ""
	return "[color=#ffd479]다시 들어가도 체력은 자동으로 차지 않습니다 — 지금 체력 %d/%d 그대로 시작합니다. 회복약을 쓰면 그만큼 오른 체력으로 들어갑니다.[/color]" % [int(PRun.boss_start_hp(r)), int(float(PRun.build(r).hp_max))]

## 바로 다시 들어갈 수 있는가. 시험 경로와 **마지막 날 부활**뿐이다
## (마지막 날은 남은 시간이 0이라 거점에서 할 일이 없다. 다음 날 부활은 하루가 통째로 남으므로 거점을 거치게 둔다)
static func can_retry_now(r: Dictionary) -> bool:
	return PRun.can_start_boss(r) and (PRun.retry_mode(r) or PRun.revived_same_day(r))

static func retry_label(r: Dictionary) -> String:
	if can_retry_now(r):
		return "같은 준비로 재도전 (Enter)" if PRun.retry_mode(r) else "같은 날 관문에 다시 들어간다 (Enter)"
	if bool((r.get("death", {}) as Dictionary).get("revived", false)):
		return "%d일차 관문 앞에서 다시 도전합니다 — 준비 화면으로" % int(r.get("day", 1))
	return "재도전 없음 — 부활 수단이 있어야 이어갈 수 있습니다"

func refresh() -> void:
	clear_all()
	var r := run()
	var sm: Dictionary = main.last_summary
	if r.is_empty():
		return
	var won: bool = String(sm.get("status", "")) == "won"
	if not won:
		var B := PRun.next_boss_cfg(r)
		var over := PRun.is_run_over(r)
		heading("[color=#ff8c73]%s[/color]" % ("회차 종료" if over else "쓰러졌다"))
		top.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(PUi.settings_short(r)), 11))
		body.add_child(PUi.rich("%s에게 패배했습니다." % PGlossaryTip.esc(String(B.name)), 14))
		var lines := defeat_lines(r)
		for i in lines.size():
			body.add_child(PUi.rich(String(lines[i]), 15 if i == 0 else 13))
		body.add_child(PUi.rich("[color=#9ea8b8]전투 %d초 · 보스에게 준 피해 %d / %d · 감속장 %d회 · 재도전 %d회[/color]" % [int(round(float(sm.get("elapsed", 0.0)))), int(float(sm.get("boss_damage", 0.0))), int(PRun.boss_hp(r, String(B.id))), int(sm.get("special_uses", 0)), int(r.get("bossRetries", 0))], 12))
		var can_retry := can_retry_now(r)
		var retry := PUi.button(retry_label(r), func(): main.start_boss(), can_retry, 16)
		body.add_child(retry)
		var go_next := PUi.button(("회차 결과 보기 (Enter)" if over else "최종 준비 화면으로"), func(): main.go_base(), true, 14)
		body.add_child(go_next)
		body.add_child(PUi.button("제목으로", func(): main.go_title(), true, 14))
		default_button = retry if can_retry else go_next # 잠긴 버튼을 Enter의 주 행동으로 두지 않는다(끝난 회차에서 Enter가 먹통이던 자리)
		return
	var rec: Dictionary = main.last_record if not main.last_record.is_empty() else r.get("lastBossClear", {})
	var B2 := PCatalog.boss_def(String(rec.get("bossId", "boss")))
	heading("%d단계 돌파" % int(r.get("stage", 0)))
	top.add_child(PUi.rich("[b]%s — %s 처치[/b]" % [PGlossaryTip.esc(String(B2.name)), PGlossaryTip.esc(String(B2.get("title", "")))], 18))
	top.add_child(PUi.rich("[color=#9ea8b8]%s · 보스 최대 체력 %d[/color]" % [PGlossaryTip.esc(PUi.settings_short(r)), int(PRun.boss_hp(r, String(B2.id)))], 11))
	var c := PUi.card("기록")
	(c.box as VBoxContainer).add_child(PUi.rich("전투 시간 [b]%s초[/b] · 재도전 [b]%d회[/b] · Lv %d" % [str(rec.get("time", 0.0)), int(rec.get("retries", 0)), int(r.growth.level)], 13))
	(c.box as VBoxContainer).add_child(PUi.rich("감속장 사용 [b]%d[/b]회 · 보스에게 준 총피해 [b]%d[/b]%s" % [int(sm.get("special_uses", 0)), int(float(sm.get("boss_damage", 0.0))), (" · 승리 회복(장비) 체력 +%d" % int(float(rec.heal))) if rec.has("heal") else ""], 13))
	var award_txt := PProfile.award_text(main.last_profile_award)
	if award_txt != "":
		(c.box as VBoxContainer).add_child(PUi.rich("[color=#ffe066]%s[/color]" % PGlossaryTip.esc(award_txt), 12))
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
