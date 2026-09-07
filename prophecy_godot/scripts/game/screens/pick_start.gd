class_name PPickStartScreen
extends PScreen
## 시작 자동기술 선택(HTML pickStart): 프로필 해금(PProfile.unlocked().start_weapons — 프로필이 없으면 PCatalog.startable())의 이름·설명·실제 파생 수치(PBuild.derive) → PRun.new_run.
## 위에 이번 회차에 고정될 영구 특성 요약을 보여 준다(재선택은 영구 성장 화면, 출발하면 고정).

func refresh() -> void:
	clear_all()
	var C := PCatalog.config()
	var p: Dictionary = main.profile
	heading("시작 자동기술 선택")
	top.add_child(PUi.rich("[color=#9ea8b8]자동기술 1개(Lv1, 개조 없음) · 감속장(Q) Lv1 · 체력 %d · 금화 %d으로 1일차 %s에 시작합니다. 자동기술은 최대 %d개, 장비(무기·방어구·방패)는 상점에서 삽니다.[/color]" % [int(C.PLAYER.hp), int(C.START_GOLD), String(PRun.time_slots()[0]), int(PCatalog.growth().SLOTS.weapons)], 13))
	var startable: Array = PCatalog.startable()
	if not p.is_empty():
		var u := PProfile.unlocked(p)
		startable = u.start_weapons
		var sel := PProfile.selected_traits(p)
		var names := []
		var D := PCatalog.trait_defs()
		for id in sel:
			names.append("[b]%s[/b]" % PGlossaryTip.esc(String(D[String(id)].name)))
		var cnt := PProfile.counts(p)
		top.add_child(PUi.rich("%s Lv%d · %s: %s [color=#9ea8b8](출발하면 이번 회차 동안 고정 · 재선택은 영구 성장 화면)[/color] · 시작 가능 %d/%d · 회차 중 획득 %d/%d" % [PGlossaryTip.term("meta", "영구"), PProfile.level(p), PGlossaryTip.term("trait", "특성"), (", ".join(names) if names.size() > 0 else "[color=#6a7078]없음[/color]"), int(cnt.start.have), int(cnt.start.total), int(cnt.weapons.have), int(cnt.weapons.total)], 12))
	var row := PUi.hbox(10)
	body.add_child(row)
	var first: Button = null
	for wid in startable:
		var id := String(wid)
		var d := PCatalog.weapon(id)
		var tmp := PRun.new_run(1, id)
		var b := PBuild.derive(tmp)
		var ws: Dictionary = b.weapons[0]
		var c := PUi.card("", PUi.CARD)
		var pnl: PanelContainer = c.panel
		pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box: VBoxContainer = c.box
		box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.term("w:" + id, String(d.name)), 17))
		box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 13))
		var mods := []
		for mid in d.mods:
			if bool(d.mods[mid].impl) and (p.is_empty() or PProfile.run_unlock_ok({ "unlocks": PProfile.unlocked(p) }, "mods", id, String(mid))):
				mods.append(String(d.mods[mid].name))
		var rng_txt := (" · 사거리 %d" % int(round(float(ws.range)))) if float(ws.range) > 0.0 else ""
		box.add_child(PUi.rich("[color=#9ea8b8]기본 피해 %s · 주기 %s초%s · 개조 후보: %s[/color]" % [PUi.fmt(float(ws.damage)), PUi.fmt(float(ws.interval)), rng_txt, ", ".join(mods)], 12))
		box.add_child(PUi.spacer())
		var btn := PUi.button("이 자동기술로 시작", func(): main.start_run(id), true, 14)
		box.add_child(btn)
		if first == null:
			first = btn
		row.add_child(pnl)
	default_button = first
	bottom.add_child(PUi.button("돌아가기", func(): main.go_title(), true, 14))
	if not p.is_empty():
		bottom.add_child(PUi.button("영구 성장(특성 재선택)", func(): main.show_meta(), true, 14))
