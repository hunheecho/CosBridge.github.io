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
		"equipment": { "weapon": null, "armor": null, "shield": null }, "bag": [], "forge": 0, "forgeBySkill": {},
		"equipPlus": {}, "equipSeq": 0, # 장비 개체별 강화 단계(개체 id → 0~2)와 개체 일련번호(회차 안에서만 유일). §4
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
		"consumables": [], "prepItem": null, "prepUsed": null, "potionBuy": { "day": 1, "count": 0 }, # 출격 준비물 가방·장착 1개·이번 전투 소모분·하루 회복약 구매 수(PConsumables)
		"paidFor": {}, "death": {}, # 장비 개체별 실제 지불 금액(판매가 기준) · 사망 정산 기록(중복 방지 키 포함)
		"revivePending": { "count": 0 }, # 부활로 들어가는 관문 재입장 표식(1 = 다음 입장 한 번은 자동 완전 회복을 건너뛴다). revive_pending 주석 참고
		"testRetry": bool(opts.get("test_retry", OS.get_environment("PROPHECY_TEST_RETRY") != "")), # 사람 플레이가 아닌 재시도 경로(아래 retry_mode 주석). opts가 있으면 opts가 이긴다
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

## 전투에 들어가는 최종 빌드. 장비·성장 계산은 PBuild가 전부 하고, 그 **결과 위에** 이번 출격 준비물 1개를 얹는다.
## 준비물을 PBuild 안에 넣지 않는 이유: 장비 효과 합산 규칙(중복 금지·월광 갑옷 재생 상한 등)을 건드리지 않기 위해서다.
## PBuild.derive를 직접 부르는 곳(화면 미리보기)은 준비물이 빠진 기본 빌드를 본다 — 준비물은 전투에만 붙는다는 뜻이다.
static func build(run: Dictionary) -> Dictionary:
	return PConsumables.apply_to_build(run, PBuild.derive(run))

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

## 이 편성이 실제로 내보낼 정예 종류 목록(길이 = tpl.elites). 배치표·이유는 data/elites.json, 붙는 자리는 data/themes.json.
## 템플릿이 읽는 필드(전부 선택 사항이며, 없으면 기존 늑대 우두머리라 회귀가 없다):
##   elite_type     — 기본 정예 1종
##   elite_type_p2  — 비용 2칸(큰 보상) 장소와 더 깊이 탐험에서 쓰는 **더 강한** 정예. 없으면 elite_type
##   elite_types    — 정예 2마리 이상일 때의 종류 조합. 조합은 이미 최대 위험이라 장소로 더 올리지 않는다
## 어느 경우에도 **마리 수는 바꾸지 않는다**(총 등장 수·경험치 예산 불변). 바뀌는 것은 종류뿐이다.
static func elite_types_for(tpl: Dictionary, place_key: String, deep: bool = false) -> Array:
	var n := int(tpl.get("elites", 0))
	if n <= 0:
		return []
	var out := []
	if tpl.has("elite_types"):
		for t in (tpl.elite_types as Array):
			out.append(String(t))
	else:
		var big := String(tpl.get("elite_type_p2", ""))
		var one := String(tpl.get("elite_type", "wolf_alpha"))
		out.append(big if (big != "" and (deep or place_key == "p2")) else one)
	while out.size() < n: # 모자라면 마지막 종류로 채우고, 넘치면 자른다
		out.append(String(out[out.size() - 1]))
	out.resize(n)
	return out

## 정예 목록을 웨이브 항목으로. 마리당 경험치 기준(ref)은 1.0이므로 합계는 항상 마리 수와 같다.
##
## **특수 정예(7종)는 언제나 결투 표시(duel)를 달고 나온다**(2026-09-09 사용자 확정 규칙, §13).
## 예전에는 여기서 만든 항목이 표시 없이 일반 웨이브에 들어가 일반 적과 **동시에** 살아 있었다
## (사용자 재현: 사슬 집행자와 일반 도마뱀이 같은 화면에). 결투는 "일반 적과 예정된 일반 증원을
## 모두 정리한 뒤"에 시작해야 하므로, 배정 경로가 무엇이든 여기서 표시를 붙인다.
## 결투는 **1대1**이라 특수 정예는 같은 종류라도 묶지 않고 한 마리씩 따로 낸다(순서 = 표 순서).
## 일반 정예·옛 정예(늑대 우두머리)는 규칙상 일반 전투에 함께 나와도 되므로 예전 그대로 묶는다.
## 종류·마리 수·경험치 기준(ref)은 어느 쪽도 바뀌지 않는다 — 총 등장 수·예산 불변.
static func _elite_entries(types: Array) -> Array:
	var order := []
	var cnt := {}
	var out := []
	for t in types:
		var tp := String(t)
		if is_special_elite(tp): # 결투 상대: 한 마리씩 따로(1대1), 순서 보존
			out.append({ "type": tp, "n": 1, "ref": 1.0, "duel": true })
			continue
		if not cnt.has(tp):
			cnt[tp] = 0
			order.append(tp)
		cnt[tp] = int(cnt[tp]) + 1
	for tp in order:
		out.append({ "type": String(tp), "n": int(cnt[tp]), "ref": float(cnt[tp]) })
	return out

## 템플릿 → 웨이브(최종 수 명시 + 경험치 기준 ref). 장소 규모(p1/p2)로 정수 배정, 나머지는 첫 주력에. 정예는 마지막.
## 총 등장 수는 날짜 예산표(PPacing.day_total, 사용자 결정 25 → 75)가 정하고 템플릿의 sizes.total은 표가 없을 때의 예비값이다.
## 밀도 배율(×5)을 여기에 다시 곱하지 않는다(테마 템플릿은 ref가 있어 PFormation이 배율을 적용하지 않는다).
## 경험치 예산(xp_ref)은 개체 수와 무관하게 고정이므로 수가 늘어도 전투당 경험치는 늘지 않는다.
static func template_waves(tpl: Dictionary, place_key: String, day: int = 0, place_cost: int = 1, deep: bool = false, duel_type: String = "") -> Array:
	var sz: Dictionary = tpl.sizes[place_key]
	var total: int = int(sz.total)
	if day > 0 and not bool(tpl.get("fixed_total", false)):
		var budget := PPacing.day_total(day, place_cost)
		if budget > 0:
			total = budget
	var xp_ref: float = float(sz.xp_ref)
	var wave := []
	var assigned := 0
	var comp: Array = comp_effective(tpl) # 미구현 종류는 빼고 비중을 나머지에 나눠 준다(총 수·예산 불변)
	for c in comp:
		var n: int = int(round(total * float(c.share)))
		wave.append({ "type": String(c.type), "n": n, "ref": xp_ref * float(c.share) })
		assigned += n
	if not wave.is_empty():
		wave[0].n = int(wave[0].n) + (total - assigned)
	_pin_budget(wave, tpl, place_key) # 구성이 바뀌어도 전투 경험치 예산은 개편 전 값 그대로
	var planned := elite_types_for(tpl, place_key, deep)
	var has_special := false
	for t in planned:
		if is_special_elite(String(t)):
			has_special = true
	_swap_one(wave, common_elite_id(tpl), "common_elite") # 일반 정예 1마리(있을 때만): 일반 적 1마리를 대신한다
	# **1대1**(§13): 편성이 이미 특수 정예를 내보내면 카드가 붙인 결투를 겹치지 않는다.
	# 배정 단계(assign_duel·duel_type_deep)에서도 막지만, 옛 저장·도구·검증 메뉴처럼
	# 다른 곳에서 온 duel_type 도 여기서 걸러야 "어떤 경로로 배정돼도" 규칙이 깨지지 않는다.
	# 붙이지 않아도 총 등장 수·예산은 그대로다(결투 상대는 일반 적 1마리를 대신하는 것이므로 그 적이 남는다).
	if not has_special:
		_swap_one(wave, duel_type, "duel")                # 카드가 붙인 결투 상대 1마리: 일반 적 1마리를 대신한다
	for g in _elite_entries(planned): # 정예는 마지막. 종류만 템플릿이 정하고 마리 수는 elites 그대로다
		wave.append(g)                 # 특수 정예면 _elite_entries 가 이미 결투 표시를 달았다
	return [wave]

## **전투 경험치 예산 고정**(총 등장 수·보상 예산 불변 규칙).
##
## 예산은 종류별 단위값(growth.XP_VALUE) × 경험치 기준(ref)의 합이라, 편성 **구성**이 바뀌면
## 같은 xp_ref 라도 실제 예산이 달라진다. 그래서 각 편성이 개편 **전에** 가지고 있던 예산을
## data/themes.json 의 xp_units 에 적어 두고, 여기서 ref 전체를 그 값에 맞춰 되돌린다.
## 미구현 종류를 건너뛰어 비중이 바뀌었을 때도 같은 값이 나온다.
static func _pin_budget(wave: Array, tpl: Dictionary, place_key: String) -> void:
	var target: float = float((tpl.get("xp_units", {}) as Dictionary).get(place_key, 0.0))
	if target <= 0.0 or wave.is_empty():
		return
	var XPV: Dictionary = PCatalog.growth().XP_VALUE
	var cur := 0.0
	for g in wave:
		cur += float(XPV.get(String(g.type), 5.0)) * float(g.get("ref", float(g.n)))
	if cur <= 0.0:
		return
	var k: float = target / cur
	for g in wave:
		g.ref = float(g.get("ref", float(g.n))) * k

## 이 종류가 지금 카탈로그에 있는가(미구현 예정 종류는 아직 없다).
## PCatalog.enemy()는 없는 종류에 오류를 찍으므로 여기서는 사전을 직접 본다(예정 종류는 오류가 아니다)
static func enemy_ready(type: String) -> bool:
	return type != "" and PCatalog.enemies().has(type)

## 아직 만들어지지 않은 예정 종류인가(data/themes.json planned_types). 보고·검사용
static func planned_type(type: String) -> bool:
	return (themes_root().get("planned_types", {}).get("types", []) as Array).has(type)

## **특수 정예**(결투 상대)인가. data/elites.json 의 7종만 참이다.
## 늑대 우두머리(wolf_alpha)와 `<종류>_elite`(일반 정예)는 거짓이다 — 그 둘은 일반 전투에 함께 나와도 된다.
## 이 판정이 "일반 등장 목록 / 결투"를 가르는 **하나의 기준**이다(§13 통합 규칙).
static func is_special_elite(type: String) -> bool:
	return type != "" and PCatalog.elites().has(type)

## **일반 정예**인가(특수 정예와 구분). 특수 정예는 data/elites.json 에 있는 7종이고,
## 늑대 우두머리(wolf_alpha)는 옛 정예다. 그 밖에 elite 로 표시된 종류가 일반 몬스터의 정예판이다.
## 일반 정예는 특수 정예 예고·추가 금화·결투의 대상이 아니다(보상 예산이 늘지 않는다).
static func is_common_elite(type: String) -> bool:
	if not enemy_ready(type) or not bool(PCatalog.enemies()[type].get("elite", false)):
		return false
	return not PCatalog.elites().has(type) and type != "wolf_alpha"

## 미구현 예정 종류(data/themes.json planned_types)를 뺀 편성 구성.
## 빠진 비중은 남은 종류에 **비례 배분**하므로 총 등장 수·경험치 예산이 달라지지 않는다.
## 종류가 생기면 이 함수가 그대로 통과시킨다(데이터를 다시 고칠 필요 없음).
static func comp_effective(tpl: Dictionary) -> Array:
	var keep := 0.0
	var drop := 0.0
	for c in (tpl.comp as Array):
		if enemy_ready(String(c.type)):
			keep += float(c.share)
		else:
			drop += float(c.share)
	if drop <= 0.0:
		return tpl.comp
	if keep <= 0.0: # 전부 미구현이면 첫 종류만 남겨 빈 편성을 만들지 않는다(있을 수 없는 경우의 방어)
		return [{ "type": String((tpl.comp as Array)[0].type), "share": 1.0 }]
	var out := []
	for c in (tpl.comp as Array):
		if not enemy_ready(String(c.type)):
			continue
		out.append({ "type": String(c.type), "share": float(c.share) * (1.0 + drop / keep), "role": String(c.get("role", "")) })
	return out

## 일반 정예(common_elite)의 실제 id. `<종류>_elite` 가 카탈로그에 있고 경험치 단위값도 정의돼 있을 때만 쓴다.
## 없으면 ""(그 자리는 그냥 일반 개체로 남는다). **정예가 없다고 늑대 우두머리로 메우지 않는다.**
static func common_elite_id(tpl: Dictionary) -> String:
	var ce: Dictionary = tpl.get("common_elite", {})
	if ce.is_empty():
		return ""
	var id := String(ce.get("type", "")) + "_elite"
	if not enemy_ready(id):
		return ""
	return id if (PCatalog.growth().XP_VALUE as Dictionary).has(id) else ""

## 웨이브에서 **일반 적 한 마리를 빼고** 그 자리에 다른 종류 한 마리를 넣는다.
## 총 등장 수는 그대로이고, 경험치 기준(ref)은 budget_from 으로 원래 종류의 단위값을 따라간다
## (PFormation.from_waves 가 단위값 비율로 환산한다) — 종류를 바꿔도 전투 경험치 예산이 늘지 않는다.
static func _swap_one(wave: Array, type: String, flag: String) -> void:
	if type == "":
		return
	var bi := -1
	for i in wave.size():
		var g: Dictionary = wave[i]
		if int(g.n) >= 2 and not bool(PCatalog.enemy(String(g.type)).get("elite", false)) and (bi < 0 or int(g.n) > int(wave[bi].n)):
			bi = i
	if bi < 0:
		return
	var base: Dictionary = wave[bi]
	var slice: float = float(base.get("ref", float(base.n))) / float(base.n)
	base.n = int(base.n) - 1
	base.ref = float(base.get("ref", 0.0)) - slice
	var e := { "type": type, "n": 1, "ref": slice, "budget_from": String(base.type) }
	e[flag] = true
	wave.append(e)

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
	return { "alive_cap": cap, "squad_mix": true, "squad": tpl.get("squad", {}), "kind": String(tpl.get("kind", "")), "tail_boost": not bool(tpl.get("fixed_total", false)), "group": int(tpl.get("group", 3)), "interval": float(tpl.get("interval", 1.0)), "type_alive_cap": PPacing.type_alive_cap(tpl.get("type_caps", {}), cap), "multiplier": 1.0, "multiplier_by_type": {}, "set_name": "template" }

