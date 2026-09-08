class_name PTerrain
extends RefCounted
## 랜덤 지형(사용자 요구 7 "랜덤 맵/지형 가능성"). 전장을 새로 만들지 않는다.
## **검증된 전장 뼈대(data/themes.json·data/config.json의 arenas)는 그대로 두고**, 그 위에
## 장애물 후보 자리를 좌우 대칭 쌍으로 추첨해 더한다. 추첨 결과가 아래 조건을 하나라도
## 어기면 유한 횟수(TRIES)만큼 다시 뽑고, 그래도 안 되면 **뼈대 그대로**(fallback)로 떨어진다.
##
## 지키는 조건(전부 check()가 수치로 확인한다)
##  1. 장애물 개수 상한/하한, 점유 면적 비율 상한/하한
##  2. 통로 폭: 어떤 두 장애물 사이·장애물과 벽 사이 틈이 pass_w(플레이어 지름 28px보다 넉넉) 이상
##  3. 시작 지점·적 등장 지점의 여유 공간(시작 위치가 장애물 안이면 실패)
##  4. 고립 없음: 플레이어가 닿을 수 있는 자유 공간이 전체 자유 공간의 iso_ratio 이상
##     (봉인·제단·출구는 PObjectives가 유효 위치에만 놓으므로, 자유 공간이 하나로 이어져 있으면 전부 도달 가능하다)
##  5. 적 등장 지점 8곳·출구 후보 4곳이 시작 지점과 이어져 있다(적 접근 경로·목표 도달)
##
## 난수: **st.rng를 쓰지 않는다.** 전투 난수 소비 순서를 바꾸면 기준 전투가 깨지므로
## 지형 전용 PRng를 따로 만든다(seed는 전투 시드에서 결정론적으로 파생 → 같은 시드 재현).
##
## 적용 제외: 승인된 기준 전투(first_fight), 보스 전장(지금 배치 유지), opts.obstacles 직접 지정.
## 기본은 꺼짐이다. opts.terrain_random=true 또는 환경 변수 PROPHECY_TERRAIN=1로 켠다.
##
## 파괴되는 지형(보스 '엄폐물 파괴')은 장애물을 **없애기만** 하므로 이어짐을 깨지 않는다.
## 정예 '균열 채굴자'의 돌무더기는 st.obstacles가 아니라 구조물(적)이고 플레이어 이동을 막지 않으며,
## 스스로 탈출로 검사(minExits)를 한다. 다만 놓을 자리가 있어야 하므로 자유 공간 비율을 함께 잰다.

const MASK := 0xFFFFFFFF
const GRID := 8.0        # 이어짐·통로 폭 검사 격자(px). 값이 작을수록 정밀하고 느리다
const PLAYER_R := 14.0   # data/config.json PLAYER.r
const ENEMY_R := 22.0    # 보스를 뺀 가장 큰 적 반지름(wolf_alpha·제단)
const RUBBLE_R := 18.0   # 균열 채굴자가 남기는 돌무더기 반지름(자유 공간 여유 계산용)

## 상한·하한(전부 **시험값**, 사람이 승인한 균형값이 아니다).
## 근거: 기존 전장 14+3곳 실측 — 개수 2~6, 면적 0.00~5.10%, 두 장애물 틈 최소 52.0, 벽 틈 최소 66.0, 시작 여유 최소 110.0
const LIMITS := {
	"count_min": 3,        # 추첨 결과의 장애물 개수 하한
	"count_max": 10,       # 상한
	"area_min": 0.012,     # 점유 면적 / 전장 면적 하한(1.2%)
	"area_max": 0.080,     # 상한(8.0%). 기존 최대 5.10%(mine_tunnel)보다 넉넉하게
	"pass_w": 44.0,        # 통로 폭 하한(px). 플레이어 지름 28 + 여유 16
	"pass_grid": 36.0,     # 격자로 잰 통로 폭 하한(격자 해상도만큼 보수적으로 나온다)
	"wall_gap": 40.0,      # 장애물과 전장 벽 사이 최소 틈
	"start_clear": 70.0,   # 시작 지점에서 장애물 표면까지 최소 거리
	"entry_clear": 46.0,   # 적 등장 지점에서 새 장애물 표면까지(적 반지름 22 + 2 + 여유)
	"goal_clear": 46.0,    # 출구 후보 4곳에서 새 장애물 표면까지
	"boss_clear": 80.0,    # 보스 등장 지점에서(보스 전장은 애초에 제외하지만 안전용)
	"iso_ratio": 0.995,    # 시작 지점에서 닿는 자유 칸 / 전체 자유 칸
	"extra_min": 1,        # 뼈대에 더할 장애물 수(목표) 하한
	"extra_max": 4,        # 상한
	"tries": 12,           # 재추첨 상한(무한 루프 금지)
}
const RADII := [24.0, 28.0, 32.0, 36.0]
## 좌우 대칭 쌍으로 뽑는 후보 자리(x는 왼쪽 절반만 적는다. 480은 중앙 = 자기 자신이 짝)
const SLOT_X := [140.0, 240.0, 340.0, 480.0]
const SLOT_Y := [130.0, 220.0, 300.0, 380.0, 470.0]
const JITTER := 14.0

