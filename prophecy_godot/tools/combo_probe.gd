extends SceneTree
## 대표 조합 측정(화면 없음):
##   godot --headless --path prophecy_godot -s tools/combo_probe.gd
## 결과: docs/sim/COMBO_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 있는가
## ---------
## 주무기 5종 × 보조 12종 × 개조 36개의 **모든 조합을 처음부터 대규모로 돌리지 않는다**(사용자 지시 8절).
## 대신 사용자가 지정한 **대표 조합 7개**만 돌려서, 각 조합이 노리는 역할이 실제로 일어나는지 본다.
##
## 피해만 보지 않는다
## ------------------
## 분신·감전은 발동과 피해, 방울은 차단, 갑각은 경감·반격, 인형은 대신 받은 공격, 서리는 둔화,
## 바람은 거리 확보를 본다. 지표는 PSupport.meter가 쌓은 st.metrics.support에서 읽는다.
##
## 봇이 못 쓰는 것과 콘텐츠가 약한 것은 다르다
## -------------------------------------------
## 지표가 0이면 "약하다"가 아니라 **봇이 그 효과를 쓸 줄 모르는 것일 수 있다.** 보고서는 두 경우를 나눠 적는다:
##   - 발동 자체가 0 → 봇 행동 문제일 가능성(어느 조건에서 발동하는지 함께 적는다)
##   - 발동은 되는데 결과가 작다 → 콘텐츠 수치 문제일 가능성
##
## 실력 봇만으로는 방어를 못 잰다
## ---------------------------
## 실력 봇은 잘 피해서 받는 피해가 거의 0이 된다. 그러면 방울 차단·갑각 경감·인형 대신 맞기가
## 전부 0으로 나오는데, 이것은 **콘텐츠가 약해서가 아니라 잴 기회가 없어서**다.
## 그래서 초보(novice) 봇으로도 같은 조합을 돌려 방어 지표를 따로 본다. 두 줄을 함께 보고한다.
##
## 부분 실행 축: combo(조합 이름) · seed · bot(봇 실력)

const STEP := 1.0 / 120.0
const MAX_SEC := 90.0
const SEEDS := [1, 2, 3]
const BOTS := ["skilled", "novice"]

## 사용자가 지정한 대표 조합. 각 조합이 무엇을 보려는 것인지 함께 적는다
const COMBOS := [
	{ "id": "daggers_orb_echo", "main": "daggers", "supports": ["orb", "echo"],
		"why": "감전·연타 연계와 재귀 발동 검사", "watch": ["shock_procs", "copies", "copy_dmg"] },
	{ "id": "hammer_frost_doll", "main": "hammer", "supports": ["frost", "doll"],
		"why": "적 모으기·공격 기회", "watch": ["slows", "taunted", "soaked"] },
	{ "id": "spear_wind_mine", "main": "spear", "supports": ["wind", "mine"],
		"why": "거리 유지·추격 경로", "watch": ["push_dist", "fires"] },
	{ "id": "sword_plague_crow", "main": "sword", "supports": ["plague", "crow"],
		"why": "우선 처치와 전염", "watch": ["spreads", "bursts", "marks"] },
	{ "id": "bow_blades_bell", "main": "bow", "supports": ["blades", "bell"],
		"why": "근접·투사체 대응을 보완해도 남는 위험", "watch": ["blocked", "blocked_dmg"] },
	{ "id": "daggers_thorns_bell", "main": "daggers", "supports": ["thorns", "bell"],
		"why": "방어 중복과 반격 상한", "watch": ["reduced_dmg", "reflects", "blocked"] },
	{ "id": "sword_ember_mine", "main": "sword", "supports": ["ember", "mine"],
		"why": "실제 이동·전투 위치의 차이", "watch": ["fires", "dmg"] },
]

var sub := PSubset.new()
var rows := []

## 그 보조가 아직 구현되지 않았는가(impl:false면 성장 후보로도 안 나온다)
func unimpl(ids: Array) -> Array:
	var out := []
	var W := PCatalog.weapons()
	for id in ids:
		if not W.has(String(id)) or not bool(W[String(id)].get("impl", false)):
			out.append(String(id))
	return out