# ---------- 특수 정예 결투(할 일 4·5) ----------
## data/themes.json 의 뿌리 블록(duel·planned_types·squad_rule)을 읽는다.
## PCatalog 에 이 블록의 접근자가 아직 없어(다른 담당 파일) 캐시된 로더를 직접 쓴다 — 필요한 훅으로 보고했다.
static func themes_root() -> Dictionary:
	return PCatalog._load("themes")

static func duel_cfg() -> Dictionary:
	return themes_root().get("duel", {})

static func duel_enabled() -> bool:
	return bool(duel_cfg().get("enabled", false))

## 이 테마의 특수 정예 후보(사용자 배정). 카탈로그에 없는 id 는 조용히 뺀다
static func duel_types_for(theme_id: String) -> Array:
	var out := []
	for t in (PCatalog.theme(theme_id).get("special_elites", []) as Array):
		if enemy_ready(String(t)):
			out.append(String(t))
	return out

## 이 편성이 **카드 결투와 상관없이** 이미 내보내는 특수 정예 종류.
## PRun.encounter_waves 가 실제로 넣는 것과 같은 순서·같은 판단이다(템플릿의 정예 자리 →
## 더 깊이에서 정예가 하나도 없을 때 붙는 강한 정예). 결투를 새로 붙일지 판단하는 근거이며,
## 같은 종류를 두 번 넣지 않고(중복 배정 금지) 한 전투에 결투가 둘이 되지 않게 한다(1대1).
## 난수를 쓰지 않는다 — 시드·저장이 같으면 같은 답이다.
static func scheduled_special_elites(region_id: String, formation_id: String, deep: bool = false) -> Array:
	if not is_theme_place(region_id):
		return []
	var tpl := theme_template(region_id, formation_id)
	if tpl.is_empty():
		return []
	var out := []
	for t in elite_types_for(tpl, theme_place_key(region_id), deep):
		if is_special_elite(String(t)) and not out.has(String(t)):
			out.append(String(t))
	if deep and int(tpl.get("elites", 0)) <= 0: # 더 깊이: 정예가 없는 편성에는 강한 정예가 하나 붙는다
		var dt := deep_elite_type(region_id, formation_id)
		if is_special_elite(dt) and not out.has(dt):
			out.append(dt)
	return out

## 막 안에서 몇 번째 날인가(1~3). 막 정의가 없으면 0
static func day_in_act(run: Dictionary, day: int) -> int:
	var a := act_of(run, day)
	if a.is_empty():
		return 0
	var i := 1
	for x in (a.get("days", []) as Array):
		if int(x) == day:
			return i
		i += 1
	return 0

## 하루의 카드가 모두 정해진 뒤 **한 장에만** 특수 정예 결투를 붙인다. **난수를 쓰지 않는다**(시드·저장 재현 유지).
##
## 규칙: 막 안 날짜마다 결투 자리가 하나 있고(선호 카드 순번은 data/themes.json duel.day_card_pref),
## 그 자리가 위험 카드면 같은 날의 다른 카드로 옮긴다(위험 카드는 이미 편성 안에 특수 정예가 있다).
## 후보는 **막 안 날짜**로 고르므로 서로 다른 두 날에서는 반드시 다른 종류가 나온다 —
## 한 막(3일)에서 하루가 통째로 위험 카드여도 **서로 다른 두 종류**를 만날 기회가 남는다.
##
## §13(2026-09-09): **1대1 결투 원칙**. 그 카드의 편성이 이미 특수 정예를 배정하고 있으면
## 결투를 겹쳐 붙이지 않는다 — 붙이면 한 전투에 결투가 둘이 되기 때문이다.
## 붙이지 않아도 총 등장 수·경험치 예산은 그대로다(결투 상대는 일반 적 1마리를 대신하는 것이라
## 붙지 않으면 그 자리에 원래의 일반 적이 남는다).
static func assign_duel(run: Dictionary, day: int, cards: Array) -> void:
	for c in cards:
		c.duelType = ""
		c.duelName = ""
	if not duel_enabled() or cards.is_empty():
		return
	var d_in := day_in_act(run, day)
	if d_in <= 0:
		return
	var pref := int(duel_cfg().get("day_card_pref", {}).get(str(d_in), 0))
	var pick := -1
	for k in cards.size():
		var i: int = (pref + k) % cards.size()
		if cards[i].get("risk", null) != null or not is_theme_place(String(cards[i].regionId)):
			continue
		# **임무 목표 카드에는 결투를 붙이지 않는다**(2026-09-09, KD-11).
		# 결투는 "일반 편성을 전부 정리한 뒤에 시작"한다(CombatState.update_duel의 normal 단계).
		# 그런데 임무 전투는 목표를 이루는 순간 끝난다 — 포로를 다 풀고 출구에 들어가면
		# 남은 적이 있어도 그 자리에서 승리다. 그래서 결투가 **시작도 못 한 채** 전투가 끝났고,
		# PFlow.settle_victory 가 "특수 정예전 미완료 상태의 승리 정산"으로 거부해 보상이 빈 사전이 되고,
		# 보상 화면이 버튼 하나 없이 그려져 **아무것도 누를 수 없었다**(사용자 재현: 포로 구출 뒤 검은 화면).
		#
		# 승리를 막아 결투를 기다리게 하는 길도 있지만, 그러면 목표를 이룬 뒤에도 남은 적과
		# 지원병을 전부 잡아야 끝나서 **끝낼 수 없는 전투**가 될 위험이 있다. 두 규칙이 같은 카드에서
		# 양립하지 않으므로 배정 단계에서 겹치지 않게 한다. 다른 카드가 있으면 거기에 붙는다.
		if PObjectives.is_objective(String(cards[i].get("objective", "clear"))):
			continue
		# 1대1: 편성이 이미 특수 정예를 내보내는 카드에는 결투를 겹치지 않는다(§13)
		if not scheduled_special_elites(String(cards[i].regionId), String(cards[i].get("formationId", "base"))).is_empty():
			continue
		pick = i
		break
	if pick < 0:
		return
	var cands := duel_types_for(PCatalog.theme_of_place(String(cards[pick].regionId)))
	if cands.is_empty():
		return
	var dt := String(cands[d_in % cands.size()])
	cards[pick].duelType = dt
	cards[pick].duelName = String(PCatalog.enemies()[dt].name)

## 더 깊이 탐험에서 붙는 추가 결투 상대(자리와 겹치지 않게 다음 후보). 이미 결투가 있으면 그대로 둔다.
##
## §13(2026-09-09): 그 편성이 **더 깊이에서** 내보내는 특수 정예와 같은 종류는 고르지 않는다(중복 배정 금지).
## 남는 후보가 없으면 붙이지 않는다 — 결투 상대는 일반 적 1마리를 대신하므로 총 등장 수·예산은 그대로다.
static func duel_type_deep(run: Dictionary, sortie: Dictionary) -> String:
	if not duel_enabled() or not bool(duel_cfg().get("deep_extra", false)):
		return ""
	var rid := String(sortie.get("regionId", ""))
	if not is_theme_place(rid) or String(sortie.get("duelType", "")) != "":
		return String(sortie.get("duelType", ""))
	var cands := duel_types_for(PCatalog.theme_of_place(rid))
	if cands.is_empty():
		return ""
	# 1대1: 더 깊이 편성이 이미 특수 정예를 내보내면 결투를 겹치지 않는다.
	# (더 깊이는 정예가 없는 편성에도 강한 정예를 하나 붙이므로 그것까지 함께 본다)
	if not scheduled_special_elites(rid, String(sortie.get("formationId", "base")), true).is_empty():
		return ""
	return String(cands[(int(run.get("day", 1)) + int(sortie.get("encounters", 0))) % cands.size()])

## 출격 **전에** 보여 줄 강적 예고(화면·봇 공용, 표시는 다른 담당이 그린다).
## { present, type, name, role, read{}, hp, reward, text }
static func duel_notice(run: Dictionary, region_id: String, duel_type: String) -> Dictionary:
	if duel_type == "":
		return { "present": false, "type": "", "name": "", "text": "" }
	var d := PCatalog.enemy(duel_type)
	var ed := PCatalog.elite_def(duel_type)
	return { "present": true, "type": duel_type, "name": String(d.get("name", duel_type)), "role": String(d.get("role", "")),
		"read": ed.get("read", {}), "hp": PPacing.elite_hp(duel_type, int(act_of(run).get("id", 1))),
		"reward": PSortie.elite_reward_text(run, region_id),
		"text": "%s · %s" % [String(duel_cfg().get("notice", "마지막에 강적이 나타난다")), String(d.get("name", duel_type))] }

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
			outt.append({ "id": String(f.id), "name": String(f.name), "desc": String(f.get("desc", "")), "goal": String(f.get("goal", "")), "kind": String(f.get("kind", "")) })
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

static func formation_waves(region_id: String, day: int, formation_id: String, deep: bool = false, duel_type: String = "") -> Array:
	if is_theme_place(region_id):
		var tpl := theme_template(region_id, formation_id)
		if tpl.is_empty():
			var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
			tpl = (t.formations.normal as Array)[0]
		return template_waves(tpl, theme_place_key(region_id), day, place_cost(region_id), deep, duel_type)
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
			for k in ["budget_from", "duel", "common_elite"]: # 예산 이관·결투 상대·일반 정예 표시는 복사에서 빠지면 안 된다
				if g.has(k):
					e[k] = g[k]
			wave.append(e)
		out.append(wave)
	return out

## 이 웨이브들에 이미 특수 정예 결투가 들어 있는가(§13 1대1 판단)
static func _has_duel(waves: Array) -> bool:
	for w in waves:
		for g in w:
			if bool(g.get("duel", false)) and is_special_elite(String(g.type)) and int(g.n) > 0:
				return true
	return false

static func encounter_waves(region_id: String, deep: bool, run: Dictionary, sortie: Dictionary = {}) -> Array:
	var waves := _copy_waves(formation_waves(region_id, int(run.get("day", 1)), String(sortie.get("formationId", "base")), deep, String(sortie.get("duelType", ""))))
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
	if not is_theme_place(region_id): # 옛 지역 일정: 기존 규칙 그대로(웨이브마다 +1, 마지막에 늑대 우두머리)
		for w in waves:
			for g in w:
				g.n = int(g.n) + 1
		var last_l: Array = waves[waves.size() - 1]
		var has_elite := false
		for g in last_l:
			if String(g.type) == "wolf_alpha":
				has_elite = true
		if not has_elite:
			last_l.append({ "type": "wolf_alpha", "n": 1 })
		return waves
	# 테마 장소의 더 깊이: **호위만** 웨이브마다 +1. 정예 수는 막별 상한(PCatalog.elite_max_per_fight)을 넘지 않고,
	# 대신 종류가 더 강한 쪽(elite_type_p2)으로 이미 바뀌어 있다 — "강한 정예 1 + 호위" 구성.
	var cap := PCatalog.elite_max_per_fight(int(act_of(run).get("id", 1)))
	var elites_n := 0
	for w in waves:
		for g in w:
			# **정예 자리**만 센다. 카드가 붙인 결투 상대는 일반 적 1마리를 대신한 것(budget_from)이라
			# 정예 자리가 아니다 — 호위 +1도 정예 상한 계산도 대상이 아니다.
			# 템플릿이 배정한 특수 정예는 이제 결투 표시를 달고 있지만 **정예 자리는 맞으므로 센다**
			# (§13 이전과 같은 수가 나온다 — 여기서 정예를 더 붙이거나 빼지 않는다).
			if bool(g.get("duel", false)) and g.has("budget_from"):
				continue
			if bool(PCatalog.enemy(String(g.type)).get("elite", false)):
				elites_n += int(g.n)
			else:
				g.n = int(g.n) + 1
	var last: Array = waves[waves.size() - 1]
	if elites_n <= 0: # 정예가 없는 편성이면 그 테마의 강한 정예를 하나 붙인다
		var dt := deep_elite_type(region_id, String(sortie.get("formationId", "base")))
		# **1대1**(§13): 카드가 이미 결투 상대를 붙였다면 여기에 특수 정예를 또 붙이지 않는다.
		# 그렇다고 자리를 비우지도 않는다 — 옛 정예(늑대 우두머리)가 그 자리를 채운다.
		# 경험치 단위값이 특수 정예와 **같은 30**이라 총 등장 수도 전투 경험치 예산도 그대로다.
		if is_special_elite(dt) and _has_duel(waves):
			dt = "wolf_alpha"
		var e := { "type": dt, "n": 1, "ref": 1.0 }
		if is_special_elite(dt): # 특수 정예면 일반 목록이 아니라 **결투**로 붙는다(§13)
			e["duel"] = true
		last.append(e)
	elif elites_n > cap: # 상한을 넘으면 뒤에서부터 줄인다(경험치 예산도 함께 줄어 늘지 않는다)
		var over := elites_n - cap
		for i in range(last.size() - 1, -1, -1):
			var g: Dictionary = last[i]
			if over <= 0:
				break
			if (bool(g.get("duel", false)) and g.has("budget_from")) or not bool(PCatalog.enemy(String(g.type)).get("elite", false)):
				continue
			var cut: int = mini(over, int(g.n))
			g.n = int(g.n) - cut
			if g.has("ref"):
				g.ref = maxf(0.0, float(g.ref) - float(cut))
			over -= cut
	return waves

