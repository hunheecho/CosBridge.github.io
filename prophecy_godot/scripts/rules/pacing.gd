class_name PPacing
extends RefCounted
## 밸런스 오버레이(data/pacing.json). enemies.json·world.json은 tools/port_export_data.js가 만드는 내보내기 산출물이라
## 손으로 고치지 않고 여기서 덮어쓴다. 규칙 코드는 읽기만 한다.
## 담는 것: 날짜별 총 등장 수 · 막별 동시 상한 · 혼합 분대 등장 · 역할별 고정 체력표 · 보스 체력 · 금화 배율.
## 실행 중 플레이어 DPS를 읽어 적을 맞추지 않는다(고정 표). 승인된 첫날 기준 전투(늑대 25·동시 12)는 어떤 경로에서도 그대로다.

static func D() -> Dictionary: return PCatalog.pacing()

# ---------- 날짜별 총 등장 수(사용자 결정 25 → 75) ----------
static func day_total_cfg() -> Dictionary: return D().get("day_total", {})

## 그 날짜·장소 비용의 일반 전투 총 등장 수. 표가 없으면 0(호출자가 템플릿 값을 그대로 쓴다)
static func day_total(day: int, place_cost: int) -> int:
	var C := day_total_cfg()
	var arr: Array = C.get("by_day", [])
	if arr.is_empty():
		return 0
	var d: int = clampi(day, 1, arr.size())
	var base: float = float(arr[d - 1])
	if place_cost >= 2:
		base *= float(C.get("place_cost2_mult", 1.0))
	return int(round(base))

# ---------- 막별 동시 생존 상한 ----------
static func alive_cap_cfg() -> Dictionary: return D().get("alive_cap", {})

static func alive_cap_set_default() -> String:
	return String(alive_cap_cfg().get("set_default", "acts"))

## 막의 동시 상한. 세트에 값이 없으면 fallback(템플릿 값)을 그대로 쓴다(대조군 legacy)
static func alive_cap(act: int, fallback: int, set_id: String = "") -> int:
	var C := alive_cap_cfg()
	var sid := set_id if set_id != "" else alive_cap_set_default()
	var sets: Dictionary = C.get("sets", {})
	var s: Dictionary = sets.get(sid, {})
	var key := str(act)
	if s.has(key):
		return int(s[key])
	return fallback

# ---------- 혼합 분대 등장 ----------
static func spawn_cfg() -> Dictionary: return D().get("spawn", {})

static func squad_mixing() -> bool:
	return bool(spawn_cfg().get("squad_mixing", false))

## 지원·통제 역할인가(혼합 분대 정렬·호위 판정용). 체력표의 roles를 그대로 쓴다
static func is_support(type: String) -> bool:
	return String(roles().get(type, "")) == "support"

static func is_melee(type: String) -> bool:
	var r := String(roles().get(type, ""))
	return r == "melee_main" or r == "swarm" or r == "armored"

static func support_share_per_group() -> float:
	return float(spawn_cfg().get("support_share_per_group", 1.0))

static func tail_group_mult() -> float:
	return float(spawn_cfg().get("tail_group_mult", 1.0))

# ---------- 장판 상한(죽은 적이 남긴 위험 표시) ----------
static func zone_cfg() -> Dictionary: return D().get("zone_cap", {})

static func max_enemy_zones() -> int:
	return int(zone_cfg().get("max_enemy_zones", 0))

## 적이 만드는 장판 종류인가(플레이어 장판은 상한 대상이 아니다)
static func is_enemy_zone(type: String) -> bool:
	var L: Array = zone_cfg().get("enemy_zone_types", [])
	return L.has(type)

# ---------- 역할별 고정 체력표 ----------
static func hp_cfg() -> Dictionary: return D().get("enemy_hp", {})
static func roles() -> Dictionary: return hp_cfg().get("roles", {})
static func tier_table() -> Dictionary: return hp_cfg().get("tier_table", {})

