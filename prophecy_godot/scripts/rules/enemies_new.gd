class_name PEnemiesNew
extends RefCounted
## 신규 기본 몬스터 8종(HTML enemies.js 이식): 멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적.
## + 특수 정예 7종(2026-09-08 추가, 시험값): 정예 궁수·정예 검사·피의 송곳니·역병 조율사·사슬 집행자·군단 기수·균열 채굴자
##   와 그들이 만드는 파괴 가능한 구조물 2종(군단 깃발·돌무더기). 정의는 data/enemies.json, 배치표는 data/elites.json, 설명은 docs/ELITES.md.
## PEnemies.update가 has(type)인 개체에 update를 호출한다. 공통 규칙: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음.
## 상호작용: 감속장은 준비·실행·빈틈 진행(tf)을 늦추고, 냉기는 이동만 늦춘다. 넉백은 돌진·잠복·도약 중에는 무시(combat_state.knock_enemy), 방패병은 50%(def.knockMult).
## 면역(최소 범위): 잠복충·균열 채굴자의 지하 구간(hidden)은 직접 공격·투사체 대상이 되지 않는다(바닥 효과는 적용). 그 외 면역 없음.
## 피해 감소(방패·깃발)는 shield_mult 한 곳에서만 계산하고, 여러 효과가 겹쳐도 곱하지 않는다(가장 강한 하나만).
## 개체별 추가 필드(snake_case, 지연 초기화): face, preview, charge_len, charge_end, charge_blocked, charge_dist, hit_done, heal_t, hex_t, rune_t, act_t, rune_at, cast_target, cast_pts, cast_t, cast_ang,
##   burrow_cd, emerge_at, web_t, web_at, side, base_dir, exploded, block_fx_t,
##   정예: shot_left, blocked_sec, leap_at, leap_from, pods, chain_len, chain_d, pull_from, slam_at, plant_left, order_left, order_t, banner_ref,
##   지휘받는 쪽: rally_t, ordered(leash_boost는 rally_t가 끝나면 PEnemies.update가 1.0으로 되돌린다). 구조물: banner_ttl, banner_r, ring_t, rubble_ttl, trail_t
##   신규 3종(2026-09-09): flame_t, flame_tick, leap_t. 일반 정예 확장: extra_recover, web2_at, residue_at, cast2_pts
##
## + 신규 일반 몬스터 3종(2026-09-09, 시험값): 흡혈 박쥐(bat) · 불씨 도마뱀(lizard) · 도약 두꺼비(toad).
## + 일반 정예 확장 10종(2026-09-09, 시험값): 늑대 우두머리(기존) + 9종. **바탕 몬스터의 강화형**이며 행동 하나만 더한다.
##   정의는 data/pacing.json "enemy_tuning"(new_type 블록), 배치·읽기 자료는 data/elites.json, 설명은 docs/MONSTERS.md.

const COMMITTED := {
	"boar": ["charge_aim", "charge_lock", "charge"],
	"shieldbearer": ["bash_aim", "bash"],
	"shaman": ["cast", "hex_aim", "hex_lock", "rune_aim"],
	"bomber": ["fuse"],
	"burrower": ["dive", "under", "warn", "emerge", "bite_aim"],
	"spider": ["web_aim", "bite_aim"],
	"frostcaller": ["cast"],
	"rogue": ["slash1_aim", "slash2_aim"],
	# 신규 일반 3종(2026-09-09, 시험값). 이탈·선회(leave·hover)와 지상 빈틈은 위험 공격이 아니라 세지 않는다
	"bat": ["bite_aim", "bite"],
	"lizard": ["flame_aim", "flame_lock", "flame"],
	"toad": ["crouch", "leap_warn", "leap", "land"],
	# 특수 정예 7종(2026-09-08, 시험값). 연계 전체를 '위험 공격 중'으로 센다 — 다른 적이 그 위에 겹쳐 쌓지 않게
	"elite_archer": ["aim", "shot_lock", "fan_aim", "fan_lock"],
	"elite_blademaster": ["dash1_aim", "dash1_lock", "dash1", "dash2_aim", "dash2_lock", "dash2", "guard", "slam_aim", "slam"],
	"elite_fang": ["bite_aim", "backoff", "leap_aim", "leap_lock", "leap"], # backoff는 연계 중간 이동이라 '연계 중'으로 센다
	"elite_plaguecaller": ["throw_aim", "swell", "burst_aim"],
	"elite_chainbreaker": ["chain_aim", "chain_lock", "chain_fly", "pull", "slam_aim", "slam_lock", "sweep_aim"],
	"elite_standard": ["plant_aim", "slash_aim"],
	"elite_miner": ["dive", "under", "warn", "erupt", "bite_aim"],
}

## 특수 정예 7종의 type(구조물 2종 제외). data/enemies.json 정의 + data/elites.json 배치표
const ELITE_TYPES := ["elite_archer", "elite_blademaster", "elite_fang", "elite_plaguecaller", "elite_chainbreaker", "elite_standard", "elite_miner"]
## 정예가 만드는 파괴 가능한 구조물(깃발·돌무더기). PEnemies.update가 구조물 중 이 둘만 갱신한다
const ELITE_STRUCTURES := ["elite_banner", "elite_rubble"]

# ---------- 일반 정예 확장 10종(2026-09-09, 시험값) ----------
## 무엇인가: **익숙한 일반 몬스터의 강화형**이다. 바탕 몬스터의 기본 행동을 그대로 굴리고,
## 정해진 전이(from → to) 한 곳에서 **눈에 띄는 변화 하나**를 잇는다. 그래서 한 연계에 들어가는
## 예고 수가 같은 등급의 일반 개체보다 반드시 하나 더 많다(tests/new_monster_tests.gd가 단언한다).
## 무엇이 아닌가:
##  - 여러 고유 패턴을 잇는 **특수 정예 7종**(ELITE_TYPES)이 아니다. 계층이 다르고 동시 연계 상한도 따로다.
##  - **세계 변화 등급(붉은·상위 변이)과 별개**다. 체력은 pacing.json enemy_hp.elite_by_act의 절대값으로 정해지므로
##    등급 배율이 그 위에 겹쳐 곱해지지 않는다(PPacing.hp_mult_for).
##  - **체력만 올린 것이 아니다.** 체력은 더한 행동을 볼 수 있을 만큼만 올렸다.
## 늑대 우두머리(wolf_alpha)는 이미 있는 정예라 여기 등록만 하고 행동을 더하지 않았다(from이 빈 문자열).
## PEnemies.update가 is_wolf를 먼저 보므로 0.3.1 늑대 규칙과 승인된 첫 전투(D33)는 그대로다.
const COMMON_ELITES := {
	"wolf_alpha":         { "base": "wolf",         "from": "",           "to": "",        "extra": [] },
	"boar_elite":         { "base": "boar",         "from": "charge",     "to": "recover", "extra": ["shock_aim"] },
	"archer_elite":       { "base": "archer",       "from": "lock",       "to": "recover", "extra": ["shot2_lock"] },
	"shieldbearer_elite": { "base": "shieldbearer", "from": "bash",       "to": "recover", "extra": ["push_aim"] },
	"spider_elite":       { "base": "spider",       "from": "web_aim",    "to": "recover", "extra": ["web2_aim"] },
	"spore_elite":        { "base": "spore",        "from": "swell",      "to": "recover", "extra": ["residue_aim"] },
	"rogue_elite":        { "base": "rogue",        "from": "slash2_aim", "to": "recover", "extra": ["flank_move", "slash3_aim"] },
	"burrower_elite":     { "base": "burrower",     "from": "warn",       "to": "emerge",  "extra": ["redive", "reunder", "rewarn"] },
	"toad_elite":         { "base": "toad",         "from": "land",       "to": "recover", "extra": ["slam_aim"] },
	"frostcaller_elite":  { "base": "frostcaller",  "from": "cast",       "to": "recover", "extra": ["cast2_aim"] },
}

## 확장 행동이 시작될 때 띄우는 한 줄(무엇이 더 오는지 글로도 읽히게)
const EXTRA_LABEL := {
	"boar_elite": "충격파",
	"archer_elite": "두 번째 화살",
	"shieldbearer_elite": "전진 공격",
	"spider_elite": "두 번째 거미줄",
	"spore_elite": "잔류 포자",
	"rogue_elite": "측면 후속 베기",
	"burrower_elite": "재잠복",
	"toad_elite": "지면 충격",
	"frostcaller_elite": "두 번째 묶음",
}

static func has(type: String) -> bool:
	return COMMITTED.has(type) or ELITE_STRUCTURES.has(type) or COMMON_ELITES.has(type)

static func is_elite(type: String) -> bool:
	return ELITE_TYPES.has(type)

## 일반 정예 확장인가(특수 정예 7종과 다른 계층이다)
static func is_common_elite(type: String) -> bool:
	return COMMON_ELITES.has(type)

## 그 정예가 강화한 바탕 몬스터의 종류. 확장이 아니면 자기 자신
static func base_type(type: String) -> String:
	return String((COMMON_ELITES[type] as Dictionary).base) if COMMON_ELITES.has(type) else type

## 그 정예가 더한 확장 행동의 상태 이름들(없으면 빈 배열)
static func extra_states(type: String) -> Array:
	return (COMMON_ELITES[type] as Dictionary).extra if COMMON_ELITES.has(type) else []

## 지금 확장 행동 중인가(바탕 규칙 대신 update_extra가 굴린다)
static func extra_busy(e: Dictionary) -> bool:
	return extra_states(String(e.type)).has(String(e.state))

## 이 종류가 '위험 공격 중'으로 세는 상태 목록. 정예 확장은 **바탕의 목록 + 더한 상태**다
static func committed_states(type: String) -> Array:
	if COMMITTED.has(type):
		return COMMITTED[type]
	if LEGACY_DANGER.has(type):
		return LEGACY_DANGER[type]
	if COMMON_ELITES.has(type):
		var b := base_type(type)
		var src: Array = COMMITTED[b] if COMMITTED.has(b) else LEGACY_DANGER.get(b, [])
		var out: Array = src.duplicate()
		out.append_array(extra_states(type))
		return out
	return []

# ---------- 동시 위험 공격 상한(적 생존 수와 분리) ----------
## 왜 있는가(2026-09-09, 사람 관찰 "전투 말미가 지루하다"에 대한 계측 결과)
##   tools/tail_probe.gd로 재 보니 원인은 멧돼지의 행동이 아니라 **종류별 동시 생존 상한**이었다.
##   예: 2막 t2c_boar_archer는 동시 상한이 15인데 멧돼지 2 + 궁수 3 = **최대 5마리**만 살 수 있어
##   전장이 3분의 1도 차지 않고, 남은 45마리가 2~3마리씩 찔끔 나온다(자리가 비어 있던 시간 74초/77초).
##   그 상한을 올리려면 "적이 많아지면 위험 공격도 그만큼 많아진다"는 문제를 먼저 갈라야 한다.
##   그래서 **적 생존 수**(편성·소환 담당)와 **동시 위험 공격 수**(적 규칙 = 여기)를 분리한다.
##
## 무엇을 하는가: 지금 예고~실행 중인 적이 상한이면 **새 공격을 시작하지 않는다**.
##   이미 시작한 공격은 절대 끊지 않고(예고가 사라지는 일이 없다), 적을 지우거나 자동 처치하지도 않는다.
##   상한은 계측으로 관측한 **오늘의 최고치**를 그대로 뒀다 — 지금 압박을 줄이는 값이 아니라,
##   종류별 상한을 올렸을 때 위험이 같이 부풀지 않게 막는 천장이다. 값은 data/pacing.json "danger_limit".
##
## 세는 것과 막는 것은 다르다
##   - **센다**: 신규 8종·특수 정예(COMMITTED) + 늑대 계열·궁수·포자(LEGACY_DANGER)
##   - **막는다**: 신규 8종·궁수·포자·특수 정예만. **늑대 계열은 막지 않는다**
##     (0.3.1 규칙과 승인된 첫 전투 D33을 그대로 보존해야 하기 때문. 늑대 돌진은 원래 wolf.dash.max_concurrent가 따로 제한한다)
##   - 보스전(mode == "boss")에서는 적용하지 않는다. 그쪽은 overlap_limit·wolf_may_attack이 이미 담당한다
const LEGACY_DANGER := {
	"wolf": ["crouch", "lock", "dash", "bite_track", "bite_lock", "bite_hit"],
	"wolf_alpha": ["crouch", "lock", "dash", "bite_track", "bite_lock", "bite_hit"],
	"archer": ["aim", "lock"],
	"spore": ["swell"],
}

static func danger_cfg() -> Dictionary:
	return PCatalog.pacing().get("danger_limit", {})

## 이 적이 지금 위험 공격(예고~실행) 중인가. is_committed보다 넓다(늑대·궁수·포자까지 센다).
## 정예 확장은 바탕의 목록에 더한 상태까지 함께 센다 — 확장 행동도 위험 공격이기 때문이다
static func danger_busy(o: Dictionary) -> bool:
	return committed_states(String(o.type)).has(String(o.state))

## 지금 위험 공격 중인 적 수(자기 자신·보스·구조물 제외)
static func danger_count(st: CombatState, e: Dictionary) -> int:
	var n := 0
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.get("boss", false)) or bool(o.get("structure", false)):
			continue
		if danger_busy(o):
			n += 1
	return n

## 그 막의 동시 위험 공격 상한. 표가 없으면 사실상 무제한(기존 동작 그대로)
static func danger_max(st: CombatState) -> int:
	var C := danger_cfg()
	var by: Dictionary = C.get("by_act", {})
	var k := str(clampi(int(st.act), 1, 3))
	if by.has(k):
		return int(by[k])
	return int(C.get("max_concurrent", 9999))

## 새 위험 공격을 시작해도 되는가: 기존 동시 제한(CombatState.may_attack) + 동시 위험 공격 상한.
## may_attack은 한 단계에 한 번만 물어야 하므로(대기 시간이 두 배로 깎인다) 상한을 **먼저** 본다
static func may_start(st: CombatState, e: Dictionary, dt: float) -> bool:
	if bool(danger_cfg().get("enabled", false)) and String(st.mode) != "boss" and danger_count(st, e) >= danger_max(st):
		e.ready_t = -1.0
		return false
	return st.may_attack(e, dt)

# ---------- 적 정의 겹쳐쓰기(data/pacing.json "enemy_tuning") ----------
## data/enemies.json은 내보내기 산출물이라 손으로 고치지 않는다. 손으로 정한 값은 data/pacing.json에 두고
## 규칙 코드가 항목별로 덮어 읽는다(포자의 PEnemies.spore_cfg()와 같은 방식). 규칙 코드에 숫자를 두지 않는 관례 그대로다.
static func tuning(type: String) -> Dictionary:
	return PCatalog.pacing().get("enemy_tuning", {}).get(type, {})

## 적 정의 값 하나를 겹쳐쓰기 우선으로 읽는다. 표에도 정의에도 없으면 fallback
static func dv(e: Dictionary, key: String, fallback: float = 0.0) -> float:
	var t := tuning(String(e.type))
	if t.has(key):
		return float(t[key])
	var d: Dictionary = e.def
	return float(d[key]) if d.has(key) else fallback

## 겹쳐쓰기 우선 사전 항목(치료 우선순위 표처럼 값이 사전인 것)
static func dvd(e: Dictionary, key: String) -> Dictionary:
	var t := tuning(String(e.type))
	if t.has(key):
		return t[key]
	var d: Dictionary = e.def
	return d[key] if d.has(key) else {}

## 겹쳐쓰기 우선 배열 항목(서리 영역의 지연 시간표처럼 값이 배열인 것)
static func dva(e: Dictionary, key: String) -> Array:
	var t := tuning(String(e.type))
	if t.has(key):
		return t[key]
	var d: Dictionary = e.def
	return d[key] if d.has(key) else []

