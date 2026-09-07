# 3일차 성장 중단 vs 정상 성장 — 실력별 봇 비교 (godot-0.6.0)

생성: `tools/stop3_skill.gd`. 전략 gradual, 시작 sword, 시드 [1, 2, 3], 성장 중단일 3(그 날 이후 출격 없음·상점만), 경로 시드 추첨. 봇: ["balanced", "novice", "regular", "skilled"] — novice/regular/skilled는 **가상 조작 모델(사람 보정 미완료)**, balanced는 기존 정책(비교 기준). 봇 결과는 사람 난이도·밸런스 승인이 아니며, 봇이 이긴다고 체력·수치를 올리지 않는다(사용자 지시).

| 봇 | 시드 | 성장 | 결과 | 마지막 날 | Lv | 받은 피해(일반) | 휴식 | 패배 | 시간초과 | 전투분 | 보스(초·결과) | 보스 받은 피해 | 보스 패턴 상위 | 경로 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| balanced | 1 | 정상 | boss_failed | 7 | 10 | 466 | 0 | 4 | 1 | 8.3 | gate_warden:won@147s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s excavation_behemoth:lost@21s | 400 | gate_warden:guard 38 · excavation_behemoth:rockfall 12 · gate_warden:bolts 9 · excavation_behemoth:burrow 4 | 버려진 요새→무너지는 광산→피의 사냥터 |
| balanced | 1 | 3일 중단 | boss_failed | 7 | 2 | 300 | 0 | 3 | 0 | 1.2 | gate_warden:won@147s excavation_behemoth:lost@158s excavation_behemoth:lost@158s excavation_behemoth:lost@158s excavation_behemoth:lost@158s | 460 | excavation_behemoth:rockfall 112 · gate_warden:guard 38 · excavation_behemoth:summon 12 · gate_warden:bolts 9 | 버려진 요새→무너지는 광산→피의 사냥터 |
| balanced | 2 | 정상 | cleared | 10 | 22 | 260 | 1 | 1 | 3 | 18.9 | boss:won@28s excavation_behemoth:won@41s doom_executor:won@31s | 88 | boss:dash 4 · excavation_behemoth:burrow 4 · excavation_behemoth:rockfall 3 · excavation_behemoth:summon 3 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| balanced | 2 | 3일 중단 | boss_failed | 10 | 5 | 184 | 1 | 1 | 0 | 1.9 | boss:won@28s excavation_behemoth:won@58s doom_executor:lost@43s doom_executor:lost@43s doom_executor:lost@43s doom_executor:lost@43s | 496 | doom_executor:slash 20 · doom_executor:guard 12 · doom_executor:summon 8 · excavation_behemoth:rockfall 6 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| balanced | 3 | 정상 | cleared | 10 | 15 | 657 | 2 | 2 | 1 | 11.0 | boss:won@47s excavation_behemoth:won@65s eater:won@75s | 18 | excavation_behemoth:burrow 7 · boss:sweep 6 · eater:lanes 6 · boss:dash 4 | 사냥 숲→무너지는 광산→시간의 심연 |
| balanced | 3 | 3일 중단 | cleared | 10 | 6 | 330 | 2 | 0 | 0 | 2.4 | boss:won@47s excavation_behemoth:won@134s eater:won@190s | 71 | excavation_behemoth:rockfall 16 · eater:mark 13 · eater:wide 12 · excavation_behemoth:burrow 10 | 사냥 숲→무너지는 광산→시간의 심연 |
| novice | 1 | 정상 | cleared | 10 | 17 | 502 | 0 | 3 | 5 | 25.7 | gate_warden:won@112s excavation_behemoth:won@46s blood_hunt_king:won@41s | 57 | gate_warden:guard 21 · gate_warden:bolts 14 · excavation_behemoth:rockfall 8 · blood_hunt_king:claw 7 | 버려진 요새→무너지는 광산→피의 사냥터 |
| novice | 1 | 3일 중단 | boss_failed | 7 | 2 | 300 | 0 | 3 | 0 | 1.1 | gate_warden:won@112s excavation_behemoth:lost@213s excavation_behemoth:lost@202s excavation_behemoth:lost@118s excavation_behemoth:won@241s | 534 | excavation_behemoth:rockfall 137 · gate_warden:guard 21 · gate_warden:bolts 14 · excavation_behemoth:summon 12 | 버려진 요새→무너지는 광산→피의 사냥터 |
| novice | 2 | 정상 | cleared | 10 | 21 | 307 | 0 | 2 | 5 | 26.0 | boss:won@80s excavation_behemoth:won@54s doom_executor:won@49s | 33 | boss:sweep 9 · boss:dash 8 · excavation_behemoth:rockfall 6 · doom_executor:slash 5 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| novice | 2 | 3일 중단 | cleared | 10 | 3 | 148 | 0 | 1 | 2 | 8.6 | boss:won@80s excavation_behemoth:won@82s doom_executor:won@118s | 49 | doom_executor:slash 12 · boss:sweep 9 · excavation_behemoth:burrow 9 · doom_executor:guard 9 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| novice | 3 | 정상 | cleared | 10 | 14 | 770 | 3 | 3 | 3 | 17.5 | boss:won@55s excavation_behemoth:won@79s eater:won@116s | 107 | excavation_behemoth:rockfall 9 · boss:sweep 8 · eater:lanes 8 · eater:wide 8 | 사냥 숲→무너지는 광산→시간의 심연 |
| novice | 3 | 3일 중단 | cleared | 10 | 6 | 324 | 2 | 0 | 1 | 5.9 | boss:won@55s excavation_behemoth:won@118s eater:won@194s | 230 | eater:mark 20 · excavation_behemoth:rockfall 12 · excavation_behemoth:burrow 10 · eater:lanes 9 | 사냥 숲→무너지는 광산→시간의 심연 |
| regular | 1 | 정상 | cleared | 10 | 17 | 494 | 1 | 3 | 5 | 25.9 | gate_warden:won@102s excavation_behemoth:won@46s blood_hunt_king:won@43s | 120 | gate_warden:guard 21 · gate_warden:bolts 10 · excavation_behemoth:rockfall 8 · blood_hunt_king:claw 8 | 버려진 요새→무너지는 광산→피의 사냥터 |
| regular | 1 | 3일 중단 | boss_failed | 7 | 2 | 300 | 0 | 3 | 0 | 1.3 | gate_warden:won@102s excavation_behemoth:lost@219s excavation_behemoth:lost@111s excavation_behemoth:lost@122s excavation_behemoth:won@203s | 458 | excavation_behemoth:rockfall 122 · gate_warden:guard 21 · excavation_behemoth:summon 12 · gate_warden:bolts 10 | 버려진 요새→무너지는 광산→피의 사냥터 |
| regular | 2 | 정상 | cleared | 10 | 21 | 262 | 1 | 1 | 5 | 27.3 | boss:won@47s excavation_behemoth:won@52s doom_executor:won@59s | 18 | doom_executor:slash 6 · boss:dash 5 · boss:sweep 5 · excavation_behemoth:rockfall 5 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| regular | 2 | 3일 중단 | cleared | 10 | 4 | 84 | 1 | 0 | 2 | 9.0 | boss:won@47s excavation_behemoth:won@89s doom_executor:won@104s | 97 | excavation_behemoth:burrow 10 · doom_executor:slash 10 · doom_executor:guard 8 · excavation_behemoth:rockfall 6 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| regular | 3 | 정상 | cleared | 10 | 14 | 559 | 0 | 2 | 3 | 18.0 | boss:won@52s excavation_behemoth:won@65s eater:won@91s | 44 | boss:dash 7 · excavation_behemoth:rockfall 7 · eater:mark 7 · excavation_behemoth:burrow 6 | 사냥 숲→무너지는 광산→시간의 심연 |
| regular | 3 | 3일 중단 | cleared | 10 | 6 | 178 | 0 | 0 | 1 | 6.4 | boss:won@52s excavation_behemoth:won@115s eater:won@142s | 180 | excavation_behemoth:rockfall 20 · eater:lanes 11 · eater:mark 9 · boss:dash 7 | 사냥 숲→무너지는 광산→시간의 심연 |
| skilled | 1 | 정상 | cleared | 10 | 17 | 444 | 1 | 3 | 5 | 25.8 | gate_warden:won@103s excavation_behemoth:won@49s blood_hunt_king:won@46s | 83 | gate_warden:guard 30 · excavation_behemoth:rockfall 8 · blood_hunt_king:claw 8 · excavation_behemoth:summon 3 | 버려진 요새→무너지는 광산→피의 사냥터 |
| skilled | 1 | 3일 중단 | boss_failed | 10 | 2 | 300 | 0 | 3 | 0 | 1.3 | gate_warden:won@103s excavation_behemoth:won@227s blood_hunt_king:lost@70s blood_hunt_king:lost@59s blood_hunt_king:lost@64s blood_hunt_king:lost@59s | 619 | blood_hunt_king:claw 60 · excavation_behemoth:rockfall 43 · gate_warden:guard 30 · blood_hunt_king:summon 12 | 버려진 요새→무너지는 광산→피의 사냥터 |
| skilled | 2 | 정상 | cleared | 10 | 19 | 116 | 0 | 0 | 6 | 31.1 | boss:won@43s excavation_behemoth:won@70s doom_executor:won@42s | 31 | excavation_behemoth:rockfall 7 · excavation_behemoth:burrow 6 · boss:sweep 5 · boss:dash 4 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| skilled | 2 | 3일 중단 | cleared | 10 | 4 | 0 | 0 | 0 | 2 | 9.6 | boss:won@43s excavation_behemoth:won@83s doom_executor:won@150s | 65 | doom_executor:guard 14 · doom_executor:slash 13 · excavation_behemoth:rockfall 10 · excavation_behemoth:burrow 7 | 사냥 숲→무너지는 광산→뒤틀린 성채 |
| skilled | 3 | 정상 | cleared | 10 | 15 | 255 | 0 | 2 | 3 | 18.2 | boss:won@53s excavation_behemoth:won@75s eater:won@101s | 23 | eater:lanes 9 · excavation_behemoth:rockfall 7 · excavation_behemoth:burrow 7 · boss:sweep 6 | 사냥 숲→무너지는 광산→시간의 심연 |
| skilled | 3 | 3일 중단 | cleared | 10 | 6 | 34 | 0 | 0 | 1 | 6.4 | boss:won@53s excavation_behemoth:won@123s eater:won@140s | 58 | excavation_behemoth:rockfall 12 · excavation_behemoth:burrow 11 · eater:lanes 10 · eater:wide 8 | 사냥 숲→무너지는 광산→시간의 심연 |

