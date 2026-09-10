extends SceneTree
## **기준 전투(D33)의 발자국을 단계마다 찍는다.** 규칙을 바꾸지 않는다 — 읽기만 한다.
##
## 왜 있는가 — 사용자 지시(2026-09-10):
##   "D33은 냉기 공급원이 없는 기준 전투다. 이번 출처 교정으로 지문이 달라지면
##    '파쇄가 줄어서'라고 설명하거나 기대값을 갱신하지 말고,
##    **최초로 달라진 피해·상태·난수 사용 지점을 추적**하라."
##
## 그래서 '몇 대 몇으로 이겼다' 같은 요약이 아니라 **단계별 원자료**를 남긴다.
## 두 판본에서 각각 돌려 파일을 diff 하면 **처음 갈라지는 줄**이 그대로 나온다.
##
## 한 줄에 담는 것(그 단계가 끝난 뒤의 상태):
##   n      단계 번호(1/120초)
##   rng    난수 내부 상태 — **난수를 몇 번, 어떤 순서로 썼는지**가 여기 그대로 드러난다
##   php    사람 체력           ppos 사람 좌표
##   ehp    살아 있는 적 체력 합   en 살아 있는 적 수
##   kill   누적 처치 수                      taken 사람이 받은 누적 피해
##   burst  연계 발동 수(파쇄·감전 후속·까마귀·숙주 …)를 이름순으로 이어 붙인 것
##   ls     흡혈 누적 회복량
##
## 실행:
##   godot --headless --path prophecy_godot -s tools/d33_trace.gd
##   PROPHECY_TRACE_OUT=<파일>  로 저장 자리를 바꿀 수 있다(기본 user://d33_trace.txt)
##   PROPHECY_TRACE_SEED=<정수> 로 시드를 바꿀 수 있다(기본 1)
##   PROPHECY_TRACE_STEPS=<정수> 최대 단계(기본 7200 = 60초)

const STEP := 1.0 / 120.0

func cfg() -> Dictionary:
	return preload("res://scripts/game/game.gd").load_config()

## 연계 발동 수를 이름순으로 한 줄에 담는다. 사전 순서에 흔들리지 않게 정렬한다
func bursts_of(st: CombatState) -> String:
	# 연계 발동은 stagger_stats.bursts 에 쌓인다(note_link_burst → _stagger_note("bursts", …))
	var ss = st.get("stagger_stats")
	if typeof(ss) != TYPE_DICTIONARY:
		return "-"
	var d = (ss as Dictionary).get("bursts", null)
	if typeof(d) != TYPE_DICTIONARY:
		return "-"
	var keys: Array = (d as Dictionary).keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [String(k), str(d[k])])
	return ",".join(parts) if not parts.is_empty() else "-"

func _init() -> void:
	var seed_v := 1
	var env_seed := OS.get_environment("PROPHECY_TRACE_SEED")
	if env_seed != "":
		seed_v = int(env_seed)
	var max_steps := 7200
	var env_steps := OS.get_environment("PROPHECY_TRACE_STEPS")
	if env_steps != "":
		max_steps = int(env_steps)
	var out_path := OS.get_environment("PROPHECY_TRACE_OUT")
	if out_path == "":
		out_path = "user://d33_trace.txt"

	var st := CombatState.first_fight(cfg(), seed_v)
	var lines: Array = []
	lines.append("# 기준 전투(D33) 발자국 · 시드 %d · 단계 1/120초" % seed_v)
	lines.append("# n rng php ppos ehp en kill taken burst ls")

	var n := 0
	# 시작 상태는 "running" 이다. 끝났는지는 "won"/"lost"/"timeout" 으로 판단한다
	while n < max_steps and (st.status == "" or st.status == "running"):
		st.step({}, STEP)
		n += 1
		var ehp := 0.0
		var en := 0
		for e in st.enemies:
			if not bool(e.get("dead", false)):
				ehp += float(e.get("hp", 0.0))
				en += 1
		var rng_state := -1
		var r = st.get("rng")
		if r != null:
			rng_state = int(r._a)
		var stats: Dictionary = st.stats if typeof(st.get("stats")) == TYPE_DICTIONARY else {}
		lines.append("%d %d %.4f %.3f,%.3f %.4f %d %d %.4f %s %.4f" % [
			n, rng_state, float(st.player.hp), float(st.player.x), float(st.player.y),
			ehp, en,
			int(stats.get("kills", 0)),
			float(stats.get("damage_taken", 0.0)),
			bursts_of(st),
			float(stats.get("lifesteal", 0.0))])

	lines.append("# 끝: 단계 %d · 상태 %s" % [n, String(st.status)])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("발자국 파일을 열지 못했다: " + out_path)
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("D33 발자국 %d줄 → %s" % [lines.size(), ProjectSettings.globalize_path(out_path)])
	print("마지막 상태: %s · 단계 %d" % [String(st.status), n])
	quit(0)
