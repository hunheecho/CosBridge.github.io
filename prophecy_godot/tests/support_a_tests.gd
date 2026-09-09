extends SceneTree
## 보조무기 A조(⑥ 추격 까마귀 · ⑦ 수호 방울 · ⑧ 잔영 분신 · ⑨ 바람 정령) 동작 시험(화면 없음):
##   godot --headless --path prophecy_godot -s tests/support_a_tests.gd
##
## 역할별 지표로 본다(피해만 보지 않는다):
##  - 까마귀: 표적이 언제 바뀌고 언제 안 바뀌는가 · 표적 사망 뒤 규칙 · 개조별 차이
##  - 방울: 차단 횟수와 막힌 피해량 · 차단 불가 공격 · 근접 수호가 같은 충전을 쓰는가 · 되돌림이 원래 피해를 복사하지 않는가
##  - 분신: 발동 횟수와 실제 피해 · 분신 자리에서 판정되는가 · 주무기 개조를 복제하지 않는가 · 분신이 분신을 만들지 않는가 · 감전 발동
##  - 바람: 실제로 확보한 거리 · 보스·정예 저항 · 벽 안으로 안 들어가는가 · 둔화 바닥
##  - 공통: 전투가 끝나거나 보조가 바뀌면 남은 개체·장판이 사라지는가
##
## 여기 나오는 수치는 전부 **시험값**이다(data/supports.json). 사람이 승인한 밸런스가 아니다.

const STEP := 1.0 / 60.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 준비 ----------
## 장애물 없는 빈 전장에 원하는 무기 구성으로 전투 상태를 만든다(소환 멈춤)
func mk(ws: Array, obstacles: Array = []) -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.weapons = ws.duplicate(true)
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 1, "arena": "forest", "waves": [], "region_id": "lab",
		"obstacles": obstacles, "objective": "clear" })
	st.spawn_hold = true
	st.player.x = 480.0
	st.player.y = 300.0
	return st

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

func put(st: CombatState, type_id: String, x: float, y: float) -> Dictionary:
	var e := st.spawn_enemy(type_id, x, y)
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

func tick(st: CombatState, seconds: float) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		PSupport.update(st, STEP)

## 주무기가 직접 맞힌 것처럼 만든다(공용 발사 관문을 거치지 않고 피해 경로만 재현).
## PWeapons.dmg_to가 출처(src)를 붙이므로 PSupport가 보는 경로는 실제 전투와 같다
func main_hit(st: CombatState, e: Dictionary, mult: float = 1.0) -> float:
	var mw := wep(st, "sword")
	mw.count = int(mw.count) + 1 # 한 번의 공격 = count 하나(분신 중복 생성 판정에 쓰인다)
	return PWeapons.dmg_to(st, e, mw, mult, {})

## 보조가 맞힌 것처럼 만든다(경로 이름 support_direct)
func support_hit(st: CombatState, e: Dictionary) -> void:
	var sw := wep(st, "crow")
	PWeapons.dmg_to(st, e, sw, 1.0, { "cause": "support_direct" })

func crow_state(st: CombatState) -> Dictionary:
	return (st.support as Dictionary).get("crow", {})

func bell_state(st: CombatState) -> Dictionary:
	return (st.support as Dictionary).get("bell", {})

func echo_state(st: CombatState) -> Dictionary:
	return (st.support as Dictionary).get("echo", {})

func wind_state(st: CombatState) -> Dictionary:
	return (st.support as Dictionary).get("wind", {})

func target_id(S: Dictionary) -> int:
	if S.is_empty() or S.get("target") == null:
		return -1
	return int((S.target as Dictionary).id)

func zone_count(st: CombatState, type_id: String) -> int:
	var n := 0
	for z in st.zones:
		if String(z.type) == type_id:
			n += 1
	return n

func _init() -> void:
	sec1_data()
	sec2_crow()
	sec3_bell()
	sec4_echo()
	sec5_wind()
	sec6_lifetime()
	sec7_frame_path()
	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 1. 자료 계약 ----------
func sec1_data() -> void:
	var W := PCatalog.weapons()
	var mine := ["crow", "bell", "echo", "wind"]
	var not_impl := []
	var no_icon := []
	var mods_n := 0
	for id in mine:
		if not bool(W[id].get("impl", false)):
			not_impl.append(id)
		if not PIcons.has(PIcons.weapon_key(id)):
			no_icon.append(PIcons.weapon_key(id))
		for mid in W[id].mods:
			mods_n += 1
			if not bool(W[id].mods[mid].get("impl", false)):
				not_impl.append("%s:%s" % [id, String(mid)])
			if not PIcons.has(PIcons.mod_key(id, String(mid))):
				no_icon.append(PIcons.mod_key(id, String(mid)))
	ok("A조 보조 4종과 개조 12개가 전부 impl:true다", not_impl.is_empty() and mods_n == 12, "미구현 %s · 개조 %d개" % [str(not_impl), mods_n])
	ok("A조 4종과 개조 12개에 각자 아이콘이 있다(다른 효과의 그림을 빌리지 않는다)", no_icon.is_empty(), str(no_icon))
	var files := {}
	var dup := []
	for k in PIcons.data().map:
		var f := String(PIcons.data().map[k].file)
		if files.has(f):
			dup.append(f)
		files[f] = k
	ok("아이콘 그림 파일이 두 효과에 겹쳐 배정되지 않았다", dup.is_empty(), str(dup))
	ok("방울의 차단 가능 목록이 자료에 있다(코드에 적혀 있지 않다)",
		(PCatalog.weapon("bell").base.incoming.blockable as Array).size() > 0,
		str(PCatalog.weapon("bell").base.incoming.blockable))

