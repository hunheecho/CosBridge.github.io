extends SceneTree
## 독 전염 세대 상한 2·3·4 비교(화면 없음):
##   godot --headless --path prophecy_godot -s tools/spread_probe.gd
## 결과: docs/sim/SPREAD_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 따로 만들었는가
## ------------------
## `tools/synergy_probe.gd` 4절은 **한 가지 조건**(늑대 16마리 밀집, 가운데 하나만 처치)에서
## 상한 2와 무제한만 비교했다. 그 한 조건의 비율이 "전투 전체의 효과 감소율"처럼 읽힌 것이
## 앞선 보고의 잘못이다(`docs/SYNERGY.md` 3절 SYN-4). 여기서는 두 가지를 고친다.
##   ① 중간값 3·4를 같은 조건으로 함께 잰다. 무제한(99)은 **참고용**으로만 둔다.
##   ② 조건을 둘로 나눈다 — **밀집한 약한 적**(전염이 잘 이어진다)과
##      **폭발 후에도 살아남는 튼튼한 적**(전염이 이어지기 어렵다).
##
## 두 가지 장면을 나눠 잰다
## ------------------------
##   격리 시험실(lab) — 기하를 고정하고 적이 때리지 않는다. 사슬 자체의 크기를 정확히 본다.
##                      **처리 비용(전투 시간·받은 피해)은 여기서 잴 수 없다** — 적이 반격하지 않기 때문이다.
##   실전 장면(fight) — 실제 파도와 봇. 나비가 계속 다시 씨를 뿌리고 봇이 실제로 죽인다.
##                      여기서만 전투 시간·받은 피해가 뜻을 갖는다.
##
## 무엇을 바꾸는가
## ---------------
## `data/supports.json`은 **읽기만 한다.** 비교를 위해 메모리에 올라온 자격표 사전의
## `eligibility.plague_spread.gen_max`만 잠시 바꾸고 실행이 끝나면 원래 값으로 되돌린다.
## **값을 바꾸는 것은 이 담당의 권한이 아니다** — 여기 있는 것은 비교 결과뿐이다.
##
## 부분 실행 축: gen · mob · scene · seed
##   PROPHECY_SUBSET="gen=2,3;mob=dense;scene=lab"

const STEP := 1.0 / 120.0

## 비교할 세대 상한. 99는 사실상 무제한이며 **참고용**이다(권장안의 근거로 쓰지 않는다)
const GENS := [2, 3, 4, 99]
const GEN_NAME := { 2: "2(지금)", 3: "3", 4: "4", 99: "무제한(참고)" }

## 무리 조건 두 가지.
##  dense — 밀집한 약한 적: 늑대를 전염 반경 안에 4×4로 세우고 **시작 체력을 30%로 깎아 둔다.**
##          주무기가 이미 긁어 놓은 상태를 흉내 낸 것이다. 왜 깎는지는 아래 '남은 시간' 설명을 봐라.
##  tough — 폭발 후에도 살아남는 튼튼한 적: 늑대 우두머리를 온전한 체력으로 같은 자리에 세운다.
##          역병 파열(남은 독의 60%)로도 독 전체로도 죽지 않아 **사람이 마무리해야** 사슬이 이어진다.
##
## 왜 밀집 조건에서 체력을 깎는가 — '남은 시간'이 진짜 제동 장치다
## ---------------------------------------------------------------
## 전염은 지속 시간을 최대치로 되돌리지 않고 **죽은 개체의 남은 시간을 물려받는다**
## (`supports_b.gd:202`). 그래서 감염된 적이 **늦게** 죽으면 물려줄 시간이 거의 없어
## 세대 상한에 닿기 전에 사슬이 저절로 끝난다.
## 실제로 온전한 체력의 늑대(48)는 독(초당 10.8)으로 4.4초 만에 죽는데 독 지속이 5초라
## 남는 시간이 0.1초도 안 되어 **세대 상한 2에 닿지도 못한다**(보고서 1-2절에 그 측정을 적어 두었다).
## 앞선 보고가 쓴 '상한 2가 연쇄를 70% 깎는다'는 값은 체력을 1로 둔 시험에서 나온 것이다 —
## 그 조건에서는 감염된 적이 즉사해 5초가 통째로 넘어가므로 상한만이 유일한 제동 장치가 된다.
const MOBS := ["dense", "tough"]
const MOB_TYPE := { "dense": "wolf", "tough": "wolf_alpha" }
## 시작 체력 비율(1.0 = 온전)
const MOB_HP := { "dense": 0.3, "tough": 1.0 }
const MOB_NAME := { "dense": "밀집한 약한 적", "tough": "튼튼한 적" }
## 실전 장면의 편성(격리 시험실과 다르다 — 여기서는 체력을 깎지 않는다)
const FIGHT_NAME := { "dense": "밀집한 약한 적(늑대 12 + 궁수 2)", "tough": "튼튼한 적(우두머리 3 + 멧돼지 4 + 방패병 3)" }

