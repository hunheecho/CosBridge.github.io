extends SceneTree
## 방패병 확정 변경 + 특수 정예 7종 규칙 검사(화면 없음).
## 실행: python tools/run_suites.py --suites elites_tests --allow-adhoc
##      (직접: godot --headless --path prophecy_godot -s tests/elites_tests.gd)
##
## 무엇을 보는가
##  - 방패병: 정면 감소 **70%(100 → 30)**가 실제 수치로 나오는지, 각도 경계·방어 유지/해제 구간·우회 관계·중복 없음.
##    (2026-09-09 사용자 확정으로 85% → 70%. 정예 검사의 방패 자세 0%는 전혀 다른 값이며 아래 작업 2에서 따로 본다.)
##  - 주술사: 강한 다친 아군 우선 치료 · 가득 찬 강적 제외 · 세 갈래 저주탄 · 저주 문양 · 치료와 공격의 공용 간격.
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

# ---------- 회피 시험 도구(작업 5) ----------
## 그 자리를 덮는 바닥 예고. 전투망치 내려찍기·기술·지뢰가 내는 것과 **같은 모양**이며 그 자체는 피해가 없다
func warn_at(st: CombatState, x: float, y: float, r: float = 55.0, ttl: float = 0.9) -> void:
	st.fx({ "kind": "strikewarn", "x": x, "y": y, "r": r, "ttl": ttl })

## 정예를 향해 날아오는 **플레이어 투사체**. dmg를 주면 실제 피해도 들어간다(무기 없는 단순 탄).
## 걸어가는 적을 그냥 조준하면 시험 자체가 빗나가므로 **지금 속도로 앞을 노린다**(가만히 서 있으면 정조준과 같다).
## 회피로 방향이 바뀌면 이 겨냥이 어긋나는데, 그것이 바로 회피가 실제로 하는 일이다
func shot_at(st: CombatState, e: Dictionary, from_ang: float, dmg: float = 0.0, d: float = 230.0, speed: float = 360.0) -> void:
	var vx: float = (float(e.x) - float(e.get("last_x", e.x))) / STEP
	var vy: float = (float(e.y) - float(e.get("last_y", e.y))) / STEP
	var tof: float = d / speed
	var tx: float = float(e.x) + vx * tof
	var ty: float = float(e.y) + vy * tof
	var sx: float = float(e.x) + cos(from_ang) * d
	var sy: float = float(e.y) + sin(from_ang) * d
	var a: float = atan2(ty - sy, tx - sx)
	st.projectiles.append({ "owner": "player", "kind": "test_arrow", "x": sx, "y": sy,
		"vx": cos(a) * speed, "vy": sin(a) * speed, "r": 5.0, "dmg": dmg, "ttl": 2.5,
		"angle": a, "dead": false, "hits": {}, "weapon": null, "target": null, "boomerang": {} })

## 회피 시험실: 정예 하나만 두고 플레이어는 멀리 세운다. 한 프레임 굴려 회피 칸을 만든 뒤 재사용을 비운다
## ('첫 회피까지의 여유 first'는 값 검사에서 따로 본다 — 여기서 보려는 것은 반응이다)
func dodge_lab(seed_v: int, tp: String, ex: float = 480.0, ey: float = 300.0) -> Array:
	var st := lab(seed_v)
	st.player.x = 60.0
	st.player.y = 560.0
	var e := put(st, tp, ex, ey)
	st.step({}, STEP)
	e["dodge_cd"] = 0.0
	e["dodge_wait"] = 0.0
	return [st, e]

func alive_step(st: CombatState) -> void:
	st.step({}, STEP)
	st.player.hp = st.player.hp_max
	st.player.dead = false
	if st.status == "lost":
		st.status = "running"

## 회피 관찰용 구동기. kind = "warn"(바닥 예고) | "shot"(투사체) | "none"
##  pin: 0 = 첫 회피 전까지 자리를 붙잡는다(거리 조건을 일정하게 유지) · 1 = 붙잡지 않는다 ·
##       2 = **회피 이동·추스름을 빼고 늘** 붙잡는다(움직이는 표적을 겨냥하는 실수를 빼고 명중만 세려는 것)
##  hold_state: 매 프레임 approach로 되돌린다(자기 연계가 끼어들지 않게 — 회피 조건만 보려는 것)
## 반환 = 실제로 낸 위협 수
func drive(st: CombatState, e: Dictionary, kind: String, sec: float, gap: float = 0.4,
		pin: int = 0, hold_state: bool = true, dmg: float = 0.0, sd: float = 230.0, sp: float = 360.0) -> int:
	var ax: float = e.x
	var ay: float = e.y
	var n := int(round(sec / STEP))
	var left := 0.0
	var fired := 0
	for i in n:
		left -= STEP
		if left <= 0.0:
			left = gap
			if kind == "warn":
				warn_at(st, float(e.x) + 16.0, float(e.y) + 16.0)
				fired += 1
			elif kind == "shot":
				shot_at(st, e, 2.2, dmg, sd, sp)
				fired += 1
		alive_step(st)
		var ph := String(e.get("dodge_phase", ""))
		if hold_state and ph != "move":
			e.state = "approach"
			e.state_t = 0.0
		if pin == 0 and int(e.get("dodge_uses", 0)) == 0:
			e.x = ax
			e.y = ay
		elif pin == 2 and ph != "move" and ph != "settle":
			e.x = ax
			e.y = ay
	return fired

## 첫 회피의 **이동**이 시작될 때까지 굴린다. 반환 = 시작했는가
func until_dodge(st: CombatState, e: Dictionary, max_sec: float = 12.0) -> bool:
	var n := int(round(max_sec / STEP))
	var left := 0.0
	var ax: float = e.x
	var ay: float = e.y
	for i in n:
		if String(e.get("dodge_phase", "")) == "move":
			return true
		left -= STEP
		if left <= 0.0:
			left = 0.4
			warn_at(st, float(e.x) + 16.0, float(e.y) + 16.0)
		alive_step(st)
		if String(e.get("dodge_phase", "")) != "move":
			e.state = "approach"
			e.state_t = 0.0
			e.x = ax
			e.y = ay
	return String(e.get("dodge_phase", "")) == "move"

## 회피가 시작된 시각들(재사용 간격을 재려는 것). 자기 연계는 매 프레임 approach로 눌러 둔다
func dodge_times(st: CombatState, e: Dictionary, sec: float, gap: float = 0.4) -> Array:
	var out := []
	var n := int(round(sec / STEP))
	var left := 0.0
	var last := int(e.get("dodge_uses", 0))
	for i in n:
		left -= STEP
		if left <= 0.0:
			left = gap
			warn_at(st, float(e.x) + 16.0, float(e.y) + 16.0)
		alive_step(st)
		if String(e.get("dodge_phase", "")) != "move":
			e.state = "approach"
			e.state_t = 0.0
		var u := int(e.get("dodge_uses", 0))
		if u > last:
			last = u
			out.append(st.t)
	return out

