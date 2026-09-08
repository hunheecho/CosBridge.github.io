# 편성 계측(협공 3종 · 분대 · 등장 종류 수 · 특수 정예 결투)

- 실행 범위: **전체 실행(축을 줄이지 않았다)**

- 측정값이며 **사람이 승인한 균형값이 아니다.** 봇 정책 balanced · 시드 [1, 2] · 최대 300초 · 집중 경로(사냥 숲 → 얼어붙은 협곡 → 뒤틀린 성채)
- 실제 출격 경로를 그대로 지난다(data/themes.json → PRun.formation_waves → PFlow.encounter_opts).

## 1. 테마별 대표 협공 3개(자료)

| 테마 | ① | ② | ③ | 특수 정예 후보 |
|---|---|---|---|---|
| 사냥 숲 | **포위 탈출 · 늑대 + 멧돼지**(swarm)<br>늑대 62%, 멧돼지 22%, 궁수 16% | **막힌 길과 착지 예고 · 거미 + 두꺼비**(coop)<br>늑대 54%, 거미 36%, 궁수 10% | **빈틈과 접근 · 일반 정예 늑대 + 박쥐**(strong)<br>늑대 79%, 궁수 21% · 일반정예 wolf(미구현 → 일반 개체) | elite_fang · elite_archer |
| 버려진 요새 | **전열 우회 · 방패병 + 궁수**(coop)<br>방패병 34%, 궁수 30%, 쌍날 도적 36% | **사격대 접근 중 측면 대응 · 궁수 + 도적**(swarm)<br>쌍날 도적 55%, 궁수 33%, 방패병 12% | **정면에 머물지 않고 우회 · 일반 정예 방패병 + 폭탄**(strong)<br>방패병 45%, 폭탄 운반체 30%, 궁수 25% · 일반정예 shieldbearer(미구현 → 일반 개체) | elite_blademaster · elite_standard |
| 포자 정원 | **탈출 공간 확보 · 포자 + 거미**(coop)<br>늑대 50%, 포자 괴물 28%, 거미 22% | **회피 경로의 착지 예고 · 두꺼비 + 포자**(swarm)<br>늑대 61%, 포자 괴물 39% | **반격과 접근 처리 · 일반 정예 두꺼비 + 박쥐**(strong)<br>늑대 63%, 포자 괴물 38% · 일반정예 toad(미구현 → 일반 개체) | elite_plaguecaller · elite_miner |
| 붉은 의식터 | **화염 피하며 치료 끊기 · 도마뱀 + 주술사**(coop)<br>방패병 47%, 늑대 36%, 주술사 17% | **강적 집중과 치료사 우선 · 방패병 + 주술사**(strong)<br>늑대 44%, 방패병 42%, 주술사 14% | **회전 화염과 측면 · 도마뱀 + 도적**(swarm)<br>쌍날 도적 66%, 늑대 34% | elite_plaguecaller · elite_chainbreaker |
| 무너지는 광산 | **폭발 회피와 기습 위치 · 잠복충 + 폭탄**(coop)<br>잠복충 36%, 폭탄 운반체 36%, 쌍날 도적 28% | **돌진 회피 직후 근접 · 멧돼지 + 박쥐**(swarm)<br>멧돼지 52%, 쌍날 도적 30%, 궁수 18% | **화염 밖 공간 고르며 출현 추적 · 일반 정예 잠복충 + 도마뱀**(strong)<br>잠복충 61%, 폭탄 운반체 39% · 일반정예 burrower(미구현 → 일반 개체) | elite_miner · elite_blademaster |
| 얼어붙은 협곡 | **봉쇄와 사격 사이 통과 · 서리술사 + 궁수**(coop)<br>늑대 52%, 궁수 28%, 서리술사 20% | **전방 사격과 후방 착지 · 궁수 + 두꺼비**(swarm)<br>멧돼지 45%, 궁수 42%, 늑대 13% | **거미줄 제거하고 추격 · 일반 정예 궁수 + 거미**(strong)<br>궁수 36%, 거미 28%, 늑대 36% · 일반정예 archer(미구현 → 일반 개체) | elite_archer · elite_chainbreaker |
| 시간의 심연 | **안전 바닥 이동 · 잠복충 + 서리술사**(coop)<br>잠복충 44%, 서리술사 22%, 궁수 16%, 쌍날 도적 18% | **착지와 측면으로 바뀌는 방향 · 두꺼비 + 도적**(swarm)<br>쌍날 도적 56%, 포자 괴물 25%, 주술사 19% | **출현 추적과 접근 · 일반 정예 잠복충 + 박쥐**(strong)<br>잠복충 54%, 궁수 27%, 포자 괴물 19% · 일반정예 burrower(미구현 → 일반 개체) | elite_miner · elite_plaguecaller |
| 피의 사냥터 | **회피 후 반격 · 도적 + 박쥐**(coop)<br>쌍날 도적 63%, 늑대 37% | **지상 추격과 착지 · 늑대 + 두꺼비**(strong)<br>늑대 64%, 쌍날 도적 36% | **측면과 직선 · 도적 + 멧돼지**(strong)<br>쌍날 도적 40%, 멧돼지 28%, 늑대 20%, 궁수 12% | elite_fang · elite_archer |
| 뒤틀린 성채 | **전열과 회전 화염 사이 돌파 · 방패병 + 도마뱀**(coop)<br>방패병 60%, 궁수 40% | **강적 우회해 치료 차단 · 일반 정예 방패병 + 주술사**(strong)<br>방패병 44%, 쌍날 도적 30%, 주술사 14%, 궁수 12% · 일반정예 shieldbearer(미구현 → 일반 개체) | **사격·폭발·측면 사이 출구 · 궁수 + 폭탄 + 도적**(swarm)<br>궁수 34%, 폭탄 운반체 32%, 쌍날 도적 34% | elite_standard · elite_blademaster · elite_chainbreaker |

