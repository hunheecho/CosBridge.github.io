extends SceneTree
## **전투 중에는 규칙 계층이 기술 편성을 막는다**(KD-13).
## 실행: python tools/run_suites.py --suites combat_lock_tests --jobs 1
##
## 왜 있는가 — 2026-09-10 검수에서 드러난 구멍:
##   PGrowth.bank_edit_reason 머리말은 "전투 중에는 절대 열지 않는다"고 적혀 있었다.
##   그런데 보는 것은 run.phase 하나였고, **전투 중에도 phase 는 "prep" 그대로다**
##   (PSortie.start 가 phase 를 바꾸지 않는다).
##   실측: screen=combat · phase=prep · bank_edit_reason="" (열려 있었다).
##   그때 실제로 막고 있던 것은 "전투 화면에 편성 버튼이 없다"는 사실뿐이었다 —
##   누가 전투 HUD 나 일시정지에 버튼을 하나 붙이면 그대로 뚫린다.
##
## 여기서 못박는 것
##   ① 전투에 들어가면 규칙 계층이 편성 변경 셋(보관·배치·맞바꾸기)을 **전부** 거부한다
##   ② 정산이 끝나면 다시 열린다 — 영영 잠기지 않는다
##   ③ 전투 도중 저장하고 이어하기해도 잠기지 않는다(이어하기는 언제나 거점부터다)
##   ④ 보스 전투도 같다
##   ⑤ 이 표시가 없는 옛 저장은 예전처럼 열린다(회차를 못 쓰게 만들지 않는다)

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 편성 변경 셋이 전부 막혔는가. 하나라도 통하면 거짓
func all_blocked(run: Dictionary) -> bool:
	var before_q := PGrowth.skill_id_in(run.growth, "q")
	var before_e := PGrowth.skill_id_in(run.growth, "e")
	var a := PGrowth.store_skill(run, "q")
	var b := PGrowth.swap_qe(run)
	var c := PGrowth.place_skill(run, "e", "slowfield")
	var unchanged: bool = PGrowth.skill_id_in(run.growth, "q") == before_q \
		and PGrowth.skill_id_in(run.growth, "e") == before_e
	return not a and not b and not c and unchanged

func mk_run() -> Dictionary:
	var r := PRun.new_run(1, "sword")
	r.growth.skills.q = { "id": "slowfield", "level": 3, "variant": "follow" }
	r.growth.skills.e = { "id": "strike", "level": 2, "variant": null }
	return r

