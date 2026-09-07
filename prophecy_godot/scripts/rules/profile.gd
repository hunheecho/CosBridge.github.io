class_name PProfile
extends RefCounted
## 영구 프로필(회차 밖 성장, data/meta.json — 시험값): 탐험 기록 → 영구 레벨, 해금(레벨 OR 도전), 특성 선택, 처리한 보상 이벤트.
## 회차 저장(PSave)과 별도 파일 `user://prophecy_profile_v1.json` 하나에 kind별(legacy/trial) 프로필을 함께 둔다(서로 지우지 않는다).
## 규칙: 기록·해금은 회차 중 즉시 프로필에 쓰되 후보 반영은 다음 새 회차(run.unlocks 스냅샷)부터. 이벤트 ID(events_done)로 저장/재도전/불러오기에도 1회만 지급.
## 봇·시험실·즉시 관문·검증 회차는 run.profileEligible=false라 아무것도 기록하지 않는다(eligible()).
## profile dict: { version, kind, records, events_done{id:true}, challenges{id:true}, progress{id:{event:true}}, traits{"1":id|null,"5":..,"10":..,"15":..}, runs, created_at, updated_at }

const SCHEMA := "prophecy_profile/1"
const VERSION := 1
const DEFAULT_PATH := "user://prophecy_profile_v1.json"
const KINDS := ["legacy", "trial"]

static var _path: String = DEFAULT_PATH

static func M() -> Dictionary: return PCatalog.meta()

## 저장 경로 변경(PROPHECY_UI_SMOKE·테스트는 별도 파일). 실제 사용자 프로필을 건드리지 않기 위한 장치. 이름은 Resource.set_path()·get_path()와 겹치지 않게(GDScript 자체가 Resource라 겹치면 스크립트 경로가 바뀐다)
static func use_path(p: String) -> void:
	_path = p

static func profile_path() -> String:
	return _path

static func tmp_path() -> String:
	return _path + ".tmp"

# ---------- 프로필 생성·정규화 ----------
static func new_profile(kind: String) -> Dictionary:
	var k := kind if KINDS.has(kind) else "trial"
	var traits := {}
	for row in PCatalog.trait_rows():
		traits[str(int(row.level))] = null
	return { "version": VERSION, "kind": k, "records": 0, "events_done": {}, "challenges": {}, "progress": {}, "traits": traits, "runs": 0, "created_at": 0, "updated_at": 0 }

## JSON에서 읽은 값의 정수·형식 복구(제자리)
static func _normalize(p: Dictionary) -> Dictionary:
	var base := new_profile(String(p.get("kind", "trial")))
	for k in base:
		if not p.has(k):
			p[k] = base[k]
	p.version = int(p.version)
	p.records = float(p.records) # 10일 본편은 하루 2/3 기록(소수 유지)
	p.runs = int(p.get("runs", 0))
	p.created_at = int(p.get("created_at", 0))
	p.updated_at = int(p.get("updated_at", 0))
	for k in (p.events_done as Dictionary).keys():
		p.events_done[k] = true
	for k in (p.challenges as Dictionary).keys():
		p.challenges[k] = true
	for row in PCatalog.trait_rows():
		var key := str(int(row.level))
		if not (p.traits as Dictionary).has(key):
			p.traits[key] = null
	return p

# ---------- 파일 ----------
static func _empty_doc() -> Dictionary:
	return { "schema": SCHEMA, "active": "", "profiles": {} }

static func load_all() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return _empty_doc()
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return _empty_doc()
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or String(parsed.get("schema", "")) != SCHEMA or typeof(parsed.get("profiles", null)) != TYPE_DICTIONARY:
		push_error("프로필 파일 형식 불일치(무시): " + _path)
		return _empty_doc()
	return parsed

static func exists() -> bool:
	return FileAccess.file_exists(_path)

## 처음 여는 사용자의 기본 종류: 기존 회차 저장·처치 기록이 있으면 legacy(기존 공개 콘텐츠 유지), 없으면 trial(새 시험 프로필)
static func default_kind() -> String:
	return "legacy" if (PSave.exists() or FileAccess.file_exists(PSave.RECORDS_PATH)) else "trial"

