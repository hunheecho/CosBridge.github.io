extends SceneTree
## 실력 봇 기반 회귀 검사(headless): godot --headless --path prophecy_godot -s tests/bot_tests.gd — user://(기록·배치 임시 폴더)를 쓰므로 APPDATA를 별도 폴더로 두고 실행.
## 지시문 prophecy-bot-balance-framework-20260907 §12 1~10: 미래 정보 누출 · 예고 시작/인식 지연 전후 입력 시점 · 스냅샷 격리 · 봇 seed와 편성 독립 · 누름 길이/지형/재사용/일시정지(사람과 같은 입력 경로) ·
## 계측 켜짐/꺼짐 결과 동일·게임 난수 불변 · 피해/보호막/회복/과잉/거절 검산·보유시간 DPS·정산 1회 · 기록 재생 해시 일치·버전 거부 · 배치 재개 중복 없음·캐시 무효화 · 실제 장면(main.tscn) 프로필 선택→시작→결과→재시작(함수 호출, 사람 입력·합성 이벤트 없음).
## 게임 수치는 바꾸지 않는다. 봇의 승률을 단언하는 검사는 없다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func cfg() -> Dictionary:
	var G := preload("res://scripts/game/game.gd")
	return G.config_with(G.load_config(), "hold", 1.5, "x5", 2)

func mk(seed_v: int = 1) -> CombatState:
	return CombatState.first_fight(cfg(), seed_v)

func no_enemies(st: CombatState) -> void:
	st.spawn_hold = true

func passive_wolf(st: CombatState, x: float, y: float) -> Dictionary:
	var w := st.spawn_enemy("wolf", x, y)
	w.bite_cd = 1.0e9
	w.dash_ready_at = 1.0e9
	return w

## 시험 고정: 늑대를 지금 돌진 준비(crouch)로 놓는다(실제 규칙이 이어서 lock→dash로 진행한다). 관측 id = e<id>#1
func crouch_now(st: CombatState, w: Dictionary) -> String:
	var p := st.player
	w.state = "crouch"
	w.state_t = 0.0
	w.aim_angle = atan2(p.y - w.y, p.x - w.x)
	w.acted = true
	w.attack_n = int(w.get("attack_n", 0)) + 1
	return "e%d#%d" % [int(w.id), int(w.attack_n)]

## 숨은 정보만 바꾼다(게임 난수 상태·대기열 좌표/시간·늑대 내부 타이머). 되돌릴 값을 돌려준다
func hide(st: CombatState) -> Dictionary:
	var saved := { "rng": st.rng._a, "pending": [], "wolves": [] }
	st.rng._a = (int(st.rng._a) ^ 0x5A5A5A5A) & 0xFFFFFFFF
	for sp in st.pending:
		saved.pending.append([sp, float(sp.x), float(sp.t)])
		sp.x = float(sp.x) + 37.0
		sp.t = float(sp.t) + 0.5
	for e in st.enemies:
		if PEnemies.is_wolf(e.def):
			saved.wolves.append([e, float(e.dash_ready_at), float(e.bite_cd), float(e.dash_cd), float(e.ready_t)])
			e.dash_ready_at = float(e.dash_ready_at) + 100.0
			e.bite_cd = float(e.bite_cd) + 100.0
			e.dash_cd = float(e.dash_cd) + 5.0
			e.ready_t = 3.0
	return saved

func unhide(st: CombatState, saved: Dictionary) -> void:
	st.rng._a = int(saved.rng)
	for q in saved.pending:
		q[0].x = q[1]
		q[0].t = q[2]
	for q in saved.wolves:
		q[0].dash_ready_at = q[1]
		q[0].bite_cd = q[2]
		q[0].dash_cd = q[3]
		q[0].ready_t = q[4]

