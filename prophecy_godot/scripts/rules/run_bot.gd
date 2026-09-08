class_name PRunBot
extends RefCounted
## 회차 봇(HTML tools/run_sim.js simulate() 이식, 헤드리스): 봇이 하루 단위로 출격·휴식·상점·관문을 진행하고 3택을 고른다.
## F1 재발 방지: 거점·전투 뒤 화면의 모든 행동은 PFlow.actions(run)이 돌려준 항목(enabled) 중에서만 고르고 _perform으로 실행한다
## (PRun.start_sortie 직접 호출 없음 — 출격은 항상 오늘의 카드 sortie:<id> 항목). 전투는 PBot.run_combat, 정산·3택·사건은 PFlow/PEvents 공용 경로.
## 시간 계정(C19, run_sim.js와 같은 가정): 시뮬레이션된 시간 = 전투 + 보스(고정 단계 시계). 가정한 메뉴 시간 = 카드 1장 6초(전투 중 포함, 실제 발생 시점에 기록)
## + 조우 전후 화면 25초 + 하루 종료 10초 + 휴식 5초 + 사건 8초. 시간 초과(조우 240초/보스 300초)는 패배와 별도로 센다.
## 봇 결과는 정책 비교용이며 사람의 체감 플레이타임·재미·승률이 아니다. 난수는 회차 시드에서만 나온다(randi 없음).

const GAME := preload("res://scripts/game/game.gd")
const MENU := { "encounter": 25.0, "card": 6.0, "dayEnd": 10.0, "rest": 5.0, "event": 8.0 }
const ENCOUNTER_MAX_SEC := 240.0
const BOSS_MAX_SEC := 300.0
const RESERVE := 40 # 거점 경제 봇: 예비 금화
const COMBAT_PICK_KINDS := ["weapon_new", "weapon_level", "weapon_mod", "common", "skill_new", "skill_level", "skill_variant", "passive"]
const LATER := ["forest", "ridge"] # 1~2일차
const MID := ["marsh", "den"] # 3~4일차
const LATE := ["den", "deep"] # 5일차~

## 전략 7종(run_sim.js STRATS). pick은 날짜별 선호 지역(오늘의 카드 중 그 지역 카드를 고른다), restBelow는 휴식 기준 체력 비율,
## deep은 더 깊이 탐험 적극, missions는 카드 우선순위(risky=위험 조건 카드, linked=빌드 연결 카드), matched는 3택을 보유 무기·기술 강화 우선
const STRATS := {
	"easy": { "id": "easy", "name": "쉬운 지역 반복", "pick": "easy", "restBelow": 0.3, "deep": false, "missions": "", "matched": false,
		"doc": "오늘의 카드 중 근교 숲 카드를 고른다(없으면 가장 쉬운 지역). 체력 30% 미만이면 휴식. 더 깊이 없음" },
	"gradual": { "id": "gradual", "name": "점차 위험 지역으로", "pick": "gradual", "restBelow": 0.3, "deep": false, "missions": "", "matched": false,
		"doc": "1~2일차 숲·능선, 3~4일차 습지·굴, 5일차~ 굴·심층 순으로 선호. 체력 30% 미만이면 휴식" },
	"risky": { "id": "risky", "name": "위험 지역 우선", "pick": "risky", "restBelow": 0.3, "deep": false, "missions": "", "matched": false,
		"doc": "오늘의 카드 중 가장 위험한 지역(심층·굴) 우선. 사건은 제단·상인 구출·봉인 전투를 받는다" },
	"cautious": { "id": "cautious", "name": "체력 낮으면 일찍 휴식", "pick": "gradual", "restBelow": 0.6, "deep": false, "missions": "", "matched": false,
		"doc": "점진 경로와 같되 체력 60% 미만이면 휴식. 사건은 치료 우선" },
	"deep": { "id": "deep", "name": "더 깊이 탐험 적극", "pick": "gradual", "restBelow": 0.3, "deep": true, "missions": "", "matched": false,
		"doc": "점진 경로 + 승리 뒤 체력 50% 이상이면 더 깊이 탐험(행동 목록의 deep_explore)" },
	"mission": { "id": "mission", "name": "위험 임무 우선", "pick": "gradual", "restBelow": 0.3, "deep": false, "missions": "risky", "matched": false,
		"doc": "오늘 카드 중 위험 조건이 붙은 임무 카드부터, 없으면 첫 카드" },
	"matched": { "id": "matched", "name": "빌드 맞춤 보상 선택", "pick": "gradual", "restBelow": 0.3, "deep": false, "missions": "linked", "matched": true,
		"doc": "빌드 연결 카드(보유 무기 레벨·개조·기술) 우선 + 3택은 보유 무기·기술 강화·지역 태그 일치 우선" },
}

static func strategies() -> Dictionary:
	return STRATS

# ---------- 인스턴스 상태(한 회차) ----------
var run: Dictionary = {}
var strat_id: String = "gradual"
var S: Dictionary = {}
var bot_policy: String = "balanced"
var opts: Dictionary = {}
var T: Dictionary = { "combat": 0.0, "cards": 0.0, "screens": 0.0, "rest": 0.0, "dayEnd": 0.0, "boss": 0.0 }
var L: Dictionary = {}
var clock: float = 0.0
var _t0: float = 0.0
var _card_sec: float = 0.0
var stop_day: int = 0
var max_days: int = 0
var stub_gates: bool = false # 측정용 장치(성장 체크포인트): 관문을 전투 없이 스텁 승리로 통과시켜 성장 곡선을 끝까지 본다. 보스 난이도 판정이 아니다
var endless_segments: int = 0 # >0: 본편 완주 뒤 무한 모드를 그 구간 수만큼(구간 보스 승리 기준) 진행하고 마친다
var max_retries: int = 3
var verbose: bool = false