## 더 깊이 탐험·큰 보상 장소에서 이 편성이 내보내는 정예 종류(표시·보상 문구 공용)
static func deep_elite_type(region_id: String, formation_id: String) -> String:
	if is_theme_place(region_id):
		var tpl := theme_template(region_id, formation_id)
		if not tpl.is_empty():
			var lst := elite_types_for(tpl, theme_place_key(region_id), true)
			if not lst.is_empty():
				return String(lst[0])
		var t := PCatalog.theme(PCatalog.theme_of_place(region_id))
		for f in ((t.formations.risk as Array) + (t.formations.normal as Array)): # 정예를 쓰는 편성이 있으면 그 종류를 따른다
			var l2 := elite_types_for(f, theme_place_key(region_id), true)
			if not l2.is_empty():
				return String(l2[0])
	return "wolf_alpha"

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
		if not owns_equip(run, String(id)) and not items.has(id) and PProfile.run_unlock_ok(run, "equipment", String(id)) and not PCatalog.equipment_retired(String(id)):
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
			reward = { "kind": kind, "text": "개조 변경권 1장 (대장간에서 개조 1개를 다른 효과로 변경)", "service": "mod_swap" }
		_:
			reward = { "kind": kind, "text": "다음 레벨업 예약: 자동기술 개조", "steer": "weapon_mod" }
	var out := { "extraTime": int(C().DEEP_EXPLORE_HOURS), "nextSlot": next_slot_name(run, int(C().DEEP_EXPLORE_HOURS)), "enemyChange": deep_enemy_change(run, sortie),
		"hpMult": hp_mult_for(run, String(sortie.regionId), true), "reward": reward, "lootAtRisk": _loot_at_risk(sortie) }
	sortie.deepPreview = out
	return out

## 더 깊이 미리보기의 '적 변화' 한 줄. 테마 장소는 실제로 나올 강한 정예 이름을 보여 준다(사전 표시)
static func deep_enemy_change(run: Dictionary, sortie: Dictionary) -> String:
	var rid := String(sortie.regionId)
	if not is_theme_place(rid):
		return "웨이브마다 적 +1, 마지막에 정예(가시갈기)"
	var names := []
	for w in encounter_waves(rid, true, run, sortie):
		for g in w:
			if bool(PCatalog.enemy(String(g.type)).get("elite", false)) and int(g.n) > 0:
				names.append("%s%s" % [String(PCatalog.enemy(String(g.type)).name), ("×%d" % int(g.n)) if int(g.n) > 1 else ""])
	if names.is_empty():
		return "호위가 웨이브마다 +1"
	return "호위가 웨이브마다 +1, 강적 %s" % " · ".join(names)

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
	var dt := duel_type_deep(run, sortie) # 더 깊은 곳: 추가 조우(자리가 아니어도 결투가 붙는다)
	if dt != "":
		sortie.duelType = dt
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
## 강적(정예)을 실제로 쓰러뜨렸을 때만 붙는 추가 금화. 규칙은 data/pacing.json elite_reward에 있다.
## **중복 금지**: 그 장소가 이미 '정예 처치 조건부 재료'(송곳니)를 주면 추가로 주지 않는다 — 같은 위험을 두 번 보상하지 않는다.
## 더 깊이 배율·위험 조건 배율도 곱하지 않는다(그 배율은 기존 전리품에 이미 붙어 있다). 조우 1회에 정확히 1번.
static func elite_bonus_gold(run: Dictionary, region_id: String, elite_killed: bool) -> int:
	if not elite_killed:
		return 0
	var cfg: Dictionary = PCatalog.pacing().get("elite_reward", {})
	if not bool(cfg.get("enabled", false)):
		return 0
	var skip := String(cfg.get("skip_if_mat", ""))
	if skip != "" and (region(region_id).get("reward", {}).get("mats", {}) as Dictionary).has(skip):
		return 0 # 이미 정예 조건부 재료를 주는 장소: 중복 지급하지 않는다
	var act := int(act_of(run).get("id", 1)) if not run.is_empty() else 1
	return int((cfg.get("gold_by_act", {}) as Dictionary).get(str(clampi(act, 1, 3)), 0))

## 조우 승리 보상(난수는 전투의 rng → 재현 가능). combat_stats: {chestGold, eliteKilled}
static func roll_reward(run: Dictionary, sortie: Dictionary, rng: PRng, combat_stats: Dictionary) -> Dictionary:
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
	# 강적 추가 보상: 실제로 정예를 잡았고, 그 장소가 이미 정예 조건부 재료를 주지 않을 때만(중복 금지)
	var eb := PPacing.gold_award(elite_bonus_gold(run, String(sortie.regionId), bool(combat_stats.get("eliteKilled", false))))
	# 금화 감축(사용자 결정 약 -30%, 시험값 ×0.7)은 "새로 지급하는" 금화에만 최종 1회. 판매금·환불·잔액에는 적용하지 않는다
	return { "gold": PPacing.gold_award(gold) + eb, "eliteGold": eb, "mats": mats, "chestGold": PPacing.gold_award(int(combat_stats.get("chestGold", 0))) }

static func apply_encounter_result(run: Dictionary, sortie: Dictionary, result: String, reward: Dictionary, combat_hp: float) -> void:
	PConsumables.clear_used(run) # 이번 전투 준비물 표시만 지운다(소모는 되돌리지 않는다 — 같은 출격의 다음 전투로 이어지지 않는다는 뜻)
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
		var iid := equip_type_of(String(id)) # 전리품 목록은 **종류**다. 가방에 들어갈 때 개체 id를 발급한다
		if owns_equip_type(run, iid):
			var dup_gold := sell_value(run, iid) # 중복 드롭도 판매와 같은 기준(구매액 없으면 정상가의 절반)
			run.gold = int(run.gold) + dup_gold
			extras.append("%s(중복→금화 +%d)" % [equip_name(iid), dup_gold])
		else:
			(run.bag as Array).append(equip_new_uid(run, iid))
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

# ---------- 사망(2026-09-09 사용자 확정) ----------
## 사람 플레이에서 쓰러지면 그 회차는 끝난다. 부활 수단(부활 물약)을 **가지고 있을 때에만** 한 개가 소모되고 다시 일어난다.
## 부활 자리는 날짜가 정한다: 다음 날이 있으면 하루를 잃고 다음 날 아침, 마지막 날이면 같은 날 관문 앞(날짜를 늘리지 않는다).
## 옛 규칙(일반 패배 후 무료 체력 회복·다음 날 진행, 보스 패배 후 무료 상태 복원·무제한 재도전)은 사람 플레이에서 사라졌다.
##
## 시험·자동 진행용 재시도 경로(사람 플레이와 분리)
## ------------------------------------------------
## run.testRetry가 true인 회차만 옛 규칙(무료 회복·보스 재도전)을 그대로 쓴다. 켜는 방법은 두 가지뿐이다:
##   - PRun.new_run(..., { "test_retry": true })  — 도구·시험이 명시적으로 켠다(PRunBot 기본값)
##   - 환경 변수 PROPHECY_TEST_RETRY=1            — 실제 게임 화면을 자동으로 굴리는 스위트(ui_smoke_*·ui_flow_tests 등, tools/suites.json)
## 사람이 플레이하는 회차는 이 값이 언제나 false다(새 회차 기본값·옛 저장에도 키가 없다).
static func retry_mode(run: Dictionary) -> bool:
	return bool(run.get("testRetry", false))

## 이 회차가 사망으로 끝났는가(완주 cleared와 구분한다)
static func is_run_over(run: Dictionary) -> bool:
	return String(run.get("phase", "")) == "dead"

## 다음 날이 있는가. 본편 마지막 날(마지막 관문일)에는 없다 — 그 날의 부활 규칙은 settle_death 주석과 docs/DEATH_AND_ECONOMY.md
static func has_next_day(run: Dictionary) -> bool:
	return int(run.get("day", 1)) < int(mode_def(run).get("days", 0))

## 지금 쓰러지면 부활할 수 있는가(물약 보유 여부만 본다 — 마지막 날에도 물약만 있으면 부활한다)
static func can_revive(run: Dictionary) -> bool:
	return PConsumables.has_revive(run)

## 이 회차에서 부활 물약을 실제로 쓴 횟수. 저장에 남으므로 이어하기로 되돌아가지 않는다.
## dict 안의 "count"는 PSave가 정수로 정규화하는 키다(bossEntries와 같은 방식 — 저장 정규화 표를 건드리지 않으려고 이 형태를 쓴다)
static func revive_uses(run: Dictionary) -> int:
	var u = run.get("reviveUses", null)
	return int((u as Dictionary).get("count", 0)) if typeof(u) == TYPE_DICTIONARY else 0

## 부활로 들어가는 관문 재입장 표식(2026-09-09 사용자 확정: 부활 체력 25%가 실제 재도전까지 간다).
## true면 **다음 start_boss 한 번**이 자동 완전 회복을 건너뛴다 — 그 한 번에서 소비되고(clear_revive_pending) 다시 서지 않는다.
## 표식은 settle_death가 부활로 관문 앞(phase "boss_prep")에 세울 때만 붙는다. 보통 날 아침으로 부활하면 붙이지 않는다
## (그 사이 end_day가 정상 회복을 하므로 표식이 남아 나중의 정상 입장까지 따라가면 안 된다 — end_day도 표식을 지운다).
## dict 안의 "count"는 PSave가 정수로 정규화하는 키다(bossEntries·reviveUses와 같은 방식 — 저장 정규화 표를 건드리지 않으려고 이 형태를 쓴다).
static func revive_pending(run: Dictionary) -> bool:
	var p = run.get("revivePending", null)
	return int((p as Dictionary).get("count", 0)) > 0 if typeof(p) == TYPE_DICTIONARY else false

## 표식을 지운다(관문 입장에서 소비되거나, 하루가 정상으로 넘어가거나, 관문을 넘었을 때)
static func clear_revive_pending(run: Dictionary) -> void:
	run.revivePending = { "count": 0 }

## 마지막 사망이 **같은 날 관문 앞 부활**이었는가(마지막 날 부활). 화면이 안내 문구를 고르는 데 쓴다
static func revived_same_day(run: Dictionary) -> bool:
	var d = run.get("death", null)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	return bool((d as Dictionary).get("revived", false)) and bool((d as Dictionary).get("sameDay", false))

## 사망 정산(정확히 1회). ctx: { key: 중복 방지 키, cause: "sortie"|"boss", regionId, bossId }
## 같은 사망을 두 번 넘겨도 물약이 두 개 빠지거나 하루가 두 번 지나가지 않는다(run.death.key로 못박는다).
## 부활 불가: 회차 종료(phase "dead", ended true). 완주(cleared)와 구분되며 PFlow.actions는 빈 목록을 돌려준다.
##
## 부활할 때(2026-09-09 사용자 확정, 두 갈래 모두 물약 1개 소모)
## ------------------------------------------------------------
##  - 다음 날이 있는 날: 남은 하루를 잃고 **다음 날** 아침에 최대 체력 hpFrac(25%)로 선다.
##  - 다음 날이 없는 **마지막 날**: 날짜를 늘리지 않고 **같은 날 관문 앞**에 최대 체력 25%로 선다.
##    그날 남은 시간은 전부 소진한다(run.hours = 0). 일정(10일)을 늘리지 않는 대신 그 날의 시간을 되돌려 주지도 않는다.
## 어느 쪽이든 미완료 관문은 그대로 남는다(건너뛰지 않고 다음 막도 열리지 않는다).
## 부활을 반복하려면 매번 물약이 한 개씩 든다 — 중복 방지 키는 관문 입장마다 새로 생기므로(start_boss가 bossEntries를 1 올린다)
## 다시 들어가서 또 쓰러지면 새 사망으로 정산된다. 물약이 떨어지면 그다음 죽음이 회차 종료다.
static func settle_death(run: Dictionary, ctx: Dictionary) -> Dictionary:
	var key := String(ctx.get("key", ""))
	var prev: Dictionary = run.get("death", {}) if typeof(run.get("death", null)) == TYPE_DICTIONARY else {}
	if key != "" and String(prev.get("key", "")) == key:
		return prev # 같은 사망의 두 번째 정산: 아무것도 하지 않는다
	var b := build(run)
	var frac: float = float(PConsumables.revive_def().get("hpFrac", 0.25))
	var next_day := has_next_day(run)
	var revived := PConsumables.consume_revive(run) if can_revive(run) else false
	var rec := {
		"key": key, "cause": String(ctx.get("cause", "sortie")), "day": int(run.get("day", 1)), "stage": int(run.get("stage", 0)),
		"count": int(prev.get("count", 0)) + 1, "seq": int(prev.get("seq", 0)) + 1,
		"regionId": String(ctx.get("regionId", "")), "bossId": String(ctx.get("bossId", "")),
		"revived": revived, "endedRun": not revived, "nextDay": next_day,
		"sameDay": revived and not next_day, # 마지막 날 부활 = 날짜를 넘기지 않고 같은 날 관문 앞(화면이 다른 문구를 쓴다)
		"hp": 0.0,
	}
	run.bossEntry = null # 사망 정산은 입장 스냅샷을 복구하지 않고 지운다(소모한 물약이 되살아나지 않게)
	run.lastDefeatDay = int(run.day)
	if not revived:
		run.hours = 0
		run.hp = 0.0
		run.phase = "dead"
		run.ended = true
		clear_revive_pending(run) # 끝난 회차에는 재입장 표식이 남지 않는다
		add_log(run, "부활 수단이 없다: 회차 종료(%d일차)" % int(run.day))
		run.death = rec
		return rec
	# 쓴 횟수는 회차에 누적해 저장한다(개수와 함께 이어하기로 되살아나지 않는 것을 검사로 못박는다)
	run.reviveUses = { "count": revive_uses(run) + 1 }
	run.hours = 0 # 어느 갈래든 그 날의 남은 시간은 사라진다
	if next_day: # 남은 하루를 잃고 다음 날 아침
		run.day = int(run.day) + 1
		run.hours = int(C().HOURS_PER_DAY)
		if not run.has("buffs") or run.buffs == null:
			run.buffs = {}
	run.hp = maxf(1.0, round(float(b.hp_max) * frac))
	rec.hp = float(run.hp)
	# 미완료 관문은 그대로 남는다: 관문 날이면 다시 관문 준비 상태, 아니면 보통 준비 상태.
	# 순서는 end_day와 같다 — 오늘의 장소·카드·재고는 phase가 정해진 뒤에 뽑는다.
	# 마지막 날에는 날짜가 그대로이므로 장소·카드·재고를 다시 뽑지 않는다(같은 날의 재고가 새로 열리면 안 된다)
	run.phase = "boss_prep" if is_boss_day(run) else "prep"
	# 부활로 **관문 앞**에 섰다면 다음 관문 입장 한 번은 자동 완전 회복을 건너뛴다(부활 체력 25%가 실제 전투 시작까지 간다).
	# 관문 앞이 아니면(보통 날 아침) 표식을 두지 않는다 — 그 사이 end_day가 정상 회복을 하므로 남겨 둘 이유가 없다.
	if String(run.phase) == "boss_prep":
		run.revivePending = { "count": 1 }
	else:
		clear_revive_pending(run)
	if next_day:
		places_for(run)
		PSortie.cards_for(run)
		refresh_stock(run)
	if String(ctx.get("cause", "")) == "boss":
		run.bossRetries = int(run.get("bossRetries", 0)) + 1
	if next_day:
		add_log(run, "부활: %s → %d일차 %s, 체력 %d/%d (미정산 전리품 상실)" % [
			PConsumables.name_of(PConsumables.revive_id()), int(run.day), slot_name(run), int(float(run.hp)), int(float(b.hp_max))])
	else:
		add_log(run, "부활: %s → 마지막 날(%d일차)이라 날짜는 그대로, 같은 날 관문 앞에서 체력 %d/%d (남은 시간 전부 소진 · 미정산 전리품 상실)" % [
			PConsumables.name_of(PConsumables.revive_id()), int(run.day), int(float(run.hp)), int(float(b.hp_max))])
	if String(run.phase) == "boss_prep":
		add_log(run, "관문은 그대로 남아 있다: 넘기 전까지 다음 막 활동은 잠긴다")
	run.death = rec
	return rec

