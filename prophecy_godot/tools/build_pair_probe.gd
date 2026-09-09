extends SceneTree
## 대표 조합 10개(주무기 5종 × 장점 강화형·약점 보완형) — **핵심 개조 하나**를 얻기 전후 비교.
##   python tools/run_suites.py --suites build_pair_probe --jobs 1
## 결과: docs/sim/BUILD_PAIR_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 따로 있는가(tools/build_probe.gd와 무엇이 다른가)
## ---------------------------------------------------
## `tools/build_probe.gd`는 **개조 4개를 통째로 뺀 것**과 다 채운 것을 비교하고, 장면이
## 단일 대상·밀집 무리·이동 전투다. 이 도구는 목적이 다르다.
##   ① 조합을 **장점 강화형 / 약점 보완형** 짝으로 다시 짠다(주무기마다 2개).
##   ② 전후 차이를 **핵심 개조 한 번의 선택**으로 좁힌다. 나머지 개조 3개는 양쪽에 다 있다.
##   ③ 장면을 **일반 무리 · 튼튼한 정예 · 보스**로 바꾼다.
##   ④ 피해 말고 **발동·연쇄 · 이동/거리 유지 · 방어·제어 역할**을 함께 잰다.
## 두 도구는 **출력 파일이 다르다**(BUILD_PROBE.md / BUILD_PAIR_PROBE.md). 서로 덮어쓰지 않는다.
##
## 실제로 얻을 수 있는 조합만 만든다
## ---------------------------------
## 사전을 손으로 조립하면 "플레이로 얻을 수 없는 빌드"를 재게 된다. 여기서는 전부
## `PGrowth.apply_choice`로 만들고 **한 번이라도 false가 나오면 그 조합을 자격 위반으로 기록**한다.
## 자격은 규칙이 정한다 — 주무기 개조는 Lv2·Lv4, 보조 개조는 그 보조의 Lv2.
##
## 같은 예산·같은 금화
## -------------------
## 열 조합 모두 성장 선택 **14회**(보조 획득 2 + 주무기 레벨 4 + 보조 레벨 4 + 개조 4)를 쓴다.
## 건너뛰기(skip_choice)를 쓰지 않으므로 금화는 열 조합 모두 시작 금화 그대로다(표에 확인값을 적는다).
## '전'은 그 14회 중 **핵심 개조 1회를 아직 쓰지 않은 상태**다 — 레벨 투자는 '후'와 완전히 같다.
##
## 0과 '미계측'을 가른다
## ---------------------
## - 보조 단위: `PSupport.is_metered(id)`가 판단한다.
## - 지표 이름 단위: 그 보조가 그 이름을 실제로 쌓는지(METER_KEYS)로 판단한다.
##   `is_metered`는 참인데 그 이름은 아무도 쓰지 않는 경우가 있다(예: 회전 칼날의 차단).
## - 개조 발동 횟수: `CombatState.note_mod`를 부르는 개조만 셀 수 있다(NOTED_MODS).
##   부르지 않는 개조의 발동 수는 **0이 아니라 미계측**이다.
##
## 부분 실행 축: combo · scene · state · seed

const STEP := 1.0 / 120.0
const SEEDS := [1, 2]
const STATES := ["before", "after"]
const BOT := "regular" # 세 장면 모두 같은 실력. 초보는 방어 지표가 커지고 실력은 0이 되어 전후 비교가 흔들린다

