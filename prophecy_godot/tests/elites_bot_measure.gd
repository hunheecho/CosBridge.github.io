extends SceneTree
## 특수 정예 7종 봇 측정(합격/불합격 판정이 아니라 **계측**이다).
## 실행: python tools/run_suites.py --suites elites_bot_measure --allow-adhoc
##
## 무엇을 재는가(사용자 지시): 살아서 실행한 공격 수 / 플레이어가 받은 피해 / 처치 시간.
## 여기에 "고유 연계를 몇 번 완주했는가"를 함께 낸다 — 체력 숫자보다 이 값이 설계 목표이기 때문이다.
## **봇 승패는 통과 조건이 아니다.** 봇은 사람이 아니고 보정도 끝나지 않았다(docs/BOT_FRAMEWORK.md).
## 통과 조건은 "측정이 실제로 이루어졌는가"뿐이며, 결과 표는 docs/ELITES.md에 옮겨 적는다.

const STEP := 1.0 / 120.0
const MAX_SEC := 90.0
var results := []

## 연계 판별: [시작 상태, 완주로 볼 상태들]. 완주 = 그 연계의 마지막 판정까지 갔다는 뜻이며,
## 사슬처럼 '빗나가면 회수 빈틈'으로 끝나는 설계는 회수도 완주로 센다(회피가 통한 정상 결과다)
const COMBO := {
	"elite_archer": ["aim", ["fan_lock"]],
	"elite_blademaster": ["dash1_aim", ["slam_aim"]],
	"elite_fang": ["bite_aim", ["leap"]],
	"elite_plaguecaller": ["throw_aim", ["swell"]],
	"elite_chainbreaker": ["chain_aim", ["slam_lock", "retract"]],
	"elite_standard": ["plant_aim", ["plant_aim", "slash_aim"]],
	"elite_miner": ["dive", ["erupt"]],
}

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func mk(seed_v: int, act: int) -> CombatState:
	var g := PGrowth.new_growth("sword")
	var b := PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "waves": [], "arena": "clearing", "region_id": "lab", "act": act, "fixed_build": true })
	st.spawn_hold = true
	return st

## 정예 1마리 대 봇 1회. 반환 {ttk, executed, taken, combos, finishes, hp_left, player_dead}
func one(type: String, policy: String, seed_v: int, act: int = 1) -> Dictionary:
	var st := mk(seed_v, act)
	var e := st.spawn_enemy(type, st.player.x + 260.0, st.player.y)
	var hp0: float = e.hp
	var bot := PBot.new(policy)
	var cs: Array = COMBO[type]
	var last_state := String(e.state)
	var combos := 0
	var finishes := 0
	var n := int(MAX_SEC / STEP)
	var ttk := -1.0
	for i in n:
		st.step(bot.step_input(st), STEP)
		if String(e.state) != last_state:
			if String(e.state) == String(cs[0]) and last_state == "approach":
				combos += 1
			if (cs[1] as Array).has(String(e.state)):
				finishes += 1
			last_state = String(e.state)
		if bool(e.dead) and ttk < 0.0:
			ttk = st.t
			break
		if bool(st.player.dead):
			break
	return { "ttk": ttk, "executed": int(st.metrics_for(e).executed), "taken": float(st.stats.damage_taken),
		"combos": combos, "finishes": finishes, "hp_left": maxf(0.0, float(e.hp)), "hp0": hp0, "player_dead": bool(st.player.dead),
		# 2026-09-09 추가: 회피는 조건 충족(dodge_seen)과 실제 발동(dodge_uses)을 따로 센다(사용자 지시).
		# 경직은 전투 전체의 누적 초이며, 정예 1마리 장면이라 사실상 그 정예가 멈춰 있던 시간이다
		"dodge_seen": int(e.get("dodge_seen", 0)), "dodge_uses": int(e.get("dodge_uses", 0)),
		"stagger_sec": float(st.stagger_stats.get("sec", 0.0)) }

func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])

