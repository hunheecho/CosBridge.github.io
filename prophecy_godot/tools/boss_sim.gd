extends SceneTree
## 보스전 헤드리스 측정(HTML tools/boss_sim.js·boss_matrix.js 이식): 고정 빌드(PCatalog.lab().BUILDS) × 보스 9종(기존 3 + 신규 6) × 봇 정책 × 시드.
## 사용: PROPHECY_SIM_SEEDS=11,18 godot --headless --path prophecy_godot -s tools/boss_sim.gd
## 환경 변수: PROPHECY_BOSS_IDS(기본 9종 전부) PROPHECY_BOSS_BUILDS(비우면 막에 맞는 관문 프리셋: 1막 stage1 · 2막 stage2 · 3막 stage3; 지정하면 모든 보스에 그 빌드들)
##   PROPHECY_SIM_BOT(정책 목록, "still,balanced,survival") PROPHECY_SIM_SEEDS("11,18,25") PROPHECY_BOSS_HP_SET("hi"|"base") PROPHECY_SIM_OUT(res://docs/sim/BOSS_SIM.md).
##   PROPHECY_SIM_BEH("on"|"off"|"on,off") 보스 행동 개편(연계·옆뛰기, data/boss_behavior.json) 켬/끔 대조군.
##   PROPHECY_SIM_Q("on"|"off"|"on,off") 감속장(Q) 사용/미사용 대조군 — 같은 정책·빌드·시드로 Q 효용을 잰다.
##   정책 추가: "stillqe"(이동·회피 없음 + Q/E 준비마다), "chase"(보스 추적만·회피 없음 + Q/E 준비마다), "skill:novice|regular|skilled"(PSkillBot 실력 프로필).
##   보스 체력은 회차 규칙(PRun.boss_hp)에서, 회차 모드에 없는 신규 보스는 boss_hp_sets[세트][id][stage<막>](bosses_new.json 시험값)에서 읽는다. 결과: 마크다운 + BOSS_SIM_JSON 한 줄.
## 기록: 승패·시간, 남은 체력, 보스 남은 체력, 받은 유효 피해, 흡수·회복, 보스 공격 실행, 패턴 실행, Q/E, 출처별 피해. 봇 결과는 사람 승률이 아니다.
## "제자리(still)"가 이기는 보스는 표 끝에 따로 표시한다(수치를 고치지 않고 보고만 한다).

const ALL_BOSSES := ["boss", "gate_warden", "spore_matriarch", "guardian", "excavation_behemoth", "frost_stalker", "eater", "blood_hunt_king", "doom_executor"]
const LEGACY_ACT := { "boss": 1, "guardian": 2, "eater": 3 }
const MAX_SEC := 300.0
var BOSSES: Array = []

## 보스의 막(1~3): 신규는 정의의 act, 기존 3종은 관문 순서
static func boss_act(bid: String) -> int:
	var d := PCatalog.boss_def(bid)
	if d.has("act"):
		return int(d.act)
	return int(LEGACY_ACT.get(bid, 1))

## 보스 체력: 회차 모드(PRun.boss_hp)에 있으면 그 값, 아니면 boss_hp_sets[세트][id][stage<막>], 없으면 정의 hp
static func boss_hp_of(run: Dictionary, bid: String) -> float:
	for b in PRun.mode_def(run).bosses:
		if String(b.id) == bid:
			return PRun.boss_hp(run, bid)
	var sets := PCatalog.boss_hp_sets()
	var set_id := String(run.get("bossHpSet", "hi"))
	var H: Dictionary = sets[set_id] if sets.has(set_id) else sets.base
	var key := "stage%d" % boss_act(bid)
	if H.has(bid) and (H[bid] as Dictionary).has(key):
		return float(H[bid][key])
	return float(PCatalog.boss_def(bid).hp)

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
	run.bossHpSet = _env("PROPHECY_BOSS_HP_SET", "hi")
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