static func active_kind() -> String:
	var doc := load_all()
	var k := String(doc.get("active", ""))
	return k if KINDS.has(k) else default_kind()

## 활성 프로필(kind ""면 파일의 active, 없으면 default_kind). 파일에 없으면 새 프로필(저장은 하지 않는다)
static func load(kind: String = "") -> Dictionary:
	var doc := load_all()
	var k := kind if KINDS.has(kind) else String(doc.get("active", ""))
	if not KINDS.has(k):
		k = default_kind()
	var P: Dictionary = doc.profiles
	if P.has(k) and typeof(P[k]) == TYPE_DICTIONARY:
		return _normalize(P[k])
	return new_profile(k)

## 저장(임시 파일 → 이름 변경). 같은 파일의 다른 kind 프로필은 그대로 둔다
static func save(profile: Dictionary, make_active: bool = true) -> bool:
	var doc := load_all()
	var k := String(profile.get("kind", "trial"))
	var now := int(Time.get_unix_time_from_system())
	if int(profile.get("created_at", 0)) == 0:
		profile.created_at = now
	profile.updated_at = now
	doc.profiles[k] = profile
	if make_active or String(doc.get("active", "")) == "":
		doc.active = k
	var f := FileAccess.open(tmp_path(), FileAccess.WRITE)
	if f == null:
		push_error("프로필 저장 실패(열기): " + tmp_path())
		return false
	f.store_string(JSON.stringify(doc))
	f.close()
	var d := DirAccess.open(_path.get_base_dir())
	if d == null:
		push_error("프로필 저장 실패(폴더)")
		return false
	if d.file_exists(_path.get_file()):
		d.remove(_path.get_file())
	var err := d.rename(tmp_path().get_file(), _path.get_file())
	if err != OK:
		push_error("프로필 저장 실패(이름 변경): %d" % err)
		return false
	return true

## 활성 종류 전환(다른 종류의 프로필은 삭제하지 않는다). 전환된 프로필을 돌려준다
static func set_active(kind: String) -> Dictionary:
	var p := PProfile.load(kind) # 전역 load()(Resource)와 구분
	save(p, true)
	return p

## 파일 삭제(테스트 전용)
static func clear() -> void:
	var d := DirAccess.open(_path.get_base_dir())
	if d == null:
		return
	if d.file_exists(_path.get_file()):
		d.remove(_path.get_file())
	if d.file_exists(tmp_path().get_file()):
		d.remove(tmp_path().get_file())

# ---------- 레벨 ----------
static func max_level() -> int:
	return int(M().levels.max)

## 누적 기록 → 영구 레벨(문턱 4,4,6,6,… 누적)
static func level_of(records: float) -> int:
	var T: Array = M().levels.thresholds
	var lv := 1
	var need := 0
	for t in T:
		need += int(t)
		if records + 1e-6 >= float(need): # 2/3 기록 누적의 부동소수 오차 허용
			lv += 1
		else:
			break
	return mini(lv, max_level())

static func level(profile: Dictionary) -> int:
	return level_of(float(profile.get("records", 0)))

## 다음 레벨 정보 {level, next, have, need, remain}. 최대면 next = level
static func next_level(profile: Dictionary) -> Dictionary:
	var T: Array = M().levels.thresholds
	var lv := level(profile)
	var have: float = float(profile.get("records", 0))
	if lv >= max_level():
		return { "level": lv, "next": lv, "have": have, "need": have, "remain": 0.0 }
	var need := 0
	for i in lv:
		need += int(T[i])
	return { "level": lv, "next": lv + 1, "have": have, "need": need, "remain": maxf(0.0, float(need) - have) }

# ---------- 해금 ----------
static func _entry_ok(profile: Dictionary, entry: Dictionary, lv: int) -> bool:
	if entry.has("level") and lv >= int(entry.level):
		return true
	if entry.has("challenge") and bool((profile.get("challenges", {}) as Dictionary).get(String(entry.challenge), false)):
		return true
	return false

static func _open_cats(profile: Dictionary) -> Array:
	var P := PCatalog.meta_profiles()
	var k := String(profile.get("kind", "trial"))
	return (P[k].get("open", []) as Array) if P.has(k) else []

