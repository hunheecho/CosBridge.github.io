extends SceneTree
## 전체 이식 규칙 테스트(화면 없음): godot --headless --path prophecy_godot -s tests/port_tests.gd
## HTML test/*.test.js의 규칙 케이스를 Godot 규칙으로 다시 쓴 것. 기대값은 명세(GAME_SPEC·growth_data)에서 오며 구현 결과를 베끼지 않는다.
## 첫 전투(D33) 케이스는 tests/run_tests.gd(72)에 그대로 있다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 성장 상태로 전투 생성(적 없음, 공터 없이 빈 전장). weapons: [{id, level, mods}], commons{}, passives{}, e{id,level,variant}, q{level,variant}, equipment{}, forge
func mk(o: Dictionary = {}) -> CombatState:
	var g := PGrowth.new_growth(String(o.get("start", "sword")))
	if o.has("weapons"):
		g.weapons = []
		for w in o.weapons:
			g.weapons.append({ "id": String(w.id), "level": int(w.get("level", 1)), "mods": (w.get("mods", []) as Array).duplicate() })
	if o.has("commons"):
		g.commons = o.commons.duplicate()
	if o.has("passives"):
		g.passives = o.passives.duplicate()
	if o.has("e"):
		g.skills.e = { "id": String(o.e.id), "level": int(o.e.get("level", 1)), "variant": o.e.get("variant", null) }
	if o.has("q"):
		g.skills.q = { "id": "slowfield", "level": int(o.q.get("level", 1)), "variant": o.q.get("variant", null) }
	if o.has("rewards"):
		g.bossRewards = (o.rewards as Array).duplicate()
	var run := PBuild.empty_run_like(g)
	if o.has("equipment"):
		for k in o.equipment:
			run.equipment[k] = o.equipment[k]
	if o.has("forge"):
		run.forge = int(o.forge)
	run.balance = String(o.get("balance", "current"))
	var b := PBuild.derive(run)
	var st := CombatState.new({ "build": b, "seed": int(o.get("seed", 1)), "arena": String(o.get("arena", "forest")), "formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} }, "region_id": String(o.get("region", "forest")), "hp": float(o.get("hp", b.hp_max)), "xp_kill_mult": 0.3 })
	st.spawn_hold = true
	return st

func steps(st: CombatState, seconds: float, input: Dictionary = {}, dt: float = STEP) -> void:
	var n := int(round(seconds / dt))
	for i in n:
		st.step(input, dt)

## 적을 제자리에 고정한 채 진행(HTML 테스트의 pins): 접근 이동을 무시하고 위치 규칙만 본다
func steps_pinned(st: CombatState, seconds: float, pins: Array, input: Dictionary = {}) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		st.step(input, STEP)
		for pin in pins:
			var e: Dictionary = pin[0]
			e.x = float(pin[1]); e.y = float(pin[2]); e.vx = 0.0; e.vy = 0.0

## 공격하지 않는 표적(체력 큰 늑대)
func dummy(st: CombatState, x: float, y: float, hp: float = 99999.0) -> Dictionary:
	var e := st.spawn_enemy("wolf", x, y)
	e.hp = hp
	e.hp_max = hp
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

func total_dmg(st: CombatState) -> float:
	var s := 0.0
	for k in st.metrics.dmg:
		s += float(st.metrics.dmg[k])
	return s

func _init() -> void:
	var W := PCatalog.weapons()
	var CM := PCatalog.commons()
	var PS := PCatalog.passives()
	var SK := PCatalog.skills()
	var EQ := PCatalog.equipment()
	# 주무기·보조 분리(2026-09-08): 주무기 5 + 보조 12 = 17종, 개조는 종당 3개로 51개.
	# 옛 값(10종·30개)은 보조 7종·개조 21개가 늘기 전의 수다.
	ok("카탈로그: 자동기술 17(주무기 5·보조 12)·개조 51·공용 9·패시브 8·E 5·변형 10·Q 변형 3·희귀 6·장비 12", W.size() == 17 and _mod_count(W) == 51 and CM.size() == 9 and PS.size() == 8 and PCatalog.e_skills().size() == 5 and _variant_count(SK) == 13 and PCatalog.boss_rewards().size() == 6 and EQ.size() == 12, "무기 %d mods %d variants %d" % [W.size(), _mod_count(W), _variant_count(SK)])
	var n_main := 0
	var n_sup := 0
	for wid in W:
		if PCatalog.is_main_weapon(String(wid)):
			n_main += 1
		else:
			n_sup += 1
	ok("역할 구분: 주무기 5종·보조 12종, 모든 자동기술에 역할이 있다", n_main == 5 and n_sup == 12, "주무기 %d 보조 %d" % [n_main, n_sup])
	# ---------- 빌드 파생(HTML 117·147): 레벨 배율 누적, 강화·숙련·가속·넓어진 공격이 한 번씩 ----------
	var st := mk({ "weapons": [{ "id": "spear", "level": 3 }], "passives": { "mastery": 2, "haste": 1 }, "forge": 2, "commons": { "wide": 1 } })
	var s0: Dictionary = st.build.weapons[0]
	# 2026-09-08 성장 개편: 레벨 배율 1/1.35/1.8/2.35/3.0, 대장간은 기술별 강화(run.forgeBySkill).
	# 이 빌드는 옛 전체 강화(forge:2)만 있고 회차가 아니라 growth 전용이라, 대장간 배율은 옛 저장 호환 경로로 그 기술에 붙는다.
	# 창 Lv3 = 14 × 1.8(레벨) × 1.2(강화2 = 옛 저장 호환) × 1.2(숙련2) = 36.29
	ok("빌드 파생: 창 Lv3 피해 14×1.8(레벨)×1.2(강화2·옛 저장 호환)×1.2(숙련2)=36.29, 주기 0.7×0.92, 폭 44×1.25", is_equal_approx(snapped(float(s0.damage), 0.01), 36.29) and is_equal_approx(snapped(float(s0.interval), 0.001), 0.644) and is_equal_approx(float(s0.width), 55.0), "dmg %.2f int %.3f w %.1f" % [float(s0.damage), float(s0.interval), float(s0.width)])
	st = mk({ "weapons": [{ "id": "sword", "level": 5 }], "commons": { "wide": 2, "reach": 2 } })
	s0 = st.build.weapons[0]
	ok("검 Lv5 배율 3.0(성장 개편), 넓어진 2단계: 각도 110×1.5=165 반지름 95×1.5×1.25", is_equal_approx(float(s0.damage), 36.0) and is_equal_approx(float(s0.arc_deg), 165.0) and is_equal_approx(float(s0.range), 95.0 * 1.5 * 1.25), "%.1f %.1f %.1f" % [float(s0.damage), float(s0.arc_deg), float(s0.range)])
	ok("창 근접 약화·주기 0.85는 test03 세트에서만", is_equal_approx(float(mk({ "start": "spear", "balance": "test03" }).build.weapons[0].interval), 0.85) and is_equal_approx(float(mk({ "start": "spear" }).build.weapons[0].interval), 0.7))
	# ---------- 자동기술 10종: 각각 사거리 안의 표적을 실제로 때린다(HTML 50·52·53) ----------
	for wid in ["sword", "spear", "daggers", "bow", "hammer", "blades", "orb", "frost", "ember", "mine"]:
		st = mk({ "weapons": [{ "id": wid }] })
		var d: Dictionary = W[wid]
		var e := dummy(st, st.player.x + 60.0, st.player.y)
		var e2 := dummy(st, st.player.x + 60.0 + 40.0, st.player.y + 30.0)
		steps(st, 6.0)
		var dealt := total_dmg(st)
		var key: String = "weapon:" + String(wid)
		ok("자동기술 %s(%s): 6초 안에 표적 피해 > 0, 출처 %s" % [String(d.name), String(d.kind), key], dealt > 0.0 and st.metrics.dmg.has(key) and float(st.metrics.dmg[key]) > 0.0, "dealt %.1f keys %s hits %d" % [dealt, str(st.metrics.dmg.keys()), st.stats.hits])
	# 검격: 한 검격에 적당 1회(HTML 50), 사거리 밖은 대기(허공 공격 없음)
	st = mk({ "weapons": [{ "id": "sword" }] })
	steps(st, 3.0)
	ok("사거리 안에 적이 없으면 검격이 발동하지 않는다", st.stats.attacks == 0)
	var eA := dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.5)
	ok("검격 한 번에 적당 1회 피해 12", st.stats.attacks == 1 and is_equal_approx(float(st.metrics.dmg["weapon:sword"]), 12.0), "attacks %d dmg %s" % [st.stats.attacks, str(st.metrics.dmg)])
	# 관통창: 일렬 3마리 모두(HTML 52), 사거리 230
	st = mk({ "weapons": [{ "id": "spear" }] })
	for i in 3:
		dummy(st, st.player.x + 60.0 + 60.0 * float(i), st.player.y)
	steps(st, 0.5)
	ok("관통창은 일렬로 선 적 3마리를 한 번에 타격", is_equal_approx(float(st.metrics.dmg["weapon:spear"]), 42.0) and st.stats.hits == 3, "dmg %s hits %d" % [str(st.metrics.dmg), st.stats.hits])
	# 회전 칼날: 살 판정(반지름 35%~100%)에 붙은 적도 맞고 접촉 주기 0.35(HTML 10·53·69)
	st = mk({ "weapons": [{ "id": "blades" }] })
	var eb := dummy(st, st.player.x + 40.0, st.player.y)
	steps(st, 2.0)
	var blade_hits: int = int(st.metrics.hits.get("blades", 0))
	ok("회전 칼날: 궤도 안쪽(40)에 붙은 적을 살 판정으로 치고 2초 동안 ≤ 6회(주기 0.35)", blade_hits >= 3 and blade_hits <= 6, "hits %d" % blade_hits)
	st = mk({ "weapons": [{ "id": "blades", "mods": ["dual"] }] })
	steps(st, 0.1)
	ok("세 번째 칼날 개조 = 같은 궤도에 칼날 +1", (st.weapons[0].blade_pos as Array).size() == 3)
	# 메아리(HTML 53·66): 4번째 공격 0.2초 뒤 반복, 메아리는 메아리를 만들지 않음
	st = mk({ "weapons": [{ "id": "sword" }], "commons": { "echo": 1 } })
	dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.55 * 4.0 + 0.5)
	ok("메아리: 2.7초 동안 검격 5회(0.25/0.8/1.35/1.9/2.45) + 4번째의 메아리 1회 = 명중 6", st.stats.attacks == 5 and st.stats.hits == 6, "hits %d attacks %d" % [st.stats.hits, st.stats.attacks])
	# ---------- 공용 증강 ----------
	st = mk({ "weapons": [{ "id": "sword" }], "commons": { "frost": 1 } })
	var ef := dummy(st, st.player.x + 50.0, st.player.y, 10.0)
	steps(st, 0.35)
	var shards := 0
	for pr in st.projectiles:
		if pr.kind == "shard_common":
			shards += 1
	ok("얼음 파편: 냉기 상태 처치 시 파편 6개, 파편은 냉기를 다시 주지 않음", ef.dead and shards == 6 and float(ef.chill) > 0.0, "shards %d chill %.1f" % [shards, float(ef.chill)])
	st = mk({ "weapons": [{ "id": "sword" }], "commons": { "burn": 1 } })
	var eb2 := dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.3)
	var burn_t0: float = float(eb2.burn.t) if not eb2.burn.is_empty() else -1.0
	steps(st, 2.2)
	var burn_dmg: float = float(st.metrics.dmg.get("dot:burn@sword", 0.0))
	ok("불붙은 공격: 화상 2초·초당 4, 0.5초 틱, 출처 dot:burn@sword, 시간만 갱신(중첩 없음)", burn_t0 >= 1.9 and burn_dmg >= 6.0 and burn_dmg <= 10.0, "t0 %.2f dmg %.1f keys %s" % [burn_t0, burn_dmg, str(st.metrics.dmg.keys())])
	st = mk({ "weapons": [{ "id": "sword" }], "commons": { "ember": 1, "flare": 1 } })
	st.step({ "mx": 1.0, "dodge_press": true, "dodge_held": true }, STEP)
	steps(st, 0.3, { "dodge_held": true })
	var fires := 0
	for z in st.zones:
		if z.type == "fire":
			fires += 1
	ok("잔불 걸음: 회피 경로에 불길 3개(판정 성공과 무관)", fires == 3, "fires %d" % fires)
	var ez := dummy(st, st.player.x - 50.0, st.player.y, 5.0) # 마지막 불길 조각(회피 100px 지점) 위
	var ez2 := dummy(st, st.player.x - 20.0, st.player.y, 100.0)
	steps(st, 0.5)
	ok("불꽃 파열: 불길 위 처치 시 반지름 80 폭발 20(출처 common:flare)", ez.dead and st.metrics.dmg.has("common:flare") and float(st.metrics.dmg["common:flare"]) == 20.0, "keys %s" % str(st.metrics.dmg))
	st = mk({ "weapons": [{ "id": "sword" }], "commons": { "saving": 1, "stasis": 1 } })
	var es := dummy(st, st.player.x + 50.0, st.player.y, 24.0)
	st.step({ "special": true }, STEP)
	var cd0: float = st.player.special_cd
	steps(st, 1.2)
	ok("시간 저축: 감속장 안 처치 1마리당 재사용 -1초(정확히): 14 - 1.2 - 1 = 11.8", es.dead and absf(st.player.special_cd - 11.8) < 1e-6, "cd %.3f (0 %.3f)" % [st.player.special_cd, cd0])
	var es2 := dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 3.0)
	var stas: float = float(st.metrics.dmg.get("common:stasis", 0.0))
	ok("정지된 칼날: 감속장 안 적중마다 흔적(최대 5), 종료 시 흔적×10 폭발(출처 common:stasis, 남은 1.8초 동안 3~5회 적중)", st.field.is_empty() and stas >= 30.0 and stas <= 50.0 and is_equal_approx(fmod(stas, 10.0), 0.0) and int(es2.stasis) == 0, "keys %s stasis %d" % [str(st.metrics.dmg), int(es2.stasis)])
	# ---------- 패시브 ----------
	st = mk({ "passives": { "vitality": 2, "toughness": 1, "mobility": 1, "focus": 1, "exploit": 2, "persistence": 1 } })
	ok("패시브: 건강 +40, 기동 ×1.08, 집중 감속장 12.6, 빈틈 2.0, 지속력 ×1.2", is_equal_approx(float(st.build.hp_max), 140.0) and is_equal_approx(float(st.build.speed_mult), 1.08) and is_equal_approx(float(st.build.special_cd), 12.6) and is_equal_approx(float(st.build.exposed_mult), 2.0) and is_equal_approx(float(st.build.duration_mult), 1.2), "%s" % str([st.build.hp_max, st.build.speed_mult, st.build.special_cd, st.build.exposed_mult]))
	st.damage_player(20.0, "wolf:bite")
	ok("강인함: 직접 피해 20 → 18(−10%), 지역 피해는 그대로", is_equal_approx(st.stats.damage_taken, 18.0))
	st.player.hit_prot = 0.0
	st.zone_damage(6.0)
	ok("지역 피해는 강인함 미적용·피격 보호 무시", is_equal_approx(st.stats.damage_taken, 24.0), "%.1f" % st.stats.damage_taken)
	# ---------- Q 변형·E 기술 ----------
	st = mk({ "q": { "level": 3, "variant": "follow" } })
	st.step({ "special": true }, STEP)
	var fx0: float = st.field.x
	steps(st, 0.5, { "mx": 1.0 })
	ok("감속장 Lv3 재사용 10초, 동행하는 시간은 플레이어를 따라온다", is_equal_approx(float(st.build.special_cd), 10.0) and st.field.x > fx0 + 50.0, "cd %.1f dx %.1f" % [float(st.build.special_cd), st.field.x - fx0])
	st = mk({ "q": { "level": 1, "variant": "echo" } })
	st.step({ "special": true }, STEP)
	steps(st, 3.1)
	var echo_zone := false
	for z in st.zones:
		if z.type == "slowecho":
			echo_zone = true
	ok("시간의 잔향: 감속장 종료 뒤 70% 감속 영역", echo_zone and st.field.is_empty())
	for eid in ["gust", "bladestorm", "strike", "gravity", "ward"]:
		st = mk({ "weapons": [{ "id": "sword" }], "e": { "id": eid, "level": 2 } })
		st.player.attack_timer = 1.0e9
		var et := dummy(st, st.player.x + 80.0, st.player.y)
		var hp_before: float = et.hp
		var sh0: float = st.player.shield
		st.step({ "skill_e": true }, STEP)
		steps(st, 1.5)
		var used: bool = st.stats.e_uses == 1 and st.player.e_cd > 0.0
		var effect: bool = (et.hp < hp_before) if eid != "ward" else (st.player.shield > sh0 or float(st.player.ward_shield) > 0.0)
		ok("E %s Lv2: 발동·재사용·실제 효과(피해 또는 보호막)" % String(SK[eid].name), used and effect, "e_uses %d cd %.1f hp %.1f→%.1f shield %.1f" % [st.stats.e_uses, st.player.e_cd, hp_before, et.hp, st.player.shield])
	st = mk({ "weapons": [{ "id": "sword" }], "e": { "id": "gust", "level": 1 } })
	dummy(st, st.player.x + 80.0, st.player.y)
	st.step({ "skill_e": true }, STEP)
	ok("E 재사용 중 재발동 불가, 재사용은 Lv 값(돌풍 8초, 같은 단계에서 1단계 진행)", absf(st.player.e_cd - (8.0 - STEP)) < 1e-6 and st.stats.e_uses == 1, "%.4f" % st.player.e_cd)
	# ---------- 장비 12종(HTML 82~93) ----------
	st = mk({ "weapons": [{ "id": "sword" }], "equipment": { "weapon": "hunter_sword" } })
	var en := dummy(st, st.player.x + 50.0, st.player.y)
	var ee := st.spawn_enemy("wolf_alpha", st.player.x - 50.0, st.player.y)
	ee.bite_cd = 1.0e9; ee.dash_ready_at = 1.0e9; ee.hp = 9999.0; ee.hp_max = 9999.0
	st.damage_enemy(en, 10.0, { "src": { "weapon_id": "sword", "direct": true } })
	st.damage_enemy(ee, 10.0, { "src": { "weapon_id": "sword", "direct": true } })
	st.damage_enemy(ee, 10.0, { "src": { "weapon_id": "sword", "direct": false, "extra": true } })
	ok("사냥꾼의 검: 정예·보스 직접 피해 +15%, 일반·추가 피해 없음", is_equal_approx(float(st.metrics.dmg["weapon:sword"]), 10.0 + 11.5 + 10.0), str(st.metrics.dmg))
	st = mk({ "weapons": [{ "id": "blades" }], "equipment": { "weapon": "pioneer_spear" } })
	ok("개척자의 창: 반지름 +12%(78 → 87.36), 안쪽 판정 시작은 반지름×0.35", is_equal_approx(snapped(float(st.build.weapons[0].radius), 0.01), 87.36))
	st = mk({ "weapons": [{ "id": "daggers", "mods": ["bleed"] }], "equipment": { "weapon": "ember_sword" }, "commons": { "burn": 1 } })
	var eb3 := dummy(st, st.player.x + 40.0, st.player.y)
	steps(st, 0.4)
	ok("잔불검: 자기 화상 2.5초·출혈 2.5초(+25%), 틱 피해 불변", not eb3.burn.is_empty() and float(eb3.burn.t) >= 2.4 and not eb3.bleed.is_empty() and float(eb3.bleed.t) >= 2.4 and is_equal_approx(float(eb3.burn.dps), 4.0), "burn %s bleed %s" % [str(eb3.burn), str(eb3.bleed)])
	st = mk({ "weapons": [{ "id": "sword" }], "equipment": { "weapon": "chrono_staff" } })
	var ec := dummy(st, st.player.x + 50.0, st.player.y)
	st.damage_enemy(ec, 10.0, { "src": { "weapon_id": "sword", "direct": true } })
	st.step({ "special": true }, STEP)
	st.damage_enemy(ec, 10.0, { "src": { "weapon_id": "sword", "direct": true } })
	ok("시간술사의 지팡이: 감속장 안 대상 직접 피해 +20%(밖은 없음)", is_equal_approx(float(st.metrics.dmg["weapon:sword"]), 22.0), str(st.metrics.dmg))
	st = mk({ "equipment": { "armor": "traveler_armor" } })
	var px0: float = st.player.x
	steps(st, 1.0, { "mx": 1.0 })
	ok("여행자의 경갑: 이동 220×1.08", is_equal_approx(snapped(st.player.x - px0, 0.01), 237.6), "%.2f" % (st.player.x - px0))
	st = mk({ "equipment": { "armor": "guardian_armor" } })
	st.damage_player(10.0, "wolf:bite")
	ok("수호자의 갑옷: 전투 시작 보호막 15, 보호막이 먼저 깎임(체력 100 유지, 흡수 10)", is_equal_approx(st.player.shield, 5.0) and st.player.hp == 100.0 and is_equal_approx(st.stats.absorbed, 10.0))
	st = mk({ "equipment": { "armor": "vitality_coat" } })
	ok("생명력의 외투: 최대 체력 120", is_equal_approx(float(st.build.hp_max), 120.0) and st.player.hp == 120.0)
	ok("원정대의 갑옷: winHeal 8 훅(승리 정산은 회차 계층에서 1회)", float(PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword")).merged({ "equipment": { "weapon": null, "armor": "expedition_armor", "shield": null } }, true)).equip.winHeal) == 8.0)
	st = mk({ "equipment": { "shield": "iron_shield" } })
	st.damage_player(25.0, "boss_dash")
	st.player.hit_prot = 0.0
	st.damage_player(10.0, "wolf:bite")
	ok("철벽 방패: 20 이상 직접 피해 −25%(25→18.8), 작은 피해 그대로", is_equal_approx(snapped(st.stats.damage_taken, 0.01), 28.8), "%.2f" % st.stats.damage_taken)
	# F3(Codex 검수): 철벽 자격은 경감 전 피해. 체력 100·강인함 10%·철벽 25%·명목 20 → 20×0.9×0.75 = 13.5
	st = mk({ "equipment": { "shield": "iron_shield" }, "passives": { "toughness": 1 } })
	st.damage_player(20.0, "wolf:bite")
	ok("철벽+강인함: 명목 20은 경감 전 기준으로 발동 → 13.5, 발동 기록 1", is_equal_approx(snapped(st.stats.damage_taken, 0.01), 13.5) and int(st.stats.equip_procs.get("iron_shield", 0)) == 1, "%.2f procs %s" % [st.stats.damage_taken, str(st.stats.equip_procs)])
	st = mk({ "equipment": { "shield": "iron_shield" }, "passives": { "toughness": 1 } })
	st.damage_player(19.9, "wolf:bite")
	ok("철벽+강인함: 명목 19.9는 발동 안 함 → 17.9", is_equal_approx(snapped(st.stats.damage_taken, 0.01), 17.9) and not st.stats.equip_procs.has("iron_shield"), "%.2f" % st.stats.damage_taken)
	st = mk({ "equipment": { "shield": "iron_shield" } })
	st.damage_player(20.0, "wolf:bite")
	ok("철벽 단독: 명목 정확히 20(=20%)은 발동 → 15", is_equal_approx(snapped(st.stats.damage_taken, 0.01), 15.0), "%.2f" % st.stats.damage_taken)
	st = mk({ "equipment": { "shield": "iron_shield" }, "passives": { "toughness": 1 } })
	st.damage_player(30.0, "zone")
	ok("철벽: 장판(zone) 피해는 강인함·철벽 모두 제외 → 30", is_equal_approx(st.stats.damage_taken, 30.0), "%.2f" % st.stats.damage_taken)
	# F5(Codex 검수): 상태 공급원은 개조 태그 기준 — 회전 칼날 톱날(serrated)도 출혈 공급원
	var g5 := PGrowth.new_growth("blades")
	g5.weapons = [{ "id": "blades", "level": 3, "mods": ["serrated"] }]
	ok("톱날(serrated) = 출혈 공급원: has_dot_source·연쇄의 씨앗 후보·상태 목록 '출혈'", PGrowth.has_dot_source(g5) and PGrowth.boss_reward_applies(g5, "seed") and PGrowth.status_sources(g5) == ["출혈"], str(PGrowth.status_sources(g5)))
	var g5b := PGrowth.new_growth("sword")
	ok("검만 있으면 상태 공급원 없음(씨앗 후보 아님)", not PGrowth.has_dot_source(g5b) and not PGrowth.boss_reward_applies(g5b, "seed"))
	g5b.weapons = [{ "id": "daggers", "level": 1, "mods": ["bleed"] }]
	g5b.commons = { "frost": 1 }
	ok("쌍검 출혈 칼날 + 얼음 파편 → 냉기·출혈", PGrowth.status_sources(g5b) == ["냉기", "출혈"], str(PGrowth.status_sources(g5b)))
	st = mk({ "equipment": { "shield": "emergency_shield" } })
	st.damage_player(75.0, "boss_dash")
	ok("비상 방패: 체력 30% 이하가 된 직후 보호막 20(1회), 소급 없음", st.player.hp == 25.0 and st.player.shield == 20.0)
	st.player.hit_prot = 0.0
	st.damage_player(10.0, "wolf:bite")
	st.player.hit_prot = 0.0
	st.damage_player(10.0, "wolf:bite")
	ok("비상 방패는 전투당 1회", st.player.shield == 0.0 and st.player.hp == 25.0, "hp %.0f shield %.0f" % [st.player.hp, st.player.shield])
	st = mk({ "e": { "id": "gust" }, "equipment": { "shield": "caster_shield" } })
	st.step({ "skill_e": true }, STEP)
	var cs0: float = st.player.shield
	steps(st, 3.2)
	ok("시전자의 방패: E 사용 시 보호막 8이 3초 뒤 만료(남은 양만 제거)", is_equal_approx(cs0, 8.0) and st.player.shield == 0.0, "%.1f → %.1f" % [cs0, st.player.shield])
	st = mk({ "equipment": { "shield": "time_shield" } })
	var ets := dummy(st, st.player.x + 50.0, st.player.y)
	st.step({ "special": true }, STEP)
	st.damage_player(10.0, "wolf:bite", ets)
	st.player.hit_prot = 0.0
	var far := dummy(st, st.player.x + 400.0, st.player.y)
	st.damage_player(10.0, "arrow", far)
	ok("시간의 방패: 감속장 안 공격자 −20%(8), 밖 공격자 10", is_equal_approx(st.stats.damage_taken, 18.0), "%.1f" % st.stats.damage_taken)
	# ---------- 선택지 생성(HTML 110~115·148) ----------
	var run := PBuild.empty_run_like(PGrowth.new_growth("sword"))
	run.seed = 11
	run.gold = 0
	var g: Dictionary = run.growth
	var cands := PGrowth.candidates(run, { "pool": "level" })
	var kinds := {}
	for c in cands:
		kinds[c.kind] = int(kinds.get(c.kind, 0)) + 1
	# 성장 개편: 개조는 자동기술 Lv2부터 자격이 생긴다. Lv1 시작 상태에서는 개조 후보가 0개다.
	# 주무기·보조 분리: 새 자동기술 후보는 **구현된 보조**만이다(주무기는 시작에 고른 1개로 고정).
	var n_impl_sup := 0
	var main_in_new := false
	for wid in PCatalog.weapons():
		if bool(PCatalog.weapons()[wid].impl) and not PCatalog.is_main_weapon(String(wid)):
			n_impl_sup += 1
	for c in cands:
		if String(c.kind) == "weapon_new" and PCatalog.is_main_weapon(String(c.id)):
			main_in_new = true
	ok("시작 상태 후보: 새 보조 = 구현된 보조 전부·주무기는 후보에 없음·검 레벨 1·검 개조 0(Lv2부터 자격)·공용 8·E 5·Q 변형 3·패시브 8", int(kinds.get("weapon_new", 0)) == n_impl_sup and not main_in_new and int(kinds.get("weapon_mod", 0)) == 0 and int(kinds.get("common", 0)) == 8 and int(kinds.get("skill_new", 0)) == 5 and int(kinds.get("skill_variant", 0)) == 3 and int(kinds.get("passive", 0)) == 8, "구현 보조 %d · %s" % [n_impl_sup, str(kinds)])
	var off1 := PGrowth.generate_offer(run, { "pool": "level" })
	var keys1 := []
	for c in off1.choices:
		keys1.append(String(c.key))
	g.pendingOffer = null
	g.choiceSeq = 0
	var off2 := PGrowth.generate_offer(run, { "pool": "level" })
	var keys2 := []
	for c in off2.choices:
		keys2.append(String(c.key))
	ok("제시는 시드·순번·레벨로 결정적(같은 seq = 같은 3택), 서로 다른 대상 3개", keys1 == keys2 and keys1.size() == 3 and keys1[0] != keys1[1] and keys1[1] != keys1[2], str(keys1))
	PGrowth.apply_choice(run, off2.choices[0])
	ok("선택 적용 뒤 pendingOffer 해제·순번 증가·기록", g.pendingOffer == null and int(g.choiceSeq) == 1 and (g.log as Array).size() == 1)
	# 새 구조가 꽉 찬 상태: 주무기 검 Lv5·개조 2, 보조 2개가 각각 Lv3·개조 1
	g.weapons = [{ "id": "sword", "level": 5, "mods": ["cross", "scar"] }, { "id": "blades", "level": 3, "mods": ["dual"] }, { "id": "orb", "level": 3, "mods": ["fork"] }]
	g.commons = { "wide": 2, "reach": 1, "echo": 1 }
	g.passives = { "mastery": 3, "haste": 1, "vitality": 1, "focus": 1 }
	g.skills.e = { "id": "gust", "level": 3, "variant": "whirl" }
	cands = PGrowth.candidates(run, { "pool": "level" })
	var bad := false
	for c in cands:
		if c.kind == "weapon_new" or c.kind == "weapon_level" or c.kind == "weapon_mod" or (c.kind == "common" and c.id in ["wide", "echo"]) or (c.kind == "passive" and c.id in ["mastery", "toughness"]) or c.kind == "skill_new" or (c.kind == "skill_level" and c.id == "gust") or (c.kind == "skill_variant" and c.id == "gust"):
			bad = true
	ok("슬롯 제한: 주무기 1(Lv5·개조 2)·보조 2(각 Lv3·개조 1)·공용 단계·패시브 4종·E 슬롯·기술 Lv3·변형 1을 넘는 후보가 없다", not bad and cands.size() > 0, "%d 후보" % cands.size())
	g.commons = {}
	g.weapons = [{ "id": "sword", "level": 1, "mods": [] }]
	var has_flare := false
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if c.kind == "common" and c.id == "flare":
			has_flare = true
	g.commons = { "ember": 1 }
	var has_flare2 := false
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if c.kind == "common" and c.id == "flare":
			has_flare2 = true
	ok("전제: 불꽃 파열은 잔불 걸음/불씨 정령이 있어야 제시", not has_flare and has_flare2)
	g.weapons = [{ "id": "daggers", "level": 1, "mods": [] }]
	g.commons = {}
	var has_reach := false
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if c.kind == "common" and c.id == "reach":
			has_reach = true
	ok("적용 대상: 쌍검만 있으면 긴 사거리는 제시되지 않는다", not has_reach)
	g.weapons = [{ "id": "sword", "level": 1, "mods": [] }]
	var bc := PGrowth.candidates(run, { "pool": "boss" })
	var bids := []
	for c in bc:
		bids.append(String(c.id))
	ok("희귀 보상 후보: 검 1개·E 돌풍만 → 일제 공격 + 범용 2(공명·씨앗·복제 제외)", bids.has("volley") and not bids.has("resonance") and not bids.has("clone") and not bids.has("seed") and bids.has("vigor") and bids.has("tempo"), str(bids))
	# 경험치 곡선·다중 레벨(HTML 110)
	var g2 := PGrowth.new_growth("sword")
	ok("필요 경험치 20·25·30.2→30, 최대 40레벨", PGrowth.xp_need(1) == 20 and PGrowth.xp_need(2) == 25 and PGrowth.xp_need(3) == 30)
	var gained := PGrowth.add_xp(g2, 46.0)
	ok("경험치 46 → 2레벨 상승(20+25), 잔여 1, 선택 2회 누적", gained == 2 and int(g2.level) == 3 and is_equal_approx(float(g2.xp), 1.0) and int(g2.pendingLevelUps) == 2, "%s" % str(g2))
	# 카드 설명이 실제 파생값을 쓴다(HTML 119·159)
	var run3 := PBuild.empty_run_like(PGrowth.new_growth("spear"))
	run3.growth.weapons[0].level = 2
	var desc := PGrowth.describe(run3, { "kind": "weapon_level", "id": "spear" })
	# 성장 개편: 레벨 배율 Lv2 1.35 · Lv3 1.8 → 관통창 14 × 1.35 = 18.9 → 14 × 1.8 = 25.2
	ok("카드 설명: 관통창 2→3 기본 피해 18.9 → 25.2", "18.9" in String(desc.change) and "25.2" in String(desc.change), String(desc.change))
	# ---------- 지속 피해 감사(HTML 11·67): 화상 fps 무관 총량, 감속장 증폭 없음 ----------
	var tot := {}
	for fps in [60, 120]:
		var dt := 1.0 / float(fps)
		st = mk({ "weapons": [{ "id": "sword" }], "commons": { "burn": 1 } })
		st.player.attack_timer = 1.0e9
		var ed := dummy(st, st.player.x + 50.0, st.player.y)
		st.damage_enemy(ed, 1.0, { "src": { "weapon_id": "sword", "direct": true } })
		steps(st, 4.0, {}, dt)
		tot[fps] = float(st.metrics.dmg.get("dot:burn@sword", 0.0))
	ok("화상 4초 총량이 60fps와 120fps에서 같다(틱 오차 ≤ 1틱 2.0)", absf(float(tot[60]) - float(tot[120])) <= 2.0 and float(tot[120]) >= 6.0, str(tot))
	# ---------- 피해 통계: 출처 합 = 적 체력 감소(HTML 68) ----------
	st = mk({ "weapons": [{ "id": "sword", "mods": ["cross"] }, { "id": "orb" }, { "id": "ember" }], "commons": { "burn": 1, "frost": 1 } })
	var lost := 0.0
	var seen := {}
	for i in 5:
		var ex := dummy(st, st.player.x + 40.0 + 25.0 * float(i), st.player.y + 10.0 * float(i), 40.0)
		seen[ex.id] = ex
	steps(st, 6.0)
	for id in seen:
		lost += float(seen[id].hp_max) - maxf(0.0, float(seen[id].hp))
	ok("출처별 유효 피해 합 = 적 실제 체력 감소 합(다중 무기·화상·냉기 파편)", absf(lost - total_dmg(st)) < 0.6, "lost %.1f dealt %.1f (%s)" % [lost, total_dmg(st), str(st.metrics.dmg)])
	# ---------- 지형(HTML 166·167·170): 투사체는 장애물에서 소멸, 직접 공격은 장애물 뒤를 때리지 않음, 불길은 장애물 안에 생기지 않음 ----------
	st = mk({ "weapons": [{ "id": "bow" }], "arena": "clearing" })
	st.player.x = 285.0; st.player.y = 220.0 + 42.0 + 14.0 + 30.0 # 바위A 바로 아래
	var behind := dummy(st, 285.0, 220.0 - 42.0 - 60.0) # 바위 너머
	steps_pinned(st, 3.0, [[behind, 285.0, 118.0]])
	var shot := false
	for evn in st.events:
		if evn == "shoot":
			shot = true
	ok("투사체(추적궁)는 장애물 뒤의 적을 대상으로 삼지 않거나 장애물에서 소멸한다(피해 0)", float(behind.hp) == float(behind.hp_max), "hp %.0f shot %s" % [behind.hp, str(shot)])
	st = mk({ "weapons": [{ "id": "sword" }], "arena": "clearing" })
	st.player.x = 285.0; st.player.y = 220.0 + 42.0 + 14.0 + 20.0
	var behind2 := dummy(st, 285.0, 220.0 - 42.0 - 20.0)
	steps_pinned(st, 2.0, [[behind2, 285.0, 158.0]])
	ok("직접 공격(검격)은 장애물 뒤의 적을 때리지 않는다", float(behind2.hp) == float(behind2.hp_max) and st.stats.attacks == 0, "attacks %d" % st.stats.attacks)
	st = mk({ "weapons": [{ "id": "spear" }], "arena": "clearing" })
	st.player.x = 285.0; st.player.y = 220.0 + 42.0 + 14.0 + 20.0
	var near_ := dummy(st, 285.0, st.player.y - 18.0) # 바위 앞(플레이어와 바위 사이, 바위 밖)
	var behind3 := dummy(st, 285.0, 220.0 - 42.0 - 30.0)
	steps_pinned(st, 1.0, [[near_, 285.0, st.player.y - 18.0], [behind3, 285.0, 148.0]])
	ok("관통 검광은 장애물에서 멈춘다(앞의 적만 피해)", float(near_.hp) < float(near_.hp_max) and float(behind3.hp) == float(behind3.hp_max))
	st = mk({ "commons": { "ember": 1 }, "arena": "clearing" })
	st.player.x = 285.0 - 42.0 - 14.0 - 2.0; st.player.y = 220.0
	st.step({ "mx": 1.0, "dodge_press": true, "dodge_held": true }, STEP)
	steps(st, 0.3, { "dodge_held": true })
	var in_rock := false
	for z in st.zones:
		if z.type == "fire" and not st.valid_pos(z.x, z.y, 0.0):
			in_rock = true
	ok("불길 조각은 장애물 안에 생기지 않는다(회피가 바위에 막혀 종료)", not in_rock and st.player.dodge_end == "blocked", "end %s" % st.player.dodge_end)
	# ---------- 편성 변환(PORT_BASELINE C4, 잠정): 숲 1일차 새벽(2+3) → 25마리, 경험치 예산 = HTML 5마리 × 1.8 = 9.0 ----------
	var f := PFormation.from_waves([[{ "type": "wolf", "n": 2 }], [{ "type": "wolf", "n": 3 }]], {}, "forest", st)
	ok("편성 변환: 늑대 5 → 25(×5), 동시 상한 12, 마리당 0.36, 예산 9.0", (f.units as Array).size() == 25 and int(f.alive_cap) == 12 and is_equal_approx(float(f.xp_map.wolf), 0.36) and is_equal_approx(float(f.xp_map.wolf) * 25.0, 9.0), str(f.xp_map))
	f = PFormation.from_waves([[{ "type": "wolf", "n": 3 }], [{ "type": "wolf_alpha", "n": 1 }, { "type": "wolf", "n": 2 }]], {}, "den", st)
	var alpha_n := 0
	for u in f.units:
		if String(u) == "wolf_alpha":
			alpha_n += 1
	ok("정예는 배율을 적용하지 않고(1마리) 웨이브 순서를 지킨다(늑대 15 뒤 16번째), 경험치는 굴 배율 2.5 반영(늑대 6×2.5×0.3/5=0.9, 우두머리 30×2.5×0.3=22.5)", alpha_n == 1 and (f.units as Array).size() == 26 and String(f.units[15]) == "wolf_alpha" and is_equal_approx(float(f.xp_map.wolf), 0.9) and is_equal_approx(float(f.xp_map.wolf_alpha), 22.5), "%s idx15=%s" % [str(f.xp_map), String(f.units[15])])
	# ---------- 밀도 모델 스폰: 종류별 동시 상한(궁수 3)을 지키며 순서를 보존한다 ----------
	var run4 := PBuild.empty_run_like(PGrowth.new_growth("sword"))
	var b4 := PBuild.derive(run4)
	var st4 := CombatState.new({ "build": b4, "seed": 2, "arena": "forest", "waves": [[{ "type": "archer", "n": 2 }], [{ "type": "archer", "n": 2 }, { "type": "wolf", "n": 2 }]], "region_id": "ridge", "xp_kill_mult": 0.3 })
	st4.player.attack_timer = 1.0e9
	var max_archers := 0
	for i in 600:
		st4.step({}, STEP)
		max_archers = maxi(max_archers, st4.alive_count_of("archer"))
	ok("종류별 동시 상한: 궁수는 동시에 3마리를 넘지 않고, 전체 대기열 30(궁수 20·늑대 10)", max_archers <= 3 and st4.spawn_total == 30, "max archers %d total %d spawned %d" % [max_archers, st4.spawn_total, st4.spawn_count])
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

func _mod_count(W: Dictionary) -> int:
	var n := 0
	for id in W:
		n += (W[id].mods as Dictionary).size()
	return n

func _variant_count(SK: Dictionary) -> int:
	var n := 0
	for id in SK:
		n += (SK[id].get("variants", {}) as Dictionary).size()
	return n
