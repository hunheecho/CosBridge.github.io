extends Node2D
## 전투 화면: 고정 단계로 규칙(CombatState)을 진행하고, _draw()는 상태를 읽기만 한다(그리는 동안 상태 변경 없음).
## 입력 장치 → 게임 행동 변환은 PInputRouter(router)가 맡는다(키보드·게임패드 InputMap + 가상 터치 상태 → PStepDriver 형식). 봇 모드에서는 PBot이 같은 행동 형식을 만든다.
## 그리기는 PRender(render.gd)가 맡고(예고 도형 = 실제 판정), 소리는 PAudio(자동 로드 /root/Audio가 있으면 그것, 없으면 자식으로 만든다)가 st.events를 읽어 낸다.

signal finished(summary: Dictionary)

var st: CombatState
var bot: PBot = null
var driver := PStepDriver.new()
var router := PInputRouter.new() # 장치 → 행동(키보드 경로는 0.4.3과 동일한 값, 터치 오버레이가 가상 상태를 넣는다)
var paused: bool = false
var running: bool = false
var frame_count: int = 0
var end_timer: float = 0.0
var decor: Dictionary = {}     # 숲 장식(시드 결정적, PRender.make_decor)
var audio: PAudio = null
var time_scale: float = 1.0 # 검증 자동 진행 전용(PROPHECY_UI_SPEED). 규칙은 고정 단계라 결과는 같고 벽시계만 빨라진다

const STEP := PStepDriver.STEP

func _ready() -> void:
	var a := get_node_or_null("/root/Audio")
	if a != null and a is PAudio:
		audio = a
	else:
		audio = PAudio.new()
		audio.name = "Audio"
		add_child(audio)

func start(seed_v: int, use_bot: bool = false) -> void:
	st = Game.new_combat(seed_v)
	bot = PBot.new() if use_bot else null
	_begin(false)

## 준비된 상태(다른 화면 흐름·시험)를 그대로 받아 진행한다. 이미 쌓인 이벤트는 소리 내지 않는다
func start_state(state: CombatState, use_bot: PBot = null) -> void:
	st = state
	bot = use_bot
	_begin(true)

func _begin(skip_events: bool) -> void:
	driver.reset() # 재시작 뒤 대기 입력 없음
	perf = { "frames": 0, "frame_ms_max": 0.0, "frame_ms_sum": 0.0, "sim_us_sum": 0, "sim_us_max": 0, "steps_sum": 0, "capped_frames": 0, "win_frames": 0, "win_frame_ms_max": 0.0, "win_sim_us_max": 0, "win_t": 0.0, "last_frame_ms_max": 0.0, "last_sim_us_max": 0 }
	paused = false
	running = true
	end_timer = 0.0
	frame_count = 0
	decor = PRender.make_decor(st)
	_mv_setup() # 이동 진단 초기화(계측 전용)
	if audio != null:
		audio.reset(st, skip_events)
	queue_redraw()

func set_paused(v: bool) -> void:
	paused = v
	driver.reset() # 일시정지 중 생긴 입력은 재개 시 폐기. 재개 후 회피는 새 누름이 필요하다
	router.reset() # 가상 스틱·유지 상태도 폐기(손가락이 그대로여도 다시 눌러야 한다)
	_mv_note("일시정지 " + ("켬" if v else "끔"))

## 대기 입력·가상 스틱을 지금 즉시 버린다(화면이 세로로 바뀌는 등, 손가락이 화면에서 사라진 것과 같게 만들 때).
## set_paused와 같은 폐기 경로를 쓰지만 일시정지 여부는 건드리지 않는다
func release_inputs(reason: String = "") -> void:
	driver.reset()
	router.reset()
	_mv_note("입력 해제" + ((" · " + reason) if reason != "" else ""))

func steps_this_frame() -> int:
	return driver.steps_last_frame

# ---------- 성능 기록(표시·보고용): 프레임 간격·시뮬레이션 시간·단계 상한 도달(=시뮬레이션 지연) ----------
var perf := { "frames": 0, "frame_ms_max": 0.0, "frame_ms_sum": 0.0, "sim_us_sum": 0, "sim_us_max": 0, "steps_sum": 0, "capped_frames": 0, "win_frames": 0, "win_frame_ms_max": 0.0, "win_sim_us_max": 0, "win_t": 0.0, "last_frame_ms_max": 0.0, "last_sim_us_max": 0 }

