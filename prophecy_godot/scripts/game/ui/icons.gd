class_name PIcons
extends RefCounted
## 실제 게임 ID → 아이콘의 중앙 매핑(표시 전용). 모든 화면(전투 HUD·마을·선택 카드·상점/대장간·통계)은 여기만 쓴다.
## 매핑 표는 data/icons.json, 그림 파일은 assets/icons/png128(주)·png64(작은 칸)·svg(원본). 규칙 수치는 여기서 계산하지 않는다.
##
## 키 형식(게임 데이터 ID 그대로):
##   weapon:<id>            자동기술 10종 (sword·spear·daggers·bow·hammer·blades·orb·frost·ember·mine)
##   mod:<weapon>:<mod>     개조 30종 (sword:cross · spear:split · frost:fan …)
##   action:dodge           회피
##   skill:q  / skill:slowfield   Q 감속장
##   skill:e:<id>           E 기술(ward = 수호 결계)
##   skill:e:<id>:<variant> E 변형
##   common:<id> / passive:<id> / equip:<id> / reward:<id>
##
## 아이콘이 없는 ID는 절대 다른 효과의 아이콘으로 대체하지 않는다(오인 금지).
## 없는 경우 has(key) = false 이고, 화면은 중립 자리표시 기호 + 실제 한국어 이름을 그린다(PIconTile).
## 누락 목록은 coverage()가 기계 판독 형태로 돌려준다(tests/hud_tests.gd·docs/sim/ICON_COVERAGE.md).

const DATA_PATH := "res://data/icons.json"

static var _data: Dictionary = {}
static var _tex64: Dictionary = {}
static var _tex128: Dictionary = {}

static func data() -> Dictionary:
	if not _data.is_empty():
		return _data
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("아이콘 표 없음: " + DATA_PATH)
		_data = { "map": {}, "alias": {} }
		return _data
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("아이콘 표 파싱 실패: " + DATA_PATH)
		_data = { "map": {}, "alias": {} }
		return _data
	_data = parsed
	return _data

## 표기 흔들림(skill:q ↔ skill:slowfield, skill:e:ward ↔ skill:ward)을 하나의 키로 모은다
static func canon(key: String) -> String:
	var k := key
	var al: Dictionary = data().get("alias", {})
	if al.has(k):
		k = String(al[k])
	if k.begins_with("skill:e:"):
		var rest := k.substr(8)
		var cut := rest.find(":")
		var base := rest.substr(0, cut) if cut >= 0 else rest
		var direct := "skill:" + base
		if (data().get("map", {}) as Dictionary).has(direct) and cut < 0:
			return direct
	return k

static func entry(key: String) -> Dictionary:
	var m: Dictionary = data().get("map", {})
	var k := canon(key)
	return m[k] if m.has(k) else {}

static func has(key: String) -> bool:
	return not entry(key).is_empty()

## 아이콘 그림. 없으면 null(호출자는 자리표시 기호를 그린다). big=false면 png64
static func texture(key: String, big: bool = true) -> Texture2D:
	var e := entry(key)
	if e.is_empty():
		return null
	var file := String(e.file)
	var cache: Dictionary = _tex128 if big else _tex64
	if cache.has(file):
		return cache[file]
	var dir := String(data().get("dir128" if big else "dir64", ""))
	var tex: Texture2D = load(dir + "/" + file + ".png") as Texture2D
	cache[file] = tex
	return tex

## 흑백(재사용 대기 중) 아이콘. 같은 그림을 채도 0으로 바꿔 만든다(그림을 다른 효과로 바꾸지 않는다).
## 결과를 정적 캐시에 두지 않는다: 만든 이미지 자원을 부르는 쪽(PIconTile 노드)이 들고 있다가 화면과 함께 정리한다
## — 정적 변수에 두면 렌더 서버가 내려간 뒤에 풀려 종료 때 죽는 일이 있었다(2026-09-08).
static func texture_gray(key: String, big: bool = true) -> Texture2D:
	var src := texture(key, big)
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return src
	var copy: Image = img.duplicate()
	if copy.is_compressed():
		copy.decompress()
	copy.adjust_bcs(1.0, 1.0, 0.0) # 밝기·대비 그대로, 채도 0 = 흑백
	return ImageTexture.create_from_image(copy)

