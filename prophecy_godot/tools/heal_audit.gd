extends SceneTree
## 회복 경제 실측(화면 없음):
##   godot --headless --path prophecy_godot -s tools/heal_audit.gd
## 결과: docs/sim/HEAL_AUDIT.md (부분 실행이면 HEAL_AUDIT_PARTIAL.md)
##
## 회복약을 **최대 체력과만** 비교하면 "하루 2개(60)로는 100을 못 채우니 휴식을 대체 못 한다"는
## 결론이 나온다. 그것은 최대 체력을 다 잃는다는 가정이다. 실제로 하루에 얼마를 잃는지 재고,
## 다른 회복 수단과 합쳐서 판단해야 한다(2026-09-08 사용자 지시 §4).
##
## 재는 것
##   - 날짜별 **실제 손실 체력**(전투에서 잃은 양)과 하루 끝 잔여 체력
##   - 회복 수단별 실제 적용량: 휴식 · 회복약 · 장비 자동 회복 · 준비물(약낭·부적 흡수)
##   - 휴식 선택 횟수와 그때의 체력
##   - 회복약 하루 상한이 하루 손실을 덮는가(= 휴식을 대체할 수 있는가)
##
## 부분 실행 축: strat(전략) · seed
##   예) PROPHECY_ONLY="seed:1" · PROPHECY_QUICK=1

const STRATS := ["gradual", "deep"]
const SEEDS := [1, 2, 3, 4]

var sub := PSubset.new()
var days := []      # 날짜별 기록
var runs := []      # 회차 요약

func _init() -> void:
	for strat in sub.pick("strat", STRATS):
		for sd in sub.pick("seed", SEEDS):
			if not sub.more():
				break
			_one(String(strat), int(sd))
			printerr("done ", strat, " ", sd)
	print("HEAL_AUDIT_JSON " + JSON.stringify({ "days": days, "runs": runs }))
	_write()
	quit()

## 한 회차를 봇으로 돌리며 날짜별 체력 흐름을 기록한다.
## PRunBot이 하루 단위 훅을 주지 않으므로, 회차 로그(run.log)와 회차 결과의 집계를 쓴다.
func _one(strat: String, seed_v: int) -> void:
	var rec := PRunBot.simulate(seed_v, strat, { "start": "sword", "bot_policy": "balanced",
		"max_retries": 3, "legacy_places": true, "track_days": true })
	var per_day: Array = rec.get("dayRows", [])
	var hp_max := 100.0
	var lost_total := 0.0
	var rest_n := 0
	var potion_n := 0
	for d in per_day:
		lost_total += float(d.get("lost", 0.0))
		rest_n += int(d.get("rest", 0))
		potion_n += int(d.get("potion", 0))
		days.append({ "strat": strat, "seed": seed_v, "day": int(d.get("day", 0)),
			"start_hp": float(d.get("startHp", 0.0)), "end_hp": float(d.get("endHp", 0.0)),
			"lost": float(d.get("lost", 0.0)), "healed": float(d.get("healed", 0.0)),
			"rest": int(d.get("rest", 0)), "potion": int(d.get("potion", 0)),
			"fights": int(d.get("fights", 0)) })
		hp_max = maxf(hp_max, float(d.get("hpMax", 100.0)))
	runs.append({ "strat": strat, "seed": seed_v, "days": per_day.size(),
		"lost_total": snapped(lost_total, 0.1), "rest": rest_n, "potion": potion_n,
		"hp_max": hp_max, "cleared": bool(rec.get("cleared", false)),
		"last_day": int(rec.get("day", 0)) })

static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