const SCENES := ["lab", "fight"]
## 시드. 실전 장면의 받은 피해는 봇 경로가 갈리면 크게 흔들려 시드가 적으면 방향을 읽을 수 없다
const SEEDS := [1, 2, 3, 4, 5]

## 격리 시험실 관측 시간(초). 독 지속 5초 + 전염이 여러 세대 이어질 여유
const LAB_SEC := 14.0
## 튼튼 조건에서 사람 대신 마무리하는 간격(초). 감염된 적을 하나씩 처치해 사슬을 이어 준다
const ASSIST_GAP := 1.2
## 실전 장면 제한 시간(초)
const FIGHT_SEC := 90.0

var sub := PSubset.new()
var lab_rows := []
var fight_rows := []

# ---------- 공통 ----------
## 자격표의 세대 상한만 잠시 바꾼다. 돌려주는 값은 원래 값이며 반드시 restore_gen으로 되돌린다
func set_gen(v: int) -> int:
	var eff: Dictionary = (PCatalog.eligibility().get("effects", {}) as Dictionary).get("plague_spread", {})
	var saved := int(eff.get("gen_max", 2))
	eff["gen_max"] = v
	return saved

func restore_gen(saved: int) -> void:
	var eff: Dictionary = (PCatalog.eligibility().get("effects", {}) as Dictionary).get("plague_spread", {})
	eff["gen_max"] = saved

func plague_of(st: CombatState) -> Dictionary:
	return st.support.get("plague", {})

func dot_dmg(P: Dictionary) -> float:
	var box: Dictionary = P.get("dmg", {})
	return float(box.get("poison", 0.0)) + float(box.get("spread", 0.0))

func burst_dmg(P: Dictionary) -> float:
	return float((P.get("dmg", {}) as Dictionary).get("burst", 0.0))

