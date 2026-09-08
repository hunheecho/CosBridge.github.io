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

func _find_button(node: Node, needle: String) -> Button:
	if node is Button and String((node as Button).text).find(needle) >= 0:
		return node as Button
	for c in node.get_children():
		var b := _find_button(c, needle)
		if b != null:
			return b
	return null

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
	# 주무기·보조 분리: 시작 선택은 주무기만이다. 옛 구조에서 시작 자동기술로 해금해 둔 회전 칼날은
	# 여기서 빠지고 회차 중 보조 후보로 나온다(프로필 해금 자료는 지우지 않는다)
	ok("시작 선택 화면(trial Lv1): 시작 가능 2장(검·창 — 회전 칼날은 보조로 이동), 특성 요약에 근거리 훈련, 검 개조 후보 2개만", main.screen == "pick_start" and _count_text(ps, "이 자동기술로 시작") == 2 and _count_text(ps, "근거리 훈련") >= 1 and _count_text(ps, "교차 검격, 날아가는 검광") == 1 and _count_text(ps, "잔류 검흔") == 0, "화면=%s 시작버튼=%d 특성=%d 개조표시=%d 잔류검흔=%d" % [main.screen, _count_text(ps, "이 자동기술로 시작"), _count_text(ps, "근거리 훈련"), _count_text(ps, "교차 검격, 날아가는 검광"), _count_text(ps, "잔류 검흔")])
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
	# 가독성(사람 플레이 뒤 요구 2026-09-08): 계산식·반복 안내는 기본 화면이 아니라 '설명·계산식'에 둔다
	var fbtn := _find_button(forge, "설명·계산식")
	ok("대장간 기본 화면에 가격 계산식이 없고, 펼치는 버튼이 따로 있다", fbtn != null and _count_text(forge, "가격 계산식") == 0)
	if fbtn != null:
		fbtn.pressed.emit()
		await process_frame
		ok("펼치면 가격 계산식이 나온다", _count_text(main.screens["forge"], "가격 계산식") == 1)
		var fbtn2 := _find_button(main.screens["forge"], "설명·계산식 닫기")
		if fbtn2 != null:
			fbtn2.pressed.emit()
			await process_frame
	forge = main.screens["forge"]
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
	# 상점 카드: 이름 · 핵심 효과 · 비용 · 실제 변화량을 먼저, 구현 설명은 '상세 보기'로
	var shop: Node = main.screens["shop"]
	ok("상점 재고 카드가 장착 시 실제 변화량을 먼저 보여 준다", _count_text(shop, "장착하면") >= 1)
	var sbtn := _find_button(shop, "상세 보기")
	ok("상점 카드의 긴 설명·되팔 값·규칙은 '상세 보기'에 있다", sbtn != null and _count_text(shop, "되팔 때") == 0)
	if sbtn != null:
		sbtn.pressed.emit()
		await process_frame
		ok("상점 카드 상세를 펼치면 되팔 값·규칙이 나온다", _count_text(main.screens["shop"], "되팔 때") == 1)
	# 장비 화면: 해제/장착 시 실제 변화량
	ok("장비 화면이 장착·해제 시 바뀌는 값을 보여 준다", _count_text(main.screens["equip"], "해제하면") >= 1 or _count_text(main.screens["equip"], "장착하면") >= 1)
	# ---------- 상점: 유료 새로고침·잠금·준비물·회복약(2026-09-08) ----------
	main.run.gold = 2000
	main.show("shop")
	await process_frame
	var shop2: Node = main.screens["shop"]
	ok("상점에 재고 새로고침 값(60)·오늘 남은 횟수·초기화 시점이 보인다",
		_find_button(shop2, "재고 새로고침 (60)") != null and _count_text(shop2, "내일 아침") >= 1 and _count_text(shop2, "오늘 0/3회 사용") >= 1)
	ok("보존(잠금) 줄과 출격 준비물·회복약 진열이 보인다",
		_count_text(shop2, "보존(잠금) 최대 2칸") >= 1 and _count_text(shop2, "출격 준비물") >= 1 and _count_text(shop2, "회복약") >= 1)
	var rbtn := _find_button(shop2, "재고 새로고침 (60)")
	rbtn.pressed.emit()
	await process_frame
	ok("새로고침을 누르면 금화가 60 줄고 다음 값이 90으로 오른다",
		int(main.run.gold) == 1940 and _find_button(main.screens["shop"], "재고 새로고침 (90)") != null, "gold=%d" % int(main.run.gold))
	var pbtn := _find_button(main.screens["shop"], "준비물 구매")
	if pbtn != null:
		pbtn.pressed.emit()
		await process_frame
	ok("준비물·회복약을 사면 가방에 들어간다", (PConsumables.bag(main.run) as Array).size() >= 1, str(main.run.consumables))
	# 거점: 준비물 1칸(장착·해제는 소모가 아니다)
	main.run.consumables = ["guard_charm", "potion"]
	main.run.prepItem = null
	main.go_base()
	await process_frame
	var base2: Node = main.screens["base"]
	ok("거점에 출격 준비물 1칸과 회복약 사용 버튼이 있다(새 전투 단축키 없음)",
		_count_text(base2, "출격 준비물") >= 1 and _find_button(base2, "수호 부적") != null and _find_button(base2, "회복약 사용") != null)
	var sel := _find_button(base2, "수호 부적")
	sel.pressed.emit()
	await process_frame
	ok("준비물을 고르면 장착으로 표시되고 가방에서 빠지지 않는다(해제도 소모가 아니다)",
		PConsumables.armed(main.run) == "guard_charm" and PConsumables.count(main.run, "guard_charm") == 1
			and _find_button(main.screens["base"], "해제 (소모 없음)") != null)
	_find_button(main.screens["base"], "해제 (소모 없음)").pressed.emit()
	await process_frame
	ok("해제해도 가방·금화가 그대로다", PConsumables.armed(main.run) == "" and PConsumables.count(main.run, "guard_charm") == 1)
	# 전투 승리 → 보상 화면에 영구 기록 한 줄
	main.go_base()
	await process_frame
	main.start_sortie_card("d1c1")
	main.view.running = false
	main.view.st.status = "won"
	main.view.st.player.hp = 70.0
	main._on_finished(main.view.st.summary())
	await process_frame
	ok("승리 정산 뒤 보상 화면에 '탐험 기록: +0.7 (다음 회차부터 반영)'(10일 본편 2/3), 프로필 기록 2/3 저장", main.screen == "reward" and _count_text(main.screens["reward"], "탐험 기록: +0.7") == 1 and is_equal_approx(float(PProfile.load("trial").records), 2.0 / 3.0), "count=%d loaded=%s award=%s" % [_count_text(main.screens["reward"], "탐험 기록: +0.7"), str(PProfile.load("trial").get("records", null)), str(main.last_profile_award)])
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