## ---------- 대표 조합 10개 ----------
## kind: "strength" 장점을 크게 강화 / "cover" 약점을 보완해 다른 방식으로 싸운다
## key: 핵심 개조 [무기 id, 개조 id] — **맨 마지막에 고르는 한 번**이고, '전'은 이것만 빠진 상태다
## watch: 역할 지표 [보조 id, 표준 지표 이름]
const COMBOS := [
	{ "id": "sword_swarm", "name": "검·밀집 도륙", "kind": "strength", "main": "sword",
		"main_mods": ["cross", "scar"], "supports": [["plague", "burst"], ["ember", "reignite"]],
		"key": ["sword", "scar"],
		"point": "짧은 거리의 넓은 부채꼴로 몰린 적을 자주 벤다",
		"aim": "벤 자리를 한 번 더 치고, 그 처치가 독 파열과 불길 연장을 부른다",
		"watch": [["plague", "spreads"], ["plague", "bursts"], ["plague", "dot_dmg"], ["ember", "fires"]] },
	{ "id": "sword_reach", "name": "검·원격 위임", "kind": "cover", "main": "sword",
		"main_mods": ["cross", "crescent"], "supports": [["crow", "hunt"], ["frost", "ground"]],
		"key": ["frost", "ground"],
		"point": "사거리 95. 흩어지거나 거리를 두는 적에게 손이 닿지 않는다",
		"aim": "까마귀(사거리 430)가 먼 적을 맡고, 차가운 바닥이 다가오는 적을 늦춰 검이 붙을 자리를 만든다",
		"watch": [["crow", "marks"], ["crow", "hits"], ["frost", "fires"], ["frost", "slows"]] },
	{ "id": "spear_line", "name": "창·일렬 관통", "kind": "strength", "main": "spear",
		"main_mods": ["brand", "returning"], "supports": [["wind", "focused"], ["mine", "chain"]],
		"key": ["spear", "returning"],
		"point": "긴 거리의 직선 관통. 적을 일렬로 세우면 마릿수 제한 없이 꿴다",
		"aim": "압축 돌풍으로 세운 줄을 검기가 **오갈 때 두 번** 지나간다",
		"watch": [["wind", "fires"], ["wind", "push_dist"], ["mine", "blasts"]] },
	{ "id": "spear_anvil", "name": "창·모루 위임", "kind": "cover", "main": "spear",
		"main_mods": ["split", "brand"], "supports": [["doll", "tough"], ["blades", "dual"]],
		"key": ["doll", "tough"],
		"point": "폭 14의 매우 좁은 선. 붙은 적과 흩어진 적에 약하다",
		"aim": "인형이 오래 버티며 적을 한 자리에 붙잡고, 창은 그 줄을 멀리서 꿴다. 붙은 적은 칼날이 맡는다",
		"watch": [["doll", "fires"], ["doll", "taunted"], ["doll", "soaked"], ["doll", "soaked_dmg"], ["blades", "hits"]] },
	{ "id": "daggers_exec", "name": "쌍검·단일 처형", "kind": "strength", "main": "daggers",
		"main_mods": ["bleed", "pursuit"], "supports": [["orb", "conduct"], ["crow", "hunt"]],
		"key": ["orb", "conduct"],
		"point": "붙어서 3연타를 다 넣으면 단일 대상 화력이 가장 높다",
		"aim": "연타의 매 타격이 감전을 터뜨린다. 표적 하나에 화력을 몰아넣는다",
		"watch": [["orb", "shocks"], ["orb", "shock_procs"], ["orb", "shock_dmg"], ["orb", "discharges"], ["crow", "hits"]] },
	{ "id": "daggers_thorn", "name": "쌍검·되받아치기", "kind": "cover", "main": "daggers",
		"main_mods": ["bleed", "flank"], "supports": [["thorns", "focused"], ["bell", "guard"]],
		"key": ["thorns", "focused"],
		"point": "리치 62. 붙어 있어야 화력이 나오는데 그동안 계속 맞는다",
		"aim": "맞는 것을 피하는 대신 **되받아친다**. 근접 수호가 큰 한 방을 깎고 가시가 반격한다",
		"watch": [["thorns", "reduced_dmg"], ["thorns", "reflects"], ["thorns", "reflect_dmg"],
			["bell", "guards"], ["bell", "reduced_dmg"], ["bell", "blocked"], ["bell", "blocked_dmg"]] },
	{ "id": "hammer_quake", "name": "망치·광역 제압", "kind": "strength", "main": "hammer",
		"main_mods": ["shockwave", "aftershock"], "supports": [["mine", "chain"], ["ember", "scatter"]],
		"key": ["hammer", "aftershock"],
		"point": "느리지만 강한 한 방과 원형 범위·밀어내기·경직",
		"aim": "찍은 자리를 0.6초 뒤 한 번 더 터뜨리고 그 자리에 지뢰·불씨를 겹친다",
		"watch": [["mine", "blasts"], ["ember", "fires"]] },
	{ "id": "hammer_gap", "name": "망치·빈틈 메우기", "kind": "cover", "main": "hammer",
		"main_mods": ["shockwave", "pull"], "supports": [["echo", "residual"], ["frost", "ground"]],
		"key": ["hammer", "pull"],
		"point": "준비 0.45초 · 주기 1.4초. 적이 걸어 나가면 빗나가고 그 사이 빈틈이 크다",
		"aim": "착탄 직전 적을 끌어당겨 빗나감을 줄이고, 잔영과 냉기 바닥이 빈틈을 메운다",
		"watch": [["echo", "copies"], ["echo", "hits"], ["echo", "copy_dmg"], ["frost", "slows"]] },
	{ "id": "bow_kite", "name": "궁·거리 유지", "kind": "strength", "main": "bow",
		"main_mods": ["spread", "pierce"], "supports": [["wind", "lingering"], ["mine", "lure"]],
		"key": ["wind", "lingering"],
		"point": "이동하며 유지하는 원거리 공격. 안전한 사거리가 장점이다",
		"aim": "밀어낸 경로에 둔화 바람을 남겨 **다시 붙는 데 걸리는 시간**을 늘린다",
		"watch": [["wind", "fires"], ["wind", "push_dist"], ["wind", "slows"], ["mine", "blasts"]] },
	{ "id": "bow_close", "name": "궁·근접 반격", "kind": "cover", "main": "bow",
		"main_mods": ["ricochet", "spread"], "supports": [["blades", "dual"], ["thorns", "burst"]],
		"key": ["thorns", "burst"],
		"point": "쏜 자리에서 130 안이면 위력 45%. 붙으면 화력이 절반 아래로 떨어진다",
		"aim": "붙는 것을 감수하고 **붙은 적을 칼날과 원형 반격으로 정리한다**",
		"watch": [["blades", "hits"], ["blades", "dmg"], ["thorns", "reduced_dmg"], ["thorns", "reflects"], ["thorns", "reflect_dmg"]] },
]

