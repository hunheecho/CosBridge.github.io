extends SceneTree
## 신규 관문 보스 6종 규칙 테스트(headless, 결정적): godot --headless --path prophecy_godot -s tests/boss3_tests.gd
## 계획 문서 §7 공통 규칙·패턴 표·"신규 보스별 필수 판정"을 규칙 코드(scripts/rules/boss3.gd, data/bosses_new.json 시험값)로 검사한다.
## 공통: 생성/입장, 예고 도형(봇 threats = 화면 기하), 단계 70/35%, 감속장 40%, 무적 없음, 소환 상한. 보스별: 각 패턴이 예고된 기하 안에서만 피해를 준다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func build(o: Dictionary = {}) -> Dictionary:
	var g := PGrowth.new_growth(String(o.get("start", "sword")))
	if o.has("commons"):
		g.commons = o.commons
	return PBuild.derive(PBuild.empty_run_like(g))

## 이 파일의 시험은 '패턴 하나의 판정·예고·빈틈'을 본다. 행동 개편(연계·옆뛰기, data/boss_behavior.json)은 개체 스위치 beh_off로 끄고
## 개편 전(073f74f)과 같은 조건에서 확인한다 — 즉 아래 기대값은 이번 작업에서 바뀌지 않았다.
## 개편 자체의 검사는 이 파일 끝의 chain_tests()와 tests/boss_pace_tests.gd에 있다.
func boss_state(id: String, seed_v: int = 5, hp: float = 0.0, o: Dictionary = {}) -> CombatState:
	var opts := { "build": build(o), "seed": seed_v, "arena": "clearing", "boss": true, "boss_id": id, "region_id": "boss", "xp_kill_mult": 0.3 }
	if hp > 0.0:
		opts.boss_hp = hp
	var st := CombatState.new(opts)
	st.boss.beh_off = true
	return st

## 입장 연출을 지나 접근 상태에서 시작. 플레이어 자동 공격은 멀리 두어(attack_timer) 판정에 끼지 않게 한다
func ready_state(id: String, bx: float = 480.0, by: float = 300.0, px: float = 480.0, py: float = 420.0) -> CombatState:
	var st := boss_state(id)
	for i in int(round((float(PCatalog.boss_def(id).intro) + 0.2) / STEP)):
		st.step({}, STEP)
	var bz := st.boss
	bz.x = bx; bz.y = by
	st.player.x = px; st.player.y = py
	bz.state = "approach"; bz.state_t = 0.0; bz.approach_t = 0.0
	return st

func steps(st: CombatState, seconds: float, input: Dictionary = {}) -> void:
	for i in int(round(seconds / STEP)):
		st.step(input, STEP)

func run_until(st: CombatState, pred: Callable, max_sec: float, input: Dictionary = {}) -> bool:
	for i in int(round(max_sec / STEP)):
		if pred.call():
			return true
		st.step(input, STEP)
	return pred.call()

func hits(st: CombatState, src: String) -> int:
	return int(st.metrics.taken_hits.get(src, 0))

func summoned_total(st: CombatState) -> int:
	var n := PBoss.summoned_alive(st)
	for s in st.pending:
		if bool(s.get("summoned", false)):
			n += 1
	return n

func boss_threats(st: CombatState) -> Array:
	var out: Array = []
	for th in PBot.threats(st):
		if th.has("e") and th.e == st.boss:
			out.append(th)
	return out

func _init() -> void:
	common_tests()
	warden_tests()
	matriarch_tests()
	behemoth_tests()
	stalker_tests()
	hunt_king_tests()
	executor_tests()
	executor_variation_tests()
	chain_tests()
	break_candidate_tests()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 공통 ----------
func common_tests() -> void:
	var expect_act := { "gate_warden": 1, "spore_matriarch": 1, "excavation_behemoth": 2, "frost_stalker": 2, "blood_hunt_king": 3, "doom_executor": 3 }
	var hp_class := { 1: 2400.0, 2: 5000.0, 3: 7000.0 }
	var sets := PCatalog.boss_hp_sets()
	var defs := PCatalog.boss_defs()
	ok("카탈로그 합치기: boss_defs 9종(기존 3 + 신규 6), enemies에 몸체, 기존 3종 정의 그대로", defs.size() == 9 and PCatalog.enemies().has("gate_warden") and defs.boss.hp == 2400 and defs.guardian.hp == 3000 and defs.eater.hp == 3600, str(defs.keys()))
	for id in PBoss3.IDS:
		var d := PCatalog.boss_def(id)
		var act: int = int(expect_act[id])
		var key := "stage%d" % act
		ok("%s: 막 %d, 체력 시험값 hi %d / base 있음, 단계 [0.7, 0.35]" % [id, act, int(hp_class[act])], int(d.act) == act and float(d.hp) == float(hp_class[act]) and float(sets.hi[id][key]) == float(hp_class[act]) and sets.base.has(id) and float(d.phases[0]) == 0.7 and float(d.phases[1]) == 0.35)
		var st := boss_state(id)
		var bz := st.boss
		ok("%s 생성: 입장 %.1f초 동안 피해·시간 없음" % [id, float(d.intro)], bz.hp == float(d.hp) and bz.r == float(d.r) and st.intro == float(d.intro) and bz.state == "intro" and not st.damage_player(10.0, "test"))
		steps(st, float(d.intro) + 0.1)
		ok("%s 입장 뒤 접근 + 포효 이벤트" % id, bz.state == "approach" and st.events.has("boss_roar"))
		# 행동 문구(HUD): 이 보스가 쓰는 모든 상태에 문구가 있다
		var missing := []
		for s in PBoss3.COMMITTED:
			if not PCatalog.boss_action_text().has(s):
				missing.append(s)
		ok("%s HUD 문구: 확정·실행 상태 전부 boss_action_text에 있음" % id, missing.is_empty(), str(missing))
		# 단계 70/35: 첫 통과 시 구슬, 행동 사이에서 적용
		st = ready_state(id)
		bz = st.boss
		st.damage_enemy(bz, float(bz.hp_max) * 0.31, { "src": { "tag": "test" } })
		var p2: bool = int(bz.phase_pending) == 2 and st.pickups.size() == 1
		st.damage_enemy(bz, float(bz.hp_max) * 0.36, { "src": { "tag": "test" } })
		ok("%s 단계: 70%%에서 2단계 대기+구슬 1, 35%%에서 3단계 대기+구슬 2" % id, p2 and int(bz.phase_pending) == 3 and st.pickups.size() == 2 and not bz.dead, "pending %d pickups %d" % [int(bz.phase_pending), st.pickups.size()])
		run_until(st, func(): return int(bz.phase) == 3, 4.0)
		ok("%s 단계 전환은 행동 사이(포효 roar)에서만, phase_events 기록" % id, int(bz.phase) == 3 and st.phase_events.size() >= 1)
		# 감속장: 준비 진행 = dt × 0.4
		st = ready_state(id)
		bz = st.boss
		var first_pat: String = String((PCatalog.boss_def(id).weights as Dictionary).keys()[0])
		PBoss3.begin(st, bz, first_pat)
		var s0 := String(bz.state)
		var t0 := float(bz.state_t)
		st.step({ "special": true }, STEP)
		ok("%s 감속장 안 준비 진행(%s) = dt × 0.4" % [id, s0], st.in_field(bz) and absf(float(bz.state_t) - t0 - STEP * 0.4) < 1e-9, "%.5f" % float(bz.state_t))
		# 무적 없음: 모든 상태에서 피해가 들어간다(정면 방패 경감 최소 60%)
		var immune := []
		var states: Array = PBoss3.COMMITTED.duplicate()
		states.append_array(["approach", "recover", "sidestep", "guard", "guard_aim", "burrow", "dash", "ring"])
		for s in states:
			bz.state = s
			bz.state_t = 0.0
			bz.guard_real = 0.0
			var h0: float = bz.hp
			var dealt := st.damage_enemy(bz, 10.0, { "src": { "tag": "test", "direct": true } })
			if dealt < 6.0 - 1e-6 or float(bz.hp) >= h0:
				immune.append(s)
		ok("%s 무적 구간 없음(모든 상태에서 피해 ≥ 60%%)" % id, immune.is_empty(), str(immune))
		# 예고 도형: 패턴마다 봇 threats에 보스 위협이 보인다(소환 제외)
		var no_threat := []
		for pat in (PCatalog.boss_def(id).weights as Dictionary).keys():
			if String(pat) == "summon":
				continue
			var s2 := ready_state(id)
			var b2 := s2.boss
			b2.phase = 2
			PBoss3.begin(s2, b2, String(pat))
			var seen := run_until(s2, func(): return boss_threats(s2).size() > 0, 1.5)
			if not seen:
				no_threat.append(pat)
		ok("%s 예고 도형: 모든 패턴이 봇 threats에 노출" % id, no_threat.is_empty(), str(no_threat))
		# 소환 상한: 반복 소환해도 cap 이하, cap ≤ 기존 보스 상한 4
		if PCatalog.boss_def(id).has("summon"):
			var S: Dictionary = PCatalog.boss_def(id).summon
			var s3 := ready_state(id)
			var b3 := s3.boss
			var over := false
			for k in 4:
				b3.last_summon = -999.0
				b3.phase = 1 + (k % 3)
				PBoss3.summon(s3, b3)
				steps(s3, 1.2)
				if summoned_total(s3) > int(S.cap):
					over = true
			ok("%s 소환 상한 %d(≤4) 유지, 예산 %d" % [id, int(S.cap), int(S.budget)], not over and int(S.cap) <= 4 and summoned_total(s3) <= int(S.cap) and int(b3.summon_budget) >= 0, "alive+pending %d budget %d" % [summoned_total(s3), int(b3.summon_budget)])
	# 피격 보호 공유: 보스에게 맞은 직후엔 소환수의 피해도 들어가지 않는다(같은 hit_prot)
	var sh := ready_state("blood_hunt_king")
	sh.damage_player(10.0, "boss_claw", sh.boss)
	ok("피격 보호 공유: 보스 피해 직후 0.6초 동안 다른 출처 피해 무효", not sh.damage_player(12.0, "wolf:bite") and sh.player.hp == 90.0)

