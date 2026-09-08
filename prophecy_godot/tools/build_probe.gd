extends SceneTree
## 대표 빌드 10개의 완성 전후 비교(화면 없음):
##   godot --headless --path prophecy_godot -s tools/build_probe.gd
## 결과: docs/sim/BUILD_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 있는가
## ---------
## **전수 시뮬레이션이 아니다.** 주무기 5종마다 서로 다른 완성형 빌드 2개, 모두 10개만 돌린다.
## 각 빌드는 실제 성장 규칙(PGrowth.apply_choice)으로 만들어 슬롯 상한과 개조 자격을 지킨다 —
## 손으로 만든 사전을 밀어 넣으면 "플레이로 얻을 수 없는 빌드"를 재게 된다.
##
## 무엇을 같게 두는가
## ------------------
## '전'과 '후'는 **레벨 투자가 같다**(주무기 Lv5 · 보조 각 Lv3). 다른 것은 개조뿐이다 —
## 주무기 개조 2개와 보조 개조 2개를 뺀 상태가 '전', 다 채운 상태가 '후'다.
## 그래서 표의 차이는 레벨 차이가 아니라 **완성(개조)의 차이**다.
##
## 세 장면을 나눠 잰다
## -------------------
##   단일 대상 — 죽지 않는 표적 1기를 20초. 접근·이탈까지 포함한 실제 화력
##   밀집 무리 — 늑대 6 + 궁수 2. 광역과 연쇄가 사는 자리
##   이동 전투 — 궁수 4 + 주술사 2 + 서리술사 1(거리를 두는 편성). 걸으면서 싸워야 한다
##
## 피해만 보지 않는다
## ------------------
## 발동 횟수 · 한 프레임에 여럿이 죽은 횟수(연쇄 체감) · 방어·제어 지표를 함께 남긴다.
## **처치의 원인을 세는 훅이 없어** '연쇄 처치 수'를 정확히 셀 수 없다 —
## 대신 (가) 한 프레임에 2마리 이상 죽은 횟수와 (나) 직접 타격이 아닌 경로의 피해 비율로 대신했다.
## 이 두 값은 근사이며, 정확한 값은 `kill_enemy`에 원인을 남기는 훅이 필요하다(보고서에 적어 둔다).
##
## 부분 실행 축: build · scene · state · seed

const STEP := 1.0 / 120.0
const SEEDS := [1, 2]
const STATES := ["before", "after"]

## 대표 빌드 10개. 주무기 개조 2개(자격 Lv2/Lv4) · 보조 2종 각 Lv3 + 개조 1개(자격 Lv2).
## **같은 폭발 효과로 열 개를 다 만들지 않는다** — 바뀌는 것이 공격 형태·연쇄·이동·표적 선택 중
## 무엇인지를 build마다 다르게 잡았다.
const BUILDS := [
	{ "id": "sword_garden", "name": "검·역병 정원", "main": "sword", "mods": ["cross", "scar"],
		"supports": [["plague", "burst"], ["ember", "reignite"]],
		"axis": "연쇄", "why": "죽음이 다음 죽음을 부른다(전염 → 파열 → 불길 연장)" },
	{ "id": "sword_echo", "name": "검·잔영 검진", "main": "sword", "mods": ["cross", "crescent"],
		"supports": [["echo", "residual"], ["orb", "conduct"]],
		"axis": "공격 형태", "why": "한 번 벨 때 여러 자리에서 동시에 벤다 + 감전 축적" },
	{ "id": "spear_line", "name": "창·일렬 정렬", "main": "spear", "mods": ["returning", "brand"],
		"supports": [["wind", "focused"], ["mine", "chain"]],
		"axis": "이동", "why": "밀어내 일렬로 세우고 지뢰밭으로 몬다" },
	{ "id": "spear_mark", "name": "창·표식 저격", "main": "spear", "mods": ["brand", "split"],
		"supports": [["crow", "hunt"], ["frost", "ground"]],
		"axis": "표적 선택", "why": "주무기가 찍은 하나를 까마귀가 계속 문다 + 냉기로 묶는다" },
	{ "id": "daggers_shock", "name": "쌍검·감전 연타", "main": "daggers", "mods": ["bleed", "flank"],
		"supports": [["orb", "conduct"], ["echo", "chase"]],
		"axis": "연쇄", "why": "3연타마다 감전 후속, 쌓이면 방전" },
	{ "id": "daggers_thorn", "name": "쌍검·가시 근접", "main": "daggers", "mods": ["bleed", "pursuit"],
		"supports": [["thorns", "focused"], ["bell", "guard"]],
		"axis": "방어", "why": "붙어 있는 시간을 버티게 한다" },
	{ "id": "hammer_anvil", "name": "망치·인형 모루", "main": "hammer", "mods": ["pull", "aftershock"],
		"supports": [["doll", "tough"], ["frost", "ground"]],
		"axis": "표적 이동", "why": "인형이 모으고 망치가 그 자리를 두 번 찍는다" },
	{ "id": "hammer_line", "name": "망치·충격 전선", "main": "hammer", "mods": ["shockwave", "aftershock"],
		"supports": [["wind", "broad"], ["blades", "dual"]],
		"axis": "이동", "why": "밀어내고 앞으로 밀고 나가는 전선" },
	{ "id": "bow_hunt", "name": "궁·표적 사냥", "main": "bow", "mods": ["spread", "ricochet"],
		"supports": [["crow", "switch"], ["wind", "lingering"]],
		"axis": "표적 선택", "why": "처치할 때마다 다음 표적으로 갈아탄다 + 거리를 벌린다" },
	{ "id": "bow_fort", "name": "궁·지뢰 요새", "main": "bow", "mods": ["pierce", "spread"],
		"supports": [["mine", "lure"], ["bell", "layered"]],
		"axis": "이동", "why": "지뢰밭 뒤에서 쏘고 방울로 화살을 막는다" },
]