## ---------- 장면 ----------
const SCENES := ["pack", "elite", "boss"]
const SCENE_NAME := { "pack": "일반 무리", "elite": "튼튼한 정예", "boss": "보스" }
const SCENE_SEC := { "pack": 60.0, "elite": 60.0, "boss": 180.0 }
const SCENE_DESC := {
	"pack": "늑대 8 + 궁수 2를 넣는다(약한 적 다수). **밀도 배율이 곱해지므로 실제 등장 수는 표의 '총 등장' 칸**이다. 목표 clear, 상한 60초.",
	"elite": "정예 검사 1기(단일 강적). **2막 표 체력 1381**(`act: 2`, data/pacing.json enemy_hp.elite_by_act). 정예는 밀도 배율을 받지 않는다. 목표 clear, 상한 60초.",
	"boss": "가시갈기(1막 관문 보스, 체력은 회차 규칙이 정한다). 상한 180초. **3막 보스·체력은 읽지도 건드리지도 않는다.**",
}

## ---------- 계측 연결표 ----------
## 그 보조가 실제로 쌓는 표준 지표 이름. PSupport.METER_MAP(A조·B조 7종)과
## PSupport.meter를 직접 부르는 5종(scripts/rules/weapons.gd·combat_state.gd)을 읽어 적었다.
## 여기 없는 이름의 0은 **약한 것이 아니라 재지 못한 것**이다.
const METER_KEYS := {
	"crow": ["marks", "hits", "dmg"],
	"bell": ["blocked", "blocked_dmg", "guards", "reduced_dmg", "reflects", "reflect_dmg"],
	"echo": ["copies", "hits", "copy_dmg"],
	"wind": ["fires", "push_dist", "slows"],
	"plague": ["fires", "spreads", "bursts", "dmg", "dot_dmg"],
	"thorns": ["reduced_dmg", "reflects", "hits", "dmg", "reflect_dmg"],
	"doll": ["fires", "taunted", "soaked", "soaked_dmg"],
	"blades": ["hits", "dmg"],
	"orb": ["shocks", "shock_procs", "shock_dmg", "discharges"],
	"frost": ["fires", "slows"],
	"ember": ["fires"],
	"mine": ["blasts"],
}

## `CombatState.note_mod`를 부르는 개조. 이 목록에 없는 개조의 발동 수는 셀 수 없다(미계측).
## note_mod 호출 지점(scripts/rules/weapons.gd · supports_a.gd · supports_b.gd)에서 읽어 적었다.
const NOTED_MODS := ["cross", "scar", "split", "returning", "fan", "shatter",
	"twin", "hunt", "switch", "guard", "reflect", "residual", "chase",
	"broad", "focused", "wide", "deep", "burst", "venom", "tough", "firework"]

var sub := PSubset.new()
var rows: Array = []
var faults: Array = []      # 자격 위반·구성 오류
var drift: Array = []       # NOTED_MODS 밖인데 실제로 세어진 개조(목록이 낡았다는 신호)
var gold_seen: Dictionary = {}
var boss_hp_seen: float = 0.0

func combo_of(id: String) -> Dictionary:
	for c in COMBOS:
		if String(c.id) == id:
			return c
	return {}

## 성장 선택 14회의 순서. 자격을 지키는 순서다(주무기 개조는 Lv2·Lv4, 보조 개조는 그 보조 Lv2)
func plan_of(cb: Dictionary) -> Array:
	var main := String(cb.main)
	var sa: Array = cb.supports[0]
	var sb: Array = cb.supports[1]
	return [
		{ "kind": "weapon_new", "id": String(sa[0]) },
		{ "kind": "weapon_new", "id": String(sb[0]) },
		{ "kind": "weapon_level", "id": main },                                    # Lv2 — 첫 개조 자격
		{ "kind": "weapon_mod", "id": main, "mod": String(cb.main_mods[0]) },
		{ "kind": "weapon_level", "id": String(sa[0]) },                           # 보조 A Lv2 — 개조 자격
		{ "kind": "weapon_level", "id": String(sb[0]) },                           # 보조 B Lv2 — 개조 자격
		{ "kind": "weapon_mod", "id": String(sa[0]), "mod": String(sa[1]) },
		{ "kind": "weapon_mod", "id": String(sb[0]), "mod": String(sb[1]) },
		{ "kind": "weapon_level", "id": main },                                    # Lv3
		{ "kind": "weapon_level", "id": main },                                    # Lv4 — 두 번째 개조 자격
		{ "kind": "weapon_mod", "id": main, "mod": String(cb.main_mods[1]) },
		{ "kind": "weapon_level", "id": main },                                    # Lv5
		{ "kind": "weapon_level", "id": String(sa[0]) },                           # 보조 A Lv3
		{ "kind": "weapon_level", "id": String(sb[0]) },                           # 보조 B Lv3
	]

