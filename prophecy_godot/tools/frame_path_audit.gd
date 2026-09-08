extends SceneTree
## 실제 프레임 경로에서의 중복 발사 검사(화면 없음):
##   godot --headless --path prophecy_godot -s tools/frame_path_audit.gd
## 결과: docs/sim/FRAME_PATH_AUDIT.md
##
## `tools/attack_audit.gd`는 규칙(CombatState.step)에 직접 dt를 넣어 잰다. 그것만으로는
## **화면이 쓰는 경로**를 검증하지 못한다는 지적(2026-09-08 검토 §3)에 따라 이 도구를 따로 만들었다.
## 여기서는 화면과 같은 연결부 `PStepDriver.frame()`을 쓴다:
##   - 한 프레임에 여러 고정 단계를 처리한다(저프레임에서 몰아 처리).
##   - 누름(press)은 프레임 사이에 생겨도 다음 첫 단계에서 **한 번만** 소비된다.
##   - 일시정지·재개는 `reset()`으로 대기 중인 누름과 누적 시간을 버린다.
##
## 확인하려는 것: **같은 게임 시간**을 프레임률만 바꿔 진행했을 때
##   ① 자동기술 발사 수가 늘어나지 않는가
##   ② 일시정지 → 재개 뒤 몰아서 발사되지 않는가
##   ③ 대기 중인 누름이 두 번 소비되지 않는가

const STEP := 1.0 / 120.0
const GAME_SEC := 20.0
const SEED := 7
const SKILLS := ["sword", "spear", "daggers", "bow", "hammer", "blades", "orb", "frost", "ember", "mine"]

var rows := []
var notes := []

func make_state(skill: String) -> CombatState:
	var run := PRun.new_run(SEED, skill)
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": SEED,
		"waves": [[{ "type": "wolf", "n": 1 }]], "objective": "clear", "region_id": "forest",
		"pool": ["wolf"], "run": run })
	st.spawn_hold = true
	for e in st.enemies:
		e.dead = true
	st.pending.clear()
	st.player.hp = 1.0e9
	st.player.hp_max = 1.0e9
	for i in 3:
		var e := st.spawn_enemy("wolf", float(st.player.x) + 90.0 + float(i) * 40.0, float(st.player.y))
		e.hp = 1.0e9
		e.hp_max = 1.0e9
	st.metrics = CombatState._new_metrics()
	return st

## 화면과 같은 연결부로 game_sec만큼 진행한다.
##  fps      : 한 프레임의 길이(1/fps초)
##  pause_every / pause_len : 그 간격마다 그만큼 '일시정지'한다(프레임을 아예 돌리지 않고 reset)
##  press_每frame : 매 프레임 회피 누름을 예약한다(누름 중복 소비 검사용)
func run_frames(skill: String, fps: float, pause_every: float, pause_len: float, press_each: bool) -> Dictionary:
	var st := make_state(skill)
	var drv := PStepDriver.new()
	var frame_dt := 1.0 / fps
	var frames := 0
	var steps := 0
	var presses := 0
	var next_pause := pause_every
	# **같은 게임 시간**을 정확히 맞추려고 고정 단계 수로 센다(t 기준으로 멈추면 프레임률마다
	# 부동소수 누적이 달라 진행한 게임 시간이 미세하게 어긋나고, 그만큼 발사 수가 하나씩 다르게 보인다).
	# 일시정지 동안에는 단계가 진행되지 않는다(화면과 같다).
	var target_steps := int(round(GAME_SEC / STEP))
	while steps < target_steps and frames < 200000:
		if pause_every > 0.0 and st.t >= next_pause:
			drv.reset()                      # 화면의 일시정지 경로와 같다(대기 누름·누적 시간 버림)
			next_pause += pause_every + pause_len
		if press_each:
			drv.note_dodge_press()
			presses += 1
		var did := drv.frame(st, frame_dt, 0.0, 0.0, false, null)
		steps += did
		frames += 1
		if did == 0 and frames > 200000:
			break
	var s: Dictionary = st.weapons[0].stats
	return {
		"skill": skill, "fps": fps, "pause_every": pause_every, "press_each": press_each,
		"game_t": snapped(st.t, 0.01), "frames": frames, "steps": steps,
		"fires": st.metrics.cause_fires.duplicate(),
		"dodges": int(st.stats.dodges), "presses": presses,
		"interval": float(s.get("interval", 0.0)), "kind": String(s.kind),
	}

