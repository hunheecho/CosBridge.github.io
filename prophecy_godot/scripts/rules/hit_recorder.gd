class_name PHitRecorder
extends RefCounted
## 피격·공격 관측 계측(선택, docs/BOT_FRAMEWORK.md §통계 계약·§피격 태그). st.recorder = PHitRecorder.new()로 붙이면 CombatState가
## on_step_begin/on_hit/on_reject/on_step_end를 부른다. 읽기만 하고 규칙·난수를 건드리지 않는다(recorder가 null이면 훅 자체가 실행되지 않는다).
## - 공격 관측(attack_id별): 예고 시작·고정·활성·종료 단계, 결과 killed_during_telegraph / cancelled / executed / hit. 지원 전용(치료 시전)·구조물은 공격 예고가 없어 분모에 들어가지 않는다.
## - 피격 사건: step/t, 출처, 명목·경감 후·보호막 흡수·유효(실제 체력 감소)·과잉, 체력 전후, 회피/피격 보호 상태, 회피 재사용 잔여, 마지막 입력, 그 순간 봇이 인식한 위협(bot_ctx), 태그.
## - 거절된 타격: 이유(dodge_invuln / hit_protection / inactive / boss_dead)별로 따로 세고 피해에 더하지 않는다.
## - 검산: 최종 HP = 초기 HP + 회복 + 최대 체력 증가에 따른 명시적 증가 − 유효 피해 (unexplained가 0이어야 한다). 보호막은 부여/흡수/만료(덮어쓰기 포함)로 분리.
## 피격 태그(§8, 중복 허용, '당시 조건'이지 원인 확정이 아니다): not_perceived · perceived_no_input · dodge_rejected_cooldown · dodge_blocked_terrain · after_dodge_025 ·
##   hit_by_other_while_escaping · walking_out · overlap · unclassified. 봇 문맥(bot_ctx)이 없으면(사람 입력) not_perceived/perceived_* 는 붙이지 않는다.

const STEP := 1.0 / 120.0
const AFTER_DODGE_WINDOW := 0.25   # 시험 관찰 창
const RECENT_WINDOW := 0.5         # 거절된 회피 누름·지형 차단을 '최근'으로 보는 창

var hits: Array = []
var rejected: Array = []
var reject_counts: Dictionary = {}
var attacks: Dictionary = {}        # attack_id → 관측
var attack_counts: Dictionary = { "started": 0, "locked": 0, "executed": 0, "killed_during_telegraph": 0, "cancelled": 0, "hit": 0, "open": 0 }
var tags: Dictionary = {}
var shield: Dictionary = { "granted": 0.0, "absorbed": 0.0, "expired": 0.0, "initial": 0.0 }
var hp: Dictionary = { "initial": 0.0, "gained": 0.0, "effective": 0.0, "overkill": 0.0, "final": 0.0, "unexplained": 0.0 }
var dodge_events: Array = []        # {start_step, end_step, end, dist}
var presses: Array = []             # 회피 누름 시도 {step, accepted, reason}
var bot_ctx: Dictionary = {}        # 봇이 매 단계 넣는 문맥(없으면 {})
var max_concurrent: Dictionary = { "enemies": 0, "telegraphs": 0, "projectiles": 0, "zones": 0 }
var _started := false
var _last_hp := 0.0
var _last_shield := 0.0
var _step_effective := 0.0
var _step_absorbed := 0.0
var _last_input: Dictionary = {}
var _dodge_start_step := -1
var _last_dodge_end_step := -1
var _last_dodge_end := ""
var _last_reject_step := -1
var _exec_base: Dictionary = {}     # attack_id → 시작 시 실행 수
var _open: Dictionary = {}          # attack_id → true(현재 화면에 있는 공격)
var _last_step := 0

func _exec_count(e: Dictionary) -> int:
	return int(e.get("executed", 0)) + int(e.get("bites", 0)) + int(e.get("dashes", 0))

func _begin(st: CombatState) -> void:
	_started = true
	_last_hp = float(st.player.hp)
	_last_shield = float(st.player.shield)
	hp.initial = _last_hp
	shield.initial = _last_shield

# ---------- 훅(CombatState가 부른다) ----------
func on_step_begin(st: CombatState, input: Dictionary) -> void:
	if not _started:
		_begin(st)
	_last_step = int(st.step_n)
	_last_input = input.duplicate()
	var p: Dictionary = st.player
	if bool(input.get("dodge_press", false)) and st.status == "running" and float(st.intro) <= 0.0:
		var accepted: bool = not bool(p.dodge_active) and float(p.dodge_cd) <= 0.0
		var reason := "" if accepted else ("active" if bool(p.dodge_active) else "cooldown")
		presses.append({ "step": int(st.step_n), "t": snapped(float(st.t), 0.001), "accepted": accepted, "reason": reason, "cd_left": snapped(float(p.dodge_cd), 0.001) })
		if not accepted and reason == "cooldown":
			_last_reject_step = int(st.step_n)

