# ?ㅻ젰蹂??꾪닾 遊?횞 ?좉퇋 愿臾?蹂댁뒪 6醫?鍮꾧탳(BOT_COMPARE_BOSS3)

생성: `tools/bot_batch.gd` (run_id `boss3_compare1`, 2026-09-07T22:24:00). **가상 조작 모델(실제 플레이어 분포 아님) · 사람 보정 미완료.** 봇 결과는 규칙·정보 경계·집계 검증용이며 사람 승률·재미·가독성 판단이 아니다. 시간초과는 시간초과로 남긴다(패배·승리로 치환하지 않음).

환경: 게임 godot-0.6.0-s2 · 규칙 rules@godot-0.6.0-s2/observe-2 · 봇 skillbot-0.1/skillbot-0.1 · 관측 observe-2 · 기록 형식 prophecy_replay/1 · 엔진 4.7.2-stable (official) · OS Windows/x86_64 · git HEAD 41a2bd6dce30f28f18e28df8c57a69eda8164275 (prophecy_godot 미커밋 변경: true) · 데이터 해시 be035c9e8c4db700 · 프로필 해시 d325940048e157de · 설정 해시 54570b6cae131924

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

- 시나리오: boss_warden(성문 파수장(1막) × stage1 프리셋, 체력 hi 2400), boss_matriarch(포자 어미(1막) × stage1 프리셋, 체력 hi 2400), boss_behemoth(굴착 거수(2막) × stage2 프리셋, 체력 hi 5000), boss_stalker(서리 추적자(2막) × stage2 프리셋, 체력 hi 5000), boss_hunt_king(핏빛 사냥왕(3막) × stage3 프리셋, 체력 hi 7000), boss_executor(종말의 집행관(3막) × stage3 프리셋, 체력 hi 7000). 미구현(`unimplemented`) 행: 0.
- 게임 seed [1, 2, 3, 4, 5](봇 seed = 게임 seed) × 프로필 ["novice", "regular", "skilled", "balanced"]. 같은 seed의 반복 재생은 독립 표본이 아니다. 전투 상한: { "boss_warden": 300.0, "boss_matriarch": 300.0, "boss_behemoth": 300.0, "boss_stalker": 300.0, "boss_hunt_king": 300.0, "boss_executor": 300.0 }초. 정체(stalled) = 처치·피해·체력 변화 없이 60초.
- 완료 72행, 상태 분포 {"won":72}. 회귀 검사는 `tests/bot_tests.gd`(정보 경계·지연·기록 재생·검산·배치 재개).

## 4. 비용과 재현 방법

- 벽시계 합계 143.1초(전투당 평균 1.99초, 최장 시뮬 66.3초, 예산 3600초). 헤드리스 처리 속도는 실제 화면 FPS가 아니다.
- 재현: `PROPHECY_BOT_RUN_ID=boss3_compare1 godot --headless --path prophecy_godot -s tools/bot_batch.gd` (같은 run_id면 완료 행을 건너뛰고 재개; 캐시 키(git HEAD·데이터·프로필·설정·엔진·OS)가 다르면 무효화 메시지). 결과 원본: `docs/sim/bot_runs/boss3_compare1/results.jsonl`, 실패 전투·표본 성공 전투의 입력 기록: `replays/`(`PReplay.replay`로 상태 해시 대조). OS 간 일치는 이번에 검증하지 않았다.

## 5. 관찰 결과

### 5-2. 보스(실험실 프리셋 빌드)

