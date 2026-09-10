class_name PShopScreen
extends PScreen
## 상점(HTML shop 탭 stock/skills/merchant + 판매): 오늘의 재고 장비 2 · 기술 1 · 유료 새로고침/잠금 · 출격 준비물 · 회복약 · 방문 상인 · 판매(장착+가방) · 재료 판매.
## 가격·구매 가능 여부·사유는 PRun이 준다(equip_price_for / can_buy_* / sell_price).
##
## 읽기 우선순위(사람 플레이 뒤 요구 2026-09-08): 이름 · 핵심 효과 · 비용 · 실제 변화량.
## 구현 설명·긴 문장·반복 안내는 카드의 '상세'로 옮긴다(기본 화면에 두지 않는다).

var _detail := ""   # 상세를 펼친 재고 id("" = 없음)

func on_enter() -> void:
	_detail = ""
	super.on_enter()

func on_escape() -> bool:
	if super.on_escape(): # 확인 창이 열려 있으면 먼저 닫는다(아무것도 바뀌지 않는다)
		return true
	if _detail != "":
		_detail = ""
		refresh()
		return true
	return false

func refresh() -> void:
	clear_all()
	close_confirm()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	var hrow := PUi.hbox(8)
	hrow.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]시간 소모 없음[/color]" % PGlossaryTip.term("shop", "상점"), 22))
	top.add_child(hrow)
	var st := PRun.stock(r)
	var SH := PCatalog.shop()
	body.add_child(PUi.rich("[b]오늘의 재고[/b]%s" % ("  [color=#ffe066]할인권 보유[/color]" if PRun.has_service(r, "shop_discount") else ""), 17))
	_refresh_row(r, st)
	# §8: 진열 2 → 4. **한 줄에 네 칸을 밀어 넣으면 마지막 칸이 화면 밖으로 잘린다** —
	# 카드 폭은 글자 배율·긴 설명에 따라 커지므로 줄당 2칸으로 접는다(2줄 × 2칸). 기술 칸은 그 아래 자기 줄에 둔다
	var per_row := 2
	var row := PUi.hbox(10)
	var n_eq := 0
	for id in st.equipment:
		row.add_child(_equip_card(r, String(id), "stock"))
		n_eq += 1
		if n_eq % per_row == 0:
			body.add_child(row)
			row = PUi.hbox(10)
	if n_eq % per_row != 0:
		while n_eq % per_row != 0: # 마지막 줄이 한 칸이면 빈 자리를 채워 카드가 가로로 늘어나지 않게 한다
			row.add_child(PUi.spacer())
			n_eq += 1
		body.add_child(row)
	var skrow := PUi.hbox(10)
	skrow.add_child(_skill_card(r, st))
	skrow.add_child(PUi.spacer())
	body.add_child(skrow)
	_prep_section(r, st)
	# 방문 상인
	var m = r.get("merchant", null)
	if m != null and int(m.day) == int(r.day):
		if PRun.merchant_open(r):
			body.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]오늘 끝까지 · 장비 %d%% 할인[/color]" % [PGlossaryTip.term("merchant", "방문 상인"), int(round(float(SH.merchantDiscount) * 100.0))], 15))
			var mrow := PUi.hbox(10)
			if m.get("equipment", null) != null:
				mrow.add_child(_equip_card(r, String(m.equipment), "merchant"))
			# 이 권은 '무료'가 아니다: 쓸 때 시간이 들지 않을 뿐이고 사는 값은 100금이다(사용자 지시 2026-09-09)
			var sc := PUi.card("%s [color=#9ea8b8]%s[/color]" % [PUi.rest_ticket_name(), PUi.rest_ticket_note()], PUi.CARD_ON if PRun.can_buy_merchant_service(r) else PUi.CARD)
			var sb: VBoxContainer = sc.box
			sb.add_child(PUi.rich("체력을 완전히 회복하고 [b]시간 0칸[/b]을 씁니다(보통 휴식은 1칸).", 12))
			sb.add_child(PUi.rich("구매 금화 [color=%s][b]%d[/b][/color]%s" % ["#ff8c73" if int(r.gold) < int(m.servicePrice) else "#ffd966", int(m.servicePrice), (" [color=#ff8c73](%d 부족)[/color]" % (int(m.servicePrice) - int(r.gold))) if int(r.gold) < int(m.servicePrice) else ""], 15))
			var sold_sv: bool = (m.sold as Array).has("service")
			sb.add_child(PUi.button("판매됨" if sold_sv else "구매 (%d)" % int(m.servicePrice), func(): main.buy_merchant_service(), PRun.can_buy_merchant_service(r), 13))
			mrow.add_child(sc.panel)
			mrow.add_child(PUi.spacer())
			body.add_child(mrow)
		else:
			body.add_child(PUi.rich("[color=#9ea8b8]방문 상인은 %s부터 옵니다.[/color]" % String(PRun.time_slots()[int(m.fromSlot)]), 12))
	# 판매
	var sell := PUi.card("판매 [color=#9ea8b8]장착 중 + %s[/color]" % PGlossaryTip.term("bag", "가방"), PUi.CARD, 16)
	var sbox: VBoxContainer = sell.box
	var any := false
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var eid = r.equipment.get(slot, null)
		if eid == null:
			continue
		any = true
		var srow := PUi.hbox(8)
		srow.add_child(PUi.rich("[color=#9ea8b8]%s(장착)[/color] %s" % [PUi.slot_name(slot), PUi.equip_line(String(eid), r)], 14))
		var sid := String(eid)
		srow.add_child(PUi.button("판매 +%d" % int(PRun.sell_quote(main.run, sid).gold), func(): open_sell_confirm(sid), true, 12))
		sbox.add_child(srow)
	for id in r.bag:
		any = true
		var bid := String(id)
		var brow := PUi.hbox(8)
		brow.add_child(PUi.rich("[color=#9ea8b8]가방 · %s[/color] %s" % [PUi.slot_name(String(PCatalog.equipment_def(PRun.equip_type_of(bid)).slot)), PUi.equip_line(bid, r)], 14))
		brow.add_child(PUi.button("판매 +%d" % int(PRun.sell_quote(main.run, bid).gold), func(): open_sell_confirm(bid), true, 12))
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