## 2. 총 등장 수·경험치 예산(개편 전과 같은가)

| 편성 | 장소 | 총 등장 수 | 경험치 예산(단위) | 고정 목표 | 차이 |
|---|---|---:|---:|---:|---:|
| t1a_wolves | p1 | 25 | 55.80 | 55.80 | -0.00 |
| t1a_wolves | p2 | 27 | 80.60 | 80.60 | -0.00 |
| t1a_boar | p1 | 25 | 70.20 | 70.20 | +0.00 |
| t1a_boar | p2 | 27 | 101.40 | 101.40 | +0.00 |
| t1a_mixed | p1 | 25 | 66.60 | 66.60 | -0.00 |
| t1a_mixed | p2 | 27 | 96.20 | 96.20 | +0.00 |
| t1a_risk | p1 | 26 | 84.00 | 84.00 | +0.00 |
| t1a_risk | p2 | 28 | 108.00 | 108.00 | +0.00 |
| t1b_shield_archer | p1 | 25 | 79.20 | 79.20 | +0.00 |
| t1b_shield_archer | p2 | 27 | 114.40 | 114.40 | +0.00 |
| t1b_archers | p1 | 25 | 73.80 | 73.80 | +0.00 |
| t1b_archers | p2 | 27 | 106.60 | 106.60 | +0.00 |
| t1b_wall | p1 | 25 | 84.60 | 84.60 | +0.00 |
| t1b_wall | p2 | 27 | 122.20 | 122.20 | +0.00 |
| t1b_risk | p1 | 26 | 111.00 | 111.00 | +0.00 |
| t1b_risk | p2 | 28 | 147.00 | 147.00 | +0.00 |
| t1c_spore_wolf | p1 | 25 | 59.40 | 59.40 | +0.00 |
| t1c_spore_wolf | p2 | 27 | 85.80 | 85.80 | +0.00 |
| t1c_spider_wolf | p1 | 25 | 56.70 | 56.70 | +0.00 |
| t1c_spider_wolf | p2 | 27 | 81.90 | 81.90 | -0.00 |
| t1c_spore_spider | p1 | 25 | 62.10 | 62.10 | -0.00 |
| t1c_spore_spider | p2 | 27 | 89.70 | 89.70 | +0.00 |
| t1c_risk | p1 | 26 | 93.00 | 93.00 | +0.00 |
| t1c_risk | p2 | 28 | 121.00 | 121.00 | +0.00 |
| t2a_shield_shaman | p1 | 45 | 109.20 | 109.20 | +0.00 |
| t2a_shield_shaman | p2 | 48 | 126.00 | 126.00 | +0.00 |
| t2a_elite_support | p1 | 46 | 135.30 | 135.30 | +0.00 |
| t2a_elite_support | p2 | 49 | 151.50 | 151.50 | +0.00 |
| t2a_red_wolves | p1 | 45 | 85.80 | 85.80 | -0.00 |
| t2a_red_wolves | p2 | 48 | 99.00 | 99.00 | -0.00 |
| t2a_risk | p1 | 46 | 148.30 | 148.30 | +0.00 |
| t2a_risk | p2 | 49 | 166.50 | 166.50 | +0.00 |
| t2b_bomb_rogue | p1 | 45 | 106.60 | 106.60 | +0.00 |
| t2b_bomb_rogue | p2 | 48 | 123.00 | 123.00 | +0.00 |
| t2b_burrow_shield | p1 | 45 | 130.00 | 130.00 | +0.00 |
| t2b_burrow_shield | p2 | 48 | 150.00 | 150.00 | +0.00 |
| t2b_bomb_burrow | p1 | 45 | 102.70 | 102.70 | +0.00 |
| t2b_bomb_burrow | p2 | 48 | 118.50 | 118.50 | +0.00 |
| t2b_risk | p1 | 46 | 134.00 | 134.00 | +0.00 |
| t2b_risk | p2 | 49 | 150.00 | 150.00 | +0.00 |
| t2c_frost_wolf | p1 | 45 | 83.85 | 83.85 | -0.00 |
| t2c_frost_wolf | p2 | 48 | 96.75 | 96.75 | +0.00 |
| t2c_boar_archer | p1 | 45 | 123.50 | 123.50 | +0.00 |
| t2c_boar_archer | p2 | 48 | 142.50 | 142.50 | +0.00 |
| t2c_frost_boar | p1 | 45 | 132.60 | 132.60 | +0.00 |
| t2c_frost_boar | p2 | 48 | 153.00 | 153.00 | -0.00 |
| t2c_risk | p1 | 46 | 154.80 | 154.80 | -0.00 |
| t2c_risk | p2 | 49 | 174.00 | 174.00 | +0.00 |
| t3a_archer_burrow | p1 | 70 | 136.00 | 136.00 | -0.00 |
| t3a_archer_burrow | p2 | 75 | 152.00 | 152.00 | +0.00 |
| t3a_spore_shaman | p1 | 70 | 150.45 | 150.45 | +0.00 |
| t3a_spore_shaman | p2 | 75 | 168.15 | 168.15 | -0.00 |
| t3a_mixed | p1 | 70 | 141.10 | 141.10 | -0.00 |
| t3a_mixed | p2 | 75 | 157.70 | 157.70 | -0.00 |
| t3a_risk | p1 | 72 | 201.10 | 201.10 | +0.00 |
| t3a_risk | p2 | 77 | 217.70 | 217.70 | +0.00 |
| t3b_wolf_boar | p1 | 70 | 132.60 | 132.60 | +0.00 |
| t3b_wolf_boar | p2 | 75 | 148.20 | 148.20 | +0.00 |
| t3b_rogue_alpha | p1 | 71 | 162.60 | 162.60 | +0.00 |
| t3b_rogue_alpha | p2 | 76 | 178.20 | 178.20 | +0.00 |
| t3b_wolf_archer | p1 | 71 | 137.10 | 137.10 | +0.00 |
| t3b_wolf_archer | p2 | 76 | 149.70 | 149.70 | +0.00 |
| t3b_risk | p1 | 72 | 202.80 | 202.80 | +0.00 |
| t3b_risk | p2 | 77 | 219.60 | 219.60 | -0.00 |
| t3c_shield_archer | p1 | 70 | 153.00 | 153.00 | -0.00 |
| t3c_shield_archer | p2 | 75 | 171.00 | 171.00 | -0.00 |
| t3c_shield_shaman | p1 | 70 | 173.40 | 173.40 | +0.00 |
| t3c_shield_shaman | p2 | 75 | 193.80 | 193.80 | +0.00 |
| t3c_frost_archer | p1 | 70 | 159.80 | 159.80 | +0.00 |
| t3c_frost_archer | p2 | 75 | 178.60 | 178.60 | +0.00 |
| t3c_risk | p1 | 72 | 213.00 | 213.00 | +0.00 |
| t3c_risk | p2 | 77 | 231.00 | 231.00 | +0.00 |