# ---------- 새 종류 정의(생성 파일 data/enemies.json은 손대지 않는다) ----------
## 왜 이렇게 하는가: data/enemies.json은 내보내기 산출물이라 손으로 고치지 않는다는 관례가 있다.
## 그래서 **새 적의 정의도** 손으로 정하는 표(data/pacing.json "enemy_tuning")에 둔다.
## 방패병 frontMult·포자 spore 블록과 같은 자리, 같은 방식이다. 판별은 항목의 `new_type` 블록이며,
## `new_type.base`가 있으면 그 바탕 적의 정의를 복사한 뒤 항목 값으로 덮는다(일반 정예 확장).
##
## **필요한 훅(다른 담당 몫)**: scripts/rules/catalog.gd의 PCatalog.enemies()가 bosses_new를 합치는 것과 똑같이
##   var extra := PEnemiesNew.extra_defs(out)
##   for k in extra: out[k] = extra[k]
## 두 줄을 더해 주면 CombatState.spawn_enemy·PFormation·PRun이 새 종류를 바로 찾는다.
## 그 훅이 붙기 전까지는 아래 ensure_defs()가 같은 일을 한다 — 다만 **전투가 시작된 뒤**(PEnemies.update 첫 호출)라
## 편성이 새 종류를 먼저 조회하는 경로에서는 훅 쪽이 정본이다. 자세한 내용은 docs/MONSTERS.md §필요한 훅.
##
## 주의(2026-09-09 계측): 이 등록을 `_static_init`(스크립트 적재 시점)에서 하면 검사가 모두 통과해도
## 프로세스가 접근 위반(종료 코드 3221225477 = KD-1)으로 끝난다. tests/elites_tests.gd로 확인했다
## (읽기만 하면 정상, **적 사전을 static_init에서 고치면** 비정상 종료). 그래서 등록은 늦게 한다.
const NEW_TYPE_GUARD := "bat"

## 이 표가 정의하는 새 종류들(type → 정의). base_defs = 바탕이 되는 적 사전(재귀를 피하려고 인자로 받는다).
## 바탕은 이미 있는 적일 수도 있고, **이 표에서 먼저 만들어진 새 종류**일 수도 있다(도약 두꺼비 → 충격 두꺼비).
## 그래서 표 순서대로 만들면서 앞서 만든 정의도 바탕 후보로 본다 — 표에서 바탕을 아래에 두면 안 된다.
static func extra_defs(base_defs: Dictionary) -> Dictionary:
	var out := {}
	var T: Dictionary = PCatalog.pacing().get("enemy_tuning", {})
	for k in T:
		if typeof(T[k]) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = T[k]
		if not row.has("new_type") or base_defs.has(String(k)):
			continue
		var base := String((row.new_type as Dictionary).get("base", ""))
		var src: Dictionary = {}
		if base != "":
			src = out[base] if out.has(base) else base_defs.get(base, {})
		out[String(k)] = build_def(row, src, base)
	return out

## 적 사전에 아직 새 종류가 없으면 등록한다(값싼 검사 한 번. PCatalog.reset()으로 캐시가 비면 다시 등록한다)
static func ensure_defs() -> void:
	var E := PCatalog.enemies()
	if E.has(NEW_TYPE_GUARD):
		return
	var add := extra_defs(E)
	for k in add:
		E[k] = add[k]

## 표 한 줄 + 바탕 정의로 적 정의를 만든다. 겹치는 순서는
##   바탕 정의 → **바탕의 손으로 정한 겹쳐쓰기** → 이 항목 → 이 항목의 new_type 블록.
## 바탕 겹쳐쓰기를 함께 물려받는 이유: 방패병 정면 감소처럼 **사용자가 확정한 값**이 data/pacing.json에만 있고
## data/enemies.json에는 옛 값이 남아 있다. 그것을 그대로 복사하면 정예만 확정 전 값을 쓰게 된다.
## 설명용 항목(note로 끝나는 이름)은 정의에 넣지 않는다.
static func build_def(row: Dictionary, base_def: Dictionary, base: String) -> Dictionary:
	var out: Dictionary = base_def.duplicate(true)
	if base != "":
		_overlay_row(out, tuning(base))
	_overlay_row(out, row)
	_overlay_row(out, row.new_type)
	return out

static func _overlay_row(out: Dictionary, row: Dictionary) -> void:
	for k in row:
		var key := String(k)
		if key == "new_type" or key == "base" or key == "note" or key.ends_with("_note"):
			continue
		out[key] = row[k]

static func update(st: CombatState, e: Dictionary, dt: float) -> void:
	update_as(st, e, dt, String(e.type))

## 정예 확장이 **바탕 몬스터의 기본 행동**을 그대로 굴릴 때 쓰는 입구(PEnemies.update_common_elite가 부른다)
static func update_base(st: CombatState, e: Dictionary, dt: float) -> void:
	update_as(st, e, dt, base_type(String(e.type)))

static func update_as(st: CombatState, e: Dictionary, dt: float, type: String) -> void:
	match type:
		"boar":
			update_boar(st, e, dt)
		"shieldbearer":
			update_shieldbearer(st, e, dt)
		"shaman":
			update_shaman(st, e, dt)
		"bomber":
			update_bomber(st, e, dt)
		"burrower":
			update_burrower(st, e, dt)
		"spider":
			update_spider(st, e, dt)
		"frostcaller":
			update_frostcaller(st, e, dt)
		"rogue":
			update_rogue(st, e, dt)
		"bat":
			update_bat(st, e, dt)
		"lizard":
			update_lizard(st, e, dt)
		"toad":
			update_toad(st, e, dt)
		"elite_archer":
			update_elite_archer(st, e, dt)
		"elite_blademaster":
			update_elite_blademaster(st, e, dt)
		"elite_fang":
			update_elite_fang(st, e, dt)
		"elite_plaguecaller":
			update_elite_plaguecaller(st, e, dt)
		"elite_chainbreaker":
			update_elite_chainbreaker(st, e, dt)
		"elite_standard":
			update_elite_standard(st, e, dt)
		"elite_miner":
			update_elite_miner(st, e, dt)
		"elite_banner":
			update_banner(st, e, dt)
		"elite_rubble":
			update_rubble(st, e, dt)

static func is_committed(e: Dictionary) -> bool:
	var t := String(e.type)
	if COMMON_ELITES.has(t): # 정예 확장: 바탕의 확정 상태 + 더한 상태
		return committed_states(t).has(String(e.state))
	var c: Array = COMMITTED.get(t, [])
	return c.has(String(e.state))

# ---------- 공용 도우미 ----------
## 빈틈 상태로 전환. label=false면 "빈틈!" 표시 생략.
## **일반 정예 확장 가로채기**: 바탕 행동이 빈틈으로 들어가는 그 순간이 확장 행동의 시작점이면
## 빈틈 대신 확장 행동 하나를 먼저 끼운다(끝나면 여기서 받은 길이 그대로 빈틈으로 들어간다).
static func to_recover(st: CombatState, e: Dictionary, dur: float, label: bool = true) -> void:
	if _extra_on_recover(st, e, dur):
		return
	e.state = "recover"
	e.state_t = 0.0
	e.recover_dur = dur
	if label:
		st.text(e.x, e.y - e.r - 26.0, "빈틈!", "#ffd166")

## 궁수식 거리 유지(장애물 우회)
static func keep_distance(st: CombatState, e: Dictionary, d: Dictionary, dt: float, sm: float) -> void:
	var p := st.target_of(e)
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if dist < float(d.keepMin):
		st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
	elif dist > float(d.keepMax):
		st.approach(e, p.x, p.y, float(d.speed) * sm, dt)

## 부채꼴 근접 판정(직접 공격: 장애물 가림 적용)
static func arc_hit(st: CombatState, e: Dictionary, ang: float, R: float, half: float, dmg: float, src: String) -> void:
	var p := st.target_of(e)
	if PGeom.in_arc(e.x, e.y, R, ang, half, p.x, p.y, p.r) and not st.los_blocked(e.x, e.y, p.x, p.y):
		st.damage_player(dmg, src, e)

static func _recover_tick(e: Dictionary, adv: float) -> void:
	e.state_t += adv
	if float(e.state_t) >= float(e.recover_dur):
		e.state = "approach"
		e.state_t = 0.0

# ---------- A. 멧돼지: 긴 직선 돌파 ----------
static func update_boar(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach":
			if dist < float(d.minDist): # 너무 가까우면 물러나서 거리를 벌린 뒤 돌파(밀어붙이기 금지)
				e.state = "backoff"
				e.state_t = 0.0
				return
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			# 코앞이 막혀 있으면 돌파하지 않는다
			if dist <= float(d.engageDist) and dist >= float(d.minDist) and not st.los_blocked(e.x, e.y, p.x, p.y) \
				and float(PBoss.dash_path(st, e, atan2(p.y - e.y, p.x - e.x), float(d.chargeDist))["len"]) >= float(d.minDist) and may_start(st, e, dt):
				e.state = "charge_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"backoff": # 최대 1.5초 뒤로 물러남(벽에 막히면 접선 방향). 거리가 벌어지면 접근 상태로
			e.state_t += dt
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
			if dist >= float(d.minDist) + 40.0 or float(e.state_t) >= 1.5:
				e.state = "approach"
				e.state_t = 0.0
		"charge_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			e.preview = PBoss.dash_path(st, e, float(e.aim_angle), float(d.chargeDist)) # 예고와 실제가 같은 계산
			var pv: Dictionary = e.preview
			if float(e.state_t) >= float(d.aim) and not pv.is_empty() and float(pv["len"]) < float(d.minDist): # 준비 중 통로가 막히면 돌파 취소
				e.state = "approach"
				e.state_t = 0.0
				e.preview = {}
				return
			if float(e.state_t) >= float(d.aim):
				e.state = "charge_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				var path := PBoss.dash_path(st, e, float(e.dir), float(d.chargeDist))
				e.charge_len = float(path["len"])
				e.charge_end = path.end
				e.charge_blocked = float(path["len"]) < float(d.chargeDist) - 1.0 # 통로가 장애물·벽에서 끊기면 그 끝에서 충돌(긴 빈틈)
				e.charge_dist = 0.0
				e.hit_done = false
				st.ev("lock")
		"charge_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.lock):
				e.state = "charge"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"charge": # 거리 기준: 감속되어도 경로·거리 그대로. 장애물·벽에 닿으면 긴 빈틈
			var remain: float = maxf(0.0, float(e.charge_len) - float(e.charge_dist))
			var stp: float = minf(float(d.chargeSpeed) * tf * dt, remain)
			var x0: float = e.x
			var y0: float = e.y
			var mv := st.move_swept(e, cos(float(e.dir)) * stp, sin(float(e.dir)) * stp)
			e.charge_dist = float(e.charge_dist) + PGeom.dist(e.x, e.y, x0, y0)
			if not bool(e.hit_done) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, p.r + e.r):
				e.hit_done = true
				e.bite_t = 0.0
				st.ev("bite")
				st.damage_player(float(d.damage), "boar", e)
			var done: bool = float(e.charge_dist) >= float(e.charge_len) - 1e-6 or stp <= 1e-9
			if String(mv.hit) != "" or (done and bool(e.charge_blocked)):
				e.state = "stagger"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 26.0, "충돌! 긴 빈틈", "#ffd166")
				st.fx({ "kind": "impact", "x": e.x + cos(float(e.dir)) * e.r, "y": e.y + sin(float(e.dir)) * e.r, "r": 40.0, "ttl": 0.3 })
				st.ev("boss_land")
			elif done:
				to_recover(st, e, float(d.recover))
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.stun):
				e.state = "approach"
				e.state_t = 0.0
		"recover":
			_recover_tick(e, adv)

# ---------- B. 방패병: 정면 방어 ----------
## 2026-09-09 사용자 확정: 정면 감소 **85% → 70%**(pacing.json enemy_tuning.shieldbearer.frontMult 0.30), 정면 각 120도 유지.
##   — 앞선 2026-09-08 확정(70% → 85%, enemies.json frontMult 0.15)을 사람이 직접 플레이한 뒤 되돌린 것이다.
##   — **일반 방패병 전용 수치다.** 정예 검사(elite_blademaster)의 방패 자세는 guardMult(0.0 = 완전 차단)로 따로 있다.
## 접근 중과 방패치기 **준비 중(bash_aim)**에는 방패를 유지하고, 실제 방패치기(bash)와 그 뒤 빈틈(recover)에만 연다.
## 방향 전환은 느리게 유지(turnRate 2.2 rad/s)해 측·후방 공략이 답이 되게 한다. 판정 점검은 docs/SHIELDBEARER.md.
static func update_shieldbearer(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("face"):
		e.face = atan2(p.y - e.y, p.x - e.x)
	# 방향 전환은 즉시가 아니다: 초당 turnRate(감속장 안에서는 더 느리게)
	var want: float = atan2(p.y - e.y, p.x - e.x)
	var diff := PGeom.ang_diff(float(e.face), want)
	var max_turn: float = float(d.turnRate) * adv
	e.face = float(e.face) + clampf(diff, -max_turn, max_turn)
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) + e.r and absf(diff) < PGeom.deg(50.0) and may_start(st, e, dt):
				e.state = "bash_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"bash_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.aim):
				e.state = "bash"
				e.state_t = 0.0
				e.dir = e.face
				st.move_swept(e, cos(float(e.dir)) * float(d.lunge), sin(float(e.dir)) * float(d.lunge))
				var half: float = PGeom.deg(float(d.bashDeg)) / 2.0
				arc_hit(st, e, float(e.dir), float(d.bashRange), half, float(d.damage), "bash")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.bashRange), "half": half, "ttl": 0.18, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("boss_sweep")
		"bash":
			e.state_t += adv
			if float(e.state_t) >= 0.12:
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 방패가 지금 닫혀(방어) 있는가. 2026-09-08 사용자 확정: 접근 중과 방패치기 **준비 중**에는 유지,
## 실제 방패치기(bash)와 그 뒤 빈틈(recover)에만 열린다. 정예 검사(elite_blademaster)의 방패 자세도 같은 함수로 묻는다
## 일반 정예 확장(돌격 방패병)도 바탕과 같은 규칙을 쓴다(base_type). 확장이 끼우는 **전진 공격 준비(push_aim)**도
## 방패가 열린 구간으로 둔다 — 확장 때문에 반격 창이 짧아지면 안 되기 때문이다(시험값).
static func guard_closed(e: Dictionary) -> bool:
	match base_type(String(e.type)):
		"shieldbearer":
			var s := String(e.state)
			return s != "bash" and s != "recover" and s != "push_aim"
		"elite_blademaster":
			return String(e.state) == "guard"
	return false

## 방패 판정: 방패가 닫혀 있고 공격 **출처**가 정면 부채꼴 안이면 감소 배율을 적용한다.
##   - 일반 방패병: frontMult = **0.30(70% 감소, 2026-09-09 사용자 확정)** — pacing.json enemy_tuning이 정본
##   - 정예 검사: guardMult = 0.0(정면 직접 피해 **완전 차단**) — 전혀 다른 값이며 위와 섞지 않는다
## 출처 위치가 없는 바닥·추가·기술·지속 피해는 정상(우회). 측·후면과 방패를 내린 시간에도 감소가 없다.
## 감소는 **한 번만** 적용한다: 여러 방어 효과가 겹치면 곱하지 않고 가장 강한 하나(min)만 쓴다.
static func shield_mult(st: CombatState, e: Dictionary, opt: Dictionary) -> float:
	var m := 1.0
	if guard_closed(e) and e.has("face") and _blockable(opt):
		var d: Dictionary = e.def
		var from: Dictionary = opt.get("from", st.player)
		var a: float = atan2(float(from.y) - e.y, float(from.x) - e.x)
		var deg_key := "guardDeg" if d.has("guardDeg") else "frontDeg"
		var mult_key := "guardMult" if d.has("guardMult") else "frontMult"
		var half: float = PGeom.deg(dv(e, deg_key, 0.0)) / 2.0
		if half > 0.0 and absf(PGeom.ang_diff(float(e.face), a)) <= half:
			m = minf(m, dv(e, mult_key, 1.0))
	if _rally_guard(st, e) and _blockable(opt): # 군단 기수 깃발의 방어 지원(중복 아님: 더 강한 쪽만)
		m = minf(m, float(PCatalog.enemy("elite_standard").get("banner", {}).get("guardMult", 1.0)))
	# 출격 준비물 '파쇄 기름': 방어 감소에 하한을 둔다. min으로 고른 결과에 **한 번만** 적용하고 곱하지 않는다
	m = maxf(m, PConsumables.guard_floor(st.build))
	return m

## 방패·깃발이 막을 수 있는 피해인가(직접 공격 = 무기 본체·투사체). 바닥·추가·기술·지속 피해는 정상
static func _blockable(opt: Dictionary) -> bool:
	var sr: Dictionary = opt.get("src", {})
	return bool(sr.get("direct", true)) and not bool(sr.get("extra", false)) and not bool(sr.get("skill", false)) and not opt.has("dot")

