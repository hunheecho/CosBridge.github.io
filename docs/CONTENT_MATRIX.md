# 콘텐츠 대조표 (Godot 전체 이식)

작성 2026-09-07. 열: **설계**(사용자 합의 / 시험값(사용자) / 시험값(구현자) / 제안 / 폐기·대체) · **HTML**(ee10fc7: 구현 / 부분 / 미구현 / 오류) · **Godot**(착수 시점 0.3.1 → 이식 후 상태를 갱신) · **포함**(이번 이식 포함 여부·근거) · **검증**(테스트 ID 또는 방법).
규칙 본문은 정본(§열의 문서·코드)에 있고 여기서는 식별·상태만 적는다. Godot 열은 구현이 끝날 때마다 갱신한다(미구현 → 구현 → 검증).

## A. 자동기술 10종 (정본: `src/growth_data.js` PA.WEAPONS, GAME_SPEC §5.3~5.4, §19.8) — 슬롯 3·Lv5(배율 1/1.2/1.4/1.6/1.8)·개조 2·피해 = 기본×레벨×강화×숙련
| ID | 이름·방식·판정 범주 | 기본값(구현자 시험값) | 개조(이름: 동작) | 설계 | HTML | Godot(2026-09-07 갱신) | 포함 | 검증 |
|---|---|---|---|---|---|---|---|---|
| w:sword | 검 · 전방 부채꼴 · 직접 | 12/0.55s/95/110°/넉백 40, 시작 가능 | cross: 3번째마다 반대 방향 추가 · crescent: 초승달 검기 투사체(60%, 관통, 420/s, 사거리 120) · scar: 0.5초 뒤 같은 부채꼴 50% | 사용자 합의(D03), 수치 시험값 | 구현 | 구현(weapons.gd, 개조 3 포함; Lv1 = 0.3.1 기준 전투) | 포함 | HTML 50·51·167, Godot 검격 테스트 |
| w:spear | 관통창 · 직선 빔 · 직접 | 14/0.70/230/폭 44/넉백 30 (test03: 주기 0.85·근접 약화 45%×0.5, C9) | returning: 0.35초 뒤 끝점에서 반대 방향 재타격(개조 미적용) · split: 첫 적중 뒤 사선 검기 2(40%) · brand: 같은 적 4회 → 폭발 150% r60 | 합의(D09 문제 제기), 수치 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | HTML 52·38 |
| w:daggers | 쌍검 · 3연속 짧은 부채꼴(0.09s 간격) · 직접 | 6/0.75/62/타 3/70°/넉백 10 | bleed: 2초 출혈(초당 30%) · flank: 마지막 타 좌우 넓은 검격(×1.3 r, 반각 0.9) · pursuit: 처치 시 200 안 이웃에게 칼날 80% | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | dot 감사 11, F4 출처 |
| w:bow | 추적궁 · 추적 화살 · 투사체 | 11/0.8/320/속도 380/선회 4.0 | spread: 3발 부채꼴(±0.35) · ricochet: 160 안 1회 튕김 70% · pierce: 관통 | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 166 투사체·장애물 |
| w:hammer | 전투망치 · 원형 타격 · 직접 | 30/1.4/110/반지름 70/넉백 120 | shockwave: 전방 160×50 60%(비직접) · aftershock: 0.6초 뒤 50%(바닥) · pull: 타격 직전 90 안 작은 적 30px 당김 | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 명중·넉백 테스트 |
| w:blades | 회전 칼날 · 공전 살 판정(r×0.35~끝, 두께 14) · 직접 | 10/0.35(접촉 주기)/2개/r78/각속도 3.2/넉백 20 (v0.8 시험값, D09) | dual: 칼날 +1 · launch: 3초마다 부메랑 120%(240 안 대상, 520/s) · serrated: 1.5초 출혈 | 시험값(구현자, 조작감 미승인) | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | HTML 10·53·69·84 |
| w:orb | 번개 구체 · 연쇄(같은 적 1회) · 직접 | 9/0.9/200/도약 130/3회 | fork: 첫 대상에서 2갈래 · loop: 최초 대상 1회 복귀(명시 예외) · conduct: 표식 2초, 다른 무기 직접 타격 시 40% 폭발 r50 | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 연쇄 테스트 |
| w:frost | 서리 수정 · 냉기 탄환 · 투사체 · 시작 불가 | 7/1.0/260/속도 360/냉기 2.0 | fan: 3발(±0.44) · shatter: 파편 3(40%) · ground: 2초 냉기 영역 r40 | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 냉기 갱신 규칙 |
| w:ember | 불씨 정령 · 대상 근처 불길 · 바닥 · 시작 불가 | 5/1.6/260/r34/2.5s/틱 0.4 | scatter: 소형 3개 · trail: 착탄에서 3조각 · reignite: 불길 위 처치 +1.5초(상한 4.5) | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | HTML 65 |
| w:mine | 룬 지뢰 · 바닥 지뢰(최대 6, 준비 0.5) · 바닥 · 시작 불가 | 22/1.5/r70/트리거 30 | chain: 90 안 0.15초 연쇄 · frosttrap: 냉기 · lure: 70 안 작은 적 40px/s 당김 | 시험값 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 지뢰 1회 폭발 |
공용: 대상 = 표식 우선 → 가장 가까운 가림 없는 적, 사거리 안일 때만 발동, 첫 공격 0.25+i×0.2, 음수 잔여 이월, 대상 없으면 0.05초. 시작 기술 검·창·칼날(PA.STARTABLE), 나머지 4 시작 후보는 검증 메뉴.

