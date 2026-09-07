extends Node2D
## 전투 화면: 고정 단계로 규칙(CombatState)을 진행하고, _draw()는 상태를 읽기만 한다(그리는 동안 상태 변경 없음).
## 입력 장치 → 게임 행동 변환은 여기서만 한다. 봇 모드에서는 PBot이 같은 행동 형식을 만든다.
## 그리기는 PRender(render.gd)가 맡고(예고 도형 = 실제 판정), 소리는 PAudio(자동 로드 /root/Audio가 있으면 그것, 없으면 자식으로 만든다)가 st.events를 읽어 낸다.

signal finished(summary: Dictionary)

var st: CombatState
var bot: PBot = null
var driver := PStepDriver.new()
var paused: bool = false
var running: bool = false
var frame_count: int = 0
var end_timer: float = 0.0
var decor: Dictionary = {}     # 숲 장식(시드 결정적, PRender.make_decor)
var audio: PAudio = null

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
	if audio != null:
		audio.reset(st, skip_events)
	queue_redraw()

func set_paused(v: bool) -> void:
	paused = v
	driver.reset() # 일시정지 중 생긴 입력은 재개 시 폐기. 재개 후 회피는 새 누름이 필요하다

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

func _unhandled_input(event: InputEvent) -> void:
	if not running or paused or bot != null:
		return
	if event.is_action_pressed("dodge") and not event.is_echo():
		driver.note_dodge_press() # 프레임 사이의 짧은 탭도 기록된다(다음 단계에서 1번 소비)
	if event.is_action_pressed("slowfield") and not event.is_echo():
		driver.note_special_press()

func _process(delta: float) -> void:
	if not running or st == null or paused:
		return
	frame_count += 1
	var mx := 0.0
	var my := 0.0
	var held := false
	if bot == null:
		if Input.is_action_pressed("move_left"):
			mx -= 1.0
		if Input.is_action_pressed("move_right"):
			mx += 1.0
		if Input.is_action_pressed("move_up"):
			my -= 1.0
		if Input.is_action_pressed("move_down"):
			my += 1.0
		held = Input.is_action_pressed("dodge")
	var t0 := Time.get_ticks_usec()
	var n_steps := driver.frame(st, delta, mx, my, held, bot)
	var sim_us := Time.get_ticks_usec() - t0
	_perf_record(delta, sim_us, n_steps)
	if audio != null:
		audio.drain(st)
	if st.status != "running":
		end_timer += delta
		if end_timer >= 1.3:
			running = false
			finished.emit(st.summary())
	queue_redraw()

# ---------- 그리기(읽기 전용) ----------
func _draw() -> void:
	if st == null:
		return
	if decor.is_empty() or int(decor.get("seed", -1)) != st.seed_value:
		decor = PRender.make_decor(st)
	PRender.draw(self, st, decor)