## 일반 출격 패배. 사람 플레이: 미정산 전리품 상실 + 사망 정산(부활 물약이 있으면 부활, 없으면 회차 종료).
## 시험 재시도 경로(run.testRetry)에서만 옛 규칙(남은 하루 상실 → 다음 날 정상 체력)을 쓴다.
static func defeat(run: Dictionary, sortie: Dictionary) -> void:
	if bool(sortie.get("lost", false)): # 같은 출격의 두 번째 패배 처리는 무시(하루가 두 번 지나가지 않는다)
		return
	sortie.lost = true
	sortie.settled = true
	sortie.loot = { "gold": 0, "mats": {}, "chestGold": 0 }
	if PEndless.active(run): # 무한: 패배 = 종료(재도전 없음), 본편 완주 기록 유지
		PEndless.over(run, "lost")
		return
	add_log(run, "%s에서 쓰러졌다: 미정산 전리품 상실" % String(region(String(sortie.regionId)).name))
	if retry_mode(run): # 시험·자동 진행 전용 경로(사람 플레이 아님)
		run.hours = 0
		run.hp = float(build(run).hp_max)
		run.lastDefeatDay = int(run.day)
		if String(run.phase) == "prep":
			end_day(run)
		return
	settle_death(run, { "cause": "sortie", "key": "sortie:%d:%d" % [int(run.get("sortieCount", 0)), int(sortie.get("encounters", 0))], "regionId": String(sortie.get("regionId", "")) })

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
## 쉴 수 있는가.
## 거점(prep): 예전 그대로 — 시간 1칸 또는 휴식권.
## 관문 앞(boss_prep): **마지막 날이 아니고 시간이 남아 있으면** 쉴 수 있다(사용자 확정 2026-09-09).
##   왜: 관문에서 죽고 부활하면 다음 날 관문 앞에 최대 체력의 25%로 선다. 하루가 통째로 남아도
##   그 단계에서는 휴식이 막혀 회복약 말고는 회복 수단이 없었다. '시간을 잃는다'는 비용은 이미
##   치렀는데 그 시간을 쓸 방법이 없는 것이 어긋난다.
##   비용은 그대로다 — 휴식은 여전히 시간 1칸(또는 가진 휴식권)을 먹는다. 공짜 회복이 아니다.
##   마지막 날은 부활이 그날 시간을 전부 소진시키므로 hours가 0이라 자연히 막힌다. 그래도
##   **has_next_day를 함께 본다** — 시간이 남은 채로 마지막 날 관문 앞에 서는 다른 경로가 생겨도
##   마지막 날의 비용(그날을 잃는다)이 새어 나가지 않게 하기 위해서다.
##   **휴식권만으로는 이 자리가 열리지 않는다** — "시간을 소비해 쉰다"가 이 자리의 규칙이다.
##
## **관문 앞에서는 시간과 휴식권을 나눈다(사용자 확정 2026-09-09 보완).**
##   기본 '휴식' = 시간 1칸. 가진 휴식권을 **자동으로 쓰지 않는다.**
##   휴식권은 '휴식권 사용'이라는 별도 선택이고, 그것도 **마지막 날 제외·남은 시간 1칸 이상**을 지킨다
##   — 시간 0이나 마지막 날을 우회하는 수단이 되면 안 된다.
##   거점(prep)의 기존 규칙은 이 보완으로 바뀌지 않는다(예전처럼 휴식권이 있으면 먼저 쓴다).
static func can_rest(run: Dictionary) -> bool:
	match String(run.phase):
		"prep":
			return int(run.hours) >= int(C().REST_HOURS) or has_service(run, "free_rest")
		"boss_prep":
			return has_next_day(run) and int(run.hours) >= int(C().REST_HOURS)
	return false

## 관문 앞에서 '휴식권 사용'을 고를 수 있는가. 자리 조건(마지막 날 제외·시간 1칸 이상)은 같고
## 휴식권을 실제로 가지고 있어야 한다. 거점에서는 이 갈래를 쓰지 않는다(기존 규칙 유지)
static func can_rest_voucher(run: Dictionary) -> bool:
	return String(run.phase) == "boss_prep" and can_rest(run) and has_service(run, "free_rest")

## 휴식권의 표시 이름. 데이터의 서비스 이름("무료 휴식권")은 다른 담당 파일이라 바꾸지 못하므로,
## 화면이 쓸 문구는 규칙 계층이 준다 — "무료"가 아니라 "시간 소모 없음"이 사용자 확정 표현이다.
static func rest_voucher_name() -> String:
	return "휴식권 (시간 소모 없음)"

## 쉴 수 없는 이유(화면이 그대로 쓴다). 관문 앞이 열린 뒤로 "거점에서만"은 더 이상 맞는 말이 아니다
static func _rest_block_reason(run: Dictionary) -> String:
	match String(run.phase):
		"prep":
			return "시간 부족(%d칸 필요)" % int(C().REST_HOURS)
		"boss_prep":
			if not has_next_day(run):
				return "마지막 날 관문 앞에서는 쉴 수 없습니다"
			return "시간 부족(%d칸 필요)" % int(C().REST_HOURS)
	return "거점이나 관문 앞에서만"

## 휴식 견적(확인 창용, 회차를 전혀 바꾸지 않는다). 확정은 rest()가 한다 — 취소하면 아무 일도 없다.
## 휴식권은 100금 그대로이고, 표현은 "무료"가 아니라 **"시간 소모 없음"**이다(costText를 화면이 그대로 쓴다).
## { can, reason, useVoucher, hours, costText, slotNow, slotAfter, hp, hpAfter, hpMax, heal, voucherLeft, voucherPrice, forced, text }
## opt.useVoucher: 관문 앞에서 '휴식권 사용'을 고른 경우 true. 거점에서는 예전처럼 자동 판단한다
static func rest_quote(run: Dictionary, opt: Dictionary = {}) -> Dictionary:
	var gate := String(run.phase) == "boss_prep"
	var voucher: bool = bool(opt.get("useVoucher", false)) if gate else has_service(run, "free_rest")
	var hours: int = 0 if voucher else int(C().REST_HOURS)
	var hp_max := float(build(run).hp_max)
	var can: bool = can_rest_voucher(run) if (gate and voucher) else can_rest(run)
	return {
		"can": can, "reason": "" if can else (("휴식권이 없습니다" if (gate and voucher and not has_service(run, "free_rest")) else _rest_block_reason(run))),
		"useVoucher": voucher, "hours": hours, "voucherName": rest_voucher_name(),
		"costText": "시간 소모 없음 (휴식권 1장)" if voucher else "시간 %d칸" % hours,
		"slotNow": slot_name(run), "slotAfter": next_slot_name(run, hours),
		"hp": float(run.hp), "hpAfter": hp_max, "hpMax": hp_max, "heal": maxf(0.0, hp_max - float(run.hp)),
		"voucherLeft": int(run.get("services", {}).get("free_rest", 0)), "voucherPrice": merchant_service_price("free_rest"),
		"forced": not any_departure(run),
		"text": "휴식하면 체력이 %d → %d(최대 %d)이 되고 %s입니다. 쉬시겠습니까?" % [int(float(run.hp)), int(hp_max), int(hp_max), ("시간이 들지 않습니다(휴식권 1장 사용)" if voucher else "%s이(가) 됩니다" % next_slot_name(run, hours))],
	}

## 휴식 확정(확인 창의 '예'). 견적은 rest_quote가 준다
## opt.useVoucher: 관문 앞 '휴식권 사용'. 거점에서는 무시하고 예전 규칙대로 판단한다.
## **시간과 휴식권 중 하나만 빠진다** — 둘이 함께 빠지는 길은 없다(검사로 못 박았다).
static func rest(run: Dictionary, opt: Dictionary = {}) -> bool:
	var gate := String(run.phase) == "boss_prep"
	var want_voucher: bool = bool(opt.get("useVoucher", false)) and gate
	if want_voucher:
		if not can_rest_voucher(run):
			push_error("휴식권 사용 불가")
			return false
	elif not can_rest(run):
		push_error("휴식 불가")
		return false
	if want_voucher:
		use_service(run, "free_rest")           # 관문 앞: 골랐을 때만 휴식권을 쓴다(시간은 그대로)
	elif gate:
		run.hours = int(run.hours) - int(C().REST_HOURS)  # 관문 앞 기본: 시간 1칸. 휴식권을 자동 소비하지 않는다
	elif has_service(run, "free_rest"):
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
	clear_revive_pending(run) # 하루가 정상으로 넘어가면 부활 표식은 남지 않는다(다음 날 정상 입장은 예전대로 완전 회복)
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
##
## 예외 하나(2026-09-09 사용자 확정): **부활로 들어온 재입장**(run.revivePending)은 자동 완전 회복을 건너뛴다.
## 그래야 부활 체력 25%가 실제 재도전에서 값을 한다 — 예전에는 여기서 100%로 되돌아가 25%가 아무 비용도 아니었다.
## 그 사이 휴식·회복약 같은 정상 회복 수단으로 오른 체력은 **그대로** 들어간다(다시 25%로 깎지 않는다).
## 표식은 이 입장 한 번에만 쓰이고 여기서 소비된다 — 다음 정상 입장은 예전대로 완전 회복이다.
## 시험 재시도 경로(run.testRetry)는 사망 정산 자체를 하지 않아 표식이 붙지 않는다(경로가 섞이지 않는다).
static func start_boss(run: Dictionary) -> Dictionary:
	if not can_start_boss(run):
		push_error("보스 준비 상태가 아님")
		return {}
	var revive_entry := revive_pending(run)
	clear_revive_pending(run) # 표식 소비: 성공한 입장 한 번에만 쓰인다
	if revive_entry:
		clamp_hp(run) # 장비를 팔아 최대 체력이 줄었으면 거기에 맞춘다(올리지는 않는다)
		run.hp = maxf(1.0, float(run.hp))
		add_log(run, "부활 뒤 재입장: 체력 %d/%d 그대로 관문에 들어간다 (입장 회복 없음)" % [int(float(run.hp)), int(float(build(run).hp_max))])
	else:
		run.hp = float(build(run).hp_max)
	# 준비물·회복약도 금화·장비와 같은 규칙으로 스냅샷에 담는다(재도전이 소모를 되돌린다 — 재도전마다 다시 사지 않아도 되고, 무한 회복도 아니다)
	var snap := { "growth": run.growth, "hp": run.hp, "stage": int(run.get("stage", 0)), "gold": int(run.gold), "services": run.services, "equipment": run.equipment, "bag": run.bag, "forge": int(run.forge), "forgeBySkill": run.get("forgeBySkill", {}),
		"equipPlus": equip_plus_map(run), "equipSeq": int(run.get("equipSeq", 0)) } # 장비 개체·강화도 금화·가방과 같은 규칙으로 스냅샷에 담는다
	snap["prep"] = PConsumables.snapshot(run)
	run.bossEntry = snap.duplicate(true)
	run.bossEntries = { "count": boss_entries(run) + 1 } # 사망 정산 중복 방지 키(입장마다 1 증가 — 같은 입장의 패배는 한 번만 정산된다). dict 안의 "count"는 PSave가 정수로 정규화하는 키다
	var nb := next_boss(run)
	return { "regionId": "boss", "bossId": String(nb.id) if not nb.is_empty() else "boss", "stage": int(run.get("stage", 0)), "seed": boss_seed(run), "loot": { "gold": 0, "mats": {} }, "encounters": 0 }

## 관문 전투가 **실제로 시작될 때**의 플레이어 체력(PFlow.make_boss_encounter가 이 값을 CombatState에 넣는다).
## 입장 규칙(start_boss)이 정한 run.hp를 그대로 쓴다: 보통 입장은 그 값이 이미 최대 체력이고,
## 부활로 들어온 재입장에서만 25%(또는 그 사이 회복 수단으로 오른 만큼)가 그대로 전투 시작 체력이 된다.
## 예전에는 여기서 무조건 최대 체력으로 다시 채워, start_boss만 고쳐서는 25%가 전투까지 가지 않았다.
## b는 이미 계산해 둔 빌드(PRun.build)를 넘겨 두 번 계산하지 않게 하는 선택 인자다.
static func boss_start_hp(run: Dictionary, b: Dictionary = {}) -> float:
	var hp_max: float = float(b.get("hp_max", 0.0))
	if hp_max <= 0.0:
		hp_max = float(build(run).hp_max)
	return clampf(float(run.get("hp", hp_max)), 1.0, hp_max)