## B. 공용 증강 9종 (PA.COMMONS, 3슬롯, 단계 상승은 슬롯 미소비) — 설계 사용자 합의(D03·D04), 수치 시험값
| ID | 이름 | 단계 | 동작·상한·전제 | HTML | Godot | 포함 | 검증 |
|---|---|---|---|---|---|---|---|
| c:wide | 넓어진 공격 | 2 (×1.25/1.5) | 각도·폭·반지름·트리거(검격은 반지름 ×(1+(w−1)/2)); 적용 무기 있어야 제시 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 147·148·159 |
| c:reach | 긴 사거리 | 2 (×1.25/1.5) | 사거리 있는 무기만(쌍검·칼날·지뢰 제외) | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 113 |
| c:frost | 얼음 파편 | 1 | 직접 적중 냉기 2.0×지속력, 냉기 처치 시 파편 6(피해 8×숙련, 냉기 재부여 없음) | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 55·66 |
| c:burn | 불붙은 공격 | 1 | 직접 적중 화상 2초·초당 4(중첩 없음, 시간 갱신) | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 11·67 |
| c:echo | 메아리 | 1 | 무기별 4번째 공격 0.2초 뒤 반복(재귀 없음) | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 53·66 |
| c:ember | 잔불 걸음 | 1 | 회피마다 불길 3(반지름 30×wide, 2.5s×지속력, 5), 장애물 안 생략 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 54·170 |
| c:flare | 불꽃 파열 | 1 | 불길 위 처치 시 r80 20×숙련 폭발; 전제 잔불 걸음 또는 불씨 정령 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 54·113 |
| c:saving | 시간 저축 | 1 | 감속장 안 처치마다 Q 재사용 −1(0 미만 불가) | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 42·29 |
| c:stasis | 정지된 칼날 | 1 | 감속장 안 직접 적중 흔적(최대 5), 종료 시 흔적×10×숙련 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 | 57·43 |

## C. 패시브 8종 (PA.PASSIVES, 4종·3레벨) — 합의, 수치 시험값
| ID | 효과/레벨 | 비고 | HTML | Godot | 포함 |
|---|---|---|---|---|---|
| p:vitality | 최대 체력 +20(현재 체력도) | 사망 되돌리지 않음 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:toughness | 직접 피해 −10% | 바닥 지속 피해 제외 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:mastery | 자동기술 피해 +10% | Q/E 제외, 추가 효과(파편·파열·흔적·공명)에는 적용 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:haste | 공격 주기 −8% | | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:mobility | 이동 +8% | 회피 거리·무적 불변 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:focus | Q/E 재사용 −10% | | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:exploit | 빈틈 배율 +0.25 | 기본 1.5 → 가산 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| p:persistence | 불길·냉기·화상·감속장 +20% | 적 장판 제외 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |

## D. 수동 기술 (PA.SKILLS) — 합의(D03), 수치 시험값. Q 재사용 = Lv(14/12/10)×집중×박자×샘, 최소 1
| ID | 기술 | 레벨 | 변형(이름: 동작) | HTML | Godot | 포함 | 검증 |
|---|---|---|---|---|---|---|---|
| q:slowfield | 감속장 r150·3s×지속력·적 속도·준비 40% | 재사용 14/12/10 | follow: 따라옴 · split: r100 ×2(자기+60 밖 최근접 적 위치) · echo: 종료 뒤 1.5초 70% 잔향 | 구현 | 구현(skills.gd Lv·변형 3, port_tests) | 포함 | 18·43·57 |
| e:gust | 돌풍 170×120 밀어내기(140+30/Lv), 보스는 피해만 | 8/7/6s, 10/14/18 | whirl: r130 전방위 · windpath: 3초 이동 +40% 영역 3 | 구현 | 구현(skills.gd, port_tests) | 포함 | 기술 발동 |
| e:bladestorm | 칼날 폭풍 r110 1.2s 0.2s마다 | 10/9/8, 8/11/14 | advancing: 150/s 전진 · condensed: r70 ×1.8 | 구현 | 구현(skills.gd, port_tests) | 포함 | |
| e:strike | 낙뢰 260 안 자동 대상(표식>정예>최근접) 0.25s 예고 r45 | 9/8/7, 40/55/70 | chain: 150 안 2대상 50% · storm: 2초 0.5초마다 30% r50 | 구현 | 구현(skills.gd, port_tests) | 포함 | |
| e:gravity | 중력핵 무리 중심 r140 1.2s 끌어모음 90×(1/1.3/1.6), 0.25s마다 dps | 12/11/10, 6/9/12 | collapse: 종료 폭발 ×3 r100 · orbit: 1초 추가 포획 | 구현 | 구현(skills.gd, port_tests) | 포함 | |
| e:ward | 수호 결계 4s 보호막 30/45/60 | 14/12/10 | fortress: r60 밀어내기 30/s · pulse: 0.8s마다 r110 8 피해 | 구현 | 구현(skills.gd, port_tests) | 포함 | 56(보호막 순서) |
E는 1개, 차 있으면 습득 카드 없음(교체는 상점). 일제 공격(보스 보상)은 E 사용 시 무기 1회씩(E 효과 재발동 없음). 시전자의 방패 훅(§H).

## E. 보스 희귀 보상 (PA.BOSS_REWARDS) — 합의(D05), 적용 조건은 구현자 시험값
| ID | 효과 | 후보 조건 | HTML | Godot | 포함 |
|---|---|---|---|---|---|
| r:resonance | 서로 다른 무기 3종 4초 안 같은 적 → 폭발 40×숙련 r70, 적당 6초 | 무기 ≥2 | 구현 | 구현(weapons.gd on_hit/on_kill·update_projectiles·skills.gd volley, 후보 규칙 port_tests) | 포함 |
| r:seed | 상태(냉기·화상·출혈) 적 처치 시 r90 전파(남은 시간 절반, 더 긴 쪽) | 상태 원천 보유 | 구현 | 구현(weapons.gd on_hit/on_kill·update_projectiles·skills.gd volley, 후보 규칙 port_tests) | 포함 |
| r:clone | 감속장 통과 아군 투사체 1회 복제 | 투사체 무기(homing·bolt·beam·crescent·launch) | 구현 | 구현(weapons.gd on_hit/on_kill·update_projectiles·skills.gd volley, 후보 규칙 port_tests) | 포함 |
| r:volley | E 사용 시 장착 무기 즉시 1회(공전·지뢰 제외) | E 보유 | 구현 | 구현(weapons.gd on_hit/on_kill·update_projectiles·skills.gd volley, 후보 규칙 port_tests) | 포함 |
| r:vigor / r:tempo | 범용: 최대 체력 +25(즉시 회복) / Q·E 재사용 −15% | 후보 <3일 때 채움, 가중치 0.5 | 구현 | 구현(weapons.gd on_hit/on_kill·update_projectiles·skills.gd volley, 후보 규칙 port_tests) | 포함 |
1·2보스 뒤 3택 1회(저장·재굴림 없음), 마지막 보스 뒤 없음. 후보 0개면 생략·기록.