# ---------- 성문 파수장 ----------
func warden_tests() -> void:
	var st := ready_state("gate_warden", 480.0, 300.0, 600.0, 300.0)
	var bz := st.boss
	var G: Dictionary = PCatalog.boss_def("gate_warden").guard
	PBoss3.begin(st, bz, "guard")
	bz.aim_angle = 0.0
	var front := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x + 100.0, "y": bz.y } })
	var side := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x, "y": bz.y + 100.0 } })
	var back := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x - 100.0, "y": bz.y } })
	var zone := st.damage_enemy(bz, 10.0, { "src": { "extra": true, "direct": false, "tag": "common:ember" }, "from": { "x": bz.x + 100.0, "y": bz.y } })
	ok("파수장 방패: 자세 중 정면(±60°) 직접 피해 40%% 경감(10→6), 옆·뒤·바닥 피해 정상, 0이 아님", is_equal_approx(front, 6.0) and is_equal_approx(side, 10.0) and is_equal_approx(back, 10.0) and is_equal_approx(zone, 10.0), "%.1f %.1f %.1f %.1f" % [front, side, back, zone])
	bz.guard_real = float(G.maxReal) + 0.1
	var capped := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x + 100.0, "y": bz.y } })
	bz.guard_real = 0.0
	bz.state = "approach"
	var off := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x + 100.0, "y": bz.y } })
	ok("파수장 방패: 실시간 상한(%.1f초) 뒤·자세 밖(접근)에서는 정면도 정상 피해" % float(G.maxReal), is_equal_approx(capped, 10.0) and is_equal_approx(off, 10.0), "%.1f %.1f" % [capped, off])
	# 밀치기: 확정 방향 부채꼴(r110, 100°) 안만
	st = ready_state("gate_warden", 480.0, 300.0, 480.0, 380.0)
	bz = st.boss
	PBoss3.begin(st, bz, "guard")
	run_until(st, func(): return bz.state == "guard_lock", 2.0)
	var locked_dir: float = bz.dir
	run_until(st, func(): return bz.state == "recover", 2.0)
	var in_hit := hits(st, "boss_shove")
	st = ready_state("gate_warden", 480.0, 300.0, 480.0, 380.0)
	bz = st.boss
	PBoss3.begin(st, bz, "guard")
	run_until(st, func(): return bz.state == "guard_lock", 2.0)
	st.player.x = 480.0; st.player.y = 300.0 - 80.0 # 확정 뒤 뒤로 돌아감
	run_until(st, func(): return bz.state == "recover", 2.0)
	ok("파수장 밀치기: 정면 80은 14 피해, 확정 뒤 뒤로 돌면 무사, 빈틈 1.2초", in_hit == 1 and hits(st, "boss_shove") == 0 and is_equal_approx(float(bz.recover_dur), float(G.recover)) and absf(locked_dir - PI / 2.0) < 1e-6)
	# 석궁 3발: 확정 부채꼴 ±18°, 재추적 없음, 줄 위만 맞음
	st = ready_state("gate_warden", 200.0, 520.0, 600.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "bolts")
	run_until(st, func(): return bz.state == "bolts_lock", 2.0)
	st.player.y = 520.0 + 150.0 # 확정 뒤 이동: 볼트는 따라오지 않는다
	run_until(st, func(): return bz.state == "recover", 2.0)
	var bolts := []
	for pr in st.projectiles:
		if pr.kind == "boss_bolt":
			bolts.append(pr)
	var spread_ok: bool = bolts.size() == 3 and absf(PGeom.ang_diff(float(bolts[0].angle), float(bolts[2].angle)) - PGeom.deg(36.0)) < 1e-6 and absf(float(bolts[1].angle)) < 1e-6
	steps(st, 1.5)
	ok("파수장 석궁: 볼트 3발(0°, ±18°, 피해 10)이 확정 방향으로, 줄 밖으로 비킨 플레이어는 무사", spread_ok and float(bolts[0].dmg) == 10.0 and hits(st, "boss_bolt") == 0, "bolts %d" % bolts.size())
	st = ready_state("gate_warden", 200.0, 520.0, 600.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "bolts")
	run_until(st, func(): return hits(st, "boss_bolt") > 0, 4.0)
	ok("파수장 석궁: 줄 위에 서 있으면 볼트에 맞는다(피해 출처 boss_bolt)", hits(st, "boss_bolt") == 1 and st.player.hp == 90.0, "hp %.0f" % st.player.hp)
	# 방패 돌파: 방향 고정·예고 길이·1단계 빈틈 2.0 / 2단계 넓은 휩쓸기 뒤 빈틈 2.4
	st = ready_state("gate_warden", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "breach")
	run_until(st, func(): return bz.state == "breach_lock", 2.0)
	var d0: float = bz.dir
	var len0: float = float(bz.dash_len)
	st.player.y = 300.0
	run_until(st, func(): return bz.state == "recover", 3.0)
	ok("파수장 돌파(1단계): 확정 뒤 방향 불변, 예고 길이 ≤ 440, 빈틈 2.0", absf(PGeom.ang_diff(d0, float(bz.dir))) < 1e-9 and len0 <= 440.0 + 1e-6 and is_equal_approx(float(bz.recover_dur), 2.0), "len %.0f" % len0)
	st = ready_state("gate_warden", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "breach")
	var sweep_seen := run_until(st, func(): return bz.state == "bsweep_aim", 3.0)
	run_until(st, func(): return bz.state == "recover", 3.0)
	ok("파수장 돌파(2단계~): 돌파 끝에 넓은 휩쓸기(200°) 한 번, 그 뒤 방패 내리고 빈틈 2.4", sweep_seen and is_equal_approx(float(bz.recover_dur), 2.4) and hits(st, "boss_bsweep") + hits(st, "boss_breach") >= 1, str(st.metrics.taken_hits))
	ok("파수장 돌파 뒤 빈틈에는 방패 경감 없음(측후방 공격 기회)", not PBoss3.guard_active(bz) and is_equal_approx(st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x + cos(float(bz.dir)) * 100.0, "y": bz.y + sin(float(bz.dir)) * 100.0 } }), 15.0))

