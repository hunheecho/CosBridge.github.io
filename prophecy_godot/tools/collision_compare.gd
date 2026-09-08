extends SceneTree
## 장애물 접촉 탈출 수정의 전후 비교(화면 없음):
##   godot --headless --path prophecy_godot -s tools/collision_compare.gd
## 같은 설정·같은 시드로 수정 전(legacy)과 수정 후를 **한 프로세스에서** 돌려 대조한다.
## 결과: docs/sim/COLLISION_FIX_COMPARE.md
##
## 수정 내용: 이미 닿아 있는 장애물에 대해 멀어지거나 접선 방향으로 가는 이동은 막지 않는다.
## 수정 전에는 `push_out`이 정확히 접점에 놓은 뒤 스윕 판정이 어느 방향이든 t=0으로 막아
## 플레이어·적이 바위에 붙으면 영원히 못 움직였다.
##
## 봇 결과는 규칙 검증용이며 사람 조작감·최종 밸런스 판단이 아니다.
## **여기 나오는 수정 후 값은 사람이 승인한 기준이 아니다.** 기존 기준표(docs/DENSITY_REPORT.md)는
## 과거 비교용으로 그대로 둔다.

const STEP := 1.0 / 120.0
const SEEDS := [1, 2, 3, 4, 5, 6]
const FORMS := ["base", "x5", "x10"]
const POLICIES := ["stand", "active"]
const MAX_SEC := 240.0

func run_one(fid: String, pol: String, seed_v: int, legacy: bool) -> Dictionary:
	CombatState.collision_legacy = legacy
	var G := preload("res://scripts/game/game.gd")
	var cfg: Dictionary = G.config_with(G.load_config(), "hold", 1.5, fid, 2)
	var st := CombatState.first_fight(cfg, seed_v)
	var bot := PBot.new(pol)
	var n := 0
	var blocked_steps := 0     # 접촉 상태에서 이동이 0으로 막힌 단계 수(수정 전 관찰용)
	var frozen_enemy_steps := 0 # 적이 장애물에 닿은 채 한 단계 동안 전혀 움직이지 않은 횟수
	while st.status == "running" and n < int(MAX_SEC / STEP):
		var px0: float = st.player.x
		var py0: float = st.player.y
		var prev := {}
		for e in st.enemies:
			if not e.dead:
				prev[int(e.id)] = [float(e.x), float(e.y)]
		st.step(bot.step_input(st), STEP)
		if _touching(st, st.player) and absf(float(st.player.x) - px0) < 1e-6 and absf(float(st.player.y) - py0) < 1e-6:
			blocked_steps += 1
		for e in st.enemies:
			if e.dead or not prev.has(int(e.id)):
				continue
			var p0: Array = prev[int(e.id)]
			if _touching(st, e) and absf(float(e.x) - p0[0]) < 1e-6 and absf(float(e.y) - p0[1]) < 1e-6:
				frozen_enemy_steps += 1
		n += 1
	var m: Dictionary = st.metrics.enemies.get("wolf", {})
	var sp := maxi(1, int(m.get("spawned", 0)))
	return {
		"formation": fid, "policy": pol, "seed": seed_v, "legacy": legacy,
		"status": st.status, "elapsed": snapped(st.t, 0.01), "hp": snapped(st.player.hp, 0.1),
		"taken": snapped(st.stats.damage_taken, 0.1),
		"spawned": m.get("spawned", 0), "killed": m.get("killed", 0),
		"bites_executed": m.get("bites_executed", 0), "dashes_executed": m.get("dashes_executed", 0),
		"bite_hits": m.get("bite_hits", 0), "dash_hits": m.get("dash_hits", 0),
		"died_before_execute_pct": snapped(100.0 * float(m.get("died_before_execute", 0)) / sp, 0.1),
		"xp": snapped(st.stats.xp, 0.0001), "steps": n,
		"contact_blocked_player_steps": blocked_steps,
		"contact_frozen_enemy_steps": frozen_enemy_steps,
		"escapes": st.stuck_escapes,
	}

## 장애물에 닿아 있는가(접점 오차 1px 허용)
func _touching(st: CombatState, o: Dictionary) -> bool:
	for ob in st.obstacles:
		if PGeom.dist(float(ob.x), float(ob.y), float(o.x), float(o.y)) <= float(ob.r) + float(o.r) + 1.0:
			return true
	return false

