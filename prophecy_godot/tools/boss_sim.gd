extends SceneTree
## 보스전 헤드리스 측정(HTML tools/boss_sim.js·boss_matrix.js 이식): 고정 빌드(PCatalog.lab().BUILDS) × 보스 3종 × 봇 정책 × 시드.
## 사용: PROPHECY_SIM_SEEDS=11,18 godot --headless --path prophecy_godot -s tools/boss_sim.gd
## 환경 변수: PROPHECY_BOSS_BUILDS("stage1,stage2,stage3,stop3_final") PROPHECY_SIM_BOT(정책 목록, "still,balanced,survival") PROPHECY_SIM_SEEDS("11,18,25")
##   PROPHECY_SIM_OUT(res://docs/sim/BOSS_SIM.md). 보스 체력은 회차 규칙(PRun.boss_hp, 세트 hi)에서 읽는다(F8). 결과: 마크다운 + BOSS_SIM_JSON 한 줄.
## 기록: 승패·시간, 남은 체력, 보스 남은 체력, 받은 유효 피해, 흡수·회복, 보스 공격 실행, 패턴 실행, Q/E, 출처별 피해. 봇 결과는 사람 승률이 아니다.

const BOSSES := ["boss", "guardian", "eater"]
const MAX_SEC := 300.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _list(s: String) -> Array:
	var out := []
	for p in s.split(","):
		var t := String(p).strip_edges()
		if t != "":
			out.append(t)
	return out

## 실험실 프리셋 → 회차 dict(성장·장비·강화). 회차 규칙(PRun.new_run)으로 만들고 성장만 덮어쓴다(boss_matrix.js mkRun)
func make_run(seed: int, preset: Dictionary) -> Dictionary:
	var gw: Dictionary = preset.growth
	var first := String((gw.weapons as Array)[0].id)
	var run := PRun.new_run(seed, first)
	run.bossHpSet = "hi"
	var g: Dictionary = run.growth
	var ws := []
	for w in gw.weapons:
		ws.append({ "id": String(w.id), "level": int(w.level), "mods": (w.mods as Array).duplicate() if w.has("mods") else [] })
	g.weapons = ws
	var cm := {}
	for k in gw.get("commons", {}):
		cm[String(k)] = int(gw.commons[k])
	g.commons = cm
	var ps := {}
	for k in gw.get("passives", {}):
		ps[String(k)] = int(gw.passives[k])
	g.passives = ps
	if gw.has("e"):
		g.skills.e = { "id": String(gw.e.id), "level": int(gw.e.level), "variant": (String(gw.e.variant) if gw.e.get("variant", null) != null else null) }
	if gw.has("q"):
		g.skills.q.level = int(gw.q.get("level", 1))
		g.skills.q.variant = String(gw.q.variant) if gw.q.get("variant", null) != null else null
	var br := []
	for id in gw.get("bossRewards", []):
		br.append(String(id))
	g.bossRewards = br
	var lv := 1
	for w in ws:
		lv += int(w.level) - 1 + (w.mods as Array).size()
	for k in cm:
		lv += int(cm[k])
	for k in ps:
		lv += int(ps[k])
	g.level = lv
	var eq: Dictionary = preset.get("equipment", {})
	for slot in eq:
		if eq[slot] != null and PCatalog.equipment().has(String(eq[slot])):
			run.equipment[String(slot)] = String(eq[slot])
	var gear: Dictionary = preset.get("gear", {})
	run.forge = int(preset.get("forge", gear.get("upgrade", 0)))
	run.hp = float(PRun.build(run).hp_max)
	return run

