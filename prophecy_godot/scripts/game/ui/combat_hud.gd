class_name PCombatHud
extends Control
## 전투 하단 HUD(표시 전용). 실제 전투 상태(CombatState)와 실제 빌드(st.build = PBuild.derive(run))만 읽는다.
## 구성(UI_REDESIGN_HANDOFF §2):
##   왼쪽~가운데  자동기술 3칸 = [큰 아이콘 / 이름 / Lv] + 바로 아래 [개조 아이콘 ×2]. 미보유 슬롯·빈 개조 칸은 빈 테두리.
##   그 아래 줄   공용 증강·패시브(작은 보조 줄, 하나를 여러 기술에 복제하지 않는다) + 장비 3칸(자동기술과 시각적으로 분리된 영역)
##   오른쪽       회피 / Q / E (키 라벨 · 아이콘 · 쿨다운 가림막 + 남은 초). 미보유 E는 사용할 수 없는 빈 슬롯.
##
## 크기(1080p 기준 시작값): 자동기술 아이콘 56, 개조 30, 수동 버튼 64. 좁은 창에서는 아이콘만 줄이지 않고 배치를 바꾼다(PLayout 묶음).
## 초광폭에서는 수동 묶음을 화면 오른쪽 끝이 아니라 자동기술 묶음에서 일정 거리 안에 둔다(핵심 HUD를 양 끝으로 흩지 않는다).
##
## 규칙 보호: 이 클래스는 st를 읽기만 하고 st.rng를 절대 쓰지 않는다. 점등은 st.mod_stats[...].last_proc_t 등 실제 이벤트 시각으로만 계산한다.

const AUTO_SLOTS := 3
const MOD_SLOTS := 2

var st: CombatState = null
var touch_mode := false                 # 터치일 때 키 라벨을 숨긴다(터치 버튼은 PTouchControls가 그린다)

var _auto_tiles: Array = []             # [{tile: PIconTile, mods: [PIconTile, PIconTile]}]
var _manual: Dictionary = {}            # "dodge"|"q"|"e" → PIconTile
var _equip_tiles: Array = []
var _common_row: HBoxContainer
var _equip_row: HBoxContainer
var _auto_row: HBoxContainer
var _manual_row: HBoxContainer
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _equip_head: Label
var _common_head: Label
var _built_bucket := ""
var _built_touch := false

# 준비 완료(false→true) 신호: 능력별 마지막 준비 시각. 화면 재구성·일시정지·불러오기로 다시 터지지 않도록 상태(bool)를 그대로 들고 다닌다
var _ready_state: Dictionary = { "dodge": true, "q": true, "e": true }
var _ready_flash: Dictionary = { "dodge": -1.0, "q": -1.0, "e": -1.0 }
var _ready_bound_st: int = 0            # 지금 신호 상태가 어느 CombatState 기준인지(전투가 바뀌면 알림 없이 현재값으로 맞춘다)

const READY_SOUND := { "dodge": "ready_dodge", "q": "ready_q", "e": "ready_e" }

signal ready_signal(ability: String)    # false→true 전환 1회(소리·연출은 main이 낸다)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

# ---------- 구성 ----------
func _clear_children() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_auto_tiles = []
	_manual = {}
	_equip_tiles = []

func _bucket() -> String:
	return PLayout.bucket_of(get_viewport()) if is_inside_tree() else "standard"

func _sizes() -> Dictionary:
	# 1080p(=canvas 960 기준) 시작값. 좁은 창(narrow)은 아이콘을 조금 줄이고 이름 줄을 접는다
	var bk := _bucket()
	match bk:
		"narrow": return { "auto": 48.0, "mod": 28.0, "manual": 56.0, "equip": 30.0, "labels": false }
		"wide": return { "auto": 60.0, "mod": 32.0, "manual": 68.0, "equip": 34.0, "labels": true }
		_: return { "auto": 56.0, "mod": 30.0, "manual": 64.0, "equip": 32.0, "labels": true }

## 칸 폭: 아이콘 크기는 위 값 그대로 두고, 이름 한 줄이 들어가도록 칸만 넓힌다(작은 창에서도 이름을 지우지 않는다)
func _tile_w(S: Dictionary) -> Dictionary:
	var mod_w: float = float(S.mod) + 28.0
	return { "mod_w": mod_w, "auto_w": maxf(float(S.auto) + 24.0, mod_w * float(MOD_SLOTS) + 4.0) }

