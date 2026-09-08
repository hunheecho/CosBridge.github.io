class_name PRun
extends RefCounted
## 회차 상태(HTML run.js 이식): 날짜·시간대·장소·금화·재료·장비·상점·대장간·보스 관문·체력. 전투 밖의 모든 규칙.
## run dict는 HTML 필드명(camelCase)을 그대로 쓴다(테스트·문서 1:1). "값 없음"은 JS처럼 null(run.stock, growth.steer 등).
## 이식 결정(docs/PORT_BASELINE.md): mode는 "trio"만, 레거시 필드(gear/owned/augments)·이전 저장 migrate 없음, 기본 밸런스 세트 = balance_default(test03)이되
## 적 체력 난이도는 "base"(D33: 지역 ×1, candE는 F3 후보). 원정대의 갑옷 회복(winHeal)은 PFlow.settle_*victory에서 승리마다 1회(C7).
## 난수는 PRng(mulberry32)만, 시각(Time)은 new_run의 seed 0 대체에서만 쓴다.

const VERSION := 4
const DEEP_KINDS := ["gold_big", "equipment", "voucher", "steer"]

static func C() -> Dictionary: return PCatalog.config()
static func W() -> Dictionary: return PCatalog.world()
static func SH() -> Dictionary: return PCatalog.shop()

# ---------- 새 회차 ----------
## seed_v 0 = 현재 시각에서 고른다(HTML: PA.clock.now() % 100000). balance ""면 balance_default. mode는 trio 고정.
## opts(선택): { density_set: "roles" 등 밀도 세트(비교용), world_stages: bool,
##   profile: 프로필 dict(영구 성장, 시험값 — 있으면 run.unlocks 스냅샷·run.traits 고정·run.profileKind), eligible: bool(실제 플레이 회차만 true → 영구 기록 대상) }.
## opts에 profile이 없으면(봇·시험실·도구·테스트) unlocks 키 없음 = 전부 열림, profileEligible=false — 기존 동작 그대로
static func new_run(seed_v: int, start_weapon: String, balance: String = "", opts: Dictionary = {}) -> Dictionary:
	var cfg := C()
	var BS := PCatalog.balance_sets()
	var bal := balance if (balance != "" and BS.has(balance)) else String(PCatalog.balance().balance_default)
	var B: Dictionary = BS[bal] if BS.has(bal) else {}
	var s := seed_v
	if s == 0:
		s = int(Time.get_unix_time_from_system()) % 100000
		if s == 0:
			s = 1
	var run := {
		"version": VERSION, "seed": s,
		"balance": bal, "bossHpSet": String(B.get("bossHpSet", "base")), "dayHpSet": String(B.get("dayHp", "none")),
		"mode": String(opts.get("mode", PCatalog.run_mode_default())), "stage": 0, "bossesDone": [], "bossRecords": {}, # acts = 10일·3막 본편(사용자 결정), trio = 옛 7일 호환
		"growth": PGrowth.new_growth(start_weapon if start_weapon != "" else "sword"),
		"layout": "classic", "difficulty": "base", # D33: Godot 기본은 적 체력 ×1(세트의 candE는 쓰지 않는다)
		"sortieCount": 0,
		"phase": "prep", # prep(준비) | boss_prep(관문) | cleared(완주)
		"bossRetries": 0, "bossClear": null,
		"day": 1, "hours": int(cfg.HOURS_PER_DAY), # hours = 남은 시간대 칸 수. 현재 칸 = HOURS_PER_DAY - hours
		"gold": int(cfg.START_GOLD), "mats": { "pelt": 0, "iron": 0, "spore": 0, "fang": 0 },
		"equipment": { "weapon": null, "armor": null, "shield": null }, "bag": [], "forge": 0,
		"visited": {}, "schedule": {}, "stock": null, "merchant": null,
		"hp": float(cfg.PLAYER.hp),
		"log": [],
		"stats": { "encounters": 0, "wins": 0, "losses": 0, "kills": 0 },
		"dmgStats": { "combats": [], "byKey": {} },
		"services": {}, "cards": null, "missionsDone": {}, "pendingSortie": null, "buffs": {}, "lastEvent": null, "lastSupplyDay": null, "eventsResolved": 0,
		"ended": false, "bossEntry": null,
		"worldStages": bool(opts.get("world_stages", true)), "densitySet": String(opts.get("density_set", "")),
		"aliveCapSet": String(opts.get("alive_cap_set", "")), # 막별 동시 상한 세트(빈 값 = 기본 acts, "legacy" = 기존 상한 대조군)
		"worldFeature": pick_world_feature(s), "lastFormation": {}, # 반복 콘텐츠(시드 확정, 재접속 재추첨 없음)
		"route": pick_route(s, opts), # 10일·3막: 막마다 테마 1개(독립 경로 난수, 저장·재추첨 없음). trio는 []
		"profileEligible": bool(opts.get("eligible", false)), "traits": [], "startWeapon": (start_weapon if start_weapon != "" else "sword"),
		"storedShield": 0.0, "crafted": [],
		"endless": null, "mainCleared": false, # 무한 모드 상태(PEndless)·본편 완주 확정(무한에서 죽어도 유지)
	}
	var profile = opts.get("profile", null)
	if profile != null and typeof(profile) == TYPE_DICTIONARY and not (profile as Dictionary).is_empty():
		run.unlocks = PProfile.unlocked(profile) # 해금 스냅샷: 회차 중 프로필이 바뀌어도 이 회차의 후보는 그대로
		run.traits = PProfile.selected_traits(profile) # 출발 시 고정
		run.profileKind = String(profile.get("kind", "trial"))
		run.profileLevel = int(PProfile.level(profile))
		var cq := PProfile.conqueror_snapshot(profile) # 정복자 배분 스냅샷(출발 후 고정, 무한 도중 레벨업 소급 없음). 포인트 없으면 키 없음
		if not cq.is_empty():
			run.conqueror = cq
	run.bossPlan = pick_boss_plan(s, run) # 경로의 테마 보스(또는 boss_gates 후보)
	PSortie.cards_for(run) # 1일차 장소·목적 확정
	refresh_stock(run)
	return run

static func build(run: Dictionary) -> Dictionary: return PBuild.derive(run)

# ---------- 반복 콘텐츠(2026-09-07 사용자 합의 방향, 값은 시험값) ----------
## 회차 특징: 시드로 1개 확정. 저장 필드(run.worldFeature)만 읽으므로 재접속 재추첨이 없다
static func pick_world_feature(seed_v: int) -> String:
	var L: Array = W().get("world_features", {}).get("list", [])
	if L.is_empty():
		return ""
	var rng := PRng.new((seed_v * 31 + 5) & 0xFFFFFFFF)
	return String(L[rng.int_range(0, L.size() - 1)].id)

static func world_feature(run: Dictionary) -> Dictionary:
	var id := String(run.get("worldFeature", ""))
	for f in W().get("world_features", {}).get("list", []):
		if String(f.id) == id:
			return f
	return {}

## 관문별 보스 계획: 경로(테마)가 있으면 테마의 보스, 없으면 boss_gates 후보 중 시드로 확정(후보 1개면 그대로). 거점에 미리 표시한다
static func pick_boss_plan(seed_v: int, run: Dictionary = {}) -> Array:
	var route: Array = run.get("route", [])
	if not route.is_empty():
		var out_r := []
		for tid in route:
			out_r.append(String(PCatalog.theme(String(tid)).boss))
		return out_r
	var G: Array = W().get("boss_gates", {}).get("gates", [])
	var rng := PRng.new((seed_v * 53 + 9) & 0xFFFFFFFF)
	var out := []
	for g in G:
		var cands: Array = g.candidates
		out.append(String(cands[rng.int_range(0, cands.size() - 1)]) if cands.size() > 1 else String(cands[0]))
	return out

# ---------- 테마 경로(10일·3막, 계획서 §4) ----------
## 구현된 테마 = 보스가 실제 구현된 테마(보스 정의 존재). 기본 3 → 6 → 9 단계로 늘어난다
static func theme_implemented(tid: String) -> bool:
	var t := PCatalog.theme(tid)
	if t.is_empty():
		return false
	return PCatalog.boss_defs().has(String(t.boss))

static func themes_for_act(act: int, implemented_only: bool = true) -> Array:
	var out := []
	for tid in PCatalog.themes():
		var t: Dictionary = PCatalog.themes()[tid]
		if int(t.act) == act and (not implemented_only or theme_implemented(String(tid))):
			out.append(String(tid))
	out.sort()
	return out

## 경로: 막마다 후보 중 균등 추첨(첫 시험값), 막별 독립 난수(seed×(211+act)+act). opts.route가 있으면(검증 메뉴) 그대로(합법성만 검사)
static func pick_route(seed_v: int, opts: Dictionary = {}) -> Array:
	var RM := PCatalog.run_modes()
	var mode := String(opts.get("mode", PCatalog.run_mode_default()))
	var A: Array = (RM[mode] as Dictionary).get("acts", []) if RM.has(mode) else []
	if A.is_empty():
		return []
	if bool(opts.get("legacy_places", false)) or OS.get_environment("PROPHECY_LEGACY_PLACES") != "": # 테마 없이 기존 지역 일정(비교·회귀 테스트용: 옛 지역 규칙 스위트는 이 환경 변수로 실행)
		return []
	var forced: Array = opts.get("route", [])
	var out := []
	for a in A:
		var act := int(a.id)
		var cands := themes_for_act(act)
		if cands.is_empty():
			cands = [PCatalog.act_default_theme(act)]
		var pick := ""
		if forced.size() >= act and cands.has(String(forced[act - 1])):
			pick = String(forced[act - 1])
		else:
			var rng := PRng.new((seed_v * (211 + act) + act) & 0xFFFFFFFF)
			pick = String(cands[rng.int_range(0, cands.size() - 1)])
		out.append(pick)
	return out

static func route_theme(run: Dictionary, act: int) -> Dictionary:
	var route: Array = run.get("route", [])
	if act >= 1 and act <= route.size():
		return PCatalog.theme(String(route[act - 1]))
	return {}

