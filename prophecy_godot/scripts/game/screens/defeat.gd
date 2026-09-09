class_name PDefeatScreen
extends PScreen
## 일반 출격 패배(HTML defeat): 잃은 전리품과 다음 시작 시점(PRun.defeat 결과). 거점으로.
##
## 사망 안내 문구는 static으로 뽑아 두었다(death_lines·next_label). 화면과 시험이 **같은 문자열**을 보게 하려는 것이다 —
## 예전에는 결과와 상관없이 "구조되어 정상 체력으로 시작합니다"라고만 적어, 회차가 끝났는데도 계속할 수 있는 것처럼 보였다.

## 지금 회차 상태가 가리키는 "다시 서는 자리"(관문 날이면 관문, 아니면 그 날 아침)
static func spot_text(r: Dictionary) -> String:
	if String(r.get("phase", "")) == "boss_prep":
		return "%d일차 보스 관문" % int(r.get("day", 1))
	return "%d일차 %s" % [int(r.get("day", 1)), String(PRun.time_slots()[0])]

## 사망 결과 안내(2026-09-09 사용자 확정). 회차 상태만 보고 만들므로 시험이 화면을 띄우지 않고 그대로 확인한다.
## 세 갈래가 서로 **다른 문구**다: 회차 종료 / 마지막 날 부활(같은 날 관문 앞) / 보통 날 부활(다음 날).
static func death_lines(r: Dictionary) -> Array:
	var now := spot_text(r)
	var death: Dictionary = r.get("death", {}) if typeof(r.get("death", null)) == TYPE_DICTIONARY else {}
	if PRun.is_run_over(r):
		return [
			"[color=#ff8c73]부활 수단이 없어 이번 회차가 여기서 끝납니다.[/color] 다음 회차는 처음부터 시작합니다.",
			"[color=#9ea8b8]부활 물약을 가지고 있었다면 하루를 잃고 다음 날 최대 체력 25%로 이어갈 수 있었습니다.[/color]",
		]
	if PRun.revived_same_day(r): # 마지막 날: 다음 날이 아니라 **같은 날 관문 앞**이다
		return [
			"[b]부활 물약 1개를 썼습니다.[/b] 마지막 날이라 [b]날짜는 넘어가지 않습니다[/b] — [b]같은 %s[/b] 앞에서 [b]최대 체력의 25%%[/b]로 다시 섭니다." % now,
			"[color=#9ea8b8]대신 오늘 남은 시간은 전부 사라집니다(휴식·상점·출격 없이 관문만 남습니다). 다시 쓰러지면 부활 물약이 또 한 개 듭니다.[/color]",
			"[color=#9ea8b8]남은 부활 물약 %d개 · 이미 정산한 금화·장비와 레벨·성장은 그대로입니다.[/color]" % PConsumables.revive_count(r),
		]
	if bool(death.get("revived", false)):
		return [
			"[b]부활 물약 1개를 썼습니다.[/b] 남은 하루를 잃고 [b]%s[/b]에 [b]최대 체력의 25%%[/b]로 이어갑니다." % now,
			"[color=#9ea8b8]남은 부활 물약 %d개 · 이미 정산한 금화·장비와 레벨·성장은 그대로입니다.[/color]" % PConsumables.revive_count(r),
		]
	return ["[b]%s[/b]에 이어갑니다. 이미 정산한 금화·장비와 레벨·성장은 그대로입니다." % now]

## 주 버튼 문구(Enter). 마지막 날 부활은 "다음 날"이 아니라는 것을 버튼에서도 드러낸다
static func next_label(r: Dictionary) -> String:
	if PRun.is_run_over(r):
		return "회차 결과 보기 (Enter)"
	if PRun.revived_same_day(r):
		return "같은 날 관문 앞으로 (Enter)"
	var spot := spot_text(r)
	return "%s%s (Enter)" % [spot, PUi.josa(spot, "으로", "로")] # "보스 관문으로" / "아침으로"

func refresh() -> void:
	clear_all()
	var r := run()
	var s: Dictionary = main.sortie
	var sm: Dictionary = main.last_summary
	if r.is_empty() or s.is_empty():
		return
	var reg := PRun.region(String(s.regionId))
	var lost: Dictionary = main.lost_loot
	var lost_txt := "금화 %d" % int(lost.get("gold", 0))
	var mats := PUi.mats_text(lost.get("mats", {}))
	if mats != "":
		lost_txt += ", " + mats
	for id in lost.get("items", []):
		lost_txt += ", " + PRun.equip_name(String(id))
	heading("[color=#ff8c73]%s[/color]" % ("회차 종료" if PRun.is_run_over(r) else "패배"))
	body.add_child(PUi.rich("%s에서 쓰러졌습니다. 이번 출격의 미정산 전리품([b]%s[/b])을 잃었습니다." % [PGlossaryTip.esc(String(reg.name)), PGlossaryTip.esc(lost_txt)], 14))
	var lines := death_lines(r)
	for i in lines.size():
		body.add_child(PUi.rich(String(lines[i]), 15 if i == 0 else 13))
	body.add_child(PUi.rich("[color=#9ea8b8]처치 %d · 받은 피해 %d · %d초[/color]" % [int(sm.get("kills", 0)), int(float(sm.get("damage_taken", 0.0))), int(round(float(sm.get("elapsed", 0.0))))], 12))
	var btn := PUi.button(next_label(r), func(): main.after_defeat(), true, 16)
	body.add_child(btn)
	default_button = btn