- 목표와 어긋난 편성: **0개**(0이어야 한다). 목표 = data/themes.json 의 xp_units(개편 전 값) + 정예 마리 수 × 정예 단위값.

## 3. 대표 전투 실측(집중 경로)

| 편성 | 막 | 시드 | 결과 | 시간 | 종류 수 | 동시 종류 최대 | 총 등장/실제 | 동시 최대 | 분대 투입(겹침) | 1~2마리 구간 | 자리 비고 대기 | 지원만 남은 시간 |
|---|--:|--:|---|--:|--:|--:|---|--:|---|--:|--:|--:|
| t1a_wolves | 1 | 1 | won | 37.0초 | 3 | 3 | 25/25 | 12 | 12(11) | 0.0초 | 20.3초 | 0.0초 |
| t1a_wolves | 1 | 2 | won | 31.0초 | 3 | 3 | 25/25 | 12 | 12(11) | 0.0초 | 16.3초 | 0.0초 |
| t1a_boar | 1 | 1 | won | 34.3초 | 3 | 3 | 25/25 | 12 | 12(11) | 0.0초 | 5.3초 | 4.7초 |
| t1a_boar | 1 | 2 | won | 29.8초 | 3 | 3 | 25/25 | 12 | 12(11) | 0.0초 | 6.7초 | 2.6초 |
| t1a_mixed | 1 | 1 | won | 29.6초 | 2 | 2 | 25/25 | 12 | 9(8) | 0.0초 | 4.8초 | 3.8초 |
| t1a_mixed | 1 | 2 | won | 32.3초 | 2 | 2 | 25/25 | 12 | 14(13) | 0.0초 | 6.7초 | 3.1초 |
| t2c_frost_wolf | 2 | 1 | won | 28.4초 | 3 | 3 | 45/45 | 14 | 18(17) | 0.0초 | 13.8초 | 0.0초 |
| t2c_frost_wolf | 2 | 2 | won | 30.6초 | 3 | 3 | 45/45 | 15 | 19(18) | 0.0초 | 16.7초 | 12.0초 |
| t2c_boar_archer | 2 | 1 | won | 38.7초 | 3 | 3 | 45/45 | 14 | 23(22) | 0.0초 | 30.8초 | 0.0초 |
| t2c_boar_archer | 2 | 2 | won | 40.7초 | 3 | 3 | 45/45 | 15 | 25(24) | 0.0초 | 31.8초 | 0.0초 |
| t2c_frost_boar | 2 | 1 | won | 27.4초 | 3 | 3 | 45/45 | 14 | 19(18) | 0.3초 | 19.7초 | 5.4초 |
| t2c_frost_boar | 2 | 2 | won | 29.3초 | 3 | 3 | 45/45 | 15 | 19(18) | 0.3초 | 16.5초 | 6.2초 |
| t3c_shield_archer | 3 | 1 | won | 59.5초 | 2 | 2 | 70/70 | 14 | 41(40) | 0.0초 | 52.8초 | 0.0초 |
| t3c_shield_archer | 3 | 2 | won | 60.0초 | 2 | 2 | 70/70 | 14 | 40(39) | 0.0초 | 52.4초 | 0.0초 |
| t3c_shield_shaman | 3 | 1 | won | 53.1초 | 4 | 4 | 70/70 | 18 | 35(34) | 0.0초 | 34.1초 | 0.0초 |
| t3c_shield_shaman | 3 | 2 | won | 45.2초 | 4 | 4 | 70/70 | 18 | 29(28) | 0.0초 | 27.9초 | 0.0초 |
| t3c_frost_archer | 3 | 1 | won | 36.7초 | 3 | 3 | 70/70 | 17 | 27(26) | 0.0초 | 26.3초 | 8.3초 |
| t3c_frost_archer | 3 | 2 | won | 42.7초 | 3 | 3 | 70/70 | 18 | 27(26) | 0.0초 | 26.7초 | 16.5초 |

