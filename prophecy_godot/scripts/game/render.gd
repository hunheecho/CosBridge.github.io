class_name PRender
extends RefCounted
## 전투 화면 벡터 렌더러(HTML render.js 이식, 임시 그래픽·정식 아트 아님·외부 에셋 없음). CombatState를 읽기만 한다.
## 그리기 순서(GAME_SPEC §11): 숲 바닥 → 장애물 → 바닥 지역 → 상자·목표 객체·회복 구슬 → 사거리 → 무기 몸체 → 내 공격 잔상(반투명)
##   → 적/플레이어(y 정렬) → 수관(가까우면 투명) → 적 예고선(최상단) → 투사체 → 불꽃·숫자. HUD는 그리지 않는다(main.gd의 Control HUD).
## 예고 도형 = 실제 판정 영역: 늑대 물기 부채꼴(def.bite.reach·arc_deg)·돌진 통로(폭 2(e.r+p.r), 길이 dash_speed×dash_time)는 combat_view 0.3.1과 같은 기하.
## 모든 함수는 static이며 첫 인자로 그릴 대상(ci)을 받는다. 전투 화면은 Node2D, HUD 아이콘 칸(PIconTile)은 Control이라 공용 도우미(txt·rrect·stroke_circle 등)는 CanvasItem을 받는다.
## 장식(풀·낙엽·돌)은 make_decor()로 시드에서 1회 만들어 캐시한다(st.rng 사용 안 함).
##
## 개조 식별(사용자 지시 §12): 개조가 만든 효과는 fx의 "mod" 필드로 구분해 실루엣·움직임을 다르게 그린다.
##   split_node(첫 명중 지점의 분기 결절) · shard(mod=split) 두 갈래 파편 · beam(returning=true) 되돌아오는 검기(선두 갈매기 + 뒤로 끌리는 잔상)
##   · arc(mod=cross) 빗금 실루엣 · scar_mark(점선 = 무해한 잔상) vs scar(채워진 부채꼴 = 실제 피해 순간) · bolt(mod=fan) 양옆 2발 · shatter_burst + shard(mod=shatter)
## 규칙 보호: 보이게 하려고 실제 사거리·수명·판정 폭을 늘리지 않는다. 장식용 잔상은 점선·윤곽만 써서 위험 범위(채워진 붉은 예고)와 섞이지 않게 한다.
## 적 예고선은 항상 플레이어 효과 위에 그린다(draw 순서: draw_player_effects → 개체 → 내 적중 연출 → draw_telegraphs).
##
## 색(막·테마): data/palette.json이 정본이다. 이 파일에 배경·예고 색을 새로 적지 않는다(palette_for → use_palette → _pal).
##   1막 초록 / 2막 연주황 / 3막 붉은 주황이며, 테마 9종은 막 색 위에 몇 개 키만 덮어쓴다.
##   적 예고는 막마다 밝기를 올린 붉은 계열 + 어두운 겹 + 밝은 테두리라 3막의 붉은 배경 위에서도 묻히지 않는다(수치는 tests/palette_tests.gd).
## 화면 흔들림: 강한 타격 연출(SHAKE_SOURCES)에서만, st.effects 값으로만 계산한다(규칙·난수를 읽지도 바꾸지도 않는다).
##   장판 틱·일반 적중은 원인 목록에 없어서 장판 위에서 화면이 계속 흔들리지 않는다. 전역 시간 정지는 어디서도 하지 않는다.

const VS := 1.25 # 캐릭터 시각 배율(판정 반지름과 별개)
## 이번 그리기의 기준 변환. 화면 흔들림 오프셋이 여기에만 들어가고 모든 그리기가 이 위에 얹힌다.
## 흔들림이 없으면 항등이라 좌표 계산은 예전과 완전히 같다. draw()가 시작·끝에서 설정·복원한다.
static var IDENT := Transform2D.IDENTITY

# ---------- 기본 도우미 ----------
static func C(h: String, a: float = 1.0) -> Color:
	var c := Color.html(h)
	c.a = a
	return c

static func rgba(r: int, g: int, b: int, a: float) -> Color:
	return Color(float(r) / 255.0, float(g) / 255.0, float(b) / 255.0, a)

static func font() -> Font:
	return ThemeDB.fallback_font

static func txt(ci: CanvasItem, x: float, y: float, s: String, size: int, color: Color, align: int = 0, outline: bool = false) -> void:
	# align: 0 = 가운데, -1 = 왼쪽, 1 = 오른쪽. y는 기준선
	var f := font()
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var px: float = x - w / 2.0 if align == 0 else (x if align < 0 else x - w)
	if outline:
		ci.draw_string_outline(f, Vector2(px, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.8 * color.a))
	ci.draw_string(f, Vector2(px, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func ellipse_pts(cx: float, cy: float, rx: float, ry: float, rot: float = 0.0, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n)
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var ex: float = cos(a) * rx
		var ey: float = sin(a) * ry
		pts[i] = Vector2(cx + ex * cr - ey * sr, cy + ex * sr + ey * cr)
	return pts

static func fill_ellipse(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float, color: Color, rot: float = 0.0, n: int = 20) -> void:
	ci.draw_colored_polygon(ellipse_pts(cx, cy, rx, ry, rot, n), color)

static func arc_pts(cx: float, cy: float, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	for i in n + 1:
		var a: float = a0 + (a1 - a0) * float(i) / float(n)
		pts[i] = Vector2(cx + cos(a) * r, cy + sin(a) * r)
	return pts

static func sector_pts(cx: float, cy: float, r: float, a0: float, a1: float, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(cx, cy)])
	pts.append_array(arc_pts(cx, cy, r, a0, a1, n))
	return pts

static func fill_sector(ci: CanvasItem, cx: float, cy: float, r: float, a0: float, a1: float, color: Color, n: int = 18) -> void:
	ci.draw_colored_polygon(sector_pts(cx, cy, r, a0, a1, n), color)

static func stroke_sector(ci: CanvasItem, cx: float, cy: float, r: float, a0: float, a1: float, color: Color, width: float, n: int = 18) -> void:
	var pts := sector_pts(cx, cy, r, a0, a1, n)
	pts.append(Vector2(cx, cy))
	ci.draw_polyline(pts, color, width)

static func quad_pts(p0: Vector2, p1: Vector2, p2: Vector2, n: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	for i in n + 1:
		var t: float = float(i) / float(n)
		var u: float = 1.0 - t
		pts[i] = p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)
	return pts

## 꺾은선을 폭 width의 띠 다각형으로(양쪽 법선 오프셋). 반투명 굵은 선을 이음새 겹침 없이 그릴 때
static func strip_polygon(path: PackedVector2Array, width: float) -> PackedVector2Array:
	var n: int = path.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var dir: Vector2 = (path[mini(n - 1, i + 1)] - path[maxi(0, i - 1)]).normalized()
		var nrm := Vector2(-dir.y, dir.x) * (width / 2.0)
		left.append(path[i] + nrm)
		right.append(path[i] - nrm)
	var out := PackedVector2Array()
	out.append_array(left)
	for i in range(n - 1, -1, -1):
		out.append(right[i])
	return out

static func circle_n(r: float) -> int:
	return clampi(int(r * 0.6), 12, 64)

static func stroke_circle(ci: CanvasItem, cx: float, cy: float, r: float, color: Color, width: float) -> void:
	ci.draw_arc(Vector2(cx, cy), r, 0.0, TAU, circle_n(r), color, width)

static func dashed_circle(ci: CanvasItem, cx: float, cy: float, r: float, color: Color, width: float, dash: float, gap: float, phase: float = 0.0) -> void:
	var per: float = (dash + gap) / maxf(1.0, r)
	var n: int = maxi(4, int(TAU / per))
	var seg := PackedVector2Array()
	for i in n:
		var a0: float = phase + float(i) * per
		var a1: float = a0 + dash / maxf(1.0, r)
		var am: float = (a0 + a1) * 0.5
		seg.append(Vector2(cx + cos(a0) * r, cy + sin(a0) * r))
		seg.append(Vector2(cx + cos(am) * r, cy + sin(am) * r))
		seg.append(Vector2(cx + cos(am) * r, cy + sin(am) * r))
		seg.append(Vector2(cx + cos(a1) * r, cy + sin(a1) * r))
	ci.draw_multiline(seg, color, width)

static func dashed_line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	ci.draw_dashed_line(a, b, color, width, dash + gap, true)

static func shadow(ci: Node2D, x: float, y: float, rx: float, ry: float) -> void:
	fill_ellipse(ci, x, y, rx, ry, Color(0, 0, 0, 0.32))

## 경기장 좌표의 변환(기준 변환 = 화면 흔들림을 포함한다)
static func xf(pos: Vector2, rot: float, sc: Vector2) -> Transform2D:
	return IDENT * Transform2D(rot, sc, 0.0, pos)

## 이미 자리를 잡은 변환 위에 얹는 상대 변환(흔들림을 두 번 더하지 않는다)
static func rel(rot: float, sc: Vector2) -> Transform2D:
	return Transform2D(rot, sc, 0.0, Vector2.ZERO)

static func rrect(ci: CanvasItem, x: float, y: float, w: float, h: float, r: float, color: Color) -> void:
	# 둥근 사각형(간이): 사각형 + 네 모서리 원
	ci.draw_rect(Rect2(x + r, y, w - 2.0 * r, h), color)
	ci.draw_rect(Rect2(x, y + r, w, h - 2.0 * r), color)
	for cx in [x + r, x + w - r]:
		for cy in [y + r, y + h - r]:
			ci.draw_circle(Vector2(float(cx), float(cy)), r, color)

# ---------- 막·테마 색(data/palette.json이 정본) ----------
## 여기서 색을 새로 만들지 않는다. palette.json의 acts(막 기본값) 위에 themes(테마별 덮어쓰기)를 얹어 한 벌을 만든다.
## 보스 전투처럼 테마 id가 없으면(region_id="boss") 막 기본값만 쓴다.
static var _pal_raw: Dictionary = {}
static var _pal_merged: Dictionary = {}
static var _pal: Dictionary = {}    # 이번 그리기가 쓰는 색 한 벌(use_palette가 정한다)

static func palette_data() -> Dictionary:
	if not _pal_raw.is_empty():
		return _pal_raw
	var f := FileAccess.open("res://data/palette.json", FileAccess.READ)
	if f == null:
		push_error("색 정본 없음: res://data/palette.json")
		_pal_raw = { "acts": {}, "themes": {} }
		return _pal_raw
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("색 정본 파싱 실패: res://data/palette.json")
		parsed = { "acts": {}, "themes": {} }
	_pal_raw = parsed
	return _pal_raw

## 시험·도구용: 파일을 다시 읽게 한다
static func palette_reset() -> void:
	_pal_raw = {}
	_pal_merged = {}
	_pal = {}

## 막(1~3) + 테마 id → 색 한 벌. 테마 항목은 막 기본값 위에 덮어쓸 키만 가진다(막 색감 유지 + 테마 차이 보존)
static func palette_for(act: int, theme_id: String = "") -> Dictionary:
	var key := "%d|%s" % [act, theme_id]
	if _pal_merged.has(key):
		return _pal_merged[key]
	var d := palette_data()
	var acts: Dictionary = d.get("acts", {})
	var themes: Dictionary = d.get("themes", {})
	var th: Dictionary = themes.get(theme_id, {})
	var a: int = int(th.get("act", clampi(act, 1, 3)))
	var out: Dictionary = (acts.get(str(a), {}) as Dictionary).duplicate(true)
	for k in th:
		if String(k) == "act" or String(k) == "name":
			continue
		out[k] = th[k]
	out["act"] = a
	out["theme"] = theme_id
	_pal_merged[key] = out
	return out

## 이번 그리기의 색 한 벌을 정한다(같은 막·테마면 캐시라 값싸다)
static func use_palette(st: CombatState) -> Dictionary:
	_pal = palette_for(int(st.act), String(st.region_id))
	return _pal

## 색 한 벌에서 색을 꺼낸다. 키가 없으면 fallback(옛 하드코딩 값)을 쓴다
static func pc(key: String, fallback: String, a: float = 1.0) -> Color:
	return C(String(_pal.get(key, fallback)), a)

static func pf(key: String, fallback: float) -> float:
	return float(_pal.get(key, fallback))

# 적 예고 색: 채움 / 밝은 테두리 / 테두리 밑 어두운 겹 / '!' 표식 / 조준 중(확정 전)
static func tel_fill(a: float) -> Color: return pc("tele_fill", "#ff5a46", a)
static func tel_edge(a: float) -> Color: return pc("tele_edge", "#ffb08a", a)
static func tel_dark(a: float) -> Color: return pc("tele_dark", "#180b07", a)
static func tel_mark(a: float) -> Color: return pc("tele_mark", "#ffc08a", a)
static func tel_soft(a: float) -> Color: return pc("tele_soft", "#ff8a5c", a)
static func tel_label(a: float = 1.0) -> Color: return pc("tele_label", "#ffd9b0", a)

## 확정된 예고의 테두리: 어두운 겹을 먼저 굵게, 그 위에 밝은 선. 배경 밝기와 무관하게 형태가 읽힌다.
static func tel_stroke_poly(ci: CanvasItem, pts: PackedVector2Array, a: float, w: float) -> void:
	ci.draw_polyline(pts, tel_dark(a * 0.85), w + 3.0)
	ci.draw_polyline(pts, tel_edge(a), w)

static func tel_stroke_rect(ci: CanvasItem, r: Rect2, a: float, w: float) -> void:
	ci.draw_rect(r, tel_dark(a * 0.85), false, w + 3.0)
	ci.draw_rect(r, tel_edge(a), false, w)

static func tel_stroke_arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, a: float, w: float, n: int = 24) -> void:
	ci.draw_arc(c, r, a0, a1, n, tel_dark(a * 0.85), w + 3.0)
	ci.draw_arc(c, r, a0, a1, n, tel_edge(a), w)

static func tel_stroke_sector(ci: CanvasItem, cx: float, cy: float, r: float, a0: float, a1: float, a: float, w: float, n: int = 18) -> void:
	stroke_sector(ci, cx, cy, r, a0, a1, tel_dark(a * 0.85), w + 3.0, n)
	stroke_sector(ci, cx, cy, r, a0, a1, tel_edge(a), w, n)

static func tel_stroke_circle(ci: CanvasItem, cx: float, cy: float, r: float, a: float, w: float) -> void:
	stroke_circle(ci, cx, cy, r, tel_dark(a * 0.85), w + 3.0)
	stroke_circle(ci, cx, cy, r, tel_edge(a), w)

## 확정 예고의 '!' 표식: 검은 외곽선을 함께 그려 어느 배경에서도 읽힌다
static func tel_bang(ci: CanvasItem, x: float, y: float, size: int, a: float = 1.0) -> void:
	txt(ci, x, y, "!", size, tel_mark(a), 0, true)

# ---------- 화면 흔들림(강한 타격 전용, 그리기 값만) ----------
## 원인은 이 표에 있는 연출뿐이다. 값은 st.effects의 t·ttl·위치에서만 나오므로
## 같은 상태를 두 번 그리면 같은 값이 나오고, 규칙(무적·재사용·판정·봇)에는 아무 영향이 없다.
## 일반 적중(spark)·피격 점멸(hitflash)·장판(zone)은 일부러 뺐다 — 장판 위에서 화면이 계속 흔들리면 안 된다.
const SHAKE_SOURCES := { "impact": 2.4, "bossland": 2.6, "mineburst": 1.8, "strike": 2.0, "slashline": 1.6 }
const SHAKE_MAX := 3.0
const SHAKE_PREFS := "user://render_prefs.json"

static var shake_enabled := true
static var _prefs_loaded := false

static func load_prefs() -> void:
	_prefs_loaded = true
	if OS.get_environment("PROPHECY_NO_SHAKE") != "":
		shake_enabled = false
		return
	if not FileAccess.file_exists(SHAKE_PREFS):
		return
	var f := FileAccess.open(SHAKE_PREFS, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("camera_shake"):
		shake_enabled = bool(parsed.camera_shake)

## 끄기 옵션: 값은 user://render_prefs.json에 남는다(소리 설정과 같은 방식)
static func set_shake(on: bool) -> void:
	shake_enabled = on
	_prefs_loaded = true
	var f := FileAccess.open(SHAKE_PREFS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({ "camera_shake": on }))

static func shake_on() -> bool:
	if not _prefs_loaded:
		load_prefs()
	return shake_enabled

## 지금 화면을 얼마나 밀지(px). 끄면 정확히 (0,0)
static func shake_offset(st: CombatState) -> Vector2:
	if st == null or not shake_on():
		return Vector2.ZERO
	var o := Vector2.ZERO
	for f in st.effects:
		var amp: float = float(SHAKE_SOURCES.get(String(f.kind), 0.0))
		if amp <= 0.0:
			continue
		var ttl: float = maxf(0.001, float(f.ttl))
		var k: float = clampf(1.0 - float(f.t) / ttl, 0.0, 1.0)
		var ph: float = float(f.t) * 52.0 + float(f.get("x", 0.0)) * 0.017 + float(f.get("y", 0.0)) * 0.023
		var w: float = amp * k * k
		o += Vector2(sin(ph), cos(ph * 0.86)) * w
	return o.limit_length(SHAKE_MAX)   # 몇 개가 겹쳐도 실제로 미는 거리는 SHAKE_MAX를 넘지 않는다

# ---------- 숲 장식(시드 결정적, 판정과 무관). st.rng를 쓰지 않는다 ----------
static func make_decor(st: CombatState) -> Dictionary:
	var rng := PRng.new(st.seed_value * 7 + 3)
	var w: float = st.arena_w
	var h: float = st.arena_h
	var d := { "grass": [], "leaves": [], "stones": [], "path": PackedVector2Array(), "seed": st.seed_value, "w": w, "h": h }
	for i in 160:
		d.grass.append({ "x": rng.range_f(10.0, w - 10.0), "y": rng.range_f(10.0, h - 10.0), "s": rng.range_f(0.7, 1.3) })
	# 낙엽은 색을 여기서 정하지 않는다(막·테마가 바뀌면 같은 배치로 색만 바뀌게 번호만 남긴다)
	for i in 40:
		var lx: float = rng.range_f(0.0, w)
		var ly: float = rng.range_f(0.0, h)
		var lr: float = rng.range_f(2.0, 4.0)
		var la: float = rng.range_f(0.0, TAU)
		var li: int = rng.int_range(0, 2)
		d.leaves.append({ "pts": ellipse_pts(lx, ly, lr * 1.6, lr, la, 10), "ci": li })
	for i in 18:
		var sx: float = rng.range_f(20.0, w - 20.0)
		var sy: float = rng.range_f(20.0, h - 20.0)
		var sr: float = rng.range_f(3.0, 6.0)
		d.stones.append({ "a": ellipse_pts(sx, sy, sr * 1.3, sr, 0.0, 12), "b": ellipse_pts(sx - 1.0, sy - 1.0, sr * 0.7, sr * 0.45, 0.0, 10) })
	var x0: float = rng.range_f(0.0, w * 0.3)
	var x1: float = rng.range_f(w * 0.7, w)
	var mid := Vector2(w * 0.5 + rng.range_f(-150.0, 150.0), h * 0.5 + rng.range_f(-100.0, 100.0))
	d.path = quad_pts(Vector2(x0, h + 20.0), mid, Vector2(x1, -20.0), 24)
	d.path_wide = strip_polygon(d.path, 64.0)
	d.path_narrow = strip_polygon(d.path, 36.0)
	return d

## 비네트(중앙이 조금 밝고 가장자리는 어두움)·위쪽 그늘 텍스처. 막·테마마다 한 번만 만들어 캐시한다
static var _grad_cache: Dictionary = {}

static func _vignette_tex() -> GradientTexture2D:
	var key := "v|" + String(_pal.get("theme", "")) + "|" + str(_pal.get("act", 1))
	if _grad_cache.has(key):
		return _grad_cache[key]
	var g := Gradient.new()
	g.set_color(0, pc("vignette", "#5a783c", pf("vignette_a", 0.20)))
	g.set_color(1, pc("vignette_edge", "#000000", pf("vignette_edge_a", 0.35)))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.2, 0.5)
	gt.width = 128
	gt.height = 128
	_grad_cache[key] = gt
	return gt

static func _topshade_tex() -> GradientTexture2D:
	var key := "t|" + String(_pal.get("theme", "")) + "|" + str(_pal.get("act", 1))
	if _grad_cache.has(key):
		return _grad_cache[key]
	var g2 := Gradient.new()
	g2.set_color(0, pc("topshade", "#000000", pf("topshade_a", 0.35)))
	g2.set_color(1, pc("topshade", "#000000", 0.0))
	var gt2 := GradientTexture2D.new()
	gt2.gradient = g2
	gt2.fill = GradientTexture2D.FILL_LINEAR
	gt2.fill_from = Vector2(0.0, 0.0)
	gt2.fill_to = Vector2(0.0, 1.0)
	gt2.width = 4
	gt2.height = 32
	_grad_cache[key] = gt2
	return gt2

static func draw_forest(ci: Node2D, st: CombatState, d: Dictionary) -> void:
	use_palette(st)
	var w: float = st.arena_w
	var h: float = st.arena_h
	# 바닥은 흔들림 폭만큼 넉넉히 칠한다(화면이 밀려도 경기장 밖이 비지 않게). 경계선은 실제 경기장 크기 그대로다
	var m := SHAKE_MAX + 1.0
	ci.draw_rect(Rect2(-m, -m, w + m * 2.0, h + m * 2.0), pc("ground", "#2b3a25"))
	ci.draw_texture_rect(_vignette_tex(), Rect2(0, 0, w, h), false)
	# 흙길(장식, 저대비): 겹침 없는 띠 다각형(굵은 polyline은 이음새가 겹쳐 진해진다)
	if d.has("path_wide"):
		ci.draw_colored_polygon(d.path_wide, pc("path_wide", "#6e5837", pf("path_wide_a", 0.2)))
		ci.draw_colored_polygon(d.path_narrow, pc("path_narrow", "#82693f", pf("path_narrow_a", 0.14)))
	var leaf_cols: Array = _pal.get("leaves", ["#7a5a2e", "#8a6a34", "#5f6b2c"])
	for l in d.get("leaves", []):
		ci.draw_colored_polygon(l.pts, C(String(leaf_cols[int(l.get("ci", 0)) % leaf_cols.size()])))
	var st_c := pc("stone", "#4a4f48")
	var st_hi := pc("stone_hi", "#6a6f66")
	for s in d.get("stones", []):
		ci.draw_colored_polygon(s.a, st_c)
		ci.draw_colored_polygon(s.b, st_hi)
	# 풀(바람에 흔들림): 한 번의 multiline
	var seg := PackedVector2Array()
	for t in d.get("grass", []):
		var gx: float = t.x
		var gy: float = t.y
		var gs: float = t.s
		var sway: float = sin(st.t * 1.5 + gx * 0.05) * 1.5
		seg.append(Vector2(gx - 3.0 * gs, gy))
		seg.append(Vector2(gx - 2.0 * gs + sway, gy - 7.0 * gs))
		seg.append(Vector2(gx, gy))
		seg.append(Vector2(gx + sway, gy - 9.0 * gs))
		seg.append(Vector2(gx + 3.0 * gs, gy))
		seg.append(Vector2(gx + 2.0 * gs + sway, gy - 6.0 * gs))
	if seg.size() > 0:
		ci.draw_multiline(seg, pc("grass", "#4f7a34"), 1.5)
	# 경계선: 이동 가능 영역의 끝
	ci.draw_rect(Rect2(0, 0, w, h), pc("border", "#141e12", pf("border_a", 0.9)), false, 6.0)
	ci.draw_rect(Rect2(1, 1, w - 2.0, h - 2.0), pc("border_in", "#a0c878", pf("border_in_a", 0.25)), false, 1.5)
	ci.draw_texture_rect(_topshade_tex(), Rect2(0, 0, w, 30), false)

# ---------- 장애물: 바위·나무 밑동(충돌 범위 = 그림). 수관은 개체 위에 반투명으로 따로 ----------
static func draw_obstacles(ci: Node2D, st: CombatState) -> void:
	use_palette(st)
	for ob in st.obstacles:
		var x: float = ob.x
		var y: float = ob.y
		var r: float = ob.r
		if String(ob.type) == "rock":
			fill_ellipse(ci, x + 4.0, y + r * 0.55, r * 1.05, r * 0.5, Color(0, 0, 0, 0.3))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x - r, y + r * 0.35), Vector2(x - r * 0.75, y - r * 0.55), Vector2(x - r * 0.15, y - r), Vector2(x + r * 0.55, y - r * 0.8), Vector2(x + r, y - r * 0.1), Vector2(x + r * 0.85, y + r * 0.6), Vector2(x + r * 0.1, y + r), Vector2(x - r * 0.7, y + r * 0.8)]), pc("rock", "#5b6160"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x - r * 0.6, y - r * 0.3), Vector2(x - r * 0.1, y - r * 0.85), Vector2(x + r * 0.45, y - r * 0.65), Vector2(x + r * 0.3, y - r * 0.1), Vector2(x - r * 0.3, y + r * 0.05)]), pc("rock_hi", "#7d8482"))
			fill_ellipse(ci, x - r * 0.45, y + r * 0.35, r * 0.3, r * 0.16, pc("moss", "#5a8c46", 0.55), 0.3, 10)
			stroke_circle(ci, x, y, r, pc("obstacle_edge", "#141816", 0.7), 2.0)
		else:
			fill_ellipse(ci, x + 3.0, y + 6.0, r * 1.2, r * 0.55, Color(0, 0, 0, 0.3))
			ci.draw_circle(Vector2(x, y), r, pc("trunk", "#4a3420"))
			ci.draw_circle(Vector2(x, y), r * 0.72, pc("trunk_in", "#5e4429"))
			for i in range(1, 4):
				stroke_circle(ci, x, y, r * 0.72 * float(i) / 4.0, pc("trunk_ring", "#3a2816"), 1.5)
			for i in 4:
				var a: float = float(i) * TAU / 4.0 + 0.6
				ci.draw_line(Vector2(x + cos(a) * r * 0.8, y + sin(a) * r * 0.8), Vector2(x + cos(a) * (r + 12.0), y + sin(a) * (r + 12.0)), pc("trunk", "#4a3420"), 5.0)
			stroke_circle(ci, x, y, r, pc("obstacle_edge", "#141816", 0.7), 2.0)

