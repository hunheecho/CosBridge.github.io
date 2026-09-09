class_name PTouchScroll
extends Node
## 손가락으로 목록을 넘기는 공통 장치. `ScrollContainer` 하나에 붙여 두면 그 목록이 제대로 넘어간다.
## 화면 14개가 모두 `PScreen`을 상속하고 `PScreen.setup()`이 여기 하나를 붙이므로,
## 이 파일만 고치면 상점·장비·대장간·통계·기록… 전부가 함께 고쳐진다.
##
## 왜 Godot 내장 터치 스크롤을 그냥 쓰지 않는가
## -------------------------------------------
## 1) **버튼 위에서 시작한 끌기.** 버튼(`MOUSE_FILTER_STOP`)이 사건을 먹으면 바깥 ScrollContainer는
##    아무 것도 받지 못한다. 상점처럼 버튼이 빽빽한 화면에서는 그게 곧 "스크롤이 안 된다"였다(KD-8).
## 2) **탭과 끌기를 갈라야 한다.** 내장에는 문턱이 없어 손가락이 1px만 밀려도 스크롤이 시작된다.
##    우리는 12px을 넘겨야 끌기로 보고, 그 순간 눌려 있던 버튼에 **취소**를 보낸다.
##    이게 없으면 "넘기려다 실수로 팔았다"가 다시 생긴다(친구 보고).
## 그래서 화면 계층(`_input`)에서 직접 받는다. 대신 내장이 주던 두 가지를 여기서 갖춰야 한다 —
## **소수점 이동**과 **관성**. 아래 두 개가 그것이다.
##
## 소수점 이동
## ----------
## `ScrollContainer.scroll_vertical`은 정수다. 예전 코드는 사건마다 `int(relative.y)`로 잘라 넣어
## 1px 미만 움직임을 **전부 버렸다**(0.4px씩 10번 끌면 0px). 폰은 화면 갱신보다 손가락을 더 자주
## 읽으므로 한 사건의 이동량이 늘 작고, 화면 배율(canvas_items·expand) 때문에 더 작아진다.
## 여기서는 자리를 float `_pos`로 들고 있고 화면에는 **반올림한 정수**만 넣는다. 남는 소수는
## `_pos`에 그대로 남아 다음 사건·다음 프레임으로 이어진다.
##
## 관성
## ----
## 손을 뗄 때의 속도로 계속 미끄러지다가 마찰로 멎는다. 경계에서는 그 자리에 선다(튕기지 않는다).
##
## 속도는 **마지막 0.1초 동안 실제로 움직인 거리 ÷ 그 시간**이다(안드로이드 VelocityTracker와 같은 방식).
## 예전에는 프레임마다 재고 지수 평활(0.65)을 걸었는데, 그러면 **손가락 사건이 없는 프레임마다 속도가 0.35배로 죽었다.**
## 브라우저는 화면 갱신과 터치 표본의 주기가 다르므로 끌기 도중에도 사건 없는 프레임이 늘 섞인다.
## 2026-09-09 실제 브라우저 계측(폰 가로 640×360·캔버스 1137×640): 빠른 쓸기 뒤 속도가 520 → 182 → 64 → 22px/초로
## 내려앉아, 손을 떼는 순간에는 171px/초만 남았고 목록은 **10px 남짓 가다 그 자리에 섰다**(관성이 사실상 없었다).
## 시간창으로 재면 그런 프레임이 있어도 값이 흔들리지 않는다.
## 떼기 직전 0.12초 동안 손가락이 멈춰 있었으면 던지지 않는다(붙잡아 세운 뒤 떼는 동작).
##
## 되돌아온 취소 사건에 스스로 당하지 않기
## --------------------------------------
## `push_input`으로 밀어 넣은 취소 사건은 **우리 `_input`으로 곧장 되돌아온다**.
## 예전 코드는 그것을 진짜 손 뗌으로 읽어 `_drag_id`를 지웠고, 그 뒤 같은 손가락의 끌기는
## 전부 무시됐다 — 한 번 누를 때마다 **딱 한 칸**만 움직인 원인이다(2026-09-09 계측).
## `_in_cancel` 동안 들어오는 사건은 우리 것이므로 상태를 건드리지 않는다.

## --- 시험값(사람 손으로 맞춰야 하는 값. 규칙과 무관하다) ---
const DRAG_START_PX := 12.0     # 이만큼 움직여야 탭이 아니라 끌기로 본다
const MAX_SPEED := 3000.0       # 관성 최대 속도(px/초). 화면 하나가 640px이다
const FRICTION := 2000.0        # 마찰(px/초²). 최대 속도에서 약 1.5초·2250px 미끄러진다
const STOP_SPEED := 8.0         # 이보다 느려지면 그 자리에서 멈춘다(px/초)
const VEL_WINDOW := 0.10        # 뗄 때 '마지막 이만큼(초)' 동안의 이동으로 속도를 낸다
const VEL_IDLE := 0.12          # 떼기 전에 이만큼(초) 손가락이 멈춰 있었으면 던지지 않는다
const VEL_KEEP := 24            # 들고 있는 이동 표본의 최대 개수