## F. 몬스터 (PA.ENEMIES + enemies.js/boss*.js) — 역할 합의(D05·D13), 수치 시험값(구현자). 공통: 준비→확정→실행→빈틈, 접촉 피해 없음, 감속장은 준비·실행·빈틈(tf) 냉기는 이동만, 빈틈 피해 ×1.5
| ID | 이름·역할 | 핵심 행동(정본 GAME_SPEC §4) | 감속/넉백/지형 | 설계 | HTML | Godot | 포함 | 검증 |
|---|---|---|---|---|---|---|---|---|
| m:wolf | 늑대 · 돌진 습격 + 근접 물기 | **Godot 규칙(D35)**: ≤44 물기(0.2 추적+0.15 고정, 유효 0.1, 빈틈 0.4, 재사용 1.2) / 70~170 돌진(0.6+0.15, 256, 빈틈 0.9, 재사용 8, 첫 돌진 2~5초, 동시 2) | 재사용도 tf 적용, 돌진 중 넉백 무시, 겹침 해소 상한 | 시험값(사용자 채택 D33) | HTML은 옛 규칙 | **0.3.1 구현·72 테스트** | 포함(보존) | E1~E19 유지 |
| m:wolf_alpha | 늑대 우두머리 · 정예 | 체력 120·r22·물기/돌진 피해 18, 2연속 돌진(두 번째 준비 0.35), 빈틈 1.2, 4일차부터 체력 ×1.25 | 잠정: Godot 물기·돌진 재사용·동시 돌진 집계 적용(C2) | 합의(정예) | 구현(옛 늑대 규칙) | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함(잠정) | 정예 전멸·2연속 |
| m:archer | 궁수 · 원거리 압박 | 220~360 거리 유지, 조준 1.0(추적)→고정 0.25→화살 460/s 10→빈틈 1.3, 접근 0.3초 뒤 | 화살은 감속장 tf, 벽에서 소멸 | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 58 |
| m:spore | 포자 괴물 · 지역 통제 | 130 안 부풀기 0.9 → 구름 r80 5s 0.5s마다 6 → 빈틈 1.6, 사망 구름 r50 3s | 구름 틱 겹침 최대 1회 | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 49·58 |
| m:boar | 멧돼지 · 긴 직선 돌파 | 320 안·110 이상, 준비 0.9→고정 0.35→최대 520·700/s 16→빈틈 1.4, 장애물 충돌 비틀 2.4, 코앞 막힘 시 돌파 안 함, 110 안이면 물러남 | 돌파 중 넉백 무시, 예고=dashPath | 합의(역할) | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 70·71 |
| m:shieldbearer | 방패병 · 정면 방어 | 정면 120° 직접 공격 30%(준비·공격·빈틈 중 열림), 회전 2.2rad/s, 66 안 준비 0.7 → 돌진 18 + 64·100° 14 → 빈틈 1.3 | 넉백 50%, 바닥·기술·지속·추가 효과는 방패 무시 | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 72 |
| m:shaman | 주술사 · 치료(우선 처치) | 170~300 유지, 6초마다 280 안 가장 다친 아군 1.5초 시전 30% 치료(자기·주술사·보스 제외), 12 이상 한 방/넉백 20 이상 중단, 대상 없으면 0.9초 조준 저주 구슬 260/s 8(3초마다) | | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 73·74 |
| m:bomber | 폭탄 운반체 · 접근 후 폭발 | 90 안 정지 1.3초 → r95 22 자폭(처치·경험치 아님), 준비 중 처치 시 폭발 없음 | 넉백 시 원도 이동 | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 75 |
| m:burrower | 잠복충 · 자리 옮기기 | 240 안·재사용 6: 잠수 0.4→지하 0.7(260/s 추적, 직접·투사체 대상 아님)→출현 예고 0.6(지형 밖 보정, 재추적 없음)→r60 14→빈틈 2.0; 지상 44 물기(0.5 예고, 8, 빈틈 1.0) | 지하·예고 중 넉백 무시 | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 76 |
| m:spider | 거미 · 이동 경로 제한 | 5초마다 진행 방향 70 앞 0.7초 예고 → 거미줄 r55 6s(최대 4, 오래된 것 제거), 걷기 50%(회피 정상), 46 물기(0.5, 9, 빈틈 1.1) | | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 77 |
| m:frostcaller | 서리술사 · 순차 바닥 공격 | 200~330 유지, 5.5초마다 0.6초 시전: 위치+진행 방향 120 간격 3영역 r55 확정, 0.9/1.5/2.1초 뒤 순차 12(회피·보호 적용), 빈틈 1.4 | 영역 시간은 tf 무관 | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 78 |
| m:rogue | 쌍날 도적 · 근접 측면 접근 | 190 안 측면(오프셋 70) 접근, 54 안 베기1 예고 0.45(추적) → 50+r·100°·10 → 베기2 예고 0.35(±35° 보정) → 빈틈 1.6, 빈틈 뒤 측면 반전 | | 합의 | 구현 | 구현(enemies.gd·enemies_new.gd, 스모크 확인·규칙 테스트는 이후) | 포함 | 79 |
| s:altar_heal/hazard/reinforce | 제단 3종 · 구조물(체력 90, 경험치 0, 이동 없음) | 치료 4초/20/총 120/280 · 위험 5초 좌우 2개 r52 10 · 증원 6초 예산 5 동시 4 | 자동 공격 대상, 분리 시 상대만 밀림 | 합의(D14 임무) | 구현 | 구현(boss.gd·boss2.gd·objectives.gd, boss_tests 34) | 포함 | 141 |
| s:seal_device | 봉인 장치 ×3(체력 120, 경험치 0) | 6초 주기(첫 3초+1.5i) 플레이어 좌우 2개 r55 10, 동시 위험 상한 6 | | 합의(보스2) | 구현 | 구현(boss.gd·boss2.gd·objectives.gd, boss_tests 34) | 포함 | 32 |
| b:boss | 가시갈기 · 보스1(3일차 관문) | 체력 후보 1500/2400, 단계 70/35%, 휩쓸기(0.65/0.40 r145 120° 16 빈틈 1.5)·돌진(0.70/0.45 460·800 20 빈틈 2.2, 3단계 2연속 0.45/0.40 빈틈 3.0)·소환(1.6s 2마리 생존 4 간격 18 예고 0.9 등장 후 0.8 돌진 금지)·덮쳐찍기(2단계~, 0.50/0.65 도약 0.45 r105 18 빈틈 1.8, ≥300)·회복 구슬 15%·포효 0.9·넉백 20%·겹침 제한 | 감속장 전 단계, 도약 중 지형 무시 | 합의(D05·D12), 수치 시험값 | 구현 | 구현(boss.gd·boss2.gd·objectives.gd, boss_tests 34) | 포함 | 13~31 |
| b:guardian | 봉인 수호자 · 보스2(5일차) | 3000/5000, 단계 65/30%, 첫 공격 충격파, 무거운 휩쓸기(0.8/0.45 r165 150° 22 빈틈 1.8)·직선 충격파(0.6/0.35 폭70 길이520 속도900 18, 3단계 2발 ±20°)·봉인 장치 3·넉백 15%·아군 확정 중 1초 대기 | 파동은 투사체(감속장 tf) | 합의(R-BOSS-20) | 구현 | 구현(boss.gd·boss2.gd·objectives.gd, boss_tests 34) | 포함 | 32 |
| b:eater | 예언을 먹는 자 · 최종(7일차) | 3600/7000, 단계 60/30%, 첫 공격 두 줄 직선, 표식(0.5s 시전, 0.5초 이상 지난 위치 4/6/6개 r58, 1.2s 뒤 0.25s 간격 14, 빈틈 1.4, 표식 남아 있으면 새 패턴 없음)·두 줄 직선(0.7/0.3 폭90 길이720 16, +70° 0.5s 뒤, 빈틈 1.5)·광역(1.2/0.5 r230/270 24 빈틈 3.0)·소환(늑대·궁수·포자 2, 총 6 동시 3, 간격 16) | | 합의(R-BOSS-21) | 구현 | 구현(boss.gd·boss2.gd·objectives.gd, boss_tests 34) | 포함 | 33 |
표식 우선순위(사냥꾼의 표식은 v0.5 폐기 → 레거시 mark 필드만; 자동 대상 우선순위는 낙뢰 autoTarget: 표식>정예>최근접). PA.CONFIG.MARK는 레거시 → 미포함(폐기).

