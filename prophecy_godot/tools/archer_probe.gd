extends SceneTree
## 궁수 상대 봇 행동 측정(화면 없음):
##   godot --headless --path prophecy_godot -s tools/archer_probe.gd
## 결과: docs/sim/ARCHER_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 사용자 지적: "궁수 상대할 때 답답해 죽겠다. 봇이 멍청해서 시뮬레이션이 오래 걸린다."
## 원인 후보: 궁수의 조준선은 발사 전까지 플레이어를 따라오는데, 봇이 그걸 피하려고
## 옆걸음만 반복해 거리를 좁히지 못한다. 궁수가 여럿이면 항상 누군가 조준 중이라 끝나지 않는다.
##
## 재는 것: 처치까지 걸린 시간 · 실제로 준 피해 · 받은 피해 · 거리 변화 · 회피 횟수.
## 부분 실행 축: n(궁수 수) · seed

const STEP := 1.0 / 120.0
const MAX_SEC := 120.0
const COUNTS := [1, 2, 3]
const SEEDS := [1, 2, 3]

var sub := PSubset.new()
var rows := []

## 궁수 n마리를 실제 체력으로 세우고 실력 봇에게 맡긴다. 플레이어는 그 시점 빌드
func run_one(n: int, seed_v: int, tier: String) -> Dictionary:
	var run := PRun.new_run(seed_v, "sword")
	for i in 6:   # 보통 수준 공격 투자(레벨 몇 번 + 개조)
		var g: Dictionary = run.growth
		var w: Dictionary = g.weapons[0]
		var c := {}
		if (w.mods as Array).size() < PGrowth.mod_quota(int(w.level)):
			for mid in (PCatalog.weapon("sword").get("mods", {}) as Dictionary):
				if bool(PCatalog.weapon("sword").mods[mid].get("impl", false)) and not (w.mods as Array).has(String(mid)):
					c = { "kind": "weapon_mod", "id": "sword", "mod": String(mid) }
					break
		if c.is_empty() and int(w.level) < 5:
			c = { "kind": "weapon_level", "id": "sword" }
		if c.is_empty() or not PGrowth.apply_choice(run, c):
			break
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [[{ "type": "wolf", "n": 1 }]], "objective": "clear", "region_id": "forest",
		"pool": ["archer"], "run": run })
	st.spawn_hold = true
	for e in st.enemies:
		e.dead = true
	st.pending.clear()
	var px: float = st.player.x
	var py: float = st.player.y
	var targets := []
	for i in n:
		targets.append(st.spawn_enemy("archer", px + 320.0, py - 60.0 + float(i) * 60.0, false, tier))
	var bot := PSkillBot.new("skilled", seed_v)
	var steps := int(MAX_SEC / STEP)
	var d0 := 320.0
	var d_min := 1.0e9
	var i2 := 0
	while i2 < steps:
		var alive := 0
		for e in targets:
			if not e.dead:
				alive += 1
		if alive == 0:
			break
		st.step(bot.step_input(st), STEP)
		for e in targets:
			if not e.dead:
				d_min = minf(d_min, PGeom.dist(float(e.x), float(e.y), float(st.player.x), float(st.player.y)))
		i2 += 1
	var killed := 0
	for e in targets:
		if e.dead:
			killed += 1
	var dealt := 0.0
	for k in (st.metrics.dmg as Dictionary):
		dealt += float(st.metrics.dmg[k])
	return { "n": n, "seed": seed_v, "tier": tier, "sec": snapped(st.t, 0.01), "killed": killed,
		"dealt": snapped(dealt, 0.1), "taken": snapped(float(st.stats.damage_taken), 0.1),
		"dodges": int(st.stats.dodges), "start_dist": d0, "closest": snapped(d_min, 0.1),
		"timeout": killed < n }

func _init() -> void:
	for tier in sub.pick("tier", ["normal", "red", "apex"]):
		for n in sub.pick("n", COUNTS):
			for sd in sub.pick("seed", SEEDS):
				rows.append(run_one(int(n), int(sd), String(tier)))
				printerr("done ", tier, " n=", n, " seed=", sd)
	print("ARCHER_PROBE_JSON " + JSON.stringify(rows))
	var md := "# 궁수 상대 봇 행동 측정\n\n"
	md += "생성: `tools/archer_probe.gd` (%s, Godot %s). 궁수를 320px 밖에 세우고 실력 봇에게 맡긴다. 상한 %.0f초.\n" % [OS.get_name(), Engine.get_version_info().string, MAX_SEC]
	md += sub.describe("궁수 상대 측정") + "\n\n"
	md += "| 등급 | 궁수 수 | 시드 | 처치 | 걸린 시간(초) | 가장 가까이 간 거리 | 준 피해 | 받은 피해 | 회피 | 시간 초과 |\n"
	md += "|---:|---:|---:|---:|---:|---:|---:|---:|---|\n"
	for r in rows:
		md += "| %d | %d | %d/%d | %.1f | %.0f | %.0f | %.0f | %d | %s |\n" % [int(r.n), int(r.seed),
			int(r.killed), int(r.n), float(r.sec), float(r.closest), float(r.dealt), float(r.taken),
			int(r.dodges), "**초과**" if bool(r.timeout) else "-"]
	md += "\n**시간 초과**는 상한 %.0f초 안에 못 잡았다는 뜻이다. 가장 가까이 간 거리가 시작 거리(320px) 근처면 접근 자체를 못 한 것이다.\n" % MAX_SEC
	var f := FileAccess.open(sub.out_path("res://docs/sim/ARCHER_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()
