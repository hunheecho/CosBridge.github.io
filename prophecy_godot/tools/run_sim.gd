extends SceneTree
## 회차 시뮬레이션 보고서(헤드리스, HTML tools/run_sim.js 이식). 봇이 회차를 끝까지 돌리고(PRunBot) 전략 × 시드 표를 만든다.
## 사용: PROPHECY_SIM_SEEDS=1,2,3 godot --headless --path prophecy_godot -s tools/run_sim.gd
## 환경 변수: PROPHECY_SIM_SEEDS("1,2,3,4,5") PROPHECY_SIM_STRATS(전략 id 목록, 기본 7종 전부) PROPHECY_SIM_START(sword|spear|blades)
##   PROPHECY_SIM_BOT(balanced 등 PBot 정책) PROPHECY_SIM_BALANCE(밸런스 세트, 기본 = balance_default) PROPHECY_SIM_STOPDAY(성장 중단일) PROPHECY_SIM_DENSITY(밀도 세트 uniform_x5|roles) PROPHECY_SIM_OUT(res://docs/sim/RUN_SIM.md)
## 머리말의 설정값은 실제 회차·카탈로그 값에서 만든다(F8: 하드코딩 없음). 결과: 마크다운 + RUN_SIM_JSON 한 줄. 봇 결과는 정책 비교용이며 사람의 체감·재미와 다르다.

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

func _avg(rows: Array, key: String) -> float:
	if rows.is_empty():
		return 0.0
	var sum := 0.0
	for r in rows:
		var v = (r as Dictionary).get(key, 0)
		sum += float(v) if v != null else 0.0
	return round(sum / float(rows.size()) * 10.0) / 10.0

func _avg_idx(rows: Array, key: String, idx: int) -> float:
	if rows.is_empty():
		return 0.0
	var sum := 0.0
	for r in rows:
		var arr: Array = (r as Dictionary).get(key, [])
		sum += float(arr[idx]) if idx < arr.size() else 0.0
	return round(sum / float(rows.size()) * 10.0) / 10.0

func _join(arr: Array, sep: String = "/") -> String:
	var parts := []
	for v in arr:
		parts.append(str(v))
	return sep.join(parts)

func _n(v: Variant) -> String:
	return "-" if v == null else str(v)

func _rows_of(all: Array, sid: String) -> Array:
	var out := []
	for r in all:
		if String(r.strategy) == sid:
			out.append(r)
	return out

func _pat_text(rows: Array) -> String:
	var pat := {}
	for r in rows:
		var bp: Dictionary = r.bossPatterns
		for k in bp:
			pat[String(k)] = int(pat.get(String(k), 0)) + int(bp[k])
	var keys := pat.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s %s" % [String(k), str(round(float(pat[k]) / float(rows.size()) * 10.0) / 10.0)])
	return ", ".join(parts)

