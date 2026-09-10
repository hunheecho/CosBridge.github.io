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
## 두 경우를 **각각** 만들어 확인한다(사용자 지적 2026-09-10:
##   "자료 미준비 때문에 막히는 경우와, 자료는 정상인데 검사 저장 위치가 미격리여서 막히는 경우를
##    각각 확인해라. 두 번째는 **가짜 사용자 저장 위치**에서 구성해라.
##    원본 사용자 파일에 접근하지 않고도 저장·삭제 거부를 검증해야 한다."):
##   ① 자료 미준비  — 이 프로세스 안에서 자료 캐시를 잠깐 비워 만든다([3]~[6])
##   ② 미격리       — **가짜 APPDATA**를 붙인 별개의 프로세스(tests/save_guard_probe.gd)를 띄워 만든다([7])
##      그 폴더에 **가짜 저장 파일을 미리 넣어 두고**, 거부 뒤 그 파일이 **한 바이트도 안 바뀌었는지
##      내용으로** 비교한다. 수정 시각만 보고 보존을 단정하지 않는다(내용이 같은지가 증거다).
##      원본 사람 저장은 읽지도 쓰지도 않는다 — 손대는 것은 우리가 만든 임시 폴더뿐이다.
## 보호를 **빼 보는** 방향(고장 주입)은 tools/mutation_check.py 가 격리된 사본에서 확인한다.

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

	sec7_unisolated()
	sec8_catalog_fail_keeps_equipment()

	print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)

