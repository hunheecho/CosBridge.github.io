extends SceneTree
## 일반 탐험 수정(KD-7) 전후의 하루 수입·경험치 비교(화면 없음):
##   godot --headless --path prophecy_godot -s tools/repeat_income_probe.gd
## 결과: docs/sim/REPEAT_INCOME.md (부분 실행이면 _PARTIAL.md)
##
## 이것은 **기록 도구다 — 판정 스위트가 아니다.** 단언이 없고(0/0) 통과·실패를 말하지 않는다.
## 여기 있는 숫자는 전부 봇 결과이며 사람의 체감·재미가 아니다. 재미와 균형은 이 문서가 판단하지 않는다.
##
## 무엇을 비교하는가
## -----------------
## KD-7(`docs/KNOWN_DEFECTS.md`): 목표가 'clear'인 출격 카드가 영영 완료되지 않아
##  (1) 남는 시간의 '일반 탐험'이 열리지 않았고
##  (2) 같은 카드를 정상 비용으로 무한 반복하면서 **사건·이용권이 매번 새로 나왔다.**
## 지금은 `PSortie.on_clear_win`이 완료를 찍는다. 그 고침이 하루 벌이를 얼마나 바꿨는지 잰다.
##
## 대조군 스위치: `PFlow.clear_done_on`(환경 변수 PROPHECY_CLEAR_DONE=0과 같은 자리).
## 이 도구는 한 프로세스 안에서 두 규칙을 번갈아 재야 하므로 그 정적 변수를 직접 바꾸고 **반드시 되돌린다.**
## `data/**`와 저장 파일은 건드리지 않는다.
##
## "같은 행동"을 어떻게 맞추는가
## -----------------------------
## 고정: 시드 · 회차 전략(카드 고르는 규칙) · 전투 봇 정책 · 시작 무기 · 밸런스 세트 · 잰 날 수 · 사망 규칙.
## 고정하지 않는 것(고정할 수 없는 것): **어느 카드를 고르는가**. 옛 규칙에서는 이긴 카드가 완료되지 않아
## 같은 카드가 목록에 남고, 지금 규칙에서는 그 자리에 '일반 탐험'(1칸) 카드가 생긴다.
## **행동이 갈라지는 것 자체가 이 비교의 결과다** — 그래서 출격 횟수도 함께 적는다.
##
## 왜 2일인가 — 관문이 섞이지 않는 마지막 날
## ------------------------------------------
## 1막 관문은 **4일차**다(`data/enemies.json` acts.gate_day). 회차 봇은 하루 고리 맨 위에서
## `phase == "boss_prep"`을 먼저 보고 관문을 치르므로, 3일을 재려고 하면 3일차를 끝낸 뒤
## 4일차로 넘어가면서 **관문 전투가 먼저 들어온다**(`max_days` 검사가 그 뒤에 있다).
## 그러면 금화·경험치·전투 시간에 보스전이 섞여 '하루 벌이'가 아니게 된다.
## 그래서 기본은 2일이다 — 2일차를 끝내고 3일차(관문 아님)로 넘어간 자리에서 깔끔하게 멈춘다.
## 날 수를 늘리려면 `PROPHECY_INCOME_DAYS`를 쓰되, 관문이 섞이면 보고서가 그 사실을 경고한다.
##
## 부분 실행 축: rule · seed
##   PROPHECY_SUBSET="rule=now;seed=1"
## 환경 변수: PROPHECY_INCOME_DAYS(기본 2 — 관문이 섞이지 않는 마지막 날) PROPHECY_INCOME_SEEDS("1,2,3,4,5")
##   PROPHECY_INCOME_STRAT(기본 gradual) PROPHECY_INCOME_BOT(기본 balanced) PROPHECY_SIM_OUT

## 비교할 두 규칙. legacy = 옛 규칙(완료 표시 없음), now = 지금 규칙(기본값)
const RULES := ["legacy", "now"]
const RULE_NAME := { "legacy": "옛 규칙(완료 표시 없음)", "now": "지금 규칙(완료 표시)" }
const SEEDS := [1, 2, 3, 4, 5]

var sub := PSubset.new()
var rows := []
var days := 2
var strat := "gradual"
var bot := "balanced"

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ints(s: String) -> Array:
	var out := []
	for p in s.split(","):
		var t := String(p).strip_edges()
		if t != "" and t.is_valid_int():
			out.append(int(t))
	return out

