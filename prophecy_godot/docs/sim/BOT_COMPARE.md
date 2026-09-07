# 실력별 전투 봇 첫 비교(BOT_COMPARE)

생성: `tools/bot_batch.gd` (run_id `compare1`, 2026-09-07T21:04:03). **가상 조작 모델(실제 플레이어 분포 아님) · 사람 보정 미완료.** 봇 결과는 규칙·정보 경계·집계 검증용이며 사람 승률·재미·가독성 판단이 아니다. 시간초과는 시간초과로 남긴다(패배·승리로 치환하지 않음).

환경: 게임 godot-0.5.0 · 규칙 rules@godot-0.5.0/observe-1 · 봇 skillbot-0.1/skillbot-0.1 · 관측 observe-1 · 기록 형식 prophecy_replay/1 · 엔진 4.7.2-stable (official) · OS Windows/x86_64 · git HEAD fabdaa3f320eb79217da451ed026b594db5a8b4d (prophecy_godot 미커밋 변경: true) · 데이터 해시 4ad8aed56edd6a3b · 프로필 해시 d325940048e157de · 설정 해시 a586dc9c0822d16b

## 1. 구현된 프로필

프로필 값은 `data/bots.json`에서 읽어 만든 표(시험값, 사용자 승인 아님).

| 프로필 | 이름 | 판단 간격 | 새 위협 인식 지연 | 추적 갱신 지연 | 고려 위험 수 | 회피 방향 후보 | 방향 오차 | 누름 길이 |
|---|---|---|---|---|---|---|---|---|
| novice | 서툰(가상) | 150ms | 350~550ms | 150ms | 2 | 8 | ±15.0° | 기본 최대거리 시도 |
| regular | 보통(가상) | 100ms | 200~350ms | 100ms | 4 | 8 | ±8.0° | 짧음/중간/김(빠져나갈 거리로) |
| skilled | 능숙(가상) | 50ms | 120~220ms | 50ms | 8 | 16 | ±3.0° | 짧음/중간/김(빠져나갈 거리로) |
| balanced | 균형(기존 정책, 기준 행) | 5스텝(41.7ms) | 없음(react_at 0.4) | 없음 | 전부 | 도형 탈출 방향 1 | 0 | 끝까지 |

공통 규칙(모든 프로필 동일, `data/bots.json` common): Q = 200 안 3마리 이상 또는 보스 180 안 · E = 보유·200 안 2마리 이상 · 유지 거리 55 · 안전 여유 6 · 반응 문턱 = 추적 예고(warn)는 진행률 0.4 이상, 남은 초 표시 예고는 0.9초 이하일 때만 벗어남(그 전에는 접근 계속) · 예고 warn 잔여 추정 0.60초×(1−진행률), lock 잔여 0.15초 · 걸어서 벗어나기 = 빠져나갈 거리 ≤ 이동속도×추정 잔여×0.8 · 짧음 ≤ 75px, 중간 ≤ 115px · 재사용 잔여가 판단 간격×0.5 이하이면 미리 누름. 진단 성향(greedy_attack·nearest_only·long_dodge·hoard_qe)은 전부 꺼짐.

## 2. 기존 대비 동작 차이

- 기존 정책(stand/active/aggressive/balanced/survival/idle/aware/still)은 코드·동작 그대로(`bot.gd` 변경 없음). `balanced` 행은 기준 행으로만 함께 실행했다(기존 정밀 정책이지 최적·완벽 회피가 증명된 봇이 아니다).
- 새 프로필은 CombatState를 직접 읽지 않고 `PObserve` 스냅샷(화면에 그려지는 것만, 깊은 복사)만 읽는다. 기존 정책은 예고 진행률(react_at)로 반응하고 반응 지연이 없다; 새 프로필은 위협(attack_id)마다 인식 지연을 봇 seed로 표본화하고, 추적 중인 위협의 방향 변경은 추적 갱신 지연 뒤에만 안다.
- 회피는 후보 방향 중 고려한 위협 도형의 합집합을 가장 짧게 벗어나는 방향 + 판단당 1회 방향 오차. 누름 길이는 조작 타이머로만 요청하고 실제 거리는 게임 규칙(70~150·충돌·재사용 1.5초)이 정한다(게임 수치 변경 없음).
- Q/E·자동 공격·목표 접근은 모든 프로필 같은 단순 규칙이라 차이는 이동·회피에서만 난다.

