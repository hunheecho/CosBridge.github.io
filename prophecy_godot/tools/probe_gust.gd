extends SceneTree
## 조사 전용(임시): 돌풍(E)이 실제로 어디를 향해 나가는가.
##   godot --headless --path prophecy_godot -s tools/probe_gust.gd
##
## 규칙·수치를 하나도 건드리지 않는다. CombatState.effects(표시용 목록)만 읽어 재구성한다:
## PSkills.cast_e의 "gust" 갈래가 st.fx({kind:"gust", x,y,angle,len,w})를 남기고, 그 x·y·angle이
## 곧 발사 순간의 플레이어 자리와 조준각이다(scripts/rules/skills.gd:164).
##
## 재는 것
##  - 발사 수, 유효 적중(부채꼴 판정 안 + 가림 없음) 수
##  - '적이 없는 방향으로 나갔다' = 사거리 안에 적이 있었는데 0마리를 맞힌 발사
##  - 조준각과 가장 가까운 적 방향 사이의 각도 차이
##  - 반사실: 같은 순간에 ① 단순 최근접 ② 지금 규칙(유효한 가까운 적) ③ 최선의 방향으로 쐈다면 몇 마리를 맞혔을까
## 자리 기준: 단계가 **시작하기 전에** 찍어 둔 적 자리를 쓴다. 그것이 cast_e가 실제로 본 자리다
## (단계가 끝난 뒤 자리는 돌풍이 이미 140~200px 밀어낸 뒤라 맞힌 적이 사거리 밖으로 나가 있다).

const STEP := 1.0 / 120.0
const MAX_SEC := 90.0

## 판정 기하는 규칙에서 직접 읽는다(예전에는 170·120을 여기 베껴 적었다).
## 규칙이 바뀌면 이 도구도 같이 바뀌므로 '측정한 기하'와 '실제 기하'가 갈라질 수 없다.
var RANGE: float = PSkills.GUST_LEN
var WIDTH: float = PSkills.GUST_W

## 수정 전 기준선(커밋 7150134, `var ang: float = p.face`).
## **같은 도구·같은 조건으로 다시 읽은 값이다**(2026-09-09). 전투를 새로 설계해 잰 것이 아니라
## 옛 조준 한 줄만 되돌려 같은 편성·봇·시드로 한 번 돌린 것이고, 발사 수가 267회로 그대로 나와
## 되돌림이 옛 동작을 정확히 재현했음을 확인했다.
##
## **왜 다시 읽었나 — 처음 공개한 수치는 측정 결함이었다.**
## 예전 판은 단계가 끝난 뒤의 적 자리로 적중을 다시 계산했는데, 그 자리는 돌풍이 방금 140~200px
## 밀어낸 뒤라 **정작 맞힌 적이 사거리 밖으로 나가 '안 맞은 것'으로** 세어졌다.
## 그래서 발당 0.21 · 0적중 86%로 나왔지만, 같은 실행을 사용 순간의 자리로 읽으면 1.22 · 33%다.
## 조준이 적을 등지고 나간다는 사실 자체는 그대로다(조준 오차 중앙값 90~150도).
##
## 열: 발사 · 발당 유효 적중 · 0적중 · 0적중% · 사거리 안에 적이 있었는데 0적중 · 그 % · 단순 최근접 쪽이었다면
const BEFORE := {
	"balanced":   { "n": 65, "hit": 1.38, "zero": 12, "zero_p": 18.0, "zwe": 12, "zwe_p": 18.0, "alt": 1.88 },
	"aggressive": { "n": 69, "hit": 1.13, "zero": 25, "zero_p": 36.0, "zwe": 5, "zwe_p": 7.0, "alt": 1.20 },
	"survival":   { "n": 77, "hit": 1.17, "zero": 24, "zero_p": 31.0, "zwe": 24, "zwe_p": 31.0, "alt": 2.25 },
	"still":      { "n": 56, "hit": 1.23, "zero": 28, "zero_p": 50.0, "zwe": 4, "zwe_p": 7.0, "alt": 1.41 },
	"__total__":  { "n": 267, "hit": 1.22, "zero": 89, "zero_p": 33.0, "zwe": 45, "zwe_p": 17.0, "alt": 1.71 },
}

## 수정 전 실행에서 '유효한 가까운 적 쪽이었다면'이 낸 값(= 지금 규칙이 낼 것으로 예측된 값).
## 수정 후 실측이 이 값 언저리에 오면 규칙과 도구가 서로 맞는다는 뜻이다.
const BEFORE_PREDICT := { "balanced": 1.88, "aggressive": 1.20, "survival": 2.26, "still": 1.41, "__total__": 1.72 }