static func draw_canopies(ci: Node2D, st: CombatState) -> void:
	use_palette(st)
	var p: Dictionary = st.player
	for ob in st.obstacles:
		if String(ob.type) != "tree":
			continue
		var x: float = ob.x
		var y: float = ob.y
		var R: float = float(ob.get("canopy", 70.0))
		var near: bool = PGeom.dist(p.x, p.y, x, y) < R + 30.0
		if not near:
			for e in st.enemies:
				if not e.dead and PGeom.dist(e.x, e.y, x, y) < R + float(e.r) + 10.0:
					near = true
					break
		var a: float = 0.32 if near else 0.82
		var cn := pc("canopy", "#233a22", a)
		var cn2 := pc("canopy_hi", "#2c4a2a", a)
		ci.draw_circle(Vector2(x, y - 14.0), R, cn)
		ci.draw_circle(Vector2(x - R * 0.35, y - 24.0), R * 0.55, cn2)
		ci.draw_circle(Vector2(x + R * 0.4, y - 20.0), R * 0.5, cn2)
		ci.draw_circle(Vector2(x, y - R * 0.55), R * 0.5, cn2)
		ci.draw_circle(Vector2(x - R * 0.2, y - R * 0.45), R * 0.35, pc("canopy_light", "#8cbe64", 0.25 * a))

# ---------- 바닥 지역 ----------
static func draw_zones(ci: Node2D, st: CombatState) -> void:
	use_palette(st)
	for z in st.zones:
		var life: float = float(z.ttl) / maxf(0.001, float(z.max_ttl))
		var zx: float = z.x
		var zy: float = z.y
		var zr: float = z.r
		var zt: float = float(z.get("t", 0.0))
		var c := Vector2(zx, zy)
		match String(z.type):
			"spore":
				ci.draw_circle(c, zr, rgba(170, 90, 230, 0.2 + 0.2 * life))
				dashed_circle(ci, zx, zy, zr, rgba(215, 160, 255, 0.5 + 0.3 * life), 2.0, 6.0, 6.0)
				for i in 6:
					var ang: float = zt * 0.8 + float(i) * 1.1
					var rr: float = zr * (0.25 + 0.6 * fmod(float(i) * 0.37 + zt * 0.2, 1.0))
					ci.draw_circle(Vector2(zx + cos(ang) * rr, zy + sin(ang) * rr), 3.0 + float(i % 2), rgba(235, 200, 255, 0.55))
				txt(ci, zx, zy + 5.0, "☠", 14, Color(1, 1, 1, 0.75))
			"web":
				var wc := rgba(235, 235, 245, 0.35 + 0.35 * life)
				for i in 8:
					var a: float = float(i) * TAU / 8.0
					ci.draw_line(c, Vector2(zx + cos(a) * zr, zy + sin(a) * zr), wc, 1.2)
				for k in range(1, 4):
					stroke_circle(ci, zx, zy, zr * float(k) / 3.0, wc, 1.2)
				ci.draw_arc(c, zr + 2.0, -PI / 2.0, -PI / 2.0 + TAU * life, 40, Color(1, 1, 1, 0.8), 2.0)
				txt(ci, zx, zy - zr - 6.0, "거미줄(걷기 50%)", 11, Color(1, 1, 1, 0.8))
			"frostzone":
				var k: float = 1.0 - life
				ci.draw_circle(c, zr, rgba(160, 220, 255, 0.12 + 0.25 * k))
				ci.draw_circle(c, zr * k, rgba(200, 240, 255, 0.35 + 0.4 * k))
				var soon: bool = float(z.ttl) < 0.45
				stroke_circle(ci, zx, zy, zr, rgba(255, 120, 120, 0.8 + 0.2 * sin(st.t * 60.0)) if soon else rgba(200, 240, 255, 0.8), 3.0 if soon else 1.5)
				txt(ci, zx, zy + 6.0, str(int(z.get("order", 0))) if z.has("order") else "", 18, Color.WHITE)
			"coldground":
				ci.draw_circle(c, zr, rgba(160, 220, 255, 0.22 * life + 0.08))
				stroke_circle(ci, zx, zy, zr, rgba(200, 240, 255, 0.6 * life), 1.5)
			"windpath":
				dashed_circle(ci, zx, zy, zr, rgba(200, 255, 220, 0.5 * life), 2.0, 6.0, 6.0)
			"slowecho":
				ci.draw_circle(c, zr, rgba(110, 180, 255, 0.08 * life + 0.04))
				stroke_circle(ci, zx, zy, zr, rgba(110, 180, 255, 0.35 * life), 1.5)
			"storm":
				dashed_circle(ci, zx, zy, zr, rgba(255, 240, 150, 0.5 * life), 2.0, 3.0, 5.0)
			"hazard":
				if not bool(z.get("armed", false)):
					var k: float = minf(1.0, zt / maxf(0.001, float(z.get("warn", 1.0))))
					var late: bool = k > 0.7
					# 위험 장판 예고: 늦을수록 밝은 테두리 + 어두운 겹(3막 붉은 바닥 위에서도 형태가 읽히게)
					dashed_circle(ci, zx, zy, zr, tel_dark(0.7), (3.0 if late else 2.0) + 3.0, 6.0, 5.0)
					dashed_circle(ci, zx, zy, zr, tel_edge(0.5 + 0.5 * absf(sin(st.t * 20.0))) if late else tel_soft(0.7), 3.0 if late else 2.0, 6.0, 5.0)
					ci.draw_circle(c, zr * k, tel_fill(0.1 + 0.2 * k))
					var _zt := String(z.get("tag", ""))
					var _ztxt := "위험 예고"
					match _zt:      # 예고 문구는 실제 출처를 말한다(전부 '제단'으로 적지 않는다)
						"terrain": _ztxt = "지형 붕괴 예고"
						"altar": _ztxt = "제단 위험 예고"
						"boss": _ztxt = "보스 공격 예고"
						"elite": _ztxt = "정예 공격 예고"
					txt(ci, zx, zy - zr - 6.0, _ztxt, 11, tel_label(1.0), 0, true)
				else:
					ci.draw_circle(c, zr, tel_fill(0.3 + 0.25 * life))
					tel_stroke_circle(ci, zx, zy, zr, 0.8, 2.0)
					for i in 5:
						var a: float = float(i) * 1.26 + zt * 2.0
						ci.draw_line(Vector2(zx + cos(a) * zr * 0.3, zy + sin(a) * zr * 0.3), Vector2(zx + cos(a) * zr * 0.9, zy + sin(a) * zr * 0.9), rgba(255, 220, 160, 0.6), 1.5)
			"fire":
				var fl: float = 1.0 + 0.12 * sin(zt * 22.0)
				ci.draw_circle(c, zr * fl, rgba(255, 110, 30, 0.25 + 0.25 * life))
				ci.draw_circle(c, zr * 0.5 * fl, rgba(255, 220, 90, 0.55 * life))
				for i in 4:
					var ang: float = float(i) * 1.57 + zt * 3.0
					var fr: float = zr * 0.6
					var bx: float = zx + cos(ang) * fr
					var by: float = zy + sin(ang) * fr
					ci.draw_colored_polygon(PackedVector2Array([Vector2(bx, by - 6.0 - 4.0 * sin(zt * 15.0 + float(i))), Vector2(bx - 3.0, by + 2.0), Vector2(bx + 3.0, by + 2.0)]), rgba(255, 200, 80, 0.5 * life))
			"ice": # 빙판(서리 추적자): 걷기 속도만 감속. 미끄러짐·입력 반전 없음
				ci.draw_circle(c, zr, rgba(170, 225, 255, 0.16 + 0.18 * life))
				stroke_circle(ci, zx, zy, zr, rgba(210, 240, 255, 0.5 * life + 0.2), 1.5)
				for i in 3:
					var a: float = float(i) * 2.1 + 0.4
					ci.draw_line(Vector2(zx + cos(a) * zr * 0.2, zy + sin(a) * zr * 0.2), Vector2(zx + cos(a) * zr * 0.8, zy + sin(a) * zr * 0.8), rgba(255, 255, 255, 0.45 * life), 1.2)
				if PGeom.dist(zx, zy, float(st.player.x), float(st.player.y)) <= zr + float(st.player.r) * 0.5:
					txt(ci, zx, zy - zr - 6.0, "빙판(걷기 %d%%)" % int(round(float(z.get("slow", 0.6)) * 100.0)), 11, Color(1, 1, 1, 0.85))
			"rubble": # 낙석 잔해(굴착 거수): 서 있으면 0.5초마다 피해
				ci.draw_circle(c, zr, rgba(150, 110, 70, 0.22 + 0.2 * life))
				stroke_circle(ci, zx, zy, zr, rgba(210, 170, 120, 0.6 * life + 0.2), 2.0)
				for i in 6:
					var a: float = float(i) * 1.05 + 0.2
					var rr: float = zr * (0.25 + 0.5 * fmod(float(i) * 0.41, 1.0))
					ci.draw_circle(Vector2(zx + cos(a) * rr, zy + sin(a) * rr), 4.0 + float(i % 3), rgba(120, 90, 60, 0.8))
				txt(ci, zx, zy + 5.0, "잔해", 11, Color(1, 1, 1, 0.75))
			_:
				stroke_circle(ci, zx, zy, zr, Color(1, 1, 1, 0.4 * life), 1.5)
	if not st.field.is_empty():
		draw_field(ci, st, st.field, "감속장")
	var f2: Dictionary = st.skill_state.get("field2", {}) if not st.skill_state.is_empty() else {}
	if not f2.is_empty():
		draw_field(ci, st, f2, "감속장(분할)")

static func draw_field(ci: Node2D, st: CombatState, f: Dictionary, label: String) -> void:
	var fx: float = f.x
	var fy: float = f.y
	var fr: float = f.r
	var life: float = float(f.ttl) / maxf(0.001, float(f.max_ttl))
	var c := Vector2(fx, fy)
	ci.draw_circle(c, fr, rgba(110, 180, 255, 0.16))
	stroke_circle(ci, fx, fy, fr, rgba(170, 225, 255, 0.45), 1.5)
	var ticks := PackedVector2Array()
	var big := PackedVector2Array()
	for i in 24:
		var ang: float = float(i) * TAU / 24.0 - st.t * 0.3
		var L: float = 10.0 if i % 6 == 0 else 5.0
		var a := Vector2(fx + cos(ang) * (fr - L), fy + sin(ang) * (fr - L))
		var b := Vector2(fx + cos(ang) * fr, fy + sin(ang) * fr)
		if i % 6 == 0:
			big.append(a)
			big.append(b)
		else:
			ticks.append(a)
			ticks.append(b)
	ci.draw_multiline(ticks, rgba(200, 235, 255, 0.7), 1.0)
	ci.draw_multiline(big, rgba(200, 235, 255, 0.7), 2.0)
	ci.draw_arc(c, fr + 3.0, -PI / 2.0, -PI / 2.0 + TAU * life, 48, rgba(190, 235, 255, 0.95), 3.0)
	for i in 10:
		var ang: float = float(i) * 0.63 + st.t * 0.4
		var rr: float = fr * (0.2 + 0.7 * fmod(float(i) * 0.31 + st.t * 0.05, 1.0))
		ci.draw_circle(Vector2(fx + cos(ang) * rr, fy + sin(ang) * rr), 2.0, rgba(220, 245, 255, 0.6))
	txt(ci, fx, fy - fr - 10.0, "%s %.1fs" % [label, float(f.ttl)], 12, rgba(200, 235, 255, 0.95))

# ---------- 상자·목표 객체·회복 구슬 ----------
static func draw_chest(ci: Node2D, st: CombatState) -> void:
	var c: Dictionary = st.chest
	if c.is_empty() or (bool(c.opened) and float(c.t) > 0.6):
		return
	var cx: float = c.x
	var cy: float = c.y
	var bob: float = 0.0 if bool(c.opened) else sin(st.t * 4.0) * 2.0
	fill_ellipse(ci, cx, cy + 12.0, 16.0, 5.0, Color(0, 0, 0, 0.3))
	ci.draw_rect(Rect2(cx - 14.0, cy - 10.0 + bob, 28.0, 20.0), C("#8a6b2f") if bool(c.opened) else C("#c9973a"))
	ci.draw_rect(Rect2(cx - 14.0, cy - 12.0 + bob, 28.0, 6.0), C("#5b3f14"))
	ci.draw_rect(Rect2(cx - 3.0, cy - 4.0 + bob, 6.0, 6.0), C("#ffe9a8"))
	if not bool(c.opened):
		txt(ci, cx, cy - 20.0 + bob, "보급 상자", 12, C("#ffd166"))

static func draw_objects(ci: Node2D, st: CombatState) -> void:
	for o in st.objects:
		var ox: float = o.x
		var oy: float = o.y
		var orr: float = o.r
		match String(o.kind):
			"cage":
				var freed: bool = bool(o.get("freed", false))
				ci.draw_rect(Rect2(ox - orr, oy - orr * 0.9, orr * 2.0, orr * 1.8), rgba(60, 60, 70, 0.5) if freed else C("#2b2b33"))
				var bar_c := C("#666666") if freed else C("#c8c8d0")
				for i in range(-2, 3):
					ci.draw_line(Vector2(ox + float(i) * orr * 0.45, oy - orr * 0.9), Vector2(ox + float(i) * orr * 0.45, oy + orr * 0.9), bar_c, 2.0)
				ci.draw_rect(Rect2(ox - orr, oy - orr * 0.9, orr * 2.0, orr * 1.8), bar_c, false, 2.0)
				if not freed:
					ci.draw_circle(Vector2(ox, oy - 4.0), 6.0, C("#e9c9a8"))
					ci.draw_rect(Rect2(ox - 5.0, oy + 2.0, 10.0, 12.0), C("#e9c9a8"))
					var near_r: float = float(PCatalog.objectives().get("rescue", {}).get("near", 60.0))
					dashed_circle(ci, ox, oy, near_r, rgba(156, 255, 176, 0.5), 1.0, 5.0, 5.0)
					if float(o.get("progress", 0.0)) > 0.0:
						ci.draw_rect(Rect2(ox - 24.0, oy - orr - 16.0, 48.0, 6.0), Color(0, 0, 0, 0.6))
						ci.draw_rect(Rect2(ox - 24.0, oy - orr - 16.0, 48.0 * float(o.progress) / maxf(0.001, float(o.total)), 6.0), C("#9cffb0"))
				txt(ci, ox, oy + orr + 16.0, "빈 우리" if freed else "포로 %d" % int(o.get("id", 0)), 11, C("#eeeeee"))
			"seal":
				var O: Dictionary = st.obj
				var k: float = float(O.progress) / maxf(0.001, float(O.total)) if (not O.is_empty() and O.has("progress")) else 0.0
				var paused: bool = bool(O.get("paused", false)) if not O.is_empty() else false
				var pulse: float = 0.5 + 0.5 * sin(st.t * 4.0)
				var moving: bool = bool(o.get("moving", false))
				ci.draw_circle(Vector2(ox, oy), orr, rgba(120, 200, 255, 0.15 + 0.1 * pulse) if (not O.is_empty() and not paused) else rgba(120, 200, 255, 0.08))
				if moving:
					dashed_circle(ci, ox, oy, orr, rgba(255, 200, 80, 0.9), 3.0, 4.0, 4.0)
				else:
					stroke_circle(ci, ox, oy, orr, rgba(160, 220, 255, 0.9), 3.0)
				for i in 6:
					var a: float = float(i) * TAU / 6.0 + st.t * 0.4
					ci.draw_line(Vector2(ox + cos(a) * orr * 0.5, oy + sin(a) * orr * 0.5), Vector2(ox + cos(a) * orr * 0.85, oy + sin(a) * orr * 0.85), rgba(160, 220, 255, 0.6), 2.0)
				if k > 0.0:
					ci.draw_arc(Vector2(ox, oy), orr + 6.0, -PI / 2.0, -PI / 2.0 + TAU * k, 48, C("#bfefff"), 5.0)
				var nx: Dictionary = o.get("next", {})
				if moving and not nx.is_empty():
					dashed_line(ci, Vector2(ox, oy), Vector2(float(nx.x), float(nx.y)), rgba(255, 200, 80, 0.9), 3.0, 8.0, 6.0)
					dashed_circle(ci, float(nx.x), float(nx.y), orr, rgba(255, 200, 80, 0.9), 3.0, 8.0, 6.0)
					txt(ci, float(nx.x), float(nx.y) - orr - 8.0, "봉인 지점 이동!", 12, C("#ffd166"))
				var lbl := "봉인 해제 중"
				if not O.is_empty() and paused:
					lbl = "피격: 잠시 정지" if float(O.get("hit_pause", 0.0)) > 0.0 else "지점 밖: 정지"
				txt(ci, ox, oy - orr - 10.0, lbl, 11, C("#eeeeff"))
			"exit":
				var open: bool = bool(o.get("open", false))
				var ec := C("#9cffb0") if open else C("#777777")
				ci.draw_arc(Vector2(ox, oy + 10.0), orr * 0.7, PI, TAU, 24, ec, 5.0)
				ci.draw_line(Vector2(ox - orr * 0.7, oy + 10.0), Vector2(ox - orr * 0.7, oy + 30.0), ec, 5.0)
				ci.draw_line(Vector2(ox + orr * 0.7, oy + 10.0), Vector2(ox + orr * 0.7, oy + 30.0), ec, 5.0)
				if open:
					dashed_circle(ci, ox, oy, orr, rgba(156, 255, 176, 0.6), 2.0, 5.0, 5.0)
				txt(ci, ox, oy - 12.0, "출구 열림 — 여기로" if open else "출구 (포로를 모두 구하면 열림)", 11, C("#9cffb0") if open else C("#aaaaaa"))
			"prisoner":
				if bool(o.get("gone", false)):
					continue
				ci.draw_circle(Vector2(ox, oy - 8.0), 5.0, C("#e9c9a8"))
				ci.draw_rect(Rect2(ox - 4.0, oy - 3.0, 8.0, 12.0), C("#b8a080"))
				txt(ci, ox, oy - 16.0, "탈출 중", 10, C("#9cffb0"))

static func draw_pickups(ci: Node2D, st: CombatState) -> void:
	for k in st.pickups:
		var kx: float = k.x
		var ky: float = k.y + sin(float(k.t) * 4.0) * 3.0
		var kr: float = k.r
		ci.draw_circle(Vector2(kx, ky), kr + 6.0 + sin(float(k.t) * 6.0) * 2.0, rgba(120, 255, 160, 0.25))
		ci.draw_circle(Vector2(kx, ky), kr, C("#7fe8a0"))
		ci.draw_circle(Vector2(kx - 4.0, ky - 4.0), 4.0, Color.WHITE)
		ci.draw_line(Vector2(kx - 6.0, ky), Vector2(kx + 6.0, ky), C("#1e4a2a"), 3.0)
		ci.draw_line(Vector2(kx, ky - 6.0), Vector2(kx, ky + 6.0), C("#1e4a2a"), 3.0)
		txt(ci, kx, ky - kr - 6.0, "+%d" % int(k.get("amount", 0)), 11, C("#bfffd0"))

# ---------- 사거리·무기 몸체·기술 상태 ----------
static func draw_range(ci: Node2D, st: CombatState) -> void:
	if st.weapons.is_empty():
		return
	var s: Dictionary = st.weapons[0].stats
	var rr: float = float(s.get("range", 0.0))
	if rr <= 0.0:
		return
	dashed_circle(ci, st.player.x, st.player.y, rr, rgba(150, 210, 255, 0.16), 1.0, 4.0, 6.0)

static func draw_weapon_bodies(ci: Node2D, st: CombatState) -> void:
	var p: Dictionary = st.player
	for w in st.weapons:
		var kind := String(w.stats.get("kind", ""))
		if kind == "orbit":
			for bp in w.get("blade_pos", []):
				if bp.has("ix"):
					ci.draw_line(Vector2(float(bp.ix), float(bp.iy)), Vector2(float(bp.x), float(bp.y)), rgba(143, 182, 238, 0.35), 3.0)
				var T := xf(Vector2(float(bp.x), float(bp.y)), float(bp.a) + st.t * 8.0, Vector2.ONE)
				for i in 3:
					ci.draw_set_transform_matrix(T * rel(TAU / 3.0 * float(i + 1), Vector2.ONE))
					var blade := PackedVector2Array([Vector2(0, 0), Vector2(14, -4), Vector2(16, 0), Vector2(14, 4)])
					ci.draw_colored_polygon(blade, C("#e6edf5"))
					blade.append(Vector2(0, 0))
					ci.draw_polyline(blade, C("#8fb6ee"), 1.5)
				ci.draw_set_transform_matrix(IDENT)
		elif kind == "chain":
			var ox: float = p.x + cos(st.t * 2.0) * 26.0
			var oy: float = p.y - 30.0 + sin(st.t * 3.0) * 6.0
			ci.draw_circle(Vector2(ox, oy), 12.0, rgba(120, 200, 255, 0.35))
			ci.draw_circle(Vector2(ox, oy), 6.0, C("#dff4ff"))
		elif kind == "bolt":
			var ox: float = p.x - 22.0
			var oy: float = p.y - 26.0 + sin(st.t * 3.0 + 1.0) * 4.0
			ci.draw_colored_polygon(PackedVector2Array([Vector2(ox, oy - 9.0), Vector2(ox + 6.0, oy), Vector2(ox, oy + 9.0), Vector2(ox - 6.0, oy)]), C("#bfefff"))
		elif kind == "ember":
			var ox: float = p.x + 24.0
			var oy: float = p.y - 28.0 + sin(st.t * 4.0) * 4.0
			ci.draw_circle(Vector2(ox, oy), 9.0, rgba(255, 150, 60, 0.5))
			ci.draw_circle(Vector2(ox, oy), 4.0, C("#ffd27a"))
	for mn in st.mines:
		if bool(mn.get("dead", false)):
			continue
		var mx: float = mn.x
		var my: float = mn.y
		var armed: bool = float(mn.arm) <= 0.0
		stroke_circle(ci, mx, my, 9.0, rgba(200, 140, 255, 0.9 if armed else 0.4), 2.0)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(mx, my - 6.0), Vector2(mx + 5.0, my + 3.0), Vector2(mx - 5.0, my + 3.0)]), C("#d9b3ff") if armed else C("#8a6bb0"))
		if armed:
			dashed_circle(ci, mx, my, float(mn.r), rgba(200, 140, 255, 0.25), 1.0, 3.0, 5.0)
	var S: Dictionary = st.skill_state
	if S.is_empty():
		return
	var storm: Dictionary = S.get("storm", {})
	if not storm.is_empty():
		for i in 4:
			var rr: float = float(storm.r) * (0.5 + 0.5 * fmod(st.t * 2.0 + float(i) * 0.25, 1.0))
			ci.draw_arc(Vector2(float(storm.x), float(storm.y)), rr, st.t * 10.0 + float(i), st.t * 10.0 + float(i) + 2.2, 20, rgba(230, 240, 255, 0.8), 3.0)
	var g: Dictionary = S.get("gravity", {})
	if not g.is_empty():
		var gx: float = g.x
		var gy: float = g.y
		var gr: float = g.r
		ci.draw_circle(Vector2(gx, gy), gr, rgba(150, 100, 255, 0.18))
		stroke_circle(ci, gx, gy, 14.0 + sin(st.t * 12.0) * 3.0, rgba(200, 170, 255, 0.8), 2.0)
		for i in 8:
			var a: float = float(i) * TAU / 8.0 - st.t * 4.0
			var rr: float = gr * (0.3 + 0.6 * fmod(st.t * 0.8 + float(i) * 0.13, 1.0))
			ci.draw_circle(Vector2(gx + cos(a) * rr, gy + sin(a) * rr), 2.5, rgba(210, 190, 255, 0.7))
	var ward: Dictionary = S.get("ward", {})
	if not ward.is_empty():
		stroke_circle(ci, p.x, p.y - 2.0, float(p.r) + 14.0, rgba(126, 242, 255, 0.9), 3.0)
	var tg = S.get("target")
	if tg != null:
		var tx: float = tg.x
		var ty: float = tg.y
		stroke_circle(ci, tx, ty, 12.0, rgba(255, 240, 150, 0.85), 1.5)
		ci.draw_line(Vector2(tx - 16.0, ty), Vector2(tx - 8.0, ty), rgba(255, 240, 150, 0.85), 1.5)
		ci.draw_line(Vector2(tx + 8.0, ty), Vector2(tx + 16.0, ty), rgba(255, 240, 150, 0.85), 1.5)
		txt(ci, tx, ty - 16.0, "E", 10, rgba(255, 240, 150, 0.9))