# ---------- 2. ⑥ 추격 까마귀 ----------
func sec2_crow() -> void:
	var st := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": [] }])
	var cw := wep(st, "crow")
	var hold := float(cw.stats.hold)
	var e1 := put(st, "wolf", 680.0, 300.0)
	var e2 := put(st, "wolf", 480.0, 130.0)
	tick(st, 0.1)
	ok("아직 주무기가 맞히지 않았으면 까마귀는 표적이 없다(스스로 찾지 않는다)", target_id(crow_state(st)) == -1)
	main_hit(st, e1)
	var S := crow_state(st)
	ok("주무기로 직접 맞힌 적이 표적이 된다", target_id(S) == int(e1.id) and int(S.marks) == 1, "표적 %d · 지정 %d회" % [target_id(S), int(S.marks)])
	main_hit(st, e2)
	ok("표적 유지 시간 동안에는 본체가 다른 적을 쳐도 표적이 안 바뀐다", target_id(S) == int(e1.id) and int(S.marks) == 1)
	support_hit(st, e2)
	ok("보조 피해로는 표적이 안 바뀐다(자격표 crow_mark)", target_id(S) == int(e1.id))
	ok("자격표가 보조·장판·분신 경로의 표적 지정을 막는다",
		PSupport.eligible("crow_mark", "main_direct")
		and not PSupport.eligible("crow_mark", "support_direct")
		and not PSupport.eligible("crow_mark", "echo_direct")
		and not PSupport.eligible("crow_mark", "zone_tick"))
	# 유지 시간이 지나면 다음 주무기 타격이 새 표적을 만든다
	tick(st, hold + 0.2)
	main_hit(st, e2)
	ok("표적 유지 시간이 지나면 다음 주무기 타격이 표적을 옮긴다", target_id(S) == int(e2.id) and int(S.marks) == 2, "표적 %d" % target_id(S))
	# 까마귀가 표적 위에 도착하면 실제로 쫀다
	tick(st, 1.0)
	var hp0: float = e2.hp
	PWeapons.fire(st, cw, e2, false)
	ok("표적 위에 도착한 까마귀가 표적을 쫀다(본체가 아니라 까마귀 자리에서 온 피해)",
		int(S.strikes) == 1 and float(S.damage) > 0.0 and e2.hp < hp0, "타격 %d회 · 피해 %.1f" % [int(S.strikes), float(S.damage)])
	ok("까마귀 피해가 보조 경로(support_direct)로 집계된다", float(st.metrics.cause_dmg.get("support_direct", 0.0)) > 0.0)
	# 표적 사망 → 다음 대상 규칙(사거리 안·가림 없는 가장 가까운 적)
	st.damage_enemy(e2, 9999.0, { "src": { "weapon": wep(st, "sword").stats, "weapon_id": "sword", "level": 1, "direct": true } })
	tick(st, 0.1)
	ok("표적이 죽으면 사거리 안 가장 가까운 적으로 옮긴다(자동 재지정 1회)",
		target_id(S) == int(e1.id) and int(S.retargets) == 1, "표적 %d · 재지정 %d" % [target_id(S), int(S.retargets)])
	st.damage_enemy(e1, 9999.0, { "src": { "weapon": wep(st, "sword").stats, "weapon_id": "sword", "level": 1, "direct": true } })
	tick(st, 0.1)
	ok("옮길 적이 없으면 표적을 비우고 대기한다", target_id(S) == -1)
	# 사거리 이탈: 표적이 사거리 밖으로 나가면 사망과 같은 규칙으로 다음 대상을 고른다
	var rs2 := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": [] }])
	var rw2 := wep(rs2, "crow")
	var f1 := put(rs2, "wolf", 680.0, 300.0)
	var f2 := put(rs2, "wolf", 560.0, 300.0)
	main_hit(rs2, f1)
	tick(rs2, 0.1)
	var RS2 := crow_state(rs2)
	ok("사거리 이탈 전에는 표적이 그대로다", target_id(RS2) == int(f1.id))
	f1.x = rs2.player.x + float(rw2.stats.range) + 200.0 # 표적이 사거리 밖으로 달아났다
	tick(rs2, 0.1)
	ok("표적이 사거리 밖으로 나가면 사거리 안 가장 가까운 적으로 옮긴다",
		target_id(RS2) == int(f2.id) and int(RS2.retargets) == 1, "표적 %d · 재지정 %d" % [target_id(RS2), int(RS2.retargets)])

	# --- 개조 ① 집중 사냥: 같은 적을 계속 치면 피해 단계 상승, 표적이 바뀌면 초기화 ---
	var sh := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": ["hunt"] }])
	var hw := wep(sh, "crow")
	var h1 := put(sh, "wolf", 680.0, 300.0)
	h1.hp = 99999.0
	main_hit(sh, h1)
	tick(sh, 1.0)
	var first := 0.0
	var last := 0.0
	for i in 6:
		var b: float = h1.hp
		PWeapons.fire(sh, hw, h1, false)
		var d: float = b - h1.hp
		if i == 0:
			first = d
		last = d
	ok("집중 사냥: 같은 적을 계속 치면 피해가 단계적으로 오른다", last > first + 0.01, "첫 %.1f → 마지막 %.1f" % [first, last])
	var h2 := put(sh, "wolf", 480.0, 140.0)
	h2.hp = 99999.0
	tick(sh, float(hw.stats.hold) + 0.2)
	main_hit(sh, h2)
	tick(sh, 1.2)
	var b2: float = h2.hp
	PWeapons.fire(sh, hw, h2, false)
	ok("집중 사냥: 표적이 바뀌면 단계가 초기화된다", absf((b2 - h2.hp) - first) < 0.05, "새 표적 첫 타격 %.1f (기준 %.1f)" % [b2 - h2.hp, first])

	# --- 개조 ② 먹잇감 전환: 표적 처치 뒤 다음 적 첫 공격이 강해진다 ---
	var ss := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": ["switch"] }])
	var sw2 := wep(ss, "crow")
	var s1 := put(ss, "wolf", 680.0, 300.0)
	var s2 := put(ss, "wolf", 660.0, 320.0)
	s2.hp = 99999.0
	main_hit(ss, s1)
	tick(ss, 1.0)
	ss.damage_enemy(s1, 9999.0, { "src": { "weapon": wep(ss, "sword").stats, "weapon_id": "sword", "level": 1, "direct": true } })
	tick(ss, 1.0)
	var sb: float = s2.hp
	PWeapons.fire(ss, sw2, s2, false)
	var boosted: float = sb - s2.hp
	var sb2: float = s2.hp
	PWeapons.fire(ss, sw2, s2, false)
	var plain: float = sb2 - s2.hp
	ok("먹잇감 전환: 표적 처치 뒤 다음 적 첫 공격만 강해진다",
		boosted > plain * 1.5 and plain > 0.0, "첫 %.1f vs 그다음 %.1f" % [boosted, plain])

	# --- 개조 ③ 쌍둥이 까마귀: 두 마리가 서로 다른 적을, 개체 화력은 낮게 ---
	var ts := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": ["twin"] }])
	var tw := wep(ts, "crow")
	var t1 := put(ts, "wolf", 680.0, 300.0)
	var t2 := put(ts, "wolf", 480.0, 140.0)
	t1.hp = 99999.0
	t2.hp = 99999.0
	main_hit(ts, t1)
	tick(ts, 1.2)
	var TS := crow_state(ts)
	ok("쌍둥이: 까마귀가 두 마리고 두 번째는 표적과 다른 적을 문다",
		(TS.birds as Array).size() == 2 and TS.alt != null and int((TS.alt as Dictionary).id) == int(t2.id),
		"%d마리" % (TS.birds as Array).size())
	var a0: float = t1.hp
	var b0: float = t2.hp
	PWeapons.fire(ts, tw, t1, false)
	var da: float = a0 - t1.hp
	var db: float = b0 - t2.hp
	ok("쌍둥이: 한 주기에 두 적이 각각 맞는다", da > 0.0 and db > 0.0, "표적 %.1f · 두 번째 %.1f" % [da, db])
	ok("쌍둥이: 개체당 피해가 기본 한 마리보다 낮다", da < first, "쌍둥이 %.1f < 기본 %.1f" % [da, first])

