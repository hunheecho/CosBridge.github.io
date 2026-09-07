class_name PBotBatch
extends RefCounted
## 실력 봇 배치 실행기 본체(docs/BOT_FRAMEWORK.md §배치): 시나리오 × 프로필 × 게임 seed × 봇 seed. 증분 저장(results.jsonl)·재개·캐시 키·벽시계 예산.
## 헤드리스 진입은 tools/bot_batch.gd(환경 변수 → run(opts)). 테스트는 run(opts)에 base_dir·목록을 직접 넣어 재개·무효화를 검사한다.
## 사용: PROPHECY_BOT_RUN_ID=<id> godot --headless --path prophecy_godot -s tools/bot_batch.gd
## 환경 변수: PROPHECY_BOT_RUN_ID(기본 날짜시각) PROPHECY_BOT_MODE(compare|throughput|report) PROPHECY_BOT_SCENARIOS(쉼표, 기본 compare 묶음)
##   PROPHECY_BOT_PROFILES(기본 novice,regular,skilled,balanced) PROPHECY_BOT_SEEDS(기본 1,2,3,4,5) PROPHECY_BOT_BOSS_SEEDS(기본 1,2,3) PROPHECY_BOT_BOT_SEED(기본 = 게임 seed; 정수면 고정)
##   PROPHECY_BOT_BUDGET_SEC(벽시계 예산, 기본 600) PROPHECY_BOT_MAX_SEC(전투 상한 덮어쓰기) PROPHECY_BOT_SAMPLE(성공 재생 표본 간격, 기본 5) PROPHECY_BOT_FORCE=1(캐시 불일치 시 폴더 무효화 후 새로)
##   PROPHECY_BOT_REPORT(res://docs/sim/BOT_COMPARE.md; 비어 있으면 run 폴더에만 summary.md) PROPHECY_BOT_TITLE(보고서 제목, 기본 "실력별 전투 봇 첫 비교(BOT_COMPARE)")
##   시나리오 "boss3" = 신규 관문 보스 6종 묶음(BOSS3_SCENARIOS)으로 펼친다
## 결과: res://docs/sim/bot_runs/<run_id>/{results.jsonl, meta.json, summary.md, git_head.txt, replays/*.json}. 시간초과는 timeout 그대로(패배·승리로 바꾸지 않는다). 봇 결과는 가상 조작 모델이며 사람 승률이 아니다.

const STEP := 1.0 / 120.0
const SCENARIOS := {
	"baseline_wolf25": { "kind": "first_fight", "max_sec": 240.0, "build": "sword_lv1", "doc": "0.3.1 D33 기준 전투(x5 늑대 25, 동시 12, 동시 돌진 2, 회피 hold 70~150/1.5초)" },
	"ranged_mix": { "kind": "encounter", "region": "ridge", "day": 3, "max_sec": 240.0, "build": "sword_lv1", "doc": "바람 능선 3일차 기본 편성(궁수·방패병·늑대·거미, uniform_x5), 검 Lv1 고정" },
	"zone_mix": { "kind": "encounter", "region": "marsh", "day": 4, "max_sec": 240.0, "build": "sword_lv1", "doc": "안개 습지 4일차 기본 편성(포자·서리술사·거미·궁수·늑대, uniform_x5), 검 Lv1 고정" },
	"boss_thornmane": { "kind": "boss", "boss": "boss", "preset": "stage1", "max_sec": 300.0, "build": "lab:stage1", "doc": "가시갈기 × 실험실 stage1 프리셋(boss_sim make_run)" },
	"boss_guardian": { "kind": "boss", "boss": "guardian", "preset": "stage2", "max_sec": 300.0, "build": "lab:stage2", "doc": "봉인 수호자 × stage2 프리셋" },
	"boss_eater": { "kind": "boss", "boss": "eater", "preset": "stage3", "max_sec": 300.0, "build": "lab:stage3", "doc": "예언을 먹는 자 × stage3 프리셋" },
	# 신규 관문 보스 6종(boss3.gd, bosses_new.json 시험값): 막에 맞는 관문 프리셋(tools/boss_sim.gd와 같은 규칙: 1막 stage1 · 2막 stage2 · 3막 stage3), 체력 세트 hi(boss_hp_sets)
	"boss_warden": { "kind": "boss", "boss": "gate_warden", "preset": "stage1", "max_sec": 300.0, "build": "lab:stage1", "doc": "성문 파수장(1막) × stage1 프리셋, 체력 hi 2400" },
	"boss_matriarch": { "kind": "boss", "boss": "spore_matriarch", "preset": "stage1", "max_sec": 300.0, "build": "lab:stage1", "doc": "포자 어미(1막) × stage1 프리셋, 체력 hi 2400" },
	"boss_behemoth": { "kind": "boss", "boss": "excavation_behemoth", "preset": "stage2", "max_sec": 300.0, "build": "lab:stage2", "doc": "굴착 거수(2막) × stage2 프리셋, 체력 hi 5000" },
	"boss_stalker": { "kind": "boss", "boss": "frost_stalker", "preset": "stage2", "max_sec": 300.0, "build": "lab:stage2", "doc": "서리 추적자(2막) × stage2 프리셋, 체력 hi 5000" },
	"boss_hunt_king": { "kind": "boss", "boss": "blood_hunt_king", "preset": "stage3", "max_sec": 300.0, "build": "lab:stage3", "doc": "핏빛 사냥왕(3막) × stage3 프리셋, 체력 hi 7000" },
	"boss_executor": { "kind": "boss", "boss": "doom_executor", "preset": "stage3", "max_sec": 300.0, "build": "lab:stage3", "doc": "종말의 집행관(3막) × stage3 프리셋, 체력 hi 7000" },
}
const BOSS3_SCENARIOS := ["boss_warden", "boss_matriarch", "boss_behemoth", "boss_stalker", "boss_hunt_king", "boss_executor"]
const LEGACY_ACT := { "boss": 1, "guardian": 2, "eater": 3 }
const STALL_SEC := 60.0 # 처치·피해·체력 변화가 이 시간 동안 없으면 진행정체(stalled)로 종료

## 보스 체력(tools/boss_sim.gd boss_hp_of와 같은 규칙; SceneTree 스크립트를 preload하면 종료 시 ObjectDB 누수 경고가 나서 여기 복사): 회차 모드(PRun.boss_hp)에 있으면 그 값, 아니면 boss_hp_sets[세트][id][stage<막>], 없으면 정의 hp
static func _boss_hp_of(run: Dictionary, bid: String) -> float:
	for b in PRun.mode_def(run).bosses:
		if String(b.id) == bid:
			return PRun.boss_hp(run, bid)
	var d := PCatalog.boss_def(bid)
	var act: int = int(d.act) if d.has("act") else int(LEGACY_ACT.get(bid, 1))
	var sets := PCatalog.boss_hp_sets()
	var set_id := String(run.get("bossHpSet", "hi"))
	var H: Dictionary = sets[set_id] if sets.has(set_id) else sets.base
	var key := "stage%d" % act
	if H.has(bid) and (H[bid] as Dictionary).has(key):
		return float(H[bid][key])
	return float(d.hp)