## 환경 변수 스위치(기본 꺼짐). 규칙·난수 기본 경로를 바꾸지 않기 위해 opts로도 켤 수 있다
static var env_on := OS.get_environment("PROPHECY_TERRAIN") == "1"

static func enabled(o: Dictionary) -> bool:
	return bool(o.get("terrain_random", env_on))

# ---------- 시드 ----------
static func mix_seed(a: int, b: int) -> int:
	var x: int = (a ^ ((b * 0x2545F491) & MASK)) & MASK
	x = (x ^ (x >> 16)) & MASK
	x = (x * 0x2545F491) & MASK
	x = (x ^ (x >> 15)) & MASK
	return x if x != 0 else 1

## 전투 시드 + 전장 이름에서 지형 시드를 결정론적으로 만든다(같은 시드 → 같은 배치)
static func seed_for(seed_value: int, arena_id: String) -> int:
	return mix_seed(seed_value & MASK, arena_id.hash() & MASK)

# ---------- 전장 정보 ----------
## KD-3: data/themes.json은 시작 위치 키가 player, data/config.json은 playerStart였다.
## 둘 다 읽어 준다(정본은 playerStart). 없으면 전장 중앙.
static func arena_start(arena_def: Dictionary, w: float, h: float) -> Dictionary:
	if arena_def.has("playerStart"):
		return { "x": float(arena_def.playerStart.x), "y": float(arena_def.playerStart.y) }
	if arena_def.has("player"):
		return { "x": float(arena_def.player.x), "y": float(arena_def.player.y) }
	return { "x": w / 2.0, "y": h / 2.0 }

static func arena_boss_start(arena_def: Dictionary, w: float) -> Dictionary:
	if arena_def.has("bossStart"):
		return { "x": float(arena_def.bossStart.x), "y": float(arena_def.bossStart.y) }
	return { "x": w / 2.0, "y": 120.0 }

## 적 등장 지점(data/world.json density.entry_points). [[x, y], ...]
static func entry_points() -> Array:
	var out := []
	for q in PCatalog.density().get("entry_points", []):
		out.append([float(q[0]), float(q[1])])
	return out

## 출구·목표가 놓이는 가장자리 후보(PObjectives.edge_exit와 같은 4곳)
static func exit_points(w: float, h: float) -> Array:
	return [[60.0, h / 2.0], [w - 60.0, h / 2.0], [w / 2.0, 60.0], [w / 2.0, h - 60.0]]

static func copy_obstacles(list: Array) -> Array:
	var out := []
	for ob in list:
		var d := { "id": String(ob.id), "type": String(ob.type), "x": float(ob.x), "y": float(ob.y), "r": float(ob.r) }
		if ob.has("canopy") and float(ob.canopy) > 0.0:
			d["canopy"] = float(ob.canopy)
		out.append(d)
	return out