### 구간별 등장 종류(첫 시드)

- **t1a_wolves** — open: wolf, archer · core: wolf, boar · late: boar, wolf
- **t1a_boar** — open: wolf, spider, archer · core: wolf, spider · late: wolf, spider
- **t1a_mixed** — open: wolf, archer · core: wolf · late: wolf, archer
- **t2c_frost_wolf** — open: wolf, frostcaller, archer · core: frostcaller, wolf, archer · late: wolf, archer
- **t2c_boar_archer** — open: boar, archer, wolf · core: wolf · late: archer, boar, wolf
- **t2c_frost_boar** — open: wolf, archer, spider · core: spider, wolf, archer · late: spider, wolf
- **t3c_shield_archer** — open: shieldbearer, archer · core: shieldbearer · late: shieldbearer, archer
- **t3c_shield_shaman** — open: shieldbearer, shaman, archer, rogue · core: rogue, shieldbearer · late: archer, rogue, shieldbearer, shaman
- **t3c_frost_archer** — open: bomber, archer, rogue · core: bomber, rogue, archer · late: archer, bomber, rogue

### 실제 분대 투입 순서(첫 시드, 앞 6개)

- **t1a_wolves**
  - 0.0초 · open · wolf:front, wolf:front, wolf:front, wolf:front, wolf:front · 이전 생존 0
  - 1.0초 · open · wolf:front, archer:support, wolf:front, archer:support · 이전 생존 5 · **겹침**
  - 2.0초 · core · wolf:front, wolf:front, boar:flank · 이전 생존 9 · **겹침**
  - 3.9초 · core · wolf:front · 이전 생존 11 · **겹침**
  - 4.9초 · late · boar:flank · 이전 생존 11 · **겹침**
  - 5.9초 · late · wolf:front · 이전 생존 10 · **겹침**
