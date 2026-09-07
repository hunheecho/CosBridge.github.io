class_name PBaseScreen
extends PScreen
## 거점(HTML base/finalPrep): 상단 줄(날짜·시간대·보스·체력·금화) + 오늘의 장소 카드 2장(요약 + 상세 보기) + 거점 행동 + 장비·성장 패널.
## phase == boss_prep 이면 최종 준비(보스 카드 전체 정보·입장). 하루 종료는 확인 창(PRun.preview_next_day)을 거친다.
## 모든 수치는 PRun/PSortie/PBuild가 준 값(실제 적용 빌드)이다.

const RISK_DESC := { "reinforce": "지원병 총량 ×1.5", "escort": "첫 웨이브에 정예 1 추가", "hazard": "주기적 바닥 붕괴(안전 통로 있음)" }
const BOSS_DESC := {
	"boss": "숲과 늑대 무리를 지배하는 거대한 늑대. 목과 등에 부러진 나뭇가지 같은 검은 가시가 돋았고, 한쪽 송곳니가 부러졌다.",
	"guardian": "봉인을 지키는 돌 갑옷의 거인. 느리지만 한 번의 휩쓸기가 무겁고, 봉인 장치가 바닥을 위험하게 만든다.",
	"eater": "예언을 삼키는 시간의 포식자. 당신이 지나온 자리를 표식으로 찍고, 두 줄의 직선과 광역으로 공간을 좁힌다.",
}

var _detail_open: Dictionary = {}   # card id → bool
var _confirm: Control
var _confirm_box: VBoxContainer

func _build() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.1, 0.12, 0.15, 0.98), 8, 16, Color(0.5, 0.6, 0.75, 0.9)))
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	_confirm_box = PUi.vbox(8)
	panel.add_child(_confirm_box)
	_confirm.visible = false
	add_child(_confirm)

func on_escape() -> bool:
	if _confirm.visible:
		_confirm.visible = false
		return true
	return false

func refresh() -> void:
	clear_all()
	_confirm.visible = false
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	var wf := PRun.world_feature(r)
	if not wf.is_empty(): # 회차 특징 한 줄(시드 확정, 재접속 재추첨 없음)
		top.add_child(PUi.rich("[color=#9ea8b8]이번 회차[/color] [b]%s[/b] [color=#9ea8b8]— %s[/color]" % [PGlossaryTip.esc(String(wf.name)), PGlossaryTip.esc(String(wf.line))], 12))
	if String(r.phase) != "prep":
		_final_prep(r)
		return
	var cols := two_cols(0.56)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	left.add_child(PUi.rich("[b]오늘의 장소[/b] [color=#9ea8b8]2곳 · 출발 시간대에 편성·사건·보상 확정 · 승리 후 %s 1회[/color]" % PGlossaryTip.term("deep", "더 깊이"), 16))
	var first_btn: Button = null
	for c in PSortie.cards_for(r):
		var res := _place_card(r, c)
		left.add_child(res.panel)
		if first_btn == null and res.button != null and not (res.button as Button).disabled:
			first_btn = res.button
	_merchant_card(r, left)
	_actions_card(r, left)
	_services_card(r, left)
	left.add_child(_boss_card(r, false))
	right.add_child(PUi.equip_panel(r))
	right.add_child(PUi.build_panel(r))
	_stats_compact(r, right)
	_log_card(r, right)
	default_button = first_btn