## 아이콘 색(자리표시 기호에도 같은 계열을 쓰지 않는다 — 자리표시는 항상 중립 회색)
static func color(key: String) -> Color:
	var e := entry(key)
	if e.is_empty():
		return Color(0.62, 0.66, 0.72)
	return Color.html(String(e.get("color", "#ffffff")))

# ---------- 실제 게임 데이터 → 키·이름 ----------
static func weapon_key(weapon_id: String) -> String:
	return "weapon:" + weapon_id

static func mod_key(weapon_id: String, mod_id: String) -> String:
	return "mod:%s:%s" % [weapon_id, mod_id]

static func e_key(skill_id: String, variant: Variant = null) -> String:
	if variant == null or String(variant) == "":
		return "skill:e:" + skill_id
	return "skill:e:%s:%s" % [skill_id, String(variant)]

## 키 → 실제 한국어 이름(카탈로그가 먼저, 없으면 아이콘 표의 이름). 이름을 임의로 만들지 않는다
static func name_of(key: String) -> String:
	var parts := key.split(":")
	var kind := String(parts[0])
	match kind:
		"weapon":
			var W := PCatalog.weapons()
			var id := String(parts[1]) if parts.size() > 1 else ""
			if W.has(id):
				return String(W[id].name)
		"mod":
			if parts.size() >= 3:
				var W2 := PCatalog.weapons()
				var wid := String(parts[1])
				var mid := String(parts[2])
				if W2.has(wid) and (W2[wid].mods as Dictionary).has(mid):
					return String(W2[wid].mods[mid].name)
		"action":
			return "회피"
		"skill":
			var SK := PCatalog.skills()
			if parts.size() >= 3 and String(parts[1]) == "e":
				var sid := String(parts[2])
				if SK.has(sid):
					if parts.size() >= 4 and (SK[sid].get("variants", {}) as Dictionary).has(String(parts[3])):
						return "%s · %s" % [String(SK[sid].name), String(SK[sid].variants[String(parts[3])].name)]
					return String(SK[sid].name)
			var id2 := String(parts[1]) if parts.size() > 1 else ""
			if id2 == "q":
				id2 = "slowfield"
			if SK.has(id2):
				return String(SK[id2].name)
		"common":
			var CM := PCatalog.commons()
			var id3 := String(parts[1]) if parts.size() > 1 else ""
			if CM.has(id3):
				return String(CM[id3].name)
		"passive":
			var PS := PCatalog.passives()
			var id4 := String(parts[1]) if parts.size() > 1 else ""
			if PS.has(id4):
				return String(PS[id4].name)
		"equip":
			var ed := PCatalog.equipment_def(String(parts[1]) if parts.size() > 1 else "")
			if not ed.is_empty():
				return String(ed.name)
		"reward":
			var BR := PCatalog.boss_rewards()
			var id5 := String(parts[1]) if parts.size() > 1 else ""
			if BR.has(id5):
				return String(BR[id5].name)
	var e := entry(key)
	return String(e.get("name", key)) if not e.is_empty() else key