## 규칙 호출 뒤 저장·다시 그리기(main에는 새 함수를 만들지 않는다). 실패하면 이유를 그대로 알린다
func _act(done: bool, fail_msg: String) -> void:
	if done:
		main.save_run()
		refresh()
	else:
		main.message(fail_msg)

## 유료 새로고침 줄: 값·오늘 남은 횟수·초기화 시점·잠금 안내를 한 줄로
func _refresh_row(r: Dictionary, st: Dictionary) -> void:
	var SR: Dictionary = PCatalog.shop().stockRefresh
	var cost := PRun.stock_refresh_cost(r)
	var left := PRun.stock_refresh_left(r)
	var can := PRun.can_refresh_stock(r)
	var row := PUi.hbox(8)
	row.add_child(PUi.button("재고 새로고침 (%d)" % cost, func(): _act(PRun.refresh_stock_paid(r), PRun.stock_refresh_reason(r)), can, 13))
	var why := PRun.stock_refresh_reason(r)
	row.add_child(PUi.rich("[color=#9ea8b8]오늘 %d/%d회 사용 · 다음 값 [b]%d[/b](연속하면 ×%s씩 오름) · 잠근 칸은 유지 · [b]내일 아침[/b]에 횟수·잠금·값 초기화[/color]%s" % [
		int(SR.maxPerDay) - left, int(SR.maxPerDay), cost, PUi.fmt(float(SR.mult)), ("  [color=#ff8c73]%s[/color]" % why) if why != "" else ""], 12))
	row.add_child(PUi.spacer())
	body.add_child(row)
	var lrow := PUi.hbox(6)
	lrow.add_child(PUi.rich_nowrap("[color=#9ea8b8]보존(잠금) 최대 %d칸[/color]" % int(SR.lockMax), 12))
	for id in st.equipment:
		var key := String(id)
		var on := PRun.stock_locked(r, key)
		var lr := PRun.stock_lock_reason(r, key)
		lrow.add_child(PUi.button("%s %s" % ["■" if on else "□", PRun.equip_name(key)], func(): PRun.toggle_stock_lock(r, key); main.save_run(); refresh(), on or lr == "", 12))
	if st.get("skill", null) != null:
		var on_s := PRun.stock_locked(r, "skill")
		var lr_s := PRun.stock_lock_reason(r, "skill")
		lrow.add_child(PUi.button("%s 기술 칸" % ("■" if on_s else "□"), func(): PRun.toggle_stock_lock(r, "skill"); main.save_run(); refresh(), on_s or lr_s == "", 12))
	lrow.add_child(PUi.spacer())
	body.add_child(lrow)

