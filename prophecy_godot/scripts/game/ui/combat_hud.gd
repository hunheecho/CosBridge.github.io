class_name PCombatHud
extends Control
## 전투 HUD(표시 전용). 실제 전투 상태(CombatState)와 실제 빌드(st.build = PBuild.derive(run))만 읽는다.
##
## 사람 플레이 뒤 요구(2026-09-08): 전장에는 지금 눌러야 할 것만 남긴다.
##   상단  체력 = 빨간 막대 + 큰 숫자. 보호막은 같은 막대에 섞지 않고 아래 파란 줄 + 따로 적는다.
##   하단  조작 아이콘 Space / Q / E 3칸만. 자동기술 3칸·개조·공용·패시브·장비는 전장에 상시 표시하지 않는다.
##         (전체 빌드는 일시정지의 '내 빌드' = PBuildDetail 에서 본다. Tab · 일시정지 버튼 · 터치의 '빌드' 버튼)
##
## 조작 아이콘 4가지 상태를 구분한다(PIconTile.state):
##   미보유(none) 빈 테두리 + '미보유' · 사용 불가(unusable) 흐림 + 빗금 · 재사용 대기(cooldown) 흑백 + 남은 초 · 준비됨(ready) 컬러 + 테두리 점등.
## 준비 소리는 실제 false→true 전환 순간에만 1회. 일시정지·재개·저장 복구·화면 재구성은 sync_ready_silent로 조용히 맞춘다.
##
## 규칙 보호: 이 클래스는 st를 읽기만 하고 st.rng를 절대 쓰지 않는다. 점등은 실제 이벤트 시각으로만 계산한다.

const MANUAL := ["dodge", "q", "e"]

## 색은 여기서만 정한다. 체력은 붉은 계열로 전장에서 가장 먼저 눈에 들어와야 하고(사용자 지시),
## 보호막은 파란 계열로 같은 막대에 섞지 않는다. 시험이 이 관계를 그대로 확인한다.
const HP_FILL := Color(0.82, 0.20, 0.20, 0.96)
const HP_BACK := Color(0.16, 0.06, 0.07, 0.92)
const HP_EDGE := Color(0.55, 0.24, 0.24, 0.9)
const SHIELD_FILL := Color(0.42, 0.72, 1.0, 0.95)
const SHIELD_BACK := Color(0.08, 0.12, 0.20, 0.9)

var st: CombatState = null
var touch_mode := false                 # 터치일 때 키 라벨을 숨긴다(터치 버튼은 PTouchControls가 그린다)

var _manual: Dictionary = {}            # "dodge"|"q"|"e" → PIconTile
var _manual_row: HBoxContainer
var _health: Control                    # 상단 체력·보호막(PHealth 내부 클래스)
var _built_bucket := ""
var _built_touch := false
var _blocked := false                   # 지금 규칙이 조작 입력을 받지 않는 상태인가(등장 연출·전투 종료)
var _legacy: Array = []                 # 상단 띠의 옛 체력 노드(HP·Shield·HPText). 매 갱신마다 숨긴 상태를 유지한다

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

