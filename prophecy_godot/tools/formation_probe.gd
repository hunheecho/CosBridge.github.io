extends SceneTree
## **편성 계측 도구**(합격/불합격 판정이 아니다 — 수치를 남기는 것이 전부다).
##
## 왜 있는가
##   "코드에 종류가 등록됐다 / 검사가 통과했다"는 것과 "편성이 실제로 그렇게 나온다"는 것은 다르다.
##   여기서는 **실제 출격 경로**(data/themes.json → PRun.formation_waves → PFlow.encounter_opts)를 그대로 지나
##   아래를 재고 표로 남긴다.
##     ① 테마마다 대표 협공 3개가 실제로 서로 다른가(주역·비중·함께 나오는 적)
##     ② 한 전투에 몇 **종류**가 나오는가 / 동시에 상대하는 종류 수는 몇인가(개체 수와 다른 값이다)
##     ③ 분대가 실제로 역할을 갖고 나오는가(앞·지원·측면), 다음 분대가 앞 분대와 **겹쳐** 들어가는가
##     ④ 전투 말미의 대기(1~2마리 구간·자리가 비었는데 기다린 시간)
##     ⑤ 특수 정예 결투: 전환 뒤 **일반 증원 0**, 고유 소환 동작, 처치 순서
##     ⑥ 총 등장 수·경험치 예산이 개편 전과 같은가
##
## 실행
##   python tools/run_suites.py --suites formation_probe
##   (직접: godot --headless --path prophecy_godot -s tools/formation_probe.gd)
##
## 부분 실행(tools/subset.gd) — 축: act(1·2·3) / theme / formation / seed
##   PROPHECY_SUBSET="act=1;seed=1" python tools/run_suites.py --suites formation_probe
##   부분이면 결과가 docs/sim/FORMATION_PROBE_PARTIAL.md로 나간다(전체 결과 파일을 덮어쓰지 않는다).
##
## 플레이어는 계측 전용으로 죽지 않게 눌러 둔다(전투 말미와 결투까지 보는 것이 목적이다 — 봇 승패는 재지 않는다).

const STEP := 1.0 / 120.0
const SAMPLE_EVERY := 6      # 20Hz 표본(계측 전용. 규칙·난수에 영향 없음)
const MAX_SEC := 300.0
const POLICY := "balanced"
const PICKS_BY_DAY := { 1: 0, 5: 12, 9: 22 }
const DAY_OF_ACT := { 1: 1, 2: 5, 3: 9 }
## 집중 경로(사용자 지정): 사냥 숲 → 얼어붙은 협곡 → 뒤틀린 성채
const FOCUS := [
	{ "act": 1, "theme": "act1_hunt_forest", "place": "t1a_path" },
	{ "act": 2, "theme": "act2_frozen_pass", "place": "t2c_snow" },
	{ "act": 3, "theme": "act3_twisted_citadel", "place": "t3c_corridor" },
]

var sub: PSubset = null
var lines := []

func w(s: String = "") -> void:
	lines.append(s)
	print(s)

# ---------- 회차·빌드(tools/tail_probe.gd와 같은 규칙) ----------
func grow(run: Dictionary, picks: int) -> void:
	var g: Dictionary = run.growth
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
		var wp := PGrowth.weapon_of(g, wid)
		if (wp.mods as Array).size() < PGrowth.mod_quota(int(wp.level)):
			for mid in (PCatalog.weapon(wid).get("mods", {}) as Dictionary):
				if bool(PCatalog.weapon(wid).mods[mid].get("impl", false)) and not (wp.mods as Array).has(String(mid)):
					c = { "kind": "weapon_mod", "id": wid, "mod": String(mid) }
					break
		if c.is_empty() and int(lo.level) < 5:
			c = { "kind": "weapon_level", "id": wid }
		if c.is_empty() and ws.size() < 2:
			c = { "kind": "weapon_new", "id": "spear" }
		if c.is_empty():
			for cid in PCatalog.commons():
				var cd: Dictionary = PCatalog.commons()[cid]
				var cl: int = int(g.commons.get(cid, 0))
				if bool(cd.impl) and cl < int(cd.max) and (cl > 0 or (g.commons as Dictionary).size() < 3):
					c = { "kind": "common", "id": String(cid) }
					break
		if c.is_empty() or blocked.has(JSON.stringify(c)):
			break
		if PGrowth.apply_choice(run, c):
			used += 1
		else:
			blocked[JSON.stringify(c)] = true
	run.hp = float(PRun.build(run).hp_max)