| 시나리오 | 프로필 | N | 승 | 패 | 시간초과 | 정체 | 오류 | 승률(Wilson 95%) | 승리 시간 중앙/p90(초) | 패배 생존 중앙(초) | 보스 남은 체력 평균 | 받은 피해 평균 | 피격 수 | 회피 평균(거리) | 차단 | 누름 거절 | Q/E | 피해 출처(유효 합) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| boss_warden | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.6 / 31.6 (N<10: p90 불안정) | - | 0 | 30.0 | 5 | 6.3 (118.7) | 10 | 0 | 9/0 | boss_breach 90 |
| boss_warden | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.4 / 32.4 (N<10: p90 불안정) | - | 0 | 6.0 | 1 | 6.0 (79.1) | 3 | 0 | 9/0 | boss_breach 18 |
| boss_warden | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.9 / 32.9 (N<10: p90 불안정) | - | 0 | 6.0 | 1 | 5.0 (76.3) | 4 | 0 | 9/0 | boss_breach 18 |
| boss_warden | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.0 / 31.0 (N<10: p90 불안정) | - | 0 | 5.3 | 1 | 5.0 (112.0) | 6 | 82 | 9/0 | boss_bsweep 16 |
| boss_matriarch | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 50.7 / 50.7 (N<10: p90 불안정) | - | 0 | 82.3 | 24 | 11.0 (141.6) | 8 | 0 | 9/6 | boss_ring 144, zone 61, boss_spore_shot 42 |
| boss_matriarch | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 56.5 / 56.5 (N<10: p90 불안정) | - | 0 | 63.7 | 17 | 10.7 (85.2) | 6 | 0 | 11/5 | boss_ring 128, zone 35, boss_spore_shot 28 |
| boss_matriarch | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 63.8 / 63.8 (N<10: p90 불안정) | - | 0 | 68.0 | 17 | 13.3 (81.9) | 10 | 0 | 11/3 | boss_ring 160, zone 30, boss_spore_shot 14 |
| boss_matriarch | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 51.2 / 51.2 (N<10: p90 불안정) | - | 0 | 63.3 | 12 | 9.7 (89.4) | 15 | 359 | 10/4 | boss_ring 176, boss_spore_shot 14 |
| boss_behemoth | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 29.2 / 29.2 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 4.0 (148.4) | 3 | 0 | 6/3 | - |
| boss_behemoth | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 29.6 / 29.6 (N<10: p90 불안정) | - | 0 | 9.3 | 3 | 3.3 (71.2) | 1 | 0 | 6/2 | boss_rockfall 18, boss_rubble 10 |
| boss_behemoth | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 27.4 / 27.4 (N<10: p90 불안정) | - | 0 | 3.3 | 2 | 3.7 (61.3) | 3 | 0 | 6/1 | boss_rubble 10 |
| boss_behemoth | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 28.0 / 28.0 (N<10: p90 불안정) | - | 0 | 20.3 | 4 | 4.7 (103.8) | 7 | 103 | 6/3 | boss_rockfall 36, boss_burrow 20, boss_rubble 5 |
| boss_stalker | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.3 / 31.3 (N<10: p90 불안정) | - | 0 | 20.0 | 4 | 8.0 (133.0) | 8 | 0 | 9/0 | boss_dash 36, boss_icepath 24 |
| boss_stalker | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.4 / 30.4 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 7.7 (75.3) | 0 | 0 | 7/0 | - |
| boss_stalker | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 34.4 / 34.4 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 8.0 (74.7) | 3 | 0 | 9/0 | - |
| boss_stalker | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 32.8 / 32.8 (N<10: p90 불안정) | - | 0 | 31.7 | 8 | 6.3 (101.4) | 6 | 91 | 9/0 | boss_icepath 84, boss_icebolt 11 |
| boss_hunt_king | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 28.4 / 28.4 (N<10: p90 불안정) | - | 0 | 6.0 | 1 | 2.3 (139.6) | 5 | 0 | 7/3 | boss_dash 18 |
| boss_hunt_king | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.0 / 30.0 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 3.0 (84.5) | 1 | 0 | 8/2 | - |
| boss_hunt_king | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 28.8 / 28.8 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 1.7 (94.4) | 0 | 0 | 7/1 | - |
| boss_hunt_king | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 27.6 / 27.6 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 2.3 (131.7) | 1 | 34 | 6/1 | - |
| boss_executor | novice | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.6 / 31.6 (N<10: p90 불안정) | - | 0 | 7.3 | 1 | 3.0 (91.8) | 4 | 0 | 8/5 | boss_slash 22 |
| boss_executor | regular | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 31.5 / 31.5 (N<10: p90 불안정) | - | 0 | 22.0 | 3 | 3.0 (70.0) | 0 | 0 | 6/4 | boss_slash 66 |
| boss_executor | skilled | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.8 / 30.8 (N<10: p90 불안정) | - | 0 | 0.0 | 0 | 2.7 (70.0) | 0 | 0 | 8/3 | - |
| boss_executor | balanced | 3 | 3 | 0 | 0 | 0 | 0 | 3/3 = 100% [44%, 100%] | 30.4 / 30.4 (N<10: p90 불안정) | - | 0 | 7.3 | 1 | 3.0 (87.9) | 5 | 31 | 6/4 | boss_slash 22 |

