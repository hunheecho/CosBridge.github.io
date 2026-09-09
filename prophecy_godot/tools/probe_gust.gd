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
##  - 반사실: 같은 순간에 auto_target(표식>정예>가장 가까운) 쪽으로 쐈다면 몇 마리를 맞혔을까
## 검출 지연: 효과는 단계 끝에 읽으므로 적 위치가 1/120초(최대 1.6px)만큼 움직인 뒤 값이다.

const STEP := 1.0 / 120.0
const MAX_SEC := 90.0
const RANGE := 170.0
const WIDTH := 120.0

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
			fires.append(measure_fire(st, float(f.x), float(f.y), float(f.get("angle", 0.0))))
	return { "fires": fires, "sec": float(st.t), "status": String(st.status), "kills": int(st.stats.kills),
		"e_uses": int(st.stats.e_uses), "gust_dmg": float((st.metrics.dmg as Dictionary).get("skill:gust", 0.0)) }

## 한 발의 조준 품질. 실제 판정과 같은 기하(PGeom.in_beam + los_blocked)를 그대로 쓴다
func measure_fire(st: CombatState, px: float, py: float, ang: float) -> Dictionary:
	var alive := st.alive_targets()
	var hit := 0
	var in_range := 0
	var nearest := {}
	var nd := INF
	for e in alive:
		var d: float = PGeom.dist(px, py, float(e.x), float(e.y))
		if d <= RANGE + float(e.r):
			in_range += 1
			if d < nd:
				nd = d
				nearest = e
		if PGeom.in_beam(px, py, ang, RANGE, WIDTH, float(e.x), float(e.y), float(e.r)) and not st.los_blocked(px, py, float(e.x), float(e.y)):
			hit += 1
	# 반사실 ①: 가장 가까운 적 쪽으로 쐈다면
	var alt_near := 0
	var err := -1.0
	if not nearest.is_empty():
		var a2: float = atan2(float(nearest.y) - py, float(nearest.x) - px)
		err = absf(PGeom.ang_diff(ang, a2))
		for e in alive:
			if PGeom.in_beam(px, py, a2, RANGE, WIDTH, float(e.x), float(e.y), float(e.r)) and not st.los_blocked(px, py, float(e.x), float(e.y)):
				alt_near += 1
	# 반사실 ②: PSkills.auto_target(표식 > 정예 > 가장 가까운) 쪽으로 쐈다면
	var alt_auto := 0
	var tg := PSkills.auto_target(st, RANGE)
	if not tg.is_empty():
		var a3: float = atan2(float(tg.y) - py, float(tg.x) - px)
		for e in alive:
			if PGeom.in_beam(px, py, a3, RANGE, WIDTH, float(e.x), float(e.y), float(e.r)) and not st.los_blocked(px, py, float(e.x), float(e.y)):
				alt_auto += 1
	# 반사실 ③: 적이 가장 많이 걸리는 방향(상한 — 사람이 완벽히 조준했을 때)
	var best := 0
	for k in 72:
		var a4: float = float(k) / 72.0 * TAU
		var c := 0
		for e in alive:
			if PGeom.in_beam(px, py, a4, RANGE, WIDTH, float(e.x), float(e.y), float(e.r)) and not st.los_blocked(px, py, float(e.x), float(e.y)):
				c += 1
		best = maxi(best, c)
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
	md.append("생성 `tools/probe_gust.gd` · 단계 %0.4f초 · 상한 %d초. **규칙·수치를 바꾸지 않았다.**" % [STEP, int(MAX_SEC)])
	md.append("")
	md.append("판정 기하는 `scripts/rules/skills.gd:163-167`과 같다(길이 170 · 폭 120 · 가림 검사).")
	md.append("")
	md.append("| 편성 | 봇 | 돌풍 | 발사 | 유효 적중(발당) | 0적중 | **사거리 안에 적이 있었는데 0적중** | 조준 오차(도, 중앙) | 가장 가까운 적 쪽이었다면 | auto_target 쪽이었다면 | 최선의 방향이었다면 | 발사 중 이동 중 |")
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
	md.append("| 봇 | 발사 | 발당 유효 적중 | 0적중 | 사거리 안에 적이 있었는데 0적중 | 가장 가까운 적 쪽이었다면 | auto_target 쪽이었다면 | 최선의 방향이었다면 |")
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
	md.append("총 발사 %d회. '조준 오차'는 발사 각과 **가장 가까운 적 방향** 사이의 각도 차이다(0도면 정면으로 겨눈 것)." % total_fires)
	md.append("")
	var fa := FileAccess.open("res://docs/sim/PROBE_GUST.md", FileAccess.WRITE)
	fa.store_string("\n".join(md) + "\n")
	fa.close()
	print("\n".join(md))
	print("PROBE_GUST_DONE fires=%d" % total_fires)
	quit()
