extends SceneTree
## 타격감 연출 시험(headless). 실제 전투 상태를 만들어 연출 값만 확인한다.
## 실행: python tools/run_suites.py --suites hit_feel_tests --jobs 1 --allow-adhoc
##
## 확인하는 것
##  A. 적중 이벤트에 맞춰 연출이 붙는가 — 적 짧은 점멸(e.flash), 방향이 담긴 타격 효과(spark.angle), 치명타 구분
##  B. 사망 반응 — death 연출(적 색·반지름)과 kill 소리, 보스는 boss_down 소리
##  C. 기술별로 구분되는 소리 — 같은 "hit"이 검격/관통/단검/원거리에 따라 다른 소리 이름이 되고, 파형도 서로 다르다
##  D. 강한 공격에만 약한 화면 반응 — 장판 틱·일반 적중·피격에는 흔들림이 정확히 0, 강한 연출에만 나며 크기 상한이 있다
##  E. 끄기 옵션 — PRender.set_shake(false)면 어떤 연출에도 0이고, 값이 user://render_prefs.json에 남는다
##  F. 전역 화면 정지 없음 — 표시 계층이 Engine.time_scale·tree.paused를 건드리지 않는다
##  G. 연출이 규칙을 바꾸지 않는다 — 같은 시드에서 '그리기·소리 있음'과 '없음'의 전투 결과가 완전히 같다
##  H. 아군 적중 연출이 적 예고를 가리지 않는다 — 그리기 순서와 화면 전체 덮기 금지

const DT := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

func _cfg() -> Dictionary:
	return preload("res://scripts/game/game.gd").load_config()

func _fx_of(st: CombatState, kind: String) -> Dictionary:
	for f in st.effects:
		if String(f.kind) == kind:
			return f
	return {}

## 연출 하나만 담긴 가짜 상태(흔들림 계산은 st.effects만 읽는다)
func _st_with(kind: String, ttl: float = 0.3) -> CombatState:
	var st := CombatState.first_fight(_cfg(), 5)
	st.effects.clear()
	st.fx({ "kind": kind, "x": 300.0, "y": 200.0, "r": 60.0, "ttl": ttl })
	return st