static func current_theme(run: Dictionary, day: int = 0) -> Dictionary:
	var a := act_of(run, day)
	return route_theme(run, int(a.get("id", 0))) if not a.is_empty() else {}

## 테마 장소인가
static func is_theme_place(region_id: String) -> bool:
	return PCatalog.theme_places().has(region_id)

## 템플릿 → 웨이브(최종 수 명시 + 경험치 기준 ref). 장소 규모(p1/p2)로 정수 배정, 나머지는 첫 주력에. 정예는 마지막.
## 총 등장 수는 날짜 예산표(PPacing.day_total, 사용자 결정 25 → 75)가 정하고 템플릿의 sizes.total은 표가 없을 때의 예비값이다.
## 밀도 배율(×5)을 여기에 다시 곱하지 않는다(테마 템플릿은 ref가 있어 PFormation이 배율을 적용하지 않는다).
## 경험치 예산(xp_ref)은 개체 수와 무관하게 고정이므로 수가 늘어도 전투당 경험치는 늘지 않는다.
static func template_waves(tpl: Dictionary, place_key: String, day: int = 0, place_cost: int = 1) -> Array:
	var sz: Dictionary = tpl.sizes[place_key]
	var total: int = int(sz.total)
	if day > 0 and not bool(tpl.get("fixed_total", false)):
		var budget := PPacing.day_total(day, place_cost)
		if budget > 0:
			total = budget
	var xp_ref: float = float(sz.xp_ref)
	var wave := []
	var assigned := 0
	var first := true
	var comp: Array = tpl.comp
	for c in comp:
		var n: int = int(round(total * float(c.share)))
		wave.append({ "type": String(c.type), "n": n, "ref": xp_ref * float(c.share) })
		assigned += n
	if not wave.is_empty():
		wave[0].n = int(wave[0].n) + (total - assigned)
	if int(tpl.get("elites", 0)) > 0:
		wave.append({ "type": "wolf_alpha", "n": int(tpl.elites), "ref": float(tpl.elites) })
	return [wave]

static func theme_place_key(region_id: String) -> String:
	var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
	if t.is_empty():
		return "p1"
	return "p1" if String((t.places as Array)[0].id) == region_id else "p2"

static func theme_template(region_id: String, formation_id: String) -> Dictionary:
	var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
	if t.is_empty():
		return {}
	if t.has("first_day") and String((t.first_day as Dictionary).id) == formation_id:
		return t.first_day
	for f in (t.formations.normal as Array) + (t.formations.risk as Array):
		if String(f.id) == formation_id:
			return f
	return {}

## 템플릿의 동시 상한·묶음·간격·종류별 상한(밀도 세트 배율은 적용하지 않는다)
## 템플릿의 동시 상한·묶음·간격·종류별 상한. act > 0이면 막별 동시 상한(PPacing, 시험값)이 템플릿 값을 덮어쓴다.
## 승인된 첫날 기준 전투(fixed_alive_cap)는 어떤 세트에서도 템플릿 값(12) 그대로다.
static func theme_density_override(region_id: String, formation_id: String, act: int = 0, cap_set: String = "") -> Dictionary:
	var tpl := theme_template(region_id, formation_id)
	if tpl.is_empty():
		return {}
	var pk := theme_place_key(region_id)
	var cap: int = int(tpl.sizes[pk].alive_cap)
	if act > 0 and not bool(tpl.get("fixed_alive_cap", false)):
		cap = PPacing.alive_cap(act, cap, cap_set)
	return { "alive_cap": cap, "squad_mix": true, "tail_boost": not bool(tpl.get("fixed_total", false)), "group": int(tpl.get("group", 3)), "interval": float(tpl.get("interval", 1.0)), "type_alive_cap": (tpl.get("type_caps", {}) as Dictionary).duplicate(), "multiplier": 1.0, "multiplier_by_type": {}, "set_name": "template" }

## 방문 상인이 오는 날짜(회차 특징으로 바뀔 수 있음)
static func merchant_days(run: Dictionary) -> Array:
	var mode := String(run.get("mode", "trio"))
	var f := world_feature(run)
	if String(f.get("kind", "")) == "merchant":
		var fm: Dictionary = f.get("merchant_days_by_mode", {})
		if fm.has(mode):
			return fm[mode]
		if f.has("merchant_days"):
			return f.merchant_days
	var MV: Dictionary = W().merchant_visits
	var bm: Dictionary = MV.get("by_mode", {})
	return bm[mode] if bm.has(mode) else MV.days

## 위험 임무 확률·보상 배율(회차 특징 'risk')
static func risk_chance(run: Dictionary) -> float:
	var f := world_feature(run)
	return float(f.risk_chance) if String(f.get("kind", "")) == "risk" else float(PCatalog.mission_rules().riskChance)

static func risk_reward_mult(run: Dictionary) -> float:
	var f := world_feature(run)
	return float(f.risk_reward_mult) if String(f.get("kind", "")) == "risk" else float(PCatalog.mission_rules().riskRewardMult)

## 사건 가중치(회차 특징 'events'): 없는 종류는 1, 0이면 제외
static func event_weight(run: Dictionary, event_id: String) -> float:
	var f := world_feature(run)
	if String(f.get("kind", "")) == "events":
		return float((f.get("event_weights", {}) as Dictionary).get(event_id, 1.0))
	return 1.0

## 지역×날짜의 편성 대안(기본 "base" + formation_sets). 첫날 숲은 고정(D33). 테마 장소는 템플릿(일반 3, 위험 전투는 risk)
static func formation_options(region_id: String, day: int, risk: bool = false) -> Array:
	if is_theme_place(region_id):
		var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
		if day <= 1 and not risk and t.has("first_day") and String((t.first_day as Dictionary).place) == region_id: # 승인된 첫 전투(D33 늑대 25) 고정
			var fd: Dictionary = t.first_day
			return [{ "id": String(fd.id), "name": String(fd.name), "desc": String(fd.get("desc", "")) }]
		var outt := []
		for f in (t.formations.risk if risk else t.formations.normal):
			outt.append({ "id": String(f.id), "name": String(f.name), "desc": String(f.get("desc", "")) })
		return outt
	var out := [{ "id": "base", "name": "기본", "desc": "" }]
	if region_id == "forest" and day <= 1:
		return out
	var FS: Dictionary = W().get("formation_sets", {})
	if not FS.has(region_id):
		return out
	var key := day_key(region_id, day)
	for a in (FS[region_id] as Dictionary).get(key, []):
		out.append({ "id": String(a.id), "name": String(a.name), "desc": String(a.get("desc", "")) })
	return out

static func formation_waves(region_id: String, day: int, formation_id: String) -> Array:
	if is_theme_place(region_id):
		var tpl := theme_template(region_id, formation_id)
		if tpl.is_empty():
			var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
			tpl = (t.formations.normal as Array)[0]
		return template_waves(tpl, theme_place_key(region_id), day, place_cost(region_id))
	if formation_id == "" or formation_id == "base":
		return day_waves(region_id, day)
	var FS: Dictionary = W().get("formation_sets", {})
	if FS.has(region_id):
		for a in (FS[region_id] as Dictionary).get(day_key(region_id, day), []):
			if String(a.id) == formation_id:
				return a.waves
	return day_waves(region_id, day)

## 시간대 변주 목록(표시용): 실제 출발 시간대 기준(비용 2 장소의 저녁 변주는 오후로 이동, Q4). 화면 문구와 출발 시간대를 같은 함수로 맞춘다
static func slot_variants_list(region_id: String) -> Array:
	var out := []
	for s in 5:
		var v := slot_variant(region_id, s)
		if not v.is_empty():
			out.append(v)
	return out

static func add_log(run: Dictionary, msg: String) -> void:
	if not run.has("log"): run.log = []
	(run.log as Array).insert(0, "%d일차 · %s" % [int(run.get("day", 1)), msg])
	if (run.log as Array).size() > 8: (run.log as Array).resize(8)

# ---------- 밸런스 세트 ----------
static func balance_set(run: Dictionary) -> Dictionary:
	var BS := PCatalog.balance_sets()
	var bal := String(run.get("balance", "current"))
	return BS[bal] if BS.has(bal) else {}

## 처치 경험치 배율(HTML PA.GROWTH.XP_KILL_MULT = 세트.killXp)
static func kill_xp_mult(run: Dictionary) -> float:
	return float(balance_set(run).get("killXp", 1.0))

## 지역 경험치 배율(HTML PA.GROWTH.BONUS_XP_MULT = 세트.bonusXp)
static func bonus_xp_mult(run: Dictionary) -> float:
	return float(balance_set(run).get("bonusXp", 1.0))

static func region_bonus_xp(run: Dictionary, region_id: String, deep: bool) -> float:
	var base_bonus: float = float(PCatalog.growth().REGION_BONUS_XP.get(region_id, 0.0))
	if is_theme_place(region_id):
		base_bonus = float(PCatalog.theme_places()[region_id].get("bonus_xp", 0.0))
	var v: float = base_bonus * bonus_xp_mult(run)
	return round((v * 1.5 if deep else v) * 100.0) / 100.0

# ---------- 회차 구조(trio) ----------
static func mode_def(run: Dictionary) -> Dictionary:
	var RM := PCatalog.run_modes()
	var m := String(run.get("mode", "trio"))
	return RM[m] if RM.has(m) else RM.trio

## 막(act): 10일 본편은 1~3/4~6/7~9일 탐험, 관문 4/7/10. 옛 trio 모드는 막 정의가 없어 {}를 돌려준다
static func acts(run: Dictionary) -> Array:
	return mode_def(run).get("acts", [])

static func act_of(run: Dictionary, day: int = 0) -> Dictionary:
	var d: int = day if day > 0 else int(run.get("day", 1))
	var A := acts(run)
	var passed: int = int(run.get("stage", 0)) # 넘은 관문 수. 관문일에 관문을 넘었으면 남은 칸은 다음 막
	for i in A.size():
		var a: Dictionary = A[i]
		var in_days := false
		for x in a.days: # JSON 숫자는 float → int 비교
			if int(x) == d:
				in_days = true
		if in_days:
			return a
		if int(a.gate_day) == d:
			return A[i + 1] if (passed > i and i + 1 < A.size()) else a
	return A[A.size() - 1] if A.size() > 0 else {}

