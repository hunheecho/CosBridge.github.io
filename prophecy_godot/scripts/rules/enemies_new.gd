class_name PEnemiesNew
extends RefCounted
## 신규 기본 몬스터 8종(HTML enemies.js 이식): 멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적.
## + 특수 정예 7종(2026-09-08 추가, 시험값): 정예 궁수·정예 검사·피의 송곳니·역병 조율사·사슬 집행자·군단 기수·균열 채굴자
##   와 그들이 만드는 파괴 가능한 구조물 2종(군단 깃발·돌무더기). 정의는 data/enemies.json, 배치표는 data/elites.json, 설명은 docs/ELITES.md.
## PEnemies.update가 has(type)인 개체에 update를 호출한다. 공통 규칙: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음.
## 상호작용: 감속장은 준비·실행·빈틈 진행(tf)을 늦추고, 냉기는 이동만 늦춘다. 넉백은 돌진·잠복·도약 중에는 무시(combat_state.knock_enemy), 방패병은 50%(def.knockMult).
## 면역(최소 범위): 잠복충·균열 채굴자의 지하 구간(hidden)은 직접 공격·투사체 대상이 되지 않는다(바닥 효과는 적용). 그 외 면역 없음.
## 피해 감소(방패·깃발)는 shield_mult 한 곳에서만 계산하고, 여러 효과가 겹쳐도 곱하지 않는다(가장 강한 하나만).
## 2026-09-10 추가 필드: obs_t·obs_x·obs_y·obs_vx·obs_vy(관측 이동) · chase_t·snipe_t·step_t·wave_t·runbite_t·cut_t·seek_t·wall_t·anchor_t·drag_t·rush_t·pincer_t·surface_t·rift_t(신규 패턴 재사용)
##   · chase_left·runbite_left·last_pattern·pattern_uses · seek·wall·drag_at·drag_now·drag_r·drag_a0·drag_side · pod_done · pincer_ang·pincer_ally·pincer_solo
##   플레이어 쪽: curse_until(§10 저주가 풀리는 시각)
## 개체별 추가 필드(snake_case, 지연 초기화): face, preview, charge_len, charge_end, charge_blocked, charge_dist, hit_done, heal_t, hex_t, rune_t, act_t, rune_at, cast_target, cast_pts, cast_t, cast_ang,
##   burrow_cd, emerge_at, web_t, web_at, side, base_dir, exploded, block_fx_t,
##   정예: shot_left, blocked_sec, leap_at, leap_from, pods, chain_len, chain_d, pull_from, slam_at, plant_left, order_left, order_t, banner_ref,
##   지휘받는 쪽: rally_t, ordered(leash_boost는 rally_t가 끝나면 PEnemies.update가 1.0으로 되돌린다). 구조물: banner_ttl, banner_r, ring_t, rubble_ttl, trail_t
##   신규 3종(2026-09-09): flame_t, flame_tick, leap_t. 일반 정예 확장: extra_recover, web2_at, residue_at, cast2_pts
##   특수 정예 회피(2026-09-09): dodge_phase, dodge_t, dodge_cd, dodge_wait, dodge_dx, dodge_dy, dodge_dist, dodge_from,
##     dodge_kind, dodge_hit_t + 계측용 dodge_seen · dodge_uses · dodge_skip (docs/ELITE_DODGE.md)
##
## + 2026-09-10(전부 첫 시험값):
##   §10 일반 주술사의 **피해 증폭 저주** — 기존 저주 문양 개편(직접 피해 0 · 받는 피해 +50% · 4초). docs/CURSE.md
##       **곱하는 자리는 combat_state.gd라 여기서는 상태만 건다**(붙일 자리는 docs/CURSE.md §붙일 자리).
##   §11-B 특수 정예 7종 × **신규 공격 패턴 2개**(표 = NEW_PATTERNS). docs/ELITE_PATTERNS.md
##   §12 기존 몬스터 수정 — 역병 조율사 포자 재조준 · 사슬 발사 속도 · 도마뱀 준비시간 · 도마뱀 말미 등장. docs/MONSTER_FIX_2026-09-10.md
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
	# 2026-09-10 §11-B: 종류마다 **신규 공격 패턴 2개**를 더했다(NEW_PATTERNS 표). 그 연계 상태도 전부 여기 센다.
	"elite_archer": ["aim", "shot_lock", "fan_aim", "fan_lock",
		"chase_run", "chase_aim", "chase_lock", "snipe1_aim", "snipe1_lock", "snipe_gap", "snipe2_aim", "snipe2_lock"],
	"elite_blademaster": ["dash1_aim", "dash1_lock", "dash1", "dash2_aim", "dash2_lock", "dash2", "guard", "slam_aim", "slam",
		"step1_aim", "step1", "step2_aim", "step2", "step3_aim", "step3", "wave_aim", "wave_lock", "wave"],
	"elite_fang": ["bite_aim", "backoff", "leap_aim", "leap_lock", "leap", # backoff는 연계 중간 이동이라 '연계 중'으로 센다
		"runbite_run", "runbite_aim", "cut_aim", "cut_lock", "cut_leap", "cut_turn", "cut_claw_aim"],
	"elite_plaguecaller": ["throw_aim", "swell", "burst_aim",
		"seek_aim", "seek_fly", "seek_swell", "wall_aim", "wall_burst"],
	"elite_chainbreaker": ["chain_aim", "chain_lock", "chain_fly", "pull", "slam_aim", "slam_lock", "sweep_aim",
		"anchor_aim", "anchor_lock", "anchor_fly", "drag_aim", "drag_lock", "drag_toss", "drag_sweep"],
	"elite_standard": ["plant_aim", "slash_aim",
		"rush_aim", "rush_lock", "rush", "thrust_aim", "cross_aim", "pincer_aim", "pincer_move", "pincer_slash_aim", "solo_aim1", "solo_gap", "solo_aim2"],
	"elite_miner": ["dive", "under", "warn", "erupt", "bite_aim",
		"surface_run", "pick_aim", "rift_aim", "rift"],
}

## 특수 정예 7종의 type(구조물 2종 제외). data/enemies.json 정의 + data/elites.json 배치표
const ELITE_TYPES := ["elite_archer", "elite_blademaster", "elite_fang", "elite_plaguecaller", "elite_chainbreaker", "elite_standard", "elite_miner"]

# ---------- §11-B 특수 정예 신규 공격 패턴 14개(2026-09-10, 전부 시험값. docs/ELITE_PATTERNS.md) ----------
## 무엇을 노렸나: "멀리서 같은 방향으로 걸으며 자동 공격"하는 놀이를 흔드는 것이다. 개수가 목표가 아니다.
##  - **접근 압박**: 걸어서 벌린 거리를 정예가 스스로 좁힌다(추격 사격·전진 연속 베기·달리는 물어뜯기·지상 추격 강타·닻 도약).
##  - **도주 경로 차단**: 지금 걷고 있는 **앞쪽**을 막거나 앞질러 선다(엇박 저격·앞질러 습격·역병 가로막기·사슬 끌어쓸기·쐐기 균열).
## 지키는 선(사용자 지시):
##  - **확정 뒤에는 절대 따라가지 않는다.** 모든 패턴이 lock/실행 시점에 각·자리를 굳히고 그 뒤로는 갱신하지 않는다.
##  - **플레이어 입력을 미리 읽지 않는다.** 앞을 겨누는 패턴은 obs_vel()이 주는 **관측한 위치 변화**만 쓴다(아래).
##  - 회피 무적·피격 보호를 무시하지 않는다(전부 st.damage_player / circle_hit / arc_hit을 거친다).
##  - 연계가 끝나면 반드시 빈틈(recover)으로 들어간다 — **반격 기회**를 없애지 않는다.
##  - 무적·강제 생존·체력 구간 피해 상한을 새로 만들지 않았다.
## 기존 회피(dodge)는 그대로 두었고 **패턴 수에 세지 않는다**. 기존 공격의 속도·조준만 고친 것도 세지 않는다
## (그것은 §12 쪽이며 사슬 발사 속도·도마뱀 준비시간이 거기에 해당한다).
##
## 표의 뜻: type → [패턴 id, 시작 상태, 첫 상태의 표시 낱말, 재사용 시각 칸 이름]
const NEW_PATTERNS := {
	"elite_archer": [
		{ "id": "chase", "state": "chase_run", "label": "추격 사격", "cd": "chase_t", "color": "#ffd166" },
		{ "id": "snipe", "state": "snipe1_aim", "label": "엇박 저격 1발", "cd": "snipe_t", "color": "#ffd166" }],
	"elite_blademaster": [
		{ "id": "step", "state": "step1_aim", "label": "전진 연속 베기 1/3", "cd": "step_t", "color": "#ffb0b0" },
		{ "id": "wave", "state": "wave_aim", "label": "추격 검기", "cd": "wave_t", "color": "#ffb0b0" }],
	"elite_fang": [
		{ "id": "runbite", "state": "runbite_run", "label": "달려든다", "cd": "runbite_t", "color": "#ff6b93" },
		{ "id": "cut", "state": "cut_aim", "label": "앞질러 습격", "cd": "cut_t", "color": "#ff6b93" }],
	"elite_plaguecaller": [
		{ "id": "seek", "state": "seek_aim", "label": "추적 포자탄", "cd": "seek_t", "color": "#9cff9c" },
		{ "id": "wall", "state": "wall_aim", "label": "역병 가로막기", "cd": "wall_t", "color": "#9cff9c" }],
	"elite_chainbreaker": [
		{ "id": "anchor", "state": "anchor_aim", "label": "닻 도약", "cd": "anchor_t", "color": "#ffd166" },
		{ "id": "drag", "state": "drag_aim", "label": "사슬 끌어쓸기", "cd": "drag_t", "color": "#ffd166" }],
	"elite_standard": [
		{ "id": "rush", "state": "rush_aim", "label": "깃발 돌격", "cd": "rush_t", "color": "#e0c060" },
		{ "id": "pincer", "state": "pincer_aim", "label": "양면 협공", "cd": "pincer_t", "color": "#e0c060" }],
	"elite_miner": [
		{ "id": "surface", "state": "surface_run", "label": "지상 추격", "cd": "surface_t", "color": "#c8a06a" },
		{ "id": "rift", "state": "rift_aim", "label": "쐐기 균열", "cd": "rift_t", "color": "#c8a06a" }],
}

## 그 종류의 신규 패턴 id 목록(없으면 빈 배열). 검사·문서가 읽는 정본이다
static func new_pattern_ids(type: String) -> Array:
	var out: Array = []
	for row in NEW_PATTERNS.get(type, []):
		out.append(String((row as Dictionary).id))
	return out

## 회피(2026-09-09, 시험값)를 **시작해도 되는 상태**. 여기 없는 상태에서는 절대 시작하지 않는다.
## 뺀 것과 그 이유:
##  - 자기 공격 준비·실행(COMMITTED의 모든 상태) — 사용자 지시 "자신의 공격 준비·실행 중에는 회피하지 않는다"
##  - **빈틈**(recover · 송곳니/채굴자의 stagger · 집행자의 retract · 채굴자의 erupt) — 되갚는 창이라 빠져나가면 안 된다
##  - 지하(hidden)·공중(airborne) — 그 구간은 이미 고유 패턴이 자리를 정한다
## 남은 것은 걷거나 자리를 잡는 구간뿐이다. 회피가 끝나면 전부 approach로 돌아간다.
const DODGE_FROM := {
	"elite_archer": ["approach", "reposition"],
	"elite_blademaster": ["approach", "backoff"],
	"elite_fang": ["approach"],
	"elite_plaguecaller": ["approach"],
	"elite_chainbreaker": ["approach"],
	"elite_standard": ["approach"],
	"elite_miner": ["approach"],
}

## 표현별 후보 각도(도). 0 = 위협의 반대쪽 정면. 앞의 것부터 좋은 자리로 치고, 지형이 막으면 뒤 후보로 넘어간다
const DODGE_ANGLES := {
	"backstep": [0.0, 40.0, -40.0, 80.0, -80.0],
	"sidestep": [90.0, -90.0, 55.0, -55.0, 0.0],
	"roll": [55.0, -55.0, 20.0, -20.0, 0.0],
	"leap": [35.0, -35.0, 70.0, -70.0, 0.0],
}
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
## **종류별** 동시 위험 공격 상한(2026-09-10 §12, 시험값). 전체 상한(by_act)과 다른 값이다.
## 왜 필요한가: 종류별 생존 상한을 올리면 같은 종류가 한꺼번에 많이 살 수 있다. 도마뱀처럼
## **오래 유지되는 넓은 위험**(2.4초짜리 불줄기)은 그때 서로 겹쳐 피할 곳이 사라진다.
## 표에 없는 종류는 상한이 없다(기존 동작 그대로). 값은 data/pacing.json danger_limit.by_type
static func danger_type_max(type: String) -> int:
	var by: Dictionary = danger_cfg().get("by_type", {})
	return int(by[type]) if by.has(type) else 9999