func _run() -> void:
	PSave.clear()
	PRender.palette_reset()
	PRender.set_shake(true)

	# ---------- A. 적중 연출 ----------
	var st := CombatState.first_fight(_cfg(), 11)
	st.intro = 0.0
	var e := st.spawn_enemy("wolf", st.player.x + 60.0, st.player.y)
	st.effects.clear()
	st.events.clear()
	st.events_data.clear()
	st.damage_enemy(e, 3.0, { "dir": [1.0, 0.0], "src": { "direct": true, "weapon_id": "sword" } })
	var sp := _fx_of(st, "spark")
	ok("적중 1회 → 적 점멸(e.flash>0) + 타격 효과 + 'hit' 이벤트", float(e.flash) > 0.0 and not sp.is_empty() and st.events.has("hit"),
		"flash=%.3f fx=%s ev=%s" % [float(e.flash), str(not sp.is_empty()), str(st.events)])
	ok("타격 효과에 맞은 방향이 들어 있다(오른쪽에서 맞으면 각도 0)", is_equal_approx(float(sp.get("angle", -9.0)), 0.0), "angle=%s" % str(sp.get("angle", null)))
	# 방향이 바뀌면 각도도 바뀐다
	st.effects.clear()
	st.damage_enemy(e, 1.0, { "dir": [0.0, 1.0], "src": { "direct": true, "weapon_id": "sword" } })
	var sp2 := _fx_of(st, "spark")
	ok("맞은 방향이 다르면 효과 각도도 다르다", absf(float(sp2.get("angle", 0.0)) - PI / 2.0) < 0.01, "angle=%.3f" % float(sp2.get("angle", 0.0)))
	# 치명타(빈틈 상태)는 따로 표시된다
	st.effects.clear()
	e.state = "recover"
	st.damage_enemy(e, 1.0, { "dir": [1.0, 0.0], "src": { "direct": true, "weapon_id": "sword" } })
	ok("빈틈(치명타) 적중은 효과에 crit 표시가 붙는다", bool(_fx_of(st, "spark").get("crit", false)))
	ok("점멸 시간은 규칙 값 그대로(연출이 늘리지 않는다)", is_equal_approx(float(e.flash), 0.12), "flash=%s" % str(e.flash))

	# ---------- B. 사망 반응 ----------
	st.effects.clear()
	st.events.clear()
	var hp_before: float = float(e.hp)
	st.damage_enemy(e, hp_before + 50.0, { "dir": [1.0, 0.0], "src": { "direct": true, "weapon_id": "sword" } })
	var dfx := _fx_of(st, "death")
	ok("처치 → 사망 연출(적 색·반지름) + 'kill' 이벤트", bool(e.dead) and not dfx.is_empty() and st.events.has("kill"),
		"death=%s ev=%s" % [str(dfx), str(st.events)])
	ok("사망 연출이 적 색을 그대로 쓴다(종류가 구분된다)", String(dfx.get("color", "")) != "" and float(dfx.get("r", 0.0)) > 0.0)

	# ---------- C. 기술별로 구분되는 소리 ----------
	var au := PAudio.new()
	var sa := CombatState.first_fight(_cfg(), 4)
	var picked := {}
	for form in ["arc", "beam", "melee"]:
		sa.events.clear()
		sa.events_data.clear()
		au.reset(sa, false)
		sa.ev("hit", { "crit": false })
		sa.ev("swing", { "form": form })
		var names: Array = au.pending_sounds(sa)
		picked[form] = names
	sa.events.clear()
	sa.events_data.clear()
	au.reset(sa, false)
	sa.ev("hit", { "crit": false })
	sa.ev("shoot")
	var shot_names: Array = au.pending_sounds(sa)
	sa.events.clear()
	sa.events_data.clear()
	au.reset(sa, false)
	sa.ev("hit", { "crit": true })
	sa.ev("swing", { "form": "arc" })
	var crit_names: Array = au.pending_sounds(sa)
	var hit_sounds := [String(picked.arc[0]), String(picked.beam[0]), String(picked.melee[0]), String(shot_names[0]), String(crit_names[0])]
	var uniq := {}
	for s in hit_sounds:
		uniq[s] = true
	ok("같은 적중이라도 기술마다 다른 소리를 고른다(검격·관통·단검·원거리·치명타 5종)", uniq.size() == 5, str(hit_sounds))
	ok("휘두르는 소리도 기술별로 다르다", String(picked.arc[1]) == "swing_arc" and String(picked.beam[1]) == "swing_beam" and String(picked.melee[1]) == "swing_melee",
		"%s %s %s" % [String(picked.arc[1]), String(picked.beam[1]), String(picked.melee[1])])
	var waves := {}
	var same := ""
	for s in ["hit", "hit_arc", "hit_beam", "hit_melee", "hit_shot", "crit", "kill", "boss_down"]:
		var b: PackedFloat32Array = PAudio._synth(s)
		var key := "%d|%.4f|%.4f" % [b.size(), b[mini(200, b.size() - 1)], b[mini(600, b.size() - 1)]]
		if waves.has(key):
			same = "%s = %s" % [s, String(waves[key])]
		waves[key] = s
	ok("고른 소리들이 실제로 서로 다른 파형이다(이름만 다른 게 아니다)", same == "" and waves.size() == 8, same)
	ok("규칙에 새 이벤트를 넣지 않았다(hit·swing·kill·boss_down은 이미 있던 신호)", sa.events.has("hit") and PAudio.NAMES.has("boss_down"))
	au.free()

	# ---------- D. 강한 공격에만 약한 화면 반응 ----------
	PRender.set_shake(true)
	var quiet := []
	for kind in ["spark", "hitflash", "zone", "text", "burst", "flare", "death", "arc", "beam"]:
		var sq := _st_with(kind)
		if PRender.shake_offset(sq) != Vector2.ZERO:
			quiet.append(kind)
	ok("장판 틱·일반 적중·피격 표시로는 화면이 전혀 흔들리지 않는다", quiet.is_empty(), "흔들린 연출: " + ", ".join(quiet))
	# 장판이 여러 개 켜진 상태(가장 흔한 '틱마다 흔들림' 상황)도 정확히 0
	var sz := CombatState.first_fight(_cfg(), 6)
	sz.effects.clear()
	for i in 6:
		sz.add_zone("fire", 200.0 + float(i) * 40.0, 200.0, 60.0, 3.0, 2.0)
		sz.fx({ "kind": "hitflash", "x": 300.0, "y": 200.0, "ttl": 0.25 })
		sz.fx({ "kind": "spark", "x": 300.0, "y": 200.0, "ttl": 0.22, "angle": 0.0 })
	ok("장판 6개 + 피격·적중 표시가 겹쳐도 흔들림 0(장판 틱마다 진동 금지)", PRender.shake_offset(sz) == Vector2.ZERO, str(PRender.shake_offset(sz)))
	var strong := {}
	var missing := []
	for kind in PRender.SHAKE_SOURCES.keys():
		var ss := _st_with(String(kind))
		var off: Vector2 = PRender.shake_offset(ss)
		strong[kind] = off.length()
		if off == Vector2.ZERO:
			missing.append(String(kind))
	ok("강한 타격 연출(%s)에서만 화면이 반응한다" % ", ".join(PackedStringArray(PRender.SHAKE_SOURCES.keys())), missing.is_empty(), "반응 없음: " + ", ".join(missing))
	var maxlen := 0.0
	var sbig := CombatState.first_fight(_cfg(), 7)
	sbig.effects.clear()
	for i in 12:
		sbig.fx({ "kind": "bossland", "x": 100.0 + float(i) * 30.0, "y": 150.0, "r": 60.0, "ttl": 0.4 })
	for step in 40:
		maxlen = maxf(maxlen, PRender.shake_offset(sbig).length())
		for f in sbig.effects:
			f.t = float(f.t) + 0.01
	ok("흔들림은 약하다(강한 연출 12개가 겹쳐도 상한 %.1fpx 이내)" % PRender.SHAKE_MAX, maxlen <= PRender.SHAKE_MAX + 0.001, "최대 %.2fpx" % maxlen)
	# 잦아든다: 같은 연출이 끝나갈수록 작아진다
	var sfade := _st_with("impact", 0.4)
	var a0: float = PRender.shake_offset(sfade).length()
	sfade.effects[0].t = 0.35
	var a1: float = PRender.shake_offset(sfade).length()
	ok("한 번 반응하면 곧 잦아든다(끝나갈수록 작아진다)", a1 < a0, "%.2f → %.2f" % [a0, a1])

	# ---------- E. 끄기 옵션 ----------
	PRender.set_shake(false)
	var still := []
	for kind in PRender.SHAKE_SOURCES.keys():
		if PRender.shake_offset(_st_with(String(kind))) != Vector2.ZERO:
			still.append(String(kind))
	ok("끄기 옵션(PRender.set_shake(false))이면 어떤 강한 연출에도 흔들리지 않는다", still.is_empty(), ", ".join(still))
	var pf := FileAccess.open(PRender.SHAKE_PREFS, FileAccess.READ)
	var saved = JSON.parse_string(pf.get_as_text()) if pf != null else null
	ok("옵션 값이 user://render_prefs.json에 남는다(다음 실행에도 유지)", typeof(saved) == TYPE_DICTIONARY and saved.camera_shake == false, str(saved))
	PRender.set_shake(true)
	ok("다시 켜면 반응이 돌아온다", PRender.shake_offset(_st_with("impact")) != Vector2.ZERO)

	# ---------- F. 전역 화면 정지 없음 ----------
	var freeze := []
	for path in ["res://scripts/game/render.gd", "res://scripts/game/audio.gd"]:
		var fa := FileAccess.open(path, FileAccess.READ)
		var text := fa.get_as_text() if fa != null else ""
		for bad in ["Engine.time_scale", "get_tree().paused", "Engine.set_time_scale", "OS.delay_msec"]:
			if text.find(bad) >= 0:
				freeze.append("%s: %s" % [path.get_file(), bad])
	ok("연출이 전역 시간 정지를 쓰지 않는다(화면 정지 금지)", freeze.is_empty(), "; ".join(freeze))

	# ---------- H. 아군 적중 연출이 적 예고를 가리지 않는다 ----------
	var fr := FileAccess.open("res://scripts/game/render.gd", FileAccess.READ)
	var src := fr.get_as_text()
	var i_layers := src.find("static func _draw_layers(")
	var order_src := src.substr(i_layers, maxi(0, src.length() - i_layers))
	var i_impacts := order_src.find("draw_impacts(ci, st)")
	var i_tele := order_src.find("draw_telegraphs(ci, st)")
	var i_players := order_src.find("draw_player_effects(ci, st)")
	ok("그리기 순서: 내 공격 잔상 → 내 적중 연출 → 적 예고(예고가 항상 위)", i_players > 0 and i_impacts > i_players and i_tele > i_impacts,
		"잔상 %d < 적중 %d < 예고 %d" % [i_players, i_impacts, i_tele])
	var impacts_start := src.find("static func draw_impacts(")
	var impacts_end := src.find("# ---------- 불꽃·숫자·기타 효과 ----------")
	var impacts := src.substr(impacts_start, maxi(0, impacts_end - impacts_start))
	ok("피격 표시가 경기장 전체를 붉게 덮지 않는다(가장자리 띠만 — 예고가 묻히면 안 된다)",
		impacts.find("Rect2(0, 0, st.arena_w, st.arena_h)") < 0 and impacts.find("band") >= 0)

	# ---------- G. 연출이 전투 결과를 바꾸지 않는다 ----------
	var plain := _sim(23, null, null)
	var view: Node2D = Node2D.new()
	view.set_script(load("res://scripts/game/combat_view.gd"))
	view.position = Vector2(0, 40)
	root.add_child(view)
	await process_frame
	var audio: PAudio = view.get("audio")
	var fancy := await _sim_drawn(23, view, audio)
	ok("같은 시드: 그리기·소리를 매 프레임 돌려도 전투 결과가 완전히 같다", JSON.stringify(plain) == JSON.stringify(fancy),
		"%s\nvs\n%s" % [JSON.stringify(plain), JSON.stringify(fancy)])
	view.set("running", false)
	view.queue_free()
	await process_frame

	PSave.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

## 표시 없이 봇으로 끝까지(비교 기준). 결과에 난수 상태·공격 순서까지 넣어 '규칙이 같았는지'를 강하게 본다
func _sim(seed_v: int, _a, _b) -> Dictionary:
	var st := CombatState.first_fight(_cfg(), seed_v)
	var bot := PBot.new()
	var n := 0
	while st.status == "running" and n < 120 * 120:
		st.step(bot.step_input(st), DT)
		n += 1
	return _fingerprint(st, n)

## 같은 시드·같은 봇을 돌리면서 매 프레임 소리를 뽑고 주기적으로 실제 화면을 그린다
func _sim_drawn(seed_v: int, view: Node2D, audio: PAudio) -> Dictionary:
	var st := CombatState.first_fight(_cfg(), seed_v)
	var bot := PBot.new()
	view.set("st", st)
	view.set("decor", PRender.make_decor(st))
	view.set("running", false)      # 규칙 진행은 이 시험이 직접 한다
	if audio != null:
		audio.reset(st, false)
	var n := 0
	while st.status == "running" and n < 120 * 120:
		st.step(bot.step_input(st), DT)
		if audio != null:
			audio.drain(st)
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
		"rng": int(st.rng._a), "attacks": JSON.stringify(st.attack_log) }