func _init() -> void:
	var seeds := _ints(_env("PROPHECY_SIM_SEEDS", "1,2,3,4,5"))
	if seeds.is_empty():
		seeds = [1]
	var STR := PRunBot.strategies()
	var strats := []
	for p in _env("PROPHECY_SIM_STRATS", ",".join(STR.keys())).split(","):
		var t := String(p).strip_edges()
		if STR.has(t):
			strats.append(t)
	if strats.is_empty():
		strats = STR.keys()
	var start := _env("PROPHECY_SIM_START", "sword")
	var bot := _env("PROPHECY_SIM_BOT", "balanced")
	var balance := _env("PROPHECY_SIM_BALANCE", "")
	var stop_day := int(_env("PROPHECY_SIM_STOPDAY", "0"))
	var density_set := _env("PROPHECY_SIM_DENSITY", "") # 밀도 세트(uniform_x5 기본 | roles 후보)
	var out_path := _env("PROPHECY_SIM_OUT", "res://docs/sim/RUN_SIM.md")
	var o := { "start": start, "bot_policy": bot, "balance": balance, "stop_day": stop_day, "max_retries": 3, "density_set": density_set }
	var SET := PRunBot.settings(o)
	printerr("run_sim: seeds=%s strats=%s start=%s bot=%s balance=%s(%s) difficulty=%s bossHp=%s" % [str(seeds), str(strats), start, bot, String(SET.balance), String(SET.balance_name), String(SET.difficulty), JSON.stringify(SET.boss_hp)])
	var all := []
	var t_all := Time.get_ticks_msec()
	for sid in strats:
		for seed in seeds:
			var t0 := Time.get_ticks_msec()
			var L = PRunBot.simulate(int(seed), String(sid), o)
			if L == null or not (L is Dictionary) or (L as Dictionary).is_empty():
				printerr("FAIL %s seed %d: 기록 없음(위 오류 참조)" % [String(sid), int(seed)])
				continue
			var rec: Dictionary = L
			all.append(rec)
			printerr("done %s seed %d: level=%d encounters=%d losses=%d timeouts=%d boss=%s cleared=%s (%d ms)" % [String(sid), int(seed), int(rec.level), int(rec.encounters), int(rec.losses), int(rec.timeouts), String(rec.boss), str(rec.cleared), Time.get_ticks_msec() - t0])
	var md := _markdown(all, strats, seeds, SET, o)
	_write(out_path, md)
	var json_rows := []
	for r in all:
		var c: Dictionary = (r as Dictionary).duplicate()
		var gb := []
		for b in c.get("gateBuilds", []):
			gb.append({ "stage": int(b.stage), "bossId": String(b.bossId), "day": int(b.day), "level": int(b.level), "growth": b.growth, "equipment": b.equipment, "forge": int(b.forge), "gold": int(b.gold), "hpMax": float(b.hpMax) })
		c.gateBuilds = gb
		json_rows.append(c)
	print("RUN_SIM_JSON " + JSON.stringify({ "settings": SET, "seeds": seeds, "strategies": strats, "runs": json_rows }))
	printerr("run_sim: %d runs in %d ms → %s" % [all.size(), Time.get_ticks_msec() - t_all, out_path])
	quit(0)

func _write(path: String, text: String) -> void:
	var dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("쓰기 실패: " + path)
		return
	f.store_string(text)
	f.close()