## 봇별 요약 (평균)

| 봇 | 성장 | 완주 | 평균 Lv | 평균 받은 피해(일반) | 평균 휴식 | 평균 보스 받은 피해 | 평균 보스 초 |
|---|---|---|---|---|---|---|---|
| balanced | 정상 | 2/3 | 15.7 | 461 | 1.0 | 169 | 173 |
| balanced | 3일 중단 | 1/3 | 4.3 | 271 | 1.0 | 342 | 469 |
| novice | 정상 | 3/3 | 17.3 | 526 | 1.0 | 66 | 211 |
| novice | 3일 중단 | 2/3 | 3.7 | 257 | 0.7 | 271 | 511 |
| regular | 정상 | 3/3 | 17.3 | 438 | 0.7 | 61 | 186 |
| regular | 3일 중단 | 2/3 | 4.0 | 187 | 0.3 | 245 | 435 |
| skilled | 정상 | 3/3 | 17.0 | 272 | 0.3 | 46 | 194 |
| skilled | 3일 중단 | 2/3 | 4.0 | 111 | 0.0 | 247 | 391 |

읽는 법: '받은 피해'는 일반 전투 합계, '보스 받은 피해'는 관문 전투 합계(재도전 포함). 중단 빌드가 완주하면 후반이 봇에게 느슨하다는 뜻이지 사람에게도 그렇다는 뜻은 아니다. 완주 실패의 원인(보스 패배·시간 초과·정체)은 결과 열로 구분한다.
실행 벽시계: 910.2초.
