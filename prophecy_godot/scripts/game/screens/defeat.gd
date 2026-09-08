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
	# **사망 규칙(2026-09-09 사용자 확정)을 그대로 보여 준다.** 예전에는 결과와 상관없이
	# "구조되어 정상 체력으로 시작합니다"라고만 적어, 회차가 끝났는데도 계속할 수 있는 것처럼 보였다
	var death: Dictionary = r.get("death", {})
	var over := PRun.is_run_over(r)
	var revived := bool(death.get("revived", false))
	heading("[color=#ff8c73]%s[/color]" % ("회차 종료" if over else "패배"))
	body.add_child(PUi.rich("%s에서 쓰러졌습니다. 이번 출격의 미정산 전리품([b]%s[/b])을 잃었습니다." % [PGlossaryTip.esc(String(reg.name)), PGlossaryTip.esc(lost_txt)], 14))
	if over:
		body.add_child(PUi.rich("[color=#ff8c73]부활 수단이 없어 이번 회차가 여기서 끝납니다.[/color] 다음 회차는 처음부터 시작합니다.", 15))
		body.add_child(PUi.rich("[color=#9ea8b8]부활 물약을 가지고 있었다면 하루를 잃고 다음 날 최대 체력 25%로 이어갈 수 있었습니다.[/color]", 13))
	elif revived:
		body.add_child(PUi.rich("[b]부활 물약 1개를 썼습니다.[/b] 남은 하루를 잃고 [b]%s[/b]에 [b]최대 체력의 25%%[/b]로 이어갑니다." % now, 15))
		body.add_child(PUi.rich("[color=#9ea8b8]남은 부활 물약 %d개 · 이미 정산한 금화·장비와 레벨·성장은 그대로입니다.[/color]" % PConsumables.revive_count(r), 13))
	else:
		body.add_child(PUi.rich("[b]%s[/b]에 이어갑니다. 이미 정산한 금화·장비와 레벨·성장은 그대로입니다." % now, 14))
	body.add_child(PUi.rich("[color=#9ea8b8]처치 %d · 받은 피해 %d · %d초[/color]" % [int(sm.get("kills", 0)), int(float(sm.get("damage_taken", 0.0))), int(round(float(sm.get("elapsed", 0.0))))], 12))
	var btn := PUi.button(("회차 결과 보기 (Enter)" if over else "%s로 (Enter)" % now), func(): main.after_defeat(), true, 16)
	body.add_child(btn)
	default_button = btn
