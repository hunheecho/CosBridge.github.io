class_name PSave
extends RefCounted
## 저장(user://, JSON 한 파일). HTML 저장과 호환하지 않는다(PORT_BASELINE C12/C14: 새 형식, migrate 없음).
## 파일: {"schema": "prophecy_save/1", "saved_at": unix초, "run": run}. 임시 파일에 쓴 뒤 이름을 바꿔 덮어쓴다(원자성에 가깝게).
## JSON 숫자는 전부 float로 읽히므로 _normalize가 정수 필드를 int로 되돌린다(저장 전 run에도 같은 규칙을 적용하면 문자열이 일치한다).

const SCHEMA := "prophecy_save/1"

## ---------- 회차 판본(run_version) ----------
## **schema 와 다른 것을 가리킨다.**
##   schema      : 파일의 겉모양(키 구성 {schema, saved_at, run_version, run}).
##   run_version : 그 안에 담긴 **회차 규칙의 판**.
##
## 왜 나눠 뒀나 — schema 를 올리면 아래 load() 가 파일을 **.corrupt 로 이름을 바꿔 밀어낸다.**
## 그 길은 사람의 저장을 옆으로 치우는 동작이고, 화면은 "저장이 깨졌다"와 "판이 바뀌었다"를
## 구분하지 못한다. 그래서 겉모양은 그대로 두고 판본만 따로 적는다.
## **판이 다른 저장 파일은 지우지도, 이름을 바꾸지도 않는다** — 그대로 둔다.
## 사람이 새 회차를 시작하면 그때 정상 경로로 덮인다.
##
## 판별을 **판본으로만** 한다는 것도 여기에 못 박는다.
## "자료에 없는 장비가 들어 있으니 옛 회차겠지" 같은 짐작으로 가르지 않는다 —
## 시험용 장비가 든 새 판본 저장은 예전처럼 정리하고 **그대로 이어할 수 있어야 한다**
## (tests/save_version_tests.gd 가 값으로 확인한다).
##
## 판본 이력
##   1 — 판본을 적기 전의 모든 파일. run_version 이 **없으면 1로 본다.**
##   2 — 2026-09-10 대규모 개편. 장비가 개체(`<종류>#N`)와 강화 단계(run.equipPlus)로 바뀌고,
##       수동 기술 창고(growth.bank)와 장비 기술(eq_*)이 들어왔다.
##       사용자 확정: **이전 회차의 장비·패시브를 새 규칙으로 이전하지 않는다.**
##       그래서 판본 1 회차는 이어할 수 없다(프로필·도전과제·처치 기록·설정은 그대로 산다).
const RUN_VERSION := 2
const LEGACY_RUN_VERSION := 1

## load_result().status 가 가지는 값. 지금까지 {} 하나로 뭉뚱그리던 것을 셋으로 가른다
const LOAD_OK := "ok"                 ## 정상 — run 에 회차가 들어 있다
const LOAD_NONE := "none"             ## 저장이 없다(또는 읽지 못했다)
const LOAD_VERSION := "version"       ## 판 불일치 — 이어하기 불가. **파일은 그대로 둔다**
const LOAD_BROKEN := "broken"         ## 파일이 깨졌다(겉모양 자체가 아니다) — 예전처럼 .corrupt 로 보관

## 판이 다를 때 화면에 그대로 내보내는 문구(정본 한 자리)
const VERSION_MESSAGE := "대규모 업데이트로 새 회차를 시작해야 합니다"

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
	# **여기서 전투 상태를 건드리지 않는다.** 이 함수는 제자리 수정이고 저장·불러오기 양쪽이 부른다.
	# 여기에 run["inCombat"] = false 를 두었더니 **진행 중인 회차의 전투 잠금이 풀렸다** —
	# 전투 시작 체크포인트를 저장하는 순간 원본 회차가 열려 버렸다(2026-09-10 지적).
	# 정규화는 형식(정수·실수)만 만지고, 전투 표시는 _for_file / load 가 각자 맡는다.
	return run

static func normalize(run: Dictionary) -> Dictionary:
	return _normalize(run)

