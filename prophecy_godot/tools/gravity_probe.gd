extends SceneTree
## 중력핵(E) 효용 측정 — 화면 없음. **추정하지 않고 실제 전투에서 센 값만 적는다**(사용자 요구 16번).
##
## 사용:
##   godot --headless --path prophecy_godot -s tools/gravity_probe.gd
##   PROPHECY_QUICK=1 godot ... -s tools/gravity_probe.gd          # 축마다 대표값 하나(가장 작은 실행 — 큰 측정 전에 먼저)
##   PROPHECY_ONLY="scene:forest;level:2" godot ...                # 그 값들만
##   PROPHECY_SKIP="scene:boss3" / PROPHECY_LIMIT=12               # 빼기 / 조합 상한
##
## 축(tools/subset.gd PSubset): scene(장면) · level(기술 레벨) · variant(변형) · tune(시험안 후보) · seed(시드)
## 결과: docs/sim/GRAVITY_PROBE.md — **부분 실행이면 docs/sim/GRAVITY_PROBE_PARTIAL.md**(전체 실행 표와 섞지 않는다) + GRAVITY_PROBE_JSON 한 줄
##
## 세는 것(모두 규칙 안에서 실제로 일어난 사건이다. scripts/rules/skills.gd의 읽기 전용 훅 PSkills.probe):
##   사용 횟수 · 회당 피해 · 적중 수 · 맞은 대상 수 · 끌어모은 적 수와 실제로 끌려 들어온 거리 · 대상이 반지름 안에 머문 시간 · 마무리 처치 수.
## 세지 않는 것: "끌어모아서 자동기술이 더 맞았을 것" 같은 **간접 기여**. 추정 피해를 총 피해에 더하지 않는다.
##   중력핵은 도구형 기술이므로 자동기술과 DPS가 같아야 할 이유가 없다 — 표는 비중을 보여 줄 뿐 목표치가 아니다.
## 보스는 끌리지 않는다(skills.gd 중력 갱신부의 `if e.boss or e.airborne: continue`). 보스전은 따로 잰다.
##
## 어떤 수치도 최종 밸런스 승인이 아니다(전부 시험값).

const MAX_SEC_FIGHT := 180.0
const MAX_SEC_BOSS := 300.0

## 장면: 실제 지역 편성·실제 관문 보스. build는 balance.json lab.BUILDS의 관문 프리셋(막에 맞춘 기준 빌드)에서 E만 중력핵으로 바꾼다
const SCENES := {
	"forest": { "kind": "sortie", "region": "forest", "day": 1, "deep": false, "build": "stage1", "act": 1, "desc": "1일차 근교 숲 일반 조우(1막 기준 빌드)" },
	"ridge": { "kind": "sortie", "region": "ridge", "day": 2, "deep": false, "build": "stage1", "act": 1, "desc": "2일차 능선 일반 조우(1막 기준 빌드)" },
	"marsh": { "kind": "sortie", "region": "marsh", "day": 4, "deep": false, "build": "stage2", "act": 2, "desc": "4일차 습지 일반 조우(2막 기준 빌드)" },
	"deepdive": { "kind": "sortie", "region": "deep", "day": 7, "deep": true, "build": "stage3", "act": 3, "desc": "7일차 심층 더 깊이(3막 기준 빌드, 정예 섞임)" },
	"boss1": { "kind": "boss", "boss": "boss", "day": 3, "build": "stage1", "act": 1, "desc": "1관문 보스(끌리지 않는 상대)" },
	"boss2": { "kind": "boss", "boss": "guardian", "day": 6, "build": "stage2", "act": 2, "desc": "2관문 보스(엄폐·수호자)" },
	"boss3": { "kind": "boss", "boss": "eater", "day": 10, "build": "stage3", "act": 3, "desc": "3관문 보스" },
}