func on_reject(st: CombatState, amount: float, src: String, attacker, reason: String) -> void:
	reject_counts[reason] = int(reject_counts.get(reason, 0)) + 1
	rejected.append({ "step": int(st.step_n), "t": snapped(float(st.t), 0.001), "src": src, "amount": amount, "reason": reason, "attack_id": _attack_id_of(st, src, attacker) })

func on_hit(st: CombatState, d: Dictionary) -> void:
	var p: Dictionary = st.player
	var attacker = d.get("attacker")
	var aid := _attack_id_of(st, String(d.src), attacker)
	var effective := float(d.effective)
	_step_effective += effective
	_step_absorbed += float(d.absorbed)
	hp.effective = float(hp.effective) + effective
	hp.overkill = float(hp.overkill) + float(d.overkill)
	shield.absorbed = float(shield.absorbed) + float(d.absorbed)
	var ev := { "step": int(st.step_n), "t": snapped(float(st.t), 0.001), "src": String(d.src), "attack_id": aid,
		"attacker_id": (int(attacker.id) if attacker != null else -1), "attacker_type": (String(attacker.type) if attacker != null else ""), "attacker_tier": (String(attacker.get("tier", "normal")) if attacker != null else ""),
		"nominal": float(d.nominal), "requested": float(d.requested), "absorbed": float(d.absorbed), "effective": effective, "overkill": float(d.overkill),
		"hp_before": float(d.hp_before), "hp_after": float(d.hp_after), "shield_before": float(d.shield_before), "shield_after": float(d.shield_after),
		"dodge_active": bool(p.dodge_active), "hit_prot_before": float(d.hit_prot_before), "dodge_cd": snapped(float(p.dodge_cd), 0.001), "big_hit": bool(d.get("big_hit", false)),
		"input": _last_input.duplicate(), "perceived": (bot_ctx.get("perceived", {}) as Dictionary).keys() if not bot_ctx.is_empty() else [], "escape_id": String(bot_ctx.get("escape_id", "")) }
	ev.tags = _tags_for(st, ev)
	for tg in ev.tags:
		tags[tg] = int(tags.get(tg, 0)) + 1
	hits.append(ev)
	if attacks.has(aid):
		attacks[aid].hits = int(attacks[aid].hits) + 1
	elif aid.begins_with("e"): # 부분 접미사(:lane0 등)는 본체 공격에 귀속
		var base: String = aid.split(":")[0]
		if attacks.has(base):
			attacks[base].hits = int(attacks[base].hits) + 1

func on_step_end(st: CombatState) -> void:
	if not _started:
		_begin(st)
	var p: Dictionary = st.player
	# 체력 검산: 마지막 단계 끝 이후(단계 밖 직접 호출 포함)의 유효 피해를 뺀 나머지 변화 = 회복·최대 체력 증가(양수) 또는 설명 안 되는 감소
	var dh: float = float(p.hp) - _last_hp + _step_effective
	if dh > 1e-9:
		hp.gained = float(hp.gained) + dh
	elif dh < -1e-9:
		hp.unexplained = float(hp.unexplained) + dh
	_last_hp = float(p.hp)
	var ds: float = float(p.shield) - _last_shield + _step_absorbed
	if ds > 1e-9:
		shield.granted = float(shield.granted) + ds
	elif ds < -1e-9:
		shield.expired = float(shield.expired) - ds
	_last_shield = float(p.shield)
	_step_effective = 0.0
	_step_absorbed = 0.0
	hp.final = _last_hp
	# 회피 시작·종료
	if bool(p.dodge_active) and _dodge_start_step < 0:
		_dodge_start_step = int(st.step_n)
	elif not bool(p.dodge_active) and _dodge_start_step >= 0:
		_last_dodge_end_step = int(st.step_n)
		_last_dodge_end = String(p.dodge_end)
		dodge_events.append({ "start_step": _dodge_start_step, "end_step": int(st.step_n), "end": _last_dodge_end, "dist": snapped(float(p.dodge_dist), 0.1) })
		_dodge_start_step = -1
	# 공격 관측: 화면 예고(PObserve.threats_of)로 시작·고정·활성·종료를 본다
	var ths: Array = []
	PObserve.threats_of(st, ths)
	var seen := {}
	var tele_n := 0
	for th in ths:
		var id := String(th.attack_id)
		if not id.begins_with("e"):
			continue
		tele_n += 1
		var base: String = id.split(":")[0]
		seen[base] = true
		var ph := String(th.phase)
		if not attacks.has(base):
			var e := _enemy_by_id(st, int(th.enemy_id))
			attacks[base] = { "attack_id": base, "enemy_id": int(th.enemy_id), "type": String(th.type), "tier": (String(e.get("tier", "normal")) if not e.is_empty() else ""), "label": String(th.label),
				"start_step": int(st.step_n), "start_t": snapped(float(st.t), 0.001), "lock_step": -1, "active_step": -1, "end_step": -1, "outcome": "open", "hits": 0, "boss": bool(e.get("boss", false)) }
			_exec_base[base] = _exec_count(e) if not e.is_empty() else 0
			_open[base] = true
			attack_counts.started = int(attack_counts.started) + 1
		var a: Dictionary = attacks[base]
		if (ph == "lock" or ph == "active") and int(a.lock_step) < 0:
			a.lock_step = int(st.step_n)
			attack_counts.locked = int(attack_counts.locked) + 1
		if ph == "active" and int(a.active_step) < 0:
			a.active_step = int(st.step_n)
	for base in _open.keys():
		if seen.has(base):
			continue
		_close_attack(st, String(base))
	# 동시 최대(관찰 항목)
	var en := 0
	for e in st.enemies:
		if not bool(e.dead) and not bool(e.get("structure", false)):
			en += 1
	var np := 0
	for pr in st.projectiles:
		if String(pr.get("owner", "")) == "enemy":
			np += 1
	var nz := 0
	for z in st.zones:
		if String(z.type) in ["spore", "frostzone", "hazard", "web", "ice", "rubble"]:
			nz += 1
	max_concurrent.enemies = maxi(int(max_concurrent.enemies), en)
	max_concurrent.telegraphs = maxi(int(max_concurrent.telegraphs), tele_n)
	max_concurrent.projectiles = maxi(int(max_concurrent.projectiles), np)
	max_concurrent.zones = maxi(int(max_concurrent.zones), nz)

