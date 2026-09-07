# 예언의 시간표(가칭) — Godot 이식 (prophecy_godot)

HTML 프로토타입(`../prophecy_action_prototype`, v0.8.0, 커밋 ee10fc7)에서 합의된 게임 전체를 Godot으로 옮긴 프로젝트입니다(godot-0.4.0). 새 회차 → 시작 기술 → 거점 → 장소/시간대 카드 → 전투(레벨업 3택) → 승리/보상 → 더 깊이/귀환 → 상점·장비·대장간·휴식 → 다음 날 → 관문 보스(희귀 보상) → 최종 보스 → 회차 결과 → 새 회차까지 일반 UI로 진행할 수 있고, 저장/계속하기와 패배 경로가 있습니다. 0.3.1의 첫 전투(사용자 긍정 평가, D33)는 "기준 전투"로 그대로 보존됩니다. 게임 이름은 아직 미정(가칭)입니다.

이식 기준·충돌 처리: `../docs/PORT_BASELINE.md` · 콘텐츠 ID별 상태: `../docs/CONTENT_MATRIX.md` · 규칙 계층 계약: `docs/PORT_CONVENTIONS.md` · 잠정값과 근거: `docs/ASSUMPTIONS.md` · 이번 이식 기록·재현 정보: `docs/PORT_NOTES.md` §12.

## 필요한 Godot
- **Godot 4.7.2-stable, 표준(non-.NET) Windows 64비트** 공식 배포본.
- 다운로드: https://github.com/godotengine/godot/releases/tag/4.7.2-stable → `Godot_v4.7.2-stable_win64.exe.zip` (`mono`가 붙은 파일은 .NET판이므로 받지 않음).
- GDScript만 사용하고, .NET·C#·JS 확장·외부 플러그인·외부 에셋이 없습니다(그래픽은 도형, 소리는 합성음). 렌더러는 Compatibility(OpenGL 3).

## 바로 실행하는 방법
1. 위 zip을 풀고 `Godot_v4.7.2-stable_win64.exe`를 실행한다(설치 과정 없음).
2. 프로젝트 관리자에서 **가져오기(Import)** → 이 폴더의 `project.godot` 선택 → **가져오기 및 편집**.
3. 편집기 우상단 ▶(F5) 실행. 제목 화면에서 **새 회차** 또는 **계속하기**.

Godot 없이 플레이하려면 `../prophecy_godot_build/`의 Windows 빌드 ZIP을 사용합니다(§`docs/PORT_NOTES.md` §12에 빌드 커밋·해시). 사람이 키보드로 플레이한 확인은 아직 없습니다(봇 자동 진행·헤드리스 검증만).

