# project.godot 의 기본값 아닌 설정과 그 이유

**주석을 project.godot 안에 두지 않는다.** Godot 편집기는 프로젝트를 열 때 그 파일을 다시 쓰면서
`;` 주석을 **전부 지운다**(2026-09-09에 실제로 그렇게 됐다). 그래서 설명은 여기에 둔다.

| 설정 | 값 | 왜 |
|---|---|---|
| `application/config/name` | `텐데이즈투둠스데이` | 창 제목이 되는 표시명. **정본은 `scripts/game/game.gd` 의 `APP_NAME` 이고 여기는 엔진용 사본**이다(엔진은 GDScript 상수를 못 읽는다). 두 값이 어긋나지 않는지는 `name_tests` 가 본다 |
| `application/config/use_custom_user_dir` | `true` | **사용자 저장 자리를 옛 이름에 묶어 두는 열쇠.** Godot 의 `user://` 는 원래 `config/name` 에서 파생돼서, 이름만 바꾸면 저장 폴더가 함께 바뀌고 사용자가 하던 회차·프로필·처치 기록에 못 닿는다 |
| `application/config/custom_user_dir_name` | `Godot/app_userdata/예언의 시간표 — Godot 첫 전투` | 위 열쇠가 가리키는 실제 경로. 여기 적힌 옛 이름은 **표시명이 아니라 폴더 이름**이다. 지우지도 새 이름으로 바꾸지도 마라 — 바꾸는 순간 사용자의 저장이 끊긴다. `docs/NAMING.md` |
| `window/size/viewport_width` · `_height` | 960 · 640 | 전장 기준 크기. 판정·좌표가 이 값을 전제한다 |
| `window/stretch/mode` | `canvas_items` | 화면이 커져도 전장 비율을 유지한다 |
| `window/stretch/aspect` | `expand` | 양옆 여백을 UI가 쓰되 **플레이 공간·판정은 안 바뀐다** |
| `window/handheld/orientation` | `0`(가로) | 폰에서 가로로 시작한다. `docs/ORIENTATION.md` |
| `gui/theme/custom_font` | `res://assets/fonts/ui.ttf` | **웹에는 운영체제 글꼴이 없어 이게 빠지면 한글이 전부 네모(□)** 가 된다. 엔진 시작 때 기본 테마 글꼴과 `ThemeDB.fallback_font`를 함께 채운다. `docs/WEB_BUILD.md` §2 · `docs/FONT_LICENSE.md` |
| `editor/movie_writer/fps` | 24 | 실제 속도 영상. `--write-movie`로 찍을 때만 쓰인다 |
| `editor/movie_writer/movie_file` | `""` | 비워 둔다. 실수로 편집기 실행이 영상을 쓰지 않게 |
| `editor/movie_writer/mjpeg_quality` | 0.35 | 4.7.2에서 **결과 크기를 바꾸지 않는 것으로 측정됐다**(0.35와 0.05가 바이트까지 같은 파일). 용량은 길이로만 조절한다 |
| `editor/movie_writer/disable_vsync` | true | 촬영 중 프레임이 화면 주사율에 묶이지 않게 |

## 편집기를 열었다 닫으면 이 파일이 바뀔 수 있다

Godot 편집기는 항목 순서를 다시 정렬하고 주석을 지운다. **설정 값 자체가 사라지지는 않아야 한다** —
2026-09-09에는 `window/handheld/orientation`과 `movie_writer/movie_file`이 실제로 지워져 되살렸다.
편집기를 연 뒤에는 `git diff -- prophecy_godot/project.godot`로 **값이 없어지지 않았는지** 한 번 보는 것이 좋다.
