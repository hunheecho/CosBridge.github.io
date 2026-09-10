class_name PScreen
extends Control
## 화면 공통 뼈대: 배경 + 여백 + (상단 줄 · 스크롤 본문 · 하단 줄). 각 화면은 _build()에서 고정 틀을, refresh()에서 회차 상태로 내용을 다시 만든다.
## 화면은 규칙을 계산하지 않는다: main(회차 흐름)과 PRun/PBuild/PGrowth/PFlow가 준 값을 표시하고, 버튼은 main의 함수를 부른다.

var main: Node = null
var root: VBoxContainer
var top: VBoxContainer
var body: VBoxContainer
var bottom: HBoxContainer
var scroll: ScrollContainer
var touch_scroll: PTouchScroll        # 손가락으로 목록 넘기기(터치 전용). 화면 14개가 이 하나를 함께 쓴다
var default_button: Button = null
var _margin: MarginContainer          # 여백 = 기본(14·10) + 안전 영역 밖(PLayout.margins)
var _bucket := ""                      # 마지막 refresh 때의 화면 비율 묶음(wide/standard/narrow)
var _modal: Control                    # 확인 창 층(휴식·판매·구매 뒤 선택 — 모든 화면 공용)
var _modal_box: VBoxContainer
var _modal_panel: PanelContainer       # 확인 창의 판(글자 배율에 맞춰 폭을 다시 준다)
## 확인 창 판의 기본 폭(canvas px). 글자가 배율만큼 커지면 폭도 같이 커져야 줄 수가 늘지 않는다 —
## 폭을 그대로 두면 같은 글이 훨씬 여러 줄로 접혀 창이 세로로 길어지고, 낮은 폰 화면에서는
## **아래쪽 '취소'·'확정' 버튼이 화면 밖으로 밀린다**(2026-09-09 실제 브라우저에서 본 위험).
const MODAL_W := 560.0
var _modal_token := 0                  # 확인 창마다 새 번호. 확정하면 번호가 올라 그 창의 버튼은 모두 무효가 된다(중복 클릭 방지)
var _modal_prev_default: Button = null # 확인 창을 열기 전의 기본 버튼(취소하면 Enter가 원래 행동으로 돌아간다)

func setup(m: Node) -> void:
	main = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = PUi.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = margin
	_apply_safe_margins()
	add_child(margin)
	root = PUi.vbox(8)
	margin.add_child(root)
	top = PUi.vbox(6)
	root.add_child(top)
	scroll = PUi.scroll()
	root.add_child(scroll)
	body = PUi.vbox(8)
	scroll.add_child(body)
	bottom = PUi.hbox(10)
	root.add_child(bottom)
	_make_modal()
	# 손가락 끌기로 스크롤 — 화면마다 따로 만들지 않고 공통 뼈대에서 한 번만 붙인다.
	# 확인 창이 열려 있으면 뒤쪽 목록이 따라 움직이지 않게 새 끌기를 시작하지 않는다.
	touch_scroll = PTouchScroll.attach(self, scroll)
	touch_scroll.blocked = confirm_open
	_build()

# ---------- 확인 창(모든 화면 공용) ----------
## 결정 전에 무엇이 오가는지 보여 주고, 취소하면 아무것도 바뀌지 않는다(사용자 지시 2026-09-09).
## 확정은 한 번만 실행된다 — 창마다 번호를 매기고 확정 순간 번호를 올려, 같은 창의 버튼이 다시 눌려도 아무 일도 하지 않는다.
func _make_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.1, 0.12, 0.15, 0.98), 8, 16, Color(0.5, 0.6, 0.75, 0.9)))
	panel.custom_minimum_size = Vector2(MODAL_W, 0)
	_modal_panel = panel
	center.add_child(panel)
	_modal_box = PUi.vbox(8)
	panel.add_child(_modal_box)
	_modal.visible = false
	add_child(_modal)

func confirm_open() -> bool:
	return _modal != null and _modal.visible

func close_confirm() -> void:
	_modal_token += 1
	if _modal != null and _modal.visible:
		_modal.visible = false
		if _modal_prev_default != null and is_instance_valid(_modal_prev_default):
			default_button = _modal_prev_default # 취소 뒤 Enter가 원래 주 행동으로 돌아간다
	_modal_prev_default = null