func _build() -> void:
	_clear_children()
	_built_bucket = _bucket()
	_built_touch = touch_mode
	var S := _sizes()
	var TW := _tile_w(S)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 4)
	_left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_left_box)
	# --- 자동기술 3칸 + 각 칸의 개조 2칸(위치만으로 소속을 안다) ---
	_auto_row = HBoxContainer.new()
	_auto_row.add_theme_constant_override("separation", 10)
	_auto_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_box.add_child(_auto_row)
	for i in AUTO_SLOTS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tile := PIconTile.new("", PIconTile.STYLE_AUTO)
		tile.set_icon_px(float(S.auto), float(TW.auto_w), 2 if bool(S.labels) else 1)
		col.add_child(tile)
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 4)
		mrow.alignment = BoxContainer.ALIGNMENT_CENTER
		mrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mods: Array = []
		for j in MOD_SLOTS:
			var mt := PIconTile.new("", PIconTile.STYLE_MOD)
			mt.set_icon_px(float(S.mod), float(TW.mod_w), 1)
			mrow.add_child(mt)
			mods.append(mt)
		col.add_child(mrow)
		_auto_row.add_child(col)
		_auto_tiles.append({ "tile": tile, "mods": mods })
	# --- 공용 증강·패시브(작은 보조 줄) ---
	_common_head = _small_label("공용 · 패시브")
	_left_box.add_child(_common_head)
	_common_row = HBoxContainer.new()
	_common_row.add_theme_constant_override("separation", 4)
	_common_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_box.add_child(_common_row)
	# --- 장비(자동기술과 분리된 영역: 제목 줄 + 별도 배경 카드) ---
	var eq_wrap := PanelContainer.new()
	eq_wrap.add_theme_stylebox_override("panel", PUi.stylebox(Color(0.07, 0.09, 0.12, 0.72), 6, 6, Color(0.30, 0.34, 0.40, 0.8)))
	eq_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var eq_box := VBoxContainer.new()
	eq_box.add_theme_constant_override("separation", 2)
	eq_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eq_wrap.add_child(eq_box)
	_equip_head = _small_label("장비")
	eq_box.add_child(_equip_head)
	_equip_row = HBoxContainer.new()
	_equip_row.add_theme_constant_override("separation", 4)
	_equip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eq_box.add_child(_equip_row)
	for sl in PCatalog.world().equip_slots:
		var et := PIconTile.new("", PIconTile.STYLE_EQUIP)
		et.set_icon_px(float(S.equip), float(S.equip) + 26.0, 1)
		et.title = PUi.slot_name(String(sl))
		_equip_row.add_child(et)
		_equip_tiles.append({ "slot": String(sl), "tile": et })
	root.add_child(eq_wrap)
	# --- 회피 / Q / E (오른쪽, 시각적으로 분리된 묶음) ---
	_right_box = VBoxContainer.new()
	_right_box.add_theme_constant_override("separation", 2)
	_right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_right_box)
	_manual_row = HBoxContainer.new()
	_manual_row.add_theme_constant_override("separation", 8)
	_manual_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_box.add_child(_manual_row)
	for spec in [["dodge", "action:dodge", "Space"], ["q", "skill:slowfield", "Q"], ["e", "", "E"]]:
		var t := PIconTile.new(String(spec[1]), PIconTile.STYLE_MANUAL)
		t.set_icon_px(float(S.manual), float(S.manual) + 6.0, 1)
		t.key_label = "" if touch_mode else String(spec[2])
		_manual_row.add_child(t)
		_manual[String(spec[0])] = t

func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.60, 0.65, 0.72))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 창 크기·터치 여부가 바뀌면 아이콘만 줄이지 않고 배치를 다시 만든다.
## 터치일 때는 회피/Q/E 묶음을 숨기고(터치 버튼이 그 역할) 빌드 줄을 상단 띠 아래로 올려 손가락 조작 영역과 겹치지 않게 한다.
func relayout(safe: Rect2) -> float:
	if _built_bucket != _bucket() or _built_touch != touch_mode:
		_build()
	if get_child_count() == 0:
		return 0.0
	var root: Control = get_child(0) as Control
	if root == null:
		return 0.0
	if _right_box != null:
		_right_box.visible = not touch_mode
	root.reset_size()
	var w: float = root.get_combined_minimum_size().x
	var h: float = root.get_combined_minimum_size().y
	if touch_mode:
		root.position = Vector2(round(safe.position.x + 10.0), round(safe.position.y + 46.0))
		root.size = Vector2(w, h)
		return h + 12.0
	# 초광폭: 핵심 HUD 묶음을 안전 영역 왼쪽에서 시작해 한 덩어리로 둔다(양 끝으로 흩지 않는다)
	var x: float = safe.position.x + 12.0
	if safe.size.x > w + 240.0:
		x = safe.position.x + minf(60.0, (safe.size.x - w) / 2.0)
	root.position = Vector2(round(x), round(safe.end.y - h - 24.0))
	root.size = Vector2(w, h)
	return 0.0