- **t1a_boar**
  - 0.0초 · open · wolf:front, wolf:front, wolf:front, spider:support, archer:support · 이전 생존 0
  - 1.0초 · open · wolf:front, spider:support, wolf:front, spider:support, archer:support · 이전 생존 3 · **겹침**
  - 2.0초 · core · wolf:front, spider:support · 이전 생존 7 · **겹침**
  - 4.1초 · core · wolf:front · 이전 생존 11 · **겹침**
  - 5.1초 · late · wolf:front · 이전 생존 11 · **겹침**
  - 6.1초 · late · spider:support · 이전 생존 11 · **겹침**
- **t1a_mixed**
  - 0.0초 · open · wolf:front, wolf:front, wolf:front, wolf:front, archer:support · 이전 생존 0
  - 1.0초 · open · wolf:front, wolf:front, wolf:front, archer:support · 이전 생존 5 · **겹침**
  - 2.0초 · open · wolf:front, archer:support · 이전 생존 9 · **겹침**
  - 3.0초 · core · wolf:front · 이전 생존 11 · **겹침**
  - 4.0초 · core · wolf:front · 이전 생존 11 · **겹침**
  - 5.0초 · late · wolf:front, wolf:front · 이전 생존 10 · **겹침**
- **t2c_frost_wolf**
  - 0.0초 · open · wolf:front, wolf:front, wolf:front, wolf:front, frostcaller:support, frostcaller:support · 이전 생존 0
  - 1.0초 · open · wolf:front, wolf:front, archer:support, wolf:front, archer:support · 이전 생존 4 · **겹침**
  - 2.0초 · open · wolf:front, archer:support, archer:support, wolf:front, frostcaller:support · 이전 생존 8 · **겹침**
  - 3.0초 · open · wolf:front, frostcaller:support, archer:support · 이전 생존 9 · **겹침**
  - 4.0초 · core · frostcaller:support, wolf:front, wolf:front · 이전 생존 10 · **겹침**
  - 5.0초 · core · wolf:front, archer:support · 이전 생존 12 · **겹침**
- **t2c_boar_archer**
  - 0.0초 · open · boar:front, boar:front, archer:support, boar:front, archer:support, archer:support · 이전 생존 0
  - 1.0초 · open · boar:front, archer:support, boar:front, archer:support · 이전 생존 6 · **겹침**
  - 2.0초 · open · archer:support, wolf:front · 이전 생존 10 · **겹침**
  - 3.0초 · open · wolf:front · 이전 생존 12 · **겹침**
  - 4.5초 · core · wolf:front, wolf:front · 이전 생존 13 · **겹침**
  - 5.5초 · late · archer:support · 이전 생존 13 · **겹침**
