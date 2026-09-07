class_name PForgeScreen
extends PScreen
## 대장간(HTML shop 'forge'·'skills' 탭 + swap 화면): 공용 공격 강화 · 개조 변경 · E 변형 변경 · 기술 교체(3단계: 새 기술 → 개조 선택 → 확인).
## 견적·경고·비용은 PRun.swap_quote / swap_warnings / forge_next / mod_change_cost 가 준다. 취소는 아무것도 바꾸지 않는다.

var _swap: Dictionary = {}   # {slot, index, new_id, mods[]} — 비어 있으면 교체 중 아님

func on_escape() -> bool:
	if not _swap.is_empty():
		_swap = {}
		refresh()
		return true
	return false

func on_enter() -> void:
	_swap = {}
	super.on_enter()

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	if not _swap.is_empty():
		_swap_view(r)
		return
	top.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]시간 소모 없음[/color]" % PGlossaryTip.term("forge", "대장간"), 20))
	var g: Dictionary = r.growth
	var b := PBuild.derive(r)
	var SH := PCatalog.shop()
	var cols := two_cols(0.5)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	# 공용 공격 강화
	var F := PRun.forge_next(r)
	var fc := PUi.card("%s [color=#9ea8b8]현재 %d단계 · 자동기술 피해 ×%s[/color]" % [PGlossaryTip.term("forge", "공용 공격 강화"), int(r.get("forge", 0)), PUi.fmt(float(b.forge_mult))], PUi.CARD_ON if (not F.is_empty() and bool(F.open) and bool(F.affordable)) else PUi.CARD)
	var fbox: VBoxContainer = fc.box
	if F.is_empty():
		fbox.add_child(PUi.rich("[color=#9ea8b8]최대 단계[/color]", 13))
	else:
		fbox.add_child(PUi.rich("%d단계: 자동기술 피해 ×%s · 금화 [color=%s][b]%d[/b][/color]%s" % [int(F.lv), PUi.fmt(1.0 + float(SH.forgeMult[int(F.lv)])), "#ff8c73" if int(r.gold) < int(F.cost) else "#ffd966", int(F.cost), (" [color=#ff8c73]· 보스 %d 처치 후 개방[/color]" % int(F.afterBoss)) if not bool(F.open) else ""], 13))
		var lbl := "잠김" if not bool(F.open) else ("강화" if bool(F.affordable) else "%d 부족" % (int(F.cost) - int(r.gold)))
		fbox.add_child(PUi.button(lbl, func(): main.forge_upgrade(), bool(F.open) and bool(F.affordable), 13))
	var costs := []
	for f in SH.forge:
		costs.append(str(int(f.cost)))
	fbox.add_child(PUi.rich("[color=#9ea8b8]단계별 %s · 2단계는 1보스, 3단계는 2보스 처치 후[/color]" % " / ".join(costs), 11))
	left.add_child(fc.panel)
	# 개조·변형 변경
	var mc := PRun.mod_change_cost(r)
	var vc := PRun.variant_change_cost(r)
	var no_offer: bool = g.get("pendingOffer", null) == null
	var cc := PUi.card("%s·%s 변경 [color=#9ea8b8]같은 기술의 다른 후보 3택 · %d금 또는 %s[/color]" % [PGlossaryTip.term("mod", "개조"), PGlossaryTip.term("variant", "변형"), int(SH.modChange), PGlossaryTip.term("voucher", "교체권")])
	var cbox: VBoxContainer = cc.box
	var any := false
	for w in g.weapons:
		var wid := String(w.id)
		var wd := PCatalog.weapon(wid)
		for m in w.mods:
			any = true
			var mid := String(m)
			var row := PUi.hbox(8)
			row.add_child(PUi.rich("[b]%s[/b]: %s" % [PGlossaryTip.esc(String(wd.name)), PGlossaryTip.esc(String(wd.mods[mid].name))], 13))
			var ok: bool = no_offer and (bool(mc.voucher) or int(r.gold) >= int(mc.gold))
			row.add_child(PUi.button("변경 (%s)" % ("교체권" if bool(mc.voucher) else "%d금" % int(mc.gold)), func(): main.mod_change(wid, mid), ok, 12))
			cbox.add_child(row)
	if not any:
		cbox.add_child(PUi.rich("[color=#6a7078]변경할 개조 없음[/color]", 12))
	var e = g.skills.get("e", null)
	if e != null and e.get("variant", null) != null:
		var ed: Dictionary = PCatalog.skills()[String(e.id)]
		var row2 := PUi.hbox(8)
		row2.add_child(PUi.rich("[b]E %s[/b]: %s" % [PGlossaryTip.esc(String(ed.name)), PGlossaryTip.esc(String(ed.variants[String(e.variant)].name))], 13))
		var ok2: bool = no_offer and (bool(vc.voucher) or int(r.gold) >= int(vc.gold))
		row2.add_child(PUi.button("변경 (%s)" % ("교체권" if bool(vc.voucher) else "%d금" % int(vc.gold)), func(): main.variant_change(), ok2, 12))
		cbox.add_child(row2)
	else:
		cbox.add_child(PUi.rich("[color=#6a7078]E 변형 없음[/color]", 12))
	cbox.add_child(PUi.rich("[color=#9ea8b8]후보가 없으면 아무것도 차감되지 않습니다. 3택에서 '받지 않음'을 고르면 원래 개조가 유지되고 비용은 돌려받습니다.[/color]", 11))
	left.add_child(cc.panel)
	# 기술 교체
	var SW: Dictionary = SH.swap
	var sc := PUi.card("보유 %s [color=#9ea8b8]%d + (레벨−1)×%d + 개조×%d[/color]" % [PGlossaryTip.term("swap", "기술 교체"), int(SW.base), int(SW.perLevel), int(SW.perMod)])
	var sbox: VBoxContainer = sc.box
	for i in (g.weapons as Array).size():
		var w: Dictionary = g.weapons[i]
		var q := PRun.swap_quote(r, "weapon", i)
		var row := PUi.hbox(8)
		row.add_child(PUi.rich("[b]%s[/b] Lv%d · 개조 %d [color=#9ea8b8]→ 교체 %d금 (레벨·개조 수 보존, 새 개조는 새 기술에서 선택)[/color]" % [PGlossaryTip.esc(String(PCatalog.weapon(String(w.id)).name)), int(w.level), (w.mods as Array).size(), int(q.price)], 13))
		var has_opt: bool = (q.options as Array).size() > 0
		var idx := i
		row.add_child(PUi.button(("교체" if bool(q.affordable) else "%d 부족" % (int(q.price) - int(r.gold))) if has_opt else "후보 없음", func(): _swap_open("weapon", idx), has_opt and bool(q.affordable), 12))
		sbox.add_child(row)
	if e != null:
		var q2 := PRun.swap_quote(r, "e", 0)
		var row3 := PUi.hbox(8)
		row3.add_child(PUi.rich("[b]E %s[/b] Lv%d%s [color=#9ea8b8]→ 교체 %d금[/color]" % [PGlossaryTip.esc(String(PCatalog.skills()[String(e.id)].name)), int(e.level), " · 변형 1" if e.get("variant", null) != null else "", int(q2.price)], 13))
		var has_opt2: bool = (q2.options as Array).size() > 0
		row3.add_child(PUi.button(("교체" if bool(q2.affordable) else "%d 부족" % (int(q2.price) - int(r.gold))) if has_opt2 else "후보 없음", func(): _swap_open("e", 0), has_opt2 and bool(q2.affordable), 12))
		sbox.add_child(row3)
	else:
		sbox.add_child(PUi.rich("[color=#6a7078]E 없음[/color]", 12))
	sbox.add_child(PUi.rich("[color=#9ea8b8]교체하면 옛 기술은 남지 않습니다. 확정 전까지 금화는 차감되지 않습니다.[/color]", 11))
	right.add_child(sc.panel)
	right.add_child(PUi.build_panel(r))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	bottom.add_child(PUi.button("상점", func(): main.show("shop"), true, 14))
	bottom.add_child(PUi.button("장비", func(): main.show("equip"), true, 14))
	default_button = back

