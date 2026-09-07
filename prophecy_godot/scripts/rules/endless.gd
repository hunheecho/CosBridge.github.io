class_name PEndless
extends RefCounted
## 무한 모드(계획서 prophecy-act-themes-plan §10, godot-0.6.0 단계 4 — 방향은 사용자 결정, 수치는 시험값 data/meta.json endless).
## 본편(10일·3막) 마지막 관문 승리 → 완주 기록·영구 보상 확정 뒤 "현재 빌드로 계속". 날짜를 11·12일로 늘리지 않고
## run.endless = { segment, fights, wins, bossesWon, regroupLeft, over, reason, rows[] } 구간 상태로 구분한다(mode는 그대로, phase = endless | endless_boss | endless_over).
## 구간 = 일반 전투 fights_per_segment + 구간 보스 1. 구간마다 적 체력 +enemy_hp_step, 보스 체력 +boss_hp_step(선형, 복리 아님),
## 등급 비율은 tier_by_segment(하위 등급 퇴장 원칙: 마지막 항목이 그 뒤 모든 구간). 첫 구간은 본편 3차 세계 그대로(완성 빌드를 즐길 여유).
## 패배(일반·보스·시간 초과)는 무한 종료 — 재도전 없음, 본편 완주(run.mainCleared)·보스 기록·영구 보상은 취소되지 않는다. 저장 후 이어 하기 가능.
## 영구 기록: 구간 보스 승리마다 "본편 대응 예산(하루 첫 승리 기록 + 관문 최초 승리 기록) × reward_ratio"를 1회(이벤트 ID run:<seed>:endless:<segment>).
## 잡몹마다 1/10을 주지 않는다. 회차 내 경험치·금화는 줄이지 않는다(본편 규칙 그대로). 도전(challenges)은 무한에서 달성 처리하지 않는다.

static func D() -> Dictionary: return PCatalog.meta_endless()

static func state(run: Dictionary) -> Dictionary:
	var e = run.get("endless", null)
	return e if (e != null and typeof(e) == TYPE_DICTIONARY) else {}

## 무한 진행 중(전투 선택 또는 구간 보스 대기)
static func active(run: Dictionary) -> bool:
	return not state(run).is_empty() and (String(run.phase) == "endless" or String(run.phase) == "endless_boss")

static func is_over(run: Dictionary) -> bool:
	return String(run.phase) == "endless_over"

static func segment(run: Dictionary) -> int:
	return int(state(run).get("segment", 1))

static func fights_per_segment() -> int:
	return int(D().get("fights_per_segment", 3))

## 본편 완주 상태에서만, 1회만. 검증 빠른 회차(quick)·시험실 회차는 제외
static func can_start(run: Dictionary) -> bool:
	return String(run.phase) == "cleared" and state(run).is_empty() and not bool(run.get("quick", false)) and not bool(run.get("lab", false)) and not places(run).is_empty()

static func start(run: Dictionary) -> bool:
	if not can_start(run):
		push_error("무한 모드 시작 불가(본편 완주 상태가 아니거나 이미 시작)")
		return false
	run.mainCleared = true # 본편 완주는 여기서 확정된 상태(boss_victory가 phase=cleared로 만든 뒤). 무한에서 죽어도 되돌리지 않는다
	run.endless = { "segment": 1, "fights": 0, "wins": 0, "bossesWon": 0, "regroupLeft": int(D().get("regroup_per_segment", 1)), "over": false, "reason": "", "rows": [], "startedDay": int(run.day), "startLevel": int(run.growth.level) }
	run.phase = "endless"
	run.ended = false
	run.pendingSortie = null
	run.bossEntry = null
	run.hp = float(PRun.build(run).hp_max)
	PRun.add_log(run, "무한 모드 시작: 현재 빌드로 계속 (1구간, 전투 %d + 보스)" % fights_per_segment())
	return true

## 무한의 장소 후보: 경로 테마 3개의 장소 전부(1막→3막 순). 경로가 없는 회차(옛 지역 일정)는 기존 지역 5곳
static func places(run: Dictionary) -> Array:
	var out := []
	for tid in run.get("route", []):
		var t := PCatalog.theme(String(tid))
		for p in t.get("places", []):
			out.append(String(p.id))
	if out.is_empty():
		for rid in ["forest", "ridge", "marsh", "den", "deep"]:
			if not PCatalog.region(rid).is_empty():
				out.append(rid)
	return out

