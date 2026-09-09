class_name PConsumables
extends RefCounted
## 출격 준비물(단일 전투)·회복약·부활 물약 규칙(2026-09-08 지시 §6·§7, 2026-09-09 사망 규칙). 값은 data/consumables.json에만 둔다(코드에 숫자 없음).
##
## 왜 이 파일이 따로 있나
## ----------------------
## 전투 단축키를 새로 만들지 않기로 했다. 그래서 준비물은 "거점에서 1개만 골라 두면 다음 전투가 시작될 때 저절로 쓰인다"는
## 형태다. 고르는 것·사는 것·소모하는 것·빌드에 얹는 것을 한 곳에 모아 두어야 중복 소비·복제가 생기지 않는다.
##
## 회차에 저장하는 필드(전부 PSave 정규화와 맞는 형태 — 정수 dict를 새로 만들지 않는다)
##   run.consumables : Array[String]  가방(준비물 id와 "potion"·"revive_potion"을 그대로 넣는다. run.bag과 같은 방식)
##                                    상한은 셋이 서로 독립이다: 준비물 carryMax, 회복약 potionCarryMax, 부활 물약 reviveCarryMax
##   run.prepItem    : String|null    다음 전투에 쓸 준비물 1개(해제·교체는 소모가 아니다)
##   run.prepUsed    : String|null    지금 전투에서 실제로 소모된 준비물(전투가 끝나면 지운다)
##   run.potionBuy   : { "day": int, "count": int }  그 날 산 회복약 수(하루 상한)
##
## 소모 시점(정확히 1회): PFlow.make_encounter / make_boss_encounter가 CombatState를 만든 **뒤**에 consume_for_fight를 부른다.
## 빌드는 그 앞에서 계산되므로(PRun.build → apply_to_build) 효과는 이번 전투에 들어가고, 가방에서는 딱 한 번 빠진다.
## 전투 중 종료·재접속으로 그 전투가 사라져도 이미 빠진 준비물은 돌아오지 않는다(무한 회복 악용 차단).
##
## 보스 입장 스냅샷(run.bossEntry)의 복구는 2026-09-09부터 **시험·자동 진행 전용 재도전 경로**에만 남아 있다
## (PRun.boss_defeat_retry). 사람 플레이의 관문 패배는 사망 정산(PRun.settle_death)이 처리하며, 그 경로는
## 스냅샷을 복구하지 않고 지운다 — 그래서 사망으로 소모한 부활 물약이 스냅샷·계속하기로 되살아나지 않는다.
## 마지막 날(다음 날이 없는 날)의 부활도 같은 규칙이다: 물약 1개를 쓰고 날짜를 늘리지 않은 채 같은 날 관문 앞에 서며,
## 다시 죽으면 또 한 개가 든다(반복 부활에 무료가 없다). 자세한 것은 docs/DEATH_AND_ECONOMY.md.

static var _cache: Dictionary = {}

static func data() -> Dictionary:
	if _cache.has("data"):
		return _cache["data"]
	var f := FileAccess.open("res://data/consumables.json", FileAccess.READ)
	if f == null:
		push_error("데이터 없음: res://data/consumables.json")
		_cache["data"] = {}
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("파싱 실패: res://data/consumables.json")
		_cache["data"] = {}
		return {}
	_cache["data"] = parsed
	return parsed

static func reset() -> void:
	_cache = {}

static func rules() -> Dictionary: return data().get("rules", {})
static func prep_defs() -> Dictionary: return data().get("prep", {})
static func potion_def() -> Dictionary: return data().get("potion", {})
static func revive_def() -> Dictionary: return data().get("revive", {})
## 부활 물약 id(정본은 데이터). 코드에 문자열을 흩뿌리지 않는다
static func revive_id() -> String: return String(revive_def().get("id", "revive_potion"))
static func prep_ids() -> Array:
	var out := []
	for k in prep_defs():
		out.append(String(k))
	return out

## 준비물 또는 회복약·부활 물약 정의. 없으면 {}
static func def(id: String) -> Dictionary:
	if id == "potion":
		return potion_def()
	if id == revive_id():
		return revive_def()
	var P := prep_defs()
	return P[id] if P.has(id) else {}

static func name_of(id: String) -> String:
	var d := def(id)
	return String(d.get("name", id))

static func price(id: String) -> int:
	return int(def(id).get("price", 0))

static func is_prep(id: String) -> bool:
	return prep_defs().has(id)

# ---------- 가방 ----------
static func bag(run: Dictionary) -> Array:
	if typeof(run.get("consumables", null)) != TYPE_ARRAY:
		run.consumables = []
	return run.consumables