# ---------- 3. ⑦ 수호 방울 ----------
func sec3_bell() -> void:
	var st := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": [] }])
	var bw := wep(st, "bell")
	var cap := PSupportA.bell_max(st, bw)
	var archer := put(st, "archer", 700.0, 300.0)
	var r1 := PSupport.on_player_damage(st, 30.0, "arrow", archer)
	var S := bell_state(st)
	ok("차단 가능한 적 투사체는 완전히 막힌다(0을 돌려준다)", is_zero_approx(r1) and int(S.blocked) == 1 and is_equal_approx(float(S.blocked_damage), 30.0),
		"차단 %d회 · 막은 피해 %.1f" % [int(S.blocked), float(S.blocked_damage)])
	var r2 := PSupport.on_player_damage(st, 18.0, "arrow", archer)
	ok("방울을 쓸수록 저장이 줄고 차단 횟수·막힌 피해량이 쌓인다",
		is_zero_approx(r2) and int(S.blocked) == 2 and is_equal_approx(float(S.blocked_damage), 48.0) and int(S.charges) == cap - 2,
		"남은 방울 %d/%d" % [int(S.charges), cap])
	var r3 := PSupport.on_player_damage(st, 25.0, "arrow", archer)
	ok("방울이 다 떨어지면 더 막지 못한다", is_equal_approx(r3, 25.0) and int(S.blocked) == 2)
	tick(st, float(bw.stats.recharge) + 0.1)
	ok("시간이 지나면 방울이 다시 찬다", int(S.charges) == 1, "%d개" % int(S.charges))
	# 차단 불가 공격
	var bs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": [] }])
	var boss := put(bs, "boss", 700.0, 300.0)
	var rb := PSupport.on_player_damage(bs, 40.0, "boss_bolt", boss)
	var BS := bell_state(bs)
	ok("차단 불가 공격(보스 투사체)은 막히지 않고 방울도 쓰이지 않는다",
		is_equal_approx(rb, 40.0) and int(BS.blocked) == 0 and int(BS.charges) == PSupportA.bell_max(bs, wep(bs, "bell")),
		"%.1f · 방울 %d" % [rb, int(BS.charges)])
	var rz := PSupport.on_player_damage(bs, 12.0, "zone", null)
	ok("장판 피해도 방울로 막지 못한다", is_equal_approx(rz, 12.0) and int(BS.blocked) == 0)
	var rm := PSupport.on_player_damage(bs, 22.0, "wolf:bite", null)
	ok("근접 수호 개조가 없으면 근접 피해는 그대로 들어온다", is_equal_approx(rm, 22.0))
	# 근접 수호: 투사체와 같은 충전을 쓴다
	var gs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": ["guard"] }])
	var gw := wep(gs, "bell")
	var gcap := PSupportA.bell_max(gs, gw)
	var garcher := put(gs, "archer", 700.0, 300.0)
	var g1 := PSupport.on_player_damage(gs, 40.0, "wolf:bite", null)
	var GS := bell_state(gs)
	ok("근접 수호: 근접 한 타격의 피해를 절반으로 줄인다(막지는 않는다)",
		is_equal_approx(g1, 40.0 * (1.0 - float(gw.stats.guardCut))) and int(GS.guarded) == 1, "%.1f" % g1)
	for i in gcap - 1:
		PSupport.on_player_damage(gs, 10.0, "wolf:bite", null)
	var g2 := PSupport.on_player_damage(gs, 30.0, "arrow", garcher)
	ok("근접 수호는 투사체 차단과 **같은 충전**을 쓴다(근접으로 다 쓰면 투사체를 못 막는다)",
		is_equal_approx(g2, 30.0) and int(GS.charges) == 0 and int(GS.blocked) == 0,
		"방울 %d · 근접 수호 %d회 · 차단 %d회" % [int(GS.charges), int(GS.guarded), int(GS.blocked)])
	# 되돌림: 원래 피해를 복사하지 않는다
	var fs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": ["reflect"] }])
	var fw := wep(fs, "bell")
	var shooter := put(fs, "archer", 640.0, 300.0)
	shooter.hp = 99999.0
	var huge := 999.0
	var rr := PSupport.on_player_damage(fs, huge, "arrow", shooter)
	var FS := bell_state(fs)
	ok("되돌림: 막은 순간 반격탄이 나간다", is_zero_approx(rr) and int(FS.reflects) == 1 and fs.projectiles.size() == 1)
	var hp_b: float = shooter.hp
	for i in 240:
		fs.update_projectiles(STEP)
		if shooter.hp < hp_b:
			break
	var back: float = hp_b - shooter.hp
	ok("되돌림 피해는 원래 적 투사체 피해를 복사하지 않는다(방울의 별도 시험값)",
		back > 0.0 and back < huge * 0.2 and is_equal_approx(back, float(fw.stats.damage)),
		"반격 %.1f (원래 %.1f · 자료값 %.1f)" % [back, huge, float(fw.stats.damage)])
	# 겹울림
	var ls := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": ["layered"] }])
	var lw := wep(ls, "bell")
	ok("겹울림: 저장 방울이 하나 늘고 충전이 느려진다",
		PSupportA.bell_max(ls, lw) == cap + 1 and PSupportA.bell_recharge(ls, lw) > PSupportA.bell_recharge(st, bw),
		"%d개 · %.2f초" % [PSupportA.bell_max(ls, lw), PSupportA.bell_recharge(ls, lw)])
	# 실제 피격 경로에서도 체력이 안 깎인다
	var ps := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": [] }])
	var pa := put(ps, "archer", 700.0, 300.0)
	var php: float = ps.player.hp
	ps.damage_player(31.0, "arrow", pa)
	ok("실제 피격 경로에서도 차단된 투사체는 체력을 깎지 않는다", is_equal_approx(ps.player.hp, php), "%.1f" % ps.player.hp)
	# 표시용 표식(화면이 차단 가능/불가를 다르게 그릴 수 있게 규칙이 남기는 값)
	var ms := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "bell", "level": 1, "mods": [] }])
	var ma := put(ms, "archer", 700.0, 300.0)
	ms.projectiles.append({ "owner": "enemy", "kind": "arrow", "shooter": ma, "x": 700.0, "y": 300.0, "vx": -1.0, "vy": 0.0, "r": 4.0, "dmg": 5.0, "ttl": 2.0, "dead": false, "hits": {} })
	ms.projectiles.append({ "owner": "enemy", "kind": "boss_bolt", "shooter": ma, "x": 700.0, "y": 320.0, "vx": -1.0, "vy": 0.0, "r": 4.0, "dmg": 5.0, "ttl": 2.0, "dead": false, "hits": {} })
	tick(ms, STEP)
	ok("날아오는 적 투사체에 '막을 수 있는가' 표식이 붙는다(화면이 다르게 그릴 근거)",
		bool(ms.projectiles[0].get("bell_blockable", false)) and not bool(ms.projectiles[1].get("bell_blockable", true)),
		"arrow=%s · boss_bolt=%s" % [str(ms.projectiles[0].get("bell_blockable")), str(ms.projectiles[1].get("bell_blockable"))])

