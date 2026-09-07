class_name PReplay
extends RefCounted
## 입력 기록·재생(docs/BOT_FRAMEWORK.md §재생 형식). 고정 단계 번호와 입력 사전의 '변경'만 저장한다(누름 press는 true→false 전환도 변경이므로 자기 항목으로 남는다).
## 머리말: 게임 버전·규칙/봇 버전·엔진·OS·커밋(배치 실행기가 넘긴다, 없으면 unknown)·데이터 해시(data/*.json SHA-256)·시나리오·빌드·게임/봇 seed·기록 형식 버전.
## 주기 상태 해시(120단계마다): 플레이어 위치·체력·보호막·재사용 + 살아 있는 적 id/위치/체력 + t. 재생은 같은 단계에서 해시를 대조한다.
## 버전(형식·게임·데이터 해시)이 다르면 재생을 명시적으로 거부한다(check_header). 사람 경로: attach_recorder(driver)로 PStepDriver가 단계마다 note()를 부른다.
## 일시정지/포커스 상실/재시작은 mark("reset")로 남는다(대기 입력 폐기 = 다음 항목의 press false). 벽시계는 섞지 않는다(전투 단계 번호만).

const FORMAT := "prophecy_replay/1"
const HASH_EVERY := 120
const KEYS := ["mx", "my", "dodge_press", "dodge_held", "special", "skill_e"]

var header: Dictionary = {}
var inputs: Array = []     # [step, {mx,my,dodge_press,dodge_held,special,skill_e}]
var marks: Array = []      # [step, kind]
var hashes: Array = []     # [step, sha256]
var result: Dictionary = {}
var _last: Dictionary = {}
var _hashed_step: int = -1
var _last_step: int = 0
var recording: bool = false

## 입력 정규화(6키, 실수는 그대로 — 반올림하면 재생이 갈라진다). 저장 항목의 mx/my는 var_to_str 문자열(17유효자리, 어떤 double도 정확 복원. JSON.stringify는 15자리, String.num(20)은 작은 값에서 자릿수 부족)이며 여기서 다시 실수로 읽는다
static func _num(v: Variant) -> float:
	if typeof(v) == TYPE_STRING:
		var p = str_to_var(String(v))
		return float(p) if (typeof(p) == TYPE_FLOAT or typeof(p) == TYPE_INT) else String(v).to_float()
	return float(v)

static func norm_input(inp: Dictionary) -> Dictionary:
	return { "mx": _num(inp.get("mx", 0.0)), "my": _num(inp.get("my", 0.0)), "dodge_press": bool(inp.get("dodge_press", false)), "dodge_held": bool(inp.get("dodge_held", false)), "special": bool(inp.get("special", false)), "skill_e": bool(inp.get("skill_e", false)) }

## 저장용: 실수를 var_to_str 문자열로(정확 복원)
static func ser_input(inp: Dictionary) -> Dictionary:
	return { "mx": var_to_str(float(inp.mx)), "my": var_to_str(float(inp.my)), "dodge_press": bool(inp.dodge_press), "dodge_held": bool(inp.dodge_held), "special": bool(inp.special), "skill_e": bool(inp.skill_e) }