# ---------- 생성 ----------
## 반환 = 배치 결과(저장·재현용). obstacles가 실제로 쓸 목록이다.
## { arena, seed, tries, fallback, obstacles[], added[], check{} }
static func generate(arena_id: String, w: float, h: float, base: Array, start: Dictionary, seed_value: int, boss_start: Dictionary = {}) -> Dictionary:
	var tseed := seed_for(seed_value, arena_id)
	var entries := entry_points()
	var exits := exit_points(w, h)
	var bs: Dictionary = boss_start if not boss_start.is_empty() else { "x": w / 2.0, "y": 120.0 }
	var base_obs := copy_obstacles(base)
	var last_check := {}
	for attempt in int(LIMITS.tries):
		var rng := PRng.new(mix_seed(tseed, attempt + 1))
		var obs := base_obs.duplicate(true)
		var added := _draw(rng, w, h, obs, start, entries, exits, bs)
		for a in added:
			obs.append(a)
		var ck := check(w, h, obs, start, entries, exits)
		last_check = ck
		if bool(ck.ok):
			return { "arena": arena_id, "seed": tseed, "tries": attempt + 1, "fallback": false,
				"obstacles": obs, "added": added, "check": ck }
	# 유한 횟수 뒤에도 못 만들면 검증된 뼈대 그대로 쓴다(무한 루프 금지)
	var ck0 := check(w, h, base_obs, start, entries, exits)
	return { "arena": arena_id, "seed": tseed, "tries": int(LIMITS.tries), "fallback": true,
		"obstacles": base_obs, "added": [], "check": ck0, "last_fail": last_check.get("reasons", []) }

## 저장된 배치를 그대로 되살린다(같은 시드 재현과 별개로, 기록해 둔 결과를 그대로 쓰는 길)
static func restore(layout: Dictionary) -> Array:
	return copy_obstacles(layout.get("obstacles", []))

## 후보 자리를 섞어 좌우 대칭 쌍으로 넣어 본다. 하나라도 어기면 그 자리는 건너뛴다
static func _draw(rng: PRng, w: float, h: float, obs: Array, start: Dictionary, entries: Array, exits: Array, bs: Dictionary) -> Array:
	var slots := []
	for sx in SLOT_X:
		for sy in SLOT_Y:
			slots.append([float(sx), float(sy)])
	# Fisher-Yates(지형 전용 난수)
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.int_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	# 더할 장애물 수 목표. 뼈대가 하한에 못 미치면(예: 장애물 없는 forest) 채울 만큼 올린다.
	# 대칭 쌍은 한 번에 2개가 들어가므로 목표를 1 넘길 수 있다(개수 상한은 아래에서 따로 막는다).
	var want := rng.int_range(int(LIMITS.extra_min), int(LIMITS.extra_max))
	want = maxi(want, int(LIMITS.count_min) - obs.size())
	want = mini(want, int(LIMITS.count_max) - obs.size())
	var added := []
	var area := _area(obs)
	var area_cap: float = float(LIMITS.area_max) * w * h
	var n := 0
	for s in slots:
		if added.size() >= want:
			break
		var r: float = float(RADII[rng.int_range(0, RADII.size() - 1)])
		var is_tree := rng.next() < 0.35
		var jx := rng.range_f(-JITTER, JITTER)
		var jy := rng.range_f(-JITTER, JITTER)
		var x: float = float(s[0]) + jx
		var y: float = float(s[1]) + jy
		var pair := [_mk(n, x, y, r, is_tree)]
		if absf(x - w / 2.0) > 1.0:
			pair.append(_mk(n + 1, w - x, y, r, is_tree))
		if obs.size() + added.size() + pair.size() > int(LIMITS.count_max):
			continue
		if area + float(pair.size()) * PI * r * r > area_cap:
			continue
		var ok := true
		for c in pair:
			if not _fits(c, w, h, obs, added, pair, start, entries, exits, bs):
				ok = false
				break
		if not ok:
			continue
		for c in pair:
			added.append(c)
			area += PI * r * r
		n += pair.size()
	return added

static func _mk(n: int, x: float, y: float, r: float, is_tree: bool) -> Dictionary:
	var d := { "id": "g%d" % (n + 1), "type": ("tree" if is_tree else "rock"), "x": x, "y": y, "r": r }
	if is_tree:
		d["canopy"] = snappedf(r * 2.4, 1.0)
	return d

