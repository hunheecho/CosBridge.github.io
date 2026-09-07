extends Node
## 화면 전환: 제목 → 전투(HUD) → 결과(다시 시작) / Esc 일시정지 / 조작법 / 검증 패널(F3). 규칙은 CombatView 안의 CombatState만 바꾼다.

@onready var view: Node2D = $CombatView
@onready var title: Control = $UI/Title
@onready var hud: Control = $UI/HUD
@onready var pause_panel: Control = $UI/Pause
@onready var result_panel: Control = $UI/Result
@onready var controls_panel: Control = $UI/Controls
@onready var debug_panel: Control = $UI/Debug
var screen := "title"
var use_bot := false
var seed_v := 7
var last_summary: Dictionary = {}

func _ready() -> void:
	view.finished.connect(_on_finished)
	$UI/Title/VBox/StartBtn.pressed.connect(func(): start_fight(false))
	$UI/Title/VBox/BotBtn.pressed.connect(func(): start_fight(true))
	$UI/Title/VBox/ControlsBtn.pressed.connect(func(): show_controls(true))
	$UI/Title/VBox/QuitBtn.pressed.connect(func(): get_tree().quit())
	$UI/Pause/VBox/ResumeBtn.pressed.connect(func(): set_pause(false))
	$UI/Pause/VBox/ControlsBtn.pressed.connect(func(): show_controls(true))
	$UI/Pause/VBox/TitleBtn.pressed.connect(func(): go_title())
	$UI/Result/VBox/RetryBtn.pressed.connect(func(): start_fight(use_bot))
	$UI/Result/VBox/TitleBtn.pressed.connect(func(): go_title())
	$UI/Controls/VBox/CloseBtn.pressed.connect(func(): show_controls(false))
	$UI/Title/VBox/Version.text = Game.settings_text()
	$UI/Title/VBox/SeedSpin.value = seed_v
	_setup_debug_options()
	go_title()
	if OS.get_environment("PROPHECY_FORMATION") != "":
		set_formation(OS.get_environment("PROPHECY_FORMATION"), Game.dash_max)
	if OS.get_environment("PROPHECY_MOVIE") != "":
		_movie_mode = true
		_movie_single = OS.get_environment("PROPHECY_MOVIE") == "single"
	if OS.get_environment("PROPHECY_DODGE_DEMO") != "":
		_demo_mode = true
		if OS.get_environment("PROPHECY_DODGE_MODE") != "":
			set_dodge_settings(OS.get_environment("PROPHECY_DODGE_MODE"), float(OS.get_environment("PROPHECY_DODGE_CD")) if OS.get_environment("PROPHECY_DODGE_CD") != "" else Game.dodge_cooldown)
	if OS.get_environment("PROPHECY_CAPTURE") != "":
		_capture_dir = OS.get_environment("PROPHECY_CAPTURE")
		_capture_mode = true

# ---------- 검증용 자동 캡처(환경 변수 PROPHECY_CAPTURE=<폴더>): 봇 전투를 돌리며 화면을 저장하고 종료 ----------
var _capture_mode := false
var _capture_dir := ""
var _cap_frame := 0
var _cap_done := {}

func _snap(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_capture_dir.path_join(name + ".png"))
	print("CAPTURE ", name, " ", img.get_width(), "x", img.get_height())

var _movie_mode := false
var _movie_single := false
var _movie_fights := 0
var _movie_pause_left := 0
var _movie_paused_once := false
var _movie_result_left := 0