# ---------- 포자 어미 ----------
func matriarch_tests() -> void:
	var S: Dictionary = PCatalog.boss_def("spore_matriarch").shot
	var R: Dictionary = PCatalog.boss_def("spore_matriarch").ring
	var st := ready_state("spore_matriarch", 480.0, 300.0, 480.0, 480.0)
	var bz := st.boss
	PBoss3.begin(st, bz, "shot")
	run_until(st, func(): return bz.state == "shot_wait", 2.0)
	var mk: Dictionary = bz.marks[0]
	var at_player: bool = PGeom.dist(float(mk.x), float(mk.y), st.player.x, st.player.y) < 1.0
	run_until(st, func(): return (bz.marks as Array).is_empty(), 2.0)
	var clouds := 0
	for z in st.zones:
		if z.type == "spore" and String(z.get("owner", "")) == "boss":
			clouds += 1
	ok("포자 탄: 조준 뒤 표시 자리(플레이어 위치)에 1.0초 뒤 착탄 14, 잔류 구름 1", at_player and is_equal_approx(float(mk.land_at) - float(mk.get("placed_t", float(mk.land_at) - float(S.delay))), float(S.delay)) and hits(st, "boss_spore_shot") == 1 and clouds == 1 and bz.state == "recover", str(st.metrics.taken_hits))
	st = ready_state("spore_matriarch", 480.0, 300.0, 480.0, 480.0)
	bz = st.boss
	PBoss3.begin(st, bz, "shot")
	run_until(st, func(): return bz.state == "shot_wait", 2.0)
	st.player.x = 480.0 + 120.0 # 표시된 원 밖으로
	run_until(st, func(): return (bz.marks as Array).is_empty(), 2.0)
	ok("포자 탄: 표시 원(r62) 밖이면 무사", hits(st, "boss_spore_shot") == 0)
	# 후반 두 자리 시간차: 두 번째는 0.45초 뒤 플레이어의 새 위치
	st = ready_state("spore_matriarch", 480.0, 300.0, 400.0, 480.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "shot")
	run_until(st, func(): return bz.state == "shot_wait", 2.0)
	var m1x: float = float(bz.marks[0].x)
	run_until(st, func(): return (bz.marks as Array).size() >= 2, 1.0, { "mx": 1.0 })
	var m2: Dictionary = bz.marks[1]
	ok("포자 탄(2단계~): 두 자리 시간차 0.45초, 둘째는 그 시점 플레이어 위치(첫째보다 오른쪽)", (bz.marks as Array).size() == 2 and float(m2.x) > m1x + 40.0 and int(m2.order) == 2 and is_equal_approx(float(m2.land_at) - float(bz.marks[0].land_at), float(S.gap)), "m1 %.0f m2 %.0f" % [m1x, float(m2.x)])
	# 구름 상한 3·수명: 끝난 구름은 사라져 피해 없음
	st = ready_state("spore_matriarch", 480.0, 300.0, 480.0, 480.0)
	bz = st.boss
	for i in 3:
		var z := st.add_zone("spore", 100.0 + float(i) * 50.0, 100.0, 40.0, 2.5, 5.0)
		z.owner = "boss"
	PBoss3.begin(st, bz, "shot")
	run_until(st, func(): return (bz.marks as Array).is_empty(), 3.0)
	var clouds2 := 0
	for z in st.zones:
		if z.type == "spore":
			clouds2 += 1
	steps(st, 4.0)
	var spore_left := 0
	var ztypes := []
	for z in st.zones:
		ztypes.append(String(z.type))
		if z.type == "spore":
			spore_left += 1
	ok("잔류 구름: 동시 상한 3(이미 3개면 새 구름 없음), 수명 뒤 제거되어 피해 없음", clouds2 == 3 and spore_left == 0, "clouds %d zones %s" % [clouds2, str(ztypes)])
	# 고리: 빈 구간은 실제 판정도 비어 있다
	st = ready_state("spore_matriarch", 480.0, 300.0, 680.0, 300.0)
	bz = st.boss
	PBoss3.begin(st, bz, "ring")
	bz.ring_gap = 0.0
	var gap_half: float = float(bz.ring_half)
	run_until(st, func(): return bz.state == "recover", 4.0)
	var in_gap_hits := hits(st, "boss_ring")
	st = ready_state("spore_matriarch", 480.0, 300.0, 480.0, 500.0)
	bz = st.boss
	PBoss3.begin(st, bz, "ring")
	bz.ring_gap = 0.0
	run_until(st, func(): return bz.state == "recover", 4.0)
	ok("포자 고리: 빈 구간(%.0f°) 안(각 0°, 거리 200)은 무사, 밖(각 90°)은 16 피해 1회, 빈틈 1.6" % (gap_half * 2.0 * 180.0 / PI), in_gap_hits == 0 and hits(st, "boss_ring") == 1 and is_equal_approx(float(bz.recover_dur), float(R.recover)), "gap %d out %d" % [in_gap_hits, hits(st, "boss_ring")])
	var e2 := { "x": 0.0, "y": 0.0, "ring_r": 200.0, "ring_gap": 0.0, "ring_half": PGeom.deg(35.0) }
	ok("고리 판정 함수: 띠 안+빈 구간 밖 true, 빈 구간 안 false, 띠 밖 false, 빈 구간 가장자리(34°) false·(36°) true", PBoss3.ring_hits(e2, 44.0, 0.0, 200.0, 14.0) and not PBoss3.ring_hits(e2, 44.0, 200.0, 0.0, 14.0) and not PBoss3.ring_hits(e2, 44.0, 0.0, 100.0, 14.0) and not PBoss3.ring_hits(e2, 44.0, cos(PGeom.deg(34.0)) * 200.0, sin(PGeom.deg(34.0)) * 200.0, 14.0) and PBoss3.ring_hits(e2, 44.0, cos(PGeom.deg(36.0)) * 200.0, sin(PGeom.deg(36.0)) * 200.0, 14.0))
	st = ready_state("spore_matriarch", 480.0, 300.0, 480.0, 500.0)
	bz = st.boss
	PBoss3.begin(st, bz, "ring")
	bz.phase = 3
	PBoss3.begin(st, bz, "ring")
	ok("포자 고리(3단계): 빈 구간 55°(더 좁지만 유지)", is_equal_approx(float(bz.ring_half) * 2.0, PGeom.deg(55.0)))
	# 분사: 느린 접근 뒤 정면 부채꼴, 분사 뒤 이동 정지
	st = ready_state("spore_matriarch", 480.0, 300.0, 480.0, 380.0)
	bz = st.boss
	PBoss3.begin(st, bz, "spray")
	run_until(st, func(): return bz.state == "recover", 2.0)
	var rx: float = bz.x
	var ry: float = bz.y
	st.player.x = 480.0; st.player.y = 560.0
	steps(st, 1.0)
	ok("분사: 정면 80은 12 피해, 분사 뒤 빈틈 1.4초 동안 이동 없음", hits(st, "boss_spray") == 1 and bz.state == "recover" and PGeom.dist(rx, ry, bz.x, bz.y) < 1e-6)
	st = ready_state("spore_matriarch", 480.0, 300.0, 480.0, 380.0)
	bz = st.boss
	PBoss3.begin(st, bz, "spray")
	run_until(st, func(): return bz.state == "spray_lock", 2.0)
	st.player.x = 480.0; st.player.y = 300.0 - 90.0
	run_until(st, func(): return bz.state == "recover", 2.0)
	ok("분사: 확정 뒤 뒤로 돌면 무사", hits(st, "boss_spray") == 0)