## 후보 하나가 모든 여유·통로 조건을 만족하는가(격자 검사 전 값싼 선별)
static func _fits(c: Dictionary, w: float, h: float, obs: Array, added: Array, pair: Array, start: Dictionary, entries: Array, exits: Array, bs: Dictionary) -> bool:
	var r: float = float(c.r)
	var gap: float = float(LIMITS.wall_gap)
	if float(c.x) - r < gap or float(c.x) + r > w - gap or float(c.y) - r < gap or float(c.y) + r > h - gap:
		return false
	if PGeom.dist(float(c.x), float(c.y), float(start.x), float(start.y)) < r + float(LIMITS.start_clear):
		return false
	if PGeom.dist(float(c.x), float(c.y), float(bs.x), float(bs.y)) < r + float(LIMITS.boss_clear):
		return false
	for e in entries:
		if PGeom.dist(float(c.x), float(c.y), float(e[0]), float(e[1])) < r + float(LIMITS.entry_clear):
			return false
	for g in exits:
		if PGeom.dist(float(c.x), float(c.y), float(g[0]), float(g[1])) < r + float(LIMITS.goal_clear):
			return false
	var pw: float = float(LIMITS.pass_w)
	for o in obs:
		if PGeom.dist(float(c.x), float(c.y), float(o.x), float(o.y)) - r - float(o.r) < pw:
			return false
	for o in added:
		if PGeom.dist(float(c.x), float(c.y), float(o.x), float(o.y)) - r - float(o.r) < pw:
			return false
	for o in pair:
		if o == c:
			continue
		if PGeom.dist(float(c.x), float(c.y), float(o.x), float(o.y)) - r - float(o.r) < pw:
			return false
	return true

static func _area(obs: Array) -> float:
	var a := 0.0
	for o in obs:
		a += PI * float(o.r) * float(o.r)
	return a

# ---------- 검사 ----------
## 배치 하나를 수치로 검사한다. 생성기·테스트·보고서가 같은 함수를 쓴다.
## 반환: { ok, reasons[], count, area_ratio, pair_gap, wall_gap, start_clear, iso_ratio,
##         pass_grid, entry_min, exit_min, free22 }
static func check(w: float, h: float, obs: Array, start: Dictionary, entries: Array, exits: Array) -> Dictionary:
	var why := []
	var cnt := obs.size()
	var ratio := _area(obs) / (w * h)
	# 1) 개수·면적
	if cnt < int(LIMITS.count_min) or cnt > int(LIMITS.count_max):
		why.append("개수 %d(허용 %d~%d)" % [cnt, int(LIMITS.count_min), int(LIMITS.count_max)])
	if ratio < float(LIMITS.area_min) or ratio > float(LIMITS.area_max):
		why.append("면적 %.2f%%(허용 %.1f~%.1f%%)" % [ratio * 100.0, float(LIMITS.area_min) * 100.0, float(LIMITS.area_max) * 100.0])
	# 2) 통로 폭(정확값): 장애물끼리·장애물과 벽
	var pair_gap := INF
	var wall_gap := INF
	for i in obs.size():
		var a: Dictionary = obs[i]
		wall_gap = minf(wall_gap, minf(minf(float(a.x) - float(a.r), float(a.y) - float(a.r)), minf(w - float(a.x) - float(a.r), h - float(a.y) - float(a.r))))
		for j in range(i + 1, obs.size()):
			var b: Dictionary = obs[j]
			pair_gap = minf(pair_gap, PGeom.dist(float(a.x), float(a.y), float(b.x), float(b.y)) - float(a.r) - float(b.r))
	if obs.is_empty():
		pair_gap = w
		wall_gap = w
	if pair_gap < float(LIMITS.pass_w):
		why.append("두 장애물 틈 %.1f < %.1f" % [pair_gap, float(LIMITS.pass_w)])
	if wall_gap < float(LIMITS.wall_gap):
		why.append("벽 틈 %.1f < %.1f" % [wall_gap, float(LIMITS.wall_gap)])
	# 3) 시작 지점 여유
	var sc := INF
	for o in obs:
		sc = minf(sc, PGeom.dist(float(start.x), float(start.y), float(o.x), float(o.y)) - float(o.r))
	if obs.is_empty():
		sc = w
	if sc < float(LIMITS.start_clear):
		why.append("시작 여유 %.1f < %.1f" % [sc, float(LIMITS.start_clear)])
	# 4~5) 격자 검사: 고립·통로 폭·등장 지점·출구 도달
	var g := _grid(w, h, obs)
	var fl := _flood(g, PLAYER_R, float(start.x), float(start.y))
	var iso := 1.0
	if int(fl.free) > 0:
		iso = float(fl.count) / float(fl.free)
	else:
		why.append("시작 지점 주변에 설 자리가 없다")
	if iso < float(LIMITS.iso_ratio):
		why.append("고립: 닿는 자유 칸 %.1f%%" % [iso * 100.0])
	var entry_min := 999.0
	var exit_min := 999.0
	var mark: PackedByteArray = fl.mark
	for e in entries:
		if not _reach(g, mark, ENEMY_R, float(e[0]), float(e[1]), 70.0):
			why.append("적 등장 지점 (%d,%d)이 이어지지 않는다" % [int(e[0]), int(e[1])])
			entry_min = 0.0
	for gp in exits:
		if not _reach(g, mark, PLAYER_R, float(gp[0]), float(gp[1]), 90.0):
			why.append("출구 후보 (%d,%d)이 이어지지 않는다" % [int(gp[0]), int(gp[1])])
			exit_min = 0.0
	# 격자로 잰 통로 폭: 시작 지점에서 등장·출구 지점까지 모두 이어지는 최대 팽창 반지름 × 2
	var pass_grid := _passage(g, start, entries, exits) * 2.0
	if pass_grid < float(LIMITS.pass_grid):
		why.append("격자 통로 폭 %.0f < %.0f" % [pass_grid, float(LIMITS.pass_grid)])
	# 돌무더기(r18)를 놓을 자리가 남아 있는가(정예 균열 채굴자). 통과 조건이 아니라 기록값
	var free22 := _free_ratio(g, RUBBLE_R + 4.0)
	return { "ok": why.is_empty(), "reasons": why, "count": cnt, "area_ratio": ratio,
		"pair_gap": pair_gap, "wall_gap": wall_gap, "start_clear": sc, "iso_ratio": iso,
		"pass_grid": pass_grid, "entry_min": entry_min, "exit_min": exit_min, "free22": free22 }

