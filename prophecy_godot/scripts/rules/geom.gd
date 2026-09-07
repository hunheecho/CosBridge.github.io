class_name PGeom
extends RefCounted
## 판정 기하(HTML PA.m 이식). 좌표는 double(float) 쌍으로 다룬다(Vector2는 32비트라 재현 비교에 쓰지 않는다).

static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))

static func norm(x: float, y: float) -> Array:
	var l := sqrt(x * x + y * y)
	if l > 1e-9:
		return [x / l, y / l]
	return [0.0, 0.0]

static func ang_diff(a: float, b: float) -> float:
	var d := b - a
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	return d

## 점 p(반지름 pr)가 원(c, r)과 각도 ang 중심, 반각 half의 부채꼴 안에 있는가
static func in_arc(cx: float, cy: float, r: float, ang: float, half: float, px: float, py: float, pr: float) -> bool:
	var d := dist(cx, cy, px, py)
	if d > r + pr:
		return false
	if d <= pr:
		return true
	var a := atan2(py - cy, px - cx)
	var dd := absf(ang_diff(ang, a))
	var extra := asin(minf(1.0, pr / maxf(d, 1e-6)))
	return dd <= half + extra

## 선분 (x0,y0)->(x1,y1)이 원(cx,cy,r)에 처음 닿는 t(0..1). 시작점이 안이면 0. 안 닿으면 -1
static func seg_circle_t(x0: float, y0: float, x1: float, y1: float, cx: float, cy: float, r: float) -> float:
	var fx := x0 - cx
	var fy := y0 - cy
	if fx * fx + fy * fy <= r * r:
		return 0.0
	var dx := x1 - x0
	var dy := y1 - y0
	var a := dx * dx + dy * dy
	if a < 1e-12:
		return -1.0
	var b := 2.0 * (fx * dx + fy * dy)
	var cc := fx * fx + fy * fy - r * r
	var disc := b * b - 4.0 * a * cc
	if disc < 0.0:
		return -1.0
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t >= 0.0 and t <= 1.0:
		return t
	return -1.0

## 선분과 원 교차(스윕 물기 판정)
static func seg_circle(x0: float, y0: float, x1: float, y1: float, cx: float, cy: float, r: float) -> bool:
	var dx := x1 - x0
	var dy := y1 - y0
	var l2 := dx * dx + dy * dy
	var t := 0.0
	if l2 > 1e-9:
		t = clampf(((cx - x0) * dx + (cy - y0) * dy) / l2, 0.0, 1.0)
	var px := x0 + dx * t
	var py := y0 + dy * t
	return dist(cx, cy, px, py) <= r
