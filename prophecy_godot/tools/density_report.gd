extends SceneTree
## 밀도 비교 시뮬레이션(화면 없음): godot --headless --path prophecy_godot -s tools/density_report.gd
## 같은 시드 묶음 × 편성(base/x5/x10) × 봇 정책(stand/active). 결과: DENSITY_JSON 한 줄 + docs/DENSITY_REPORT.md
## 봇 결과는 규칙 검증용이며 사람 조작감·최종 밸런스 판단이 아니다.

const STEP := 1.0 / 120.0
const SEEDS := [1, 2, 3, 4, 5, 6]
const FORMS := ["base", "x5", "x10"]
const POLICIES := ["stand", "active"]
const MAX_SEC := 240.0

func run_one(fid: String, pol: String, seed_v: int) -> Dictionary:
	var G := preload("res://scripts/game/game.gd")
	var cfg: Dictionary = G.config_with(G.load_config(), "hold", 1.5, fid, 2)
	var st := CombatState.first_fight(cfg, seed_v)
	var bot := PBot.new(pol)
	var n := 0
	var us0 := Time.get_ticks_usec()
	while st.status == "running" and n < int(MAX_SEC / STEP):
		st.step(bot.step_input(st), STEP)
		n += 1
	var us := Time.get_ticks_usec() - us0
	var m: Dictionary = st.metrics.enemies.get("wolf", {})
	var sp := maxi(1, int(m.get("spawned", 0)))
	return {
		"formation": fid, "policy": pol, "seed": seed_v, "status": st.status, "elapsed": snapped(st.t, 0.01),
		"hp": snapped(st.player.hp, 0.1), "taken": snapped(st.stats.damage_taken, 0.1), "taken_by": st.metrics.taken.duplicate(),
		"spawned": m.get("spawned", 0), "killed": m.get("killed", 0),
		"bites_per_wolf": snapped(float(m.get("bites_executed", 0)) / sp, 0.01), "dashes_per_wolf": snapped(float(m.get("dashes_executed", 0)) / sp, 0.01),
		"bite_hits": m.get("bite_hits", 0), "dash_hits": m.get("dash_hits", 0),
		"died_before_attack_pct": snapped(100.0 * float(m.get("died_before_attack", 0)) / sp, 0.1),
		"died_before_execute_pct": snapped(100.0 * float(m.get("died_before_execute", 0)) / sp, 0.1),
		"max_alive": st.stats.max_alive, "max_dash_states": st.stats.max_dash_states, "max_bite_states": st.stats.max_bite_states,
		"xp": snapped(st.stats.xp, 0.0001), "xp_per_kill": snapped(st.xp_per_kill(), 0.0001),
		"dodges": st.stats.dodges, "perfect": st.stats.perfect_dodges, "q": st.stats.special_uses,
		"sim_us_per_step": snapped(float(us) / maxf(1.0, n), 0.1), "steps": n,
	}

func _init() -> void:
	var rows := []
	for fid in FORMS:
		for pol in POLICIES:
			for sd in SEEDS:
				rows.append(run_one(fid, pol, sd))
				printerr("done ", fid, " ", pol, " ", sd)
	print("DENSITY_JSON " + JSON.stringify(rows))
	var md := "# 밀도 비교 시뮬레이션(봇, 규칙 검증용 — 사람 조작감·최종 밸런스 판단 아님)\n\n"
	md += "설정: 회피 hold·1.5초, 동시 돌진 2, 늑대 체력 30, 물기 12/돌진 12, 시드 %s, 상한 %.0f초. 생성: `tools/density_report.gd` (%s, Godot %s). 받은 피해 = 유효 피해(실제 체력 감소, 과잉 제외; godot-0.3.1 피해 통계 수정 이후). 같은 코드라도 OS가 다르면 긴 전투의 시간·처치가 달라질 수 있다(PORT_NOTES §11).\n\n" % [str(SEEDS), MAX_SEC, OS.get_name(), Engine.get_version_info().string]
	md += "> **이 표는 2026-09-08 장애물 접촉 탈출 수정 *이전*의 동작이다.** 사용자가 승인한 첫 전투 기준이므로 그대로 보존한다. 같은 값을 다시 만들려면 `PROPHECY_COLLISION_LEGACY=1`을 켜고 이 도구를 돌린다(그 환경에서 44행이 정확히 재현되는 것을 확인했다). 수정 이후의 같은 시드 결과는 `docs/sim/COLLISION_FIX_COMPARE.md`에 따로 있으며, 그쪽 값은 사람이 승인한 기준이 아니다.

"
	md += "| 편성 | 정책 | 시드 | 결과 | 시간 | 남은 체력 | 받은 피해(물기/돌진) | 등장/처치 | 물기/마리 | 돌진/마리 | 물기 명중 | 돌진 명중 | 예고 전 사망% | 실행 전 사망% | 최대 생존 | 최대 돌진상태 | 최대 물기상태 | 경험치 | 회피(회피!) | Q | 시뮬 µs/단계 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in rows:
		md += "| %s | %s | %d | %s | %.1f | %.0f | %.0f (%s/%s) | %d/%d | %.2f | %.2f | %d | %d | %.0f | %.0f | %d | %d | %d | %.4f | %d(%d) | %d | %.1f |\n" % [r.formation, r.policy, r.seed, r.status, r.elapsed, r.hp, r.taken, str(r.taken_by.get("wolf:bite", 0)), str(r.taken_by.get("wolf:dash", 0)), r.spawned, r.killed, r.bites_per_wolf, r.dashes_per_wolf, r.bite_hits, r.dash_hits, r.died_before_attack_pct, r.died_before_execute_pct, r.max_alive, r.max_dash_states, r.max_bite_states, r.xp, r.dodges, r.perfect, r.q, r.sim_us_per_step]
	md += "\n## 편성 × 정책 평균(시드 %d개)\n\n| 편성 | 정책 | 승/패 | 평균 시간 | 평균 받은 피해 | 물기/마리 | 돌진/마리 | 물기 명중 | 돌진 명중 | 예고 전 사망%% | 실행 전 사망%% | 최대 생존 | 최대 돌진상태 | 최대 물기상태 | 경험치 | 시뮬 µs/단계 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n" % SEEDS.size()
	for fid in FORMS:
		for pol in POLICIES:
			var sub := rows.filter(func(r): return r.formation == fid and r.policy == pol)
			var wins := sub.filter(func(r): return r.status == "won").size()
			md += "| %s | %s | %d/%d | %.1f | %.1f | %.2f | %.2f | %.1f | %.1f | %.0f | %.0f | %d | %d | %d | %.4f | %.0f |\n" % [fid, pol, wins, sub.size() - wins, _avg(sub, "elapsed"), _avg(sub, "taken"), _avg(sub, "bites_per_wolf"), _avg(sub, "dashes_per_wolf"), _avg(sub, "bite_hits"), _avg(sub, "dash_hits"), _avg(sub, "died_before_attack_pct"), _avg(sub, "died_before_execute_pct"), _max(sub, "max_alive"), _max(sub, "max_dash_states"), _max(sub, "max_bite_states"), _avg(sub, "xp"), _avg(sub, "sim_us_per_step")]
	var f := FileAccess.open("res://docs/DENSITY_REPORT.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit(0)

func _avg(rows: Array, key: String) -> float:
	var sum := 0.0
	for r in rows:
		sum += float(r[key])
	return sum / maxf(1.0, rows.size())

func _max(rows: Array, key: String) -> int:
	var m := 0
	for r in rows:
		m = maxi(m, int(r[key]))
	return m