func is_key(cb: Dictionary, c: Dictionary) -> bool:
	return String(c.kind) == "weapon_mod" and String(c.id) == String(cb.key[0]) and String(c.mod) == String(cb.key[1])

## 실제 성장 규칙으로만 키운다. state="before"면 핵심 개조 한 번을 빼고, "after"면 맨 마지막에 더한다
func make_run(cb: Dictionary, seed_v: int, state: String) -> Dictionary:
	var run: Dictionary = PRun.new_run(seed_v, String(cb.main))
	var key_choice := {}
	for c in plan_of(cb):
		var ch: Dictionary = c
		if is_key(cb, ch):
			key_choice = ch
			continue
		if not PGrowth.apply_choice(run, ch):
			faults.append("%s: 자격 위반 %s" % [String(cb.id), JSON.stringify(ch)])
	if key_choice.is_empty():
		faults.append("%s: 핵심 개조 %s가 선택 계획에 없다" % [String(cb.id), String(cb.key[1])])
	elif state == "after":
		if not PGrowth.apply_choice(run, key_choice):
			faults.append("%s: 핵심 개조 자격 위반 %s" % [String(cb.id), JSON.stringify(key_choice)])
	return run

## 편성이 규칙 상한을 지켰는지(주무기 1·Lv5·개조 2 / 보조 2·각 Lv3·개조 1)
func check_shape(cb: Dictionary, run: Dictionary, state: String) -> void:
	var g: Dictionary = run.growth
	var mains: Array = PGrowth.main_weapons(g)
	var sups: Array = PGrowth.support_weapons(g)
	var want_mods := 4 if state == "after" else 3
	var got_mods := 0
	if mains.size() != 1:
		faults.append("%s/%s: 주무기 %d개" % [String(cb.id), state, mains.size()])
	if sups.size() != 2:
		faults.append("%s/%s: 보조 %d개" % [String(cb.id), state, sups.size()])
	for w in g.weapons:
		var wd: Dictionary = w
		var cap := PGrowth.mod_cap(g, String(wd.id))
		got_mods += (wd.mods as Array).size()
		if (wd.mods as Array).size() > cap:
			faults.append("%s/%s: %s 개조 %d개(상한 %d)" % [String(cb.id), state, String(wd.id), (wd.mods as Array).size(), cap])
		if int(wd.level) != PGrowth.level_cap(g, String(wd.id)):
			faults.append("%s/%s: %s Lv%d(상한 %d)" % [String(cb.id), state, String(wd.id), int(wd.level), PGrowth.level_cap(g, String(wd.id))])
	if got_mods != want_mods:
		faults.append("%s/%s: 개조 합계 %d개(기대 %d)" % [String(cb.id), state, got_mods, want_mods])
	gold_seen[String(cb.id) + "/" + state] = int(run.get("gold", -1))

func loadout_of(run: Dictionary) -> Array:
	var out: Array = []
	var g: Dictionary = run.growth
	for w in g.weapons:
		var wd: Dictionary = w
		var names: Array = []
		for m in wd.mods:
			names.append(String(PCatalog.weapon(String(wd.id)).mods[String(m)].name))
		out.append("%s Lv%d%s" % [String(PCatalog.weapon(String(wd.id)).name), int(wd.level),
			("+" + "+".join(names)) if names.size() > 0 else ""])
	return out

func opts_for(scene: String, b: Dictionary, seed_v: int, run: Dictionary) -> Dictionary:
	if scene == "boss":
		return { "build": b, "hp": float(b.hp_max), "seed": seed_v, "boss": true, "boss_id": "boss",
			"boss_hp": PRun.boss_hp(run, "boss"), "arena": "clearing", "region_id": "boss", "run": run }
	if scene == "pack":
		return { "build": b, "hp": float(b.hp_max), "seed": seed_v,
			"waves": [[{ "type": "wolf", "n": 8 }, { "type": "archer", "n": 2 }]],
			"objective": "clear", "region_id": "den", "run": run }
	# 정예는 **2막 표 체력**으로 세운다(act=2 → PPacing.elite_by_act). 1막 값 280은 이 완성 빌드가
	# 5초에 지워 버려 전후 차이가 보이지 않는다. 이 빌드의 실측 화력(보스전 약 68/초)은
	# 자료가 2막 기준으로 잡은 화력(enemy_hp.ref_dps.act2 = 68)과 같은 자리다.
	return { "build": b, "hp": float(b.hp_max), "seed": seed_v, "act": 2,
		"waves": [[{ "type": "elite_blademaster", "n": 1 }]],
		"objective": "clear", "region_id": "den", "run": run }

