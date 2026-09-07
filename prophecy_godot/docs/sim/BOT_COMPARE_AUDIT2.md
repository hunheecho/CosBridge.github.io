# 검수 2(godot-audit-8dfcbd1) 수정 전후 같은 조건 비교 (BOT_COMPARE_AUDIT2)

수정 전 = 8dfcbd1(observe-2 · skillbot-0.1, run `audit2_before`, 별도 worktree에서 실행), 수정 후 = 이 커밋(observe-3 · skillbot-0.2, run `audit2_after`). 같은 시나리오 ['baseline_wolf25', 'ranged_mix', 'zone_mix', 'boss_guardian', 'boss_warden', 'boss_matriarch', 'boss_stalker'] × 프로필 ['novice', 'regular', 'skilled', 'balanced'] × 게임 시드 [1, 2, 3, 4, 5](보스 [1, 2, 3]), 봇 시드 = 게임 시드, 같은 엔진·OS·데이터. 게임 수치·프로필 값 변경 없음. **가상 조작 모델 · 사람 보정 미완료** — 봇 승패는 밸런스 승인이 아니다. 기존 보고서(BOT_COMPARE·BOT_COMPARE_BOSS3)의 수치는 재사용하지 않고 양쪽 모두 새로 실행했다.

수정 내용: ① 서로 다른 장판·발사자 없는 투사체는 인식 지연을 상속하지 않는다(같은 공격 인스턴스 e<id>#<n>의 부분만 상속) ② 투사체 id를 발사 시점에 고정(발사자의 다음 공격·형제 투사체 제거에도 불변, 피격 기록도 발사 시점 공격) ③ 배치 캐시 키에 코드 내용 해시·규칙/관측 버전 추가, 식별 불가면 재개 거부.

| 시나리오 | 봇 | N | 승(전) → 승(후) | 시간초과(전→후) | 평균 받은 피해(전→후) | 평균 시뮬 초(전→후) | 최초 입력 지연 ms(전→후) | 피격 태그 상위(전) | 피격 태그 상위(후) |
|---|---|---|---|---|---|---|---|---|---|
| baseline_wolf25 | novice | 5 | 5 → 5 | 0 → 0 | 67 → 67 | 18.8 → 18.8 | 518 → 518 | not_perceived 24 · after_dodge_025 3 · hit_by_other_while_escaping 2 · perceived_no_input 2 | not_perceived 24 · after_dodge_025 3 · hit_by_other_while_escaping 2 · perceived_no_input 2 |
| baseline_wolf25 | regular | 5 | 5 → 5 | 0 → 0 | 17 → 17 | 18.4 → 18.4 | 337 → 337 | perceived_no_input 3 · walking_out 2 · overlap 2 · hit_by_other_while_escaping 2 | perceived_no_input 3 · walking_out 2 · overlap 2 · hit_by_other_while_escaping 2 |
| baseline_wolf25 | skilled | 5 | 5 → 5 | 0 → 0 | 5 → 5 | 20.8 → 20.8 | 251 → 251 | walking_out 2 · overlap 1 | walking_out 2 · overlap 1 |
| baseline_wolf25 | balanced | 5 | 3 → 3 | 0 → 0 | 74 → 74 | 17.8 → 17.8 | - → - | unclassified 19 · dodge_rejected_cooldown 12 · dodge_blocked_terrain 3 | unclassified 19 · dodge_rejected_cooldown 12 · dodge_blocked_terrain 3 |
| ranged_mix | novice | 5 | 0 → 1 | 0 → 0 | 100 → 99 | 48.2 → 56.7 | 552 → 536 | not_perceived 16 · walking_out 16 · hit_by_other_while_escaping 13 · overlap 12 | overlap 16 · walking_out 14 · not_perceived 13 · hit_by_other_while_escaping 12 |
| ranged_mix | regular | 5 | 1 → 3 | 0 → 0 | 98 → 84 | 115.7 → 117.0 | 408 → 407 | walking_out 24 · overlap 23 · hit_by_other_while_escaping 8 · unclassified 7 | walking_out 21 · overlap 19 · hit_by_other_while_escaping 5 · unclassified 5 |
| ranged_mix | skilled | 5 | 2 → 2 | 2 → 2 | 51 → 64 | 217.0 → 221.6 | 368 → 366 | walking_out 15 · overlap 12 · unclassified 4 · hit_by_other_while_escaping 3 | overlap 20 · walking_out 20 · hit_by_other_while_escaping 5 · unclassified 3 |
| ranged_mix | balanced | 5 | 0 → 0 | 0 → 0 | 100 → 100 | 64.9 → 64.9 | - → - | dodge_rejected_cooldown 36 · unclassified 6 · dodge_blocked_terrain 3 · after_dodge_025 2 | dodge_rejected_cooldown 36 · unclassified 6 · dodge_blocked_terrain 3 · after_dodge_025 2 |
| zone_mix | novice | 5 | 0 → 0 | 0 → 0 | 100 → 100 | 74.2 → 53.4 | 506 → 516 | overlap 22 · hit_by_other_while_escaping 20 · not_perceived 15 · walking_out 15 | not_perceived 19 · hit_by_other_while_escaping 16 · overlap 13 · unclassified 13 |
| zone_mix | regular | 5 | 0 → 0 | 0 → 0 | 100 → 100 | 159.4 → 102.8 | 372 → 388 | walking_out 22 · unclassified 21 · overlap 20 · hit_by_other_while_escaping 10 | unclassified 33 · walking_out 19 · overlap 14 · hit_by_other_while_escaping 8 |
| zone_mix | skilled | 5 | 1 → 0 | 3 → 1 | 53 → 98 | 207.6 → 187.4 | 334 → 346 | walking_out 18 · overlap 14 · unclassified 6 · after_dodge_025 2 | unclassified 32 · walking_out 22 · overlap 15 · after_dodge_025 6 |
| zone_mix | balanced | 5 | 2 → 2 | 1 → 1 | 79 → 79 | 153.4 → 153.4 | - → - | dodge_rejected_cooldown 39 · after_dodge_025 3 · dodge_blocked_terrain 3 · unclassified 1 | dodge_rejected_cooldown 39 · after_dodge_025 3 · dodge_blocked_terrain 3 · unclassified 1 |
| boss_guardian | novice | 3 | 3 → 3 | 0 → 0 | 7 → 0 | 30.4 → 30.1 | 406 → 536 | walking_out 2 | - |
| boss_guardian | regular | 3 | 3 → 3 | 0 → 0 | 0 → 0 | 30.5 → 29.2 | 282 → 268 | - | - |
| boss_guardian | skilled | 3 | 3 → 3 | 0 → 0 | 0 → 0 | 31.0 → 30.8 | 325 → 270 | - | - |
| boss_guardian | balanced | 3 | 3 → 3 | 0 → 0 | 0 → 0 | 30.1 → 30.1 | - → - | - | - |
| boss_warden | novice | 3 | 3 → 3 | 0 → 0 | 30 → 30 | 32.5 → 33.5 | 407 → 409 | walking_out 4 · unclassified 1 | walking_out 5 |
| boss_warden | regular | 3 | 3 → 3 | 0 → 0 | 6 → 6 | 32.4 → 32.4 | 460 → 460 | walking_out 1 | walking_out 1 |
| boss_warden | skilled | 3 | 3 → 3 | 0 → 0 | 6 → 6 | 32.7 → 32.7 | 313 → 313 | walking_out 1 | walking_out 1 |
| boss_warden | balanced | 3 | 3 → 3 | 0 → 0 | 5 → 5 | 31.0 → 31.0 | - → - | dodge_rejected_cooldown 1 | dodge_rejected_cooldown 1 |
| boss_matriarch | novice | 3 | 3 → 3 | 0 → 0 | 82 → 71 | 48.7 → 47.8 | 471 → 445 | unclassified 13 · not_perceived 10 · walking_out 1 | unclassified 12 · not_perceived 9 |
| boss_matriarch | regular | 3 | 3 → 3 | 0 → 0 | 64 → 53 | 56.1 → 54.4 | 372 → 332 | unclassified 10 · not_perceived 6 · after_dodge_025 1 · dodge_blocked_terrain 1 | unclassified 9 · not_perceived 5 · after_dodge_025 1 · dodge_blocked_terrain 1 |
| boss_matriarch | skilled | 3 | 3 → 3 | 0 → 0 | 68 → 56 | 63.1 → 56.9 | 212 → 220 | unclassified 12 · not_perceived 5 | unclassified 12 · not_perceived 5 · walking_out 1 |
| boss_matriarch | balanced | 3 | 3 → 3 | 0 → 0 | 63 → 63 | 50.9 → 50.9 | - → - | dodge_rejected_cooldown 9 · unclassified 3 · dodge_blocked_terrain 1 | dodge_rejected_cooldown 9 · unclassified 3 · dodge_blocked_terrain 1 |
| boss_stalker | novice | 3 | 3 → 3 | 0 → 0 | 20 → 4 | 31.8 → 32.0 | 543 → 588 | walking_out 4 | walking_out 1 |
| boss_stalker | regular | 3 | 3 → 3 | 0 → 0 | 0 → 0 | 32.6 → 32.6 | 356 → 348 | - | - |
| boss_stalker | skilled | 3 | 3 → 3 | 0 → 0 | 0 → 8 | 34.0 → 32.7 | 332 → 332 | - | walking_out 2 |
| boss_stalker | balanced | 3 | 3 → 3 | 0 → 0 | 32 → 32 | 32.5 → 32.5 | - → - | dodge_rejected_cooldown 4 · after_dodge_025 4 | dodge_rejected_cooldown 4 · after_dodge_025 4 |

## 요약

| 봇 | 승(전) | 승(후) | 전투 수 |
|---|---|---|---|
| novice | 17 | 18 | 27 |
| regular | 18 | 20 | 27 |
| skilled | 20 | 19 | 27 |
| balanced | 17 | 17 | 27 |

## 행 단위 변화 (54/108 행이 결과·피해·시간 중 하나라도 다름)

| 시나리오 | 봇 | 시드 | 결과(전→후) | 받은 피해(전→후) | 시뮬 초(전→후) | 태그(전) | 태그(후) |
|---|---|---|---|---|---|---|---|
| boss_guardian | novice | 1 | won → won | 0 → 0 | 28.8 → 28.0 | - | - |
| boss_guardian | novice | 2 | won → won | 10 → 0 | 32.4 → 32.3 | walking_out 1 | - |
| boss_guardian | novice | 3 | won → won | 10 → 0 | 30.2 → 30.1 | walking_out 1 | - |
| boss_guardian | regular | 1 | won → won | 0 → 0 | 27.6 → 27.2 | - | - |
| boss_guardian | regular | 2 | won → won | 0 → 0 | 32.9 → 33.2 | - | - |
| boss_guardian | regular | 3 | won → won | 0 → 0 | 31.0 → 27.3 | - | - |
| boss_guardian | skilled | 1 | won → won | 0 → 0 | 27.3 → 28.4 | - | - |
| boss_guardian | skilled | 2 | won → won | 0 → 0 | 36.0 → 33.6 | - | - |
| boss_guardian | skilled | 3 | won → won | 0 → 0 | 29.6 → 30.6 | - | - |
| boss_matriarch | novice | 2 | won → won | 69 → 47 | 50.9 → 46.8 | not_perceived 4 · unclassified 3 | not_perceived 3 · unclassified 2 |
| boss_matriarch | novice | 3 | won → won | 112 → 99 | 50.7 → 52.2 | unclassified 6 · not_perceived 3 · walking_out 1 | unclassified 6 · not_perceived 3 |
| boss_matriarch | regular | 1 | won → won | 90 → 74 | 61.2 → 57.1 | unclassified 5 · not_perceived 2 · after_dodge_025 1 · dodge_blocked_terrain 1 | unclassified 4 · not_perceived 2 · after_dodge_025 1 · dodge_blocked_terrain 1 |
| boss_matriarch | regular | 2 | won → won | 24 → 26 | 50.5 → 48.1 | not_perceived 2 · unclassified 1 | not_perceived 2 · unclassified 1 |
| boss_matriarch | regular | 3 | won → won | 77 → 59 | 56.5 → 58.1 | unclassified 4 · not_perceived 2 · overlap 1 · walking_out 1 | unclassified 4 · not_perceived 1 |
| boss_matriarch | skilled | 1 | won → won | 104 → 36 | 66.3 → 60.0 | unclassified 6 · not_perceived 2 | not_perceived 2 · unclassified 2 · walking_out 1 |
| boss_matriarch | skilled | 2 | won → won | 47 → 52 | 59.0 → 54.5 | unclassified 3 · not_perceived 2 | unclassified 4 · not_perceived 2 |
| boss_matriarch | skilled | 3 | won → won | 53 → 79 | 63.8 → 56.2 | unclassified 3 · not_perceived 1 | unclassified 6 · not_perceived 1 |
| boss_stalker | novice | 1 | won → won | 12 → 0 | 32.8 → 33.5 | walking_out 1 | - |
| boss_stalker | novice | 2 | won → won | 30 → 0 | 31.3 → 31.6 | walking_out 2 | - |
| boss_stalker | novice | 3 | won → won | 18 → 12 | 31.3 → 30.9 | walking_out 1 | walking_out 1 |
| boss_stalker | regular | 2 | won → won | 0 → 0 | 30.4 → 30.3 | - | - |
| boss_stalker | regular | 3 | won → won | 0 → 0 | 37.1 → 37.0 | - | - |
| boss_stalker | skilled | 1 | won → won | 0 → 12 | 34.4 → 32.0 | - | walking_out 1 |
| boss_stalker | skilled | 2 | won → won | 0 → 12 | 32.0 → 30.4 | - | walking_out 1 |
| boss_warden | novice | 1 | won → won | 36 → 36 | 31.6 → 34.5 | unclassified 1 · walking_out 1 | walking_out 2 |
| ranged_mix | novice | 1 | lost → won | 100 → 96 | 46.6 → 126.4 | after_dodge_025 3 · dodge_blocked_terrain 3 · hit_by_other_while_escaping 3 · not_perceived 3 | walking_out 4 · overlap 3 · after_dodge_025 2 · dodge_blocked_terrain 2 |
| ranged_mix | novice | 2 | lost → lost | 100 → 100 | 69.7 → 44.3 | overlap 5 · hit_by_other_while_escaping 4 · walking_out 4 · dodge_blocked_terrain 2 | overlap 6 · hit_by_other_while_escaping 4 · not_perceived 2 · perceived_no_input 2 |
| ranged_mix | novice | 3 | lost → lost | 100 → 100 | 61.7 → 49.2 | not_perceived 3 · walking_out 3 · hit_by_other_while_escaping 2 · perceived_no_input 1 | not_perceived 4 · perceived_no_input 2 · walking_out 2 · hit_by_other_while_escaping 1 |
| ranged_mix | novice | 5 | lost → lost | 100 → 100 | 39.8 → 40.6 | not_perceived 5 · perceived_no_input 2 · walking_out 2 · hit_by_other_while_escaping 1 | not_perceived 3 · hit_by_other_while_escaping 2 · perceived_no_input 2 · walking_out 2 |
| ranged_mix | regular | 1 | lost → won | 100 → 86 | 151.0 → 161.4 | overlap 6 · hit_by_other_while_escaping 3 · unclassified 3 · walking_out 3 | overlap 3 · walking_out 3 · hit_by_other_while_escaping 2 · unclassified 2 |
| ranged_mix | regular | 2 | won → won | 89 → 52 | 151.1 → 163.3 | walking_out 4 · overlap 3 · hit_by_other_while_escaping 2 · unclassified 1 | unclassified 2 · hit_by_other_while_escaping 1 · overlap 1 · walking_out 1 |
| ranged_mix | regular | 3 | lost → lost | 100 → 100 | 82.9 → 39.2 | overlap 4 · walking_out 4 · after_dodge_025 2 · hit_by_other_while_escaping 1 | overlap 5 · walking_out 4 · after_dodge_025 1 · dodge_blocked_terrain 1 |
| ranged_mix | regular | 4 | lost → lost | 100 → 100 | 47.3 → 42.5 | walking_out 7 · overlap 5 · hit_by_other_while_escaping 1 · unclassified 1 | walking_out 8 · overlap 4 · after_dodge_025 1 |
| ranged_mix | regular | 5 | lost → won | 100 → 84 | 146.0 → 178.8 | walking_out 6 · overlap 5 · dodge_blocked_terrain 1 · hit_by_other_while_escaping 1 | overlap 6 · walking_out 5 · hit_by_other_while_escaping 1 · perceived_no_input 1 |
| ranged_mix | skilled | 1 | won → timeout | 31 → 33 | 161.2 → 240.0 | walking_out 3 · overlap 2 · after_dodge_025 1 | overlap 3 · walking_out 3 |
| ranged_mix | skilled | 2 | won → won | 38 → 48 | 212.1 → 226.8 | overlap 2 · hit_by_other_while_escaping 1 · unclassified 1 · walking_out 1 | overlap 3 · walking_out 2 · hit_by_other_while_escaping 1 · unclassified 1 |
| ranged_mix | skilled | 3 | timeout → lost | 40 → 100 | 240.0 → 214.5 | walking_out 3 · overlap 2 | walking_out 8 · overlap 6 · unclassified 1 |
| ranged_mix | skilled | 4 | timeout → won | 48 → 52 | 240.0 → 186.8 | walking_out 4 | overlap 2 · walking_out 2 · hit_by_other_while_escaping 1 · unclassified 1 |
| ranged_mix | skilled | 5 | lost → timeout | 100 → 89 | 231.6 → 240.0 | overlap 6 · walking_out 4 · unclassified 3 · hit_by_other_while_escaping 2 | overlap 6 · walking_out 5 · hit_by_other_while_escaping 3 · after_dodge_025 1 |
| zone_mix | novice | 1 | lost → lost | 100 → 100 | 81.0 → 52.0 | hit_by_other_while_escaping 4 · unclassified 4 · overlap 3 · walking_out 3 | not_perceived 4 · hit_by_other_while_escaping 2 · overlap 2 · unclassified 2 |
| zone_mix | novice | 2 | lost → lost | 100 → 100 | 57.2 → 92.9 | overlap 7 · walking_out 5 · hit_by_other_while_escaping 4 · not_perceived 4 | not_perceived 5 · unclassified 5 · hit_by_other_while_escaping 3 · overlap 2 |
| zone_mix | novice | 3 | lost → lost | 100 → 100 | 60.3 → 58.8 | overlap 5 · hit_by_other_while_escaping 4 · not_perceived 4 · after_dodge_025 2 | unclassified 5 · not_perceived 3 · walking_out 3 · overlap 2 |
| zone_mix | novice | 4 | lost → lost | 100 → 100 | 50.4 → 39.7 | hit_by_other_while_escaping 4 · not_perceived 4 · overlap 3 · perceived_no_input 2 | hit_by_other_while_escaping 6 · not_perceived 5 · dodge_blocked_terrain 3 · overlap 2 |
| zone_mix | novice | 5 | lost → lost | 100 → 100 | 122.0 → 23.5 | hit_by_other_while_escaping 4 · overlap 4 · unclassified 4 · walking_out 3 | hit_by_other_while_escaping 5 · overlap 5 · walking_out 4 · not_perceived 2 |
| zone_mix | regular | 1 | lost → lost | 100 → 100 | 168.9 → 150.6 | overlap 5 · walking_out 5 · unclassified 4 · hit_by_other_while_escaping 2 | unclassified 6 · walking_out 5 · after_dodge_025 2 · overlap 2 |
| zone_mix | regular | 2 | lost → lost | 100 → 100 | 148.2 → 69.0 | unclassified 4 · hit_by_other_while_escaping 3 · dodge_blocked_terrain 2 · walking_out 2 | unclassified 8 · overlap 3 · walking_out 3 · after_dodge_025 1 |
| zone_mix | regular | 3 | lost → lost | 100 → 100 | 175.8 → 112.2 | overlap 8 · walking_out 6 · hit_by_other_while_escaping 2 · unclassified 2 | overlap 6 · walking_out 5 · unclassified 4 · after_dodge_025 3 |
| zone_mix | regular | 4 | lost → lost | 100 → 100 | 137.9 → 109.5 | overlap 6 · unclassified 5 · walking_out 5 · after_dodge_025 2 | unclassified 10 · walking_out 3 · hit_by_other_while_escaping 1 |
| zone_mix | regular | 5 | lost → lost | 100 → 100 | 166.1 → 72.6 | unclassified 6 · walking_out 4 · after_dodge_025 2 · not_perceived 2 | unclassified 5 · hit_by_other_while_escaping 3 · overlap 3 · walking_out 3 |
| zone_mix | skilled | 1 | won → lost | 33 → 100 | 220.9 → 156.6 | walking_out 2 · overlap 1 · unclassified 1 | unclassified 7 · overlap 4 · hit_by_other_while_escaping 3 · walking_out 2 |
| zone_mix | skilled | 2 | timeout → timeout | 12 → 90 | 240.0 → 240.0 | unclassified 1 | unclassified 5 · walking_out 5 · after_dodge_025 2 · overlap 2 |
| zone_mix | skilled | 3 | lost → lost | 100 → 100 | 97.1 → 186.4 | overlap 9 · walking_out 8 · after_dodge_025 1 · hit_by_other_while_escaping 1 | unclassified 6 · walking_out 5 · overlap 4 · after_dodge_025 2 |
| zone_mix | skilled | 4 | timeout → lost | 66 → 100 | 240.0 → 169.8 | unclassified 3 · walking_out 3 · dodge_blocked_terrain 2 · overlap 2 | unclassified 6 · walking_out 6 · overlap 4 · after_dodge_025 2 |
| zone_mix | skilled | 5 | timeout → lost | 56 → 100 | 240.0 → 184.3 | walking_out 5 · overlap 2 · not_perceived 1 | unclassified 8 · walking_out 4 · overlap 1 |

읽는 법: balanced(기존 PBot 정책)는 관측 스냅샷을 쓰지 않으므로 전후 동일해야 한다(동일: 예 — 게임 규칙·난수 불변의 증거). 실력 봇의 차이는 ①(독립 장판·투사체가 각각 새 지연을 받아 반응이 늦어짐)과 ②(투사체 id가 바뀌지 않아 추적·피격 원천 연결이 안정)에서만 나온다. 방향은 한쪽이 아니며(①은 대체로 피격 증가, ②는 감소·증가 모두 가능) 어느 쪽도 사람 승률이 아니다.

환경: 전 8dfcbd1d / 후 8dfcbd1d (code_hash 전 없음·후 bbf6ce1ed94f…). 벽시계 전 634초 · 후 457초.
