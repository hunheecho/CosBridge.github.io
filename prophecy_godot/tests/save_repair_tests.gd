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

	print("%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
