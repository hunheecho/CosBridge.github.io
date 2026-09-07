# 3일차 성장 중단 vs 정상 성장 — 실력별 봇 비교 (godot-0.6.0)

생성: `tools/stop3_skill.gd`. 전략 gradual, 시작 sword, 시드 [1, 2, 3], 성장 중단일 3(그 날 이후 출격 없음·상점만), 경로 ["act1_hunt_forest", "act2_crimson_ritual", "act3_temporal_abyss"]. 봇: ["balanced", "novice", "regular", "skilled"] — novice/regular/skilled는 **가상 조작 모델(사람 보정 미완료)**, balanced는 기존 정책(비교 기준). 봇 결과는 사람 난이도·밸런스 승인이 아니며, 봇이 이긴다고 체력·수치를 올리지 않는다(사용자 지시).

| 봇 | 시드 | 성장 | 결과 | 마지막 날 | Lv | 받은 피해(일반) | 휴식 | 패배 | 시간초과 | 전투분 | 보스(초·결과) | 보스 받은 피해 | 보스 패턴 상위 | 경로 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| balanced | 1 | 정상 | cleared | 10 | 17 | 524 | 1 | 2 | 0 | 8.6 | boss:won@27s guardian:won@39s eater:won@38s | 43 | guardian:shock 6 · boss:sweep 5 · guardian:sweep 4 · eater:mark 3 | 사냥 숲→붉은 의식터→시간의 심연 |
| balanced | 1 | 3일 중단 | cleared | 10 | 7 | 266 | 1 | 0 | 0 | 4.0 | boss:won@27s guardian:won@55s eater:won@63s | 0 | guardian:shock 7 · guardian:sweep 7 · eater:mark 6 · boss:sweep 5 | 사냥 숲→붉은 의식터→시간의 심연 |
| balanced | 2 | 정상 | cleared | 10 | 15 | 276 | 1 | 1 | 2 | 12.4 | boss:won@28s guardian:won@39s eater:won@43s | 3 | guardian:shock 7 · boss:dash 4 · guardian:sweep 3 · eater:mark 3 | 사냥 숲→붉은 의식터→시간의 심연 |
| balanced | 2 | 3일 중단 | cleared | 10 | 5 | 184 | 1 | 1 | 0 | 1.9 | boss:won@28s guardian:won@55s eater:won@66s | 72 | guardian:shock 11 · eater:lanes 6 · boss:dash 4 · guardian:sweep 4 | 사냥 숲→붉은 의식터→시간의 심연 |
| balanced | 3 | 정상 | cleared | 10 | 16 | 594 | 2 | 2 | 0 | 8.0 | boss:won@47s guardian:won@56s eater:won@69s | 42 | guardian:shock 7 · guardian:sweep 7 · boss:sweep 6 · eater:lanes 5 | 사냥 숲→붉은 의식터→시간의 심연 |
| balanced | 3 | 3일 중단 | cleared | 10 | 6 | 330 | 2 | 0 | 0 | 2.4 | boss:won@47s guardian:won@138s eater:won@190s | 66 | guardian:shock 19 · guardian:sweep 16 · eater:mark 13 · eater:wide 12 | 사냥 숲→붉은 의식터→시간의 심연 |
| novice | 1 | 정상 | cleared | 10 | 17 | 562 | 2 | 2 | 5 | 24.6 | boss:won@65s guardian:won@53s eater:won@55s | 136 | boss:sweep 15 · guardian:sweep 7 · guardian:shock 6 · eater:mark 5 | 사냥 숲→붉은 의식터→시간의 심연 |
| novice | 1 | 3일 중단 | boss_failed | 7 | 3 | 214 | 2 | 0 | 2 | 8.9 | boss:won@65s guardian:lost@41s guardian:lost@73s guardian:lost@82s guardian:lost@99s | 509 | guardian:shock 42 · guardian:sweep 35 · boss:sweep 15 · boss:howl 3 | 사냥 숲→붉은 의식터→시간의 심연 |
| novice | 2 | 정상 | cleared | 10 | 14 | 325 | 0 | 1 | 7 | 30.4 | boss:won@80s guardian:won@36s eater:won@44s | 32 | boss:sweep 9 · boss:dash 8 · guardian:shock 5 · boss:howl 4 | 사냥 숲→붉은 의식터→시간의 심연 |
| novice | 2 | 3일 중단 | cleared | 10 | 3 | 148 | 0 | 1 | 2 | 8.6 | boss:won@80s guardian:won@81s eater:won@126s | 34 | guardian:shock 11 · guardian:sweep 10 · boss:sweep 9 · eater:wide 9 | 사냥 숲→붉은 의식터→시간의 심연 |
| novice | 3 | 정상 | cleared | 10 | 14 | 692 | 3 | 2 | 3 | 18.4 | boss:won@55s guardian:won@75s eater:won@105s | 56 | guardian:shock 13 · eater:mark 10 · boss:sweep 8 · guardian:sweep 7 | 사냥 숲→붉은 의식터→시간의 심연 |
| novice | 3 | 3일 중단 | cleared | 10 | 6 | 324 | 2 | 0 | 1 | 5.9 | boss:won@55s guardian:won@133s eater:won@213s | 138 | guardian:sweep 18 · guardian:shock 17 · eater:mark 17 · eater:lanes 12 | 사냥 숲→붉은 의식터→시간의 심연 |
| regular | 1 | 정상 | cleared | 10 | 15 | 258 | 0 | 1 | 7 | 32.6 | boss:won@46s guardian:won@43s eater:won@63s | 122 | boss:sweep 10 · guardian:shock 6 · guardian:sweep 5 · eater:wide 4 | 사냥 숲→붉은 의식터→시간의 심연 |
| regular | 1 | 3일 중단 | cleared | 10 | 4 | 36 | 0 | 0 | 2 | 9.4 | boss:won@46s guardian:lost@65s guardian:won@103s eater:lost@97s eater:won@170s | 431 | eater:mark 24 · guardian:sweep 23 · guardian:shock 21 · eater:wide 16 | 사냥 숲→붉은 의식터→시간의 심연 |
| regular | 2 | 정상 | cleared | 10 | 14 | 216 | 1 | 1 | 6 | 26.9 | boss:won@47s guardian:won@33s eater:won@42s | 24 | boss:dash 5 · boss:sweep 5 · guardian:shock 4 · guardian:sweep 4 | 사냥 숲→붉은 의식터→시간의 심연 |
| regular | 2 | 3일 중단 | cleared | 10 | 4 | 84 | 1 | 0 | 2 | 9.0 | boss:won@47s guardian:won@101s eater:won@142s | 60 | guardian:shock 18 · eater:lanes 12 · guardian:sweep 9 · eater:wide 8 | 사냥 숲→붉은 의식터→시간의 심연 |
| regular | 3 | 정상 | cleared | 10 | 15 | 645 | 0 | 2 | 4 | 21.7 | boss:won@52s guardian:won@79s eater:won@99s | 56 | guardian:shock 10 · guardian:sweep 10 · boss:dash 7 · eater:mark 7 | 사냥 숲→붉은 의식터→시간의 심연 |
| regular | 3 | 3일 중단 | cleared | 10 | 6 | 178 | 0 | 0 | 1 | 6.4 | boss:won@52s guardian:won@114s eater:won@142s | 120 | guardian:shock 16 · guardian:sweep 14 · eater:lanes 11 · eater:mark 9 | 사냥 숲→붉은 의식터→시간의 심연 |
| skilled | 1 | 정상 | cleared | 10 | 15 | 127 | 0 | 1 | 7 | 33.2 | boss:won@45s guardian:won@57s eater:won@58s | 64 | boss:sweep 10 · guardian:sweep 8 · guardian:shock 6 · eater:mark 4 | 사냥 숲→붉은 의식터→시간의 심연 |
| skilled | 1 | 3일 중단 | cleared | 10 | 4 | 12 | 0 | 0 | 2 | 9.4 | boss:won@45s guardian:won@99s eater:won@151s | 66 | guardian:shock 14 · eater:mark 13 · guardian:sweep 12 · boss:sweep 10 | 사냥 숲→붉은 의식터→시간의 심연 |
| skilled | 2 | 정상 | cleared | 10 | 13 | 214 | 0 | 2 | 5 | 25.4 | boss:won@43s guardian:won@61s eater:won@79s | 40 | guardian:shock 9 · guardian:sweep 7 · boss:sweep 5 · eater:mark 5 | 사냥 숲→붉은 의식터→시간의 심연 |
| skilled | 2 | 3일 중단 | cleared | 10 | 4 | 0 | 0 | 0 | 2 | 9.6 | boss:won@43s guardian:won@108s eater:won@143s | 16 | guardian:shock 14 · guardian:sweep 14 · eater:lanes 12 · eater:mark 8 | 사냥 숲→붉은 의식터→시간의 심연 |
| skilled | 3 | 정상 | cleared | 10 | 15 | 248 | 0 | 2 | 3 | 18.9 | boss:won@53s guardian:won@87s eater:won@97s | 7 | guardian:shock 12 · guardian:sweep 11 · boss:sweep 6 · eater:wide 6 | 사냥 숲→붉은 의식터→시간의 심연 |
| skilled | 3 | 3일 중단 | cleared | 10 | 6 | 34 | 0 | 0 | 1 | 6.4 | boss:won@53s guardian:won@112s eater:won@140s | 48 | guardian:shock 15 · guardian:sweep 14 · eater:lanes 10 · eater:wide 8 | 사냥 숲→붉은 의식터→시간의 심연 |