## 출격 준비물 + 회복약. 설명은 짧게(한 줄), 자세한 것은 각 카드의 desc 한 줄만
func _prep_section(r: Dictionary, st: Dictionary) -> void:
	var R := PConsumables.rules()
	body.add_child(PUi.rich("[b]출격 준비물[/b] [color=#9ea8b8]다음 전투 1회 · 출격 전에 %d개 중 1개만 장착 · 가방 %d/%d · 중첩 없음[/color]" % [
		int(R.armedMax), PConsumables.prep_count(r), int(R.carryMax)], 17))
	var row := PUi.hbox(10)
	for id in st.prep:
		row.add_child(_prep_card(r, String(id)))
	row.add_child(_potion_card(r))
	row.add_child(_revive_card(r)) # 부활 물약: 규칙·봇 경로에만 있고 사람이 살 자리가 없었다(2026-09-09 보완)
	body.add_child(row)

func _prep_card(r: Dictionary, id: String) -> Control:
	var d := PConsumables.def(id)
	var can := PConsumables.can_buy(r, id)
	var why := PConsumables.buy_reason(r, id)
	var c := PUi.card("", PUi.CARD_ON if can else PUi.CARD)
	var p: PanelContainer = c.panel
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(d.name)), PGlossaryTip.esc(String(d.roleName))], 15))
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 14))
	box.add_child(PUi.rich("[color=#9ea8b8]보유 %d/%d[/color]" % [PConsumables.count(r, id), int(PConsumables.rules().perItemMax)], 13))
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s" % ["#ff8c73" if int(r.gold) < PConsumables.price(id) else "#ffd966", PConsumables.price(id), (" [color=#9ea8b8]· %s[/color]" % why) if why != "" else ""], 15))
	box.add_child(PUi.spacer())
	box.add_child(PUi.button("준비물 구매", func(): _act(PConsumables.buy(r, id), PConsumables.buy_reason(r, id)), can, 14))
	var open_now: bool = _detail == id
	box.add_child(PUi.button("상세 닫기 ▼" if open_now else "상세 보기 ▶", func(): _detail = ("" if open_now else id); refresh(), true, 12))
	if open_now:
		box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 13))
	return p

func _potion_card(r: Dictionary) -> Control:
	var d := PConsumables.potion_def()
	var can := PConsumables.can_buy(r, "potion")
	var why := PConsumables.buy_reason(r, "potion")
	var c := PUi.card("", PUi.CARD_ON if can else PUi.CARD)
	var p: PanelContainer = c.panel
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]거점 회복[/color]" % PGlossaryTip.esc(String(d.name)), 15))
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 14))
	box.add_child(PUi.rich("[color=#9ea8b8]보유 %d/%d · 오늘 %d개 더 살 수 있음[/color]" % [PConsumables.potion_count(r), int(PConsumables.rules().potionCarryMax), PConsumables.potion_left_today(r)], 13))
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s" % ["#ff8c73" if int(r.gold) < PConsumables.price("potion") else "#ffd966", PConsumables.price("potion"), (" [color=#9ea8b8]· %s[/color]" % why) if why != "" else ""], 15))
	box.add_child(PUi.spacer())
	box.add_child(PUi.button("회복약 구매", func(): _act(PConsumables.buy(r, "potion"), PConsumables.buy_reason(r, "potion")), can, 14))
	box.add_child(PUi.rich("[color=#6a7078]완전 회복은 휴식(시간 1칸) 또는 %s(%d금 · %s).[/color]" % [PUi.rest_ticket_name(), PRun.merchant_service_price("free_rest"), PUi.rest_ticket_note()], 12))
	return p