## 지금까지 얻은 경험치 총량. 레벨 표(PGrowth.xp_need)를 누적하고 남은 경험치를 더한다.
## run.growth에는 누계가 없어서(레벨업 때마다 빼기 때문에) 여기서 되돌려 센다
func total_xp(g: Dictionary) -> float:
	var sum := 0.0
	for lv in range(1, int(g.level)):
		sum += float(PGrowth.xp_need(lv))
	return sum + float(g.get("xp", 0.0))

## 보유 이용권(종류별 합). 사용한 이용권은 여기 남지 않는다 — 보고서에 그 한계를 적는다
func voucher_n(run: Dictionary) -> int:
	var n := 0
	for k in (run.get("services", {}) as Dictionary):
		n += int(run.services[k])
	return n

func voucher_text(run: Dictionary) -> String:
	var parts := []
	var S: Dictionary = run.get("services", {})
	var keys := S.keys()
	keys.sort()
	for k in keys:
		if int(S[k]) > 0:
			parts.append("%s %d" % [String(PCatalog.services()[String(k)].name), int(S[k])])
	return " · ".join(parts) if parts.size() > 0 else "-"

func _sum(arr: Array) -> int:
	var n := 0
	for v in arr:
		n += int(v)
	return n

## 회차 한 번. rule에 맞춰 대조군 스위치를 켜고 끄되 **끝나면 반드시 원래대로 돌린다**
func one_run(rule: String, seed_v: int) -> Dictionary:
	var saved: bool = PFlow.clear_done_on
	PFlow.clear_done_on = (rule == "now")
	var o := { "start": "sword", "bot_policy": bot, "balance": "", "max_retries": 3, "max_days": days }
	var L: Dictionary = PRunBot.simulate(seed_v, strat, o)
	PFlow.clear_done_on = saved
	if L.is_empty():
		return {}
	var run: Dictionary = L.get("run_state", {})
	var g: Dictionary = run.get("growth", {})
	var gold_days: Array = L.get("goldEarnedByDay", [])
	var sorties: int = int(L.encounters) - int(L.eventFights) - int(L.deeps)
	return {
		"rule": rule, "seed": seed_v,
		"gold_by_day": gold_days.duplicate(),
		"gold_total": _sum(gold_days),
		"gold_left": int(L.gold), "gold_spent": int(L.goldSpent),
		"xp_total": round(total_xp(g) * 10.0) / 10.0, "level": int(g.get("level", 1)),
		"events": int(L.eventCount), "event_fights": int(L.eventFights),
		"vouchers": voucher_n(run), "voucher_text": voucher_text(run),
		"sorties": sorties, "encounters": int(L.encounters), "deeps": int(L.deeps),
		"rests": int(L.rests), "picks": int(L.picksTotal),
		"combat_sec": int(L.combatSec), "taken": int(L.taken),
		"gates": (L.get("bosses", []) as Array).size(), # 0이 아니면 관문 전투가 섞였다는 뜻이다(2절 경고)
		"days_done": int(L.day), "stop": String(L.stopReason),
	}

func avg(rule: String, key: String) -> float:
	var sum := 0.0
	var n := 0
	for r in rows:
		if String((r as Dictionary).rule) != rule:
			continue
		sum += float((r as Dictionary).get(key, 0))
		n += 1
	return round(sum / float(maxi(1, n)) * 10.0) / 10.0

func rule_rows(rule: String) -> Array:
	var out := []
	for r in rows:
		if String((r as Dictionary).rule) == rule:
			out.append(r)
	return out

## 두 규칙 평균의 차이를 "옛 → 지금(+n / −n)" 한 칸으로
func delta_cell(key: String, fmt: String = "%.1f") -> String:
	var a := avg("legacy", key)
	var b := avg("now", key)
	var d := b - a
	var sign := "+" if d > 0.0 else ""
	return (fmt % a) + " → " + (fmt % b) + " (" + sign + (fmt % d) + ")"

