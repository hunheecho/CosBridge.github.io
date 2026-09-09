extends SceneTree
## 조사 전용: **회피를 넣은 뒤 정예의 '연계 완주'가 줄어든 원인**을 횟수가 아니라 **행동 순서**로 가른다.
##   godot --headless --path prophecy_godot -s tools/probe_dodge.gd
## 규칙·수치를 하나도 바꾸지 않는다. 회피를 끈 판은 비교 전용 스위치(PEnemiesNew.set_dodge_on)로만 만든다.
##
## 가려야 할 세 가지(사용자 지시)
##  ㉮ 연계가 **진행 중인데 회피로 끊겼는가**       → 회피 시작 순간에 연계가 열려 있었는가로 센다
##  ㉯ 연계 **종료 후 다음 공격 시작이 늦어졌는가** → 공격과 공격 사이 빈 시간(gap)의 중앙값을 회피 켬/끔으로 비교한다
##  ㉰ **적이 먼저 죽어** 완주할 시간이 줄었는가    → 처치 시간(ttk)과 살아 있던 시간을 켬/끔으로 비교한다
##
## 그리고 요구 위반을 직접 잡는다:
##  · **공격 준비·실행(COMMITTED) 중에 회피가 시작됐는가** — 회피 직전 상태가 COMMITTED였으면 위반
##  · **회피 단계가 도는 동안 COMMITTED 상태였는가** — 프레임마다 확인
##
## 장면은 tests/elites_bot_measure.gd와 같다(시험실 · 정예 1마리 · 같은 COMBO 표) — 그래야 그때의 숫자와 이어 읽힌다.

const STEP := 1.0 / 120.0
const MAX_SEC := 90.0
const SEEDS := [1, 2, 3]
const POLICIES := ["balanced", "aggressive"]
const LOG_SEED := 1
const LOG_POLICY := "balanced"

## 연계 판별표: [시작 상태, 완주로 볼 상태들]. tests/elites_bot_measure.gd와 **같은 값**이다
const COMBO := {
	"elite_archer": ["aim", ["fan_lock"]],
	"elite_blademaster": ["dash1_aim", ["slam_aim"]],
	"elite_fang": ["bite_aim", ["leap"]],
	"elite_plaguecaller": ["throw_aim", ["swell"]],
	"elite_chainbreaker": ["chain_aim", ["slam_lock", "retract"]],
	"elite_standard": ["plant_aim", ["plant_aim", "slash_aim"]],
	"elite_miner": ["dive", ["erupt"]],
}
## 사용자가 이름을 든 세 종류(연계 완주가 줄었다고 보고된 것)
const FOCUS := ["elite_standard", "elite_miner", "elite_archer"]

func mk(seed_v: int, act: int) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": act, "fixed_build": true })
	st.spawn_hold = true
	return st

func committed(tp: String, s: String) -> bool:
	return (PEnemiesNew.COMMITTED.get(tp, []) as Array).has(s)

## 정예 1마리 대 봇 1판. 상태 전이 순서를 통째로 남기고, 그 순서에서 세 원인을 센다.
func one(tp: String, policy: String, seed_v: int, dodge_on: bool) -> Dictionary:
	PEnemiesNew.set_dodge_on(dodge_on)
	var st := mk(seed_v, 1)
	var e := st.spawn_enemy(tp, st.player.x + 260.0, st.player.y)
	var bot := PBot.new(policy)
	var cs: Array = COMBO[tp]
	var start_state := String(cs[0])
	var finish_states: Array = cs[1]
	var last := String(e.state)
	var last_phase := ""
	var log: Array = []               # [t, from, to, dodge_phase]
	var combos := 0
	var finishes := 0
	var chain_open := false
	var dodge_in_chain := 0
	var dodge_from_committed := 0
	var dodge_uses := 0
	var locked_sec := 0.0
	var committed_while_locked := 0
	var atk_starts := 0
	var gaps: Array = []              # 공격이 끝난 뒤 다음 공격이 시작되기까지의 초
	var last_atk_end := -1.0
	var ttk := -1.0
	var n := int(MAX_SEC / STEP)
	for i in n:
		st.step(bot.step_input(st), STEP)
		if bool(e.dead):
			if ttk < 0.0:
				ttk = st.t
			break
		if bool(st.player.dead):
			break
		var ph := String(e.get("dodge_phase", ""))
		if ph != "":
			locked_sec += STEP
			if committed(tp, String(e.state)):
				committed_while_locked += 1
		last_phase = ph
		var s := String(e.state)
		if s == last:
			continue
		log.append([float(st.t), last, s, ph])
		# 연계 시작·완주(elites_bot_measure와 같은 셈법)
		if s == start_state and last == "approach":
			combos += 1
		if finish_states.has(s):
			finishes += 1
		# 연계가 열렸는가(시작 → 완주 사이)
		if s == start_state:
			chain_open = true
		elif finish_states.has(s) or s == "approach" or s == "recover":
			chain_open = false
		# 공격 시작·끝(COMMITTED 진입/이탈) → 공격 사이 빈 시간
		var was_c := committed(tp, last)
		var now_c := committed(tp, s)
		if now_c and not was_c:
			atk_starts += 1
			if last_atk_end >= 0.0:
				gaps.append(float(st.t) - last_atk_end)
		if was_c and not now_c:
			last_atk_end = float(st.t)
		# 회피 시작 순간의 성격
		if s == "dodge":
			dodge_uses += 1
			if chain_open:
				dodge_in_chain += 1
			if was_c:
				dodge_from_committed += 1
			chain_open = false
		last = s
	PEnemiesNew.set_dodge_on(true)
	return { "ttk": ttk, "alive": (ttk if ttk > 0.0 else float(st.t)), "combos": combos, "finishes": finishes,
		"atk_starts": atk_starts, "gaps": gaps, "log": log, "hp_left": maxf(0.0, float(e.hp)),
		"dodge_uses": dodge_uses, "dodge_seen": int(e.get("dodge_seen", 0)), "dodge_in_chain": dodge_in_chain,
		"dodge_from_committed": dodge_from_committed, "locked_sec": locked_sec,
		"committed_while_locked": committed_while_locked, "last_phase": last_phase,
		"player_dead": bool(st.player.dead), "executed": int(st.metrics_for(e).executed) }