## G. 편성·지역·시간대 (world_data.js, GAME_SPEC §19.3) — 사용자 합의(D14·D15), 편성 내용은 구현자 첫 안
| ID | 내용 | 설계 | HTML | Godot | 포함 | 비고 |
|---|---|---|---|---|---|---|
| wd:slots | 새벽·아침·점심·오후·저녁, hours=남은 칸 | 합의 | 구현 | 미구현 | 포함 | |
| wd:schedule | 1 숲/능선, 2 숲/습지, 3 능선/굴, 4 습지/굴, 5 굴/심층, 6 시드 재방문/심층, 7 최종 | 합의(구현안) | 구현 | 미구현 | 포함 | 6일차 첫 칸 시드(run.schedule 저장) |
| wd:cost | 숲1 능선1 습지2 굴2 심층2, 더 깊이 +1, 휴식 1 | 사용자 지정 | 구현 | 미구현 | 포함 | |
| wd:day_waves | 지역×날짜 편성 5지역 13정의(그 이하 가장 가까운 날짜) | 구현자 첫 안 | 구현 | 미구현 | 포함(C4 변환) | 종류별 전체 수·동시 상한으로 변환 |
| wd:variants | 시간대 변주 9: 숲 새벽(마지막 웨이브 없음 ×0.8)/저녁(정예 ×1.3), 능선 오후(궁수+2 ×1.15)/저녁(도적+2 ×1.3), 습지 점심(상인 사건)/저녁(포자+2 ×1.3→C11), 굴 새벽/오후(늑대+3 ×1.15), 심층 저녁(정예+1 ×1.4→C11) | 시험값 | 구현(F2 도달 불가 2건) | 미구현 | 포함(도달 가능성 검사) | |
| wd:merchant | 2·4·6일차 점심부터: 장비 1(15% 할인) + 무료 휴식권 40 | 합의(D21) | 구현 | 미구현 | 포함 | |
| wd:regions | 지역 보상 금화 30~45/35~50/50~70/70~100/100~140, 재료(v0.8에서 임무는 3택 대체, 재료는 레거시 판매만) | 시험값 | 구현 | 미구현 | 포함 | 재료 시스템은 v0.8에서 축소(재료 판매만 남음) → 그대로 |
| wd:hp_mult | 지역 체력 후보 base/candE/A~D, 날짜 후보 none/dayA, 정예 4일차 ×1.25 | 후보(D07·D13) | 구현 | 미구현 | 포함(F3 후보, 기본 base·none, C5) | |
| wd:arena | 지역 전장: 기본 숲(장애물 없음), 공터(바위2·나무2), 기둥 숲(바위3·나무1); 배치안 classic/trial | 시험값 | 구현 | 0.3.1 공터만 | 포함(지역별 배치는 시험값: 숲=공터(D33), 능선=기둥, 습지=숲, 굴=기둥, 심층=공터) | 지형 검증 161~170 |