# ---------- C. 주술사: 강한 아군 우선 치료 + 공격 두 패턴 ----------
## 2026-09-09 사용자 피드백 반영. 세 행동(치료 · 세 갈래 저주탄 · 저주 문양)은 **하나의 행동 상태를 공유**한다:
## 한 행동을 끝내면 공용 간격(actGap)이 지나야 다음을 시작하므로 동시에·연달아 몰아 쓰지 않는다.
## 정예급 연계(예고 → 확정 → 곧바로 다음 예고)는 일반 주술사에게 넣지 않았다 — 세 행동 모두 예고 → 확정 → 실행 → 빈틈 한 벌이다.
## 수치는 data/pacing.json enemy_tuning.shaman이 정본이다(enemies.json은 내보내기 산출물이라 손대지 않는다).

## 치료 대상 우선순위 등급(클수록 먼저). 특수 정예 → 일반 정예·우두머리 → 주력 적 → 일반 잡몹.
## 역할은 pacing.json enemy_hp.roles 표를 그대로 쓴다(약한 무리 swarm만 잡몹).
static func heal_rank(e: Dictionary, o: Dictionary) -> int:
	var t := String(o.type)
	if is_elite(t):
		return int(dv(e, "heal_rank_special_elite", 3.0))
	if bool(o.get("elite", false)) or bool((o.def as Dictionary).get("elite", false)):
		return int(dv(e, "heal_rank_elite", 2.0))
	var by_role: Dictionary = dvd(e, "heal_rank_by_role")
	var role := String(PPacing.roles().get(t, ""))
	if by_role.has(role):
		return int(by_role[role])
	return int(dv(e, "heal_rank_default", 0.0))

## 치료 대상: 자기·보스·다른 주술사·지하·구조물 제외, **다치지 않은 적은 제외**(가득 찬 강적을 붙잡고
## 다른 다친 아군을 무시하지 않는다). 사거리 안에서 우선순위 등급이 가장 높은 아군을 고르고,
## 같은 등급 안에서는 **잃은 체력의 절대값**이 큰 쪽을 고른다. 무작위 선택도, 잃은 비율만 보는 선택도 하지 않는다. 없으면 {}
static func heal_target(st: CombatState, e: Dictionary) -> Dictionary:
	var best := {}
	var best_rank := -1
	var best_miss := -1.0
	var reach := dv(e, "healRange", 0.0)
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.boss) or bool((o.def as Dictionary).get("boss", false)) or String(o.type) == "shaman" or bool(o.get("hidden", false)):
			continue
		if bool(o.get("structure", false)): # 깃발·돌무더기·제단은 싸우는 아군이 아니다
			continue
		if float(o.hp) >= float(o.hp_max):
			continue
		if PGeom.dist(o.x, o.y, e.x, e.y) > reach:
			continue
		var rk := heal_rank(e, o)
		var miss: float = float(o.hp_max) - float(o.hp)
		if rk > best_rank or (rk == best_rank and miss > best_miss):
			best_rank = rk
			best_miss = miss
			best = o
	return best

## 지금 이 주술사가 치료 중인 대상(없으면 {}). 화면·계측이 읽는 관측 자료 — PEnemies.support_links가 이것으로 선을 만든다
static func heal_link_target(e: Dictionary) -> Dictionary:
	if String(e.type) != "shaman" or String(e.state) != "cast":
		return {}
	var tgv = e.get("cast_target")
	if tgv == null or typeof(tgv) != TYPE_DICTIONARY or bool(tgv.dead):
		return {}
	return tgv

static func update_shaman(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("heal_t"):
		e.heal_t = 2.0
		e.hex_t = 1.5
		e.rune_t = 3.0
		e.act_t = 0.0
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			e.heal_t = float(e.heal_t) - dt
			e.hex_t = float(e.hex_t) - dt
			e.rune_t = float(e.rune_t) - dt
			e.act_t = float(e.act_t) - dt
			if float(e.act_t) > 0.0: # 세 행동이 공유하는 간격 — 치료와 공격을 동시에 몰아 쓰지 않는다
				return
			var may: bool = may_start(st, e, dt) # 한 단계에 한 번만 묻는다(여러 번 물으면 대기 시간이 두 배로 깎인다)
			if not may:
				return
			if float(e.heal_t) <= 0.0:
				var tg := heal_target(st, e)
				if not tg.is_empty():
					e.state = "cast"
					e.state_t = 0.0
					e.cast_target = tg
					e.ready_t = -1.0
					st.note_attack(e, "prepare")
					st.text(e.x, e.y - e.r - 26.0, "치료 시전", "#e9b6ff")
					return
			if float(e.rune_t) <= 0.0 and dist <= dv(e, "runeRange", 0.0):
				# 문양 위치는 **예고를 시작하는 지금** 확정한다. 그 뒤로는 플레이어를 따라가지 않는다
				var pos := st.nearest_valid_pos(p.x, p.y, 0.0, 120.0)
				e.rune_at = pos if not pos.is_empty() else [p.x, p.y]
				e.state = "rune_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.text(e.x, e.y - e.r - 26.0, "저주 문양", "#e9b6ff")
				st.ev("hazard_warn")
				return
			if float(e.hex_t) <= 0.0 and dist <= float(d.keepMax) + 40.0 and not st.los_blocked(e.x, e.y, p.x, p.y):
				e.state = "hex_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.text(e.x, e.y - e.r - 26.0, "세 갈래 저주탄", "#e9b6ff")
		"cast":
			var tgv = e.get("cast_target")
			e.state_t += adv
			if tgv == null or bool(tgv.dead) or PGeom.dist(float(tgv.x), float(tgv.y), e.x, e.y) > dv(e, "healRange", 0.0) + 40.0:
				e.cast_target = null
				e.heal_t = float(d.healInterval) * 0.5
				e.act_t = dv(e, "actGap", 0.0)
				to_recover(st, e, 0.6, false)
				return
			if float(e.state_t) >= float(d.healCast):
				var tg: Dictionary = tgv
				var before: float = tg.hp
				tg.hp = minf(float(tg.hp_max), float(tg.hp) + float(tg.hp_max) * dv(e, "healRatio", 0.0))
				var amt: float = float(tg.hp) - before
				st.metrics.heals += 1
				st.metrics.heal_amount += amt
				st.text(tg.x, tg.y - tg.r - 22.0, "+" + str(int(round(amt))), "#9cffb0")
				st.fx({ "kind": "burst", "x": tg.x, "y": tg.y, "r": tg.r + 14.0, "ttl": 0.3, "color": "#e9b6ff" })
				st.ev("orb")
				st.note_attack(e, "execute")
				e.heal_t = float(d.healInterval)
				e.act_t = dv(e, "actGap", 0.0)
				e.cast_target = null
				to_recover(st, e, float(d.recover))
		"hex_aim": # 예고: 조준선이 플레이어를 따라간다
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.hexAim):
				e.state = "hex_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 방향 확정 — 여기서부터 따라가지 않는다. 옆으로 이동하면 피할 수 있다
				st.ev("lock")
		"hex_lock": # 확정 뒤 짧은 고정 시간, 그다음 세 갈래로 발사
			e.state_t += adv
			if float(e.state_t) >= dv(e, "hexLock", 0.0):
				var n: int = int(dv(e, "hexCount", 1.0))
				var step: float = PGeom.deg(dv(e, "hexSpreadDeg", 0.0))
				for i in n:
					# 가운데 탄은 확정 시점의 플레이어 방향 그대로다(가만히 선 플레이어를 양옆으로 빗겨 쏘지 않는다)
					_hex_bolt(st, e, d, float(e.dir) + (float(i) - float(n - 1) / 2.0) * step)
				st.ev("shoot")
				st.note_attack(e, "execute")
				e.hex_t = float(d.hexInterval)
				e.act_t = dv(e, "actGap", 0.0)
				to_recover(st, e, float(d.recover), false)
		"rune_aim": # 바닥 문양: 위치는 시작 때 이미 고정이라 예고 원이 플레이어를 따라오지 않는다
			e.state_t += adv
			if float(e.state_t) >= dv(e, "runeAim", 0.0):
				var at: Array = e.rune_at
				circle_hit(st, e, float(at[0]), float(at[1]), dv(e, "runeR", 0.0), dv(e, "runeDamage", 0.0), "shaman_rune")
				st.ev("spore")
				e.rune_t = dv(e, "runeInterval", 0.0)
				e.act_t = dv(e, "actGap", 0.0)
				e.erase("rune_at")
				to_recover(st, e, dv(e, "runeRecover", 0.0))
		"recover":
			_recover_tick(e, adv)

## 저주탄 한 발(기존 hex 투사체와 같은 종류·같은 발당 피해)
static func _hex_bolt(st: CombatState, e: Dictionary, d: Dictionary, ang: float) -> void:
	var pr := { "owner": "enemy", "kind": "hex", "shooter": e, "x": e.x + cos(ang) * (float(e.r) + 4.0), "y": e.y + sin(ang) * (float(e.r) + 4.0),
		"vx": cos(ang) * float(d.hexSpeed), "vy": sin(ang) * float(d.hexSpeed), "r": float(d.hexR), "dmg": float(d.hexDamage), "ttl": 4.0, "angle": ang, "dead": false, "hits": {} }
	CombatState.stamp_projectile(e, pr)
	st.projectiles.append(pr)

## 막기 연출(사용자 확정): **실제 방어 판정이 일어난 순간에만** 방패 타격 효과·금속음·짧은 '방어' 표시.
## damage_enemy가 피해를 적용한 직후 같은 opt로 다시 물어보므로(shield_mult는 부작용 없는 조회) 판정과 연출이 어긋나지 않는다.
## 화면의 '방어 중/열림' 구분과 흰 방패·"막음" 표시는 render.gd가 e.state·e.blocked_t로 이미 그린다.
static func note_block(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	if shield_mult(st, e, opt) >= 1.0:
		return
	if st.t - float(e.get("block_fx_t", -9.0)) < 0.15: # 연타로 소리·글자가 겹치지 않게(판정은 매번 그대로)
		return
	e.block_fx_t = st.t
	var fa: float = float(e.get("face", 0.0))
	var bx: float = e.x + cos(fa) * (float(e.r) + 6.0)
	var by: float = e.y + sin(fa) * (float(e.r) + 6.0)
	st.fx({ "kind": "burst", "x": bx, "y": by, "r": 16.0, "ttl": 0.22, "color": "#e8e8f0" }) # 방패 타격 효과
	st.fx({ "kind": "spark", "x": bx, "y": by, "ttl": 0.18, "angle": fa + PI, "crit": false })
	st.text(e.x, e.y - float(e.r) - 40.0, "방어", "#cfe3ff")
	st.ev("shatter") # 금속음(짧은 고음 사각파)

## 시전 방해: 12 이상 한 방 또는 넉백(20 이상)이면 끊긴다. 처치는 당연히 끊는다.
static func on_damaged(st: CombatState, e: Dictionary, dmg: float, opt: Dictionary) -> void:
	note_block(st, e, opt)
	if String(e.type) == "shaman" and e.state == "cast" and (dmg >= float(e.def.interruptDamage) or float(opt.get("knock", 0.0)) >= 20.0):
		e.cast_target = null
		e.heal_t = float(e.def.healInterval) * 0.5
		st.metrics.interrupts += 1
		st.text(e.x, e.y - e.r - 40.0, "시전 중단!", "#7ef2ff")
		to_recover(st, e, 1.0)

# ---------- D. 폭탄 운반체 ----------
static func update_bomber(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) + e.r and may_start(st, e, dt):
				e.state = "fuse"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.ev("lock")
		"fuse": # 멈춰 서서 준비. 넉백으로 밀리면 표시 원도 같이 움직인다(실제 범위 = 표시 범위)
			e.state_t += adv
			if float(e.state_t) >= float(d.fuse):
				st.note_attack(e, "execute")
				if dist <= float(d.blastR) + p.r:
					st.damage_player(float(d.damage), "blast", e)
				st.fx({ "kind": "mineburst", "x": e.x, "y": e.y, "r": float(d.blastR), "ttl": 0.4 })
				st.ev("explode")
				e.exploded = true
				e.hp = 0.0
				e.dead = true
				e.death_t = 0.0
				e.acted = true
				var m := st.metrics_for(e)
				m.exploded = int(m.get("exploded", 0)) + 1

# ---------- E. 잠복충 ----------
static func update_burrower(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("burrow_cd"):
		e.burrow_cd = 1.0
	if e.state != "under" and e.state != "dive" and e.state != "warn":
		e.burrow_cd = float(e.burrow_cd) - dt
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and float(e.burrow_cd) <= 0.0 and may_start(st, e, dt):
				e.state = "dive"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
			elif dist <= float(d.biteRange) + e.r and may_start(st, e, dt):
				e.state = "bite_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"dive":
			e.state_t += adv
			if float(e.state_t) >= float(d.dive):
				e.state = "under"
				e.state_t = 0.0
				e.hidden = true
		"under": # 짧은 지하 이동(플레이어 추적 허용). 끝나면 출현 지점 확정(지형 안 금지)
			e.state_t += adv
			var n := PGeom.norm(p.x - e.x, p.y - e.y)
			st.move_swept(e, n[0] * float(d.underSpeed) * sm * dt, n[1] * float(d.underSpeed) * sm * dt, true)
			if float(e.state_t) >= float(d.under) or dist < 30.0:
				var pos := st.nearest_valid_pos(e.x, e.y, e.r, 200.0)
				if pos.is_empty():
					pos = [e.x, e.y]
				e.emerge_at = pos
				e.state = "warn"
				e.state_t = 0.0
				st.ev("lock")
		"warn":
			e.state_t += adv
			if float(e.state_t) >= float(d.warn):
				var at: Array = e.emerge_at
				e.x = float(at[0])
				e.y = float(at[1])
				e.hidden = false
				e.state = "emerge"
				e.state_t = 0.0
				st.note_attack(e, "execute")
				if PGeom.dist(e.x, e.y, p.x, p.y) <= float(d.emergeR) + p.r:
					st.damage_player(float(d.damage), "emerge", e)
				st.fx({ "kind": "bossland", "x": e.x, "y": e.y, "r": float(d.emergeR), "ttl": 0.4 })
				st.ev("boss_land")
				e.burrow_cd = float(d.cooldown)
		"emerge":
			e.state_t += adv
			if float(e.state_t) >= 0.15:
				e.state = "stagger"
				e.state_t = 0.0
				st.text(e.x, e.y - e.r - 26.0, "빈틈!", "#ffd166")
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.exposed):
				e.state = "approach"
				e.state_t = 0.0
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "bite")
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.biteRecover))
		"recover":
			_recover_tick(e, adv)

# ---------- F. 거미 ----------
static func web_count(st: CombatState) -> int:
	var n := 0
	for z in st.zones:
		if z.type == "web":
			n += 1
	return n

static func update_spider(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("web_t"):
		e.web_t = 1.2
	match String(e.state):
		"approach":
			# 거미줄 직전에만 거리를 두고, 그 외에는 물려고 다가온다
			if float(e.web_t) > 1.5:
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			else:
				keep_distance(st, e, d, dt, sm)
			e.web_t = float(e.web_t) - dt
			if dist <= float(d.biteRange) + e.r and may_start(st, e, dt):
				e.state = "bite_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				return
			if float(e.web_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and may_start(st, e, dt): # 플레이어 진행 방향 앞(70)에 예고. 예고 위치는 시작 때 확정
				var ax: float = p.x + cos(float(p.face)) * 70.0
				var ay: float = p.y + sin(float(p.face)) * 70.0
				var pos := st.nearest_valid_pos(ax, ay, 0.0, 120.0)
				if pos.is_empty():
					pos = [p.x, p.y]
				e.web_at = pos
				e.state = "web_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"web_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.webAim):
				while web_count(st) >= int(d.maxWebs):
					for i in st.zones.size():
						if st.zones[i].type == "web":
							st.zones.remove_at(i)
							break
				var at: Array = e.web_at
				var z := st.add_zone("web", float(at[0]), float(at[1]), float(d.webR), float(d.webTtl), 0.0)
				z.slow = float(d.webSlow)
				st.metrics.webs += 1
				st.note_attack(e, "execute")
				e.web_t = float(d.webInterval)
				st.ev("spore")
				to_recover(st, e, 0.5, false)
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "bite")
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

