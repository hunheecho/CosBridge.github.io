class_name PMetaScreen
extends PScreen
## 영구 성장(회차 밖, 시험값 meta.json): 프로필 종류 전환(legacy/trial, 확인 뒤·다른 프로필 삭제 없음) · 영구 레벨/탐험 기록/다음 해금 한 줄 ·
## 특성 4행(행마다 3택 1개, 무료 재선택 — 다음 새 회차부터 반영) · 도감(획득 n/전체 · 시작 가능 n/전체를 분모 다르게) · 잠긴 항목 클릭 → 이름·짧은 효과·조건.
## 모든 값은 PProfile이 준다(화면은 계산하지 않는다).

var _confirm_kind := ""      # 전환 확인 대기 중인 종류
var _detail := ""            # "cat:id" 상세 보기

func on_escape() -> bool:
	if _confirm_kind != "" or _detail != "":
		_confirm_kind = ""
		_detail = ""
		refresh()
		return true
	return false

func on_enter() -> void:
	_confirm_kind = ""
	_detail = ""
	super.on_enter()

func refresh() -> void:
	clear_all()
	var p: Dictionary = main.profile
	if p.is_empty():
		return
	var P := PCatalog.meta_profiles()
	var kind := String(p.kind)
	heading("%s [color=#9ea8b8](시험값 · 사용자 승인 아님)[/color]" % PGlossaryTip.term("meta", "영구 성장"))
	# ---------- 프로필 종류 ----------
	var kc := PUi.card("프로필 [color=#9ea8b8]현재: %s[/color]" % PGlossaryTip.esc(String(P[kind].name)))
	var kbox: VBoxContainer = kc.box
	kbox.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(P[kind].desc)), 12))
	if _confirm_kind != "":
		var cc := PUi.card("프로필을 '%s'(으)로 전환할까요?" % PGlossaryTip.esc(String(P[_confirm_kind].name)), PUi.CARD_BOSS, 14)
		(cc.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(P[_confirm_kind].desc)), 12))
		(cc.box as VBoxContainer).add_child(PUi.rich("지금 프로필은 삭제되지 않고 같은 파일에 남습니다(언제든 되돌릴 수 있음). 진행 중인 회차는 시작 시점의 해금·특성으로 그대로 이어집니다. 새 프로필의 해금·특성은 다음 새 회차부터 적용됩니다.", 12))
		var crow := PUi.hbox(8)
		var k2 := _confirm_kind
		crow.add_child(PUi.button("전환", func(): _confirm_kind = ""; main.set_profile_kind(k2), true, 13))
		crow.add_child(PUi.button("취소", func(): _confirm_kind = ""; refresh(), true, 13))
		(cc.box as VBoxContainer).add_child(crow)
		kbox.add_child(cc.panel)
	else:
		var krow := PUi.hbox(8)
		for k in PProfile.KINDS:
			var kk := String(k)
			krow.add_child(PUi.button(String(P[kk].name) + (" (현재)" if kk == kind else ""), func(): _confirm_kind = kk; refresh(), kk != kind, 13))
		kbox.add_child(krow)
	body.add_child(kc.panel)
	# ---------- 레벨·기록 ----------
	var nl := PProfile.next_level(p)
	var lc := PUi.card("영구 Lv %d [color=#9ea8b8]· %s %d%s[/color]" % [int(nl.level), PGlossaryTip.esc(String(PCatalog.meta_records().name)), int(nl.have), (" · 다음 Lv까지 %d (%d/%d)" % [int(nl.remain), int(nl.have), int(nl.need)]) if int(nl.next) > int(nl.level) else " · 최대"])
	var lbox: VBoxContainer = lc.box
	lbox.add_child(PUi.rich("다음 해금: [b]%s[/b]" % PGlossaryTip.esc(PProfile.next_unlock_line(p)), 13))
	lbox.add_child(PUi.rich("[color=#9ea8b8]기록: 1~6일차 첫 정상 전투 승리 +1 · 관문 보스 최초 승리 +2 · 완주 +2(회차당 최대 14). 심층·임무·같은 날 반복·봇·시험실·즉시 관문은 기록되지 않습니다. 해금은 다음 새 회차의 후보부터.[/color]", 11))
	body.add_child(lc.panel)
	# ---------- 정복자(영구 Lv15 이후, 계획서 §10, 시험값) ----------
	var ci := PProfile.conqueror_info(p)
	var CS: Dictionary = PCatalog.meta_conqueror().get("stats", {})
	var cc2 := PUi.card("%s Lv %d/%d [color=#9ea8b8]· 포인트 %d (남은 %d)%s[/color]" % [PGlossaryTip.term("conqueror", "정복자"), int(ci.level), int(ci.max_level), int(ci.points), int(ci.free), ("" if int(ci.level) >= int(ci.max_level) else " · 다음 Lv까지 기록 %s" % PProfile._fmt_rec(float(ci.next_need)))], PUi.CARD, 14)
	var cbox: VBoxContainer = cc2.box
	cbox.add_child(PUi.rich("[color=#9ea8b8]영구 Lv%d(기록 %d) 이후의 별도 레벨. 기록 초과분 %d마다 1레벨(시험값). 출발 전 무료 재분배, 출발 후 무한까지 고정. 영구 만렙과 정복자 만렙은 다른 표시.[/color]" % [PProfile.max_level(), PProfile.records_to_max(), int(PCatalog.meta_conqueror().get("xp_per_level", 16))], 11))
	for key in ["attack", "hp", "move"]:
		var k2 := String(key)
		if not CS.has(k2):
			continue
		var sd: Dictionary = CS[k2]
		var cur := int((ci.alloc as Dictionary).get(k2, 0))
		var crow := PUi.hbox(6)
		crow.add_child(PUi.rich_nowrap("[b]%s[/b] %d/%d [color=#9ea8b8](+%.1f%%)[/color]" % [PGlossaryTip.esc(String(sd.name)), cur, int(sd.max_points), float(sd.per_point) * float(cur) * 100.0], 13))
		crow.add_child(PUi.button("−", func(): main.set_conqueror(k2, cur - 1), cur > 0, 12))
		crow.add_child(PUi.button("+", func(): main.set_conqueror(k2, cur + 1), int(ci.free) > 0 and cur < int(sd.max_points), 12))
		crow.add_child(PUi.rich("[color=#6a7078]%s[/color]" % PGlossaryTip.esc(String(sd.get("applies", ""))), 10))
		cbox.add_child(crow)
	body.add_child(cc2.panel)
	# ---------- 특성 ----------
	var sel := PProfile.selected_traits(p)
	var tc := PUi.card("%s [color=#9ea8b8]행마다 1개 · 장착 %d/%d · 무료 재선택 · 다음 새 회차부터 반영(진행 중 회차는 출발 때 고정)[/color]" % [PGlossaryTip.term("trait", "영구 특성"), sel.size(), int(PCatalog.traits().max_equipped)])
	var tbox: VBoxContainer = tc.box
	var D := PCatalog.trait_defs()
	for row in PCatalog.trait_rows():
		var lvl := int(row.level)
		var open := PProfile.row_unlocked(p, lvl)
		var cur = (p.traits as Dictionary).get(str(lvl), null)
		var rrow := PUi.hbox(6)
		rrow.add_child(PUi.rich_nowrap("[b]Lv%d %s[/b]%s" % [lvl, PGlossaryTip.esc(String(row.name)), "" if open else " [color=#6a7078](Lv%d에 열림)[/color]" % lvl], 13))
		for id in row.ids:
			var tid := String(id)
			var td: Dictionary = D[tid]
			var on: bool = cur != null and String(cur) == tid
			var can := PProfile.can_equip_trait(p, lvl, tid)
			var b := PUi.button(("● " if on else "○ ") + String(td.name), func(): main.set_trait(lvl, "" if on else tid), open and (on or bool(can.ok)), 12)
			b.tooltip_text = "%s\n적합: %s%s" % [String(td.short), String(td.fit), ("\n" + String(can.reason)) if (not bool(can.ok) and not on) else ""]
			rrow.add_child(b)
		rrow.add_child(PUi.spacer())
		tbox.add_child(rrow)
		if cur != null and D.has(String(cur)):
			tbox.add_child(PUi.rich("[color=#9ea8b8]  → %s[/color]" % PGlossaryTip.esc(String(D[String(cur)].short)), 11))
	body.add_child(tc.panel)
	# ---------- 도감 ----------
	var cnt := PProfile.counts(p)
	var u := PProfile.unlocked(p)
	var dc := PUi.card("도감 [color=#9ea8b8]자동기술 획득 %d/%d · 시작 가능 %d/%d · 개조 %d/%d · 공용 %d/%d · E %d/%d · Q 변형 %d/%d · 장비 %d/%d · 제작법 %d/%d[/color]" % [int(cnt.weapons.have), int(cnt.weapons.total), int(cnt.start.have), int(cnt.start.total), int(cnt.mods.have), int(cnt.mods.total), int(cnt.commons.have), int(cnt.commons.total), int(cnt.e.have), int(cnt.e.total), int(cnt.q_variants.have), int(cnt.q_variants.total), int(cnt.equipment.have), int(cnt.equipment.total), int(cnt.recipes.have), int(cnt.recipes.total)])
	var dbox: VBoxContainer = dc.box
	dbox.add_child(PUi.rich("[color=#9ea8b8]잠긴 항목을 누르면 이름·짧은 효과·조건이 보입니다. 발견 경로는 안내하지 않습니다.[/color]", 11))
	var W := PCatalog.weapons()
	var U := PCatalog.meta_unlocks()
	_chips(dbox, "자동기술(회차 중 획득)", "weapons", U.weapons.keys(), u.weapons, func(id: String) -> String: return String(W[id].name))
	_chips(dbox, "시작 선택", "start_weapons", U.start_weapons.keys(), u.start_weapons, func(id: String) -> String: return String(W[id].name))
	for wid in U.mods:
		if String(wid) == "note":
			continue
		var w := String(wid)
		var have: Array = (u.mods as Dictionary).get(w, [])
		_chips(dbox, "%s 개조" % String(W[w].name), "mods:" + w, PCatalog.mods_of(w).keys(), have, func(id: String) -> String: return String(W[w].mods[id].name))
	_chips(dbox, "공용 증강", "commons", U.commons.keys(), u.commons, func(id: String) -> String: return String(PCatalog.commons()[id].name))
	_chips(dbox, "Q 변형", "q_variants", U.q_variants.keys(), u.q_variants, func(id: String) -> String: return String(PCatalog.skills().slowfield.variants[id].name))
	_chips(dbox, "E 기술(변형 2종 함께)", "e_skills", U.e_skills.keys(), u.e_skills, func(id: String) -> String: return String(PCatalog.skills()[id].name))
	_chips(dbox, "장비", "equipment", U.equipment.keys(), u.equipment, func(id: String) -> String: return String(PCatalog.equipment()[id].name))
	_chips(dbox, "제작법(대장간)", "recipes", U.recipes.keys(), u.recipes, func(id: String) -> String: return String(PCatalog.crafted_equipment()[id].name))
	if _detail != "":
		dbox.add_child(_detail_card())
	body.add_child(dc.panel)
	var back := PUi.button("돌아가기 (Esc)", func(): main.go_title(), true, 14)
	bottom.add_child(back)
	default_button = back