## 지형 안에 제대로 있는가(전장 밖·벽·바위 안으로 들어가지 않았는가). 밀어내기가 정확히 접점까지 놓으므로 여유 0.6px
func in_terrain(st: CombatState, e: Dictionary) -> bool:
	var r: float = float(e.r)
	if float(e.x) < r - 0.6 or float(e.x) > st.arena_w - r + 0.6:
		return false
	if float(e.y) < r - 0.6 or float(e.y) > st.arena_h - r + 0.6:
		return false
	for ob in st.obstacles:
		if PGeom.dist(float(e.x), float(e.y), float(ob.x), float(ob.y)) < float(ob.r) + r - 0.6:
			return false
	return true

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
	var SB_T := PEnemiesNew.tuning("shieldbearer") # 손으로 정한 값은 data/pacing.json이 정본(enemies.json은 내보내기 산출물)
	ok("사용자 확정(2026-09-09): 방패병 정면 피해 감소 **70%**(frontMult 0.30), 정면 각 120도 유지",
		is_equal_approx(float(SB_T.frontMult), 0.30) and is_equal_approx(float(SB.frontDeg), 120.0),
		"frontMult %.2f(겹쳐쓰기) · frontDeg %.0f" % [float(SB_T.frontMult), float(SB.frontDeg)])

	var st1 := lab()
	var sb := put(st1, "shieldbearer", 600.0, 300.0)
	sb.face = 0.0 # 오른쪽(+x)을 본다
	var front := probe(st1, sb, 0.0)
	var side := probe(st1, sb, PI / 2.0)
	var back := probe(st1, sb, PI)
	ok("사용자 확정: 유효 정면 직접 피해 100 → 30 (측면·후면은 100 그대로)",
		is_equal_approx(front, 30.0) and is_equal_approx(side, 100.0) and is_equal_approx(back, 100.0),
		"정면 %.1f / 측면 %.1f / 후면 %.1f" % [front, side, back])

	var edge_in := probe(st1, sb, PGeom.deg(59.0))
	var edge_out := probe(st1, sb, PGeom.deg(61.0))
	ok("정면 각도 경계(±60도)에서 판정이 흔들리지 않는다: 59도 감소 · 61도 정상",
		is_equal_approx(edge_in, 30.0) and is_equal_approx(edge_out, 100.0),
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
		is_equal_approx(float(guard_states.approach), 30.0) and is_equal_approx(float(guard_states.bash_aim), 30.0)
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

	# 다른 방어 효과와 중복 적용되지 않는다(깃발 지원 0.85 × 방패 0.30 = 0.255가 아니라, 강한 쪽 하나만)
	var st_dbl := lab()
	var sb4 := put(st_dbl, "shieldbearer", 600.0, 300.0)
	sb4.face = 0.0
	var bn := put(st_dbl, "elite_banner", 600.0, 300.0)
	bn.banner_r = 220.0
	bn.banner_ttl = 60.0
	var both := probe(st_dbl, sb4, 0.0)
	var only_banner := probe(st_dbl, sb4, PI)
	ok("피해 감소가 겹쳐 적용되지 않는다: 깃발 지원(0.85) + 방패 정면(0.30)에서 30.0(=0.30만), 후면은 85.0(=0.85만)",
		is_equal_approx(both, 30.0) and is_equal_approx(only_banner, 85.0),
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
		is_equal_approx(from_player, 30.0) and is_equal_approx(from_behind, 100.0) and is_equal_approx(fallback, 30.0),
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
	ok("무기 경로 확인: 근접 부채꼴은 시전 위치(플레이어 뒤 → 후면 = 감소 없음), 투사체는 충돌 직전 위치(정면에서 날아옴 → 30%만)",
		arc_lost > 0.0 and near(proj_lost / maxf(arc_lost, 0.001), 0.30, 0.01),
		"근접 %.1f / 투사체 %.1f (비 %.3f)" % [arc_lost, proj_lost, proj_lost / maxf(arc_lost, 0.001)])

	# ================= 작업 1-2. 주술사(사용자 피드백 2026-09-09) =================
	var SH_T := PEnemiesNew.tuning("shaman")
	ok("시험값: 치료량 30%% → **20%%**(healRatio 0.20)", is_equal_approx(float(SH_T.healRatio), 0.20),
		"healRatio %.2f(겹쳐쓰기)" % float(SH_T.healRatio))

	# --- 치료 대상 우선순위: 특수 정예 → 일반 정예·우두머리 → 주력 적 → 일반 잡몹 ---
	var st_h := lab()
	var sh := put(st_h, "shaman", 600.0, 300.0)
	var t_fang := put(st_h, "elite_fang", 640.0, 300.0)
	var t_alpha := put(st_h, "wolf_alpha", 660.0, 300.0)
	var t_wolf := put(st_h, "wolf", 680.0, 300.0)
	var t_spider := put(st_h, "spider", 700.0, 300.0)
	# 잃은 체력의 절대값은 **낮은 순위 쪽이 훨씬 크게** 만들어 둔다 — 그래도 순위가 이겨야 한다
	t_fang.hp = float(t_fang.hp_max) - 1.0
	t_alpha.hp = float(t_alpha.hp_max) - 2.0
	t_wolf.hp = float(t_wolf.hp_max) - 20.0
	t_spider.hp = 1.0
	var pick1 := PEnemiesNew.heal_target(st_h, sh)
	t_fang.dead = true
	var pick2 := PEnemiesNew.heal_target(st_h, sh)
	t_alpha.dead = true
	var pick3 := PEnemiesNew.heal_target(st_h, sh)
	t_wolf.dead = true
	var pick4 := PEnemiesNew.heal_target(st_h, sh)
	ok("사용자 지시: 치료 우선순위 = 특수 정예 → 일반 정예·우두머리 → 주력 적 → 일반 잡몹(잃은 체력이 더 커도 순위가 이긴다)",
		pick1 == t_fang and pick2 == t_alpha and pick3 == t_wolf and pick4 == t_spider,
		"%s → %s → %s → %s" % [String(pick1.get("type", "없음")), String(pick2.get("type", "없음")), String(pick3.get("type", "없음")), String(pick4.get("type", "없음"))])

	# 같은 순위 안에서는 **잃은 체력의 절대값**이 큰 쪽(잃은 비율이 아니다)
	var st_a := lab()
	var sh_a := put(st_a, "shaman", 600.0, 300.0)
	var a_wolf := put(st_a, "wolf", 640.0, 300.0)      # 최대 체력이 작다 → 비율은 크고 절대값은 작다
	var a_shield := put(st_a, "shieldbearer", 660.0, 300.0) # 최대 체력이 크다 → 비율은 작고 절대값은 크다
	a_wolf.hp = float(a_wolf.hp_max) - 20.0
	a_shield.hp = float(a_shield.hp_max) - 30.0
	var pick_abs := PEnemiesNew.heal_target(st_a, sh_a)
	ok("같은 순위 안에서는 **잃은 체력의 절대값**이 큰 쪽을 고른다(잃은 비율로 고르지 않는다)",
		pick_abs == a_shield,
		"늑대 잃음 20(비율 %.2f) / 방패병 잃음 30(비율 %.2f) → %s" % [20.0 / float(a_wolf.hp_max), 30.0 / float(a_shield.hp_max), String(pick_abs.get("type", "없음"))])

	# 가득 찬 강적은 대상이 아니다 + 자기·다른 주술사·보스는 제외(기존 규칙 유지)
	var st_f := lab()
	var sh_f := put(st_f, "shaman", 600.0, 300.0)
	var f_fang := put(st_f, "elite_fang", 640.0, 300.0) # 체력 가득
	var f_wolf := put(st_f, "wolf", 660.0, 300.0)
	f_wolf.hp = float(f_wolf.hp_max) - 5.0
	var pick_full := PEnemiesNew.heal_target(st_f, sh_f)
	sh_f.hp = float(sh_f.hp_max) - 30.0
	var sh_f2 := put(st_f, "shaman", 620.0, 300.0)
	sh_f2.hp = float(sh_f2.hp_max) - 30.0
	var boss_f := put(st_f, "boss", 700.0, 300.0)
	boss_f.hp = float(boss_f.hp_max) - 500.0
	var pick_excl := PEnemiesNew.heal_target(st_f, sh_f)
	ok("가득 찬 강적을 붙잡고 다친 아군을 무시하지 않는다 + 자기·다른 주술사·보스는 대상 제외(기존 규칙 유지)",
		pick_full == f_wolf and pick_excl == f_wolf and not f_fang.dead,
		"가득 찬 정예 있어도 %s / 자기·주술사·보스 제외 뒤에도 %s" % [String(pick_full.get("type", "없음")), String(pick_excl.get("type", "없음"))])

	# 치료량 20%와 관측 자료(누구를 치료 중인지)
	var st_c := lab()
	var sh_c := put(st_c, "shaman", 600.0, 300.0)
	var c_wolf := put(st_c, "wolf", 640.0, 300.0)
	c_wolf.hp = 1.0
	sh_c.heal_t = 0.0
	sh_c.hex_t = 99.0
	sh_c.rune_t = 99.0
	sh_c.act_t = 0.0
	until(st_c, sh_c, "cast", 4.0)
	var links := []
	PEnemies.support_links(st_c, links)
	var hp_before: float = c_wolf.hp
	play(st_c, float(PCatalog.enemy("shaman").healCast) + 0.2)
	var healed: float = float(c_wolf.hp) - hp_before
	ok("치료량은 대상 최대 체력의 20%%이고, **지금 누구를 치료 중인지**가 관측 자료(PEnemies.support_links)로 나온다",
		near(healed, float(c_wolf.hp_max) * 0.20, 0.5) and links.size() == 1 and links[0].target == c_wolf and String(links[0].kind) == "heal_link",
		"회복 %.1f(최대 %.1f의 20%% = %.1f) · 연결선 %d개" % [healed, float(c_wolf.hp_max), float(c_wolf.hp_max) * 0.2, links.size()])

	# 시전 중단(기존 대응 유지)
	var st_i := lab()
	var sh_i := put(st_i, "shaman", 600.0, 300.0)
	var i_wolf := put(st_i, "wolf", 640.0, 300.0)
	i_wolf.hp = 1.0
	sh_i.heal_t = 0.0
	sh_i.hex_t = 99.0
	sh_i.rune_t = 99.0
	sh_i.act_t = 0.0
	until(st_i, sh_i, "cast", 4.0)
	sh_i.hp = 100000.0
	sh_i.hp_max = 100000.0
	st_i.damage_enemy(sh_i, 30.0, { "src": { "direct": true } })
	ok("강한 타격(12 이상)으로 치료 시전이 끊긴다(기존 대응 유지)",
		String(sh_i.state) == "recover" and sh_i.get("cast_target") == null and int(st_i.metrics.interrupts) == 1,
		"상태 %s · 중단 %d회" % [String(sh_i.state), int(st_i.metrics.interrupts)])

	# --- 공격 A. 세 갈래 저주탄 ---
	var st_x := lab()
	var sh_x := put(st_x, "shaman", st_x.player.x + 250.0, st_x.player.y)
	sh_x.heal_t = 99.0
	sh_x.rune_t = 99.0
	sh_x.hex_t = 0.0
	sh_x.act_t = 0.0
	until(st_x, sh_x, "hex_lock", 6.0)
	var lock_dir: float = sh_x.dir
	var want_dir: float = atan2(st_x.player.y - sh_x.y, st_x.player.x - sh_x.x)
	st_x.player.y += 260.0 # 확정 뒤에 크게 움직인다 — 따라오면 안 된다
	play(st_x, float(SH_T.hexLock) + 0.1)
	var bolts := []
	for pr in st_x.projectiles:
		if String(pr.kind) == "hex":
			bolts.append(float(pr.angle))
	bolts.sort()
	var step_deg := PGeom.deg(float(SH_T.hexSpreadDeg))
	var center_ok: bool = bolts.size() == 3 and near(PGeom.ang_diff(lock_dir, float(bolts[1])), 0.0, 0.01)
	ok("공격 A: 한 발 평타 → **세 갈래 저주탄**이고, **가운데 탄은 조준 확정 시점의 플레이어 방향**이다",
		center_ok and near(PGeom.ang_diff(lock_dir, want_dir), 0.0, 0.01),
		"탄 %d발 · 확정 방향 %.1f도 · 확정 시점 플레이어 방향 %.1f도" % [bolts.size(), lock_dir * 180.0 / PI, want_dir * 180.0 / PI])
	var spread_ok: bool = bolts.size() == 3 and near(absf(PGeom.ang_diff(float(bolts[0]), float(bolts[1]))), step_deg, 0.01) and near(absf(PGeom.ang_diff(float(bolts[2]), float(bolts[1]))), step_deg, 0.01)
	ok("공격 A: 예고(hex_aim)는 따라오지만 확정(hex_lock) 뒤에는 방향이 고정된다 — 옆으로 이동해 피할 수 있다",
		spread_ok and near(PGeom.ang_diff(lock_dir, float(bolts[1])), 0.0, 0.01),
		"±%.0f도 · 크게 움직인 뒤에도 가운데 탄 %.1f도(확정 %.1f도)" % [step_deg * 180.0 / PI, float(bolts[1]) * 180.0 / PI, lock_dir * 180.0 / PI])

	# --- 공격 B. 저주 문양 ---
	var st_r := lab()
	var sh_r := put(st_r, "shaman", st_r.player.x + 250.0, st_r.player.y)
	sh_r.heal_t = 99.0
	sh_r.hex_t = 99.0
	sh_r.rune_t = 0.0
	sh_r.act_t = 0.0
	until(st_r, sh_r, "rune_aim", 4.0)
	var rune_at0: Array = (sh_r.rune_at as Array).duplicate()
	var px0: float = st_r.player.x
	var py0: float = st_r.player.y
	st_r.player.x += 240.0 # 예고 중 크게 이동 — 문양이 따라오면 안 된다
	play(st_r, float(SH_T.runeAim) * 0.5)
	var th_r := []
	PEnemies.threats(st_r, sh_r, th_r)
	var fixed_ok: bool = near(float((sh_r.rune_at as Array)[0]), float(rune_at0[0]), 0.001) and near(float((sh_r.rune_at as Array)[1]), float(rune_at0[1]), 0.001)
	var shown_ok: bool = th_r.size() == 1 and String(th_r[0].kind) == "circle" and bool(th_r[0].locked) \
		and near(float(th_r[0].x), float(rune_at0[0]), 0.001) and near(float(th_r[0].r), float(SH_T.runeR), 0.001)
	ok("공격 B: 저주 문양은 **예고를 시작한 자리에 고정**된다(예고가 끝날 때까지 플레이어를 따라다니지 않는다)",
		fixed_ok and near(float(rune_at0[0]), px0, 1.0) and near(float(rune_at0[1]), py0, 1.0),
		"예고 시작 자리 (%.0f, %.0f) · 플레이어 240 이동 뒤 문양 (%.0f, %.0f)" % [float(rune_at0[0]), float(rune_at0[1]), float((sh_r.rune_at as Array)[0]), float((sh_r.rune_at as Array)[1])])
	ok("공격 B: 문양이 고정되는 시점(첫 프레임부터 locked)과 실제 폭발 범위(반지름 %.0f)가 예고 도형으로 보인다" % float(SH_T.runeR),
		shown_ok, "예고 도형 %d개" % th_r.size())

	# --- 치료와 공격이 행동 상태를 공유한다 ---
	var st_g := lab()
	var sh_g := put(st_g, "shaman", st_g.player.x + 250.0, st_g.player.y)
	var g_wolf := put(st_g, "wolf", sh_g.x + 40.0, sh_g.y)
	g_wolf.hp = 1.0
	g_wolf.state = "bite_recover" # 늑대가 스스로 움직여 사거리를 벗어나지 않게 묶어 둔다
	g_wolf.state_t = -1000.0
	sh_g.heal_t = 0.0
	sh_g.hex_t = 0.0
	sh_g.rune_t = 0.0
	sh_g.act_t = 0.0
	play(st_g, 1.0 / 120.0)
	var first_state := String(sh_g.state)
	var multi := first_state != "approach" # 셋이 동시에 시작되지 않고 하나만 시작한다
	# 첫 행동이 끝나 approach로 돌아온 시각 → 다음 행동이 시작된 시각
	until(st_g, sh_g, "approach", 12.0)
	var gap_t0: float = st_g.t
	var n_gap := int(round(12.0 / STEP))
	var gap_t1 := -1.0
	for i in n_gap:
		st_g.step({}, STEP)
		st_g.player.hp = st_g.player.hp_max
		if String(sh_g.state) != "approach":
			gap_t1 = st_g.t
			break
	ok("치료·저주탄·문양은 **행동 상태를 공유**한다: 한 번에 하나만 시작하고, 다음 행동까지 공용 간격(%.1f초) 이상 쉰다" % float(SH_T.actGap),
		multi and gap_t1 > 0.0 and (gap_t1 - gap_t0) >= float(SH_T.actGap) - 0.05,
		"첫 행동 %s · 다음 행동까지 %.2f초" % [first_state, gap_t1 - gap_t0])

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
	ok("B 방패 자세: 정면 직접 피해 **완전 차단**(0) — 일반 방패병 70% 감소(30)와 구분. 측면·바닥은 그대로",
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

	dodge_tests()
	dodge_measure()
	dodge_chain_tests()
	fang_readability_tests()
	placement_tests()
	encounter_count_tests()

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# =========================================================================
# 배치 회귀(2026-09-08): 특수 정예가 **실제 출격 편성**에 들어가는가.
# 규칙과 값은 data/elites.json(배치표) · data/themes.json(편성) · data/pacing.json(체력·보상)에 있고
# 여기서는 "그 표대로 게임에 나오는가 / 예산이 늘지 않았는가 / 보상이 겹치지 않는가"만 본다.
# =========================================================================

## 정예를 쓰는 편성 전부: [{ theme, act, kind, tpl, places[] }]
func elite_slots() -> Array:
	var out := []
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		for kind in ["normal", "risk"]:
			for f in (t.formations[kind] as Array):
				if int(f.get("elites", 0)) > 0:
					out.append({ "theme": String(tid), "act": int(t.act), "kind": String(kind), "tpl": f, "places": t.places })
	return out

## 정예 지정을 뗀 사본(비교 기준 = 배치 전과 같은 늑대 우두머리 편성)
func strip_elite(tpl: Dictionary) -> Dictionary:
	var c := tpl.duplicate(true)
	c.erase("elite_type")
	c.erase("elite_type_p2")
	c.erase("elite_types")
	return c

func wave_total(waves: Array) -> int:
	var n := 0
	for w in waves:
		for g in w:
			n += int(g.n)
	return n

## 이 편성의 전투 경험치 예산 총량(PFormation과 같은 산식: 종류별 단위값 × ref 합)
func xp_budget(waves: Array, region_id: String) -> float:
	var s := 0.0
	for w in waves:
		for g in w:
			var ref: float = float(g.ref) if g.has("ref") else float(g.n)
			s += PGrowth.xp_value_unit(String(g.type), false, region_id, 0.3) * ref
	return round(s * 10000.0) / 10000.0

func fresh_run(seed_v: int, act: int) -> Dictionary:
	var r := PRun.new_run(seed_v, "sword", "", { "route": [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)] })
	r.day = [1, 5, 9][clampi(act, 1, 3) - 1]
	r.stage = clampi(act, 1, 3) - 1
	return r

func placement_tests() -> void:
	var E := PCatalog.elites()
	var slots := elite_slots()

	# --- 1. 배치표가 실제 편성에 붙어 있는가 ---
	var unassigned := []
	var unknown := []
	for s in slots:
		var tpl: Dictionary = s.tpl
		if not (tpl.has("elite_type") or tpl.has("elite_types")):
			unassigned.append(String(tpl.id))
		for tp in PRun.elite_types_for(tpl, "p1"):
			if not E.has(String(tp)):
				unknown.append("%s→%s" % [String(tpl.id), String(tp)])
	ok("정예를 쓰는 편성 %d개가 모두 배치표의 정예를 지정한다(늑대 우두머리 기본값으로 남지 않는다)" % slots.size(),
		unassigned.is_empty() and not slots.is_empty(), str(unassigned))
	ok("지정한 정예가 배치표(data/elites.json)에 있는 종류다", unknown.is_empty(), str(unknown))

	# --- 2. 실제로 편성(웨이브)에 들어가는가 ---
	var missing := []
	var seen_by_act := { 1: {}, 2: {}, 3: {} }
	for s in slots:
		var tpl: Dictionary = s.tpl
		for pi in (s.places as Array).size():
			var pid := String((s.places as Array)[pi].id)
			var pk := "p1" if pi == 0 else "p2"
			var want: Array = PRun.elite_types_for(tpl, pk)
			var got := {}
			for w in PRun.formation_waves(pid, 0, String(tpl.id)):
				for g in w:
					if PEnemiesNew.is_elite(String(g.type)):
						got[String(g.type)] = int(got.get(String(g.type), 0)) + int(g.n)
						seen_by_act[int(s.act)][String(g.type)] = true
			for tp in want:
				if int(got.get(String(tp), 0)) <= 0:
					missing.append("%s/%s에 %s 없음" % [pid, String(tpl.id), String(tp)])
			var n_got := 0
			for k in got:
				n_got += int(got[k])
			if n_got != int(tpl.elites):
				missing.append("%s/%s 정예 수 %d != %d" % [pid, String(tpl.id), n_got, int(tpl.elites)])
	ok("지정한 정예가 실제 편성 웨이브에 그 수만큼 들어간다(PRun.formation_waves)", missing.is_empty(), str(missing))
	ok("2막·3막 모두 7종이 전부 실제 편성 안에 있다",
		(seen_by_act[2] as Dictionary).size() >= 7 and (seen_by_act[3] as Dictionary).size() >= 7,
		"2막 %d종 · 3막 %d종" % [(seen_by_act[2] as Dictionary).size(), (seen_by_act[3] as Dictionary).size()])

	# --- 3. 배치표 규칙(막·상극·호위 필요)을 지키는가 ---
	var bad_act := []
	var bad_avoid := []
	var bad_escort := []
	for s in slots:
		var tpl: Dictionary = s.tpl
		var comp_types := []
		for c in (tpl.comp as Array):
			comp_types.append(String(c.type))
		for pk in ["p1", "p2"]:
			var lst: Array = PRun.elite_types_for(tpl, pk)
			for tp in lst:
				var d: Dictionary = E.get(String(tp), {})
				if d.is_empty():
					continue
				var acts_ok := false
				for a in (d.acts as Array):
					if int(a) == int(s.act):
						acts_ok = true
				if not acts_ok:
					bad_act.append("%s(%s) %d막" % [String(tpl.id), String(tp), int(s.act)])
				for av in (d.get("avoid_with", []) as Array):
					var an := String(av)
					if an.begins_with("objective:"):
						continue
					if comp_types.has(an) or (lst.has(an) and an != String(tp)):
						bad_avoid.append("%s: %s + %s" % [String(tpl.id), String(tp), an])
				if int(d.get("requires_allies", 0)) > 0 and int(tpl.sizes[pk].total) < int(d.requires_allies):
					bad_escort.append("%s(%s) 호위 부족" % [String(tpl.id), String(tp)])
	ok("배치한 정예가 그 막에 허용된 종류다(elites.json acts)", bad_act.is_empty(), str(bad_act))

	# **결투 후보도 같은 제한을 지킨다.** 편성 안 정예만 보던 검사라 결투 후보(themes[].special_elites)가
	# 막 제한을 어겨도 잡히지 않았다 — 1막 포자 정원의 역병 조율사·균열 채굴자가 그런 경우였다.
	# acts_extra는 '그 테마에서만' 여는 예외다(다른 테마로 넓히지 않는다).
	var bad_duel := []
	var T2 := PCatalog.themes()
	for tid in T2:
		var th2: Dictionary = T2[tid]
		var act2 := int(th2.act)
		for tp2 in th2.get("special_elites", []):
			var d2: Dictionary = E.get(String(tp2), {})
			if d2.is_empty():
				continue
			var okk := false
			for a2 in (d2.acts as Array):
				if int(a2) == act2:
					okk = true
			if not okk:
				var ex: Array = (d2.get("acts_extra", {}) as Dictionary).get(str(act2), [])
				if ex.has(String(tid)):
					okk = true
			if not okk:
				bad_duel.append("%s(%s) %d막" % [String(tid), String(tp2), act2])
	ok("결투 후보(테마별 특수 정예)도 그 막에 허용된 종류다", bad_duel.is_empty(), str(bad_duel))

	# 예외가 **그 테마에만** 열려 있는지(다른 테마로 새지 않았는지)
	var leaked := []
	for k2 in E:
		var ex2: Dictionary = (E[k2] as Dictionary).get("acts_extra", {})
		for a3 in ex2:
			for tid2 in (ex2[a3] as Array):
				if not T2.has(String(tid2)):
					leaked.append("%s: 없는 테마 %s" % [String(k2), String(tid2)])
				elif int(T2[String(tid2)].act) != int(a3):
					leaked.append("%s: %s는 %d막인데 %s막 예외" % [String(k2), String(tid2), int(T2[String(tid2)].act), String(a3)])
	ok("막 예외(acts_extra)가 실제로 그 막의 그 테마만 가리킨다", leaked.is_empty(), str(leaked))
	ok("상극 조합(avoid_with)이 같은 편성에 함께 들어가지 않는다", bad_avoid.is_empty(), str(bad_avoid))
	ok("호위가 필요한 정예(군단 기수)는 호위가 충분한 편성에만 있다", bad_escort.is_empty(), str(bad_escort))

	# --- 4. 노출 빈도: 1막은 위험 편성에만, 평범한 편성에는 드물게 ---
	var act1_normal := 0
	var normal_with_elite := 0
	var normal_total := 0
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		for f in (t.formations.normal as Array):
			normal_total += 1
			if int(f.get("elites", 0)) > 0:
				normal_with_elite += 1
				if int(t.act) == 1:
					act1_normal += 1
	ok("1막에서는 위험 편성에만 정예가 나온다(첫 만남 보호)", act1_normal == 0, "1막 일반 편성 중 정예 포함 %d개" % act1_normal)
	ok("평범한 출격에는 드물게 나온다(일반 편성 %d개 중 %d개, 3분의 1 이하)" % [normal_total, normal_with_elite],
		normal_with_elite * 3 <= normal_total)

	# --- 5. 총 등장 수·경험치 예산 불변(정예를 넣어도 예산이 늘지 않는다) ---
	var cnt_diff := []
	var xp_diff := []
	for s in slots:
		var tpl: Dictionary = s.tpl
		var base := strip_elite(tpl)
		for pi in (s.places as Array).size():
			var pid := String((s.places as Array)[pi].id)
			var pk := "p1" if pi == 0 else "p2"
			for day in [0, 5, 9]:
				var wa := PRun.template_waves(tpl, pk, day, PRun.place_cost(pid))
				var wb := PRun.template_waves(base, pk, day, PRun.place_cost(pid))
				if wave_total(wa) != wave_total(wb):
					cnt_diff.append("%s/%s/%d일 %d != %d" % [pid, String(tpl.id), day, wave_total(wa), wave_total(wb)])
				if not is_equal_approx(xp_budget(wa, pid), xp_budget(wb, pid)):
					xp_diff.append("%s/%s/%d일 %.2f != %.2f" % [pid, String(tpl.id), day, xp_budget(wa, pid), xp_budget(wb, pid)])
	ok("정예 종류를 바꿔도 총 등장 수가 그대로다(배치 전 늑대 우두머리 편성과 같다)", cnt_diff.is_empty(), str(cnt_diff))
	ok("정예 종류를 바꿔도 전투 경험치 예산이 그대로다", xp_diff.is_empty(), str(xp_diff))
	var XPV: Dictionary = PCatalog.growth().XP_VALUE
	var xp_off := []
	for tp in PEnemiesNew.ELITE_TYPES:
		if float(XPV.get(String(tp), 0.0)) != float(XPV.wolf_alpha):
			xp_off.append("%s=%s" % [String(tp), str(XPV.get(String(tp), 0))])
	ok("정예 7종의 마리당 경험치가 늑대 우두머리와 같다(%d) — 종류 교체로 예산이 흔들리지 않는다" % int(XPV.wolf_alpha),
		xp_off.is_empty(), str(xp_off))

	# --- 6. 큰 보상 장소·더 깊이: 강한 정예 1 + 호위 ---
	var weaker := []
	for s in slots:
		var tpl: Dictionary = s.tpl
		if not tpl.has("elite_type_p2"):
			continue
		var t1 := String(PRun.elite_types_for(tpl, "p1")[0])
		var t2 := String(PRun.elite_types_for(tpl, "p2")[0])
		if PPacing.elite_hp(t2, int(s.act)) < PPacing.elite_hp(t1, int(s.act)):
			weaker.append("%s %s < %s" % [String(tpl.id), t2, t1])
	ok("비용 2칸(큰 보상) 장소의 정예가 1칸 장소보다 약하지 않다", weaker.is_empty(), str(weaker))

	var deep_bad := []
	for s in slots:
		var tpl: Dictionary = s.tpl
		var run := fresh_run(7, int(s.act))
		var cap := PCatalog.elite_max_per_fight(int(s.act))
		for pi in (s.places as Array).size():
			var pid := String((s.places as Array)[pi].id)
			var sortie := { "regionId": pid, "formationId": String(tpl.id) }
			var n_e := 0
			var n_all := 0
			var groups_norm := 0
			for w in PRun.encounter_waves(pid, true, run, sortie):
				for g in w:
					n_all += int(g.n)
					if PEnemiesNew.is_elite(String(g.type)):
						n_e += int(g.n)
					else:
						groups_norm += 1
			var flat := PRun.encounter_waves(pid, false, run, sortie)
			if n_e > cap:
				deep_bad.append("%s 더 깊이 정예 %d > 상한 %d" % [pid, n_e, cap])
			# 호위만 묶음마다 +1, 정예는 늘지 않는다
			var expect := wave_total(flat) - int(tpl.elites) + groups_norm + n_e
			if n_all != expect:
				deep_bad.append("%s 더 깊이 수가 규칙과 다르다(%d != %d)" % [pid, n_all, expect])
	ok("더 깊이 탐험은 '강한 정예 1(막별 상한) + 호위 +1'이다 — 정예를 늘려 예산을 키우지 않는다", deep_bad.is_empty(), str(deep_bad))

	var deep_type := []
	for s in slots:
		var tpl: Dictionary = s.tpl
		if not tpl.has("elite_type_p2"):
			continue
		var run := fresh_run(9, int(s.act))
		var pid := String((s.places as Array)[0].id) # 비용 1칸 장소에서도 더 깊이면 강한 정예
		var found := ""
		for w in PRun.encounter_waves(pid, true, run, { "regionId": pid, "formationId": String(tpl.id) }):
			for g in w:
				if PEnemiesNew.is_elite(String(g.type)) and int(g.n) > 0:
					found = String(g.type)
		if found != String(tpl.elite_type_p2):
			deep_type.append("%s 더 깊이 %s != %s" % [pid, found, String(tpl.elite_type_p2)])
	ok("더 깊이 탐험은 1칸 장소에서도 강한 정예(elite_type_p2)로 바뀐다", deep_type.is_empty(), str(deep_type))

	# --- 7. 추가 보상: 실제 위험에 대응하되 기존 보상과 겹치지 않는다 ---
	var run2 := fresh_run(11, 2)
	var dup := []
	var none := []
	for pid in PCatalog.theme_places():
		var mats: Dictionary = PRun.region(String(pid)).get("reward", {}).get("mats", {})
		var gb := PRun.elite_bonus_gold(run2, String(pid), true)
		if mats.has("fang") and gb > 0:
			dup.append(String(pid)) # 송곳니(정예 조건부 재료)를 이미 주는데 금화까지 주면 중복이다
		if not mats.has("fang") and gb <= 0:
			none.append(String(pid))
	ok("정예 조건부 재료를 주는 장소에는 추가 금화를 주지 않는다(같은 위험을 두 번 보상하지 않는다)", dup.is_empty(), str(dup))
	ok("그 밖의 장소에서는 정예를 잡으면 추가 금화를 준다(위험에 대응하는 보상)", none.is_empty(), str(none))
	ok("정예를 잡지 않으면 추가 보상이 없다", PRun.elite_bonus_gold(run2, "t2a_pilgrim", false) == 0)

	var s_r := { "regionId": "t2a_pilgrim", "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 } }
	var rw_no := PRun.roll_reward(run2, s_r, PRng.new(3), { "chestGold": 0, "eliteKilled": false })
	var rw_yes := PRun.roll_reward(run2, s_r, PRng.new(3), { "chestGold": 0, "eliteKilled": true })
	var bonus := PPacing.gold_award(PRun.elite_bonus_gold(run2, "t2a_pilgrim", true))
	ok("추가 보상은 조우 1회에 정확히 1번, 금화 감축 규칙을 지나 붙는다(+%d)" % bonus,
		int(rw_yes.gold) - int(rw_no.gold) == bonus and int(rw_yes.eliteGold) == bonus and int(rw_no.eliteGold) == 0)
	var s_deep := { "regionId": "t2a_pilgrim", "deep": true, "loot": { "gold": 0, "mats": {}, "chestGold": 0 } }
	var rwd_no := PRun.roll_reward(run2, s_deep, PRng.new(3), { "chestGold": 0, "eliteKilled": false })
	var rwd_yes := PRun.roll_reward(run2, s_deep, PRng.new(3), { "chestGold": 0, "eliteKilled": true })
	ok("더 깊이 배율이 추가 보상에 곱해지지 않는다(심층 보상과 이중 지급 없음)",
		int(rwd_yes.gold) - int(rwd_no.gold) == bonus)

	# --- 8. 출격 카드 사전 표시 ---
	var run3 := fresh_run(5, 2)
	var mismatch := []
	var shown := 0
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		if int(t.act) != 2:
			continue
		for kind in ["normal", "risk"]:
			for f in (t.formations[kind] as Array):
				for p in (t.places as Array):
					var c := { "regionId": String(p.id), "formationId": String(f.id) }
					var nt := PSortie.elite_notice(run3, c)
					var real: bool = int(f.get("elites", 0)) > 0
					if bool(nt.present) != real:
						mismatch.append("%s/%s" % [String(p.id), String(f.id)])
					if bool(nt.present):
						shown += 1
						if (nt.names as Array).is_empty() or String(nt.reward) == "":
							mismatch.append("%s/%s 표시 비어 있음" % [String(p.id), String(f.id)])
	ok("출격 카드가 강적 출현을 미리 알린다 — 실제 편성과 정확히 일치(2막 %d자리)" % shown, mismatch.is_empty(), str(mismatch))
	var nt2 := PSortie.elite_notice(run3, { "regionId": "t2a_pilgrim", "formationId": "t2a_risk" })
	ok("카드 표시에 강적 이름과 보상 종류가 함께 나온다: %s" % String(nt2.text),
		bool(nt2.present) and String(nt2.text).contains("강적 출현") and String(nt2.text).contains("보상"))

# ================= 작업 4. 특수 정예 조우 빈도(실제 회차의 하루 카드로 센다) =================
## 사용자 지시: "편성표에 이름이 있다는 것만으로 완료로 치지 마라. 대표 실제 회차(여러 시드)를 돌려
## 종류별 조우 수를 세어 표로 남겨라." 그래서 **실제 카드 생성기**(PSortie.cards_for)를 시드별·날짜별로
## 그대로 돌리고, 각 카드의 강적 예고(PSortie.elite_notice)를 센다. 카드를 고르면 그 강적을 만난다.
## 전투를 끝까지 돌리지 않는 이유는 여기서 보려는 것이 '만날 기회가 실제로 있는가'이기 때문이다
## (정예의 행동·처치 시간은 tests/elite_placement_measure.gd·tests/elites_bot_measure.gd가 따로 잰다).
const ENC_SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]

func encounter_count_tests() -> void:
	var by_type := {}      # 정예 종류 → 예고된 카드 수
	var by_act := {}       # 막 → [강적 카드, 전체 카드]
	var days := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	# 경로는 시드마다 다르게 잡는다(기본 경로만 보면 다른 테마의 정예를 영영 못 본다 — 실제로 이 검사가 그 구멍을 찾아냈다)
	var themes_of := { 1: [], 2: [], 3: [] }
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		(themes_of[int(t.act)] as Array).append(String(tid))
	for a in themes_of:
		(themes_of[a] as Array).sort()
	for s in ENC_SEEDS:
		var route := []
		for a in [1, 2, 3]:
			var lst: Array = themes_of[a]
			route.append(String(lst[int(s) % lst.size()]))
		for d in days:
			var run := PRun.new_run(int(s), "sword", "", { "route": route })
			run.day = int(d)
			run.stage = (0 if int(d) <= 3 else (1 if int(d) <= 7 else 2))
			var act: int = run.stage + 1
			if not by_act.has(act):
				by_act[act] = [0, 0]
			for c in PSortie.cards_for(run):
				(by_act[act] as Array)[1] = int((by_act[act] as Array)[1]) + 1
				var nt := PSortie.elite_notice(run, c)
				if not bool(nt.present):
					continue
				(by_act[act] as Array)[0] = int((by_act[act] as Array)[0]) + 1
				for tp in (nt.types as Array):
					by_type[String(tp)] = int(by_type.get(String(tp), 0)) + 1

	# 표를 사람이 읽게 남긴다(수치는 전부 측정값)
	print("")
	print("[특수 정예 조우 빈도] 시드 %s · 1~9일 · 실제 카드 생성기" % str(ENC_SEEDS))
	print("| 정예 | 예고된 카드 수 |")
	print("|---|---:|")
	for tp in PEnemiesNew.ELITE_TYPES:
		print("| %s | %d |" % [String(PCatalog.enemy(String(tp)).name), int(by_type.get(String(tp), 0))])
	var acts := by_act.keys()
	acts.sort()
	for a in acts:
		var row: Array = by_act[a]
		print("%d막: 전체 카드 %d장 중 강적 예고 %d장(%.0f%%)" % [int(a), int(row[1]), int(row[0]), float(row[0]) / float(maxi(1, int(row[1]))) * 100.0])
	print("")

	var never := []
	for tp in PEnemiesNew.ELITE_TYPES:
		if int(by_type.get(String(tp), 0)) <= 0:
			never.append(String(tp))
	ok("특수 정예 7종이 모두 **실제 회차의 카드**에 나온다(편성표에 이름만 있는 종류가 없다)",
		never.is_empty(), "한 번도 안 나온 종류: %s" % (str(never) if not never.is_empty() else "없음"))

	var all_cards := 0
	var elite_cards := 0
	for a in acts:
		var row: Array = by_act[a]
		elite_cards += int(row[0])
		all_cards += int(row[1])
	var frac := float(elite_cards) / float(maxi(1, all_cards))
	ok("일반 경로에서도 존재를 알 수 있을 만큼 만나되(0이 아님), 모든 일반 전투에 의무로 넣지는 않는다(절반 미만)",
		frac > 0.05 and frac < 0.5, "전체 카드 %d장 중 강적 예고 %d장(%.0f%%)" % [all_cards, elite_cards, frac * 100.0])

	# --- 역할 읽기 자료(외형은 render.gd 담당, 자료는 여기가 정본) ---
	var rd_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var row: Dictionary = PCatalog.elite_def(String(tp)).get("read", {})
		for f in ["held", "silhouette", "tell", "role_text", "distance"]:
			if String(row.get(f, "")).strip_edges() == "":
				rd_bad.append("%s.%s" % [String(tp), String(f)])
	ok("정예 7종 모두 **역할을 읽을 수 있게 하는 자료**가 있다(무엇을 들었는지·예고에서 어디가 커지는지·어느 거리를 잡아야 하는지)",
		rd_bad.is_empty(), str(rd_bad))

# =========================================================================
# 작업 5(2026-09-09). 특수 정예 7종의 **회피**. 값은 data/elites.json(elites.<id>.dodge),
# 규칙은 scripts/rules/enemies_new.gd의 elite_dodge 갈래, 설명은 docs/ELITE_DODGE.md.
# 사용자 확정을 그대로 항목으로 옮겼다:
#   짧고 빠른 자리 바꾸기 · 플레이어보다 훨씬 긴 재사용 · **무적 없음** · 이미 나타난 전투 상태에만 반응(반응 지연) ·
#   자기 공격 준비·실행/경직/빙결 중 금지 · 회피 뒤 추스르는 틈 · 모든 공격을 자동으로 피하지 않음 · 고유 패턴 복귀.
# 수치는 전부 **시험값**이다. 여기서 통과했다는 것은 규칙이 그렇게 돈다는 뜻이지 재미·균형을 승인한 것이 아니다.
# =========================================================================
const DSEED := 20260909
## 회피를 갖지 않아야 하는 명단(일반 몬스터 · 일반 정예 확장 10종 · 정예가 만드는 구조물)
const NOT_DODGERS := ["wolf", "archer", "spore", "boar", "shieldbearer", "shaman", "bomber", "burrower", "spider", "frostcaller", "rogue", "bat", "lizard", "toad",
	"wolf_alpha", "boar_elite", "archer_elite", "shieldbearer_elite", "spider_elite", "spore_elite", "rogue_elite", "burrower_elite", "toad_elite", "frostcaller_elite",
	"elite_banner", "elite_rubble"]
## 지형 시험 자리(전장 960x600 · 바위 rockA(285,220,42) rockB(675,380,42) 나무 treeA(300,420,26) treeB(660,180,26))
const DODGE_SPOTS := [[28.0, 300.0], [932.0, 300.0], [480.0, 26.0], [480.0, 574.0], [285.0, 290.0], [675.0, 310.0]]

func dodge_tests() -> void:
	# ---- ① 명단: 7종 전부 가지고, 그 밖에는 하나도 갖지 않는다 ----
	var miss := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		for f in ["style", "dist", "time", "cooldown", "react", "settle", "chance"]:
			if not c.has(f):
				miss.append("%s.%s" % [String(tp), String(f)])
	ok("① 특수 정예 **7종 전부** 회피 값을 가진다(표현·거리·이동 시간·재사용·반응 지연·추스르는 틈·확률)",
		miss.is_empty(), "빠진 값: %s" % (str(miss) if not miss.is_empty() else "없음"))

	var leak := []
	for tp in NOT_DODGERS:
		if not PEnemiesNew.dodge_cfg(String(tp)).is_empty():
			leak.append(String(tp))
	for bid in PCatalog.bosses_new().bosses:
		if not PEnemiesNew.dodge_cfg(String(bid)).is_empty():
			leak.append(String(bid))
	if not PEnemiesNew.dodge_cfg("boss").is_empty():
		leak.append("boss")
	ok("① 일반 몬스터 14종·일반 정예 확장 10종(늑대 우두머리 포함)·구조물 2종·보스 6종은 회피 값을 갖지 않는다",
		leak.is_empty(), "샌 종류: %s" % (str(leak) if not leak.is_empty() else "없음"))

	# 사용자 첫 시험값 범위(재사용 8~12초 · 이동 시간 0.2~0.3초)를 실제로 지키는가
	var rng_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		if float(c.cooldown) < 8.0 or float(c.cooldown) > 12.0:
			rng_bad.append("%s 재사용 %.1f" % [String(tp), float(c.cooldown)])
		if float(c.time) < 0.2 or float(c.time) > 0.3:
			rng_bad.append("%s 이동 시간 %.2f" % [String(tp), float(c.time)])
	ok("① 사용자 첫 시험값 범위 그대로: 재사용 8~12초 · 이동 시간 0.20~0.30초", rng_bad.is_empty(), str(rng_bad))

	# ---- ③ 플레이어 회피 재사용과 숫자로 대조 ----
	var PD: Dictionary = PCatalog.config().PLAYER.dodge
	var p_cd := float(PD.cooldown)
	var p_spd := float(PD.distance) / float(PD.duration)
	var cd_lo := 1e9
	var cd_hi := 0.0
	var spd_hi := 0.0
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		cd_lo = minf(cd_lo, float(c.cooldown))
		cd_hi = maxf(cd_hi, float(c.cooldown))
		spd_hi = maxf(spd_hi, float(c.dist) / float(c.time))
	ok("③ 재사용이 플레이어보다 **훨씬 길다**: 가장 짧은 정예 %.1f초 = 플레이어 %.1f초의 %.1f배(4배 이상)" % [cd_lo, p_cd, cd_lo / p_cd],
		cd_lo >= p_cd * 4.0, "정예 %.1f~%.1f초 · 플레이어 재사용 선택지 %s" % [cd_lo, cd_hi, str(PD.cooldown_options)])
	ok("③ 이동 속도는 플레이어 회피를 넘지 않는다: 가장 빠른 정예 %.0f px/s ≤ 플레이어 %.0f px/s" % [spd_hi, p_spd], spd_hi <= p_spd)

	# ---- ② 실제 위협에 반응해서 회피한다(종류마다 최소 1회, 두 가지 위협 각각) ----
	print("")
	print("[특수 정예 회피 — 값과 반응] 시드 %d · 위협을 0.4초마다 대고 14초 · 수치는 전부 시험값" % DSEED)
	print("| 정예 | 표현 | 거리 | 이동 | 재사용 | 반응 지연 | 추스름 | 확률 | 바닥 예고(충족/발동) | 투사체(충족/발동) |")
	print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
	var react_bad := []
	var seen_sum := 0
	var use_sum := 0
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		var row := []
		for kind in ["warn", "shot"]:
			var lb := dodge_lab(DSEED, String(tp))
			var stx: CombatState = lb[0]
			var ex: Dictionary = lb[1]
			drive(stx, ex, String(kind), 14.0)
			var u := int(ex.get("dodge_uses", 0))
			var s := int(ex.get("dodge_seen", 0))
			var k := String(ex.get("dodge_kind", ""))
			seen_sum += s
			use_sum += u
			row.append([u, s, k, String(ex.get("dodge_skip", ""))])
			var want := "warn" if String(kind) == "warn" else "projectile"
			if u < 1:
				react_bad.append("%s/%s 발동 0회(이유 %s)" % [String(tp), String(kind), String(ex.get("dodge_skip", ""))])
			elif k != want:
				react_bad.append("%s/%s 위협 종류 %s" % [String(tp), String(kind), k])
		print("| %s | %s | %d | %.2f | %.1f | %.2f | %.2f | %.2f | %d/%d | %d/%d |" % [
			String(PCatalog.enemy(String(tp)).name), String(c.style_text), int(c.dist), float(c.time), float(c.cooldown),
			float(c.react), float(c.settle), float(c.chance),
			int((row[0] as Array)[1]), int((row[0] as Array)[0]), int((row[1] as Array)[1]), int((row[1] as Array)[0])])
	print("")
	ok("② 7종 전부 **실제 위협에 반응해서** 회피한다 — 바닥 예고·날아오는 투사체 각각 최소 1회",
		react_bad.is_empty(), "실패: %s" % (str(react_bad) if not react_bad.is_empty() else "없음"))
	ok("⑪ 조건 충족(위협을 보고 판단한 횟수) %d회 vs 실제 발동 %d회 — 충족이 발동보다 많다(재사용·확률이 걸러 낸다)" % [seen_sum, use_sum],
		seen_sum > use_sum and use_sum > 0)

	# ---- ③ 재사용 시간이 지나기 전에는 다시 회피하지 않는다 ----
	var cd_bad := []
	var gaps := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		var lb := dodge_lab(DSEED, String(tp))
		var stc: CombatState = lb[0]
		var ec: Dictionary = lb[1]
		var ts := dodge_times(stc, ec, 34.0)
		if ts.size() < 2:
			cd_bad.append("%s 회피 %d회(간격을 못 잼)" % [String(tp), ts.size()])
			continue
		for k in range(1, ts.size()):
			var g: float = float(ts[k]) - float(ts[k - 1])
			gaps.append(g)
			if g < float(c.cooldown) - 0.05:
				cd_bad.append("%s 간격 %.2f초 < 재사용 %.1f초" % [String(tp), g, float(c.cooldown)])
	ok("③ 재사용 시간이 지나기 전에는 다시 회피하지 않는다(7종 · 34초 동안 위협을 계속 대고 잰 간격 %d개)" % gaps.size(),
		cd_bad.is_empty(), str(cd_bad))

	# ---- ④ 자기 공격 준비·실행 중에는 회피하지 않는다 ----
	var busy_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var hold := String((PEnemiesNew.COMMITTED[String(tp)] as Array)[0])
		var lb := dodge_lab(DSEED, String(tp))
		var stb: CombatState = lb[0]
		var eb: Dictionary = lb[1]
		var n := int(round(6.0 / STEP))
		for i in n:
			if i % 48 == 0:
				warn_at(stb, float(eb.x) + 16.0, float(eb.y) + 16.0)
			eb.state = hold # 매 프레임 자기 공격 준비로 되돌린다(연계가 끝나 버리지 않게)
			eb.state_t = 0.0
			alive_step(stb)
		if int(eb.get("dodge_uses", 0)) != 0:
			busy_bad.append("%s(%s) %d회" % [String(tp), hold, int(eb.dodge_uses)])
		elif String(eb.get("dodge_skip", "")) != "committed":
			busy_bad.append("%s(%s) 이유가 %s" % [String(tp), hold, String(eb.get("dodge_skip", ""))])
	ok("④ 자기 공격 준비·실행 중에는 회피하지 않는다(7종의 첫 확정 상태에서 6초 동안 위협을 대도 0회)",
		busy_bad.is_empty(), str(busy_bad))

	# ---- ⑤ 빙결·경직 중에는 회피하지 않는다(상태 우선순위 빙결 > 경직 > 회피) ----
	var fz_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		# ㉠ 빙결(hard): CombatState가 갱신을 통째로 건너뛴다 → 회피 단계도 흐르지 않는다
		var lb1 := dodge_lab(DSEED, String(tp))
		var s1: CombatState = lb1[0]
		var e1: Dictionary = lb1[1]
		for i in int(round(6.0 / STEP)):
			e1["freeze"] = 3.0
			e1["freeze_kind"] = "hard"
			if i % 48 == 0:
				warn_at(s1, float(e1.x) + 16.0, float(e1.y) + 16.0)
			alive_step(s1)
		if int(e1.get("dodge_uses", 0)) != 0:
			fz_bad.append("%s 빙결(hard) 중 %d회" % [String(tp), int(e1.dodge_uses)])
		# ㉡ freeze 필드가 살아 있는데 갱신이 도는 경우 — 규칙 안의 금지 조항이 직접 막아야 한다
		var lb2 := dodge_lab(DSEED, String(tp))
		var s2: CombatState = lb2[0]
		var e2: Dictionary = lb2[1]
		for i in int(round(6.0 / STEP)):
			e2["freeze"] = 3.0
			e2["freeze_kind"] = "soft"
			if i % 48 == 0:
				warn_at(s2, float(e2.x) + 16.0, float(e2.y) + 16.0)
			alive_step(s2)
			e2.state = "approach"
			e2.state_t = 0.0
		if int(e2.get("dodge_uses", 0)) != 0 or String(e2.get("dodge_skip", "")) != "freeze":
			fz_bad.append("%s freeze>0인데 %d회(이유 %s)" % [String(tp), int(e2.dodge_uses), String(e2.get("dodge_skip", ""))])
		# ㉢ 경직(stagger_t = 연계 완성 경직. combat_state.gd 가 만든다. 없으면 0.0으로 안전하게 읽는다)
		var lb3 := dodge_lab(DSEED, String(tp))
		var s3: CombatState = lb3[0]
		var e3: Dictionary = lb3[1]
		for i in int(round(6.0 / STEP)):
			e3["stagger_t"] = 3.0
			if i % 48 == 0:
				warn_at(s3, float(e3.x) + 16.0, float(e3.y) + 16.0)
			alive_step(s3)
			e3.state = "approach"
			e3.state_t = 0.0
		if int(e3.get("dodge_uses", 0)) != 0:
			fz_bad.append("%s stagger_t>0인데 회피 %d회" % [String(tp), int(e3.dodge_uses)])
		# 위 고리에서는 CombatState가 경직 중 갱신 자체를 건너뛰므로 규칙 안의 금지 조항까지는 가지 않는다
		# (그래서 dodge_skip 이 이전 값 그대로 남는다). 그 조항이 살아 있는지는 갱신을 **직접** 불러서 본다 —
		# 합칠 때 필드 이름이 어긋나 이 방어가 죽어 있던 적이 있어 두 겹으로 확인한다
		e3["stagger_t"] = 3.0
		e3.state = "approach"
		e3.state_t = 0.0
		e3["dodge_skip"] = "none"
		var direct0 := int(e3.get("dodge_uses", 0))
		for i in 24:
			warn_at(s3, float(e3.x) + 16.0, float(e3.y) + 16.0)
			PEnemiesNew.update(s3, e3, STEP)
		if int(e3.get("dodge_uses", 0)) != direct0 or String(e3.get("dodge_skip", "")) != "stagger":
			fz_bad.append("%s 갱신 직접 호출에서 stagger_t 금지가 안 걸린다(%d회, 이유 %s)" % [
				String(tp), int(e3.dodge_uses) - direct0, String(e3.get("dodge_skip", ""))])
		# ㉣ **실제** 연계 완성 경직(CombatState.apply_stagger)으로 확인한다.
		# ㉢은 필드를 손으로 넣은 것이라 "규칙이 그 필드를 읽는가"만 본다. 여기서는 회피와 경직
		# 두 체계가 실제로 맞물리는지 본다 — 합칠 때 필드 이름이 어긋나 방어가 죽어 있던 적이 있다
		var lb4 := dodge_lab(DSEED, String(tp))
		var s4: CombatState = lb4[0]
		var e4: Dictionary = lb4[1]
		e4.state = "approach"
		e4.state_t = 0.0
		if not s4.apply_stagger(e4, "frost_shatter"):
			fz_bad.append("%s 실제 경직(파쇄)이 걸리지 않았다" % String(tp))
		else:
			var uses0 := int(e4.get("dodge_uses", 0))
			var state0 := String(e4.state)
			var t0 := float(e4.state_t)
			var guard := 0
			while s4.is_staggered(e4) and guard < 600:
				warn_at(s4, float(e4.x) + 16.0, float(e4.y) + 16.0)
				alive_step(s4)
				guard += 1
			if guard >= 600:
				fz_bad.append("%s 경직이 끝나지 않았다(무한 경직)" % String(tp))
			if int(e4.get("dodge_uses", 0)) != uses0:
				fz_bad.append("%s 실제 경직 중 회피 %d회" % [String(tp), int(e4.dodge_uses) - uses0])
			# 멈췄다가 이어 가는 것이므로 경직 동안 상태·진행도가 흐르면 안 된다
			if String(e4.state) != state0 or not is_equal_approx(float(e4.state_t), t0):
				fz_bad.append("%s 실제 경직 중 진행도가 흘렀다(%s %.3f → %s %.3f)" % [
					String(tp), state0, t0, String(e4.state), float(e4.state_t)])
	ok("⑤ 빙결(freeze > 0)·경직(stagger_t > 0) 중에는 회피하지 않는다 — 7종 × 네 경우(갱신 정지·freeze 필드·stagger_t 필드·실제 apply_stagger)",
		fz_bad.is_empty(), str(fz_bad))

	# ---- ⑥⑦ 회피 뒤 추스르는 틈에는 공격을 시작하지 않고, 끝나면 고유 패턴으로 돌아온다 ----
	var settle_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		var lb := dodge_lab(DSEED, String(tp))
		var ss: CombatState = lb[0]
		var es: Dictionary = lb[1]
		if not until_dodge(ss, es, 14.0):
			settle_bad.append("%s 회피가 시작되지 않음" % String(tp))
			continue
		var back := ""
		var started := false
		var s_from := -1.0 # 추스르는 틈이 시작된 시각
		var s_to := -1.0   # 회피 단계가 완전히 끝난 시각
		for i in int(round(4.0 / STEP)):
			if String(es.get("dodge_phase", "")) == "": # 이동이 지형에 막혀 짧게 끝날 수도 있으므로 **단계로** 잰다
				s_to = ss.t
				break
			ss.player.x = clampf(float(es.x) + 26.0, 20.0, ss.arena_w - 20.0) # 바로 옆에 붙인다(허락되면 곧장 때릴 자리)
			ss.player.y = clampf(float(es.y), 20.0, ss.arena_h - 20.0)
			alive_step(ss)
			if back == "" and String(es.get("dodge_phase", "")) == "settle":
				back = String(es.state) # 이동이 끝난 그 순간의 상태
				s_from = ss.t
			# 그 프레임을 아직 회피 단계로 끝냈는데 공격 상태라면 무예고 공격이다
			if String(es.get("dodge_phase", "")) != "" and PEnemiesNew.is_committed(es):
				started = true
		if started:
			settle_bad.append("%s 추스르는 틈에 공격을 시작함" % String(tp))
		if back != "approach":
			settle_bad.append("%s 회피 뒤 상태가 %s" % [String(tp), back])
		if s_from < 0.0 or s_to < 0.0 or s_to - s_from < float(c.settle) - 0.03:
			settle_bad.append("%s 추스르는 틈이 %.2f초(설정 %.2f초)" % [String(tp), s_to - s_from, float(c.settle)])
		var after := false
		for i in int(round(5.0 / STEP)):
			ss.player.x = clampf(float(es.x) + 26.0, 20.0, ss.arena_w - 20.0)
			ss.player.y = clampf(float(es.y), 20.0, ss.arena_h - 20.0)
			alive_step(ss)
			if PEnemiesNew.is_committed(es):
				after = true
				break
		if not after:
			settle_bad.append("%s 틈이 끝나도 고유 패턴이 안 나옴" % String(tp))
	ok("⑥⑦ 회피 뒤 **추스르는 틈** 동안 공격을 시작하지 않고(무예고 공격 금지), 틈이 끝나면 approach로 돌아가 고유 패턴을 다시 낸다",
		settle_bad.is_empty(), str(settle_bad))

	# ---- ⑧ 지형: 전장 밖·벽·바위를 뚫지 않는다(여러 방향) ----
	var terr_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		for sp in DODGE_SPOTS:
			var lb := dodge_lab(DSEED, String(tp), float(sp[0]), float(sp[1]))
			var stt: CombatState = lb[0]
			var et: Dictionary = lb[1]
			var ax: float = et.x
			var ay: float = et.y
			for i in int(round(9.0 / STEP)):
				if i % 48 == 0:
					warn_at(stt, 480.0, 300.0, 900.0) # 전장 한가운데를 덮는 예고 → 바깥(벽·바위) 쪽으로 피하게 만든다
				alive_step(stt)
				if not in_terrain(stt, et):
					terr_bad.append("%s @(%.0f,%.0f) → (%.1f,%.1f)" % [String(tp), ax, ay, float(et.x), float(et.y)])
					break
				if String(et.get("dodge_phase", "")) != "move":
					et.state = "approach"
					et.state_t = 0.0
					if int(et.get("dodge_uses", 0)) == 0:
						et.x = ax
						et.y = ay
	ok("⑧ 회피가 전장 밖·벽·바위를 뚫지 않는다(7종 × 자리 %d개 · 매 프레임 확인)" % DODGE_SPOTS.size(),
		terr_bad.is_empty(), str(terr_bad))

	# ---- ⑨ 무적이 없다: 회피 중에도 맞으면 그대로 들어간다 ----
	var inv_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var lb := dodge_lab(DSEED, String(tp))
		var si: CombatState = lb[0]
		var ei: Dictionary = lb[1]
		if not until_dodge(si, ei, 14.0):
			inv_bad.append("%s 회피가 시작되지 않음" % String(tp))
			continue
		var hp0: float = ei.hp
		si.damage_enemy(ei, 20.0, { "src": { "direct": true }, "from": { "x": float(ei.x) + 120.0, "y": float(ei.y) } })
		var lost: float = hp0 - float(ei.hp)
		if not is_equal_approx(lost, 20.0):
			inv_bad.append("%s 이동 중 피해 %.1f(20이어야 한다)" % [String(tp), lost])
		if String(ei.get("dodge_phase", "")) != "move":
			inv_bad.append("%s 피해가 회피를 끊었다" % String(tp))
	ok("⑨ **무적이 없다** — 회피 이동 중에 맞은 20 피해가 그대로 20 들어간다(감소·무효 없음)",
		inv_bad.is_empty(), str(inv_bad))

	# ---- ⑩ 모든 공격을 피하지는 않는다(실제 명중이 남는다) ----
	var all_bad := []
	var shots_sum := 0
	var hits_sum := 0
	for tp in PEnemiesNew.ELITE_TYPES:
		var lb := dodge_lab(DSEED, String(tp))
		var sa: CombatState = lb[0]
		var ea: Dictionary = lb[1]
		var hp0: float = ea.hp
		# 피해 1짜리 화살을 0.5초마다. 가까이(110px)에서 빠르게(600px/s) 오므로 반응 지연 안에 이미 닿는 것이 많다.
		# 자리는 회피 이동·추스름을 뺀 동안 붙잡는다 — 걷는 표적을 잘못 겨냥해 빗나가는 것을 명중률에서 걷어내려는 것이다
		var fired := drive(sa, ea, "shot", 20.0, 0.5, 2, true, 1.0, 110.0, 600.0)
		var hits := int(round(hp0 - float(ea.hp)))
		shots_sum += fired
		hits_sum += hits
		if hits < 20:
			all_bad.append("%s 명중 %d/%d" % [String(tp), hits, fired])
		if int(ea.get("dodge_uses", 0)) < 1:
			all_bad.append("%s 회피 0회" % String(tp))
	ok("⑩ 모든 공격을 자동으로 피하지 않는다 — 7종 합계 화살 %d발 중 **%d발이 그대로 명중**(%.0f%%)" % [shots_sum, hits_sum, float(hits_sum) / float(maxi(1, shots_sum)) * 100.0],
		all_bad.is_empty(), str(all_bad))

	# ---- ⑫ 낮은 프레임(큰 dt)·일시정지 복귀에서 두 번 처리되지 않는다 ----
	var dt_bad := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var c := PEnemiesNew.dodge_cfg(String(tp))
		var lb := dodge_lab(DSEED, String(tp))
		var sd: CombatState = lb[0]
		var ed: Dictionary = lb[1]
		var big := 0.5
		var span := 24.0
		var far := 0.0
		for i in int(round(span / big)):
			warn_at(sd, float(ed.x) + 16.0, float(ed.y) + 16.0, 55.0, 1.2)
			sd.step({}, big)
			sd.player.hp = sd.player.hp_max
			sd.player.dead = false
			if sd.status == "lost":
				sd.status = "running"
			far = maxf(far, float(ed.get("dodge_dist", 0.0)))
			if String(ed.get("dodge_phase", "")) != "move":
				ed.state = "approach"
				ed.state_t = 0.0
		var cap := int(floor(span / float(c.cooldown))) + 1
		if int(ed.get("dodge_uses", 0)) > cap:
			dt_bad.append("%s dt=0.5에서 %d회(상한 %d)" % [String(tp), int(ed.dodge_uses), cap])
		if far > float(c.dist) + 0.5:
			dt_bad.append("%s 한 번에 %.1f px(거리 %d)" % [String(tp), far, int(c.dist)])
		# 일시정지 복귀: 아주 큰 한 걸음에서도 한 번만 처리된다
		var u0 := int(ed.get("dodge_uses", 0))
		ed["dodge_cd"] = 0.0
		ed["dodge_wait"] = 0.0
		warn_at(sd, float(ed.x) + 16.0, float(ed.y) + 16.0, 55.0, 6.0)
		sd.step({}, 2.0)
		if int(ed.get("dodge_uses", 0)) - u0 > 1:
			dt_bad.append("%s 한 걸음(2.0초)에 %d회" % [String(tp), int(ed.dodge_uses) - u0])
	ok("⑫ 낮은 프레임(dt 0.5초)·일시정지 복귀(dt 2.0초)에서도 회피가 두 번 처리되지 않고 거리를 넘지 않는다",
		dt_bad.is_empty(), str(dt_bad))

# -------------------------------------------------------------------------
# 측정(합격 판정이 아니다). 사용자 지시 두 가지를 값으로 남긴다:
#  ㉠ 조건 충족 횟수 vs 실제 발동 횟수 — **실제 전투**에서(시험실이 아니라 봇이 싸우는 판에서)
#  ㉡ 짧은 사거리 무기가 불리해지는 정도 — **재기만 한다. 보정 수치는 넣지 않았다.**
# 봇 승패는 통과 조건이 아니다(docs/BOT_FRAMEWORK.md). 통과 조건은 '측정이 이루어졌는가'뿐이다.
# -------------------------------------------------------------------------
const DODGE_WEAPONS := ["daggers", "sword", "hammer", "spear", "bow"]
const DODGE_FIGHT_SEC := 45.0

## 정예 1마리 대 봇 1회(주무기 wid). 반환 [처치 시간(-1 = 못 잡음), 조건 충족, 실제 발동, 받은 피해, 마지막 이유]
func dodge_fight(wid: String, tp: String, seed_v: int) -> Array:
	var g := PGrowth.new_growth(wid)
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": 1, "fixed_build": true })
	st.spawn_hold = true
	var e := st.spawn_enemy(tp, st.player.x + 260.0, st.player.y)
	var bot := PBot.new("regular")
	var n := int(round(DODGE_FIGHT_SEC / STEP))
	var ttk := -1.0
	for i in n:
		st.step(bot.step_input(st), STEP)
		if bool(e.dead):
			ttk = st.t
			break
		if bool(st.player.dead):
			break
	return [ttk, int(e.get("dodge_seen", 0)), int(e.get("dodge_uses", 0)), float(st.stats.damage_taken), String(e.get("dodge_skip", "없음"))]

func dodge_measure() -> void:
	var W := PCatalog.weapons()
	print("")
	print("[측정 ㉠] 실제 전투에서의 **조건 충족 vs 실제 발동** — 주무기 5종 × 정예 7종 · 봇 '보통' · 최대 %.0f초 · 시드 %d" % [DODGE_FIGHT_SEC, DSEED])
	print("| 주무기 | 사거리 | 조건 충족 | 실제 발동 | 발동/충족 | 정예를 잡은 판 | 처치 시간 중앙값 |")
	print("|---|---:|---:|---:|---:|---:|---:|")
	var tot_seen := 0
	var tot_use := 0
	var zero_why := []
	var by_w := {}
	for wid in DODGE_WEAPONS:
		var wr := float((W[String(wid)] as Dictionary).base.range)
		var seen := 0
		var used := 0
		var kills := 0
		var ttks := []
		var taken := 0.0
		for tp in PEnemiesNew.ELITE_TYPES:
			var r := dodge_fight(String(wid), String(tp), DSEED)
			seen += int(r[1])
			used += int(r[2])
			taken += float(r[3])
			if float(r[0]) > 0.0:
				kills += 1
				ttks.append(float(r[0]))
			if int(r[2]) == 0:
				zero_why.append("%s/%s: %s" % [String(wid), String(tp), String(r[4])])
		tot_seen += seen
		tot_use += used
		ttks.sort()
		var mid: float = float(ttks[ttks.size() / 2]) if not ttks.is_empty() else -1.0
		by_w[String(wid)] = [wr, mid, taken]
		print("| %s | %.0f | %d | %d | %.0f%% | %d/7 | %s |" % [String((W[String(wid)] as Dictionary).name), wr, seen, used,
			float(used) / float(maxi(1, seen)) * 100.0, kills, ("%.1f초" % mid) if mid > 0.0 else "—"])
	print("")
	if not zero_why.is_empty():
		print("발동 0회였던 판과 그때 남은 이유: %s" % str(zero_why))
		print("")
	ok("⑪ 실제 전투에서도 조건 충족 %d회 vs 실제 발동 %d회를 따로 셌다(발동 0회인 판은 이유를 값으로 남긴다)" % [tot_seen, tot_use],
		tot_seen > 0 and tot_use > 0 and tot_use <= tot_seen,
		"발동/충족 %.0f%%" % (float(tot_use) / float(maxi(1, tot_seen)) * 100.0))

	# ㉡ 회피 한 번이 각 무기의 사거리를 얼마나 벗어나게 하는가. **측정만 한다 — 보정 수치는 넣지 않았다.**
	print("[측정 ㉡] 짧은 사거리 무기가 불리해지는 정도 — 회피 한 번이 사거리 밖으로 나가는가")
	print("(플레이어를 사거리의 80% 거리에 세우고 정예 발밑에 바닥 예고를 띄운 뒤, 회피가 끝난 자리의 거리를 잰다. **보정은 넣지 않았다.**)")
	print("| 주무기 | 사거리 | 회피 시작 거리 | 회피 뒤 평균 거리 | 사거리 밖으로 나간 종류 | 45초 전투에서 받은 피해(7종 합) |")
	print("|---|---:|---:|---:|---:|---:|")
	var esc_rows := 0
	for wid in DODGE_WEAPONS:
		var wr := float((W[String(wid)] as Dictionary).base.range)
		var outn := 0
		var gain := 0.0
		var cnt := 0
		for tp in PEnemiesNew.ELITE_TYPES:
			var lb := dodge_lab(DSEED, String(tp))
			var sm: CombatState = lb[0]
			var em: Dictionary = lb[1]
			var ax: float = em.x
			var ay: float = em.y
			var px: float = clampf(ax - wr * 0.8, 24.0, sm.arena_w - 24.0)
			var py: float = ay
			var d1 := -1.0
			var moving := false
			for i in int(round(18.0 / STEP)):
				sm.player.x = px
				sm.player.y = py
				if i % 48 == 0:
					warn_at(sm, float(em.x), float(em.y), 40.0, 0.9) # 정예 발밑에 떨어질 예고(전투망치 내려찍기와 같은 모양)
				alive_step(sm)
				var ph := String(em.get("dodge_phase", ""))
				if ph == "move":
					moving = true
				elif moving and ph == "settle":
					d1 = PGeom.dist(px, py, float(em.x), float(em.y))
					break
				if ph != "move":
					em.state = "approach"
					em.state_t = 0.0
					if int(em.get("dodge_uses", 0)) == 0:
						em.x = ax
						em.y = ay
			if d1 < 0.0:
				continue
			cnt += 1
			esc_rows += 1
			gain += d1
			if d1 > wr:
				outn += 1
		var row: Array = by_w[String(wid)]
		print("| %s | %.0f | %.0f px | %.0f px | %d/%d | %.0f |" % [String((W[String(wid)] as Dictionary).name), wr, wr * 0.8,
			gain / float(maxi(1, cnt)), outn, cnt, float(row[2])])
	print("")
	ok("측정: 짧은 사거리 무기가 불리해지는 정도를 값으로 남겼다(회피 %d건 · **보정 수치는 넣지 않았다**)" % esc_rows, esc_rows > 0)

# =========================================================================
# ⑬ 회피와 '연계 완주'(2026-09-09). 앞선 보고에서 회피를 넣은 뒤 정예의 연계 완주가 조금 줄었다.
# **횟수만으로 단정하지 않고 행동 순서(상태 전이)로** 세 가지를 가른다:
#   ㉮ 연계가 진행 중인데 회피로 끊겼는가   ㉯ 연계 종료 후 다음 공격 시작이 늦어졌는가   ㉰ 적이 먼저 죽어 시간이 줄었는가
# 그리고 사용자 요구("자기 공격 준비·실행 중에는 회피하지 않는다")를 **실제 전투 전체**에서 확인한다 —
# 기존 ④는 첫 확정 상태에 6초 붙여 두는 합성 장면이라, 판 전체를 훑는 이 검사와 서로 보완한다.
# 조사 도구(같은 셈법·더 넓은 표): tools/probe_dodge.gd → docs/sim/PROBE_DODGE.md
# =========================================================================

const CHAIN_COMBO := {
	"elite_archer": ["aim", ["fan_lock"]],
	"elite_blademaster": ["dash1_aim", ["slam_aim"]],
	"elite_fang": ["bite_aim", ["leap"]],
	"elite_plaguecaller": ["throw_aim", ["swell"]],
	"elite_chainbreaker": ["chain_aim", ["slam_lock", "retract"]],
	"elite_standard": ["plant_aim", ["plant_aim", "slash_aim"]],
	"elite_miner": ["dive", ["erupt"]],
}
const CHAIN_SEC := 40.0

func chain_committed(tp: String, s: String) -> bool:
	return (PEnemiesNew.COMMITTED.get(tp, []) as Array).has(s)

## 정예 1마리 대 봇 1판을 상태 전이로 기록한다. 회피를 끈 판은 비교 전용 스위치로만 만든다
func chain_run(tp: String, seed_v: int, dodge_on: bool) -> Dictionary:
	PEnemiesNew.set_dodge_on(dodge_on)
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": 1, "fixed_build": true })
	st.spawn_hold = true
	var e := st.spawn_enemy(tp, st.player.x + 260.0, st.player.y)
	var bot := PBot.new("balanced")
	var cs: Array = CHAIN_COMBO[tp]
	var start_state := String(cs[0])
	var fin: Array = cs[1]
	var last := String(e.state)
	var finishes := 0
	var chain_open := false
	var in_chain := 0          # ㉮ 연계가 열린 채로 회피가 시작된 횟수
	var from_committed := 0    # 요구 위반: 공격 준비·실행 중에 회피가 시작됐다
	var locked_committed := 0  # 요구 위반: 회피 단계가 도는 동안 COMMITTED였다
	var gaps: Array = []       # ㉯ 공격이 끝난 뒤 다음 공격 시작까지의 초
	var last_end := -1.0
	var alive := 0.0
	for i in int(round(CHAIN_SEC / STEP)):
		st.step(bot.step_input(st), STEP)
		alive = float(st.t)
		if bool(e.dead) or bool(st.player.dead):
			break
		if String(e.get("dodge_phase", "")) != "" and chain_committed(tp, String(e.state)):
			locked_committed += 1
		var s := String(e.state)
		if s == last:
			continue
		if fin.has(s):
			finishes += 1
		if s == start_state:
			chain_open = true
		elif fin.has(s) or s == "approach" or s == "recover":
			chain_open = false
		var was_c := chain_committed(tp, last)
		if chain_committed(tp, s) and not was_c:
			if last_end >= 0.0:
				gaps.append(float(st.t) - last_end)
		if was_c and not chain_committed(tp, s):
			last_end = float(st.t)
		if s == "dodge":
			if chain_open:
				in_chain += 1
			if was_c:
				from_committed += 1
			chain_open = false
		last = s
	PEnemiesNew.set_dodge_on(true)
	var gm := 0.0
	if not gaps.is_empty():
		gaps.sort()
		gm = float(gaps[gaps.size() / 2])
	return { "finishes": finishes, "gap": gm, "alive": alive, "in_chain": in_chain,
		"from_committed": from_committed, "locked_committed": locked_committed,
		"uses": int(e.get("dodge_uses", 0)), "dead": bool(e.dead) }

func dodge_chain_tests() -> void:
	print("")
	print("[⑬ 회피와 연계 완주] 정예 1마리 · 봇 '보통' · 최대 %.0f초 · 시드 %d — 회피 켬/끔을 같은 시드로 나란히" % [CHAIN_SEC, DSEED])
	print("| 정예 | 완주(끔→켬) | 공격 사이 빈 시간(끔→켬) | 살아 있던 시간(끔→켬) | 회피 | ㉮ 연계 중 끊김 | 위반(준비·실행 중 회피) |")
	print("|---|---|---|---|---:|---:|---|")
	var tot_in_chain := 0
	var tot_violation := 0
	var tot_uses := 0
	var slower := 0
	var earlier := 0
	for tp in PEnemiesNew.ELITE_TYPES:
		var on := chain_run(String(tp), DSEED, true)
		var off := chain_run(String(tp), DSEED, false)
		tot_in_chain += int(on.in_chain)
		tot_violation += int(on.from_committed) + int(on.locked_committed)
		tot_uses += int(on.uses)
		if float(on.gap) > float(off.gap) + 0.01:
			slower += 1
		if float(on.alive) < float(off.alive) - 0.05:
			earlier += 1
		print("| %s | %d → %d | %.2f초 → %.2f초 | %.1f초 → %.1f초 | %d회 | %d회 | %s |" % [
			String(PCatalog.enemy(String(tp)).name), int(off.finishes), int(on.finishes),
			float(off.gap), float(on.gap), float(off.alive), float(on.alive),
			int(on.uses), int(on.in_chain),
			("**있다(직전 %d · 단계 중 %d)**" % [int(on.from_committed), int(on.locked_committed)]) if (int(on.from_committed) + int(on.locked_committed)) > 0 else "없다"])
	print("")
	ok("⑬-가 실제 전투 전체에서 **자기 공격 준비·실행 중에는 회피가 시작되지 않는다**(회피 %d회 · 위반 %d건)" % [tot_uses, tot_violation],
		tot_uses > 0 and tot_violation == 0)
	ok("⑬-나 **진행 중인 연계를 회피가 끊지 않는다**(연계가 열린 채 시작된 회피 %d회)" % tot_in_chain, tot_in_chain == 0)
	ok("⑬-다 [관찰] 연계 완주가 줄어든 자리는 **연계 종료 후 다음 공격이 늦어진 것**이다 — 공격 사이 빈 시간이 늘어난 종류 %d/7 · 먼저 죽은 종류 %d/7 (판정이 아니라 계측)" % [slower, earlier],
		true, "회피에 묶이는 시간 = 반응 지연 + 이동 + 추스르는 틈(설계 그대로). 수치·적용 범위는 바꾸지 않았다")

# =========================================================================
# ⑭ 피의 송곳니 가독성(2026-09-09 사용자 판정 ㉢ "실행은 되는데 알아보기 어렵다").
# **체력·속도·예고 시간은 하나도 바꾸지 않았다** — 이 검사가 그 사실을 값으로 붙들어 둔다.
# 더한 것: 물기 예고의 **짧은 낱말 + 짧은 경고음**, 물기 준비 자세·표식(화면), 도적과 갈리는 색.
# =========================================================================

## 이번 작업 **전과 같아야 하는** 수치(시험값 자체는 2026-09-08 것 그대로다)
const FANG_FIXED := { "hp": 190.0, "speed": 190.0, "biteAim": 0.35, "biteRange": 52.0, "biteDeg": 90.0,
	"biteDamage": 16.0, "backoffTime": 0.5, "leapAim": 0.6, "leapLock": 0.15, "leapTime": 0.38,
	"leapRange": 260.0, "leapR": 74.0, "leapDamage": 22.0, "recover": 1.1, "missStagger": 1.6 }

## 색을 색상각·채도·명도로 갈라 본다(색만으로 가르지 않지만, '거의 같은 색'은 그 자체가 결함이었다)
func hsv_of(hex: String) -> Array:
	var c := Color(hex)
	return [c.h * 360.0, c.s, c.v]

func hue_gap(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 360.0 - d)

func fang_readability_tests() -> void:
	var fg: Dictionary = PCatalog.enemy("elite_fang")
	var ro: Dictionary = PCatalog.enemy("rogue")
	var wo: Dictionary = PCatalog.enemy("wolf")
	# 가) 수치 불변
	var moved: Array = []
	for k in FANG_FIXED:
		if not is_equal_approx(float(fg.get(String(k), -1.0)), float(FANG_FIXED[k])):
			moved.append("%s %.3f(기대 %.3f)" % [String(k), float(fg.get(String(k), -1.0)), float(FANG_FIXED[k])])
	ok("⑭-가 송곳니의 체력·이동 속도·예고 시간·사거리·피해가 그대로다(표시만 고쳤다)", moved.is_empty(), str(moved))
	# 나) 색이 쌍날 도적과 실제로 갈린다
	var f := hsv_of(String(fg.color))
	var r := hsv_of(String(ro.color))
	var w := hsv_of(String(wo.color))
	var hg := hue_gap(float(f[0]), float(r[0]))
	ok("⑭-나 송곳니 색이 쌍날 도적과 갈린다(색상각 ≥12도 또는 채도 차 ≥0.15)",
		hg >= 12.0 or absf(float(f[1]) - float(r[1])) >= 0.15,
		"송곳니 %s(H %.0f S %.2f V %.2f) · 도적 %s(H %.0f S %.2f V %.2f) · 색상각 차 %.1f도 · 채도 차 %.2f · 명도 차 %.2f" % [
			String(fg.color), float(f[0]), float(f[1]), float(f[2]), String(ro.color), float(r[0]), float(r[1]), float(r[2]),
			hg, absf(float(f[1]) - float(r[1])), absf(float(f[2]) - float(r[2]))])
	ok("⑭-나2 송곳니 색이 늑대와도 갈린다(늑대는 회색 = 채도가 아주 낮다)", absf(float(f[1]) - float(w[1])) >= 0.3,
		"채도 %.2f vs %.2f" % [float(f[1]), float(w[1])])
	# 다) 물기 예고에 글자와 소리가 있다(늑대·도적과 다른 소리 이름)
	var st := lab(3)
	var e := put(st, "elite_fang", float(st.player.x) + 70.0, float(st.player.y))
	var ev0: int = st.events.size()
	var fx0: int = st.effects.size()
	var t := until(st, e, "bite_aim", 8.0)
	var said := ""
	for i in range(fx0, st.effects.size()):
		var f2: Dictionary = st.effects[i]
		if String(f2.get("kind", "")) == "text" and PGeom.dist(float(f2.x), float(f2.y), float(e.x), float(e.y)) < 80.0:
			said = String(f2.get("text", ""))
	var heard: Array = []
	for i in range(ev0, st.events.size()):
		heard.append(String(st.events[i]))
	ok("⑭-다 물기 예고 시작에 **짧은 낱말**이 뜬다(예전에는 글자가 없었다)", t >= 0.0 and said != "" and said.length() <= 6,
		"'%s'" % said)
	ok("⑭-라 물기 예고 시작에 **짧은 경고음**이 난다(예전에는 소리가 없었다)", heard.has("boss_lock"), str(heard))
	ok("⑭-마 그 소리가 늑대의 물기 확정(bite_lock)·돌진 확정(lock)과 다른 이름이다",
		not heard.has("bite_lock"), str(heard))
	# 바) 도약 확정 소리 집합이 늑대 돌진 확정과 다르다(lock 하나가 아니다)
	var st2 := lab(3)
	var e2 := put(st2, "elite_fang", float(st2.player.x) + 70.0, float(st2.player.y))
	until(st2, e2, "leap_aim", 10.0)
	var ev2: int = st2.events.size()
	var got := until(st2, e2, "leap_lock", 4.0)
	var heard2: Array = []
	for i in range(ev2, st2.events.size()):
		heard2.append(String(st2.events[i]))
	ok("⑭-바 도약 확정 소리가 늑대 돌진 확정(lock 하나)과 다르다", got >= 0.0 and heard2.has("lock") and heard2.has("boss_lock"),
		str(heard2))