# 영상 기록용 흐름(타이머·await 없이 프레임 수로만 진행: Movie Maker 모드에서도 같은 순서를 보장)
func _movie_tick() -> void:
	if _demo_mode:
		return # 회피 시연은 자체 흐름으로 진행·종료한다
	_cap_frame += 1
	if _cap_frame % 60 == 0:
		print("MOVIE frame ", _cap_frame, " screen=", screen, " t=", (view.st.t if view.st != null else -1.0))
	if _cap_frame == 45 and screen == "title":
		start_fight(true)
		return
	if screen == "combat" and view.st != null:
		if _movie_pause_left > 0:
			_movie_pause_left -= 1
			if _movie_pause_left == 0:
				set_pause(false)
		elif _movie_fights == 0 and not _movie_paused_once and view.st.t >= 6.0:
			_movie_paused_once = true
			set_pause(true) # 일시정지 화면도 영상에 담는다(1.5초)
			_movie_pause_left = 45
	elif screen == "result":
		_movie_result_left += 1
		if _movie_result_left >= 90:
			_movie_result_left = 0
			_movie_fights += 1
			if _movie_fights >= 2 or _movie_single:
				print("MOVIE_SUMMARY ", JSON.stringify(last_summary), " PERF ", JSON.stringify(view.perf_summary()))
				get_tree().quit()
			else:
				start_fight(true)
	if screen == "combat" and view.st != null and view.st.t >= 75.0 and view.running:
		print("MOVIE_CUT t=75 ", JSON.stringify(view.st.summary()), " PERF ", JSON.stringify(view.perf_summary()))
		get_tree().quit()

func _capture_tick() -> void:
	_cap_frame += 1
	if _cap_frame == 20 and not _cap_done.has("title"):
		_cap_done["title"] = true
		_snap("01_title")
		start_fight(true)
	if screen == "combat" and view.st != null:
		var t: float = view.st.t
		if t >= 2.0 and not _cap_done.has("c1"):
			_cap_done["c1"] = true
			_snap("02_combat_wave1")
		if t >= 5.0 and not _cap_done.has("pause"):
			_cap_done["pause"] = true
			set_pause(true)
			var t0: float = view.st.t
			var cd0: float = view.st.player.dodge_cd
			var q0: float = view.st.player.special_cd
			# 일시정지 중 입력이 들어와도 재개 후 남지 않아야 한다(대기 입력은 재개 시 비운다)
			view.driver.note_dodge_press()
			view.driver.note_special_press()
			for i in range(30):
				await get_tree().process_frame
			print("PAUSE_CHECK time_frozen=", view.st.t == t0, " dodge_cd_frozen=", view.st.player.dodge_cd == cd0, " q_cd_frozen=", view.st.player.special_cd == q0)
			_snap("03_pause")
			debug_panel.visible = true
			await get_tree().process_frame
			_snap("04_debug_panel")
			debug_panel.visible = false
			show_controls(true)
			await get_tree().process_frame
			_snap("05_controls")
			show_controls(false)
			set_pause(false)
			print("PAUSE_CHECK pending_cleared_on_resume=", (not view.driver.press_pending) and (not view.driver.special_pending))
			await get_tree().process_frame
			print("PAUSE_CHECK time_resumed=", view.st.t > t0)
		if t >= 8.0 and not _cap_done.has("c2"):
			_cap_done["c2"] = true
			_snap("06_combat_later")
	if screen == "result" and not _cap_done.has("result"):
		_cap_done["result"] = true
		await get_tree().process_frame
		_snap("07_result")
		print("CAPTURE_SUMMARY ", JSON.stringify(last_summary))
		print("CAPTURE_PERF ", JSON.stringify(view.perf_summary()))
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()

func go_title() -> void:
	screen = "title"
	view.running = false
	view.set_paused(false)
	view.visible = false
	title.visible = true
	hud.visible = false
	pause_panel.visible = false
	result_panel.visible = false
	controls_panel.visible = false

func start_fight(bot: bool) -> void:
	use_bot = bot
	seed_v = int($UI/Title/VBox/SeedSpin.value)
	screen = "combat"
	title.visible = false
	result_panel.visible = false
	pause_panel.visible = false
	view.visible = true
	hud.visible = true
	view.start(seed_v, bot)
	$UI/HUD/Settings.text = Game.settings_short(view.st.cfg) + ("  · 봇 조작" if bot else "")
	$UI/HUD/Demo.text = ""
	_refresh_debug_note()

func set_pause(v: bool) -> void:
	view.set_paused(v)
	pause_panel.visible = v
	if not v:
		controls_panel.visible = false

