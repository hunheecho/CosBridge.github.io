extends SceneTree
## **저장 보호 관문(PSave.write_blocked)이 실제로 막는지** 값으로 확인한다.
## 실행: python tools/run_suites.py --suites save_guard_tests --jobs 1
##
## 왜 있는가 — 사용자 지적(2026-09-10):
##   "저장 보호는 구현됐다는 보고와 검증 완료를 구분해야 해."
## 그때까지 이 관문을 부르는 검사가 **하나도 없었다**(tests/ 전수 검색). 구현만 있고 검사가 없었다.
##
## 무엇을 막는 관문인가
##   ① 자료가 안 섰을 때(PCatalog.data_ready()가 거짓) — 빈 회차로 멀쩡한 저장을 덮어쓰지 않는다.
##   ② 검사·도구 스크립트인데 저장 자리가 격리돼 있지 않을 때 — 사람의 저장을 건드리지 않는다.
##      (실제로 격리 없이 돌린 창 모드 실행이 사람이 하던 회차를 덮어쓴 사고가 있었다.)
##   저장과 지우기 **둘 다** 이 관문을 지난다. 한쪽만 막으면 반쪽이다.
##
## 여기서는 ①을 캐시를 갈아끼워 만들고, ②는 지금 실행이 실제로 격리돼 있는지로 확인한다.
## ②의 '격리 안 된 상태'는 이 자리에서 만들 수 없다 — 만들면 그게 곧 사고다.
## 그 방향은 tools/mutation_check.py 가 **격리된 사본에서** 보호를 빼 보고 확인한다.

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func save_bytes() -> PackedByteArray:
	if not FileAccess.file_exists(PSave.SAVE_PATH):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(PSave.SAVE_PATH)

## world 자료의 장비 목록을 잠깐 비운다(= 자료를 못 읽은 상태). 되돌릴 값을 돌려준다
func blank_data():
	var saved = PCatalog._cache.get("world", null)
	if typeof(saved) == TYPE_DICTIONARY:
		var b: Dictionary = (saved as Dictionary).duplicate(true)
		b["equipment"] = {}
		PCatalog._cache["world"] = b
	return saved

func restore_data(saved) -> void:
	if typeof(saved) == TYPE_DICTIONARY:
		PCatalog._cache["world"] = saved
	else:
		PCatalog.reset()

func _init() -> void:
	print("[1] 지금 이 실행이 '검사 스크립트'로 인식되고, 저장 자리가 격리돼 있다")
	ok("검사·도구 스크립트로 인식된다", PSave.running_test_script(),
		str(OS.get_cmdline_args()))
	var dir := ProjectSettings.globalize_path("user://")
	ok("저장 자리가 격리돼 있다(공용 실행기가 붙인 자리)",
		dir.find("userdata__") >= 0 or dir.find("prophecy_test_runs") >= 0, dir)
	ok("그래서 관문이 열려 있다", PSave.write_blocked() == "", PSave.write_blocked())

	print("\n[2] 정상 상태에서는 실제로 저장된다")
	var run := PRun.new_run(3, "sword")
	run.gold = 777
	ok("저장이 됐다", PSave.save(run))
	ok("파일이 생겼다", PSave.exists())
	var good := save_bytes()
	ok("파일에 내용이 있다", good.size() > 0, "%d바이트" % good.size())

	print("\n[3] 자료가 안 서면 저장을 거부하고 **기존 파일을 건드리지 않는다**")
	var keep = blank_data()
	var reason := PSave.write_blocked()
	ok("관문이 사유를 돌려준다", reason != "", reason)
	ok("자료 미준비를 사유로 든다", reason.find("자료가 서 있지 않다") >= 0, reason)
	var run2 := PRun.new_run(9, "spear")
	run2.gold = 1
	ok("save()가 거짓을 돌려준다(조용히 성공하지 않는다)", not PSave.save(run2))
	ok("기존 저장 파일이 **한 바이트도 바뀌지 않았다**", save_bytes() == good,
		"%d → %d바이트" % [good.size(), save_bytes().size()])

	print("\n[4] 지우기도 같은 관문을 지난다(저장만 막으면 반쪽이다)")
	PSave.clear()
	ok("자료가 안 선 상태에서는 저장을 지우지도 않는다", PSave.exists() and save_bytes() == good)

	print("\n[5] 임시 파일도 남기지 않는다")
	ok("거부된 저장의 임시 파일이 남아 있지 않다",
		not FileAccess.file_exists(PSave.TMP_PATH), PSave.TMP_PATH)

	print("\n[6] 자료가 돌아오면 관문도 다시 열린다(영구히 잠기지 않는다)")
	restore_data(keep)
	ok("관문이 다시 열렸다", PSave.write_blocked() == "", PSave.write_blocked())
	var run3 := PRun.new_run(5, "bow")
	run3.gold = 4242
	ok("다시 저장된다", PSave.save(run3))
	var back := PSave.load()
	ok("방금 저장한 회차가 돌아온다", not back.is_empty() and int(back.gold) == 4242,
		str(back.get("gold", "없음")))
	PSave.clear()
	ok("관문이 열려 있을 때는 지우기가 실제로 지운다", not PSave.exists())

	print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