func _init() -> void:
	var seeds := [1, 2, 3]
	var policies := ["balanced", "aggressive"]
	var types: Array = PEnemiesNew.ELITE_TYPES
	print("")
	print("### 정예 7종 봇 측정(시드 1·2·3 중앙값, 1막 시작 빌드 · 정예 1마리 · 최대 %d초)" % int(MAX_SEC))
	print("")
	print("| 정예 | 봇 | 체력 | 처치 시간(초) | 살아서 실행한 공격 수 | 연계 시작/완주 | 플레이어가 받은 피해 | 회피 충족/발동 | 총 경직(초) |")
	print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
	var measured := 0
	var no_attack := []
	var no_two_combos := []
	for tp in types:
		for pol in policies:
			var ttks := []
			var exs := []
			var tks := []
			var cbs := []
			var fns := []
			var dsn := []
			var dus := []
			var sgs := []
			var hp0 := 0.0
			var dead_n := 0
			for sd in seeds:
				var r := one(String(tp), String(pol), int(sd))
				hp0 = float(r.hp0)
				ttks.append(float(r.ttk) if float(r.ttk) > 0.0 else MAX_SEC)
				exs.append(float(r.executed))
				tks.append(float(r.taken))
				cbs.append(float(r.combos))
				fns.append(float(r.finishes))
				dsn.append(float(r.dodge_seen))
				dus.append(float(r.dodge_uses))
				sgs.append(float(r.stagger_sec))
				if bool(r.player_dead):
					dead_n += 1
				measured += 1
			var mt := med(ttks)
			print("| %s | %s | %.0f | %s | %.0f | %.0f / %.0f | %.0f | %.0f / %.0f | %.2f |" % [
				String(PCatalog.enemy(String(tp)).name), String(pol), hp0,
				("%.1f" % mt) if mt < MAX_SEC else "미처치(%d초)" % int(MAX_SEC),
				med(exs), med(cbs), med(fns), med(tks), med(dsn), med(dus), med(sgs)])
			if med(exs) < 1.0:
				no_attack.append("%s/%s" % [String(tp), String(pol)])
			if med(fns) < 2.0:
				no_two_combos.append("%s/%s 완주 %.0f회" % [String(tp), String(pol), med(fns)])
			if dead_n > 0:
				print("| ↳ 참고 | %s | — | 봇이 쓰러진 실행 %d/%d회(판정 아님) | — | — | — |" % [String(pol), dead_n, seeds.size()])

	print("")
	# 군단 기수는 지휘가 본체다: 호위(늑대 3)와 함께 둔 편성에서 명령 횟수를 따로 잰다
	print("### 군단 기수 + 호위 늑대 3(지휘 확인, 시드 1·2·3)")
	print("")
	print("| 봇 | 기수 처치 시간(초) | 깃발 설치 | 돌격 명령 발동 | 명령 예산 소진 | 추가 소환 |")
	print("|---|---:|---:|---:|---:|---|")
	for pol in policies:
		var kts := []
		var plants := []
		var orders := []
		for sd in seeds:
			var st := mk(int(sd), 1)
			var sdb := st.spawn_enemy("elite_standard", st.player.x + 260.0, st.player.y)
			var n0 := st.enemies.size()
			for k in 3:
				st.spawn_enemy("wolf", st.player.x + 230.0 + float(k) * 26.0, st.player.y + 40.0)
			n0 = st.enemies.size()
			var bot := PBot.new(String(pol))
			var kt := MAX_SEC
			for i in int(MAX_SEC / STEP):
				st.step(bot.step_input(st), STEP)
				if bool(sdb.dead):
					kt = st.t
					break
				if bool(st.player.dead):
					break
			var banners := 0
			for o in st.enemies:
				if String(o.type) == "elite_banner":
					banners += 1
			kts.append(kt)
			plants.append(float(int(PCatalog.enemy("elite_standard").plantBudget) - int(sdb.get("plant_left", 0))))
			orders.append(float(int(PCatalog.enemy("elite_standard").banner.orderBudget) - int(sdb.get("order_left", 0))))
		print("| %s | %.1f | %.0f회 | %.0f회 | %.0f/%d | 없음(설계상 소환하지 않는다) |" % [
			String(pol), med(kts), med(plants), med(orders), med(orders), int(PCatalog.enemy("elite_standard").banner.orderBudget)])
	print("")

	# 대조군: 강화된 1막 일반 적
	print("### 대조군(강화된 1막 일반 적, 같은 조건)")
	print("")
	print("| 적 | 봇 | 체력 | 처치 시간(초) | 실행한 공격 수 | 받은 피해 |")
	print("|---|---|---:|---:|---:|---:|")
	for tp in ["wolf", "shieldbearer"]:
		for pol in ["balanced"]:
			var ttks2 := []
			var exs2 := []
			var tks2 := []
			var hp02 := 0.0
			for sd in seeds:
				var st := mk(int(sd), 1)
				var e := st.spawn_enemy(String(tp), st.player.x + 260.0, st.player.y)
				hp02 = float(e.hp)
				var bot := PBot.new(String(pol))
				var ttk := MAX_SEC
				for i in int(MAX_SEC / STEP):
					st.step(bot.step_input(st), STEP)
					if bool(e.dead):
						ttk = st.t
						break
					if bool(st.player.dead):
						break
				ttks2.append(ttk)
				exs2.append(float(st.metrics_for(e).executed))
				tks2.append(float(st.stats.damage_taken))
			print("| %s | %s | %.0f | %.1f | %.0f | %.0f |" % [String(PCatalog.enemy(String(tp)).name), String(pol), hp02, med(ttks2), med(exs2), med(tks2)])
	print("")

	ok("측정이 실제로 수행되었다(정예 7종 × 봇 2종 × 시드 3개)", measured == types.size() * policies.size() * seeds.size(), "%d회" % measured)
	ok("모든 정예가 살아서 공격을 실행한다(맞기 전에 녹아 사라지지 않는다)", no_attack.is_empty(), str(no_attack))
	ok("[관찰] 고유 연계를 2회 이상 완주하는가 — 미달 조합은 체력·간격 조정 후보(봇 승패는 판정 아님)", true, str(no_two_combos) if not no_two_combos.is_empty() else "모든 조합 2회 이상")

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