## 구간 배율(선형·시험값)
static func enemy_hp_mult(run: Dictionary) -> float:
	return 1.0 + float(D().get("enemy_hp_step", 0.1)) * float(segment(run) - 1)

static func boss_hp_mult(run: Dictionary) -> float:
	return 1.0 + float(D().get("boss_hp_step", 0.15)) * float(segment(run) - 1)

## 등급 비율: tier_by_segment[min(seg-1, last)]. 비어 있으면 본편 세계 단계 그대로
static func tier_mix(run: Dictionary) -> Dictionary:
	var T: Array = D().get("tier_by_segment", [])
	if T.is_empty():
		return PRun.world_stage_def(run).get("mix", { "normal": 1.0 }).duplicate()
	var i: int = mini(segment(run) - 1, T.size() - 1)
	return (T[i] as Dictionary).duplicate()

static func _fight_rng(run: Dictionary, seg: int, fight: int) -> PRng:
	return PRng.new((int(run.seed) * (311 + seg) + fight * 13 + 5) & 0xFFFFFFFF)

## 다음 전투 미리보기(결정적: 시드·구간·전투 번호). { regionId, name, formationId, formationName, hpMult, tier }
static func next_fight(run: Dictionary) -> Dictionary:
	var E := state(run)
	if E.is_empty():
		return {}
	var seg := int(E.segment)
	var f := int(E.fights)
	var rng := _fight_rng(run, seg, f)
	var pl := places(run)
	var rid := String(pl[rng.int_range(0, pl.size() - 1)])
	var opts := PRun.formation_options(rid, 9, false) # 옛 지역은 후반(9일차) 편성 키, 테마 장소는 일반 템플릿 전부
	var fm: Dictionary = opts[rng.int_range(0, opts.size() - 1)]
	return { "regionId": rid, "name": String(PCatalog.region(rid).name), "formationId": String(fm.id), "formationName": String(fm.name), "hpMult": enemy_hp_mult(run), "tier": tier_mix(run), "segment": seg, "fight": f + 1, "perSegment": fights_per_segment() }

## 전투 시작: 출격 dict(일반 출격과 같은 모양 + endless 표시). 시간 칸은 쓰지 않는다
static func start_fight(run: Dictionary) -> Dictionary:
	if String(run.phase) != "endless":
		push_error("무한 전투 상태가 아님")
		return {}
	var nf := next_fight(run)
	if nf.is_empty():
		return {}
	var E := state(run)
	run.sortieCount = int(run.sortieCount) + 1
	run.visited[nf.regionId] = int(run.visited.get(nf.regionId, 0)) + 1
	return { "regionId": String(nf.regionId), "deep": false, "loot": { "gold": 0, "mats": {}, "chestGold": 0 }, "encounters": 0,
		"seed": int(run.seed) * 173 + int(E.segment) * 29 + int(E.fights) * 7 + 1009, "day": int(run.day), "slot": 0, "variant": null,
		"formationId": String(nf.formationId), "endless": true, "segment": int(E.segment), "fight": int(E.fights) + 1 }

## 승리 정산(귀환) 뒤: 전투 수 증가, 구간 전투를 채우면 보스 대기
static func after_fight(run: Dictionary, sortie: Dictionary) -> void:
	var E := state(run)
	if E.is_empty() or not bool(sortie.get("endless", false)) or String(run.phase) != "endless":
		return
	E.fights = int(E.fights) + 1
	E.wins = int(E.wins) + 1
	if int(E.fights) >= fights_per_segment():
		run.phase = "endless_boss"
		PRun.add_log(run, "무한 %d구간 전투 완료: 구간 보스 대기" % int(E.segment))

static func can_regroup(run: Dictionary) -> bool:
	return String(run.phase) == "endless" and int(state(run).get("regroupLeft", 0)) > 0 and float(run.hp) < float(PRun.build(run).hp_max)

## 재정비: 구간당 regroup_per_segment회, 체력 완전 회복(시간 없음)
static func regroup(run: Dictionary) -> bool:
	if not can_regroup(run):
		return false
	var E := state(run)
	E.regroupLeft = int(E.regroupLeft) - 1
	run.hp = float(PRun.build(run).hp_max)
	PRun.add_log(run, "재정비: 체력 회복 (남은 %d회)" % int(E.regroupLeft))
	return true