func run_fight(st: CombatState, bot: PBot, max_sec: float, rp: PReplay = null) -> int:
	var n := 0
	while st.status == "running" and n < int(max_sec / STEP):
		var inp := bot.step_input(st)
		if rp != null:
			rp.note(st, inp)
		st.step(inp, STEP)
		n += 1
	return n

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ---------- 1. 미래 정보 누출: 같은 공개 관측·봇 seed, 다른 숨은 미래 → 같은 스냅샷·같은 입력 ----------
	var st := mk(11)
	var A := PSkillBot.new("regular", 7)
	var B := PSkillBot.new("regular", 7)
	var same_in := true
	var same_snap := true
	var leak_keys := false
	var n := 0
	var decisions := 0
	while st.status == "running" and n < 120 * 12:
		var sa := A.observer.take(st, true)
		var saved := hide(st)
		var sb := B.observer.take(st, true)
		unhide(st, saved)
		var ja := JSON.stringify(sa)
		if ja != JSON.stringify(sb):
			same_snap = false
		for k in ["dash_ready_at", "bite_cd", "ready_t", "\"pending\"", "\"rng\"", "dash_cd", "explode_at"]:
			if ja.find(k) >= 0:
				leak_keys = true
		var ia := A.step_snapshot(sa)
		var ib := B.step_snapshot(sb)
		if JSON.stringify(ia) != JSON.stringify(ib):
			same_in = false
		if bool(ia.dodge_press):
			decisions += 1
		st.step(ia, STEP)
		n += 1
	ok("1 미래 정보 누출: 숨은 난수·대기열·늑대 타이머를 바꿔도 스냅샷 동일·입력 동일(%d단계, 회피 %d회), 스냅샷에 내부 필드 이름 없음" % [n, decisions], same_snap and same_in and not leak_keys and decisions > 0)
	# ---------- 2. 예고 시작·인식 지연 전후의 입력 시점 / 조준선 갱신 / 종료된 위협 ----------
	st = mk(1)
	no_enemies(st)
	var w := passive_wolf(st, st.player.x + 130.0, st.player.y)
	var bot := PSkillBot.new("regular", 3)
	for i in 60:
		st.step(bot.step_input(st), STEP)
	var aid := crouch_now(st, w)
	var s0 := int(st.step_n)
	var recog := -1
	var first_dodge := -1
	var first_escape := -1
	var early_press := false
	var angs := {}
	var stale_ok := true
	var recog_changed := false
	var k := 0
	while k < 90 and st.status == "running":
		var cur := PObserve.snapshot(st)
		for th in cur.threats:
			if String(th.attack_id) == aid:
				angs[int(st.step_n)] = float(th.ang)
		var inp := bot.step_input(st)
		if bot.known.has(aid):
			var kk: Dictionary = bot.known[aid]
			if recog < 0:
				recog = int(kk.recog_step)
			elif int(kk.recog_step) != recog:
				recog_changed = true
			if int(st.step_n) >= recog and angs.has(int(kk.tracked_step)):
				if absf(float(kk.geom.ang) - float(angs[int(kk.tracked_step)])) > 1e-9 or int(st.step_n) - int(kk.tracked_step) > bot.track_steps:
					stale_ok = false
		if bool(inp.dodge_press):
			if int(st.step_n) < recog or recog < 0:
				early_press = true
			if first_dodge < 0:
				first_dodge = int(st.step_n)
		if first_escape < 0 and bot.escape_id == aid:
			first_escape = int(st.step_n)
		st.step(inp, STEP)
		k += 1
	var gate_step: int = s0 + int(ceil(float(bot.common.get("warn_react_prog", 0.4)) * float(w.def.dash.crouch) / STEP)) # 공통 반응 문턱(예고 진행률 0.4)
	ok("2a 인식 지연: 예고 시작 s0=%d, 인식 %d(+%d단계 = %d~%dms 범위), 반응 문턱 %d, 첫 탈출 판단 %d(+%d), 첫 회피 %d — 인식 전 입력 없음, 인식·문턱 뒤 한 판단 간격 안에 반응" % [s0, recog, recog - s0, bot.recog_lo * 1000 / 120, bot.recog_hi * 1000 / 120, gate_step, first_escape, first_escape - s0, first_dodge], recog - s0 >= bot.recog_lo and recog - s0 <= bot.recog_hi and first_escape >= recog and first_escape <= maxi(recog, gate_step) + bot.decide_steps and not early_press and first_dodge >= recog)
	ok("2b 추적: 인식 시각은 조준선 갱신에도 불변, 봇이 아는 각도 = 마지막 추적 갱신 시점의 각도(갱신 간격 ≤ %d단계)" % bot.track_steps, not recog_changed and stale_ok and angs.size() > 20)
	st = mk(1)
	no_enemies(st)
	w = passive_wolf(st, st.player.x + 130.0, st.player.y)
	bot = PSkillBot.new("regular", 3)
	for i in 60:
		st.step(bot.step_input(st), STEP)
	aid = crouch_now(st, w)
	for i in 10:
		st.step(bot.step_input(st), STEP)
	var had := bot.known.has(aid)
	st.damage_enemy(w, 9999.0, "test")
	var pressed := false
	for i in 120:
		var inp2 := bot.step_input(st)
		if bool(inp2.dodge_press):
			pressed = true
		st.step(inp2, STEP)
	ok("2c 종료된 위협: 인식 대기 중 사망 → 대기 항목 삭제, 이후 1초 동안 회피 입력 없음", had and not bot.known.has(aid) and not pressed)
	# ---------- 3. 스냅샷 격리: 적 방향·위치 변경이 이전 스냅샷·봇의 기억을 바꾸지 않음 ----------
	st = mk(1)
	no_enemies(st)
	w = passive_wolf(st, st.player.x + 130.0, st.player.y)
	aid = crouch_now(st, w)
	bot = PSkillBot.new("skilled", 1)
	var snap := PObserve.snapshot(st)
	bot.step_input(st)
	var ang0: float = float(snap.threats[0].ang)
	var ex0: float = float(snap.enemies[0].x)
	var geom_ang0: float = float(bot.known[aid].geom.ang)
	w.aim_angle = float(w.aim_angle) + 1.0
	w.x = float(w.x) + 50.0
	w.dir = 2.0
	ok("3 스냅샷 격리: 적 각도 +1.0·위치 +50 뒤에도 이전 스냅샷 각도/위치·봇 기억 각도 불변", float(snap.threats[0].ang) == ang0 and float(snap.enemies[0].x) == ex0 and float(bot.known[aid].geom.ang) == geom_ang0 and absf(ang0 - (float(w.aim_angle) - 1.0)) < 1e-9)
	# ---------- 4. 봇 seed(오차 표본)가 최초 편성·경로 난수를 바꾸지 않음 ----------
	var s1 := mk(5)
	var s2 := mk(5)
	var b1 := PSkillBot.new("regular", 1)
	var b2 := PSkillBot.new("regular", 2)
	for i in int(1.2 / STEP):
		s1.step(b1.step_input(s1), STEP)
		s2.step(b2.step_input(s2), STEP)
	var pos1 := []
	var pos2 := []
	for e in s1.enemies:
		pos1.append([e.id, snapped(e.x, 0.001), snapped(e.y, 0.001)])
	for e in s2.enemies:
		pos2.append([e.id, snapped(e.x, 0.001), snapped(e.y, 0.001)])
	ok("4 봇 seed 1/2: 1.2초 뒤 편성 순서·등장 위치·게임 난수 상태 동일(적 %d)" % pos1.size(), str(s1.formation.units) == str(s2.formation.units) and str(pos1) == str(pos2) and s1.rng._a == s2.rng._a and pos1.size() > 0 and b1.brng._a != b2.brng._a)
	# ---------- 5. 짧은/중간/긴 누름 · 지형 차단 · 재사용 중 거절 · 일시정지 뒤 재발동 방지(사람과 같은 입력 경로 st.step/PStepDriver) ----------
	st = mk(1)
	no_enemies(st)
	bot = PSkillBot.new("regular", 1)
	var rules := PObserve.rules_of(st)
	var hs := { "short": bot.hold_steps_for("short", rules), "medium": bot.hold_steps_for("medium", rules), "long": bot.hold_steps_for("long", rules) }
	var dists := {}
	for kind in ["short", "medium", "long"]:
		var sx := mk(1)
		no_enemies(sx)
		var x0: float = sx.player.x
		var h: int = hs[kind]
		sx.step({ "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": h != 0 }, STEP)
		var j := 1
		while sx.player.dodge_active and j < 200:
			sx.step({ "mx": 1.0, "my": 0.0, "dodge_press": false, "dodge_held": (h < 0) or (j < h) }, STEP)
			j += 1
		dists[kind] = snapped(sx.player.x - x0, 0.1)
	ok("5a 누름 길이 정책(요청 누름 단계 %s) → 실제 거리 짧음 %.1f(최소 70) / 중간 %.1f(100~125) / 김 %.1f(150)" % [str(hs), dists.short, dists.medium, dists.long], int(hs.short) == 0 and int(hs.long) < 0 and int(hs.medium) > 0 and absf(float(dists.short) - 70.0) < 1.5 and float(dists.medium) >= 100.0 and float(dists.medium) <= 125.0 and absf(float(dists.long) - 150.0) < 1.5)
	st = mk(1)
	no_enemies(st)
	var rec := PHitRecorder.new()
	st.recorder = rec
	var ob: Dictionary = st.obstacles[0]
	st.player.x = float(ob.x) - float(ob.r) - st.player.r - 30.0
	st.player.y = float(ob.y)
	st.step({ "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": true }, STEP)
	for i in 60:
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": true }, STEP)
	ok("5b 지형 차단: 장애물 쪽 회피는 blocked로 끝나고 계측 dodge_events에 남는다(거리 %.1f)" % float(st.player.dodge_dist), String(st.player.dodge_end) == "blocked" and rec.dodge_events.size() == 1 and String(rec.dodge_events[0].end) == "blocked")
	st = mk(1)
	no_enemies(st)
	rec = PHitRecorder.new()
	st.recorder = rec
	st.step({ "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": false }, STEP)
	for i in 20:
		st.step({}, STEP)
	st.step({ "mx": 1.0, "my": 0.0, "dodge_press": true, "dodge_held": false }, STEP)
	ok("5c 재사용 중 거절: 두 번째 누름은 발동 없음(회피 1회), 계측 presses[1] accepted=false reason=cooldown", int(st.stats.dodges) == 1 and rec.presses.size() == 2 and not bool(rec.presses[1].accepted) and String(rec.presses[1].reason) == "cooldown")
	st = mk(1)
	no_enemies(st)
	var drv := PStepDriver.new()
	var rp0 := PReplay.new()
	rp0.begin(st, { "scenario": "test" })
	rp0.attach_recorder(drv)
	drv.note_dodge_press()
	drv.reset() # 일시정지·포커스 상실 = 대기 입력 폐기
	drv.frame(st, STEP, 0.0, 0.0, false)
	var marks_reset := false
	for m in rp0.marks:
		if String(m[1]) == "reset":
			marks_reset = true
	ok("5d 일시정지 뒤 재발동 방지: reset 뒤 프레임에서 회피 없음, 기록에 reset 표식", int(st.stats.dodges) == 0 and marks_reset and rp0.inputs.size() == 1 and not bool(rp0.inputs[0][1].dodge_press))
	# ---------- 6. 계측 켜짐/꺼짐: 고정 입력(같은 봇·seed) 결과 동일, 게임 난수 소비 동일 ----------
	var res := {}
	var replay_rec: Dictionary = {}
	for mode in ["off", "on", "legacy_off", "legacy_on"]:
		var sx := mk(4)
		var bx: PBot = PBot.new("balanced") if mode.begins_with("legacy") else PSkillBot.new("regular", 4)
		var rpx: PReplay = null
		if mode.ends_with("on"):
			sx.recorder = PHitRecorder.new()
			rpx = PReplay.new()
			rpx.begin(sx, { "scenario": "baseline_wolf25", "game_seed": 4, "bot_seed": 4, "profile": "regular" })
		run_fight(sx, bx, 120.0, rpx)
		if sx.recorder != null:
			sx.recorder.finish(sx)
		var sm := sx.summary()
		res[mode] = { "status": String(sm.status), "t": float(sm.elapsed), "hp": float(sm.hp), "kills": int(sm.kills), "taken": float(sm.damage_taken), "rng": int(sx.rng._a), "log": JSON.stringify(sx.attack_log), "steps": int(sx.step_n) }
		if mode == "on":
			replay_rec = rpx.finish(sx)
	ok("6 계측 켜짐/꺼짐 동일: 실력 봇 %s/%.1fs/hp%.0f/처치%d, 난수 상태·공격 순서 동일 · 기존 balanced도 동일" % [String(res.on.status), float(res.on.t), float(res.on.hp), int(res.on.kills)], JSON.stringify(res.off) == JSON.stringify(res.on) and JSON.stringify(res.legacy_off) == JSON.stringify(res.legacy_on) and int(res.on.kills) > 0)
	# ---------- 7. 검산: 피해/보호막/회복/과잉/거절·출처 합·보유시간 DPS·정산 1회 ----------
	st = mk(2)
	rec = PHitRecorder.new()
	st.recorder = rec
	var nov := PSkillBot.new("novice", 2)
	run_fight(st, nov, 120.0)
	rec.finish(st)
	var rr := rec.report()
	var src_sum := 0.0
	for k2 in rr.by_src:
		src_sum += float(rr.by_src[k2])
	var taken_sum := 0.0
	for k2 in st.metrics.taken:
		taken_sum += float(st.metrics.taken[k2])
	ok("7a 전투 검산(novice seed 2, %s, 피격 %d): 최종 HP = 초기 + 회복 − 유효(unexplained 0), 출처 합 %.1f = 유효 피해 %.1f = metrics.taken 합, 무적 거절 %d = 회피! %d" % [st.status, int(rr.hits), src_sum, float(st.stats.damage_taken), int(rr.rejected.get("dodge_invuln", 0)), int(st.stats.perfect_dodges)], bool(rr.checksum.ok) and absf(src_sum - float(st.stats.damage_taken)) < 1e-6 and absf(taken_sum - float(st.stats.damage_taken)) < 1e-6 and int(rr.rejected.get("dodge_invuln", 0)) == int(st.stats.perfect_dodges) and int(rr.hits) > 0)
	st = mk(1)
	no_enemies(st)
	rec = PHitRecorder.new()
	st.recorder = rec
	st.step({}, STEP)
	st.player.shield = 20.0
	st.step({}, STEP)
	st.damage_player(8.0, "wolf:bite")
	for i in 80:
		st.step({}, STEP)
	st.damage_player(50.0, "wolf:dash")
	for i in 80:
		st.step({}, STEP)
	st.player.hp += 20.0
	st.step({}, STEP)
	st.damage_player(500.0, "wolf:bite")
	st.step({}, STEP)
	rec.finish(st)
	var cs := rec.checksum()
	ok("7b 보호막 부여 20 → 8 흡수(유효 0) · 50 요청 = 12 흡수 + 유효 38 · 회복 20 · 500 요청 = 유효 82 + 과잉 418 → 최종 0 = 100 + 20 − 120, 흡수 합 20, 명목 합 %.0f" % float(st.stats.damage_taken_nominal), bool(cs.ok) and float(cs.shield_granted) == 20.0 and float(cs.shield_absorbed) == 20.0 and float(cs.effective) == 120.0 and float(cs.overkill) == 418.0 and float(cs.gained) == 20.0 and float(cs.final) == 0.0 and rec.hits.size() == 3 and float(rec.hits[0].effective) == 0.0 and float(rec.hits[0].absorbed) == 8.0 and float(rec.hits[1].absorbed) == 12.0 and float(rec.hits[1].effective) == 38.0 and float(rec.hits[2].overkill) == 418.0 and float(st.stats.damage_taken_nominal) == 558.0)
	var prun := { "dmgStats": { "combats": [], "byKey": {} } }
	var sfight := mk(3)
	run_fight(sfight, PSkillBot.new("skilled", 3), 120.0)
	var r1 := PStats.record(prun, sfight, { "kind": "sortie" })
	var r2 := PStats.record(prun, sfight, { "kind": "sortie" })
	var agg := PStats.aggregate(prun)
	var dps_ok := true
	var sword_active := -1.0
	for row in agg.rows:
		if absf(float(row.dps) - float(row.amount) / maxf(1e-6, float(row.active))) > 0.11:
			dps_ok = false
		if String(row.key) == "weapon:sword":
			sword_active = float(row.active)
	ok("7c PStats 재사용: 정산 1회(재기록 {}), 보유시간 DPS = 피해/보유시간, 검 보유시간 %.1f = 전투시간 %.2f(0.1 반올림), 검증 통과" % [sword_active, float(sfight.t)], not r1.is_empty() and r2.is_empty() and (prun.dmgStats.combats as Array).size() == 1 and dps_ok and absf(sword_active - float(sfight.t)) <= 0.051 and PStats.verify(prun).all(func(v): return bool(v.ok)))
	# ---------- 8. 기록 재생: 해시·결과 일치, 버전 불일치 거부, 변조 감지, JSON 왕복 ----------
	var fresh := mk(4)
	var rres := PReplay.replay(fresh, replay_rec)
	ok("8a 재생 일치: 해시 %d개 대조, 결과 %s = %s" % [int(rres.hash_checked), String(rres.status), String(res.on.status)], bool(rres.ok) and int(rres.hash_checked) == (replay_rec.hashes as Array).size() and int(rres.hash_checked) > 0 and String(rres.status) == String(res.on.status) and int(rres.steps) == int(res.on.steps))
	var jr = JSON.parse_string(JSON.stringify(replay_rec))
	var rres2 := PReplay.replay(mk(4), jr)
	ok("8b JSON 왕복 뒤 재생도 일치(실수 17자리)", bool(rres2.ok) and int(rres2.hash_checked) == int(rres.hash_checked))
	var bad := replay_rec.duplicate(true)
	bad.header.game_version = "godot-0.0.0"
	var rb := PReplay.replay(mk(4), bad)
	var bad2 := replay_rec.duplicate(true)
	bad2.format = "other/9"
	var rb2 := PReplay.replay(mk(4), bad2)
	ok("8c 버전 불일치 명시적 거부: %s / %s" % [String(rb.reason), String(rb2.reason)], bool(rb.refused) and not bool(rb.ok) and String(rb.reason).find("게임 버전") >= 0 and bool(rb2.refused) and String(rb2.reason).find("형식") >= 0)
	var tam := replay_rec.duplicate(true)
	var ti: int = mini(5, (tam.inputs as Array).size() - 1)
	tam.inputs[ti][1].mx = -float(tam.inputs[ti][1].mx) - 0.5
	var rt := PReplay.replay(mk(4), tam)
	ok("8d 입력 변조(항목 %d) → 해시 불일치 감지(첫 불일치 단계 %d)" % [ti, int(rt.mismatches[0].step) if rt.mismatches.size() > 0 else -1], not bool(rt.ok) and rt.mismatches.size() >= 1)
	# ---------- 9. 배치 재개: 중복 없음, 예산 중단 뒤 재개, 캐시 키 불일치 무효화 ----------
	var base_dir := "user://bot_runs_test"
	var abs_dir := ProjectSettings.globalize_path(base_dir)
	if DirAccess.dir_exists_absolute(abs_dir):
		_rm_rf(abs_dir)
	var bopts := { "PROPHECY_BOT_RUN_ID": "t_resume", "base_dir": base_dir, "PROPHECY_BOT_SCENARIOS": "baseline_wolf25", "PROPHECY_BOT_PROFILES": "regular", "PROPHECY_BOT_SEEDS": "1,2", "PROPHECY_BOT_MAX_SEC": "60", "PROPHECY_BOT_BUDGET_SEC": "0" }
	var bb := PBotBatch.new()
	var o1 := bb.run(bopts)
	var bopts2 := bopts.duplicate()
	bopts2.PROPHECY_BOT_BUDGET_SEC = "600"
	var o2 := PBotBatch.new().run(bopts2)
	var o3 := PBotBatch.new().run(bopts2)
	var lines := 0
	var f := FileAccess.open(base_dir.path_join("t_resume/results.jsonl"), FileAccess.READ)
	while f != null and not f.eof_reached():
		if f.get_line().strip_edges() != "":
			lines += 1
	if f != null:
		f.close()
	var budget_msg := false
	for m in o1.messages:
		if String(m).begins_with("BUDGET_EXCEEDED"):
			budget_msg = true
	ok("9a 예산 0 → 전투 없이 중단(코드 3, 재개 안내) → 예산 600으로 재개 완료 2행 → 다시 실행 시 0행 추가, results.jsonl 2줄(중복 없음)", int(o1.code) == 3 and int(o1.rows.size()) == 0 and budget_msg and int(o2.code) == 0 and bool(o2.complete) and int(o2.did) == 2 and int(o3.code) == 0 and int(o3.did) == 0 and lines == 2 and int(o3.rows.size()) == 2)
	var bopts3 := bopts2.duplicate()
	bopts3.env_override = { "data_hash": "deadbeef" }
	var o4 := PBotBatch.new().run(bopts3)
	var inval := false
	for m in o4.messages:
		if String(m).begins_with("CACHE_INVALID") and String(m).find("data_hash") >= 0:
			inval = true
	ok("9b 캐시 키(데이터 해시) 불일치 → 명시적 무효화 메시지·코드 2·기존 행 유지", int(o4.code) == 2 and inval and int(o4.rows.size()) == 2)
	boss3_observe_tests()
	# ---------- 10. 실제 장면(main.tscn): 프로필 선택 → 시작 → 결과 → 재시작. 모두 함수 호출(버튼과 같은 함수), 사람 입력·합성 키 이벤트 없음 ----------
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.seed_v = 3
	main.set_bot_profile("novice")
	main.start_fight(true)
	var bot_ok: bool = main.view.bot is PSkillBot and String((main.view.bot as PSkillBot).profile_id) == "novice" and main.screen == "combat"
	var guard := 0
	while main.screen == "combat" and guard < 8000:
		main.view._process(1.0 / 60.0)
		guard += 1
	var st_res := String(main.last_summary.get("status", ""))
	var result_ok: bool = main.screen == "result" and st_res in ["won", "lost", "timeout"]
	main.retry_fight()
	var retry_ok: bool = main.screen == "combat" and main.view.bot is PSkillBot and String((main.view.bot as PSkillBot).profile_id) == "novice" and int(main.view.st.step_n) == 0 and main.view.running
	ok("10a 장면(함수 호출): set_bot_profile('novice') → start_fight(true) → PSkillBot novice 전투 → 결과 화면(%s, %d프레임) → retry_fight → 같은 프로필로 새 전투" % [st_res, guard], bot_ok and result_ok and retry_ok)
	main.go_title()
	main.set_bot_profile("legacy")
	main.start_fight(true)
	var legacy_ok: bool = main.view.bot != null and not (main.view.bot is PSkillBot) and String(main.view.bot.policy) == "active"
	main.go_title()
	var rec_dir := ProjectSettings.globalize_path("user://recordings")
	if DirAccess.dir_exists_absolute(rec_dir):
		_rm_rf(rec_dir) # 이전 실행의 기록을 비운다(APPDATA 격리 폴더)
	main.record_inputs = true
	main.start_fight(false)
	var rec_attached: bool = main.view.bot == null and main.view.driver.recorder != null
	for i in 30:
		main.view._process(1.0 / 60.0)
	main.view.running = false
	main.view.st.status = "won" # 상태 주입(사람 승리 주장 아님): 기록 저장 경로만 확인
	main._on_finished(main.view.st.summary())
	var files := []
	var rd := DirAccess.open("user://recordings")
	if rd != null:
		rd.list_dir_begin()
		var fn := rd.get_next()
		while fn != "":
			if fn.ends_with(".json"):
				files.append(fn)
			fn = rd.get_next()
		rd.list_dir_end()
	var loaded: Dictionary = PReplay.load_file("user://recordings/" + String(files[0])) if files.size() > 0 else {}
	var hdr: Dictionary = loaded.get("header", {})
	ok("10b 기존 정책 선택 시 D33 봇(active) 그대로 · '이번 전투 입력 기록' 켜고 사람 경로(봇 없음) → user://recordings/<시각>_first_fight….json 저장(항목 %d, 형식 %s, 시나리오 %s)" % [(loaded.get("inputs", []) as Array).size(), String(loaded.get("format", "")), String(hdr.get("scenario", ""))], legacy_ok and rec_attached and files.size() == 1 and String(loaded.get("format", "")) == PReplay.FORMAT and String(hdr.get("scenario", "")).begins_with("first_fight") and String(hdr.get("profile", "")) == "human" and main.view.driver.recorder == null)
	main.queue_free()
	await process_frame
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 11. 신규 관문 보스 6종 관측(observe-2): 예고 단계(warn/lock/active)마다 그려지는 도형이 스냅샷 threats에 render.gd와 같은 수치로 있고, 숨은 필드 이름이 없고, 숨은 값을 바꿔도 스냅샷·입력이 같다 ----------
const HIDDEN3 := ["land_at", "burrow_plan", "ring_gap", "hit_done", "rubble_tick", "shot_timer", "guard_real", "wait_t", "summon_budget", "last_summon", "dash_end", "explode_at", "dash_ready_at", "bite_cd", "\"pending\"", "\"rng\"", "aim_angle", "state_t"]