### 5-3. seed별 짝(성공·실패가 바뀐 짝 보존)

| 시나리오 | 게임 seed | novice | regular | skilled | balanced |
|---|---|---|---|---|---|
| boss_warden | 1 | won 31.6s hp79 보스0 | won 34.0s hp100 보스0 | won 32.2s hp100 보스0 | won 31.0s hp84 보스0 |
| boss_warden | 2 | won 31.6s hp97 보스0 | won 30.7s hp100 보스0 | won 32.9s hp100 보스0 | won 30.8s hp100 보스0 |
| boss_warden | 3 | won 34.4s hp94 보스0 | won 32.4s hp100 보스0 | won 33.2s hp82 보스0 | won 31.2s hp100 보스0 |
| boss_matriarch | 1 | won 44.5s hp49 보스0 | won 61.2s hp25 보스0 | won 66.3s hp26 보스0 | won 51.2s hp53 보스0 |
| boss_matriarch | 2 | won 50.9s hp61 보스0 | won 50.5s hp86 보스0 | won 59.0s hp83 보스0 | won 49.1s hp51 보스0 |
| boss_matriarch | 3 | won 50.7s hp18 보스0 | won 56.5s hp53 보스0 | won 63.8s hp62 보스0 | won 52.3s hp66 보스0 |
| boss_behemoth | 1 | won 29.5s hp100 보스0 | won 31.7s hp95 보스0 | won 27.4s hp100 보스0 | won 28.0s hp77 보스0 |
| boss_behemoth | 2 | won 28.6s hp100 보스0 | won 29.6s hp100 보스0 | won 28.5s hp100 보스0 | won 27.2s hp100 보스0 |
| boss_behemoth | 3 | won 29.2s hp100 보스0 | won 27.8s hp97 보스0 | won 26.1s hp100 보스0 | won 28.6s hp62 보스0 |
| boss_stalker | 1 | won 32.8s hp100 보스0 | won 30.4s hp100 보스0 | won 34.4s hp100 보스0 | won 32.8s hp88 보스0 |
| boss_stalker | 2 | won 31.3s hp70 보스0 | won 30.4s hp100 보스0 | won 32.0s hp100 보스0 | won 31.1s hp77 보스0 |
| boss_stalker | 3 | won 31.3s hp82 보스0 | won 37.1s hp100 보스0 | won 35.6s hp100 보스0 | won 33.5s hp94 보스0 |
| boss_hunt_king | 1 | won 26.8s hp82 보스0 | won 30.2s hp100 보스0 | won 28.8s hp100 보스0 | won 27.1s hp100 보스0 |
| boss_hunt_king | 2 | won 28.4s hp100 보스0 | won 29.2s hp100 보스0 | won 32.0s hp100 보스0 | won 30.3s hp100 보스0 |
| boss_hunt_king | 3 | won 30.2s hp100 보스0 | won 30.0s hp100 보스0 | won 27.7s hp100 보스0 | won 27.6s hp100 보스0 |
| boss_executor | 1 | won 31.6s hp100 보스0 | won 28.1s hp100 보스0 | won 30.8s hp100 보스0 | won 30.4s hp100 보스0 |
| boss_executor | 2 | won 31.6s hp100 보스0 | won 31.5s hp100 보스0 | won 30.1s hp100 보스0 | won 30.4s hp93 보스0 |
| boss_executor | 3 | won 28.4s hp100 보스0 | won 31.7s hp56 보스0 | won 31.7s hp100 보스0 | won 30.5s hp100 보스0 |

