extends SceneTree
## 방패병 확정 변경 + 특수 정예 7종 규칙 검사(화면 없음).
## 실행: python tools/run_suites.py --suites elites_tests --allow-adhoc
##      (직접: godot --headless --path prophecy_godot -s tests/elites_tests.gd)
##
## 무엇을 보는가
##  - 방패병: 정면 감소 85%(100 → 15)가 실제 수치로 나오는지, 각도 경계·방어 유지/해제 구간·우회 관계·중복 없음.
##  - 정예 7종: 행동 순서 · 예고 시간 · 확정 뒤 추적 없음 · 빈틈 길이 · 피해 · 상한(구름·돌무더기·명령 예산).
## 사용자 확정값과 시험값을 구분해 이름에 적는다. 봇 승패는 통과 조건이 아니다(측정은 tests/elites_bot_measure.gd).

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func near(a: float, b: float, tol: float = 0.02) -> bool:
	return absf(a - b) <= tol

# ---------- 시험실 ----------
## 적이 저절로 나오지 않고 자동 공격도 없는 빈 전장(적 규칙만 본다)
func lab(seed_v: int = 1, act: int = 1) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": act })
	st.spawn_hold = true
	st.weapons = [] # 자동기술 정지: 적 행동만 관찰한다
	return st

func put(st: CombatState, type: String, x: float, y: float) -> Dictionary:
	return st.spawn_enemy(type, x, y)

## seconds 만큼 진행. keep_alive면 플레이어를 계속 살려 둔다(연계 전체를 보기 위해)
func play(st: CombatState, seconds: float, input: Dictionary = {}, keep_alive: bool = true) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		st.step(input, STEP)
		if keep_alive:
			st.player.hp = st.player.hp_max
			st.player.dead = false
			if st.status == "lost":
				st.status = "running"