## 지금 같은 종류로 위험 공격 중인 적 수(자기 자신 제외)
static func danger_count_type(st: CombatState, e: Dictionary, type: String) -> int:
	var n := 0
	for o in st.enemies:
		if o == e or bool(o.dead) or String(o.type) != type:
			continue
		if danger_busy(o):
			n += 1
	return n

static func may_start(st: CombatState, e: Dictionary, dt: float) -> bool:
	if bool(danger_cfg().get("enabled", false)) and String(st.mode) != "boss":
		if danger_count(st, e) >= danger_max(st):
			e.ready_t = -1.0
			return false
		var tp := String(e.type)
		var tmax := danger_type_max(tp)
		if tmax < 9999 and danger_count_type(st, e, tp) >= tmax:
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
	# 특수 정예 7종: **관측 이동**을 먼저 갱신하고(§11-B, 매 프레임 필요) 신규 패턴 재사용 시각을 흘린다.
	# 회피로 이 프레임이 끝나더라도 둘 다 이미 갱신됐으므로 관측이 끊기지 않는다
	if is_elite(type):
		obs_vel(st, e, st.target_of(e))
		tick_patterns(e, dt)
	# 특수 정예 7종의 회피(docs/ELITE_DODGE.md). 이동 구간에는 고유 패턴 대신 회피가 이 프레임을 굴린다.
	# is_elite(type)이라 일반 몬스터·일반 정예 확장의 바탕 갱신 경로(update_base)는 지나가지 않는다
	if is_elite(type) and elite_dodge(st, e, dt):
		return
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
				# 빈틈 길이는 **겹침 파일이 정본**이다(dv). 예전에는 정의 사전만 봐서
				# pacing.json 으로 조절할 수 없었다
				to_recover(st, e, dv(e, "recover", 1.3))
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
				# §10 개편: **직접 피해가 없다.** 맞으면 받는 피해가 늘어나는 저주만 건다(try_curse).
				# 화면 표시는 예전과 같은 자리·같은 반지름이므로 무엇을 피해야 하는지는 그대로다
				var at: Array = e.rune_at
				try_curse(st, e, float(at[0]), float(at[1]), dv(e, "runeR", 0.0))
				st.fx({ "kind": "bossland", "x": float(at[0]), "y": float(at[1]), "r": dv(e, "runeR", 0.0), "ttl": 0.4 })
				st.note_attack(e, "execute")
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
	# 특수 정예 회피: **이미 맞은 뒤**의 반응 근거만 남긴다(피해를 되돌리거나 줄이지 않는다. docs/ELITE_DODGE.md)
	if dmg > 0.0 and is_elite(String(e.type)):
		e["dodge_hit_t"] = st.t
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
		# §12: 첫 실제 분사까지의 **지연**. 예전에는 코드에 1.2초가 박혀 있어 등장 뒤 한참을 그냥 걸었다.
		# 값은 data/pacing.json enemy_tuning.lizard.flameFirst가 정본이다(준비시간 flameAim·flameLock과 분리된 값)
		e.flame_t = dv(e, "flameFirst", 1.2)
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

## 연계를 시작해도 되는가: 기존 동시 제한(may_attack) + 정예 동시 연계 1 + 회피 단계
static func elite_may_start(st: CombatState, e: Dictionary, dt: float) -> bool:
	if dodge_locked(e): # 반응 지연·이동·추스르는 틈: 회피 직후 무예고 공격으로 이어지지 않는다
		e.ready_t = -1.0
		return false
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

# ---------- 특수 정예 공통: 회피 (2026-09-09, 전부 시험값. docs/ELITE_DODGE.md) ----------
## 무엇인가: 플레이어의 Space 회피처럼 **짧고 빠르게 자리를 바꾸는** 행동이다. 종류에 따라
##   옆걸음·구르기·도약·짧은 후퇴로 표현하며 수치는 data/elites.json의 elites.<id>.dodge에 있다.
##   **특수 정예 7종만** 가진다 — 일반 몬스터·일반 정예 확장 10종·보스에는 없다(dodge_cfg가 빈 사전을 준다).
##
## 무엇이 아닌가
##  - **무적이 아니다.** 이동 중에도 피해·넉백·바닥 효과가 그대로 들어간다. 공격 도약과 달리 airborne을
##    쓰지 않는 것도 같은 이유다 — 밀어내기·지형 규칙을 하나도 비켜 가지 않는다.
##  - 이미 맞은 피해를 되돌리지 않는다. 장판을 지우지 않고, 추적 탄도 무효로 만들지 않는다
##    (투사체 판단에 **직선 예측만** 쓴다 — 휘어 오는 탄은 그대로 맞는다).
##  - 플레이어 입력이나 아직 시작되지 않은 공격을 미리 읽지 않는다. **이미 나타난** 전투 상태만 본다.
##
## 상태 우선순위: **빙결 > 경직 > 회피 > 고유 패턴**
##  - 빙결(freeze > 0): CombatState.update_enemies가 갱신을 통째로 건너뛰므로 회피 단계와 재사용도 함께 멈춘다.
##    여기서도 한 번 더 막는다(soft 빙결·다른 경로로 들어와도 같게 동작하도록).
##  - 경직(stagger > 0): **다른 담당이 만드는 필드**라 e.get으로 안전하게 읽는다. 있으면 시작하지 않고
##    이미 반응 지연 중이면 취소한다. (송곳니·채굴자의 `state == "stagger"`는 이것과 다른 것이며, 그쪽은 DODGE_FROM이 막는다.)
##  - 회피: 조건을 만족하면 그 프레임의 이동을 고유 패턴 대신 회피가 굴린다(이동 구간에만).
##  - 고유 패턴: 이동이 끝나면 approach로 돌아가 원래대로 이어 간다.
##
## 단계: (없음) → react(반응 지연) → move(이동) → settle(추스르는 틈) → (없음)
##  세 단계 모두 elite_may_start를 막는다 — 회피 직후 무예고 공격으로 이어지지 않는다.
##  한 프레임에 단계 전이는 **최대 한 번**이라 큰 dt(낮은 프레임·일시정지 복귀)에서도 두 번 처리되지 않는다.
##
## 개체별 필드(지연 초기화): dodge_phase, dodge_t, dodge_cd, dodge_wait, dodge_dx, dodge_dy, dodge_dist,
##   dodge_from, dodge_kind, dodge_hit_t, 그리고 계측용 dodge_seen(조건 충족) · dodge_uses(실제 발동) · dodge_skip(마지막으로 쓰지 않은 이유)

## 비교 측정 전용 스위치(기본 켬). 끄면 회피가 아예 없던 개편 전 동작이 된다 —
## "연계 완주가 줄어든 것이 회피 때문인가"를 같은 시드로 가르려면 켠 판과 끈 판이 둘 다 필요하다.
## 게임 실행에는 영향이 없다(아무도 부르지 않으면 켜진 채다). PBoss.set_break_on과 같은 방식이다
static var _dodge_on := true

static func set_dodge_on(v: bool) -> void:
	_dodge_on = v

static func dodge_enabled() -> bool:
	return _dodge_on

## 그 종류의 회피 설정. 특수 정예가 아니면 빈 사전이다(여기가 '누가 회피를 가지는가'의 정본)
static func dodge_cfg(type: String) -> Dictionary:
	if not _dodge_on:
		return {}
	if not ELITE_TYPES.has(type):
		return {}
	var row: Dictionary = PCatalog.elite_def(type)
	if not row.has("dodge"):
		return {}
	var c: Dictionary = row.dodge
	return c

static func dodge_num(c: Dictionary, key: String, fallback: float) -> float:
	return float(c[key]) if c.has(key) else fallback

## 지금 회피와 관련된 단계에 있는가(반응 지연·이동·추스르는 틈). 참이면 새 공격을 시작하지 않는다
static func dodge_locked(e: Dictionary) -> bool:
	return String(e.get("dodge_phase", "")) != ""

static func _dodge_init(e: Dictionary, c: Dictionary) -> void:
	e["dodge_phase"] = ""
	e["dodge_t"] = 0.0
	e["dodge_cd"] = dodge_num(c, "first", 2.5) # 전투 시작 직후에 바로 쓰지 않게 하는 여유
	e["dodge_wait"] = 0.0
	e["dodge_dx"] = 0.0
	e["dodge_dy"] = 0.0
	e["dodge_dist"] = 0.0
	e["dodge_from"] = [0.0, 0.0]
	e["dodge_kind"] = ""
	e["dodge_hit_t"] = float(e.get("dodge_hit_t", -99.0)) # 첫 갱신 전에 맞았을 수도 있다
	e["dodge_seen"] = 0
	e["dodge_uses"] = 0
	e["dodge_skip"] = "none"

## 지금 회피하면 안 되는 이유. ""면 해도 된다. 우선순위 그대로 위에서부터 본다
static func _dodge_deny(e: Dictionary) -> String:
	if float(e.get("freeze", 0.0)) > 0.0:
		return "freeze"
	if float(e.get("stagger_t", 0.0)) > 0.0: # 연계 완성 경직(combat_state.gd. 필드가 없으면 0.0)
		return "stagger"
	if bool(e.get("hidden", false)) or bool(e.get("airborne", false)):
		return "airborne"
	if is_committed(e): # 자기 공격 준비·실행 중
		return "committed"
	var allow: Array = DODGE_FROM.get(String(e.type), [])
	if not allow.has(String(e.state)):
		return "state" # 빈틈(recover·stagger·retract)과 그 밖의 연계 구간
	return ""

## 회피 한 단계. true를 돌려주면 **이번 프레임의 이동을 회피가 대신 굴렸다**(고유 패턴을 건너뛴다)
static func elite_dodge(st: CombatState, e: Dictionary, dt: float) -> bool:
	var c := dodge_cfg(String(e.type))
	if c.is_empty():
		return false
	if not e.has("dodge_phase"):
		_dodge_init(e, c)
	var ph := String(e.dodge_phase)
	e.dodge_cd = maxf(0.0, float(e.dodge_cd) - dt) # 재사용은 단계와 무관하게 흐른다 — **시작 순간부터**(플레이어 회피와 같은 규칙)
	if ph == "":
		e.dodge_wait = maxf(0.0, float(e.dodge_wait) - dt)
		_dodge_try(st, e, c)
		return false
	if ph == "react": # 반응 지연: 아직 움직이지 않는다. 이 사이에 맞으면 그대로 맞는다
		var why := _dodge_deny(e)
		if why != "": # 지연 중에 얼거나 경직되거나 스스로 공격을 시작하면 회피는 취소된다
			e.dodge_phase = ""
			e.dodge_t = 0.0
			e.dodge_skip = why
			return false
		e.dodge_t = float(e.dodge_t) + dt
		if float(e.dodge_t) >= dodge_num(c, "react", 0.3):
			_dodge_launch(st, e, c)
			return true # 이 프레임은 방향을 정하는 데 쓴다. **이동은 다음 프레임부터** — 큰 dt에서도 두 번 처리되지 않는다
		return false
	if ph == "move":
		_dodge_step(st, e, c, dt)
		return true
	# settle: 자세를 추스른다. 고유 패턴의 이동은 그대로 굴리되 **새 공격은 시작하지 않는다**
	e.dodge_t = float(e.dodge_t) + dt
	if float(e.dodge_t) >= dodge_num(c, "settle", 0.45):
		e.dodge_phase = ""
		e.dodge_t = 0.0
	return false

## 시작 판단. 재사용이 돌아왔다고 반드시 회피하지는 않는다 — 실제 위협이 보일 때만, 그것도 확률로 고른다
static func _dodge_try(st: CombatState, e: Dictionary, c: Dictionary) -> void:
	if float(e.dodge_cd) > 0.0:
		e.dodge_skip = "cooldown"
		return
	if float(e.dodge_wait) > 0.0: # 굴림에 실패한 뒤 다시 판단하지 않는 시간(매 프레임 다시 굴리면 확률이 사실상 1이 된다)
		return
	var why := _dodge_deny(e)
	if why != "":
		e.dodge_skip = why
		return
	var th := _dodge_threat(st, e, c)
	if th.is_empty():
		e.dodge_skip = "no_threat"
		return
	e.dodge_seen = int(e.dodge_seen) + 1 # 조건 충족(위협을 보고 판단한) 횟수
	if st.rng.next() > dodge_num(c, "chance", 0.7):
		e.dodge_wait = dodge_num(c, "retry", 1.2)
		e.dodge_skip = "chance" # 모든 공격을 자동으로 완벽하게 피하지는 않는다
		return
	e.dodge_phase = "react"
	e.dodge_t = 0.0
	e.dodge_kind = String(th.kind)
	e.dodge_from = [float(th.x), float(th.y)] # 위협이 닿을 자리 — 반응 지연이 끝나면 여기를 기준으로 방향을 고른다