static func same_input(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	for k in KEYS:
		if a[k] != b[k]:
			return false
	return true

## 기록 시작. extra = {scenario, build_fixture, game_seed, bot_seed, profile, bot_version, commit, dirty, data_hash, engine, os}
func begin(st: CombatState, extra: Dictionary = {}) -> void:
	header = { "format": FORMAT, "game_version": game_version(), "rules_version": rules_version(), "bot_version": String(extra.get("bot_version", "human")),
		"engine": String(extra.get("engine", "unknown")), "os": String(extra.get("os", "unknown")), "commit": String(extra.get("commit", "unknown")), "dirty": extra.get("dirty", "unknown"),
		"data_hash": String(extra.get("data_hash", "unknown")), "scenario": String(extra.get("scenario", "unknown")), "build_fixture": String(extra.get("build_fixture", "unknown")),
		"game_seed": int(extra.get("game_seed", st.seed_value)), "bot_seed": int(extra.get("bot_seed", 0)), "profile": String(extra.get("profile", "human")), "step": 1.0 / 120.0, "hash_every": HASH_EVERY,
		"start_step": int(st.step_n) }
	for k in extra:
		if not header.has(k):
			header[k] = extra[k]
	inputs = []
	marks = []
	hashes = []
	result = {}
	_last = {}
	_hashed_step = -1
	recording = true

## 단계 실행 직전에 부른다(입력이 바뀐 단계만 저장). 직전 단계가 해시 주기면 그 상태 해시를 남긴다
func note(st: CombatState, inp: Dictionary) -> void:
	if not recording:
		return
	_last_step = int(st.step_n)
	_maybe_hash(st)
	var cur := norm_input(inp)
	if not same_input(cur, _last):
		inputs.append([int(st.step_n) + 1, ser_input(cur)])
		_last = cur

func _maybe_hash(st: CombatState) -> void:
	var n: int = int(st.step_n)
	if n > 0 and n % HASH_EVERY == 0 and n != _hashed_step:
		_hashed_step = n
		hashes.append([n, state_hash(st)])

func mark(kind: String, st: CombatState = null) -> void:
	if recording:
		marks.append([int(st.step_n) if st != null else _last_step, kind])

func finish(st: CombatState) -> Dictionary:
	if not recording:
		return to_dict()
	_maybe_hash(st)
	if _hashed_step != int(st.step_n):
		hashes.append([int(st.step_n), state_hash(st)])
	result = { "status": String(st.status), "steps": int(st.step_n), "t": snapped(float(st.t), 0.001), "hp": float(st.player.hp), "kills": int(st.stats.kills), "damage_taken": float(st.stats.damage_taken) }
	recording = false
	return to_dict()

func to_dict() -> Dictionary:
	return { "format": FORMAT, "header": header.duplicate(true), "inputs": inputs.duplicate(true), "marks": marks.duplicate(true), "hashes": hashes.duplicate(true), "result": result.duplicate(true) }

func save(path: String) -> bool:
	var dir := path.get_base_dir()
	if dir.begins_with("user://") or dir.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	else:
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("기록 저장 실패: " + path)
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true

static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## 사람 경로: PStepDriver가 단계마다 note()를 부르고 reset()에 mark("reset")를 남긴다
func attach_recorder(driver: PStepDriver) -> void:
	driver.recorder = self

static func game_version() -> String:
	return String(preload("res://scripts/game/game.gd").VERSION)

static func rules_version() -> String:
	return "rules@" + game_version() + "/" + PObserve.VERSION

## 상태 해시(플레이어·살아 있는 적·시간). 소수는 3자리로 잘라 문자열화 → SHA-256
static func state_hash(st: CombatState) -> String:
	var p: Dictionary = st.player
	var parts := PackedStringArray()
	parts.append("t=%.4f;n=%d;st=%s" % [float(st.t), int(st.step_n), String(st.status)])
	parts.append("p=%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s" % [float(p.x), float(p.y), float(p.hp), float(p.shield), float(p.dodge_cd), float(p.special_cd), float(p.get("e_cd", 0.0)), str(bool(p.dodge_active))])
	for e in st.enemies:
		if bool(e.dead):
			continue
		parts.append("e%d=%s,%.3f,%.3f,%.3f,%s" % [int(e.id), String(e.type), float(e.x), float(e.y), float(e.hp), String(e.state)])
	parts.append("k=%d;d=%.3f" % [int(st.stats.kills), float(st.stats.damage_taken)])
	return "\n".join(parts).sha256_text()

## 재생 가능 여부. "" = 가능, 아니면 거부 이유
static func check_header(rec: Dictionary, data_hash: String = "") -> String:
	if String(rec.get("format", "")) != FORMAT:
		return "기록 형식 불일치: %s ≠ %s" % [String(rec.get("format", "")), FORMAT]
	var h: Dictionary = rec.get("header", {})
	if String(h.get("game_version", "")) != game_version():
		return "게임 버전 불일치: %s ≠ %s" % [String(h.get("game_version", "")), game_version()]
	if String(h.get("rules_version", "")) != rules_version():
		return "규칙 버전 불일치: %s ≠ %s" % [String(h.get("rules_version", "")), rules_version()]
	if data_hash != "" and String(h.get("data_hash", "unknown")) != "unknown" and String(h.data_hash) != data_hash:
		return "데이터 해시 불일치: %s ≠ %s" % [String(h.data_hash), data_hash]
	return ""

## 같은 초기 상태(st)에 기록 입력을 단계별로 넣고 주기 해시를 대조한다. 반환 {ok, refused, reason, steps, mismatches[{step, expected, actual}], status, hash_checked}
static func replay(st: CombatState, rec: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var reason := check_header(rec, String(opts.get("data_hash", "")))
	if reason != "" and not bool(opts.get("force", false)):
		return { "ok": false, "refused": true, "reason": reason, "steps": 0, "mismatches": [], "status": String(st.status), "hash_checked": 0 }
	var ins: Array = rec.get("inputs", [])
	var hs: Array = rec.get("hashes", [])
	var expected := {}
	for h in hs:
		expected[int(h[0])] = String(h[1])
	var total: int = int(rec.get("result", {}).get("steps", 0))
	if total <= 0 and not ins.is_empty():
		total = int(ins[ins.size() - 1][0])
	var max_steps: int = int(opts.get("max_steps", total))
	var cur := norm_input({})
	var idx := 0
	var mism := []
	var checked := 0
	var dt := 1.0 / 120.0
	var n: int = int(st.step_n)
	while n < max_steps:
		var next_n := n + 1
		while idx < ins.size() and int(ins[idx][0]) <= next_n:
			if int(ins[idx][0]) == next_n:
				cur = norm_input(ins[idx][1])
			idx += 1
		st.step(cur, dt)
		n = int(st.step_n)
		if expected.has(n):
			checked += 1
			var actual := state_hash(st)
			if actual != String(expected[n]):
				mism.append({ "step": n, "expected": String(expected[n]), "actual": actual })
				if bool(opts.get("stop_on_mismatch", true)):
					break
	return { "ok": mism.is_empty() and not (bool(opts.get("require_result", true)) and rec.has("result") and not (rec.result as Dictionary).is_empty() and String(rec.result.status) != String(st.status)), "refused": false, "reason": "", "steps": n, "mismatches": mism, "status": String(st.status), "hash_checked": checked }

## data/*.json 전체의 SHA-256(파일 이름순 연결). 캐시 키·기록 머리말용
## 판단·규칙에 영향을 주는 코드의 내용 해시(검수 지적 3): res://scripts, res://tools의 .gd + project.godot + .tscn(경로+내용, 정렬). .uid/.import 제외.
## git 정보가 없는 프로젝트 ZIP에서도 같은 값. 파일을 못 읽으면 "unknown"(배치는 그 값으로 기존 결과 재개를 거부한다)
static func code_hash() -> String:
	var files := []
	for root in ["res://scripts", "res://tools", "res://scenes"]:
		_collect_code(root, files)
	var top := DirAccess.open("res://") # 최상위 장면 파일(main.tscn 등)만, 하위 폴더는 위 목록으로
	if top != null:
		top.list_dir_begin()
		var tn := top.get_next()
		while tn != "":
			if not top.current_is_dir() and tn.ends_with(".tscn"):
				files.append("res://" + tn)
			tn = top.get_next()
		top.list_dir_end()
	files.append("res://project.godot")
	files.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var n := 0
	for path in files:
		var f := FileAccess.open(String(path), FileAccess.READ)
		if f == null:
			continue
		ctx.update((String(path) + "\n").to_utf8_buffer())
		ctx.update(f.get_buffer(f.get_length()))
		f.close()
		n += 1
	if n == 0:
		return "unknown"
	return ctx.finish().hex_encode()

static func _collect_code(root: String, out: Array) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		var full := root.path_join(fn)
		if dir.current_is_dir():
			if not fn.begins_with("."):
				_collect_code(full, out)
		elif fn.ends_with(".gd") or fn.ends_with(".tscn"):
			out.append(full)
		fn = dir.get_next()
	dir.list_dir_end()

static func data_hash() -> String:
	var dir := DirAccess.open("res://data")
	if dir == null:
		return "unknown"
	var names := []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".json"):
			names.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	names.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for nm in names:
		var f := FileAccess.open("res://data/" + String(nm), FileAccess.READ)
		if f != null:
			ctx.update(f.get_buffer(f.get_length()))
			f.close()
	return ctx.finish().hex_encode()
