extends SceneTree
## **게임 이름을 바꿔도 사용자의 저장 자리는 한 글자도 안 바뀐다**를 값으로 못 박는다.
## 실행: python tools/run_suites.py --suites name_tests --jobs 1
##
## 왜 있는가
##   Godot 의 `user://` 는 `application/config/name` 에서 파생된다.
##   이름만 바꾸면 저장 폴더가 함께 바뀌어 **사용자가 이미 하던 회차·프로필·처치 기록에 못 닿는다.**
##   그래서 project.godot 에서 저장 경로를 옛 이름으로 직접 못 박았다:
##       config/name="텐데이즈투둠스데이"
##       config/use_custom_user_dir=true
##       config/custom_user_dir_name="Godot/app_userdata/예언의 시간표 — Godot 첫 전투"
##   이 검사는 그 세 줄 중 **하나라도 지워지거나 새 이름으로 바뀌면 실패한다.**
##   특히 [4]의 `custom_user_dir_name` 은 옛 표시명이 아니라 **폴더 이름**이다. 고치지 마라 — docs/NAMING.md
##
## 사용자 원본 저장은 읽지도 쓰지도 않는다.
## 공용 실행기(tools/run_suites.py)가 APPDATA 를 바꿔치기해 만든 **격리된 자리**에서 새로 만들어 쓴다.
## [3]이 그 격리가 실제로 걸려 있는지를 먼저 확인하고, 걸려 있지 않으면 [5]는 아무것도 쓰지 않는다.

## 저장 폴더의 꼬리. **옛 이름 그대로다**(사용자 저장을 지키는 값)
const USER_DIR_TAIL := "Godot/app_userdata/예언의 시간표 — Godot 첫 전투"
const NEW_NAME := "텐데이즈투둠스데이"
const NEW_NAME_EN := "Ten Days to Doomsday"
const OLD_NAME := "예언의 시간표 — Godot 첫 전투"

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 윈도우에서 섞여 들어오는 역슬래시를 하나로 맞춘다(값 비교를 경로 표기에 맡기지 않는다)
func slash(p: String) -> String:
	return p.replace("\\", "/")

func game_const(key: String) -> String:
	var gs: GDScript = load("res://scripts/game/game.gd")
	return String(gs.get_script_constant_map().get(key, ""))

func _init() -> void:
	print("[1] 표시명이 새 이름이다")
	var cfg_name := String(ProjectSettings.get_setting("application/config/name", ""))
	ok("project.godot 의 표시명이 새 이름이다", cfg_name == NEW_NAME, cfg_name)
	ok("창 제목이 될 값에 옛 이름이 남아 있지 않다", cfg_name.find("예언의 시간표") < 0, cfg_name)

	print("\n[2] 표시명의 정본은 한 자리다(화면은 그 자리를 거쳐서만 읽는다)")
	ok("game.gd 의 APP_NAME 이 새 이름이다", game_const("APP_NAME") == NEW_NAME, game_const("APP_NAME"))
	ok("game.gd 의 APP_NAME_EN 이 영어 표기다", game_const("APP_NAME_EN") == NEW_NAME_EN, game_const("APP_NAME_EN"))
	ok("PUi.app_name() 이 정본과 같은 값을 준다", PUi.app_name() == game_const("APP_NAME"), PUi.app_name())
	ok("PUi.app_name_en() 이 정본과 같은 값을 준다", PUi.app_name_en() == game_const("APP_NAME_EN"), PUi.app_name_en())
	ok("엔진 사본(project.godot)과 정본(game.gd)이 어긋나지 않는다", cfg_name == game_const("APP_NAME"),
		"%s / %s" % [cfg_name, game_const("APP_NAME")])

	print("\n[3] 그래도 저장 자리는 옛 이름 그대로다")
	var use_custom := bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	ok("저장 자리를 직접 못 박아 두었다(use_custom_user_dir)", use_custom, str(use_custom))
	var custom_dir := slash(String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")))
	ok("못 박은 값이 옛 이름 폴더다", custom_dir == USER_DIR_TAIL, custom_dir)
	var udir := slash(OS.get_user_data_dir())
	ok("실제 저장 자리가 옛 이름 폴더로 끝난다", udir.ends_with(USER_DIR_TAIL), udir)
	ok("저장 자리에 새 이름이 끼어들지 않았다", udir.find(NEW_NAME) < 0, udir)

	print("\n[4] 공용 실행기의 격리(APPDATA 바꿔치기)가 여전히 먹힌다")
	var here := slash(ProjectSettings.globalize_path("user://"))
	var isolated := here.find("userdata__") >= 0 or here.find("prophecy_test_runs") >= 0
	ok("저장 자리가 격리돼 있다(공용 실행기가 붙인 자리)", isolated, here)
	ok("검사·도구 스크립트로 인식된다", PSave.running_test_script(), str(OS.get_cmdline_args()))
	ok("그래서 저장 관문이 열려 있다", PSave.write_blocked() == "", PSave.write_blocked())
	ok("격리된 자리 **안에** 옛 이름 폴더가 들어 있다", isolated and here.find(OLD_NAME) >= 0, here)

	print("\n[5] 옛 이름 폴더에 저장한 회차·프로필·처치 기록이 그대로 살아 돌아온다")
	if not isolated:
		fail_n += 1
		print("FAIL 격리가 걸려 있지 않아 [5]를 하지 않았다 — 사람의 저장을 건드릴 수 있다: " + here)
		print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
		quit(1)
		return
	check_round_trip()

	print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)