# ---------- 굴착 거수 ----------
func behemoth_tests() -> void:
	var RK: Dictionary = PCatalog.boss_def("excavation_behemoth").rockfall
	var B: Dictionary = PCatalog.boss_def("excavation_behemoth").burrow
	var st := ready_state("excavation_behemoth", 480.0, 120.0, 480.0, 400.0)
	var bz := st.boss
	ok("굴착 거수: 호위 동시 위험 행동 한도 1(overlap_limit)", st.overlap_limit == 1)
	PBoss3.begin(st, bz, "rockfall")
	run_until(st, func(): return bz.state == "rock_wait", 2.0)
	var rocks: Array = bz.rocks
	var seq_ok: bool = rocks.size() == 3
	for i in rocks.size():
		if int(rocks[i].order) != i + 1 or (i > 0 and not is_equal_approx(float(rocks[i].land_at) - float(rocks[i - 1].land_at), float(RK.gap))):
			seq_ok = false
	var exits := PBoss3.exits_open(st, bz, rocks)
	var t_cast: float = st.t
	run_until(st, func(): return bool(rocks[0].done), 2.0)
	var one_only: bool = bool(rocks[0].done) and not bool(rocks[1].done) and not bool(rocks[2].done)
	var t1: float = st.t - t_cast
	run_until(st, func(): return bool(rocks[1].done), 2.0)
	var two: bool = not bool(rocks[2].done)
	run_until(st, func(): return bz.state == "recover", 2.0)
	var rubble := 0
	for z in st.zones:
		if z.type == "rubble":
			rubble += 1
	ok("낙석: 세 구역 1→2→3 순서 번호, 낙하 시각 0.5초 간격, 동시가 아닌 순차(1 떨어질 때 2·3 대기)", seq_ok and one_only and two and absf(t1 - float(RK.warn)) < STEP * 2.0, "n %d t1 %.2f" % [rocks.size(), t1])
	ok("낙석: 첫 구역(플레이어 자리)에 서 있으면 18 피해, 잔해 3개 남고 잔해 위에서 0.5초 간격 피해(boss_rubble), 빈틈 1.5", hits(st, "boss_rockfall") == 1 and rubble == 3 and hits(st, "boss_rubble") >= 1 and is_equal_approx(float(bz.recover_dur), float(RK.recover)), str(st.metrics.taken_hits))
	ok("낙석: 예고 직후 플레이어 주위 16방향 중 열린 출구 ≥ %d" % int(RK.minExits), exits >= int(RK.minExits), "exits %d" % exits)
	# 옆으로 빠지면 무사(예고 0.9초, 반지름 72)
	st = ready_state("excavation_behemoth", 480.0, 120.0, 480.0, 400.0)
	bz = st.boss
	PBoss3.begin(st, bz, "rockfall")
	run_until(st, func(): return bz.state == "rock_wait", 2.0)
	run_until(st, func(): return bz.state == "recover", 4.0, { "mx": 1.0 })
	ok("낙석: 예고를 보고 옆으로 걸어 나가면 세 구역 모두 무사", hits(st, "boss_rockfall") == 0 and hits(st, "boss_rubble") == 0, str(st.metrics.taken_hits))
	# 잔해가 남은 상태에서 다시 낙석: 출구 검사 통과(모든 방향을 막지 않음)
	st = ready_state("excavation_behemoth", 480.0, 120.0, 480.0, 400.0)
	bz = st.boss
	for i in 3:
		var z := st.add_zone("rubble", 480.0 + float(i - 1) * 125.0, 400.0, 72.0, 4.0, 5.0)
		z.owner = "boss"
	PBoss3.begin(st, bz, "rockfall")
	run_until(st, func(): return bz.state == "rock_wait", 2.0)
	var exits2 := PBoss3.exits_open(st, bz, bz.rocks)
	ok("낙석: 이전 잔해 3개가 있어도 새 예고 + 잔해가 모든 출구를 막지 않는다(열린 방향 ≥ %d)" % int(RK.minExits), exits2 >= int(RK.minExits), "exits %d rocks %d" % [exits2, (bz.rocks as Array).size()])
	# 굴착 돌파: 몸 보임·피해 가능, 방향 고정, 2단계 두 방향 순서 예고·재조준 없음
	st = ready_state("excavation_behemoth", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "burrow")
	run_until(st, func(): return bz.state == "burrow_lock", 2.0)
	var plan: Array = (bz.burrow_plan as Array).duplicate(true)
	var beams := 0
	for th in boss_threats(st):
		if String(th.kind) == "beam":
			beams += 1
	st.player.x = 620.0; st.player.y = 300.0 # 확정 뒤 이동: 둘째 방향도 이미 고정
	run_until(st, func(): return bz.state == "burrow", 1.0)
	var h0: float = bz.hp
	st.damage_enemy(bz, 10.0, { "src": { "tag": "test" } })
	var hittable: bool = float(bz.hp) < h0 and not bool(bz.hidden)
	run_until(st, func(): return int(bz.dash_seq) == 2 and bz.state == "burrow", 3.0)
	var second_same: bool = absf(PGeom.ang_diff(float(bz.dir), float(plan[1].ang))) < 1e-9
	run_until(st, func(): return bz.state == "recover", 3.0)
	ok("굴착(2단계~): 확정 시 두 방향을 1→2로 미리 예고(빔 2개), 둘째 방향은 재조준 없이 그대로, 두 번 뒤 빈틈 3.0", plan.size() == 2 and beams == 2 and second_same and is_equal_approx(float(bz.recover_dur), float(B.doubleRecover)), "plan %d beams %d" % [plan.size(), beams])
	ok("굴착 중 몸은 보이고 피해를 받는다(지하 무적 없음)", hittable)
	st = ready_state("excavation_behemoth", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "burrow")
	run_until(st, func(): return bz.state == "recover", 4.0)
	ok("굴착(1단계): 플레이어를 지나며 20 피해, 잔해에 멈추는 빈틈 2.4", hits(st, "boss_burrow") == 1 and is_equal_approx(float(bz.recover_dur), float(B.recover)))
	# 폭탄 운반체 소환: 동시 2, 폭발/사망 1회
	st = ready_state("excavation_behemoth", 480.0, 120.0, 480.0, 400.0)
	bz = st.boss
	PBoss3.begin(st, bz, "summon")
	run_until(st, func(): return PBoss.summoned_alive(st) >= 2, 4.0)
	var bombers := []
	for e in st.enemies:
		if e.type == "bomber" and not e.dead:
			bombers.append(e)
	ok("폭탄 운반체 소환 2(동시 상한 2, 총 6)", bombers.size() == 2 and summoned_total(st) == 2 and int(bz.summon_budget) == 4)
	var bm: Dictionary = bombers[0]
	for b in bombers: # 둘째는 멀리 두어 플레이어 자동 공격에 죽지 않게(집계는 종류별이라 분리)
		if b != bm:
			b.x = 60.0; b.y = 60.0
	st.player.x = bm.x; st.player.y = bm.y + 40.0
	bm.state = "fuse"; bm.state_t = 0.0
	bz.state = "recover"; bz.state_t = 0.0; bz.recover_dur = 99.0 # 보스 공격이 피격 보호를 먼저 쓰지 않게
	st.player.attack_timer = 1.0e9 # 자동기술 끔(테스트 훅) — 폭발 전에 죽이지 않게
	steps(st, 1.5)
	var m: Dictionary = st.metrics.enemies["bomber:summoned"]
	var once: bool = bool(bm.dead) and bool(bm.get("exploded", false)) and int(m.exploded) == 1 and hits(st, "blast") == 1
	var dead_n := 0
	for e in st.enemies:
		if e.type == "bomber" and e.dead:
			dead_n += 1
	steps(st, 1.5)
	ok("폭탄 운반체 폭발: 표시 원 안 22 피해, 폭발/사망 처리 1회(exploded 1, 죽은 수 = exploded + killed, 재집계 없음)", once and int(m.exploded) == 1 and dead_n == int(m.exploded) + int(m.killed), "exploded %d killed %d dead %d" % [int(m.exploded), int(m.killed), dead_n])