var run_id := ""
var run_dir := ""
var meta: Dictionary = {}
var env_info: Dictionary = {}
var t_start := 0
var budget_sec := 600.0
var sample_every := 5
var success_n := 0
var warnings: Array = []
var opts: Dictionary = {}   # run(opts)의 설정(환경 변수 이름과 같은 키). 있으면 환경 변수보다 우선
var messages: Array = []    # CACHE_INVALID·BUDGET_EXCEEDED 등 실행 메시지(테스트 확인용)

func _env(k: String, d: String) -> String:
	if opts.has(k):
		return str(opts[k])
	var v := OS.get_environment(k)
	return v if v != "" else d

func _msg(s: String) -> void:
	messages.append(s)
	printerr(s)

func _list(s: String) -> Array:
	var out := []
	for p in s.split(","):
		var t := String(p).strip_edges()
		if t != "":
			out.append(t)
	return out

func _ints(s: String) -> Array:
	var out := []
	for p in _list(s):
		if String(p).is_valid_int():
			out.append(int(p))
	return out

# ---------- 환경 식별 ----------
func _git(args: Array) -> String:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var out := []
	var a := ["-C", root]
	for x in args:
		a.append(x)
	var code := OS.execute("git", a, out, true)
	if code != 0 or out.is_empty():
		return ""
	return String(out[0]).strip_edges()

func _env_info() -> Dictionary:
	var head := _git(["rev-parse", "HEAD"])
	var dirty := _git(["status", "--porcelain", "--", "prophecy_godot"])
	return { "git_head": head if head != "" else "unknown", "dirty": (dirty != "") if head != "" else "unknown", "dirty_files": dirty.split("\n").size() if dirty != "" else 0,
		"data_hash": PReplay.data_hash(), "code_hash": PReplay.code_hash(), "profile_hash": PSkillBot.profile_hash(), "engine": Engine.get_version_info().string, "os": OS.get_name() + "/" + Engine.get_architecture_name(),
		"game_version": PReplay.game_version(), "rules_version": PReplay.rules_version(), "bot_version": PSkillBot.BOT_VERSION + "/" + String(PCatalog.bots().get("version", "?")), "observe_version": PObserve.VERSION, "replay_format": PReplay.FORMAT }

# ---------- 시나리오 ----------
## 시나리오 → {st, build_fixture, max_sec, boss_id} 또는 {error}
func make_scenario(sid: String, seed_v: int) -> Dictionary:
	if not SCENARIOS.has(sid):
		return { "error": "unimplemented:unknown_scenario" }
	var S: Dictionary = SCENARIOS[sid]
	var max_sec: float = float(S.max_sec)
	if _env("PROPHECY_BOT_MAX_SEC", "") != "":
		max_sec = float(_env("PROPHECY_BOT_MAX_SEC", ""))
	match String(S.kind):
		"first_fight":
			var G := preload("res://scripts/game/game.gd")
			var cfg: Dictionary = G.config_with(G.load_config(), "hold", 1.5, "x5", 2)
			return { "st": CombatState.first_fight(cfg, seed_v), "build_fixture": String(S.build), "max_sec": max_sec, "boss_id": "" }
		"encounter":
			var run := PRun.new_run(seed_v, "sword")
			run.day = int(S.day)
			run.hp = float(PRun.build(run).hp_max)
			var s := { "regionId": String(S.region), "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0, "seed": seed_v * 977 + int(S.day), "day": int(S.day), "slot": 1, "variant": null }
			if not PCatalog.world().day_waves.has(String(S.region)):
				return { "error": "unimplemented:no_day_waves" }
			var st := PFlow.make_encounter(run, s, { "fixed_build": true }) # 검 Lv1 고정(레벨업 없음)
			return { "st": st, "build_fixture": String(S.build), "max_sec": max_sec, "boss_id": "" }
		"boss":
			var BUILDS: Dictionary = PCatalog.lab().get("BUILDS", {})
			if not BUILDS.has(String(S.preset)):
				return { "error": "unimplemented:no_preset" }
			var run2 := _lab_run(seed_v, BUILDS[String(S.preset)])
			var b := PRun.build(run2)
			var st2 := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v, "boss": true, "boss_id": String(S.boss), "boss_hp": _boss_hp_of(run2, String(S.boss)),
				"arena": "clearing", "region_id": "boss", "xp_kill_mult": PRun.kill_xp_mult(run2), "run": run2 })
			return { "st": st2, "build_fixture": String(S.build), "max_sec": max_sec, "boss_id": String(S.boss) }
	return { "error": "unimplemented" }

## 실험실 프리셋 → 회차 dict(tools/boss_sim.gd make_run과 같은 절차: PRun.new_run 뒤 성장·장비·강화만 덮어쓴다, bossHpSet hi)
static func _lab_run(seed_v: int, preset: Dictionary) -> Dictionary:
	var gw: Dictionary = preset.growth
	var first := String((gw.weapons as Array)[0].id)
	var run := PRun.new_run(seed_v, first)
	run.bossHpSet = "hi"
	var g: Dictionary = run.growth
	var ws := []
	for w in gw.weapons:
		ws.append({ "id": String(w.id), "level": int(w.level), "mods": (w.mods as Array).duplicate() if w.has("mods") else [] })
	g.weapons = ws
	var cm := {}
	for k in gw.get("commons", {}):
		cm[String(k)] = int(gw.commons[k])
	g.commons = cm
	var ps := {}
	for k in gw.get("passives", {}):
		ps[String(k)] = int(gw.passives[k])
	g.passives = ps
	if gw.has("e"):
		g.skills.e = { "id": String(gw.e.id), "level": int(gw.e.level), "variant": (String(gw.e.variant) if gw.e.get("variant", null) != null else null) }
	if gw.has("q"):
		g.skills.q.level = int(gw.q.get("level", 1))
		g.skills.q.variant = String(gw.q.variant) if gw.q.get("variant", null) != null else null
	var br := []
	for id in gw.get("bossRewards", []):
		br.append(String(id))
	g.bossRewards = br
	var lv := 1
	for w in ws:
		lv += int(w.level) - 1 + (w.mods as Array).size()
	for k in cm:
		lv += int(cm[k])
	for k in ps:
		lv += int(ps[k])
	g.level = lv
	var eq: Dictionary = preset.get("equipment", {})
	for slot in eq:
		if eq[slot] != null and PCatalog.equipment().has(String(eq[slot])):
			run.equipment[String(slot)] = String(eq[slot])
	var gear: Dictionary = preset.get("gear", {})
	run.forge = int(preset.get("forge", gear.get("upgrade", 0)))
	run.hp = float(PRun.build(run).hp_max)
	return run