# ---------- 내 공격 잔상(반투명, 예고선 아래) ----------
static func draw_player_effects(ci: Node2D, st: CombatState) -> void:
	for f in st.effects:
		var k: float = 1.0 - float(f.t) / maxf(0.001, float(f.ttl))
		var kind := String(f.kind)
		match kind:
			"arc":
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				var ang: float = f.angle
				var half: float = f.half
				if bool(f.get("enemy", false)):
					fill_sector(ci, fx, fy, r, ang - half, ang + half, rgba(255, 120, 80, 0.35 * k))
					ci.draw_arc(Vector2(fx, fy), r * (0.6 + 0.4 * (1.0 - k)), ang - half, ang + half, 18, rgba(255, 220, 200, 0.9 * k), 4.0 * k + 1.0)
				elif String(f.get("mod", "")) == "cross":
					mod_cross_arc(ci, fx, fy, r, ang, half, k)
				else:
					fill_sector(ci, fx, fy, r, ang - half, ang + half, rgba(150, 205, 255, 0.28 * k))
					for i in 3:
						var rr: float = r * (0.55 + 0.45 * (1.0 - k)) - float(i) * 5.0
						var hh: float = half * (1.0 - float(i) * 0.15)
						ci.draw_arc(Vector2(fx, fy), maxf(1.0, rr), ang - hh, ang + hh, 18, rgba(230, 245, 255, (0.9 - float(i) * 0.25) * k), 5.0 - float(i) * 1.5)
			"beam":
				var L: float = f.len
				var W: float = f.w
				var returning: bool = bool(f.get("returning", false))
				ci.draw_set_transform_matrix(xf(Vector2(float(f.x), float(f.y)), float(f.angle), Vector2.ONE))
				# 실제 판정 폭(W)은 그대로. 나가는 검기와 돌아오는 검기는 선두 모양·잔상 방향으로 구분한다(같은 선을 두 번 깜박이지 않는다)
				if returning:
					ci.draw_rect(Rect2(0.0, -W / 2.0, L, W), rgba(244, 198, 109, 0.22 * k))
					# 뒤로 끌리는 잔상: 진행 방향(0 → L) 반대편 꼬리를 계단식으로 옅게
					for i in 4:
						var seg: float = L * (0.18 + 0.2 * float(i))
						ci.draw_rect(Rect2(seg, -W / 2.0 + 2.0, L * 0.10, W - 4.0), rgba(244, 198, 109, (0.30 - 0.06 * float(i)) * k))
					# 선두 = 두 겹 갈매기(돌아오는 방향을 가리킨다)
					for i in 2:
						var d0: float = float(i) * 12.0
						ci.draw_polyline(PackedVector2Array([Vector2(L - 22.0 - d0, -W / 2.0), Vector2(L - d0, 0.0), Vector2(L - 22.0 - d0, W / 2.0)]), rgba(255, 230, 160, (0.95 - 0.35 * float(i)) * k), 3.0)
				else:
					ci.draw_rect(Rect2(0.0, -W / 2.0, L, W), rgba(160, 220, 255, 0.35 * k))
					ci.draw_rect(Rect2(0.0, -2.0, L * (0.6 + 0.4 * (1.0 - k)), 4.0), Color(1, 1, 1, 0.8 * k))
					ci.draw_colored_polygon(PackedVector2Array([Vector2(L, 0.0), Vector2(L - 18.0, -W / 2.0), Vector2(L - 18.0, W / 2.0)]), rgba(200, 240, 255, 0.6 * k))
				ci.draw_set_transform_matrix(IDENT)
			"dagger":
				var side: int = int(f.get("side", 0))
				var half: float = f.half
				var s0: float = 1.0 if side % 2 == 1 else -1.0
				var s1: float = -0.2 if side % 2 == 1 else 0.2
				var a0: float = float(f.angle) - half * s0
				var a1: float = float(f.angle) + half * s1
				ci.draw_arc(Vector2(float(f.x), float(f.y)), float(f.r) * 0.9, minf(a0, a1), maxf(a0, a1), 12, Color(1, 1, 1, 0.9 * k), 3.0)
			"scar": # 잔류 검흔의 '피해가 들어가는 순간'(발동 표시가 아니라 실제 후속 타격 시점)
				var sx: float = f.x
				var sy: float = f.y
				var sr: float = f.r
				var sa: float = f.angle
				var sh: float = f.half
				fill_sector(ci, sx, sy, sr, sa - sh, sa + sh, rgba(238, 228, 202, 0.30 * k))
				# 선두 호를 짧고 두껍게 — 앞선 점선 흔적(scar_mark)과 확실히 다른 실루엣
				ci.draw_arc(Vector2(sx, sy), sr * (0.72 + 0.28 * (1.0 - k)), sa - sh, sa + sh, 20, rgba(255, 245, 220, 0.95 * k), 5.0 * k + 2.0)
			"scar_mark": # 남아 있는 흔적(무해한 장식): 채우지 않고 점선 윤곽만 — 위험 범위 표시와 혼동되지 않게
				var mx: float = f.x
				var my: float = f.y
				var mr: float = f.r
				var ma: float = f.angle
				var mh: float = f.half
				var edge := arc_pts(mx, my, mr, ma - mh, ma + mh, 16)
				for i in range(0, edge.size() - 1, 2):
					ci.draw_line(edge[i], edge[i + 1], rgba(238, 228, 202, 0.42 * k), 1.5)
				ci.draw_line(Vector2(mx, my), Vector2(mx + cos(ma - mh) * mr, my + sin(ma - mh) * mr), rgba(238, 228, 202, 0.22 * k), 1.0)
				ci.draw_line(Vector2(mx, my), Vector2(mx + cos(ma + mh) * mr, my + sin(ma + mh) * mr), rgba(238, 228, 202, 0.22 * k), 1.0)
			"split_node": # 분열 창날: 실제 첫 명중 지점의 분기 결절 + 두 방향의 짧은 안내 궤적(판정 없음 = 점선)
				var nx: float = f.x
				var ny: float = f.y
				var na: float = f.angle
				var grow: float = 1.0 - k
				stroke_circle(ci, nx, ny, 5.0 + 7.0 * grow, rgba(244, 198, 109, 0.95 * k), 2.5)
				ci.draw_circle(Vector2(nx, ny), 3.0, rgba(255, 236, 190, 0.95 * k))
				for da in [-0.6, 0.6]:
					var a2: float = na + float(da)
					var p0 := Vector2(nx + cos(a2) * 10.0, ny + sin(a2) * 10.0)
					var p1 := Vector2(nx + cos(a2) * (26.0 + 34.0 * grow), ny + sin(a2) * (26.0 + 34.0 * grow))
					dashed_line(ci, p0, p1, rgba(244, 198, 109, 0.7 * k), 2.0, 5.0, 4.0)
					ci.draw_polyline(PackedVector2Array([p1 - Vector2(cos(a2 + 0.5), sin(a2 + 0.5)) * 7.0, p1, p1 - Vector2(cos(a2 - 0.5), sin(a2 - 0.5)) * 7.0]), rgba(255, 236, 190, 0.85 * k), 2.0)
			"shatter_burst": # 깨지는 수정: 파열 순간(표시 전용). 실제 적중은 아래 파편이 맡는다
				var bx: float = f.x
				var by: float = f.y
				var gr: float = 1.0 - k
				for i in 6:
					var a3: float = float(i) * TAU / 6.0 + 0.26
					var r0: float = 4.0 + 6.0 * gr
					var r1: float = 12.0 + 20.0 * gr
					ci.draw_line(Vector2(bx + cos(a3) * r0, by + sin(a3) * r0), Vector2(bx + cos(a3) * r1, by + sin(a3) * r1), rgba(144, 229, 244, 0.9 * k), 2.5)
				var hexp := PackedVector2Array()
				for i in 7:
					var a4: float = float(i) * TAU / 6.0
					hexp.append(Vector2(bx + cos(a4) * (9.0 + 12.0 * gr), by + sin(a4) * (9.0 + 12.0 * gr)))
				ci.draw_polyline(hexp, rgba(210, 245, 255, 0.85 * k), 2.0)
			"impact":
				var r: float = f.r
				var c := Vector2(float(f.x), float(f.y))
				ci.draw_circle(c, r * (0.6 + 0.4 * (1.0 - k)), rgba(200, 150, 90, 0.35 * k) if bool(f.get("after", false)) else rgba(230, 200, 150, 0.4 * k))
				stroke_circle(ci, c.x, c.y, r * (1.0 - k * 0.25), rgba(255, 230, 180, 0.9 * k), 5.0 * k + 1.0)
			"chain":
				var pts: Array = f.get("pts", [])
				if pts.size() >= 2:
					var poly := PackedVector2Array()
					for i in pts.size():
						var p0 = pts[i]
						var v0 := Vector2(float(p0.x), float(p0.y)) if typeof(p0) == TYPE_DICTIONARY else Vector2(float(p0[0]), float(p0[1]))
						if i > 0:
							var p1 = pts[i - 1]
							var v1 := Vector2(float(p1.x), float(p1.y)) if typeof(p1) == TYPE_DICTIONARY else Vector2(float(p1[0]), float(p1[1]))
							var off: float = 8.0 if i % 2 == 1 else -8.0
							poly.append(Vector2((v0.x + v1.x) / 2.0 + off, (v0.y + v1.y) / 2.0 - off))
						poly.append(v0)
					ci.draw_polyline(poly, rgba(120, 200, 255, 0.5 * k), 7.0)
					ci.draw_polyline(poly, rgba(200, 240, 255, 0.95 * k), 3.0)
			"emberthrow":
				var kk: float = float(f.t) / maxf(0.001, float(f.ttl))
				var x0: float = f.x0
				var y0: float = f.y0
				var ex: float = x0 + (float(f.x) - x0) * kk
				var ey: float = y0 + (float(f.y) - y0) * kk - sin(kk * PI) * 60.0
				var arcp := PackedVector2Array()
				for i in 9:
					var q: float = kk * float(i) / 8.0
					arcp.append(Vector2(x0 + (float(f.x) - x0) * q, y0 + (float(f.y) - y0) * q - sin(q * PI) * 60.0))
				ci.draw_polyline(arcp, rgba(255, 179, 71, 0.4), 1.5)
				ci.draw_circle(Vector2(ex, ey), 6.0, C("#ffb347"))
			"mineburst":
				var c := Vector2(float(f.x), float(f.y))
				ci.draw_circle(c, float(f.r) * (0.5 + 0.5 * (1.0 - k)), rgba(190, 120, 255, 0.4 * k))
				stroke_circle(ci, c.x, c.y, float(f.r), rgba(230, 200, 255, 0.9 * k), 4.0)
			"strikewarn":
				dashed_circle(ci, float(f.x), float(f.y), float(f.r), rgba(255, 240, 150, 0.6 + 0.4 * (1.0 - k)), 2.0, 4.0, 4.0)
			"strike":
				var fx: float = f.x
				var fy: float = f.y
				ci.draw_circle(Vector2(fx, fy), float(f.r), rgba(255, 250, 200, 0.4 * k))
				ci.draw_polyline(PackedVector2Array([Vector2(fx + 10.0, fy - 160.0), Vector2(fx - 8.0, fy - 70.0), Vector2(fx + 8.0, fy - 60.0), Vector2(fx, fy)]), Color(1, 1, 1, k), 4.0)
			"gust":
				var gc := rgba(200, 255, 220, 0.8 * k)
				if bool(f.get("whirl", false)):
					for i in 3:
						ci.draw_arc(Vector2(float(f.x), float(f.y)), float(f.r) * (0.4 + 0.2 * float(i)) * (1.0 + (1.0 - k) * 0.6), float(i), float(i) + 4.0, 24, gc, 3.0)
				else:
					ci.draw_set_transform_matrix(xf(Vector2(float(f.x), float(f.y)), float(f.angle), Vector2.ONE))
					var W: float = f.w
					for i in 3:
						var xx: float = float(f.len) * (0.3 + 0.35 * float(i)) * (1.0 - k * 0.3)
						var hw: float = W / 2.0 * (0.4 + 0.3 * float(i))
						ci.draw_polyline(quad_pts(Vector2(xx, -hw), Vector2(xx + 25.0, 0.0), Vector2(xx, hw), 8), gc, 3.0)
					ci.draw_set_transform_matrix(IDENT)
			"spin":
				var c := Vector2(float(f.x), float(f.y))
				stroke_circle(ci, c.x, c.y, float(f.r) * (0.7 + 0.3 * (1.0 - k)), rgba(210, 235, 255, 0.85 * k), 7.0 * k + 2.0)
				ci.draw_circle(c, float(f.r), rgba(150, 205, 255, 0.18 * k))

## 교차 검격의 두 번째 궤적: 겹쳐도 방향이 읽히도록 채움 대신 빗금(교차 해칭) + 한쪽 선두만 두껍게 그린다.
## 실제 판정(부채꼴 r·half)은 기본 검격과 같고 여기서 늘리지 않는다.
static func mod_cross_arc(ci: CanvasItem, cx: float, cy: float, r: float, ang: float, half: float, k: float) -> void:
	var col := rgba(238, 228, 202, 0.85 * k)
	fill_sector(ci, cx, cy, r, ang - half, ang + half, rgba(238, 228, 202, 0.14 * k))
	# 빗금 5줄(기본 검격의 동심 호와 다른 실루엣)
	for i in 5:
		var q: float = float(i) / 4.0
		var a: float = ang - half + half * 2.0 * q
		var r0: float = r * (0.25 + 0.15 * q)
		ci.draw_line(Vector2(cx + cos(a) * r0, cy + sin(a) * r0), Vector2(cx + cos(a) * r, cy + sin(a) * r), rgba(238, 228, 202, 0.5 * k), 2.0)
	# 선두(진행 방향 쪽 가장자리)만 두껍게 = 어느 쪽에서 들어온 궤적인지 읽힌다
	var lead := arc_pts(cx, cy, r * (0.7 + 0.3 * (1.0 - k)), ang - half, ang + half, 18)
	ci.draw_polyline(lead, col, 4.0 * k + 1.5)
	ci.draw_line(Vector2(cx, cy), Vector2(cx + cos(ang + half) * r, cy + sin(ang + half) * r), col, 2.5)

# ---------- 상태 아이콘 ----------
static func status_icon(ci: Node2D, x: float, y: float, kind: String) -> void:
	match kind:
		"chill":
			for i in 3:
				var a: float = float(i) * PI / 3.0
				ci.draw_line(Vector2(x - cos(a) * 6.0, y - sin(a) * 6.0), Vector2(x + cos(a) * 6.0, y + sin(a) * 6.0), C("#9fe8ff"), 2.0)
		"mark":
			stroke_circle(ci, x, y, 6.0, C("#ff5a5a"), 2.0)
			ci.draw_line(Vector2(x - 9.0, y), Vector2(x + 9.0, y), C("#ff5a5a"), 2.0)
			ci.draw_line(Vector2(x, y - 9.0), Vector2(x, y + 9.0), C("#ff5a5a"), 2.0)
		"exposed":
			var pts := PackedVector2Array()
			for i in 5:
				var a: float = -PI / 2.0 + float(i) * TAU / 5.0
				var b: float = a + TAU / 10.0
				pts.append(Vector2(x + cos(a) * 7.0, y + sin(a) * 7.0))
				pts.append(Vector2(x + cos(b) * 3.0, y + sin(b) * 3.0))
			ci.draw_colored_polygon(pts, C("#ffd166"))
		"slow":
			stroke_circle(ci, x, y, 6.0, C("#a9d8ff"), 2.0)
			ci.draw_polyline(PackedVector2Array([Vector2(x, y), Vector2(x, y - 4.0), Vector2(x + 3.0, y - 4.0)]), C("#a9d8ff"), 2.0)
		"burn":
			var pts := quad_pts(Vector2(x, y - 7.0), Vector2(x + 7.0, y), Vector2(x, y + 7.0), 6)
			pts.append_array(quad_pts(Vector2(x, y + 7.0), Vector2(x - 7.0, y), Vector2(x, y - 7.0), 6))
			ci.draw_colored_polygon(pts, C("#ff9f43"))
		"bleed":
			ci.draw_circle(Vector2(x, y + 2.0), 4.0, C("#ff5a5a"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 7.0), Vector2(x + 4.0, y + 1.0), Vector2(x - 4.0, y + 1.0)]), C("#ff5a5a"))
		"conduct":
			ci.draw_polyline(PackedVector2Array([Vector2(x + 3.0, y - 7.0), Vector2(x - 3.0, y), Vector2(x + 2.0, y), Vector2(x - 3.0, y + 7.0)]), C("#bfe8ff"), 2.0)

# ---------- 늑대(측면, 좌우 반전). 상태: approach|bite_track|bite_lock|bite_hit|bite_recover|crouch|lock|dash|recover ----------
static func draw_wolf(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var p: Dictionary = st.player
	var ex: float = e.x
	var ey: float = e.y
	var s: float = float(e.r) / 14.0 * VS
	var stt := String(e.state)
	var ang: float
	if stt == "crouch" or stt == "bite_track":
		ang = float(e.aim_angle)
	elif stt == "lock" or stt == "dash" or stt == "bite_lock" or stt == "bite_hit":
		ang = float(e.dir)
	else:
		ang = atan2(float(p.y) - ey, float(p.x) - ex)
	var face_x: float = float(e.get("face_x", 1.0)) if (stt == "approach" or stt == "recover" or stt == "bite_recover") else (1.0 if cos(ang) >= 0.0 else -1.0)
	if stt == "approach" and absf(cos(ang)) > 0.2:
		face_x = 1.0 if cos(ang) >= 0.0 else -1.0
	var dying: bool = e.dead
	var elite: bool = bool(e.get("elite", false))
	var fur := C("#a8873f") if elite else C("#8d9198")
	var fur2 := C("#6b5326") if elite else C("#5c6068")
	var belly := C("#d6bd85") if elite else C("#c2c5ca")
	# 상태 색: 빈틈(노랑)·물기 뒤 멈춤(연파랑)·돌진(붉게)·물기 고정(진한 주황)
	if stt == "recover":
		fur = fur.lerp(Color(0.95, 0.8, 0.4), 0.6)
		belly = belly.lerp(Color(1.0, 0.9, 0.6), 0.5)
	elif stt == "bite_recover":
		fur = fur.lerp(Color(0.65, 0.72, 0.85), 0.6)
	elif stt == "dash":
		fur = fur.lerp(Color(1.0, 0.55, 0.45), 0.35)
	elif stt == "bite_lock":
		fur = fur.lerp(Color(0.75, 0.45, 0.25), 0.45)
	var flash: bool = float(e.flash) > 0.0 or stt == "bite_hit"
	var chilled: bool = float(e.chill) > 0.0
	var body_c := Color.WHITE if flash else (C("#b9d4e6") if chilled else fur)
	var alpha: float = maxf(0.0, 1.0 - maxf(0.0, float(e.death_t) - 0.4) / 0.5) if dying else 1.0
	if alpha <= 0.0:
		return
	shadow(ci, ex, ey + 12.0 * s, 17.0 * s, 5.0 * s)
	if stt == "dash":
		var dr: float = e.dir
		for i in range(1, 4):
			fill_ellipse(ci, ex - cos(dr) * 12.0 * float(i), ey - sin(dr) * 12.0 * float(i), 18.0 * s, 7.0 * s, rgba(210, 210, 220, 0.22 / float(i)), dr, 12)
	# 자세
	var body_y := 0.0
	var stretch := 1.0
	var ry := 8.0
	var head_y := -7.0
	var tail_up := 1.0
	var leg_spread := false
	var leg_fold := false
	var jaw := 0.12
	var tilt := 0.0
	var st_t: float = float(e.state_t)
	var bite_t: float = float(e.get("bite_t", 9.0))
	match stt:
		"crouch":
			body_y = 3.0; ry = 6.5; head_y = -2.0; tail_up = -0.6; leg_fold = true; stretch = 1.1; jaw = 0.25; tilt = -0.12
		"lock":
			body_y = 4.0; ry = 6.5; head_y = -1.0; tail_up = -0.8; leg_fold = true; stretch = 0.95; jaw = 0.6; tilt = -0.2
		"dash":
			body_y = 1.0; ry = 6.5; head_y = -3.0; tail_up = 0.0; leg_spread = true; stretch = 1.35; jaw = 0.05 if bite_t < 0.2 else 0.7
		"recover":
			body_y = 2.0; head_y = -4.0; tail_up = -0.3; tilt = sin(st_t * 14.0) * 0.12; jaw = 0.35
		"bite_track":
			head_y = -5.0; jaw = 0.3; tail_up = 0.4; stretch = 1.05
		"bite_lock":
			body_y = 1.0; head_y = -4.0; jaw = 0.65; tail_up = -0.2; leg_fold = true
		"bite_hit":
			body_y = 1.0; head_y = -4.0; jaw = 0.05; stretch = 1.15; leg_spread = true
		"bite_recover":
			body_y = 2.0; head_y = -4.0; jaw = 0.3; tilt = sin(st_t * 10.0) * 0.08; tail_up = -0.2
	if dying:
		tilt = minf(1.35, float(e.death_t) * 4.0)
		body_y = minf(8.0, float(e.death_t) * 20.0)
		jaw = 0.4
	var T := xf(Vector2(ex, ey), 0.0, Vector2(face_x, 1.0)) * rel(tilt, Vector2(s, s))
	ci.draw_set_transform_matrix(T)
	var L: float = 16.0 * stretch
	var a_fur2 := Color(fur2, fur2.a * alpha)
	# 꼬리
	ci.draw_polyline(quad_pts(Vector2(-L + 2.0, body_y - 1.0), Vector2(-L - 8.0, body_y - 2.0 - 6.0 * tail_up), Vector2(-L - 12.0, body_y - 10.0 * tail_up + 2.0), 8), a_fur2, 4.0)
	# 다리(뒤 2, 앞 2)
	var legs := [[-9.0, 0.0], [-7.0, PI], [8.0, PI], [10.0, 0.0]]
	var move_t: float = float(e.get("move_t", 0.0))
	var hip_y: float = body_y + 4.0
	for i in 4:
		var lhx: float = legs[i][0]
		var ph: float = legs[i][1]
		var fx: float
		var fy: float
		if leg_spread:
			fx = lhx + (9.0 if lhx > 0.0 else -9.0); fy = hip_y + 7.0
		elif leg_fold:
			fx = lhx + (3.0 if lhx > 0.0 else -3.0); fy = hip_y + 6.0
		elif dying:
			fx = lhx + 3.0; fy = hip_y + 6.0
		else:
			var walking: bool = stt == "approach"
			var sw: float = sin(move_t * TAU * 0.9 + ph) if walking else 0.0
			fx = lhx + sw * 5.0
			fy = hip_y + 10.0 - (maxf(0.0, cos(move_t * TAU * 0.9 + ph)) * 2.0 if walking else 0.0)
		var kx: float = (lhx + fx) / 2.0 + (1.0 if lhx > 0.0 else -2.0)
		var ky: float = (hip_y + fy) / 2.0
		ci.draw_polyline(PackedVector2Array([Vector2(lhx, hip_y), Vector2(kx, ky), Vector2(fx, fy)]), a_fur2, 3.2)
		fill_ellipse(ci, fx + 1.0, fy, 2.5, 1.6, C("#2f3136", alpha), 0.0, 8)
	# 몸통
	fill_ellipse(ci, 0.0, body_y, L, ry, Color(body_c, alpha), 0.0, 24)
	fill_ellipse(ci, 1.0, body_y + 3.0, L * 0.7, ry * 0.45, Color(Color.WHITE if flash else belly, alpha), 0.0, 16)
	if elite:
		fill_ellipse(ci, L * 0.45, body_y - 3.0, L * 0.45, ry * 0.7, a_fur2, 0.0, 16)
	# 머리
	var hx: float = L - 2.0
	var hy: float = body_y + head_y
	ci.draw_circle(Vector2(hx, hy), 7.0, Color(body_c, alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(hx + 3.0, hy - 4.0), Vector2(hx + 15.0, hy + 0.5), Vector2(hx + 4.0, hy + 3.0)]), Color(body_c, alpha))
	ci.draw_circle(Vector2(hx + 14.5, hy), 1.6, C("#1e1f22", alpha))
	# 아래턱(열림 = jaw)
	ci.draw_set_transform_matrix(T * Transform2D(jaw, Vector2(hx + 3.0, hy + 2.0)))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(11, 0), Vector2(1, 3.5)]), Color(Color.WHITE if flash else fur2, alpha))
	if jaw > 0.2:
		for i in 3:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(3.0 + float(i) * 2.6, 0.0), Vector2(4.0 + float(i) * 2.6, -2.2), Vector2(5.0 + float(i) * 2.6, 0.0)]), Color(1, 1, 1, alpha))
	if stt == "recover" and not dying:
		fill_ellipse(ci, 6.0, 2.5, 3.0, 1.5, C("#e06a7a", alpha), 0.3, 8)
	ci.draw_set_transform_matrix(T)
	if jaw > 0.2:
		for i in 3:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(hx + 6.0 + float(i) * 2.6, hy + 1.5), Vector2(hx + 7.0 + float(i) * 2.6, hy + 4.0), Vector2(hx + 8.0 + float(i) * 2.6, hy + 1.5)]), Color(1, 1, 1, alpha))
	if bite_t < 0.15:
		var kb: float = bite_t / 0.15
		for i in range(-1, 2):
			ci.draw_arc(Vector2(hx + 12.0, hy + 1.0), 8.0 + 6.0 * kb, -0.6 + float(i) * 0.5, -0.2 + float(i) * 0.5, 6, Color(1, 1, 1, (1.0 - kb) * alpha), 2.0)
	# 귀(준비·확정 시 뒤로)
	var ear_back: float = -3.0 if (stt == "crouch" or stt == "lock" or stt == "dash" or stt == "bite_lock") else 0.0
	var ear_c := Color(Color.WHITE if flash else fur2, alpha)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(hx - 3.0, hy - 4.0), Vector2(hx - 6.0 + ear_back, hy - 13.0), Vector2(hx + 1.0, hy - 6.0)]), ear_c)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(hx + 1.0, hy - 5.0), Vector2(hx - 1.0 + ear_back, hy - 12.0), Vector2(hx + 5.0, hy - 5.0)]), ear_c)
	# 눈
	ci.draw_circle(Vector2(hx + 3.0, hy - 1.5), 1.7, C("#333333", alpha) if dying else (C("#ffd27a", alpha) if stt == "approach" else C("#ff4a4a", alpha)))
	if elite:
		ci.draw_line(Vector2(hx - 2.0, hy - 6.0), Vector2(hx + 2.0, hy + 1.0), C("#3b2c12", alpha), 1.5)
	ci.draw_set_transform_matrix(IDENT)

