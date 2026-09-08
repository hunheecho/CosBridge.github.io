class_name PBaseScreen
extends PScreen
## 거점(마을 홈). 2026-09-09 재구성 — 메인은 설명이 아니라 "지금 할 수 있는 행동"을 먼저 보여 준다.
##
## 상시로 남기는 것
##   상단 줄(날짜·막 · 남은 시간 · 체력 · 금화) · 마을 그림(상점·대장간·장비·통계/기록·휴식) ·
##   오늘의 출격 카드(장소 · 목표 한 줄 · 시간 비용 · 특별 보상 한 줄 · 큰 출발 버튼) ·
##   별도 영역의 "일반 탐험 · N칸" · 현재 빌드(아이콘).
## 상세(버튼을 눌러야 열린다)로 옮긴 것
##   편성·웨이브·적 설명·시간대 변주 설명·다른 시간대 비교·지역 설명·보스 공략·회차 특징·막 테마·내일 미리보기.
## 숨기지 않는 것
##   시간 비용 · 위험 조건 · 강적 출현 · 일반 탐험에는 임무 보상·사건·이용권이 없다는 사실.
## 상황 변화
##   완료한 출격은 한 줄로 접는다. 시간이 없으면 "오늘 활동을 마쳤습니다"와 큰 "다음 날로"를 왼쪽 맨 위에 두고,
##   같은 버튼을 오른쪽에 겹쳐 두지 않는다. 상점·대장간·장비·휴식 버튼은 그대로 남는다(규칙이 막을 때만 비활성).
## 휴식은 확인 창을 거친다: 소모(시간 1칸 또는 휴식권 1장) · 회복 전후 체력 · 취소하면 아무 변화 없음.
##
## phase == boss_prep 이면 최종 준비(보스 카드 전체 정보·입장). 모든 수치는 PRun/PSortie/PBuild가 준 값이다.

const RISK_DESC := { "reinforce": "지원병 총량 ×1.5", "escort": "첫 웨이브에 정예 1 추가", "hazard": "주기적 바닥 붕괴(안전 통로 있음)" }
const BOSS_DESC := {
	"boss": "숲과 늑대 무리를 지배하는 거대한 늑대. 목과 등에 부러진 나뭇가지 같은 검은 가시가 돋았고, 한쪽 송곳니가 부러졌다.",
	"guardian": "봉인을 지키는 돌 갑옷의 거인. 느리지만 한 번의 휩쓸기가 무겁고, 봉인 장치가 바닥을 위험하게 만든다.",
	"eater": "예언을 삼키는 시간의 포식자. 당신이 지나온 자리를 표식으로 찍고, 두 줄의 직선과 광역으로 공간을 좁힌다.",
}

var _detail_open: Dictionary = {}   # 출격 카드 id → 상세를 펼쳤는가
var _build_detail_open := false     # 오른쪽 빌드 요약의 "상세 설명"
var _info_open := false             # 이번 회차 정보(특징·막 테마·내일)
var _boss_open := false             # 보스 상세
var village: PVillageMap = null     # 마을 그림(refresh마다 새로 만든다)
var _confirm: Control = null        # 확인 창 층. 공용(PScreen._modal)을 가리키는 옛 이름 — tests/input_tests.gd가 이 이름을 쓴다

func _build() -> void:
	_confirm = _modal

func on_enter() -> void:
	_boss_open = false
	_info_open = false
	super.on_enter()

