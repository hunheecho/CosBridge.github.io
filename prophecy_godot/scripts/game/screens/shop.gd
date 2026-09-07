class_name PShopScreen
extends PScreen
## 상점(HTML shop 탭 stock/skills/merchant + 판매): 오늘의 재고 장비 2 · 기술 1 · 방문 상인 · 판매(장착+가방) · 재료 판매.
## 가격·구매 가능 여부·사유는 PRun이 준다(equip_price_for / can_buy_* / sell_price).

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	var hrow := PUi.hbox(8)
	hrow.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]시간 소모 없음 · 재고는 날마다 정해지며 다시 열어도 같습니다. 같은 장비는 두 번 살 수 없습니다.[/color]" % PGlossaryTip.term("shop", "상점"), 20))
	top.add_child(hrow)
	var st := PRun.stock(r)
	var SH := PCatalog.shop()
	body.add_child(PUi.rich("[b]오늘의 재고[/b] [color=#9ea8b8]판매가: 무기 %d · 방어구 %d · 방패 %d%s[/color]" % [int(SH.sellPrice.weapon), int(SH.sellPrice.armor), int(SH.sellPrice.shield), "  · [color=#ffe066]할인권 보유[/color]" if PRun.has_service(r, "shop_discount") else ""], 15))
	var row := PUi.hbox(10)
	for id in st.equipment:
		row.add_child(_equip_card(r, String(id), "stock"))
	row.add_child(_skill_card(r, st))
	body.add_child(row)
	# 방문 상인
	var m = r.get("merchant", null)
	if m != null and int(m.day) == int(r.day):
		if PRun.merchant_open(r):
			body.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]오늘 끝까지 · 장비 %d%% 할인[/color]" % [PGlossaryTip.term("merchant", "방문 상인"), int(round(float(SH.merchantDiscount) * 100.0))], 15))
			var mrow := PUi.hbox(10)
			if m.get("equipment", null) != null:
				mrow.add_child(_equip_card(r, String(m.equipment), "merchant"))
			var sc := PUi.card("무료 휴식권 [color=#9ea8b8]서비스[/color]", PUi.CARD_ON if PRun.can_buy_merchant_service(r) else PUi.CARD)
			var sb: VBoxContainer = sc.box
			sb.add_child(PUi.rich(PGlossaryTip.esc(String(PCatalog.services().free_rest.desc)), 12))
			sb.add_child(PUi.rich("금화 [color=#ffd966][b]%d[/b][/color]" % int(m.servicePrice), 13))
			var sold_sv: bool = (m.sold as Array).has("service")
			sb.add_child(PUi.button("판매됨" if sold_sv else "구매", func(): main.buy_merchant_service(), PRun.can_buy_merchant_service(r), 13))
			mrow.add_child(sc.panel)
			mrow.add_child(PUi.spacer())
			body.add_child(mrow)
		else:
			body.add_child(PUi.rich("[color=#9ea8b8]방문 상인은 %s부터 옵니다.[/color]" % String(PRun.time_slots()[int(m.fromSlot)]), 12))
	# 판매
	var sell := PUi.card("판매 [color=#9ea8b8]장착 중 + %s[/color]" % PGlossaryTip.term("bag", "가방"), PUi.CARD, 14)
	var sbox: VBoxContainer = sell.box
	var any := false
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var eid = r.equipment.get(slot, null)
		if eid == null:
			continue
		any = true
		var srow := PUi.hbox(8)
		srow.add_child(PUi.rich("[color=#9ea8b8]%s(장착)[/color] %s" % [PUi.slot_name(slot), PUi.equip_line(String(eid))], 12))
		var sid := String(eid)
		srow.add_child(PUi.button("판매 +%d" % PRun.sell_price(sid), func(): main.sell_equipment(sid), true, 12))
		sbox.add_child(srow)
	for id in r.bag:
		any = true
		var bid := String(id)
		var brow := PUi.hbox(8)
		brow.add_child(PUi.rich("[color=#9ea8b8]가방 · %s[/color] %s" % [PUi.slot_name(String(PCatalog.equipment()[bid].slot)), PUi.equip_line(bid)], 12))
		brow.add_child(PUi.button("판매 +%d" % PRun.sell_price(bid), func(): main.sell_equipment(bid), true, 12))
		sbox.add_child(brow)
	if not any:
		sbox.add_child(PUi.rich("[color=#6a7078]팔 장비 없음[/color]", 12))
	var mrow2 := PUi.hbox(8)
	mrow2.add_child(PUi.rich_nowrap("[b]재료 판매[/b]", 13))
	var any_m := false
	var MT := PCatalog.materials()
	for k in r.mats:
		if int(r.mats[k]) > 0:
			any_m = true
			var mid := String(k)
			mrow2.add_child(PUi.rich_nowrap("%s [b]%d[/b]" % [PGlossaryTip.esc(String(MT[mid].name)), int(r.mats[k])], 12))
			mrow2.add_child(PUi.button("1개 판매 (+%d)" % int(MT[mid].sell), func(): main.sell_mat(mid), true, 12))
	if not any_m:
		mrow2.add_child(PUi.rich_nowrap("[color=#6a7078]재료 없음[/color]", 12))
	mrow2.add_child(PUi.spacer())
	sbox.add_child(mrow2)
	body.add_child(sell.panel)
	body.add_child(PUi.equip_panel(r))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	bottom.add_child(PUi.button("대장간", func(): main.show("forge"), true, 14))
	bottom.add_child(PUi.button("장비", func(): main.show("equip"), true, 14))
	default_button = back