# ---------- 상단 체력·보호막(빨간 막대 + 큰 숫자) ----------
## 체력과 보호막을 절대 한 막대에 합치지 않는다: 위 = 체력(빨강), 아래 얇은 줄 = 보호막(파랑) + 글자도 따로.
class PHealth extends Control:
	var hp := 100.0
	var hp_max := 100.0
	var shield := 0.0
	var shield_max := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(p_hp: float, p_hp_max: float, p_shield: float, p_shield_max: float) -> void:
		hp = p_hp
		hp_max = p_hp_max
		shield = p_shield
		shield_max = p_shield_max
		queue_redraw()

	func has_shield() -> bool:
		return shield > 0.0

	func _draw() -> void:
		var w: float = size.x
		var bar_h: float = 26.0
		# 체력 막대: 어두운 바탕 + 빨간 채움
		PRender.rrect(self, 0.0, 0.0, w, bar_h, 5.0, PCombatHud.HP_BACK)
		var k: float = clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
		if k > 0.0:
			PRender.rrect(self, 0.0, 0.0, maxf(4.0, w * k), bar_h, 5.0, PCombatHud.HP_FILL)
		draw_rect(Rect2(0.0, 0.0, w, bar_h), PCombatHud.HP_EDGE, false, 1.0)
		# 큰 숫자(체력만). 보호막은 절대 여기에 더하지 않는다
		PRender.txt(self, 8.0, bar_h - 6.0, "%d" % int(ceil(hp)), 22, Color(1, 1, 1, 0.98), -1, true)
		PRender.txt(self, w - 8.0, bar_h - 9.0, "/ %d" % int(hp_max), 13, Color(0.94, 0.86, 0.86, 0.97), 1, true)
		if shield <= 0.0:
			return
		# 보호막: 체력 막대와 색·위치·글자를 모두 분리한다
		var sy: float = bar_h + 2.0
		var sh: float = 7.0
		PRender.rrect(self, 0.0, sy, w, sh, 3.0, PCombatHud.SHIELD_BACK)
		var sk: float = clampf(shield / maxf(1.0, shield_max), 0.0, 1.0)
		PRender.rrect(self, 0.0, sy, maxf(3.0, w * sk), sh, 3.0, PCombatHud.SHIELD_FILL)
		PRender.txt(self, w - 2.0, sy + sh + 10.0, "보호막 %d" % int(ceil(shield)), 12, Color(0.66, 0.84, 1.0, 0.98), 1, true)

# ---------- 구성 ----------
func _clear_children() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_manual = {}

func _bucket() -> String:
	return PLayout.bucket_of(get_viewport()) if is_inside_tree() else "standard"

func _sizes() -> Dictionary:
	# 전장에 남기는 것은 조작 아이콘 3칸뿐이다. 작지만 분명하게(키 라벨 + 남은 초가 읽히는 최소 크기)
	match _bucket():
		"narrow": return { "manual": 44.0 }
		"wide": return { "manual": 52.0 }
		_: return { "manual": 48.0 }

func _build() -> void:
	_clear_children()
	_built_bucket = _bucket()
	_built_touch = touch_mode
	var S := _sizes()
	_health = PHealth.new()
	_health.custom_minimum_size = Vector2(200.0, 36.0)
	_health.size = Vector2(200.0, 36.0)
	add_child(_health)
	_manual_row = HBoxContainer.new()
	_manual_row.add_theme_constant_override("separation", 8)
	_manual_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_manual_row)
	for spec in [["dodge", "action:dodge", "Space"], ["q", "skill:slowfield", "Q"], ["e", "", "E"]]:
		var t := PIconTile.new(String(spec[1]), PIconTile.STYLE_MANUAL)
		t.set_icon_px(float(S.manual), float(S.manual) + 10.0, 1)
		t.key_label = "" if touch_mode else String(spec[2])
		_manual_row.add_child(t)
		_manual[String(spec[0])] = t

## 상단 띠의 옛 체력 막대·글자는 숨긴다(같은 정보를 빨간 막대 + 큰 숫자로 다시 그린다).
## main.gd는 그 노드에 값을 계속 넣으므로 시험 계약(HPText.text)은 그대로 살아 있다.
func _hide_legacy_health() -> void:
	if _legacy.is_empty():
		var parent := get_parent()
		if parent == null:
			return
		for n in ["HP", "Shield", "HPText"]:
			var c: Control = parent.get_node_or_null(NodePath(n)) as Control
			if c != null:
				_legacy.append(c)
	for cc in _legacy:
		var ctl: Control = cc
		if is_instance_valid(ctl) and ctl.visible:
			ctl.visible = false # main._update_hud가 매 프레임 보호막 막대를 다시 켜므로 여기서 계속 눌러 둔다