func make_run(seed_v: int, act: int, theme_id: String) -> Dictionary:
	var route := [PCatalog.act_default_theme(1), PCatalog.act_default_theme(2), PCatalog.act_default_theme(3)]
	route[act - 1] = theme_id
	var run := PRun.new_run(seed_v, "sword", "", { "route": route })
	run.day = int(DAY_OF_ACT[act])
	run.stage = act - 1
	grow(run, int(PICKS_BY_DAY.get(int(run.day), 12)))
	return run

func encounter(run: Dictionary, place_id: String, formation_id: String, seed_v: int, duel_type: String = "", no_squad: bool = false) -> CombatState:
	var sortie := { "regionId": place_id, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 },
		"encounters": 0, "seed": int(run.seed) * 131 + seed_v * 17 + int(run.day), "day": int(run.day),
		"slot": 0, "variant": null, "formationId": formation_id, "duelType": duel_type }
	var o := PFlow.encounter_opts(run, sortie)
	if no_squad: # 대조군: **같은 코드·같은 시드·같은 편성**에서 분대 편성만 끈다(옛 비례 섞기)
		(o.density as Dictionary).erase("squad")
	return CombatState.new(o)

# ---------- 한 전투 재기 ----------
func run_once(act: int, theme_id: String, place_id: String, formation_id: String, seed_v: int, duel_type: String = "", no_squad: bool = false) -> Dictionary:
	var run := make_run(seed_v, act, theme_id)
	var st := encounter(run, place_id, formation_id, seed_v, duel_type, no_squad)
	var bot := PBot.new(POLICY)
	var dt_s := STEP * float(SAMPLE_EVERY)
	var tail12 := 0.0
	var room_wait := 0.0
	var conc_types := {}      # 동시에 살아 있던 종류 수의 분포
	var max_conc := 0
	var max_alive := 0
	var stage_types := { "open": {}, "core": {}, "late": {}, "all": {} }
	var reinforce_in_duel := 0   # 결투 중 들어온 **일반 편성** 증원(0이어야 한다)
	var spawn_at_duel := -1
	var duel_seen := {}
	var n := 0
	var limit := int(MAX_SEC / STEP)
	while st.status == "running" and n < limit:
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max # 계측 전용: 전투 말미·결투까지 보기 위해 죽지 않게 한다
		st.player.dead = false
		n += 1
		if st.duel_stage != "" and st.duel_stage != "normal":
			duel_seen[st.duel_stage] = true
			if spawn_at_duel < 0:
				spawn_at_duel = int(st.spawn_count)
			elif int(st.spawn_count) > spawn_at_duel:
				reinforce_in_duel += int(st.spawn_count) - spawn_at_duel
				spawn_at_duel = int(st.spawn_count)
		if n % SAMPLE_EVERY != 0:
			continue
		var alive := 0
		var types := {}
		for e in st.enemies:
			if e.dead or bool(e.get("structure", false)):
				continue
			alive += 1
			types[String(e.type)] = true
		max_alive = maxi(max_alive, alive)
		if alive > 0:
			max_conc = maxi(max_conc, types.size())
			conc_types[types.size()] = float(conc_types.get(types.size(), 0.0)) + dt_s
		if alive >= 1 and alive <= 2 and not bool(st.spawned_all):
			tail12 += dt_s
		var queued: int = maxi(0, int(st.spawn_total) - int(st.spawn_count))
		var room: int = int(st.formation.get("alive_cap", 0)) - st.alive_units() - st.pending.size()
		if queued > 0 and room > 0:
			room_wait += dt_s
	for sq in st.squad_log: # 구간별로 어떤 종류가 나왔는가(등장 순서의 변화)
		var key := String(sq.get("stage", "all"))
		if not stage_types.has(key):
			stage_types[key] = {}
		for m in (sq.members as Array):
			(stage_types[key] as Dictionary)[String(m).split(":")[0]] = true
	var status := String(st.status)
	if status == "running":
		status = "timeout"
		st.delayed.clear()
	var kinds := {}
	for t in (st.formation.godot_counts as Dictionary):
		kinds[String(t)] = int(st.formation.godot_counts[t])
	return { "formation": formation_id, "act": act, "seed": seed_v, "status": status, "sec": snappedf(float(st.t), 0.1),
		"types": kinds, "n_types": kinds.size(), "max_conc_types": max_conc, "conc_hist": conc_types,
		"spawn_total": int(st.spawn_total), "spawned": int(st.spawn_count), "max_alive": max_alive,
		"squad_pushes": int(st.stats.squad_pushes), "squad_overlaps": int(st.stats.squad_overlaps),
		"tail12": snappedf(tail12, 0.1), "room_wait": snappedf(room_wait, 0.1), "thin_tail": snappedf(float(st.stats.thin_tail_sec), 0.1),
		"support_only": snappedf(float(st.stats.support_only_sec), 0.1), "no_target": snappedf(float(st.stats.no_target_sec), 0.1),
		"stage_types": stage_types, "squad_log": st.squad_log.slice(0, 6),
		"duel_type": String(st.duel_type), "duel_stage": String(st.duel_stage), "duel_stages_seen": duel_seen.keys(),
		"duel_reinforce": reinforce_in_duel, "duel_summons": int(st.stats.duel_summons), "duel_cleared": int(st.stats.duel_summons_cleared),
		"duel_sec": snappedf(float(st.stats.duel_sec), 0.1) }

