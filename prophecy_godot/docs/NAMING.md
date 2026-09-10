# 게임 이름 — 표시명은 바꾸고, 저장 자리는 그대로 둔다

확정(2026-09-10 사용자):

| | 이름 |
|---|---|
| 한국어 | **텐데이즈투둠스데이** |
| 영어 | **Ten Days to Doomsday** |

옛 이름은 `예언의 시간표`(project.godot 의 표시명은 `예언의 시간표 — Godot 첫 전투`, 제목 화면은 `예언의 시간표 (가칭)`)였다.

---

## 1. 왜 이름만 바꾸면 안 되는가

Godot 의 `user://` 는 **`application/config/name` 에서 파생된다.** 윈도우에서는 이렇게 만들어진다:

```
%APPDATA%/Godot/app_userdata/<config/name>/
```

지금 이 폴더 안에 사용자의 **진행 중인 회차(`prophecy_save_v1.json`) · 영구 프로필(`prophecy_profile_v1.json`) ·
처치 기록(`prophecy_records_v1.json`) · 입력 기록(`recordings/`) · 소리·화면 설정**이 들어 있다.

`config/name` 만 새 이름으로 바꾸면 엔진이 **`.../app_userdata/텐데이즈투둠스데이/` 라는 빈 폴더를 새로 만든다.**
게임은 멀쩡히 돌아가지만 사용자가 보기에는 **하던 회차가 통째로 사라진 것**이 된다. 옮기는 코드를 넣는 방법도 있지만,
파일을 옮기다 실패하면 그때는 되돌릴 것이 없다. 그래서 **파일을 건드리지 않고 경로를 옛 이름에 못 박는 쪽**을 골랐다.

## 2. 고른 방법 — project.godot 세 줄

```ini
config/name="텐데이즈투둠스데이"
config/use_custom_user_dir=true
config/custom_user_dir_name="Godot/app_userdata/예언의 시간표 — Godot 첫 전투"
```

`use_custom_user_dir=true` 이면 엔진은 `config/name` 을 더 이상 저장 경로에 쓰지 않고
`custom_user_dir_name` 을 `%APPDATA%` 뒤에 그대로 붙인다(경로 구분자 `/` 를 허용한다).
결과가 옛 경로와 **글자 하나까지 같아진다.**

> **`custom_user_dir_name` 은 옛 표시명이 아니라 폴더 이름이다.**
> 여기 적힌 `예언의 시간표 — Godot 첫 전투` 를 새 이름으로 "정리"하는 순간 사용자의 저장이 끊긴다.
> 지우지도, 바꾸지도 마라. 이 값은 `tests/name_tests.gd` 가 지킨다.

실측(같은 PC, 가짜 APPDATA 로 격리해 확인. 사용자 원본 폴더는 읽지도 쓰지도 않았다):

| | `OS.get_user_data_dir()` |
|---|---|
| 변경 전 | `<APPDATA>/Godot/app_userdata/예언의 시간표 — Godot 첫 전투` |
| 변경 후 | `<APPDATA>/Godot/app_userdata/예언의 시간표 — Godot 첫 전투` |

## 3. 표시명은 한 자리에서만 읽는다

정본은 **`scripts/game/game.gd` 의 상수 두 줄**이다.

```gdscript
const APP_NAME := "텐데이즈투둠스데이"
const APP_NAME_EN := "Ten Days to Doomsday"
```

화면은 `PUi.app_name()` · `PUi.app_name_en()` 으로만 읽는다(판본 `PUi.version()`, 글꼴 고지 `PUi.font_notice()` 와 같은 방식 —
자동 로드 없이 헤드리스 시험에서도 읽힌다). **화면 코드에 이름을 직접 적지 마라.**

예외가 하나 있다: `project.godot` 의 `config/name`. 엔진이 창 제목을 만들 때 쓰는 값이라 GDScript 상수를 읽을 수 없어
같은 값을 한 벌 더 적어 둔다. 두 값이 어긋나지 않는지는 `name_tests` 가 본다.

---

## 4. 어디를 바꿨고 어디를 그대로 뒀나

### 바꾼 자리 — "지금 이 게임을 소개하는 표시명"

| 자리 | 전 | 후 |
|---|---|---|
| `project.godot` `config/name`(= 창 제목) | `예언의 시간표 — Godot 첫 전투` | `텐데이즈투둠스데이` |
| `scripts/game/game.gd` | (없음) | `APP_NAME` · `APP_NAME_EN` **정본 신설** |
| `scripts/game/ui/widgets.gd` | (없음) | `PUi.app_name()` · `PUi.app_name_en()` 신설 |
| 제목 화면 큰 글씨 `screens/title.gd` | `"예언의 시간표 (가칭)"` 직접 기입 | `PUi.app_name()` |
| 제목 화면 부제 `screens/title.gd` | `마검사의 준비 기간 — 액션 로그라이트` | 앞에 `Ten Days to Doomsday · ` 를 덧붙임 **(PC에서만)** |
| 설정 화면 판본 줄 `ui/settings_panel.gd` | `판본 v1.3.2` | `텐데이즈투둠스데이 (Ten Days to Doomsday) · 판본 v1.3.2` |
| `docs/PROJECT_SETTINGS.md` | (없음) | 세 줄의 값과 이유를 표에 추가 |
| `docs/NAMING.md` | — | 이 문서(신설) |