func _perf_record(delta: float, sim_us: int, n_steps: int) -> void:
	perf.frames += 1
	perf.frame_ms_sum += delta * 1000.0
	perf.frame_ms_max = maxf(perf.frame_ms_max, delta * 1000.0)
	perf.sim_us_sum += sim_us
	perf.sim_us_max = maxi(perf.sim_us_max, sim_us)
	perf.steps_sum += n_steps
	if n_steps >= PStepDriver.MAX_STEPS_PER_FRAME:
		perf.capped_frames += 1
	perf.win_frames += 1
	perf.win_frame_ms_max = maxf(perf.win_frame_ms_max, delta * 1000.0)
	perf.win_sim_us_max = maxi(perf.win_sim_us_max, sim_us)
	perf.win_t += delta
	if perf.win_t >= 1.0:
		perf.last_frame_ms_max = perf.win_frame_ms_max
		perf.last_sim_us_max = perf.win_sim_us_max
		perf.win_frames = 0
		perf.win_frame_ms_max = 0.0
		perf.win_sim_us_max = 0
		perf.win_t = 0.0

func perf_text() -> String:
	if perf.frames == 0:
		return "성능: -"
	return "성능: 평균 프레임 %.1fms(최근 1초 최대 %.1fms, 전체 최대 %.1fms) · 시뮬 %.2fms/프레임(최대 %.2fms) · 단계 상한 도달 %d/%d 프레임" % [perf.frame_ms_sum / perf.frames, perf.last_frame_ms_max, perf.frame_ms_max, perf.sim_us_sum / 1000.0 / perf.frames, perf.sim_us_max / 1000.0, perf.capped_frames, perf.frames]

func perf_summary() -> Dictionary:
	return { "frames": perf.frames, "avg_frame_ms": snapped(perf.frame_ms_sum / maxf(1.0, perf.frames), 0.01), "max_frame_ms": snapped(perf.frame_ms_max, 0.01), "avg_sim_ms": snapped(perf.sim_us_sum / 1000.0 / maxf(1.0, perf.frames), 0.001), "max_sim_ms": snapped(perf.sim_us_max / 1000.0, 0.001), "avg_steps": snapped(float(perf.steps_sum) / maxf(1.0, perf.frames), 0.01), "capped_frames": perf.capped_frames }

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		driver.reset() # 포커스 상실: 대기 입력 폐기(눌린 키 상태는 엔진이 해제한다)
		router.reset()
		_mv_note("창 포커스 상실")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_mv_note("창 포커스 복귀")

func _unhandled_input(event: InputEvent) -> void:
	if not running or paused or bot != null:
		return
	router.handle_event(event, driver) # 프레임 사이의 짧은 탭도 기록된다(다음 단계에서 1번 소비)

func _process(delta: float) -> void:
	if not running or st == null or paused:
		return
	frame_count += 1
	var mx := 0.0
	var my := 0.0
	var held := false
	if bot == null:
		var a := router.poll() # 키보드·게임패드 + 가상 터치(없으면 키보드만: 0.4.3과 같은 값)
		mx = float(a.mx)
		my = float(a.my)
		held = bool(a.held)
	var t0 := Time.get_ticks_usec()
	var px0: float = st.player.x
	var py0: float = st.player.y
	var n_steps := driver.frame(st, delta * time_scale, mx, my, held, bot)
	var sim_us := Time.get_ticks_usec() - t0
	_move_watch(delta, mx, my, held, n_steps, px0, py0)
	_perf_record(delta, sim_us, n_steps)
	if audio != null:
		audio.drain(st)
	if st.status != "running":
		end_timer += delta
		if end_timer >= 1.3:
			running = false
			finished.emit(st.summary())
	queue_redraw()

# ---------- 이동 진단(계측 전용) ----------
## 목적: "움직이려는 입력이 있는데 실제로 안 움직인다"를 다음에 또 겪었을 때 증거가 자동으로 남게 한다.
## 추적 순서: 장치 입력(mx,my,held) → 시뮬레이션에 넘긴 값 → 실제 이동량(px) → 거부 이유.
## 규칙·난수·연출은 건드리지 않는다(읽기와 출력만). 자동 진행 진단(_auto_diagnostics)과 같은 방식으로 값만 남긴다.
## 환경 변수
##  - PROPHECY_MOVE_LOG=<초> : 그 간격으로 현재 이동 진단을 계속 출력한다(0이면 매 프레임). 없으면 아래 감시만 동작한다.
##  - PROPHECY_MOVE_STUCK=<초>: 이동 의도가 있는데 못 움직인 시간이 이 값을 넘으면 1회 보고한다(기본 3초).
## 보고 형식: "MOVE_STUCK ..." / "MOVE_DEAD_INPUT ..." / "MOVE_LOG ..." 한 줄 + JSON
const MOVE_EPS := 0.5              # 이 정도(px) 이하로 움직였으면 '안 움직였다'로 본다
var move_stuck_sec := 3.0          # 이동 의도가 있는데 못 움직인 시간이 이 값을 넘으면 보고
var _mv_log_every := -1.0          # PROPHECY_MOVE_LOG(초). 음수면 정기 출력 안 함
var _mv_log_t := 0.0
var _mv_stuck_t := 0.0             # 이동 의도가 있는데 못 움직인 누적 시간
var _mv_idle_t := 0.0              # 이동 입력이 계속 0인 누적 시간(입력 경로 단절 감시)
var _mv_reported := 0              # 보고 횟수(반복 도배 방지: 10초 간격)
var _mv_report_t := 0.0
var _mv_last: Dictionary = {}      # 마지막 프레임의 진단 값(main·시험이 읽는다)
var _mv_events: Array = []         # 최근 사건(일시정지 켬/끔·포커스 상실/복귀·전투 시작)
var _mv_snap_t := 0.0              # 진단 사전을 마지막으로 만든 뒤 지난 시간(매 프레임 만들지 않기 위한 간격)