func fight(run: Dictionary, boss_id: String, pol: String, seed: int) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed, "boss": true, "boss_id": boss_id, "boss_hp": PRun.boss_hp(run, boss_id),
		"arena": "clearing", "region_id": "boss", "xp_kill_mult": PRun.kill_xp_mult(run), "run": run })
	PBot.run_combat(st, pol, { "max_sec": MAX_SEC })
	if st.status == "running":
		st.status = "timeout"
		st.delayed.clear()
	var sm := st.summary()
	var attempts := 0
	for k in sm.enemies:
		if BOSSES.has(String(k)) or String(k).begins_with(boss_id):
			attempts += int(sm.enemies[k].get("executed", 0))
	var hits_on := 0
	var th: Dictionary = sm.taken_hits
	for k in th:
		var ks := String(k)
		if ks.begins_with("boss") or ks.find("sweep") >= 0 or ks.find("dash") >= 0 or ks.find("pounce") >= 0 or ks.find("shock") >= 0 or ks.find("wide") >= 0 or ks.find("mark") >= 0 or ks.find("lane") >= 0 or ks.find("slam") >= 0 or ks.find("beam") >= 0:
			hits_on += int(th[k])
	var by_src := {}
	for k in sm.dmg:
		by_src[String(k)] = float(sm.dmg[k])
	return { "status": st.status, "t": round(st.t * 10.0) / 10.0, "hp": round(float(st.player.hp)), "bossHp": round(float(st.boss.hp)) if not st.boss.is_empty() else 0.0, "bossHpMax": round(float(st.boss.hp_max)) if not st.boss.is_empty() else 0.0,
		"taken": round(float(sm.damage_taken)), "absorbed": round(float(sm.absorbed)), "heal": round(float(sm.healed)), "attempts": attempts, "hitsOn": hits_on, "patterns": (sm.patterns as Dictionary).duplicate(),
		"q": int(sm.special_uses), "e": int(sm.e_uses), "bd": round(float(sm.boss_damage)), "kills": int(sm.kills), "bySrc": by_src, "seed": seed, "policy": pol, "boss": boss_id, "phase": int(st.boss.get("phase", 0)) if not st.boss.is_empty() else 0 }

func _avg(list: Array, key: String) -> String:
	if list.is_empty():
		return "-"
	var s := 0.0
	for r in list:
		s += float(r[key])
	return str(int(round(s / float(list.size()))))