# ---------- 보스: 가시갈기(늑대 확장) ----------
static func draw_thornmane(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var p: Dictionary = st.player
	var ex: float = e.x
	var ey: float = e.y
	var s: float = float(e.r) / 14.0 * 0.95
	var stt := String(e.state)
	var land: Dictionary = e.get("land", {})
	var lf: Dictionary = e.get("leap_from", {})
	var facing: float
	if stt == "sweep_aim" or stt == "pounce_aim" or stt == "dash_aim":
		facing = float(e.aim_angle)
	elif stt == "sweep_lock" or stt == "dash_lock" or stt == "dash":
		facing = float(e.dir)
	elif stt == "leap" and not land.is_empty() and not lf.is_empty():
		facing = atan2(float(land.y) - float(lf.y), float(land.x) - float(lf.x))
	else:
		facing = atan2(float(p.y) - ey, float(p.x) - ex)
	var face_x: float = (1.0 if cos(facing) >= 0.0 else -1.0) if absf(cos(facing)) > 0.15 else float(e.get("face_x", 1.0))
	var dying: bool = e.dead
	var alpha: float = maxf(0.25, 1.0 - maxf(0.0, float(e.death_t) - 1.2) / 1.5) if dying else 1.0
	var air: float = sin(float(e.get("leap_k", 0.0)) * PI) * 90.0 if stt == "leap" else 0.0
	shadow(ci, ex, ey + 16.0 * s, (17.0 - air * 0.05) * s, (5.0 - air * 0.02) * s)
	if stt == "dash":
		var dr: float = e.dir
		for i in range(1, 4):
			fill_ellipse(ci, ex - cos(dr) * 26.0 * float(i), ey - sin(dr) * 26.0 * float(i), 20.0 * s, 8.0 * s, rgba(120, 100, 70, 0.22 / float(i)), dr, 12)
	var body_y := 0.0
	var ry := 9.0
	var head_y := -8.0
	var head_tilt := 0.0
	var tail_up := 0.8
	var stretch := 1.0
	var leg_spread := false
	var leg_fold := false
	var jaw := 0.15
	var tilt := 0.0
	var mane_up := 0.0
	var breathe := false
	var st_t: float = float(e.state_t)
	var bite_t: float = float(e.get("bite_t", 9.0))
	match stt:
		"intro": mane_up = 1.0; head_tilt = -0.9; tail_up = 1.0; jaw = 0.6
		"sweep_aim": head_tilt = -0.55 * minf(1.0, st_t / 0.3); tilt = -0.06; jaw = 0.3
		"sweep_lock": head_tilt = -0.75; tilt = -0.1; jaw = 0.6
		"dash_aim": body_y = 4.0; ry = 7.5; head_y = -3.0; tail_up = -0.5; leg_fold = true; tilt = -0.12; jaw = 0.25
		"dash_lock": body_y = 5.0; ry = 7.5; head_y = -2.0; tail_up = -0.7; leg_fold = true; tilt = -0.2; jaw = 0.6
		"dash": body_y = 1.0; ry = 7.5; head_y = -4.0; stretch = 1.35; leg_spread = true; jaw = 0.05 if bite_t < 0.2 else 0.7
		"howl": mane_up = 1.0; head_tilt = -1.1; tail_up = 1.0; jaw = 0.7
		"pounce_aim", "pounce_lock": body_y = 6.0; ry = 7.0; head_y = -1.0; leg_fold = true; stretch = 0.85; tail_up = -0.4; jaw = 0.3
		"leap": body_y = 0.0; stretch = 1.2; leg_spread = true; head_y = -6.0; jaw = 0.6; tail_up = 0.3
		"recover": body_y = 3.0; head_y = 2.0; head_tilt = 0.35; tail_up = -0.4; breathe = true; jaw = 0.4
		"stagger": tilt = sin(st_t * 14.0) * 0.15; head_tilt = 0.2; jaw = 0.4
		"roar", "summon": mane_up = 1.0; head_tilt = -0.8; jaw = 0.8; tail_up = 1.0
		_: ry = 9.0 + 0.4 * sin(float(e.get("anim_t", 0.0)) * 3.0)
	if dying:
		tilt = minf(1.3, float(e.death_t) * 2.5)
		body_y = minf(12.0, float(e.death_t) * 20.0)
		jaw = 0.5
	if breathe:
		ry *= 1.0 + 0.05 * sin(st_t * 6.0)
	var T := xf(Vector2(ex, ey - air), 0.0, Vector2(face_x, 1.0)) * rel(tilt, Vector2(s, s))
	ci.draw_set_transform_matrix(T)
	var L: float = 18.0 * stretch
	var fur := C("#6e5a3a", alpha)
	var fur2 := C("#4a3a24", alpha)
	var belly := C("#a08a62", alpha)
	var thorn := C("#1c1a17", alpha)
	var flash: bool = float(e.flash) > 0.0
	var body_c := Color(1, 1, 1, alpha) if flash else (C("#9fb4c4", alpha) if float(e.chill) > 0.0 else fur)
	ci.draw_polyline(quad_pts(Vector2(-L + 2.0, body_y - 1.0), Vector2(-L - 9.0, body_y - 2.0 - 7.0 * tail_up), Vector2(-L - 15.0, body_y - 12.0 * tail_up + 2.0), 8), fur2, 5.0)
	var legs := [[-10.0, 0.0], [-8.0, PI], [9.0, PI], [12.0, 0.0]]
	var move_t: float = float(e.get("move_t", 0.0))
	var hip_y: float = body_y + 5.0
	for i in 4:
		var lhx: float = legs[i][0]
		var ph: float = legs[i][1]
		var fx: float
		var fy: float
		if leg_spread:
			fx = lhx + (11.0 if lhx > 0.0 else -11.0); fy = hip_y + 8.0
		elif leg_fold:
			fx = lhx + (3.0 if lhx > 0.0 else -3.0); fy = hip_y + 7.0
		elif dying:
			fx = lhx + 3.0; fy = hip_y + 7.0
		elif stt == "recover":
			fx = lhx + (6.0 if lhx > 0.0 else -2.0); fy = hip_y + 10.0
		else:
			var sw: float = sin(move_t * TAU * 0.6 + ph) if stt == "approach" else 0.0
			fx = lhx + sw * 6.0; fy = hip_y + 11.0
		var kx: float = (lhx + fx) / 2.0 + (1.5 if lhx > 0.0 else -2.5)
		var ky: float = (hip_y + fy) / 2.0
		ci.draw_polyline(PackedVector2Array([Vector2(lhx, hip_y), Vector2(kx, ky), Vector2(fx, fy)]), fur2, 4.5)
		fill_ellipse(ci, fx + 1.0, fy, 3.2, 2.0, C("#26221e", alpha), 0.0, 8)
	fill_ellipse(ci, 0.0, body_y, L, ry, body_c, 0.0, 24)
	fill_ellipse(ci, L * 0.45, body_y - 3.0, L * 0.5, ry * 0.95, body_c, 0.0, 16)
	fill_ellipse(ci, 0.0, body_y + 3.5, L * 0.7, ry * 0.45, Color(1, 1, 1, alpha) if flash else belly, 0.0, 16)
	ci.draw_line(Vector2(-6.0, body_y - 5.0), Vector2(-1.0, body_y + 1.0), C("#3a2a1c", alpha), 1.5)
	ci.draw_line(Vector2(-3.0, body_y - 6.0), Vector2(2.0, body_y), C("#3a2a1c", alpha), 1.5)
	for i in 7:
		var bx: float = L * 0.75 - float(i) * 4.2
		var by: float = body_y - ry * 0.85 + (1.0 if i > 3 else 0.0)
		var h: float = (6.0 + (4.0 if i < 4 else 1.0)) * (1.0 + 0.6 * mane_up)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(bx - 1.6, by + 1.0), Vector2(bx - 3.0 + float(i % 2), by - h), Vector2(bx + 1.6, by + 1.0)]), thorn)
	var hx: float = L - 1.0
	var hy: float = body_y + head_y
	var TH := T * Transform2D(head_tilt, Vector2(hx, hy))
	ci.draw_set_transform_matrix(TH)
	ci.draw_circle(Vector2.ZERO, 9.0, body_c)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(4, -5), Vector2(19, 1), Vector2(5, 4)]), body_c)
	ci.draw_circle(Vector2(18.5, 0.5), 2.0, C("#1e1f22", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(11, 3), Vector2(12.5, 8.5), Vector2(14, 3)]), C("#f3ead8", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(6, 3.5), Vector2(6.8, 5.5), Vector2(8, 3.5)]), C("#f3ead8", alpha))
	ci.draw_set_transform_matrix(TH * Transform2D(jaw, Vector2(4.0, 3.0)))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(14, 0), Vector2(1, 4.5)]), Color(1, 1, 1, alpha) if flash else fur2)
	if jaw > 0.25:
		for i in 4:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(3.0 + float(i) * 2.8, 0.0), Vector2(4.0 + float(i) * 2.8, -2.6), Vector2(5.0 + float(i) * 2.8, 0.0)]), C("#f3ead8", alpha))
	ci.draw_set_transform_matrix(TH)
	var ear_back: float = -4.0 if (stt == "dash_aim" or stt == "dash_lock" or stt == "dash") else (2.0 if mane_up > 0.0 else 0.0)
	var ear_c := Color(1, 1, 1, alpha) if flash else fur2
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, -5), Vector2(-8.0 + ear_back, -17.0), Vector2(1, -8)]), ear_c)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(1, -6), Vector2(-1.0 + ear_back, -16.0), Vector2(6, -6)]), ear_c)
	ci.draw_circle(Vector2(4.0, -2.5), 2.2, C("#333333", alpha) if dying else (C("#ffb347", alpha) if stt == "approach" else C("#ff3b3b", alpha)))
	ci.draw_line(Vector2(-2, -8), Vector2(2, 1), C("#2a1e12", alpha), 1.5)
	ci.draw_set_transform_matrix(T)
	if bite_t < 0.15 and not dying:
		var kb: float = bite_t / 0.15
		for i in range(-1, 2):
			ci.draw_arc(Vector2(hx + 16.0, hy + 1.0), 10.0 + 8.0 * kb, -0.6 + float(i) * 0.5, -0.2 + float(i) * 0.5, 6, Color(1, 1, 1, (1.0 - kb) * alpha), 2.5)
	ci.draw_set_transform_matrix(IDENT)

# 봉인 수호자: 돌 갑옷 거인(각진 몸통·어깨 판·룬 눈)
static func draw_guardian(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 40.0
	var dying: bool = e.dead
	var alpha: float = maxf(0.25, 1.0 - maxf(0.0, float(e.death_t) - 1.2) / 1.5) if dying else 1.0
	var glow: float = 0.5 + 0.5 * sin(st.t * 3.0)
	var stt := String(e.state)
	shadow(ci, float(e.x), float(e.y) + 30.0 * s, 34.0 * s, 10.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), minf(1.2, float(e.death_t) * 2.0) if dying else 0.0, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var flash: bool = float(e.flash) > 0.0
	var armor := Color(1, 1, 1, alpha) if flash else C("#5a6a9a", alpha)
	var dark := C("#eeeeff", alpha) if flash else C("#38456a", alpha)
	ci.draw_rect(Rect2(-22.0 * s, 6.0 * s, 16.0 * s, 26.0 * s), dark)
	ci.draw_rect(Rect2(6.0 * s, 6.0 * s, 16.0 * s, 26.0 * s), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-30.0 * s, -26.0 * s), Vector2(30.0 * s, -26.0 * s), Vector2(26.0 * s, 12.0 * s), Vector2(-26.0 * s, 12.0 * s)]), armor)
	ci.draw_rect(Rect2(-46.0 * s, -30.0 * s, 18.0 * s, 14.0 * s), dark)
	ci.draw_rect(Rect2(28.0 * s, -30.0 * s, 18.0 * s, 14.0 * s), dark)
	var arm_ang: float = (-0.9 + (0.3 if stt == "sweep_lock" else 0.0)) if (stt == "sweep_aim" or stt == "sweep_lock") else 0.4
	if stt == "shock_aim" or stt == "shock_lock":
		arm_ang = -1.6 + 0.4 * minf(1.0, float(e.state_t) * 2.0)
	ci.draw_set_transform_matrix(T * Transform2D(arm_ang, Vector2(38.0 * s, -20.0 * s)))
	ci.draw_rect(Rect2(-6.0 * s, 0.0, 12.0 * s, 44.0 * s), armor)
	ci.draw_rect(Rect2(-12.0 * s, 40.0 * s, 24.0 * s, 14.0 * s), dark)
	ci.draw_set_transform_matrix(T * Transform2D(-0.3, Vector2(-38.0 * s, -20.0 * s)))
	ci.draw_rect(Rect2(-6.0 * s, 0.0, 12.0 * s, 40.0 * s), armor)
	ci.draw_set_transform_matrix(T)
	ci.draw_rect(Rect2(-14.0 * s, -44.0 * s, 28.0 * s, 20.0 * s), armor)
	ci.draw_rect(Rect2(-9.0 * s, -38.0 * s, 18.0 * s, 4.0 * s), rgba(150, 210, 255, (0.5 + 0.5 * glow) * alpha))
	ci.draw_arc(Vector2(0.0, -8.0 * s), 9.0 * s, 0.0, TAU, 20, rgba(150, 210, 255, (0.4 + 0.4 * glow) * alpha), 2.0)
	ci.draw_line(Vector2(0.0, -17.0 * s), Vector2(0.0, 1.0 * s), rgba(150, 210, 255, (0.4 + 0.4 * glow) * alpha), 2.0)
	ci.draw_set_transform_matrix(IDENT)

# 예언을 먹는 자: 떠 있는 검은 구체·갈라진 입·여러 눈·촉수
static func draw_eater(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 38.0
	var dying: bool = e.dead
	var alpha: float = maxf(0.25, 1.0 - maxf(0.0, float(e.death_t) - 1.2) / 1.5) if dying else 1.0
	var bob: float = sin(st.t * 2.2) * 4.0
	var stt := String(e.state)
	shadow(ci, float(e.x), float(e.y) + 30.0 * s, 30.0 * s, 9.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y) - 8.0 * s + bob), 0.0, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var flash: bool = float(e.flash) > 0.0
	var body := Color(1, 1, 1, alpha) if flash else C("#3a1f4a", alpha)
	var edge := C("#eeeeff", alpha) if flash else C("#7a3a8a", alpha)
	for i in 6:
		var a: float = float(i) * TAU / 6.0 + st.t * 0.7
		var L: float = (30.0 + 10.0 * sin(st.t * 3.0 + float(i))) * s
		var p0 := Vector2(cos(a) * 26.0 * s, sin(a) * 26.0 * s)
		var p1 := Vector2(cos(a + 0.4) * (26.0 * s + L * 0.6), sin(a + 0.4) * (26.0 * s + L * 0.6))
		var p2 := Vector2(cos(a) * (26.0 * s + L), sin(a) * (26.0 * s + L))
		ci.draw_polyline(quad_pts(p0, p1, p2, 8), edge, 4.0 * s)
	var bpts := ellipse_pts(0.0, 0.0, 34.0 * s, 30.0 * s, 0.2, 28)
	ci.draw_colored_polygon(bpts, body)
	bpts.append(bpts[0])
	ci.draw_polyline(bpts, edge, 3.0)
	var open: float = 0.9 if (stt == "wide_aim" or stt == "wide_lock" or stt == "mark_cast") else (0.6 if stt == "summon" else 0.25)
	fill_ellipse(ci, 2.0 * s, 8.0 * s, 20.0 * s, 8.0 * s * open + 2.0, C("#12060f", alpha), 0.0, 16)
	for i in range(-2, 3):
		var tx: float = float(i) * 7.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2((tx - 1.0) * s, (8.0 - 6.0 * open) * s), Vector2((tx + 2.0) * s, (8.0 - 6.0 * open) * s), Vector2(tx * s, 8.0 * s)]), C("#e0c0ff", alpha))
	var eyes := [[-14.0, -10.0, 6.0], [8.0, -14.0, 8.0], [18.0, -2.0, 4.0], [-4.0, -18.0, 3.0]]
	var eye_c := C("#ffd166", alpha) if (stt == "recover" or stt == "stagger") else C("#c080ff", alpha)
	for ee in eyes:
		var ex: float = ee[0]
		var ey: float = ee[1]
		var er: float = ee[2]
		ci.draw_circle(Vector2(ex * s, ey * s), er * s, eye_c)
		ci.draw_circle(Vector2(ex * s + 1.0, ey * s), er * s * 0.45, C("#12060f", alpha))
	ci.draw_set_transform_matrix(IDENT)

static func draw_boss(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var id := String(e.get("boss_id", "boss"))
	match id:
		"guardian": draw_guardian(ci, st, e)
		"eater": draw_eater(ci, st, e)
		"gate_warden": draw_gate_warden(ci, st, e)
		"spore_matriarch": draw_spore_matriarch(ci, st, e)
		"excavation_behemoth": draw_excavation_behemoth(ci, st, e)
		"frost_stalker": draw_frost_stalker(ci, st, e)
		"blood_hunt_king": draw_blood_hunt_king(ci, st, e)
		"doom_executor": draw_doom_executor(ci, st, e)
		_: draw_thornmane(ci, st, e)

# ---------- 신규 보스 6종(임시 도형: 실루엣·자세 색·방향으로 식별. 애니메이션 없음) ----------
static func _boss3_alpha(e: Dictionary) -> float:
	return maxf(0.25, 1.0 - maxf(0.0, float(e.death_t) - 1.2) / 1.5) if bool(e.dead) else 1.0

static func _boss3_body(e: Dictionary, color: String, alpha: float) -> Color:
	if float(e.flash) > 0.0:
		return Color(1, 1, 1, alpha)
	if float(e.get("chill", 0.0)) > 0.0:
		return C(color, alpha).lerp(C("#bcd6e6"), 0.5)
	return C(color, alpha)

## 빈틈·비틀거림이면 노란 테두리(공격 기회)
static func _boss3_exposed(ci: Node2D, e: Dictionary) -> void:
	var stt := String(e.state)
	if stt == "recover" or stt == "stagger":
		dashed_circle(ci, float(e.x), float(e.y), float(e.r) + 6.0, rgba(255, 209, 102, 0.85), 2.5, 6.0, 5.0)

## 방패 경감 표시: 정면 부채꼴(파랑) + 문구. 경감이 유효할 때만
static func _boss3_guard_arc(ci: Node2D, e: Dictionary, ang: float, front_deg: float, reduce: float, R: float) -> void:
	if not PBoss3.guard_active(e):
		return
	var half: float = front_deg * PI / 360.0
	fill_sector(ci, float(e.x), float(e.y), R, ang - half, ang + half, rgba(120, 170, 255, 0.18), 16)
	stroke_sector(ci, float(e.x), float(e.y), R, ang - half, ang + half, rgba(140, 190, 255, 0.85), 2.0, 16)
	txt(ci, float(e.x) + cos(ang) * (R + 14.0), float(e.y) + sin(ang) * (R + 14.0), "정면만 -%d%% (옆·뒤 정상)" % int(round(reduce * 100.0)), 11, C("#bcd0ff"))

# 성문 파수장: 갑옷 병사 + 큰 탑방패(향하는 쪽) + 반대팔 석궁
static func draw_gate_warden(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 40.0
	var alpha := _boss3_alpha(e)
	var stt := String(e.state)
	var face := PBoss3.facing(e) if stt != "approach" and stt != "recover" and stt != "intro" and stt != "roar" else atan2(float(st.player.y) - float(e.y), float(st.player.x) - float(e.x))
	shadow(ci, float(e.x), float(e.y) + 30.0 * s, 32.0 * s, 10.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), minf(1.2, float(e.death_t) * 2.0) if bool(e.dead) else 0.0, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var armor := _boss3_body(e, "#8a97b0", alpha)
	var dark := C("#4a5468", alpha)
	var gold := C("#d8b458", alpha)
	ci.draw_rect(Rect2(-18.0 * s, 4.0 * s, 14.0 * s, 26.0 * s), dark)
	ci.draw_rect(Rect2(4.0 * s, 4.0 * s, 14.0 * s, 26.0 * s), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-26.0 * s, -24.0 * s), Vector2(26.0 * s, -24.0 * s), Vector2(22.0 * s, 10.0 * s), Vector2(-22.0 * s, 10.0 * s)]), armor)
	ci.draw_rect(Rect2(-12.0 * s, -44.0 * s, 24.0 * s, 22.0 * s), armor)
	ci.draw_rect(Rect2(-9.0 * s, -37.0 * s, 18.0 * s, 4.0 * s), dark)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-4.0 * s, -52.0 * s), Vector2(4.0 * s, -52.0 * s), Vector2(2.0 * s, -44.0 * s), Vector2(-2.0 * s, -44.0 * s)]), gold)
	# 탑방패: 향하는 방향 앞. 자세 중엔 밝게(경감 유효), 빈틈엔 내려놓음(옆으로)
	var guard_on := PBoss3.guard_active(e)
	var lowered: bool = stt == "recover"
	var sh_ang: float = face + (1.3 if lowered else 0.0)
	var sh_d: float = (22.0 if lowered else 34.0) * s
	ci.draw_set_transform_matrix(T * Transform2D(sh_ang, Vector2(cos(sh_ang) * sh_d, sin(sh_ang) * sh_d)))
	var sh_col: Color = C("#cfe0ff", alpha) if guard_on else C("#6a7a9a", alpha)
	ci.draw_rect(Rect2(-6.0 * s, -30.0 * s, 12.0 * s, 60.0 * s), sh_col)
	ci.draw_rect(Rect2(-3.0 * s, -22.0 * s, 6.0 * s, 44.0 * s), gold if guard_on else dark)
	# 석궁(반대팔)
	ci.draw_set_transform_matrix(T * Transform2D(face, Vector2(cos(face + PI) * 24.0 * s, sin(face + PI) * 24.0 * s)))
	ci.draw_rect(Rect2(-4.0 * s, -3.0 * s, 44.0 * s, 6.0 * s), C("#6b4a2a", alpha))
	ci.draw_line(Vector2(30.0 * s, -16.0 * s), Vector2(30.0 * s, 16.0 * s), C("#d0d0d0", alpha), 2.0)
	ci.draw_set_transform_matrix(IDENT)
	_boss3_exposed(ci, e)

# 포자 어미: 커다란 보라 버섯 갓(점무늬) + 포자 주머니. 준비 중 갓이 부푼다
static func draw_spore_matriarch(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 44.0
	var alpha := _boss3_alpha(e)
	var stt := String(e.state)
	var swell: float = 1.0 + (0.12 if (stt.ends_with("_aim") or stt == "shot_cast" or stt == "ring_lock") else 0.0) + 0.03 * sin(st.t * 2.5)
	shadow(ci, float(e.x), float(e.y) + 34.0 * s, 40.0 * s, 12.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), 0.0, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var cap := _boss3_body(e, "#a070c8", alpha)
	var stem := C("#e8d8f0", alpha)
	ci.draw_rect(Rect2(-16.0 * s, -4.0 * s, 32.0 * s, 36.0 * s), stem)
	for i in 3:
		var a: float = -0.5 + float(i) * 0.5
		ci.draw_circle(Vector2(cos(a + PI / 2.0) * 30.0 * s, 20.0 * s + sin(a) * 6.0 * s), 9.0 * s, C("#c090e0", alpha))
	fill_ellipse(ci, 0.0, -12.0 * s, 46.0 * s * swell, 26.0 * s * swell, cap, 0.0, 28)
	var spots := [[-22.0, -16.0, 6.0], [4.0, -24.0, 8.0], [22.0, -10.0, 5.0], [-6.0, -6.0, 4.0]]
	for sp in spots:
		ci.draw_circle(Vector2(float(sp[0]) * s * swell, float(sp[1]) * s * swell), float(sp[2]) * s, C("#e8c8ff", alpha))
	var eye_c := C("#ffd166", alpha) if (stt == "recover" or stt == "stagger") else C("#fff0ff", alpha)
	ci.draw_circle(Vector2(-8.0 * s, 8.0 * s), 3.5 * s, eye_c)
	ci.draw_circle(Vector2(8.0 * s, 8.0 * s), 3.5 * s, eye_c)
	ci.draw_set_transform_matrix(IDENT)
	_boss3_exposed(ci, e)

# 굴착 거수: 바위 등껍질 딱정벌레 + 드릴 주둥이(향하는 방향). 굴착 중 흙먼지
static func draw_excavation_behemoth(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 46.0
	var alpha := _boss3_alpha(e)
	var stt := String(e.state)
	var face := PBoss3.facing(e) if (stt.begins_with("burrow")) else atan2(float(st.player.y) - float(e.y), float(st.player.x) - float(e.x))
	shadow(ci, float(e.x), float(e.y) + 30.0 * s, 42.0 * s, 12.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), face, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var rock := _boss3_body(e, "#a8865a", alpha)
	var dark := C("#5a4630", alpha)
	for i in 6:
		var a: float = float(i) * TAU / 6.0
		ci.draw_line(Vector2(cos(a) * 20.0 * s, sin(a) * 20.0 * s), Vector2(cos(a) * 44.0 * s, sin(a) * 44.0 * s), dark, 6.0 * s)
	fill_ellipse(ci, -4.0 * s, 0.0, 40.0 * s, 32.0 * s, rock, 0.0, 24)
	for i in 4:
		var a: float = float(i) * 1.5 + 0.3
		ci.draw_circle(Vector2(-6.0 * s + cos(a) * 18.0 * s, sin(a) * 12.0 * s), 6.0 * s, dark)
	var spin: float = st.t * (18.0 if stt == "burrow" else 3.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(30.0 * s, -14.0 * s), Vector2(62.0 * s, 0.0), Vector2(30.0 * s, 14.0 * s)]), C("#c0c0c8", alpha))
	for i in 3:
		var k: float = fmod(spin + float(i) * 0.33, 1.0)
		ci.draw_line(Vector2((30.0 + 30.0 * k) * s, -12.0 * (1.0 - k) * s), Vector2((30.0 + 30.0 * k) * s, 12.0 * (1.0 - k) * s), dark, 2.0)
	var eye_c := C("#ffd166", alpha) if (stt == "recover" or stt == "stagger") else C("#ff8040", alpha)
	ci.draw_circle(Vector2(22.0 * s, -10.0 * s), 3.5 * s, eye_c)
	ci.draw_circle(Vector2(22.0 * s, 10.0 * s), 3.5 * s, eye_c)
	ci.draw_set_transform_matrix(IDENT)
	if stt == "burrow":
		for i in 5:
			var a2: float = face + PI + float(i - 2) * 0.35
			ci.draw_circle(Vector2(float(e.x) + cos(a2) * (float(e.r) + 12.0 + float(i % 2) * 10.0), float(e.y) + sin(a2) * (float(e.r) + 12.0)), 5.0, rgba(180, 150, 110, 0.6))
	_boss3_exposed(ci, e)