## boss3_tests.ready_state와 같은 고정: 입장을 지나 접근 상태, 보스·플레이어 위치 지정(검 Lv1 빌드)
func boss_ready(id: String, bx: float, by: float, px: float, py: float) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 5, "arena": "clearing", "boss": true, "boss_id": id, "region_id": "boss", "xp_kill_mult": 0.3 })
	for i in int(round((float(PCatalog.boss_def(id).intro) + 0.2) / STEP)):
		st.step({}, STEP)
	var bz := st.boss
	bz.x = bx
	bz.y = by
	st.player.x = px
	st.player.y = py
	bz.state = "approach"
	bz.state_t = 0.0
	bz.approach_t = 0.0
	return st

func until_state(st: CombatState, s: String, max_sec: float, input: Dictionary = {}) -> bool:
	for i in int(round(max_sec / STEP)):
		if String(st.boss.state) == s:
			return true
		st.step(input, STEP)
	return String(st.boss.state) == s

func steps3(st: CombatState, sec: float, input: Dictionary = {}) -> void:
	for i in int(round(sec / STEP)):
		st.step(input, STEP)

## 스냅샷에서 보스의 위협 중 attack_id가 접미사로 끝나는 것(""이면 부분 없는 본 위협)
func th_of(snap: Dictionary, suffix: String) -> Dictionary:
	var bid := int(snap.boss.id)
	for th in snap.threats:
		if int(th.enemy_id) != bid:
			continue
		var id := String(th.attack_id)
		if suffix == "" and id.find(":") < 0:
			return th
		if suffix != "" and id.ends_with(suffix):
			return th
	return {}