## 이번 보스 행동 개편 계측용 정책(사용자 요청 §6 "맞다이 시험도 정책을 분리한다").
## PBot.POLICIES를 건드리지 않고 여기서 사람과 같은 입력 사전만 만든다(규칙 우회 없음).
##  - "stillqe": 이동·회피 없음, Q/E는 준비될 때마다 누른다(게임이 재사용 중이면 거절한다).
##  - "chase":  보스만 따라가고 회피는 하지 않는다. Q/E는 준비될 때마다.
func custom_input(st: CombatState, pol: String) -> Dictionary:
	var p := st.player
	var mx := 0.0
	var my := 0.0
	if pol == "chase" and not st.boss.is_empty() and not bool(st.boss.dead):
		var dx: float = float(st.boss.x) - p.x
		var dy: float = float(st.boss.y) - p.y
		var d: float = maxf(1.0, sqrt(dx * dx + dy * dy))
		if d > float(st.boss.r) + float(p.r) + 6.0:
			mx = dx / d
			my = dy / d
	return { "mx": mx, "my": my, "dodge_press": false, "dodge_held": false, "special": true, "skill_e": true }

static func is_custom(pol: String) -> bool:
	return pol == "stillqe" or pol == "chase"

## 정책별 입력을 만들어 전투를 끝까지 돌린다. q_on=false면 감속장(Q)만 누르지 않는다(Q 있음/없음 비교용)
func drive(st: CombatState, pol: String, q_on: bool) -> void:
	var bot: PBot = null
	if pol.begins_with("skill:"):
		bot = PSkillBot.new(pol.substr(6), 1)
	elif not is_custom(pol):
		bot = PBot.new(pol)
	var n := int(round(MAX_SEC / PBot.STEP))
	for i in n:
		if st.status != "running":
			break
		var inp: Dictionary = custom_input(st, pol) if bot == null else bot.step_input(st)
		if not q_on:
			inp.special = false
		st.step(inp, PBot.STEP)