## 지금 열린 것 전부: { weapons[], start_weapons[], mods{weapon:[mod]}, commons[], q_variants[], e_skills[], e_variants{e:[v]}, equipment[], recipes[], level }
static func unlocked(profile: Dictionary) -> Dictionary:
	var lv := level(profile)
	var U := PCatalog.meta_unlocks()
	var open := _open_cats(profile)
	var out := { "weapons": [], "start_weapons": [], "mods": {}, "commons": [], "q_variants": [], "e_skills": [], "e_variants": {}, "equipment": [], "recipes": [], "level": lv }
	var W := PCatalog.weapons()
	for id in U.weapons:
		if open.has("weapons") or _entry_ok(profile, U.weapons[id], lv):
			(out.weapons as Array).append(String(id))
	for id in U.start_weapons:
		if _entry_ok(profile, U.start_weapons[id], lv) and (out.weapons as Array).has(String(id)):
			(out.start_weapons as Array).append(String(id))
	for wid in U.mods:
		if String(wid) == "note" or not W.has(String(wid)):
			continue
		if not (out.weapons as Array).has(String(wid)):
			continue # 잠긴 기술의 개조는 세지 않는다("접근 가능한 기술마다 2개")
		var rule: Dictionary = U.mods[wid]
		var list := []
		if open.has("mods"):
			for m in PCatalog.mods_of(String(wid)):
				list.append(String(m))
		else:
			for m in rule.get("base", []):
				list.append(String(m))
			var third := String(rule.get("third", ""))
			if third != "" and bool((profile.get("challenges", {}) as Dictionary).get("mod3:" + String(wid), false)):
				list.append(third)
		out.mods[String(wid)] = list
	for id in U.commons:
		if open.has("commons") or _entry_ok(profile, U.commons[id], lv):
			(out.commons as Array).append(String(id))
	for id in U.q_variants:
		if open.has("q_variants") or _entry_ok(profile, U.q_variants[id], lv):
			(out.q_variants as Array).append(String(id))
	var SK := PCatalog.skills()
	for id in U.e_skills:
		if open.has("e_skills") or _entry_ok(profile, U.e_skills[id], lv):
			(out.e_skills as Array).append(String(id))
			var vs := []
			if SK.has(String(id)):
				for v in SK[String(id)].get("variants", {}):
					vs.append(String(v))
			out.e_variants[String(id)] = vs
	for id in U.equipment:
		if open.has("equipment") or _entry_ok(profile, U.equipment[id], lv):
			(out.equipment as Array).append(String(id))
	for id in U.recipes:
		if open.has("recipes") or _entry_ok(profile, U.recipes[id], lv):
			(out.recipes as Array).append(String(id))
	return out

## 도감 개수: { weapons{have,total}, start{have,total}, mods{have,total}, commons{}, e{}, equipment{}, recipes{} }
static func counts(profile: Dictionary) -> Dictionary:
	var u := unlocked(profile)
	var U := PCatalog.meta_unlocks()
	var mods_have := 0
	var mods_total := 0
	for wid in u.mods:
		mods_have += (u.mods[wid] as Array).size()
	for wid in U.mods:
		if String(wid) != "note":
			mods_total += PCatalog.mods_of(String(wid)).size()
	return {
		"weapons": { "have": (u.weapons as Array).size(), "total": (U.weapons as Dictionary).size() },
		"start": { "have": (u.start_weapons as Array).size(), "total": (U.start_weapons as Dictionary).size() },
		"mods": { "have": mods_have, "total": mods_total },
		"commons": { "have": (u.commons as Array).size(), "total": (U.commons as Dictionary).size() },
		"e": { "have": (u.e_skills as Array).size(), "total": (U.e_skills as Dictionary).size() },
		"q_variants": { "have": (u.q_variants as Array).size(), "total": (U.q_variants as Dictionary).size() },
		"equipment": { "have": (u.equipment as Array).size(), "total": (U.equipment as Dictionary).size() },
		"recipes": { "have": (u.recipes as Array).size(), "total": (U.recipes as Dictionary).size() },
	}