## 시험안 후보(모두 시험값). base는 지금 규칙 그대로 — 어떤 값도 바꾸지 않는다.
## 값의 뜻은 scripts/rules/skills.gd gravity_tune() 머리말에 있다.
const TUNES := {
	"base": { "desc": "지금 규칙 그대로(data/growth.json의 skills.gravity.tune를 건드리지 않는다)", "tune": {} },
	"nofinish": { "desc": "마무리 폭발 없음(2026-09-08 시험안 적용 전의 규칙)", "tune": { "base_collapse_mult": 0.0 } },
	"control": { "desc": "제어력 강화: 끌어당김 기본 90 → 170", "tune": { "pull_base": 170.0 } },
	"duration": { "desc": "지속 시간: 1.2 → 2.0초(틱 5 → 8, 재사용 대기 그대로)", "tune": { "dur": 2.0 } },
	"finish": { "desc": "폭발 마무리: 기본형도 끝날 때 피해 ×2.0(반지름 100) — 2026-09-08 고른 시험안", "tune": { "base_collapse_mult": 2.0 } },
	"antiboss": { "desc": "보스 상대 효과: 끌리지 않는 보스에게 틱 피해 ×2.5", "tune": { "boss_mult": 2.5 } },
	"control_finish": { "desc": "제어력 + 마무리(둘을 합친 안)", "tune": { "pull_base": 170.0, "base_collapse_mult": 2.0 } },
}

# ---------- 읽기 전용 관측자 ----------
class Watch extends RefCounted:
	var casts: Array = []
	var cur = null
	var boss_pull_events: int = 0 # 보스가 끌린 횟수(규칙상 0이어야 한다 — 검산용)

	func on_gravity(st, g: Dictionary, ev: String, data: Dictionary) -> void:
		match ev:
			"cast":
				var inside := 0
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, g.x, g.y) <= float(g.r) + float(e.r):
						inside += 1
				cur = { "t": float(st.t), "level": int(data.get("level", 1)), "variant": String(data.get("variant", "")),
					"hits": 0, "damage": 0.0, "targets": {}, "pulled": {}, "dwell": {}, "life": 0.0,
					"inside_at_cast": inside, "inside_peak": inside,
					"boss_hits": 0, "boss_damage": 0.0, "boss_dwell": 0.0,
					"collapse_hits": 0, "collapse_damage": 0.0, "kills": 0, "overkill": 0.0 }
				casts.append(cur)
			"pull":
				if cur == null:
					return
				var dt := float(data.get("dt", 0.0))
				cur.life = float(cur.life) + dt
				var inside := 0
				for e in st.alive_targets():
					if PGeom.dist(e.x, e.y, g.x, g.y) <= float(g.r) + float(e.r):
						inside += 1
						if bool(e.boss):
							cur.boss_dwell = float(cur.boss_dwell) + dt
						else:
							var k := str(e.id)
							(cur.dwell as Dictionary)[k] = float((cur.dwell as Dictionary).get(k, 0.0)) + dt
				if inside > int(cur.inside_peak):
					cur.inside_peak = inside
				for it in data.get("list", []):
					var en: Dictionary = it.e
					if bool(en.boss):
						boss_pull_events += 1
					var pk := str(en.id)
					var P: Dictionary = cur.pulled
					if not P.has(pk):
						P[pk] = { "first": float(it.before), "min": float(it.after) }
					else:
						(P[pk] as Dictionary).min = minf(float((P[pk] as Dictionary).min), float(it.after))
			"tick", "collapse":
				if cur == null:
					return
				for it in data.get("list", []):
					var en: Dictionary = it.e
					var dealt := float(it.dealt) # 규칙이 계산한 명목 피해(damage_enemy의 반환값)
					# 유효 피해(실제로 줄어든 체력) = 통계 화면과 같은 기준. 남은 체력을 넘긴 몫(과잉)은 빼고 센다
					var eff := dealt if float(en.hp) >= 0.0 else maxf(0.0, float(en.hp) + dealt)
					cur.hits = int(cur.hits) + 1
					cur.damage = float(cur.damage) + eff
					cur.overkill = float(cur.overkill) + (dealt - eff)
					(cur.targets as Dictionary)[str(en.id)] = true
					if ev == "collapse":
						cur.collapse_hits = int(cur.collapse_hits) + 1
						cur.collapse_damage = float(cur.collapse_damage) + eff
					if bool(en.boss):
						cur.boss_hits = int(cur.boss_hits) + 1
						cur.boss_damage = float(cur.boss_damage) + eff
					if float(en.hp) <= 0.0:
						cur.kills = int(cur.kills) + 1
			"end":
				cur = null