func _init() -> void:
	var LAB := PCatalog.lab()
	var BUILDS: Dictionary = LAB.get("BUILDS", {})
	var build_ids := []
	for id in _list(_env("PROPHECY_BOSS_BUILDS", "stage1,stage2,stage3,stop3_final")):
		if BUILDS.has(id):
			build_ids.append(id)
		else:
			printerr("알 수 없는 빌드: " + id)
	var pols := []
	for p in _list(_env("PROPHECY_SIM_BOT", "still,balanced,survival")):
		if PBot.policies().has(p) or p == "stand" or p == "active":
			pols.append(p)
	var seeds := []
	for s in _list(_env("PROPHECY_SIM_SEEDS", "11,18,25")):
		if s.is_valid_int():
			seeds.append(int(s))
	var out_path := _env("PROPHECY_SIM_OUT", "res://docs/sim/BOSS_SIM.md")
	var probe := make_run(1, BUILDS[build_ids[0]] if build_ids.size() > 0 else { "growth": { "weapons": [{ "id": "sword", "level": 1 }] } })
	var boss_hp := {}
	for bid in BOSSES:
		boss_hp[bid] = int(PRun.boss_hp(probe, bid))
	printerr("boss_sim: builds=%s bosses=%s policies=%s seeds=%s bossHpSet=%s hp=%s" % [str(build_ids), str(BOSSES), str(pols), str(seeds), String(probe.bossHpSet), JSON.stringify(boss_hp)])
	var rows := []
	var fights := []
	var t_all := Time.get_ticks_msec()
	for bid in BOSSES:
		for build_id in build_ids:
			var preset: Dictionary = BUILDS[build_id]
			for pol in pols:
				var res := []
				for seed in seeds:
					var run := make_run(int(seed), preset)
					var r = fight(run, String(bid), String(pol), int(seed))
					if r == null or not (r is Dictionary):
						printerr("FAIL %s %s %s seed %d" % [String(bid), String(build_id), String(pol), int(seed)])
						continue
					var rd: Dictionary = r
					rd.build = String(build_id)
					rd.level = int(run.growth.level)
					res.append(rd)
					fights.append(rd)
				var wins := []
				for r in res:
					if String(r.status) == "won":
						wins.append(r)
				var pat := {}
				var src := {}
				for r in res:
					for k in r.patterns:
						pat[String(k)] = int(pat.get(String(k), 0)) + int(r.patterns[k])
					for k in r.bySrc:
						src[String(k)] = float(src.get(String(k), 0.0)) + float(r.bySrc[k])
				var pkeys := pat.keys()
				pkeys.sort()
				var pparts := []
				for k in pkeys:
					pparts.append("%s %s" % [String(k), str(round(float(pat[k]) / float(maxi(1, res.size())) * 10.0) / 10.0)])
				var tot := 0.0
				for k in src:
					tot += float(src[k])
				var skeys := src.keys()
				skeys.sort_custom(func(a, b): return float(src[a]) > float(src[b]))
				var sparts := []
				for k in skeys.slice(0, 3):
					sparts.append("%s %d%%" % [String(PStats.classify(String(k)).name), int(round(float(src[k]) / maxf(1.0, tot) * 100.0))])
				var row := { "boss": String(bid), "build": String(build_id), "buildName": String(preset.name), "policy": String(pol), "n": res.size(), "wins": wins.size(), "t": _avg(wins, "t"), "hp": _avg(res, "hp"), "bossHp": _avg(res, "bossHp"),
					"taken": _avg(res, "taken"), "absorbed": _avg(res, "absorbed"), "heal": _avg(res, "heal"), "attempts": _avg(res, "attempts"), "hitsOn": _avg(res, "hitsOn"), "q": _avg(res, "q"), "e": _avg(res, "e"), "bd": _avg(res, "bd"), "pat": ", ".join(pparts), "src": ", ".join(sparts), "level": int(probe.growth.level) }
				if res.size() > 0:
					row.level = int(res[0].level)
				rows.append(row)
				printerr("done %s %s %s: %d/%d" % [String(bid), String(build_id), String(pol), wins.size(), res.size()])
	var md := "# 보스전 헤드리스 측정 (%s, Godot %s, %s, 밸런스 %s, 보스 체력 세트 %s = 가시갈기 %d / 봉인 수호자 %d / 예언을 먹는 자 %d, 상한 %d초, 시드 %s)\n\n" % [String(preload("res://scripts/game/game.gd").VERSION), String(Engine.get_version_info().string), OS.get_name(), String(probe.balance), String(probe.bossHpSet), int(boss_hp.boss), int(boss_hp.guardian), int(boss_hp.eater), int(MAX_SEC), str(seeds)]
	md += "생성: `tools/boss_sim.gd`. 빌드는 PCatalog.lab().BUILDS 프리셋(성장·장비·강화)을 회차 dict에 넣고 PRun.build로 파생. 정책: "
	var pn := []
	for p in pols:
		pn.append("%s=%s" % [String(p), String(PBot.policies()[p].name) if PBot.policies().has(p) else String(p)])
	md += " · ".join(pn) + ". 봇 결과는 사람 승률이 아니다. 받은 피해 = 유효 피해(실제 체력 감소).\n"
	for bid in BOSSES:
		md += "\n## %s (체력 %d)\n\n| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n" % [String(PCatalog.boss_def(bid).name), int(boss_hp[bid])]
		for r in rows:
			if String(r.boss) != bid:
				continue
			md += "| %s | %d | %s | %d/%d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % [String(r.buildName), int(r.level) - 1, String(PBot.policies()[r.policy].name) if PBot.policies().has(r.policy) else String(r.policy), int(r.wins), int(r.n), String(r.t), String(r.hp), String(r.bossHp), String(r.taken), String(r.absorbed), String(r.heal), String(r.attempts), String(r.hitsOn), String(r.q), String(r.e), String(r.bd), String(r.pat), String(r.src)]
	md += "\n## 전투별\n\n| 보스 | 빌드 | 정책 | 시드 | 결과 | 초 | 남은 체력 | 보스 남은/최대 | 받은 피해 | 처치(소환) | Q | E | 패턴 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for f in fights:
		var pp := []
		for k in f.patterns:
			pp.append("%s %d" % [String(k), int(f.patterns[k])])
		md += "| %s | %s | %s | %d | %s | %s | %d | %d/%d | %d | %d | %d | %d | %s |\n" % [String(PCatalog.boss_def(String(f.boss)).name), String(f.build), String(f.policy), int(f.seed), String(f.status), str(f.t), int(f.hp), int(f.bossHp), int(f.bossHpMax), int(f.taken), int(f.kills), int(f.q), int(f.e), ", ".join(pp)]
	md += "\n## 읽는 법\n- \"제자리 Q/E\"(still)와 이동 정책의 차이 = 이동·회피가 보스 행동·생존에 미친 영향(같은 빌드·시드).\n- 보스 공격 실행 대비 명중이 0에 가까우면 정지한 플레이어를 못 맞히는 것이므로 재현·수정 대상.\n- 제자리 행동이 이기는 칸은 \"서서 버티며 이김\"의 신호. 원인은 체력 부족으로 단정하지 않는다(공격 빈도·명중률·틈을 함께 본다).\n"
	var dir := ProjectSettings.globalize_path(out_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	else:
		printerr("쓰기 실패: " + out_path)
	print("BOSS_SIM_JSON " + JSON.stringify({ "bossHp": boss_hp, "bossHpSet": String(probe.bossHpSet), "balance": String(probe.balance), "builds": build_ids, "policies": pols, "seeds": seeds, "rows": rows, "fights": fights }))
	printerr("boss_sim: %d fights in %d ms → %s" % [fights.size(), Time.get_ticks_msec() - t_all, out_path])
	quit(0)
