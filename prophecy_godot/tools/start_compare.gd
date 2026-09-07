extends SceneTree
## 시작 자동기술 3종 집중 비교(HTML tools/start_compare.js 이식, 헤드리스). 같은 시드·같은 정책을 짝지어 비교한다.
##  A 첫 전투(1일차 첫 카드 = 근교 숲, Lv1, 개조·장비 없음): PRun.new_run → PSortie.start(오늘의 첫 카드) → PFlow.make_encounter → PBot.run_combat
##  B 첫날 전체(점진 전략, 체력 30% 미만이면 휴식, 봇 성장 선택): PRunBot.simulate(max_days=1)
##  D(첫 보스, run_sim 덤프 빌드)는 덤프 파일이 없어 옮기지 않았다. 보스는 tools/boss_sim.gd.
## 사용: PROPHECY_SIM_SEEDS=100,101 godot --headless --path prophecy_godot -s tools/start_compare.gd
## 환경 변수: PROPHECY_SIM_SEEDS("100,...,104") PROPHECY_SIM_BOT(정책 목록, "balanced,aware") PROPHECY_SIM_OUT(res://docs/sim/START_COMPARE.md)

const STARTS := ["sword", "spear", "blades"]
const MAX_SEC := 180.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _list(s: String) -> Array:
	var out := []
	for p in s.split(","):
		var t := String(p).strip_edges()
		if t != "":
			out.append(t)
	return out

func fight_stats(st: CombatState) -> Dictionary:
	var sm := st.summary()
	var spawned := 0
	var executed := 0
	var dba := 0
	var killed := 0
	for k in sm.enemies:
		var m: Dictionary = sm.enemies[k]
		spawned += int(m.get("spawned", 0))
		executed += int(m.get("executed", 0))
		dba += int(m.get("died_before_attack", 0))
		killed += int(m.get("killed", 0)) + int(m.get("exploded", 0))
	var hits := int(sm.hits)
	var by_key := {}
	for k in sm.dmg:
		by_key[String(k)] = float(sm.dmg[k])
	return { "status": st.status, "t": round(st.t * 10.0) / 10.0, "taken": round(float(sm.damage_taken)), "hits": hits, "hitsPerSec": (round(float(hits) / st.t * 100.0) / 100.0) if st.t > 0.0 else 0.0,
		"dbaPct": int(round(float(dba) / float(killed) * 100.0)) if killed > 0 else 0, "spawned": spawned, "executed": executed, "kills": int(sm.kills), "hp": round(float(sm.hp)), "dmg": by_key, "dmgTotal": float(sm.dmg_total), "level_ups": int(sm.level_ups) }

## A. 첫 전투
func first_fight(seed: int, start: String, pol: String) -> Dictionary:
	var run := PRun.new_run(seed, start)
	var cards := PSortie.cards_for(run)
	var s := PSortie.start(run, String(cards[0].id))
	if s.is_empty():
		return {}
	var st := PFlow.make_encounter(run, s)
	PBot.run_combat(st, pol, { "max_sec": MAX_SEC })
	if st.status == "running":
		st.status = "timeout"
		st.delayed.clear()
	var f := fight_stats(st)
	f.region = String(s.regionId)
	f.seed = seed
	f.start = start
	f.pol = pol
	f.balance = String(run.balance)
	return f

func _avg(l: Array, key: String) -> String:
	if l.is_empty():
		return "-"
	var s := 0.0
	for r in l:
		var v = (r as Dictionary).get(key, 0)
		s += float(v) if v != null else 0.0
	return str(round(s / float(l.size()) * 10.0) / 10.0)

func _count(l: Array, key: String, val: String) -> int:
	var n := 0
	for r in l:
		if String(r[key]) == val:
			n += 1
	return n

func _filter(l: Array, pol: String, start: String) -> Array:
	var out := []
	for r in l:
		if String(r.pol) == pol and String(r.start) == start:
			out.append(r)
	return out

