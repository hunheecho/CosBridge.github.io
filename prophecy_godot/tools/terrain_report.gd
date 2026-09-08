extends SceneTree
## 랜덤 지형 배치 측정(화면 없음): godot --headless --path prophecy_godot -s tools/terrain_report.gd
## 전장 × 시드마다 추첨을 돌려 개수·면적·통로 폭·시작 여유·고립·재추첨 횟수를 표로 남긴다.
## 결과: docs/TERRAIN_REPORT.md (부분 실행이면 docs/TERRAIN_REPORT_PARTIAL.md — PSubset).
##
## 부분 실행(큰 측정 전에 작게 먼저) — `tools/subset.gd`(PSubset). 축 이름은 **arena**와 **seed**다.
##   PROPHECY_QUICK=1                          축마다 대표값 하나(전장 1곳 × 시드 1개)
##   PROPHECY_ONLY="arena:clearing,mine_tunnel;seed:1,3"
##   PROPHECY_SKIP="arena:forest"   PROPHECY_LIMIT=8
## 부분 실행이면 결과를 docs/TERRAIN_REPORT_PARTIAL.md에 쓴다(전체 결과 파일을 덮어쓰지 않는다).
##
## 이 표의 값은 전부 **시험값**이며 사람이 승인한 균형값이 아니다. 봇 승패·조작감 판단도 아니다.

const W := 960.0
const H := 600.0
const OUT := "res://docs/TERRAIN_REPORT.md"
const SEEDS := [1, 2, 3, 4, 5, 6]

func _init() -> void:
	var sub := PSubset.new()
	var arenas := sub.pick("arena", (PCatalog.theme_arenas().keys() as Array) + ["clearing", "pillars", "forest"])
	var seeds := sub.pick("seed", SEEDS)
	var head := "랜덤 지형 배치 측정 — %s 전장 %d곳 × 시드 %d개." % [sub.describe("랜덤 지형"), arenas.size(), seeds.size()]
	print(head)
	var entries := PTerrain.entry_points()
	var exits := PTerrain.exit_points(W, H)
	var rows := []
	var t0 := Time.get_ticks_msec()
	for aid in arenas:
		var ad := PCatalog.arena(String(aid))
		var base: Array = ad.get("obstacles", [])
		var start := PTerrain.arena_start(ad, W, H)
		var b := PTerrain.check(W, H, PTerrain.copy_obstacles(base), start, entries, exits)
		for sd in seeds:
			if not sub.more(): # PROPHECY_LIMIT 조합 상한
				break
			var lay := PTerrain.generate(String(aid), W, H, base, start, int(sd))
			var ck: Dictionary = lay.check
			rows.append({ "arena": String(aid), "seed": int(sd), "base_n": base.size(), "base_area": float(b.area_ratio),
				"n": int(ck.count), "added": (lay.added as Array).size(), "area": float(ck.area_ratio),
				"pair": float(ck.pair_gap), "wall": float(ck.wall_gap), "start": float(ck.start_clear),
				"iso": float(ck.iso_ratio), "pass": float(ck.pass_grid), "free22": float(ck.free22),
				"tries": int(lay.tries), "fallback": bool(lay.fallback) })
			printerr("done ", aid, " ", sd)
	var ms := Time.get_ticks_msec() - t0

	var md := "# 랜덤 지형 배치 측정(생성기 검증용 — 사람 조작감·최종 밸런스 판단 아님)\n\n"
	md += "%s\n\n" % head
	md += "상한·하한(**전부 시험값**): %s\n\n" % PTerrain.limits_text()
	md += "생성: `tools/terrain_report.gd` (%s, Godot %s), %d행 · %d ms.\n" % [OS.get_name(), Engine.get_version_info().string, rows.size(), ms]
	md += "규칙: **검증된 전장 뼈대는 그대로 두고** 후보 자리를 좌우 대칭 쌍으로 추첨해 더한다. 조건을 어기면 최대 %d회 다시 뽑고, 그래도 안 되면 뼈대 그대로 쓴다(기본 배치). 승인된 기준 전투(first_fight)와 보스 전장에는 적용하지 않는다. 추첨은 지형 전용 난수를 써서 전투 난수(`st.rng`) 소비 순서를 바꾸지 않는다.\n\n" % int(PTerrain.LIMITS.tries)
	md += "열 설명: `틈` = 어떤 두 장애물 사이 최소 거리(정확값) · `통로` = 격자로 잰 통로 폭(시작 지점 ↔ 등장 지점 8곳 ↔ 출구 후보 4곳이 모두 이어지는 최대 팽창 반지름 × 2, 격자 8px만큼 보수적) · `이어짐` = 시작 지점에서 닿는 자유 칸 / 전체 자유 칸 · `여유22` = 반지름 22로 설 수 있는 칸 비율(돌무더기·목표를 놓을 여지).\n\n"
	md += "| 전장 | 시드 | 뼈대 개수 | 더한 수 | 개수 | 면적 | 틈 | 벽 틈 | 시작 여유 | 이어짐 | 통로 | 여유22 | 추첨 횟수 | 기본 배치 |\n"
	md += "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in rows:
		md += "| %s | %d | %d | %d | %d | %.2f%% | %.0f | %.0f | %.0f | %.4f | %.0f | %.2f | %d | %s |\n" % [
			r.arena, r.seed, r.base_n, r.added, r.n, r.area * 100.0, r.pair, r.wall, r.start, r.iso, r.pass, r.free22, r.tries, ("예" if r.fallback else "아니오")]
	md += "\n## 전장별 폭(시드 %d개)\n\n| 전장 | 뼈대 개수/면적 | 개수 | 면적 | 틈 최소 | 시작 여유 최소 | 이어짐 최소 | 통로 최소 | 기본 배치 |\n|---|---|---|---|---|---|---|---|---|\n" % seeds.size()
	for aid in arenas:
		var s: Array = rows.filter(func(r): return r.arena == String(aid))
		if s.is_empty():
			continue
		md += "| %s | %d / %.2f%% | %d~%d | %.2f~%.2f%% | %.0f | %.0f | %.4f | %.0f | %d/%d |\n" % [
			String(aid), int(s[0].base_n), float(s[0].base_area) * 100.0,
			_mini(s, "n"), _maxi(s, "n"), _minf(s, "area") * 100.0, _maxf(s, "area") * 100.0,
			_minf(s, "pair"), _minf(s, "start"), _minf(s, "iso"), _minf(s, "pass"),
			s.filter(func(r): return r.fallback).size(), s.size()]
	md += "\n검사 스위트: `tests/terrain_tests.gd` (`python tools/run_suites.py --suites terrain_tests --jobs 1`).\n"

	var path := PTerrain.report_path(OUT, sub.partial())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(md)
	f.close()
	print("wrote ", path)
	quit(0)

func _minf(rows: Array, key: String) -> float:
	var m := INF
	for r in rows:
		m = minf(m, float(r[key]))
	return m

func _maxf(rows: Array, key: String) -> float:
	var m := -INF
	for r in rows:
		m = maxf(m, float(r[key]))
	return m

func _mini(rows: Array, key: String) -> int:
	var m := 1 << 30
	for r in rows:
		m = mini(m, int(r[key]))
	return m

func _maxi(rows: Array, key: String) -> int:
	var m := -(1 << 30)
	for r in rows:
		m = maxi(m, int(r[key]))
	return m