func refresh() -> void:
	clear_all()
	close_confirm()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
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
	# 왼쪽: 마을(건물을 눌러 연다) → (시간이 없으면 다음 날로) → 오늘의 출격 → 일반 탐험 → 준비물
	village = PVillageMap.new()
	village.custom_minimum_size = Vector2(0, PLayout.village_height(bk))
	village.picked.connect(_on_village_pick)
	village.set_state("rest", PRun.can_rest(r), _rest_label(r))
	left.add_child(village)
	var out_of_time: bool = int(r.hours) <= 0
	var first_btn: Button = null
	if out_of_time:
		first_btn = _day_over_card(r, left)
	left.add_child(PUi.rich("[b]오늘의 출격[/b]", 16))
	var done: Array = []
	var row := PUi.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var shown := 0
	for c in PSortie.cards_for(r):
		if bool(c.done):
			done.append(c)
			continue
		var res := _place_card(r, c)
		(res.panel as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(res.panel as Control).size_flags_stretch_ratio = 1.0
		row.add_child(res.panel)
		shown += 1
		if first_btn == null and res.button != null and not (res.button as Button).disabled:
			first_btn = res.button
	if shown > 0:
		left.add_child(row)
	elif done.is_empty():
		left.add_child(PUi.rich("[color=#6a7078]오늘 나갈 장소가 없습니다.[/color]", 13))
	if not done.is_empty():
		left.add_child(_done_line(done))
	var rep := _repeat_card(r, left)
	if first_btn == null and rep != null and not rep.disabled:
		first_btn = rep
	_prep_card(r, left)
	_merchant_card(r, left)
	_services_card(r, left)
	# 오른쪽: 오늘의 행동 → 보스 한 줄 → 현재 빌드
	# 행동을 맨 위에 둔다 — 720p에서 '하루 종료'가 스크롤 아래로 밀리지 않게(2026-09-09 캡처로 확인)
	_actions_card(r, right, out_of_time)
	right.add_child(_boss_card(r, false))
	right.add_child(_build_summary(r))
	if _build_detail_open:
		right.add_child(PUi.equip_panel(r))
		right.add_child(PUi.build_panel(r))
		_stats_compact(r, right)
		_log_card(r, right)
	if _info_open:
		right.add_child(_info_card(r))
	default_button = first_btn

## 마을 건물 → 화면(같은 main 함수). 휴식만 확인 창을 거친다
func _on_village_pick(id: String) -> void:
	match id:
		"forge": main.show("forge")
		"shop": main.show("shop")
		"equip": main.show("equip")
		"stats": main.show("stats")
		"rest": _open_rest()

func _rest_label(r: Dictionary) -> String:
	if PRun.has_service(r, "free_rest"):
		return "휴식 (%s)" % PUi.rest_ticket_name()
	return "휴식 (%d칸)" % int(PCatalog.config().REST_HOURS)

# ---------- 휴식 확인 창 ----------
## 결정에 필요한 것만: 무엇을 소모하는가 · 체력이 얼마에서 얼마가 되는가 · 어느 시간대로 넘어가는가.
## 취소하면 아무것도 바뀌지 않는다. 확정은 한 번만 실행된다(PScreen.open_confirm).
func _open_rest() -> void:
	var r := run()
	if not PRun.can_rest(r):
		main.message("지금은 쉴 수 없습니다 (남은 시간 %d칸)" % int(r.hours))
		return
	open_confirm("휴식할까요?", _rest_body.bind(r), [{ "text": "휴식한다", "cb": func(): main.rest() }])

func _rest_body(box: VBoxContainer, r: Dictionary) -> void:
	var cost := int(PCatalog.config().REST_HOURS)
	var hp0 := int(float(r.hp))
	var hp1 := int(float(PBuild.derive(r).hp_max))
	if PRun.has_service(r, "free_rest"):
		PUi.kv(box, "소모", "[b]%s 1장[/b] [color=#9ea8b8](%s · 사는 값 %d금)[/color]" % [PUi.rest_ticket_name(), PUi.rest_ticket_note(), PRun.merchant_service_price("free_rest")], 15)
	else:
		PUi.kv(box, "소모", "[b]시간 %d칸[/b] [color=#9ea8b8](남은 %d칸 → %d칸)[/color]" % [cost, int(r.hours), int(r.hours) - cost], 15)
	PUi.kv(box, "체력", "[b]%d → %d[/b]%s" % [hp0, hp1, " [color=#9ea8b8](이미 가득 — 시간만 넘깁니다)[/color]" if hp0 >= hp1 else ""], 15)
	PUi.kv(box, "시간대", "[b]%s[/b]" % PRun.next_slot_name(r), 15)
	box.add_child(PUi.rich("[color=#9ea8b8]취소하면 아무것도 바뀌지 않습니다.[/color]", 12))

# ---------- 시간이 없을 때 ----------
## 오늘 할 수 있는 일이 끝났음을 먼저 말하고, 다음 날로 가는 큰 버튼 하나를 둔다.
## 상점·대장간·장비는 시간을 쓰지 않으므로 그대로 쓸 수 있고, 휴식권이 있으면 휴식도 가능하다(마을 버튼을 지우지 않는다).
func _day_over_card(r: Dictionary, into: VBoxContainer) -> Button:
	var c := PUi.card("오늘 활동을 마쳤습니다", PUi.CARD_ON, 19)
	var box: VBoxContainer = c.box
	var more := "상점·대장간·장비는 시간 없이 계속 쓸 수 있습니다."
	if PRun.has_service(r, "free_rest"):
		more += " %s이 있어 지금도 쉴 수 있습니다." % PUi.rest_ticket_name()
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % more, 13))
	var b := PUi.button("다음 날로 (%d일차)" % (int(r.day) + 1), func(): _open_endday(), true, 19)
	b.custom_minimum_size = Vector2(0, PLayout.primary_button_height() + 8.0)
	box.add_child(b)
	into.add_child(c.panel)
	return b