static func act_label(run: Dictionary, day: int = 0) -> String:
	if PEndless.active(run) or PEndless.is_over(run):
		return "무한 %d구간" % PEndless.segment(run)
	var a := act_of(run, day)
	if a.is_empty():
		return ""
	var th := route_theme(run, int(a.id))
	return String(a.name) + ((" · " + String(th.name)) if not th.is_empty() else "")

## 관문 준비 화면용 다음 막 미리보기(계획서 §4: 다음 막의 장소·대표 적·위협 한 줄·보스 이름). 없으면 {}
static func act_preview(run: Dictionary) -> Dictionary:
	var A := acts(run)
	if A.is_empty():
		return {}
	var cur := act_of(run)
	var idx := -1
	for i in A.size():
		if int(A[i].id) == int(cur.get("id", -1)):
			idx = i
	var nb := next_boss(run)
	var next_act: Dictionary = {}
	# 관문 준비(gate_day) 시점: 이 관문을 넘으면 시작되는 막 = 현재 act(gate_day를 포함) 다음 막
	if is_boss_day(run) and idx >= 0 and idx + 1 < A.size():
		next_act = A[idx + 1]
	elif is_boss_day(run) and idx >= 0 and idx + 1 >= A.size():
		return { "final": true, "boss": (String(nb.id) if not nb.is_empty() else "") }
	if next_act.is_empty():
		return {}
	var days: Array = next_act.days
	var places := []
	var enemies := []
	var nth0 := route_theme(run, int(next_act.id)) # 다음 막 테마가 있으면 그 장소·대표 적(현재 막 장소와 섞지 않음)
	if not nth0.is_empty():
		for p in nth0.places:
			places.append(String(p.id))
		for wave in day_waves(String((nth0.places as Array)[0].id), int(days[0])):
			for g in wave:
				if not enemies.has(String(g.type)) and not bool(PCatalog.enemy(String(g.type)).get("elite", false)):
					enemies.append(String(g.type))
		for wave in day_waves(String((nth0.places as Array)[1].id), int(days[0])):
			for g in wave:
				if not enemies.has(String(g.type)) and not bool(PCatalog.enemy(String(g.type)).get("elite", false)):
					enemies.append(String(g.type))
	else:
		for d in days:
			for id in places_for(run, int(d)):
				var rid := String(id)
				if not places.has(rid):
					places.append(rid)
				for wave in day_waves(rid, int(d)):
					for g in wave:
						if not enemies.has(String(g.type)) and not bool(PCatalog.enemy(String(g.type)).get("elite", false)):
							enemies.append(String(g.type))
	var next_gate: Dictionary = {}
	var bosses: Array = mode_def(run).bosses
	var st: int = int(run.get("stage", 0)) + 1
	if st < bosses.size():
		next_gate = (bosses[st] as Dictionary).duplicate()
		var plan: Array = run.get("bossPlan", [])
		if st < plan.size():
			next_gate.id = String(plan[st])
	var nth := route_theme(run, int(next_act.id))
	return { "act": next_act, "places": places, "enemies": enemies.slice(0, 4), "gate": next_gate, "theme": nth }

## 다음 보스 정의 {id, day, hpKey, rare}. 완주 후에는 {}. 회차의 보스 계획(bossPlan, 관문별 후보에서 시드로 확정)이 있으면 그 id를 쓴다
static func next_boss(run: Dictionary) -> Dictionary:
	var bosses: Array = mode_def(run).bosses
	var st: int = int(run.get("stage", 0))
	if st < 0 or st >= bosses.size():
		return {}
	var nb: Dictionary = (bosses[st] as Dictionary).duplicate()
	var plan: Array = run.get("bossPlan", [])
	if st < plan.size():
		nb.id = String(plan[st])
	return nb

static func next_boss_cfg(run: Dictionary) -> Dictionary:
	var nb := next_boss(run)
	if not nb.is_empty():
		return PCatalog.boss_def(String(nb.id))
	var done: Array = run.get("bossesDone", [])
	return PCatalog.boss_def(String(done[done.size() - 1])) if done.size() > 0 else PCatalog.boss_def("boss")

static func boss_hp(run: Dictionary, boss_id: String) -> float:
	var nb := {}
	for b in mode_def(run).bosses:
		if String(b.id) == boss_id:
			nb = b
	var sets := PCatalog.boss_hp_sets()
	var set_id := String(run.get("bossHpSet", ""))
	var H: Dictionary = sets[set_id] if sets.has(set_id) else sets.base
	var mult: float = PEndless.boss_hp_mult(run) if PEndless.active(run) else 1.0 # 무한 구간 계단(시험값)
	var hp_key := String(nb.hpKey) if not nb.is_empty() else ""
	var over := PPacing.boss_hp(set_id, boss_id, hp_key) # 밸런스 오버레이(사용자 기록 기반 산술 후보, 시험값)
	if over > 0.0:
		return over * mult
	if not nb.is_empty() and H.has(boss_id) and (H[boss_id] as Dictionary).has(hp_key):
		return float(H[boss_id][hp_key]) * mult
	return float(PCatalog.boss_def(boss_id).hp) * mult

static func stage_count(run: Dictionary) -> int: return (mode_def(run).bosses as Array).size()

## 회차 일정 한 줄(화면 표시용). 새 회차 = "본편 · 10일", 옛 저장 = "이전 회차 · 7일 일정".
## 버전이 같아도 회차 설정이 같지 않다는 것을 화면에서 구분하기 위한 것이다(검토 문서 §1).
static func schedule_label(run: Dictionary) -> String:
	if run.is_empty():
		return ""
	var md := mode_def(run)
	var days := int(md.get("days", 0))
	var gates: Array = []
	for b in md.get("bosses", []):
		gates.append(str(int(b.day)))
	var name := "본편" if String(run.get("mode", "")) == PCatalog.run_mode_default() else "이전 회차"
	return "%s · %d일 일정 (관문 %s)" % [name, days, "/".join(gates)]

## 짧은 형태("본편 · 10일" / "이전 회차 · 7일 일정") — 버튼·머리말용
static func schedule_short(run: Dictionary) -> String:
	if run.is_empty():
		return ""
	var days := int(mode_def(run).get("days", 0))
	if String(run.get("mode", "")) == PCatalog.run_mode_default():
		return "본편 · %d일" % days
	return "이전 회차 · %d일 일정" % days

## 저장 dict(회차를 만들지 않고)에서 같은 판정: 계속하기 버튼 라벨용
static func schedule_short_of_save(saved: Dictionary) -> String:
	if saved.is_empty():
		return ""
	var mode := String(saved.get("mode", "trio"))
	var RM := PCatalog.run_modes()
	var days := int((RM[mode] as Dictionary).get("days", 0)) if RM.has(mode) else 0
	if mode == PCatalog.run_mode_default():
		return "본편 · %d일" % days
	return "이전 회차 · %d일 일정" % days

## 결과 화면·검증 기록용 실제 설정 한 줄(일정·밀도 세트·밸런스 세트·동시 상한 세트·시드)
static func settings_record(run: Dictionary) -> String:
	if run.is_empty():
		return ""
	var D := PCatalog.density()
	var ds := String(run.get("densitySet", ""))
	if ds == "":
		ds = String(D.get("set_default", "uniform_x5"))
	var BS := PCatalog.balance_sets()
	var bal := String(run.get("balance", ""))
	var bal_name := String(BS[bal].name) if BS.has(bal) else bal
	var cap := String(run.get("aliveCapSet", ""))
	if cap == "":
		cap = PPacing.alive_cap_set_default()
	return "%s · 밀도 %s · 동시 상한 %s · %s · 시드 %d" % [schedule_label(run), ds, cap, bal_name, int(run.seed)]
static func boss_days_left(run: Dictionary) -> int:
	var nb := next_boss(run)
	return int(nb.day) - int(run.day) if not nb.is_empty() else 0
static func is_boss_day(run: Dictionary) -> bool:
	var nb := next_boss(run)
	return not nb.is_empty() and int(run.day) >= int(nb.day)

# ---------- 시간대 ----------
static func time_slots() -> Array: return W().time_slots
static func slot_index(run: Dictionary) -> int:
	return maxi(0, mini(time_slots().size() - 1, int(C().HOURS_PER_DAY) - int(run.hours)))
static func slot_name(run: Dictionary) -> String:
	return "저녁 끝" if int(run.hours) <= 0 else String(time_slots()[slot_index(run)])
static func next_slot_name(run: Dictionary, cost: int = 1) -> String:
	var i := slot_index(run) + cost
	return "하루 끝" if i >= time_slots().size() else String(time_slots()[i])

# ---------- 지역/출격 ----------
static func region(id: String) -> Dictionary: return PCatalog.region(id)
static func place_cost(region_id: String) -> int:
	var cost: Dictionary = W().schedule.cost
	return int(cost[region_id]) if cost.has(region_id) else int(region(region_id).get("cost", 1))

## 오늘의 장소 2곳. 6일차 첫 칸은 이전 방문 지역 중 시드로 1곳(run.schedule에 저장해 재접속으로 바뀌지 않게)
static func places_for(run: Dictionary, day: int = 0) -> Array:
	var d: int = day if day > 0 else int(run.day)
	var key := str(d)
	var sched: Dictionary = run.schedule
	if sched.has(key):
		return sched[key]
	var places: Dictionary = W().schedule.places
	var by_mode: Dictionary = W().schedule.get("places_by_mode", {})
	var mode := String(run.get("mode", "trio"))
	if by_mode.has(mode):
		places = by_mode[mode]
	var base: Array = (places[key] as Array).duplicate() if places.has(key) else []
	var th := current_theme(run, d) # 테마 경로가 있으면 그 막의 테마 장소 2곳(1칸·2칸). 10일차는 없음
	if not th.is_empty():
		var A := acts(run)
		var last_gate: int = int(A[A.size() - 1].gate_day) if A.size() > 0 else 99
		base = [] if d >= last_gate else [String((th.places as Array)[0].id), String((th.places as Array)[1].id)]
	if base.has(null): # 재방문: 이전 방문 지역 중 1칸 장소 우선(마지막 칸에도 실제 행동이 남게)
		var visited := []
		for id in run.get("visited", {}):
			if String(id) != "deep" and not base.has(id) and place_cost(String(id)) <= 1:
				visited.append(String(id))
		var pool: Array = visited if visited.size() > 0 else ["forest"]
		var rng := PRng.new((int(run.seed) * 53 + d * 977) & 0xFFFFFFFF)
		base[base.find(null)] = pool[rng.int_range(0, pool.size() - 1)]
	sched[key] = base
	return base