# ---------- 4. ⑧ 잔영 분신 ----------
func sec4_echo() -> void:
	# 검(사거리 95)으로 A를 치면 분신은 공격 방향 반대쪽 offset(72) 자리에 선다.
	# B는 본체 사거리 밖이고 분신 사거리 안이라, 분신이 본체 위치가 아니라 **제 자리에서** 판정한다는 증거가 된다
	var st := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": [] }])
	var ew := wep(st, "echo")
	var mw := wep(st, "sword")
	var reach := float(mw.stats.range)
	var a := put(st, "wolf", 480.0 + reach - 10.0, 300.0)
	var b := put(st, "wolf", 480.0 - float(ew.stats.offset) - 40.0, 300.0)
	a.hp = 99999.0
	b.hp = 99999.0
	var pd := PGeom.dist(st.player.x, st.player.y, b.x, b.y)
	ok("배치 확인: B는 본체 사거리 밖이다(분신 자리에서만 닿는다)", pd > reach + float(b.r), "본체→B %.0f · 사거리 %.0f" % [pd, reach])
	main_hit(st, a)
	var S := echo_state(st)
	ok("주무기 기본 공격 한 번에 분신 하나가 생긴다", int(S.spawned) == 1 and (S.clones as Array).size() == 1, "%d개" % int(S.spawned))
	var bhp0: float = b.hp
	var ahp0: float = a.hp
	tick(st, float(ew.stats.delay) + 0.1)
	ok("분신은 시간차를 두고 따라 한다(발동 횟수 1 · 실제 피해 있음)",
		int(S.strikes) == 1 and float(S.damage) > 0.0, "타격 %d회 · 피해 %.1f" % [int(S.strikes), float(S.damage)])
	ok("분신은 **분신이 선 자리**에서 사거리·적중을 판정한다(본체가 못 닿는 B가 맞았다)",
		b.hp < bhp0 and is_equal_approx(a.hp, ahp0), "B %.1f 감소 · A %.1f 감소" % [bhp0 - b.hp, ahp0 - a.hp])
	var want := float(mw.stats.damage) * float(ew.stats.share)
	ok("분신 피해는 주무기 피해 × share다(본체보다 낮다)",
		absf((bhp0 - b.hp) - want) < 0.2 and want < float(mw.stats.damage), "%.1f (기대 %.1f)" % [bhp0 - b.hp, want])
	ok("분신 타격이 자기 경로(echo_direct)로 집계된다", int(st.metrics.cause_fires.get("echo_direct", 0)) == 1)
	ok("분신이 분신을 만들지 않는다(순환 금지)", int(S.spawned) == 1 and (S.clones as Array).size() == 0)
	# 한 번의 공격이 적 여럿을 맞혀도 분신은 하나다(같은 발사 번호는 한 번만 복제한다)
	var ds := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": [] }])
	var dw := wep(ds, "sword")
	var d1 := put(ds, "wolf", 540.0, 300.0)
	var d2 := put(ds, "wolf", 540.0, 330.0)
	var d3 := put(ds, "wolf", 545.0, 270.0)
	d1.hp = 99999.0
	d2.hp = 99999.0
	d3.hp = 99999.0
	PWeapons.fire(ds, dw, d1, false) # 부채꼴 한 번에 셋이 맞는다
	var DS := echo_state(ds)
	ok("한 번의 공격이 여럿을 맞혀도 분신은 하나만 생긴다",
		int(DS.spawned) == 1 and int(ds.stats.hits) >= 3, "분신 %d개 · 적중 %d회" % [int(DS.spawned), int(ds.stats.hits)])
	# 주무기 개조를 복제하지 않는다: 교차 검격(3회마다 반대 방향 추가 타격)을 붙여도 분신은 한 번만 친다
	var cs := mk([{ "id": "sword", "level": 1, "mods": ["cross"] }, { "id": "echo", "level": 1, "mods": [] }])
	var cw := wep(cs, "sword")
	var ce := wep(cs, "echo")
	var c1 := put(cs, "wolf", 480.0 + float(cw.stats.range) - 10.0, 300.0)
	var c2 := put(cs, "wolf", 480.0 - float(ce.stats.offset) - 40.0, 300.0)
	c1.hp = 99999.0
	c2.hp = 99999.0
	cw.count = 3 # 교차 검격 조건(count % 3 == 0)을 만족시켜 반대 방향 추가 타격이 실제로 나가게 한다
	PWeapons.fire(cs, cw, c1, false)
	var CS := echo_state(cs)
	tick(cs, float(ce.stats.delay) + 0.1)
	ok("분신은 주무기 개조가 만든 추가 타격을 복제하지 않는다(교차 검격이 있어도 분신 타격은 1회)",
		int(CS.spawned) == 1 and int(CS.strikes) == 1 and int(cs.metrics.cause_fires.get("echo_direct", 0)) == 1,
		"생성 %d · 타격 %d" % [int(CS.spawned), int(CS.strikes)])
	# 시간차를 두고 따로 들어오는 개조 추가 타격(잔류 검흔)은 자격표(main_extra)가 막는다
	var sc := mk([{ "id": "sword", "level": 1, "mods": ["scar"] }, { "id": "echo", "level": 1, "mods": [] }])
	var scw := wep(sc, "sword")
	var sce := wep(sc, "echo")
	var sc1 := put(sc, "wolf", 480.0 + float(scw.stats.range) - 10.0, 300.0)
	var sc2 := put(sc, "wolf", 480.0 - float(sce.stats.offset) - 40.0, 300.0)
	sc1.hp = 99999.0
	sc2.hp = 99999.0
	PWeapons.fire(sc, scw, sc1, false)
	var SC := echo_state(sc)
	var after_base := int(SC.spawned)
	scw.count = int(scw.count) + 1 # 추가 타격이 '새 공격'으로 오인될 수 있는 최악의 조건을 만든다
	for d in sc.delayed:
		(d.fn as Callable).call() # 0.5초 뒤의 잔류 검흔을 지금 실행
	sc.delayed = []
	ok("주무기 개조의 지연 추가 타격은 자격표(main_extra)가 막아 분신을 새로 만들지 않는다",
		after_base == 1 and int(SC.spawned) == 1, "기본 뒤 %d개 → 추가 타격 뒤 %d개" % [after_base, int(SC.spawned)])
	ok("자격표가 개조 추가 타격·다른 보조·분신 자신의 복제를 막는다",
		PSupport.eligible("echo_copy", "main_direct")
		and not PSupport.eligible("echo_copy", "main_extra")
		and not PSupport.eligible("echo_copy", "support_direct")
		and not PSupport.eligible("echo_copy", "echo_direct"))
	# 분신의 직접 타격은 감전(전도 표식)을 발동시킨다
	var ks := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "orb", "level": 1, "mods": ["conduct"] }, { "id": "echo", "level": 1, "mods": [] }])
	var ke := wep(ks, "echo")
	var kw := wep(ks, "sword")
	var k1 := put(ks, "wolf", 480.0 + float(kw.stats.range) - 10.0, 300.0)
	var k2 := put(ks, "wolf", 480.0 - float(ke.stats.offset) - 40.0, 300.0)
	k1.hp = 99999.0
	k2.hp = 99999.0
	k2.conduct = 2.0
	main_hit(ks, k1)
	tick(ks, float(ke.stats.delay) + 0.1)
	ok("분신의 직접 타격이 감전(전도 표식)을 발동시킨다", is_zero_approx(float(k2.conduct)), "표식 %.2f" % float(k2.conduct))
	# --- 개조 ① 교차 잔영: 옆으로 떨어진 자리 ---
	var xs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": ["cross"] }])
	var xw := wep(xs, "echo")
	var x1 := put(xs, "wolf", 560.0, 300.0)
	x1.hp = 99999.0
	main_hit(xs, x1)
	var XS := echo_state(xs)
	var cl: Dictionary = (XS.clones as Array)[0]
	ok("교차 잔영: 본체 옆(공격 방향과 수직)으로 떨어진 자리에 선다",
		absf(float(cl.y) - xs.player.y) > 40.0 and absf(float(cl.x) - xs.player.x) < 1.0,
		"(%.0f, %.0f) · 본체 (%.0f, %.0f)" % [float(cl.x), float(cl.y), xs.player.x, xs.player.y])
	# --- 개조 ② 잔류 잔영: 지나온 자리에 남아 여러 번 ---
	var rs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": ["residual"] }])
	var rw := wep(rs, "echo")
	tick(rs, 1.0) # 지나온 자리 기록이 쌓이게
	var r1 := put(rs, "wolf", 540.0, 300.0)
	r1.hp = 99999.0
	main_hit(rs, r1)
	tick(rs, float(rw.stats.residualTtl) + float(rw.stats.delay) + 0.2)
	var RS := echo_state(rs)
	ok("잔류 잔영: 한 자리에 남아 여러 번 친다(수명이 끝나면 사라진다)",
		int(RS.strikes) == int(rw.stats.residualHits) and (RS.clones as Array).is_empty(),
		"타격 %d회(상한 %d)" % [int(RS.strikes), int(rw.stats.residualHits)])
	# --- 개조 ③ 추격 잔영: 대상을 따라가 제한 횟수 ---
	var chs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": ["chase"] }])
	var chw := wep(chs, "echo")
	var ch1 := put(chs, "wolf", 540.0, 300.0)
	ch1.hp = 99999.0
	main_hit(chs, ch1)
	tick(chs, float(chw.stats.chaseTtl) + float(chw.stats.delay) + 0.2)
	var CH := echo_state(chs)
	ok("추격 잔영: 대상을 따라가며 상한 횟수까지만 친다",
		int(CH.strikes) == int(chw.stats.chaseHits) and (CH.clones as Array).is_empty(),
		"타격 %d회(상한 %d)" % [int(CH.strikes), int(chw.stats.chaseHits)])
	var chs2 := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "echo", "level": 1, "mods": ["chase"] }])
	var cf := wep(chs2, "echo")
	var cz := put(chs2, "wolf", 540.0, 300.0)
	main_hit(chs2, cz)
	chs2.damage_enemy(cz, 9999.0, { "src": { "weapon": wep(chs2, "sword").stats, "weapon_id": "sword", "level": 1, "direct": true } })
	tick(chs2, float(cf.stats.delay) + 0.2)
	ok("추격 잔영: 대상이 죽으면 분신이 남지 않는다", (echo_state(chs2).clones as Array).is_empty())