# ---------- G. 서리술사 ----------
static func update_frostcaller(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("cast_t"):
		e.cast_t = 1.5
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			e.cast_t = float(e.cast_t) - dt
			if float(e.cast_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and may_start(st, e, dt): # 위치는 시전 시작 때 확정: 플레이어 위치 + 진행 방향으로 3개
				var ang: float = float(p.face) if bool(p.moving) else st.rng.range_f(0.0, TAU)
				e.cast_ang = ang # 정예 확장(서리 이중술사)이 두 번째 묶음을 **다른 방향**에 놓을 때 읽는다
				var pts := []
				for i in 3:
					var x: float = p.x + cos(ang) * float(d.spacing) * float(i)
					var y: float = p.y + sin(ang) * float(d.spacing) * float(i)
					var pos := st.nearest_valid_pos(clampf(x, 20.0, st.arena_w - 20.0), clampf(y, 20.0, st.arena_h - 20.0), 0.0, 120.0)
					if pos.is_empty():
						pos = [p.x, p.y]
					pts.append(pos)
				e.cast_pts = pts
				e.state = "cast"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.ev("lock")
		"cast":
			e.state_t += adv
			if float(e.state_t) >= float(d.castAim):
				var pts: Array = e.cast_pts
				var delays: Array = d.delays
				for i in pts.size():
					var pt: Array = pts[i]
					var z := st.add_zone("frostzone", float(pt[0]), float(pt[1]), float(d.zoneR), float(delays[i]), 0.0)
					z.order = i + 1
					z.dmg = float(d.damage) * float(e.get("tier_dmg", 1.0)) # 등급 피해 배율(장판은 attacker가 없어 생성 시 적용)
					z.owner = e
				st.note_attack(e, "execute")
				e.cast_t = float(d.castInterval)
				e.cast_pts = []
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 서리 영역 폭발(combat_state.update_zones가 ttl 소진 직전에 호출). 회피 무적·피격 보호 적용(damage_player)
static func detonate(st: CombatState, z: Dictionary) -> void:
	var p := st.player
	if z.type == "frostzone":
		st.fx({ "kind": "frostburst", "x": z.x, "y": z.y, "r": z.r, "ttl": 0.35 })
		st.ev("shatter")
		if PGeom.dist(z.x, z.y, p.x, p.y) <= z.r + p.r:
			st.damage_player(float(z.dmg), "frostzone")

# ---------- H. 쌍날 도적 ----------
static func update_rogue(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if int(e.get("side", 0)) == 0:
		e.side = -1 if st.rng.next() < 0.5 else 1
	match String(e.state):
		"approach":
			if dist > float(d.flankDist):
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			else:
				var n := PGeom.norm(p.x - e.x, p.y - e.y)
				var side: float = float(e.side)
				var tx: float = p.x - n[0] * 30.0 + (-n[1]) * side * float(d.flankOffset)
				var ty: float = p.y - n[1] * 30.0 + n[0] * side * float(d.flankOffset)
				st.approach(e, tx, ty, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) + e.r and may_start(st, e, dt):
				e.state = "slash1_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"slash1_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.aim1):
				e.dir = e.aim_angle
				slash(st, e, d)
				e.state = "slash2_aim"
				e.state_t = 0.0
				e.base_dir = e.dir
				e.aim_angle = e.dir
		"slash2_aim": # 두 번째 베기: 첫 방향에서 ±adjust 안에서만 보정
			var want: float = atan2(p.y - e.y, p.x - e.x)
			var lim: float = PGeom.deg(float(d.adjustDeg))
			e.aim_angle = float(e.base_dir) + clampf(PGeom.ang_diff(float(e.base_dir), want), -lim, lim)
			e.state_t += adv
			if float(e.state_t) >= float(d.aim2):
				e.dir = e.aim_angle
				slash(st, e, d)
				to_recover(st, e, float(d.recover))
		"recover":
			e.state_t += adv
			if float(e.state_t) >= float(e.recover_dur):
				e.state = "approach"
				e.state_t = 0.0
				e.side = -int(e.side)

static func slash(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	var half: float = PGeom.deg(float(d.slashDeg)) / 2.0
	arc_hit(st, e, float(e.dir), float(d.slashRange) + e.r, half, float(d.damage), "slash")
	st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.slashRange) + e.r, "half": half, "ttl": 0.14, "enemy": true })
	e.bite_t = 0.0
	st.note_attack(e, "execute")
	st.ev("boss_sweep")

# ========== 신규 일반 몬스터 3종 (2026-09-09, 시험값 — 정의는 data/pacing.json enemy_tuning · 설명은 docs/MONSTERS.md) ==========
## 공통 규칙은 위 8종과 같다: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음.

# ---------- I. 흡혈 박쥐: 접근 → 짧은 물기 → 이탈 ----------
## 늑대처럼 계속 붙어 걷지 않는다. 물면 **반드시 이탈**하고, 이탈·선회가 끝나야 다시 접근한다.
## 빠르지만 **무예고 접촉 피해가 없다** — 짧아도 bite_aim 예고를 지나야 물기 판정이 생긴다.
## **회복(흡혈) 기능은 넣지 않았다.** 이름이 흡혈이라도 적 회복 수치는 사용자 결정 사항이므로
## 규칙에도 정의에도 회복 경로를 두지 않았다. 넣을 때 필요한 값은 docs/MONSTERS.md에 적어 뒀다.
static func update_bat(st: CombatState, e: Dictionary, dt: float) -> void:
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach": # 접근: 빠르게 파고든다(닿아도 피해 없음)
			st.approach(e, p.x, p.y, dv(e, "speed", 0.0) * sm, dt)
			if dist <= dv(e, "engageDist", 0.0) + float(e.r) and may_start(st, e, dt):
				e.state = "bite_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
		"bite_aim": # 공격 예고(짧다). 여기를 지나야만 피해가 생긴다
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "biteAim", 0.0):
				e.dir = e.aim_angle
				e.state = "bite"
				e.state_t = 0.0
				var half: float = PGeom.deg(dv(e, "biteDeg", 0.0)) / 2.0
				arc_hit(st, e, float(e.dir), dv(e, "biteRange", 0.0) + float(e.r), half, dv(e, "biteDamage", 0.0), "bat_bite")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": dv(e, "biteRange", 0.0) + float(e.r), "half": half, "ttl": 0.12, "enemy": true })
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				st.ev("bite")
		"bite":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "biteActive", 0.0):
				e.state = "leave"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "이탈", "#cfe3ff")
		"leave": # 이탈: 물었든 빗나갔든 반드시 물러난다(붙어 걷기 금지)
			e.state_t += adv
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, dv(e, "leaveSpeed", 0.0) * sm, dt)
			if float(e.state_t) >= dv(e, "leaveTime", 0.0):
				e.state = "hover"
				e.state_t = 0.0
		"hover": # 거리를 둔 채 선회하는 빈틈. 너무 가까우면 더 물러난다
			e.state_t += adv
			if dist < dv(e, "hoverDist", 0.0):
				st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, dv(e, "speed", 0.0) * 0.6 * sm, dt)
			if float(e.state_t) >= dv(e, "hoverTime", 0.0):
				e.state = "approach"
				e.state_t = 0.0

# ---------- J. 불씨 도마뱀: 멈춰서 준비하는 긴 화염 ----------
## 중거리까지 온 뒤 **멈춰서** 준비한다(flame_aim·flame_lock 동안 이동 명령이 없다).
## 입에서 이어지는 긴 좁은 불줄기 자체가 공격 범위다. **잔류 장판을 만들지 않는다.**
## 유지 중에는 flameTurn(rad/s) 상한으로 **천천히만** 돌아온다 — 갑자기 뒤집거나 즉시 따라잡지 않는다.
## 지속 피해는 flameTick 간격으로만 계산한다(공통 피격 보호 0.60초보다 크게 잡았다).
static func update_lizard(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("flame_t"):
		e.flame_t = 1.2
		e.flame_tick = 0.0
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			e.flame_t = float(e.flame_t) - dt
			if float(e.flame_t) <= 0.0 and dist <= dv(e, "keepMax", 0.0) + 40.0 \
				and not st.los_blocked(e.x, e.y, p.x, p.y) and may_start(st, e, dt):
				e.state = "flame_aim"
				e.state_t = 0.0
				e.ready_t = -1.0
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				st.note_attack(e, "prepare")
				st.text(e.x, e.y - float(e.r) - 26.0, "화염 준비", "#ff9f43")
		"flame_aim": # **멈춰서** 준비(이동 명령 없음). 입이 밝아지며 첫 발사 방향을 예고한다
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "flameAim", 0.0):
				e.state = "flame_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 첫 발사 방향 확정
				st.ev("lock")
		"flame_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "flameLock", 0.0):
				e.state = "flame"
				e.state_t = 0.0
				e.flame_tick = 0.0
				st.note_attack(e, "execute")
				st.ev("shoot")
		"flame": # 불줄기 유지. 회전 상한이 있고, 장판을 남기지 않는다
			e.state_t += adv
			var want: float = atan2(p.y - e.y, p.x - e.x)
			var mx: float = dv(e, "flameTurn", 0.0) * adv
			e.dir = float(e.dir) + clampf(PGeom.ang_diff(float(e.dir), want), -mx, mx)
			var seg := flame_seg(st, e, float(e.dir))
			e.flame_tick = float(e.flame_tick) - adv
			if float(e.flame_tick) <= 0.0:
				e.flame_tick = dv(e, "flameTick", 0.5) # 명시된 틱 간격
				if PGeom.in_beam(float(seg[0]), float(seg[1]), float(e.dir), float(seg[2]), dv(e, "flameW", 0.0), p.x, p.y, float(p.r)):
					st.damage_player(dv(e, "flameDamage", 0.0), "lizard_flame", e)
			if fmod(float(e.state_t), 0.15) < adv: # 불꽃 표시(연출만. 판정은 위 줄이 전부다)
				st.fx({ "kind": "burst", "x": float(seg[0]) + cos(float(e.dir)) * float(seg[2]), "y": float(seg[1]) + sin(float(e.dir)) * float(seg[2]), "r": dv(e, "flameW", 0.0) * 0.5, "ttl": 0.2, "color": "#ff9f43" })
			if float(e.state_t) >= dv(e, "flameDur", 0.0):
				e.flame_t = dv(e, "flameInterval", 0.0)
				to_recover(st, e, dv(e, "recover", 0.0)) # 반격할 빈틈
		"recover":
			_recover_tick(e, adv)

## 불줄기 = [입 x, 입 y, 길이]. **입에서 시작해** 장애물에 막히는 데까지 이어진다(예고와 실제가 같은 계산)
static func flame_seg(st: CombatState, e: Dictionary, ang: float) -> Array:
	var mx: float = e.x + cos(ang) * float(e.r)
	var my: float = e.y + sin(ang) * float(e.r)
	return [mx, my, st.beam_length(mx, my, ang, dv(e, "flameLen", 0.0))]

# ---------- K. 도약 두꺼비: 예고·확정된 착지 ----------
## 웅크리기(crouch) 동안에만 착지 원이 플레이어를 따라가고, 예고(leap_warn)에 들어가는 순간 **확정**된다.
## 확정 뒤에는 공중에서 방향을 바꾸지 않는다(직선 보간). 착지 자리는 바위 안·맵 밖이 아니고,
## 그 자리에서 다시 나올 길이 있으며, **다른 두꺼비의 확정된 착지 원까지 합쳐** 플레이어의 탈출 방향이
## 남아 있는 곳만 쓴다. 조건을 만족하는 자리가 없으면 도약을 취소한다.
static func update_toad(st: CombatState, e: Dictionary, dt: float) -> void:
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("leap_t"):
		e.leap_t = 1.0
	match String(e.state):
		"approach":
			e.leap_t = float(e.leap_t) - dt
			if dist > dv(e, "minDist", 0.0):
				st.approach(e, p.x, p.y, dv(e, "speed", 0.0) * sm, dt)
			if float(e.leap_t) <= 0.0 and dist <= dv(e, "engageDist", 0.0) and may_start(st, e, dt):
				var first := leap_spot(st, e)
				if first.is_empty(): # 지금은 안전한 착지 자리가 없다 — 잠시 뒤 다시 본다
					e.leap_t = 0.5
					e.ready_t = -1.0
					return
				e.leap_at = first
				e.state = "crouch"
				e.state_t = 0.0
				e.ready_t = -1.0
				st.note_attack(e, "prepare")
				st.text(e.x, e.y - float(e.r) - 26.0, "도약 준비", "#9cff9c")
		"crouch": # 웅크리기: 착지 원이 아직 따라온다(확정 전)
			e.state_t += adv
			var track := leap_spot(st, e)
			if not track.is_empty():
				e.leap_at = track
			if float(e.state_t) >= dv(e, "crouch", 0.0):
				var spot := leap_spot(st, e)
				if spot.is_empty(): # 확정할 자리가 없으면 도약을 취소한다(억지로 내려앉지 않는다)
					e.leap_t = dv(e, "leapInterval", 0.0) * 0.5
					e.erase("leap_at")
					to_recover(st, e, dv(e, "recover", 0.0) * 0.5, false)
					return
				e.leap_at = spot
				e.state = "leap_warn"
				e.state_t = 0.0
				st.ev("lock")
				st.ev("hazard_warn")
		"leap_warn": # 착지 위치 **확정**. 여기서부터 절대 바뀌지 않는다
			e.state_t += adv
			if float(e.state_t) >= dv(e, "warn", 0.0):
				e.state = "leap"
				e.state_t = 0.0
				e.leap_from = [e.x, e.y]
				e.airborne = true
				st.note_attack(e, "execute")
		"leap": # 확정된 지점까지 직선 보간. 공중에서 플레이어를 따라 꺾지 않는다
			e.state_t += adv
			var at: Array = e.leap_at
			var fr: Array = e.leap_from
			var k: float = clampf(float(e.state_t) / maxf(0.001, dv(e, "leapTime", 0.0)), 0.0, 1.0)
			e.x = float(fr[0]) + (float(at[0]) - float(fr[0])) * k
			e.y = float(fr[1]) + (float(at[1]) - float(fr[1])) * k
			if k >= 1.0:
				e.airborne = false
				e.state = "land"
				e.state_t = 0.0
				circle_hit(st, e, e.x, e.y, dv(e, "landR", 0.0), dv(e, "landDamage", 0.0), "toad_land")
		"land":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "landActive", 0.1):
				e.leap_t = dv(e, "leapInterval", 0.0)
				to_recover(st, e, dv(e, "recover", 0.0)) # 착지 후 빈틈
		"recover":
			_recover_tick(e, adv)

## 착지 후보 자리(중심에서 바깥으로). 노린 자리가 막히면 둘레를 차례로 본다
const TOAD_TRY := [[0.0, 0.0], [64.0, 0.0], [-64.0, 0.0], [0.0, 64.0], [0.0, -64.0], [46.0, 46.0], [-46.0, 46.0], [46.0, -46.0], [-46.0, -46.0]]

## 착지 지점 고르기. 조건을 다 만족하는 첫 자리를 돌려주고, 없으면 빈 배열(도약 취소)
##  ① 사거리 상한 안의 플레이어 자리를 노린다
##  ② **바위 안·맵 밖 금지**(nearest_valid_pos는 유효 위치만 돌려준다)
##  ③ 착지 지점에서 다시 나올 길이 있어야 한다(사방이 막힌 곳에 갇히지 않는다)
##  ④ 지금 착지 지점이 **확정된 다른 두꺼비들의 원까지 합쳐** 플레이어 주위 탈출 방향이 minExits개 이상 남아야 한다
static func leap_spot(st: CombatState, e: Dictionary) -> Array:
	var p := st.target_of(e)
	var max_range: float = dv(e, "leapRange", 0.0)
	var land_r: float = dv(e, "landR", 0.0)
	var probe: float = dv(e, "probe", 0.0)
	var need: int = int(dv(e, "minExits", 0.0))
	var others := locked_leaps(st, e)
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var dd := sqrt(dx * dx + dy * dy)
	var k: float = 1.0 if dd <= max_range or dd < 1e-6 else max_range / dd
	for off in TOAD_TRY:
		var cx: float = clampf(e.x + dx * k + float(off[0]), float(e.r), st.arena_w - float(e.r))
		var cy: float = clampf(e.y + dy * k + float(off[1]), float(e.r), st.arena_h - float(e.r))
		var pos := st.nearest_valid_pos(cx, cy, float(e.r), 140.0)
		if pos.is_empty():
			continue
		if _pos_exits(st, float(pos[0]), float(pos[1]), float(e.r), probe) <= 0:
			continue
		var dangers: Array = others.duplicate()
		dangers.append({ "x": float(pos[0]), "y": float(pos[1]), "r": land_r })
		if _exits_open(st, dangers, probe) < need:
			continue
		return [float(pos[0]), float(pos[1])]
	return []

