# 화면 방향과 전체화면 — 폰 가로 화면 대응

**무엇을 하는 문서인가.** 폰 브라우저(안드로이드 크롬)에서 **가로로 크게** 하고,
**세로로 돌아간 동안 다치지 않게** 하는 부분만 적는다.
조작 버튼의 크기·자리·터치 판정은 여기서 정하지 않는다 — `docs/TOUCH_CONTROLS.md`(조작 담당)의 몫이다.
이 쪽은 **화면 크기가 바뀐 것을 알아채고 알리는 것**까지다.

| 항목 | 파일 |
| --- | --- |
| 안내막(세로 안내 · '계속' · 전체화면 다시) | `scripts/game/screens/orient_gate.gd` (`POrientGate`) |
| 판정·일시정지·전체화면 요청·신호 | `scripts/game/main.gd` |
| 입력 즉시 해제 | `scripts/game/combat_view.gd` `release_inputs()` |
| 제목 화면 버튼 | `scripts/game/screens/title.gd` |
| 회귀 검사 | `tests/orient_tests.gd` (`python tools/run_suites.py --suites orient_tests --jobs 1`) |

---

## 1. 버튼 — 무엇이 어디에 있는가

| 버튼 | 글자 | 자리 | 언제 보이나 |
| --- | --- | --- | --- |
| 전체화면으로 시작 | `전체화면으로 시작` (18pt, 최소 높이 = `PLayout.primary_button_height()`) | **제목 화면 메뉴 맨 위**(부제 아래, '계속하기'·'새 회차'보다 위). 바로 아래 11pt 흐린 한 줄: "폰에서 주소창을 감추고 가로로 고정합니다. 되지 않는 기기에서는 그대로 진행합니다." | 항상 |
| 전체화면(구석) | `전체화면` (13pt) | **안전 영역 오른쪽 위 구석**(위 4px, 오른쪽 8px, 108×34). 터치 '빌드' 버튼(안전 영역 위에서 54~114px)과 세로로 겹치지 않는다 | 전체화면을 **요청한 적이 있고 지금 전체화면이 아닐 때**. 안내막이 떠 있으면 대신 안내막 안의 버튼을 쓴다 |
| 전체화면으로 다시 들어가기 | `전체화면으로 다시 들어가기` (15pt) | 안내막 안('계속' 옆) · 일시정지 화면(3번째 줄) | 위와 같은 조건 |
| 계속 | `계속` (20pt, 200×주버튼높이) | 안내막 한가운데 | **가로**이면서 세로 때문에 멈춘 전투가 남아 있을 때만 |

**제목 화면의 Enter(기본 버튼)는 그대로다.** 새 버튼은 `default_button`을 가져가지 않는다
(저장이 있으면 '계속하기', 없으면 '새 회차'). 전체화면 버튼을 눌러도 **회차가 시작되지 않고 화면도 바뀌지 않는다** —
전체화면만 요청한다. PC에서 달라지는 것은 **버튼이 하나 늘어난 것뿐**이다.

---

## 2. 전체화면·가로 고정을 부르는 정확한 경로

`main.request_fullscreen_landscape()` **하나**뿐이다. 버튼 콜백에서 **곧바로** 부른다 —
브라우저는 사용자 제스처 안에서만 전체화면·방향 고정을 허락하므로, 한 프레임 미뤄도 거절당한다.

```
버튼 pressed → title._on_fullscreen() / POrientGate.fullscreen_pressed
            → main.request_fullscreen_landscape()
```

| 갈래 | 조건 | 하는 일 | `last_fullscreen_result` |
| --- | --- | --- | --- |
| 웹 | `OS.has_feature("web")` | `JavaScriptBridge.eval(FS_ENTER_JS, true)` — `document.documentElement.requestFullscreen()`(webkit/moz/ms 대체 포함) 뒤 `screen.orientation.lock('landscape')` | `{web: true, fullscreen: "요청함", orientation: "요청함(가로)"}` |
| PC 창 | 웹이 아니고 `DisplayServer.get_name() != "headless"` | `DisplayServer.window_set_mode(WINDOW_MODE_FULLSCREEN)`. **방향 개념이 없어 고정은 하지 않는다** | `{web: false, fullscreen: "창 모드 전환", orientation: "건너뜀"}` |
| 헤드리스(검사) | `DisplayServer.get_name() == "headless"` | **아무것도 하지 않는다** | `{web: false, fullscreen: "건너뜀", orientation: "건너뜀"}` |

