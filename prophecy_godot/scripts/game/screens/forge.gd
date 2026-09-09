class_name PForgeScreen
extends PScreen
## 대장간(HTML shop 'forge'·'skills' 탭 + swap 화면): 공용 공격 강화 · 개조 변경 · E 변형 변경 · 기술 교체(3단계: 새 기술 → 개조 선택 → 확인) · 제작(시험값).
## 견적·경고·비용은 PRun.swap_quote / swap_warnings / forge_next / mod_change_cost / craft_options 가 준다. 취소는 아무것도 바꾸지 않는다.

## §16 이름 통일: 화면 어디서나 금화로 사는 것은 '대장간 강화 단계', 레벨업 3택으로 오르는 것은 '무기 레벨'이다.
## 두 이름을 한 곳에서만 정해 두어, 같은 화면 안에서 '단계'와 'Lv'가 뒤섞여 같은 것으로 읽히지 않게 한다.
const FORGE_STAGE_NAME := "대장간 강화 단계"
const WEAPON_LEVEL_NAME := "무기 레벨"
## §8 이름 통일 2단계(2026-09-10): 대장간에서 하는 일은 **세 가지**이고 대상이 서로 다르다.
## 이 세 이름은 여기서만 정하고 화면 어디서나 그대로 쓴다 — 같은 화면에 '강화'가 두 개 있어 섞이지 않게 한다.
const EQUIP_UP_NAME := "장비 강화"        # 대상: 내가 가진 장비 개체(무기·방어구·방패). +0 → +1 → +2
const EQUIP_CRAFT_NAME := "장비 제작"     # 대상: 기본 장비 + 재료 → 새 장비
const SKILL_FORGE_NAME := "자동기술 강화·개조" # 대상: 자동으로 나가는 기술(무기 아님)

var _swap: Dictionary = {}   # {slot, index, new_id, mods[]} — 비어 있으면 교체 중 아님
var _craft := ""             # 미리보기 중인 제작법 id("" = 없음)
var _formula_open := false   # 가격 계산식·규칙 설명을 펼쳤는가(기본 접힘 — 사람 플레이 뒤 요구 2026-09-08)

func on_escape() -> bool:
	if super.on_escape(): # 확인 창이 열려 있으면 먼저 닫는다
		return true
	if not _swap.is_empty() or _craft != "" or _formula_open:
		_swap = {}
		_craft = ""
		_formula_open = false
		refresh()
		return true
	return false