# ---------- 서리 추적자 ----------
func stalker_tests() -> void:
	var I: Dictionary = PCatalog.boss_def("frost_stalker").icepath
	var D: Dictionary = PCatalog.boss_def("frost_stalker").dash
	var st := ready_state("frost_stalker", 300.0, 300.0, 700.0, 300.0)
	var bz := st.boss
	PBoss3.begin(st, bz, "bolt")
	run_until(st, func(): return hits(st, "boss_icebolt") > 0, 3.0)
	ok("얼음 발사: 확정 방향의 얼음 탄(피해 14)에 맞는다", hits(st, "boss_icebolt") == 1 and st.player.hp == 86.0)
	st = ready_state("frost_stalker", 300.0, 300.0, 700.0, 300.0)
	bz = st.boss
	PBoss3.begin(st, bz, "icepath")
	run_until(st, func(): return bz.state == "recover", 2.0)
	var ice := 0
	for z in st.zones:
		if z.type == "ice" and float(z.get("slow", 1.0)) == float(I.slow):
			ice += 1
	var angs: Array = bz.lanes
	ok("얼음길: 세 줄(0°, ±40°) 확정, 줄 위 플레이어 12 피해, 빙판(감속 0.6) 생성, 빈틈 1.5", angs.size() == 3 and absf(PGeom.ang_diff(float(angs[0]), float(angs[2])) - PGeom.deg(80.0)) < 1e-6 and hits(st, "boss_icepath") == 1 and ice > 0 and is_equal_approx(float(bz.recover_dur), float(I.recover)), "ice %d" % ice)
	st = ready_state("frost_stalker", 300.0, 300.0, 300.0 + cos(PGeom.deg(20.0)) * 300.0, 300.0 + sin(PGeom.deg(20.0)) * 300.0)
	bz = st.boss
	PBoss3.begin(st, bz, "icepath")
	bz.aim_angle = 0.0
	run_until(st, func(): return bz.state == "path_lock", 2.0)
	bz.dir = 0.0
	bz.lanes = PBoss3.lane_angles(bz, I)
	run_until(st, func(): return bz.state == "recover", 2.0)
	ok("얼음길: 줄 사이(20°, 거리 300)의 통로는 비어 있어 무사", hits(st, "boss_icepath") == 0)
	for k in 3:
		PBoss3.lay_ice(st, bz, 0.5, I)
	steps(st, STEP)
	var ice2 := 0
	for z in st.zones:
		if z.type == "ice":
			ice2 += 1
	ok("빙판 동시 상한 %d(넘으면 오래된 것부터 제거)" % int(I.iceCap), ice2 <= int(I.iceCap), "ice %d" % ice2)
	# 빙판은 이동 속도만: 방향 그대로, 미끄러짐 없음, 겹쳐도 곱하지 않음, 회피 거리 그대로
	st = ready_state("frost_stalker", 100.0, 100.0, 480.0, 500.0)
	bz = st.boss
	bz.state = "recover"; bz.recover_dur = 99.0
	var p := st.player
	var x0: float = p.x
	st.step({ "mx": 1.0 }, STEP)
	var dx_plain: float = p.x - x0
	var z1 := st.add_zone("ice", p.x, p.y, 60.0, 5.0, 0.0)
	z1.slow = 0.6
	x0 = p.x
	var y0: float = p.y
	st.step({ "mx": 1.0 }, STEP)
	var dx_ice: float = p.x - x0
	var dy_ice: float = p.y - y0
	var z2 := st.add_zone("ice", p.x, p.y, 60.0, 5.0, 0.0)
	z2.slow = 0.6
	x0 = p.x
	st.step({ "mx": 1.0 }, STEP)
	var dx_ice2: float = p.x - x0
	ok("빙판: 걷기 속도 60%%(%.3f→%.3f), y 변화 0(입력 방향 그대로), 두 빙판 겹쳐도 그대로 60%%" % [dx_plain, dx_ice], is_equal_approx(dx_ice, dx_plain * 0.6) and absf(dy_ice) < 1e-9 and is_equal_approx(dx_ice2, dx_ice))
	var xd: float = p.x
	steps(st, 0.3, { "mx": 1.0, "dodge_press": true, "dodge_held": true })
	ok("빙판 위 회피: 거리 150 그대로(회피는 감속 대상 아님)", p.x - xd >= 150.0 - 1e-6 and p.x - xd <= 150.0 + 220.0 * 0.05, "%.1f" % (p.x - xd))
	# 낮은 이동속도(빙판 위)에서도 예고를 보고 탈출: 줄 중앙, 빙판 위, 옆으로 걷기
	st = ready_state("frost_stalker", 300.0, 300.0, 520.0, 300.0)
	bz = st.boss
	var z3 := st.add_zone("ice", 520.0, 300.0, 60.0, 9.0, 0.0)
	z3.slow = 0.6
	PBoss3.begin(st, bz, "icepath")
	run_until(st, func(): return bz.state == "recover", 2.0, { "my": 1.0 })
	ok("빙판 위(60%%)에서도 예고 %.1f초 안에 옆으로 걸어 줄(폭 70)을 벗어난다" % (float(I.aim) + float(I.lock)), hits(st, "boss_icepath") == 0 and st.player.y - 300.0 > 49.0, "dy %.0f" % (st.player.y - 300.0))
	# 아군 냉기 면역 없음
	st = boss_state("frost_stalker", 5, 0.0, { "commons": { "frost": 1 } })
	steps(st, 1.8)
	bz = st.boss
	st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true } })
	ok("서리 추적자는 아군 냉기에 면역 아님: 냉기 걸리고 이동 60%", float(bz.chill) > 0.0 and is_equal_approx(st.enemy_speed_mult(bz), 0.6))
	# 옆 이동 뒤 예고 돌진: 옆 이동 중 피해 가능, 확정 뒤 방향 불변, 빈틈 2.2
	st = ready_state("frost_stalker", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "dash")
	var sx: float = bz.x
	var sy: float = bz.y
	var h0: float = bz.hp
	st.damage_enemy(bz, 10.0, { "src": { "tag": "test" } })
	var side_hit: bool = float(bz.hp) < h0 and bz.state == "sidestep"
	run_until(st, func(): return bz.state == "dash_aim", 1.0)
	var moved: float = PGeom.dist(sx, sy, bz.x, bz.y)
	run_until(st, func(): return bz.state == "dash_lock", 2.0)
	var d0: float = bz.dir
	st.player.y = 300.0
	run_until(st, func(): return bz.state == "recover", 3.0)
	ok("옆 이동(≈140) 중에도 피해를 받고, 돌진은 확정 뒤 방향 불변, 빈틈 2.2", side_hit and moved > 100.0 and absf(PGeom.ang_diff(d0, float(bz.dir))) < 1e-9 and is_equal_approx(float(bz.recover_dur), float(D.recover)), "moved %.0f" % moved)
	st = ready_state("frost_stalker", 200.0, 520.0, 520.0, 520.0)
	bz = st.boss
	bz.phase = 2
	bz.actions = 3
	bz.history = ["bolt", "icepath"]
	ok("2단계~ 얼음길 다음은 돌진 연계(선택 규칙)", PBoss3.choose(st, bz) == "dash")