# ---------- 오늘의 장소 카드 ----------
func _place_card(r: Dictionary, c: Dictionary) -> Dictionary:
	var rid := String(c.regionId)
	var reg := PRun.region(rid)
	var can := PSortie.can_start(r, c)
	var M := PCatalog.mission_rules()
	var obj := String(c.objective)
	var O: Dictionary = PCatalog.objectives().get(obj, {}) if obj != "clear" else {}
	var slot := PRun.slot_index(r)
	var v: Dictionary = PRun.slot_variant(rid, slot) if int(r.hours) > 0 else {}
	var hpm := PRun.hp_mult_for(r, rid, false)
	var waves := PRun.encounter_waves(rid, false, r, { "variant": (v if not v.is_empty() else null) })
	var elite := false
	for eid in c.enemies:
		if bool(PCatalog.enemy(String(eid)).get("elite", false)):
			elite = true
	for w in waves:
		for g in w:
			if bool(PCatalog.enemy(String(g.type)).get("elite", false)):
				elite = true
	var has_risk: bool = c.get("risk", null) != null
	var gm := (PRun.risk_reward_mult(r) if has_risk else 1.0) * (float(v.goldMult) if v.has("goldMult") else 1.0)
	var reward := "금화 %d~%d" % [int(round(float(reg.reward.gold[0]) * gm)), int(round(float(reg.reward.gold[1]) * gm))]
	var steer := PSortie.steer_state(r, c)
	var done: bool = bool(c.done)
	var card := PUi.card("", PUi.CARD_OFF if (done or not can) else PUi.CARD)
	var box: VBoxContainer = card.box
	var title := "[b]%s[/b] [color=#9ea8b8][%d칸][/color]  %s" % [PGlossaryTip.esc(String(reg.name)), int(c.timeCost), (PGlossaryTip.term("mission", String(O.name)) if not O.is_empty() else "전멸")]
	if elite:
		title += " · " + PGlossaryTip.term("elite", "정예")
	if has_risk:
		title += " · [color=#ff8c73]%s[/color]" % PGlossaryTip.esc(String(M.riskText[String(c.risk)]))
	if done:
		title += "  [color=#9ea8b8](오늘 완료)[/color]"
	box.add_child(PUi.rich(title, 16))
	var names := []
	for eid in c.enemies:
		var ed := PCatalog.enemy(String(eid))
		if not bool(ed.get("elite", false)) and names.size() < 3:
			names.append(String(ed.name))
	box.add_child(PUi.rich("%s · %s%s" % ["·".join(names), reward, (" · 체력 ×%s" % PUi.fmt(float(hpm.normal))) if float(hpm.normal) != 1.0 else ""], 13))
	var slots := PRun.time_slots()
	var vline := ""
	if not v.is_empty():
		vline = "[color=#ffe066]지금 출발하면 · %s[/color] %s" % [PGlossaryTip.term("variant_slot", "%s %s" % [String(slots[mini(slot, slots.size() - 1)]), String(v.name)]), PGlossaryTip.esc(String(v.desc))]
	else:
		vline = "[color=#9ea8b8]%s 출발: 기본 편성[/color]" % String(slots[mini(slot, slots.size() - 1)])
	var others := [] # 실제 출발 시간대 기준(Q4: 비용 2 장소의 저녁 변주는 오후로 이동한 슬롯으로 표시)
	for ov in PRun.slot_variants_list(rid):
		var si := int(ov.slot)
		if si != slot:
			others.append("%s %s" % [String(slots[si]), String(ov.name)])
	if others.size() > 0:
		vline += " [color=#6a7078]· 다른 시간대: %s[/color]" % PGlossaryTip.esc(" · ".join(others))
	box.add_child(PUi.rich(vline, 12))
	if not O.is_empty():
		box.add_child(PUi.rich("보상: [b]%s[/b]%s" % [PGlossaryTip.esc(String(steer.text)), (" [color=#9ea8b8](%s)[/color]" % PGlossaryTip.esc(String(c.rewardTarget))) if String(c.get("rewardTarget", "")) != "" else ""], 12))
	# 상세 보기(접힘)
	var cid := String(c.id)
	var opened: bool = bool(_detail_open.get(cid, false))
	var detail := PUi.vbox(3)
	detail.visible = opened
	detail.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(O.desc) if not O.is_empty() else String(reg.desc)), 12))
	if has_risk:
		PUi.kv(detail, "위험 조건", "[b]%s[/b] [color=#9ea8b8](%s) · 금화 ×%s[/color]" % [PGlossaryTip.esc(String(M.riskText[String(c.risk)])), String(RISK_DESC.get(String(c.risk), "")), str(PRun.risk_reward_mult(r))], 12)
	var fname := String(c.get("formationName", "기본"))
	var fdesc := String(c.get("formationDesc", ""))
	PUi.kv(detail, "편성", "[b]%s · %d웨이브 · 전멸(웨이브·대기 포함)[/b]%s" % [PGlossaryTip.esc(fname), waves.size(), ((" [color=#9ea8b8]— %s[/color]" % PGlossaryTip.esc(fdesc)) if fdesc != "" else "")], 12)
	PUi.kv(detail, "경험치", "[b]처치 즉시 · 지역 +%s[/b]" % str(PRun.region_bonus_xp(r, rid, false)), 12)
	for eid in c.enemies:
		var ed := PCatalog.enemy(String(eid))
		detail.add_child(PUi.rich("  [b]%s[/b] [color=#9ea8b8]%s — %s[/color]" % [PGlossaryTip.esc(String(ed.name)), PGlossaryTip.esc(String(ed.get("role", ""))), PGlossaryTip.esc(String(ed.get("readme", "")))], 12))
	var toggle := PUi.button(("상세 닫기 ▾" if opened else "상세 보기 ▸"), func(): _toggle_detail(cid), true, 12)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(toggle)
	box.add_child(detail)
	var why := ""
	if done:
		why = "오늘 완료"
	elif String(r.phase) != "prep":
		why = "출격 불가"
	elif PRun.is_boss_day(r):
		why = "관문 날"
	elif int(r.hours) < int(c.timeCost):
		why = "시간 부족 (%d칸 필요)" % int(c.timeCost)
	var label := ("출격 (%d칸 · %s 출발)" % [int(c.timeCost), String(slots[mini(slot, slots.size() - 1)])]) if can else why
	if int(c.attempts) > 0 and not done:
		label += " · 시도 %d" % int(c.attempts)
	var btn := PUi.button(label, func(): main.start_sortie_card(cid), can, 15)
	box.add_child(btn)
	return { "panel": card.panel, "button": btn }

