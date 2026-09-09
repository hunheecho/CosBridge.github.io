extends SceneTree
## 주무기 단일 대상 화력 측정(화면 없음):
##   godot --headless --path prophecy_godot -s tools/dps_probe.gd
## 결과: docs/sim/DPS_PROBE.md (부분 실행이면 _PARTIAL.md)
##
## 왜 있는가
## ---------
## 사용자 확정 사항: **쌍검은 같은 레벨·개조 투자·장비·대장간 조건에서, 전부 적중하는 단일 대상 DPS가
## 검의 최소 1.5배**여야 한다. 그 숫자를 눈대중이 아니라 같은 조건에서 재려고 만든 도구다.
##
## 그런데 "전부 적중하는 DPS"만 보면 쌍검을 과대평가한다. 쌍검은 리치 62·폭 70°로 주무기 중 가장 짧고,
## 3연타가 0.18초 동안 이어져 그 사이 적이 벗어나면 뒤 타격이 통째로 빠진다. 그래서 세 가지를 따로 잰다.
##
##   ① 이론 단일 대상 DPS — 움직이지 않는 표적 하나에 붙어서(거리 45) 전부 적중할 때 초당 피해.
##   ② 실제 단일 대상 DPS — 실제로 움직이는 늑대 1기를 실력 봇이 상대할 때 초당 피해.
##      여기서 손실을 둘로 나눈다:
##        · **접근 손실** = 사거리 밖이라 아예 발사하지 못한 시간(놓친 주기 수 × 주기)
##        · **이탈 손실** = 발사는 했는데 연타 중 적이 벗어나 빠진 타수와 그 피해
##   ③ 무리 상대(참고) — 늑대 6기. 검이 유리해야 정상이다(쌍검이 여기서도 이기면 구분이 무너진 것).
##
## 손실을 어떻게 나누는가(계산 방식)
## --------------------------------
##   이론 1주기 피해 = 이론 실행의 직접 피해 ÷ 발사 수      (그 무기가 한 주기에 넣을 수 있는 최대)
##   접근 손실 후 DPS = 이론 DPS × (실제 발사 수 × 주기 ÷ 실제 시간)
##   실제 DPS        = 실제 총 피해 ÷ 실제 시간
##   접근 손실 = 이론 DPS − 접근 손실 후 DPS · 이탈 손실 = 접근 손실 후 DPS − 실제 DPS
## 지속 피해(출혈)는 총 DPS에 포함하지만 위 손실 분해에는 넣지 않는다(주기에 딱 붙지 않는 값이라
## 1주기 피해로 나눌 수 없다). 그래서 손실 분해는 **직접 피해만** 쓰고, 표에 따로 적는다.
##
## 개조 축을 어떻게 고르는가
## ------------------------
## 개조 1·2개는 **그 무기에서 단일 대상 이론 DPS가 가장 높아지는 조합을 측정으로 고른다.**
## 임의로 목록 순서대로 고르면 비교가 유리한 쪽으로 기울 수 있다(예: 검의 잔류 검흔은 단일 대상에
## 매우 강한데 목록 3번째라 '개조 2'에서 빠진다). 고른 개조 id는 보고서에 적는다.
##
## **자격 없는 칸은 재지 않는다.** 주무기 개조는 Lv2에 첫 개, Lv4에 두 번째가 열린다
## (data/supports.json slots.modUnlockMain, PGrowth.mod_quota_of). 그래서 Lv1에 개조 2개를 끼운
## 가상 조합은 이 도구가 만들지 않는다 — 실제로 고를 수 있는 성장 단계에서만 비교한다는 뜻이다.
## 그래서 레벨 축에 첫 자격 레벨(2·4)을 함께 넣었다: 개조 1은 Lv2가, 개조 2는 Lv4가 가장 이른 칸이다.
##
## 이 도구가 재지 않는 것
## ---------------------
## 봇은 무기 리치를 모른다(모든 무기에 같은 유지 거리 55를 쓴다 — data/bots.json common.keep_dist).
## 그래서 '실제 DPS'는 **그 무기를 이해한 사람의 상한이 아니라, 같은 조작 정책에서의 값**이다.
## 무기별로 봇을 다르게 두면 무기 비교가 아니라 봇 비교가 되므로 일부러 같은 정책을 쓴다.
##
## 부분 실행 축: weapon · level · mods · seed  (tools/subset.gd)
##   PROPHECY_SUBSET="weapon=sword,daggers;level=1;mods=0;seed=1"
##
## 여기 나오는 수치는 전부 **시험값**이다. 사람이 승인한 밸런스가 아니다.