## 3. 실제 검사 범위

- 시나리오: baseline_wolf25(0.3.1 D33 기준 전투(x5 늑대 25, 동시 12, 동시 돌진 2, 회피 hold 70~150/1.5초)), ranged_mix(바람 능선 3일차 기본 편성(궁수·방패병·늑대·거미, uniform_x5), 검 Lv1 고정), zone_mix(안개 습지 4일차 기본 편성(포자·서리술사·거미·궁수·늑대, uniform_x5), 검 Lv1 고정), boss_thornmane(가시갈기 × 실험실 stage1 프리셋(boss_sim make_run)), boss_guardian(봉인 수호자 × stage2 프리셋), boss_eater(예언을 먹는 자 × stage3 프리셋). 미구현(`unimplemented`) 행: 0.
- 게임 seed [1, 2, 3, 4, 5](봇 seed = 게임 seed) × 프로필 ["novice", "regular", "skilled", "balanced"]. 같은 seed의 반복 재생은 독립 표본이 아니다. 전투 상한: { "baseline_wolf25": 240.0, "ranged_mix": 240.0, "zone_mix": 240.0, "boss_thornmane": 300.0, "boss_guardian": 300.0, "boss_eater": 300.0 }초. 정체(stalled) = 처치·피해·체력 변화 없이 60초.
- 완료 96행, 상태 분포 {"lost":30,"timeout":6,"won":60}. 회귀 검사는 `tests/bot_tests.gd`(정보 경계·지연·기록 재생·검산·배치 재개).

## 4. 비용과 재현 방법

- 벽시계 합계 447.9초(전투당 평균 4.67초, 최장 시뮬 240.0초, 예산 1500초). 헤드리스 처리 속도는 실제 화면 FPS가 아니다.
- 재현: `PROPHECY_BOT_RUN_ID=compare1 godot --headless --path prophecy_godot -s tools/bot_batch.gd` (같은 run_id면 완료 행을 건너뛰고 재개; 캐시 키(git HEAD·데이터·프로필·설정·엔진·OS)가 다르면 무효화 메시지). 결과 원본: `docs/sim/bot_runs/compare1/results.jsonl`, 실패 전투·표본 성공 전투의 입력 기록: `replays/`(`PReplay.replay`로 상태 해시 대조). OS 간 일치는 이번에 검증하지 않았다.

## 5. 관찰 결과

### 5-1. 일반 전투(검 Lv1 고정)

| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 받은 피해 평균 | 피격 수 | 남은 체력 평균(승) | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 최대 동시 적/예고/투사체/장판 | 피해 출처(유효 합) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 5 | 5 | 0 | 0 | 0 | 0 | 5/5 = 100% [57%, 100%] | 18.3 / 20.2 (N<10: p90 불안정) | - | 67.2 | 28 | 32.8 | 8.0 (136.0) | 8 | 0 | 8/0 | 12/6/0/0 | wolf:bite 324, wolf:dash 12 |
| baseline_wolf25 | regular | 5 | 5 | 0 | 0 | 0 | 0 | 5/5 = 100% [57%, 100%] | 17.8 / 18.9 (N<10: p90 불안정) | - | 16.8 | 7 | 83.2 | 7.8 (70.0) | 0 | 0 | 7/0 | 12/6/0/0 | wolf:bite 72, wolf:dash 12 |
| baseline_wolf25 | skilled | 5 | 5 | 0 | 0 | 0 | 0 | 5/5 = 100% [57%, 100%] | 20.9 / 22.1 (N<10: p90 불안정) | - | 4.8 | 2 | 95.2 | 9.8 (67.9) | 3 | 0 | 10/0 | 12/5/0/0 | wolf:dash 12, wolf:bite 12 |
| baseline_wolf25 | balanced | 5 | 3 | 2 | 0 | 0 | 0 | 3/5 = 60% [23%, 88%] | 19.4 / 19.4 (N<10: p90 불안정) | 13.8 | 73.6 | 32 | 44.0 | 4.6 (71.5) | 5 | 217 | 8/0 | 12/6/0/0 | wolf:bite 256, wolf:dash 112 |
| ranged_mix | novice | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 46.6 | 100.0 | 46 | - | 25.8 (123.9) | 39 | 0 | 18/0 | 12/8/3/3 | bash 158, wolf:bite 156, bite 89, arrow 85, wolf:dash 12 |
| ranged_mix | regular | 5 | 1 | 4 | 0 | 0 | 0 | 1/5 = 20% [4%, 62%] | 151.1 / 151.1 (N<10: p90 불안정) | 82.9 | 97.8 | 44 | 11.0 | 63.4 (69.5) | 27 | 0 | 29/0 | 12/9/3/3 | bash 214, arrow 134, wolf:bite 60, bite 45, wolf:dash 36 |
| ranged_mix | skilled | 5 | 2 | 1 | 2 | 0 | 0 | 2/5 = 40% [12%, 77%] | 161.2 / 161.2 (N<10: p90 불안정) | 231.6 | 51.4 | 22 | 65.5 | 126.0 (67.5) | 85 | 0 | 44/0 | 12/9/3/3 | bash 140, arrow 63, wolf:bite 24, bite 18, wolf:dash 12 |
| ranged_mix | balanced | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 43.7 | 100.0 | 43 | - | 36.4 (107.2) | 59 | 2113 | 21/0 | 12/9/3/3 | bash 215, wolf:bite 108, arrow 99, wolf:dash 60, bite 18 |
| zone_mix | novice | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 60.3 | 100.0 | 60 | - | 37.6 (129.7) | 56 | 0 | 26/0 | 12/15/3/14 | bite 149, zone 131, wolf:bite 120, arrow 64, frostzone 24, wolf:dash 12 |
| zone_mix | regular | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 166.1 | 100.0 | 57 | - | 66.4 (71.0) | 30 | 0 | 53/0 | 12/12/3/14 | frostzone 195, zone 111, arrow 83, bite 63, wolf:bite 36, wolf:dash 12 |
| zone_mix | skilled | 5 | 1 | 1 | 3 | 0 | 0 | 1/5 = 20% [4%, 62%] | 220.9 / 220.9 (N<10: p90 불안정) | 97.1 | 53.4 | 27 | 67.0 | 72.4 (74.1) | 37 | 0 | 69/0 | 12/14/3/15 | frostzone 104, arrow 70, bite 63, zone 18, wolf:bite 12 |
| zone_mix | balanced | 5 | 2 | 2 | 1 | 0 | 0 | 2/5 = 40% [12%, 77%] | 208.8 / 208.8 (N<10: p90 불안정) | 50.1 | 79.2 | 40 | 41.0 | 53.0 (106.6) | 95 | 1959 | 47/0 | 12/13/3/14 | frostzone 120, wolf:bite 72, bite 63, arrow 60, zone 45, wolf:dash 36 |

### 5-2. 보스(실험실 프리셋 빌드)

| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 보스 남은 체력 평균 | 받은 피해 평균 | 피격 수 | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 피해 출처(유효 합) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| boss_thornmane | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 33.2 / 33.2 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 2.0 (148.0) | 2 | 0 | 9/6 | - |
| boss_thornmane | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.1 / 31.1 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 1.7 (88.5) | 0 | 0 | 8/5 | - |
| boss_thornmane | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 33.1 / 33.1 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 2.7 (115.4) | 0 | 0 | 9/6 | - |
| boss_thornmane | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.3 / 32.3 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 2.7 (122.3) | 2 | 39 | 8/4 | - |
| boss_guardian | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.2 / 30.2 (N<10: p90 불안정) | - | 0 | 6.7 | 2 | 4.7 (140.0) | 4 | 0 | 8/0 | zone 20 |
| boss_guardian | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.0 / 31.0 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 4.3 (67.2) | 2 | 0 | 8/0 | - |
| boss_guardian | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 29.6 / 29.6 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 5.7 (71.5) | 2 | 0 | 7/0 | - |
| boss_guardian | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 29.6 / 29.6 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 4.7 (129.3) | 5 | 63 | 6/0 | - |
| boss_eater | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.8 / 30.8 (N<10: p90 불안정) | - | 0 | 33.3 | 5 | 3.7 (146.5) | 4 | 0 | 6/0 | boss_wide 72, boss_mark 28 |
| boss_eater | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 33.3 / 33.3 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 4.7 (70.0) | 0 | 0 | 7/1 | - |
| boss_eater | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 33.5 / 33.5 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 5.3 (77.9) | 2 | 0 | 7/3 | - |
| boss_eater | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 35.5 / 35.5 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 5.3 (103.0) | 6 | 96 | 7/3 | - |

### 5-3. seed별 짝(성공·실패가 바뀐 짝 보존)

| 시나리오 | 게임 seed | novice | regular | skilled | balanced |
|---|---|---|---|---|---|
| baseline_wolf25 | 1 | won 20.2s hp28 | won 15.5s hp76 | won 22.1s hp100 | won 21.5s hp40 |
| baseline_wolf25 | 2 | won 18.3s hp40 | won 18.9s hp88 | won 20.9s hp88 | won 19.4s hp52 |
| baseline_wolf25 | 3 | won 20.7s hp40 | won 17.8s hp76 | won 19.2s hp100 | lost 15.4s hp0 |
| baseline_wolf25 | 4 | won 17.0s hp16 | won 17.7s hp88 | won 22.6s hp100 | won 18.8s hp40 |
| baseline_wolf25 | 5 | won 17.8s hp40 | won 22.4s hp88 | won 19.1s hp88 | lost 13.8s hp0 |
| ranged_mix | 1 | lost 46.6s hp0 | lost 151.0s hp0 | won 161.2s hp69 | lost 141.4s hp0 |
| ranged_mix | 2 | lost 69.7s hp0 | won 151.1s hp11 | won 212.1s hp62 | lost 63.4s hp0 |
| ranged_mix | 3 | lost 61.7s hp0 | lost 82.9s hp0 | timeout 240.0s hp60 | lost 43.7s hp0 |
| ranged_mix | 4 | lost 22.9s hp0 | lost 47.3s hp0 | timeout 240.0s hp52 | lost 39.3s hp0 |
| ranged_mix | 5 | lost 39.8s hp0 | lost 146.0s hp0 | lost 231.6s hp0 | lost 36.6s hp0 |
| zone_mix | 1 | lost 81.0s hp0 | lost 168.9s hp0 | won 220.9s hp67 | won 218.0s hp33 |
| zone_mix | 2 | lost 57.2s hp0 | lost 148.2s hp0 | timeout 240.0s hp88 | lost 50.1s hp0 |
| zone_mix | 3 | lost 60.3s hp0 | lost 175.8s hp0 | lost 97.1s hp0 | lost 50.2s hp0 |
| zone_mix | 4 | lost 50.4s hp0 | lost 137.9s hp0 | timeout 240.0s hp34 | timeout 240.0s hp22 |
| zone_mix | 5 | lost 122.1s hp0 | lost 166.1s hp0 | timeout 240.0s hp44 | won 208.8s hp49 |
| boss_thornmane | 1 | won 33.4s hp100 보스0 | won 28.8s hp100 보스0 | won 32.8s hp100 보스0 | won 32.3s hp100 보스0 |
| boss_thornmane | 2 | won 33.2s hp100 보스0 | won 32.3s hp100 보스0 | won 33.1s hp100 보스0 | won 33.6s hp100 보스0 |
| boss_thornmane | 3 | won 32.9s hp100 보스0 | won 31.1s hp100 보스0 | won 33.5s hp100 보스0 | won 30.2s hp100 보스0 |
| boss_guardian | 1 | won 28.8s hp100 보스0 | won 27.6s hp100 보스0 | won 27.3s hp100 보스0 | won 29.6s hp100 보스0 |
| boss_guardian | 2 | won 32.4s hp100 보스0 | won 32.9s hp100 보스0 | won 36.1s hp100 보스0 | won 31.2s hp100 보스0 |
| boss_guardian | 3 | won 30.2s hp100 보스0 | won 31.0s hp100 보스0 | won 29.6s hp100 보스0 | won 29.6s hp100 보스0 |
| boss_eater | 1 | won 29.0s hp76 보스0 | won 33.5s hp100 보스0 | won 33.5s hp100 보스0 | won 35.5s hp100 보스0 |
| boss_eater | 2 | won 31.6s hp62 보스0 | won 29.6s hp100 보스0 | won 30.7s hp100 보스0 | won 36.0s hp100 보스0 |
| boss_eater | 3 | won 30.8s hp86 보스0 | won 33.3s hp100 보스0 | won 38.1s hp100 보스0 | won 30.7s hp100 보스0 |

