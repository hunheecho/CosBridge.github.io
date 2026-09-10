extends SceneTree
## **회차 판본(run_version)으로 이어하기 가부를 가른다**는 것을 값으로 확인한다.
## 실행: python tools/run_suites.py --suites save_version_tests --jobs 1
##
## 왜 있는가(사용자 확정 2026-09-10)
##   대규모 개편으로 장비·패시브 규칙이 바뀌었다. 이전 회차를 새 규칙으로 **이전하지 않기로** 정했다.
##   그래서 옛 회차는 이어하기를 막고 "대규모 업데이트로 새 회차를 시작해야 합니다"라고 안내한다.
##
## 이 검사가 못박는 것 — 말이 아니라 값으로
##   ① 가부는 **명시적인 판본**으로만 가른다. "자료에 없는 장비가 들어 있으니 옛 회차겠지" 같은
##      짐작으로 가르지 않는다 → [5]에서 **없는 장비가 든 새 판본 저장이 그대로 이어진다**.
##   ② 판이 달라도 **옛 저장 파일을 지우거나 이름을 바꾸지 않는다** → 앞뒤 해시가 같다.
##      (schema 를 올려 .corrupt 로 밀어내는 길을 쓰지 않은 이유가 여기 있다.)
##   ③ 프로필·처치 기록은 **손대지 않는다** → 앞뒤 해시가 같다.
##   ④ 제목 화면은 '계속하기'를 **감추지 않고** 눌리지 않게 두고, 사유를 글자로 보여 준다.
##   ⑤ 새 판본 회차는 저장→이어하기가 그대로 된다(개체 id·강화·기술 레벨·변형·창고·Q/E).
##
## 손대는 파일은 **이 실행의 격리된 user:// 안**뿐이다. 사람의 실제 저장 자리는 읽지도 쓰지도 않는다
## (공용 실행기 tools/run_suites.py 가 APPDATA·LOCALAPPDATA 를 실행 전용 폴더로 바꿔 준다).

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