# 서리 추적자: 낮고 긴 네발짐승, 창백한 푸른 몸 + 얼음 가시. 옆 이동 중 화살표
static func draw_frost_stalker(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 36.0
	var alpha := _boss3_alpha(e)
	var stt := String(e.state)
	var face := PBoss3.facing(e) if (stt.ends_with("_aim") or stt.ends_with("_lock") or stt == "dash") else atan2(float(st.player.y) - float(e.y), float(st.player.x) - float(e.x))
	shadow(ci, float(e.x), float(e.y) + 22.0 * s, 40.0 * s, 9.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), face, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var body := _boss3_body(e, "#9fd0ea", alpha)
	var dark := C("#4a6a8a", alpha)
	for i in 4:
		var lx: float = (-24.0 + float(i) * 16.0) * s
		ci.draw_line(Vector2(lx, 8.0 * s), Vector2(lx + (4.0 if i % 2 == 0 else -4.0) * s, 24.0 * s), dark, 4.0 * s)
	fill_ellipse(ci, -4.0 * s, 0.0, 40.0 * s, 16.0 * s, body, 0.0, 22)
	fill_ellipse(ci, 30.0 * s, -4.0 * s, 16.0 * s, 11.0 * s, body, 0.0, 16)
	for i in 4:
		var bx: float = (-20.0 + float(i) * 12.0) * s
		ci.draw_colored_polygon(PackedVector2Array([Vector2(bx - 4.0 * s, -10.0 * s), Vector2(bx + 4.0 * s, -10.0 * s), Vector2(bx, -26.0 * s)]), C("#e8f8ff", alpha))
	ci.draw_line(Vector2(-40.0 * s, 0.0), Vector2(-60.0 * s, -10.0 * s), body, 5.0 * s)
	var eye_c := C("#ffd166", alpha) if (stt == "recover" or stt == "stagger") else C("#40e0ff", alpha)
	ci.draw_circle(Vector2(38.0 * s, -7.0 * s), 3.0 * s, eye_c)
	ci.draw_set_transform_matrix(IDENT)
	if stt == "sidestep":
		var sd: Array = e.get("side_dir", [1.0, 0.0])
		var ax: float = float(e.x) + float(sd[0]) * (float(e.r) + 24.0)
		var ay: float = float(e.y) + float(sd[1]) * (float(e.r) + 24.0)
		ci.draw_line(Vector2(float(e.x), float(e.y)), Vector2(ax, ay), rgba(191, 239, 255, 0.9), 3.0)
		txt(ci, ax, ay - 14.0, "옆 이동(맞음)", 11, C("#bfefff"))
	_boss3_exposed(ci, e)

# 핏빛 사냥왕: 붉은 큰 짐승 + 뼈 왕관 + 발톱. 재조준 중 표식은 telegraph가 그린다
static func draw_blood_hunt_king(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 42.0
	var alpha := _boss3_alpha(e)
	var stt := String(e.state)
	var face := PBoss3.facing(e) if (stt.begins_with("claw") or stt.begins_with("dash")) else atan2(float(st.player.y) - float(e.y), float(st.player.x) - float(e.x))
	shadow(ci, float(e.x), float(e.y) + 30.0 * s, 40.0 * s, 11.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), face, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var body := _boss3_body(e, "#b04040", alpha)
	var dark := C("#5a1a1a", alpha)
	var bone := C("#efe6d0", alpha)
	for i in 4:
		var lx: float = (-22.0 + float(i) * 15.0) * s
		ci.draw_line(Vector2(lx, 12.0 * s), Vector2(lx + (5.0 if i % 2 == 0 else -5.0) * s, 30.0 * s), dark, 6.0 * s)
	fill_ellipse(ci, -6.0 * s, 0.0, 42.0 * s, 24.0 * s, body, 0.0, 24)
	fill_ellipse(ci, 32.0 * s, -6.0 * s, 20.0 * s, 15.0 * s, body, 0.0, 18)
	for i in 5:
		var cx: float = (24.0 + float(i) * 4.0) * s
		ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - 3.0 * s, -20.0 * s), Vector2(cx + 3.0 * s, -20.0 * s), Vector2(cx, (-30.0 - float(i % 2) * 6.0) * s)]), bone)
	var claw_out: float = 1.0 if (stt == "claw_aim" or stt == "claw_lock") else 0.5
	for i in 3:
		var cy: float = (-10.0 + float(i) * 10.0) * s
		ci.draw_line(Vector2(40.0 * s, cy), Vector2((40.0 + 18.0 * claw_out) * s, cy + 4.0 * s), bone, 3.0)
	var eye_c := C("#ffd166", alpha) if (stt == "recover" or stt == "stagger") else C("#ffe060", alpha)
	ci.draw_circle(Vector2(40.0 * s, -10.0 * s), 3.0 * s, eye_c)
	ci.draw_set_transform_matrix(IDENT)
	_boss3_exposed(ci, e)

# 종말의 집행관: 키 큰 검은 로브 + 거대한 처형검 + 방패(방어 자세 땐 정면으로)
static func draw_doom_executor(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var s: float = float(e.r) / 44.0
	var alpha := _boss3_alpha(e)
	var stt := String(e.state)
	var face: float = float(e.get("face", 0.0)) if stt == "guard" else (PBoss3.facing(e) if (stt.begins_with("gstrike")) else atan2(float(st.player.y) - float(e.y), float(st.player.x) - float(e.x)))
	shadow(ci, float(e.x), float(e.y) + 34.0 * s, 30.0 * s, 10.0 * s)
	var T := xf(Vector2(float(e.x), float(e.y)), 0.0, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var robe := _boss3_body(e, "#6a5a8a", alpha)
	var dark := C("#2a2038", alpha)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-16.0 * s, -30.0 * s), Vector2(16.0 * s, -30.0 * s), Vector2(30.0 * s, 34.0 * s), Vector2(-30.0 * s, 34.0 * s)]), robe)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-14.0 * s, -56.0 * s), Vector2(14.0 * s, -56.0 * s), Vector2(18.0 * s, -28.0 * s), Vector2(-18.0 * s, -28.0 * s)]), dark)
	var eye_c := C("#ffd166", alpha) if (stt == "recover" or stt == "stagger") else C("#c080ff", alpha)
	ci.draw_circle(Vector2(-6.0 * s, -42.0 * s), 3.0 * s, eye_c)
	ci.draw_circle(Vector2(6.0 * s, -42.0 * s), 3.0 * s, eye_c)
	# 처형검: 절단 준비 땐 세로로 높이, 큰 베기 땐 향하는 쪽
	var raised: bool = stt.begins_with("slash")
	var sw_ang: float = -PI / 2.0 if raised else face
	ci.draw_set_transform_matrix(T * Transform2D(sw_ang, Vector2(cos(face) * 22.0 * s, sin(face) * 22.0 * s)))
	ci.draw_rect(Rect2(0.0, -5.0 * s, 70.0 * s, 10.0 * s), C("#d0d0e0", alpha))
	ci.draw_rect(Rect2(-10.0 * s, -8.0 * s, 10.0 * s, 16.0 * s), dark)
	# 방패: 방어 자세 땐 정면(밝게), 아니면 등 뒤
	var guard_on := PBoss3.guard_active(e)
	var sh_ang: float = face if guard_on else face + PI
	ci.draw_set_transform_matrix(T * Transform2D(sh_ang, Vector2(cos(sh_ang) * 30.0 * s, sin(sh_ang) * 30.0 * s)))
	ci.draw_rect(Rect2(-5.0 * s, -26.0 * s, 10.0 * s, 52.0 * s), C("#c8b8ff", alpha) if guard_on else dark)
	ci.draw_set_transform_matrix(IDENT)
	_boss3_exposed(ci, e)

# ---------- 궁수·포자 ----------
static func begin_alpha(e: Dictionary) -> float:
	return maxf(0.0, 1.0 - float(e.death_t) / 0.5) if bool(e.dead) else 1.0

static func body_col(e: Dictionary, color: String, alpha: float) -> Color:
	if float(e.flash) > 0.0:
		return Color(1, 1, 1, alpha)
	if float(e.chill) > 0.0:
		return C("#bcd6e6", alpha)
	return C(color, alpha)

## 등급 색(세계 변화): 정의 색과 등급 tint를 섞는다(임시 그래픽). 색만으로 구분하지 않도록 draw_enemy가 표식도 그린다
static func def_color(e: Dictionary, fallback: String) -> String:
	var base := String(e.def.get("color", fallback))
	var tier := String(e.get("tier", "normal"))
	if tier == "normal":
		return base
	var TD := PCatalog.tier(tier)
	var c := C(base).lerp(C(String(TD.get("tint", "#d24a3a"))), 0.55)
	return "#" + c.to_html(false)

## 등급 표식(임시 도형): 붉은 개체 = 머리 위 붉은 삼각 + 테두리 링, 상위 변이 = 보라 이중 삼각 + 굵은 링
static func tier_mark(ci: Node2D, e: Dictionary) -> void:
	var tier := String(e.get("tier", "normal"))
	if tier == "normal" or bool(e.dead) or bool(e.get("hidden", false)):
		return
	var TD := PCatalog.tier(tier)
	var col := C(String(TD.get("tint", "#d24a3a")))
	var ex: float = e.x
	var ey: float = e.y
	var r: float = e.r
	ci.draw_arc(Vector2(ex, ey), r + 3.0, 0.0, TAU, 24, Color(col, 0.85), 2.0 if tier == "red" else 3.5)
	var ty: float = ey - r - 22.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(ex, ty - 6.0), Vector2(ex - 5.0, ty + 2.0), Vector2(ex + 5.0, ty + 2.0)]), col)
	if tier == "apex":
		ci.draw_colored_polygon(PackedVector2Array([Vector2(ex, ty - 13.0), Vector2(ex - 5.0, ty - 5.0), Vector2(ex + 5.0, ty - 5.0)]), col)

static func draw_archer(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var d: Dictionary = e.def
	var p: Dictionary = st.player
	var to_p: float = atan2(float(p.y) - float(e.y), float(p.x) - float(e.x))
	var face_x: float = 1.0 if cos(to_p) >= 0.0 else -1.0
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	shadow(ci, float(e.x), float(e.y) + 14.0, 11.0, 4.0)
	var T := xf(Vector2(float(e.x), float(e.y)), 0.0, Vector2(face_x, 1.0))
	ci.draw_set_transform_matrix(T)
	var stt := String(e.state)
	var walk: float = sin(float(e.get("move_t", 0.0)) * TAU) * 3.0 if stt == "approach" else 0.0
	ci.draw_line(Vector2(-3, 4), Vector2(-3.0 + walk, 14.0), C("#3d4a2a", alpha), 3.0)
	ci.draw_line(Vector2(3, 4), Vector2(3.0 - walk, 14.0), C("#3d4a2a", alpha), 3.0)
	rrect(ci, -6.0, -8.0, 12.0, 14.0, 3.0, body_col(e, def_color(e, "#7cc47a"), alpha))
	ci.draw_circle(Vector2(0, -13), 5.0, C("#e8c39e", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-6, -14), Vector2(0, -21), Vector2(7, -14)]), C("#2e5a2c", alpha))
	var pull: float = minf(1.0, float(e.state_t) / maxf(0.001, float(d.get("aim", 1.0)))) if stt == "aim" else (1.0 if stt == "lock" else 0.0)
	var ba: float = float(e.aim_angle) if stt == "aim" else (float(e.dir) if stt == "lock" else to_p)
	ci.draw_set_transform_matrix(T * Transform2D(PI - ba if face_x < 0.0 else ba, Vector2.ZERO))
	ci.draw_arc(Vector2(8, -2), 11.0, -1.2, 1.2, 12, C("#d9b26f", alpha), 2.5)
	ci.draw_polyline(PackedVector2Array([Vector2(8.0 + cos(-1.2) * 11.0, -2.0 + sin(-1.2) * 11.0), Vector2(8.0 - pull * 10.0, -2.0), Vector2(8.0 + cos(1.2) * 11.0, -2.0 + sin(1.2) * 11.0)]), C("#eeeeee", alpha), 1.0)
	if pull > 0.0:
		ci.draw_line(Vector2(8.0 - pull * 10.0, -2.0), Vector2(20.0, -2.0), C("#ffd9a0", alpha), 2.0)
	ci.draw_set_transform_matrix(IDENT)

static func draw_spore(ci: Node2D, _st: CombatState, e: Dictionary) -> void:
	var d: Dictionary = e.def
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	shadow(ci, float(e.x), float(e.y) + 16.0, 16.0, 5.0)
	var stt := String(e.state)
	var anim_t: float = float(e.get("anim_t", 0.0))
	var sw: float = (1.0 + 0.45 * (float(e.state_t) / maxf(0.001, float(d.get("swell", 0.9))))) if stt == "swell" else (0.85 if stt == "recover" else 1.0 + 0.05 * sin(anim_t * 6.0))
	ci.draw_set_transform_matrix(xf(Vector2(float(e.x), float(e.y)), 0.0, Vector2(sw, sw)))
	var r: float = e.r
	var bc := body_col(e, def_color(e, "#b070d8"), alpha)
	if float(e.chill) > 0.0 and float(e.flash) <= 0.0:
		bc = C("#c9b3e8", alpha)
	ci.draw_circle(Vector2.ZERO, r, bc)
	for i in 6:
		var a: float = float(i) * TAU / 6.0 + anim_t * 0.5
		ci.draw_circle(Vector2(cos(a) * r * 0.85, sin(a) * r * 0.85), r * 0.35, bc)
	for i in 5:
		var a: float = float(i) * 1.26 + 0.4
		ci.draw_circle(Vector2(cos(a) * r * 0.5, sin(a) * r * 0.5), 2.5, C("#d9a6ff", alpha))
	ci.draw_circle(Vector2(-5, -3), 3.0, C("#3a1d55", alpha))
	ci.draw_circle(Vector2(5, -3), 3.0, C("#3a1d55", alpha))
	ci.draw_set_transform_matrix(IDENT)

# ---------- v0.6 신규 몬스터 8종 ----------
static func draw_boar(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var p: Dictionary = st.player
	var stt := String(e.state)
	var ang: float = float(e.aim_angle) if stt == "charge_aim" else (float(e.dir) if (stt == "charge_lock" or stt == "charge") else atan2(float(p.y) - float(e.y), float(p.x) - float(e.x)))
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 16.0, 20.0, 4.0)
	if stt == "charge":
		var dr: float = e.dir
		for i in range(1, 4):
			fill_ellipse(ci, ex - cos(dr) * 14.0 * float(i), ey - sin(dr) * 14.0 * float(i), 22.0, 12.0, rgba(160, 120, 80, 0.25 / float(i)), dr, 12)
	var rot: float = ang + (sin(float(e.state_t) * 10.0) * 0.2 if stt == "stagger" else 0.0)
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), rot, Vector2.ONE))
	var crouch: bool = stt == "charge_aim" or stt == "charge_lock"
	fill_ellipse(ci, -4.0 if crouch else 0.0, 0.0, 22.0, 11.0 if crouch else 13.0, body_col(e, def_color(e, "#8a6a4a"), alpha), 0.0, 20)
	fill_ellipse(ci, -6.0, -4.0, 14.0, 5.0, C("#5a4630", alpha), 0.0, 12)
	ci.draw_circle(Vector2(20, 0), 9.0, body_col(e, "#6f5238", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(24, -4), Vector2(34, -10), Vector2(28, -2)]), C("#f5efe0", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(24, 4), Vector2(34, 10), Vector2(28, 2)]), C("#f5efe0", alpha))
	ci.draw_circle(Vector2(22, -4), 1.8, C("#ffd27a", alpha) if stt == "approach" else C("#ff4a4a", alpha))
	var move_t: float = float(e.get("move_t", 0.0))
	for lx in [-12.0, -4.0, 8.0, 14.0]:
		var sw: float = sin(move_t * TAU + float(lx)) * 4.0 if stt == "approach" else 0.0
		ci.draw_line(Vector2(float(lx), 8.0), Vector2(float(lx) + sw, 17.0), C("#4a3624", alpha), 3.0)
	ci.draw_set_transform_matrix(IDENT)
	if stt == "stagger":
		for i in 3:
			var a: float = st.t * 4.0 + float(i) * 2.1
			txt(ci, ex + cos(a) * 16.0, ey - 26.0 + sin(a) * 5.0, "★", 12, C("#ffe066"))

static func draw_shieldbearer(ci: Node2D, _st: CombatState, e: Dictionary) -> void:
	var stt := String(e.state)
	# 규칙(PEnemiesNew.guard_closed)과 맞춘다: 준비(bash_aim) 중에도 방패는 닫혀 있다
	var open: bool = stt == "bash" or stt == "recover"
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 15.0, 12.0, 4.0)
	var T := xf(Vector2(ex, ey), 0.0, Vector2.ONE)
	ci.draw_set_transform_matrix(T)
	var walk: float = sin(float(e.get("move_t", 0.0)) * TAU) * 3.0 if stt == "approach" else 0.0
	ci.draw_line(Vector2(-4, 4), Vector2(-4.0 + walk, 15.0), C("#3d4552", alpha), 3.5)
	ci.draw_line(Vector2(4, 4), Vector2(4.0 - walk, 15.0), C("#3d4552", alpha), 3.5)
	rrect(ci, -8.0, -10.0, 16.0, 18.0, 4.0, body_col(e, def_color(e, "#7a8aa0"), alpha))
	ci.draw_circle(Vector2(0, -15), 6.0, C("#d8c8a8", alpha))
	ci.draw_rect(Rect2(-7, -22, 14, 5), C("#4a5566", alpha))
	var fa: float = float(e.get("face", 0.0))
	var blocked: bool = float(e.get("blocked_t", 0.0)) > 0.0
	ci.draw_set_transform_matrix(T * Transform2D(fa + (-1.2 if open else 0.0), Vector2.ZERO))
	rrect(ci, 10.0, -16.0, 8.0, 32.0, 3.0, Color(1, 1, 1, alpha) if blocked else C("#c9a44a", alpha))
	ci.draw_rect(Rect2(10, -16, 8, 32), C("#5a4620", alpha), false, 2.0)
	ci.draw_rect(Rect2(13, -3, 2, 6), C("#7a5a2a", alpha))
	if stt == "bash_aim" or stt == "bash":
		ci.draw_set_transform_matrix(T * Transform2D(fa, Vector2.ZERO))
		ci.draw_line(Vector2(6, 0), Vector2(24, 0), C("#e8e8f0", alpha), 3.0)
	ci.draw_set_transform_matrix(IDENT)
	if blocked:
		txt(ci, ex, ey - 30.0, "막음", 11, Color(1, 1, 1, alpha))

static func draw_shaman(ci: Node2D, _st: CombatState, e: Dictionary) -> void:
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 15.0, 11.0, 4.0)
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), 0.0, Vector2.ONE))
	var bob: float = sin(float(e.get("anim_t", 0.0)) * 3.0) * 1.5
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0.0, -18.0 + bob), Vector2(-11, 14), Vector2(11, 14)]), body_col(e, def_color(e, "#c58ae0"), alpha))
	ci.draw_circle(Vector2(0.0, -14.0 + bob), 6.0, C("#3a1d55", alpha))
	ci.draw_circle(Vector2(-2.0, -15.0 + bob), 1.6, C("#e9b6ff", alpha))
	ci.draw_circle(Vector2(2.0, -15.0 + bob), 1.6, C("#e9b6ff", alpha))
	ci.draw_line(Vector2(12, 12), Vector2(14.0, -20.0 + bob), C("#6b4a2a", alpha), 2.5)
	var stt := String(e.state)
	var glow: float = 1.0 if stt == "cast" else (0.6 if stt == "hex_aim" else 0.25)
	ci.draw_circle(Vector2(14.0, -22.0 + bob), 5.0 + glow * 3.0, rgba(233, 182, 255, (0.3 + glow * 0.6) * alpha))
	ci.draw_set_transform_matrix(IDENT)

static func draw_bomber(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var d: Dictionary = e.def
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 15.0, 13.0, 4.0)
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), 0.0, Vector2.ONE))
	var stt := String(e.state)
	var fuse: bool = stt == "fuse"
	var k: float = float(e.state_t) / maxf(0.001, float(d.get("fuse", 1.3))) if fuse else 0.0
	var pulse: float = 1.0 + 0.15 * sin(st.t * (20.0 + 40.0 * k)) if fuse else 1.0
	var walk: float = sin(float(e.get("move_t", 0.0)) * TAU * 1.5) * 3.0 if stt == "approach" else 0.0
	ci.draw_line(Vector2(-5, 8), Vector2(-5.0 + walk, 16.0), C("#4a3020", alpha), 3.0)
	ci.draw_line(Vector2(5, 8), Vector2(5.0 - walk, 16.0), C("#4a3020", alpha), 3.0)
	var bc := body_col(e, def_color(e, "#e07040"), alpha)
	if fuse and float(e.flash) <= 0.0 and int(floor(st.t * (6.0 + 20.0 * k))) % 2 == 1:
		bc = C("#ff9a6a", alpha)
	ci.draw_circle(Vector2.ZERO, 13.0 * pulse, bc)
	ci.draw_circle(Vector2(-4, -2), 2.5, C("#2b1d14", alpha))
	ci.draw_circle(Vector2(4, -2), 2.5, C("#2b1d14", alpha))
	ci.draw_polyline(quad_pts(Vector2(0, -13), Vector2(6, -22), Vector2(10, -18), 6), C("#3a2a1a", alpha), 2.0)
	ci.draw_circle(Vector2(10.0 + sin(st.t * 30.0) * 1.5, -18.0), 4.0 if fuse else 2.5, C("#ffd27a", alpha))
	ci.draw_set_transform_matrix(IDENT)

static func draw_burrower(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var d: Dictionary = e.def
	var stt := String(e.state)
	var ex: float = e.x
	var ey: float = e.y
	if bool(e.get("hidden", false)) or stt == "dive":
		var k: float = 1.0 - float(e.state_t) / maxf(0.001, float(d.get("dive", 0.4))) if stt == "dive" else 1.0
		fill_ellipse(ci, ex, ey + 4.0, 18.0, 8.0, C("#5a4630"), 0.0, 14)
		fill_ellipse(ci, ex, ey, 14.0, 6.0, C("#7a6040"), 0.0, 12)
		if stt == "dive":
			ci.draw_circle(Vector2(ex, ey - 8.0 * k), 9.0, body_col(e, def_color(e, "#a0784c"), maxf(0.0, k)))
		return
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	shadow(ci, ex, ey + 14.0, 16.0, 4.0)
	var p: Dictionary = st.player
	var ang: float = float(e.aim_angle) if stt == "bite_aim" else atan2(float(p.y) - ey, float(p.x) - ex)
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), ang, Vector2.ONE))
	var up: bool = stt == "emerge" or stt == "stagger"
	var move_t: float = float(e.get("move_t", 0.0))
	for i in range(3, -1, -1):
		var cx: float = -float(i) * 9.0 + 6.0
		var cy: float = -float(i) * 4.0 if up else sin(move_t * TAU + float(i)) * 2.0
		ci.draw_circle(Vector2(cx, cy), 9.0 - float(i) * 0.8, body_col(e, def_color(e, "#a0784c") if i % 2 == 1 else "#8a6840", alpha))
	ci.draw_circle(Vector2(10, -3), 2.0, C("#2b1d14", alpha))
	ci.draw_circle(Vector2(10, 3), 2.0, C("#2b1d14", alpha))
	var open: float = 4.0 if stt == "bite_aim" else 0.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(13, -4), Vector2(20.0, -7.0 - open), Vector2(15, -1)]), C("#f0e8d8", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(13, 4), Vector2(20.0, 7.0 + open), Vector2(15, 1)]), C("#f0e8d8", alpha))
	ci.draw_set_transform_matrix(IDENT)

static func draw_spider(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 12.0, 16.0, 4.0)
	var p: Dictionary = st.player
	var ang: float = atan2(float(p.y) - ey, float(p.x) - ex)
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), ang, Vector2.ONE))
	var stt := String(e.state)
	var move_t: float = float(e.get("move_t", 0.0))
	var lc := C("#2f2f3a", alpha)
	for i in 4:
		var a: float = -0.9 + float(i) * 0.6
		var sw: float = sin(move_t * TAU * 2.0 + float(i)) * 3.0 if stt == "approach" else 0.0
		for sgn in [1.0, -1.0]:
			var sg: float = sgn
			ci.draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(cos(a) * 12.0, sg * (10.0 + sw)), Vector2(cos(a) * 20.0, sg * (16.0 + sw))]), lc, 2.0)
	var bc := body_col(e, def_color(e, "#5c5c6e"), alpha)
	fill_ellipse(ci, -4.0, 0.0, 11.0, 8.0, bc, 0.0, 16)
	ci.draw_circle(Vector2(8, 0), 6.0, bc)
	var eye_c := C("#e8f0ff", alpha) if stt == "web_aim" else C("#ff4a4a", alpha)
	for i in 4:
		ci.draw_circle(Vector2(10.0 + float(i % 2) * 2.0, -4.0 + float(i) * 2.6), 1.3, eye_c)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-8, -4), Vector2(-2, 0), Vector2(-8, 4)]), C("#c9a0ff", alpha))
	ci.draw_set_transform_matrix(IDENT)

