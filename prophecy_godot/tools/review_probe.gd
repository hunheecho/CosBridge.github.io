extends SceneTree
## **자체 교차 검수 전용 계측 도구**(2026-09-09). 규칙·자료는 하나도 고치지 않는다.
## 실행: godot --headless --path prophecy_godot -s tools/review_probe.gd
##
## 왜 있는가
## ---------
## 기존 검사·계측은 편성표(`data/themes.json`)나 카드 예고(`PSortie.elite_notice`)까지만 보고 멈춘다.
## 그런데 사람이 실제로 만나는 것은 **카드를 눌러 시작한 전투의 `CombatState`에 실제로 예약된 적**이다.
## 이 도구는 그 마지막 한 칸까지 밀어 본다:
##   PSortie.cards_for → PSortie.start → PFlow.encounter_opts → CombatState → 실제 소환 대기열
##
## 재는 것
##   ① 실제 회차에서 특수 정예·일반 정예·새 몬스터가 **전투에 실제로 예약되는가**
##      (카드 예고와 실제 편성이 어긋나는지)
##   ② 부활 수단 없이 죽으면 회차가 즉시 끝나는가 / 물약이 되살아나지 않는가
##   ③ 보스 사망 뒤 체력 25% 벌칙이 실제로 남는가
##   ④ 무한 모드에서 부활 물약이 동작하는가
## 판정하지 않는다. 수치만 남긴다.

const DAYS := 10
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]

var lines := []

func say(s: String) -> void:
	lines.append(s)
	print(s)

func _init() -> void:
	section_elites()
	section_death()
	say("REVIEW_PROBE_DONE")
	quit(0)

## 이 전투 상태에 실제로 등장이 예약된 적 종류를 센다(이미 나온 것 + 대기 중 + 아직 예약 안 한 편성 몫)
func types_in(st: CombatState) -> Dictionary:
	var out := {}
	for e in st.enemies:
		out[String(e.type)] = int(out.get(String(e.type), 0)) + 1
	for q in st.pending:
		var t := String(q.get("type", ""))
		if t != "":
			out[t] = int(out.get(t, 0)) + 1
	# formation.units는 종류 이름의 배열이다(사전이 아니다)
	for g in st.formation.get("units", []):
		var t2 := String(g)
		if t2 != "":
			out[t2] = int(out.get(t2, 0)) + 1
	return out

func is_elite(t: String) -> bool:
	return t.begins_with("elite_") or t == "wolf_alpha"

