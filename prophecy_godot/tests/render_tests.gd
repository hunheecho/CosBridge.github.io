extends SceneTree
## 화면 표시 시험(headless). **눈으로 보는 검사가 아니라 "그리는 코드가 그 자료를 실제로 읽는가"** 를 본다.
## 실행: python tools/run_suites.py --suites render_tests --jobs 1
##
## 왜 이런 모양인가
##   규칙 담당들이 만든 값(보조무기 개체 · 특수 정예 read 자료 · 주술사 새 예고 · 보스 파괴 자격)이
##   화면에 안 나오는 것이 이번 결함이었다. 그림이 예쁜지는 사람이 봐야 하지만,
##   **그 자료를 읽는 갈래가 있는지 / 빠진 종류가 있는지 / 서로 다른 도형이 나오는지**는 기계가 볼 수 있다.
##   그래서 (가) render.gd 원본에서 갈래와 읽는 키를 확인하고 (나) 실제 전투 상태를 만들어 진짜로 그려 본다.
##
## 확인하는 것
##  1. 보조무기 A·B조 — 새 개체·장판·투사체·연출 종류가 그리기 목록에 있다(빠진 종류 0). 장판은 규칙 전수 조사.
##  2. 특수 정예 7종 — data/elites.json의 read 자료를 읽어 **서로 다른 실루엣 키**를 만든다(같은 키 재사용 0).
##  3. 주술사 — hex_lock 세 줄 · rune_aim 고정 원 · 치료 연결선이 그리기 대상에 있다. 방패병 방어/열림 구분.
##  4. 보스 — 지형 파괴 예고가 그리기 대상이고, **공격 예고보다 먼저** 그려진다. 파괴 예고 전용 소리.
##  5. 색만으로 구분하는 곳이 없다 — 적 등급 구분에 크기·장식이 함께 쓰인다.
##  6. KD-5 — 나무 가림 반지름이 1px가 아니다.
##  7. 그리기가 규칙을 바꾸지 않는다.
##
## 사람이 눈으로 봐야 하는 것(이 시험이 대신해 주지 못한다)은 docs/FEEL_AND_PALETTE.md '눈으로 볼 항목'에 적어 둔다.

const STEP := 1.0 / 60.0
var results := []
var src := ""

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

# ---------- 원본 읽기 도우미 ----------
func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

## 이름이 name인 static 함수의 본문(다음 static func 앞까지)
func _fn(text: String, name: String) -> String:
	var i := text.find("static func %s(" % name)
	if i < 0:
		return ""
	var j := text.find("\nstatic func ", i + 10)
	return text.substr(i, (text.length() - i) if j < 0 else (j - i))

func _has_all(body: String, needles: Array) -> Array:
	var miss := []
	for n in needles:
		if body.find(String(n)) < 0:
			miss.append(String(n))
	return miss

# ---------- 전투 상태 도우미 ----------
func _cfg() -> Dictionary:
	return preload("res://scripts/game/game.gd").load_config()

## 원하는 무기 구성으로 빈 전장 전투 상태(장애물 없음, 소환 멈춤)
func mk(ws: Array, arena: String = "forest") -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.weapons = ws.duplicate(true)
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 5, "arena": arena, "waves": [], "region_id": "act1_hunt_forest",
		"obstacles": [], "objective": "clear" })
	st.spawn_hold = true
	st.player.x = 480.0
	st.player.y = 300.0
	return st

func run_for(st: CombatState, seconds: float) -> void:
	var bot := PBot.new()
	var n := int(round(seconds / STEP))
	for i in n:
		if st.status != "running":
			return
		st.step(bot.step_input(st), STEP)

## 적을 쓰러뜨리지 않고 오래 굴리기 위해 체력만 크게 올린다(표시 시험이라 규칙 판정과 무관)
func tough(e: Dictionary) -> Dictionary:
	e.hp = 99999.0
	e.hp_max = 99999.0
	return e

## 조건이 참이 되는 첫 순간까지 굴린다. 참이 되면 그 순간의 상태를 남기고 true를 돌려준다
## (보조 개체·장판·투사체는 수명이 짧아 "끝난 뒤에 세면" 0으로 보인다 — 그래서 순간을 잡아 그린다)
func run_until(st: CombatState, cond: Callable, max_sec: float) -> bool:
	var bot := PBot.new()
	var n := int(round(max_sec / STEP))
	for i in n:
		if st.status != "running":
			return bool(cond.call(st))
		st.step(bot.step_input(st), STEP)
		if bool(cond.call(st)):
			return true
	return bool(cond.call(st))