## 조작
WASD/방향키 이동 · Space 회피(짧게/길게 눌러 거리 70~150, 재사용 1.5초) · Q 감속장 · **E 수동 기술**(습득 후) · 자동 공격(보유 자동기술이 사거리 안의 적에게 자동 발동) · Esc 일시정지/메뉴 닫기 · Enter 기본 버튼 · F3 검증 패널. 밑줄 친 용어는 마우스를 올리면 설명, 클릭하면 고정(전투 중 고정 시 일시정지). 고정된 용어를 다시 클릭하거나 바깥을 클릭하면 닫힘.
- **게임패드**(추가 매핑, 실제 패드로는 미확인): 왼쪽 스틱/십자키 이동 · A·B 회피 · X 감속장(Q) · Y E 기술 · Start 일시정지. 키보드와 같은 InputMap 행동이라 규칙은 같다.
- **터치 오버레이**(모바일 준비, 실기 미검증): 터치 화면이 있거나 환경 변수 `PROPHECY_TOUCH=1`이면 전투 중 왼쪽 가상 스틱(누른 자리가 중심) + 오른쪽 회피(누르는 동안 유지)·Q·E 버튼이 나온다. PC에서는 `PROPHECY_TOUCH=1`로 켜면 마우스 왼쪽 버튼을 터치 1개로 취급한다(멀티터치는 실기 필요). 밑줄 용어는 탭하면 고정, 다시 탭/바깥 탭으로 닫힘.
- 거점은 마을 그림에서 건물(대장간·상점·장비·통계·기록·휴식)을 클릭/탭해 연다(걷기 없음). 오늘의 출격 2장이 주 버튼. 현재 빌드는 한 줄씩 요약, 전체는 "상세". 창 비율(넓음/기본/좁음)과 안전 영역에 맞춰 여백·열 비율이 바뀐다(`scripts/game/ui/layout.gd`).
제목 화면 **검증 메뉴**: 기준 전투(0.3.1 D33, 사람/봇) · 시작 기술 첫 전투 비교 · 관문 빌드 보스전 · 봇 회차 데모. 전투 규칙: `docs/RULES.md`.
제목 화면 **영구 성장**(godot-0.4.3, 별도 시험 프로필): 프로필 종류(기존 시험 사용자 = 0.4.x 콘텐츠 전부 / 새 시험 프로필 = 초안 초기 범위) · 탐험 기록 → 영구 레벨(최대 15) · 특성 4행(행마다 1개, 출발 전 재선택, 새 회차부터 적용) · 도감(잠긴 항목 클릭 → 조건) · 대장간 **제작**(해금 제작법 + 장비/재료/금화). 방향은 사용자 합의, 수치는 시험값(`../docs/DESIGN_DECISIONS.md` D39, `docs/ASSUMPTIONS.md` §영구 성장).

## 검증 명령(터미널, Godot 콘솔 실행 파일 경로를 `godot`라고 할 때)
```
godot --headless --path prophecy_godot --import                       # class_name 추가 뒤 1회(전역 클래스 캐시)
godot --headless --path prophecy_godot -s tests/run_tests.gd          # 기준 전투 규칙 72
godot --headless --path prophecy_godot -s tests/port_tests.gd         # 전투 콘텐츠(자동기술·개조·범용·특성·Q/E·장비·지형·편성·철벽 경계·상태 공급원) 76
godot --headless --path prophecy_godot -s tests/boss_tests.gd         # 보스 3·전투 목표 34
godot --headless --path prophecy_godot -s tests/run_layer_tests.gd    # 회차 계층(상점·교체·대장간·정산·관문·저장·통계·밀도 세트·정산 1회·DPS 분모) 62
godot --headless --path prophecy_godot -s tests/world_tests.gd        # 세계 변화(붉은 달) 30
godot --headless --path prophecy_godot -s tests/content_tests.gd      # 반복 콘텐츠(회차 특징·사전 편성·강적의 흔적·보스 계획·밀도 비교 회차) 28
godot --headless --path prophecy_godot -s tests/ui_flow_tests.gd      # 화면 계층(실제 main.tscn: 전투 중 종료 체크포인트·HUD 보호막) 14 — user:// 저장을 쓰므로 APPDATA를 별도 폴더로 두고 실행
godot --headless --path prophecy_godot -s tests/meta_tests.gd         # 영구 성장·해금·제작(레벨·해금 집합·후보 필터·카드 희석 수치·특성 12·기록 1회·제작·제작 6종 전투 효과) 78 — user:// 프로필을 쓰므로 APPDATA 격리
godot --headless --path prophecy_godot -s tests/meta_ui_tests.gd      # 영구 성장 화면 계층(실제 main.tscn: 영구 성장·특성·프로필 전환·시작 선택·제작 미리보기/확정·보상 줄) 11 — APPDATA 격리
godot --headless --path prophecy_godot -s tests/input_tests.gd        # 입력 라우터(키보드 = 0.4.3 동일값·1회 소비)·가상 스틱/멀티터치·배치 헬퍼·거점 마을 60 — APPDATA 격리
PROPHECY_SHOTS=<폴더> [PROPHECY_TOUCH=1] godot --path prophecy_godot --resolution 1280x720 -s tools/layout_shots.gd   # 창 크기별 배치 캡처 + 넘침 검사(LAYOUT_CHECK)
godot --headless --path prophecy_godot -s tools/density_report.gd     # 기준 전투 밀도 비교(0.3.1과 같은 36행) → docs/DENSITY_REPORT.md
godot --headless --path prophecy_godot -s tools/compare_scenario.gd   # HTML 대조 측정(COMPARE_JSON)
PROPHECY_SIM_SEEDS=1,2 godot --headless --path prophecy_godot -s tools/run_sim.gd        # 회차 봇 전략 7종 → docs/sim/RUN_SIM.md
PROPHECY_SIM_SEEDS=11,18 godot --headless --path prophecy_godot -s tools/boss_sim.gd     # 관문 빌드 × 보스 × 정책 → docs/sim/BOSS_SIM.md
PROPHECY_SIM_SEEDS=100,101 godot --headless --path prophecy_godot -s tools/start_compare.gd  # 시작 기술 비교 → docs/sim/START_COMPARE.md
PROPHECY_UI_SMOKE=<폴더> [PROPHECY_UI_FULL=1 PROPHECY_UI_SPEED=5] godot --path prophecy_godot  # 실제 창에서 새 회차→…→관문(→최종 보스→회차 결과→새 회차) 자동 진행, PNG 저장
PROPHECY_CAPTURE=<폴더> godot --path prophecy_godot                   # 기준 전투 봇 캡처 7장
PROPHECY_MOVIE=1|single godot --path prophecy_godot --write-movie out.png --fixed-fps 30   # 기준 전투 영상 프레임
godot --headless --path prophecy_godot --export-release "Windows Desktop" <출력 exe>       # Windows 빌드(공식 4.7.2 템플릿 필요)
```
데이터 재생성(HTML 카탈로그 → JSON): `node prophecy_action_prototype/tools/port_export_data.js` (HTML 원본은 수정하지 않음).