static func can_sortie(run: Dictionary, region_id: String, cost_override: int = 0) -> bool:
	var cost: int = cost_override if cost_override > 0 else place_cost(region_id)
	return String(run.phase) == "prep" and not is_boss_day(run) and places_for(run).has(region_id) and int(run.hours) >= cost

## 오늘 남은 시간으로 나갈 수 있는 출격이 하나라도 있는가(휴식이 '선택'인지 '어쩔 수 없음'인지 구분용, 지시 8)
static func any_departure(run: Dictionary) -> bool:
	if String(run.phase) != "prep" or is_boss_day(run):
		return false
	for c in PSortie.cards_for(run):
		if PSortie.can_start(run, c):
			return true
	return not PSortie.repeat_cards(run).is_empty()

## 시간대 변주 {slot, name, desc, ...}. 없으면 {}.
## C11(F2 도달 불가 수정): 비용 2 장소(습지·심층)의 저녁(4) 변주는 저녁에 출발할 수 없으므로(남은 칸 1 < 2) 오후(3)에 노출한다. 명시적 3 변주가 있으면 그것이 우선
static func slot_variant(region_id: String, slot: int) -> Dictionary:
	var SV: Dictionary = W().slot_variants
	if not SV.has(region_id):
		return {}
	var V: Dictionary = SV[region_id]
	var key := str(slot)
	var remap: bool = place_cost(region_id) >= 2
	if V.has(key) and not (remap and slot == 4):
		var out := { "slot": slot }
		for k in V[key]:
			out[k] = V[key][k]
		return out
	if remap and slot == 3 and V.has("4"):
		var out := { "slot": 3, "remappedFrom": 4 }
		for k in V["4"]:
			out[k] = V["4"][k]
		return out
	return {}

## 출격 시작(카드 경로는 PSortie.start). 불가하면 push_error 후 {}
static func start_sortie(run: Dictionary, region_id: String, cost_override: int = 0) -> Dictionary:
	var cost: int = cost_override if cost_override > 0 else place_cost(region_id)
	if not can_sortie(run, region_id, cost):
		push_error("시간 부족" if int(run.hours) < cost else "오늘 갈 수 없는 장소")
		return {}
	var slot := slot_index(run)
	var variant := slot_variant(region_id, slot) # 출발 시점의 시간대로 편성·사건·보상 확정
	run.hours = int(run.hours) - cost
	run.sortieCount = int(run.sortieCount) + 1
	run.visited[region_id] = int(run.visited.get(region_id, 0)) + 1
	return { "regionId": region_id, "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0,
		"seed": int(run.seed) * 131 + int(run.sortieCount) * 17 + int(run.day), "day": int(run.day), "slot": slot, "variant": (variant if not variant.is_empty() else null) }

static func layout_region(region_id: String, run: Dictionary) -> Dictionary:
	var L := PCatalog.layouts()
	var lid := String(run.get("layout", "classic"))
	if L.has(lid) and (L[lid].regions as Dictionary).has(region_id):
		return L[lid].regions[region_id]
	return {}

## 세계 변화 단계(사용자 합의 2026-09-07): 실제 관문 완료(bossesDone)에서만 도출한다. 날짜만 지나도 바뀌지 않고, 재도전·계속하기·보상 대기에서도 같은 값(파생값이라 두 번 전환되지 않음)
static func world_stage(run: Dictionary) -> int:
	if not bool(run.get("worldStages", true)):
		return 0
	var S: Array = PCatalog.world_stages().get("stages", [])
	var done: Array = run.get("bossesDone", [])
	var stage := 0
	for i in range(1, S.size()):
		var ab := String(S[i].get("after_boss", ""))
		if ab != "" and done.has(ab):
			stage = i
		else:
			break
	return stage

static func world_stage_def(run: Dictionary) -> Dictionary:
	var S: Array = PCatalog.world_stages().get("stages", [])
	var i := world_stage(run)
	return S[i] if i < S.size() else { "id": 0, "name": "변화 전", "mix": { "normal": 1.0 } }

## 등급 비율(종류별 정수 편성은 PFormation이 한다)
static func tier_mix(run: Dictionary) -> Dictionary:
	if PEndless.active(run):
		return PEndless.tier_mix(run) # 무한: 구간별 하위 등급 퇴장(시험값)
	return (world_stage_def(run).get("mix", { "normal": 1.0 }) as Dictionary).duplicate()

## 지역의 적 종류(날짜 편성 기준, 등장 순)
static func region_enemies(region_id: String, run: Dictionary) -> Array:
	var out := []
	for wave in day_waves(region_id, int(run.get("day", 1))):
		for g in wave:
			if not out.has(String(g.type)):
				out.append(String(g.type))
	return out

## 전장: 배치안(layout)의 arena → world.region_arena → "forest"
static func region_arena(region_id: String, run: Dictionary = {}) -> String:
	if not run.is_empty():
		var lr := layout_region(region_id, run)
		if lr.has("arena"):
			return String(lr.arena)
	if is_theme_place(region_id):
		return String(PCatalog.theme_places()[region_id].get("arena", "clearing"))
	return String(W().region_arena.get(region_id, "forest"))

## 날짜별 편성 키: 그 날짜 이하에서 가장 가까운 정의
static func day_key(region_id: String, day: int) -> String:
	var T: Dictionary = W().day_waves
	if not T.has(region_id):
		return ""
	var keys := []
	for k in T[region_id]:
		keys.append(int(String(k)))
	keys.sort()
	var best := -1
	for k in keys:
		if k <= maxi(1, day):
			best = k
	if best < 0:
		best = keys[0]
	return str(best)

## 날짜별 편성: 그 날짜 이하에서 가장 가까운 정의
static func day_waves(region_id: String, day: int) -> Array:
	if is_theme_place(region_id): # 테마 장소: 첫 일반 템플릿(대표 편성)
		var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
		return template_waves((t.formations.normal as Array)[0], theme_place_key(region_id))
	var T: Dictionary = W().day_waves
	if not T.has(region_id):
		return region(region_id).waves
	return T[region_id][day_key(region_id, day)]

static func _copy_waves(src: Array) -> Array:
	var out := []
	for w in src:
		var wave := []
		for g in w:
			var e := { "type": String(g.type), "n": int(g.n) }
			if g.has("ref"):
				e.ref = float(g.ref) # 테마 템플릿의 경험치 기준(최종 수 명시 표시)
			wave.append(e)
		out.append(wave)
	return out

static func encounter_waves(region_id: String, deep: bool, run: Dictionary, sortie: Dictionary = {}) -> Array:
	var waves := _copy_waves(formation_waves(region_id, int(run.get("day", 1)), String(sortie.get("formationId", "base"))))
	var v = sortie.get("variant", null)
	if v != null:
		if bool(v.get("dropLastWave", false)) and waves.size() > 1:
			waves.resize(waves.size() - 1)
		if v.has("extra"):
			for g in v.extra:
				(waves[waves.size() - 1] as Array).append({ "type": String(g.type), "n": int(g.n) })
		if bool(v.get("addElite", false)):
			var last: Array = waves[waves.size() - 1]
			var found := false
			for g in last:
				if String(g.type) == "wolf_alpha":
					g.n = int(g.n) + 1
					found = true
					break
			if not found:
				last.append({ "type": "wolf_alpha", "n": 1 })
	if not deep:
		return waves
	for w in waves: # 더 깊이: 웨이브마다 +1, 마지막에 정예 추가(없다면)
		for g in w:
			g.n = int(g.n) + 1
	var last: Array = waves[waves.size() - 1]
	var has_elite := false
	for g in last:
		if String(g.type) == "wolf_alpha":
			has_elite = true
	if not has_elite:
		last.append({ "type": "wolf_alpha", "n": 1 })
	return waves

## 일반·정예·더 깊이 모두 전멸 종료. "elite"는 HUD 정보
static func encounter_objective(region_id: String, deep: bool, _run: Dictionary) -> String:
	return "elite" if deep else String(region(region_id).get("objective", "clear"))

## 체력 배율: 지역 후보 × 날짜 배율(체력만) × 정예 날짜 보정. 플레이어 공격력과 무관
static func hp_mult_for(run: Dictionary, region_id: String, deep: bool) -> Dictionary:
	var cands: Dictionary = PCatalog.difficulty().candidates
	var did := String(run.get("difficulty", "base"))
	var c: Dictionary = cands[did] if cands.has(did) else cands.base
	var day: int = int(run.get("day", 1))
	var sets: Dictionary = W().day_hp_sets
	var sid := String(run.get("dayHpSet", "none"))
	var arr: Array = sets[sid] if sets.has(sid) else sets.none
	var idx := mini(6, day)
	var dm: float = float(arr[idx]) if idx < arr.size() else 1.0
	if bool(run.get("worldStages", true)) and bool(PCatalog.world_stages().get("excludes_day_hp_set", true)):
		dm = 1.0 # 세계 변화(등급)와 날짜 체력 세트는 중복 적용하지 않는다
	var v: float = float(c.hp.get(region_id, 1.0)) * (float(c.get("deepMult", 1.0)) if deep else 1.0) * dm
	if PEndless.active(run):
		v *= PEndless.enemy_hp_mult(run) # 무한 구간 계단(선형, 시험값)
	var EDM: Dictionary = W().elite_day_mult
	var em: float = float(EDM.mult) if day >= int(EDM.from) else 1.0
	return { "normal": round(v * 100.0) / 100.0, "elite": round(v * em * 100.0) / 100.0, "boss": 1.0 }

