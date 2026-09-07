# 보스전 헤드리스 측정 (godot-0.5.0, Godot 4.7.2-stable (official), Windows, 밸런스 test03, 보스 체력 세트 base = 성문 파수장 1500 / 포자 어미 1500 / 굴착 거수 3000 / 서리 추적자 3000 / 핏빛 사냥왕 3600 / 종말의 집행관 3600, 상한 300초, 시드 [11, 18])

생성: `tools/boss_sim.gd`. 빌드는 PCatalog.lab().BUILDS 프리셋(성장·장비·강화)을 회차 dict에 넣고 PRun.build로 파생(고정 빌드 start_sword,start_spear,start_blades,mid_melee,mid_ranged,dot). 신규 보스 6종 수치는 bosses_new.json 시험값(사람 승인 아님). 정책: balanced=균형. 봇 결과는 사람 승률이 아니다. 받은 피해 = 유효 피해(실제 체력 감소).

## 성문 파수장 (1막 · 체력 1500)

| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 시작: 검격(Lv1, 개조·장비 없음) | 0 | 균형 | 2/2 | 89 | 100 | -8 | 0 | 0 | 0 | 28 | 0 | 6 | 0 | 1500 | bolts 7.5, guard 20.5 | 검 100% |
| 시작: 관통창(Lv1) | 0 | 균형 | 2/2 | 102 | 92 | -8 | 13 | 0 | 5 | 32 | 1 | 7 | 0 | 1500 | bolts 7.5, breach 9.0, guard 9.5 | 관통창 100% |
| 시작: 회전 칼날(Lv1) | 0 | 균형 | 2/2 | 120 | 100 | -8 | 0 | 0 | 0 | 38 | 0 | 8 | 0 | 1500 | bolts 4.0, guard 34.0 | 회전 칼날 100% |
| 중간 근접 조합 | 7 | 균형 | 2/2 | 23 | 95 | -2 | 5 | 0 | 0 | 6 | 1 | 2 | 0 | 1500 | bolts 3.5, guard 3.5 | 검 53%, 쌍검 43%, 출혈(쌍검) 5% |
| 중간 원거리 조합 | 7 | 균형 | 2/2 | 14 | 100 | -4 | 0 | 0 | 0 | 4 | 0 | 1 | 0 | 1500 | bolts 2.5, breach 0.5, guard 0.5 | 추적궁 84%, 서리 수정 16% |
| 불길·지속 피해 조합 | 10 | 균형 | 2/2 | 13 | 100 | -5 | 0 | 0 | 0 | 4 | 0 | 1 | 0 | 1500 | bolts 1.0, breach 1.0, guard 0.5 | 불씨 정령 79%, 검 15%, 잔불 걸음 3% |

## 포자 어미 (1막 · 체력 1500)

| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 시작: 검격(Lv1, 개조·장비 없음) | 0 | 균형 | 0/2 | - | 0 | 30 | 115 | 0 | 15 | 27 | 6 | 7 | 0 | 1470 | ring 6.0, shot 9.0, spray 5.0, summon 2.5 | 검 100% |
| 시작: 관통창(Lv1) | 0 | 균형 | 0/2 | - | 0 | 648 | 108 | 0 | 8 | 17 | 7 | 4 | 0 | 853 | ring 6.5, shot 6.0, summon 2.0 | 관통창 100% |
| 시작: 회전 칼날(Lv1) | 0 | 균형 | 0/2 | - | 0 | 553 | 115 | 0 | 15 | 24 | 8 | 6 | 0 | 948 | ring 7.0, shot 6.5, spray 5.5, summon 3.0 | 회전 칼날 100% |
| 중간 근접 조합 | 7 | 균형 | 2/2 | 34 | 76 | -1 | 32 | 0 | 8 | 10 | 2 | 3 | 0 | 1500 | ring 2.0, shot 4.5, spray 0.5, summon 1.5 | 검 62%, 쌍검 34%, 출혈(쌍검) 4% |
| 중간 원거리 조합 | 7 | 균형 | 2/2 | 17 | 92 | -4 | 16 | 0 | 8 | 5 | 1 | 2 | 0 | 1500 | ring 1.0, shot 2.0, summon 0.5 | 추적궁 84%, 서리 수정 16% |
| 불길·지속 피해 조합 | 10 | 균형 | 2/2 | 16 | 84 | -2 | 16 | 0 | 0 | 4 | 1 | 1 | 0 | 1500 | ring 2.0, shot 1.0, summon 1.0 | 불씨 정령 90%, 검 8%, 화상(검) 2% |