func controls_text() -> String:
	var c: Dictionary = view.st.cfg if (screen == "combat" and view.st != null) else Game.current_config()
	var D: Dictionary = c.player.dodge
	var S: Dictionary = c.player.slowfield
	var dodge_line := ""
	if String(D.mode) == "hold":
		dodge_line = "Space: 회피 — 누르면 즉시 출발. 떼면 짧게 멈춤(최소 %d). 계속 누르면 최대 %d.\n   짧게 써도 재사용 대기(%.1f초, 출발 순간부터)는 같음. 무적은 회피 이동 중에만(최대 %.2f초).\n   방향은 출발 순간 고정: 이동 중이면 그 방향, 아니면 바라보는 방향. 바위·나무·경계에 막히면 그 자리에서 끝남." % [int(D.min_distance), int(D.distance), float(D.cooldown), float(D.duration)]
	else:
		dodge_line = "Space: 회피 — 누르면 즉시 출발, 떼도 %d까지 감(고정 거리·비교용). 재사용 %.1f초(출발 순간부터). 무적은 회피 이동 중에만(최대 %.2f초).\n   방향은 출발 순간 고정: 이동 중이면 그 방향, 아니면 바라보는 방향." % [int(D.distance), float(D.cooldown), float(D.duration)]
	return "WASD / 방향키: 이동\n%s\nQ: 감속장 (반지름 %d, %.0f초, 안의 적 속도·준비 %.0f%%, 재사용 %.0f초)\n자동 공격: 사거리 안의 가장 가까운 적을 향해 검격 (%.2f초마다)\nEsc: 일시정지 / 재개 · F3: 검증 패널(회피 방식·재사용 비교 설정, 다음 재시작에 적용)\n\n읽어야 할 것\n주황 짧은 부채꼴: 늑대의 물기 예고(머리 앞, 판정 범위와 같음). 진해지고 '!'가 뜨면 방향 고정 — 옆·뒤로 빠지세요. 흰색 = 물어뜨리는 순간. 물기 뒤 잠시 멈춤(연한 파랑, 보너스 없음).\n붉은 통로: 늑대가 돌진할 길(동시 최대 %d마리). 굵어지며 '!'가 뜨면 방향이 고정됨 — 옆으로 피하세요.\n통로의 폭 = 실제 판정 폭. 흰 큰 부채꼴 = 검격의 실제 판정 범위.\n노란 늑대 = 돌진 뒤 빈틈 (피해 1.5배). 파란 원 = 감속장 범위. 몸이 닿기만 해서는 피해가 없습니다.\n바위·나무의 테두리 = 충돌 경계. 돌진도 막힙니다.\n밝은 플레이어 + 잔상 = 회피 이동 중(무적, 적의 몸을 통과). 잔상이 사라지면 무적도 끝." % [dodge_line, int(S.radius), float(S.duration), float(S.slow) * 100.0, float(S.cooldown), float(c.weapon.interval), int(c.enemies.wolf.dash.max_concurrent)]

func show_controls(v: bool) -> void:
	controls_panel.visible = v
	if v:
		$UI/Controls/VBox/Body.text = controls_text()
	if screen == "combat" and view.paused:
		pause_panel.visible = not v # 조작법 위에 일시정지 글자가 비치지 않게
	if screen == "title":
		title.visible = not v

