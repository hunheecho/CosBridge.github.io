# 조사: 보스전의 나무 — 충돌체인가 장식인가, 그리고 왜 안 깨지는가

생성 `tools/probe_tree.gd`. **규칙·수치를 바꾸지 않았다**(읽기만 한다).
보스전 전장은 `scripts/rules/flow.gd:145`가 정하는 **clearing** 하나다(돌 2 · 나무 2).

## 1. 나무는 충돌체인가 장식인가 (사실 확인)

| 장애물 | 종류 | 중심 | 판정 r | 수관(그림) | 중심에 설 수 있나 | 표면 통과 시야 | 구실(role_of) |
|---|---|---|---:|---:|---|---|---|
| `rockA` | rock | (285, 220) | 42 | false | **아니오(막힌다)** | **막힌다** | cover |
| `rockB` | rock | (675, 380) | 42 | false | **아니오(막힌다)** | **막힌다** | cover |
| `treeA` | tree | (300, 420) | 26 | true | **아니오(막힌다)** | **막힌다** | cover |
| `treeB` | tree | (660, 180) | 26 | true | **아니오(막힌다)** | **막힌다** | cover |

`st.obstacles`에 실린 모든 항목은 `los_blocked` · `valid_pos` · `push_out` · `sweep_circle` · `beam_length` ·
`steer_dir`가 **종류를 가리지 않고** 같은 `r`로 본다(`scripts/rules/combat_state.gd`). 즉 나무도 돌과 똑같은 충돌체다.

## 2. 보스별 파괴 설정(data/boss_behavior.json)

| 보스 | 판정 모양 | 부술 수 있는 종류 | 파괴가 걸린 행동 |
|---|---|---|---|
| boss | land | ["rock", "tree"] | pounce |
| guardian | designate | ["rock", "tree"] |  |
| eater | mark | ["rock", "tree"] | mark |
| gate_warden | ram | ["rock", "tree"] | breach |
| spore_matriarch | spore | ["tree"] | shot |
| excavation_behemoth | pierce | ["rock", "tree"] | burrow |
| frost_stalker | lanes | ["rock", "tree"] | icepath |
| blood_hunt_king | arc | ["rock", "tree"] | claw |
| doom_executor | column | ["rock", "tree"] | slash |

## 3. 돌 뒤 / 나무 뒤에 각각 서 있었을 때(45초, 3단계, 시드 11)

| 보스 | 엄폐 종류 | 그 뒤에 설 자리 | 예고가 지목한 것 | 부순 것 | 서 있던 엄폐가 사라졌나 | 첫 예고 | 첫 파괴 | 닿는 칸 |
|---|---|---|---|---|---|---:|---:|---|
| boss | rock | (709, 439) | rock 1회 | rock(boss:pounce) | 예 | 2.4초 | 3.4초 | 7720 → 7889 |
| boss | tree | (274, 465) | tree 1회 | tree(boss:pounce) | 예 | 2.4초 | 3.4초 | 7720 → 7809 |
| guardian | rock | (709, 439) | rock 1회 | rock(guardian:designate) | 예 | 1.5초 | 2.6초 | 7720 → 7889 |
| guardian | tree | (274, 465) | tree 1회 | tree(guardian:designate) | 예 | 1.5초 | 2.6초 | 7720 → 7809 |
| eater | rock | (709, 439) | rock 1회 | rock(eater:mark) | 예 | 2.8초 | 3.6초 | 7720 → 7889 |
| eater | tree | (274, 465) | tree 1회 | tree(eater:mark) | 예 | 2.8초 | 3.6초 | 7720 → 7809 |
| gate_warden | rock | (709, 439) | rock 1회 | rock(gate_warden:breach) | 예 | 1.6초 | 4.1초 | 7720 → 7889 |
| gate_warden | tree | (274, 465) | tree 1회 | tree(gate_warden:breach) | 예 | 1.6초 | 4.2초 | 7720 → 7809 |
| spore_matriarch | rock | (709, 439) | — | **없다** | **아니오** | — | — | 7720 → 7720 |
| spore_matriarch | tree | (274, 465) | tree 1회 | tree(spore_matriarch:shot) | 예 | 4.2초 | 5.7초 | 7720 → 7809 |
| excavation_behemoth | rock | (709, 439) | rock 1회 | rock(excavation_behemoth:burrow) | 예 | 1.9초 | 2.3초 | 7720 → 7889 |
| excavation_behemoth | tree | (274, 465) | tree 1회 | tree(excavation_behemoth:burrow) | 예 | 1.9초 | 2.3초 | 7720 → 7809 |
| frost_stalker | rock | (709, 439) | rock 1회 | rock(frost_stalker:icepath) | 예 | 2.0초 | 2.5초 | 7720 → 7889 |
| frost_stalker | tree | (274, 465) | tree 1회 | tree(frost_stalker:icepath) | 예 | 2.0초 | 2.5초 | 7720 → 7809 |
| blood_hunt_king | rock | (709, 439) | rock 1회 | rock(blood_hunt_king:claw) | 예 | 3.6초 | 5.6초 | 7720 → 7889 |
| blood_hunt_king | tree | (274, 465) | tree 1회 | tree(blood_hunt_king:claw) | 예 | 3.7초 | 5.7초 | 7720 → 7809 |
| doom_executor | rock | (709, 439) | rock 1회 | rock(doom_executor:slash) | 예 | 3.8초 | 4.3초 | 7720 → 7889 |
| doom_executor | tree | (274, 465) | tree 1회 | tree(doom_executor:slash) | 예 | 3.8초 | 4.3초 | 7720 → 7809 |