func _close_attack(st: CombatState, base: String) -> void:
	var a: Dictionary = attacks[base]
	a.end_step = int(st.step_n)
	var e := _enemy_by_id(st, int(a.enemy_id))
	var executed: bool = not e.is_empty() and _exec_count(e) > int(_exec_base.get(base, 0))
	if e.is_empty() or bool(e.get("dead", false)) or bool(e.get("exploded", false)):
		# 폭탄 운반체는 실행하면서 죽는다(exploded)
		if executed or bool(e.get("exploded", false)):
			a.outcome = "hit" if int(a.hits) > 0 else "executed"
		else:
			a.outcome = "killed_during_telegraph"
	elif executed:
		a.outcome = "hit" if int(a.hits) > 0 else "executed"
	else:
		a.outcome = "cancelled"
	attack_counts[a.outcome] = int(attack_counts.get(a.outcome, 0)) + 1
	if a.outcome == "hit":
		attack_counts.executed = int(attack_counts.executed) + 1
	_open.erase(base)
	_exec_base.erase(base)

## 전투가 끝난 뒤 아직 열린 공격을 닫는다(결과 요약 전에 1회)
func finish(st: CombatState) -> void:
	for base in _open.keys():
		_close_attack(st, String(base))
	hp.final = float(st.player.hp)
	attack_counts.open = 0

static func _enemy_by_id(st: CombatState, id: int) -> Dictionary:
	for e in st.enemies:
		if int(e.id) == id:
			return e
	return {}

## 피해 출처 → attack_id. 적 개체가 있으면 e<id>#<n>, 지역은 플레이어를 담은 지역 키, 표식은 보스 표식
func _attack_id_of(st: CombatState, src: String, attacker) -> String:
	if attacker != null and typeof(attacker) == TYPE_DICTIONARY and attacker.has("id"):
		return "e%d#%d" % [int(attacker.id), int(attacker.get("attack_n", 0))]
	var p: Dictionary = st.player
	if src == "zone" or src == "frostzone" or src == "hazard":
		var want := "spore" if src == "zone" else src
		for z in st.zones:
			var zt := String(z.type)
			if (zt == want or (src == "zone" and zt == "hazard")) and PGeom.dist(float(z.x), float(z.y), float(p.x), float(p.y)) <= float(z.r) + float(p.r):
				return "zone:%s:%d:%d" % [zt, int(round(float(z.x))), int(round(float(z.y)))]
		return "zone:%s" % src
	if src == "boss_mark" and not st.boss.is_empty():
		var marks: Array = st.boss.get("marks", [])
		for i in marks.size():
			var mk: Dictionary = marks[i]
			if PGeom.dist(float(mk.x), float(mk.y), float(p.x), float(p.y)) <= float(mk.r) + float(p.r):
				return "e%d#%d:mark%d" % [int(st.boss.id), int(st.boss.get("attack_n", 0)), i]
		return "e%d#%d:mark" % [int(st.boss.id), int(st.boss.get("attack_n", 0))]
	if src == "arrow" or src == "hex" or src == "shock":
		return "proj:" + src
	return "src:" + src