# ---------- 1. 격리 시험실 ----------
## 늑대/우두머리 16마리를 4×4로 세우고 가운데 하나만 나비 독으로 감염시킨 뒤 그 하나를 처치한다.
## 튼튼 조건에서는 ASSIST_GAP마다 **살아 있는 감염된 적 하나**를 더 처치한다 —
## 독만으로는 죽지 않아 사슬이 시작조차 못 하기 때문이다. 그 보조 처치 수는 따로 적어
## '전염과 독으로 죽은 수'와 섞이지 않게 한다.
func lab_run(gen_v: int, mob: String, seed_v: int, mods: Array = [], hp_frac: float = -1.0) -> Dictionary:
	var saved := set_gen(gen_v)
	var g: Dictionary = PGrowth.new_growth("sword")
	g.weapons = [{ "id": "plague", "level": 3, "mods": mods.duplicate() }]
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": [], "arena": "clearing", "region_id": "lab" })
	st.spawn_hold = true
	st.obstacles = []
	var etype := String(MOB_TYPE[mob])
	var frac: float = float(MOB_HP[mob]) if hp_frac < 0.0 else hp_frac
	var pack := []
	for iy in 4:
		for ix in 4:
			var e: Dictionary = st.spawn_enemy(etype, 380.0 + float(ix) * 70.0, 220.0 + float(iy) * 70.0)
			e.hp = float(e.hp_max) * frac
			pack.append(e)
	# 가운데 하나에 나비가 직접 독을 건다(세대 0) → 그 하나만 처치한다
	PSupportB._infect(st, pack[5], 0, -1.0)
	_lab_tick(st, 0.5)
	var assist := 1        # 씨앗 한 마리도 사람이 처치한 것으로 센다
	st.kill_enemy(pack[5], {})
	var assist_t := ASSIST_GAP
	var elapsed := 0.0
	while elapsed < LAB_SEC:
		_lab_tick(st, STEP)
		elapsed += STEP
		if mob != "tough":
			continue
		assist_t -= STEP
		if assist_t > 0.0:
			continue
		assist_t = ASSIST_GAP
		var victim := _nearest_infected(pack)
		if not victim.is_empty():
			assist += 1
			st.kill_enemy(victim, {})
	var P := plague_of(st)
	var dead := 0
	for e in pack:
		if bool(e.dead):
			dead += 1
	restore_gen(saved)
	return { "gen": gen_v, "mob": mob, "seed": seed_v, "mods": mods.duplicate(), "hp_frac": snappedf(frac, 0.01),
		"hp_max": snappedf(float((pack[0] as Dictionary).hp_max), 0.1),
		"spreads": int(P.get("spreads", 0)), "blocked": int(P.get("spread_blocked", 0)),
		"bursts": int(P.get("bursts", 0)), "max_gen": int(P.get("max_gen", 0)),
		"dead": dead, "assist": assist, "chain_dead": maxi(0, dead - assist), "total": pack.size(),
		"dot": snappedf(dot_dmg(P), 0.1), "burst": snappedf(burst_dmg(P), 0.1),
		"dmg": snappedf(dot_dmg(P) + burst_dmg(P), 0.1) }

## 적을 움직이지 않고 보조·지연 호출만 굴린다(기하를 고정해 사슬 크기만 본다)
func _lab_tick(st: CombatState, dt: float) -> void:
	var keep := []
	for d in st.delayed:
		d.t = float(d.t) - dt
		if float(d.t) <= 0.0:
			(d.fn as Callable).call()
		else:
			keep.append(d)
	st.delayed = keep
	PSupport.update(st, dt)

## 아직 살아 있고 독이 걸린 적 하나(사람이 마무리할 대상). 없으면 {}
func _nearest_infected(pack: Array) -> Dictionary:
	for e in pack:
		var ed: Dictionary = e
		if bool(ed.dead):
			continue
		if not (ed.get("plague", {}) as Dictionary).is_empty():
			return ed
	return {}

# ---------- 2. 실전 장면 ----------
## 실제 파도·봇으로 싸운다. 나비가 주기마다 다시 씨를 뿌리므로 **세대가 계속 0으로 되돌아간다** —
## 격리 시험실의 사슬 크기가 전투 전체의 효과와 같지 않다는 것을 여기서 확인한다.
## 처리 비용(전투 시간·받은 피해)은 이 장면에서만 뜻을 갖는다.
func fight_waves(mob: String) -> Array:
	if mob == "tough":
		# 튼튼: 우두머리 3 + 멧돼지 4 + 방패병 3. 독·파열 한 번으로는 죽지 않는 편성
		return [[{ "type": "wolf_alpha", "n": 3 }, { "type": "boar", "n": 4 }, { "type": "shieldbearer", "n": 3 }]]
	# 밀집 약함: 늑대 12 + 궁수 2. 독만으로도 죽어 사슬이 이어지는 편성
	return [[{ "type": "wolf", "n": 12 }, { "type": "archer", "n": 2 }]]

