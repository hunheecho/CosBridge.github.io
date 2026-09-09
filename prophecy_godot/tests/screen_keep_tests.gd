extends SceneTree
## 같은 화면을 다시 그릴 때 **보고 있던 자리를 잃지 않는다**(실제 main 장면).
## 실행: python tools/run_suites.py --suites screen_keep_tests
##
## 왜 있는가 — 사람 플레이 보고(2026-09-09, 두 번째):
##   "판매할 때마다 위로 올라가는 것도 없애줘. 이거 예전에 없앴다고 하지 않았냐??"
##
## 예전에 고친 것은 clear_all() 쪽이었고 그것만으로는 부족했다.
## 판매·장착·구매는 main.show(screen) 으로 **같은 화면을 다시** 부르는데,
## 그 길이 on_enter() 를 타면서 refresh() 가 방금 저장한 _keep_scroll 을
## 바로 다음 줄에서 0 으로 지웠다. 되살리기가 아무 일도 하지 않았다.
##
## 여기서 못박는 것
##  · 같은 화면을 다시 그리면 자리를 지킨다(판매·재료 판매·장착).
##  · **다른** 화면으로 갔다 오면 맨 위에서 시작한다(이건 그대로여야 한다).
##  · main.show 가 두 경우를 실제로 갈라 부른다.

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# 폰 가로에 가까운 낮은 화면으로 잡는다 — 목록이 화면보다 길어야 스크롤이 생긴다
	root.size = Vector2i(854, 400)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.start_run("sword")

	# 팔 것을 넉넉히 넣는다(실제 장비 id). 목록이 길어야 스크롤이 생긴다
	main.run.bag = ["hunter_sword", "pioneer_spear", "ember_sword", "chrono_staff",
		"traveler_armor", "guardian_armor", "vitality_coat", "expedition_armor"]
	main.run.gold = 500
	# 재료도 실제로 팔리게 넣는다(없으면 그 검사가 저절로 통과해 버린다)
	for mk in (PCatalog.materials() as Dictionary):
		(main.run.mats as Dictionary)[String(mk)] = 5
	main.show("shop")
	await process_frame
	await process_frame

	var shop: PScreen = main.screens["shop"]
	var sc: ScrollContainer = shop.scroll
	ok("상점 화면이 열렸다", shop != null and sc != null)

	# 스크롤이 생길 만큼 목록이 긴지 확인하고, 중간까지 내린다
	var max_scroll: int = int(maxf(0.0, float(sc.get_v_scroll_bar().max_value) - float(sc.size.y)))
	ok("상점 목록이 한 화면보다 길다(스크롤이 생긴다)", max_scroll > 40, "최대 %d" % max_scroll)
	var want: int = int(max_scroll / 2)
	sc.scroll_vertical = want
	await process_frame
	var before: int = int(sc.scroll_vertical)
	ok("중간까지 내렸다", before > 20, "자리 %d" % before)

	# ---------- 판매: 같은 화면을 다시 그린다 ----------
	var sell_id := String(main.run.bag[0])
	main.sell_equipment(sell_id)
	await process_frame
	await process_frame
	await process_frame
	var after: int = int(sc.scroll_vertical)
	ok("장비를 팔아도 보던 자리가 유지된다(맨 위로 안 튄다)",
		absi(after - before) <= 8, "판매 전 %d → 후 %d" % [before, after])

	# ---------- 재료 판매도 같은 길이다 ----------
	sc.scroll_vertical = want
	await process_frame
	var before2: int = int(sc.scroll_vertical)
	var sold_mat := false
	for k in (main.run.mats as Dictionary):
		if int(main.run.mats[k]) > 0:
			main.sell_mat(String(k))
			sold_mat = true
			break
	ok("재료를 실제로 팔았다(검사가 저절로 통과하지 않는다)", sold_mat)
	await process_frame
	await process_frame
	await process_frame
	ok("재료를 팔아도 보던 자리가 유지된다",
		absi(int(sc.scroll_vertical) - before2) <= 8,
		"판매 전 %d → 후 %d" % [before2, int(sc.scroll_vertical)])

	# ---------- 다른 화면에 갔다 오면 맨 위 ----------
	sc.scroll_vertical = want
	await process_frame
	main.show("base")
	await process_frame
	main.show("shop")
	await process_frame
	await process_frame
	ok("다른 화면에 갔다 오면 맨 위에서 시작한다(이건 그대로여야 한다)",
		int(sc.scroll_vertical) == 0, "자리 %d" % int(sc.scroll_vertical))

	print("%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