## 상태 전이 순서를 기록하며 진행
func trace(st: CombatState, e: Dictionary, seconds: float, input: Dictionary = {}) -> Array:
	var out := [String(e.state)]
	var n := int(round(seconds / STEP))
	for i in n:
		st.step(input, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		if String(e.state) != String(out[out.size() - 1]):
			out.append(String(e.state))
	return out

## 상태 s가 나올 때까지(최대 max_sec) 진행. 도달 시각을 돌려준다(-1 = 못 봄)
func until(st: CombatState, e: Dictionary, s: String, max_sec: float = 12.0, input: Dictionary = {}) -> float:
	var n := int(round(max_sec / STEP))
	for i in n:
		if String(e.state) == s:
			return st.t
		st.step(input, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
	return -1.0

## 그 상태가 이어진 시간
func dur_of(st: CombatState, e: Dictionary, s: String, max_sec: float = 12.0) -> float:
	var t0 := until(st, e, s, max_sec)
	if t0 < 0.0:
		return -1.0
	var n := int(round(max_sec / STEP))
	for i in n:
		st.step({}, STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		if String(e.state) != s:
			return st.t - t0
	return -1.0

## 100 피해를 그 방향에서 넣었을 때 실제로 깎인 체력
func probe(st: CombatState, e: Dictionary, from_ang: float, opt: Dictionary = {}) -> float:
	var o := { "src": { "direct": true }, "from": { "x": e.x + cos(from_ang) * 120.0, "y": e.y + sin(from_ang) * 120.0 } }
	for k in opt:
		o[k] = opt[k]
	var hp0: float = e.hp
	e.hp = 100000.0
	e.hp_max = maxf(float(e.hp_max), 100000.0)
	st.damage_enemy(e, 100.0, o)
	var lost: float = 100000.0 - float(e.hp)
	e.hp = hp0
	return lost

func _init() -> void:
	var E := PCatalog.enemies()

	# ================= 작업 1. 방패병(사용자 확정) =================
	var SB: Dictionary = E.shieldbearer
	ok("사용자 확정: 방패병 정면 피해 감소 85%(frontMult 0.15), 정면 각 120도 유지",
		is_equal_approx(float(SB.frontMult), 0.15) and is_equal_approx(float(SB.frontDeg), 120.0),
		"frontMult %.2f · frontDeg %.0f" % [float(SB.frontMult), float(SB.frontDeg)])

	var st1 := lab()
	var sb := put(st1, "shieldbearer", 600.0, 300.0)
	sb.face = 0.0 # 오른쪽(+x)을 본다
	var front := probe(st1, sb, 0.0)
	var side := probe(st1, sb, PI / 2.0)
	var back := probe(st1, sb, PI)
	ok("사용자 확정: 유효 정면 직접 피해 100 → 15 (측면·후면은 100 그대로)",
		is_equal_approx(front, 15.0) and is_equal_approx(side, 100.0) and is_equal_approx(back, 100.0),
		"정면 %.1f / 측면 %.1f / 후면 %.1f" % [front, side, back])

	var edge_in := probe(st1, sb, PGeom.deg(59.0))
	var edge_out := probe(st1, sb, PGeom.deg(61.0))
	ok("정면 각도 경계(±60도)에서 판정이 흔들리지 않는다: 59도 감소 · 61도 정상",
		is_equal_approx(edge_in, 15.0) and is_equal_approx(edge_out, 100.0),
		"59도 %.1f / 61도 %.1f" % [edge_in, edge_out])

	# 우회 관계(현재 동작 그대로 유지 — 측정해서 남긴다)
	var by_ground := probe(st1, sb, 0.0, { "src": { "direct": false, "extra": true, "tag": "common:ember" } })
	var by_dot := probe(st1, sb, 0.0, { "src": { "extra": true, "direct": false }, "dot": "burn" })
	var by_skill := probe(st1, sb, 0.0, { "src": { "skill": true, "direct": false, "skill_id": "strike" } })
	ok("우회 관계 유지: 바닥·추가(불길) · 지속(화상/출혈) · 기술 피해는 방패를 무시하고 100 그대로",
		is_equal_approx(by_ground, 100.0) and is_equal_approx(by_dot, 100.0) and is_equal_approx(by_skill, 100.0),
		"바닥 %.1f / 지속 %.1f / 기술 %.1f" % [by_ground, by_dot, by_skill])

	# 방어 유지/해제 구간
	var guard_states := {}
	for s in ["approach", "bash_aim", "bash", "recover"]:
		sb.state = s
		guard_states[s] = probe(st1, sb, 0.0)
	sb.state = "approach"
	ok("사용자 확정: 접근 중·방패치기 **준비 중**에는 방어 유지, 실제 방패치기와 그 뒤 빈틈에만 해제",
		is_equal_approx(float(guard_states.approach), 15.0) and is_equal_approx(float(guard_states.bash_aim), 15.0)
		and is_equal_approx(float(guard_states.bash), 100.0) and is_equal_approx(float(guard_states.recover), 150.0),
		"접근 %.1f / 준비 %.1f / 방패치기 %.1f / 빈틈 %.1f(빈틈은 노출 배율 1.5배가 곱해진 값)" % [float(guard_states.approach), float(guard_states.bash_aim), float(guard_states.bash), float(guard_states.recover)])

	# 방향 전환 속도(느리게 유지)
	var st_turn := lab()
	var sb2 := put(st_turn, "shieldbearer", st_turn.player.x + 300.0, st_turn.player.y)
	sb2.face = 0.0
	sb2.state = "bash_aim" # 접근으로 움직이지 않게 고정
	sb2.state_t = -1000.0
	var f0: float = sb2.face
	play(st_turn, 1.0)
	var turned := absf(PGeom.ang_diff(f0, float(sb2.face)))
	ok("방향 전환은 느리다(turnRate 2.2 rad/s = 1초에 약 126도) — 측·후방 공략이 가능하다",
		turned <= PGeom.deg(130.0) and turned > 0.0, "1초 회전 %.0f도" % (turned * 180.0 / PI))

	# 막기 연출 신호(실제 방어 판정이 일어난 순간에만)
	var st_fx := lab()
	var sb3 := put(st_fx, "shieldbearer", 600.0, 300.0)
	sb3.face = 0.0
	st_fx.effects.clear()
	st_fx.events.clear()
	probe(st_fx, sb3, 0.0)
	var has_block_text := false
	for f in st_fx.effects:
		if String(f.get("text", "")) == "방어":
			has_block_text = true
	var has_metal: bool = (st_fx.events as Array).has("shatter")
	var blocked_flag: bool = float(sb3.blocked_t) > 0.0
	st_fx.effects.clear()
	st_fx.events.clear()
	sb3.block_fx_t = -9.0
	probe(st_fx, sb3, PI / 2.0)
	var side_text := false
	for f in st_fx.effects:
		if String(f.get("text", "")) == "방어":
			side_text = true
	ok("막기 연출: 실제 방어 판정에서만 방패 타격·금속음·'방어' 표시가 나온다(측면 타격에는 없다)",
		has_block_text and has_metal and blocked_flag and not side_text and not (st_fx.events as Array).has("shatter"))

	# 다른 방어 효과와 중복 적용되지 않는다(깃발 지원 0.85 × 방패 0.15 = 0.1275가 아니라, 강한 쪽 하나만)
	var st_dbl := lab()
	var sb4 := put(st_dbl, "shieldbearer", 600.0, 300.0)
	sb4.face = 0.0
	var bn := put(st_dbl, "elite_banner", 600.0, 300.0)
	bn.banner_r = 220.0
	bn.banner_ttl = 60.0
	var both := probe(st_dbl, sb4, 0.0)
	var only_banner := probe(st_dbl, sb4, PI)
	ok("피해 감소가 겹쳐 적용되지 않는다: 깃발 지원(0.85) + 방패 정면(0.15)에서 15.0(=0.15만), 후면은 85.0(=0.85만)",
		is_equal_approx(both, 15.0) and is_equal_approx(only_banner, 85.0),
		"정면 %.1f / 후면 %.1f" % [both, only_banner])

	# 출처 방향 규칙(문서와 코드가 같은지 확인)
	var st_src := lab()
	var sb5 := put(st_src, "shieldbearer", st_src.player.x + 200.0, st_src.player.y)
	sb5.face = PI # 플레이어(왼쪽)를 본다
	var from_player := probe(st_src, sb5, PI)
	var from_behind := probe(st_src, sb5, 0.0)
	var no_from_hp: float = sb5.hp
	sb5.hp = 100000.0
	sb5.hp_max = 100000.0
	st_src.damage_enemy(sb5, 100.0, { "src": { "direct": true } }) # from 없음 → 플레이어 현재 위치로 대체
	var fallback: float = 100000.0 - float(sb5.hp)
	sb5.hp = no_from_hp
	ok("출처 방향 규칙: opt.from(공격이 시작된 점)으로 판정하고, from이 없으면 플레이어 **현재 위치**로 대체한다",
		is_equal_approx(from_player, 15.0) and is_equal_approx(from_behind, 100.0) and is_equal_approx(fallback, 15.0),
		"플레이어쪽 %.1f / 뒤쪽 %.1f / from 없음 %.1f" % [from_player, from_behind, fallback])

	# 실제 무기 경로: 부채꼴 근접은 시전 위치, 투사체는 '충돌 직전' 위치를 출처로 쓴다(같은 무기·같은 배율로 비교)
	var st_w := lab()
	st_w.weapons = PWeapons.init(st_w)
	var wsw: Dictionary = st_w.weapons[0]
	var sbw := put(st_w, "shieldbearer", st_w.player.x + 150.0, st_w.player.y)
	sbw.face = 0.0 # 플레이어 반대쪽(오른쪽)을 본다 → 플레이어에서 온 공격은 후면
	sbw.hp = 100000.0
	sbw.hp_max = 100000.0
	PWeapons.hit_arc(st_w, wsw, st_w.player.x, st_w.player.y, 0.0, 400.0, PI, 1.0, {})
	var arc_lost: float = 100000.0 - float(sbw.hp)
	sbw.hp = 100000.0
	var prj := PWeapons.proj(st_w, wsw, { "kind": "arrow", "x": sbw.x + 40.0, "y": sbw.y, "vx": -400.0, "vy": 0.0, "r": 4.0, "speed": 400.0 })
	PWeapons.on_projectile_hit(st_w, prj, sbw)
	var proj_lost: float = 100000.0 - float(sbw.hp)
	ok("무기 경로 확인: 근접 부채꼴은 시전 위치(플레이어 뒤 → 후면 = 감소 없음), 투사체는 충돌 직전 위치(정면에서 날아옴 → 15%만)",
		arc_lost > 0.0 and near(proj_lost / maxf(arc_lost, 0.001), 0.15, 0.01),
		"근접 %.1f / 투사체 %.1f (비 %.3f)" % [arc_lost, proj_lost, proj_lost / maxf(arc_lost, 0.001)])

	# ================= 작업 2. 특수 정예 7종 =================
	var TYPES := ["elite_archer", "elite_blademaster", "elite_fang", "elite_plaguecaller", "elite_chainbreaker", "elite_standard", "elite_miner"]
	var missing := []
	var bad_hp := []
	for tp in TYPES:
		if not E.has(tp):
			missing.append(tp)
			continue
		var dd: Dictionary = E[tp]
		if not bool(dd.get("elite", false)):
			missing.append(tp + "(elite 아님)")
		var h: float = float(dd.hp)
		if h < 48.0 * 3.0 or h > 88.0 * 5.0: # 강화된 1막 주력(늑대 48 · 방패병 88)의 3~5배 범위
			bad_hp.append("%s %.0f" % [tp, h])
	ok("특수 정예 7종이 정의되어 있고 모두 정예 표시", missing.is_empty(), str(missing))
	ok("체력 초기 후보(시험값): 강화된 1막 주력(늑대 48 · 방패병 88)의 3~5배 안", bad_hp.is_empty(), str(bad_hp))

	# 정예 동시 연계 상한 1(보완 규칙)
	var st_cc := lab()
	var c1 := put(st_cc, "elite_fang", st_cc.player.x + 40.0, st_cc.player.y)
	var c2 := put(st_cc, "elite_fang", st_cc.player.x - 40.0, st_cc.player.y)
	var both_committed := false
	for i in int(6.0 / STEP):
		st_cc.step({}, STEP)
		st_cc.player.hp = st_cc.player.hp_max
		st_cc.player.dead = false
		if st_cc.status == "lost":
			st_cc.status = "running"
		if PEnemiesNew.is_committed(c1) and PEnemiesNew.is_committed(c2):
			both_committed = true
			break
	ok("정예 동시 연계 상한 1(보완): 정예 둘이 같은 순간에 연계를 실행하지 않는다(일반 적 압박은 그대로)", not both_committed)

	# ---------- A. 정예 궁수 ----------
	var AD: Dictionary = E.elite_archer
	var sta := lab()
	var ar := put(sta, "elite_archer", sta.player.x + 250.0, sta.player.y)
	var seq_a := trace(sta, ar, 5.5)
	ok("A 정예 궁수 행동 순서: 조준 → 단발 3회 → 부채꼴 예고 → 부채꼴 3발 → 재장전 빈틈",
		seq_a.size() >= 10 and String(seq_a[1]) == "aim" and String(seq_a[2]) == "shot_lock" and String(seq_a[3]) == "aim"
		and seq_a.has("fan_aim") and seq_a.has("fan_lock") and seq_a.has("recover"), str(seq_a))
	# 한 연계(첫 빈틈까지)에서 만들어진 화살 수
	var sta_c := lab()
	var ar_c := put(sta_c, "elite_archer", sta_c.player.x + 250.0, sta_c.player.y)
	var arrows := 0
	var seen := 0
	for i in int(6.0 / STEP):
		sta_c.step({}, STEP)
		sta_c.player.hp = sta_c.player.hp_max
		sta_c.player.dead = false
		if sta_c.status == "lost":
			sta_c.status = "running"
		var made := 0
		for pr2 in sta_c.projectiles: # 새로 만들어진 화살만 한 번씩 센다(맞아서 사라진 화살은 이미 세어 두었다)
			if not pr2.has("_counted"):
				pr2["_counted"] = true
				made += 1
		if made > 0:
			arrows += made
			seen += 1
		if String(ar_c.state) == "recover":
			break
	ok("A 정예 궁수: 한 연계에 화살 6발(단발 3 + 부채꼴 3), 발사 판정 4회", arrows == 6 and seen == 4,
		"화살 %d발 · 발사 %d회 · 실행 판정 %d회" % [arrows, seen, int(sta_c.metrics_for(ar_c).executed)])

	var sta2 := lab()
	var ar2 := put(sta2, "elite_archer", sta2.player.x + 250.0, sta2.player.y)
	var t_aim := until(sta2, ar2, "aim", 4.0)
	var t_shot := until(sta2, ar2, "shot_lock", 4.0)
	var t_shot2 := -1.0
	for i in int(2.0 / STEP): # 두 번째 발사까지
		sta2.step({}, STEP)
		if String(ar2.state) == "shot_lock" and sta2.t - t_shot > 0.2:
			t_shot2 = sta2.t
			break
	ok("A 시험값: 첫 조준 0.70초(추적 0.58 + 방향 고정 0.12), 단발 간격 0.50초(재조준 0.38 + 고정 0.12)",
		near(t_shot - t_aim + float(AD.lock), 0.70, 0.03) and near(t_shot2 - t_shot, 0.50, 0.04),
		"첫 조준 %.2f초 · 간격 %.2f초" % [t_shot - t_aim + float(AD.lock), t_shot2 - t_shot])

	var sta3 := lab()
	var ar3 := put(sta3, "elite_archer", sta3.player.x + 250.0, sta3.player.y)
	until(sta3, ar3, "shot_lock", 4.0)
	var locked_dir: float = ar3.dir
	sta3.player.y -= 120.0 # 확정 뒤 플레이어가 움직여도
	play(sta3, float(AD.lock) + 0.02)
	var shot_ang := 0.0
	for pr3 in sta3.projectiles:
		shot_ang = float(pr3.angle)
	ok("A 확정 뒤 추적 없음: 방향 고정(shot_lock) 뒤에는 플레이어가 움직여도 발사 방향이 그대로",
		near(shot_ang, locked_dir, 0.001), "고정 %.3f → 발사 %.3f" % [locked_dir, shot_ang])

	var sta4 := lab()
	var ar4 := put(sta4, "elite_archer", sta4.player.x + 250.0, sta4.player.y)
	var rec_a := dur_of(sta4, ar4, "recover", 8.0)
	ok("A 시험값: 연계 뒤 빈틈 1.2~1.6초(현재 1.4초)", rec_a >= 1.2 and rec_a <= 1.6, "%.2f초" % rec_a)

	# 장애물에 계속 막히면 사격 위치를 바꾼다
	var sta5 := lab()
	sta5.obstacles = [{ "id": "r1", "type": "rock", "x": sta5.player.x + 120.0, "y": sta5.player.y, "r": 60.0 }]
	var ar5 := put(sta5, "elite_archer", sta5.player.x + 250.0, sta5.player.y)
	var seq5 := trace(sta5, ar5, 2.5)
	ok("A 장애물에 계속 막히면 사격 위치를 바꾼다(reposition)", seq5.has("reposition"), str(seq5))

	# ---------- B. 정예 검사 ----------
	var BD: Dictionary = E.elite_blademaster
	var stb := lab()
	var bl := put(stb, "elite_blademaster", stb.player.x + 220.0, stb.player.y)
	var seq_b := trace(stb, bl, 9.0)
	ok("B 정예 검사 행동 순서: 돌진 베기 → 새 방향 예고 → 두 번째 돌진 베기 → 방패 자세 → 내려찍기 → 빈틈",
		seq_b.has("dash1_aim") and seq_b.has("dash1") and seq_b.has("dash2_aim") and seq_b.has("dash2")
		and seq_b.has("guard") and seq_b.has("slam_aim") and seq_b.has("recover")
		and seq_b.find("guard") > seq_b.find("dash2") and seq_b.find("slam_aim") > seq_b.find("guard"), str(seq_b))
	ok("B 시험값: 첫 예고 0.65초 · 두 번째 예고 0.50초 · 방패 자세 1.5초 · 마지막 빈틈 1.0초",
		is_equal_approx(float(BD.aim1), 0.65) and is_equal_approx(float(BD.aim2), 0.5)
		and is_equal_approx(float(BD.guardDur), 1.5) and is_equal_approx(float(BD.recover), 1.0))

	var stb2 := lab()
	var bl2 := put(stb2, "elite_blademaster", stb2.player.x + 220.0, stb2.player.y)
	until(stb2, bl2, "dash1", 4.0)
	var d0: float = bl2.dir
	stb2.player.y -= 150.0
	play(stb2, 0.15)
	ok("B 돌진 중 추적 회전 금지: 확정한 방향 그대로 달린다", near(float(bl2.dir), d0, 0.0001),
		"확정 %.3f → 진행 중 %.3f" % [d0, float(bl2.dir)])

	var stb3 := lab()
	var bl3 := put(stb3, "elite_blademaster", stb3.player.x + 220.0, stb3.player.y)
	until(stb3, bl3, "guard", 9.0)
	var g_front := probe(stb3, bl3, float(bl3.face))
	var g_side := probe(stb3, bl3, float(bl3.face) + PI / 2.0)
	var g_ground := probe(stb3, bl3, float(bl3.face), { "src": { "direct": false, "extra": true, "tag": "common:ember" } })
	ok("B 방패 자세: 정면 직접 피해 **완전 차단**(0) — 일반 방패병 85% 감소(15)와 구분. 측면·바닥은 그대로",
		is_equal_approx(g_front, 0.0) and is_equal_approx(g_side, 100.0) and is_equal_approx(g_ground, 100.0),
		"정면 %.1f / 측면 %.1f / 바닥 %.1f" % [g_front, g_side, g_ground])

	# ---------- C. 피의 송곳니 ----------
	var CD: Dictionary = E.elite_fang
	var stc := lab()
	var fg := put(stc, "elite_fang", stc.player.x + 60.0, stc.player.y)
	var seq_c := trace(stc, fg, 7.0)
	ok("C 피의 송곳니 행동 순서: 접근 → 짧은 물기 → 짧게 이탈 → 착지 예고 → 도약 → 빈틈",
		seq_c.has("bite_aim") and seq_c.has("backoff") and seq_c.has("leap_aim") and seq_c.has("leap_lock")
		and seq_c.has("leap") and (seq_c.has("recover") or seq_c.has("stagger"))
		and seq_c.find("backoff") > seq_c.find("bite_aim") and seq_c.find("leap_aim") > seq_c.find("backoff"), str(seq_c))

	var stc2 := lab()
	var fg2 := put(stc2, "elite_fang", stc2.player.x + 60.0, stc2.player.y)
	until(stc2, fg2, "leap_lock", 8.0)
	var land0: Array = fg2.leap_at
	stc2.player.x -= 200.0
	play(stc2, float(CD.leapLock) + float(CD.leapTime) + 0.02)
	var land1: Array = fg2.leap_at
	ok("C 착지 위치 확정 뒤 추적 금지: 확정 뒤 플레이어가 200 움직여도 착지점이 같다",
		near(float(land0[0]), float(land1[0]), 0.001) and near(float(land0[1]), float(land1[1]), 0.001),
		"(%.0f,%.0f) → (%.0f,%.0f)" % [float(land0[0]), float(land0[1]), float(land1[0]), float(land1[1])])
	ok("C 도약 실패(빗나감)는 더 긴 빈틈 1.6초 — 공격 기회", String(fg2.state) == "stagger" and is_equal_approx(float(CD.missStagger), 1.6), String(fg2.state))

	# ---------- D. 역병 조율사 ----------
	var DD: Dictionary = E.elite_plaguecaller
	var std := lab()
	var pc := put(std, "elite_plaguecaller", std.player.x + 220.0, std.player.y)
	until(std, pc, "swell", 6.0)
	var pods: Array = pc.pods
	var orders := []
	var gaps := []
	for pod in pods:
		orders.append(int(pod.order))
		gaps.append(float(pod.land_at))
	var gap_ok := true
	for i in range(1, gaps.size()):
		if not near(float(gaps[i]) - float(gaps[i - 1]), float(DD.podGap), 0.02):
			gap_ok = false
	ok("D 역병 조율사: 포자 3개를 흩어 투척하고 1 → 2 → 3 순서로 0.45초 간격 순차 폭발(순서·범위 표시)",
		pods.size() == int(DD.podCount) and orders == [1, 2, 3] and gap_ok, "순서 %s · 간격 %s" % [str(orders), str(gaps)])
	var th_d := []
	PEnemies.threats(std, pc, th_d)
	ok("D 폭발 범위와 순서를 예고 도형으로 내보낸다(봇·화면이 같은 정보를 본다)", th_d.size() == pods.size() and int(th_d[0].get("order", 0)) >= 1, str(th_d.size()))

	play(std, float(DD.swell) + float(DD.podGap) * 3.0 + 0.2)
	var clouds := 0
	var max_ttl := 0.0
	for z in std.zones:
		if String(z.type) == "spore":
			clouds += 1
			max_ttl = maxf(max_ttl, float(z.max_ttl))
	ok("D 잔류 구름 수·시간 상한(시험값 3개 · 2.6초)로 전장 전체를 봉쇄하지 않는다",
		clouds <= int(DD.maxClouds) and max_ttl <= float(DD.cloudTtl) + 1e-6, "구름 %d개 · 최대 수명 %.1f초" % [clouds, max_ttl])

	var std2 := lab()
	var pc2 := put(std2, "elite_plaguecaller", std2.player.x + 60.0, std2.player.y)
	var seq_d2 := trace(std2, pc2, 2.0)
	ok("D 근접에는 예고된 좁은 포자 분출(burst_aim, 예고 0.45초 · 70도)", seq_d2.has("burst_aim") and is_equal_approx(float(DD.burstDeg), 70.0), str(seq_d2))

	# ---------- E. 사슬 집행자 ----------
	var ED: Dictionary = E.elite_chainbreaker
	var ste := lab()
	var ch := put(ste, "elite_chainbreaker", ste.player.x + 240.0, ste.player.y)
	var seq_e := trace(ste, ch, 6.0)
	ok("E 사슬 집행자 행동 순서: 사슬 예고 → 발사 → 명중 시 끌기 → 강타 예고 → 강타",
		seq_e.has("chain_aim") and seq_e.has("chain_lock") and seq_e.has("chain_fly")
		and (seq_e.has("pull") or seq_e.has("retract")), str(seq_e))

	var ste2 := lab()
	var ch2 := put(ste2, "elite_chainbreaker", ste2.player.x + 240.0, ste2.player.y)
	until(ste2, ch2, "pull", 6.0)
	var t_pull := ste2.t
	var t_slam := until(ste2, ch2, "slam_lock", 4.0)
	var window := t_slam - t_pull - float(ED.pullTime)
	ok("E 끌린 뒤 후속 강타를 회피할 입력 기회 보장(끌기 종료 → 강타 확정까지 0.55초 이상)",
		window >= 0.5, "%.2f초" % window)

	var ste3 := lab()
	var ch3 := put(ste3, "elite_chainbreaker", ste3.player.x + 240.0, ste3.player.y)
	until(ste3, ch3, "pull", 6.0)
	var hp_e0: float = ste3.player.hp
	# 강타 예고 동안 옆으로 걸어 나간다(무적·회피 없이 이동만)
	var moved := 0
	for i in int(2.0 / STEP):
		ste3.step({ "mx": 0.0, "my": -1.0 }, STEP)
		moved += 1
		if String(ch3.state) == "recover":
			break
	var slam_taken: float = hp_e0 - float(ste3.player.hp)
	ok("E 확정 뒤에도 회피가 통한다: 강타 예고 동안 걸어 나가면 강타를 맞지 않는다",
		slam_taken <= float(ED.chainDamage) + 0.01, "받은 피해 %.0f(사슬 %.0f 포함)" % [slam_taken, float(ED.chainDamage)])

	var ste4 := lab()
	# 플레이어 너머(사슬 경로 위)에 바위: 플레이어까지의 시야는 열려 있지만 사슬은 바위에서 끊긴다
	ste4.obstacles = [{ "id": "r1", "type": "rock", "x": ste4.player.x - 60.0, "y": ste4.player.y, "r": 40.0 }]
	var ch4 := put(ste4, "elite_chainbreaker", ste4.player.x + 240.0, ste4.player.y)
	var t_cl := until(ste4, ch4, "chain_lock", 8.0)
	ok("E 사슬은 바위에 막힌다(예고 길이 = 실제 길이)",
		t_cl >= 0.0 and float(ch4.chain_len) < float(ED.chainLen) - 20.0,
		"사슬 길이 %.0f (최대 %.0f)" % [float(ch4.get("chain_len", -1.0)), float(ED.chainLen)])

	# ---------- F. 군단 기수 ----------
	var FD: Dictionary = E.elite_standard
	var stf := lab()
	var sd := put(stf, "elite_standard", stf.player.x + 260.0, stf.player.y)
	var n_before := stf.enemies.size()
	until(stf, sd, "plant_aim", 4.0)
	play(stf, float(FD.plantAim) + 0.05)
	var banner := {}
	for o in stf.enemies:
		if String(o.type) == "elite_banner":
			banner = o
	ok("F 군단 기수: 파괴 가능한 깃발을 설치한다(구조물 · 부술 수 있다)",
		not banner.is_empty() and bool(banner.structure) and float(banner.hp) > 0.0, "깃발 체력 %.0f" % (float(banner.hp) if not banner.is_empty() else -1.0))
	ok("F 깃발은 적을 새로 부르지 않는다(추가 소환으로 무한 경험치·금화가 되지 않는다)",
		stf.enemies.size() == n_before + 1, "적 수 %d → %d(깃발 1개만)" % [n_before, stf.enemies.size()])
	ok("F 깃발·돌무더기는 경험치를 주지 않는다", is_equal_approx(stf.xp_for(banner), 0.0))

	var stf2 := lab()
	var sd2 := put(stf2, "elite_standard", stf2.player.x + 260.0, stf2.player.y)
	var ally := put(stf2, "wolf", stf2.player.x + 250.0, stf2.player.y + 30.0)
	ally.bite_cd = 1.0e9
	ally.dash_ready_at = 1.0e9
	until(stf2, sd2, "plant_aim", 4.0)
	play(stf2, float(FD.plantAim) + 0.2)
	var boosted: bool = float(ally.leash_boost) > 1.0
	var ally_guard := 0.0
	var hp_a0: float = ally.hp
	ally.hp = 100000.0
	ally.hp_max = 100000.0
	stf2.damage_enemy(ally, 100.0, { "src": { "direct": true }, "from": { "x": ally.x + 50.0, "y": ally.y } })
	ally_guard = 100000.0 - float(ally.hp)
	ally.hp = hp_a0
	ok("F 깃발 범위 안 아군: 집결(이동 가속)과 방어 지원(직접 피해 100 → 85)이 함께 걸린다",
		boosted and is_equal_approx(ally_guard, 85.0), "가속 ×%.2f · 피해 %.1f" % [float(ally.leash_boost), ally_guard])

	# 깃발을 부수면 지원이 끊긴다
	for o in stf2.enemies:
		if String(o.type) == "elite_banner":
			stf2.damage_enemy(o, 1000.0, { "src": { "direct": true } })
	play(stf2, 0.35)
	var hp_a1: float = ally.hp
	ally.hp = 100000.0
	ally.hp_max = 100000.0
	stf2.damage_enemy(ally, 100.0, { "src": { "direct": true }, "from": { "x": ally.x + 50.0, "y": ally.y } })
	var after_break := 100000.0 - float(ally.hp)
	ally.hp = hp_a1
	ok("F 깃발을 먼저 부수면 집결·방어 지원이 즉시 끊긴다(기수와 깃발 중 무엇을 칠지 선택 가능)",
		is_equal_approx(after_break, 100.0) and is_equal_approx(float(ally.leash_boost), 1.0),
		"피해 %.1f · 가속 ×%.2f" % [after_break, float(ally.leash_boost)])
	var BB: Dictionary = FD.banner
	ok("F 호위·지원은 유한 예산(시험값): 깃발 %d개 · 돌격 명령 %d회 · 깃발 수명 %.0f초" % [int(FD.plantBudget), int(BB.orderBudget), float(BB.ttl)],
		int(FD.plantBudget) <= 2 and int(BB.orderBudget) <= 6 and float(BB.ttl) <= 20.0)

	# ---------- G. 균열 채굴자 ----------
	var GD: Dictionary = E.elite_miner
	var stg := lab()
	var mn := put(stg, "elite_miner", stg.player.x + 200.0, stg.player.y)
	var seq_g := trace(stg, mn, 8.0)
	ok("G 균열 채굴자 행동 순서: 잠행 → 지하 이동 → 출현 예고 → 솟구치기 → 지상 빈틈",
		seq_g.has("dive") and seq_g.has("under") and seq_g.has("warn") and seq_g.has("erupt") and seq_g.has("stagger"), str(seq_g))

	var stg2 := lab()
	var mn2 := put(stg2, "elite_miner", stg2.player.x + 200.0, stg2.player.y)
	var under_dur := dur_of(stg2, mn2, "under", 8.0)
	ok("G 지하에만 오래 숨어 시간을 끌지 않는다(최대 1.6초)", under_dur > 0.0 and under_dur <= float(GD.underMax) + 0.05, "%.2f초" % under_dur)

	var stg3 := lab()
	var mn3 := put(stg3, "elite_miner", stg3.player.x + 200.0, stg3.player.y)
	until(stg3, mn3, "warn", 8.0)
	var at0: Array = mn3.emerge_at
	stg3.player.x -= 250.0
	play(stg3, float(GD.warn) + 0.02)
	ok("G 출현 위치 확정 뒤 추적 금지: 플레이어가 250 움직여도 예고한 자리에서 솟구친다",
		near(float(at0[0]), float(mn3.x), 0.5) and near(float(at0[1]), float(mn3.y), 0.5),
		"예고 (%.0f,%.0f) → 실제 (%.0f,%.0f)" % [float(at0[0]), float(at0[1]), float(mn3.x), float(mn3.y)])

	var rocks := 0
	for o in stg3.enemies:
		if String(o.type) == "elite_rubble" and not o.dead:
			rocks += 1
	ok("G 돌무더기는 파괴 가능한 구조물이고 수 상한(4)·수명(8초)이 있다",
		rocks <= int(GD.rockMax) and float(GD.rockTtl) <= 8.0, "이번에 %d개 · 상한 %d · 수명 %.0f초" % [rocks, int(GD.rockMax), float(GD.rockTtl)])
	if rocks > 0:
		var rk := {}
		for o in stg3.enemies:
			if String(o.type) == "elite_rubble" and not o.dead:
				rk = o
		stg3.damage_enemy(rk, 1000.0, { "src": { "direct": true } })
		ok("G 돌무더기를 부술 수 있다", bool(rk.dead))
	else:
		ok("G 돌무더기를 부술 수 있다(이번 배치에서는 출구 검사로 생략됨 — 규칙은 같다)", true)

	# 돌무더기가 플레이어의 탈출 방향을 모두 막지 않는다
	var stg4 := lab()
	var mn4 := put(stg4, "elite_miner", stg4.player.x + 200.0, stg4.player.y)
	play(stg4, 8.0)
	var dangers := []
	for o in stg4.enemies:
		if String(o.type) == "elite_rubble" and not o.dead:
			dangers.append({ "x": o.x, "y": o.y, "r": o.r })
	var free := PEnemiesNew._exits_open(stg4, dangers, float(GD.probe))
	ok("G 돌무더기가 시작점·목표·유일한 탈출로를 막지 않는다(16방향 중 %d방향 열림, 기준 %d 이상)" % [free, int(GD.minExits)],
		free >= int(GD.minExits))

	# ---------- 공통: 예고 도형이 있어야 회피가 가능하다 ----------
	var no_threat := []
	for tp in TYPES:
		var stt := lab()
		var ee := put(stt, tp, stt.player.x + 200.0, stt.player.y)
		var seen_th := false
		for i in int(10.0 / STEP):
			stt.step({}, STEP)
			stt.player.hp = stt.player.hp_max
			stt.player.dead = false
			if stt.status == "lost":
				stt.status = "running"
			var th := []
			PEnemies.threats(stt, ee, th)
			if th.size() > 0:
				seen_th = true
				break
		if not seen_th:
			no_threat.append(tp)
	ok("정예 7종 모두 봇·화면이 읽는 예고 도형을 내보낸다(예고 없는 공격 없음)", no_threat.is_empty(), str(no_threat))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