## 부활 물약. 회복약과 다른 자리(가방 상한도 따로)라 카드도 따로 둔다.
## **언제 어떻게 살아나는지는 날짜에 따라 다르다** — 보통 날은 다음 날, 마지막 날은 같은 날 관문 앞이다.
## 그 한 줄을 PConsumables.revive_when_line(run)에서 그대로 받아 쓴다(화면이 문구를 따로 만들지 않는다).
func _revive_card(r: Dictionary) -> Control:
	var d := PConsumables.revive_def()
	if d.is_empty():
		return PUi.spacer()
	var id := PConsumables.revive_id()
	var can := PConsumables.can_buy(r, id)
	var why := PConsumables.buy_reason(r, id)
	var c := PUi.card("", PUi.CARD_ON if can else PUi.CARD)
	var p: PanelContainer = c.panel
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]회차 보험[/color]" % PGlossaryTip.esc(String(d.name)), 15))
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 14))
	box.add_child(PUi.rich("[color=#ffd966]%s[/color]" % PGlossaryTip.esc(PConsumables.revive_when_line(r)), 13))
	box.add_child(PUi.rich("[color=#9ea8b8]보유 %d/%d[/color]" % [PConsumables.revive_count(r), int(PConsumables.rules().get("reviveCarryMax", 2))], 13))
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s" % ["#ff8c73" if int(r.gold) < PConsumables.price(id) else "#ffd966", PConsumables.price(id), (" [color=#9ea8b8]· %s[/color]" % why) if why != "" else ""], 15))
	box.add_child(PUi.spacer())
	box.add_child(PUi.button("부활 물약 구매", func(): _act(PConsumables.buy(r, id), PConsumables.buy_reason(r, id)), can, 14))
	var open_now: bool = _detail == id
	box.add_child(PUi.button("상세 닫기 ▼" if open_now else "상세 보기 ▶", func(): _detail = ("" if open_now else id); refresh(), true, 12))
	if open_now:
		box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 13))
	return p

