extends SceneTree
## 조사 전용: **보스전에서 나무가 안 깨진다**(2026-09-09 사용자 피드백)를 사실로 가른다.
##   godot --headless --path prophecy_godot -s tools/probe_tree.gd
## 규칙·수치를 하나도 바꾸지 않는다(읽기만 한다).
##
## 무엇을 가리는가
##  ① 나무가 **실제 충돌체**인가 **단순 장식**인가 — 서 있을 수 있는가·시야가 통과하는가·투사체가 막히는가.
##  ② 보스 9종 각각에 대해 플레이어를 **나무 뒤**에 세우고 한 판을 돌려, 그 나무가 부서지는가.
##     (기존 tests/boss_break_tests.gd는 breaker.types의 **첫 종류**만 골라 camp하므로 8종이 돌만 시험했다.)
##  ③ 부서진 뒤 **보이지 않는 벽**이 남지 않는가 — 그 자리에 설 수 있는가·시야가 트이는가·걸어 닿는 칸이 줄지 않는가.
##  ④ 예고(break_want가 선 시각)와 실제 파괴 시각의 순서.

const STEP := 1.0 / 120.0
const HUGE_HP := 1000000.0
const CAMP_SEC := 45.0
const BOSSES: Array = ["boss", "guardian", "eater", "gate_warden", "spore_matriarch",
	"excavation_behemoth", "frost_stalker", "blood_hunt_king", "doom_executor"]
const BOT_POLICY := "balanced"
const SEEDS := [11, 12, 13]
const FIGHT_SEC := 70.0

func ember_build() -> Dictionary:
	var g := PGrowth.new_growth("sword")
	g.weapons = [{ "id": "ember", "level": 3, "mods": ["scatter", "trail"] }]
	return PBuild.derive(PBuild.empty_run_like(g))

func make(boss_id: String, seed_v: int = 11, phase: int = 3) -> CombatState:
	PBoss.set_cover_mode("")
	PBoss.set_split_on(true)
	PBoss.set_break_on(true)
	var st := CombatState.new({ "build": ember_build(), "seed": seed_v, "arena": "clearing", "boss": true,
		"boss_id": boss_id, "region_id": "boss", "xp_kill_mult": 0.3, "boss_hp": HUGE_HP, "act": 3 })
	for i in 900:
		if String(st.boss.state) != "intro":
			break
		st.step({}, STEP)
	st.boss.phase = phase
	st.boss.phase_pending = phase
	return st

## want_type 종류의 장애물 뒤에 서는 자리. 반환 [x, y, 장애물] (없으면 [])
func camp_spot(st: CombatState, want_type: String) -> Array:
	var bz: Dictionary = st.boss
	var best := []
	var bd := -1.0
	for ob in st.obstacles:
		if String(ob.type) != want_type:
			continue
		for k in 24:
			var a: float = float(k) * TAU / 24.0
			var d: float = float(ob.r) + 26.0
			var x: float = clampf(float(ob.x) + cos(a) * d, 30.0, st.arena_w - 30.0)
			var y: float = clampf(float(ob.y) + sin(a) * d, 30.0, st.arena_h - 30.0)
			if not st.valid_pos(x, y, float(st.player.r)):
				continue
			if not st.los_blocked(float(bz.x), float(bz.y), x, y):
				continue
			var score := PGeom.dist(x, y, float(bz.x), float(bz.y))
			if score > bd:
				bd = score
				best = [x, y, ob]
	return best

## 그 자리에 계속 서 있는 한 판
func camp_run(st: CombatState, spot: Array, sec: float = CAMP_SEC) -> Dictionary:
	var bz: Dictionary = st.boss
	var phase: int = int(bz.phase)
	var start := { "x": spot[0], "y": spot[1] }
	var target: Dictionary = spot[2]
	var obs0: int = st.obstacles.size()
	var reach0 := PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, start)
	var t_break := -1.0
	var t_warn := -1.0
	var aimed := {}     # 예고로 지목한 장애물 종류별 횟수
	var last_want := false
	for i in int(sec / STEP):
		if st.status != "running" or bool(bz.dead):
			break
		st.player.x = spot[0]
		st.player.y = spot[1]
		var want: bool = bool(bz.get("break_want", false))
		if want and not last_want:
			var ob: Dictionary = bz.get("break_ob", {})
			var ty := String(ob.get("type", "?"))
			aimed[ty] = int(aimed.get(ty, 0)) + 1
			if t_warn < 0.0:
				t_warn = st.t
		last_want = want
		st.step({ "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": false }, STEP)
		st.player.hp = st.player.hp_max
		bz.phase = phase
		bz.phase_pending = phase
		if t_break < 0.0 and not (st.metrics.get("broken", []) as Array).is_empty():
			t_break = st.t
	var broken: Array = st.metrics.get("broken", [])
	var kinds := []
	for b in broken:
		kinds.append("%s(%s)" % [String(b.type), String(b.why)])
	return { "broke": broken.size(), "broken": broken, "kinds": kinds, "t_break": t_break, "t_warn": t_warn,
		"aimed": aimed, "obs0": obs0, "obs1": st.obstacles.size(), "gone": st.obstacles.find(target) < 0,
		"reach0": reach0, "reach1": PTerrain.reach_cells(st.arena_w, st.arena_h, st.obstacles, start) }