static func count(run: Dictionary, id: String) -> int:
	var n := 0
	for x in bag(run):
		if String(x) == id:
			n += 1
	return n

## 준비물만 센다(회복약 제외 — 상한이 따로다)
static func prep_count(run: Dictionary) -> int:
	var n := 0
	for x in bag(run):
		if is_prep(String(x)):
			n += 1
	return n

static func potion_count(run: Dictionary) -> int:
	return count(run, "potion")

## 가지고 있는 부활 물약 수(준비물·회복약과 별도 계정)
static func revive_count(run: Dictionary) -> int:
	return count(run, revive_id())

static func has_revive(run: Dictionary) -> bool:
	return revive_count(run) > 0

# ---------- 구매 ----------
## 살 수 없는 이유(살 수 있으면 ""). 화면은 이 문구를 그대로 쓴다
static func buy_reason(run: Dictionary, id: String) -> String:
	var R := rules()
	if def(id).is_empty():
		return "없는 물건"
	if id == revive_id():
		if revive_count(run) >= int(R.get("reviveCarryMax", 2)):
			return "부활 물약은 %d개까지 들 수 있음" % int(R.get("reviveCarryMax", 2))
	elif id == "potion":
		if potion_count(run) >= int(R.potionCarryMax):
			return "회복약은 %d개까지 들 수 있음" % int(R.potionCarryMax)
		if potion_bought_today(run) >= int(R.potionPerDay):
			return "오늘 회복약 구매 한도(%d) 소진" % int(R.potionPerDay)
	else:
		if prep_count(run) >= int(R.carryMax):
			return "준비물은 %d개까지 들 수 있음" % int(R.carryMax)
		if count(run, id) >= int(R.perItemMax):
			return "같은 준비물은 %d개까지" % int(R.perItemMax)
	if int(run.gold) < price(id):
		return "금화 %d 부족" % (price(id) - int(run.gold))
	return ""

static func can_buy(run: Dictionary, id: String) -> bool:
	return buy_reason(run, id) == ""

## 구매(금화 차감 → 가방). 실패하면 회차를 전혀 바꾸지 않는다
static func buy(run: Dictionary, id: String) -> bool:
	var why := buy_reason(run, id)
	if why != "":
		push_error("구매 불가(%s): %s" % [id, why])
		return false
	run.gold = int(run.gold) - price(id)
	(bag(run) as Array).append(id)
	if id == "potion":
		_note_potion_buy(run)
	PRun.add_log(run, "%s 구매 (-%d)" % [name_of(id), price(id)])
	return true

static func potion_state(run: Dictionary) -> Dictionary:
	var s = run.get("potionBuy", null)
	if typeof(s) != TYPE_DICTIONARY or int((s as Dictionary).get("day", -1)) != int(run.day):
		run.potionBuy = { "day": int(run.day), "count": 0 }
	return run.potionBuy

static func potion_bought_today(run: Dictionary) -> int:
	return int(potion_state(run).get("count", 0))

static func potion_left_today(run: Dictionary) -> int:
	return maxi(0, int(rules().potionPerDay) - potion_bought_today(run))

static func _note_potion_buy(run: Dictionary) -> void:
	var s := potion_state(run)
	s.count = int(s.count) + 1

# ---------- 회복약 사용(거점에서만, 시간 소모 없음) ----------
static func can_use_potion(run: Dictionary) -> bool:
	if potion_count(run) <= 0:
		return false
	if String(run.phase) != "prep" and String(run.phase) != "boss_prep":
		return false
	return float(run.hp) < float(PRun.build(run).hp_max)

## 회복량(최대 체력을 넘지 않는다). 실제로 회복한 양을 돌려준다
static func use_potion(run: Dictionary) -> float:
	if not can_use_potion(run):
		push_error("회복약 사용 불가")
		return 0.0
	var b := PRun.build(run)
	var before: float = float(run.hp)
	run.hp = minf(float(b.hp_max), before + float(potion_def().heal))
	(bag(run) as Array).erase("potion")
	var healed: float = float(run.hp) - before
	PRun.add_log(run, "회복약 사용: 체력 +%d (%d/%d)" % [int(round(healed)), int(float(run.hp)), int(float(b.hp_max))])
	return healed

# ---------- 장착(다음 전투에 쓸 1개) ----------
static func armed(run: Dictionary) -> String:
	var v = run.get("prepItem", null)
	return String(v) if v != null else ""

## 고를 수 없는 이유(고를 수 있으면 "")
static func select_reason(run: Dictionary, id: String) -> String:
	if not is_prep(id):
		return "준비물이 아님"
	if count(run, id) <= 0:
		return "가방에 없음"
	return ""