var rows := []

## still = 제자리(Q/E만). 움직이지 않으므로 p.face가 이동 방향으로 덮이지 않고
## '마지막으로 자동공격이 겨눈 방향'(PWeapons.fire_*의 p.face = ang)만 남는다 — 대조군이다.
func _pol_ids() -> Array:
	return ["balanced", "aggressive", "survival", "still"]

## E=돌풍을 실제 성장 규칙으로 넣은 회차. picks만큼 성장 선택을 소비한다
func make_run(seed_v: int, gust_lv: int, variant: String, picks: int) -> Dictionary:
	var run := PRun.new_run(seed_v, "sword")
	PGrowth.apply_choice(run, { "kind": "skill_new", "id": "gust" })
	for i in maxi(0, gust_lv - 1):
		PGrowth.apply_choice(run, { "kind": "skill_level", "slot": "e", "id": "gust" })
	if variant != "":
		PGrowth.apply_choice(run, { "kind": "skill_variant", "slot": "e", "id": "gust", "variant": variant })
	var used := 0
	var guard := 0
	while used < picks and guard < 200:
		guard += 1
		var g: Dictionary = run.growth
		var ws: Array = g.weapons
		var lo: Dictionary = ws[0]
		for w in ws:
			if int(w.level) < int(lo.level):
				lo = w
		if int(lo.level) < 5 and PGrowth.apply_choice(run, { "kind": "weapon_level", "id": String(lo.id) }):
			used += 1
			continue
		break
	run.hp = float(PRun.build(run).hp_max)
	return run

func fight(run: Dictionary, waves: Array, seed_v: int, arena: String, act: int) -> CombatState:
	return CombatState.new({ "build": PRun.build(run), "hp": float(run.hp), "seed": seed_v,
		"waves": waves, "objective": "clear", "region_id": "lab", "arena": arena, "act": act, "run": run })

## 한 판. 반환 = 발사별 기록 배열
func one(run: Dictionary, waves: Array, seed_v: int, pol: String, act: int) -> Dictionary:
	var st := fight(run, waves, seed_v, "clearing", act)
	var bot := PBot.new(pol)
	var fires := []
	var n := int(MAX_SEC / STEP)
	for i in n:
		if st.status != "running":
			break
		# **단계가 시작하기 전에** 적 자리를 찍어 둔다. 한 단계의 순서는
		# update_player(이동 → cast_e) → PSkills.update → update_enemies라서
		# cast_e가 본 적 자리 = 여기서 찍은 자리다.
		# 단계가 끝난 뒤에 읽으면 **돌풍이 방금 140~200px 밀어낸 뒤의 자리**라
		# 정작 맞힌 적이 사거리 밖으로 나가 '안 맞은 것'으로 세어진다(2026-09-09 수정).
		var snap := snapshot(st)
		st.step(bot.step_input(st), STEP)
		# 이번 단계에 생긴 효과만 센다: fx는 t=0으로 들어오고 update_effects가 그 단계에서 t += dt를 한 번 한다.
		# 다음 단계에는 2*dt가 되므로 t <= 1.5*dt면 방금 생긴 것 하나뿐이다(중복 계수 없음).
		for f in st.effects:
			if String(f.get("kind", "")) != "gust":
				continue
			if float(f.t) > STEP * 1.5:
				continue
			if bool(f.get("whirl", false)):
				continue     # 회오리 변형은 방향이 없다
			fires.append(measure_fire(st, snap, float(f.x), float(f.y), float(f.get("angle", 0.0))))
	return { "fires": fires, "sec": float(st.t), "status": String(st.status), "kills": int(st.stats.kills),
		"e_uses": int(st.stats.e_uses), "gust_dmg": float((st.metrics.dmg as Dictionary).get("skill:gust", 0.0)) }

## 단계 시작 시점의 적 자리·크기·성질. 규칙을 건드리지 않고 읽기만 한다
func snapshot(st: CombatState) -> Array:
	var out := []
	for e in st.alive_targets():
		out.append({ "x": float(e.x), "y": float(e.y), "r": float(e.r),
			"skip": bool(e.get("structure", false)) or bool(e.get("airborne", false)) })
	return out

## 그 각으로 쐈다면 몇 마리가 맞나(실제 판정과 같은 기하: PGeom.in_beam + los_blocked)
func count_hits(st: CombatState, snap: Array, px: float, py: float, ang: float) -> int:
	var c := 0
	for e in snap:
		if PGeom.in_beam(px, py, ang, RANGE, WIDTH, float(e.x), float(e.y), float(e.r)) and not st.los_blocked(px, py, float(e.x), float(e.y)):
			c += 1
	return c

