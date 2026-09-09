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

## 이 이름이 자격표가 아는 경로 어휘인가(data/supports.json eligibility.causes).
## 규칙 코드가 피해 opt에 직접 적어 넣은 cause 중에는 자격표의 어휘가 아닌 것이 섞여 있다
## (지뢰가 opt.cause="mine"을 쓰고 자격표에는 "mine_blast"만 있는 것이 그렇다).
## cause_of는 opt.cause가 있으면 그대로 돌려주므로, **그 값이 어휘 밖이면 무기 id로 다시 물어야** 한다 —
## 그러지 않으면 표에 없는 이름이 되어 eligible()이 "모르는 효과는 막지 않는다" 규칙에 걸려 조용히 통과한다.
static func known_cause(cause: String) -> bool:
	return (PCatalog.eligibility().get("causes", {}) as Dictionary).has(cause)

## 전염·모방처럼 세대가 있는 효과의 상한. 없으면 -1(제한 없음)
static func gen_max(effect: String) -> int:
	var E: Dictionary = PCatalog.eligibility().get("effects", {})
	if not E.has(effect):
		return -1
	return int((E[effect] as Dictionary).get("gen_max", -1))

## 지금 피해가 어느 경로에서 왔는지(st.attack_cause + 옵션)를 자격표의 어휘로 바꾼다.
## 규칙 코드는 이 함수만 쓰고 st.attack_cause 문자열을 직접 비교하지 않는다.
## opt로 넘길 수 있는 것: { cause } 직접 지정 · { weapon } 무기 id · { hit } damage_enemy에 넘어간 피해 opt.
## **hit을 꼭 넘겨라.** 그것이 없으면 '개조가 만든 추가 타격'과 '기본 타격'을 구분할 수 없고,
## 지뢰 폭발 같은 간접 피해가 직접 타격으로 잘못 분류된다(2026-09-09 SYN-2가 그 결함이었다).
static func cause_of(st: CombatState, opt: Dictionary = {}) -> String:
	if opt.has("cause") and String(opt.cause) != "":
		return String(opt.cause)
	var wid := String(opt.get("weapon", ""))
	var hit: Dictionary = opt.get("hit", {})
	var sr: Dictionary = hit.get("src", {})
	# opt.dot에는 "burn"·"bleed" 같은 **문자열**이 들어온다. Godot 4에는 String → bool 변환이 없어
	# 예전의 bool(hit.get("dot", false))는 진짜 지속 피해 opt를 넘기는 순간 그 자리에서 오류를 냈다
	# (2026-09-09 발견 — 그때까지 아무도 dot opt를 hit으로 넘기지 않아 드러나지 않았다). 있는지만 본다
	if hit.has("dot"):
		return "dot"
	if wid == "mine":
		return "mine_blast" # 지뢰는 설치 → 폭발이라 직접 타격이 아니다(무엇이 터뜨렸든)
	var c := String(st.attack_cause)
	match c:
		"echo": return "main_extra"     # 공용 '메아리'가 만든 주무기 추가 타격
		"volley": return "main_extra"
		"orbit": return "support_direct" # 회전 칼날 접촉
		"mine": return "mine_blast"
		"zone": return "zone_tick"
		"dot": return "dot"
	if c != "" and c != "base":
		return c
	# 남은 것은 기본 발사 경로다. **개조가 만든 추가 타격**(src.extra 또는 direct:false)은 기본 타격과 다르다 —
	# 자격표가 main_extra를 따로 두는 이유이고, 그 구분이 없으면 잔류 검흔·여진 같은 것이 아예 자격 심사를 못 받는다
	var indirect := bool(sr.get("extra", false)) or not bool(sr.get("direct", true))
	if wid != "" and not PCatalog.is_main_weapon(wid):
		return "zone_tick" if indirect else "support_direct"
	return "main_extra" if indirect else "main_direct"

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
	sync_meters(st)

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
##   slows **새로 둔화가 걸린 적의 수**(이미 걸린 적의 갱신은 세지 않는다)
##   slow_sec **둔화 적·초**(둔화 중인 적 하나가 1초를 보내면 1.0)      (서리 수정·잔바람)
##   ↑ 이 둘은 단위가 다르다. 서로 더하거나 한쪽 이름으로 다른 쪽 값을 넣지 마라(2026-09-09 BP-2)
##   chill_stacks 부여한 냉기 중첩 누계 · chill_targets 중첩을 받은 **서로 다른 적의 수**
##   freezes 빙결(hard) 횟수 · chills_boss 결빙(soft) 횟수 · freeze_sec **빙결·결빙 적·초**
##   shatters 파쇄 횟수 · shard_hits 파편이 맞힌 수 · shard_dmg 파편 피해   (냉기 기본 특성, docs/FROST_CONTRACT.md 2절)
##   ↑ freezes/shatters(횟수)와 freeze_sec(적·초)도 단위가 다르다. slows/slow_sec와 같은 실수를 반복하지 마라
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