# ---------- [7] ② 미격리 — 가짜 APPDATA에서 실제로 막히는 장면 ----------
## 이 프로세스의 user:// 는 바꿀 수 없다(시작할 때 정해진다). 그래서 **별개의 프로세스**를 띄운다:
## APPDATA·LOCALAPPDATA 를 우리가 만든 임시 폴더로 바꾸면 그 프로세스의 user:// 가 그 아래로 간다.
## 그 경로에는 userdata__ 도 prophecy_test_runs 도 없으므로 PSave.write_blocked()가 막아야 한다.
func sec7_unisolated() -> void:
	print("\n[7] ② 자료는 정상인데 **저장 자리가 격리돼 있지 않은** 경우 — 가짜 APPDATA에서 만든다")
	var tmp := OS.get_environment("TEMP")
	if tmp == "":
		tmp = OS.get_environment("TMP")
	if tmp == "":
		ok("가짜 저장 자리를 놓을 임시 폴더를 찾았다(이 검사의 전제)", false, "TEMP·TMP 둘 다 비어 있다")
		return
	var fake_root := tmp.replace("\\", "/").path_join("pg_fake_home_%d" % OS.get_process_id())
	ok("가짜 APPDATA 경로에 격리 표시가 **없다**(그래야 막히는 장면이 된다)",
		fake_root.find("userdata__") < 0 and fake_root.find("prophecy_test_runs") < 0, fake_root)
	if fake_root.find("userdata__") >= 0 or fake_root.find("prophecy_test_runs") >= 0:
		return
	# 이 프로세스의 user:// 가 APPDATA 아래 어디에 붙는지 그대로 흉내 낸다(엔진이 정하는 꼬리를 그대로 쓴다)
	var my_appdata := OS.get_environment("APPDATA").replace("\\", "/")
	var my_user := OS.get_user_data_dir().replace("\\", "/")
	if my_appdata == "" or not my_user.begins_with(my_appdata):
		ok("지금 실행의 user:// 가 APPDATA 아래에 있다(이 검사의 전제)", false,
			"appdata=%s user=%s" % [my_appdata, my_user])
		return
	var tail := my_user.substr(my_appdata.length())
	var fake_user := fake_root + tail
	DirAccess.make_dir_recursive_absolute(fake_user)
	# **가짜 사람 저장 파일**을 미리 넣어 둔다. 거부 뒤 이 내용이 한 바이트도 바뀌면 안 된다
	var fake_path := fake_user.path_join("prophecy_save_v1.json")
	var planted := '{"schema":"prophecy_save/1","saved_at":1757400000,"run":{"gold":4242,"day":3,"표시":"사람이 하던 회차"}}'
	var wf := FileAccess.open(fake_path, FileAccess.WRITE)
	if wf == null:
		ok("가짜 저장 파일을 만들었다(이 검사의 전제)", false, fake_path)
		return
	wf.store_string(planted)
	wf.close()
	var planted_bytes := FileAccess.get_file_as_bytes(fake_path)
	var planted_sha := planted.sha256_text()
	ok("가짜 저장 파일을 심었다 — %d바이트" % planted_bytes.size(), planted_bytes.size() > 0, fake_path)

	var prev_appdata := OS.get_environment("APPDATA")
	var prev_local := OS.get_environment("LOCALAPPDATA")
	OS.set_environment("APPDATA", fake_root.replace("/", "\\"))
	OS.set_environment("LOCALAPPDATA", fake_root.replace("/", "\\"))
	var out: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/save_guard_probe.gd"]
	var rc := OS.execute(OS.get_executable_path(), args, out, true)
	OS.set_environment("APPDATA", prev_appdata)
	OS.set_environment("LOCALAPPDATA", prev_local)
	var text := ""
	for line in out:
		text += String(line)
	var v := _probe_values(text)
	print("---- 가짜 APPDATA에서 돌린 프로세스가 남긴 값 ----")
	for k in v:
		print("  %s = %s" % [String(k), String(v[k])])
	print("---- 끝(종료 코드 %d) ----" % rc)
	ok("가짜 자리에서 프로세스가 실제로 돌았다", v.has("PROBE_DONE") or v.has("PROBE_BLOCKED"),
		text.substr(maxi(0, text.length() - 400)))
	ok("그 프로세스의 user:// 가 우리가 만든 가짜 폴더 안이다(사람의 저장 자리가 아니다)",
		String(v.get("PROBE_USER_DIR", "")).replace("\\", "/").begins_with(fake_root),
		String(v.get("PROBE_USER_DIR", "없음")))
	ok("그 프로세스에서는 **자료가 정상으로 서 있었다**(막힌 이유가 ①이 아니다)",
		String(v.get("PROBE_DATA_READY", "")) == "true", String(v.get("PROBE_DATA_READY", "없음")))
	ok("검사·도구 스크립트로 인식됐다", String(v.get("PROBE_TEST_SCRIPT", "")) == "true",
		String(v.get("PROBE_TEST_SCRIPT", "없음")))
	# 사유 문자열 자체는 프로세스 밖으로 나오며 창의 글자표에 부딪혀 깨진다(위 출력이 그렇다).
	# 그래서 **판정은 그 프로세스가 안에서 정한 영문 표(PROBE_BLOCK_KIND)로** 한다.
	ok("관문이 막았다(사유가 비어 있지 않다) — %s자" % String(v.get("PROBE_BLOCK_LEN", "?")),
		int(String(v.get("PROBE_BLOCK_LEN", "0"))) > 0)
	ok("막은 사유가 ①자료 미준비가 아니라 **②저장 자리 미격리**다",
		String(v.get("PROBE_BLOCK_KIND", "")) == "isolation",
		String(v.get("PROBE_BLOCK_KIND", "없음")))
	ok("save()가 거짓을 돌려줬다(조용히 성공하지 않았다)",
		String(v.get("PROBE_SAVE_RESULT", "")) == "false", String(v.get("PROBE_SAVE_RESULT", "없음")))
	ok("clear() 뒤에도 그 자리 저장 파일이 그대로 있다(지우기도 같은 관문을 지난다)",
		String(v.get("PROBE_EXISTS_AFTER", "")) == "true", String(v.get("PROBE_EXISTS_AFTER", "없음")))
	ok("거부된 저장의 임시 파일도 남지 않았다",
		String(v.get("PROBE_TMP_LEFT", "")) == "false", String(v.get("PROBE_TMP_LEFT", "없음")))
	# **내용으로** 비교한다. 수정 시각은 증거로 쓰지 않는다
	var now_bytes := FileAccess.get_file_as_bytes(fake_path)
	var now_sha := now_bytes.get_string_from_utf8().sha256_text()
	ok("심어 둔 저장 파일이 **한 바이트도 바뀌지 않았다**(내용 비교 — 수정 시각이 아니다)",
		now_bytes == planted_bytes and now_sha == planted_sha,
		"%d바이트 %s → %d바이트 %s" % [planted_bytes.size(), planted_sha.substr(0, 12),
			now_bytes.size(), now_sha.substr(0, 12)])
	ok("그 프로세스가 스스로 잰 해시도 앞뒤가 같다(우리 비교와 따로 확인)",
		String(v.get("PROBE_SHA_BEFORE", "-")) == String(v.get("PROBE_SHA_AFTER", "="))
		and String(v.get("PROBE_SHA_BEFORE", "-")) == planted_sha,
		"%s / %s" % [String(v.get("PROBE_SHA_BEFORE", "없음")).substr(0, 12),
			String(v.get("PROBE_SHA_AFTER", "없음")).substr(0, 12)])
	_rm_tree(fake_root)