# ---------- 핏빛 사냥왕 ----------
func hunt_king_tests() -> void:
	var D: Dictionary = PCatalog.boss_def("blood_hunt_king").dash
	var C: Dictionary = PCatalog.boss_def("blood_hunt_king").claw
	var st := ready_state("blood_hunt_king", 480.0, 300.0, 480.0, 420.0)
	var bz := st.boss
	PBoss3.begin(st, bz, "claw")
	run_until(st, func(): return bz.state == "recover", 2.0)
	var front := hits(st, "boss_claw")
	st = ready_state("blood_hunt_king", 480.0, 300.0, 480.0, 420.0)
	bz = st.boss
	PBoss3.begin(st, bz, "claw")
	run_until(st, func(): return bz.state == "claw_lock", 2.0)
	st.player.x = 480.0; st.player.y = 300.0 - 120.0
	run_until(st, func(): return bz.state == "recover", 2.0)
	ok("발톱 휩쓸기: 정면(r170·170°) 20 피해, 확정 뒤 뒤로 돌면 무사, 빈틈 1.5", front == 1 and hits(st, "boss_claw") == 0 and is_equal_approx(float(bz.recover_dur), float(C.recover)))
	# 두 번의 추적 돌진: 첫 예고 선은 첫 돌진만, 재조준 표식 뒤 새 방향 고정
	st = ready_state("blood_hunt_king", 200.0, 520.0, 560.0, 520.0)
	bz = st.boss
	PBoss3.begin(st, bz, "dash")
	run_until(st, func(): return bz.state == "dash_lock", 2.0)
	var beams1 := 0
	for th in boss_threats(st):
		if String(th.kind) == "beam":
			beams1 += 1
	var d1: float = bz.dir
	run_until(st, func(): return bz.state == "dash_reaim", 3.0)
	var reaim_x: float = bz.x
	var reaim_y: float = bz.y
	var a_before: float = bz.aim_angle
	st.player.x = 620.0; st.player.y = 300.0
	st.step({}, STEP)
	var tracks: bool = absf(PGeom.ang_diff(a_before, float(bz.aim_angle))) > 0.1
	var reaim_th := boss_threats(st)
	var has_marker: bool = reaim_th.size() == 1 and bool(reaim_th[0].get("reaim", false)) and int(reaim_th[0].get("order", 0)) == 2
	run_until(st, func(): return bz.state == "dash_relock", 2.0)
	var d2: float = bz.dir
	st.player.x = 200.0; st.player.y = 100.0 # 고정 뒤 이동: 둘째 방향 불변
	run_until(st, func(): return bz.state == "dash" and int(bz.dash_seq) == 2, 2.0)
	steps(st, 0.2)
	var d2_kept: bool = absf(PGeom.ang_diff(d2, float(bz.dir))) < 1e-9
	run_until(st, func(): return bz.state == "recover", 3.0)
	ok("추적 돌진: 첫 확정 땐 예고 선 1개(둘째 없음), 첫 돌진 뒤 재조준(추적·표식 order 2)", beams1 == 1 and tracks and has_marker, "beams %d tracks %s marker %s" % [beams1, str(tracks), str(has_marker)])
	ok("추적 돌진: 둘째 방향은 재조준 고정 시점에 확정되어 첫 방향과 다르고, 고정 뒤 불변, 두 번 뒤 긴 빈틈 2.6", absf(PGeom.ang_diff(d1, d2)) > 0.3 and d2_kept and is_equal_approx(float(bz.recover_dur), float(D.recover)) and PGeom.dist(reaim_x, reaim_y, 200.0, 520.0) > 300.0, "d1 %.2f d2 %.2f" % [d1, d2])
	# 호위 늑대: 2단계~ 한쪽 측면(±50°)에 몰아 부름
	st = ready_state("blood_hunt_king", 480.0, 200.0, 480.0, 420.0)
	bz = st.boss
	bz.phase = 2
	PBoss3.begin(st, bz, "summon")
	run_until(st, func(): return summoned_total(st) >= 2, 3.0)
	var angs := []
	for s in st.pending:
		if bool(s.get("summoned", false)):
			angs.append(atan2(float(s.y) - st.player.y, float(s.x) - st.player.x))
	var one_side: bool = angs.size() == 2 and absf(PGeom.ang_diff(float(angs[0]), float(angs[1]))) <= PGeom.deg(100.0) + 0.01
	var flank: bool = one_side
	for a in angs:
		var rel: float = absf(PGeom.ang_diff(atan2(bz.y - st.player.y, bz.x - st.player.x), float(a)))
		if rel < PGeom.deg(35.0) or rel > PGeom.deg(145.0):
			flank = false # 보스 방향·정반대가 아닌 측면
	ok("호위 호출(2단계~): 늑대 2마리가 한쪽 측면 100° 안에 몰려 보스 반대쪽이 열린다(동시 3·총 6)", one_side and flank and int(PCatalog.boss_def("blood_hunt_king").summon.cap) == 3, str(angs))
	# 동시 위험 행동 공유: 보스 확정 중 늑대 돌진 금지, 늑대 돌진 준비 중 보스는 대기
	run_until(st, func(): return PBoss.summoned_alive(st) >= 2, 3.0)
	steps(st, 1.0)
	var wolf := {}
	for e in st.enemies:
		if e.type == "wolf" and not e.dead:
			wolf = e
	bz.state = "dash_lock"; bz.state_t = 0.0
	var wolf_blocked: bool = not st.wolf_may_attack(wolf, STEP)
	bz.state = "approach"; bz.state_t = 0.0; bz.approach_t = 1.0; bz.wait_t = 0.0
	wolf.state = "crouch"; wolf.state_t = 0.0
	st.step({}, STEP)
	ok("동시 위험 행동 공유: 보스 확정 중 늑대 돌진 불가, 늑대 돌진 준비 중 보스는 큰 공격을 미룸(wait_t)", wolf_blocked and bz.state == "approach" and float(bz.wait_t) > 0.0, "state %s wait %.3f" % [bz.state, float(bz.wait_t)])

