extends SceneTree
## 화면을 막는 창은 **언제나 나갈 수 있어야 한다**(headless).
## 실행: python tools/run_suites.py --suites overlay_tests
##
## 왜 있는가 — 사람 플레이 보고(2026-09-09):
##   "포로 구출했는데 또 봉인돼서 화면 아무것도 누를 수 없는 상태가 되냐고."
##   "모바일에서 화면에 버튼을 감추지 마. esc 같은 건 데스크탑에서나 할 수 있지
##    모바일에선 버튼 없으면 아예 안 된다고."
##
## 3택 창(PChoiceOverlay)이 떠 있으면 main.gd 의 choice.is_open() 관문이 전투 입력을 통째로 막는다.
## 그런데 나가는 버튼이 pool 별로 따로 달려 있어서, "boss" pool 에는 아무 버튼도 없었고
## 후보 목록이 비면(PGrowth.generate_offer 가 빈 목록을 낼 수 있다) 고를 카드도 없었다.
## 그러면 '내 빌드 보기'만 눌리는 — 아무리 눌러도 진행이 안 되는 — 화면이 된다.
##
## 여기서 못박는 것: **어떤 pool 이든, 후보가 비었든 아니든, 나갈 길이 하나는 있다.**
## '내 빌드 보기'는 나갈 길로 세지 않는다(눌러도 창이 안 닫힌다).
## pool 을 새로 늘려도 이 검사가 잡는다.

var pass_n := 0
var fail_n := 0

func ok(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 창에 실제로 붙어 있는, 누를 수 있는 버튼 글자들
func button_texts(node: Node, out: Array) -> Array:
	if node is Button:
		var b := node as Button
		if not b.disabled:
			out.append(String(b.text))
	for ch in node.get_children():
		button_texts(ch, out)
	return out

func _init() -> void:
	var run := PRun.new_run(7, "sword")
	var ov := PChoiceOverlay.new()
	root.add_child(ov)
	await process_frame   # _ready()가 돌아 _box가 만들어질 때까지 기다린다

	# pool 4종 × 후보 없음. 후보가 비는 것이 가장 위험한 경우다
	for pool in ["level", "boss", "mission", "deep", "새로_생긴_이름"]:
		ov.open(run, { "pool": pool, "choices": [] })
		var texts := button_texts(ov, [])
		ok("후보가 비어도 나갈 수 있다 — pool=%s" % pool, ov.has_exit(), "버튼: %s" % str(texts))
		ok("후보가 비면 '계속'이 실제로 붙는다 — pool=%s" % pool,
			texts.has("계속") or texts.has("받지 않음") or texts.any(func(t): return String(t).begins_with("건너뛰기")),
			str(texts))

	# 후보가 있으면 카드를 고르는 것이 나갈 길이다
	var off := PGrowth.generate_offer(run, { "pool": "level", "region_id": "" })
	if not (off.get("choices", []) as Array).is_empty():
		ov.open(run, off)
		ok("후보가 있으면 나갈 수 있다(카드 고르기)", ov.has_exit(),
			"후보 %d개" % (off.choices as Array).size())

	# '내 빌드 보기'만으로는 나갈 길이 아니다 — 그것만 있는 화면이 생기면 안 된다
	ov.open(run, { "pool": "boss", "choices": [] })
	var only := button_texts(ov, [])
	var exits := 0
	for t in only:
		var s := String(t)
		if s == "계속" or s == "받지 않음" or s.begins_with("건너뛰기"):
			exits += 1
	ok("'내 빌드 보기' 말고 나가는 버튼이 최소 하나 있다", exits >= 1, str(only))

	ov.queue_free()
	print("%d/%d PASS" % [pass_n, pass_n + fail_n])
	quit(1 if fail_n > 0 else 0)
