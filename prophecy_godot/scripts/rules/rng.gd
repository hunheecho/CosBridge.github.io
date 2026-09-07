class_name PRng
extends RefCounted
## mulberry32 — HTML(PA.rng)과 같은 알고리즘·같은 소비 순서. 32비트 부호 없는 정수 연산으로 재현한다.

const MASK := 0xFFFFFFFF
var _a: int

func _init(seed_value: int) -> void:
	_a = seed_value & MASK
	if _a == 0:
		_a = 1

static func _imul(x: int, y: int) -> int:
	return (x * y) & MASK

func next() -> float:
	_a = (_a + 0x6D2B79F5) & MASK
	var t := _imul(_a ^ (_a >> 15), 1 | _a)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) ^ t) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next()

func int_range(lo: int, hi: int) -> int:
	return lo + int(floor(next() * float(hi - lo + 1)))