## 굴착 거수 (2막 · 체력 3000)

| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 시작: 검격(Lv1, 개조·장비 없음) | 0 | 균형 | 1/2 | 172 | 40 | 870 | 68 | 0 | 8 | 64 | 8 | 8 | 0 | 2130 | burrow 1.0, rockfall 20.0, summon 3.0 | 검 100% |
| 시작: 관통창(Lv1) | 0 | 균형 | 1/2 | 216 | 25 | 1017 | 83 | 0 | 8 | 38 | 12 | 10 | 0 | 1980 | burrow 9.5, rockfall 23.5, summon 3.0 | 관통창 100% |
| 시작: 회전 칼날(Lv1) | 0 | 균형 | 0/2 | - | 0 | 1625 | 100 | 0 | 0 | 40 | 10 | 5 | 0 | 1375 | burrow 1.5, rockfall 13.0, summon 3.0 | 회전 칼날 100% |
| 중간 근접 조합 | 7 | 균형 | 2/2 | 53 | 78 | -16 | 30 | 0 | 8 | 29 | 2 | 4 | 0 | 3000 | rockfall 9.5, summon 3.0 | 검 60%, 쌍검 37%, 출혈(쌍검) 4% |
| 중간 원거리 조합 | 7 | 균형 | 2/2 | 30 | 84 | -29 | 24 | 0 | 8 | 12 | 4 | 2 | 1 | 3000 | burrow 3.0, rockfall 2.0, summon 1.0 | 추적궁 79%, 서리 수정 20%, 낙뢰(E) 1% |
| 불길·지속 피해 조합 | 10 | 균형 | 2/2 | 23 | 100 | -5 | 0 | 0 | 0 | 10 | 0 | 2 | 0 | 3000 | burrow 1.5, rockfall 2.0, summon 1.0 | 불씨 정령 82%, 검 13%, 화상(검) 3% |

## 서리 추적자 (2막 · 체력 3000)

| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 시작: 검격(Lv1, 개조·장비 없음) | 0 | 균형 | 2/2 | 116 | 34 | -12 | 96 | 0 | 30 | 33 | 8 | 9 | 0 | 3000 | bolt 1.0, icepath 32.0 | 검 100% |
| 시작: 관통창(Lv1) | 0 | 균형 | 0/2 | - | 0 | 1357 | 115 | 0 | 15 | 29 | 10 | 8 | 0 | 1644 | bolt 12.0, dash 7.0, icepath 10.0 | 관통창 100% |
| 시작: 회전 칼날(Lv1) | 0 | 균형 | 0/2 | - | 0 | 410 | 112 | 0 | 12 | 38 | 10 | 10 | 0 | 2590 | bolt 1.0, icepath 37.0 | 회전 칼날 100% |
| 중간 근접 조합 | 7 | 균형 | 2/2 | 36 | 79 | -28 | 36 | 0 | 15 | 10 | 3 | 3 | 0 | 3000 | bolt 1.0, icepath 9.0 | 검 52%, 쌍검 44%, 출혈(쌍검) 4% |
| 중간 원거리 조합 | 7 | 균형 | 2/2 | 28 | 85 | -8 | 21 | 0 | 6 | 7 | 2 | 2 | 0 | 3000 | bolt 1.5, dash 3.0, icepath 2.5 | 추적궁 79%, 서리 수정 21% |
| 불길·지속 피해 조합 | 10 | 균형 | 2/2 | 24 | 87 | -7 | 25 | 0 | 12 | 6 | 2 | 2 | 0 | 3000 | bolt 2.0, dash 1.5, icepath 2.0 | 불씨 정령 79%, 검 16%, 화상(검) 4% |

## 핏빛 사냥왕 (3막 · 체력 3600)

| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 시작: 검격(Lv1, 개조·장비 없음) | 0 | 균형 | 2/2 | 212 | 100 | 0 | 0 | 0 | 0 | 64 | 0 | 15 | 0 | 3600 | claw 59.5, dash 1.0, summon 3.0 | 검 100% |
| 시작: 관통창(Lv1) | 0 | 균형 | 0/2 | - | 0 | 2437 | 100 | 0 | 0 | 29 | 4 | 6 | 0 | 1164 | claw 8.5, dash 8.5, summon 3.0 | 관통창 100% |
| 시작: 회전 칼날(Lv1) | 0 | 균형 | 2/2 | 271 | 90 | -3 | 30 | 0 | 20 | 81 | 0 | 19 | 0 | 3600 | claw 75.5, dash 1.0, summon 3.0 | 회전 칼날 100% |
| 중간 근접 조합 | 7 | 균형 | 2/2 | 59 | 100 | -7 | 0 | 0 | 0 | 18 | 0 | 4 | 0 | 3600 | claw 13.5, dash 1.0, summon 3.0 | 검 53%, 쌍검 42%, 출혈(쌍검) 5% |
| 중간 원거리 조합 | 7 | 균형 | 2/2 | 33 | 100 | -10 | 0 | 0 | 0 | 11 | 0 | 3 | 2 | 3600 | claw 1.5, dash 4.0, summon 1.5 | 추적궁 78%, 서리 수정 19%, 낙뢰(E) 3% |
| 불길·지속 피해 조합 | 10 | 균형 | 2/2 | 26 | 100 | -5 | 0 | 0 | 0 | 8 | 0 | 2 | 0 | 3600 | claw 2.5, dash 2.0, summon 1.0 | 불씨 정령 80%, 검 16%, 화상(검) 3% |

## 종말의 집행관 (3막 · 체력 3600)

| 빌드 | 선택 수 | 정책 | 승리 | 평균 초(승) | 남은 체력 | 보스 남은 | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | E | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 시작: 검격(Lv1, 개조·장비 없음) | 0 | 균형 | 1/2 | 169 | 50 | 1255 | 61 | 0 | 11 | 39 | 3 | 8 | 0 | 2341 | guard 9.0, slash 14.0, summon 2.0 | 검 100% |
| 시작: 관통창(Lv1) | 0 | 균형 | 0/2 | - | 0 | 2770 | 100 | 0 | 0 | 23 | 5 | 5 | 0 | 830 | guard 5.5, slash 8.0, summon 2.0 | 관통창 100% |
| 시작: 회전 칼날(Lv1) | 0 | 균형 | 1/2 | 197 | 43 | 850 | 72 | 0 | 15 | 51 | 4 | 11 | 0 | 2750 | guard 13.0, slash 18.0, summon 2.0 | 회전 칼날 100% |
| 중간 근접 조합 | 7 | 균형 | 2/2 | 53 | 85 | -10 | 23 | 0 | 8 | 18 | 1 | 4 | 0 | 3600 | guard 4.5, slash 5.5, summon 2.0 | 검 52%, 쌍검 43%, 출혈(쌍검) 5% |
| 중간 원거리 조합 | 7 | 균형 | 1/2 | 41 | 6 | 172 | 102 | 0 | 8 | 15 | 5 | 3 | 2 | 3420 | guard 1.5, slash 5.5, summon 2.0 | 추적궁 79%, 서리 수정 18%, 낙뢰(E) 3% |
| 불길·지속 피해 조합 | 10 | 균형 | 2/2 | 29 | 78 | -10 | 22 | 0 | 0 | 10 | 1 | 2 | 0 | 3600 | guard 1.0, slash 4.0, summon 1.0 | 불씨 정령 82%, 검 11%, 화상(검) 3% |

## 전투별