## §8 태그(당시 조건)
func _tags_for(st: CombatState, ev: Dictionary) -> Array:
	var out := []
	var p: Dictionary = st.player
	var n: int = int(st.step_n)
	var aid := String(ev.attack_id)
	var base: String = aid.split(":")[0]
	var has_ctx: bool = not bot_ctx.is_empty()
	if has_ctx:
		var perceived: Dictionary = bot_ctx.get("perceived", {})
		var recog_step: int = n + 1
		for pid in perceived: # 정확히 같은 id 또는 같은 공격 인스턴스의 부분(e5#2:proj0 ↔ e5#2)
			var ps := String(pid)
			if ps == aid or ps.split(":")[0] == base:
				recog_step = mini(recog_step, int(perceived[pid]))
		var known: bool = recog_step <= n
		if not known and not aid.begins_with("src:"):
			out.append("not_perceived")
		elif known:
			var moving := bool(bot_ctx.get("moving", false))
			var pressed_since := false
			for pz in presses:
				if int(pz.step) >= recog_step:
					pressed_since = true
					break
			if not moving and not pressed_since and not bool(p.dodge_active):
				out.append("perceived_no_input")
	if _last_reject_step >= 0 and float(n - _last_reject_step) * STEP <= RECENT_WINDOW:
		out.append("dodge_rejected_cooldown")
	if _last_dodge_end_step >= 0 and _last_dodge_end == "blocked" and float(n - _last_dodge_end_step) * STEP <= RECENT_WINDOW:
		out.append("dodge_blocked_terrain")
	if _last_dodge_end_step >= 0 and float(n - _last_dodge_end_step) * STEP <= AFTER_DODGE_WINDOW:
		out.append("after_dodge_025")
	if has_ctx:
		var esc := String(bot_ctx.get("escape_id", ""))
		if esc != "" and esc != aid and esc.split(":")[0] != base:
			out.append("hit_by_other_while_escaping")
		if esc != "" and (esc == aid or esc.split(":")[0] == base) and bool(bot_ctx.get("moving", false)) and not bool(p.dodge_active):
			out.append("walking_out")
		var inside: Array = bot_ctx.get("inside", [])
		if inside.size() >= 2:
			out.append("overlap")
	if out.is_empty():
		out.append("unclassified")
	return out

# ---------- 보고 ----------
func checksum() -> Dictionary:
	var expect: float = float(hp.initial) + float(hp.gained) - float(hp.effective)
	return { "initial": float(hp.initial), "gained": float(hp.gained), "effective": float(hp.effective), "overkill": float(hp.overkill), "final": float(hp.final), "expected_final": expect,
		"ok": absf(expect - float(hp.final)) <= 1e-6 and absf(float(hp.unexplained)) <= 1e-6, "unexplained": float(hp.unexplained),
		"shield_initial": float(shield.initial), "shield_granted": float(shield.granted), "shield_absorbed": float(shield.absorbed), "shield_expired": float(shield.expired) }

func report() -> Dictionary:
	var by_src := {}
	var by_src_n := {}
	for h in hits:
		by_src[h.src] = float(by_src.get(h.src, 0.0)) + float(h.effective)
		by_src_n[h.src] = int(by_src_n.get(h.src, 0)) + 1
	var blocked := 0
	var dists := []
	for d in dodge_events:
		dists.append(float(d.dist))
		if String(d.end) == "blocked":
			blocked += 1
	var rej_press := 0
	for pz in presses:
		if not bool(pz.accepted):
			rej_press += 1
	var by_type := {}
	for k in attacks:
		var a: Dictionary = attacks[k]
		var key := String(a.type)
		if not by_type.has(key):
			by_type[key] = { "started": 0, "executed": 0, "hit": 0, "killed_during_telegraph": 0, "cancelled": 0, "open": 0 }
		by_type[key].started = int(by_type[key].started) + 1
		var oc := String(a.outcome)
		by_type[key][oc] = int(by_type[key].get(oc, 0)) + 1
		if oc == "hit":
			by_type[key].executed = int(by_type[key].executed) + 1
	return { "hits": hits.size(), "effective_total": float(hp.effective), "by_src": by_src, "by_src_hits": by_src_n, "rejected": reject_counts.duplicate(), "tags": tags.duplicate(),
		"attacks": attack_counts.duplicate(), "attacks_by_type": by_type, "checksum": checksum(), "dodges": dodge_events.size(), "dodge_blocked": blocked, "dodge_dists": dists,
		"press_attempts": presses.size(), "press_rejected": rej_press, "max_concurrent": max_concurrent.duplicate() }
