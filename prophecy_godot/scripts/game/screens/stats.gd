class_name PStatsScreen
extends PScreen
## 런 피해 통계(HTML statsPanel): PStats.views(run)의 4가지 보기(전체 / 보스전 성공 / 보스전 실패 / 일반 출격).

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	top.add_child(PUi.rich("[b]피해 통계[/b] [color=#9ea8b8]유효 피해 = 실제 체력 감소(과잉 피해 제외) · DPS 분모 = 그 기술을 보유한 실제 전투 시간[/color]", 20))
	var combats: Array = r.get("dmgStats", {}).get("combats", [])
	if combats.is_empty():
		body.add_child(PUi.rich("[color=#9ea8b8]아직 기록된 전투가 없습니다.[/color]", 14))
	else:
		var V := PStats.views(r)
		for pair in [["all", "전체"], ["boss", "보스전(성공)"], ["bossFailed", "보스전(실패한 도전)"], ["sortie", "일반 출격"]]:
			var c := PUi.card("")
			(c.box as VBoxContainer).add_child(PUi.stats_table(V[String(pair[0])], String(pair[1])))
			body.add_child(c.panel)
		body.add_child(PUi.rich("[color=#9ea8b8]감속장(Q)의 감속·방어·회복은 피해가 아니므로 표에 없음.[/color]", 11))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	default_button = back
