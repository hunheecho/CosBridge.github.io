# 실력 봇 비교(run audit2_after)

생성: `tools/bot_batch.gd` (run_id `audit2_after`, 2026-09-07T23:38:45). **가상 조작 모델(실제 플레이어 분포 아님) · 사람 보정 미완료.** 봇 결과는 규칙·정보 경계·집계 검증용이며 사람 승률·재미·가독성 판단이 아니다. 시간초과는 시간초과로 남긴다(패배·승리로 치환하지 않음).

환경: 게임 godot-0.6.0 · 규칙 rules@godot-0.6.0/observe-3 · 봇 skillbot-0.2/skillbot-0.1 · 관측 observe-3 · 기록 형식 prophecy_replay/1 · 엔진 4.7.2-stable (official) · OS Windows/x86_64 · git HEAD 8dfcbd1da645e6482d1d9523c828f1d1b8499d66 (prophecy_godot 미커밋 변경: true) · 데이터 해시 cb567b2ded307ab9 · 프로필 해시 d325940048e157de · 설정 해시 f67688401f5a4651

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

- 시나리오: baseline_wolf25(0.3.1 D33 기준 전투(x5 늑대 25, 동시 12, 동시 돌진 2, 회피 hold 70~150/1.5초)), ranged_mix(바람 능선 3일차 기본 편성(궁수·방패병·늑대·거미, uniform_x5), 검 Lv1 고정), zone_mix(안개 습지 4일차 기본 편성(포자·서리술사·거미·궁수·늑대, uniform_x5), 검 Lv1 고정), boss_guardian(봉인 수호자 × stage2 프리셋), boss_warden(성문 파수장(1막) × stage1 프리셋, 체력 hi 2400), boss_matriarch(포자 어미(1막) × stage1 프리셋, 체력 hi 2400), boss_stalker(서리 추적자(2막) × stage2 프리셋, 체력 hi 5000). 미구현(`unimplemented`) 행: 0.
- 게임 seed [1, 2, 3, 4, 5](봇 seed = 게임 seed) × 프로필 ["novice", "regular", "skilled", "balanced"]. 같은 seed의 반복 재생은 독립 표본이 아니다. 전투 상한: { "baseline_wolf25": 240.0, "ranged_mix": 240.0, "zone_mix": 240.0, "boss_guardian": 300.0, "boss_warden": 300.0, "boss_matriarch": 300.0, "boss_stalker": 300.0 }초. 정체(stalled) = 처치·피해·체력 변화 없이 60초.
- 완료 108행, 상태 분포 {"lost":30,"timeout":4,"won":74}. 회귀 검사는 `tests/bot_tests.gd`(정보 경계·지연·기록 재생·검산·배치 재개).

## 4. 비용과 재현 방법

- 벽시계 합계 454.9초(전투당 평균 4.21초, 최장 시뮬 240.0초, 예산 2400초). 헤드리스 처리 속도는 실제 화면 FPS가 아니다.
- 재현: `PROPHECY_BOT_RUN_ID=audit2_after godot --headless --path prophecy_godot -s tools/bot_batch.gd` (같은 run_id면 완료 행을 건너뛰고 재개; 캐시 키(git HEAD·데이터·프로필·설정·엔진·OS)가 다르면 무효화 메시지). 결과 원본: `docs/sim/bot_runs/audit2_after/results.jsonl`, 실패 전투·표본 성공 전투의 입력 기록: `replays/`(`PReplay.replay`로 상태 해시 대조). OS 간 일치는 이번에 검증하지 않았다.

## 5. 관찰 결과

### 5-1. 일반 전투(검 Lv1 고정)

| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 받은 피해 평균 | 피격 수 | 남은 체력 평균(승) | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 최대 동시 적/예고/투사체/장판 | 피해 출처(유효 합) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 5 | 5 | 0 | 0 | 0 | 0 | 5/5 = 100% [57%, 100%] | 18.3 / 20.2 (N<10: p90 불안정) | - | 67.2 | 28 | 32.8 | 8.0 (136.0) | 8 | 0 | 8/0 | 12/6/0/0 | wolf:bite 324, wolf:dash 12 |
| baseline_wolf25 | regular | 5 | 5 | 0 | 0 | 0 | 0 | 5/5 = 100% [57%, 100%] | 17.8 / 18.9 (N<10: p90 불안정) | - | 16.8 | 7 | 83.2 | 7.8 (70.0) | 0 | 0 | 7/0 | 12/6/0/0 | wolf:bite 72, wolf:dash 12 |
| baseline_wolf25 | skilled | 5 | 5 | 0 | 0 | 0 | 0 | 5/5 = 100% [57%, 100%] | 20.9 / 22.1 (N<10: p90 불안정) | - | 4.8 | 2 | 95.2 | 9.8 (67.9) | 3 | 0 | 10/0 | 12/5/0/0 | wolf:dash 12, wolf:bite 12 |
| baseline_wolf25 | balanced | 5 | 3 | 2 | 0 | 0 | 0 | 3/5 = 60% [23%, 88%] | 19.4 / 19.4 (N<10: p90 불안정) | 13.8 | 73.6 | 32 | 44.0 | 4.6 (71.5) | 5 | 217 | 8/0 | 12/6/0/0 | wolf:bite 256, wolf:dash 112 |
| ranged_mix | novice | 5 | 1 | 4 | 0 | 0 | 0 | 1/5 = 20% [4%, 62%] | 126.4 / 126.4 (N<10: p90 불안정) | 40.6 | 99.2 | 44 | 4.0 | 29.6 (123.3) | 47 | 0 | 16/0 | 12/8/3/3 | bash 173, wolf:bite 156, arrow 96, bite 59, wolf:dash 12 |
| ranged_mix | regular | 5 | 3 | 2 | 0 | 0 | 0 | 3/5 = 60% [23%, 88%] | 163.3 / 163.3 (N<10: p90 불안정) | 39.2 | 84.4 | 35 | 26.0 | 62.6 (68.7) | 26 | 0 | 24/0 | 12/9/3/3 | bash 230, arrow 78, wolf:bite 60, wolf:dash 36, bite 18 |
| ranged_mix | skilled | 5 | 2 | 1 | 2 | 0 | 0 | 2/5 = 40% [12%, 77%] | 186.8 / 186.8 (N<10: p90 불안정) | 214.5 | 64.4 | 28 | 50.0 | 127.2 (67.9) | 83 | 0 | 48/0 | 12/9/3/3 | bash 140, arrow 116, wolf:bite 36, bite 18, wolf:dash 12 |
| ranged_mix | balanced | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 43.7 | 100.0 | 43 | - | 36.4 (107.2) | 59 | 2113 | 21/0 | 12/9/3/3 | bash 215, wolf:bite 108, arrow 99, wolf:dash 60, bite 18 |
| zone_mix | novice | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 52.0 | 100.0 | 56 | - | 27.6 (129.2) | 41 | 0 | 20/0 | 12/12/3/14 | wolf:bite 166, zone 111, bite 108, arrow 67, frostzone 24, wolf:dash 24 |
| zone_mix | regular | 5 | 0 | 5 | 0 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 109.5 | 100.0 | 62 | - | 51.0 (72.1) | 18 | 0 | 34/0 | 12/14/3/13 | zone 154, arrow 140, bite 99, frostzone 95, wolf:dash 12 |
| zone_mix | skilled | 5 | 0 | 4 | 1 | 0 | 0 | 0/5 = 0% [0%, 43%] | - | 169.8 | 98.0 | 61 | - | 87.2 (72.9) | 34 | 0 | 62/0 | 12/12/3/14 | zone 187, arrow 110, frostzone 94, bite 63, wolf:dash 24, wolf:bite 12 |
| zone_mix | balanced | 5 | 2 | 2 | 1 | 0 | 0 | 2/5 = 40% [12%, 77%] | 208.8 / 208.8 (N<10: p90 불안정) | 50.1 | 79.2 | 40 | 41.0 | 53.0 (106.6) | 95 | 1959 | 47/0 | 12/13/3/14 | frostzone 120, wolf:bite 72, bite 63, arrow 60, zone 45, wolf:dash 36 |

### 5-2. 보스(실험실 프리셋 빌드)

| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 보스 남은 체력 평균 | 받은 피해 평균 | 피격 수 | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 피해 출처(유효 합) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| boss_guardian | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.1 / 30.1 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 6.0 (143.7) | 5 | 0 | 8/0 | - |
| boss_guardian | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 27.3 / 27.3 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 4.0 (73.4) | 0 | 0 | 7/0 | - |
| boss_guardian | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.6 / 30.6 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 5.7 (74.7) | 0 | 0 | 7/0 | - |
| boss_guardian | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 29.6 / 29.6 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 4.7 (129.3) | 5 | 63 | 6/0 | - |
| boss_warden | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 34.4 / 34.4 (N<10: p90 불안정) | - | 0 | 30.0 | 5 | 7.0 (114.7) | 10 | 0 | 9/0 | boss_breach 90 |
| boss_warden | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.4 / 32.4 (N<10: p90 불안정) | - | 0 | 6.0 | 1 | 6.0 (79.1) | 3 | 0 | 9/0 | boss_breach 18 |
| boss_warden | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.9 / 32.9 (N<10: p90 불안정) | - | 0 | 6.0 | 1 | 5.0 (76.3) | 4 | 0 | 9/0 | boss_breach 18 |
| boss_warden | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.0 / 31.0 (N<10: p90 불안정) | - | 0 | 5.3 | 1 | 5.0 (112.0) | 6 | 82 | 9/0 | boss_bsweep 16 |
| boss_matriarch | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 46.8 / 46.8 (N<10: p90 불안정) | - | 0 | 70.7 | 21 | 10.7 (132.8) | 12 | 0 | 10/5 | boss_ring 128, zone 56, boss_spore_shot 28 |
| boss_matriarch | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 57.1 / 57.1 (N<10: p90 불안정) | - | 0 | 53.0 | 14 | 10.3 (90.7) | 2 | 0 | 10/5 | boss_ring 128, zone 31 |
| boss_matriarch | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 56.2 / 56.2 (N<10: p90 불안정) | - | 0 | 55.7 | 18 | 11.7 (82.6) | 5 | 0 | 11/5 | boss_ring 112, zone 55 |
| boss_matriarch | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 51.2 / 51.2 (N<10: p90 불안정) | - | 0 | 63.3 | 12 | 9.7 (89.4) | 15 | 359 | 10/4 | boss_ring 176, boss_spore_shot 14 |
| boss_stalker | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.6 / 31.6 (N<10: p90 불안정) | - | 0 | 4.0 | 1 | 7.3 (147.1) | 4 | 0 | 9/0 | boss_icepath 12 |
| boss_stalker | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.4 / 30.4 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 8.0 (76.8) | 0 | 0 | 7/0 | - |
| boss_stalker | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.0 / 32.0 (N<10: p90 불안정) | - | 0 | 8.0 | 2 | 7.7 (74.4) | 2 | 0 | 9/0 | boss_icepath 24 |
| boss_stalker | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.8 / 32.8 (N<10: p90 불안정) | - | 0 | 31.7 | 8 | 6.3 (101.4) | 6 | 91 | 9/0 | boss_icepath 84, boss_icebolt 11 |

### 5-3. seed별 짝(성공·실패가 바뀐 짝 보존)