func _toggle_detail(cid: String) -> void:
	_detail_open[cid] = not bool(_detail_open.get(cid, false))
	refresh()

func _merchant_card(r: Dictionary, into: VBoxContainer) -> void:
	var m = r.get("merchant", null)
	if m == null or int(m.day) != int(r.day):
		return
	var slots := PRun.time_slots()
	var disc := int(round(float(PCatalog.shop().merchantDiscount) * 100.0))
	if not PRun.merchant_open(r):
		into.add_child(PUi.rich("[b]방문 상인[/b] [color=#9ea8b8]%s부터 하루 끝까지 · 장비 1개 할인(%d%%)·무료 휴식권[/color]" % [String(slots[int(m.fromSlot)]), disc], 12))
		return
	var c := PUi.card("방문 상인 [color=#9ea8b8]오늘 끝까지 · 상점 화면에서 거래[/color]", PUi.CARD_ON)
	var box: VBoxContainer = c.box
	var eq_txt := "[color=#9ea8b8]장비 품절[/color]"
	if m.get("equipment", null) != null and not (m.sold as Array).has(String(m.equipment)):
		eq_txt = "%s [color=#ffd966][b]%d[/b][/color] (%d%% 할인)" % [PUi.equip_line(String(m.equipment)), PRun.equip_price_for(r, String(m.equipment), "merchant"), disc]
	box.add_child(PUi.rich("%s · 무료 휴식권 [color=#ffd966][b]%d[/b][/color]%s" % [eq_txt, int(m.servicePrice), " (판매됨)" if (m.sold as Array).has("service") else ""], 12))
	box.add_child(PUi.button("상인에게 (상점)", func(): main.show("shop"), true, 12))
	into.add_child(c.panel)