## title = 큰 물음 줄, fill(box) = 결정에 필요한 내용(비용·전후 수치·부작용), actions = [{text, cb}]
## 취소 버튼은 항상 마지막에 붙는다.
func open_confirm(title: String, fill: Callable, actions: Array, cancel_text: String = "취소 (Esc)") -> void:
	PUi.clear(_modal_box)
	if _modal_panel != null:
		# 글자 배율만큼 판도 넓힌다. 화면(안전 영역)보다 넓어지지는 않는다
		var lim: float = PLayout.screen_size(get_viewport()).x - 32.0 if is_inside_tree() else MODAL_W
		_modal_panel.custom_minimum_size = Vector2(minf(MODAL_W * PLayout.cur_ui_scale(), maxf(MODAL_W, lim)), 0.0)
	if not _modal.visible: # 창 안에서 다른 창으로 넘어갈 때는 처음의 기본 버튼을 그대로 들고 간다
		_modal_prev_default = default_button
	_modal_token += 1
	var tok := _modal_token
	_modal_box.add_child(PUi.rich("[b]%s[/b]" % title, 20))
	if fill.is_valid():
		fill.call(_modal_box)
	var row := PUi.hbox(8)
	var first: Button = null
	for a in actions:
		var act: Dictionary = a
		var cb: Callable = act.cb
		var btn := PUi.button(String(act.text), func(): _confirm_run(tok, cb), true, 15)
		btn.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		row.add_child(btn)
		if first == null:
			first = btn
	row.add_child(PUi.button(cancel_text, func(): close_confirm(), true, 15))
	_modal_box.add_child(row)
	default_button = first
	_modal.visible = true

## 확정 한 번만: 이 창의 번호가 아직 살아 있을 때만 처리하고, 처리하면서 번호를 올린다
func _confirm_run(tok: int, cb: Callable) -> void:
	if tok != _modal_token:
		return
	_modal_token += 1
	_modal.visible = false
	if cb.is_valid():
		cb.call()

## 판매 확인 창(거점 아이콘·장비 화면·상점이 같은 창을 쓴다).
## 받을 금액을 그대로 적고, 장착 중이면 해제된다는 것을 함께 말한다. 취소하면 금화·가방·장착이 그대로다.
## 확정은 한 번만 실행되므로 중복 클릭으로 같은 장비가 두 번 팔리지 않는다.
func open_sell_confirm(id: String) -> void:
	var r := run()
	if r.is_empty():
		return
	var nm := PRun.equip_display_name(r, id) # 강화 단계까지 이름에 넣는다(무엇을 파는지 헷갈리지 않게 — §4)
	var q := PRun.sell_quote(main.run, id)   # 판매가 정본은 견적이다(지불액의 절반 + 강화 비용의 50%)
	var price := int(q.gold)
	# 확정에 이 금액을 그대로 넘긴다 — 창에 적힌 값과 실제 입금액이 다를 수 없다
	open_confirm("%s%s %d금에 판매할까요?" % [PGlossaryTip.esc(nm), PUi.josa(nm, "을", "를"), price],
		_sell_body.bind(r, id, price), [{ "text": "판매한다", "cb": func(): main.sell_equipment(id, price) }])