func on_enter() -> void:
	_swap = {}
	_craft = ""
	super.on_enter()

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	if not _swap.is_empty():
		_swap_view(r)
		return
	top.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]시간 소모 없음[/color]" % PGlossaryTip.term("forge", "대장간"), 22))
	# §8: 여기서 하는 일이 무엇을 대상으로 하는지 맨 위에서 한 번에 갈라 적는다
	top.add_child(PUi.rich("[color=#9ea8b8]대장간에서 하는 일은 셋입니다 — [color=#ffd966][b]%s[/b][/color](내가 낀 장비 +0→+2) · [color=#7fd6a0][b]%s[/b][/color](기본 장비+재료 → 새 장비) · [color=#9fd6ff][b]%s[/b][/color](자동으로 나가는 기술). [b]서로 다른 것입니다.[/b][/color]" % [EQUIP_UP_NAME, EQUIP_CRAFT_NAME, SKILL_FORGE_NAME], 13))
	var g: Dictionary = r.growth
	var b := PBuild.derive(r)
	var SH := PCatalog.shop()
	var cols := two_cols(0.5)
	var left: VBoxContainer = cols.left
	var right: VBoxContainer = cols.right
	left.add_child(_equip_upgrade_card(r))
	left.add_child(_craft_card(r))
	# 자동기술 강화(2026-09-08 시험값): 전체가 아니라 **고른 자동기술 하나**에 투자한다
	var fc := PUi.card("[color=#9fd6ff]%s[/color] [color=#9ea8b8]자동기술 하나를 골라 강화한다 · [b]장비 강화가 아닙니다[/b][/color]" % PGlossaryTip.term("forge", SKILL_FORGE_NAME), PUi.CARD)
	var fbox: VBoxContainer = fc.box
	# §16 UI: **대장간 강화 단계**와 **무기 레벨**은 서로 다른 값이다. 한 줄에 섞어 적지 않고 두 줄로 갈라 이름·출처·상한을 모두 밝힌다.
	fbox.add_child(PUi.rich("[color=#9ea8b8]%s는 금화로 산다. %s은 레벨업 3택으로만 오른다 — 여기서는 못 올린다. 둘은 곱해진다.[/color]" % [FORGE_STAGE_NAME, WEAPON_LEVEL_NAME], 12))
	for w in (r.growth.weapons as Array):
		var wid := String(w.id)
		var wname := String(PCatalog.weapon(wid).name)
		var wlv: int = PRun.forge_level_of(r, wid)          # 대장간 강화 단계(금화)
		var glv: int = int(w.level)                          # 무기 레벨(성장 3택)
		var glv_cap: int = PGrowth.level_cap(r.growth, wid)
		var stage_max: int = int(SH.get("forgePerSkillMax", (SH.forge as Array).size()))
		var Fw := PRun.forge_next(r, wid)
		fbox.add_child(PUi.rich("[b]%s[/b]  [color=#8a93a6]%s[/color] [b]Lv%d/%d[/b]  [color=#8a93a6]%s[/color] [b]%d/%d단계[/b] [color=#9ea8b8]· 지금 이 기술 피해 ×%s[/color]" % [
			wname, WEAPON_LEVEL_NAME, glv, glv_cap, FORGE_STAGE_NAME, wlv, stage_max, PUi.fmt(PBuild.forge_mult_of(b, wid))], 14))
		if Fw.is_empty():
			fbox.add_child(PUi.rich("[color=#9ea8b8]%s는 더 올릴 수 없다(%s은 그대로 레벨업으로 오른다).[/color]" % [FORGE_STAGE_NAME, WEAPON_LEVEL_NAME], 13))
			fbox.add_child(_damage_share_line(r, wid))
			continue
		fbox.add_child(PUi.rich("다음 %s [b]%d → %d단계[/b]: 피해 ×%s · 금화 [color=%s][b]%d[/b][/color]%s" % [
			FORGE_STAGE_NAME, wlv, int(Fw.weaponLv), PUi.fmt(1.0 + float(SH.forgeMult[mini(int(Fw.weaponLv), (SH.forgeMult as Array).size() - 1)])),
			"#ff8c73" if int(r.gold) < int(Fw.cost) else "#ffd966", int(Fw.cost),
			(" [color=#ff8c73]· 보스 %d 처치 후 개방[/color]" % int(Fw.afterBoss)) if not bool(Fw.open) else ""], 13))
		# 효용을 눈에 보이게: 사고 나면 남는 금화 + 이 기술이 지금까지 실제로 낸 피해 비중
		fbox.add_child(PUi.rich("[color=#9ea8b8]사면 잔액 [b]%d[/b][/color]" % maxi(0, int(r.gold) - int(Fw.cost)), 12))
		fbox.add_child(_damage_share_line(r, wid))
		var lbl := "잠김" if not bool(Fw.open) else ("이 기술 %s 올리기" % FORGE_STAGE_NAME if bool(Fw.affordable) else "%d 부족" % (int(Fw.cost) - int(r.gold)))
		var wid_c := wid
		fbox.add_child(PUi.button(lbl, func(): main.forge_upgrade(wid_c), bool(Fw.open) and bool(Fw.affordable), 13))
		fbox.add_child(_alternatives_line(r, int(Fw.cost)))
	if bool(b.get("forge_legacy", false)):
		fbox.add_child(PUi.rich("[color=#9ea8b8]이전 회차에서 산 전체 강화는 그대로 유지된다. 다음 강화부터 고른 기술에만 붙는다.[/color]", 12))
	if _formula_open:
		var costs := []
		for f in SH.forge:
			costs.append(str(int(f.cost)))
		fbox.add_child(PUi.rich("[color=#9ea8b8]비용은 회차 전체에서 이어진다: %s · 2번째는 1보스, 3번째는 2보스 처치 후[/color]" % " / ".join(costs), 12))
	right.add_child(fc.panel)
	# 개조·변형 변경
	var mc := PRun.mod_change_cost(r)
	var vc := PRun.variant_change_cost(r)
	var no_offer: bool = g.get("pendingOffer", null) == null
	var vouchers: int = int(r.get("services", {}).get("mod_swap", 0))
	# 이름 통일(§6.8): 이 기능은 어디서나 '개조 변경권'. 기술 자체를 바꾸는 '기술 교체'와 다른 이름을 쓴다.
	# 버튼 글자는 실제 결제 경로와 같다 — 변경권이 있으면 '변경권 사용', 없으면 '<금액>G로 변경'.
	var vname := PGlossaryTip.term("voucher", "개조 변경권")
	var cc := PUi.card("%s·%s 변경 [color=#9ea8b8]같은 기술의 다른 후보 3택 · 보유 %s %d장[/color]" % [PGlossaryTip.term("mod", "개조"), PGlossaryTip.term("variant", "변형"), vname, vouchers])
	var cbox: VBoxContainer = cc.box
	if _formula_open:
		cbox.add_child(PUi.rich("[color=#9ea8b8]%s 1장 = 개조 1개를 같은 기술의 다른 효과로 바꿉니다(기술 자체를 바꾸는 '%s'와 다릅니다).[/color]" % [vname, PGlossaryTip.term("swap", "기술 교체")], 12))
	var any := false
	for w in g.weapons:
		var wid := String(w.id)
		var wd := PCatalog.weapon(wid)
		for m in w.mods:
			any = true
			var mid := String(m)
			var row := PUi.hbox(8)
			var mrow := PUi.hbox(6)
			mrow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			mrow.add_child(PUi.icon_of(PIcons.weapon_key(wid), 28.0, "", "", 0.0, 0))
			mrow.add_child(PUi.icon_of(PIcons.mod_key(wid, mid), 28.0, "", "", 0.0, 0))
			row.add_child(mrow)
			row.add_child(PUi.rich("[b]%s[/b]: %s" % [PGlossaryTip.esc(String(wd.name)), PGlossaryTip.esc(String(wd.mods[mid].name))], 15))
			var has_cand: bool = not PFlow._mod_candidates(r.duplicate(true), wid, mid).is_empty()
			var ok: bool = no_offer and has_cand and (bool(mc.voucher) or int(r.gold) >= int(mc.gold))
			var label := "후보 없음" if not has_cand else ("변경권 사용" if bool(mc.voucher) else "%dG로 변경" % int(mc.gold))
			row.add_child(PUi.button(label, func(): main.mod_change(wid, mid), ok, 12))
			cbox.add_child(row)
	if not any:
		cbox.add_child(PUi.rich("[color=#6a7078]변경할 개조 없음[/color]", 12))
	var e = g.skills.get("e", null)
	if e != null and e.get("variant", null) != null:
		var ed: Dictionary = PCatalog.skills()[String(e.id)]
		var row2 := PUi.hbox(8)
		row2.add_child(PUi.rich("[b]E %s[/b]: %s" % [PGlossaryTip.esc(String(ed.name)), PGlossaryTip.esc(String(ed.variants[String(e.variant)].name))], 13))
		var ok2: bool = no_offer and (bool(vc.voucher) or int(r.gold) >= int(vc.gold))
		row2.add_child(PUi.button(("변경권 사용" if bool(vc.voucher) else "%dG로 변경" % int(vc.gold)), func(): main.variant_change(), ok2, 12))
		cbox.add_child(row2)
	else:
		cbox.add_child(PUi.rich("[color=#6a7078]E 변형 없음[/color]", 12))
	if _formula_open:
		cbox.add_child(PUi.rich("[color=#9ea8b8]바꿀 후보가 없으면 아무것도 차감되지 않습니다. 3택에서 '받지 않음'을 고르면 원래 개조가 그대로 남고 %s(또는 금화)이 그대로 돌아옵니다.[/color]" % vname, 12))
	right.add_child(cc.panel)
	# 기술 교체
	var SW: Dictionary = SH.swap
	var sc := PUi.card("보유 %s [color=#9ea8b8]기술 자체를 다른 기술로 바꿉니다[/color]" % PGlossaryTip.term("swap", "기술 교체"))
	var sbox: VBoxContainer = sc.box
	for i in (g.weapons as Array).size():
		var w: Dictionary = g.weapons[i]
		var q := PRun.swap_quote(r, "weapon", i)
		var row := PUi.hbox(8)
		row.add_child(PUi.icon_of(PIcons.weapon_key(String(w.id)), 28.0, "", "", 0.0, 0))
		# 자리 이름을 먼저 적는다 — 주무기 자리는 주무기끼리, 보조 자리는 보조끼리만 바뀐다(PRun.swap_quote)
		var rname := "주무기" if String(q.get("role", "")) == "main" else ("보조" if String(q.get("role", "")) == "support" else "자동기술")
		row.add_child(PUi.rich("[color=#8a93a6]%s[/color] [b]%s[/b] [color=#8a93a6]%s[/color] Lv%d · 개조 %d · [color=#8a93a6]%s[/color] %d단계 [color=#9ea8b8]→ 같은 %s 중에서 교체[/color] [color=#ffd966][b]%d금[/b][/color] [color=#9ea8b8](%s·개조 수 보존, 강화 단계는 기술마다 따로)[/color]" % [rname, PGlossaryTip.esc(String(PCatalog.weapon(String(w.id)).name)), WEAPON_LEVEL_NAME, int(w.level), (w.mods as Array).size(), FORGE_STAGE_NAME, PRun.forge_level_of(r, String(w.id)), rname, int(q.price), WEAPON_LEVEL_NAME], 13))
		var has_opt: bool = (q.options as Array).size() > 0
		var idx := i
		row.add_child(PUi.button(("교체" if bool(q.affordable) else "%d 부족" % (int(q.price) - int(r.gold))) if has_opt else "후보 없음", func(): _swap_open("weapon", idx), has_opt and bool(q.affordable), 12))
		sbox.add_child(row)
	if e != null:
		var q2 := PRun.swap_quote(r, "e", 0)
		var row3 := PUi.hbox(8)
		row3.add_child(PUi.rich("[b]E %s[/b] Lv%d%s [color=#9ea8b8]→ 교체 %d금[/color]" % [PGlossaryTip.esc(String(PCatalog.skills()[String(e.id)].name)), int(e.level), " · 변형 1" if e.get("variant", null) != null else "", int(q2.price)], 13))
		var has_opt2: bool = (q2.options as Array).size() > 0
		row3.add_child(PUi.button(("교체" if bool(q2.affordable) else "%d 부족" % (int(q2.price) - int(r.gold))) if has_opt2 else "후보 없음", func(): _swap_open("e", 0), has_opt2 and bool(q2.affordable), 12))
		sbox.add_child(row3)
	else:
		sbox.add_child(PUi.rich("[color=#6a7078]E 없음[/color]", 12))
	if _formula_open:
		sbox.add_child(PUi.rich("[color=#9ea8b8]교체하면 옛 기술은 남지 않습니다. 확정 전까지 금화는 차감되지 않습니다.[/color]", 12))
		sbox.add_child(PUi.rich("[color=#9ea8b8]가격 계산식: %d + (레벨−1)×%d + 개조 수×%d[/color]" % [int(SW.base), int(SW.perLevel), int(SW.perMod)], 12))
	right.add_child(sc.panel)
	right.add_child(PUi.build_panel(r))
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 15)
	bottom.add_child(back)
	bottom.add_child(PUi.button("상점", func(): main.show("shop"), true, 15))
	bottom.add_child(PUi.button("장비", func(): main.show("equip"), true, 15))
	bottom.add_child(PUi.button("설명·계산식 닫기 ▼" if _formula_open else "설명·계산식 ▶", func(): _formula_open = not _formula_open; refresh(), true, 13))
	default_button = back