## 회차 1개 실행. opts: { start("sword"), bot_policy("balanced"), balance(""=기본 세트), max_retries(3), stop_day(0=없음: 그 날 이후 출격 없음),
##   max_days(0=없음: 그 날까지만 진행하고 멈춤 — 첫날 비교용), verbose(false: printerr 진행 줄) }
static func simulate(seed: int, strat: String, o: Dictionary = {}) -> Dictionary:
	var b := PRunBot.new()
	return b._run(seed, strat, o)

## 보고서 머리말용 실제 설정(하드코딩 금지, F8): 회차 dict·카탈로그에서 읽는다
static func settings(o: Dictionary = {}) -> Dictionary:
	var start := String(o.get("start", "sword"))
	var r := PRun.new_run(1, start, String(o.get("balance", "")))
	r.densitySet = String(o.get("density_set", ""))
	var BS := PCatalog.balance_sets()
	var bal := String(r.balance)
	var DC: Dictionary = PCatalog.difficulty().candidates
	var did := String(r.difficulty)
	var boss_hp := {}
	var boss_names := {}
	for b in PRun.mode_def(r).bosses:
		boss_hp[String(b.id)] = PRun.boss_hp(r, String(b.id))
		boss_names[String(b.id)] = String(PCatalog.boss_def(String(b.id)).name)
	var D := PCatalog.density()
	var X: Dictionary = PCatalog.growth().XP
	return {
		"start": start, "mode": String(r.mode), "days": int(PRun.mode_def(r).days),
		"balance": bal, "balance_name": String(BS[bal].name) if BS.has(bal) else bal,
		"difficulty": did, "difficulty_name": String(DC[did].name) if DC.has(did) else did,
		"bossHpSet": String(r.bossHpSet), "dayHpSet": String(r.dayHpSet), "boss_hp": boss_hp, "boss_names": boss_names,
		"killXp": PRun.kill_xp_mult(r), "bonusXp": PRun.bonus_xp_mult(r),
		"density_set": String(o.get("density_set", "")) if String(o.get("density_set", "")) != "" else String(D.get("set_default", "uniform_x5")), "density_set_name": String((D.get("sets", {}) as Dictionary).get(String(o.get("density_set", "")) if String(o.get("density_set", "")) != "" else String(D.get("set_default", "uniform_x5")), {}).get("name", "")),
		"density_mult": float(D.multiplier), "alive_cap": int(D.alive_cap), "group": int(D.group), "interval": float(D.interval),
		"xp_base": float(X.base), "xp_step": float(X.step), "xp_quad": float(X.get("quad", 0.0)),
		"bot_policy": String(o.get("bot_policy", "balanced")), "rules_version": String(GAME.VERSION), "engine": String(Engine.get_version_info().string), "os": OS.get_name(),
		"menu": MENU.duplicate(), "encounter_max_sec": ENCOUNTER_MAX_SEC, "boss_max_sec": BOSS_MAX_SEC, "start_gold": int(PCatalog.config().START_GOLD), "reserve": RESERVE,
	}

func _log(msg: String) -> void:
	if verbose:
		printerr("[run_bot %s/%d d%d] %s" % [strat_id, int(run.get("seed", 0)), int(run.get("day", 0)), msg])

# ---------- 행동 목록(F1: UI·봇 공용) ----------
func _actions() -> Array:
	return PFlow.actions(run)

func _find(acts: Array, id: String) -> Dictionary:
	for a in acts:
		if String(a.id) == id and bool(a.enabled):
			return a
	return {}

func _of_kind(acts: Array, kind: String) -> Array:
	var out := []
	for a in acts:
		if String(a.kind) == kind and bool(a.enabled):
			out.append(a)
	return out

## 행동 목록 항목 실행. 전투 뒤 화면 행동은 run.pendingSortie(없으면 sortie 인자)를 쓴다. 지원하지 않는 항목·비활성은 null
func _perform(act: Dictionary, sortie: Dictionary = {}) -> Variant:
	if act.is_empty() or not bool(act.enabled):
		push_error("행동 불가: " + String(act.get("id", "?")))
		return null
	var d: Dictionary = act.data
	var s: Dictionary = run.pendingSortie if run.get("pendingSortie", null) != null else sortie
	match String(act.kind):
		"sortie": return PSortie.start(run, String(d.card_id))
		"rest": return PRun.rest(run)
		"end_day": return PRun.end_day(run)
		"boss_start": return PEndless.start_boss(run) if PEndless.active(run) else PRun.start_boss(run)
		"endless_start": return PEndless.start(run)
		"endless_fight": return PEndless.start_fight(run)
		"endless_regroup": return PEndless.regroup(run)
		"endless_quit":
			PEndless.over(run, "quit")
			return true
		"deep_explore": return PRun.deep_explore(run, s)
		"return_home":
			PFlow.return_home(run, s)
			return true
		"event": return PEvents.resolve(run, s, String(d.opt_id))
		"event_fight": return PFlow.make_encounter(run, s)
		"buy_equipment": return PRun.buy_equipment(run, String(d.id), true, String(d.from))
		"buy_skill": return PRun.buy_skill(run)
		"buy_merchant_service": return PRun.buy_merchant_service(run)
		"forge_upgrade": return PRun.forge_upgrade(run)
		"equip": return PRun.equip_item(run, String(d.id))
		"unequip":
			PRun.unequip_item(run, String(d.slot))
			return true
		"sell": return PRun.sell_equipment(run, String(d.id))
		"sell_mat": return PRun.sell(run, String(d.mat_id), int(d.n))
		"continue_offer": return PFlow.resolve_all(run, {}, _pick_cb(), _on_pick_cb("screen"))
	push_error("지원하지 않는 행동: " + String(act.id))
	return null

