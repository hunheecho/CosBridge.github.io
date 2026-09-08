class_name PSubset
extends RefCounted
## 측정 도구의 **부분 실행**. 큰 비교를 통째로 돌리기 전에 바꾼 시나리오만 작게 확인하고,
## 필요한 범위만 넓히기 위한 공통 도구다(2026-09-08 사용자 지시).
##
## 환경 변수(모두 선택):
##   PROPHECY_QUICK=1                  각 축의 대표값 하나씩만 돌린다(가장 작은 실행)
##   PROPHECY_ONLY=<축>:<값>[,<값>...] 그 축에서 이 값들만 돌린다. 여러 축은 `;`로 잇는다
##                                     예) PROPHECY_ONLY="skill:sword,ember;day:9"
##   PROPHECY_SKIP=<축>:<값>[,...]     그 축에서 이 값들을 뺀다(ONLY보다 나중에 적용)
##   PROPHECY_LIMIT=<n>                전체 조합 수 상한(초과하면 그만 돈다)
##
## 축 이름은 도구마다 다르다. 각 도구의 머리말에 적혀 있다.
## 부분 실행으로 만든 보고서에는 **어떤 범위로 돌렸는지**가 함께 적힌다 — 전체 실행 결과와 섞지 않기 위해서다.

var only: Dictionary = {}      # 축 → { 값: true }
var skip: Dictionary = {}
var quick: bool = false
var limit: int = 0
var used: int = 0

func _init() -> void:
	quick = OS.get_environment("PROPHECY_QUICK") != ""
	limit = int(OS.get_environment("PROPHECY_LIMIT")) if OS.get_environment("PROPHECY_LIMIT") != "" else 0
	only = _parse(OS.get_environment("PROPHECY_ONLY"))
	skip = _parse(OS.get_environment("PROPHECY_SKIP"))

static func _parse(raw: String) -> Dictionary:
	var out := {}
	if raw == "":
		return out
	for part in raw.split(";", false):
		var kv := String(part).split(":", false, 1)
		if kv.size() != 2:
			continue
		var vals := {}
		for v in String(kv[1]).split(",", false):
			vals[String(v).strip_edges()] = true
		out[String(kv[0]).strip_edges()] = vals
	return out

## 이 축의 이 값을 돌릴 것인가
func keep(axis: String, value) -> bool:
	var v := str(value)
	if only.has(axis) and not (only[axis] as Dictionary).has(v):
		return false
	if skip.has(axis) and (skip[axis] as Dictionary).has(v):
		return false
	return true

## 축의 값 목록을 부분 실행 조건에 맞게 줄인다. quick이면 남은 것 중 첫 하나만
func pick(axis: String, values: Array) -> Array:
	var out := []
	for v in values:
		if keep(axis, v):
			out.append(v)
	if out.is_empty():
		out = values.duplicate()   # 조건이 아무것도 남기지 않으면 원래대로(빈 실행 방지)
	if quick and out.size() > 1:
		out = [out[0]]
	return out

## 조합 상한. 더 돌려도 되면 true
func more() -> bool:
	if limit <= 0:
		return true
	used += 1
	return used <= limit

## 보고서 머리에 적을 실행 범위 한 줄
func describe(full: bool) -> String:
	if full:
		return "전체 실행(부분 실행 조건 없음)."
	var bits := []
	if quick:
		bits.append("PROPHECY_QUICK=1(축마다 대표값 하나)")
	for a in only:
		bits.append("only %s=%s" % [a, ",".join((only[a] as Dictionary).keys())])
	for a in skip:
		bits.append("skip %s=%s" % [a, ",".join((skip[a] as Dictionary).keys())])
	if limit > 0:
		bits.append("조합 상한 %d" % limit)
	return "**부분 실행**: " + " · ".join(bits) + ". 전체 실행 결과와 같은 표로 취급하지 않는다."

## 부분 실행 조건이 하나라도 있는가
func partial() -> bool:
	return quick or not only.is_empty() or not skip.is_empty() or limit > 0