# ---------- 기술 교체 흐름 ----------
func _swap_open(slot: String, index: int) -> void:
	_swap = { "slot": slot, "index": index, "new_id": "", "mods": [] }
	refresh()

func _swap_view(r: Dictionary) -> void:
	var slot := String(_swap.slot)
	var index := int(_swap.index)
	var q := PRun.swap_quote(r, slot, index)
	if q.is_empty():
		_swap = {}
		refresh()
		return
	var is_e := slot == "e"
	var cur_name := String(PCatalog.skills()[String(q.current.id)].name) if is_e else String(PCatalog.weapon(String(q.current.id)).name)
	var hrow := PUi.hbox(8)
	hrow.add_child(PUi.rich("[b]기술 교체[/b] [color=#9ea8b8]%s Lv%d%s → 비용[/color] [color=#ffd966][b]%d[/b][/color]" % [PGlossaryTip.esc(cur_name), int(q.level), (" · 개조 %d개 보존" % int(q.modCount)) if int(q.modCount) > 0 else "", int(q.price)], 20))
	hrow.add_child(PUi.spacer())
	hrow.add_child(PUi.button("취소 (변경 없음, Esc)", func(): on_escape(), true, 13))
	top.add_child(hrow)
	var new_id := String(_swap.new_id)
	if new_id == "":
		top.add_child(PUi.rich("[color=#9ea8b8]1/3 새 기술을 고르세요. 레벨 %d과 개조 수 %d은 그대로 이어집니다.[/color]" % [int(q.level), int(q.modCount)], 13))
		var row := PUi.hbox(10)
		for oid in q.options:
			var id := String(oid)
			var d: Dictionary = PCatalog.skills()[id] if is_e else PCatalog.weapon(id)
			var c := PUi.card("", PUi.CARD)
			var p: PanelContainer = c.panel
			p.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var box: VBoxContainer = c.box
			box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.term(("e:" if is_e else "w:") + id, String(d.name)), 15))
			box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 12))
			if not is_e:
				var tmp: Dictionary = r.duplicate(true)
				tmp.growth.weapons[index] = { "id": id, "level": int(q.level), "mods": [] }
				var ws: Dictionary = PBuild.derive(tmp).weapons[index]
				var mods := []
				for m in d.mods:
					if bool(d.mods[m].impl):
						mods.append(String(d.mods[m].name))
				box.add_child(PUi.rich("[color=#9ea8b8]Lv%d 피해 %s · 주기 %s초 · 개조 후보: %s[/color]" % [int(q.level), PUi.fmt(float(ws.damage)), PUi.fmt(float(ws.interval)), ", ".join(mods)], 11))
			box.add_child(PUi.spacer())
			box.add_child(PUi.button("이 기술로", func(): _swap_pick(id), true, 13))
			row.add_child(p)
		body.add_child(row)
		return
	var d2: Dictionary = PCatalog.skills()[new_id] if is_e else PCatalog.weapon(new_id)
	var pool := []
	if is_e:
		for v in d2.get("variants", {}):
			if bool(d2.variants[v].impl):
				pool.append(String(v))
	else:
		for m in d2.mods:
			if bool(d2.mods[m].impl):
				pool.append(String(m))
	var need := mini(int(q.modCount), pool.size())
	var chosen: Array = _swap.mods
	var chosen_names := []
	for m in chosen:
		chosen_names.append(String((d2.variants if is_e else d2.mods)[String(m)].name))
	if chosen.size() < need:
		top.add_child(PUi.rich("[color=#9ea8b8]2/3 %s의 %s를 %d개 고르세요 (%d/%d).%s[/color]" % [PGlossaryTip.esc(String(d2.name)), "변형" if is_e else "개조", need, chosen.size(), need, (" 선택: " + ", ".join(chosen_names)) if chosen.size() > 0 else ""], 13))
		var row2 := PUi.hbox(10)
		for m in pool:
			var mid := String(m)
			if chosen.has(mid):
				continue
			var md: Dictionary = (d2.variants if is_e else d2.mods)[mid]
			var c := PUi.card("", PUi.CARD)
			var p: PanelContainer = c.panel
			p.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var box: VBoxContainer = c.box
			box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.esc(String(md.name)), 15))
			box.add_child(PUi.rich(PGlossaryTip.esc(String(md.desc)), 12))
			box.add_child(PUi.spacer())
			box.add_child(PUi.button("선택", func(): _swap_mod(mid), true, 13))
			row2.add_child(p)
		body.add_child(row2)
		bottom.add_child(PUi.button("처음부터", func(): _swap_open(slot, index), true, 13))
		return
	top.add_child(PUi.rich("[color=#9ea8b8]3/3 확인[/color]", 13))
	var warns := [] if is_e else PRun.swap_warnings(r, slot, index, new_id)
	var cc := PUi.card("")
	var cbox: VBoxContainer = cc.box
	PUi.kv(cbox, "바뀌는 것", "[b]%s Lv%d → %s Lv%d[/b]" % [PGlossaryTip.esc(cur_name), int(q.level), PGlossaryTip.esc(String(d2.name)), int(q.level)], 13)
	PUi.kv(cbox, "변형" if is_e else "개조", "[b]%s[/b]%s" % [(", ".join(chosen_names) if chosen_names.size() > 0 else "없음"), (" [color=#9ea8b8](후보가 %d개뿐이라 %d개는 비어 있음 · 비용은 동일)[/color]" % [need, int(q.modCount) - need]) if int(q.modCount) > need else ""], 13)
	PUi.kv(cbox, "비용", "[color=#ffd966][b]%d[/b][/color] [color=#9ea8b8](남는 금화 %d)[/color]" % [int(q.price), int(r.gold) - int(q.price)], 13)
	if not is_e:
		var before: Dictionary = PBuild.derive(r).weapons[index]
		var tmp2: Dictionary = r.duplicate(true)
		var mods_out := []
		for m in chosen:
			mods_out.append(String(m))
		tmp2.growth.weapons[index] = { "id": new_id, "level": int(q.level), "mods": mods_out }
		var after: Dictionary = PBuild.derive(tmp2).weapons[index]
		PUi.kv(cbox, "수치", "피해 %s → %s · 주기 %s → %s초" % [PUi.fmt(float(before.damage)), PUi.fmt(float(after.damage)), PUi.fmt(float(before.interval)), PUi.fmt(float(after.interval))], 13)
	if warns.size() > 0:
		var wn := []
		for w in warns:
			wn.append(PGlossaryTip.esc(String(w)))
		PUi.kv(cbox, "[color=#ff8c73]경고[/color]", "[color=#ff8c73]공용 증강 %s이(가) 적용 대상을 잃습니다[/color]" % ", ".join(wn), 13)
	var row3 := PUi.hbox(8)
	var confirm := PUi.button("확정 (금화 %d 차감)" % int(q.price), func(): _swap_confirm(), bool(q.affordable), 14)
	row3.add_child(confirm)
	row3.add_child(PUi.button("취소 (변경 없음)", func(): on_escape(), true, 14))
	cbox.add_child(row3)
	body.add_child(cc.panel)
	default_button = confirm

func _swap_pick(id: String) -> void:
	_swap.new_id = id
	_swap.mods = []
	refresh()

func _swap_mod(m: String) -> void:
	if not (_swap.mods as Array).has(m):
		(_swap.mods as Array).append(m)
	refresh()

func _swap_confirm() -> void:
	var sw := _swap
	_swap = {}
	main.apply_swap(String(sw.slot), int(sw.index), String(sw.new_id), sw.mods)
