extends SceneTree
## 자동기술 중복 발사 검사(화면 없음):
##   godot --headless --path prophecy_godot -s tools/attack_audit.gd
## 결과: docs/sim/ATTACK_AUDIT.md
##
## 사용자 보고: "불씨 정령이 두 발씩 나가는 것 같다". 아직 버그로 확정하지 않는다.
## 이 도구는 자동기술 10종 전체에서 **정상 추가 공격**과 **의도치 않은 중복**을 구분한다.
##   base   = 기본 발사(간격 = stats.interval)
##   echo   = 공용 '메아리'가 4회마다 예약하는 지연 추가 공격(정상)
##   volley = 보스 보상 '일제 공격'이 E 사용 시 넣는 추가 공격(정상)
##   zone   = 장판(불길·서리 등)의 주기 피해. 개조로 장판 수가 늘어난다(정상)
##   dot    = 화상·출혈 등 지속 피해 틱(정상)
## 정상 증강 효과를 '한 발만 나가야 한다'는 이유로 제거하지 않는다.

const STEP := 1.0 / 120.0
const SECONDS := 20.0
const SEED := 7

## 검사할 자동기술과 개조(데이터 정본 data/weapons.json 순서)
const SKILLS := ["sword", "spear", "daggers", "bow", "hammer", "blades", "orb", "frost", "ember", "mine"]

## 부분 실행 축: skill(자동기술 id) · mode(normal·lowfps·pause·refresh)
## 예) PROPHECY_SUBSET="skill=ember,sword"
var sub := PSubset.new()
var rows := []
var notes := []

## 한 자동기술을 고정 상황에서 돌린다. 적은 죽지 않게 체력을 크게 두어
## '대상이 없어 발사가 멈추는' 상황과 중복 발사를 섞지 않는다.
func run_one(skill: String, mods: Array, commons: Dictionary, use_e: bool, mode: String = "normal") -> Dictionary:
	# 빌드: 실제 성장 경로 그대로 만든다(자동기술 1종 + 요청한 개조·공용)
	var run := PRun.new_run(SEED, skill)
	(run.growth.weapons as Array)[0] = { "id": skill, "level": 1, "mods": mods.duplicate() }
	run.growth.commons = commons.duplicate()
	if use_e:
		run.growth.skills.e = { "id": "gravity", "level": 1, "variant": null }
		(run.growth.bossRewards as Array).append("volley")
	# 실제 출격과 같은 경로로 전투를 만든다(첫 전투 전용 설정은 불길 장판 설정이 없어 쓰지 않는다)
	var b := PRun.build(run)
	var st := CombatState.new({ "build": b, "hp": float(b.hp_max), "seed": SEED,
		"waves": [[{ "type": "wolf", "n": 1 }]], "objective": "clear", "region_id": "forest",
		"pool": ["wolf"], "run": run })
	st.spawn_hold = true               # 새 등장 없음(승리 판정도 나지 않는다)
	for e in st.enemies:
		e.dead = true
	st.pending.clear()
	# 고정 표적 3마리를 사거리 안에 세운다(죽지 않게 체력 크게). 플레이어도 죽지 않게 둔다 —
	# 도중에 전투가 끝나면 발사 수가 잘려 중복 여부를 볼 수 없다
	for i in 3:
		var e := st.spawn_enemy("wolf", float(st.player.x) + 90.0 + float(i) * 40.0, float(st.player.y))
		e.hp = 1.0e9
		e.hp_max = 1.0e9
		e.speed = 0.0
	st.player.hp = 1.0e9
	st.player.hp_max = 1.0e9
	st.player.e_cd = 0.0
	st.metrics = CombatState._new_metrics()
	# 실행 방식
	#  normal  : 고정 단계(1/120초)
	#  lowfps  : 큰 단계(1/20초) — 프레임이 낮을 때 한 단계에서 여러 번 발사되는지 본다
	#  pause   : 5초마다 1초씩 단계를 아예 진행하지 않는다(일시정지). 재개 직후 몰아 발사되는지 본다
	#  refresh : 5초 시점에 전투 중 성장 반영(PWeapons.refresh)을 한 번 넣는다
	var dt := STEP if mode != "lowfps" else 1.0 / 20.0
	var n := int(SECONDS / dt)
	var run_sec := 0.0
	for i in n:
		if mode == "pause" and fmod(run_sec, 5.0) < 1.0 and run_sec > 1.0:
			run_sec += dt          # 시간만 흐르고 시뮬레이션은 진행하지 않는다
			continue
		if mode == "refresh" and absf(run_sec - 5.0) < dt * 0.5:
			PWeapons.refresh(st)
		var inp := { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false, "skill_e": use_e and i == int(5.0 / dt) }
		st.step(inp, dt)
		run_sec += dt
	var s: Dictionary = st.weapons[0].stats
	return {
		"skill": skill, "mods": mods.duplicate(), "commons": commons.duplicate(), "use_e": use_e, "mode": mode,
		"interval": float(s.get("interval", 0.0)), "kind": String(s.kind),
		"fires": st.metrics.cause_fires.duplicate(),
		"hits": st.metrics.cause_hits.duplicate(),
		"dmg": st.metrics.cause_dmg.duplicate(),
		"count": int(st.weapons[0].count),
	}