func _dmg_text(l: Array) -> String:
	var s := {}
	for r in l:
		for k in r.dmg:
			s[String(k)] = float(s.get(String(k), 0.0)) + float(r.dmg[k])
	var tot := 0.0
	for k in s:
		tot += float(s[k])
	var keys := s.keys()
	keys.sort_custom(func(a, b): return float(s[a]) > float(s[b]))
	var parts := []
	for k in keys.slice(0, 4):
		parts.append("%s %d%%" % [String(PStats.classify(String(k)).name), int(round(float(s[k]) / maxf(1.0, tot) * 100.0))])
	return ", ".join(parts)

func _pn(p: String) -> String:
	return String(PBot.policies()[p].name) if PBot.policies().has(p) else p

func _wn(id: String) -> String:
	return String(PCatalog.weapon(id).name)

func _init() -> void:
	var seeds := []
	for s in _list(_env("PROPHECY_SIM_SEEDS", "100,101,102,103,104")):
		if s.is_valid_int():
			seeds.append(int(s))
	var pols := []
	for p in _list(_env("PROPHECY_SIM_BOT", "balanced,aware")):
		if PBot.policies().has(p) or p == "stand" or p == "active":
			pols.append(p)
	var out_path := _env("PROPHECY_SIM_OUT", "res://docs/sim/START_COMPARE.md")
	var SET := PRunBot.settings({ "start": "sword", "bot_policy": pols[0] if pols.size() > 0 else "balanced" })
	printerr("start_compare: seeds=%s policies=%s balance=%s difficulty=%s" % [str(seeds), str(pols), String(SET.balance), String(SET.difficulty)])
	var A := []
	var B := []
	var t_all := Time.get_ticks_msec()
	for pol in pols:
		for seed in seeds:
			for start in STARTS:
				var a = first_fight(int(seed), String(start), String(pol))
				if a is Dictionary and not (a as Dictionary).is_empty():
					A.append(a)
				else:
					printerr("FAIL A %s %s seed %d" % [String(pol), String(start), int(seed)])
				var L = PRunBot.simulate(int(seed), "gradual", { "start": String(start), "bot_policy": String(pol), "max_days": 1 })
				if L is Dictionary and not (L as Dictionary).is_empty():
					var r: Dictionary = L
					B.append({ "pol": String(pol), "seed": int(seed), "start": String(start), "fights": int(r.encounters), "wins": int(r.encounters) - int(r.losses) - int(r.timeouts), "losses": int(r.losses), "timeouts": int(r.timeouts), "rests": int(r.rests),
						"levelUps": int(r.level) - 1, "t": int(r.combatSec), "taken": float(r.taken), "dbaPct": int(r.dbaPct), "execPerSpawn": float(r.execPerSpawn), "gold": int(r.gold), "hp": float(r.hpBeforeBoss), "cards": int(r.cards), "build": String(r.build) })
				else:
					printerr("FAIL B %s %s seed %d" % [String(pol), String(start), int(seed)])
			printerr("done %s seed %d (%d ms)" % [String(pol), int(seed), Time.get_ticks_msec() - t_all])
	var md := "# 시작 자동기술 3종 집중 비교 (%s, Godot %s, %s, 밸런스 %s(%s), 난이도 %s, 처치 경험치 ×%s, 밀도 배율 ×%s, 시드 %d개 짝지음 %s, 정책 %s)\n\n" % [String(SET.rules_version), String(SET.engine), String(SET.os), String(SET.balance), String(SET.balance_name), String(SET.difficulty), str(SET.killXp), str(SET.density_mult), seeds.size(), str(seeds), " / ".join(pols.map(_pn))]
	md += "생성: `tools/start_compare.gd`. 봇 결과는 정책 비교용이며 사람 승률·재미 승인이 아니다. '기술 특성 이해' 정책은 균형 정책에 거리 규칙만 더한 것(회전 칼날: 살 중간, 관통창: 근접 약화 밖). 첫 전투 상한 %d초.\n" % int(MAX_SEC)
	md += "\n## A. 첫 전투(1일차 첫 카드 %s, Lv1, 개조·장비 없음)\n\n| 정책 | 자동기술 | 승/패/초과 | 평균 초 | 받은 피해 | 남은 체력 | 명중/초 | 공격 전 사망%% | 적 공격 실행/전투 | 등장 | 피해 기여 |\n|---|---|---|---|---|---|---|---|---|---|---|\n" % [String(PRun.region(String(A[0].region)).name) if A.size() > 0 else "근교 숲"]
	for pol in pols:
		for start in STARTS:
			var l := _filter(A, String(pol), String(start))
			md += "| %s | %s | %d/%d/%d | %s | %s | %s | %s | %s | %s | %s | %s |\n" % [_pn(String(pol)), _wn(String(start)), _count(l, "status", "won"), _count(l, "status", "lost"), _count(l, "status", "timeout"), _avg(l, "t"), _avg(l, "taken"), _avg(l, "hp"), _avg(l, "hitsPerSec"), _avg(l, "dbaPct"), _avg(l, "executed"), _avg(l, "spawned"), _dmg_text(l)]
	if pols.size() > 0:
		md += "\n### A. 시드별 짝 비교(%s 정책): 결과 전투 초 / 받은 피해\n\n| 시드 | %s | %s | %s |\n|---|---|---|---|\n" % [_pn(String(pols[0])), _wn("sword"), _wn("spear"), _wn("blades")]
		for seed in seeds:
			var cells := []
			for start in STARTS:
				var cell := "-"
				for r in A:
					if String(r.pol) == String(pols[0]) and int(r.seed) == int(seed) and String(r.start) == String(start):
						cell = "%s%ss / %d" % [("" if String(r.status) == "won" else String(r.status) + " "), str(r.t), int(r.taken)]
				cells.append(cell)
			md += "| %d | %s | %s | %s |\n" % [int(seed), cells[0], cells[1], cells[2]]
	md += "\n## B. 첫날 전체(점진 전략: 오늘의 카드 순서, 체력 30% 미만이면 휴식, 봇 성장 선택; PRunBot max_days=1)\n\n| 정책 | 자동기술 | 전투 | 승/패/초과 | 휴식 | 레벨업 | 카드 | 전투 초 합 | 받은 피해 합 | 공격 전 사망% | 실행/스폰 | 정산 금화 | 하루 끝 체력 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for pol in pols:
		for start in STARTS:
			var l := _filter(B, String(pol), String(start))
			md += "| %s | %s | %s | %s/%s/%s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % [_pn(String(pol)), _wn(String(start)), _avg(l, "fights"), _avg(l, "wins"), _avg(l, "losses"), _avg(l, "timeouts"), _avg(l, "rests"), _avg(l, "levelUps"), _avg(l, "cards"), _avg(l, "t"), _avg(l, "taken"), _avg(l, "dbaPct"), _avg(l, "execPerSpawn"), _avg(l, "gold"), _avg(l, "hp")]
	md += "\nD(첫 보스, run_sim 덤프의 3일차 관문 빌드)는 덤프 파일이 없어 생략. 고정 빌드 보스전은 `tools/boss_sim.gd`(docs/sim/BOSS_SIM.md).\n"
	var dir := ProjectSettings.globalize_path(out_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	else:
		printerr("쓰기 실패: " + out_path)
	print("START_COMPARE_JSON " + JSON.stringify({ "settings": SET, "seeds": seeds, "policies": pols, "A": A, "B": B }))
	printerr("start_compare: A=%d B=%d in %d ms → %s" % [A.size(), B.size(), Time.get_ticks_msec() - t_all, out_path])
	quit(0)