# ---------- 오늘의 출격 카드 ----------
## 장소 · 목표 한 줄 · 시간 비용 · 특별 보상 한 줄 · 큰 출발 버튼. 그 밖은 전부 '상세 보기'로 접는다.
func _place_card(r: Dictionary, c: Dictionary) -> Dictionary:
	var rid := String(c.regionId)
	var reg := PRun.region(rid)
	var can := PSortie.can_start(r, c)
	var M := PCatalog.mission_rules()
	var obj := String(c.objective)
	var O: Dictionary = PCatalog.objectives().get(obj, {}) if obj != "clear" else {}
	var notice := PSortie.elite_notice(r, c) # 강적 사전 표시(규칙은 PSortie가 정한다 — 화면은 그리기만)
	var elite: bool = bool(notice.present)
	var has_risk: bool = c.get("risk", null) != null
	var card := PUi.card("", PUi.CARD if can else PUi.CARD_OFF)
	var box: VBoxContainer = card.box
	box.add_child(PUi.rich("[b]%s[/b]  [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(reg.name)), (PGlossaryTip.term("mission", String(O.name)) if not O.is_empty() else "전멸")], 17))
	# 결정 전에 필요한 불이익은 그대로 남긴다: 시간 비용 · 강적 · 위험 조건
	var cost_line := "[b]시간 %d칸[/b]" % int(c.timeCost)
	if elite:
		cost_line += "  [color=#ffb066]%s[/color]" % PGlossaryTip.term("elite", "강적 출현")
	if has_risk:
		cost_line += "  [color=#ff8c73]%s[/color]" % PGlossaryTip.esc(String(M.riskText[String(c.risk)]))
	box.add_child(PUi.rich(cost_line, 14))
	box.add_child(PUi.rich("[color=#9ea8b8]보상[/color] [b]%s[/b]" % _reward_line(r, c, O), 14))
	var cid := String(c.id)
	var why := ""
	if String(r.phase) != "prep":
		why = "출격 불가"
	elif PRun.is_boss_day(r):
		why = "관문 날"
	elif int(r.hours) < int(c.timeCost):
		why = "시간 부족 (%d칸 필요)" % int(c.timeCost)
	var btn := PUi.button(("출격 (%d칸)" % int(c.timeCost)) if can else why, func(): main.start_sortie_card(cid), can, 18)
	btn.custom_minimum_size = Vector2(0, PLayout.primary_button_height() + 4.0) # 주 행동: 큰 버튼(터치 대상)
	box.add_child(btn)
	# 상세는 눌러야 열린다(마우스만 올려서는 열리지 않는다). 펼치기 전에는 트리에 만들지도 않는다
	var opened: bool = bool(_detail_open.get(cid, false))
	var toggle := PUi.button("상세 닫기 ▼" if opened else "상세 보기 ▶", func(): _toggle_detail(cid), true, 12)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(toggle)
	if opened:
		box.add_child(_place_detail(r, c, O, notice))
	return { "panel": card.panel, "button": btn }

## 특별 보상 한 줄: 임무 보상이 있으면 그것, 없으면 실제로 받는 금화 범위(위험·시간대 배율 반영)
func _reward_line(r: Dictionary, c: Dictionary, O: Dictionary) -> String:
	if not O.is_empty():
		return PGlossaryTip.esc(String(PSortie.steer_state(r, c).text))
	var rid := String(c.regionId)
	var reg := PRun.region(rid)
	var v: Dictionary = PRun.slot_variant(rid, PRun.slot_index(r)) if int(r.hours) > 0 else {}
	var gm := (PRun.risk_reward_mult(r) if c.get("risk", null) != null else 1.0) * (float(v.goldMult) if v.has("goldMult") else 1.0)
	return "금화 %d~%d" % [int(round(float(reg.reward.gold[0]) * gm)), int(round(float(reg.reward.gold[1]) * gm))]

## 상세: 소제목으로 나눠 적는다(한 문단으로 이어 붙이지 않는다)
func _place_detail(r: Dictionary, c: Dictionary, O: Dictionary, notice: Dictionary) -> Control:
	var rid := String(c.regionId)
	var reg := PRun.region(rid)
	var M := PCatalog.mission_rules()
	var slots := PRun.time_slots()
	var slot := PRun.slot_index(r)
	var v: Dictionary = PRun.slot_variant(rid, slot) if int(r.hours) > 0 else {}
	var hpm := PRun.hp_mult_for(r, rid, false)
	var waves := PRun.encounter_waves(rid, false, r, { "formationId": String(c.get("formationId", "base")), "variant": (v if not v.is_empty() else null) })
	var d := PUi.vbox(3)
	d.add_child(PUi.rich("[b]장소[/b]", 13))
	d.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(O.desc) if not O.is_empty() else String(reg.desc)), 12))
	d.add_child(PUi.rich("[b]나오는 적[/b] [color=#9ea8b8]%d웨이브 · 전멸(웨이브·대기 포함)%s[/color]" % [waves.size(), (" · 체력 ×%s" % PUi.fmt(float(hpm.normal))) if float(hpm.normal) != 1.0 else ""], 13))
	for eid in c.enemies:
		var ed := PCatalog.enemy(String(eid))
		d.add_child(PUi.rich("  [b]%s[/b] [color=#9ea8b8]%s — %s[/color]" % [PGlossaryTip.esc(String(ed.name)), PGlossaryTip.esc(String(ed.get("role", ""))), PGlossaryTip.esc(String(ed.get("readme", "")))], 12))
	if bool(notice.present):
		d.add_child(PUi.rich("[b]강적[/b] [color=#ffb066]%s[/color] [color=#9ea8b8]· 보상 %s[/color]" % [PGlossaryTip.esc(" · ".join(notice.names)), PGlossaryTip.esc(String(notice.reward))], 13))
	if c.get("risk", null) != null:
		d.add_child(PUi.rich("[b]위험 조건[/b]", 13))
		d.add_child(PUi.rich("[color=#ff8c73]%s[/color] [color=#9ea8b8]— %s · 금화 ×%s[/color]" % [PGlossaryTip.esc(String(M.riskText[String(c.risk)])), String(RISK_DESC.get(String(c.risk), "")), str(PRun.risk_reward_mult(r))], 12))
	d.add_child(PUi.rich("[b]편성[/b]", 13))
	var fdesc := String(c.get("formationDesc", ""))
	d.add_child(PUi.rich("[color=#9ea8b8]%s%s[/color]" % [PGlossaryTip.esc(String(c.get("formationName", "기본"))), (" — " + PGlossaryTip.esc(fdesc)) if fdesc != "" else ""], 12))
	d.add_child(PUi.rich("[b]출발 시간대[/b]", 13))
	if not v.is_empty():
		d.add_child(PUi.rich("[color=#ffe066]%s %s[/color] [color=#9ea8b8]%s[/color]" % [String(slots[mini(slot, slots.size() - 1)]), PGlossaryTip.esc(String(v.name)), PGlossaryTip.esc(String(v.desc))], 12))
	else:
		d.add_child(PUi.rich("[color=#9ea8b8]%s 출발: 기본 편성[/color]" % String(slots[mini(slot, slots.size() - 1)]), 12))
	var others := [] # 실제 출발 시간대 기준(Q4: 비용 2 장소의 저녁 변주는 오후로 이동한 슬롯으로 표시)
	for ov in PRun.slot_variants_list(rid):
		if int(ov.slot) != slot:
			others.append("%s %s" % [String(slots[int(ov.slot)]), String(ov.name)])
	if others.size() > 0:
		d.add_child(PUi.rich("[color=#6a7078]다른 시간대: %s[/color]" % PGlossaryTip.esc(" · ".join(others)), 12))
	d.add_child(PUi.rich("[color=#6a7078]편성·사건·보상은 출발하는 순간의 시간대로 확정됩니다.[/color]", 11))
	d.add_child(PUi.rich("[b]경험치[/b] [color=#9ea8b8]처치 즉시 · 지역 +%s[/color]" % str(PRun.region_bonus_xp(r, rid, false)), 13))
	d.add_child(PUi.rich("[b]승리 뒤[/b] [color=#9ea8b8]%s를 한 번 더 고를 수 있습니다(시간 1칸).[/color]" % PGlossaryTip.term("deep", "더 깊이"), 13))
	if int(c.attempts) > 0:
		d.add_child(PUi.rich("[color=#6a7078]오늘 시도 %d회[/color]" % int(c.attempts), 11))
	return d