func zone_count(st: CombatState, t: String) -> int:
	var n := 0
	for z in st.zones:
		if String(z.type) == t:
			n += 1
	return n

# ---------- 실제로 그려 본다 ----------
var view: Node2D = null

func _open_view() -> void:
	view = Node2D.new()
	view.set_script(load("res://scripts/game/combat_view.gd"))
	view.position = Vector2(0, 40)
	root.add_child(view)
	await process_frame

## PROPHECY_RENDER_SHOT=<폴더>로 창을 띄워 돌리면 그린 화면을 PNG로 남긴다(사람이 눈으로 볼 몫).
##   PROPHECY_RENDER_SHOT=docs/captures/0.9.0_render godot --path prophecy_godot --resolution 1280x720 -s tests/render_tests.gd
## headless(기본)에서는 아무것도 저장하지 않는다 — 판정에는 영향이 없다.
var shot_dir := ""
var shot_n := 0

func _paint(st: CombatState, shot_name: String = "") -> void:
	view.set("st", st)
	view.set("decor", PRender.make_decor(st))
	view.set("running", false)
	for i in 3:
		view.queue_redraw()
		await process_frame
	if shot_dir != "" and shot_name != "":
		shot_n += 1
		var img := root.get_texture().get_image()
		var path := shot_dir.path_join("%02d_%s.png" % [shot_n, shot_name])
		img.save_png(path)
		print("RENDER_SHOT %s %dx%d" % [path, img.get_width(), img.get_height()])

func _close_view() -> void:
	view.set("running", false)
	view.queue_free()
	await process_frame