# ---------- 3택 선택 ----------
func _pick_cb() -> Callable:
	return Callable(self, "_pick")

func _on_pick_cb(where: String) -> Callable:
	return Callable(self, "_on_pick").bind(where)

## 선택지 → 선택(없으면 null). matched 전략은 보유 무기·기술 강화·지역 태그 일치 우선(run_sim.js matchedPick)
func _pick(off: Dictionary) -> Variant:
	var cs: Array = off.get("choices", [])
	if cs.is_empty():
		return null
	if bool(S.matched):
		var g: Dictionary = run.growth
		var owned := {}
		for w in g.weapons:
			owned[String(w.id)] = true
		var best: Dictionary = {}
		var best_s := 0
		for c in cs:
			var sc := 0
			var k := String(c.kind)
			if (k == "weapon_level" or k == "weapon_mod") and owned.has(String(c.id)):
				sc += 3
			if k == "skill_level" or k == "skill_variant":
				sc += 2
			if bool(c.get("regionMatch", false)):
				sc += 1
			if sc > best_s:
				best_s = sc
				best = c
		if best_s > 0:
			return best
	var p := PBot.pick_choice(off, int(run.seed))
	return p if not p.is_empty() else null

func _on_pick(off: Dictionary, c: Variant, where: String) -> void:
	T.cards = float(T.cards) + float(MENU.card)
	clock += float(MENU.card)
	L.cards = int(L.cards) + 1
	if where == "combat":
		L.cardsInCombat = int(L.cardsInCombat) + 1
	var pool := String(off.get("pool", ""))
	if pool == "deep":
		L.deepPicks = int(L.deepPicks) + 1
	if pool == "mission":
		L.missionPicks = int(L.missionPicks) + 1
	if pool == "boss":
		(L.rarePicks as Array).append(String(c.key) if c != null else "skip")
	(L.events as Array).append({ "t": int(round(clock)), "kind": pool, "key": (String(c.key) if c != null else "skip"), "where": where })
	_mark()

## 무기 2·3번째, E 습득 시점(초)
func _mark() -> void:
	var g: Dictionary = run.growth
	var t := int(round(clock))
	if L.weapon2 == null and (g.weapons as Array).size() >= 2:
		L.weapon2 = t
	if L.weapon3 == null and (g.weapons as Array).size() >= 3:
		L.weapon3 = t
	if L.eSkill == null and g.skills.get("e", null) != null:
		L.eSkill = t

func _resolve_all(region_id: String, where: String) -> int:
	return PFlow.resolve_all(run, { "region_id": region_id }, _pick_cb(), _on_pick_cb(where))

# ---------- 전투 ----------
func _on_level_up(st2: CombatState, sortie: Dictionary) -> void:
	clock = _t0 + st2.t + _card_sec
	var before := float(T.cards)
	_resolve_all(String(sortie.regionId), "combat")
	_card_sec += float(T.cards) - before
	st2.rebuild(PRun.build(run))

## 조우 1회(일반·사건 추가 전투·더 깊이 공용). st가 주어지면(event_fight 행동이 만든 상태) 그것을 쓴다
func _fight(sortie: Dictionary, pre: CombatState = null) -> CombatState:
	var st: CombatState = pre if pre != null else PFlow.make_encounter(run, sortie)
	_t0 = clock
	_card_sec = 0.0
	PBot.run_combat(st, bot_policy, _bot_opts({ "max_sec": ENCOUNTER_MAX_SEC, "on_level_up": Callable(self, "_on_level_up").bind(sortie) }))
	T.combat = float(T.combat) + st.t
	clock = _t0 + st.t + _card_sec
	L.encounters = int(L.encounters) + 1
	var sm := st.summary()
	for k in sm.enemies:
		var m: Dictionary = sm.enemies[k]
		L.spawned = int(L.spawned) + int(m.get("spawned", 0))
		L.executed = int(L.executed) + int(m.get("executed", 0))
		L.dba = int(L.dba) + int(m.get("died_before_attack", 0))
		L.killedN = int(L.killedN) + int(m.get("killed", 0))
	L.taken = float(L.taken) + float(sm.damage_taken)
	L.supportOnlySec = float(L.get("supportOnlySec", 0.0)) + float(sm.get("support_only_sec", 0.0)) # 편성 측정(지시 4)
	L.thinTailSec = float(L.get("thinTailSec", 0.0)) + float(sm.get("thin_tail_sec", 0.0))
	L.noTargetSec = float(L.get("noTargetSec", 0.0)) + float(sm.get("no_target_sec", 0.0))
	L.maxAlive = maxi(int(L.get("maxAlive", 0)), int(sm.get("max_alive", 0)))
	T.screens = float(T.screens) + float(MENU.encounter)
	clock += float(MENU.encounter)
	if st.status == "running":
		st.status = "timeout"
		L.timeouts = int(L.timeouts) + 1
		st.delayed.clear() # 전투 밖 정리: 남은 지연 람다의 순환 참조 해제(규칙 아님)
	_log("fight %s%s: %s t=%.1f hp=%.0f kills=%d lv=%d" % [String(sortie.regionId), " deep" if bool(sortie.get("deep", false)) else "", st.status, st.t, float(st.player.hp), int(st.stats.kills), int(run.growth.level)])
	return st