static func draw_frostcaller(ci: Node2D, _st: CombatState, e: Dictionary) -> void:
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 15.0, 11.0, 4.0)
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), 0.0, Vector2.ONE))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-9, 14), Vector2(-7, -12), Vector2(7, -12), Vector2(9, 14)]), body_col(e, def_color(e, "#8fc8e8"), alpha))
	ci.draw_circle(Vector2(0, -16), 6.0, C("#e8f4ff", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, -16), Vector2(0, -26), Vector2(7, -16)]), C("#4a7a9a", alpha))
	var cast: bool = String(e.state) == "cast"
	var raise: float = -10.0 if cast else 0.0
	ci.draw_line(Vector2(11, 12), Vector2(13.0, -18.0 + raise), C("#8fb6d0", alpha), 2.5)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(13.0, -28.0 + raise), Vector2(18.0, -20.0 + raise), Vector2(13.0, -14.0 + raise), Vector2(8.0, -20.0 + raise)]), Color(1, 1, 1, alpha) if cast else C("#bfefff", alpha))
	ci.draw_set_transform_matrix(IDENT)

static func draw_rogue(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var d: Dictionary = e.def
	var alpha := begin_alpha(e)
	if alpha <= 0.0:
		return
	var ex: float = e.x
	var ey: float = e.y
	shadow(ci, ex, ey + 15.0, 10.0, 4.0)
	var p: Dictionary = st.player
	var stt := String(e.state)
	var ang: float = float(e.aim_angle) if (stt == "slash1_aim" or stt == "slash2_aim") else atan2(float(p.y) - ey, float(p.x) - ex)
	var face_x: float = 1.0 if cos(ang) >= 0.0 else -1.0
	var lean: float = 0.15 if stt == "approach" else 0.0
	ci.draw_set_transform_matrix(xf(Vector2(ex, ey), 0.0, Vector2(face_x, 1.0)) * rel(lean, Vector2.ONE))
	var walk: float = sin(float(e.get("move_t", 0.0)) * TAU * 1.3) * 4.0 if stt == "approach" else 0.0
	ci.draw_line(Vector2(-3, 4), Vector2(-3.0 + walk, 15.0), C("#4a2a34", alpha), 3.0)
	ci.draw_line(Vector2(3, 4), Vector2(3.0 - walk, 15.0), C("#4a2a34", alpha), 3.0)
	rrect(ci, -5.0, -9.0, 10.0, 15.0, 3.0, body_col(e, def_color(e, "#b04a5a"), alpha))
	ci.draw_circle(Vector2(0, -14), 5.0, C("#e8c39e", alpha))
	ci.draw_rect(Rect2(-5, -16, 10, 3), C("#5a2a34", alpha))
	var k: float = float(e.state_t) / maxf(0.001, float(d.get("aim1", 0.45))) if stt == "slash1_aim" else (float(e.state_t) / maxf(0.001, float(d.get("aim2", 0.35))) if stt == "slash2_aim" else 0.0)
	var swing: float = 1.2 if float(e.get("bite_t", 9.0)) < 0.12 else 0.0
	ci.draw_line(Vector2(5, -4), Vector2(16.0 + swing * 6.0, -12.0 + k * 6.0 + swing * 8.0), C("#e6edf5", alpha), 2.5)
	ci.draw_line(Vector2(5, 2), Vector2(16.0 + swing * 6.0, 10.0 - k * 6.0 - swing * 8.0), C("#e6edf5", alpha), 2.5)
	ci.draw_set_transform_matrix(IDENT)

# 구조물(제단·봉인 장치): 사각 기단 + 기둥 + 색 문양. 파괴되면 무너진 돌
static func draw_structure(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var c := C(def_color(e, "#9ad0ff"))
	var ex: float = e.x
	var ey: float = e.y
	var r: float = e.r
	var k: float = minf(1.0, float(e.death_t) * 2.0) if bool(e.dead) else 0.0
	ci.draw_rect(Rect2(ex - r, ey + r * 0.4 - 6.0, r * 2.0, 12.0), C("#3a3a44"))
	if bool(e.dead):
		for i in 4:
			var a: float = float(i) * 1.6
			ci.draw_circle(Vector2(ex + cos(a) * r * 0.8 * k, ey + r * 0.3 + sin(a) * 6.0), 6.0 - k * 2.0, C("#55555f"))
		return
	ci.draw_rect(Rect2(ex - r * 0.45, ey - r * 1.5, r * 0.9, r * 1.9), Color.WHITE if float(e.flash) > 0.0 else C("#6a6a78"))
	stroke_circle(ci, ex, ey - r * 0.7, r * 0.28, c, 3.0)
	var pulse: float = 0.5 + 0.5 * sin(st.t * 3.0 + float(e.id))
	ci.draw_circle(Vector2(ex, ey - r * 0.7), r * 0.14, Color(c, 0.35 + 0.4 * pulse))
	var altar := String(e.get("altar", ""))
	if altar == "heal":
		ci.draw_line(Vector2(ex, ey - r * 1.75), Vector2(ex, ey - r * 1.55), c, 2.0)
		ci.draw_line(Vector2(ex - 6.0, ey - r * 1.65), Vector2(ex + 6.0, ey - r * 1.65), c, 2.0)
	elif altar == "hazard":
		ci.draw_colored_polygon(PackedVector2Array([Vector2(ex, ey - r * 1.85), Vector2(ex - 6.0, ey - r * 1.55), Vector2(ex + 6.0, ey - r * 1.55)]), c)
	elif altar == "reinforce":
		stroke_circle(ci, ex, ey - r * 1.7, 6.0, c, 2.0)
		ci.draw_circle(Vector2(ex, ey - r * 1.7), 2.0, c)
	elif bool(e.def.get("device", false)):
		# 봉인 장치: 룬 삼각형이 회전
		for i in 3:
			var a: float = st.t * 1.2 + float(i) * TAU / 3.0
			ci.draw_line(Vector2(ex + cos(a) * 8.0, ey - r * 1.7 + sin(a) * 8.0), Vector2(ex + cos(a + TAU / 3.0) * 8.0, ey - r * 1.7 + sin(a + TAU / 3.0) * 8.0), c, 2.0)
	var label := String(e.def.get("name", ""))
	var budget = e.get("budget", null)
	if budget != null and typeof(budget) == TYPE_FLOAT and is_finite(float(budget)):
		label += " (%s%d)" % ["치료 " if altar == "heal" else "증원 ", int(round(float(budget)))]
	txt(ci, ex, ey + r + 22.0, label, 11, C("#eeeeee"))
	if not st.obj.is_empty():
		var tg := PObjectives.auto_target(st)
		if not tg.is_empty() and tg.has("id") and int(tg.id) == int(e.id):
			dashed_circle(ci, ex, ey - r * 0.4, r + 8.0, C("#ffe066"), 2.0, 4.0, 3.0)

static func draw_enemy(ci: Node2D, st: CombatState, e: Dictionary) -> void:
	var type := String(e.type)
	if bool(e.get("structure", false)):
		draw_structure(ci, st, e)
		if bool(e.dead):
			return
	elif bool(e.get("boss", false)):
		draw_boss(ci, st, e)
	else:
		match type:
			"wolf", "wolf_alpha": draw_wolf(ci, st, e)
			"archer": draw_archer(ci, st, e)
			"spore": draw_spore(ci, st, e)
			"boar": draw_boar(ci, st, e)
			"shieldbearer": draw_shieldbearer(ci, st, e)
			"shaman": draw_shaman(ci, st, e)
			"bomber": draw_bomber(ci, st, e)
			"burrower": draw_burrower(ci, st, e)
			"spider": draw_spider(ci, st, e)
			"frostcaller": draw_frostcaller(ci, st, e)
			"rogue": draw_rogue(ci, st, e)
			_:
				# 알 수 없는 종류: 원 + 이름
				var alpha := begin_alpha(e)
				ci.draw_circle(Vector2(float(e.x), float(e.y)), float(e.r), body_col(e, def_color(e, "#9aa0a8"), alpha))
				txt(ci, float(e.x), float(e.y) + 4.0, String(e.get("name", type)), 10, Color(1, 1, 1, alpha))
	if bool(e.dead):
		return
	if bool(e.get("hidden", false)):
		return
	# 적중 점멸: 규칙이 준 e.flash가 남아 있는 동안만 밝은 테두리 한 겹(기본 0.12초).
	# 시간·값을 여기서 만들지 않는다 — 규칙이 정한 값을 읽기만 한다.
	if float(e.flash) > 0.0:
		var fk: float = clampf(float(e.flash) / 0.12, 0.0, 1.0)
		stroke_circle(ci, float(e.x), float(e.y), float(e.r) + 2.0, Color(1, 1, 1, 0.7 * fk), 2.0 + 1.5 * fk)
	tier_mark(ci, e)
	var ex: float = e.x
	var ey: float = e.y
	var r: float = e.r
	var stt := String(e.state)
	var is_boss: bool = bool(e.get("boss", false))
	if stt == "stagger" and not is_boss:
		txt(ci, ex, ey + r + 20.0, "빈틈", 11, C("#ffe066"))
	if stt == "recover" and (type == "wolf" or type == "wolf_alpha"):
		txt(ci, ex, ey - r - 12.0, "빈틈!", 13, Color(1, 0.85, 0.4)) # 돌진 뒤 빈틈(피해 ×1.5)
	# 체력 막대(보스는 HUD가 그린다). 상처 입었을 때만
	if not is_boss and float(e.hp) < float(e.hp_max):
		var w: float = r * 2.6
		ci.draw_rect(Rect2(ex - w / 2.0, ey - r - 16.0, w, 5.0), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(ex - w / 2.0, ey - r - 16.0, w * clampf(float(e.hp) / maxf(1.0, float(e.hp_max)), 0.0, 1.0), 5.0), C("#ffe066") if bool(e.get("elite", false)) else C("#ff6b6b"))
	# 상태 아이콘
	var ix: float = ex - 10.0
	var iy: float = ey - r - 28.0
	if stt == "recover" or stt == "stagger":
		status_icon(ci, ix, iy, "exposed"); ix += 16.0
	if float(e.chill) > 0.0:
		status_icon(ci, ix, iy, "chill"); ix += 16.0
	var burn: Dictionary = e.get("burn", {})
	if not burn.is_empty() and float(burn.get("t", 0.0)) > 0.0:
		status_icon(ci, ix, iy, "burn"); ix += 16.0
	var bleed: Dictionary = e.get("bleed", {})
	if not bleed.is_empty() and float(bleed.get("t", 0.0)) > 0.0:
		status_icon(ci, ix, iy, "bleed"); ix += 16.0
	if float(e.get("conduct", 0.0)) > 0.0:
		status_icon(ci, ix, iy, "conduct"); ix += 16.0
	if st.in_field(e):
		status_icon(ci, ix, iy, "slow"); ix += 16.0
	if st.mark_target != null and typeof(st.mark_target) == TYPE_DICTIONARY and int(st.mark_target.get("id", -1)) == int(e.id):
		status_icon(ci, ex, ey - r - 44.0, "mark")
	if float(e.chill) > 0.0:
		dashed_circle(ci, ex, ey, r * 1.4 + 3.0, rgba(160, 230, 255, 0.85), 2.0, 3.0, 4.0, st.t * 1.5)
	var stasis: int = int(e.get("stasis", 0))
	if stasis > 0:
		var w: float = float(stasis) * 7.0
		ci.draw_rect(Rect2(ex - w / 2.0 - 2.0, ey + r + 8.0, w + 4.0, 10.0), Color(0, 0, 0, 0.55))
		for i in stasis:
			var hot: bool = i == stasis - 1 and int(floor(st.t * 8.0)) % 2 == 1
			ci.draw_rect(Rect2(ex - w / 2.0 + float(i) * 7.0, ey + r + 10.0, 5.0, 6.0), Color.WHITE if hot else C("#a9d8ff"))
		txt(ci, ex + w / 2.0 + 4.0, ey + r + 17.0, "흔적 %d" % stasis, 10, C("#cfeaff"), -1)
	if bool(e.get("elite", false)):
		txt(ci, ex, ey + r + 22.0, "정예 · " + String(e.get("name", "")), 12, C("#ffe066"))
	if bool(e.get("summoned", false)) and float(e.get("grace", 0.0)) > 0.0:
		txt(ci, ex, ey - r - 34.0, "소환", 11, rgba(255, 200, 80, 0.9))

# ---------- 마검사(측면, 좌우 반전) ----------
static func draw_swordsman(ci: Node2D, st: CombatState) -> void:
	var p: Dictionary = st.player
	var px: float = p.x
	var py: float = p.y
	var face: float = p.face
	var face_left: bool = cos(face) < 0.0
	var la: float = PI - face if face_left else face
	var dodge: bool = bool(p.dodge_active)
	shadow(ci, px, py + 17.0 * VS, 13.0 * VS, 4.5 * VS)
	if dodge:
		for i in range(1, 4):
			fill_ellipse(ci, px - float(p.dodge_dx) * 13.0 * float(i), py - float(p.dodge_dy) * 13.0 * float(i), 10.0, 14.0, rgba(120, 190, 255, 0.28 / float(i)), 0.0, 12)
	var alpha: float = 0.5 if (float(p.hit_prot) > 0.0 and int(floor(st.t * 20.0)) % 2 == 0) else 1.0
	if bool(p.dead):
		alpha = 0.6
	var shake: float = sin(st.t * 90.0) * 2.5 if float(p.hurt_t) < 0.2 else 0.0
	var T := xf(Vector2(px + shake, py), 0.0, Vector2(-VS if face_left else VS, VS))
	if dodge:
		var dur: float = float(st.cfg.player.dodge.get("duration", 0.26))
		var k: float = float(p.dodge_t) / maxf(0.001, dur)
		var sgn: float = 1.0 if ((-float(p.dodge_dx) if face_left else float(p.dodge_dx)) >= 0.0) else -1.0
		T = T * rel(k * TAU * sgn, Vector2(1.0, 0.85))
	ci.draw_set_transform_matrix(T)
	var moving: bool = bool(p.moving) and not dodge
	var walk_t: float = p.walk_t
	var walk: float = sin(walk_t * 13.0) if moving else 0.0
	var bob: float = absf(cos(walk_t * 13.0)) * -1.5 if moving else sin(st.t * 2.0) * 0.6
	var hurt: bool = float(p.flash) > 0.0
	# 망토
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-3.0, -8.0 + bob), Vector2(-9.0 - absf(walk) * 4.0 - (3.0 if moving else 0.0), 6.0 + bob + sin(st.t * 6.0) * 1.5), Vector2(-2.0, 9.0 + bob), Vector2(4.0, -6.0 + bob)]), C("#a04050", alpha) if hurt else C("#25335c", alpha))
	# 다리·장화
	var leg_c := C("#c07080", alpha) if hurt else C("#3a3f55", alpha)
	ci.draw_line(Vector2(-3.0, 6.0 + bob), Vector2(-3.0 + walk * 5.0, 16.0), leg_c, 4.0)
	ci.draw_line(Vector2(3.0, 6.0 + bob), Vector2(3.0 - walk * 5.0, 16.0), leg_c, 4.0)
	fill_ellipse(ci, -3.0 + walk * 5.0 + 1.0, 17.0, 4.0, 2.0, C("#26221e", alpha), 0.0, 8)
	fill_ellipse(ci, 3.0 - walk * 5.0 + 1.0, 17.0, 4.0, 2.0, C("#26221e", alpha), 0.0, 8)
	# 몸통(갑옷)
	rrect(ci, -6.5, -9.0 + bob, 13.0, 17.0, 3.0, C("#ff9a9a", alpha) if hurt else C("#4d7fd0", alpha))
	ci.draw_rect(Rect2(-2.0, -7.0 + bob, 5.0, 12.0), C("#ffc0c0", alpha) if hurt else C("#8fb6ee", alpha))
	ci.draw_rect(Rect2(-6.5, 3.0 + bob, 13.0, 2.5), C("#2b2620", alpha))
	# 뒷팔
	var skin := C("#ffb0b0", alpha) if hurt else C("#e9c8a6", alpha)
	ci.draw_line(Vector2(-5.0, -5.0 + bob), Vector2(-8.0, 3.0 + bob), skin, 3.0)
	# 머리·머리카락·눈
	ci.draw_circle(Vector2(0.0, -16.0 + bob), 6.5, C("#ffd0c0", alpha) if hurt else C("#f1c9a5", alpha))
	var hair := arc_pts(0.0, -17.5 + bob, 6.8, PI * 1.05, PI * 1.95, 12)
	hair.append(Vector2(6.5, -15.0 + bob))
	hair.append(Vector2(-6.8, -14.0 + bob))
	ci.draw_colored_polygon(hair, C("#2b1d14", alpha))
	ci.draw_circle(Vector2(3.0, -15.5 + bob), 1.3, C("#1e1a18", alpha))
	# 앞팔 + 검
	var sw: float = p.swing_t
	var swinging: bool = sw < 0.18
	var form := String(p.swing_form)
	var wid := String(st.weapons[0].id) if not st.weapons.is_empty() else "sword"
	var sword_c := C("#bfefff", alpha) if wid == "spear" else C("#e8ecf2", alpha)
	var sa: float
	var reach := 7.0
	if swinging and form == "spin":
		sa = la + (sw / 0.22) * TAU
	elif swinging and form == "beam":
		sa = la
		reach = 7.0 + 9.0 * (1.0 - sw / 0.18)
	elif swinging and form == "heavy":
		sa = la - 2.0 + 2.6 * minf(1.0, sw / 0.18)
	elif swinging:
		sa = la - 1.4 + 2.8 * minf(1.0, sw / 0.16)
	else:
		sa = la + 0.95
	var shx := 5.0
	var shy: float = -6.0 + bob
	var hx: float = shx + cos(sa) * reach
	var hy: float = shy + sin(sa) * reach
	ci.draw_line(Vector2(shx, shy), Vector2(hx, hy), skin, 3.0)
	ci.draw_set_transform_matrix(T * Transform2D(sa, Vector2(hx, hy)))
	var bl: float = 30.0 if wid == "spear" else 26.0
	ci.draw_rect(Rect2(-6.0, -1.5, 6.0, 3.0), C("#5a4630", alpha))
	ci.draw_rect(Rect2(-1.0, -4.5, 3.0, 9.0), C("#c9a44a", alpha))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(2.0, -2.2), Vector2(bl - 5.0, -2.2), Vector2(bl, 0.0), Vector2(bl - 5.0, 2.2), Vector2(2.0, 2.2)]), sword_c)
	ci.draw_rect(Rect2(3.0, -0.6, bl - 8.0, 1.2), Color(1, 1, 1, 0.7 * alpha))
	if swinging:
		ci.draw_line(Vector2(4.0, 0.0), Vector2(bl + 6.0, 0.0), rgba(200, 235, 255, 0.9 * (1.0 - sw / 0.18)), 3.0)
	ci.draw_set_transform_matrix(IDENT)
	if float(p.shield) > 0.0:
		ci.draw_circle(Vector2(px, py - 2.0), float(p.r) + 10.0, rgba(126, 242, 255, 0.08))
		stroke_circle(ci, px, py - 2.0, float(p.r) + 10.0, rgba(126, 242, 255, 0.85), 2.5)

