extends SceneTree
## 보조무기 12종이 **대표 장면에서 실제로 발동하는가**(화면 없음):
##   godot --headless --path prophecy_godot -s tools/support_scene_probe.gd
## 결과: docs/sim/SUPPORT_SCENE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 있는가
## ---------
## "코드에 12종·36개가 들어갔다"와 "핵심 동작이 검증됐다"는 다른 말이다(사용자 지적).
## 단위 검사는 함수를 직접 불러 확인하므로 **실제 전투에서 한 번도 안 터져도 통과할 수 있다.**
## 이 도구는 보조를 하나만 달고 대표 장면을 돌려서, 그 보조가 실제로 발동하는지와
## 지표가 그 발동과 맞는지를 본다.
##
## 세 가지를 나눠 적는다
## --------------------
##   코드 반영   — impl:true이고 개조가 등록돼 있는가
##   실제 발동   — 대표 장면에서 그 보조의 고유 사건이 일어났는가(내부 계수기로 확인)
##   지표 일치   — 표준 지표(PSupport.metered)가 내부 계수기와 같은 값을 가리키는가
##
## 지표가 0인데 내부 계수기도 0이면 **발동하지 않은 것**이고,
## 내부 계수기가 없으면 **계측 미연결**이다(약하다는 뜻이 아니다).
##
## 부분 실행 축: support · seed

const STEP := 1.0 / 120.0
const MAX_SEC := 60.0
const SEEDS := [1, 2]

## 보조별로 '이것이 일어나면 발동한 것'이라고 볼 내부 계수기(st.support[id]의 키)
const FIRE_KEYS := {
	"crow": ["strikes", "marks"], "bell": ["blocked", "guarded", "reflects"],
	"echo": ["spawned", "strikes"], "wind": ["blasts", "pushed"],
	"plague": ["applied", "spreads"], "thorns": ["cuts", "reflects"],
	"doll": ["placed", "lured", "absorbed"],
	# 번개 구체는 내부 계수기 대신 표준 지표(PSupport.meter)로 바로 센다 — 감전 수정 때 그렇게 넣었다
	"orb": [], "blades": [], "frost": [], "ember": [], "mine": [],
}
## 내부 계수기가 없고 표준 지표로 바로 세는 보조
const STD_ONLY := {
	"orb": ["shocks", "shock_procs", "discharges"],
	"blades": ["hits"], "frost": ["fires"], "ember": ["fires"], "mine": ["blasts"],
}

var sub := PSubset.new()
var rows := []

func support_ids() -> Array:
	var out := []
	for wid in PCatalog.weapons():
		if not PCatalog.is_main_weapon(String(wid)):
			out.append(String(wid))
	out.sort()
	return out

## 주무기 검 + 보조 하나. 보조는 Lv3·개조 1개(구현된 첫 개조)
func build_run(sid: String, seed_v: int) -> Dictionary:
	var run := PRun.new_run(seed_v, "sword")
	PGrowth.apply_choice(run, { "kind": "weapon_new", "id": sid })
	PGrowth.apply_choice(run, { "kind": "weapon_level", "id": sid })
	PGrowth.apply_choice(run, { "kind": "weapon_level", "id": sid })
	var g: Dictionary = run.growth
	var w := PGrowth.weapon_of(g, sid)
	for mid in PCatalog.weapon(sid).get("mods", {}):
		if (w.mods as Array).size() >= PGrowth.mod_quota_of(g, w):
			break
		if bool(PCatalog.weapon(sid).mods[mid].get("impl", false)):
			PGrowth.apply_choice(run, { "kind": "weapon_mod", "id": sid, "mod": String(mid) })
	return run

