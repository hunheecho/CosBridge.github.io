class_name PSupport
extends RefCounted
## 보조무기 공통 규칙(2026-09-08 주무기·보조 분리).
##
## 여기 있는 것:
##  1. **효과별 발동 자격표 한 곳**(사용자 지시 5절). data/supports.json eligibility를 그대로 읽는다.
##     감전 추가 피해·독 전염·분신 모방·가시 반격·까마귀 표적이 서로 재귀적으로 증식하지 않게 하는 유일한 관문이다.
##  2. **제압 저항**(둔화·밀어내기·경직·유인). 정예·보스가 영구히 행동하지 못하는 조합을 막는다.
##  3. 새 보조 7종의 발사·갱신 진입점. 구현 전에는 아무 일도 하지 않는다(impl:false라 후보로도 안 나온다).
##
## 수치는 전부 data/supports.json에 있고 전부 시험값이다. 여기 숫자를 적지 않는다.

# ---------- 1. 효과별 발동 자격 ----------
## effect가 cause 경로에서 발동할 수 있는가.
## allow에 "*"가 있으면 deny만 본다. allow 목록이 있으면 그 안에 있어야 하고, deny에 있으면 무조건 막힌다.
## 표에 없는 효과는 **막지 않는다**(모르는 효과를 조용히 꺼 버리면 원인을 못 찾는다).
static func eligible(effect: String, cause: String) -> bool:
	var E: Dictionary = PCatalog.eligibility().get("effects", {})
	if not E.has(effect):
		return true
	var d: Dictionary = E[effect]
	var deny: Array = d.get("deny", [])
	if deny.has(cause):
		return false
	var allow: Array = d.get("allow", [])
	if allow.is_empty() or allow.has("*"):
		return true
	return allow.has(cause)

## 전염·모방처럼 세대가 있는 효과의 상한. 없으면 -1(제한 없음)
static func gen_max(effect: String) -> int:
	var E: Dictionary = PCatalog.eligibility().get("effects", {})
	if not E.has(effect):
		return -1
	return int((E[effect] as Dictionary).get("gen_max", -1))

## 지금 피해가 어느 경로에서 왔는지(st.attack_cause + 옵션)를 자격표의 어휘로 바꾼다.
## 규칙 코드는 이 함수만 쓰고 st.attack_cause 문자열을 직접 비교하지 않는다.
static func cause_of(st: CombatState, opt: Dictionary = {}) -> String:
	if opt.has("cause"):
		return String(opt.cause)
	var c := String(st.attack_cause)
	match c:
		"", "base":
			# 주무기의 기본 타격인지 보조의 타격인지는 무기 역할로 가른다
			var wid := String(opt.get("weapon", ""))
			if wid != "" and not PCatalog.is_main_weapon(wid):
				return "support_direct"
			return "main_direct"
		"echo": return "main_extra"     # 공용 '메아리'가 만든 주무기 추가 타격
		"volley": return "main_extra"
		"orbit", "mine": return "support_direct"
		"zone": return "zone_tick"
		"dot": return "dot"
	return c

# ---------- 2. 제압 저항 ----------
## 적 등급(일반/정예/보스). 구조물은 일반으로 본다
static func tier_class(e: Dictionary) -> String:
	if bool(e.get("boss", false)):
		return "boss"
	if bool(e.get("elite", false)):
		return "elite"
	return "normal"

## 제압 배율. kind = "knock" | "stagger" | "slow" | "taunt". 1.0이면 그대로, 0이면 안 걸린다
static func resist_mult(kind: String, e: Dictionary) -> float:
	var R: Dictionary = PCatalog.support_resist()
	if not R.has(kind):
		return 1.0
	return float((R[kind] as Dictionary).get(tier_class(e), 1.0))

## 어떤 둔화를 겹쳐도 이 아래로는 못 내려가는 이동 속도 비율. 영구 정지 조합을 막는다
static func slow_floor() -> float:
	return float(PCatalog.support_resist().get("slowFloor", 0.35))

## 이미 걸린 둔화 비율 cur(1.0 = 정상)에 새 둔화 add(0~1, 깎을 비율)를 겹친다.
## 곱으로 겹치되 등급 저항을 적용하고 최저 속도로 자른다
static func stack_slow(cur: float, add: float, e: Dictionary) -> float:
	var eff := clampf(add, 0.0, 1.0) * resist_mult("slow", e)
	return maxf(slow_floor(), cur * (1.0 - eff))

## 밀어내기 거리에 등급 저항을 적용한다. 보스는 0(강제 위치 이동 없음)
static func knock_dist(base: float, e: Dictionary) -> float:
	return base * resist_mult("knock", e)

## 이 적을 인형·도발로 끌 수 있는가(등급 저항을 확률이 아니라 자격으로 쓴다: 보스는 0이라 절대 안 끌린다)
static func tauntable(e: Dictionary) -> bool:
	return resist_mult("taunt", e) > 0.0

# ---------- 3. 보조무기 진입점 ----------
## 이 회차에 이 보조를 달고 있는가(전투 상태 기준)
static func equipped(st: CombatState, id: String) -> bool:
	for w in st.weapons:
		if String(w.id) == id:
			return true
	return false