# ---------- 장비 강화(§4, 2026-09-10). **자동기술 강화와 다른 대상**이라 카드를 따로 둔다 ----------
## 보여 주는 것: 개체마다 지금 단계(+N) · 다음 단계의 값과 비용 · 왜 아직 못 하는지(관문 수·금화).
## 강화는 그 개체에만 붙는다는 문장을 카드 머리에 둔다 — 자동기술 강화와 헷갈리지 않게.
func _equip_upgrade_card(r: Dictionary) -> Control:
	var opts := PRun.equip_upgrade_options(r)
	var open_max := PRun.equip_upgrade_open_max(r)
	var done: int = (r.get("bossesDone", []) as Array).size()
	var c := PUi.card("[color=#ffd966]%s[/color] [color=#9ea8b8]내가 가진 장비를 +0 → +1 → +2로 · 확정 성공 · 시간 소모 없음 · 지금 열린 단계 [b]+%d[/b](관문 %d돌파)[/color]" % [
		PGlossaryTip.term("equip_upgrade", EQUIP_UP_NAME), open_max, done], PUi.CARD)
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[color=#9ea8b8]강화는 [b]강화한 그 장비[/b]에만 붙습니다. 가방에 넣어도 유지되고, 다른 장비를 껴도 따라가지 않으며, 팔거나 재료로 쓰면 함께 사라집니다. [b]기본 능력치만[/b] 오릅니다(횟수·지속·재사용 시간은 오르지 않습니다).[/color]", 12))
	if opts.is_empty():
		box.add_child(PUi.rich("[color=#6a7078]강화할 장비가 없습니다(상점에서 장비를 먼저 사세요)[/color]", 13))
		return c.panel
	for o in opts:
		var e: Dictionary = o
		var uid := String(e.uid)
		var q: Dictionary = e.next
		var row := PUi.hbox(8)
		row.add_child(PUi.icon_of("equip:" + String(e.type), 28.0, "", "", 0.0, 0))
		row.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s · %s[/color] %s" % [
			PGlossaryTip.esc(PRun.equip_name(String(e.type))), PUi.slot_name(String(e.slot)), "장착 중" if String(e.where) == "equipped" else "가방",
			("[color=#ffd966][b]+%d[/b][/color]" % int(e.plus)) if int(e.plus) > 0 else "[color=#6a7078]+0[/color]"], 14))
		row.add_child(PUi.spacer())
		if q.is_empty():
			row.add_child(PUi.rich("[color=#9ea8b8]최대 단계[/color]", 12))
		else:
			var lbl := "+%d로 강화 (%d금)" % [int(q.next), int(q.cost)]
			if not bool(q.can):
				lbl = String(q.reason)
			row.add_child(PUi.button(lbl, func(): _open_equip_upgrade(uid), bool(q.can), 13))
		box.add_child(row)
		if not q.is_empty():
			box.add_child(PUi.rich("[color=#6a7078]%s[/color]" % PUi.equip_upgrade_text(String(e.type), int(e.plus)), 11))
	if _formula_open:
		var steps: Array = PRun.equip_upgrade_rules().get("steps", [])
		var parts := []
		for st in steps:
			parts.append("+%d %d금(관문 %d돌파 후)" % [int((st as Dictionary).plus), int((st as Dictionary).cost), int((st as Dictionary).afterBoss)])
		box.add_child(PUi.rich("[color=#9ea8b8]%s · 값은 시험값입니다[/color]" % " / ".join(parts), 12))
	return c.panel