## 저장 → (다시 읽기 = 이어하기) → 값이 살아 있는지. 세 갈래(회차·프로필·처치 기록)를 모두 본다
func check_round_trip() -> void:
	var run := PRun.new_run(20260910, "sword")
	run.gold = 4321
	run.day = 4
	ok("회차가 저장됐다", PSave.save(run))
	var save_at := slash(ProjectSettings.globalize_path(PSave.SAVE_PATH))
	ok("저장 파일이 옛 이름 폴더 안에 놓인다", save_at.find(USER_DIR_TAIL + "/") >= 0, save_at)
	ok("저장 파일 이름이 그대로다(prophecy_save_v1.json)", save_at.ends_with("/prophecy_save_v1.json"), save_at)

	var back := PSave.load()
	ok("이어하기로 같은 회차가 돌아온다", not back.is_empty() and int(back.gold) == 4321 and int(back.day) == 4,
		"금화 %s · %s일차" % [str(back.get("gold", "없음")), str(back.get("day", "없음"))])
	ok("시드도 그대로다", int(back.get("seed", 0)) == 20260910, str(back.get("seed", 0)))
	ok("제목 화면의 '계속하기' 줄을 만들 수 있다", PRun.schedule_short_of_save(back) != "",
		PRun.schedule_short_of_save(back))

	var prof := PProfile.new_profile("legacy")
	prof.records = 7.0
	prof.runs = 3
	ok("프로필이 저장됐다", PProfile.save(prof))
	var prof_at := slash(ProjectSettings.globalize_path(PProfile.profile_path()))
	ok("프로필 파일도 옛 이름 폴더 안에 놓인다", prof_at.find(USER_DIR_TAIL + "/") >= 0, prof_at)
	var prof_back := PProfile.load("legacy")
	ok("프로필의 탐험 기록이 살아 있다", is_equal_approx(float(prof_back.records), 7.0), str(prof_back.records))
	ok("프로필의 회차 수가 살아 있다", int(prof_back.runs) == 3, str(prof_back.runs))

	PSave.save_record({ "day": 10, "gold": 999, "seed": 20260910 })
	var recs := PSave.load_records()
	var first: Dictionary = recs.get("first_clear", {}) if typeof(recs.get("first_clear", null)) == TYPE_DICTIONARY else {}
	ok("처치 기록이 살아 있다", int(first.get("gold", 0)) == 999 and (recs.clears as Array).size() == 1,
		str(recs.get("first_clear", "없음")))
	var rec_at := slash(ProjectSettings.globalize_path(PSave.RECORDS_PATH))
	ok("처치 기록 파일도 옛 이름 폴더 안에 놓인다", rec_at.find(USER_DIR_TAIL + "/") >= 0, rec_at)

	# 격리된 자리라도 만든 것은 치운다(다음 실행이 남은 파일을 물려받지 않게)
	PSave.clear()
	PProfile.clear()
	ok("만들어 쓴 회차 저장을 치웠다", not PSave.exists())
