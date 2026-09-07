extends Node
## 화면 라우터 + 회차 흐름 연결(HTML main.js 이식). 화면(scripts/game/screens/*)은 표시와 버튼만 맡고, 규칙은 PRun/PSortie/PFlow/PGrowth/PEvents가 결정한다.
## 화면: title · pick_start · base(거점/최종 준비) · shop · equip · forge · stats · log · combat · reward · after · event · defeat · boss_result · run_result
## 오버레이: 3택(PChoiceOverlay, 열려 있으면 다른 입력 차단·전투 정지) · 일시정지 · 조작법 · 설정 · 용어 툴팁(PGlossaryTip, 고정 시 전투 정지) · F3 검증 패널
## 검증 경로: 기준 전투(첫 전투, 0.3.1 D33)는 view.start(seed, bot) 그대로. PROPHECY_CAPTURE / PROPHECY_MOVIE / PROPHECY_DODGE_DEMO 는 그 경로를 쓴다.
## PROPHECY_UI_SMOKE=<폴더>: 새 회차 → 거점 → 출격(봇) → 전투 → 승리 뒤 화면 → 상점·대장간·장비·통계 → 하루 종료 → 관문 → 보스전 → 결과까지 자동 진행하며 PNG 저장 후 종료.

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
	touch = PTouchControls.new()
	hud.add_child(touch) # HUD와 같이 전투 중에만 보인다
	touch.bind(view, view.router)
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()
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
	if OS.get_environment("PROPHECY_UI_SMOKE") != "":
		_auto_dir = OS.get_environment("PROPHECY_UI_SMOKE")
		_auto_full = OS.get_environment("PROPHECY_UI_FULL") != "" # 최종 보스·회차 결과·새 회차까지 봇으로 계속
		_auto_stop = OS.get_environment("PROPHECY_UI_STOP")
		if OS.get_environment("PROPHECY_UI_SPEED") != "":
			view.time_scale = clampf(float(OS.get_environment("PROPHECY_UI_SPEED")), 1.0, 6.0)
		_auto = true
		_auto_snap = DisplayServer.get_name() != "headless" # 헤드리스는 PNG 없이 단계만 출력
		_auto_quit = true

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
	if not combat:
		pause_panel.visible = false
		controls_panel.visible = false
	result_panel.visible = name == "result"
	if screens.has(name):
		(screens[name] as PScreen).on_enter()
	if _auto:
		print("UI_SMOKE screen=", name)

func go_title() -> void:
	fight_kind = "first"
	view.running = false
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
	show("run_result" if String(run.phase) == "cleared" else "base")
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
	run = PRun.new_run(seed_use, weapon_id, "", { "density_set": String(new_run_opts.get("density_set", "")), "profile": profile, "eligible": true })
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

func rest() -> void:
	if PRun.rest(run):
		save_run()
	show("base")

func end_day() -> void:
	if PRun.end_day(run):
		save_run()
	go_base()

func start_boss() -> void:
	var s := PRun.start_boss(run)
	if s.is_empty():
		message("보스 준비 상태가 아닙니다")
		return
	sortie = s
	save_run() # 보스 직전 상태 저장
	start_encounter()

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

func forge_upgrade() -> void:
	PRun.forge_upgrade(run)
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
func open_choice(off: Variant) -> void:
	if off == null or typeof(off) != TYPE_DICTIONARY:
		return
	choice.open(run, off)
	if screen == "combat":
		view.set_paused(true)

func close_choice() -> void:
	choice.close()
	if screen == "combat" and not pause_panel.visible and not glossary_paused:
		view.set_paused(false)

## 전투 중 레벨업: 미처리 선택이 있으면 하나씩 제시
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
		view.st.rebuild(PBuild.derive(run))
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

func start_encounter() -> void:
	var st: CombatState
	if String(sortie.regionId) == "boss":
		st = PFlow.make_boss_encounter(run, sortie)
	else:
		st = PFlow.make_encounter(run, sortie)
	fight_kind = "run"
	save_run() # 전투 시작 체크포인트(F1): pendingSortie=null 상태로 저장 → 전투 중 종료 시 시간은 지불·성장 유지·미정산 전리품 상실·거점 복구(GAME_SPEC §전투 도중 종료)
	_view_start(st, PBot.new("balanced") if use_bot else null)
	choice.close()
	tips.close_all()
	show("combat")
	_refresh_combat_texts()