# ---------- 보조 ----------
func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _r1(v: float) -> float: return round(v * 10.0) / 10.0
func _r2(v: float) -> float: return round(v * 100.0) / 100.0

var _orig_tune: Dictionary = {}   # 데이터 정본의 조절값(base로 되돌릴 때 쓴다)
var _orig_read := false

## 조절값 적용: 카탈로그(메모리 캐시)의 skills.gravity.tune만 바꾼다. 파일은 건드리지 않는다.
## "base"는 **데이터 정본 그대로**를 뜻한다(지운다는 뜻이 아니다 — 정본에 시험값이 들어 있으면 그 값으로 잰다).
func _apply_tune(id: String) -> void:
	var SK := PCatalog.skills()
	if not SK.has("gravity"):
		return
	var G: Dictionary = SK.gravity
	if not _orig_read:
		_orig_tune = (G.get("tune", {}) as Dictionary).duplicate()
		_orig_read = true
	var t: Dictionary = (TUNES[id] as Dictionary).tune
	if id == "base":
		if _orig_tune.is_empty():
			G.erase("tune")
		else:
			G["tune"] = _orig_tune.duplicate()
	else:
		var merged := _orig_tune.duplicate()
		for k in t:
			merged[k] = t[k]
		G["tune"] = merged

## 장면 빌드: 관문 프리셋 + E를 중력핵(요청 레벨·변형)으로 교체
func _make_run(scene: Dictionary, seed_v: int, level: int, variant: String) -> Dictionary:
	var preset: Dictionary = PCatalog.lab().BUILDS[String(scene.build)]
	var gw: Dictionary = preset.growth
	var first := String((gw.weapons as Array)[0].id)
	var run := PRun.new_run(seed_v, first)
	run.day = int(scene.day)
	var g: Dictionary = run.growth
	var ws := []
	for w in gw.weapons:
		ws.append({ "id": String(w.id), "level": int(w.level), "mods": (w.mods as Array).duplicate() if w.has("mods") else [] })
	g.weapons = ws
	var cm := {}
	for k in gw.get("commons", {}):
		cm[String(k)] = int(gw.commons[k])
	g.commons = cm
	var ps := {}
	for k in gw.get("passives", {}):
		ps[String(k)] = int(gw.passives[k])
	g.passives = ps
	if gw.has("q"):
		g.skills.q.level = int(gw.q.get("level", 1))
		g.skills.q.variant = String(gw.q.variant) if gw.q.get("variant", null) != null else null
	g.skills.e = { "id": "gravity", "level": level, "variant": (variant if variant != "" else null) }
	var br := []
	for id in gw.get("bossRewards", []):
		br.append(String(id))
	g.bossRewards = br
	var lv := 1
	for w in ws:
		lv += int(w.level) - 1 + (w.mods as Array).size()
	for k in cm:
		lv += int(cm[k])
	for k in ps:
		lv += int(ps[k])
	g.level = lv
	run.hp = float(PRun.build(run).hp_max)
	return run

## 전투 하나. 반환: 이 전투의 관측 + 전투 요약
func _fight(scene_id: String, seed_v: int, level: int, variant: String) -> Dictionary:
	var scene: Dictionary = SCENES[scene_id]
	var run := _make_run(scene, seed_v, level, variant)
	var st: CombatState
	var max_sec := MAX_SEC_FIGHT
	if String(scene.kind) == "boss":
		var b := PRun.build(run)
		max_sec = MAX_SEC_BOSS
		st = CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": seed_v, "boss": true, "boss_id": String(scene.boss),
			"boss_hp": _boss_hp(run, String(scene.boss)), "arena": "clearing", "region_id": "boss",
			"xp_kill_mult": PRun.kill_xp_mult(run), "run": run })
	else:
		# 실제 출격과 같은 조우 옵션(PFlow.encounter_opts). 시간·금화를 쓰지 않고 조우만 만든다
		var sortie := { "regionId": String(scene.region), "deep": bool(scene.deep), "encounters": 0,
			"seed": seed_v * 131 + int(scene.day) * 17, "day": int(scene.day), "slot": 0, "variant": null }
		st = CombatState.new(PFlow.encounter_opts(run, sortie))
	var w := Watch.new()
	PSkills.probe = w
	var bot := PBot.new("balanced")
	var n := int(round(max_sec / PBot.STEP))
	for i in n:
		if st.status != "running":
			break
		st.step(bot.step_input(st), PBot.STEP)
	PSkills.probe = null
	if st.status == "running":
		st.status = "timeout"
		st.delayed.clear()
	var total := 0.0
	for k in st.metrics.dmg:
		total += float(st.metrics.dmg[k])
	var grav := float(st.metrics.dmg.get("skill:gravity", 0.0))
	return { "watch": w, "elapsed": float(st.t), "status": String(st.status), "total": total, "grav_metric": grav,
		"e_uses": int(st.stats.e_uses), "kills": int(st.stats.kills),
		"boss_left": (float(st.boss.hp) if not st.boss.is_empty() else 0.0),
		"boss_max": (float(st.boss.hp_max) if not st.boss.is_empty() else 0.0) }