func _toggle_detail(cid: String) -> void:
	_detail_open[cid] = not bool(_detail_open.get(cid, false))
	refresh()

## 오늘 끝낸 출격은 한 줄로 접는다(다시 나가려면 아래 '일반 탐험')
func _done_line(done: Array) -> Control:
	var names := []
	for c in done:
		var extra := int(c.get("repeatAttempts", 0))
		names.append("%s%s" % [String(PRun.region(String(c.regionId)).name), (" (+%s %d)" % [PPacing.repeat_label(), extra]) if extra > 0 else ""])
	var card := PUi.card("", PUi.CARD_OFF)
	(card.box as VBoxContainer).add_child(PUi.rich("[color=#9ea8b8]오늘 완료[/color]  %s" % PGlossaryTip.esc(" · ".join(names)), 13))
	return card.panel

# ---------- 일반 탐험(별도 영역) ----------
## 정본은 data/pacing.json repeat_sortie. 완료 카드 밑의 보충 설명이 아니라 자기 영역을 가진다(사용자 지시 2026-09-09).
## 카드·시간·가능 판정은 공통 규칙(PSortie.repeat_cards / PSortie.can_start)이 준 값이며 여기서 새 규칙을 만들지 않는다.
## 임무 보상·사건·이용권이 없다는 불이익은 접지 않고 그대로 적는다.
func _repeat_card(r: Dictionary, into: VBoxContainer) -> Button:
	if not PPacing.repeat_enabled():
		return null
	var rname := PPacing.repeat_label()
	var cost := PPacing.repeat_cost()
	var c := PUi.card("%s [color=#9ea8b8]· %d칸[/color]" % [PGlossaryTip.esc(rname), cost], PUi.CARD, 16)
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[color=#9ea8b8]오늘 끝낸 장소로 한 번 더. 전리품·경험치만 — 임무 보상·사건·이용권은 없습니다.[/color]", 12))
	var cards := PSortie.repeat_cards(r)
	var first: Button = null
	if cards.is_empty():
		var any_done := false
		for c0 in PSortie.cards_for(r):
			if bool(c0.done):
				any_done = true
		var why := "시간 부족 (%d칸 필요)" % cost
		if PRun.is_boss_day(r):
			why = "관문 날에는 없습니다"
		elif not any_done:
			why = "출격을 한 번 마치면 열립니다"
		var off := PUi.button("%s · %s" % [rname, why], Callable(), false, 15)
		off.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
		box.add_child(off)
		first = off
	else:
		var row := PUi.hbox(8)
		for x in cards:
			var rc: Dictionary = x
			var again_id := String(rc.id)
			var can := PSortie.can_start(r, rc)
			var b := PUi.button("%s · %s (%d칸)" % [rname, String(PRun.region(String(rc.regionId)).name), cost], func(): main.start_sortie_card(again_id), can, 16)
			b.custom_minimum_size = Vector2(0, PLayout.primary_button_height())
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
			if first == null and can:
				first = b
		box.add_child(row)
	into.add_child(c.panel)
	return first

# ---------- 현재 빌드(아이콘) ----------
## 주무기·보조 · 개조 · 수동(Space/Q/E) · 공용 증강·패시브 · 장비를 모두 아이콘으로 둔다.
## 아이콘을 누르면 짧은 정보와 관련 행동이 열리고, 긴 조건·수식·예외는 그 안의 '상세 설명' 버튼으로만 열린다.
func _build_summary(r: Dictionary) -> Control:
	var g: Dictionary = r.growth
	var pend := int(g.pendingLevelUps)
	var c := PUi.card("현재 빌드 [color=#9ea8b8]Lv %d[/color]%s" % [int(g.level), (" [color=#ff8c73]미처리 레벨업 %d[/color]" % pend) if pend > 0 else ""], PUi.CARD, 15)
	var box: VBoxContainer = c.box
	var pick := Callable(self, "_icon_info")
	box.add_child(PUi.build_icon_row(r, 44.0, 26.0, main.take_pick_highlight(), pick))
	box.add_child(PUi.manual_icon_row(r, 32.0, pick))
	box.add_child(PUi.common_icon_row(r, 24.0, pick))
	box.add_child(PUi.equip_icon_row(r, 32.0, pick))
	# 이름은 아이콘 창의 '상세 설명'과 겹치지 않게 둔다(같은 화면에서 서로 다른 것을 연다)
	var toggle := PUi.button(("전체 빌드 닫기 ▼" if _build_detail_open else "전체 빌드 ▶ (장비·성장·통계·기록)"), func(): _toggle_build_detail(), true, 13)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.custom_minimum_size = Vector2(0, PLayout.button_min_height())
	box.add_child(toggle)
	return c.panel

func _toggle_build_detail() -> void:
	_build_detail_open = not _build_detail_open
	refresh()

# ---------- 아이콘 한 칸의 짧은 정보 + 관련 행동 ----------
## detail=false: 이름·핵심 수치·바로 할 수 있는 행동만. detail=true: 소제목으로 나눈 긴 설명.
## PC 클릭과 터치 탭이 같은 경로다(PUi.icon_pick이 아이콘 위에 버튼을 얹는다).
func _icon_info(kind: String, id: String, detail: bool = false) -> void:
	var r := run()
	if r.is_empty():
		return
	match kind:
		"weapon": _info_weapon(r, id, detail)
		"mod": _info_mod(r, id, detail)
		"manual": _info_manual(r, id, detail)
		"common": _info_aug(r, "common", id, detail)
		"passive": _info_aug(r, "passive", id, detail)
		"equip": _info_equip(r, id, detail)

## 한 줄짜리 안내만 담는 확인 창 내용(빈 칸을 눌렀을 때)
func _note_body(box: VBoxContainer, text: String) -> void:
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(text), 14))

