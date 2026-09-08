class_name PBaseScreen
extends PScreen
## 거점(HTML base/finalPrep) — 마을 홈 구성(사용자 긍정 평가 방향, 2026-09-07): 상단 줄(날짜·시간대 5칸·관문·체력·금화·세계 변화, PUi.header) + 회차 특징 한 줄,
## 왼쪽 = 클릭/탭 가능한 마을 그림(PVillageMap: 대장간·상점·장비·통계·기록·휴식, 걷기 없음) + 오늘의 출격 카드 2장(큰 버튼, 상세는 접힘),
## 오른쪽 = 간결한 현재 빌드(자동기술 3 슬롯·Q/E·장비 3, 한 줄씩; 전체 패널은 "상세" 토글 뒤) + 다가오는 보스 + 하루 종료·저장.
## phase == boss_prep 이면 최종 준비(보스 카드 전체 정보·입장). 하루 종료는 확인 창(PRun.preview_next_day)을 거친다.
## 모든 수치는 PRun/PSortie/PBuild가 준 값(실제 적용 빌드)이다. 열 비율·마을 높이는 PLayout(화면 비율 묶음)이 준다.

const RISK_DESC := { "reinforce": "지원병 총량 ×1.5", "escort": "첫 웨이브에 정예 1 추가", "hazard": "주기적 바닥 붕괴(안전 통로 있음)" }
const BOSS_DESC := {
	"boss": "숲과 늑대 무리를 지배하는 거대한 늑대. 목과 등에 부러진 나뭇가지 같은 검은 가시가 돋았고, 한쪽 송곳니가 부러졌다.",
	"guardian": "봉인을 지키는 돌 갑옷의 거인. 느리지만 한 번의 휩쓸기가 무겁고, 봉인 장치가 바닥을 위험하게 만든다.",
	"eater": "예언을 삼키는 시간의 포식자. 당신이 지나온 자리를 표식으로 찍고, 두 줄의 직선과 광역으로 공간을 좁힌다.",
}