| 시나리오 | 게임 seed | novice | regular | skilled | balanced |
|---|---|---|---|---|---|
| baseline_wolf25 | 1 | won 20.2s hp28 | won 15.5s hp76 | won 22.1s hp100 | won 21.5s hp40 |
| baseline_wolf25 | 2 | won 18.3s hp40 | won 18.9s hp88 | won 20.9s hp88 | won 19.4s hp52 |
| baseline_wolf25 | 3 | won 20.7s hp40 | won 17.8s hp76 | won 19.2s hp100 | lost 15.4s hp0 |
| baseline_wolf25 | 4 | won 17.0s hp16 | won 17.7s hp88 | won 22.6s hp100 | won 18.8s hp40 |
| baseline_wolf25 | 5 | won 17.8s hp40 | won 22.4s hp88 | won 19.1s hp88 | lost 13.8s hp0 |
| ranged_mix | 1 | won 126.4s hp4 | won 161.4s hp14 | timeout 240.0s hp67 | lost 141.4s hp0 |
| ranged_mix | 2 | lost 44.3s hp0 | won 163.3s hp48 | won 226.8s hp52 | lost 63.4s hp0 |
| ranged_mix | 3 | lost 49.2s hp0 | lost 39.2s hp0 | lost 214.5s hp0 | lost 43.7s hp0 |
| ranged_mix | 4 | lost 22.9s hp0 | lost 42.5s hp0 | won 186.8s hp48 | lost 39.3s hp0 |
| ranged_mix | 5 | lost 40.6s hp0 | won 178.8s hp16 | timeout 240.0s hp11 | lost 36.6s hp0 |
| zone_mix | 1 | lost 52.0s hp0 | lost 150.6s hp0 | lost 156.6s hp0 | won 218.0s hp33 |
| zone_mix | 2 | lost 92.9s hp0 | lost 69.0s hp0 | timeout 240.0s hp10 | lost 50.1s hp0 |
| zone_mix | 3 | lost 58.8s hp0 | lost 112.2s hp0 | lost 186.4s hp0 | lost 50.2s hp0 |
| zone_mix | 4 | lost 39.7s hp0 | lost 109.5s hp0 | lost 169.8s hp0 | timeout 240.0s hp22 |
| zone_mix | 5 | lost 23.5s hp0 | lost 72.6s hp0 | lost 184.3s hp0 | won 208.8s hp49 |
| boss_guardian | 1 | won 28.0s hp100 보스0 | won 27.2s hp100 보스0 | won 28.4s hp100 보스0 | won 29.6s hp100 보스0 |
| boss_guardian | 2 | won 32.3s hp100 보스0 | won 33.2s hp100 보스0 | won 33.6s hp100 보스0 | won 31.2s hp100 보스0 |
| boss_guardian | 3 | won 30.1s hp100 보스0 | won 27.3s hp100 보스0 | won 30.6s hp100 보스0 | won 29.6s hp100 보스0 |
| boss_warden | 1 | won 34.5s hp94 보스0 | won 34.0s hp100 보스0 | won 32.2s hp100 보스0 | won 31.0s hp84 보스0 |
| boss_warden | 2 | won 31.6s hp97 보스0 | won 30.7s hp100 보스0 | won 32.9s hp100 보스0 | won 30.8s hp100 보스0 |
| boss_warden | 3 | won 34.4s hp94 보스0 | won 32.4s hp100 보스0 | won 33.2s hp82 보스0 | won 31.2s hp100 보스0 |
| boss_matriarch | 1 | won 44.5s hp49 보스0 | won 57.1s hp56 보스0 | won 60.0s hp94 보스0 | won 51.2s hp53 보스0 |
| boss_matriarch | 2 | won 46.8s hp83 보스0 | won 48.1s hp84 보스0 | won 54.5s hp78 보스0 | won 49.1s hp51 보스0 |
| boss_matriarch | 3 | won 52.2s hp31 보스0 | won 58.1s hp71 보스0 | won 56.2s hp36 보스0 | won 52.3s hp66 보스0 |
| boss_stalker | 1 | won 33.5s hp100 보스0 | won 30.4s hp100 보스0 | won 32.0s hp100 보스0 | won 32.8s hp88 보스0 |
| boss_stalker | 2 | won 31.6s hp100 보스0 | won 30.3s hp100 보스0 | won 30.4s hp88 보스0 | won 31.1s hp77 보스0 |
| boss_stalker | 3 | won 30.9s hp88 보스0 | won 37.0s hp100 보스0 | won 35.6s hp100 보스0 | won 33.5s hp94 보스0 |

### 5-4. 피격 태그(당시 조건, 중복 허용 — 원인 확정 아님) · 거절된 타격 · 공격 관측

