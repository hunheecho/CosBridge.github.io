class_name PUi
extends RefCounted
## 화면 공용 위젯 헬퍼(코드로 만드는 Control). 색·글자 크기·카드 모양은 여기서만 정한다.
## 규칙 수치는 절대 여기서 계산하지 않는다(화면은 PRun/PBuild/PGrowth가 준 값을 보여 주기만 한다).

const BG := Color(0.078, 0.094, 0.114)
const CARD := Color(0.13, 0.15, 0.18)
const CARD_ON := Color(0.15, 0.2, 0.17)
const CARD_OFF := Color(0.11, 0.12, 0.13)
const CARD_BOSS := Color(0.2, 0.14, 0.14)
const DIM := Color(0.62, 0.66, 0.72)
const GOLD := Color(1.0, 0.85, 0.4)
const WARN := Color(1.0, 0.55, 0.45)
const OK := Color(0.6, 0.9, 0.6)
const LINK := Color(0.65, 0.85, 1.0)

static func stylebox(color: Color, radius: int = 6, margin: int = 8, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(float(margin))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb

static func label(text: String, size: int = 14, color: Color = Color.WHITE, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## 용어 링크({{id}}·[url=id])가 살아 있는 본문. 툴팁 층에 연결된다
static func rich(text: String, size: int = 14, color: Color = Color.WHITE) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	r.text = PGlossaryTip.markup(text)
	PGlossaryTip.bind(r)
	return r

## 줄바꿈 없는 짧은 본문(상단 줄·표 칸): 내용 너비만 차지한다
static func rich_nowrap(text: String, size: int = 14, color: Color = Color.WHITE) -> RichTextLabel:
	var r := rich(text, size, color)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.size_flags_horizontal = Control.SIZE_FILL
	return r

static func button(text: String, cb: Callable, enabled: bool = true, size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", size)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

static func spacer(h: int = 0) -> Control:
	var c := Control.new()
	if h > 0:
		c.custom_minimum_size = Vector2(0, h)
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## 카드: {panel: PanelContainer, box: VBoxContainer}. 제목이 있으면 첫 줄에 넣는다
static func card(title: String = "", color: Color = CARD, title_size: int = 15) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(color))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(4)
	p.add_child(v)
	if title != "":
		v.add_child(rich("[b]%s[/b]" % title, title_size))
	return { "panel": p, "box": v }

## 키·값 한 줄(키는 흐리게)
static func kv(box: Control, key: String, val: String, size: int = 13) -> void:
	box.add_child(rich("[color=#9ea8b8]%s[/color]  %s" % [PGlossaryTip.esc(key), val], size))

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func fmt(n: float) -> String:
	var v: float = snapped(n, 0.1)
	if v == floor(v):
		return str(int(v))
	return str(v)

static func mats_text(mats: Dictionary) -> String:
	var parts := []
	var M := PCatalog.materials()
	for k in mats:
		if int(mats[k]) > 0:
			parts.append("%s %d" % [String(M[String(k)].name), int(mats[k])])
	return ", ".join(parts)

static func balance_name(run: Dictionary) -> String:
	var BS := PCatalog.balance_sets()
	var bal := String(run.get("balance", "current"))
	return String(BS[bal].name) if BS.has(bal) else bal

## 자동 로드 Game 없이도(헤드리스 -s 시험) 버전 문자열을 읽는다
static func version() -> String:
	var gs: GDScript = load("res://scripts/game/game.gd")
	return String(gs.get_script_constant_map().get("VERSION", "?"))

static func settings_short(run: Dictionary) -> String:
	return "%s · %s · 시드 %d" % [version(), balance_name(run), int(run.get("seed", 0))]

## 거점·상점 공용 상단 줄(HTML header): 날짜 · 시간대 · 보스 · 체력 · 금화 · 설정
static func header(run: Dictionary) -> Control:
	var b := PBuild.derive(run)
	var h := hbox(14)
	h.add_child(rich_nowrap("[color=#9ea8b8]날짜[/color] [b]%d일차[/b]" % int(run.day), 14))
	var slots := PRun.time_slots()
	var cur := PRun.slot_index(run)
	var done: bool = int(run.hours) <= 0
	var strip := ""
	for i in slots.size():
		var nm := String(slots[i])
		if done or i < cur:
			strip += "[color=#5a606a]%s[/color] " % nm
		elif i == cur:
			strip += "[color=#ffe066][b]%s[/b][/color] " % nm
		else:
			strip += "%s " % nm
	h.add_child(rich_nowrap("%s [color=#9ea8b8](남은 %d칸)[/color] %s" % [PGlossaryTip.term("timeslot", "시간대"), int(run.hours), strip.strip_edges()], 14))
	var nb := PRun.next_boss(run)
	var nbc := PRun.next_boss_cfg(run)
	var left := PRun.boss_days_left(run)
	var stages := PRun.stage_count(run)
	var when := "완료" if nb.is_empty() else ("%d일 뒤" % left if left > 0 else "오늘")
	var lbl := ("보스 %d/%d · %s" % [int(run.get("stage", 0)) + 1, stages, String(nbc.name)]) if stages > 1 and not nb.is_empty() else "보스"
	h.add_child(rich_nowrap("[color=#9ea8b8]%s[/color] [b]%s%s[/b]" % [lbl, ("[color=#ff8c73]" if left <= 1 and not nb.is_empty() else ""), when + ("[/color]" if left <= 1 and not nb.is_empty() else "")], 14))
	var ws := PRun.world_stage(run)
	if ws > 0:
		h.add_child(rich_nowrap("[color=#d24a3a][b]%s[/b][/color]" % PGlossaryTip.esc(String(PRun.world_stage_def(run).name)), 14))
	h.add_child(rich_nowrap("[color=#9ea8b8]체력[/color] [b]%d / %d[/b]" % [int(float(run.hp)), int(float(b.hp_max))], 14))
	h.add_child(rich_nowrap("[color=#9ea8b8]금화[/color] [color=#ffd966][b]%d[/b][/color]" % int(run.gold), 14))
	var sp := spacer()
	h.add_child(sp)
	h.add_child(rich("[color=#9ea8b8]%s[/color]" % PGlossaryTip.esc(settings_short(run)), 11))
	return h

## 장비 한 줄(이름은 용어 링크)
static func equip_line(id: String) -> String:
	var d: Dictionary = PCatalog.equipment_def(id)
	return "[b]%s[/b] [color=#9ea8b8]%s[/color]" % [PGlossaryTip.term("eq:" + id, String(d.name)), PGlossaryTip.esc(String(d.short))]

static func slot_name(slot: String) -> String:
	return String(PCatalog.world().equip_slot_names.get(slot, slot))

## 장비 패널(HTML equipPanel)
static func equip_panel(run: Dictionary) -> Control:
	var b := PBuild.derive(run)
	var c := card("%s [color=#9ea8b8]슬롯당 1개 · 이번 회차 한정 · %s %d개[/color]" % [PGlossaryTip.term("equipment", "장비"), PGlossaryTip.term("bag", "가방"), (run.bag as Array).size()])
	var box: VBoxContainer = c.box
	for sl in PCatalog.world().equip_slots:
		var slot := String(sl)
		var id = run.equipment.get(slot, null)
		box.add_child(rich("[color=#9ea8b8]%s[/color]  %s" % [slot_name(slot), (equip_line(String(id)) if id != null else "[color=#6a7078]비어 있음[/color]")], 13))
	var forge_txt := ""
	if int(b.forge) > 0:
		forge_txt = " · %s %d단계(자동기술 피해 ×%s)" % [PGlossaryTip.term("forge", "공용 공격 강화"), int(b.forge), fmt(float(b.forge_mult))]
	box.add_child(rich("[color=#9ea8b8]최대 체력 %d · 이동 ×%s · 시작 보호막 %d%s[/color]" % [int(float(b.hp_max)), fmt(float(b.speed_mult)), int(float(b.shield)), forge_txt], 12))
	return c.panel

## 성장 패널(HTML buildPanel): 실제 파생 수치(PBuild.derive)만 표시
static func build_panel(run: Dictionary) -> Control:
	var b := PBuild.derive(run)
	var g: Dictionary = run.growth
	var S: Dictionary = PCatalog.growth().SLOTS
	var pend := int(g.pendingLevelUps)
	var c := card("성장 [color=#9ea8b8]Lv %d · 경험치 %d/%d%s[/color]" % [int(g.level), int(floor(float(g.xp))), PGrowth.xp_need(int(g.level)), (" · [color=#ff8c73]미처리 레벨업 %d[/color]" % pend) if pend > 0 else ""])
	var box: VBoxContainer = c.box
	if g.get("steer", null) != null:
		box.add_child(rich("[color=#ffe066]%s[/color] 다음 레벨업은 [b]%s[/b] 후보만 제시 (%s, 1회)" % [PGlossaryTip.term("steer", "성장 예약"), PSortie.kind_name(String(g.steer.kind)), "심층 보상" if String(g.steer.get("from", "")) == "deep" else "임무 보상"], 12))
	box.add_child(rich("[b]%s %d/%d[/b]" % [PGlossaryTip.term("auto_skill", "자동기술"), (b.weapons as Array).size(), int(S.weapons)], 13))
	for w in b.weapons:
		var wd: Dictionary = w
		var mods := []
		for mid in wd.mods:
			mods.append(String(wd.def.mods[String(mid)].name))
		var rng_txt := (" · 사거리 %d" % int(round(float(wd.range)))) if float(wd.range) > 0.0 else ""
		box.add_child(rich("  [b]%s[/b] Lv%d/%d [color=#9ea8b8]피해 %s · 주기 %s초%s[/color] · %s %d/%d: %s" % [PGlossaryTip.term("w:" + String(wd.id), String(wd.name)), int(wd.level), int(S.weaponMax), fmt(float(wd.damage)), fmt(float(wd.interval)), rng_txt, PGlossaryTip.term("mod", "개조"), mods.size(), int(S.weaponMods), (", ".join(mods) if mods.size() > 0 else "없음")], 12))
	for i in int(S.weapons) - (b.weapons as Array).size():
		box.add_child(rich("  [color=#6a7078]빈 자동기술 슬롯 (레벨업 또는 상점)[/color]", 12))
	box.add_child(rich("[b]수동 기술[/b]", 13))
	for slot in ["q", "e"]:
		var sk = g.skills.get(slot)
		if sk == null:
			box.add_child(rich("  [b]E[/b]: [color=#6a7078]비어 있음 (레벨업 또는 상점)[/color]", 12))
			continue
		var d: Dictionary = PCatalog.skills()[String(sk.id)]
		var cd := float(d.cooldown[mini(3, int(sk.level)) - 1]) * float(b.skill_cd_mult)
		var vtxt := (" · 변형: " + String(d.variants[String(sk.variant)].name)) if sk.get("variant", null) != null else ""
		var term_id := "slowfield" if slot == "q" else "e:" + String(sk.id)
		box.add_child(rich("  [b]%s[/b]: [b]%s[/b] Lv%d/%d [color=#9ea8b8]재사용 %s초%s[/color]" % [String(d.key), PGlossaryTip.term(term_id, String(d.name)), int(sk.level), int(S.skillMax), fmt(cd), vtxt], 12))
	var commons := []
	var CM := PCatalog.commons()
	for k in g.commons:
		if int(g.commons[k]) > 0:
			var cd2: Dictionary = CM[String(k)]
			commons.append("[b]%s[/b]%s" % [String(cd2.name), (" %d/%d" % [int(g.commons[k]), int(cd2.max)]) if int(cd2.max) > 1 else ""])
	var passives := []
	var PS := PCatalog.passives()
	for k in g.passives:
		if int(g.passives[k]) > 0:
			passives.append("[b]%s[/b] %d/%d" % [String(PS[String(k)].name), int(g.passives[k]), int(PS[String(k)].max)])
	var rewards := []
	for id in g.bossRewards:
		rewards.append("[b]%s[/b]" % String(PCatalog.boss_rewards()[String(id)].name))
	box.add_child(rich("%s %d/%d: %s · %s %d/%d: %s%s" % [PGlossaryTip.term("common", "공용 증강"), PGrowth.common_count(g), int(S.commons), (", ".join(commons) if commons.size() > 0 else "[color=#6a7078]없음[/color]"), PGlossaryTip.term("passive", "패시브"), PGrowth.passive_count(g), int(S.passives), (", ".join(passives) if passives.size() > 0 else "[color=#6a7078]없음[/color]"), (" · 희귀 보상: " + ", ".join(rewards)) if rewards.size() > 0 else ""], 12))
	return c.panel

## 피해 통계 표 하나(PStats.aggregate 결과)
static func stats_table(a: Dictionary, title: String) -> Control:
	var v := vbox(2)
	if int(a.n) == 0:
		v.add_child(rich("[b]%s[/b] [color=#9ea8b8]기록 없음[/color]" % title, 13))
		return v
	v.add_child(rich("[b]%s[/b] [color=#9ea8b8]전투 %d회 · 실제 전투 %s초 · 총 유효 피해 %s · 전체 DPS %s · 받은 피해 %s[/color]" % [title, int(a.n), str(a.elapsed), str(a.total), str(a.dpsAll), str(a.taken)], 13))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	var heads := ["출처", "분류", PGlossaryTip.term("effective", "유효 피해"), "비중", "보유 시간", PGlossaryTip.term("dps", "DPS")]
	for hd in heads:
		var hl := rich("[color=#9ea8b8]%s[/color]" % String(hd), 12)
		hl.fit_content = true
		hl.size_flags_horizontal = Control.SIZE_FILL
		hl.custom_minimum_size = Vector2(90, 0)
		grid.add_child(hl)
	for r in a.rows:
		var row: Dictionary = r
		var cells := [PGlossaryTip.esc(String(row.name)), "[color=#9ea8b8]%s[/color]" % String(PStats.CATS.get(String(row.cat), row.cat)), str(row.amount), "%s%%" % str(row.share), "%s초" % str(row.active), "[b]%s[/b]" % str(row.dps)]
		for ctext in cells:
			var cl := rich(String(ctext), 12)
			cl.size_flags_horizontal = Control.SIZE_FILL
			cl.custom_minimum_size = Vector2(90, 0)
			grid.add_child(cl)
	v.add_child(grid)
	var cats := []
	for k in a.cats:
		cats.append("%s %s" % [String(PStats.CATS.get(String(k), k)), str(a.cats[k])])
	v.add_child(rich("[color=#9ea8b8]분류별: %s[/color]" % " · ".join(cats), 11))
	return v