func fight_run(gen_v: int, mob: String, seed_v: int) -> Dictionary:
	var saved := set_gen(gen_v)
	# 실제 성장 규칙으로 키운다(손으로 만든 사전은 플레이로 얻을 수 없는 편성이 된다)
	var run: Dictionary = PRun.new_run(seed_v, "sword")
	PGrowth.apply_choice(run, { "kind": "weapon_new", "id": "plague" })
	for i in 4:
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": "sword" })
	for i in 2:
		PGrowth.apply_choice(run, { "kind": "weapon_level", "id": "plague" })
	var b: Dictionary = PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v,
		"waves": fight_waves(mob), "objective": "clear", "region_id": "den" })
	var bot := PSkillBot.new("regular", seed_v)
	var steps := int(FIGHT_SEC / STEP)
	var i := 0
	while i < steps and st.status == "running":
		st.step(bot.step_input(st), STEP)
		i += 1
	var P := plague_of(st)
	var dealt := 0.0
	for k in (st.metrics.dmg as Dictionary):
		dealt += float(st.metrics.dmg[k])
	restore_gen(saved)
	return { "gen": gen_v, "mob": mob, "seed": seed_v, "status": String(st.status),
		"sec": snappedf(st.t, 0.01), "kills": int(st.stats.kills),
		"taken": snappedf(float(st.stats.damage_taken), 0.1),
		"spreads": int(P.get("spreads", 0)), "blocked": int(P.get("spread_blocked", 0)),
		"applied": int(P.get("applied", 0)), "max_gen": int(P.get("max_gen", 0)),
		"dot": snappedf(dot_dmg(P), 0.1), "dealt": snappedf(dealt, 0.1),
		"dot_share": snappedf((dot_dmg(P) / maxf(0.01, dealt)) * 100.0, 0.1) }

# ---------- 집계 ----------
func lab_pick(gen_v: int, mob: String) -> Dictionary:
	return _avg(lab_rows, gen_v, mob, ["spreads", "blocked", "bursts", "max_gen", "dead", "assist", "chain_dead", "dot", "burst", "dmg"])

## 기본 조건(개조 없음·기본 체력 비율)의 줄만 고른다. 참고용 줄이 평균에 섞이지 않게 한다
func _is_base_row(r: Dictionary, mob: String) -> bool:
	if not (r.get("mods", []) as Array).is_empty():
		return false
	return is_equal_approx(float(r.get("hp_frac", 1.0)), float(MOB_HP[mob]))

func fight_pick(gen_v: int, mob: String) -> Dictionary:
	var acc := _avg(fight_rows, gen_v, mob, ["sec", "kills", "taken", "spreads", "blocked", "applied", "max_gen", "dot", "dealt", "dot_share"])
	if acc.is_empty():
		return acc
	var won := 0
	for r in fight_rows:
		if int(r.gen) == gen_v and String(r.mob) == mob and String(r.status) == "won":
			won += 1
	acc["won"] = won
	return acc

func _avg(src: Array, gen_v: int, mob: String, keys: Array) -> Dictionary:
	var acc := {}
	var n := 0
	for r in src:
		if int(r.gen) != gen_v or String(r.mob) != mob:
			continue
		if r.has("hp_frac") and not _is_base_row(r, mob):
			continue
		if not (r.get("mods", []) as Array).is_empty():
			continue
		n += 1
		for k in keys:
			acc[String(k)] = float(acc.get(String(k), 0.0)) + float(r[String(k)])
	if n == 0:
		return {}
	for k in keys:
		acc[String(k)] = snappedf(float(acc[String(k)]) / float(n), 0.1)
	acc["n"] = n
	return acc

func num(v) -> String:
	var f := float(v)
	return str(int(round(f))) if is_equal_approx(f, round(f)) else str(snappedf(f, 0.1))

func cell(d: Dictionary, key: String) -> String:
	return num(d.get(key, 0.0)) if not d.is_empty() else "미계측"

## 요약표의 한 칸. 음수는 재지 못한 칸이다(0으로 적지 않는다)
func _v(x) -> String:
	return "미계측" if float(x) < 0.0 else num(x)

## 상한을 올려도 값이 더 늘지 않는 첫 값. 재지 못한 칸이 있으면 판단하지 않는다
func _saturate(vals: Array) -> String:
	for v in vals:
		if float(v) < 0.0:
			return "판단 불가(미계측 칸 있음)"
	for i in GENS.size() - 1:
		var here := float(vals[i])
		var rest_max := here
		for j in range(i + 1, GENS.size()):
			rest_max = maxf(rest_max, float(vals[j]))
		if rest_max <= here + 1e-6:
			return "상한 %s에서 포화" % str(GENS[i])
	return "무제한까지 계속 는다"