func _write() -> void:
	var pot := PConsumables.potion_def()
	var rules := PConsumables.rules()
	var heal: float = float(pot.get("heal", 0.0))
	var per_day_cap: int = int(rules.get("potionPerDay", 0))
	var md := "# 회복 경제 실측 (하루에 실제로 얼마를 잃는가)\n\n"
	md += "생성: `tools/heal_audit.gd` (%s, Godot %s).\n" % [OS.get_name(), Engine.get_version_info().string]
	md += sub.describe(not sub.partial()) + "\n\n"
	md += "> 봇 결과는 규칙 검증용이며 사람 체감이 아니다. 봇 승패를 통과 조건으로 쓰지 않았다.\n\n"
	md += "## 1. 날짜별 실제 손실 체력\n\n"
	md += "| 전략 | 시드 | 날짜 수 | 하루 평균 손실 | 하루 최대 손실 | 휴식 | 회복약 |\n|---|---:|---:|---:|---:|---:|---:|\n"
	for r in runs:
		var mine := []
		for d in days:
			if String(d.strat) == String(r.strat) and int(d.seed) == int(r.seed):
				mine.append(float(d.lost))
		var mx := 0.0
		for v in mine:
			mx = maxf(mx, v)
		md += "| %s | %d | %d | %.1f | %.1f | %d | %d |\n" % [String(r.strat), int(r.seed), int(r.days),
			_avg(mine), mx, int(r.rest), int(r.potion)]
	var all_lost := []
	for d in days:
		all_lost.append(float(d.lost))
	var avg_lost := _avg(all_lost)
	var max_lost := 0.0
	for v in all_lost:
		max_lost = maxf(max_lost, v)
	md += "\n**하루 평균 손실 %.1f · 하루 최대 손실 %.1f** (최대 체력 100 기준).\n" % [avg_lost, max_lost]
	md += "\n## 2. 회복약이 휴식을 대체할 수 있는가\n\n"
	md += "| 항목 | 값 |\n|---|---|\n"
	md += "| 회복약 1개 회복량 | %.0f |\n" % heal
	md += "| 하루 구매 상한 | %d개 = %.0f 회복 |\n" % [per_day_cap, heal * float(per_day_cap)]
	md += "| 하루 평균 손실 | %.1f |\n" % avg_lost
	md += "| 하루 최대 손실 | %.1f |\n" % max_lost
	var covers_avg := heal * float(per_day_cap) >= avg_lost
	var covers_max := heal * float(per_day_cap) >= max_lost
	md += "| 평균 손실을 덮는가 | %s |\n" % ("**덮는다**" if covers_avg else "덮지 못한다")
	md += "| 최대 손실을 덮는가 | %s |\n" % ("**덮는다**" if covers_max else "덮지 못한다")
	md += "\n판단: "
	if covers_max:
		md += "회복약 하루 상한이 **가장 나쁜 날의 손실까지 덮는다.** 휴식을 사실상 대체할 수 있으므로 상한이나 회복량을 낮추는 후보를 검토해야 한다.\n"
	elif covers_avg:
		md += "회복약 하루 상한이 **보통 날의 손실은 덮지만 나쁜 날은 못 덮는다.** 휴식과 회복약 사이에 선택이 생기는 상태다 — 지금 값이 그 목적에는 맞는다.\n"
	else:
		md += "회복약 하루 상한이 **보통 날의 손실도 못 덮는다.** 휴식을 대체할 수 없고, 급할 때 시간을 아끼는 보조 수단에 머문다.\n"
	md += "\n최대 체력(100)과만 비교하면 '못 덮는다'가 되지만, 실제 손실과 비교하면 위 결론이 나온다. **최대 체력이 아니라 실제 손실로 판단한다.**\n"
	md += "\n## 3. 다른 회복 수단과 합친 하루 회복력\n\n"
	md += "| 수단 | 하루 최대 회복 | 조건 |\n|---|---:|---|\n"
	md += "| 휴식 | 100(전체) | 시간 1칸, 남은 칸만큼 |\n"
	md += "| 무료 휴식권 | 100(전체) | 상인 날 1장, 100금, 시간 0칸 |\n"
	md += "| 회복약 | %.0f | %d개 상한, 개당 %d금 |\n" % [heal * float(per_day_cap), per_day_cap, int(pot.get("price", 0))]
	md += "| 장비 자동 회복 | 승리마다 8 | 갑옷 칸을 쓴다 |\n"
	md += "| 응급 약낭(준비물) | 18 | 전투 1회, 체력 30% 이하 |\n"
	md += "| 수호 부적(준비물, 흡수) | 25 | 전투 1회 시작 보호막 |\n"
	md += "\n준비물은 하나만 장착하므로 약낭과 부적을 같은 전투에 함께 쓸 수 없다.\n"
	var f := FileAccess.open("res://docs/sim/HEAL_AUDIT.md" if not sub.partial() else "res://docs/sim/HEAL_AUDIT_PARTIAL.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
