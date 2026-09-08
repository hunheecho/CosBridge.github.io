class_name PSubset
extends RefCounted
## 부분 실행(축 줄이기). 큰 측정을 돌리기 전에 **작게 먼저 확인**하기 위한 공용 도우미다.
## 측정 도구·검사 스위트가 축(시드·전장 …)을 여기에 등록하면, 환경 변수로 축을 잘라 준다.
## 하나라도 잘리면 partial = true가 되고, 보고서는 원래 파일 대신 `..._PARTIAL.md`에 쓴다.
## (부분 결과가 전체 결과 파일을 덮어써서 나중에 전체 측정처럼 읽히는 일을 막는다.)
##
## 환경 변수
##  PROPHECY_SUBSET=<n>            모든 축을 앞에서 n개만 남긴다(예: 2 → 시드 2개·전장 2곳)
##  PROPHECY_AXIS_<축이름>=a,b,c    그 축의 값을 직접 지정한다(축 이름 대문자, 예 PROPHECY_AXIS_SEEDS=1,7)
##  PROPHECY_SEEDS / PROPHECY_ARENAS  자주 쓰는 두 축의 짧은 이름(위와 같은 뜻)
##
## 쓰는 법
##  var sub := PSubset.new({ "seeds": [1,2,3,4], "arenas": ["clearing","pillars"] })
##  for s in sub.axis("seeds"): ...
##  print(sub.describe("랜덤 지형 측정"))
##  var path := sub.out_path("res://docs/TERRAIN_REPORT.md")

var full: Dictionary = {}     # 축 이름 → 전체 값 목록
var used: Dictionary = {}     # 축 이름 → 이번 실행에서 쓸 값 목록
var partial := false          # 하나라도 줄었는가
var cuts: Array = []          # 어떻게 줄였는지(보고서 머리에 그대로 적는다)

func _init(axes: Dictionary) -> void:
	full = axes.duplicate(true)
	var n := int(OS.get_environment("PROPHECY_SUBSET"))
	for name in axes:
		var all: Array = axes[name]
		var vals: Array = all.duplicate()
		var env := _env_for(String(name))
		if env != "":
			vals = _parse(env, all)
			cuts.append("%s=%s" % [String(name), _join(vals)])
		elif n > 0 and vals.size() > n:
			vals = vals.slice(0, n)
			cuts.append("%s 앞 %d개" % [String(name), n])
		used[name] = vals
		if vals.size() != all.size():
			partial = true

## 이번 실행에서 쓸 축 값
func axis(name: String) -> Array:
	return used.get(name, [])

func count(name: String) -> int:
	return (used.get(name, []) as Array).size()

## 보고서 머리에 넣는 한 줄. 전체 실행인지 부분 실행인지와 축 크기를 그대로 적는다
func describe(title: String) -> String:
	var parts := []
	for name in full:
		parts.append("%s %d/%d" % [String(name), (used[name] as Array).size(), (full[name] as Array).size()])
	var head := "부분 실행" if partial else "전체 실행"
	var tail := (" · 자른 방식: " + ", ".join(PackedStringArray(cuts))) if not cuts.is_empty() else ""
	return "%s — %s (%s)%s" % [title, head, ", ".join(PackedStringArray(parts)), tail]

## 부분 실행이면 파일 이름에 _PARTIAL을 붙여 전체 결과 파일을 덮어쓰지 않는다
func out_path(base: String) -> String:
	if not partial:
		return base
	var dot := base.rfind(".")
	if dot < 0:
		return base + "_PARTIAL"
	return base.substr(0, dot) + "_PARTIAL" + base.substr(dot)

# ---------- 내부 ----------
func _env_for(name: String) -> String:
	var up := name.to_upper()
	var v := OS.get_environment("PROPHECY_AXIS_" + up)
	if v != "":
		return v
	return OS.get_environment("PROPHECY_" + up)

## 전체 목록의 첫 값 형에 맞춰 문자열을 값으로 바꾼다(정수·실수·문자열)
func _parse(text: String, template: Array) -> Array:
	var kind := TYPE_STRING
	if not template.is_empty():
		kind = typeof(template[0])
	var out := []
	for s in text.split(",", false):
		var t := String(s).strip_edges()
		if t == "":
			continue
		if kind == TYPE_INT:
			out.append(int(t))
		elif kind == TYPE_FLOAT:
			out.append(float(t))
		else:
			out.append(t)
	return out

func _join(vals: Array) -> String:
	var out := []
	for v in vals:
		out.append(str(v))
	return ",".join(PackedStringArray(out))