const SCENES := ["single", "pack", "move"]
const SCENE_NAME := { "single": "단일 대상", "pack": "밀집 무리", "move": "이동 전투" }
const SCENE_SEC := { "single": 20.0, "pack": 60.0, "move": 60.0 }

## 방어·제어 지표(표준 이름). 피해로 드러나지 않는 일을 여기서 읽는다
const GUARD_KEYS := ["blocked_dmg", "reduced_dmg", "reflects", "taunted", "soaked", "soaked_dmg", "slows", "push_dist"]
## 발동 지표
const FIRE_KEYS := ["fires", "hits", "copies", "spreads", "bursts", "marks", "shock_procs", "discharges", "shocks"]

var sub := PSubset.new()
var rows := []

func build_of(id: String) -> Dictionary:
	for b in BUILDS:
		if String(b.id) == id:
			return b
	return {}

## 실제 성장 규칙으로 키운다. state="before"면 개조를 하나도 고르지 않는다(레벨 투자는 같다)
func make_run(bd: Dictionary, seed_v: int, state: String) -> Dictionary:
	var run: Dictionary = PRun.new_run(seed_v, String(bd.main))
	for s in bd.supports:
		PGrowth.apply_choice(run, { "kind": "weapon_new", "id": String(s[0]) })
	for i in 4:
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": String(bd.main) })   # Lv5
	for s in bd.supports:
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": String(s[0]) })      # Lv2 — 개조 자격
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": String(s[0]) })      # Lv3
	if state == "after":
		for m in bd.mods:
			PGrowth.apply_choice(run, { "kind": "weapon_mod", "id": String(bd.main), "mod": String(m) })
		for s in bd.supports:
			PGrowth.apply_choice(run, { "kind": "weapon_mod", "id": String(s[0]), "mod": String(s[1]) })
	return run

## 빌드가 실제로 규칙 안에서 만들어졌는지(상한을 넘기지 않았는지) 확인한다
func loadout_of(run: Dictionary) -> Array:
	var out := []
	var g: Dictionary = run.growth
	for w in g.weapons:
		var names := []
		for m in w.mods:
			names.append(String(PCatalog.weapon(String(w.id)).mods[String(m)].name))
		out.append("%s Lv%d%s" % [String(PCatalog.weapon(String(w.id)).name), int(w.level),
			("+" + "+".join(names)) if names.size() > 0 else ""])
	return out

func waves_for(scene: String) -> Array:
	match scene:
		"pack":
			return [[{ "type": "wolf", "n": 6 }, { "type": "archer", "n": 2 }]]
		"move":
			return [[{ "type": "archer", "n": 4 }, { "type": "shaman", "n": 2 }, { "type": "frostcaller", "n": 1 }]]
	return []

