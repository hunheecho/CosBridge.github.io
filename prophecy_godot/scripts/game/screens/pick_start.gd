class_name PPickStartScreen
extends PScreen
## 시작 자동기술 선택(HTML pickStart): PCatalog.startable()의 이름·설명·실제 파생 수치(PBuild.derive) → PRun.new_run.

func refresh() -> void:
	clear_all()
	var C := PCatalog.config()
	heading("시작 자동기술 선택")
	top.add_child(PUi.rich("[color=#9ea8b8]자동기술 1개(Lv1, 개조 없음) · 감속장(Q) Lv1 · 체력 %d · 금화 %d으로 1일차 %s에 시작합니다. 자동기술은 최대 %d개, 장비(무기·방어구·방패)는 상점에서 삽니다.[/color]" % [int(C.PLAYER.hp), int(C.START_GOLD), String(PRun.time_slots()[0]), int(PCatalog.growth().SLOTS.weapons)], 13))
	var row := PUi.hbox(10)
	body.add_child(row)
	var first: Button = null
	for wid in PCatalog.startable():
		var id := String(wid)
		var d := PCatalog.weapon(id)
		var tmp := PRun.new_run(1, id)
		var b := PBuild.derive(tmp)
		var ws: Dictionary = b.weapons[0]
		var c := PUi.card("", PUi.CARD)
		var p: PanelContainer = c.panel
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box: VBoxContainer = c.box
		box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.term("w:" + id, String(d.name)), 17))
		box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 13))
		var mods := []
		for mid in d.mods:
			if bool(d.mods[mid].impl):
				mods.append(String(d.mods[mid].name))
		var rng_txt := (" · 사거리 %d" % int(round(float(ws.range)))) if float(ws.range) > 0.0 else ""
		box.add_child(PUi.rich("[color=#9ea8b8]기본 피해 %s · 주기 %s초%s · 개조 후보: %s[/color]" % [PUi.fmt(float(ws.damage)), PUi.fmt(float(ws.interval)), rng_txt, ", ".join(mods)], 12))
		box.add_child(PUi.spacer())
		var btn := PUi.button("이 자동기술로 시작", func(): main.start_run(id), true, 14)
		box.add_child(btn)
		if first == null:
			first = btn
		row.add_child(p)
	default_button = first
	bottom.add_child(PUi.button("돌아가기", func(): main.go_title(), true, 14))
