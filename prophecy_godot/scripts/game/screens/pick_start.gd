class_name PPickStartScreen
extends PScreen
## 시작 선택(HTML pickStart). **두 단계다**(2026-09-10 §7):
##   ① 주무기 1개  → ② 수동 기술 1개(Q에 Lv1으로 장착) → 출발
## 감속장을 기본으로 강제 지급하지 않는다 — ②에서 고른 것이 Q에 들어가고 E는 비어 있다.
## 목록은 프로필 해금(PProfile.unlocked(): start_weapons·e_skills)을 따르고, 수치는 실제 파생값(PBuild.derive)을 읽는다.
## ②에서 "주무기 다시 고르기"로 ①로 돌아갈 수 있고, 화면을 떠났다 오면 ①부터 다시 시작한다(취소·뒤로 연결).

var _step: int = 0        # 0 = 주무기, 1 = 수동 기술
var _weapon: String = ""  # ①에서 고른 주무기

## 화면에 들어올 때마다 처음부터(다른 화면을 들렀다 오면 고르던 것이 남아 있지 않게)
func on_enter() -> void:
	_step = 0
	_weapon = ""
	super()

func refresh() -> void:
	clear_all()
	if _step == 1 and _weapon != "":
		_refresh_skill()
		return
	_refresh_weapon()

# ---------- ① 주무기 ----------
func _refresh_weapon() -> void:
	var C := PCatalog.config()
	var p: Dictionary = main.profile
	var R := PCatalog.slot_rules()
	heading("주무기 선택 (1/2)")
	top.add_child(PUi.rich("[color=#9ea8b8]① 주무기 1개(Lv1, 개조 없음)를 고르고 ② 수동 기술 1개를 골라 Q에 장착합니다. E는 비어 있고 회차 중에 채웁니다. 체력 %d · 금화 %d으로 1일차 %s에 시작합니다. 주무기는 이 1개로 최대 Lv%d·개조 %d개까지 키우고, 보조무기는 회차 중에 최대 %d개(각 Lv%d·개조 %d개)를 얻습니다. 장비(무기·방어구·방패)는 상점에서 따로 삽니다.[/color]" % [int(C.PLAYER.hp), int(C.START_GOLD), String(PRun.time_slots()[0]), int(R.get("mainMax", 5)), int(R.get("mainMods", 2)), int(R.get("supports", 2)), int(R.get("supportMax", 3)), int(R.get("supportMods", 1))], 13))
	var startable: Array = PCatalog.startable()
	if not p.is_empty():
		var u := PProfile.unlocked(p)
		startable = u.start_weapons
		var sel := PProfile.selected_traits(p)
		var names := []
		var D := PCatalog.trait_defs()
		for id in sel:
			names.append("[b]%s[/b]" % PGlossaryTip.esc(String(D[String(id)].name)))
		var cnt := PProfile.counts(p)
		top.add_child(PUi.rich("%s Lv%d · %s: %s [color=#9ea8b8](출발하면 이번 회차 동안 고정 · 재선택은 영구 성장 화면)[/color] · 시작 가능 %d/%d · 회차 중 획득 %d/%d" % [PGlossaryTip.term("meta", "영구"), PProfile.level(p), PGlossaryTip.term("trait", "특성"), (", ".join(names) if names.size() > 0 else "[color=#6a7078]없음[/color]"), int(cnt.start.have), int(cnt.start.total), int(cnt.weapons.have), int(cnt.weapons.total)], 12))
	# 새 구조에서 시작 선택은 주무기만이다. 옛 구조에서 시작 자동기술로 해금해 둔 보조(회전 칼날·번개 구체)는
	# 여기서 빠지지만 프로필 해금 자료는 그대로 두고, 회차 중 보조 후보로 계속 나온다(사용자 지시 6절: 임의 삭제 금지)
	startable = startable.filter(func(wid): return PCatalog.is_main_weapon(String(wid)))
	if startable.is_empty():
		startable = PCatalog.startable()
	var row := PUi.hbox(10)
	body.add_child(row)
	var first: Button = null
	for wid in startable:
		var id := String(wid)
		var d := PCatalog.weapon(id)
		var tmp := PRun.new_run(1, id)
		var b := PBuild.derive(tmp)
		var ws: Dictionary = b.weapons[0]
		var c := PUi.card("", PUi.CARD)
		var pnl: PanelContainer = c.panel
		pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box: VBoxContainer = c.box
		box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.term("w:" + id, String(d.name)), 17))
		box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 13))
		var mods := []
		for mid in d.mods:
			if bool(d.mods[mid].impl) and (p.is_empty() or PProfile.run_unlock_ok({ "unlocks": PProfile.unlocked(p) }, "mods", id, String(mid))):
				mods.append(String(d.mods[mid].name))
		box.add_child(PUi.rich("[color=#9ea8b8]기본 %s · 개조 후보: %s[/color]" % [PUi.weapon_stats_text(ws), ", ".join(mods)], 12))
		box.add_child(PUi.spacer())
		var btn := PUi.button("이 주무기로 (다음)", func(): _pick_weapon(id), true, 14)
		box.add_child(btn)
		if first == null:
			first = btn
		row.add_child(pnl)
	default_button = first
	bottom.add_child(PUi.button("돌아가기", func(): main.go_title(), true, 14))
	if not p.is_empty():
		bottom.add_child(PUi.button("영구 성장(특성 재선택)", func(): main.show_meta(), true, 14))