func _on_finished(summary: Dictionary) -> void:
	last_summary = summary
	screen = "result"
	result_panel.visible = true
	var won: bool = summary.status == "won"
	$UI/Result/VBox/Title.text = "전투 승리" if won else "패배"
	var dmg_lines := []
	for k in summary.dmg:
		dmg_lines.append("%s %s" % [k, str(snapped(summary.dmg[k], 0.1))])
	var dists := []
	for d in summary.dodge_dists:
		dists.append(str(int(round(float(d)))))
	var mw: Dictionary = summary.enemies.get("wolf", {})
	var spn: int = maxi(1, int(mw.get("spawned", 0)))
	var taken_lines := []
	for k in summary.taken:
		taken_lines.append("%s %s" % [k, str(snapped(summary.taken[k], 0.1))])
	$UI/Result/VBox/Body.text = "편성 %s(전체 %d, 동시 돌진 %d) · 늑대 체력 %.0f · 시간 %s초 · 처치 %d/%d · 받은 피해 %d(%s)\n늑대 1마리당 물기 %.2f / 돌진 %.2f · 예고 전 사망 %d · 실행 전 사망 %d(%.0f%%) · 최대 생존 %d · 최대 돌진상태 %d · 경험치 %.2f(마리당 %.2f)\n공격 %d회(명중 %d) · 회피 %d(회피! %d) · 감속장 %d · 피해 출처: %s\n회피 설정: %s · 재사용 %.1f초 · 회피 거리: %s\n같은 조건(시드 %d, 같은 적 배치)으로 다시 시작할 수 있습니다." % [String(summary.formation), int(summary.spawn_total), int(summary.dash_max), float(summary.wolf_hp), str(summary.elapsed), summary.kills, int(summary.spawn_total), int(summary.damage_taken), (", ".join(taken_lines) if taken_lines.size() > 0 else "없음"), float(mw.get("bites_executed", 0)) / spn, float(mw.get("dashes_executed", 0)) / spn, int(mw.get("died_before_attack", 0)), int(mw.get("died_before_execute", 0)), 100.0 * float(mw.get("died_before_execute", 0)) / spn, int(summary.max_alive), int(summary.max_dash_states), float(summary.xp), float(summary.xp) / maxf(1.0, float(summary.kills)), summary.attacks, summary.hits, summary.dodges, summary.perfect_dodges, summary.special_uses, ", ".join(dmg_lines), Game.dodge_mode_name(summary.dodge_mode), float(summary.dodge_cooldown), (", ".join(dists) if dists.size() > 0 else "없음"), summary.seed]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if screen == "combat" and view.running:
			if controls_panel.visible:
				controls_panel.visible = false
			else:
				set_pause(not view.paused)
			get_viewport().set_input_as_handled()
		elif controls_panel.visible:
			controls_panel.visible = false
	if event.is_action_pressed("debug_panel"):
		debug_panel.visible = not debug_panel.visible
	if event.is_action_pressed("confirm"):
		if screen == "title":
			start_fight(false)
		elif screen == "result":
			start_fight(use_bot)

func _process(_dt: float) -> void:
	if _demo_mode:
		_demo_tick(_dt)
	if _capture_mode:
		_capture_tick()
	if _movie_mode:
		_movie_tick()
	if screen == "combat" and view.st != null:
		var st: CombatState = view.st
		var p := st.player
		var P: Dictionary = st.cfg.player
		$UI/HUD/HP.value = p.hp / p.hp_max * 100.0
		$UI/HUD/HPText.text = "체력 %d / %d" % [int(ceil(p.hp)), int(p.hp_max)]
		var dcd: float = float(P.dodge.cooldown)
		$UI/HUD/Dodge.value = (1.0 - clampf(p.dodge_cd / dcd, 0.0, 1.0)) * 100.0
		var guide := "짧게/길게 눌러 거리 조절" if String(P.dodge.mode) == "hold" else "고정 %d" % int(P.dodge.distance)
		$UI/HUD/DodgeText.text = "Space 회피 · " + ("회피 중 %d" % int(p.dodge_dist) if p.dodge_active else (guide if p.dodge_cd <= 0.0 else "%.1f초" % p.dodge_cd))
		var qcd: float = float(P.slowfield.cooldown)
		$UI/HUD/Q.value = (1.0 - clampf(p.special_cd / qcd, 0.0, 1.0)) * 100.0
		$UI/HUD/QText.text = "Q 감속장 " + ("준비" if p.special_cd <= 0.0 else "%.1f초" % p.special_cd) + (" · 전개 %.1f초" % st.field.ttl if not st.field.is_empty() else "")
		var r := st.remaining()
		$UI/HUD/Objective.text = "전멸 · 남은 %d · 지금 %d/%d · 돌진 %d/%d · %.1f초" % [r.total, r.alive, r.cap, st.dash_states_count(), int(st.cfg.enemies.wolf.dash.max_concurrent), st.t]
		if debug_panel.visible:
			var r2 := st.remaining()
			var mw: Dictionary = st.metrics.enemies.get("wolf", {})
			$UI/Debug/Text.text = "검증 패널 (F3)\n%s\n스텝 %d · 프레임 %d · 이번 프레임 단계 %d · fps %d\n%s\n플레이어 (%.1f, %.1f) 회피cd %.2f 회피 %s 거리 %.1f Qcd %.2f 피격보호 %.2f 체력 %.0f\n적: 지금 %d / 상한 %d · 대기 %d · 등장 %d/%d · 돌진상태 %d(최대 %d) · 물기상태 %d(최대 %d) · 최대 생존 %d\n늑대: 물기 준비 %d 실행 %d 명중 %d · 돌진 준비 %d 실행 %d 명중 %d · 예고 전 사망 %d · 실행 전 사망 %d · 처치 %d · 경험치 %.2f\n받은 피해 %s · 회피 거리 %s" % [Game.settings_text(st.cfg), st.step_n, view.frame_count, view.steps_this_frame(), Engine.get_frames_per_second(), view.perf_text(), p.x, p.y, p.dodge_cd, ("중" if p.dodge_active else "-"), p.dodge_dist, p.special_cd, p.hit_prot, p.hp, r2.alive, r2.cap, r2.pending, r2.spawned, r2.spawn_total, st.dash_states_count(), st.stats.max_dash_states, st.bite_states_count(), st.stats.max_bite_states, st.stats.max_alive, mw.get("bites_prepared", 0), mw.get("bites_executed", 0), mw.get("bite_hits", 0), mw.get("dashes_prepared", 0), mw.get("dashes_executed", 0), mw.get("dash_hits", 0), mw.get("died_before_attack", 0), mw.get("died_before_execute", 0), mw.get("killed", 0), st.stats.xp, str(st.metrics.taken), str(st.stats.dodge_dists)]
	elif debug_panel.visible:
		$UI/Debug/Text.text = "검증 패널 (F3)\n다음 전투 설정: %s\n비교 설정은 오른쪽에서 고른다. 전투 중에는 바뀌지 않고 다음 재시작(Enter)에 적용된다." % Game.settings_text()