func _boss_hp(run: Dictionary, bid: String) -> float:
	for b in PRun.mode_def(run).bosses:
		if String(b.id) == bid:
			return PRun.boss_hp(run, bid)
	return float(PCatalog.boss_def(bid).hp)

## 여러 전투의 관측을 하나의 행으로 모은다
func _fold(scene_id: String, level: int, variant: String, tune: String, runs: Array) -> Dictionary:
	var casts := 0
	var hits := 0
	var damage := 0.0
	var targets := 0
	var pulled := 0
	var pull_dist := 0.0
	var dwell := 0.0
	var dwell_units := 0
	var kills := 0
	var boss_hits := 0
	var boss_damage := 0.0
	var boss_dwell := 0.0
	var collapse_damage := 0.0
	var overkill := 0.0
	var inside_cast := 0
	var inside_peak := 0
	var life := 0.0
	var elapsed := 0.0
	var total := 0.0
	var grav_metric := 0.0
	var e_uses := 0
	var boss_pull := 0
	var statuses := {}
	for r in runs:
		var w: Watch = r.watch
		elapsed += float(r.elapsed)
		total += float(r.total)
		grav_metric += float(r.grav_metric)
		e_uses += int(r.e_uses)
		boss_pull += w.boss_pull_events
		statuses[String(r.status)] = int(statuses.get(String(r.status), 0)) + 1
		for c in w.casts:
			casts += 1
			hits += int(c.hits)
			damage += float(c.damage)
			targets += (c.targets as Dictionary).size()
			kills += int(c.kills)
			boss_hits += int(c.boss_hits)
			boss_damage += float(c.boss_damage)
			boss_dwell += float(c.boss_dwell)
			collapse_damage += float(c.collapse_damage)
			overkill += float(c.overkill)
			inside_cast += int(c.inside_at_cast)
			inside_peak += int(c.inside_peak)
			life += float(c.life)
			for k in c.pulled:
				var p: Dictionary = (c.pulled as Dictionary)[k]
				pulled += 1
				pull_dist += maxf(0.0, float(p.first) - float(p.min))
			for k2 in c.dwell:
				dwell_units += 1
				dwell += float((c.dwell as Dictionary)[k2])
	var nc := maxf(1.0, float(casts))
	return { "scene": scene_id, "level": level, "variant": variant, "tune": tune, "fights": runs.size(),
		"casts": casts, "e_uses": e_uses, "elapsed": _r1(elapsed),
		"dmg_per_cast": _r1(damage / nc), "hits_per_cast": _r2(float(hits) / nc), "targets_per_cast": _r2(float(targets) / nc),
		"pulled_per_cast": _r2(float(pulled) / nc), "pull_dist": _r1(pull_dist / maxf(1.0, float(pulled))),
		"inside_at_cast": _r2(float(inside_cast) / nc), "inside_peak": _r2(float(inside_peak) / nc),
		"dwell_per_cast": _r2(dwell / nc), "dwell_per_target": _r2(dwell / maxf(1.0, float(dwell_units))),
		"life": _r2(life / nc), "kills_per_cast": _r2(float(kills) / nc),
		"boss_hits_per_cast": _r2(float(boss_hits) / nc), "boss_dmg_per_cast": _r1(boss_damage / nc), "boss_dwell_per_cast": _r2(boss_dwell / nc),
		"collapse_share": (_r1(collapse_damage / damage * 100.0) if damage > 0.0 else 0.0),
		"damage": _r1(damage), "overkill": _r1(overkill), "grav_metric": _r1(grav_metric), "total": _r1(total),
		"share": (_r1(damage / total * 100.0) if total > 0.0 else 0.0),
		"dps": (_r2(damage / elapsed) if elapsed > 0.0 else 0.0),
		"status": statuses }