# ---------- ① 정예·새 몬스터가 실제 전투에 예약되는가 ----------
func section_elites() -> void:
	say("")
	say("## ① 실제 카드 경로로 시작한 전투에 어떤 적이 예약되는가")
	say("")
	say("`PSortie.cards_for` → `PSortie.start` → `PFlow.encounter_opts` → `CombatState`까지 실제로 태운다.")
	say("")
	var notice_cards := 0        # 카드가 '강적 출현'이라고 예고한 횟수
	var notice_real := 0         # 그중 실제 전투에 특수 정예가 예약된 횟수
	var fights := 0
	var elite_fights := 0
	var by_type := {}
	var by_obj := {}             # 목표별: [카드 예고 수, 실제 정예 수]
	var seen_types := {}
	for sd in SEEDS:
		var run := PRun.new_run(sd, "sword")
		for day in DAYS:
			if bool(run.get("ended", false)):
				break
			# 관문 날이면 **계측 전용으로** 보스를 이긴 것으로 처리해 다음 막으로 넘어간다.
			# 이 도구는 편성 도달성을 재는 것이고, 보스 난이도를 재는 것이 아니다
			if PRun.is_boss_day(run):
				run.phase = "boss_prep"
				PRun.start_boss(run)
				PRun.boss_victory(run, { "elapsed": 60.0 })
				if String(run.phase) == "cleared" or bool(run.get("ended", false)):
					break
				run.phase = "prep"
				run.hours = 5
			var cards: Array = PSortie.cards_for(run)
			for c in cards:
				if not PSortie.can_start(run, c):
					continue
				# 카드를 실제로 시작해 보고, 상태를 되돌린다(계측 전용 — 진행은 아래 end_day가 한다)
				var snap: Dictionary = JSON.parse_string(JSON.stringify(run)) as Dictionary
				var s: Dictionary = PSortie.start(run, String(c.id))
				if s.is_empty():
					run = snap
					continue
				var st := PFlow.make_encounter(run, s)
				fights += 1
				var act := 1 if int(run.day) <= 4 else (2 if int(run.day) <= 7 else 3)
				var obj := "%d막 %s" % [act, String(s.get("objective", "clear"))]
				if not by_obj.has(obj):
					by_obj[obj] = [0, 0, 0]
				by_obj[obj][2] = int(by_obj[obj][2]) + 1
				var notice: Dictionary = PSortie.elite_notice(run, c) as Dictionary
				var predicted: bool = not notice.is_empty() and not (notice.get("types", []) as Array).is_empty()
				if predicted:
					notice_cards += 1
					by_obj[obj][0] = int(by_obj[obj][0]) + 1
				var ts := types_in(st)
				var found := false
				for t in ts:
					seen_types[t] = int(seen_types.get(t, 0)) + int(ts[t])
					if is_elite(String(t)):
						found = true
						by_type[t] = int(by_type.get(t, 0)) + int(ts[t])
				if found:
					elite_fights += 1
					by_obj[obj][1] = int(by_obj[obj][1]) + 1
					if predicted:
						notice_real += 1
				run = snap
			# 하루 넘기기. 관문 날이면 phase가 boss_prep이 되어 end_day가 막히므로
			# **계측 전용으로** phase만 prep으로 되돌려 10일 전체(1~3막)를 훑는다.
			# 규칙을 고치는 것이 아니라 이 도구 안에서만 날짜를 넘기는 것이다
			run.phase = "prep"
			run.hours = 5
			if not PRun.end_day(run):
				break
	say("- 실제로 시작한 전투 **%d회** · 그중 정예(일반+특수)가 예약된 전투 **%d회**" % [fights, elite_fights])
	say("- 카드가 '강적 출현'이라 예고한 전투 **%d회** · 그중 실제로 정예가 있던 전투 **%d회**" % [notice_cards, notice_real])
	say("")
	say("| 목표(objective) | 전투 수 | 카드 예고 | 실제 정예 |")
	say("|---|---:|---:|---:|")
	for o in by_obj:
		say("| %s | %d | %d | %d |" % [o, int(by_obj[o][2]), int(by_obj[o][0]), int(by_obj[o][1])])
	say("")
	say("| 실제로 예약된 정예 | 마릿수 |")
	say("|---|---:|")
	if by_type.is_empty():
		say("| (없음) | 0 |")
	for t in by_type:
		say("| %s | %d |" % [t, int(by_type[t])])
	say("")
	var news := ["boar", "shieldbearer", "shaman", "bomber", "burrower", "spider", "frostcaller", "rogue"]
	var miss := []
	for n in news:
		if not seen_types.has(n):
			miss.append(n)
	say("- 새 몬스터 8종 중 실제 전투에 예약되지 않은 것: **%s**" % ("없음" if miss.is_empty() else str(miss)))
	var all_elites: Array = ["elite_archer", "elite_blademaster", "elite_chainbreaker", "elite_fang",
		"elite_miner", "elite_plaguecaller", "elite_standard", "wolf_alpha"]
	var e_miss := []
	for n in all_elites:
		if not by_type.has(n):
			e_miss.append(n)
	say("- 정예 8종 중 실제 전투에 한 번도 예약되지 않은 것: **%s**" % ("없음" if e_miss.is_empty() else str(e_miss)))