## 무엇을 위협으로 보는가. 셋 다 **이미 나타난** 전투 상태다(아직 시작되지 않은 공격은 보지 않는다)
static func _dodge_threat(st: CombatState, e: Dictionary, c: Dictionary) -> Dictionary:
	var look := dodge_num(c, "look", 0.7)
	var rr: float = float(e.r) + dodge_num(c, "margin", 22.0)
	# ① 이미 화면에 뜬 바닥 예고(전투망치 내려찍기·기술·지뢰)가 자기 자리를 덮을 때
	for f in st.effects:
		if String(f.get("kind", "")) != "strikewarn":
			continue
		if PGeom.dist(float(f.x), float(f.y), float(e.x), float(e.y)) <= float(f.get("r", 0.0)) + float(e.r):
			return { "kind": "warn", "x": float(f.x), "y": float(f.y) }
	# ② 날아오는 투사체(적의 것은 세지 않는다). 직선 예측만 쓴다 — 추적 탄을 임의로 무효화하지 않기 위해서다
	for pr in st.projectiles:
		if bool(pr.get("dead", false)) or String(pr.get("owner", "")) == "enemy":
			continue
		var vx: float = float(pr.get("vx", 0.0))
		var vy: float = float(pr.get("vy", 0.0))
		var vv: float = vx * vx + vy * vy
		if vv < 1.0:
			continue
		var hr: float = rr + float(pr.get("r", 4.0))
		var rx: float = float(pr.x) - float(e.x)
		var ry: float = float(pr.y) - float(e.y)
		if rx * rx + ry * ry <= hr * hr:
			continue # 이미 코앞이다 — 늦었다(놓친 것으로 둔다)
		var tc: float = -(rx * vx + ry * vy) / vv
		if tc <= 0.0 or tc > look:
			continue
		var cx: float = float(pr.x) + vx * tc
		var cy: float = float(pr.y) + vy * tc
		if PGeom.dist(cx, cy, float(e.x), float(e.y)) > hr:
			continue
		return { "kind": "projectile", "x": cx, "y": cy }
	# ③ **방금 맞은** 직접 타격. 예측이 아니라 이미 일어난 일에 대한 반응이고, 피해는 그대로 들어간 뒤에 물러선다.
	#    근접 주무기(검·창·단검)에는 미리 보이는 예고가 없어서 이것이 없으면 회피가 전투 내내 한 번도 나오지 않는다
	if bool(c.get("react_to_hit", true)) and st.t - float(e.get("dodge_hit_t", -99.0)) <= dodge_num(c, "hit_window", 0.5):
		var p := st.target_of(e)
		return { "kind": "hit", "x": float(p.x), "y": float(p.y) }
	return {}

## 방향을 고르고 이동을 시작한다. 재사용은 **시작 순간부터** 흐른다(플레이어 회피와 같은 규칙)
static func _dodge_launch(st: CombatState, e: Dictionary, c: Dictionary) -> void:
	var ref: Array = e.dodge_from
	var ax: float = float(e.x) - float(ref[0])
	var ay: float = float(e.y) - float(ref[1])
	if ax * ax + ay * ay < 1.0: # 위협이 발밑이면 표적 반대쪽을 기준으로 삼는다
		var p := st.target_of(e)
		ax = float(e.x) - float(p.x)
		ay = float(e.y) - float(p.y)
	var n := PGeom.norm(ax, ay)
	var base: float = atan2(n[1], n[0]) if not (n[0] == 0.0 and n[1] == 0.0) else float(e.get("face", 0.0))
	var dist := dodge_num(c, "dist", 100.0)
	var style := String(c.get("style", "backstep"))
	var offs: Array = DODGE_ANGLES[style] if DODGE_ANGLES.has(style) else DODGE_ANGLES["backstep"]
	var best := base
	var best_score := -1.0e12
	for o in offs:
		var a: float = base + PGeom.deg(float(o))
		var tx: float = float(e.x) + cos(a) * dist
		var ty: float = float(e.y) + sin(a) * dist
		var score: float = PGeom.dist(tx, ty, float(ref[0]), float(ref[1]))
		# 벽·바위에 막히는 방향은 뒤로 민다. 골라도 뚫고 가지는 않는다(move_swept가 그 자리에서 멈춘다)
		if not st.valid_pos(tx, ty, float(e.r)):
			score -= 100000.0
		if not st.valid_pos(float(e.x) + cos(a) * dist * 0.5, float(e.y) + sin(a) * dist * 0.5, float(e.r)):
			score -= 100000.0
		if score > best_score:
			best_score = score
			best = a
	e.dodge_dx = cos(best)
	e.dodge_dy = sin(best)
	e.dodge_dist = 0.0
	e.dodge_phase = "move"
	e.dodge_t = 0.0
	e.dodge_cd = dodge_num(c, "cooldown", 10.0)
	e.dodge_uses = int(e.dodge_uses) + 1
	e.state = "dodge" # 공격 상태가 아니다 — COMMITTED에 없으므로 '위험 공격 중'으로 세지 않는다
	e.state_t = 0.0
	st.text(float(e.x), float(e.y) - float(e.r) - 26.0, String(c.get("style_text", "회피")), "#cfe3ff")
	st.ev("dodge")

## 이동 한 단계. 벽·바위에 닿으면 거기서 끝난다(플레이어 회피와 같은 규칙)
static func _dodge_step(st: CombatState, e: Dictionary, c: Dictionary, dt: float) -> void:
	var dist := dodge_num(c, "dist", 100.0)
	var tm := maxf(0.001, dodge_num(c, "time", 0.25))
	var sm := st.enemy_speed_mult(e) # 냉기·감속장은 이동을 늦춘다(기존 규칙 그대로 — 그만큼 덜 간다)
	var remain: float = maxf(0.0, dist - float(e.dodge_dist))
	var want: float = minf(dist / tm * sm * dt, remain)
	var x0: float = e.x
	var y0: float = e.y
	var blocked := false
	if want > 0.0:
		var res := st.move_swept(e, float(e.dodge_dx) * want, float(e.dodge_dy) * want)
		blocked = String(res.hit) != ""
	e.dodge_dist = float(e.dodge_dist) + PGeom.dist(x0, y0, float(e.x), float(e.y))
	e.dodge_t = float(e.dodge_t) + dt
	if blocked or float(e.dodge_dist) >= dist - 1e-6 or float(e.dodge_t) >= tm - 1e-9:
		e.dodge_phase = "settle"
		e.dodge_t = 0.0
		e.state = "approach" # 고유 패턴으로 복귀
		e.state_t = 0.0

# ---------- §11-B 공통 도구: 관측한 이동 · 패턴 고르기 ----------
## **관측한 플레이어 이동**(사용자 지시 "플레이어 입력을 미리 읽지 말고 관측 가능한 위치·이동을 사용"의 구현).
## 개체마다 지난 프레임의 플레이어 위치를 적어 두고, 그 차이를 OBS_WIN(초)짜리 지연으로 부드럽게 만든다.
## 그래서 플레이어가 방향을 꺾으면 이 값은 약 OBS_WIN 동안 **옛 방향**을 가리킨다 —
## 앞을 겨누는 패턴(엇박 저격·앞질러 습격·역병 가로막기·사슬 끌어쓸기)이 방향 전환으로 빗나가는 이유가 이 지연이다.
## p.face(그 프레임의 이동 입력 방향)는 **쓰지 않는다** — 그건 입력을 그대로 읽는 것과 같기 때문이다.
const OBS_WIN := 0.30

## 관측 속도 [vx, vy](픽셀/초). 매 프레임 불러야 값이 따뜻하게 유지된다(update_as가 정예마다 한 번 부른다)
static func obs_vel(st: CombatState, e: Dictionary, p: Dictionary) -> Array:
	var lt: float = float(e.get("obs_t", -1.0))
	var vx: float = float(e.get("obs_vx", 0.0))
	var vy: float = float(e.get("obs_vy", 0.0))
	if lt >= 0.0:
		var age: float = st.t - lt
		if age > 1e-5:
			var k: float = clampf(age / OBS_WIN, 0.0, 1.0)
			vx += ((float(p.x) - float(e.get("obs_x", p.x))) / age - vx) * k
			vy += ((float(p.y) - float(e.get("obs_y", p.y))) / age - vy) * k
	e["obs_t"] = st.t
	e["obs_x"] = p.x
	e["obs_y"] = p.y
	e["obs_vx"] = vx
	e["obs_vy"] = vy
	return [vx, vy]

## 관측 이동으로 내다본 앞 지점. lead_max로 상한을 둬 **무한정 앞서 겨누지 않는다**(멀리 도망칠수록 더 앞을 막는 일이 없게)
static func obs_lead(st: CombatState, e: Dictionary, p: Dictionary, tof: float, lead_max: float) -> Array:
	var v := obs_vel(st, e, p)
	var dx: float = float(v[0]) * tof
	var dy: float = float(v[1]) * tof
	var dd := sqrt(dx * dx + dy * dy)
	if dd > lead_max and dd > 1e-6:
		dx = dx / dd * lead_max
		dy = dy / dd * lead_max
	return [float(p.x) + dx, float(p.y) + dy]

## 지금 관측 속도의 크기(픽셀/초). "같은 방향으로 걷고 있다"를 재는 값
static func obs_speed(e: Dictionary) -> float:
	var vx: float = float(e.get("obs_vx", 0.0))
	var vy: float = float(e.get("obs_vy", 0.0))
	return sqrt(vx * vx + vy * vy)

## 신규 패턴 재사용 시각을 흐르게 한다(상태와 무관하게 흐른다 — 연계 중에도 다음 차례가 준비된다).
## 첫 사용까지의 여유는 <id>First, 다음 사용까지는 <id>Interval(둘 다 data/pacing.json enemy_tuning)
static func tick_patterns(e: Dictionary, dt: float) -> void:
	for row in NEW_PATTERNS.get(String(e.type), []):
		var r: Dictionary = row
		var key := String(r.cd)
		if not e.has(key):
			e[key] = dv(e, String(r.id) + "First", 2.0)
		else:
			e[key] = float(e[key]) - dt

## 지금 시작해도 되는 신규 패턴 하나를 시작한다(했으면 true).
## allow는 부르는 쪽이 정한 **거리·상황 조건**이다(id → bool). 재사용이 끝난 것 중 **가장 오래 기다린 것**을 고른다
## — 무작위를 쓰지 않으므로 같은 시드에서 늘 같은 순서가 나오고 검사가 재현된다.
static func try_new_pattern(st: CombatState, e: Dictionary, dt: float, allow: Dictionary) -> bool:
	var best: Dictionary = {}
	var best_left := 0.0
	for row in NEW_PATTERNS.get(String(e.type), []):
		var r: Dictionary = row
		if not bool(allow.get(String(r.id), false)):
			continue
		var left: float = float(e.get(String(r.cd), 9.0))
		if left > 0.0:
			continue
		if best.is_empty() or left < best_left:
			best = r
			best_left = left
	if best.is_empty() or not elite_may_start(st, e, dt):
		return false
	var id := String(best.id)
	e[String(best.cd)] = dv(e, id + "Interval", 9.0)
	e["last_pattern"] = id
	var uses: Dictionary = e.get("pattern_uses", {})
	uses[id] = int(uses.get(id, 0)) + 1
	e["pattern_uses"] = uses
	var agg: Dictionary = st.metrics.get("elite_patterns", {}) # 계측 전용(규칙에 영향 없음)
	agg[id] = int(agg.get(id, 0)) + 1
	st.metrics["elite_patterns"] = agg
	elite_begin(st, e, String(best.state), String(best.label), String(best.color))
	return true

## 이 개체가 실제로 쓴 신규 패턴 횟수(검사·계측이 읽는다)
static func pattern_uses(e: Dictionary) -> Dictionary:
	return e.get("pattern_uses", {})

