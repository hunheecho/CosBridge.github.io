# 예언의 시간표 — Godot 첫 전투 (prophecy_godot)

HTML 프로토타입(`../prophecy_action_prototype`, v0.8.0, 커밋 ee10fc7)의 **첫 전투 하나**를 Godot으로 옮긴 프로젝트입니다. 전체 이식이 아니라 "집에서 열면 바로 한 판 플레이할 수 있는 상태"가 목표입니다. 상세 기록은 `docs/PORT_NOTES.md`.

## 필요한 Godot
- **Godot 4.7.2-stable, 표준(non-.NET) Windows 64비트** 공식 배포본.
- 다운로드: https://github.com/godotengine/godot/releases/tag/4.7.2-stable → `Godot_v4.7.2-stable_win64.exe.zip` (`mono`가 붙은 파일은 .NET판이므로 받지 않음).
- 이 프로젝트는 GDScript만 사용하고, .NET·C#·JS 확장·외부 플러그인이 없습니다. 렌더러는 Compatibility(OpenGL 3).

## 바로 실행하는 방법
1. 위 zip을 풀고 `Godot_v4.7.2-stable_win64.exe`를 실행한다(설치 과정 없음).
2. 프로젝트 관리자에서 **가져오기(Import)** → 이 폴더의 `project.godot` 선택 → **가져오기 및 편집**.
3. 편집기 우상단 ▶(F5) 실행. 시작 화면에서 **Enter** 또는 `전투 시작`.

Godot 없이 플레이하려면 `../prophecy_godot_build/`의 Windows 빌드 ZIP(`prophecy_first_fight.exe`, godot-0.3.0)을 사용합니다. 프로젝트를 Windows 10 로컬 Godot 4.7.2에서 가져오기·테스트·실행한 것은 godot-0.3.1에서 확인했습니다(`docs/PORT_NOTES.md` §11). 사람이 키보드로 플레이한 확인은 아직 없습니다.

새 세션에서 읽을 문서 순서는 `../prophecy_action_prototype/docs/HANDOFF.md` 맨 위 "구현자 진입 순서" 한 곳에만 둡니다.

## 조작
WASD/방향키 이동 · Space 회피(짧게/길게 눌러 거리 70~150 조절, 재사용 1.5초) · Q 감속장 · 자동 공격(검격 Lv1) · Esc 일시정지/재개 · F3 검증 패널(회피 방식·재사용, 편성 5/25/50, 동시 돌진 2/3 비교 설정, 다음 재시작에 적용) · Enter 시작/재시작. 규칙: `docs/RULES.md`, 근거: `docs/ASSUMPTIONS.md`, 봇 밀도 비교: `docs/DENSITY_REPORT.md`.

## 검증 명령(터미널, Godot 실행 파일 경로를 `godot`라고 할 때)
```
godot --headless --path prophecy_godot -s tests/run_tests.gd        # 규칙 테스트 72개
godot --headless --path prophecy_godot -s tools/density_report.gd   # 밀도 비교(편성 × 봇 정책 × 시드) → docs/DENSITY_REPORT.md
godot --headless --path prophecy_godot -s tools/compare_scenario.gd  # HTML 대조용 측정(COMPARE_JSON)
PROPHECY_CAPTURE=<폴더> godot --path prophecy_godot                  # 봇 전투를 돌리며 화면 7장 저장 후 종료
PROPHECY_MOVIE=1|single [PROPHECY_FORMATION=base|x5|x10] godot --path prophecy_godot --write-movie out.png --fixed-fps 30  # 영상 프레임 기록
PROPHECY_DODGE_DEMO=1 [PROPHECY_DODGE_MODE=hold|fixed PROPHECY_DODGE_CD=1.5] godot --path prophecy_godot  # 회피 시연(스크립트 입력, DEMO_RESULT 출력)
```
HTML 쪽 대조 스크립트: `node prophecy_action_prototype/tools/port_compare_html.js`.

## 폴더
- `data/first_fight.json` 첫 전투 데이터(플레이어·검격·늑대 물기/돌진·장애물·편성·소환·보상 예산). 규칙 코드는 숫자를 갖지 않는다.
- `scripts/rules/` 순수 규칙(`combat_state.gd`, `rng.gd`, `geom.gd`, `bot.gd`): Node·Vector2·입력·그리기 없음. 고정 단계 1/120초.
- `scripts/game/` 표시·연결부(`step_driver.gd` 프레임→단계·누름 1회 소비, `combat_view.gd` 입력 읽기와 `_draw`, `main.gd` 화면 전환·HUD·F3 비교 설정, `game.gd` 자동 로드·설정).
- `scenes/main.tscn` 단일 씬. `tests/`, `tools/` 검증용. `docs/` 기록·캡처(`.gdignore`로 Godot이 가져오지 않음).