func make_bot(profile: String, bot_seed: int) -> PBot:
	if PCatalog.bot_profiles().has(profile):
		return PSkillBot.new(profile, bot_seed)
	return PBot.new(profile)

# ---------- 전투 1회 ----------
func fight(sid: String, profile: String, gseed: int, bseed: int) -> Dictionary:
	var row := { "run_id": run_id, "scenario": sid, "profile": profile, "game_seed": gseed, "bot_seed": bseed, "status": "error", "sim_sec": 0.0, "wall_ms": 0, "steps": 0 }
	var sc := make_scenario(sid, gseed)
	if sc.has("error"):
		row.status = "unimplemented"
		row.error = String(sc.error)
		return row
	var st: CombatState = sc.st
	var bot := make_bot(profile, bseed)
	var rec := PHitRecorder.new()
	st.recorder = rec
	var rp := PReplay.new()
	var hdr := env_info.duplicate()
	hdr.commit = String(env_info.git_head)
	hdr.scenario = sid
	hdr.build_fixture = String(sc.build_fixture)
	hdr.game_seed = gseed
	hdr.bot_seed = bseed
	hdr.profile = profile
	hdr.bot_version = String(env_info.bot_version) if bot is PSkillBot else ("legacy:" + profile)
	rp.begin(st, hdr)
	var max_sec: float = float(sc.max_sec)
	var max_n := int(round(max_sec / STEP))
	var n := 0
	var ms0 := Time.get_ticks_msec()
	var last_progress_t := 0.0
	var last_kills := 0
	var last_hp: float = float(st.player.hp)
	var stalled := false
	while st.status == "running" and n < max_n:
		var inp := bot.step_input(st)
		rp.note(st, inp)
		st.step(inp, STEP)
		n += 1
		if int(st.stats.kills) != last_kills or float(st.player.hp) != last_hp or float(st.intro) > 0.0:
			last_kills = int(st.stats.kills)
			last_hp = float(st.player.hp)
			last_progress_t = float(st.t)
		elif float(st.t) - last_progress_t >= STALL_SEC:
			stalled = true
			break
	var wall := Time.get_ticks_msec() - ms0
	rec.finish(st)
	var status := String(st.status)
	if status == "running":
		status = "stalled" if stalled else "timeout"
		st.status = status if status == "timeout" else st.status # timeout은 상태 자체를 timeout으로(요약 일관성); stalled는 running 상태를 남긴다
		st.delayed.clear()
	var d := rp.finish(st)
	var sm := st.summary()
	var rr := rec.report()
	var dists: Array = sm.dodge_dists
	var dsum := 0.0
	for v in dists:
		dsum += float(v)
	row.status = status
	row.stalled = stalled
	row.sim_sec = snapped(float(st.t), 0.01)
	row.wall_ms = wall
	row.steps = n
	row.kills = int(sm.kills)
	row.spawn_total = int(sm.spawn_total)
	row.hp = snapped(float(st.player.hp), 0.1)
	row.hp_max = float(st.player.hp_max)
	row.taken = snapped(float(sm.damage_taken), 0.1)
	row.taken_nominal = snapped(float(sm.damage_taken_nominal), 0.1)
	row.absorbed = snapped(float(sm.absorbed), 0.1)
	row.healed = snapped(float(sm.healed), 0.1)
	row.shield = rr.checksum
	row.taken_by = sm.taken
	row.taken_hits = sm.taken_hits
	row.dodges = int(sm.dodges)
	row.dodge_dists = dists
	row.dodge_avg = snapped(dsum / maxf(1.0, float(dists.size())), 0.1) if dists.size() > 0 else 0.0
	row.dodge_blocked = int(rr.dodge_blocked)
	row.perfect_dodges = int(sm.perfect_dodges)
	row.press_attempts = int(rr.press_attempts)
	row.press_rejected = int(rr.press_rejected)
	row.q = int(sm.special_uses)
	row.e = int(sm.e_uses)
	row.max_alive = int(sm.max_alive)
	row.max_concurrent = rr.max_concurrent
	row.attacks = rr.attacks
	row.attacks_by_type = rr.attacks_by_type
	row.rejected_hits = rr.rejected
	row.hits = int(rr.hits)
	row.tags = rr.tags
	row.checksum_ok = bool(rr.checksum.ok)
	row.dmg_total = float(sm.dmg_total)
	row.dmg = sm.dmg
	row.boss_damage = float(sm.boss_damage)
	row.boss_hp_left = (maxf(0.0, snapped(float(st.boss.hp), 0.1)) if not st.boss.is_empty() else 0.0)
	row.boss_hp_max = (float(st.boss.hp_max) if not st.boss.is_empty() else 0.0)
	row.patterns = sm.patterns
	row.level_ups = int(sm.level_ups)
	row.latency = (bot as PSkillBot).latency_report() if bot is PSkillBot else {}
	# 출처별 피해(PStats 재사용: 보유 시간 DPS)
	var prun := { "dmgStats": { "combats": [], "byKey": {} } }
	PStats.record(prun, st, { "kind": "boss" if st.mode == "boss" else "sortie" })
	var agg := PStats.aggregate(prun)
	var rows := []
	for r in agg.rows:
		rows.append({ "key": String(r.key), "amount": float(r.amount), "active": float(r.active), "dps": float(r.dps), "cat": String(r.cat) })
	row.dmg_rows = rows
	row.dps_all = float(agg.dpsAll)
	# 재생 파일: 실패는 항상, 성공은 표본
	var keep := status != "won"
	if status == "won":
		success_n += 1
		keep = (success_n % sample_every) == 1 or sample_every <= 1
	if keep:
		var rel := "replays/%s_%s_g%d_b%d.json" % [sid, profile, gseed, bseed]
		rp.save(run_dir.path_join(rel))
		row.replay = rel
	else:
		row.replay = ""
	row.replay_inputs = d.inputs.size()
	row.replay_hashes = d.hashes.size()
	return row

# ---------- 저장·재개 ----------
func _key(r: Dictionary) -> String:
	return "%s|%s|%d|%d" % [String(r.scenario), String(r.profile), int(r.game_seed), int(r.bot_seed)]