## 강화 확인 창: 값·전후 수치·차감 후 잔액을 보여 주고, 취소하면 아무것도 바뀌지 않는다.
## 확정은 견적 금액을 함께 넘겨 두 번 눌려도 두 번 차감되지 않게 한다
func _open_equip_upgrade(uid: String) -> void:
	var r := run()
	var q := PRun.equip_upgrade_next(r, uid)
	if q.is_empty():
		return
	var cost := int(q.cost)
	var qname := PRun.equip_name(String(q.type))
	open_confirm("%s%s +%d로 강화할까요?" % [PGlossaryTip.esc(qname), PUi.josa(qname, "을", "를"), int(q.next)], _equip_upgrade_body.bind(r, uid, q),
		[{ "text": "강화한다 (%d금)" % cost, "cb": func(): main.upgrade_equip(uid, cost) }])

func _equip_upgrade_body(box: VBoxContainer, r: Dictionary, uid: String, q: Dictionary) -> void:
	var tid := String(q.type)
	PUi.kv(box, "값", "[color=#ffd966][b]%d금[/b][/color] [color=#9ea8b8](금화 %d → %d)[/color]" % [int(q.cost), int(r.gold), int(r.gold) - int(q.cost)], 15)
	PUi.kv(box, "단계", "[b]+%d → +%d[/b] [color=#9ea8b8]시간 소모 없음 · 반드시 성공[/color]" % [int(q.plus), int(q.next)], 14)
	box.add_child(PUi.rich(PUi.equip_upgrade_text(tid, int(q.plus)), 13))
	# 전후 수치: 복제 회차에서 실제로 강화해 PBuild.derive를 비교한다(규칙은 건드리지 않는다)
	var dup: Dictionary = r.duplicate(true)
	PRun.equip_plus_map(dup)[uid] = int(q.next)
	var b0 := PBuild.derive(r)
	var b1 := PBuild.derive(dup)
	# 조건부 효과(비상 보호막·큰 타격 감소 등)는 파생 수치에 안 나온다 — 그때는 '변화 없음'이 아니라 무엇이 커지는지 말한다
	var same: bool = is_equal_approx(float(b0.hp_max), float(b1.hp_max)) and is_equal_approx(float(b0.speed_mult), float(b1.speed_mult)) 		and is_equal_approx(float(b0.shield), float(b1.shield)) and is_equal_approx(float(b0.range_mult), float(b1.range_mult))
	PUi.kv(box, "바뀌는 수치", "[color=#9ea8b8]기본 파생 수치는 그대로(조건이 맞을 때 발동하는 값이 커집니다)[/color]" if same else PUi.diff_text(b0, b1), 13)
	box.add_child(PUi.rich("[color=#9ea8b8]이 강화는 [b]이 장비 하나[/b]에만 붙습니다. 다른 장비로 옮기거나 제작 완성품에 물려줄 수 없습니다.[/color]", 12))
	box.add_child(PUi.rich("[color=#9ea8b8]취소하면 금화·장비가 그대로입니다.[/color]", 12))