func run_one(cb: Dictionary, scene: String, state: String, seed_v: int) -> Dictionary:
	var run: Dictionary = make_run(cb, seed_v, state)
	check_shape(cb, run, state)
	var b: Dictionary = PRun.build(run)
	var st := CombatState.new(opts_for(scene, b, seed_v, run))
	var bot := PSkillBot.new(BOT, seed_v)
	var steps := int(SCENE_SEC[scene] / STEP)
	var i := 0
	var kills := 0
	var multi := 0
	var travel := 0.0
	var gap_sum := 0.0
	var gap_n := 0
	var chill_frames := 0
	var lure_frames := 0
	var near_frames := 0     # 가장 가까운 적이 120 안에 있던 프레임(근접 교전 시간)
	while i < steps and st.status == "running":
		var px := float(st.player.x)
		var py := float(st.player.y)
		st.step(bot.step_input(st), STEP)
		travel += PGeom.dist(px, py, float(st.player.x), float(st.player.y))
		var best := -1.0
		for e in st.alive_targets():
			var ed: Dictionary = e
			if bool(ed.get("structure", false)):
				continue
			var d: float = PGeom.dist(float(st.player.x), float(st.player.y), float(ed.x), float(ed.y)) - float(ed.r)
			if best < 0.0 or d < best:
				best = d
			if float(ed.get("chill", 0.0)) > 0.0:
				chill_frames += 1
		if best >= 0.0:
			gap_sum += best
			gap_n += 1
			if best <= 120.0:
				near_frames += 1
		if st.support.has("doll_obj"):
			var dob: Dictionary = st.support["doll_obj"]
			lure_frames += (dob.get("lured", {}) as Dictionary).size()
		var k := int(st.stats.kills)
		if k - kills >= 2:
			multi += 1
		kills = k
		i += 1
	var dealt := 0.0
	for k2 in (st.metrics.dmg as Dictionary):
		dealt += float(st.metrics.dmg[k2])
	var base_dmg := float(st.metrics.cause_dmg.get("base", 0.0))
	var indirect := 0.0
	if dealt > 0.0:
		indirect = (dealt - base_dmg) / dealt
	var taken_hits := 0
	for k3 in (st.metrics.taken_hits as Dictionary):
		taken_hits += int(st.metrics.taken_hits[k3])
	var sup := {}
	for s in cb.supports:
		var sid := String((s as Array)[0])
		sup[sid] = (st.metrics.support.get(sid, {}) as Dictionary).duplicate()
	var key_mod := String(cb.key[1])
	var ms: Dictionary = (st.mod_stats as Dictionary).get(key_mod, {})
	for mid in (st.mod_stats as Dictionary):
		if not NOTED_MODS.has(String(mid)):
			var note := "%s: 계측되는데 NOTED_MODS에 없다" % String(mid)
			if not drift.has(note):
				drift.append(note)
	return { "combo": String(cb.id), "scene": scene, "state": state, "seed": seed_v,
		"status": String(st.status), "sec": snappedf(st.t, 0.01), "kills": int(st.stats.kills),
		"dealt": snappedf(dealt, 0.1), "taken": snappedf(float(st.stats.damage_taken), 0.1),
		"taken_nominal": snappedf(float(st.stats.damage_taken_nominal), 0.1),
		"absorbed": snappedf(float(st.stats.absorbed), 0.1), "taken_hits": taken_hits,
		"attacks": int(st.stats.attacks), "hits": int(st.stats.hits),
		"indirect": snappedf(indirect * 100.0, 0.1), "multi": multi,
		"travel": snappedf(travel, 0.1), "gap": snappedf(gap_sum / maxf(1.0, float(gap_n)), 0.1),
		"near_sec": snappedf(float(near_frames) * STEP, 0.01),
		"chill_sec": snappedf(float(chill_frames) * STEP, 0.01),
		"lure_sec": snappedf(float(lure_frames) * STEP, 0.01),
		"key_procs": int(ms.get("procs", 0)), "key_hits": int(ms.get("hits", 0)),
		"key_dmg": snappedf(float(ms.get("damage", 0.0)), 0.1),
		"spawn_total": (1 if scene == "boss" else int(st.spawn_total)),
		"support": sup, "loadout": loadout_of(run) }

## 같은 조합·장면·상태의 시드 평균
func pick_row(cid: String, scene: String, state: String) -> Dictionary:
	var acc := {}
	var n := 0
	var num := ["sec", "kills", "dealt", "taken", "taken_nominal", "absorbed", "taken_hits",
		"attacks", "hits", "indirect", "multi", "travel", "gap", "near_sec", "chill_sec", "lure_sec",
		"key_procs", "key_hits", "key_dmg", "spawn_total"]
	for r in rows:
		var rd: Dictionary = r
		if String(rd.combo) != cid or String(rd.scene) != scene or String(rd.state) != state:
			continue
		n += 1
		for k in num:
			acc[k] = float(acc.get(k, 0.0)) + float(rd[k])
		acc["won"] = float(acc.get("won", 0.0)) + (1.0 if String(rd.status) == "won" else 0.0)
		var sup: Dictionary = acc.get("support", {})
		for sid in (rd.support as Dictionary):
			var cur: Dictionary = sup.get(String(sid), {})
			for key in (rd.support[sid] as Dictionary):
				cur[String(key)] = float(cur.get(String(key), 0.0)) + float(rd.support[sid][key])
			sup[String(sid)] = cur
		acc["support"] = sup
		acc["loadout"] = rd.loadout
	if n == 0:
		return {}
	for k in num:
		acc[k] = snappedf(float(acc[k]) / float(n), 0.1)
	var sup2: Dictionary = acc.get("support", {})
	for sid in sup2:
		var cur2: Dictionary = sup2[sid]
		for key in cur2:
			cur2[key] = snappedf(float(cur2[key]) / float(n), 0.1)
	acc["n"] = n
	return acc

