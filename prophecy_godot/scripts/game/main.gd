extends Node
## 화면 라우터 + 회차 흐름 연결(HTML main.js 이식). 화면(scripts/game/screens/*)은 표시와 버튼만 맡고, 규칙은 PRun/PSortie/PFlow/PGrowth/PEvents가 결정한다.
## 화면: title · pick_start · base(거점/최종 준비) · shop · equip · forge · stats · log · combat · reward · after · event · defeat · boss_result · run_result
## 오버레이: 3택(PChoiceOverlay, 열려 있으면 다른 입력 차단·전투 정지) · 일시정지 · 조작법 · 설정 · 용어 툴팁(PGlossaryTip, 고정 시 전투 정지) · F3 검증 패널
## 검증 경로: 기준 전투(첫 전투, 0.3.1 D33)는 view.start(seed, bot) 그대로. PROPHECY_CAPTURE / PROPHECY_MOVIE / PROPHECY_DODGE_DEMO 는 그 경로를 쓴다.
## PROPHECY_UI_SMOKE=<폴더>: 새 회차 → 거점 → 출격(봇) → 전투 → 승리 뒤 화면 → 상점·대장간·장비·통계 → 하루 종료 → 관문 → 보스전 → 결과까지 자동 진행하며 PNG 저장 후 종료.
## 이동 진단(계측 전용, combat_view.gd): PROPHECY_MOVE_LOG=<초>·PROPHECY_MOVE_STUCK=<초>. 자동 진단(_auto_diagnostics)의 combat.move와 심박 줄 move=에 같은 값이 들어간다. 설명은 docs/KNOWN_DEFECTS.md 부록.

@onready var view: Node2D = $CombatView
@onready var screens_root: Control = $UI/Screens
@onready var hud: Control = $UI/HUD
@onready var pause_panel: Control = $UI/Pause
@onready var result_panel: Control = $UI/Result
@onready var controls_panel: Control = $UI/Controls
@onready var debug_panel: Control = $UI/Debug
@onready var overlay_root: Control = $UI/Overlay
@onready var tips_layer: CanvasLayer = $Tips

var screen := "title"
var screens: Dictionary = {}        # name → PScreen
var run: Dictionary = {}            # 진행 중 회차({} = 없음)
var sortie: Dictionary = {}         # 진행 중 출격({} = 없음). 보스전은 regionId "boss"
var last_reward: Dictionary = {}
var last_summary: Dictionary = {}
var last_record: Dictionary = {}
var lost_loot: Dictionary = {}      # 패배 화면용(정산 전 전리품)
var lab_run: Dictionary = {}        # 검증 메뉴 임시 회차(저장하지 않음)
var lab_label := ""
var fight_kind := "first"           # first(기준 전투) | lab(검증 빠른 전투) | run(회차)
var use_bot := false
var bot_profile := "legacy"         # 검증 메뉴 봇 선택: legacy(기존 PBot 정책 그대로) | novice | regular | skilled(PSkillBot, docs/BOT_FRAMEWORK.md)
var record_inputs := false          # 검증 메뉴 '이번 전투 입력 기록'(사람 입력만, 로컬 user://recordings, 업로드 없음)
static var _data_hash_cache := ""
var seed_v := 7
var choice: PChoiceOverlay
var tips: PGlossaryTip
var settings_panel: PSettingsPanel
var glossary_paused := false
var profile: Dictionary = {}        # 영구 프로필(PProfile, 회차 저장과 별도 파일). 시험값
var last_profile_award: Dictionary = {} # 마지막 정산의 영구 기록·해금(결과 화면 한 줄)

const TEST_PROFILE_PATH := "user://prophecy_profile_test_v1.json" # PROPHECY_UI_SMOKE·봇 데모는 실제 프로필을 건드리지 않는다
var touch: PTouchControls               # 터치 오버레이(터치 화면 또는 PROPHECY_TOUCH=1일 때만 켜짐, HUD 아래 자식)
var _hud_base: Dictionary = {}          # HUD 노드 이름 → 설계 기준(960×640) offset_left/right
var build_hud: PCombatHud               # 하단 빌드 HUD(자동기술 3칸+개조·공용·장비·회피/Q/E). 표시 전용
var build_detail: PBuildDetail          # 빌드 상세(전투 중에는 공통 일시정지 경로로 연다)
var _detail_paused := false             # 빌드 상세 때문에 우리가 멈춘 상태인지

# ---------- 화면 방향·전체화면(docs/ORIENTATION.md) ----------
## 화면 크기가 바뀌었다는 신호. 주소창이 뜨고 지는 것 · 전체화면 전환 · 회전 · PC 창 크기 조절이 모두 여기로 온다.
## 조작 버튼 자리·터치 판정은 이 신호를 받는 쪽(PLayout·PTouchControls 담당)이 정한다 — 여기서는 알리기만 한다.
signal screen_metrics_changed(metrics: Dictionary)

var orient: POrientGate                 # 세로 안내 · '계속' · 전체화면 다시 들어가기(표시 전용)
var orient_paused := false              # 세로로 바뀌어서 우리가 멈춘 상태인지. 가로로 돌아와도 '계속'을 눌러야 풀린다
var _orient_layer: CanvasLayer          # 안내막 층(HUD·툴팁보다 위)
var _portrait := false                  # 마지막으로 판정한 세로 여부
var _fs_wanted := false                 # 사용자가 전체화면을 한 번이라도 요청했는가(다시 들어가는 버튼의 조건)
var _fs_active := false                 # 지금 전체화면인가(웹은 document.fullscreenElement, PC는 창 모드)
var _fs_poll_t := 0.0                   # 전체화면 상태를 다시 읽기까지 남은 시간(초)
var last_fullscreen_result: Dictionary = {} # 마지막 전체화면 요청이 실제로 무엇을 했는지(검사·보고용)
var _pause_fs_btn: Button               # 일시정지 화면의 '전체화면' 버튼(전체화면에서 빠져나왔을 때만 보인다)

const FS_POLL_SEC := 0.5                # 전체화면 상태 확인 간격(초)

func _ready() -> void:
	if OS.get_environment("PROPHECY_UI_SMOKE") != "":
		PProfile.use_path(TEST_PROFILE_PATH)
	profile = PProfile.load()
	view.finished.connect(_on_finished)
	tips = PGlossaryTip.new()
	tips_layer.add_child(tips)
	tips.pin_count_changed.connect(_on_tip_pins)
	choice = PChoiceOverlay.new()
	overlay_root.add_child(choice)
	choice.picked.connect(_on_pick)
	choice.skipped.connect(_on_skip)
	choice.rerolled.connect(_on_reroll)
	settings_panel = PSettingsPanel.new()
	overlay_root.add_child(settings_panel)
	settings_panel.closed.connect(_on_settings_closed)
	_make_screens()
	build_detail = PBuildDetail.new()
	overlay_root.add_child(build_detail)
	build_detail.closed.connect(_on_detail_closed)
	# 하단 빌드 HUD: 실제 저장 빌드(st.build)를 읽어 자동기술 3칸·개조·공용·장비·회피/Q/E를 그린다(표시 전용)
	build_hud = PCombatHud.new()
	build_hud.touch_mode = PLayout.is_touch()
	hud.add_child(build_hud)
	build_hud.ready_signal.connect(_on_ability_ready)
	_hide_legacy_ability_bars()
	touch = PTouchControls.new()
	hud.add_child(touch) # HUD와 같이 전투 중에만 보인다
	touch.bind(view, view.router)
	_make_orient_gate()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized() # 배치 + 첫 세로/가로 판정
	# 일시정지 화면에서도 같은 빌드 상세를 연다(마우스만 쓰는 경우·터치)
	var detail_btn := PUi.button("빌드 상세 (Tab)", func(): open_build_detail(), true, 14)
	$UI/Pause/VBox.add_child(detail_btn)
	$UI/Pause/VBox.move_child(detail_btn, 2)
	# 전투 중에 전체화면이 풀렸을 때 되돌아가는 길(전체화면을 쓴 적이 있을 때만 보인다)
	_pause_fs_btn = PUi.button("전체화면으로 다시 들어가기", func(): request_fullscreen_landscape(), true, 14)
	_pause_fs_btn.visible = false
	$UI/Pause/VBox.add_child(_pause_fs_btn)
	$UI/Pause/VBox.move_child(_pause_fs_btn, 3)
	$UI/Pause/VBox/ResumeBtn.pressed.connect(func(): set_pause(false))
	$UI/Pause/VBox/ControlsBtn.pressed.connect(func(): show_controls(true))
	$UI/Pause/VBox/SettingsBtn.pressed.connect(func(): open_settings())
	$UI/Pause/VBox/TitleBtn.pressed.connect(func(): give_up())
	$UI/Result/VBox/RetryBtn.pressed.connect(func(): retry_fight())
	$UI/Result/VBox/TitleBtn.pressed.connect(func(): go_title())
	$UI/Controls/VBox/CloseBtn.pressed.connect(func(): show_controls(false))
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
	if OS.get_environment("PROPHECY_MOD_DEMO") != "": # 개조 연출 연속 프레임(영상 아님)
		_mod_dir = OS.get_environment("PROPHECY_MOD_DEMO")
		_mod_demo = true
	if OS.get_environment("PROPHECY_CLIP") != "": # 실제 속도 영상 클립(Movie Maker와 함께 쓴다)
		_clip_id = OS.get_environment("PROPHECY_CLIP")
		_clip_sec = float(OS.get_environment("PROPHECY_CLIP_SEC")) if OS.get_environment("PROPHECY_CLIP_SEC") != "" else 8.0
		_clip_fps = float(OS.get_environment("PROPHECY_CLIP_FPS")) if OS.get_environment("PROPHECY_CLIP_FPS") != "" else 30.0
		_clip_mode = true
	if OS.get_environment("PROPHECY_UI_SMOKE") != "":
		_auto_dir = OS.get_environment("PROPHECY_UI_SMOKE")
		_auto_full = OS.get_environment("PROPHECY_UI_FULL") != "" # 최종 보스·회차 결과·새 회차까지 봇으로 계속
		_auto_stop = OS.get_environment("PROPHECY_UI_STOP")
		if OS.get_environment("PROPHECY_UI_SPEED") != "":
			view.time_scale = clampf(float(OS.get_environment("PROPHECY_UI_SPEED")), 1.0, 6.0)
		# 자동 진행 검증은 실력 프로필 봇을 쓴다(기존 정책 봇은 개편된 보스를 넘지 못해 화면 순회가 4일차에서 멈춘다).
		# 게임 규칙이 아니라 검증 경로 설정이며, PROPHECY_UI_BOT으로 바꿀 수 있다.
		bot_profile = OS.get_environment("PROPHECY_UI_BOT") if OS.get_environment("PROPHECY_UI_BOT") != "" else "skilled"
		_auto = true
		_auto_snap = DisplayServer.get_name() != "headless" # 헤드리스는 PNG 없이 단계만 출력
		_auto_quit = true
		_auto_t0_ms = Time.get_ticks_msec()
		_auto_last_progress_ms = _auto_t0_ms
		_auto_seg_t0 = _auto_t0_ms
		if OS.get_environment("PROPHECY_UI_MAXMIN") != "":
			_auto_budget_sec = maxf(1.0, float(OS.get_environment("PROPHECY_UI_MAXMIN"))) * 60.0
		if OS.get_environment("PROPHECY_UI_STALL") != "":
			_auto_stall_sec = maxf(10.0, float(OS.get_environment("PROPHECY_UI_STALL")))

func _make_screens() -> void:
	var defs := {
		"title": PTitleScreen, "pick_start": PPickStartScreen, "base": PBaseScreen, "shop": PShopScreen, "equip": PEquipScreen, "forge": PForgeScreen,
		"stats": PStatsScreen, "log": PLogScreen, "reward": PRewardScreen, "after": PAfterScreen, "event": PEventScreen, "defeat": PDefeatScreen,
		"boss_result": PBossResultScreen, "run_result": PRunResultScreen, "meta": PMetaScreen,
	}
	for name in defs:
		var s: PScreen = (defs[name] as GDScript).new()
		s.name = String(name)
		s.visible = false
		screens_root.add_child(s)
		s.setup(self)
		screens[String(name)] = s

# ---------- 화면 전환 ----------
func show(name: String) -> void:
	screen = name
	for k in screens:
		(screens[k] as Control).visible = (String(k) == name)
	var combat := name == "combat"
	view.visible = combat or name == "result"
	hud.visible = combat
	if combat:
		_layout_hud() # 경기장 크기(st.arena_w/h)에 맞춰 가운데 배치
		if build_hud != null and view.st != null:
			build_hud.sync_ready_silent(view.st) # 화면 진입 = 이미 준비된 기술에 알림을 다시 터뜨리지 않는다
	elif build_detail != null and build_detail.is_open():
		build_detail.close()
	if not combat:
		pause_panel.visible = false
		controls_panel.visible = false
		orient_paused = false # 전투를 벗어나면 '계속' 대기는 끝난다(세로 안내는 세로인 동안 그대로)
	_sync_orient_gate()
	result_panel.visible = name == "result"
	if screens.has(name):
		(screens[name] as PScreen).on_enter()
	if _auto:
		print("UI_SMOKE screen=", name)

func go_title() -> void:
	fight_kind = "first"
	view.running = false
	view.driver.recorder = null # 끝나지 않은 입력 기록은 버린다(저장은 전투 종료 시에만)
	orient_paused = false       # 전투를 떠나면 '계속' 대기도 끝난다(세로 안내 자체는 세로면 그대로 남는다)
	_sync_orient_gate()
	view.set_paused(false)
	choice.close()
	tips.close_all()
	settings_panel.visible = false
	show("title")

func cur_run() -> Dictionary:
	return run if fight_kind == "run" else lab_run

func message(text: String) -> void:
	print("MESSAGE ", text)
	$UI/HUD/Demo.text = text

func save_run() -> void:
	if not run.is_empty() and fight_kind == "run":
		PSave.save(run)

## 거점으로: 저장 → 완주면 회차 결과, 아니면 거점. 보류 중인 비-레벨업 3택(임무·보스·사건·심층)이 있으면 먼저 연다
func go_base() -> void:
	if run.is_empty():
		go_title()
		return
	save_run()
	# 죽은 회차(phase "dead")도 거점이 아니라 회차 결과로 간다. 예전에는 거점으로 보내서
	# 끝난 회차에 관문 준비 화면이 뜨고 계속 진행할 수 있는 것처럼 보였다
	show("run_result" if (String(run.phase) == "cleared" or PRun.is_run_over(run) or PEndless.is_over(run)) else "base")
	var g: Dictionary = run.growth
	if g.get("pendingDeepPick", null) != null or g.get("pendingBossPick", null) != null or g.get("pendingMissionPick", null) != null or (g.get("pendingOffer", null) != null and String(g.pendingOffer.pool) != "level"):
		var off = PFlow.next_offer(run)
		if off != null:
			open_choice(off)
			save_run()

func new_run_flow() -> void:
	show("pick_start")

var new_run_opts := {} # 검증 메뉴에서 정한 새 회차 옵션 { seed, density_set } — 새 회차 1회에만 쓰고 비운다

## 새 회차: 프로필의 해금 스냅샷·특성을 고정하고 영구 기록 대상(profileEligible)으로 만든다. 봇으로 진행한 전투가 있으면 _on_finished가 대상에서 뺀다.
## 검증 메뉴의 밀도 비교 회차(new_run_opts)는 시드·세트만 정하고 프로필 규칙은 같다
func start_run(weapon_id: String) -> void:
	fight_kind = "run"
	var seed_use: int = int(new_run_opts.get("seed", _auto_seed if _auto else 0))
	var route_v: Array = new_run_opts.get("route", [])
	if route_v.is_empty() and _auto and OS.get_environment("PROPHECY_UI_ROUTE") != "": # 자동 진행 스모크의 경로 고정(예: 기존 보스 3종 경로)
		route_v = Array(OS.get_environment("PROPHECY_UI_ROUTE").split(",")).map(func(t): return String(t))
	run = PRun.new_run(seed_use, weapon_id, "", { "density_set": String(new_run_opts.get("density_set", "")), "route": route_v, "profile": profile, "eligible": true })
	new_run_opts = {}
	sortie = {}
	last_profile_award = {}
	profile.runs = int(profile.get("runs", 0)) + 1
	PProfile.save(profile)
	save_run()
	go_base()

# ---------- 영구 성장(프로필) ----------
func show_meta() -> void:
	profile = PProfile.load()
	show("meta")