## 관문 패배. 사람 플레이: 사망 정산(부활 물약이 있으면 다시 관문 앞에 서고, 없으면 회차 종료).
## 다음 날이 있으면 하루를 잃고 다음 날 관문 앞, 마지막 날이면 날짜를 늘리지 않고 같은 날 관문 앞이다(둘 다 물약 1개).
## 무료 상태 복원·무제한 재도전은 없다. 부활해도 관문은 그대로 남아 다음 막이 열리지 않는다.
## 시험 재시도 경로(run.testRetry)에서만 옛 규칙(입장 스냅샷 복구 + 즉시 재도전)을 쓴다 — boss_defeat_retry가 그 몸통이다.
static func boss_defeat(run: Dictionary) -> void:
	if retry_mode(run):
		boss_defeat_retry(run)
		return
	var nb := next_boss(run)
	settle_death(run, { "cause": "boss", "key": "boss:%d:%d" % [boss_entries(run), int(run.get("stage", 0))], "bossId": (String(nb.id) if not nb.is_empty() else "boss") })

## 이 회차에서 관문에 들어간 횟수(사망 정산 중복 방지 키의 재료)
static func boss_entries(run: Dictionary) -> int:
	var e = run.get("bossEntries", null)
	return int((e as Dictionary).get("count", 0)) if typeof(e) == TYPE_DICTIONARY else 0

## 시험·자동 진행 전용: 입장 시 준비 상태로 복구(레벨·경험치·선택·금화 — 전투 중 건너뛰기 금화 반복 악용 방지)
static func boss_defeat_retry(run: Dictionary) -> void:
	run.bossRetries = int(run.get("bossRetries", 0)) + 1
	clear_revive_pending(run) # 재도전 경로는 부활과 섞이지 않는다(옛 규칙대로 완전 회복으로 다시 들어간다)
	if run.get("bossEntry", null) != null:
		var E: Dictionary = (run.bossEntry as Dictionary).duplicate(true)
		run.growth = E.growth
		if E.has("gold"): run.gold = int(E.gold)
		if E.has("services"): run.services = E.services
		if E.has("equipment"): run.equipment = E.equipment
		if E.has("bag"): run.bag = E.bag
		if E.has("equipPlus"): run.equipPlus = (E.equipPlus as Dictionary).duplicate(true) # 장비 강화도 입장 시점으로 돌아간다(재도전이 강화를 복제하지 않는다)
		if E.has("equipSeq"): run.equipSeq = int(E.equipSeq)
		if E.has("forge"): run.forge = int(E.forge)
		if E.has("forgeBySkill"): run.forgeBySkill = (E.forgeBySkill as Dictionary).duplicate(true)
		if E.has("prep"): PConsumables.restore(run, E.prep)
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
	clear_revive_pending(run) # 관문을 넘었으면 부활 표식은 어느 쪽이든 남지 않는다
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

# ---------- 장비 개체(§0·§4, 2026-09-10 사용자 확정 방식) ----------
## 장비는 더 이상 종류 문자열이 아니라 **개체**다. 개체 id = "<타입>#<일련번호>"(예 "hunter_sword#2").
## - 타입은 '#' 앞을 읽는다. **'#'가 없으면 그 문자열 자체가 타입이고 강화 +0이다.**
##   → 옛 저장(종류 문자열만 든 run.equipment·run.bag)이 **변환 없이 그대로** 동작한다. 이 성질을 깨지 말 것.
## - 강화 단계는 run.equipPlus[개체 id]에만 있다. 개체가 사라지면 그 기록도 사라진다(이전·복제 없음).
## - 일련번호(run.equipSeq)는 회차 안에서만 유일하면 된다.
## PCatalog.equipment_def()는 **타입**만 받는다. 개체 id를 넘기기 전에 반드시 equip_type_of를 거칠 것.
const EQUIP_UID_SEP := "#"

## 개체 id → 장비 종류(자료 id). '#'가 없으면 그대로 돌려준다(옛 저장 호환)
static func equip_type_of(uid: String) -> String:
	var i := uid.find(EQUIP_UID_SEP)
	return uid.substr(0, i) if i > 0 else uid

## 이 개체의 강화 단계(0~2). 기록이 없으면 0 — 옛 저장의 장비는 전부 +0이다
static func equip_plus_of(run: Dictionary, uid: String) -> int:
	var m = run.get("equipPlus", null)
	if typeof(m) != TYPE_DICTIONARY:
		return 0
	return int((m as Dictionary).get(uid, 0))

static func equip_plus_map(run: Dictionary) -> Dictionary:
	if typeof(run.get("equipPlus", null)) != TYPE_DICTIONARY:
		run.equipPlus = {}
	return run.equipPlus

## 새 개체 id 발급(구매·제작·드롭에서만 부른다). 일련번호는 회차 안에서만 증가한다
static func equip_new_uid(run: Dictionary, type_id: String) -> String:
	var n := int(run.get("equipSeq", 0)) + 1
	run.equipSeq = n
	return "%s%s%d" % [type_id, EQUIP_UID_SEP, n]

## 화면에 그대로 쓰는 이름("사냥꾼의 검 +1"). 강화가 없으면 이름만
static func equip_display_name(run: Dictionary, uid: String) -> String:
	var nm := equip_name(equip_type_of(uid))
	var p := equip_plus_of(run, uid)
	return "%s +%d" % [nm, p] if p > 0 else nm

## 보유한 장비 개체 전부(장착 + 가방): [{ uid, type, slot, plus, where("equipped"|"bag"), slotName }]
static func equip_instances(run: Dictionary) -> Array:
	var out := []
	for sl in W().equip_slots:
		var slot := String(sl)
		var cur = run.equipment.get(slot, null)
		if cur != null:
			out.append(_equip_inst(run, String(cur), "equipped"))
	for id in run.bag:
		out.append(_equip_inst(run, String(id), "bag"))
	return out

static func _equip_inst(run: Dictionary, uid: String, where: String) -> Dictionary:
	var t := equip_type_of(uid)
	var d := PCatalog.equipment_def(t)
	return { "uid": uid, "type": t, "slot": String(d.get("slot", "")), "plus": equip_plus_of(run, uid),
		"where": where, "name": equip_display_name(run, uid), "def": d }

## 이 **개체**를 정확히 가지고 있는가(장착 또는 가방)
static func has_equip_uid(run: Dictionary, uid: String) -> bool:
	if (run.bag as Array).has(uid):
		return true
	for slot in run.equipment:
		if run.equipment[slot] != null and String(run.equipment[slot]) == uid:
			return true
	return false

## 이 **종류**의 개체를 하나라도 가지고 있는가(상점 중복 진열·중복 구매 차단이 보는 값)
static func owns_equip_type(run: Dictionary, type_id: String) -> bool:
	for id in run.bag:
		if equip_type_of(String(id)) == type_id:
			return true
	for slot in run.equipment:
		if run.equipment[slot] != null and equip_type_of(String(run.equipment[slot])) == type_id:
			return true
	return false

# ---------- 상점(하루 시드 재고)·장비·대장간 ----------
## 옛 이름 유지: 개체 id('#' 포함)를 주면 그 개체를, 종류를 주면 그 종류를 본다.
## 옛 저장은 '#'이 없어 예전과 완전히 같은 판정이 된다
static func owns_equip(run: Dictionary, id: String) -> bool:
	if id.find(EQUIP_UID_SEP) > 0:
		return has_equip_uid(run, id)
	return owns_equip_type(run, id)

static func stock_seed(run: Dictionary, day: int = 0) -> int:
	var d: int = day if day > 0 else int(run.day)
	return (int(run.seed) * 17 + d * 401 + 9) & 0xFFFFFFFF

## 유료 새로고침마다 시드를 바꾼다(같은 날 같은 재고가 다시 나오지 않게). 저장 필드(refresh.count)에서만 나오므로 재접속해도 같다
static func stock_seed_for(run: Dictionary, refreshes: int) -> int:
	return (stock_seed(run) + refreshes * 7919) & 0xFFFFFFFF

## 장비 후보가 지금 막에서 팔리는가(막이 오르면 새 후보가 열린다). minAct가 없는 장비는 항상 열림.
## acts가 아닌 회차(trio·시험실)나 막을 알 수 없으면 제한하지 않는다 — 기존 동작 그대로
static func equip_act_ok(run: Dictionary, id: String) -> bool:
	var d := PCatalog.equipment_def(equip_type_of(id))
	if d.is_empty() or not d.has("minAct"):
		return true
	var a := act_of(run)
	if a.is_empty() or not a.has("id"):
		return true
	return int(a.id) >= int(d.minAct)

## 오늘의 재고: 장비 2(미보유) + 자동기술 또는 E 1 + 출격 준비물 진열. 다시 열거나 불러와도 같다(저장). 방문 상인은 예정된 날 점심부터.
## 재고 후보는 해금 스냅샷(run.unlocks)·막(minAct)을 따르고 제작 전용 장비는 넣지 않는다.
## paid=true면 유료 새로고침이다: 잠근 칸은 그대로 두고 나머지만 다시 뽑으며, 이미 산 칸의 '판매됨' 기록은 유지한다
## (그래서 새로고침으로 같은 장비를 두 번 사거나 산 물건이 되살아나는 일이 없다).
static func refresh_stock(run: Dictionary, paid: bool = false) -> Dictionary:
	var old = run.get("stock", null)
	var same_day: bool = paid and old != null and int((old as Dictionary).get("day", -1)) == int(run.day)
	var refreshes: int = (int((old as Dictionary).refresh.count) + 1) if (same_day and (old as Dictionary).has("refresh")) else 0
	var locked: Array = ((old as Dictionary).get("locked", []) as Array).duplicate() if same_day else []
	var sold: Array = ((old as Dictionary).get("sold", []) as Array).duplicate() if same_day else []
	var keep_eq := []
	var keep_skill = null
	if same_day:
		for id in (old as Dictionary).equipment:
			if locked.has(String(id)) or sold.has(String(id)): # 잠근 칸·이미 산 칸은 자리를 지킨다
				keep_eq.append(String(id))
		if (old as Dictionary).get("skill", null) != null and (locked.has("skill") or sold.has("skill")):
			keep_skill = (old as Dictionary).skill
	var rng := PRng.new(stock_seed_for(run, refreshes))
	var g: Dictionary = run.growth
	var EQ := PCatalog.equipment()
	var pool := []
	for id in EQ:
		if not owns_equip(run, String(id)) and PProfile.run_unlock_ok(run, "equipment", String(id)) and equip_act_ok(run, String(id)) and not keep_eq.has(String(id)) and not PCatalog.equipment_retired(String(id)):
			pool.append(String(id))
	var eq := keep_eq.duplicate()
	while eq.size() < int(SH().stock.equipment) and pool.size() > 0:
		var idx := rng.int_range(0, pool.size() - 1)
		eq.append(pool[idx])
		pool.remove_at(idx)
	var skill = keep_skill
	var W_ := PCatalog.weapons()
	var wpool := []
	for id in W_:
		# can_take_weapon이 역할별 상한을 본다 — 새 구조에서 주무기는 회차 중에 늘지 않으므로 진열되지 않는다
		if bool(W_[id].impl) and PGrowth.can_take_weapon(g, String(id)) and PProfile.run_unlock_ok(run, "weapons", String(id)):
			wpool.append(String(id))
	var es := []
	for id in PCatalog.e_skills():
		if bool(PCatalog.skills()[id].impl) and PProfile.run_unlock_ok(run, "e_skills", String(id)):
			es.append(String(id))
	if skill == null and wpool.size() > 0:
		skill = { "kind": "weapon", "id": wpool[rng.int_range(0, wpool.size() - 1)], "price": int(SH().newSkill) }
	elif skill == null and g.skills.get("e", null) == null and es.size() > 0:
		skill = { "kind": "e", "id": es[rng.int_range(0, es.size() - 1)], "price": int(SH().newE) }
	# 준비물 진열도 같은 시드로(새로고침하면 준비물 목록도 바뀐다). 잠금은 장비·기술 칸에만 건다
	var prep := PConsumables.stock_ids(stock_seed_for(run, refreshes) + 31, int(SH().consumableStock.prep))
	run.stock = { "day": int(run.day), "equipment": eq, "skill": skill, "sold": sold, "locked": locked, "prep": prep,
		"refresh": { "count": refreshes, "price": int(round(float(SH().stockRefresh.base) * pow(float(SH().stockRefresh.mult), refreshes))) } }
	var MV: Dictionary = W().merchant_visits
	var visit := false
	for d in merchant_days(run):
		if int(d) == int(run.day):
			visit = true
	if visit:
		var p2 := []
		for id in EQ:
			if not owns_equip(run, String(id)) and not eq.has(String(id)) and PProfile.run_unlock_ok(run, "equipment", String(id)) and equip_act_ok(run, String(id)) and not PCatalog.equipment_retired(String(id)):
				p2.append(String(id))
		# 무료 휴식권 값은 data/world.json shop.merchantService가 정본이다(사용자 결정: 100). 코드에 숫자를 두지 않는다
		run.merchant = { "day": int(run.day), "fromSlot": int(MV.slot), "equipment": (p2[rng.int_range(0, p2.size() - 1)] if p2.size() > 0 else null), "service": "free_rest", "servicePrice": merchant_service_price("free_rest"), "sold": [] }
	elif not same_day: # 유료 새로고침은 상인 재고를 다시 뽑지 않는다(상인 물건은 하루 1회 확정)
		run.merchant = null
	return run.stock

## 방문 상인 서비스 가격(정본 = data/world.json shop.merchantService). 무료 보상으로 받은 권리에는 청구하지 않는다
static func merchant_service_price(id: String) -> int:
	return int((SH().get("merchantService", {}) as Dictionary).get(id, 0))

# ---------- 상점 재고 새로고침·잠금(2026-09-08 시험값) ----------
## 다음 새로고침 값. 오늘 한 횟수에 따라 오른다(60 → 90 → 135). 하루가 바뀌면 0회부터 다시
static func stock_refresh_cost(run: Dictionary) -> int:
	return int(stock(run).refresh.price)

static func stock_refreshes_today(run: Dictionary) -> int:
	return int(stock(run).refresh.count)

static func stock_refresh_left(run: Dictionary) -> int:
	return maxi(0, int(SH().stockRefresh.maxPerDay) - stock_refreshes_today(run))