func _init() -> void:
	print("[1] 거점에서는 열려 있다(이 검사가 저절로 통과하지 않는다)")
	var run := mk_run()
	ok("거점에서 관문이 열려 있다", PGrowth.bank_edit_reason(run) == "", PGrowth.bank_edit_reason(run))
	ok("실제로 보관이 된다", PGrowth.store_skill(run, "q"))
	ok("실제로 배치가 된다", PGrowth.place_skill(run, "q", "slowfield"))
	ok("실제로 맞바꾸기가 된다", PGrowth.swap_qe(run))
	PGrowth.swap_qe(run) # 되돌린다

	print("\n[2] 전투에 들어가면 **규칙 계층이** 막는다")
	var run2 := mk_run()
	var cards := PSortie.cards_for(run2)
	ok("오늘 카드가 있다(이 검사의 전제)", not cards.is_empty(), str(cards.size()))
	var sortie := PSortie.start(run2, String(cards[0].id))
	ok("출격이 시작됐다", not sortie.is_empty())
	var st := PFlow.make_encounter(run2, sortie)
	st.spawn_hold = true
	ok("전투에 들어가도 phase 는 여전히 'prep' 이다(이것이 예전에 뚫린 이유)",
		String(run2.get("phase", "")) == "prep", String(run2.get("phase", "")))
	ok("그래도 관문이 사유를 돌려준다", PGrowth.bank_edit_reason(run2) != "",
		PGrowth.bank_edit_reason(run2))
	ok("사유가 전투를 가리킨다", PGrowth.bank_edit_reason(run2).find("전투 중") >= 0,
		PGrowth.bank_edit_reason(run2))
	ok("보관·배치·맞바꾸기가 **전부** 거부되고 편성이 그대로다", all_blocked(run2))

	print("\n[3] 정산이 끝나면 다시 열린다 — 영영 잠기지 않는다")
	st.status = "won"
	st.mark_duel_done_for_test()
	st.player.hp = 80.0
	PFlow.settle_victory(run2, sortie, st)
	ok("승리 정산 뒤 관문이 열렸다", PGrowth.bank_edit_reason(run2) == "",
		PGrowth.bank_edit_reason(run2))
	ok("정산 뒤에는 실제로 맞바꾸기가 된다", PGrowth.swap_qe(run2))

	print("\n[4] 패배 정산도 잠근 채로 두지 않는다")
	var run3 := mk_run()
	var c3 := PSortie.cards_for(run3)
	var s3 := PSortie.start(run3, String(c3[0].id))
	var st3 := PFlow.make_encounter(run3, s3)
	st3.spawn_hold = true
	ok("전투 중에는 막힌다", PGrowth.bank_edit_reason(run3) != "")
	st3.status = "lost"
	st3.player.hp = 0.0
	PFlow.settle_defeat(run3, s3, st3)
	# 패배하면 회차가 끝나 phase 가 "dead" 가 된다 — 그래서 **여전히** 사유가 있다.
	# 여기서 못박는 것은 "전투 중 표시가 남아 있지 않다"이지 "누구나 편성할 수 있다"가 아니다.
	# 두 사유를 구분하지 않으면 표시가 남아도 검사가 통과해 버린다.
	ok("패배 정산 뒤 '전투 중' 표시가 내려갔다",
		not bool(run3.get("inCombat", false)), str(run3.get("inCombat", null)))
	ok("남은 사유는 회차가 끝났기 때문이지 전투 중이어서가 아니다",
		PGrowth.bank_edit_reason(run3).find("전투 중") < 0 and String(run3.get("phase", "")) == "dead",
		"%s / phase=%s" % [PGrowth.bank_edit_reason(run3), String(run3.get("phase", ""))])

	print("\n[5] 전투 도중 저장 → 이어하기로 잠기지 않는다")
	var run4 := mk_run()
	var c4 := PSortie.cards_for(run4)
	var s4 := PSortie.start(run4, String(c4[0].id))
	var st4 := PFlow.make_encounter(run4, s4)
	st4.spawn_hold = true
	ok("전투 중이다", PGrowth.bank_edit_reason(run4) != "")
	var saved := PSave.save(run4) # 전투 시작 체크포인트와 같은 자리
	ok("전투 중에도 저장은 된다(저장을 막는 것이 아니다)", saved, PSave.write_blocked())
	var back := PSave.load()
	ok("이어하기가 회차를 돌려준다", not back.is_empty())
	ok("**이어하기한 회차는 잠겨 있지 않다**(거점부터 시작하므로)",
		PGrowth.bank_edit_reason(back) == "", PGrowth.bank_edit_reason(back))
	ok("이어하기 뒤 실제로 편성을 바꿀 수 있다", PGrowth.swap_qe(back))
	PSave.clear()

	print("\n[6] 보스 전투도 같다")
	var run5 := mk_run()
	run5.phase = "boss_prep"
	ok("관문 준비에서는 열려 있다", PGrowth.bank_edit_reason(run5) == "",
		PGrowth.bank_edit_reason(run5))
	var bs := { "seed": 12345, "bossId": "boss", "regionId": "boss" }
	var st5 := PFlow.make_boss_encounter(run5, bs)
	st5.spawn_hold = true
	ok("보스 전투에 들어가면 막힌다", PGrowth.bank_edit_reason(run5) != "",
		PGrowth.bank_edit_reason(run5))
	ok("보스 전투에서도 셋 다 거부된다", all_blocked(run5))

	print("\n[7] 이 표시가 없는 옛 저장은 예전처럼 열린다")
	var old_run := mk_run()
	old_run.erase("inCombat")
	ok("inCombat 키가 없어도 거점이면 열린다", PGrowth.bank_edit_reason(old_run) == "",
		PGrowth.bank_edit_reason(old_run))
	old_run.phase = "dead"
	ok("옛 규칙(phase)도 그대로 살아 있다", PGrowth.bank_edit_reason(old_run) != "",
		PGrowth.bank_edit_reason(old_run))

	print("\n%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
