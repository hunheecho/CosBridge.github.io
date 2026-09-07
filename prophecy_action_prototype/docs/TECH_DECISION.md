# 기술 선택 기록

## 결정
**HTML5 Canvas + 순수 JavaScript(ES2020, 빌드 도구 없음)**, 논리 검증은 Node.js 내장 `node --test`, 화면 검증은 Playwright(Chromium).

## 근거
| 요구 | 선택이 충족하는 방식 |
|---|---|
| Windows에서 쉽게 실행 | `index.html` 더블클릭 또는 `run.bat`. 설치 없음. 크롬/엣지 모두 동작 |
| 2D 표현·입력·충돌·오디오 | Canvas 2D, KeyboardEvent, 자체 원/사각 충돌, WebAudio 합성음(자산 라이선스 문제 없음) |
| 프레임 독립 시간 처리 | 고정 시간 단계(1/120초) 누적기. 시뮬레이션은 `dt`만 받으며 렌더링과 분리 |
| 빠른 돌진·투사체 관통 방지 | 120Hz 고정 단계에서 최대 이동량(돌진 800px/s → 6.7px/step)이 판정 반지름보다 작음. 테스트로 보장 |
| 다수 객체 관리 | 배열 기반 엔티티 + 매 단계 압축(dead 제거). 이 규모(수십 개)에서는 충분 |
| 전투 상태와 UI 일관성 | 렌더러는 시뮬레이션 상태만 읽음. HUD는 같은 상태 객체에서 그림 |
| 저장/불러오기 | 회차 상태를 JSON으로 직렬화해 `localStorage` 저장. 자동 저장은 거점에서 |
| 재현 가능한 시험 전투 | 시드 난수(mulberry32) + `?scenario=<id>&seed=<n>` URL 파라미터 |
| 자산·수치 관리 | 모든 수치는 `src/data.js` 한 곳. 자산은 코드로 그린 도형(외부 이미지 없음) |
| 디버그와 사람용 화면 분리 | F3 토글 디버그 오버레이(판정 원, 상태 텍스트). 기본 꺼짐 |
| 테스트 가능성 | 스크립트는 전역 네임스페이스 `PA`에 모듈을 등록. Node 테스트는 같은 파일을 `vm`으로 로드 |

## 검토했지만 택하지 않은 것
- **Python + pygame-ce**: Windows에 Python 설치가 필요하고 한국어 폰트를 직접 번들해야 함. 이 컨테이너에는 pygame이 없어 설치·검증 비용이 큼.
- **Godot**: 에디터 배포·빌드 파이프라인이 이 원격 환경에서 검증 불가.
- **ES 모듈 + 번들러**: `file://`에서 모듈 로딩이 차단되어 더블클릭 실행이 깨짐. 전역 네임스페이스 방식 채택.

## 실행 환경 제한(이 세션)
- 원격 Linux 컨테이너. 실제 Windows 실행은 하지 못했고, 헤드리스 Chromium으로 렌더링·입력 시나리오를 확인했다.
- 소리는 헤드리스에서 들을 수 없으므로 코드 경로만 검증했다.

## Godot 이식 준비 지침 (2026-09-07, 지금 이식하지 않음)

새 기능은 아래를 지킨다. 이식 준비를 이유로 구현을 늦추지 않고, 대규모 구조 변경도 하지 않는다.

| 지침 | 현재 상태(감사: `grep document|window|localStorage|canvas|Date.now|Math.random` src/핵심 모듈) |
|---|---|
| 전투·성장·경제 규칙 ↔ 화면 표시 분리 | 규칙: combat/weapons/skills/boss/enemies/objectives/growth/run/sortie/flow/stats. 표시: render.js(캔버스)·screens.js(DOM)·main.js(입력·루프·화면 전환). 규칙 모듈은 DOM·Canvas 참조 0 |
| 데이터 ↔ 실행 코드 분리 | data.js(적·지역·설정), growth_data.js(자동기술·개조·공용·패시브·기술), world_data.js(시간대·장소·편성·변주·장비·가격), boss_data.js, mission_data.js, balance_data.js, glossary_data.js, lab_data.js |
| 핵심 규칙에서 브라우저 API 직접 참조 금지 | 저장은 `Run.save/load(storage)`·`Lab.saveConfig(storage)`에 저장소를 주입(기본값만 localStorage, 테스트는 fakeStorage). 시간은 `PA.clock.now()`(기본 Date.now) 한 곳. 난수는 `PA.rng.create(seed)`만 사용(Math.random 0) |
| 입력·저장은 별도 연결부 | 입력: `PA.Input`(키 → {mx,my,dodge,special,skillE}) 또는 `PA.Bot.stepInput`이 같은 형식으로 `Combat.step(st, input, dt)`에 전달. 저장: 위 storage 인자 |
| 시간·난수 통제 | 고정 단계 1/120초(`CONFIG.STEP`), 봇 판단 5스텝, 단일 시드 난수. 프레임 속도 독립 테스트(test/lab.test.js) |
| 대표 전투의 입력·설정·결과 | `docs/port/fixtures_v08.json` + `FIXTURES.md`(`tools/port_fixtures.js`, `--verify`로 입력 열만 재실행). 규칙이 바뀌면 `test/port_fixtures.test.js`가 깨지고 다시 기록한다 |

남은 결합(이식 시 정리 대상, 지금은 두는 것): screens.js가 규칙 함수(Run.*, Sortie.*)를 직접 호출해 문자열을 만든다(표시 전용이라 허용). main.js의 게임 루프가 Combat.step과 Bot을 직접 묶는다(연결부 역할). Combat.summary/metrics는 규칙 모듈 안에 있으나 표시와 무관한 순수 집계다.

## Godot 전환 결정 (2026-09-07)
- 엔진 **Godot 4.7.2-stable** 공식 배포본(표준, non-.NET), GDScript만, 2D, Compatibility(OpenGL3) 렌더러 우선, 내보내기 템플릿 버전 = 엔진 버전으로 고정. 플러그인·시스템 변경 없음.
- 프로젝트는 `../prophecy_godot`(별도 폴더). HTML은 삭제·덮어쓰기 없이 비교 기준선으로 보존. 이식 기준 커밋 ee10fc7.
- 구조 원칙은 위 "이식 준비 지침"을 Godot에서도 그대로: 규칙(`scripts/rules`, RefCounted·dict·double, Node/입력/그리기 없음) ↔ 표시(`scripts/game`), 데이터(`data/*.json`) ↔ 코드, 입력은 행동 dict, 사람·봇 같은 `step`, 고정 1/120 스텝·시드 RNG(HTML과 같은 mulberry32), `_draw` 읽기 전용, 피해 출처 키 보존. Godot 물리는 쓰지 않고 자체 스윕 원 충돌(바꾸면 대조 측정 재실행).
- 함수가 섞인 JS 데이터(개조 apply·사건 선택지·보스 패턴)는 JSON으로 옮기지 않고 GDScript 데이터/Resource로 재작성한다. 변환 프레임워크는 만들지 않는다.
- 검증 방식: headless 규칙 테스트(`tests/run_tests.gd`) + 고정 배치·고정 입력 대조(`tools/compare_scenario.gd` ↔ HTML `tools/port_compare_html.js`) + Xvfb 실제 렌더 캡처/영상(`PROPHECY_CAPTURE`, `PROPHECY_MOVIE`). "같은 시드 = 같은 전투"는 가정하지 않는다.