# ---------- 격자 도우미 ----------
## 칸마다 '가장 가까운 장애물 표면까지 거리'와 '벽까지 거리'를 미리 재 둔다.
## 자유(반지름 r) 판정은 CombatState.valid_pos와 같은 식이다: 벽 여유 ≥ r, 장애물 표면 ≥ r + 2
static func _grid(w: float, h: float, obs: Array) -> Dictionary:
	var cols := int(floor(w / GRID))
	var rows := int(floor(h / GRID))
	var clr := PackedFloat32Array()
	clr.resize(cols * rows)
	var wal := PackedFloat32Array()
	wal.resize(cols * rows)
	for j in rows:
		var cy := (float(j) + 0.5) * GRID
		for i in cols:
			var cx := (float(i) + 0.5) * GRID
			var m := 1e9
			for o in obs:
				var d: float = PGeom.dist(cx, cy, float(o.x), float(o.y)) - float(o.r)
				if d < m:
					m = d
			clr[j * cols + i] = m
			wal[j * cols + i] = minf(minf(cx, cy), minf(w - cx, h - cy))
	return { "cols": cols, "rows": rows, "clear": clr, "wall": wal }

static func _free(g: Dictionary, k: int, r: float) -> bool:
	var clr: PackedFloat32Array = g.clear
	var wal: PackedFloat32Array = g.wall
	return wal[k] >= r and clr[k] >= r + 2.0

## (x, y)에 가장 가까운 자유 칸(없으면 -1). max_px 안에서만 찾는다
static func _near_cell(g: Dictionary, r: float, x: float, y: float, max_px: float) -> int:
	var cols: int = g.cols
	var rows: int = g.rows
	var ci := clampi(int(x / GRID), 0, cols - 1)
	var cj := clampi(int(y / GRID), 0, rows - 1)
	var span := int(ceil(max_px / GRID))
	var best := -1
	var bd := INF
	for dj in range(-span, span + 1):
		for di in range(-span, span + 1):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= cols or j >= rows:
				continue
			var k := j * cols + i
			if not _free(g, k, r):
				continue
			var d := PGeom.dist(x, y, (float(i) + 0.5) * GRID, (float(j) + 0.5) * GRID)
			if d <= max_px and d < bd:
				bd = d
				best = k
	return best