func _detail_action(kind: String, id: String, detail: bool) -> Array:
	if detail:
		return []
	return [{ "text": "상세 설명", "cb": func(): _icon_info(kind, id, true) }]

func _info_weapon(r: Dictionary, wid: String, detail: bool) -> void:
	var acts := _detail_action("weapon", wid, detail)
	acts.append({ "text": "대장간에서 강화·교체", "cb": func(): main.show("forge") })
	open_confirm(String(PCatalog.weapon(wid).name), _weapon_body.bind(r, wid, detail), acts, "닫기 (Esc)")

func _weapon_body(box: VBoxContainer, r: Dictionary, wid: String, detail: bool) -> void:
	var d := PCatalog.weapon(wid)
	var ws: Dictionary = {}
	for w in PBuild.derive(r).weapons:
		if String(w.id) == wid:
			ws = w
	if ws.is_empty():
		box.add_child(PUi.rich("[color=#6a7078]지금 빌드에 없습니다.[/color]", 14))
		return
	PUi.kv(box, "Lv%d 공격" % int(ws.level), "[b]%s[/b]" % PUi.weapon_stats_text(ws), 15)
	var mods: Array = ws.get("mods", [])
	var names := []
	for m in mods:
		names.append(String(d.mods[String(m)].name))
	PUi.kv(box, "붙은 개조", "[b]%s[/b]" % (", ".join(names) if names.size() > 0 else "없음"), 14)
	if not detail:
		return
	box.add_child(PUi.rich("[b]기본값[/b] [color=#9ea8b8]성장·강화 전[/color]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PUi.weapon_base_text(d.base), 13))
	box.add_child(PUi.rich("[b]붙은 개조[/b]", 14))
	if mods.is_empty():
		box.add_child(PUi.rich("[color=#6a7078]아직 없음[/color]", 13))
	for m in mods:
		var mid := String(m)
		box.add_child(PUi.rich("· [b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(d.mods[mid].name)), PGlossaryTip.esc(String(d.mods[mid].get("desc", "")))], 13))
	box.add_child(PUi.rich("[b]아직 붙지 않은 개조 후보[/b]", 14))
	var rest := 0
	for mid2 in d.mods:
		if mods.has(String(mid2)) or not bool(d.mods[mid2].get("impl", false)):
			continue
		rest += 1
		box.add_child(PUi.rich("[color=#9ea8b8]· %s %s[/color]" % [PGlossaryTip.esc(String(d.mods[mid2].name)), PGlossaryTip.esc(String(d.mods[mid2].get("desc", "")))], 13))
	if rest == 0:
		box.add_child(PUi.rich("[color=#6a7078]없음[/color]", 13))

func _info_mod(r: Dictionary, pair: String, detail: bool) -> void:
	var parts := pair.split(":")
	var wid := String(parts[0])
	var mid := String(parts[1]) if parts.size() > 1 else ""
	var md: Dictionary = PCatalog.weapon(wid).mods.get(mid, {})
	var acts := _detail_action("mod", pair, detail)
	acts.append({ "text": "대장간에서 개조 변경", "cb": func(): main.show("forge") })
	open_confirm(String(md.get("name", mid)), _mod_body.bind(wid, mid, detail), acts, "닫기 (Esc)")

func _mod_body(box: VBoxContainer, wid: String, mid: String, detail: bool) -> void:
	var wd := PCatalog.weapon(wid)
	var md: Dictionary = wd.mods.get(mid, {})
	PUi.kv(box, "붙은 기술", "[b]%s[/b]" % PGlossaryTip.esc(String(wd.name)), 15)
	box.add_child(PUi.rich(PGlossaryTip.esc(String(md.get("desc", ""))), 14))
	if not detail:
		return
	box.add_child(PUi.rich("[b]같은 기술의 다른 개조[/b]", 14))
	for other in wd.mods:
		if String(other) == mid or not bool(wd.mods[other].get("impl", false)):
			continue
		box.add_child(PUi.rich("[color=#9ea8b8]· %s %s[/color]" % [PGlossaryTip.esc(String(wd.mods[other].name)), PGlossaryTip.esc(String(wd.mods[other].get("desc", "")))], 13))
	box.add_child(PUi.rich("[b]바꾸는 방법[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]대장간의 '개조 변경'에서 같은 기술의 다른 후보 3택으로 바꿉니다. 후보가 없으면 아무것도 차감되지 않습니다.[/color]", 13))

func _info_manual(r: Dictionary, slot: String, detail: bool) -> void:
	if slot == "dodge":
		open_confirm("회피 (Space)", _dodge_body.bind(detail), _detail_action("manual", slot, detail), "닫기 (Esc)")
		return
	var sk = r.growth.skills.get(slot)
	if sk == null:
		open_confirm("E — 비어 있음", _note_body.bind("아직 E 기술이 없습니다. 상점의 기술 재고나 성장 3택에서 얻습니다."), [{ "text": "상점 열기", "cb": func(): main.show("shop") }], "닫기 (Esc)")
		return
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	var acts := _detail_action("manual", slot, detail)
	acts.append({ "text": "대장간에서 변경", "cb": func(): main.show("forge") })
	open_confirm("%s (%s)" % [String(d.name), String(d.key)], _skill_body.bind(r, slot, detail), acts, "닫기 (Esc)")

func _dodge_body(box: VBoxContainer, detail: bool) -> void:
	box.add_child(PUi.rich("짧게 굴러 피합니다. [color=#9ea8b8]무적은 구르는 동안에만입니다.[/color]", 14))
	if detail:
		box.add_child(PUi.rich("[b]재사용[/b]", 14))
		box.add_child(PUi.rich("[color=#9ea8b8]재사용 시간은 설정의 회피 방식에 따라 다릅니다. 전투 화면의 Space 칸이 남은 초를 보여 줍니다.[/color]", 13))

func _skill_body(box: VBoxContainer, r: Dictionary, slot: String, detail: bool) -> void:
	var b := PBuild.derive(r)
	var sk = r.growth.skills.get(slot)
	var d: Dictionary = PCatalog.skills()[String(sk.id)]
	PUi.kv(box, "Lv%d 재사용" % int(sk.level), "[b]%s초[/b]" % PUi.fmt(PBuildDetail.cd_of_build(b, slot)), 15)
	if sk.get("variant", null) != null:
		PUi.kv(box, "변형", "[b]%s[/b]" % PGlossaryTip.esc(String(d.variants[String(sk.variant)].name)), 14)
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.get("desc", ""))), 14))
	if not detail:
		return
	box.add_child(PUi.rich("[b]레벨별 기본 재사용[/b]", 14))
	var cds := []
	for x in d.cooldown:
		cds.append("%s초" % PUi.fmt(float(x)))
	box.add_child(PUi.rich("[color=#9ea8b8]%s — 여기에 빌드의 재사용 감소가 곱해집니다.[/color]" % " / ".join(cds), 13))
	var vs: Dictionary = d.get("variants", {})
	if not vs.is_empty():
		box.add_child(PUi.rich("[b]변형 후보[/b]", 14))
		for v in vs:
			box.add_child(PUi.rich("[color=#9ea8b8]· %s %s[/color]" % [PGlossaryTip.esc(String(vs[v].name)), PGlossaryTip.esc(String(vs[v].get("desc", "")))], 13))

