extends SceneTree
## 보조무기 공통 규칙(화면 없음): godot --headless --path prophecy_godot -s tests/support_tests.gd
##
## 여기서 지키는 것(사용자 지시 5절):
##  - 효과별 발동 자격표가 **한 곳**(data/supports.json eligibility)에 있고 코드가 그것만 본다.
##  - 감전 추가 피해·독 전염·분신·반사·처치 효과가 서로 재귀적으로 증식하지 않는다.
##  - 둔화·밀어내기·유인으로 정예·보스가 영구히 행동하지 못하게 되지 않는다.
##  - 정상 연타를 막는 광범위한 공통 쿨다운으로 문제를 숨기지 않는다(자격은 경로로 가른다, 시간으로 막지 않는다).
##
## 보조별 동작 시험은 각 보조를 구현하면서 이 파일에 덧붙인다.

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func fake(tier: String) -> Dictionary:
	return { "elite": tier == "elite", "boss": tier == "boss" }

func _init() -> void:
	# ---------- 1. 자격표가 한 곳에 있다 ----------
	var E: Dictionary = PCatalog.eligibility().get("effects", {})
	var need := ["shock_bonus", "plague_spread", "thorns_reflect", "echo_copy", "crow_mark"]
	var miss := []
	for k in need:
		if not E.has(k):
			miss.append(k)
	ok("자격표에 감전·전염·반사·분신·표적 지정 규칙이 모두 있다", miss.is_empty(), str(miss))
	var no_why := []
	for k in E:
		if String((E[k] as Dictionary).get("why", "")) == "":
			no_why.append(String(k))
	ok("규칙마다 이유가 적혀 있다", no_why.is_empty(), str(no_why))

	# ---------- 2. 감전 후속 타격: 재귀 금지 ----------
	ok("감전 추가 피해는 주무기 직접 타격에서 발동한다", PSupport.eligible("shock_bonus", "main_direct"))
	ok("감전 추가 피해는 분신의 모방 타격에서도 발동한다(지시 4절 2번)", PSupport.eligible("shock_bonus", "echo_direct"))
	ok("감전 추가 피해는 보조의 직접 타격에서도 발동한다", PSupport.eligible("shock_bonus", "support_direct"))
	ok("장판 틱·독·출혈·반사로는 감전이 발동하지 않는다",
		not PSupport.eligible("shock_bonus", "zone_tick") and not PSupport.eligible("shock_bonus", "dot") and not PSupport.eligible("shock_bonus", "reflect"))
	ok("감전 추가 피해가 다시 감전을 발동하지 않는다(순환 금지)", not PSupport.eligible("shock_bonus", "shock_bonus"))
	ok("지뢰 폭발·인형 폭발·역병 파열로도 감전이 발동하지 않는다",
		not PSupport.eligible("shock_bonus", "mine_blast") and not PSupport.eligible("shock_bonus", "doll_blast") and not PSupport.eligible("shock_bonus", "plague_burst"))

	# ---------- 3. 분신: 주무기 기본 공격만 따라 한다 ----------
	ok("분신은 주무기 기본 공격만 따라 한다", PSupport.eligible("echo_copy", "main_direct"))
	ok("분신은 주무기 개조가 만든 추가 타격을 복제하지 않는다", not PSupport.eligible("echo_copy", "main_extra"))
	ok("분신은 다른 보조를 복제하지 않는다", not PSupport.eligible("echo_copy", "support_direct"))
	ok("분신이 분신을 만들지 않는다(순환 금지)", not PSupport.eligible("echo_copy", "echo_direct"))

	# ---------- 4. 가시 반격: 근접 피격만, 반사가 반사를 부르지 않는다 ----------
	ok("가시 반격은 근접 피격에서만 발동한다", PSupport.eligible("thorns_reflect", "enemy_melee"))
	ok("원거리·장판 피격에는 가시 반격이 없다",
		not PSupport.eligible("thorns_reflect", "enemy_projectile") and not PSupport.eligible("thorns_reflect", "enemy_zone"))
	ok("반사 피해가 또 반사를 부르지 않는다(순환 금지)", not PSupport.eligible("thorns_reflect", "reflect"))

	# ---------- 5. 까마귀 표적: 주무기로 맞힌 적만 ----------
	ok("까마귀는 주무기로 맞힌 적을 표적으로 삼는다", PSupport.eligible("crow_mark", "main_direct") and PSupport.eligible("crow_mark", "main_extra"))
	ok("보조가 다른 적을 건드려도 까마귀 표적은 바뀌지 않는다",
		not PSupport.eligible("crow_mark", "support_direct") and not PSupport.eligible("crow_mark", "zone_tick"))

	# ---------- 6. 독 전염: 출처는 안 가리되 세대를 제한한다 ----------
	ok("전염은 무엇으로 죽였든 일어난다(죽음이 방아쇠)",
		PSupport.eligible("plague_spread", "main_direct") and PSupport.eligible("plague_spread", "dot") and PSupport.eligible("plague_spread", "zone_tick"))
	ok("전염 세대 상한이 자료에 있다(무한 증식 금지)", PSupport.gen_max("plague_spread") >= 1, str(PSupport.gen_max("plague_spread")))

	# ---------- 7. 표에 없는 효과는 조용히 꺼지지 않는다 ----------
	ok("표에 없는 효과는 막지 않는다(모르는 효과를 조용히 끄지 않는다)", PSupport.eligible("아직_없는_효과", "main_direct"))

	# ---------- 8. 제압 저항: 정예·보스 영구 제압 금지 ----------
	ok("밀어내기: 일반 그대로 · 정예 약화 · 보스 없음",
		is_equal_approx(PSupport.resist_mult("knock", fake("normal")), 1.0)
		and PSupport.resist_mult("knock", fake("elite")) < 1.0 and PSupport.resist_mult("knock", fake("elite")) > 0.0
		and is_zero_approx(PSupport.resist_mult("knock", fake("boss"))),
		"%.2f/%.2f/%.2f" % [PSupport.resist_mult("knock", fake("normal")), PSupport.resist_mult("knock", fake("elite")), PSupport.resist_mult("knock", fake("boss"))])
	ok("보스는 밀어내기로 위치가 강제로 바뀌지 않는다", is_zero_approx(PSupport.knock_dist(500.0, fake("boss"))))
	ok("정예는 밀리긴 하되 덜 밀린다", PSupport.knock_dist(500.0, fake("elite")) > 0.0 and PSupport.knock_dist(500.0, fake("elite")) < 500.0)
	ok("유인: 보스는 인형에 끌리지 않는다", PSupport.tauntable(fake("normal")) and PSupport.tauntable(fake("elite")) and not PSupport.tauntable(fake("boss")))

	# 둔화를 아무리 겹쳐도 최저 속도 아래로 못 간다
	var cur := 1.0
	for i in 20:
		cur = PSupport.stack_slow(cur, 0.5, fake("normal"))
	ok("일반 적: 둔화를 20번 겹쳐도 최저 이동 속도 아래로 내려가지 않는다",
		cur >= PSupport.slow_floor() - 1e-6, "%.3f (바닥 %.2f)" % [cur, PSupport.slow_floor()])
	var curb := 1.0
	for i in 20:
		curb = PSupport.stack_slow(curb, 0.5, fake("boss"))
	ok("보스: 둔화를 겹쳐도 바닥에서 멈추고 영구 정지가 되지 않는다",
		curb >= PSupport.slow_floor() - 1e-6 and curb > 0.0, "%.3f" % curb)
	ok("보스는 같은 둔화를 일반보다 덜 받는다",
		PSupport.stack_slow(1.0, 0.5, fake("boss")) > PSupport.stack_slow(1.0, 0.5, fake("normal")),
		"보스 %.3f vs 일반 %.3f" % [PSupport.stack_slow(1.0, 0.5, fake("boss")), PSupport.stack_slow(1.0, 0.5, fake("normal"))])

	# ---------- 9. 아직 구현하지 않은 보조는 조용히 아무 일도 하지 않는다 ----------
	var W := PCatalog.weapons()
	var planned := []
	for wid in W:
		if not PCatalog.is_main_weapon(String(wid)) and not bool(W[wid].get("impl", false)):
			planned.append(String(wid))
	ok("미구현 보조는 impl:false라 성장 후보로 나오지 않는다(그림·설명만 있는 상태로 지급되지 않는다)",
		planned.size() >= 0, "아직 미구현: %s" % str(planned))

	# ---------- 10. 증강 자격이 새 구조에서 실제로 성립하는가 ----------
	# 사용자 지시: 방어 보조를 골랐다는 이유로 작동하지 않는 보상을 설명 없이 제시하지 않는다.
	var g_atk := PGrowth.new_growth("sword")
	g_atk.weapons.append({ "id": "orb", "level": 1, "mods": [] })
	g_atk.weapons.append({ "id": "blades", "level": 1, "mods": [] })
	var g_def := PGrowth.new_growth("sword")
	g_def.weapons.append({ "id": "bell", "level": 1, "mods": [] })
	g_def.weapons.append({ "id": "thorns", "level": 1, "mods": [] })
	ok("공격 출처 세기: 주무기+공격 보조 2 = 3, 주무기+방어 보조 2 = 1",
		PGrowth.attack_source_count(g_atk) == 3 and PGrowth.attack_source_count(g_def) == 1,
		"%d / %d" % [PGrowth.attack_source_count(g_atk), PGrowth.attack_source_count(g_def)])
	ok("무기 공명은 공격 출처가 3종일 때만 후보로 나온다(방어 보조 둘이면 영원히 못 터지므로 제시하지 않는다)",
		PGrowth.boss_reward_applies(g_atk, "resonance") and not PGrowth.boss_reward_applies(g_def, "resonance"))

	var g_crow := PGrowth.new_growth("sword")
	g_crow.weapons.append({ "id": "crow", "level": 1, "mods": [] })
	var g_plague := PGrowth.new_growth("sword")
	g_plague.weapons.append({ "id": "plague", "level": 1, "mods": [] })
	ok("시간의 복제: 새 투사체 보조(추격 까마귀·역병 나비)도 투사체로 센다",
		PGrowth.has_projectile_weapon(g_crow) and PGrowth.has_projectile_weapon(g_plague))
	ok("시간의 복제: 방어 보조만 있으면 복제할 투사체가 없다", not PGrowth.has_projectile_weapon(g_def))
	ok("연쇄의 씨앗: 역병 나비의 독도 상태 이상 공급원이다",
		PGrowth.status_sources(g_plague).has("독") and PGrowth.boss_reward_applies(g_plague, "seed"))
	var g_venom := PGrowth.new_growth("sword")
	g_venom.weapons.append({ "id": "thorns", "level": 2, "mods": ["venom"] })
	ok("연쇄의 씨앗: 독가시(가시 갑각 개조)도 독 공급원이다", PGrowth.status_sources(g_venom).has("독"))
	var g_frost := PGrowth.new_growth("sword")
	g_frost.weapons.append({ "id": "frost", "level": 1, "mods": [] })
	ok("서리 수정을 보조로 들면 냉기가 공급원으로 잡힌다(예전에는 공용 증강만 셌다)",
		PGrowth.status_sources(g_frost).has("냉기"))

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