func _actions_card(r: Dictionary, into: VBoxContainer) -> void:
	var c := PUi.card("거점")
	var box: VBoxContainer = c.box
	var pend := int(r.growth.pendingLevelUps)
	if pend > 0:
		box.add_child(PUi.button("미처리 레벨업 선택 (%d)" % pend, func(): main.offer_pending_level_ups(), true, 15))
	var row := PUi.hbox(6)
	row.add_child(PUi.button("상점", func(): main.show("shop"), true, 14))
	row.add_child(PUi.button("대장간", func(): main.show("forge"), true, 14))
	row.add_child(PUi.button("장비", func(): main.show("equip"), true, 14))
	row.add_child(PUi.button("통계", func(): main.show("stats"), true, 14))
	row.add_child(PUi.button("기록", func(): main.show("log"), true, 14))
	box.add_child(row)
	box.add_child(PUi.rich("[color=#6a7078]상점·대장간·장비 교체는 시간을 쓰지 않습니다.[/color]", 11))
	var can_rest := PRun.can_rest(r)
	var full: bool = float(r.hp) >= float(PBuild.derive(r).hp_max)
	var rest_txt := ""
	if PRun.has_service(r, "free_rest"):
		rest_txt = "휴식 (무료 휴식권 · 시간 소모 없음)"
	else:
		rest_txt = "휴식 → %s" % PRun.next_slot_name(r)
	rest_txt += "  " + ("체력 가득 · 시간만 넘김" if full else "체력 완전 회복") + ("" if can_rest else " · 남은 칸 없음")
	box.add_child(PUi.button(rest_txt, func(): main.rest(), can_rest, 14))
	var nx := PRun.preview_next_day(r)
	var next_txt := ""
	if nx.has("boss"):
		next_txt = "보스 관문 (%s)" % String(PCatalog.boss_def(String(nx.boss)).name)
	else:
		var ps := []
		for p in nx.places:
			ps.append("%s%s" % [String(p.name), "(정예)" if bool(p.elite) else ""])
		next_txt = " · ".join(ps)
	box.add_child(PUi.button("하루 종료 → %d일차  %s내일: %s" % [int(r.day) + 1, ("(남은 %d칸 버림) · " % int(r.hours)) if int(r.hours) > 0 else "", next_txt], func(): _open_endday(), true, 14))
	box.add_child(PUi.button("저장 후 종료", func(): main.save_quit(), true, 13))
	into.add_child(c.panel)

func _services_card(r: Dictionary, into: VBoxContainer) -> void:
	var parts := []
	var S := PCatalog.services()
	for k in r.get("services", {}):
		if int(r.services[k]) > 0:
			parts.append("[b]%s[/b] ×%d" % [String(S[String(k)].name), int(r.services[k])])
	if parts.is_empty():
		return
	into.add_child(PUi.rich("[b]보유 이용권[/b]  %s [color=#9ea8b8](개조 교체권·할인권은 상점·대장간에서 사용)[/color]" % " · ".join(parts), 12))

## 다가오는 보스 카드(HTML bossCard). full=true면 설명·정보 줄 전부
func _boss_card(r: Dictionary, full: bool) -> Control:
	var B := PRun.next_boss_cfg(r)
	var left := PRun.boss_days_left(r)
	var nb := PRun.next_boss(r)
	var stages := PRun.stage_count(r)
	var when := "처치함" if String(r.phase) == "cleared" else (("%d일 뒤 도래" % left) if left > 0 else "오늘 도래")
	var hp := PRun.boss_hp(r, String(B.id))
	var stage_lbl := ("%d단계 보스" % (int(r.get("stage", 0)) + 1)) if stages > 1 else ("보스" if not full else "다가오는 보스")
	var info: Array = B.get("info", [])
	if not full:
		var c := PUi.card("", PUi.CARD_BOSS)
		(c.box as VBoxContainer).add_child(PUi.rich("[b]%s: %s[/b] [color=#ffe066]%s[/color]  [color=#9ea8b8]%s[/color]" % [stage_lbl, PGlossaryTip.esc(String(B.name)), when, PGlossaryTip.esc(String(info[0]) if info.size() > 0 else "")], 13))
		return c.panel
	var c2 := PUi.card("", PUi.CARD_BOSS)
	var box: VBoxContainer = c2.box
	box.add_child(PUi.rich("[b]%s: %s — %s[/b] [color=#ffe066]%s[/color]" % [stage_lbl, PGlossaryTip.esc(String(B.name)), PGlossaryTip.esc(String(B.get("title", ""))), when], 15))
	box.add_child(PUi.rich(String(BOSS_DESC.get(String(B.id), "")), 13))
	for t in info:
		box.add_child(PUi.rich("• " + PGlossaryTip.esc(String(t)), 12))
	var ph := []
	for p in B.get("phases", []):
		ph.append("%d%%" % int(round(float(p) * 100.0)))
	box.add_child(PUi.rich("[color=#9ea8b8]전장: %s · 체력 %d · 단계 전환 %s · 시간제한 없음%s[/color]" % [PGlossaryTip.esc(String(PCatalog.arenas().clearing.name)), int(hp), "·".join(ph), " · 승리 시 희귀 보상 3택" if (not nb.is_empty() and bool(nb.get("rare", false))) else ""], 12))
	return c2.panel