### 5-4. 피격 태그(당시 조건, 중복 허용 — 원인 확정 아님) · 거절된 타격 · 공격 관측

| 시나리오 | 프로필 | 피격 | not_perceived | perceived_no_input | dodge_rejected_cooldown | dodge_blocked_terrain | after_dodge_025 | hit_by_other_while_escaping | walking_out | overlap | unclassified | 거절(무적/보호) | 공격 관측: 시작/고정/실행/명중/예고 중 사망/취소 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| boss_warden | novice | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 | 1 | 0/0 | 22/22/22/5/0/0 |
| boss_warden | regular | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0/0 | 23/23/23/1/0/0 |
| boss_warden | skilled | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0/0 | 22/21/21/1/1/0 |
| boss_warden | balanced | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 21/21/21/1/0/0 |
| boss_matriarch | novice | 24 | 10 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 13 | 0/0 | 34/28/30/12/3/1 |
| boss_matriarch | regular | 17 | 6 | 0 | 0 | 1 | 1 | 0 | 1 | 1 | 10 | 1/0 | 39/33/36/10/3/0 |
| boss_matriarch | skilled | 17 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 12 | 0/0 | 45/38/42/11/3/0 |
| boss_matriarch | balanced | 12 | 0 | 0 | 9 | 1 | 0 | 0 | 0 | 0 | 3 | 0/1 | 35/30/33/12/2/0 |
| boss_behemoth | novice | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 15/14/14/0/1/0 |
| boss_behemoth | regular | 3 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 0/7 | 15/15/14/2/1/0 |
| boss_behemoth | skilled | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0/0 | 15/14/13/2/2/0 |
| boss_behemoth | balanced | 4 | 0 | 0 | 3 | 1 | 0 | 0 | 0 | 0 | 1 | 4/67 | 14/14/14/4/0/0 |
| boss_stalker | novice | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 0/0 | 25/24/24/4/1/0 |
| boss_stalker | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 27/26/26/0/1/0 |
| boss_stalker | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 27/26/26/0/1/0 |
| boss_stalker | balanced | 8 | 0 | 0 | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 0/0 | 24/23/23/8/1/0 |
| boss_hunt_king | novice | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0/0 | 16/14/14/1/2/0 |
| boss_hunt_king | regular | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1/0 | 17/17/17/0/0/0 |
| boss_hunt_king | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 16/16/16/0/0/0 |
| boss_hunt_king | balanced | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 14/14/14/0/0/0 |
| boss_executor | novice | 1 | 0 | 0 | 0 | 1 | 1 | 0 | 1 | 0 | 0 | 0/0 | 17/14/14/1/3/0 |
| boss_executor | regular | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 0 | 0/0 | 17/15/14/3/3/0 |
| boss_executor | skilled | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 16/15/15/0/1/0 |
| boss_executor | balanced | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0/0 | 16/14/14/1/2/0 |

### 5-5. 지연(판단 간격·인식 지연·실제 최초 입력 지연)

