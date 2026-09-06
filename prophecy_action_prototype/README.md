# 예언의 시간표 — 액션 프로토타입

마검사가 보스 도래 전 며칠 동안 하루 5시간을 배분해 출격하고, **짧은 실시간 전투**에서 적의 예고를 읽어 대응하며, 증강·장비로 공격 형태를 바꾸는 게임의 첫 플레이 가능한 프로토타입.

## 실행 (Windows)
1. 이 폴더를 통째로 받는다.
2. `index.html`을 더블클릭한다(또는 `run.bat`). Chrome·Edge에서 동작. 설치 없음.
3. 인터넷이 있으면 Noto Sans KR 웹폰트를, 없으면 맑은 고딕을 쓴다.

단일 파일 버전: `dist/prophecy_single.html` 하나만 복사해도 실행된다(`node tools/build_single.js`로 생성).

## 조작 (화면 하단에도 표시)
| 키 | 동작 |
|---|---|
| W A S D / 방향키 | 이동 |
| Space | 회피 (0.26초 무적) |
| Q | 감속장 |
| Esc | 일시정지 (음량·음소거·조작법) |
| Enter / 클릭 | 메뉴 확인 |
| F3 | 디버그 오버레이 (개발용) |

## 전투 시험실 (v0.6) — 이 버튼부터
1. `index.html`(또는 `dist/prophecy_single.html`) → 제목 화면 **"전투 시험실"**.
2. 기본값(근교 숲 · 체력 ×1 · 초반 기본 검 · 직접 조작) 그대로 **시작**. WASD 이동, Space 회피, Q 감속장, Esc 일시정지(설정 확인·중단).
3. 결과 화면에서 **"체력 배율만 바꿔 재시작"**으로 ×2 → ×3을 같은 시드로 비교. 표에서 "공격 전 사망%"와 "실행/등장"이 적이 행동을 보여줬는지 알려준다.
4. 적 조합을 "단독 시험 → 멧돼지"(기둥 숲), "조합 프리셋 → 방패병 + 궁수" 등으로 바꿔 신규 몬스터를 본다. 봇 조작을 켜면 정책 3종의 결과를 표로 비교할 수 있다(사람 결과가 아님).
- 주소로 바로 열기: `index.html?lab=enemy%3Dsolo%3Aboar%3Bhp%3D2%2C1%2C1%3Bseed%3D3%3Bbuild%3Dmid_melee%3Bcontrol%3Dhuman` (설정 화면 하단에 현재 설정의 주소가 표시된다).
- 시험실은 정식 회차 저장을 건드리지 않는다. 시험안 배치·난이도 후보는 "새 회차 → 검증 메뉴"에서 고른다(기본은 기존 배치·×1).
- 시뮬레이션: `node tools/lab_sim.js A|B|C --seeds 10 --workers 4` → `node tools/lab_report.js A|B|C` (`docs/sim/report_*.md`), 회차: `node tools/run_sim.js --mode trio|single --curve v06 --strats easy,gradual,risky,cautious,deep,mission,matched --start sword|spear|blades`. 요약과 질문별 답: `docs/sim/SUMMARY.md`.
- v0.7 브라우저 검증: `NODE_PATH=<playwright> node tools/verify_v07.js` (25항목, `docs/verify_v07_log.txt`).
- v0.7 회차 흐름: 거점 → 출격(오늘의 카드 3장: 지역+목표, 시간, 주요 적, 위험 조건, 보상 종류 / 일반 탐험) → 전투(목표 HUD) → 보상 → 3택(레벨업·임무·사건·더 깊이) → 사건(출격당 최대 1회) → 더 깊이/귀환. 보스 관문: 3일차·5일차·7일차 시작(새 회차 기본 3보스, 시작 화면에서 단일 보스 선택 가능). 제목 화면 검증 메뉴 "N단계 관문 직전"으로 관문을 바로 시험할 수 있다.
- 브라우저 검증(실제 키·클릭): `NODE_PATH=<playwright> node tools/verify_lab.js`.

## 성장 시스템 (v0.5)
- 새 회차 → **시작 무기 선택**(검·관통창·회전 칼날, 검증 메뉴에서 쌍검·추적궁·전투망치·번개 구체). 전투 중 레벨업 카드에서 무기 2개를 더 얻고, 공통 증강 3칸·E 기술·패시브 4칸을 채운다.
- 조작: WASD 이동, Space 회피, Q 감속장, **E 선택 기술**, Esc.
- 조합 시험 링크(v3 파라미터): `index.html?scenario=forest&seed=11&start=spear&weapons=blades:2:dual,frost:1:fan&commons=frost,echo&e=gust:1:whirl&passives=mastery:1` — `weapons=무기:레벨:방식+방식`, `commons=`, `passives=`, `e=기술:레벨:변형`, `q=slowfield:레벨:변형`, `rewards=resonance` (보스 보상 시험).
- 예시: 관통창+귀환+분열 `weapons=spear:3:returning+split` · 번개 구체 분기+전도 `start=orb&weapons=orb:3:fork+conduct` · 불씨+재점화+불꽃 파열 `start=sword&weapons=ember:2:reignite&commons=flare` · 지뢰 연결+유인 `weapons=mine:2:chain+lure` · 낙뢰 연쇄 `e=strike:2:chain` · 중력핵 붕괴 `e=gravity:2:collapse`.
- 전체 목록·구현 상태: `src/growth_data.js`(모든 항목 `impl: true`), 명세 §5.
- 성장 속도 시뮬레이션: `node tools/growth_sim.js mixed|easy|risky 1,2,3`.