func run_one(bd: Dictionary, scene: String, state: String, seed_v: int) -> Dictionary:
	var run: Dictionary = make_run(bd, seed_v, state)
	var b: Dictionary = PRun.build(run)
	var opts := { "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": waves_for(scene), "objective": "clear", "region_id": "den" }
	var st := CombatState.new(opts)
	var target := {}
	if scene == "single":
		# 죽지 않는 표적 하나. 접근·이탈 손실까지 포함한 실제 화력을 본다
		st.spawn_hold = true
		target = st.spawn_enemy("wolf", st.player.x + 260.0, st.player.y)
		target.hp = 200000.0
		target.hp_max = 200000.0
	var bot := PSkillBot.new("skilled" if scene != "pack" else "novice", seed_v)
	var steps := int(SCENE_SEC[scene] / STEP)
	var i := 0
	var kills := 0
	var multi := 0
	var max_frame := 0
	while i < steps and st.status == "running":
		st.step(bot.step_input(st), STEP)
		var k := int(st.stats.kills)
		var d := k - kills
		if d >= 2:
			multi += 1
			max_frame = maxi(max_frame, d)
		kills = k
		i += 1
	var dealt := 0.0
	for k2 in (st.metrics.dmg as Dictionary):
		dealt += float(st.metrics.dmg[k2])
	# 직접 타격이 아닌 경로의 피해 비율(연쇄·개조·보조가 실제로 얼마나 일했는가의 근사)
	var base_dmg := float(st.metrics.cause_dmg.get("base", 0.0))
	var indirect := 0.0
	if dealt > 0.0:
		indirect = (dealt - base_dmg) / dealt
	var sup := {}
	for s in bd.supports:
		sup[String(s[0])] = (st.metrics.support.get(String(s[0]), {}) as Dictionary).duplicate()
	return { "build": String(bd.id), "scene": scene, "state": state, "seed": seed_v,
		"status": String(st.status), "sec": snappedf(st.t, 0.01), "kills": int(st.stats.kills),
		"dealt": snappedf(dealt, 0.1), "dps": snappedf(dealt / maxf(0.01, st.t), 0.1),
		"taken": snappedf(float(st.stats.damage_taken), 0.1), "hp_left": snappedf(float(st.player.hp), 0.1),
		"indirect": snappedf(indirect * 100.0, 0.1), "multi_kill_frames": multi, "max_kills_in_frame": max_frame,
		"support": sup, "loadout": loadout_of(run) }

func pick_row(bid: String, scene: String, state: String) -> Dictionary:
	var acc := {}
	var n := 0
	for r in rows:
		if String(r.build) != bid or String(r.scene) != scene or String(r.state) != state:
			continue
		n += 1
		for k in ["sec", "kills", "dealt", "dps", "taken", "indirect", "multi_kill_frames"]:
			acc[k] = float(acc.get(k, 0.0)) + float(r[k])
		acc["won"] = float(acc.get("won", 0.0)) + (1.0 if String(r.status) == "won" else 0.0)
		acc["support"] = r.support
		acc["loadout"] = r.loadout
	if n == 0:
		return {}
	for k in ["sec", "kills", "dealt", "dps", "taken", "indirect", "multi_kill_frames"]:
		acc[k] = snappedf(float(acc[k]) / float(n), 0.1)
	acc["n"] = n
	return acc

## 그 빌드의 두 보조에서 실제로 0이 아닌 지표만 짧게 적는다
func meters_text(sup: Dictionary, keys: Array) -> String:
	var parts := []
	for sid in sup:
		var d: Dictionary = sup[sid]
		for k in keys:
			var v := float(d.get(String(k), 0.0))
			if v > 0.0:
				parts.append("%s %s" % [String(k), str(snappedf(v, 0.1))])
	return " · ".join(parts) if parts.size() > 0 else "-"

