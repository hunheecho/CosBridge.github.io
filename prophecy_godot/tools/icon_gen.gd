extends SceneTree
## 아이콘 생성기: `assets/icons/manifest_source.json`(도형 정본, 프로젝트 안에서 코드로 그린 벡터) →
##   assets/icons/svg/<id>.svg · png128/<id>.png · png64/<id>.png · data/icons.json(중앙 매핑 정본)
## 사용: godot --headless --path prophecy_godot -s tools/icon_gen.gd
##
## 외부에서 그림을 내려받지 않는다. 도형은 manifest의 `shape`(SVG 경로)이고, 색·굵기·둥근 끝은 여기서 한 겹으로 감싼다.
## 한 그림 파일을 두 효과에 배정하지 않는다(오인 금지) — id 중복이면 실패로 끝낸다.
## 게임에 없는 ID를 매핑하면 경고를 남긴다(매핑은 실제 게임 데이터 ID만 쓴다).

const SIZE := 128
const SMALL := 64

func _svg(color: String, shape: String) -> String:
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 64 64\"><g color=\"%s\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"3.4\" stroke-linecap=\"round\" stroke-linejoin=\"round\">%s</g></svg>" % [SIZE, SIZE, color, shape]

## manifest의 kind·key → 실제 게임 데이터 ID(PIcons 키)
func _game_key(kind: String, key: String) -> String:
	match kind:
		"weapon": return "weapon:" + key
		"action": return "action:" + key
		"skill": return "skill:" + key
		"skill_variant": return "skill:e:" + key
		"mod": return "mod:" + key
		"common": return "common:" + key
		"passive": return "passive:" + key
		"equip": return "equip:" + key
		"reward": return "reward:" + key
	return kind + ":" + key

func _init() -> void:
	var f := FileAccess.open("res://assets/icons/manifest_source.json", FileAccess.READ)
	if f == null:
		printerr("manifest_source.json 없음")
		quit(1)
		return
	var rows = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(rows) != TYPE_ARRAY:
		printerr("manifest 파싱 실패")
		quit(1)
		return
	for d in ["res://assets/icons/svg", "res://assets/icons/png128", "res://assets/icons/png64"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	var map := {}
	var files := {}
	var made := 0
	var failed := []
	for r in rows:
		var id := String(r.id)
		var color := String(r.color)
		var svg := _svg(color, String(r.shape))
		if files.has(id):
			printerr("그림 파일 id 중복: " + id)
			quit(1)
			return
		files[id] = true
		var sf := FileAccess.open("res://assets/icons/svg/%s.svg" % id, FileAccess.WRITE)
		sf.store_string(svg + "\n") # 줄 끝 개행: 기존 파일과 같은 형태를 지켜 쓸데없는 차이가 나지 않게
		sf.close()
		var img := Image.new()
		var err := img.load_svg_from_string(svg, 1.0)
		if err != OK or img.get_width() != SIZE:
			failed.append(id)
			continue
		img.save_png(ProjectSettings.globalize_path("res://assets/icons/png128/%s.png" % id))
		var small := Image.new()
		small.load_svg_from_string(svg, float(SMALL) / float(SIZE))
		small.save_png(ProjectSettings.globalize_path("res://assets/icons/png64/%s.png" % id))
		made += 1
		var gk := _game_key(String(r.kind), String(r.key))
		if map.has(gk):
			printerr("게임 ID 중복: " + gk)
			quit(1)
			return
		map[gk] = { "file": id, "name": String(r.name), "color": color, "kind": String(r.kind) }
	if not failed.is_empty():
		printerr("SVG 래스터화 실패: " + str(failed))
		quit(1)
		return
	# data/icons.json 다시 쓰기(별칭은 기존 값을 유지한다 — 표기 흔들림을 한 키로 모으는 규칙)
	var cur := {}
	var cf := FileAccess.open("res://data/icons.json", FileAccess.READ)
	if cf != null:
		var parsed = JSON.parse_string(cf.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			cur = parsed
		cf.close()
	var out := {
		"schema": "prophecy.icons.v1",
		"source": "assets/icons/manifest_source.json (프로젝트 안에서 코드로 그린 벡터 %d종, 최종 아트 아님)" % map.size(),
		"note": String(cur.get("note", "게임 ID -> 아이콘 파일. 여기에 없는 ID는 절대 다른 효과의 아이콘으로 대체하지 않고 중립 자리표시 기호 + 실제 한국어 이름으로 그린다.")),
		"generator": "tools/icon_gen.gd — manifest_source.json을 고치고 이 도구를 다시 돌려 svg/png/매핑을 함께 만든다(손으로 고치지 않는다)",
		"dir64": "res://assets/icons/png64", "dir128": "res://assets/icons/png128", "dir_svg": "res://assets/icons/svg",
		"map": map, "alias": cur.get("alias", { "skill:q": "skill:slowfield", "skill:e:ward": "skill:ward", "w:sword": "weapon:sword" }),
	}
	var of := FileAccess.open("res://data/icons.json", FileAccess.WRITE)
	of.store_string(JSON.stringify(out, " ", false) + "\n")
	of.close()
	# 게임에 실제로 있는 ID인지 확인(없는 ID를 매핑하면 화면에 영영 안 나온다)
	PCatalog.reset()
	PIcons._data = {}
	var cov := PIcons.coverage()
	# 게임 쪽 키도 같은 규칙(PIcons.canon)으로 모아서 비교한다 — skill:e:ward ↔ skill:ward 같은 표기 흔들림이 거짓 경고가 되지 않게
	var known := {}
	for k in cov.have:
		known[PIcons.canon(String(k))] = true
		known[String(k)] = true
	for m in cov.missing:
		known[PIcons.canon(String(m.key))] = true
		known[String(m.key)] = true
	var orphan := []
	for k in map:
		if not known.has(String(k)):
			orphan.append(String(k))
	print("icon_gen: 그림 %d개 생성 · 매핑 %d개 · 표시 대상 %d개 중 아이콘 있음 %d · 누락 %d" % [made, map.size(), int(cov.total), (cov.have as Array).size(), (cov.missing as Array).size()])
	if not orphan.is_empty():
		printerr("경고: 게임에 없는 ID를 매핑했다 → " + str(orphan))
	print("ICON_GEN_MISSING " + JSON.stringify(cov.missing))
	quit(0 if orphan.is_empty() else 1)