var enabled := true             # 끄면 이 장치는 아무 것도 하지 않는다(PC 휠 경로에는 영향 없다)
var blocked: Callable = Callable()  # true를 주면 새 끌기를 시작하지 않는다(확인 창이 열렸을 때 등)

var _scroll: ScrollContainer = null
var _pos := 0.0                 # 소수점까지 들고 있는 세로 자리(정본). 화면에는 반올림해 넣는다
var _drag_id := -1              # 지금 끌고 있는 손가락 번호(-1이면 없다)
var _drag_from := Vector2.ZERO  # 그 손가락이 처음 닿은 자리(문턱 판정용)
var _dragging := false          # 문턱을 넘어 끌기로 확정됐는가
var _velocity := 0.0            # 관성 속도(px/초). 아래로 밀면 양수
var _samples: Array[Vector2] = []  # 최근 이동 표본 [시각(초), 그때의 _pos]. 뗄 때 속도를 여기서 낸다
var _elapsed := 0.0             # step()이 받은 delta의 누적. 표본의 시간 축(시험도 같은 축을 쓴다)
var _last_delta := 1.0 / 60.0   # 마지막 프레임 간격(한 프레임 안에 사건이 몰렸을 때의 시간 축)
var _in_cancel := false         # 우리가 밀어 넣은 취소 사건을 처리하는 중인가

## 이 스크롤에 장치를 붙인다. host의 자식으로 들어가 host와 함께 살고 죽는다.
static func attach(host: Node, sc: ScrollContainer) -> PTouchScroll:
	var ts := PTouchScroll.new()
	ts.name = "TouchScroll"
	ts._scroll = sc
	host.add_child(ts)
	return ts

## 지금 손가락 입력을 받아도 되는 상태인가. 터치 기기가 아니면 항상 false(PC는 휠 그대로).
func active() -> bool:
	return enabled and _scroll != null and is_instance_valid(_scroll) \
		and _scroll.is_visible_in_tree() and PLayout.is_touch()

## 끌기·관성을 모두 끝내고 자리를 다시 읽는다. 화면이 바뀔 때 부른다(다음 화면이 저절로 미끄러지지 않게).
func stop() -> void:
	_drag_id = -1
	_dragging = false
	_velocity = 0.0
	_samples.clear()
	sync()

## 바깥에서 `scroll_vertical`을 바꾼 뒤(보던 자리 되살리기 등) 소수점 자리를 맞춘다.
func sync() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_pos = float(_scroll.scroll_vertical)

func is_dragging() -> bool:
	return _dragging

func velocity() -> float:
	return _velocity

func position_f() -> float:
	return _pos

## 더 내려갈 수 있는 최대 자리. 내용이 창보다 짧으면 0이다.
func max_scroll() -> float:
	if _scroll == null or not is_instance_valid(_scroll):
		return 0.0
	var vb := _scroll.get_v_scroll_bar()
	if vb == null:
		return 0.0
	return maxf(0.0, vb.max_value - vb.page)

# ---------- 입력 ----------
func _input(event: InputEvent) -> void:
	if handle(event):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()

## 사건 하나를 처리한다. true면 우리가 삼킨 것이다(시험이 직접 부르는 입구이기도 하다).
func handle(event: InputEvent) -> bool:
	if _in_cancel:
		return false            # 우리가 밀어 넣은 취소 사건이 되돌아온 것 — 상태를 건드리지 않는다
	if not active():
		return false
	if event is InputEventScreenTouch:
		return _on_touch(event as InputEventScreenTouch)
	if event is InputEventScreenDrag:
		return _on_drag(event as InputEventScreenDrag)
	return false

## 누름은 절대 삼키지 않는다 — 평범한 탭이 그대로 살아야 한다.
## 끌기로 확정된 뒤의 손 뗌만 삼킨다(내장 관성이 뒤늦게 끼어들지 않게).
func _on_touch(t: InputEventScreenTouch) -> bool:
	if t.pressed:
		if _drag_id != -1:
			return false        # 이미 다른 손가락이 끌고 있다 — 손가락을 바꾸지 않는다
		if not _can_start(t.position):
			return false
		_drag_id = t.index
		_drag_from = t.position
		_dragging = false
		_velocity = 0.0         # 미끄러지는 중에 손을 대면 그 자리에 선다(사람이 기대하는 동작)
		_samples.clear()
		sync()
		return false
	if t.index != _drag_id:
		return false
	var was := _dragging
	_drag_id = -1
	_dragging = false
	if was:
		_velocity = _release_velocity()   # 마지막 시간창의 실제 이동으로 던진다
	_samples.clear()
	return was