### 5-4. 피격 태그(당시 조건, 중복 허용 — 원인 확정 아님) · 거절된 타격 · 공격 관측

| 시나리오 | 프로필 | 피격 | not_perceived | perceived_no_input | dodge_rejected_cooldown | dodge_blocked_terrain | after_dodge_025 | hit_by_other_while_escaping | walking_out | overlap | unclassified | 거절(무적/보호) | 공격 관측: 시작/고정/실행/명중/예고 중 사망/취소 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 28 | 24 | 2 | 0 | 0 | 3 | 2 | 1 | 0 | 0 | 3/8 | 192/172/156/28/36/0 |
| baseline_wolf25 | regular | 7 | 0 | 3 | 0 | 0 | 0 | 2 | 2 | 2 | 0 | 1/4 | 182/155/138/7/44/0 |
| baseline_wolf25 | skilled | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 0 | 0/0 | 181/153/141/2/40/0 |
| baseline_wolf25 | balanced | 32 | 0 | 0 | 12 | 3 | 0 | 0 | 0 | 0 | 19 | 2/23 | 179/156/143/32/34/2 |
| ranged_mix | novice | 46 | 16 | 3 | 0 | 6 | 4 | 13 | 16 | 12 | 4 | 2/14 | 557/481/506/46/40/11 |
| ranged_mix | regular | 44 | 0 | 2 | 0 | 1 | 2 | 8 | 24 | 23 | 7 | 3/8 | 948/849/860/44/80/8 |
| ranged_mix | skilled | 22 | 0 | 0 | 0 | 1 | 1 | 3 | 15 | 12 | 4 | 1/1 | 1492/1377/1383/22/105/4 |
| ranged_mix | balanced | 43 | 0 | 0 | 36 | 3 | 2 | 0 | 0 | 0 | 6 | 5/17 | 657/582/596/43/50/11 |
| zone_mix | novice | 60 | 15 | 5 | 0 | 3 | 4 | 20 | 15 | 22 | 11 | 17/5 | 858/435/792/36/56/10 |
| zone_mix | regular | 57 | 2 | 0 | 0 | 3 | 7 | 10 | 22 | 20 | 21 | 8/4 | 1295/510/1205/20/89/1 |
| zone_mix | skilled | 27 | 2 | 0 | 0 | 2 | 2 | 1 | 18 | 14 | 6 | 6/4 | 1427/449/1328/15/95/4 |
| zone_mix | balanced | 40 | 0 | 0 | 39 | 3 | 3 | 0 | 0 | 0 | 1 | 14/7 | 967/310/910/22/56/1 |
| boss_thornmane | novice | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 18/18/18/0/0/0 |
| boss_thornmane | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 19/18/18/0/1/0 |
| boss_thornmane | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 20/18/18/0/2/0 |
| boss_thornmane | balanced | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 19/19/19/0/0/0 |
| boss_guardian | novice | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 0/0 | 25/23/23/0/2/0 |
| boss_guardian | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 23/23/23/0/0/0 |
| boss_guardian | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 25/25/24/0/1/0 |
| boss_guardian | balanced | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3/0 | 24/23/23/0/1/0 |
| boss_eater | novice | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 4 | 0/0 | 17/17/9/3/1/7 |
| boss_eater | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 20/18/12/0/2/6 |
| boss_eater | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 22/20/11/0/2/9 |
| boss_eater | balanced | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1/0 | 29/24/18/0/5/6 |