| 보스 | 빌드 | 정책 | 시드 | 결과 | 초 | 남은 체력 | 보스 남은/최대 | 받은 피해 | 처치(소환) | Q | E | 패턴 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 성문 파수장 | start_sword | balanced | 11 | won | 87.6 | 100 | -4/1500 | 0 | 1 | 6 | 0 | bolts 6, guard 22 |
| 성문 파수장 | start_sword | balanced | 18 | won | 90.1 | 100 | -11/1500 | 0 | 1 | 6 | 0 | bolts 9, guard 19 |
| 성문 파수장 | start_spear | balanced | 11 | won | 100.7 | 100 | -11/1500 | 10 | 1 | 7 | 0 | bolts 5, guard 9, breach 11 |
| 성문 파수장 | start_spear | balanced | 18 | won | 103.2 | 84 | -4/1500 | 16 | 1 | 7 | 0 | bolts 10, guard 10, breach 7 |
| 성문 파수장 | start_blades | balanced | 11 | won | 120.1 | 100 | -8/1500 | 0 | 1 | 8 | 0 | bolts 4, guard 34 |
| 성문 파수장 | start_blades | balanced | 18 | won | 120.1 | 100 | -8/1500 | 0 | 1 | 8 | 0 | bolts 4, guard 34 |
| 성문 파수장 | mid_melee | balanced | 11 | won | 25.8 | 100 | -1/1500 | 0 | 1 | 2 | 0 | bolts 3, guard 5 |
| 성문 파수장 | mid_melee | balanced | 18 | won | 20.1 | 90 | -3/1500 | 10 | 1 | 2 | 0 | bolts 4, guard 2 |
| 성문 파수장 | mid_ranged | balanced | 11 | won | 15.1 | 100 | -5/1500 | 0 | 1 | 1 | 0 | bolts 3, guard 1 |
| 성문 파수장 | mid_ranged | balanced | 18 | won | 13.6 | 100 | -3/1500 | 0 | 1 | 1 | 0 | bolts 2, breach 1 |
| 성문 파수장 | dot | balanced | 11 | won | 12.4 | 100 | -7/1500 | 0 | 1 | 1 | 0 | bolts 1, breach 1 |
| 성문 파수장 | dot | balanced | 18 | won | 13.6 | 100 | -2/1500 | 0 | 1 | 1 | 0 | bolts 1, guard 1, breach 1 |
| 포자 어미 | start_sword | balanced | 11 | lost | 96.8 | 0 | 18/1500 | 115 | 1 | 7 | 0 | shot 8, ring 7, spray 5, summon 3 |
| 포자 어미 | start_sword | balanced | 18 | lost | 87.9 | 0 | 42/1500 | 115 | 2 | 6 | 0 | shot 10, ring 5, spray 5, summon 2 |
| 포자 어미 | start_spear | balanced | 11 | lost | 65.0 | 0 | 594/1500 | 115 | 2 | 4 | 0 | shot 7, ring 6, summon 2 |
| 포자 어미 | start_spear | balanced | 18 | lost | 59.8 | 0 | 702/1500 | 100 | 2 | 4 | 0 | shot 5, ring 7, summon 2 |
| 포자 어미 | start_blades | balanced | 11 | lost | 103.9 | 0 | 240/1500 | 115 | 1 | 7 | 0 | shot 8, spray 10, ring 6, summon 3 |
| 포자 어미 | start_blades | balanced | 18 | lost | 71.0 | 0 | 865/1500 | 115 | 2 | 5 | 0 | shot 5, ring 8, summon 3, spray 1 |
| 포자 어미 | mid_melee | balanced | 11 | won | 34.6 | 84 | 0/1500 | 16 | 2 | 3 | 0 | shot 5, summon 2, spray 1, ring 1 |
| 포자 어미 | mid_melee | balanced | 18 | won | 33.3 | 67 | -1/1500 | 48 | 1 | 2 | 0 | shot 4, ring 3, summon 1 |
| 포자 어미 | mid_ranged | balanced | 11 | won | 15.7 | 84 | -5/1500 | 16 | 1 | 1 | 0 | shot 2, ring 1 |
| 포자 어미 | mid_ranged | balanced | 18 | won | 18.2 | 99 | -2/1500 | 16 | 2 | 2 | 0 | shot 2, summon 1, ring 1 |
| 포자 어미 | dot | balanced | 11 | won | 15.8 | 84 | -3/1500 | 16 | 2 | 1 | 0 | shot 1, summon 1, ring 2 |
| 포자 어미 | dot | balanced | 18 | won | 16.6 | 84 | -1/1500 | 16 | 2 | 1 | 0 | shot 1, summon 1, ring 2 |
| 굴착 거수 | start_sword | balanced | 11 | won | 171.8 | 79 | 0/3000 | 36 | 1 | 11 | 0 | rockfall 30, summon 3, burrow 2 |
| 굴착 거수 | start_sword | balanced | 18 | lost | 55.1 | 0 | 1740/3000 | 100 | 1 | 4 | 0 | rockfall 10, summon 3 |
| 굴착 거수 | start_spear | balanced | 11 | lost | 68.9 | 0 | 2041/3000 | 100 | 5 | 5 | 0 | rockfall 7, summon 3, burrow 6 |
| 굴착 거수 | start_spear | balanced | 18 | won | 216.1 | 49 | -7/3000 | 66 | 4 | 15 | 0 | rockfall 40, burrow 13, summon 3 |
| 굴착 거수 | start_blades | balanced | 11 | lost | 91.3 | 0 | 1350/3000 | 100 | 1 | 6 | 0 | rockfall 16, summon 3, burrow 1 |
| 굴착 거수 | start_blades | balanced | 18 | lost | 62.7 | 0 | 1900/3000 | 100 | 0 | 4 | 0 | rockfall 10, summon 3, burrow 2 |
| 굴착 거수 | mid_melee | balanced | 11 | won | 51.6 | 95 | -30/3000 | 5 | 6 | 4 | 0 | rockfall 9, summon 3 |
| 굴착 거수 | mid_melee | balanced | 18 | won | 54.7 | 61 | -1/3000 | 54 | 4 | 4 | 0 | rockfall 10, summon 3 |
| 굴착 거수 | mid_ranged | balanced | 11 | won | 29.8 | 100 | -11/3000 | 0 | 3 | 2 | 1 | rockfall 2, burrow 3, summon 1 |
| 굴착 거수 | mid_ranged | balanced | 18 | won | 29.2 | 67 | -47/3000 | 48 | 2 | 2 | 1 | rockfall 2, burrow 3, summon 1 |
| 굴착 거수 | dot | balanced | 11 | won | 24.4 | 100 | -1/3000 | 0 | 3 | 2 | 0 | rockfall 3, summon 1, burrow 1 |
| 굴착 거수 | dot | balanced | 18 | won | 22.0 | 100 | -9/3000 | 0 | 3 | 2 | 0 | rockfall 1, burrow 2, summon 1 |
| 서리 추적자 | start_sword | balanced | 11 | won | 116.3 | 34 | -12/3000 | 96 | 1 | 9 | 0 | bolt 1, icepath 32 |
| 서리 추적자 | start_sword | balanced | 18 | won | 116.3 | 34 | -12/3000 | 96 | 1 | 9 | 0 | bolt 1, icepath 32 |
| 서리 추적자 | start_spear | balanced | 11 | lost | 55.8 | 0 | 2111/3000 | 100 | 0 | 4 | 0 | bolt 6, icepath 7, dash 3 |
| 서리 추적자 | start_spear | balanced | 18 | lost | 151.8 | 0 | 603/3000 | 130 | 0 | 11 | 0 | bolt 18, dash 11, icepath 13 |
| 서리 추적자 | start_blades | balanced | 11 | lost | 132.5 | 0 | 410/3000 | 112 | 0 | 10 | 0 | bolt 1, icepath 37 |
| 서리 추적자 | start_blades | balanced | 18 | lost | 132.5 | 0 | 410/3000 | 112 | 0 | 10 | 0 | bolt 1, icepath 37 |
| 서리 추적자 | mid_melee | balanced | 11 | won | 36.3 | 79 | -28/3000 | 36 | 1 | 3 | 0 | bolt 1, icepath 9 |
| 서리 추적자 | mid_melee | balanced | 18 | won | 36.3 | 79 | -28/3000 | 36 | 1 | 3 | 0 | bolt 1, icepath 9 |
| 서리 추적자 | mid_ranged | balanced | 11 | won | 28.9 | 100 | -5/3000 | 0 | 1 | 2 | 0 | bolt 2, dash 3, icepath 2 |
| 서리 추적자 | mid_ranged | balanced | 18 | won | 27.7 | 70 | -11/3000 | 42 | 1 | 2 | 0 | bolt 1, dash 3, icepath 3 |
| 서리 추적자 | dot | balanced | 11 | won | 24.4 | 88 | -6/3000 | 24 | 1 | 2 | 0 | bolt 1, icepath 2, dash 2 |
| 서리 추적자 | dot | balanced | 18 | won | 24.0 | 86 | -8/3000 | 26 | 1 | 2 | 0 | bolt 3, icepath 2, dash 1 |
| 핏빛 사냥왕 | start_sword | balanced | 11 | won | 210.8 | 100 | 0/3600 | 0 | 7 | 15 | 0 | dash 1, claw 59, summon 3 |
| 핏빛 사냥왕 | start_sword | balanced | 18 | won | 212.9 | 100 | 0/3600 | 0 | 7 | 15 | 0 | dash 1, claw 60, summon 3 |
| 핏빛 사냥왕 | start_spear | balanced | 11 | lost | 86.6 | 0 | 2326/3600 | 100 | 4 | 6 | 0 | dash 9, claw 9, summon 3 |
| 핏빛 사냥왕 | start_spear | balanced | 18 | lost | 77.9 | 0 | 2547/3600 | 100 | 6 | 6 | 0 | dash 8, summon 3, claw 8 |
| 핏빛 사냥왕 | start_blades | balanced | 11 | won | 272.3 | 100 | 0/3600 | 24 | 7 | 19 | 0 | dash 1, claw 76, summon 3 |
| 핏빛 사냥왕 | start_blades | balanced | 18 | won | 268.8 | 79 | -5/3600 | 36 | 7 | 19 | 0 | dash 1, summon 3, claw 75 |
| 핏빛 사냥왕 | mid_melee | balanced | 11 | won | 58.7 | 100 | -3/3600 | 0 | 7 | 4 | 0 | dash 1, claw 13, summon 3 |
| 핏빛 사냥왕 | mid_melee | balanced | 18 | won | 58.8 | 100 | -10/3600 | 0 | 7 | 4 | 0 | dash 1, summon 3, claw 14 |
| 핏빛 사냥왕 | mid_ranged | balanced | 11 | won | 33.2 | 100 | -4/3600 | 0 | 3 | 3 | 1 | dash 4, summon 1, claw 2 |
| 핏빛 사냥왕 | mid_ranged | balanced | 18 | won | 33.5 | 100 | -15/3600 | 0 | 5 | 3 | 2 | dash 4, summon 2, claw 1 |
| 핏빛 사냥왕 | dot | balanced | 11 | won | 26.4 | 100 | -2/3600 | 0 | 3 | 2 | 0 | dash 2, summon 1, claw 3 |
| 핏빛 사냥왕 | dot | balanced | 18 | won | 25.2 | 100 | -7/3600 | 0 | 3 | 2 | 0 | dash 2, summon 1, claw 2 |
| 종말의 집행관 | start_sword | balanced | 11 | won | 168.6 | 100 | -10/3600 | 22 | 5 | 12 | 0 | slash 21, guard 14, summon 2 |
| 종말의 집행관 | start_sword | balanced | 18 | lost | 54.1 | 0 | 2519/3600 | 100 | 2 | 4 | 0 | slash 7, summon 2, guard 4 |
| 종말의 집행관 | start_spear | balanced | 11 | lost | 40.7 | 0 | 3009/3600 | 100 | 0 | 3 | 0 | slash 5, guard 3, summon 1 |
| 종말의 집행관 | start_spear | balanced | 18 | lost | 103.0 | 0 | 2531/3600 | 100 | 4 | 7 | 0 | slash 11, guard 8, summon 3 |
| 종말의 집행관 | start_blades | balanced | 11 | lost | 100.0 | 0 | 1700/3600 | 100 | 4 | 7 | 0 | slash 13, guard 8, summon 2 |
| 종말의 집행관 | start_blades | balanced | 18 | won | 196.5 | 86 | -1/3600 | 44 | 5 | 14 | 0 | slash 23, summon 2, guard 18 |
| 종말의 집행관 | mid_melee | balanced | 11 | won | 52.2 | 69 | -11/3600 | 46 | 5 | 4 | 0 | slash 5, summon 2, guard 5 |
| 종말의 집행관 | mid_melee | balanced | 18 | won | 53.1 | 100 | -8/3600 | 0 | 5 | 4 | 0 | slash 6, summon 2, guard 4 |
| 종말의 집행관 | mid_ranged | balanced | 11 | lost | 38.8 | 0 | 360/3600 | 115 | 4 | 3 | 2 | slash 6, summon 2, guard 1 |
| 종말의 집행관 | mid_ranged | balanced | 18 | won | 41.1 | 12 | -17/3600 | 88 | 5 | 3 | 2 | slash 5, summon 2, guard 2 |
| 종말의 집행관 | dot | balanced | 11 | won | 29.5 | 100 | -9/3600 | 0 | 3 | 2 | 0 | slash 4, summon 1, guard 1 |
| 종말의 집행관 | dot | balanced | 18 | won | 29.3 | 56 | -11/3600 | 44 | 3 | 2 | 0 | slash 4, summon 1, guard 1 |

## 제자리(still) 정책 결과 — 서서 버티며 이기는 보스

| 보스 | 빌드 | 제자리 승리 | 판정 |
|---|---|---|---|

## 읽는 법
- "제자리 Q/E"(still)와 이동 정책의 차이 = 이동·회피가 보스 행동·생존에 미친 영향(같은 빌드·시드).
- 보스 공격 실행 대비 명중이 0에 가까우면 정지한 플레이어를 못 맞히는 것이므로 재현·수정 대상.
- 제자리 행동이 이기는 칸은 "서서 버티며 이김"의 신호. 원인은 체력 부족으로 단정하지 않는다(공격 빈도·명중률·틈을 함께 본다).