func _markdown(all: Array, strats: Array, seeds: Array, SET: Dictionary, o: Dictionary) -> String:
	var STR := PRunBot.strategies()
	var M: Dictionary = SET.menu
	var boss_parts := []
	for id in SET.boss_hp:
		boss_parts.append("%s %d" % [String(SET.boss_names[id]), int(SET.boss_hp[id])])
	var stop_txt := (", 성장 중단 %d일차" % int(o.stop_day)) if int(o.stop_day) > 0 else ""
	var md := "# 회차 시뮬레이션 (%s, 봇 %s, 밸런스 %s(%s), 난이도 %s(%s), 시작 무기 %s, 회차 구조 %s %d일, 처치 경험치 ×%s, 지역 경험치 ×%s, 보스 체력 세트 %s = %s, 날짜 체력 %s, 밀도 세트 %s(배율 ×%s) 동시 %d%s)\n\n" % [
		String(SET.rules_version), String(SET.bot_policy), String(SET.balance), String(SET.balance_name), String(SET.difficulty), String(SET.difficulty_name), String(SET.start), String(SET.mode), int(SET.days),
		str(SET.killXp), str(SET.bonusXp), String(SET.bossHpSet), ", ".join(boss_parts), String(SET.dayHpSet), String(SET.density_set) + " " + String(SET.density_set_name), str(SET.density_mult), int(SET.alive_cap), stop_txt]
	md += "생성: `tools/run_sim.gd` (Godot %s, %s). 전략 %d종 × 시드 %s. 경험치 필요치 %s+%sk+%sk². 봇 결과는 정책 비교용이며 사람의 체감 플레이타임·재미와 다르다. 머리말 값은 실제 회차·카탈로그에서 읽은 것(F8).\n\n" % [String(SET.engine), String(SET.os), strats.size(), _join(seeds, ","), str(SET.xp_base), str(SET.xp_step), str(SET.xp_quad)]
	md += "시간 계정(C19): 시뮬레이션된 시간 = 전투 + 보스(고정 단계 시계 1/120초). 가정한 메뉴 시간 = 카드 1장 %d초(전투 중 레벨업·지역 3택 포함, 실제 발생 시점에 기록) + 조우 전후 화면 %d초 + 사건 %d초 + 하루 종료 %d초 + 휴식 %d초. 합계는 보스전까지 포함해 마지막에 한 번만 더한다. 시간 초과(봇이 조우 %d초/보스 %d초 안에 못 끝냄)는 패배와 별도 열. 모든 행동은 PFlow.actions(run)의 항목으로만 실행(F1), 조우 생성·정산·3택·사건은 게임과 같은 PFlow/PEvents 경로.\n\n" % [int(M.card), int(M.encounter), int(M.event), int(M.dayEnd), int(M.rest), int(SET.encounter_max_sec), int(SET.boss_max_sec)]
	md += "전략:\n"
	for sid in strats:
		md += "- %s(%s): %s\n" % [String(STR[sid].name), String(sid), String(STR[sid].doc)]
	md += "\n## 회차별 결과\n\n| 전략 | 시드 | 레벨 | 레벨업/일 | 조우(패배/초과) | 휴식 | 더깊이(3택) | 임무(3택) | 사건(전투) | 카드(전투중) | 전투분 | 카드분 | 메뉴분(가정) | 보스분 | 합계분 | 무기2/무기3/E 시점(초) | 금화 | 보스 | 멈춤 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in all:
		md += "| %s | %d | %d | %s | %d(%d/%d) | %d | %d(%d) | %d(%d) | %d(%d) | %d(%d) | %s | %s | %s | %s | %s | %s/%s/%s | %d | %s | %s |\n" % [String(r.strategyName), int(r.seed), int(r.level), _join(r.levelUpsByDay), int(r.encounters), int(r.losses), int(r.timeouts), int(r.rests), int(r.deeps), int(r.deepPicks), int(r.missions), int(r.missionPicks), int(r.eventCount), int(r.eventFights), int(r.cards), int(r.cardsInCombat), str(r.combatMin), str(r.cardMin), str(r.menuMin), str(r.bossMin), str(r.totalMin), _n(r.weapon2), _n(r.weapon3), _n(r.eSkill), int(r.gold), String(r.boss) if String(r.boss) != "" else "-", String(r.stopReason)]
	md += "\n## 성장·전투 지표(전략 평균)\n\n전투력 선택 = 무기/공통/기술/패시브 선택 수, 서비스 = 거점 서비스 선택, 사망전 처치% = 첫 공격을 실행하기 전에 죽은 적 비율, 실행/스폰 = 적 1마리당 실행한 공격 수\n\n| 전략 | 레벨업 | 전투력 선택 | 임무 3택 | 더깊이 3택 | 사건 선택 | 희귀 선택 | 서비스 | 건너뜀 | 선택 간격 평균/중앙(초) | 첫 선택(초) | 무기2/무기3/E(초) | 사망전 처치% | 실행/스폰 | 받은 피해(조우) | 받은 피해(보스) | 휴식 | 보스 패턴(시작 횟수) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for sid in strats:
		var rows := _rows_of(all, String(sid))
		if rows.is_empty():
			continue
		md += "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s/%s | %s | %s/%s/%s | %s | %s | %s | %s | %s | %s |\n" % [String(STR[sid].name), str(_avg(rows, "level") - 1.0), str(_avg(rows, "combatPicks")), str(_avg(rows, "missionPicks")), str(_avg(rows, "deepPicks")), str(_avg(rows, "eventCount")), str(_avg(rows, "rarePicksN")), str(_avg(rows, "servicePicks")), str(_avg(rows, "skips")), str(_avg(rows, "pickGapAvg")), str(_avg(rows, "pickGapMed")), str(_avg(rows, "firstPickSec")), str(_avg(rows, "weapon2")), str(_avg(rows, "weapon3")), str(_avg(rows, "eSkill")), str(_avg(rows, "dbaPct")), str(_avg(rows, "execPerSpawn")), str(_avg(rows, "taken")), str(_avg(rows, "bossTaken")), str(_avg(rows, "rests")), _pat_text(rows)]
	md += "\n## 전략별 평균\n\n| 전략 | 레벨 | 1일차 레벨업 | 1일차 비중% | 조우 | 패배 | 초과 | 휴식 | 더깊이 3택 | 임무 | 사건 | 전투분 | 보스분 | 메뉴분(가정) | 합계분 | 금화 | 완주 | 보스 총초 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for sid in strats:
		var rows := _rows_of(all, String(sid))
		if rows.is_empty():
			continue
		var d1 := _avg_idx(rows, "levelUpsByDay", 0)
		var cleared := 0
		for r in rows:
			if bool(r.cleared):
				cleared += 1
		md += "| %s | %s | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d/%d | %s |\n" % [String(STR[sid].name), str(_avg(rows, "level")), str(d1), int(round(d1 / maxf(1.0, _avg(rows, "level") - 1.0) * 100.0)), str(_avg(rows, "encounters")), str(_avg(rows, "losses")), str(_avg(rows, "timeouts")), str(_avg(rows, "rests")), str(_avg(rows, "deepPicks")), str(_avg(rows, "missions")), str(_avg(rows, "eventCount")), str(_avg(rows, "combatMin")), str(_avg(rows, "bossMin")), str(_avg(rows, "menuMin")), str(_avg(rows, "totalMin")), str(_avg(rows, "gold")), cleared, rows.size(), str(_avg(rows, "bossSec"))]
	md += "\n## 보스 관문 결과(전략 × 시드)\n\n| 전략 | 시드 | 보스 | 단계 | 결과 | 초 | 남은 체력 | 보스 남은/최대 | 받은 피해 | Lv | 재도전 | 패턴(시작) |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in all:
		for b in r.bosses:
			var pp := []
			for k in b.patterns:
				pp.append("%s %d" % [String(k), int(b.patterns[k])])
			md += "| %s | %d | %s | %d | %s | %d | %d | %d/%d | %d | %d | %d | %s |\n" % [String(r.strategyName), int(r.seed), String(PCatalog.boss_def(String(b.id)).name), int(b.stage) + 1, String(b.status), int(b.sec), int(b.hp), int(b.bossHp), int(b.bossHpMax), int(b.taken), int(b.level), int(b.retries), ", ".join(pp)]
	md += "\n## 최종 빌드 예시(시드 %d)\n\n" % int(seeds[0])
	for sid in strats:
		for r in all:
			if String(r.strategy) == String(sid) and int(r.seed) == int(seeds[0]):
				md += "- %s: Lv%d · %s\n" % [String(STR[sid].name), int(r.level), String(r.build)]
	md += "\n## 경제: 하루 획득 금화(정산 기준, 사용분 포함)·구매·강화·예약·패배로 잃은 날\n\n| 전략 | 시드 | 하루 금화(평균) | 일별 | 총 사용 | 장비 | 새 기술 | 강화 | 예약 소비 | 심층 보상 | 패배로 잃은 날 | 최종 금화 |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	var EQ := PCatalog.equipment()
	for r in all:
		var eqn := []
		for id in r.equipBought:
			eqn.append(String(EQ[String(id)].name) if EQ.has(String(id)) else String(id))
		md += "| %s | %d | %d | %s | %d | %s | %d | %d | %d | %s | %d | %d |\n" % [String(r.strategyName), int(r.seed), int(r.goldPerDay), _join(r.goldEarnedByDay), int(r.goldSpent), ",".join(eqn) if eqn.size() > 0 else "-", int(r.skillsBought), int(r.forge), int(r.steered), String(r.deepRewardText) if String(r.deepRewardText) != "" else "-", int(r.daysLostToDefeat), int(r.gold)]
	md += "\n"
	for sid in strats:
		var rows := _rows_of(all, String(sid))
		if rows.is_empty():
			continue
		md += "- %s 평균: 하루 금화 %s · 사용 %s · 장비 %s개 · 강화 %s · 예약 %s · 패배로 잃은 날 %s\n" % [String(STR[sid].name), str(_avg(rows, "goldPerDay")), str(_avg(rows, "goldSpent")), str(_avg(rows, "equipN")), str(_avg(rows, "forge")), str(_avg(rows, "steered")), str(_avg(rows, "daysLostToDefeat"))]
	md += "\n## 날짜별: 레벨업 / 전투력 보상(경험치 외) / 전투초 / 받은 피해 / 휴식 / 금화 수입 / 지출 · 첫 구매 시점 · 남은 금화\n\n| 전략 | 시드 | 레벨업/일 | 보상/일 | 전투초/일 | 피해/일 | 휴식/일 | 수입/일 | 지출/일 | 첫 장비·강화·기술(일차) | 남은 금화 |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in all:
		var fb: Dictionary = r.firstBuy
		md += "| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s·%s·%s | %d |\n" % [String(r.strategyName), int(r.seed), _join(r.levelUpsByDay), _join(r.powerByDay), _join(r.combatSecByDay), _join(r.takenByDay), _join(r.restsByDay), _join(r.goldEarnedByDay), _join(r.spentByDay), _n(fb.get("equipment", null)), _n(fb.get("forge", null)), _n(fb.get("skill", null)), int(r.gold)]
	return md