- **나무 뒤에서 그 나무가 안 사라진 보스**: 없다
- **돌 뒤에서 그 돌이 안 사라진 보스**: spore_matriarch

## 4. 실제 전투(봇 `balanced` · 시드 [11, 12, 13] · 최대 70초) — 진짜 판에서 무엇이 부서지는가

| 보스 | 시드 | 막은 것(프레임 수) | 예고가 지목한 것 | **지목한 그것이 부서짐** | 부순 것 | 남은 장애물 | 최소치에 걸려 더 못 부순 시간 |
|---|---:|---|---|---|---|---|---:|
| boss | 11 | 돌 14 · 나무 479 | 돌 0 · 나무 1 | 돌 0 · 나무 1 | 돌 0 · 나무 1 | rockA(rock), rockB(rock), treeB(tree) | 0.0초 |
| boss | 12 | 돌 1156 · 나무 482 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | rockB(rock), treeB(tree) | 37.1초 |
| boss | 13 | 돌 222 · 나무 491 | 돌 0 · 나무 1 | 돌 0 · 나무 1 | 돌 0 · 나무 1 | rockA(rock), rockB(rock), treeB(tree) | 0.0초 |
| guardian | 11 | 돌 553 · 나무 633 | 돌 2 · 나무 0 | 돌 2 · 나무 0 | 돌 2 · 나무 0 | treeA(tree), treeB(tree) | 6.5초 |
| guardian | 12 | 돌 508 · 나무 496 | 돌 1 · 나무 0 | 돌 1 · 나무 0 | 돌 1 · 나무 0 | rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| guardian | 13 | 돌 633 · 나무 390 | 돌 1 · 나무 0 | 돌 1 · 나무 0 | 돌 1 · 나무 0 | rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| eater | 11 | 돌 2023 · 나무 887 | 돌 0 · 나무 1 | 돌 0 · 나무 1 | 돌 0 · 나무 1 | rockA(rock), rockB(rock), treeA(tree) | 0.0초 |
| eater | 12 | 돌 189 · 나무 2619 | 돌 0 · 나무 2 | 돌 0 · 나무 0 | 돌 1 · 나무 0 | rockA(rock), treeA(tree), treeB(tree) | 0.0초 |
| eater | 13 | 돌 467 · 나무 364 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | rockB(rock), treeB(tree) | 38.9초 |
| gate_warden | 11 | 돌 362 · 나무 406 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| gate_warden | 12 | 돌 407 · 나무 865 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | rockA(rock), treeA(tree) | 8.7초 |
| gate_warden | 13 | 돌 283 · 나무 42 | 돌 1 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| spore_matriarch | 11 | 돌 0 · 나무 638 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| spore_matriarch | 12 | 돌 83 · 나무 960 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| spore_matriarch | 13 | 돌 0 · 나무 710 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| excavation_behemoth | 11 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| excavation_behemoth | 12 | 돌 463 · 나무 271 | 돌 1 · 나무 0 | 돌 1 · 나무 0 | 돌 1 · 나무 0 | rockA(rock), treeA(tree), treeB(tree) | 0.0초 |
| excavation_behemoth | 13 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| frost_stalker | 11 | 돌 1385 · 나무 1149 | 돌 0 · 나무 2 | 돌 0 · 나무 2 | 돌 0 · 나무 2 | rockA(rock), rockB(rock) | 37.2초 |
| frost_stalker | 12 | 돌 1929 · 나무 1133 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | rockB(rock), treeA(tree) | 39.2초 |
| frost_stalker | 13 | 돌 817 · 나무 368 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | 돌 1 · 나무 1 | rockB(rock), treeA(tree) | 23.1초 |
| blood_hunt_king | 11 | 돌 113 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| blood_hunt_king | 12 | 돌 325 · 나무 0 | 돌 1 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| blood_hunt_king | 13 | 돌 1 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| doom_executor | 11 | 돌 0 · 나무 72 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| doom_executor | 12 | 돌 160 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |
| doom_executor | 13 | 돌 0 · 나무 208 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | 돌 0 · 나무 0 | rockA(rock), rockB(rock), treeA(tree), treeB(tree) | 0.0초 |

**합계** — 시선을 막은 프레임: 돌 12093 · 나무 13663 / 예고 지목: 돌 12 · 나무 12 / **지목한 그것이 부서짐: 돌 10 · 나무 10** / 실제 파괴: 돌 11 · 나무 10 · 최소치에 걸린 시간 합 190.8초

### 조준 정렬 전후(같은 시드·같은 봇) — 예고한 그 장애물이 실제로 부서졌는가

| 파괴 조준 정렬 | 예고 지목(돌/나무) | **지목한 그것이 부서짐(돌/나무)** | 일치율 |
|---|---|---|---:|
| 끔(개편 전) | 13 / 15 | 10 / 11 | 75% |
| **켬(지금)** | 12 / 12 | **10 / 10** | **83%** |