## 개발 중 기준 빌드의 단일 표적 DPS(act1/act2/act3). 표 도출 근거이며 실행 중에 읽어 쓰지 않는다
static func ref_dps(act: int) -> float:
	return float(hp_cfg().get("ref_dps", {}).get("act%d" % act, 0.0))

static func target_sec(role: String) -> float:
	return float(hp_cfg().get("target_sec", {}).get(role, 0.0))

## 등급별 절대 체력. 표에 없으면 -1(호출자가 기존 값·배율을 쓴다)
static func tier_hp(type: String, tier: String) -> float:
	var T := tier_table()
	if not T.has(type):
		return -1.0
	var row: Dictionary = T[type]
	return float(row[tier]) if row.has(tier) else -1.0

## 정예의 막별 절대 체력(정예는 등급 배정 대상이 아니다). 없으면 -1
static func elite_hp(type: String, act: int) -> float:
	var E: Dictionary = hp_cfg().get("elite_by_act", {})
	if not E.has(type):
		return -1.0
	var row: Dictionary = E[type]
	var key := str(clampi(act, 1, 3))
	return float(row[key]) if row.has(key) else -1.0

## spawn_enemy가 쓰는 최종 체력 배율. 절대표가 있으면 기본 체력 대비 배율로 바꿔 돌려준다(코드 경로는 그대로).
## act는 정예용(등급 대신 막으로 오른다). 표가 없으면 세계 변화 등급 배율(fallback)을 그대로 쓴다.
static func hp_mult_for(type: String, tier: String, base_hp: float, act: int, fallback: float) -> float:
	if base_hp <= 0.0:
		return fallback
	var el := elite_hp(type, act)
	if el > 0.0:
		return el / base_hp
	var abs_hp := tier_hp(type, tier)
	if abs_hp > 0.0:
		return maxf(abs_hp, tier_hp(type, "normal")) / base_hp # 등급 역전 방지: 상위 등급이 일반보다 약해지지 않는다
	return fallback

# ---------- 보스 체력 ----------
## 보스 체력 오버레이. 없으면 -1(enemies.json·bosses_new.json의 기존 세트를 쓴다)
static func boss_hp(set_id: String, boss_id: String, hp_key: String) -> float:
	var S: Dictionary = D().get("boss_hp", {}).get("sets", {})
	var sid := set_id if S.has(set_id) else "base"
	var one: Dictionary = S.get(sid, {})
	if not one.has(boss_id):
		return -1.0
	var row: Dictionary = one[boss_id]
	if row.has(hp_key):
		return float(row[hp_key])
	return -1.0

# ---------- 표시 이름·짧은 효과 문구(내보내기 산출물 덮어쓰기) ----------
static func display_cfg() -> Dictionary: return D().get("display", {})

static func enemy_name(type: String, fallback: String) -> String:
	return String(display_cfg().get("enemy_names", {}).get(type, fallback))

## 제단 같은 구조물의 짧은 효과 한 줄(없으면 "")
static func enemy_short(type: String) -> String:
	return String(display_cfg().get("enemy_short", {}).get(type, ""))

# ---------- 사건: 무료 이득만 있는 선택의 '지나치기' 제거 ----------
static func event_no_skip(id: String) -> bool:
	var L: Array = D().get("events", {}).get("no_skip", [])
	return L.has(id)

# ---------- 반복 탐험(남는 시간) ----------
static func repeat_cfg() -> Dictionary: return D().get("repeat_sortie", {})
static func repeat_enabled() -> bool: return bool(repeat_cfg().get("enabled", false))
static func repeat_cost() -> int: return int(repeat_cfg().get("time_cost", 1))
static func repeat_label() -> String: return String(repeat_cfg().get("label", "일반 탐험"))

# ---------- 금화 ----------
static func gold_cfg() -> Dictionary: return D().get("gold", {})

## 새로 지급하는 금화에만 곱한다(판매금·환불·잔액 제외). 최종 지급 지점에서 정확히 1회
static func gold_mult() -> float:
	return float(gold_cfg().get("mult", 1.0))

static func gold_award(amount: int) -> int:
	if amount <= 0:
		return amount
	return int(round(float(amount) * gold_mult()))
