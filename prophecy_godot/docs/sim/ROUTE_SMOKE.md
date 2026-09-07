# 경로 스모크 (godot-0.6.0-s2, 봇 balanced, 시드 [1], 시작 ["sword"])

생성: `tools/route_smoke.gd`. 구현된 테마(보스 정의 존재)만 조합: 1막 3 × 2막 3 × 3막 3 = 27경로(목표 27). 봇 결과는 기술 스모크이며 사람 난이도·밸런스 승인이 아니다. 실패 구분: boss_lost(보스 패배·재도전 소진) / lost(일반전 패배로 정체) / stalled(진행 정체) / error(스크립트 오류).

| 경로 | 시작 | 시드 | 결과 | 마지막 날 | 레벨 | 전투분 | 보스(초) | 패배 | 휴식 | 금화 | 제작 가능 재료(정산) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 버려진 요새→무너지는 광산→피의 사냥터 | sword | 1 | boss_failed | 7 | 10 | 8.3 | gate_warden:won@147s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s | 4 | 0 | 147 | { "pelt": 0, "iron": 5, "spore": 2, "fang": 0 } |
| 버려진 요새→무너지는 광산→시간의 심연 | sword | 1 | boss_failed | 7 | 10 | 8.3 | gate_warden:won@147s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s | 4 | 0 | 147 | { "pelt": 0, "iron": 5, "spore": 2, "fang": 0 } |
| 버려진 요새→무너지는 광산→뒤틀린 성채 | sword | 1 | boss_failed | 7 | 10 | 8.3 | gate_warden:won@147s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s | 4 | 0 | 147 | { "pelt": 0, "iron": 5, "spore": 2, "fang": 0 } |
| 버려진 요새→붉은 의식터→피의 사냥터 | sword | 1 | cleared | 10 | 19 | 14.5 | gate_warden:won@147s guardian:won@55s blood_hunt_king:won@44s | 4 | 0 | 62 | { "pelt": 5, "iron": 4, "spore": 10, "fang": 0 } |
| 버려진 요새→붉은 의식터→시간의 심연 | sword | 1 | cleared | 10 | 15 | 6.1 | gate_warden:won@147s guardian:won@55s eater:won@45s | 6 | 0 | 45 | { "pelt": 0, "iron": 4, "spore": 10, "fang": 0 } |
| 버려진 요새→붉은 의식터→뒤틀린 성채 | sword | 1 | boss_failed | 10 | 20 | 11.8 | gate_warden:won@147s guardian:won@55s doom_executor:lost@45s doom_executor:lost@45s doom_executor:lost@45s doom_executor:lost@45s | 5 | 0 | 150 | { "pelt": 0, "iron": 10, "spore": 12, "fang": 0 } |
| 버려진 요새→얼어붙은 협곡→피의 사냥터 | sword | 1 | cleared | 10 | 18 | 15.7 | gate_warden:won@147s frost_stalker:won@30s blood_hunt_king:won@34s | 4 | 0 | 145 | { "pelt": 13, "iron": 7, "spore": 0, "fang": 0 } |
| 버려진 요새→얼어붙은 협곡→시간의 심연 | sword | 1 | cleared | 10 | 15 | 11.0 | gate_warden:won@147s frost_stalker:won@30s eater:won@38s | 5 | 0 | 95 | { "pelt": 6, "iron": 7, "spore": 0, "fang": 0 } |
| 버려진 요새→얼어붙은 협곡→뒤틀린 성채 | sword | 1 | cleared | 10 | 20 | 16.0 | gate_warden:won@147s frost_stalker:won@30s doom_executor:won@36s | 4 | 0 | 79 | { "pelt": 6, "iron": 13, "spore": 3, "fang": 0 } |
| 사냥 숲→무너지는 광산→피의 사냥터 | sword | 1 | cleared | 10 | 20 | 25.1 | boss:won@27s excavation_behemoth:won@48s blood_hunt_king:won@43s | 0 | 1 | 90 | { "pelt": 24, "iron": 9, "spore": 2, "fang": 0 } |
| 사냥 숲→무너지는 광산→시간의 심연 | sword | 1 | cleared | 10 | 17 | 16.2 | boss:won@27s excavation_behemoth:won@48s eater:won@47s | 2 | 1 | 92 | { "pelt": 20, "iron": 9, "spore": 2, "fang": 0 } |
| 사냥 숲→무너지는 광산→뒤틀린 성채 | sword | 1 | cleared | 10 | 21 | 22.7 | boss:won@27s excavation_behemoth:won@48s doom_executor:won@43s | 1 | 1 | 107 | { "pelt": 20, "iron": 13, "spore": 4, "fang": 0 } |
| 사냥 숲→붉은 의식터→피의 사냥터 | sword | 1 | cleared | 10 | 21 | 17.6 | boss:won@27s guardian:won@39s blood_hunt_king:won@44s | 0 | 1 | 61 | { "pelt": 25, "iron": 7, "spore": 11, "fang": 0 } |
| 사냥 숲→붉은 의식터→시간의 심연 | sword | 1 | cleared | 10 | 17 | 8.6 | boss:won@27s guardian:won@39s eater:won@38s | 2 | 1 | 139 | { "pelt": 20, "iron": 7, "spore": 11, "fang": 0 } |
| 사냥 숲→붉은 의식터→뒤틀린 성채 | sword | 1 | cleared | 10 | 22 | 11.4 | boss:won@27s guardian:won@39s doom_executor:won@37s | 2 | 1 | 89 | { "pelt": 20, "iron": 12, "spore": 14, "fang": 0 } |
| 사냥 숲→얼어붙은 협곡→피의 사냥터 | sword | 1 | cleared | 10 | 21 | 19.4 | boss:won@27s frost_stalker:won@32s blood_hunt_king:won@44s | 0 | 1 | 96 | { "pelt": 33, "iron": 8, "spore": 0, "fang": 0 } |
| 사냥 숲→얼어붙은 협곡→시간의 심연 | sword | 1 | cleared | 10 | 18 | 10.7 | boss:won@27s frost_stalker:won@32s eater:won@50s | 2 | 1 | 82 | { "pelt": 28, "iron": 8, "spore": 0, "fang": 0 } |
| 사냥 숲→얼어붙은 협곡→뒤틀린 성채 | sword | 1 | cleared | 10 | 22 | 12.8 | boss:won@27s frost_stalker:won@32s doom_executor:won@42s | 2 | 1 | 111 | { "pelt": 28, "iron": 13, "spore": 2, "fang": 0 } |
| 포자 정원→무너지는 광산→피의 사냥터 | sword | 1 | cleared | 10 | 20 | 33.8 | spore_matriarch:won@42s excavation_behemoth:won@33s blood_hunt_king:won@42s | 0 | 1 | 148 | { "pelt": 10, "iron": 10, "spore": 20, "fang": 0 } |
| 포자 정원→무너지는 광산→시간의 심연 | sword | 1 | cleared | 10 | 16 | 25.1 | spore_matriarch:won@42s excavation_behemoth:won@33s eater:won@44s | 2 | 1 | 50 | { "pelt": 3, "iron": 10, "spore": 20, "fang": 0 } |
| 포자 정원→무너지는 광산→뒤틀린 성채 | sword | 1 | cleared | 10 | 20 | 28.0 | spore_matriarch:won@42s excavation_behemoth:won@33s doom_executor:won@42s | 2 | 1 | 82 | { "pelt": 3, "iron": 17, "spore": 22, "fang": 0 } |
| 포자 정원→붉은 의식터→피의 사냥터 | sword | 1 | cleared | 10 | 20 | 22.2 | spore_matriarch:won@42s guardian:won@42s blood_hunt_king:won@46s | 0 | 1 | 103 | { "pelt": 9, "iron": 4, "spore": 27, "fang": 0 } |
| 포자 정원→붉은 의식터→시간의 심연 | sword | 1 | cleared | 10 | 17 | 13.5 | spore_matriarch:won@42s guardian:won@42s eater:won@48s | 2 | 1 | 148 | { "pelt": 3, "iron": 4, "spore": 27, "fang": 0 } |
| 포자 정원→붉은 의식터→뒤틀린 성채 | sword | 1 | cleared | 10 | 21 | 16.4 | spore_matriarch:won@42s guardian:won@42s doom_executor:won@39s | 2 | 1 | 42 | { "pelt": 3, "iron": 10, "spore": 31, "fang": 0 } |
| 포자 정원→얼어붙은 협곡→피의 사냥터 | sword | 1 | cleared | 10 | 20 | 23.6 | spore_matriarch:won@42s frost_stalker:won@33s blood_hunt_king:won@50s | 0 | 1 | 116 | { "pelt": 16, "iron": 7, "spore": 17, "fang": 0 } |
| 포자 정원→얼어붙은 협곡→시간의 심연 | sword | 1 | cleared | 10 | 17 | 15.0 | spore_matriarch:won@42s frost_stalker:won@33s eater:won@46s | 2 | 1 | 153 | { "pelt": 10, "iron": 7, "spore": 17, "fang": 0 } |
| 포자 정원→얼어붙은 협곡→뒤틀린 성채 | sword | 1 | cleared | 10 | 21 | 17.9 | spore_matriarch:won@42s frost_stalker:won@33s doom_executor:won@40s | 2 | 1 | 85 | { "pelt": 10, "iron": 14, "spore": 21, "fang": 0 } |

실행 벽시계: 1104.0초. 미구현 테마(보스 없음)는 후보에서 제외되어 표에 없다.