## 시작 지점에서 닿는 칸을 표시한다. { mark(1=닿음), count(닿은 칸), free(전체 자유 칸) }
static func _flood(g: Dictionary, r: float, sx: float, sy: float) -> Dictionary:
	var cols: int = g.cols
	var rows: int = g.rows
	var clr: PackedFloat32Array = g.clear
	var wal: PackedFloat32Array = g.wall
	var need := r + 2.0
	var mark := PackedByteArray()
	mark.resize(cols * rows)
	var free_n := 0
	for k in cols * rows:
		if wal[k] >= r and clr[k] >= need:
			free_n += 1
	var s := _near_cell(g, r, sx, sy, 60.0)
	if s < 0:
		return { "mark": mark, "count": 0, "free": free_n }
	var stack := [s]
	mark[s] = 1
	var n := 0
	while not stack.is_empty():
		var k: int = stack.pop_back()
		n += 1
		var i: int = k % cols
		var j: int = k / cols
		if i > 0 and mark[k - 1] == 0 and wal[k - 1] >= r and clr[k - 1] >= need:
			mark[k - 1] = 1
			stack.append(k - 1)
		if i < cols - 1 and mark[k + 1] == 0 and wal[k + 1] >= r and clr[k + 1] >= need:
			mark[k + 1] = 1
			stack.append(k + 1)
		if j > 0 and mark[k - cols] == 0 and wal[k - cols] >= r and clr[k - cols] >= need:
			mark[k - cols] = 1
			stack.append(k - cols)
		if j < rows - 1 and mark[k + cols] == 0 and wal[k + cols] >= r and clr[k + cols] >= need:
			mark[k + cols] = 1
			stack.append(k + cols)
	return { "mark": mark, "count": n, "free": free_n }

## (x, y) 근처(max_px)에 '닿은 것으로 표시된' 자유 칸이 있는가
static func _reach(g: Dictionary, mark: PackedByteArray, r: float, x: float, y: float, max_px: float) -> bool:
	var cols: int = g.cols
	var rows: int = g.rows
	var ci := clampi(int(x / GRID), 0, cols - 1)
	var cj := clampi(int(y / GRID), 0, rows - 1)
	var span := int(ceil(max_px / GRID))
	for dj in range(-span, span + 1):
		for di in range(-span, span + 1):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= cols or j >= rows:
				continue
			var k := j * cols + i
			if mark[k] == 1 and _free(g, k, r) and PGeom.dist(x, y, (float(i) + 0.5) * GRID, (float(j) + 0.5) * GRID) <= max_px:
				return true
	return false

## 시작 지점에서 등장 지점·출구 후보가 전부 이어지는 최대 팽창 반지름(이분 탐색).
## 반지름 r로 부풀린 자유 공간이 이어진다 = 그 경로의 통로 폭이 2r 이상이다
static func _passage(g: Dictionary, start: Dictionary, entries: Array, exits: Array) -> float:
	var lo := PLAYER_R
	var hi := 60.0
	if not _connected(g, lo, start, entries, exits):
		return 0.0
	for i in 6:
		var mid := (lo + hi) / 2.0
		if _connected(g, mid, start, entries, exits):
			lo = mid
		else:
			hi = mid
	return lo

static func _connected(g: Dictionary, r: float, start: Dictionary, entries: Array, exits: Array) -> bool:
	var fl := _flood(g, r, float(start.x), float(start.y))
	if int(fl.count) == 0:
		return false
	var mark: PackedByteArray = fl.mark
	for e in entries:
		if not _reach(g, mark, r, float(e[0]), float(e[1]), 90.0):
			return false
	for gp in exits:
		if not _reach(g, mark, r, float(gp[0]), float(gp[1]), 110.0):
			return false
	return true

## 반지름 r로 설 수 있는 칸의 비율(돌무더기·목표를 놓을 여지)
static func _free_ratio(g: Dictionary, r: float) -> float:
	var cols: int = g.cols
	var rows: int = g.rows
	var n := 0
	for k in cols * rows:
		if _free(g, k, r):
			n += 1
	return float(n) / float(maxi(1, cols * rows))