## H. 회차·경제 (run.js/sortie.js/flow.js/events.js, GAME_SPEC §19) — 사용자 합의 D14~D24, 세부 구현자
| ID | 내용 | HTML | Godot | 포함 | 검증 |
|---|---|---|---|---|---|
| run:new | 1일차 새벽 5칸 체력 100 금화 60 시작 자동기술 1(검/창/칼날) Q1 E 없음 장비 없음, trio 구조 | 구현 | 미구현 | 포함 | 154 |
| run:sortie | 카드 = 오늘 장소 2곳, 2일차부터 임무(첫 카드 확정, 둘째 50%), 3일차부터 위험 50%, 시드 확정, 하루 1회 완료 | 구현 | 미구현 | 포함 | 136·137 |
| run:actions | UI·봇 공용 행동 목록(출격 카드/휴식/하루 종료/상점/대장간/장비/보스 입장) | **오류 F1** | 미구현 | 포함(신설) | 회차 봇 경로 = UI 경로 |
| run:deep | 승리 뒤 더 깊이 1회 +1칸(임무 제외), 웨이브 +1·정예, 보상 ×1.5, 미리보기 4종(금화/장비/교체권/예약) 시드 확정(F5 수정), 승리 시 전리품에 얹음, 귀환만 | 구현(F5) | 미구현 | 포함 | 106 |
| run:return | 귀환 정산 1회(금화·장비→가방/중복 판매가·이용권·예약), 원정대 회복은 전투 승리마다(C7) | 구현(F7) | 미구현 | 포함 | 9·156 |
| run:defeat | 미정산 상실·남은 칸 0·다음 날 정상 체력, 장비 파괴 없음 | 구현 | 미구현 | 포함 | 5·156 |
| run:rest/endday | 휴식 1칸(가득해도), 하루 종료 남은 칸 소모·내일 미리보기, 관문 건너뛰기 불가 | 구현 | 미구현 | 포함 | 154 |
| run:mission | 정예 추적/제단 파괴/봉인 해제/포로 구출 규칙(objectives.js) + 위험 조건 3 | 구현 | 구현(objectives.gd, boss_tests) — 카드·예약 연결은 run 계층 | 포함 | 140~144·102 |
| run:steer | 성장 예약 단일, 덮어쓰기 금지(금화 대체), 소급 없음, 후보 없으면 금화, 구조는 서비스 3택 | 구현 | 미구현 | 포함 | 8·138·139 |
| run:events | 사건 6종(무기 제단·보급소·갇힌 상인·시간의 샘·봉인된 전리품·정찰자) 출격당 1회 시드, 규칙 events.js | 구현 | 미구현 | 포함 | 94~101 |
| run:services | 무료 휴식권·상인 할인권·개조 교체권·제시 재선택권 | 구현 | 미구현 | 포함 | 103 |
| run:boss | 관문 3·5·7일차, 입장 스냅샷(성장·체력·단계·금화·서비스·장비·가방·강화), 패배 복구, 승리 1회 기록·다음 단계 5칸·희귀 보상 보류, 최종 뒤 cleared | 구현 | 미구현 | 포함 | 6·34·35·118 |
| run:levelup | 정지·입력 차단·유효 후보 3(중복 대상 제거는 선택지 키 기준, F3 수정)·시드 결정·pendingOffer 저장·누적 처리·건너뛰기 금화 20 | 구현(F3) | 미구현 | 포함 | 7·110~115 |
| econ:shop | 하루 시드 재고 장비 2 + 기술 1(무기 180/E 180), 구매 장착/보관, 중복 불가, 판매 35/30/30, 할인권 | 구현 | 미구현 | 포함 | 1·150 |
| econ:swap | 교체 120+(Lv−1)×40+개조×80, 견적→새 기술→개조 선택→확인(공용 경고)→확정, 취소 원복 | 구현 | 미구현 | 포함 | 2·151 |
| econ:forge | 강화 90/160/240(보스 0/1/2 뒤) ×1.1/1.2/1.3, 개조 변경 140/교체권, E 변형 변경 140, 받지 않음 환불 | 구현 | 미구현 | 포함 | 3·152 |
| econ:equip | 장비 12종(§I) 슬롯 1, 가방, 무료 교체(거점), 탈착 회복 없음(hp 클램프), 회차 종료 소멸 | 구현 | 미구현 | 포함 | 4·82~93 |
| econ:mats | 재료 4종 판매(v0.8 잔존: 사건·지역 보상 재료) | 구현 | 미구현 | 포함(최소) | 153 |
| stats:dmg | 전투당 출처별 유효 피해·받은 피해·보유 시간, 보기 4종, DPS, 합계 검증, 저장 | 구현(F4) | 0.3.1 전투 내 집계만 | 포함(원천 키 확장) | 12·68 |
| save | `user://` 버전 저장, 새 회차·계속하기·저장 후 종료, 보류 선택·정산·사건·상점·보스 스냅샷 보존, 원자적 쓰기(임시 파일→교체), 손상·구버전 처리 | HTML localStorage v4 | 미구현 | 포함(새 형식) | 7·101·157 |