static func can_select(run: Dictionary, id: String) -> bool:
	return select_reason(run, id) == ""

## 1개만 고른다. 이미 다른 것을 골랐으면 바꾸기만 하고 아무것도 소모하지 않는다
static func select(run: Dictionary, id: String) -> bool:
	if not can_select(run, id):
		push_error("준비물 선택 불가: " + id)
		return false
	if armed(run) == id:
		return true
	run.prepItem = id
	PRun.add_log(run, "출격 준비물: %s (다음 전투에서 사용)" % name_of(id))
	return true

## 해제도 소모가 아니다(가방에 그대로 남는다)
static func clear_select(run: Dictionary) -> void:
	if armed(run) == "":
		return
	run.prepItem = null

# ---------- 소모(전투 입장) ----------
## 이번 전투에 쓰인 준비물 id("" = 없음). 가방에서 1개를 빼고 장착을 비운다.
## PFlow.make_encounter / make_boss_encounter가 CombatState를 만든 뒤 정확히 1회 부른다.
static func consume_for_fight(run: Dictionary) -> String:
	var id := armed(run)
	if id == "":
		run.prepUsed = null
		return ""
	if count(run, id) <= 0: # 방어: 장착만 남고 물건이 없으면 조용히 비운다(효과 없음)
		run.prepItem = null
		run.prepUsed = null
		return ""
	(bag(run) as Array).erase(id)
	run.prepItem = null
	run.prepUsed = id
	PRun.add_log(run, "%s 사용(이번 전투)" % name_of(id))
	return id

## 전투가 끝난 뒤(승리·패배 모두) 표시를 지운다. 소모는 되돌리지 않는다
static func clear_used(run: Dictionary) -> void:
	run.prepUsed = null

# ---------- 부활 물약 소모(사망 정산에서만) ----------
## 정확히 한 개를 소모한다. 없으면 false(회차가 끝난다는 뜻).
## 여기 말고 어디에서도 부활 물약을 빼지 않는다 — PRun.settle_death가 사망 1건마다 딱 한 번 부른다.
## **부활 한 번에 물약 한 개다.** 마지막 날처럼 같은 날 관문 앞으로 돌아가는 경우에도 다시 죽으면 또 한 개가 든다
## (관문에 다시 들어가면 PRun.start_boss가 중복 방지 키를 바꾸므로 새 사망으로 정산된다). 한 번 쓰고 무한 재도전이 되지 않는다.
## 이 소모는 보스 입장 스냅샷(PConsumables.restore)으로 되돌리지 않는다: 사망 정산 경로는 스냅샷을 복구하지 않고 지운다(PRun.settle_death).
static func consume_revive(run: Dictionary) -> bool:
	if not has_revive(run):
		return false
	(bag(run) as Array).erase(revive_id())
	PRun.add_log(run, "%s 사용: 쓰러졌지만 다시 일어난다 (남은 %d개)" % [name_of(revive_id()), revive_count(run)])
	return true

## 부활 물약을 **사기 전에** 알아야 할 것을 화면이 그대로 쓸 수 있게 규칙 계층이 준다.
## data/consumables.json의 short/desc가 정본이고, 여기는 그 중 "지금 이 회차에서 어떻게 되는지"를 한 줄로 덧붙인다.
## 마지막 날(다음 날이 없는 날)에는 날짜가 늘지 않고 같은 날 관문 앞으로 돌아가며 그날 남은 시간이 전부 사라진다.
static func revive_when_line(run: Dictionary) -> String:
	var pct := int(round(float(revive_def().get("hpFrac", 0.25)) * 100.0))
	if PRun.has_next_day(run):
		return "지금 쓰러지면: 남은 하루를 잃고 다음 날 최대 체력 %d%%로 부활" % pct
	return "지금은 마지막 날: 날짜는 그대로, 같은 날 관문 앞에서 최대 체력 %d%%로 부활(그날 남은 시간은 전부 소진)" % pct

# ---------- 빌드 반영 ----------
## PRun.build가 PBuild.derive 결과 위에 얹는다. 장착 중인 준비물 1개만, 딱 한 번.
## 장비 효과 계산(PBuild)은 건드리지 않는다 — 여기서 더하는 값은 전부 "이미 계산된 결과에 한 번 더하기"다.
static func apply_to_build(run: Dictionary, b: Dictionary) -> Dictionary:
	var id := armed(run)
	if id == "" or not is_prep(id):
		return b
	var e: Dictionary = def(id).get("eff", {})
	b["prep"] = id                       # 화면·전투가 "무엇이 걸렸는지" 읽는 한 곳
	b["prep_eff"] = e.duplicate(true)
	if e.has("shield"):
		# 수호 부적: 시작 보호막에 더한다. equip.startShield에는 넣지 않는다
		# (월광 갑옷의 재생 상한이 equip.startShield를 읽기 때문에 — 거기 더하면 갑옷 효과가 같이 커진다)
		b.shield = float(b.shield) + float(e.shield)
	if e.has("eliteDirect"):
		# 사냥꾼의 검과 같은 칸에 더한다. 전투는 (1 + eliteDirect)를 한 번만 곱하므로 중복 계산이 없다
		var EQ: Dictionary = b.equip
		EQ["eliteDirect"] = float(EQ.get("eliteDirect", 0.0)) + float(e.eliteDirect)
	return b