## 부채꼴 근접 판정 + 화면 표시 한 벌(신규 근접 패턴이 공통으로 쓴다)
static func arc_strike(st: CombatState, e: Dictionary, ang: float, R: float, half: float, dmg: float, src: String) -> void:
	arc_hit(st, e, ang, R, half, dmg, src)
	st.fx({ "kind": "arc", "x": e.x, "y": e.y, "angle": ang, "r": R, "half": half, "ttl": 0.14, "enemy": true })
	st.note_attack(e, "execute")

# ---------- §10 주술사의 피해 증폭 저주(2026-09-10, 전부 시험값. docs/CURSE.md) ----------
## 무엇인가: **기존 저주 문양(rune_aim)을 개편**한 것이다. 비슷한 문양을 하나 더 추가하지 않았다.
##  - 문양 자체의 **직접 피해는 없다**(runeDamage 12 → 0). 맞으면 그 뒤 받는 피해가 +50%가 된다.
##  - 문양 자리는 **예고를 시작하는 순간** 고정이고 그 뒤 따라오지 않는다(개편 전과 같다).
##  - 회피 무적·피격 보호를 **무시하지 않는다** — 그 둘에 막히면 저주도 걸리지 않는다.
##
## 상태를 어디에 두는가: 플레이어 사전의 **시각 한 칸**(curse_until)뿐이다. 남은 시간은 st.t와의 차이로 읽으므로
## 매 단계 줄여 줄 자리가 필요 없다(그 자리는 담당 밖 파일이다). 여러 주술사가 걸어도 같은 칸을 갱신하니
## 배율이 겹쳐 곱해질 방법이 아예 없다 — 상한 ×1.5는 자료 구조가 보장한다.
##
## **곱하는 자리는 여기가 아니다.** scripts/rules/combat_state.gd가 담당 밖이라 상태만 걸어 둔다.
## 붙일 자리는 apply_player_damage의 등급 배율(tier_dmg) 바로 다음 한 곳이다(docs/CURSE.md §붙일 자리).
static func curse_cfg() -> Dictionary:
	return tuning("shaman")

## 저주가 더하는 몫(0.5 = 받는 피해 +50%)
static func curse_add() -> float:
	return float(curse_cfg().get("curseAdd", 0.5))

static func curse_dur() -> float:
	return float(curse_cfg().get("curseDur", 4.0))

## 남은 저주 시간(초). 0이면 걸려 있지 않다
static func curse_left(st: CombatState) -> float:
	return maxf(0.0, float(st.player.get("curse_until", -1.0)) - st.t)

static func curse_on(st: CombatState) -> bool:
	return curse_left(st) > 0.0

## **피해 계산에 곱할 값.** 여러 주술사가 겹쳐 걸어도 1 + curseAdd를 넘지 않는다(칸이 하나뿐이라 구조로 보장)
static func curse_mult(st: CombatState) -> float:
	return (1.0 + curse_add()) if curse_on(st) else 1.0

## 화면에 적을 한 줄("저주 · 받는 피해 +50%"). 걸려 있지 않으면 빈 글자
static func curse_label(st: CombatState) -> String:
	if not curse_on(st):
		return ""
	return "저주 · 받는 피해 +%d%%" % int(round(curse_add() * 100.0))

