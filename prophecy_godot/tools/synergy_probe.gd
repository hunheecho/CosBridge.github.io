extends SceneTree
## 지금 있는 시너지 검수(화면 없음):
##   godot --headless --path prophecy_godot -s tools/synergy_probe.gd
## 결과: docs/sim/SYNERGY_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 있는가
## ---------
## "설명상 연결되는 효과"가 **실제로 함께 작동하는지**만 본다. 전수 시뮬레이션이 아니다.
## 검사(tests/)는 규칙 함수를 직접 불러 조건을 고정하므로 "실제 전투 경로에서 한 번도 안 터져도" 통과할 수 있다.
## 여기서는 되도록 **진짜 발사 경로**(PWeapons.fire · PSupport.update · st.step)로 몰아넣고 지표를 읽는다.
##
## 허용해야 할 연쇄와 막아야 할 오류를 구분한다
## -------------------------------------------
## 다른 적이 실제로 죽어 다음 처치 효과를 일으키는 것은 **정상이고 재미의 핵심**이다(불꽃 파열이 그 기준점).
## 막을 것은 네 가지뿐이다 — 같은 적의 사망 중복 정산 · 감전의 자기 호출 · 반사의 자기 호출 · 분신의 무한 복제.
## 그래서 이 도구는 "연쇄가 얼마나 크게 이어지는가"(불꽃 파열·독 전염)와
## "자기 호출이 없는가"(감전·반사·분신)를 **따로** 잰다.
##
## 부분 실행 축: sec(절 번호)
##   PROPHECY_SUBSET="sec=1,4"

const STEP := 1.0 / 120.0

var sub := PSubset.new()
var out_rows := {}      # 절 번호 → 표 문자열 배열
var json_rows := {}
var path_dmg := 0.0   # 직전 경로가 실제로 낸 피해(경로가 돌았는지 구분용)

# ---------- 공통 시험실 ----------
## 적이 저절로 나오지 않고 장애물도 없는 빈 전장.
## ids = [[무기 id, 레벨, [개조...]], ...] — 주무기·보조를 섞어 넣는다(성장 상한은 여기서 보지 않는다.
## 상한을 지키는 실제 빌드는 tools/build_probe.gd가 성장 규칙으로 만든다).
func lab(ids: Array, seed_v: int = 1, commons: Dictionary = {}) -> CombatState:
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = []
	for row in ids:
		g.weapons.append({ "id": String(row[0]), "level": int(row[1]), "mods": (row[2] as Array).duplicate() })
	for k in commons:
		(g.commons as Dictionary)[String(k)] = int(commons[k])
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = []
	return st

## 적을 움직이지 않고 무기·보조만 진행한다(기하를 고정해 두고 규칙 경로만 본다).
func tick(st: CombatState, dt: float) -> void:
	var keep := []
	for d in st.delayed:
		d.t = float(d.t) - dt
		if float(d.t) <= 0.0:
			(d.fn as Callable).call()
		else:
			keep.append(d)
	st.delayed = keep
	PSupport.update(st, dt)
	st.update_projectiles(dt)   # 개조가 만든 검기·창날·화살이 실제로 날아가야 한다

## 장판(불길·냉기 바닥)까지 함께 굴린다. 장판 틱은 CombatState가 맡는다
func tick_zone(st: CombatState, dt: float) -> void:
	tick(st, dt)
	st.update_zones(dt)

func run_for(st: CombatState, sec: float) -> void:
	for i in int(round(sec / STEP)):
		tick(st, STEP)

