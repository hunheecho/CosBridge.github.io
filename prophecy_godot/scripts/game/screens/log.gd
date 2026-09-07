class_name PLogScreen
extends PScreen
## 최근 기록(run.log, 최대 8줄)과 회차 통계 한 줄.

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	top.add_child(PUi.rich("[b]기록[/b]", 20))
	var s: Dictionary = r.get("stats", {})
	body.add_child(PUi.rich("[color=#9ea8b8]전투 %d · 승리 %d · 패배 %d · 출격 %d회 · 사건 %d회[/color]" % [int(s.get("encounters", 0)), int(s.get("wins", 0)), int(s.get("losses", 0)), int(r.get("sortieCount", 0)), int(r.get("eventsResolved", 0))], 13))
	var L: Array = r.get("log", [])
	var c := PUi.card("최근 기록")
	if L.is_empty():
		(c.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]아직 없음[/color]", 13))
	for l in L:
		(c.box as VBoxContainer).add_child(PUi.rich(PGlossaryTip.esc(String(l)), 13))
	body.add_child(c.panel)
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	default_button = back