## 주무기와 보조를 실제 성장 규칙으로 키운다. 같은 선택 예산(성장 선택 횟수)을 모든 조합에 똑같이 준다.
## 배분: 주무기 레벨 2 → 보조 둘 레벨 2 → 보조 개조 → 주무기 레벨 4 → 주무기 개조 2개.
func build_run(combo: Dictionary, seed_v: int) -> Dictionary:
	var run := PRun.new_run(seed_v, String(combo.main))
	var g: Dictionary = run.growth
	for sid in combo.supports:
		PGrowth.apply_choice(run, { "kind": "weapon_new", "id": String(sid) })
	var plan := [
		{ "kind": "weapon_level", "id": String(combo.main) },   # Lv2 — 첫 개조 자격
		{ "kind": "weapon_level", "id": String(combo.main) },   # Lv3
		{ "kind": "weapon_level", "id": String(combo.main) },   # Lv4 — 두 번째 개조 자격
		{ "kind": "weapon_level", "id": String(combo.main) },   # Lv5
	]
	for sid in combo.supports:
		plan.append({ "kind": "weapon_level", "id": String(sid) }) # 보조 Lv2 — 개조 자격
		plan.append({ "kind": "weapon_level", "id": String(sid) }) # 보조 Lv3
	for c in plan:
		PGrowth.apply_choice(run, c)
	# 개조는 자격이 열린 뒤에만 고를 수 있다. 카탈로그에서 구현된 것 중 첫 번째를 고른다(시험값 선택)
	for w in g.weapons:
		var wid := String(w.id)
		var quota := PGrowth.mod_quota_of(g, w)
		for mid in PCatalog.weapon(wid).get("mods", {}):
			if (w.mods as Array).size() >= quota:
				break
			if bool(PCatalog.weapon(wid).mods[mid].get("impl", false)):
				PGrowth.apply_choice(run, { "kind": "weapon_mod", "id": wid, "mod": String(mid) })
	return run

## 한 조합을 실제 전투에 넣고 역할 지표를 읽는다. 9일차 수준 편성(늑대·궁수·방패병 섞음)
func run_one(combo: Dictionary, seed_v: int, bot_id: String) -> Dictionary:
	var run := build_run(combo, seed_v)
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [[{ "type": "wolf", "n": 4 }, { "type": "archer", "n": 2 }, { "type": "shieldbearer", "n": 1 }]],
		"objective": "clear", "region_id": "den", "run": run })
	var bot := PSkillBot.new(bot_id, seed_v)
	var steps := int(MAX_SEC / STEP)
	var i := 0
	while i < steps and st.status == "running":
		st.step(bot.step_input(st), STEP)
		i += 1
	var dealt := 0.0
	for k in (st.metrics.dmg as Dictionary):
		dealt += float(st.metrics.dmg[k])
	var sup := {}
	for sid in combo.supports:
		sup[String(sid)] = (st.metrics.support.get(String(sid), {}) as Dictionary).duplicate()
	var g: Dictionary = run.growth
	var loadout := []
	for w in g.weapons:
		var mn := []
		for m in w.mods:
			mn.append(String(PCatalog.weapon(String(w.id)).mods[String(m)].name))
		loadout.append("%s Lv%d%s" % [String(PCatalog.weapon(String(w.id)).name), int(w.level),
			("+" + "+".join(mn)) if mn.size() > 0 else ""])
	return { "combo": String(combo.id), "seed": seed_v, "bot": bot_id, "status": String(st.status),
		"sec": snapped(st.t, 0.01), "kills": int(st.stats.kills), "dealt": snapped(dealt, 0.1),
		"taken": snapped(float(st.stats.damage_taken), 0.1), "hp_left": snapped(float(st.player.hp), 0.1),
		"support": sup, "loadout": loadout }

func fmt_metrics(d: Dictionary, watch: Array) -> String:
	var parts := []
	for k in watch:
		var v := 0.0
		for sid in d:
			v += float((d[sid] as Dictionary).get(String(k), 0.0))
		parts.append("%s %s" % [String(k), str(snapped(v, 0.1))])
	return " · ".join(parts) if parts.size() > 0 else "-"