## 전투 봇: 기존 정책(문자열)이면 PBot.run_combat이 만들고, 실력 프로필(novice/regular/skilled, docs/BOT_FRAMEWORK.md)이면 전투마다 PSkillBot을 만든다.
## 봇 난수는 회차 시드·전투 순번에서만(게임 난수와 분리). 사람 보정 미완료
var _bot_n: int = 0
func _bot_opts(o: Dictionary) -> Dictionary:
	if PSkillBot.profile_ids().has(bot_policy):
		_bot_n += 1
		o.bot = PSkillBot.new(bot_policy, int(run.seed) * 101 + _bot_n * 7)
	return o

func _settle_win(sortie: Dictionary, st: CombatState) -> void:
	PFlow.settle_victory(run, sortie, st)
	_resolve_all(String(sortie.regionId), "screen")
	_mark()

func _settle_loss(sortie: Dictionary, st: CombatState) -> void:
	PFlow.settle_defeat(run, sortie, st)
	if st.status == "lost":
		L.losses = int(L.losses) + 1
	_mark()

## 탐험 사건(출격당 최대 1회): PEvents.bot_choose 정책으로 고르되 행동 목록의 event:<id> 항목으로만 실행. 반환 "fight"|"deep"|""
func _handle_event(sortie: Dictionary) -> String:
	var ev = sortie.get("event", null)
	if ev == null or bool(ev.resolved):
		return ""
	var acts := _actions()
	var choice := PEvents.bot_choose(run, sortie, strat_id)
	var act := _find(acts, "event:" + choice)
	if act.is_empty():
		act = _find(acts, "event:leave")
		choice = "leave"
	if act.is_empty():
		_log("event %s: 선택 가능한 행동 없음" % String(ev.id))
		return ""
	var r = _perform(act, sortie)
	L.eventCount = int(L.eventCount) + 1
	(L.eventChoices as Array).append(String(ev.id) + ":" + choice)
	T.screens = float(T.screens) + float(MENU.event)
	clock += float(MENU.event)
	if r == null or not (r is Dictionary):
		return ""
	var nx := String((r as Dictionary).get("next", "after"))
	if nx == "offer":
		_resolve_all(String(sortie.regionId), "screen")
	return nx if (nx == "fight" or nx == "deep") else ""

# ---------- 보스 관문 ----------
func _boss_gate() -> bool:
	if stub_gates: # 측정 전용: 관문을 스텁 승리로 통과(전투를 하지 않으므로 보스 기록·시간은 남기지 않는다)
		var g2 := 0
		while String(run.phase) == "boss_prep" and g2 < 6:
			g2 += 1
			var act0 := _find(_actions(), "boss_start")
			if act0.is_empty():
				return false
			var bs0_v = _perform(act0)
			if bs0_v == null or not (bs0_v is Dictionary) or (bs0_v as Dictionary).is_empty():
				return false
			var st0 := PFlow.make_boss_encounter(run, bs0_v)
			st0.status = "won"
			if not st0.boss.is_empty():
				st0.boss.dead = true
			PFlow.settle_boss_victory(run, st0)
			PFlow.resolve_all(run, {}, _pick_cb(), _on_pick_cb("screen"))
		return true
	var guard := 0
	while String(run.phase) == "boss_prep" and guard < max_retries + 2:
		guard += 1
		var act := _find(_actions(), "boss_start")
		if act.is_empty():
			_log("boss_start 행동 없음")
			return false
		var bs_v = _perform(act)
		if bs_v == null or not (bs_v is Dictionary) or (bs_v as Dictionary).is_empty():
			return false
		var bs: Dictionary = bs_v
		var g: Dictionary = run.growth
		if int(run.get("bossRetries", 0)) == 0:
			(L.gateBuilds as Array).append({ "stage": int(bs.stage), "bossId": String(bs.bossId), "day": int(run.day), "level": int(g.level), "growth": g.duplicate(true), "equipment": (run.equipment as Dictionary).duplicate(), "forge": int(run.forge), "gold": int(run.gold), "hpMax": float(PRun.build(run).hp_max) })
		var st := PFlow.make_boss_encounter(run, bs)
		PBot.run_combat(st, bot_policy, _bot_opts({ "max_sec": BOSS_MAX_SEC }))
		if st.status == "running":
			st.status = "timeout"
			st.delayed.clear()
		T.boss = float(T.boss) + st.t
		clock += st.t
		L.bossSec = int(L.bossSec) + int(round(st.t))
		var sm := st.summary()
		L.bossTaken = float(L.bossTaken) + float(sm.damage_taken)
		var pats: Dictionary = sm.patterns
		for k in pats:
			var pk := String(bs.bossId) + ":" + String(k)
			L.bossPatterns[pk] = int(L.bossPatterns.get(pk, 0)) + int(pats[k])
		var row := { "id": String(bs.bossId), "stage": int(bs.stage), "status": st.status, "sec": int(round(st.t)), "hp": int(round(float(st.player.hp))),
			"bossHp": int(round(float(st.boss.hp))) if not st.boss.is_empty() else 0, "bossHpMax": int(round(float(st.boss.hp_max))) if not st.boss.is_empty() else 0,
			"taken": int(round(float(sm.damage_taken))), "patterns": pats.duplicate(), "level": int(g.level), "day": int(run.day), "retries": int(run.get("bossRetries", 0)) }
		(L.bosses as Array).append(row)
		_log("boss %s: %s t=%.1f hp=%d bossHp=%d" % [String(bs.bossId), st.status, st.t, int(row.hp), int(row.bossHp)])
		if st.status == "won":
			PFlow.settle_boss_victory(run, st)
			PFlow.resolve_all(run, {}, _pick_cb(), _on_pick_cb("screen"))
		else:
			PFlow.settle_boss_defeat(run, st)
			L.bossRetries = int(L.bossRetries) + 1
			if int(run.get("bossRetries", 0)) >= max_retries:
				L.failedAt = String(bs.bossId)
				return false
	return true

