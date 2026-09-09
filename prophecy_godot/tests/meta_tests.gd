extends SceneTree
## 영구 성장·해금·제작 테스트(headless): godot --headless --path prophecy_godot -s tests/meta_tests.gd
## user:// 프로필 파일을 쓰므로 APPDATA를 별도 폴더로 두고 실행한다(실제 사용자 프로필·저장을 건드리지 않는다). 프로필 경로는 시험 파일로 바꾼다.
## 기대값은 data/meta.json(시험값, Codex 초안)과 사용자 지시 §5의 규칙에서 온다. 전투는 상태 주입(spawn_hold·더미 적)이며 사람/봇 플레이 주장이 아니다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

## 기록 수로 프로필 만들기(레벨은 PProfile.level_of가 정한다)
func prof(kind: String, records: int, traits: Dictionary = {}, challenges: Array = []) -> Dictionary:
	var p := PProfile.new_profile(kind)
	p.records = records
	for k in traits:
		p.traits[String(k)] = traits[k]
	for c in challenges:
		p.challenges[String(c)] = true
	return p

## 성장·장비·특성으로 전투 생성(적 없음). o: weapons[{id,level,mods}], commons{}, e{id,level,variant}, equipment{}, traits[], start, hp
func mk(o: Dictionary = {}) -> CombatState:
	var g := PGrowth.new_growth(String(o.get("start", "sword")))
	if o.has("weapons"):
		g.weapons = []
		for w in o.weapons:
			g.weapons.append({ "id": String(w.id), "level": int(w.get("level", 1)), "mods": (w.get("mods", []) as Array).duplicate() })
	if o.has("commons"):
		g.commons = (o.commons as Dictionary).duplicate()
	if o.has("e"):
		g.skills.e = { "id": String(o.e.id), "level": int(o.e.get("level", 1)), "variant": o.e.get("variant", null) }
	var run := PBuild.empty_run_like(g)
	for k in o.get("equipment", {}):
		run.equipment[k] = o.equipment[k]
	if o.has("traits"):
		run.traits = (o.traits as Array).duplicate()
		run.startWeapon = String(o.get("start", "sword"))
	if o.has("storedShield"):
		run.storedShield = float(o.storedShield)
	var b := PBuild.derive(run)
	var st := CombatState.new({ "build": b, "seed": int(o.get("seed", 1)), "arena": "forest", "formation": { "units": [], "alive_cap": 0, "group": 0, "interval": 1.0, "type_caps": {} }, "region_id": "forest", "hp": float(o.get("hp", b.hp_max)), "xp_kill_mult": 0.3 })
	st.spawn_hold = true
	return st

func steps(st: CombatState, seconds: float, input: Dictionary = {}) -> void:
	for i in int(round(seconds / STEP)):
		st.step(input, STEP)

func dummy(st: CombatState, x: float, y: float, hp: float = 99999.0, type: String = "wolf") -> Dictionary:
	var e := st.spawn_enemy(type, x, y)
	e.hp = hp
	e.hp_max = hp
	e.bite_cd = 1.0e9
	e.dash_ready_at = 1.0e9
	return e

## 전투 없이 승리 상태(정산 규칙·기록만 본다). dmg_keys: 유효 피해 출처 주입
func fake_win(run: Dictionary, sortie: Dictionary, dmg: Dictionary = {}, extra: Dictionary = {}) -> CombatState:
	var st := PFlow.make_encounter(run, sortie)
	st.spawn_hold = true
	st.step({}, STEP)
	st.status = "won"
	st.mark_duel_done_for_test() # 결투가 예정된 편성이면 그것도 이긴 것으로 본다(승리 정산 규칙과 앞뒤를 맞춘다)
	st.player.hp = 80.0
	for k in dmg:
		st.metrics.dmg[String(k)] = float(dmg[k])
	for k in extra:
		st.stats[String(k)] = extra[k]
	return st

## 그 회차에서 새로 얻을 수 있는 자동기술 수. 해금·구현 여부·역할 상한을 모두 본다.
## 주무기·보조 분리 뒤에는 이 값이 곧 '고를 수 있는 보조 수'다
func expect_weapon_new(run: Dictionary) -> int:
	var g: Dictionary = run.growth
	var n := 0
	for wid in PCatalog.weapons():
		if not bool(PCatalog.weapons()[wid].get("impl", false)):
			continue
		if not PGrowth.can_take_weapon(g, String(wid)):
			continue
		if not PProfile.run_unlock_ok(run, "weapons", String(wid)):
			continue
		n += 1
	return n

## weapon_new 후보에 주무기가 섞였는지
func main_in_new(run: Dictionary) -> Array:
	var out := []
	for c in PGrowth.candidates(run, { "pool": "level" }):
		if String(c.kind) == "weapon_new" and PCatalog.is_main_weapon(String(c.id)):
			out.append(String(c.id))
	return out

func kinds_of(off: Dictionary) -> Array:
	var out := []
	for c in off.choices:
		out.append(String(c.kind))
	return out