func wep(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w
	return {}

func put(st: CombatState, type: String, x: float, y: float) -> Dictionary:
	return st.spawn_enemy(type, x, y)

## 죽지 않는 표적(경로 검사용). 체력을 크게 두어 한 번의 타격으로 사라지지 않게 한다
func dummy(st: CombatState, x: float, y: float, hp: float = 100000.0) -> Dictionary:
	var e: Dictionary = put(st, "wolf", x, y)
	e.hp = hp
	e.hp_max = hp
	return e

func row(sec: int, cells: Array) -> void:
	if not out_rows.has(sec):
		out_rows[sec] = []
	(out_rows[sec] as Array).append(cells)

func yn(v: bool) -> String:
	return "O" if v else "X"

func verdict(expect: bool, actual: bool) -> String:
	return "일치" if expect == actual else "**어긋남**"

# ---------- 1. 감전 후속의 경로별 발동 ----------
## 자격표(data/supports.json eligibility.shock_bonus)는 다음을 말한다:
##   발동함  — 주무기 직접 · 주무기 개조 추가 · 보조 직접 · 분신 모방
##   발동 안 함 — 장판 틱 · 독 · 반사 · 감전 후속 자신 · 지뢰/인형 폭발 · 역병 파열
## 여기서는 **자격표가 그렇게 대답하는가**와 **실제 전투 경로에서 그렇게 도는가**를 따로 잰다.
func sec1() -> void:
	# (1) 자격표 자체
	for c in ["main_direct", "main_extra", "support_direct", "echo_direct",
			"zone_tick", "dot", "reflect", "shock_bonus", "plague_burst", "mine_blast", "doll_blast"]:
		var allow := PSupport.eligible("shock_bonus", String(c))
		row(1, ["자격표", String(c), "-", yn(allow), "-", "-"])

	# (2) 실제 경로. 표적에 감전을 직접 걸고(fire_chain의 zap과 같은 값) 그 경로로 때린다.
	# **경로가 실제로 일어났는지**(그 창에서 표적이 피해를 받았는지)를 함께 적는다 —
	# 발동 0이 "막혔다"인지 "경로 자체가 안 돌았다"인지 구분하기 위해서다.
	var cases := [
		# [이름, 기대 발동, 준비 함수]
		["주무기 직접(검 기본)", true, "sword_base"],
		["주무기 개조 추가(검 잔류 검흔)", true, "sword_scar"],
		["주무기 개조 추가(검 교차 검격)", true, "sword_cross"],
		["주무기 개조 추가(망치 여진)", true, "hammer_after"],
		["주무기 개조 추가(창 귀환 검기)", true, "spear_returning"],
		["주무기 개조 추가(검 날아가는 검광)", true, "sword_crescent"],
		["보조 직접(바람 정령 돌풍)", true, "wind_blast"],
		["보조 직접(회전 칼날 접촉)", true, "blades_orbit"],
		["분신 모방(잔영 분신)", true, "echo_copy"],
		["장판 틱(불씨 정령 불길)", false, "ember_zone"],
		["독(역병 나비)", false, "plague_dot"],
		["반사(가시 갑각 반격)", false, "thorns_reflect"],
		["지뢰 폭발(룬 지뢰)", false, "mine_blast"],
		["역병 파열", false, "plague_burst"],
		["인형 폭발(폭죽 인형)", false, "doll_blast"],
	]
	for c in cases:
		path_dmg = 0.0
		var got: int = call("_shock_" + String(c[2]))
		var ran: bool = path_dmg > 0.0
		row(1, ["실제 경로", String(c[0]), yn(bool(c[1])), yn(got > 0),
			"%s(%s)" % [yn(ran), str(snappedf(path_dmg, 0.1))],
			("판단 불가 — 경로 미발생" if not ran else verdict(bool(c[1]), got > 0))])
		json_rows["shock:" + String(c[2])] = { "procs": got, "path_dmg": snappedf(path_dmg, 0.1) }

## 감전을 건 표적 하나가 있는 시험실. weapons에 orb를 넣어 두어야 후속이 터진다.
## 표적은 **플레이어 기준**으로 세운다(전장 절대 좌표로 두면 사거리 밖에 서서 조용히 0이 된다)
func shock_lab(ids: Array, ahead: float = 60.0) -> Array:
	var full: Array = [["orb", 1, []]]
	for i in ids:
		full.append(i)
	var st: CombatState = lab(full)
	var e: Dictionary = dummy(st, st.player.x + ahead, st.player.y)
	e.conduct = float(PCatalog.support_tuning("orb").get("shockDur", 2.0))
	return [st, e]

func procs(st: CombatState) -> int:
	return int(PSupport.metered(st, "orb", "shock_procs"))

## 그 창에서 그 경로가 노린 대상이 실제로 피해를 받았는가(경로가 돌았는가)
func mark(e: Dictionary) -> float:
	return float(e.hp)

func _shock_sword_base() -> int:
	var lb: Array = shock_lab([["sword", 1, []]], 60.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	var h0: float = mark(e)
	PWeapons.fire(st, wep(st, "sword"), e, false)
	path_dmg = h0 - mark(e)
	return procs(st)

func _shock_sword_scar() -> int:
	var lb: Array = shock_lab([["sword", 1, ["scar"]]], 60.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "sword"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0            # 기본 타격이 이미 썼으므로 다시 걸고 잔류 검흔만 본다
	var h0: float = mark(e)
	run_for(st, 0.7)           # 0.5초 뒤 잔류 검흔
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_sword_cross() -> int:
	# 기본 검격과 교차 검격이 같은 호출 안에 있으므로 **앞뒤로 갈라 세운다** —
	# 기본 검격은 앞의 표적을, 교차 검격은 뒤(반대 방향)의 감전된 적을 친다
	var lb: Array = shock_lab([["sword", 1, ["cross"]]], -60.0)
	var st: CombatState = lb[0]
	var back: Dictionary = lb[1]
	var front: Dictionary = dummy(st, st.player.x + 60.0, st.player.y)
	var w: Dictionary = wep(st, "sword")
	w.count = 3                # 교차 검격은 3의 배수 번째 검격에서만 돈다
	var h0: float = mark(back)
	PWeapons.fire(st, w, front, false)
	path_dmg = h0 - mark(back)
	return procs(st)

func _shock_hammer_after() -> int:
	var lb: Array = shock_lab([["hammer", 1, ["aftershock"]]], 60.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "hammer"), e, false)
	run_for(st, 0.5)           # 준비 0.45초 뒤 내려찍기
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	run_for(st, 0.8)           # 0.6초 뒤 여진
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_spear_returning() -> int:
	# 귀환 검기: 끝까지 간 검기가 0.35초 뒤 같은 선을 되돌아오며 다시 친다(주무기 개조가 만든 추가 타격)
	var lb: Array = shock_lab([["spear", 1, ["returning"]]], 120.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "spear"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	run_for(st, 0.6)
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_sword_crescent() -> int:
	# 날아가는 검광: 검격 끝에서 초승달 검기가 조금 더 뻗는다(관통 투사체)
	var lb: Array = shock_lab([["sword", 1, ["crescent"]]], 40.0)
	var st: CombatState = lb[0]
	var far: Dictionary = dummy(st, st.player.x + 120.0, st.player.y)
	var st_e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "sword"), st_e, false)
	var before: int = procs(st)
	far.conduct = 2.0
	var h0: float = mark(far)
	run_for(st, 0.5)
	path_dmg = h0 - mark(far)
	return procs(st) - before

func _shock_wind_blast() -> int:
	var lb: Array = shock_lab([["wind", 1, []]], 90.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	var h0: float = mark(e)
	PWeapons.fire(st, wep(st, "wind"), e, false)
	path_dmg = h0 - mark(e)
	return procs(st)

func _shock_blades_orbit() -> int:
	var lb: Array = shock_lab([["blades", 1, []]], 40.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	e.conduct = 2.0
	var h0: float = mark(e)
	for i in int(3.0 / STEP):
		PWeapons.update(st, STEP)
		if procs(st) > 0:
			break
	path_dmg = h0 - mark(e)
	return procs(st)

func _shock_echo_copy() -> int:
	# 분신은 공격 방향 반대쪽 72에 생긴다. 분신 자리에서 사거리(95) 안에 들어오도록 적을 가까이 세운다
	var lb: Array = shock_lab([["sword", 1, []], ["echo", 1, []]], 20.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	var w: Dictionary = wep(st, "sword")
	w.count = 1
	PWeapons.fire(st, w, e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	run_for(st, 1.2)
	path_dmg = h0 - mark(e)
	var S: Dictionary = st.support.get("echo", {})
	json_rows["echo_copy_strikes"] = int(S.get("strikes", 0))
	return procs(st) - before

func _shock_ember_zone() -> int:
	var lb: Array = shock_lab([["ember", 1, []]], 120.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "ember"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	for i in int(3.0 / STEP):
		tick_zone(st, STEP)
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_plague_dot() -> int:
	var lb: Array = shock_lab([["plague", 1, []]], 120.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "plague"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	run_for(st, 3.0)
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_thorns_reflect() -> int:
	var lb: Array = shock_lab([["thorns", 1, []]], 40.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	PSupport.after_player_damage(st, 10.0, "wolf:bite", e)
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_mine_blast() -> int:
	var lb: Array = shock_lab([["mine", 1, []]], 30.0)  # 지뢰는 플레이어 발밑(40 안)에 놓인다
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	e.conduct = 2.0
	PWeapons.fire_mine(st, wep(st, "mine"))
	var before: int = procs(st)
	var h0: float = mark(e)
	for i in int(2.0 / STEP):
		PWeapons.update_mines(st, STEP)
		if st.mines.is_empty():
			break
	path_dmg = h0 - mark(e)
	return procs(st) - before

func _shock_plague_burst() -> int:
	var lb: Array = shock_lab([["plague", 1, ["burst"]]], 80.0)
	var st: CombatState = lb[0]
	var near: Dictionary = lb[1]
	var victim: Dictionary = put(st, "wolf", float(near.x) - 40.0, float(near.y))
	near.conduct = 2.0
	PSupportB._infect(st, victim, 0, -1.0)
	var before: int = procs(st)
	var h0: float = mark(near)
	st.kill_enemy(victim, {})
	path_dmg = h0 - mark(near)
	return procs(st) - before

func _shock_doll_blast() -> int:
	var lb: Array = shock_lab([["doll", 1, ["firework"]]], 100.0)
	var st: CombatState = lb[0]
	var e: Dictionary = lb[1]
	PWeapons.fire(st, wep(st, "doll"), e, false)
	var before: int = procs(st)
	e.conduct = 2.0
	var h0: float = mark(e)
	run_for(st, 20.0)
	path_dmg = h0 - mark(e)
	return procs(st) - before


# ---------- 2. 축전(개조) ----------
## 감전 후속을 chargeNeed번 쌓으면 방전. 방전 자체는 감전을 다시 걸지 않는다(자기 호출 금지).
func sec2() -> void:
	var T: Dictionary = PCatalog.support_tuning("orb")
	var need: int = int(T.get("chargeNeed", 3))
	var st: CombatState = lab([["orb", 1, ["conduct"]], ["sword", 1, []]])
	var e: Dictionary = dummy(st, st.player.x + 60.0, st.player.y)
	var w: Dictionary = wep(st, "sword")
	var fired := 0
	var dis := 0
	for i in need + 1:
		e.conduct = 2.0
		w.count = int(w.count) + 1
		PWeapons.fire(st, w, e, false)
		fired = int(PSupport.metered(st, "orb", "shock_procs"))
		dis = int(PSupport.metered(st, "orb", "discharges"))
		row(2, ["감전 후속 %d회째" % (i + 1), str(fired), str(dis), str(int(st.support_charge))])
	row(2, ["방전 뒤 표적의 감전이 다시 걸렸는가", "-", "-", yn(float(e.conduct) > 0.0)])
	# 축전이 없으면 방전이 아예 없어야 한다
	var st2: CombatState = lab([["orb", 1, []], ["sword", 1, []]])
	var e2: Dictionary = dummy(st2, st2.player.x + 60.0, st2.player.y)
	var w2: Dictionary = wep(st2, "sword")
	for i in need + 1:
		e2.conduct = 2.0
		w2.count = int(w2.count) + 1
		PWeapons.fire(st2, w2, e2, false)
	row(2, ["축전 없음 — 방전 횟수", str(int(PSupport.metered(st2, "orb", "shock_procs"))),
		str(int(PSupport.metered(st2, "orb", "discharges"))), "-"])
	json_rows["conduct_discharges"] = dis

# ---------- 3. 분신 모방의 자격과 자기 복제 금지 ----------
func sec3() -> void:
	var st: CombatState = lab([["sword", 1, []], ["echo", 1, []]])
	var e: Dictionary = dummy(st, st.player.x + 60.0, st.player.y)
	var w: Dictionary = wep(st, "sword")
	# 주무기 기본 타격 → 분신 1개
	w.count = 1
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": true } }, 1.0)
	var S: Dictionary = st.support.get("echo", {})
	row(3, ["주무기 기본 타격 뒤 분신 수", "1", str(int(S.get("spawned", 0))), verdict(true, int(S.get("spawned", 0)) == 1)])
	# 같은 공격(같은 count)의 두 번째 적중은 분신을 더 만들지 않는다
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": true } }, 1.0)
	row(3, ["같은 공격의 두 번째 적중 뒤 분신 수", "1", str(int(S.get("spawned", 0))), verdict(true, int(S.get("spawned", 0)) == 1)])
	# 주무기 개조 추가 타격은 복제하지 않는다
	w.count = 2
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": false, "mod": "scar" }, "cause": "main_extra" }, 1.0)
	row(3, ["주무기 개조 추가 타격 뒤 분신 수", "1", str(int(S.get("spawned", 0))), verdict(true, int(S.get("spawned", 0)) == 1)])
	# 분신 자신의 타격은 분신을 만들지 않는다
	w.count = 3
	PSupportA.on_enemy_hit(st, e, { "src": { "weapon_id": "sword", "direct": true, "echo": true }, "cause": "echo_direct" }, 1.0)
	row(3, ["분신 타격 뒤 분신 수", "1", str(int(S.get("spawned", 0))), verdict(true, int(S.get("spawned", 0)) == 1)])
	# 실제 프레임 경로에서 분신이 무한히 늘지 않는가
	var st2: CombatState = lab([["sword", 3, []], ["echo", 3, []]])
	for i in 6:
		dummy(st2, st2.player.x + 30.0 + float(i) * 20.0, st2.player.y, 4000.0)
	for i in int(20.0 / STEP):
		PWeapons.update(st2, STEP)
	var S2: Dictionary = st2.support.get("echo", {})
	var cap: int = int(PSupport.stats_of(st2, "echo").get("maxClones", 6))
	row(3, ["20초 뒤 동시 분신 수 ≤ 상한 %d" % cap, "≤%d" % cap, str((S2.get("clones", []) as Array).size()),
		verdict(true, (S2.get("clones", []) as Array).size() <= cap)])
	row(3, ["20초 분신 생성 수 ≤ 주무기 발사 수", str(int(wep(st2, "sword").count)), str(int(S2.get("spawned", 0))),
		verdict(true, int(S2.get("spawned", 0)) <= int(wep(st2, "sword").count))])
	json_rows["echo_spawned"] = int(S2.get("spawned", 0))
	json_rows["echo_strikes"] = int(S2.get("strikes", 0))

# ---------- 4. 독 전염 — 세대 상한 2가 연쇄를 얼마나 줄이는가 ----------
## data/supports.json은 읽기만 한다. 비교를 위해 **메모리에 올라온 자격표 사전**의 gen_max만 잠시 바꾼다
## (파일은 건드리지 않는다). 끝나면 원래 값으로 되돌린다.
func spread_run(gen_max: int, seed_v: int, mods: Array = []) -> Dictionary:
	var E: Dictionary = PCatalog.eligibility().get("effects", {})
	var eff: Dictionary = E.get("plague_spread", {})
	var saved: int = int(eff.get("gen_max", 2))
	eff["gen_max"] = gen_max
	var st: CombatState = lab([["plague", 3, mods]], seed_v)
	# 밀집 무리: 전염 반경(110) 안에 서로 겹치도록 4×4로 세운다
	var mob := []
	for iy in 4:
		for ix in 4:
			var e: Dictionary = put(st, "wolf", 380.0 + float(ix) * 70.0, 220.0 + float(iy) * 70.0)
			e.hp = 1.0
			e.hp_max = 1.0
			mob.append(e)
	# 가운데 하나에 나비가 직접 독을 건다(세대 0)
	PSupportB._infect(st, mob[5], 0, -1.0)
	run_for(st, 0.5)
	# 감염된 그 적만 처치한다. 나머지는 전염과 독으로만 죽는다(연쇄 크기를 재는 것이 목적)
	st.kill_enemy(mob[5], {})
	run_for(st, 12.0)
	var P: Dictionary = st.support.get("plague", {})
	var infected := 0
	var dead := 0
	for e in mob:
		if bool(e.dead):
			dead += 1
		if not (e.get("plague", {}) as Dictionary).is_empty():
			infected += 1
	eff["gen_max"] = saved
	return { "gen_max": gen_max, "mods": mods, "spreads": int(P.get("spreads", 0)),
		"blocked": int(P.get("spread_blocked", 0)), "bursts": int(P.get("bursts", 0)),
		"dead": dead, "still_infected": infected,
		"dot_dmg": snappedf(float((P.get("dmg", {}) as Dictionary).get("poison", 0.0)) + float((P.get("dmg", {}) as Dictionary).get("spread", 0.0)), 0.1) }

func sec4() -> void:
	for gm in [2, 99]:
		var r: Dictionary = spread_run(gm, 1)
		row(4, ["세대 상한 %s" % ("2(지금)" if gm == 2 else "무제한(비교용)"), str(int(r.spreads)), str(int(r.blocked)),
			"%d/16" % int(r.dead), str(float(r.dot_dmg))])
		json_rows["spread_gen%d" % gm] = r
	# 역병 파열을 함께 골랐을 때 전염이 얼마나 남는가(둘이 같은 자원을 먹는지)
	var rb: Dictionary = spread_run(2, 1, ["burst"])
	row(4, ["세대 상한 2 + 역병 파열", str(int(rb.spreads)), str(int(rb.blocked)),
		"%d/16" % int(rb.dead), str(float(rb.dot_dmg))])
	json_rows["spread_gen2_burst"] = rb
	# 역병 파열: 같은 죽음으로 두 번 정산되지 않는가
	var st: CombatState = lab([["plague", 1, ["burst"]]])
	var victim: Dictionary = put(st, "wolf", 460.0, 300.0)
	var near: Dictionary = dummy(st, 500.0, 300.0)
	PSupportB._infect(st, victim, 0, -1.0)
	run_for(st, 1.0)
	var hp0: float = float(near.hp)
	st.kill_enemy(victim, {})
	var hp1: float = float(near.hp)
	PSupport.on_enemy_death(st, victim, {})   # 같은 개체로 다시 부른다
	var hp2: float = float(near.hp)
	var P: Dictionary = st.support.get("plague", {})
	row(4, ["역병 파열 — 첫 사망 정산 피해", "-", "-", str(snappedf(hp0 - hp1, 0.1)), "-"])
	row(4, ["같은 죽음으로 다시 부를 때 추가 피해", "0", "-", str(snappedf(hp1 - hp2, 0.1)), verdict(true, is_zero_approx(hp1 - hp2))])
	row(4, ["파열 횟수(같은 죽음)", "1", "-", str(int(P.get("bursts", 0))), verdict(true, int(P.get("bursts", 0)) == 1)])
	# 파열이 전염 시간을 통째로 넘기지 않는가
	json_rows["burst_double"] = snappedf(hp1 - hp2, 0.1)

# ---------- 5. 불꽃 파열 — 만족감의 기준점을 수치로 ----------
## 사용자가 유일하게 만족감을 느꼈다고 한 효과. 다른 연쇄를 판단할 기준이므로 크기를 먼저 재 둔다.
## 불길 위에서 적을 처치하면 반지름 80 폭발 → 그 폭발이 다른 적을 죽이면 그 적도 다시 터진다(정상 연쇄).
func sec5() -> void:
	for use_flare in [false, true]:
		var cm := {}
		if use_flare:
			cm = { "ember": 1, "flare": 1 }
		else:
			cm = { "ember": 1 }
		var st: CombatState = lab([["ember", 3, []], ["sword", 3, []]], 1, cm)
		var mob := []
		for i in 10:
			var e: Dictionary = put(st, "wolf", 420.0 + float(i % 5) * 44.0, 260.0 + float(i / 5) * 44.0)
			e.hp = 12.0
			e.hp_max = 12.0
			mob.append(e)
		# 불길을 깔고 나서 하나만 직접 처치한다. 나머지는 불길·연쇄로만 죽는다
		var z: Dictionary = st.add_zone("fire", 508.0, 282.0, 150.0, 12.0, 6.0)
		z.weapon = wep(st, "ember")
		run_for(st, 0.6)
		var killed_before: int = int(st.stats.kills)
		st.kill_enemy(mob[0], {})
		var chain_kills: int = int(st.stats.kills) - killed_before - 1
		run_for(st, 0.2)
		row(5, ["불꽃 파열 %s" % ("있음" if use_flare else "없음"), str(int(st.stats.kills)),
			str(chain_kills), str(snappedf(float(st.metrics.dmg.get("common:flare", 0.0)), 0.1))])
		json_rows["flare_%s" % ("on" if use_flare else "off")] = { "kills": int(st.stats.kills), "chain": chain_kills }

# ---------- 6. 도깨비 인형 유인 ----------
## 적이 실제로 인형을 때리고 인형이 대신 맞는가. 인형 없음/있음을 같은 시드·같은 편성으로 비교한다.
func doll_run(with_doll: bool, seed_v: int) -> Dictionary:
	var ids := [["sword", 3, []]]
	if with_doll:
		ids.append(["doll", 3, []])
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = []
	for r in ids:
		g.weapons.append({ "id": String(r[0]), "level": int(r[1]), "mods": (r[2] as Array).duplicate() })
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [[{ "type": "wolf", "n": 8 }]], "objective": "clear", "region_id": "den" })
	var bot := PSkillBot.new("novice", seed_v)
	var i := 0
	while i < int(60.0 / STEP) and st.status == "running":
		st.step(bot.step_input(st), STEP)
		i += 1
	var D: Dictionary = st.support.get("doll", {})
	return { "taken": snappedf(float(st.stats.damage_taken), 0.1), "kills": int(st.stats.kills),
		"status": String(st.status), "sec": snappedf(st.t, 0.01),
		"lured": int(D.get("lured", 0)), "absorbed": int(D.get("absorbed", 0)),
		"absorbed_dmg": snappedf(float(D.get("absorbed_dmg", 0.0)), 0.1), "placed": int(D.get("placed", 0)) }

func sec6() -> void:
	for sd in [1, 2, 3]:
		var a: Dictionary = doll_run(false, sd)
		var d: Dictionary = doll_run(true, sd)
		row(6, ["시드 %d" % sd, "%s / %s" % [String(a.status), String(d.status)],
			"%s / %s" % [str(float(a.taken)), str(float(d.taken))],
			str(int(d.placed)), str(int(d.lured)), "%d회 %s" % [int(d.absorbed), str(float(d.absorbed_dmg))],
			"%s / %s" % [str(float(a.sec)), str(float(d.sec))]])
		json_rows["doll_seed%d" % sd] = { "off": a, "on": d }

# ---------- 7. 가시 반격 — 반사가 반사를 부르지 않는다 ----------
func sec7() -> void:
	var st: CombatState = lab([["thorns", 3, []]])
	var e: Dictionary = dummy(st, st.player.x + 40.0, st.player.y)
	PSupport.after_player_damage(st, 10.0, "wolf:bite", e)
	var r1: int = int((st.support.get("thorns", {}) as Dictionary).get("reflects", 0))
	# 반사 경로로 다시 불러도 반격이 늘지 않아야 한다
	PSupport.after_player_damage(st, 10.0, "reflect", e)
	var r2: int = int((st.support.get("thorns", {}) as Dictionary).get("reflects", 0))
	row(7, ["근접 피격 뒤 반격 횟수", "1", str(r1), verdict(true, r1 == 1)])
	row(7, ["반사 경로로 다시 불렀을 때 늘어난 반격", "0", str(r2 - r1), verdict(true, r2 == r1)])
	# 투사체·장판에는 반격하지 않는다
	var st2: CombatState = lab([["thorns", 3, []]])
	var e2: Dictionary = dummy(st2, st2.player.x + 300.0, st2.player.y)
	PSupport.after_player_damage(st2, 10.0, "arrow", e2)
	PSupport.after_player_damage(st2, 10.0, "zone", null)
	row(7, ["투사체·장판 피격 뒤 반격 횟수", "0",
		str(int((st2.support.get("thorns", {}) as Dictionary).get("reflects", 0))),
		verdict(true, int((st2.support.get("thorns", {}) as Dictionary).get("reflects", 0)) == 0)])
	# 피해 0(막힌 공격)에는 반격하지 않는다
	var st3: CombatState = lab([["thorns", 3, []]])
	var e3: Dictionary = dummy(st3, st3.player.x + 40.0, st3.player.y)
	PSupport.after_player_damage(st3, 0.0, "wolf:bite", e3)
	row(7, ["막힌 공격(피해 0) 뒤 반격 횟수", "0",
		str(int((st3.support.get("thorns", {}) as Dictionary).get("reflects", 0))),
		verdict(true, int((st3.support.get("thorns", {}) as Dictionary).get("reflects", 0)) == 0)])
	json_rows["thorns_self"] = r2 - r1

# ---------- 8. 무기 공명이 방어 보조를 골랐을 때 후보로 나오는가 ----------
func sec8() -> void:
	var sets := [
		["검 + 번개 구체 + 불씨 정령(공격 3)", ["sword", "orb", "ember"], true],
		["검 + 수호 방울 + 가시 갑각(공격 1)", ["sword", "bell", "thorns"], false],
		["검 + 도깨비 인형 + 가시 갑각(공격 1)", ["sword", "doll", "thorns"], false],
		["검 + 잔영 분신 + 수호 방울(공격 2)", ["sword", "echo", "bell"], false],
		["검 + 추격 까마귀 + 역병 나비(공격 3)", ["sword", "crow", "plague"], true],
	]
	for s in sets:
		var g: Dictionary = PGrowth.new_growth(String((s[1] as Array)[0]))
		g.weapons = []
		for wid in (s[1] as Array):
			g.weapons.append({ "id": String(wid), "level": 1, "mods": [] })
		var applies: bool = PGrowth.boss_reward_applies(g, "resonance")
		row(8, [String(s[0]), str(PGrowth.attack_source_count(g)), yn(bool(s[2])), yn(applies), verdict(bool(s[2]), applies)])
		json_rows["resonance:" + String(s[0])] = applies

# ---------- 보고서 ----------
func table(sec: int, head: Array, align: Array) -> String:
	if not out_rows.has(sec):
		return "(이 절은 이번 실행에서 돌리지 않았다)\n"
	var md := "| " + " | ".join(head) + " |\n|"
	for a in align:
		md += String(a) + "|"
	md += "\n"
	for r in out_rows[sec]:
		var cells := []
		for c in r:
			cells.append(str(c))
		md += "| " + " | ".join(cells) + " |\n"
	return md

func _init() -> void:
	var secs: Array = sub.pick("sec", [1, 2, 3, 4, 5, 6, 7, 8])
	for s in secs:
		printerr("sec ", s)
		call("sec%d" % int(s))
	print("SYNERGY_PROBE_JSON " + JSON.stringify(json_rows))

	var md := "# 시너지 검수 측정\n\n"
	md += "생성: `tools/synergy_probe.gd` (%s, Godot %s).\n" % [OS.get_name(), Engine.get_version_info().string]
	md += "**설명상 연결되는 효과가 실제로 함께 작동하는지**만 본다. 전수 시뮬레이션이 아니다.\n"
	md += "모든 수치는 시험값이며 사람이 승인한 밸런스가 아니다.\n\n"
	md += sub.describe("시너지 검수") + "\n"

	md += "## 1. 감전 후속의 경로별 발동\n\n"
	md += "자격표(`data/supports.json` `eligibility.shock_bonus`)가 무엇이라고 대답하는지와,\n"
	md += "**실제 전투 경로에서 그렇게 도는지**를 따로 잰다. 두 줄이 어긋나면 자격표가 아니라 구현이 문제다.\n\n"
	md += table(1, ["구분", "경로", "기대", "실제 발동", "경로가 실제로 돌았나(피해)", "판정"], ["---", "---", ":---:", ":---:", ":---:", ":---:"])
	md += "\n표적에는 `fire_chain`의 연쇄가 거는 것과 같은 값(`shockDur`)으로 감전을 직접 걸어 두었다.\n\n"

	md += "## 2. 축전(번개 구체 개조)\n\n"
	md += table(2, ["단계", "감전 후속 누계", "방전 누계", "쌓인 축전"], ["---", "---:", "---:", "---:"])
	md += "\n"

	md += "## 3. 잔영 분신 — 모방 자격과 무한 복제 금지\n\n"
	md += table(3, ["항목", "기대", "실제", "판정"], ["---", ":---:", ":---:", ":---:"])
	md += "\n"

	md += "## 4. 독 전염 — 세대 상한 2가 연쇄를 얼마나 줄이는가\n\n"
	md += "늑대 16마리를 전염 반경 안에 4×4로 세우고 **가운데 한 마리만** 감염시킨 뒤 그 한 마리를 처치한다.\n"
	md += "나머지는 전염과 독으로만 죽는다. 비교를 위해 **메모리에 올라온 자격표의 `gen_max`만 잠시** 99로 바꿨다\n"
	md += "(`data/supports.json` 파일은 읽기만 했다).\n\n"
	md += table(4, ["조건", "전염 횟수", "세대 상한에 막힌 죽음", "죽은 수", "독 피해"], ["---", "---:", "---:", "---:", "---:"])
	md += "\n"

	md += "## 5. 불꽃 파열 — 기준점\n\n"
	md += "사용자가 유일하게 만족감을 느꼈다고 한 효과다. 다른 연쇄를 판단할 자가 되므로 크기를 먼저 잰다.\n"
	md += "불길 위 늑대 10마리 중 **한 마리만 직접 처치**하고 나머지가 연쇄로 죽는지 본다.\n\n"
	md += table(5, ["조건", "총 처치", "직접 처치를 뺀 연쇄 처치", "파열 피해"], ["---", "---:", "---:", "---:"])
	md += "\n"

	md += "## 6. 도깨비 인형 유인\n\n"
	md += "같은 시드·같은 편성(늑대 8), 초보 봇 60초. 인형 없음/있음을 나란히 둔다.\n\n"
	md += table(6, ["시드", "결과(없음/있음)", "받은 피해(없음/있음)", "세운 인형", "유인한 적", "대신 받음", "걸린 시간(없음/있음)"],
		["---", "---", "---", "---:", "---:", "---", "---"])
	md += "\n"

	md += "## 7. 가시 반격 — 반사가 반사를 부르지 않는다\n\n"
	md += table(7, ["항목", "기대", "실제", "판정"], ["---", ":---:", ":---:", ":---:"])
	md += "\n"

	md += "## 8. 무기 공명 후보 자격\n\n"
	md += table(8, ["편성", "공격 출처 수", "기대", "후보로 나옴", "판정"], ["---", "---:", ":---:", ":---:", ":---:"])
	md += "\n**정상 연쇄를 막지 않았다.** 이 표에서 막는 것은 네 가지뿐이다 —\n"
	md += "같은 적의 사망 중복 정산 · 감전의 자기 호출 · 반사의 자기 호출 · 분신의 무한 복제.\n"
	md += "다른 적이 실제로 죽어 다음 처치 효과를 일으키는 것(5절 불꽃 파열·4절 독 전염)은 그대로 둔다.\n"

	var f := FileAccess.open(sub.out_path("res://docs/sim/SYNERGY_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()