### 5-5. 지연(판단 간격·인식 지연·실제 최초 입력 지연)

| 시나리오 | 프로필 | 판단 간격 | 인식 지연 평균(위협 수) | 최초 입력 지연 평균 / 판별 p50 중앙 / p90 중앙 (ms, 안에 있던 위협 수) | 누름 짧음/중간/김 | 봇 난수 소비 |
|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 150ms | 453.6 (192) | 520.8 / 525.0 / 608.3 (83) | 0/0/40 | 343 |
| baseline_wolf25 | regular | 100ms | 275.4 (182) | 338.4 / 325.0 / 408.3 (131) | 39/0/0 | 564 |
| baseline_wolf25 | skilled | 50ms | 171.2 (181) | 250.3 / 250.0 / 300.0 (146) | 49/0/0 | 1071 |
| baseline_wolf25 | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| ranged_mix | novice | 150ms | 448.3 (568) | 554.6 / 541.7 / 766.7 (405) | 0/0/129 | 1437 |
| ranged_mix | regular | 100ms | 274.0 (961) | 409.9 / 441.7 / 525.0 (931) | 310/7/0 | 4497 |
| ranged_mix | skilled | 50ms | 165.5 (1501) | 367.7 / 425.0 / 458.3 (1613) | 629/1/0 | 15266 |
| ranged_mix | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| zone_mix | novice | 150ms | 450.7 (865) | 502.1 / 508.3 / 758.3 (656) | 0/0/188 | 2169 |
| zone_mix | regular | 100ms | 276.0 (1310) | 374.4 / 358.3 / 541.7 (1268) | 293/38/1 | 4565 |
| zone_mix | skilled | 50ms | 166.7 (1438) | 332.7 / 308.3 / 466.7 (1197) | 295/60/7 | 7601 |
| zone_mix | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_thornmane | novice | 150ms | 455.6 (18) | 535.0 / 533.3 / 533.3 (5) | 0/0/6 | 39 |
| boss_thornmane | regular | 100ms | 268.4 (19) | 348.3 / 316.7 / 316.7 (5) | 0/5/0 | 45 |
| boss_thornmane | skilled | 50ms | 165.8 (20) | 304.1 / 283.3 / 283.3 (8) | 1/5/2 | 104 |
| boss_thornmane | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_guardian | novice | 150ms | 454.8 (40) | 403.3 / 433.3 / 583.3 (25) | 0/0/14 | 86 |
| boss_guardian | regular | 100ms | 284.0 (40) | 289.3 / 275.0 / 383.3 (25) | 12/1/0 | 133 |
| boss_guardian | skilled | 50ms | 169.5 (44) | 335.0 / 233.3 / 741.7 (36) | 16/0/1 | 286 |
| boss_guardian | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_eater | novice | 150ms | 458.4 (17) | 664.0 / 541.7 / 1091.7 (28) | 0/0/11 | 65 |
| boss_eater | regular | 100ms | 282.1 (20) | 544.5 / 375.0 / 958.3 (35) | 14/0/0 | 101 |
| boss_eater | skilled | 50ms | 181.9 (23) | 714.5 / 583.3 / 1283.3 (46) | 13/2/1 | 228 |
| boss_eater | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |

### 5-6. 준 피해(출처별, PStats 보유 시간 DPS 재사용)