## 프로필 종류 전환(다른 종류는 삭제하지 않음). 진행 중 회차는 시작 시점 스냅샷 그대로
func set_profile_kind(kind: String) -> void:
	profile = PProfile.set_active(kind)
	show("meta")

## 특성 선택(출발 전 무료 재선택). 다음 새 회차부터 반영
func set_trait(level_key: int, id: String) -> void:
	if PProfile.set_trait(profile, level_key, id):
		PProfile.save(profile)
	show("meta")

## 회차 결과를 프로필에 반영·저장(정확히 1회는 PProfile의 이벤트 ID가 보장). kind: victory | boss | return
func _award_profile(kind: String, ctx: Dictionary) -> Dictionary:
	if run.is_empty() or fight_kind != "run":
		return {}
	var a := PProfile.award_from_run(profile, run, kind, ctx)
	if bool(a.get("eligible", false)) and (float(a.get("records", 0)) > 0.0 or not (a.get("challenges", []) as Array).is_empty()): # 10일 본편은 하루 2/3 기록(소수)
		PProfile.save(profile)
		var txt := PProfile.award_text(a)
		if txt != "":
			PRun.add_log(run, txt)
	return a

## 제작 확정(대장간): 검증 → 소비 → 생성 → 가방/장착을 한 번에, 저장 1회
func craft(recipe_id: String, use_equipped: bool, equip_after: bool) -> void:
	if PRun.craft(run, recipe_id, use_equipped, equip_after):
		save_run()
	else:
		message("제작할 수 없습니다(재료·금화·보유 상태를 확인)")
	show("forge")

func continue_run() -> void:
	var r := PSave.load()
	if r.is_empty():
		message("저장된 회차가 없습니다")
		return
	fight_kind = "run"
	run = r
	sortie = {}
	if run.get("pendingSortie", null) != null: # 전투 뒤 안전 화면에서 종료했다면 그 자리로
		sortie = run.pendingSortie
		var step := PFlow.after_combat_step(run, sortie)
		if step == "offer":
			show("after")
			open_choice(PFlow.next_offer(run, { "region_id": String(sortie.regionId) }))
		else:
			show(step)
		return
	go_base()

func save_quit() -> void:
	save_run()
	go_title()

# ---------- 거점 행동 ----------
func start_sortie_card(card_id: String) -> void:
	var s := PSortie.start(run, card_id)
	if s.is_empty():
		message("출격할 수 없습니다")
		return
	sortie = s
	save_run() # 출격 비용은 지불된 상태로 저장
	start_encounter()

## opt.useVoucher: 관문 앞 '휴식권 사용'을 고른 경우. 거점 휴식은 예전 그대로다
func rest(opt: Dictionary = {}) -> void:
	if PRun.rest(run, opt):
		save_run()
	show("base")

func end_day() -> void:
	if PRun.end_day(run):
		save_run()
	go_base()

func start_boss() -> void:
	var s := PEndless.start_boss(run) if PEndless.active(run) else PRun.start_boss(run)
	if s.is_empty():
		message("보스 준비 상태가 아닙니다")
		return
	sortie = s
	save_run() # 보스 직전 상태 저장
	start_encounter()

# ---------- 무한 모드(PEndless, 계획서 §10) ----------
func start_endless() -> void:
	if not PEndless.start(run):
		message("무한 모드를 시작할 수 없습니다(본편 완주 뒤 1회)")
		return
	save_run()
	go_base()

func endless_fight() -> void:
	var s := PEndless.start_fight(run)
	if s.is_empty():
		message("무한 전투를 시작할 수 없습니다")
		return
	sortie = s
	save_run()
	start_encounter()

func endless_regroup() -> void:
	if PEndless.regroup(run):
		save_run()
	show("base")

func endless_quit() -> void:
	PEndless.over(run, "quit")
	save_run()
	go_base()

## 정복자 배분(출발 전 무료 재분배, 다음 새 회차부터 반영)
func set_conqueror(key: String, n: int) -> void:
	if PProfile.set_conqueror(profile, key, n):
		PProfile.save(profile)
	show("meta")

func buy_equipment(id: String, equip: bool, from: String) -> void:
	PRun.buy_equipment(run, id, equip, from)
	save_run()
	show("shop")

func buy_skill() -> void:
	PRun.buy_skill(run)
	save_run()
	show("shop")

func buy_merchant_service() -> void:
	PRun.buy_merchant_service(run)
	save_run()
	show("shop")

func sell_equipment(id: String) -> void:
	PRun.sell_equipment(run, id)
	save_run()
	show(screen)

func sell_mat(id: String) -> void:
	PRun.sell(run, id, 1)
	save_run()
	show(screen)

func equip_item(id: String) -> void:
	PRun.equip_item(run, id)
	save_run()
	show(screen)

func unequip_item(slot: String) -> void:
	PRun.unequip_item(run, slot)
	save_run()
	show(screen)

func forge_upgrade(weapon_id: String = "") -> void:
	PRun.forge_upgrade(run, weapon_id)
	save_run()
	show("forge")

func mod_change(weapon_id: String, mod_id: String) -> void:
	var off := PFlow.mod_change(run, weapon_id, mod_id)
	save_run()
	if off.is_empty():
		message("이 기술에는 바꿀 수 있는 다른 개조가 없습니다. 아무것도 차감되지 않았습니다.")
		show("forge")
	else:
		open_choice(off)

func variant_change() -> void:
	var off := PFlow.variant_change(run)
	save_run()
	if off.is_empty():
		message("바꿀 수 있는 다른 변형이 없습니다. 아무것도 차감되지 않았습니다.")
		show("forge")
	else:
		open_choice(off)

func apply_swap(slot: String, index: int, new_id: String, mods: Array) -> void:
	PRun.apply_swap(run, slot, index, new_id, mods)
	save_run()
	show("forge")

# ---------- 3택 ----------
var last_pick_highlight := ""   # 방금 선택으로 바뀐 빌드 칸("w<i>" / "w<i>:m<j>"). 화면이 한 번 읽고 비운다

## 선택 뒤 회차 상태에서 그 후보가 들어간 칸을 찾는다(표시 전용). 못 찾으면 ""
func _slot_of_choice(c: Dictionary) -> String:
	var r := cur_run()
	if r.is_empty():
		return ""
	var ws: Array = r.growth.weapons
	var wid := String(c.get("id", ""))
	for i in ws.size():
		if String(ws[i].id) != wid:
			continue
		if String(c.get("kind", "")) == "weapon_mod":
			var mods: Array = ws[i].mods
			var idx: int = mods.find(String(c.get("mod", "")))
			return "w%d:m%d" % [i, idx] if idx >= 0 else "w%d" % i
		return "w%d" % i
	return ""

## 화면이 강조 표시를 한 번만 쓰도록 읽고 비운다
func take_pick_highlight() -> String:
	var h := last_pick_highlight
	last_pick_highlight = ""
	return h

func open_choice(off: Variant) -> void:
	if off == null or typeof(off) != TYPE_DICTIONARY:
		return
	choice.open(run, off)
	if screen == "combat":
		view.set_paused(true)

func close_choice() -> void:
	choice.close()
	if screen == "combat" and not pause_panel.visible and not glossary_paused and not orient_paused:
		view.set_paused(false)

## 전투 중 레벨업: 미처리 선택이 있으면 하나씩 제시
## **특수 정예 결투 전 성장 선택 문.**
## 규칙 계층은 화면이 자리를 잡지 않으면 그냥 지나간다(봇·검사에서 멈춰 서지 않게 하는 안전 기본값).
## 사람이 하는 화면에서는 여기서 자리를 잡고, 밀린 레벨업을 다 처리한 뒤에 문을 연다.
## 잡지 않으면 강적이 성장 선택 없이 바로 나온다.
func _duel_gate_tick() -> void:
	if screen != "combat" or view == null or view.st == null:
		return
	var st: CombatState = view.st
	if String(st.duel_stage) != "growth":
		return
	if not st.duel_gate_held:
		st.hold_duel_gate()
	if st.duel_gate:
		return
	if choice != null and choice.visible:
		return # 이미 3택이 떠 있다
	if int(run.growth.pendingLevelUps) > 0 and not run.is_empty():
		offer_pending_level_ups()
		return
	st.open_duel_gate()

func offer_pending_level_ups() -> bool:
	if run.is_empty() or int(run.growth.pendingLevelUps) <= 0:
		return false
	var rid := String(sortie.get("regionId", "")) if not sortie.is_empty() else ""
	open_choice(PGrowth.generate_offer(run, { "pool": "level", "region_id": rid }))
	save_run()
	return true

func _after_choice() -> void:
	save_run()
	if screen == "combat" and view.st != null:
		view.st.rebuild(PRun.build(run))   # 준비물·회차 효과까지 포함한 빌드로 재계산한다 # HUD가 옛 캐시를 읽지 않게 실제 빌드를 다시 만든다
		if build_hud != null:
			build_hud.update_from(view.st)
			build_hud.highlight_slot(take_pick_highlight()) # 방금 들어간 칸만 잠깐 강조
		close_choice()
		if int(run.growth.pendingLevelUps) > 0:
			offer_pending_level_ups()
		return
	close_choice()
	var off = PFlow.next_offer(run, { "region_id": String(sortie.get("regionId", "")) }) if screen != "reward" else null
	if off != null:
		open_choice(off)
		save_run()
	elif screen == "after" and not sortie.is_empty() and sortie.get("event", null) != null and not bool(sortie.event.resolved):
		show("event")
	else:
		show(screen)

func _on_pick(key: String) -> void:
	var off := choice.offer
	if off.is_empty():
		return
	for c in off.choices:
		if String(c.key) == key:
			PFlow.resolve_offer(run, off, c)
			last_pick_highlight = _slot_of_choice(c) # 선택 직후 바뀐 칸만 잠깐 강조(빌드 표시가 옛 캐시를 읽지 않게 항상 새 회차 상태에서 계산)
			_after_choice()
			return

func _on_skip() -> void:
	var off := choice.offer
	if off.is_empty():
		return
	PFlow.resolve_offer(run, off, null)
	_after_choice()

func _on_reroll() -> void:
	var off := PFlow.reroll_offer(run)
	if not off.is_empty():
		open_choice(off)
		save_run()

# ---------- 전투 뒤 ----------
func after_reward() -> void:
	var step := PFlow.after_combat_step(run, sortie)
	if step == "offer":
		open_choice(PFlow.next_offer(run, { "region_id": String(sortie.regionId) }))
		save_run()
		return
	show(step)

func event_choice(opt_id: String) -> void:
	var r := PEvents.resolve(run, sortie, opt_id)
	save_run()
	var next := String(r.get("next", "after"))
	if next == "fight" or next == "deep":
		start_encounter()
		return
	if next == "offer":
		var off = PFlow.next_offer(run, { "region_id": String(sortie.regionId) })
		if off != null:
			show("after")
			open_choice(off)
			save_run()
			return
	show("after")

func deep_explore() -> void:
	if not PRun.deep_explore(run, sortie):
		return
	save_run()
	start_encounter()

func return_home() -> void:
	PFlow.return_home(run, sortie)
	_award_profile("return", { "sortie": sortie }) # 생환·정산 도전(원정대의 갑옷·재생의 여행복 제작법)
	sortie = {}
	go_base()

func after_defeat() -> void:
	sortie = {}
	if PRun.is_run_over(cur_run()):
		save_run()
		show("run_result")
		return
	go_base()

# ---------- 전투 시작·종료 ----------
func _view_start(st: CombatState, bot: PBot) -> void:
	if view.has_method("start_state"):
		view.start_state(st, bot)
	else: # combat_view.start_state가 아직 없을 때의 최소 대체(같은 필드만 설정)
		view.st = st
		view.bot = bot
		view.driver.reset()
		view.paused = false
		view.running = true
		view.end_timer = 0.0
		view.frame_count = 0
		view.queue_redraw()

## 검증 메뉴의 봇: legacy면 기존 PBot 정책(전달된 기본값) 그대로, 실력 프로필이면 PSkillBot(봇 seed = 화면의 시드)
func make_bot(default_policy: String = "balanced") -> PBot:
	if PCatalog.bot_profiles().has(bot_profile):
		return PSkillBot.new(bot_profile, seed_v)
	return PBot.new(default_policy)

func set_bot_profile(id: String) -> void:
	bot_profile = id if PCatalog.bot_profiles().has(id) else "legacy"

## '이번 전투 입력 기록': 사람 입력(봇 아님)일 때만 PStepDriver에 기록기를 붙인다. 저장은 _on_finished에서 user://recordings/<시각>_<시나리오>.json (로컬만)
func _attach_recording(scenario: String) -> void:
	view.driver.recorder = null
	if not record_inputs or view.bot != null or view.st == null:
		return
	if _data_hash_cache == "":
		_data_hash_cache = PReplay.data_hash()
	var rp := PReplay.new()
	rp.begin(view.st, { "scenario": scenario, "build_fixture": fight_kind, "game_seed": view.st.seed_value, "engine": Engine.get_version_info().string, "os": OS.get_name() + "/" + Engine.get_architecture_name(), "data_hash": _data_hash_cache, "commit": "unknown", "profile": "human", "bot_version": "human" })
	rp.attach_recorder(view.driver)

func _finish_recording(st: CombatState) -> String:
	var rp: PReplay = view.driver.recorder
	if rp == null:
		return ""
	view.driver.recorder = null
	rp.finish(st)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", "")
	var path := "user://recordings/%s_%s.json" % [stamp, String(rp.header.get("scenario", "fight")).validate_filename()]
	if rp.save(path):
		print("INPUT_RECORDING ", ProjectSettings.globalize_path(path))
		return path
	return ""

func start_encounter() -> void:
	var st: CombatState
	if String(sortie.regionId) == "boss":
		st = PFlow.make_boss_encounter(run, sortie)
	else:
		st = PFlow.make_encounter(run, sortie)
	fight_kind = "run"
	save_run() # 전투 시작 체크포인트(F1): pendingSortie=null 상태로 저장 → 전투 중 종료 시 시간은 지불·성장 유지·미정산 전리품 상실·거점 복구(GAME_SPEC §전투 도중 종료)
	_view_start(st, make_bot("balanced") if use_bot else null)
	_attach_recording("run:%s:day%d" % [String(sortie.regionId), int(run.get("day", 1))])
	choice.close()
	tips.close_all()
	show("combat")
	_refresh_combat_texts()

## 기준 전투(첫 전투, 0.3.1 D33): 검증 메뉴·캡처·영상·회피 시연이 쓰는 경로. 봇은 기존 PBot("active") 그대로, 실력 프로필을 고르면 같은 상태에 PSkillBot
func start_fight(bot: bool) -> void:
	use_bot = bot
	fight_kind = "first"
	if bot and PCatalog.bot_profiles().has(bot_profile):
		view.start_state(Game.new_combat(seed_v), make_bot("active"))
	else:
		view.start(seed_v, bot)
	_attach_recording("first_fight:%s:%s%.1f:dash%d" % [Game.formation_id, Game.dodge_mode, Game.dodge_cooldown, Game.dash_max])
	choice.close()
	show("combat")
	_refresh_combat_texts()
	_refresh_debug_note()

func retry_fight() -> void:
	match fight_kind:
		"first": start_fight(use_bot)
		"lab": _lab_restart()
		_: go_title()

var _lab_last: Dictionary = {}

func _lab_restart() -> void:
	if _lab_last.is_empty():
		go_title()
	elif String(_lab_last.kind) == "start":
		quick_start_fight(String(_lab_last.arg), use_bot)
	else:
		quick_boss_fight(String(_lab_last.arg), use_bot)

## 검증 메뉴: 시작 기술 첫 전투 비교 — 새 회차(시드 1)의 첫 숲 카드 조우
func quick_start_fight(weapon_id: String, bot: bool) -> void:
	use_bot = bot
	_lab_last = { "kind": "start", "arg": weapon_id }
	lab_run = PRun.new_run(1, weapon_id)
	var card: Dictionary = {}
	for c in PSortie.cards_for(lab_run):
		if String(c.regionId) == "forest" and PSortie.can_start(lab_run, c):
			card = c
			break
	if card.is_empty():
		card = PSortie.cards_for(lab_run)[0]
	var s := PSortie.start(lab_run, String(card.id))
	var st := PFlow.make_encounter(lab_run, s)
	st.time_limit = float(PCatalog.lab().TIME_LIMITS[1])
	fight_kind = "lab"
	lab_label = "시작 기술 비교: %s · %s 1일차 첫 카드 · 시드 %d · 제한 %d초" % [String(PCatalog.weapon(weapon_id).name), String(PRun.region(String(card.regionId)).name), int(lab_run.seed), int(st.time_limit)]
	_view_start(st, make_bot("balanced") if bot else null)
	_attach_recording("lab_start:" + weapon_id)
	show("combat")
	_refresh_combat_texts()

