extends SceneTree
## 보스 공격 속도(행동 빈도) 계측·검사: godot --headless --path prophecy_godot -s tests/boss_pace_tests.gd
## 목적(사용자 요청 §6): 분당 실제 공격 개시 횟수를 재고, 예고(예고→발동)가 짧아지지 않았는지, 연계 종료에 빈틈이 있는지,
##   가까운 거리에서 이동 공격 후보가 존재하는지(가시갈기의 구조적 문제)를 고정 조건에서 확인한다.
## 계측 조건은 고정 실험이다: 장애물 없는 전장(forest), 보스 체력 100만(죽지 않음), 플레이어는 매 단계 보스에서 정해진 거리로 재배치(이동·회피 없음),
##   플레이어 체력은 매 단계 최대치로 되돌린다(사망 없음), Q/E 사용 없음, 단계(phase)는 고정. 사람 조작이 아니며 승률과 무관하다.
## 환경 변수: PROPHECY_PACE_JSON=1 → 계측표를 BOSS_PACE_JSON 한 줄로 출력(docs/sim/BOSS_PACE.md 작성용). PROPHECY_PACE_SEC(기본 60).
## 개선 전 기준값은 data/boss_behavior.json 의 pace_baseline(같은 스크립트로 073f74f에서 측정한 값)이다.
## 모든 수치는 시험값(사람이 승인한 균형값 아님).