| 시나리오 | 프로필 | 피격 | not_perceived | perceived_no_input | dodge_rejected_cooldown | dodge_blocked_terrain | after_dodge_025 | hit_by_other_while_escaping | walking_out | overlap | unclassified | 거절(무적/보호) | 공격 관측: 시작/고정/실행/명중/예고 중 사망/취소 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 28 | 24 | 2 | 0 | 0 | 3 | 2 | 1 | 0 | 0 | 3/8 | 192/172/156/28/36/0 |
| baseline_wolf25 | regular | 7 | 0 | 3 | 0 | 0 | 0 | 2 | 2 | 2 | 0 | 1/4 | 182/155/138/7/44/0 |
| baseline_wolf25 | skilled | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 0 | 0/0 | 181/153/141/2/40/0 |
| baseline_wolf25 | balanced | 32 | 0 | 0 | 12 | 3 | 0 | 0 | 0 | 0 | 19 | 2/23 | 179/156/143/32/34/2 |
| ranged_mix | novice | 44 | 13 | 7 | 0 | 3 | 3 | 12 | 14 | 16 | 2 | 0/15 | 586/507/524/44/57/5 |
| ranged_mix | regular | 35 | 0 | 2 | 0 | 1 | 2 | 5 | 21 | 19 | 5 | 3/6 | 934/838/853/35/77/4 |
| ranged_mix | skilled | 28 | 0 | 0 | 0 | 0 | 1 | 5 | 20 | 20 | 3 | 3/1 | 1505/1392/1392/28/110/3 |
| ranged_mix | balanced | 43 | 0 | 0 | 36 | 3 | 2 | 0 | 0 | 0 | 6 | 5/17 | 657/579/596/43/50/11 |
| zone_mix | novice | 56 | 19 | 2 | 0 | 6 | 2 | 16 | 11 | 13 | 13 | 17/12 | 609/329/561/35/43/5 |
| zone_mix | regular | 62 | 0 | 0 | 0 | 3 | 7 | 8 | 19 | 14 | 33 | 12/8 | 978/447/910/26/65/3 |
| zone_mix | skilled | 61 | 0 | 0 | 0 | 2 | 6 | 5 | 22 | 15 | 32 | 6/6 | 1545/652/1462/21/78/5 |
| zone_mix | balanced | 40 | 0 | 0 | 39 | 3 | 3 | 0 | 0 | 0 | 1 | 14/7 | 967/309/910/22/56/1 |
| boss_guardian | novice | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 23/23/23/0/0/0 |
| boss_guardian | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 22/22/22/0/0/0 |
| boss_guardian | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1/0 | 25/24/24/0/1/0 |
| boss_guardian | balanced | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3/0 | 24/23/23/0/1/0 |
| boss_warden | novice | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 5 | 0 | 0 | 0/0 | 23/23/23/5/0/0 |
| boss_warden | regular | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0/0 | 23/23/23/1/0/0 |
| boss_warden | skilled | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0/0 | 22/21/21/1/1/0 |
| boss_warden | balanced | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 21/21/21/1/0/0 |
| boss_matriarch | novice | 21 | 9 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 12 | 1/0 | 33/27/28/10/5/0 |
| boss_matriarch | regular | 14 | 5 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 9 | 2/0 | 39/32/33/8/6/0 |
| boss_matriarch | skilled | 18 | 5 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 12 | 1/0 | 40/34/37/7/3/0 |
| boss_matriarch | balanced | 12 | 0 | 0 | 9 | 1 | 0 | 0 | 0 | 0 | 3 | 0/1 | 35/30/33/12/2/0 |
| boss_stalker | novice | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0/0 | 25/24/24/1/1/0 |
| boss_stalker | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 27/26/26/0/1/0 |
| boss_stalker | skilled | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 0/0 | 27/26/26/2/1/0 |
| boss_stalker | balanced | 8 | 0 | 0 | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 0/0 | 24/23/23/8/1/0 |

### 5-5. 지연(판단 간격·인식 지연·실제 최초 입력 지연)