## 잠긴 항목의 조건 문구(해금 규칙 항목에서). 예: "영구 Lv3", "도전: … (또는 Lv7)"
static func unlock_text(cat: String, id: String) -> String:
	var U := PCatalog.meta_unlocks()
	if cat == "mods":
		return "도전: " + String(PCatalog.challenges()["mod3:" + id].cond)
	if not (U.has(cat) and (U[cat] as Dictionary).has(id)):
		return ""
	var e: Dictionary = U[cat][id]
	var parts := []
	if e.has("challenge"):
		var C := PCatalog.challenges()
		parts.append("도전: " + String(C[String(e.challenge)].cond) if C.has(String(e.challenge)) else String(e.challenge))
	elif e.has("level"):
		parts.append("영구 Lv%d" % int(e.level))
	return " · ".join(parts)

## 다음 레벨에 새로 열리는 것 한 줄(레벨 규칙 항목만)
static func next_unlock_line(profile: Dictionary) -> String:
	var nl := next_level(profile)
	if int(nl.next) <= int(nl.level):
		return "최대 레벨"
	var target := int(nl.next)
	var U := PCatalog.meta_unlocks()
	var names := []
	var W := PCatalog.weapons()
	for id in U.weapons:
		if int(U.weapons[id].get("level", 0)) == target:
			names.append(String(W[String(id)].name))
	for id in U.start_weapons:
		if int(U.start_weapons[id].get("level", 0)) == target and not names.has(String(W[String(id)].name)):
			names.append("시작 선택 " + String(W[String(id)].name))
	for id in U.commons:
		if int(U.commons[id].get("level", 0)) == target:
			names.append(String(PCatalog.commons()[String(id)].name))
	for id in U.q_variants:
		if int(U.q_variants[id].get("level", 0)) == target:
			names.append("Q " + String(PCatalog.skills().slowfield.variants[String(id)].name))
	for id in U.e_skills:
		if int(U.e_skills[id].get("level", 0)) == target:
			names.append("E " + String(PCatalog.skills()[String(id)].name))
	for id in U.equipment:
		if int(U.equipment[id].get("level", 0)) == target:
			names.append(String(PCatalog.equipment()[String(id)].name) + "(대체)")
	for id in U.recipes:
		if int(U.recipes[id].get("level", 0)) == target:
			names.append(String(PCatalog.crafted_equipment()[String(id)].name) + " 제작법(대체)")
	for row in PCatalog.trait_rows():
		if int(row.level) == target:
			names.append("특성 행 '%s'" % String(row.name))
	return "Lv%d: %s" % [target, (", ".join(names) if names.size() > 0 else "없음")]

## 회차 스냅샷(run.unlocks)에 대한 후보 자격. unlocks 키가 없는 회차(봇·시험실·옛 저장)는 전부 열린 것으로 본다
static func run_unlock_ok(run: Dictionary, cat: String, id: String, sub: String = "") -> bool:
	if not run.has("unlocks") or typeof(run.unlocks) != TYPE_DICTIONARY:
		return true
	var U: Dictionary = run.unlocks
	match cat:
		"mods":
			return ((U.get("mods", {}) as Dictionary).get(id, []) as Array).has(sub)
		"e_variants":
			return ((U.get("e_variants", {}) as Dictionary).get(id, []) as Array).has(sub)
		_:
			if not U.has(cat):
				return true
			return (U[cat] as Array).has(id)

# ---------- 특성 ----------
static func trait_row(level_key: int) -> Dictionary:
	for row in PCatalog.trait_rows():
		if int(row.level) == level_key:
			return row
	return {}

static func row_unlocked(profile: Dictionary, level_key: int) -> bool:
	return level(profile) >= level_key

## 선택된 특성 ID(열린 행만, 행 순서)
static func selected_traits(profile: Dictionary) -> Array:
	var out := []
	var lv := level(profile)
	for row in PCatalog.trait_rows():
		if lv < int(row.level):
			continue
		var v = (profile.get("traits", {}) as Dictionary).get(str(int(row.level)), null)
		if v != null and String(v) != "" and (row.ids as Array).has(String(v)):
			out.append(String(v))
	return out

