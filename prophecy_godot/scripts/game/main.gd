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
	go_title()
	if OS.get_environment("PROPHECY_MOVIE") != "":
		_movie_mode = true
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
var _movie_fights := 0
var _movie_pause_left := 0
var _movie_paused_once := false
var _movie_result_left := 0

# 영상 기록용 흐름(타이머·await 없이 프레임 수로만 진행: Movie Maker 모드에서도 같은 순서를 보장)
func _movie_tick() -> void:
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
		if _movie_result_left >= 60:
			_movie_result_left = 0
			_movie_fights += 1
			if _movie_fights >= 2:
				get_tree().quit()
			else:
				start_fight(true)

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
			view.pending_dodge = true
			view.pending_special = true
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
			print("PAUSE_CHECK pending_cleared_on_resume=", (not view.pending_dodge) and (not view.pending_special))
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
	$UI/HUD/Settings.text = Game.settings_text() + ("  · 봇 조작" if bot else "")

func set_pause(v: bool) -> void:
	view.set_paused(v)
	pause_panel.visible = v
	if not v:
		controls_panel.visible = false

func show_controls(v: bool) -> void:
	controls_panel.visible = v
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
	$UI/Result/VBox/Body.text = "시간 %s초 · 처치 %d · 받은 피해 %d · 공격 %d회(명중 %d) · 회피 %d · 감속장 %d\n피해 출처: %s\n같은 조건(시드 %d)으로 다시 시작할 수 있습니다." % [str(summary.elapsed), summary.kills, int(summary.damage_taken), summary.attacks, summary.hits, summary.dodges, summary.special_uses, ", ".join(dmg_lines), summary.seed]

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
	if _capture_mode:
		_capture_tick()
	if _movie_mode:
		_movie_tick()
	if screen == "combat" and view.st != null:
		var st: CombatState = view.st
		var p := st.player
		var P: Dictionary = Game.config.player
		$UI/HUD/HP.value = p.hp / p.hp_max * 100.0
		$UI/HUD/HPText.text = "체력 %d / %d" % [int(ceil(p.hp)), int(p.hp_max)]
		var dcd: float = float(P.dodge.cooldown)
		$UI/HUD/Dodge.value = (1.0 if p.dodge_active else (1.0 - clampf(p.dodge_cd / dcd, 0.0, 1.0))) * 100.0
		$UI/HUD/DodgeText.text = "Space 회피 " + ("회피 중" if p.dodge_active else ("준비" if p.dodge_cd <= 0.0 else "%.1f초" % p.dodge_cd))
		var qcd: float = float(P.slowfield.cooldown)
		$UI/HUD/Q.value = (1.0 - clampf(p.special_cd / qcd, 0.0, 1.0)) * 100.0
		$UI/HUD/QText.text = "Q 감속장 " + ("준비" if p.special_cd <= 0.0 else "%.1f초" % p.special_cd) + ("  (전개 중 %.1f초)" % st.field.ttl if not st.field.is_empty() else "")
		var r := st.remaining()
		$UI/HUD/Objective.text = "목적: 전멸 · 남은 적 %d (지금 %d) · 남은 웨이브 %d / %d · %.1f초" % [r.total, r.alive, r.waves_left, r.waves, st.t]
		if debug_panel.visible:
			$UI/Debug/Text.text = "검증 패널 (F3)\n%s\n스텝 %d · 프레임 %d · 이번 프레임 단계 %d · fps %d\n플레이어 (%.1f, %.1f) 회피cd %.2f Qcd %.2f 무적 %.2f\n적 %d: %s\n통계 %s" % [Game.settings_text(), st.step_n, view.frame_count, view.steps_this_frame, Engine.get_frames_per_second(), p.x, p.y, p.dodge_cd, p.special_cd, p.hit_prot, st.alive_enemies().size(), ", ".join(st.alive_enemies().map(func(e): return "%s(%.0f) %s" % [e.type, e.hp, e.state])), str(st.stats)]