## 파일에 담을 회차. **원본을 건드리지 않는 깊은 사본**이다.
##
## 왜 사본인가 — 전투 시작 직후 체크포인트를 저장한다. 그때 원본에 손을 대면
## **진행 중인 전투의 편성 잠금이 그 자리에서 풀린다.** 실제로 그렇게 만들었다가 지적받았다.
## 저장은 읽어서 쓰는 일이지 회차를 바꾸는 일이 아니다.
##
## 전투 표시를 파일에서 내리는 이유는 그대로다(KD-13): 이어하기는 언제나 거점부터이고,
## 표시가 실려 나가면 돌아온 사람의 편성이 영영 잠긴다.
static func _for_file(run: Dictionary) -> Dictionary:
	var copy: Dictionary = run.duplicate(true)
	copy["inCombat"] = false
	return copy

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
	# **자료가 안 섰으면 저장하지 않는다.** 그 상태의 회차는 장비·무기가 비어 있어
	# 그대로 쓰면 멀쩡한 저장을 망가진 것으로 덮어쓴다(사용자 지시: 기존 저장 보존).
	if not PCatalog.data_ready():
		return "게임 자료가 서 있지 않다 — 불완전한 회차로 저장을 덮어쓰지 않는다"
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
	_normalize(run) # 형식 정규화는 예전 그대로 원본에도 적용한다(정수·실수 자리만 만진다)
	# run_version 은 **doc 맨 위**에 적는다(run 안이 아니다). 회차 사전을 건드리지 않으므로
	# 저장 전후로 run 을 통째로 비교하는 기존 검사들이 그대로 성립한다.
	var doc := { "schema": SCHEMA, "saved_at": int(Time.get_unix_time_from_system()),
		"run_version": RUN_VERSION, "run": _for_file(run) }
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

## 불러온 파일의 회차 판본. run_version 이 없으면 **판본 1**(적기 전의 파일)로 본다
static func file_run_version(doc: Dictionary) -> int:
	var v = doc.get("run_version", null)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return int(v)
	return LEGACY_RUN_VERSION

## 불러오기 — **결과를 셋(넷)으로 갈라서** 돌려준다.
##   { status, run, file_version, current_version, message }
##
## 왜 갈랐나: 예전에는 없음·깨짐·판 불일치가 전부 {} 하나였다. 그래서 화면이
## "저장이 없다"밖에 말하지 못했고, 판이 바뀌어 못 이어하는 사람에게 사유를 보여 줄 수 없었다.
##
## **판 불일치일 때 파일에 손대지 않는다.** 지우지도, .corrupt 로 옮기지도 않는다.
## 사람이 새 회차를 시작하면 그때 정상 경로(save)로 덮인다.
## .corrupt 보관은 **정말로 겉모양이 깨진 파일**에만 남겨 둔다(예전 동작 그대로).
static func load_result() -> Dictionary:
	var out := { "status": LOAD_NONE, "run": {}, "file_version": 0,
		"current_version": RUN_VERSION, "message": "" }
	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return out
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
		out["status"] = LOAD_BROKEN
		out["message"] = "저장 파일을 읽을 수 없습니다"
		return out
	var doc: Dictionary = parsed
	var fv := file_run_version(doc)
	out["file_version"] = fv
	if fv != RUN_VERSION:
		# **여기서 파일을 건드리지 않는다.** 사유만 돌려준다
		out["status"] = LOAD_VERSION
		out["message"] = VERSION_MESSAGE
		return out
	var run := _normalize(doc.run)
	# 불러온 회차는 **언제나 거점부터**다. 파일이 어떤 값을 안고 있든 전투 표시를 내린다.
	# 저장 쪽에서도 내리지만(_for_file), 옛 파일·손으로 고친 파일까지 덮으려고 여기서도 내린다.
	run["inCombat"] = false
	_drop_unknown_equipment(run)
	out["status"] = LOAD_OK
	out["run"] = run
	return out

## 예전 그대로의 얇은 겉면: 이어할 수 있는 회차만 돌려주고, 아니면 {}.
## 사유가 필요한 쪽(제목 화면·이어하기)은 load_result()를 쓴다.
static func load() -> Dictionary:
	var r := load_result()
	if String(r.status) != LOAD_OK:
		return {}
	var run: Dictionary = r.run
	return run

## 지금 저장을 **이어할 수 있는가**(파일이 있고 판본이 맞는가)
static func continuable() -> bool:
	return String(load_result().status) == LOAD_OK

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
	# **자료를 못 읽었으면 아무것도 빼지 않는다.**
	# PCatalog._load 가 실패하면 빈 사전을 돌려주고, 그러면 여기서 **멀쩡한 장비까지 전부**
	# '없는 것'으로 보여 사람의 장비를 통째로 지워 버린다. 지우는 쪽이 훨씬 위험하므로,
	# 목록이 실제로 서 있을 때만 정리한다. 서 있지 않으면 그대로 두고 넘긴다 —
	# 없는 장비가 남아도 아래 게임이 죽을 뿐이고, 지워 버리면 되돌릴 수 없다.
	if (PCatalog.equipment() as Dictionary).is_empty():
		push_warning("장비 자료를 읽지 못해 저장 정리를 건너뛴다(멀쩡한 장비를 지우지 않으려고)")
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