# ---------- 제작(시험값 meta.json): 해금된 제작법 목록 → 미리보기(소비 장비·재료·금화, 효과 차이) → 확정/취소. 확정 전에는 아무것도 소비하지 않는다 ----------
func _craft_card(r: Dictionary) -> Control:
	var opts := PRun.craft_options(r)
	var CE := PCatalog.crafted_equipment()
	var live := 0   # 폐기(§1)한 제작법은 세지도 보이지도 않는다
	for id0 in CE:
		if not PCatalog.equipment_retired(String(id0)):
			live += 1
	var known := opts.size()
	var c := PUi.card("[color=#7fd6a0]%s[/color] [color=#9ea8b8]제작법 %d/%d 해금 · 기본 장비 하나 + 재료 + 금화 · 이번 회차 한정 · 시간 소모 없음 · 분해 없음 · [b]자동기술 강화가 아닙니다[/b][/color]" % [PGlossaryTip.term("craft", EQUIP_CRAFT_NAME), known, live])
	var box: VBoxContainer = c.box
	if opts.is_empty():
		box.add_child(PUi.rich("[color=#6a7078]해금된 제작법 없음 (영구 성장 화면의 도감에서 조건 확인)[/color]", 12))
	for o in opts:
		var opt: Dictionary = o
		var id := String(opt.id)
		var d: Dictionary = opt.def
		var row := PUi.hbox(8)
		var ings := []
		for ing in opt.ingredients:
			var have_txt := ""
			if String(ing.kind) == "equipment":
				have_txt = "[color=#9fe89f]장착[/color]" if String(ing.where) == "equipped" else ("[color=#9fe89f]가방[/color]" if String(ing.where) == "bag" else "[color=#ff8c73]없음[/color]")
			else:
				have_txt = "[color=%s]%d/%d[/color]" % ["#9fe89f" if int(ing.have) >= int(ing.n) else "#ff8c73", int(ing.have), int(ing.n)]
			ings.append("%s %s" % [PGlossaryTip.esc(String(ing.name)), have_txt])
		row.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]%s[/color]\n[color=#9ea8b8]%s[/color] · %s · 수수료 [color=%s]%d[/color]" % [PGlossaryTip.term("eq:" + id, String(d.name)), PUi.slot_name(String(d.slot)), PGlossaryTip.esc(String(d.short)), " + ".join(ings), "#ffd966" if bool(opt.affordable) else "#ff8c73", int(opt.fee)], 12))
		var can: bool = bool(opt.can)
		row.add_child(PUi.button("미리보기" if can else ("보유 중" if bool(opt.owned) else "재료 부족"), func(): _craft = id; refresh(), can, 12))
		box.add_child(row)
	if _craft != "" and PCatalog.crafted_equipment().has(_craft):
		var opt := PRun.craft_option(r, _craft)
		if bool(opt.can):
			box.add_child(_craft_preview(r, opt))
		else:
			_craft = ""
	# 잠긴 제작법: 이름·짧은 효과·조건(발견 경로 안내 없음)
	var locked := []
	for id in CE:
		if PCatalog.equipment_retired(String(id)):
			continue # 폐기 장비는 '잠김'으로도 보여 주지 않는다(다시 열릴 것처럼 읽히지 않게)
		if not PProfile.run_unlock_ok(r, "recipes", String(id)):
			locked.append("[b]%s[/b](%s) — %s" % [PGlossaryTip.esc(String(CE[id].name)), PGlossaryTip.esc(String(CE[id].short)), PGlossaryTip.esc(PProfile.unlock_text("recipes", String(id)))])
	if locked.size() > 0:
		box.add_child(PUi.rich("[color=#6a7078]잠김: %s[/color]" % " · ".join(locked), 11))
	return c.panel

func _craft_preview(r: Dictionary, opt: Dictionary) -> Control:
	var id := String(opt.id)
	var d: Dictionary = opt.def
	var pv: Dictionary = opt.preview
	var c := PUi.card("%s 미리보기 [color=#9ea8b8](확정 전 소비 없음)[/color]" % PGlossaryTip.esc(String(d.name)), PUi.CARD_ON, 13)
	var box: VBoxContainer = c.box
	var consume := []
	var uses_equipped := false
	var burn_plus := 0   # 재료로 사라지는 강화 단계의 합(§4: 완성품에 계승하지 않는다 — 처리 미확정)
	for ing in opt.ingredients:
		if String(ing.kind) == "equipment":
			var pl := int(ing.get("plus", 0))
			consume.append("%s%s(%s)" % [String(ing.name), (" +%d" % pl) if pl > 0 else "", "장착 중" if String(ing.where) == "equipped" else "가방"])
			burn_plus += pl
			if String(ing.where) == "equipped":
				uses_equipped = true
		else:
			consume.append("%s %d" % [String(ing.name), int(ing.n)])
	consume.append("금화 %d" % int(opt.fee))
	PUi.kv(box, "소비", PGlossaryTip.esc(", ".join(consume)), 12)
	PUi.kv(box, "효과", PGlossaryTip.esc(String(d.desc)), 12)
	var cur = r.equipment.get(String(d.slot), null)
	PUi.kv(box, "현재 %s" % PUi.slot_name(String(d.slot)), PUi.equip_line(String(cur)) if cur != null else "[color=#6a7078]없음[/color]", 12)
	if not pv.is_empty():
		var b0: Dictionary = pv.before
		var b1: Dictionary = pv.after
		PUi.kv(box, "제작·장착 시 수치", "최대 체력 %d → %d · 이동 ×%s → ×%s · 시작 보호막 %d → %d · 사거리 ×%s → ×%s" % [int(float(b0.hp_max)), int(float(b1.hp_max)), PUi.fmt(float(b0.speed_mult)), PUi.fmt(float(b1.speed_mult)), int(float(b0.shield)), int(float(b1.shield)), PUi.fmt(float(b0.range_mult)), PUi.fmt(float(b1.range_mult))], 12)
	if uses_equipped:
		box.add_child(PUi.rich("[color=#ff8c73]장착 중인 장비가 재료로 소비됩니다(그 슬롯은 비거나 완성품으로 교체).[/color]", 11))
	# §4: 강화 자동 계승은 승인되지 않았다. 몰래 물려주지도, 조용히 태우지도 않고 **미리 말한다**
	if burn_plus > 0:
		box.add_child(PUi.rich("[color=#ff8c73]재료 장비의 [b]강화 +%d가 사라집니다[/b] — 완성품은 +0에서 시작하고 환급도 없습니다(처리 방식 미확정).[/color]" % burn_plus, 11))
	else:
		box.add_child(PUi.rich("[color=#9ea8b8]완성품은 +0에서 시작합니다(재료 장비의 강화를 물려받지 않습니다).[/color]", 11))
	var row := PUi.hbox(8)
	var confirm := PUi.button("확정 후 장착", func(): _craft = ""; main.craft(id, true, true), true, 13)
	row.add_child(confirm)
	row.add_child(PUi.button("확정 후 보관", func(): _craft = ""; main.craft(id, true, false), true, 13))
	row.add_child(PUi.button("취소 (Esc)", func(): _craft = ""; refresh(), true, 13))
	box.add_child(row)
	default_button = confirm
	return c.panel

# ---------- 기술 교체 흐름 ----------
func _swap_open(slot: String, index: int) -> void:
	_swap = { "slot": slot, "index": index, "new_id": "", "mods": [] }
	refresh()

func _swap_view(r: Dictionary) -> void:
	var slot := String(_swap.slot)
	var index := int(_swap.index)
	var q := PRun.swap_quote(r, slot, index)
	if q.is_empty():
		_swap = {}
		refresh()
		return
	var is_e := slot == "e"
	var cur_name := String(PCatalog.skills()[String(q.current.id)].name) if is_e else String(PCatalog.weapon(String(q.current.id)).name)
	var hrow := PUi.hbox(8)
	hrow.add_child(PUi.rich("[b]기술 교체[/b] [color=#9ea8b8]%s %s Lv%d%s → 비용[/color] [color=#ffd966][b]%d[/b][/color]" % [PGlossaryTip.esc(cur_name), ("기술 레벨" if is_e else WEAPON_LEVEL_NAME), int(q.level), (" · 개조 %d개 보존" % int(q.modCount)) if int(q.modCount) > 0 else "", int(q.price)], 20))
	hrow.add_child(PUi.spacer())
	hrow.add_child(PUi.button("취소 (변경 없음, Esc)", func(): on_escape(), true, 13))
	top.add_child(hrow)
	var new_id := String(_swap.new_id)
	if new_id == "":
		top.add_child(PUi.rich("[color=#9ea8b8]1/3 새 기술을 고르세요. 레벨 %d과 개조 수 %d은 그대로 이어집니다.[/color]" % [int(q.level), int(q.modCount)], 13))
		var row := PUi.hbox(10)
		for oid in q.options:
			var id := String(oid)
			var d: Dictionary = PCatalog.skills()[id] if is_e else PCatalog.weapon(id)
			var c := PUi.card("", PUi.CARD)
			var p: PanelContainer = c.panel
			p.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var box: VBoxContainer = c.box
			box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.term(("e:" if is_e else "w:") + id, String(d.name)), 15))
			box.add_child(PUi.rich(PGlossaryTip.esc(String(d.desc)), 12))
			if not is_e:
				var tmp: Dictionary = r.duplicate(true)
				tmp.growth.weapons[index] = { "id": id, "level": int(q.level), "mods": [] }
				var ws: Dictionary = PBuild.derive(tmp).weapons[index]
				var mods := []
				for m in d.mods:
					if bool(d.mods[m].impl):
						mods.append(String(d.mods[m].name))
				box.add_child(PUi.rich("[color=#9ea8b8]Lv%d %s · 개조 후보: %s[/color]" % [int(q.level), PUi.weapon_stats_text(ws), ", ".join(mods)], 11))
			box.add_child(PUi.spacer())
			box.add_child(PUi.button("이 기술로", func(): _swap_pick(id), true, 13))
			row.add_child(p)
		body.add_child(row)
		return
	var d2: Dictionary = PCatalog.skills()[new_id] if is_e else PCatalog.weapon(new_id)
	var pool := []
	if is_e:
		for v in d2.get("variants", {}):
			if bool(d2.variants[v].impl):
				pool.append(String(v))
	else:
		for m in d2.mods:
			if bool(d2.mods[m].impl):
				pool.append(String(m))
	var need := mini(int(q.modCount), pool.size())
	var chosen: Array = _swap.mods
	var chosen_names := []
	for m in chosen:
		chosen_names.append(String((d2.variants if is_e else d2.mods)[String(m)].name))
	if chosen.size() < need:
		top.add_child(PUi.rich("[color=#9ea8b8]2/3 %s의 %s를 %d개 고르세요 (%d/%d).%s[/color]" % [PGlossaryTip.esc(String(d2.name)), "변형" if is_e else "개조", need, chosen.size(), need, (" 선택: " + ", ".join(chosen_names)) if chosen.size() > 0 else ""], 13))
		var row2 := PUi.hbox(10)
		for m in pool:
			var mid := String(m)
			if chosen.has(mid):
				continue
			var md: Dictionary = (d2.variants if is_e else d2.mods)[mid]
			var c := PUi.card("", PUi.CARD)
			var p: PanelContainer = c.panel
			p.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var box: VBoxContainer = c.box
			box.add_child(PUi.rich("[b]%s[/b]" % PGlossaryTip.esc(String(md.name)), 15))
			box.add_child(PUi.rich(PGlossaryTip.esc(String(md.desc)), 12))
			box.add_child(PUi.spacer())
			box.add_child(PUi.button("선택", func(): _swap_mod(mid), true, 13))
			row2.add_child(p)
		body.add_child(row2)
		bottom.add_child(PUi.button("처음부터", func(): _swap_open(slot, index), true, 13))
		return
	top.add_child(PUi.rich("[color=#9ea8b8]3/3 확인[/color]", 13))
	var warns := [] if is_e else PRun.swap_warnings(r, slot, index, new_id)
	var cc := PUi.card("")
	var cbox: VBoxContainer = cc.box
	# 현재 → 교체 후를 같은 아이콘·이름·배치로(선택 중인 결과를 이미 보유한 효과처럼 보이지 않게 '→'로 분리)
	var irow := PUi.hbox(8)
	irow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	irow.add_child(PUi.icon_of(("skill:e:" + String(q.current.id)) if is_e else PIcons.weapon_key(String(q.current.id)), 40.0, cur_name, "현재", 110.0))
	irow.add_child(PUi.rich("[b]→[/b]", 20))
	irow.add_child(PUi.icon_of(("skill:e:" + new_id) if is_e else PIcons.weapon_key(new_id), 40.0, String(d2.name), "교체 후", 110.0))
	for m in chosen:
		irow.add_child(PUi.icon_of(("skill:e:%s:%s" % [new_id, String(m)]) if is_e else PIcons.mod_key(new_id, String(m)), 28.0, "", "", 0.0, 0))
	cbox.add_child(irow)
	PUi.kv(cbox, "바뀌는 것", "[b]%s → %s[/b] [color=#9ea8b8](%s %d 그대로)[/color]" % [PGlossaryTip.esc(cur_name), PGlossaryTip.esc(String(d2.name)), WEAPON_LEVEL_NAME, int(q.level)], 13)
	if not is_e:
		# §16: 무기 레벨은 따라오지만 **대장간 강화 단계는 기술마다 따로**다. 교체 뒤 새 기술의 단계는 그 기술이 가진 단계다(0일 수 있다).
		var cur_stage: int = PRun.forge_level_of(r, String(q.current.id))
		var new_stage: int = PRun.forge_level_of(r, new_id)
		PUi.kv(cbox, FORGE_STAGE_NAME, "[b]%d단계 → %d단계[/b] [color=#9ea8b8](%s는 기술마다 따로 쌓인다 — 따라오지 않는다. 옛 기술의 단계는 그 기술로 돌아가면 그대로 있다)[/color]" % [cur_stage, new_stage, FORGE_STAGE_NAME], 13)
	PUi.kv(cbox, "변형" if is_e else "개조", "[b]%s[/b]%s" % [(", ".join(chosen_names) if chosen_names.size() > 0 else "없음"), (" [color=#9ea8b8](후보가 %d개뿐이라 %d개는 비어 있음 · 비용은 동일)[/color]" % [need, int(q.modCount) - need]) if int(q.modCount) > need else ""], 13)
	PUi.kv(cbox, "비용", "[color=#ffd966][b]%d[/b][/color] [color=#9ea8b8](남는 금화 %d)[/color]" % [int(q.price), int(r.gold) - int(q.price)], 13)
	if not is_e:
		var before: Dictionary = PBuild.derive(r).weapons[index]
		var tmp2: Dictionary = r.duplicate(true)
		var mods_out := []
		for m in chosen:
			mods_out.append(String(m))
		tmp2.growth.weapons[index] = { "id": new_id, "level": int(q.level), "mods": mods_out }
		var after: Dictionary = PBuild.derive(tmp2).weapons[index]
		PUi.kv(cbox, "수치", "[b]%s[/b]  →  [b]%s[/b]" % [PUi.weapon_stats_text(before), PUi.weapon_stats_text(after)], 13)
	if warns.size() > 0:
		var wn := []
		for w in warns:
			wn.append(PGlossaryTip.esc(String(w)))
		PUi.kv(cbox, "[color=#ff8c73]경고[/color]", "[color=#ff8c73]공용 증강 %s이(가) 적용 대상을 잃습니다[/color]" % ", ".join(wn), 13)
	var row3 := PUi.hbox(8)
	var confirm := PUi.button("확정 (금화 %d 차감)" % int(q.price), func(): _swap_confirm(), bool(q.affordable), 14)
	row3.add_child(confirm)
	row3.add_child(PUi.button("취소 (변경 없음)", func(): on_escape(), true, 14))
	cbox.add_child(row3)
	body.add_child(cc.panel)
	default_button = confirm