func _row_md(r: Dictionary) -> String:
	return "| %s | %d | %s | %s | %d | %.1f | %.2f | %.2f | %.2f | %.1f | %.2f | %.2f | %.2f | %.1f | %.2f | %.1f%% |\n" % [
		String(r.scene), int(r.level), ("기본" if String(r.variant) == "" else String(r.variant)), String(r.tune), int(r.casts),
		float(r.dmg_per_cast), float(r.hits_per_cast), float(r.targets_per_cast), float(r.pulled_per_cast), float(r.pull_dist),
		float(r.dwell_per_cast), float(r.dwell_per_target), float(r.kills_per_cast), float(r.damage), float(r.dps), float(r.share)]

func _init() -> void:
	var sub := PSubset.new()
	var t0 := Time.get_ticks_msec()
	var pass_id := _env("PROPHECY_GRAV_PASS", "both") # measure(측정) | candidates(후보 비교) | both
	var seeds_all := []
	for s in _env("PROPHECY_GRAV_SEEDS", "11,18,25").split(",", false):
		seeds_all.append(int(String(s).strip_edges()))
	var scenes := sub.pick("scene", SCENES.keys())
	var seeds := sub.pick("seed", seeds_all)
	var rows := []
	var stopped := false

	# 1) 측정: 지금 규칙 그대로(tune=base)
	if pass_id != "candidates":
		var levels := sub.pick("level", [1, 2, 3])
		var variants := sub.pick("variant", ["", "collapse", "orbit"])
		_apply_tune("base")
		for sc in scenes:
			for lv in levels:
				for v in variants:
					if not sub.more():
						stopped = true
						break
					var runs := []
					for sd in seeds:
						runs.append(_fight(String(sc), int(sd), int(lv), String(v)))
					var row := _fold(String(sc), int(lv), String(v), "base", runs)
					row.pass_id = "measure"
					rows.append(row)
					printerr("gravity_probe[측정] %s lv%d %s → 사용 %d · 회당 피해 %.1f · 회당 적중 %.2f · 끌어모음 %.2f" % [String(sc), int(lv), ("기본" if String(v) == "" else String(v)), int(row.casts), float(row.dmg_per_cast), float(row.hits_per_cast), float(row.pulled_per_cast)])
				if stopped:
					break
			if stopped:
				break

	# 2) 후보 비교: 같은 장면·같은 레벨·기본 변형에서 조절값만 바꾼다
	if pass_id != "measure" and not stopped:
		var clevel := int(sub.pick("level", [2])[0])
		var tunes := sub.pick("tune", TUNES.keys())
		for sc in scenes:
			for tn in tunes:
				if not sub.more():
					stopped = true
					break
				_apply_tune(String(tn))
				var runs := []
				for sd in seeds:
					runs.append(_fight(String(sc), int(sd), clevel, ""))
				var row := _fold(String(sc), clevel, "", String(tn), runs)
				row.pass_id = "candidates"
				rows.append(row)
				printerr("gravity_probe[후보] %s %s → 회당 피해 %.1f · 끌어모음 %.2f(%.1fpx) · 체류/대상 %.2f초" % [String(sc), String(tn), float(row.dmg_per_cast), float(row.pulled_per_cast), float(row.pull_dist), float(row.dwell_per_target)])
			if stopped:
				break
		_apply_tune("base")

	var partial := sub.partial() or stopped
	var md := "# 중력핵(E) 측정 — 실제 전투에서 센 값 (%s)\n\n" % Game.VERSION
	md += "생성: `tools/gravity_probe.gd`. %s\n\n" % sub.describe(not partial)
	if stopped:
		md += "조합 상한(PROPHECY_LIMIT)에 걸려 도중에 멈췄다. 아래는 **거기까지의 결과**다.\n\n"
	md += "읽는 법 / 세지 않는 것\n\n"
	md += "- 모든 값은 규칙 안에서 실제로 일어난 사건을 센 것이다(읽기 전용 훅 `PSkills.probe`). 판정·수명·피해를 바꾸지 않는다.\n"
	md += "- **간접 기여를 추정 피해로 만들어 총 피해에 더하지 않았다.** '끌어모아서 자동기술이 더 맞았을 것'은 이 표에 없다.\n"
	md += "- 중력핵은 도구형 기술이다. 자동기술과 DPS가 같아야 할 이유가 없으므로 '비중'은 목표치가 아니라 관찰값이다.\n"
	md += "- 보스는 끌리지 않는다(`scripts/rules/skills.gd`). 보스 장면(boss1~3)의 '끌어모은 적'은 보스를 뺀 잡몹 수다.\n"
	md += "- 봇(balanced) 조작이며 사람 실력·재미가 아니다. **전부 시험값이고 밸런스 승인이 아니다.**\n\n"
	md += "장면: "
	var sdesc := []
	for k in SCENES:
		sdesc.append("`%s` %s" % [String(k), String(SCENES[k].desc)])
	md += " · ".join(sdesc) + "\n\n"
	md += "시드 %s, 장면·설정마다 %d전투.\n\n" % [str(seeds), seeds.size()]

	var head := "| 장면 | Lv | 변형 | 설정 | 사용 | 회당 피해 | 회당 적중 | 회당 대상 | 끌어모은 적 | 끌린 거리px | 회당 체류(대상·초) | 대상당 체류초 | 회당 처치 | 총 E 피해 | E DPS | 전투 피해 비중 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	var meas := rows.filter(func(r): return String(r.pass_id) == "measure")
	if not meas.is_empty():
		md += "## 1. 지금 규칙 측정\n\n" + head
		for r in meas:
			md += _row_md(r)
		md += "\n### 보스전 따로 보기(보스는 끌리지 않는다)\n\n"
		md += "| 장면 | Lv | 변형 | 사용 | 보스 회당 적중 | 보스 회당 피해 | 보스 회당 체류초 | 보스가 끌린 횟수 | 결과 |\n|---|---|---|---|---|---|---|---|---|\n"
		for r in meas:
			if not String(r.scene).begins_with("boss"):
				continue
			md += "| %s | %d | %s | %d | %.2f | %.1f | %.2f | %d | %s |\n" % [String(r.scene), int(r.level), ("기본" if String(r.variant) == "" else String(r.variant)), int(r.casts), float(r.boss_hits_per_cast), float(r.boss_dmg_per_cast), float(r.boss_dwell_per_cast), 0, JSON.stringify(r.status)]
		md += "\n'보스가 끌린 횟수'는 규칙상 0이며 계측으로도 확인했다(0이 아니면 규칙이 깨진 것이다).\n\n"
	var cand := rows.filter(func(r): return String(r.pass_id) == "candidates")
	if not cand.is_empty():
		md += "## 2. 시험안 후보 비교(같은 장면·같은 레벨·기본 변형, 조절값만 다름)\n\n"
		md += "각 후보는 **지금 데이터 값 위에** 그 항목만 덮어쓴 것이다(`data/growth.json`의 `skills.gravity.tune`).\n"
		md += "`base`는 지금 데이터 그대로이고, 이미 적용된 시험안을 끄고 보려면 그 후보(예: `nofinish`)를 본다.\n\n"
		md += "| 설정 | 뜻 |\n|---|---|\n"
		for k in TUNES:
			md += "| `%s` | %s |\n" % [String(k), String(TUNES[k].desc)]
		md += "\n" + head
		for r in cand:
			md += _row_md(r)
		md += "\n"
	md += "\n실행 벽시계: %.1f초.\n" % ((Time.get_ticks_msec() - t0) / 1000.0)
	var out := "res://docs/sim/GRAVITY_PROBE.md" if not partial else "res://docs/sim/GRAVITY_PROBE_PARTIAL.md"
	out = _env("PROPHECY_GRAV_OUT", out)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	print("GRAVITY_PROBE_JSON " + JSON.stringify(rows))
	print("gravity_probe 완료: %d행 → %s" % [rows.size(), out])
	quit()