## 비용 지표(낮을수록 좋은 것)의 최소~최대 폭. 상한을 바꿔도 비용이 얼마나 흔들리는지만 말한다
func _spread_pct(vals: Array) -> String:
	var lo := INF
	var hi := -INF
	for v in vals:
		if float(v) < 0.0:
			return "판단 불가(미계측 칸 있음)"
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	if lo <= 0.0:
		return "%s~%s" % [num(lo), num(hi)]
	return "%s~%s (폭 %s%%)" % [num(lo), num(hi), num(snappedf((hi - lo) / lo * 100.0, 0.1))]

## 그 조건의 적 최대 체력(실제로 잰 줄에서 읽는다). 잰 줄이 없으면 0
func _lab_hp(mob: String) -> float:
	for r in lab_rows:
		if String(r.mob) == mob:
			return float(r.get("hp_max", 0.0))
	return 0.0

## 역병 나비 Lv3 독이 한 번의 감염으로 줄 수 있는 최대 피해(초당 × 지속). 데이터에서 읽는다
func _poison_total() -> float:
	var W: Dictionary = PCatalog.weapon("plague")
	var b: Dictionary = W.get("base", {})
	var ls: Dictionary = (PCatalog.level_scale().get("plague", {}) as Dictionary).get("dps", {})
	var mult: Array = ls.get("mult", [1.0, 1.0, 1.0])
	var m: float = float(mult[mult.size() - 1]) if mult.size() > 0 else 1.0
	return float(b.get("dps", 0.0)) * m * float(b.get("dur", 0.0))

