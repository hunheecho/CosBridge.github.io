class_name PSave
extends RefCounted
## 저장(user://, JSON 한 파일). HTML 저장과 호환하지 않는다(PORT_BASELINE C12/C14: 새 형식, migrate 없음).
## 파일: {"schema": "prophecy_save/1", "saved_at": unix초, "run": run}. 임시 파일에 쓴 뒤 이름을 바꿔 덮어쓴다(원자성에 가깝게).
## JSON 숫자는 전부 float로 읽히므로 _normalize가 정수 필드를 int로 되돌린다(저장 전 run에도 같은 규칙을 적용하면 문자열이 일치한다).

const SCHEMA := "prophecy_save/1"
const SAVE_PATH := "user://prophecy_save_v1.json"
const TMP_PATH := "user://prophecy_save_v1.json.tmp"
const CORRUPT_PATH := "user://prophecy_save_v1.json.corrupt"
const RECORDS_PATH := "user://prophecy_records_v1.json"

## 어디에 나오든 정수인 키(값이 정수이면 int로). hp·xp·elapsed·dmg 같은 실수 필드는 두지 않는다
const INT_KEYS := {
	"version": true, "seed": true, "stage": true, "sortieCount": true, "bossRetries": true, "day": true, "hours": true, "gold": true, "forge": true,
	"encounters": true, "wins": true, "losses": true, "kills": true, "eventsResolved": true, "lastSupplyDay": true, "lastDefeatDay": true,
	"level": true, "pendingLevelUps": true, "choiceSeq": true, "seq": true, "steerFallbacks": true, "missionGoldFallbacks": true, "deepPickNone": true, "bossPickNone": true,
	"fallbackGold": true, "attempts": true, "timeCost": true, "variantSlot": true, "slot": true, "remappedFrom": true, "chestGold": true, "n": true, "count": true,
	"fromSlot": true, "servicePrice": true, "price": true, "index": true, "modCount": true, "lv": true, "cost": true, "afterBoss": true,
	"retries": true, "specialUses": true, "extraTime": true, "heal": true, "hpCost": true,
	"profileLevel": true, # 영구 성장(run.unlocks.level은 "level"로 이미 정수)
	"equipSeq": true, "plus": true, "next": true, # 장비 개체 일련번호·강화 단계(§4)
}
## 값 전체가 정수인 사전
const INT_MAPS := { "mats": true, "picks": true, "commons": true, "passives": true, "services": true, "visited": true, "missionsDone": true,
	"equipPlus": true } # 장비 개체 id → 강화 단계(§4). 개체 id를 키로 쓰므로 값만 정수로 되돌린다
## 정수 배열로 두는 키(없음 — 예비)
const FLOAT_KEYS := { "hp": true, "xp": true, "elapsed": true, "total": true, "taken": true, "takenNominal": true, "bossDamage": true, "time": true }

static func _norm_value(key: String, v: Variant, parent_key: String) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var all_int: bool = INT_MAPS.has(key)
			for k in d.keys():
				var ck := String(k)
				var cv = d[k]
				if all_int and typeof(cv) == TYPE_FLOAT and cv == floor(cv):
					d[k] = int(cv)
				else:
					d[k] = _norm_value(ck, cv, key)
			return d
		TYPE_ARRAY:
			var a: Array = v
			for i in a.size():
				a[i] = _norm_value(key, a[i], parent_key)
			return a
		TYPE_FLOAT:
			if FLOAT_KEYS.has(key):
				return v
			if INT_KEYS.has(key) and v == floor(v):
				return int(v)
			return v
	return v

## 정수 필드 정규화(제자리). 저장 전·불러온 뒤 모두 적용해 JSON 문자열이 같아지게 한다
static func _normalize(run: Dictionary) -> Dictionary:
	_norm_value("", run, "")
	# 값이 비어도 형식을 보장하는 필드
	if run.get("stock", null) != null and (run.stock as Dictionary).get("skill", null) != null:
		run.stock.skill.price = int(run.stock.skill.price)
	if run.has("hp"):
		run.hp = float(run.hp)
	return run