## 실제 전투 한 판(봇 조작). 종류별로 ① 시선을 막은 프레임 수 ② 예고가 지목한 횟수 ③ 실제 파괴 수를 센다.
## keepmin_sec = 남길 최소 장애물 수에 걸려 **아무것도 부술 수 없던** 시간(초).
func fight_run(boss_id: String, seed_v: int, aim_on: bool = true) -> Dictionary:
	var st := make(boss_id, seed_v)
	PBoss.set_break_aim_on(aim_on)
	var bz: Dictionary = st.boss
	var bot := PBot.new(BOT_POLICY)
	var keep_min: int = int(PTerrain.break_rules().get("keepMin", 0))
	var block := { "rock": 0, "tree": 0 }
	var aim := { "rock": 0, "tree": 0 }
	var kept := { "rock": 0, "tree": 0 }   # 예고한 그 장애물이 실제로 부서진 횟수
	var keepmin_sec := 0.0
	var last_want := false
	var want_ob := {}
	for i in int(FIGHT_SEC / STEP):
		if st.status != "running":
			break
		var bi := PBoss.blocking_index(st, bz)
		if bi >= 0:
			var ty := String((st.obstacles[bi] as Dictionary).type)
			block[ty] = int(block.get(ty, 0)) + 1
		if st.obstacles.size() <= keep_min:
			keepmin_sec += STEP
		var want: bool = bool(bz.get("break_want", false))
		if want and not last_want:
			want_ob = bz.get("break_ob", {})
			var ty2 := String(want_ob.get("type", "?"))
			aim[ty2] = int(aim.get(ty2, 0)) + 1
		elif last_want and not want and not want_ob.is_empty():
			# 자격이 내려간 순간: 지목했던 그 장애물이 실제로 사라졌는가(= 예고와 실제가 같은 것을 가리켰는가)
			if st.obstacles.find(want_ob) < 0:
				var ty3 := String(want_ob.get("type", "?"))
				kept[ty3] = int(kept.get(ty3, 0)) + 1
			want_ob = {}
		last_want = want
		st.step(bot.step_input(st), STEP)
		st.player.hp = st.player.hp_max   # 판이 일찍 끝나 기회 자체가 줄어드는 것을 막는다(파괴 기회 상한 측정)
	PBoss.set_break_aim_on(true)
	var brk := { "rock": 0, "tree": 0 }
	for b in (st.metrics.get("broken", []) as Array):
		var bty := String((b as Dictionary).type)
		brk[bty] = int(brk.get(bty, 0)) + 1
	var left := []
	for ob in st.obstacles:
		left.append("%s(%s)" % [String(ob.id), String(ob.type)])
	return { "block": block, "aim": aim, "kept": kept, "brk": brk, "keepmin_sec": keepmin_sec,
		"left": ", ".join(PackedStringArray(left)), "status": String(st.status), "t": float(st.t) }

