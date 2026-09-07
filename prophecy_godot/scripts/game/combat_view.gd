extends Node2D
## 전투 화면: 고정 단계로 규칙(CombatState)을 진행하고, _draw()는 상태를 읽기만 한다(그리는 동안 상태 변경 없음).
## 입력 장치 → 게임 행동 변환은 여기서만 한다. 봇 모드에서는 PBot이 같은 행동 형식을 만든다.

signal finished(summary: Dictionary)

var st: CombatState
var bot: PBot = null
var driver := PStepDriver.new()
var paused: bool = false
var running: bool = false
var frame_count: int = 0
var end_timer: float = 0.0

const STEP := PStepDriver.STEP
const COL_BG := Color("1b2418")
const COL_PLAYER := Color("7ef2ff")
const COL_WOLF := Color("9aa0a8")
const COL_ROCK := Color("6c6f75")
const COL_TREE := Color("3f7a3f")

func start(seed_v: int, use_bot: bool = false) -> void:
	st = Game.new_combat(seed_v)
	bot = PBot.new() if use_bot else null
	driver.reset() # 재시작 뒤 대기 입력 없음
	perf = { "frames": 0, "frame_ms_max": 0.0, "frame_ms_sum": 0.0, "sim_us_sum": 0, "sim_us_max": 0, "steps_sum": 0, "capped_frames": 0, "win_frames": 0, "win_frame_ms_max": 0.0, "win_sim_us_max": 0, "win_t": 0.0, "last_frame_ms_max": 0.0, "last_sim_us_max": 0 }
	paused = false
	running = true
	end_timer = 0.0
	frame_count = 0
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
	var W := st.arena_w
	var H := st.arena_h
	draw_rect(Rect2(0, 0, W, H), COL_BG)
	# 장애물: 그림 = 충돌 경계
	for ob in st.obstacles:
		var c := COL_ROCK if ob.type == "rock" else COL_TREE
		draw_circle(Vector2(ob.x, ob.y), ob.r, c)
		draw_arc(Vector2(ob.x, ob.y), ob.r, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 1.5)
	# 감속장
	if not st.field.is_empty():
		var f := st.field
		var life: float = f.ttl / f.max_ttl
		draw_circle(Vector2(f.x, f.y), f.r, Color(0.5, 0.75, 1.0, 0.12 + 0.1 * life))
		draw_arc(Vector2(f.x, f.y), f.r, 0.0, TAU, 64, Color(0.6, 0.85, 1.0, 0.7), 2.0)
	# 등장 예고
	for fx in st.effects:
		if fx.kind == "spawnwarn":
			var k: float = fx.t / fx.ttl
			draw_arc(Vector2(fx.x, fx.y), 18.0 + 10.0 * k, 0.0, TAU, 24, Color(1, 0.5, 0.3, 0.8 - 0.5 * k), 2.0)
	var p := st.player
	# 늑대 돌진 예고: 통로(폭 = 늑대 반지름 + 플레이어 반지름 × 2 = 실제 물기 판정), 확정되면 굵어지고 '!'
	for e in st.alive_enemies():
		if e.state == "bite_track" or e.state == "bite_lock" or e.state == "bite_hit":
			# 물기 예고: 머리 앞 짧은 부채꼴(반지름 = 실제 판정 거리 reach, 각도 = 실제 판정 각도). 추적 = 옅은 주황, 고정 = 진한 주황 + 테두리 + '!', 유효 = 흰색
			var B: Dictionary = e.def.bite
			var bang: float = e.aim_angle if e.state == "bite_track" else e.dir
			var half := float(B.arc_deg) * PI / 360.0
			var rr := float(B.reach)
			var pts := PackedVector2Array([Vector2(e.x, e.y)])
			for i in 11:
				var a: float = bang - half + half * 2.0 * float(i) / 10.0
				pts.append(Vector2(e.x + cos(a) * rr, e.y + sin(a) * rr))
			if e.state == "bite_track":
				draw_colored_polygon(pts, Color(1.0, 0.55, 0.2, 0.22 + 0.2 * (e.state_t / float(B.track))))
			elif e.state == "bite_lock":
				draw_colored_polygon(pts, Color(1.0, 0.5, 0.15, 0.55))
				draw_polyline(pts, Color(1.0, 0.7, 0.3, 0.95), 2.0)
				draw_string(ThemeDB.fallback_font, Vector2(e.x - 3.0, e.y - e.r - 8.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.7, 0.3))
			else:
				draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.7))
		if e.state == "crouch" or e.state == "lock":
			var d: Dictionary = e.def.dash
			var ang: float = e.aim_angle if e.state == "crouch" else e.dir
			var L := float(d.dash_speed) * float(d.dash_time)
			var locked: bool = e.state == "lock"
			var alpha: float = (0.75 + 0.25 * sin(st.t * 60.0)) if locked else (0.4 + 0.35 * (e.state_t / float(d.crouch)))
			var hw: float = e.r + p.r
			draw_set_transform(Vector2(e.x, e.y), ang, Vector2.ONE)
			draw_rect(Rect2(0, -hw, L, hw * 2.0), Color(1, 0.25, 0.25, alpha * 0.3))
			draw_line(Vector2(e.r, 0), Vector2(L - 12.0, 0), Color(1, 0.3, 0.3, alpha), 4.0 if locked else 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(L, 0), Vector2(L - 16, -9), Vector2(L - 16, 9)]), Color(1, 0.3, 0.3, alpha))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if locked:
				draw_string(ThemeDB.fallback_font, Vector2(e.x - 4.0, e.y - e.r - 26.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.45, 0.45))
	# 검격 범위(실제 판정 부채꼴)
	for fx in st.effects:
		if fx.kind == "arc":
			var k: float = 1.0 - fx.t / fx.ttl
			var pts := PackedVector2Array([Vector2(fx.x, fx.y)])
			var n := 18
			for i in n + 1:
				var a: float = fx.angle - fx.half + fx.half * 2.0 * float(i) / float(n)
				pts.append(Vector2(fx.x + cos(a) * fx.r, fx.y + sin(a) * fx.r))
			draw_colored_polygon(pts, Color(1, 1, 1, 0.25 * k))
			draw_polyline(pts, Color(1, 1, 1, 0.8 * k), 1.5)
	# 적
	for e in st.enemies:
		var col := COL_WOLF
		if e.dead:
			col = Color(0.4, 0.4, 0.4, maxf(0.0, 1.0 - e.death_t / 0.9))
		elif e.flash > 0.0:
			col = Color.WHITE
		elif e.state == "recover":
			col = Color(0.95, 0.8, 0.4) # 돌진 뒤 빈틈(피해 ×1.5)
		elif e.state == "dash":
			col = Color(1, 0.55, 0.45)
		elif e.state == "bite_recover":
			col = Color(0.65, 0.72, 0.85) # 물기 뒤 빈틈(보너스 없음)
		elif e.state == "bite_lock" or e.state == "bite_hit":
			col = Color(0.9, 0.7, 0.55)
		draw_circle(Vector2(e.x, e.y), e.r, col)
		draw_arc(Vector2(e.x, e.y), e.r, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.5)
		if not e.dead:
			var fa: float = e.aim_angle if (e.state == "crouch" or e.state == "bite_track") else (e.dir if (e.state == "lock" or e.state == "dash" or e.state == "bite_lock" or e.state == "bite_hit") else atan2(p.y - e.y, p.x - e.x))
			draw_circle(Vector2(e.x + cos(fa) * e.r * 0.6, e.y + sin(fa) * e.r * 0.6), 3.5, Color(1, 0.3, 0.3) if e.state != "approach" else Color(1, 0.85, 0.5))
			if e.state == "recover":
				draw_string(ThemeDB.fallback_font, Vector2(e.x - 16.0, e.y - e.r - 12.0), "빈틈!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.4))
			var hpw := 30.0
			draw_rect(Rect2(e.x - hpw / 2.0, e.y + e.r + 4.0, hpw, 4.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(e.x - hpw / 2.0, e.y + e.r + 4.0, hpw * clampf(e.hp / e.hp_max, 0.0, 1.0), 4.0), Color(0.9, 0.3, 0.3))
	# 플레이어
	var pc := COL_PLAYER
	if p.dead:
		pc = Color(0.4, 0.4, 0.5)
	elif p.dodge_active:
		pc = Color(0.75, 0.95, 1.0)
		for i in range(1, 4):
			draw_circle(Vector2(p.x - p.dodge_dx * 13.0 * i, p.y - p.dodge_dy * 13.0 * i), 9.0, Color(0.5, 0.75, 1.0, 0.28 / float(i)))
	elif p.hit_prot > 0.0 and int(floor(st.t * 20.0)) % 2 == 0:
		pc = Color(1.0, 0.6, 0.6, 0.6)
	elif p.flash > 0.0:
		pc = Color(1, 0.5, 0.5)
	draw_circle(Vector2(p.x, p.y), p.r, pc)
	draw_arc(Vector2(p.x, p.y), p.r, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 1.5)
	draw_line(Vector2(p.x, p.y), Vector2(p.x + cos(p.face) * (p.r + 6.0), p.y + sin(p.face) * (p.r + 6.0)), Color.WHITE, 2.0)
	# 이펙트
	for fx in st.effects:
		if fx.kind == "text":
			var k: float = 1.0 - fx.t / fx.ttl
			draw_string(ThemeDB.fallback_font, Vector2(fx.x - 10.0, fx.y), str(fx.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Color(fx.color), k))
		elif fx.kind == "spark":
			draw_circle(Vector2(fx.x, fx.y), 6.0 * (1.0 - fx.t / fx.ttl), Color(1, 0.85, 0.4, 0.8) if fx.crit else Color(1, 1, 1, 0.8))
		elif fx.kind == "hitflash":
			draw_rect(Rect2(0, 0, W, H), Color(1, 0.2, 0.2, 0.18 * (1.0 - fx.t / fx.ttl)))
		elif fx.kind == "death":
			draw_arc(Vector2(fx.x, fx.y), fx.r + 14.0 * (fx.t / fx.ttl), 0.0, TAU, 20, Color(1, 1, 1, 0.6 * (1.0 - fx.t / fx.ttl)), 2.0)