## 보조별 내부 계수기(st.support)를 **표준 지표 이름**(st.metrics.support)으로 옮긴다.
##
## 왜 옮기는가. A조·B조가 각자 만들면서 서로 다른 이름으로 세어 두었다(bell은 blocked_damage,
## doll은 absorbed, wind는 push_total …). 대표 조합 측정은 하나의 이름표를 읽어야 하므로
## 여기서 한 번에 옮긴다. **세는 일은 각 조가 하고, 이름을 맞추는 일만 여기서 한다** —
## 이름을 맞추려고 각 조의 코드를 흩어 고치면 나중에 또 어긋난다.
##
## 규칙에는 영향이 없다(계측 전용). 값을 더하지 않고 **덮어쓴다** — 내부 계수기가 이미 누계이기 때문이다.
const METER_MAP := {
	"crow":   { "marks": "marks", "hits": "strikes", "dmg": "damage" },
	"bell":   { "blocked": "blocked", "blocked_dmg": "blocked_damage",
				"guards": "guarded", "reduced_dmg": "reduced", "reflects": "reflects", "reflect_dmg": "reflect_damage" },
	"echo":   { "copies": "spawned", "hits": "strikes", "copy_dmg": "damage" },
	"wind":   { "fires": "blasts", "push_dist": "push_total", "slows": "slowed", "slow_sec": "slow_sec" },
	"plague": { "fires": "applied", "spreads": "spreads", "bursts": "bursts" },
	"thorns": { "reduced_dmg": "reduced", "reflects": "reflects", "hits": "reflect_hits" },
	"doll":   { "fires": "placed", "taunted": "lured", "soaked": "absorbed", "soaked_dmg": "absorbed_dmg" },
}

## 내부 계수기 없이 **PSupport.meter를 직접 부르는** 보조. 기존 5종이 여기 속한다.
## (A조·B조는 자기 계수기를 쓰고 sync_meters가 이름을 옮긴다 — METER_MAP 쪽이다.)
const METERED_DIRECT := ["blades", "orb", "frost", "ember", "mine"]

## 이 보조의 역할 지표가 실제로 세어지는가. 측정 도구가 "0"과 "재지 못함"을 가르는 데 쓴다.
## **여기 없는 보조의 0은 '약하다'가 아니라 '재지 못했다'는 뜻이다.**
static func is_metered(id: String) -> bool:
	return METER_MAP.has(id) or METERED_DIRECT.has(id)

static func sync_meters(st: CombatState) -> void:
	for id in METER_MAP:
		var src: Dictionary = st.support.get(id, {})
		if src.is_empty():
			continue
		# **장착하지 않은 보조는 지표를 만들지 않는다.** B조 갱신이 매 프레임 상태 칸을 미리 만들어 두기 때문에
		# 그대로 옮기면 달지도 않은 보조가 '계측 연결 · 전부 0'으로 보고서에 나온다(있는데 일을 안 한 것처럼 읽힌다)
		if not equipped(st, String(id)):
			continue
		var M: Dictionary = st.metrics.support
		if not M.has(id):
			M[id] = {}
		var dst: Dictionary = M[id]
		for std in METER_MAP[id]:
			var key := String(METER_MAP[id][std])
			if src.has(key):
				dst[std] = float(src[key])
		# 지속 피해 합계는 사전 안에 들어 있어 따로 더한다
		if src.has("dmg") and typeof(src.dmg) == TYPE_DICTIONARY:
			var total := 0.0
			for k in (src.dmg as Dictionary):
				total += float(src.dmg[k])
			dst["dmg"] = total
			if id == "plague":
				dst["dot_dmg"] = float((src.dmg as Dictionary).get("poison", 0.0)) + float((src.dmg as Dictionary).get("spread", 0.0))
			if id == "thorns":
				dst["reflect_dmg"] = float((src.dmg as Dictionary).get("reflect", 0.0))