func _equip_card(r: Dictionary, id: String, from: String) -> Control:
	var d: Dictionary = PCatalog.equipment()[id]
	var target: Dictionary = r.merchant if from == "merchant" else PRun.stock(r)
	var sold: bool = (target.sold as Array).has(id) or PRun.owns_equip(r, id)
	var price := PRun.equip_price_for(r, id, from)
	var can := PRun.can_buy_equipment(r, id, from)
	var c := PUi.card("", PUi.CARD_ON if can else (PUi.CARD_OFF if sold else PUi.CARD))
	var p: PanelContainer = c.panel
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.term("eq:" + id, String(d.name)), PUi.slot_name(String(d.slot))], 15))
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 13))
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 11))
	var cur = r.equipment.get(String(d.slot), null)
	PUi.kv(box, "현재 %s" % PUi.slot_name(String(d.slot)), PUi.equip_line(String(cur)) if cur != null else "[color=#6a7078]없음[/color]", 11)
	var note := _compare_note(r, d)
	if note != "":
		PUi.kv(box, "주의", note, 11)
	var reason := ""
	if sold:
		reason = " · 보유/판매됨"
	elif int(r.gold) < price:
		reason = " (%d 부족)" % (price - int(r.gold))
	var extra := (" [color=#9ea8b8](상인 할인 %d%%)[/color]" % int(round(float(PCatalog.shop().merchantDiscount) * 100.0))) if from == "merchant" else ""
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s%s%s" % ["#ff8c73" if int(r.gold) < price else "#ffd966", price, reason, extra, " [color=#ffe066]할인권 적용[/color]" if (PRun.has_service(r, "shop_discount") and not sold) else ""], 13))
	box.add_child(PUi.spacer())
	var row := PUi.hbox(6)
	row.add_child(PUi.button("구매 후 장착", func(): main.buy_equipment(id, true, from), can, 12))
	row.add_child(PUi.button("구매 후 보관", func(): main.buy_equipment(id, false, from), can, 12))
	box.add_child(row)
	return p

## 장비 비교 주의(HTML equipCompare): 지금 빌드에서 효과가 없는 조건
func _compare_note(r: Dictionary, d: Dictionary) -> String:
	var g: Dictionary = r.growth
	var eff: Dictionary = d.eff
	if String(d.get("needs", "")) == "dot":
		var has_bleed := false
		for w in g.weapons:
			if (w.mods as Array).has("bleed"):
				has_bleed = true
		if not PGrowth.has_fire_source(g) and not has_bleed and int(g.commons.get("frost", 0)) == 0:
			return "[color=#ff8c73]지금 빌드에는 지속 피해 원천이 없어 효과가 없음[/color]"
	if eff.has("eliteDirect"):
		var any_elite := false
		for c in PSortie.cards_for(r):
			for e in c.enemies:
				if bool(PCatalog.enemy(String(e)).get("elite", false)):
					any_elite = true
		if not any_elite:
			return "[color=#9ea8b8]오늘 장소에는 정예가 없음[/color]"
	if eff.has("fieldDirect") or eff.has("fieldTaken"):
		return "[color=#9ea8b8]감속장(Q) 안에서만[/color]"
	if eff.has("eShield") and g.skills.get("e", null) == null:
		return "[color=#ff8c73]E 기술이 없어 발동 없음[/color]"
	return ""

func _skill_card(r: Dictionary, st: Dictionary) -> Control:
	var g: Dictionary = r.growth
	var S: Dictionary = PCatalog.growth().SLOTS
	var sk = st.get("skill", null)
	var sold: bool = (st.sold as Array).has("skill")
	var can := PRun.can_buy_skill(r)
	var c := PUi.card("", PUi.CARD_ON if can else (PUi.CARD_OFF if (sk == null or sold) else PUi.CARD))
	var p: PanelContainer = c.panel
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = c.box
	if sk == null:
		box.add_child(PUi.rich("[b]새 기술[/b]", 15))
		box.add_child(PUi.rich("[color=#9ea8b8]빈 슬롯이 없어 오늘 기술 재고 없음[/color]", 12))
		return p
	var is_w: bool = String(sk.kind) == "weapon"
	var d: Dictionary = PCatalog.weapons()[String(sk.id)] if is_w else PCatalog.skills()[String(sk.id)]
	var term_id := ("w:" if is_w else "e:") + String(sk.id)
	box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s · Lv1 · 개조 없음[/color]" % [PGlossaryTip.term(term_id, String(d.name)), "새 자동기술" if is_w else "새 E 기술"], 15))
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 13))
	var why := ""
	if sold:
		why = "구매함"
	elif is_w and (g.weapons as Array).size() >= int(S.weapons):
		why = "자동기술 슬롯 가득"
	elif not is_w and g.skills.get("e", null) != null:
		why = "E 슬롯 사용 중"
	elif int(r.gold) < int(sk.price):
		why = "%d 부족" % (int(sk.price) - int(r.gold))
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s" % ["#ff8c73" if int(r.gold) < int(sk.price) else "#ffd966", int(sk.price), (" [color=#9ea8b8]· %s[/color]" % why) if why != "" else ""], 13))
	box.add_child(PUi.spacer())
	box.add_child(PUi.button("구매 (빈 슬롯에 장착)", func(): main.buy_skill(), can, 12))
	return p