## 한 분류의 항목 줄: 열린 항목은 글자, 잠긴 항목은 '잠김' 버튼(상세 보기)
func _chips(into: VBoxContainer, title: String, cat: String, ids: Array, have: Array, name_of: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_child(PUi.rich_nowrap("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(title), 12))
	for id in ids:
		var sid := String(id)
		if sid == "note":
			continue
		var nm := String(name_of.call(sid))
		if have.has(sid):
			flow.add_child(PUi.rich_nowrap(PGlossaryTip.esc(nm), 12))
		else:
			var key := cat + ":" + sid
			var b := PUi.button("잠김 · " + nm, func(): _detail = key; refresh(), true, 11)
			b.add_theme_color_override("font_color", PUi.DIM)
			flow.add_child(b)
	into.add_child(flow)

## 잠긴 항목 상세: 이름 · 짧은 효과 · 해금 조건(+ 제작법은 재료)
func _detail_card() -> Control:
	var sep := _detail.find(":")
	var cat := _detail.substr(0, sep)
	var rest := _detail.substr(sep + 1)
	var name := ""
	var effect := ""
	var cond := ""
	var W := PCatalog.weapons()
	if cat == "mods":
		var pr := rest.split(":")
		var md: Dictionary = W[pr[0]].mods[pr[1]]
		name = "%s 개조: %s" % [String(W[pr[0]].name), String(md.name)]
		effect = String(md.desc)
		cond = PProfile.unlock_text("mods", pr[0])
	else:
		cond = PProfile.unlock_text(cat, rest)
		match cat:
			"weapons":
				name = String(W[rest].name); effect = String(W[rest].desc)
			"start_weapons":
				name = "시작 선택: " + String(W[rest].name); effect = String(W[rest].desc)
			"commons":
				name = String(PCatalog.commons()[rest].name); effect = String(PCatalog.commons()[rest].desc)
			"q_variants":
				var v: Dictionary = PCatalog.skills().slowfield.variants[rest]
				name = "감속장 변형: " + String(v.name); effect = String(v.desc)
			"e_skills":
				var d: Dictionary = PCatalog.skills()[rest]
				name = "E " + String(d.name); effect = String(d.desc)
			"equipment":
				var d: Dictionary = PCatalog.equipment()[rest]
				name = String(d.name); effect = String(d.short)
			"recipes":
				var d: Dictionary = PCatalog.crafted_equipment()[rest]
				name = String(d.name) + " 제작법"
				effect = String(d.short)
				var rc: Dictionary = d.recipe
				var ing := []
				for e in rc.equipment:
					ing.append(PRun.equip_name(String(e)))
				for m in rc.mats:
					ing.append("%s %d" % [String(PCatalog.materials()[String(m)].name), int(rc.mats[m])])
				effect += " · 재료: %s · 수수료 %d금" % [", ".join(ing), int(rc.fee)]
	var c := PUi.card("[color=#ffe066]잠김[/color] %s" % PGlossaryTip.esc(name), PUi.CARD_OFF, 13)
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich(PGlossaryTip.esc(effect), 12))
	box.add_child(PUi.rich("[color=#9ea8b8]조건: %s[/color]" % PGlossaryTip.esc(cond if cond != "" else "처음부터"), 12))
	box.add_child(PUi.button("닫기", func(): _detail = ""; refresh(), true, 11))
	return c.panel