## I. 장비 12종 (PA.EQUIPMENT) — 사용자 채택 시험안(D20), 수치 사용자 지정
| ID | 이름 | 효과(대상 명시) | 훅 | HTML | Godot | 포함 |
|---|---|---|---|---|---|---|
| eq:hunter_sword | 사냥꾼의 검 | 정예·보스 직접 피해 +15% | damage_enemy | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:pioneer_spear | 개척자의 창 | 사거리·폭·반지름 +12%(칼날 안쪽 사각 없음) | build | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:ember_sword | 잔불검 | 자기 화상·출혈 지속 +25% | dot 부여 | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:chrono_staff | 시간술사의 지팡이 | 감속장 안 대상 직접 +20% | damage_enemy | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:traveler_armor | 여행자의 경갑 | 이동 +8% | build | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:guardian_armor | 수호자의 갑옷 | 전투 시작 보호막 15 | create | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:vitality_coat | 생명력의 외투 | 최대 체력 +20(회복 없음) | build/clamp | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:expedition_armor | 원정대의 갑옷 | 전투 승리마다 8(정산당 1회, C7) | 승리 정산 | 구현(귀환) | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함(합의 기준) |
| eq:iron_shield | 철벽 방패 | 직접 1타 ≥ 최대 20% → −25%(원래 피해로 판정) | player damage | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:emergency_shield | 비상 방패 | 체력 ≤30% 된 직후 보호막 20(전투 1회, 시작 시 30% 이하면 즉시) | player damage | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:caster_shield | 시전자의 방패 | E 사용 시 보호막 8 3초, 재사용 10초, 대체(누적 없음) | castE | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |
| eq:time_shield | 시간의 방패 | 감속장 안 공격자의 직접 피해 −20%(공격자 없는 지대·표식 제외, 투사체는 발사자) | player damage | 구현 | 구현(weapons.gd·growth.gd·build.gd·combat_state.gd, port_tests) | 포함 |

## J. 전투 공통 규칙 (combat.js) — 대부분 합의(GAME_SPEC §3·§13.3), 수치 시험값
| ID | 규칙 | HTML | Godot | 포함 |
|---|---|---|---|---|
| cb:step | 고정 1/120, 순서 플레이어→기술→적→목표→투사체→지역→구슬→상자→웨이브→효과→승패, 승리 우선 | 구현 | 0.3.1 유사 | 포함 |
| cb:terrain | 스윕 이동·미끄러짐·pushOut·losBlocked·validPos·nearestValidPos·beamLength·steerDir(0.8s 유지) | 구현 | 0.3.1 구현 | 유지 |
| cb:player_damage | 회피 무적(회피!)·피격 보호 0.6 공용·보호막 우선·강인함·철벽·시간의 방패·비상 방패·지역 틱 0.5s 최대 1회(보호 무시·무적 존중)·**유효/명목 분리(0.3.1)**·사망 승리 우선 | 구현(명목 집계 — Godot에서 수정됨) | 0.3.1 구현 | 포함 |
| cb:enemy_damage | 빈틈 배율(기본 1.5+빈틈 포착), 장비 배율, 방패병 정면, 반올림 0.1, 유효 집계, 넉백(보스 20/15%, 방패병 50%, 돌진·지하 무시), 냉기/화상/흔적/출혈 부여, onHit(전도·공명), 처치 효과(파편·파열·시간 저축·재점화·추격·씨앗·표식 이동) 적당 1회 | 구현 | 0.3.1 검격만 | 포함 |
| cb:zones | 포자·불길(0.4 틱)·냉기 바닥·폭풍·잔향·바람길·거미줄·서리 영역·위험(예고→무장) | 구현 | 구현(combat_state.gd, port_tests 지형·투사체·지역) | 포함 |
| cb:projectiles | 아군(추적·부메랑·복제·관통·도탄·파편·검광·칼날) / 적(화살·저주·충격파·파동), 장애물 우선 판정, 감속장 tf(적만) | 구현 | 구현(combat_state.gd, port_tests 지형·투사체·지역) | 포함 |
| cb:waves | 등장 경고 0.6, 가장자리 등장(플레이어 160 밖), 보급 상자(2번째 웨이브, 15~25) | 구현 | 0.3.1 진입 지점 8곳 | 포함(밀도 모델로 통합, 상자 유지) |
| cb:overlap | 동시 공격 제한(조우 지정 시), 보스전 늑대 동시 1·보스 확정 중 금지·0.15~0.5 지연 | 구현 | 0.3.1 늑대 돌진 2 | 포함(역할별 상한 C4) |
| cb:pause | 정지 중 입력 폐기, 재개 후 새 누름, 포커스 상실 | 구현 | 0.3.1 구현 | 유지 |
| cb:metrics | 종류별 등장·처치·준비·실행·공격 전 사망·TTK·패턴 횟수·명중·치료·중단·거미줄 | 구현 | 0.3.1 부분 | 포함 |

