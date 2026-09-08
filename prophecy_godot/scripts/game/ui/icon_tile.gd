class_name PIconTile
extends Control
## 아이콘 한 칸(표시 전용). 전투 HUD·마을·선택 카드·상점이 모두 이 위젯을 쓴다.
## 그리는 것: 바탕 → (아이콘 그림 | 중립 자리표시 기호) → 쿨다운 가림막·남은 초 → 준비 완료 테두리 점등 → 이름·Lv·키 라벨.
##
## 규칙: 아이콘이 없는 ID는 다른 효과의 아이콘으로 대체하지 않는다. 자리표시는 항상 같은 중립 회색 마름모이고 실제 한국어 이름을 함께 쓴다.
## 자동기술 칸(STYLE_AUTO)은 눌리는 버튼처럼 보이지 않는다(테두리 얇음·눌림 표현 없음). 수동 버튼(STYLE_MANUAL)만 키 라벨과 두꺼운 테두리를 가진다.
## 애니메이션은 스스로 만들지 않는다: 점등은 호출자가 준 flash_t(실제 발동 시각)와 now의 차이로만 계산한다(임의 타이머 금지).

enum { STYLE_AUTO, STYLE_MOD, STYLE_MANUAL, STYLE_EQUIP, STYLE_SMALL }

const FLASH_DUR := 0.32   # 발동·준비 점등 길이(초). 반복 점멸 없음(1회)

var key := ""             # PIcons 키("" = 빈 슬롯)
var title := ""           # 표시 이름(비면 PIcons.name_of(key))
var sub := ""             # Lv·변형 등 보조 한 줄
var key_label := ""       # 수동 버튼의 키(Space·Q·E)
var style: int = STYLE_AUTO
var empty := false        # 아직 얻지 않은 슬롯 → 빈 테두리
var disabled := false     # 미보유 E 등 사용 불가
var cd_ratio := 0.0       # 1 = 완전히 대기 중, 0 = 준비 완료
var cd_left := 0.0        # 남은 초(0 이하면 표시 안 함)
var flash_t := -1.0       # 마지막 발동·준비 전환 시각(전투 시계). 음수면 점등 없음
var now_t := -1.0         # 현재 전투 시계
var badge := ""           # 오른쪽 위 작은 글자(개수 등)
var dimmed := false       # 미보유·비활성 표현(흐리게)
var label_lines := 1      # 칸 아래에 쓸 글자 줄 수(0 = 없음, 1 = 이름, 2 = 이름 + 보조). 아이콘 상자 높이를 정한다
var pick_until_ms := 0    # 방금 선택으로 바뀐 칸을 잠깐 강조(벽시계 ms). 전투 시계와 무관한 화면 이벤트라 여기만 실시간을 쓴다
var wrap_title := false   # 이름이 칸보다 길면 …로 자르지 않고 줄을 나눈다(아이콘 이름 구별 불가 방지)

## 조작 아이콘의 상태(전투 HUD 전용). "" = 상태 표시 안 함
const ST_NONE := "none"           # 미보유: 빈 테두리 + '미보유'
const ST_UNUSABLE := "unusable"   # 사용 불가: 흐림 + 빗금
const ST_COOLDOWN := "cooldown"   # 재사용 대기: 흑백 + 남은 초
const ST_READY := "ready"         # 준비됨: 컬러 + 테두리
var state := ""

var _gray_key := ""            # 이 칸이 들고 있는 흑백 그림의 키(칸마다 하나만 만들어 쓰고 화면과 함께 정리된다)
var _gray_big := true
var _gray_tex: Texture2D = null

func _init(p_key: String = "", p_style: int = STYLE_AUTO) -> void:
	key = p_key
	style = p_style
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER # 표·목록 안에서 늘어나지 않게(아이콘 칸 크기는 set_size_px가 정한다)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

func set_size_px(w: float, h: float) -> void:
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)

## 아이콘 실제 px과 칸 폭을 주면 글자 줄 수만큼 높이를 더해 칸을 만든다(아이콘 크기를 글자 때문에 줄이지 않는다)
func set_icon_px(icon_px: float, width: float, lines: int = 1) -> void:
	label_lines = lines
	set_size_px(maxf(width, icon_px + 8.0), icon_px + 8.0 + float(lines) * 14.0)