# ---------- 5. ⑨ 바람 정령 ----------
func sec5_wind() -> void:
	var st := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": [] }])
	var ww := wep(st, "wind")
	var knock := float(ww.stats.knock)
	var e := put(st, "wolf", 540.0, 300.0)
	e.hp = 99999.0
	var x0: float = e.x
	PWeapons.fire(st, ww, e, false)
	var S := wind_state(st)
	ok("바람: 가까이 붙은 적을 실제로 밀어낸다(확보한 거리)",
		absf((e.x - x0) - knock) < 1.0 and absf(float(S.push_total) - knock) < 1.0 and e.hp < 99999.0,
		"밀어낸 거리 %.1f (시험값 %.0f)" % [e.x - x0, knock])
	var far := put(st, "wolf", 480.0 + float(ww.stats.trigger) + 120.0, 300.0)
	var fx0: float = far.x
	PWeapons.fire(st, ww, far, false)
	ok("발동 거리 밖에만 적이 있으면 돌풍이 불지 않는다", is_equal_approx(far.x, fx0) and int(S.blasts) == 1, "%d회" % int(S.blasts))
	# 보스·정예 저항
	var bs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": [] }])
	var bw := wep(bs, "wind")
	var boss := put(bs, "boss", 560.0, 300.0)
	var bx: float = boss.x
	PWeapons.fire(bs, bw, boss, false)
	ok("보스는 밀어내기로 위치가 강제로 바뀌지 않는다", is_equal_approx(boss.x, bx), "%.2f → %.2f" % [bx, boss.x])
	var es := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": [] }])
	var ew := wep(es, "wind")
	var el := put(es, "wolf_alpha", 550.0, 300.0)
	el.hp = 99999.0
	var ex: float = el.x
	PWeapons.fire(es, ew, el, false)
	var emoved: float = el.x - ex
	ok("정예는 밀리긴 하되 일반보다 덜 밀린다", emoved > 0.0 and emoved < knock - 1.0, "정예 %.1f < 일반 %.0f" % [emoved, knock])
	# 벽·바위 안으로 밀어 넣지 않는다
	var ws := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": [] }])
	ws.player.x = 820.0
	var w1 := put(ws, "wolf", 880.0, 300.0)
	w1.hp = 99999.0
	PWeapons.fire(ws, wep(ws, "wind"), w1, false)
	ok("벽 밖으로 밀려 나가지 않는다(전장 안에 남는다)",
		w1.x <= ws.arena_w - float(w1.r) + 1e-6 and ws.valid_pos(w1.x, w1.y, w1.r), "x=%.1f (전장 %.0f)" % [w1.x, ws.arena_w])
	var rs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": [] }],
		[{ "id": "rock_t", "type": "rock", "x": 760.0, "y": 300.0, "r": 40.0 }])
	rs.player.x = 600.0
	var w2 := put(rs, "wolf", 660.0, 300.0)
	w2.hp = 99999.0
	PWeapons.fire(rs, wep(rs, "wind"), w2, false)
	# 바위 표면에서 멈춘다. valid_pos는 '새로 놓아도 되는 자리'라 2px 여유를 더 요구하므로
	# 여기서는 겹침 여부(중심 거리 >= 바위 반지름 + 적 반지름)로 본다 — move_swept가 보장하는 것과 같은 기준이다
	var gap := PGeom.dist(w2.x, w2.y, 760.0, 300.0)
	ok("바위 안으로 밀어 넣지 않는다(표면에서 멈춘다)",
		gap >= 40.0 + float(w2.r) - 1e-6 and w2.x > 660.0 and w2.x < 660.0 + float(ww.stats.knock),
		"x=%.1f · 바위 중심까지 %.1f (막는 거리 %.1f)" % [w2.x, gap, 40.0 + float(w2.r)])
	# 개조: 각도·밀어내기 상충
	var mods := { "broad": 0.0, "focused": 0.0 }
	for mid in mods:
		var ms := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": [String(mid)] }])
		var mw := wep(ms, "wind")
		var me := put(ms, "wolf", 540.0, 300.0)
		me.hp = 99999.0
		var mx: float = me.x
		PWeapons.fire(ms, mw, me, false)
		mods[mid] = me.x - mx
	ok("넓은 돌풍은 개별 밀어내기가 약하고, 압축 돌풍은 강하다",
		float(mods.broad) < knock - 1.0 and float(mods.focused) > knock + 1.0,
		"넓은 %.1f · 기본 %.0f · 압축 %.1f" % [float(mods.broad), knock, float(mods.focused)])
	var bws := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["broad"] }])
	var bww := wep(bws, "wind")
	var side := put(bws, "wolf", 480.0 + 60.0, 300.0)
	var wide := put(bws, "wolf", 480.0 + 40.0, 300.0 - 90.0) # 90도 부채꼴 밖, 150도 부채꼴 안
	side.hp = 99999.0
	wide.hp = 99999.0
	var wy0: float = wide.y
	PWeapons.fire(bws, bww, side, false)
	ok("넓은 돌풍은 기본 각도 밖의 적까지 닿는다", absf(wide.y - wy0) > 1.0, "옆 적 이동 %.1f" % absf(wide.y - wy0))
	# 잔바람: 둔화가 겹쳐도 바닥 아래로 안 내려간다
	var ls := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var lw := wep(ls, "wind")
	var le := put(ls, "wolf", 540.0, 300.0)
	le.hp = 99999.0
	PWeapons.fire(ls, lw, le, false)
	ok("잔바람: 돌풍이 지나간 자리에 둔화 바람이 남는다", zone_count(ls, "windgust") > 0, "%d개" % zone_count(ls, "windgust"))
	# 같은 자리에 겹쳐 쌓아도 바닥 아래로 못 내려간다
	for i in 20:
		var z := ls.add_zone("windgust", le.x, le.y, float(lw.stats.gustR), 5.0, 0.0)
		z["slow"] = float(lw.stats.gustSlow)
	le.last_x = float(le.x) - 10.0
	le.last_y = float(le.y)
	PSupport.update(ls, STEP)
	var LS := wind_state(ls)
	ok("잔바람: 둔화를 겹쳐도 최저 이동 속도 아래로 내려가지 않는다",
		float(LS.slow_min) >= PSupport.slow_floor() - 1e-6 and float(LS.slow_min) < 1.0,
		"%.3f (바닥 %.2f)" % [float(LS.slow_min), PSupport.slow_floor()])
	ok("잔바람: 둔화된 적은 실제로 덜 움직인다(직전 이동을 되돌린다)",
		absf(float(le.x) - (float(le.last_x) + 10.0 * float(LS.slow_min))) < 0.5,
		"되돌린 뒤 x=%.2f" % float(le.x))
	# 잔바람 장판 상한
	var cs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var cw := wep(cs, "wind")
	for i in 12:
		var ce := put(cs, "wolf", 520.0 + float(i), 300.0)
		ce.hp = 99999.0
		PWeapons.fire(cs, cw, ce, false)
	ok("잔바람 장판은 상한을 넘겨 쌓이지 않는다(화면을 덮지 않게)",
		zone_count(cs, "windgust") <= int(cw.stats.gustMax), "%d개(상한 %d)" % [zone_count(cs, "windgust"), int(cw.stats.gustMax)])
	sec5_wind_lingering_place()

