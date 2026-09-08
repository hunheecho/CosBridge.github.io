class_name PSubset
extends RefCounted
## 측정 도구의 **부분 실행**(축 줄이기) 도우미.
##
## 왜 있는가
## ---------
## 큰 측정을 통째로 돌리면 한 번에 수십 분이 든다. 바꾼 것이 맞는지 보려고 전체를 돌리는 것은 낭비이고,
## 더 나쁜 것은 **작게 돌린 결과가 전체 결과처럼 보고서에 남는 일**이다. 이 도구는 두 가지를 한다.
##   ① 축(정예 종류·막·시드…)을 환경 변수로 줄여 준다.
##   ② 줄여서 돌렸다는 사실을 보고서 머리(describe)와 파일 이름(out_path의 `_PARTIAL.md`)에 남긴다.
##
## 쓰는 법
## -------
##     var sub := PSubset.new()
##     var elites := sub.pick("elite", PEnemiesNew.ELITE_TYPES)   # 축을 줄인다
##     var acts   := sub.pick("act", [2, 3])
##     print(sub.describe("정예 배치 측정"))                       # 보고서 머리(무엇을 줄였는지)
##     var path   := sub.out_path("res://docs/sim/X.md")          # 부분이면 X_PARTIAL.md
##
## 환경 변수
## ---------
##     PROPHECY_SUBSET="elite=elite_fang,elite_archer;act=3;seed=1"
##   - 축 이름은 pick()에 준 이름과 같다. 세미콜론으로 축을 나누고 쉼표로 값을 나눈다.
##   - 지정하지 않은 축은 줄이지 않는다.
##   - 목록에 없는 값을 적으면 무시하고 unknown에 남긴다. 남는 값이 하나도 없으면 **전체를 쓴다**
##     (조용히 0회 실행하고 "통과"로 보이는 것을 막는다).
##   - 값 비교는 문자열로 한다(정수 축도 "3"으로 적으면 된다).

const ENV := "PROPHECY_SUBSET"

var _spec: Dictionary = {}      # 축 → [문자열 값]
var _applied: Dictionary = {}   # 축 → { "kept": 남은 수, "all": 전체 수 }
var _unknown: Array = []        # 목록에 없어 무시한 "축=값"
var _ignored: Array = []        # 남는 값이 없어 전체로 되돌린 축

func _init(spec_text: String = "") -> void:
	var raw := spec_text if spec_text != "" else OS.get_environment(ENV)
	for part in raw.split(";", false):
		var kv: PackedStringArray = String(part).split("=", false)
		if kv.size() != 2:
			continue
		var axis := String(kv[0]).strip_edges()
		var vals := []
		for v in String(kv[1]).split(",", false):
			var s := String(v).strip_edges()
			if s != "":
				vals.append(s)
		if axis != "" and not vals.is_empty():
			_spec[axis] = vals

## 이 축에서 실제로 돌릴 값 목록. 환경 변수에 그 축이 없으면 values를 그대로 돌려준다.
func pick(axis: String, values: Array) -> Array:
	if not _spec.has(axis):
		return values
	var want: Array = _spec[axis]
	var out := []
	var seen := {}
	for v in values:
		if want.has(str(v)):
			out.append(v)
			seen[str(v)] = true
	for w in want:
		if not seen.has(String(w)):
			_unknown.append("%s=%s" % [axis, String(w)])
	if out.is_empty(): # 실수로 0회 실행하지 않는다
		_ignored.append(axis)
		return values
	_applied[axis] = { "kept": out.size(), "all": values.size() }
	return out

## 하나라도 실제로 줄었는가
func partial() -> bool:
	for a in _applied:
		if int(_applied[a].kept) < int(_applied[a].all):
			return true
	return false

## 사람이 읽는 한 줄(줄인 축과 남은 수). 전체 실행이면 그렇다고 말한다
func summary() -> String:
	if not partial():
		return "전체 실행(축을 줄이지 않았다)"
	var parts := []
	for a in _applied:
		parts.append("%s %d/%d" % [String(a), int(_applied[a].kept), int(_applied[a].all)])
	return "부분 실행 — " + " · ".join(parts)

## 보고서 머리(제목 + 부분 실행 경고). 큰 표가 전체 결과로 오해되지 않게 맨 위에 넣는다
func describe(title: String) -> String:
	var lines := []
	lines.append("# %s%s" % [title, " (부분 실행)" if partial() else ""])
	lines.append("")
	lines.append("- 실행 범위: **%s**" % summary())
	if partial():
		lines.append("- **이 표는 전체 결과가 아니다.** 줄인 축 밖의 값은 이번에 재지 않았다. 전체는 `%s` 없이 다시 돌려라." % ENV)
	if not _unknown.is_empty():
		lines.append("- 목록에 없어 무시한 지정: %s" % ", ".join(_unknown))
	if not _ignored.is_empty():
		lines.append("- 남는 값이 없어 **전체로 되돌린** 축: %s" % ", ".join(_ignored))
	lines.append("")
	return "\n".join(lines)

## 결과 파일 경로. 부분 실행이면 확장자 앞에 _PARTIAL을 붙여 전체 결과 파일을 덮어쓰지 않는다
func out_path(path: String) -> String:
	if not partial():
		return path
	var dot := path.rfind(".")
	if dot < 0:
		return path + "_PARTIAL"
	return path.substr(0, dot) + "_PARTIAL" + path.substr(dot)

## 지금 적용된 지정(기록·검사용)
func spec() -> Dictionary:
	return _spec.duplicate(true)