| 시나리오 | 프로필 | 총피해 평균 | 전체 전투시간 DPS(총피해/총전투시간) | 출처별 유효 피해 합(보유시간 DPS) |
|---|---|---|---|---|
| baseline_wolf25 | novice | 750 | 39.9 | weapon:sword 3750(39.9/s) |
| baseline_wolf25 | regular | 750 | 40.7 | weapon:sword 3750(40.7/s) |
| baseline_wolf25 | skilled | 750 | 36.1 | weapon:sword 3750(36.1/s) |
| baseline_wolf25 | balanced | 715 | 40.2 | weapon:sword 3576(40.2/s) |
| ranged_mix | novice | 1147 | 23.8 | weapon:sword 5736(23.8/s) |
| ranged_mix | regular | 1793 | 15.5 | weapon:sword 8963(15.5/s) |
| ranged_mix | skilled | 2002 | 9.2 | weapon:sword 10012(9.2/s) |
| ranged_mix | balanced | 1415 | 21.8 | weapon:sword 7074(21.8/s) |
| zone_mix | novice | 1307 | 17.6 | weapon:sword 6537(17.6/s) |
| zone_mix | regular | 2117 | 13.3 | weapon:sword 10587(13.3/s) |
| zone_mix | skilled | 2381 | 11.5 | weapon:sword 11903(11.5/s) |
| zone_mix | balanced | 2043 | 13.3 | weapon:sword 10215(13.3/s) |
| boss_thornmane | novice | 2520 | 76.0 | weapon:blades 2971(29.9/s), weapon:ember 2386(24.0/s), weapon:sword 2133(21.4/s), skill:gust 70(1.1/s) |
| boss_thornmane | regular | 2500 | 81.4 | weapon:blades 2862(31.0/s), weapon:ember 2509(27.2/s), weapon:sword 2090(22.7/s), skill:gust 40(0.7/s) |
| boss_thornmane | skilled | 2520 | 76.1 | weapon:blades 2993(30.1/s), weapon:sword 2289(23.0/s), weapon:ember 2278(22.9/s) |
| boss_thornmane | balanced | 2480 | 77.5 | weapon:blades 2840(29.6/s), weapon:ember 2447(25.5/s), weapon:sword 2113(22.0/s), skill:gust 40(0.6/s) |
| boss_guardian | novice | 5268 | 173.0 | weapon:ember 10241(112.1/s), weapon:sword 2974(32.5/s), weapon:blades 2588(28.3/s) |
| boss_guardian | regular | 5254 | 172.2 | weapon:ember 10278(112.3/s), weapon:sword 2902(31.7/s), weapon:blades 2582(28.2/s) |
| boss_guardian | skilled | 5120 | 165.4 | weapon:ember 10508(113.1/s), weapon:sword 2508(27.0/s), weapon:blades 2344(25.2/s) |
| boss_guardian | balanced | 5268 | 175.1 | weapon:ember 10348(114.5/s), weapon:sword 2946(32.6/s), weapon:blades 2510(27.8/s) |
| boss_eater | novice | 7000 | 229.9 | weapon:ember 13231(144.8/s), weapon:blades 4035(44.1/s), weapon:sword 3353(36.7/s), dot:burn@blades 296(3.2/s), dot:burn@sword 85(0.9/s) |
| boss_eater | regular | 7035 | 219.1 | weapon:ember 13766(142.8/s), weapon:blades 3713(38.5/s), weapon:sword 3187(33.1/s), dot:burn@blades 282(2.9/s), dot:burn@sword 105(1.1/s) |
| boss_eater | skilled | 7060 | 207.0 | weapon:ember 14022(137.1/s), weapon:blades 3679(36.0/s), weapon:sword 2955(28.9/s), dot:burn@blades 326(3.2/s), common:flare 97(1.3/s) |
| boss_eater | balanced | 7060 | 207.4 | weapon:ember 13611(133.2/s), weapon:blades 3715(36.4/s), weapon:sword 3424(33.5/s), dot:burn@blades 279(2.7/s), dot:burn@sword 137(1.3/s) |

## 6. 사람 확인 필요