static func layout_text(run: Dictionary) -> String:
	var parts := []
	var BS := PCatalog.balance_sets()
	var bal := String(run.get("balance", "current"))
	if bal != "current" and BS.has(bal):
		parts.append("밸런스: " + String(BS[bal].name))
	var lid := String(run.get("layout", "classic"))
	if lid != "classic" and PCatalog.layouts().has(lid):
		parts.append("배치: " + String(PCatalog.layouts()[lid].name))
	var did := String(run.get("difficulty", "base"))
	if did != "base" and (PCatalog.difficulty().candidates as Dictionary).has(did):
		parts.append("난이도: " + String(PCatalog.difficulty().candidates[did].name))
	return " · ".join(parts)

# ---------- 더 깊이 ----------
static func can_deep_explore(run: Dictionary, sortie: Dictionary) -> bool:
	return int(run.hours) >= int(C().DEEP_EXPLORE_HOURS) and not bool(sortie.get("mission", false)) and not bool(sortie.get("deepDone", false))

## 더 깊이 미리보기. 보상 종류·장비는 출격 시드로 확정(재접속 동일). F5 수정: RNG 한 스트림(종류 → 장비 순), 결과는 sortie.deepPreview에 저장해 재호출 시 같은 값
static func deep_preview(run: Dictionary, sortie: Dictionary) -> Dictionary:
	if sortie.get("deepPreview", null) != null:
		var cached: Dictionary = sortie.deepPreview
		cached.nextSlot = next_slot_name(run, int(C().DEEP_EXPLORE_HOURS)) # 시간대 표기만 현재 상태로
		cached.hpMult = hp_mult_for(run, String(sortie.regionId), true)
		cached.lootAtRisk = _loot_at_risk(sortie)
		return cached
	var rng := PRng.new((int(sortie.seed) * 3 + 11) & 0xFFFFFFFF)
	var kind := String(DEEP_KINDS[rng.int_range(0, DEEP_KINDS.size() - 1)])
	var pool := []
	var items: Array = sortie.loot.get("items", [])
	for id in PCatalog.equipment(): # 일반 장비만(제작 전용은 후보 아님) + 해금 스냅샷
		if not owns_equip(run, String(id)) and not items.has(id) and PProfile.run_unlock_ok(run, "equipment", String(id)):
			pool.append(String(id))
	if kind == "equipment" and pool.is_empty():
		kind = "gold_big"
	if kind == "steer" and run.growth.get("steer", null) != null:
		kind = "gold_big"
	var r := region(String(sortie.regionId))
	var gold_mult: float = float(C().DEEP_REWARD_MULT)
	var reward := {}
	match kind:
		"gold_big":
			var g := int(round(float(r.reward.gold[1]) * gold_mult))
			reward = { "kind": kind, "text": "금화 큰 묶음 (+%d 추가)" % g, "gold": g }
		"equipment":
			var item := String(pool[rng.int_range(0, pool.size() - 1)])
			reward = { "kind": kind, "text": "장비 1개: %s" % String(PCatalog.equipment()[item].name), "item": item }
		"voucher":
			reward = { "kind": kind, "text": "개조 교체권 1장", "service": "mod_swap" }
		_:
			reward = { "kind": kind, "text": "다음 레벨업 예약: 자동기술 개조", "steer": "weapon_mod" }
	var out := { "extraTime": int(C().DEEP_EXPLORE_HOURS), "nextSlot": next_slot_name(run, int(C().DEEP_EXPLORE_HOURS)), "enemyChange": "웨이브마다 적 +1, 마지막에 정예(가시갈기)",
		"hpMult": hp_mult_for(run, String(sortie.regionId), true), "reward": reward, "lootAtRisk": _loot_at_risk(sortie) }
	sortie.deepPreview = out
	return out

static func _loot_at_risk(sortie: Dictionary) -> Dictionary:
	return { "gold": int(sortie.loot.gold), "items": (sortie.loot.get("items", []) as Array).duplicate(), "services": (sortie.loot.get("services", []) as Array).duplicate() }

static func deep_explore(run: Dictionary, sortie: Dictionary) -> bool:
	if not can_deep_explore(run, sortie):
		push_error("더 깊이 불가")
		return false
	run.hours = int(run.hours) - int(C().DEEP_EXPLORE_HOURS)
	sortie.deep = true
	sortie.deepDone = true
	sortie.deepReward = deep_preview(run, sortie).reward
	return true

## 더 깊이 승리: 표시된 보상을 미정산 전리품에 얹는다(귀환 시 정산). null이면 이미 반영됨/없음
static func apply_deep_reward(_run: Dictionary, sortie: Dictionary) -> Variant:
	var rw = sortie.get("deepReward", null)
	if rw == null or bool(sortie.get("deepRewarded", false)):
		return null
	sortie.deepRewarded = true
	var loot: Dictionary = sortie.loot
	match String(rw.kind):
		"gold_big": loot.gold = int(loot.gold) + PPacing.gold_award(int(rw.gold))
		"equipment":
			if not loot.has("items"): loot.items = []
			(loot.items as Array).append(String(rw.item))
		"voucher":
			if not loot.has("services"): loot.services = []
			(loot.services as Array).append(String(rw.service))
		"steer": loot.steer = String(rw.steer)
	return rw

# ---------- 조우 정산 ----------
## 조우 승리 보상(난수는 전투의 rng → 재현 가능). combat_stats: {chestGold, eliteKilled}
static func roll_reward(_run: Dictionary, sortie: Dictionary, rng: PRng, combat_stats: Dictionary) -> Dictionary:
	var r := region(String(sortie.regionId))
	var mult: float = float(C().DEEP_REWARD_MULT) if bool(sortie.get("deep", false)) else 1.0
	var v = sortie.get("variant", null)
	var gm: float = float(v.goldMult) if (v != null and v.has("goldMult")) else 1.0
	var gold := int(round(float(rng.int_range(int(r.reward.gold[0]), int(r.reward.gold[1]))) * mult * gm))
	var mats := {}
	for k in r.reward.mats:
		var lo: int = int(r.reward.mats[k][0])
		var hi: int = int(r.reward.mats[k][1])
		var n := rng.int_range(lo, hi)
		if String(k) == "fang":
			n = 1 if bool(combat_stats.get("eliteKilled", false)) else 0 # 송곳니는 정예 처치 시에만
		elif bool(sortie.get("deep", false)):
			n = int(round(float(n) * mult))
		if n > 0:
			mats[String(k)] = n
	# 금화 감축(사용자 결정 약 -30%, 시험값 ×0.7)은 "새로 지급하는" 금화에만 최종 1회. 판매금·환불·잔액에는 적용하지 않는다
	return { "gold": PPacing.gold_award(gold), "mats": mats, "chestGold": PPacing.gold_award(int(combat_stats.get("chestGold", 0))) }

static func apply_encounter_result(run: Dictionary, sortie: Dictionary, result: String, reward: Dictionary, combat_hp: float) -> void:
	run.stats.encounters = int(run.stats.encounters) + 1
	sortie.encounters = int(sortie.get("encounters", 0)) + 1
	run.hp = maxf(0.0, combat_hp)
	if result == "won":
		run.stats.wins = int(run.stats.wins) + 1
		sortie.loot.gold = int(sortie.loot.gold) + int(reward.gold) + int(reward.get("chestGold", 0))
		for k in reward.mats:
			sortie.loot.mats[k] = int(sortie.loot.mats.get(k, 0)) + int(reward.mats[k])
	else:
		run.stats.losses = int(run.stats.losses) + 1

## 귀환 정산(정확히 1회): 금화·재료·장비(가방)·이용권·성장 예약. 원정대의 갑옷 회복은 여기가 아니라 승리 정산(PFlow.settle_victory, C7)
static func return_to_base(run: Dictionary, sortie: Dictionary) -> void:
	if bool(sortie.get("settled", false)) or bool(sortie.get("lost", false)):
		return
	sortie.settled = true
	var loot: Dictionary = sortie.loot
	run.gold = int(run.gold) + int(loot.gold)
	for k in loot.mats:
		run.mats[k] = int(run.mats.get(k, 0)) + int(loot.mats[k])
	var extras := []
	for id in loot.get("items", []):
		var iid := String(id)
		if owns_equip(run, iid):
			run.gold = int(run.gold) + sell_price(iid)
			extras.append("%s(중복→금화 +%d)" % [equip_name(iid), sell_price(iid)])
		else:
			(run.bag as Array).append(iid)
			extras.append(equip_name(iid))
	for sv in loot.get("services", []):
		run.services[String(sv)] = int(run.services.get(sv, 0)) + 1
		extras.append(String(PCatalog.services()[String(sv)].name))
	if loot.get("steer", null) != null:
		var g: Dictionary = run.growth
		if g.get("steer", null) != null:
			run.gold = int(run.gold) + 60
			extras.append("예약 있음 → 금화 +60")
		else:
			g.steer = { "kind": String(loot.steer), "regionId": String(sortie.regionId), "day": int(run.day), "fallbackGold": PPacing.gold_award(60), "from": "deep" }
			extras.append("다음 레벨업 예약(개조)")
	var mat_parts := []
	for k in loot.mats:
		mat_parts.append("%s %d" % [String(PCatalog.materials()[String(k)].name), int(loot.mats[k])])
	var txt := "%s 귀환: 금화 +%d" % [String(region(String(sortie.regionId)).name), int(loot.gold)]
	if mat_parts.size() > 0:
		txt += ", " + ", ".join(mat_parts)
	if extras.size() > 0:
		txt += ", " + ", ".join(extras)
	add_log(run, txt)