## 어떤 점이 시작 지점에서 걸어 닿는가(목표 도달 검사용 공개 함수)
static func reachable(w: float, h: float, obs: Array, start: Dictionary, x: float, y: float, r: float = PLAYER_R, max_px: float = 40.0) -> bool:
	var g := _grid(w, h, obs)
	var fl := _flood(g, r, float(start.x), float(start.y))
	return _reach(g, fl.mark, r, x, y, max_px)

## 여러 점을 한 번에 검사한다(격자를 한 번만 만든다). points = [{x, y}] 또는 [[x, y]]
static func reachable_all(w: float, h: float, obs: Array, start: Dictionary, points: Array, r: float = PLAYER_R, max_px: float = 40.0) -> Array:
	var g := _grid(w, h, obs)
	var fl := _flood(g, r, float(start.x), float(start.y))
	var out := []
	for p in points:
		var px: float = float(p[0]) if typeof(p) == TYPE_ARRAY else float(p.x)
		var py: float = float(p[1]) if typeof(p) == TYPE_ARRAY else float(p.y)
		out.append(_reach(g, fl.mark, r, px, py, max_px))
	return out

# ---------- 파괴 가능한 전투 장애물 / 파괴할 수 없는 외곽 경계 ----------
## 사용자 확정 사항: 보스가 지형을 부술 수 있게 하되 **부술 수 있는 것과 없는 것을 데이터로 나눈다.**
## 규칙은 data/boss_behavior.json의 terrain 절이 정본이고 여기에는 숫자를 두지 않는다.
## 항목이 없으면 모든 장애물이 "boundary"(= 아무도 못 부순다) → 개편 전과 같다.
## 실제로 지우는 곳은 CombatState.break_obstacle 한 곳뿐이다(그림만 지우는 길이 없다).
static func break_rules() -> Dictionary:
	return PBoss.behavior().get("terrain", {})

## 장애물 하나의 구실. "cover" = 파괴 가능한 전투 장애물 / "boundary" = 파괴할 수 없는 외곽 경계
static func role_of(w: float, h: float, ob: Dictionary) -> String:
	var R := break_rules()
	if R.is_empty():
		return "boundary"
	if (R.get("boundaryIds", []) as Array).has(String(ob.get("id", ""))):
		return "boundary"
	if not (R.get("breakTypes", []) as Array).has(String(ob.get("type", ""))):
		return "boundary"
	# 전장 벽에 붙어 경계선을 이루는 장애물은 부수면 경계에 구멍이 난다 → 외곽 경계로 본다
	var m := float(R.get("edgeMargin", 0.0))
	var x := float(ob.x)
	var y := float(ob.y)
	var r := float(ob.r)
	if x - r <= m or y - r <= m or x + r >= w - m or y + r >= h - m:
		return "boundary"
	return "cover"

## 이 종류로 부술 수 있는가(보스별 types 제한까지 본다. types가 비면 규칙의 breakTypes 그대로)
static func breakable(w: float, h: float, ob: Dictionary, types: Array = []) -> bool:
	if role_of(w, h, ob) != "cover":
		return false
	if types.is_empty():
		return true
	return types.has(String(ob.get("type", "")))

# ---------- 파괴 판정 모양(보스마다 다르다) ----------
## 아래 다섯 개가 보스 9종의 파괴 판정을 만든다. 전부 "장애물 목록에서 고르기"만 하고 아무것도 지우지 않는다.
## 고른 결과를 실제로 지우는 것은 CombatState.break_obstacle이다.

## 원 안(착지 충격·표식 폭발·포자 착탄). 표면이 원에 닿으면 고른다
static func pick_circle(w: float, h: float, obs: Array, x: float, y: float, rad: float, types: Array = []) -> Array:
	var out: Array = []
	for i in obs.size():
		var ob: Dictionary = obs[i]
		if not breakable(w, h, ob, types):
			continue
		if PGeom.dist(x, y, float(ob.x), float(ob.y)) <= rad + float(ob.r):
			out.append(i)
	return out