# ---------- 검증 패널 비교 설정(회피 방식·재사용 대기): 다음 재시작에 적용 ----------
func _setup_debug_options() -> void:
	var mode_opt: OptionButton = $UI/Debug/Opts/ModeOpt
	var cd_opt: OptionButton = $UI/Debug/Opts/CdOpt
	mode_opt.clear()
	for m in Game.config.player.dodge.modes:
		mode_opt.add_item(Game.dodge_mode_name(String(m)))
		mode_opt.set_item_metadata(mode_opt.item_count - 1, String(m))
	cd_opt.clear()
	for cdv in Game.config.player.dodge.cooldown_options:
		cd_opt.add_item("%.1f초" % float(cdv))
		cd_opt.set_item_metadata(cd_opt.item_count - 1, float(cdv))
	var form_opt: OptionButton = $UI/Debug/Opts/FormOpt
	var dash_opt: OptionButton = $UI/Debug/Opts/DashOpt
	form_opt.clear()
	for fid in ["base", "x5", "x10"]:
		var F: Dictionary = Game.config.formations[fid]
		form_opt.add_item("%s (전체 %d · 동시 %d)" % [String(F.name), int(F.total), int(F.alive_cap)])
		form_opt.set_item_metadata(form_opt.item_count - 1, fid)
	dash_opt.clear()
	for dm in Game.config.enemies.wolf.dash.concurrent_options:
		dash_opt.add_item("동시 돌진 최대 %d마리" % int(dm))
		dash_opt.set_item_metadata(dash_opt.item_count - 1, int(dm))
	_sync_debug_options()
	mode_opt.item_selected.connect(func(i): Game.dodge_mode = String(mode_opt.get_item_metadata(i)); _refresh_debug_note())
	cd_opt.item_selected.connect(func(i): Game.dodge_cooldown = float(cd_opt.get_item_metadata(i)); _refresh_debug_note())
	form_opt.item_selected.connect(func(i): Game.formation_id = String(form_opt.get_item_metadata(i)); _refresh_debug_note())
	dash_opt.item_selected.connect(func(i): Game.dash_max = int(dash_opt.get_item_metadata(i)); _refresh_debug_note())
	$UI/Debug/Opts/ApplyBtn.pressed.connect(func():
		if screen == "combat" or screen == "result":
			start_fight(use_bot))