## 일반 출격 패배: 미정산 전리품 상실, 남은 하루 상실, 다음 날 정상 체력. 정산한 재산·성장은 보존
static func defeat(run: Dictionary, sortie: Dictionary) -> void:
	sortie.lost = true
	sortie.settled = true
	sortie.loot = { "gold": 0, "mats": {}, "chestGold": 0 }
	if PEndless.active(run): # 무한: 패배 = 종료(재도전 없음), 본편 완주 기록 유지
		PEndless.over(run, "lost")
		return
	add_log(run, "%s에서 패배: 미정산 전리품 상실, 남은 하루 상실" % String(region(String(sortie.regionId)).name))
	run.hours = 0
	run.hp = float(build(run).hp_max)
	run.lastDefeatDay = int(run.day)
	if String(run.phase) == "prep":
		end_day(run) # 구조: 하루 종료 → 다음 날(관문 날이면 관문)

# ---------- 거점 행동 ----------
static func has_service(run: Dictionary, id: String) -> bool:
	return int(run.get("services", {}).get(id, 0)) > 0

static func use_service(run: Dictionary, id: String) -> bool:
	if not has_service(run, id):
		push_error("서비스 없음: " + id)
		return false
	run.services[id] = int(run.services[id]) - 1
	add_log(run, "%s 사용" % String(PCatalog.services()[id].name))
	return true

## 체력이 가득해도 다음 시간대로 넘길 수 있다(별도 대기 버튼 없음)
static func can_rest(run: Dictionary) -> bool:
	return String(run.phase) == "prep" and (int(run.hours) >= int(C().REST_HOURS) or has_service(run, "free_rest"))

static func rest(run: Dictionary) -> bool:
	if not can_rest(run):
		push_error("휴식 불가")
		return false
	if has_service(run, "free_rest"):
		use_service(run, "free_rest")
	else:
		run.hours = int(run.hours) - int(C().REST_HOURS)
	run.hp = float(build(run).hp_max)
	# 지시 8: 선택해서 쉰 휴식과 나갈 곳이 없어서 쉰 휴식을 구분해 센다(통계 전용)
	var forced: bool = not any_departure(run)
	run.stats["rest_forced"] = int(run.stats.get("rest_forced", 0)) + (1 if forced else 0)
	run.stats["rest_chosen"] = int(run.stats.get("rest_chosen", 0)) + (0 if forced else 1)
	add_log(run, "휴식: 체력 회복 → %s%s" % [slot_name(run), " (나갈 수 있는 출격 없음)" if forced else ""])
	return true

static func end_day(run: Dictionary) -> bool:
	if String(run.phase) != "prep":
		push_error("보스 준비 중에는 하루를 넘길 수 없음")
		return false
	run.day = int(run.day) + 1
	run.hours = int(C().HOURS_PER_DAY)
	run.hp = float(build(run).hp_max)
	if not run.has("buffs") or run.buffs == null:
		run.buffs = {}
	add_log(run, "새로운 아침")
	if is_boss_day(run):
		run.phase = "boss_prep"
		add_log(run, "보스 관문: 준비 뒤 입장")
	places_for(run)
	PSortie.cards_for(run)
	refresh_stock(run)
	return true

## 하루가 끝나기 전 다음 날 미리보기: 장소 2곳과 핵심 위험(관문이면 보스)
static func preview_next_day(run: Dictionary) -> Dictionary:
	var d: int = int(run.day) + 1
	var nb := next_boss(run)
	if not nb.is_empty() and d >= int(nb.day) and not (run.bossesDone as Array).has(String(nb.id)):
		return { "day": d, "boss": String(nb.id) }
	var places := []
	for id in places_for(run, d):
		var rid := String(id)
		var elite := false
		var types := []
		for wave in day_waves(rid, d):
			for g in wave:
				if bool(PCatalog.enemy(String(g.type)).get("elite", false)):
					elite = true
				if not types.has(String(g.type)):
					types.append(String(g.type))
		places.append({ "id": rid, "name": String(region(rid).name), "elite": elite, "enemies": types.slice(0, 3) })
	return { "day": d, "places": places }

# ---------- 보스전 ----------
## 같은 회차·같은 단계 재도전 = 같은 시드·지형
static func boss_seed(run: Dictionary) -> int:
	return int(run.seed) * 997 + 7 + int(run.get("stage", 0)) * 31

static func can_start_boss(run: Dictionary) -> bool:
	return String(run.phase) == "boss_prep" or String(run.phase) == "cleared"

## 입장: 체력 완전 회복, 재도전 복구 스냅샷(run.bossEntry). 돌려주는 값 = 보스 출격 dict
static func start_boss(run: Dictionary) -> Dictionary:
	if not can_start_boss(run):
		push_error("보스 준비 상태가 아님")
		return {}
	run.hp = float(build(run).hp_max)
	run.bossEntry = { "growth": run.growth, "hp": run.hp, "stage": int(run.get("stage", 0)), "gold": int(run.gold), "services": run.services, "equipment": run.equipment, "bag": run.bag, "forge": int(run.forge) }.duplicate(true)
	var nb := next_boss(run)
	return { "regionId": "boss", "bossId": String(nb.id) if not nb.is_empty() else "boss", "stage": int(run.get("stage", 0)), "seed": boss_seed(run), "loot": { "gold": 0, "mats": {} }, "encounters": 0 }

## 패배: 입장 시 준비 상태로 복구(레벨·경험치·선택·금화 — 전투 중 건너뛰기 금화 반복 악용 방지)
static func boss_defeat(run: Dictionary) -> void:
	run.bossRetries = int(run.get("bossRetries", 0)) + 1
	if run.get("bossEntry", null) != null:
		var E: Dictionary = (run.bossEntry as Dictionary).duplicate(true)
		run.growth = E.growth
		if E.has("gold"): run.gold = int(E.gold)
		if E.has("services"): run.services = E.services
		if E.has("equipment"): run.equipment = E.equipment
		if E.has("bag"): run.bag = E.bag
		if E.has("forge"): run.forge = int(E.forge)
	run.hp = float(build(run).hp_max)
	add_log(run, "보스전 패배 (재도전 %d회, 성장은 입장 시점으로 복구)" % int(run.bossRetries))

## 승리(정확히 1회, PFlow.settle_boss_victory에서): 기록 → 다음 단계 해금 또는 완주. stats = st.stats(elapsed, special_uses, boss_damage)
static func boss_victory(run: Dictionary, stats: Dictionary) -> Dictionary:
	var b := build(run)
	var nb := next_boss(run)
	var boss_id := String(nb.id) if not nb.is_empty() else "boss"
	var cfg := PCatalog.boss_def(boss_id)
	var wnames := []
	for w in b.weapons:
		wnames.append(String(w.name))
	var rec := { "bossId": boss_id, "stage": int(run.get("stage", 0)), "time": round(float(stats.get("elapsed", 0.0)) * 10.0) / 10.0, "retries": int(run.get("bossRetries", 0)),
		"weapon": String(wnames[0]) if wnames.size() > 0 else "", "weapons": wnames, "forge": int(run.forge), "equipment": (run.equipment as Dictionary).duplicate(),
		"level": int(run.growth.level), "specialUses": int(stats.get("special_uses", 0)), "bossDamage": round(float(stats.get("boss_damage", 0.0))),
		"day": int(run.day), "seed": int(run.seed), "mode": String(run.mode) }
	if not (run.bossRecords as Dictionary).has(boss_id):
		run.bossRecords[boss_id] = rec # 보스별 처치 기록은 1회(재도전·재정산으로 갱신하지 않음)
	if boss_id == "boss" and run.get("bossClear", null) == null:
		run.bossClear = rec
	run.lastBossClear = rec
	var stage_before := world_stage(run)
	if not (run.bossesDone as Array).has(boss_id):
		(run.bossesDone as Array).append(boss_id)
	add_log(run, "%s 처치 (%s초)" % [String(cfg.name), str(rec.time)])
	if world_stage(run) != stage_before: # 세계 변화는 관문 완료에서 도출되므로 기록만 남긴다(전환은 정확히 1회)
		rec.worldStage = world_stage(run)
		rec.worldStageName = String(world_stage_def(run).name)
		add_log(run, "세계 변화: %s" % rec.worldStageName)
	var last: bool = int(run.get("stage", 0)) >= stage_count(run) - 1
	if last: # 마지막 보스: 회차 종료, 다음 보스 없음, 추가 성장 없음
		run.phase = "cleared"
		run.ended = true
		run.stage = stage_count(run)
	else: # 다음 단계 해금: 그날의 5시간 시작, 희귀 보상 3택은 1회 보류 등록(저장됨)
		if bool(nb.get("rare", false)):
			run.growth.pendingBossPick = { "bossId": boss_id, "stage": int(run.get("stage", 0)), "key": "%d:%d" % [int(run.seed), int(run.get("stage", 0))] }
		run.stage = int(run.get("stage", 0)) + 1
		run.phase = "prep"
		run.hours = int(C().HOURS_PER_DAY)
		run.hp = float(b.hp_max)
		run.bossRetries = 0
		run.bossEntry = null
		add_log(run, "%d단계 해금: 오늘 %d시간 시작" % [int(run.stage) + 1, int(C().HOURS_PER_DAY)])
		PSortie.cards_for(run)
	return rec

# ---------- 상점(하루 시드 재고)·장비·대장간 ----------
static func owns_equip(run: Dictionary, id: String) -> bool:
	if (run.bag as Array).has(id):
		return true
	for slot in run.equipment:
		if run.equipment[slot] != null and String(run.equipment[slot]) == id:
			return true
	return false

static func stock_seed(run: Dictionary, day: int = 0) -> int:
	var d: int = day if day > 0 else int(run.day)
	return (int(run.seed) * 17 + d * 401 + 9) & 0xFFFFFFFF