func _on_drag(d: InputEventScreenDrag) -> bool:
	if d.index != _drag_id:
		return false
	if not _dragging:
		if d.position.distance_to(_drag_from) < DRAG_START_PX:
			return false        # 아직 탭일 수 있다 — 아무 것도 하지 않는다
		_dragging = true
		_cancel_press(d)
	var before := _pos
	_move_by(-d.relative.y)      # 손가락을 위로 올리면 목록이 내려간다
	if absf(_pos - before) > 0.0:
		_push_sample()           # 경계에 막혀 못 움직인 만큼은 속도로도 세지 않는다
	return true

## 지금 자리를 표본으로 남긴다(시간 축 = step이 받은 delta의 누적)
func _push_sample() -> void:
	_samples.append(Vector2(_elapsed, _pos))
	if _samples.size() > VEL_KEEP:
		_samples.remove_at(0)

## 손을 뗄 때의 속도(px/초). 마지막 VEL_WINDOW초 동안 실제로 움직인 거리로 낸다.
## 프레임마다 재지 않으므로 **사건이 없는 프레임이 있어도 값이 줄지 않는다**(이게 관성이 죽던 원인이었다).
func _release_velocity() -> float:
	var n := _samples.size()
	if n == 0:
		return 0.0
	var last: Vector2 = _samples[n - 1]
	if _elapsed - last.x > VEL_IDLE:
		return 0.0               # 떼기 전에 손가락이 멈춰 있었다 — 던지지 않는다
	var first: Vector2 = last
	for i in range(n - 1, -1, -1):
		var s: Vector2 = _samples[i]
		if last.x - s.x > VEL_WINDOW:
			break
		first = s
	var dist: float = last.y - first.y
	if absf(dist) < 0.0001:
		return 0.0
	var span: float = last.x - first.x
	# 사건이 한 프레임에 몰려 시간 폭이 0이면 그 프레임 길이를 시간 축으로 쓴다(0으로 나누지 않는다)
	var denom: float = span if span > 0.0 else maxf(_last_delta, 0.001)
	return clampf(dist / denom, -MAX_SPEED, MAX_SPEED)

## 끌기로 판정한 순간, 눌려 있던 버튼의 누름을 취소한다.
## 손을 떼도 그 버튼은 눌리지 않는다 — "넘기려다 실수로 팔았다"를 막는 장치다.
func _cancel_press(d: InputEventScreenDrag) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var c := InputEventScreenTouch.new()
	c.index = d.index
	c.position = d.position
	c.pressed = false
	c.canceled = true
	_in_cancel = true
	vp.push_input(c, true)       # 이미 뷰포트 좌표다 — 다시 변환시키지 않는다
	_in_cancel = false

## 새 끌기를 시작해도 되는 자리인가: 스크롤 안이어야 하고, 위에 창이 떠 있으면 안 된다.
func _can_start(pos: Vector2) -> bool:
	if blocked.is_valid() and bool(blocked.call()):
		return false
	return _scroll.get_global_rect().has_point(pos)

# ---------- 프레임 ----------
func _process(delta: float) -> void:
	step(delta)

## 프레임 하나를 진행한다(시험은 이것을 직접 부른다 — 진짜 프레임 없이도 관성을 잴 수 있게).
func step(delta: float) -> void:
	if delta > 0.0:
		_last_delta = delta
		_elapsed += delta
	if not active():
		if _dragging or _velocity != 0.0 or _drag_id != -1:
			stop()               # 화면이 바뀌거나 꺼졌다 — 관성을 남기지 않는다
		return
	if _dragging:
		return                   # 끌고 있는 동안에는 아무 것도 하지 않는다(속도는 뗄 때 표본으로 낸다)
	if _velocity == 0.0:
		sync()                   # 바깥이 바꾼 자리를 조용히 따라간다(보던 자리 되살리기 등)
		return
	var before := _pos
	_move_by(_velocity * _last_delta)
	if absf(_pos - before) < 0.0001:
		_velocity = 0.0          # 끝에 닿았다 — 그 자리에서 멈춘다(튕기지 않는다)
		return
	_velocity = move_toward(_velocity, 0.0, FRICTION * _last_delta)
	if absf(_velocity) <= STOP_SPEED:
		_velocity = 0.0

## 세로로 dy만큼 옮긴다. 범위를 벗어나지 않고, 화면에는 반올림한 정수만 넣는다.
func _move_by(dy: float) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	_pos = clampf(_pos + dy, 0.0, max_scroll())
	_scroll.scroll_vertical = int(round(_pos))