| 시나리오 | 프로필 | 판단 간격 | 인식 지연 평균(위협 수) | 최초 입력 지연 평균 / 판별 p50 중앙 / p90 중앙 (ms, 안에 있던 위협 수) | 누름 짧음/중간/김 | 봇 난수 소비 |
|---|---|---|---|---|---|---|
| boss_warden | novice | 150ms | 436.7 (22) | 417.6 / 400.0 / 575.0 (37) | 0/0/19 | 106 |
| boss_warden | regular | 100ms | 278.6 (23) | 468.7 / 391.7 / 633.3 (34) | 12/6/0 | 136 |
| boss_warden | skilled | 50ms | 170.5 (22) | 309.6 / 291.7 / 375.0 (26) | 10/5/0 | 214 |
| boss_warden | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_matriarch | novice | 150ms | 455.0 (52) | 472.5 / 466.7 / 608.3 (42) | 0/0/33 | 166 |
| boss_matriarch | regular | 100ms | 278.8 (60) | 374.1 / 316.7 / 458.3 (54) | 23/2/7 | 306 |
| boss_matriarch | skilled | 50ms | 167.5 (68) | 212.8 / 191.7 / 383.3 (56) | 29/3/8 | 649 |
| boss_matriarch | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_behemoth | novice | 150ms | 454.4 (23) | 495.8 / 433.3 / 541.7 (12) | 0/0/12 | 43 |
| boss_behemoth | regular | 100ms | 267.4 (24) | 325.0 / 275.0 / 366.7 (20) | 9/1/0 | 92 |
| boss_behemoth | skilled | 50ms | 173.9 (22) | 285.8 / 191.7 / 383.3 (20) | 10/1/0 | 143 |
| boss_behemoth | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_stalker | novice | 150ms | 446.6 (32) | 540.6 / 541.7 / 583.3 (24) | 0/0/24 | 103 |
| boss_stalker | regular | 100ms | 289.8 (31) | 355.7 / 366.7 / 416.7 (25) | 20/3/0 | 147 |
| boss_stalker | skilled | 50ms | 174.2 (33) | 331.6 / 266.7 / 375.0 (37) | 19/5/0 | 392 |
| boss_stalker | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_hunt_king | novice | 150ms | 462.5 (16) | 497.3 / 491.7 / 491.7 (6) | 0/0/7 | 29 |
| boss_hunt_king | regular | 100ms | 271.6 (17) | 315.8 / 391.7 / 391.7 (9) | 3/5/1 | 73 |
| boss_hunt_king | skilled | 50ms | 161.0 (16) | 251.7 / 291.7 / 291.7 (5) | 2/3/0 | 78 |
| boss_hunt_king | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |
| boss_executor | novice | 150ms | 463.7 (17) | 486.7 / 433.3 / 591.7 (17) | 0/0/9 | 62 |
| boss_executor | regular | 100ms | 266.7 (17) | 411.9 / 383.3 / 400.0 (14) | 9/0/0 | 91 |
| boss_executor | skilled | 50ms | 166.7 (16) | 334.4 / 283.3 / 383.3 (16) | 8/0/0 | 169 |
| boss_executor | balanced | 5스텝 | (기존 정책: 지연 모델 없음) | - | - | - |

### 5-6. 준 피해(출처별, PStats 보유 시간 DPS 재사용)