## 구간 보스: 경로 보스 계획을 구간 순서로 순환(1구간 = 1막 보스 …)
static func boss_id(run: Dictionary) -> String:
	var plan: Array = run.get("bossPlan", [])
	if plan.is_empty():
		for b in PRun.mode_def(run).bosses:
			plan.append(String(b.id))
	if plan.is_empty():
		return "boss"
	return String(plan[(segment(run) - 1) % plan.size()])

static func boss_seed(run: Dictionary) -> int:
	return int(run.seed) * 997 + 7 + (100 + segment(run)) * 31

static func can_start_boss(run: Dictionary) -> bool:
	return String(run.phase) == "endless_boss"

## 입장: 체력 완전 회복(관문과 같은 규칙). 재도전 스냅샷은 없다(패배 = 종료)
static func start_boss(run: Dictionary) -> Dictionary:
	if not can_start_boss(run):
		push_error("무한 구간 보스 상태가 아님")
		return {}
	run.hp = float(PRun.build(run).hp_max)
	run.bossEntry = null
	return { "regionId": "boss", "bossId": boss_id(run), "stage": PRun.stage_count(run) + segment(run) - 1, "seed": boss_seed(run), "loot": { "gold": 0, "mats": {} }, "encounters": 0, "endless": true, "segment": segment(run) }

## 구간 보스 승리(정확히 1회, PFlow.settle_boss_victory에서): 기록 행 → 다음 구간(전투 0, 재정비 회복, 체력 완전)
static func boss_victory(run: Dictionary, stats: Dictionary) -> Dictionary:
	var E := state(run)
	var seg := int(E.segment)
	var bid := boss_id(run)
	var rec := { "bossId": bid, "segment": seg, "time": round(float(stats.get("elapsed", 0.0)) * 10.0) / 10.0, "level": int(run.growth.level),
		"bossDamage": round(float(stats.get("boss_damage", 0.0))), "bossHpMult": boss_hp_mult(run), "endless": true, "seed": int(run.seed) }
	(E.rows as Array).append(rec)
	E.bossesWon = int(E.bossesWon) + 1
	E.segment = seg + 1
	E.fights = 0
	E.regroupLeft = int(D().get("regroup_per_segment", 1))
	run.phase = "endless"
	run.bossEntry = null
	run.hp = float(PRun.build(run).hp_max)
	PRun.add_log(run, "무한 %d구간 보스 %s 처치 (%s초) → %d구간" % [seg, String(PCatalog.boss_def(bid).name), str(rec.time), seg + 1])
	return rec

## 종료(패배·보스 패배·시간 초과·자발적 마침): 본편 완주 기록은 그대로
static func over(run: Dictionary, reason: String) -> void:
	var E := state(run)
	if E.is_empty():
		return
	E.over = true
	E.reason = reason
	run.phase = "endless_over"
	run.ended = true
	run.pendingSortie = null
	run.bossEntry = null
	PRun.add_log(run, "무한 모드 종료(%s): %d구간 도달 · 전투 승 %d · 구간 보스 %d" % [reason_name(reason), int(E.segment), int(E.wins), int(E.bossesWon)])

static func reason_name(reason: String) -> String:
	match reason:
		"lost": return "전투 패배"
		"boss_lost": return "구간 보스 패배"
		"timeout": return "시간 초과"
		"quit": return "마침"
	return reason

## 결과 화면·봇 보고용 요약
static func summary(run: Dictionary) -> Dictionary:
	var E := state(run)
	if E.is_empty():
		return {}
	return { "segment": int(E.segment), "fights": int(E.fights), "wins": int(E.wins), "bossesWon": int(E.bossesWon), "over": bool(E.get("over", false)), "reason": String(E.get("reason", "")),
		"rows": (E.rows as Array).duplicate(true), "startLevel": int(E.get("startLevel", 0)), "level": int(run.growth.level) }

## 구간 보스 승리 1회의 영구 기록량: 본편 대응 예산 × 비율(잡몹마다가 아니라 구간 단위)
static func segment_records(run: Dictionary) -> float:
	var R := PCatalog.meta_records_for(String(run.get("mode", "trio")))
	return float(D().get("reward_ratio", 0.1)) * (float(R.day_win) + float(R.boss_first))