## 점등 세기(0~1). 실제 이벤트 시각 기준으로만 계산하며, 지난 뒤에는 0으로 남는다(계속 깜박이지 않음)
func flash_k() -> float:
	var k := 0.0
	if flash_t >= 0.0 and now_t >= 0.0:
		var d: float = now_t - flash_t
		if d >= 0.0 and d <= FLASH_DUR:
			k = 1.0 - d / FLASH_DUR
	if pick_until_ms > 0:
		var left: int = pick_until_ms - Time.get_ticks_msec()
		if left > 0:
			k = maxf(k, minf(1.0, float(left) / 400.0))
	return k

func _icon_box() -> Rect2:
	var pad := 4.0
	var w: float = size.x - pad * 2.0
	var h: float = size.y - pad * 2.0 - float(label_lines) * 14.0
	var s: float = maxf(8.0, minf(w, h))
	return Rect2(Vector2((size.x - s) / 2.0, pad), Vector2(s, s))

func _bg_color() -> Color:
	if empty:
		return Color(0.10, 0.11, 0.13, 0.55)
	match style:
		STYLE_MANUAL: return Color(0.14, 0.16, 0.20, 0.92)
		STYLE_MOD: return Color(0.11, 0.13, 0.16, 0.85)
		_: return Color(0.12, 0.14, 0.17, 0.85)

func _border_color() -> Color:
	if state == ST_READY:
		return Color(0.98, 0.90, 0.58, 0.98) # 준비됨: 따뜻한 밝은 테두리(대기와 한눈에 구분)
	if state == ST_COOLDOWN:
		return Color(0.44, 0.47, 0.52, 0.9)  # 재사용 대기: 무채색 테두리
	if empty:
		return Color(0.35, 0.38, 0.44, 0.75)
	if disabled:
		return Color(0.30, 0.32, 0.36, 0.8)
	match style:
		STYLE_MANUAL: return Color(0.62, 0.70, 0.82, 0.95)
		STYLE_MOD: return Color(0.42, 0.48, 0.56, 0.85)
		_: return Color(0.48, 0.54, 0.62, 0.9)

## 지금 이 칸이 흑백으로 그려지는가(재사용 대기 중에만)
func is_gray() -> bool:
	return state == ST_COOLDOWN

## 이 칸의 흑백 그림(키가 바뀔 때만 다시 만든다). 칸이 사라지면 함께 정리된다
func _gray_texture(big: bool) -> Texture2D:
	if _gray_key != key or _gray_big != big:
		_gray_key = key
		_gray_big = big
		_gray_tex = PIcons.texture_gray(key, big)
	return _gray_tex

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var radius: float = 6.0 if style != STYLE_MOD else 5.0
	PRender.rrect(self, r.position.x, r.position.y, r.size.x, r.size.y, radius, _bg_color())
	# 테두리: 빈 슬롯은 점선처럼 옅게, 수동 버튼은 두껍게
	var bw: float = 2.0 if style == STYLE_MANUAL else 1.0
	_stroke_rect(r, _border_color(), bw)
	var box := _icon_box()
	var big: bool = style != STYLE_MOD and style != STYLE_SMALL
	if not empty:
		var tex := _gray_texture(big) if is_gray() else PIcons.texture(key, big)
		var a: float = 0.45 if (disabled or dimmed) else 1.0
		if tex != null:
			draw_texture_rect(tex, box, false, Color(1, 1, 1, a))
		else:
			_placeholder(box, a)
	# 사용 불가(미보유가 아니라 지금 쓸 수 없음): 빗금 한 줄로 대기와 구분한다
	if state == ST_UNUSABLE and not empty:
		draw_line(box.position + Vector2(4.0, 4.0), box.end - Vector2(4.0, 4.0), Color(0.85, 0.45, 0.40, 0.8), 2.0)
	# 쿨다운 가림막(아래에서 위로 걷힌다) + 남은 초(흑백 위에 흰 숫자로 크게)
	if cd_ratio > 0.001 and not empty:
		var hh: float = box.size.y * clampf(cd_ratio, 0.0, 1.0)
		draw_rect(Rect2(box.position + Vector2(0.0, box.size.y - hh), Vector2(box.size.x, hh)), Color(0.03, 0.04, 0.06, 0.5))
		if cd_left > 0.05 and style != STYLE_MOD:
			var cf: int = 20 if style == STYLE_MANUAL else 16
			PRender.txt(self, box.position.x + box.size.x / 2.0, box.position.y + box.size.y / 2.0 + cf * 0.36, _cd_text(), cf, Color(1, 1, 1, 0.98), 0, true)
	# 준비 완료·개조 발동 점등(1회, 테두리만)
	var fk := flash_k()
	if fk > 0.0:
		_stroke_rect(r.grow(-1.0), Color(1.0, 0.94, 0.68, 0.95 * fk), 3.0)
	if key_label != "":
		var kw: float = 8.0 + float(key_label.length()) * 7.0
		PRender.rrect(self, 2.0, 2.0, kw, 14.0, 3.0, Color(0.05, 0.06, 0.08, 0.85))
		PRender.txt(self, 2.0 + kw / 2.0, 12.0, key_label, 11, Color(0.86, 0.92, 1.0), 0)
	if badge != "":
		PRender.txt(self, size.x - 3.0, 12.0, badge, 11, Color(1.0, 0.85, 0.4), 1)
	var ty: float = size.y - 3.0
	var fs: int = 11 if (style == PIconTile.STYLE_MOD or style == PIconTile.STYLE_SMALL) else 12
	if label_lines <= 0:
		return
	if sub != "" and label_lines >= 2:
		PRender.txt(self, size.x / 2.0, ty, _fit(sub, size.x - 6.0, 11), 11, Color(0.72, 0.77, 0.84), 0)
		ty -= 13.0
	if title != "" or (key != "" and not empty):
		var t := title if title != "" else PIcons.name_of(key)
		var col := Color(0.92, 0.95, 0.99) if not (disabled or empty) else Color(0.60, 0.64, 0.70)
		# 이름 줄: 여유 줄이 있으면 잘라내지 않고 두 줄로 나눈다(아이콘 이름이 …로 뭉개져 구별되지 않는 문제)
		var lines := [_fit(t, size.x - 6.0, fs)]
		if wrap_title and sub == "" and label_lines >= 2:
			lines = _fit_lines(t, size.x - 6.0, fs, 2)
		for i in range(lines.size() - 1, -1, -1):
			PRender.txt(self, size.x / 2.0, ty, String(lines[i]), fs, col, 0)
			ty -= float(fs) + 2.0