| 시나리오 | 프로필 | 총피해 평균 | 전체 전투시간 DPS(총피해/총전투시간) | 출처별 유효 피해 합(보유시간 DPS) |
|---|---|---|---|---|
| boss_warden | novice | 2400 | 73.9 | weapon:blades 2731(28.0/s), weapon:ember 2448(25.1/s), weapon:sword 2021(20.7/s) |
| boss_warden | regular | 2400 | 74.2 | weapon:blades 2733(28.1/s), weapon:ember 2533(26.1/s), weapon:sword 1935(19.9/s) |
| boss_warden | skilled | 2400 | 73.3 | weapon:blades 2604(26.5/s), weapon:ember 2602(26.5/s), weapon:sword 1993(20.3/s) |
| boss_warden | balanced | 2400 | 77.5 | weapon:blades 2673(28.7/s), weapon:ember 2418(26.0/s), weapon:sword 2109(22.7/s) |
| boss_matriarch | novice | 2492 | 51.2 | weapon:ember 3519(24.1/s), weapon:blades 2526(17.3/s), weapon:sword 1333(9.1/s), skill:gust 100(0.7/s) |
| boss_matriarch | regular | 2510 | 44.8 | weapon:ember 4017(23.9/s), weapon:blades 2215(13.2/s), weapon:sword 1218(7.2/s), skill:gust 80(0.5/s) |
| boss_matriarch | skilled | 2492 | 39.5 | weapon:ember 3947(20.9/s), weapon:blades 2202(11.6/s), weapon:sword 1276(6.7/s), skill:gust 50(0.4/s) |
| boss_matriarch | balanced | 2492 | 49.0 | weapon:ember 3434(22.5/s), weapon:blades 2446(16.0/s), weapon:sword 1520(10.0/s), skill:gust 75(0.5/s) |
| boss_behemoth | novice | 5070 | 174.3 | weapon:ember 10590(121.3/s), weapon:sword 2346(26.9/s), weapon:blades 2230(25.5/s), common:frost 24(0.4/s), skill:gust 20(0.7/s) |
| boss_behemoth | regular | 5053 | 170.3 | weapon:ember 10705(120.1/s), weapon:sword 2230(25.0/s), weapon:blades 2207(24.8/s), common:frost 16(0.5/s) |
| boss_behemoth | skilled | 5023 | 183.9 | weapon:ember 10367(126.4/s), weapon:blades 2362(28.8/s), weapon:sword 2333(28.5/s), common:frost 8(0.3/s) |
| boss_behemoth | balanced | 5070 | 181.6 | weapon:ember 10022(119.7/s), weapon:sword 2646(31.6/s), weapon:blades 2463(29.4/s), common:frost 80(1.0/s) |
| boss_stalker | novice | 5000 | 157.2 | weapon:ember 9300(97.6/s), weapon:sword 3067(32.2/s), weapon:blades 2633(27.6/s) |
| boss_stalker | regular | 5000 | 153.3 | weapon:ember 9626(98.3/s), weapon:sword 2868(29.3/s), weapon:blades 2507(25.6/s) |
| boss_stalker | skilled | 5000 | 147.1 | weapon:ember 9380(92.0/s), weapon:sword 3002(29.4/s), weapon:blades 2619(25.7/s) |
| boss_stalker | balanced | 5000 | 154.1 | weapon:ember 9027(92.7/s), weapon:sword 3287(33.7/s), weapon:blades 2686(27.6/s) |
| boss_hunt_king | novice | 7060 | 248.2 | weapon:ember 12753(149.3/s), weapon:blades 4136(48.4/s), weapon:sword 3860(45.2/s), dot:burn@blades 295(3.5/s), dot:burn@sword 111(1.3/s) |
| boss_hunt_king | regular | 7060 | 237.2 | weapon:ember 12412(138.8/s), weapon:sword 4145(46.4/s), weapon:blades 4115(46.0/s), dot:burn@blades 290(3.2/s), dot:burn@sword 121(1.4/s) |
| boss_hunt_king | skilled | 7020 | 237.9 | weapon:ember 12374(139.8/s), weapon:blades 4210(47.6/s), weapon:sword 4053(45.8/s), dot:burn@blades 243(2.7/s), dot:burn@sword 155(1.8/s) |
| boss_hunt_king | balanced | 7040 | 248.6 | weapon:ember 11946(140.5/s), weapon:blades 4356(51.2/s), weapon:sword 4346(51.1/s), dot:burn@blades 289(3.4/s), dot:burn@sword 101(1.2/s) |
| boss_executor | novice | 7200 | 236.1 | weapon:ember 14186(154.9/s), weapon:blades 3706(40.5/s), weapon:sword 3163(34.5/s), dot:burn@blades 307(3.3/s), dot:burn@sword 81(0.9/s) |
| boss_executor | regular | 7160 | 235.3 | weapon:ember 14270(156.3/s), weapon:blades 3457(37.9/s), weapon:sword 3274(35.9/s), dot:burn@blades 300(3.3/s), dot:burn@sword 88(1.0/s) |
| boss_executor | skilled | 7120 | 230.6 | weapon:ember 13815(149.2/s), weapon:blades 3672(39.7/s), weapon:sword 3456(37.3/s), dot:burn@blades 299(3.2/s), dot:burn@sword 82(0.9/s) |
| boss_executor | balanced | 7123 | 234.0 | weapon:ember 14176(155.3/s), weapon:blades 3535(38.7/s), weapon:sword 3245(35.5/s), dot:burn@blades 290(3.2/s), dot:burn@sword 91(1.0/s) |