func _sell_body(box: VBoxContainer, r: Dictionary, id: String, price: int) -> void:
	var slot := ""
	for sl in PCatalog.world().equip_slots:
		var s := String(sl)
		if r.equipment.get(s, null) != null and String(r.equipment[s]) == id:
			slot = s
	PUi.kv(box, "받을 금액", "[color=#ffd966][b]+%d금[/b][/color] [color=#9ea8b8](금화 %d → %d)[/color]" % [price, int(r.gold), int(r.gold) + price], 15)
	# 판매가가 어떻게 갈리는지 그대로 적는다(기본가 + 강화 비용 환급) — 견적과 같은 값이다
	var q := PRun.sell_quote(r, id)
	var paid := int(q.get("paid", -1))
	var basis := ("이 장비에 실제로 낸 %d금" % paid) if paid >= 0 else ("산 적이 없는 장비라 정상가 %d금" % PRun.equip_price(id))
	PUi.kv(box, "기본가", "[b]%d금[/b] [color=#9ea8b8]%s의 %d%%[/color]" % [int(q.get("base", 0)), basis, int(round(PRun.sell_rate() * 100.0))], 13)
	if int(q.get("plus", 0)) > 0:
		PUi.kv(box, "강화 환급", "[b]%d금[/b] [color=#9ea8b8]+%d까지 낸 강화 비용 %d금의 %d%%[/color]" % [
			int(q.get("refund", 0)), int(q.plus), int(q.get("upgradeSpent", 0)), int(round(PRun.sell_refund_rate() * 100.0))], 13)
	if slot != "":
		var dup: Dictionary = r.duplicate(true)
		PRun.unequip_item(dup, slot)
		box.add_child(PUi.rich("[color=#ff8c73]지금 %s 칸에 장착 중입니다 — 팔면 해제됩니다.[/color]" % PUi.slot_name(slot), 14))
		PUi.kv(box, "해제하면", PUi.diff_text(PBuild.derive(r), PBuild.derive(dup)), 13)
	else:
		PUi.kv(box, "있는 곳", "[b]%s[/b]" % PGlossaryTip.term("bag", "가방"), 14)
	box.add_child(PUi.rich("[color=#9ea8b8]취소하면 금화·가방·장착이 그대로입니다. 판 장비는 되사올 수 없습니다.[/color]", 12))

func run() -> Dictionary:
	return main.run

func _build() -> void:
	pass

func refresh() -> void:
	pass

## **다른 화면에서 새로 들어올 때.** 맨 위에서 시작한다.
func on_enter() -> void:
	refresh_in_place()
	_keep_scroll = 0          # 화면에 새로 들어올 때는 맨 위에서 시작한다
	scroll.scroll_vertical = 0
	if touch_scroll != null:
		touch_scroll.stop()   # 앞 화면에서 미끄러지던 관성을 물려받지 않는다

## **같은 화면을 그 자리에서 다시 그릴 때.** 보고 있던 자리를 잃지 않는다.
##
## 사람 플레이 보고(2026-09-09, 두 번째): "판매할 때마다 위로 올라가는 것도 없애줘.
## 이거 예전에 없앴다고 하지 않았냐?" — 맞다. 예전에 고친 것은 clear_all() 쪽이었고
## 그것만으로는 부족했다. 판매·장착·구매는 main.show(screen) 으로 **같은 화면을 다시**
## 부르는데, 그 길이 on_enter() 를 타면서 refresh() 가 방금 저장한 _keep_scroll 을
## 바로 다음 줄에서 0 으로 지워 버렸다. 그래서 되살리기가 아무 일도 하지 않았다.
## 이제 화면이 실제로 바뀔 때만 맨 위로 간다(main.show 가 갈라 부른다).
func refresh_in_place() -> void:
	default_button = null
	_apply_safe_margins()
	_bucket = bucket()
	refresh()

## 화면 비율 묶음(PLayout): 화면들이 열 비율·마을 높이를 고를 때 쓴다
func bucket() -> String:
	return PLayout.bucket_of(get_viewport()) if is_inside_tree() else "standard"

func _apply_safe_margins() -> void:
	if _margin == null or not is_inside_tree():
		return
	PLayout.apply_margins(_margin, get_viewport(), 14, 10)

## 오른쪽 위 '전체화면' 버튼 자리가 바뀌었다(전체화면 진입·이탈): 여백만 다시 준다.
## 화면을 다시 만들지 않으므로 스크롤 위치·펼침 상태가 그대로 남는다
func relayout_margins() -> void:
	_apply_safe_margins()

## 창 크기 변경: 여백 갱신, 비율 묶음이 바뀐 보이는 화면은 다시 만든다
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and _margin != null:
		_apply_safe_margins()
		if visible and _bucket != "" and bucket() != _bucket:
			_bucket = bucket()
			refresh()