func _equip_card(r: Dictionary, id: String, from: String) -> Control:
	var d: Dictionary = PCatalog.equipment_def(id)
	var target: Dictionary = r.merchant if from == "merchant" else PRun.stock(r)
	var sold: bool = (target.sold as Array).has(id) or PRun.owns_equip(r, id)
	var price := PRun.equip_price_for(r, id, from)
	var can := PRun.can_buy_equipment(r, id, from)
	var c := PUi.card("", PUi.CARD_ON if can else (PUi.CARD_OFF if sold else PUi.CARD))
	var p: PanelContainer = c.panel
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = c.box
	var head := PUi.hbox(8)
	head.add_child(PUi.icon_of("equip:" + id, 34.0, "", "", 0.0, 0)) # 장비 아이콘(임시 아이콘 없음 → 중립 자리표시 + 아래 실제 이름)
	head.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.term("eq:" + id, String(d.name)), PUi.slot_name(String(d.slot))], 15))
	box.add_child(head)
	if d.has("roleName"): # 역할(다수 처리·정예 상대·접근·보호막·연계) — 같은 부위 후보를 무엇으로 고를지 먼저 보이게
		box.add_child(PUi.rich("[color=#7fd6a0]역할 · %s[/color]" % PGlossaryTip.esc(String(d.roleName)), 13))
	# §8: **기본 능력치와 고유 효과를 갈라서** 보여 준다(한 줄 요약만으로는 둘이 섞여 읽힌다). 강화로 무엇이 오르는지도 여기서.
	box.add_child(PUi.rich(PUi.equip_effect_lines(id), 14))
	box.add_child(_needs_row(r, id, d))
	box.add_child(PUi.rich("[color=#9ea8b8]장착하면[/color]  %s" % _change_text(r, id), 14))
	box.add_child(_current_row(r, String(d.slot)))
	var note := _compare_note(r, d)
	if note != "":
		box.add_child(PUi.rich(note, 13))
	var reason := ""
	if sold:
		reason = " · 보유/판매됨"
	elif int(r.gold) < price:
		reason = " (%d 부족)" % (price - int(r.gold))
	var extra := (" [color=#9ea8b8](상인 할인 %d%%)[/color]" % int(round(float(PCatalog.shop().merchantDiscount) * 100.0))) if from == "merchant" else ""
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s%s%s" % ["#ff8c73" if int(r.gold) < price else "#ffd966", price, reason, extra, " [color=#ffe066]할인권 적용[/color]" if (PRun.has_service(r, "shop_discount") and not sold) else ""], 15))
	box.add_child(PUi.spacer())
	# 구매는 확인 창을 거치고, 그 자리에서 '지금 장착 / 가방에 넣기'를 고른다(사용자 지시 2026-09-09).
	# 취소하면 금화·가방·장착이 그대로다. 확정은 한 번만 실행되므로 중복 클릭으로 두 번 사지 않는다.
	var buy := PUi.button("구매 (%d금)" % price, func(): _open_buy(id, from), can, 15)
	buy.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	box.add_child(buy)
	# 상세: 구현 설명·현재 슬롯·판매가처럼 매번 읽을 필요 없는 것
	var open_now: bool = _detail == id
	box.add_child(PUi.button("상세 닫기 ▼" if open_now else "상세 보기 ▶", func(): _detail = ("" if open_now else id); refresh(), true, 12))
	if open_now:
		box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 13))
		var cur = r.equipment.get(String(d.slot), null)
		PUi.kv(box, "현재 %s" % PUi.slot_name(String(d.slot)), PUi.equip_line(String(cur), r) if cur != null else "[color=#6a7078]없음[/color]", 13)
		var SH2 := PCatalog.shop()
		PUi.kv(box, "되팔 때", "무기 %d · 방어구 %d · 방패 %d" % [int(SH2.sellPrice.weapon), int(SH2.sellPrice.armor), int(SH2.sellPrice.shield)], 12)
		PUi.kv(box, "규칙", "재고는 날마다 정해지고 다시 열어도 같습니다. 같은 장비는 두 번 살 수 없습니다.", 12)
	return p

## 구매 확인 창: 값·효과·장착 시 변화·교체되는 장비를 보여 주고, 사면서 바로 어디에 둘지 고른다
func _open_buy(id: String, from: String) -> void:
	var r := run()
	var nm := String(PCatalog.equipment_def(id).name)
	var price := PRun.equip_price_for(r, id, from)
	open_confirm("%s%s %d금에 살까요?" % [PGlossaryTip.esc(nm), PUi.josa(nm, "을", "를"), price], _buy_body.bind(r, id, price),
		[{ "text": "지금 장착", "cb": func(): main.buy_equipment(id, true, from) },
		 { "text": "가방에 넣기", "cb": func(): main.buy_equipment(id, false, from) }])

func _buy_body(box: VBoxContainer, r: Dictionary, id: String, price: int) -> void:
	var d: Dictionary = PCatalog.equipment_def(id)
	var slot := String(d.slot)
	PUi.kv(box, "값", "[color=#ffd966][b]%d금[/b][/color] [color=#9ea8b8](금화 %d → %d)[/color]" % [price, int(r.gold), int(r.gold) - price], 15)
	PUi.kv(box, "부위", "[b]%s[/b]" % PUi.slot_name(slot), 14)
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 14))
	PUi.kv(box, "지금 장착하면", _change_text(r, id), 13)
	var cur = r.equipment.get(slot, null)
	if cur != null:
		box.add_child(PUi.rich("[color=#9ea8b8]지금 낀 %s은(는) 가방으로 갑니다(그 장비의 강화도 함께 따라갑니다).[/color]" % PGlossaryTip.esc(PRun.equip_display_name(r, String(cur))), 13))
	var note := _compare_note(r, d)
	if note != "":
		box.add_child(PUi.rich(note, 13))
	box.add_child(PUi.rich("[color=#9ea8b8]취소하면 금화·가방·장착이 그대로입니다.[/color]", 12))