## 6. 사람 확인 필요

- 프로필 시험값(지연·후보 수·오차)과 공통 규칙은 실측 인구 통계가 아니다. 검증 메뉴의 '이번 전투 입력 기록'으로 사람 기록 5~10회를 모아 전투 시간·피해 출처·회피 빈도/거리·Q/E와 비교해야 한다(**사람 보정 미완료**).
- 실력 순서와 결과가 뒤집힌 seed·시나리오는 관측/판단/기술 적합성 원인 조사 대상이지 숨길 결과가 아니다. 이 표로 게임 수치를 바꾸지 않는다(원인 후보·조정 대상만 보고).
- 태그는 '다른 방향이면 피했다'를 뜻하지 않는다. 그런 결론은 해당 입력 기록을 재생해 대안 입력을 따로 검사해야 한다.

## 7. 관찰(사람이 씀 — 배치 도구가 보고서를 다시 만들면 이 절은 사라지므로 `docs/BOT_FRAMEWORK.md` §8-1과 `docs/BOSSES.md` '봇 관측'에도 같은 내용) — **사람 보정 미완료**

배경: 관측 계층이 옛 보스 3종의 예고만 담던 상태(observe-1)에서는 실력 봇이 신규 보스 6종에 17~28초 안에 전패했다(예고를 못 보고 낙석·볼트·절단선·빙판 위에 서 있었음, `tools/stop3_skill.gd` 관찰). observe-2에서 `render.gd draw_boss3_telegraphs`와 같은 수치의 예고·빙판·잔해·투사체를 스냅샷에 넣은 뒤(봇 규칙·프로필 값·게임 수치 변경 없음) 같은 봇이 이 배치(막에 맞는 관문 프리셋 stage1/2/3, 체력 세트 hi 2400/5000/7000, 보스 seed 1·2·3)에서 **72/72 승**이다. 따라서 이전 전패의 원인은 봇의 판단이 아니라 관측 누락이었다.

이길 수 없는 보스: **이 배치에서는 없다**(6종 × 4프로필 × 3seed 전승, 승리 시간 27~66초, 패배·시간초과·정체 0). 단 N=3이고 빌드가 관문 시점보다 강한 실험실 프리셋이므로 "사람이 이긴다"는 뜻이 아니고, 시작 빌드(Lv1)나 회차 실제 성장으로는 재지 않았다.

보스별 관찰(피격 출처·태그·패턴 실행 수는 §5-2·§5-4, 12전투 합):