## 문양이 실제로 적중했는가. 맞았으면 저주를 **갱신**(더하지 않는다)하고 true
static func try_curse(st: CombatState, e: Dictionary, cx: float, cy: float, r: float) -> bool:
	var p := st.target_of(e)
	if bool(p.get("lure", false)): # 미끼는 저주에 걸리지 않는다(본체가 아니다)
		return false
	if PGeom.dist(cx, cy, float(p.x), float(p.y)) > r + float(p.r):
		return false
	var pl: Dictionary = st.player
	if float(pl.get("invuln_t", 0.0)) > 0.0: # 회피 무적을 무시하지 않는다
		st.text(pl.x, pl.y - 30.0, "회피!", "#7ef2ff")
		return false
	if st.hit_protected("shaman_curse", e): # 피격 보호를 무시하지 않는다
		return false
	var fresh: bool = not curse_on(st)
	pl["curse_until"] = st.t + curse_dur() # 재적중이면 남은 시간을 curseDur로 갱신한다(길이가 쌓이지 않는다)
	st.text(pl.x, pl.y - 46.0, "저주!" if fresh else "저주 갱신", "#e9b6ff")
	st.fx({ "kind": "burst", "x": pl.x, "y": pl.y, "r": float(pl.r) + 16.0, "ttl": 0.35, "color": "#e9b6ff" })
	st.ev("orb")
	var m: Dictionary = st.metrics
	m["curse_hits"] = int(m.get("curse_hits", 0)) + 1
	return true

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
			# §11-B 신규 2개를 먼저 본다. ① 추격 사격은 **멀어질 때**(같은 방향으로 걸어 벌린 거리를 스스로 좁힌다)
			#                          ② 엇박 저격은 사거리 안에서. 둘 다 실패하면 기존 단발 → 부채꼴 연계
			if try_new_pattern(st, e, dt, { "chase": dist > dv(e, "chaseStop", 200.0), "snipe": not blocked and dist <= float(d.keepMax) + 60.0 }):
				e.chase_left = int(dv(e, "chaseShots", 2.0))
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
		# ---- §11-B ① 추격 사격: 달려 접근하다 **짧게 멈춰** 빠른 화살 ----
		## 같은 방향으로 걷기만 하는 놀이를 흔드는 쪽은 "달려 붙는다"이다. 멈춘 뒤 예고 0.30 + 확정 0.10이 있고
		## 확정 뒤에는 따라가지 않으므로, 멈추는 것이 보이면 옆으로 꺾어 피한다. 두 발이 끝나면 확실한 빈틈이 남는다
		"chase_run":
			e.state_t += adv
			st.approach(e, p.x, p.y, dv(e, "chaseSpeed", 160.0) * sm, dt)
			if dist <= dv(e, "chaseStop", 190.0) or float(e.state_t) >= dv(e, "chaseRun", 1.1):
				e.state = "chase_aim"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "멈춰 쏜다", "#ffd166")
		"chase_aim": # 멈춰서 조준(이동 명령 없음). 예고 동안에는 **관측한 이동의 앞**으로 조준선이 옮겨간다
			var ctof: float = dv(e, "chaseLock", 0.1) + dist / maxf(1.0, dv(e, "chaseArrowSpeed", 620.0))
			var clead := obs_lead(st, e, p, ctof, dv(e, "chaseLeadMax", 130.0))
			e.aim_angle = atan2(float(clead[1]) - e.y, float(clead[0]) - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "chaseAim", 0.3):
				e.state = "chase_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 방향 확정 — 여기서부터 따라가지 않는다
				st.ev("lock")
		"chase_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "chaseLock", 0.1):
				_arrow(st, e, float(e.dir), dv(e, "chaseArrowSpeed", 620.0), float(d.arrowR), dv(e, "chaseArrowDamage", 11.0))
				st.note_attack(e, "execute")
				e.chase_left = int(e.get("chase_left", 1)) - 1
				if int(e.chase_left) > 0:
					e.state = "chase_run"
					e.state_t = 0.0
				else:
					to_recover(st, e, dv(e, "chaseRecover", 1.0))
		# ---- §11-B ② 엇박 저격: 첫 발 뒤 **이동한 방향을 새로 겨눈** 강한 두 번째 발 ----
		## 두 발의 예고를 구분할 수 있게 만들었다: 첫 발은 짧은 조준(0.45)에 보통 화살,
		## 사이에 눈에 보이는 **엇박 간격**(0.55, 궁수가 옆으로 자리를 옮긴다)이 있고,
		## 두 번째는 더 긴 조준(0.70)에 굵은 예고선이며 **관측한 이동 방향의 앞**을 겨눈다.
		## 관측은 OBS_WIN(0.30초) 지연이 있으므로 **간격 동안 방향을 바꾸면 앞을 겨눈 두 번째 발이 빗나간다**
		"snipe1_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "snipe1Aim", 0.45):
				e.state = "snipe1_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("lock")
		"snipe1_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "snipe1Lock", 0.1):
				_arrow(st, e, float(e.dir), float(d.arrowSpeed), float(d.arrowR), float(d.arrowDamage))
				st.note_attack(e, "execute")
				e.state = "snipe_gap"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 30.0, "엇박 — 두 번째 발", "#ff9f43")
		"snipe_gap": # 눈에 보이는 간격(옆으로 자리를 옮긴다). 공격 판정 없음
			e.state_t += adv
			strafe(st, e, float(d.strafeSpeed) * 0.7 * sm, dt)
			if float(e.state_t) >= dv(e, "snipeGap", 0.55):
				e.state = "snipe2_aim"
				e.state_t = 0.0
		"snipe2_aim": # **관측한 이동 방향의 앞**을 겨눈다(지금 서 있는 자리가 아니다)
			var tof: float = dist / maxf(1.0, dv(e, "snipe2Speed", 520.0))
			var lead := obs_lead(st, e, p, tof + dv(e, "snipe2Aim", 0.7) * 0.5, dv(e, "snipeLeadMax", 170.0))
			e.aim_angle = atan2(float(lead[1]) - e.y, float(lead[0]) - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "snipe2Aim", 0.7):
				e.state = "snipe2_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle # 확정 — 여기서부터는 앞을 다시 재지 않는다
				st.ev("lock")
		"snipe2_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "snipe2Lock", 0.18):
				_arrow(st, e, float(e.dir), dv(e, "snipe2Speed", 520.0), float(d.arrowR) + 2.0, dv(e, "snipe2Damage", 20.0))
				st.note_attack(e, "execute")
				to_recover(st, e, dv(e, "snipeRecover", 1.3))
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
			# §11-B ① 전진 연속 베기는 **가까울 때**(긴 돌진 두 번과 구분되는 근거리 추격),
			#        ② 추격 검기는 **멀 때**(원거리에서도 공격이 성립한다). 둘 다 아니면 기존 돌진 연계.
			# 거리를 만드는 backoff보다 **먼저** 본다 — 붙어 있을 때 쓰라고 만든 것이 전진 연속 베기이기 때문이다
			if try_new_pattern(st, e, dt, { "step": dist <= dv(e, "stepRange", 240.0), "wave": dist > dv(e, "stepRange", 240.0) and not st.los_blocked(e.x, e.y, p.x, p.y) }):
				return
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
		# ---- §11-B ① 전진 연속 베기: 짧게 전진하며 세 번 ----
		## 기존 긴 돌진(240px·640/s) 두 번과 **다른 것**이다: 78px·420/s짜리 짧은 전진 셋으로
		## 물러나는 상대를 조금씩 밀어붙인다. 매 번 예고가 따로 있고(0.32 / 0.26 / 0.26) 확정 뒤에는 방향을 바꾸지 않으므로
		## 옆으로 꺾으면 한 번씩 흘릴 수 있다. 세 번이 끝나면 1.1초 빈틈 — 반격 기회가 남는다
		"step1_aim", "step2_aim", "step3_aim":
			var stof: float = dv(e, "stepDist", 78.0) / maxf(1.0, dv(e, "stepSpeed", 420.0))
			var slead := obs_lead(st, e, p, stof, dv(e, "stepLeadMax", 90.0))
			e.aim_angle = atan2(float(slead[1]) - e.y, float(slead[0]) - e.x)
			e.state_t += adv
			var sidx: int = 1 if String(e.state) == "step1_aim" else (2 if String(e.state) == "step2_aim" else 3)
			if float(e.state_t) >= dv(e, "stepAim%d" % sidx, 0.3):
				e.dir = e.aim_angle # 확정 — 이 걸음 동안은 방향을 바꾸지 않는다
				e.charge_len = dv(e, "stepDist", 78.0)
				e.charge_end = [e.x + cos(float(e.dir)) * float(e.charge_len), e.y + sin(float(e.dir)) * float(e.charge_len)]
				e.charge_dist = 0.0
				e.hit_done = false
				e.state = "step%d" % sidx
				e.state_t = 0.0
				st.ev("lock")
				st.note_attack(e, "execute")
		"step1", "step2", "step3":
			if _charge_step(st, e, dv(e, "stepSpeed", 420.0), dv(e, "stepDamage", 13.0), "elite_step", dt, tf):
				var nidx: int = 2 if String(e.state) == "step1" else 3
				if String(e.state) == "step3":
					to_recover(st, e, dv(e, "stepRecover", 1.1))
				else:
					e.state = "step%d_aim" % nidx
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 30.0, "전진 연속 베기 %d/3" % nidx, "#ffb0b0")
		# ---- §11-B ② 추격 검기: 이동 경로를 겨눈 검기 + 본체도 전진 ----
		## 원거리에서도 성립한다. 예고 동안에는 **관측한 이동 방향의 앞**으로 조준선이 옮겨가고,
		## 확정(wave_lock) 뒤에는 각이 굳는다 — 검기는 직선으로 날아갈 뿐 따라오지 않는다.
		## 관측은 0.30초 지연이므로 예고를 보고 **방향을 꺾으면 빗나간다**. 본체가 함께 전진하므로 제자리 걷기는 통하지 않는다
		"wave_aim":
			var wtof: float = dist / maxf(1.0, dv(e, "waveSpeed", 430.0))
			var wl := obs_lead(st, e, p, wtof, dv(e, "waveLeadMax", 150.0))
			e.aim_angle = atan2(float(wl[1]) - e.y, float(wl[0]) - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "waveAim", 0.5):
				e.state = "wave_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				st.ev("lock")
		"wave_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "waveLock", 0.15):
				var wa: float = float(e.dir)
				var pr := { "owner": "enemy", "kind": "blade_wave", "shooter": e,
					"x": e.x + cos(wa) * (float(e.r) + 6.0), "y": e.y + sin(wa) * (float(e.r) + 6.0),
					"vx": cos(wa) * dv(e, "waveSpeed", 430.0), "vy": sin(wa) * dv(e, "waveSpeed", 430.0),
					"r": dv(e, "waveR", 22.0), "dmg": dv(e, "waveDamage", 15.0), "ttl": 2.0, "angle": wa, "dead": false, "hits": {} }
				CombatState.stamp_projectile(e, pr)
				st.projectiles.append(pr)
				st.note_attack(e, "execute")
				st.ev("shoot")
				e.state = "wave"
				e.state_t = 0.0
		"wave": # 검기를 날린 뒤 **본체도 전진**한다(거리를 벌린 채 버티는 놀이를 막는다). 이 구간에는 접촉 피해가 없다
			e.state_t += adv
			st.approach(e, p.x, p.y, dv(e, "waveWalk", 190.0) * sm, dt)
			if float(e.state_t) >= dv(e, "waveTime", 0.5):
				to_recover(st, e, dv(e, "waveRecover", 1.0))
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
			# §11-B ① 달리는 물어뜯기는 **멀리 있을 때**(측면으로 도는 기존 접근과 달리 곧장 달려든다)
			#        ② 앞질러 습격은 중거리에서. 걷는 방향 **앞쪽**에 내려앉아 도주 경로를 끊는다
			if try_new_pattern(st, e, dt, { "runbite": dist > float(d.biteRange) + float(e.r), "cut": dist <= dv(e, "cutRange", 340.0) and dist > float(d.biteRange) + float(e.r) }):
				e.runbite_left = int(dv(e, "runbiteCount", 2.0))
				return
			if dist <= float(d.biteRange) + e.r and elite_may_start(st, e, dt):
				# 2026-09-09 가독성(표시만): 물기 예고에는 글자도 소리도 없어 평범한 늑대보다 경고가 부실했다.
				# 짧은 낱말 하나 + **짧은 경고음**을 예고 시작에 붙인다. 예고 시간(biteAim 0.35)·속도·피해는 그대로다.
				elite_begin(st, e, "bite_aim", "문다!", "#ff6b93")
				st.ev("boss_lock") # 낮은 두 음(늑대 물기 bite_lock·돌진 lock, 두꺼비 lock+hazard_warn과 갈린다)
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
				# 도약 확정 소리. lock만 쓰면 늑대 돌진 확정과 같은 소리라 구분이 안 됐다(2026-09-09).
				# 낮은 두 음을 겹쳐 '송곳니의 확정'만 다른 소리로 들리게 한다. 확정 시각(leapAim 0.6 뒤)은 그대로다
				st.ev("lock")
				st.ev("boss_lock")
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
		# ---- §11-B ① 달리는 물어뜯기: 먼 플레이어에게 **접근해** 짧은 물기 두 번 ----
		## 기존 접근은 옆으로 크게 도는 길이라 걸어서 벌리면 계속 벌어졌다. 이쪽은 곧장 달려붙는다.
		## 물기 방향은 **물기 직전에 확정**되므로 각으로는 못 피한다 — 대신 사거리가 짧아(68) **거리를 벌리면** 빗나가고,
		## 달려오는 구간과 예고 부채꼴이 다 보인다. 두 번이 끝나면 1.0초 빈틈이 남는다
		"runbite_run":
			e.state_t += adv
			st.approach(e, p.x, p.y, dv(e, "runbiteSpeed", 235.0) * sm, dt)
			if dist <= float(d.biteRange) + float(e.r) or float(e.state_t) >= dv(e, "runbiteRun", 1.2):
				e.state = "runbite_aim"
				e.state_t = 0.0
				e.aim_angle = atan2(p.y - e.y, p.x - e.x)
				st.ev("boss_lock")
		"runbite_aim": # 예고 동안에도 **덤벼든다** — 멈춰 서면 걷기만으로 사거리를 벗어나 버린다
			st.approach(e, p.x, p.y, dv(e, "runbiteSpeed", 320.0) * dv(e, "runbiteLungeMult", 0.55) * sm, dt)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "runbiteAim", 0.3):
				# 물기 직전 확정. 부채꼴은 기본 물기(90도)보다 **좁다**(runbiteDeg) — 덤벼드는 대신 각을 좁혀
				# 방향을 꺾으면 빠져나갈 수 있게 했다
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), dv(e, "runbiteRange", float(d.biteRange)) + float(e.r), PGeom.deg(dv(e, "runbiteDeg", 60.0)) / 2.0, dv(e, "runbiteDamage", 13.0), "elite_runbite")
				e.bite_t = 0.0
				st.ev("bite")
				e.runbite_left = int(e.get("runbite_left", 1)) - 1
				if int(e.runbite_left) > 0:
					e.state = "runbite_run"
					e.state_t = 0.0
				else:
					to_recover(st, e, dv(e, "runbiteRecover", 1.0))
		# ---- §11-B ② 앞질러 습격: 진행 방향 **앞쪽**으로 도약 뒤 돌아서 할퀴기 ----
		## **착지와 후속을 각각 읽게** 만들었다: ① 앞쪽에 착지 원이 뜨고(0.5 예고 + 0.15 확정) ② 착지 충격이 한 번,
		## ③ 돌아서는 0.35초 동안은 판정이 없고 ④ 그 다음 할퀴기 예고(0.30)가 따로 뜬다.
		## 착지점은 **관측한 이동(0.30초 지연)** 으로 정하므로 예고를 보고 방향을 꺾으면 엉뚱한 곳에 내려앉는다
		"cut_aim":
			e.state_t += adv
			var cl := obs_lead(st, e, p, dv(e, "cutLead", 0.75), dv(e, "cutLeadMax", 150.0))
			var cpos := st.nearest_valid_pos(float(cl[0]), float(cl[1]), float(e.r), 160.0)
			e.leap_at = cpos if not cpos.is_empty() else [float(cl[0]), float(cl[1])]
			if float(e.state_t) >= dv(e, "cutAim", 0.5):
				e.state = "cut_lock"
				e.state_t = 0.0
				st.ev("lock")
				st.ev("boss_lock")
		"cut_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "cutLock", 0.15):
				e.state = "cut_leap"
				e.state_t = 0.0
				e.leap_from = [e.x, e.y]
				e.airborne = true
				st.note_attack(e, "execute")
		"cut_leap":
			e.state_t += adv
			var cat: Array = e.leap_at
			var cfr: Array = e.leap_from
			var ck: float = clampf(float(e.state_t) / maxf(0.001, dv(e, "cutLeap", 0.32)), 0.0, 1.0)
			e.x = float(cfr[0]) + (float(cat[0]) - float(cfr[0])) * ck
			e.y = float(cfr[1]) + (float(cat[1]) - float(cfr[1])) * ck
			if ck >= 1.0:
				e.airborne = false
				circle_hit(st, e, e.x, e.y, dv(e, "cutLandR", 62.0), dv(e, "cutLandDamage", 12.0), "elite_cut_land")
				e.state = "cut_turn"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 26.0, "돌아선다", "#ff6b93")
		"cut_turn": # 돌아서는 구간 — **공격 판정이 없다**(후속을 따로 읽을 시간)
			e.state_t += adv
			face_toward(e, p.x, p.y, dv(e, "cutTurnRate", 5.0), adv)
			if float(e.state_t) >= dv(e, "cutTurn", 0.35):
				elite_begin(st, e, "cut_claw_aim", "할퀴기", "#ff9f43")
		"cut_claw_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "cutClawAim", 0.3):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), dv(e, "cutClawRange", 62.0) + float(e.r), PGeom.deg(dv(e, "cutClawDeg", 100.0)) / 2.0, dv(e, "cutClawDamage", 18.0), "elite_cut_claw")
				st.ev("bite")
				to_recover(st, e, dv(e, "cutRecover", 1.2))
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
## 포자를 순서대로 터뜨린다(예고 0.5 → 첫 포자 0.9 → 다음 포자를 **새로 조준**해 0.55 예고 → …) → 재정비 1.5초.
## 잔류 구름은 수(3)·시간(2.6초) 상한이 있고, 전장 전체를 덮지 않도록 배치 전에 탈출 방향 수를 확인한다.
## 근접(96 이내)에는 예고된 좁은 포자 분출(70°)로 대응한다.
##
## **2026-09-10 §12 수정(무엇이 문제였나)**: 순차 폭발은 원래부터 있었다. 문제는 **세 자리를 전부 처음에 한 번에 고정**한 것이다
##   (_place_pods가 throw_aim 끝에서 3개를 다 놓았다). 그래서 첫 폭발을 보고 걸어 나오면 **남은 두 개가 통째로 헛돌았다** —
##   구역을 벗어나기만 하면 나머지 공격이 전부 의미를 잃는 구조였다.
##   이제는 **한 번에 한 자리만** 정한다. 포자가 터지면 그때 플레이어가 서 있는 자리를 **새로 조준**해 다음 포자를 예고한다(podRearm).
##   각 포자는 여전히 자리가 고정된 예고이고 확정 뒤 따라오지 않는다 — 바뀐 것은 '언제 자리를 정하는가'뿐이다.
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
			# §11-B ① 추적 포자탄(중·원거리) ② 역병 가로막기(걷는 앞을 긴 띠로 끊는다)
			if try_new_pattern(st, e, dt, { "seek": dist <= dv(e, "seekRange", 420.0), "wall": dist <= dv(e, "wallRange", 420.0) }):
				if String(e.state) == "wall_aim":
					e.wall = _place_wall(st, e)
				return
			# 주 무기는 포자 3개다. 분출은 '붙었는데 아직 포자가 준비되지 않았을 때'의 대응이지 기본 행동이 아니다
			if float(e.cast_t) <= 0.0 and dist <= float(d.keepMax) + 60.0 and elite_may_start(st, e, dt):
				elite_begin(st, e, "throw_aim", "포자 %d개 — 하나씩 다시 조준" % int(d.podCount), "#9cff9c")
				return
			if dist <= float(d.burstRange) + e.r and elite_may_start(st, e, dt):
				elite_begin(st, e, "burst_aim", "포자 분출", "#9cff9c")
		"throw_aim":
			e.state_t += adv
			if float(e.state_t) >= float(d.throwAim):
				e.pods = []
				e.pod_done = 0
				_aim_next_pod(st, e, float(d.swell)) # **첫 자리만** 정한다(나머지는 폭발할 때마다 새로 조준)
				e.state = "swell"
				e.state_t = 0.0
				st.ev("spore")
				st.ev("hazard_warn")
		"swell": # 한 개씩: 터질 때마다 **다음 자리를 새로 조준·예고**한다. 정한 개수를 다 쓰면 재정비
			e.state_t += adv
			_update_pods(st, e, d)
			var waiting := false
			for pod in e.pods:
				if not bool(pod.done):
					waiting = true
			if not waiting:
				if int(e.get("pod_done", 0)) < int(d.podCount):
					_aim_next_pod(st, e, dv(e, "podRearm", 0.55)) # 폭발 사이에 새로 조준(§12)
					st.ev("hazard_warn")
				else:
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
		# ---- §11-B ① 추적 포자탄: 가까워지면 **추적을 멈추고** 부푼 뒤 폭발 ----
		## 끝까지 쫓아와 반드시 맞히는 확정 피해로 만들지 않았다. 포자탄은 seekStop(110)까지만 따라오고
		## 거기서 **멈춘 채** seekSwell(0.6초) 동안 부푼다 — 그 사이에 반지름 seekR 밖으로 걸어 나가면 맞지 않는다.
		## 선회 속도에도 상한(seekTurn)이 있어 옆으로 크게 꺾으면 애초에 따라붙지 못한다
		"seek_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "seekAim", 0.45):
				e.seek = { "x": e.x + cos(float(e.aim_angle)) * (float(e.r) + 6.0), "y": e.y + sin(float(e.aim_angle)) * (float(e.r) + 6.0), "ang": float(e.aim_angle) }
				e.state = "seek_fly"
				e.state_t = 0.0
				st.note_attack(e, "execute")
				st.ev("shoot")
		"seek_fly":
			e.state_t += adv
			var sk: Dictionary = e.seek
			var sang: float = float(sk.ang)
			var slead2 := obs_lead(st, e, p, dv(e, "seekLead", 0.55), dv(e, "seekLeadMax", 130.0))
			var want: float = atan2(float(slead2[1]) - float(sk.y), float(slead2[0]) - float(sk.x))
			var mx: float = dv(e, "seekTurn", 2.6) * adv
			sang += clampf(PGeom.ang_diff(sang, want), -mx, mx)
			sk.ang = sang
			sk.x = float(sk.x) + cos(sang) * dv(e, "seekSpeed", 210.0) * adv
			sk.y = float(sk.y) + sin(sang) * dv(e, "seekSpeed", 210.0) * adv
			# 멈추는 기준은 **걷는 앞 지점**이다: 플레이어의 지금 자리를 기준으로 멈추면 계속 걷는 상대에게 늘 뒤처진다
			var sd := PGeom.dist(float(sk.x), float(sk.y), float(slead2[0]), float(slead2[1]))
			if sd <= dv(e, "seekStop", 90.0) or float(e.state_t) >= dv(e, "seekFly", 2.2) \
				or float(sk.x) < 6.0 or float(sk.y) < 6.0 or float(sk.x) > st.arena_w - 6.0 or float(sk.y) > st.arena_h - 6.0:
				e.state = "seek_swell" # **여기서 추적이 끝난다** — 자리가 굳고 그 뒤로는 움직이지 않는다
				e.state_t = 0.0
				st.ev("hazard_warn")
		"seek_swell":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "seekSwell", 0.6):
				var sk2: Dictionary = e.seek
				circle_hit(st, e, float(sk2.x), float(sk2.y), dv(e, "seekR", 80.0), dv(e, "seekDamage", 16.0), "elite_spore_seek")
				st.ev("spore")
				e.erase("seek")
				to_recover(st, e, dv(e, "seekRecover", 1.3))
		# ---- §11-B ② 역병 가로막기: 도주 경로에 **긴 포자 띠**를 예고한 뒤 한쪽부터 폭발 ----
		## 띠 자리는 wall_aim 시작 순간에 확정한다(따라오지 않는다). 한쪽 끝부터 wallGap(0.18초) 간격으로 터지므로
		## **반대쪽 끝이나 아직 안 터진 칸을 지나 빠져나갈 수 있다**. 놓기 전에 탈출 방향 수를 확인해
		## 전부 막히면 플레이어에게 가까운 칸부터 지운다 — 피할 곳 없는 벽을 만들지 않는다
		"wall_aim":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "wallAim", 0.7):
				e.state = "wall_burst"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"wall_burst":
			e.state_t += adv
			var wleft := false
			for wp in e.get("wall", []):
				var w: Dictionary = wp
				if bool(w.done):
					continue
				if st.t >= float(w.land_at):
					w.done = true
					circle_hit(st, e, float(w.x), float(w.y), float(w.r), dv(e, "wallDamage", 14.0), "elite_spore_wall")
					st.ev("spore")
				else:
					wleft = true
			if not wleft:
				e.erase("wall")
				to_recover(st, e, dv(e, "wallRecover", 1.4))
		"recover":
			keep_distance(st, e, d, dt, sm)
			_recover_tick(e, adv)