## 잔바람 회귀(2026-09-09 BP-1): '밀어낸 경로' → '돌풍이 지나간 자리'.
## 여기서 못박는 것 — (1) 밀리지 않는 상대에게도 장판이 남고 실제로 둔화가 걸린다,
## (2) 조각이 몇 겹이든 최저 이동 속도 바닥 아래로 못 내려간다, (3) 조각 수가 적 수에 비례하지 않는다.
func sec5_wind_lingering_place() -> void:
	# (1) 보스: PSupport.knock_dist가 0이라 한 걸음도 안 밀리지만 돌풍은 지나갔다
	var bs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var bw := wep(bs, "wind")
	var boss := put(bs, "boss", 560.0, 300.0)
	boss.hp = 9.0e6
	var bx0: float = boss.x
	PWeapons.fire(bs, bw, boss, false)
	var BS := wind_state(bs)
	ok("잔바람: 밀리지 않는 상대(보스)에게도 장판이 남는다",
		zone_count(bs, "windgust") > 0 and is_equal_approx(boss.x, bx0) and float(BS.push_total) == 0.0,
		"장판 %d개 · 밀어낸 거리 %.1f" % [zone_count(bs, "windgust"), float(BS.push_total)])
	for i in 60: # 1초 동안 보스가 장판 안에서 걷는다
		boss.last_x = float(boss.x) - 2.0
		boss.last_y = float(boss.y)
		PSupport.update(bs, STEP)
	PSupport.sync_meters(bs)
	var b_sec := PSupport.metered(bs, "wind", "slow_sec")
	var b_slows := PSupport.metered(bs, "wind", "slows")
	var b_expect := PSupport.stack_slow(1.0, float(bw.stats.gustSlow), boss)
	ok("잔바람: 보스에게 실제로 둔화가 걸린다(등급 저항을 적용한 값)",
		b_sec > 0.9 and b_slows >= 1.0 and absf(float(BS.slow_min) - b_expect) < 1e-6 and float(BS.slow_min) < 1.0,
		"slows=%.0f · slow_sec=%.2f · 이동 배율 %.4f(저항 적용 기대 %.4f)" % [b_slows, b_sec, float(BS.slow_min), b_expect])
	# (2) 몇 겹을 깔아도 바닥 아래로 못 내려간다. 한 조각의 둔화 비율을 바닥보다 세게 만들어 바닥 자체를 본다
	var fs := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var fw := wep(fs, "wind")
	var fe := put(fs, "wolf", 540.0, 300.0)
	fe.hp = 99999.0
	PWeapons.fire(fs, fw, fe, false)
	for i in 12:
		var z := fs.add_zone("windgust", fe.x, fe.y, float(fw.stats.gustR), 5.0, 0.0)
		z["slow"] = 0.95 # 바닥(0.35)보다 센 한 조각
	fe.last_x = float(fe.x) - 10.0
	fe.last_y = float(fe.y)
	PSupport.update(fs, STEP)
	var FS := wind_state(fs)
	ok("잔바람: 조각을 몇 겹 깔아도 최저 이동 속도 바닥 아래로 내려가지 않는다",
		absf(float(FS.slow_min) - PSupport.slow_floor()) < 1e-6,
		"이동 배율 %.3f (바닥 %.2f · 조각 %d개)" % [float(FS.slow_min), PSupport.slow_floor(), zone_count(fs, "windgust")])
	# (3) 조각 수는 한 번의 돌풍당 고정이다 — 적이 몇이든 gustPerBlast를 넘지 않는다
	var one := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var ow := wep(one, "wind")
	var oe := put(one, "wolf", 540.0, 300.0)
	oe.hp = 99999.0
	PWeapons.fire(one, ow, oe, false)
	var many := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var mw := wep(many, "wind")
	for i in 6:
		var me := put(many, "wolf", 530.0 + float(i) * 12.0, 290.0 + float(i) * 4.0)
		me.hp = 99999.0
	PWeapons.fire(many, mw, many.enemies[0], false)
	ok("잔바람: 한 번의 돌풍이 남기는 조각 수는 적 수에 비례하지 않는다",
		zone_count(one, "windgust") == zone_count(many, "windgust")
		and zone_count(one, "windgust") <= int(ow.stats.gustPerBlast) and zone_count(one, "windgust") > 0,
		"적 1기 %d개 · 적 6기 %d개(한 번 상한 %d)" % [zone_count(one, "windgust"), zone_count(many, "windgust"), int(ow.stats.gustPerBlast)])
	# 지표 두 개가 **다른 것을 센다**(2026-09-09 BP-2 회귀).
	# slows = 새로 둔화가 걸린 적의 수 · slow_sec = 둔화 적·초. 예전에는 하나가 둘을 겸해
	# 서리 수정의 slows(새로 걸린 횟수)와 같은 이름으로 세 자릿수 차이가 났다
	var ms2 := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var mw2 := wep(ms2, "wind")
	var me2 := put(ms2, "wolf", 540.0, 300.0)
	me2.hp = 99999.0
	PWeapons.fire(ms2, mw2, me2, false)
	for i in 60: # 1초 동안 한 마리가 계속 둔화 안에 있게 한다
		me2.last_x = float(me2.x) - 2.0
		me2.last_y = float(me2.y)
		PSupport.update(ms2, STEP)
	PSupport.sync_meters(ms2)
	var m_slows := PSupport.metered(ms2, "wind", "slows")
	var m_sec := PSupport.metered(ms2, "wind", "slow_sec")
	ok("바람 둔화 지표: 적 1기가 1초 있으면 slows=1 · slow_sec≈1.0(프레임 수가 아니다)",
		absf(m_slows - 1.0) < 0.001 and absf(m_sec - 1.0) < 0.05,
		"slows=%.0f · slow_sec=%.2f" % [m_slows, m_sec])