| 보스 | 실행된 패턴(12전투 합) | 실력 봇이 맞은 것 | 원인 후보(태그·기하) | 범용 봇이 못 하는 것 |
|---|---|---|---|---|
| 성문 파수장 | bolts 39 · breach 38 · guard 11 | novice 돌파 5회(36/18/36), regular·skilled 돌파 1회씩(18) | 전부 `walking_out`: 돌파 통로(폭 108)를 걸어서 벗어나다 맞음 — 확정 0.4초 뒤 780/s 돌진은 lock 잔여 추정 0.15초보다 빠르고, novice는 인식 350~550ms | 석궁 줄 사이·방패 옆·뒤로 돌기(boss.guard는 보이지만 쓰지 않음). 볼트(3발)는 한 번도 맞지 않았다 |
| 포자 어미 | shot 76 · ring 56 · summon 22 | 피격 24/17/17(novice/regular/skilled): 고리 9/8/10, 잔류 구름 12/7/6, 포자 탄 3/2/1. 받은 피해 63~82, 승리 51~64초(가장 오래 걸림) | 고리: 준비 부채꼴(r340)은 150px 탐색으로 못 벗어나 '가장 트인 방향'(보스 반대쪽)으로 걷다 확산 띠(250/s)에 잡힘(`unclassified` 13/10/12). 구름: 착탄 뒤 생기는 `zone:spore`가 새 attack_id라 인식 지연 안에 밟음(`not_perceived` 10/6/5). balanced(기준 행)는 인식 지연이 없어 구름 피격 0, 대신 회피 재사용 거절 9 | **빈 구간으로 들어가기**(설계 답). 봇은 부채꼴 밖으로만 나가려 한다. 잔류 구름은 인식 뒤엔 피한다(`approach`의 활성 장판 회피) |
| 굴착 거수 | rockfall 36 · burrow 24 · summon 13 | novice 0, regular 잔해 2·낙석 1(5/5/18), skilled 잔해 2(10) | 낙석 원 3개는 순번·남은 초로 보여 걸어서 벗어나고, 잔해(`zone:rubble`)는 새 id라 인식 전 한 틱(5) 밟음. 굴착 돌파 피격 0 | 없음(출구 검사 ≥4는 게임 보장, 봇은 그 방향을 고르지 않아도 됐다). 폭탄 운반체 호위(최대 동시 3)는 맞지 않음 |
| 서리 추적자 | bolt 42 · dash 32 · icepath 29 | novice 얼음길 2·돌진 2(12/30/18, 전부 `walking_out`), regular·skilled 0 | 빙판 최대 동시 33개(`harm=slow`, 회피 대상 아님) 위에서 60%로 걷다 novice만 늦음. balanced는 얼음길 7회 맞음(회피 재사용 거절 4·회피 직후 4) | 빙판 위임을 감안한 걷기 판단(걸어서 벗어나기 추정이 기본 속도 기준). 실력 봇은 옆 이동→돌진(sidestep에 예고 없음)에 맞지 않았다 |
| 핏빛 사냥왕 | dash 39 · claw 24 · summon 12 | novice 돌진 1회(18), 나머지 0 | 재조준(`:dash2`, 표시된 '방향 고정 n초 뒤')이 같은 공격의 부분으로 이어져 재인식 없음 → 둘째 돌진 피격 0 | 없음(호위 늑대 최대 동시 3 포함 피격 0). 발톱(r170·170°)은 뒤로 도는 대신 밖으로 나가서 피함 |
| 종말의 집행관 | slash 35 · guard 26 · summon 17 | novice 절단 1(22), regular 절단 3(22/44), skilled 0 | 전부 `walking_out`: 세로 통로(폭 80)를 걸어서 벗어나다 2번 선(1번이 떨어질 때 내 x에 고정, 0.5+0.3초)에 맞음. novice는 회피 재사용·지형 차단 1 | 좌우 한 걸음의 '충분한' 거리 판단(폭 80 + 여유 6 → 46px 이상 걸어야 하는데 고정 0.8초 안에 인식 200~550ms). 방어 자세(boss.guard) 옆·뒤 공격은 하지 않음 |

지연(§5-5): 인식 지연 평균 novice 437~464 / regular 267~290 / skilled 161~174ms(프로필 범위 그대로), 실제 최초 입력 지연 평균 novice 418~541 / regular 316~469 / skilled 213~334ms. 포자 어미에서 위협 수(52/60/68)가 가장 많고 봇 난수 소비도 가장 많다(166/306/649).

실력 순서: 받은 피해는 대체로 novice ≥ regular ≥ skilled(파수장 30/6/6, 굴착 0/9/3은 역전, 서리 20/0/0, 사냥왕 6/0/0, 집행관 7/22/0은 역전, 포자 82/64/68). 역전 칸(굴착 novice 0 < regular 9, 집행관 regular 22 > novice 7)은 N=3 표본·seed 짝 차이이며 숨길 결과가 아니다(§6).

수치 조정 없음: 이 표로 보스·봇 수치를 바꾸지 않았다. 사람 비교 우선 후보는 포자 어미(고리 빈 구간·잔류 구름)와 집행관 절단선(2번 선 고정 규칙의 가독성)이다.