## 새로고침할 수 없는 이유(할 수 있으면 ""). 화면·행동 목록이 그대로 쓴다
static func stock_refresh_reason(run: Dictionary) -> String:
	if String(run.phase) != "prep" and String(run.phase) != "boss_prep":
		return "거점에서만"
	if stock_refresh_left(run) <= 0:
		return "오늘 새로고침 한도(%d) 소진 · 내일 아침에 초기화" % int(SH().stockRefresh.maxPerDay)
	if int(run.gold) < stock_refresh_cost(run):
		return "금화 %d 부족" % (stock_refresh_cost(run) - int(run.gold))
	return ""

static func can_refresh_stock(run: Dictionary) -> bool:
	return stock_refresh_reason(run) == ""

## 유료 새로고침: 값을 내고 잠그지 않은 칸만 다시 뽑는다. 실패하면 회차를 전혀 바꾸지 않는다
static func refresh_stock_paid(run: Dictionary) -> bool:
	var why := stock_refresh_reason(run)
	if why != "":
		push_error("새로고침 불가: " + why)
		return false
	var cost := stock_refresh_cost(run)
	run.gold = int(run.gold) - cost
	refresh_stock(run, true)
	add_log(run, "상점 재고 새로고침 (-%d, 오늘 %d회째)" % [cost, stock_refreshes_today(run)])
	return true

## 잠금 대상 키: 장비 id 또는 "skill". 이미 산 칸은 잠글 필요가 없다(자리를 지킨다)
static func stock_lock_reason(run: Dictionary, key: String) -> String:
	var st := stock(run)
	var listed: bool = (st.equipment as Array).has(key) or (key == "skill" and st.get("skill", null) != null)
	if not listed:
		return "재고에 없음"
	if (st.sold as Array).has(key):
		return "이미 구매함(자리 유지)"
	if not (st.locked as Array).has(key) and (st.locked as Array).size() >= int(SH().stockRefresh.lockMax):
		return "잠금은 %d칸까지" % int(SH().stockRefresh.lockMax)
	return ""

static func stock_locked(run: Dictionary, key: String) -> bool:
	return (stock(run).locked as Array).has(key)

## 잠금 토글(값 없음). 켜졌으면 true를 돌려준다
static func toggle_stock_lock(run: Dictionary, key: String) -> bool:
	var st := stock(run)
	if (st.locked as Array).has(key):
		(st.locked as Array).erase(key)
		return false
	if stock_lock_reason(run, key) != "":
		push_error("잠금 불가: " + stock_lock_reason(run, key))
		return false
	(st.locked as Array).append(key)
	return true

static func stock(run: Dictionary) -> Dictionary:
	if run.get("stock", null) == null or int(run.stock.day) != int(run.day):
		refresh_stock(run)
	var st: Dictionary = run.stock
	if not st.has("locked"): # 옛 저장 호환: 새로고침·잠금·준비물 칸이 없던 재고
		st.locked = []
	if not st.has("refresh"):
		st.refresh = { "count": 0, "price": int(SH().stockRefresh.base) }
	if not st.has("prep"):
		st.prep = PConsumables.stock_ids(stock_seed(run) + 31, int(SH().consumableStock.prep))
	return st

static func merchant_open(run: Dictionary) -> bool:
	var m = run.get("merchant", null)
	return m != null and int(m.day) == int(run.day) and slot_index(run) >= int(m.fromSlot)

## 아래 세 함수는 개체 id도 종류도 받는다(안에서 타입으로 바꾼다)
static func equip_price(id: String) -> int: return int(SH().price[String(PCatalog.equipment_def(equip_type_of(id)).slot)])
## 옛 고정 판매가표(35/30/30). 지금 판매 규칙은 sell_value가 정본이며 이 함수는 옛 표를 읽는 자리(도구·대조)에만 남아 있다
static func sell_price(id: String) -> int: return int(SH().sellPrice[String(PCatalog.equipment_def(equip_type_of(id)).slot)])
static func equip_name(id: String) -> String: return String(PCatalog.equipment_def(equip_type_of(id)).get("name", equip_type_of(id)))

# ---------- 판매(2026-09-09 확정: 구매액의 절반 · 2026-09-10 확정: + 강화 비용의 50%) ----------
## 판매가는 **두 값을 따로 세어 더한다**:
##   ① 기본가  = floor(실제 지불액 × shop.sellRate)          — 산 적이 없으면 정상 구매가를 지불액 자리에 쓴다
##   ② 강화 환급 = floor(누적 강화 비용 × shop.equipUpgrade.sellRefundRate)
## 지금 자료 기준 ②는 +0 0금 · +1 35금 · +2 100금이다. **비율·비용은 전부 자료가 정본이고 코드에 숫자를 두지 않는다.**
## 중복 환급이 없는 이유: 강화 단계는 개체 id 하나(run.equipPlus)에만 붙고, 제작으로 재료를 태우면 그 기록이
## 함께 지워지며(craft), 완성품은 계승 단계만 갖는다. 제작은 강화 비용을 다시 청구하지도, 환급하지도 않는다.
## 장비 개체별 실제 지불 금액표. 구매할 때만 적는다(할인가로 샀으면 할인가가 남아 싸게 사서 비싸게 파는 일이 없다).
static func paid_map(run: Dictionary) -> Dictionary:
	if typeof(run.get("paidFor", null)) != TYPE_DICTIONARY:
		run.paidFor = {}
	return run.paidFor

## 이 장비를 실제로 얼마에 샀는가. 산 적이 없으면 -1(드롭·제작·옛 저장)
static func paid_for(run: Dictionary, id: String) -> int:
	var m := paid_map(run)
	if not m.has(id):
		return -1
	var e = m[id]
	return int((e as Dictionary).get("price", -1)) if typeof(e) == TYPE_DICTIONARY else int(e)

## 구매 기록(구매 확정에서만 부른다). from = "stock" | "merchant"
static func note_paid(run: Dictionary, id: String, price: int, from: String) -> void:
	paid_map(run)[id] = { "price": maxi(0, price), "from": from, "day": int(run.get("day", 1)) }

## 판매 비율의 정본은 **자료**다(코드에 숫자를 두지 않는다).
## 없거나 0~1 밖이면 -1을 돌려준다 — 부르는 쪽이 판매를 막는다(잘못된 자료로 금화가 먼저 늘지 않게).
static func _rate_of(d: Dictionary, key: String) -> float:
	if not d.has(key):
		return -1.0
	var v = d[key]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return -1.0
	var f := float(v)
	return f if f >= 0.0 and f <= 1.0 else -1.0

## 지불액에 곱하는 비율(data/world.json shop.sellRate). 없으면 -1
static func sell_rate() -> float:
	return _rate_of(SH(), "sellRate")

## 강화 비용에 곱하는 환급 비율(data/world.json shop.equipUpgrade.sellRefundRate). 없으면 -1
static func sell_refund_rate() -> float:
	return _rate_of(equip_upgrade_rules(), "sellRefundRate")

## 자료가 성했는가(둘 다 있어야 판매 금액을 셀 수 있다)
static func sell_rates_ok() -> bool:
	return sell_rate() >= 0.0 and sell_refund_rate() >= 0.0

## 판매 **기본가**: 실제 지불 금액 × shop.sellRate(정수 내림).
## 구매액이 없는 장비(드롭·제작·옛 저장)는 **정상 기준 구매가**를 지불액 자리에 쓴다(docs/DEATH_AND_ECONOMY.md).
## 강화 비용 환급은 여기에 **들어 있지 않다** — sell_upgrade_refund가 따로 센다(사용자 확정 2026-09-10).
static func sell_base_value(run: Dictionary, id: String) -> int:
	var rate := sell_rate()
	if rate < 0.0:
		push_error("판매 비율 자료(shop.sellRate)가 없다: 판매 금액을 셀 수 없다")
		return 0
	var p := paid_for(run, id)
	if p < 0:
		p = equip_price(id)
	return int(floor(float(p) * rate))

## 판매 **강화 환급**: 이 개체가 지금 단계까지 쌓은 누적 강화 비용 × sellRefundRate(정수 내림).
## 단계는 개체 하나에만 붙으므로(run.equipPlus) 재료로 태운 개체와 완성품이 같은 비용을 두 번 돌려주지 않는다 —
## 제작으로 **계승된** 단계도 완성품 한 곳에서만 환급된다.
static func sell_upgrade_refund(run: Dictionary, id: String) -> int:
	var rate := sell_refund_rate()
	if rate < 0.0:
		push_error("강화 환급 비율 자료(shop.equipUpgrade.sellRefundRate)가 없다")
		return 0
	return int(floor(float(equip_upgrade_total_cost(equip_plus_of(run, id))) * rate))

## 판매 금액 = 기본가 + 강화 환급. 두 값을 **따로 세어 더한다**(§판매, 사용자 확정 2026-09-10)
static func sell_value(run: Dictionary, id: String) -> int:
	return sell_base_value(run, id) + sell_upgrade_refund(run, id)

## 판매 근거 문자열("paid" = 실제 지불액 기준 / "list" = 정상 기준 구매가 기준)
static func sell_basis(run: Dictionary, id: String) -> String:
	return "paid" if paid_for(run, id) >= 0 else "list"

## 확인 창에 그대로 쓰는 견적(회차를 전혀 바꾸지 않는다). 화면은 이 값만 보여 주고 확정은 sell_equipment가 한다.
## { id, name, slot, gold(받을 금액 = base + refund), base, refund, upgradeSpent, plus,
##   paid(-1 = 구매액 없음), basis, equipped, unequips, hpMax, hpMaxAfter, hp, hpAfter, goldAfter, can, reason }
static func sell_quote(run: Dictionary, id: String) -> Dictionary:
	var d := PCatalog.equipment_def(equip_type_of(id))
	if d.is_empty():
		return { "id": id, "can": false, "reason": "없는 장비", "gold": 0 }
	if not sell_rates_ok(): # 자료가 비었으면 금액을 셀 수 없다 — 팔 수 없다고 답한다(금화가 먼저 늘지 않게)
		return { "id": id, "can": false, "reason": "판매 비율 자료가 없습니다", "gold": 0, "base": 0, "refund": 0 }
	var slot := String(d.slot)
	var equipped: bool = run.equipment.get(slot, null) != null and String(run.equipment[slot]) == id
	var base_gold := sell_base_value(run, id)
	var refund := sell_upgrade_refund(run, id)
	var gold := base_gold + refund
	var hp_max := float(build(run).hp_max)
	var hp_max_after := hp_max
	if equipped: # 장착 중 판매는 해제를 포함한다 — 최대 체력이 줄면 현재 체력도 잘린다
		var dup: Dictionary = run.duplicate() # 얕은 복제 + 장비 칸만 따로 복사(PBuild.derive는 읽기만 한다)
		dup.equipment = (run.equipment as Dictionary).duplicate()
		dup.equipment[slot] = null
		hp_max_after = float(PBuild.derive(dup).hp_max)
	var owned := owns_equip(run, id)
	return {
		"id": id, "name": equip_display_name(run, id), "slot": slot, "type": equip_type_of(id), "plus": equip_plus_of(run, id),
		"gold": gold, "price": gold, # price는 옛 행동 목록 항목(data.price)을 읽던 자리를 위한 같은 값의 별칭이다
		"base": base_gold, "refund": refund,                       # 판매가를 가르는 두 값(지불액의 절반 / 강화 비용 환급)
		"upgradeSpent": equip_upgrade_total_cost(equip_plus_of(run, id)), # 이 개체에 실제로 들어간 누적 강화 비용
		"paid": paid_for(run, id), "basis": sell_basis(run, id),
		"equipped": equipped, "unequips": equipped,
		"hp": float(run.hp), "hpAfter": minf(float(run.hp), hp_max_after), "hpMax": hp_max, "hpMaxAfter": hp_max_after,
		"goldAfter": int(run.gold) + gold,
		"can": owned, "reason": "" if owned else "보유하지 않은 장비",
		"text": "%s을(를) %d금에 판매할까요?%s%s" % [equip_display_name(run, id), gold, " (장착 중이라 해제됩니다)" if equipped else "",
			" · 강화 +%d도 함께 사라집니다(되돌릴 수 없습니다 — 강화 비용 %d금 중 %d금을 되돌려 받습니다)" % [equip_plus_of(run, id), equip_upgrade_total_cost(equip_plus_of(run, id)), refund] if equip_plus_of(run, id) > 0 else ""],
	}

static func can_sell_equipment(run: Dictionary, id: String) -> bool:
	return bool(sell_quote(run, id).can)

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

## 구매: 즉시 장착(equip=true) 또는 보관. 같은 종류 중복 구매 불가.
## 재고 id는 **종류**이고, 사면 그 자리에서 **새 개체 id**를 발급한다(§4의 개체 귀속 강화가 붙을 자리)
static func buy_equipment(run: Dictionary, id: String, equip: bool, from: String = "stock") -> bool:
	if not can_buy_equipment(run, id, from):
		push_error("구매 불가: " + id)
		return false
	var paid := equip_price_for(run, id, from)
	run.gold = int(run.gold) - paid
	var uid := equip_new_uid(run, equip_type_of(id))
	note_paid(run, uid, paid, from) # 할인 구매도 실제 지불액을 남긴다(판매 차익 방지). 기록은 개체별이다
	if has_service(run, "shop_discount"):
		use_service(run, "shop_discount")
	var target: Dictionary = run.merchant if from == "merchant" else stock(run)
	(target.sold as Array).append(id) # 재고의 '판매됨'은 종류로 남긴다(재고 목록이 종류이므로)
	(run.bag as Array).append(uid)
	if equip:
		equip_item(run, uid)
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

## 장착: id는 **가방에 있는 개체 id**다. 슬롯에 있던 개체는 가방으로 간다(강화는 개체를 따라 그대로 남는다)
static func equip_item(run: Dictionary, id: String) -> bool:
	var d: Dictionary = PCatalog.equipment_def(equip_type_of(id))
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