func _run() -> void:
	src = _read("res://scripts/game/render.gd")
	PRender.palette_reset()
	shot_dir = OS.get_environment("PROPHECY_RENDER_SHOT")
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
	await _open_view()

	# ================= 1. 보조무기 A·B조 =================
	# 1-1. 규칙이 만드는 장판 종류를 하나도 빠뜨리지 않았는가(전수 조사 — 앞으로 새 장판이 생겨도 잡힌다)
	var zone_types := []
	for p in ["res://scripts/rules/supports_a.gd", "res://scripts/rules/supports_b.gd", "res://scripts/rules/enemies.gd",
			"res://scripts/rules/enemies_new.gd", "res://scripts/rules/boss.gd", "res://scripts/rules/boss2.gd",
			"res://scripts/rules/boss3.gd", "res://scripts/rules/weapons.gd", "res://scripts/rules/skills.gd",
			"res://scripts/rules/objectives.gd", "res://scripts/rules/combat_state.gd", "res://scripts/rules/terrain.gd"]:
		var rx := RegEx.new()
		rx.compile("add_zone\\(\"([a-z_]+)\"")
		for m in rx.search_all(_read(String(p))):
			var t := m.get_string(1)
			if not zone_types.has(t):
				zone_types.append(t)
	zone_types.sort()
	var zones_body := _fn(src, "draw_zones")
	var zone_miss := []
	for t in zone_types:
		if zones_body.find("\"%s\":" % String(t)) < 0:
			zone_miss.append(String(t))
	ok("draw_zones가 규칙이 만드는 장판 %d종을 하나도 빠뜨리지 않는다(빠진 종류 0)" % zone_types.size(),
		zone_miss.is_empty() and zone_types.has("windgust"), "빠진 것=%s / 전체=%s" % [str(zone_miss), str(zone_types)])

	# 1-2. 새 개체(까마귀·분신·인형 몸체)를 st.support에서 읽는가
	var sup_body := _fn(src, "draw_supports") + _fn(src, "draw_crow_birds") + _fn(src, "draw_echo_clones") + _fn(src, "draw_doll")
	var sup_miss := _has_all(sup_body, ["st.support", "\"crow\"", "birds", "\"echo\"", "clones", "doll_obj", "lured", "hp_max"])
	ok("보조무기 개체를 그리는 코드가 st.support의 birds·clones·doll_obj를 실제로 읽는다", sup_miss.is_empty(), "빠진 읽기=%s" % str(sup_miss))

	# 1-2b. 수호 방울의 남은 충전(날아오는 투사체가 없을 때 "지금 막을 수 있나"를 알 길이 없었다)
	var bell_body := _fn(src, "draw_bell_charges")
	ok("수호 방울의 남은 충전을 규칙 값(PSupportA.bell_max·bell_recharge)으로 그리고, 남음/빈자리를 채움 여부로 가른다",
		bell_body.find("PSupportA.bell_max") >= 0 and bell_body.find("PSupportA.bell_recharge") >= 0
		and bell_body.find("draw_colored_polygon") >= 0 and bell_body.find("draw_polyline") >= 0)

	# 1-3. 새 투사체 종류
	var proj_body := _fn(src, "draw_projectiles")
	ok("draw_projectiles에 되돌림 반격탄(bellshot) 갈래가 있다", proj_body.find("\"bellshot\"") >= 0)

	# 1-4. 새 연출 종류
	var imp_body := _fn(src, "draw_impacts")
	var fx_miss := _has_all(imp_body, ["\"bell_block\"", "\"bell_guard\"", "\"wind_gust\"", "\"echo_clone\""])
	ok("draw_impacts에 방울 차단·근접 수호·돌풍·분신 타격 연출이 모두 있다(빠진 종류 0)", fx_miss.is_empty(), "빠진 것=%s" % str(fx_miss))

	# 1-5. 차단 가능/불가를 **도형으로** 가르는가(색만으로 가르지 않는다)
	var mark_body := _fn(src, "bell_proj_mark")
	ok("적 투사체의 bell_blockable·bell_guard를 읽어 차단 가능/불가를 서로 다른 도형(고리 vs 가시)으로 그린다",
		mark_body.find("bell_blockable") >= 0 and mark_body.find("bell_guard") >= 0
		and mark_body.find("stroke_circle") >= 0 and mark_body.find("draw_line") >= 0,
		"고리=%s 가시=%s" % [mark_body.find("stroke_circle") >= 0, mark_body.find("draw_line") >= 0])

	# 1-6. 보조 표시가 적 예고를 덮지 않는다(그리기 순서)
	var layers := _fn(src, "_draw_layers")
	var i_sup := layers.find("draw_supports(ci, st)")
	var i_tel := layers.find("draw_telegraphs(ci, st)")
	ok("보조무기 개체는 적 예고보다 **먼저** 그린다(예고·피격 판정을 덮지 않는다)", i_sup > 0 and i_tel > i_sup, "보조 %d < 예고 %d" % [i_sup, i_tel])

	# 1-7. 실제 규칙이 만든 개체·장판으로 그려 본다
	var sa := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": ["twin"] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	for i in 6:
		tough(sa.spawn_enemy("boar", 380.0 + float(i) * 40.0, 250.0))
	var got_gust := run_until(sa, func(s: CombatState) -> bool: return zone_count(s, "windgust") > 0, 20.0)
	var crow_s: Dictionary = (sa.support as Dictionary).get("crow", {})
	var birds: int = (crow_s.get("birds", []) as Array).size()
	var gusts := zone_count(sa, "windgust")
	await _paint(sa, "supports_crow_wind")
	ok("실제 전투가 만든 까마귀 %d마리 · 잔바람 장판 %d개를 그 순간에 오류 없이 그린다" % [birds, gusts], birds > 0 and got_gust and gusts > 0)

	var sb := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": ["reflect"] }])
	for i in 4:
		tough(sb.spawn_enemy("archer", 250.0 + float(i) * 110.0, 180.0))
	tough(sb.spawn_enemy("shaman", 700.0, 380.0))
	tough(sb.spawn_enemy("wolf", 500.0, 340.0))
	var got_both := run_until(sb, func(s: CombatState) -> bool:
		var ec: Dictionary = (s.support as Dictionary).get("echo", {})
		var mk_n := 0
		for pr in s.projectiles:
			if pr.has("bell_blockable"):
				mk_n += 1
		return (ec.get("clones", []) as Array).size() > 0 and mk_n > 0, 25.0)
	var echo_s: Dictionary = (sb.support as Dictionary).get("echo", {})
	var clones: int = (echo_s.get("clones", []) as Array).size()
	var marked := 0
	var guardable := 0
	for pr in sb.projectiles:
		if pr.has("bell_blockable"):
			marked += 1
			if bool(pr.bell_blockable):
				guardable += 1
	await _paint(sb, "supports_echo_bell")
	ok("실제 전투가 만든 잔영 분신 %d개와 차단 표식이 붙은 적 투사체 %d개(막을 수 있는 것 %d)를 그 순간에 그린다" % [clones, marked, guardable],
		got_both and clones > 0 and marked > 0, "분신 %d · 표식 %d" % [clones, marked])

	var sc := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "doll", "level": 1, "mods": [] }])
	for i in 4:
		tough(sc.spawn_enemy("wolf", 380.0 + float(i) * 50.0, 380.0))
	var got_doll := run_until(sc, func(s: CombatState) -> bool: return not (s.support as Dictionary).get("doll_obj", {}).is_empty(), 30.0)
	var doll: Dictionary = (sc.support as Dictionary).get("doll_obj", {})
	await _paint(sc, "supports_doll")
	ok("실제 전투가 세운 도깨비 인형 몸체를 오류 없이 그린다(체력 막대·남은 시간·유인 수 포함)", got_doll and not doll.is_empty(),
		"인형=%s" % ("있음" if not doll.is_empty() else "없음(발동 주기 안에 안 섬)"))

	# ================= 2. 특수 정예 7종 =================
	var elite_ids := ["elite_archer", "elite_blademaster", "elite_fang", "elite_plaguecaller", "elite_chainbreaker", "elite_standard", "elite_miner"]
	var keys := {}
	var no_read := []
	var lines := []
	for id in elite_ids:
		var P := PRender.elite_props(String(id))
		if not bool(P.read):
			no_read.append(String(id))
		var k := PRender.elite_silhouette_key(String(id))
		keys[k] = (keys.get(k, []) as Array) + [String(id)]
		lines.append("%-20s %s" % [String(id), k])
	for l in lines:
		print("  " + String(l))
	ok("특수 정예 7종 전부 data/elites.json의 read 자료를 읽는다(PCatalog.elite_def(id).read)", no_read.is_empty(), "자료 없음=%s" % str(no_read))
	var dup := []
	for k in keys:
		if (keys[k] as Array).size() > 1:
			dup.append("%s ← %s" % [String(k), str(keys[k])])
	ok("7종의 실루엣 키가 서로 다르다(같은 키를 재사용하지 않는다) — 서로 다른 키 %d개" % keys.size(),
		keys.size() == elite_ids.size() and dup.is_empty(), "; ".join(dup))

	# 실루엣 조각이 정말 read 자료의 낱말에서 나왔는가(화면이 새 자료를 지어내지 않았다)
	var from_data := true
	var bad_src := []
	for id in elite_ids:
		var R: Dictionary = PCatalog.elite_def(String(id)).get("read", {})
		var P := PRender.elite_props(String(id))
		var okd := true
		for w in PRender.ELITE_HELD_WORDS:
			var has_word: bool = String(R.get("held", "")).find(String(w[0])) >= 0
			if has_word != (P.held as Array).has(String(w[1])):
				okd = false
		if String(P.role) != String(R.get("role_text", "")) or String(P.dist) != String(R.get("distance", "")):
			okd = false
		if not okd:
			from_data = false
			bad_src.append(String(id))
	ok("실루엣 부품·역할 문구가 전부 read 자료에서 나온다(화면이 새 자료를 만들지 않았다)", from_data, str(bad_src))

	# 등급 구분이 색만이 아니다
	var enemy_body := _fn(src, "draw_enemy")
	var ring_body := _fn(src, "elite_ground_ring")
	var tier_body := _fn(src, "tier_mark")
	ok("등급 구분에 크기·장식이 함께 쓰인다(특수 정예 = e.r 받침 고리 + 견장, 일반 정예 = 머리 위 삼각 + 링)",
		ring_body.find("e.r") >= 0 and ring_body.find("draw_arc") >= 0
		and _fn(src, "elite_emblem").find("elite_mark") >= 0
		and tier_body.find("draw_colored_polygon") >= 0 and tier_body.find("draw_arc") >= 0)
	ok("특수 정예가 '알 수 없는 종류'(원 + 작은 이름) 갈래로 떨어지지 않는다",
		enemy_body.find("elite_props(type).read") >= 0 and enemy_body.find("draw_elite(ci, st, e)") >= 0)

	# 테마 소속 장식: 한 막 안에서는 **도형**이 서로 다르고, 9종 전체는 (도형, 색) 짝이 유일하다
	var themes: Dictionary = PRender.palette_data().get("themes", {})
	var by_act := {}
	var pairs := {}
	var mark_bad := []
	for tid in themes:
		var P2 := PRender.palette_for(int((themes[tid] as Dictionary).act), String(tid))
		var a := int(P2.act)
		var shape := int(P2.get("elite_mark", -1))
		var trim := String(P2.get("elite_trim", ""))
		if shape < 0 or trim == "":
			mark_bad.append(String(tid))
		var seen: Array = by_act.get(a, [])
		if seen.has(shape):
			mark_bad.append("%s 도형 중복(%d막)" % [String(tid), a])
		seen.append(shape)
		by_act[a] = seen
		var pk := "%d|%s" % [shape, trim]
		if pairs.has(pk):
			mark_bad.append("%s ↔ %s 장식 같음" % [String(tid), String(pairs[pk])])
		pairs[pk] = String(tid)
	ok("같은 특수 정예라도 테마마다 견장 **도형**이 다르다(막 안 3종 도형 중복 0 · 9종 (도형,색) 짝 유일)",
		mark_bad.is_empty() and pairs.size() == 9, "; ".join(mark_bad))

	# 정예 예고 도형이 실제 판정값을 쓰는가(봇 회피용 여유가 아니라 def의 사거리·각도)
	var et_body := _fn(src, "draw_elite_telegraph")
	var et_miss := _has_all(et_body, ["d.biteRange", "d.biteDeg", "d.slamR", "d.leapR", "d.eruptR", "d.chainLen", "d.sweepRange", "d.fanDeg", "d.slashRange"])
	ok("특수 정예 예고 도형이 def의 실제 판정값(사거리·각도·반지름)을 읽는다", et_miss.is_empty(), "빠진 읽기=%s" % str(et_miss))

	# 7종을 실제로 세워 그린다
	var ee := mk([{ "id": "sword", "level": 1, "mods": [] }], "clearing")
	var spots := [[130.0, 120.0], [400.0, 110.0], [700.0, 120.0], [880.0, 300.0], [140.0, 330.0], [330.0, 520.0], [720.0, 520.0]]
	for i in elite_ids.size():
		var sp: Array = spots[i]
		tough(ee.spawn_enemy(String(elite_ids[i]), float(sp[0]), float(sp[1])))
	run_for(ee, 1.2)
	await _paint(ee, "elites_seven")
	var alive := 0
	for e in ee.enemies:
		if PEnemiesNew.is_elite(String(e.type)):
			alive += 1
	ok("특수 정예 7종을 한 화면에 세우고 3초 진행한 뒤 그려도 오류가 없다", alive == 7, "화면의 특수 정예 %d마리" % alive)

	# ================= 3. 주술사 · 방패병 =================
	var tel := _fn(src, "draw_telegraphs")
	var hex_ok: bool = tel.find("\"hex_lock\"") >= 0 and tel.find("hexCount") >= 0 and tel.find("hexSpreadDeg") >= 0 and tel.find("e.dir") >= 0
	ok("세 갈래 저주탄 확정(hex_lock)이 그리기 대상이고 확정 방향·갈래 수를 규칙 값으로 읽는다", hex_ok)
	var rune_ok: bool = tel.find("\"rune_aim\"") >= 0 and tel.find("rune_at") >= 0 and tel.find("runeR") >= 0
	ok("저주 문양(rune_aim)이 그리기 대상이고 고정된 자리·실제 폭발 반지름을 읽는다", rune_ok)
	var link_body := _fn(src, "draw_support_links")
	var link_miss := _has_all(link_body, ["PEnemies.support_links", "heal_link", "prog", "ratio", "target"])
	ok("치료 연결선이 규칙의 관측 자료(PEnemies.support_links)를 읽고 진행도·회복량·대상 반응을 그린다", link_miss.is_empty(), "빠진 읽기=%s" % str(link_miss))

	var sh := mk([{ "id": "sword", "level": 1, "mods": [] }])
	var wolf := sh.spawn_enemy("wolf", 620.0, 300.0)
	wolf.hp = float(wolf.hp_max) * 0.4
	var sm := sh.spawn_enemy("shaman", 700.0, 300.0)
	sm.state = "hex_lock"
	sm.state_t = 0.05
	sm.dir = PI
	var sm2 := sh.spawn_enemy("shaman", 760.0, 420.0)
	sm2.state = "rune_aim"
	sm2.state_t = 0.3
	sm2.rune_at = [480.0, 320.0]
	var sm3 := sh.spawn_enemy("shaman", 300.0, 460.0)
	sm3.state = "cast"
	sm3.state_t = 0.9
	sm3.cast_target = wolf
	var links := []
	PEnemies.support_links(sh, links)
	await _paint(sh, "shaman_hexlock_rune_heal")
	ok("hex_lock·rune_aim·치료 연결선이 있는 화면을 오류 없이 그린다(치료 연결 %d개)" % links.size(), links.size() == 1, "연결 %d" % links.size())

	# 방패병: 규칙의 guard_closed와 화면의 '열림'이 모든 상태에서 일치한다
	var sbd := mk([{ "id": "sword", "level": 1, "mods": [] }])
	var guard := sbd.spawn_enemy("shieldbearer", 560.0, 300.0)
	var mismatch := []
	for stt in ["approach", "bash_aim", "bash", "recover"]:
		guard.state = String(stt)
		var closed_rule: bool = PEnemiesNew.guard_closed(guard)
		var open_view: bool = String(stt) == "bash" or String(stt) == "recover"
		if closed_rule == open_view:
			mismatch.append(String(stt))
	ok("방패병: 규칙(guard_closed)과 화면의 방패 열림/닫힘이 네 상태에서 모두 일치한다", mismatch.is_empty(), "어긋난 상태=%s" % str(mismatch))
	var sbd_body := _fn(src, "draw_shieldbearer")
	ok("방패에 막히는 반응과 방패가 열린 상태를 서로 다른 도형으로 가른다(닫힘=정면 부채꼴 · 열림=점선 링 + 문구 · 막음=흰 방패 + 충격 쐐기)",
		sbd_body.find("fill_sector") >= 0 and sbd_body.find("dashed_circle") >= 0 and sbd_body.find("방패 내림") >= 0 and sbd_body.find("막음") >= 0)
	ok("방패치기 준비(bash_aim) 문구가 '방패 열림'이 아니다(규칙은 준비 중에도 닫아 둔다 — 2026-09-08 불일치)",
		tel.find("방패 열림") < 0 and tel.find("방패 유지 · 방패치기 준비") >= 0)

	# ================= 4. 보스 지형 파괴 =================
	var brk := _fn(src, "draw_boss_break_warn")
	var brk_miss := _has_all(brk, ["break_want", "break_ob", "aimText", "PBoss.breaker_of"])
	ok("보스 파괴 예고가 규칙의 자격 자료(break_want·break_ob·aimText)를 읽는다", brk_miss.is_empty(), "빠진 읽기=%s" % str(brk_miss))
	var i_brk := tel.find("draw_boss_break_warn(ci, st, flash_t)")
	var i_boss := tel.find("draw_boss_telegraphs(ci, st, flash_t)")
	ok("파괴 예고를 보스 공격 예고보다 **먼저** 그린다(공격 판정보다 먼저 읽힌다)", i_brk > 0 and i_boss > i_brk, "파괴 %d < 공격 %d" % [i_brk, i_boss])
	ok("부서지는 장애물 전용 표시가 있다(깨짐 금 + 조여드는 점선 + 남은 시간 고리 — 일반 폭발 효과가 아니다)",
		brk.find("dashed_circle") >= 0 and brk.find("draw_arc") >= 0 and brk.find("wantTtl") >= 0)

	var bs := CombatState.new({ "build": PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword"))), "seed": 3,
		"arena": "clearing", "boss": true, "boss_id": "guardian", "region_id": "boss" })
	run_for(bs, 1.0)
	var bz: Dictionary = bs.boss
	var painted_break := false
	if not bz.is_empty() and bs.obstacles.size() > 0:
		bz.break_want = true
		bz.break_want_t = 1.0
		bz.break_idx = 0
		bz.break_ob = bs.obstacles[0]
		painted_break = true
	await _paint(bs, "boss_break_warn")
	ok("파괴 자격이 선 보스 화면을 오류 없이 그린다", painted_break, "보스=%s 장애물=%d" % [String(bz.get("boss_id", "")), bs.obstacles.size()])

	var au := PAudio.new()
	ok("파괴 **예고** 전용 소리가 있다(기존 shatter는 부서진 뒤의 소리다)", PAudio.NAMES.has("break_warn") and PAudio.NAMES.has("shatter"))
	var w_warn: PackedFloat32Array = PAudio._synth("break_warn")
	var w_shat: PackedFloat32Array = PAudio._synth("shatter")
	ok("파괴 예고 소리와 파괴 소리의 파형이 서로 다르다(길이 %d vs %d)" % [w_warn.size(), w_shat.size()],
		not w_warn.is_empty() and w_warn.size() != w_shat.size())
	var fired := 0
	var seen_st := bs
	au._break_seen = false
	if au._break_warn_due(seen_st):
		fired += 1
	if au._break_warn_due(seen_st):
		fired += 1                                     # 자격이 유지되는 동안 다시 울리지 않는다
	ok("파괴 자격이 서는 순간에만 한 번 울린다(자격이 유지되는 동안 반복하지 않는다)", fired == 1, "울린 횟수 %d" % fired)

	# ================= 5. KD-5 나무 가림 =================
	# 전장 'clearing'의 나무는 자료에 canopy 70이 있는데, 규칙이 참/거짓으로 바꿔 실어 화면에서 1px가 되었다
	var tree := {}
	for ob in bs.obstacles:
		if String(ob.type) == "tree":
			tree = ob
			break
	var cr: float = PRender.canopy_r(tree) if not tree.is_empty() else 0.0
	ok("KD-5: 실제 전투 상태의 나무 가림 반지름이 1px가 아니다(밑동 반지름에서 되짚는다) — %.1f" % cr,
		not tree.is_empty() and cr > 30.0, "나무 r=%.1f · canopy 값=%s" % [float(tree.get("r", 0.0)), str(tree.get("canopy", null))])
	ok("자료에 숫자가 살아 있으면 그 값을 그대로 쓰고, 가림 없음(false)은 0이다",
		is_equal_approx(PRender.canopy_r({ "type": "tree", "r": 26.0, "canopy": 70.0 }), 70.0)
		and is_equal_approx(PRender.canopy_r({ "type": "tree", "r": 26.0, "canopy": false }), 0.0))

	# ================= 6. 그리기가 규칙을 바꾸지 않는다 =================
	var plain := _sim(31)
	var drawn := await _sim_drawn(31)
	ok("같은 시드: 매 프레임 그려도 전투 결과가 완전히 같다(표시가 규칙·난수를 건드리지 않는다)",
		JSON.stringify(plain) == JSON.stringify(drawn), "%s\nvs\n%s" % [JSON.stringify(plain), JSON.stringify(drawn)])

	await _close_view()
	PSave.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

func _sim(seed_v: int) -> Dictionary:
	var st := CombatState.first_fight(_cfg(), seed_v)
	var bot := PBot.new()
	var n := 0
	while st.status == "running" and n < 60 * 90:
		st.step(bot.step_input(st), STEP)
		n += 1
	return _fingerprint(st, n)

func _sim_drawn(seed_v: int) -> Dictionary:
	var st := CombatState.first_fight(_cfg(), seed_v)
	var bot := PBot.new()
	view.set("st", st)
	view.set("decor", PRender.make_decor(st))
	view.set("running", false)
	var n := 0
	while st.status == "running" and n < 60 * 90:
		st.step(bot.step_input(st), STEP)
		if n % 20 == 0:
			view.queue_redraw()
			await process_frame
		n += 1
	view.queue_redraw()
	await process_frame
	return _fingerprint(st, n)

func _fingerprint(st: CombatState, n: int) -> Dictionary:
	var s := st.summary()
	return { "status": String(s.status), "t": snapped(float(s.elapsed), 0.0001), "hp": snapped(float(s.hp), 0.0001),
		"kills": int(s.kills), "taken": snapped(float(s.damage_taken), 0.0001), "steps": st.step_n, "frames": n,
		"rng": int(st.rng._a) }