## 다음 포자 한 개의 자리를 **지금** 정한다(§12 수정의 핵심). warn = 이 포자가 터지기까지의 예고 시간.
## 자리는 플레이어의 **현재 위치** 주위이며, 놓고 나서도 탈출 방향이 minExits개 이상 남는 곳만 쓴다.
## 놓을 자리가 없으면 그 포자는 건너뛴다(개수는 그대로 세므로 연계가 끝나지 않는 일이 없다).
static func _aim_next_pod(st: CombatState, e: Dictionary, warn: float) -> void:
	var d: Dictionary = e.def
	var p := st.target_of(e)
	var idx: int = int(e.get("pod_done", 0))
	e.pod_done = idx + 1
	var base: float = atan2(p.y - e.y, p.x - e.x)
	var pods: Array = e.pods
	for tryi in 3: # 한 자리가 막히면 좌·우로 벌려 다시 본다
		var a: float = base + PGeom.deg(float(d.podArcDeg)) * (float(tryi) - 1.0)
		var cx: float = p.x + cos(a) * float(d.podSpread) * (0.0 if tryi == 0 else 1.0)
		var cy: float = p.y + sin(a) * float(d.podSpread) * (0.0 if tryi == 0 else 1.0)
		var pos := st.nearest_valid_pos(clampf(cx, 20.0, st.arena_w - 20.0), clampf(cy, 20.0, st.arena_h - 20.0), 0.0, 120.0)
		if pos.is_empty():
			continue
		var trial := { "x": float(pos[0]), "y": float(pos[1]), "r": float(d.podR) }
		var live: Array = []
		for old in pods:
			if not bool((old as Dictionary).done):
				live.append(old)
		live.append(trial)
		if _exits_open(st, live, float(d.probe)) < int(d.minExits): # 전장을 통째로 막지 않는다
			continue
		trial["order"] = idx + 1
		trial["land_at"] = st.t + warn
		trial["warn"] = warn
		trial["done"] = false
		pods.append(trial)
		return