## 지금 착지 위치가 **확정된** 다른 두꺼비들의 착지 원(정예 확장 포함). 예고 중인 것만 센다
static func locked_leaps(st: CombatState, e: Dictionary) -> Array:
	var out: Array = []
	for o in st.enemies:
		if o == e or bool(o.dead) or base_type(String(o.type)) != "toad":
			continue
		if not o.has("leap_at"):
			continue
		var s := String(o.state)
		if s != "leap_warn" and s != "leap":
			continue
		var at: Array = o.leap_at
		out.append({ "x": float(at[0]), "y": float(at[1]), "r": dv(o, "landR", 0.0) })
	return out

## 그 자리에서 probe 거리로 걸어 나갈 수 있는 방향 수(16방향 중 유효 위치인 것)
static func _pos_exits(st: CombatState, x: float, y: float, r: float, probe: float) -> int:
	var n := 0
	for i in 16:
		var a := float(i) / 16.0 * TAU
		if st.valid_pos(x + cos(a) * probe, y + sin(a) * probe, r):
			n += 1
	return n

# ========== 특수 정예 7종 (2026-09-08, 시험값 — data/enemies.json 정의 · data/elites.json 배치표 · docs/ELITES.md) ==========
## 공통 규칙
##  - 예고 → 방향(위치) 확정 → 실행 → 빈틈. 확정 뒤에는 추적하지 않으므로 회피가 통한다.
##  - 연계 시작 전에 CombatState.may_attack을 그대로 쓴다(위험 공격 동시 제한). 거기에 **정예 동시 연계 1**을
##    더한다(보완): 일반 전투는 overlap_limit이 0이라 may_attack이 항상 참이므로, 정예끼리 연계를 겹쳐
##    탈출 불가능한 상황을 만들지 않도록 이 한 줄만 추가한다. 일반 적의 압박은 줄이지 않는다.
##  - 무조건 명중·회피 불가 공격·강제 피해 할당량은 쓰지 않는다. 모든 피해는 st.damage_player(회피·피격 보호가 그대로 작동).

## 지금 연계 중인 다른 정예가 있는가(정예 동시 연계 상한 1, 시험값)
static func elite_busy(st: CombatState, e: Dictionary) -> bool:
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.get("boss", false)):
			continue
		if is_elite(String(o.type)) and is_committed(o):
			return true
	return false

## 연계를 시작해도 되는가: 기존 동시 제한(may_attack) + 정예 동시 연계 1
static func elite_may_start(st: CombatState, e: Dictionary, dt: float) -> bool:
	if elite_busy(st, e):
		e.ready_t = -1.0
		return false
	return may_start(st, e, dt)

## 예고 시작 공통 처리(계측·표시)
static func elite_begin(st: CombatState, e: Dictionary, state: String, label: String = "", color: String = "#ffb0b0") -> void:
	e.state = state
	e.state_t = 0.0
	e.ready_t = -1.0
	st.note_attack(e, "prepare")
	if label != "":
		st.text(e.x, e.y - float(e.r) - 30.0, label, color)

## 느린 방향 전환(방패 자세·조준 유지용). 반환 = 남은 각도 차이
static func face_toward(e: Dictionary, tx: float, ty: float, rate: float, adv: float) -> float:
	if not e.has("face"):
		e.face = atan2(ty - float(e.y), tx - float(e.x))
	var want: float = atan2(ty - float(e.y), tx - float(e.x))
	var diff := PGeom.ang_diff(float(e.face), want)
	var mx: float = rate * adv
	e.face = float(e.face) + clampf(diff, -mx, mx)
	return diff

## 원형 착탄(장애물 가림 없음 — 바닥에 떨어지는 충격). 맞으면 true
static func circle_hit(st: CombatState, e: Dictionary, cx: float, cy: float, r: float, dmg: float, src: String) -> bool:
	var p := st.target_of(e)
	var hit := false
	if PGeom.dist(cx, cy, p.x, p.y) <= r + float(p.r):
		hit = st.damage_player(dmg, src, e)
	st.fx({ "kind": "bossland", "x": cx, "y": cy, "r": r, "ttl": 0.4 })
	st.ev("boss_land")
	st.note_attack(e, "execute")
	return hit

## 옆으로 이동(재장전·자리 옮기기). side = -1|1
static func strafe(st: CombatState, e: Dictionary, speed: float, dt: float) -> void:
	var p := st.target_of(e)
	var n := PGeom.norm(p.x - e.x, p.y - e.y)
	if int(e.get("side", 0)) == 0:
		e.side = -1 if st.rng.next() < 0.5 else 1
	var s: float = float(e.side)
	st.approach(e, e.x + (-n[1]) * s * 120.0, e.y + n[0] * s * 120.0, speed, dt)

# ---------- A. 정예 궁수(추격 사수) ----------
## 첫 조준 0.70초(추적 0.58 + 방향 고정 0.12) → 단발 3회(간격 0.50초 = 재조준 0.38 + 고정 0.12)
## → 별도 예고 0.75초(추적 0.60 + 고정 0.15) 뒤 부채꼴 3발 → 측면 이동·재장전 1.4초 빈틈.
## 발사 방향은 shot_lock/fan_lock 시작 때 고정한다(그 뒤에는 플레이어를 따라가지 않는다).
static func update_elite_archer(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("shot_left"):
		e.shot_left = int(d.shots)
		e.blocked_sec = 0.0
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			var blocked: bool = st.los_blocked(e.x, e.y, p.x, p.y)
			e.blocked_sec = (float(e.blocked_sec) + dt) if blocked else 0.0
			if float(e.blocked_sec) >= float(d.blockedLimit): # 장애물에 계속 막히면 사격 위치를 바꾼다
				e.blocked_sec = 0.0
				e.side = -int(e.get("side", 1))
				e.state = "reposition"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "자리 옮김", "#cfe3ff")
				return
			if not blocked and dist <= float(d.keepMax) + 60.0 and elite_may_start(st, e, dt):
				e.shot_left = int(d.shots)
				elite_begin(st, e, "aim", "조준", "#ffd166")
		"reposition":
			e.state_t += dt
			strafe(st, e, float(d.strafeSpeed) * sm, dt)
			if float(e.state_t) >= float(d.strafeTime):
				e.state = "approach"
				e.state_t = 0.0
		"aim": # 매 발 재조준(추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			var need: float = float(d.aim) if int(e.shot_left) == int(d.shots) else float(d.reaim)
			if float(e.state_t) >= need:
				e.state = "shot_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 방향 확정 — 여기서부터 추적하지 않는다
				st.ev("lock")
		"shot_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.lock):
				_arrow(st, e, float(e.dir), float(d.arrowSpeed), float(d.arrowR), float(d.arrowDamage))
				st.note_attack(e, "execute")
				e.shot_left = int(e.shot_left) - 1
				if int(e.shot_left) > 0:
					e.state = "aim"
					e.state_t = 0.0
				else:
					e.state = "fan_aim"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "부채꼴 3발", "#ff9f43")
		"fan_aim": # 별도 예고(추적)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.fanAim):
				e.state = "fan_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 중앙 화살 방향 확정
				st.ev("lock")
		"fan_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.fanLock):
				var n: int = int(d.fanCount)
				var step: float = PGeom.deg(float(d.fanDeg))
				for i in n:
					var off: float = (float(i) - float(n - 1) / 2.0) * step
					_arrow(st, e, float(e.dir) + off, float(d.arrowSpeed), float(d.arrowR), float(d.fanDamage))
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.recover))
		"recover": # 측면 이동·재장전
			strafe(st, e, float(d.strafeSpeed) * sm, dt)
			_recover_tick(e, adv)
			if String(e.state) == "approach":
				e.side = -int(e.get("side", 1))

static func _arrow(st: CombatState, e: Dictionary, ang: float, speed: float, r: float, dmg: float) -> void:
	var pr := { "owner": "enemy", "kind": "arrow", "shooter": e, "x": e.x + cos(ang) * (float(e.r) + 4.0), "y": e.y + sin(ang) * (float(e.r) + 4.0),
		"vx": cos(ang) * speed, "vy": sin(ang) * speed, "r": r, "dmg": dmg, "ttl": 4.0, "angle": ang, "dead": false, "hits": {} }
	CombatState.stamp_projectile(e, pr)
	st.projectiles.append(pr)
	st.ev("shoot")

# ---------- B. 정예 검사(철갑 추격자) ----------
## 돌진 베기(예고 0.65) → 새 방향 예고(0.50) → 두 번째 돌진 베기 → 방패 자세 1.5초 → 내려찍기 → 빈틈 1.0초.
## 돌진 중에는 추적 회전이 없다(확정 각 그대로). 방패 자세는 **정면 직접 피해 완전 차단**(guardMult 0.0) —
## 일반 방패병의 85% 감소(frontMult 0.15)와 구분된다. 측·후면과 바닥 피해는 그대로 들어간다.
static func update_elite_blademaster(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	face_toward(e, p.x, p.y, float(d.guardTurn) if String(e.state) == "guard" else 6.0, adv)
	match String(e.state):
		"approach":
			if dist < float(d.minDist): # 붙어 있으면 스스로 거리를 만든다(밀어붙이기 금지 — 멧돼지와 같은 규칙)
				e.state = "backoff"
				e.state_t = 0.0
				return
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and not st.los_blocked(e.x, e.y, p.x, p.y) and elite_may_start(st, e, dt):
				elite_begin(st, e, "dash1_aim", "돌진 베기 1/2", "#ffb0b0")
		"backoff": # 최대 1.2초 물러난다(벽에 막히면 접선). 거리가 벌어지면 돌진 연계로, 끝까지 붙어 있으면 근접 연계(방패 자세 → 내려찍기)로
			e.state_t += dt
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.speed) * sm, dt)
			if dist >= float(d.minDist) + 30.0:
				e.state = "approach"
				e.state_t = 0.0
			elif float(e.state_t) >= float(d.backoffTime) and elite_may_start(st, e, dt):
				elite_begin(st, e, "guard", "방패 자세(정면 차단)", "#a9d8ff")
		"dash1_aim", "dash2_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			var first: bool = String(e.state) == "dash1_aim"
			e.preview = PBoss.dash_path(st, e, float(e.aim_angle), float(d.dashDist))
			if float(e.state_t) >= (float(d.aim1) if first else float(d.aim2)):
				var path := PBoss.dash_path(st, e, float(e.aim_angle), float(d.dashDist))
				e.dir = e.aim_angle # 방향 확정 — 돌진 중 추적 회전 금지
				e.charge_len = float(path["len"])
				e.charge_end = path.end
				e.charge_dist = 0.0
				e.hit_done = false
				e.state = "dash1_lock" if first else "dash2_lock"
				e.state_t = 0.0
				st.ev("lock")
		"dash1_lock", "dash2_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.lock):
				e.state = "dash1" if String(e.state) == "dash1_lock" else "dash2"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"dash1", "dash2":
			if _charge_step(st, e, float(d.dashSpeed), float(d.dashDamage), "elite_blade", dt, tf):
				if String(e.state) == "dash1":
					e.state = "dash2_aim"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "돌진 베기 2/2", "#ffb0b0")
				else:
					e.state = "guard"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "방패 자세(정면 차단)", "#a9d8ff")
		"guard": # 정면 직접 피해 완전 차단. 방향 전환은 느리다(측·후면이 답)
			e.state_t += adv
			st.approach(e, p.x, p.y, float(d.speed) * float(d.guardSpeed) * sm, dt)
			if float(e.state_t) >= float(d.guardDur):
				elite_begin(st, e, "slam_aim", "내려찍기", "#ff9f43")
		"slam_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.slamAim):
				circle_hit(st, e, e.x + cos(float(e.face)) * float(d.slamOffset), e.y + sin(float(e.face)) * float(d.slamOffset), float(d.slamR), float(d.slamDamage), "elite_slam")
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 확정 경로를 따라 한 단계 돌진(감속되어도 경로·거리 그대로). 반환 true = 끝(거리 도달·충돌)
static func _charge_step(st: CombatState, e: Dictionary, speed: float, dmg: float, src: String, dt: float, tf: float) -> bool:
	var p := st.target_of(e)
	var remain: float = maxf(0.0, float(e.charge_len) - float(e.charge_dist))
	var stp: float = minf(speed * tf * dt, remain)
	var x0: float = e.x
	var y0: float = e.y
	var mv := st.move_swept(e, cos(float(e.dir)) * stp, sin(float(e.dir)) * stp)
	e.charge_dist = float(e.charge_dist) + PGeom.dist(e.x, e.y, x0, y0)
	if not bool(e.hit_done) and PGeom.seg_circle(x0, y0, e.x, e.y, p.x, p.y, float(p.r) + float(e.r)):
		e.hit_done = true
		e.bite_t = 0.0
		st.ev("bite")
		st.damage_player(dmg, src, e)
	return float(e.charge_dist) >= float(e.charge_len) - 1e-6 or String(mv.hit) != "" or stp <= 1e-9

# ---------- C. 피의 송곳니(정예 늑대) ----------
## 측면으로 돌아 접근 → 짧은 물기(예고 0.35) → 짧게 이탈 0.5초 → 착지 예고(추적 0.60 + 확정 0.15) →
## 도약 공격 → 빈틈 1.1초. 착지 위치는 leap_lock 시작 때 확정하고 그 뒤 추적하지 않는다.
## 도약이 빗나가면(착지 원 밖) 더 긴 빈틈 1.6초 — '도약 실패 = 공격 기회'.
static func update_elite_fang(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if int(e.get("side", 0)) == 0:
		e.side = -1 if st.rng.next() < 0.5 else 1
	match String(e.state):
		"approach": # 정면이 아니라 옆으로 돌아 붙는다
			if dist > float(d.flankDist):
				st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			else:
				var n := PGeom.norm(p.x - e.x, p.y - e.y)
				var s: float = float(e.side)
				st.approach(e, p.x - n[0] * 26.0 + (-n[1]) * s * float(d.flankOffset), p.y - n[1] * 26.0 + n[0] * s * float(d.flankOffset), float(d.speed) * sm, dt)
			if dist <= float(d.biteRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "bite_aim", "", "#ffb0b0")
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "elite_bite")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.biteRange) + e.r, "half": PGeom.deg(float(d.biteDeg)) / 2.0, "ttl": 0.14, "enemy": true })
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				st.ev("bite")
				e.state = "backoff"
				e.state_t = 0.0
		"backoff": # 짧게 이탈(도약 거리 확보)
			e.state_t += adv
			st.approach(e, e.x * 2.0 - p.x, e.y * 2.0 - p.y, float(d.backoffSpeed) * sm, dt)
			if float(e.state_t) >= float(d.backoffTime):
				elite_begin(st, e, "leap_aim", "도약", "#ff9f43")
		"leap_aim": # 착지 지점 예고(추적)
			e.state_t += adv
			e.leap_at = _leap_target(st, e, float(d.leapRange))
			if float(e.state_t) >= float(d.leapAim):
				e.state = "leap_lock"
				e.state_t = 0.0
				e.leap_at = _leap_target(st, e, float(d.leapRange)) # 착지 위치 확정 — 여기서부터 추적하지 않는다
				e.leap_from = [e.x, e.y]
				st.ev("lock")
		"leap_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.leapLock):
				e.state = "leap"
				e.state_t = 0.0
				e.airborne = true
				st.note_attack(e, "execute")
		"leap": # 확정된 착지점까지 포물선 이동(공중이라 밀리지 않는다)
			e.state_t += adv
			var at: Array = e.leap_at
			var fr: Array = e.leap_from
			var k: float = clampf(float(e.state_t) / float(d.leapTime), 0.0, 1.0)
			e.x = float(fr[0]) + (float(at[0]) - float(fr[0])) * k
			e.y = float(fr[1]) + (float(at[1]) - float(fr[1])) * k
			if k >= 1.0:
				e.airborne = false
				var hit := circle_hit(st, e, e.x, e.y, float(d.leapR), float(d.leapDamage), "elite_leap")
				if hit:
					to_recover(st, e, float(d.recover))
				else: # 도약 실패 — 더 긴 빈틈(공격 기회)
					e.state = "stagger"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 26.0, "빗나감 — 큰 빈틈!", "#ffd166")
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.missStagger):
				e.state = "approach"
				e.state_t = 0.0
				e.side = -int(e.side)
		"recover":
			_recover_tick(e, adv)
			if String(e.state) == "approach":
				e.side = -int(e.side)

