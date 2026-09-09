extends SceneTree
## §12 "2막에서 도마뱀만 한두 마리씩 늦게 나와 전투가 늘어진다"를 **같은 시드로 전후 비교**하는 계측 도구.
## 실행: godot --headless --path prophecy_godot -s tools/probe_lizard_tail.gd
##
## 무엇을 비교하나
##   대조군(before) = 종류별 생존 상한 비율표에서 **도마뱀을 뺀** 상태(2026-09-10 이전 그대로)
##   개편(after)    = 비율표에 도마뱀 0.30을 넣은 지금
## 바뀌는 것은 '한꺼번에 몇 마리가 살아 있을 수 있는가'뿐이다 — **총 등장 수·경험치·금화 예산은 그대로다**(같이 찍는다).
##
## 재는 것
##   · 도마뱀 상한(편성 고정값 → 보정 뒤)
##   · 전투 길이 · 적이 1~2마리만 남은 시간 · 자리가 비었는데 다음 적을 기다린 시간
##   · **살아 있는 적이 도마뱀뿐이던 시간**(이번 민원의 실체)
##   · 동시 위험 공격 수(압박이 같이 부풀지 않았는지)
## 판정하지 않는다. 봇 승패는 결과가 아니다.

const STEP := 1.0 / 120.0
const MAX_SEC := 150.0
const SEEDS := [1, 2, 3]
## 도마뱀이 들어간 편성(테마·막·템플릿). data/themes.json에서 찾은 것 그대로
const CASES := [
	{ "region": "t2a_ritual", "act": 2, "tpl": "t2a_shield_shaman" },
	{ "region": "t2a_ritual", "act": 2, "tpl": "t2a_red_wolves" },
	{ "region": "t2b_mine", "act": 2, "tpl": "t2b_bomb_burrow" },
]

func lizard_share_set(v) -> void:
	var P: Dictionary = PCatalog.pacing().get("type_alive_cap_proposal", {})
	var share: Dictionary = P.get("share_by_type", {})
	if v == null:
		share.erase("lizard")
	else:
		share["lizard"] = float(v)

func find_case(c: Dictionary) -> Dictionary:
	# 그 편성 템플릿을 쓰는 실제 출격 편성을 만든다(PRun의 정상 경로를 그대로 쓴다)
	var tpl := String(c.tpl)
	for th in PCatalog.themes():
		var T: Dictionary = PCatalog.themes()[th]
		for f in T.get("formations", {}).get("normal", []):
			var F: Dictionary = f
			if String(F.id) != tpl:
				continue
			var cap := PPacing.alive_cap(int(c.act), int(F.sizes.p2.alive_cap))
			return { "tpl": F, "cap": cap, "base_caps": (F.get("type_caps", {}) as Dictionary).duplicate() }
	return {}

func run_one(c: Dictionary, seed_v: int) -> Dictionary:
	var info := find_case(c)
	if info.is_empty():
		return {}
	var F: Dictionary = info.tpl
	var cap: int = int(info.cap)
	var caps := PPacing.type_alive_cap(info.base_caps, cap)
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var units: Array = []
	var total: int = int(F.sizes.p2.total)
	var comp: Array = F.comp
	for row in comp:
		var r: Dictionary = row
		var n: int = int(round(float(total) * float(r.share)))
		for i in n:
			units.append(String(r.type))
	var st := CombatState.new({ "build": b, "seed": seed_v, "arena": "clearing", "region_id": String(c.region), "act": int(c.act),
		"formation": { "units": units, "alive_cap": cap, "group": int(F.group), "interval": float(F.interval), "type_caps": caps, "tail_boost": true },
		"fixed_build": true })
	var bot := PBot.new("balanced")
	var tail12 := 0.0
	var idle := 0.0
	var only_lizard := 0.0
	var danger_sum := 0.0
	var danger_max := 0
	var steps := 0
	var t_end := -1.0
	for i in int(round(MAX_SEC / STEP)):
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max
		st.player.dead = false
		if st.status == "lost":
			st.status = "running"
		steps += 1
		var alive := 0
		var lz := 0
		var dn := 0
		for e in st.enemies:
			if bool(e.dead) or bool(e.get("structure", false)):
				continue
			alive += 1
			if String(e.type) == "lizard":
				lz += 1
			if PEnemiesNew.danger_busy(e):
				dn += 1
		danger_sum += float(dn)
		danger_max = maxi(danger_max, dn)
		if alive > 0 and alive <= 2:
			tail12 += STEP
		if alive < cap and st.spawn_count < st.spawn_total:
			idle += STEP
		if alive > 0 and lz == alive:
			only_lizard += STEP
		if st.spawn_count >= st.spawn_total and alive == 0:
			t_end = st.t
			break
	return { "cap_lizard": int(caps.get("lizard", 0)), "base_lizard": int(info.base_caps.get("lizard", 0)),
		"total": units.size(), "len": t_end if t_end > 0.0 else MAX_SEC, "tail12": tail12, "idle": idle,
		"only_lizard": only_lizard, "danger_avg": danger_sum / maxf(1.0, float(steps)), "danger_max": danger_max,
		"done": t_end > 0.0 }

func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	a.sort()
	return float(a[a.size() / 2])

func measure(c: Dictionary, label: String) -> void:
	var lens: Array = []
	var tails: Array = []
	var idles: Array = []
	var onlys: Array = []
	var davg: Array = []
	var dmax := 0
	var capv := 0
	var basev := 0
	var totv := 0
	for s in SEEDS:
		var r := run_one(c, int(s))
		if r.is_empty():
			continue
		capv = int(r.cap_lizard)
		basev = int(r.base_lizard)
		totv = int(r.total)
		lens.append(float(r.len))
		tails.append(float(r.tail12))
		idles.append(float(r.idle))
		onlys.append(float(r.only_lizard))
		davg.append(float(r.danger_avg))
		dmax = maxi(dmax, int(r.danger_max))
	print("| %s | %s | %d → %d | %d마리 | %.1f초 | %.1f초 | %.1f초 | **%.1f초** | %.2f / %d |" % [
		String(c.tpl), label, basev, capv, totv, med(lens), med(tails), med(idles), med(onlys), med(davg), dmax])

func _init() -> void:
	print("[§12 도마뱀 말미 등장] 같은 시드(1·2·3)로 전후 비교 · 봇 '균형' · 최대 %.0f초" % MAX_SEC)
	print("전(before) = 종류별 생존 상한 비율표에 도마뱀이 **없던** 상태 / 후(after) = 도마뱀 0.30을 넣은 지금")
	print("")
	print("| 편성 | 상태 | 도마뱀 상한(편성값 → 보정) | 총 등장 | 전투 길이 | 1~2마리만 남은 시간 | 자리 비어 기다린 시간 | 도마뱀만 남은 시간 | 동시 위험 평균/최대 |")
	print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
	for c in CASES:
		var cc: Dictionary = c
		lizard_share_set(null)
		measure(cc, "전")
		lizard_share_set(0.30)
		measure(cc, "후")
	lizard_share_set(0.30)
	print("")
	print("읽는 법: '도마뱀만 남은 시간'이 줄고 '총 등장'이 그대로면 — 예산을 건드리지 않고 말미만 고친 것이다.")
	print("'동시 위험 평균/최대'가 함께 부풀지 않았는지도 같이 본다(부풀면 종류별 위험 상한 danger_limit.by_type이 일한다).")
	quit(0)