어느 갈래든 `_fs_wanted`(요청한 적 있음)만은 참이 되고, 이것이 '다시 들어가기' 버튼의 조건이다.

### 거절·미지원을 삼키는 방법 (콘솔 오류가 남지 않는 근거)

거절은 두 갈래로 온다. 둘 다 잡는다.

1. **동기 예외** — `requestFullscreen`·`orientation.lock`이 없거나 `NotSupportedError`를 그 자리에서 던지는 경우.
   → 스크립트 전체가 `try { … } catch (e) { return 0; }` 안에 있고, 방향 고정도 자기 `try`를 따로 갖는다.
2. **Promise 거부** — 사용자 제스처 밖이거나 iOS 사파리처럼 지원하지 않는 경우.
   → `p.then(lock, function(){ lock(); })`처럼 **거부 처리기를 함께 준다.**
   `.catch` 없이 두면 브라우저가 "Uncaught (in promise)"를 콘솔에 찍는다. 처리기를 주면 찍지 않는다.
   방향 고정도 `q.then(function(){}, function(){})`로 같은 처리를 한다.

GDScript 쪽에는 `push_error`·`push_warning`이 **하나도 없다.** 반환값은 `_js_truthy()`가
`null`(웹이 아님)·불린·수·문자열을 모두 안전하게 읽는다. 실패해도 화면을 막거나 오류 화면을 띄우지 않는다.

### 전체화면에서 빠져나온 것을 아는 법

| 갈래 | 방법 |
| --- | --- |
| 웹 | 처음 한 번 `fullscreenchange`·`webkitfullscreenchange` 감시자를 걸어 `window.__prophecyFs`를 갱신하고, 0.5초마다 그 값을 읽는다(`FS_STATE_JS`) |
| PC 창 | 0.5초마다 `DisplayServer.window_get_mode()`가 `FULLSCREEN`/`EXCLUSIVE_FULLSCREEN`인지 본다 |
| 헤드리스 | **읽지 않는다.** 검사가 `main.note_fullscreen_state(true/false)`로 흉내 낸 값을 그대로 둔다 |

상태가 바뀌면 `note_fullscreen_state()`가 안내막·버튼을 다시 맞추고 화면 크기 신호를 한 번 보낸다.

---

## 3. 세로/가로 판정

```gdscript
POrientGate.is_portrait(size)   # size.y > size.x 이면 세로. 크기를 못 읽으면(0 이하) 세로가 아니다
```

**화면 크기 비율만 본다.** 회전 사건(`orientationchange`)을 쓰지 않으므로

- 폰을 세로로 돌린 것과
- **PC에서 창을 세로로 줄인 것**

이 같은 상태가 된다. 그래서 헤드리스 검사에서 `root.size = Vector2i(480, 900)` 한 줄로 회전을 재현할 수 있다
(창 480×900 → stretch(`canvas_items`·`expand`)로 canvas 960×1799 → 세로).

크기가 바뀌는 계기는 회전만이 아니다. **주소창이 뜨고 지는 것 · 전체화면 전환 · PC 창 크기 조절**이
모두 `Viewport.size_changed` 하나로 온다 → `main._on_viewport_resized()`.

---

## 4. 세로 전환 → 일시정지 → 입력 해제 → '계속' 재개

실제 값 흐름(검사 `tests/orient_tests.gd`가 그대로 확인한다).