func _init() -> void:
	var md := []
	md.append("# 조사: 보스전의 나무 — 충돌체인가 장식인가, 그리고 왜 안 깨지는가")
	md.append("")
	md.append("생성 `tools/probe_tree.gd`. **규칙·수치를 바꾸지 않았다**(읽기만 한다).")
	md.append("보스전 전장은 `scripts/rules/flow.gd:145`가 정하는 **clearing** 하나다(돌 2 · 나무 2).")
	md.append("")

	# ---------- ① 나무가 충돌체인가 ----------
	var st0 := make("boss")
	md.append("## 1. 나무는 충돌체인가 장식인가 (사실 확인)")
	md.append("")
	md.append("| 장애물 | 종류 | 중심 | 판정 r | 수관(그림) | 중심에 설 수 있나 | 표면 통과 시야 | 구실(role_of) |")
	md.append("|---|---|---|---:|---:|---|---|---|")
	for ob in st0.obstacles:
		var canv = ob.get("canopy", null)
		var stand: bool = st0.valid_pos(float(ob.x), float(ob.y), 1.0)
		var see: bool = not st0.los_blocked(float(ob.x) - float(ob.r) - 4.0, float(ob.y), float(ob.x) + float(ob.r) + 4.0, float(ob.y))
		md.append("| `%s` | %s | (%.0f, %.0f) | %.0f | %s | %s | %s | %s |" % [
			String(ob.id), String(ob.type), float(ob.x), float(ob.y), float(ob.r), str(canv),
			("예" if stand else "**아니오(막힌다)**"), ("통과" if see else "**막힌다**"),
			PTerrain.role_of(st0.arena_w, st0.arena_h, ob)])
	md.append("")
	md.append("`st.obstacles`에 실린 모든 항목은 `los_blocked` · `valid_pos` · `push_out` · `sweep_circle` · `beam_length` ·")
	md.append("`steer_dir`가 **종류를 가리지 않고** 같은 `r`로 본다(`scripts/rules/combat_state.gd`). 즉 나무도 돌과 똑같은 충돌체다.")
	md.append("")

	# ---------- ② 보스별 자료 ----------
	md.append("## 2. 보스별 파괴 설정(data/boss_behavior.json)")
	md.append("")
	md.append("| 보스 | 판정 모양 | 부술 수 있는 종류 | 파괴가 걸린 행동 |")
	md.append("|---|---|---|---|")
	for bid in BOSSES:
		var Bk: Dictionary = PBoss.beh_of(String(bid)).get("breaker", {})
		md.append("| %s | %s | %s | %s |" % [String(bid), String(Bk.get("shape", "—")), str(Bk.get("types", [])), String(Bk.get("pattern", "—"))])
	md.append("")

	# ---------- ③ 종류별 camp 실측 ----------
	md.append("## 3. 돌 뒤 / 나무 뒤에 각각 서 있었을 때(45초, 3단계, 시드 11)")
	md.append("")
	md.append("| 보스 | 엄폐 종류 | 그 뒤에 설 자리 | 예고가 지목한 것 | 부순 것 | 서 있던 엄폐가 사라졌나 | 첫 예고 | 첫 파괴 | 닿는 칸 |")
	md.append("|---|---|---|---|---|---|---:|---:|---|")
	var tree_fail := []
	var rock_fail := []
	for bid in BOSSES:
		for ty in ["rock", "tree"]:
			var st := make(String(bid))
			var spot := camp_spot(st, String(ty))
			if spot.is_empty():
				md.append("| %s | %s | **없다** | — | — | — | — | — | — |" % [String(bid), String(ty)])
				continue
			var r := camp_run(st, spot)
			var aim_txt := []
			for k in (r.aimed as Dictionary):
				aim_txt.append("%s %d회" % [String(k), int(r.aimed[k])])
			md.append("| %s | %s | (%.0f, %.0f) | %s | %s | %s | %s | %s | %d → %d |" % [
				String(bid), String(ty), float(spot[0]), float(spot[1]),
				("—" if aim_txt.is_empty() else " · ".join(PackedStringArray(aim_txt))),
				("**없다**" if int(r.broke) == 0 else ", ".join(PackedStringArray(r.kinds))),
				("예" if bool(r.gone) else "**아니오**"),
				("—" if float(r.t_warn) < 0.0 else "%.1f초" % float(r.t_warn)),
				("—" if float(r.t_break) < 0.0 else "%.1f초" % float(r.t_break)),
				int(r.reach0), int(r.reach1)])
			if not bool(r.gone):
				if String(ty) == "tree":
					tree_fail.append(String(bid))
				else:
					rock_fail.append(String(bid))
	md.append("")
	md.append("- **나무 뒤에서 그 나무가 안 사라진 보스**: %s" % ("없다" if tree_fail.is_empty() else ", ".join(PackedStringArray(tree_fail))))
	md.append("- **돌 뒤에서 그 돌이 안 사라진 보스**: %s" % ("없다" if rock_fail.is_empty() else ", ".join(PackedStringArray(rock_fail))))
	md.append("")

	# ---------- ④ 실제 전투(봇) — 진짜 판에서는 무엇이 부서지는가 ----------
	md.append("## 4. 실제 전투(봇 `%s` · 시드 %s · 최대 %d초) — 진짜 판에서 무엇이 부서지는가" % [BOT_POLICY, str(SEEDS), int(FIGHT_SEC)])
	md.append("")
	md.append("| 보스 | 시드 | 막은 것(프레임 수) | 예고가 지목한 것 | **지목한 그것이 부서짐** | 부순 것 | 남은 장애물 | 최소치에 걸려 더 못 부순 시간 |")
	md.append("|---|---:|---|---|---|---|---|---:|")
	var sum_block := { "rock": 0, "tree": 0 }
	var sum_aim := { "rock": 0, "tree": 0 }
	var sum_kept := { "rock": 0, "tree": 0 }
	var sum_break := { "rock": 0, "tree": 0 }
	var keepmin_sec := 0.0
	var off_aim := { "rock": 0, "tree": 0 }
	var off_kept := { "rock": 0, "tree": 0 }
	for bid in BOSSES:
		for sd in SEEDS:
			var r0 := fight_run(String(bid), int(sd), false)   # 개편 전(조준 정렬 없음)
			for k0 in ["rock", "tree"]:
				off_aim[k0] = int(off_aim[k0]) + int((r0.aim as Dictionary).get(k0, 0))
				off_kept[k0] = int(off_kept[k0]) + int((r0.kept as Dictionary).get(k0, 0))
			var r := fight_run(String(bid), int(sd))
			var bl: Dictionary = r.block
			var am: Dictionary = r.aim
			var br: Dictionary = r.brk
			var kp: Dictionary = r.kept
			for k in ["rock", "tree"]:
				sum_block[k] = int(sum_block[k]) + int(bl.get(k, 0))
				sum_aim[k] = int(sum_aim[k]) + int(am.get(k, 0))
				sum_kept[k] = int(sum_kept[k]) + int(kp.get(k, 0))
				sum_break[k] = int(sum_break[k]) + int(br.get(k, 0))
			keepmin_sec += float(r.keepmin_sec)
			md.append("| %s | %d | 돌 %d · 나무 %d | 돌 %d · 나무 %d | 돌 %d · 나무 %d | 돌 %d · 나무 %d | %s | %.1f초 |" % [
				String(bid), int(sd), int(bl.get("rock", 0)), int(bl.get("tree", 0)),
				int(am.get("rock", 0)), int(am.get("tree", 0)),
				int(kp.get("rock", 0)), int(kp.get("tree", 0)),
				int(br.get("rock", 0)), int(br.get("tree", 0)), String(r.left), float(r.keepmin_sec)])
	md.append("")
	md.append("**합계** — 시선을 막은 프레임: 돌 %d · 나무 %d / 예고 지목: 돌 %d · 나무 %d / **지목한 그것이 부서짐: 돌 %d · 나무 %d** / 실제 파괴: 돌 %d · 나무 %d · 최소치에 걸린 시간 합 %.1f초" % [
		int(sum_block.rock), int(sum_block.tree), int(sum_aim.rock), int(sum_aim.tree),
		int(sum_kept.rock), int(sum_kept.tree),
		int(sum_break.rock), int(sum_break.tree), keepmin_sec])
	md.append("")
	md.append("### 조준 정렬 전후(같은 시드·같은 봇) — 예고한 그 장애물이 실제로 부서졌는가")
	md.append("")
	md.append("| 파괴 조준 정렬 | 예고 지목(돌/나무) | **지목한 그것이 부서짐(돌/나무)** | 일치율 |")
	md.append("|---|---|---|---:|")
	var off_n: int = int(off_aim.rock) + int(off_aim.tree)
	var off_k: int = int(off_kept.rock) + int(off_kept.tree)
	var on_n: int = int(sum_aim.rock) + int(sum_aim.tree)
	var on_k: int = int(sum_kept.rock) + int(sum_kept.tree)
	md.append("| 끔(개편 전) | %d / %d | %d / %d | %.0f%% |" % [int(off_aim.rock), int(off_aim.tree), int(off_kept.rock), int(off_kept.tree), 100.0 * float(off_k) / maxf(1.0, float(off_n))])
	md.append("| **켬(지금)** | %d / %d | **%d / %d** | **%.0f%%** |" % [int(sum_aim.rock), int(sum_aim.tree), int(sum_kept.rock), int(sum_kept.tree), 100.0 * float(on_k) / maxf(1.0, float(on_n))])
	md.append("")

	var fa := FileAccess.open("res://docs/sim/PROBE_TREE.md", FileAccess.WRITE)
	fa.store_string("\n".join(md) + "\n")
	fa.close()
	print("\n".join(md))
	print("PROBE_TREE_DONE")
	quit()