## 검증 메뉴: 관문 빌드 보스전 — PCatalog.lab().BUILDS의 stage1/2/3 빌드로 보스 입장
func quick_boss_fight(build_key: String, bot: bool) -> void:
	use_bot = bot
	_lab_last = { "kind": "boss", "arg": build_key }
	lab_run = _lab_build_run(build_key)
	var s := PRun.start_boss(lab_run)
	var st := PFlow.make_boss_encounter(lab_run, s)
	fight_kind = "lab"
	lab_label = "관문 빌드 보스전: %s → %s · 보스 체력 %d" % [String(PCatalog.lab().BUILDS[build_key].name), String(PCatalog.boss_def(String(s.bossId)).name), int(PRun.boss_hp(lab_run, String(s.bossId)))]
	_view_start(st, make_bot("balanced") if bot else null)
	_attach_recording("lab_boss:" + build_key)
	show("combat")
	_refresh_combat_texts()

static func _lab_build_run(key: String) -> Dictionary:
	var B: Dictionary = PCatalog.lab().BUILDS[key]
	var gr: Dictionary = B.growth
	var gw: Array = gr.weapons
	var r := PRun.new_run(1, String(gw[0].id))
	var g: Dictionary = r.growth
	var picks := 0
	g.weapons = []
	for i in gw.size():
		var w: Dictionary = gw[i]
		var mods := []
		for m in w.get("mods", []):
			mods.append(String(m))
		g.weapons.append({ "id": String(w.id), "level": int(w.get("level", 1)), "mods": mods })
		picks += (1 if i > 0 else 0) + int(w.get("level", 1)) - 1 + mods.size()
	for k in gr.get("commons", {}):
		g.commons[String(k)] = int(gr.commons[k])
		picks += int(gr.commons[k])
	for k in gr.get("passives", {}):
		g.passives[String(k)] = int(gr.passives[k])
		picks += int(gr.passives[k])
	if gr.has("q"):
		g.skills.q.level = int(gr.q.get("level", 1))
		g.skills.q.variant = gr.q.get("variant", null)
		picks += int(gr.q.get("level", 1)) - 1 + (1 if gr.q.get("variant", null) != null else 0)
	if gr.has("e"):
		g.skills.e = { "id": String(gr.e.id), "level": int(gr.e.get("level", 1)), "variant": gr.e.get("variant", null) }
		picks += int(gr.e.get("level", 1)) + (1 if gr.e.get("variant", null) != null else 0)
	g.bossRewards = []
	for id in gr.get("bossRewards", []):
		g.bossRewards.append(String(id))
	g.level = 1 + picks
	for slot in B.get("equipment", {}):
		var id := String(B.equipment[slot])
		(r.bag as Array).append(id)
		PRun.equip_item(r, id)
	r.forge = int(B.get("forge", 0))
	r.gold = int(B.get("gold", r.gold))
	var idx: int = int({ "stage1": 0, "stage2": 1, "stage3": 2 }.get(key, 0))
	var bosses: Array = PRun.mode_def(r).bosses
	idx = mini(idx, bosses.size() - 1)
	r.stage = idx
	var done := []
	for i in idx:
		done.append(String(bosses[i].id))
	r.bossesDone = done
	r.day = int(bosses[idx].day)
	r.phase = "boss_prep"
	r.hours = int(PCatalog.config().HOURS_PER_DAY)
	r.hp = float(PBuild.derive(r).hp_max)
	r.quick = true
	return r

## 검증 메뉴: 봇 회차 데모 — 새 회차를 봇이 첫 관문 결과까지 자동 진행(현재 저장을 덮어쓴다)
func bot_demo() -> void:
	PProfile.use_path(TEST_PROFILE_PATH) # 봇 데모는 시험 프로필 파일로(실제 프로필 보호). 이후 이 세션의 프로필은 시험 파일
	profile = PProfile.load()
	_auto = true
	_auto_snap = false
	_auto_quit = false
	_auto_state = "start"
	_auto_done = {}
	_auto_wait = 0

func give_up() -> void:
	set_pause(false)
	if fight_kind != "run":
		go_title()
		return
	if view.st != null and view.running: # 포기 = 패배 처리(PFlow.settle_defeat는 finished에서)
		var st: CombatState = view.st
		st.player.hp = 0.0
		st.player.dead = true
		st.status = "lost"
		view.end_timer = 10.0

func _on_finished(summary: Dictionary) -> void:
	last_summary = summary
	var st: CombatState = view.st
	_finish_recording(st) # 켜져 있었으면 사람 입력 기록을 로컬에 저장(HUD·통계 변화 없음)
	if fight_kind != "run":
		_show_lab_result(summary)
		return
	if view.bot != null and bool(run.get("profileEligible", false)):
		run.profileEligible = false # 봇이 진행한 전투가 있는 회차는 영구 기록 대상에서 제외(사용자 지시 §5)
	if st.mode == "boss":
		if st.status == "won":
			last_record = PFlow.settle_boss_victory(run, st)
			if not bool(run.get("quick", false)):
				PSave.save_record(last_record)
			last_profile_award = _award_profile("boss", { "st": st, "endless_segment": int(last_record.get("segment", 0)) if bool(last_record.get("endless", false)) else 0 })
			save_run()
			sortie = {}
			show("run_result" if String(run.phase) == "cleared" else ("base" if PEndless.active(run) else "boss_result"))
		else:
			PFlow.settle_boss_defeat(run, st)
			save_run()
			sortie = {}
			show("run_result" if PEndless.is_over(run) else "boss_result")
		return
	if st.status == "won":
		last_reward = PFlow.settle_victory(run, sortie, st)
		last_profile_award = _award_profile("victory", { "sortie": sortie, "st": st })
		save_run()
		show("reward")
		if int(run.growth.pendingLevelUps) > 0:
			offer_pending_level_ups()
	else:
		lost_loot = (sortie.loot as Dictionary).duplicate(true)
		PFlow.settle_defeat(run, sortie, st)
		save_run()
		show("defeat")

## 기준 전투·검증 빠른 전투의 결과 패널
func _show_lab_result(summary: Dictionary) -> void:
	show("result")
	var won: bool = summary.status == "won"
	$UI/Result/VBox/Title.text = ("전투 승리" if won else ("시간 초과" if summary.status == "timeout" else "패배"))
	var dmg_lines := []
	for k in summary.dmg:
		dmg_lines.append("%s %s" % [k, str(snapped(summary.dmg[k], 0.1))])
	var taken_lines := []
	for k in summary.taken:
		taken_lines.append("%s %s" % [k, str(snapped(summary.taken[k], 0.1))])
	if fight_kind == "first":
		var dists := []
		for d in summary.dodge_dists:
			dists.append(str(int(round(float(d)))))
		var mw: Dictionary = summary.enemies.get("wolf", {})
		var spn: int = maxi(1, int(mw.get("spawned", 0)))
		$UI/Result/VBox/Body.text = "편성 %s(전체 %d, 동시 돌진 %d) · 늑대 체력 %.0f · 시간 %s초 · 처치 %d/%d · 받은 피해 %d(%s)\n늑대 1마리당 물기 %.2f / 돌진 %.2f · 예고 전 사망 %d · 실행 전 사망 %d(%.0f%%) · 최대 생존 %d · 최대 돌진상태 %d · 경험치 %.2f(마리당 %.2f)\n공격 %d회(명중 %d) · 회피 %d(회피! %d) · 감속장 %d · 피해 출처: %s\n회피 설정: %s · 재사용 %.1f초 · 회피 거리: %s\n같은 조건(시드 %d, 같은 적 배치)으로 다시 시작할 수 있습니다." % [String(summary.formation), int(summary.spawn_total), int(summary.dash_max), float(summary.wolf_hp), str(summary.elapsed), summary.kills, int(summary.spawn_total), int(summary.damage_taken), (", ".join(taken_lines) if taken_lines.size() > 0 else "없음"), float(mw.get("bites_executed", 0)) / spn, float(mw.get("dashes_executed", 0)) / spn, int(mw.get("died_before_attack", 0)), int(mw.get("died_before_execute", 0)), 100.0 * float(mw.get("died_before_execute", 0)) / spn, int(summary.max_alive), int(summary.max_dash_states), float(summary.xp), float(summary.xp) / maxf(1.0, float(summary.kills)), summary.attacks, summary.hits, summary.dodges, summary.perfect_dodges, summary.special_uses, ", ".join(dmg_lines), Game.dodge_mode_name(summary.dodge_mode), float(summary.dodge_cooldown), (", ".join(dists) if dists.size() > 0 else "없음"), summary.seed]
	else:
		$UI/Result/VBox/Body.text = "%s\n시간 %s초 · 처치 %d/%d · 받은 피해 %d(%s) · 체력 %d/%d\n공격 %d회(명중 %d) · 회피 %d · 감속장 %d · E %d · 보스 피해 %s · 레벨업 %d\n피해 출처: %s\n같은 조건(시드 %d)으로 다시 시작할 수 있습니다." % [lab_label, str(summary.elapsed), int(summary.kills), int(summary.spawn_total), int(summary.damage_taken), (", ".join(taken_lines) if taken_lines.size() > 0 else "없음"), int(ceil(float(summary.hp))), int(float(summary.hp_max)), summary.attacks, summary.hits, summary.dodges, summary.special_uses, summary.e_uses, str(summary.boss_damage), int(summary.level_ups), (", ".join(dmg_lines) if dmg_lines.size() > 0 else "없음"), summary.seed]

# ---------- 일시정지·조작법·설정 ----------
func set_pause(v: bool) -> void:
	if v:
		$UI/Pause/VBox/TitleBtn.text = "포기하고 거점으로 (패배 처리)" if fight_kind == "run" else "제목으로 (전투 포기)"
	view.set_paused(v or choice.is_open() or glossary_paused or orient_paused) # 세로 때문에 멈춘 것은 '계속'으로만 풀린다
	pause_panel.visible = v
	if not v:
		controls_panel.visible = false
		settings_panel.visible = false

func _combat_cfg() -> Dictionary:
	return view.st.cfg if (screen == "combat" and view.st != null) else Game.current_config()

func controls_text() -> String:
	var c := _combat_cfg()
	var D: Dictionary = c.player.dodge
	var S: Dictionary = c.player.slowfield
	var interval: float = float(c.weapon.interval) if c.has("weapon") else (float(view.st.build.weapons[0].interval) if (view.st != null and (view.st.build.weapons as Array).size() > 0) else 0.0)
	var dash_max: int = int(c.enemies.wolf.dash.max_concurrent)
	var dodge_line := ""
	if String(D.mode) == "hold":
		dodge_line = "Space: 회피 — 누르면 즉시 출발. 떼면 짧게 멈춤(최소 %d). 계속 누르면 최대 %d.\n   짧게 써도 재사용 대기(%.1f초, 출발 순간부터)는 같음. 무적은 회피 이동 중에만(최대 %.2f초).\n   방향은 출발 순간 고정: 이동 중이면 그 방향, 아니면 바라보는 방향. 바위·나무·경계에 막히면 그 자리에서 끝남." % [int(D.min_distance), int(D.distance), float(D.cooldown), float(D.duration)]
	else:
		dodge_line = "Space: 회피 — 누르면 즉시 출발, 떼도 %d까지 감(고정 거리·비교용). 재사용 %.1f초(출발 순간부터). 무적은 회피 이동 중에만(최대 %.2f초).\n   방향은 출발 순간 고정: 이동 중이면 그 방향, 아니면 바라보는 방향." % [int(D.distance), float(D.cooldown), float(D.duration)]
	var e_line := "E: 선택 수동 기술 (레벨업·상점에서 습득: 돌풍·칼날 폭풍·낙뢰·중력핵·수호 결계)"
	return "WASD / 방향키: 이동\n%s\nQ: 감속장 (반지름 %d, %.0f초, 안의 적 속도·준비 %.0f%%, 재사용 %.0f초)\n%s\n자동 공격: 사거리 안의 가장 가까운 적을 향해 자동기술 발동 (첫 자동기술 %.2f초마다)\nEsc: 일시정지 / 재개 · Enter: 메뉴 확인 · F3: 검증 패널(회피 방식·재사용 비교 설정, 기준 전투 다음 재시작에 적용)\n\n읽어야 할 것\n주황 짧은 부채꼴: 늑대의 물기 예고(머리 앞, 판정 범위와 같음). 진해지고 '!'가 뜨면 방향 고정 — 옆·뒤로 빠지세요. 흰색 = 물어뜨리는 순간. 물기 뒤 잠시 멈춤(연한 파랑, 보너스 없음).\n붉은 통로: 늑대가 돌진할 길(동시 최대 %d마리). 굵어지며 '!'가 뜨면 방향이 고정됨 — 옆으로 피하세요.\n통로의 폭 = 실제 판정 폭. 흰 큰 부채꼴 = 검격의 실제 판정 범위.\n노란 늑대 = 돌진 뒤 빈틈 (피해 1.5배). 파란 원 = 감속장 범위. 몸이 닿기만 해서는 피해가 없습니다.\n바위·나무의 테두리 = 충돌 경계. 돌진도 막힙니다. 직접 공격은 장애물 뒤를 때리지 못하지만 불길·폭발·감속장은 바닥 범위대로 적용됩니다.\n밝은 플레이어 + 잔상 = 회피 이동 중(무적, 적의 몸을 통과). 잔상이 사라지면 무적도 끝.\n보스: 붉은 통로(돌진), 부채꼴(휩쓸기), 원(덮쳐찍기), 발자국(늑대 등장). 큰 공격 뒤 \"빈틈!\"에 붙어서 때리세요. 밑줄 용어는 마우스를 올리면 설명, 클릭하면 고정(Esc로 닫기)." % [dodge_line, int(S.radius), float(S.duration), float(S.slow) * 100.0, float(S.cooldown), e_line, interval, dash_max]

func show_controls(v: bool) -> void:
	controls_panel.visible = v
	if v:
		$UI/Controls/VBox/Body.text = controls_text()
	if screen == "combat" and view.paused:
		pause_panel.visible = not v # 조작법 위에 일시정지 글자가 비치지 않게

func open_settings() -> void:
	settings_panel.open()
	if screen == "combat" and view.paused:
		pause_panel.visible = false

func _on_settings_closed() -> void:
	if screen == "combat" and view.paused and not choice.is_open():
		pause_panel.visible = true

func _on_tip_pins(n: int) -> void:
	if screen != "combat" or not view.running:
		return
	if n > 0 and not view.paused:
		glossary_paused = true
		view.set_paused(true)
	elif n == 0 and glossary_paused:
		glossary_paused = false
		if not pause_panel.visible and not choice.is_open() and not orient_paused:
			view.set_paused(false)

# ---------- 화면 방향·전체화면 ----------
## 웹에서 부르는 스크립트. 전체화면을 요청하고, 그 결과와 상관없이 가로 고정을 시도한다.
## 거절은 두 가지 길로 온다: 동기 예외(try가 삼킨다)와 Promise 거부(then의 두 번째 인자가 삼킨다).
## 둘 다 잡으므로 지원하지 않는 브라우저에서도 콘솔에 오류가 남지 않는다.
## 전체화면 + 가로 고정 요청.
## **실패를 삼키되 지우지는 않는다**(사용자 확정 2026-09-09 보완): 브라우저에 오류를 흘리지 않으면서
## 전체화면·방향 고정 **각각의 결과와 사유**를 window.__prophecyOrient 에 남긴다.
## '오류 없음'은 '가로 고정 성공'이 아니다 — 둘을 따로 적는다.
const FS_ENTER_JS := """
(function(){
  var S = window.__prophecyOrient = window.__prophecyOrient || {};
  S.fs = 'pending'; S.fsReason = ''; S.lock = 'pending'; S.lockReason = ''; S.at = Date.now();
  var lock = function(){
    try {
      var so = window.screen ? window.screen.orientation : null;
      if (!so || !so.lock) { S.lock = 'unsupported'; S.lockReason = 'screen.orientation.lock 없음'; return; }
      var q = so.lock('landscape');
      if (q && q.then) {
        q.then(function(){ S.lock = 'ok'; S.lockReason = (so.type || ''); },
               function(e){ S.lock = 'fail'; S.lockReason = (e && e.name ? e.name : 'rejected'); });
      } else { S.lock = 'ok'; S.lockReason = 'promise 아님'; }
    } catch (e) { S.lock = 'fail'; S.lockReason = (e && e.name ? e.name : 'throw'); }
  };
  try {
    var el = document.documentElement;
    var req = el.requestFullscreen || el.webkitRequestFullscreen || el.mozRequestFullScreen || el.msRequestFullscreen;
    if (!req) { S.fs = 'unsupported'; S.fsReason = 'requestFullscreen 없음'; lock(); return 1; }
    var p = req.call(el);
    if (p && p.then) {
      p.then(function(){ S.fs = 'ok'; lock(); },
             function(e){ S.fs = 'fail'; S.fsReason = (e && e.name ? e.name : 'rejected'); lock(); });
    } else {
      S.fs = document.fullscreenElement ? 'ok' : 'unknown';
      S.fsReason = 'promise 아님';
      lock();
    }
    return 1;
  } catch (e) { S.fs = 'fail'; S.fsReason = (e && e.name ? e.name : 'throw'); lock(); return 0; }
})()
"""