func _read_rows() -> Array:
	var out := []
	var f := FileAccess.open(run_dir.path_join("results.jsonl"), FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			out.append(parsed)
	f.close()
	return out

func _append_row(r: Dictionary) -> void:
	var path := run_dir.path_join("results.jsonl")
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	f.store_line(JSON.stringify(r))
	f.flush()
	f.close()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("쓰기 실패: " + path)
		return
	f.store_string(text)
	f.close()

## 캐시 키 차이 목록(비어 있으면 같은 환경). 옛 meta에 없는 키(code_hash 등)도 차이로 본다
static func cache_diff(old: Dictionary, ck: Dictionary) -> Array:
	var diff := []
	for k in ck:
		if str(old.get(k, "")) != str(ck[k]):
			diff.append("%s: %s → %s" % [String(k), str(old.get(k, "")), str(ck[k])])
	return diff

## 코드를 식별할 수 없으면(code_hash unknown) 완료 행 재개를 허용하지 않는다
static func can_resume(ck: Dictionary) -> bool:
	var ch := String(ck.get("code_hash", "unknown"))
	return ch != "" and ch != "unknown"

## 캐시 키(검수 지적 3): 커밋·dirty만으로는 미커밋 코드 변경을 구분할 수 없어 코드 내용 해시(code_hash)·규칙/관측 버전을 넣는다. 데이터·프로필·설정·엔진·OS·게임/봇 버전은 그대로
func _cache_key(settings: Dictionary) -> Dictionary:
	return { "git_head": String(env_info.git_head), "dirty": env_info.dirty, "code_hash": String(env_info.get("code_hash", "unknown")), "rules_version": String(env_info.get("rules_version", "")), "observe_version": String(env_info.get("observe_version", "")),
		"data_hash": String(env_info.data_hash), "profile_hash": String(env_info.profile_hash),
		"settings_hash": JSON.stringify(settings).sha256_text().substr(0, 16), "engine": String(env_info.engine), "os": String(env_info.os), "game_version": String(env_info.game_version), "bot_version": String(env_info.bot_version), "replay_format": String(env_info.replay_format) }

func _save_meta(complete: bool, rows_done: int) -> void:
	meta.complete = complete
	meta.rows_done = rows_done
	meta.wall_ms_total = int(meta.get("wall_ms_total", 0)) + (Time.get_ticks_msec() - t_start)
	t_start = Time.get_ticks_msec()
	meta.warnings = warnings
	meta.updated = Time.get_datetime_string_from_system()
	_write(run_dir.path_join("meta.json"), JSON.stringify(meta, "  "))

# ---------- 통계 ----------
static func wilson(k: int, n: int) -> Array:
	if n <= 0:
		return [0.0, 0.0]
	var z := 1.96
	var ph := float(k) / float(n)
	var denom := 1.0 + z * z / float(n)
	var center := (ph + z * z / (2.0 * float(n))) / denom
	var half := z * sqrt(ph * (1.0 - ph) / float(n) + z * z / (4.0 * float(n) * float(n))) / denom
	return [maxf(0.0, center - half), minf(1.0, center + half)]

static func pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return -1.0
	var s := arr.duplicate()
	s.sort()
	var idx := int(floor(q * float(s.size() - 1)))
	return float(s[clampi(idx, 0, s.size() - 1)])

static func avg(arr: Array) -> float:
	if arr.is_empty():
		return -1.0
	var t := 0.0
	for v in arr:
		t += float(v)
	return t / float(arr.size())

static func _f(v: float, digits: int = 1) -> String:
	if v < 0.0:
		return "-"
	return ("%." + str(digits) + "f") % v

# ---------- 보고서 ----------
func _group(rows: Array, sid: String, profile: String) -> Array:
	var out := []
	for r in rows:
		if String(r.scenario) == sid and String(r.profile) == profile:
			out.append(r)
	return out

func _profile_header(profiles: Array) -> String:
	var P := PSkillBot.profile_table()
	var C: Dictionary = PCatalog.bots().get("common", {})
	var md := "| 프로필 | 이름 | 판단 간격 | 새 위협 인식 지연 | 추적 갱신 지연 | 고려 위험 수 | 회피 방향 후보 | 방향 오차 | 누름 길이 |\n|---|---|---|---|---|---|---|---|---|\n"
	for pid in profiles:
		if P.has(pid):
			var p: Dictionary = P[pid]
			var rr: Array = p.recog_ms
			md += "| %s | %s | %dms | %d~%dms | %dms | %d | %d | ±%s° | %s |\n" % [pid, String(p.name), int(p.decide_ms), int(rr[0]), int(rr[1]), int(p.track_ms), int(p.attention), int(p.dodge_dirs), str(p.angle_err_deg), ("기본 최대거리 시도" if String(p.press) == "max" else "짧음/중간/김(빠져나갈 거리로)")]
		elif PBot.policies().has(pid):
			md += "| %s | %s(기존 정책, 기준 행) | 5스텝(41.7ms) | 없음(react_at %s) | 없음 | 전부 | 도형 탈출 방향 1 | 0 | 끝까지 |\n" % [pid, String(PBot.policies()[pid].name), str(PBot.policies()[pid].react_at)]
	md += "\n공통 규칙(모든 프로필 동일, `data/bots.json` common): Q = 200 안 %d마리 이상 또는 보스 %d 안 · E = 보유·200 안 %d마리 이상 · 유지 거리 %d · 안전 여유 %d · 반응 문턱 = 추적 예고(warn)는 진행률 %.1f 이상, 남은 초 표시 예고는 %.1f초 이하일 때만 벗어남(그 전에는 접근 계속) · 예고 warn 잔여 추정 %.2f초×(1−진행률), lock 잔여 %.2f초 · 걸어서 벗어나기 = 빠져나갈 거리 ≤ 이동속도×추정 잔여×%.1f · 짧음 ≤ %dpx, 중간 ≤ %dpx · 재사용 잔여가 판단 간격×%.1f 이하이면 미리 누름. 진단 성향(greedy_attack·nearest_only·long_dodge·hoard_qe)은 전부 꺼짐.\n" % [int(C.q_min_near), int(C.boss_q_dist), int(C.e_min_near), int(C.keep_dist), int(C.safety_margin), float(C.get("warn_react_prog", 0.4)), float(C.get("shown_react_sec", 0.9)), float(C.warn_est_sec), float(C.lock_est_sec), float(C.walk_factor), int(C.press_short_max), int(C.press_medium_max), float(C.press_slack_frac)]
	return md

func _sum_dict(rows: Array, key: String) -> Dictionary:
	var out := {}
	for r in rows:
		var d: Dictionary = r.get(key, {})
		for k in d:
			out[String(k)] = float(out.get(String(k), 0.0)) + float(d[k])
	return out

func _dict_text(d: Dictionary, digits: int = 0, top: int = 6) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return float(d[a]) > float(d[b]))
	var parts := []
	for k in keys.slice(0, top):
		parts.append("%s %s" % [String(k), (("%." + str(digits) + "f") % float(d[k]))])
	return ", ".join(parts) if parts.size() > 0 else "-"