## 장착 가능 여부 {ok, reason}. id ""는 해제
static func can_equip_trait(profile: Dictionary, level_key: int, id: String) -> Dictionary:
	var row := trait_row(level_key)
	if row.is_empty():
		return { "ok": false, "reason": "없는 행" }
	if not row_unlocked(profile, level_key):
		return { "ok": false, "reason": "영구 Lv%d에 열림" % level_key }
	if id == "":
		return { "ok": true, "reason": "" }
	if not (row.ids as Array).has(id):
		return { "ok": false, "reason": "이 행의 특성이 아님" }
	var cur := selected_traits(profile)
	var cur_row = (profile.traits as Dictionary).get(str(level_key), null)
	var n := cur.size() - (1 if (cur_row != null and String(cur_row) != "") else 0)
	if n + 1 > int(PCatalog.traits().max_equipped):
		return { "ok": false, "reason": "최대 %d개" % int(PCatalog.traits().max_equipped) }
	return { "ok": true, "reason": "" }

## 특성 선택(출발 전 무료 재선택). 성공 여부
static func set_trait(profile: Dictionary, level_key: int, id: String) -> bool:
	var c := can_equip_trait(profile, level_key, id)
	if not bool(c.ok):
		push_error("특성 선택 불가: " + String(c.reason))
		return false
	profile.traits[str(level_key)] = (id if id != "" else null)
	return true

## 특성 ID 목록 → 합산 효과(PBuild가 읽는다). 같은 키는 더한다(행마다 서로 다른 키라 실제 중복 없음)
static func trait_effects(ids: Array) -> Dictionary:
	var D := PCatalog.trait_defs()
	var out := {}
	for id in ids:
		if not D.has(String(id)):
			continue
		for k in D[String(id)].eff:
			out[k] = float(out.get(k, 0.0)) + float(D[String(id)].eff[k])
	return out

# ---------- 기록·도전 ----------
## 회차가 영구 기록 대상인지: 프로필로 만든 실제 회차만(봇·시험실·즉시 관문·검증 회차 제외)
static func eligible(run: Dictionary) -> bool:
	return bool(run.get("profileEligible", false)) and not bool(run.get("quick", false)) and not bool(run.get("lab", false))

## 이벤트 1회 지급. 이미 처리했으면 false
static func record_event(profile: Dictionary, event_id: String, amount: float) -> bool:
	if (profile.events_done as Dictionary).has(event_id):
		return false
	profile.events_done[event_id] = true
	profile.records = float(profile.records) + float(amount)
	return true

## 도전 달성(1회). 새로 달성했으면 true
static func complete_challenge(profile: Dictionary, id: String) -> bool:
	if bool((profile.challenges as Dictionary).get(id, false)):
		return false
	profile.challenges[id] = true
	return true

## 진행형 도전: 서로 다른 event_id마다 1 진행, progress_max에 닿으면 달성. 새로 달성했으면 true
static func progress_challenge(profile: Dictionary, id: String, event_id: String) -> bool:
	if bool((profile.challenges as Dictionary).get(id, false)):
		return false
	if not (profile.progress as Dictionary).has(id):
		profile.progress[id] = {}
	var P: Dictionary = profile.progress[id]
	P[event_id] = true
	var need: int = int(PCatalog.challenges()[id].get("progress_max", 1))
	if P.size() >= need:
		return complete_challenge(profile, id)
	return false

static func challenge_progress(profile: Dictionary, id: String) -> int:
	return ((profile.get("progress", {}) as Dictionary).get(id, {}) as Dictionary).size()

static func _dot_damage(st: CombatState) -> float:
	var s := 0.0
	for k in st.metrics.dmg:
		if String(k).begins_with("dot:"):
			s += float(st.metrics.dmg[k])
	return s

static func _fire_damage(st: CombatState) -> float:
	return float(st.metrics.dmg.get("weapon:ember", 0.0)) + float(st.metrics.dmg.get("common:ember", 0.0))

static func _boss_index(run: Dictionary, boss_id: String) -> int:
	var bosses: Array = PRun.mode_def(run).bosses
	for i in bosses.size():
		if String(bosses[i].id) == boss_id:
			return i
	return -1