# ---------- 갱신(매 프레임, 읽기 전용) ----------
func update_from(state: CombatState) -> void:
	st = state
	if st == null or _auto_tiles.is_empty():
		return
	var now: float = st.t
	var b: Dictionary = st.build
	var weapons: Array = b.get("weapons", [])
	var G := PCatalog.growth()
	var lv_max: int = int(G.SLOTS.weaponMax)
	for i in AUTO_SLOTS:
		var row: Dictionary = _auto_tiles[i]
		var tile: PIconTile = row.tile
		var mods: Array = row.mods
		if i < weapons.size():
			var wd: Dictionary = weapons[i]
			var wid := String(wd.id)
			tile.empty = false
			tile.key = PIcons.weapon_key(wid)
			tile.title = String(wd.name)
			tile.sub = "Lv%d/%d" % [int(wd.level), lv_max]
			tile.now_t = now
			var wmods: Array = wd.get("mods", [])
			for j in MOD_SLOTS:
				var mt: PIconTile = mods[j]
				mt.now_t = now
				if j < wmods.size():
					var mid := String(wmods[j])
					mt.empty = false
					mt.key = PIcons.mod_key(wid, mid)
					mt.title = ""
					mt.flash_t = _mod_proc_t(mid)
				else:
					mt.empty = true
					mt.key = ""
					mt.title = ""
					mt.flash_t = -1.0
				mt.queue_redraw()
		else:
			tile.empty = true
			tile.key = ""
			tile.title = "빈 슬롯"
			tile.sub = ""
			for j in MOD_SLOTS:
				var mt2: PIconTile = mods[j]
				mt2.empty = true
				mt2.key = ""
				mt2.flash_t = -1.0
				mt2.queue_redraw()
		tile.queue_redraw()
	_update_commons(b)
	_update_equipment(b)
	_update_manual(now)

## 공용 증강·패시브: 한 항목당 아이콘 1개만(여러 기술 밑에 복제하지 않는다). 연결은 빌드 상세에서 보여 준다
func _update_commons(b: Dictionary) -> void:
	var g: Dictionary = b.get("growth", {})
	var want: Array = []
	for k in g.get("commons", {}):
		if int(g.commons[k]) > 0:
			want.append(["common:" + String(k), int(g.commons[k])])
	for k in g.get("passives", {}):
		if int(g.passives[k]) > 0:
			want.append(["passive:" + String(k), int(g.passives[k])])
	var S := _sizes()
	while _common_row.get_child_count() < want.size():
		var t := PIconTile.new("", PIconTile.STYLE_SMALL)
		t.set_icon_px(24.0, 24.0, 0)
		_common_row.add_child(t)
	for i in _common_row.get_child_count():
		var tile: PIconTile = _common_row.get_child(i) as PIconTile
		if i < want.size():
			tile.visible = true
			tile.key = String(want[i][0])
			tile.title = ""
			tile.badge = str(int(want[i][1])) if int(want[i][1]) > 1 else ""
			tile.set_icon_px(24.0, 24.0, 0)
			tile.queue_redraw()
		else:
			tile.visible = false
	_common_head.visible = want.size() > 0
	_common_row.visible = want.size() > 0
	_common_head.text = "공용 증강 · 패시브 %d (상세는 빌드 보기)" % want.size()
	if not bool(S.labels):
		_common_head.visible = false

func _update_equipment(b: Dictionary) -> void:
	var eq_ids: Array = b.get("equip_ids", [])
	for row in _equip_tiles:
		var slot := String(row.slot)
		var tile: PIconTile = row.tile
		var found := ""
		for id in eq_ids:
			var d := PCatalog.equipment_def(String(id))
			if not d.is_empty() and String(d.get("slot", "")) == slot:
				found = String(id)
		if found == "":
			tile.empty = true
			tile.key = ""
			tile.title = PUi.slot_name(slot)
		else:
			tile.empty = false
			tile.key = "equip:" + found
			tile.title = String(PCatalog.equipment_def(found).name)
		tile.queue_redraw()