func _init() -> void:
	PProfile.use_path("user://prophecy_profile_meta_test_v1.json")
	PProfile.clear()
	PSave.clear()
	var M := PCatalog.meta()
	ok("meta.json 로드: schema prophecy_meta/1, 레벨 15, 문턱 14개 합 140, 특성 12, 제작 6, 도전 21", String(M.schema) == "prophecy_meta/1" and PProfile.max_level() == 15 and (M.levels.thresholds as Array).size() == 14 and PCatalog.trait_defs().size() == 12 and PCatalog.crafted_equipment().size() == 6 and PCatalog.challenges().size() == 21, "challenges %d" % PCatalog.challenges().size())
	ok("카탈로그 분리: equipment()는 12(제작품 제외), equipment_def는 18 모두, 판매가 무기 35·갑옷/방패 30", PCatalog.equipment().size() == 12 and not PCatalog.equipment().has("bloodmoon_sword") and not PCatalog.equipment_def("bloodmoon_sword").is_empty() and PRun.sell_price("bloodmoon_sword") == 35 and PRun.sell_price("moon_armor") == 30 and PRun.sell_price("relay_shield") == 30)
	# ---------- 레벨 문턱 ----------
	ok("레벨: 0→1, 3→1, 4→2, 8→3, 14→4, 68→10, 139→14, 140→15, 200→15(상한)", PProfile.level_of(0) == 1 and PProfile.level_of(3) == 1 and PProfile.level_of(4) == 2 and PProfile.level_of(8) == 3 and PProfile.level_of(14) == 4 and PProfile.level_of(68) == 10 and PProfile.level_of(139) == 14 and PProfile.level_of(140) == 15 and PProfile.level_of(200) == 15)
	var nl := PProfile.next_level(prof("trial", 5))
	ok("다음 레벨 정보: 기록 5 → Lv2, 다음 Lv3까지 3(5/8)", int(nl.level) == 2 and int(nl.next) == 3 and int(nl.remain) == 3 and int(nl.need) == 8, str(nl))
	# ---------- 해금 집합: trial Lv1/5/10/15, legacy Lv1 ----------
	var u1 := PProfile.unlocked(prof("trial", 0))
	var mods1 := 0
	for w in u1.mods:
		mods1 += (u1.mods[w] as Array).size()
	# **명세 변경**(2026-09-10 §7): Q와 E가 같은 6종을 공유하게 되면서 감속장이 e_skills 해금 목록에 들어갔다.
	# 그래서 수동 기술 해금 수가 한 칸씩 늘었다(3→4, 5→6). 구현 결함이 아니라 자료 구조가 바뀐 것이다.
	ok("trial Lv1: 자동기술 7(쌍검·망치·구체 없음)·시작 3·개조 14·공용 6·수동 기술 4(감속장 포함)·감속장 변형 2·장비 8·제작법 0", (u1.weapons as Array).size() == 7 and not (u1.weapons as Array).has("daggers") and not (u1.weapons as Array).has("hammer") and not (u1.weapons as Array).has("orb") and (u1.start_weapons as Array).size() == 3 and mods1 == 14 and (u1.commons as Array).size() == 6 and not (u1.commons as Array).has("saving") and not (u1.commons as Array).has("flare") and (u1.e_skills as Array).size() == 4 and (u1.e_skills as Array).has("slowfield") and not (u1.e_skills as Array).has("strike") and (u1.q_variants as Array).size() == 2 and not (u1.q_variants as Array).has("split") and (u1.equipment as Array).size() == 8 and (u1.recipes as Array).size() == 0, str(u1))
	ok("trial Lv1 개조: 검은 cross·crescent만(scar는 도전), E 변형은 기술과 함께 2종", (u1.mods.sword as Array) == ["cross", "crescent"] and (u1.e_variants.gust as Array).size() == 2)
	var u5 := PProfile.unlocked(prof("trial", 20))
	ok("trial Lv5: 낙뢰·Q 분할·시간 저축(4)·쌍검(3)·시작 추적궁(2) 열림, 망치(6)·정지된 칼날(7) 아직", int(u5.level) == 5 and (u5.e_skills as Array).has("strike") and (u5.q_variants as Array).has("split") and (u5.commons as Array).has("saving") and (u5.weapons as Array).has("daggers") and (u5.start_weapons as Array).has("bow") and (u5.start_weapons as Array).has("daggers") and not (u5.weapons as Array).has("hammer") and not (u5.commons as Array).has("stasis"))
	var u10 := PProfile.unlocked(prof("trial", 68))
	ok("trial Lv10: 자동기술 10·시작 7·공용 8(불꽃 파열만 도전)·수동 기술 6(감속장 포함)·감속장 변형 3·장비 12(대체 해금 6/7/8)·제작법 1(혈월검)", int(u10.level) == 10 and (u10.weapons as Array).size() == 10 and (u10.start_weapons as Array).size() == 7 and (u10.commons as Array).size() == 8 and not (u10.commons as Array).has("flare") and (u10.e_skills as Array).size() == 6 and (u10.e_skills as Array).has("slowfield") and (u10.q_variants as Array).size() == 3 and (u10.equipment as Array).size() == 12 and (u10.recipes as Array) == ["bloodmoon_sword"])
	var u15 := PProfile.unlocked(prof("trial", 140))
	ok("trial Lv15: 제작법 6 전부(대체 해금), 불꽃 파열은 여전히 도전으로만", (u15.recipes as Array).size() == 6 and not (u15.commons as Array).has("flare"))
	var uc := PProfile.unlocked(prof("trial", 0, {}, ["mod3:sword", "flare", "eq:time_shield", "recipe:relay_shield"]))
	ok("도전 OR: Lv1이라도 mod3:sword→잔류 검흔, flare→불꽃 파열, eq:time_shield→시간의 방패, recipe:relay_shield→연계 방패 제작법", (uc.mods.sword as Array).has("scar") and (uc.commons as Array).has("flare") and (uc.equipment as Array).has("time_shield") and (uc.recipes as Array).has("relay_shield"))
	var ul := PProfile.unlocked(prof("legacy", 0))
	var modsl := 0
	for w in ul.mods:
		modsl += (ul.mods[w] as Array).size()
	ok("legacy Lv1: 0.4.x 공개분 전부(자동기술 10·개조 30·공용 9·수동 기술 6·감속장 변형 3·장비 12), 시작 3·제작법 0은 시험 일정대로", (ul.weapons as Array).size() == 10 and modsl == 30 and (ul.commons as Array).size() == 9 and (ul.e_skills as Array).size() == 6 and (ul.q_variants as Array).size() == 3 and (ul.equipment as Array).size() == 12 and (ul.start_weapons as Array).size() == 3 and (ul.recipes as Array).size() == 0)
	var cnt := PProfile.counts(prof("trial", 0))
	ok("도감 개수 분모 분리: 획득 7/10 · 시작 가능 3/7", int(cnt.weapons.have) == 7 and int(cnt.weapons.total) == 10 and int(cnt.start.have) == 3 and int(cnt.start.total) == 7)
	ok("잠긴 항목 조건 문구: 쌍검 '영구 Lv3', 검 세 번째 개조는 도전, 잔불검은 도전(또는 Lv7)", PProfile.unlock_text("weapons", "daggers") == "영구 Lv3" and PProfile.unlock_text("mods", "sword").begins_with("도전") and PProfile.unlock_text("equipment", "ember_sword").find("Lv7") >= 0, PProfile.unlock_text("equipment", "ember_sword"))
	# ---------- 프로필 파일: 두 종류 공존·전환·정규화 ----------
	var pt := prof("trial", 5)
	ok("프로필 저장·불러오기(시험 경로): 기록 5·kind trial 유지", PProfile.save(pt) and PProfile.exists() and int(PProfile.load("trial").records) == 5 and PProfile.active_kind() == "trial")
	var pl := PProfile.set_active("legacy")
	ok("legacy로 전환해도 trial 프로필은 같은 파일에 남는다(삭제 없음)", String(pl.kind) == "legacy" and PProfile.active_kind() == "legacy" and int(PProfile.load("trial").records) == 5 and int(PProfile.load("legacy").records) == 0)
	ok("회차 저장(user://prophecy_save_v1.json)은 프로필 저장과 별개(없음)", not PSave.exists())
	# ---------- 후보 필터(trial Lv1 검 회차) ----------
	var p0 := prof("trial", 0)
	var rt := PRun.new_run(11, "sword", "", { "profile": p0, "eligible": true })
	var rl := PRun.new_run(11, "sword", "", { "profile": prof("legacy", 0), "eligible": true })
	var rn := PRun.new_run(11, "sword")
	ok("new_run(profile): unlocks 스냅샷·traits·profileEligible·startWeapon 저장, 프로필 없는 회차는 unlocks 없음·eligible false", rt.has("unlocks") and bool(rt.profileEligible) and String(rt.startWeapon) == "sword" and (rt.traits as Array).is_empty() and not rn.has("unlocks") and not bool(rn.profileEligible))
	var bad := []
	for c in PGrowth.candidates(rt, { "pool": "level" }):
		var k := String(c.kind)
		if k == "weapon_new" and String(c.id) in ["daggers", "hammer", "orb"]: bad.append(PGrowth.key_of(c))
		if k == "weapon_mod" and String(c.mod) == "scar": bad.append(PGrowth.key_of(c))
		if k == "common" and String(c.id) in ["saving", "stasis", "flare"]: bad.append(PGrowth.key_of(c))
		if k == "skill_new" and String(c.id) in ["strike", "gravity"]: bad.append(PGrowth.key_of(c))
		if k == "skill_variant" and String(c.get("variant", "")) == "split": bad.append(PGrowth.key_of(c))
	var kt := {}
	for c in PGrowth.candidates(rt, { "pool": "level" }):
		kt[c.kind] = int(kt.get(c.kind, 0)) + 1
	ok("trial Lv1 검 후보(개조는 Lv2부터 자격·새 자동기술은 해금된 보조뿐): 쌍검/망치/구체·낙뢰/중력핵·시간 저축/정지된 칼날/불꽃 파열·분할된 시간·잔류 검흔 카드 없음; 검 개조 0·공용 6·E 3·Q 변형 2", bad.is_empty() and int(kt.get("weapon_new", 0)) == expect_weapon_new(rt) and main_in_new(rt).is_empty() and int(kt.get("weapon_mod", 0)) == 0 and int(kt.get("common", 0)) == 6 and int(kt.get("skill_new", 0)) == 3 and int(kt.get("skill_variant", 0)) == 2, "기대 새 보조 %d · %s %s" % [expect_weapon_new(rt), str(bad), str(kt)])
	var kl := {}
	for c in PGrowth.candidates(rl, { "pool": "level" }):
		kl[c.kind] = int(kl.get(c.kind, 0)) + 1
	ok("legacy Lv1 검 후보(개조는 Lv2부터 자격): 새 자동기술 = 해금된 보조 전부·주무기 없음·검 개조 0·공용 8·E 5·Q 변형 3", int(kl.get("weapon_new", 0)) == expect_weapon_new(rl) and main_in_new(rl).is_empty() and int(kl.get("weapon_mod", 0)) == 0 and int(kl.get("common", 0)) == 8 and int(kl.get("skill_new", 0)) == 5 and int(kl.get("skill_variant", 0)) == 3, "기대 새 보조 %d · %s" % [expect_weapon_new(rl), str(kl)])
	# 상점·심층·교체 후보도 해금을 따른다
	var stock_bad := 0
	var deep_bad := 0
	for s in range(1, 41):
		var r := PRun.new_run(s, "sword", "", { "profile": p0 })
		for eid in r.stock.equipment:
			if not (r.unlocks.equipment as Array).has(String(eid)):
				stock_bad += 1
		if r.stock.skill != null and String(r.stock.skill.kind) == "weapon" and not (r.unlocks.weapons as Array).has(String(r.stock.skill.id)):
			stock_bad += 1
		var so := PSortie.start(r, String(PSortie.cards_for(r)[0].id))
		var pv := PRun.deep_preview(r, so)
		if String(pv.reward.kind) == "equipment" and (not (r.unlocks.equipment as Array).has(String(pv.reward.item)) or PCatalog.is_crafted(String(pv.reward.item))):
			deep_bad += 1
	var q := PRun.swap_quote(rt, "weapon", 0)
	ok("40시드 상점 재고·심층 장비 보상·교체 후보가 해금 밖(잔불검·시간술사·원정대·시간의 방패·쌍검 등)이나 제작품을 내지 않는다", stock_bad == 0 and deep_bad == 0 and not (q.options as Array).has("daggers") and (q.options as Array).has("spear"), "stock %d deep %d opts %s" % [stock_bad, deep_bad, str(q.options)])
	ok("교체 확정에서 잠긴 개조(잔류 검흔)·잠긴 기술은 거부", PRun.apply_swap(rl, "weapon", 0, "daggers", ["pursuit"]) == -1 and PRun.apply_swap(rt, "weapon", 0, "daggers", []) == -1)
	# ---------- 카드 희석: legacy vs trial 유형 빈도(N 시드, 검 Lv1, 레벨 1) ----------
	var N := 300
	var freq := { "legacy": {}, "trial": {} }
	for s in range(1000, 1000 + N):
		for who in ["legacy", "trial"]:
			var pr := prof(String(who), 0)
			var r := PRun.new_run(s, "sword", "", { "profile": pr })
			r.growth.pendingLevelUps = 1
			var off := PGrowth.generate_offer(r, { "pool": "level" })
			for k in kinds_of(off):
				freq[who][k] = int(freq[who].get(k, 0)) + 1
	var tot_l := 0
	var tot_t := 0
	for k in freq.legacy:
		tot_l += int(freq.legacy[k])
	for k in freq.trial:
		tot_t += int(freq.trial[k])
	var f_mod_l := float(freq.legacy.get("weapon_mod", 0)) / float(tot_l)
	var f_mod_t := float(freq.trial.get("weapon_mod", 0)) / float(tot_t)
	var f_new_l := float(freq.legacy.get("weapon_new", 0)) / float(tot_l)
	var f_new_t := float(freq.trial.get("weapon_new", 0)) / float(tot_t)
	var f_com_l := float(freq.legacy.get("common", 0)) / float(tot_l)
	var f_com_t := float(freq.trial.get("common", 0)) / float(tot_t)
	print("CARD_DILUTION N=%d seeds×3장: legacy(새 기술 9·검 개조 3·공용 8) vs trial(새 기술 6·검 개조 2·공용 6) — weapon_mod %.3f vs %.3f · weapon_new %.3f vs %.3f · common %.3f vs %.3f · 전체 %s / %s" % [N, f_mod_l, f_mod_t, f_new_l, f_new_t, f_com_l, f_com_t, str(freq.legacy), str(freq.trial)])
	ok("카드 희석 없음(유형 가중치 정규화): 보유 기술 개조 빈도가 trial ≥ legacy×0.9, '새 기술' 유형 빈도 차 ≤ 0.05(후보 수 9→6에도 유형 확률 불변)", f_mod_t >= f_mod_l * 0.9 and absf(f_new_t - f_new_l) <= 0.05, "mod %.3f/%.3f new %.3f/%.3f" % [f_mod_t, f_mod_l, f_new_t, f_new_l])
	# 정규화 자체: 검 개조 후보 수 3 vs 2인데 유형 합산 가중치가 같은지(weight_of/개수) — 결정적 검사
	var pool_l := PGrowth.candidates(rl, { "pool": "level" })
	var pool_t := PGrowth.candidates(rt, { "pool": "level" })
	var sum_l := 0.0
	var sum_t := 0.0
	var nl_ := 0
	var nt_ := 0
	for c in pool_l:
		if String(c.kind) == "weapon_new":
			nl_ += 1
	for c in pool_t:
		if String(c.kind) == "weapon_new":
			nt_ += 1
	for c in pool_l:
		if String(c.kind) == "weapon_new":
			sum_l += PGrowth.weight_of(rl.growth, c) / float(nl_)
	for c in pool_t:
		if String(c.kind) == "weapon_new":
			sum_t += PGrowth.weight_of(rt.growth, c) / float(nt_)
	ok("정규화 뒤 '새 기술' 유형 합산 가중치는 후보 9개·6개에서 같다(=base×early 2.0)", is_equal_approx(sum_l, sum_t) and is_equal_approx(sum_l, 2.0), "%.3f %.3f" % [sum_l, sum_t])
	# ---------- 특성: 행·최대 4·행당 1·고정·기준 불변 ----------
	var p1 := prof("trial", 0)
	ok("Lv1: 1행만 선택 가능, 5행은 잠김", bool(PProfile.can_equip_trait(p1, 1, "near").ok) and not bool(PProfile.can_equip_trait(p1, 5, "heal").ok) and not PProfile.set_trait(p1, 5, "heal"))
	ok("행에 없는 특성은 거부", not bool(PProfile.can_equip_trait(p1, 1, "heal").ok))
	PProfile.set_trait(p1, 1, "near")
	PProfile.set_trait(p1, 1, "far")
	ok("행당 1개: 같은 행에서 다시 고르면 교체(무료 재선택), 해제는 \"\"", PProfile.selected_traits(p1) == ["far"] and PProfile.set_trait(p1, 1, "") and PProfile.selected_traits(p1).is_empty())
	var p15 := prof("trial", 140, { "1": "near", "5": "guard", "10": "q_ops", "15": "focus" })
	ok("Lv15: 4행 모두 열려 4개 장착(최대 4 = 행 수라 초과 불가)", PProfile.selected_traits(p15).size() == 4 and bool(PProfile.can_equip_trait(p15, 15, "link").ok))
	var p5 := prof("trial", 20, { "1": "near", "5": "guard", "10": "q_ops" })
	ok("Lv5 프로필에 10행 값이 있어도 열린 행만 적용(2개)", PProfile.selected_traits(p5) == ["near", "guard"])
	var rf := PRun.new_run(3, "spear", "", { "profile": p15, "eligible": true })
	PProfile.set_trait(p15, 1, "far")
	ok("회차 시작 시 특성 고정: 이후 프로필을 바꿔도 run.traits 그대로, 단일 집중은 시작 기술(창)에 귀속", (rf.traits as Array) == ["near", "guard", "q_ops", "focus"] and String(rf.startWeapon) == "spear" and String(PBuild.derive(rf).trait_dmg.focus_id) == "spear")
	var b_base := PBuild.derive(PBuild.empty_run_like(PGrowth.new_growth("sword")))
	var r_empty := PBuild.empty_run_like(PGrowth.new_growth("sword"))
	r_empty.traits = []
	var b_empty := PBuild.derive(r_empty)
	ok("특성 없음 = 기준 빌드와 동일(traits/trait_dmg 키 없음, JSON 일치) → 기준 전투(D33) 불변", not b_base.has("traits") and not b_base.has("trait_dmg") and not b_empty.has("traits") and JSON.stringify(b_base.weapons) == JSON.stringify(b_empty.weapons) and float(b_base.shield) == 0.0 and is_equal_approx(float(b_base.special_cd), 14.0))
	# 특성 효과 12종
	var st := mk({ "traits": ["near"] })
	dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.5)
	ok("근거리 훈련: 거리 50 검격 12×1.06=12.7", is_equal_approx(float(st.metrics.dmg.get("weapon:sword", 0.0)), 12.7), str(st.metrics.dmg))
	st = mk({ "traits": ["near"] })
	dummy(st, st.player.x + 150.0, st.player.y) # 검 사거리 밖은 안 맞으므로 원거리 대조는 창으로
	st = mk({ "start": "spear", "weapons": [{ "id": "spear" }], "traits": ["far"] })
	dummy(st, st.player.x + 200.0, st.player.y)
	steps(st, 0.5)
	ok("원거리 훈련: 거리 200 관통창 14×1.06=14.8", is_equal_approx(float(st.metrics.dmg.get("weapon:spear", 0.0)), 14.8), str(st.metrics.dmg))
	st = mk({ "start": "spear", "weapons": [{ "id": "spear" }], "traits": ["far"] })
	dummy(st, st.player.x + 100.0, st.player.y)
	steps(st, 0.5)
	ok("원거리 훈련은 거리 100에서 미적용(14)", is_equal_approx(float(st.metrics.dmg.get("weapon:spear", 0.0)), 14.0))
	st = mk({ "commons": { "burn": 1 }, "traits": ["dot_plus"] })
	var eb := dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.5) # 검격 0.25초에 화상 2.0 부여 → 0.5초 시점 남은 1.75
	var burn_t: float = float(eb.burn.t)
	steps(st, 0.55) # 틱 0.5초마다: 2틱 × 4×0.5×1.06=2.12→2.1
	ok("지속 전투: 화상 틱 2.1(4×0.5×1.06, 반올림 0.1) × 2 = 4.2, 지속시간은 그대로(2.0−0.25)", is_equal_approx(float(st.metrics.dmg.get("dot:burn@sword", 0.0)), 4.2) and absf(burn_t - 1.75) < 0.02, "burn_t %.3f dmg %s" % [burn_t, str(st.metrics.dmg)])
	var rh := PBuild.empty_run_like(PGrowth.new_growth("sword"))
	rh.equipment.armor = "expedition_armor"
	rh.traits = ["heal"]
	rh.hp = 50.0
	var healed := PRun.on_victory_heal(rh)
	ok("회복 준비: 원정대의 갑옷 8×1.1=8.8 회복(최대 체력·보호막 무관)", is_equal_approx(healed, 8.8) and is_equal_approx(float(rh.hp), 58.8) and is_equal_approx(float(PBuild.derive(rh).hp_max), 100.0))
	st = mk({ "traits": ["guard"], "equipment": { "armor": "guardian_armor" } })
	ok("방호 준비: 시작 보호막 5(별도 출처) + 수호자의 갑옷 15 = 20", is_equal_approx(float(st.player.shield), 20.0) and is_equal_approx(float(st.build.trait_shield), 5.0))
	var bm := PBuild.derive({ "growth": PGrowth.new_growth("sword"), "equipment": { "weapon": null, "armor": null, "shield": null }, "forge": 0, "buffs": {}, "traits": ["move", "q_ops", "auto_ops"] })
	ok("기동 준비 이동 ×1.04 · 감속장 운용 Q 14×0.95=13.3 · 자동기술 운용 주기 0.55×0.97", is_equal_approx(float(bm.speed_mult), 1.04) and is_equal_approx(float(bm.special_cd), 13.3) and is_equal_approx(float(bm.weapons[0].interval), 0.55 * 0.97), "%s %s %s" % [str(bm.speed_mult), str(bm.special_cd), str(bm.weapons[0].interval)])
	st = mk({ "e": { "id": "gust" }, "traits": ["e_ops"] })
	ok("수동기술 운용: 돌풍 재사용 8×0.95=7.6, Q는 그대로 14", is_equal_approx(PSkills.cd_of(st, "e"), 7.6) and is_equal_approx(float(st.build.special_cd), 14.0))
	st = mk({ "weapons": [{ "id": "sword" }, { "id": "spear" }], "traits": ["focus"] })
	dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.5)
	ok("단일 집중(시작 검): 검 12×1.12=13.4, 창 14×0.94=13.2", is_equal_approx(float(st.metrics.dmg.get("weapon:sword", 0.0)), 13.4) and is_equal_approx(float(st.metrics.dmg.get("weapon:spear", 0.0)), 13.2), str(st.metrics.dmg))
	st = mk({ "e": { "id": "gust" }, "traits": ["link"] })
	dummy(st, st.player.x + 50.0, st.player.y) # 앞: 돌풍에 맞고 밀려난다(E 피해 측정)
	var el := dummy(st, st.player.x - 50.0, st.player.y) # 뒤: 돌풍 범위 밖, 검격 대상
	st.player.face = 0.0
	PSkills.cast_e(st)
	var gust_dmg: float = float(st.metrics.dmg.get("skill:gust", 0.0))
	steps(st, 0.5)
	var sword_in := float(st.metrics.dmg.get("weapon:sword", 0.0))
	ok("연계 준비: E 피해 10×0.9=9, E 뒤 3초 창 안 검격 12×1.1=13.2, 창 3.0으로 갱신", is_equal_approx(gust_dmg, 9.0) and is_equal_approx(sword_in, 13.2) and st.link_t > 2.0, "gust %.1f sword %.1f link %.2f" % [gust_dmg, sword_in, st.link_t])
	steps(st, 3.2)
	var before_out := float(st.metrics.dmg.get("weapon:sword", 0.0))
	el.x = st.player.x - 50.0
	el.y = st.player.y
	steps(st, 0.55)
	ok("창이 끝나면 검격 12로 복귀", st.link_t <= 0.0 and is_equal_approx(float(st.metrics.dmg.get("weapon:sword", 0.0)) - before_out, 12.0), "%.2f" % (float(st.metrics.dmg.get("weapon:sword", 0.0)) - before_out))
	st = mk({ "commons": { "burn": 1 }, "traits": ["dot_spec"] })
	var ed := dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.5)
	ok("지속 전문화: 화상 지속 2×1.15=2.3(0.5초 시점 남은 2.05), 직접 12×0.95=11.4, 틱 피해는 그대로 2.0, Q 지속은 그대로(duration_mult 1)", absf(float(ed.burn.t) - 2.05) < 0.02 and is_equal_approx(float(st.metrics.dmg.get("weapon:sword", 0.0)), 11.4) and is_equal_approx(float(st.metrics.dmg.get("dot:burn@sword", 0.0)), 2.0) and is_equal_approx(float(st.build.duration_mult), 1.0), "burn %s dmg %s" % [str(ed.burn), str(st.metrics.dmg)])
	# ---------- 영구 기록: 1회 지급·재시도·재로드·반복·심층·봇 제외 ----------
	var pe := prof("trial", 0)
	var re := PRun.new_run(21, "sword", "", { "profile": pe, "eligible": true })
	var se := PSortie.start(re, String(PSortie.cards_for(re)[0].id))
	var ste := fake_win(re, se)
	PFlow.settle_victory(re, se, ste)
	var a1 := PProfile.award_from_run(pe, re, "victory", { "sortie": se, "st": ste })
	var a1b := PProfile.award_from_run(pe, re, "victory", { "sortie": se, "st": ste })
	var DW: float = float(PCatalog.meta_records_for("acts").day_win) # 10일 본편: 하루 2/3
	ok("1일차 첫 정상 전투 승리 +2/3(10일 본편), 같은 전투 두 번 정산해도 0", is_equal_approx(float(a1.records), DW) and is_equal_approx(float(pe.records), DW) and float(a1b.records) == 0.0, str(a1))
	if se.get("event", null) != null:
		PEvents.resolve(re, se, "leave")
	PFlow.return_home(re, se)
	var se2 := PSortie.start(re, String(PSortie.cards_for(re)[1].id))
	var ste2 := fake_win(re, se2)
	PFlow.settle_victory(re, se2, ste2)
	var a2 := PProfile.award_from_run(pe, re, "victory", { "sortie": se2, "st": ste2 })
	ok("같은 날 두 번째 전투 승리는 0(날짜당 1회)", float(a2.records) == 0.0 and is_equal_approx(float(pe.records), DW))
	if se2.get("event", null) != null:
		PEvents.resolve(re, se2, "leave")
	PRun.deep_explore(re, se2)
	var ste3 := fake_win(re, se2)
	PFlow.settle_victory(re, se2, ste3)
	var a3 := PProfile.award_from_run(pe, re, "victory", { "sortie": se2, "st": ste3 })
	ok("심층 승리는 기록 0", int(a3.records) == 0)
	PFlow.return_home(re, se2)
	var a3r := PProfile.award_from_run(pe, re, "return", { "sortie": se2 })
	ok("심층 승리 뒤 생환·정산: 원정대의 갑옷 도전 달성 + 같은 출격(일반+심층)이라 재생의 여행복 제작법 도전", (a3r.challenges as Array).has("eq:expedition_armor") and (a3r.challenges as Array).has("recipe:renewal_coat") and (a3r.unlocked.get("equipment", []) as Array).has("expedition_armor") and (a3r.unlocked.get("recipes", []) as Array).has("renewal_coat"), str(a3r))
	PProfile.save(pe)
	var pe2 := PProfile.load("trial")
	var a4 := PProfile.award_from_run(pe2, re, "victory", { "sortie": se, "st": ste })
	ok("프로필 재로드 뒤 같은 이벤트 재지급 없음(events_done 저장)", float(a4.records) == 0.0 and is_equal_approx(float(pe2.records), DW) and bool(pe2.challenges.get("eq:expedition_armor", false)))
	re.day = 2
	re.hours = 5
	re.cards = null
	var se4 := PSortie.start(re, String(PSortie.cards_for(re)[0].id))
	var ste4 := fake_win(re, se4)
	PFlow.settle_victory(re, se4, ste4)
	var a5 := PProfile.award_from_run(pe, re, "victory", { "sortie": se4, "st": ste4 })
	ok("2일차 첫 정상 전투(임무면 0, 전멸이면 +1)", int(a5.records) == (0 if bool(se4.get("mission", false)) else 1), "mission=%s" % str(se4.get("mission", false)))
	# 보스: 최초 승리 +2, 재도전(패배 뒤 승리) 중복 없음, 완주 +2, 스냅샷 복구가 프로필을 되돌리지 않음
	re.day = 4
	re.phase = "boss_prep"
	re.hours = 5
	var bs := PRun.start_boss(re)
	var stb := PFlow.make_boss_encounter(re, bs)
	stb.status = "lost"
	PFlow.settle_boss_defeat(re, stb)
	var rec_before := int(pe.records)
	var bs2 := PRun.start_boss(re)
	var stb2 := PFlow.make_boss_encounter(re, bs2)
	stb2.status = "won"
	stb2.boss.dead = true
	stb2.metrics.dmg["dot:bleed@daggers"] = 30.0
	stb2.stats.special_uses = 1
	stb2.stats.e_uses = 1
	re.equipment.shield = "iron_shield"
	PFlow.settle_boss_victory(re, stb2)
	var ab := PProfile.award_from_run(pe, re, "boss", { "st": stb2 })
	ok("첫 관문 승리 +2(재도전 뒤에도 1회), 도전: 시간의 방패·혈월검 제작법(화상/출혈 피해)·반격 방패 제작법(철벽 장착), 잔불검(출혈 피해)", int(ab.records) == 2 and int(pe.records) == rec_before + 2 and (ab.challenges as Array).has("eq:time_shield") and (ab.challenges as Array).has("recipe:bloodmoon_sword") and (ab.challenges as Array).has("recipe:reprisal_shield") and (ab.challenges as Array).has("eq:ember_sword") and not (ab.challenges as Array).has("recipe:relay_shield"), str(ab))
	var ab2 := PProfile.award_from_run(pe, re, "boss", { "st": stb2 })
	ok("같은 보스 승리 재정산 0", int(ab2.records) == 0)
	ok("보스 패배 스냅샷 복구는 회차만 되돌리고 프로필 기록은 그대로", bool(re.profileEligible) and int(pe.records) == rec_before + 2)
	# 완주: 마지막 보스
	re.stage = PRun.stage_count(re) - 1
	re.phase = "boss_prep"
	re.day = 7
	var bs3 := PRun.start_boss(re)
	var stb3 := PFlow.make_boss_encounter(re, bs3)
	stb3.status = "won"
	stb3.boss.dead = true
	PFlow.settle_boss_victory(re, stb3)
	var ac := PProfile.award_from_run(pe, re, "boss", { "st": stb3 })
	ok("최종 보스: 보스 +2 + 완주 +2 = 4, 이벤트 2개, 재정산 0", int(ac.records) == 4 and (ac.events as Array).size() == 2 and String(re.phase) == "cleared" and int(PProfile.award_from_run(pe, re, "boss", { "st": stb3 }).records) == 0, str(ac))
	# 제외 경로
	var rb := PRun.new_run(21, "sword")
	var sb := PSortie.start(rb, String(PSortie.cards_for(rb)[0].id))
	var stbb := fake_win(rb, sb)
	PFlow.settle_victory(rb, sb, stbb)
	var ax := PProfile.award_from_run(pe, rb, "victory", { "sortie": sb, "st": stbb })
	var rq := PRun.new_run(22, "sword", "", { "profile": pe, "eligible": true })
	rq.quick = true
	var sq := PSortie.start(rq, String(PSortie.cards_for(rq)[0].id))
	var stq := fake_win(rq, sq)
	PFlow.settle_victory(rq, sq, stq)
	var ay := PProfile.award_from_run(pe, rq, "victory", { "sortie": sq, "st": stq })
	var rz := PRun.new_run(23, "sword", "", { "profile": pe, "eligible": true })
	rz.profileEligible = false # main._on_finished: 봇이 진행한 전투가 있는 회차
	var sz := PSortie.start(rz, String(PSortie.cards_for(rz)[0].id))
	var stz := fake_win(rz, sz)
	PFlow.settle_victory(rz, sz, stz)
	var az := PProfile.award_from_run(pe, rz, "victory", { "sortie": sz, "st": stz })
	ok("봇·시험실·즉시 관문 회차(프로필 없음/quick/eligible false)는 기록·도전 모두 없음", not bool(ax.eligible) and int(ax.records) == 0 and not bool(ay.eligible) and not bool(az.eligible) and (ax.challenges as Array).is_empty())
	# 세 번째 개조 도전·불꽃 파열·시간술사(3회 진행)
	var pm := prof("trial", 0)
	var rm := PRun.new_run(31, "sword", "", { "profile": pm, "eligible": true })
	rm.growth.weapons = [{ "id": "sword", "level": 3, "mods": ["cross"] }, { "id": "ember", "level": 1, "mods": [] }]
	var sm := PSortie.start(rm, String(PSortie.cards_for(rm)[0].id))
	var stm := fake_win(rm, sm, { "weapon:sword": 40.0, "weapon:ember": 5.0 }, { "elite_kills": 1, "field_hits": 3 })
	PFlow.settle_victory(rm, sm, stm)
	var am := PProfile.award_from_run(pm, rm, "victory", { "sortie": sm, "st": stm })
	ok("검 Lv3·유효 피해>0 승리 → mod3:sword(잔류 검흔 해금), 불씨 정령+정예+불길 피해 → flare, 감속장 안 유효 피해 → 시간술사 진행 1/3(아직 미해금)", (am.challenges as Array).has("mod3:sword") and (am.challenges as Array).has("flare") and (am.unlocked.get("mods", []) as Array).has("sword:scar") and (am.unlocked.get("commons", []) as Array).has("flare") and not (am.challenges as Array).has("eq:chrono_staff") and PProfile.challenge_progress(pm, "eq:chrono_staff") == 1, str(am))
	var am2 := PProfile.award_from_run(pm, rm, "victory", { "sortie": sm, "st": stm })
	ok("같은 전투 재정산은 시간술사 진행을 늘리지 않는다(1/3)", PProfile.challenge_progress(pm, "eq:chrono_staff") == 1 and (am2.challenges as Array).is_empty())
	rm.growth.weapons = [{ "id": "sword", "level": 2, "mods": [] }]
	var stm2 := fake_win(rm, sm, { "weapon:sword": 40.0 }, { "field_hits": 1 })
	stm2.seed_value = 777
	var am3 := PProfile.award_from_run(pm, rm, "victory", { "sortie": sm, "st": stm2 })
	ok("검 Lv2 승리는 mod3 조건 아님(이미 달성분은 유지), 다른 전투는 시간술사 진행 2/3", not (am3.challenges as Array).has("mod3:sword") and PProfile.challenge_progress(pm, "eq:chrono_staff") == 2)
	# ---------- 저장 호환: unlocks/traits 저장·복구, 옛 저장(키 없음)은 전부 열림 ----------
	var rs := PRun.new_run(41, "sword", "", { "profile": p15, "eligible": true })
	PSave.save(rs)
	var loaded := PSave.load()
	ok("회차 저장에 unlocks·traits·profileEligible·mats·storedShield 포함, 복구 JSON 일치", loaded.has("unlocks") and (loaded.traits as Array).size() == 4 and bool(loaded.profileEligible) and loaded.has("storedShield") and JSON.stringify(PSave.normalize(rs)) == JSON.stringify(loaded))
	var old := PRun.new_run(42, "sword")
	old.erase("unlocks")
	old.erase("traits")
	old.erase("profileEligible")
	old.erase("storedShield")
	old.erase("crafted")
	PSave.save(old)
	var old2 := PSave.load()
	var kinds_old := {}
	for c in PGrowth.candidates(old2, { "pool": "level" }):
		kinds_old[c.kind] = int(kinds_old.get(c.kind, 0)) + 1
	ok("옛 저장(키 없음): 해금 제한 없이 후보 전부 열림, 빌드 계산·상점 정상, 기록 대상 아님", int(kinds_old.get("weapon_new", 0)) == expect_weapon_new(old2) and int(kinds_old.get("weapon_new", 0)) > 0 and not PBuild.derive(old2).has("traits") and not PProfile.eligible(old2) and (PRun.stock(old2).equipment as Array).size() == 4, "기대 %d 실제 %d" % [expect_weapon_new(old2), int(kinds_old.get("weapon_new", 0))])
	PSave.clear()
	# ---------- 제작 ----------
	var rc := PRun.new_run(51, "sword") # 프로필 없음 = 제작법 전부 열림(도구·테스트)
	rc.gold = 100
	# §8 명세 변경(2026-09-10): 제작은 **기본 장비 하나** + 재료 + 금화다(혈월검 = 잔불검 + 송곳니 1 + 무쇠 1 + 90금).
	# 사냥꾼의 검은 계보에서 빠졌으므로 재료가 아니다 — 아래 기대값은 그 지시에 맞춘 것이다
	rc.equipment.weapon = "ember_sword"
	rc.mats.fang = 1
	rc.mats.iron = 1
	var json_before := JSON.stringify(PSave.normalize(rc.duplicate(true)))
	var opts := PRun.craft_options(rc)
	var bm_opt := {}
	for o in opts:
		if String(o.id) == "bloodmoon_sword":
			bm_opt = o
	# 폐기 2종(§1)은 제작 후보에서 빠져 4개다
	ok("제작 후보 4개(폐기 2종 제외), 혈월검: 재료 잔불검(장착)·송곳니 1/1·무쇠 1/1·수수료 90 → 가능, 미리보기 있음", opts.size() == 4 and bool(bm_opt.can) and (bm_opt.ingredients as Array).size() == 3 and String(bm_opt.ingredients[0].where) == "equipped" and int(bm_opt.fee) == 90 and not (bm_opt.preview as Dictionary).is_empty(), str(bm_opt.get("missing", [])))
	ok("폐기 장비는 제작 후보에 없고 확정도 거부된다(§1)", not opts.any(func(o): return String(o.id) == "reprisal_shield" or String(o.id) == "relay_shield") and not PRun.can_craft(rc, "reprisal_shield") and not PRun.craft(rc, "relay_shield", true, false))
	ok("미리보기·후보 계산은 회차를 바꾸지 않는다(취소 = 소비 없음)", JSON.stringify(PSave.normalize(rc.duplicate(true))) == json_before)
	ok("장착 중 재료를 쓰지 않는 제작은 실패·불변", not PRun.craft(rc, "bloodmoon_sword", false, true) and int(rc.gold) == 100 and rc.equipment.weapon == "ember_sword")
	var trial_rc := PRun.new_run(51, "sword", "", { "profile": prof("trial", 0) })
	ok("trial Lv1 회차는 제작법이 없어 후보 0·제작 거부", PRun.craft_options(trial_rc).is_empty() and not PRun.can_craft(trial_rc, "bloodmoon_sword"))
	var crafted_ok := PRun.craft(rc, "bloodmoon_sword", true, true)
	# 완성품은 **장비 개체**다(§4): 슬롯에는 "bloodmoon_sword#N"이 들어간다. 종류로 비교할 때는 equip_type_of를 쓴다
	var made_uid := String(rc.equipment.weapon)
	ok("확정(장착): 재료 장비·송곳니·무쇠·90금 소비, 완성품 장착, 가방 비움, crafted 기록, 강화 단계 무관", crafted_ok and PRun.equip_type_of(made_uid) == "bloodmoon_sword" and (rc.bag as Array).is_empty() and int(rc.mats.fang) == 0 and int(rc.gold) == 10 and (rc.crafted as Array) == ["bloodmoon_sword"] and int(rc.forge) == 0, "eq %s bag %s gold %d" % [str(rc.equipment), str(rc.bag), int(rc.gold)])
	ok("완성품은 +0에서 시작한다(재료 강화 자동 계승 없음 — §4 미승인)", PRun.equip_plus_of(rc, made_uid) == 0)
	ok("중복 확정 불가(재료 없음·이미 보유)", not PRun.craft(rc, "bloodmoon_sword", true, true) and int(rc.gold) == 10)
	var gold_s := int(rc.gold)
	PRun.sell_equipment(rc, made_uid)
	# 판매가 변경(사용자 확정): 구매액의 절반. 제작품은 구매액이 없으므로 정상 구매가의 절반을 기준으로 쓴다.
	# 혈월검 정상가 140 → 70. 옛 값 35는 '정상가의 1/4'이던 시절의 수다
	ok("완성품 판매 = 정상 구매가의 절반(혈월검 140 → 70), 재료 환급 없음", int(rc.gold) == gold_s + 70 and rc.equipment.weapon == null and int(rc.mats.fang) == 0, "금화 %d (기대 %d)" % [int(rc.gold), gold_s + 70])
	rc.gold = 200
	rc.bag = ["guardian_armor"]   # '#'이 없는 옛 형식 문자열도 그대로 쓸 수 있다(§0 호환)
	rc.mats.iron = 2
	rc.mats.pelt = 1
	var moon_ok := PRun.craft(rc, "moon_armor", false, false)
	var moon_uid := String((rc.bag as Array)[0]) if (rc.bag as Array).size() > 0 else ""
	ok("가방 재료로 제작(보관): 월광 갑옷 가방에, 슬롯 비어 있음", moon_ok and (rc.bag as Array).size() == 1 and PRun.equip_type_of(moon_uid) == "moon_armor" and rc.equipment.armor == null and int(rc.mats.iron) == 0 and int(rc.gold) == 120)
	var acts := PFlow.actions(rc)
	ok("행동 목록·장비 이름이 제작품도 처리(equip/sell 항목 — 항목 id는 개체 id다)", acts.any(func(a): return String(a.id) == "equip:" + moon_uid) and acts.any(func(a): return String(a.id) == "sell:" + moon_uid and int(a.data.price) == 60)) # 월광 갑옷 정상가 120의 절반
	# ---------- 장비 개체·장비 강화(§0·§4, 2026-09-10) ----------
	# 여기의 검사는 **규칙 계층**이다. 실제 버튼 경로는 meta_ui_tests·수동 확인이 따로 본다.
	var eqr := PRun.new_run(77, "sword")
	eqr.gold = 2000
	eqr.bossesDone = ["b1", "b2"] # 관문 2돌파 = +1·+2 둘 다 열린 상태
	# 같은 종류 2개를 손으로 넣는다. 상점은 같은 종류를 두 번 팔지 않으므로 **정상 경로로는 생기지 않는 상태**이며,
	# 개체 구분이 실제로 되는지 보기 위한 주입 검사다(보조 근거로 구분해 보고한다)
	var eu_a := PRun.equip_new_uid(eqr, "vitality_coat")
	var eu_b := PRun.equip_new_uid(eqr, "vitality_coat")
	(eqr.bag as Array).append(eu_a)
	(eqr.bag as Array).append(eu_b)
	ok("개체 id: 같은 종류라도 서로 다른 id를 받고, 타입은 둘 다 같게 읽힌다",
		eu_a != eu_b and PRun.equip_type_of(eu_a) == "vitality_coat" and PRun.equip_type_of(eu_b) == "vitality_coat", "%s / %s" % [eu_a, eu_b])
	var eq_gup := int(eqr.gold)
	ok("강화 +1: 금화가 표대로 줄고 그 개체만 +1이 된다", PRun.upgrade_equip(eqr, eu_a) and PRun.equip_plus_of(eqr, eu_a) == 1 and PRun.equip_plus_of(eqr, eu_b) == 0 and int(eqr.gold) == eq_gup - 70, "gold %d" % int(eqr.gold))
	ok("강화 +2도 같은 개체에 쌓인다", PRun.upgrade_equip(eqr, eu_a) and PRun.equip_plus_of(eqr, eu_a) == 2 and int(eqr.gold) == eq_gup - 200)
	ok("+2가 최대다(더는 견적이 없다)", PRun.equip_upgrade_next(eqr, eu_a).is_empty() and not PRun.upgrade_equip(eqr, eu_a))
	ok("같은 종류 2개를 서로 다르게 강화해도 각각 구분된다(+2 / +0)", PRun.equip_plus_of(eqr, eu_a) == 2 and PRun.equip_plus_of(eqr, eu_b) == 0)
	# §4 값: 강화는 **기본 능력치만** 올린다. 생명력의 외투 hpMax 20 → 27 → 34(시험값)
	var eq_eff2 := PCatalog.equipment_eff("vitality_coat", 2)
	ok("강화표가 기본 능력치만 바꾼다(hpMax 20 → 34), 원본 정의는 그대로", int(eq_eff2.hpMax) == 34 and int(PCatalog.equipment_def("vitality_coat").eff.hpMax) == 20)
	var eq_effsh := PCatalog.equipment_eff("caster_shield", 2)
	ok("강화표는 지속·재사용을 건드리지 않는다(시전자의 방패: 보호막만 8 → 14, dur 3·cd 10 그대로)",
		int(eq_effsh.eShield.shield) == 14 and int(eq_effsh.eShield.dur) == 3 and int(eq_effsh.eShield.cd) == 10)
	# ② 강화 → 가방 보관 → 재착용해 같은 강화 유지
	PRun.equip_item(eqr, eu_a)
	var hp_plus2 := float(PBuild.derive(eqr).hp_max)
	PRun.unequip_item(eqr, "armor")
	ok("가방에 넣어도 강화가 유지된다", (eqr.bag as Array).has(eu_a) and PRun.equip_plus_of(eqr, eu_a) == 2)
	PRun.equip_item(eqr, eu_a)
	ok("재착용해도 같은 강화(+2)와 같은 최대 체력", PRun.equip_plus_of(eqr, eu_a) == 2 and is_equal_approx(float(PBuild.derive(eqr).hp_max), hp_plus2))
	# ③ 다른 장비를 착용해도 강화가 따라가지 않는다
	PRun.equip_item(eqr, eu_b)
	ok("다른 장비를 껴도 강화가 따라가지 않는다(+0 그대로, 최대 체력도 +0 값)",
		String(eqr.equipment.armor) == eu_b and PRun.equip_plus_of(eqr, eu_b) == 0 and float(PBuild.derive(eqr).hp_max) < hp_plus2)
	ok("벗어 둔 개체의 강화는 그대로 남아 있다", (eqr.bag as Array).has(eu_a) and PRun.equip_plus_of(eqr, eu_a) == 2)
	# ⑦ 저장/이어하기 보존
	PSave.save(eqr)
	var eqr2 := PSave.load()
	ok("저장·이어하기 뒤에도 장비 개체·강화·일련번호가 그대로다",
		PRun.equip_plus_of(eqr2, eu_a) == 2 and PRun.equip_plus_of(eqr2, eu_b) == 0 and String(eqr2.equipment.armor) == eu_b and int(eqr2.equipSeq) == int(eqr.equipSeq)
			and JSON.stringify(PSave.normalize(eqr)) == JSON.stringify(eqr2))
	PSave.clear()
	# 판매하면 개체와 함께 강화도 사라진다(다른 장비로 옮겨가지 않는다)
	var gold_b4 := int(eqr.gold)
	var eq_qup := PRun.sell_quote(eqr, eu_a)
	ok("강화한 장비의 판매 견적에 '강화가 사라진다'가 적혀 있다", String(eq_qup.text).find("강화 +2") >= 0, String(eq_qup.text))
	ok("판매하면 그 개체가 가방에서 사라지고 강화 기록도 지워진다",
		PRun.sell_equipment(eqr, eu_a, int(eq_qup.gold)) and not (eqr.bag as Array).has(eu_a) and PRun.equip_plus_of(eqr, eu_a) == 0 and int(eqr.gold) == gold_b4 + int(eq_qup.gold)
			and not (eqr.get("equipPlus", {}) as Dictionary).has(eu_a))
	# 강화 잠금: 관문을 덜 돌파했으면 열리지 않고 금화도 빠지지 않는다
	var eqrl := PRun.new_run(78, "sword")
	eqrl.gold = 2000
	var eu_c := PRun.equip_new_uid(eqrl, "iron_shield")
	(eqrl.bag as Array).append(eu_c)
	var eq_gl := int(eqrl.gold)
	ok("관문 0돌파: +1도 아직 잠겨 있고, 시도해도 금화가 그대로다",
		PRun.equip_upgrade_open_max(eqrl) == 0 and not PRun.can_upgrade_equip(eqrl, eu_c) and not PRun.upgrade_equip(eqrl, eu_c) and int(eqrl.gold) == eq_gl)
	eqrl.bossesDone = ["b1"]
	ok("관문 1돌파: +1만 열리고 +2는 아직 잠긴다", PRun.equip_upgrade_open_max(eqrl) == 1 and PRun.can_upgrade_equip(eqrl, eu_c) and PRun.upgrade_equip(eqrl, eu_c) and PRun.equip_upgrade_next(eqrl, eu_c).open == false)
	var eq_gl2 := int(eqrl.gold)
	ok("견적과 다른 금액으로 확정하면 실행되지 않는다(금화 불변)", not PRun.upgrade_equip(eqrl, eu_c, 999) and int(eqrl.gold) == eq_gl2 and PRun.equip_plus_of(eqrl, eu_c) == 1)
	# ⑩·§0 옛 저장 호환: '#'이 없는 **옛 형식 그대로**를 읽어 동작하는지
	var eqro := PRun.new_run(79, "sword")
	eqro.equipment = { "weapon": "hunter_sword", "armor": "vitality_coat", "shield": "reprisal_shield" } # 폐기 장비를 낀 옛 저장
	eqro.bag = ["relay_shield", "iron_shield"]
	eqro.erase("equipPlus")
	eqro.erase("equipSeq")
	PSave.save(eqro)
	var eqro2 := PSave.load()
	var eq_bo := PBuild.derive(eqro2)
	ok("옛 형식 저장(개체 id 없음·equipPlus 없음)이 변환 없이 그대로 동작한다: 타입 해석·강화 +0·빌드 계산",
		PRun.equip_type_of("hunter_sword") == "hunter_sword" and PRun.equip_plus_of(eqro2, "vitality_coat") == 0
			and int(float(eq_bo.hp_max)) == int(float(PCatalog.config().PLAYER.hp)) + 20 and (eq_bo.equip as Dictionary).has("eliteDirect") and (eq_bo.equip as Dictionary).has("bigHit"),
		"hp_max %.0f" % float(eq_bo.hp_max))
	ok("옛 저장의 폐기 장비는 지워지지 않고 보유·장착 상태 그대로 남는다(이전 처리 미확정)",
		String(eqro2.equipment.shield) == "reprisal_shield" and (eqro2.bag as Array).has("relay_shield") and (eq_bo.equip as Dictionary).has("reprisal"))
	ok("옛 저장의 폐기 장비도 팔 수는 있다(값이 사라지지 않는다)", bool(PRun.sell_quote(eqro2, "relay_shield").can) and int(PRun.sell_quote(eqro2, "relay_shield").gold) == 60)
	ok("옛 저장에 새로 사면 개체 id가 붙고, 옛 문자열과 섞여도 서로 구분된다",
		PRun.equip_new_uid(eqro2, "iron_shield") == "iron_shield#1" and PRun.owns_equip_type(eqro2, "iron_shield") and PRun.has_equip_uid(eqro2, "iron_shield") and not PRun.has_equip_uid(eqro2, "iron_shield#1"))
	PSave.clear()
	# ⑩ 폐기 장비의 신규 유입 차단(상점·심층 보상·제작)
	var eqrr := PRun.new_run(80, "sword")
	var seen_retired := false
	for d in range(1, 8):
		eqrr.day = d
		PRun.refresh_stock(eqrr)
		for id in PRun.stock(eqrr).equipment:
			if PCatalog.equipment_retired(String(id)):
				seen_retired = true
	ok("폐기 장비는 상점 재고에 절대 나오지 않는다(7일치 재고 확인)", not seen_retired)
	ok("폐기 판정 자체", PCatalog.equipment_retired("reprisal_shield") and PCatalog.equipment_retired("relay_shield") and not PCatalog.equipment_retired("moon_armor") and not PCatalog.equipment_retired("iron_shield"))

	# 제작 × 강화(§4 미결정 항목의 **현재 동작**을 못 박아 둔다 — 처리안이 정해지면 여기부터 고친다)
	var rcp := PRun.new_run(81, "sword")
	rcp.gold = 2000
	rcp.bossesDone = ["b1", "b2"]
	rcp.mats.iron = 2
	rcp.mats.pelt = 1
	var g_low := PRun.equip_new_uid(rcp, "guardian_armor")
	var g_high := PRun.equip_new_uid(rcp, "guardian_armor")
	(rcp.bag as Array).append(g_low)
	(rcp.bag as Array).append(g_high)
	PRun.upgrade_equip(rcp, g_high)
	PRun.upgrade_equip(rcp, g_high)
	var pick_o := PRun.craft_pick_uid(rcp, "guardian_armor")
	ok("재료가 여럿이면 **강화가 가장 낮은 개체**를 쓴다(비싸게 강화한 장비를 조용히 태우지 않는다)",
		String(pick_o.uid) == g_low and int(pick_o.plus) == 0, str(pick_o))
	var opt_moon := PRun.craft_option(rcp, "moon_armor", false)
	var ing_plus := -1
	for ing in opt_moon.ingredients:
		if String(ing.kind) == "equipment":
			ing_plus = int(ing.get("plus", -1))
	ok("제작 후보가 소비할 개체의 강화 단계를 함께 알려 준다(화면이 미리 경고할 수 있게)", ing_plus == 0, "plus %d" % ing_plus)
	ok("제작 확정: 낮은 쪽만 사라지고 강화한 개체는 그대로 남는다",
		PRun.craft(rcp, "moon_armor", false, false) and not (rcp.bag as Array).has(g_low) and (rcp.bag as Array).has(g_high) and PRun.equip_plus_of(rcp, g_high) == 2)
	var made_moon := ""
	for id in rcp.bag:
		if PRun.equip_type_of(String(id)) == "moon_armor":
			made_moon = String(id)
	ok("완성품은 +0이고 재료의 강화를 물려받지 않는다(§4: 자동 계승 미승인)", made_moon != "" and PRun.equip_plus_of(rcp, made_moon) == 0)

	# ---------- 제작 6종 효과(전투) ----------
	st = mk({ "equipment": { "weapon": "bloodmoon_sword" } })
	var e1 := dummy(st, st.player.x + 50.0, st.player.y)
	steps(st, 0.5)
	var d_plain := float(st.metrics.dmg.get("weapon:sword", 0.0))
	e1.bleed = { "t": 2.0, "dps": 3.0, "tick": 9.0, "src": "daggers" }
	steps(st, 0.55)
	ok("혈월검: 상태 없는 적 12, 출혈 중인 적 12×1.2=14.4(상태를 스스로 부여하지 않음)", is_equal_approx(d_plain, 12.0) and is_equal_approx(float(st.metrics.dmg.get("weapon:sword", 0.0)) - d_plain, 14.4) and st.build.equip.has("statusDirect") and not st.build.equip.has("eliteDirect"), "%.1f" % (float(st.metrics.dmg.get("weapon:sword", 0.0)) - d_plain))
	st = mk({ "equipment": { "weapon": "echo_staff" } })
	var e2 := dummy(st, st.player.x + 50.0, st.player.y)
	PSkills.cast_q(st)
	steps(st, 0.5)
	var m1 := float(st.metrics.dmg.get("weapon:sword", 0.0))
	steps(st, 0.55)
	var m2 := float(st.metrics.dmg.get("weapon:sword", 0.0)) - m1
	st.end_field()
	steps(st, 0.55)
	var m3 := float(st.metrics.dmg.get("weapon:sword", 0.0)) - m1 - m2
	steps(st, 2.2)
	var m_before := float(st.metrics.dmg.get("weapon:sword", 0.0))
	steps(st, 0.55)
	var m4 := float(st.metrics.dmg.get("weapon:sword", 0.0)) - m_before
	ok("잔향의 지팡이: 감속장 안 첫 적중 12(표식), 재적중 12×1.15=13.8, 감속장 종료 뒤 표식 남은 동안 13.8, 2초 지나면 12", is_equal_approx(m1, 12.0) and is_equal_approx(m2, 13.8) and is_equal_approx(m3, 13.8) and is_equal_approx(m4, 12.0) and float(e2.get("echo_mark", 0.0)) > 0.0, "%.1f %.1f %.1f %.1f" % [m1, m2, m3, m4])
	var rr := PRun.new_run(61, "sword")
	rr.bag = ["renewal_coat"]
	PRun.equip_item(rr, "renewal_coat")
	rr.hp = 95.0
	var h1 := PRun.on_victory_heal(rr)
	var h2 := PRun.on_victory_heal(rr)
	var h3 := PRun.on_victory_heal(rr)
	ok("재생의 여행복: 95→100 회복 5, 초과 3 저장; 가득 찬 채 승리 2회 → 저장 11, 19→상한 16", is_equal_approx(h1, 5.0) and is_equal_approx(h2, 0.0) and is_equal_approx(h3, 0.0) and is_equal_approx(float(rr.storedShield), 16.0), str(rr.storedShield))
	var so_r := PSortie.start(rr, String(PSortie.cards_for(rr)[0].id))
	var st_r := PFlow.make_encounter(rr, so_r)
	ok("다음 전투 시작 보호막 16(저장분 소비 → 0), 이동속도 효과 없음", is_equal_approx(float(st_r.player.shield), 16.0) and is_equal_approx(float(rr.storedShield), 0.0) and is_equal_approx(float(st_r.build.speed_mult), 1.0))
	st = mk({ "equipment": { "armor": "moon_armor" } })
	ok("월광 갑옷: 시작 보호막 20 = 이 장비 몫 20", is_equal_approx(float(st.player.shield), 20.0) and is_equal_approx(st.moon_shield, 20.0))
	st.damage_player(8.0, "wolf:bite")
	steps(st, 1.0)
	var sh_out := float(st.player.shield)
	PSkills.cast_q(st)
	steps(st, 1.0)
	var sh_in := float(st.player.shield)
	steps(st, 5.0) # 감속장 3초 → 총 +6 = 18, 밖에서 2초는 정지
	var sh_after := float(st.player.shield)
	PSkills.cast_q(st)
	steps(st, 3.0)
	ok("피격 뒤 12, 감속장 밖 1초 재생 없음(12), 안에서 1초 +2(14), 감속장 3초 뒤 18, 다시 감속장 → 상한 20", is_equal_approx(sh_out, 12.0) and is_equal_approx(snapped(sh_in, 0.01), 14.0) and absf(sh_after - 18.0) < 0.05 and is_equal_approx(snapped(float(st.player.shield), 0.01), 20.0), "%.2f %.2f %.2f %.2f" % [sh_out, sh_in, sh_after, float(st.player.shield)])
	st = mk({ "equipment": { "armor": "moon_armor" }, "e": { "id": "ward" } })
	PSkills.cast_e(st) # 결계 30 + 월광 20 = 50
	st.damage_player(30.0, "wolf:bite") # 20 → 월광 몫 0(완전히 깨짐)
	PSkills.cast_q(st)
	steps(st, 2.0)
	ok("월광 몫이 완전히 깨지면 감속장 안에서도 재생 없음(다른 출처 보호막 20은 재생하지 않음)", is_equal_approx(st.moon_shield, 0.0) and is_equal_approx(float(st.player.shield), 20.0), "%.2f moon %.2f" % [float(st.player.shield), st.moon_shield])
	st = mk({ "equipment": { "shield": "reprisal_shield" }, "e": { "id": "gust" } })
	st.player.special_cd = 5.0
	st.player.e_cd = 5.0
	st.damage_player(20.0, "wolf:bite")
	var hp1 := float(st.player.hp)
	var q1 := float(st.player.special_cd)
	var ec1 := float(st.player.e_cd)
	steps(st, 1.0)
	st.damage_player(20.0, "wolf:bite")
	var q2 := float(st.player.special_cd)
	steps(st, 4.5)
	st.damage_player(20.0, "wolf:bite")
	var q3 := float(st.player.special_cd)
	ok("반격 방패: 큰 타격 20→15(체력 85), Q/E 남은 재사용 5→4, 5초 안 두 번째 큰 타격은 감소 없음(4−1.0경과), 5초 뒤 다시 −1, 비상 보호막 없음", is_equal_approx(hp1, 85.0) and is_equal_approx(q1, 4.0) and is_equal_approx(ec1, 4.0) and is_equal_approx(snapped(q2, 0.01), 3.0) and is_equal_approx(snapped(q3, 0.01), 0.0) and int(st.stats.equip_procs.get("reprisal_shield", 0)) == 2 and not st.build.equip.has("lowShield"), "hp %.1f q %.2f %.2f %.2f" % [hp1, q1, q2, q3])
	st = mk({ "equipment": { "shield": "relay_shield" }, "e": { "id": "gust" } })
	PSkills.cast_e(st)
	var s_e_only := float(st.player.shield)
	st.player.e_cd = 0.0
	PSkills.cast_q(st)
	steps(st, 1.0)
	PSkills.cast_e(st)
	var s_relay := float(st.player.shield)
	steps(st, 3.1)
	var s_exp := float(st.player.shield)
	st.player.e_cd = 0.0
	st.player.special_cd = 0.0
	PSkills.cast_q(st)
	PSkills.cast_e(st)
	var s_cd := float(st.player.shield)
	ok("연계 방패: E만으로 0, Q 뒤 1초 E → 18, 3초 뒤 만료 0, 내부 재사용 10초 안 Q→E 재발동 없음", is_equal_approx(s_e_only, 0.0) and is_equal_approx(s_relay, 18.0) and is_equal_approx(s_exp, 0.0) and is_equal_approx(s_cd, 0.0), "%.1f %.1f %.1f %.1f" % [s_e_only, s_relay, s_exp, s_cd])
	st = mk({ "equipment": { "shield": "relay_shield" }, "e": { "id": "gust" } })
	PSkills.cast_q(st)
	steps(st, 4.5)
	st.player.e_cd = 0.0
	PSkills.cast_e(st)
	ok("연계 방패: Q 뒤 4초 창이 지나면 E에 보호막 없음", is_equal_approx(float(st.player.shield), 0.0))
	# ---------- 프로필 파일 분리 ----------
	var saved_again := PProfile.save(pe)
	ok("이 테스트는 시험 프로필 경로만 썼다(set_path)·저장 성공·재로드 기록 일치", PProfile.profile_path() == "user://prophecy_profile_meta_test_v1.json" and saved_again and PProfile.exists() and int(PProfile.load("trial").records) == int(pe.records), "exists=%s records=%d/%d saved=%s path=%s" % [str(PProfile.exists()), int(PProfile.load("trial").records), int(pe.records), str(saved_again), PProfile.profile_path()])
	PProfile.clear()
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