func _init() -> void:
	var names := []
	for c in COMBOS:
		names.append(String(c.id))
	var skipped := []
	for cid in sub.pick("combo", names):
		var combo := {}
		for c in COMBOS:
			if String(c.id) == String(cid):
				combo = c
		var missing := unimpl(combo.supports)
		if not missing.is_empty():
			skipped.append([String(cid), missing])
			printerr("skip ", cid, " (미구현: ", missing, ")")
			continue
		for bt in sub.pick("bot", BOTS):
			for sd in sub.pick("seed", SEEDS):
				rows.append(run_one(combo, int(sd), String(bt)))
				printerr("done ", cid, " bot=", bt, " seed=", sd)
	print("COMBO_PROBE_JSON " + JSON.stringify({ "rows": rows, "skipped": skipped }))

	var md := "# 대표 조합 측정\n\n"
	md += "생성: `tools/combo_probe.gd` (%s, Godot %s). 9일차 수준 편성(늑대 4·궁수 2·방패병 1). 봇 실력 두 가지(skilled·novice). 상한 %.0f초.\n" % [OS.get_name(), Engine.get_version_info().string, MAX_SEC]
	md += "**모든 조합의 대규모 시뮬레이션이 아니다.** 사용자가 지정한 대표 조합 %d개만 돌린다.\n" % COMBOS.size()
	md += "모든 수치는 시험값이며 사람이 승인한 밸런스가 아니다.\n\n"
	md += sub.describe("대표 조합 측정") + "\n\n"
	if not skipped.is_empty():
		md += "## 아직 못 돌린 조합\n\n"
		md += "| 조합 | 미구현 보조 |\n|---|---|\n"
		for s in skipped:
			md += "| %s | %s |\n" % [String(s[0]), ", ".join(s[1])]
		md += "\n보조가 구현되면 같은 명령으로 다시 돌린다. **미구현을 결과 없음으로 적지 않는다.**\n\n"
	if rows.is_empty():
		md += "## 결과\n\n돌린 조합이 없다.\n"
	else:
		md += "## 결과\n\n"
		md += "| 조합 | 봇 | 시드 | 편성 | 결과 | 걸린 시간 | 처치 | 준 피해 | 받은 피해 | 남은 체력 | 역할 지표 |\n"
		md += "|---|---|---:|---|---|---:|---:|---:|---:|---:|---|\n"
		for r in rows:
			var combo := {}
			for c in COMBOS:
				if String(c.id) == String(r.combo):
					combo = c
			md += "| %s | %s | %d | %s | %s | %.1f | %d | %.0f | %.0f | %.0f | %s |\n" % [
				String(r.combo), String(r.bot), int(r.seed), " / ".join(r.loadout), String(r.status), float(r.sec),
				int(r.kills), float(r.dealt), float(r.taken), float(r.hp_left),
				fmt_metrics(r.support, combo.get("watch", []))]
		md += "\n## 조합이 보려는 것\n\n| 조합 | 무엇을 보려는가 | 읽는 지표 |\n|---|---|---|\n"
		for c in COMBOS:
			md += "| %s | %s | %s |\n" % [String(c.id), String(c.why), ", ".join(c.watch)]
		md += "\n**봇 실력을 나눠 본다.** 실력 봇(skilled)은 잘 피해서 받는 피해가 0에 가까워 방어 지표를 잴 수 없다.\n"
		md += "초보 봇(novice) 줄이 방울 차단·갑각 경감·인형 대신 맞기를 재는 줄이다. 두 줄을 같이 봐야 한다.\n\n"
		md += "**지표가 0일 때 두 경우를 구분한다.** 발동 자체가 0이면 봇이 그 효과를 쓸 줄 모르는 것일 수 있고,\n"
		md += "발동은 되는데 결과가 작으면 콘텐츠 수치 문제일 수 있다. 0을 곧바로 '약하다'로 적지 않는다.\n"
	var f := FileAccess.open(sub.out_path("res://docs/sim/COMBO_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()