## 봇별 요약 (평균)

| 봇 | 성장 | 완주 | 평균 Lv | 평균 받은 피해(일반) | 평균 휴식 | 평균 보스 받은 피해 | 평균 보스 초 |
|---|---|---|---|---|---|---|---|
| balanced | 정상 | 3/3 | 16.0 | 465 | 1.3 | 29 | 129 |
| balanced | 3일 중단 | 3/3 | 6.0 | 260 | 1.3 | 46 | 223 |
| novice | 정상 | 3/3 | 15.0 | 526 | 1.7 | 75 | 189 |
| novice | 3일 중단 | 2/3 | 4.0 | 229 | 1.3 | 227 | 349 |
| regular | 정상 | 3/3 | 14.7 | 373 | 0.3 | 67 | 168 |
| regular | 3일 중단 | 3/3 | 4.7 | 99 | 0.3 | 204 | 360 |
| skilled | 정상 | 3/3 | 14.3 | 196 | 0.0 | 37 | 193 |
| skilled | 3일 중단 | 3/3 | 4.7 | 15 | 0.0 | 43 | 298 |

읽는 법: '받은 피해'는 일반 전투 합계, '보스 받은 피해'는 관문 전투 합계(재도전 포함). 중단 빌드가 완주하면 후반이 봇에게 느슨하다는 뜻이지 사람에게도 그렇다는 뜻은 아니다. 완주 실패의 원인(보스 패배·시간 초과·정체)은 결과 열로 구분한다.
실행 벽시계: 1111.2초.