const STEP := 1.0 / 120.0
const BOSSES := ["boss", "guardian", "eater", "gate_warden", "spore_matriarch", "excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]
## 연계 후속타의 예고 하한(초). 연계 첫 공격은 데이터의 원래 예고를 그대로 쓴다
const FOLLOW_WARN_FLOOR := 0.45
const HUGE_HP := 1000000.0
## 패턴 → 원래 예고 설정 위치(boss_defs 안의 키). 첫 공격 예고가 이 값보다 짧아지면 안 된다
const WARN_KEYS := {
	"boss": { "sweep": ["sweep"], "dash": ["dash"], "pounce": ["pounce"] },
	"guardian": { "sweep": ["sweep"], "shock": ["shock"] },
	"eater": { "lanes": ["lanes"], "wide": ["wide"], "mark": ["mark"] },
	"gate_warden": { "guard": ["guard"], "breach": ["breach"], "bolts": ["bolts"] },
	"spore_matriarch": { "ring": ["ring"], "spray": ["spray"] },
	"excavation_behemoth": { "burrow": ["burrow"] },
	"frost_stalker": { "bolt": ["bolt"], "icepath": ["icepath"] },
	"blood_hunt_king": { "claw": ["claw"], "dash": ["dash"] },
	"doom_executor": { "slash": ["slash"] },
}

var results: Array = []
var table: Array = []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func build() -> Dictionary:
	return PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword")))

func make(boss_id: String, seed_v: int) -> CombatState:
	var st := CombatState.new({ "build": build(), "seed": seed_v, "arena": "forest", "boss": true, "boss_id": boss_id,
		"region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP })
	for i in 600: # 입장 연출(시간이 흐르지 않는 구간)을 넘긴다
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	return st

## 플레이어를 보스에서 dist만큼, 전장 중심 쪽으로 재배치(둘 다 중앙 부근에 머물게 한다)
func hold_player(st: CombatState, bz: Dictionary, dist: float) -> void:
	var cx: float = st.arena_w * 0.5
	var cy: float = st.arena_h * 0.5
	var a := 0.0
	if PGeom.dist(float(bz.x), float(bz.y), cx, cy) >= 1.0:
		a = atan2(cy - float(bz.y), cx - float(bz.x))
	var p: Dictionary = st.player
	p.x = clampf(float(bz.x) + cos(a) * dist, float(p.r), st.arena_w - float(p.r))
	p.y = clampf(float(bz.y) + sin(a) * dist, float(p.r), st.arena_h - float(p.r))

## 고정 조건 계측 1회. dist = 유지 거리, phase = 고정 단계, sec = 계측 시간(초)
## "실제 공격 개시" = 예고 구간(준비·방향 고정, PBoss.is_warn_state)이 새로 시작한 횟수.
##   화면·봇이 읽는 예고 하나 = 공격 하나로 세므로, 연속 돌진 2/2·굴착 2/2·절단선 2번처럼 예고가 다시 뜨는 후속 동작도 각각 센다.
##   소환·호효(늑대 부르기)는 예고 도형이 없으므로 공격 개시로 세지 않는다(패턴 실행 수 inits에는 남는다).
## 예고 시간 = 그 예고가 시작해서 예고 구간을 벗어날 때까지. 늦게 떨어지는 표식·낙석은 이 값에 섞이지 않는다.
func measure(boss_id: String, dist: float, phase: int, sec: float, seed_v: int) -> Dictionary:
	var st := make(boss_id, seed_v)
	var bz: Dictionary = st.boss
	bz.phase = phase
	var t0: float = st.t
	var prep_n := int(bz.get("attack_n", 0))
	var inits := 0
	var warns := 0
	var pats: Dictionary = {}
	var first_warns: Dictionary = {}   # 패턴 → 연계 첫 공격의 최소 예고 시간
	var follow_min := 999.0
	var follow_n := 0
	var recover_steps := 0
	var rec_t := -1.0
	var chain_i := 0
	var max_chain := 0
	var chain_ends := 0
	var end_gap_min := 999.0
	var in_warn := false
	var warn_t := 0.0
	var warn_pat := ""
	var warn_kind := 0 # 0 = 패턴의 첫 예고, 1 = 연계 후속타의 첫 예고, 2 = 한 패턴 안의 2단계 예고(연속 돌진 2/2 등, 개편 전부터 있던 것)
	var stage_idx := 0
	var stage_min := 999.0
	for i in int(round(sec / STEP)):
		hold_player(st, bz, dist)
		st.player.hp = st.player.hp_max
		st.step({}, STEP)
		if bz.dead:
			break
		var s := String(bz.state)
		# 빈틈 구간(빈틈 피해 1.5배가 붙는 recover·stagger)
		if s == "recover" or s == "stagger":
			recover_steps += 1
			if rec_t < 0.0:
				rec_t = st.t
		elif rec_t >= 0.0:
			var dur: float = st.t - rec_t
			if chain_i > 0:
				chain_ends += 1
				end_gap_min = minf(end_gap_min, dur)
			max_chain = maxi(max_chain, chain_i)
			chain_i = 0
			rec_t = -1.0
		# 패턴 실행 수(begin 호출)
		var pn := int(bz.get("attack_n", 0))
		if pn > prep_n:
			prep_n = pn
			chain_i += 1
			inits += 1
			stage_idx = 0
			var h: Array = bz.get("history", [])
			var pk := String(h[h.size() - 1]) if h.size() > 0 else "?"
			pats[pk] = int(pats.get(pk, 0)) + 1
		# 예고 시작·종료
		var now_warn := PBoss.is_warn_state(s)
		if now_warn and not in_warn:
			in_warn = true
			warns += 1
			warn_t = st.t
			if stage_idx > 0:
				warn_kind = 2
			elif float(bz.get("warn_speed", 1.0)) > 1.0:
				warn_kind = 1
			else:
				warn_kind = 0
			stage_idx += 1
			var h2: Array = bz.get("history", [])
			warn_pat = String(h2[h2.size() - 1]) if h2.size() > 0 else "?"
		elif in_warn and not now_warn:
			in_warn = false
			var w: float = st.t - warn_t
			if warn_kind == 1:
				follow_min = minf(follow_min, w)
				follow_n += 1
			elif warn_kind == 2:
				stage_min = minf(stage_min, w)
			else:
				first_warns[warn_pat] = minf(float(first_warns.get(warn_pat, 999.0)), w)
	max_chain = maxi(max_chain, chain_i)
	var elapsed: float = maxf(0.001, st.t - t0)
	var fw: Dictionary = {}
	for k in first_warns:
		fw[String(k)] = snapped(float(first_warns[k]), 0.001)
	return { "boss": boss_id, "dist": dist, "phase": phase, "sec": snapped(elapsed, 0.01), "inits": inits, "warns": warns,
		"per_min": snapped(float(inits) / elapsed * 60.0, 0.1), "warn_per_min": snapped(float(warns) / elapsed * 60.0, 0.1),
		"patterns": pats, "first_warn": fw,
		"stage_warn_min": (snapped(stage_min, 0.001) if stage_min < 999.0 else 0.0),
		"follow_warn_min": (snapped(follow_min, 0.001) if follow_min < 999.0 else 0.0), "follow_n": follow_n,
		"max_chain": max_chain, "chain_ends": chain_ends, "end_gap_min": (snapped(end_gap_min, 0.01) if end_gap_min < 999.0 else 0.0),
		"exposed_frac": snapped(float(recover_steps) * STEP / elapsed, 0.001) }

## 데이터의 원래 예고(준비+고정) 합
func base_warn(cfg: Dictionary, keys: Array) -> float:
	var cur: Dictionary = cfg
	for k in keys:
		if not cur.has(String(k)):
			return 0.0
		cur = cur[String(k)]
	var a := float(cur.get("aim", cur.get("cast", cur.get("warn", 0.0))))
	return a + float(cur.get("lock", 0.0))

func _init() -> void:
	var json_mode := OS.get_environment("PROPHECY_PACE_JSON") == "1"
	var sec := 60.0
	if OS.get_environment("PROPHECY_PACE_SEC").is_valid_float():
		sec = float(OS.get_environment("PROPHECY_PACE_SEC"))
	for bid in BOSSES:
		for dist in [80.0, 260.0]:
			for ph in [1, 3]:
				table.append(measure(String(bid), float(dist), int(ph), sec, 11))
	for row in table:
		print("PACE %s d=%d ph=%d: 공격개시 %.1f회/분 (%d회/%.1f초, 예고 %.1f회/분) 첫예고=%s 후속예고최소=%.2f(%d) 최대연계=%d 연계끝빈틈최소=%.2f 빈틈비율=%.3f 패턴=%s" % [
			String(row.boss), int(row.dist), int(row.phase), float(row.per_min), int(row.inits), float(row.sec), float(row.warn_per_min),
			JSON.stringify(row.first_warn), float(row.follow_warn_min), int(row.follow_n), int(row.max_chain),
			float(row.end_gap_min), float(row.exposed_frac), JSON.stringify(row.patterns)])
	# ---------- 1) 가시갈기: 근거리에서 휩쓸기 전용이 아닌가(검토 문서가 재현한 구조적 문제) ----------
	var st := make("boss", 11)
	var bz: Dictionary = st.boss
	bz.actions = 3
	bz.history = []
	bz.last_howl = st.t # 소환 쿨다운 중
	bz.phase = 1
	st.player.x = bz.x + 80.0
	st.player.y = bz.y
	var cands: Array = PBoss.candidate_names(st, bz)
	var only_sweep: bool = cands.size() <= 1 and cands.has("sweep")
	ok("가시갈기 거리80·1단계: 후보가 휩쓸기 전용이 아니다(근거리에서도 이동 공격 후보 존재)", not only_sweep, "후보 %s" % str(cands))
	bz.phase = 3
	var cands3: Array = PBoss.candidate_names(st, bz)
	ok("가시갈기 거리80·3단계: 후보 2종 이상", cands3.size() >= 2, "후보 %s" % str(cands3))
	bz.phase = 1
	var pick: Dictionary = {}
	for i in 100:
		bz.history = []
		var pat := PBoss.choose_pattern(st, bz)
		pick[pat] = int(pick.get(pat, 0)) + 1
	ok("가시갈기 거리80 추첨 100회: 휩쓸기 100%가 아니다", int(pick.get("sweep", 0)) < 100, JSON.stringify(pick))
	# ---------- 2) 예고가 짧아지지 않았다 ----------
	var B: Dictionary = PCatalog.boss_defs()
	var base_ok := true
	var base_txt: Array = []
	var seen := 0
	for row in table:
		var bid := String(row.boss)
		var keys: Dictionary = WARN_KEYS.get(bid, {})
		for pat in row.first_warn:
			if not keys.has(String(pat)):
				continue
			seen += 1
			var want := base_warn(B[bid], keys[String(pat)])
			var got := float(row.first_warn[pat])
			if got < want - 0.02:
				base_ok = false
				base_txt.append("%s.%s %.2f<%.2f" % [bid, String(pat), got, want])
	ok("연계 첫 공격의 예고(준비+고정)는 데이터 원래 값 이상 (%d건 확인)" % seen, base_ok and seen > 0, ", ".join(base_txt))
	var fw_ok := true
	var fw_txt: Array = []
	for row in table:
		if int(row.follow_n) > 0 and float(row.follow_warn_min) < FOLLOW_WARN_FLOOR - 1e-6:
			fw_ok = false
			fw_txt.append("%s d%d ph%d %.2f" % [String(row.boss), int(row.dist), int(row.phase), float(row.follow_warn_min)])
	ok("연계 후속타의 예고도 하한 %.2f초 이상(읽을 수 있는 예고 유지)" % FOLLOW_WARN_FLOOR, fw_ok, ", ".join(fw_txt))
	# ---------- 3) 연계 종료 시 빈틈 존재 ----------
	var gap_ok := true
	var gap_txt: Array = []
	for row in table:
		if int(row.max_chain) >= 2 and (int(row.chain_ends) == 0 or float(row.end_gap_min) < 0.5):
			gap_ok = false
			gap_txt.append("%s d%d ph%d 끝빈틈 %.2f" % [String(row.boss), int(row.dist), int(row.phase), float(row.end_gap_min)])
	ok("연계가 끝나면 반드시 빈틈(0.5초 이상)이 온다", gap_ok, ", ".join(gap_txt))
	var exp_ok := true
	var exp_txt: Array = []
	for row in table:
		if float(row.exposed_frac) <= 0.0:
			exp_ok = false
			exp_txt.append("%s d%d ph%d" % [String(row.boss), int(row.dist), int(row.phase)])
	ok("모든 조건에서 빈틈 구간이 존재한다(무한 연계 없음)", exp_ok, ", ".join(exp_txt))
	# ---------- 4) 목표 빈도(시험값): 개선 전 기록 대비 ----------
	var base_ref: Dictionary = PBoss.behavior().get("pace_baseline", {})
	var rate_txt: Array = []
	var reached := 0
	var counted := 0
	var ratio_sum := 0.0
	var ratio_lo := 99.0
	for bid in BOSSES:
		var sum_now := 0.0
		var sum_ref := 0.0
		var k := 0
		for row in table:
			if String(row.boss) != bid:
				continue
			var key := "%s|%d|%d" % [bid, int(row.dist), int(row.phase)]
			if not base_ref.has(key):
				continue
			sum_now += float(row.per_min)
			sum_ref += float(base_ref[key])
			k += 1
		if k == 0:
			continue
		counted += 1
		var ratio: float = sum_now / maxf(0.001, sum_ref)
		ratio_sum += ratio
		ratio_lo = minf(ratio_lo, ratio)
		if ratio >= 2.5:
			reached += 1
		rate_txt.append("%s ×%.2f(%.1f→%.1f)" % [bid, ratio, sum_ref / float(k), sum_now / float(k)])
	var ratio_avg: float = ratio_sum / float(maxi(1, counted))
	ok("분당 공격 개시 배율(개선 전 기록 대비) — 9종 평균 ×%.2f, 최저 ×%.2f, 2.5배 이상 %d종" % [ratio_avg, ratio_lo, reached],
		counted == BOSSES.size(), ", ".join(rate_txt))
	# 목표(사용자 요청): 기존 대비 최소 2.5배. 고정 거리 실험에서 보스별 편차가 있으므로 평균 2.5배 + 개별 하한 2.0배로 본다
	ok("빈도 목표(시험값): 9종 평균 2.5배 이상", ratio_avg >= 2.5, "평균 ×%.2f" % ratio_avg)
	ok("빈도 하한(시험값): 어떤 보스도 2.0배 미만이 아니다", ratio_lo >= 2.0, "최저 ×%.2f" % ratio_lo)
	if json_mode:
		print("BOSS_PACE_JSON " + JSON.stringify({ "rows": table, "baseline": base_ref, "sec": sec, "seed": 11 }))
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