## 그 지표 이름을 그 보조가 실제로 쌓는가
func metered_key(sid: String, key: String) -> bool:
	if not PSupport.is_metered(sid):
		return false
	return (METER_KEYS.get(sid, []) as Array).has(key)

func meters_text(cb: Dictionary, sup: Dictionary) -> String:
	var parts: Array = []
	for w in cb.watch:
		var pair: Array = w
		var sid := String(pair[0])
		var key := String(pair[1])
		if not metered_key(sid, key):
			parts.append("%s %s **미계측**" % [sid, key])
			continue
		var v := float((sup.get(sid, {}) as Dictionary).get(key, 0.0))
		parts.append("%s %s %s" % [sid, key, str(snappedf(v, 0.1))])
	return " · ".join(parts) if parts.size() > 0 else "-"

func key_text(cb: Dictionary, r: Dictionary) -> String:
	var mid := String(cb.key[1])
	if not NOTED_MODS.has(mid):
		return "**미계측**(note_mod 없음)"
	return "발동 %.1f · 적중 %.1f · 피해 %.1f" % [float(r.key_procs), float(r.key_hits), float(r.key_dmg)]

func res_text(r: Dictionary) -> String:
	return "%d/%d 승" % [int(r.won), int(r.n)]

func time_text(r: Dictionary) -> String:
	if int(r.won) < int(r.n):
		return "%.1f(미완 포함)" % float(r.sec)
	return "%.1f" % float(r.sec)