const STEP := 1.0 / 120.0
const THEORY_SEC := 30.0     # 이론 실행 길이(발사 수 반올림 오차를 줄이려고 길게 잡는다)
const REAL_SEC := 30.0       # 실제 실행 길이
const SWARM_SEC := 20.0      # 무리 실행 길이(참고용)
const THEORY_DIST := 45.0    # '붙어 있는' 거리. 주무기 5종 모두 사거리 안이다(쌍검 62가 가장 짧다)
const FAR_DIST := 200.0      # 참고: 원거리 표적. 창(230)·궁(320)만 닿고 검(95)·망치(110)·쌍검(62)은 못 닿는 거리
const REAL_START := 260.0    # 실제 실행에서 늑대가 등장하는 거리(접근 시간을 실제로 만들려고 멀리 둔다)
const SWARM_N := 6
const HUGE_HP := 1.0e9       # 표적이 죽으면 시간 창이 무기마다 달라진다. 죽지 않게 둔다
const HUGE_PLAYER_HP := 1.0e6 # 플레이어가 죽어도 시간 창이 달라진다. 측정 대상은 화력이라 살려 둔다
const WEAPONS := ["sword", "spear", "daggers", "hammer", "bow"]
const LEVELS := [1, 2, 3, 4, 5]   # 2·4는 개조 1·2가 처음 열리는 레벨이다(자격표 modUnlockMain)
const MODS := [0, 1, 2]
const SEEDS := [1, 2, 3]
const BOT := "skilled"
const TARGET_RATIO := 1.5    # 사용자 확정: 쌍검 이론 단일 대상 DPS ≥ 검 × 1.5
# 창 '분열 창날'이 뒤쪽 적까지 가는지 재는 일렬 무리(창 전용, MOD-1)
const LINE_N := 3            # 일렬로 세우는 늑대 수
const LINE_FIRST := 120.0    # 첫 적까지 거리. 창의 근접 약화(사거리 45% = 103.5) 밖이라 셋 다 같은 배율로 맞는다
const LINE_GAP := 45.0       # 적 사이 간격. 분열탄 도달 거리(modTuning travel) 안이라 바로 뒤 적에게 닿는다
const LINE_SEC := 10.0       # 고정 표적 실행 길이(적별 분열 피해를 가르는 측정)
const LINE_KILL_SEC := 60.0  # 처치 시간 상한. 이 안에 다 못 쓰러뜨리면 -1로 적는다
const LINE_LEVELS := [2, 5]  # 개조 1개가 처음 열리는 레벨(2)과 최대 레벨(5)

var sub := PSubset.new()
var theory_rows: Array = []   # 이론 결과
var real_rows: Array = []     # 실제 결과(시드별)
var swarm_rows: Array = []    # 무리 결과(시드별)
var far_rows: Array = []      # 원거리 참고
var line_rows: Array = []     # 창 일렬 무리(분열 창날) 결과
var mod_pick: Dictionary = {} # "weapon|level|k" → [개조 id]

# ---------- 개조 자격(Lv2에 첫 개, Lv4에 두 번째) ----------
## 그 레벨에서 실제로 가질 수 있는 개조 수. 규칙 코드(PGrowth)를 그대로 물어본다 — 여기서 숫자를 베끼지 않는다
func quota_at(wid: String, level: int) -> int:
	var g: Dictionary = PGrowth.new_growth(wid)
	g.weapons = [{ "id": wid, "level": level, "mods": [] }]
	return PGrowth.mod_quota_of(g, g.weapons[0])

## 이 칸(레벨 × 개조 수)이 실제로 고를 수 있는 조합인가
func eligible(wid: String, level: int, k: int) -> bool:
	return k <= quota_at(wid, level)