## 마지막 요청의 결과를 읽는다(개발용 기록). 값이 없으면 빈 문자열
const FS_RESULT_JS := """
(function(){
  try {
    var S = window.__prophecyOrient;
    if (!S) return '';
    return [S.fs || '', S.fsReason || '', S.lock || '', S.lockReason || ''].join('|');
  } catch (e) { return ''; }
})()
"""

## 지금 전체화면인가를 읽는다. 처음 한 번 fullscreenchange 감시자를 걸어 두고 그 값을 읽는다(폴링 간격 사이의 이탈도 잡힌다)
const FS_STATE_JS := """
(function(){
  try {
    if (!window.__prophecyFsHook) {
      window.__prophecyFsHook = 1;
      var f = function(){
        try { window.__prophecyFs = !!(document.fullscreenElement || document.webkitFullscreenElement); }
        catch (e) { window.__prophecyFs = false; }
      };
      document.addEventListener('fullscreenchange', f, false);
      document.addEventListener('webkitfullscreenchange', f, false);
      f();
    }
    return window.__prophecyFs ? 1 : 0;
  } catch (e) { return 0; }
})()
"""

func _make_orient_gate() -> void:
	_orient_layer = CanvasLayer.new()
	_orient_layer.name = "OrientLayer"
	_orient_layer.layer = 64 # HUD(UI)·툴팁(Tips)보다 위. 세로 안내는 무엇보다 먼저 보여야 한다
	add_child(_orient_layer)
	orient = POrientGate.new()
	orient.name = "OrientGate"
	_orient_layer.add_child(orient)
	orient.resume_pressed.connect(orient_resume)
	orient.fullscreen_pressed.connect(request_fullscreen_landscape)

## 창·화면 크기가 바뀌었다: 배치를 다시 맞추고, 세로/가로를 다시 판정하고, 바뀐 크기를 알린다.
## 주소창이 뜨고 지는 것도 폰에서는 이 경로로 온다(크기 변화).
## 화면 크기가 바뀌면 글자·버튼 배율을 다시 정한다(주소창 등장·전체화면·회전 전부 여기로 온다)
func _sync_ui_scale() -> void:
	var before := PLayout.cur_ui_scale()
	PLayout.set_ui_scale(PLayout.ui_scale(get_viewport()))
	if not is_equal_approx(before, PLayout.cur_ui_scale()):
		var scr: Node = screens.get(screen, null)
		if scr != null and scr.has_method("refresh"):
			scr.refresh()   # 이미 그려진 화면도 새 크기로 다시 그린다

func _on_viewport_resized() -> void:
	_sync_ui_scale()
	_layout_hud()
	refresh_orientation()

## 지금 세로인가(화면 크기 비율만 본다)
func is_portrait() -> bool:
	return _portrait

func fullscreen_active() -> bool:
	return _fs_active

func fullscreen_wanted() -> bool:
	return _fs_wanted

## 화면 크기 창구: 조작 크기·자리를 정하는 쪽이 읽는 값. screen_metrics_changed와 같은 내용이다
func screen_metrics() -> Dictionary:
	var vp := get_viewport()
	var vis: Rect2 = vp.get_visible_rect() if vp != null else Rect2(0.0, 0.0, PLayout.BASE_W, PLayout.BASE_H)
	return {
		"visible": vis,                       # 보이는 canvas 영역
		"safe": PLayout.safe_rect(vp),        # 안전 영역(노치·둥근 모서리 제외)
		"portrait": _portrait,                # 세로인가
		"bucket": PLayout.aspect_bucket(vis.size),
		"fullscreen": _fs_active,             # 지금 전체화면인가
		"touch": PLayout.is_touch(),
	}

## 세로/가로를 다시 판정한다. 세로로 바뀌는 순간 전투를 멈추고 입력을 놓는다(가로로 돌아와도 저절로 재개하지 않는다)
func refresh_orientation() -> void:
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2.ZERO
	_portrait = POrientGate.is_portrait(size)
	if _portrait:
		_pause_for_portrait()
	_sync_orient_gate()
	screen_metrics_changed.emit(screen_metrics())

## 세로인데 전투가 돌고 있으면 멈춘다. 이미 있는 일시정지 경로를 그대로 쓴다(전투 시간·재사용 시간이 함께 멈춘다)
func _pause_for_portrait() -> void:
	if screen != "combat" or view == null or not view.running or view.st == null:
		return
	orient_paused = true             # 가로로 돌아와도 '계속'을 누를 때까지 유지된다
	if not view.paused:
		view.set_paused(true)        # 이미 있는 일시정지 경로(전투 시간·재사용 시간이 멈춘다)
	view.release_inputs("세로 전환")    # 누르고 있던 이동·회피를 놓는다
	if touch != null and touch.has_method("release_all"):
		touch.call("release_all")        # 잡고 있던 가상 스틱·버튼도 즉시 해제(조작 담당의 공개 경로)

## 매 프레임 확인: 세로 상태에서 전투가 새로 시작됐다면 그때도 멈춘다
func _orient_guard() -> void:
	if _portrait and screen == "combat" and view.running and (not view.paused or not orient_paused):
		_pause_for_portrait()
		_sync_orient_gate()

## '계속': 사용자가 눌렀을 때만 재개한다. 세로에서는 재개하지 않는다
func orient_resume() -> void:
	if not orient_paused or _portrait:
		return
	orient_paused = false
	_sync_orient_gate()
	if screen == "combat" and not pause_panel.visible and not choice.is_open() and not glossary_paused and not _detail_paused:
		view.set_paused(false)

func _sync_orient_gate() -> void:
	if orient == null:
		return
	var offer: bool = _fs_wanted and not _fs_active
	orient.apply(_portrait, orient_paused, offer)
	if _pause_fs_btn != null:
		_pause_fs_btn.visible = offer

## 전체화면 + 가로 고정 요청. 반드시 버튼 콜백에서 바로 불러야 한다(브라우저는 사용자 제스처 안에서만 허용한다).
## 지원하지 않거나 거부해도 아무것도 막지 않는다 — 조용히 넘어가고 게임은 그대로 돈다.
func request_fullscreen_landscape() -> void:
	var res := { "web": false, "fullscreen": "건너뜀", "orientation": "건너뜀" }
	_fs_wanted = true
	if OS.has_feature("web"):
		res.web = true
		var r: Variant = JavaScriptBridge.eval(FS_ENTER_JS, true)
		var called: bool = _js_truthy(r)
		res.fullscreen = "요청함" if called else "브라우저가 거절"
		res.orientation = "요청함(가로)" if called else "건너뜀"
	elif DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN) # PC 창: 방향 개념이 없다
		res.fullscreen = "창 모드 전환"
	last_fullscreen_result = res
	_note_fs_log("요청", res)
	_fs_poll_t = 0.0 # 다음 프레임에 실제 상태를 다시 읽는다
	_sync_orient_gate()

## 개발용 기록. 사용자 화면에는 안 나온다 — 콘솔과 이 목록에만 남는다.
## "오류가 없었다"와 "가로 고정이 됐다"는 다른 말이라 **둘을 따로** 남긴다
var fullscreen_log: Array = []
func _note_fs_log(tag: String, res: Dictionary) -> void:
	var line := "[전체화면] %s · web=%s · 전체화면=%s · 방향고정=%s" % [tag, str(res.get("web", false)), String(res.get("fullscreen", "?")), String(res.get("orientation", "?"))]
	fullscreen_log.append(line)
	if fullscreen_log.size() > 20:
		fullscreen_log.remove_at(0)
	print(line)

const _FS_WORD := { "ok": "성공", "fail": "거부됨", "unsupported": "미지원", "pending": "대기", "unknown": "알 수 없음", "": "?" }

## 브라우저가 실제로 어떻게 됐는지 뒤늦게 읽어 기록을 갱신한다(요청 시점에는 아직 모른다).
## 실패해도 게임은 그대로 돈다 — 여기서 하는 일은 기록뿐이다
func _poll_fs_result() -> void:
	if not OS.has_feature("web"):
		return
	var raw := String(JavaScriptBridge.eval(FS_RESULT_JS, true))
	if raw == "":
		return
	var parts := raw.split("|")
	if parts.size() < 4:
		return
	var fs_w := String(_FS_WORD.get(parts[0], parts[0]))
	var lk_w := String(_FS_WORD.get(parts[2], parts[2]))
	var fs_txt: String = fs_w if String(parts[1]) == "" else "%s(%s)" % [fs_w, String(parts[1])]
	var lk_txt: String = lk_w if String(parts[3]) == "" else "%s(%s)" % [lk_w, String(parts[3])]
	if String(last_fullscreen_result.get("fullscreen", "")) == fs_txt and String(last_fullscreen_result.get("orientation", "")) == lk_txt:
		return
	last_fullscreen_result = { "web": true, "fullscreen": fs_txt, "orientation": lk_txt }
	_note_fs_log("결과", last_fullscreen_result)

## 전체화면 여부가 바뀌었다(웹의 fullscreenchange · PC의 창 모드 · 검사의 흉내). 안내막·버튼만 다시 맞춘다
func note_fullscreen_state(active: bool) -> void:
	if _fs_active == active:
		return
	_fs_active = active
	_sync_orient_gate()
	screen_metrics_changed.emit(screen_metrics())

## 전체화면 상태를 읽을 수 있는 곳인가(헤드리스 검사는 읽을 수 없다 → 흉내 낸 값을 그대로 둔다)
func _fs_detectable() -> bool:
	return OS.has_feature("web") or DisplayServer.get_name() != "headless"

func _poll_fullscreen(dt: float) -> void:
	if not _fs_detectable():
		return
	_poll_fs_result() # 개발용 기록 갱신(요청 결과는 뒤늦게 온다)
	_fs_poll_t -= dt
	if _fs_poll_t > 0.0:
		return
	_fs_poll_t = FS_POLL_SEC
	var now := false
	if OS.has_feature("web"):
		now = _js_truthy(JavaScriptBridge.eval(FS_STATE_JS, true))
	else:
		var m := DisplayServer.window_get_mode()
		now = m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	note_fullscreen_state(now)

## JavaScriptBridge.eval의 반환값(웹이 아니면 null)을 안전하게 참/거짓으로 읽는다
static func _js_truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL: return bool(v)
		TYPE_INT: return int(v) != 0
		TYPE_FLOAT: return float(v) != 0.0
		TYPE_STRING: return String(v) != "" and String(v) != "0"
	return false

func _unhandled_input(event: InputEvent) -> void:
	# Tab: 빌드 상세 열기·닫기(전투 중이면 공통 일시정지 경로). 3택·설정이 열려 있으면 받지 않는다
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_TAB:
		if not choice.is_open() and not settings_panel.visible and not controls_panel.visible:
			if build_detail.is_open():
				build_detail.close()
			else:
				open_build_detail()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause"):
		if build_detail != null and build_detail.is_open():
			build_detail.close()
			get_viewport().set_input_as_handled()
			return
		if choice.is_open():
			get_viewport().set_input_as_handled()
			return
		if settings_panel.visible:
			settings_panel.close()
			_on_settings_closed()
			get_viewport().set_input_as_handled()
			return
		if screen == "combat" and view.running:
			if controls_panel.visible:
				controls_panel.visible = false
				if view.paused:
					pause_panel.visible = true
			else:
				set_pause(not pause_panel.visible)
			get_viewport().set_input_as_handled()
		elif controls_panel.visible:
			controls_panel.visible = false
		elif screens.has(screen):
			var s: PScreen = screens[screen]
			if not s.on_escape():
				if screen in ["shop", "equip", "forge", "stats", "log"]:
					go_base()
	if event.is_action_pressed("debug_panel"):
		debug_panel.visible = not debug_panel.visible
	if event.is_action_pressed("confirm"):
		if choice.is_open() or controls_panel.visible or settings_panel.visible:
			return
		if screen == "result":
			retry_fight()
		elif screens.has(screen):
			var s: PScreen = screens[screen]
			var b := s.default_button
			if b != null and is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled:
				b.pressed.emit()

# ---------- 빌드 상세(전투 중에는 공통 일시정지·입력 초기화 경로) ----------
func open_build_detail() -> void:
	if build_detail == null or build_detail.is_open():
		return
	var b: Dictionary = {}
	var report: Dictionary = {}
	var where := ""
	if screen == "combat" and view.st != null:
		b = view.st.build
		report = view.st.mod_report()
		where = "전투 중 · 이번 전투 기록"
	elif not cur_run().is_empty():
		b = PBuild.derive(cur_run())
		where = "거점"
	else:
		return
	build_detail.open_with(b, report, where)
	if screen == "combat" and view.running and not view.paused:
		_detail_paused = true
		view.set_paused(true) # 공통 일시정지 경로(대기 입력·가상 스틱도 초기화된다)

func _on_detail_closed() -> void:
	if _detail_paused:
		_detail_paused = false
		if screen == "combat" and not pause_panel.visible and not choice.is_open() and not glossary_paused and not orient_paused:
			view.set_paused(false)
	if build_hud != null and view.st != null:
		build_hud.sync_ready_silent(view.st) # 화면을 닫고 돌아올 때 이미 준비된 기술에 알림이 다시 터지지 않게

# ---------- HUD ----------
## 상단 띠의 옛 회피/Q/E 막대: 하단 아이콘 묶음이 같은 정보를 더 잘 보여 주므로 숨긴다(값 계산은 그대로 두어 시험 계약을 깨지 않는다)
func _hide_legacy_ability_bars() -> void:
	for n in ["Dodge", "DodgeText", "Q", "QText", "E", "EText"]:
		var c: Control = hud.get_node_or_null(n)
		if c != null:
			c.visible = false
	# 빈 자리에 날짜·시간대·세계 변화 한 줄(상단은 체력·보호막 / 날짜·시간대·세계 변화 / 남은 적·보스 체력만 둔다)
	var day := Label.new()
	day.name = "Day"
	day.add_theme_font_size_override("font_size", 13)
	day.add_theme_color_override("font_color", Color(0.80, 0.85, 0.92))
	day.clip_text = true
	day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	day.offset_left = 224.0
	day.offset_top = 6.0
	day.offset_right = 690.0
	day.offset_bottom = 34.0
	day.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(day)

## 상단 날짜 줄: 날짜 · 시간대 · 세계 변화(개발용 설정·긴 효과 설명은 넣지 않는다)
func _day_line(st: CombatState) -> String:
	var r := cur_run()
	if r.is_empty() or st.cfg.has("weapon"):
		return ""
	var slots := PRun.time_slots()
	var cur := PRun.slot_index(r)
	var slot_name := String(slots[cur]) if cur >= 0 and cur < slots.size() else ""
	var out := "%s%d일차" % [(PRun.act_label(r).split(" · ")[0] + " · ") if PRun.act_label(r) != "" else "", int(r.get("day", 1))]
	if slot_name != "":
		out += " · " + slot_name
	if PRun.world_stage(r) > 0:
		out += " · " + String(PRun.world_stage_def(r).name)
	return out

## 회피/Q/E 준비 완료(false→true) 1회 신호: 능력별로 다른 짧은 소리 + 테두리 점등(PCombatHud가 그린다).
## 계속 깜박이거나 반복 선언하지 않는다. 일시정지·저장 복구·화면 재구성은 sync_ready_silent로 조용히 맞춘다.
func _on_ability_ready(ability: String) -> void:
	if screen != "combat" or view.st == null or not view.running:
		return
	if view.audio != null:
		view.audio.play(String(PCombatHud.READY_SOUND.get(ability, "")))

