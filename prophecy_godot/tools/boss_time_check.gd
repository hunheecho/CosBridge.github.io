extends SceneTree
## 새 보스 행동 + 새 보스 체력의 실제 전투 시간 재측정(지시 6: 표를 그대로 확정하지 말고 재측정).
## 성장 체크포인트의 실제 빌드(관문 시점)로 각 관문 보스를 싸운다. 이동 없음+Q/E 자동 / 추적만 / 실력 봇을 분리.
## 결과: docs/sim/BOSS_TIME.md. 봇 결과는 사람 밸런스 승인이 아니다.
const BOSS_MAX := 300.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func gate_build(seed_v: int, day: int, route: Array) -> Dictionary:
	if day <= 0:
		return PRun.new_run(seed_v, "sword", "", { "route": route })
	var rec := PRunBot.simulate(seed_v, "gradual", { "start": "sword", "bot_policy": "balanced", "max_retries": 3, "stub_gates": true, "max_days": day, "route": route })
	var r = rec.get("run_state", {})
	return r if (r is Dictionary) else {}

func fight(run: Dictionary, boss_id: String, policy: String, seed_v: int) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v * 97 + 3, "boss": true, "boss_id": boss_id,
		"boss_hp": PRun.boss_hp(run, boss_id), "arena": "clearing", "region_id": "boss", "run": run, "act": int(PRun.act_of(run).get("id", 1)) })
	var bot: PBot = PSkillBot.new(policy, seed_v) if PSkillBot.profile_ids().has(policy) else PBot.new(policy)
	PBot.run_combat(st, policy, { "max_sec": BOSS_MAX, "bot": bot })
	if st.status == "running":
		st.status = "timeout"
		st.delayed.clear()
	var sm := st.summary()
	return { "status": st.status, "sec": round(st.t * 10.0) / 10.0, "hp": int(round(float(st.player.hp))),
		"bossHpMax": int(round(float(st.boss.hp_max))) if not st.boss.is_empty() else 0,
		"bossLeft": int(round(maxf(0.0, float(st.boss.hp)))) if not st.boss.is_empty() else 0,
		"taken": int(round(float(sm.damage_taken))), "absorbed": int(round(float(sm.get("absorbed", 0.0)))), "healed": int(round(float(sm.get("healed", 0.0)))),
		"dps": round(float(st.stats.boss_damage) / maxf(0.1, st.t) * 10.0) / 10.0 }

func _init() -> void:
	var seeds := []
	for s in _env("PROPHECY_SIM_SEEDS", "1,2").split(","):
		seeds.append(int(s))
	var pols := _env("PROPHECY_SIM_BOTS", "stand,active,regular,skilled").split(",")
	var route := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)]
	var gates := [{ "id": "boss", "day": 3, "name": "가시갈기(4일차 관문)" }, { "id": "guardian", "day": 6, "name": "봉인 수호자(7일차 관문)" }, { "id": "eater", "day": 9, "name": "예언을 먹는 자(10일차 관문)" }]
	var rows := []
	var t0 := Time.get_ticks_msec()
	for g in gates:
		for seed_v in seeds:
			var run := gate_build(seed_v, int(g.day), route)
			if run.is_empty():
				continue
			for pol in pols:
				var r := fight(run, String(g.id), String(pol), seed_v)
				r["boss"] = String(g.name)
				r["seed"] = seed_v
				r["policy"] = String(pol)
				r["level"] = int(run.growth.level)
				rows.append(r)
				printerr("boss_time: %s seed %d %s → %s %.1fs hp %d/%d taken %d" % [String(g.name), seed_v, String(pol), String(r.status), float(r.sec), int(r.bossLeft), int(r.bossHpMax), int(r.taken)])
	var md := "# 새 보스 행동 + 새 보스 체력 전투 시간 재측정 (%s)\n\n" % Game.VERSION
	md += "생성: `tools/boss_time_check.gd`. 관문 시점의 실제 성장 빌드(성장 체크포인트와 같은 방식, 관문은 스텁 통과)로 각 관문 보스를 싸운다. 시드 %s.\n" % str(seeds)
	md += "조작 정책: **stand**(이동 없음 · Q/E 준비마다 자동) · **active**(보스 추적, 회피 없음) · **regular/skilled**(실력 프로필 봇). 상한 %.0f초.\n" % BOSS_MAX
	md += "받은 피해는 실제 체력 감소이고 보호막 흡수·회복을 따로 적는다. **봇은 가상 조작 모델이며 사람 보정 미완료 — 밸런스 승인이 아니다.**\n\n"
	md += "| 보스 | 시드 | Lv | 조작 | 결과 | 시간(초) | 보스 남은/최대 | 보스 DPS | 실제 체력 손실 | 보호막 흡수 | 회복 |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in rows:
		md += "| %s | %d | %d | %s | %s | %.1f | %d/%d | %.1f | %d | %d | %d |\n" % [String(r.boss), int(r.seed), int(r.level), String(r.policy), String(r.status), float(r.sec), int(r.bossLeft), int(r.bossHpMax), float(r.dps), int(r.taken), int(r.absorbed), int(r.healed)]
	md += "\n실행 벽시계: %.1f초.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var fa := FileAccess.open("res://docs/sim/BOSS_TIME.md", FileAccess.WRITE)
	fa.store_string(md)
	fa.close()
	print("BOSS_TIME_JSON " + JSON.stringify(rows))
	quit()