## 선분 위(굴착 관통·얼음길·돌파 경로). pad = 선의 두께 절반
static func pick_segment(w: float, h: float, obs: Array, x0: float, y0: float, x1: float, y1: float, pad: float, types: Array = []) -> Array:
	var out: Array = []
	for i in obs.size():
		var ob: Dictionary = obs[i]
		if not breakable(w, h, ob, types):
			continue
		if PGeom.seg_circle(x0, y0, x1, y1, float(ob.x), float(ob.y), float(ob.r) + pad):
			out.append(i)
	return out

## 부채꼴 안(발톱 휩쓸기). 중심이 부채꼴 안이거나 표면이 닿으면 고른다
static func pick_arc(w: float, h: float, obs: Array, x: float, y: float, ang: float, rad: float, half: float, types: Array = []) -> Array:
	var out: Array = []
	for i in obs.size():
		var ob: Dictionary = obs[i]
		if not breakable(w, h, ob, types):
			continue
		if PGeom.in_arc(x, y, rad, ang, half, float(ob.x), float(ob.y), float(ob.r)):
			out.append(i)
	return out

## 세로 절단선 위(집행관). 전장 높이 전체를 지나는 폭 width의 띠
static func pick_column(w: float, h: float, obs: Array, cx: float, width: float, types: Array = []) -> Array:
	var out: Array = []
	for i in obs.size():
		var ob: Dictionary = obs[i]
		if not breakable(w, h, ob, types):
			continue
		if absf(float(ob.x) - cx) <= width / 2.0 + float(ob.r):
			out.append(i)
	return out

## 두 점을 잇는 선을 막는 장애물의 번호(가장 먼저 걸리는 것). 없으면 -1.
## pad = 그 보스 공격의 반폭(예: 충격파 폭 70이면 35). 가는 시선은 트였는데 두꺼운 공격만 장애물에 먹히는
## 경우를 같은 함수로 잡는다 — 사람이 겪은 "돌 뒤에 서 있으면 한 대도 안 맞는다"가 바로 이 경우였다.
static func blocking_index(obs: Array, ax: float, ay: float, bx: float, by: float, pad: float = 0.0) -> int:
	var best := -1
	var bt := INF
	for i in obs.size():
		var ob: Dictionary = obs[i]
		var tt := PGeom.seg_circle_t(ax, ay, bx, by, float(ob.x), float(ob.y), float(ob.r) + pad)
		if tt >= 0.0 and tt < bt:
			bt = tt
			best = i
	return best

## 시작 지점에서 걸어 닿는 자유 칸 수(파괴 전후 이동 가능 영역 비교용).
## 장애물을 지우기만 하므로 이 값은 줄어들 수 없다 — 줄어들면 파편이 새 장애물이 됐다는 뜻이고 시험이 잡는다.
static func reach_cells(w: float, h: float, obs: Array, start: Dictionary, r: float = PLAYER_R) -> int:
	var g := _grid(w, h, obs)
	var fl := _flood(g, r, float(start.x), float(start.y))
	return int(fl.count)

## 부분 실행(PSubset)으로 만든 보고서는 파일 이름에 _PARTIAL을 붙인다.
## 전체 실행 결과 파일을 부분 결과가 덮어써서 나중에 전체 측정처럼 읽히는 일을 막는다
static func report_path(base: String, partial: bool) -> String:
	if not partial:
		return base
	var dot := base.rfind(".")
	return (base + "_PARTIAL") if dot < 0 else (base.substr(0, dot) + "_PARTIAL" + base.substr(dot))

## 보고서·문서용 한 줄 요약
static func limits_text() -> String:
	return "개수 %d~%d · 면적 %.1f~%.1f%% · 통로 폭 ≥%.0f(격자 ≥%.0f) · 벽 틈 ≥%.0f · 시작 여유 ≥%.0f · 등장 지점 여유 ≥%.0f · 이어짐 ≥%.1f%% · 재추첨 ≤%d회" % [
		int(LIMITS.count_min), int(LIMITS.count_max), float(LIMITS.area_min) * 100.0, float(LIMITS.area_max) * 100.0,
		float(LIMITS.pass_w), float(LIMITS.pass_grid), float(LIMITS.wall_gap), float(LIMITS.start_clear),
		float(LIMITS.entry_clear), float(LIMITS.iso_ratio) * 100.0, int(LIMITS.tries)]