func _sync_debug_options() -> void:
	var mode_opt: OptionButton = $UI/Debug/Opts/ModeOpt
	var cd_opt: OptionButton = $UI/Debug/Opts/CdOpt
	for i in mode_opt.item_count:
		if String(mode_opt.get_item_metadata(i)) == Game.dodge_mode:
			mode_opt.select(i)
	for i in cd_opt.item_count:
		if is_equal_approx(float(cd_opt.get_item_metadata(i)), Game.dodge_cooldown):
			cd_opt.select(i)
	var form_opt: OptionButton = $UI/Debug/Opts/FormOpt
	var dash_opt: OptionButton = $UI/Debug/Opts/DashOpt
	for i in form_opt.item_count:
		if String(form_opt.get_item_metadata(i)) == Game.formation_id:
			form_opt.select(i)
	for i in dash_opt.item_count:
		if int(dash_opt.get_item_metadata(i)) == Game.dash_max:
			dash_opt.select(i)
	_refresh_debug_note()

## 비교 설정을 코드에서 바꿀 때(캡처·시연)도 같은 경로를 쓴다
func set_dodge_settings(mode: String, cooldown: float) -> void:
	Game.dodge_mode = mode
	Game.dodge_cooldown = cooldown
	_sync_debug_options()

func set_formation(fid: String, dmax: int) -> void:
	Game.formation_id = fid
	Game.dash_max = dmax
	_sync_debug_options()

func _refresh_debug_note() -> void:
	var now := "현재 전투: " + ((Game.formation_text(view.st.cfg) + " · " + Game.dodge_text(view.st.cfg)) if (view.st != null and (screen == "combat" or screen == "result")) else "없음")
	var nc := Game.current_config()
	var next := "다음 재시작: " + Game.formation_text(nc) + " · " + Game.dodge_text(nc)
	$UI/Debug/Opts/Note.text = now + "\n" + next + "\n(전투 중에는 바뀌지 않음. 같은 시드 = 같은 적 배치)"

# ---------- 회피 시연·검증(환경 변수 PROPHECY_DODGE_DEMO=1): 실제 씬의 입력 경로(InputEventAction → _unhandled_input · Input 상태)로
# 짧은 탭 / 중간 해제 / 최대 회피 / 재사용 중 누름 / 계속 누름을 재생하고 결과를 출력한다. 적은 나오지 않게 웨이브를 미룬다 ----------
var _demo_mode := false
var _demo_t := 0.0
var _demo_i := 0
var _demo_started := false
# (시각, 행동, 라벨). 행동: press/release 는 dodge, mr = 오른쪽 이동 시작
var _demo_script := [
	[1.0, "press", "1) 짧은 탭 → 최소 70"], [1.0, "release", ""],
	[3.0, "press", "2) 0.15초 누르고 뗌 → 70~150 사이"], [3.15, "release", ""],
	[5.0, "press", "3) 계속 누름 → 최대 150"], [5.6, "release", ""],
	[5.8, "press", "4) 재사용 대기 중 누름 → 발동 없음"], [5.85, "release", ""],
	[7.0, "press", "5) 계속 누른 채 대기 시간 경과 → 자동 재발동 없음"], [9.5, "release", ""],
	[10.2, "quit", ""],
]

func _demo_action(name: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _demo_tick(delta: float) -> void:
	if not _demo_started:
		_demo_started = true
		start_fight(false)
		view.st.spawn_hold = true # 시연 동안 적 없음
		view.st.player.x = 200.0 # 오른쪽(바라보는 방향)으로 회피 4번(최대 70+150+150+150)을 해도 경계에 닿지 않는 출발점
		$UI/HUD/Demo.text = "회피 시연(적 없음) · " + Game.dodge_text(view.st.cfg)
		return
	_demo_t += delta
	while _demo_i < _demo_script.size() and float(_demo_script[_demo_i][0]) <= _demo_t:
		var row: Array = _demo_script[_demo_i]
		_demo_i += 1
		var act := String(row[1])
		if row[2] != "":
			$UI/HUD/Demo.text = "회피 시연(적 없음) · " + String(row[2])
		match act:
			"mr": _demo_action("move_right", true)
			"press": _demo_action("dodge", true)
			"release": _demo_action("dodge", false)
			"quit":
				var p: Dictionary = view.st.player
				print("DEMO_RESULT ", JSON.stringify({ "dodges": view.st.stats.dodges, "dists": view.st.stats.dodge_dists, "cd_left": snapped(p.dodge_cd, 0.01), "held_now": Input.is_action_pressed("dodge"), "mode": String(view.st.cfg.player.dodge.mode), "cooldown": float(view.st.cfg.player.dodge.cooldown), "x": snapped(p.x, 0.1) }))
				get_tree().quit()
