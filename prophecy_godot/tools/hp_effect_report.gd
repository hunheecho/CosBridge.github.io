extends SceneTree
## 체력 상향의 실제 효과 보고(화면 없음):
##   godot --headless --path prophecy_godot -s tools/hp_effect_report.gd
## 결과: docs/sim/HP_EFFECT.md
##
## "전투 시간 +40%"만으로는 사용자 목표("적이 살아서 공격을 실행하고, 그 공격이 실제로 닿는가")를
## 판단할 수 없다는 지적(2026-09-08 검토)에 따라 만든 도구다. 다음을 함께 잰다.
##   ① 적이 공격을 **준비**한 횟수와 **실행**한 횟수, 그리고 플레이어에게 **맞힌** 횟수
##   ② 공격을 준비하기도 전에 죽은 비율 / 준비는 했으나 실행 전에 죽은 비율
##   ③ 제자리 · 추적 · 회피 세 정책의 받은 피해 차이
##   ④ 연속 출격 3회의 잔여 체력·회복·휴식 선택
##
## 비교 조건은 `PROPHECY_PACING`으로 나눈다.
##   counts = 날짜별 적 수·혼합 편성만(체력 오버레이 없음) → **체력 상향 전**
##   full   = 현재(H3 체력표 포함)                        → **체력 상향 후**
## 적 수·편성은 두 조건에서 같다. 달라지는 것은 체력뿐이다.

const STEP := 1.0 / 120.0
const SEEDS := [1, 2, 3]
const DAYS := [2, 5, 9]
const MAX_SEC := 180.0
const POLICIES := ["stand", "active", "survival"]   # 제자리 / 추적·공격 / 회피 우선
## 그 날짜까지 사람이 보통 쌓았을 성장 선택 수(보통 수준 공격 투자). 레벨만 올리고 빌드가 비면
## 그 날짜 적을 상대할 수 없어 비교가 '누가 더 빨리 죽나'가 된다.
const PICKS_BY_DAY := { 2: 4, 5: 12, 9: 22 }

## 두 자동기술 + 개조 + 공용·패시브를 실제 규칙으로 쌓는다(연계 정책에 가깝다)
func grow(run: Dictionary, picks: int) -> void:
	var g: Dictionary = run.growth
	var second := "spear"
	var used := 0
	var guard := 0
	var blocked := {}
	while used < picks and guard < 200:
		guard += 1
		var c := {}
		var ws: Array = g.weapons
		var lo: Dictionary = ws[0]
		for i in mini(2, ws.size()):
			if int(ws[i].level) < int(lo.level):
				lo = ws[i]
		var wid := String(lo.id)
		var w := PGrowth.weapon_of(g, wid)
		if (w.mods as Array).size() < PGrowth.mod_quota(int(w.level)):
			for mid in (PCatalog.weapon(wid).get("mods", {}) as Dictionary):
				if bool(PCatalog.weapon(wid).mods[mid].get("impl", false)) and not (w.mods as Array).has(String(mid)):
					c = { "kind": "weapon_mod", "id": wid, "mod": String(mid) }
					break
		if c.is_empty() and int(lo.level) < 5:
			c = { "kind": "weapon_level", "id": wid }
		if c.is_empty() and ws.size() < 2:
			c = { "kind": "weapon_new", "id": second }
		if c.is_empty():
			for cid in PCatalog.commons():
				var cd: Dictionary = PCatalog.commons()[cid]
				var cl: int = int(g.commons.get(cid, 0))
				if bool(cd.impl) and cl < int(cd.max) and (cl > 0 or (g.commons as Dictionary).size() < 3):
					c = { "kind": "common", "id": String(cid) }
					break
		if c.is_empty():
			for pid in PCatalog.passives():
				var pd: Dictionary = PCatalog.passives()[pid]
				var pl: int = int(g.passives.get(pid, 0))
				if pl < int(pd.max) and (pl > 0 or (g.passives as Dictionary).size() < 4):
					c = { "kind": "passive", "id": String(pid) }
					break
		if c.is_empty() or blocked.has(JSON.stringify(c)):
			break
		if PGrowth.apply_choice(run, c):
			used += 1
		else:
			blocked[JSON.stringify(c)] = true
	run.hp = float(PRun.build(run).hp_max)

var rows := []
var runs := []

func set_variant(v: String) -> void:
	OS.set_environment("PROPHECY_PACING", v)

