class_name PStatsScreen
extends PScreen
## 런 피해 통계(사용자 지시 §15 · REVIEW §7).
## 기본 표: 기술별 [총 피해 / 기여율 / 전투 평균 DPS] 한 줄씩. 펼치면 그 기술의 파생(직접·지속·개조·공용) 행과 DPS 분모를 본다.
## 필터: 런 전체 / 최근 전투 / 보스별. 보호막 흡수·회복·체력 손실은 피해 표와 섞지 않고 따로 적는다.
## DPS 정의는 표가 아니라 아래 '도움말'에 둔다.
##
## 규칙 계산은 하지 않는다: PStats.aggregate / PStats.by_owner / run.dmgStats 가 준 값을 보여 주기만 한다.

const FILTERS := [["all", "런 전체"], ["recent", "최근 전투"], ["boss", "보스별"]]

var _filter := "all"
var _open_owner := ""      # 펼친 기술 행(owner 키). "" = 모두 접힘
var _help_open := false

func on_escape() -> bool:
	if _help_open:
		_help_open = false
		refresh()
		return true
	if _open_owner != "":
		_open_owner = ""
		refresh()
		return true
	return false

func refresh() -> void:
	clear_all()
	var r := run()
	if r.is_empty():
		return
	top.add_child(PUi.header(r))
	top.add_child(PUi.rich("[b]피해 통계[/b] [color=#9ea8b8]기술별 총 피해 · 기여율 · 전투 평균 DPS[/color]", 20))
	var combats: Array = r.get("dmgStats", {}).get("combats", [])
	# 필터 줄
	var frow := PUi.hbox(8)
	for pair in FILTERS:
		var id := String(pair[0])
		var on: bool = _filter == id
		var btn := PUi.button(("● " if on else "") + String(pair[1]), func(): _set_filter(id), not on, 13)
		btn.custom_minimum_size = Vector2(0, PLayout.button_min_height())
		frow.add_child(btn)
	frow.add_child(PUi.spacer())
	frow.add_child(PUi.button("DPS·유효 피해 도움말", func(): _help_open = not _help_open; refresh(), true, 12))
	top.add_child(frow)
	if combats.is_empty():
		body.add_child(PUi.rich("[color=#9ea8b8]아직 기록된 전투가 없습니다.[/color]", 14))
		_back_button()
		return
	if _help_open:
		body.add_child(_help_card())
	match _filter:
		"recent":
			var last: Dictionary = combats[combats.size() - 1]
			body.add_child(_table_card(PStats.aggregate(r, func(rec): return rec == last), _combat_label(last), r))
		"boss":
			var seen := {}
			var any := false
			for rec in combats:
				if String(rec.get("kind", "")) != "boss":
					continue
				var bid := String(rec.get("bossId", rec.get("boss", "")))
				if seen.has(bid):
					continue
				seen[bid] = true
				any = true
				var bname := String(PCatalog.boss_def(bid).get("name", bid)) if bid != "" else "보스"
				body.add_child(_table_card(PStats.aggregate(r, func(x): return String(x.get("kind", "")) == "boss" and String(x.get("bossId", x.get("boss", ""))) == bid), "보스전 · " + bname, r))
			if not any:
				body.add_child(PUi.rich("[color=#9ea8b8]보스전 기록이 없습니다.[/color]", 14))
		_:
			body.add_child(_table_card(PStats.aggregate(r), "런 전체", r))
	body.add_child(_survival_card(r))
	_back_button()

func _set_filter(id: String) -> void:
	_filter = id
	_open_owner = ""
	refresh()

func _combat_label(rec: Dictionary) -> String:
	var kind := String(rec.get("kind", ""))
	if kind == "boss":
		var bid := String(rec.get("bossId", rec.get("boss", "")))
		return "최근 전투 · 보스전 %s" % String(PCatalog.boss_def(bid).get("name", bid))
	var rid := String(rec.get("regionId", ""))
	var rname := String(PRun.region(rid).get("name", rid)) if rid != "" else "출격"
	return "최근 전투 · %s %d일차" % [rname, int(rec.get("day", 0))]