func _settings_line(st: CombatState) -> String:
	if st.cfg.has("weapon"):
		return Game.settings_short(st.cfg) + ("  · 봇 조작" if view.bot != null else "")
	var r := cur_run()
	var where := ""
	if st.mode == "boss":
		where = "보스전 · " + String(PCatalog.boss_def(st.boss_id).name)
	else:
		where = "%s · %s" % [String(PRun.region(st.region_id).get("name", st.region_id)), PSortie.objective_name(st.objective)]
		if st.hp_mult.normal != 1.0:
			where += " · 체력 ×%s" % str(st.hp_mult.normal)
	var lab := (" · " + lab_label) if fight_kind == "lab" else ""
	return "%s · %s · %d일차 · %s%s · 시드 %d%s" % [Game.VERSION, PUi.balance_name(r), int(r.get("day", 1)), where, lab, st.seed_value, "  · 봇 조작" if view.bot != null else ""]

func _refresh_combat_texts() -> void:
	if view.st == null:
		return
	$UI/HUD/Settings.text = _settings_line(view.st)
	$UI/HUD/Demo.text = ""
	$UI/HUD/Boss.visible = not view.st.boss.is_empty()
	_refresh_debug_note()

func _update_hud() -> void:
	var st: CombatState = view.st
	var p := st.player
	var P: Dictionary = st.cfg.player
	var hp_bar: ProgressBar = $UI/HUD/HP
	hp_bar.value = p.hp / p.hp_max * 100.0
	var shield: float = float(p.shield) # ward_shield는 shield 총량의 구성분이라 다시 더하지 않는다(F2)
	$UI/HUD/HPText.text = "체력 %d / %d" % [int(ceil(p.hp)), int(p.hp_max)] + ((" · 보호막 %d" % int(ceil(shield))) if shield > 0.0 else "")
	var sh_bar: ProgressBar = $UI/HUD/Shield
	var sh_max: float = maxf(float(p.shield_max), shield)
	sh_bar.visible = shield > 0.0
	sh_bar.value = (shield / sh_max * 100.0) if sh_max > 0.0 else 0.0
	var dcd: float = float(P.dodge.cooldown)
	$UI/HUD/Dodge.value = (1.0 - clampf(p.dodge_cd / dcd, 0.0, 1.0)) * 100.0
	var guide := "길이=거리" if String(P.dodge.mode) == "hold" else "고정 %d" % int(P.dodge.distance)
	var dodge_key := "회피 · " if (touch != null and touch.enabled) else "Space 회피 · " # 터치 오버레이가 켜지면 버튼 이름 없이
	$UI/HUD/DodgeText.text = dodge_key + ("회피 중 %d" % int(p.dodge_dist) if p.dodge_active else (guide if p.dodge_cd <= 0.0 else "%.1f초" % p.dodge_cd))
	var qcd: float = float(st.build.special_cd) if st.build.has("special_cd") else float(P.slowfield.cooldown)
	$UI/HUD/Q.value = (1.0 - clampf(p.special_cd / maxf(0.01, qcd), 0.0, 1.0)) * 100.0
	$UI/HUD/QText.text = "Q 감속장 " + ("준비" if p.special_cd <= 0.0 else "%.1f초" % p.special_cd) + (" · 전개 %.1f초" % st.field.ttl if not st.field.is_empty() else "")
	var e_bar: ProgressBar = $UI/HUD/E
	if st.build.skills.get("e", null) != null:
		var ecd := PSkills.cd_of(st, "e")
		var e_cd_now: float = float(p.get("e_cd", 0.0))
		e_bar.value = (1.0 - clampf(e_cd_now / maxf(0.01, ecd), 0.0, 1.0)) * 100.0
		$UI/HUD/EText.text = "E %s " % String(PCatalog.skills()[String(st.build.skills.e.id)].name) + ("준비" if e_cd_now <= 0.0 else "%.1f초" % e_cd_now)
	else:
		e_bar.value = 0.0
		$UI/HUD/EText.text = "E 없음"
	if build_hud != null:
		build_hud.update_from(st) # 하단 빌드 HUD(자동기술·개조·공용·장비·회피/Q/E)
	var day_l: Label = hud.get_node_or_null("Day")
	if day_l != null:
		day_l.text = _day_line(st)
	var obj_l: Label = $UI/HUD/Objective
	if st.mode == "boss":
		obj_l.text = "보스전 · 소환 %d · %.1f초" % [PBoss.summoned_alive(st), st.t]
	elif not st.obj.is_empty():
		var h := PObjectives.hud(st)
		if h.is_empty():
			obj_l.text = "%.1f초" % st.t
		else:
			# 목표 지점 안내: 원 밖 정지 / 진행 중 / 피격 중단을 구분하고, 화면 밖이면 방향·거리를 말한다
			var mk: Dictionary = h.get("marker", {})
			var obj_guide := ""
			if not mk.is_empty():
				if String(mk.get("state", "")) != "":
					obj_guide += " · " + String(mk.state)
				if float(mk.get("dist", 0.0)) > 260.0:
					obj_guide += " · %s %d 이동" % [String(mk.get("dir", "")), int(mk.dist)]
			obj_l.text = "%s · %s%s%s · %.1f초" % [String(h.title), String(h.line), (" · " + String(h.risk)) if String(h.risk) != "" else "", obj_guide, st.t]
	else:
		var r := st.remaining()
		obj_l.text = "전멸 · 남은 %d · 지금 %d/%d · 대기 %d · 돌진 %d/%d · %.1f초" % [r.total, r.alive, r.cap, r.pending, st.dash_states_count(), int(st.cfg.enemies.wolf.dash.max_concurrent), st.t]
	var boss_panel: Control = $UI/HUD/Boss
	boss_panel.visible = not st.boss.is_empty()
	if not st.boss.is_empty():
		var bz: Dictionary = st.boss
		var def := PCatalog.boss_def(st.boss_id)
		$UI/HUD/Boss/BossName.text = "%s  %d / %d" % [String(def.name), int(maxf(0.0, ceil(float(bz.hp)))), int(float(bz.hp_max))]
		$UI/HUD/Boss/BossAction.text = String(PCatalog.boss_action_text().get(String(bz.state), String(bz.state)))
		var bar: ProgressBar = $UI/HUD/Boss/BossBar
		bar.value = clampf(float(bz.hp) / maxf(1.0, float(bz.hp_max)) * 100.0, 0.0, 100.0)
		var ph: Array = def.get("phases", [0.7, 0.35])
		var ticks := [$UI/HUD/Boss/Tick1, $UI/HUD/Boss/Tick2]
		for i in ticks.size():
			var tk: ColorRect = ticks[i]
			tk.visible = i < ph.size()
			if i < ph.size():
				var x := bar.offset_left + (bar.offset_right - bar.offset_left) * float(ph[i])
				tk.offset_left = x - 1.0
				tk.offset_right = x + 1.0

## HUD·전투 화면 배치(PLayout): 창 크기·안전 영역이 바뀌면 HUD 왼쪽 묶음은 안전 영역 시작에, 목적·설정 줄은 안전 영역 끝에, 경기장은 HUD 아래 가운데에 둔다.
## 설계 크기 960×640(안전 영역 = 전체)에서는 main.tscn의 offset 그대로(0.4.3과 같은 화면).
func _layout_hud() -> void:
	var vp := get_viewport()
	var vis: Rect2 = vp.get_visible_rect()
	var safe: Rect2 = PLayout.safe_rect(vp)
	if _hud_base.is_empty():
		for n in ["HP", "Shield", "HPText", "Dodge", "DodgeText", "Q", "QText", "E", "EText", "Day", "Objective", "Demo", "Settings"]:
			var c0: Control = hud.get_node(n)
			_hud_base[n] = Vector2(c0.offset_left, c0.offset_right)
	var dx: float = safe.position.x - vis.position.x
	for n in _hud_base:
		var c: Control = hud.get_node(String(n))
		var base: Vector2 = _hud_base[n]
		c.offset_left = base.x + dx
		c.offset_right = base.y + dx
	var bar: Control = $UI/HUD/Bar
	bar.offset_left = vis.position.x
	bar.offset_right = vis.end.x
	var obj: Control = $UI/HUD/Objective
	obj.offset_right = safe.end.x - 4.0
	var demo: Control = $UI/HUD/Demo
	demo.offset_right = safe.end.x - 4.0
	var stg: Control = $UI/HUD/Settings
	stg.offset_top = safe.end.y - 18.0
	stg.offset_bottom = safe.end.y
	stg.offset_right = safe.end.x - 4.0
	var boss: Control = $UI/HUD/Boss
	boss.offset_left = vis.position.x + (vis.size.x - 480.0) / 2.0
	boss.offset_right = boss.offset_left + 480.0
	var aw := 960.0
	var ah := 600.0
	if view.st != null:
		aw = float(view.st.arena_w)
		ah = float(view.st.arena_h)
	view.position = Vector2(round(vis.position.x + (vis.size.x - aw) / 2.0), round(vis.position.y + 40.0 + maxf(0.0, (vis.size.y - 40.0 - ah) / 2.0)))
	var reserve := 0.0
	if build_hud != null:
		build_hud.touch_mode = PLayout.is_touch()
		reserve = build_hud.relayout(safe) # 터치일 때는 빌드 줄을 상단에 두고 그 높이를 돌려준다
	if touch != null:
		touch.reserve_top = reserve # 손가락 끌기 영역이 빌드 아이콘과 겹치지 않게 내린다
		touch.layout(safe)
	if orient != null:
		orient.layout(safe) # 전체화면 다시 들어가기 버튼도 안전 영역 안에

func _cfg_text(st: CombatState) -> String:
	if st.cfg.has("weapon"):
		return Game.settings_text(st.cfg)
	return _settings_line(st) + " · 원본 " + Game.HTML_SOURCE

func _process(_dt: float) -> void:
	_poll_fullscreen(_dt) # 전체화면에서 빠져나왔으면 다시 들어가는 버튼을 띄운다
	_orient_guard()       # 세로 상태에서 전투가 돌기 시작하면 그 자리에서 멈춘다
	_duel_gate_tick()
	if _demo_mode:
		_demo_tick(_dt)
	if _capture_mode:
		_capture_tick()
	if _mod_demo:
		_mod_demo_tick()
	if _clip_mode:
		_clip_tick()
	if _movie_mode:
		_movie_tick()
	if _auto:
		_auto_tick()
	if screen == "combat" and view.st != null:
		var st: CombatState = view.st
		# 전투 중 레벨업: 정지 + 3택(회차에서만). 기준 전투·검증 전투는 무시
		if st.level_ups > 0 and st.status == "running" and not choice.is_open():
			st.level_ups = 0
			if fight_kind == "run" and not run.is_empty():
				offer_pending_level_ups()
		_update_hud()
		if debug_panel.visible:
			var p := st.player
			var r2 := st.remaining()
			var mw: Dictionary = st.metrics.enemies.get("wolf", {})
			$UI/Debug/Text.text = "검증 패널 (F3)\n%s\n스텝 %d · 프레임 %d · 이번 프레임 단계 %d · fps %d\n%s\n플레이어 (%.1f, %.1f) 회피cd %.2f 회피 %s 거리 %.1f Qcd %.2f 피격보호 %.2f 체력 %.0f\n적: 지금 %d / 상한 %d · 대기 %d · 등장 %d/%d · 돌진상태 %d(최대 %d) · 물기상태 %d(최대 %d) · 최대 생존 %d\n늑대: 물기 준비 %d 실행 %d 명중 %d · 돌진 준비 %d 실행 %d 명중 %d · 예고 전 사망 %d · 실행 전 사망 %d · 처치 %d · 경험치 %.2f\n받은 피해 %s · 회피 거리 %s" % [_cfg_text(st), st.step_n, view.frame_count, view.steps_this_frame(), Engine.get_frames_per_second(), view.perf_text(), p.x, p.y, p.dodge_cd, ("중" if p.dodge_active else "-"), p.dodge_dist, p.special_cd, p.hit_prot, p.hp, r2.alive, r2.cap, r2.pending, r2.spawned, r2.spawn_total, st.dash_states_count(), st.stats.max_dash_states, st.bite_states_count(), st.stats.max_bite_states, st.stats.max_alive, mw.get("bites_prepared", 0), mw.get("bites_executed", 0), mw.get("bite_hits", 0), mw.get("dashes_prepared", 0), mw.get("dashes_executed", 0), mw.get("dash_hits", 0), mw.get("died_before_attack", 0), mw.get("died_before_execute", 0), mw.get("killed", 0), st.stats.xp, str(st.metrics.taken), str(st.stats.dodge_dists)]
	elif debug_panel.visible:
		var run_txt := ("회차: %d일차 · Lv %d · 금화 %d · 단계 %s · 시드 %d" % [int(run.day), int(run.growth.level), int(run.gold), String(run.phase), int(run.seed)]) if not run.is_empty() else "회차 없음"
		$UI/Debug/Text.text = "검증 패널 (F3)\n다음 기준 전투 설정: %s\n%s\n화면: %s\n비교 설정은 오른쪽에서 고른다. 기준 전투 중에는 바뀌지 않고 다음 재시작(Enter)에 적용된다." % [Game.settings_text(), run_txt, screen]

# ---------- 검증 패널 비교 설정(회피 방식·재사용 대기): 기준 전투 다음 재시작에 적용 ----------
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
		if (screen == "combat" or screen == "result") and fight_kind == "first":
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
	var has_ff: bool = view.st != null and (screen == "combat" or screen == "result") and view.st.cfg.has("formation")
	var now := "현재 전투: " + ((Game.formation_text(view.st.cfg) + " · " + Game.dodge_text(view.st.cfg)) if has_ff else ("회차 전투(기준 전투 아님)" if view.st != null and screen == "combat" else "없음"))
	var nc := Game.current_config()
	var next := "다음 재시작: " + Game.formation_text(nc) + " · " + Game.dodge_text(nc)
	$UI/Debug/Opts/Note.text = now + "\n" + next + "\n(전투 중에는 바뀌지 않음. 같은 시드 = 같은 적 배치)"

# ---------- 검증용 자동 캡처(환경 변수 PROPHECY_CAPTURE=<폴더>): 기준 전투를 봇으로 돌리며 화면을 저장하고 종료 ----------
var _capture_mode := false
var _capture_dir := ""
var _cap_frame := 0
var _cap_done := {}