# ---------- 거점 경제 봇(run_sim.js shopBot): 예비 금화를 남기고 ① 빈 슬롯 새 기술 ② 공용 공격 강화(개방 시) ③ 오늘의 장비(빈 슬롯 우선). 교체 없음 ----------
func _note_buy(k: String) -> void:
	if not (L.firstBuy as Dictionary).has(k):
		L.firstBuy[k] = int(run.day)

func _shop_bot() -> void:
	if stop_day > 0 and int(run.day) > stop_day:
		return
	var guard := 0
	while guard < 12:
		guard += 1
		var g0 := int(run.gold)
		var acts := _actions()
		var did := false
		var sk := _find(acts, "buy_skill")
		if not sk.is_empty() and g0 - int(sk.data.price) >= RESERVE:
			if bool(_perform(sk)):
				L.skillsBought = int(L.skillsBought) + 1
				_note_buy("skill")
				did = true
		if not did:
			var fg := _find(acts, "forge_upgrade")
			if not fg.is_empty() and g0 - int(fg.data.cost) >= RESERVE:
				if bool(_perform(fg)):
					L.forge = int(run.forge)
					_note_buy("forge")
					did = true
		if not did:
			var cands := []
			for a in _of_kind(acts, "buy_equipment"):
				if g0 - int(a.data.price) >= RESERVE:
					cands.append(a)
			var EQ := PCatalog.equipment()
			cands.sort_custom(func(a, b):
				var ea: int = 1 if run.equipment[String(EQ[String(a.data.id)].slot)] != null else 0
				var eb: int = 1 if run.equipment[String(EQ[String(b.data.id)].slot)] != null else 0
				return ea < eb)
			if cands.size() > 0:
				var a: Dictionary = cands[0]
				if bool(_perform(a)):
					(L.equipBought as Array).append(String(a.data.id))
					_note_buy("equipment")
					did = true
		L.goldSpent = int(L.goldSpent) + (g0 - int(run.gold))
		if not did:
			break

# ---------- 출격 카드 선택(행동 목록의 sortie:* 중에서) ----------
func _want(day: int) -> Array:
	match String(S.pick):
		"easy": return ["forest"]
		"risky": return ["deep", "den"]
	var a := PRun.act_of(run, day) # 10일 본편: 막 기준(1막 근교, 2막 습지·굴, 3막 굴·심층). 옛 trio는 날짜 기준
	var th := PRun.current_theme(run, day)
	if not th.is_empty(): # 테마 경로: 1칸 장소(외곽) 우선, 위험/후반 전략은 2칸(핵심)
		var p1 := String((th.places as Array)[0].id)
		var p2 := String((th.places as Array)[1].id)
		match String(S.pick):
			"easy": return [p1]
			"risky": return [p2, p1]
		return [p1, p2] if int(a.get("id", 1)) == 1 else [p2, p1]
	if not a.is_empty():
		match int(a.id):
			1: return LATER
			2: return MID
			_: return LATE
	if day <= 2:
		return LATER
	if day <= 4:
		return MID
	return LATE

func _region_index(id: String) -> int:
	var i := 0
	for r in PCatalog.regions():
		if String(r.id) == id:
			return i
		i += 1
	if PRun.is_theme_place(id): # 테마 장소: 1칸 < 2칸 순서(막 안에서의 위험도)
		return 50 + PRun.place_cost(id)
	return -1

func _choose_sortie(acts: Array) -> Dictionary:
	var cards := _of_kind(acts, "sortie")
	if cards.is_empty():
		return {}
	var ms := String(S.missions)
	if ms != "":
		for a in cards:
			var d: Dictionary = a.data
			var ok: bool = (d.get("risk", null) != null) if ms == "risky" else bool(PSortie.card(run, String(d.card_id)).get("linked", false))
			if ok:
				return a
		return cards[0]
	var want := _want(int(run.day))
	for w in want:
		for a in cards:
			if String(a.data.region_id) == String(w):
				return a
	# 선호 지역이 없으면: 선호 중 가장 위험한 지역 이하에서 가장 위험한 카드, 그것도 없으면 첫 카드
	var max_want := -1
	for w in want:
		max_want = maxi(max_want, _region_index(String(w)))
	var best: Dictionary = {}
	var best_i := -1
	for a in cards:
		var ri := _region_index(String(a.data.region_id))
		if ri <= max_want and ri > best_i:
			best_i = ri
			best = a
	return best if not best.is_empty() else cards[0]

# ---------- 회차 전체 ----------
func _new_log() -> Dictionary:
	return { "takenByDay": [], "matsByDay": [], "combatSecByDay": [], "restsByDay": [], "powerByDay": [], "spentByDay": [], "firstBuy": {}, "gateBuilds": [], "goldEarnedByDay": [], "goldSpent": 0,
		"equipBought": [], "skillsBought": 0, "swaps": 0, "forge": 0, "deepRewards": [], "daysLostToDefeat": 0, "steered": 0, "encounters": 0, "losses": 0, "timeouts": 0, "rests": 0,
		"deeps": 0, "cards": 0, "cardsInCombat": 0, "deepPicks": 0, "missions": 0, "missionPicks": 0, "eventCount": 0, "eventChoices": [], "eventFights": 0, "levelUpsByDay": [],
		"weapon2": null, "weapon3": null, "eSkill": null, "events": [], "spawned": 0, "executed": 0, "dba": 0, "killedN": 0, "taken": 0.0, "bossTaken": 0.0, "bossPatterns": {},
		"bosses": [], "bossSec": 0, "bossRetries": 0, "rarePicks": [], "failedAt": "", "stopDay": 0, "stopReason": "" }

