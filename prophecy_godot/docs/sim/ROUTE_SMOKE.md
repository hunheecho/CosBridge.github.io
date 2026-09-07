# 경로 스모크 (godot-0.6.0-s2, 봇 balanced, 시드 [1, 2], 시작 ["sword", "spear", "blades"])

생성: `tools/route_smoke.gd`. 구현된 테마(보스 정의 존재)만 조합: 1막 1 × 2막 1 × 3막 1 = 1경로(목표 27). 봇 결과는 기술 스모크이며 사람 난이도·밸런스 승인이 아니다. 실패 구분: boss_lost(보스 패배·재도전 소진) / lost(일반전 패배로 정체) / stalled(진행 정체) / error(스크립트 오류).

| 경로 | 시작 | 시드 | 결과 | 마지막 날 | 레벨 | 전투분 | 보스(초) | 패배 | 휴식 | 금화 | 제작 가능 재료(정산) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 사냥 숲→붉은 의식터→시간의 심연 | sword | 1 | cleared | 10 | 17 | 8.6 | boss:won@27s guardian:won@39s eater:won@38s | 2 | 1 | 139 | { "pelt": 20, "iron": 7, "spore": 11, "fang": 0 } |
| 사냥 숲→붉은 의식터→시간의 심연 | sword | 2 | cleared | 10 | 15 | 12.4 | boss:won@28s guardian:won@39s eater:won@43s | 1 | 1 | 106 | { "pelt": 4, "iron": 3, "spore": 5, "fang": 0 } |
| 사냥 숲→붉은 의식터→시간의 심연 | spear | 1 | cleared | 10 | 15 | 10.8 | boss:won@35s guardian:won@50s eater:won@65s | 2 | 3 | 44 | { "pelt": 6, "iron": 6, "spore": 11, "fang": 0 } |
| 사냥 숲→붉은 의식터→시간의 심연 | spear | 2 | cleared | 10 | 13 | 6.7 | boss:won@45s guardian:won@39s eater:won@51s | 3 | 2 | 75 | { "pelt": 3, "iron": 3, "spore": 5, "fang": 0 } |
| 사냥 숲→붉은 의식터→시간의 심연 | blades | 1 | cleared | 10 | 16 | 8.9 | boss:won@44s guardian:won@76s eater:won@111s | 4 | 1 | 60 | { "pelt": 7, "iron": 5, "spore": 10, "fang": 0 } |
| 사냥 숲→붉은 의식터→시간의 심연 | blades | 2 | cleared | 10 | 15 | 13.6 | boss:won@43s guardian:won@42s eater:won@46s | 1 | 2 | 83 | { "pelt": 10, "iron": 2, "spore": 6, "fang": 0 } |

실행 벽시계: 153.7초. 미구현 테마(보스 없음)는 후보에서 제외되어 표에 없다.