# ---------- 종말의 집행관 ----------
func executor_tests() -> void:
	var SL: Dictionary = PCatalog.boss_def("doom_executor").slash
	var G: Dictionary = PCatalog.boss_def("doom_executor").guard
	var st := ready_state("doom_executor", 480.0, 120.0, 480.0, 400.0)
	var bz := st.boss
	ok("집행관: 호위 동시 위험 행동 한도 1(overlap_limit)", st.overlap_limit == 1)
	PBoss3.begin(st, bz, "slash")
	steps(st, 0.4, { "mx": 1.0 })
	var tracking: bool = absf(float(bz.slashes[0].x) - st.player.x) < 1e-6 and st.player.x > 480.0
	run_until(st, func(): return bz.state == "slash_lock", 2.0)
	var x1: float = float(bz.slashes[0].x)
	steps(st, float(SL.lock) - STEP, { "mx": 1.0 }) # 고정 뒤 오른쪽으로 66 → 선(폭 80) 밖
	var fixed: bool = is_equal_approx(float(bz.slashes[0].x), x1)
	run_until(st, func(): return bz.state == "slash_gap", 1.0)
	var miss1: bool = hits(st, "boss_slash") == 0
	var s2: Dictionary = bz.slashes[1]
	var x2: float = float(s2.x)
	var second_at_player: bool = is_equal_approx(x2, st.player.x) and int(s2.order) == 2 and bool(s2.fixed)
	run_until(st, func(): return bz.state == "recover", 2.0)
	ok("절단선 1: 예고 중 내 x를 따라오다 고정, 고정 뒤 옆으로 걸으면 무사(폭 80)", tracking and fixed and miss1, "x1 %.0f px %.0f" % [x1, st.player.x])
	ok("절단선 2: 1번이 떨어지는 순간 내 x에 고정(order 2), 0.8초 뒤 22 피해(서 있음), 빈틈 1.6", second_at_player and hits(st, "boss_slash") == 1 and is_equal_approx(float(bz.recover_dur), float(SL.recover)), str(st.metrics.taken_hits))
	# 회전 방어 자세: 느린 회전, 정면만 경감, 시간 상한, 큰 베기 뒤 해제
	st = ready_state("doom_executor", 480.0, 300.0, 480.0, 560.0)
	bz = st.boss
	PBoss3.begin(st, bz, "guard")
	bz.face = 0.0
	st.step({}, STEP)
	var turn: float = absf(float(bz.face))
	var front := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x + cos(float(bz.face)) * 100.0, "y": bz.y + sin(float(bz.face)) * 100.0 } })
	var back := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x - cos(float(bz.face)) * 100.0, "y": bz.y - sin(float(bz.face)) * 100.0 } })
	var h0: float = bz.hp
	st.add_zone("fire", bz.x, bz.y, 80.0, 2.0, 10.0)
	steps(st, 0.5)
	var zone_hurts: bool = float(bz.hp) < h0 - 5.0
	ok("방어 자세: 회전은 초당 %.1frad(한 단계 %.4f ≤ %.4f), 정면 직접 피해만 40%% 경감(6), 뒤는 10, 불길(바닥)은 그대로 들어감" % [float(G.turnRate), turn, float(G.turnRate) * STEP], turn <= float(G.turnRate) * STEP + 1e-9 and turn > 0.0 and is_equal_approx(front, 6.0) and is_equal_approx(back, 10.0) and zone_hurts)
	var t_guard0: float = st.t
	run_until(st, func(): return bz.state == "gstrike_aim", 4.0)
	var guard_len: float = st.t - t_guard0 + 0.5
	run_until(st, func(): return bz.state == "recover", 2.0)
	var after := st.damage_enemy(bz, 10.0, { "src": { "weapon_id": "sword", "direct": true }, "from": { "x": bz.x + cos(float(bz.dir)) * 100.0, "y": bz.y + sin(float(bz.dir)) * 100.0 } })
	ok("방어 자세: 시간 상한 %.1f초 안에 큰 베기로 넘어가고, 베기 뒤 자세 해제(빈틈 2.0, 정면 경감 없음 ×1.5=15)" % float(G.dur), guard_len <= float(G.dur) + 0.1 and is_equal_approx(float(bz.recover_dur), float(G.recover)) and is_equal_approx(after, 15.0), "guard %.2f after %.1f" % [guard_len, after])
	st = ready_state("doom_executor", 480.0, 300.0, 480.0, 400.0)
	bz = st.boss
	PBoss3.begin(st, bz, "guard")
	run_until(st, func(): return bz.state == "recover", 5.0)
	ok("큰 베기: 정면 100은 24 피해(boss_gstrike)", hits(st, "boss_gstrike") == 1)
	# 호위 방패병: 두 방향에서, 동시 2
	st = ready_state("doom_executor", 480.0, 120.0, 480.0, 420.0)
	bz = st.boss
	PBoss3.begin(st, bz, "summon")
	run_until(st, func(): return summoned_total(st) >= 2, 3.0)
	var angs := []
	var types_ok := true
	for s in st.pending:
		if bool(s.get("summoned", false)):
			angs.append(atan2(float(s.y) - st.player.y, float(s.x) - st.player.x))
			if String(s.type) != "shieldbearer":
				types_ok = false
	ok("호위 방패병 2명이 서로 다른 두 방향(≥120° 차이)에서 온다, 동시 상한 2·총 4", angs.size() == 2 and types_ok and absf(PGeom.ang_diff(float(angs[0]), float(angs[1]))) >= PGeom.deg(120.0) and int(PCatalog.boss_def("doom_executor").summon.cap) == 2, str(angs))
	# 무적·순간이동 없음: 봇 전투 15초 동안 한 단계 이동 ≤ 15px
	st = boss_state("doom_executor", 11, 3000.0)
	bz = st.boss
	var bot := PBot.new("balanced")
	var max_jump := 0.0
	var lx: float = bz.x
	var ly: float = bz.y
	for i in 120 * 15:
		st.step(bot.step_input(st), STEP)
		max_jump = maxf(max_jump, PGeom.dist(lx, ly, bz.x, bz.y))
		lx = bz.x; ly = bz.y
		if st.status != "running":
			break
	ok("집행관: 순간이동 없음(봇 전투 15초 동안 한 단계 최대 이동 %.1fpx ≤ 15)" % max_jump, max_jump <= 15.0)