func _snap_to(dir: String, name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("CAPTURE ", name, " ", img.get_width(), "x", img.get_height())

func _snap(name: String) -> void:
	_snap_to(_capture_dir, name)

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

# ---------- 개조 연출 확인용 연속 프레임 저장(PROPHECY_MOD_DEMO=<폴더>) ----------
## 분열 창날 · 귀환 검기 · 서리 부채 · 깨지는 수정이 실제로 화면에 나온 프레임만 연속 저장한다(영상 아님 — 연속 프레임 PNG).
## 규칙은 건드리지 않는다: 고정 빌드의 검증 전투를 봇으로 돌리고, 개조 표시 효과(split_node·beam(returning)·shatter_burst·fan 탄)가 살아 있는 프레임을 고른다.
var _mod_demo := false
var _mod_dir := ""
var _mod_shots := 0
var _mod_started := false
const MOD_DEMO_MAX := 40

func _mod_demo_start() -> void:
	_mod_started = true
	use_bot = true
	_lab_last = { "kind": "start", "arg": "spear" }
	lab_run = PRun.new_run(1, "spear")
	var g: Dictionary = lab_run.growth
	g.weapons = [{ "id": "spear", "level": 3, "mods": ["split", "returning"] }, { "id": "frost", "level": 3, "mods": ["fan", "shatter"] }]
	g.level = 8
	lab_run.cards = null
	var card: Dictionary = PSortie.cards_for(lab_run)[0]
	var s := PSortie.start(lab_run, String(card.id))
	var st := PFlow.make_encounter(lab_run, s)
	fight_kind = "lab"
	lab_label = "개조 연출 확인: 관통창(분열·귀환) + 서리 수정(부채·깨짐)"
	_view_start(st, make_bot("balanced"))
	show("combat")
	_refresh_combat_texts()

## 지금 화면에 개조 표시 효과가 있으면 그 이름
func _mod_fx_now() -> String:
	if view.st == null:
		return ""
	var names: Array = []
	for f in view.st.effects:
		var k := String(f.kind)
		if k == "split_node":
			names.append("분열")
		elif k == "beam" and bool(f.get("returning", false)):
			names.append("귀환")
		elif k == "shatter_burst":
			names.append("수정파열")
		elif k == "scar_mark":
			names.append("검흔")
	for pr in view.st.projectiles:
		if bool(pr.get("dead", false)):
			continue
		if String(pr.get("mod", "")) == "fan":
			names.append("부채")
		elif String(pr.get("mod", "")) == "split":
			names.append("분열파편")
		elif String(pr.get("mod", "")) == "shatter":
			names.append("수정파편")
	if names.is_empty():
		return ""
	var uniq: Array = []
	for n in names:
		if not uniq.has(n):
			uniq.append(String(n))
	return "+".join(uniq)

func _mod_demo_tick() -> void:
	if not _mod_started:
		if _cap_frame < 10:
			_cap_frame += 1
			return
		_mod_demo_start()
		return
	if screen != "combat" or view.st == null:
		return
	var tag := _mod_fx_now()
	if tag == "" or _mod_shots >= MOD_DEMO_MAX:
		if view.st.t > 40.0 or _mod_shots >= MOD_DEMO_MAX:
			print("MOD_DEMO done shots=", _mod_shots, " t=", snapped(view.st.t, 0.01))
			get_tree().quit()
		return
	_mod_shots += 1
	var name := "mod_%02d_t%0.2f_%s" % [_mod_shots, view.st.t, tag]
	_snap_to(_mod_dir, name)

# ---------- 실제 속도 영상 클립(PROPHECY_CLIP=<이름>) ----------
## 실제 속도로 재생되는 영상 파일을 만들기 위한 장면 준비다. Godot Movie Maker와 함께 쓴다:
##   PROPHECY_CLIP=mixed PROPHECY_CLIP_SEC=8 godot --path prophecy_godot --resolution 1280x720 \
##       --write-movie docs/captures/<파일>.avi --fixed-fps 30
## 규칙을 바꾸지 않는다: 판정·수명·피해·시간 배율(time_scale = 1 그대로)은 건드리지 않고 **어떤 장면을 띄울지**만 고른다.
## 방패병 정면/측후방 클립만 사람 입력을 대신하는 조작(ClipBot)을 쓴다 — 규칙 우회가 아니라 이동 입력이다.
## 길이는 프레임 수로 세므로(--fixed-fps와 같은 값) Movie Maker에서 정확히 그 초만큼 나온다.
const CLIPS := {
	"hud": { "desc": "조작 3칸(Space 회피 · Q 감속장 · E 중력핵) 상태 전환", "kind": "sortie", "region": "forest", "day": 1, "build": "stage1", "e": "gravity" },
	"mixed": { "desc": "일반 혼합 전투(습지 4일차)", "kind": "sortie", "region": "marsh", "day": 4, "build": "stage2", "e": "gravity" },
	"elite": { "desc": "특수 정예(칼날 장인 · 역병술사 · 사슬 파괴자)", "kind": "elites", "build": "stage2", "types": ["elite_blademaster", "elite_plaguecaller", "elite_chainbreaker"] },
	"shield_front": { "desc": "방패병 정면(막힘)", "kind": "shield", "build": "stage1", "drive": "front" },
	"shield_flank": { "desc": "방패병 측후방(돌아 들어가기)", "kind": "shield", "build": "stage1", "drive": "flank" },
	"mission_seal": { "desc": "봉인 임무", "kind": "sortie", "region": "ridge", "day": 3, "build": "stage2", "objective": "seal" },
	"mission_altar": { "desc": "제단 임무", "kind": "sortie", "region": "marsh", "day": 4, "build": "stage2", "objective": "altars" },
	"guardian_cover": { "desc": "수호자 엄폐 대응", "kind": "boss", "boss": "guardian", "build": "stage2" },
	"mod_spear_off": { "desc": "개조 전: 관통창(개조 없음)", "kind": "modcmp", "weapons": [{ "id": "spear", "level": 3, "mods": [] }] },
	"mod_spear_on": { "desc": "개조 후: 관통창 + 귀환 검기", "kind": "modcmp", "weapons": [{ "id": "spear", "level": 3, "mods": ["returning"] }] },
	"mod_frost_off": { "desc": "개조 전: 서리 수정(개조 없음)", "kind": "modcmp", "weapons": [{ "id": "frost", "level": 3, "mods": [] }] },
	"mod_frost_on": { "desc": "개조 후: 서리 수정 + 서리 부채 · 깨지는 수정", "kind": "modcmp", "weapons": [{ "id": "frost", "level": 3, "mods": ["fan", "shatter"] }] },

	# ---------- 0.9.x 새 보조무기와 연계(2026-09-09) ----------
	# 전부 실제 편성(sortie)에서 찍는다 — 연습장이 아니라 평소 전투에서 그 효과가 보이는지가 중요하다.
	# 주무기·보조·개조는 새 슬롯 구조의 상한을 지킨다(주무기 Lv5·개조 2 / 보조 Lv3·개조 1).
	"sup_crow": { "desc": "추격 까마귀 — 주무기로 맞힌 적을 물고 늘어진다", "kind": "sortie", "region": "marsh", "day": 4,
		"weapons": [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "crow", "level": 3, "mods": ["hunt"] }] },
	"sup_bell": { "desc": "수호 방울 — 날아오는 화살을 대신 막는다", "kind": "arena", "types": ["archer"], "count": 4, "bot": "novice",
		"weapons": [{ "id": "bow", "level": 4, "mods": ["spread"] }, { "id": "bell", "level": 3, "mods": ["layered"] }] },
	"sup_echo": { "desc": "잔영 분신 — 짧은 시간차로 같은 공격을 한 번 더", "kind": "sortie", "region": "marsh", "day": 4,
		"weapons": [{ "id": "daggers", "level": 4, "mods": ["bleed"] }, { "id": "echo", "level": 3, "mods": ["cross"] }] },
	"sup_wind": { "desc": "바람 정령 — 붙은 적을 밀어내 거리를 만든다", "kind": "sortie", "region": "marsh", "day": 4,
		"weapons": [{ "id": "spear", "level": 4, "mods": ["returning"] }, { "id": "wind", "level": 3, "mods": ["focused"] }] },
	"sup_plague": { "desc": "역병 나비 — 감염된 적이 죽으면 주변으로 옮는다", "kind": "sortie", "region": "marsh", "day": 4,
		"weapons": [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "plague", "level": 3, "mods": ["burst"] }] },
	"sup_thorns": { "desc": "가시 갑각 — 근접 피해를 줄이고 되받아친다", "kind": "arena", "types": ["wolf"], "count": 10, "bot": "novice",
		"weapons": [{ "id": "daggers", "level": 1, "mods": [] }, { "id": "thorns", "level": 3, "mods": ["focused"] }] },
	"sup_doll": { "desc": "도깨비 인형 — 적을 끌어가 대신 맞는다", "kind": "arena", "types": ["wolf"], "count": 10, "bot": "novice",
		"weapons": [{ "id": "hammer", "level": 1, "mods": [] }, { "id": "doll", "level": 3, "mods": ["tough"] }] },

	# 연계: 감전은 **기본 연쇄**가 건다(개조 없이도). 분신의 모방 타격도 감전을 터뜨린다
	"syn_shock": { "desc": "감전 연계 — 번개가 걸고 쌍검·분신이 터뜨린다", "kind": "sortie", "region": "marsh", "day": 4,
		"weapons": [{ "id": "daggers", "level": 4, "mods": ["bleed"] }, { "id": "orb", "level": 3, "mods": ["conduct"] }] },
	"syn_flare": { "desc": "불꽃 파열 — 불붙은 적이 죽으면 터진다", "kind": "sortie", "region": "marsh", "day": 4,
		"weapons": [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "ember", "level": 3, "mods": ["scatter"] }],
		"commons": { "ember": 1, "flare": 1, "burn": 1 } },

	# 보스가 엄폐물을 부순다(2026-09-09). 성격에 맞는 행동이 실제로 선택되는지 본다
	"boss_break_warden": { "desc": "성문 파수장 — 방패 돌파로 바위를 부순다(엄폐 뒤에 선 채로)", "kind": "boss", "boss": "gate_warden", "build": "stage2", "drive": "cover" },
	"boss_break_guardian": { "desc": "봉인 수호자 — 막은 장애물을 지목해 부순다(엄폐 뒤에 선 채로)", "kind": "boss", "boss": "guardian", "build": "stage2", "drive": "cover" },

	# ---------- 1.0.x 새 몬스터 · 테마 협공 · 특수 정예 결투(2026-09-09) ----------
	# 앞의 열한 편은 보조무기와 개조를 찍었다. 여기서는 **적 쪽에 새로 들어온 것**을 찍는다.
	# 신규 3종은 **약한 빌드**로 찍는다. 완성 빌드(stage2)로 세우면 박쥐(체력 18)가 2초 안에 전멸해
	# '치고 빠지는' 행동 자체가 화면에 남지 않는다. 규칙이 아니라 촬영용 상대의 세기를 고른 것이다
	"mon_new": { "desc": "신규 일반 3종 — 흡혈 박쥐(물고 이탈) · 불씨 도마뱀(불줄기) · 도약 두꺼비(착지 예고)", "kind": "arena",
		"types": ["bat", "lizard", "toad"], "count": 4, "bot": "novice",
		"weapons": [{ "id": "sword", "level": 1, "mods": [] }] },
	"mon_elite": { "desc": "일반 정예 변종 — 쇄도 멧돼지 · 연사 궁수 · 충격 두꺼비(늑대 셋과 함께)", "kind": "elites", "build": "stage2",
		"types": ["boar_elite", "archer_elite", "toad_elite"] },
	# 협공은 **실제 출격 편성**으로만 찍는다. 연습장에 세우면 등장 시차·분대 배치가 사라져 협공이 아니게 된다
	"form_coop": { "desc": "테마 협공 — 얼어붙은 협곡 '봉쇄와 사격 사이 통과'(서리술사가 길을 좁히고 궁수가 겹친다)",
		"kind": "sortie", "region": "t2c_snow", "day": 5, "build": "stage2", "formationId": "t2c_frost_wolf" },
	"form_coop2": { "desc": "테마 협공 — 사냥 숲 '막힌 길과 착지 예고'(거미줄 + 두꺼비 착지)",
		"kind": "sortie", "region": "t1a_path", "day": 2, "build": "stage1", "formationId": "t1a_boar" },
	# 결투: 일반 편성 증원이 없는 1대1. 특수 정예 자신의 소환·깃발·구조물은 그대로 나온다
	"duel_special": { "desc": "특수 정예 결투 — 증원 없는 1대1(사냥 숲 · 송곳니 우두머리)",
		"kind": "sortie", "region": "t1a_path", "day": 2, "build": "stage1", "duelType": "elite_fang", "warmup_until": "transition" },
	"duel_standard": { "desc": "특수 정예 결투 — 군단 기수(부하 소환은 유지된다)",
		"kind": "sortie", "region": "t1b_yard", "day": 2, "build": "stage1", "duelType": "elite_standard", "warmup_until": "transition" },

	# ---------- 1.1.0 이번에 고치거나 새로 넣은 것(2026-09-09) ----------
	# 사용자 지시: 쌍검 중첩 · 정상화된 창 분열 · 잔바람의 보스 적용 · 일반 적 빙결/파쇄 ·
	# 보스 결빙/파쇄를 **실제 속도로** 보여 준다.
	# 보스를 상대로 찍는다. 일반 적은 중첩이 차기 전에 죽어 고리가 화면에 남지 않는다
	"dagger_focus": { "desc": "쌍검 집중 중첩 — 겨눈 적을 칠 때마다 중첩이 차고 최대 6에서 모양이 바뀐다",
		"kind": "boss", "boss": "guardian", "build": "stage2",
		"weapons": [{ "id": "daggers", "level": 4, "mods": ["bleed"] }] },
	# 창 분열: 첫 적 뒤에 둘째·셋째를 세워 **분열탄이 뒤쪽 적을 맞히는** 것을 본다.
	# 고치기 전에는 창날이 첫 적에게 다시 흡수돼 뒤쪽에 아무것도 닿지 않았다
	"spear_split": { "desc": "정상화된 분열 창날 — 첫 적을 뚫고 나온 창날이 뒤쪽 적을 맞힌다",
		"kind": "arena", "types": ["wolf"], "count": 6, "bot": "balanced",
		"weapons": [{ "id": "spear", "level": 4, "mods": ["split"] }] },
	# 잔바람: 보스는 밀리지 않는다. 그런데도 **돌풍이 지나간 자리**에 둔화 바람이 남는지 본다
	# **근접 주무기 + 긴 클립으로 찍는다.** 활로 찍으면 봇이 거리를 벌려 돌풍 발동 거리(120px)
	# 안에 보스가 안 들어온다. 검으로 바꿔도 8초로는 붙기 전에 끝나 fires 0이었고,
	# 25초를 굴리니 fires 3 · 밀린 거리 0.0(보스 면역 유지) · 둔화 4.33 적·초가 나왔다
	"wind_boss": { "desc": "잔바람이 보스에게도 걸린다 — 밀리지 않아도 지나간 자리에 바람이 남는다",
		"kind": "boss", "boss": "guardian", "build": "stage2",
		"weapons": [{ "id": "sword", "level": 4, "mods": ["cross"] }, { "id": "wind", "level": 3, "mods": ["lingering"] }] },
	# 일반 적 빙결·파쇄: 냉기 5중첩 → 얼음 덮개 → 주무기로 깨면 파편
	# **버티는 적으로, 개조 없이 찍는다.** 늑대로 찍었더니 5중첩 전에 죽었고(freezes 0),
	# '넓은 빙결'(fan)을 끼웠더니 세 갈래로 나뉘어 한 적이 5중첩에 못 닿았다(중첩 유지 3초).
	# 기본형으로도 5중첩까지 안 찼다 — 탄환이 14초에 5발(약 2.8초에 한 발)인데
	# 중첩 유지가 3초라 움직이는 적에게는 좀처럼 쌓이지 않는다(측정: chill_stacks 5 · freezes 0).
	# 그래서 개조 '빠른 빙결'(ground)로 찍는다. 이건 **촬영 조건**이지 밸런스 판단이 아니다 —
	# "기본형으로는 일반 적을 얼리기 어렵다"는 측정 결과는 보고에 그대로 남긴다
	"frost_shatter": { "desc": "냉기 → 빙결 → 주무기 파쇄 — 얼음이 씌워지고 깨지면 파편이 퍼진다",
		"kind": "arena", "types": ["shieldbearer"], "count": 2, "bot": "balanced",
		"weapons": [{ "id": "sword", "level": 3, "mods": [] }, { "id": "frost", "level": 3, "mods": ["ground"] }] },
	# 보스 결빙: 몸이 멈추지 않는다(서리 조각과 둘레를 도는 알갱이만). 파쇄 피해와 파편은 난다
	"boss_chill": { "desc": "보스 결빙 — 멈추지 않는다. 그래도 파쇄 피해와 파편은 난다",
		"kind": "boss", "boss": "guardian", "build": "stage2",
		"weapons": [{ "id": "sword", "level": 5, "mods": ["cross", "trail"] }, { "id": "frost", "level": 3, "mods": ["ground"] }] },
}