func _back_button() -> void:
	var back := PUi.button("거점으로 (Esc)", func(): main.go_base(), true, 14)
	bottom.add_child(back)
	default_button = back

## 기본 표 한 장: 기술(owner)마다 아이콘 + 총 피해 + 기여율 + 전투 평균 DPS. 행을 누르면 파생 내역이 펼쳐진다
func _table_card(a: Dictionary, title: String, r: Dictionary) -> Control:
	var c := PUi.card("")
	var box: VBoxContainer = c.box
	if int(a.n) == 0:
		box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]기록 없음[/color]" % PGlossaryTip.esc(title), 15))
		return c.panel
	box.add_child(PUi.rich("[b]%s[/b] [color=#9ea8b8]전투 %d회 · 실제 전투 %s초 · 총 유효 피해 %s · 전체 DPS %s[/color]" % [PGlossaryTip.esc(title), int(a.n), str(a.elapsed), str(a.total), str(a.dpsAll)], 15))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	for hd in ["", "기술", "총 피해", "기여율", "전투 평균 DPS"]:
		var hl := PUi.rich("[color=#9ea8b8]%s[/color]" % String(hd), 12)
		hl.custom_minimum_size = Vector2(84, 0)
		grid.add_child(hl)
	var groups := PStats.by_owner(a)
	var total: float = float(a.total)
	for gr in groups:
		var owner := String(gr.owner)
		grid.add_child(PUi.icon_of(_owner_icon(owner), 30.0, "", "", 0.0, 0))
		var nm := _owner_name(owner)
		var btn := PUi.button(("▼ " if _open_owner == owner else "▶ ") + nm, func(): _toggle(owner), true, 12)
		btn.custom_minimum_size = Vector2(140, PLayout.button_min_height())
		grid.add_child(btn)
		grid.add_child(PUi.rich("[b]%s[/b]" % str(gr.amount), 13))
		grid.add_child(PUi.rich("%s%%" % str(round(float(gr.amount) / maxf(0.01, total) * 1000.0) / 10.0), 13))
		grid.add_child(PUi.rich("[b]%s[/b]" % str(gr.dps), 13))
	box.add_child(grid)
	if _open_owner != "":
		box.add_child(_detail_rows(a, _open_owner))
	return c.panel

func _toggle(owner: String) -> void:
	_open_owner = "" if _open_owner == owner else owner
	refresh()

## 펼친 행: 직접 / 지속 / 개조·공용 파생 각각의 유효 피해와 DPS 분모(보유 시간)
func _detail_rows(a: Dictionary, owner: String) -> Control:
	var c := PUi.card("%s [color=#9ea8b8]파생 내역[/color]" % PGlossaryTip.esc(_owner_name(owner)), PUi.CARD_ON, 13)
	var box: VBoxContainer = c.box
	var denom := 0.0
	var n := 0
	for row in a.rows:
		if String(row.get("owner", "")) != owner:
			continue
		n += 1
		denom = maxf(denom, float(row.active))
		var cat := String(PStats.CATS.get(String(row.cat), row.cat))
		var kindtxt := "직접" if String(row.key) == owner else cat
		box.add_child(PUi.rich("[color=#9ea8b8]%s[/color]  %s — 유효 피해 [b]%s[/b] · 비중 %s%% · DPS %s" % [kindtxt, PGlossaryTip.esc(String(row.name)), str(row.amount), str(row.share), str(row.dps)], 12))
	if n == 0:
		box.add_child(PUi.rich("[color=#6a7078]내역 없음[/color]", 12))
	box.add_child(PUi.rich("[color=#9ea8b8]DPS 분모(이 기술을 보유한 실제 전투 시간): [b]%s초[/b][/color]" % PUi.fmt(denom), 12))
	# 개조별 이번 회차 발동·적중 기록은 전투 상태에만 있으므로 여기서는 표시하지 않는다(전투 중 빌드 상세에서 본다)
	box.add_child(PUi.rich("[color=#6a7078]개조별 발동·적중 횟수는 전투 중 빌드 상세(Tab)에서 볼 수 있습니다. 저장 기록에는 출처별 피해만 남습니다.[/color]", 11))
	return c.panel