func boss_th_n(snap: Dictionary) -> int:
	var n := 0
	for th in snap.threats:
		if int(th.enemy_id) == int(snap.boss.id):
			n += 1
	return n

func zone_th(snap: Dictionary, type: String) -> Array:
	var out := []
	for th in snap.threats:
		if String(th.attack_id).begins_with("zone:" + type + ":"):
			out.append(th)
	return out

func near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps

## 위협 사전이 기대 값(kind/phase/label + 숫자 필드)과 같은가. 숫자는 1e-6, 각도는 ang_diff
func th_is(th: Dictionary, want: Dictionary) -> bool:
	if th.is_empty():
		return false
	for k in want:
		var v = want[k]
		if typeof(v) == TYPE_STRING:
			if String(th.get(k, "")) != String(v):
				return false
		elif String(k) == "ang":
			if absf(PGeom.ang_diff(float(th.ang), float(v))) > 1e-6:
				return false
		elif absf(float(th.get(k, -9999.0)) - float(v)) > 1e-4:
			return false
	return true

## 숨은 값만 바꾼다(게임 난수·대기열·보스 내부 타이머·소환 예산). 되돌릴 값을 돌려준다
func hide3(st: CombatState) -> Dictionary:
	var saved := hide(st)
	var bz := st.boss
	saved.boss = {}
	for k in ["wait_t", "rubble_tick", "shot_timer", "last_summon", "summon_budget", "approach_t"]:
		if bz.has(k):
			saved.boss[k] = bz[k]
	if bz.has("wait_t"):
		bz.wait_t = float(bz.wait_t) + 0.3
	if bz.has("rubble_tick"):
		bz.rubble_tick = float(bz.rubble_tick) + 0.2
	if bz.has("shot_timer"):
		bz.shot_timer = float(bz.shot_timer) + 0.1
	if bz.has("last_summon"):
		bz.last_summon = float(bz.last_summon) - 5.0
	if bz.has("summon_budget"):
		bz.summon_budget = int(bz.summon_budget) + 1
	if bz.has("approach_t"):
		bz.approach_t = float(bz.approach_t) + 0.05
	return saved