func _init() -> void:
	# 보스 체력은 회차 규칙이 정한다. 열 조합이 같은 방식으로 만들어지므로 값도 같다(부분 실행에서도 적어 둔다)
	boss_hp_seen = PRun.boss_hp(PRun.new_run(1, "sword"), "boss")
	var ids: Array = []
	for c in COMBOS:
		ids.append(String(c.id))
	for cid in sub.pick("combo", ids):
		var cb: Dictionary = combo_of(String(cid))
		for scene in sub.pick("scene", SCENES):
			for state in sub.pick("state", STATES):
				for sd in sub.pick("seed", SEEDS):
					rows.append(run_one(cb, String(scene), String(state), int(sd)))
			printerr("done ", cid, " ", scene)
	print("BUILD_PAIR_PROBE_JSON " + JSON.stringify({ "rows": rows, "faults": faults, "drift": drift,
		"gold": gold_seen, "boss_hp": boss_hp_seen }))

	var md := sub.describe("대표 조합 10개 — 핵심 개조 전후 비교")
	md += "생성: `tools/build_pair_probe.gd` (%s, Godot %s). 봇 %s · 시드 %s.\n" % [
		OS.get_name(), Engine.get_version_info().string, BOT, str(SEEDS)]
	md += "**전수 시뮬레이션이 아니다.** 주무기 5종마다 장점 강화형·약점 보완형 하나씩, 모두 10개만 돌린다.\n"
	md += "'전'과 '후'는 **핵심 개조 한 번의 선택**만 다르다. 나머지 개조 3개와 레벨 투자는 양쪽이 같다.\n"
	md += "**모든 수치는 시험값이다.** 사람이 승인한 밸런스가 아니고, 봇 결과로 재미가 승인된 것도 아니다.\n\n"

	md += "## 0. 조합이 실제로 얻을 수 있는 것인가\n\n"
	md += "| 항목 | 결과 |\n|---|---|\n"
	md += "| 자격 위반(`PGrowth.apply_choice` false) | %s |\n" % ("없음" if faults.is_empty() else str(faults.size()) + "건 — 아래 목록")
	var gold_vals: Array = []
	for k in gold_seen:
		if not gold_vals.has(int(gold_seen[k])):
			gold_vals.append(int(gold_seen[k]))
	md += "| 금화(모든 조합·상태) | %s |\n" % ("모두 %d로 같다" % int(gold_vals[0]) if gold_vals.size() == 1 else "다르다: " + str(gold_vals))
	md += "| 성장 선택 예산 | '후' 14회(보조 2 + 주무기 레벨 4 + 보조 레벨 4 + 개조 4) · '전' 13회(핵심 개조 미사용) |\n"
	md += "| 보스 체력 | %d(1막 가시갈기, `PRun.boss_hp`) |\n" % int(boss_hp_seen)
	if not faults.is_empty():
		md += "\n자격 위반 목록:\n\n"
		for f in faults:
			md += "- %s\n" % String(f)
	if not drift.is_empty():
		md += "\n**NOTED_MODS 목록이 낡았다**(계측되는데 목록에 없다):\n\n"
		for d in drift:
			md += "- %s\n" % String(d)
	md += "\n"

	md += "## 1. 조합 10개\n\n"
	md += "| # | 조합 | 짝 | 주무기(개조 2) | 보조 A | 보조 B | 핵심 개조(마지막) | 노리는 것 |\n"
	md += "|---:|---|---|---|---|---|---|---|\n"
	var idx := 0
	for c in COMBOS:
		var cb2: Dictionary = c
		idx += 1
		var kind_s := "장점 강화" if String(cb2.kind) == "strength" else "약점 보완"
		var mn := PCatalog.weapon(String(cb2.main))
		var m1 := String(mn.mods[String(cb2.main_mods[0])].name)
		var m2 := String(mn.mods[String(cb2.main_mods[1])].name)
		var sa: Array = cb2.supports[0]
		var sb: Array = cb2.supports[1]
		var sa_n := "%s + %s" % [String(PCatalog.weapon(String(sa[0])).name), String(PCatalog.weapon(String(sa[0])).mods[String(sa[1])].name)]
		var sb_n := "%s + %s" % [String(PCatalog.weapon(String(sb[0])).name), String(PCatalog.weapon(String(sb[0])).mods[String(sb[1])].name)]
		var kw := PCatalog.weapon(String(cb2.key[0]))
		md += "| %d | %s | %s | %s + %s + %s | %s | %s | **%s**(%s) | %s |\n" % [
			idx, String(cb2.name), kind_s, String(mn.name), m1, m2, sa_n, sb_n,
			String(kw.mods[String(cb2.key[1])].name), String(kw.name), String(cb2.aim)]
	md += "\n장점·약점의 근거는 `data/main_weapons.json`의 `roles`다.\n\n"
	md += "| 조합 | 이 주무기의 장점 또는 약점 |\n|---|---|\n"
	for c in COMBOS:
		var cb3: Dictionary = c
		md += "| %s | %s |\n" % [String(cb3.name), String(cb3.point)]
	md += "\n"

	for scene in SCENES:
		var any := false
		for c0 in COMBOS:
			for st0 in STATES:
				if not pick_row(String((c0 as Dictionary).id), String(scene), String(st0)).is_empty():
					any = true
		if not any:
			continue # 이번 실행에서 돌리지 않은 장면은 빈 표를 만들지 않는다
		md += "## 2.%s %s\n\n" % [str(SCENES.find(scene) + 1), String(SCENE_NAME[scene])]
		md += "%s 봇 %s.\n\n" % [String(SCENE_DESC[scene]), BOT]
		md += "### 성과\n\n"
		md += "| 조합 | 상태 | 결과 | 걸린 시간 | 총 등장 | 처치 | 준 피해 | 받은 피해 | 명목 피해 | 피격 수 | 공격 시작 | 명중 |\n"
		md += "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
		for c in COMBOS:
			var cb4: Dictionary = c
			for state in STATES:
				var r := pick_row(String(cb4.id), String(scene), String(state))
				if r.is_empty():
					continue
				md += "| %s | %s | %s | %s | %.0f | %.1f | %.0f | %.1f | %.1f | %.1f | %.0f | %.0f |\n" % [
					String(cb4.name), ("전" if state == "before" else "후"), res_text(r), time_text(r),
					float(r.spawn_total), float(r.kills), float(r.dealt), float(r.taken), float(r.taken_nominal),
					float(r.taken_hits), float(r.attacks), float(r.hits)]
		md += "\n### 발동·연쇄\n\n"
		md += "| 조합 | 상태 | 핵심 개조 | 간접 피해 비율 | 여럿이 함께 죽은 프레임 | 보조 역할 지표 |\n"
		md += "|---|---|---|---:|---:|---|\n"
		for c in COMBOS:
			var cb5: Dictionary = c
			for state in STATES:
				var r2 := pick_row(String(cb5.id), String(scene), String(state))
				if r2.is_empty():
					continue
				md += "| %s | %s | %s | %.1f%% | %.1f | %s |\n" % [
					String(cb5.name), ("전" if state == "before" else "후"), key_text(cb5, r2),
					float(r2.indirect), float(r2.multi), meters_text(cb5, r2.support)]
		md += "\n### 이동·거리 유지와 방어·제어\n\n"
		md += "| 조합 | 상태 | 평균 교전 거리 | 이동 거리 | 근접(120 이내) 시간 | 냉기 시간(적·초) | 유인 시간(적·초) | 방어가 줄인 피해 | 흡수 |\n"
		md += "|---|---|---:|---:|---:|---:|---:|---:|---:|\n"
		for c in COMBOS:
			var cb6: Dictionary = c
			for state in STATES:
				var r3 := pick_row(String(cb6.id), String(scene), String(state))
				if r3.is_empty():
					continue
				md += "| %s | %s | %.1f | %.0f | %.1f | %.2f | %.2f | %.1f | %.1f |\n" % [
					String(cb6.name), ("전" if state == "before" else "후"), float(r3.gap), float(r3.travel),
					float(r3.near_sec), float(r3.chill_sec), float(r3.lure_sec),
					float(r3.taken_nominal) - float(r3.taken), float(r3.absorbed)]
		md += "\n"

	md += "## 3. 한눈에 — 핵심 개조 전 → 후\n\n"
	md += "| 조합 | 짝 | 핵심 개조 | 무리 시간 | 무리 받은 피해 | 정예 시간 | 정예 받은 피해 | 보스 시간 | 보스 받은 피해 | 평균 교전 거리(무리) |\n"
	md += "|---|---|---|---:|---:|---:|---:|---:|---:|---:|\n"
	for c in COMBOS:
		var cb9: Dictionary = c
		var cells: Array = []
		for scene2 in SCENES:
			var a := pick_row(String(cb9.id), String(scene2), "before")
			var b2 := pick_row(String(cb9.id), String(scene2), "after")
			if a.is_empty() or b2.is_empty():
				cells.append("-")
				cells.append("-")
				continue
			cells.append("%s → %s" % [time_text(a), time_text(b2)])
			cells.append("%.1f → %.1f" % [float(a.taken), float(b2.taken)])
		var pa := pick_row(String(cb9.id), "pack", "before")
		var pb := pick_row(String(cb9.id), "pack", "after")
		var gap_s := "-" if (pa.is_empty() or pb.is_empty()) else "%.1f → %.1f" % [float(pa.gap), float(pb.gap)]
		var kw2 := PCatalog.weapon(String(cb9.key[0]))
		md += "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % [
			String(cb9.name), ("장점 강화" if String(cb9.kind) == "strength" else "약점 보완"),
			String(kw2.mods[String(cb9.key[1])].name),
			String(cells[0]), String(cells[1]), String(cells[2]), String(cells[3]),
			String(cells[4]), String(cells[5]), gap_s]
	md += "\n**한 줄 요약을 승인으로 읽지 마라.** 시드 %d개 평균이고 봇 결과다.\n\n" % SEEDS.size()

	md += "## 4. 계측이 연결되지 않은 것\n\n"
	md += "| 대상 | 판단 근거 | 상태 |\n|---|---|---|\n"
	var seen: Dictionary = {}
	for c in COMBOS:
		var cb7: Dictionary = c
		for w in cb7.watch:
			var pair2: Array = w
			var sid := String(pair2[0])
			var key := String(pair2[1])
			var kk := sid + "." + key
			if seen.has(kk):
				continue
			seen[kk] = true
			if not PSupport.is_metered(sid):
				md += "| %s %s | `PSupport.is_metered` 거짓 | **미계측** |\n" % [sid, key]
			elif not metered_key(sid, key):
				md += "| %s %s | 보조는 계측되지만 이 이름을 쌓는 코드가 없다 | **미계측** |\n" % [sid, key]
	for c in COMBOS:
		var cb8: Dictionary = c
		var mid2 := String(cb8.key[1])
		var kk2 := "mod." + mid2
		if seen.has(kk2):
			continue
		seen[kk2] = true
		if not NOTED_MODS.has(mid2):
			md += "| 개조 `%s` 발동 수 | `note_mod`를 부르지 않는다 | **미계측** |\n" % mid2
	md += "\n표의 다른 칸이 0인 것은 **재었는데 0**이라는 뜻이다. 여기 적힌 것만 재지 못한 것이다.\n\n"

	md += "## 5. 읽는 법\n\n"
	md += "- **평균 교전 거리**는 매 프레임 가장 가까운 살아 있는 적까지의 표면 거리 평균이다(도구가 직접 잰다).\n"
	md += "  **이동 거리**는 플레이어가 실제로 지나간 길이다. 둘이 함께 움직여야 \"싸우는 방식이 바뀌었다\"고 말할 수 있다.\n"
	md += "- **냉기 시간 · 유인 시간**은 도구가 매 프레임 세어 초로 바꾼 값이다(적 한 마리가 1초 걸리면 1). 규칙 코드는 이 값을 세지 않는다.\n"
	md += "- **방어가 줄인 피해** = 명목 피해 − 받은 피해. 경감·수호·차단이 실제로 깎은 양이다.\n"
	md += "- **간접 피해 비율**은 주무기 기본 발사(`base`) 밖의 모든 경로가 낸 피해 비율이다.\n"
	md += "- **여럿이 함께 죽은 프레임**은 한 프레임에 2마리 이상 죽은 횟수(연쇄 체감의 근사)다.\n"
	md += "  **처치 원인을 남기는 훅이 없어 '연쇄 처치 수'는 여전히 정확히 셀 수 없다.**\n"
	md += "- 정예·보스는 제압 저항이 있다(`data/supports.json` resist): 밀어내기 정예 0.35·보스 0, 유인 정예 0.5·보스 0, 둔화 정예 0.6·보스 0.35.\n"
	md += "  그 장면에서 제어 지표가 작은 것은 **규칙대로**이지 결함이 아니다.\n"

	var f := FileAccess.open(sub.out_path("res://docs/sim/BUILD_PAIR_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()