func _init() -> void:
	var ids := []
	for b in BUILDS:
		ids.append(String(b.id))
	for bid in sub.pick("build", ids):
		var bd: Dictionary = build_of(String(bid))
		for scene in sub.pick("scene", SCENES):
			for state in sub.pick("state", STATES):
				for sd in sub.pick("seed", SEEDS):
					rows.append(run_one(bd, String(scene), String(state), int(sd)))
			printerr("done ", bid, " ", scene)
	print("BUILD_PROBE_JSON " + JSON.stringify({ "rows": rows }))

	var md := "# 대표 빌드 10개 — 완성 전후 비교\n\n"
	md += "생성: `tools/build_probe.gd` (%s, Godot %s).\n" % [OS.get_name(), Engine.get_version_info().string]
	md += "**전수 시뮬레이션이 아니다.** 주무기 5종마다 서로 다른 완성형 빌드 2개, 모두 10개만 돌린다.\n"
	md += "'전'과 '후'는 **레벨 투자가 같고**(주무기 Lv5 · 보조 각 Lv3) 개조만 다르다.\n"
	md += "모든 수치는 시험값이며 사람이 승인한 밸런스가 아니다.\n\n"
	md += sub.describe("대표 빌드 측정") + "\n"

	md += "## 빌드 목록(실제 성장 규칙으로 만든 것)\n\n"
	md += "| 빌드 | 바뀌는 축 | 노리는 것 | 완성 편성 |\n|---|---|---|---|\n"
	for b in BUILDS:
		var lo := ""
		var r := pick_row(String(b.id), "pack", "after")
		if r.is_empty():
			r = pick_row(String(b.id), "single", "after")
		if not r.is_empty():
			lo = " / ".join(r.loadout)
		md += "| %s | %s | %s | %s |\n" % [String(b.name), String(b.axis), String(b.why), lo]
	md += "\n"

	for scene in SCENES:
		md += "## %s\n\n" % String(SCENE_NAME[scene])
		if scene == "single":
			md += "죽지 않는 표적 1기(시작 거리 260)를 20초. 접근·이탈 손실까지 포함한 실제 화력이다.\n"
			md += "**승패와 처치가 없다**(표적이 죽지 않는다) — 여기서는 초당 피해만 본다.\n\n"
		elif scene == "pack":
			md += "늑대 6 + 궁수 2, 초보 봇, 상한 60초. **초보 봇이라야 방어·제어 지표를 잴 수 있다**(실력 봇은 잘 피해서 0이 된다).\n\n"
		else:
			md += "궁수 4 + 주술사 2 + 서리술사 1(거리를 두는 편성), 실력 봇, 상한 60초. 걸어 나가지 않으면 못 잡는다.\n\n"
		md += "| 빌드 | 상태 | 결과 | 걸린 시간 | 처치 | 준 피해 | 초당 피해 | 받은 피해 | 간접 피해 비율 | 여럿이 함께 죽은 프레임 | 발동 지표 | 방어·제어 지표 |\n"
		md += "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|\n"
		for b in BUILDS:
			for state in STATES:
				var r := pick_row(String(b.id), String(scene), String(state))
				if r.is_empty():
					continue
				var res: String = "-" if String(scene) == "single" else "%d/%d 승" % [int(r.won), int(r.n)]
				var kil: String = "-" if String(scene) == "single" else str(float(r.kills))
				md += "| %s | %s | %s | %.1f | %s | %.0f | %.1f | %.1f | %.1f%% | %d | %s | %s |\n" % [
					String(b.name), ("전(개조 없음)" if state == "before" else "후(완성)"),
					res, float(r.sec), kil, float(r.dealt), float(r.dps),
					float(r.taken), float(r.indirect), int(r.multi_kill_frames),
					meters_text(r.support, FIRE_KEYS), meters_text(r.support, GUARD_KEYS)]
		md += "\n"

	md += "## 읽는 법\n\n"
	md += "- **간접 피해 비율**은 `base`(주무기 기본 발사) 밖의 모든 경로가 낸 피해 비율이다.\n"
	md += "  보조·개조·연쇄가 실제로 얼마나 일했는지의 근사이고, 낮으면 \"개조를 찍어도 주무기만 때리고 있다\"는 뜻이다.\n"
	md += "- **여럿이 함께 죽은 프레임**은 한 프레임에 2마리 이상 죽은 횟수다. 연쇄 체감의 근사다.\n"
	md += "  **처치의 원인을 세는 훅이 없어 '연쇄 처치 수'를 정확히 셀 수 없다** — `kill_enemy`에 원인을 남기는 훅이 필요하다.\n"
	md += "- **밀집 무리·이동 전투에서 '준 피해'는 편성의 총 체력과 같아진다**(다 잡으면 끝난다).\n"
	md += "  그 두 장면에서 갈리는 값은 **걸린 시간 · 받은 피해 · 간접 피해 비율**이지 총 피해가 아니다.\n"
	md += "- 지표가 0인 것을 곧바로 \"약하다\"로 읽지 않는다. 그 장면에서 발동 조건이 오지 않았을 수 있다.\n"
	md += "- 회전 칼날·번개 구체·서리 수정·불씨 정령·룬 지뢰는 `PSupport.METER_MAP`에 항목이 없어\n"
	md += "  **표준 지표가 대부분 비어 있다**(번개 구체의 감전만 직접 센다). 0을 약함으로 읽지 않는다.\n"

	var f := FileAccess.open(sub.out_path("res://docs/sim/BUILD_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()
