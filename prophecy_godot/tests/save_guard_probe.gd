extends SceneTree
## **저장 보호 ②(격리되지 않은 저장 자리)를 실제로 만들어 보는 작은 몸통.**
## 혼자 돌리는 검사가 아니다 — tests/save_guard_tests.gd 가 **가짜 APPDATA**를 붙여
## 이 스크립트를 별개의 프로세스로 띄운다. 그 프로세스의 user:// 는 경로에
## userdata__ 도 prophecy_test_runs 도 없는 자리라, PSave.write_blocked()가 막아야 한다.
##
## 왜 별개의 프로세스인가: user:// 는 프로세스가 시작할 때 정해진다. 돌고 있는 검사 안에서는
## 그 자리를 바꿀 수 없고, 바꿀 수 있다면 그것이 곧 사고다.
##
## 여기서는 **판정하지 않는다.** 값만 한 줄씩 찍고 끝낸다(PROBE_*). 판정과 파일 내용 비교는 부르는 쪽이 한다.
## 자료는 정상으로 서 있는 상태다 — 그래서 막히는 이유는 오직 '격리되지 않았다' 하나여야 한다.

func _init() -> void:
	print("PROBE_USER_DIR=", OS.get_user_data_dir())
	print("PROBE_DATA_READY=", PCatalog.data_ready())
	print("PROBE_TEST_SCRIPT=", PSave.running_test_script())
	# 사유 문자열은 프로세스 밖으로 나가며 창의 글자표에 부딪혀 깨질 수 있다.
	# 그래서 **판정에 쓸 값은 여기서(글자가 멀쩡한 자리에서) 영문 표로 바꿔 내보낸다.**
	var blocked := PSave.write_blocked()
	var kind := "none"
	if blocked != "":
		if blocked.find("자료가 서 있지 않다") >= 0:
			kind = "data"      # ① 자료 미준비
		elif blocked.find("격리돼 있지 않다") >= 0:
			kind = "isolation" # ② 저장 자리 미격리
		else:
			kind = "other"
	print("PROBE_BLOCK_KIND=", kind)
	print("PROBE_BLOCK_LEN=", blocked.length())
	print("PROBE_BLOCKED=", blocked)
	print("PROBE_EXISTS_BEFORE=", PSave.exists())
	var before := PackedByteArray()
	if FileAccess.file_exists(PSave.SAVE_PATH):
		before = FileAccess.get_file_as_bytes(PSave.SAVE_PATH)
	print("PROBE_SHA_BEFORE=", before.get_string_from_utf8().sha256_text() if before.size() > 0 else "-")
	var run := PRun.new_run(7, "sword")
	run.gold = 12345
	print("PROBE_SAVE_RESULT=", PSave.save(run))
	PSave.clear()
	print("PROBE_EXISTS_AFTER=", PSave.exists())
	print("PROBE_TMP_LEFT=", FileAccess.file_exists(PSave.TMP_PATH))
	var after := PackedByteArray()
	if FileAccess.file_exists(PSave.SAVE_PATH):
		after = FileAccess.get_file_as_bytes(PSave.SAVE_PATH)
	print("PROBE_SHA_AFTER=", after.get_string_from_utf8().sha256_text() if after.size() > 0 else "-")
	print("PROBE_DONE")
	quit(0)