# ---------- 누락 목록(기계 판독) ----------
## 게임에 실제로 존재하는 모든 표시 대상 ID를 훑어 { total, have, missing:[{key,name,kind}] }.
## missing 은 "아이콘이 아직 없는 것"이지 "게임에 없는 것"이 아니다.
static func coverage() -> Dictionary:
	var keys: Array = []
	var W := PCatalog.weapons()
	for wid in W:
		keys.append(["weapon", weapon_key(String(wid))])
		for mid in W[wid].mods:
			keys.append(["mod", mod_key(String(wid), String(mid))])
	var SK := PCatalog.skills()
	for sid in SK:
		var d: Dictionary = SK[sid]
		keys.append(["skill", ("skill:slowfield" if String(sid) == "slowfield" else e_key(String(sid)))])
		for v in d.get("variants", {}):
			keys.append(["skill_variant", e_key(String(sid), String(v))])
	keys.append(["action", "action:dodge"])
	for cid in PCatalog.commons():
		keys.append(["common", "common:" + String(cid)])
	for pid in PCatalog.passives():
		keys.append(["passive", "passive:" + String(pid)])
	for eid in PCatalog.equipment():
		keys.append(["equipment", "equip:" + String(eid)])
	for eid2 in PCatalog.crafted_equipment():
		keys.append(["equipment", "equip:" + String(eid2)])
	for rid in PCatalog.boss_rewards():
		keys.append(["reward", "reward:" + String(rid)])
	var have: Array = []
	var missing: Array = []
	var seen := {}
	for row in keys:
		var kind := String(row[0])
		var key := String(row[1])
		if seen.has(key):
			continue
		seen[key] = true
		if has(key):
			have.append(key)
		else:
			missing.append({ "key": key, "kind": kind, "name": name_of(key) })
	missing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.key) < String(b.key))
	return { "total": seen.size(), "have": have, "missing": missing }

## 누락 목록 문서(docs/sim/ICON_COVERAGE.md). 저장에 성공하면 true
static func write_coverage_doc(path: String = "res://docs/sim/ICON_COVERAGE.md") -> bool:
	var c := coverage()
	var by_kind := {}
	for m in c.missing:
		var k := String(m.kind)
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(m)
	# 적용 목록도 종류별로 묶는다(무엇이 이미 있는지 눈으로 확인할 수 있게)
	var have_by_kind := {}
	for key in c.have:
		var e := entry(String(key))
		var hk := String(e.get("kind", "기타"))
		if not have_by_kind.has(hk):
			have_by_kind[hk] = []
		(have_by_kind[hk] as Array).append({ "key": String(key), "name": name_of(String(key)), "file": String(e.get("file", "")) })
	for hk in have_by_kind:
		(have_by_kind[hk] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.key) < String(b.key))
	var lines: Array = []
	lines.append("# 아이콘 적용 범위(ICON_COVERAGE)")
	lines.append("")
	lines.append("자동 생성(scripts/game/ui/icons.gd `PIcons.write_coverage_doc`). 그림 정본은 `assets/icons/manifest_source.json`,")
	lines.append("만드는 도구는 `tools/icon_gen.gd`(프로젝트 안에서 코드로 그린 벡터 → svg·png128·png64·data/icons.json). 최종 아트는 아니다.")
	lines.append("아이콘이 없는 항목은 다른 효과의 아이콘을 재사용하지 않고 중립 자리표시 기호 + 실제 이름으로 표시한다.")
	lines.append("")
	lines.append("- 표시 대상 ID: %d" % int(c.total))
	lines.append("- 아이콘 있음: %d" % (c.have as Array).size())
	lines.append("- 누락: %d" % (c.missing as Array).size())
	lines.append("")
	if (c.missing as Array).is_empty():
		lines.append("누락 없음. 표시 대상 ID가 늘어나면 이 문서에 다시 나타난다.")
		lines.append("")
	for k in by_kind:
		lines.append("## 누락 · %s (%d)" % [String(k), (by_kind[k] as Array).size()])
		lines.append("")
		lines.append("| ID | 이름 |")
		lines.append("| --- | --- |")
		for m in by_kind[k]:
			lines.append("| `%s` | %s |" % [String(m.key), String(m.name)])
		lines.append("")
	for k2 in have_by_kind:
		lines.append("## 적용 · %s (%d)" % [String(k2), (have_by_kind[k2] as Array).size()])
		lines.append("")
		lines.append("| ID | 이름 | 그림 파일 |")
		lines.append("| --- | --- | --- |")
		for h in have_by_kind[k2]:
			lines.append("| `%s` | %s | `%s` |" % [String(h.key), String(h.name), String(h.file)])
		lines.append("")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("\n".join(lines) + "\n")
	return true