## Esc: 화면 안의 하위 상태를 닫았으면 true. 확인 창이 열려 있으면 먼저 닫는다(아무것도 바뀌지 않는다)
func on_escape() -> bool:
	if confirm_open():
		close_confirm()
		return true
	return false

var _keep_scroll := 0        # 다시 그리기 전에 보고 있던 세로 자리
var _restore_queued := false

# ---------- 손가락 끌기로 스크롤(버튼 위에서 시작해도 된다) ----------
## 카드 판·글상자는 mouse_filter=PASS 로 내려 끌기가 스크롤까지 올라가지만,
## **버튼 위에서 시작한 끌기**는 버튼이 먹어서 스크롤이 되지 않았다(KD-8 잔여분).
## 상점처럼 버튼이 빽빽한 화면에서는 그게 곧 "스크롤이 안 된다"였다.
##
## 그 처리는 이제 여기 있지 않다 — `PTouchScroll`(scripts/game/ui/touch_scroll.gd)이 통째로 맡는다.
## 문턱 12px·버튼 누름 취소·소수점 이동·관성·경계·여러 손가락이 모두 그쪽에 있고,
## 이 뼈대가 화면마다 하나씩 붙여 준다. 왜 그렇게 만들었는지는 docs/TOUCH_SCROLL.md 를 봐라.
## 터치 기기에서만 돈다. PC는 휠을 그대로 쓴다.

## 화면을 다시 그린다. **보고 있던 자리를 잃지 않는다.**
##
## 사람 플레이 보고(2026-09-09, 친구): 상점에서 아래로 내려가 '팔기 x1'을 누르면 창이 맨 위로
## 튀어 올라, 4개를 팔려면 네 번 내려가야 했다("걍 갖다 버리고 싶었음").
## 파는 동작은 목록만 바꾸므로 보던 자리는 그대로 두는 것이 맞다.
## 화면에 처음 들어올 때(on_enter)는 예전처럼 맨 위에서 시작한다.
func clear_all() -> void:
	_keep_scroll = int(scroll.scroll_vertical) if scroll != null else 0
	PUi.clear(top)
	PUi.clear(body)
	PUi.clear(bottom)
	if _keep_scroll > 0 and not _restore_queued:
		_restore_queued = true
		call_deferred("_restore_scroll")

func _restore_scroll() -> void:
	_restore_queued = false
	if scroll == null or not is_inside_tree():
		return
	await get_tree().process_frame   # 새 내용이 배치돼야 스크롤 범위가 정해진다
	if scroll != null and _keep_scroll > 0:
		scroll.scroll_vertical = _keep_scroll
		if touch_scroll != null:
			touch_scroll.sync()      # 되살린 자리를 손가락 스크롤도 같은 값으로 본다

func heading(text: String, sub: String = "") -> void:
	top.add_child(PUi.rich("[b]%s[/b]%s" % [text, ("  [color=#9ea8b8]%s[/color]" % sub) if sub != "" else ""], 22))

## 두 칸 가로 배치(왼쪽 넓게).
##
## 좁은 화면에서는 **한 열로 쌓는다**(2026-09-09 실제 브라우저, 폰 가로 640×360 · 글자 배율 1.6배).
## 두 열로 두면 오른쪽 열의 내용이 화면 오른쪽 밖으로 잘려 나갔고, 가로 스크롤이 꺼져 있어 볼 방법이 없었다.
## 넓이는 캔버스 px이 아니라 **배율을 뺀 설계 단위**로 잰다(PLayout.two_columns_fit).
## 부르는 쪽은 달라질 것이 없다 — 여전히 {left, right} 두 상자를 받는다.
func two_cols(left_ratio: float = 0.55) -> Dictionary:
	var stacked: bool = is_inside_tree() and not PLayout.two_columns_fit(get_viewport())
	var box: BoxContainer = PUi.vbox(12) if stacked else PUi.hbox(12)
	var l := PUi.vbox(8)
	var r := PUi.vbox(8)
	if not stacked:
		l.size_flags_stretch_ratio = left_ratio
		r.size_flags_stretch_ratio = 1.0 - left_ratio
	box.add_child(l)
	box.add_child(r)
	body.add_child(box)
	return { "left": l, "right": r, "stacked": stacked }