func _init() -> void:
	var WD: Dictionary = PCatalog.weapons()
	var skills: Array = sub.pick("skill", SKILLS)
	for skill in skills:
		var def: Dictionary = WD[skill]
		var mods := []   # data/weapons.json의 mods는 id를 키로 하는 사전이다
		for mid in (def.get("mods", {}) as Dictionary):
			if bool((def.mods[mid] as Dictionary).get("impl", false)):
				mods.append(String(mid))
		# (1) 무개조
		rows.append(run_one(skill, [], {}, false))
		# (2) 개조 하나씩
		for m in mods:
			rows.append(run_one(skill, [String(m)], {}, false))
		# (3) 공용 메아리
		rows.append(run_one(skill, [], { "echo": 1 }, false))
		# (4) 일제 공격(E 사용)
		rows.append(run_one(skill, [], {}, true))
		# (5) 저프레임 · 일시정지 후 재개 · 전투 중 성장 반영
		for md_mode in sub.pick("mode", ["lowfps", "pause", "refresh"]):
			rows.append(run_one(skill, [], {}, false, md_mode))
	print("ATTACK_AUDIT_JSON " + JSON.stringify(rows))

	var md := "# 자동기술 추가 공격·중복 공격 검사\n\n"
	md += "생성: `tools/attack_audit.gd` (%s, Godot %s). 고정 표적 3마리(죽지 않음)·%.0f초·시드 %d·이동 없음.\n" % [OS.get_name(), Engine.get_version_info().string, SECONDS, SEED]
	md += "적이 죽어 발사가 멈추는 상황과 중복 발사를 섞지 않으려고 표적 체력을 크게 두었다.\n\n"
	md += sub.describe("자동기술 추가 공격 검사") + "\n\n"
	md += "원인 구분: **base** 기본 발사 · **echo** 공용 메아리의 지연 추가 공격 · **volley** E 사용 시 일제 공격 · **zone** 장판 주기 피해 · **dot** 지속 피해 틱.\n\n"
	md += "## 기본 발사 주기 대조 (무개조)\n\n"
	md += "| 자동기술 | 종류 | 간격(초) | 이론 발사 수 | 실제 base 발사 | 판정 |\n|---|---|---|---:|---:|---|\n"
	for r in rows:
		if not (r.mods as Array).is_empty() or not (r.commons as Dictionary).is_empty():
			continue
		if String(r.mode) != "normal" or bool(r.use_e):
			continue
		var iv: float = float(r.interval)
		var want: int = int(floor(SECONDS / iv)) if iv > 0.0 else 0
		var got: int = int((r.fires as Dictionary).get("base", 0))
		var okv: bool = iv <= 0.0 or absf(float(got - want)) <= 2.0
		var shown := str(got)
		if String(r.kind) == "orbit":   # 공전 칼날은 주기 발사가 아니라 접촉 피해다
			okv = int((r.fires as Dictionary).get("orbit", 0)) > 0
			shown = "접촉 %d회(주기 발사 아님)" % int((r.fires as Dictionary).get("orbit", 0))
		elif String(r.kind) == "mine":  # 지뢰는 설치 → 폭발 구조다
			okv = int((r.fires as Dictionary).get("mine", 0)) > 0
			shown = "폭발 %d회 / 설치 %d회" % [int((r.fires as Dictionary).get("mine", 0)), int(r.count)]
		md += "| %s | %s | %.2f | %d | %s | %s |\n" % [r.skill, r.kind, iv, want, shown, "일치" if okv else "**차이**"]
		if not okv:
			notes.append("%s: 기본 발사 %d회(이론 %d회)" % [r.skill, got, want])
	md += "\n## 개조·공용별 원인 분해\n\n"
	md += "| 자동기술 | 개조/공용 | base | echo | volley | 공전 | 지뢰 | 직접 명중 | 장판 피해 | 지속 피해 | 총 피해 |\n|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
	for r in rows:
		if String(r.mode) != "normal" or bool(r.use_e):
			continue   # 실행 방식 비교는 아래 표에서 따로 본다
		var tag := "무개조"
		if not (r.mods as Array).is_empty():
			tag = String((r.mods as Array)[0])
		elif not (r.commons as Dictionary).is_empty():
			tag = "공용:메아리"
		var f: Dictionary = r.fires
		var h: Dictionary = r.hits
		var d: Dictionary = r.dmg
		var total := 0.0
		for k in d:
			total += float(d[k])
		md += "| %s | %s | %d | %d | %d | %d | %d | %d | %.0f | %.0f | %.0f |\n" % [r.skill, tag,
			int(f.get("base", 0)), int(f.get("echo", 0)), int(f.get("volley", 0)),
			int(f.get("orbit", 0)), int(f.get("mine", 0)),
			int(h.get("base", 0)) + int(h.get("echo", 0)),
			float(d.get("zone", 0.0)), float(d.get("dot", 0.0)), total]
	md += "\n## 일시정지·저프레임·전투 중 성장 반영에서의 중복 여부 (무개조)\n\n"
	md += "| 자동기술 | 정상 base | 저프레임(1/20초) | 일시정지 후 재개 | 전투 중 성장 반영 | 일제 공격 사용 시 volley |\n|---|---:|---:|---:|---:|---:|\n"
	for skill2 in skills:
		var by := {}
		for r2 in rows:
			if String(r2.skill) != skill2 or not (r2.mods as Array).is_empty() or not (r2.commons as Dictionary).is_empty():
				continue
			by[String(r2.mode) + ("+e" if bool(r2.use_e) else "")] = r2
		var base_n := int(((by.get("normal", {}) as Dictionary).get("fires", {}) as Dictionary).get("base", 0))
		var low_n := int(((by.get("lowfps", {}) as Dictionary).get("fires", {}) as Dictionary).get("base", 0))
		var pau_n := int(((by.get("pause", {}) as Dictionary).get("fires", {}) as Dictionary).get("base", 0))
		var ref_n := int(((by.get("refresh", {}) as Dictionary).get("fires", {}) as Dictionary).get("base", 0))
		var vol_n := int(((by.get("normal+e", {}) as Dictionary).get("fires", {}) as Dictionary).get("volley", 0))
		md += "| %s | %d | %d | %d | %d | %d |\n" % [skill2, base_n, low_n, pau_n, ref_n, vol_n]
		if low_n > base_n:
			notes.append("%s: 저프레임에서 발사 수가 늘었다(정상 %d → 저프레임 %d)" % [skill2, base_n, low_n])
		if pau_n > base_n:
			notes.append("%s: 일시정지 후 재개에서 발사 수가 늘었다(정상 %d → %d)" % [skill2, base_n, pau_n])
		if ref_n > base_n:
			notes.append("%s: 전투 중 성장 반영 뒤 발사 수가 늘었다(정상 %d → %d)" % [skill2, base_n, ref_n])
		if vol_n > 1:
			notes.append("%s: E 한 번에 일제 공격이 %d회 들어갔다(1회여야 한다)" % [skill2, vol_n])
	md += "\n일시정지는 시뮬레이션 단계를 아예 진행하지 않는 방식이라 총 진행 시간이 줄어든다. 그래서 발사 수가 **적게** 나오는 것은 정상이고, **많아지면** 비정상이다.\n"
	md += "\n## 이 설정에서 차이가 보이지 않은 개조\n\n"
	md += "표적 3마리가 붙어 서 있고 플레이어가 움직이지 않는 정지 상황이라, 위치·이동·표적 수에 의존하는 개조는 차이가 나타나지 않는다. "
	md += "아래 개조는 **효과가 없다는 뜻이 아니라 이 검사로는 볼 수 없다는 뜻**이다.\n\n"
	for r3 in rows:
		if (r3.mods as Array).is_empty() or String(r3.mode) != "normal":
			continue
		var base_row := {}
		for r4 in rows:
			if String(r4.skill) == String(r3.skill) and (r4.mods as Array).is_empty() and (r4.commons as Dictionary).is_empty() and String(r4.mode) == "normal" and not bool(r4.use_e):
				base_row = r4
		if base_row.is_empty():
			continue
		var t3 := 0.0
		var t4 := 0.0
		for k in (r3.dmg as Dictionary):
			t3 += float(r3.dmg[k])
		for k in (base_row.dmg as Dictionary):
			t4 += float(base_row.dmg[k])
		if absf(t3 - t4) < 0.5:
			md += "- %s / %s: 무개조와 총 피해가 같다(%.0f)\n" % [r3.skill, String((r3.mods as Array)[0]), t3]
	md += "\n## 읽는 법\n\n"
	md += "- **base 발사 수가 이론값과 같으면** 그 자동기술은 한 주기에 한 번만 발사한다. 화면에 여러 발로 보이는 것은 개조가 한 발에서 만드는 투사체·장판이다.\n"
	md += "- **공전 칼날(blades)과 지뢰(mine)는 주기 발사 구조가 아니다.** 공전은 접촉할 때마다 피해를 주고(같은 적은 hit_gap만큼 쉬었다가), 지뢰는 설치했다가 나중에 터진다. 그래서 base 열이 0인 것이 정상이다.\n"
	md += "- **echo 열이 0이 아닌 행은 공용 '메아리'를 켠 행뿐이어야 한다.** 다른 행에 echo가 있으면 비정상이다.\n"
	md += "- **장판 피해**는 발사 수가 아니라 장판 수·지속시간에 비례한다. 불씨 정령의 `scatter`(3장판)·`trail`(+2장판)은 정상이며, 이것이 '두 발처럼 보이는' 화면의 원인 후보다.\n"
	md += "- 이 표는 **연출이 아니라 실제 피해**를 센다. 연출만 겹치는 경우는 여기 나타나지 않는다.\n"
	if notes.is_empty():
		md += "\n## 결과\n\n검사 범위에서 **기본 발사 주기 이상 없음**. 확인한 추가 공격은 전부 정상 경로(메아리·일제 공격·개조 파생·장판 틱)였다.\n"
	else:
		md += "\n## 결과: 확인이 필요한 항목\n\n"
		for nt in notes:
			md += "- %s\n" % nt
	var fh := FileAccess.open((sub.out_path("res://docs/sim/ATTACK_AUDIT.md")), FileAccess.WRITE)
	fh.store_string(md)
	fh.close()
	quit()