부제의 영어 표기를 **PC에서만** 붙이는 이유: 터치에서는 글자가 1.6배로 커진다. 이 한 줄이 두 줄로 접히면
메뉴가 캔버스(640)를 넘어 아래 항목(설정·종료·글꼴 고지)이 잘린다 — 폰 가로 854×400 에서 메뉴 높이 851 로 실측된 적이 있다
(`screens/title.gd` 주석). 그래서 **줄 수를 늘리지 않는 자리에만** 넣었다.

### 그대로 둔 자리 — 옛 이름이 남아 있어야 하는 곳

| 자리 | 남은 값 | 왜 그대로 두나 |
|---|---|---|
| `project.godot` `config/custom_user_dir_name` | `Godot/app_userdata/예언의 시간표 — Godot 첫 전투` | **표시명이 아니라 사용자 저장 폴더 이름.** 바꾸면 사용자가 자기 저장에 못 닿는다 |
| `user://` 안의 파일 이름 (`prophecy_save_v1.json` · `prophecy_profile_v1.json` · `prophecy_records_v1.json`) | 그대로 | 저장 키다. 이름 때문에 저장을 옮기거나 초기화하지 않는다 |
| 폴더 이름 `prophecy_godot/` · 도구 경로 `tools/**` | 그대로 | 사람이 보는 표시명이 아니다. 경로를 바꾸면 문서·명령·기록이 전부 끊긴다 |
| `class_name` 의 `P` 접두(`PUi` · `PRun` · `PSave` …) | 그대로 | 내부 식별자. 표시되지 않는다 |
| 자료 파일 이름·내부 id (`data/**`) | 그대로 | 규칙과 저장이 이 id 로 이어져 있다 |
| `docs/PORT_NOTES.md` 의 실행 기록에 나오는 옛 경로 | 그대로 | **역사 기록**이다. 그때 그 경로가 실제로 그랬다 |
| `docs/captures/web_font_9bd00bd/README.md` 의 화면 설명 | 그대로 | 그때 찍은 화면에 실제로 그 글자가 있었다. 과거 보고서는 고치지 않는다 |
| `tests/font_tests.gd` 의 `"예언의 시간표"` | 그대로 | 글자 폭을 재는 **표본 문자열**이다. 표시명이 아니고, 이 작업의 소유 범위 밖이다 |

### 아직 손대지 않은 자리 (이 작업의 소유 범위 밖 — 다음에 처리해야 한다)

| 자리 | 남은 값 | 메모 |
|---|---|---|
| `README.md` 1행·3행 | `예언의 시간표(가칭) — Godot 이식`, "게임 이름은 아직 미정(가칭)입니다" | 저장소 소개 문서. **이름이 확정됐으므로 고쳐야 한다** |
| `export_presets.cfg` | `product_name="Prophecy Godot (가칭)"`, `file_description="예언의 시간표(가칭) Godot 이식"` | 윈도우 exe 속성에 보인다. 다음 내보내기 전에 고쳐야 한다 |
| `tools/deploy_web.py` | 웹 시험 빌드 페이지의 `<title>` · `<h1>` · README | 웹 배포 페이지에 보인다 |

이 셋은 사람이 보는 표시명이 맞다. 다만 이번 작업의 소유 범위(`project.godot` · `scripts/game/**` 표시 문자열 ·
`data/glossary.json` · `tests/name_tests.gd` · `tools/suites.json` · `docs/`)에 들어 있지 않아 **일부러 손대지 않았다.**

### 확인했지만 바꿀 것이 없던 자리

- `data/glossary.json` — 옛 이름이 **0건**이다(73개 항목 전수 확인). 게임 이름을 소개하는 항목이 원래 없다.
  표시명을 여기에 새로 적으면 정본이 두 곳이 되므로 **넣지 않았다**(§3).
- 창 제목을 코드에서 따로 세우는 자리 — 없다(`DisplayServer.window_set_title` 호출 0건). 창 제목은 `config/name` 이 그대로 쓰인다.

---

## 5. 검사

`tests/name_tests.gd` (`python tools/run_suites.py --suites name_tests --jobs 1`) 가 다섯 갈래를 본다:

1. `application/config/name` 이 새 이름이고, 창 제목이 될 값에 옛 이름이 남아 있지 않다.
2. 표시명의 정본이 한 자리다 — `game.gd` 의 상수 = `PUi.app_name()` = `project.godot` 의 사본.
3. `use_custom_user_dir` 이 켜져 있고, `custom_user_dir_name` 이 옛 이름 폴더이며,
   `OS.get_user_data_dir()` 이 실제로 그 폴더로 끝난다(그리고 새 이름이 경로에 끼어들지 않았다).
4. 공용 실행기의 격리(APPDATA 바꿔치기)가 여전히 먹힌다 — 경로에 `userdata__` 또는 `prophecy_test_runs` 가 있다.
   격리가 걸려 있지 않으면 5를 **하지 않고 실패로 끝낸다**(사람의 저장을 건드릴 수 있으므로).
5. 그 격리된 자리에서 회차·프로필·처치 기록을 **새로 만들어** 저장 → 다시 읽기(이어하기) 했을 때 값이 살아남고,
   세 파일이 모두 **옛 이름 폴더 안에** 놓인다.

사용자 원본 저장(`%APPDATA%/Godot/app_userdata/...`)은 읽지도 쓰지도 않는다.