func _table(rows: Array, scenarios: Array, profiles: Array, boss: bool) -> String:
	var md := ""
	if boss:
		md += "| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 보스 남은 체력 평균 | 받은 피해 평균 | 피격 수 | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 피해 출처(유효 합) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	else:
		md += "| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 받은 피해 평균 | 피격 수 | 남은 체력 평균(승) | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 최대 동시 적/예고/투사체/장판 | 피해 출처(유효 합) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for sid in scenarios:
		for pid in profiles:
			var g := _group(rows, String(sid), String(pid))
			if g.is_empty():
				continue
			var won := []
			var lost := []
			var counts := { "won": 0, "lost": 0, "timeout": 0, "stalled": 0, "error": 0, "unimplemented": 0 }
			var taken := []
			var hits := 0
			var dodges := []
			var dsum := 0.0
			var dn := 0
			var blocked := 0
			var rej := 0
			var q := 0
			var e := 0
			var hp_won := []
			var bhp := []
			var mx := [0, 0, 0, 0]
			for r in g:
				var s := String(r.status)
				counts[s] = int(counts.get(s, 0)) + 1
				if s == "won":
					won.append(float(r.sim_sec))
					hp_won.append(float(r.hp))
				elif s == "lost":
					lost.append(float(r.sim_sec))
				if s == "unimplemented":
					continue
				taken.append(float(r.taken))
				hits += int(r.hits)
				dodges.append(float(r.dodges))
				for v in r.dodge_dists:
					dsum += float(v)
					dn += 1
				blocked += int(r.dodge_blocked)
				rej += int(r.press_rejected)
				q += int(r.q)
				e += int(r.e)
				bhp.append(float(r.boss_hp_left))
				var mc: Dictionary = r.get("max_concurrent", {})
				mx[0] = maxi(mx[0], int(mc.get("enemies", 0)))
				mx[1] = maxi(mx[1], int(mc.get("telegraphs", 0)))
				mx[2] = maxi(mx[2], int(mc.get("projectiles", 0)))
				mx[3] = maxi(mx[3], int(mc.get("zones", 0)))
			var n := g.size()
			var ci := wilson(won.size(), n)
			var win_txt := "%d/%d = %.0f%% [%.0f%%, %.0f%%]" % [won.size(), n, 100.0 * float(won.size()) / float(n), ci[0] * 100.0, ci[1] * 100.0]
			var tw := ("%s / %s%s" % [_f(pct(won, 0.5)), _f(pct(won, 0.9)), (" (N<10: p90 불안정)" if won.size() < 10 and won.size() > 0 else "")]) if won.size() > 0 else "-"
			var by := _sum_dict(g, "taken_by")
			var dod := "%.1f (%s)" % [avg(dodges), _f(dsum / maxf(1.0, float(dn)))]
			if boss:
				md += "| %s | %s | %d | %d | %d | %d | %d | %d | %s | %s | %s | %s | %s | %d | %s | %d | %d | %d/%d | %s |\n" % [sid, pid, n, counts.won, counts.lost, counts.timeout, counts.stalled, int(counts.error) + int(counts.unimplemented), win_txt, tw, _f(pct(lost, 0.5)), _f(avg(bhp), 0), _f(avg(taken)), hits, dod, blocked, rej, q, e, _dict_text(by)]
			else:
				md += "| %s | %s | %d | %d | %d | %d | %d | %d | %s | %s | %s | %s | %d | %s | %s | %d | %d | %d/%d | %d/%d/%d/%d | %s |\n" % [sid, pid, n, counts.won, counts.lost, counts.timeout, counts.stalled, int(counts.error) + int(counts.unimplemented), win_txt, tw, _f(pct(lost, 0.5)), _f(avg(taken)), hits, _f(avg(hp_won)), dod, blocked, rej, q, e, mx[0], mx[1], mx[2], mx[3], _dict_text(by)]
	return md

func _tag_table(rows: Array, scenarios: Array, profiles: Array) -> String:
	var tag_keys := ["not_perceived", "perceived_no_input", "dodge_rejected_cooldown", "dodge_blocked_terrain", "after_dodge_025", "hit_by_other_while_escaping", "walking_out", "overlap", "unclassified"]
	var md := "| 시나리오 | 프로필 | 피격 | " + " | ".join(tag_keys) + " | 거절(무적/보호) | 공격 관측: 시작/고정/실행/명중/예고 중 사망/취소 |\n|---|---|---|" + "---|".repeat(tag_keys.size()) + "---|---|\n"
	for sid in scenarios:
		for pid in profiles:
			var g := _group(rows, String(sid), String(pid))
			if g.is_empty():
				continue
			var tg := _sum_dict(g, "tags")
			var rj := _sum_dict(g, "rejected_hits")
			var at := _sum_dict(g, "attacks")
			var hits := 0
			for r in g:
				hits += int(r.get("hits", 0))
			var parts := []
			for k in tag_keys:
				parts.append(str(int(tg.get(k, 0))))
			md += "| %s | %s | %d | %s | %d/%d | %d/%d/%d/%d/%d/%d |\n" % [sid, pid, hits, " | ".join(parts), int(rj.get("dodge_invuln", 0)), int(rj.get("hit_protection", 0)), int(at.get("started", 0)), int(at.get("locked", 0)), int(at.get("executed", 0)), int(at.get("hit", 0)), int(at.get("killed_during_telegraph", 0)), int(at.get("cancelled", 0))]
	return md

func _latency_table(rows: Array, scenarios: Array, profiles: Array) -> String:
	var md := "| 시나리오 | 프로필 | 판단 간격 | 인식 지연 평균(위협 수) | 최초 입력 지연 평균 / 판별 p50 중앙 / p90 중앙 (ms, 안에 있던 위협 수) | 누름 짧음/중간/김 | 봇 난수 소비 |\n|---|---|---|---|---|---|---|\n"
	for sid in scenarios:
		for pid in profiles:
			var g := _group(rows, String(sid), String(pid))
			if g.is_empty():
				continue
			var rec_sum := 0.0
			var rec_n := 0
			var fi_sum := 0.0
			var fi_n := 0
			var p50s := []
			var p90s := []
			var ps := [0, 0, 0]
			var draws := 0
			var dec := -1.0
			for r in g:
				var L: Dictionary = r.get("latency", {})
				if L.is_empty():
					continue
				dec = float(L.decide_ms)
				rec_sum += float(L.recog_avg_ms) * float(L.recog_n)
				rec_n += int(L.recog_n)
				fi_sum += float(L.first_input_avg_ms) * float(L.first_input_n)
				fi_n += int(L.first_input_n)
				if int(L.first_input_n) > 0:
					p50s.append(float(L.first_input_p50_ms))
					p90s.append(float(L.first_input_p90_ms))
				ps[0] += int(L.press_short)
				ps[1] += int(L.press_medium)
				ps[2] += int(L.press_long)
				draws += int(L.rng_draws)
			if dec < 0.0:
				md += "| %s | %s | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |\n" % [sid, pid]
				continue
			md += "| %s | %s | %dms | %s (%d) | %s / %s / %s (%d) | %d/%d/%d | %d |\n" % [sid, pid, int(dec), _f(rec_sum / maxf(1.0, float(rec_n))), rec_n, _f(fi_sum / maxf(1.0, float(fi_n))), _f(pct(p50s, 0.5)), _f(pct(p90s, 0.5)), fi_n, ps[0], ps[1], ps[2], draws]
	return md

