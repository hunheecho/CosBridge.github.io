extends SceneTree
## 장애물 충돌·접촉 탈출 규칙(화면 없음): godot --headless --path prophecy_godot -s tests/collision_tests.gd
##
## 규칙(플레이어와 적에 **같은 규칙**을 쓴다):
##  - 장애물 안으로 파고드는 이동은 막힌다.
##  - 이미 닿아(또는 겹쳐) 있는 장애물에서 멀어지거나 접선 방향으로 가는 이동은 막지 않는다.
##  - 다른 장애물은 이 예외와 무관하게 따로 판정한다(장애물 사이로 파고들지 못한다).
## 2026-09-08 이전에는 접점에서 어느 방향이든 막혀 그 자리에 영원히 갇혔다.

const STEP := 1.0 / 120.0
var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func mk() -> CombatState:
	return CombatState.first_fight(preload("res://scripts/game/game.gd").load_config(), 1)

## 장애물을 직접 지정한 상태(다른 적·규칙은 건드리지 않는다)
func mk_obs(obs: Array) -> CombatState:
	var st := mk()
	st.obstacles = obs
	return st

## o를 장애물 ob의 표면에 정확히 붙인다(push_out이 만드는 상태와 같다)
func park(st: CombatState, o: Dictionary, ob: Dictionary, ang: float) -> void:
	var d: float = float(ob.r) + float(o.r)
	o.x = float(ob.x) + cos(ang) * d
	o.y = float(ob.y) + sin(ang) * d

## 한 단계만큼 밀어 보고 실제 이동 거리를 돌려준다
func nudge(st: CombatState, o: Dictionary, dx: float, dy: float) -> float:
	var x0: float = o.x
	var y0: float = o.y
	st.move_swept(o, dx, dy, true)
	return PGeom.dist(x0, y0, float(o.x), float(o.y))

func _init() -> void:
	var ROCK := { "id": "r1", "type": "rock", "x": 480.0, "y": 300.0, "r": 42.0 }
	var ROCK2 := { "id": "r2", "type": "rock", "x": 480.0, "y": 300.0 + 42.0 * 2.0 + 28.0, "r": 42.0 }

	# ---------- 1. 접점에서의 세 방향 ----------
	for who in ["player", "enemy"]:
		var st := mk_obs([ROCK.duplicate()])
		var o: Dictionary = st.player
		if who == "enemy":
			o = st.spawn_enemy("wolf", 900.0, 300.0)
		park(st, o, ROCK, 0.0)   # 바위 오른쪽 표면에 접촉(플레이어는 바위 기준 +x 방향)
		var away := nudge(st, o, 6.0, 0.0)
		park(st, o, ROCK, 0.0)
		var tang := nudge(st, o, 0.0, 6.0)
		park(st, o, ROCK, 0.0)
		var into := nudge(st, o, -6.0, 0.0)
		ok("%s: 접점에서 멀어지는 이동은 막히지 않는다" % who, away > 5.9, "이동 %.2f" % away)
		ok("%s: 접점에서 접선 이동은 막히지 않는다" % who, tang > 5.9, "이동 %.2f" % tang)
		ok("%s: 접점에서 장애물 안으로 파고드는 이동은 막힌다" % who, into < 0.01, "이동 %.4f" % into)

	# ---------- 2. 겹친 상태에서 빠져나온다 ----------
	var st2 := mk_obs([ROCK.duplicate()])
	st2.player.x = ROCK.x + 10.0     # 바위 안쪽 깊이(비정상 상태) — 밖으로 나올 수 있어야 한다
	st2.player.y = ROCK.y
	var out_move := nudge(st2, st2.player, 8.0, 0.0)
	ok("겹친 상태에서 바깥 방향 이동이 가능하다", out_move > 7.9, "이동 %.2f" % out_move)

	# ---------- 3. 장애물 두 개 사이: 한쪽에서 멀어져도 다른 쪽은 막는다 ----------
	var st3 := mk_obs([ROCK.duplicate(), ROCK2.duplicate()])
	var gap_y: float = (float(ROCK.y) + float(ROCK2.y)) * 0.5
	st3.player.x = ROCK.x
	st3.player.y = gap_y             # 두 바위 사이 틈 한가운데
	var into2 := nudge(st3, st3.player, 0.0, -20.0)   # 위쪽 바위로 파고들기
	ok("두 장애물 사이: 다른 장애물 안으로 파고들지 못한다", into2 < 14.1, "이동 %.2f (틈 절반 14.0)" % into2)
	var st3b := mk_obs([ROCK.duplicate(), ROCK2.duplicate()])
	park(st3b, st3b.player, ROCK, PI / 2.0)           # 위쪽 바위 아래 표면에 접촉
	var side := nudge(st3b, st3b.player, 9.0, 0.0)
	ok("두 장애물 사이: 접촉한 채 옆으로 빠져나갈 수 있다", side > 8.9, "이동 %.2f" % side)

	# ---------- 4. 회피(대시)도 같은 규칙 ----------
	var st4 := mk_obs([ROCK.duplicate()])
	park(st4, st4.player, ROCK, 0.0)
	var before: float = st4.player.x
	for i in 60:
		st4.step({ "mx": 1.0, "my": 0.0, "dodge_press": i == 0, "dodge_held": i < 30 }, STEP)
	ok("회피: 바위에 붙은 상태에서 바깥으로 회피할 수 있다", st4.player.x > before + 30.0,
		"x %.1f → %.1f" % [before, st4.player.x])

	# ---------- 5. 접점에서 굳지 않는다(전 방향 확인) ----------
	var st5 := mk_obs([ROCK.duplicate()])
	var free_dirs := 0
	for k in 16:
		var a := TAU * float(k) / 16.0
		park(st5, st5.player, ROCK, 0.0)
		if nudge(st5, st5.player, cos(a) * 6.0, sin(a) * 6.0) > 0.01:
			free_dirs += 1
	ok("접점에서 16방향 중 안쪽(막혀야 하는 쪽)을 뺀 나머지로 움직일 수 있다", free_dirs >= 9,
		"움직인 방향 %d/16" % free_dirs)

	# ---------- 6. 수정 전 동작(legacy)에서는 갇힌다 — 회귀 증거 ----------
	CombatState.collision_legacy = true
	var st6 := mk_obs([ROCK.duplicate()])
	var stuck := 0
	for k in 16:
		var a2 := TAU * float(k) / 16.0
		park(st6, st6.player, ROCK, 0.0)
		if nudge(st6, st6.player, cos(a2) * 6.0, sin(a2) * 6.0) < 0.01:
			stuck += 1
	CombatState.collision_legacy = false
	ok("PROPHECY_COLLISION_LEGACY 동작에서는 접점에서 모든 방향이 막힌다(수정 전 재현)", stuck == 16,
		"막힌 방향 %d/16" % stuck)

	# ---------- 7. 기본값은 수정 후 동작 ----------
	ok("기본값은 수정 후 동작(환경 변수 없이 legacy가 아니다)", not CombatState.collision_legacy)

	var pass_n := results.filter(func(r): return r[0]).size()
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)