func _info_aug(r: Dictionary, kind: String, id: String, detail: bool) -> void:
	var d: Dictionary = PCatalog.commons()[id] if kind == "common" else PCatalog.passives()[id]
	open_confirm(String(d.name), _aug_body.bind(r, kind, id, detail), _detail_action(kind, id, detail), "닫기 (Esc)")

func _aug_body(box: VBoxContainer, r: Dictionary, kind: String, id: String, detail: bool) -> void:
	var g: Dictionary = r.growth
	var d: Dictionary = PCatalog.commons()[id] if kind == "common" else PCatalog.passives()[id]
	var have: int = int(g.commons.get(id, 0)) if kind == "common" else int(g.passives.get(id, 0))
	PUi.kv(box, "보유", "[b]%d/%d[/b]" % [have, int(d.max)], 15)
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.get("desc", ""))), 14))
	if not detail:
		return
	box.add_child(PUi.rich("[b]적용 대상[/b]", 14))
	if kind == "common":
		var wn := []
		for w in PBuild.derive(r).weapons:
			wn.append(String(w.name))
		box.add_child(PUi.rich("[color=#9ea8b8]모든 자동기술: %s[/color]" % PGlossaryTip.esc(", ".join(wn) if wn.size() > 0 else "없음"), 13))
	else:
		box.add_child(PUi.rich("[color=#9ea8b8]빌드 전체(체력·이동·재사용 등 파생 수치)에 붙습니다.[/color]", 13))
	box.add_child(PUi.rich("[b]더 얻는 방법[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]레벨업 3택에서 같은 항목이 다시 나오면 단계가 올라갑니다(상한 %d).[/color]" % int(d.max), 13))

func _info_equip(r: Dictionary, slot: String, detail: bool) -> void:
	var id = r.equipment.get(slot, null)
	if id == null:
		open_confirm("%s — 비어 있음" % PUi.slot_name(slot), _note_body.bind("이 칸에 낄 장비가 없습니다. 상점에서 사거나 가방에서 장착합니다."), [{ "text": "장비 화면", "cb": func(): main.show("equip") }, { "text": "상점 열기", "cb": func(): main.show("shop") }], "닫기 (Esc)")
		return
	var eid := String(id)
	var acts := _detail_action("equip", slot, detail)
	acts.append({ "text": "해제 (가방으로)", "cb": func(): main.unequip_item(slot) })
	acts.append({ "text": "판매 (+%d금)" % PRun.sell_price(eid), "cb": func(): open_sell_confirm(eid) })
	acts.append({ "text": "장비 화면", "cb": func(): main.show("equip") })
	open_confirm(String(PCatalog.equipment_def(eid).name), _equip_body.bind(r, slot, eid, detail), acts, "닫기 (Esc)")