func _mv_setup() -> void:
	var s := OS.get_environment("PROPHECY_MOVE_LOG")
	_mv_log_every = float(s) if s != "" else -1.0
	var k := OS.get_environment("PROPHECY_MOVE_STUCK")
	if k != "":
		move_stuck_sec = maxf(0.2, float(k))
	_mv_log_t = 0.0
	_mv_stuck_t = 0.0
	_mv_idle_t = 0.0
	_mv_reported = 0
	_mv_report_t = 0.0
	_mv_snap_t = 0.0
	_mv_last = {}
	_mv_events = []
	_mv_note("전투 시작")

## 이동에 영향을 주는 사건(일시정지·포커스)을 최근 8개만 남긴다. 멈춘 직전에 무슨 일이 있었는지 보려는 것
func _mv_note(what: String) -> void:
	_mv_events.append("%s@%s" % [what, ("t=%.1f" % st.t) if st != null else "-"])
	if _mv_events.size() > 8:
		_mv_events.remove_at(0)

## 이번 프레임의 입력·이동량을 기록하고, 막힌 상태가 이어지면 한 번 보고한다.
## 진단 사전은 매 프레임 만들지 않는다(평상시 0.25초마다 1회, 이상이 보이면 그 프레임에 바로).
func _move_watch(delta: float, mx: float, my: float, held: bool, n_steps: int, px0: float, py0: float) -> void:
	var moved := sqrt(pow(st.player.x - px0, 2.0) + pow(st.player.y - py0, 2.0))
	var wants: bool = (bot != null) or absf(mx) > 0.0 or absf(my) > 0.0
	var ended: bool = String(st.status) != "running" or st.intro > 0.0
	if ended:
		_mv_stuck_t = 0.0
		_mv_idle_t = 0.0
	else:
		# ① 움직이려는데 못 움직인다 / ② 이동 입력 자체가 계속 0이다(장치→라우터 경로 단절·입력 잠금 의심)
		_mv_stuck_t = (_mv_stuck_t + delta) if (wants and moved <= MOVE_EPS and n_steps > 0) else 0.0
		_mv_idle_t = (_mv_idle_t + delta) if (not wants and n_steps > 0) else 0.0
		_mv_report_t += delta
	var log_due := false
	if _mv_log_every >= 0.0:
		_mv_log_t += delta
		log_due = _mv_log_t >= _mv_log_every
	_mv_snap_t += delta
	if not (log_due or _mv_stuck_t > 0.0 or _mv_idle_t >= 10.0 or _mv_snap_t >= 0.25):
		return
	_mv_snap_t = 0.0
	var d := _move_snapshot(mx, my, held, n_steps, moved)
	_mv_last = d
	if log_due:
		_mv_log_t = 0.0
		print("MOVE_LOG ", JSON.stringify(d))
	if ended:
		return
	# 경계에 붙어 그 방향을 계속 누르는 것은 정상 조작이라 바로 보고하지 않는다(이유가 벽뿐일 때만 오래 기다린다)
	var wall_only: bool = (d["이유"] as Array).size() == 1 and String((d["이유"] as Array)[0]) == "경기장 벽에 붙음"
	var need: float = maxf(move_stuck_sec, 15.0) if wall_only else move_stuck_sec
	if _mv_stuck_t >= need and _mv_report_t >= 10.0:
		_mv_report_t = 0.0
		_mv_reported += 1
		d["stuck_sec"] = snappedf(_mv_stuck_t, 0.1)
		print("MOVE_STUCK ", JSON.stringify(d))
	elif _mv_idle_t >= 20.0 and _mv_report_t >= 20.0:
		_mv_report_t = 0.0
		_mv_reported += 1
		d["idle_sec"] = snappedf(_mv_idle_t, 0.1)
		print("MOVE_DEAD_INPUT ", JSON.stringify(d))

