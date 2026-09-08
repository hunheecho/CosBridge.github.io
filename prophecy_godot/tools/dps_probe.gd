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
const LEVELS := [1, 3, 5]
const MODS := [0, 1, 2]
const SEEDS := [1, 2, 3]
const BOT := "skilled"
const TARGET_RATIO := 1.5    # 사용자 확정: 쌍검 이론 단일 대상 DPS ≥ 검 × 1.5

var sub := PSubset.new()
var theory_rows: Array = []   # 이론 결과
var real_rows: Array = []     # 실제 결과(시드별)
var swarm_rows: Array = []    # 무리 결과(시드별)
var far_rows: Array = []      # 원거리 참고
var mod_pick: Dictionary = {} # "weapon|level|k" → [개조 id]

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
	for i in n:
		# 발사 자격이 있는가(사거리 안 + 가림 없음)를 규칙 코드와 같은 함수로 본다. 규칙은 건드리지 않는다
		if PWeapons.pick_target(st, w, rng_v, true).is_empty():
			no_target_steps += 1
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

	print("DPS_PROBE_JSON " + JSON.stringify({ "theory": theory_rows, "real": real_rows, "swarm": swarm_rows, "far": far_rows }))
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
	md += "| 무리(참고) | 늑대 %d기를 %.0f초. **검이 유리해야 정상**이다 |\n\n" % [SWARM_N, SWARM_SEC]
	md += "표적·플레이어 모두 죽지 않게 체력을 크게 둔다. 죽으면 무기마다 시간 창이 달라져 DPS를 비교할 수 없기 때문이다.\n"
	md += "개조 1·2개는 **그 무기의 단일 대상 이론 DPS가 가장 높아지는 조합을 측정으로 골랐다**(목록 순서가 아니다).\n\n"

	# ---- 개조 선택표 ----
	md += "## 고른 개조(단일 대상에 가장 유리한 조합)\n\n"
	md += "| 무기 | 개조 1 | 개조 2 |\n|---|---|---|\n"
	for wid_v in weapons:
		var wid := String(wid_v)
		var lv0: int = int(levels[0])
		md += "| %s | %s | %s |\n" % [wname(wid), mods_text(wid, best_mods(wid, lv0, 1)), mods_text(wid, best_mods(wid, lv0, 2))]
	md += "\n(레벨이 달라도 같은 조합이 뽑히면 한 줄로 적었다 — Lv%d 기준.)\n\n" % int(levels[0])

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
				md += " %.2f |" % (float(r.dps) if not r.is_empty() else 0.0)
			var dg := theory_of("daggers", lv, k)
			var sw := theory_of("sword", lv, k)
			if dg.is_empty() or sw.is_empty() or float(sw.dps) <= 0.0:
				md += " - | - |\n"
			else:
				var ratio: float = float(dg.dps) / float(sw.dps)
				md += " **%.3f** | %s |\n" % [ratio, "달성" if ratio >= TARGET_RATIO else "미달"]
	md += "\n"

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
	md += "\n"

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
				md += " %.1f |" % avg(pick(swarm_rows, String(wid_v), lv, k), "dps")
			md += "\n"
	md += "\n늑대 %d기 %.0f초. 총 피해 ÷ 시간이다.\n\n" % [SWARM_N, SWARM_SEC]

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
