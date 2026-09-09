extends SceneTree
## 특수 정예 결투는 **임무 목표 카드에 붙지 않는다**(KD-11).
## 실행: python tools/run_suites.py --suites duel_card_tests
##
## 왜 있는가 — 사용자 재현(2026-09-09):
##   "포로 풀어주고 내가 (출구에) 들어가면 맵 끝나는 그거다. 나도 방금 데스크탑으로 하다 이 화면 떴음"
##   (창 전체가 검게 남은 화면 = 아무것도 누를 수 없는 상태)
##
## 무슨 일이 있었나
##   결투는 "일반 편성을 전부 정리한 뒤"에 시작한다(CombatState.update_duel 의 normal 단계).
##   그런데 임무 전투는 **목표를 이루는 순간** 끝난다 — 포로를 다 풀고 출구에 들어가면
##   남은 적이 있어도 그 자리에서 승리다.
##   그래서 결투가 시작도 못 한 채 전투가 끝나고, PFlow.settle_victory 가
##   "특수 정예전 미완료 상태의 승리 정산"으로 거부해 보상이 빈 사전이 되고,
##   보상 화면이 **버튼 하나 없이** 그려졌다.
##
## 왜 이렇게 고쳤나
##   승리를 막아 결투를 기다리게 할 수도 있다. 그러면 목표를 이룬 뒤에도 남은 적과 지원병을
##   전부 잡아야 끝나서 **끝낼 수 없는 전투**가 될 위험이 있다.
##   두 규칙이 같은 카드에서 양립하지 않으므로 배정 단계에서 겹치지 않게 했다.
##   결투 자체는 없어지지 않는다 — 다른 카드가 있으면 거기에 붙는다.

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func card(id: String, place: String, obj: String) -> Dictionary:
	return { "id": id, "regionId": place, "objective": obj, "risk": null, "duelType": "", "duelName": "" }

func _init() -> void:
	var run := PRun.new_run(3, "sword")
	var places: Array = []
	for rid in PCatalog.theme_places():
		places.append(String(rid))
	if places.size() < 2:
		ok("테마 장소가 둘 이상 있다(이 검사의 전제)", false, str(places))
		print("%d/%d PASS" % [pass_n, pass_n + fail_n])
		quit(1)
		return

	var day := int(run.day)
	var mission_ids: Array = (PCatalog.missions().objective_ids as Array)
	ok("임무 목표 종류를 자료에서 읽었다", not mission_ids.is_empty(), str(mission_ids))

	# ① 임무 카드만 있는 날 — 억지로 붙이지 않는다(고치기 전에는 여기에 붙었다)
	for obj in mission_ids:
		var only: Array = [card("m", String(places[0]), String(obj))]
		PRun.assign_duel(run, day, only)
		ok("임무 카드만 있으면 결투를 붙이지 않는다 — %s" % String(obj),
			String(only[0].duelType) == "", String(only[0].duelType))

	# ② 임무 카드와 일반 카드가 섞인 날 — 일반 카드로 간다
	for obj in mission_ids:
		var mixed: Array = [card("m", String(places[0]), String(obj)),
			card("c", String(places[1 % places.size()]), "clear")]
		PRun.assign_duel(run, day, mixed)
		ok("임무 카드에는 안 붙는다 — %s" % String(obj),
			String(mixed[0].duelType) == "", String(mixed[0].duelType))
		ok("같은 날 일반 카드에는 그대로 붙는다(결투가 사라지지 않는다) — %s" % String(obj),
			String(mixed[1].duelType) != "", String(mixed[1].duelType))

	# ③ 일반 카드만 있는 날 — 예전 그대로 붙는다(이 수정이 결투를 줄이지 않는다)
	var plain: Array = [card("c1", String(places[0]), "clear"), card("c2", String(places[1 % places.size()]), "clear")]
	PRun.assign_duel(run, day, plain)
	ok("일반 카드만 있으면 예전처럼 결투가 붙는다",
		String(plain[0].duelType) != "" or String(plain[1].duelType) != "",
		"%s / %s" % [String(plain[0].duelType), String(plain[1].duelType)])

	# ④ 붙은 결투는 이름도 함께 채워진다(화면이 읽는 값)
	var named := ""
	for c in plain:
		if String((c as Dictionary).duelType) != "":
			named = String((c as Dictionary).duelName)
	ok("결투가 붙으면 상대 이름도 채워진다", named != "", named)

	print("%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