func _init() -> void:
	for skill in SKILLS:
		rows.append(run_frames(skill, 120.0, 0.0, 0.0, false))   # 기준: 화면 120프레임
		rows.append(run_frames(skill, 20.0, 0.0, 0.0, false))    # 저프레임 20
		rows.append(run_frames(skill, 8.0, 0.0, 0.0, false))     # 아주 낮은 프레임 8(한 프레임에 여러 단계)
		rows.append(run_frames(skill, 60.0, 5.0, 1.0, false))    # 5초마다 1초 일시정지 → 재개
		printerr("done ", skill)
	# 누름 중복 소비 검사(회피): 매 프레임 1회 예약 → 실제 회피 수가 예약 수를 넘지 않아야 한다
	var press_rows := []
	for fps in [120.0, 20.0, 8.0]:
		press_rows.append(run_frames("sword", fps, 0.0, 0.0, true))
	print("FRAME_PATH_JSON " + JSON.stringify({ "rows": rows, "press": press_rows }))

	var md := "# 실제 프레임 경로에서의 중복 발사 검사\n\n"
	md += "생성: `tools/frame_path_audit.gd` (%s, Godot %s). 고정 표적 3마리·게임 시간 %.0f초·시드 %d.\n" % [OS.get_name(), Engine.get_version_info().string, GAME_SEC, SEED]
	md += "화면이 쓰는 연결부 `PStepDriver.frame()`을 그대로 쓴다(한 프레임에 여러 고정 단계 처리, 누름 1회 소비, 일시정지 시 reset).\n\n"
	md += "`tools/attack_audit.gd`는 규칙에 dt를 직접 넣는 **가변 dt 스트레스**이고, 이 도구는 **실제 입력 경로** 검증이다. 둘은 목적이 다르다.\n\n"
	md += "## 같은 게임 시간에서 프레임률만 바꿨을 때의 발사 수\n\n"
	md += "모든 조건에서 **고정 단계 수를 %d개로 맞춰**(게임 시간 %.0f초) 돌린다. 프레임률만 다르고 진행한 게임 시간은 같다.\n\n" % [int(round(GAME_SEC / STEP)), GAME_SEC]
	md += "| 자동기술 | 120프레임 | 20프레임 | 8프레임 | 60프레임+일시정지 | 판정 |\n|---|---|---|---|---|---|\n"
	for skill in SKILLS:
		var by := {}
		for r in rows:
			if String(r.skill) == skill:
				by["%d_%d" % [int(r.fps), int(r.pause_every)]] = r
		var base_r: Dictionary = by.get("120_0", {})
		var key := "base"
		if String(base_r.get("kind", "")) == "orbit":
			key = "orbit"
		elif String(base_r.get("kind", "")) == "mine":
			key = "mine"
		var a := int((base_r.get("fires", {}) as Dictionary).get(key, 0))
		var b := int(((by.get("20_0", {}) as Dictionary).get("fires", {}) as Dictionary).get(key, 0))
		var c := int(((by.get("8_0", {}) as Dictionary).get("fires", {}) as Dictionary).get(key, 0))
		var d := int(((by.get("60_5", {}) as Dictionary).get("fires", {}) as Dictionary).get(key, 0))
		# 저프레임에서는 한 프레임이 고정 단계를 몰아 처리해 목표 시간을 조금 넘긴다.
		# 그래서 **게임 시간당 발사 수**로 비교한다(개수만 비교하면 그 초과분만큼 늘어 보인다).
		var ta: float = maxf(0.001, float(base_r.get("game_t", 1.0)))
		var tb: float = maxf(0.001, float((by.get("20_0", {}) as Dictionary).get("game_t", 1.0)))
		var tc: float = maxf(0.001, float((by.get("8_0", {}) as Dictionary).get("game_t", 1.0)))
		var td: float = maxf(0.001, float((by.get("60_5", {}) as Dictionary).get("game_t", 1.0)))
		var ra := float(a) / ta
		var rb := float(b) / tb
		var rc := float(c) / tc
		var rd := float(d) / td
		var bad: bool = b > a or c > a or d > a   # 단계 수를 맞췄으므로 개수 그대로 비교한다
		md += "| %s | %d (%.2f/초) | %d (%.2f/초) | %d (%.2f/초) | %d (%.2f/초) | %s |\n" % [skill, a, ra, b, rb, c, rc, d, rd, "**늘어남**" if bad else "늘지 않음"]
		if bad:
			notes.append("%s: 게임 시간당 발사 수가 늘었다(120프레임 %.2f/초 → 20프레임 %.2f · 8프레임 %.2f · 일시정지 %.2f)" % [skill, ra, rb, rc, rd])
	md += "\n일시정지 열은 게임 시간이 멈춘 동안 진행하지 않으므로 **적게 나오는 것이 정상**이고, 많아지면 비정상이다.\n"
	md += "\n## 대기 중인 누름이 두 번 소비되지 않는가 (회피)\n\n"
	md += "| 프레임 | 예약한 누름 | 실제 회피 | 판정 |\n|---|---:|---:|---|\n"
	for r in press_rows:
		var okp: bool = int(r.dodges) <= int(r.presses)
		md += "| %d프레임 | %d | %d | %s |\n" % [int(r.fps), int(r.presses), int(r.dodges), "중복 없음" if okp else "**중복**"]
		if not okp:
			notes.append("회피 누름 중복 소비(%d프레임): 예약 %d, 실제 %d" % [int(r.fps), int(r.presses), int(r.dodges)])
	md += "\n회피는 재사용 시간이 있어 예약보다 적게 나오는 것이 정상이다. **예약보다 많으면** 한 누름이 여러 번 소비된 것이다.\n"
	if notes.is_empty():
		md += "\n## 결과\n\n검사 범위에서 **실제 프레임 경로의 중복 발사·중복 소비 없음**.\n"
		md += "다만 이것은 '사용자가 본 두 발 현상의 원인을 확정했다'는 뜻이 아니다. 원인 후보는 개조가 만드는 다중 장판이며(`docs/sim/ATTACK_AUDIT.md`), 사람 화면 확인이 남아 있다.\n"
	else:
		md += "\n## 결과: 확인이 필요한 항목\n\n"
		for nt in notes:
			md += "- %s\n" % nt
	var f := FileAccess.open("res://docs/sim/FRAME_PATH_AUDIT.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
	quit(1 if not notes.is_empty() else 0)