## 판매 확정(확인 창의 '예'). expect_gold >= 0이면 견적과 같을 때만 실행한다 —
## 확인 창을 띄운 사이에 값이 바뀌었거나(저장 복구·다른 경로) 두 번 눌렸으면 아무것도 하지 않는다.
## 두 번째 호출은 이미 보유하지 않으므로 실패한다(금화·가방 복제 없음).
static func sell_equipment(run: Dictionary, id: String, expect_gold: int = -1) -> bool:
	var q := sell_quote(run, id)
	if not bool(q.can):
		push_error("판매 불가(%s): %s" % [id, String(q.get("reason", ""))])
		return false
	if expect_gold >= 0 and expect_gold != int(q.gold):
		push_error("견적이 바뀌었다(%d → %d): 판매 취소" % [expect_gold, int(q.gold)])
		return false
	var plus_sold := equip_plus_of(run, id)
	for s in W().equip_slots:
		if run.equipment[s] != null and String(run.equipment[s]) == id:
			run.equipment[s] = null
	(run.bag as Array).erase(id)
	paid_map(run).erase(id) # 개체가 사라졌으니 지불 기록도 사라진다(다시 사면 그때 값이 다시 적힌다)
	equip_plus_map(run).erase(id) # 강화도 개체와 함께 사라진다(다른 장비로 옮겨가지 않는다)
	clamp_hp(run)
	run.gold = int(run.gold) + int(q.gold)
	add_log(run, "%s 판매 +%d%s%s" % [equip_name(id), int(q.gold), " (장착 해제)" if bool(q.equipped) else "",
		" (강화 +%d 소멸 · 기본 %d + 강화 환급 %d)" % [plus_sold, int(q.base), int(q.refund)] if plus_sold > 0 else ""])
	return true

## 빈 슬롯 획득: 새 자동기술 / 새 E (Lv1, 개조·변형 없음)
static func can_buy_skill(run: Dictionary) -> bool:
	var st := stock(run)
	var g: Dictionary = run.growth
	if st.get("skill", null) == null or (st.sold as Array).has("skill"):
		return false
	var sk: Dictionary = st.skill
	if String(sk.kind) == "weapon":
		return PGrowth.can_take_weapon(g, String(sk.id)) and int(run.gold) >= int(sk.price)
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
##
## **주무기 자리에는 주무기만, 보조 자리에는 보조만 나온다**(새 구조 v2, 2026-09-09 사용자 지시).
## 전에는 후보에 모든 자동기술이 섞여 나와서, 주무기(Lv5·개조 2)를 보조로 바꾸면
## 보조가 Lv5·개조 2개가 되고(상한은 Lv3·개조 1) 주무기가 0개, 보조가 3개인 회차가 됐다.
## 옛 저장(v1)은 옛 규칙 그대로 아무 자동기술로나 바꿀 수 있다(6절: 옛 회차는 옛 구조로 끝까지).
static func swap_quote(run: Dictionary, slot: String, index: int = 0) -> Dictionary:
	var g: Dictionary = run.growth
	var cur = null
	if slot == "e":
		cur = g.skills.get("e", null)
	elif index >= 0 and index < (g.weapons as Array).size():
		cur = g.weapons[index]
	if cur == null:
		return {}
	# 장비 기술이 든 칸은 상점 '교체'의 대상이 아니다(§5: 레벨업·개조 불가 · 장비를 바꿔서 얻고 버린다).
	# 여기서 막지 않으면 유료 교체가 장비 기술을 일반 기술로 바꿔 창고 경로에 복제해 넣게 된다
	if slot == "e" and PGrowth.is_equip_skill(String(cur.id)):
		return {}
	var mods: int = (1 if cur.get("variant", null) != null else 0) if slot == "e" else (cur.mods as Array).size()
	var SW: Dictionary = SH().swap
	var price := int(SW.base) + (int(cur.level) - 1) * int(SW.perLevel) + mods * int(SW.perMod)
	var options := []
	var role := ""
	if slot == "e":
		for id in PCatalog.e_skills():
			if bool(PCatalog.skills()[id].impl) and String(id) != String(cur.id) and PProfile.run_unlock_ok(run, "e_skills", String(id)):
				options.append(String(id))
	else:
		var W_ := PCatalog.weapons()
		var want_main: bool = PCatalog.is_main_weapon(String(cur.id))
		var strict: bool = PGrowth.is_v2(g)
		role = "main" if want_main else "support"
		for id in W_:
			if not bool(W_[id].impl) or not PGrowth.weapon_of(g, String(id)).is_empty():
				continue
			if not PProfile.run_unlock_ok(run, "weapons", String(id)):
				continue
			if strict and PCatalog.is_main_weapon(String(id)) != want_main:
				continue # 주무기 ↔ 보조 교차 교체 금지(후보 단계에서 아예 제시하지 않는다)
			options.append(String(id))
	return { "slot": slot, "index": index, "current": cur, "level": int(cur.level), "modCount": mods, "price": price, "options": options,
		"role": role, "levelCap": (PGrowth.level_cap(g, String(cur.id)) if slot != "e" else 0),
		"modCap": (PGrowth.mod_cap(g, String(cur.id)) if slot != "e" else 1),
		"affordable": int(run.gold) >= price }

## 교체 확정(마지막 단계에서만 차감·교체). 새 개조/변형은 새 기술 목록에서 modCount만큼. 실패 시 -1
static func apply_swap(run: Dictionary, slot: String, index: int, new_id: String, new_mods: Array = []) -> int:
	var q := swap_quote(run, slot, index)
	if q.is_empty() or not (q.options as Array).has(new_id):
		push_error("교체 불가")
		return -1
	if int(run.gold) < int(q.price):
		push_error("금화 부족")
		return -1
	var g: Dictionary = run.growth
	# **확정에서도 다시 막는다.** 후보 목록을 지나 들어와도(옛 화면·저장된 조작·도구) 거부한다.
	if slot != "e" and PGrowth.is_v2(g) and PCatalog.is_main_weapon(new_id) != PCatalog.is_main_weapon(String(q.current.id)):
		push_error("주무기 자리와 보조 자리는 서로 교체할 수 없습니다: %s → %s" % [String(q.current.id), new_id])
		return -1
	# 레벨·개조 수는 새 자리의 상한을 넘지 않는다(같은 역할끼리면 상한이 같아 값이 바뀌지 않는다)
	var keep_lv: int = int(q.level) if slot == "e" else mini(int(q.level), PGrowth.level_cap(g, new_id))
	var keep_mods: int = int(q.modCount) if slot == "e" else mini(int(q.modCount), PGrowth.mod_cap(g, new_id))
	var nm: Array = new_mods.slice(0, keep_mods)
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
		g.weapons[index] = { "id": new_id, "level": keep_lv, "mods": mods_out }
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

## 자동기술별 대장간 강화 단계(2026-09-08 시험값). 옛 저장(전체 강화 run.forge)은 모든 기술이 그 단계인 것으로 읽는다
static func forge_level_of(run: Dictionary, weapon_id: String) -> int:
	var by = run.get("forgeBySkill", null)
	if typeof(by) == TYPE_DICTIONARY:
		return int((by as Dictionary).get(weapon_id, 0))
	return int(run.get("forge", 0))   # 옛 저장 호환: 전체 강화 단계를 그대로 본다

## 그 회차에서 지금까지 산 강화 횟수(비용 단계는 회차 전체에서 이어진다 — 기술마다 처음부터 싸게 시작하지 않는다)
static func forge_bought(run: Dictionary) -> int:
	var by = run.get("forgeBySkill", null)
	if typeof(by) != TYPE_DICTIONARY:
		return int(run.get("forge", 0))
	var n := 0
	for k in (by as Dictionary):
		n += int((by as Dictionary)[k])
	return n

## 대장간 다음 강화 {lv, cost, afterBoss, open, affordable, weaponId, weaponLv}. 최대면 {}
## weapon_id를 주면 그 자동기술의 다음 단계를 본다. 비어 있으면 첫 자동기술 기준(옛 호출 호환)
static func forge_next(run: Dictionary, weapon_id: String = "") -> Dictionary:
	var F: Array = SH().forge
	var wid := weapon_id
	if wid == "":
		var ws: Array = run.get("growth", {}).get("weapons", [])
		wid = String(ws[0].id) if ws.size() > 0 else ""
	var bought: int = forge_bought(run)
	if bought >= F.size():
		return {}
	var wlv: int = forge_level_of(run, wid)
	if wlv >= int(SH().get("forgePerSkillMax", F.size())):
		return {}
	var f: Dictionary = F[bought]
	return { "lv": int(f.lv), "cost": int(f.cost), "afterBoss": int(f.afterBoss),
		"open": (run.get("bossesDone", []) as Array).size() >= int(f.afterBoss),
		"affordable": int(run.gold) >= int(f.cost), "weaponId": wid, "weaponLv": wlv + 1 }

static func forge_upgrade(run: Dictionary, weapon_id: String = "") -> bool:
	var F := forge_next(run, weapon_id)
	if F.is_empty() or not bool(F.open) or not bool(F.affordable):
		push_error("강화 불가")
		return false
	var wid := String(F.weaponId)
	if wid == "":
		push_error("강화할 자동기술 없음")
		return false
	run.gold = int(run.gold) - int(F.cost)
	# 새 규칙: 고른 자동기술 하나만 오른다. 옛 저장이면 이 시점에 무기별 표로 옮긴다(잃는 것 없음)
	if typeof(run.get("forgeBySkill", null)) != TYPE_DICTIONARY:
		var mig := {}
		var lv0: int = int(run.get("forge", 0))
		for w0 in run.get("growth", {}).get("weapons", []):
			mig[String(w0.id)] = lv0
		run.forgeBySkill = mig
	(run.forgeBySkill as Dictionary)[wid] = forge_level_of(run, wid) + 1
	run.forge = int(F.lv)   # 옛 필드는 '산 횟수' 표시용으로 유지(저장 호환)
	add_log(run, "%s 강화 %d단계 (-%d)" % [String(PCatalog.weapon(wid).name), int((run.forgeBySkill as Dictionary)[wid]), int(F.cost)])
	return true

# ---------- 장비 강화(§4, 2026-09-10). 자동기술 강화(forge_*)와 **다른 기능**이다 ----------
## 규칙(사용자 확정): +0 → +1 → +2 두 단계. +1은 첫 관문 돌파 후, +2는 두 번째 관문 돌파 후.
## 금화 소비 · 확정 성공 · **시간 소모 없음.** 비용·상승량은 data/world.json shop.equipUpgrade의 **시험값**이다.
## 강화는 **그 개체**(run.equipPlus[개체 id])에만 붙는다: 가방에 넣어도 유지, 다른 장비로 옮겨가지 않는다.
## 무엇이 오르는지는 장비 자료의 upgrade 표가 정한다 — **횟수·단계·지속·재사용·무적 시간은 넣지 않는다**(§4 금지 목록).
static func equip_upgrade_rules() -> Dictionary:
	return SH().get("equipUpgrade", { "steps": [] })

## 이 회차에서 지금 살 수 있는 최대 강화 단계(돌파한 관문 수로 열린다)
static func equip_upgrade_open_max(run: Dictionary) -> int:
	var steps: Array = equip_upgrade_rules().get("steps", [])
	var done: int = (run.get("bossesDone", []) as Array).size()
	var n := 0
	for s in steps:
		if typeof(s) != TYPE_DICTIONARY or not _upgrade_step_ok(s):
			continue # 자료가 망가진 칸은 열린 것으로 세지 않는다
		if done >= int((s as Dictionary).afterBoss):
			n = int((s as Dictionary).plus)
	return n

## 효과 사전에서 upgrade 경로("bigHit.reduce")가 가리키는 값. 없으면 null
static func _eff_at_path(eff: Dictionary, path: String) -> Variant:
	var node: Variant = eff
	for k in path.split(".", false):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(String(k)):
			return null
		node = (node as Dictionary)[String(k)]
	return node if typeof(node) == TYPE_FLOAT or typeof(node) == TYPE_INT else null

## 이 장비 종류를 from_plus → to_plus 로 올리면 **실제로 값이 달라지는 항목**들(upgrade 표의 경로 이름).
## 표가 없거나, 표에만 있고 eff에 그 경로가 없거나, 값이 같으면 빈 배열이다.
static func equip_upgrade_diff(type_id: String, from_plus: int, to_plus: int) -> Array:
	var out: Array = []
	var d := PCatalog.equipment_def(type_id)
	if d.is_empty():
		return out
	var up: Dictionary = d.get("upgrade", {})
	if up.is_empty():
		return out
	var a := PCatalog.equipment_eff(type_id, from_plus)
	var b := PCatalog.equipment_eff(type_id, to_plus)
	for path in up:
		var p := String(path)
		var va = _eff_at_path(a, p)
		var vb = _eff_at_path(b, p)
		if va == null or vb == null:
			continue # 표에만 있고 실제 효과에는 없는 경로 — 아무것도 올리지 않는다
		if not is_equal_approx(float(va), float(vb)):
			out.append(p)
	return out

## **강화로 실제로 달라지는 것이 있는 장비인가**(사용자 확정 2026-09-10: 효과 없는 유료 강화는 결함이다).
## 거짓이면 견적(equip_upgrade_next)이 사유를 돌려주고 can_upgrade_equip·upgrade_equip이 모두 거부한다.
## 폐기 2종(반격 방패·연계 방패)도 강화표가 없어 여기서 막힌다 — 다만 **이미 가진 개체를 지우거나 효과를 빼지는 않는다**.
static func equip_upgrade_effect_ok(type_id: String, from_plus: int, to_plus: int) -> bool:
	return not equip_upgrade_diff(type_id, from_plus, to_plus).is_empty()

## 강화 단계표 한 칸이 성한가(plus·cost·afterBoss가 다 있고 값이 말이 되는가).
## 자료가 망가졌으면 금화·단계를 건드리기 **전에** 막는다(원자성).
static func _upgrade_step_ok(s: Dictionary) -> bool:
	for k in ["plus", "cost", "afterBoss"]:
		if not s.has(k):
			return false
		var v = s[k]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return false
	return int(s.cost) >= 0 and int(s.plus) > 0 and int(s.afterBoss) >= 0

