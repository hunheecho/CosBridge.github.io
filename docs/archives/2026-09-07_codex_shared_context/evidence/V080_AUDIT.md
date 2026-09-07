# v0.8.0 독립 검수 — 2026-09-07

검수 커밋: 7ec93cddae413d9c8d5bcbbe8a244e40f86ae903 (사용자 보고의 회귀 로그 커밋).
원본 저장소 파일·커밋 변경 없음. 원본 작업 트리 변경 없음, 관련 구현 러너 없음 확인 후 별도 스냅샷에서 실행했다.
별도 검수 자료만 이 보고서 폴더에 생성했다.

## 결론

기능이 추가된 것은 확인했지만 “합의 사항 모두 구현 및 실제 실행 확인, 충돌 없음”은 성립하지 않는다.
특히 회차 시뮬레이터가 화면의 출격 제한과 임무를 우회하므로, 성장·경제·정상 관문 빌드라는 전제부터 다시 검증해야 한다.
먼저 규칙·측정 오류를 고친 뒤 밸런스 수치를 판단할 것을 제안한다.

## 확인했고 문제없는 항목

- node --test test/*.test.js: tests 169 / pass 169 / fail 0, 종료코드 0. 독립 실행.
- index.html + style.css + src/*.js를 빌드 규칙대로 메모리에서 조합한 결과와 dist/prophecy_single.html이 정확히 같음. 저장소 안 빌드 파일을 재생성하지 않음.
- 배포 단일 HTML을 별도 localhost 주소에서 브라우저로 열어 v0.8.0 및 기본 test03 표시 확인.
- 정상 새 회차: 회전 칼날 Lv1, Q Lv1, 장비 없음, 100HP, 60금, 1일차 5칸 확인.
- 실제 첫 전투를 상태 조작 없이 실행: 회전 칼날, 이동/Q/E 없이 승리. 5마리 처치 / 전투 15초 / 피해 96 / 처치 경험치 9 + 지역 3. 이는 한 시드의 정지 행동 관측이며 사람 조작감 또는 무기 균형 판정이 아니다.
- 귀환: 60→88금, 체력 4 유지, 경험치 12, 피해 통계 1전/225 확인.
- 하루 종료 미리보기, 2일차 정상 체력, 휴식에 따른 시간 진행, 점심 상인 등장 및 저녁까지 유지 확인.
- 보고서의 특정 보스 신호를 30전의 별도 헤드리스 시험으로 확인:
  - 7선택 지속·장판 프리셋: 가시갈기 제자리 Q/E 3/3 승리, 20.4~23.2초.
  - 기록된 3일차 중단 seed1 빌드 Lv10: 최종 보스 기본 회피 3/3 승리, 55.6~59.6초, 받은 피해 16~24.
  - 같은 Lv10 빌드 제자리 Q/E: 3/3 패배.
  - 정상 성장 seed1 프리셋: 수호자·최종 보스 제자리 Q/E 각각 3/3 패배.
- 위 관문 빌드는 기존 덤프를 사용했다. 아래 F1 때문에 실제 정상 플레이로 얻을 수 있는 빌드인지까지 승인한 것이 아니다.
- 브라우저 검수 서버와 탭 종료 완료.

## 재현 자료

아래는 실제 실행 명령을 옮겨 쓸 수 있도록 경로만 바꾼 표기다. 이 evidence 폴더에서 실행하고, 꺾쇠 경로는 검수 커밋 7ec93cd의 실제 소스 폴더로 대체한다. 결과는 스크립트 폴더에 저장된다. 원본 소스 전체는 이 묶음에 포함하지 않았다.

    node "audit_probe.cjs" "<path-to-prophecy_action_prototype-at-7ec93cd>"
    node "sim_check.cjs" "<path-to-prophecy_action_prototype-at-7ec93cd>"

- [규칙 재현 결과](audit_evidence.json)
- [회차 시뮬레이터 경로 추적](sim_route_trace.json)
- [독립 회차 실행 결과](run_gradual.md)
- [보스 30전 원시 결과](boss_check.json)
- [규칙 재현 스크립트](audit_probe.cjs)
- [회차 경로 계측·보스 재현 스크립트](sim_check.cjs)

sim_check는 원본 run_sim.js를 읽어 실행한다. 함수 래퍼는 출격 경로만 기록하며 결과나 난수를 바꾸지 않는다.
출력 경로만 저장소 밖으로 지정했다.

## 지적 항목 — 심각도 순

### F1 [P1] 회차 봇이 실제 UI와 다른 출격을 실행한다

1. 위치:
   - [tools/run_sim.js:100](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/tools/run_sim.js#L100): 임무 정책 외의 경우 Run.startSortie를 직접 호출한다.
   - [src/sortie.js:44](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/sortie.js#L44): UI의 canStart는 완료 카드를 차단한다.
   - [src/sortie.js:47](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/sortie.js#L47): UI 경로는 카드의 임무·위험 조건을 출격에 반영한다.
   - [src/screens.js:168](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/screens.js#L168) / [src/main.js:217](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/main.js#L217): 실제 장소 버튼은 Sortie.start 경로.
2. 대조 원문:
   - [src/flow.js:1](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/flow.js#L1): “조우 생성·정산·다음 선택을 브라우저(main.js)와 헤드리스 시뮬레이터(tools/run_sim.js)가 같은 함수로 처리한다.”
   - 전달한 지시문: “임무가 있다면 해당 장소의 현재 목적에 붙인다.”
3. 재현:
   - seed1, 2일차 숲의 카드 목적은 altars(제단 파괴).
   - Sortie.start → mission=true, objective=altars.
   - Run.startSortie → mission=false, objective=clear.
   - 임무 완료 뒤 UI canStart=false지만 Run.canSortie=true.
   - 원본 회차 시뮬레이션 점진 전략 seed1을 계측 실행: 실제 UI 목적과 다른 출격 11회. 2일차 숲을 새벽~저녁 5회 모두 일반 전멸전으로 실행했다.
   - 출력: UI route mismatch count 11.
4. 제안:
   - 모든 전략이 동일한 “현재 화면에서 선택 가능한 행동” 목록을 사용하게 수정.
   - 임무 완료 후 일반 출격을 계속 허용할 설계라면 UI와 명세도 함께 일치시킬 것. 봇에만 우회 경로를 제공하면 안 된다.
   - 수정 후 성장·경제·휴식·관문 빌드 덤프 및 이 덤프를 이용한 보스 비교를 다시 측정.
   - 현재 결과가 모두 무의미하다는 뜻은 아니다. 고정 빌드 전투 측정은 그 조건에서 유효하지만 “정상 회차 성장”이라는 설명은 재검증 필요.

### F2 [P2] 습지·심층의 저녁 이벤트에 정상 진입할 수 없다

1. 위치: [src/world_data.js:9](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/world_data.js#L9), [src/world_data.js:54](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/world_data.js#L54), [src/run.js:93](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/run.js#L93).
2. 대조 원문:
   - [docs/GAME_SPEC.md:380](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/docs/GAME_SPEC.md#L380) 부근 §19.3: “습지 점심 상인 사건/저녁 포자”, “심층 저녁 심연(정예 +1, ×1.4)”.
   - 같은 절: “남은 칸 < 비용이면 출격 불가.”
3. 재현:
   - 습지와 심층 비용 2칸 / 저녁 남은 1칸 → canStart=false.
   - 브라우저에서도 2일차에 휴식으로 저녁까지 진행: “저녁 포자”와 금화 65~91이 표시되지만 버튼은 “시간 부족 (2칸 필요)”로 비활성.
   - 오후 출발은 오후 편성으로 고정되므로 저녁 이벤트를 경험하는 대체 경로도 아니다.
4. 제안:
   - 해당 이벤트를 출격 가능한 시간대로 이동하거나, 표시된 출격 비용·일정 설계를 일관되게 조정.
   - 시간대별 데이터 존재 검사 대신, 그 시간대의 실제 진입 가능성을 검증.

### F3 [P2] 개조 예약이 유효한 3개 후보를 1개로 줄인다

1. 위치: [src/growth.js:103](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/growth.js#L103), [src/growth.js:119](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/growth.js#L119).
2. 대조 원문:
   - [docs/GAME_SPEC.md:392](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/docs/GAME_SPEC.md#L392) 부근 §19.5: “레벨업은 정지 + 입력 차단 + 유효 후보 3개 + 저장.”
   - 전달한 지시문: “한 기술의 개조만 유효할 때 서로 다른 유효 개조를 제시하지 않는 문제”를 회귀 확인.
3. 재현:
   - 검 Lv1 하나 보유, 개조 0개, weapon_mod 예약, 자연 레벨업 1회.
   - 유효 후보: sword:cross / sword:crescent / sword:scar.
   - 실제 제시: sword:crescent 하나.
   - 일반 레벨업 풀에서 같은 kind와 id를 중복 제거하기 때문에 서로 다른 개조도 제거된다. 임무 풀 예외는 예약된 자연 레벨업에 적용되지 않는다.
4. 제안:
   - 중복은 선택지의 전체 고유 키로 판단하거나, 개조 예약에서 같은 기술의 서로 다른 개조를 허용.
   - 위 한 기술·세 개조 조건을 회귀 사례로 추가.

### F4 [P2] 출혈의 원래 기술을 잃고, 늦게 획득한 효과의 DPS 분모도 틀린다

1. 위치: [src/combat.js:76](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/combat.js#L76), [src/combat.js:328](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/combat.js#L328), [src/combat.js:572](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/combat.js#L572), [src/stats.js:10](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/stats.js#L10), [src/stats.js:30](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/stats.js#L30).
2. 대조 원문:
   - 전달한 지시문: “직접 피해 / 화상·출혈 / 장판 / 추가 발동의 출처 추적.”
   - “런 중간에 얻은 기술에 획득 전 시간을 분모로 넣지 않음.”
   - [docs/ASSUMPTIONS.md:179](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/docs/ASSUMPTIONS.md#L179): “피해 통계 DPS 분모는 \"기술 보유 실제 전투 시간\". 전투 중 얻은 기술은 그 시점부터 센다.”
3. 재현:
   - 쌍검이 출혈을 부여해도 적의 bleed 상태는 t/dps만 저장한다. 소유 기술 ID가 없다.
   - 피해는 weapon:daggers와 dot:bleed로 분리되며, 쌍검 출혈인지 회전 칼날 출혈인지 복구할 수 없다.
   - 전투 9초 후 쌍검을 얻고 1초 동안 피해 발생:
     - 쌍검 직접 피해: 15 / 보유 시간 1초 / DPS 15.
     - 같은 쌍검의 출혈: 2.6 / 보유 시간 10초 / DPS 0.3.
   - 기술 획득 전 9초가 출혈 분모에 들어간다.
4. 제안:
   - 지속 효과에 적용 원천을 보존하고, 갱신·대체·전파 시 원천 승계 규칙을 정의.
   - 기술별 총 피해에 그 기술의 파생 피해를 포함하고 상세 분류를 중복 집계하지 않게 구성.
   - 공용 효과를 별도 집계해도, 해당 효과의 유효 보유 시간을 기록해야 한다.
   - Stats.verify의 합계 일치만으로 출처·시간의 정확성을 증명하지 말 것.

### F5 [P2] 심층 장비 보상이 시드가 달라도 같은 아이템으로 치우친다

1. 위치: [src/run.js:139](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/run.js#L139).
2. 대조 원문: [docs/ASSUMPTIONS.md:175](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/docs/ASSUMPTIONS.md#L175): “심층 보상 종류 4개 균등 시드 선택. ... 장비는 미보유 중 시드 1개”.
3. 재현:
   - 미보유 장비 12개, 새 회차 seed1~100에서 심층 보상 미리보기.
   - 장비 보상 24건이 모두 pioneer_spear(개척자의 창).
   - 장비 종류를 뽑을 때 난수를 처음 상태로 다시 생성해 보상 종류 선택과 같은 0~3 값을 사용한다. 장비 보상인 경우 이 값은 항상 1이므로 pool[1]이 된다.
4. 제안:
   - 보상 종류를 선택한 난수 상태에서 이어서 전체 미보유 장비 범위로 한 번 선택하고 저장.
   - 미리보기와 수령이 같아야 하며, 같은 초기 보유 조건에서 여러 시드에 장비 종류가 다양하게 나오는지 확인.

### F6 [P2] 시작 화면 간소화·실제 수치 표시가 완료되지 않았다

1. 위치: [src/screens.js:76](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/screens.js#L76), [src/screens.js:83](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/screens.js#L83), [src/main.js:86](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/main.js#L86).
2. 대조 원문:
   - 전달한 지시문: “개발 설정·시뮬레이션 설명은 검증 메뉴로 분리한다.”
   - “핵심 약점은 숨기지 않는다. 예: 창의 근접 피해 약화가 유지된다면 기본 설명에서도 알 수 있어야 한다.”
3. 재현:
   - 배포 단일 HTML → 새 회차.
   - 시작 기술 위에 밸런스·회차 구조·배치·난이도와 문서 경로를 포함한 검증 설정이 펼쳐져 있다.
   - test03이 선택돼 있는데 창 카드는 주기 0.7초를 표시한다. 실제 선택 후 적용되는 값은 0.85초.
   - 창 기본 설명에는 근접 약화가 없고 설정 선택의 부연설명에만 들어 있다.
   - 기본 ×1이라는 문구와 test03의 ×1.5/×2/×3 조건도 한 화면에 함께 표시된다.
4. 제안:
   - 정상 시작은 자동기술 선택에 집중하고 검증 설정은 닫힌 고급 메뉴로 이동.
   - 선택된 설정을 반영한 파생 수치로 미리보기 생성.
   - 창의 핵심 약점을 카드에서 직접 표시.
   - 이는 디자인 취향의 판정이 아니라, 합의한 정보 분리와 실제 수치 일치 여부의 문제다.

### F7 [P2] 원정대 갑옷은 승리 직후가 아니라 귀환 때만 회복한다

1. 위치: [src/run.js:188](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/run.js#L188), [src/flow.js:19](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/flow.js#L19).
2. 대조 원문:
   - 전달한 지시문: “전투 승리 시 체력 8 회복. 승리 정산당 한 번.”
   - [src/world_data.js:72](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/src/world_data.js#L72) 부근 장비 설명: “전투 승리 정산마다 한 번 체력 8 회복(보스 포함).”
   - GAME_SPEC §19.6에는 이를 “승리 정산(귀환)”으로 바꿔 적어, 장비 데이터와 명세도 서로 다르다.
3. 재현:
   - 원정대 갑옷, 체력 50으로 승리 정산 → 50 유지.
   - 귀환 정산 이후 → 58.
   - 따라서 일반 승리 뒤 심층으로 들어갈 때 기대한 8 회복을 받지 못한다.
4. 제안:
   - 합의한 전투 승리 시점으로 옮기고 승리 정산의 중복 방지와 함께 검증.
   - 귀환 전용 효과를 의도했다면 사용자가 결정할 규칙 변경으로 분리하고 설명을 일치시킬 것.

### F8 [P2] 회차 보고서의 설정 표기가 여전히 실제와 다르다

1. 위치: [tools/run_sim.js:142](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/tools/run_sim.js#L142).
2. 대조 원문: 전달한 지시문 “보고서 머리말의 설정과 실제 적용 배율이 다른 문제”를 회귀 확인.
3. 재현:
   - sim_check는 원본 run_sim에 --balance test03 --curve v06 --seeds 1 --strats gradual 전달.
   - 출력 머리말: “처치 경험치 ×1, 지역 경험치 ×1, 보스 체력 base”.
   - 실제 보스 결과 최대 체력: 2400 / 5000 / 7000. 적용은 test03.
4. 제안:
   - CLI 인자의 미사용 기본값 대신 실제 회차/런타임 설정에서 보고서 머리말을 생성.
   - 단일 결과에 실제 커밋·배율·보스 체력을 함께 보존.

## 검증 범위의 한계와 보고 표현

- “합의 사항 18항목 모두 확인”이라는 요약은 위 재현과 충돌한다.
- [tools/verify_menu_v08.js:29](https://github.com/hunheecho/CosBridge.github.io/blob/7ec93cddae413d9c8d5bcbbe8a244e40f86ae903/prophecy_action_prototype/tools/verify_menu_v08.js#L29) 부근 정상 첫 전투 검증은 page.evaluate로 적에게 99999 피해를 주고 pending을 비우며 spawnedAll을 true로 만든다. 화면 연결 시험으로는 쓸 수 있지만 자연 전투의 승리 조건이나 밸런스를 증명하지 않는다.
- 이 검수에서는 그 브라우저 자동화 스크립트를 그대로 재실행하지 않았다. 실제 UI 첫 전투와 시간대 조작을 별도로 실행했다.
- Claude의 아티팩트 내용 자체, 모든 브라우저 검증 30/19/35/20개, 소리, 모바일, 사람의 장시간 플레이는 독립 확인하지 않았다.
- 기존 보고서의 구버전 수치와 현 코드의 재측정 값이 함께 남아 있다. 밸런스 비교에 쓸 표는 실행 커밋별로 분리해야 한다.

## 판단할 수 없어 사람에게 넘기는 항목

- 회전 칼날 조작감과 현재 수치의 만족도.
- 겹친 장판의 2~3배 피해를 어느 정도 허용할지.
- 날짜별 적 위협·휴식·교체 비용의 체감.
- 임무 완료 후 그 장소를 일반 전투로 다시 방문할 수 있게 할지.
- 보스의 필요한 압박과 준비 부족 시 승리 가능 범위.

우선 제안 순서: F1 시뮬레이션/UI 경로 일치 → F2/F3/F4/F5 기능 오류 → F6/F7 표시·규칙 일치 → 동일 조건 재측정 → 사용자 플레이.
원본 코드는 수정하지 않았다.