func _init() -> void:
	sub = PSubset.new()
	var acts: Array = sub.pick("act", [1, 2, 3])
	var seeds: Array = sub.pick("seed", [1, 2])
	w(sub.describe("편성 계측(협공 3종 · 분대 · 등장 종류 수 · 특수 정예 결투)"))
	w("- 측정값이며 **사람이 승인한 균형값이 아니다.** 봇 정책 %s · 시드 %s · 최대 %.0f초 · 집중 경로(사냥 숲 → 얼어붙은 협곡 → 뒤틀린 성채)" % [POLICY, str(seeds), MAX_SEC])
	w("- 실제 출격 경로를 그대로 지난다(data/themes.json → PRun.formation_waves → PFlow.encounter_opts).")
	w("")

	# ---------- 1. 테마별 대표 협공 3개 ----------
	w("## 1. 테마별 대표 협공 3개(자료)")
	w("")
	w("| 테마 | ① | ② | ③ | 특수 정예 후보 |")
	w("|---|---|---|---|---|")
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		var cells := []
		for f in (t.formations.normal as Array):
			var parts := []
			for c in PRun.comp_effective(f):
				parts.append("%s %d%%" % [String(PCatalog.enemies()[String(c.type)].name), int(round(float(c.share) * 100.0))])
			var ce := PRun.common_elite_id(f)
			var ce_txt := ""
			if not (f.get("common_elite", {}) as Dictionary).is_empty():
				ce_txt = " · 일반정예 %s%s" % [String(f.common_elite.type), "" if ce != "" else "(미구현 → 일반 개체)"]
			cells.append("**%s**(%s)<br>%s%s" % [String(f.name), String(f.kind), ", ".join(parts), ce_txt])
		w("| %s | %s | %s |" % [String(t.name), " | ".join(cells), " · ".join(t.get("special_elites", []))])
	w("")

	# ---------- 2. 총 등장 수·경험치 예산 불변 ----------
	w("## 2. 총 등장 수·경험치 예산(개편 전과 같은가)")
	w("")
	w("| 편성 | 장소 | 총 등장 수 | 경험치 예산(단위) | 고정 목표 | 차이 |")
	w("|---|---|---:|---:|---:|---:|")
	var XPV: Dictionary = PCatalog.growth().XP_VALUE
	var budget_bad := 0
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		if not acts.has(int(t.act)):
			continue
		for kind in ["normal", "risk"]:
			for f in (t.formations[kind] as Array):
				for pi in 2:
					var pk := "p1" if pi == 0 else "p2"
					var pid := String((t.places as Array)[pi].id)
					var wv := PRun.template_waves(f, pk, int(DAY_OF_ACT[int(t.act)]), PRun.place_cost(pid))
					var n_all := 0
					var bud := 0.0
					for wave in wv:
						for g in wave:
							n_all += int(g.n)
							bud += float(XPV.get(String(g.type), 5.0)) * float(g.get("ref", float(g.n)))
					var target: float = float((f.get("xp_units", {}) as Dictionary).get(pk, 0.0)) + float(int(f.get("elites", 0))) * float(XPV.get("wolf_alpha", 30.0))
					var diff: float = bud - target
					if absf(diff) > 0.01:
						budget_bad += 1
					w("| %s | %s | %d | %.2f | %.2f | %+.2f |" % [String(f.id), pk, n_all, bud, target, diff])
	w("")
	w("- 목표와 어긋난 편성: **%d개**(0이어야 한다). 목표 = data/themes.json 의 xp_units(개편 전 값) + 정예 마리 수 × 정예 단위값." % budget_bad)
	w("")

	# ---------- 3. 대표 전투 실측 ----------
	w("## 3. 대표 전투 실측(집중 경로)")
	w("")
	w("| 편성 | 막 | 시드 | 결과 | 시간 | 종류 수 | 동시 종류 최대 | 총 등장/실제 | 동시 최대 | 분대 투입(겹침) | 1~2마리 구간 | 자리 비고 대기 | 지원만 남은 시간 |")
	w("|---|--:|--:|---|--:|--:|--:|---|--:|---|--:|--:|--:|")
	var rows := []
	for fc in FOCUS:
		if not acts.has(int(fc.act)):
			continue
		var t: Dictionary = PCatalog.theme(String(fc.theme))
		var fids := []
		for f in (t.formations.normal as Array):
			fids.append(String(f.id))
		fids = sub.pick("formation", fids)
		for fid in fids:
			for s in seeds:
				var r := run_once(int(fc.act), String(fc.theme), String(fc.place), String(fid), int(s))
				rows.append(r)
				w("| %s | %d | %d | %s | %.1f초 | %d | %d | %d/%d | %d | %d(%d) | %.1f초 | %.1f초 | %.1f초 |" % [
					String(r.formation), int(r.act), int(r.seed), String(r.status), float(r.sec), int(r.n_types), int(r.max_conc_types),
					int(r.spawn_total), int(r.spawned), int(r.max_alive), int(r.squad_pushes), int(r.squad_overlaps),
					float(r.tail12), float(r.room_wait), float(r.support_only)])
	w("")
	w("### 구간별 등장 종류(첫 시드)")
	w("")
	for r in rows:
		if int(r.seed) != int(seeds[0]):
			continue
		var parts := []
		for k in ["open", "core", "late", "all"]:
			var d: Dictionary = (r.stage_types as Dictionary).get(k, {})
			if d.is_empty():
				continue
			parts.append("%s: %s" % [k, ", ".join(d.keys())])
		w("- **%s** — %s" % [String(r.formation), " · ".join(parts)])
	w("")
	w("### 실제 분대 투입 순서(첫 시드, 앞 6개)")
	w("")
	for r in rows:
		if int(r.seed) != int(seeds[0]):
			continue
		w("- **%s**" % String(r.formation))
		for sq in (r.squad_log as Array):
			w("  - %.1f초 · %s · %s · 이전 생존 %d%s" % [float(sq.t), String(sq.stage), ", ".join(sq.members as Array), int(sq.alive), " · **겹침**" if bool(sq.overlap) else ""])
	w("")

	# ---------- 3b. 막별 조우 기회(실제 카드 생성기로 센다) ----------
	w("## 3b. 막별 정예 조우 기회(실제 카드 생성기 PSortie.cards_for)")
	w("")
	w("카드 수이지 강제 조우 수가 아니다 — 플레이어가 그 카드를 고르면 만난다.")
	w("")
	w("| 막 | 테마 | 카드 | 특수 정예(편성 안) | 특수 정예(결투) | 결투 종류 | 일반 정예 |")
	w("|--:|---|--:|--:|--:|---|--:|")
	for tid in PCatalog.themes():
		var t8: Dictionary = PCatalog.themes()[tid]
		if not acts.has(int(t8.act)):
			continue
		var n_card := 0
		var n_in := 0
		var n_duel := 0
		var n_ce := 0
		var kinds8 := {}
		for s in seeds:
			var run8 := make_run(int(s), int(t8.act), tid)
			for d in (PRun.act_of(run8).get("days", []) as Array):
				run8.day = int(d)
				run8.cards = null
				for c in PSortie.cards_for(run8):
					n_card += 1
					if bool(PSortie.elite_notice(run8, c).get("present", false)):
						n_in += 1
					var dt8 := String(c.get("duelType", ""))
					if dt8 != "":
						n_duel += 1
						kinds8[String(PCatalog.enemies()[dt8].name)] = true
					var tpl8 := PRun.theme_template(String(c.regionId), String(c.get("formationId", "")))
					if not tpl8.is_empty() and not (tpl8.get("common_elite", {}) as Dictionary).is_empty():
						n_ce += 1
		w("| %d | %s | %d | %d | %d | %s | %d |" % [int(t8.act), String(t8.name), n_card, n_in, n_duel, " · ".join(kinds8.keys()), n_ce])
	w("")
	w("- '일반 정예' 열은 그 편성에 일반 정예 자리가 있는 카드 수다. 지금은 `<종류>_elite` 가 카탈로그에 없어 **실제로는 일반 개체로 나온다**(§1 표의 '미구현' 표시).")
	w("")

	# ---------- 4. 특수 정예 결투 ----------
	w("## 4. 특수 정예 결투(전환·일반 증원 0·고유 소환)")
	w("")
	w("| 테마 | 편성 | 결투 상대 | 결과 | 결투 시간 | 거친 단계 | 결투 중 일반 증원 | 고유 소환 | 처치 후 정리 |")
	w("|---|---|---|---|--:|---|--:|--:|--:|")
	for fc in FOCUS:
		if not acts.has(int(fc.act)):
			continue
		var t2: Dictionary = PCatalog.theme(String(fc.theme))
		var fid0 := String((t2.formations.normal as Array)[0].id)
		for dt in PRun.duel_types_for(String(fc.theme)):
			var r := run_once(int(fc.act), String(fc.theme), String(fc.place), fid0, int(seeds[0]), String(dt))
			w("| %s | %s | %s | %s | %.1f초 | %s | %d | %d | %d |" % [String(t2.name), fid0, String(PCatalog.enemies()[String(dt)].name),
				String(r.status), float(r.duel_sec), ", ".join(r.duel_stages_seen as Array), int(r.duel_reinforce), int(r.duel_summons), int(r.duel_cleared)])
	w("")
	w("- '결투 중 일반 증원'은 **0이어야 한다**(일반 편성의 추가 증원 금지).")
	w("- 고유 소환은 특수 정예에게 귀속되며 경험치·금화를 주지 않는다. 처치 후 남은 소환물은 추가 보상 없이 정리된다.")
	w("")

	# ---------- 5. 분대 편성 전후(같은 코드·같은 시드·같은 편성) ----------
	w("## 5. 분대 편성 전후 비교(같은 코드·같은 시드·같은 편성, 분대만 끄고 켠다)")
	w("")
	w("이전 커밋(종류별 상한을 동시 상한 비례로)의 개선과 **분대 편성의 개선을 가르기 위한** 대조군이다.")
	w("")
	w("| 편성 | 막 | 1~2마리 구간(전→후) | 지원만 남은 시간(전→후) | 자리 비고 대기(전→후) | 동시 최대(전→후) | 전투 시간(전→후) |")
	w("|---|--:|---|---|---|---|---|")
	for fc in FOCUS:
		if not acts.has(int(fc.act)):
			continue
		var t7: Dictionary = PCatalog.theme(String(fc.theme))
		for f in (t7.formations.normal as Array):
			var off := run_once(int(fc.act), String(fc.theme), String(fc.place), String(f.id), int(seeds[0]), "", true)
			var on := run_once(int(fc.act), String(fc.theme), String(fc.place), String(f.id), int(seeds[0]), "", false)
			w("| %s | %d | %.1f초 → %.1f초 | %.1f초 → %.1f초 | %.1f초 → %.1f초 | %d → %d | %.1f초 → %.1f초 |" % [
				String(f.id), int(fc.act), float(off.thin_tail), float(on.thin_tail), float(off.support_only), float(on.support_only),
				float(off.room_wait), float(on.room_wait), int(off.max_alive), int(on.max_alive), float(off.sec), float(on.sec)])
	w("")

	var path := sub.out_path("res://docs/sim/FORMATION_PROBE.md")
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	if f2 != null:
		f2.store_string("\n".join(lines) + "\n")
		f2.close()
		print("결과: " + path)
	print("%d/%d PASS" % [1, 1]) # 계측 도구: 판정하지 않는다(실행이 끝났음을 실행기에 알린다)
	quit(0)