## 착지 지점: 플레이어 위치(사거리 상한), 지형 안이면 가장 가까운 유효 위치
static func _leap_target(st: CombatState, e: Dictionary, max_range: float) -> Array:
	var p := st.target_of(e)
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var dd := sqrt(dx * dx + dy * dy)
	var k: float = 1.0 if dd <= max_range or dd < 1e-6 else max_range / dd
	var pos := st.nearest_valid_pos(e.x + dx * k, e.y + dy * k, float(e.r), 160.0)
	return pos if not pos.is_empty() else [e.x, e.y]

# ---------- D. 역병 조율사(정예 포자) ----------
## 포자 3개를 흩어 투척(예고 0.5) → 부풀기 0.9초 → 0.45초 간격 순차 폭발 → 재정비 1.5초.
## 잔류 구름은 수(3)·시간(2.6초) 상한이 있고, 전장 전체를 덮지 않도록 배치 전에 탈출 방향 수를 확인한다.
## 근접(96 이내)에는 예고된 좁은 포자 분출(70°)로 대응한다.
static func update_elite_plaguecaller(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("cast_t"):
		e.cast_t = 0.4
		e.pods = []
	e.cast_t = float(e.cast_t) - dt # 재사용은 상태와 무관하게 흐른다(붙어서 분출만 반복하면 주 연계를 못 보게 되기 때문)
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			# 주 무기는 포자 3개다. 분출은 '붙었는데 아직 포자가 준비되지 않았을 때'의 대응이지 기본 행동이 아니다
			if float(e.cast_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "throw_aim", "포자 3개", "#9cff9c")
				return
			if dist <= float(d.burstRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "burst_aim", "포자 분출", "#9cff9c")
		"throw_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.throwAim):
				e.pods = _place_pods(st, e)
				e.state = "swell"
				e.state_t = 0.0
				st.ev("spore")
				st.ev("hazard_warn")
		"swell": # 부풀기 → 순차 폭발(각 포자의 정해진 시각). 모두 터지면 재정비
			e.state_t += adv
			_update_pods(st, e, d)
			var left := false
			for pod in e.pods:
				if not bool(pod.done):
					left = true
			if not left:
				e.cast_t = float(d.castInterval)
				to_recover(st, e, float(d.recover))
		"burst_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.burstAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.burstRange) + e.r, PGeom.deg(float(d.burstDeg)) / 2.0, float(d.burstDamage), "elite_spore_burst")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.burstRange) + e.r, "half": PGeom.deg(float(d.burstDeg)) / 2.0, "ttl": 0.16, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("spore")
				to_recover(st, e, float(d.burstRecover))
		"recover":
			keep_distance(st, e, d, dt, sm)
			_recover_tick(e, adv)

## 포자 3개 배치: 플레이어 주위에 흩어 놓되, 놓고 나서도 탈출 방향이 minExits개 이상 남는 자리만 쓴다
static func _place_pods(st: CombatState, e: Dictionary) -> Array:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var base: float = float(p.face) if bool(p.moving) else atan2(p.y - e.y, p.x - e.x)
	var pods: Array = []
	for i in int(d.podCount):
		var a: float = base + PGeom.deg(float(d.podArcDeg)) * (float(i) - float(int(d.podCount) - 1) / 2.0)
		var cx: float = p.x + cos(a) * float(d.podSpread)
		var cy: float = p.y + sin(a) * float(d.podSpread)
		var pos := st.nearest_valid_pos(clampf(cx, 20.0, st.arena_w - 20.0), clampf(cy, 20.0, st.arena_h - 20.0), 0.0, 120.0)
		if pos.is_empty():
			continue
		var trial := { "x": float(pos[0]), "y": float(pos[1]), "r": float(d.podR) }
		var all: Array = pods.duplicate()
		all.append(trial)
		if _exits_open(st, all, float(d.probe)) < int(d.minExits): # 전장을 통째로 막지 않는다
			continue
		trial["order"] = pods.size() + 1
		trial["land_at"] = st.t + float(d.swell) + float(pods.size()) * float(d.podGap)
		trial["done"] = false
		pods.append(trial)
	return pods

static func _update_pods(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	for pod in e.pods:
		if bool(pod.done) or st.t < float(pod.land_at):
			continue
		pod.done = true
		circle_hit(st, e, float(pod.x), float(pod.y), float(pod.r), float(d.podDamage), "elite_spore")
		var z := st.add_zone("spore", float(pod.x), float(pod.y), float(pod.r) * 0.8, float(d.cloudTtl), float(d.cloudDamage) * float(e.get("tier_dmg", 1.0)))
		z.owner = e
		_trim_clouds(st, e, int(d.maxClouds))
		st.ev("spore")

## 이 개체가 남긴 구름 수 상한(오래된 것부터 제거). 전역 장판 상한(PPacing)과 별개로 개체 몫을 제한한다
static func _trim_clouds(st: CombatState, e: Dictionary, cap: int) -> void:
	var mine := []
	for z in st.zones:
		if String(z.type) == "spore" and z.get("owner") == e:
			mine.append(z)
	while mine.size() > cap:
		var oldest: Dictionary = mine[0]
		for z in mine:
			if float(z.t) > float(oldest.t):
				oldest = z
		st.zones.erase(oldest)
		mine.erase(oldest)

## 플레이어 주위 16방향 중 probe 거리 지점이 위험 원에 덮이지 않은 방향 수(PBoss3.exits_open과 같은 규칙)
static func _exits_open(st: CombatState, dangers: Array, probe: float) -> int:
	var p := st.player
	var free := 0
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var x: float = p.x + cos(a) * probe
		var y: float = p.y + sin(a) * probe
		if x < float(p.r) or y < float(p.r) or x > st.arena_w - float(p.r) or y > st.arena_h - float(p.r):
			continue
		var blocked := false
		for dz in dangers:
			if PGeom.dist(float(dz.x), float(dz.y), x, y) <= float(dz.r) + float(p.r):
				blocked = true
				break
		if not blocked:
			free += 1
	return free

# ---------- E. 사슬 집행자 ----------
## 직선 사슬 예고(추적 0.60 + 확정 0.15) → 발사(사슬은 바위에 막힌다) → 명중 시 짧은 끌기 0.35초 →
## 내려찍기 예고 0.55 + 확정 0.15 → 강타. 끌린 뒤 강타까지 0.70초의 **입력 기회**가 반드시 남는다(고정값, 시험값).
## 빗나가면 회수 빈틈 1.4초. 근접(72 이내)에서 돌면 예고된 횡베기로 대응한다.
static func update_elite_chainbreaker(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	match String(e.state):
		"approach":
			keep_distance(st, e, d, dt, sm)
			if dist <= float(d.nearDist) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "sweep_aim", "횡베기", "#ffb0b0")
				return
			if dist <= float(d.engageDist) and not st.los_blocked(e.x, e.y, p.x, p.y) and elite_may_start(st, e, dt):
				elite_begin(st, e, "chain_aim", "사슬", "#ffd166")
		"chain_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			e.chain_len = st.beam_length(e.x, e.y, float(e.aim_angle), float(d.chainLen)) # 예고와 실제가 같은 계산(바위에서 끊긴다)
			if float(e.state_t) >= float(d.chainAim):
				e.state = "chain_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 방향 확정
				e.chain_len = st.beam_length(e.x, e.y, float(e.dir), float(d.chainLen))
				e.chain_d = 0.0
				st.ev("lock")
		"chain_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.chainLock):
				e.state = "chain_fly"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"chain_fly": # 사슬 머리가 확정된 직선을 따라 나아간다
			var d0: float = float(e.chain_d)
			e.chain_d = minf(float(e.chain_len), d0 + float(d.chainSpeed) * adv)
			var hx0: float = e.x + cos(float(e.dir)) * d0
			var hy0: float = e.y + sin(float(e.dir)) * d0
			var hx1: float = e.x + cos(float(e.dir)) * float(e.chain_d)
			var hy1: float = e.y + sin(float(e.dir)) * float(e.chain_d)
			if PGeom.seg_circle(hx0, hy0, hx1, hy1, p.x, p.y, float(p.r) + float(d.chainW) / 2.0):
				if st.damage_player(float(d.chainDamage), "elite_chain", e): # 회피·피격 보호로 막히면 끌기도 없다
					e.state = "pull"
					e.state_t = 0.0
					e.pull_from = [p.x, p.y]
					st.ev("bite")
					st.text(p.x, p.y - 34.0, "끌림!", "#ff9f43")
					return
				e.chain_d = float(e.chain_len) # 회피됨 — 회수
			if float(e.chain_d) >= float(e.chain_len) - 1e-6:
				e.state = "retract"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "회수 — 빈틈!", "#ffd166")
		"pull": # 짧은 끌기(장애물·벽은 그대로 막는다)
			e.state_t += adv
			var want: float = float(d.pullTo) + float(e.r) + float(p.r)
			var cur := PGeom.dist(e.x, e.y, p.x, p.y)
			if cur > want:
				var n := PGeom.norm(e.x - p.x, e.y - p.y)
				var stp: float = minf(float(d.pullSpeed) * dt, cur - want)
				st.move_swept(p, n[0] * stp, n[1] * stp, true)
			if float(e.state_t) >= float(d.pullTime):
				# 강타 위치는 **예고 시작 때** 확정한다(예외를 의도적으로 둔다):
				# 끌기로 자리를 강제한 직후이므로, 여기서도 추적하면 회피할 입력 기회가 사라진다.
				# 그래서 slam_aim 0.55 + slam_lock 0.15 = 0.70초 동안 원의 위치가 고정이고 걸어서 벗어날 수 있다.
				e.slam_at = [p.x, p.y]
				elite_begin(st, e, "slam_aim", "강타", "#ff9f43")
		"slam_aim": # 확정된 자리에 원이 고정된 채 0.55초 — 회피할 입력 기회
			e.state_t += adv
			if float(e.state_t) >= float(d.slamAim):
				e.state = "slam_lock"
				e.state_t = 0.0
				st.ev("lock")
		"slam_lock":
			e.state_t += adv
			if float(e.state_t) >= float(d.slamLock):
				var at: Array = e.slam_at
				circle_hit(st, e, float(at[0]), float(at[1]), float(d.slamR), float(d.slamDamage), "elite_chain_slam")
				to_recover(st, e, float(d.recover))
		"sweep_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.sweepAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.sweepRange) + e.r, PGeom.deg(float(d.sweepDeg)) / 2.0, float(d.sweepDamage), "elite_chain_sweep")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.sweepRange) + e.r, "half": PGeom.deg(float(d.sweepDeg)) / 2.0, "ttl": 0.16, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("boss_sweep")
				to_recover(st, e, float(d.sweepRecover))
		"retract":
			e.state_t += adv
			if float(e.state_t) >= float(d.retract):
				e.state = "approach"
				e.state_t = 0.0
		"recover":
			_recover_tick(e, adv)

# ---------- F. 군단 기수 ----------
## 파괴 가능한 깃발 설치(예고 0.8) → 범위 안 아군 집결·방어 지원 → 일부 호위에게 돌격 명령 → 재배치.
## **적을 새로 소환하지 않는다**(무한 경험치·금화 공급 금지). 명령은 유한 예산(orderBudget), 깃발도 유한(plantBudget).
## 지휘받은 적도 위험 공격 동시 제한(may_attack)을 그대로 따른다 — 명령은 이동·집결만 바꾼다.
static func update_elite_standard(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var B: Dictionary = d.banner
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("plant_left"):
		e.plant_left = int(d.plantBudget)
		e.order_left = int(B.orderBudget)
		e.order_t = 2.0
		e.banner_ref = null
	var bn = e.get("banner_ref")
	var banner_alive: bool = bn != null and not bool(bn.dead)
	if banner_alive:
		_banner_command(st, e, bn, B, dt)
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.slashRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "slash_aim", "", "#ffb0b0")
				return
			if not banner_alive and int(e.plant_left) > 0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "plant_aim", "깃발 설치", "#e0c060")
		"plant_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.plantAim):
				var ang: float = atan2(e.y - p.y, e.x - p.x)
				var pos := st.nearest_valid_pos(e.x + cos(ang) * float(d.bannerOffset), e.y + sin(ang) * float(d.bannerOffset), 12.0, 120.0)
				if pos.is_empty():
					pos = [e.x, e.y]
				var b := st.spawn_enemy("elite_banner", float(pos[0]), float(pos[1]))
				b.banner_ttl = float(B.ttl)
				b.banner_r = float(B.radius)
				e.banner_ref = b
				e.plant_left = int(e.plant_left) - 1
				st.note_attack(e, "execute")
				st.text(float(pos[0]), float(pos[1]) - 30.0, "깃발", "#e0c060")
				st.fx({ "kind": "burst", "x": float(pos[0]), "y": float(pos[1]), "r": float(B.radius), "ttl": 0.5, "color": "#e0c060" })
				st.ev("wave")
				to_recover(st, e, float(d.recover))
		"slash_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.slashAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.slashRange) + e.r, PGeom.deg(float(d.slashDeg)) / 2.0, float(d.slashDamage), "elite_standard")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.slashRange) + e.r, "half": PGeom.deg(float(d.slashDeg)) / 2.0, "ttl": 0.14, "enemy": true })
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.recover))
		"recover":
			_recover_tick(e, adv)

## 주기적 호위 돌격 명령(유한 예산). **적을 새로 소환하지 않는다** — 이미 싸우고 있는 적의 이동만 바꾼다.
## 명령받은 적도 위험 공격 동시 제한(may_attack)을 그대로 따른다
static func _banner_command(st: CombatState, e: Dictionary, bn: Dictionary, B: Dictionary, dt: float) -> void:
	e.order_t = float(e.order_t) - dt
	if float(e.order_t) > 0.0 or int(e.order_left) <= 0:
		return
	e.order_t = float(B.orderInterval)
	var cands := []
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.get("boss", false)) or bool(o.get("structure", false)):
			continue
		if PGeom.dist(bn.x, bn.y, o.x, o.y) <= float(B.radius) and not bool(o.get("ordered", false)):
			cands.append(o)
	cands.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var n: int = mini(int(B.orderCount), mini(cands.size(), int(e.order_left)))
	for i in n:
		var o: Dictionary = cands[i]
		o.ordered = true
		o.rally_t = float(B.orderDur) # 명령 지속 동안은 집결보다 빠르다(rally_t가 끝나면 leash_boost가 1.0으로 돌아간다)
		o.leash_boost = float(B.orderSpeed)
		st.text(o.x, o.y - float(o.r) - 26.0, "돌격 명령", "#e0c060")
	if n > 0:
		e.order_left = int(e.order_left) - n
		st.ev("group")

## 깃발(구조물): 살아 있는 동안 범위 안 아군의 집결 상태를 매 단계 새로 칠한다(rally_t 0.25초 갱신).
## 부수거나 수명이 끝나면 갱신이 멈추고 0.25초 안에 저절로 꺼진다 — 죽은 깃발의 효과가 남지 않는다
static func update_banner(st: CombatState, e: Dictionary, dt: float) -> void:
	var B: Dictionary = PCatalog.enemy("elite_standard").banner
	# 깃발 범위와 지휘받는 적을 눈에 보이게 한다(0.6초마다 고리 하나. 전용 그림은 render.gd 담당)
	e.ring_t = float(e.get("ring_t", 0.0)) - dt
	var show: bool = float(e.ring_t) <= 0.0
	if show:
		e.ring_t = 0.6
		st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": float(B.radius), "ttl": 0.55, "color": "#e0c060" })
	for o in st.enemies:
		if bool(o.dead) or bool(o.get("boss", false)) or bool(o.get("structure", false)) or bool(o.get("ordered", false)):
			continue
		if PGeom.dist(e.x, e.y, o.x, o.y) <= float(B.radius):
			o.rally_t = 0.25
			o.leash_boost = float(B.rallySpeed)
			if show:
				st.fx({ "kind": "burst", "x": o.x, "y": o.y, "r": float(o.r) + 8.0, "ttl": 0.4, "color": "#e0c060" })
	e.banner_ttl = float(e.get("banner_ttl", 20.0)) - dt
	if float(e.banner_ttl) <= 0.0:
		e.hp = 0.0
		st.kill_enemy(e, {})

