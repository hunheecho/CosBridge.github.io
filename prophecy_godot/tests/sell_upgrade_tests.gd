extends SceneTree
## 판매가(지불액의 절반 + 강화 비용의 50%)와 **효과 있는 강화**만 팔리게 하는 규칙의 실측 검사.
## 실행: python tools/run_suites.py --suites sell_upgrade_tests --jobs 1
##
## 사용자 확정(2026-09-10)에서 이 파일이 고정하는 것:
##  ① 판매가 = floor(실제 지불액 × shop.sellRate) + floor(누적 강화 비용 × shop.equipUpgrade.sellRefundRate).
##     두 값을 **따로 세어 더한다**. 비율·비용은 전부 자료가 정본이고 여기서도 자료에서 읽는다.
##  ② 견적 · 확인 창에 적힌 금액 · 실제 입금액이 **셋 다 같다**(확인 창은 진짜 화면으로 확인한다).
##  ③ 제작으로 계승된 강화도 같은 규칙으로 환급되고, **재료와 완성품 양쪽에서 두 번 나오지 않는다**.
##  ④ 강화 → 제작과 제작 → 강화의 최종 단계·성능·총 강화 지출·**판매가**가 같다.
##  ⑤ 같은 종류를 여럿 가져도 **판매한 개체만** 사라진다.
##  ⑥ 강화로 실제 값이 달라지지 않는 장비는 **견적과 확정 양쪽에서** 강화가 막힌다(폐기 2종 포함).
##     다만 이미 가진 개체는 그대로 쓰이고 팔 수 있다.
##  ⑦ 신규 3종(공성 망치머리·겹번개 도선·서리 결정 흉갑)의 강화가 기본 능력치만 올린다 —
##     추가 충격 횟수·피해 비율·감전 복제 횟수·빙결 요구량은 그대로다.
##
## 여기 수치는 자료에서 읽은 값이거나 **첫 시험값**이다. 이 검사가 새로 정한 밸런스는 없다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func mk_run(seed_n: int) -> Dictionary:
	var r := PRun.new_run(seed_n, "sword")
	r.gold = 5000
	r.bossesDone = ["b1", "b2"] # 관문 2돌파 = +1·+2가 모두 열린 상태
	for mk in (PCatalog.materials() as Dictionary):
		(r.mats as Dictionary)[String(mk)] = 20
	return r

## 오늘 재고에 그 종류를 끼워 넣는다(운에 맡기지 않고 **실제 구매 통로**로 사기 위해서다)
func stock_in(run: Dictionary, type_id: String) -> void:
	var st := PRun.stock(run)
	if not (st.equipment as Array).has(type_id):
		(st.equipment as Array).append(type_id)

## 실제 구매 통로로 사고 그 개체 id를 돌려준다("" = 실패)
func buy(run: Dictionary, type_id: String) -> String:
	stock_in(run, type_id)
	if not PRun.buy_equipment(run, type_id, false):
		return ""
	var last := ""
	for u in run.bag:
		if PRun.equip_type_of(String(u)) == type_id:
			last = String(u)
	return last

## 열린 단계까지 실제 강화 통로로 올린다. 돌려주는 값 = 실제로 낸 금화 합계
func upgrade_to(run: Dictionary, uid: String, want: int) -> int:
	var spent := 0
	while PRun.equip_plus_of(run, uid) < want:
		var q := PRun.equip_upgrade_next(run, uid)
		if q.is_empty() or not bool(q.can):
			break
		spent += int(q.cost)
		PRun.upgrade_equip(run, uid, int(q.cost))
	return spent

func uid_of_type(run: Dictionary, type_id: String) -> String:
	for u in run.bag:
		if PRun.equip_type_of(String(u)) == type_id:
			return String(u)
	for slot in run.equipment:
		if run.equipment[slot] != null and PRun.equip_type_of(String(run.equipment[slot])) == type_id:
			return String(run.equipment[slot])
	return ""