## 한 발의 조준 품질. 자리는 전부 snap(사용 순간)에서 읽고, 발사 자리는 효과가 남긴 px·py다
func measure_fire(st: CombatState, snap: Array, px: float, py: float, ang: float) -> Dictionary:
	var in_range := 0
	var nearest := {}
	var nd := INF
	var valid := {}          # 지금 규칙이 고르는 대상: 사거리 안 + 가림 없음 + 구조물·공중 아님
	var vd := INF
	for e in snap:
		var d: float = PGeom.dist(px, py, float(e.x), float(e.y))
		if d > RANGE + float(e.r):
			continue
		in_range += 1
		if d < nd:
			nd = d
			nearest = e
		if bool(e.skip) or d >= vd or st.los_blocked(px, py, float(e.x), float(e.y)):
			continue
		vd = d
		valid = e
	var hit := count_hits(st, snap, px, py, ang)
	# 반사실 ①: 가장 가까운 적 쪽으로 쐈다면(가림·구조물·공중을 가리지 않은 단순 최근접)
	var alt_near := 0
	var err := -1.0
	if not nearest.is_empty():
		var a2: float = atan2(float(nearest.y) - py, float(nearest.x) - px)
		alt_near = count_hits(st, snap, px, py, a2)
	# 반사실 ②: **지금 규칙**(유효한 가까운 적 = PSkills.gust_target과 같은 조건) 쪽으로 쐈다면.
	# 수정 뒤에는 이 값이 실제 적중과 같아야 한다 — 도구가 규칙을 제대로 재고 있는지 스스로 확인하는 열이다.
	var alt_auto := 0
	if not valid.is_empty():
		var a3: float = atan2(float(valid.y) - py, float(valid.x) - px)
		err = absf(PGeom.ang_diff(ang, a3))
		alt_auto = count_hits(st, snap, px, py, a3)
	# 반사실 ③: 적이 가장 많이 걸리는 방향(상한 — 사람이 완벽히 조준했을 때)
	var best := 0
	for k in 72:
		best = maxi(best, count_hits(st, snap, px, py, float(k) / 72.0 * TAU))
	return { "hit": hit, "in_range": in_range, "alt_near": alt_near, "alt_auto": alt_auto, "best": best,
		"err": err, "moving": bool(st.player.moving) }

func avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