func _swap_pick(id: String) -> void:
	_swap.new_id = id
	_swap.mods = []
	refresh()

func _swap_mod(m: String) -> void:
	if not (_swap.mods as Array).has(m):
		(_swap.mods as Array).append(m)
	refresh()

func _swap_confirm() -> void:
	var sw := _swap
	_swap = {}
	main.apply_swap(String(sw.slot), int(sw.index), String(sw.new_id), sw.mods)

## 이 자동기술이 이번 회차에서 실제로 낸 유효 피해 비중. 강화가 값을 하는지 눈으로 보게 하는 줄이다.
##
## §15 고친 것: 예전에는 `String(g.owner) == weapon_id`로 비교했다. 통계의 owner 키는 `weapon:orb`인데
## weapon_id는 `orb`라 **언제나 거짓**이었고, 실제로 피해를 냈어도 "0%(기록 없음)"만 떴다.
## 이제 접두사를 화면에서 짜깁기하지 않고 **PStats.owner_key 규약**을 그대로 쓴다(PStats.owner_share 안에서).
##
## 범위는 통계 화면의 '런 전체'와 **같다**(둘 다 필터 없는 PStats.aggregate). 그래서 두 화면의 숫자가 어긋나지 않는다.
## 합산 정책도 통계와 같다: 직접 피해 + 그 기술에 귀속된 파생(지속 피해·개조 등) = by_owner의 amount.
##
## 세 가지 사정을 **서로 다른 문구**로 적는다(하나로 뭉뚱그리면 "0%"가 무엇을 뜻하는지 알 수 없다):
##   기록 없음   아직 정산된 전투가 없다               계측 없음  전투 기록은 있는데 출처별 피해가 안 남았다(계측 누락 — 고쳐야 할 결함)
##   피해 0      기록도 계측도 있는데 이 기술이 0이다
func _damage_share_line(r: Dictionary, weapon_id: String) -> Control:
	var s: Dictionary = PStats.owner_share(r, weapon_id)
	match String(s.state):
		"no_record":
			return PUi.rich("[color=#9ea8b8]이번 회차 피해 기여 [b]기록 없음[/b] · 아직 정산된 전투가 없다(출격하면 쌓인다)[/color]", 12)
		"no_metric":
			return PUi.rich("[color=#ff8c73]이번 회차 피해 기여 [b]계측 없음[/b] · 전투 %d회 기록에 출처별 피해가 남아 있지 않다(통계 결함)[/color]" % int(s.n), 12)
		"zero":
			return PUi.rich("[color=#9ea8b8]이번 회차 피해 기여 [b]0%%[/b] · 전투 %d회 기록에 이 기술이 낸 피해가 없다[/color]" % int(s.n), 12)
	return PUi.rich("[color=#9ea8b8]이번 회차 피해 기여 [color=#ffd966][b]%s%%[/b][/color] · 직접 %s + 파생 %s = [b]%s[/b] / 전체 %s · 전투 %d회 (피해 통계의 '런 전체'와 같은 범위)[/color]" % [
		str(s.share), str(s.direct), str(s.derived), str(s.amount), str(s.total), int(s.n)], 12)