## 장착한 보조의 파생 수치. 없으면 {}
static func stats_of(st: CombatState, id: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == id:
			return w.stats
	return {}

## 그 보조가 개조 mid를 갖고 있는가
static func has_mod(st: CombatState, id: String, mid: String) -> bool:
	for w in st.weapons:
		if String(w.id) == id:
			return (w.stats.mods as Array).has(mid)
	return false

## 새 보조 7종의 발사. PWeapons._fire_by_kind가 모르는 kind를 여기로 넘긴다.
## 처리했으면 true. 아직 구현하지 않은 보조는 false를 돌려주고 아무 일도 하지 않는다
## (impl:false라 성장 후보로 나오지 않으므로 정상 플레이에서는 여기까지 오지 않는다).
## A조(까마귀·방울·분신·바람)는 PSupportA, B조(역병·갑각·인형)는 PSupportB가 맡는다.
## 담당을 파일로 갈라 두어 동시에 만들어도 서로의 코드를 건드리지 않는다.
static func fire(st: CombatState, w: Dictionary, target: Dictionary, echoed: bool) -> bool:
	var kind := String(w.stats.kind)
	if PSupportA.handles(kind):
		return PSupportA.fire(st, w, target, echoed)
	if PSupportB.handles(kind):
		return PSupportB.fire(st, w, target, echoed)
	return false

## 매 프레임 갱신(까마귀 비행·방울 충전·인형 수명 등). 구현 전에는 아무 일도 하지 않는다
static func update(st: CombatState, dt: float) -> void:
	PSupportA.update(st, dt)
	PSupportB.update(st, dt)

## 전투 시작 시 보조별 상태 초기화. st.support에 보조 id별 dict를 둔다
static func init_state(st: CombatState) -> void:
	st.support = {}

# ---------- 4. 전투 훅(CombatState·PWeapons가 부른다) ----------
## 플레이어가 맞기 직전. 경감·차단을 적용한 피해를 돌려준다. 0을 돌려주면 완전히 막힌 것이다.
## 순서: 등급 배율 → **여기**(수호 방울 차단 → 가시 갑각 근접 경감) → 강인함 → 장비 → 흡수 방패 → 체력.
## 구현 전에는 그대로 돌려준다.
## 차단(방울)이 경감(갑각)보다 먼저다. 0이 되면 완전히 막힌 것이라 뒤 계산을 하지 않는다
static func on_player_damage(st: CombatState, amount: float, src: String, attacker) -> float:
	var v := PSupportA.on_player_damage(st, amount, src, attacker)
	if v <= 0.0:
		return 0.0
	return PSupportB.on_player_damage(st, v, src, attacker)

## 플레이어가 맞은 직후(가시 반격 같은 되받아치기). 반격은 PSupport.eligible("thorns_reflect", 경로)를 통과해야 한다
static func after_player_damage(st: CombatState, amount: float, src: String, attacker) -> void:
	PSupportA.after_player_damage(st, amount, src, attacker)
	PSupportB.after_player_damage(st, amount, src, attacker)

## 적이 맞았을 때(까마귀 표적 지정·감전 후속). opt.src에 무기 id와 직접/추가 여부가 있다
static func on_enemy_hit(st: CombatState, e: Dictionary, opt: Dictionary, dmg: float) -> void:
	PSupportA.on_enemy_hit(st, e, opt, dmg)
	PSupportB.on_enemy_hit(st, e, opt, dmg)

## 적이 죽었을 때(독 전염·역병 파열·까마귀 먹잇감 전환)
static func on_enemy_death(st: CombatState, e: Dictionary, opt: Dictionary) -> void:
	PSupportA.on_enemy_death(st, e, opt)
	PSupportB.on_enemy_death(st, e, opt)

## 이 적이 지금 노려야 할 대상(도깨비 인형 유인). {}이면 평소대로 플레이어를 노린다.
## 이미 방향이 확정된 공격·돌진은 이 값으로 바뀌지 않는다 — 부르는 쪽이 확정 전에만 묻는다
static func lure_target(st: CombatState, e: Dictionary) -> Dictionary:
	return PSupportB.lure_target(st, e)

# ---------- 5. 역할 지표 ----------
## 보조무기의 역할별 지표를 쌓는다. 피해만으로는 방울·갑각·인형·서리·바람이 일을 했는지 알 수 없기 때문이다.
## st.metrics.support[보조 id][지표 이름]에 더한다. 규칙에는 영향이 없다(계측 전용).
##
## 표준 지표 이름(대표 조합 측정이 이 이름을 읽는다 — 새로 만들지 말고 여기 있는 것을 써라):
##   fires 발동 · hits 적중 · dmg 준 피해
##   blocked 차단 횟수 · blocked_dmg 막은 피해            (수호 방울)
##   reduced_dmg 경감한 피해 · reflects 반격 · reflect_dmg 반격 피해  (가시 갑각)
##   taunted 유인한 적 · soaked 대신 받은 공격 · soaked_dmg          (도깨비 인형)
##   slows 둔화 적용 · slow_sec 둔화 시간                            (서리 수정·잔바람)
##   push_dist 밀어낸 거리                                           (바람 정령)
##   spreads 전염 · bursts 파열 · dot_dmg 독 피해                    (역병 나비)
##   marks 표적 지정 · mark_keeps 표적 유지 프레임                   (추격 까마귀)
##   copies 모방 발동 · copy_dmg 모방 피해                           (잔영 분신)
##   shock_procs 감전 후속 발동 · shock_dmg                          (번개 구체)
static func meter(st: CombatState, id: String, key: String, amount: float = 1.0) -> void:
	var M: Dictionary = st.metrics.support
	if not M.has(id):
		M[id] = {}
	var d: Dictionary = M[id]
	d[key] = float(d.get(key, 0.0)) + amount

## 쌓인 지표 조회(없으면 0)
static func metered(st: CombatState, id: String, key: String) -> float:
	return float((st.metrics.support.get(id, {}) as Dictionary).get(key, 0.0))