## 기준 전투(첫 전투, 0.3.1 D33): 검증 메뉴·캡처·영상·회피 시연이 쓰는 경로
func start_fight(bot: bool) -> void:
	use_bot = bot
	fight_kind = "first"
	view.start(seed_v, bot)
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
	_view_start(st, PBot.new("balanced") if bot else null)
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
	_view_start(st, PBot.new("balanced") if bot else null)
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
			last_profile_award = _award_profile("boss", { "st": st })
			save_run()
			sortie = {}
			show("run_result" if String(run.phase) == "cleared" else "boss_result")
		else:
			PFlow.settle_boss_defeat(run, st)
			save_run()
			sortie = {}
			show("boss_result")
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
	view.set_paused(v or choice.is_open() or glossary_paused)
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
		if not pause_panel.visible and not choice.is_open():
			view.set_paused(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
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

# ---------- HUD ----------
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
	var obj_l: Label = $UI/HUD/Objective
	if st.mode == "boss":
		obj_l.text = "보스전 · 소환 %d · %.1f초" % [PBoss.summoned_alive(st), st.t]
	elif not st.obj.is_empty():
		var h := PObjectives.hud(st)
		if h.is_empty():
			obj_l.text = "%.1f초" % st.t
		else:
			obj_l.text = "%s · %s%s · %.1f초" % [String(h.title), String(h.line), (" · " + String(h.risk)) if String(h.risk) != "" else "", st.t]
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
		for n in ["HP", "Shield", "HPText", "Dodge", "DodgeText", "Q", "QText", "E", "EText", "Objective", "Demo", "Settings"]:
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
	if touch != null:
		touch.layout(safe)

func _cfg_text(st: CombatState) -> String:
	if st.cfg.has("weapon"):
		return Game.settings_text(st.cfg)
	return _settings_line(st) + " · 원본 " + Game.HTML_SOURCE

func _process(_dt: float) -> void:
	if _demo_mode:
		_demo_tick(_dt)
	if _capture_mode:
		_capture_tick()
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

## 한 번만 실행하는 자동 진행 단계(실행했으면 true, 다음 틱까지 잠깐 기다린다)
func _auto_step(key: String, action: Callable) -> bool:
	if _auto_done.has(key):
		return false
	_auto_done[key] = true
	action.call()
	_auto_wait = 3
	return true

func _auto_shot(name: String) -> void:
	if _auto_done.has(name):
		return
	_auto_done[name] = true
	if _auto_snap:
		_snap_to(_auto_dir, name)
	if _auto_stop != "" and name == _auto_stop:
		_auto_wait = 1000000
		call_deferred("_auto_finish")
	print("UI_SMOKE step=", name, " screen=", screen, " state=", _auto_state, " day=", (int(run.day) if not run.is_empty() else 0), " phase=", (String(run.phase) if not run.is_empty() else "-"))

func _auto_finish() -> void:
	print("UI_SMOKE done state=", _auto_state, " run=", JSON.stringify({ "day": int(run.day), "phase": String(run.phase), "level": int(run.growth.level), "gold": int(run.gold), "stage": int(run.stage), "bossesDone": run.bossesDone, "retries": int(run.bossRetries) }) if not run.is_empty() else "{}", " summary=", JSON.stringify(last_summary))
	_auto = false
	if _auto_quit:
		get_tree().quit()

func _auto_tick() -> void:
	_auto_frames += 1
	if _auto_frames > 60 * 60 * 40: # 40분 안전장치
		print("UI_SMOKE timeout state=", _auto_state, " screen=", screen)
		_auto_finish()
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
			_on_pick(String(cs[0].key))
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
				"continue":
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
				_:
					_auto_finish()
		"combat":
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
				if _auto_step("p5", func(): _auto_shot("24_debug_run"); debug_panel.visible = false; set_pause(false)):
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
			_auto_state = "days" if _auto_done.has("17_stats") else "tour"
			_auto_wait = 4
		"defeat":
			_auto_shot("12d_defeat")
			after_defeat()
			_auto_state = "days" if _auto_done.has("17_stats") else "tour"
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
			_auto_shot("19_bossresult")
			if _auto_step("c1", func(): go_base(); save_run(); go_title(); _auto_state = "continue"):
				return
			go_base() # 2·3번째 관문(전체 진행 모드): 거점으로 돌아가 다음 날 계속
			_auto_state = "days"
			_auto_wait = 4
		"run_result":
			_auto_shot("32_run_result")
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