func _pick_weapon(id: String) -> void:
	_weapon = id
	_step = 1
	refresh_in_place()

# ---------- ② 수동 기술 ----------
## 고를 수 있는 기술: 자료의 6종 중 구현된 것 ∩ 프로필 해금(e_skills).
## 해금 표가 없는 프로필(시험·도구)은 전부 열린 것으로 본다 — PProfile.run_unlock_ok의 기존 규칙 그대로다.
func start_skill_options() -> Array:
	var p: Dictionary = main.profile
	var run_like := { "growth": { "skills": { "q": null, "e": null } } }
	if not p.is_empty():
		run_like["unlocks"] = PProfile.unlocked(p)
	var SK := PCatalog.skills()
	var out := []
	for id in PGrowth.manual_skill_ids():
		var sid := String(id)
		if not SK.has(sid) or not bool(SK[sid].impl):
			continue
		if not PProfile.run_unlock_ok(run_like, "e_skills", sid):
			continue
		out.append(sid)
	if out.is_empty():
		out.append("slowfield") # 어떤 이유로도 고를 것이 없어지지 않게(감속장은 언제나 열려 있다)
	return out

func _refresh_skill() -> void:
	var SK := PCatalog.skills()
	var wd := PCatalog.weapon(_weapon)
	heading("수동 기술 선택 (2/2)")
	top.add_child(PUi.rich("주무기 [b]%s[/b] [color=#9ea8b8]— 이제 %s 1개를 골라 [b]Q[/b]에 Lv1으로 장착합니다. [b]E[/b]는 비어 있고, 회차 중에 다른 기술을 얻으면 그 칸에 들어갑니다(이미 Q에 가진 기술은 후보에서 빠집니다). 이 칸은 자동으로 나가는 보조무기와 다릅니다.[/color]" % [PGlossaryTip.esc(String(wd.name)), PGlossaryTip.term("e_skill", "수동 기술")], 13))
	var row := PUi.hbox(10)
	body.add_child(row)
	var first: Button = null
	for sid0 in start_skill_options():
		var sid := String(sid0)
		var d: Dictionary = SK[sid]
		var c := PUi.card("", PUi.CARD)
		var pnl: PanelContainer = c.panel
		pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box: VBoxContainer = c.box
		var head := PUi.hbox(8)
		head.add_child(PUi.icon_of(PIcons.e_key(sid), 40.0, "", "", 0.0, 0))
		head.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.term(PUi.skill_term(sid), String(d.name)), 17))
		box.add_child(head)
		box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 13))
		var cds := []
		for v in d.cooldown:
			cds.append(PUi.fmt(float(v)))
		box.add_child(PUi.rich("[color=#9ea8b8]재사용 %s초(Lv1/2/3)%s[/color]" % ["/".join(cds), (" · 피해 %d/%d/%d" % [int(d.damage[0]), int(d.damage[1]), int(d.damage[2])]) if d.has("damage") else ((" · 흡수 %d/%d/%d" % [int(d.shield[0]), int(d.shield[1]), int(d.shield[2])]) if d.has("shield") else "")], 12))
		var vn := []
		for vid in d.get("variants", {}):
			if bool(d.variants[vid].impl):
				vn.append(String(d.variants[vid].name))
		box.add_child(PUi.rich("[color=#9ea8b8]변형 후보: %s[/color]" % (", ".join(vn) if vn.size() > 0 else "없음"), 12))
		box.add_child(PUi.spacer())
		var btn := PUi.button("이 기술로 시작", func(): main.start_run(_weapon, sid), true, 14)
		box.add_child(btn)
		if first == null:
			first = btn
		row.add_child(pnl)
	default_button = first
	var back := PUi.button("주무기 다시 고르기 (Esc)", func(): _back_to_weapon(), true, 14)
	bottom.add_child(back)
	bottom.add_child(PUi.button("돌아가기", func(): main.go_title(), true, 14))

func _back_to_weapon() -> void:
	_step = 0
	_weapon = ""
	refresh_in_place()

## Esc: 2단계에서는 주무기 선택으로 되돌아간다(회차를 시작하지 않는다).
## 확인 창이 열려 있으면 그것을 먼저 닫는 것이 기존 규칙이므로 super()를 먼저 본다.
func on_escape() -> bool:
	if super():
		return true
	if _step == 1:
		_back_to_weapon()
		return true
	return false
