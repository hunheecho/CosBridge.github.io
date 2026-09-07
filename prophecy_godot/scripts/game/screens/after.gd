class_name PAfterScreen
extends PScreen
## 전투 뒤 안전 화면(HTML after): 귀환 또는 더 깊이(PRun.can_deep_explore · deep_preview · PFlow.must_return).

static func loot_text(s: Dictionary) -> String:
	var loot: Dictionary = s.loot
	var t := "금화 %d" % int(loot.gold)
	var mats := PUi.mats_text(loot.get("mats", {}))
	if mats != "":
		t += ", " + mats
	for id in loot.get("items", []):
		t += ", " + PRun.equip_name(String(id))
	for k in loot.get("services", []):
		t += ", " + String(PCatalog.services()[String(k)].name)
	if loot.get("steer", null) != null:
		t += ", 성장 예약"
	return t

func refresh() -> void:
	clear_all()
	var r := run()
	var s: Dictionary = main.sortie
	if r.is_empty() or s.is_empty():
		return
	var reg := PRun.region(String(s.regionId))
	var b := PBuild.derive(r)
	var must := PFlow.must_return(s)
	var can_deep := not bool(s.get("deep", false)) and PRun.can_deep_explore(r, s) and not must
	heading("%s · 전투 승리" % PGlossaryTip.esc(String(reg.name)))
	body.add_child(PUi.rich("체력 [b]%d / %d[/b] · 이번 출격 %s: [b]%s[/b] · 남은 %d칸 (%s)" % [int(float(r.hp)), int(float(b.hp_max)), PGlossaryTip.term("loot", "전리품(미정산)"), PGlossaryTip.esc(loot_text(s)), int(r.hours), PRun.slot_name(r)], 14))
	if s.get("eventFight", null) != null:
		var ec := PUi.card("사건 추가 전투", PUi.CARD_BOSS)
		(ec.box as VBoxContainer).add_child(PUi.rich("갇힌 상인을 구하는 추가 전투가 남아 있습니다(체력 회복 없음, 새 전리품 없음).", 13))
		(ec.box as VBoxContainer).add_child(PUi.button("추가 전투 시작", func(): main.start_encounter(), true, 14))
		body.add_child(ec.panel)
	elif can_deep:
		var pv := PRun.deep_preview(r, s)
		var dc := PUi.card("%s (1회) [color=#9ea8b8]시간 +%d칸 → %s[/color]" % [PGlossaryTip.term("deep", "더 깊이"), int(pv.extraTime), PGlossaryTip.esc(String(pv.nextSlot))], PUi.CARD_BOSS)
		var box: VBoxContainer = dc.box
		PUi.kv(box, "적 변화", "[b]%s%s[/b]" % [PGlossaryTip.esc(String(pv.enemyChange)), (" · 체력 ×%s" % PUi.fmt(float(pv.hpMult.normal))) if float(pv.hpMult.normal) != 1.0 else ""], 13)
		PUi.kv(box, "보상", "[b]%s[/b] [color=#9ea8b8](승리 시 전리품에 추가, 귀환 때 정산)[/color]" % PGlossaryTip.esc(String(pv.reward.text)), 13)
		PUi.kv(box, "걸린 전리품", "[color=#ff8c73][b]%s[/b][/color] [color=#9ea8b8]패배하면 모두 잃고 남은 하루도 잃습니다[/color]" % PGlossaryTip.esc(loot_text(s)), 13)
		box.add_child(PUi.button("더 깊이 들어간다", func(): main.deep_explore(), true, 14))
		body.add_child(dc.panel)
	else:
		var why := "이미 탐험함" if bool(s.get("deep", false)) else ("임무 출격에서는 불가" if bool(s.get("mission", false)) else ("심층 승리 뒤에는 귀환만" if must else "남은 칸 없음"))
		body.add_child(PUi.rich("[color=#9ea8b8]더 깊이: %s[/color]" % why, 12))
	var ret := PUi.button("전리품을 가지고 귀환 (정산)", func(): main.return_home(), true, 16)
	body.add_child(ret)
	body.add_child(PUi.rich("[color=#9ea8b8]시작한 전투는 중간에 안전하게 물러날 수 없습니다. 포기는 패배로 처리됩니다.[/color]", 11))
	default_button = ret