# ---------- 파일 도구(내용 비교 — 수정 시각은 증거로 쓰지 않는다) ----------
func sha_of(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "(없음)"
	return FileAccess.get_file_as_bytes(path).get_string_from_utf8().sha256_text()

func bytes_of(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)

## 저장 자리에 **파일 내용을 직접** 심는다(정상 저장 경로를 거치지 않는다 — 옛 판본을 만들 유일한 길)
func plant(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

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

# ---------- 화면 훑기 ----------
## 보이는 층에서 글자 part 를 가진 Button(눌리든 안 눌리든). 없으면 null
func find_button(node: Node, part: String) -> Button:
	if node is Control and not (node as Control).is_visible_in_tree():
		return null
	if node is Button and String((node as Button).text).find(part) >= 0:
		return node as Button
	for ch in node.get_children():
		var f := find_button(ch, part)
		if f != null:
			return f
	return null

## 지금 **보이는** 글자 전부를 이어 붙인다(숨은 층은 세지 않는다)
func visible_text(node: Node) -> String:
	if node is Control and not (node as Control).is_visible_in_tree():
		return ""
	var s := ""
	if node is Label:
		s += String((node as Label).text) + "\n"
	elif node is RichTextLabel:
		s += String((node as RichTextLabel).text) + "\n"
	elif node is Button:
		s += String((node as Button).text) + "\n"
	for ch in node.get_children():
		s += visible_text(ch)
	return s

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[1] 전제 — 격리된 저장 자리에서, 자료가 서 있는 상태로 돈다")
	var dir := ProjectSettings.globalize_path("user://")
	ok("저장 자리가 격리돼 있다(사람의 저장을 건드리지 않는다)",
		dir.find("userdata__") >= 0 or dir.find("prophecy_test_runs") >= 0, dir)
	ok("자료가 서 있다", PCatalog.data_ready(), PCatalog.data_problem())
	ok("관문이 열려 있다(저장이 가능하다)", PSave.write_blocked() == "", PSave.write_blocked())
	ok("현재 회차 판본이 상수 한 자리에 있다", PSave.RUN_VERSION >= 2, "RUN_VERSION=%d" % PSave.RUN_VERSION)
	ok("판본을 적기 전 파일은 판본 %d 으로 본다" % PSave.LEGACY_RUN_VERSION,
		PSave.file_run_version({}) == PSave.LEGACY_RUN_VERSION and PSave.LEGACY_RUN_VERSION < PSave.RUN_VERSION,
		str(PSave.file_run_version({})))

	sec2_write_reads_version()
	sec3_old_file_blocked()
	sec4_profile_and_records_intact()
	sec5_unknown_equipment_is_not_the_test()
	sec6_roundtrip_keeps_everything()
	sec7_guard_still_works()
	sec8_checkpoint_does_not_touch_run()
	await sec9_title_screen()

	print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)

# ---------- [2] 판본을 어디에 적고 어디서 읽는가 ----------
func sec2_write_reads_version() -> void:
	print("\n[2] 저장하면 파일 맨 위에 run_version 이 적히고, 불러오기가 그 값을 읽는다")
	PSave.clear()
	var run := PRun.new_run(1234, "sword")
	run.gold = 321
	ok("새 회차가 저장됐다", PSave.save(run), PSave.write_blocked())
	var raw := FileAccess.get_file_as_string(PSave.SAVE_PATH)
	var doc = JSON.parse_string(raw)
	ok("파일이 사전으로 읽힌다", typeof(doc) == TYPE_DICTIONARY)
	ok("schema 는 예전 그대로다(겉모양을 바꾸지 않았다 — .corrupt 로 밀려나지 않게)",
		String((doc as Dictionary).get("schema", "")) == PSave.SCHEMA,
		String((doc as Dictionary).get("schema", "없음")))
	ok("파일에 run_version = %d 이 적혀 있다" % PSave.RUN_VERSION,
		PSave.file_run_version(doc) == PSave.RUN_VERSION, str((doc as Dictionary).get("run_version", "없음")))
	ok("run_version 은 회차 사전 **밖**에 있다(회차를 통째로 비교하는 기존 검사가 그대로 성립한다)",
		not ((doc as Dictionary).run as Dictionary).has("run_version"))
	var res := PSave.load_result()
	ok("불러오기 결과가 '정상'이다", String(res.status) == PSave.LOAD_OK, String(res.status))
	ok("결과가 파일 판본과 현재 판본을 함께 알려 준다",
		int(res.file_version) == PSave.RUN_VERSION and int(res.current_version) == PSave.RUN_VERSION,
		"파일 %d / 현재 %d" % [int(res.file_version), int(res.current_version)])
	ok("이어할 수 있다", PSave.continuable())
	ok("값도 그대로 돌아온다", int((res.run as Dictionary).get("gold", 0)) == 321,
		str((res.run as Dictionary).get("gold", "없음")))

	print("\n[2-2] 저장이 없으면 '없음'이다(판 불일치와 다른 사유로 구분된다)")
	PSave.clear()
	var none := PSave.load_result()
	ok("상태가 '없음'이다", String(none.status) == PSave.LOAD_NONE, String(none.status))
	ok("'없음'에는 판 불일치 문구를 붙이지 않는다", String(none.message) == "", String(none.message))
	ok("이어할 수 없다", not PSave.continuable())

# ---------- [3] 옛 판본 파일 — 막히고, 사유가 '판이 다르다'이고, 파일이 그대로 남는다 ----------
func sec3_old_file_blocked() -> void:
	print("\n[3] 옛 판본 저장 — 이어하기가 막히고 **파일은 그대로 남는다**")
	# 두 가지 옛 파일을 각각 만든다: ① run_version 이 아예 없는 파일 ② 낮은 판본을 적은 파일
	var cases := [
		["판본이 아예 없는 파일(판본을 적기 전의 저장)",
			'{"schema":"prophecy_save/1","saved_at":1757400000,"run":{"seed":777,"day":5,"gold":1234,"표시":"사람이 하던 옛 회차"}}'],
		["낮은 판본을 적은 파일(run_version=1)",
			'{"schema":"prophecy_save/1","saved_at":1757400001,"run_version":1,"run":{"seed":778,"day":6,"gold":99,"표시":"옛 판본 회차"}}'],
	]
	for c in cases:
		var title := String((c as Array)[0])
		var text := String((c as Array)[1])
		PSave.clear()
		ok("%s — 심었다" % title, plant(PSave.SAVE_PATH, text))
		var before_bytes := bytes_of(PSave.SAVE_PATH)
		var before_sha := sha_of(PSave.SAVE_PATH)
		print("     심은 파일 %d바이트 sha %s" % [before_bytes.size(), before_sha.substr(0, 12)])
		var res := PSave.load_result()
		ok("%s — 사유가 '판이 다르다'다" % title,
			String(res.status) == PSave.LOAD_VERSION, String(res.status))
		ok("%s — 사유 문구가 정본 그대로다" % title,
			String(res.message) == "대규모 업데이트로 새 회차를 시작해야 합니다"
			and String(res.message) == PSave.VERSION_MESSAGE, String(res.message))
		ok("%s — 파일 판본과 현재 판본을 값으로 알려 준다" % title,
			int(res.file_version) < PSave.RUN_VERSION and int(res.current_version) == PSave.RUN_VERSION,
			"파일 %d → 현재 %d" % [int(res.file_version), int(res.current_version)])
		ok("%s — 회차를 열어 주지 않는다" % title, (res.run as Dictionary).is_empty())
		ok("%s — 얇은 겉면 load() 도 빈 사전이다(기존 호출부가 그대로 안전하다)" % title,
			PSave.load().is_empty())
		ok("%s — continuable() 이 거짓이다" % title, not PSave.continuable())
		# **파일 보존** — 지우지도, 이름을 바꾸지도 않았다
		ok("%s — 저장 파일이 아직 그 자리에 있다" % title, FileAccess.file_exists(PSave.SAVE_PATH))
		var after_bytes := bytes_of(PSave.SAVE_PATH)
		var after_sha := sha_of(PSave.SAVE_PATH)
		ok("%s — **한 바이트도 바뀌지 않았다**(내용 비교)" % title,
			after_bytes == before_bytes and after_sha == before_sha,
			"%d바이트 %s → %d바이트 %s" % [before_bytes.size(), before_sha.substr(0, 12),
				after_bytes.size(), after_sha.substr(0, 12)])
		ok("%s — .corrupt 로 옮기지 않았다(schema 를 바꾸는 길을 쓰지 않은 이유다)" % title,
			not FileAccess.file_exists(PSave.CORRUPT_PATH), PSave.CORRUPT_PATH)
		ok("%s — 옆에 임시 파일을 만들지도 않았다" % title, not FileAccess.file_exists(PSave.TMP_PATH))
		# 여러 번 열어 봐도 그대로다(제목 화면은 새로 그릴 때마다 읽는다)
		PSave.load_result()
		PSave.load_result()
		ok("%s — 세 번 읽어도 내용이 같다(제목 화면은 그릴 때마다 읽는다)" % title,
			bytes_of(PSave.SAVE_PATH) == before_bytes)
		ok("%s — exists() 는 참이다(파일이 사라진 것이 아니다)" % title, PSave.exists())

	print("\n[3-2] 새 회차를 시작하면 그때 정상 경로로 덮인다(지우는 것이 아니라 덮는 것이다)")
	var fresh := PRun.new_run(4321, "spear")
	fresh.gold = 55
	ok("새 회차 저장이 됐다", PSave.save(fresh))
	var res2 := PSave.load_result()
	ok("이제 이어할 수 있다", String(res2.status) == PSave.LOAD_OK and int(res2.file_version) == PSave.RUN_VERSION,
		"%s / 판본 %d" % [String(res2.status), int(res2.file_version)])
	ok("덮인 회차가 새 회차다", int((res2.run as Dictionary).get("gold", 0)) == 55)
	PSave.clear()

# ---------- [4] 프로필·처치 기록은 손대지 않는다 ----------
func sec4_profile_and_records_intact() -> void:
	print("\n[4] 판이 달라도 **프로필·처치 기록**은 손대지 않는다")
	PSave.clear()
	# 프로필과 처치 기록을 실제 경로로 만들어 둔다
	var prof := PProfile.new_profile("legacy")
	prof.records = 7.0
	prof.challenges["첫걸음"] = true
	ok("프로필을 만들었다", PProfile.save(prof), PProfile.profile_path())
	PSave.save_record({ "day": 10, "gold": 4242, "seed": 20260910 })
	ok("처치 기록을 만들었다", FileAccess.file_exists(PSave.RECORDS_PATH), PSave.RECORDS_PATH)
	var prof_before := bytes_of(PProfile.profile_path())
	var prof_sha := sha_of(PProfile.profile_path())
	var rec_before := bytes_of(PSave.RECORDS_PATH)
	var rec_sha := sha_of(PSave.RECORDS_PATH)
	print("     프로필 %d바이트 sha %s · 처치 기록 %d바이트 sha %s"
		% [prof_before.size(), prof_sha.substr(0, 12), rec_before.size(), rec_sha.substr(0, 12)])

	ok("옛 판본 저장을 심었다",
		plant(PSave.SAVE_PATH, '{"schema":"prophecy_save/1","saved_at":1757400002,"run":{"seed":9,"gold":1}}'))
	var res := PSave.load_result()
	ok("이어하기가 막힌다", String(res.status) == PSave.LOAD_VERSION, String(res.status))

	ok("프로필 파일이 **한 바이트도 바뀌지 않았다**(내용 비교)",
		bytes_of(PProfile.profile_path()) == prof_before and sha_of(PProfile.profile_path()) == prof_sha,
		"%s → %s" % [prof_sha.substr(0, 12), sha_of(PProfile.profile_path()).substr(0, 12)])
	ok("처치 기록 파일이 **한 바이트도 바뀌지 않았다**(내용 비교)",
		bytes_of(PSave.RECORDS_PATH) == rec_before and sha_of(PSave.RECORDS_PATH) == rec_sha,
		"%s → %s" % [rec_sha.substr(0, 12), sha_of(PSave.RECORDS_PATH).substr(0, 12)])
	# 값으로도 살아 있는지 본다(파일만 있고 내용이 비면 소용없다)
	var p2 := PProfile.load("legacy")
	ok("프로필 값이 그대로 살아 있다(기록 7 · 도전과제 1개)",
		is_equal_approx(float(p2.records), 7.0) and bool((p2.challenges as Dictionary).get("첫걸음", false)),
		"기록 %.1f · 도전과제 %s" % [float(p2.records), str((p2.challenges as Dictionary).keys())])
	var recs := PSave.load_records()
	ok("처치 기록 값이 그대로 살아 있다(금화 4242)",
		(recs.clears as Array).size() >= 1 and int((recs.clears as Array)[0].gold) == 4242,
		str(recs.get("first_clear", null)))
	# 새 회차를 시작해도 프로필·기록은 그대로다
	ok("새 회차 저장", PSave.save(PRun.new_run(5, "bow")))
	ok("새 회차를 시작해도 프로필이 그대로다", bytes_of(PProfile.profile_path()) == prof_before)
	ok("새 회차를 시작해도 처치 기록이 그대로다", bytes_of(PSave.RECORDS_PATH) == rec_before)
	PSave.clear()

# ---------- [5] '자료에 없는 장비'로 판별하지 않는다 ----------
func sec5_unknown_equipment_is_not_the_test() -> void:
	print("\n[5] **자료에 없는 장비가 든 새 판본 저장**은 예전처럼 정리하고 **이어하기가 된다**")
	print("     ← 여기가 '없는 장비가 있으니 옛 회차'라는 짐작을 못 쓰게 못박는 자리다")
	PSave.clear()
	var known := ""
	for id in PCatalog.equipment():
		known = String(id)
		break
	ok("자료에서 실제 장비 id 를 찾았다(이 검사의 전제)", known != "", known)
	if known == "":
		return
	var run := PRun.new_run(2026, "sword")
	var good_uid := PRun.equip_new_uid(run, known)
	(run.bag as Array).append(good_uid)
	run.equipment = { "weapon": "ghost_blade#1", "armor": null, "shield": null } # 자료에 없는 장비를 착용 칸에
	(run.bag as Array).append("phantom_cloak#2")                                 # 가방에도 하나
	ok("현재 판본으로 저장됐다(정상 경로)", PSave.save(run))
	ok("파일 판본이 현재 판본이다", PSave.file_run_version(JSON.parse_string(FileAccess.get_file_as_string(PSave.SAVE_PATH))) == PSave.RUN_VERSION)
	var res := PSave.load_result()
	ok("**이어하기가 된다** — 없는 장비가 있다고 판을 다르다고 하지 않는다",
		String(res.status) == PSave.LOAD_OK, "%s (파일 판본 %d)" % [String(res.status), int(res.file_version)])
	var back: Dictionary = res.run
	ok("없는 장비는 예전처럼 정리됐다(착용 칸)", back.equipment.weapon == null, str(back.equipment))
	ok("없는 장비는 예전처럼 정리됐다(가방)", not (back.bag as Array).has("phantom_cloak#2"), str(back.bag))
	ok("멀쩡한 장비는 남았다", (back.bag as Array).has(good_uid), str(back.bag))
	ok("조용히 사라지지 않았다(회차 기록에 남는다)",
		(back.get("log", []) as Array).any(func(l): return String(l).find("자료에 없는 장비") >= 0),
		str(back.get("log", [])))
	ok("파일은 그대로 남아 있다(정리는 메모리에서만 한다)", PSave.exists())
	PSave.clear()

# ---------- [6] 새 판본 저장 → 이어하기 보존 ----------
func sec6_roundtrip_keeps_everything() -> void:
	print("\n[6] 새 판본 회차는 저장 → 이어하기가 **그대로** 된다")
	PSave.clear()
	var known := ""
	for id in PCatalog.equipment():
		known = String(id)
		break
	if known == "":
		ok("자료에서 장비 id 를 찾았다(이 검사의 전제)", false)
		return
	var run := PRun.new_run(31337, "sword")
	# ① 장비 개체 두 개 — 하나는 착용, 하나는 가방. 강화 단계를 서로 다르게 준다
	var worn := PRun.equip_new_uid(run, known)
	var spare := PRun.equip_new_uid(run, known)
	(run.bag as Array).append(worn)
	(run.bag as Array).append(spare)
	PRun.equip_item(run, worn)
	var slot := String(PCatalog.equipment_def(known).slot)
	PRun.equip_plus_map(run)[worn] = 2
	PRun.equip_plus_map(run)[spare] = 1
	# ② 수동 기술: Q 는 레벨·변형을 올려 두고, 창고에 한 종 넣어 둔다
	run.growth.skills.q = { "id": "slowfield", "level": 3, "variant": "split" }
	run.growth.skills.e = { "id": "ward", "level": 2, "variant": null }
	(PGrowth.bank(run.growth) as Array).append({ "id": "gust", "level": 4, "variant": "whirl" })
	run.gold = 1357

	var worn_plus := PRun.equip_plus_of(run, worn)
	var spare_plus := PRun.equip_plus_of(run, spare)
	var bank_before := PGrowth.bank_ids(run.growth).duplicate()
	var seq_before := int(run.get("equipSeq", 0))
	print("     저장 전 — 착용 %s(+%d) · 가방 %s(+%d) · Q slowfield Lv3/split · E ward Lv2 · 창고 %s · equipSeq %d"
		% [worn, worn_plus, spare, spare_plus, str(bank_before), seq_before])

	ok("저장이 됐다", PSave.save(run), PSave.write_blocked())
	var res := PSave.load_result()
	ok("이어하기가 정상이다", String(res.status) == PSave.LOAD_OK, String(res.status))
	var back: Dictionary = res.run

	ok("장비 **개체 id** 가 그대로다(종류가 아니라 개체)",
		String(back.equipment.get(slot, "")) == worn, str(back.equipment))
	ok("가방의 다른 개체도 그대로다", (back.bag as Array).has(spare), str(back.bag))
	ok("개체 일련번호(equipSeq)가 그대로다 — 이어한 뒤 같은 id 를 다시 발급하지 않는다",
		int(back.get("equipSeq", 0)) == seq_before, "%d → %d" % [seq_before, int(back.get("equipSeq", 0))])
	ok("착용 장비의 **강화 단계**가 그대로다 (+%d)" % worn_plus,
		PRun.equip_plus_of(back, worn) == worn_plus and worn_plus == 2,
		"+%d → +%d" % [worn_plus, PRun.equip_plus_of(back, worn)])
	ok("가방 장비의 강화 단계도 개체별로 그대로다 (+%d)" % spare_plus,
		PRun.equip_plus_of(back, spare) == spare_plus and spare_plus == 1,
		"+%d → +%d" % [spare_plus, PRun.equip_plus_of(back, spare)])
	ok("강화 단계가 **정수**로 돌아온다(JSON 실수로 새지 않는다)",
		typeof((back.equipPlus as Dictionary)[worn]) == TYPE_INT, str(typeof((back.equipPlus as Dictionary)[worn])))
	ok("Q 편성이 그대로다(id·레벨·변형)",
		String(back.growth.skills.q.id) == "slowfield" and int(back.growth.skills.q.level) == 3
		and String(back.growth.skills.q.variant) == "split", str(back.growth.skills.q))
	ok("E 편성이 그대로다(id·레벨·변형 없음)",
		String(back.growth.skills.e.id) == "ward" and int(back.growth.skills.e.level) == 2
		and back.growth.skills.e.variant == null, str(back.growth.skills.e))
	ok("수동 기술 레벨이 **정수**로 돌아온다", typeof(back.growth.skills.q.level) == TYPE_INT)
	ok("창고 내용이 그대로다", PGrowth.bank_ids(back.growth) == bank_before,
		"%s → %s" % [str(bank_before), str(PGrowth.bank_ids(back.growth))])
	ok("창고 항목의 레벨·변형까지 그대로다",
		int(PGrowth.bank_entry(back.growth, "gust").get("level", 0)) == 4
		and String(PGrowth.bank_entry(back.growth, "gust").get("variant", "")) == "whirl",
		str(PGrowth.bank_entry(back.growth, "gust")))
	ok("금화가 그대로다", int(back.gold) == 1357, str(back.gold))
	ok("이어한 회차는 거점부터다(전투 표시가 내려가 있다)", not bool(back.get("inCombat", false)))

	print("\n[6-2] Q/E 를 맞바꾸고 다시 저장해도 그대로 이어진다")
	ok("맞바꾸기가 됐다", PGrowth.swap_qe(back))
	ok("다시 저장됐다", PSave.save(back))
	var back2 := PSave.load()
	ok("맞바꾼 편성이 그대로 돌아온다(Q=ward · E=slowfield)",
		PGrowth.skill_id_in(back2.growth, "q") == "ward" and PGrowth.skill_id_in(back2.growth, "e") == "slowfield",
		"q=%s e=%s" % [PGrowth.skill_id_in(back2.growth, "q"), PGrowth.skill_id_in(back2.growth, "e")])
	ok("맞바꿔도 레벨·변형이 따라간다(Q ward Lv2 · E slowfield Lv3/split)",
		int(back2.growth.skills.q.level) == 2 and int(back2.growth.skills.e.level) == 3
		and String(back2.growth.skills.e.variant) == "split",
		"%s / %s" % [str(back2.growth.skills.q), str(back2.growth.skills.e)])
	ok("장비도 그대로 따라온다", String(back2.equipment.get(slot, "")) == worn
		and PRun.equip_plus_of(back2, worn) == 2, str(back2.equipment))
	PSave.clear()

# ---------- [7] 저장 보호 관문이 그대로 작동한다 ----------
func sec7_guard_still_works() -> void:
	print("\n[7] 저장 보호 관문이 **그대로** 작동한다(판본을 넣으면서 무너뜨리지 않았다)")
	PSave.clear()
	var run := PRun.new_run(6, "sword")
	run.gold = 808
	ok("정상 상태에서는 저장된다", PSave.save(run))
	var good := bytes_of(PSave.SAVE_PATH)
	ok("검사·도구 스크립트로 인식된다(관문 ②의 전제)", PSave.running_test_script())

	var keep = blank_data()
	var reason := PSave.write_blocked()
	ok("자료가 안 서면 관문이 사유를 든다", reason.find("자료가 서 있지 않다") >= 0, reason)
	ok("그 상태에서 save() 가 거짓이다", not PSave.save(PRun.new_run(7, "spear")))
	ok("기존 저장 파일이 한 바이트도 안 바뀌었다", bytes_of(PSave.SAVE_PATH) == good,
		"%d → %d바이트" % [good.size(), bytes_of(PSave.SAVE_PATH).size()])
	PSave.clear()
	ok("그 상태에서는 지우기도 거부된다", PSave.exists() and bytes_of(PSave.SAVE_PATH) == good)
	ok("거부된 저장의 임시 파일이 남지 않았다", not FileAccess.file_exists(PSave.TMP_PATH))
	restore_data(keep)
	ok("자료가 돌아오면 관문도 다시 열린다", PSave.write_blocked() == "", PSave.write_blocked())
	ok("판이 다른 파일이 있어도 관문 사유는 저장 보호 쪽 그대로다(둘이 섞이지 않는다)",
		PSave.write_blocked() == "")
	PSave.clear()
	ok("관문이 열려 있을 때는 지우기가 실제로 지운다", not PSave.exists())

# ---------- [8] 전투 중 체크포인트가 원본 회차를 건드리지 않는다(최소) ----------
## 전투 잠금 자체는 tests/combat_lock_tests.gd 가 본다. 여기서는 **판본을 넣은 뒤에도**
## 저장이 원본을 읽기만 하는지 한 자리만 확인한다(겹치지 않게 최소).
func sec8_checkpoint_does_not_touch_run() -> void:
	print("\n[8] 전투 중 체크포인트 저장이 **원본 회차를 건드리지 않는다**(최소 확인)")
	PSave.clear()
	var run := PRun.new_run(8, "sword")
	run["inCombat"] = true
	run.gold = 12
	var before := JSON.stringify(run)
	ok("저장이 됐다", PSave.save(run))
	ok("저장 뒤에도 원본의 '전투 중' 표시가 살아 있다", bool(run.get("inCombat", false)))
	ok("원본 회차가 통째로 그대로다(저장은 읽는 일이지 바꾸는 일이 아니다)",
		JSON.stringify(run) == before)
	var back := PSave.load()
	ok("불러온 사본은 거점부터다(전투 표시가 내려가 있다)", not bool(back.get("inCombat", false)))
	ok("불러온 사본을 만져도 원본은 그대로다", not (back.is_empty()) and bool(run.get("inCombat", false)))
	PSave.clear()

# ---------- [9] 제목 화면 — 버튼이 보이되 눌리지 않고, 사유가 글자로 보인다 ----------
func sec9_title_screen() -> void:
	print("\n[9] 제목 화면 — '계속하기'가 **보이되 눌리지 않고**, 사유가 글자로 보인다")
	PSave.clear()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame

	# ① 정상(새 판본) 저장이 있을 때는 예전 그대로 눌린다
	var run := PRun.new_run(99, "sword")
	run.gold = 42
	PSave.save(run)
	main.go_title()
	await process_frame
	var title: Node = main.screens["title"]
	var cont_ok := find_button(title, "계속하기")
	ok("정상 저장에서는 '계속하기'가 눌린다", cont_ok != null and not cont_ok.disabled,
		"버튼 %s · disabled=%s" % [str(cont_ok != null), str(cont_ok.disabled) if cont_ok != null else "-"])

	# ② 옛 판본 파일을 심고 다시 그린다
	ok("옛 판본 저장을 심었다",
		plant(PSave.SAVE_PATH, '{"schema":"prophecy_save/1","saved_at":1757400003,"run":{"seed":5,"day":9,"gold":700}}'))
	var before_bytes := bytes_of(PSave.SAVE_PATH)
	var before_sha := sha_of(PSave.SAVE_PATH)
	main.go_title()
	await process_frame
	var cont := find_button(title, "계속하기")
	ok("'계속하기' 버튼이 **여전히 화면에 있다**(감추지 않았다 — 모바일에서 키로 대신할 수 없다)",
		cont != null and cont.is_visible_in_tree(),
		"버튼 %s" % ("있음" if cont != null else "없음"))
	ok("그런데 **눌리지 않는다**", cont != null and cont.disabled,
		"disabled=%s" % (str(cont.disabled) if cont != null else "-"))
	print("     버튼에 그려진 글자: %s" % (cont.text if cont != null else "(없음)"))
	var drawn := visible_text(title)
	ok("눌리지 않는 **사유가 화면에 글자로 보인다**",
		drawn.find("대규모 업데이트로 새 회차를 시작해야 합니다") >= 0,
		"보이는 글자에 문구 %s" % ("있음" if drawn.find("대규모 업데이트로 새 회차를 시작해야 합니다") >= 0 else "없음"))
	ok("옛 저장을 지우지 않았다는 것도 화면에 적혀 있다",
		drawn.find("지우지 않았습니다") >= 0)
	ok("'새 회차' 버튼은 그대로 눌린다(사람이 앞으로 갈 길이 있다)",
		find_button(title, "새 회차") != null and not find_button(title, "새 회차").disabled)
	ok("영구 성장으로 가는 길도 그대로 있다(프로필은 살아 있다)",
		find_button(title, "영구 성장") != null)

	# ③ 그 상태로 이어하기를 불러도 열리지 않고, 파일도 그대로다
	main.continue_run()
	await process_frame
	ok("이어하기를 눌러도 회차가 열리지 않는다",
		main.screen == "title" and (main.run as Dictionary).is_empty(),
		"screen=%s run비었나=%s" % [String(main.screen), str((main.run as Dictionary).is_empty())])
	ok("화면이 사유를 알린다", String(main.get_node("UI/HUD/Demo").text).find("대규모 업데이트") >= 0,
		String(main.get_node("UI/HUD/Demo").text))
	ok("제목 화면을 거치고 이어하기를 눌러도 옛 저장 파일이 **그대로다**(내용 비교)",
		bytes_of(PSave.SAVE_PATH) == before_bytes and sha_of(PSave.SAVE_PATH) == before_sha,
		"%d바이트 %s → %d바이트 %s" % [before_bytes.size(), before_sha.substr(0, 12),
			bytes_of(PSave.SAVE_PATH).size(), sha_of(PSave.SAVE_PATH).substr(0, 12)])
	ok("그 사이에 .corrupt 파일도 생기지 않았다", not FileAccess.file_exists(PSave.CORRUPT_PATH))
	main.view.running = false
	PSave.clear()
