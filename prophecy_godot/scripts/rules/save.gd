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
}
## 값 전체가 정수인 사전
const INT_MAPS := { "mats": true, "picks": true, "commons": true, "passives": true, "services": true, "visited": true, "missionsDone": true }
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
static func save(run: Dictionary) -> bool:
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
	return _normalize(parsed.run)

static func clear() -> void:
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
