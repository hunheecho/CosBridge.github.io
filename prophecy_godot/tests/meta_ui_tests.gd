extends SceneTree
## 영구 성장 화면 계층 테스트(headless, 실제 main.tscn): 영구 성장 화면·특성 선택·프로필 전환·시작 선택(해금 반영)·대장간 제작 미리보기/확정·결과 화면 기록 줄.
## 실행: APPDATA를 별도 폴더로 두고 godot --headless --path prophecy_godot -s tests/meta_ui_tests.gd (user:// 저장·프로필을 쓴다). 화면은 버튼 콜백을 직접 부른다(사람 입력 아님).

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

func _count_text(node: Node, needle: String) -> int:
	var n := 0
	if node is RichTextLabel and String((node as RichTextLabel).text).find(needle) >= 0:
		n += 1
	if node is Button and String((node as Button).text).find(needle) >= 0:
		n += 1
	for c in node.get_children():
		n += _count_text(c, needle)
	return n

func _run() -> void:
	PProfile.use_path("user://prophecy_profile_ui_test_v1.json")
	PProfile.clear()
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	# main._ready는 기본 경로 프로필을 읽었으므로 시험 경로 프로필로 바꾼다(테스트 격리)
	main.profile = PProfile.load("trial")
	main.show_meta()
	await process_frame
	var meta: Node = main.screens["meta"]
	ok("영구 성장 화면: 프로필 종류·레벨·특성 4행·도감 표시", main.screen == "meta" and _count_text(meta, "영구 Lv 1") >= 1 and _count_text(meta, "공격 성향") >= 1 and _count_text(meta, "잠김") >= 5 and _count_text(meta, "시작 가능 3/7") >= 1)
	main.set_trait(1, "near")
	await process_frame
	ok("특성 선택(1행 근거리 훈련) → 저장·표시", PProfile.selected_traits(main.profile) == ["near"] and PProfile.selected_traits(PProfile.load("trial")) == ["near"] and _count_text(main.screens["meta"], "● 근거리 훈련") == 1)
	main.set_trait(5, "heal")
	ok("잠긴 5행 선택은 거부(Lv1)", PProfile.selected_traits(main.profile) == ["near"])
	main.set_profile_kind("legacy")
	await process_frame
	ok("프로필 전환 legacy: 활성 legacy, trial 특성은 파일에 그대로", String(main.profile.kind) == "legacy" and PProfile.active_kind() == "legacy" and PProfile.selected_traits(PProfile.load("trial")) == ["near"])
	main.set_profile_kind("trial")
	main.new_run_flow()
	await process_frame
	var ps: Node = main.screens["pick_start"]
	ok("시작 선택 화면(trial Lv1): 시작 가능 3장(검·창·칼날), 특성 요약에 근거리 훈련, 검 개조 후보 2개만", main.screen == "pick_start" and _count_text(ps, "이 자동기술로 시작") == 3 and _count_text(ps, "근거리 훈련") >= 1 and _count_text(ps, "교차 검격, 날아가는 검광") == 1 and _count_text(ps, "잔류 검흔") == 0)
	main.start_run("sword")
	await process_frame
	ok("새 회차: 특성 고정·해금 스냅샷·기록 대상, 프로필 runs 1", (main.run.traits as Array) == ["near"] and main.run.has("unlocks") and bool(main.run.profileEligible) and int(PProfile.load("trial").runs) == 1 and main.screen == "base")
	# 대장간 제작: 회차에 재료를 주입하고 제작법을 열어 미리보기 → 확정
	main.run.unlocks.recipes = ["moon_armor"]
	main.run.bag = ["guardian_armor"]
	main.run.mats.iron = 2
	main.run.mats.pelt = 1
	main.run.gold = 100
	main.show("forge")
	await process_frame
	var forge: Node = main.screens["forge"]
	ok("대장간 제작 칸: 월광 갑옷 미리보기 버튼, 잠긴 제작법 5개 조건 표시", _count_text(forge, "월광 갑옷") >= 1 and _count_text(forge, "미리보기") == 1 and _count_text(forge, "잠김:") == 1)
	forge._craft = "moon_armor"
	forge.refresh()
	await process_frame
	ok("미리보기: 소비 목록·확정/취소 버튼, 아직 소비 없음", _count_text(forge, "확정 후 장착") == 1 and _count_text(forge, "취소 (Esc)") == 1 and int(main.run.gold) == 100 and (main.run.bag as Array) == ["guardian_armor"])
	main.craft("moon_armor", true, true)
	await process_frame
	ok("확정 후 장착: 갑옷 슬롯 월광 갑옷, 금화 20, 재료 0, 저장 반영", main.run.equipment.armor == "moon_armor" and int(main.run.gold) == 20 and int(main.run.mats.iron) == 0 and PSave.load().equipment.armor == "moon_armor" and main.screen == "forge")
	main.show("equip")
	await process_frame
	main.show("shop")
	await process_frame
	ok("장비·상점 화면 표시(제작품 장착 상태)", _count_text(main.screens["equip"], "월광 갑옷") >= 1 and _count_text(main.screens["shop"], "월광 갑옷") >= 1)
	# 전투 승리 → 보상 화면에 영구 기록 한 줄
	main.go_base()
	await process_frame
	main.start_sortie_card("d1c1")
	main.view.running = false
	main.view.st.status = "won"
	main.view.st.player.hp = 70.0
	main._on_finished(main.view.st.summary())
	await process_frame
	ok("승리 정산 뒤 보상 화면에 '탐험 기록: +1 (다음 회차부터 반영)', 프로필 기록 1 저장", main.screen == "reward" and _count_text(main.screens["reward"], "탐험 기록: +1") == 1 and int(PProfile.load("trial").records) == 1, str(main.last_profile_award))
	main.view.running = false
	main.queue_free()
	await process_frame
	PSave.clear()
	PProfile.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