func _power_count() -> int:
	var P: Dictionary = run.growth.get("picks", {})
	return int(P.get("steered", 0)) + int(P.get("service", 0)) + int(P.get("boss_reward", 0)) + (L.deepRewards as Array).size()

func _run(seed: int, strat: String, o: Dictionary) -> Dictionary:
	opts = o
	strat_id = strat if STRATS.has(strat) else "gradual"
	S = STRATS[strat_id]
	bot_policy = String(o.get("bot_policy", "balanced"))
	if not PBot.policies().has(bot_policy) and bot_policy != "stand" and bot_policy != "active" and not PSkillBot.profile_ids().has(bot_policy):
		bot_policy = "balanced"
	max_retries = int(o.get("max_retries", 3))
	stop_day = int(o.get("stop_day", 0))
	max_days = int(o.get("max_days", 0))
	endless_segments = int(o.get("endless_segments", 0))
	stub_gates = bool(o.get("stub_gates", false))
	verbose = bool(o.get("verbose", false))
	var start := String(o.get("start", "sword"))
	run = PRun.new_run(seed, start, String(o.get("balance", "")), { "route": o.get("route", []), "mode": String(o.get("mode", PCatalog.run_mode_default())), "legacy_places": bool(o.get("legacy_places", false)) })
	if String(o.get("density_set", "")) != "":
		run.densitySet = String(o.density_set) # 밀도 세트(Q1 비교 후보)
	T = { "combat": 0.0, "cards": 0.0, "screens": 0.0, "rest": 0.0, "dayEnd": 0.0, "boss": 0.0 }
	L = _new_log()
	L.stopDay = stop_day
	clock = 0.0
	var days: int = int(PRun.mode_def(run).days)
	var day_guard := 0
	while day_guard < 20 and not bool(run.get("ended", false)) and String(run.phase) != "cleared":
		day_guard += 1
		if String(run.phase) == "boss_prep":
			_shop_bot()
			if not _boss_gate():
				L.stopReason = "boss_failed"
				break
		if String(run.phase) == "cleared" or bool(run.get("ended", false)):
			break
		if max_days > 0 and int(run.day) > max_days:
			L.stopReason = "max_days"
			break
		var day_start: int = int(run.day)
		var day := day_start
		var gold_start: int = int(run.gold) + int(L.goldSpent)
		var lv_start: int = int(run.growth.level)
		var taken_start := float(L.taken)
		var combat_start := float(T.combat)
		var rest_start := int(L.rests)
		var spent_start := int(L.goldSpent)
		var power_start := _power_count()
		_shop_bot()
		var guard := 0
		while guard < 20 and int(run.day) == day_start and not (stop_day > 0 and day > stop_day):
			guard += 1
			var acts := _actions()
			var hp_max := float(PRun.build(run).hp_max)
			var rest := _find(acts, "rest")
			if float(run.hp) < hp_max * float(S.restBelow) and not rest.is_empty():
				_perform(rest)
				L.rests = int(L.rests) + 1
				T.rest = float(T.rest) + float(MENU.rest)
				clock += float(MENU.rest)
				continue
			var card := _choose_sortie(acts)
			if card.is_empty():
				break
			var s_v = _perform(card)
			if s_v == null or not (s_v is Dictionary) or (s_v as Dictionary).is_empty():
				break
			var s: Dictionary = s_v
			if bool(s.get("mission", false)):
				L.missions = int(L.missions) + 1
			var st := _fight(s)
			if st.status == "won":
				_settle_win(s, st)
				var lost := false
				var ev_next := _handle_event(s)
				if ev_next == "fight":
					L.eventFights = int(L.eventFights) + 1
					var ef := _find(_actions(), "event_fight")
					var st_ef: CombatState = _perform(ef, s) if not ef.is_empty() else null
					st = _fight(s, st_ef)
					if st.status == "won":
						_settle_win(s, st)
					else:
						_settle_loss(s, st)
						lost = true
				elif ev_next == "deep":
					L.deeps = int(L.deeps) + 1
					st = _fight(s)
					if st.status == "won":
						_settle_win(s, st)
					else:
						_settle_loss(s, st)
						lost = true
				if lost:
					continue
				if bool(S.deep) and not bool(s.get("deep", false)) and float(run.hp) >= float(PRun.build(run).hp_max) * 0.5:
					var de := _find(_actions(), "deep_explore")
					if not de.is_empty() and bool(_perform(de, s)):
						L.deeps = int(L.deeps) + 1
						(L.deepRewards as Array).append(String(s.deepReward.kind) if s.get("deepReward", null) != null else "?")
						st = _fight(s)
						if st.status == "won":
							_settle_win(s, st)
						else:
							_settle_loss(s, st)
							continue
				var rh := _find(_actions(), "return_home")
				if not rh.is_empty():
					_perform(rh, s)
				else:
					_log("return_home 행동 없음: " + JSON.stringify(_actions().map(func(a): return a.id)))
			else:
				_settle_loss(s, st)
		(L.levelUpsByDay as Array).append(int(run.growth.level) - lv_start)
		T.dayEnd = float(T.dayEnd) + float(MENU.dayEnd)
		clock += float(MENU.dayEnd)
		(L.goldEarnedByDay as Array).append(int(run.gold) + int(L.goldSpent) - gold_start)
		L.steered = int(run.growth.get("picks", {}).get("steered", 0))
		(L.takenByDay as Array).append(int(round(float(L.taken) - taken_start)))
		(L.matsByDay as Array).append({ "day": day_start, "mats": (run.mats as Dictionary).duplicate(), "gold": int(run.gold), "equipment": (run.equipment as Dictionary).duplicate(), "bag": (run.bag as Array).duplicate() }) # 제작 재료 도달 시점 측정(craft_economy)
		(L.combatSecByDay as Array).append(int(round(float(T.combat) - combat_start)))
		(L.restsByDay as Array).append(int(L.rests) - rest_start)
		(L.spentByDay as Array).append(int(L.goldSpent) - spent_start)
		(L.powerByDay as Array).append(_power_count() - power_start)
		if int(run.day) != day_start: # 패배로 이미 다음 날(구조)
			L.daysLostToDefeat = int(L.daysLostToDefeat) + 1
			continue
		if max_days > 0 and day >= max_days:
			L.stopReason = "max_days"
			break
		if day < days:
			var ed := _find(_actions(), "end_day")
			if ed.is_empty():
				L.stopReason = "no_end_day"
				break
			_perform(ed)
		else:
			L.stopReason = "days"
			break
	if String(run.phase) == "boss_prep" and String(L.stopReason) != "boss_failed" and not (max_days > 0 and int(run.day) > max_days): # 재도전 소진 뒤 추가 시도 없음(이전 보고서의 4번째 행은 이 중복 호출)
		_boss_gate()
	if endless_segments > 0 and String(run.phase) == "cleared":
		_endless_loop()
	return _finish(seed, start)