func _pair_table(rows: Array, scenarios: Array, profiles: Array, seeds: Array) -> String:
	var md := "| 시나리오 | 게임 seed | " + " | ".join(profiles) + " |\n|---|---|" + "---|".repeat(profiles.size()) + "\n"
	for sid in scenarios:
		for sd in seeds:
			var cells := []
			var any := false
			for pid in profiles:
				var cell := "-"
				for r in rows:
					if String(r.scenario) == String(sid) and String(r.profile) == String(pid) and int(r.game_seed) == int(sd):
						cell = "%s %.1fs hp%d" % [String(r.status), float(r.sim_sec), int(round(float(r.hp)))]
						if float(r.get("boss_hp_max", 0.0)) > 0.0:
							cell += " 보스%d" % int(round(float(r.boss_hp_left)))
						any = true
						break
				cells.append(cell)
			if any:
				md += "| %s | %d | %s |\n" % [sid, int(sd), " | ".join(cells)]
	return md

func _dps_table(rows: Array, scenarios: Array, profiles: Array) -> String:
	var md := "| 시나리오 | 프로필 | 총피해 평균 | 전체 전투시간 DPS(총피해/총전투시간) | 출처별 유효 피해 합(보유시간 DPS) |\n|---|---|---|---|---|\n"
	for sid in scenarios:
		for pid in profiles:
			var g := _group(rows, String(sid), String(pid))
			if g.is_empty():
				continue
			var tot := 0.0
			var el := 0.0
			var by := {}
			var act := {}
			for r in g:
				tot += float(r.get("dmg_total", 0.0))
				el += float(r.sim_sec)
				for dr in r.get("dmg_rows", []):
					by[String(dr.key)] = float(by.get(String(dr.key), 0.0)) + float(dr.amount)
					act[String(dr.key)] = float(act.get(String(dr.key), 0.0)) + float(dr.active)
			var keys := by.keys()
			keys.sort_custom(func(a, b): return float(by[a]) > float(by[b]))
			var parts := []
			for k in keys.slice(0, 5):
				parts.append("%s %.0f(%.1f/s)" % [String(k), float(by[k]), float(by[k]) / maxf(1e-6, float(act[k]))])
			md += "| %s | %s | %.0f | %.1f | %s |\n" % [sid, pid, tot / float(g.size()), tot / maxf(1e-6, el), ", ".join(parts)]
	return md