## 같은 금화를 다른 곳에 쓰면 무엇을 살 수 있는가(공격 강화만 정답이 되지 않게 나란히 보여준다).
## 값은 전부 규칙·데이터에서 읽는다(화면이 계산하지 않는다)
func _alternatives_line(r: Dictionary, gold: int) -> Control:
	var SH := PCatalog.shop()
	var parts := []
	parts.append("장비 %d~%d" % [int(SH.sellPrice.armor) * 4, int(SH.price.weapon)])
	var cheap := ""
	var cheap_p := 1 << 30
	for id in PConsumables.prep_ids():
		if PConsumables.price(String(id)) < cheap_p:
			cheap_p = PConsumables.price(String(id))
			cheap = String(id)
	if cheap != "":
		parts.append("준비물 %d~%d" % [cheap_p, _max_prep_price()])
	parts.append("회복약 %d(체력 +%d)" % [PConsumables.price("potion"), int(float(PConsumables.potion_def().heal))])
	parts.append("무료 휴식권 %d(완전 회복·시간 0칸)" % PRun.merchant_service_price("free_rest"))
	parts.append("재고 새로고침 %d" % PRun.stock_refresh_cost(r))
	return PUi.rich("[color=#6a7078]같은 %d금으로: %s[/color]" % [gold, " · ".join(parts)], 11)

func _max_prep_price() -> int:
	var m := 0
	for id in PConsumables.prep_ids():
		m = maxi(m, PConsumables.price(String(id)))
	return m