## 장착했을 때 실제로 바뀌는 값(격리 사본에 장착해 PBuild.derive 전후를 비교한다 — 규칙은 건드리지 않는다)
func _change_text(r: Dictionary, id: String) -> String:
	var before := PBuild.derive(r)
	var dup: Dictionary = r.duplicate(true)
	if not (dup.bag as Array).has(id):
		(dup.bag as Array).append(id) # 사본에만 넣는다: 아직 사지 않은 재고를 '가방에 없음' 오류 없이 미리 비교하기 위해서다
	PRun.equip_item(dup, id)
	var after := PBuild.derive(dup)
	var parts := []
	if not is_equal_approx(float(before.hp_max), float(after.hp_max)):
		parts.append("최대 체력 [b]%d → %d[/b]" % [int(float(before.hp_max)), int(float(after.hp_max))])
	if not is_equal_approx(float(before.speed_mult), float(after.speed_mult)):
		parts.append("이동 [b]×%s → ×%s[/b]" % [PUi.fmt(float(before.speed_mult)), PUi.fmt(float(after.speed_mult))])
	if not is_equal_approx(float(before.shield), float(after.shield)):
		parts.append("시작 보호막 [b]%d → %d[/b]" % [int(float(before.shield)), int(float(after.shield))])
	if not is_equal_approx(float(before.range_mult), float(after.range_mult)):
		parts.append("사거리 [b]×%s → ×%s[/b]" % [PUi.fmt(float(before.range_mult)), PUi.fmt(float(after.range_mult))])
	if parts.is_empty():
		return "[color=#9ea8b8]기본 수치 변화 없음(효과는 조건부)[/color]"
	return " · ".join(parts)

## 요구 조건 한 줄(§8): 특정 주무기·상태이상·수동 기술이 있어야 하는 장비는 **그 조건을 항상 적는다**(못 채웠을 때만이 아니라).
##
## 판정 기준은 **지금 Q/E 칸에 실제로 든 기술**(PGrowth.has_skill = 슬롯 조회)과 지금 든 자동기술이다.
## 보유만 하고 편성하지 않은 기술을 "있다"고 세지 않는다 — 그렇게 세면 지금 발동하지도 않는 장비를 추천하게 된다(§8).
func _needs_row(r: Dictionary, id: String, d: Dictionary) -> Control:
	var g: Dictionary = r.growth
	var eff: Dictionary = d.get("eff", {})
	var parts := []
	if String(d.get("needs", "")) == "dot":
		var okd := PGrowth.has_dot_source(g)
		parts.append("%s지속 피해 원천[/color]" % ("[color=#9fe89f]" if okd else "[color=#ff8c73]"))
	for k in ["fieldDirect", "fieldTaken", "fieldMark", "fieldRegen"]:
		if eff.has(k):
			var okf := PGrowth.has_skill(g, "slowfield")
			parts.append("%s감속장을 Q나 E에 편성[/color]" % ("[color=#9fe89f]" if okf else "[color=#ff8c73]"))
			break
	if eff.has("eShield"):
		var oke: bool = PGrowth.usable_skill(r, "e") != null
		parts.append("%sE 칸에 수동 기술[/color]" % ("[color=#9fe89f]" if oke else "[color=#ff8c73]"))
	if eff.has("relay"):
		var okr: bool = PGrowth.usable_skill(r, "e") != null and PGrowth.usable_skill(r, "q") != null
		parts.append("%sQ·E 두 칸 모두 사용[/color]" % ("[color=#9fe89f]" if okr else "[color=#ff8c73]"))
	if eff.has("eliteDirect"):
		parts.append("[color=#9ea8b8]정예가 나오는 전투[/color]")
	if parts.is_empty():
		return PUi.rich("[color=#6a7078]요구 조건 없음 · 끼면 바로 동작[/color]", 12)
	return PUi.rich("[color=#9ea8b8]요구 조건[/color] %s" % " · ".join(parts), 12)