# ---------- 적 예고선(최상단). 도형 = 실제 판정 ----------
static func draw_telegraphs(ci: Node2D, st: CombatState) -> void:
	use_palette(st)
	var p: Dictionary = st.player
	var flash_t: float = 0.75 + 0.25 * sin(st.t * 60.0)
	var diag: float = sqrt(st.arena_w * st.arena_w + st.arena_h * st.arena_h)
	for e in st.enemies:
		if bool(e.dead):
			continue
		var d: Dictionary = e.def
		var type := String(e.type)
		var stt := String(e.state)
		var ex: float = e.x
		var ey: float = e.y
		var er: float = e.r
		var st_t: float = float(e.state_t)
		if type == "wolf" or type == "wolf_alpha":
			# 물기 예고: 머리 앞 짧은 부채꼴(반지름 = 실제 판정 거리 reach, 각도 = 실제 판정 각도). 추적 = 옅은 주황, 고정 = 진한 주황 + 테두리 + '!', 유효 = 흰색
			if stt == "bite_track" or stt == "bite_lock" or stt == "bite_hit":
				var B: Dictionary = d.bite
				var bang: float = float(e.aim_angle) if stt == "bite_track" else float(e.dir)
				var half: float = float(B.arc_deg) * PI / 360.0
				var pts := sector_pts(ex, ey, float(B.reach), bang - half, bang + half, 10)
				if stt == "bite_track":
					ci.draw_colored_polygon(pts, tel_soft(0.22 + 0.2 * (st_t / float(B.track))))
				elif stt == "bite_lock":
					ci.draw_colored_polygon(pts, tel_fill(0.55))
					pts.append(Vector2(ex, ey))
					tel_stroke_poly(ci, pts, 0.95, 2.0)
					tel_bang(ci, ex, ey - er - 8.0, 13)
				else:
					ci.draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.7))
			# 돌진 예고: 통로(폭 = (늑대 반지름 + 플레이어 반지름) × 2 = 실제 판정), 확정되면 굵어지고 '!'
			if stt == "crouch" or stt == "lock":
				var D: Dictionary = d.dash
				var ang: float = float(e.aim_angle) if stt == "crouch" else float(e.dir)
				var L: float = float(D.dash_speed) * float(D.dash_time)
				var locked: bool = stt == "lock"
				var alpha: float = flash_t if locked else (0.4 + 0.35 * (st_t / float(D.crouch)))
				var hw: float = er + float(p.r)
				ci.draw_set_transform_matrix(xf(Vector2(ex, ey), ang, Vector2.ONE))
				ci.draw_rect(Rect2(0, -hw, L, hw * 2.0), tel_fill(alpha * 0.3))
				ci.draw_line(Vector2(er, 0), Vector2(L - 12.0, 0), tel_edge(alpha), 4.0 if locked else 2.0)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(L, 0), Vector2(L - 16, -9), Vector2(L - 16, 9)]), tel_edge(alpha))
				ci.draw_set_transform_matrix(IDENT)
				if locked:
					tel_bang(ci, ex, ey - er - 26.0, 18)
		elif type == "archer" and (stt == "aim" or stt == "lock"):
			var ang: float = float(e.aim_angle) if stt == "aim" else float(e.dir)
			var locked: bool = stt == "lock"
			var to := Vector2(ex + cos(ang) * diag, ey + sin(ang) * diag)
			if locked:
				ci.draw_line(Vector2(ex, ey), to, tel_edge(0.8 + 0.2 * sin(st.t * 60.0)), 3.0)
				tel_bang(ci, ex, ey - er - 24.0, 16)
			else:
				dashed_line(ci, Vector2(ex, ey), to, tel_soft(0.35 + 0.35 * (st_t / maxf(0.001, float(d.get("aim", 1.0))))), 1.5, 8.0, 6.0)
		elif type == "spore" and stt == "swell":
			var k: float = st_t / maxf(0.001, float(d.get("swell", 0.9)))
			var cr: float = float(d.get("cloudR", 80.0))
			ci.draw_circle(Vector2(ex, ey), cr * (0.3 + 0.7 * k), rgba(200, 100, 255, 0.15 + 0.2 * k))
			stroke_circle(ci, ex, ey, cr, rgba(255, 120, 255, 0.5 + 0.5 * k), 2.0 + 2.0 * k)
		elif type == "boar" and (stt == "charge_aim" or stt == "charge_lock"):
			var locked: bool = stt == "charge_lock"
			var ang: float = float(e.dir) if locked else float(e.aim_angle)
			var plen: float
			var pend: Array
			if locked:
				plen = float(e.get("charge_len", 0.0))
				pend = e.get("charge_end", [ex + cos(ang) * plen, ey + sin(ang) * plen])
			else:
				var pv: Dictionary = e.get("preview", {})
				if pv.is_empty():
					plen = float(d.get("chargeDist", 520.0))
					pend = [ex + cos(ang) * plen, ey + sin(ang) * plen]
				else:
					plen = float(pv["len"])
					pend = pv.end
			var alpha: float = flash_t if locked else (0.35 + 0.35 * (st_t / maxf(0.001, float(d.get("aim", 0.9)))))
			var W: float = (er + float(p.r)) * 2.0
			ci.draw_set_transform_matrix(xf(Vector2(ex, ey), ang, Vector2.ONE))
			ci.draw_rect(Rect2(0.0, -W / 2.0, plen, W), tel_fill(alpha * 0.3))
			tel_stroke_rect(ci, Rect2(0.0, -W / 2.0, plen, W), alpha, 4.0 if locked else 2.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(plen, 0.0), Vector2(plen - 16.0, -9.0), Vector2(plen - 16.0, 9.0)]), tel_edge(alpha))
			ci.draw_set_transform_matrix(IDENT)
			dashed_circle(ci, float(pend[0]), float(pend[1]), er, tel_soft(alpha), 2.0, 5.0, 5.0)
			txt(ci, ex, ey - er - 30.0, "돌파!" if locked else "돌파 준비", 12, tel_label(1.0))
		elif type == "shieldbearer" and stt == "bash_aim":
			var k: float = st_t / maxf(0.001, float(d.get("aim", 0.7)))
			var half: float = float(d.get("bashDeg", 100.0)) * PI / 360.0
			var R: float = float(d.get("bashRange", 64.0)) + float(d.get("lunge", 18.0))
			var fa: float = float(e.get("face", 0.0))
			fill_sector(ci, ex, ey, R, fa - half, fa + half, tel_fill(0.12 + 0.25 * k))
			if k > 0.6:
				tel_stroke_sector(ci, ex, ey, R, fa - half, fa + half, flash_t, 4.0)
			else:
				stroke_sector(ci, ex, ey, R, fa - half, fa + half, tel_soft(0.6), 2.0)
			txt(ci, ex, ey - er - 30.0, "방패 열림 · 방패치기", 12, tel_label(1.0))
		elif type == "shaman" and stt == "cast":
			var tgv = e.get("cast_target")
			if tgv != null and typeof(tgv) == TYPE_DICTIONARY and not bool(tgv.dead):
				var tx: float = tgv.x
				var ty: float = tgv.y
				var k: float = st_t / maxf(0.001, float(d.get("healCast", 1.5)))
				dashed_line(ci, Vector2(ex, ey - 10.0), Vector2(tx, ty), rgba(233, 182, 255, 0.85), 2.5, 6.0, 4.0)
				ci.draw_arc(Vector2(ex, ey - 30.0), 12.0, -PI / 2.0, -PI / 2.0 + TAU * k, 16, C("#e9b6ff"), 4.0)
				stroke_circle(ci, tx, ty, float(tgv.r) + 8.0, rgba(233, 182, 255, 0.7), 2.0)
				txt(ci, ex, ey - er - 34.0, "치료 시전 중 — 끊어라", 12, C("#e9b6ff"))
		elif type == "shaman" and stt == "hex_aim":
			var k: float = st_t / maxf(0.001, float(d.get("hexAim", 0.9)))
			var aa: float = float(e.aim_angle)
			dashed_line(ci, Vector2(ex, ey), Vector2(ex + cos(aa) * 600.0, ey + sin(aa) * 600.0), rgba(233, 182, 255, flash_t) if k > 0.7 else rgba(233, 182, 255, 0.45), 3.0 if k > 0.7 else 1.5, 8.0, 6.0)
		elif type == "bomber" and stt == "fuse":
			var fuse: float = float(d.get("fuse", 1.3))
			var k: float = st_t / maxf(0.001, fuse)
			var R: float = float(d.get("blastR", 95.0))
			ci.draw_circle(Vector2(ex, ey), R, tel_fill(0.15 + 0.3 * k))
			ci.draw_circle(Vector2(ex, ey), R * k, rgba(255, 200, 80, 0.25 * k))
			tel_stroke_circle(ci, ex, ey, R, flash_t, 3.0)
			txt(ci, ex, ey - er - 30.0, "폭발 %.1fs" % maxf(0.0, fuse - st_t), 13, tel_label(1.0))
		elif type == "burrower" and stt == "warn" and e.has("emerge_at"):
			var at: Array = e.emerge_at
			var ax: float = at[0]
			var ay: float = at[1]
			var k: float = st_t / maxf(0.001, float(d.get("warn", 0.6)))
			var R: float = float(d.get("emergeR", 60.0))
			ci.draw_circle(Vector2(ax, ay), R, tel_fill(0.15 + 0.25 * k))
			tel_stroke_circle(ci, ax, ay, R, flash_t, 3.0)
			for i in 5:
				var a: float = float(i) * 1.26 + 0.3
				ci.draw_line(Vector2(ax, ay), Vector2(ax + cos(a) * R * k, ay + sin(a) * R * k), C("#7a6040"), 2.0)
			txt(ci, ax, ay - R - 8.0, "출현!", 12, tel_label(1.0))
		if (type == "burrower" or type == "spider") and stt == "bite_aim":
			var k: float = st_t / maxf(0.001, float(d.get("biteAim", 0.5)))
			var half: float = float(d.get("biteDeg", 90.0)) * PI / 360.0
			var R: float = float(d.get("biteRange", 44.0)) + er
			var aa: float = float(e.aim_angle)
			fill_sector(ci, ex, ey, R, aa - half, aa + half, tel_fill(0.12 + 0.25 * k))
			if k > 0.6:
				tel_stroke_sector(ci, ex, ey, R, aa - half, aa + half, flash_t, 3.0)
			else:
				stroke_sector(ci, ex, ey, R, aa - half, aa + half, tel_soft(0.6), 1.5)
		if type == "spider" and stt == "web_aim" and e.has("web_at"):
			var at: Array = e.web_at
			var wx: float = at[0]
			var wy: float = at[1]
			var k: float = st_t / maxf(0.001, float(d.get("webAim", 0.7)))
			var R: float = float(d.get("webR", 55.0))
			dashed_circle(ci, wx, wy, R, rgba(235, 235, 245, 0.4 + 0.5 * k), 2.0, 4.0, 4.0)
			ci.draw_line(Vector2(ex, ey), Vector2(wx, wy), rgba(235, 235, 245, 0.5), 1.0)
			txt(ci, wx, wy - R - 6.0, "거미줄 예고", 11, C("#eeeeff"))
		if type == "frostcaller" and stt == "cast" and e.has("cast_pts"):
			var pts: Array = e.cast_pts
			var k: float = st_t / maxf(0.001, float(d.get("castAim", 0.6)))
			var R: float = float(d.get("zoneR", 55.0))
			for i in pts.size():
				var pt: Array = pts[i]
				dashed_circle(ci, float(pt[0]), float(pt[1]), R, rgba(200, 240, 255, 0.4 + 0.5 * k), 2.0, 5.0, 5.0)
				txt(ci, float(pt[0]), float(pt[1]) + 6.0, str(i + 1), 16, C("#e8f4ff"))
			txt(ci, ex, ey - er - 34.0, "서리 1→2→3", 12, C("#bfefff"))
		if type == "rogue" and (stt == "slash1_aim" or stt == "slash2_aim"):
			var first: bool = stt == "slash1_aim"
			var k: float = st_t / maxf(0.001, float(d.get("aim1", 0.45)) if first else float(d.get("aim2", 0.35)))
			var half: float = float(d.get("slashDeg", 100.0)) * PI / 360.0
			var R: float = float(d.get("slashRange", 50.0)) + er
			var aa: float = float(e.aim_angle)
			fill_sector(ci, ex, ey, R, aa - half, aa + half, tel_fill(0.12 + 0.28 * k))
			if k > 0.5:
				tel_stroke_sector(ci, ex, ey, R, aa - half, aa + half, flash_t, 3.0)
			else:
				stroke_sector(ci, ex, ey, R, aa - half, aa + half, tel_soft(0.6), 1.5)
			txt(ci, ex, ey - er - 30.0, "베기 1/2" if first else "베기 2/2", 12, tel_label(1.0))
	draw_boss_telegraphs(ci, st, flash_t)
	for f in st.effects:
		var kind := String(f.kind)
		if kind == "pawwarn":
			var k: float = float(f.t) / maxf(0.001, float(f.ttl))
			var pawc := rgba(255, 200, 80, 0.4 + 0.6 * k)   # 등장 예고는 '위험'이 아니라 '정보'라 노랑 계열 그대로 둔다
			var fx: float = f.x
			var fy: float = f.y
			fill_ellipse(ci, fx, fy + 3.0, 6.0, 8.0, pawc, 0.0, 12)
			for i in 4:
				ci.draw_circle(Vector2(fx - 7.0 + float(i) * 4.7, fy - 8.0 + (3.0 if (i == 0 or i == 3) else 0.0)), 2.6, pawc)
			txt(ci, fx, fy - 18.0, "늑대 등장" if String(f.get("type", "wolf")) == "wolf" else "등장", 12, pawc)
		elif kind == "spawnwarn":
			var k: float = float(f.t) / maxf(0.001, float(f.ttl))
			stroke_circle(ci, float(f.x), float(f.y), 18.0 * (1.0 - k) + 6.0, rgba(255, 200, 80, 0.4 + 0.6 * k), 2.0)
			var nm := String(PCatalog.enemy(String(f.get("type", "wolf"))).get("name", ""))
			txt(ci, float(f.x), float(f.y) - 24.0, nm, 12, rgba(255, 200, 80, 0.9))

static func _beam(ci: Node2D, bx: float, by: float, ang: float, L: float, w: float, locked: bool, k: float, flash_t: float) -> void:
	var alpha: float = flash_t if locked else 0.35 + 0.35 * k
	ci.draw_set_transform_matrix(xf(Vector2(bx, by), ang, Vector2.ONE))
	ci.draw_rect(Rect2(0.0, -w / 2.0, L, w), tel_fill(alpha * 0.3))
	tel_stroke_rect(ci, Rect2(0.0, -w / 2.0, L, w), alpha, 4.0 if locked else 2.0)
	ci.draw_set_transform_matrix(IDENT)

static func draw_boss_telegraphs(ci: Node2D, st: CombatState, flash_t: float) -> void:
	var bz: Dictionary = st.boss
	if bz.is_empty() or bool(bz.dead):
		return
	var cfg := PBoss.cfg_of(bz)
	var stt := String(bz.state)
	var bx: float = bz.x
	var by: float = bz.y
	var br: float = bz.r
	var st_t: float = float(bz.state_t)
	var id := String(bz.get("boss_id", "boss"))
	var p: Dictionary = st.player
	if PBoss3.has(id):
		draw_boss3_telegraphs(ci, st, bz, cfg, flash_t)
		return
	if id == "guardian" or id == "eater":
		if (stt == "shock_aim" or stt == "shock_lock") and cfg.has("shock"):
			var S: Dictionary = cfg.shock
			var locked: bool = stt == "shock_lock"
			var ang: float = float(bz.dir) if locked else float(bz.aim_angle)
			var k: float = st_t / maxf(0.001, float(S.aim))
			if int(bz.get("shock_left", 0)) >= 2:
				_beam(ci, bx, by, ang - float(S.spread), float(S.len), float(S.width), locked, k, flash_t)
				_beam(ci, bx, by, ang + float(S.spread), float(S.len), float(S.width), locked, k, flash_t)
			else:
				_beam(ci, bx, by, ang, float(S.len), float(S.width), locked, k, flash_t)
			txt(ci, bx, by - br - 44.0, "충격파!" if locked else "충격파 준비 — 옆으로", 13, tel_label(1.0))
		if (stt == "lanes_warn" or stt == "lanes_lock" or stt == "lanes_fire") and cfg.has("lanes"):
			var L: Dictionary = cfg.lanes
			var lanes: Array = bz.get("lanes", [])
			for i in lanes.size():
				var ln: Dictionary = lanes[i]
				if bool(ln.get("fired", false)):
					continue
				var locked: bool = stt != "lanes_warn" and i == int(bz.get("lane_idx", 0))
				var la: float = ln.ang
				_beam(ci, bx, by, la, float(L.len), float(L.width), locked, minf(1.0, st_t / maxf(0.001, float(L.warn))), flash_t)
				txt(ci, bx + cos(la) * 140.0, by + sin(la) * 140.0, "직선 %d/2" % (i + 1), 12, tel_label(1.0))
		if cfg.has("mark"):
			for mk in bz.get("marks", []):
				if bool(mk.get("done", false)):
					continue
				var left: float = maxf(0.0, float(mk.explode_at) - st.t)
				var k: float = 1.0 - minf(1.0, left / maxf(0.001, float(cfg.mark.delay)))
				var mx: float = mk.x
				var my: float = mk.y
				var mr: float = mk.r
				dashed_circle(ci, mx, my, mr, rgba(230, 120, 255, flash_t) if left < 0.4 else rgba(200, 120, 255, 0.8), 4.0 if left < 0.4 else 2.0, 6.0, 5.0)
				ci.draw_circle(Vector2(mx, my), mr * k, rgba(200, 120, 255, 0.12 + 0.25 * k))
				txt(ci, mx, my + 4.0, "%.1f" % left, 12, C("#e0c0ff"))
		if (stt == "wide_aim" or stt == "wide_lock") and cfg.has("wide"):
			var rad: Array = cfg.wide.radius
			var R: float = float(rad[mini(2, int(bz.get("phase", 1)) - 1)])
			var locked: bool = stt == "wide_lock"
			var k: float = st_t / maxf(0.001, float(cfg.wide.aim))
			var alpha: float = flash_t if locked else 0.3 + 0.4 * k
			ci.draw_circle(Vector2(bx, by), R, rgba(200, 80, 255, alpha * 0.25))
			stroke_circle(ci, bx, by, R, rgba(230, 120, 255, alpha), 4.0 if locked else 2.0)
			txt(ci, bx, by - R - 8.0, "광역!" if locked else "광역 준비 — 원 밖으로 (뒤에 긴 빈틈)", 13, C("#e0c0ff"))
	if (stt == "sweep_aim" or stt == "sweep_lock") and cfg.has("sweep"):
		var locked: bool = stt == "sweep_lock"
		var ang: float = float(bz.dir) if locked else float(bz.aim_angle)
		var half: float = float(cfg.sweep.arcDeg) * PI / 360.0
		var alpha: float = flash_t if locked else 0.35 + 0.35 * (st_t / maxf(0.001, float(cfg.sweep.aim)))
		var R: float = float(cfg.sweep.radius)
		fill_sector(ci, bx, by, R, ang - half, ang + half, tel_fill(alpha * 0.32), 24)
		tel_stroke_sector(ci, bx, by, R, ang - half, ang + half, alpha, 4.0 if locked else 2.0, 24)
		if locked:
			tel_bang(ci, bx, by - br - 44.0, 18)
	if (stt == "dash_aim" or stt == "dash_lock") and cfg.has("dash"):
		var locked: bool = stt == "dash_lock"
		var ang: float = float(bz.dir) if locked else float(bz.aim_angle)
		var plen: float
		var pend: Array
		if locked:
			plen = float(bz.get("dash_len", 0.0))
			pend = bz.get("dash_end", [])
		else:
			var path := PBoss.dash_path(st, bz, ang, float(cfg.dash.dist))
			plen = float(path["len"])
			pend = path.end
		if pend.is_empty():
			pend = [bx + cos(ang) * plen, by + sin(ang) * plen]
		var alpha: float = flash_t if locked else 0.35 + 0.35 * (st_t / maxf(0.001, float(cfg.dash.aim)))
		var W: float = (br + float(p.r)) * 2.0
		ci.draw_set_transform_matrix(xf(Vector2(bx, by), ang, Vector2.ONE))
		ci.draw_rect(Rect2(0.0, -W / 2.0, plen, W), tel_fill(alpha * 0.3))
		tel_stroke_rect(ci, Rect2(0.0, -W / 2.0, plen, W), alpha, 4.0 if locked else 2.0)
		ci.draw_line(Vector2(br, 0.0), Vector2(plen - 14.0, 0.0), tel_edge(alpha), 4.0 if locked else 2.0)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(plen, 0.0), Vector2(plen - 18.0, -10.0), Vector2(plen - 18.0, 10.0)]), tel_edge(alpha))
		ci.draw_set_transform_matrix(IDENT)
		dashed_circle(ci, float(pend[0]), float(pend[1]), br, tel_soft(alpha), 2.0, 5.0, 5.0)
		if locked:
			tel_bang(ci, bx, by - br - 44.0, 18)
		if int(bz.get("dash_total", 1)) > 1:
			txt(ci, bx, by - br - 60.0, "연속 돌진 %d/%d" % [int(bz.get("dash_seq", 1)), int(bz.get("dash_total", 1))], 13, C("#ffd166"))
	var land: Dictionary = bz.get("land", {})
	if (stt == "pounce_aim" or stt == "pounce_lock" or stt == "leap") and not land.is_empty() and cfg.has("pounce"):
		var locked: bool = stt != "pounce_aim"
		var alpha: float = flash_t if locked else 0.35 + 0.35 * (st_t / maxf(0.001, float(cfg.pounce.aim)))
		var R: float = float(cfg.pounce.radius)
		var lx: float = land.x
		var ly: float = land.y
		ci.draw_circle(Vector2(lx, ly), R, tel_fill(alpha * 0.3))
		tel_stroke_circle(ci, lx, ly, R, alpha, 4.0 if locked else 2.0)
		if stt == "leap":
			tel_stroke_circle(ci, lx, ly, R * (1.0 - float(bz.get("leap_k", 0.0))) + 6.0, 0.8, 2.0)
		if locked and stt != "leap":
			tel_bang(ci, lx, ly - R - 10.0, 18)
	if stt == "howl" and cfg.has("howl"):
		var k: float = st_t / maxf(0.001, float(cfg.howl.duration))
		for i in 3:
			stroke_circle(ci, bx, by - 20.0, 40.0 + fmod(k * 3.0 + float(i), 3.0) * 40.0, rgba(255, 200, 120, 0.6 * (1.0 - k)), 3.0)

## 신규 보스 6종 예고: PBoss3.threats()와 같은 기하(봇이 보는 것 = 화면이 보는 것). 순서 번호·색으로 구분
static func draw_boss3_telegraphs(ci: Node2D, st: CombatState, bz: Dictionary, cfg: Dictionary, flash_t: float) -> void:
	var stt := String(bz.state)
	var bx: float = bz.x
	var by: float = bz.y
	var br: float = bz.r
	var st_t: float = float(bz.state_t)
	var id := String(bz.boss_id)
	var p: Dictionary = st.player
	match id:
		"gate_warden":
			var G: Dictionary = cfg.guard
			if stt == "guard_aim" or stt == "guard_lock":
				var locked: bool = stt == "guard_lock"
				var ang := PBoss3.facing(bz)
				_boss3_guard_arc(ci, bz, ang, float(G.frontDeg), float(G.reduce), float(G.radius) + 40.0)
				var half: float = float(G.arcDeg) * PI / 360.0
				var alpha: float = flash_t if locked else 0.35 + 0.35 * (st_t / maxf(0.001, float(G.aim)))
				fill_sector(ci, bx, by, float(G.radius), ang - half, ang + half, tel_fill(alpha * 0.3), 18)
				tel_stroke_sector(ci, bx, by, float(G.radius), ang - half, ang + half, alpha, 4.0 if locked else 2.0, 18)
				txt(ci, bx, by - br - 44.0, "밀치기!" if locked else "방패 자세 — 옆·뒤로 돌아가기", 13, tel_label(1.0))
			if stt == "breach_aim" or stt == "breach_lock" or stt == "breach":
				_boss3_dash_beam(ci, st, bz, float(cfg.breach.dist), flash_t, "방패 돌파" + (" → 휩쓸기" if int(bz.phase) >= 2 else ""), 1, 1)
			if stt == "bsweep_aim" or stt == "bsweep_lock":
				_boss3_sector(ci, bz, cfg.breach.sweep, stt == "bsweep_lock", flash_t, "넓은 휩쓸기 — 뒤 긴 빈틈")
			if stt == "bolts_aim" or stt == "bolts_lock":
				var BL: Dictionary = cfg.bolts
				var locked: bool = stt == "bolts_lock"
				var n: int = int(BL.count)
				for i in n:
					var a: float = PBoss3.facing(bz) + float(BL.spreadDeg) * PI / 180.0 * (float(i) - float(n - 1) / 2.0)
					_beam(ci, bx, by, a, float(BL.len), float(BL.width) + 10.0, locked, st_t / maxf(0.001, float(BL.aim)), flash_t)
				txt(ci, bx, by - br - 44.0, "석궁 3발!" if locked else "석궁 조준 — 줄 사이로", 13, tel_label(1.0))
		"spore_matriarch":
			for mk in bz.marks:
				var left: float = maxf(0.0, float(mk.land_at) - st.t)
				var k: float = 1.0 - minf(1.0, left / maxf(0.001, float(cfg.shot.delay)))
				var mx: float = mk.x
				var my: float = mk.y
				var mr: float = mk.r
				dashed_circle(ci, mx, my, mr, rgba(230, 120, 255, flash_t) if left < 0.4 else rgba(200, 120, 255, 0.8), 4.0 if left < 0.4 else 2.0, 6.0, 5.0)
				ci.draw_circle(Vector2(mx, my), mr * k, rgba(200, 120, 255, 0.12 + 0.25 * k))
				txt(ci, mx, my + 4.0, "%d · %.1f" % [int(mk.order), left], 12, C("#e0c0ff"))
			if stt == "ring_aim" or stt == "ring_lock" or stt == "ring":
				var R: Dictionary = cfg.ring
				var gap: float = float(bz.ring_gap)
				var gh: float = float(bz.ring_half)
				var locked: bool = stt != "ring_aim"
				var alpha: float = flash_t if locked else 0.35 + 0.35 * (st_t / maxf(0.001, float(R.aim)))
				var a0: float = gap + gh
				var a1: float = gap - gh + TAU
				if stt == "ring":
					var rr: float = float(bz.ring_r)
					var w: float = float(R.width)
					# 확산 중인 띠(빈 구간 제외): 바깥 호 - 안쪽 호
					ci.draw_arc(Vector2(bx, by), rr, a0, a1, 48, rgba(200, 120, 255, 0.85), w)
					ci.draw_arc(Vector2(bx, by), rr, a0, a1, 48, rgba(240, 200, 255, 0.9), 2.0)
				else:
					fill_sector(ci, bx, by, float(R.maxR), a0, a1, rgba(200, 120, 255, alpha * 0.18), 48)
					stroke_sector(ci, bx, by, float(R.maxR), a0, a1, rgba(220, 140, 255, alpha), 3.0 if locked else 1.5, 48)
				# 빈 구간(안전): 초록 부채꼴 + 문구
				fill_sector(ci, bx, by, float(R.maxR), gap - gh, gap + gh, rgba(120, 255, 160, 0.12), 12)
				stroke_sector(ci, bx, by, float(R.maxR), gap - gh, gap + gh, rgba(120, 255, 160, 0.8), 2.0, 12)
				txt(ci, bx + cos(gap) * float(R.maxR) * 0.6, by + sin(gap) * float(R.maxR) * 0.6, "빈 구간(안전)", 12, C("#a0ffb0"))
				txt(ci, bx, by - br - 44.0, "고리!" if locked else "포자 고리 준비 — 빈 구간으로", 13, C("#e0c0ff"))
			if stt == "spray_aim" or stt == "spray_lock":
				_boss3_sector(ci, bz, cfg.spray, stt == "spray_lock", flash_t, "분사 — 뒤에 정지")
		"excavation_behemoth":
			var B: Dictionary = cfg.burrow
			if stt == "burrow_aim":
				_boss3_dash_beam(ci, st, bz, float(B.dist), flash_t, "굴착 돌파", 1, int(bz.dash_total))
			if stt == "burrow_lock" or stt == "burrow":
				var plan: Array = bz.burrow_plan
				for i in plan.size():
					if i < int(bz.dash_seq) - 1:
						continue
					var pl: Dictionary = plan[i]
					var cur: bool = i == int(bz.dash_seq) - 1
					var ox: float = bx if cur else float(pl.x)
					var oy: float = by if cur else float(pl.y)
					var W: float = (br + float(p.r)) * 2.0
					ci.draw_set_transform_matrix(xf(Vector2(ox, oy), float(pl.ang), Vector2.ONE))
					ci.draw_rect(Rect2(0.0, -W / 2.0, float(pl.len), W), tel_fill((flash_t if cur else 0.5) * 0.3))
					ci.draw_rect(Rect2(0.0, -W / 2.0, float(pl.len), W), tel_edge(flash_t if cur else 0.6), 4.0 if cur else 2.0)
					ci.draw_set_transform_matrix(IDENT)
					var end: Array = pl.end
					dashed_circle(ci, float(end[0]), float(end[1]), br, tel_soft(0.8), 2.0, 5.0, 5.0)
					txt(ci, ox + cos(float(pl.ang)) * float(pl.len) * 0.5, oy + sin(float(pl.ang)) * float(pl.len) * 0.5 - 16.0, "굴착 %d/%d" % [i + 1, plan.size()], 13, C("#ffd166") if cur else C("#ffb080"))
			for rk in bz.rocks:
				if bool(rk.done):
					continue
				var left: float = maxf(0.0, float(rk.land_at) - st.t)
				var k: float = 1.0 - minf(1.0, left / maxf(0.001, float(cfg.rockfall.warn)))
				var rx: float = rk.x
				var ry: float = rk.y
				var rr2: float = rk.r
				dashed_circle(ci, rx, ry, rr2, tel_soft(flash_t) if left < 0.4 else rgba(230, 160, 100, 0.8), 4.0 if left < 0.4 else 2.0, 6.0, 5.0)
				ci.draw_circle(Vector2(rx, ry), rr2 * k, rgba(200, 140, 80, 0.12 + 0.3 * k))
				txt(ci, rx, ry + 6.0, str(int(rk.order)), 20, Color.WHITE)
				txt(ci, rx, ry - rr2 - 8.0, "낙석 %d · %.1f" % [int(rk.order), left], 11, tel_label(1.0))
		"frost_stalker":
			if stt == "bolt_aim" or stt == "bolt_lock":
				var locked: bool = stt == "bolt_lock"
				_beam(ci, bx, by, PBoss3.facing(bz), float(cfg.bolt.len), float(cfg.bolt.width) + 10.0, locked, st_t / maxf(0.001, float(cfg.bolt.aim)), flash_t)
				txt(ci, bx, by - br - 44.0, "얼음 발사!" if locked else "얼음 발사 준비 — 옆으로", 13, C("#bfefff"))
			if stt == "path_aim" or stt == "path_lock":
				var I: Dictionary = cfg.icepath
				var locked: bool = stt == "path_lock"
				var angs: Array = bz.lanes if locked else PBoss3.lane_angles({ "dir": float(bz.aim_angle) }, I)
				for i in angs.size():
					var a: float = float(angs[i])
					var alpha: float = flash_t if locked else 0.35 + 0.35 * (st_t / maxf(0.001, float(I.aim)))
					ci.draw_set_transform_matrix(xf(Vector2(bx, by), a, Vector2.ONE))
					ci.draw_rect(Rect2(0.0, -float(I.width) / 2.0, float(I.len), float(I.width)), rgba(160, 220, 255, alpha * 0.35))
					ci.draw_rect(Rect2(0.0, -float(I.width) / 2.0, float(I.len), float(I.width)), rgba(200, 240, 255, alpha), 4.0 if locked else 2.0)
					ci.draw_set_transform_matrix(IDENT)
					txt(ci, bx + cos(a) * float(I.len) * 0.55, by + sin(a) * float(I.len) * 0.55, "얼음길 %d" % (i + 1), 12, C("#bfefff"))
				txt(ci, bx, by - br - 44.0, "얼음길!" if locked else "얼음길 준비 — 줄 사이 통로로", 13, C("#bfefff"))
			if stt == "dash_aim" or stt == "dash_lock" or stt == "dash":
				_boss3_dash_beam(ci, st, bz, float(cfg.dash.dist), flash_t, "돌진", 1, 1)
		"blood_hunt_king":
			if stt == "claw_aim" or stt == "claw_lock":
				_boss3_sector(ci, bz, cfg.claw, stt == "claw_lock", flash_t, "발톱 휩쓸기 — 뒤로")
			if stt == "dash_aim" or stt == "dash_lock" or stt == "dash":
				_boss3_dash_beam(ci, st, bz, float(cfg.dash.dist), flash_t, "추적 돌진", int(bz.dash_seq), int(bz.dash_total))
			if stt == "dash_reaim" or stt == "dash_relock":
				# 재조준 표식: 이 자리에서 새 방향이 정해진다(첫 예고 선과 별개). 고정 전엔 추적 각, 고정 뒤엔 실제 경로
				var locked: bool = stt == "dash_relock"
				stroke_circle(ci, bx, by, br + 10.0, rgba(255, 200, 80, 0.9), 3.0)
				ci.draw_line(Vector2(bx - br - 18.0, by), Vector2(bx + br + 18.0, by), rgba(255, 200, 80, 0.9), 2.0)
				ci.draw_line(Vector2(bx, by - br - 18.0), Vector2(bx, by + br + 18.0), rgba(255, 200, 80, 0.9), 2.0)
				_boss3_dash_beam(ci, st, bz, float(cfg.dash.dist), flash_t, "재조준" if not locked else "방향 고정", 2, 2)
				txt(ci, bx, by + br + 26.0, "재조준 지점 — 방향 고정 %s" % ("완료" if locked else "%.1f초 뒤" % maxf(0.0, float(cfg.dash.reaim) - st_t)), 12, C("#ffd166"))
		"doom_executor":
			var SL: Dictionary = cfg.slash
			if stt == "slash_warn" or stt == "slash_lock" or stt == "slash_gap":
				for i in (bz.slashes as Array).size():
					var sl: Dictionary = bz.slashes[i]
					if bool(sl.fired):
						continue
					var cur: bool = i == int(bz.slash_idx)
					var first: bool = int(sl.order) == 1
					var k: float = 1.0
					if stt == "slash_warn":
						k = st_t / maxf(0.001, float(SL.warn))
					elif stt == "slash_gap":
						k = st_t / maxf(0.001, float(SL.gap))
					var locked: bool = cur and stt == "slash_lock"
					var alpha: float = flash_t if locked else 0.35 + 0.35 * k
					var col_fill: Color = tel_fill(alpha * 0.3) if first else rgba(200, 100, 255, alpha * 0.3)
					var col_line: Color = tel_edge(alpha) if first else rgba(220, 140, 255, alpha)
					var sx: float = sl.x
					var w: float = float(SL.width)
					ci.draw_rect(Rect2(sx - w / 2.0, 0.0, w, st.arena_h), col_fill)
					if first:
						ci.draw_rect(Rect2(sx - w / 2.0, 0.0, w, st.arena_h), col_line, false, 4.0 if locked else 2.0)
					else:
						dashed_line(ci, Vector2(sx - w / 2.0, 0.0), Vector2(sx - w / 2.0, st.arena_h), col_line, 3.0 if locked else 2.0, 10.0, 8.0)
						dashed_line(ci, Vector2(sx + w / 2.0, 0.0), Vector2(sx + w / 2.0, st.arena_h), col_line, 3.0 if locked else 2.0, 10.0, 8.0)
					txt(ci, sx, 24.0 + float(i) * 18.0, "절단 %d%s" % [int(sl.order), "!" if locked else (" (따라옴)" if not bool(sl.fixed) else " 고정")], 13, tel_label(1.0) if first else C("#e0c0ff"))
			if stt == "guard":
				var G: Dictionary = cfg.guard
				_boss3_guard_arc(ci, bz, float(bz.face), float(G.frontDeg), float(G.reduce), float(G.strike.radius))
				txt(ci, bx, by - br - 44.0, "회전 방어 자세 %.1f초 — 옆·뒤로" % maxf(0.0, float(G.dur) - float(bz.guard_t)), 13, C("#c8b8ff"))
			if stt == "gstrike_aim" or stt == "gstrike_lock":
				_boss3_sector(ci, bz, cfg.guard.strike, stt == "gstrike_lock", flash_t, "큰 베기 — 뒤 자세 해제")