func run_one(sid: String, seed_v: int) -> Dictionary:
	var run := build_run(sid, seed_v)
	var b := PRun.build(run)
	# 궁수를 넣어야 수호 방울의 차단이 잴 수 있다. 근접도 섞어 가시 갑각·인형이 일할 기회를 준다
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [[{ "type": "wolf", "n": 6 }, { "type": "archer", "n": 3 }]],
		"objective": "clear", "region_id": "den", "run": run })
	# 초보 봇: 실력 봇은 잘 피해서 방어 보조가 일할 기회 자체가 없다
	var bot := PSkillBot.new("novice", seed_v)
	var i := 0
	var steps := int(MAX_SEC / STEP)
	while i < steps and st.status == "running":
		st.step(bot.step_input(st), STEP)
		i += 1
	var inner: Dictionary = st.support.get(sid, {})
	var fired := 0
	var keys: Array = FIRE_KEYS.get(sid, [])
	for k in keys:
		fired += int(float(inner.get(String(k), 0.0)))
	var std: Dictionary = (st.metrics.support.get(sid, {}) as Dictionary).duplicate()
	if keys.is_empty() and STD_ONLY.has(sid):
		keys = STD_ONLY[sid]
		for k in keys:
			fired += int(float(std.get(String(k), 0.0)))
	var std_sum := 0.0
	for k in std:
		std_sum += float(std[k])
	return { "support": sid, "seed": seed_v, "status": String(st.status), "sec": snapped(st.t, 0.01),
		"metered": not keys.is_empty(), "fired": fired, "std_sum": snapped(std_sum, 0.1),
		"std": std, "inner": inner.duplicate() }

func _init() -> void:
	for sid in sub.pick("support", support_ids()):
		for sd in sub.pick("seed", SEEDS):
			rows.append(run_one(String(sid), int(sd)))
			printerr("done ", sid, " seed=", sd)
	print("SUPPORT_SCENE_JSON " + JSON.stringify(rows))

	var md := "# 보조무기 대표 장면 발동 확인\n\n"
	md += "생성: `tools/support_scene_probe.gd` (%s, Godot %s). 주무기 검 + 보조 하나(Lv3·개조 1).\n" % [OS.get_name(), Engine.get_version_info().string]
	md += "편성은 늑대 6 + 궁수 3, 초보 봇, 상한 %.0f초. **실력 봇은 잘 피해서 방어 보조가 일할 기회가 없다.**\n\n" % MAX_SEC
	md += "**'코드에 들어갔다'와 '실제로 발동한다'는 다른 말이다.** 이 표는 뒤쪽만 본다.\n"
	md += "모든 수치는 시험값이며 사람이 승인한 밸런스가 아니다.\n\n"
	md += sub.describe("보조 대표 장면") + "\n\n"
	md += "| 보조 | 코드 반영 | 계측 | 실제 발동(내부) | 표준 지표 합 | 판정 |\n"
	md += "|---|---|---|---:|---:|---|\n"
	var by := {}
	for r in rows:
		var k := String(r.support)
		if not by.has(k):
			by[k] = { "fired": 0, "std": 0.0, "metered": bool(r.metered) }
		by[k].fired = int(by[k].fired) + int(r.fired)
		by[k].std = float(by[k].std) + float(r.std_sum)
	for sid in support_ids():
		var d: Dictionary = by.get(String(sid), {})
		if d.is_empty():
			continue
		var W := PCatalog.weapon(String(sid))
		var mods_ok := true
		for mid in W.get("mods", {}):
			if not bool(W.mods[mid].get("impl", false)):
				mods_ok = false
		var verdict := ""
		if not bool(d.metered):
			verdict = "**계측 미연결** — 0을 약하다고 읽지 않는다"
		elif int(d.fired) == 0:
			verdict = "**발동 안 함** — 이 장면에서 한 번도 일하지 않았다"
		elif float(d.std) <= 0.0:
			verdict = "**지표 불일치** — 발동했는데 표준 지표가 0이다"
		else:
			verdict = "확인됨"
		md += "| %s | %s · 개조 %s | %s | %d | %.1f | %s |\n" % [String(W.name),
			"O" if bool(W.get("impl", false)) else "X", "3/3" if mods_ok else "일부",
			"연결" if bool(d.metered) else "미연결", int(d.fired), float(d.std), verdict]
	md += "\n## 읽는 법\n\n"
	md += "- **코드 반영**: `impl:true`이고 개조 3개가 등록됐는가. 이것만으로는 검증이 아니다.\n"
	md += "- **실제 발동**: 그 보조의 고유 사건이 대표 장면에서 일어났는가(내부 계수기).\n"
	md += "- **표준 지표 합**: `PSupport.metered`가 읽는 값의 합. 발동했는데 0이면 계측이 어긋난 것이다.\n"
	md += "- **계측 미연결**: 세는 계수기가 아직 없다. 0은 '일을 안 했다'가 아니라 '재지 못했다'는 뜻이다.\n"
	var f := FileAccess.open(sub.out_path("res://docs/sim/SUPPORT_SCENE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()