func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

func avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())

func sgn(v: float, unit: String) -> String:
	return ("+%.2f%s" % [v, unit]) if v >= 0.0 else ("%.2f%s" % [v, unit])

func _init() -> void:
	var md := []
	md.append("# 조사: 회피가 정예의 '연계 완주'를 줄였는가 — 행동 순서로 가른 결과")
	md.append("")
	md.append("생성 `tools/probe_dodge.gd` · 시험실 장면(정예 1마리 · 1막 시작 빌드 · 최대 %d초) · 봇 %s · 시드 %s." % [int(MAX_SEC), str(POLICIES), str(SEEDS)])
	md.append("장면·연계 판별표는 `tests/elites_bot_measure.gd`와 **같은 값**이다. **봇 승패는 판정이 아니다.**")
	md.append("회피를 끈 판은 비교 전용 스위치 `PEnemiesNew.set_dodge_on(false)`로만 만든다 — 자료·수치는 그대로다.")
	md.append("")

	var rows := {}
	for tp in PEnemiesNew.ELITE_TYPES:
		var acc := { "on": { "fin": [], "cmb": [], "ttk": [], "gap": [], "atk": [], "lock": [], "exec": [] },
			"off": { "fin": [], "cmb": [], "ttk": [], "gap": [], "atk": [], "lock": [], "exec": [] },
			"in_chain": 0, "from_committed": 0, "uses": 0, "locked_committed": 0 }
		for pol in POLICIES:
			for sd in SEEDS:
				for on in [true, false]:
					var r := one(String(tp), String(pol), int(sd), bool(on))
					var key := "on" if bool(on) else "off"
					var A: Dictionary = acc[key]
					(A.fin as Array).append(float(r.finishes))
					(A.cmb as Array).append(float(r.combos))
					(A.ttk as Array).append(float(r.alive))
					(A.atk as Array).append(float(r.atk_starts))
					(A.exec as Array).append(float(r.executed))
					(A.gap as Array).append(med(r.gaps))
					(A.lock as Array).append(float(r.locked_sec))
					if bool(on):
						acc.in_chain = int(acc.in_chain) + int(r.dodge_in_chain)
						acc.from_committed = int(acc.from_committed) + int(r.dodge_from_committed)
						acc.uses = int(acc.uses) + int(r.dodge_uses)
						acc.locked_committed = int(acc.locked_committed) + int(r.committed_while_locked)
		rows[String(tp)] = acc

	# ---------- 1. 세 원인 표 ----------
	md.append("## 1. 회피 켬/끔 — 같은 시드·같은 봇으로 나란히")
	md.append("")
	md.append("| 정예 | 연계 완주(끔→켬) | 연계 시작(끔→켬) | 공격 개시 수(끔→켬) | **공격 사이 빈 시간 중앙값**(끔→켬) | 살아 있던 시간(끔→켬) | 회피 발동 | 회피에 묶인 시간 |")
	md.append("|---|---|---|---|---|---|---:|---:|")
	for tp in PEnemiesNew.ELITE_TYPES:
		var A: Dictionary = rows[String(tp)]
		var on: Dictionary = A.on
		var off: Dictionary = A.off
		md.append("| %s | %.1f → %.1f (%s) | %.1f → %.1f | %.1f → %.1f | %.2f초 → %.2f초 (**%s**) | %.1f초 → %.1f초 (%s) | %d회 | %.1f초 |" % [
			String(PCatalog.enemy(String(tp)).name),
			avg(off.fin), avg(on.fin), sgn(avg(on.fin) - avg(off.fin), "회"),
			avg(off.cmb), avg(on.cmb),
			avg(off.atk), avg(on.atk),
			avg(off.gap), avg(on.gap), sgn(avg(on.gap) - avg(off.gap), "초"),
			avg(off.ttk), avg(on.ttk), sgn(avg(on.ttk) - avg(off.ttk), "초"),
			int(A.uses), avg(on.lock)])
	md.append("")

	# ---------- 2. 판정 ----------
	md.append("## 2. 세 원인 중 무엇인가 — 행동 순서가 말하는 것")
	md.append("")
	md.append("| 정예 | ㉮ 연계 진행 중 회피로 끊김 | ㉯ 다음 공격 시작 지연 | ㉰ 먼저 죽어 시간이 줄었나 | **요구 위반: 공격 준비·실행 중 회피** |")
	md.append("|---|---|---|---|---|")
	var violations := []
	for tp in PEnemiesNew.ELITE_TYPES:
		var A: Dictionary = rows[String(tp)]
		var on: Dictionary = A.on
		var off: Dictionary = A.off
		var dgap: float = avg(on.gap) - avg(off.gap)
		var dttk: float = avg(on.ttk) - avg(off.ttk)
		if int(A.from_committed) > 0 or int(A.locked_committed) > 0:
			violations.append(String(tp))
		md.append("| %s | %s | %s | %s | %s |" % [
			String(PCatalog.enemy(String(tp)).name),
			("**%d회**" % int(A.in_chain)) if int(A.in_chain) > 0 else "0회 — 아니다",
			("**그렇다(%s)**" % sgn(dgap, "초")) if dgap > 0.01 else "아니다(%s)" % sgn(dgap, "초"),
			("**그렇다(%s)**" % sgn(dttk, "초")) if dttk < -0.05 else "아니다(%s)" % sgn(dttk, "초"),
			("**있다 — 회피 직전 COMMITTED %d회 · 회피 단계 중 COMMITTED %d프레임**" % [int(A.from_committed), int(A.locked_committed)]) if (int(A.from_committed) > 0 or int(A.locked_committed) > 0) else "없다"])
	md.append("")
	md.append("- 요구 위반이 나온 종류: **%s**" % ("없다" if violations.is_empty() else ", ".join(PackedStringArray(violations))))
	md.append("- 회피가 묶는 시간 = 반응 지연 + 이동 + 추스르는 틈. 이 동안 `elite_may_start`가 막히므로 **새 공격을 시작하지 않는다**(설계 그대로).")
	md.append("")

	# ---------- 3. 대표 장면의 행동 순서 ----------
	md.append("## 3. 대표 장면의 행동 순서(상태 전이 로그) — 봇 `%s` · 시드 %d" % [LOG_POLICY, LOG_SEED])
	md.append("")
	for tp in FOCUS:
		md.append("### %s" % String(PCatalog.enemy(String(tp)).name))
		md.append("")
		for on in [false, true]:
			var r := one(String(tp), LOG_POLICY, LOG_SEED, bool(on))
			md.append("**회피 %s** — 연계 시작 %d · 완주 %d · 공격 개시 %d · 살아 있던 시간 %.1f초 · 회피 %d회(연계 중 %d회 · COMMITTED 직후 %d회)" % [
				("켬" if bool(on) else "끔"), int(r.combos), int(r.finishes), int(r.atk_starts), float(r.alive),
				int(r.dodge_uses), int(r.dodge_in_chain), int(r.dodge_from_committed)])
			md.append("")
			md.append("```")
			var line := []
			for q in (r.log as Array):
				var seg := "%.2f %s→%s" % [float(q[0]), String(q[1]), String(q[2])]
				if String(q[2]) == "dodge":
					seg = "%.2f **%s→회피**" % [float(q[0]), String(q[1])]
				line.append(seg)
				if line.size() >= 4:
					md.append("  " + " | ".join(PackedStringArray(line)))
					line = []
			if not line.is_empty():
				md.append("  " + " | ".join(PackedStringArray(line)))
			md.append("```")
			md.append("")

	var fa := FileAccess.open("res://docs/sim/PROBE_DODGE.md", FileAccess.WRITE)
	fa.store_string("\n".join(md) + "\n")
	fa.close()
	print("\n".join(md))
	print("PROBE_DODGE_DONE")
	quit()