# ---------- 화면 도우미(확인 창 값을 진짜 화면에서 읽는다) ----------
func _texts(node: Node, out: Array) -> void:
	if node is RichTextLabel:
		out.append(String((node as RichTextLabel).text))
	elif node is Label:
		out.append(String((node as Label).text))
	elif node is Button:
		out.append(String((node as Button).text))
	for c in node.get_children():
		_texts(c, out)

func _has_text(node: Node, needle: String) -> bool:
	var t := []
	_texts(node, t)
	for s in t:
		if String(s).find(needle) >= 0:
			return true
	return false

func _button(node: Node, needle: String, only_enabled: bool = true) -> Button:
	if node is Button:
		var b := node as Button
		if b.text.find(needle) >= 0 and b.is_visible_in_tree() and (not only_enabled or not b.disabled):
			return b
	for c in node.get_children():
		var r := _button(c, needle, only_enabled)
		if r != null:
			return r
	return null

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var SH := PCatalog.shop()
	var rate := PRun.sell_rate()
	var refund_rate := PRun.sell_refund_rate()
	var up1 := PRun.equip_upgrade_total_cost(1)
	var up2 := PRun.equip_upgrade_total_cost(2)

	print("\n[0] 비율·비용의 정본은 자료다")
	ok("판매 비율이 자료(shop.sellRate)에서 나온다", is_equal_approx(rate, float(SH.sellRate)) and rate >= 0.0, "sellRate=%s" % str(rate))
	ok("강화 환급 비율이 자료(shop.equipUpgrade.sellRefundRate)에서 나온다",
		is_equal_approx(refund_rate, float((SH.equipUpgrade as Dictionary).sellRefundRate)) and refund_rate >= 0.0, "sellRefundRate=%s" % str(refund_rate))
	ok("누적 강화 비용도 자료 표에서 나온다(+1 %d금 · +2 %d금)" % [up1, up2],
		up1 == int((SH.equipUpgrade.steps as Array)[0].cost) and up2 == int((SH.equipUpgrade.steps as Array)[0].cost) + int((SH.equipUpgrade.steps as Array)[1].cost))
	ok("강화 환급액: +0 %d금 · +1 %d금 · +2 %d금" % [0, int(floor(float(up1) * refund_rate)), int(floor(float(up2) * refund_rate))],
		int(floor(float(up1) * refund_rate)) == 35 and int(floor(float(up2) * refund_rate)) == 100,
		"확정 문구의 시험값(35 / 100)과 같다")

	# ---------- [1] 판매가 표: 무기·갑옷·방패 × +0/+1/+2 ----------
	# 견적(sell_quote.gold) · 확정에 넘기는 금액 · **실제 입금액**이 셋 다 같은지 값으로 본다.
	print("\n[1] 판매가 표 — 정가 구매 뒤 +0/+1/+2")
	var table := []
	for type_id in ["hunter_sword", "vitality_coat", "iron_shield"]:
		for want in [0, 1, 2]:
			var r := mk_run(200 + want)
			var uid := buy(r, String(type_id))
			if uid == "":
				ok("구매 실패 %s" % type_id, false)
				continue
			var paid := PRun.paid_for(r, uid)
			var spent := upgrade_to(r, uid, want)
			var q := PRun.sell_quote(r, uid)
			var gold_before := int(r.gold)
			var sold := PRun.sell_equipment(r, uid, int(q.gold)) # 확정에 **견적 금액을 그대로** 넘긴다
			var got := int(r.gold) - gold_before
			var want_base := int(floor(float(paid) * rate))
			var want_refund := int(floor(float(PRun.equip_upgrade_total_cost(want)) * refund_rate))
			table.append({ "type": String(type_id), "plus": want, "paid": paid, "upSpent": spent,
				"quote": int(q.gold), "base": int(q.base), "refund": int(q.refund), "got": got })
			ok("%s +%d: 견적 %d금 = 기본 %d + 강화 환급 %d, 실제 입금 %d금(셋이 같다)" % [
					String(PCatalog.equipment_def(String(type_id)).name), want, int(q.gold), int(q.base), int(q.refund), got],
				sold and int(q.gold) == got and int(q.base) == want_base and int(q.refund) == want_refund
					and int(q.gold) == int(q.base) + int(q.refund) and spent == PRun.equip_upgrade_total_cost(want),
				"지불 %d · 강화 지출 %d" % [paid, spent])
	print("[판매가표] ", JSON.stringify(table))

	# ---------- [2] 정가 / 할인 / 제작 완성품 ----------
	print("\n[2] 정가 구매 · 할인 구매 · 제작 완성품의 판매가가 어떻게 갈리는가")
	var rp := mk_run(300)
	var u_list := buy(rp, "hunter_sword")
	var q_list := PRun.sell_quote(rp, u_list)
	ok("정가 구매(140금): 기본가 = 낸 값의 %d%% = %d금, 근거는 'paid'" % [int(round(rate * 100.0)), int(q_list.base)],
		PRun.paid_for(rp, u_list) == PRun.equip_price("hunter_sword") and int(q_list.base) == int(floor(float(PRun.equip_price("hunter_sword")) * rate))
			and String(q_list.basis) == "paid" and int(q_list.refund) == 0,
		"지불 %d → 판매 %d" % [PRun.paid_for(rp, u_list), int(q_list.gold)])
	var rd := mk_run(301)
	rd.services["shop_discount"] = 1 # 할인권 1장(30%)
	var d_price := PRun.equip_price_for(rd, "hunter_sword", "stock")
	var u_disc := buy(rd, "hunter_sword")
	var q_disc := PRun.sell_quote(rd, u_disc)
	ok("할인 구매(%d금): 기본가는 **정상가가 아니라 실제로 낸 값**의 절반 = %d금(싸게 사서 비싸게 파는 길이 없다)" % [d_price, int(q_disc.base)],
		PRun.paid_for(rd, u_disc) == d_price and d_price < PRun.equip_price("hunter_sword")
			and int(q_disc.base) == int(floor(float(d_price) * rate)) and int(q_disc.gold) < int(q_list.gold),
		"정가판매 %d금 vs 할인판매 %d금" % [int(q_list.gold), int(q_disc.gold)])
	var d_spent := upgrade_to(rd, u_disc, 2)
	var q_disc2 := PRun.sell_quote(rd, u_disc)
	ok("할인 구매 + 강화 +2: 기본가는 할인가 기준이지만 **강화 환급은 낸 강화 비용 그대로**(%d금 중 %d금)" % [d_spent, int(q_disc2.refund)],
		int(q_disc2.base) == int(q_disc.base) and int(q_disc2.refund) == int(floor(float(up2) * refund_rate)) and d_spent == up2,
		"%d = %d + %d" % [int(q_disc2.gold), int(q_disc2.base), int(q_disc2.refund)])
	var rm := mk_run(302)
	var u_mat := buy(rm, "guardian_armor")
	PRun.craft(rm, "moon_armor", false, false)
	var u_made := uid_of_type(rm, "moon_armor")
	var q_made := PRun.sell_quote(rm, u_made)
	ok("제작 완성품: 산 적이 없어 기본가는 **정상 구매가**의 절반 = %d금, 근거는 'list'" % int(q_made.base),
		PRun.paid_for(rm, u_made) < 0 and String(q_made.basis) == "list"
			and int(q_made.base) == int(floor(float(PRun.equip_price("moon_armor")) * rate)) and int(q_made.refund) == 0,
		"완성품 판매 %d금(정상가 %d)" % [int(q_made.gold), PRun.equip_price("moon_armor")])
	ok("제작에 쓴 재료의 지불 기록은 완성품으로 옮겨가지 않는다(재료값을 다시 돌려받지 않는다)",
		not PRun.paid_map(rm).has(u_mat) and not PRun.has_equip_uid(rm, u_mat), "재료 %s" % u_mat)

	# ---------- [3] 중복 환급이 없다 ----------
	print("\n[3] 재료를 태우면 그 강화 지출이 어디로 가는가(중복 환급 없음)")
	var rr := mk_run(310)
	var u_src := buy(rr, "guardian_armor")
	var src_spent := upgrade_to(rr, u_src, 2)
	var q_src := PRun.sell_quote(rr, u_src)
	ok("태우기 전: 재료 개체가 +2이고 그 판매 환급은 %d금이다" % int(q_src.refund),
		PRun.equip_plus_of(rr, u_src) == 2 and int(q_src.refund) == int(floor(float(up2) * refund_rate)) and src_spent == up2)
	var gold_pre := int(rr.gold)
	PRun.craft(rr, "moon_armor", false, false)
	var u_out := uid_of_type(rr, "moon_armor")
	var q_out := PRun.sell_quote(rr, u_out)
	ok("태운 뒤: 재료 개체와 그 강화 기록이 **함께 사라진다**(equipPlus에 남지 않는다)",
		not PRun.has_equip_uid(rr, u_src) and not (rr.get("equipPlus", {}) as Dictionary).has(u_src)
			and PRun.equip_plus_of(rr, u_src) == 0, "재료 %s" % u_src)
	ok("완성품이 +2를 계승하고 **환급은 완성품 한 곳에만** 붙는다(%d금)" % int(q_out.refund),
		PRun.equip_plus_of(rr, u_out) == 2 and int(q_out.refund) == int(floor(float(up2) * refund_rate))
			and int(q_out.upgradeSpent) == up2, "완성품 %s" % u_out)
	ok("제작이 강화 비용을 다시 청구하지도, 환급하지도 않는다(수수료 %d금만 빠졌다)" % int(PCatalog.recipe("moon_armor").fee),
		gold_pre - int(rr.gold) == int(PCatalog.recipe("moon_armor").fee), "빠진 금화 %d" % (gold_pre - int(rr.gold)))
	var refund_total := int(q_out.refund)
	ok("한 번 낸 강화 %d금에 대한 환급 총액은 %d금 하나뿐이다(재료 %d + 완성품 %d 가 아니다)" % [up2, refund_total, 0, refund_total],
		refund_total == int(floor(float(up2) * refund_rate)) and PRun.sell_upgrade_refund(rr, u_src) == 0,
		"태운 개체 환급 %d금" % PRun.sell_upgrade_refund(rr, u_src))

	# ---------- [4] 강화 → 제작 vs 제작 → 강화(판매가까지) ----------
	print("\n[4] 강화 → 제작 vs 제작 → 강화: 단계·성능·총 강화 지출·판매가")
	for want2 in [1, 2]:
		var ra := mk_run(320 + want2)
		var ua := buy(ra, "guardian_armor")
		var spent_a := upgrade_to(ra, ua, want2)
		PRun.craft(ra, "moon_armor", false, false)
		var oa := uid_of_type(ra, "moon_armor")
		var rb := mk_run(340 + want2)
		var _ub := buy(rb, "guardian_armor") # 재료 개체는 아래 제작에서 태워진다
		PRun.craft(rb, "moon_armor", false, false)
		var ob := uid_of_type(rb, "moon_armor")
		var spent_b := upgrade_to(rb, ob, want2)
		var eff_a := PCatalog.equipment_eff("moon_armor", PRun.equip_plus_of(ra, oa))
		var eff_b := PCatalog.equipment_eff("moon_armor", PRun.equip_plus_of(rb, ob))
		var qa := PRun.sell_quote(ra, oa)
		var qb := PRun.sell_quote(rb, ob)
		ok("+%d: 최종 단계 %d = %d · 성능(시작 보호막) %d = %d · 총 강화 지출 %d = %d · 판매가 %d = %d" % [
				want2, PRun.equip_plus_of(ra, oa), PRun.equip_plus_of(rb, ob), int(eff_a.startShield), int(eff_b.startShield),
				spent_a, spent_b, int(qa.gold), int(qb.gold)],
			PRun.equip_plus_of(ra, oa) == want2 and PRun.equip_plus_of(rb, ob) == want2
				and int(eff_a.startShield) == int(eff_b.startShield) and spent_a == spent_b and spent_a == PRun.equip_upgrade_total_cost(want2)
				and int(qa.gold) == int(qb.gold) and int(qa.base) == int(qb.base) and int(qa.refund) == int(qb.refund)
				and int(ra.gold) == int(rb.gold),
			"잔액 %d = %d" % [int(ra.gold), int(rb.gold)])

	# ---------- [5] 같은 종류 2개 중 하나만 판매 ----------
	print("\n[5] 같은 종류 2개 중 판매한 개체만 사라진다")
	var rs := mk_run(350)
	var s_a := PRun.equip_new_uid(rs, "vitality_coat")
	var s_b := PRun.equip_new_uid(rs, "vitality_coat")
	(rs.bag as Array).append(s_a)
	(rs.bag as Array).append(s_b)
	PRun.note_paid(rs, s_a, PRun.equip_price("vitality_coat"), "stock")
	PRun.note_paid(rs, s_b, PRun.equip_price("vitality_coat"), "stock")
	var spent_a2 := upgrade_to(rs, s_a, 2)
	var q_a2 := PRun.sell_quote(rs, s_a)
	var q_b0 := PRun.sell_quote(rs, s_b)
	var gold_s := int(rs.gold)
	var sold_a := PRun.sell_equipment(rs, s_a, int(q_a2.gold))
	ok("개체 %s(+2)만 팔린다: %s(+0)는 그대로 남고 강화 기록도 각각이다" % [s_a, s_b],
		sold_a and not PRun.has_equip_uid(rs, s_a) and PRun.has_equip_uid(rs, s_b)
			and PRun.equip_plus_of(rs, s_b) == 0 and not (rs.get("equipPlus", {}) as Dictionary).has(s_a),
		"판 개체 %s · 남은 개체 %s" % [s_a, s_b])
	ok("판 개체의 판매가 %d금(기본 %d + 환급 %d)만 들어오고, 남은 개체 판매가 %d금은 건드리지 않는다" % [
			int(q_a2.gold), int(q_a2.base), int(q_a2.refund), int(q_b0.gold)],
		int(rs.gold) - gold_s == int(q_a2.gold) and int(PRun.sell_quote(rs, s_b).gold) == int(q_b0.gold)
			and int(q_a2.gold) - int(q_b0.gold) == int(floor(float(spent_a2) * refund_rate)),
		"차이 %d금 = 강화 %d금의 %d%%" % [int(q_a2.gold) - int(q_b0.gold), spent_a2, int(round(refund_rate * 100.0))])

	# ---------- [6] 신규 3종: 강화 전후 기본 능력치 ----------
	print("\n[6] 신규 3종 강화 전후 기본 능력치(첫 시험값)")
	var new3 := {
		"siege_hammerhead": { "path": "eliteDirect", "want": [0.1, 0.13, 0.16] },
		"stormwire": { "path": "reach", "want": [0.08, 0.1, 0.12] },
		"frostcrest_armor": { "path": "hpMax", "want": [15.0, 20.0, 25.0] },
	}
	for tid in new3:
		var spec: Dictionary = new3[tid]
		var path := String(spec.path)
		var got := []
		var all_ok := true
		for p in [0, 1, 2]:
			var v := float(PCatalog.equipment_eff(String(tid), p).get(path, 0.0))
			got.append(v)
			if not is_equal_approx(v, float((spec.want as Array)[p])):
				all_ok = false
		ok("%s: %s %s → %s → %s (강화가 실제로 값을 바꾼다)" % [String(PCatalog.equipment_def(String(tid)).name), path,
				str(got[0]), str(got[1]), str(got[2])],
			all_ok and not is_equal_approx(float(got[0]), float(got[1]))
				and not is_equal_approx(float(got[1]), float(got[2])), str(got))
	var hf0: Dictionary = PCatalog.equipment_eff("siege_hammerhead", 0).hammerFocus
	var hf2: Dictionary = PCatalog.equipment_eff("siege_hammerhead", 2).hammerFocus
	ok("공성 망치머리: 추가 충격의 피해 비율·지연·반경은 강화로 바뀌지 않는다(mult %s · delay %s · radiusMult %s 그대로)" % [
			str(hf2.mult), str(hf2.delay), str(hf2.radiusMult)],
		is_equal_approx(float(hf0.mult), float(hf2.mult)) and is_equal_approx(float(hf0.delay), float(hf2.delay))
			and is_equal_approx(float(hf0.radiusMult), float(hf2.radiusMult)))
	var se0: Dictionary = PCatalog.equipment_eff("stormwire", 0).shockEcho
	var se2: Dictionary = PCatalog.equipment_eff("stormwire", 2).shockEcho
	ok("겹번개 도선: 감전 복제 횟수는 강화로 바뀌지 않는다(copies %d 그대로)" % int(se2.copies), int(se0.copies) == int(se2.copies))
	var fr0: Dictionary = PCatalog.equipment_eff("frostcrest_armor", 0).frostReq
	var fr2: Dictionary = PCatalog.equipment_eff("frostcrest_armor", 2).frostReq
	ok("서리 결정 흉갑: 빙결 요구 중첩은 강화로 바뀌지 않는다(reduce %d · min %d 그대로)" % [int(fr2.reduce), int(fr2.min)],
		int(fr0.reduce) == int(fr2.reduce) and int(fr0.min) == int(fr2.min))
	# 실제 회차에서 사서 올려 본다(자료만이 아니라 규칙 통로로도 값이 달라지는지)
	var rn := mk_run(360)
	var u_frost := buy(rn, "frostcrest_armor")
	ok("서리 결정 흉갑을 실제로 살 수 있다(막 조건 무시하지 않고 재고 주입)", u_frost != "", u_frost)
	if u_frost != "":
		PRun.equip_item(rn, u_frost)
		var hp0 := float(PBuild.derive(rn).hp_max)
		upgrade_to(rn, u_frost, 1)
		var hp1 := float(PBuild.derive(rn).hp_max)
		upgrade_to(rn, u_frost, 2)
		var hp2 := float(PBuild.derive(rn).hp_max)
		ok("착용 최대 체력 실측: +0 %.0f → +1 %.0f → +2 %.0f (+5씩)" % [hp0, hp1, hp2],
			is_equal_approx(hp1 - hp0, 5.0) and is_equal_approx(hp2 - hp1, 5.0), "%.0f / %.0f / %.0f" % [hp0, hp1, hp2])

	# ---------- [7] 강화표 전수 조사 ----------
	print("\n[7] 강화표 전수 조사 — 표가 없거나 값이 안 변하는 장비")
	var no_table := []
	var dead_table := []
	var live_table := []
	var all_ids: Array = []
	for k in PCatalog.equipment():
		all_ids.append(String(k))
	for k2 in PCatalog.crafted_equipment():
		all_ids.append(String(k2))
	for id in all_ids:
		var tid2 := String(id)
		var d := PCatalog.equipment_def(tid2)
		var up: Dictionary = d.get("upgrade", {})
		var ch1 := PRun.equip_upgrade_diff(tid2, 0, 1)
		var ch2 := PRun.equip_upgrade_diff(tid2, 1, 2)
		if up.is_empty():
			no_table.append(tid2)
		elif ch1.is_empty() or ch2.is_empty():
			dead_table.append({ "id": tid2, "step1": ch1, "step2": ch2 })
		else:
			live_table.append(tid2)
	print("[전수조사] 강화 가능 %d종 %s" % [live_table.size(), JSON.stringify(live_table)])
	print("[전수조사] 강화표 없음 %d종 %s" % [no_table.size(), JSON.stringify(no_table)])
	print("[전수조사] 표는 있으나 값이 안 변함 %d종 %s" % [dead_table.size(), JSON.stringify(dead_table)])
	ok("표만 있고 값이 안 변하는 장비가 하나도 없다", dead_table.is_empty(), JSON.stringify(dead_table))
	ok("강화표가 없는 장비는 **폐기 2종뿐**이다(반격 방패·연계 방패)",
		no_table.size() == 2 and no_table.has("reprisal_shield") and no_table.has("relay_shield"), JSON.stringify(no_table))
	ok("나머지 %d종은 전부 +0→+1·+1→+2 모두 실제로 값이 달라진다" % live_table.size(), live_table.size() == all_ids.size() - 2)

	# ---------- [8] 효과 없는 강화는 견적·확정 양쪽에서 막힌다 ----------
	print("\n[8] 폐기 2종의 강화 차단 + 기존 보유분은 그대로")
	var rx := mk_run(370)
	for tid3 in ["reprisal_shield", "relay_shield"]:
		var ux := PRun.equip_new_uid(rx, String(tid3)) # 옛 저장에서 들어온 개체를 흉내 낸다(새로 살 수는 없다)
		(rx.bag as Array).append(ux)
		var gold_x := int(rx.gold)
		var qx := PRun.equip_upgrade_next(rx, ux)
		ok("%s: 견적이 **사유를 돌려준다**(빈 사전이 아니다)" % String(PCatalog.equipment_def(String(tid3)).name),
			not qx.is_empty() and not bool(qx.can) and String(qx.reason).find("강화할 수 없습니다") >= 0, String(qx.get("reason", "")))
		ok("%s: can_upgrade_equip 거짓 · upgrade_equip 거부 · 금화와 단계가 그대로" % String(tid3),
			not PRun.can_upgrade_equip(rx, ux) and not PRun.upgrade_equip(rx, ux)
				and int(rx.gold) == gold_x and PRun.equip_plus_of(rx, ux) == 0, "금화 %d" % int(rx.gold))
		var qsx := PRun.sell_quote(rx, ux)
		ok("%s: 이미 가진 개체는 그대로 쓰이고 **팔 수 있다**(%d금)" % [String(tid3), int(qsx.gold)],
			bool(qsx.can) and int(qsx.gold) == int(floor(float(PRun.equip_price(String(tid3))) * rate)), String(qsx.get("reason", "")))
	var worn_ok := PRun.equip_item(rx, uid_of_type(rx, "reprisal_shield"))
	var bx := PBuild.derive(rx)
	ok("폐기 2종을 낀 채로도 효과가 그대로 계산된다(삭제·효과 제거로 넓히지 않았다)",
		worn_ok and (bx.equip as Dictionary).has("reprisal") and (bx.equip as Dictionary).has("bigHit"),
		str((bx.equip as Dictionary).keys()))

	# ---------- [9] 자료가 비면 금화·단계가 먼저 바뀌지 않는다(원자성) ----------
	print("\n[9] 자료가 잘못됐을 때의 원자성")
	var ry := mk_run(380)
	var uy := buy(ry, "vitality_coat")
	var gold_y := int(ry.gold)
	var plus_y := PRun.equip_plus_of(ry, uy)
	var saved_steps = (PCatalog.shop().equipUpgrade as Dictionary).get("steps")
	(PCatalog.shop().equipUpgrade as Dictionary)["steps"] = [{ "plus": 1 }] # cost·afterBoss가 빠진 망가진 칸
	var qy := PRun.equip_upgrade_next(ry, uy)
	ok("망가진 강화 자료: 견적이 사유를 돌려주고 확정이 거부되며 금화·단계가 그대로다",
		not qy.is_empty() and not bool(qy.can) and String(qy.reason).find("자료") >= 0
			and not PRun.upgrade_equip(ry, uy) and int(ry.gold) == gold_y and PRun.equip_plus_of(ry, uy) == plus_y,
		String(qy.get("reason", "")))
	(PCatalog.shop().equipUpgrade as Dictionary)["steps"] = saved_steps
	var saved_rate = (PCatalog.shop() as Dictionary).get("sellRate")
	(PCatalog.shop() as Dictionary).erase("sellRate")
	var qz := PRun.sell_quote(ry, uy)
	ok("판매 비율 자료가 없으면 팔 수 없다고 답하고 금화가 늘지 않는다",
		not bool(qz.can) and int(qz.gold) == 0 and not PRun.sell_equipment(ry, uy) and int(ry.gold) == gold_y,
		String(qz.get("reason", "")))
	(PCatalog.shop() as Dictionary)["sellRate"] = saved_rate
	ok("자료를 되돌리면 다시 정상으로 판다", bool(PRun.sell_quote(ry, uy).can) and PRun.sell_rate() >= 0.0)

	# ---------- [10] 실제 화면: 확인 창에 적힌 금액 = 견적 = 입금액 ----------
	await _ui_section()
	_finish()