## 깃발 방어 지원: 살아 있는 깃발 범위 안의 일반 적은 직접 피해가 조금 줄어든다(중복 아님 — shield_mult가 min으로 한 번만)
static func _rally_guard(st: CombatState, e: Dictionary) -> bool:
	if bool(e.get("boss", false)) or bool(e.get("structure", false)):
		return false
	for o in st.enemies:
		if bool(o.dead) or String(o.type) != "elite_banner":
			continue
		if PGeom.dist(o.x, o.y, e.x, e.y) <= float(o.get("banner_r", 0.0)):
			return true
	return false

# ---------- G. 균열 채굴자 ----------
## 지하 이동 흔적 → 출현 위치 예고 0.7초 → 솟구치기 → 작은 돌무더기 생성 → 지상 빈틈 1.6초.
## 출현 위치는 warn 시작 때 확정하고 그 뒤 추적하지 않는다. 지하 구간은 최소 0.6 / 최대 1.6초로 제한해
## '지하에만 오래 숨어 시간 끌기'를 막는다. 돌무더기는 파괴 가능하고 수(4)·수명(8초) 상한이 있으며,
## 놓은 뒤에도 플레이어 주위 탈출 방향이 minExits개 이상 남는 자리에만 놓는다.
static func update_elite_miner(st: CombatState, e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	var dist := PGeom.dist(e.x, e.y, p.x, p.y)
	if not e.has("burrow_cd"):
		e.burrow_cd = 1.2
	if String(e.state) != "under" and String(e.state) != "dive" and String(e.state) != "warn":
		e.burrow_cd = float(e.burrow_cd) - dt
	match String(e.state):
		"approach":
			st.approach(e, p.x, p.y, float(d.speed) * sm, dt)
			if dist <= float(d.engageDist) and float(e.burrow_cd) <= 0.0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "dive", "잠행", "#c8a06a")
			elif dist <= float(d.biteRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "bite_aim", "", "#ffb0b0")
		"dive":
			e.state_t += adv
			if float(e.state_t) >= float(d.dive):
				e.state = "under"
				e.state_t = 0.0
				e.hidden = true
		"under": # 지하 이동 흔적(추적 허용). 최소·최대 시간 안에서만 머문다
			e.state_t += adv
			var n := PGeom.norm(p.x - e.x, p.y - e.y)
			st.move_swept(e, n[0] * float(d.underSpeed) * sm * dt, n[1] * float(d.underSpeed) * sm * dt, true)
			e.trail_t = float(e.get("trail_t", 0.0)) - dt # 지하 이동 흔적: 0.12초마다 하나(매 단계 만들면 화면이 덮인다)
			if float(e.trail_t) <= 0.0:
				e.trail_t = 0.12
				st.fx({ "kind": "burst", "x": e.x, "y": e.y, "r": 12.0, "ttl": 0.35, "color": "#a08050" })
			if float(e.state_t) >= float(d.underMax) or (float(e.state_t) >= float(d.underMin) and dist < 40.0):
				var pos := st.nearest_valid_pos(e.x, e.y, float(e.r), 200.0)
				if pos.is_empty():
					pos = [e.x, e.y]
				e.emerge_at = pos # 출현 위치 확정 — 그 뒤 추적하지 않는다
				e.state = "warn"
				e.state_t = 0.0
				st.ev("lock")
				st.ev("hazard_warn")
		"warn":
			e.state_t += adv
			if float(e.state_t) >= float(d.warn):
				var at: Array = e.emerge_at
				e.x = float(at[0])
				e.y = float(at[1])
				e.hidden = false
				e.state = "erupt"
				e.state_t = 0.0
				circle_hit(st, e, e.x, e.y, float(d.eruptR), float(d.eruptDamage), "elite_erupt")
				_place_rubble(st, e, d)
				e.burrow_cd = float(d.cooldown)
		"erupt":
			e.state_t += adv
			if float(e.state_t) >= 0.15:
				e.state = "stagger"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "빈틈!", "#ffd166")
		"stagger":
			e.state_t += adv
			if float(e.state_t) >= float(d.exposed):
				e.state = "approach"
				e.state_t = 0.0
		"bite_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= float(d.biteAim):
				e.dir = e.aim_angle
				arc_hit(st, e, float(e.dir), float(d.biteRange) + e.r, PGeom.deg(float(d.biteDeg)) / 2.0, float(d.biteDamage), "elite_pick")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": float(d.biteRange) + e.r, "half": PGeom.deg(float(d.biteDeg)) / 2.0, "ttl": 0.14, "enemy": true })
				e.bite_t = 0.0
				st.note_attack(e, "execute")
				to_recover(st, e, float(d.biteRecover))
		"recover":
			_recover_tick(e, adv)

## 돌무더기 배치: 전역 상한(rockMax)과 탈출 방향 검사를 통과한 자리에만. 시작점·목표·출구를 막지 않는다
static func _place_rubble(st: CombatState, e: Dictionary, d: Dictionary) -> void:
	var p := st.target_of(e)
	var live := rubble_count(st)
	var placed := 0
	for i in int(d.rockCount):
		if live + placed >= int(d.rockMax):
			break
		var a: float = atan2(p.y - e.y, p.x - e.x) + PGeom.deg(70.0) * (1.0 if i % 2 == 0 else -1.0)
		var cx: float = e.x + cos(a) * (float(d.eruptR) * 0.9)
		var cy: float = e.y + sin(a) * (float(d.eruptR) * 0.9)
		var pos := st.nearest_valid_pos(clampf(cx, 30.0, st.arena_w - 30.0), clampf(cy, 30.0, st.arena_h - 30.0), float(d.rockR) + 4.0, 120.0)
		if pos.is_empty():
			continue
		var dangers := [{ "x": float(pos[0]), "y": float(pos[1]), "r": float(d.rockR) }]
		for o in st.enemies:
			if not o.dead and String(o.type) == "elite_rubble":
				dangers.append({ "x": o.x, "y": o.y, "r": float(o.r) })
		if _exits_open(st, dangers, float(d.probe)) < int(d.minExits): # 유일한 탈출로를 막지 않는다
			continue
		var rk := st.spawn_enemy("elite_rubble", float(pos[0]), float(pos[1]))
		rk.rubble_ttl = float(d.rockTtl)
		placed += 1
	if placed > 0:
		st.ev("boss_land")

static func rubble_count(st: CombatState) -> int:
	var n := 0
	for o in st.enemies:
		if not o.dead and String(o.type) == "elite_rubble":
			n += 1
	return n

## 돌무더기(구조물): 수명이 끝나면 무너진다. 그 전에 부술 수도 있다
static func update_rubble(st: CombatState, e: Dictionary, dt: float) -> void:
	e.rubble_ttl = float(e.get("rubble_ttl", 8.0)) - dt
	if float(e.rubble_ttl) <= 0.0:
		e.hp = 0.0
		st.kill_enemy(e, {})

# ========== 일반 정예 확장 10종 (2026-09-09, 시험값 — 표는 COMMON_ELITES · 수치는 data/pacing.json · 설명은 docs/MONSTERS.md) ==========
## 굴리는 방법(PEnemies.update_common_elite):
##   ① 확장 행동 중이면 update_extra가 굴린다
##   ② 아니면 **바탕 몬스터의 기본 행동을 그대로** 굴린다(규칙을 복사하지 않는다 — 같은 함수를 쓴다)
##   ③ 바탕이 정해진 전이(from → to)에 닿으면 확장 행동 하나를 잇는다.
##      to == "recover"인 것은 to_recover가 가로채므로 바탕 함수를 한 줄도 고치지 않는다.
## 확장 행동도 예고 → 실행 한 벌이며, 끝나면 바탕이 주려던 빈틈으로 그대로 들어간다.

## 바탕 행동이 빈틈으로 들어가는 순간의 가로채기. 확장을 시작했으면 true(빈틈을 건너뛴다)
static func _extra_on_recover(st: CombatState, e: Dictionary, dur: float) -> bool:
	var type := String(e.type)
	if not COMMON_ELITES.has(type):
		return false
	var C: Dictionary = COMMON_ELITES[type]
	if String(C.to) != "recover" or String(C.from) != String(e.state):
		return false
	e.extra_recover = dur # 확장이 끝나면 바탕이 주려던 길이 그대로 쓴다
	begin_extra(st, e)
	return true

## 빈틈이 아닌 상태로 넘어가는 전이(지금은 잠복충의 warn → emerge 하나)를 위한 뒤처리
static func after_base(st: CombatState, e: Dictionary, prev: String) -> void:
	var type := String(e.type)
	if not COMMON_ELITES.has(type):
		return
	var C: Dictionary = COMMON_ELITES[type]
	var to := String(C.to)
	if to == "" or to == "recover":
		return
	if prev == String(C.from) and String(e.state) == to:
		begin_extra(st, e)

static func begin_extra(st: CombatState, e: Dictionary) -> void:
	var type := String(e.type)
	var ex: Array = extra_states(type)
	e.state = String(ex[0])
	e.state_t = 0.0
	if not e.has("extra_recover"):
		e.extra_recover = 0.0
	st.note_attack(e, "prepare") # 예고 하나가 더 붙는다 = 같은 등급의 일반 개체와 행동 수가 다르다
	st.text(e.x, e.y - float(e.r) - 30.0, String(EXTRA_LABEL.get(type, "추가 공격")), "#ff9f43")
	st.ev("lock")

## 확장 행동을 끝낸다. 표의 to가 "recover"면 바탕이 주려던 빈틈으로, 아니면 그 상태로 되돌린다
static func extra_end(st: CombatState, e: Dictionary) -> void:
	var C: Dictionary = COMMON_ELITES[String(e.type)]
	var to := String(C.to)
	e.state_t = 0.0
	if to == "recover":
		e.state = "recover"
		e.recover_dur = float(e.get("extra_recover", 0.0))
		st.text(e.x, e.y - float(e.r) - 26.0, "빈틈!", "#ffd166")
	else:
		e.state = to

static func update_extra(st: CombatState, e: Dictionary, dt: float) -> void:
	var p := st.target_of(e)
	var tf := st.time_factor(e)
	var sm := st.enemy_speed_mult(e)
	var adv := dt * tf
	match String(e.type):
		"boar_elite": # 돌파 끝 자리에서 예고된 짧은 충격파(바위에 부딪혀 비틀거린 돌파에는 없다)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "shockAim", 0.0):
				circle_hit(st, e, e.x, e.y, dv(e, "shockR", 0.0), dv(e, "shockDamage", 0.0), "boar_shock")
				extra_end(st, e)
		"archer_elite": # 이미 확정된 같은 선으로 두 번째 화살(새 조준 없음 = 예고선 위의 두 번째 발)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "shot2Lock", 0.0):
				_arrow(st, e, float(e.dir), dv(e, "arrowSpeed", 0.0), dv(e, "arrowR", 0.0), dv(e, "arrowDamage", 0.0))
				st.note_attack(e, "execute")
				extra_end(st, e)
		"shieldbearer_elite": # 방패치기 뒤 한 걸음 더 밀고 들어오는 짧은 전진 공격
			e.state_t += adv
			face_toward(e, p.x, p.y, dv(e, "turnRate", 0.0), adv)
			if float(e.state_t) >= dv(e, "pushAim", 0.0):
				e.dir = float(e.get("face", 0.0))
				st.move_swept(e, cos(float(e.dir)) * dv(e, "pushLunge", 0.0), sin(float(e.dir)) * dv(e, "pushLunge", 0.0))
				var half: float = PGeom.deg(dv(e, "pushDeg", 0.0)) / 2.0
				arc_hit(st, e, float(e.dir), dv(e, "pushRange", 0.0), half, dv(e, "pushDamage", 0.0), "shield_push")
				st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": e.dir, "r": dv(e, "pushRange", 0.0), "half": half, "ttl": 0.16, "enemy": true })
				st.note_attack(e, "execute")
				st.ev("boss_sweep")
				extra_end(st, e)
		"spider_elite": # 첫 거미줄과 **다른 방향**에 두 번째 거미줄(전장 총 상한은 바탕 그대로)
			if not e.has("web2_at"):
				e.web2_at = _web2_spot(st, e)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "web2Aim", 0.0):
				var at: Array = e.web2_at
				while web_count(st) >= int(dv(e, "maxWebs", 4.0)):
					var removed := false
					for i in st.zones.size():
						if String(st.zones[i].type) == "web":
							st.zones.remove_at(i)
							removed = true
							break
					if not removed:
						break
				var z := st.add_zone("web", float(at[0]), float(at[1]), dv(e, "webR", 0.0), dv(e, "webTtl", 0.0), 0.0)
				z.slow = dv(e, "webSlow", 0.0)
				st.metrics.webs += 1
				st.note_attack(e, "execute")
				st.ev("spore")
				e.erase("web2_at")
				extra_end(st, e)
		"spore_elite": # 본체가 터진 자리에 **작은** 포자 구역이 잠시 남는다(개체당 residueMax개)
			if not e.has("residue_at"):
				e.residue_at = [e.x, e.y]
			e.state_t += adv
			if float(e.state_t) >= dv(e, "residueAim", 0.0):
				var rat: Array = e.residue_at
				var rz := st.add_zone("spore", float(rat[0]), float(rat[1]), dv(e, "cloudR", 0.0) * dv(e, "residueFrac", 0.0),
					dv(e, "residueTtl", 0.0), dv(e, "residueDamage", 0.0) * float(e.get("tier_dmg", 1.0)))
				rz.owner = e
				_trim_clouds(st, e, int(dv(e, "residueMax", 1.0)))
				st.note_attack(e, "execute")
				st.ev("spore")
				e.erase("residue_at")
				extra_end(st, e)
		"rogue_elite": # 두 번째 베기 뒤 옆으로 자리를 옮겨(공격 없음) 세 번째 베기를 예고한다
			if String(e.state) == "flank_move":
				e.state_t += adv
				strafe(st, e, dv(e, "flankSpeed", 0.0) * sm, dt)
				if float(e.state_t) >= dv(e, "flankTime", 0.0):
					e.state = "slash3_aim"
					e.state_t = 0.0
					e.aim_angle = atan2(p.y - e.y, p.x - e.x)
					st.note_attack(e, "prepare")
			else:
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				e.state_t += adv
				if float(e.state_t) >= dv(e, "aim3", 0.0):
					e.dir = e.aim_angle
					slash(st, e, e.def)
					e.side = -int(e.get("side", 1))
					extra_end(st, e)
		"burrower_elite": # 첫 출현 뒤 짧게 재잠복하고 두 번째 위치를 예고해 다시 솟구친다(한 차례만)
			match String(e.state):
				"redive":
					e.state_t += adv
					if float(e.state_t) >= dv(e, "redive", 0.0):
						e.state = "reunder"
						e.state_t = 0.0
						e.hidden = true
				"reunder":
					e.state_t += adv
					var n := PGeom.norm(p.x - e.x, p.y - e.y)
					st.move_swept(e, n[0] * dv(e, "underSpeed", 0.0) * sm * dt, n[1] * dv(e, "underSpeed", 0.0) * sm * dt, true)
					if float(e.state_t) >= dv(e, "reunder", 0.0):
						var pos := st.nearest_valid_pos(e.x, e.y, float(e.r), 200.0)
						e.emerge_at = pos if not pos.is_empty() else [e.x, e.y]
						e.state = "rewarn"
						e.state_t = 0.0
						st.ev("lock")
						st.ev("hazard_warn")
				_:
					e.state_t += adv
					if float(e.state_t) >= dv(e, "rewarn", 0.0):
						var eat: Array = e.emerge_at
						e.x = float(eat[0])
						e.y = float(eat[1])
						e.hidden = false
						circle_hit(st, e, e.x, e.y, dv(e, "reEmergeR", 0.0), dv(e, "reDamage", 0.0), "burrow_reemerge")
						e.burrow_cd = dv(e, "cooldown", 0.0)
						extra_end(st, e) # → 바탕의 emerge(짧은 마무리) → 지상 빈틈
		"toad_elite": # 착지 뒤 **한 차례** 예고된 지면 충격(연속 점프로 이어지지 않는다)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "slamAim", 0.0):
				circle_hit(st, e, e.x, e.y, dv(e, "slamR", 0.0), dv(e, "slamDamage", 0.0), "toad_slam")
				extra_end(st, e)
		"frostcaller_elite": # 첫 묶음과 다른 방향에 두 번째 묶음(동시에 전 방향을 막지 않는다)
			if not e.has("cast2_pts"):
				e.cast2_pts = _frost2_points(st, e)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "cast2Aim", 0.0):
				var pts: Array = e.cast2_pts
				var delays := dva(e, "cast2Delays")
				for i in pts.size():
					var pt: Array = pts[i]
					var wait: float = float(delays[i]) if i < delays.size() else 1.2
					var fz := st.add_zone("frostzone", float(pt[0]), float(pt[1]), dv(e, "zoneR", 0.0), wait, 0.0)
					fz.order = i + 1
					fz.dmg = dv(e, "damage", 0.0) * float(e.get("tier_dmg", 1.0))
					fz.owner = e
				st.note_attack(e, "execute")
				st.ev("lock")
				e.erase("cast2_pts")
				extra_end(st, e)