func _init() -> void:
	days = int(_env("PROPHECY_INCOME_DAYS", "2"))
	strat = _env("PROPHECY_INCOME_STRAT", "gradual")
	bot = _env("PROPHECY_INCOME_BOT", "balanced")
	var seeds := _ints(_env("PROPHECY_INCOME_SEEDS", "1,2,3,4,5"))
	if seeds.is_empty():
		seeds = SEEDS.duplicate()
	var use_rules := sub.pick("rule", RULES.duplicate())
	var use_seeds := sub.pick("seed", seeds)
	printerr("repeat_income_probe: rules=%s seeds=%s days=%d strat=%s bot=%s" % [str(use_rules), str(use_seeds), days, strat, bot])
	var t0 := Time.get_ticks_msec()
	for rule in use_rules:
		for s in use_seeds:
			var t1 := Time.get_ticks_msec()
			var row := one_run(String(rule), int(s))
			if row.is_empty():
				printerr("FAIL %s seed %d: 기록 없음" % [String(rule), int(s)])
				continue
			rows.append(row)
			printerr("done %s seed %d: 금화 %d · 경험치 %.0f · 사건 %d · 이용권 %d · 출격 %d (%d ms)" % [
				String(rule), int(s), int(row.gold_total), float(row.xp_total), int(row.events),
				int(row.vouchers), int(row.sorties), Time.get_ticks_msec() - t1])
	var path := sub.out_path(_env("PROPHECY_SIM_OUT", "res://docs/sim/REPEAT_INCOME.md"))
	_write(path, _markdown(use_rules, use_seeds))
	print("REPEAT_INCOME_JSON " + JSON.stringify({ "days": days, "strategy": strat, "bot": bot,
		"rules": use_rules, "seeds": use_seeds, "subset": sub.spec(), "rows": rows }))
	printerr("repeat_income_probe: %d회 %d ms → %s" % [rows.size(), Time.get_ticks_msec() - t0, path])
	quit(0)

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("쓰기 실패: " + path)
		return
	f.store_string(text)
	f.close()