## 칸 폭에 맞게 자른다(넘치면 끝에 …). 이름을 다른 이름으로 바꾸지는 않는다 — 전체 이름은 빌드 상세에서 본다
static func _fit(s: String, maxw: float, fsize: int) -> String:
	var f := PRender.font()
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= maxw:
		return s
	var out := s
	while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > maxw:
		out = out.substr(0, out.length() - 1)
	return out + "…"

## 남은 초 글자: 1초 미만은 소수 한 자리, 그 이상은 정수(작은 칸에서도 읽히게)
func _cd_text() -> String:
	if cd_left < 1.0:
		return "%.1f" % cd_left
	return str(int(ceil(cd_left)))

## 칸 폭에 맞춰 최대 n줄로 나눈다(마지막 줄만 넘치면 …). 이름 자체는 바꾸지 않는다
static func _fit_lines(s: String, maxw: float, fsize: int, max_lines: int) -> Array:
	var f := PRender.font()
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= maxw:
		return [s]
	var out: Array = []
	var rest := s
	while out.size() < max_lines - 1 and rest.length() > 1:
		var cut := rest.length()
		while cut > 1 and f.get_string_size(rest.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > maxw:
			cut -= 1
		var sp := rest.substr(0, cut).rfind(" ")
		if sp > 0 and cut < rest.length():
			cut = sp + 1
		out.append(rest.substr(0, cut).strip_edges())
		rest = rest.substr(cut)
		if f.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= maxw:
			break
	out.append(_fit(rest.strip_edges(), maxw, fsize))
	return out

## 중립 자리표시 기호: 회색 마름모 + 가운데 점. 어떤 실제 효과의 도형과도 닮지 않게 유지한다
func _placeholder(box: Rect2, a: float) -> void:
	var c := box.position + box.size / 2.0
	var s: float = box.size.x * 0.32
	var col := Color(0.55, 0.59, 0.66, a)
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)])
	draw_polyline(pts, col, maxf(1.0, box.size.x * 0.045))
	draw_circle(c, maxf(1.0, box.size.x * 0.06), col)

func _stroke_rect(r: Rect2, col: Color, w: float) -> void:
	draw_rect(r, col, false, w)