## K. UI·표현·소리 (screens.js/render.js/audio.js/glossary) — 합의(D11·D25), 임시 그래픽 요구(2026-09-07)
| ID | 내용 | HTML | Godot | 포함 |
|---|---|---|---|---|
| ui:title | 제목·새 회차(시작 기술 선택·밸런스/배치 후보는 검증 메뉴)·계속하기·검증 메뉴(기준 전투·시작 기술 비교·관문 빌드)·조작법·설정(음량) | 구현 | 0.3.1 첫 전투용 | 포함 |
| ui:base | 거점: 날짜·시간대·체력·금화·보스 카드·장소 카드 2(요약+상세)·휴식·하루 종료·상점·대장간·장비·기록·보류 3택 | 구현 | 미구현 | 포함 |
| ui:combat | HUD(체력/보호막·회피·Q·E 슬롯·목적·남은 적·보스 체력바·행동 문구), 예고 최상단, 상태 아이콘, F3 | 구현 | 0.3.1 부분 | 포함 |
| ui:levelup | 3택 카드(실제 파생값 설명·태그·슬롯), 건너뛰기, 재선택권 | 구현 | 미구현 | 포함 |
| ui:after | 전투 승리(보상·심층 미리보기·귀환)/패배/사건/보스 준비·패배·승리/회차 결과·통계(4 보기) | 구현 | 미구현 | 포함 |
| ui:shop | 상점·방문 상인·장비 비교·교체 흐름·대장간 | 구현 | 미구현 | 포함 |
| ui:glossary | 밑줄 용어 중첩 툴팁(클릭 고정·Esc·화면 안 배치·전투 중 고정 시 정지) 31+생성 항목 | 구현 | 미구현 | 포함 |
| gfx:temp | 플레이어 자세(대기·걷기·회피·휘두르기·피격), 적 12종 실루엣·준비/고정/실행/빈틈 구분, 보스 3, 바닥·바위·나무·그림자, 궤적·피격·사망, 감속장·상태 표시 | 구현(벡터) | 0.3.1 원·선 | 포함(자체 벡터, 외부 에셋 없음) |
| sfx | 타격·피격·기술·경고·회피·처치·감속장·보스·승패, 음량·음소거 저장 | 구현(WebAudio 합성) | 미구현 | 포함(AudioStreamGenerator 합성, 외부 파일 없음) |

## L. 봇·시뮬레이션·검증 도구
| ID | 내용 | HTML | Godot | 포함 |
|---|---|---|---|---|
| bot:combat | 정책 6(공격/균형/생존/제자리/이해/제자리 Q·E), 40ms 판단, 위협 도형, 목표 이동 | 구현 | 구현(bot.gd 6정책 + stand/active 보존, fps 무관 확인) | 포함(정책 이식 + 기존 유지) |
| bot:run | 회차 전략 7(쉬움 반복·점진·위험 임무·일찍 휴식·더 깊이·빌드 맞춤·시작 기술), 카드 선택 정책, 사건 정책, UI 행동 목록 사용 | 구현(F1) | 미구현 | 포함 |
| sim:tools | run_sim(전략×시드, 시간 계정), boss_sim/matrix, start_compare, density_report(유지), compare_scenario(유지) | 구현 | 0.3.1 2종 | 포함 |
| test | 규칙 72(유지) + HTML 170 재작성 + 통합·저장·완주 | 170 | 72 | 포함 |
| tools:capture | 캡처·영상·회피 시연 | — | 0.3.1 구현 | 유지·확장 |