## 역병 가로막기의 띠: **관측한 이동 방향 앞쪽**에 그 방향과 직각으로 늘어선 포자 줄.
## 놓은 뒤에도 탈출 방향이 minExits개 이상 남을 때까지 **플레이어에게 가장 가까운 칸부터** 지운다.
## 폭발은 한쪽 끝(order 1)부터 wallGap 간격이므로 늦게 터지는 쪽으로 빠져나갈 수 있다
static func _place_wall(st: CombatState, e: Dictionary) -> Array:
	var p := st.target_of(e)
	var lead := obs_lead(st, e, p, dv(e, "wallLead", 0.85), dv(e, "wallLeadMax", 150.0))
	var dirx: float = float(lead[0]) - float(p.x)
	var diry: float = float(lead[1]) - float(p.y)
	if sqrt(dirx * dirx + diry * diry) < 1e-3: # 서 있으면 조율사 → 플레이어 방향 너머에 세운다
		var a0: float = atan2(p.y - e.y, p.x - e.x)
		dirx = cos(a0) * dv(e, "wallLeadMax", 150.0) * 0.6
		diry = sin(a0) * dv(e, "wallLeadMax", 150.0) * 0.6
	var ang: float = atan2(diry, dirx)
	var cx: float = float(p.x) + dirx
	var cy: float = float(p.y) + diry
	var n: int = int(dv(e, "wallCount", 5.0))
	var step: float = dv(e, "wallStep", 74.0)
	var rr: float = dv(e, "wallR", 46.0)
	var gap: float = dv(e, "wallGap", 0.18)
	var warn: float = dv(e, "wallAim", 0.7)
	var out: Array = []
	for i in n:
		var off: float = (float(i) - float(n - 1) / 2.0) * step
		var wx: float = cx + cos(ang + PI / 2.0) * off
		var wy: float = cy + sin(ang + PI / 2.0) * off
		var pos := st.nearest_valid_pos(clampf(wx, 20.0, st.arena_w - 20.0), clampf(wy, 20.0, st.arena_h - 20.0), 0.0, 90.0)
		if pos.is_empty():
			continue
		out.append({ "x": float(pos[0]), "y": float(pos[1]), "r": rr, "order": out.size() + 1,
			"land_at": st.t + warn + float(out.size()) * gap, "warn": warn, "done": false })
	while out.size() > 2 and _exits_open(st, out, dv(e, "probe", 90.0)) < int(dv(e, "minExits", 6.0)):
		var near_i := 0
		var near_d := 1e9
		for i in out.size():
			var w: Dictionary = out[i]
			var dd := PGeom.dist(float(w.x), float(w.y), p.x, p.y)
			if dd < near_d:
				near_d = dd
				near_i = i
		out.remove_at(near_i)
		for i in out.size():
			var w2: Dictionary = out[i]
			w2.order = i + 1
			w2.land_at = st.t + warn + float(i) * gap
	return out

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
			# §11-B ① 닻 도약(멀리 떨어져 있어도 스스로 붙는다 — 사슬을 맞히지 않아도 접근이 성립)
			#        ② 사슬 끌어쓸기(걷는 앞에 추를 던지고 옆으로 쓸어 당긴다 — 직선 사슬과 다른 범위)
			var far_ok: bool = dist > float(d.nearDist) + float(e.r)
			if try_new_pattern(st, e, dt, { "anchor": far_ok and dist <= dv(e, "anchorRange", 420.0), "drag": far_ok and dist <= dv(e, "dragRange", 300.0) }):
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
			# §12: 발사 속도는 data/pacing.json에서 겹쳐 읽는다(dv). 예고 시간(chainAim·chainLock)과 **분리된 값**이다
			e.chain_d = minf(float(e.chain_len), d0 + dv(e, "chainSpeed", 620.0) * adv)
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
		# ---- §11-B ① 닻 도약: 지면에 사슬을 박고 **자신을 당겨** 착지 강타 ----
		## **플레이어에게 사슬을 맞히지 않아도 접근이 성립한다** — 걸어서 거리를 벌리는 놀이를 흔드는 쪽이다.
		## 착지 원은 anchor_aim 동안만 따라오고 anchor_lock(0.15)에 자리가 굳는다. 확정 뒤에는 쫓아오지 않으므로
		## 원 밖으로 걸어 나오면 빗나가고, 착지 뒤에는 1.2초 빈틈이 남는다
		"anchor_aim":
			e.state_t += adv
			# 착지 자리는 **관측한 이동**(0.30초 지연)으로 내다본 앞이다 — 걸어서 벌리는 놀이를 흔들려면
			# 지금 서 있는 자리에 내려앉아서는 안 된다. 확정(anchor_lock) 뒤에는 이 계산을 더 하지 않는다
			var al := obs_lead(st, e, p, dv(e, "anchorLock", 0.15) + dv(e, "anchorFly", 0.3), dv(e, "anchorLeadMax", 130.0))
			var an: float = atan2(float(al[1]) - e.y, float(al[0]) - e.x)
			var agap: float = dv(e, "anchorGap", 40.0)
			var apos := st.nearest_valid_pos(float(al[0]) - cos(an) * agap, float(al[1]) - sin(an) * agap, float(e.r), 160.0)
			e.slam_at = apos if not apos.is_empty() else [float(al[0]) - cos(an) * agap, float(al[1]) - sin(an) * agap]
			if float(e.state_t) >= dv(e, "anchorAim", 0.55):
				e.state = "anchor_lock"
				e.state_t = 0.0
				st.ev("lock")
		"anchor_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "anchorLock", 0.15):
				e.state = "anchor_fly"
				e.state_t = 0.0
				e.pull_from = [e.x, e.y]
				e.airborne = true
				st.note_attack(e, "execute")
		"anchor_fly": # 사슬을 당겨 자기 몸을 옮긴다(이 구간에는 접촉 피해가 없다)
			e.state_t += adv
			var aat: Array = e.slam_at
			var afr: Array = e.pull_from
			var ak: float = clampf(float(e.state_t) / maxf(0.001, dv(e, "anchorFly", 0.3)), 0.0, 1.0)
			e.x = float(afr[0]) + (float(aat[0]) - float(afr[0])) * ak
			e.y = float(afr[1]) + (float(aat[1]) - float(afr[1])) * ak
			if ak >= 1.0:
				e.airborne = false
				circle_hit(st, e, e.x, e.y, dv(e, "anchorR", 88.0), dv(e, "anchorDamage", 20.0), "elite_chain_anchor")
				e.erase("slam_at")
				to_recover(st, e, dv(e, "anchorRecover", 1.2))
		# ---- §11-B ② 사슬 끌어쓸기: 진행 방향 **앞**에 추를 던진 뒤 **옆으로 쓸어** 당기기 ----
		## 기존 직선 사슬과 범위가 다르다: 추가 던져진 자리에서 집행자 쪽으로 **호를 그리며** 감겨 온다.
		## 던질 자리는 관측한 이동(0.30초 지연)으로 정하고 drag_lock에 굳는다 — 예고를 보고 꺾으면 엉뚱한 앞을 막는다.
		## 쓸기는 한 번만 판정하고(맞아도 연속으로 갈리지 않는다) 끝나면 1.1초 빈틈
		"drag_aim":
			e.state_t += adv
			var dl := obs_lead(st, e, p, dv(e, "dragLead", 0.7), dv(e, "dragLeadMax", 130.0))
			e.drag_at = [float(dl[0]), float(dl[1])]
			if float(e.state_t) >= dv(e, "dragAim", 0.5):
				e.state = "drag_lock"
				e.state_t = 0.0
				st.ev("lock")
		"drag_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "dragLock", 0.15):
				# 추가 도는 **반지름은 지금 플레이어까지의 거리**, **각은 걷는 앞 방향**이다.
				# (앞 지점까지의 거리로 반지름을 잡으면 추가 플레이어보다 늘 바깥으로 돌아 무엇을 해도 스치기만 한다 — 첫 시험값의 결함)
				var dat: Array = e.drag_at
				e.drag_r = maxf(40.0, PGeom.dist(e.x, e.y, p.x, p.y))
				e.drag_a0 = atan2(float(dat[1]) - e.y, float(dat[0]) - e.x)
				e.drag_at = [e.x + cos(float(e.drag_a0)) * float(e.drag_r), e.y + sin(float(e.drag_a0)) * float(e.drag_r)]
				e.drag_side = 1.0 if int(e.id) % 2 == 0 else -1.0 # 난수를 쓰지 않는다(난수 소비 순서를 건드리면 기준 전투가 흔들린다)
				e.hit_done = false
				e.state = "drag_toss"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"drag_toss": # 추가 던져진 자리에 닿을 때까지(판정 없음 — 무엇이 올지 읽는 시간)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "dragToss", 0.2):
				e.state = "drag_sweep"
				e.state_t = 0.0
				st.ev("boss_sweep")
		"drag_sweep": # 추가 호를 그리며 감겨 온다. 지나간 자리에 한 번만 판정
			e.state_t += adv
			var dk: float = clampf(float(e.state_t) / maxf(0.001, dv(e, "dragSweep", 0.45)), 0.0, 1.0)
			var da: float = float(e.drag_a0) + PGeom.deg(dv(e, "dragArcDeg", 150.0)) * float(e.drag_side) * dk
			var drr: float = float(e.drag_r) * (1.0 - dv(e, "dragPull", 0.15) * dk) # 거의 같은 반지름으로 쓴다 — 안팎으로 움직이면 벗어난다
			var wx: float = e.x + cos(da) * drr
			var wy: float = e.y + sin(da) * drr
			e.drag_now = [wx, wy]
			if not bool(e.get("hit_done", false)) and PGeom.dist(wx, wy, p.x, p.y) <= dv(e, "dragR", 34.0) + float(p.r):
				e.hit_done = true
				st.damage_player(dv(e, "dragDamage", 16.0), "elite_chain_drag", e)
			if dk >= 1.0:
				e.erase("drag_now")
				to_recover(st, e, dv(e, "dragRecover", 1.1))
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
			# §11-B ① 깃발 돌격(멀 때 겨누고 접근해 찌르기 → 횡베기) ② 양면 협공(부하와 시간차. 부하가 없으면 본체 대체 연계)
			if try_new_pattern(st, e, dt, { "rush": dist > float(d.slashRange) + float(e.r) and dist <= dv(e, "rushRange", 400.0), "pincer": dist <= dv(e, "pincerRange", 320.0) }):
				if String(e.state) == "pincer_aim":
					_pincer_pick(st, e)
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
		# ---- §11-B ① 깃발 돌격: 겨누고 접근해 찌르기 → 횡베기 ----
		## 원거리에서 시작해 **스스로 붙는다**. 방향은 rush_lock(0.12)에 굳고 전진 중에는 회전하지 않으므로
		## 옆으로 꺾으면 돌격 자체가 빗나간다. 붙은 뒤에도 찌르기(0.28)와 횡베기(0.30)의 예고가 따로 있고
		## 찌르기는 좁고(46°) 횡베기는 넓다(170°) — 무엇을 피할지 두 번 고를 수 있다. 끝나면 1.2초 빈틈
		"rush_aim":
			var rtof: float = dv(e, "rushLock", 0.12) + dv(e, "rushDist", 380.0) / maxf(1.0, dv(e, "rushSpeed", 480.0))
			var rlead := obs_lead(st, e, p, rtof, dv(e, "rushLeadMax", 170.0))
			e.aim_angle = atan2(float(rlead[1]) - e.y, float(rlead[0]) - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "rushAim", 0.5):
				e.state = "rush_lock"
				e.state_t = 0.0
				e.dir = e.aim_angle
				e.charge_dist = 0.0
				st.ev("lock")
		"rush_lock":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "rushLock", 0.12):
				e.state = "rush"
				e.state_t = 0.0
				st.note_attack(e, "execute")
		"rush": # 확정 방향으로 전진(접촉 피해 없음 — 이동은 공격이 아니다)
			e.state_t += adv
			var rstp: float = dv(e, "rushSpeed", 300.0) * sm * dt
			var rx0: float = e.x
			var ry0: float = e.y
			var rmv := st.move_swept(e, cos(float(e.dir)) * rstp, sin(float(e.dir)) * rstp, true)
			e.charge_dist = float(e.get("charge_dist", 0.0)) + PGeom.dist(e.x, e.y, rx0, ry0)
			if float(e.charge_dist) >= dv(e, "rushDist", 220.0) or String(rmv.hit) != "" or dist <= dv(e, "thrustRange", 84.0) + float(e.r):
				elite_begin(st, e, "thrust_aim", "찌르기", "#ffb0b0")
		"thrust_aim": # 좁은 찌르기
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "thrustAim", 0.28):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), dv(e, "thrustRange", 84.0) + float(e.r), PGeom.deg(dv(e, "thrustDeg", 46.0)) / 2.0, dv(e, "thrustDamage", 17.0), "elite_standard_thrust")
				elite_begin(st, e, "cross_aim", "횡베기", "#ff9f43")
		"cross_aim": # 넓은 횡베기
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "crossAim", 0.3):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), dv(e, "crossRange", 78.0) + float(e.r), PGeom.deg(dv(e, "crossDeg", 170.0)) / 2.0, dv(e, "crossDamage", 15.0), "elite_standard_cross")
				st.ev("boss_sweep")
				to_recover(st, e, dv(e, "rushRecover", 1.2))
		# ---- §11-B ② 양면 협공: 부하와 본체가 **다른 방향에서 시간차** ----
		## 부하는 새로 부르지 않는다 — 이미 싸우고 있는 적 하나의 **이동만** 반대편으로 돌린다(경험치·금화 예산 불변).
		## 부하가 없으면 본체 혼자 각을 바꿔 두 번 베는 **대체 연계**로 간다(_pincer_pick가 그때 solo_aim1로 보낸다).
		## 두 방향이 동시에 닫히지 않도록 본체 쪽은 0.5초 늦게 들어오고, 각 베기에는 따로 예고가 있다
		"pincer_aim":
			e.state_t += adv
			if float(e.state_t) >= dv(e, "pincerAim", 0.6):
				if bool(e.get("pincer_solo", true)): # 부하가 없으면 **본체 대체 연계**
					e.state = "solo_aim1"
					e.state_t = 0.0
				else:
					e.state = "pincer_move"
					e.state_t = 0.0
					st.text(e.x, e.y - float(e.r) - 26.0, "반대편으로", "#e0c060")
		"pincer_move": # 부하의 반대쪽으로 돌아 들어간다(이 구간에는 공격 판정이 없다)
			e.state_t += adv
			var pang: float = float(e.get("pincer_ang", atan2(e.y - p.y, e.x - p.x)))
			st.approach(e, p.x + cos(pang) * (dv(e, "thrustRange", 84.0) * 0.7), p.y + sin(pang) * (dv(e, "thrustRange", 84.0) * 0.7), dv(e, "pincerMoveSpeed", 200.0) * sm, dt)
			if float(e.state_t) >= dv(e, "pincerMove", 0.5):
				elite_begin(st, e, "pincer_slash_aim", "협공 베기", "#e0c060")
		"pincer_slash_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "pincerSlashAim", 0.32):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), float(d.slashRange) + float(e.r), PGeom.deg(float(d.slashDeg)) / 2.0, dv(e, "pincerDamage", 16.0), "elite_standard_pincer")
				to_recover(st, e, dv(e, "pincerRecover", 1.2))
		"solo_aim1": # 부하가 없을 때의 **본체 대체 연계** 1/2
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "soloAim1", 0.35):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), float(d.slashRange) + float(e.r), PGeom.deg(float(d.slashDeg)) / 2.0, dv(e, "pincerDamage", 16.0), "elite_standard_solo")
				e.state = "solo_gap"
				e.state_t = 0.0
				st.text(e.x, e.y - float(e.r) - 30.0, "각을 바꾼다", "#e0c060")
		"solo_gap": # 옆으로 돌아 **다른 각**을 만든다(판정 없음 — 되받아칠 틈)
			e.state_t += adv
			strafe(st, e, dv(e, "soloGapSpeed", 190.0) * sm, dt)
			if float(e.state_t) >= dv(e, "soloGap", 0.45):
				elite_begin(st, e, "solo_aim2", "반대쪽에서 2/2", "#e0c060")
		"solo_aim2":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "soloAim2", 0.3):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), float(d.slashRange) + float(e.r), PGeom.deg(float(d.slashDeg)) / 2.0, dv(e, "pincerDamage", 16.0), "elite_standard_solo")
				to_recover(st, e, dv(e, "pincerRecover", 1.2))
		"recover":
			_recover_tick(e, adv)

