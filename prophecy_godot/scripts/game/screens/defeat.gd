class_name PDefeatScreen
extends PScreen
## 일반 출격 패배(HTML defeat): 잃은 전리품과 다음 시작 시점(PRun.defeat 결과). 거점으로.

func refresh() -> void:
	clear_all()
	var r := run()
	var s: Dictionary = main.sortie
	var sm: Dictionary = main.last_summary
	if r.is_empty() or s.is_empty():
		return
	var reg := PRun.region(String(s.regionId))
	var lost: Dictionary = main.lost_loot
	var lost_txt := "금화 %d" % int(lost.get("gold", 0))
	var mats := PUi.mats_text(lost.get("mats", {}))
	if mats != "":
		lost_txt += ", " + mats
	for id in lost.get("items", []):
		lost_txt += ", " + PRun.equip_name(String(id))
	var now := ("%d일차 보스 관문" % int(r.day)) if String(r.phase) == "boss_prep" else ("%d일차 %s" % [int(r.day), String(PRun.time_slots()[0])])
	heading("[color=#ff8c73]패배[/color]")
	body.add_child(PUi.rich("%s에서 쓰러졌습니다. 이번 출격의 미정산 전리품([b]%s[/b])과 남은 하루를 잃었습니다." % [PGlossaryTip.esc(String(reg.name)), PGlossaryTip.esc(lost_txt)], 14))
	body.add_child(PUi.rich("구조되어 [b]%s[/b]에 정상 체력으로 시작합니다. 이미 정산한 금화·장비와 레벨·성장은 그대로입니다." % now, 14))
	body.add_child(PUi.rich("[color=#9ea8b8]처치 %d · 받은 피해 %d · %d초[/color]" % [int(sm.get("kills", 0)), int(float(sm.get("damage_taken", 0.0))), int(round(float(sm.get("elapsed", 0.0))))], 12))
	var btn := PUi.button("%s로 (Enter)" % now, func(): main.after_defeat(), true, 16)
	body.add_child(btn)
	default_button = btn
