class_name PEventScreen
extends PScreen
## 탐험 사건(HTML event): 비용·위험을 먼저 보여 주고 선택(PEvents.options → PEvents.resolve). 선택은 1회.

func refresh() -> void:
	clear_all()
	var r := run()
	var s: Dictionary = main.sortie
	if r.is_empty() or s.is_empty() or s.get("event", null) == null:
		return
	var ev: Dictionary = s.event
	var E: Dictionary = PCatalog.events()[String(ev.id)]
	var b := PBuild.derive(r)
	heading("%s · %s" % [PGlossaryTip.esc(String(PRun.region(String(s.regionId)).name)), PGlossaryTip.esc(String(E.name))])
	body.add_child(PUi.rich(PGlossaryTip.esc(String(E.desc)), 14))
	body.add_child(PUi.rich("[color=#9ea8b8]체력 %d / %d · 오늘 남은 시간 %d · 이번 출격 전리품 금화 %d[/color]" % [int(float(r.hp)), int(float(b.hp_max)), int(r.hours), int(s.loot.gold)], 12))
	var row := PUi.hbox(10)
	var first: Button = null
	for o in PEvents.options(r, s):
		var opt: Dictionary = o
		var en := bool(opt.enabled)
		var c := PUi.card("", PUi.CARD_ON if en else PUi.CARD_OFF)
		var p: PanelContainer = c.panel
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box: VBoxContainer = c.box
		box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.esc(String(opt.name)), 15))
		PUi.kv(box, "비용·위험", "[b]%s[/b]" % PGlossaryTip.esc(String(opt.cost)), 12)
		PUi.kv(box, "효과", "[b]%s[/b]" % PGlossaryTip.esc(String(opt.effect)), 12)
		box.add_child(PUi.spacer())
		var oid := String(opt.id)
		var btn := PUi.button("선택" if en else "불가", func(): main.event_choice(oid), en, 14)
		box.add_child(btn)
		if first == null and en:
			first = btn
		row.add_child(p)
	body.add_child(row)
	body.add_child(PUi.rich("[color=#9ea8b8]사건은 출격당 최대 1회, 선택은 되돌릴 수 없습니다. 비용과 보상은 선택 즉시 1회 정산됩니다.[/color]", 11))
	default_button = first