## 오늘의 재고: 장비 2(미보유) + 자동기술 또는 E 1. 다시 열거나 불러와도 같다(저장). 방문 상인은 예정된 날 점심부터.
## 재고 후보는 해금 스냅샷(run.unlocks)을 따르고 제작 전용 장비는 넣지 않는다
static func refresh_stock(run: Dictionary) -> Dictionary:
	var rng := PRng.new(stock_seed(run))
	var g: Dictionary = run.growth
	var EQ := PCatalog.equipment()
	var pool := []
	for id in EQ:
		if not owns_equip(run, String(id)) and PProfile.run_unlock_ok(run, "equipment", String(id)):
			pool.append(String(id))
	var eq := []
	while eq.size() < int(SH().stock.equipment) and pool.size() > 0:
		var idx := rng.int_range(0, pool.size() - 1)
		eq.append(pool[idx])
		pool.remove_at(idx)
	var skill = null
	var W_ := PCatalog.weapons()
	var wpool := []
	for id in W_:
		if bool(W_[id].impl) and PGrowth.weapon_of(g, String(id)).is_empty() and PProfile.run_unlock_ok(run, "weapons", String(id)):
			wpool.append(String(id))
	var es := []
	for id in PCatalog.e_skills():
		if bool(PCatalog.skills()[id].impl) and PProfile.run_unlock_ok(run, "e_skills", String(id)):
			es.append(String(id))
	if (g.weapons as Array).size() < int(PCatalog.growth().SLOTS.weapons) and wpool.size() > 0:
		skill = { "kind": "weapon", "id": wpool[rng.int_range(0, wpool.size() - 1)], "price": int(SH().newSkill) }
	elif g.skills.get("e", null) == null and es.size() > 0:
		skill = { "kind": "e", "id": es[rng.int_range(0, es.size() - 1)], "price": int(SH().newE) }
	run.stock = { "day": int(run.day), "equipment": eq, "skill": skill, "sold": [] }
	var MV: Dictionary = W().merchant_visits
	var visit := false
	for d in merchant_days(run):
		if int(d) == int(run.day):
			visit = true
	if visit:
		var p2 := []
		for id in EQ:
			if not owns_equip(run, String(id)) and not eq.has(String(id)) and PProfile.run_unlock_ok(run, "equipment", String(id)):
				p2.append(String(id))
		run.merchant = { "day": int(run.day), "fromSlot": int(MV.slot), "equipment": (p2[rng.int_range(0, p2.size() - 1)] if p2.size() > 0 else null), "service": "free_rest", "servicePrice": 40, "sold": [] }
	else:
		run.merchant = null
	return run.stock

static func stock(run: Dictionary) -> Dictionary:
	if run.get("stock", null) == null or int(run.stock.day) != int(run.day):
		refresh_stock(run)
	return run.stock

static func merchant_open(run: Dictionary) -> bool:
	var m = run.get("merchant", null)
	return m != null and int(m.day) == int(run.day) and slot_index(run) >= int(m.fromSlot)

static func equip_price(id: String) -> int: return int(SH().price[String(PCatalog.equipment_def(id).slot)])
## 판매가: 같은 부위 기존 장비 판매가(35/30/30). 제작 전용도 동일(재료→완성품→판매 차익 방지, 시험값)
static func sell_price(id: String) -> int: return int(SH().sellPrice[String(PCatalog.equipment_def(id).slot)])
static func equip_name(id: String) -> String: return String(PCatalog.equipment_def(id).get("name", id))

static func equip_price_for(run: Dictionary, id: String, from: String = "stock") -> int:
	var p := equip_price(id)
	if from == "merchant":
		p = int(round(float(p) * (1.0 - float(SH().merchantDiscount))))
	if has_service(run, "shop_discount"):
		p = int(round(float(p) * (1.0 - float(PCatalog.services().shop_discount.rate))))
	return p

static func can_buy_equipment(run: Dictionary, id: String, from: String = "stock") -> bool:
	if not PCatalog.equipment().has(id):
		return false
	var listed := false
	var sold: Array = []
	if from == "merchant":
		var m = run.get("merchant", null)
		if m == null:
			return false
		listed = merchant_open(run) and m.equipment != null and String(m.equipment) == id
		sold = m.sold
	else:
		var st := stock(run)
		listed = (st.equipment as Array).has(id)
		sold = st.sold
	return listed and not sold.has(id) and not owns_equip(run, id) and int(run.gold) >= equip_price_for(run, id, from)

## 구매: 즉시 장착(equip=true) 또는 보관. 같은 장비 중복 구매 불가
static func buy_equipment(run: Dictionary, id: String, equip: bool, from: String = "stock") -> bool:
	if not can_buy_equipment(run, id, from):
		push_error("구매 불가: " + id)
		return false
	run.gold = int(run.gold) - equip_price_for(run, id, from)
	if has_service(run, "shop_discount"):
		use_service(run, "shop_discount")
	var target: Dictionary = run.merchant if from == "merchant" else stock(run)
	(target.sold as Array).append(id)
	(run.bag as Array).append(id)
	if equip:
		equip_item(run, id)
	add_log(run, "%s 구매%s" % [equip_name(id), "·장착" if equip else "·보관"])
	return true

## 방문 상인 서비스(무료 휴식권) 구매 — HTML main.js 'buy-merchant-service'
static func can_buy_merchant_service(run: Dictionary) -> bool:
	var m = run.get("merchant", null)
	return m != null and merchant_open(run) and not (m.sold as Array).has("service") and int(run.gold) >= int(m.servicePrice)

static func buy_merchant_service(run: Dictionary) -> bool:
	if not can_buy_merchant_service(run):
		push_error("구매 불가")
		return false
	var m: Dictionary = run.merchant
	run.gold = int(run.gold) - int(m.servicePrice)
	(m.sold as Array).append("service")
	run.services[String(m.service)] = int(run.services.get(m.service, 0)) + 1
	add_log(run, "방문 상인: %s 구매 (-%d)" % [String(PCatalog.services()[String(m.service)].name), int(m.servicePrice)])
	return true

static func equip_item(run: Dictionary, id: String) -> bool:
	var d: Dictionary = PCatalog.equipment_def(id)
	if d.is_empty() or not (run.bag as Array).has(id):
		push_error("가방에 없음: " + id)
		return false
	var slot := String(d.slot)
	var cur = run.equipment[slot]
	(run.bag as Array).erase(id)
	if cur != null:
		(run.bag as Array).append(String(cur))
	run.equipment[slot] = id
	clamp_hp(run)
	return true

static func unequip_item(run: Dictionary, slot: String) -> void:
	var cur = run.equipment.get(slot, null)
	if cur == null:
		return
	run.equipment[slot] = null
	(run.bag as Array).append(String(cur))
	clamp_hp(run)

## 최대 체력이 줄면 현재 체력도 줄어든다. 늘어도 회복하지 않는다(탈착 회복 악용 없음)
static func clamp_hp(run: Dictionary) -> void:
	run.hp = minf(float(run.hp), float(build(run).hp_max))

static func sell_equipment(run: Dictionary, id: String) -> bool:
	if not owns_equip(run, id):
		push_error("미보유: " + id)
		return false
	for s in W().equip_slots:
		if run.equipment[s] != null and String(run.equipment[s]) == id:
			run.equipment[s] = null
			clamp_hp(run)
	(run.bag as Array).erase(id)
	run.gold = int(run.gold) + sell_price(id)
	add_log(run, "%s 판매 +%d" % [equip_name(id), sell_price(id)])
	return true

## 빈 슬롯 획득: 새 자동기술 / 새 E (Lv1, 개조·변형 없음)
static func can_buy_skill(run: Dictionary) -> bool:
	var st := stock(run)
	var g: Dictionary = run.growth
	if st.get("skill", null) == null or (st.sold as Array).has("skill"):
		return false
	var sk: Dictionary = st.skill
	if String(sk.kind) == "weapon":
		return (g.weapons as Array).size() < int(PCatalog.growth().SLOTS.weapons) and PGrowth.weapon_of(g, String(sk.id)).is_empty() and int(run.gold) >= int(sk.price)
	return g.skills.get("e", null) == null and int(run.gold) >= int(sk.price)

static func buy_skill(run: Dictionary) -> bool:
	if not can_buy_skill(run):
		push_error("구매 불가")
		return false
	var st := stock(run)
	var g: Dictionary = run.growth
	var sk: Dictionary = st.skill
	run.gold = int(run.gold) - int(sk.price)
	(st.sold as Array).append("skill")
	var nm := ""
	if String(sk.kind) == "weapon":
		(g.weapons as Array).append({ "id": String(sk.id), "level": 1, "mods": [] })
		nm = String(PCatalog.weapons()[String(sk.id)].name)
	else:
		g.skills.e = { "id": String(sk.id), "level": 1, "variant": null }
		nm = String(PCatalog.skills()[String(sk.id)].name)
	add_log(run, "%s 획득 (-%d)" % [nm, int(sk.price)])
	return true

## 보유 자동기술/E 교체 견적: 120 + (레벨-1)×40 + 개조·변형 수×80. 없으면 {}
static func swap_quote(run: Dictionary, slot: String, index: int = 0) -> Dictionary:
	var g: Dictionary = run.growth
	var cur = null
	if slot == "e":
		cur = g.skills.get("e", null)
	elif index >= 0 and index < (g.weapons as Array).size():
		cur = g.weapons[index]
	if cur == null:
		return {}
	var mods: int = (1 if cur.get("variant", null) != null else 0) if slot == "e" else (cur.mods as Array).size()
	var SW: Dictionary = SH().swap
	var price := int(SW.base) + (int(cur.level) - 1) * int(SW.perLevel) + mods * int(SW.perMod)
	var options := []
	if slot == "e":
		for id in PCatalog.e_skills():
			if bool(PCatalog.skills()[id].impl) and String(id) != String(cur.id) and PProfile.run_unlock_ok(run, "e_skills", String(id)):
				options.append(String(id))
	else:
		var W_ := PCatalog.weapons()
		for id in W_:
			if bool(W_[id].impl) and PGrowth.weapon_of(g, String(id)).is_empty() and PProfile.run_unlock_ok(run, "weapons", String(id)):
				options.append(String(id))
	return { "slot": slot, "index": index, "current": cur, "level": int(cur.level), "modCount": mods, "price": price, "options": options, "affordable": int(run.gold) >= price }