func _probe_values(text: String) -> Dictionary:
	var out := {}
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if not line.begins_with("PROBE_"):
			continue
		var i := line.find("=")
		if i < 0:
			out[line] = ""
			continue
		out[line.substr(0, i)] = line.substr(i + 1)
	return out

func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			if d.current_is_dir():
				_rm_tree(path.path_join(name))
			else:
				DirAccess.remove_absolute(path.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)

# ---------- [8] 자료 적재 실패 때 멀쩡한 장비를 지우지 않는다 ----------
## 사용자 지시: "자료 적재 실패 때 정상 장비를 미정의로 오판해 삭제하지 않는지 값으로 확인해라."
## 여기서는 **파일에 저장했다가 실제로 PSave.load()로 되읽는** 길에서 본다
## (규칙 함수 하나를 직접 부르는 확인은 tests/save_repair_tests.gd 가 따로 한다).
func sec8_catalog_fail_keeps_equipment() -> void:
	print("\n[8] 자료를 못 읽은 상태로 **불러와도** 멀쩡한 장비를 지우지 않는다")
	var known := ""
	for id in PCatalog.equipment():
		known = String(id)
		break
	ok("자료에서 실제 장비 id 를 찾았다(이 검사의 전제)", known != "", known)
	if known == "":
		return
	var run := PRun.new_run(4, "sword")
	var uid := PRun.equip_new_uid(run, known)
	var spare := PRun.equip_new_uid(run, known) # 가방에 남겨 둘 같은 종류의 다른 개체
	(run.bag as Array).append(uid)
	(run.bag as Array).append(spare)
	PRun.equip_item(run, uid) # 착용하면 그 개체는 가방에서 칸으로 옮겨 간다
	var slot := String(PCatalog.equipment_def(known).slot)
	ok("자료가 서 있는 동안 저장했다(파일이 정상이다)", PSave.save(run) and PSave.exists(),
		"%s 칸 %s" % [uid, slot])
	var keep = blank_data()
	var back := PSave.load()
	restore_data(keep)
	ok("자료를 못 읽어도 불러오기가 회차를 돌려준다", not back.is_empty())
	ok("착용 장비가 '없는 장비'로 오판되어 지워지지 않았다",
		String(back.get("equipment", {}).get(slot, "")) == uid,
		str(back.get("equipment", {})))
	ok("가방에 남아 있던 장비도 그대로다", (back.get("bag", []) as Array).has(spare),
		str(back.get("bag", [])))
	ok("'정리했다'는 기록도 남기지 않았다(지운 것이 없으므로)",
		not (back.get("log", []) as Array).any(func(l): return String(l).find("자료에 없는 장비") >= 0),
		str(back.get("log", [])))
	PSave.clear()