# ---------- 6. 공통 수명 ----------
func sec6_lifetime() -> void:
	var st := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }])
	var ww := wep(st, "wind")
	var e := put(st, "wolf", 540.0, 300.0)
	e.hp = 99999.0
	PWeapons.fire(st, ww, e, false)
	ok("전투 중에는 잔바람 장판이 있다", zone_count(st, "windgust") > 0)
	st.status = "won"
	st.mark_duel_done_for_test() # 결투가 예정된 편성이면 그것도 이긴 것으로 본다(승리 정산 규칙과 앞뒤를 맞춘다)
	PSupport.update(st, STEP)
	ok("전투가 끝나면 남은 장판·상태가 사라진다",
		zone_count(st, "windgust") == 0 and not (st.support as Dictionary).has("wind"), str((st.support as Dictionary).keys()))
	# 보조 교체: 무기 목록에서 빠지면 그 보조의 개체·장판이 사라진다
	var sw := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "wind", "level": 1, "mods": ["lingering"] }, { "id": "crow", "level": 1, "mods": [] }])
	var e2 := put(sw, "wolf", 540.0, 300.0)
	e2.hp = 99999.0
	PWeapons.fire(sw, wep(sw, "wind"), e2, false)
	main_hit(sw, e2)
	tick(sw, 0.2)
	ok("교체 전: 잔바람 장판과 까마귀 개체가 있다",
		zone_count(sw, "windgust") > 0 and (crow_state(sw).birds as Array).size() > 0)
	var g2: Dictionary = sw.build.growth
	g2.weapons = [{ "id": "sword", "level": 1, "mods": [] }, { "id": "blades", "level": 1, "mods": [] }]
	sw.rebuild(PBuild.derive(PBuild.empty_run_like(g2)))
	PSupport.update(sw, STEP)
	ok("보조가 바뀌면 옛 개체·장판이 남지 않는다(무료 중복 효과 금지)",
		zone_count(sw, "windgust") == 0 and not (sw.support as Dictionary).has("wind") and not (sw.support as Dictionary).has("crow"),
		str((sw.support as Dictionary).keys()))
	# 레벨업(같은 보조 유지)에서는 개체가 사라지지 않는다
	var lv := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": [] }])
	var le := put(lv, "wolf", 640.0, 300.0)
	le.hp = 99999.0
	main_hit(lv, le)
	tick(lv, 0.3)
	var g3: Dictionary = lv.build.growth
	g3.weapons = [{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 2, "mods": [] }]
	lv.rebuild(PBuild.derive(PBuild.empty_run_like(g3)))
	PSupport.update(lv, STEP)
	ok("레벨업으로 같은 보조가 강해질 때는 표적·개체가 유지된다",
		target_id(crow_state(lv)) == int(le.id) and (crow_state(lv).birds as Array).size() > 0)
	# B조 항목은 건드리지 않는다
	var mixed := mk([{ "id": "sword", "level": 1, "mods": [] }, { "id": "crow", "level": 1, "mods": [] }])
	(mixed.support as Dictionary)["thorns"] = { "keep": true }
	mixed.status = "lost"
	PSupport.update(mixed, STEP)
	ok("A조 정리가 B조(역병·갑각·인형)의 상태를 지우지 않는다", (mixed.support as Dictionary).has("thorns"))