## 전투 승리(일반·보스 공통)에서 검사하는 도전. out.challenges에 새로 달성한 ID를 더한다
static func _challenges_on_win(profile: Dictionary, run: Dictionary, st: CombatState, out: Dictionary, is_boss: bool) -> void:
	var g: Dictionary = run.growth
	var dmg: Dictionary = st.metrics.dmg
	var elite_win: bool = int(st.stats.elite_kills) > 0
	for w in g.weapons:
		var wid := String(w.id)
		if int(w.level) >= 3 and float(dmg.get("weapon:" + wid, 0.0)) > 0.0 and PCatalog.challenges().has("mod3:" + wid):
			if complete_challenge(profile, "mod3:" + wid):
				(out.challenges as Array).append("mod3:" + wid)
	if elite_win and PGrowth.has_fire_source(g) and _fire_damage(st) > 0.0:
		if complete_challenge(profile, "flare"):
			(out.challenges as Array).append("flare")
	if _dot_damage(st) > 0.0:
		if complete_challenge(profile, "eq:ember_sword"):
			(out.challenges as Array).append("eq:ember_sword")
	if int(st.stats.get("field_hits", 0)) > 0:
		if progress_challenge(profile, "eq:chrono_staff", "run:%d:fight:%d" % [int(run.seed), int(st.seed_value)]):
			(out.challenges as Array).append("eq:chrono_staff")
	var armor = (run.get("equipment", {}) as Dictionary).get("armor", null)
	if elite_win and armor != null and String(armor) == "guardian_armor":
		if complete_challenge(profile, "recipe:moon_armor"):
			(out.challenges as Array).append("recipe:moon_armor")
	if not is_boss:
		return
	var idx := _boss_index(run, st.boss_id)
	var shield = (run.get("equipment", {}) as Dictionary).get("shield", null)
	if idx == 0 and complete_challenge(profile, "eq:time_shield"):
		(out.challenges as Array).append("eq:time_shield")
	if idx == 0 and _dot_damage(st) > 0.0 and complete_challenge(profile, "recipe:bloodmoon_sword"):
		(out.challenges as Array).append("recipe:bloodmoon_sword")
	if idx == 1 and int(st.stats.get("field_hits", 0)) > 0 and complete_challenge(profile, "recipe:echo_staff"):
		(out.challenges as Array).append("recipe:echo_staff")
	if shield != null and (String(shield) == "iron_shield" or String(shield) == "emergency_shield") and complete_challenge(profile, "recipe:reprisal_shield"):
		(out.challenges as Array).append("recipe:reprisal_shield")
	if idx == 1 and int(st.stats.special_uses) > 0 and int(st.stats.e_uses) > 0 and complete_challenge(profile, "recipe:relay_shield"):
		(out.challenges as Array).append("recipe:relay_shield")