# ---------- 전투 준비 ----------
## 주무기 하나만 든 전투(장애물 없음 — 가림 때문에 값이 흔들리지 않게)
func mk(wid: String, level: int, mods: Array, seed_v: int) -> CombatState:
	var g: Dictionary = PGrowth.new_growth(wid)
	g.weapons = [{ "id": wid, "level": level, "mods": mods.duplicate() }]
	var b: Dictionary = PBuild.derive(PBuild.empty_run_like(g))
	var st := CombatState.new({ "build": b, "seed": seed_v, "arena": "clearing", "obstacles": [],
		"formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} } })
	st.spawn_hold = true
	st.player.x = st.arena_w / 2.0
	st.player.y = st.arena_h / 2.0
	st.player.hp_max = HUGE_PLAYER_HP
	st.player.hp = HUGE_PLAYER_HP
	return st

func wep(st: CombatState, wid: String) -> Dictionary:
	for w in st.weapons:
		if String(w.id) == wid:
			return w
	return {}

## 죽지 않는 표적. attack=false면 물기·돌진도 하지 않는다(이론 실행용)
func target(st: CombatState, x: float, y: float, attack: bool) -> Dictionary:
	var e: Dictionary = st.spawn_enemy("wolf", x, y)
	e.hp = HUGE_HP
	e.hp_max = HUGE_HP
	if not attack:
		e.bite_cd = 1.0e9
		e.dash_ready_at = 1.0e9
	return e

## 그 무기가 낸 모든 피해(직접 + 그 무기가 붙인 지속 피해). 출혈은 dot:bleed@<id>로 따로 쌓인다
func dmg_of(st: CombatState, wid: String) -> Array:
	var direct := 0.0
	var dot := 0.0
	for k in (st.metrics.dmg as Dictionary):
		var key := String(k)
		if key == "weapon:" + wid:
			direct += float(st.metrics.dmg[k])
		elif key.begins_with("dot:") and key.ends_with("@" + wid):
			dot += float(st.metrics.dmg[k])
	return [direct, dot]

# ---------- ① 이론 단일 대상 DPS ----------
## 움직이지 않는 표적 하나에 붙어서(dist) 전부 적중할 때. 표적은 매 단계 제자리에 고정한다
func theory(wid: String, level: int, mods: Array, dist: float) -> Dictionary:
	var st := mk(wid, level, mods, 1)
	var tx: float = st.player.x + dist
	var ty: float = st.player.y
	var e := target(st, tx, ty, false)
	var n := int(round(THEORY_SEC / STEP))
	for i in n:
		st.step({}, STEP)
		e.x = tx
		e.y = ty
		e.vx = 0.0
		e.vy = 0.0
	var d := dmg_of(st, wid)
	var w := wep(st, wid)
	var fires: int = int(w.count)
	var hits: int = int(st.metrics.hits.get(wid, 0))
	var total: float = float(d[0]) + float(d[1])
	return { "weapon": wid, "level": level, "mods": mods.duplicate(), "dist": dist,
		"dps": total / THEORY_SEC, "direct_dps": float(d[0]) / THEORY_SEC, "dot_dps": float(d[1]) / THEORY_SEC,
		"fires": fires, "hits": hits,
		"per_fire": (float(d[0]) / float(fires)) if fires > 0 else 0.0,
		"hits_per_fire": (float(hits) / float(fires)) if fires > 0 else 0.0,
		"interval": float(w.stats.interval) }

# ---------- 개조 고르기(단일 대상에 가장 유리한 조합) ----------
func impl_mods(wid: String) -> Array:
	var out: Array = []
	var d: Dictionary = PCatalog.weapon(wid)
	for mid in (d.get("mods", {}) as Dictionary):
		if bool(d.mods[mid].get("impl", false)):
			out.append(String(mid))
	return out

func combos(all: Array, k: int) -> Array:
	var out: Array = []
	if k == 1:
		for m in all:
			out.append([String(m)])
	elif k == 2:
		for i in all.size():
			for j in range(i + 1, all.size()):
				out.append([String(all[i]), String(all[j])])
	return out

## 개조 k개 중 단일 대상 이론 DPS가 가장 높은 조합. 같은 값이면 목록 순서가 앞선 쪽
func best_mods(wid: String, level: int, k: int) -> Array:
	var key := "%s|%d|%d" % [wid, level, k]
	if mod_pick.has(key):
		return (mod_pick[key] as Array).duplicate()
	if k <= 0:
		mod_pick[key] = []
		return []
	var best: Array = []
	var best_dps := -1.0
	for c in combos(impl_mods(wid), k):
		var r := theory(wid, level, c, THEORY_DIST)
		if float(r.dps) > best_dps + 1e-9:
			best_dps = float(r.dps)
			best = (c as Array).duplicate()
	mod_pick[key] = best.duplicate()
	return best.duplicate()

# ---------- ② 실제 단일 대상 DPS ----------
## 실제로 움직이는 늑대 1기를 실력 봇이 상대한다. 접근 손실·이탈 손실을 함께 센다
func real_one(wid: String, level: int, mods: Array, seed_v: int, theo: Dictionary) -> Dictionary:
	var st := mk(wid, level, mods, seed_v)
	target(st, st.player.x + REAL_START, st.player.y, true)
	var bot := PSkillBot.new(BOT, seed_v)
	var w := wep(st, wid)
	var rng_v: float = float(w.stats.range)
	var no_target_steps := 0
	var n := int(round(REAL_SEC / STEP))
	# 쌍검 '출혈 칼날'의 집중 중첩이 실제로 얼마나 유지되는지(읽기만 한다 — 규칙에 영향 없음).
	# 이론 실행에서는 늘 최대지만, 움직이는 적을 상대로는 붙었다 떨어질 때마다 풀린다
	var focus_sum := 0.0
	var focus_full := 0
	var focus_max: int = int(PWeapons.mod_tune(w.stats, "bleed", { "maxStack": 0 }).maxStack) if mods.has("bleed") else 0
	for i in n:
		# 발사 자격이 있는가(사거리 안 + 가림 없음)를 규칙 코드와 같은 함수로 본다. 규칙은 건드리지 않는다
		if PWeapons.pick_target(st, w, rng_v, true).is_empty():
			no_target_steps += 1
		var fs: int = int((w.get("focus", {}) as Dictionary).get("n", 0))
		focus_sum += float(fs)
		if focus_max > 0 and fs >= focus_max:
			focus_full += 1
		st.step(bot.step_input(st), STEP)
	var d := dmg_of(st, wid)
	var fires: int = int(w.count)
	var hits: int = int(st.metrics.hits.get(wid, 0))
	var interval: float = float(w.stats.interval)
	var total: float = float(d[0]) + float(d[1])
	var ideal_fires: float = REAL_SEC / interval
	var lost_fires: float = maxf(0.0, ideal_fires - float(fires))
	var dps_after_approach: float = float(theo.direct_dps) * (float(fires) * interval / REAL_SEC)
	var missed_hits: float = maxf(0.0, float(fires) * float(theo.hits_per_fire) - float(hits))
	var missed_dmg: float = maxf(0.0, float(fires) * float(theo.per_fire) - float(d[0]))
	return { "weapon": wid, "level": level, "mods": mods.duplicate(), "seed": seed_v,
		"dps": total / REAL_SEC, "direct_dps": float(d[0]) / REAL_SEC, "dot_dps": float(d[1]) / REAL_SEC,
		"fires": fires, "hits": hits, "ideal_fires": ideal_fires, "lost_fires": lost_fires,
		"no_target_sec": float(no_target_steps) * STEP,
		"lost_fire_sec": lost_fires * interval,
		"dps_after_approach": dps_after_approach,
		"approach_loss": maxf(0.0, float(theo.direct_dps) - dps_after_approach),
		"leash_loss": maxf(0.0, dps_after_approach - float(d[0]) / REAL_SEC),
		"missed_hits": missed_hits, "missed_dmg": missed_dmg,
		"focus_avg": focus_sum / float(n), "focus_full_frac": float(focus_full) / float(n), "focus_max": focus_max,
		"taken": float(st.stats.damage_taken) }

# ---------- ③ 무리 상대(참고) ----------
func swarm_one(wid: String, level: int, mods: Array, seed_v: int) -> Dictionary:
	var st := mk(wid, level, mods, seed_v)
	var rng := PRng.new(seed_v)
	for i in SWARM_N:
		var a: float = TAU * float(i) / float(SWARM_N) + rng.range_f(-0.2, 0.2)
		var r: float = 200.0 + rng.range_f(-40.0, 40.0)
		target(st, st.player.x + cos(a) * r, st.player.y + sin(a) * r, true)
	var bot := PSkillBot.new(BOT, seed_v)
	var n := int(round(SWARM_SEC / STEP))
	for i in n:
		st.step(bot.step_input(st), STEP)
	var d := dmg_of(st, wid)
	return { "weapon": wid, "level": level, "mods": mods.duplicate(), "seed": seed_v,
		"dps": (float(d[0]) + float(d[1])) / SWARM_SEC, "hits": int(st.metrics.hits.get(wid, 0)) }

# ---------- ④ 창 '분열 창날': 일렬 무리에서 뒤쪽 적까지 가는가(창 전용) ----------
## 늑대를 일렬로 세우고 창만 쏜다. 분열탄이 첫 명중한 적에게 다시 흡수되면 **뒤쪽 적이 받는 분열 피해가 0**이다
## (`docs/MOD_REVIEW.md` MOD-1의 재현 절차 ①). 여기서 그 값을 직접 잰다.
##
## 적별 분열 피해를 어떻게 가르는가: **같은 자리·같은 시간으로 개조 없이 한 번 더 재고 차이를 본다.**
## 표적을 매 단계 제자리에 고정하고 죽지 않게 두므로 두 실행은 분열탄 말고 다른 것이 하나도 다르지 않다
## (피해 계산에는 난수가 없다 — `CombatState.damage_enemy`). 산술로 추정하지 않고 측정으로 가른다.
func line_positions(st: CombatState) -> Array:
	var out: Array = []
	for i in LINE_N:
		out.append([st.player.x + LINE_FIRST + LINE_GAP * float(i), st.player.y])
	return out

## 고정 표적 일렬(죽지 않는다). 적별 총 피해와 개조 계측을 돌려준다
func line_damage(level: int, mods: Array) -> Dictionary:
	var st := mk("spear", level, mods, 1)
	var pos: Array = line_positions(st)
	var es: Array = []
	for p in pos:
		es.append(target(st, float((p as Array)[0]), float((p as Array)[1]), false))
	var n := int(round(LINE_SEC / STEP))
	for i in n:
		st.step({}, STEP)
		for j in es.size():
			var e: Dictionary = es[j]
			e.x = float((pos[j] as Array)[0])
			e.y = float((pos[j] as Array)[1])
			e.vx = 0.0
			e.vy = 0.0
	var per: Array = []
	for e_v in es:
		var e2: Dictionary = e_v
		per.append(float(e2.hp_max) - float(e2.hp))
	var ms: Dictionary = (st.mod_stats as Dictionary).get("split", {})
	return { "per": per, "split_hits": int(ms.get("hits", 0)), "split_procs": int(ms.get("procs", 0)),
		"split_dmg": float(ms.get("damage", 0.0)), "fires": int(wep(st, "spear").count) }

## 실제 체력의 늑대를 일렬로 세우고 **적별 쓰러지는 시각**과 전부 쓰러질 때까지의 시간을 잰다.
## 창은 줄을 통째로 꿰므로 '전부 쓰러질 때까지'만 보면 분열탄이 어디로 갔는지 드러나지 않는다 —
## 적별 시각을 함께 봐야 뒤쪽 적이 실제로 더 빨리 쓰러지는지 읽힌다. 상한 안에 못 쓰러뜨리면 -1
func line_kill(level: int, mods: Array) -> Dictionary:
	var st := mk("spear", level, mods, 1)
	var pos: Array = line_positions(st)
	var es: Array = []
	var at_t: Array = []
	for p in pos:
		var e: Dictionary = st.spawn_enemy("wolf", float((p as Array)[0]), float((p as Array)[1]))
		e.bite_cd = 1.0e9      # 물기·돌진을 끈다: 재는 것은 화력이지 생존이 아니다
		e.dash_ready_at = 1.0e9
		es.append(e)
		at_t.append(-1.0)
	var n := int(round(LINE_KILL_SEC / STEP))
	var all_t := -1.0
	for i in n:
		st.step({}, STEP)
		var alive := 0
		for j in es.size():
			var e2: Dictionary = es[j]
			if bool(e2.dead):
				if float(at_t[j]) < 0.0:
					at_t[j] = float(st.t)
				continue
			alive += 1
			e2.x = float((pos[j] as Array)[0])
			e2.y = float((pos[j] as Array)[1])
			e2.vx = 0.0
			e2.vy = 0.0
		if alive == 0:
			all_t = float(st.t)
			break
	return { "each": at_t, "all": all_t }

## 개조 없음 / 분열 창날 한 쌍을 재고 적별 분열 피해를 가른다
func line_pair(level: int) -> Dictionary:
	var base := line_damage(level, [])
	var with_split := line_damage(level, ["split"])
	var delta: Array = []
	var rear := 0.0
	var first_extra := 0.0
	var distinct := 0
	for i in LINE_N:
		var d: float = float((with_split.per as Array)[i]) - float((base.per as Array)[i])
		delta.append(d)
		if d > 0.01:
			distinct += 1
		if i == 0:
			first_extra = d
		else:
			rear += d
	# 같은 개조가 **단일 대상**에 얼마나 보태는지도 같은 자리에서 잰다(개조 없음 ↔ 분열 창날 하나).
	# 무리 처리가 정상화되는 것과 단일 대상 화력이 줄어드는 것은 서로 다른 이야기라 따로 적는다.
	var one_base := theory("spear", level, [], THEORY_DIST)
	var one_split := theory("spear", level, ["split"], THEORY_DIST)
	return { "level": level, "delta": delta, "distinct": distinct, "first_extra": first_extra, "rear": rear,
		"split_hits": int(with_split.split_hits), "split_procs": int(with_split.split_procs),
		"split_dmg": float(with_split.split_dmg), "fires": int(with_split.fires),
		"base_per": (base.per as Array).duplicate(), "split_per": (with_split.per as Array).duplicate(),
		"single_base": float(one_base.dps), "single_split": float(one_split.dps),
		"kill_base": line_kill(level, []), "kill_split": line_kill(level, ["split"]) }

## 처치 시각 한 칸의 글자(못 쓰러뜨렸으면 그 사실을 적는다)
func kill_text(v: float) -> String:
	return ("%.2f초" % v) if v >= 0.0 else ("%.0f초 안에 못 끝냄" % LINE_KILL_SEC)

# ---------- 표 만들기 ----------
func avg(rows: Array, field: String) -> float:
	if rows.is_empty():
		return 0.0
	var t := 0.0
	for r in rows:
		t += float(r[field])
	return t / float(rows.size())

func pick(rows: Array, wid: String, level: int, k: int) -> Array:
	var out: Array = []
	for r in rows:
		if String(r.weapon) == wid and int(r.level) == level and int(r.get("mods_k", -1)) == k:
			out.append(r)
	return out

func theory_of(wid: String, level: int, k: int) -> Dictionary:
	for r in theory_rows:
		if String(r.weapon) == wid and int(r.level) == level and int(r.mods_k) == k:
			return r
	return {}

func wname(wid: String) -> String:
	return String(PCatalog.weapon(wid).get("name", wid))

## 그 개조 수의 자격이 열리는 **가장 이른 레벨**에서 고른 조합. 자격이 없으면 빈 배열
func first_pick(wid: String, levels: Array, k: int) -> Array:
	for lv_v in levels:
		if eligible(wid, int(lv_v), k):
			return best_mods(wid, int(lv_v), k)
	return []

func mods_text(wid: String, mods: Array) -> String:
	if mods.is_empty():
		return "-"
	var out: Array = []
	var d: Dictionary = PCatalog.weapon(wid)
	for m in mods:
		out.append("%s(%s)" % [String(d.mods[String(m)].name), String(m)])
	return "+".join(out)

func _init() -> void:
	var weapons: Array = sub.pick("weapon", WEAPONS)
	var levels: Array = sub.pick("level", LEVELS)
	var mods_ax: Array = sub.pick("mods", MODS)
	var seeds: Array = sub.pick("seed", SEEDS)

	for wid_v in weapons:
		var wid := String(wid_v)
		for lv_v in levels:
			var lv := int(lv_v)
			for k_v in mods_ax:
				var k := int(k_v)
				if not eligible(wid, lv, k):
					printerr("skip %s Lv%d 개조%d — 자격 없음(개조 %d개까지)" % [wid, lv, k, quota_at(wid, lv)])
					continue
				var ms := best_mods(wid, lv, k)
				var th := theory(wid, lv, ms, THEORY_DIST)
				th["mods_k"] = k
				theory_rows.append(th)
				for sd_v in seeds:
					var sd := int(sd_v)
					var rr := real_one(wid, lv, ms, sd, th)
					rr["mods_k"] = k
					real_rows.append(rr)
					var sw := swarm_one(wid, lv, ms, sd)
					sw["mods_k"] = k
					swarm_rows.append(sw)
				printerr("done %s Lv%d 개조%d %s" % [wid, lv, k, str(ms)])
			# 참고: 원거리 표적(개조 없음). 창·궁이 제 몫을 하는 거리
			var fr := theory(wid, lv, [], FAR_DIST)
			fr["mods_k"] = 0
			far_rows.append(fr)

	# 창 '분열 창날'이 뒤쪽 적까지 가는가(창을 고른 실행에서만, 레벨 축과 별개로 잰다)
	if weapons.has("spear"):
		for lv_v in LINE_LEVELS:
			line_rows.append(line_pair(int(lv_v)))
			printerr("done spear 일렬 무리 Lv%d" % int(lv_v))

	print("DPS_PROBE_JSON " + JSON.stringify({ "theory": theory_rows, "real": real_rows, "swarm": swarm_rows, "far": far_rows, "line": line_rows }))
	write_report(weapons, levels, mods_ax, seeds)
	quit()

func write_report(weapons: Array, levels: Array, mods_ax: Array, seeds: Array) -> void:
	var md := sub.describe("주무기 단일 대상 화력 측정")
	md += "생성: `tools/dps_probe.gd` (%s, Godot %s).\n" % [OS.get_name(), Engine.get_version_info().string]
	md += "**여기 있는 수치는 전부 시험값이다.** 사람이 승인한 밸런스가 아니다.\n\n"
	md += "## 무엇을 어떻게 재는가\n\n"
	md += "| 값 | 재는 방법 |\n|---|---|\n"
	md += "| 이론 단일 대상 DPS | 움직이지 않는 표적 1기를 거리 %.0f에 두고 %.0f초. 표적을 매 단계 제자리에 고정해 **전부 적중**시킨다 |\n" % [THEORY_DIST, THEORY_SEC]
	md += "| 실제 단일 대상 DPS | 늑대 1기(거리 %.0f에서 시작)를 실력 봇(%s)이 %.0f초 상대. 적도 봇도 실제로 움직인다 |\n" % [REAL_START, BOT, REAL_SEC]
	md += "| 접근 손실 | 사거리 밖이라 발사 자체를 못 한 몫. 놓친 주기 수 × 주기(초)와 DPS 감소로 적는다 |\n"
	md += "| 이탈 손실 | 발사는 했는데 연타 중 적이 벗어나 빠진 타수·피해. 이론 1주기 값과의 차이 |\n"
	md += "| 무리(참고) | 늑대 %d기를 %.0f초. **검이 유리해야 정상**이다 |\n" % [SWARM_N, SWARM_SEC]
	md += "| 창 일렬 무리(§4-2) | 늑대 %d기를 %.0f 간격으로 **일렬로** 세우고 창만 쏜다. '분열 창날'의 창날이 뒤쪽 적까지 가는지(알려진 결함 MOD-1) |\n\n" % [LINE_N, LINE_GAP]
	md += "표적·플레이어 모두 죽지 않게 체력을 크게 둔다. 죽으면 무기마다 시간 창이 달라져 DPS를 비교할 수 없기 때문이다.\n"
	md += "개조 1·2개는 **그 무기의 단일 대상 이론 DPS가 가장 높아지는 조합을 측정으로 골랐다**(목록 순서가 아니다).\n\n"
	md += "**자격 없는 칸은 재지 않았다(표에 `-`).** 주무기 개조는 Lv2에 첫 개, Lv4에 두 번째가 열린다\n"
	var unlock_txt := []
	for u in (PCatalog.slot_rules().get("modUnlockMain", []) as Array):
		unlock_txt.append("Lv%d" % int(u))
	md += "(`data/supports.json` slots.modUnlockMain = %s, 판정은 `PGrowth.mod_quota_of`). Lv1에 개조 2개를 끼운\n" % ", ".join(unlock_txt)
	md += "가상 조합으로는 비교하지 않는다는 뜻이다. 레벨 축에 2·4를 넣은 이유도 그것이 각 개조 수의 **가장 이른 칸**이기 때문이다.\n\n"

	# ---- 개조 선택표 ----
	md += "## 고른 개조(단일 대상에 가장 유리한 조합)\n\n"
	md += "| 무기 | 개조 1 | 개조 2 |\n|---|---|---|\n"
	for wid_v in weapons:
		var wid := String(wid_v)
		md += "| %s | %s | %s |\n" % [wname(wid), mods_text(wid, first_pick(wid, levels, 1)), mods_text(wid, first_pick(wid, levels, 2))]
	md += "\n레벨 배율은 한 무기의 모든 경로에 똑같이 곱해지므로 레벨이 달라도 같은 조합이 뽑힌다.\n"
	md += "**자격이 열리는 가장 이른 레벨** 기준으로 적었다(개조 1은 Lv2, 개조 2는 Lv4).\n\n"

	# ---- 이론 DPS 표 ----
	md += "## 1. 이론 단일 대상 DPS (거리 %.0f · 전부 적중)\n\n" % THEORY_DIST
	md += "| 레벨 | 개조 |"
	for wid_v in weapons:
		md += " %s |" % wname(String(wid_v))
	md += " 쌍검/검 | 1.5배 |\n|---:|---:|"
	for _w in weapons:
		md += "---:|"
	md += "---:|---|\n"
	for lv_v in levels:
		var lv := int(lv_v)
		for k_v in mods_ax:
			var k := int(k_v)
			md += "| %d | %d |" % [lv, k]
			for wid_v in weapons:
				var r := theory_of(String(wid_v), lv, k)
				md += (" %.2f |" % float(r.dps)) if not r.is_empty() else " - |"
			var dg := theory_of("daggers", lv, k)
			var sw := theory_of("sword", lv, k)
			if dg.is_empty() or sw.is_empty() or float(sw.dps) <= 0.0:
				md += " - | 자격 없음 |\n"
			else:
				var ratio: float = float(dg.dps) / float(sw.dps)
				md += " **%.3f** | %s |\n" % [ratio, "달성" if ratio >= TARGET_RATIO else "미달"]
	md += "\n`-`는 그 레벨에서 그 개조 수를 **고를 수 없다**는 뜻이다(개조 1은 Lv2부터, 개조 2는 Lv4부터).\n"
	md += "레벨 배율표가 두 무기에 똑같이 곱해지므로 쌍검/검 비율은 레벨과 무관하다 — 자격이 열린 레벨마다 같은 값이 나온다.\n\n"

	# ---- 실제 DPS 표 ----
	md += "## 2. 실제 단일 대상 DPS와 손실 분해 (시드 %s 평균)\n\n" % str(seeds)
	md += "손실 분해는 **직접 피해만** 쓴다. 지속 피해(출혈)는 주기에 붙지 않아 1주기 값으로 나눌 수 없기 때문이다.\n"
	md += "읽는 순서: 이론(직접) → 접근 손실을 빼면 '접근 후' → 이탈 손실을 빼면 '실제(직접)' → 지속 피해를 더하면 '실제(총)'.\n\n"
	md += "| 무기 | 레벨 | 개조 | 이론(총) | 이론(직접) | 접근 후 | 실제(직접) | 실제(총) | 실제/이론 | 사거리 밖(초/%.0f초) | 놓친 주기 | 접근 손실 DPS | 못 맞힌 타수 | 못 맞힌 피해 | 이탈 손실 DPS |\n" % REAL_SEC
	md += "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
	for wid_v in weapons:
		var wid := String(wid_v)
		for lv_v in levels:
			var lv := int(lv_v)
			for k_v in mods_ax:
				var k := int(k_v)
				var rs := pick(real_rows, wid, lv, k)
				if rs.is_empty():
					continue
				var th := theory_of(wid, lv, k)
				var real_dps := avg(rs, "dps")
				md += "| %s | %d | %d | %.2f | %.2f | %.2f | %.2f | %.2f | %.0f%% | %.1f | %.1f | %.2f | %.1f | %.0f | %.2f |\n" % [
					wname(wid), lv, k, float(th.dps), float(th.direct_dps), avg(rs, "dps_after_approach"),
					avg(rs, "direct_dps"), real_dps,
					(real_dps / float(th.dps) * 100.0) if float(th.dps) > 0.0 else 0.0,
					avg(rs, "no_target_sec"), avg(rs, "lost_fires"), avg(rs, "approach_loss"),
					avg(rs, "missed_hits"), avg(rs, "missed_dmg"), avg(rs, "leash_loss")]
	md += "\n- **접근 손실** = 사거리 밖이라 발사조차 못 한 몫. '사거리 밖(초)'는 그 순간 대상이 없던 시간의 합이고,\n"
	md += "  '놓친 주기'는 그중 실제로 발사 기회를 잃은 횟수다(대기 중이던 시간은 손실이 아니다). 둘은 다른 값이다.\n"
	md += "- **못 맞힌 타수·피해** = 발사는 했는데 판정이 빗나간 몫. 쌍검은 대부분 **연타 중 이탈**(2·3타),\n"
	md += "  검은 잔류 검흔의 0.5초 뒤 검격, 망치는 예고 뒤 걸어 나간 적이 여기에 들어간다.\n\n"

	# ---- 실제 비율 ----
	md += "## 3. 실제 성능에서의 쌍검/검 비율\n\n"
	md += "| 레벨 | 개조 | 검 실제 DPS | 쌍검 실제 DPS | 쌍검/검(실제) | 쌍검/검(이론) |\n|---:|---:|---:|---:|---:|---:|\n"
	for lv_v in levels:
		var lv := int(lv_v)
		for k_v in mods_ax:
			var k := int(k_v)
			var sr := pick(real_rows, "sword", lv, k)
			var dr := pick(real_rows, "daggers", lv, k)
			if sr.is_empty() or dr.is_empty():
				continue
			var s_dps := avg(sr, "dps")
			var d_dps := avg(dr, "dps")
			var th_s := theory_of("sword", lv, k)
			var th_d := theory_of("daggers", lv, k)
			md += "| %d | %d | %.2f | %.2f | **%.3f** | %.3f |\n" % [lv, k, s_dps, d_dps,
				(d_dps / s_dps) if s_dps > 0.0 else 0.0,
				(float(th_d.dps) / float(th_s.dps)) if (not th_s.is_empty() and float(th_s.dps) > 0.0) else 0.0]
	md += "\n**1.5배 목표는 '전부 적중했을 때'(§1)에 걸린 것이고, 이 표는 움직이는 적을 상대한 별도 기록이다.**\n"
	md += "둘의 차이가 곧 접근·이탈 손실이다(§2).\n\n"

	# ---- 집중 중첩 유지율 ----
	md += "### 3-2. 쌍검 '출혈 칼날'의 집중 중첩이 실제로 얼마나 유지되나\n\n"
	md += "중첩은 같은 적을 연속으로 벨 때만 자란다. 이론 실행에서는 첫 두 주기 뒤 계속 최대지만,\n"
	md += "움직이는 적을 상대로는 붙었다 떨어질 때마다 풀린다. 아래는 **매 단계 중첩 수를 읽어 평균낸 값**이다.\n\n"
	md += "| 무기 | 레벨 | 개조 | 최대 중첩 | 평균 중첩 | 최대 유지 시간 비율 |\n|---|---:|---:|---:|---:|---:|\n"
	for lv_v in levels:
		var lv := int(lv_v)
		for k_v in mods_ax:
			var k := int(k_v)
			var rs3 := pick(real_rows, "daggers", lv, k)
			if rs3.is_empty() or int(rs3[0].focus_max) <= 0:
				continue
			md += "| %s | %d | %d | %d | %.2f | %.0f%% |\n" % [wname("daggers"), lv, k,
				int(rs3[0].focus_max), avg(rs3, "focus_avg"), avg(rs3, "focus_full_frac") * 100.0]
	md += "\n중첩이 0인 칸은 개조를 고르지 않았거나 그 개조가 뽑히지 않은 경우다(표에서 뺐다).\n\n"

	# ---- 무리 ----
	md += "## 4. 무리 상대(참고 — 검이 유리해야 정상)\n\n"
	md += "| 레벨 | 개조 |"
	for wid_v in weapons:
		md += " %s |" % wname(String(wid_v))
	md += "\n|---:|---:|"
	for _w in weapons:
		md += "---:|"
	md += "\n"
	for lv_v in levels:
		var lv := int(lv_v)
		for k_v in mods_ax:
			var k := int(k_v)
			md += "| %d | %d |" % [lv, k]
			for wid_v in weapons:
				var rs2 := pick(swarm_rows, String(wid_v), lv, k)
				md += (" %.1f |" % avg(rs2, "dps")) if not rs2.is_empty() else " - |"
			md += "\n"
	md += "\n늑대 %d기 %.0f초. 총 피해 ÷ 시간이다.\n\n" % [SWARM_N, SWARM_SEC]

	# ---- 창 '분열 창날'의 뒤쪽 무리 처리 ----
	if not line_rows.is_empty():
		var lpos := []
		for i in LINE_N:
			lpos.append("%.0f" % (LINE_FIRST + LINE_GAP * float(i)))
		md += "## 4-2. 창 '분열 창날': 일렬 무리에서 뒤쪽 적까지 가는가\n\n"
		md += "늑대 %d기를 거리 %s에 **일렬로** 세우고 창만 쏜다(표적 고정 %0.0f초). 적별 분열 피해는\n" % [LINE_N, ", ".join(lpos), LINE_SEC]
		md += "**개조 없이 같은 조건으로 한 번 더 재고 그 차이**로 가른다 — 산술 추정이 아니라 측정이다.\n"
		md += "첫 적까지 거리 %.0f는 창의 근접 약화 구간(사거리 45%%) 밖이라 셋 다 같은 배율로 맞는다.\n\n" % LINE_FIRST
		md += "| 레벨 | 발사 | 분열 발동 | 분열 적중 | 분열 피해 | 첫 적이 받은 분열 | 뒤쪽 적이 받은 분열 | 분열이 맞힌 적 수 |\n"
		md += "|---:|---:|---:|---:|---:|---:|---:|---:|\n"
		for r_v in line_rows:
			var r: Dictionary = r_v
			md += "| %d | %d | %d | %d | %.1f | **%.1f** | **%.1f** | %d |\n" % [int(r.level), int(r.fires),
				int(r.split_procs), int(r.split_hits), float(r.split_dmg), float(r.first_extra), float(r.rear), int(r.distinct)]
		md += "\n**'뒤쪽 적이 받은 분열'이 0이면 분열탄이 첫 적에게 도로 흡수된 것이다**(알려진 결함 MOD-1).\n"
		md += "분열탄은 관통하지 않으므로 한 발이 적 하나를 맞히고 사라진다 — 두 발 모두 첫 적 바로 뒤 한 마리에게 들어간다.\n\n"
		md += "### 적별 총 피해(고정 표적 %.0f초)\n\n" % LINE_SEC
		md += "| 레벨 | 적 | 개조 없음 | 분열 창날 | 차이(= 분열 몫) |\n|---:|---:|---:|---:|---:|\n"
		for r_v2 in line_rows:
			var r2: Dictionary = r_v2
			for i in LINE_N:
				md += "| %d | %d번(거리 %.0f) | %.1f | %.1f | %+.1f |\n" % [int(r2.level), i + 1,
					LINE_FIRST + LINE_GAP * float(i), float((r2.base_per as Array)[i]), float((r2.split_per as Array)[i]),
					float((r2.delta as Array)[i])]
		md += "\n### 처치 시각(실제 체력의 늑대 %d기, 적별)\n\n" % LINE_N
		md += "창은 줄을 통째로 꿰므로 '셋 다 쓰러질 때까지'만 보면 분열탄이 어디로 갔는지 드러나지 않는다.\n"
		md += "**적별 시각**을 함께 봐야 뒤쪽 적이 실제로 더 빨리 쓰러지는지 읽힌다.\n\n"
		md += "| 레벨 | 적 | 개조 없음 | 분열 창날 | 차이 |\n|---:|---:|---:|---:|---:|\n"
		for r_v3 in line_rows:
			var r3: Dictionary = r_v3
			var kb: Dictionary = r3.kill_base
			var ks: Dictionary = r3.kill_split
			for i in LINE_N:
				var b: float = float((kb.each as Array)[i])
				var s2: float = float((ks.each as Array)[i])
				md += "| %d | %d번(거리 %.0f) | %s | %s | %s |\n" % [int(r3.level), i + 1,
					LINE_FIRST + LINE_GAP * float(i), kill_text(b), kill_text(s2),
					("%+.2f초" % (s2 - b)) if (b >= 0.0 and s2 >= 0.0) else "-"]
			md += "| %d | 셋 다 | %s | %s | %s |\n" % [int(r3.level), kill_text(float(kb.all)), kill_text(float(ks.all)),
				("%+.2f초" % (float(ks.all) - float(kb.all))) if (float(kb.all) >= 0.0 and float(ks.all) >= 0.0) else "-"]
		md += "\n적은 제자리에 고정하고 물기·돌진을 껐다(재는 것은 화력이지 생존이 아니다).\n\n"
		md += "### 같은 개조가 단일 대상에 보태는 몫(거리 %.0f · 표적 1기)\n\n" % THEORY_DIST
		md += "무리 처리와 단일 대상은 **다른 이야기**라 따로 잰다. 분열탄이 앞의 적을 지나쳐 나아가면\n"
		md += "표적이 하나뿐인 자리에서는 아무것도 맞히지 못하므로 이 몫은 0이 되는 것이 정상이다.\n\n"
		md += "| 레벨 | 개조 없음 | 분열 창날 하나 | 개조가 보탠 몫 |\n|---:|---:|---:|---:|\n"
		for r_v4 in line_rows:
			var r4: Dictionary = r_v4
			var sb: float = float(r4.single_base)
			var ss: float = float(r4.single_split)
			md += "| %d | %.2f | %.2f | %+.2f (%+.0f%%) |\n" % [int(r4.level), sb, ss, ss - sb,
				((ss - sb) / sb * 100.0) if sb > 0.0 else 0.0]
		md += "\n"

	# ---- 원거리 참고 ----
	md += "## 5. 참고: 원거리 표적(거리 %.0f · 개조 없음)\n\n" % FAR_DIST
	md += "| 레벨 |"
	for wid_v in weapons:
		md += " %s |" % wname(String(wid_v))
	md += "\n|---:|"
	for _w in weapons:
		md += "---:|"
	md += "\n"
	for lv_v in levels:
		var lv := int(lv_v)
		md += "| %d |" % lv
		for wid_v in weapons:
			var v := 0.0
			for r in far_rows:
				if String(r.weapon) == String(wid_v) and int(r.level) == lv:
					v = float(r.dps)
			md += " %.2f |" % v
		md += "\n"
	md += "\n거리 %.0f는 쌍검(62)·검(95)·망치(110)의 사거리 밖이라 0이 정상이다. 창(230)·궁(320)만 닿는다 —\n" % FAR_DIST
	md += "가까이 붙어야만 나오는 §1의 값과 달리, 이 두 무기는 **접근 손실 없이** 이만큼을 계속 낸다는 뜻이다.\n\n"

	md += "## 이 표를 읽을 때 주의할 것\n\n"
	md += "1. **봇은 무기 리치를 모른다.** 모든 무기에 같은 유지 거리(%.0f, data/bots.json common.keep_dist)를 쓴다.\n" % float(PCatalog.bots().common.keep_dist)
	md += "   그래서 실제 DPS는 그 무기를 이해한 사람의 상한이 아니다. 무기별로 봇을 바꾸면 무기 비교가 아니라 봇 비교가 된다.\n"
	md += "2. **실제 DPS가 낮다고 곧바로 약한 무기는 아니다.** 접근 손실은 편성·지형·조작으로 줄어들 수 있는 몫이고,\n"
	md += "   이탈 손실은 무기 자체의 성질(연타 길이·리치)에서 오는 몫이다. 표에서 둘을 나눠 놓은 이유다.\n"
	md += "3. 늑대는 돌진(속도 800 × 0.32초)으로 플레이어를 지나쳐 멀어진다. 짧은 리치 무기의 접근 손실은\n"
	md += "   대부분 그 뒤의 재접근 시간이다.\n"
	var f := FileAccess.open(sub.out_path("res://docs/sim/DPS_PROBE.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