func _equip_body(box: VBoxContainer, r: Dictionary, slot: String, eid: String, detail: bool) -> void:
	var d: Dictionary = PCatalog.equipment_def(eid)
	PUi.kv(box, "부위", "[b]%s[/b]" % PUi.slot_name(slot), 15)
	box.add_child(PUi.rich(PGlossaryTip.esc(String(d.short)), 14))
	var dup: Dictionary = r.duplicate(true)
	PRun.unequip_item(dup, slot)
	PUi.kv(box, "해제하면", PUi.diff_text(PBuild.derive(r), PBuild.derive(dup)), 13)
	if not detail:
		return
	box.add_child(PUi.rich("[b]자세한 효과[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(String(d.desc)), 13))
	box.add_child(PUi.rich("[b]되팔 때[/b]", 14))
	box.add_child(PUi.rich("[color=#9ea8b8]%d금 · 장착 중이면 해제한 뒤 팝니다.[/color]" % PRun.sell_price(eid), 13))

# ---------- 출격 준비물 ----------
## 가진 준비물 중 1개를 골라 두면 다음 전투 입장 때 저절로 쓰인다. 해제·교체는 소모가 아니다.
## 회복약도 여기서 마신다(거점 전용, 시간 0칸). 설명은 한 줄로 줄이고 나머지는 상점 카드에 있다.
func _prep_card(r: Dictionary, into: VBoxContainer) -> void:
	var bag := PConsumables.bag(r)
	var armed := PConsumables.armed(r)
	var have_any: bool = PConsumables.prep_count(r) > 0
	if not have_any and PConsumables.potion_count(r) <= 0:
		return
	var c := PUi.card("출격 준비물 [color=#9ea8b8]1개 · 다음 전투에서 소모[/color]", PUi.CARD_ON if armed != "" else PUi.CARD, 15)
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
			row.add_child(PUi.button("%s %s ×%d" % ["●" if on else "○", PConsumables.name_of(id), PConsumables.count(r, id)], func(): _pick_prep(r, id), true, 13))
		row.add_child(PUi.spacer())
		box.add_child(row)
		if armed != "":
			box.add_child(PUi.rich("[color=#7fd6a0]장착[/color] [b]%s[/b] — %s" % [PConsumables.name_of(armed), PGlossaryTip.esc(PConsumables.effect_line(armed))], 13))
			box.add_child(PUi.button("해제 (소모 없음)", func(): PConsumables.clear_select(r); main.save_run(); refresh(), true, 12))
	if PConsumables.potion_count(r) > 0:
		var b := PBuild.derive(r)
		var prow := PUi.hbox(6)
		prow.add_child(PUi.button("회복약 사용 ×%d" % PConsumables.potion_count(r), func(): _use_potion(r), PConsumables.can_use_potion(r), 13))
		prow.add_child(PUi.rich("[color=#9ea8b8]체력 +%d · 시간 0칸 · 지금 %d/%d[/color]" % [int(float(PConsumables.potion_def().heal)), int(float(r.hp)), int(float(b.hp_max))], 12))
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

## 방문 상인: 무엇을 살 수 있는지 한 줄. 일정 비교 문장은 두지 않는다
func _merchant_card(r: Dictionary, into: VBoxContainer) -> void:
	var m = r.get("merchant", null)
	if m == null or int(m.day) != int(r.day):
		return
	var slots := PRun.time_slots()
	if not PRun.merchant_open(r):
		into.add_child(PUi.rich("[color=#9ea8b8]방문 상인 %s부터[/color]" % String(slots[int(m.fromSlot)]), 12))
		return
	var c := PUi.card("방문 상인 [color=#9ea8b8]오늘 끝까지[/color]", PUi.CARD_ON, 15)
	var box: VBoxContainer = c.box
	var parts := []
	if m.get("equipment", null) != null and not (m.sold as Array).has(String(m.equipment)):
		parts.append("장비 1개 할인 %d%%" % int(round(float(PCatalog.shop().merchantDiscount) * 100.0)))
	if not (m.sold as Array).has("service"):
		parts.append("%s %d금 (%s)" % [PUi.rest_ticket_name(), int(m.servicePrice), PUi.rest_ticket_note()])
	box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % (PGlossaryTip.esc(" · ".join(parts)) if parts.size() > 0 else "품절"), 12))
	box.add_child(PUi.button("상인에게 (상점)", func(): main.show("shop"), true, 13))
	into.add_child(c.panel)

## 오늘의 행동: 미처리 레벨업 · 하루 종료 · 저장 후 종료 · 기록 · 이번 회차 정보(접힘)
func _actions_card(r: Dictionary, into: VBoxContainer, out_of_time: bool) -> void:
	var c := PUi.card("오늘", PUi.CARD, 14)
	var box: VBoxContainer = c.box
	var pend := int(r.growth.pendingLevelUps)
	if pend > 0:
		var lv := PUi.button("미처리 레벨업 선택 (%d)" % pend, func(): main.offer_pending_level_ups(), true, 15)
		lv.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		box.add_child(lv)
	if not out_of_time: # 시간이 없을 때는 왼쪽 '다음 날로' 하나만 둔다(같은 버튼을 두 곳에 흩어놓지 않는다)
		var endb := PUi.button("하루 종료 → %d일차 (남은 %d칸 버림)" % [int(r.day) + 1, int(r.hours)], func(): _open_endday(), true, 14)
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
	box.add_child(PUi.button("이번 회차 정보 닫기 ▼" if _info_open else "이번 회차 정보 ▶", func(): _info_open = not _info_open; refresh(), true, 12))
	into.add_child(c.panel)

## 이번 회차 정보(접힘): 회차 특징 · 막 테마 · 내일 미리보기. 메인 상시 줄에서 내린 것들이다
func _info_card(r: Dictionary) -> Control:
	var c := PUi.card("이번 회차", PUi.CARD, 14)
	var box: VBoxContainer = c.box
	var wf := PRun.world_feature(r)
	if not wf.is_empty():
		box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.esc(String(wf.name)), PGlossaryTip.esc(String(wf.line))], 13))
	var cth := PRun.current_theme(r)
	if not cth.is_empty():
		box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s · 보스 %s[/color]" % [PGlossaryTip.esc(String(cth.name)), PGlossaryTip.esc(String(cth.line)), PGlossaryTip.esc(String(PCatalog.boss_def(String(cth.boss)).name))], 13))
	box.add_child(PUi.rich("[b]내일[/b]", 13))
	var nx := PRun.preview_next_day(r)
	if nx.has("boss"):
		box.add_child(PUi.rich("[color=#9ea8b8]%s 관문[/color]" % PGlossaryTip.esc(String(PCatalog.boss_def(String(nx.boss)).name)), 12))
	else:
		var ps := []
		for p in nx.places:
			ps.append("%s%s" % [String(p.name), "(정예)" if bool(p.elite) else ""])
		box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(" · ".join(ps)), 12))
	return c.panel