func _init() -> void:
	var old_rows := []
	var new_rows := []
	for fid in FORMS:
		for pol in POLICIES:
			for sd in SEEDS:
				old_rows.append(run_one(fid, pol, sd, true))
				new_rows.append(run_one(fid, pol, sd, false))
				printerr("done ", fid, " ", pol, " ", sd)
	CombatState.collision_legacy = false
	print("COLLISION_JSON " + JSON.stringify({ "legacy": old_rows, "fixed": new_rows }))

	var diff := 0
	var same := 0
	for i in old_rows.size():
		if _same_result(old_rows[i], new_rows[i]):
			same += 1
		else:
			diff += 1
	var md := "# 장애물 접촉 탈출 수정: 전후 비교 (같은 설정·같은 시드)\n\n"
	md += "생성: `tools/collision_compare.gd` (%s, Godot %s). 회피 hold·1.5초, 동시 돌진 2, 시드 %s, 상한 %.0f초.\n" % [OS.get_name(), Engine.get_version_info().string, str(SEEDS), MAX_SEC]
	md += "**전(legacy)** = `PROPHECY_COLLISION_LEGACY=1`과 같은 동작(수정 전). **후(fixed)** = 현재 규칙.\n\n"
	md += "> 이 표의 '후' 값은 **사람이 승인한 기준이 아니다.** 승인된 기준표는 `docs/DENSITY_REPORT.md`이며 과거 비교용으로 그대로 둔다.\n"
	md += "> 기존 표에 맞추려고 수치를 조정하지 않았다. 바뀐 것은 충돌 판정 하나뿐이다.\n\n"
	md += "결과가 달라진 행 **%d개**, 그대로인 행 **%d개** (총 %d).\n\n" % [diff, same, old_rows.size()]
	md += "## 행별 대조\n\n"
	md += "| 편성 | 정책 | 시드 | 결과(전→후) | 시간 | 남은 체력 | 등장/처치 | 물기 실행 | 돌진 실행 | 명중(물기/돌진) | 실행 전 사망% | 접촉 정지 단계(플레이어) | 접촉 정지 단계(적) | 탈출 허용 횟수 |\n"
	md += "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for i in old_rows.size():
		var a: Dictionary = old_rows[i]
		var b: Dictionary = new_rows[i]
		md += "| %s | %s | %d | %s → %s | %.1f → %.1f | %.0f → %.0f | %d/%d → %d/%d | %d → %d | %d → %d | %d/%d → %d/%d | %.0f → %.0f | %d → %d | %d → %d | %d |\n" % [
			a.formation, a.policy, a.seed, a.status, b.status, a.elapsed, b.elapsed, a.hp, b.hp,
			a.spawned, a.killed, b.spawned, b.killed, a.bites_executed, b.bites_executed,
			a.dashes_executed, b.dashes_executed, a.bite_hits, a.dash_hits, b.bite_hits, b.dash_hits,
			a.died_before_execute_pct, b.died_before_execute_pct,
			a.contact_blocked_player_steps, b.contact_blocked_player_steps,
			a.contact_frozen_enemy_steps, b.contact_frozen_enemy_steps, b.escapes]
	md += "\n## 왜 달라졌나 (등장·이동·처치 기록)\n\n"
	md += "| 편성 | 정책 | 시드 | 수정 전 접촉 정지 단계(적) | 수정 후 | 탈출 허용 횟수 | 처치 변화 | 물기+돌진 실행 변화 |\n|---|---|---|---|---|---|---|---|\n"
	for i in old_rows.size():
		var a: Dictionary = old_rows[i]
		var b: Dictionary = new_rows[i]
		if _same_result(a, b):
			continue
		md += "| %s | %s | %d | %d | %d | %d | %d → %d | %d → %d |\n" % [a.formation, a.policy, a.seed,
			a.contact_frozen_enemy_steps, b.contact_frozen_enemy_steps, b.escapes, a.killed, b.killed,
			int(a.bites_executed) + int(a.dashes_executed), int(b.bites_executed) + int(b.dashes_executed)]
	md += "\n읽는 법.\n\n"
	md += "- **접촉 정지 단계**: 장애물에 닿은 개체가 그 단계에서 한 픽셀도 움직이지 못한 횟수. 수정 전에는 바위에 붙은 늑대가 굳어 물기·돌진을 실행하지 못한 채 죽었다.\n"
	md += "- **탈출 허용 횟수**: 새 예외가 실제로 이동을 살린 횟수. 정지 단계가 0인 행도 이 값이 0이 아니면 결과가 달라진다 — 완전히 멈추지는 않았지만 **이동량이 깎이던** 경우이고, 그 작은 차이가 이후 위치·표적·처치 순서를 바꾼다.\n"
	md += "- 그래서 같은 시드에서도 처치 수·공격 실행 수·전투 시간이 달라진다. **적 체력·피해·등장 수·난수는 하나도 바꾸지 않았다.** 바뀐 것은 접촉 상태의 이동 판정 하나다.\n"
	var f := FileAccess.open("res://docs/sim/COLLISION_FIX_COMPARE.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()

func _same_result(a: Dictionary, b: Dictionary) -> bool:
	for k in ["status", "elapsed", "hp", "spawned", "killed", "bites_executed", "dashes_executed", "bite_hits", "dash_hits", "xp"]:
		if a[k] != b[k]:
			return false
	return true