func _report(rows: Array, settings: Dictionary, path: String, title: String) -> void:
	var scen: Array = settings.scenarios
	var profiles: Array = settings.profiles
	var normal := []
	var bosses := []
	for s in scen:
		if String(SCENARIOS.get(s, {}).get("kind", "")) == "boss":
			bosses.append(s)
		else:
			normal.append(s)
	var wall := 0
	var max_sim := 0.0
	var done := 0
	var statuses := {}
	for r in rows:
		wall += int(r.wall_ms)
		max_sim = maxf(max_sim, float(r.sim_sec))
		done += 1
		statuses[String(r.status)] = int(statuses.get(String(r.status), 0)) + 1
	var md := "# %s\n\n" % title
	md += "생성: `tools/bot_batch.gd` (run_id `%s`, %s). **가상 조작 모델(실제 플레이어 분포 아님) · 사람 보정 미완료.** 봇 결과는 규칙·정보 경계·집계 검증용이며 사람 승률·재미·가독성 판단이 아니다. 시간초과는 시간초과로 남긴다(패배·승리로 치환하지 않음).\n\n" % [run_id, String(meta.get("updated", ""))]
	md += "환경: 게임 %s · 규칙 %s · 봇 %s · 관측 %s · 기록 형식 %s · 엔진 %s · OS %s · git HEAD %s (prophecy_godot 미커밋 변경: %s) · 데이터 해시 %s · 프로필 해시 %s · 설정 해시 %s\n\n" % [String(env_info.game_version), String(env_info.rules_version), String(env_info.bot_version), String(env_info.observe_version), String(env_info.replay_format), String(env_info.engine), String(env_info.os), String(env_info.git_head), str(env_info.dirty), String(env_info.data_hash).substr(0, 16), String(env_info.profile_hash), String(meta.get("cache_key", {}).get("settings_hash", "?"))]
	md += "## 1. 구현된 프로필\n\n프로필 값은 `data/bots.json`에서 읽어 만든 표(시험값, 사용자 승인 아님).\n\n" + _profile_header(profiles) + "\n"
	md += "## 2. 기존 대비 동작 차이\n\n- 기존 정책(stand/active/aggressive/balanced/survival/idle/aware/still)은 코드·동작 그대로(`bot.gd` 변경 없음). `balanced` 행은 기준 행으로만 함께 실행했다(기존 정밀 정책이지 최적·완벽 회피가 증명된 봇이 아니다).\n- 새 프로필은 CombatState를 직접 읽지 않고 `PObserve` 스냅샷(화면에 그려지는 것만, 깊은 복사)만 읽는다. 기존 정책은 예고 진행률(react_at)로 반응하고 반응 지연이 없다; 새 프로필은 위협(attack_id)마다 인식 지연을 봇 seed로 표본화하고, 추적 중인 위협의 방향 변경은 추적 갱신 지연 뒤에만 안다.\n- 회피는 후보 방향 중 고려한 위협 도형의 합집합을 가장 짧게 벗어나는 방향 + 판단당 1회 방향 오차. 누름 길이는 조작 타이머로만 요청하고 실제 거리는 게임 규칙(70~150·충돌·재사용 1.5초)이 정한다(게임 수치 변경 없음).\n- Q/E·자동 공격·목표 접근은 모든 프로필 같은 단순 규칙이라 차이는 이동·회피에서만 난다.\n\n"
	md += "## 3. 실제 검사 범위\n\n- 시나리오: %s. 미구현(`unimplemented`) 행: %d.\n- 게임 seed %s(봇 seed = 게임 seed) × 프로필 %s. 같은 seed의 반복 재생은 독립 표본이 아니다. 전투 상한: %s초. 정체(stalled) = 처치·피해·체력 변화 없이 %.0f초.\n- 완료 %d행, 상태 분포 %s. 회귀 검사는 `tests/bot_tests.gd`(정보 경계·지연·기록 재생·검산·배치 재개).\n\n" % [", ".join(scen.map(func(s): return "%s(%s)" % [String(s), String(SCENARIOS.get(s, {}).get("doc", "?"))])), int(statuses.get("unimplemented", 0)), str(settings.game_seeds), str(profiles), str(settings.max_sec), STALL_SEC, done, JSON.stringify(statuses)]
	md += "## 4. 비용과 재현 방법\n\n- 벽시계 합계 %.1f초(전투당 평균 %.2f초, 최장 시뮬 %.1f초, 예산 %.0f초). 헤드리스 처리 속도는 실제 화면 FPS가 아니다.\n- 재현: `PROPHECY_BOT_RUN_ID=%s godot --headless --path prophecy_godot -s tools/bot_batch.gd` (같은 run_id면 완료 행을 건너뛰고 재개; 캐시 키(git HEAD·데이터·프로필·설정·엔진·OS)가 다르면 무효화 메시지). 결과 원본: `docs/sim/bot_runs/%s/results.jsonl`, 실패 전투·표본 성공 전투의 입력 기록: `replays/`(`PReplay.replay`로 상태 해시 대조). OS 간 일치는 이번에 검증하지 않았다.\n\n" % [float(wall) / 1000.0, float(wall) / 1000.0 / maxf(1.0, float(done)), max_sim, budget_sec, run_id, run_id]
	md += "## 5. 관찰 결과\n\n"
	if not normal.is_empty():
		md += "### 5-1. 일반 전투(검 Lv1 고정)\n\n" + _table(rows, normal, profiles, false) + "\n"
	if not bosses.is_empty():
		md += "### 5-2. 보스(실험실 프리셋 빌드)\n\n" + _table(rows, bosses, profiles, true) + "\n"
	md += "### 5-3. seed별 짝(성공·실패가 바뀐 짝 보존)\n\n" + _pair_table(rows, scen, profiles, settings.game_seeds) + "\n"
	md += "### 5-4. 피격 태그(당시 조건, 중복 허용 — 원인 확정 아님) · 거절된 타격 · 공격 관측\n\n" + _tag_table(rows, scen, profiles) + "\n"
	md += "### 5-5. 지연(판단 간격·인식 지연·실제 최초 입력 지연)\n\n" + _latency_table(rows, scen, profiles) + "\n"
	md += "### 5-6. 준 피해(출처별, PStats 보유 시간 DPS 재사용)\n\n" + _dps_table(rows, scen, profiles) + "\n"
	md += "## 6. 사람 확인 필요\n\n- 프로필 시험값(지연·후보 수·오차)과 공통 규칙은 실측 인구 통계가 아니다. 검증 메뉴의 '이번 전투 입력 기록'으로 사람 기록 5~10회를 모아 전투 시간·피해 출처·회피 빈도/거리·Q/E와 비교해야 한다(**사람 보정 미완료**).\n- 실력 순서와 결과가 뒤집힌 seed·시나리오는 관측/판단/기술 적합성 원인 조사 대상이지 숨길 결과가 아니다. 이 표로 게임 수치를 바꾸지 않는다(원인 후보·조정 대상만 보고).\n- 태그는 '다른 방향이면 피했다'를 뜻하지 않는다. 그런 결론은 해당 입력 기록을 재생해 대안 입력을 따로 검사해야 한다.\n"
	_write(path, md)

