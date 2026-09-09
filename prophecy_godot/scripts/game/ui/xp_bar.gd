class_name PXpBar
extends Control
## 레벨 + 경험치 진행 막대(표시 전용, §14). 전투 최상단(체력바 바로 옆)과 거점 '현재 빌드'가 **같은 것**을 쓴다.
##
## 규칙
##  - 색: 체력은 빨강, 경험치는 **파랑**. 보호막(연한 하늘색)과도 갈리도록 더 진한 파랑을 쓴다.
##  - 숫자(경험치 x/y)는 데스크톱에서만 적는다. 모바일(터치)은 **레벨과 막대**를 크게 두고 숫자를 뺀다.
##  - 막대는 부드럽게 차오르고, 레벨이 오르는 순간에만 **짧게** 테두리를 밝힌다(계속 깜박이지 않는다).
##  - **글자는 언제나 실제 값이다.** 애니메이션은 채움 비율에만 있고, 레벨이 바뀌면 즉시 실제 값으로 맞춘다
##    (여러 레벨이 한 번에 올라도, 성장 3택·일시정지·저장 복구로 값이 튀어도 화면 숫자가 어긋나지 않는다).
##  - 하단에 따로 경험치바를 만들지 않는다 — 이 하나만 쓴다.

const FILL := Color(0.26, 0.55, 0.98, 0.96)      # 경험치(파랑)
const BACK := Color(0.06, 0.09, 0.17, 0.92)
const EDGE := Color(0.33, 0.46, 0.74, 0.90)
const LEVEL_FG := Color(1.0, 1.0, 1.0, 0.98)
const NUM_FG := Color(0.80, 0.88, 1.0, 0.97)
const PEND_FG := Color(1.0, 0.88, 0.40, 1.0)     # 미처리 레벨업(선택이 남아 있다)
const FLASH_FG := Color(1.0, 0.94, 0.55, 1.0)    # 레벨업 순간의 짧은 강조
const FLASH_SEC := 0.7                            # 강조가 사라지기까지(초)
const APPROACH := 7.0                             # 채움이 실제 값에 다가가는 속도(초당)
const SNAP_EPS := 0.004                           # 이만큼 가까우면 딱 붙인다(영원히 미세하게 움직이지 않게)
const BAR_H := 26.0                               # 전투 상단 띠에서 체력 막대와 같은 높이

var level := 1
var xp := 0.0
var need := 1.0
var pending := 0
var compact := false        # true = 모바일: 숫자 생략, 레벨·막대 우선
var bar_h := BAR_H
var level_fs := 15
var num_fs := 11

var _shown := 0.0           # 지금 그려지는 채움 비율(0~1). 실제 값으로 부드럽게 따라간다
var _flash_left := 0.0      # 레벨업 강조 남은 시간(초)
var _init_done := false     # 처음 값은 애니메이션 없이 그대로 그린다(화면을 열자마자 0에서 차오르지 않게)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

## 실제 값 넣기. 레벨이 바뀌면(레벨업·여러 레벨 한 번에·저장 복구·새 회차) 채움을 즉시 실제 값으로 맞춘다.
## gained_level = 방금 올랐는가(강조를 켤지). 값만 다시 넣는 경우(복구·재구성)에는 강조하지 않는다.
func set_values(p_level: int, p_xp: float, p_need: float, p_pending: int = 0) -> void:
	var lv_changed: bool = p_level != level
	var leveled_up: bool = p_level > level and _init_done
	level = p_level
	xp = maxf(0.0, p_xp)
	need = maxf(1.0, p_need)
	pending = maxi(0, p_pending)
	if not _init_done or lv_changed:
		_shown = ratio()     # 레벨이 바뀌면 새 레벨의 실제 지점에서 다시 시작한다(옛 레벨 막대가 남지 않게)
		_init_done = true
	if leveled_up:
		_flash_left = FLASH_SEC
	queue_redraw()

## 실제 값이 만드는 채움 비율(0~1). 시험이 화면 값과 규칙 값을 대조하는 창구다
func ratio() -> float:
	return clampf(xp / maxf(1.0, need), 0.0, 1.0)

## 지금 그려지고 있는 채움 비율(애니메이션 중이면 ratio()와 잠시 다르다)
func shown_ratio() -> float:
	return _shown

## 애니메이션을 건너뛰고 실제 값에 붙인다(일시정지·화면 재구성·저장 복구·시험)
func snap() -> void:
	_shown = ratio()
	queue_redraw()

func flashing() -> bool:
	return _flash_left > 0.0

## 화면에 적히는 글(시험·보고용). 언제나 실제 값이다
func text_line() -> String:
	return "Lv %d" % level if compact else "Lv %d  %d / %d" % [level, int(floor(xp)), int(need)]

func _process(delta: float) -> void:
	var target := ratio()
	var moved := false
	if not is_equal_approx(_shown, target):
		if absf(target - _shown) <= SNAP_EPS:
			_shown = target
		else:
			_shown += (target - _shown) * clampf(delta * APPROACH, 0.0, 1.0)
		moved = true
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		moved = true
	if moved:
		queue_redraw()

func _draw() -> void:
	var w: float = size.x
	if w <= 2.0:
		return
	var h: float = minf(bar_h, maxf(8.0, size.y))
	PRender.rrect(self, 0.0, 0.0, w, h, 5.0, BACK)
	var k: float = clampf(_shown, 0.0, 1.0)
	if k > 0.0:
		PRender.rrect(self, 0.0, 0.0, maxf(3.0, w * k), h, 5.0, FILL)
	draw_rect(Rect2(0.0, 0.0, w, h), EDGE, false, 1.0)
	if _flash_left > 0.0:
		# 레벨업: 테두리만 짧게 밝힌다(막대 색을 바꾸지 않는다 — 체력과 헷갈리지 않게)
		var a: float = clampf(_flash_left / FLASH_SEC, 0.0, 1.0)
		draw_rect(Rect2(-1.0, -1.0, w + 2.0, h + 2.0), Color(FLASH_FG.r, FLASH_FG.g, FLASH_FG.b, a), false, 2.0)
	var base_y: float = h - maxf(5.0, h * 0.26)
	var lv_txt := "Lv %d" % level
	PRender.txt(self, 7.0, base_y, lv_txt, level_fs, LEVEL_FG, -1, true)
	if pending > 0:
		# 아직 고르지 않은 레벨업이 남아 있다(막대만 보고 '다 끝났다'고 읽지 않게)
		var lw: float = PRender.font().get_string_size(lv_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, level_fs).x
		PRender.txt(self, 7.0 + lw + 5.0, base_y, "+%d" % pending, num_fs, PEND_FG, -1, true)
	if not compact:
		# 데스크톱: 레벨과 경험치 수치를 함께 적는다. 모바일은 레벨·막대를 크게 두려고 숫자를 뺀다
		PRender.txt(self, w - 7.0, base_y, "%d / %d" % [int(floor(xp)), int(need)], num_fs, NUM_FG, 1, true)