## 무한 모드(계획서 §10) 봇 진행: 행동 목록의 endless_* 항목만 사용. 구간 보스를 endless_segments회 이기면 마침(endless_quit). 패배는 규칙대로 종료
func _endless_loop() -> void:
	var es := _find(_actions(), "endless_start")
	if es.is_empty() or not bool(_perform(es)):
		return
	var rows := []
	var guard := 0
	while PEndless.active(run) and guard < endless_segments * (PEndless.fights_per_segment() + 4) + 8:
		guard += 1
		var acts := _actions()
		if String(run.phase) == "endless_boss":
			var act := _find(acts, "boss_start")
			var bs_v = _perform(act)
			if bs_v == null or not (bs_v is Dictionary) or (bs_v as Dictionary).is_empty():
				break
			var bs: Dictionary = bs_v
			var st := PFlow.make_boss_encounter(run, bs)
			PBot.run_combat(st, bot_policy, _bot_opts({ "max_sec": BOSS_MAX_SEC }))
			if st.status == "running":
				st.status = "timeout"
				st.delayed.clear()
			T.boss = float(T.boss) + st.t
			clock += st.t
			var sm := st.summary()
			rows.append({ "kind": "boss", "segment": int(bs.segment), "id": String(bs.bossId), "status": st.status, "sec": int(round(st.t)), "hp": int(round(float(st.player.hp))), "bossHpMax": int(round(float(st.boss.hp_max))) if not st.boss.is_empty() else 0, "taken": int(round(float(sm.damage_taken))), "level": int(run.growth.level) })
			if st.status == "won":
				PFlow.settle_boss_victory(run, st)
				PFlow.resolve_all(run, {}, _pick_cb(), _on_pick_cb("screen"))
				if int(PEndless.state(run).bossesWon) >= endless_segments:
					_perform(_find(_actions(), "endless_quit"))
					break
			else:
				PFlow.settle_boss_defeat(run, st)
			continue
		var hp_max := float(PRun.build(run).hp_max)
		var rg := _find(acts, "endless_regroup")
		if float(run.hp) < hp_max * float(S.restBelow) and not rg.is_empty() and bool(rg.enabled):
			_perform(rg)
			L.rests = int(L.rests) + 1
			continue
		var ef := _find(acts, "endless_fight")
		if ef.is_empty():
			break
		var s_v = _perform(ef)
		if s_v == null or not (s_v is Dictionary) or (s_v as Dictionary).is_empty():
			break
		var s: Dictionary = s_v
		var st2 := _fight(s)
		rows.append({ "kind": "fight", "segment": int(s.segment), "fight": int(s.fight), "regionId": String(s.regionId), "formationId": String(s.formationId), "status": st2.status, "sec": int(round(st2.t)), "hp": int(round(float(st2.player.hp))), "taken": int(round(float(st2.summary().damage_taken))), "level": int(run.growth.level) })
		if st2.status == "won":
			_settle_win(s, st2)
			var rh := _find(_actions(), "return_home")
			if not rh.is_empty():
				_perform(rh)
		else:
			_settle_loss(s, st2)
	L.endless = PEndless.summary(run)
	L.endlessRows = rows