func _stats_compact(r: Dictionary, into: VBoxContainer) -> void:
	var combats: Array = r.get("dmgStats", {}).get("combats", [])
	if combats.is_empty():
		return
	var a := PStats.aggregate(r)
	var row := PUi.hbox(8)
	row.add_child(PUi.rich("[b]피해 통계[/b] [color=#9ea8b8]전투 %d회 · 총 %s · 전체 DPS %s[/color]" % [int(a.n), str(a.total), str(a.dpsAll)], 12))
	row.add_child(PUi.button("통계 보기", func(): main.show("stats"), true, 12))
	into.add_child(row)

func _log_card(r: Dictionary, into: VBoxContainer) -> void:
	var L: Array = r.get("log", [])
	var c := PUi.card("최근 기록", PUi.CARD, 13)
	var box: VBoxContainer = c.box
	if L.is_empty():
		box.add_child(PUi.rich("[color=#9ea8b8]아직 없음[/color]", 12))
	for i in mini(4, L.size()):
		box.add_child(PUi.rich("[color=#c8ced8]%s[/color]" % PGlossaryTip.esc(String(L[i])), 11))
	into.add_child(c.panel)

# ---------- 하루 종료 확인 ----------
func _open_endday() -> void:
	var r := run()
	PUi.clear(_confirm_box)
	var nx := PRun.preview_next_day(r)
	_confirm_box.add_child(PUi.rich("[b]하루를 마칠까요?[/b]", 20))
	_confirm_box.add_child(PUi.rich("%s%d일차 %s으로 넘어갑니다. 체력이 완전히 회복됩니다." % [("남은 %d칸을 버리고 " % int(r.hours)) if int(r.hours) > 0 else "", int(r.day) + 1, String(PRun.time_slots()[0])], 13))
	if nx.has("boss"):
		var c := PUi.card("내일: %s 관문" % PGlossaryTip.esc(String(PCatalog.boss_def(String(nx.boss)).name)), PUi.CARD_BOSS)
		(c.box as VBoxContainer).add_child(PUi.rich(("내일은 보스 관문으로 시작합니다. 상점·대장간·장비 교체 뒤 보스전에 들어가고, 이기면 그날의 시간대가 시작됩니다." if PRun.stage_count(r) > 1 else "일반 출격이 없습니다. 최종 준비 뒤 보스전에 들어갑니다.") + " 패배해도 입장 시점으로 돌아와 같은 준비로 재도전합니다.", 12))
		_confirm_box.add_child(c.panel)
	else:
		var c2 := PUi.card("내일의 장소")
		var box: VBoxContainer = c2.box
		for p in nx.places:
			var en := []
			for t in p.enemies:
				en.append(String(PCatalog.enemy(String(t)).name))
			box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s%s[/color]" % [PGlossaryTip.esc(String(p.name)), "·".join(en), " · [b]정예[/b]" if bool(p.elite) else ""], 12))
		var MV: Dictionary = PCatalog.world().merchant_visits
		for d in MV.days:
			if int(d) == int(nx.day):
				box.add_child(PUi.rich("[color=#ffe066]상인[/color] %s부터 방문 상인" % String(PRun.time_slots()[int(MV.slot)]), 12))
		if not PRun.next_boss(r).is_empty() and PRun.boss_days_left(r) - 1 > 0:
			box.add_child(PUi.rich("[color=#9ea8b8]다음 보스까지 %d일[/color]" % (PRun.boss_days_left(r) - 1), 12))
		_confirm_box.add_child(c2.panel)
	var row := PUi.hbox(8)
	var ok := PUi.button("하루 종료", func(): main.end_day(), true, 15)
	row.add_child(ok)
	row.add_child(PUi.button("돌아가기 (Esc)", func(): _confirm.visible = false, true, 15))
	_confirm_box.add_child(row)
	default_button = ok
	_confirm.visible = true