## 부채꼴 예고(준비: 추적 각 옅게, 확정: 고정 각 진하게 + '!')
static func _boss3_sector(ci: Node2D, bz: Dictionary, S: Dictionary, locked: bool, flash_t: float, label: String) -> void:
	var ang := PBoss3.facing(bz)
	var half: float = float(S.arcDeg) * PI / 360.0
	var alpha: float = flash_t if locked else 0.35 + 0.35 * (float(bz.state_t) / maxf(0.001, float(S.aim)))
	var R: float = float(S.radius)
	fill_sector(ci, float(bz.x), float(bz.y), R, ang - half, ang + half, tel_fill(alpha * 0.32), 24)
	tel_stroke_sector(ci, float(bz.x), float(bz.y), R, ang - half, ang + half, alpha, 4.0 if locked else 2.0, 24)
	txt(ci, float(bz.x), float(bz.y) - float(bz.r) - 44.0, "!" if locked else label, 18 if locked else 13, tel_mark(1.0) if locked else tel_label(1.0))

## 직선 돌진 예고(준비 중엔 추적 각의 실제 경로, 확정 뒤엔 고정 경로) + 끝점 원 + n/m 표시
static func _boss3_dash_beam(ci: Node2D, st: CombatState, bz: Dictionary, dist: float, flash_t: float, label: String, seq: int, total: int) -> void:
	var stt := String(bz.state)
	var locked: bool = not (stt.ends_with("_aim") or stt == "dash_reaim")
	var bx: float = bz.x
	var by: float = bz.y
	var br: float = bz.r
	var ang: float = float(bz.dir) if locked else float(bz.aim_angle)
	var plen: float
	var pend: Array
	if locked:
		plen = float(bz.get("dash_len", 0.0))
		pend = bz.get("dash_end", [])
	else:
		var path := PBoss3.path_from(st, bx, by, br, ang, dist)
		plen = float(path["len"])
		pend = path.end
	if pend.is_empty():
		pend = [bx + cos(ang) * plen, by + sin(ang) * plen]
	var alpha: float = flash_t if locked else 0.35 + 0.35 * minf(1.0, float(bz.state_t))
	var W: float = (br + float(st.player.r)) * 2.0
	ci.draw_set_transform_matrix(xf(Vector2(bx, by), ang, Vector2.ONE))
	ci.draw_rect(Rect2(0.0, -W / 2.0, plen, W), tel_fill(alpha * 0.3))
	tel_stroke_rect(ci, Rect2(0.0, -W / 2.0, plen, W), alpha, 4.0 if locked else 2.0)
	ci.draw_line(Vector2(br, 0.0), Vector2(maxf(br, plen - 14.0), 0.0), tel_edge(alpha), 4.0 if locked else 2.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(plen, 0.0), Vector2(plen - 18.0, -10.0), Vector2(plen - 18.0, 10.0)]), tel_edge(alpha))
	ci.draw_set_transform_matrix(IDENT)
	dashed_circle(ci, float(pend[0]), float(pend[1]), br, tel_soft(alpha), 2.0, 5.0, 5.0)
	txt(ci, bx, by - br - 44.0, ("!" if locked else label + " 준비 — 옆으로") + ((" %d/%d" % [seq, total]) if total > 1 else ""), 18 if locked else 13, tel_mark(1.0) if locked else tel_label(1.0))

# ---------- 투사체 ----------
static func draw_projectiles(ci: Node2D, st: CombatState) -> void:
	for pr in st.projectiles:
		if bool(pr.get("dead", false)):
			continue
		var kind := String(pr.kind)
		var x: float = pr.x
		var y: float = pr.y
		var vx: float = pr.vx
		var vy: float = pr.vy
		var c := Vector2(x, y)
		if String(pr.owner) == "player" and kind != "shard" and kind != "shard_common":
			var ang: float = atan2(vy, vx)
			if kind == "crescent":
				ci.draw_set_transform_matrix(xf(c, ang, Vector2.ONE))
				ci.draw_arc(Vector2(-8, 0), 18.0, -1.1, 1.1, 12, rgba(220, 245, 255, 0.95), 4.0)
				ci.draw_set_transform_matrix(IDENT)
				continue
			if kind == "arrow_h":
				ci.draw_set_transform_matrix(xf(c, ang, Vector2.ONE))
				ci.draw_line(Vector2(-12, 0), Vector2(8, 0), C("#e8f7ff"), 2.5)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(4, -4), Vector2(4, 4)]), C("#9fd8ff"))
				ci.draw_set_transform_matrix(IDENT)
				continue
			if kind == "bolt":
				var bang: float = atan2(vy, vx)
				# 서리 부채: 세 발이 각각 어느 방향으로 가는지 읽히도록 진행 방향 꼬리를 그린다(양옆 2발만 길고 갈매기 표식)
				var side_mod: bool = String(pr.get("mod", "")) == "fan"
				var tail: float = 28.0 if side_mod else 16.0
				ci.draw_line(Vector2(x - cos(bang) * tail, y - sin(bang) * tail), c, rgba(144, 229, 244, 0.55 if side_mod else 0.3), 3.0 if side_mod else 2.0)
				ci.draw_circle(c, 6.0, C("#bfefff"))
				for i in 3:
					var a: float = float(i) * PI / 3.0 + st.t * 6.0
					ci.draw_line(Vector2(x - cos(a) * 7.0, y - sin(a) * 7.0), Vector2(x + cos(a) * 7.0, y + sin(a) * 7.0), rgba(160, 230, 255, 0.7), 2.0)
				if side_mod:
					ci.draw_polyline(PackedVector2Array([Vector2(x - cos(bang + 0.45) * 13.0, y - sin(bang + 0.45) * 13.0), c, Vector2(x - cos(bang - 0.45) * 13.0, y - sin(bang - 0.45) * 13.0)]), rgba(200, 245, 255, 0.85), 2.0)
				continue
			if kind == "blade":
				for i in 3:
					ci.draw_set_transform_matrix(xf(c, st.t * 20.0 + TAU / 3.0 * float(i + 1), Vector2.ONE))
					ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(12, -3), Vector2(12, 3)]), C("#e6edf5"))
				ci.draw_set_transform_matrix(IDENT)
				continue
		if kind == "shock":
			var r: float = pr.r
			ci.draw_set_transform_matrix(xf(c, float(pr.get("angle", atan2(vy, vx))), Vector2.ONE))
			ci.draw_arc(Vector2(-10, 0), r, -1.2, 1.2, 12, rgba(255, 200, 120, 0.95), 5.0)
			ci.draw_arc(Vector2(-22, 0), r * 0.8, -1.0, 1.0, 10, rgba(255, 120, 60, 0.6), 3.0)
			ci.draw_set_transform_matrix(IDENT)
		elif kind == "hex":
			ci.draw_circle(c, 10.0, rgba(200, 120, 255, 0.45))
			ci.draw_circle(c, 5.0, C("#e9b6ff"))
		elif kind == "arrow":
			ci.draw_set_transform_matrix(xf(c, float(pr.get("angle", atan2(vy, vx))), Vector2.ONE))
			ci.draw_line(Vector2(-14, 0), Vector2(8, 0), C("#ffd9a0"), 3.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(4, -4), Vector2(4, 4)]), C("#ff6b6b"))
			ci.draw_set_transform_matrix(IDENT)
		elif kind == "boss_bolt": # 파수장 석궁 볼트(굵은 화살)
			ci.draw_set_transform_matrix(xf(c, float(pr.get("angle", atan2(vy, vx))), Vector2.ONE))
			ci.draw_line(Vector2(-18, 0), Vector2(10, 0), C("#d8c8a8"), 4.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(16, 0), Vector2(6, -6), Vector2(6, 6)]), C("#ff6b6b"))
			ci.draw_set_transform_matrix(IDENT)
		elif kind == "boss_icebolt": # 서리 추적자 얼음 탄(푸른 결정)
			var r2: float = pr.r
			ci.draw_set_transform_matrix(xf(c, float(pr.get("angle", atan2(vy, vx))), Vector2.ONE))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(r2 * 1.6, 0), Vector2(0, -r2), Vector2(-r2 * 1.4, 0), Vector2(0, r2)]), rgba(200, 240, 255, 0.95))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-r2 * 1.4, 0), Vector2(-r2 * 2.6, -r2 * 0.5), Vector2(-r2 * 2.6, r2 * 0.5)]), rgba(191, 239, 255, 0.45))
			ci.draw_set_transform_matrix(IDENT)
		elif kind == "shard" and String(pr.get("mod", "")) == "split":
			# 분열 창날의 파편: 창 금색 뾰족 실루엣 + 갈라져 나온 방향의 꼬리(어느 갈래인지 읽힌다)
			var sa: float = atan2(vy, vx)
			ci.draw_set_transform_matrix(xf(c, sa, Vector2.ONE))
			ci.draw_line(Vector2(-22.0, 0.0), Vector2(0.0, 0.0), rgba(244, 198, 109, 0.5), 2.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(9.0, 0.0), Vector2(-4.0, -4.0), Vector2(-2.0, 0.0), Vector2(-4.0, 4.0)]), C("#f4c66d"))
			ci.draw_set_transform_matrix(IDENT)
		elif kind == "shard" and String(pr.get("mod", "")) == "shatter":
			# 깨지는 수정의 파편: 서리 청록 결정 조각 + 파열 지점 쪽 꼬리(파열 순간과 실제 적중을 잇는다)
			var sa2: float = atan2(vy, vx)
			ci.draw_set_transform_matrix(xf(c, sa2, Vector2.ONE))
			ci.draw_line(Vector2(-18.0, 0.0), Vector2(0.0, 0.0), rgba(144, 229, 244, 0.45), 2.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(6.0, 0.0), Vector2(0.0, -4.0), Vector2(-5.0, 0.0), Vector2(0.0, 4.0)]), C("#90e5f4"))
			ci.draw_set_transform_matrix(IDENT)
		else:
			ci.draw_circle(c, 4.0, C("#bfefff"))
			ci.draw_circle(Vector2(x - vx * 0.02, y - vy * 0.02), 3.0, rgba(191, 239, 255, 0.4))

# ---------- 타격 연출(적중·사망·피격). 적 예고선 아래에 그린다 ----------
## 여기 있는 것은 전부 '이미 일어난 일'의 표시다. 규칙이 만든 fx 값(spark·death·hitflash)만 읽고
## 무적·재사용·판정·봇 반응에 쓰이는 값은 어떤 것도 만들지 않는다.
## 그리는 자리: draw_telegraphs 앞 — 아군 적중 연출이 적 예고를 덮지 않게 한다.
static func draw_impacts(ci: Node2D, st: CombatState) -> void:
	for f in st.effects:
		var k: float = 1.0 - float(f.t) / maxf(0.001, float(f.ttl))
		match String(f.kind):
			"spark": # 적중: 맞은 방향으로 뻗는 쐐기 + 짧은 충격 고리(치명타는 금색·더 크게)
				var fx: float = f.x
				var fy: float = f.y
				var base: float = float(f.get("angle", 0.0))
				var crit: bool = bool(f.get("crit", false))
				var col := C("#ffd166", k) if crit else Color(1, 1, 1, k)
				var grow: float = 1.0 - k
				var scale: float = 1.35 if crit else 1.0
				# ① 진행 방향으로 벌어지는 쐐기(어느 쪽에서 맞았는지 읽힌다)
				var tip: float = (10.0 + 22.0 * grow) * scale
				var back: float = 5.0 * scale
				var wide: float = (7.0 + 4.0 * grow) * scale
				var dirv := Vector2(cos(base), sin(base))
				var nrm := Vector2(-dirv.y, dirv.x)
				var o := Vector2(fx, fy)
				ci.draw_colored_polygon(PackedVector2Array([o + dirv * tip, o + nrm * wide - dirv * back, o - dirv * (back * 1.6), o - nrm * wide - dirv * back]), Color(col, 0.55 * k))
				# ② 방향으로 흩어지는 불티(±0.5rad 부채)
				var seg := PackedVector2Array()
				for i in 5:
					var a: float = base + float(i - 2) * 0.5
					var r0: float = (6.0 + 14.0 * grow) * scale
					seg.append(Vector2(fx + cos(a) * r0, fy + sin(a) * r0))
					seg.append(Vector2(fx + cos(a) * (r0 + 6.0 * scale), fy + sin(a) * (r0 + 6.0 * scale)))
				ci.draw_multiline(seg, col, 2.0 * scale)
				# ③ 맞은 자리의 짧은 흰 고리(치명타만 한 겹 더)
				stroke_circle(ci, fx, fy, (5.0 + 13.0 * grow) * scale, Color(1, 1, 1, 0.5 * k), 2.0)
				if crit:
					stroke_circle(ci, fx, fy, (5.0 + 20.0 * grow) * scale, C("#ffd166", 0.5 * k), 2.0)
			"death": # 사망 반응: 바깥으로 흩어지는 조각 + 주저앉는 고리(적 색을 그대로 쓴다)
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				var dc := C(String(f.get("color", "#9aa0a8")), k)
				var grow: float = 1.0 - k
				stroke_circle(ci, fx, fy, r * (0.5 + 1.5 * grow), Color(dc, 0.5 * k), 3.0 * k + 1.0)
				fill_ellipse(ci, fx, fy + r * 0.4, r * (1.0 + 0.6 * grow), r * (0.3 + 0.2 * grow), Color(0, 0, 0, 0.22 * k))
				for i in 9:
					var a: float = float(i) * TAU / 9.0 + 0.3
					var dd: float = r * (0.6 + 1.9 * grow)
					var px: float = fx + cos(a) * dd
					var py: float = fy + sin(a) * dd - 14.0 * grow + 26.0 * grow * grow
					ci.draw_circle(Vector2(px, py), 3.2 * k + 1.0, Color(dc, 0.85 * k))
			"hitflash": # 내가 맞았다: 몸 주위 고리 + 화면 가장자리만 붉게(경기장 전체를 덮지 않는다 — 예고가 묻힌다)
				stroke_circle(ci, float(f.x), float(f.y), 18.0 + 16.0 * (1.0 - k), C("#ff5050", k * 0.55), 3.0)
				var w: float = st.arena_w
				var h: float = st.arena_h
				var band: float = 26.0
				var ec := Color(1, 0.2, 0.2, 0.30 * k)
				ci.draw_rect(Rect2(0, 0, w, band), ec)
				ci.draw_rect(Rect2(0, h - band, w, band), ec)
				ci.draw_rect(Rect2(0, band, band, h - band * 2.0), ec)
				ci.draw_rect(Rect2(w - band, band, band, h - band * 2.0), ec)

# ---------- 불꽃·숫자·기타 효과 ----------
static func draw_misc(ci: Node2D, st: CombatState) -> void:
	for f in st.effects:
		var k: float = 1.0 - float(f.t) / maxf(0.001, float(f.ttl))
		var kind := String(f.kind)
		match kind:
			"bosssweep":
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				var ang: float = f.angle
				var half: float = f.half
				fill_sector(ci, fx, fy, r, ang - half, ang + half, rgba(255, 120, 80, 0.35 * k), 24)
				ci.draw_arc(Vector2(fx, fy), r * (0.6 + 0.4 * (1.0 - k)), ang - half, ang + half, 24, C("#ffd9b0", k), maxf(1.0, 6.0 * k))
			"bossland":
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				ci.draw_circle(Vector2(fx, fy), r * (0.6 + 0.4 * (1.0 - k)), rgba(200, 150, 90, 0.35 * k))
				stroke_circle(ci, fx, fy, r * (1.0 - k * 0.2), C("#e8c9a0", k), 5.0)
				for i in 10:
					var a: float = float(i) * TAU / 10.0
					ci.draw_circle(Vector2(fx + cos(a) * r * (1.0 - k) * 0.9, fy + sin(a) * r * (1.0 - k) * 0.9 - 14.0 * k), 3.0, C("#8a6b45", k))
			"burst":
				stroke_circle(ci, float(f.x), float(f.y), float(f.r) * (1.0 - k * 0.6), C(String(f.get("color", "#ffffff")), k), 4.0)
			"slashline": # 집행관 세로 절단(순서별 색)
				var first: bool = int(f.get("order", 1)) == 1
				var w: float = float(f.w) * (1.0 - k * 0.5)
				ci.draw_rect(Rect2(float(f.x) - w / 2.0, float(f.y), w, float(f.h)), rgba(255, 120, 80, 0.45 * k) if first else rgba(220, 140, 255, 0.45 * k))
				ci.draw_line(Vector2(float(f.x), float(f.y)), Vector2(float(f.x), float(f.y) + float(f.h)), Color(1, 1, 1, k), 3.0)
			"flare":
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				ci.draw_circle(Vector2(fx, fy), r * (0.5 + 0.5 * (1.0 - k)), C("#ff9f43", k * 0.6))
				stroke_circle(ci, fx, fy, r * (1.0 - k * 0.3), C("#ffe08a", k), 4.0)
				for i in 8:
					var a: float = float(i) * TAU / 8.0
					ci.draw_circle(Vector2(fx + cos(a) * r * (1.0 - k) * 1.1, fy + sin(a) * r * (1.0 - k) * 1.1), 3.0, C("#ffcc55", k))
			"stasisburst":
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				ci.draw_circle(Vector2(fx, fy), r * (1.0 - k * 0.4), rgba(160, 210, 255, 0.35 * k))
				for i in 6:
					var a: float = float(i) * TAU / 6.0 + 0.4
					ci.draw_line(Vector2(fx, fy), Vector2(fx + cos(a) * r * (1.2 - k * 0.5), fy + sin(a) * r * (1.2 - k * 0.5)), C("#e0f4ff", k), 3.0)
			"healbeam":
				dashed_line(ci, Vector2(float(f.x), float(f.y) - 30.0), Vector2(float(f.tx), float(f.ty)), C("#8ee6a0", k), 3.0, 6.0, 4.0)
			"frostburst":
				var fx: float = f.x
				var fy: float = f.y
				var r: float = f.r
				ci.draw_circle(Vector2(fx, fy), r * (0.7 + 0.3 * (1.0 - k)), rgba(200, 240, 255, 0.5 * k))
				for i in 6:
					var a: float = float(i) * TAU / 6.0
					ci.draw_line(Vector2(fx, fy), Vector2(fx + cos(a) * r * (1.1 - k * 0.4), fy + sin(a) * r * (1.1 - k * 0.4)), Color(1, 1, 1, k), 3.0)
			"fieldend":
				stroke_circle(ci, float(f.x), float(f.y), float(f.r) * (1.0 + 0.15 * (1.0 - k)), C("#bfe6ff", k * 0.7), maxf(1.0, 6.0 * k))
	for f in st.effects:
		if String(f.kind) == "text":
			var a: float = minf(1.0, (1.0 - float(f.t) / maxf(0.001, float(f.ttl))) * 2.0)
			txt(ci, float(f.x), float(f.y), str(f.get("text", "")), 15, C(String(f.get("color", "#ffffff")), a), 0, true)

# ---------- 전체 ----------
## 그리기 순서: 배경 → 개체 → 내 적중 연출(draw_impacts) → 적 예고(draw_telegraphs) → 투사체 → 숫자.
## 적 예고는 항상 아군 연출 위다. 적중 불티·사망 조각·피격 붉은 테두리가 예고를 덮지 않는다.
static func draw(ci: Node2D, st: CombatState, decor: Dictionary) -> void:
	use_palette(st)
	# 화면 흔들림: 기준 변환에만 넣는다. 아래 모든 그리기가 이 위에 얹히고 HUD(Control)는 영향을 받지 않는다
	IDENT = Transform2D(0.0, Vector2.ONE, 0.0, shake_offset(st))
	ci.draw_set_transform_matrix(IDENT)
	_draw_layers(ci, st, decor)
	IDENT = Transform2D.IDENTITY
	ci.draw_set_transform_matrix(IDENT)

static func _draw_layers(ci: Node2D, st: CombatState, decor: Dictionary) -> void:
	draw_forest(ci, st, decor)
	draw_obstacles(ci, st)
	draw_zones(ci, st)
	draw_chest(ci, st)
	draw_objects(ci, st)
	draw_pickups(ci, st)
	draw_range(ci, st)
	draw_weapon_bodies(ci, st)
	draw_player_effects(ci, st)
	# 개체는 y순으로(겹침이 자연스럽게). -1 = 플레이어
	var order: Array = []
	for i in st.enemies.size():
		order.append([float(st.enemies[i].y), i])
	order.append([float(st.player.y), -1])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for o in order:
		var idx: int = o[1]
		if idx < 0:
			draw_swordsman(ci, st)
		else:
			draw_enemy(ci, st, st.enemies[idx])
	draw_canopies(ci, st)
	draw_impacts(ci, st)
	draw_telegraphs(ci, st)
	draw_projectiles(ci, st)
	draw_misc(ci, st)