# ---------- 행동 개편(연계·옆뛰기, data/boss_behavior.json 시험값) ----------
## 위의 시험은 모두 beh_off(개편 끔)로 패턴 자체를 확인했다. 여기서는 개편을 켠 상태만 본다.
## 개편이 꺼져 있으면(파일 없음·enabled=false) 건너뛴다.
func chain_state(id: String, dist: float = 80.0, seed_v: int = 11) -> CombatState:
	var st := CombatState.new({ "build": build(), "seed": seed_v, "arena": "forest", "boss": true, "boss_id": id,
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
	for i in 600:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	var bz := st.boss
	st.player.x = clampf(bz.x + dist, 20.0, st.arena_w - 20.0)
	st.player.y = bz.y
	return st

func chain_tests() -> void:
	if PBoss.chain_cfg({ "boss_id": "gate_warden", "phase": 1 }).is_empty():
		ok("행동 개편(boss_behavior.json)이 꺼져 있어 연계 검사를 건너뛴다", true)
		return
	# 1) 가까이 붙어도 후보가 한 종류만 남지 않는다(파수장 방패 자세만 / 거수 낙석만 / 추적자 얼음길만 / 사냥왕 발톱만 나오던 문제)
	for id in PBoss3.IDS:
		var st := chain_state(String(id), 80.0)
		var bz := st.boss
		bz.actions = 3
		bz.history = []
		var cands: Array = []
		for c in PBoss3.candidates(st, bz):
			cands.append(String(c[0]))
		ok("%s: 거리 80에서 후보가 2종 이상(한 패턴만 반복하지 않는다)" % String(id), cands.size() >= 2, str(cands))
	# 2) 여러 행동을 연달아 한 뒤 반드시 빈틈이 온다(무한 연계 없음)
	for id in PBoss3.IDS:
		var st2 := chain_state(String(id), 160.0)
		var bz2 := st2.boss
		var chain_len := 0
		var rec := -1.0
		var prev_n := int(bz2.get("attack_n", 0))
		for i in 120 * 40:
			st2.player.hp = st2.player.hp_max
			st2.step({}, STEP)
			var n := int(bz2.get("attack_n", 0))
			if n > prev_n:
				prev_n = n
				chain_len += 1
			if String(bz2.state) == "recover" and chain_len >= 2:
				rec = float(bz2.recover_dur)
				break
		ok("%s: 연계 %d회 뒤 빈틈 %.2f초(0.5초 이상)" % [String(id), chain_len, maxf(0.0, rec)], chain_len >= 2 and rec >= 0.5)
	# 3) 예고: 연계 첫 공격은 원래 값 그대로, 후속타만 빨라지되 하한을 지킨다
	var floor_ok := true
	var floor_txt: Array = []
	for id in PBoss3.IDS:
		var st3 := chain_state(String(id), 160.0)
		var bz3 := st3.boss
		var cfg := PCatalog.boss_def(String(id))
		var lo := float(PBoss.chain_cfg(bz3).get("followWarnMin", 0.5))
		var prev := int(bz3.get("attack_n", 0))
		var follow_seen := 0
		for i in 120 * 40:
			st3.player.hp = st3.player.hp_max
			st3.step({}, STEP)
			var n := int(bz3.get("attack_n", 0))
			if n <= prev:
				continue
			prev = n
			var hh: Array = bz3.history
			var pat := String(hh[hh.size() - 1])
			var base := PBoss.pattern_warn(cfg, pat)
			var sp := float(bz3.warn_speed)
			if int(bz3.chain_i) == 1 and not is_equal_approx(sp, 1.0):
				floor_ok = false
				floor_txt.append("%s 첫 공격 배속 %.2f" % [String(id), sp])
			if int(bz3.chain_i) >= 2 and base > 0.0:
				follow_seen += 1
				if base / sp < lo - 1e-6:
					floor_ok = false
					floor_txt.append("%s.%s %.2f초" % [String(id), pat, base / sp])
			if follow_seen >= 3:
				break
	ok("신규 6종: 연계 첫 공격의 예고는 데이터 원래 값, 후속타 예고는 하한 이상", floor_ok, ", ".join(floor_txt))
	# 4) 감속장(Q): 연계를 켜도 예고·빈틈이 그대로 40%로 늦춰진다(Q를 조용히 약화하지 않았다)
	var q_ok := true
	var q_txt: Array = []
	for id in PBoss3.IDS:
		var st4 := chain_state(String(id), 60.0)
		var bz4 := st4.boss
		bz4.state = "recover"
		bz4.state_t = 0.0
		bz4.recover_dur = 3.0
		st4.player.x = bz4.x
		st4.player.y = bz4.y + 40.0
		st4.step({ "special": true }, STEP)
		if absf(float(bz4.state_t) - STEP * 0.4) > 1e-9:
			q_ok = false
			q_txt.append("%s 빈틈 %.5f" % [String(id), float(bz4.state_t)])
	ok("신규 6종: 감속장 안 빈틈 진행 = dt × 0.4 (연계를 켜도 그대로)", q_ok, ", ".join(q_txt))

## 3막 관문(종말의 집행관) 위치 변주: 절단선 사이에 보스만 옆으로 움직인다.
## 예고 시간·선 위치·피해·빈틈은 그대로여야 한다(기존 대응 보존).
func executor_variation_tests() -> void:
	if PBoss.beh_e({ "boss_id": "doom_executor", "phase": 1 }).get("gapStep", {}).is_empty():
		ok("집행관 위치 변주가 꺼져 있어(gapStep 없음) 검사를 건너뛴다", true)
		return
	var SL: Dictionary = PCatalog.boss_def("doom_executor").slash
	var st := chain_state("doom_executor", 200.0)
	var bz := st.boss
	PBoss3.begin(st, bz, "slash")
	var px0: float = st.player.x
	run_until(st, func(): return String(bz.state) == "slash_lock", 2.0)
	var line1: float = float(bz.slashes[0].x)
	run_until(st, func(): return String(bz.state) == "slash_gap", 1.0)
	var bx0: float = float(bz.x)
	var by0: float = float(bz.y)
	var line2: float = float(bz.slashes[1].x)
	var gap_sec: float = PBoss.pat_num(bz, PCatalog.boss_def("doom_executor"), "slash", "gap", float(SL.gap))
	var moved := 0.0
	for i in int(gap_sec / STEP) - 1:
		st.step({}, STEP)
		if String(bz.state) != "slash_gap":
			break
	moved = PGeom.dist(float(bz.x), float(bz.y), bx0, by0)
	ok("집행관: 절단선 1↔2 사이에 보스가 옆으로 파고든다(위치 변주)", moved > 10.0, "이동 %.0f" % moved)
	ok("집행관: 절단선 위치는 그대로 플레이어 x 기준(변주가 판정을 바꾸지 않는다)",
		is_equal_approx(float(bz.slashes[0].x), line1) and is_equal_approx(float(bz.slashes[1].x), line2) and is_equal_approx(line1, px0),
		"1번 %.0f · 2번 %.0f · 플레이어 %.0f" % [line1, line2, px0])
	var thr := boss_threats(st)
	var beam_ok := true
	for t in thr:
		if String(t.get("kind", "")) == "beam" and absf(float(t.get("ang", 0.0)) - PI / 2.0) < 1e-6:
			# 예고 도형은 여전히 세로선이고 x는 선 위치와 같다(보스 위치와 무관)
			if absf(float(t.x) - line1) > 1e-6 and absf(float(t.x) - line2) > 1e-6:
				beam_ok = false
	ok("집행관: 화면·봇이 보는 예고 도형이 보스 이동과 무관하게 선 위치 그대로다", beam_ok, str(thr.size()))
	run_until(st, func(): return String(bz.state) == "recover", 2.0)
	ok("집행관: 절단선 뒤 빈틈은 그대로 %.1f초" % float(SL.recover), is_equal_approx(float(bz.recover_dur), float(SL.recover)), "%.2f" % float(bz.recover_dur))

# ---------- 지형 파괴 자격이 후보 규칙을 새게 하지 않는가 ----------
## 시선이 막히면 후보에서 빠지던 행동(돌파·굴착·발톱)은, **파괴 자격을 받은 그 행동일 때만** 되살아난다.
## 자격이 없으면 개편 전과 똑같이 빠져야 한다 — 모든 공격을 벽 관통으로 만들지 않았다는 확인이다.
## 파괴가 실제로 일어나는지·무엇이 부서지는지는 tests/boss_break_tests.gd가 본다.
func break_candidate_tests() -> void:
	var pairs := [["gate_warden", "breach"], ["excavation_behemoth", "burrow"], ["blood_hunt_king", "claw"]]
	for pr in pairs:
		var bid := String(pr[0])
		var pat := String(pr[1])
		var st := CombatState.new({ "build": build(), "seed": 11, "arena": "clearing", "boss": true, "boss_id": bid,
			"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": 1000000.0 })
		run_until(st, func(): return String(st.boss.state) != "intro", 3.0)
		var bz: Dictionary = st.boss
		# 보스와 플레이어 사이에 돌을 놓아 시선을 막는다(파괴 자격은 주지 않는다)
		var p := st.player
		p.x = float(bz.x)
		p.y = float(bz.y) + 200.0
		st.obstacles.append({ "id": "mid", "type": "rock", "x": float(bz.x), "y": float(bz.y) + 100.0, "r": 40.0, "canopy": false })
		bz.break_want = false
		var names0 := []
		for c in PBoss3.candidates(st, bz):
			names0.append(String(c[0]))
		ok("%s: 파괴 자격이 없으면 시선이 막힌 %s는 후보에서 빠진다" % [bid, pat], not names0.has(pat), str(names0))
		bz.break_want = true
		var names1 := []
		for c in PBoss3.candidates(st, bz):
			names1.append(String(c[0]))
		var only_that := names1.has(pat)
		for n in names1: # 자격은 그 행동 하나만 되살린다(다른 시선 검사 행동까지 열리지 않는다)
			if not names0.has(String(n)) and String(n) != pat:
				only_that = false
		ok("%s: 파괴 자격을 받은 %s만 후보로 되살아난다" % [bid, pat], only_that, str(names1))