static func normalize(run: Dictionary) -> Dictionary:
	return _normalize(run)

## 저장: 임시 파일에 쓴 뒤 본 파일 위로 이름 변경. 성공 여부
## **사람의 저장을 시험이 덮어쓰지 못하게 하는 관문**(2026-09-10 사고 뒤 추가).
##
## 무슨 일이 있었나: 검사 스크립트를 **창을 띄운 채 APPDATA 격리 없이** 돌렸다. 그 스크립트가
## PSave.clear() 뒤 새 회차를 저장해 **사람이 진행하던 회차 저장이 시험 자료로 덮여 사라졌다.**
## 되돌릴 방법이 없었다(원본을 지운 뒤 새로 썼다).
##
## 그래서 규칙 계층에 관문을 둔다. `PROPHECY_TEST=1`이 켜져 있는데 user:// 가 **격리된 자리가
## 아니면** 쓰기를 거부한다. 격리 표시는 경로에 `userdata__` 또는 `prophecy_test_runs`가 들어 있는 것
## (공용 실행기 tools/run_suites.py가 그렇게 만든다).
## 검사·도구는 이 값을 켜고 돌린다 → 격리를 깜빡하면 저장이 안 되고 경고가 남는다.
## 사람이 하는 실제 게임은 이 값이 없으므로 아무 영향이 없다.
## 지금 돌고 있는 것이 **검사·도구 스크립트**인가. `-s tests/…` 또는 `-s tools/…` 로 판별한다.
## 환경 변수에만 기대면 사고를 못 막는다 — 실제 사고 때 그 변수는 없었고, 창을 띄운 채
## `-s tests/bank_ui_tests.gd` 로 돌렸을 뿐이다. 실행 인자는 그 경우에도 반드시 남는다
static func running_test_script() -> bool:
	if OS.get_environment("PROPHECY_TEST") == "1":
		return true
	for a in OS.get_cmdline_args():
		var t := String(a).replace("\\", "/")
		if t.begins_with("tests/") or t.begins_with("tools/") or t.find("/tests/") >= 0 or t.find("/tools/") >= 0:
			return true
	return false

static func write_blocked() -> String:
	if not running_test_script():
		return ""
	var dir := ProjectSettings.globalize_path("user://")
	if dir.find("userdata__") >= 0 or dir.find("prophecy_test_runs") >= 0:
		return ""
	return "검사·도구 스크립트인데 저장 자리가 격리돼 있지 않다: " + dir

static func save(run: Dictionary) -> bool:
	var blocked := write_blocked()
	if blocked != "":
		push_error("저장 거부 — " + blocked + " · 사람의 저장을 덮어쓰지 않으려고 막았다(PSave.write_blocked)")
		return false
	var doc := { "schema": SCHEMA, "saved_at": int(Time.get_unix_time_from_system()), "run": _normalize(run) }
	var txt := JSON.stringify(doc)
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("저장 실패(열기): " + TMP_PATH)
		return false
	f.store_string(txt)
	f.close()
	var d := DirAccess.open("user://")
	if d == null:
		push_error("저장 실패(user://)")
		return false
	if d.file_exists(SAVE_PATH.get_file()):
		d.remove(SAVE_PATH.get_file())
	var err := d.rename(TMP_PATH.get_file(), SAVE_PATH.get_file())
	if err != OK:
		push_error("저장 실패(이름 변경): %d" % err)
		return false
	return true

static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## 불러오기: 없거나 깨졌으면 {} (깨진 파일은 .corrupt로 이름 변경)
static func load() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY or String(parsed.get("schema", "")) != SCHEMA or typeof(parsed.get("run", null)) != TYPE_DICTIONARY:
		push_error("저장 파일 형식 불일치 → .corrupt로 보관")
		var d := DirAccess.open("user://")
		if d != null:
			if d.file_exists(CORRUPT_PATH.get_file()):
				d.remove(CORRUPT_PATH.get_file())
			d.rename(SAVE_PATH.get_file(), CORRUPT_PATH.get_file())
		return {}
	var run := _normalize(parsed.run)
	_drop_unknown_equipment(run)
	return run