# ---------- ② ③ ④ 사망·부활 ----------
func section_death() -> void:
	say("")
	say("## ② 사망·부활을 실제 회차 상태로 태운다")
	say("")

	# (가) 부활 수단 없음 · 일반 전투 사망
	var r1 := PRun.new_run(11, "sword")
	r1.day = 3
	var s1 := PRun.start_sortie(r1, String(PRun.places_for(r1)[0]))
	PRun.defeat(r1, s1)
	say("- **물약 없이 일반 전투 사망**: phase=`%s` · ended=%s · hours=%d · hp=%.1f · is_run_over=%s · 행동 수=%d"
		% [String(r1.phase), str(r1.get("ended", false)), int(r1.hours), float(r1.hp), str(PRun.is_run_over(r1)), (PFlow.actions(r1) as Array).size()])

	# (나) 부활 물약 있음 · 일반 전투 사망 → 물약이 되살아나지 않는가(저장 왕복 포함)
	var r2 := PRun.new_run(12, "sword")
	r2.day = 3
	r2.gold = 9999
	PConsumables.buy(r2, "revive_potion")
	var have0 := PConsumables.count(r2, "revive_potion")
	var s2 := PRun.start_sortie(r2, String(PRun.places_for(r2)[0]))
	PRun.defeat(r2, s2)
	var have1 := PConsumables.count(r2, "revive_potion")
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(r2))
	var have2 := PConsumables.count(round_trip, "revive_potion")
	say("- **물약 들고 일반 전투 사망**: 물약 %d → %d(저장 왕복 뒤 %d) · phase=`%s` · ended=%s · day=%d · hp=%.1f(최대 %.1f)"
		% [have0, have1, have2, String(r2.phase), str(r2.get("ended", false)), int(r2.day), float(r2.hp), float(PRun.build(r2).hp_max)])

	# (다) 같은 사망을 두 번 정산해도 값이 바뀌지 않는가
	var before := JSON.stringify(r2)
	PRun.defeat(r2, s2)
	say("- **같은 사망 재정산**: 회차 상태가 그대로인가 = %s" % str(JSON.stringify(r2) == before))

	# (라) 보스 사망 뒤 체력 25% 벌칙이 실제로 남는가
	var r3 := PRun.new_run(13, "sword")
	r3.gold = 9999
	PConsumables.buy(r3, "revive_potion")
	while not PRun.is_boss_day(r3) and int(r3.day) < 12:
		r3.day = int(r3.day) + 1
	r3.phase = "boss_prep"
	PRun.start_boss(r3)
	PRun.boss_defeat(r3)
	var hp_after_death: float = float(r3.hp)
	var cap: float = float(PRun.build(r3).hp_max)
	var hp_at_reentry := -1.0
	if String(r3.phase) == "boss_prep":
		PRun.start_boss(r3)
		hp_at_reentry = float(r3.hp)
	say("- **보스 사망 뒤 부활**: 정산 직후 체력 %.1f / %.1f (%.0f%%) → 관문 재입장 뒤 체력 %.1f (%.0f%%)"
		% [hp_after_death, cap, hp_after_death / maxf(cap, 1.0) * 100.0, hp_at_reentry, hp_at_reentry / maxf(cap, 1.0) * 100.0])

	# (마) 무한 모드에서 부활 물약이 동작하는가
	var r4 := PRun.new_run(14, "sword")
	r4.gold = 9999
	PConsumables.buy(r4, "revive_potion")
	var e_have0 := PConsumables.count(r4, "revive_potion")
	r4.phase = "cleared"
	r4.day = 10
	var started: bool = PEndless.start(r4)
	var e_txt := "무한 모드를 켜지 못해 확인 못 함(can_start=%s)" % str(PEndless.can_start(r4))
	if started and PEndless.active(r4):
		var s4 := PRun.start_sortie(r4, String(PRun.places_for(r4)[0])) if not PRun.places_for(r4).is_empty() else {}
		if not s4.is_empty():
			PRun.defeat(r4, s4)
			e_txt = "물약 %d → %d · phase=`%s` · ended=%s" % [e_have0, PConsumables.count(r4, "revive_potion"), String(r4.phase), str(r4.get("ended", false))]
	say("- **무한 모드 사망**: %s" % e_txt)