## 같은 부위에 지금 낀 장비(§8 '현재 장비와 비교'). 비어 있으면 그렇게 적는다
func _current_row(r: Dictionary, slot: String) -> Control:
	var cur = r.equipment.get(slot, null)
	if cur == null:
		return PUi.rich("[color=#9ea8b8]지금 %s[/color] [color=#6a7078]비어 있음(교체 없이 그대로 낍니다)[/color]" % PUi.slot_name(slot), 12)
	return PUi.rich("[color=#9ea8b8]지금 %s[/color] %s [color=#6a7078]→ 사면 가방으로[/color]" % [PUi.slot_name(slot), PUi.equip_line(String(cur), r)], 12)

## 장비 비교 주의(HTML equipCompare): 지금 빌드에서 효과가 없는 조건
func _compare_note(r: Dictionary, d: Dictionary) -> String:
	var g: Dictionary = r.growth
	var eff: Dictionary = d.eff
	if String(d.get("needs", "")) == "dot":
		if not PGrowth.has_dot_source(g): # 희귀 보상 후보와 같은 판정(F5)
			return "[color=#ff8c73]지금 빌드에는 지속 피해 원천이 없어 효과가 없음[/color]"
	if eff.has("eliteDirect"):
		var any_elite := false
		for c in PSortie.cards_for(r):
			for e in c.enemies:
				if bool(PCatalog.enemy(String(e)).get("elite", false)):
					any_elite = true
		if not any_elite:
			return "[color=#9ea8b8]오늘 장소에는 정예가 없음[/color]"
	# 수동 기술 보유 조건(§8): 감속장·E 칸이 필요한 장비는 **왜 지금 안 되는지**를 말한다(조용히 빼지 않는다)
	var why := PGrowth.equip_eff_inactive_reason_run(r, eff) # 회차 전체로 본다: 장비를 벗어 못 쓰는 장비 기술이 든 칸은 빈 칸으로 센다
	if why != "":
		return "[color=#ff8c73]%s[/color]" % PGlossaryTip.esc(why)
	if eff.has("fieldDirect") or eff.has("fieldTaken") or eff.has("fieldMark") or eff.has("fieldRegen"):
		return "[color=#9ea8b8]감속장 안에서만 (%s 칸)[/color]" % PGrowth.skill_slot_of(g, "slowfield").to_upper()
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
	var term_id := ("w:" + String(sk.id)) if is_w else PUi.skill_term(String(sk.id)) # 감속장은 옛 용어 키("slowfield")를 쓴다
	var head2 := PUi.hbox(8)
	head2.add_child(PUi.icon_of(PIcons.weapon_key(String(sk.id)) if is_w else PIcons.e_key(String(sk.id)), 40.0, "", "", 0.0, 0))
	head2.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s · Lv1 · 개조 없음[/color]
금화 [color=%s][b]%d[/b][/color]" % [PGlossaryTip.term(term_id, String(d.name)), "새 자동기술" if is_w else "새 E 기술", "#ff8c73" if int(r.gold) < int(sk.price) else "#ffd966", int(sk.price)], 15))
	box.add_child(head2)
	box.add_child(PUi.rich("[color=#9ea8b8]지금 내 빌드[/color]", 13))
	box.add_child(PUi.build_icon_row(r, 34.0, 22.0))
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 15))
	var why := ""
	if sold:
		why = "구매함"
	elif is_w and (g.weapons as Array).size() >= int(S.weapons):
		why = "자동기술 슬롯 가득"
	elif not is_w and g.skills.get("e", null) != null:
		why = "E 슬롯 사용 중"
	elif int(r.gold) < int(sk.price):
		why = "%d 부족" % (int(sk.price) - int(r.gold))
	box.add_child(PUi.rich("금화 [color=%s][b]%d[/b][/color]%s" % ["#ff8c73" if int(r.gold) < int(sk.price) else "#ffd966", int(sk.price), (" [color=#9ea8b8]· %s[/color]" % why) if why != "" else ""], 15))
	box.add_child(PUi.spacer())
	box.add_child(PUi.button("구매 (빈 슬롯에 장착)", func(): main.buy_skill(), can, 14))
	return p