var _detail_open: Dictionary = {}   # card id → bool
var _build_detail_open := false     # 오른쪽 빌드 요약의 "상세" 토글
var _confirm: Control
var _confirm_box: VBoxContainer
var village: PVillageMap = null     # 마을 그림(refresh마다 새로 만든다)

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
	var cth := PRun.current_theme(r)
	if not cth.is_empty(): # 현재 막 테마 한 줄(계획서 §4: 1막은 거점에서 공개, 다음 막은 관문 준비에서)
		top.add_child(PUi.rich("[color=#9ea8b8]%s[/color] [b]%s[/b] [color=#9ea8b8]— %s · 보스: %s[/color]" % [PGlossaryTip.esc(PRun.act_label(r).split(" · ")[0]), PGlossaryTip.esc(String(cth.name)), PGlossaryTip.esc(String(cth.line)), PGlossaryTip.esc(String(PCatalog.boss_def(String(cth.boss)).name))], 12))
	if String(r.phase) != "prep":
		if PEndless.active(r):
			_endless_home(r)
		else:
			_final_prep(r)
		return
	var bk := bucket()
	var cols := two_cols(PLayout.left_ratio(bk))
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	# 왼쪽: 마을(시설은 건물을 눌러 연다) + 오늘의 출격 2장
	village = PVillageMap.new()
	village.custom_minimum_size = Vector2(0, PLayout.village_height(bk))
	village.picked.connect(_on_village_pick)
	village.set_state("rest", PRun.can_rest(r), _rest_label(r))
	left.add_child(village)
	left.add_child(PUi.rich("[color=#6a7078]건물을 누르면 바로 열립니다(시간 소모 없음) · %s[/color]" % _rest_note(r), 11))
	left.add_child(PUi.rich("[b]오늘의 출격[/b] [color=#9ea8b8]2곳 · 출발 시간대에 편성·사건·보상 확정 · 승리 후 %s 1회[/color]" % PGlossaryTip.term("deep", "더 깊이"), 16))
	var first_btn: Button = null
	var row := PUi.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for c in PSortie.cards_for(r):
		var res := _place_card(r, c)
		(res.panel as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(res.panel as Control).size_flags_stretch_ratio = 1.0
		row.add_child(res.panel)
		if first_btn == null and res.button != null and not (res.button as Button).disabled:
			first_btn = res.button
		if first_btn == null and res.get("repeat_button", null) != null and not (res.repeat_button as Button).disabled:
			first_btn = res.repeat_button # 오늘 카드를 다 끝냈으면 '일반 탐험'이 기본 버튼이 된다
	left.add_child(row)
	_prep_card(r, left)
	_merchant_card(r, left)
	_services_card(r, left)
	# 오른쪽: 간결한 빌드 + 보스 + 오늘의 행동
	right.add_child(_build_summary(r))
	right.add_child(_boss_card(r, false))
	_actions_card(r, right)
	if _build_detail_open:
		right.add_child(PUi.equip_panel(r))
		right.add_child(PUi.build_panel(r))
		_stats_compact(r, right)
		_log_card(r, right)
	default_button = first_btn

## 마을 건물 → 화면(같은 main 함수). 휴식은 오늘의 버튼과 같은 규칙(PRun.rest)
func _on_village_pick(id: String) -> void:
	match id:
		"forge": main.show("forge")
		"shop": main.show("shop")
		"equip": main.show("equip")
		"stats": main.show("stats")
		"rest": main.rest()

func _rest_label(r: Dictionary) -> String:
	if PRun.has_service(r, "free_rest"):
		return "휴식 (무료권)"
	return "휴식 → %s" % PRun.next_slot_name(r)

func _rest_note(r: Dictionary) -> String:
	var can_rest := PRun.can_rest(r)
	var full: bool = float(r.hp) >= float(PBuild.derive(r).hp_max)
	var t := "휴식: "
	if PRun.has_service(r, "free_rest"):
		t += "무료 휴식권 보유(쓸 때 시간 0칸 — 이미 산 권에는 값을 다시 받지 않습니다) · "
	else:
		t += "시간 1칸 · "
	t += ("체력 가득(시간만 넘김)" if full else "체력 완전 회복")
	if not can_rest:
		t += " · 남은 칸 없음"
	return t

## 간결한 현재 빌드(한 줄씩): 자동기술 3 슬롯 · Q/E · 장비 3 · 요약 수치. 전체 패널(장비·성장·통계·기록)은 "상세" 토글
func _build_summary(r: Dictionary) -> Control:
	var b := PBuild.derive(r)
	var g: Dictionary = r.growth
	var S: Dictionary = PCatalog.growth().SLOTS
	var pend := int(g.pendingLevelUps)
	var c := PUi.card("현재 빌드 [color=#9ea8b8]Lv %d · 경험치 %d/%d[/color]%s" % [int(g.level), int(floor(float(g.xp))), PGrowth.xp_need(int(g.level)), (" [color=#ff8c73]미처리 레벨업 %d[/color]" % pend) if pend > 0 else ""], PUi.CARD, 14)
	var box: VBoxContainer = c.box
	# 긴 문장 대신 전투 HUD와 같은 아이콘 구성(자동기술 3칸 + 각 칸 아래 개조 2칸). 방금 고른 칸은 잠깐 강조된다
	box.add_child(PUi.build_icon_row(r, 44.0, 26.0, main.take_pick_highlight()))
	box.add_child(PUi.common_icon_row(r, 24.0))
	var qe := []
	for slot in ["q", "e"]:
		var sk = g.skills.get(slot)
		if sk == null:
			qe.append("[b]E[/b] [color=#6a7078]비어 있음[/color]")
			continue
		var d: Dictionary = PCatalog.skills()[String(sk.id)]
		var term_id := "slowfield" if slot == "q" else "e:" + String(sk.id)
		qe.append("[b]%s[/b] %s Lv%d%s" % [String(d.key), PGlossaryTip.term(term_id, String(d.name)), int(sk.level), (" · " + String(d.variants[String(sk.variant)].name)) if sk.get("variant", null) != null else ""])
	box.add_child(PUi.rich("[color=#9ea8b8]수동[/color] " + " · ".join(qe), 12))
	box.add_child(PUi.equip_icon_row(r, 32.0)) # 장비는 자동기술 칸과 다른 영역(테두리 카드)으로 분리한다
	box.add_child(PUi.rich("[color=#9ea8b8]최대 체력 %d · 이동 ×%s · %s %d/%d · %s %d/%d%s[/color]" % [int(float(b.hp_max)), PUi.fmt(float(b.speed_mult)), PGlossaryTip.term("common", "공용"), PGrowth.common_count(g), int(S.commons), PGlossaryTip.term("passive", "패시브"), PGrowth.passive_count(g), int(S.passives), (" · %s %d단계" % [PGlossaryTip.term("forge", "강화"), int(b.forge)]) if int(b.forge) > 0 else ""], 11))
	var toggle := PUi.button(("상세 닫기 ▾" if _build_detail_open else "상세 보기 ▸ (장비·성장·통계·기록)"), func(): _toggle_build_detail(), true, 12)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	box.add_child(toggle)
	return c.panel

func _toggle_build_detail() -> void:
	_build_detail_open = not _build_detail_open
	refresh()

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
	var rep_ok := _repeat_ready(r, c) # 완료한 카드라도 '일반 탐험'이 가능하면 카드를 흐리게 두지 않는다
	var card := PUi.card("", PUi.CARD_OFF if ((done or not can) and not rep_ok) else PUi.CARD)
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
	var btn := PUi.button(label, func(): main.start_sortie_card(cid), can, 16)
	btn.custom_minimum_size = Vector2(0, PLayout.primary_button_height()) # 주 행동: 큰 버튼(터치 대상)
	box.add_child(btn)
	return { "panel": card.panel, "button": btn, "repeat_button": _repeat_button(r, c, box) }

## 이 카드에 '일반 탐험' 버튼을 보여야 하는가(완료한 카드 + 규칙이 켜져 있고 준비 단계 + 관문 날 아님)
func _repeat_shown(r: Dictionary, c: Dictionary) -> bool:
	return bool(c.done) and PPacing.repeat_enabled() and String(r.phase) == "prep" and not PRun.is_boss_day(r)

## 지금 실제로 나갈 수 있는가. 판정은 공통 규칙이 만든 반복 카드 + PSortie.can_start 그대로다
func _repeat_ready(r: Dictionary, c: Dictionary) -> bool:
	if not _repeat_shown(r, c):
		return false
	var again_id := String(c.id) + ":again"
	for x in PSortie.repeat_cards(r): # 시간이 모자라면 목록이 비어 있다 → 비활성 버튼으로 이유를 보여 준다
		if String(x.id) == again_id:
			return PSortie.can_start(r, x)
	return false

## 남는 시간의 '일반 탐험'(정본 data/pacing.json repeat_sortie): 새 카드를 만들지 않고 완료한 장소 카드 안에 버튼 하나를 더 둔다.
## 카드·시간·출격 가능 판정은 모두 공통 규칙(PSortie.repeat_cards / PSortie.can_start)이 준 값이며 여기서 새 규칙을 만들지 않는다.
## 보상은 정상 전투 전리품뿐이다(임무 보상·사건·이용권·예약은 PSortie.start / PFlow가 repeat 표시로 막는다).
func _repeat_button(r: Dictionary, c: Dictionary, box: VBoxContainer) -> Button:
	if not _repeat_shown(r, c):
		return null
	var again_id := String(c.id) + ":again"
	var cost := PPacing.repeat_cost()
	var can_rep := _repeat_ready(r, c)
	var rname := PPacing.repeat_label()
	var label := ("%s (%d칸)" % [rname, cost]) if can_rep else ("%s · 시간 부족 (%d칸 필요)" % [rname, cost])
	var tries := int(c.get("repeatAttempts", 0))
	if tries > 0 and can_rep:
		label += " · 시도 %d" % tries
	box.add_child(PUi.rich("[color=#9ea8b8]%s: 같은 장소로 한 번 더 · 전리품·경험치만 (임무 보상·사건·이용권 없음)[/color]" % PGlossaryTip.esc(rname), 11))
	var rb := PUi.button(label, func(): main.start_sortie_card(again_id), can_rep, 15)
	rb.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
	box.add_child(rb)
	return rb

func _toggle_detail(cid: String) -> void:
	_detail_open[cid] = not bool(_detail_open.get(cid, false))
	refresh()

## 출격 준비물 1칸(전투 단축키 없음): 가진 준비물 중 1개를 골라 두면 다음 전투 입장 때 저절로 쓰인다.
## 해제·교체는 소모가 아니다. 회복약도 여기서 마신다(거점 전용, 시간 0칸)
func _prep_card(r: Dictionary, into: VBoxContainer) -> void:
	var bag := PConsumables.bag(r)
	var armed := PConsumables.armed(r)
	var have_any: bool = PConsumables.prep_count(r) > 0
	if not have_any and PConsumables.potion_count(r) <= 0:
		into.add_child(PUi.rich("[color=#6a7078]출격 준비물·회복약 없음 — 상점에서 삽니다(준비물은 다음 전투 1회, 시간 소모 없음).[/color]", 12))
		return
	var c := PUi.card("출격 준비물 [color=#9ea8b8]1개만 · 다음 전투에서 소모 · 더 깊이 들어가는 다음 전투로 이어지지 않음[/color]",
		PUi.CARD_ON if armed != "" else PUi.CARD, 15)
	var box: VBoxContainer = c.box
	if have_any:
		var seen := {}
		var row := PUi.hbox(6)
		for x in bag:
			var id := String(x)
			if not PConsumables.is_prep(id) or seen.has(id):
				continue
			seen[id] = true
			var on: bool = armed == id
			var n := PConsumables.count(r, id)
			row.add_child(PUi.button("%s %s ×%d" % ["●" if on else "○", PConsumables.name_of(id), n],
				func(): _pick_prep(r, id), true, 13))
		row.add_child(PUi.spacer())
		box.add_child(row)
		if armed != "":
			box.add_child(PUi.rich("[color=#7fd6a0]장착[/color] [b]%s[/b] — %s" % [PConsumables.name_of(armed), PGlossaryTip.esc(PConsumables.effect_line(armed))], 13))
			box.add_child(PUi.button("해제 (소모 없음)", func(): PConsumables.clear_select(r); main.save_run(); refresh(), true, 12))
		else:
			box.add_child(PUi.rich("[color=#9ea8b8]고르지 않으면 아무것도 쓰지 않습니다(그대로 남습니다).[/color]", 12))
	if PConsumables.potion_count(r) > 0:
		var b := PBuild.derive(r)
		var can := PConsumables.can_use_potion(r)
		var prow := PUi.hbox(6)
		prow.add_child(PUi.button("회복약 사용 ×%d" % PConsumables.potion_count(r), func(): _use_potion(r), can, 13))
		prow.add_child(PUi.rich("[color=#9ea8b8]체력 +%d · 시간 0칸 · 지금 %d/%d%s[/color]" % [
			int(float(PConsumables.potion_def().heal)), int(float(r.hp)), int(float(b.hp_max)),
			" · 이미 가득" if float(r.hp) >= float(b.hp_max) else ""], 12))
		prow.add_child(PUi.spacer())
		box.add_child(prow)
	into.add_child(c.panel)

func _pick_prep(r: Dictionary, id: String) -> void:
	if PConsumables.armed(r) == id:
		PConsumables.clear_select(r)
	elif not PConsumables.select(r, id):
		main.message(PConsumables.select_reason(r, id))
		return
	main.save_run()
	refresh()

func _use_potion(r: Dictionary) -> void:
	if PConsumables.use_potion(r) <= 0.0:
		main.message("회복약을 쓸 수 없습니다")
		return
	main.save_run()
	refresh()

func _merchant_card(r: Dictionary, into: VBoxContainer) -> void:
	var m = r.get("merchant", null)
	if m == null or int(m.day) != int(r.day):
		return
	var slots := PRun.time_slots()
	var disc := int(round(float(PCatalog.shop().merchantDiscount) * 100.0))
	if not PRun.merchant_open(r):
		into.add_child(PUi.rich("[b]방문 상인[/b] [color=#9ea8b8]%s부터 하루 끝까지 · 장비 1개 할인(%d%%) · 무료 휴식권 %d금(쓸 때 시간 0칸)[/color]" % [String(slots[int(m.fromSlot)]), disc, int(m.servicePrice)], 12))
		return
	var c := PUi.card("방문 상인 [color=#9ea8b8]오늘 끝까지 · 상점 화면에서 거래[/color]", PUi.CARD_ON)
	var box: VBoxContainer = c.box
	var eq_txt := "[color=#9ea8b8]장비 품절[/color]"
	if m.get("equipment", null) != null and not (m.sold as Array).has(String(m.equipment)):
		eq_txt = "%s [color=#ffd966][b]%d[/b][/color] (%d%% 할인)" % [PUi.equip_line(String(m.equipment)), PRun.equip_price_for(r, String(m.equipment), "merchant"), disc]
	box.add_child(PUi.rich("%s · 무료 휴식권 [color=#ffd966][b]%d[/b][/color] [color=#9ea8b8](구매 유료 · 쓸 때 시간 0칸)[/color]%s" % [eq_txt, int(m.servicePrice), " (판매됨)" if (m.sold as Array).has("service") else ""], 12))
	box.add_child(PUi.button("상인에게 (상점)", func(): main.show("shop"), true, 12))
	into.add_child(c.panel)

## 오늘의 행동(오른쪽 열): 미처리 레벨업 · 하루 종료(확인 창) · 저장 후 종료 · 기록. 시설·휴식은 마을 건물로 연다
func _actions_card(r: Dictionary, into: VBoxContainer) -> void:
	var c := PUi.card("오늘", PUi.CARD, 14)
	var box: VBoxContainer = c.box
	var pend := int(r.growth.pendingLevelUps)
	if pend > 0:
		var lv := PUi.button("미처리 레벨업 선택 (%d)" % pend, func(): main.offer_pending_level_ups(), true, 15)
		lv.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		box.add_child(lv)
	var nx := PRun.preview_next_day(r)
	var next_txt := ""
	if nx.has("boss"):
		next_txt = "보스 관문 (%s)" % String(PCatalog.boss_def(String(nx.boss)).name)
	else:
		var ps := []
		for p in nx.places:
			ps.append("%s%s" % [String(p.name), "(정예)" if bool(p.elite) else ""])
		next_txt = " · ".join(ps)
	var endb := PUi.button("하루 종료 → %d일차  %s내일: %s" % [int(r.day) + 1, ("(남은 %d칸 버림) · " % int(r.hours)) if int(r.hours) > 0 else "", next_txt], func(): _open_endday(), true, 14)
	endb.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	box.add_child(endb)
	var row := PUi.hbox(6)
	var sq := PUi.button("저장 후 종료", func(): main.save_quit(), true, 13)
	sq.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	row.add_child(sq)
	var lg := PUi.button("기록", func(): main.show("log"), true, 13)
	lg.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	row.add_child(lg)
	box.add_child(row)
	into.add_child(c.panel)

func _services_card(r: Dictionary, into: VBoxContainer) -> void:
	var parts := []
	var S := PCatalog.services()
	for k in r.get("services", {}):
		if int(r.services[k]) > 0:
			parts.append("[b]%s[/b] ×%d" % [String(S[String(k)].name), int(r.services[k])])
	if parts.is_empty():
		return
	into.add_child(PUi.rich("[b]보유 이용권[/b]  %s [color=#9ea8b8](개조 변경권·할인권은 상점·대장간에서 사용)[/color]" % " · ".join(parts), 12))

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

# ---------- 무한 모드 거점(PEndless, 계획서 §10) ----------
func _endless_home(r: Dictionary) -> void:
	var E := PEndless.state(r)
	var b := PBuild.derive(r)
	var g: Dictionary = r.growth
	var boss_wait: bool = String(r.phase) == "endless_boss"
	heading("%s — %d구간 · 전투 %d/%d%s" % [PGlossaryTip.term("endless", "무한 모드"), int(E.segment), int(E.fights), PEndless.fights_per_segment(), " · 구간 보스 대기" if boss_wait else ""])
	top.add_child(PUi.rich("[color=#9ea8b8]본편 완주 기록은 확정되었습니다. 무한에서 패배하면 이 회차는 끝나지만 완주·보스 기록·영구 보상은 유지됩니다. 구간마다 적 체력 +%d%%, 보스 체력 +%d%%, 하위 등급 퇴장(시험값).[/color]" % [int(round(float(PEndless.D().get("enemy_hp_step", 0.1)) * 100.0)), int(round(float(PEndless.D().get("boss_hp_step", 0.15)) * 100.0))], 12))
	var cols := two_cols(PLayout.left_ratio(bucket()))
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	var nc := PUi.card("구간 보스" if boss_wait else "다음 전투", PUi.CARD_BOSS if boss_wait else PUi.CARD, 14)
	var nbox: VBoxContainer = nc.box
	if boss_wait:
		var bid := PEndless.boss_id(r)
		nbox.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]· 체력 %d (×%.2f) · 입장 시 체력 완전 회복 · 패배하면 무한 종료[/color]" % [PGlossaryTip.esc(String(PCatalog.boss_def(bid).name)), int(round(PRun.boss_hp(r, bid))), PEndless.boss_hp_mult(r)], 13))
		var enter := PUi.button("구간 보스 입장", func(): main.start_boss(), true, 16)
		enter.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
		nbox.add_child(enter)
		default_button = enter
	else:
		var nf := PEndless.next_fight(r)
		var tier_parts := []
		var TD: Dictionary = PCatalog.world_stages().get("tiers", {})
		for k in nf.tier:
			tier_parts.append("%s %d%%" % [String((TD.get(String(k), {}) as Dictionary).get("name", String(k))), int(round(float(nf.tier[k]) * 100.0))])
		nbox.add_child(PUi.rich("[b]%s[/b] · %s [color=#9ea8b8]· 적 체력 ×%.2f · 등급 %s[/color]" % [PGlossaryTip.esc(String(nf.name)), PGlossaryTip.esc(String(nf.formationName)), float(nf.hpMult), " / ".join(tier_parts)], 13))
		var go := PUi.button("전투 시작 (%d/%d)" % [int(nf.fight), int(nf.perSegment)], func(): main.endless_fight(), true, 16)
		go.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
		nbox.add_child(go)
		default_button = go
		var can_rg := PEndless.can_regroup(r)
		nbox.add_child(PUi.button("재정비 (체력 완전 회복, 남은 %d회)" % int(E.get("regroupLeft", 0)), func(): main.endless_regroup(), can_rg, 13))
	left.add_child(nc.panel)
	var rows: Array = E.get("rows", [])
	if not rows.is_empty():
		var rc := PUi.card("구간 보스 기록", PUi.CARD_ON, 13)
		for rec in rows:
			(rc.box as VBoxContainer).add_child(PUi.rich("%d구간 %s: %s초 · Lv %d · 보스 체력 ×%.2f" % [int(rec.segment), PGlossaryTip.esc(String(PCatalog.boss_def(String(rec.bossId)).name)), str(rec.time), int(rec.level), float(rec.bossHpMult)], 12))
		left.add_child(rc.panel)
	var snap := PUi.card("현재 빌드", PUi.CARD, 13)
	var wn := []
	for w in g.weapons:
		wn.append("%s Lv%d" % [String(PCatalog.weapon(String(w.id)).name), int(w.level)])
	(snap.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]Lv %d · %s · 체력 %d/%d · 금화 %d[/color]" % [int(g.level), PGlossaryTip.esc(", ".join(wn)), int(float(r.hp)), int(float(b.hp_max)), int(r.gold)], 12))
	left.add_child(snap.panel)
	var prep := PUi.card("거점 시설 (시간 소모 없음)")
	var row := PUi.hbox(6)
	row.add_child(PUi.button("상점", func(): main.show("shop"), true, 14))
	row.add_child(PUi.button("대장간", func(): main.show("forge"), true, 14))
	row.add_child(PUi.button("장비", func(): main.show("equip"), true, 14))
	row.add_child(PUi.button("통계", func(): main.show("stats"), true, 14))
	row.add_child(PUi.button("기록", func(): main.show("log"), true, 14))
	(prep.box as VBoxContainer).add_child(row)
	(prep.box as VBoxContainer).add_child(PUi.button("무한 모드 마치기 (기록 확정)", func(): main.endless_quit(), true, 13))
	(prep.box as VBoxContainer).add_child(PUi.button("저장하고 제목으로", func(): main.save_quit(), true, 13))
	right.add_child(prep.panel)
	right.add_child(_build_summary(r))
	if _build_detail_open:
		right.add_child(PUi.equip_panel(r))
		right.add_child(PUi.build_panel(r))
		_log_card(r, right)

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
	var cols := two_cols(PLayout.left_ratio(bucket()))
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	var wn := []
	for w in g.weapons:
		wn.append("%s Lv%d" % [String(PCatalog.weapon(String(w.id)).name), int(w.level)])
	var ap := PRun.act_preview(r) # 다음 막 미리보기(계획서 §4): 관문 도전 전에 대비할 수 있게 장소·대표 적·보스 이름만
	if not cleared and not ap.is_empty():
		var pv := PUi.card("다음 막 미리보기", PUi.CARD, 13)
		if bool(ap.get("final", false)):
			(pv.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]이 관문을 넘으면 본편 완주입니다.[/color]", 12))
		else:
			var pnames := []
			for pid in ap.places:
				pnames.append(String(PRun.region(String(pid)).name))
			var enames := []
			for eid in ap.enemies:
				enames.append(String(PCatalog.enemy(String(eid)).name))
			var gate: Dictionary = ap.get("gate", {})
			var gname := String(PCatalog.boss_def(String(gate.id)).name) if not gate.is_empty() else "-"
			(pv.box as VBoxContainer).add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8](%d~%d일차)[/color] · 장소: %s · 대표 적: %s" % [PGlossaryTip.esc(String(ap.act.name)), int((ap.act.days as Array)[0]), int((ap.act.days as Array)[(ap.act.days as Array).size() - 1]), PGlossaryTip.esc("·".join(pnames)), PGlossaryTip.esc("·".join(enames))], 12))
			(pv.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]다음 관문 보스:[/color] [b]%s[/b] [color=#9ea8b8](%d일차)[/color]" % [PGlossaryTip.esc(gname), int(gate.get("day", 0))], 12))
		left.add_child(pv.panel)
	if not cleared:
		_prep_card(r, left) # 관문에서도 준비물 1개를 골라 둘 수 있다(재도전은 입장 스냅샷으로 함께 되돌아온다)
	var snap := PUi.card("입장 스냅샷", PUi.CARD, 13)
	(snap.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]Lv %d · %s · 체력 %d · 재도전 %d회%s[/color]" % [int(g.level), ", ".join(wn), int(float(b.hp_max)), int(r.get("bossRetries", 0)), " (입장 시점 상태로 복구됨: 처치 경험치·보상 중복 없음)" if int(r.get("bossRetries", 0)) > 0 else ""], 12))
	(snap.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]준비물·회복약도 입장 시점으로 복구됩니다(재도전마다 다시 사지 않아도 되고, 무한 회복도 아닙니다).[/color]", 12))
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
	enter.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
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