## 보스전 (v0.4)
- 정상 회차: 6일차까지 준비 → 하루 종료(내일 보스 도래 안내) → 7일차 최종 준비(상점·판매·장비 교체·보스 정보) → "보스에게 간다" → 패배 시 같은 준비로 재도전, 승리 시 결과 화면.
- 바로 시험: `index.html?scenario=boss&seed=5` (+ `weapon=pierce&aug=spin,stasis,saving&upgrade=2&acc=fang_necklace&armor=leather_armor`).
- 빌드별 시험 링크: 기본 `?scenario=boss&seed=5&upgrade=2&aug=sharp:2` · 감속장+회전+정지된 칼날 `?scenario=boss&seed=5&aug=spin,stasis,saving,wide` · 관통+얼음 `?scenario=boss&seed=5&weapon=pierce&aug=frost,quick` · 잔불+파열 `?scenario=boss&seed=5&aug=ember,flare,wide:2`.
- 헤드리스 길이 측정: `node tools/boss_sim.js`, 브라우저 통합 검증: `NODE_PATH=<playwright> node tools/verify_boss.js`.

## 한 바퀴
거점(시간·보스·목표 장비 확인) → 지역 선택(비용·위험·보상) → 실시간 전투 → 보상·증강 선택 → 더 깊이/귀환 → 상점·대장간에서 구매·제작·장착 → 다시 출격 → 하루 종료 → … → 7일차 최종 준비 → 보스전(가시갈기) → 재도전 또는 결과.

## 조합 바로 시험하기
| 조합 | 주소 |
|---|---|
| ① 감속장 + 회전 검격 | `index.html?scenario=forest&seed=11&aug=spin,wide` → 늑대가 모이면 Q |
| ② 관통검 + 얼음 파편 | `index.html?scenario=forest&seed=11&weapon=pierce&aug=frost` |
| ③ 잔불 걸음 + 불꽃 파열 | `index.html?scenario=forest&seed=11&aug=ember,flare` → Space로 불길을 남기고 그 위로 늑대를 유도 |
| 시간 저축 + 정지된 칼날 | `index.html?scenario=den&seed=5&aug=saving,stasis,spin` |

## 시험 전투 바로 열기
`index.html?scenario=<지역id>&seed=<숫자>&weapon=pierce&aug=spin,ember,mark:1&upgrade=2&deep=1`
지역 id: `forest` `ridge` `marsh` `den` `deep`. 증강 id는 `src/data.js`의 AUGMENTS 참고.

## 개발
- 자세 대조표: `NODE_PATH=<playwright 경로> node tools/posesheet.js`
- 테스트: `node --test test/*.test.js` (Node 18+)
- 화면 캡처: `NODE_PATH=<playwright 경로> node tools/shots.js`
- 한 바퀴 자동 점검: `NODE_PATH=<playwright 경로> node tools/playthrough.js`
- v0.3 검수·조합 검증(실제 입력·재실행 포함): `NODE_PATH=<playwright 경로> node tools/verify_v03.js`
- 일시정지 입력 검증(실제 키 이벤트): `NODE_PATH=<playwright 경로> node tools/verify_pause_input.js`
- 단일 파일 빌드: `node tools/build_single.js`
- 시험실 브라우저 검증: `NODE_PATH=<playwright 경로> node tools/verify_lab.js`
- 대량 시뮬레이션·집계: `node tools/lab_sim.js A|B|C`, `node tools/lab_report.js A|B|C`, 회차 `node tools/run_sim.js`

## 문서
- `docs/GAME_SPEC.md` 현재 규칙
- `docs/ASSUMPTIONS.md` 임시 수치와 가정
- `docs/TRACEABILITY.md` 요구사항 추적표
- `docs/TECH_DECISION.md` 기술 선택
- `docs/HANDOFF.md` 현재 상태와 다음 작업

## 자산·라이선스
- 그래픽: 전부 코드로 그린 도형. 외부 이미지 없음.
- 소리: WebAudio로 합성. 외부 파일 없음.
- 폰트: Noto Sans KR (SIL Open Font License) — Google Fonts 링크로 로드, 저장소에 포함하지 않음.
- 참고 게임의 자산은 사용하지 않았다.

## 영상·자세표
- `docs/video/combat_forest.webm`: 봇이 근교 숲에서 싸우는 실제 녹화(21초). `combat_forest_clip.webm`은 8초 요약.
- `docs/screenshots/pose_wolves.png`, `pose_swordsman.png`: 동작별 자세 대조표. `video_contact_sheet.png`: 영상 1초 간격 프레임.
- 녹화 재생성: `NODE_PATH=<playwright> node tools/record.js "?scenario=forest&seed=11" 30`

## 실행 화면 (헤드리스 Chromium 캡처)
`docs/screenshots/` — 거점, 상점 미리보기, 늑대 돌진 예고, 감속장, 관통검+보호막, 증강 선택, 보스 도래. 자동 한 바퀴 기록은 `docs/playthrough_log.txt`.