func _init() -> void:
	var md := []
	md.append("# 조사: 돌풍(E) 조준 측정")
	md.append("")
	md.append("생성 `tools/probe_gust.gd` · 단계 %0.4f초 · 상한 %d초. **이 도구는 규칙·수치를 바꾸지 않는다(읽기만 한다).**" % [STEP, int(MAX_SEC)])
	md.append("")
	md.append("판정 기하는 규칙에서 직접 읽는다 — 길이 %.0f · 폭 %.0f(`PSkills.GUST_LEN`·`GUST_W`) · 가림 검사(`los_blocked`)." % [RANGE, WIDTH])
	md.append("")
	md.append("아래 표는 **지금 규칙**(2026-09-09 자동 조준)으로 잰 값이다. 수정 전 기준선과의 비교는 맨 아래 절에 있다.")
	md.append("")
	md.append("| 편성 | 봇 | 돌풍 | 발사 | 유효 적중(발당) | 0적중 | **사거리 안에 적이 있었는데 0적중** | 조준 오차(도, 중앙) | 단순 최근접 쪽이었다면 | 유효한 가까운 적 쪽이었다면 | 최선의 방향이었다면 | 발사 중 이동 중 |")
	md.append("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

	var scenes := [
		{ "id": "늑대 6", "waves": [[{ "type": "wolf", "n": 6 }]], "act": 1, "picks": 4 },
		{ "id": "늑대 4 + 궁수 2 + 방패병 1", "waves": [[{ "type": "wolf", "n": 4 }, { "type": "archer", "n": 2 }, { "type": "shieldbearer", "n": 1 }]], "act": 2, "picks": 12 },
		{ "id": "늑대 3 + 도적 3", "waves": [[{ "type": "wolf", "n": 3 }, { "type": "rogue", "n": 3 }]], "act": 2, "picks": 12 },
	]
	var lvs := [{ "lv": 1, "v": "", "name": "Lv1 기본" }, { "lv": 3, "v": "windpath", "name": "Lv3 바람길" }]
	var seeds := [1, 2, 3]
	var total_fires := 0
	var roll := {}   # 정책 → 합계(표 아래 요약용)
	for sc in scenes:
		for L in lvs:
			for pol in _pol_ids():
				var hits := []
				var errs := []
				var zero := 0
				var zero_with_enemy := 0
				var nfire := 0
				var alt_n := []
				var alt_a := []
				var bests := []
				var moving_n := 0
				for sd in seeds:
					var run := make_run(int(sd), int(L.lv), String(L.v), int(sc.picks))
					var r := one(run, (sc.waves as Array).duplicate(true), int(sd), String(pol), int(sc.act))
					for f in r.fires:
						nfire += 1
						hits.append(float(f.hit))
						alt_n.append(float(f.alt_near))
						alt_a.append(float(f.alt_auto))
						bests.append(float(f.best))
						if float(f.err) >= 0.0:
							errs.append(rad_to_deg(float(f.err)))
						if int(f.hit) == 0:
							zero += 1
							if int(f.in_range) > 0:
								zero_with_enemy += 1
						if bool(f.moving):
							moving_n += 1
				total_fires += nfire
				if not roll.has(String(pol)):
					roll[String(pol)] = { "n": 0, "hit": 0.0, "zero": 0, "zwe": 0, "alt": 0.0, "auto": 0.0, "best": 0.0 }
				var R: Dictionary = roll[String(pol)]
				R.n = int(R.n) + nfire
				for v in hits:
					R.hit = float(R.hit) + float(v)
				for v in alt_n:
					R.alt = float(R.alt) + float(v)
				for v in alt_a:
					R.auto = float(R.auto) + float(v)
				for v in bests:
					R.best = float(R.best) + float(v)
				R.zero = int(R.zero) + zero
				R.zwe = int(R.zwe) + zero_with_enemy
				errs.sort()
				var mederr: float = errs[errs.size() / 2] if not errs.is_empty() else -1.0
				md.append("| %s | %s | %s | %d | %.2f | %d(%.0f%%) | **%d(%.0f%%)** | %.0f | %.2f | %.2f | %.2f | %.0f%% |" % [
					String(sc.id), String(pol), String(L.name), nfire, avg(hits),
					zero, 100.0 * float(zero) / maxf(1.0, float(nfire)),
					zero_with_enemy, 100.0 * float(zero_with_enemy) / maxf(1.0, float(nfire)),
					mederr, avg(alt_n), avg(alt_a), avg(bests),
					100.0 * float(moving_n) / maxf(1.0, float(nfire))])
	md.append("")
	md.append("")
	md.append("## 요약 — 정책별 합계")
	md.append("")
	md.append("`still`은 **제자리 정책**이라 이동 방향이 p.face를 덮지 않는다. 나머지 셋은 거의 늘 움직인다.")
	md.append("")
	md.append("| 봇 | 발사 | 발당 유효 적중 | 0적중 | 사거리 안에 적이 있었는데 0적중 | 단순 최근접 쪽이었다면 | 유효한 가까운 적 쪽이었다면 | 최선의 방향이었다면 |")
	md.append("|---|---:|---:|---:|---:|---:|---:|---:|")
	var tot := { "n": 0, "hit": 0.0, "zero": 0, "zwe": 0, "alt": 0.0, "auto": 0.0, "best": 0.0 }
	for pol in roll:
		var R: Dictionary = roll[pol]
		for k in tot:
			tot[k] = tot[k] + R[k]
		md.append("| %s | %d | %.2f | %d(%.0f%%) | **%d(%.0f%%)** | %.2f | %.2f | %.2f |" % [
			String(pol), int(R.n), float(R.hit) / maxf(1.0, float(R.n)),
			int(R.zero), 100.0 * float(R.zero) / maxf(1.0, float(R.n)),
			int(R.zwe), 100.0 * float(R.zwe) / maxf(1.0, float(R.n)),
			float(R.alt) / maxf(1.0, float(R.n)), float(R.auto) / maxf(1.0, float(R.n)), float(R.best) / maxf(1.0, float(R.n))])
	md.append("| **전체** | %d | **%.2f** | %d(%.0f%%) | **%d(%.0f%%)** | %.2f | %.2f | %.2f |" % [
		int(tot.n), float(tot.hit) / maxf(1.0, float(tot.n)),
		int(tot.zero), 100.0 * float(tot.zero) / maxf(1.0, float(tot.n)),
		int(tot.zwe), 100.0 * float(tot.zwe) / maxf(1.0, float(tot.n)),
		float(tot.alt) / maxf(1.0, float(tot.n)), float(tot.auto) / maxf(1.0, float(tot.n)), float(tot.best) / maxf(1.0, float(tot.n))])
	md.append("")
	md.append("총 발사 %d회. '조준 오차'는 발사 각과 **유효한 가까운 적 방향** 사이의 각도 차이다(0도면 정면으로 겨눈 것)." % total_fires)
	md.append("")
	md.append("'유효한 가까운 적 쪽이었다면' 열은 **지금 규칙이 고르는 대상**(사거리 안 + 가림 없음 + 구조물·공중 제외)이다.")
	md.append("자동 조준을 넣은 뒤에는 이 열이 실제 적중과 같아야 한다 — 도구가 규칙을 제대로 재고 있는지 스스로 확인하는 자리다.")
	md.append("")
	md.append("")
	md.append("## 수정 전(커밋 7150134, `ang = p.face`) 대비")
	md.append("")
	md.append("같은 도구·같은 조건(편성 3 × 돌풍 2 × 봇 4 × 시드 3 · 단계 %0.4f초 · 상한 %d초)이다." % [STEP, int(MAX_SEC)])
	md.append("수정 전 값은 **옛 조준 한 줄만 되돌려 같은 편성·봇·시드로 한 번 돌린 것**이다(발사 267회가 그대로 나와 재현을 확인했다).")
	md.append("")
	md.append("**처음 공개했던 수정 전 수치(발당 0.21 · 0적중 86%)는 측정 결함이었다.** 단계가 끝난 뒤의 적 자리로 다시 계산했는데,")
	md.append("그 자리는 돌풍이 방금 140~200px 밀어낸 뒤라 **정작 맞힌 적이 사거리 밖으로 나가 '안 맞은 것'으로** 세어졌다.")
	md.append("같은 실행을 사용 순간의 자리로 읽으면 **1.22 · 33%**다. 아래 표는 전후 모두 고친 읽기로 잰 값이다.")
	md.append("")
	md.append("주의 — 조준이 바뀌면 적이 다르게 죽고 전투가 갈라지므로 **발사 횟수 자체는 같지 않다.**")
	md.append("견줄 수 있는 것은 **발당 비율**이다.")
	md.append("")
	md.append("| 봇 | 발사(전 → 후) | 발당 유효 적중(전 → 후) | 배수 | 0적중(전 → 후) | 사거리 안에 적이 있었는데 0적중(전 → 후) |")
	md.append("|---|---|---|---:|---|---|")
	var order := _pol_ids()
	order.append("__total__")
	for pol in order:
		var B: Dictionary = BEFORE[String(pol)]
		var A: Dictionary = tot if String(pol) == "__total__" else (roll[String(pol)] as Dictionary)
		var an := maxf(1.0, float(A.n))
		var a_hit := float(A.hit) / an
		var b_hit := float(B.hit)
		md.append("| %s | %d → %d | %.2f → **%.2f** | **×%.1f** | %d(%.0f%%) → %d(%.0f%%) | **%d(%.0f%%) → %d(%.0f%%)** |" % [
			("**전체**" if String(pol) == "__total__" else String(pol)),
			int(B.n), int(A.n), b_hit, a_hit, a_hit / maxf(0.01, b_hit),
			int(B.zero), float(B.zero_p), int(A.zero), 100.0 * float(A.zero) / an,
			int(B.zwe), float(B.zwe_p), int(A.zwe), 100.0 * float(A.zwe) / an])
	md.append("")
	md.append("")
	md.append("### 예측과 실측")
	md.append("")
	md.append("수정 전 실행의 '유효한 가까운 적 쪽이었다면' 열은 **지금 규칙이 낼 값의 예측**이었다. 실제로 얼마가 나왔나:")
	md.append("")
	md.append("| 봇 | 수정 전 예측 | 수정 후 실측 |")
	md.append("|---|---:|---:|")
	for pol in order:
		var A2: Dictionary = tot if String(pol) == "__total__" else (roll[String(pol)] as Dictionary)
		md.append("| %s | %.2f | **%.2f** |" % [("**전체**" if String(pol) == "__total__" else String(pol)), float(BEFORE_PREDICT[String(pol)]), float(A2.hit) / maxf(1.0, float(A2.n))])
	md.append("")
	md.append("전투가 갈라지므로 정확히 같은 값이 나오지는 않는다. 크게 어긋나면 규칙이나 도구 중 하나가 잘못된 것이다.")
	md.append("상한('최선의 방향이었다면')과의 차이는 **조준한 뒤에도 나머지 적이 부채꼴 밖에 흩어져 있는 몫**이다 — 자동 조준으로는 메울 수 없다.")
	md.append("")
	var fa := FileAccess.open("res://docs/sim/PROBE_GUST.md", FileAccess.WRITE)
	fa.store_string("\n".join(md) + "\n")
	fa.close()
	print("\n".join(md))
	print("PROBE_GUST_DONE fires=%d" % total_fires)
	quit()
