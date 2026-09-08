class_name PRewardScreen
extends PScreen
## 전투 승리(HTML reward). 2026-09-09 단순화 — 기본 화면에는 결과와 진행만 남긴다.
##
## 기본: 전투 승리 · 핵심 획득물(금화·재료) · 지금 체력 · 실제로 받은 특별 보상 한 줄 · 큰 '계속' 하나 · 보조 '전투 통계'.
## 상세('전투 통계'를 눌러야 열린다): 보급 상자 포함 금액 · 경험치 세부 · 처치 · 받은 피해 · 전투 시간 · 피해 출처 · 버전·시드.
## '계속'은 요약 바로 아래 한 곳에만 둔다(맨 아래에 같은 버튼을 겹쳐 두지 않는다 — 사용자 지시).
## 내부 처리 문장(예약·정산·반영)은 보상 설명으로 쓰지 않는다: 실제로 무엇을 받았는지만 적는다.

var _stats_open := false      # 전투 통계를 펼쳤는가(기본 접힘)

func on_enter() -> void:
	_stats_open = false
	super.on_enter()

func refresh() -> void:
	clear_all()
	close_confirm()
	var r := run()
	var rw: Dictionary = main.last_reward
	var sm: Dictionary = main.last_summary
	if r.is_empty() or rw.is_empty():
		return
	var s: Dictionary = main.sortie
	var g: Dictionary = r.growth
	heading("%s · 전투 승리" % PGlossaryTip.esc(String(PRun.region(String(s.get("regionId", "forest"))).name)))
	var c := PUi.card("", PUi.CARD)
	var box: VBoxContainer = c.box
	var got := "금화 [color=#ffd966][b]+%d[/b][/color]" % int(rw.gold)
	var mats := PUi.mats_text(rw.get("mats", {}))
	if mats != "":
		got += " · " + PGlossaryTip.esc(mats)
	box.add_child(PUi.rich(got, 20))
	box.add_child(PUi.rich("[color=#9ea8b8]체력[/color] [b]%d / %d[/b]" % [int(float(r.hp)), int(float(PBuild.derive(r).hp_max))], 17))
	for line in _special_lines(r, rw):
		box.add_child(PUi.rich(line, 15))
	body.add_child(c.panel)
	# 요약 바로 아래의 큰 '계속' 하나. 통계를 펼쳐도 이 버튼은 그대로 남는다
	var go := PUi.button("계속 (Enter)", func(): main.after_reward(), true, 20)
	go.custom_minimum_size = Vector2(0, PLayout.primary_button_height() + 8.0)
	body.add_child(go)
	default_button = go
	if int(g.pendingLevelUps) > 0:
		var lc := PUi.card("미처리 레벨업 %d" % int(g.pendingLevelUps), PUi.CARD_BOSS, 16)
		(lc.box as VBoxContainer).add_child(PUi.rich("조우 종료와 동시에 오른 레벨입니다. 지금 선택합니다.", 15))
		var lb := PUi.button("선택하기", func(): main.offer_pending_level_ups(), true, 16)
		lb.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		(lc.box as VBoxContainer).add_child(lb)
		body.add_child(lc.panel)
	var toggle := PUi.button("전투 통계 닫기 ▼" if _stats_open else "전투 통계 ▶", func(): _stats_open = not _stats_open; refresh(), true, 14)
	toggle.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(toggle)
	if _stats_open:
		_stats_detail(r, rw, sm, g)

## 실제로 받은 특별 보상만 한 줄씩. 아무것도 없으면 빈 목록(빈 줄을 만들지 않는다)
func _special_lines(r: Dictionary, rw: Dictionary) -> Array:
	var out := []
	if rw.get("deep", null) != null:
		out.append("%s 보상: [b]%s[/b]" % [PGlossaryTip.term("deep", "더 깊이"), PGlossaryTip.esc(String(rw.deep.text))])
	if bool(rw.get("mission", false)):
		var mp = rw.get("missionPick", false)
		if typeof(mp) == TYPE_BOOL and mp == true:
			out.append("[b]임무 완료[/b] — 보상 3택")
		elif typeof(mp) == TYPE_DICTIONARY:
			var mpd: Dictionary = mp
			if mpd.has("gold"):
				out.append("[b]임무 완료[/b] — 금화 +%d" % int(mpd.gold))
			else:
				out.append("[b]임무 완료[/b] — 다음 성장은 %s 후보" % PSortie.kind_name(String(mpd.steer)))
	if bool(rw.get("sealedLoot", false)):
		out.append("[b]봉인된 전리품[/b] — 금화 ×2")
	if float(rw.get("heal", 0.0)) > 0.0:
		out.append("[color=#9fe89f]승리 회복(장비): 체력 +%d[/color]" % int(float(rw.heal)))
	var award_txt := PProfile.award_text(main.last_profile_award)
	if award_txt != "":
		out.append("[color=#ffe066]%s[/color]" % PGlossaryTip.esc(award_txt))
	return out