## 창 크기·터치 여부가 바뀌면 배치를 다시 만든다.
## 조작 아이콘은 화면 왼쪽 아래 한 덩어리로만 둔다(적 예고·목표 줄·상단 띠를 가리지 않게).
## 터치일 때는 PTouchControls가 같은 조작을 큰 버튼으로 그리므로 아이콘 줄은 숨긴다.
func relayout(safe: Rect2) -> float:
	if _built_bucket != _bucket() or _built_touch != touch_mode:
		_build()
	_hide_legacy_health()
	if _health != null:
		var hw: float = minf(200.0, maxf(140.0, safe.size.x * 0.22))
		_health.custom_minimum_size = Vector2(hw, 36.0)
		_health.size = Vector2(hw, 36.0)
		_health.position = Vector2(round(safe.position.x + 12.0), round(safe.position.y + 4.0))
	if _manual_row == null:
		return 0.0
	_manual_row.visible = not touch_mode
	_manual_row.reset_size()
	var w: float = _manual_row.get_combined_minimum_size().x
	var h: float = _manual_row.get_combined_minimum_size().y
	_manual_row.position = Vector2(round(safe.position.x + 12.0), round(safe.end.y - h - 10.0))
	_manual_row.size = Vector2(w, h)
	return 0.0 # 전장에 빌드 줄을 두지 않으므로 터치 스틱 영역을 밀어낼 높이도 없다

## 지금 조작 아이콘 묶음이 차지하는 화면 영역(가림 검사용). 터치면 빈 사각형
func manual_rect() -> Rect2:
	if _manual_row == null or not _manual_row.visible:
		return Rect2()
	return Rect2(_manual_row.position, _manual_row.size)

func health_rect() -> Rect2:
	if _health == null:
		return Rect2()
	return Rect2(_health.position, _health.size)

# ---------- 갱신(매 프레임, 읽기 전용) ----------
func update_from(state: CombatState) -> void:
	if state != null and state.get_instance_id() != _ready_bound_st:
		sync_ready_silent(state) # 새 전투·저장 복구: 이미 준비된 기술에 알림이 터지지 않게 먼저 맞춘다
	st = state
	if st == null or _manual.is_empty():
		return
	_hide_legacy_health()
	_update_health()
	_update_manual(st.t)

func _update_health() -> void:
	if _health == null:
		return
	var p: Dictionary = st.player
	var shield: float = float(p.shield) # ward_shield는 shield 총량의 구성분이라 다시 더하지 않는다(F2)
	_health.set_values(float(p.hp), float(p.hp_max), shield, maxf(float(p.shield_max), shield))

func _update_manual(now: float) -> void:
	var p: Dictionary = st.player
	var P: Dictionary = st.cfg.player
	var b: Dictionary = st.build
	# '사용 불가': 규칙이 실제로 입력을 받지 않는 동안(등장 연출 intro · 전투 종료). 미보유·재사용 대기와 다른 표시다.
	_blocked = st.intro > 0.0 or st.status != "running"
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
		te.state = PIconTile.ST_NONE
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
	# 준비 신호는 '재사용 대기 종료'만 본다: 연출이 끝났다고 알림이 터지면 안 된다
	var is_ready: bool = left <= 0.0 and not disabled_v
	if disabled_v or _blocked:
		t.state = PIconTile.ST_UNUSABLE
	elif is_ready:
		t.state = PIconTile.ST_READY
	else:
		t.state = PIconTile.ST_COOLDOWN
	if bool(_ready_state.get(ability, true)) != is_ready:
		_ready_state[ability] = is_ready
		if is_ready:
			_ready_flash[ability] = now
			ready_signal.emit(ability)
	t.flash_t = float(_ready_flash.get(ability, -1.0))
	t.queue_redraw()

## 조작 아이콘의 지금 상태("none"|"unusable"|"cooldown"|"ready"). 시험·검증용
func ability_state(ability: String) -> String:
	var t: PIconTile = _manual.get(ability, null)
	return String(t.state) if t != null else ""

func manual_tile(ability: String) -> PIconTile:
	return _manual.get(ability, null)

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

## 방금 선택으로 바뀐 칸 강조: 자동기술 칸이 전장에 없으므로 전투 HUD에서는 아무것도 하지 않는다.
## 같은 강조는 거점 '현재 빌드'(PUi.build_icon_row)와 일시정지의 '내 빌드'가 보여 준다.
func highlight_slot(_slot: String, _seconds: float = 1.2) -> void:
	pass

func bound_state_id() -> int:
	return _ready_bound_st

func ready_state() -> Dictionary:
	return _ready_state.duplicate()
