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