## 전투 통계(펼쳤을 때만): 상자 포함 금액 · 경험치 · 처치·받은 피해·시간 · 피해 출처 상위 5 · 버전·시드
func _stats_detail(r: Dictionary, rw: Dictionary, sm: Dictionary, g: Dictionary) -> void:
	var c := PUi.card("이번 전투", PUi.CARD, 15)
	var box: VBoxContainer = c.box
	var gold_txt := "+%d" % int(rw.gold)
	if int(rw.get("chestGold", 0)) > 0:
		gold_txt += " (보급 상자 +%d 포함)" % int(rw.chestGold)
	PUi.kv(box, "금화", gold_txt, 13)
	PUi.kv(box, "지역 경험치", "+%s" % str(rw.get("xp", 0.0)), 13)
	PUi.kv(box, "전투 중 경험치", "%s [color=#9ea8b8]· 감속장 안 처치 %d[/color]" % [str(sm.get("xp", 0.0)), int(sm.get("saving_kills", 0))], 13)
	PUi.kv(box, "처치 · 받은 피해 · 시간", "[b]%d[/b] · [b]%d[/b] · [b]%d초[/b]" % [int(sm.get("kills", 0)), int(float(sm.get("damage_taken", 0.0))), int(round(float(sm.get("elapsed", 0.0))))], 13)
	if int(sm.get("level_ups", 0)) > 0:
		PUi.kv(box, "레벨업", "%d회 (Lv %d)" % [int(sm.get("level_ups", 0)), int(g.level)], 13)
	if rw.has("eventFight"):
		PUi.kv(box, "사건 추가 전투", "전리품 없음(서비스 해금)", 13)
	if bool(rw.get("mission", false)) and typeof(rw.get("missionPick", false)) == TYPE_BOOL and not bool(rw.get("missionPick", false)):
		PUi.kv(box, "임무", "오늘 이미 완료 — 추가 3택 없음", 13)
	body.add_child(c.panel)
	var dmg: Dictionary = sm.get("dmg", {})
	if not dmg.is_empty():
		var keys := dmg.keys()
		keys.sort_custom(func(a, b): return float(dmg[a]) > float(dmg[b]))
		var total := 0.0
		for k in keys:
			total += float(dmg[k])
		var dc := PUi.card("피해 출처 [color=#9ea8b8]상위 5 · 유효 피해[/color]", PUi.CARD, 15)
		for i in mini(5, keys.size()):
			var k2 := String(keys[i])
			var cl := PStats.classify(k2)
			(dc.box as VBoxContainer).add_child(PUi.rich("%s [color=#9ea8b8]%s[/color]  [b]%s[/b] (%d%%)" % [PGlossaryTip.esc(String(cl.name)), String(PStats.CATS.get(String(cl.cat), cl.cat)), PUi.fmt(float(dmg[k2])), int(round(float(dmg[k2]) / maxf(1.0, total) * 100.0))], 14))
		body.add_child(dc.panel)
	var taken: Dictionary = sm.get("taken", {})
	if not taken.is_empty():
		var parts := []
		for k3 in taken:
			parts.append("%s %s" % [String(k3), PUi.fmt(float(taken[k3]))])
		body.add_child(PUi.rich("[color=#9ea8b8]받은 피해 출처: %s[/color]" % PGlossaryTip.esc(", ".join(parts)), 13))
	body.add_child(PUi.rich("[color=#6a7078]%s[/color]" % PGlossaryTip.esc(PUi.settings_short(r)), 11))
