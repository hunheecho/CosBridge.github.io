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

## 한 바퀴
거점(시간·보스·목표 장비 확인) → 지역 선택(비용·위험·보상) → 실시간 전투 → 보상·증강 선택 → 더 깊이/귀환 → 상점·대장간에서 구매·제작·장착 → 다시 출격 → 하루 종료 → … → 7일차 보스 도래(보스전은 미구현, 정직하게 표시).

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
- 단일 파일 빌드: `node tools/build_single.js`

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