## 방패병 클립 전용 조작(사람 입력 자리): 정면에서 버티거나, 뒤로 돌아 들어간다. 규칙은 건드리지 않는다
class ClipBot extends PBot:
	var mode := "front"
	var ang := 0.0
	func _init(m: String) -> void:
		super("balanced")
		mode = m
	func step_input(st: CombatState) -> Dictionary:
		var inp := super.step_input(st)
		if mode == "cover":
			# 보스에서 본 장애물 **반대편**에 선다. 회피·공격은 평소 봇 그대로다
			var src := st.boss if not st.boss.is_empty() else {}
			if src.is_empty():
				return inp
			var best := {}
			var bd := 1.0e9
			for ob in st.obstacles:
				var d: float = PGeom.dist(float(ob.x), float(ob.y), float(src.x), float(src.y))
				if d < bd:
					bd = d
					best = ob
			if best.is_empty():
				return inp
			var nx: float = float(best.x) - float(src.x)
			var ny: float = float(best.y) - float(src.y)
			var nl: float = sqrt(nx * nx + ny * ny)
			if nl < 1.0:
				return inp
			var wx: float = float(best.x) + nx / nl * (float(best.r) + 26.0)
			var wy: float = float(best.y) + ny / nl * (float(best.r) + 26.0)
			var ddx: float = wx - float(st.player.x)
			var ddy: float = wy - float(st.player.y)
			var dd: float = sqrt(ddx * ddx + ddy * ddy)
			if dd > 8.0:
				inp.mx = ddx / dd
				inp.my = ddy / dd
			else:
				inp.mx = 0.0
				inp.my = 0.0
			return inp
		var tg := {}
		for e in st.alive_targets():
			if String(e.type) == "shieldbearer":
				tg = e
				break
		if tg.is_empty():
			return inp
		var p := st.player
		var want_x: float = float(tg.x)
		var want_y: float = float(tg.y)
		if mode == "flank":
			ang += 1.7 * PBot.STEP # 초당 약 97도로 상대 주위를 돈다
			want_x += cos(ang) * 74.0
			want_y += sin(ang) * 74.0
		else:
			want_x -= 78.0 # 정면(왼쪽)에서 버틴다
		var dx: float = want_x - p.x
		var dy: float = want_y - p.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > 6.0:
			inp.mx = dx / d
			inp.my = dy / d
		else:
			inp.mx = 0.0
			inp.my = 0.0
		return inp

var _clip_mode := false
var _clip_id := ""
var _clip_sec := 8.0
var _clip_fps := 30.0
var _clip_frames := 0
var _clip_started := false

## 클립용 회차: 관문 프리셋(balance.json lab.BUILDS)에서 필요한 부분만 바꾼다
func _clip_run(c: Dictionary) -> Dictionary:
	var preset: Dictionary = PCatalog.lab().BUILDS[String(c.get("build", "stage2"))]
	var gw: Dictionary = preset.growth
	var ws: Array = c.get("weapons", [])
	var first := String(ws[0].id) if not ws.is_empty() else String((gw.weapons as Array)[0].id)
	var run := PRun.new_run(int(c.get("seed", 7)), first)
	run.day = int(c.get("day", 4))
	var g: Dictionary = run.growth
	if ws.is_empty():
		var out := []
		for w in gw.weapons:
			out.append({ "id": String(w.id), "level": int(w.level), "mods": (w.mods as Array).duplicate() if w.has("mods") else [] })
		g.weapons = out
		var cm := {}
		for k in gw.get("commons", {}):
			cm[String(k)] = int(gw.commons[k])
		g.commons = cm
	else:
		g.weapons = ws.duplicate(true)
		# 공용 증강은 클립이 따로 적었을 때만 넣는다(불꽃 파열 같은 연계를 보여 주려면 필요하다)
		var cm2 := {}
		for k in c.get("commons", {}):
			cm2[String(k)] = int(c.commons[k])
		g.commons = cm2
	if c.has("e"):
		g.skills.e = { "id": String(c.e), "level": 2, "variant": null }
	elif gw.has("e"):
		g.skills.e = { "id": String(gw.e.id), "level": int(gw.e.level), "variant": (String(gw.e.variant) if gw.e.get("variant", null) != null else null) }
	g.level = 6
	run.hp = float(PRun.build(run).hp_max)
	return run

func _clip_start() -> void:
	_clip_started = true
	if not CLIPS.has(_clip_id):
		printerr("CLIP 이름 없음: ", _clip_id, " (있는 것: ", CLIPS.keys(), ")")
		get_tree().quit(3)
		return
	var c: Dictionary = CLIPS[_clip_id]
	var run := _clip_run(c)
	var kind := String(c.kind)
	var st: CombatState
	# 봇 실력은 클립이 고를 수 있다. 가시 갑각·수호 방울·도깨비 인형처럼 **맞아야 일하는 보조**는
	# 잘 피하는 봇으로 찍으면 6초 내내 아무 일도 일어나지 않는다. 규칙은 그대로이고 조종자만 바꾸는 것이다
	var bot: PBot = make_bot(String(c.get("bot", "balanced")))
	match kind:
		"boss":
			var b := PRun.build(run)
			st = CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": 7, "boss": true, "boss_id": String(c.boss),
				"boss_hp": float(PCatalog.boss_def(String(c.boss)).hp), "arena": "clearing", "region_id": "boss",
				"xp_kill_mult": PRun.kill_xp_mult(run), "run": run })
		"arena":
			# 정해진 적을 바로 세운다. 판정·피해·수명은 그대로이고 **누구를 세우느냐만** 고른 것이다.
			# 실제 출격에서는 6~12초 안에 근접 접촉이 안 생기는 편성이 많아, 방어 보조가 일하는 장면을 못 찍는다
			var b3 := PRun.build(run)
			st = CombatState.new({ "build": b3, "hp": float(b3.hp_max), "seed": 7, "waves": [], "arena": "clearing", "region_id": "lab", "act": 2, "run": run })
			st.spawn_hold = true
			var ax: float = float(st.player.x)
			var ay: float = float(st.player.y)
			var k := 0
			for tp2 in c.get("types", []):
				for m in int(c.get("count", 3)):
					var ang2 := TAU * float(k) / 8.0
					st.spawn_enemy(String(tp2), ax + cos(ang2) * 190.0, ay + sin(ang2) * 190.0)
					k += 1
		"elites", "shield":
			var b2 := PRun.build(run)
			st = CombatState.new({ "build": b2, "hp": float(b2.hp_max), "seed": 7, "waves": [], "arena": "clearing", "region_id": "lab", "act": 2, "run": run })
			st.spawn_hold = true # 클립 길이 동안 새 등장·승리 판정 없이 그 장면만 보여 준다
			var px: float = float(st.player.x)
			var py: float = float(st.player.y)
			if kind == "shield":
				# 3기를 떨어뜨려 세운다: 1기만 두면 1~2초 만에 쓰러져 나머지 시간이 빈 화면이 된다.
				# 체력·방어 판정은 그대로이고 '몇 마리를 세우느냐'만 고른 것이다
				st.spawn_enemy("shieldbearer", px + 210.0, py)
				st.spawn_enemy("shieldbearer", px + 250.0, py - 130.0)
				st.spawn_enemy("shieldbearer", px + 250.0, py + 130.0)
				bot = ClipBot.new(String(c.get("drive", "front")))
			else:
				var i := 0
				for tp in c.types:
					st.spawn_enemy(String(tp), px + 190.0 + float(i) * 70.0, py - 60.0 + float(i) * 60.0)
					i += 1
				for j in 3:
					st.spawn_enemy("wolf", px + 150.0, py - 90.0 + float(j) * 90.0)
		_:
			var sortie := { "regionId": String(c.get("region", "marsh")), "deep": false, "encounters": 0,
				"seed": 7 * 131 + int(run.day) * 17, "day": int(run.day), "slot": 0, "variant": null }
			if c.has("objective"):
				sortie.mission = true
				sortie.objective = String(c.objective)
				sortie.cardId = "clip"
			if c.has("formationId"): # 테마 협공: 어느 편성인지 못 박는다(안 적으면 그날의 기본 편성이 나온다)
				sortie.formationId = String(c.formationId)
			if c.has("duelType"): # 특수 정예 결투 상대. PRun.encounter_waves가 이 값을 그대로 읽는다
				sortie.duelType = String(c.duelType)
			st = CombatState.new(PFlow.encounter_opts(run, sortie))
	# 엄폐 조작은 종류를 가리지 않는다(보스 파괴 클립이 쓴다). match 밖에 두어야 보스 갈래에도 걸린다
	if String(c.get("drive", "")) == "cover":
		bot = ClipBot.new("cover")
	fight_kind = "lab"
	use_bot = true
	lab_label = "영상 클립: " + String(c.desc)
	_view_start(st, bot)
	# **앞 구간 미리 돌리기.** 결투는 일반 편성을 전부 정리한 뒤에 열리므로(CombatState.update_duel),
	# 그냥 찍으면 짧은 클립이 일반 전투만 담는다. 여기서는 결투가 시작될 때까지를 **한 프레임 안에서**
	# 미리 돌린 뒤 촬영을 시작한다 — 규칙·시간 배율·봇은 그대로이고, 영상에 담는 구간만 고른 것이다.
	# (Movie Maker는 그린 프레임만 담으므로 이 되감기는 파일에 들어가지 않는다.)
	var until := String(c.get("warmup_until", ""))
	if until != "":
		var wf := 0
		while wf < 60 * 240:
			if until == "duel" and view.st != null and view.st.duel_stage == "duel":
				break
			# "transition"은 **전환 장면부터** 찍는다: 일반 편성이 정리된 순간(normal을 벗어난 첫 프레임)에 멈춘다.
			# 그래야 잔여 정리 → 성장 선택 → 등장 연출 → 결투가 영상 안에 그대로 들어간다
			if until == "transition" and view.st != null and view.st.duel_stage != "normal":
				break
			if view.st == null or String(view.st.status) != "running":
				break
			view._process(1.0 / 60.0)
			wf += 1
		print("CLIP warmup=", _clip_id, " until=", until, " sec=", snapped(float(wf) / 60.0, 0.01),
			" duel_stage=", (view.st.duel_stage if view.st != null else "?"))
	show("combat")
	_refresh_combat_texts()
	print("CLIP start=", _clip_id, " sec=", _clip_sec, " fps=", _clip_fps, " ", String(c.desc))

func _clip_tick() -> void:
	if not _clip_started:
		_clip_frames += 1
		if _clip_frames >= 12: # 첫 몇 프레임은 창·배치가 잡히는 시간
			_clip_frames = 0
			_clip_start()
		return
	_clip_frames += 1
	if float(_clip_frames) >= _clip_sec * _clip_fps:
		var tt: float = view.st.t if view.st != null else -1.0
		# **찍힌 장면에 그 효과가 실제로 들어 있었는지**를 함께 남긴다.
		# 파일이 만들어졌다는 것과 효과가 보인다는 것은 다른 말이라, 영상 목록에 이 수치를 같이 적는다.
		var sup_m := {}
		var cause_m := {}
		if view.st != null:
			sup_m = (view.st.metrics.support as Dictionary).duplicate(true)
			cause_m = (view.st.metrics.cause_fires as Dictionary).duplicate()
			cause_m["부순 장애물"] = (view.st.metrics.get("broken", []) as Array).size()
		# **누가 실제로 나왔는지**도 함께 남긴다. 새 몬스터·협공 편성·결투 클립은
		# "그 종류가 화면에 있었는가"가 곧 촬영 성공 여부라, 지표만으로는 확인이 안 된다.
		var seen := {}
		var duel := ""
		if view.st != null:
			for e in view.st.enemies:
				var tk := String(e.get("type", ""))
				seen[tk] = int(seen.get(tk, 0)) + 1
			duel = String(view.st.duel_stage)
		print("CLIP done=", _clip_id, " frames=", _clip_frames, " combat_t=", snapped(tt, 0.01), " screen=", screen,
			" enemies=", JSON.stringify(seen), " duel=", duel,
			" support=", JSON.stringify(sup_m), " cause=", JSON.stringify(cause_m))
		get_tree().quit()

# ---------- 회차 화면 자동 진행(PROPHECY_UI_SMOKE=<폴더> / 봇 회차 데모): 프레임 수로만 진행 ----------
var _auto := false
var _auto_snap := false
var _auto_quit := false
var _auto_dir := ""
var _auto_full := false
var _auto_stop := "" # PROPHECY_UI_STOP=<단계 이름>: 그 캡처 뒤 종료(짧은 영상 기록용)
var _auto_state := "start"
var _auto_wait := 0
var _auto_done := {}
var _auto_frames := 0
var _auto_seed := 1   # 자동 진행은 같은 시드(재현 가능)
## 완료 판정(2026-09-08): 프레임 수가 아니라 단조 증가 시계로 실제 경과를 잰다.
## 이전의 프레임 상한(144000)은 60FPS일 때만 40분이고, 배속·부하에 따라 실제 경과와 달랐다.
## 또한 시간 초과와 정상 완료가 같은 출력·같은 종료 코드였다. 이제 서로 구분한다.
var _auto_t0_ms := 0                 # 시작 시각(Time.get_ticks_msec)
var _auto_budget_sec := 2400.0       # 실제 경과 상한(PROPHECY_UI_MAXMIN 분)
var _auto_stall_sec := 300.0         # 진행 정체 판정 시간(PROPHECY_UI_STALL 초)
var _auto_last_progress_ms := 0      # 마지막으로 진행이 있었던 시각
var _auto_last_progress := ""        # 그때의 진행 이름
var _auto_sig := ""                  # 진행 여부를 재는 상태 서명(화면·단계·등장·처치)
var _auto_combat_sec := 0.0          # 게임 속 전투 시간 합계(실제 경과와 구분해 기록)
var _auto_combat_seen := {}          # 전투별 1회만 더하기
var _auto_status := "running"        # running | done | incomplete | timeout | stalled
var _auto_reached := {}              # 도달한 필수 단계 → 그때의 실제 경과 초
var _auto_seg_ms := {}               # 구간별 소요(진단용)
var _auto_seg_t0 := 0
var _auto_beat_ms := 0               # 진행 상황 정기 출력(멈춘 구간을 로그만으로 찾기 위해)

## 한 번만 실행하는 자동 진행 단계(실행했으면 true, 다음 틱까지 잠깐 기다린다)
func _auto_step(key: String, action: Callable) -> bool:
	if _auto_done.has(key):
		return false
	_auto_done[key] = true
	_auto_note_progress("step:" + key)
	action.call()
	_auto_wait = 3
	return true

## 진행이 있었다고 표시한다(정체 판정의 기준). 직전 구간의 소요 시간도 남긴다
func _auto_note_progress(what: String) -> void:
	var now := Time.get_ticks_msec()
	if _auto_last_progress != "":
		_auto_seg_ms[_auto_last_progress] = now - _auto_seg_t0
	_auto_seg_t0 = now
	_auto_last_progress = what
	_auto_last_progress_ms = now

## 필수 단계 도달 기록. 완료 판정은 오직 이 목록으로 한다
func _auto_reach(id: String) -> void:
	if _auto_reached.has(id):
		return
	var sec := int(Time.get_ticks_msec() - _auto_t0_ms) / 1000
	_auto_reached[id] = sec
	# wall_sec은 **실행 시작 후 누적 실제 경과 시간(도달 시각)**이다. 그 단계 자체의 소요 시간이 아니다.
	# 게임 속 전투 시간은 game_combat_sec으로 따로 센다.
	print("UI_SMOKE reached=", id, " wall_sec_cumulative=", sec,
		" game_combat_sec=", snapped(_auto_combat_sec, 0.1))

## 화면·단계·등장 수·처치 수를 묶은 서명. 이 값이 바뀌면 "진행 중"이다
func _auto_signature() -> String:
	var sig := screen + "|" + _auto_state
	if not run.is_empty():
		sig += "|d%d.h%d.%s" % [int(run.day), int(run.hours), String(run.phase)]
	if view != null and view.st != null:
		var st: CombatState = view.st
		var dead := 0
		for e in st.enemies:
			if e.dead:
				dead += 1
		sig += "|%s.s%d.k%d" % [st.status, int(st.spawn_count), dead]
	return sig

func _auto_shot(name: String) -> void:
	if _auto_done.has(name):
		return
	_auto_done[name] = true
	_auto_note_progress("shot:" + name)
	if _auto_snap:
		_snap_to(_auto_dir, name)
	if _auto_stop != "" and name == _auto_stop:
		_auto_wait = 1000000
		call_deferred("_auto_finish")
	print("UI_SMOKE step=", name, " screen=", screen, " state=", _auto_state, " day=", (int(run.day) if not run.is_empty() else 0), " phase=", (String(run.phase) if not run.is_empty() else "-"))

## 자동 진행이 반드시 지나야 하는 단계.
## 전체 진행 모드는 관문 3개 → 10일차 회차 결과 → 저장/계속하기까지 도달해야 정상 완료다.
## 짧은 화면 순회 모드는 거점·전투·저장/계속하기까지만 요구한다(별도 기준이며 완주가 아니다).
func _auto_required() -> Array:
	if _auto_stop != "": # 특정 캡처에서 끊는 짧은 기록용 실행. 완주 판정 대상이 아니다
		return []
	if _auto_full:
		return ["gate1", "gate2", "gate3", "run_result", "save_continue"]
	return ["base", "combat", "save_continue"]