| 시나리오 | 프로필 | 판단 간격 | 인식 지연 평균(위협 수) | 최초 입력 지연 평균 / 판별 p50 중앙 / p90 중앙 (ms, 안에 있던 위협 수) | 누름 짧음/중간/김 | 봇 난수 소비 |
|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 150ms | 453.6 (192) | 520.8 / 525.0 / 608.3 (83) | 0/0/40 | 343 |
| baseline_wolf25 | regular | 100ms | 275.4 (182) | 338.4 / 325.0 / 408.3 (131) | 39/0/0 | 564 |
| baseline_wolf25 | skilled | 50ms | 171.2 (181) | 250.3 / 250.0 / 300.0 (146) | 49/0/0 | 1071 |
| baseline_wolf25 | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| ranged_mix | novice | 150ms | 448.8 (613) | 538.1 / 533.3 / 800.0 (452) | 0/0/148 | 1589 |
| ranged_mix | regular | 100ms | 276.0 (962) | 408.4 / 450.0 / 525.0 (908) | 312/1/0 | 4360 |
| ranged_mix | skilled | 50ms | 166.4 (1543) | 365.4 / 425.0 / 458.3 (1649) | 634/2/0 | 15481 |
| ranged_mix | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| zone_mix | novice | 150ms | 450.6 (1004) | 515.8 / 516.7 / 708.3 (470) | 0/0/138 | 1921 |
| zone_mix | regular | 100ms | 274.6 (1765) | 383.7 / 391.7 / 541.7 (951) | 230/23/2 | 4277 |
| zone_mix | skilled | 50ms | 165.9 (2941) | 347.9 / 308.3 / 466.7 (1518) | 388/44/4 | 11120 |
| zone_mix | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_guardian | novice | 150ms | 452.4 (100) | 536.1 / 516.7 / 641.7 (27) | 0/0/18 | 161 |
| boss_guardian | regular | 100ms | 272.1 (74) | 276.7 / 316.7 / 383.3 (25) | 11/1/0 | 160 |
| boss_guardian | skilled | 50ms | 168.2 (91) | 294.2 / 275.0 / 641.7 (36) | 16/0/1 | 361 |
| boss_guardian | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_warden | novice | 150ms | 438.8 (23) | 412.6 / 400.0 / 575.0 (41) | 0/0/21 | 120 |
| boss_warden | regular | 100ms | 278.6 (23) | 468.7 / 391.7 / 633.3 (34) | 12/6/0 | 136 |
| boss_warden | skilled | 50ms | 170.5 (22) | 309.6 / 291.7 / 375.0 (26) | 10/5/0 | 214 |
| boss_warden | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_matriarch | novice | 150ms | 443.9 (53) | 443.5 / 500.0 / 566.7 (42) | 0/0/32 | 158 |
| boss_matriarch | regular | 100ms | 276.1 (79) | 328.3 / 358.3 / 466.7 (56) | 22/0/9 | 323 |
| boss_matriarch | skilled | 50ms | 168.2 (78) | 215.2 / 183.3 / 408.3 (58) | 25/2/8 | 574 |
| boss_matriarch | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_stalker | novice | 150ms | 456.3 (212) | 589.1 / 575.0 / 616.7 (22) | 0/0/22 | 278 |
| boss_stalker | regular | 100ms | 278.6 (122) | 348.2 / 366.7 / 416.7 (28) | 20/4/0 | 244 |
| boss_stalker | skilled | 50ms | 167.3 (142) | 327.5 / 316.7 / 375.0 (34) | 19/4/0 | 473 |
| boss_stalker | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |

### 5-6. 준 피해(출처별, PStats 보유 시간 DPS 재사용)