# ---------- 최종 준비(관문) ----------
func _final_prep(r: Dictionary) -> void:
	var b := PBuild.derive(r)
	var cleared: bool = String(r.phase) == "cleared"
	var stages := PRun.stage_count(r)
	var g: Dictionary = r.growth
	var h := "%d일차 — %s" % [int(r.day), ("회차 완주" if stages > 1 else "예언의 날을 넘겼다") if cleared else (("%d단계 보스 관문" % (int(r.get("stage", 0)) + 1)) if stages > 1 else "최종 준비")]
	heading(h)
	var note := ""
	if cleared:
		note = "마지막 보스를 넘었습니다. 이 회차의 성장은 여기서 끝납니다. 같은 빌드로 다시 도전하거나 새 회차를 시작하세요."
	else:
		note = "보스전은 하루 시간 밖의 관문입니다. 상점·대장간·장비 교체는 시간을 쓰지 않습니다. 패배하면 입장 시점으로 돌아와 같은 준비로 재도전합니다(하루 손실 없음)."
		if stages > 1 and int(r.get("stage", 0)) < stages - 1:
			note += " 승리하면 그날의 시간대가 %s부터 시작됩니다." % String(PRun.time_slots()[0])
	top.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % note, 12))
	var cols := two_cols(0.55)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	var wn := []
	for w in g.weapons:
		wn.append("%s Lv%d" % [String(PCatalog.weapon(String(w.id)).name), int(w.level)])
	var snap := PUi.card("입장 스냅샷", PUi.CARD, 13)
	(snap.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]Lv %d · %s · 체력 %d · 재도전 %d회%s[/color]" % [int(g.level), ", ".join(wn), int(float(b.hp_max)), int(r.get("bossRetries", 0)), " (입장 시점 상태로 복구됨: 처치 경험치·보상 중복 없음)" if int(r.get("bossRetries", 0)) > 0 else ""], 12))
	left.add_child(snap.panel)
	var recs: Dictionary = r.get("bossRecords", {})
	if not recs.is_empty():
		var rc := PUi.card("처치 기록", PUi.CARD_ON, 13)
		for k in recs:
			var rec: Dictionary = recs[k]
			(rc.box as VBoxContainer).add_child(PUi.rich("%s: %s초 · 재도전 %d회 · Lv %d · 보스에게 준 피해 %d" % [PGlossaryTip.esc(String(PCatalog.boss_def(String(rec.get("bossId", "boss"))).name)), str(rec.time), int(rec.retries), int(rec.get("level", 0)), int(float(rec.get("bossDamage", 0.0)))], 12))
		left.add_child(rc.panel)
	left.add_child(_boss_card(r, true))
	var prep := PUi.card("준비")
	var pb: VBoxContainer = prep.box
	var enter := PUi.button("이번 빌드로 보스 다시 도전" if cleared else "보스에게 간다 (입장)", func(): main.start_boss(), PRun.can_start_boss(r), 16)
	pb.add_child(enter)
	default_button = enter
	var row := PUi.hbox(6)
	row.add_child(PUi.button("상점", func(): main.show("shop"), true, 14))
	row.add_child(PUi.button("대장간", func(): main.show("forge"), true, 14))
	row.add_child(PUi.button("장비", func(): main.show("equip"), true, 14))
	row.add_child(PUi.button("통계", func(): main.show("stats"), true, 14))
	row.add_child(PUi.button("기록", func(): main.show("log"), true, 14))
	pb.add_child(row)
	if cleared:
		pb.add_child(PUi.button("회차 결과 보기", func(): main.show("run_result"), true, 14))
		pb.add_child(PUi.button("새 회차 시작", func(): main.new_run_flow(), true, 14))
	pb.add_child(PUi.button("저장 후 종료", func(): main.save_quit(), true, 13))
	left.add_child(prep.panel)
	right.add_child(PUi.equip_panel(r))
	right.add_child(PUi.build_panel(r))
	_stats_compact(r, right)
	_log_card(r, right)