## 멈춘 시점의 상태를 남긴다(원인 구분용). 추정 대신 이 기록으로 판단한다
func _auto_diagnostics() -> Dictionary:
	var d := {
		"screen": screen, "auto_state": _auto_state, "choice_open": choice.is_open(),
		"wall_sec": int(Time.get_ticks_msec() - _auto_t0_ms) / 1000,
		"game_combat_sec": snapped(_auto_combat_sec, 0.1),
		"frames": _auto_frames,
		"last_progress": _auto_last_progress,
		"since_progress_sec": int(Time.get_ticks_msec() - _auto_last_progress_ms) / 1000,
		"segments_ms": _auto_seg_ms.duplicate(),
	}
	if not run.is_empty():
		d["day"] = int(run.day)
		d["hours_left"] = int(run.hours)
		d["phase"] = String(run.phase)
		d["level"] = int(run.growth.level)
		d["stage"] = int(run.stage)
		d["bosses_done"] = (run.bossesDone as Array).duplicate()
		d["boss_retries"] = int(run.get("bossRetries", 0))
	if view != null and view.st != null:
		var st: CombatState = view.st
		var alive := 0
		var nearest := -1.0
		for e in st.enemies:
			if e.dead or bool(e.get("hidden", false)):
				continue
			alive += 1
			var dd := PGeom.dist(float(e.x), float(e.y), float(st.player.x), float(st.player.y))
			if nearest < 0.0 or dd < nearest:
				nearest = dd
		var remain := []   # 남은 개체를 종류·상태별로 남긴다(무엇 때문에 끝나지 않는지 보려고)
		for e in st.enemies:
			if e.dead:
				continue
			remain.append({
				"type": String(e.get("type", "?")), "hp": int(e.get("hp", 0)),
				"hidden": bool(e.get("hidden", false)), "structure": bool(e.get("structure", false)),
				"tier": String(e.get("tier", "")), "state": String(e.get("state", "")),
				"pos": [int(e.x), int(e.y)],
				"dist": int(PGeom.dist(float(e.x), float(e.y), float(st.player.x), float(st.player.y))),
			})
		d["combat"] = {
			"remaining": remain,
			"region": st.region_id, "t": snapped(st.t, 0.1), "status": st.status,
			"objective": st.objective, "obj_done": bool(st.obj.get("done", false)),
			"obj_hud": (PObjectives.hud_line(st, st.obj) if PObjectives.is_objective(st.objective) else ""),
			"obj_keys": st.obj.keys(), "time_limit": st.time_limit, "spawn_hold": st.spawn_hold,
			"alive": alive, "pending_spawn": st.pending.size(),
			"spawned": int(st.spawn_count), "spawn_total": int(st.spawn_total), "spawned_all": bool(st.spawned_all),
			"player_pos": [int(st.player.x), int(st.player.y)], "player_hp": int(st.player.hp),
			"player_dodge": bool(st.player.get("dodge_active", false)), "obstacles": st.obstacles.size(),
			"arena": [int(st.arena_w), int(st.arena_h)], "player_r": float(st.player.r),
			"obstacle_list": _auto_obstacles(st),
			"nearest_enemy_dist": (int(nearest) if nearest >= 0.0 else -1),
			"zones": st.zones.size(), "projectiles": st.projectiles.size(),
			"bot": view.bot != null, "paused": view.paused, "time_scale": view.time_scale,
			"bot_info": (view.bot.debug_state() if view.bot != null and view.bot.has_method("debug_state") else {}),
			# 이동 진단(계측 전용, combat_view._move_watch): 입력 → 시뮬 전달 → 실제 이동량 → 거부 이유
			"move": (view.move_diag() if view.has_method("move_diag") else {}),
		}
	return d

## 장애물과 플레이어의 겹침(끼임 여부 판정용)
func _auto_obstacles(st: CombatState) -> Array:
	var out := []
	for ob in st.obstacles:
		var d := PGeom.dist(float(ob.x), float(ob.y), float(st.player.x), float(st.player.y))
		out.append({ "type": String(ob.get("type", "")), "pos": [int(ob.x), int(ob.y)], "r": float(ob.r),
			"dist": snapped(d, 0.1), "overlap": snapped(float(ob.r) + float(st.player.r) - d, 0.1) })
	return out

func _auto_finish(status: String = "done") -> void:
	if not _auto:
		return
	_auto_status = status
	var missing := []
	for r in _auto_required():
		if not _auto_reached.has(r):
			missing.append(r)
	# 요구한 마지막 단계까지 도달했을 때만 정상 완료다. 중단·시간 초과는 완료가 아니다
	if status == "done" and not missing.is_empty():
		_auto_status = "incomplete"
	var diag := _auto_diagnostics()
	print("UI_SMOKE result=", _auto_status, " reached=", JSON.stringify(_auto_reached),
		" missing=", JSON.stringify(missing), " wall_sec=", diag.wall_sec,
		" game_combat_sec=", diag.game_combat_sec)
	print("UI_SMOKE diagnostics=", JSON.stringify(diag))
	print("UI_SMOKE done state=", _auto_state, " run=", JSON.stringify({ "day": int(run.day), "phase": String(run.phase), "level": int(run.growth.level), "gold": int(run.gold), "stage": int(run.stage), "bossesDone": run.bossesDone, "retries": int(run.bossRetries) }) if not run.is_empty() else "{}", " summary=", JSON.stringify(last_summary))
	if _auto_dir != "":
		var f := FileAccess.open(_auto_dir.path_join("smoke_result.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({ "status": _auto_status, "full": _auto_full,
				"required": _auto_required(), "reached": _auto_reached, "missing": missing,
				"diagnostics": diag, "version": Game.VERSION }, "  "))
			f.close()
	_auto = false
	if _auto_quit:
		# 종료 코드 — 0 정상 완료 / 2 시간 초과 / 3 진행 정체 / 4 필수 단계 미도달
		var code := 0
		match _auto_status:
			"timeout": code = 2
			"stalled": code = 3
			"incomplete": code = 4
		get_tree().quit(code)

func _auto_tick() -> void:
	_auto_frames += 1
	var now := Time.get_ticks_msec()
	if view != null and view.st != null and view.st.status != "running":
		var key := "%d:%s:%0.1f" % [int(view.st.seed_value), String(view.st.region_id), view.st.t]
		if not _auto_combat_seen.has(key): # 게임 속 전투 시간(실제 경과와 따로 기록한다)
			_auto_combat_seen[key] = true
			_auto_combat_sec += float(view.st.t)
	var sig := _auto_signature() # 화면·날짜·등장·처치 중 하나라도 바뀌면 진행 중이다
	if sig != _auto_sig:
		_auto_sig = sig
		_auto_last_progress_ms = now
	if now - _auto_beat_ms >= 30000: # 30초마다 현재 위치를 남긴다(중단 지점을 로그에서 바로 찾는다)
		_auto_beat_ms = now
		print("UI_SMOKE heartbeat wall_sec=", int(now - _auto_t0_ms) / 1000,
			" sig=", sig, " since_progress_sec=", int(now - _auto_last_progress_ms) / 1000,
			" combat_sec=", snapped(_auto_combat_sec, 0.1),
			" t=", (snapped(view.st.t, 0.1) if view != null and view.st != null else 0.0),
			" ppos=", ([int(view.st.player.x), int(view.st.player.y)] if view != null and view.st != null else []),
			# 멈춤이 '이동 불능' 때문인지 로그만으로 가릴 수 있게 이유를 같이 남긴다(계측 전용)
			" move=", (JSON.stringify(view.move_diag().get("이유", [])) if view != null and view.st != null and view.has_method("move_diag") else "[]"))
	if float(now - _auto_t0_ms) / 1000.0 > _auto_budget_sec:
		print("UI_SMOKE timeout wall_sec=", int(now - _auto_t0_ms) / 1000, " budget_sec=", int(_auto_budget_sec))
		_auto_finish("timeout")
		return
	if float(now - _auto_last_progress_ms) / 1000.0 > _auto_stall_sec:
		print("UI_SMOKE stalled since_progress_sec=", int(now - _auto_last_progress_ms) / 1000,
			" last_progress=", _auto_last_progress, " sig=", _auto_sig)
		_auto_finish("stalled")
		return
	if _auto_wait > 0:
		_auto_wait -= 1
		return
	if choice.is_open(): # 어떤 3택이든 첫 후보 선택(레벨업 3택 화면은 1회 저장)
		if not _auto_done.has("13_choice"):
			_auto_shot("13_choice")
			_auto_wait = 2
			return
		var cs: Array = choice.offer.get("choices", [])
		if cs.size() > 0:
			# 항상 첫 후보를 고르면(옛 방식) 빌드가 한쪽으로 치우쳐 회차 검증이 성장 부족으로 막힌다.
			# 회차 봇과 같은 선택 규칙(PBot.pick_choice)을 쓴다. 전투 규칙·수치는 그대로다.
			var pick := PBot.pick_choice(choice.offer, int(run.seed) if not run.is_empty() else _auto_seed)
			_on_pick(String(pick.key) if not pick.is_empty() else String(cs[0].key))
		else:
			_on_skip()
		_auto_wait = 3
		return
	match screen:
		"title":
			if _auto_state == "continue": # 저장 후 종료 → 계속하기 경로 확인
				if _auto_step("c2", func(): _auto_shot("25_title_continue"); continue_run()):
					return
			elif _auto_state == "newrun":
				_auto_finish()
				return
			if _auto_state == "start":
				if _auto_frames < 8:
					return
				if _auto_step("t0", func(): _auto_shot("00_title"); (screens["title"] as PTitleScreen)._toggle_verify()):
					return
				if _auto_step("t1", func(): _auto_shot("00b_title_verify"); (screens["title"] as PTitleScreen)._toggle_verify(); new_run_flow()):
					return
			elif _auto_state == "lab":
				if _auto_step("l1", func(): quick_start_fight("spear", true)):
					return
		"pick_start":
			if _auto_state == "newrun":
				if _auto_step("r2", func(): _auto_shot("33_new_run_after_clear"); go_title()):
					return
				return
			if _auto_step("t2", func(): _auto_shot("01_pick_start"); use_bot = true; start_run("sword"); _auto_state = "base1"):
				return
		"base":
			_auto_reach("base")
			match _auto_state:
				"start", "base1":
					if _auto_step("b1", func(): _auto_shot("10_base"); tips._on_click("auto_skill")):
						return
					if _auto_step("b2", func(): _auto_shot("20_tooltip"); tips.close_all()):
						return
					_auto_state = "sortie"
					_auto_wait = 2
				"sortie":
					var picked := ""
					for c in PSortie.cards_for(run):
						if PSortie.can_start(run, c):
							picked = String(c.id)
							break
					if picked == "":
						end_day()
						_auto_wait = 4
					else:
						use_bot = true
						start_sortie_card(picked)
						_auto_state = "combat"
						_auto_wait = 2
				"tour":
					show("shop")
					_auto_wait = 4
				"days":
					if _auto_full and String(run.phase) == "prep" and PSortie.cards_for(run).any(func(c): return PSortie.can_start(run, c)):
						_auto_state = "sortie"
						_auto_wait = 2
						return
					if String(run.phase) == "prep":
						if _auto_step("d1", func(): (screens["base"] as PBaseScreen)._open_endday()):
							return
						if _auto_step("d2", func(): _auto_shot("18a_endday_confirm")):
							return
						end_day()
						_auto_wait = 4
					else:
						_auto_state = "bossprep"
				"continue": # 저장 → 종료(제목 화면) → 계속하기로 실제 복귀한 지점
					_auto_reach("save_continue")
					_auto_shot("26_base_continued")
					print("UI_SMOKE continued day=", int(run.day), " stage=", int(run.stage), " level=", int(run.growth.level), " gold=", int(run.gold))
					if _auto_full:
						_auto_state = "days"
						_auto_wait = 4
					else:
						_auto_state = "lab"
						go_title()
						_auto_wait = 4
				"bossprep":
					_auto_shot("18_bossprep")
					use_bot = true
					start_boss()
					_auto_state = "boss"
					_auto_wait = 2
				"endless": # 무한 모드(전체 진행 모드): 무한 거점 → 전투 1회(봇) → 정산 → 마치기 → 결과
					_auto_shot("34_endless_home")
					if String(run.phase) == "endless":
						use_bot = true
						endless_fight()
						_auto_state = "endless_combat"
						_auto_wait = 2
					else:
						_auto_state = "endless_after"
				"endless_after":
					_auto_shot("35_endless_after_fight")
					print("UI_SMOKE endless=", JSON.stringify(PEndless.summary(run)))
					endless_quit()
					_auto_state = "endless_done"
					_auto_wait = 4
				_:
					_auto_finish()
		"combat":
			_auto_reach("combat")
			if view.st != null and view.st.t >= 3.0 and _auto_state == "combat":
				_auto_shot("11_combat")
			if view.st != null and view.st.t >= 4.5 and _auto_state == "combat": # 일시정지·조작법·설정 화면도 한 번씩
				if _auto_step("p1", func(): set_pause(true)):
					return
				if _auto_step("p2", func(): _auto_shot("21_pause"); show_controls(true)):
					return
				if _auto_step("p3", func(): _auto_shot("22_controls"); show_controls(false); open_settings()):
					return
				if _auto_step("p4", func(): _auto_shot("23_settings"); settings_panel.close(); debug_panel.visible = true):
					return
				if _auto_step("p5", func(): _auto_shot("24_debug_run"); debug_panel.visible = false; open_build_detail()):
					return
				if _auto_step("p6", func(): _auto_shot("27_build_detail"); build_detail.close(); set_pause(false)):
					return
		"reward":
			_auto_shot("12_reward")
			after_reward()
			_auto_wait = 4
		"event":
			_auto_shot("12c_event")
			event_choice("leave")
			_auto_wait = 4
		"after":
			_auto_shot("12b_after")
			return_home()
			_auto_state = "endless_after" if _auto_state.begins_with("endless") else ("days" if _auto_done.has("17_stats") else "tour")
			_auto_wait = 4
		"defeat":
			_auto_shot("12d_defeat")
			after_defeat()
			_auto_state = "endless_done" if _auto_state.begins_with("endless") else ("days" if _auto_done.has("17_stats") else "tour")
			_auto_wait = 4
		"shop":
			_auto_shot("14_shop")
			show("forge")
			_auto_wait = 4
		"forge":
			_auto_shot("15_forge")
			show("equip")
			_auto_wait = 4
		"equip":
			_auto_shot("16_equip")
			show("stats")
			_auto_wait = 4
		"stats":
			_auto_shot("17_stats")
			go_base()
			_auto_state = "days"
			_auto_wait = 4
		"boss_result":
			if not run.is_empty() and (run.bossesDone as Array).size() >= 1:
				_auto_reach("gate%d" % mini(3, (run.bossesDone as Array).size()))
			_auto_shot("19_bossresult")
			if int(run.get("bossRetries", 0)) >= 4: # 같은 관문에서 봇이 계속 지면 무한 재도전 대신 종료(관찰 기록)
				print("UI_SMOKE boss_stuck boss=", String(PRun.next_boss(run).get("id", "?")), " retries=", int(run.bossRetries), " day=", int(run.day), " level=", int(run.growth.level))
				_auto_finish()
				return
			if _auto_step("c1", func(): go_base(); save_run(); go_title(); _auto_state = "continue"):
				return
			go_base() # 2·3번째 관문(전체 진행 모드): 거점으로 돌아가 다음 날 계속
			_auto_state = "days"
			_auto_wait = 4
		"run_result":
			if _auto_state != "endless_done":
				_auto_reach("run_result") # 회차 결과 화면(10일차 최종 보스 뒤)
				# 마지막 관문은 관문 결과 화면을 거치지 않고 곧바로 회차 결과로 간다.
				# 넘은 관문 수를 여기서 다시 확인해 표시한다
				if not run.is_empty():
					for i in (run.bossesDone as Array).size():
						_auto_reach("gate%d" % (i + 1))
			if _auto_state == "endless_done":
				_auto_shot("36_endless_result")
			_auto_shot("32_run_result")
			if _auto_full and _auto_state != "endless_done" and PEndless.can_start(run):
				if _auto_step("e1", func(): start_endless(); _auto_state = "endless"):
					return
			if _auto_step("r1", func(): new_run_flow(); _auto_state = "newrun"):
				return
		"result": # 검증 메뉴 빠른 전투(시작 기술 비교 → 관문 빌드 보스전)의 결과 패널
			if _auto_step("l2", func(): _auto_shot("30_lab_start_result"); quick_boss_fight("stage1", true)):
				return
			if _auto_step("l3", func(): _auto_shot("31_lab_boss_result")):
				return
			_auto_finish()

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