# ---------- 7. 실제 프레임 경로 ----------
## 직접 호출이 아니라 st.step()으로 진짜 전투를 돌린다.
## 보는 것: 개체·장판·연출이 폭주하지 않는가(재귀 증식 금지) · 실제로 발동하는가 · 오류 없이 끝나는가
func play(ws: Array, seconds: float) -> CombatState:
	var g := PGrowth.new_growth("sword")
	g.weapons = ws.duplicate(true)
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": 7, "arena": "clearing", "waves": [], "region_id": "lab", "objective": "clear" })
	st.spawn_hold = true
	for i in 8:
		var e := st.spawn_enemy("wolf" if i % 3 != 0 else "archer", 200.0 + float(i) * 70.0, 140.0 + float(i % 3) * 60.0)
		e.hp = 400.0
	var n := int(round(seconds / STEP))
	var mv := 1.0
	for i in n:
		if i % 90 == 0:
			mv = -mv
		st.step({ "mx": mv, "my": 0.0 }, STEP)
	return st

func sec7_frame_path() -> void:
	var a := play([{ "id": "sword", "level": 2, "mods": [] }, { "id": "crow", "level": 2, "mods": ["twin"] }, { "id": "wind", "level": 2, "mods": ["lingering"] }], 20.0)
	var CA := crow_state(a)
	var WA := wind_state(a)
	ok("실제 전투(까마귀+바람 20초): 두 보조가 모두 실제로 발동한다",
		int(CA.get("strikes", 0)) > 0 and int(WA.get("blasts", 0)) > 0,
		"까마귀 %d타 · 돌풍 %d회 · 밀어낸 거리 합 %.0f" % [int(CA.get("strikes", 0)), int(WA.get("blasts", 0)), float(WA.get("push_total", 0.0))])
	ok("실제 전투: 까마귀 개체가 상한을 넘어 늘어나지 않는다", (CA.birds as Array).size() <= 2, "%d마리" % (CA.birds as Array).size())
	ok("실제 전투: 잔바람 장판이 상한 안에서 유지된다(재귀 증식 없음)",
		zone_count(a, "windgust") <= int(wep(a, "wind").stats.gustMax), "%d개" % zone_count(a, "windgust"))
	var stuck := []
	for e in a.alive_enemies():
		for ob in a.obstacles:
			if PGeom.dist(e.x, e.y, float(ob.x), float(ob.y)) < float(ob.r) + float(e.r) - 1.0:
				stuck.append("%s@%s" % [String(e.type), String(ob.id)])
	ok("실제 전투: 밀어내기로 적이 바위 안에 박히지 않는다", stuck.is_empty(),
		"%d마리 생존 · 박힌 적 %s" % [a.alive_enemies().size(), str(stuck)])
	var inside := true
	for e in a.alive_enemies():
		if e.x < -1.0 or e.x > a.arena_w + 1.0 or e.y < -1.0 or e.y > a.arena_h + 1.0:
			inside = false
	ok("실제 전투: 밀어내기로 적이 전장 밖으로 나가지 않는다", inside)
	var b := play([{ "id": "sword", "level": 2, "mods": [] }, { "id": "bell", "level": 2, "mods": ["reflect"] }, { "id": "echo", "level": 2, "mods": ["residual"] }], 20.0)
	var BB := bell_state(b)
	var EB := echo_state(b)
	ok("실제 전투(방울+분신 20초): 분신이 주무기 공격 수를 넘겨 생기지 않는다",
		int(EB.get("spawned", 0)) > 0 and int(EB.get("spawned", 0)) <= int(wep(b, "sword").count),
		"분신 %d개 · 주무기 발사 %d회 · 분신 타격 %d회 · 피해 %.1f" % [int(EB.get("spawned", 0)), int(wep(b, "sword").count), int(EB.get("strikes", 0)), float(EB.get("damage", 0.0))])
	ok("실제 전투: 남아 있는 분신이 동시 상한을 넘지 않는다",
		(EB.clones as Array).size() <= int(wep(b, "echo").stats.maxClones), "%d개" % (EB.clones as Array).size())
	ok("실제 전투: 방울 저장이 상한과 0 사이에 있다",
		int(BB.get("charges", -1)) >= 0 and int(BB.get("charges", 99)) <= PSupportA.bell_max(b, wep(b, "bell")),
		"방울 %d/%d · 차단 %d회" % [int(BB.get("charges", -1)), PSupportA.bell_max(b, wep(b, "bell")), int(BB.get("blocked", 0))])