- **t2c_frost_boar**
  - 0.0초 · open · wolf:front, archer:support, archer:support, wolf:front, spider:support, archer:support · 이전 생존 0
  - 1.0초 · open · wolf:front, spider:support, archer:support, wolf:front, archer:support, spider:support · 이전 생존 6 · **겹침**
  - 2.0초 · open · wolf:front, spider:support, archer:support, wolf:front · 이전 생존 11 · **겹침**
  - 3.0초 · core · spider:support, spider:support, wolf:front, archer:support · 이전 생존 11 · **겹침**
  - 4.0초 · core · archer:support · 이전 생존 14 · **겹침**
  - 5.0초 · core · wolf:front, archer:support, wolf:front · 이전 생존 12 · **겹침**
- **t3c_shield_archer**
  - 0.0초 · open · shieldbearer:front, shieldbearer:front, shieldbearer:front, shieldbearer:front, archer:support · 이전 생존 0
  - 1.0초 · open · shieldbearer:front, shieldbearer:front, shieldbearer:front · 이전 생존 4 · **겹침**
  - 2.0초 · open · archer:support, archer:support · 이전 생존 8 · **겹침**
  - 3.0초 · open · archer:support, archer:support · 이전 생존 8 · **겹침**
  - 4.0초 · open · shieldbearer:front, shieldbearer:front, archer:support, archer:support · 이전 생존 8 · **겹침**
  - 5.0초 · open · shieldbearer:front, shieldbearer:front · 이전 생존 10 · **겹침**
- **t3c_shield_shaman**
  - 0.0초 · open · shieldbearer:front, shieldbearer:front, shieldbearer:front, shieldbearer:front, shaman:support · 이전 생존 0
  - 1.0초 · open · shieldbearer:front, shieldbearer:front, shieldbearer:front, archer:support · 이전 생존 5 · **겹침**
  - 2.0초 · open · rogue:flank, rogue:flank, shaman:support · 이전 생존 9 · **겹침**
  - 3.0초 · open · rogue:flank, shaman:support, archer:support · 이전 생존 10 · **겹침**
  - 4.0초 · open · shieldbearer:front, rogue:flank, archer:support · 이전 생존 13 · **겹침**
  - 5.0초 · open · shaman:support, rogue:flank, shaman:support, archer:support · 이전 생존 13 · **겹침**
- **t3c_frost_archer**
  - 0.0초 · open · bomber:front, archer:support, archer:support, bomber:front, bomber:front · 이전 생존 0
  - 1.0초 · open · bomber:front, archer:support, archer:support, rogue:flank, rogue:flank · 이전 생존 5 · **겹침**
  - 2.0초 · open · bomber:front, archer:support, archer:support, rogue:flank, bomber:front · 이전 생존 7 · **겹침**
  - 3.0초 · open · bomber:front, archer:support, rogue:flank, rogue:flank · 이전 생존 12 · **겹침**
  - 4.0초 · open · bomber:front, rogue:flank · 이전 생존 12 · **겹침**
  - 5.0초 · core · bomber:front, rogue:flank, bomber:front · 이전 생존 14 · **겹침**

## 3b. 막별 정예 조우 기회(실제 카드 생성기 PSortie.cards_for)

카드 수이지 강제 조우 수가 아니다 — 플레이어가 그 카드를 고르면 만난다.

| 막 | 테마 | 카드 | 특수 정예(편성 안) | 특수 정예(결투) | 결투 종류 | 일반 정예 |
|--:|---|--:|--:|--:|---|--:|
| 1 | 사냥 숲 | 12 | 2 | 6 | 정예 궁수 · 피의 송곳니 | 5 |
| 1 | 버려진 요새 | 12 | 2 | 6 | 군단 기수 · 정예 검사 | 6 |
| 1 | 포자 정원 | 12 | 2 | 6 | 균열 채굴자 · 역병 조율사 | 6 |
| 2 | 붉은 의식터 | 12 | 10 | 4 | 사슬 집행자 · 역병 조율사 | 0 |
| 2 | 무너지는 광산 | 12 | 8 | 4 | 정예 검사 · 균열 채굴자 | 1 |
| 2 | 얼어붙은 협곡 | 12 | 8 | 4 | 사슬 집행자 · 정예 궁수 | 1 |
| 3 | 시간의 심연 | 12 | 6 | 5 | 역병 조율사 · 균열 채굴자 | 3 |
| 3 | 피의 사냥터 | 12 | 10 | 5 | 정예 궁수 · 피의 송곳니 | 0 |
| 3 | 뒤틀린 성채 | 12 | 6 | 5 | 정예 검사 · 사슬 집행자 · 군단 기수 | 1 |