```
① 창이 세로가 된다            root.size = (480,900) → canvas (960,1799)
② size_changed               main._on_viewport_resized()
      ├ _layout_hud()        HUD·전장·터치 배치 다시 맞춤(안전 영역 기준)
      └ refresh_orientation()
            _portrait = true
            _pause_for_portrait()          ← 전투 중일 때만
                orient_paused = true
                view.set_paused(true)      ← **이미 있는 일시정지 경로**(전투 시간·재사용 시간이 함께 멈춘다)
                view.release_inputs("세로 전환")   driver.reset() + router.reset()
                touch.release_all()        ← 잡고 있던 가상 스틱·버튼 해제(조작 담당의 공개 함수)
            _sync_orient_gate()            안내막 = 세로 안내
            screen_metrics_changed.emit(...)
③ 세로인 동안                 combat_view._process()가 곧바로 돌아간다 → 단계 0
      st.t · st.step_n · player.hp · enemies 가 **하나도 바뀌지 않는다**
④ 가로로 돌아온다             _portrait = false, 하지만 orient_paused 는 그대로
      안내막 = '계속' 버튼 (자동 재개 없음)
⑤ 사용자가 '계속'             main.orient_resume()
            orient_paused = false
            view.set_paused(false)         다른 정지 이유(일시정지 화면·3택·용어 고정·빌드 상세)가 없을 때만
```

검사가 실제로 찍은 값(38개 단언 중):

| 시점 | 전투 시간 t | 단계 | 체력 | 적 |
| --- | ---: | ---: | ---: | ---: |
| 전투 시작 | 0.0083 | 1 | 100 | 0 |
| 12프레임(1.2초) 진행 | 1.2083 | 145 | 100 | 3 |
| **세로 전환 직후** | 1.2083 | 145 | 100 | 3 |
| 세로에서 40프레임(4초분) 더 굴린 뒤 | **1.2083** | **145** | **100** | **3** (배치 해시까지 같다) |
| '계속' 뒤 10프레임 | 2.2167 | 266 | 100 | 6 |

**세로인 동안 피해를 받을 수 없다** — 규칙을 진행시키는 단계 자체가 하나도 돌지 않기 때문이다.
`scripts/rules/**`는 한 줄도 고치지 않았다. 새 일시정지 규칙도 만들지 않았다.

### 자동 재개를 막는 자물쇠

`orient_paused`가 참인 동안에는 **다른 어떤 경로로도 재개되지 않는다.**

| 경로 | 처리 |
| --- | --- |
| `set_pause(false)`(Esc·일시정지 화면의 '계속') | `view.set_paused(v or … or orient_paused)` → 여전히 멈춤 |
| `close_choice()` · `_on_detail_closed()` · `_on_tip_pins(0)` | 각각 `and not orient_paused` 조건 추가 |
| 가로 복귀 | 판정만 바꾸고 재개하지 않는다 |
| 전투를 벗어남(`show()`가 combat이 아닌 화면으로 · `go_title()`) | `orient_paused = false`(기다릴 전투가 없다) |

세로 상태에서 전투가 **새로** 시작되는 경우(세로인 채 출격)는 `_process`의 `_orient_guard()`가
그 프레임에 다시 잡아 멈춘다.

---

## 5. 조작 담당에게 보내는 신호

```gdscript
signal screen_metrics_changed(metrics: Dictionary)   # main.gd
func screen_metrics() -> Dictionary                  # 같은 값을 아무 때나 읽는 창구
```

**뜻: "화면 크기가 바뀌었다. 자리를 다시 잡아라."** 주소창이 뜨고 지는 것 · 전체화면 전환 ·
회전 · PC 창 크기 조절 · 전체화면 상태 변화가 모두 이 신호 하나로 온다.
**자리 계산은 하지 않는다** — 받는 쪽(`PLayout`·`PTouchControls`)이 정한다.

| 열쇠 | 뜻 |
| --- | --- |
| `visible` (`Rect2`) | 보이는 canvas 영역 (`Viewport.get_visible_rect()`) |
| `safe` (`Rect2`) | 안전 영역 (`PLayout.safe_rect()`) — 노치·둥근 모서리를 뺀 자리 |
| `portrait` (`bool`) | 세로인가 |
| `bucket` (`String`) | `wide` / `standard` / `narrow` (`PLayout.aspect_bucket()`) |
| `fullscreen` (`bool`) | 지금 전체화면인가 |
| `touch` (`bool`) | 터치 화면인가 (`PLayout.is_touch()`) |

받는 쪽 예:

```gdscript
main.screen_metrics_changed.connect(_on_metrics)

func _on_metrics(m: Dictionary) -> void:
    _relayout(m.safe, bool(m.portrait))
```