func _markdown(use_rules: Array, use_seeds: Array) -> String:
	var md := sub.describe("일반 탐험 수정(KD-7) 전후의 하루 수입·경험치")
	md += "%s. **기록 도구다 — 판정 스위트가 아니다**(단언 0/0). 여기 있는 숫자는 전부 봇 결과이고 시험값이다.\n" % Time.get_date_string_from_system()
	md += "**체감·재미는 이 문서가 판단하지 않는다.** 숫자만 낸다.\n\n"
	md += "- 도구: `tools/repeat_income_probe.gd` (스위트 `repeat_income_probe`)\n"
	md += "- 대조군 스위치: `PFlow.clear_done_on`(환경 변수 `PROPHECY_CLEAR_DONE=0`이면 옛 규칙). 기본값은 지금 규칙이다.\n"
	md += "- 배경: `docs/KNOWN_DEFECTS.md` KD-7 · 규칙: `PSortie.on_clear_win` · `PSortie.repeat_cards`\n\n"
	md += "---\n\n## 1. 무엇을 고정했고 무엇이 갈라지는가\n\n"
	md += "| 항목 | 값 | 두 규칙에서 같은가 |\n|---|---|---|\n"
	md += "| 시드 | %s | 같다 |\n" % str(use_seeds)
	md += "| 잰 날 수 | %d일 | 같다 |\n" % days
	var sdef: Dictionary = PRunBot.strategies().get(strat, {})
	md += "| 회차 전략(카드 고르는 규칙) | `%s` — %s | 같다 |\n" % [strat, String(sdef.get("doc", ""))]
	md += "| 전투 봇 정책 | `%s` | 같다 |\n" % bot
	md += "| 시작 무기 · 밸런스 세트 · 사망 규칙 | sword · 기본 · 시험 재시도 | 같다 |\n"
	md += "| **어느 카드를 고르는가** | 전략이 정한 선호 지역 안에서 목록의 첫 카드 | **갈라진다(아래)** |\n\n"
	md += "옛 규칙에서는 이긴 카드가 완료되지 않아 **같은 카드가 목록에 그대로 남는다**(정상 비용·정상 보상·사건 재굴림).\n"
	md += "지금 규칙에서는 그 카드가 완료로 접히고, 남는 시간에 **'일반 탐험'(1칸, 전리품·경험치만)** 카드가 생긴다.\n"
	md += "봇은 두 규칙에서 **같은 고르는 규칙**을 쓰지만 **목록이 다르므로 고르는 것이 달라진다.**\n"
	md += "그 갈라짐 자체가 이 비교의 결과다 — 그래서 출격 횟수·사건 수를 수입과 나란히 적는다.\n\n"
	md += "**왜 %d일인가.** 1막 관문은 4일차다. 회차 봇은 하루 고리 맨 위에서 `phase == \"boss_prep\"`을 먼저 보고\n" % days
	md += "관문을 치르므로(그 뒤에 `max_days` 검사가 온다), 3일을 재려고 하면 3일차를 끝내고 4일차로 넘어가면서\n"
	md += "**관문 전투가 금화·경험치·전투 시간에 섞인다**. 그러면 '하루 벌이' 비교가 아니게 된다.\n"
	md += "그래서 기본은 관문이 섞이지 않는 마지막 날인 2일이다(`PROPHECY_INCOME_DAYS`로 바꿀 수 있다).\n\n"
	md += "---\n\n## 2. 규칙별 평균(%d일 합계 기준)\n\n" % days
	var gate_n := 0
	for r in rows:
		gate_n += int((r as Dictionary).get("gates", 0))
	if gate_n > 0:
		md += "> **경고: 관문 전투가 %d번 섞였다.** 아래 금화·경험치·전투 시간은 순수한 하루 벌이가 아니다.\n" % gate_n
		md += "> `PROPHECY_INCOME_DAYS`를 관문 전날(2일 또는 5일)로 되돌려 다시 재라.\n\n"
	md += "| 값 | 옛 규칙 → 지금 규칙 (차이) |\n|---|---|\n"
	md += "| **금화 수입**(번 것, 쓴 것 포함) | %s |\n" % delta_cell("gold_total", "%.0f")
	md += "| **경험치 총량** | %s |\n" % delta_cell("xp_total", "%.0f")
	md += "| 도달 레벨 | %s |\n" % delta_cell("level", "%.1f")
	md += "| **사건 발생 수** | %s |\n" % delta_cell("events", "%.1f")
	md += "| **이용권(보유, 끝 시점)** | %s |\n" % delta_cell("vouchers", "%.1f")
	md += "| **출격 횟수**(카드 출격) | %s |\n" % delta_cell("sorties", "%.1f")
	md += "| 전투 수(사건·심층 포함) | %s |\n" % delta_cell("encounters", "%.1f")
	md += "| 성장 3택 횟수 | %s |\n" % delta_cell("picks", "%.1f")
	md += "| 휴식 횟수 | %s |\n" % delta_cell("rests", "%.1f")
	md += "| 전투 시간 합(초) | %s |\n" % delta_cell("combat_sec", "%.0f")
	md += "| 받은 피해 합 | %s |\n" % delta_cell("taken", "%.0f")
	md += "\n**이용권은 '보유' 기준이다.** 이 도구는 획득을 직접 세지 않는다 — 회차 기록(`run.log`)이 8줄로 잘리고\n"
	md += "규칙에 획득 계수기가 없기 때문이다. 이 구간에서 이용권이 줄어드는 길은 휴식권 사용 하나뿐이므로\n"
	md += "휴식 횟수를 같이 적었다(휴식이 0이면 보유 = 획득이다).\n\n"
	md += "---\n\n## 3. 시드별\n\n"
	for rule in use_rules:
		md += "### %s\n\n" % String(RULE_NAME.get(rule, rule))
		md += "| 시드 | 하루별 금화 | 금화 합 | 경험치 | 레벨 | 사건 | 이용권(보유) | 출격 | 전투 | 휴식 | 관문 | 멈춘 이유 |\n"
		md += "|---:|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---|\n"
		for r in rule_rows(String(rule)):
			var d: Dictionary = r
			var per := []
			for v in (d.gold_by_day as Array):
				per.append(str(int(v)))
			md += "| %d | %s | %d | %.0f | %d | %d | %s | %d | %d | %d | %d | %s |\n" % [
				int(d.seed), "/".join(per), int(d.gold_total), float(d.xp_total), int(d.level),
				int(d.events), String(d.voucher_text), int(d.sorties), int(d.encounters), int(d.rests),
				int(d.get("gates", 0)), String(d.stop)]
		md += "\n"
	md += "---\n\n## 4. 이 표가 말하지 않는 것\n\n"
	md += "- **재미와 체감은 재지 않았다.** 하루 벌이가 늘었는지 줄었는지만 있다. 그것이 좋은지는 사람이 정한다.\n"
	md += "- 봇은 사람이 아니다. 카드 고르는 규칙 하나(`%s`)만 썼고, 사람은 남는 시간을 다르게 쓴다.\n" % strat
	md += "- %d일까지만 봤다. 관문·후반 날짜의 벌이는 이 표 밖이다.\n" % days
	md += "- 이용권은 보유 기준이라 사용분이 빠져 있다(2절 주석).\n"
	md += "- 옛 규칙 쪽 숫자는 **고쳐진 구멍을 되살린 것**이다. 되돌리자는 제안이 아니라 비교 기준일 뿐이다.\n"
	return md