- '일반 정예' 열은 그 편성에 일반 정예 자리가 있는 카드 수다. 지금은 `<종류>_elite` 가 카탈로그에 없어 **실제로는 일반 개체로 나온다**(§1 표의 '미구현' 표시).

## 4. 특수 정예 결투(전환·일반 증원 0·고유 소환)

| 테마 | 편성 | 결투 상대 | 결과 | 결투 시간 | 거친 단계 | 결투 중 일반 증원 | 고유 소환 | 처치 후 정리 |
|---|---|---|---|--:|---|--:|--:|--:|
| 사냥 숲 | t1a_wolves | 피의 송곳니 | won | 12.5초 | cleanup, growth, intro, duel, done | 0 | 0 | 0 |
| 사냥 숲 | t1a_wolves | 정예 궁수 | won | 18.9초 | cleanup, growth, intro, duel, done | 0 | 0 | 0 |
| 얼어붙은 협곡 | t2c_frost_wolf | 정예 궁수 | won | 21.7초 | cleanup, growth, intro, duel, done | 0 | 0 | 0 |
| 얼어붙은 협곡 | t2c_frost_wolf | 사슬 집행자 | won | 14.6초 | cleanup, growth, intro, duel, done | 0 | 0 | 0 |
| 뒤틀린 성채 | t3c_shield_archer | 군단 기수 | won | 27.8초 | cleanup, growth, intro, duel, done | 0 | 6 | 2 |
| 뒤틀린 성채 | t3c_shield_archer | 정예 검사 | won | 59.7초 | cleanup, growth, intro, duel, done | 0 | 0 | 0 |
| 뒤틀린 성채 | t3c_shield_archer | 사슬 집행자 | won | 35.6초 | cleanup, growth, intro, duel, done | 0 | 0 | 0 |

- '결투 중 일반 증원'은 **0이어야 한다**(일반 편성의 추가 증원 금지).
- 고유 소환은 특수 정예에게 귀속되며 경험치·금화를 주지 않는다. 처치 후 남은 소환물은 추가 보상 없이 정리된다.

## 5. 분대 편성 전후 비교(같은 코드·같은 시드·같은 편성, 분대만 끄고 켠다)

이전 커밋(종류별 상한을 동시 상한 비례로)의 개선과 **분대 편성의 개선을 가르기 위한** 대조군이다.

| 편성 | 막 | 1~2마리 구간(전→후) | 지원만 남은 시간(전→후) | 자리 비고 대기(전→후) | 동시 최대(전→후) | 전투 시간(전→후) |
|---|--:|---|---|---|---|---|
| t1a_wolves | 1 | 0.0초 → 0.0초 | 0.0초 → 0.0초 | 11.8초 → 20.3초 | 12 → 12 | 52.5초 → 37.0초 |
| t1a_boar | 1 | 0.0초 → 0.0초 | 4.9초 → 4.7초 | 6.3초 → 5.3초 | 12 → 12 | 30.8초 → 34.3초 |
| t1a_mixed | 1 | 0.0초 → 0.0초 | 0.0초 → 3.8초 | 6.8초 → 4.8초 | 12 → 12 | 27.6초 → 29.6초 |
| t2c_frost_wolf | 2 | 0.1초 → 0.0초 | 0.0초 → 0.0초 | 15.1초 → 13.8초 | 15 → 14 | 31.4초 → 28.4초 |
| t2c_boar_archer | 2 | 0.0초 → 0.0초 | 0.0초 → 0.0초 | 35.0초 → 30.8초 | 14 → 14 | 45.0초 → 38.7초 |
| t2c_frost_boar | 2 | 0.0초 → 0.3초 | 7.3초 → 5.4초 | 19.9초 → 19.7초 | 15 → 14 | 29.9초 → 27.4초 |
| t3c_shield_archer | 3 | 0.0초 → 0.0초 | 0.0초 → 0.0초 | 53.7초 → 52.8초 | 14 → 14 | 61.6초 → 59.5초 |
| t3c_shield_shaman | 3 | 0.0초 → 0.0초 | 0.0초 → 0.0초 | 35.5초 → 34.1초 | 18 → 18 | 48.9초 → 53.1초 |
| t3c_frost_archer | 3 | 0.1초 → 0.0초 | 9.7초 → 8.3초 | 26.3초 → 26.3초 | 18 → 17 | 35.6초 → 36.7초 |