func _update_manual(now: float) -> void:
	var p: Dictionary = st.player
	var P: Dictionary = st.cfg.player
	var b: Dictionary = st.build
	# 회피
	var dcd: float = float(P.dodge.cooldown)
	var d_left: float = maxf(0.0, float(p.dodge_cd))
	_set_manual("dodge", "action:dodge", false, clampf(d_left / maxf(0.01, dcd), 0.0, 1.0), d_left, now, "회피")
	# Q 감속장
	var qcd: float = float(b.special_cd) if b.has("special_cd") else float(P.slowfield.cooldown)
	var q_left: float = maxf(0.0, float(p.special_cd))
	_set_manual("q", "skill:slowfield", false, clampf(q_left / maxf(0.01, qcd), 0.0, 1.0), q_left, now, "감속장")
	# E(미보유는 사용할 수 없는 빈 슬롯)
	var e = b.skills.get("e", null)
	if e == null:
		var te: PIconTile = _manual["e"]
		te.empty = true
		te.disabled = true
		te.key = ""
		te.title = "미보유"
		te.cd_ratio = 0.0
		te.cd_left = 0.0
		te.flash_t = -1.0
		te.now_t = now
		te.queue_redraw()
		_ready_state["e"] = false
	else:
		var ecd: float = PSkills.cd_of(st, "e")
		var e_left: float = maxf(0.0, float(p.get("e_cd", 0.0)))
		var sid := String(e.id)
		_set_manual("e", PIcons.e_key(sid, e.get("variant", null)), false, clampf(e_left / maxf(0.01, ecd), 0.0, 1.0), e_left, now, String(PCatalog.skills()[sid].name))

func _set_manual(ability: String, key: String, disabled_v: bool, ratio: float, left: float, now: float, title: String) -> void:
	var t: PIconTile = _manual[ability]
	t.empty = false
	t.disabled = disabled_v
	t.key = key
	t.title = title
	t.cd_ratio = ratio
	t.cd_left = left
	t.now_t = now
	var is_ready: bool = left <= 0.0 and not disabled_v
	if bool(_ready_state.get(ability, true)) != is_ready:
		_ready_state[ability] = is_ready
		if is_ready:
			_ready_flash[ability] = now
			ready_signal.emit(ability)
	t.flash_t = float(_ready_flash.get(ability, -1.0))
	t.queue_redraw()

## 개조가 실제로 발동한 시각(st.mod_stats). 자체 타이머가 아니라 실제 이벤트만 쓴다
func _mod_proc_t(mod_id: String) -> float:
	if st == null:
		return -1.0
	var ms: Dictionary = st.mod_stats
	if not ms.has(mod_id):
		return -1.0
	return float((ms[mod_id] as Dictionary).get("last_proc_t", -1.0))

## 새 전투·재개·저장 복구: 이미 준비된 능력에 알림이 다시 터지지 않도록 현재값으로 조용히 맞춘다
func sync_ready_silent(state: CombatState) -> void:
	st = state
	if st == null:
		return
	_ready_bound_st = st.get_instance_id()
	var p: Dictionary = st.player
	var b: Dictionary = st.build
	_ready_state["dodge"] = float(p.dodge_cd) <= 0.0
	_ready_state["q"] = float(p.special_cd) <= 0.0
	_ready_state["e"] = b.skills.get("e", null) != null and float(p.get("e_cd", 0.0)) <= 0.0
	for k in _ready_flash:
		_ready_flash[k] = -1.0

## 방금 선택으로 바뀐 칸을 잠깐 강조("w<i>" 또는 "w<i>:m<j>"). 빈 문자열이면 아무것도 하지 않는다
func highlight_slot(slot: String, seconds: float = 1.2) -> void:
	if slot == "" or _auto_tiles.is_empty():
		return
	var parts := slot.split(":")
	var wi: int = int(String(parts[0]).substr(1)) if String(parts[0]).begins_with("w") else -1
	if wi < 0 or wi >= _auto_tiles.size():
		return
	var row: Dictionary = _auto_tiles[wi]
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	if parts.size() >= 2 and String(parts[1]).begins_with("m"):
		var mj: int = int(String(parts[1]).substr(1))
		if mj >= 0 and mj < (row.mods as Array).size():
			(row.mods[mj] as PIconTile).pick_until_ms = until
			return
	(row.tile as PIconTile).pick_until_ms = until

func bound_state_id() -> int:
	return _ready_bound_st

func ready_state() -> Dictionary:
	return _ready_state.duplicate()