func _finish(seed: int, start: String) -> Dictionary:
	var g: Dictionary = run.growth
	# 성장 선택 간격: 선택 사이의 실제 경과 초(가정 메뉴 시간 포함). 첫 선택까지의 시간도 기록
	var ts := []
	for e in L.events:
		if String(e.key) != "skip":
			ts.append(int(e.t))
	ts.sort()
	var gaps := []
	for i in range(1, ts.size()):
		gaps.append(int(ts[i]) - int(ts[i - 1]))
	var gsum := 0
	for v in gaps:
		gsum += int(v)
	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort()
	L.pickGapAvg = int(round(float(gsum) / float(gaps.size()))) if gaps.size() > 0 else 0
	L.pickGapMed = int(sorted_gaps[int(floor(float(gaps.size()) / 2.0))]) if gaps.size() > 0 else 0
	L.firstPickSec = int(ts[0]) if ts.size() > 0 else 0
	L.picksTotal = ts.size()
	var P: Dictionary = g.get("picks", {})
	L.picks = P.duplicate()
	var cp := 0
	for k in COMBAT_PICK_KINDS:
		cp += int(P.get(k, 0))
	L.combatPicks = cp
	L.servicePicks = int(P.get("service", 0))
	L.bossRewardPicks = int(P.get("boss_reward", 0))
	L.skips = int(P.get("skip", 0))
	L.rarePicksN = (L.rarePicks as Array).size()
	L.dbaPct = int(round(float(L.dba) / float(maxi(1, int(L.killedN))) * 100.0)) if int(L.spawned) > 0 else 0
	L.execPerSpawn = (round(float(L.executed) / float(L.spawned) * 100.0) / 100.0) if int(L.spawned) > 0 else 0.0
	L.taken = round(float(L.taken))
	L.bossTaken = round(float(L.bossTaken))
	L.level = int(g.level)
	L.gold = int(run.gold)
	var ge: Array = L.goldEarnedByDay
	var gsum2 := 0
	for v in ge:
		gsum2 += int(v)
	L.goldPerDay = int(round(float(gsum2) / float(ge.size()))) if ge.size() > 0 else 0
	L.equipN = (L.equipBought as Array).size()
	L.deepRewardText = ",".join(L.deepRewards)
	L.mats = (run.mats as Dictionary).duplicate()
	var craftable := []
	var partial := []
	for co in PRun.craft_options(run): # 제작 재료 접근성(정산된 재료·보유 장비 기준): 즉시 제작 가능 / 재료 일부
		var have_all := true
		var have_any := false
		for ing in co.get("ingredients", []):
			if int(ing.get("have", 0)) >= int(ing.get("n", 1)):
				have_any = true
			else:
				have_all = false
		if have_all:
			craftable.append(String(co.id))
		elif have_any:
			partial.append(String(co.id))
	L.craftable = craftable
	L.craftPartial = partial
	L.route = (run.get("route", []) as Array).duplicate()
	L.hpBeforeBoss = float(run.hp)
	L.build = build_text(g)
	var last_b: Dictionary = L.bosses[(L.bosses as Array).size() - 1] if (L.bosses as Array).size() > 0 else { "status": "none", "sec": 0, "hp": 0, "bossHp": 0 }
	var bparts := []
	for b in L.bosses:
		bparts.append("%s:%s@%ds" % [String(b.id), String(b.status), int(b.sec)])
	L.boss = " ".join(bparts)
	L.bossStatus = "won" if (String(run.phase) == "cleared" or bool(run.get("mainCleared", false))) else String(last_b.status)
	L.cleared = String(run.phase) == "cleared" or bool(run.get("mainCleared", false))
	if bool(L.cleared):
		L.stopReason = "cleared"
	# 합계는 여기서 한 번만: 버킷 합 = 시계(clock)와 같아야 한다(검증)
	var sum := 0.0
	for k in T:
		sum += float(T[k])
	if absf(sum - clock) > 0.5:
		push_warning("시간 계정 불일치 %.1f vs %.1f" % [sum, clock])
	L.timeAccountOk = absf(sum - clock) <= 0.5
	var tm := {}
	for k in T:
		tm[String(k)] = int(round(float(T[k])))
	L.time = tm
	L.combatSec = int(round(float(T.combat)))
	L.simulatedSec = int(round(float(T.combat) + float(T.boss)))
	L.assumedSec = int(round(float(T.cards) + float(T.screens) + float(T.rest) + float(T.dayEnd)))
	L.totalMin = round(sum / 60.0 * 10.0) / 10.0
	L.combatMin = round(float(T.combat) / 60.0 * 10.0) / 10.0
	L.cardMin = round(float(T.cards) / 60.0 * 10.0) / 10.0
	L.menuMin = round(float(L.assumedSec) / 60.0 * 10.0) / 10.0
	L.bossMin = round(float(T.boss) / 60.0 * 10.0) / 10.0
	L.seed = seed
	L.strategy = strat_id
	L.strategyName = String(S.name)
	L.start = start
	L.day = int(run.day)
	L.phase = String(run.phase)
	L.balance = String(run.balance)
	L.difficulty = String(run.difficulty)
	L.bossHpSet = String(run.bossHpSet)
	L.bot_policy = bot_policy
	L.rules_version = String(GAME.VERSION)
	L.os = OS.get_name()
	L.engine = String(Engine.get_version_info().string)
	L.statsVerify = PStats.verify(run)
	L.run_state = run # 체크포인트 측정용: 그 시점의 실제 회차 상태(빌드 전체). 보고서에는 넣지 않는다
	L.supportOnlySec = round(float(L.get("supportOnlySec", 0.0)) * 10.0) / 10.0
	L.thinTailSec = round(float(L.get("thinTailSec", 0.0)) * 10.0) / 10.0
	L.noTargetSec = round(float(L.get("noTargetSec", 0.0)) * 10.0) / 10.0
	L.restForced = int(run.get("stats", {}).get("rest_forced", 0))
	L.restChosen = int(run.get("stats", {}).get("rest_chosen", 0))
	return L

## 빌드 요약 문자열(run_sim.js log.build)
static func build_text(g: Dictionary) -> String:
	var ws := []
	for w in g.weapons:
		ws.append("%s%d%s" % [String(w.id), int(w.level), ("[" + "+".join(w.mods) + "]") if (w.mods as Array).size() > 0 else ""])
	var cs := []
	for k in g.commons:
		cs.append("%s%d" % [String(k), int(g.commons[k])])
	var ps := []
	for k in g.passives:
		ps.append("%s%d" % [String(k), int(g.passives[k])])
	var e = g.skills.get("e", null)
	return "%s | 공통 %s | E %s | 패시브 %s" % [" ".join(ws), ",".join(cs) if cs.size() > 0 else "-", ("%s%d" % [String(e.id), int(e.level)]) if e != null else "-", ",".join(ps) if ps.size() > 0 else "-"]