## 보호막 흡수·회복·체력 손실은 피해 표와 섞지 않는다
func _survival_card(r: Dictionary) -> Control:
	var c := PUi.card("받은 피해 · 보호막 · 회복 [color=#9ea8b8]피해 표와 분리[/color]", PUi.CARD_OFF, 14)
	var box: VBoxContainer = c.box
	var taken := 0.0
	var nominal := 0.0
	for rec in r.get("dmgStats", {}).get("combats", []):
		taken += float(rec.get("taken", 0.0))
		nominal += float(rec.get("takenNominal", rec.get("taken", 0.0)))
	var absorbed: float = maxf(0.0, nominal - taken)
	PUi.kv(box, "체력 손실(유효)", "[b]%s[/b]" % PUi.fmt(taken), 13)
	PUi.kv(box, "보호막이 흡수", "[b]%s[/b] [color=#9ea8b8](명목 %s − 유효 %s)[/color]" % [PUi.fmt(absorbed), PUi.fmt(nominal), PUi.fmt(taken)], 13)
	PUi.kv(box, "회복", "[color=#9ea8b8]거점 휴식·사건으로 회복한 체력은 전투 기록에 남지 않습니다(현재 체력 %d)[/color]" % int(float(r.hp)), 13)
	box.add_child(PUi.rich("[color=#9ea8b8]감속장의 감속·방어·회복은 피해가 아니므로 피해 표에 없습니다(감속장이 Q에 있든 E에 있든 같습니다).[/color]", 11))
	return c.panel

func _help_card() -> Control:
	var c := PUi.card("도움말 — 이 표를 읽는 법", PUi.CARD_ON, 14)
	var box: VBoxContainer = c.box
	box.add_child(PUi.rich("[b]유효 피해[/b] = 실제로 줄어든 적 체력. 남은 체력보다 큰 피해(과잉 피해)는 세지 않습니다.", 12))
	box.add_child(PUi.rich("[b]전투 평균 DPS[/b] = 그 기술의 유효 피해 ÷ [b]그 기술을 보유한 실제 전투 시간[/b]. 아직 얻지 않았던 시간은 분모에 넣지 않고, 기술을 잃은 뒤 남아 있던 지속 효과의 피해는 같은 분모에 포함합니다.", 12))
	box.add_child(PUi.rich("[color=#9ea8b8]그래서 나중에 얻은 기술은 분모가 짧아 DPS가 높게 보일 수 있고, 기술마다 분모가 달라 각 DPS를 더해도 전체 DPS가 되지 않습니다. 기여율(총 피해 비중)과 함께 읽으세요.[/color]", 12))
	box.add_child(PUi.rich("[color=#9ea8b8]사거리·범위가 다른 기술은 전투 거리에 따라 값이 크게 달라집니다. 이 표만으로 기술의 강약을 결론짓지 마세요.[/color]", 12))
	return c.panel

# ---------- 출처 키 → 아이콘·이름 ----------
func _owner_icon(owner: String) -> String:
	if owner.begins_with("weapon:"):
		return PIcons.weapon_key(owner.substr(7))
	if owner == "skill:q":
		return "skill:slowfield"
	if owner.begins_with("skill:"):
		return PIcons.e_key(owner.substr(6))
	if owner.begins_with("common:"):
		return "common:" + owner.substr(7)
	return ""

func _owner_name(owner: String) -> String:
	if owner == "other" or owner == "":
		return "기타(출처 미상)"
	var c := PStats.classify(owner)
	return String(c.get("name", owner))