## 다음 강화 견적. **최대 단계이거나 장비 정의가 없으면 {}**(옛 동작 그대로).
## 강화할 수 없는 사유가 있으면 빈 사전이 아니라 can=false + reason 을 돌려준다.
## { uid, type, name, plus, next, cost, afterBoss, open, affordable, can, reason, changes }
static func equip_upgrade_next(run: Dictionary, uid: String) -> Dictionary:
	var steps: Array = equip_upgrade_rules().get("steps", [])
	var cur := equip_plus_of(run, uid)
	var tid := equip_type_of(uid)
	var d := PCatalog.equipment_def(tid)
	if d.is_empty() or steps.is_empty() or cur >= steps.size():
		return {}
	var owned := has_equip_uid(run, uid)
	var blocked := { "uid": uid, "type": tid, "name": equip_display_name(run, uid), "plus": cur, "next": cur,
		"cost": 0, "afterBoss": 0, "open": false, "affordable": false, "can": false, "reason": "", "changes": [] }
	if typeof(steps[cur]) != TYPE_DICTIONARY or not _upgrade_step_ok(steps[cur]):
		blocked.reason = "강화 자료가 잘못되었습니다(shop.equipUpgrade.steps)"
		return blocked
	var s: Dictionary = steps[cur]
	# 강화로 **아무 값도 달라지지 않는 장비**는 여기서 막는다 — 금화만 받고 아무것도 안 주는 일이 없게
	var changes := equip_upgrade_diff(tid, cur, int(s.plus))
	if changes.is_empty():
		blocked.next = int(s.plus)
		blocked.afterBoss = int(s.afterBoss)
		blocked.reason = "이 장비는 강화할 수 없습니다(강화로 오르는 기본 능력치가 없습니다)"
		return blocked
	var done: int = (run.get("bossesDone", []) as Array).size()
	var open: bool = done >= int(s.afterBoss)
	var cost := int(s.cost)
	var reason := ""
	if not owned:
		reason = "보유하지 않은 장비"
	elif not open:
		reason = "관문 %d개를 돌파해야 열립니다(지금 %d개)" % [int(s.afterBoss), done]
	elif int(run.gold) < cost:
		reason = "금화 %d 부족" % (cost - int(run.gold))
	return { "uid": uid, "type": tid, "name": equip_display_name(run, uid), "plus": cur, "next": int(s.plus),
		"cost": cost, "afterBoss": int(s.afterBoss), "open": open, "affordable": int(run.gold) >= cost,
		"can": owned and open and int(run.gold) >= cost, "reason": reason, "changes": changes }

static func can_upgrade_equip(run: Dictionary, uid: String) -> bool:
	var q := equip_upgrade_next(run, uid)
	return not q.is_empty() and bool(q.can)

## 강화 확정(확인 창의 '예'). expect_cost >= 0이면 견적과 같을 때만 실행한다(두 번 눌러도 두 번 차감되지 않는다).
## 시간은 쓰지 않는다. **원자적이다**: 검사가 전부 통과한 뒤에야 금화와 단계를 함께 바꾼다 —
## 자료가 비었거나 강화로 아무 값도 달라지지 않는 장비면 금화가 먼저 빠지는 일이 없다
static func upgrade_equip(run: Dictionary, uid: String, expect_cost: int = -1) -> bool:
	var q := equip_upgrade_next(run, uid)
	if q.is_empty() or not bool(q.can):
		push_error("장비 강화 불가(%s): %s" % [uid, String(q.get("reason", "최대 단계"))])
		return false
	if expect_cost >= 0 and expect_cost != int(q.cost):
		push_error("견적이 바뀌었다(%d → %d): 강화 취소" % [expect_cost, int(q.cost)])
		return false
	# 확정 직전 마지막 확인: 효과가 실제로 달라지는가(견적과 확정이 같은 판정을 쓴다)
	if not equip_upgrade_effect_ok(String(q.type), int(q.plus), int(q.next)):
		push_error("장비 강화 불가(%s): 강화로 오르는 기본 능력치가 없다" % uid)
		return false
	run.gold = int(run.gold) - int(q.cost)
	equip_plus_map(run)[uid] = int(q.next)
	clamp_hp(run) # 최대 체력이 오르는 장비도 있다. 늘어난 만큼 회복하지는 않는다(기존 규칙 그대로)
	add_log(run, "%s 강화 +%d → +%d (-%d금)" % [equip_name(uid), int(q.plus), int(q.next), int(q.cost)])
	return true

## 지금 강화할 수 있는 장비 개체 목록(장착 + 가방). 화면이 그대로 그린다
static func equip_upgrade_options(run: Dictionary) -> Array:
	var out := []
	for inst in equip_instances(run):
		var e: Dictionary = inst
		var q := equip_upgrade_next(run, String(e.uid))
		e["next"] = q
		out.append(e)
	return out

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
		if PCatalog.equipment_retired(cid):
			continue # 폐기 장비(§1): 제작 후보에서 뺀다. 이미 가진 개체는 건드리지 않는다
		if not PProfile.run_unlock_ok(run, "recipes", cid):
			continue
		out.append(craft_option(run, cid))
	return out

## 제작에 쓸 재료 장비 **개체**를 고른다: 같은 종류가 여럿이면 **강화가 가장 낮은 것**부터,
## 같은 강화면 가방을 장착보다 먼저 쓴다.
##
## 계승이 확정된 뒤(2026-09-10) 이 규칙을 **다시 봤다**. 그대로 둔다. 이유:
## 강화 비용표(shop.equipUpgrade.steps)는 장비 종류와 무관하게 단계마다 같은 값이다.
## 그래서 '재료를 강화한 뒤 제작'과 '제작한 뒤 완성품을 강화'의 **총 강화 지출이 같다**(craft_cost_parity).
## → 낮은 개체를 태워도 플레이어가 잃는 금화가 없다. 대신 비싸게 강화한 개체는 **손에 남는다**.
## 반대로 높은 쪽을 태우면 남는 개체가 +0이 되어, 같은 단계를 되찾으려면 이미 낸 값을 다시 내야 한다.
## → 낮은 쪽 우선이 더 안전하다. 다만 **무엇을 태우는지는 반드시 확인창에 보여 준다**(uid·단계·위치를 함께 돌려준다).
##
## 돌려주는 값: { where("bag"|"equipped"|""), uid, plus, slot?, count(같은 종류 보유 수), others[{uid,plus,where}] }
static func craft_pick_uid(run: Dictionary, type_id: String) -> Dictionary:
	var all: Array = []
	for id in run.bag:
		var uid := String(id)
		if equip_type_of(uid) == type_id:
			all.append({ "where": "bag", "uid": uid, "plus": equip_plus_of(run, uid) })
	for slot in run.equipment:
		if run.equipment[slot] == null:
			continue
		var uid2 := String(run.equipment[slot])
		if equip_type_of(uid2) == type_id:
			all.append({ "where": "equipped", "uid": uid2, "plus": equip_plus_of(run, uid2), "slot": String(slot) })
	var best := { "where": "", "uid": "", "plus": 0, "count": all.size(), "others": [] }
	for e in all:
		var cand: Dictionary = e
		if String(best.where) == "" or int(cand.plus) < int(best.plus):
			best = cand.duplicate(true)
	if String(best.where) == "":
		return { "where": "", "uid": "", "plus": 0, "count": 0, "others": [] }
	var others: Array = []
	for e2 in all:
		var o: Dictionary = e2
		if String(o.uid) != String(best.uid):
			others.append(o)
	best["count"] = all.size()
	best["others"] = others
	return best

## 이 제작법의 **결과가 물려받을 강화 단계**(2026-09-10 사용자 확정: 재료의 강화를 결과에 계승한다).
## 재료 장비가 둘 이상인 제작법이면 **가장 높은 단계**를 물려준다 — 이미 낸 강화 비용을 다시 받지 않기 위해서다.
## (지금 활성 제작법은 모두 재료 장비가 하나뿐이라 '그 재료의 단계' 그대로다.)
static func craft_inherit_plus(run: Dictionary, id: String) -> int:
	var rc := PCatalog.recipe(id)
	var p := 0
	for eid in rc.get("equipment", []):
		var pick := craft_pick_uid(run, String(eid))
		if String(pick.where) != "":
			p = maxi(p, int(pick.plus))
	return p

## 어떤 장비든 +0에서 이 단계까지 올리는 **총 강화 지출**(비용표는 장비 종류와 무관하다).
## 확인창이 '제작 뒤에 올려도 같은 값'이라고 적을 때 쓰는 숫자다 — 화면이 따로 계산하지 않는다.
static func equip_upgrade_total_cost(plus: int) -> int:
	var steps: Array = equip_upgrade_rules().get("steps", [])
	var acc := 0
	for s in steps:
		if int((s as Dictionary).plus) <= plus:
			acc += int((s as Dictionary).cost)
	return acc

static func craft_option(run: Dictionary, id: String, with_preview: bool = true) -> Dictionary:
	var d: Dictionary = PCatalog.crafted_equipment()[id]
	var rc: Dictionary = d.recipe
	var ings := []
	var missing := []
	for eid in rc.get("equipment", []):
		var e := String(eid) # 제작법은 **종류**로 적는다. 실제로 소비할 개체는 craft_pick_uid가 고른다
		var pick := craft_pick_uid(run, e)
		var where := String(pick.get("where", ""))
		var nm := equip_name(e)
		# uid·plus·count·others를 그대로 올려 준다 — 확인창이 **어느 개체를 태우고 무엇이 남는지** 적을 수 있게(사용자 확정 2026-09-10)
		ings.append({ "kind": "equipment", "id": e, "name": nm, "n": 1, "have": 1 if where != "" else 0, "where": where,
			"uid": String(pick.get("uid", "")), "plus": int(pick.get("plus", 0)),
			"slot": String(pick.get("slot", "")), "count": int(pick.get("count", 0)), "others": pick.get("others", []) })
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
	var inherit := craft_inherit_plus(run, id)
	var opt := { "id": id, "def": d, "recipe": rc, "fee": fee, "affordable": affordable, "ingredients": ings, "missing": missing,
		"can": missing.is_empty(), "owned": owned, "preview": {},
		"inherit": inherit,                                          # 완성품이 물려받을 강화 단계
		"inheritPaid": equip_upgrade_total_cost(inherit) }            # 그 단계까지 이미 낸 강화 지출(다시 받지 않는다)
	if bool(opt.can) and with_preview:
		var dup: Dictionary = run.duplicate(true)
		var before := PBuild.derive(dup)
		craft(dup, id, true, true)
		opt.preview = { "before": before, "after": PBuild.derive(dup) }
	return opt

static func can_craft(run: Dictionary, id: String, use_equipped: bool = true) -> bool:
	if not PCatalog.crafted_equipment().has(id) or not PProfile.run_unlock_ok(run, "recipes", id):
		return false
	if PCatalog.equipment_retired(id):
		return false # 후보 목록을 지나 들어와도(옛 화면·저장된 조작·도구) 폐기 장비는 새로 만들지 못한다
	var o := craft_option(run, id, false)
	if not bool(o.can):
		return false
	if not use_equipped:
		for ing in o.ingredients:
			if String(ing.kind) == "equipment" and String(ing.where) == "equipped":
				return false
	return true

## 제작 확정(원자적: 검증 → 소비 → 생성 → 가방/장착). 저장은 호출자가 1회. use_equipped=false면 장착 중인 재료 장비는 쓰지 않는다(실패).
## 회차 강화(forge)는 장비 인스턴스와 무관하므로 그대로. 분해·환급 없음. 실패 시 아무것도 바꾸지 않는다.
##
## **강화 계승(2026-09-10 사용자 확정)**: 재료 장비의 강화 단계를 완성품에 물려준다(+0→+0 · +1→+1 · +2→+2).
## - 이미 낸 강화 비용을 **다시 받지 않는다**(제작 수수료·재료는 별개다).
## - 관문 개방 조건(equip_upgrade_next의 afterBoss)은 **다시 보지 않는다** — 계승은 구매가 아니라 이월이고,
##   그 단계는 이미 그 조건을 지나 산 것이기 때문이다.
## - 계승은 **제작에서만** 일어난다. 아무 장비 사이의 강화 이전 기능으로 넓히지 않는다(§4 금지 그대로).
## - 소비하지 않은 같은 종류의 다른 개체와 그 강화는 **건드리지 않는다**(craft_pick_uid가 고른 개체만 지운다).
static func craft(run: Dictionary, id: String, use_equipped: bool = true, equip_after: bool = false) -> bool:
	if not can_craft(run, id, use_equipped):
		push_error("제작 불가: " + id)
		return false
	var rc := PCatalog.recipe(id)
	var inherit := craft_inherit_plus(run, id) # 재료를 지우기 **전에** 읽는다
	for eid in rc.get("equipment", []):
		var e := String(eid)
		var pick := craft_pick_uid(run, e)
		var uid := String(pick.get("uid", ""))
		if uid == "":
			continue
		if String(pick.where) == "bag":
			(run.bag as Array).erase(uid)
		else:
			for slot in run.equipment:
				if run.equipment[slot] != null and String(run.equipment[slot]) == uid:
					run.equipment[slot] = null
		paid_map(run).erase(uid) # 재료로 사라진 개체의 지불 기록도 사라진다(완성품은 '구매액 없는 장비'다)
		equip_plus_map(run).erase(uid) # 재료 개체의 강화 기록은 개체와 함께 지운다(아래에서 완성품에 계승한다)
	for mid in rc.get("mats", {}):
		run.mats[String(mid)] = int(run.mats.get(String(mid), 0)) - int(rc.mats[mid])
	run.gold = int(run.gold) - int(rc.get("fee", 0))
	var out_uid := equip_new_uid(run, id) # 완성품도 개체다
	if inherit > 0:
		equip_plus_map(run)[out_uid] = inherit # 계승: 금화를 다시 받지 않는다
	(run.bag as Array).append(out_uid)
	if not run.has("crafted"):
		run.crafted = []
	(run.crafted as Array).append(id)
	clamp_hp(run) # 계승 단계까지 반영한 뒤에 부른다(최대 체력이 오르는 장비가 있다)
	if equip_after:
		equip_item(run, out_uid)
	add_log(run, "%s%s 제작 (-%d금)%s" % [equip_name(id), (" +%d 계승" % inherit) if inherit > 0 else "", int(rc.get("fee", 0)), "·장착" if equip_after else "·보관"])
	return true