# ---------- 전투가 묻는 값(전투 코드는 이 세 함수만 부르면 된다) ----------
## 파쇄 기름: 방어 자세 감소 배율의 하한. 없으면 0.0(하한 없음)
## PEnemiesNew.shield_mult가 min으로 고른 **결과**에만 적용한다 — min 규칙을 깨지 않고, 곱하지도 않는다
static func guard_floor(build: Dictionary) -> float:
	return float((build.get("prep_eff", {}) as Dictionary).get("guardFloor", 0.0))

## 정화 향: { slow: 감속 완화 비율, zone: 지대 지속 피해 감소 비율 }. 없으면 둘 다 0
static func purge(build: Dictionary) -> Dictionary:
	var e: Dictionary = build.get("prep_eff", {})
	return { "slow": float(e.get("purgeSlow", 0.0)), "zone": float(e.get("purgeZone", 0.0)) }

## 응급 약낭: { frac, heal }. 없으면 {}
static func low_heal(build: Dictionary) -> Dictionary:
	var e: Dictionary = build.get("prep_eff", {})
	return e.lowHeal if e.has("lowHeal") else {}

# ---------- 상점 진열(하루 시드) ----------
## 오늘 상점에 놓을 준비물 id 목록. 재고 시드와 같은 규칙이라 다시 열거나 불러와도 같다
static func stock_ids(seed_v: int, n: int) -> Array:
	var pool := prep_ids()
	var rng := PRng.new(seed_v)
	var out := []
	while out.size() < n and pool.size() > 0:
		var i := rng.int_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out

# ---------- 보스 재도전 스냅샷 ----------
## PRun.start_boss가 담고 PRun.boss_defeat가 되돌린다(금화·장비와 같은 규칙)
static func snapshot(run: Dictionary) -> Dictionary:
	return {
		"consumables": (bag(run) as Array).duplicate(),
		"prepItem": run.get("prepItem", null),
		"potionBuy": (run.get("potionBuy", {}) as Dictionary).duplicate(),
	}

static func restore(run: Dictionary, snap: Dictionary) -> void:
	if snap.is_empty():
		return
	run.consumables = (snap.get("consumables", []) as Array).duplicate()
	run.prepItem = snap.get("prepItem", null)
	if snap.has("potionBuy"):
		run.potionBuy = (snap.potionBuy as Dictionary).duplicate()
	run.prepUsed = null

# ---------- 표시용 ----------
## "지금 이 준비물이 이 전투에서 얼마나 값을 하는가"를 한 줄로. 화면이 계산하지 않게 여기서 만든다
static func effect_line(id: String) -> String:
	var d := def(id)
	return String(d.get("short", ""))

## 회복 경제 한 줄(거점에서 지금 쓸 수 있는 회복 수단). { potion, rest, voucher } 각각 회복량·비용
static func heal_options(run: Dictionary) -> Array:
	var b := PRun.build(run)
	var miss: float = maxf(0.0, float(b.hp_max) - float(run.hp))
	var out := []
	var ph: float = minf(float(potion_def().heal), miss)
	out.append({ "id": "potion", "name": String(potion_def().name), "heal": ph, "gold": price("potion"), "hours": 0,
		"have": potion_count(run), "can": can_use_potion(run) })
	out.append({ "id": "rest", "name": "휴식", "heal": miss, "gold": 0, "hours": int(PCatalog.config().REST_HOURS),
		"have": -1, "can": PRun.can_rest(run) and not PRun.has_service(run, "free_rest") })
	# 표현은 "무료"가 아니라 "시간 소모 없음"(2026-09-09 사용자 확정). 데이터의 서비스 이름은 다른 담당 파일이라 규칙 계층이 문구를 준다
	out.append({ "id": "free_rest", "name": PRun.rest_voucher_name(), "heal": miss, "gold": int(PCatalog.shop().merchantService.free_rest), "hours": 0,
		"have": int(run.get("services", {}).get("free_rest", 0)), "can": PRun.has_service(run, "free_rest") })
	return out