func fight(run: Dictionary, boss_id: String, pol: String, seed: int, opts: Dictionary = {}) -> Dictionary:
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed, "boss": true, "boss_id": boss_id, "boss_hp": boss_hp_of(run, boss_id),
		"arena": "clearing", "region_id": "boss", "xp_kill_mult": PRun.kill_xp_mult(run), "run": run })
	# 행동 개편(연계·옆뛰기)을 끈 대조군: 같은 빌드·시드로 개편 전(073f74f) 행동과 비교한다
	if not bool(opts.get("beh", true)) and not st.boss.is_empty():
		st.boss.beh_off = true
	drive(st, pol, bool(opts.get("q", true)))
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
	# 보스의 실제 공격 개시(note_attack "prepare" = attack_log)와 분당 환산
	var inits := 0
	var bid_num: int = int(st.boss.get("id", -1)) if not st.boss.is_empty() else -1
	for a in st.attack_log:
		if int(a[1]) == bid_num:
			inits += 1
	var secs: float = maxf(0.001, st.t)
	return { "status": st.status, "t": round(st.t * 10.0) / 10.0, "hp": round(float(st.player.hp)), "bossHp": round(float(st.boss.hp)) if not st.boss.is_empty() else 0.0, "bossHpMax": round(float(st.boss.hp_max)) if not st.boss.is_empty() else 0.0,
		"taken": round(float(sm.damage_taken)), "absorbed": round(float(sm.absorbed)), "heal": round(float(sm.healed)), "attempts": attempts, "hitsOn": hits_on, "patterns": (sm.patterns as Dictionary).duplicate(),
		"inits": inits, "ipm": round(float(inits) / secs * 600.0) / 10.0, "dps": round(float(sm.boss_damage) / secs * 10.0) / 10.0,
		"beh": bool(opts.get("beh", true)), "qon": bool(opts.get("q", true)),
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
	for id in _list(_env("PROPHECY_BOSS_IDS", ",".join(ALL_BOSSES))):
		if PCatalog.boss_defs().has(id):
			BOSSES.append(id)
		else:
			printerr("알 수 없는 보스: " + id)
	var build_ids := []
	var fixed_builds: bool = _env("PROPHECY_BOSS_BUILDS", "") != ""
	for id in _list(_env("PROPHECY_BOSS_BUILDS", "stage1,stage2,stage3")):
		if BUILDS.has(id):
			build_ids.append(id)
		else:
			printerr("알 수 없는 빌드: " + id)
	var pols := []
	for p in _list(_env("PROPHECY_SIM_BOT", "still,balanced,survival")):
		if PBot.policies().has(p) or p == "stand" or p == "active" or is_custom(p) or (p.begins_with("skill:") and PSkillBot.profile_ids().has(p.substr(6))):
			pols.append(p)
		else:
			printerr("알 수 없는 정책: " + p)
	# 행동 개편 on/off, 감속장(Q) on/off — 같은 빌드·시드로 대조군을 만든다
	var behs := []
	for v in _list(_env("PROPHECY_SIM_BEH", "on")):
		behs.append(v == "on")
	var qs := []
	for v in _list(_env("PROPHECY_SIM_Q", "on")):
		qs.append(v == "on")
	if behs.is_empty():
		behs = [true]
	if qs.is_empty():
		qs = [true]
	var seeds := []
	for s in _list(_env("PROPHECY_SIM_SEEDS", "11,18,25")):
		if s.is_valid_int():
			seeds.append(int(s))
	var out_path := _env("PROPHECY_SIM_OUT", "res://docs/sim/BOSS_SIM.md")
	var probe := make_run(1, BUILDS[build_ids[0]] if build_ids.size() > 0 else { "growth": { "weapons": [{ "id": "sword", "level": 1 }] } })
	var boss_hp := {}
	for bid in BOSSES:
		boss_hp[bid] = int(boss_hp_of(probe, bid))
	printerr("boss_sim: builds=%s(%s) bosses=%s policies=%s seeds=%s bossHpSet=%s hp=%s" % [str(build_ids), "고정" if fixed_builds else "막별", str(BOSSES), str(pols), str(seeds), String(probe.bossHpSet), JSON.stringify(boss_hp)])
	var rows := []
	var fights := []
	var t_all := Time.get_ticks_msec()
	for bid in BOSSES:
		var use_builds: Array = build_ids
		if not fixed_builds: # 막에 맞는 관문 프리셋 하나(1막 stage1 · 2막 stage2 · 3막 stage3)
			var want := "stage%d" % boss_act(String(bid))
			use_builds = [want] if BUILDS.has(want) else build_ids
		for build_id in use_builds:
			var preset: Dictionary = BUILDS[build_id]
			for pol in pols:
				for beh in behs:
					for q_on in qs:
							var res := []
							for seed in seeds:
								var run := make_run(int(seed), preset)
								var r = fight(run, String(bid), String(pol), int(seed), { "beh": bool(beh), "q": bool(q_on) })
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
							row.beh = bool(beh)
							row.qon = bool(q_on)
							row.ipm = _avg(res, "ipm")
							row.dps = _avg(res, "dps")
							rows.append(row)
							printerr("done %s %s %s beh=%s q=%s: %d/%d" % [String(bid), String(build_id), String(pol), "on" if beh else "off", "on" if q_on else "off", wins.size(), res.size()])
	var hp_parts := []
	for bid in BOSSES:
		hp_parts.append("%s %d" % [String(PCatalog.boss_def(bid).name), int(boss_hp[bid])])
	var md := "# 보스전 헤드리스 측정 (%s, Godot %s, %s, 밸런스 %s, 보스 체력 세트 %s = %s, 상한 %d초, 시드 %s)\n\n" % [String(preload("res://scripts/game/game.gd").VERSION), String(Engine.get_version_info().string), OS.get_name(), String(probe.balance), String(probe.bossHpSet), " / ".join(hp_parts), int(MAX_SEC), str(seeds)]
	md += "생성: `tools/boss_sim.gd`. 빌드는 PCatalog.lab().BUILDS 프리셋(성장·장비·강화)을 회차 dict에 넣고 PRun.build로 파생%s. 신규 보스 6종 수치는 bosses_new.json 시험값(사람 승인 아님). 정책: " % ("(막별 관문 프리셋: 1막 stage1 · 2막 stage2 · 3막 stage3)" if not fixed_builds else "(고정 빌드 " + ",".join(build_ids) + ")")
	var pn := []
	for p in pols:
		pn.append("%s=%s" % [String(p), String(PBot.policies()[p].name) if PBot.policies().has(p) else String(p)])
	md += " · ".join(pn) + ". 봇 결과는 사람 승률이 아니다. 받은 피해 = 유효 피해(실제 체력 감소).\n"
	for bid in BOSSES:
		md += "\n## %s (%d막 · 체력 %d)\n\n| 빌드 | 선택 수 | 정책 | 개편 | Q | 승리 | 평균 초(승) | 공격 개시/분 | 남은 체력 | 보스 남은 | 실제 체력 손실 | 보호막 흡수 | 회복 | 보스 공격 실행 | 명중 | Q회 | E회 | 보스에게 준 피해 | 보스 DPS | 패턴 실행(평균) | 피해 출처 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n" % [String(PCatalog.boss_def(bid).name), boss_act(String(bid)), int(boss_hp[bid])]
		for r in rows:
			if String(r.boss) != bid:
				continue
			md += "| %s | %d | %s | %s | %s | %d/%d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % [String(r.buildName), int(r.level) - 1, String(PBot.policies()[r.policy].name) if PBot.policies().has(r.policy) else String(r.policy), "켬" if bool(r.get("beh", true)) else "끔", "켬" if bool(r.get("qon", true)) else "끔", int(r.wins), int(r.n), String(r.t), String(r.get("ipm", "-")), String(r.hp), String(r.bossHp), String(r.taken), String(r.absorbed), String(r.heal), String(r.attempts), String(r.hitsOn), String(r.q), String(r.e), String(r.bd), String(r.get("dps", "-")), String(r.pat), String(r.src)]
	md += "\n## 전투별\n\n| 보스 | 빌드 | 정책 | 개편 | Q | 시드 | 결과 | 초 | 공격 개시/분 | 남은 체력 | 보스 남은/최대 | 실제 체력 손실 | 보호막 흡수 | 회복 | 처치(소환) | Q회 | E회 | 패턴 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for f in fights:
		var pp := []
		for k in f.patterns:
			pp.append("%s %d" % [String(k), int(f.patterns[k])])
		md += "| %s | %s | %s | %s | %s | %d | %s | %s | %s | %d | %d/%d | %d | %d | %d | %d | %d | %d | %s |\n" % [String(PCatalog.boss_def(String(f.boss)).name), String(f.build), String(f.policy), "켬" if bool(f.get("beh", true)) else "끔", "켬" if bool(f.get("qon", true)) else "끔", int(f.seed), String(f.status), str(f.t), str(f.get("ipm", 0.0)), int(f.hp), int(f.bossHp), int(f.bossHpMax), int(f.taken), int(f.absorbed), int(f.heal), int(f.kills), int(f.q), int(f.e), ", ".join(pp)]
	# 제자리 정책이 이기는 칸: 서서 버티며 이김의 신호(수치는 고치지 않고 보고)
	md += "\n## 제자리(still) 정책 결과 — 서서 버티며 이기는 보스\n\n| 보스 | 빌드 | 제자리 승리 | 판정 |\n|---|---|---|---|\n"
	for r in rows:
		if String(r.policy) != "still":
			continue
		var flag := "**경고: 제자리 자동 공격만으로 전승**" if (int(r.wins) == int(r.n) and int(r.n) > 0) else ("일부 승(관찰)" if int(r.wins) > 0 else "패(정지 표적 아님)")
		md += "| %s | %s | %d/%d | %s |\n" % [String(PCatalog.boss_def(String(r.boss)).name), String(r.build), int(r.wins), int(r.n), flag]
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