## 양면 협공의 부하 고르기. **적을 새로 부르지 않는다** — 이미 싸우고 있는 적 하나의 이동만 반대편으로 돌린다.
## 쓸 만한 부하가 없으면 본체 혼자 각을 바꿔 두 번 베는 **대체 연계**(solo_aim1)로 보낸다.
static func _pincer_pick(st: CombatState, e: Dictionary) -> void:
	var p := st.target_of(e)
	var best: Dictionary = {}
	var best_d := 1e9
	for o in st.enemies:
		if o == e or bool(o.dead) or bool(o.get("boss", false)) or bool(o.get("structure", false)) or bool(o.get("hidden", false)):
			continue
		var dd := PGeom.dist(o.x, o.y, p.x, p.y)
		if dd > dv(e, "pincerRadius", 260.0) or dd >= best_d:
			continue
		best_d = dd
		best = o
	if best.is_empty():
		e.pincer_solo = true # 부하 없음 — 예고가 끝나면 본체 대체 연계로 간다(예고 상태는 같다)
		e.erase("pincer_ally")
		st.text(e.x, e.y - float(e.r) - 30.0, "혼자서 두 번", "#e0c060")
		return
	e.pincer_solo = false
	var ally: Dictionary = best
	ally.rally_t = dv(e, "pincerOrderDur", 2.4) # 이동만 바꾼다(공격 시작은 그 적의 규칙과 동시 위험 상한이 그대로 정한다)
	ally.leash_boost = dv(e, "pincerOrderSpeed", 1.5)
	st.text(ally.x, ally.y - float(ally.r) - 26.0, "협공", "#e0c060")
	e.pincer_ang = atan2(p.y - float(ally.y), p.x - float(ally.x)) # 부하의 **반대편**이 본체 자리다
	e.pincer_ally = ally
	st.ev("group")

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
			# §11-B ① 지상 추격 강타(**몸을 드러낸 채** 달려온다 — 잠복·출현과 구분된다) ② 쐐기 균열(앞쪽 두 갈래)
			if try_new_pattern(st, e, dt, { "surface": dist > float(d.biteRange) + float(e.r) and dist <= dv(e, "surfaceRange", 400.0), "rift": dist <= dv(e, "riftRange", 340.0) }):
				return
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
		# ---- §11-B ① 지상 추격 강타: **몸을 드러내고** 달려와 곡괭이 ----
		## 기존 잠복·출현과 구분된다: hidden이 되지 않으므로 달리는 내내 때릴 수 있고(지하 면역이 없다),
		## 원거리에서 걷기만 하는 놀이에 대해 **거리를 스스로 좁힌다**. 곡괭이는 예고 0.40이 따로 있고 끝나면 1.2초 빈틈
		"surface_run":
			e.state_t += adv
			e.hidden = false
			st.approach(e, p.x, p.y, dv(e, "surfaceSpeed", 215.0) * sm, dt)
			if dist <= dv(e, "pickRange", 66.0) + float(e.r) or float(e.state_t) >= dv(e, "surfaceRun", 1.4):
				elite_begin(st, e, "pick_aim", "곡괭이", "#ffb0b0")
		"pick_aim": # 예고 동안에도 다가선다(멈추면 걷기만으로 벗어난다). 각은 예고 내내 따라오고 실행 순간 굳는다
			st.approach(e, p.x, p.y, dv(e, "surfaceSpeed", 330.0) * dv(e, "pickLungeMult", 0.5) * sm, dt)
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "pickAim", 0.4):
				e.dir = e.aim_angle
				arc_strike(st, e, float(e.dir), dv(e, "pickRange", 66.0) + float(e.r), PGeom.deg(dv(e, "pickDeg", 90.0)) / 2.0, dv(e, "pickDamage", 18.0), "elite_pick_run")
				to_recover(st, e, dv(e, "surfaceRecover", 1.2))
		# ---- §11-B ② 쐐기 균열: 앞쪽에서 **두 갈래** 균열 ----
		## 두 갈래 **사이**가 비어 있고(각 갈래 ±26°) 바깥으로 꺾어도 벗어난다 — 두 가지 답이 있다.
		## 예고(0.65) 동안에는 갈래가 따라오지만 실행 순간 각이 굳고 그 뒤로는 움직이지 않는다
		"rift_aim":
			e.aim_angle = atan2(p.y - e.y, p.x - e.x)
			e.state_t += adv
			if float(e.state_t) >= dv(e, "riftAim", 0.65):
				e.dir = e.aim_angle
				e.state = "rift"
				e.state_t = 0.0
				st.note_attack(e, "execute")
				st.ev("boss_land")
				var rl: float = dv(e, "riftLen", 260.0)
				var rw: float = dv(e, "riftW", 46.0)
				for s in [1.0, -1.0]:
					var ra: float = float(e.dir) + PGeom.deg(dv(e, "riftDeg", 26.0)) * float(s)
					var seg: float = st.beam_length(e.x, e.y, ra, rl)
					st.fx({ "kind": "burst", "x": e.x + cos(ra) * seg * 0.5, "y": e.y + sin(ra) * seg * 0.5, "r": rw * 0.5, "ttl": 0.3, "color": "#c8a06a" })
					if PGeom.in_beam(e.x, e.y, ra, seg, rw, p.x, p.y, float(p.r)):
						st.damage_player(dv(e, "riftDamage", 17.0), "elite_rift", e)
		"rift": # 균열이 벌어진 채 잠깐 남는다(표시). 판정은 이미 끝났다
			e.state_t += adv
			if float(e.state_t) >= dv(e, "riftHold", 0.25):
				to_recover(st, e, dv(e, "riftRecover", 1.3))
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
			elif state == "chase_aim" or state == "chase_lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir) if state == "chase_lock" else float(e.aim_angle), "len": 2000.0, "w": 40.0,
					"prog": _prog(e, "chaseAim") if state == "chase_aim" else 1.0, "locked": state == "chase_lock" })
			elif state == "snipe1_aim" or state == "snipe1_lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir) if state == "snipe1_lock" else float(e.aim_angle), "len": 2000.0, "w": 40.0,
					"prog": _prog(e, "snipe1Aim") if state == "snipe1_aim" else 1.0, "locked": state == "snipe1_lock" })
			elif state == "snipe2_aim" or state == "snipe2_lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir) if state == "snipe2_lock" else float(e.aim_angle), "len": 2000.0, "w": 56.0,
					"prog": _prog(e, "snipe2Aim") if state == "snipe2_aim" else 1.0, "locked": state == "snipe2_lock" })
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
			elif state == "step1_aim" or state == "step2_aim" or state == "step3_aim":
				var sk: String = "stepAim" + state.substr(4, 1)
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.aim_angle), "len": dv(e, "stepDist", 78.0) + float(p.r) + 20.0, "w": w, "prog": _prog(e, sk), "locked": false })
			elif state == "step1" or state == "step2" or state == "step3":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir), "len": maxf(0.0, float(e.get("charge_len", 0.0)) - float(e.get("charge_dist", 0.0))) + 20.0, "w": w, "prog": 1.0, "locked": true })
			elif state == "wave_aim" or state == "wave_lock":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.dir) if state == "wave_lock" else float(e.aim_angle),
					"len": 900.0, "w": dv(e, "waveR", 22.0) * 2.0, "prog": _prog(e, "waveAim") if state == "wave_aim" else 1.0, "locked": state == "wave_lock" })
		"elite_fang":
			if state == "bite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.biteAim), "locked": float(e.state_t) / float(d.biteAim) > 0.6 })
			elif (state == "leap_aim" or state == "leap_lock" or state == "leap") and e.has("leap_at"):
				var at: Array = e.leap_at
				out.append({ "kind": "circle", "e": e, "x": float(at[0]), "y": float(at[1]), "r": float(d.leapR), "prog": (float(e.state_t) / float(d.leapAim)) if state == "leap_aim" else 1.0, "locked": state != "leap_aim" })
			elif state == "runbite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "runbiteRange", float(d.biteRange)) + e.r + 10.0, "half": PGeom.deg(dv(e, "runbiteDeg", 60.0)) / 2.0 + 0.2, "prog": _prog(e, "runbiteAim"), "locked": _prog(e, "runbiteAim") > 0.6 })
			elif (state == "cut_aim" or state == "cut_lock" or state == "cut_leap") and e.has("leap_at"):
				var cat: Array = e.leap_at
				out.append({ "kind": "circle", "e": e, "x": float(cat[0]), "y": float(cat[1]), "r": dv(e, "cutLandR", 62.0), "prog": _prog(e, "cutAim") if state == "cut_aim" else 1.0, "locked": state != "cut_aim" })
			elif state == "cut_claw_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "cutClawRange", 62.0) + e.r + 10.0, "half": PGeom.deg(dv(e, "cutClawDeg", 100.0)) / 2.0 + 0.2, "prog": _prog(e, "cutClawAim"), "locked": _prog(e, "cutClawAim") > 0.6 })
		"elite_plaguecaller":
			if state == "burst_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.burstRange) + e.r + 10.0, "half": PGeom.deg(float(d.burstDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.burstAim), "locked": float(e.state_t) / float(d.burstAim) > 0.6 })
			elif state == "swell":
				for pod in e.get("pods", []):
					if bool(pod.done):
						continue
					var left: float = maxf(0.0, float(pod.land_at) - st.t)
					out.append({ "kind": "circle", "e": e, "x": float(pod.x), "y": float(pod.y), "r": float(pod.r), "prog": 1.0 - left / maxf(0.001, float(pod.get("warn", d.swell))), "locked": true, "order": int(pod.order) })
			elif (state == "seek_fly" or state == "seek_swell") and e.has("seek"):
				var sk: Dictionary = e.seek
				out.append({ "kind": "circle", "e": e, "x": float(sk.x), "y": float(sk.y), "r": dv(e, "seekR", 80.0),
					"prog": _prog(e, "seekSwell") if state == "seek_swell" else 0.3, "locked": state == "seek_swell" })
			elif state == "wall_aim" or state == "wall_burst":
				for wp in e.get("wall", []):
					var wpd: Dictionary = wp
					if bool(wpd.done):
						continue
					var wleft: float = maxf(0.0, float(wpd.land_at) - st.t)
					out.append({ "kind": "circle", "e": e, "x": float(wpd.x), "y": float(wpd.y), "r": float(wpd.r),
						"prog": clampf(1.0 - wleft / maxf(0.001, float(wpd.warn)), 0.0, 1.0), "locked": true, "order": int(wpd.order) })
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
			elif (state == "anchor_aim" or state == "anchor_lock" or state == "anchor_fly") and e.has("slam_at"):
				var aat: Array = e.slam_at
				out.append({ "kind": "circle", "e": e, "x": float(aat[0]), "y": float(aat[1]), "r": dv(e, "anchorR", 88.0), "prog": _prog(e, "anchorAim") if state == "anchor_aim" else 1.0, "locked": state != "anchor_aim" })
			elif (state == "drag_aim" or state == "drag_lock" or state == "drag_toss") and e.has("drag_at"):
				var dat: Array = e.drag_at
				out.append({ "kind": "circle", "e": e, "x": float(dat[0]), "y": float(dat[1]), "r": dv(e, "dragR", 34.0), "prog": _prog(e, "dragAim") if state == "drag_aim" else 1.0, "locked": state != "drag_aim" })
			elif state == "drag_sweep" and e.has("drag_now"):
				var dnw: Array = e.drag_now
				out.append({ "kind": "circle", "e": e, "x": float(dnw[0]), "y": float(dnw[1]), "r": dv(e, "dragR", 34.0), "prog": 1.0, "locked": true })
		"elite_standard":
			if state == "slash_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.slashRange) + e.r + 10.0, "half": PGeom.deg(float(d.slashDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.slashAim), "locked": float(e.state_t) / float(d.slashAim) > 0.6 })
			elif state == "rush_aim" or state == "rush_lock" or state == "rush":
				out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": float(e.aim_angle) if state == "rush_aim" else float(e.dir),
					"len": maxf(60.0, dv(e, "rushDist", 220.0) - float(e.get("charge_dist", 0.0))) + 20.0, "w": w, "prog": _prog(e, "rushAim") if state == "rush_aim" else 1.0, "locked": state != "rush_aim" })
			elif state == "thrust_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "thrustRange", 84.0) + e.r + 10.0, "half": PGeom.deg(dv(e, "thrustDeg", 46.0)) / 2.0 + 0.2, "prog": _prog(e, "thrustAim"), "locked": _prog(e, "thrustAim") > 0.6 })
			elif state == "cross_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "crossRange", 78.0) + e.r + 10.0, "half": PGeom.deg(dv(e, "crossDeg", 170.0)) / 2.0 + 0.2, "prog": _prog(e, "crossAim"), "locked": _prog(e, "crossAim") > 0.6 })
			elif state == "pincer_slash_aim" or state == "solo_aim1" or state == "solo_aim2":
				var pkey: String = "pincerSlashAim" if state == "pincer_slash_aim" else ("soloAim1" if state == "solo_aim1" else "soloAim2")
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.slashRange) + e.r + 10.0, "half": PGeom.deg(float(d.slashDeg)) / 2.0 + 0.2, "prog": _prog(e, pkey), "locked": _prog(e, pkey) > 0.6 })
		"elite_miner":
			if state == "warn" and e.has("emerge_at"):
				var mat: Array = e.emerge_at
				out.append({ "kind": "circle", "e": e, "x": float(mat[0]), "y": float(mat[1]), "r": float(d.eruptR), "prog": float(e.state_t) / float(d.warn), "locked": true })
			elif state == "bite_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": float(d.biteRange) + e.r + 10.0, "half": PGeom.deg(float(d.biteDeg)) / 2.0 + 0.2, "prog": float(e.state_t) / float(d.biteAim), "locked": float(e.state_t) / float(d.biteAim) > 0.6 })
			elif state == "pick_aim":
				out.append({ "kind": "arc", "e": e, "x": e.x, "y": e.y, "ang": e.aim_angle, "r": dv(e, "pickRange", 66.0) + e.r + 10.0, "half": PGeom.deg(dv(e, "pickDeg", 90.0)) / 2.0 + 0.2, "prog": _prog(e, "pickAim"), "locked": _prog(e, "pickAim") > 0.6 })
			elif state == "rift_aim":
				for rs in [1.0, -1.0]:
					var ra2: float = float(e.aim_angle) + PGeom.deg(dv(e, "riftDeg", 26.0)) * float(rs)
					out.append({ "kind": "beam", "e": e, "x": e.x, "y": e.y, "ang": ra2, "len": st.beam_length(e.x, e.y, ra2, dv(e, "riftLen", 260.0)), "w": dv(e, "riftW", 46.0), "prog": _prog(e, "riftAim"), "locked": false })

static func zone_threats(st: CombatState, out: Array) -> void:
	for z in st.zones:
		if z.type == "frostzone":
			out.append({ "kind": "circle", "x": z.x, "y": z.y, "r": z.r, "prog": 1.0 - float(z.ttl) / float(z.max_ttl), "locked": float(z.ttl) < 0.45 })
		elif z.type == "web":
			out.append({ "kind": "zone", "x": z.x, "y": z.y, "r": z.r, "web": true })