## **자료에 없는 장비를 불러올 때 걸러낸다.**
##
## 왜: 장비는 id 문자열로 저장된다. 그 id가 지금 자료에 없으면(시험용 장비가 든 저장, 판이 바뀌며
## 사라진 장비, 손으로 고친 저장) PCatalog.equipment_def가 빈 사전을 돌려주고, 그것을 받은 쪽이
## `.slot`을 읽다 **게임이 죽는다.** 실제로 그런 저장이 만들어진 적이 있다(2026-09-10).
##
## 사람의 장비를 함부로 버리지 않는다 — **지금 자료에 아예 없는 것만** 뺀다. 폐기 표시(retired)가
## 붙은 장비는 자료에 그대로 있으므로 여기서 걸리지 않는다(기존 저장 보존).
## 무엇을 뺐는지는 기록으로 남겨 조용히 사라지지 않게 한다.
static func _drop_unknown_equipment(run: Dictionary) -> void:
	if run.is_empty():
		return
	var dropped: Array = []
	var eq: Dictionary = run.get("equipment", {})
	for slot in eq.keys():
		var uid = eq[slot]
		if uid == null:
			continue
		if PCatalog.equipment_known(PRun.equip_type_of(String(uid))):
			continue
		dropped.append(String(uid))
		eq[slot] = null
	var bag: Array = run.get("bag", [])
	var keep: Array = []
	for uid in bag:
		if PCatalog.equipment_known(PRun.equip_type_of(String(uid))):
			keep.append(uid)
		else:
			dropped.append(String(uid))
	if keep.size() != bag.size():
		run["bag"] = keep
	if dropped.is_empty():
		return
	push_warning("저장에 없는 장비가 들어 있어 뺐다(게임을 멈추지 않으려고): " + str(dropped))
	var log: Array = run.get("log", [])
	log.append("자료에 없는 장비 %d개를 정리했다: %s" % [dropped.size(), ", ".join(dropped)])
	run["log"] = log

static func clear() -> void:
	# 지우기도 같은 관문을 지난다. 사고를 낸 스크립트는 clear() 뒤 새 회차를 저장했다 —
	# 지우기만 막아도, 저장만 막아도 반쪽이라 둘 다 막는다
	var blocked := write_blocked()
	if blocked != "":
		push_error("저장 지우기 거부 — " + blocked + " · 사람의 저장을 지우지 않으려고 막았다")
		return
	var d := DirAccess.open("user://")
	if d == null:
		return
	if d.file_exists(SAVE_PATH.get_file()):
		d.remove(SAVE_PATH.get_file())
	if d.file_exists(TMP_PATH.get_file()):
		d.remove(TMP_PATH.get_file())

# ---------- 처치 기록(회차와 별도, 새 회차로 삭제되지 않음) ----------
static func load_records() -> Dictionary:
	var empty := { "first_clear": null, "clears": [] }
	if not FileAccess.file_exists(RECORDS_PATH):
		return empty
	var f := FileAccess.open(RECORDS_PATH, FileAccess.READ)
	if f == null:
		return empty
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("clears"):
		return empty
	_norm_value("", parsed, "")
	return parsed

## 기록 추가(첫 완주는 first_clear, clears는 최대 20개). 갱신된 기록을 돌려준다
static func save_record(rec: Dictionary) -> Dictionary:
	var R := load_records()
	if R.get("first_clear", null) == null:
		R.first_clear = rec
	(R.clears as Array).append(rec)
	while (R.clears as Array).size() > 20:
		(R.clears as Array).remove_at(0)
	var f := FileAccess.open(RECORDS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(R))
		f.close()
	return R