func unhide3(st: CombatState, saved: Dictionary) -> void:
	unhide(st, saved)
	for k in saved.boss:
		st.boss[k] = saved.boss[k]

func boss3_observe_tests() -> void:
	var pr_: float = float(mk(1).player.r)
	# ----- 성문 파수장: 방패 자세(부채꼴 110/100°) · 방패 돌파(통로, 2단계 휩쓸기 150/200°) · 석궁 3발(통로 3 → 투사체 3) -----
	var st := boss_ready("gate_warden", 480.0, 300.0, 480.0, 420.0)
	var bz := st.boss
	var G: Dictionary = PCatalog.boss_def("gate_warden")
	PBoss3.begin(st, bz, "guard")
	steps3(st, 0.2)
	var sn := PObserve.snapshot(st)
	var a1 := th_is(th_of(sn, ""), { "kind": "sector", "phase": "warn", "label": "shove", "r": 110.0, "half": PGeom.deg(100.0) / 2.0, "ang": float(bz.aim_angle), "prog": float(bz.state_t) / 0.8, "x": float(bz.x), "y": float(bz.y) })
	var g1: Dictionary = sn.boss.guard
	var guard_ok: bool = not g1.is_empty() and near(float(g1.r), 150.0) and near(float(g1.half), PGeom.deg(120.0) / 2.0) and near(float(g1.reduce), 0.4) and float(g1.left) < 0.0
	until_state(st, "guard_lock", 2.0)
	sn = PObserve.snapshot(st)
	var a2 := th_is(th_of(sn, ""), { "kind": "sector", "phase": "lock", "label": "shove", "r": 110.0, "ang": float(bz.dir), "prog": 1.0 })
	until_state(st, "recover", 2.0)
	var a3: bool = boss_th_n(PObserve.snapshot(st)) == 0 and (PObserve.snapshot(st).boss.guard as Dictionary).is_empty()
	ok("11a 파수장 방패 자세: guard_aim → 부채꼴 warn(r110·100°·추적 각·진행률) + boss.guard(정면 120°·r150·-40%%), guard_lock → lock(고정 각), 빈틈엔 위협·방패 표시 없음", a1 and guard_ok and a2 and a3)
	st = boss_ready("gate_warden", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "breach")
	steps3(st, 0.2)
	sn = PObserve.snapshot(st)
	var plen: float = float(PBoss3.path_from(st, float(bz.x), float(bz.y), float(bz.r), float(bz.aim_angle), 440.0)["len"])
	var b1 := th_is(th_of(sn, ""), { "kind": "corridor", "phase": "warn", "label": "breach", "ang": float(bz.aim_angle), "len": plen, "w": (40.0 + pr_) * 2.0, "prog": float(bz.state_t) / 0.8 })
	until_state(st, "breach_lock", 2.0)
	sn = PObserve.snapshot(st)
	var b2 := th_is(th_of(sn, ""), { "kind": "corridor", "phase": "lock", "ang": float(bz.dir), "len": float(bz.dash_len), "prog": 1.0 })
	until_state(st, "breach", 1.0)
	var b3 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "corridor", "phase": "active", "len": float(bz.dash_len) })
	until_state(st, "bsweep_aim", 3.0)
	steps3(st, 0.1)
	var b4 := th_is(th_of(PObserve.snapshot(st), ":sweep"), { "kind": "sector", "phase": "warn", "label": "bsweep", "r": 150.0, "half": PGeom.deg(200.0) / 2.0, "ang": float(bz.aim_angle) })
	until_state(st, "bsweep_lock", 2.0)
	var b5 := th_is(th_of(PObserve.snapshot(st), ":sweep"), { "kind": "sector", "phase": "lock", "ang": float(bz.dir) })
	ok("11b 파수장 방패 돌파(2단계): breach_aim → 통로 warn(추적 각·path_from 길이·폭 (40+%.0f)×2), breach_lock → lock(dash_len), breach → active, 돌파 끝 넓은 휩쓸기 :sweep 부채꼴 r150·200° warn→lock" % pr_, b1 and b2 and b3 and b4 and b5)
	st = boss_ready("gate_warden", 200.0, 520.0, 600.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "bolts")
	var aid := "e%d#%d" % [int(bz.id), int(bz.attack_n)]
	steps3(st, 0.2)
	sn = PObserve.snapshot(st)
	var c1 := true
	for i in 3:
		c1 = c1 and th_is(th_of(sn, ":bolt%d" % i), { "kind": "corridor", "phase": "warn", "label": "bolt%d" % (i + 1), "len": 620.0, "w": 26.0, "ang": float(bz.aim_angle) + PGeom.deg(18.0) * float(i - 1), "prog": float(bz.state_t) / 0.7 })
	until_state(st, "bolts_lock", 2.0)
	sn = PObserve.snapshot(st)
	var c2 := th_is(th_of(sn, ":bolt0"), { "phase": "lock", "ang": float(bz.dir) - PGeom.deg(18.0) }) and th_is(th_of(sn, ":bolt2"), { "phase": "lock", "ang": float(bz.dir) + PGeom.deg(18.0) })
	until_state(st, "recover", 2.0)
	sn = PObserve.snapshot(st)
	var c3: bool = (sn.projectiles as Array).size() == 3 and String(sn.projectiles[0].id) == aid + ":proj0" and String(sn.projectiles[2].kind) == "boss_bolt" and th_is(th_of(sn, ":proj1"), { "kind": "lane", "phase": "active", "type": "boss_bolt", "w": 20.0, "len": PObserve.PROJ_LOOK }) and String(th_of(sn, ":proj1").attack_id) == aid + ":proj1"
	ok("11c 파수장 석궁: bolts_aim → 통로 3(:bolt0~2, 0°·±18°, 길이 620, 폭 16+10) warn, bolts_lock → lock(고정 각), 발사 뒤 같은 공격의 투사체 %s:proj0~2(boss_bolt, 폭 16+4 통로 220)" % aid, c1 and c2 and c3)
	# ----- 포자 어미: 포자 탄(위치 예고 원 + 남은 초) · 포자 고리(빈 구간 뺀 부채꼴 → 확산 띠) · 분사(부채꼴) -----
	st = boss_ready("spore_matriarch", 480.0, 300.0, 480.0, 480.0)
	bz = st.boss
	PBoss3.begin(st, bz, "shot")
	until_state(st, "shot_wait", 2.0)
	sn = PObserve.snapshot(st)
	var mk1: Dictionary = bz.marks[0]
	var m1 := th_is(th_of(sn, ":mark1"), { "kind": "circle", "phase": "warn", "label": "shot1", "x": float(mk1.x), "y": float(mk1.y), "r": 62.0, "shown_left": float(mk1.land_at) - float(st.t), "prog": 1.0 - (float(mk1.land_at) - float(st.t)) / 1.0 })
	var at_player: bool = near(float(mk1.x), float(st.player.x)) and near(float(mk1.y), float(st.player.y))
	steps3(st, 0.65)
	sn = PObserve.snapshot(st)
	var m2 := th_is(th_of(sn, ":mark1"), { "phase": "lock" }) and float(th_of(sn, ":mark1").shown_left) < 0.4
	steps3(st, 0.5)
	sn = PObserve.snapshot(st)
	var m3: bool = th_of(sn, ":mark1").is_empty() and zone_th(sn, "spore").size() == 1 and String(zone_th(sn, "spore")[0].phase) == "active"
	st = boss_ready("spore_matriarch", 480.0, 300.0, 400.0, 480.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "shot")
	steps3(st, 0.7 + 0.45 + 0.1)
	sn = PObserve.snapshot(st)
	var m4: bool = not th_of(sn, ":mark1").is_empty() and not th_of(sn, ":mark2").is_empty() and float(th_of(sn, ":mark2").shown_left) > float(th_of(sn, ":mark1").shown_left)
	ok("11d 포자 탄: 표시 원(:mark1, r62, 플레이어 자리)에 남은 초 shown_left(1.0→0), 0.4초 미만은 lock, 착탄 뒤 표식 사라지고 잔류 구름 zone:spore active; 2단계 두 표식(:mark2가 더 늦음)", m1 and at_player and m2 and m3 and m4)
	st = boss_ready("spore_matriarch", 480.0, 300.0, 480.0, 480.0)
	bz = st.boss
	PBoss3.begin(st, bz, "ring")
	steps3(st, 0.2)
	sn = PObserve.snapshot(st)
	var gap: float = float(bz.ring_gap)
	var gh: float = float(bz.ring_half)
	var r1 := th_is(th_of(sn, ""), { "kind": "sector", "phase": "warn", "label": "ring", "r": 340.0, "ang": gap + PI, "half": PI - gh, "prog": float(bz.state_t) / 0.9 }) and near(gh, PGeom.deg(70.0) / 2.0)
	until_state(st, "ring_lock", 2.0)
	var r2 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "sector", "phase": "lock", "prog": 1.0 })
	until_state(st, "ring", 1.0)
	steps3(st, 0.3)
	sn = PObserve.snapshot(st)
	var band: Dictionary = th_of(sn, "")
	var r3 := th_is(band, { "kind": "band", "phase": "active", "label": "ring", "r": float(bz.ring_r) + 22.0, "w": 44.0, "ang": gap + PI, "half": PI - gh })
	var rr: float = float(bz.ring_r)
	var on_band := PObserve.inside(band, float(bz.x) + cos(gap + PI) * rr, float(bz.y) + sin(gap + PI) * rr, pr_)
	var in_gap := PObserve.inside(band, float(bz.x) + cos(gap) * rr, float(bz.y) + sin(gap) * rr, pr_)
	var passed := PObserve.inside(band, float(bz.x) + cos(gap + PI) * maxf(0.0, rr - 44.0 - pr_ - 8.0), float(bz.y) + sin(gap + PI) * maxf(0.0, rr - 44.0 - pr_ - 8.0), pr_)
	var d_band := PObserve.dist_to(band, float(bz.x) + cos(gap + PI) * (rr + 22.0 + pr_ + 50.0), float(bz.y) + sin(gap + PI) * (rr + 22.0 + pr_ + 50.0), pr_)
	ok("11e 포자 고리: ring_aim → 빈 구간(70°)을 뺀 부채꼴 r340 warn, ring_lock → lock, 확산 중 → 띠(band, ring_r±22) active: 띠 위 안·빈 구간 밖·지나간 안쪽 밖(%s/%s/%s), 띠 바깥 50px 거리 %.1f" % [str(on_band), str(in_gap), str(passed), d_band], r1 and r2 and r3 and on_band and not in_gap and not passed and near(d_band, 50.0, 0.01))
	st = boss_ready("spore_matriarch", 480.0, 300.0, 480.0, 400.0)
	bz = st.boss
	PBoss3.begin(st, bz, "spray")
	steps3(st, 0.2)
	var sp1 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "sector", "phase": "warn", "label": "spray", "r": 120.0, "half": PGeom.deg(90.0) / 2.0, "ang": float(bz.aim_angle) })
	until_state(st, "spray_lock", 2.0)
	var sp2 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "sector", "phase": "lock", "ang": float(bz.dir) })
	ok("11f 포자 분사: spray_aim → 부채꼴 r120·90° warn(추적 각), spray_lock → lock", sp1 and sp2)
	# ----- 굴착 거수: 낙석 3(순번·남은 초 원 → 잔해 지역) · 굴착 돌파 2방향(현재 통로 + 고정된 다음 통로) -----
	st = boss_ready("excavation_behemoth", 480.0, 120.0, 480.0, 400.0)
	bz = st.boss
	PBoss3.begin(st, bz, "rockfall")
	until_state(st, "rock_wait", 2.0)
	sn = PObserve.snapshot(st)
	var rocks: Array = bz.rocks
	var k1: bool = rocks.size() == 3
	for i in rocks.size():
		var rk: Dictionary = rocks[i]
		k1 = k1 and th_is(th_of(sn, ":rock%d" % (i + 1)), { "kind": "circle", "phase": "warn", "label": "rock%d" % (i + 1), "x": float(rk.x), "y": float(rk.y), "r": 72.0, "shown_left": float(rk.land_at) - float(st.t) })
	var rock_order: bool = k1 and float(th_of(sn, ":rock1").shown_left) < float(th_of(sn, ":rock2").shown_left) and float(th_of(sn, ":rock2").shown_left) < float(th_of(sn, ":rock3").shown_left) and near(float(th_of(sn, ":rock2").shown_left) - float(th_of(sn, ":rock1").shown_left), 0.5, 0.02)
	steps3(st, 0.6)
	sn = PObserve.snapshot(st)
	var k2: bool = th_is(th_of(sn, ":rock1"), { "phase": "lock" }) and th_is(th_of(sn, ":rock2"), { "phase": "warn" })
	steps3(st, 0.45)
	sn = PObserve.snapshot(st)
	var rub := zone_th(sn, "rubble")
	var k3: bool = th_of(sn, ":rock1").is_empty() and not th_of(sn, ":rock2").is_empty() and rub.size() == 1 and th_is(rub[0], { "kind": "circle", "phase": "active", "harm": "damage", "label": "rubble", "x": float(rocks[0].x), "y": float(rocks[0].y), "r": 72.0 }) and String(sn.zones[0].type) == "rubble"
	ok("11g 낙석: rock_wait → 원 3(:rock1~3, r72, 표시 순번·남은 초 0.5초 간격) warn, 0.4초 미만 lock, 착지한 자리는 zone:rubble active 원(잔해)로 이어짐", rock_order and k2 and k3)
	st = boss_ready("excavation_behemoth", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "burrow")
	steps3(st, 0.2)
	sn = PObserve.snapshot(st)
	plen = float(PBoss3.path_from(st, float(bz.x), float(bz.y), float(bz.r), float(bz.aim_angle), 480.0)["len"])
	var u1 := th_is(th_of(sn, ":burrow1"), { "kind": "corridor", "phase": "warn", "label": "burrow1", "ang": float(bz.aim_angle), "len": plen, "w": (46.0 + pr_) * 2.0, "prog": float(bz.state_t) / 0.9 }) and th_of(sn, ":burrow2").is_empty()
	until_state(st, "burrow_lock", 2.0)
	sn = PObserve.snapshot(st)
	var plan: Array = bz.burrow_plan
	var u2: bool = plan.size() == 2 and th_is(th_of(sn, ":burrow1"), { "phase": "lock", "x": float(bz.x), "y": float(bz.y), "ang": float(plan[0].ang), "len": float(plan[0].len) }) and th_is(th_of(sn, ":burrow2"), { "kind": "corridor", "phase": "lock", "label": "burrow2", "x": float(plan[1].x), "y": float(plan[1].y), "ang": float(plan[1].ang), "len": float(plan[1].len) })
	until_state(st, "burrow", 1.0)
	var u3 := th_is(th_of(PObserve.snapshot(st), ":burrow1"), { "phase": "active" })
	steps3(st, 0.05)
	until_state(st, "burrow_lock", 2.0)
	sn = PObserve.snapshot(st)
	var u4: bool = int(bz.dash_seq) == 2 and th_of(sn, ":burrow1").is_empty() and th_is(th_of(sn, ":burrow2"), { "phase": "lock", "x": float(bz.x), "y": float(bz.y) })
	ok("11h 굴착 돌파(2단계): burrow_aim → :burrow1 통로 warn(추적 각·path_from 길이), burrow_lock → :burrow1 lock + 고정된 :burrow2 lock(첫 경로 끝에서), burrow → :burrow1 active, 둘째 고정 땐 :burrow2만", u1 and u2 and u3 and u4)
	# ----- 서리 추적자: 얼음 발사(통로 → 투사체) · 얼음길 3줄(통로 → 빙판 slow 지역) · 옆 이동(예고 없음) → 돌진 -----
	st = boss_ready("frost_stalker", 300.0, 300.0, 700.0, 300.0)
	bz = st.boss
	PBoss3.begin(st, bz, "bolt")
	aid = "e%d#%d" % [int(bz.id), int(bz.attack_n)]
	steps3(st, 0.2)
	var f1 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "corridor", "phase": "warn", "label": "icebolt", "len": 640.0, "w": 28.0, "ang": float(bz.aim_angle), "prog": float(bz.state_t) / 0.6 })
	until_state(st, "bolt_lock", 2.0)
	var f2 := th_is(th_of(PObserve.snapshot(st), ""), { "phase": "lock", "ang": float(bz.dir) })
	until_state(st, "recover", 2.0)
	sn = PObserve.snapshot(st)
	var f3: bool = (sn.projectiles as Array).size() == 1 and String(sn.projectiles[0].kind) == "boss_icebolt" and th_is(th_of(sn, ":proj0"), { "kind": "lane", "phase": "active", "type": "boss_icebolt", "w": 22.0 }) and String(th_of(sn, ":proj0").attack_id) == aid + ":proj0"
	ok("11i 얼음 발사: bolt_aim → 통로 warn(길이 640, 폭 18+10), bolt_lock → lock, 발사 뒤 같은 공격의 투사체 %s:proj0(boss_icebolt)" % aid, f1 and f2 and f3)
	st = boss_ready("frost_stalker", 300.0, 300.0, 700.0, 300.0)
	bz = st.boss
	PBoss3.begin(st, bz, "icepath")
	steps3(st, 0.2)
	sn = PObserve.snapshot(st)
	var i1 := true
	for i in 3:
		i1 = i1 and th_is(th_of(sn, ":lane%d" % i), { "kind": "corridor", "phase": "warn", "label": "icepath%d" % (i + 1), "len": 420.0, "w": 70.0, "ang": float(bz.aim_angle) + PGeom.deg(40.0) * float(i - 1), "prog": float(bz.state_t) / 0.8 })
	until_state(st, "path_lock", 2.0)
	sn = PObserve.snapshot(st)
	var i2 := true
	for i in 3:
		i2 = i2 and th_is(th_of(sn, ":lane%d" % i), { "phase": "lock", "ang": float(bz.lanes[i]) })
	until_state(st, "recover", 2.0)
	sn = PObserve.snapshot(st)
	var ice := zone_th(sn, "ice")
	var i3: bool = ice.size() > 0 and th_is(ice[0], { "kind": "circle", "phase": "active", "harm": "slow", "label": "ice", "r": 38.0 }) and boss_th_n(sn) == 0
	var slow_ok := true
	var ice_n := 0
	for z in sn.zones:
		if String(z.type) == "ice":
			ice_n += 1
			slow_ok = slow_ok and near(float(z.slow), 0.6)
	ok("11j 얼음길: path_aim → 통로 3(:lane0~2, 0°·±40°, 길이 420, 폭 70) warn, path_lock → lock(고정 각), 실행 뒤 빙판 %d개 = harm slow 원(r38) + zones.slow 0.6(걷기만)" % ice_n, i1 and i2 and i3 and slow_ok and ice_n == ice.size())
	st = boss_ready("frost_stalker", 300.0, 300.0, 700.0, 300.0)
	bz = st.boss
	PBoss3.begin(st, bz, "dash")
	steps3(st, 0.2)
	var d1: bool = String(bz.state) == "sidestep" and boss_th_n(PObserve.snapshot(st)) == 0
	until_state(st, "dash_aim", 1.0)
	steps3(st, 0.2)
	var d2 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "corridor", "phase": "warn", "label": "dash", "ang": float(bz.aim_angle), "w": (36.0 + pr_) * 2.0, "prog": float(bz.state_t) / 0.7 })
	until_state(st, "dash_lock", 2.0)
	var d3 := th_is(th_of(PObserve.snapshot(st), ""), { "phase": "lock", "ang": float(bz.dir), "len": float(bz.dash_len) })
	until_state(st, "dash", 1.0)
	var d4 := th_is(th_of(PObserve.snapshot(st), ""), { "phase": "active" })
	ok("11k 서리 옆 이동 → 돌진: sidestep엔 예고 없음(몸만 이동), dash_aim → 통로 warn, dash_lock → lock, dash → active", d1 and d2 and d3 and d4)
	# ----- 핏빛 사냥왕: 발톱(부채꼴 170/170°) · 추적 돌진 2회(:dash1 → 재조준 :dash2에 '방향 고정 n초 뒤' 표시 → 재고정 → 둘째 돌진) -----
	st = boss_ready("blood_hunt_king", 480.0, 300.0, 480.0, 420.0)
	bz = st.boss
	PBoss3.begin(st, bz, "claw")
	steps3(st, 0.2)
	var h1 := th_is(th_of(PObserve.snapshot(st), ""), { "kind": "sector", "phase": "warn", "label": "claw", "r": 170.0, "half": PGeom.deg(170.0) / 2.0, "ang": float(bz.aim_angle), "prog": float(bz.state_t) / 0.7 })
	until_state(st, "claw_lock", 2.0)
	var h2 := th_is(th_of(PObserve.snapshot(st), ""), { "phase": "lock", "ang": float(bz.dir) })
	ok("11l 발톱 휩쓸기: claw_aim → 부채꼴 r170·170° warn, claw_lock → lock", h1 and h2)
	st = boss_ready("blood_hunt_king", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "dash")
	steps3(st, 0.2)
	sn = PObserve.snapshot(st)
	var j1 := th_is(th_of(sn, ":dash1"), { "kind": "corridor", "phase": "warn", "label": "dash1", "ang": float(bz.aim_angle), "w": (42.0 + pr_) * 2.0, "prog": float(bz.state_t) / 0.7, "shown_left": -1.0 }) and th_of(sn, ":dash2").is_empty()
	until_state(st, "dash_lock", 2.0)
	var j2 := th_is(th_of(PObserve.snapshot(st), ":dash1"), { "phase": "lock", "ang": float(bz.dir), "len": float(bz.dash_len) })
	until_state(st, "dash", 1.0)
	var j3 := th_is(th_of(PObserve.snapshot(st), ":dash1"), { "phase": "active" })
	until_state(st, "dash_reaim", 2.0)
	steps3(st, 0.1)
	sn = PObserve.snapshot(st)
	var j4: bool = th_of(sn, ":dash1").is_empty() and th_is(th_of(sn, ":dash2"), { "kind": "corridor", "phase": "warn", "label": "dash2", "ang": float(bz.aim_angle), "shown_left": 0.45 - float(bz.state_t), "prog": float(bz.state_t) / 0.45 })
	until_state(st, "dash_relock", 1.0)
	var j5 := th_is(th_of(PObserve.snapshot(st), ":dash2"), { "phase": "lock", "ang": float(bz.dir), "shown_left": -1.0 })
	until_state(st, "dash", 1.0)
	var j6: bool = int(bz.dash_seq) == 2 and th_is(th_of(PObserve.snapshot(st), ":dash2"), { "phase": "active" })
	ok("11m 추적 돌진 2회: :dash1 warn→lock→active, 재조준 지점에선 :dash2 warn + 표시된 '방향 고정 n초 뒤'(shown_left), 재고정 → lock(shown_left −1), 둘째 돌진 active", j1 and j2 and j3 and j4 and j5 and j6)
	# ----- 종말의 집행관: 세로 절단선 2(통로 x=선, y=0, 각 π/2, 길이 = 경기장 높이, 폭 80) · 회전 방어 자세(boss.guard, 위협 아님) → 큰 베기(부채꼴 160/140°) -----
	st = boss_ready("doom_executor", 480.0, 120.0, 480.0, 400.0)
	bz = st.boss
	PBoss3.begin(st, bz, "slash")
	steps3(st, 0.3, { "mx": 1.0 })
	sn = PObserve.snapshot(st)
	var x0: bool = near(float(bz.slashes[0].x), float(st.player.x)) and float(st.player.x) > 480.0
	var e1 := th_is(th_of(sn, ":slash1"), { "kind": "corridor", "phase": "warn", "label": "slash1", "x": float(st.player.x), "y": 0.0, "ang": PI / 2.0, "len": float(st.arena_h), "w": 80.0, "prog": float(bz.state_t) / 0.8 }) and th_of(sn, ":slash2").is_empty()
	until_state(st, "slash_lock", 2.0)
	var x1: float = float(bz.slashes[0].x)
	steps3(st, 0.1, { "mx": 1.0 })
	var e2 := th_is(th_of(PObserve.snapshot(st), ":slash1"), { "phase": "lock", "x": x1, "prog": 1.0 })
	until_state(st, "slash_gap", 1.0)
	steps3(st, 0.1)
	sn = PObserve.snapshot(st)
	var e3: bool = th_of(sn, ":slash1").is_empty() and th_is(th_of(sn, ":slash2"), { "kind": "corridor", "phase": "warn", "label": "slash2", "x": float(bz.slashes[1].x), "w": 80.0, "prog": float(bz.state_t) / 0.5 })
	until_state(st, "slash_lock", 1.0)
	var e4 := th_is(th_of(PObserve.snapshot(st), ":slash2"), { "phase": "lock" })
	ok("11n 절단선: slash_warn → :slash1 세로 통로 warn(플레이어 x를 따라옴), slash_lock → lock(x 고정), 1번 뒤 :slash2 warn(고정 x, 진행률) → lock", x0 and e1 and e2 and e3 and e4)
	st = boss_ready("doom_executor", 480.0, 300.0, 480.0, 560.0)
	bz = st.boss
	PBoss3.begin(st, bz, "guard")
	steps3(st, 0.3)
	sn = PObserve.snapshot(st)
	var gd: Dictionary = sn.boss.guard
	var v1: bool = boss_th_n(sn) == 0 and not gd.is_empty() and near(float(gd.ang), float(bz.face)) and near(float(gd.half), PGeom.deg(110.0) / 2.0) and near(float(gd.r), 160.0) and near(float(gd.left), 2.4 - float(bz.guard_t), 1e-4)
	until_state(st, "gstrike_aim", 4.0)
	steps3(st, 0.1)
	sn = PObserve.snapshot(st)
	var v2 := th_is(th_of(sn, ":strike"), { "kind": "sector", "phase": "warn", "label": "gstrike", "r": 160.0, "half": PGeom.deg(140.0) / 2.0, "ang": float(bz.aim_angle) }) and (sn.boss.guard as Dictionary).is_empty()
	until_state(st, "gstrike_lock", 2.0)
	var v3 := th_is(th_of(PObserve.snapshot(st), ":strike"), { "phase": "lock", "ang": float(bz.dir) })
	ok("11o 회전 방어 자세: guard 중 위협 0 + boss.guard(정면 110°·r160·남은 초 표시), gstrike_aim → :strike 부채꼴 r160·140° warn(방패 표시 없음), gstrike_lock → lock", v1 and v2 and v3)
	# ----- 6종 공통: 실력 봇 전투 15초 동안 매 단계 숨은 값(난수·대기열·보스 타이머·소환 예산) 변경 → 같은 스냅샷·같은 입력, 스냅샷에 숨은 필드 이름 없음, 보스 위협을 실제로 봄 -----
	for id in PBoss3.IDS:
		var s3 := boss_ready(String(id), 480.0, 200.0, 480.0, 420.0)
		var A := PSkillBot.new("skilled", 7)
		var B := PSkillBot.new("skilled", 7)
		var same_snap := true
		var same_in := true
		var leak := ""
		var labels := {}
		var kinds := {}
		var n := 0
		while s3.status == "running" and n < 120 * 15:
			var sa := A.observer.take(s3, true)
			var saved := hide3(s3)
			var sb := B.observer.take(s3, true)
			unhide3(s3, saved)
			var ja := JSON.stringify(sa)
			if ja != JSON.stringify(sb):
				same_snap = false
			for k in HIDDEN3:
				if ja.find(String(k)) >= 0:
					leak = String(k)
			for th in sa.threats:
				if int(th.enemy_id) == int(sa.boss.id):
					labels[String(th.label)] = true
					kinds[String(th.kind)] = true
			var ia := A.step_snapshot(sa)
			var ib := B.step_snapshot(sb)
			if JSON.stringify(ia) != JSON.stringify(ib):
				same_in = false
			s3.step(ia, STEP)
			n += 1
		var lk := labels.keys()
		lk.sort()
		ok("11p %s: 숨은 값 변경에도 스냅샷·입력 동일(%d단계), 숨은 필드 없음(%s), 본 보스 위협 %s(%s)" % [String(id), n, "누출: " + leak if leak != "" else "없음", str(lk), ",".join(kinds.keys())], same_snap and same_in and leak == "" and labels.size() > 0)

func _rm_rf(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		var full := path.path_join(fn)
		if d.current_is_dir():
			_rm_rf(full)
			DirAccess.remove_absolute(full)
		else:
			DirAccess.remove_absolute(full)
		fn = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