# ---------- 실행 ----------
## opts 키 = 환경 변수 이름(PROPHECY_BOT_*) + base_dir(기본 res://docs/sim/bot_runs) + env_override(캐시 키 검사용 환경 식별 덮어쓰기, 테스트 전용). 반환 {code, rows, complete, messages}
func run(o: Dictionary = {}) -> Dictionary:
	opts = o
	t_start = Time.get_ticks_msec()
	var mode := _env("PROPHECY_BOT_MODE", "compare")
	run_id = _env("PROPHECY_BOT_RUN_ID", Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", ""))
	run_dir = String(o.get("base_dir", "res://docs/sim/bot_runs")).path_join(run_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	env_info = _env_info()
	for k in o.get("env_override", {}):
		env_info[String(k)] = o.env_override[k]
	_write(run_dir.path_join("git_head.txt"), "%s\ndirty_prophecy_godot=%s\n" % [String(env_info.git_head), str(env_info.dirty)])
	budget_sec = float(_env("PROPHECY_BOT_BUDGET_SEC", "600"))
	sample_every = int(_env("PROPHECY_BOT_SAMPLE", "5"))
	var profiles := _list(_env("PROPHECY_BOT_PROFILES", "novice,regular,skilled,balanced"))
	var seeds := _ints(_env("PROPHECY_BOT_SEEDS", "1,2,3,4,5"))
	var boss_seeds := _ints(_env("PROPHECY_BOT_BOSS_SEEDS", "1,2,3"))
	var scen := []
	for s in _list(_env("PROPHECY_BOT_SCENARIOS", "baseline_wolf25,ranged_mix,zone_mix,boss_thornmane,boss_guardian,boss_eater")):
		if String(s) == "boss3":
			scen.append_array(BOSS3_SCENARIOS)
		else:
			scen.append(s)
	var report_title := _env("PROPHECY_BOT_TITLE", "실력별 전투 봇 첫 비교(BOT_COMPARE)")
	var bot_seed_fixed := _env("PROPHECY_BOT_BOT_SEED", "")
	var max_sec := {}
	for s in scen:
		max_sec[s] = float(SCENARIOS.get(s, {}).get("max_sec", 240.0)) if _env("PROPHECY_BOT_MAX_SEC", "") == "" else float(_env("PROPHECY_BOT_MAX_SEC", ""))
	var jobs := []
	if mode == "throughput":
		for sd in range(1, 11):
			jobs.append(["baseline_wolf25", "regular", sd, sd])
		for sd in range(11, 16):
			jobs.append(["boss_thornmane", "regular", sd, sd])
		scen = ["baseline_wolf25", "boss_thornmane"]
		profiles = ["regular"]
		seeds = range(1, 11)
	else:
		for s in scen:
			var sl: Array = boss_seeds if String(SCENARIOS.get(s, {}).get("kind", "")) == "boss" else seeds
			for p in profiles:
				for sd in sl:
					jobs.append([s, p, int(sd), int(bot_seed_fixed) if bot_seed_fixed.is_valid_int() else int(sd)])
	var settings := { "mode": mode, "scenarios": scen, "profiles": profiles, "game_seeds": seeds, "boss_seeds": boss_seeds, "bot_seed": ("fixed:" + bot_seed_fixed) if bot_seed_fixed != "" else "=game_seed", "max_sec": max_sec, "hash_every": PReplay.HASH_EVERY, "stall_sec": STALL_SEC, "sample_every": sample_every }
	var ck := _cache_key(settings)
	var meta_path := run_dir.path_join("meta.json")
	var existing := _read_rows()
	if FileAccess.file_exists(meta_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			meta = parsed
		var old: Dictionary = meta.get("cache_key", {})
		var diff := cache_diff(old, ck)
		if not existing.is_empty() and not can_resume(ck):
			diff.append("code_hash: 코드 식별 불가(unknown) — 기존 결과 재개 거부")
		if not diff.is_empty() and mode != "report":
			_msg("CACHE_INVALID run_id=%s 캐시 키 불일치: %s" % [run_id, "; ".join(diff)])
			if _env("PROPHECY_BOT_FORCE", "") == "1":
				var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
				DirAccess.rename_absolute(ProjectSettings.globalize_path(run_dir.path_join("results.jsonl")), ProjectSettings.globalize_path(run_dir.path_join("results.invalidated_%s.jsonl" % stamp)))
				_msg("PROPHECY_BOT_FORCE=1: 기존 결과를 results.invalidated_%s.jsonl로 옮기고 새로 시작" % stamp)
				existing = []
				meta = {}
			else:
				_msg("무효화: 같은 run_id로 재개할 수 없다. 새 PROPHECY_BOT_RUN_ID를 쓰거나 PROPHECY_BOT_FORCE=1로 기존 결과를 밀어낸다.")
				return { "code": 2, "rows": existing, "complete": false, "messages": messages }
	if meta.is_empty():
		meta = { "run_id": run_id, "created": Time.get_datetime_string_from_system(), "cache_key": ck, "settings": settings, "env": env_info, "complete": false, "rows_done": 0, "wall_ms_total": 0, "warnings": [] }
	if mode == "report":
		_report(existing, settings, run_dir.path_join("summary.md"), "실력 봇 비교(run %s)" % run_id)
		var rp0 := _env("PROPHECY_BOT_REPORT", "")
		if rp0 != "":
			_report(existing, settings, rp0, report_title)
		return { "code": 0, "rows": existing, "complete": bool(meta.get("complete", false)), "messages": messages }
	var done_keys := {}
	for r in existing:
		done_keys[_key(r)] = true
	success_n = existing.size()
	printerr("bot_batch: run_id=%s mode=%s jobs=%d done=%d budget=%.0fs head=%s dirty=%s data=%s profiles=%s" % [run_id, mode, jobs.size(), existing.size(), budget_sec, String(env_info.git_head).substr(0, 8), str(env_info.dirty), String(env_info.data_hash).substr(0, 8), String(env_info.profile_hash)])
	_save_meta(false, existing.size())
	var rows := existing.duplicate()
	var did := 0
	var stopped := false
	for j in jobs:
		var key := "%s|%s|%d|%d" % [String(j[0]), String(j[1]), int(j[2]), int(j[3])]
		if done_keys.has(key):
			continue
		var elapsed := float(Time.get_ticks_msec() - t_start + int(meta.get("wall_ms_total", 0))) / 1000.0
		if elapsed > budget_sec:
			_msg("BUDGET_EXCEEDED %.0fs > %.0fs: 완료 %d/%d. 재개: PROPHECY_BOT_RUN_ID=%s 로 같은 명령을 다시 실행(완료 행은 건너뜀). 예산 변경: PROPHECY_BOT_BUDGET_SEC" % [elapsed, budget_sec, rows.size(), jobs.size(), run_id])
			stopped = true
			break
		var row := fight(String(j[0]), String(j[1]), int(j[2]), int(j[3]))
		_append_row(row)
		rows.append(row)
		done_keys[key] = true
		did += 1
		printerr("done %s %s g%d b%d: %s %.1fs hp %.0f kills %d wall %dms" % [String(row.scenario), String(row.profile), int(row.game_seed), int(row.bot_seed), String(row.status), float(row.sim_sec), float(row.get("hp", 0.0)), int(row.get("kills", 0)), int(row.wall_ms)])
		if did % 5 == 0:
			_save_meta(false, rows.size())
	var complete := rows.size() >= jobs.size() and not stopped
	_save_meta(complete, rows.size())
	if mode == "throughput":
		var wb := []
		var wz := []
		var ms := 0.0
		for r in rows:
			ms = maxf(ms, float(r.sim_sec))
			if String(r.scenario) == "baseline_wolf25":
				wb.append(float(r.wall_ms))
			else:
				wz.append(float(r.wall_ms))
		var total_ms := 0.0
		for r in rows:
			total_ms += float(r.wall_ms)
		var fpm := float(rows.size()) / maxf(1e-6, total_ms / 60000.0)
		var est45 := (avg(wb) * 45.0) / 1000.0
		var est_boss := (avg(wz) * 27.0) / 1000.0
		var log_bytes := FileAccess.get_file_as_bytes(run_dir.path_join("results.jsonl")).size()
		printerr("THROUGHPUT fights=%d fights/min=%.1f avg_wall_baseline=%.0fms avg_wall_boss=%.0fms max_sim=%.1fs peak_mem=%.1fMB results_jsonl=%dB → 45전투(기준 평균 기준) 예상 %.0fs, 보스 27전투 예상 %.0fs" % [rows.size(), fpm, avg(wb), avg(wz), ms, float(OS.get_static_memory_peak_usage()) / 1048576.0, log_bytes, est45, est_boss])
		meta.throughput = { "fights": rows.size(), "fights_per_min": fpm, "avg_wall_baseline_ms": avg(wb), "avg_wall_boss_ms": avg(wz), "max_sim_sec": ms, "peak_mem_mb": float(OS.get_static_memory_peak_usage()) / 1048576.0, "results_bytes": log_bytes, "est_45_sec": est45, "est_boss27_sec": est_boss }
		_write(meta_path, JSON.stringify(meta, "  "))
	_report(rows, settings, run_dir.path_join("summary.md"), "실력 봇 비교(run %s)" % run_id)
	var rp := _env("PROPHECY_BOT_REPORT", "")
	if rp != "" and complete:
		_report(rows, settings, rp, report_title)
	_msg("bot_batch: %s rows=%d/%d wall=%.1fs(이번 실행 %d행) → %s" % ["complete" if complete else "partial", rows.size(), jobs.size(), float(int(meta.get("wall_ms_total", 0))) / 1000.0, did, run_dir])
	return { "code": 0 if complete else 3, "rows": rows, "complete": complete, "messages": messages, "did": did }