static func _diff_unlocked(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for cat in ["weapons", "start_weapons", "commons", "q_variants", "e_skills", "equipment", "recipes"]:
		var added := []
		for id in after[cat]:
			if not (before[cat] as Array).has(id):
				added.append(String(id))
		if added.size() > 0:
			out[cat] = added
	var mods := []
	for wid in after.mods:
		for m in after.mods[wid]:
			if not ((before.mods as Dictionary).get(wid, []) as Array).has(m):
				mods.append("%s:%s" % [String(wid), String(m)])
	if mods.size() > 0:
		out["mods"] = mods
	return out

## 회차 결과를 프로필에 반영(제자리, 저장은 호출자). kind: "victory"(ctx {sortie, st}) · "boss"(ctx {st}) · "return"(ctx {sortie}).
## 돌려주는 값: { eligible, records(이번 지급), events[], challenges[], unlocked{cat:[id]}, level_before, level_after }
static func award_from_run(profile: Dictionary, run: Dictionary, kind: String, ctx: Dictionary) -> Dictionary:
	var out := { "eligible": eligible(run), "records": 0, "events": [], "challenges": [], "unlocked": {}, "level_before": level(profile), "level_after": level(profile) }
	if not bool(out.eligible):
		return out
	var before := unlocked(profile)
	var R := PCatalog.meta_records_for(String(run.get("mode", "trio"))) # 회차 구조별(10일 본편: 하루 2/3)
	var seed_v := int(run.seed)
	match kind:
		"victory":
			var st: CombatState = ctx.get("st", null)
			var sortie: Dictionary = ctx.get("sortie", {})
			if st == null or st.status != "won" or sortie.is_empty():
				return out
			var normal: bool = not bool(sortie.get("deep", false)) and not bool(sortie.get("mission", false)) and sortie.get("eventFight", null) == null
			var day := int(run.day)
			if normal and day >= 1 and day <= int(R.day_max):
				var ev := "run:%d:day:%d" % [seed_v, day]
				if record_event(profile, ev, float(R.day_win)):
					out.records = float(out.records) + float(R.day_win)
					(out.events as Array).append(ev)
			_challenges_on_win(profile, run, st, out, false)
		"boss":
			var st: CombatState = ctx.get("st", null)
			if st == null or st.status != "won" or st.boss_id == "":
				return out
			var ev := "run:%d:boss:%s" % [seed_v, st.boss_id]
			if record_event(profile, ev, float(R.boss_first)):
				out.records = float(out.records) + float(R.boss_first)
				(out.events as Array).append(ev)
			if String(run.get("phase", "")) == "cleared":
				var ev2 := "run:%d:clear" % seed_v
				if record_event(profile, ev2, float(R.clear)):
					out.records = float(out.records) + float(R.clear)
					(out.events as Array).append(ev2)
			_challenges_on_win(profile, run, st, out, true)
		"return":
			var sortie: Dictionary = ctx.get("sortie", {})
			if sortie.is_empty() or not bool(sortie.get("settled", false)) or bool(sortie.get("lost", false)):
				return out
			if bool(sortie.get("deep", false)) and bool(sortie.get("deepRewarded", false)):
				if complete_challenge(profile, "eq:expedition_armor"):
					(out.challenges as Array).append("eq:expedition_armor")
				if int(sortie.get("encounters", 0)) >= 2 and complete_challenge(profile, "recipe:renewal_coat"):
					(out.challenges as Array).append("recipe:renewal_coat")
	out.unlocked = _diff_unlocked(before, unlocked(profile))
	out.level_after = level(profile)
	return out

## 결과 화면 한 줄: "이번 회차 영구 기록: +N (다음 회차부터 반영)" + 새로 열린 것
static func award_text(a: Dictionary) -> String:
	if a.is_empty() or not bool(a.get("eligible", false)):
		return ""
	var parts := []
	if float(a.get("records", 0)) > 0.0:
		parts.append("이번 회차 %s: +%s (다음 회차부터 반영)" % [String(PCatalog.meta_records().name), _fmt_rec(float(a.records))])
	if int(a.get("level_after", 1)) > int(a.get("level_before", 1)):
		parts.append("영구 Lv%d → Lv%d" % [int(a.level_before), int(a.level_after)])
	var names := unlocked_names(a.get("unlocked", {}))
	if names.size() > 0:
		parts.append("새로 열림: " + ", ".join(names))
	return " · ".join(parts)

## 해금 diff → 이름 목록
static func unlocked_names(diff: Dictionary) -> Array:
	var names := []
	var W := PCatalog.weapons()
	for cat in diff:
		for id in diff[cat]:
			var sid := String(id)
			match String(cat):
				"weapons": names.append(String(W[sid].name))
				"start_weapons": names.append("시작 선택 " + String(W[sid].name))
				"mods":
					var pr := sid.split(":")
					names.append("%s 개조 %s" % [String(W[pr[0]].name), String(W[pr[0]].mods[pr[1]].name)])
				"commons": names.append(String(PCatalog.commons()[sid].name))
				"q_variants": names.append("Q " + String(PCatalog.skills().slowfield.variants[sid].name))
				"e_skills": names.append("E " + String(PCatalog.skills()[sid].name))
				"equipment": names.append(String(PCatalog.equipment()[sid].name))
				"recipes": names.append(String(PCatalog.crafted_equipment()[sid].name) + " 제작법")
	return names

## 기록 수 표시(소수는 셋째 자리 버림 없이 1자리로): 6.0 → "6", 4.67 → "4.7"
static func _fmt_rec(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 1e-6 else "%.1f" % v
