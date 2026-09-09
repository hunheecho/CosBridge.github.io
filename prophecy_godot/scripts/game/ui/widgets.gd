class_name PUi
extends RefCounted
## 화면 공용 위젯 헬퍼(코드로 만드는 Control). 색·글자 크기·카드 모양은 여기서만 정한다.
## 규칙 수치는 절대 여기서 계산하지 않는다(화면은 PRun/PBuild/PGrowth가 준 값을 보여 주기만 한다).

const BG := Color(0.078, 0.094, 0.114)
const CARD := Color(0.13, 0.15, 0.18)
const CARD_ON := Color(0.15, 0.2, 0.17)
const CARD_OFF := Color(0.11, 0.12, 0.13)
const CARD_BOSS := Color(0.2, 0.14, 0.14)
const DIM := Color(0.62, 0.66, 0.72)
const GOLD := Color(1.0, 0.85, 0.4)
const WARN := Color(1.0, 0.55, 0.45)
const OK := Color(0.6, 0.9, 0.6)
const LINK := Color(0.65, 0.85, 1.0)

static func stylebox(color: Color, radius: int = 6, margin: int = 8, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(float(margin))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb

static func label(text: String, size: int = 14, color: Color = Color.WHITE, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## 용어 링크({{id}}·[url=id])가 살아 있는 본문. 툴팁 층에 연결된다
static func rich(text: String, size: int = 14, color: Color = Color.WHITE) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 손가락 끌기를 여기서 삼키면 바깥 스크롤이 못 받는다. 글상자는 누르는 대상이 아니므로 위로 넘긴다
	# (친구 보고: "스크롤이 화면 사이로 드래그해야만 됨" — 카드 사이 틈에서만 스크롤됐다)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_size_override("normal_font_size", PLayout.fs(size))
	r.add_theme_font_size_override("bold_font_size", PLayout.fs(size))
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	r.text = PGlossaryTip.markup(text)
	PGlossaryTip.bind(r)
	return r

## 줄바꿈 없는 짧은 본문(상단 줄·표 칸): 내용 너비만 차지한다
static func rich_nowrap(text: String, size: int = 14, color: Color = Color.WHITE) -> RichTextLabel:
	var r := rich(text, size, color)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.size_flags_horizontal = Control.SIZE_FILL
	return r

static func button(text: String, cb: Callable, enabled: bool = true, size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", PLayout.fs(size))
	b.custom_minimum_size = Vector2(b.custom_minimum_size.x, maxf(b.custom_minimum_size.y, PLayout.button_min_height()))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

static func spacer(h: int = 0) -> Control:
	var c := Control.new()
	if h > 0:
		c.custom_minimum_size = Vector2(0, h)
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## 카드: {panel: PanelContainer, box: VBoxContainer}. 제목이 있으면 첫 줄에 넣는다
static func card(title: String = "", color: Color = CARD, title_size: int = 15) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(color))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS  # 카드 판이 손가락 끌기를 삼키지 않게(스크롤이 위로 간다)
	var v := vbox(4)
	p.add_child(v)
	if title != "":
		v.add_child(rich("[b]%s[/b]" % title, title_size))
	return { "panel": p, "box": v }

## 키·값 한 줄(키는 흐리게)
static func kv(box: Control, key: String, val: String, size: int = 13) -> void:
	box.add_child(rich("[color=#9ea8b8]%s[/color]  %s" % [PGlossaryTip.esc(key), val], size))

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func fmt(n: float) -> String:
	var v: float = snapped(n, 0.1)
	if v == floor(v):
		return str(int(v))
	return str(v)

## 데이터의 서비스 이름은 '무료 휴식권'이지만, 화면에서는 '무료'가 아니라 '시간 소모 없음'으로 적는다.
## 사는 값이 100금이라 '무료'는 값을 오해하게 만든다(사용자 지시 2026-09-09). 이름 자체(data/missions.json)는 규칙 담당 몫이라 표시만 통일한다.
static func rest_ticket_name() -> String: return "휴식권"
static func rest_ticket_note() -> String: return "시간 소모 없음"

## 한국어 조사(을/를 · 은/는 · 이/가): 마지막 글자의 받침으로 고른다. 이름을 문장에 그대로 넣기 위한 표시 도우미
static func josa(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty():
		return without
	var code := word.unicode_at(word.length() - 1)
	if code < 0xAC00 or code > 0xD7A3:
		return without
	return with_batchim if (code - 0xAC00) % 28 != 0 else without

## 장착·해제 전후로 실제로 바뀌는 파생 수치(PBuild.derive 결과 두 개를 비교한다 — 여기서 계산하지 않는다)
static func diff_text(before: Dictionary, after: Dictionary) -> String:
	var parts := []
	parts.append("최대 체력 [b]%d → %d[/b]" % [int(float(before.hp_max)), int(float(after.hp_max))])
	parts.append("이동 [b]×%s → ×%s[/b]" % [fmt(float(before.speed_mult)), fmt(float(after.speed_mult))])
	if float(before.shield) != float(after.shield):
		parts.append("시작 보호막 %d → %d" % [int(float(before.shield)), int(float(after.shield))])
	if float(before.range_mult) != float(after.range_mult):
		parts.append("사거리 ×%s → ×%s" % [fmt(float(before.range_mult)), fmt(float(after.range_mult))])
	return " · ".join(parts)

## 무기 한 번의 공격이 실제로 어떻게 나가는가: "6 × 3연타 (간격 0.09초)"처럼 연타 수·간격까지 적는다.
## "피해 6"만 적으면 실제 화력을 절반 이하로 읽게 된다(사용자 지시 2026-09-09).
## 값은 PBuild.weapon_stats가 준 파생 수치를 읽기만 한다 — 여기서 곱하거나 더하지 않는다.
static func weapon_damage_text(wd: Dictionary) -> String:
	var dmg := fmt(float(wd.get("damage", 0.0)))
	var hits := int(wd.get("hits", 1))
	var count := int(wd.get("count", 1))
	var hops := int(wd.get("hops", 1))
	var gap := float(wd.get("hitGap", 0.0))
	if hits > 1:
		return "%s × %d연타%s" % [dmg, hits, (" (간격 %s초)" % fmt(gap)) if gap > 0.0 else ""]
	if count > 1:
		return "%s × 칼날 %d개%s" % [dmg, count, (" (같은 적 %s초마다)" % fmt(gap)) if gap > 0.0 else ""]
	if hops > 1:
		return "%s · 최대 %d번 튕김" % [dmg, hops]
	return dmg

## 공격 구조 · 주기 · 사거리 한 줄
static func weapon_stats_text(wd: Dictionary) -> String:
	var parts := [weapon_damage_text(wd), "주기 %s초" % fmt(float(wd.get("interval", 0.0)))]
	if float(wd.get("range", 0.0)) > 0.0:
		parts.append("사거리 %d" % int(round(float(wd.range))))
	return " · ".join(parts)

## 카탈로그 기본값(회차 밖·상점 후보)용 공격 구조 한 줄. base 사전을 그대로 읽는다
static func weapon_base_text(base: Dictionary) -> String:
	return weapon_stats_text(base)

## 아이콘 칸을 누를 수 있게 만든다: 그리기는 PIconTile 그대로, 위에 같은 크기의 평평한 Button을 씌운다.
## PC 클릭·터치 탭·키보드 포커스가 모두 같은 경로로 들어온다(사용자 지시: 같은 정보에 두 방식 모두로 닿는다).
static func icon_pick(tile: PIconTile, cb: Callable, hint: String = "") -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = tile.custom_minimum_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = hint
	if cb.is_valid():
		b.pressed.connect(cb)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(tile)
	return b

static func mats_text(mats: Dictionary) -> String:
	var parts := []
	var M := PCatalog.materials()
	for k in mats:
		if int(mats[k]) > 0:
			parts.append("%s %d" % [String(M[String(k)].name), int(mats[k])])
	return ", ".join(parts)

static func balance_name(run: Dictionary) -> String:
	var BS := PCatalog.balance_sets()
	var bal := String(run.get("balance", "current"))
	return String(BS[bal].name) if BS.has(bal) else bal

## 자동 로드 Game 없이도(헤드리스 -s 시험) 버전 문자열을 읽는다
static var _stamp_cache := ""
static var _stamp_read := false

## 화면에 보이는 판본. 배포한 빌드에는 커밋 표식이 괄호로 붙는다(예: godot-1.1.0 (2396eda)).
## 폰에서 "지금 보는 것이 어느 판인가"를 이 한 줄로 가른다.
## 화면에 보이는 판본. **우리가 정한 번호만** 보여 준다(예: v1.1.1).
## 예전에는 뒤에 커밋 해시를 붙였는데(v1.1.0 (dafc8bc)) 사람이 읽고 말하기 나빴다.
## 해시는 추적용이라 설정 화면과 version.json 에만 남긴다 — build_stamp()로 따로 읽는다.
static func version() -> String:
	var gs: GDScript = load("res://scripts/game/game.gd")
	return "v" + String(gs.get_script_constant_map().get("VERSION", "?"))

## 판본 + 커밋 표식(설정 화면·기록용). 개발 중 실행에는 해시가 없어 판본만 나온다
static func version_full() -> String:
	var b := build_stamp()
	return version() if b == "" else "%s · 빌드 %s" % [version(), b]

## 내보내기 도구가 남기는 배포 표식(res://data/build.json). 개발 중 실행에는 없다 → 빈 문자열.
## 규칙에 영향이 없는 표시 전용 값이라 PCatalog에 태우지 않고 직접 읽는다.
static func build_stamp() -> String:
	if _stamp_read:
		return _stamp_cache
	_stamp_read = true
	if not FileAccess.file_exists("res://data/build.json"):
		return _stamp_cache
	var f := FileAccess.open("res://data/build.json", FileAccess.READ)
	if f == null:
		return _stamp_cache
	var txt := f.get_as_text()
	f.close()
	var j = JSON.parse_string(txt)
	if typeof(j) != TYPE_DICTIONARY:
		return _stamp_cache
	_stamp_cache = String((j as Dictionary).get("build", ""))
	return _stamp_cache

static func settings_short(run: Dictionary) -> String:
	return "%s · %s · 시드 %d" % [version(), balance_name(run), int(run.get("seed", 0))]

## 글꼴 고지. SIL OFL 1.1은 저작권 표시와 라이선스를 함께 배포하라고 요구하므로 화면에서도 보이게 둔다.
## 정본 문자열은 game.gd의 상수이고(자동 로드 없이도 읽는다), 전문은 assets/fonts/OFL.txt에 함께 담긴다.
static func font_notice() -> String:
	var gs: GDScript = load("res://scripts/game/game.gd")
	return String(gs.get_script_constant_map().get("UI_FONT_NOTICE", ""))

static func font_notice_short() -> String:
	var gs: GDScript = load("res://scripts/game/game.gd")
	return String(gs.get_script_constant_map().get("UI_FONT_NOTICE_SHORT", ""))

## 라이선스 전문이 담긴 경로(내보내기에 함께 들어간다)
static func font_license_path() -> String:
	var gs: GDScript = load("res://scripts/game/game.gd")
	return String(gs.get_script_constant_map().get("UI_FONT_LICENSE_PATH", ""))

## 거점·상점 공용 상단 줄(HTML header): 날짜 · 시간대 · 보스 · 체력 · 금화 · 설정
##
## 터치에서는 **한 줄로 밀어 넣지 않고 접는다**(2026-09-09 실제 브라우저, 폰 가로 640×360 · 글자 배율 1.6배):
## HBoxContainer는 넘쳐도 줄을 바꾸지 않아서 오른쪽 끝의 **체력·금화가 화면 밖으로 밀려 아예 안 보였다.**
## 글자를 줄여서 맞추지 않는다 — 자리가 모자라면 다음 줄로 넘긴다(사용자 지시).
## PC는 예전 그대로 HBox 한 줄이다.
static func header(run: Dictionary) -> Control:
	var b := PBuild.derive(run)
	var wrap: bool = PLayout.is_touch()
	var h: Container
	if wrap:
		var fc := HFlowContainer.new()
		fc.add_theme_constant_override("h_separation", 14)
		fc.add_theme_constant_override("v_separation", 2)
		h = fc
	else:
		h = hbox(14)
	var act_lbl := PRun.act_label(run)
	h.add_child(rich_nowrap("[color=#9ea8b8]%s[/color] [b]%s%d일차[/b]" % [PRun.schedule_short(run), (act_lbl + " · ") if act_lbl != "" else "", int(run.day)], 14))
	var slots := PRun.time_slots()
	var cur := PRun.slot_index(run)
	var done: bool = int(run.hours) <= 0
	var strip := ""
	for i in slots.size():
		var nm := String(slots[i])
		if done or i < cur:
			strip += "[color=#5a606a]%s[/color] " % nm
		elif i == cur:
			strip += "[color=#ffe066][b]%s[/b][/color] " % nm
		else:
			strip += "%s " % nm
	h.add_child(rich_nowrap("%s [color=#9ea8b8](남은 %d칸)[/color] %s" % [PGlossaryTip.term("timeslot", "시간대"), int(run.hours), strip.strip_edges()], 14))
	var nb := PRun.next_boss(run)
	var nbc := PRun.next_boss_cfg(run)
	var left := PRun.boss_days_left(run)
	var stages := PRun.stage_count(run)
	var when := "완료" if nb.is_empty() else ("%d일 뒤" % left if left > 0 else "오늘")
	var lbl := ("보스 %d/%d · %s" % [int(run.get("stage", 0)) + 1, stages, String(nbc.name)]) if stages > 1 and not nb.is_empty() else "보스"
	h.add_child(rich_nowrap("[color=#9ea8b8]%s[/color] [b]%s%s[/b]" % [lbl, ("[color=#ff8c73]" if left <= 1 and not nb.is_empty() else ""), when + ("[/color]" if left <= 1 and not nb.is_empty() else "")], 14))
	var ws := PRun.world_stage(run)
	if ws > 0:
		h.add_child(rich_nowrap("[color=#d24a3a][b]%s[/b][/color]" % PGlossaryTip.esc(String(PRun.world_stage_def(run).name)), 14))
	h.add_child(rich_nowrap("[color=#9ea8b8]체력[/color] [b]%d / %d[/b]" % [int(float(run.hp)), int(float(b.hp_max))], 14))
	h.add_child(rich_nowrap("[color=#9ea8b8]금화[/color] [color=#ffd966][b]%d[/b][/color]" % int(run.gold), 14))
	# 판본·시드는 **참고 정보**다. 줄바꿈을 허용하면 좁은 화면에서 한 글자씩 세로로 접혀
	# 머리줄이 화면 절반을 먹는다(폰 가로 854x400에서 실제로 그랬다). 접지 않고, 좁으면 아예 뺀다.
	if not wrap:
		h.add_child(spacer())
		h.add_child(rich_nowrap("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(settings_short(run)), 11))
	return h

## 장비 한 줄(이름은 용어 링크). id는 장비 **개체 id**("타입#번호")도 종류도 받는다 — 정의는 타입으로 찾는다.
## run을 주면 강화 단계를 이름 뒤에 붙인다("사냥꾼의 검 [color=..]+1[/color]")
static func equip_line(id: String, run: Dictionary = {}) -> String:
	var tid := PRun.equip_type_of(id)
	var d: Dictionary = PCatalog.equipment_def(tid)
	var plus: int = PRun.equip_plus_of(run, id) if not run.is_empty() else 0
	var ptxt := " [color=#ffd966][b]+%d[/b][/color]" % plus if plus > 0 else ""
	# short 문구는 +0 기준 값이다. 강화한 개체는 **지금 값**을 뒤에 덧붙인다(20이라 적어 놓고 26이 나오는 일이 없게)
	var now := equip_plus_now_text(tid, plus)
	return "[b]%s[/b]%s [color=#9ea8b8]%s[/color]%s" % [PGlossaryTip.term("eq:" + tid, String(d.name)), ptxt, PGlossaryTip.esc(String(d.short)),
		(" [color=#ffd966]→ 지금 %s[/color]" % now) if now != "" else ""]

## 지금 강화 단계에서의 실제 값("비상 보호막 26"). +0이거나 강화표가 없으면 ""
static func equip_plus_now_text(type_id: String, plus: int) -> String:
	var d: Dictionary = PCatalog.equipment_def(type_id)
	var up: Dictionary = d.get("upgrade", {})
	if plus <= 0 or up.is_empty():
		return ""
	var eff := PCatalog.equipment_eff(type_id, plus)
	var parts := []
	for path in up:
		var nm := String(d.get("upgradeName", {}).get(path, String(path)))
		var v := get_eff_at(String(path), { "eff": eff })
		var ratio: bool = _all_below_one(up[path]) and _all_below_one([get_eff_at(String(path), d)])
		parts.append("%s %s" % [nm, ("%d%%" % int(round(v * 100.0))) if ratio else fmt(v)])
	return " · ".join(parts)

## 장비 기본 능력치 / 고유 효과를 갈라 적은 두 줄(§8 상점 표시). 자료의 basic·unique 문구가 정본이다.
## 강화가 있으면 그 값이 어떻게 바뀌는지도 한 줄에 붙인다
static func equip_effect_lines(type_id: String, plus: int = 0) -> String:
	var d: Dictionary = PCatalog.equipment_def(type_id)
	var basic := String(d.get("basic", ""))
	var uniq := String(d.get("unique", ""))
	var up_txt := equip_upgrade_text(type_id, plus)
	var l1 := "[color=#7fd6a0]기본 능력치[/color] %s" % (PGlossaryTip.esc(basic) if basic != "" else "[color=#6a7078]없음[/color]")
	var l2 := "[color=#c9a0ff]고유 효과[/color] %s" % (PGlossaryTip.esc(uniq) if uniq != "" else "[color=#6a7078]없음[/color]")
	return "%s\n%s%s" % [l1, l2, ("\n" + up_txt) if up_txt != "" else ""]

## 배열의 값이 전부 1 미만인가(비율 항목 판정)
static func _all_below_one(a: Array) -> bool:
	for x in a:
		if absf(float(x)) >= 1.0:
			return false
	return true

## upgrade 경로("bigHit.reduce")가 가리키는 +0 값. 없으면 0
static func get_eff_at(path: String, d: Dictionary) -> float:
	var node: Variant = d.get("eff", {})
	for k in path.split(".", false):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(String(k)):
			return 0.0
		node = (node as Dictionary)[String(k)]
	return float(node) if typeof(node) == TYPE_FLOAT or typeof(node) == TYPE_INT else 0.0

## 강화 단계별 값 한 줄("강화 +1 → 최대 체력 27 · +2 → 34"). 강화표가 없으면 ""
static func equip_upgrade_text(type_id: String, plus: int = 0) -> String:
	var d: Dictionary = PCatalog.equipment_def(type_id)
	var up: Dictionary = d.get("upgrade", {})
	if up.is_empty():
		return "[color=#6a7078]강화 없음(이 장비는 단계로 오르는 기본 능력치가 없습니다)[/color]"
	var parts := []
	for path in up:
		var arr: Array = up[path]
		var nm := String(d.get("upgradeName", {}).get(path, String(path)))
		# 비율 항목(0.12 같은 값)은 소수점 한 자리로 적으면 +1과 +2가 같은 숫자로 보인다 — 백분율로 적는다.
		# 절대값 항목(최대 체력 27 같은 값)은 그대로 둔다
		var ratio: bool = _all_below_one(arr) and _all_below_one([float(get_eff_at(String(path), d))])
		var vals := []
		for i in arr.size():
			vals.append("+%d [b]%s[/b]" % [i + 1, ("%d%%" % int(round(float(arr[i]) * 100.0))) if ratio else fmt(float(arr[i]))])
		parts.append("%s %s" % [nm, " · ".join(vals)])
	return "[color=#ffd966]강화[/color] [color=#9ea8b8]%s%s[/color]" % [" / ".join(parts), (" · 지금 +%d" % plus) if plus > 0 else ""]

static func slot_name(slot: String) -> String:
	return String(PCatalog.world().equip_slot_names.get(slot, slot))

## 장비 패널(HTML equipPanel)
static func equip_panel(run: Dictionary) -> Control:
	var b := PBuild.derive(run)
	var c := card("%s [color=#9ea8b8]%s %d개[/color]" % [PGlossaryTip.term("equipment", "장비"), PGlossaryTip.term("bag", "가방"), (run.bag as Array).size()], CARD, 16)
	var box: VBoxContainer = c.box
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var id = run.equipment.get(slot, null)
		box.add_child(rich("[color=#9ea8b8]%s[/color]  %s" % [slot_name(slot), (equip_line(String(id), run) if id != null else "[color=#6a7078]비어 있음[/color]")], 15))
	# §16: 대장간 강화는 이제 **기술마다 따로**다. 예전에는 산 횟수(b.forge)를 "공용 공격 강화 N단계 · 피해 ×1.0"으로
	# 적어서, 무기 레벨과 같은 것처럼 보이면서 배율까지 틀렸다(새 구조에서 b.forge_mult는 늘 1.0이다).
	var forge_txt := ""
	var fbs: Dictionary = b.get("forge_by_skill", {})
	var fparts := []
	for w0 in b.weapons:
		var wid0 := String((w0 as Dictionary).id)
		var flv := int(fbs.get(wid0, 0))
		if flv > 0:
			fparts.append("%s %d단계(피해 ×%s)" % [String((w0 as Dictionary).name), flv, fmt(PBuild.forge_mult_of(b, wid0))])
	if fparts.size() > 0:
		forge_txt = " · %s: %s" % [PGlossaryTip.term("forge", "대장간 강화 단계"), ", ".join(fparts)]
	elif int(b.forge) > 0 and bool(b.get("forge_legacy", false)):
		forge_txt = " · %s %d단계(옛 전체 강화)" % [PGlossaryTip.term("forge", "대장간 강화 단계"), int(b.forge)]
	box.add_child(rich("[color=#9ea8b8]최대 체력 %d · 이동 ×%s · 시작 보호막 %d%s[/color]" % [int(float(b.hp_max)), fmt(float(b.speed_mult)), int(float(b.shield)), forge_txt], 14))
	return c.panel

## 레벨 + 경험치 진행 막대(§14). 전투 최상단(체력바 옆)과 **같은 위젯·같은 색**을 거점에서도 쓴다.
## 값은 규칙 사전(run.growth)과 PGrowth.xp_need만 읽는다 — 화면이 필요 경험치를 계산하지 않는다.
## 터치는 숫자를 빼고 레벨·막대를 크게, 데스크톱은 레벨과 수치를 함께 적는다.
static func xp_row(run: Dictionary) -> Control:
	var g: Dictionary = run.get("growth", {})
	var lv: int = int(g.get("level", 1))
	var bar := PXpBar.new()
	bar.compact = PLayout.is_touch()
	bar.bar_h = 24.0 * PLayout.cur_ui_scale()
	bar.level_fs = PLayout.fs(13)
	bar.num_fs = PLayout.fs(11)
	bar.custom_minimum_size = Vector2(160.0, bar.bar_h)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.set_values(lv, float(g.get("xp", 0.0)), float(PGrowth.xp_need(lv)), int(g.get("pendingLevelUps", 0)))
	return bar

## 성장 패널(HTML buildPanel): 실제 파생 수치(PBuild.derive)만 표시
static func build_panel(run: Dictionary) -> Control:
	var b := PBuild.derive(run)
	var g: Dictionary = run.growth
	var S: Dictionary = PCatalog.growth().SLOTS
	var pend := int(g.pendingLevelUps)
	var c := card("성장 [color=#9ea8b8]Lv %d · 경험치 %d/%d%s[/color]" % [int(g.level), int(floor(float(g.xp))), PGrowth.xp_need(int(g.level)), (" · [color=#ff8c73]미처리 레벨업 %d[/color]" % pend) if pend > 0 else ""])
	var box: VBoxContainer = c.box
	box.add_child(xp_row(run))   # 전투 상단과 같은 진행 막대(§14)
	if g.get("steer", null) != null:
		box.add_child(rich("[color=#ffe066]%s[/color] 다음 레벨업은 [b]%s[/b] 후보만 제시 (%s, 1회)" % [PGlossaryTip.term("steer", "성장 예약"), PSortie.kind_name(String(g.steer.kind)), "심층 보상" if String(g.steer.get("from", "")) == "deep" else "임무 보상"], 12))
	box.add_child(rich("[b]%s %d/%d[/b]" % [PGlossaryTip.term("auto_skill", "자동기술"), (b.weapons as Array).size(), int(S.weapons)], 15))
	for w in b.weapons:
		var wd: Dictionary = w
		var mods := []
		for mid in wd.mods:
			mods.append(String(wd.def.mods[String(mid)].name))
		# 상한은 그 무기의 규칙값이다(주무기 Lv5·개조 2 / 보조 Lv3·개조 1). 화면이 숫자를 지어내지 않는다
		var cap_lv := PGrowth.level_cap(g, String(wd.id))
		var cap_md := PGrowth.mod_cap(g, String(wd.id))
		var kind_tag := ""
		if PGrowth.is_v2(g):
			kind_tag = "[color=#8a93a6]%s[/color] " % ("주무기" if PCatalog.is_main_weapon(String(wd.id)) else "보조")
		# §16: 무기 레벨(레벨업 3택)과 대장간 강화 단계(금화)를 같은 줄에서 **이름을 붙여** 갈라 적는다
		var flv2 := int((b.get("forge_by_skill", {}) as Dictionary).get(String(wd.id), 0))
		var fstage: String = " · [color=#6a7078]대장간 강화 0단계[/color]"
		if flv2 > 0:
			fstage = " · %s [b]%d단계[/b]" % [PGlossaryTip.term("forge", "대장간 강화"), flv2]
		box.add_child(rich("  %s[b]%s[/b] 레벨 Lv%d/%d%s [color=#9ea8b8]%s[/color] · %s %d/%d: %s" % [kind_tag, PGlossaryTip.term("w:" + String(wd.id), String(wd.name)), int(wd.level), cap_lv, fstage, weapon_stats_text(wd), PGlossaryTip.term("mod", "개조"), mods.size(), cap_md, (", ".join(mods) if mods.size() > 0 else "없음")], 14))
	for i in int(S.weapons) - (b.weapons as Array).size():
		box.add_child(rich("  [color=#6a7078]빈 자동기술 슬롯[/color]", 14))
	box.add_child(rich("[b]수동 기술 Q/E[/b] [color=#9ea8b8]보조무기(자동)와 다른 칸입니다[/color]", 15))
	for slot in PGrowth.SKILL_SLOTS:
		var sl := String(slot)
		var sk = g.skills.get(sl)
		if sk == null:
			box.add_child(rich("  [b]%s[/b]: [color=#6a7078]비어 있음[/color]" % sl.to_upper(), 14))
			continue
		var d: Dictionary = PCatalog.skills()[String(sk.id)]
		var cd := PBuildDetail.cd_of_build(b, sl)
		var vtxt := (" · 변형: " + String(d.variants[String(sk.variant)].name)) if sk.get("variant", null) != null else ""
		box.add_child(rich("  [b]%s[/b]: [b]%s[/b] Lv%d/%d [color=#9ea8b8]재사용 %s초%s[/color]" % [sl.to_upper(), PGlossaryTip.term(skill_term(String(sk.id)), String(d.name)), int(sk.level), int(S.skillMax), fmt(cd), vtxt], 14))
	var commons := []
	var CM := PCatalog.commons()
	for k in g.commons:
		if int(g.commons[k]) > 0:
			var cd2: Dictionary = CM[String(k)]
			commons.append("[b]%s[/b]%s" % [String(cd2.name), (" %d/%d" % [int(g.commons[k]), int(cd2.max)]) if int(cd2.max) > 1 else ""])
	var passives := []
	var PS := PCatalog.passives()
	for k in g.passives:
		if int(g.passives[k]) > 0:
			passives.append("[b]%s[/b] %d/%d" % [String(PS[String(k)].name), int(g.passives[k]), int(PS[String(k)].max)])
	var rewards := []
	for id in g.bossRewards:
		rewards.append("[b]%s[/b]" % String(PCatalog.boss_rewards()[String(id)].name))
	box.add_child(rich("%s %d/%d: %s · %s %d/%d: %s%s" % [PGlossaryTip.term("common", "공용 증강"), PGrowth.common_count(g), int(S.commons), (", ".join(commons) if commons.size() > 0 else "[color=#6a7078]없음[/color]"), PGlossaryTip.term("passive", "패시브"), PGrowth.passive_count(g), int(S.passives), (", ".join(passives) if passives.size() > 0 else "[color=#6a7078]없음[/color]"), (" · 희귀 보상: " + ", ".join(rewards)) if rewards.size() > 0 else ""], 14))
	return c.panel

## 피해 통계 표 하나(PStats.aggregate 결과)
static func stats_table(a: Dictionary, title: String) -> Control:
	var v := vbox(2)
	if int(a.n) == 0:
		v.add_child(rich("[b]%s[/b] [color=#9ea8b8]기록 없음[/color]" % title, 13))
		return v
	v.add_child(rich("[b]%s[/b] [color=#9ea8b8]전투 %d회 · 실제 전투 %s초 · 총 유효 피해 %s · 전체 DPS %s · 받은 피해 %s[/color]" % [title, int(a.n), str(a.elapsed), str(a.total), str(a.dpsAll), str(a.taken)], 13))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	var heads := ["출처", "분류", PGlossaryTip.term("effective", "유효 피해"), "비중", "보유 시간", PGlossaryTip.term("dps", "DPS")]
	for hd in heads:
		var hl := rich("[color=#9ea8b8]%s[/color]" % String(hd), 12)
		hl.fit_content = true
		hl.size_flags_horizontal = Control.SIZE_FILL
		hl.custom_minimum_size = Vector2(90, 0)
		grid.add_child(hl)
	for r in a.rows:
		var row: Dictionary = r
		var cells := [PGlossaryTip.esc(String(row.name)), "[color=#9ea8b8]%s[/color]" % String(PStats.CATS.get(String(row.cat), row.cat)), str(row.amount), "%s%%" % str(row.share), "%s초" % str(row.active), "[b]%s[/b]" % str(row.dps)]
		for ctext in cells:
			var cl := rich(String(ctext), 12)
			cl.size_flags_horizontal = Control.SIZE_FILL
			cl.custom_minimum_size = Vector2(90, 0)
			grid.add_child(cl)
	v.add_child(grid)
	var cats := []
	for k in a.cats:
		cats.append("%s %s" % [String(PStats.CATS.get(String(k), k)), str(a.cats[k])])
	v.add_child(rich("[color=#9ea8b8]분류별: %s[/color]" % " · ".join(cats), 11))
	return v

# ---------- 아이콘 기반 빌드 표시(전투 HUD와 같은 구성 요소) ----------
## 자동기술 3칸 + 각 칸 아래 개조 2칸. 소속은 위치로만 나타낸다(공용 증강 아이콘을 기술마다 복제하지 않는다).
## highlight = 방금 바뀐 칸("w<i>" 또는 "w<i>:m<j>")을 잠깐 강조한다(선택 직후 어떤 칸이 바뀌었는지 보이게).
## on_pick(kind, id)가 valid면 각 칸이 눌리는 버튼이 된다(kind = "weapon"|"mod", id = 무기 id 또는 "무기:개조").
## 현재 빌드 아이콘. **주무기 영역과 보조무기 영역을 제목과 배치로 갈라서** 그린다.
##
## 왜 다시 썼나(2026-09-09 사람 플레이 지적): 예전에는 growth().SLOTS의 옛 평면 구조
## (무기 3칸 · 전부 최대 Lv5 · 전부 개조 2칸)를 읽어서, 주무기 전투망치와 보조 회전 칼날·
## 서리 수정이 **같은 위계로 나열**되고 보조가 Lv1/5로 표시되며 보조 아래 **없는 개조 칸이
## 2개씩** 그려졌다. 확정 구조는 주무기 1(Lv5·개조 2) + 보조 2(각 Lv3·개조 1)다.
##
## 표시값은 전부 **규칙 자료**(PCatalog.slot_rules = data/supports.json slots)에서 읽는다.
## 문구만 5→3으로 바꾸지 않는다 — 자료가 바뀌면 화면도 따라 바뀐다.
## 개조 칸은 세 가지를 구분한다: 가진 것 · 자격은 열렸지만 아직 안 고른 것(미획득) ·
## 아직 자격이 없는 것(Lv? 필요). **자격이 열린 것이 자동으로 들어온 것처럼 보이면 안 된다.**
static func build_icon_row(run: Dictionary, icon_px: float = 44.0, mod_px: float = 26.0, highlight: String = "", on_pick: Callable = Callable()) -> Control:
	# **growth가 없는 사전이 들어올 수 있다.** 3택 창은 `run.get("growth", {})`로 방어하고 있었는데
	# 내가 여기서 `run.growth`를 바로 읽어 그 경로가 죽었다 — 임무 승리 뒤 3택이 뜨는 순간
	# 화면이 통째로 검게 나갔다(2026-09-09 친구 보고: "봉인 100% 채웠더니 화면 날라감").
	var g_all: Dictionary = run.get("growth", {})
	if g_all.is_empty():
		return vbox(0)
	var b := PBuild.derive(run)
	var R := PCatalog.slot_rules()
	var mains := []
	var sups := []
	for w in (b.weapons as Array):
		if PCatalog.is_main_weapon(String((w as Dictionary).id)):
			mains.append(w)
		else:
			sups.append(w)
	var root := vbox(8)
	root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := hbox(16)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# **옛 저장(v1)은 주무기·보조 구분이 없다.** 그런 회차에 새 제목을 붙이면 거짓말이 되므로
	# 예전처럼 한 덩어리로 그린다(상한도 그 회차의 규칙을 따른다)
	if not PGrowth.is_v2(g_all):
		var S: Dictionary = PCatalog.growth().SLOTS
		row.add_child(_slot_group(run, "자동기술", b.weapons as Array, int(S.weapons),
			int(S.weaponMax), int(S.weaponMods), PCatalog.growth().get("MOD_UNLOCK_LEVEL", [2, 4]),
			icon_px, mod_px, highlight, on_pick))
		root.add_child(row)
		return root
	row.add_child(_slot_group(run, "주무기", mains, int(R.get("main", 1)), int(R.get("mainMax", 5)),
		int(R.get("mainMods", 2)), R.get("modUnlockMain", [2, 4]), icon_px + 10.0, mod_px, highlight, on_pick))
	row.add_child(_group_sep())
	row.add_child(_slot_group(run, "보조무기", sups, int(R.get("supports", 2)), int(R.get("supportMax", 3)),
		int(R.get("supportMods", 1)), R.get("modUnlockSupport", [2]), icon_px, mod_px, highlight, on_pick))
	root.add_child(row)
	return root

## 두 영역 사이의 세로 줄. 색만이 아니라 **선과 간격**으로도 갈라 보이게 한다
static func _group_sep() -> Control:
	var sep := VSeparator.new()
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sep.add_theme_constant_override("separation", 2)
	return sep

## 한 영역(주무기 또는 보조무기). 제목 한 줄 + 칸들
static func _slot_group(run: Dictionary, title: String, ws: Array, slots: int, lv_max: int, mod_slots: int,
		unlock: Variant, icon_px: float, mod_px: float, highlight: String, on_pick: Callable) -> Control:
	var col := vbox(4)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# 좁은 화면(터치)에서는 설명을 줄인다. 긴 문구는 1.6배 글자에서 두 줄로 접혀 칸을 밀어낸다
	var cap := ""
	if PLayout.is_touch():
		cap = "%d칸 · Lv%d · 개조%d" % [slots, lv_max, mod_slots]
	elif slots > 1:
		cap = "%d칸 · 각 최대 Lv%d · 개조 %d" % [slots, lv_max, mod_slots]
	else:
		cap = "%d칸 · 최대 Lv%d · 개조 %d" % [slots, lv_max, mod_slots]
	col.add_child(rich("[b]%s[/b] [color=#8a93a6]%s[/color]" % [title, cap], 13))
	var row := hbox(10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var g_ws: Array = (run.get("growth", {}) as Dictionary).get("weapons", [])
	for i in slots:
		var wd: Dictionary = ws[i] if i < ws.size() else {}
		var wid := String(wd.get("id", ""))
		# 강조 열쇠는 growth.weapons 의 자리번호를 쓴다(main.gd가 그 번호로 만든다)
		var gi := -1
		for k in g_ws.size():
			if String((g_ws[k] as Dictionary).id) == wid:
				gi = k
				break
		var one := vbox(3)
		one.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var tile := PIconTile.new("", PIconTile.STYLE_AUTO)
		tile.set_icon_px(icon_px, icon_px + 46.0, 2)
		if wid != "":
			tile.key = PIcons.weapon_key(wid)
			tile.title = String(wd.get("name", wid))
			# 상한은 **그 회차의 규칙**이 정한다(PGrowth가 v1/v2와 주무기/보조를 함께 본다)
			tile.sub = "Lv%d/%d" % [int(wd.get("level", 1)), PGrowth.level_cap(run.get("growth", {}), wid)]
		else:
			tile.empty = true
			tile.title = "빈 슬롯"
		if gi >= 0 and highlight == "w%d" % gi:
			tile.now_t = 0.0
			tile.flash_t = 0.0
		if on_pick.is_valid() and wid != "":
			one.add_child(icon_pick(tile, func(): on_pick.call("weapon", wid), tile.title))
		else:
			one.add_child(tile)
		var mods: Array = wd.get("mods", [])
		var lv := int(wd.get("level", 1))
		# 개조 칸 수와 자격 레벨도 규칙에서 읽는다. 빈 자리는 영역 기본값을 쓴다
		var slots_here: int = PGrowth.mod_cap(run.get("growth", {}), wid) if wid != "" else mod_slots
		var unlock_here: Variant = PGrowth.mod_unlock_levels(run.get("growth", {}), wid) if wid != "" else unlock
		var mrow := hbox(4)
		mrow.alignment = BoxContainer.ALIGNMENT_CENTER
		mrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for j in slots_here:                                  # **없는 칸은 아예 그리지 않는다**
			var mt := PIconTile.new("", PIconTile.STYLE_MOD)
			mt.set_icon_px(mod_px, mod_px + 34.0, 2)
			mt.wrap_title = true
			var mid_here := ""
			if j < mods.size():
				mid_here = String(mods[j])
				mt.key = PIcons.mod_key(wid, mid_here)
			else:
				mt.empty = true
				var need := _mod_unlock_lv(unlock_here, j)
				if wid == "":
					mt.title = ""
				elif lv >= need:
					mt.title = "미획득"                        # 자격은 열렸다. **자동으로 들어오지 않는다**
				else:
					mt.title = "Lv%d 필요" % need              # 아직 자격이 없다
					mt.dimmed = true
			if gi >= 0 and highlight == "w%d:m%d" % [gi, j]:
				mt.now_t = 0.0
				mt.flash_t = 0.0
			if on_pick.is_valid() and mid_here != "":
				var pair := "%s:%s" % [wid, mid_here]
				mrow.add_child(icon_pick(mt, func(): on_pick.call("mod", pair), PIcons.name_of(mt.key)))
			else:
				mrow.add_child(mt)
		one.add_child(mrow)
		row.add_child(one)
	col.add_child(row)
	return col

## j번째 개조 칸이 열리는 레벨. 목록이 짧으면 마지막 값을 쓴다(자료가 늘어도 화면이 안 깨지게)
static func _mod_unlock_lv(unlock: Variant, j: int) -> int:
	var arr: Array = unlock if typeof(unlock) == TYPE_ARRAY else []
	if arr.is_empty():
		return 2
	return int(arr[j]) if j < arr.size() else int(arr[arr.size() - 1])

## 수동 기술 용어 사전 키. 감속장만 옛 키("slowfield")를 그대로 쓴다(용어 항목을 옮기지 않기 위해서다)
static func skill_term(skill_id: String) -> String:
	return "slowfield" if skill_id == "slowfield" else "e:" + skill_id

## 수동 기술 3칸(Space · Q · E) 아이콘. 전투 HUD와 같은 순서·같은 아이콘을 거점에서도 쓴다.
## on_pick(kind, id)가 valid면 눌리는 버튼이 된다(kind = "manual", id = "dodge"|"q"|"e").
static func manual_icon_row(run: Dictionary, icon_px: float = 32.0, on_pick: Callable = Callable()) -> Control:
	var g: Dictionary = run.growth
	var h := hbox(6)
	h.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for spec in [["dodge", "action:dodge", "Space", "회피"], ["q", "", "Q", ""], ["e", "", "E", ""]]:
		var slot := String(spec[0])
		var t := PIconTile.new(String(spec[1]), PIconTile.STYLE_MANUAL)
		t.key_label = String(spec[2])
		t.title = String(spec[3])
		t.set_icon_px(icon_px, icon_px + 46.0, 2)
		t.wrap_title = true
		if slot != "dodge":
			var sk = g.skills.get(slot)
			if sk == null:
				t.empty = true
				t.title = "비어 있음"
			else:
				var d: Dictionary = PCatalog.skills()[String(sk.id)]
				t.key = PIcons.e_key(String(sk.id), sk.get("variant", null)) # 칸이 아니라 기술 id가 아이콘을 정한다
				t.title = String(d.name)
				t.sub = "Lv%d" % int(sk.level)
		if on_pick.is_valid() and not t.empty:
			h.add_child(icon_pick(t, func(): on_pick.call("manual", slot), t.title))
		else:
			h.add_child(t)
	return h

## 장비 3칸(자동기술과 다른 영역임이 보이도록 제목 줄 + 테두리 카드로 감싼다).
## on_pick(kind, id)가 valid면 각 칸이 눌리는 버튼이 된다(kind = "equip", id = 슬롯 이름).
static func equip_icon_row(run: Dictionary, icon_px: float = 32.0, on_pick: Callable = Callable()) -> Control:
	var slot_names := []
	for sl0 in PCatalog.world().equip_slots:
		slot_names.append(slot_name(String(sl0))) # 칸 이름과 제목이 어긋나지 않게 같은 곳에서 읽는다
	var c := card("%s [color=#9ea8b8]%s[/color]" % [PGlossaryTip.term("equipment", "장비"), " · ".join(slot_names)], CARD_OFF, 15)
	var box: VBoxContainer = c.box
	var row := hbox(6)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var id = run.equipment.get(slot, null)
		# 아이콘 키·정의는 **타입**으로 찾고, 이름에는 그 개체의 강화 단계를 붙인다(§4)
		var t := PIconTile.new(("equip:" + PRun.equip_type_of(String(id))) if id != null else "", PIconTile.STYLE_EQUIP)
		t.empty = id == null
		t.title = PRun.equip_display_name(run, String(id)) if id != null else slot_name(slot)
		t.sub = "" # 슬롯 이름은 카드 제목(무기 · 방어구 · 방패)이 말한다 — 이름 줄을 두 줄로 쓴다
		t.set_icon_px(icon_px, icon_px + 46.0, 2)
		t.wrap_title = true
		if on_pick.is_valid():
			row.add_child(icon_pick(t, func(): on_pick.call("equip", slot), t.title))
		else:
			row.add_child(t)
	box.add_child(row)
	return c.panel

## 공용 증강·패시브 보조 줄(한 항목당 아이콘 1개). 어느 기술에 적용되는지는 빌드 상세에서만 연결해 보여 준다
## on_pick(kind, id)가 valid면 각 칸이 눌리는 버튼이 된다(kind = "common"|"passive").
static func common_icon_row(run: Dictionary, icon_px: float = 24.0, on_pick: Callable = Callable()) -> Control:
	var g: Dictionary = run.growth
	var h := hbox(4)
	h.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var n := 0
	for k in g.get("commons", {}):
		if int(g.commons[k]) > 0:
			var cid := String(k)
			var t := PIconTile.new("common:" + cid, PIconTile.STYLE_SMALL)
			t.set_icon_px(icon_px, icon_px, 0)
			t.badge = str(int(g.commons[k])) if int(g.commons[k]) > 1 else ""
			if on_pick.is_valid():
				h.add_child(icon_pick(t, func(): on_pick.call("common", cid), String(PCatalog.commons()[cid].name)))
			else:
				h.add_child(t)
			n += 1
	for k in g.get("passives", {}):
		if int(g.passives[k]) > 0:
			var pid := String(k)
			var t2 := PIconTile.new("passive:" + pid, PIconTile.STYLE_SMALL)
			t2.set_icon_px(icon_px, icon_px, 0)
			t2.badge = str(int(g.passives[k]))
			if on_pick.is_valid():
				h.add_child(icon_pick(t2, func(): on_pick.call("passive", pid), String(PCatalog.passives()[pid].name)))
			else:
				h.add_child(t2)
			n += 1
	if n == 0:
		# 이 줄은 폭을 최소로 잡는 HBox 안에 있다. 줄바꿈이 켜져 있으면 한 글자씩 세로로 접혀 큰 빈칸이 생긴다
		h.add_child(rich_nowrap("[color=#6a7078]공용 증강·패시브 없음[/color]", 11))
	return h

## 아이콘 1칸(선택 카드·상점에서 항목 하나를 크게 보일 때)
## lines = -1이면 자동(이름/보조 유무로 결정), 0이면 글자 없이 아이콘만(옆에 이미 이름이 적혀 있을 때)
static func icon_of(key: String, px: float, title: String = "", sub: String = "", width: float = 0.0, lines: int = -1) -> PIconTile:
	var t := PIconTile.new(key, PIconTile.STYLE_AUTO)
	t.title = title
	t.sub = sub
	var n: int = lines
	if n < 0:
		n = 1 if (title != "" or key != "") else 0
		if sub != "":
			n = 2
	t.set_icon_px(px, maxf(px, width), n)
	return t