## 지금 이동을 막고 있는 것으로 보이는 이유들(위에서부터 확인). 추정이 아니라 실제 값에서 뽑는다
func _move_reasons(mx: float, my: float, moved: float) -> Array:
	var out := []
	if bot != null:
		out.append("봇 조종(사람 입력 무시)")
	if paused:
		out.append("일시정지")
	if not running:
		out.append("전투 정지(running=false)")
	if st == null:
		out.append("상태 없음")
		return out
	if String(st.status) != "running":
		out.append("전투 종료(status=%s)" % String(st.status))
	if st.intro > 0.0:
		out.append("도입 연출(intro=%.2f)" % st.intro)
	if bool(st.player.get("dodge_active", false)):
		out.append("회피 이동 중(걷기 입력 무시)")
	if bot == null and absf(mx) <= 0.0 and absf(my) <= 0.0:
		out.append("이동 입력 0(장치→라우터)")
	var spd: float = float(st.cfg.player.speed) * float(st.build.speed_mult)
	if spd <= 0.0:
		out.append("이동 속도 0(speed=%.1f × 배율=%.2f)" % [float(st.cfg.player.speed), float(st.build.speed_mult)])
	for ob in st.obstacles: # 겹침 > 0 = 장애물 안/표면에 붙어 있다
		var ov: float = float(ob.r) + float(st.player.r) - sqrt(pow(float(ob.x) - st.player.x, 2.0) + pow(float(ob.y) - st.player.y, 2.0))
		if ov >= -0.5:
			out.append("장애물 접촉·겹침 %s(%.1fpx)" % [String(ob.id), ov])
	var p: Dictionary = st.player
	if p.x <= float(p.r) + 0.5 or p.y <= float(p.r) + 0.5 or p.x >= st.arena_w - float(p.r) - 0.5 or p.y >= st.arena_h - float(p.r) - 0.5:
		out.append("경기장 벽에 붙음")
	if out.is_empty() and moved <= MOVE_EPS:
		out.append("이유 불명(위 항목 모두 아님)")
	return out

func _move_snapshot(mx: float, my: float, held: bool, n_steps: int, moved: float) -> Dictionary:
	var d := {
		"입력": { "mx": snappedf(mx, 0.01), "my": snappedf(my, 0.01), "held": held },
		"장치": {
			"키보드": [Input.is_action_pressed("move_left"), Input.is_action_pressed("move_right"), Input.is_action_pressed("move_up"), Input.is_action_pressed("move_down")],
			"가상스틱": [snappedf(router.virtual_move.x, 0.01), snappedf(router.virtual_move.y, 0.01)],
			"가상유지": router.virtual_held, "가상입력있었음": router.virtual_used,
			"터치모드": PLayout.is_touch(),
		},
		"단계": { "steps": n_steps, "acc": snappedf(driver.acc, 0.0001), "dodge_pending": driver.press_pending, "q_pending": driver.special_pending, "e_pending": driver.e_pending },
		"이동": snappedf(moved, 0.01),
		"봇": bot != null, "일시정지": paused, "진행": running, "시간배율": time_scale,
	}
	if st != null:
		d["전투"] = {
			"status": String(st.status), "t": snappedf(st.t, 0.1), "intro": snappedf(st.intro, 0.01), "step_n": st.step_n,
			"위치": [snappedf(st.player.x, 0.1), snappedf(st.player.y, 0.1)], "반지름": float(st.player.r),
			"체력": snappedf(float(st.player.hp), 0.1), "회피중": bool(st.player.get("dodge_active", false)),
			"이동배율": snappedf(float(st.build.speed_mult), 0.01), "기본속도": float(st.cfg.player.speed),
			"경기장": [int(st.arena_w), int(st.arena_h)], "arena": st.arena_id, "region": st.region_id,
			"장애물수": st.obstacles.size(), "탈출예외": st.stuck_escapes,
		}
	d["최근사건"] = _mv_events.duplicate()
	d["이유"] = _move_reasons(mx, my, moved)
	return d

## 마지막 프레임의 이동 진단(main 자동 진행 진단·시험이 읽는다). 아직 없으면 지금 값으로 만든다
func move_diag() -> Dictionary:
	if _mv_last.is_empty() and st != null:
		return _move_snapshot(0.0, 0.0, false, 0, 0.0)
	return _mv_last

# ---------- 그리기(읽기 전용) ----------
func _draw() -> void:
	if st == null:
		return
	if decor.is_empty() or int(decor.get("seed", -1)) != st.seed_value:
		decor = PRender.make_decor(st)
	PRender.draw(self, st, decor)