## 교체 확정(마지막 단계에서만 차감·교체). 새 개조/변형은 새 기술 목록에서 modCount만큼. 실패 시 -1
static func apply_swap(run: Dictionary, slot: String, index: int, new_id: String, new_mods: Array = []) -> int:
	var q := swap_quote(run, slot, index)
	if q.is_empty() or not (q.options as Array).has(new_id):
		push_error("교체 불가")
		return -1
	if int(run.gold) < int(q.price):
		push_error("금화 부족")
		return -1
	var nm: Array = new_mods.slice(0, int(q.modCount))
	var g: Dictionary = run.growth
	var label := ""
	if slot == "e":
		var d: Dictionary = PCatalog.skills()[new_id]
		var v = nm[0] if nm.size() > 0 else null
		if v != null and not (d.has("variants") and (d.variants as Dictionary).has(String(v)) and bool(d.variants[String(v)].impl) and PProfile.run_unlock_ok(run, "e_variants", new_id, String(v))):
			push_error("변형 불가")
			return -1
		g.skills.e = { "id": new_id, "level": int(q.level), "variant": (String(v) if v != null else null) }
		label = String(d.name)
	else:
		var d: Dictionary = PCatalog.weapons()[new_id]
		var seen := {}
		for m in nm:
			if not ((d.mods as Dictionary).has(String(m)) and bool(d.mods[String(m)].impl) and PProfile.run_unlock_ok(run, "mods", new_id, String(m))):
				push_error("개조 불가")
				return -1
			if seen.has(String(m)):
				push_error("개조 중복")
				return -1
			seen[String(m)] = true
		var mods_out := []
		for m in nm:
			mods_out.append(String(m))
		g.weapons[index] = { "id": new_id, "level": int(q.level), "mods": mods_out }
		label = String(d.name)
	run.gold = int(run.gold) - int(q.price)
	g.picks.swap = int(g.picks.get("swap", 0)) + 1
	add_log(run, "%s 교체 → %s (-%d)" % ["E" if slot == "e" else "자동기술", label, int(q.price)])
	return int(q.price)

static func _applies_to_any(d: Dictionary, weapon_ids: Array) -> bool:
	if not d.has("applies"):
		return true
	for id in weapon_ids:
		var wd := PCatalog.weapon(String(id))
		if String(d.applies) == "width" and bool(wd.get("width", false)):
			return true
		if String(d.applies) == "reach" and bool(wd.get("reach", false)):
			return true
	return false

## 교체로 적용 대상이 사라지는 공용 증강 이름 목록(확정 전 표시용)
static func swap_warnings(run: Dictionary, slot: String, index: int, new_id: String) -> Array:
	if slot == "e":
		return []
	var g: Dictionary = run.growth
	var after := []
	for i in (g.weapons as Array).size():
		after.append(new_id if i == index else String(g.weapons[i].id))
	var out := []
	var CM := PCatalog.commons()
	for id in g.commons:
		var d: Dictionary = CM[String(id)]
		if int(g.commons[id]) > 0 and d.has("applies") and not _applies_to_any(d, after):
			out.append(String(d.name))
	return out

## 대장간 다음 강화 {lv, cost, afterBoss, open, affordable}. 최대면 {}
static func forge_next(run: Dictionary) -> Dictionary:
	var lv: int = int(run.get("forge", 0))
	var F: Array = SH().forge
	if lv >= F.size():
		return {}
	var f: Dictionary = F[lv]
	return { "lv": int(f.lv), "cost": int(f.cost), "afterBoss": int(f.afterBoss), "open": (run.get("bossesDone", []) as Array).size() >= int(f.afterBoss), "affordable": int(run.gold) >= int(f.cost) }

static func forge_upgrade(run: Dictionary) -> bool:
	var F := forge_next(run)
	if F.is_empty() or not bool(F.open) or not bool(F.affordable):
		push_error("강화 불가")
		return false
	run.gold = int(run.gold) - int(F.cost)
	run.forge = int(F.lv)
	add_log(run, "공용 공격 강화 %d단계 (-%d)" % [int(F.lv), int(F.cost)])
	return true

static func mod_change_cost(run: Dictionary) -> Dictionary:
	return { "voucher": true, "gold": 0 } if has_service(run, "mod_swap") else { "voucher": false, "gold": int(SH().modChange) }
static func variant_change_cost(run: Dictionary) -> Dictionary:
	return { "voucher": true, "gold": 0 } if has_service(run, "mod_swap") else { "voucher": false, "gold": int(SH().variantChange) }

## 재료 판매
static func sell(run: Dictionary, mat_id: String, n: int = 1) -> bool:
	if int(run.mats.get(mat_id, 0)) < n:
		push_error("재료 부족")
		return false
	run.mats[mat_id] = int(run.mats[mat_id]) - n
	run.gold = int(run.gold) + int(PCatalog.materials()[mat_id].sell) * n
	return true

## 승리 정산 시 장비 효과(원정대의 갑옷·재생의 여행복 winHeal): 승리마다 1회(C7). 회복량을 돌려준다.
## 특성 '회복 준비'(heal_mult)는 회복량에만 적용. 재생의 여행복(overflowShield)은 최대 체력을 넘는 초과분을 run.storedShield에 저장(상한, 다음 전투 시작 시 소비)
static func on_victory_heal(run: Dictionary) -> float:
	var b := build(run)
	if (b.equip as Dictionary).has("winHeal"):
		var before: float = float(run.hp)
		var amount: float = float(b.equip.winHeal) * float(b.get("heal_mult", 1.0))
		run.hp = minf(float(b.hp_max), float(run.hp) + amount)
		var healed: float = float(run.hp) - before
		if (b.equip as Dictionary).has("overflowShield") and amount - healed > 0.0:
			run.storedShield = minf(float(b.equip.overflowShield.max), float(run.get("storedShield", 0.0)) + (amount - healed))
		return healed
	return 0.0

# ---------- 제작(대장간, 시험값 meta.json crafted_equipment) ----------
## 제작 후보(해금된 제작법만): [{ id, def, recipe, fee, affordable, ingredients[{kind:"equipment"|"mat", id, name, n, have, where}], missing[], can, owned, preview{before,after} }]
## 재료 장비는 장착 중(where "equipped")이거나 가방(where "bag")의 인스턴스, 재료는 귀환 정산된 run.mats만. 미리보기는 복제 회차에 실제 제작·장착해 PBuild.derive로 계산한다
static func craft_options(run: Dictionary) -> Array:
	var out := []
	var CE := PCatalog.crafted_equipment()
	for id in CE:
		var cid := String(id)
		if not PProfile.run_unlock_ok(run, "recipes", cid):
			continue
		out.append(craft_option(run, cid))
	return out

static func craft_option(run: Dictionary, id: String, with_preview: bool = true) -> Dictionary:
	var d: Dictionary = PCatalog.crafted_equipment()[id]
	var rc: Dictionary = d.recipe
	var ings := []
	var missing := []
	for eid in rc.get("equipment", []):
		var e := String(eid)
		var where := ""
		if (run.bag as Array).has(e):
			where = "bag"
		else:
			for slot in run.equipment:
				if run.equipment[slot] != null and String(run.equipment[slot]) == e:
					where = "equipped"
		var nm := equip_name(e)
		ings.append({ "kind": "equipment", "id": e, "name": nm, "n": 1, "have": 1 if where != "" else 0, "where": where })
		if where == "":
			missing.append(nm)
	var M := PCatalog.materials()
	for mid in rc.get("mats", {}):
		var m := String(mid)
		var n := int(rc.mats[mid])
		var have := int(run.mats.get(m, 0))
		ings.append({ "kind": "mat", "id": m, "name": String(M[m].name), "n": n, "have": have, "where": "" })
		if have < n:
			missing.append("%s %d/%d" % [String(M[m].name), have, n])
	var fee := int(rc.get("fee", 0))
	var affordable: bool = int(run.gold) >= fee
	if not affordable:
		missing.append("금화 %d/%d" % [int(run.gold), fee])
	var owned := owns_equip(run, id)
	if owned:
		missing.append("이미 보유")
	var opt := { "id": id, "def": d, "recipe": rc, "fee": fee, "affordable": affordable, "ingredients": ings, "missing": missing, "can": missing.is_empty(), "owned": owned, "preview": {} }
	if bool(opt.can) and with_preview:
		var dup: Dictionary = run.duplicate(true)
		var before := PBuild.derive(dup)
		craft(dup, id, true, true)
		opt.preview = { "before": before, "after": PBuild.derive(dup) }
	return opt

static func can_craft(run: Dictionary, id: String, use_equipped: bool = true) -> bool:
	if not PCatalog.crafted_equipment().has(id) or not PProfile.run_unlock_ok(run, "recipes", id):
		return false
	var o := craft_option(run, id, false)
	if not bool(o.can):
		return false
	if not use_equipped:
		for ing in o.ingredients:
			if String(ing.kind) == "equipment" and String(ing.where) == "equipped":
				return false
	return true

## 제작 확정(원자적: 검증 → 소비 → 생성 → 가방/장착). 저장은 호출자가 1회. use_equipped=false면 장착 중인 재료 장비는 쓰지 않는다(실패).
## 회차 강화(forge)는 장비 인스턴스와 무관하므로 그대로. 분해·환급 없음. 실패 시 아무것도 바꾸지 않는다
static func craft(run: Dictionary, id: String, use_equipped: bool = true, equip_after: bool = false) -> bool:
	if not can_craft(run, id, use_equipped):
		push_error("제작 불가: " + id)
		return false
	var rc := PCatalog.recipe(id)
	for eid in rc.get("equipment", []):
		var e := String(eid)
		if (run.bag as Array).has(e):
			(run.bag as Array).erase(e)
		else:
			for slot in run.equipment:
				if run.equipment[slot] != null and String(run.equipment[slot]) == e:
					run.equipment[slot] = null
	for mid in rc.get("mats", {}):
		run.mats[String(mid)] = int(run.mats.get(String(mid), 0)) - int(rc.mats[mid])
	run.gold = int(run.gold) - int(rc.get("fee", 0))
	(run.bag as Array).append(id)
	if not run.has("crafted"):
		run.crafted = []
	(run.crafted as Array).append(id)
	clamp_hp(run)
	if equip_after:
		equip_item(run, id)
	add_log(run, "%s 제작 (-%d금)%s" % [equip_name(id), int(rc.get("fee", 0)), "·장착" if equip_after else "·보관"])
	return true