- 프로필 시험값(지연·후보 수·오차)과 공통 규칙은 실측 인구 통계가 아니다. 검증 메뉴의 '이번 전투 입력 기록'으로 사람 기록 5~10회를 모아 전투 시간·피해 출처·회피 빈도/거리·Q/E와 비교해야 한다(**사람 보정 미완료**).
- 실력 순서와 결과가 뒤집힌 seed·시나리오는 관측/판단/기술 적합성 원인 조사 대상이지 숨길 결과가 아니다. 이 표로 게임 수치를 바꾸지 않는다(원인 후보·조정 대상만 보고).
- 태그는 '다른 방향이면 피했다'를 뜻하지 않는다. 그런 결론은 해당 입력 기록을 재생해 대안 입력을 따로 검사해야 한다.

## 7. 구현자 관찰 메모(손으로 작성 — 위 표에서 읽은 것, 원인 확정 아님. `PROPHECY_BOT_MODE=report`로 재생성하면 이 절은 사라지므로 다시 붙일 것)

- 기준 전투(늑대 25): 세 프로필 모두 5/5 승리(N=5, Wilson 하한 57%). 받은 피해 평균 novice 67 → regular 17 → skilled 5, 남은 체력 33 → 83 → 95로 실력 순서가 유지된다. novice 피격 28회 중 24회가 `not_perceived`(인식 350~550ms > 물기 예고 0.35초): 늑대 물기의 짧은 예고에 novice가 불리하다는 지시문 §5의 예상과 일치. 기존 `balanced`는 3/5(누름 거절 217회 = 매 판단 회피를 누르는 기존 정책의 성질; 태그 `dodge_rejected_cooldown` 12).
- 능선 3일차·습지 4일차(검 Lv1 고정, 전체 65마리): novice·regular는 전패, skilled는 2/5·1/5 + 시간초과 2·3. 패배 생존 시간 중앙값은 novice 47/60초 → regular 83/166초 → skilled 232/97초로 늘어나지만 승리로 잘 이어지지 않는다. 총피해가 적 체력 합에 못 미치는 구간이라 조작 실력만으로 뒤집히지 않는 것으로 보인다(검 Lv1·성장 없음이 시나리오 정의). 이 시나리오에서 실력 차이는 승패보다 생존 시간·피격 태그에 나타난다. 무기·성장 축(§10-4)은 별도 표가 필요하다.
- skilled의 시간초과·긴 승리(151~221초): 조준선(궁수)에 반응 문턱(진행률 0.4)을 두었는데도 이동·회피에 시간을 많이 써 처치 속도(전체 DPS 9.2/s vs novice 23.8/s)가 낮다. '안전하지만 느린' 조작 모델의 성질이며 사람의 선택과 다를 수 있다 → 사람 기록과 비교할 항목.
- 보스 3종(실험실 프리셋): 전 프로필 3/3 승리, 피격은 novice에서만(수호자 zone 20, 먹는 자 wide 72·mark 28). 표본 3은 승률 판단에 쓰지 않는다. 보스 공격 관측에서 `killed_during_telegraph`·`cancelled`(먹는 자의 표식 잔여로 취소)가 구분돼 남는다.
- 태그 분포: regular/skilled 피격의 다수가 `walking_out`(걸어서 벗어나던 중)·`overlap`(중첩)·`hit_by_other_while_escaping` — 걷기/회피 선택 규칙(추정 잔여 0.6초 가정)과 주의력 상한이 다음 조정 후보. 어느 것도 게임 수치 조정 근거로 쓰지 않는다.
- 정체(stalled) 0건: 첫 실행에서 skilled가 능선에서 정체(궁수 조준선을 항상 즉시 비켜 거리를 못 좁힘)해 공통 반응 문턱을 넣고 전부 재실행했다(`docs/BOT_FRAMEWORK.md` §3-2).
- 저장된 재생 파일 표본 6개를 같은 시나리오 초기 상태에 재생해 주기 해시·결과가 일치했다(같은 PC·같은 커밋).