## 폴더
- `data/*.json` 카탈로그(HTML에서 내보냄: config·weapons·growth·enemies·world·missions·balance·glossary) + `first_fight.json`(0.3.1 기준 전투) + `meta.json`(손으로 작성: 영구 레벨·해금 일정·특성 12·제작 6 — Codex 초안 시험값, 사용자 승인 아님). 규칙 코드는 숫자를 갖지 않는다.
- `scripts/rules/` 순수 규칙(Node·Vector2·입력·그리기 없음, 고정 단계 1/120초): `combat_state.gd`(전투) · `weapons.gd`·`skills.gd`(자동기술·Q/E) · `enemies.gd`·`enemies_new.gd`·`boss.gd`·`boss2.gd`·`objectives.gd` · `growth.gd`·`build.gd`·`formation.gd` · `run.gd`·`sortie.gd`·`events.gd`·`flow.gd`(행동 목록 `PFlow.actions(run)`, UI·봇 공용) · `stats.gd`·`save.gd`(`user://prophecy_save_v1.json`) · `profile.gd`(영구 프로필 `user://prophecy_profile_v1.json`, legacy/trial 공존; 시험·봇 데모는 `prophecy_profile_test_v1.json`) · `bot.gd`·`run_bot.gd` · `catalog.gd`·`geom.gd`·`rng.gd`.
- `scripts/game/` 표시·연결부: `step_driver.gd`(프레임→단계) · `combat_view.gd`(입력·`_draw`) · `render.gd`(도형 그리기) · `audio.gd`(합성음, 자동 로드 `Audio`) · `main.gd`(화면 전환·HUD·자동 진행) · `screens/`·`ui/`(화면·위젯·3택·용어 툴팁·설정 · `input_router.gd` 장치→행동 · `touch_controls.gd` 터치 오버레이 · `layout.gd` 안전 영역·비율 · `village_map.gd` 거점 마을 그림) · `game.gd`(자동 로드·버전).
- `scenes/main.tscn` 단일 씬. `tests/`, `tools/` 검증용. `docs/` 기록·보고서·캡처(`.gdignore`).