# ---------- 보고서 ----------
func _init() -> void:
	var gens: Array = sub.pick("gen", GENS)
	var mobs: Array = sub.pick("mob", MOBS)
	var scenes: Array = sub.pick("scene", SCENES)
	var seeds: Array = sub.pick("seed", SEEDS)
	for gv in gens:
		for m in mobs:
			for sd in seeds:
				if scenes.has("lab"):
					lab_rows.append(lab_run(int(gv), String(m), int(sd)))
				if scenes.has("fight"):
					fight_rows.append(fight_run(int(gv), String(m), int(sd)))
			printerr("done gen=", gv, " mob=", m)
	# 참고 ①: 체력을 깎지 않은 늑대(온전) — '남은 시간'이 상한보다 먼저 사슬을 끝내는지
	# 참고 ②: 체력을 1로 둔 늑대(앞선 보고가 쓴 조건) — 그 조건에서만 상한이 유일한 제동 장치다
	var fresh_rows := []
	var glass_rows := []
	# 역병 파열을 함께 골랐을 때(밀집, 시드 1)만 따로 본다 — 파열이 이웃을 먼저 죽여 사슬이 끊기는지
	var burst_rows := []
	if scenes.has("lab"):
		for gv in gens:
			fresh_rows.append(lab_run(int(gv), "dense", 1, [], 1.0))
			glass_rows.append(lab_run(int(gv), "dense", 1, [], 0.02))
			burst_rows.append(lab_run(int(gv), "dense", 1, ["burst"]))
			lab_rows.append(fresh_rows[fresh_rows.size() - 1])
			lab_rows.append(glass_rows[glass_rows.size() - 1])
			lab_rows.append(burst_rows[burst_rows.size() - 1])
	print("SPREAD_PROBE_JSON " + JSON.stringify({ "lab": lab_rows, "fight": fight_rows }))

	var md := sub.describe("독 전염 세대 상한 비교(2·3·4)")
	md += "생성: `tools/spread_probe.gd` (%s, Godot %s).\n" % [OS.get_name(), Engine.get_version_info().string]
	md += "**모든 수치는 시험값이다.** 사람이 승인한 밸런스가 아니고 봇 계측으로 재미가 승인된 것도 아니다.\n"
	md += "`data/supports.json`은 읽기만 했다 — 메모리에 올라온 자격표의 `gen_max`만 잠시 바꾸고 되돌린다.\n"
	md += "**값을 바꾸는 것은 이 담당의 권한이 아니다.** 여기 있는 것은 비교 결과와 권장안뿐이다.\n\n"

	md += "## 0. 읽는 법 — 두 조건과 두 장면을 섞지 마라\n\n"
	md += "| 축 | 값 | 뜻 |\n|---|---|---|\n"
	md += "| 조건 | 밀집한 약한 적 | 늑대 16마리를 **시작 체력 %d%%**(=%s)로 깎아 세운다. 주무기가 이미 긁어 놓은 상태를 흉내 낸 것이고, 그래야 독이 빨리 마무리해 남은 시간이 다음 세대로 넘어간다 |\n" % [int(float(MOB_HP.dense) * 100.0), num(_lab_hp("dense") * float(MOB_HP.dense))]
	md += "| 조건 | 튼튼한 적 | 늑대 우두머리(체력 %s) 16마리. 독 전체(%s)로도 파열로도 죽지 않아 **사람이 마무리해야** 사슬이 이어진다 |\n" % [num(_lab_hp("tough")), num(_poison_total())]
	md += "| 장면 | 격리 시험실 | 적이 때리지 않고 움직이지도 않는다. 사슬 자체의 크기만 본다. **처리 비용은 잴 수 없다** |\n"
	md += "| 장면 | 실전 | 실제 파도·봇 %d초. 나비가 계속 다시 씨를 뿌린다. 전투 시간·받은 피해는 여기서만 뜻이 있다 |\n\n" % int(FIGHT_SEC)
	md += "**격리 시험실의 비율을 전투 전체의 효과 감소율로 옮겨 적지 마라.** 3절이 그 차이를 수치로 보여 준다.\n\n"

	md += "## 1. 격리 시험실 — 밀집한 약한 적\n\n"
	md += "늑대 16마리(시작 체력 %d%%)를 전염 반경 안에 4×4(간격 70)로 세우고 **가운데 한 마리만** 감염시킨 뒤 그 한 마리를 처치한다.\n" % int(float(MOB_HP.dense) * 100.0)
	md += "나머지는 전염과 독으로만 죽는다. 시드 %d개 평균.\n\n" % seeds.size()
	md += _lab_table("dense")
	md += "\n"

	md += "### 1-2. 같은 자리에서 체력만 바꾼 참고 측정 — 무엇이 사슬을 끝내는가\n\n"
	md += "전염은 지속 시간을 최대치로 되돌리지 않고 **죽은 개체의 남은 시간을 물려받는다**(`supports_b.gd:202`).\n"
	md += "그래서 감염된 적이 늦게 죽을수록 물려줄 시간이 없어 **세대 상한에 닿기 전에** 사슬이 끝난다.\n"
	md += "아래 두 줄은 같은 자리·같은 상한에서 **시작 체력만** 바꾼 것이다.\n\n"
	md += "| 조건 | 세대 상한 | 전염 | 상한에 막힌 죽음 | 도달 최대 세대 | 죽은 수 | 사슬을 끝낸 것 |\n"
	md += "|---|---|---:|---:|---:|---:|---|\n"
	for r in fresh_rows:
		md += "| 온전한 늑대(체력 100%%) | %s | %d | %d | %d | %d/16 | %s |\n" % [String(GEN_NAME.get(int(r.gen), str(r.gen))),
			int(r.spreads), int(r.blocked), int(r.max_gen), int(r.dead),
			("**남은 시간**(상한에 막힌 죽음 0)" if int(r.blocked) == 0 else "세대 상한")]
	for r in glass_rows:
		md += "| 체력 2%%(앞선 보고가 쓴 조건) | %s | %d | %d | %d | %d/16 | %s |\n" % [String(GEN_NAME.get(int(r.gen), str(r.gen))),
			int(r.spreads), int(r.blocked), int(r.max_gen), int(r.dead),
			("남은 시간" if int(r.blocked) == 0 else "**세대 상한**")]
	md += "\n**이 표가 앞선 보고의 '상한 2는 연쇄를 70% 깎는다'를 바로잡는 근거다.**\n"
	md += "그 70%는 체력을 거의 0으로 둔 한 조건에서만 나온다 — 감염된 적이 즉사해 5초가 통째로 넘어가므로\n"
	md += "세대 상한이 유일한 제동 장치가 되기 때문이다. 체력이 실제 값에 가까워질수록 사슬은 상한이 아니라\n"
	md += "**남은 시간**이 끝낸다. 그러므로 그 수치를 전투 전체의 효과 감소율로 옮겨 적으면 안 된다.\n\n"

	md += "## 2. 격리 시험실 — 폭발 후에도 살아남는 튼튼한 적\n\n"
	md += "같은 자리에 늑대 우두머리(체력 %s) 16마리. 독 전체(%s)로도 파열로도 죽지 않는다.\n" % [num(_lab_hp("tough")), num(_poison_total())]
	md += "그래서 **%.1f초마다 감염된 적 하나를 사람 대신 처치**해 사슬을 이어 준다(그 수는 '사람 처치'로 따로 적었다).\n" % ASSIST_GAP
	md += "**여기서 전염이 0에 가깝다고 곧바로 결함이라고 읽으면 안 된다** — 이어지기 어려운 조건을 일부러 고른 것이다.\n\n"
	md += _lab_table("tough")
	md += "\n"

	md += "## 3. 실전 장면 — 처리 비용까지\n\n"
	md += "실제 파도와 봇(regular). 밀집=늑대 12 + 궁수 2, 튼튼=우두머리 3 + 멧돼지 4 + 방패병 3.\n"
	md += "편성은 검 Lv5 + 역병 나비 Lv3(개조 없음), 시드 %d개 평균.\n" % seeds.size()
	md += "나비가 주기마다 다시 씨를 뿌려 **세대가 계속 0으로 되돌아가므로** 세대 상한의 영향이 시험실보다 작다.\n\n"
	md += _fight_table()
	md += "\n**받은 피해는 시드 %d개로는 방향을 읽지 마라.** 상한이 바뀌면 봇의 걷는 길이 갈려\n" % seeds.size()
	md += "받은 피해가 크게 흔들린다(처치 수와 전투 시간은 거의 같은데 받은 피해만 다르면 그것은 경로가 갈린 흔적이다).\n"
	md += "여기서 읽어야 할 것은 **처리 비용이 상한에 따라 크게 달라지지 않는다**는 사실이다.\n\n"

	md += "## 4. 역병 파열을 함께 골랐을 때(밀집, 시드 1)\n\n"
	md += "파열이 감염될 이웃을 먼저 죽여 전염 후보가 남지 않는 문제(`docs/SYNERGY.md` SYN-3)가\n"
	md += "세대 상한을 올리면 달라지는지 본다. **파열로 주변이 다 죽어 전염이 0이 된 것 자체는 결함이 아니다** —\n"
	md += "그 죽음이 처치로 이어졌는지를 함께 봐야 한다.\n\n"
	md += "| 세대 상한 | 전염 | 파열 | 죽은 수 | 독 피해 | 파열 피해 |\n|---|---:|---:|---:|---:|---:|\n"
	for r in burst_rows:
		md += "| %s | %d | %d | %d/%d | %s | %s |\n" % [String(GEN_NAME.get(int(r.gen), str(r.gen))),
			int(r.spreads), int(r.bursts), int(r.dead), int(r.total), num(r.dot), num(r.burst)]
	md += "\n"

	md += "## 5. 무엇을 계속 막아야 하는가\n\n"
	md += "세대 상한을 올려도 **같은 죽음의 중복 정산**과 **무한 재귀**는 계속 막혀 있어야 한다.\n"
	md += "지금 그 둘을 막는 것은 세대 상한이 아니라 다른 두 곳이다 — 상한을 올려도 사라지지 않는다.\n\n"
	md += "| 막는 것 | 어디가 막는가 | 세대 상한과 상관있나 |\n|---|---|---|\n"
	md += "| 같은 죽음으로 두 번 정산 | `supports_b.gd:166` `pg.done = true` · `e[\"plague\"] = {}` | 없다 |\n"
	md += "| 지속 시간이 무한히 늘어남 | `supports_b.gd:202` 남은 시간만 물려받고 `_apply_poison`이 `max`로 자른다 | 없다 |\n"
	md += "| 독가시의 독이 퍼짐 | `supports_b.gd:189` `spread=false` | 없다 |\n"
	md += "| 세대가 무한히 이어짐 | `PSupport.gen_max(\"plague_spread\")` | **있다(이 표의 축)** |\n\n"
	md += "즉 상한을 2에서 3·4로 올려도 **무한 재귀는 생기지 않는다.** 물려받는 지속 시간이 매 세대 줄어들기 때문에\n"
	md += "(`inherit = 남은 시간 × (1 - 파열 몫)`) 사슬은 시간으로도 저절로 끝난다.\n\n"

	md += "## 6. 어디서 포화하는가(측정 요약 — 판단이 아니다)\n\n"
	md += "각 조건에서 상한을 올릴 때 **더 올려도 값이 안 바뀌는 지점**을 적는다. 결정은 사용자 몫이다.\n\n"
	md += "| 조건 | 지표 | 상한 2 | 3 | 4 | 무제한(참고) | 포화 지점 |\n|---|---|---:|---:|---:|---:|---|\n"
	for m in MOBS:
		for key in ["spreads", "dead"]:
			var vals := []
			for gv in GENS:
				var d := lab_pick(int(gv), String(m))
				vals.append(d.get(key, -1.0) if not d.is_empty() else -1.0)
			md += "| %s(격리) | %s | %s | %s | %s | %s | %s |\n" % [String(MOB_NAME[m]),
				("전염 수" if key == "spreads" else "죽은 수"),
				_v(vals[0]), _v(vals[1]), _v(vals[2]), _v(vals[3]), _saturate(vals)]
	for m in MOBS:
		for key in ["sec", "taken"]:
			var vals := []
			for gv in GENS:
				var d := fight_pick(int(gv), String(m))
				vals.append(d.get(key, -1.0) if not d.is_empty() else -1.0)
			md += "| %s(실전) | %s | %s | %s | %s | %s | %s |\n" % [String(MOB_NAME[m]),
				("전투 시간" if key == "sec" else "받은 피해"),
				_v(vals[0]), _v(vals[1]), _v(vals[2]), _v(vals[3]), _spread_pct(vals)]
	md += "\n격리 시험실 줄의 '포화 지점'은 **그 값보다 상한을 올려도 이 지표가 더 늘지 않는 첫 값**이다.\n"
	md += "실전 줄은 늘어나는 지표가 아니라 **비용**이므로 포화 대신 최소~최대 폭을 적었다.\n"
	md += "재지 못한 칸은 '미계측'이며 0으로 적지 않았다.\n"

	var f := FileAccess.open(sub.out_path("res://docs/sim/SPREAD_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit()

func _lab_table(mob: String) -> String:
	var md := "| 세대 상한 | 전염 | 상한에 막힌 죽음 | 도달 최대 세대 | 죽은 수 | 사람 처치 | 사슬 처치 | 독 피해 |\n"
	md += "|---|---:|---:|---:|---:|---:|---:|---:|\n"
	for gv in GENS:
		var d := lab_pick(int(gv), mob)
		if d.is_empty():
			md += "| %s | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 |\n" % String(GEN_NAME[gv])
			continue
		md += "| %s | %s | %s | %s | %s/16 | %s | %s | %s |\n" % [String(GEN_NAME[gv]),
			cell(d, "spreads"), cell(d, "blocked"), cell(d, "max_gen"), cell(d, "dead"),
			cell(d, "assist"), cell(d, "chain_dead"), cell(d, "dot")]
	return md

func _fight_table() -> String:
	var md := "| 조건 | 세대 상한 | 전염 | 새 감염(나비 재파종 포함) | 상한에 막힌 죽음 | 처치 | 독 피해 | 독 비중 % | 전투 시간 | 받은 피해 | 승 |\n"
	md += "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
	for m in MOBS:
		for gv in GENS:
			var d := fight_pick(int(gv), String(m))
			if d.is_empty():
				md += "| %s | %s | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 | 미계측 |\n" % [String(FIGHT_NAME[m]), String(GEN_NAME[gv])]
				continue
			md += "| %s | %s | %s | %s | %s | %s | %s | %s | %s초 | %s | %d/%d |\n" % [String(FIGHT_NAME[m]), String(GEN_NAME[gv]),
				cell(d, "spreads"), cell(d, "applied"), cell(d, "blocked"), cell(d, "kills"),
				cell(d, "dot"), cell(d, "dot_share"), cell(d, "sec"), cell(d, "taken"),
				int(d.get("won", 0)), int(d.get("n", 0))]
	return md