func _ui_section() -> void:
	print("\n[10] 진짜 화면의 판매 확인 창")
	PProfile.use_path("user://prophecy_profile_sell_upgrade_v1.json")
	PProfile.clear()
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.profile = PProfile.load("legacy")
	main.use_bot = false
	main.start_run("sword")
	await process_frame
	var r: Dictionary = main.run
	r.gold = 4000
	r.bossesDone = ["b1", "b2"]
	PRun.refresh_stock(r)
	var uid := buy(r, "vitality_coat")
	var spent := upgrade_to(r, uid, 2)
	PRun.equip_item(r, uid)
	var q := PRun.sell_quote(r, uid)
	main.show("shop")
	await process_frame
	var shop: Node = main.screens["shop"]
	var sell_btn := _button(shop, "판매 +%d" % int(q.gold))
	ok("상점 판매 줄의 금액이 견적과 같다(판매 +%d)" % int(q.gold), sell_btn != null, "견적 %d금" % int(q.gold))
	if sell_btn == null:
		main.queue_free()
		return
	var gold_before := int(r.gold)
	sell_btn.pressed.emit()
	await process_frame
	shop = main.screens["shop"]
	ok("확인 창이 열리고 아직 금화가 빠지거나 들어오지 않는다", _has_text(shop, "판매할까요?") and int(r.gold) == gold_before)
	ok("확인 창이 받을 금액 %d금을 적는다" % int(q.gold), _has_text(shop, "+%d금" % int(q.gold)), "견적 %d" % int(q.gold))
	ok("확인 창이 기본가 %d금과 강화 환급 %d금을 갈라 적는다" % [int(q.base), int(q.refund)],
		_has_text(shop, "%d금" % int(q.base)) and _has_text(shop, "%d금" % int(q.refund)) and _has_text(shop, "강화 환급"),
		"기본 %d · 환급 %d(강화 지출 %d)" % [int(q.base), int(q.refund), spent])
	var cancel := _button(shop, "취소")
	if cancel != null:
		cancel.pressed.emit()
		await process_frame
	ok("취소하면 금화·장비가 그대로다", int(r.gold) == gold_before and PRun.has_equip_uid(r, uid) and PRun.equip_plus_of(r, uid) == 2)
	shop = main.screens["shop"]
	_button(shop, "판매 +%d" % int(q.gold)).pressed.emit()
	await process_frame
	shop = main.screens["shop"]
	_button(shop, "판매한다").pressed.emit()
	await process_frame
	ok("'판매한다'를 누르면 **확인 창에 적힌 금액 그대로** 들어온다(+%d금)" % int(q.gold),
		int(r.gold) - gold_before == int(q.gold) and not PRun.has_equip_uid(r, uid),
		"금화 %d → %d" % [gold_before, int(r.gold)])
	main.queue_free()
	await process_frame

func _finish() -> void:
	var pass_n := 0
	for x in results:
		if x[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