| 시나리오 | 프로필 | 총피해 평균 | 전체 전투시간 DPS(총피해/총전투시간) | 출처별 유효 피해 합(보유시간 DPS) |
|---|---|---|---|---|
| baseline_wolf25 | novice | 750 | 39.9 | weapon:sword 3750(39.9/s) |
| baseline_wolf25 | regular | 750 | 40.7 | weapon:sword 3750(40.7/s) |
| baseline_wolf25 | skilled | 750 | 36.1 | weapon:sword 3750(36.1/s) |
| baseline_wolf25 | balanced | 715 | 40.2 | weapon:sword 3576(40.2/s) |
| ranged_mix | novice | 1266 | 22.3 | weapon:sword 6330(22.3/s) |
| ranged_mix | regular | 1773 | 15.1 | weapon:sword 8865(15.1/s) |
| ranged_mix | skilled | 2041 | 9.2 | weapon:sword 10206(9.2/s) |
| ranged_mix | balanced | 1415 | 21.8 | weapon:sword 7074(21.8/s) |
| zone_mix | novice | 1049 | 19.7 | weapon:sword 5247(19.7/s) |
| zone_mix | regular | 1549 | 15.1 | weapon:sword 7744(15.1/s) |
| zone_mix | skilled | 2140 | 11.4 | weapon:sword 10698(11.4/s) |
| zone_mix | balanced | 2043 | 13.3 | weapon:sword 10215(13.3/s) |
| boss_guardian | novice | 5176 | 171.8 | weapon:ember 10462(115.7/s), weapon:sword 2743(30.3/s), weapon:blades 2323(25.7/s) |
| boss_guardian | regular | 5200 | 177.9 | weapon:ember 10110(115.3/s), weapon:sword 2911(33.2/s), weapon:blades 2579(29.4/s) |
| boss_guardian | skilled | 5160 | 167.4 | weapon:ember 10874(117.4/s), weapon:sword 2404(26.0/s), weapon:blades 2202(23.8/s) |
| boss_guardian | balanced | 5268 | 175.1 | weapon:ember 10348(114.5/s), weapon:sword 2946(32.6/s), weapon:blades 2510(27.8/s) |
| boss_warden | novice | 2400 | 71.7 | weapon:blades 2746(27.3/s), weapon:ember 2457(24.4/s), weapon:sword 1997(19.9/s) |
| boss_warden | regular | 2400 | 74.2 | weapon:blades 2733(28.1/s), weapon:ember 2533(26.1/s), weapon:sword 1935(19.9/s) |
| boss_warden | skilled | 2400 | 73.3 | weapon:blades 2604(26.5/s), weapon:ember 2602(26.5/s), weapon:sword 1993(20.3/s) |
| boss_warden | balanced | 2400 | 77.5 | weapon:blades 2673(28.7/s), weapon:ember 2418(26.0/s), weapon:sword 2109(22.7/s) |
| boss_matriarch | novice | 2499 | 52.3 | weapon:ember 3398(23.7/s), weapon:blades 2598(18.1/s), weapon:sword 1435(10.0/s), skill:gust 65(0.7/s) |
| boss_matriarch | regular | 2510 | 46.1 | weapon:ember 3772(23.1/s), weapon:blades 2414(14.8/s), weapon:sword 1289(7.9/s), skill:gust 55(0.5/s) |
| boss_matriarch | skilled | 2510 | 44.1 | weapon:ember 3880(22.7/s), weapon:blades 2249(13.2/s), weapon:sword 1327(7.8/s), skill:gust 75(0.6/s) |
| boss_matriarch | balanced | 2492 | 49.0 | weapon:ember 3434(22.5/s), weapon:blades 2446(16.0/s), weapon:sword 1520(10.0/s), skill:gust 75(0.5/s) |
| boss_stalker | novice | 5000 | 156.2 | weapon:ember 9467(98.6/s), weapon:sword 2947(30.7/s), weapon:blades 2586(26.9/s) |
| boss_stalker | regular | 5000 | 153.6 | weapon:ember 9436(96.6/s), weapon:sword 2997(30.7/s), weapon:blades 2567(26.3/s) |
| boss_stalker | skilled | 5000 | 153.0 | weapon:ember 9770(99.7/s), weapon:sword 2800(28.6/s), weapon:blades 2430(24.8/s) |
| boss_stalker | balanced | 5000 | 154.1 | weapon:ember 9027(92.7/s), weapon:sword 3287(33.7/s), weapon:blades 2686(27.6/s) |

## 6. 사람 확인 필요

- 프로필 시험값(지연·후보 수·오차)과 공통 규칙은 실측 인구 통계가 아니다. 검증 메뉴의 '이번 전투 입력 기록'으로 사람 기록 5~10회를 모아 전투 시간·피해 출처·회피 빈도/거리·Q/E와 비교해야 한다(**사람 보정 미완료**).
- 실력 순서와 결과가 뒤집힌 seed·시나리오는 관측/판단/기술 적합성 원인 조사 대상이지 숨길 결과가 아니다. 이 표로 게임 수치를 바꾸지 않는다(원인 후보·조정 대상만 보고).
- 태그는 '다른 방향이면 피했다'를 뜻하지 않는다. 그런 결론은 해당 입력 기록을 재생해 대안 입력을 따로 검사해야 한다.