`main._layout_hud()`는 이 신호와 **별도로** 이미 `touch.layout(safe)`·`build_hud.relayout(safe)`를
같은 크기 변화에서 부른다. 신호는 그 밖의 쪽(직접 연결하고 싶은 화면·도구)을 위한 창구다.

---

## 6. 검사

```
python tools/run_suites.py --suites orient_tests --jobs 1
```

`PROPHECY_TOUCH=1`로 돈다 — 세로 전환 순간 **터치 입력이 풀리는지**를 보려면 오버레이가 켜져 있어야 한다.

| 절 | 확인 |
| --- | --- |
| A | 제목 화면에 '전체화면으로 시작'이 있고 눌린다 · Enter 기본 버튼을 가로채지 않는다 · 눌러도 회차가 시작되지 않는다 |
| B | 전체화면이 실패한 뒤에도 새 회차 → 거점이 정상 |
| C | 세로 크기 → '휴대폰을 가로로 돌려주세요' · 전투 밖에서는 '계속'이 없다 |
| D | 전투 중 세로 → 일시정지, 40프레임을 굴려도 시간·체력·적 배치가 그대로 |
| E | 세로 전환 순간 스틱·회피 유지·대기 누름이 모두 해제 |
| F | 가로 복귀만으로는 재개되지 않고, Esc로도 안 풀리며, '계속'을 눌러야 재개 |
| G | 전체화면 이탈을 흉내내면 다시 들어가는 버튼이 나타나고, 눌러도 오류가 없다 |
| H | `screen_metrics_changed`가 오고 여섯 열쇠가 들어 있다 |
| I | PC 가로 창 회귀: 안내막 없음 · Esc 일시정지/재개 그대로 · 960×640 = `standard` |

---

## 7. 확인한 것과 못 한 것

| 단계 | 상태 |
| --- | --- |
| 헤드리스 회귀(창 크기로 회전 재현) | **확인함** — `orient_tests` 38/38 |
| 기준 전투(D33) 지문 불변 | **확인함** — `run_tests` 통과 |
| **JS 조각 자체**를 크롬에서 실행 | **확인함** — 아래 |
| 게임(웹 빌드)을 브라우저에서 눌러 보기 | **미검증** — 웹으로 내보내 사람이 눌러야 한다 |
| **실제 안드로이드 기기** | **미검증** — 기기가 없다. `docs/WEB_BUILD.md` §7 점검표 13~16번으로 사람이 확인한다 |

### JS 조각 확인 (크롬, 2026-09-09)

`main.gd`에서 `FS_ENTER_JS`·`FS_STATE_JS`를 **글자 그대로 뽑아** 로컬 정적 페이지(`127.0.0.1`)에서 돌렸다.
게임을 돌린 것이 아니라 **스크립트만** 돌린 것이다(문법과 거절 삼키기 확인이 목적).

```
ENTER returned: 1                       ← 스크립트가 끝까지 돌았다
STATE returned: 0                       ← 지금 전체화면 아님
hook=1 fsFlag=false                     ← fullscreenchange 감시자가 한 번만 걸렸다
has requestFullscreen: true / has orientation.lock: true
AFTER 1.5s uncaught errors/rejections: NONE (0)
```

이 페이지에서 전체화면 요청은 **실제로 거부됐다**(사용자 제스처 밖에서 불렀으므로) —
바로 우리가 삼켜야 하는 그 경우다. 결과:

- `window.onerror` 0건 · `unhandledrejection` **0건** · `console.error` 0건.
- 콘솔에 남은 것은 크롬 **자신의 경고** 한 줄뿐이다:
  `[warn] Failed to execute 'requestFullscreen' on 'Element': API can only be initiated by a user gesture.`
  이것은 브라우저가 거부를 알리는 경고이지 우리 코드가 낸 오류가 아니며,
  실제 게임에서는 **버튼 콜백 안**에서 부르므로 이 경고 자체가 나지 않는다.

**iOS 사파리는 `screen.orientation.lock`을 지원하지 않고 `requestFullscreen`도 제한적이다.**
그 경우 요청은 조용히 실패하고 세로 안내만 뜬다 — 게임은 그대로 돈다.