func _services_card(r: Dictionary, into: VBoxContainer) -> void:
	var parts := []
	var S := PCatalog.services()
	for k in r.get("services", {}):
		if int(r.services[k]) > 0:
			var nm := PUi.rest_ticket_name() if String(k) == "free_rest" else String(S[String(k)].name)
			parts.append("[b]%s[/b] ×%d" % [nm, int(r.services[k])])
	if parts.is_empty():
		return
	into.add_child(PUi.rich("[b]보유 이용권[/b]  %s" % " · ".join(parts), 12))

## 다가오는 보스: 메인은 한 줄. 공략(설명·단계·정보 줄)은 '보스 상세'를 눌러야 열린다
func _boss_card(r: Dictionary, full: bool) -> Control:
	var B := PRun.next_boss_cfg(r)
	var left := PRun.boss_days_left(r)
	var stages := PRun.stage_count(r)
	var when := "처치함" if String(r.phase) == "cleared" else (("%d일 뒤 도래" % left) if left > 0 else "오늘 도래")
	var stage_lbl := ("%d단계 보스" % (int(r.get("stage", 0)) + 1)) if stages > 1 else ("보스" if not full else "다가오는 보스")
	if not full:
		var c := PUi.card("", PUi.CARD_BOSS)
		var box: VBoxContainer = c.box
		box.add_child(PUi.rich("[b]%s: %s[/b] [color=#ffe066]%s[/color]" % [stage_lbl, PGlossaryTip.esc(String(B.name)), when], 14))
		box.add_child(PUi.button("보스 상세 닫기 ▼" if _boss_open else "보스 상세 ▶", func(): _boss_open = not _boss_open; refresh(), true, 12))
		if _boss_open:
			_boss_detail(box, r, B)
		return c.panel
	var c2 := PUi.card("", PUi.CARD_BOSS)
	var box2: VBoxContainer = c2.box
	box2.add_child(PUi.rich("[b]%s: %s — %s[/b] [color=#ffe066]%s[/color]" % [stage_lbl, PGlossaryTip.esc(String(B.name)), PGlossaryTip.esc(String(B.get("title", ""))), when], 15))
	_boss_detail(box2, r, B)
	return c2.panel

func _boss_detail(box: VBoxContainer, r: Dictionary, B: Dictionary) -> void:
	var nb := PRun.next_boss(r)
	box.add_child(PUi.rich(String(BOSS_DESC.get(String(B.id), "")), 13))
	for t in B.get("info", []):
		box.add_child(PUi.rich("• " + PGlossaryTip.esc(String(t)), 12))
	var ph := []
	for p in B.get("phases", []):
		ph.append("%d%%" % int(round(float(p) * 100.0)))
	box.add_child(PUi.rich("[color=#9ea8b8]전장: %s · 체력 %d · 단계 전환 %s · 시간제한 없음%s[/color]" % [PGlossaryTip.esc(String(PCatalog.arenas().clearing.name)), int(PRun.boss_hp(r, String(B.id))), "·".join(ph), " · 승리 시 희귀 보상 3택" if (not nb.is_empty() and bool(nb.get("rare", false))) else ""], 12))

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
	open_confirm("하루를 마칠까요?", _endday_body.bind(run()), [{ "text": "하루 종료", "cb": func(): main.end_day() }], "돌아가기 (Esc)")

func _endday_body(box: VBoxContainer, r: Dictionary) -> void:
	var nx := PRun.preview_next_day(r)
	box.add_child(PUi.rich("%s%d일차 %s으로 넘어갑니다. 체력이 완전히 회복됩니다." % [("남은 %d칸을 버리고 " % int(r.hours)) if int(r.hours) > 0 else "", int(r.day) + 1, String(PRun.time_slots()[0])], 14))
	if nx.has("boss"):
		var c := PUi.card("내일: %s 관문" % PGlossaryTip.esc(String(PCatalog.boss_def(String(nx.boss)).name)), PUi.CARD_BOSS)
		(c.box as VBoxContainer).add_child(PUi.rich(("내일은 보스 관문으로 시작합니다. 상점·대장간·장비 교체 뒤 보스전에 들어가고, 이기면 그날의 시간대가 시작됩니다." if PRun.stage_count(r) > 1 else "일반 출격이 없습니다. 최종 준비 뒤 보스전에 들어갑니다.") + " 패배해도 입장 시점으로 돌아와 같은 준비로 재도전합니다.", 12))
		box.add_child(c.panel)
		return
	var c2 := PUi.card("내일의 장소")
	var b2: VBoxContainer = c2.box
	for p in nx.places:
		var en := []
		for t in p.enemies:
			en.append(String(PCatalog.enemy(String(t)).name))
		b2.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s%s[/color]" % [PGlossaryTip.esc(String(p.name)), "·".join(en), " · [b]정예[/b]" if bool(p.elite) else ""], 12))
	var MV: Dictionary = PCatalog.world().merchant_visits
	for d in MV.days:
		if int(d) == int(nx.day):
			b2.add_child(PUi.rich("[color=#ffe066]상인[/color] %s부터 방문 상인" % String(PRun.time_slots()[int(MV.slot)]), 12))
	if not PRun.next_boss(r).is_empty() and PRun.boss_days_left(r) - 1 > 0:
		b2.add_child(PUi.rich("[color=#9ea8b8]다음 보스까지 %d일[/color]" % (PRun.boss_days_left(r) - 1), 12))
	box.add_child(c2.panel)

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
		nbox.add_child(PUi.button("재정비 (체력 완전 회복, 남은 %d회)" % int(E.get("regroupLeft", 0)), func(): main.endless_regroup(), PEndless.can_regroup(r), 13))
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
	right.add_child(_build_summary(r))
	if _build_detail_open:
		right.add_child(PUi.equip_panel(r))
		right.add_child(PUi.build_panel(r))
	_stats_compact(r, right)
	_log_card(r, right)