## 두 번째 거미줄 자리: 플레이어를 중심으로 첫 자리에서 web2Deg만큼 돌린 방향
static func _web2_spot(st: CombatState, e: Dictionary) -> Array:
	var p := st.target_of(e)
	var first: Array = e.get("web_at", [p.x, p.y])
	var a0: float = atan2(float(first[1]) - p.y, float(first[0]) - p.x)
	if PGeom.dist(float(first[0]), float(first[1]), p.x, p.y) < 1e-3:
		a0 = float(p.face)
	var a1: float = a0 + PGeom.deg(dv(e, "web2Deg", 0.0))
	var dist2: float = dv(e, "web2Dist", 0.0)
	var pos := st.nearest_valid_pos(clampf(p.x + cos(a1) * dist2, 20.0, st.arena_w - 20.0), clampf(p.y + sin(a1) * dist2, 20.0, st.arena_h - 20.0), 0.0, 120.0)
	return pos if not pos.is_empty() else [p.x, p.y]

## 두 번째 서리 묶음의 자리. 첫 묶음 방향(cast_ang)에서 cast2Deg 돌린 쪽에 cast2Count개.
## **놓고 나서도** 살아 있는 서리 영역까지 합쳐 탈출 방향이 minExits개 이상 남는 자리만 쓴다
static func _frost2_points(st: CombatState, e: Dictionary) -> Array:
	var p := st.target_of(e)
	var ang: float = float(e.get("cast_ang", 0.0)) + PGeom.deg(dv(e, "cast2Deg", 0.0))
	var n: int = int(dv(e, "cast2Count", 0.0))
	var spacing: float = dv(e, "spacing", 0.0)
	var zone_r: float = dv(e, "zoneR", 0.0)
	var probe: float = dv(e, "probe", 0.0)
	var need: int = int(dv(e, "minExits", 0.0))
	var live: Array = []
	for z in st.zones:
		if String(z.type) == "frostzone":
			live.append({ "x": float(z.x), "y": float(z.y), "r": float(z.r) })
	var out: Array = []
	for i in n:
		var x: float = p.x + cos(ang) * spacing * float(i)
		var y: float = p.y + sin(ang) * spacing * float(i)
		var pos := st.nearest_valid_pos(clampf(x, 20.0, st.arena_w - 20.0), clampf(y, 20.0, st.arena_h - 20.0), 0.0, 120.0)
		if pos.is_empty():
			continue
		var dangers: Array = live.duplicate()
		for o in out:
			dangers.append({ "x": float(o[0]), "y": float(o[1]), "r": zone_r })
		dangers.append({ "x": float(pos[0]), "y": float(pos[1]), "r": zone_r })
		if _exits_open(st, dangers, probe) < need: # 이 자리를 놓으면 빠져나갈 곳이 없다 — 건너뛴다
			continue
		out.append([float(pos[0]), float(pos[1])])
	return out

# ---------- 봇용 위협 도형(화면에 보이는 예고와 같은 정보만) ----------
static func threats(st: CombatState, e: Dictionary, out: Array) -> void:
	threats_as(st, e, out, String(e.type))

## 정예 확장은 **바탕 종류의 예고 도형**을 그대로 쓴다(같은 공격이므로 같은 도형이어야 한다)
static func threats_as(st: CombatState, e: Dictionary, out: Array, type: String) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var state := String(e.state)
	if type == "boar":
		var pv: Dictionary = e.get("preview", {})
		if state == "charge_aim" and not pv.is_empty():
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": float(pv["len"]) + 30.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": float(e.state_t) / float(d.aim), "locked": false })
		elif state == "charge_lock" or state == "charge":
			var cl: float = float(e.get("charge_len", 0.0))
			if cl <= 0.0:
				cl = float(d.chargeDist)
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": cl + 30.0, "w": (e.r + p.r) * 2.0 + 30.0, "prog": 1.0, "locked": true })
	elif type == "shieldbearer" and state == "bash_aim":
		var prog: float = float(e.state_t) / float(d.aim)
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.face, "r": float(d.bashRange) + float(d.lunge) + 20.0, "half": PGeom.deg(float(d.bashDeg)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.6 })
	elif type == "shaman" and state == "hex_aim": # 예고: 아직 따라온다(확정 전)
		var prog: float = float(e.state_t) / float(d.hexAim)
		out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": 2000.0, "w": 40.0, "prog": prog, "locked": false })
	elif type == "shaman" and state == "hex_lock": # 확정: 세 갈래가 각각 고정된 선으로 보인다(가운데가 플레이어 방향)
		var n: int = int(dv(e, "hexCount", 1.0))
		var step: float = PGeom.deg(dv(e, "hexSpreadDeg", 0.0))
		for i in n:
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir) + (float(i) - float(n - 1) / 2.0) * step, "len": 2000.0, "w": 40.0, "prog": 1.0, "locked": true, "center": i == n / 2 })
	elif type == "shaman" and state == "rune_aim" and e.has("rune_at"): # 바닥 문양: 위치가 처음부터 확정이라 첫 프레임부터 locked
		var at: Array = e.rune_at
		out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": dv(e, "runeR", 0.0), "prog": float(e.state_t) / maxf(0.001, dv(e, "runeAim", 0.0)), "locked": true })
	elif type == "bomber" and state == "fuse":
		out.append({ "kind": "circle", "e": e, "x": e.x, "y": e.y, "r": float(d.blastR), "prog": float(e.state_t) / float(d.fuse), "locked": true })
	elif type == "burrower" and state == "warn" and e.has("emerge_at"):
		var at: Array = e.emerge_at
		out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": float(d.emergeR), "prog": float(e.state_t) / float(d.warn), "locked": true })
	elif (type == "burrower" or type == "spider") and state == "bite_aim":
		var prog: float = float(e.state_t) / float(d.biteAim)
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.6 })
	elif type == "rogue" and (state == "slash1_aim" or state == "slash2_aim"):
		var prog: float = float(e.state_t) / (float(d.aim1) if state == "slash1_aim" else float(d.aim2))
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.slashRange) + e.r + 10.0, "half": PGeom.deg(float(d.slashDeg)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.5 })
	elif type == "bat" and state == "bite_aim":
		var prog: float = float(e.state_t) / maxf(0.001, dv(e, "biteAim", 0.0))
		out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "biteRange", 0.0) + e.r + 10.0, "half": PGeom.deg(dv(e, "biteDeg", 0.0)) / 2.0 + 0.2, "prog": prog, "locked": prog > 0.6 })
	elif type == "lizard" and (state == "flame_aim" or state == "flame_lock" or state == "flame"):
		# 예고 중에는 아직 따라오고(확정 전), 확정 뒤에는 회전 상한만큼만 움직인다. 도형 = 입에서 이어지는 선 그대로
		var ang: float = float(e.aim_angle) if state == "flame_aim" else float(e.dir)
		var seg := flame_seg(st, e, ang)
		out.append({ "kind": "beam", "e": e, "x": float(seg[0]), "y": float(seg[1]), "ang": ang, "len": float(seg[2]), "w": dv(e, "flameW", 0.0),
			"prog": (float(e.state_t) / maxf(0.001, dv(e, "flameAim", 0.0))) if state == "flame_aim" else 1.0, "locked": state != "flame_aim" })
	elif type == "toad" and (state == "crouch" or state == "leap_warn" or state == "leap") and e.has("leap_at"):
		var at: Array = e.leap_at
		out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": dv(e, "landR", 0.0),
			"prog": (float(e.state_t) / maxf(0.001, dv(e, "crouch", 0.0))) if state == "crouch" else 1.0, "locked": state != "crouch" })
	elif is_elite(type):
		elite_threats(st, e, out)

## 확장 예고의 진행도(0~1)
static func _prog(e: Dictionary, key: String) -> float:
	return clampf(float(e.state_t) / maxf(0.001, dv(e, key, 0.0)), 0.0, 1.0)

## 일반 정예 확장이 더한 행동의 예고 도형(확장 상태에서만 부른다).
## 자리를 옮기는 구간(flank_move·redive·reunder)에는 공격 판정이 없으므로 도형도 없다
static func extra_threats(_st: CombatState, e: Dictionary, out: Array) -> void:
	var state := String(e.state)
	match String(e.type):
		"boar_elite":
			out.append({ "kind": "circle", "e": e, "x": e.x, "y": e.y, "r": dv(e, "shockR", 0.0), "prog": _prog(e, "shockAim"), "locked": true })
		"archer_elite":
			out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": 2000.0, "w": 40.0, "prog": 1.0, "locked": true })
		"shieldbearer_elite":
			out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.get("face", 0.0), "r": dv(e, "pushRange", 0.0) + dv(e, "pushLunge", 0.0) + 20.0,
				"half": PGeom.deg(dv(e, "pushDeg", 0.0)) / 2.0 + 0.2, "prog": _prog(e, "pushAim"), "locked": true })
		"spider_elite":
			if e.has("web2_at"):
				var wat: Array = e.web2_at
				out.append({ "kind": "circle", "e": e, "x": float(wat[0]), "y": float(wat[1]), "r": dv(e, "webR", 0.0), "prog": _prog(e, "web2Aim"), "locked": true })
		"spore_elite":
			if e.has("residue_at"):
				var sat: Array = e.residue_at
				out.append({ "kind": "circle", "e": e, "x": float(sat[0]), "y": float(sat[1]), "r": dv(e, "cloudR", 0.0) * dv(e, "residueFrac", 0.0), "prog": _prog(e, "residueAim"), "locked": true })
		"rogue_elite":
			if state == "slash3_aim":
				var pr3 := _prog(e, "aim3")
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "slashRange", 0.0) + e.r + 10.0,
					"half": PGeom.deg(dv(e, "slashDeg", 0.0)) / 2.0 + 0.2, "prog": pr3, "locked": pr3 > 0.5 })
		"burrower_elite":
			if state == "rewarn" and e.has("emerge_at"):
				var bat: Array = e.emerge_at
				out.append({ "kind": "circle", "e": e, "x": float(bat[0]), "y": float(bat[1]), "r": dv(e, "reEmergeR", 0.0), "prog": _prog(e, "rewarn"), "locked": true })
		"toad_elite":
			out.append({ "kind": "circle", "e": e, "x": e.x, "y": e.y, "r": dv(e, "slamR", 0.0), "prog": _prog(e, "slamAim"), "locked": true })
		"frostcaller_elite":
			for pt in e.get("cast2_pts", []):
				out.append({ "kind": "circle", "e": e, "x": float(pt[0]), "y": float(pt[1]), "r": dv(e, "zoneR", 0.0), "prog": _prog(e, "cast2Aim"), "locked": true })

## 특수 정예 7종의 예고 도형(화면 표시와 같은 기하). 확정(locked) 뒤에는 추적하지 않는다
static func elite_threats(st: CombatState, e: Dictionary, out: Array) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var state := String(e.state)
	var w: float = (float(e.r) + float(p.r)) * 2.0 + 30.0
	match String(e.type):
		"elite_archer":
			if state == "aim":
				var need: float = float(d.aim) if int(e.get("shot_left", 1)) == int(d.shots) else float(d.reaim)
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": 2000.0, "w": 40.0, "prog": float(e.state_t) / need, "locked": false })
			elif state == "shot_lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": 2000.0, "w": 40.0, "prog": 1.0, "locked": true })
			elif state == "fan_aim" or state == "fan_lock":
				var ang: float = float(e.aim_angle) if state == "fan_aim" else float(e.dir)
				var half: float = PGeom.deg(float(d.fanDeg)) * (float(int(d.fanCount) - 1) / 2.0) + 0.12
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": ang, "r": 900.0, "half": half, "prog": (float(e.state_t) / float(d.fanAim)) if state == "fan_aim" else 1.0, "locked": state == "fan_lock" })
		"elite_blademaster":
			if state == "dash1_aim" or state == "dash2_aim":
				var pv: Dictionary = e.get("preview", {})
				var L: float = float(pv["len"]) if not pv.is_empty() else float(d.dashDist)
				var need2: float = float(d.aim1) if state == "dash1_aim" else float(d.aim2)
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "len": L + 30.0, "w": w, "prog": float(e.state_t) / need2, "locked": false })
			elif state == "dash1_lock" or state == "dash2_lock" or state == "dash1" or state == "dash2":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": maxf(0.0, float(e.get("charge_len", 0.0)) - float(e.get("charge_dist", 0.0))) + 30.0, "w": w, "prog": 1.0, "locked": true })
			elif state == "slam_aim":
				out.append({ "kind": "circle", "e": e, "x": e.x + cos(float(e.get("face", 0.0))) * float(d.slamOffset), "y": e.y + sin(float(e.get("face", 0.0))) * float(d.slamOffset), "r": float(d.slamR), "prog": float(e.state_t) / float(d.slamAim), "locked": true })
		"elite_fang":
			if state == "bite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.biteAim), "locked": float(e.state_t) / float(d.biteAim) > 0.6 })
			elif (state == "leap_aim" or state == "leap_lock" or state == "leap") and e.has("leap_at"):
				var at: Array = e.leap_at
				out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": float(d.leapR), "prog": (float(e.state_t) / float(d.leapAim)) if state == "leap_aim" else 1.0, "locked": state != "leap_aim" })
		"elite_plaguecaller":
			if state == "burst_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.burstRange) + e.r + 10.0, "half": PGeom.deg(float(d.burstDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.burstAim), "locked": float(e.state_t) / float(d.burstAim) > 0.6 })
			elif state == "swell":
				for pod in e.get("pods", []):
					if bool(pod.done):
						continue
					var left: float = maxf(0.0, float(pod.land_at) - st.t)
					out.append({ "kind": "circle", "e": e, "x": float(pod.x), "y": float(pod.y), "r": float(pod.r), "prog": 1.0 - left / maxf(0.001, float(d.swell)), "locked": true, "order": int(pod.order) })
		"elite_chainbreaker":
			if state == "chain_aim" or state == "chain_lock":
				var cl: float = float(e.get("chain_len", float(d.chainLen)))
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.aim_angle) if state == "chain_aim" else float(e.dir), "len": cl, "w": float(d.chainW), "prog": (float(e.state_t) / float(d.chainAim)) if state == "chain_aim" else 1.0, "locked": state == "chain_lock" })
			elif state == "chain_fly":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": e.dir, "len": float(e.get("chain_d", 0.0)), "w": float(d.chainW), "prog": 1.0, "locked": true })
			elif (state == "slam_aim" or state == "slam_lock") and e.has("slam_at"):
				var sat: Array = e.slam_at
				out.append({ "kind": "circle", "e": e, "x": float(sat[0]), "y": float(sat[1]), "r": float(d.slamR), "prog": (float(e.state_t) / float(d.slamAim)) if state == "slam_aim" else 1.0, "locked": true })
			elif state == "sweep_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.sweepRange) + e.r + 10.0, "half": PGeom.deg(float(d.sweepDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.sweepAim), "locked": float(e.state_t) / float(d.sweepAim) > 0.6 })
		"elite_standard":
			if state == "slash_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.slashRange) + e.r + 10.0, "half": PGeom.deg(float(d.slashDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.slashAim), "locked": float(e.state_t) / float(d.slashAim) > 0.6 })
		"elite_miner":
			if state == "warn" and e.has("emerge_at"):
				var mat: Array = e.emerge_at
				out.append({ "kind": "circle", "e": e, "x": float(mat[0]), "y": float(mat[1]), "r": float(d.eruptR), "prog": float(e.state_t) / float(d.warn), "locked": true })
			elif state == "bite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.biteAim), "locked": float(e.state_t) / float(d.biteAim) > 0.6 })

static func zone_threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "frostzone":
			out.append({ "kind": "circle", "x": z.x, "y": z.y, "r": z.r, "prog": 1.0 - float(z.ttl) / float(z.max_ttl), "locked": float(z.ttl) < 0.45 })
		elif z.type == "web":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r, "web": true })