## 그 날짜의 대표 출격을 만든다(테마 경로 고정 — 조건 사이에 편성이 달라지지 않게)
func make_fight(seed_v: int, day: int) -> CombatState:
	var run := PRun.new_run(seed_v, "sword", "", { "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	run.day = day
	run.stage = 0 if day < 4 else (1 if day < 7 else 2)
	grow(run, int(PICKS_BY_DAY.get(day, 4)))
	var cards := PSortie.cards_for(run)
	if cards.is_empty():
		return null
	var card: Dictionary = cards[0]
	var sortie := PSortie.start(run, String(card.id))
	if sortie.is_empty():
		return null
	return CombatState.new(PFlow.encounter_opts(run, sortie))

func measure(seed_v: int, day: int, policy: String) -> Dictionary:
	var st := make_fight(seed_v, day)
	if st == null:
		return {}
	var bot := PBot.new(policy)
	var n := 0
	while st.status == "running" and n < int(MAX_SEC / STEP):
		st.step(bot.step_input(st), STEP)
		n += 1
	var prepared := 0
	var executed := 0
	var spawned := 0
	var died_before_attack := 0
	var died_before_execute := 0
	for k in (st.metrics.enemies as Dictionary):
		var m: Dictionary = st.metrics.enemies[k]
		prepared += int(m.get("prepared", 0))
		executed += int(m.get("executed", 0))
		spawned += int(m.get("spawned", 0))
		died_before_attack += int(m.get("died_before_attack", 0))
		died_before_execute += int(m.get("died_before_execute", 0))
	var hits := 0
	for k in (st.metrics.taken_hits as Dictionary):
		hits += int(st.metrics.taken_hits[k])
	return {
		"seed": seed_v, "day": day, "policy": policy, "status": st.status,
		"sec": snapped(st.t, 0.01), "spawned": spawned, "killed": int(st.stats.kills),
		"prepared": prepared, "executed": executed, "hits": hits,
		"taken": snapped(float(st.stats.damage_taken), 0.1),
		"hp_left": snapped(maxf(0.0, float(st.player.hp)), 0.1),
		"died_before_attack": died_before_attack, "died_before_execute": died_before_execute,
	}

## 연속 출격: 회복 없이 3회 이어 나갔을 때의 잔여 체력과, 그 시점에 휴식을 고를 만한지
func measure_streak(seed_v: int, day: int, policy: String) -> Dictionary:
	var run := PRun.new_run(seed_v, "sword", "", { "route": ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"] })
	run.day = day
	run.stage = 0 if day < 4 else (1 if day < 7 else 2)
	grow(run, int(PICKS_BY_DAY.get(day, 4)))
	var hp_track := []
	var heal := 0.0
	var rest := 0
	for i in 3:
		var cards := PSortie.cards_for(run)
		if cards.is_empty():
			break
		var sortie := PSortie.start(run, String(cards[0].id))
		if sortie.is_empty():
			break
		var st := CombatState.new(PFlow.encounter_opts(run, sortie))
		var bot := PBot.new(policy)
		var n := 0
		while st.status == "running" and n < int(MAX_SEC / STEP):
			st.step(bot.step_input(st), STEP)
			n += 1
		var before := float(run.hp)
		run.hp = maxf(0.0, float(st.player.hp))
		hp_track.append(snapped(float(run.hp), 0.1))
		heal += maxf(0.0, float(run.hp) - before + float(st.stats.damage_taken))
		if st.status == "lost":
			break
		# 휴식을 고를 만한 상태인가: 최대 체력의 절반 아래면 사람이라면 쉰다고 본다(판정 기준일 뿐 강제 아님)
		if float(run.hp) < float(PRun.build(run).hp_max) * 0.5:
			rest += 1
	return { "seed": seed_v, "day": day, "policy": policy, "hp_track": hp_track,
		"rest_worth": rest, "fights": hp_track.size() }

func _init() -> void:
	for variant in ["counts", "full"]:
		set_variant(variant)
		for day in DAYS:
			for policy in POLICIES:
				for sd in SEEDS:
					var r := measure(sd, day, policy)
					if r.is_empty():
						continue
					r["variant"] = variant
					rows.append(r)
				var sr := measure_streak(SEEDS[0], day, policy)
				sr["variant"] = variant
				runs.append(sr)
			printerr("done ", variant, " day", day)
	set_variant("")
	print("HP_EFFECT_JSON " + JSON.stringify({ "rows": rows, "runs": runs }))
	_write()
	quit()

static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

func _pick(variant: String, day: int, policy: String) -> Array:
	var out := []
	for r in rows:
		if String(r.variant) == variant and int(r.day) == day and String(r.policy) == policy:
			out.append(r)
	return out

func _write() -> void:
	var md := "# 체력 상향의 실제 효과 (전투 시간 말고 무엇이 달라졌나)\n\n"
	md += "생성: `tools/hp_effect_report.gd` (%s, Godot %s). 시드 %s · 날짜 %s · 상한 %.0f초.\n" % [OS.get_name(), Engine.get_version_info().string, str(SEEDS), str(DAYS), MAX_SEC]
	md += "**전** = `PROPHECY_PACING=counts`(적 수·편성은 지금과 같고 체력 오버레이만 끈 상태) · **후** = 현재(H3 체력표).\n"
	md += "적 수·편성·경험치·금화는 두 조건에서 같다. 달라지는 것은 **체력뿐**이다.\n\n"
	md += "> 봇 결과는 규칙 검증용이며 사람 조작감·최종 밸런스 판단이 아니다. 봇 승패를 통과 조건으로 쓰지 않았다.\n\n"
	md += "## 1. 적이 실제로 공격했는가 (정책별)\n\n"
	md += "| 날짜 | 정책 | 조건 | 결과 | 등장 | 공격 준비 | 공격 실행 | 플레이어 명중 | 준비 전 사망 | 실행 전 사망 | 전투(초) |\n"
	md += "|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|\n"
	for day in DAYS:
		for policy in POLICIES:
			for variant in ["counts", "full"]:
				var a := _pick(variant, day, policy)
				if a.is_empty():
					continue
				var wins := 0
				var losses := 0
				for r in a:
					if String(r.status) == "won":
						wins += 1
					elif String(r.status) == "lost":
						losses += 1
				md += "| %d | %s | %s | %d승 %d패 | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.1f |\n" % [day, policy,
					"전" if variant == "counts" else "**후**", wins, losses,
					_avg(a.map(func(r): return r.spawned)), _avg(a.map(func(r): return r.prepared)),
					_avg(a.map(func(r): return r.executed)), _avg(a.map(func(r): return r.hits)),
					_avg(a.map(func(r): return r.died_before_attack)), _avg(a.map(func(r): return r.died_before_execute)),
					_avg(a.map(func(r): return r.sec))]
	md += "\n**준비 전 사망**은 공격을 예고하기도 전에 죽은 개체 수다. 사용자가 말한 \"가만히 있어도 접근하다 죽는다\"가 이 숫자다.\n"
	md += "\n## 2. 제자리 · 추적 · 회피의 받은 피해\n\n"
	md += "| 날짜 | 조건 | 제자리 | 추적·공격 | 회피 우선 |\n|---:|---|---:|---:|---:|\n"
	for day in DAYS:
		for variant in ["counts", "full"]:
			var cells := []
			for policy in POLICIES:
				var a := _pick(variant, day, policy)
				cells.append(_avg(a.map(func(r): return r.taken)))
			md += "| %d | %s | %.0f | %.0f | %.0f |\n" % [day, "전" if variant == "counts" else "**후**", cells[0], cells[1], cells[2]]
	md += "\n제자리와 회피의 차이가 클수록 \"예고를 읽고 움직이면 피할 수 있다\"에 가깝다. 둘 다 0에 가까우면 압박 자체가 없는 것이다.\n"
	md += "\n## 3. 연속 출격 3회의 잔여 체력\n\n"
	md += "| 날짜 | 정책 | 조건 | 1회 뒤 | 2회 뒤 | 3회 뒤 | 휴식할 만한 시점 |\n|---:|---|---|---:|---:|---:|---:|\n"
	for r in runs:
		var t: Array = r.hp_track
		md += "| %d | %s | %s | %s | %s | %s | %d회 |\n" % [int(r.day), String(r.policy),
			"전" if String(r.variant) == "counts" else "**후**",
			("%.0f" % float(t[0])) if t.size() > 0 else "-",
			("%.0f" % float(t[1])) if t.size() > 1 else "-",
			("%.0f" % float(t[2])) if t.size() > 2 else "-",
			int(r.rest_worth)]
	md += "\n회복은 하지 않고 이어서 나간 값이다. '휴식할 만한 시점'은 최대 체력의 절반 아래로 떨어진 횟수이며 강제 규칙이 아니라 판단 기준이다.\n"
	md += "\n## 읽는 법\n\n"
	md += "- 전투 시간이 늘어난 것만으로는 목표를 만족했다고 할 수 없다. **공격 실행·명중이 함께 늘어야** 한다.\n"
	md += "- 준비 전 사망이 줄지 않았다면 체력이 아니라 접근 거리·등장 위치·이동을 손봐야 한다.\n"
	md += "- 회피 정책의 받은 피해가 제자리와 비슷하면 예고를 읽을 방법이 없다는 뜻이다. 반대로 회피가 0이면 압박이 없다.\n"
	var f := FileAccess.open("res://docs/sim/HP_EFFECT.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
