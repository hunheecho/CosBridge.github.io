extends SceneTree
## 저장에 **자료에 없는 장비**가 들어 있어도 게임이 죽지 않는다.
## 실행: python tools/run_suites.py --suites save_repair_tests
##
## 왜 있는가(2026-09-10): 시험 스크립트가 사람의 저장을 덮어써서, 환경 변수를 켜야만 존재하는
## 시험용 장비 id 가 든 저장이 만들어졌다. 그 저장을 '계속하기'로 열면
## PCatalog.equipment_def 가 빈 사전을 돌려주고 그것을 받은 쪽이 `.slot` 을 읽다 **게임이 죽는다.**
## 사용자 지시: "저장 회차는 상관없어. 우리 게임만 오류 없으면 돼."
## → 회차를 되살리는 것이 아니라 **어떤 저장이 와도 멈추지 않게** 만든다.

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	# 자료에 있는 장비 하나를 골라 기준으로 삼는다
	var known := ""
	for id in PCatalog.equipment():
		known = String(id)
		break
	ok("자료에서 실제 장비 id 를 찾았다(이 검사의 전제)", known != "", known)

	var run := PRun.new_run(11, "sword")
	run.equipment = { "weapon": "ghost_blade#1", "armor": known, "shield": null }
	run.bag = ["phantom_cloak#2", known]

	# 불러오기와 같은 정리를 태운다
	PSave._drop_unknown_equipment(run)

	ok("없는 장비를 장착 칸에서 뺀다", run.equipment.weapon == null, str(run.equipment))
	ok("있는 장비는 그대로 둔다", String(run.equipment.armor) == known, str(run.equipment))
	ok("없는 장비를 가방에서 뺀다", not (run.bag as Array).has("phantom_cloak#2"), str(run.bag))
	ok("가방의 있는 장비는 남는다", (run.bag as Array).has(known), str(run.bag))
	ok("조용히 사라지지 않는다 — 회차 기록에 남는다",
		(run.get("log", []) as Array).any(func(l): return String(l).find("자료에 없는 장비") >= 0),
		str(run.get("log", [])))

	# 정리한 뒤에는 빌드 계산이 오류 없이 끝난다(여기가 예전에 죽던 자리다)
	var b := PBuild.derive(run)
	ok("정리 뒤 빌드 계산이 끝난다(예전에는 여기서 죽었다)", not b.is_empty() and float(b.hp_max) > 0.0,
		"최대 체력 %.0f" % float(b.hp_max))

	# 폐기 장비는 자료에 남아 있으므로 빠지지 않는다(기존 저장 보존)
	var retired := ""
	for id in PCatalog.crafted_equipment():
		if String(id) != "note" and PCatalog.equipment_retired(String(id)):
			retired = String(id)
			break
	if retired != "":
		var r2 := PRun.new_run(12, "sword")
		r2.equipment = { "weapon": null, "armor": null, "shield": retired }
		PSave._drop_unknown_equipment(r2)
		ok("폐기 장비는 빠지지 않는다(자료에 그대로 있다 — 기존 저장 보존)",
			String(r2.equipment.shield) == retired, str(r2.equipment))

	# 멀쩡한 저장은 아무것도 바뀌지 않는다
	var r3 := PRun.new_run(13, "sword")
	r3.equipment = { "weapon": null, "armor": known, "shield": null }
	r3.bag = [known]
	var before := JSON.stringify(r3.equipment) + JSON.stringify(r3.bag)
	PSave._drop_unknown_equipment(r3)
	ok("멀쩡한 저장은 손대지 않는다",
		JSON.stringify(r3.equipment) + JSON.stringify(r3.bag) == before)

	# **자료를 못 읽은 상황에서는 아무것도 지우면 안 된다.**
	# 사용자 지적(2026-09-10): "자료를 아직 못 읽었거나 개체 id 를 잘못 해석해서
	# 존재하는 장비를 없는 것으로 판단하는 경우를 막아야 한다."
	# 목록을 잠깐 비워(캐시를 직접 갈아끼워) 그 상황을 만든 뒤, 장비가 살아남는지 본다.
	var r4 := PRun.new_run(14, "sword")
	r4.equipment = { "weapon": null, "armor": known, "shield": null }
	r4.bag = [known]
	var saved_world = PCatalog._cache.get("world", null)
	var blanked: Dictionary = {}
	if typeof(saved_world) == TYPE_DICTIONARY:
		blanked = (saved_world as Dictionary).duplicate(true)
		blanked["equipment"] = {}
		PCatalog._cache["world"] = blanked
	PSave._drop_unknown_equipment(r4)
	if typeof(saved_world) == TYPE_DICTIONARY:
		PCatalog._cache["world"] = saved_world
	ok("자료를 못 읽으면 아무것도 지우지 않는다(멀쩡한 장비를 지우는 쪽이 더 위험하다)",
		String(r4.equipment.armor) == known and (r4.bag as Array).has(known), str(r4.equipment) + str(r4.bag))
	ok("그 상황에서 회차 기록에 '정리했다'를 적지도 않는다",
		not (r4.get("log", []) as Array).any(func(l): return String(l).find("자료에 없는 장비") >= 0),
		str(r4.get("log", [])))

	# 개체 id 해석: 같은 종류라도 일련번호가 다르면 각각, 그러나 **종류는 같게** 읽어야 한다
	ok("개체 id 해석 — '<종류>#N' 의 종류는 '#' 앞", PRun.equip_type_of(known + "#7") == known,
		PRun.equip_type_of(known + "#7"))
	ok("개체 id 해석 — '#' 이 없으면 문자열 전체가 종류(옛 저장)", PRun.equip_type_of(known) == known)
	var r5 := PRun.new_run(15, "sword")
	r5.equipment = { "weapon": null, "armor": known + "#1", "shield": null }
	r5.bag = [known + "#2", known + "#3"]
	PSave._drop_unknown_equipment(r5)
	ok("같은 종류의 개체 여러 개가 전부 살아남는다",
		String(r5.equipment.armor) == known + "#1" and (r5.bag as Array).size() == 2, str(r5.bag))

	print("%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
