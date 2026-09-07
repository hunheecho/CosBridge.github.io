# Godot 이식 기록 — 첫 전투 (2026-09-07)

## 1. 기준 커밋·버전
| 항목 | 값 |
|---|---|
| 이식 기준 HTML | `prophecy_action_prototype` v0.8.0, 커밋 **ee10fc7** (작업 시작 시 최신, 작업 트리 깨끗함 확인) |
| Godot 프로젝트 커밋 | 아래 "커밋 기록" 절 |
| Godot 프로젝트 버전 | `godot-0.3.0` (`project.godot` `config/version`, 시작 화면·HUD 하단에 표시). 0.1.0 = 이식 그대로, 0.2.0 = 회피 시험 설계, 0.3.0 = 늑대 물기·돌진 빈도·밀도 시험(docs/RULES.md) |
| 엔진 | **Godot 4.7.2-stable** 공식 배포본 (`4.7.2.stable.official.ed1daf0bf`), GDScript만, 2D, Compatibility 렌더러 |
| 내보내기 템플릿 | 공식 `Godot_v4.7.2-stable_export_templates.tpz` → `windows_release_x86_64.exe` (템플릿 버전 = 엔진 버전 4.7.2.stable) |
| HTML 프로젝트 | 손대지 않음(비교 기준). 추가한 것은 대조 스크립트 `tools/port_compare_html.js` 하나 |

## 2. 작업 환경에서 확인한 것 / 못 한 것
| 항목 | 결과 |
|---|---|
| OS·도구 | Ubuntu 24.04 (Linux x86_64), Godot 편집기 없이 명령줄 실행. `xvfb-run`으로 화면 렌더, ffmpeg(정적 바이너리)로 영상 인코딩 |
| Godot 확보 | GitHub 공식 릴리스에서 Linux 편집기 바이너리·내보내기 템플릿 다운로드. godotengine.org·tuxfamily는 차단, GitHub 릴리스 다운로드만 가능 |
| headless 실행 | `--headless -s` 스크립트 실행 가능 → 규칙 테스트·대조 측정에 사용 |
| 실제 렌더 | Xvfb + OpenGL3(Compatibility)로 `main.tscn` 실행, `get_viewport().get_texture().get_image()`로 화면 저장 → `docs/captures/*.png` 7장(가짜 캡처 아님) |
| 영상 | Godot Movie Maker(`--write-movie … --fixed-fps 30`) PNG 시퀀스 1003장 → `docs/captures/fight_seed7_bot.mp4` 33초(제목→봇 전투→일시정지 1.5초→결과→같은 조건 재시작→결과) |
| Windows 내보내기 | `--export-release "Windows Desktop"` 성공, `prophecy_first_fight.exe` 109MB(pck 내장). **Windows 실기 실행 미확인**(이 환경에 Windows·wine 없음) |
| 미확인 | 실제 키보드 조작(봇·스크립트 입력만 검증), Windows에서의 실행·글꼴 표시(한글은 Godot 기본 글꼴로 Linux에서 정상 표시됨), 편집기 GUI에서의 프로젝트 가져오기(명령줄 가져오기만 확인) |

## 3. 구조 (규칙 ↔ 표시, 데이터 ↔ 코드)
```
data/first_fight.json          첫 전투 숫자 전부(플레이어·검격·늑대·장애물·웨이브·상수). 코드에 숫자 없음
scripts/rules/rng.gd           PRng: HTML PA.rng(mulberry32)와 같은 알고리즘(uint32 마스크 연산)
scripts/rules/geom.gd          PGeom: 거리·각도·선분-원 교차(정적 함수)
scripts/rules/combat_state.gd  CombatState(RefCounted): 순수 규칙. step(input, dt) 하나로 진행. Node·Vector2·Input·그리기 없음
scripts/rules/bot.gd           PBot: 사람 입력과 같은 형식 {mx,my,dodge,special}을 만든다(5스텝마다 판단)
scripts/game/game.gd           자동 로드 Game: JSON 로드, 버전·설정 문자열
scripts/game/combat_view.gd    Node2D: 고정 단계 1/120초 누적기(프레임당 최대 12스텝), 입력→행동 변환, _draw()는 읽기만
scripts/game/main.gd           화면 전환(제목·HUD·일시정지·결과·조작법·F3 검증 패널), 캡처/영상 모드(환경 변수로만 켜짐)
scenes/main.tscn               단일 씬
tests/run_tests.gd             규칙 테스트 25개(headless)
tools/compare_scenario.gd      HTML 대조 측정(COMPARE_JSON 출력)
```
- **입력은 행동으로**: 키(WASD/방향키/Space/Q)는 `combat_view.gd`에서 `{mx,my,dodge,special}`로 바뀌고 규칙은 키를 모른다. 회피·Q 같은 1회성 입력은 프레임의 첫 스텝에서만 소비된다.
- **사람·봇 같은 규칙**: `PBot.step_input`이 같은 dict를 만들어 같은 `CombatState.step`에 넣는다. 시작 화면 "봇 조작으로 보기"가 그 경로.
- **시간·난수 통제**: `dt`는 항상 1/120 고정, 난수는 `PRng(seed)` 하나. 종료 뒤에는 `t`가 멈추고 효과만 진행.
- **그리기는 상태를 바꾸지 않는다**: `_draw()`는 `st`를 읽기만 하고, HUD 갱신도 `_process`에서 읽기만.
- **피해 출처 보존**: `damage_enemy(e, amount, src_key, …)`에 `"weapon:sword"` 같은 출처 키를 처음부터 넘기고 `metrics.dmg[src]`, `metrics.taken[type]`에 과잉 피해를 뺀 실효 피해만 기록. 결과 화면 "피해 출처"가 이 값.
- **Godot 물리 미사용**: 이동·회피·돌진·장애물은 HTML과 같은 스윕 원 충돌(`move_swept`, `push_out`)을 규칙 안에서 직접 계산한다. CharacterBody2D 등을 쓰지 않았으므로 Godot 물리 때문에 생기는 거리·주기 차이가 없다(§5 대조 결과가 그 증거). 나중에 Godot 물리로 바꾸면 §5 측정을 다시 해야 한다.
- **저장**: 첫 전투에는 저장이 없다. 설계만: `{"schema": "prophecy_save/N", …}` 형태로 JSON 한 파일, 로드 시 schema 번호로 변환(HTML `Run.migrate` v3→v4와 같은 방식). 저장 위치는 `user://`.

### HTML 의존 관계 확인(첫 전투가 실제로 쓰는 것)
| HTML 모듈 | 첫 전투에서 쓴 부분 | Godot 처리 |
|---|---|---|
| `data.js` PLAYER·wolf·ARENAS.clearing·CONFIG(STEP·WAVE_DELAY·SPAWN_WARN·SEPARATION·EXPOSED) | 전부 | `first_fight.json`으로 숫자만 옮김 |
| `growth_data.js` sword base(12/0.55/95/110°/넉백 40) | 검격 Lv1 | JSON `weapon` |
| `world_data.js` forest 1일차 웨이브 `[[wolf2],[wolf3],[wolf4]]`, 새벽 변주(마지막 웨이브 없음) | 새벽 변주 적용: `[[wolf2],[wolf3]]` | JSON `waves` (변주 계산 자체는 안 옮김) |
| `combat.js` updatePlayer·moveSwept·pushOut·steerDir·losBlocked·queueWave/edgePos/updateWaves·damagePlayer·damageEnemy·updateWolf·separation·checkObjective | 전부 | `combat_state.gd`에 규칙만 다시 씀(복사 아님) |
| `weapons.js` FIRE.arc·hitArc·pickTarget·init(첫 공격 0.25초·음수 잔여 이월·대상 없으면 0.05초) | 검격만 | `update_attack`·`pick_target` |
| `skills.js` castQ | 감속장 Lv1 | `cast_slowfield`·`update_field`·`time_factor` |
| `bot.js` | 판단 로직은 옮기지 않음 | `PBot`은 첫 전투용 단순 봇(코리도 회피·접근·Q). HTML 봇과 행동이 같지 않다 |
| `render.js`·`screens.js`·`main.js`·`input.js` | 표시·입력 | Godot `_draw`·Control 노드로 새로 작성 |
| 함수가 든 JS 데이터(개조 `apply`, 사건 `choices`, 보스 패턴) | 첫 전투 미사용 | 옮기지 않음. 옮길 때는 JSON이 아니라 GDScript 데이터 또는 Resource로 재작성 필요 |

## 4. 첫 전투 범위 구현 상태
| 요구 | 상태 |
|---|---|
| 시작 화면 | 제목·전투 시작·봇 조작·조작법·시드·종료·버전 한 줄. 설정·검증 정보는 F3 패널로 분리 |
| 검격 자동기술 Lv1 | 사거리 안 가장 가까운 적(시야 차단 제외) 방향으로 110° 부채꼴, 0.55초 주기, 피해 12(빈틈 ×1.5=18), 넉백 40 |
| 이동·Space 회피·Q 감속장 | 220/s(대각선 정규화), 회피 150/0.26초 무적/재사용 0.9초, 감속장 반지름 150·3초·재사용 14초·적 속도 40% |
| 늑대 접근→준비→방향 확정→돌진→빈틈 | 접근(170 안까지)→준비 0.6초(붉은 통로가 플레이어를 따라감)→고정 0.15초(통로 굵어지고 "!")→돌진 800×0.32초=256→빈틈 0.9초(노란색). 고정 뒤에는 플레이어를 따라가지 않음(테스트) |
| 숲 전투·장애물 | 960×600, 바위 2·나무 2. 테두리가 충돌 경계. 이동·돌진 모두 막힘 |
| HUD | 체력 막대·숫자, 회피 재사용 막대·상태, Q 막대·남은 시간(전개 중 남은 초), 목적(남은 적·웨이브·시간) |
| 예고·실제 범위 | 통로 폭 = 2×(늑대 r + 플레이어 r) = 실제 물기 판정 폭(테스트: 옆으로 20 → 맞음, 40 → 안 맞음). 검격 부채꼴 = 실제 판정 범위. 감속장 원 = 실제 감속 범위 |
| 승리·패배·재시작 | 예정 웨이브 모두 소환 + 생존 적 0 → 승리(1회 확정). 체력 0 → 패배(1회, 시간 정지). 결과 화면 Enter → 같은 시드로 재시작 |
| Esc 일시정지·재개 | 전투 시간·회피/Q 재사용이 멈춤, 일시정지 중 눌린 회피/Q는 재개 시 버림(실제 씬에서 확인: `PAUSE_CHECK` 3항목 true) |
| 조작법 화면 | 제목·일시정지 양쪽에서 열림. 읽는 법(통로·부채꼴·빈틈·감속장·테두리) 포함 |
| 하지 않은 것 | 회전 칼날·창·E 기술·성장·상점·날짜·보스·저장(요구대로 제외, 빈 화면도 없음). 마우스 조준·수동 공격 없음. 수치 변경 없음 |

## 5. 검증 결과
### 5-1. 규칙 테스트(`tests/run_tests.gd`, headless) — **25/25 통과**
데이터 로드 / 이동 220·1초 / 회피 150·무적·재사용 0.9 / 재사용 중 회피 거부·0.9초 뒤 허용 / 늑대 상태 순서 / 고정 뒤 방향 불변 / 돌진 256 / 옆으로 비키면 안 맞고 빈틈 진입 / 통로 폭(20 맞음·40 안 맞음) / 바위가 이동·돌진을 막음 / 감속장 안 0.4·밖 1.0·3초 뒤 해제 / 적 0이어도 웨이브 남으면 승리 아님 / 전멸 시 승리 1회 / 체력 0 패배 1회·시간 정지 / 피격 보호 0.6초 / 과잉 피해 집계 제외 / 공격 횟수·빈틈 피해 18 / 같은 시드·같은 봇 → 같은 결과 / 기록 입력 재실행 일치 / 받은 피해 합 = 잃은 체력.

### 5-2. HTML 대조(`tools/compare_scenario.gd` ↔ `prophecy_action_prototype/tools/port_compare_html.js`, 같은 고정 배치·같은 입력)
| 측정 | Godot | HTML |
|---|---|---|
| 1초 이동(직선/대각) | 220.0 / 219.3 | 같음 |
| 회피 거리·무적 스텝·직후 재사용 | 150.0 · 32스텝(0.267) · 0.8933 | 같음 |
| 늑대 준비/고정/돌진/빈틈 스텝 | 72 / 18 / 39 / 109 | 같음 |
| 돌진 거리 | 256.0 | 같음 |
| 검격 시각(9회) | 0.2583, 0.8, 1.35 … 4.65 | 같음 |
| 단타 피해 보통/빈틈 | 14.0 / 18.0 (측정 배치는 데이터의 12 대신 14로 넘긴 값) | 같음 |
| 감속장 안/밖 0.5초 늑대 이동 | 30.0 / 75.0 | 같음 |
| 물기 피해·피격 보호 | 12.0 · 0.6 | 같음 |

처음엔 검격 시각이 달랐다(Godot 0.2083 시작, 주기마다 1/120 누적 지연). 원인: HTML `weapons.js`가 첫 공격 대기 0.25초, 주기 갱신 시 음수 잔여 이월(`max(-interval/2, timer)+interval`), 대상 없으면 0.05초 재시도를 쓰는데 첫 구현이 이를 단순화했었다. 규칙으로 타당한 쪽(누적 오차 없는 이월)을 택해 JSON `first_attack_delay` 0.25와 이월 규칙으로 맞췄다.

**같은 시드 = 같은 전투가 아니다**: RNG 알고리즘은 같지만 호출 순서(소환 위치·봇 판단)가 HTML과 다르므로 시드가 같아도 HTML의 전투를 재현하지 않는다. 그래서 대조는 위처럼 고정 배치·고정 입력 시나리오로 했고, 결정성(같은 시드·같은 입력 → 같은 결과)은 Godot 안에서만 검증했다.

### 5-3. 실제 렌더·흐름(Xvfb, OpenGL3)
`docs/captures/01_title` 제목 → `02_combat_wave1` 1웨이브(늑대 통로·고정 "!"·HUD) → `03_pause` 일시정지 → `04_debug_panel` F3 → `05_controls` 조작법 → `06_combat_later` 2웨이브(감속장·회피) → `07_result` 결과. 봇 전투(시드 7) 요약: 승리, 11.97초, 처치 5, 공격 14(명중 14), 받은 피해 12, 회피 5, 감속장 1, 피해 출처 `weapon:sword 150.0`. 영상 `fight_seed7_bot.mp4`.

### 5-4. 프레임 속도 독립
규칙은 고정 1/120 스텝만 받으므로 프레임 속도와 무관. 영상은 30fps 고정(Movie Maker), 캡처 실행은 Xvfb 가변 프레임 — 둘 다 같은 시드로 같은 경과를 보였다(요약 수치 동일). 프레임이 1/10초보다 길면 스텝을 최대 12개로 잘라 게임 시간이 느려진다(멈춤 방지 의도, HTML과 같은 방식).

## 6. HTML v0.8.0 독립 검토 지적 사항 — 최신 코드(ee10fc7) 확인 결과와 이식 주의
| 항목 | 최신 HTML 상태 | 이식 주의(첫 전투 범위 밖, 구현 안 함) |
|---|---|---|
| A. 봇 출격 경로 ≠ UI 경로 | **남아 있음**. UI는 `Sortie.canStart/start`(카드)만 쓰고, `tools/run_sim.js`의 임무 없는 전략은 `Run.startSortie(run, rid)`를 직접 호출한다(제단 임무 장소를 일반 소탕으로, 완료 장소 재출격) | 성장·경제·관문 빌드 덤프는 검증된 기준선으로 쓰지 않는다. Godot에서는 "선택 가능한 행동 목록" 함수 하나를 사람 UI와 봇이 같이 쓰게 설계(첫 전투는 봇·사람이 같은 `step` 입력으로 이미 통일) |
| B. 저녁 사건 도달 불가 | **남아 있음**. `canSortie`는 `hours >= cost`, 저녁은 남은 칸 1인데 습지·굴·심층 비용 2 → 이 세 곳의 저녁 변주(`SLOT_VARIANTS[*][4]`)는 도달 불가. 숲·능선(비용 1)만 가능 | 시간대 변주를 옮길 때 "도달 가능한 (장소, 시간대) 조합"을 데이터 검사로 강제 |
| C. 개조 예약인데 카드 1장 | **남아 있음**. `growth.js generateOffer`가 레벨 풀에서 `kind+id`가 같은 후보를 하나로 줄인다(검 개조 3개 → 1장) | 기술 ID와 선택지 ID를 구분(`keyOf`처럼 kind:id:mod). 중복 제거 기준은 선택지 ID |
| D. 지속 피해 출처·DPS | **남아 있음**. `srcKey`가 `dot:bleed`로만 기록해 쌍검 출혈이 일반 출혈로 집계됨. 획득 시각과 무관한 전체 시간 분모 문제도 그대로 | 지속 효과는 붙일 때 원인 기술 키를 함께 저장(`{src:"weapon:daggers", kind:"bleed"}`). DPS 분모는 획득 시각부터 |
| E. 심층 장비 보상 편향 | **남아 있음**. `run.js deepPreview`가 같은 시드로 RNG를 다시 만들고 첫 난수를 종류 선택과 아이템 선택에 재사용 → 종류가 equipment이면 항상 같은 색인(개척자의 창) | 보상은 재현성(같은 시드 → 같은 결과)과 다양성(시드마다 다른 결과)을 **둘 다** 테스트. RNG는 한 스트림을 이어서 쓴다 |
| F. 표시값 ≠ 실제값 | **남아 있음**. `screens.js pickStart`가 `d.base.interval`(창 0.70)을 그대로 보여주고 시험 빌드의 0.85를 반영하지 않음. 검증 메뉴가 일반 시작 화면에 있음 | Godot 시작 화면은 실제 설정(`Game.settings_text()`)에서 파생한 값만 표시(검격 12/0.55, 늑대 30). 검증 정보는 F3 패널로 분리했다 |
| G. 원정대의 갑옷 회복 시점 | **불일치 남아 있음**. 코드·`GAME_SPEC` §장비: 귀환 정산당 1회. 데이터 `short`는 "전투 승리 시 체력 8 회복"(승리마다로 읽힘). 합의가 "전투 승리마다 +8"이면 코드가 틀리고, "정산당 1회"면 짧은 문구가 틀리다 | 규칙 시점(전투 승리 시 / 정산 시)을 먼저 정하고 데이터·문구·코드 셋을 같은 값에서 파생. 첫 전투에는 장비가 없다 |

## 7. 다음 이식 순서(첫 전투 확인 뒤)
전제: 사용자가 Windows에서 첫 전투를 실제로 플레이하고 "규칙 감이 HTML과 같다/다르다"를 확인한 뒤 시작한다. 전체 이식이 아니라 아래 순서로 한 덩어리씩.

| 순서 | 내용 | 의존 | 가져올 것(데이터) / 다시 쓸 것(코드) |
|---|---|---|---|
| 1 | 사람 조작 확인 반영: 입력 반응·표시 가독성(통로·부채꼴·HUD) 수정, 키 재배치 필요 여부 | 첫 전투 플레이 | 코드만 |
| 2 | 적 추가: 궁수·도적(능선), 늑대 우두머리(정예) → 웨이브 편성 데이터 확장 | 1 | `data.js` 적 수치·`world_data.js` 편성은 JSON으로. 행동은 `combat_state.gd`에 상태기계로 재작성 |
| 3 | 자동기술 나머지: 관통창·회전 칼날(기본 Lv1) + 자동기술 3개 슬롯 | 2 | `growth_data.js` base 숫자는 JSON. `weapons.js` FIRE.*는 재작성(개조 `apply` 함수는 코드) |
| 4 | Q 변형·E 기술(돌풍 등) | 3 | `skills.js` 재작성, 수치 JSON |
| 5 | 전투 목표 4종·시간대 변주·장애물 배치안(지역별 아레나) | 2 | `ARENAS`·`SLOT_VARIANTS`·`OBJECTIVES` 데이터 JSON(§6 B 도달 가능성 검사 포함) |
| 6 | 회차 껍데기: 날짜·시간대·장소 2곳·출격 카드·귀환 정산·패배 | 5 | `run.js`·`sortie.js`·`flow.js` 재작성. 사람 UI와 봇이 같은 "행동 목록" 사용(§6 A) |
| 7 | 성장: 경험치·레벨업 3택·개조·공용 증강·예약(§6 C) | 3, 6 | `growth_data.js`는 함수가 섞여 있어 JSON 불가 → GDScript 데이터 파일(또는 Resource)로 재작성 |
| 8 | 상점·장비 12종·대장간·경제(§6 G 시점 확정) | 6, 7 | `world_data.js` 장비 효과 수치 JSON, 효과 적용은 코드 |
| 9 | 저장 v1(Godot) + 마이그레이션 틀 | 6~8 | 새로 설계(HTML 저장 v4와 호환하지 않음) |
| 10 | 보스 3종·관문·최종 보스 | 2~8 | `boss_data.js` 수치 JSON, 패턴 코드 재작성 |
| 11 | 시험실·시뮬레이션 도구(headless 대량 실행) | 규칙 완성 | `tools/*.js` 대응물을 GDScript headless로 |
| 12 | 그래픽·소리 교체 | 규칙 확정 뒤 | 표시 계층만 |

**의도적으로 미룬 것**: HTML 봇(`bot.js`) 정책 이식(첫 전투는 단순 봇), Godot 물리(CharacterBody2D) 사용 여부 결정(현재 자체 충돌; 바꾸면 §5 재측정), 해상도·전체화면 설정, 게임패드, 사운드, 저장, 용어 사전/툴팁, 밸런스 후보 비교 메뉴, 검증 메뉴의 본편 노출.

## 8. 커밋 기록
- HTML 이식 기준: `ee10fc7`
- Godot 프로젝트(코드·데이터·테스트·캡처·문서): **56d600f** (브랜치 `claude/prophecy-action-prototype-hehbeo`)
- 배포물(같은 브랜치 `prophecy_godot_build/`): `prophecy_godot_project_56d600f.zip`(프로젝트 전체, `git archive`로 만들어 캐시·절대 경로 없음, 0.97MB) · `prophecy_first_fight_windows_godot-0.1.0_56d600f.zip`(Windows 빌드: exe + 실행 안내, 38MB, Windows 실기 실행 미확인)

## 9. 회피 시험 설계 (godot-0.2.0, 2026-09-07)
규칙·수치·검증 상태는 `docs/RULES.md` §회피가 기준. 여기에는 결과 기록만.
- 변경 이유: 사용자가 회피 거리 조절을 제안했고, 기존 0.9초 쿨다운이 너무 짧을 가능성이 있어 기본 1.5초로 시험한다.
- 이번에 바꾸지 않은 것: 적 체력·공격력·검격·Q·성장 수치. 늑대 체력 30 문제는 별도 비교 항목. 게임명·파일명 변경 없음.
- 규칙 테스트 42/42. HTML 대조 14개 중 13개 동일, `dodge_cd_after`만 규칙 변경으로 다름(재사용 시작 시점 출발 기준).
- 실제 씬 시연(`PROPHECY_DODGE_DEMO`, 스크립트 입력, 사람 키보드 아님) 결과 — 탭 / 0.15초 / 0.6초 누름 / 대기 중 누름 / 2.5초 계속 누름:
  - hold·1.5: 회피 4회(대기 중 누름은 발동 없음), 거리 [70.0, 91.3, 150.0, 150.0] (가변 fps) / 영상(30fps 고정) [70.0, 76.9, 150.0, 150.0] — 중간 해제 값의 차이는 해제 시각의 프레임 양자화, 마지막 회피 뒤 남은 대기 0, 뗀 뒤 누름 상태 false
  - fixed·1.5: [150.0, 150.0, 150.0, 150.0], 4회(탭도 150)
  - fixed·0.9: [150.0 ×4] / hold·0.9: [70.0, 86.5, 150.0, 150.0]
- 봇 전투(시드 7, hold·1.5): 승리 11.69초, 처치 5, 공격 14(명중 14), 받은 피해 12, 회피 4회 거리 [150, 150, 88, 150](88은 장애물에 막힘), 회피! 0, 감속장 1. 일시정지 검사 3항목 true(시간·회피/Q 대기 정지, 재개 시 대기 입력 폐기)
- 봇 정책 변경: 입력 형식만 바꿈(press 1회 + 회피가 끝날 때까지 held → 항상 최대 거리 시도). 판단 논리(통로 안이면 옆으로 회피·접근·Q)는 그대로. 봇은 거리를 고르지 않는다.
- 미결(사용자 판단): 막힌 채 누르면 거리 0으로 끝나며 대기 시간을 소모한다 / 0.9 비교 설정은 과거(종료 기준)와 재사용 시작 시점이 다르다 / 회피 중 이동 입력 무시(HTML과 같음)를 유지할지.
- 커밋·배포물(godot-0.2.0): 프로젝트 커밋 **77d48c0**, `prophecy_godot_build/prophecy_godot_project_godot-0.2.0_77d48c0.zip`, `prophecy_first_fight_windows_godot-0.2.0_77d48c0.zip`(Windows 실기 실행 미확인). 0.1.0 ZIP은 삭제.

## 10. 몬스터 밀도·늑대 공격 시험 (godot-0.3.0, 2026-09-07)
규칙·수치는 `docs/RULES.md` §늑대·§밀도, 근거는 `docs/ASSUMPTIONS.md`, 봇 비교는 `docs/DENSITY_REPORT.md`. 0.2.0 회피 작업은 그대로 보존(설정도 그대로 비교에 사용).
- 사용자 결정: 몬스터가 적어 위협이 없다 → 5/25/50 편성 비교, 접촉 피해 없음, 가까우면 물기·멀면 돌진, 물기 자주·돌진 드물게, 예고·반격 가독성. 경험치 예산 고정(성장 미구현: 누적·검증만).
- 규칙 테스트 68/68(0.2.0의 42 + 늑대·밀도 E1~E19 26). HTML 대조: 이동·회피·돌진·감속·검격 시각 등 12개 동일, 달라진 2개는 규칙 변경(`dodge_cd_after` 재사용 시작 시점, `hit_damage_normal` 12 = 공격하지 않는 표적 기준(HTML 14는 빈틈 명중 섞임)).
- 관찰(테스트 E1n): 검격 넉백 40이 물기 준비 중인 늑대를 사거리 44 밖으로 밀어 정면 늑대의 물기가 자주 빗나간다. 봇 결과의 "실행 전 사망 15~27%"와 낮은 물기 명중은 이 상호작용의 영향이 크다. 이번에 넉백·사거리를 바꾸지 않았다(다음 비교 후보).
- 봇 정책: v1(0.2.0: 돌진 통로만 회피) → v2(0.3.0: 물기 고정/유효 부채꼴 안이면 옆으로 회피 추가) + stand(입력 없음) 신설. 규칙 우회 없음.
- 성능(Xvfb 소프트웨어 GL, 실제 GPU 아님): x5 평균 프레임 9.5ms·시뮬 0.33ms/프레임(최대 5.5ms), x10 평균 10.2ms·시뮬 0.61ms(최대 9.2ms), 단계 상한 도달 1프레임(시작 직후 스파이크 130ms 1회). headless 시뮬 µs/단계: base 100, x5 240~270, x10 430~480. 실제 GPU·Windows 프레임은 미확인.
- 커밋·배포물(godot-0.3.0): 프로젝트 커밋 **272608f**, `prophecy_godot_build/prophecy_godot_project_godot-0.3.0_272608f.zip`, `prophecy_first_fight_windows_godot-0.3.0_272608f.zip`(Windows 실기 실행 미확인). 0.2.0 ZIP은 삭제.

## 11. 피해 통계 수정·Windows 로컬 첫 실행 (godot-0.3.1, 2026-09-07)
이 절부터는 **Windows 10 로컬**(Godot 4.7.2.stable.official 편집기 실행 파일, 실제 GPU) 세션 기록이다. 이전 절은 모두 Linux 원격 세션.

### 11-1. 수정한 오류 (Codex 독립 검수 지적, 검토 기준 5093832)
| 항목 | 내용 |
|---|---|
| 위치 | `scripts/rules/combat_state.gd` `damage_player()` |
| 수정 전 | `p.hp -= amount` 뒤 `stats.damage_taken`·`metrics.taken[src]`에 **amount 전체**를 더하고, 사망 처리에서 hp만 0으로 보정. 체력 100에 12 피해 9회 → 실제 감소 100, 통계 108(마지막 타격의 과잉 8 포함). `DENSITY_REPORT.md`의 패배 행 "받은 피해 108"이 이 오류의 결과였다 |
| 수정 후 | `effective = min(amount, max(0, hp))`를 hp·총합·출처별에 동일하게 적용. 명목 피해는 새 필드 `stats.damage_taken_nominal`(summary에도 포함)에만 누적. 생존 판정·피격 보호·회피 무적·사망 뒤 거부 경로는 그대로 |
| 테스트 | E18: "사망했고 합 ≥ 100이면 통과"하던 OR 우회 제거 → 출처별 합 = `damage_taken` = 체력 감소를 엄격 비교. 회귀 추가 E20(12×9 → hp 0·유효 100·명목 108·사망 뒤 추가 집계 없음) · E21(체력 4에서 12 → 해당 출처 +4) · E22(물기 7·돌진 1·물기 1 혼합 → 물기 88/돌진 12/합 100) · E23(회피 무적·피격 보호 거부 시 유효·명목 모두 0). 기대값은 규칙에서 도출했고 구현 결과에 맞추지 않았다 |
| 표시 | 결과 화면·F3 패널의 "받은 피해"·"받은 피해 출처"는 `summary()`를 그대로 읽으므로 코드 변경 없이 유효 피해로 바뀐다. `damage_taken_nominal`은 화면에 표시하지 않는다 |
| 바꾸지 않은 것 | 피해량·체력·재사용·편성 등 난이도 수치 전부, 검격 넉백(정면 물기 빗나감은 버그로 취급하지 않음), 게임명·저장 키·파일명 |

### 11-2. 검증 (Windows 로컬, 이 세션에서 직접 실행)
| 구분 | 실행 여부 | 결과 |
|---|---|---|
| 규칙 테스트 `tests/run_tests.gd` (headless) | 실행함 | 수정 전 68/68 → 수정 후 **72/72** |
| HTML 대조 `tools/compare_scenario.gd` | 실행함 | 14개 측정 0.3.0 기록과 동일(`dodge_cd_after` 0.6333, `hit_damage_normal` 12 포함). 피해 통계 수정은 대조값에 영향 없음 |
| 밀도 보고서 `tools/density_report.gd` | 실행함(수정 전 코드·수정 후 코드 각각 Windows에서) | 같은 OS에서 수정 전후 **승패·시간·등장/처치·명중·경험치 전부 동일**, 달라진 열은 "받은 피해"뿐(패배 행 108 → 100, 출처별 값도 유효 피해로). 봇·규칙은 통계를 읽지 않으므로 예상대로. `docs/DENSITY_REPORT.md`는 Windows 측정으로 교체 |
| 실제 게임 창(`PROPHECY_CAPTURE`, 봇 조작, 시드 7, x5) | 실행함 | 창이 뜨고 캡처 7장 저장 후 종료 코드 0. 결과 화면: 승리 19.51초, 처치 25/25, 받은 피해 24(wolf:bite 24.0), 회피 10(회피! 1), 감속장 2. 한글 글꼴 정상. Windows 실기 실행은 이번이 **처음 확인** |
| 편집기 GUI 가져오기·실행 | 실행함 | `--editor`로 열림(`main.tscn` 로드), 별도로 `--path` 실행 창도 확인. 편집기가 `project.godot`의 기본값 줄(`window/stretch/aspect="keep"`)과 `icon.svg.import`를 다시 써서 diff가 생기는데 동작 차이는 없다(커밋에서 제외, 원복) |
| 스크립트 입력 검증 | 봇 입력만 | `PROPHECY_DODGE_DEMO`는 이번에 다시 돌리지 않음(회피 규칙 미변경) |
| **사람이 키보드로 플레이한 확인** | **하지 않음** | 조작감·가독성·밸런스는 여전히 미검증. 게임 창을 띄운 것은 "실행된다"의 확인일 뿐이다 |

### 11-3. 관찰: OS 간 결과 차이 (미확정, 다음 작업 후보)
- 같은 커밋(272608f 코드)·같은 시드·같은 봇인데 Linux 기록(0.3.0 보고서)과 Windows 재실행이 36행 중 8행에서 **시간·처치·명중이 다르다**(x5 active 시드 3·5, x10 stand 2·3, x10 active 1·2·4·5; base 12행과 x5 stand 6행은 동일). 승패는 전부 같다. 적이 많고 전투가 길수록 갈라진다.
- 추정 원인: 삼각함수·제곱근 등 플랫폼 수학 라이브러리의 마지막 자리 차이가 충돌·조향 판정에서 증폭. 규칙 코드에 시간·프레임 의존은 없고(D10 프레임 독립 테스트), 같은 OS에서는 완전히 재현된다. 확인하려면 두 OS에서 단계별 상태 해시를 비교해야 한다(미실시).
- 영향: "같은 시드 = 같은 전투"는 **같은 OS 안에서만** 보장한다고 문서화(RULES §공통). 밀도 보고서는 이제 Windows 기준이며, 비교는 항상 같은 OS에서 수정 전후를 함께 재측정한다.
- 별개 관찰: `실행 전 사망%` 1/22(4.545…)이 Linux 4, Windows 5로 출력됨 — 값은 같고 `%.0f` 반올림(반올림 규칙) 차이.

### 11-4. 커밋·미작성
- 프로젝트 커밋(godot-0.3.1): **2cb7ae6** (브랜치 `claude/prophecy-action-prototype-hehbeo`, 로컬 커밋. 원격 push 여부는 HANDOFF 참조).
- 배포물 ZIP(`prophecy_godot_build/`)은 0.3.0 그대로(272608f). 0.3.1 Windows 빌드는 내보내기 템플릿이 이 PC에 설치돼 있지 않아 만들지 않았다. 필요하면 `Godot_v4.7.2-stable_export_templates.tpz` 설치 뒤 `--export-release "Windows Desktop"`.
- 제목 화면 부제 "늑대 2 → 3"(`scenes/main.tscn`)은 0.1.0 웨이브 문구가 남은 것(현재 편성은 25마리). 규칙과 무관한 표시 오류라 이번 수정에 섞지 않았다(다음 작업 1번에 포함).

## 12. 합의된 게임 전체 이식 (godot-0.4.0, 2026-09-07, Windows 로컬)
기준 문서: `docs/PORT_BASELINE.md`(권한·충돌 C1~C21·질문 Q1~Q5), `docs/CONTENT_MATRIX.md`(ID별 상태), `prophecy_godot/docs/PORT_CONVENTIONS.md`(규칙 계층 계약), `prophecy_godot/docs/ASSUMPTIONS.md` §전체 게임 이식(잠정값). HTML 기준 커밋 ee10fc7(v0.8.0), Godot 기준 0.3.1(8cad17f).

### 12-1. 환경·명령 (Codex 재현용)
| 항목 | 값 |
|---|---|
| OS | Windows 10 Home 10.0.19045 |
| Godot | 4.7.2.stable.official.ed1daf0bf, `Godot_v4.7.2-stable_win64_console.exe`(headless), 편집기 실행 파일 같은 폴더 |
| 내보내기 템플릿 | 4.7.2.stable 공식 `.tpz` → `%APPDATA%\Godot\export_templates\4.7.2.stable\` (이 세션에서 설치) |
| 데이터 생성 | `node prophecy_action_prototype/tools/port_export_data.js` → `prophecy_godot/data/*.json` (HTML 원본은 수정하지 않음) |
| 클래스 캐시 | `class_name` 파일을 추가한 뒤에는 `godot --headless --path prophecy_godot --import` 1회 |
| 규칙 테스트 | `godot --headless --path prophecy_godot -s tests/run_tests.gd` (기준 전투 72) · `-s tests/port_tests.gd` (전투 콘텐츠 69) · `-s tests/boss_tests.gd` (보스·목표 34) · `-s tests/run_layer_tests.gd` (회차 계층 51) |
| 기준 전투 보존 | `tools/density_report.gd`(0.3.1과 같은 시드 36행 비교), `tools/compare_scenario.gd`(HTML 대조 14개) |
| Windows 빌드 | `godot --headless --path prophecy_godot --export-release "Windows Desktop" <출력 exe>` (preset `export_presets.cfg`, 임베디드 PCK) |

### 12-2. 구현 순서·커밋 (모두 로컬, push 안 함)
| 커밋 | 내용 |
|---|---|
| 8e02ceb | PORT_BASELINE·CONTENT_MATRIX(이식 기준·ID 목록) |
| 32f0599 | 데이터 내보내기·JSON·PORT_CONVENTIONS |
| e256488 | 규칙 뼈대(geom·catalog·build·growth·formation·combat_state 재작성) — 기준 전투 72/72 유지 |
| 18a8176 | port_tests 69 |
| 48e7ff0 | 적 12종·정예·보스 3·목표(objectives) |
| 3167a41 | 봇 정책·boss_tests 34 |
| fe0b23e | 회차 계층(run·sortie·events·flow·stats·save) + delayed 람다 누수 수정 |
| 4f97a5f | run_layer_tests 51 |
| abf311e | 전투 표시(render.gd)·합성음(audio.gd), active 봇 늑대 외 적 보호 |
| f3b79f2 | 회차 봇(run_bot.gd)·run_sim/boss_sim/start_compare + docs/sim |
| f906b6d | godot-0.4.0: 회차 UI 화면 14종·3택·툴팁·설정, E 키, Audio 자동 로드, 전체 회차 자동 진행, FORMATION_TABLE |
| 09b3123 | 밀도 세트(uniform_x5/roles, Q1 답변)·문서·시뮬 보고서·캡처·내보내기 프리셋 |
| 7f36cd9 | 내보낸 빌드 종료 시 오디오 정리(접근 위반 수정)·밀도 세트 비교 기록 — **최종 코드 커밋** |
| (아래 §12-8) | 빌드 ZIP·해시·최종 검증 기록 커밋(문서·ZIP만) |

### 12-3. 검증 결과 (모두 이 PC에서 직접 실행)
| 구분 | 결과 |
|---|---|
| 기준 전투 규칙 `tests/run_tests.gd` | **72/72** (0.3.1과 같은 테스트, `CombatState.first_fight` 경로) |
| 전투 콘텐츠 `tests/port_tests.gd` | **69/69** (자동기술 10·개조·메아리·범용 9·특성 8·Q/E·장비 12·제시·경험치 곡선·지속 피해 원천·지형·편성 변환·종류별 상한) |
| 보스·목표 `tests/boss_tests.gd` | **34/34** (가시갈기·봉인 수호자·예언을 먹는 자 패턴·단계·승리 우선, 목표 4·호위·제단·봉인·구조·위험) |
| 회차 계층 `tests/run_layer_tests.gd` | **51/51** (상점 재고·구매·판매·교체 견적/취소/확정·대장간·개조 변경 환불·출격 시드·정산 1회·패배·휴식·하루 종료·관문 스냅샷/재도전/승리·희귀 보상·예약·심층 미리보기·사건·저장/복구·통계 검증) |
| 기준 전투 밀도 비교 `tools/density_report.gd` | 36행 모두 0.3.1 기록과 **결과 열 동일**(승패·전투 시간·남은 체력·받은 피해·등장/처치·명중·경험치·회피·Q). 달라진 열은 **"시뮬 µs/단계"(프로그램 실행 소요 시간, 벽시계)** 하나뿐이며 이는 코드 양·PC 부하에 따라 매번 다른 성능 수치다. **전투 시뮬레이션 시간("시간" 열)은 동일**하다 → 기준 전투는 규칙·결과 기준으로 동일. 이유: 늑대·회피·검격·소환 규칙과 RNG 소비 순서를 `first_fight` 경로에서 그대로 두었고, 새 규칙(다른 적·기술·밀도 변환)은 이 경로에서 실행되지 않는다 |
| HTML 대조 `tools/compare_scenario.gd` | 14개 측정 0.3.1 기록과 동일(리팩터링 직후 확인) |
| 회차 봇 `tools/run_sim.gd` (시드 1·2, 전략 7종) | 14회차 모두 완주(최종 보스 처치). 평균 레벨 13~19.5, 조우 12.5~16, 패배 0.5~1.5, 전투 5.9~12.3분, 보스 2.0~3.7분, 합계(메뉴 가정 포함) 18.1~25.4분, 금화 83~360. `docs/sim/RUN_SIM.md` |
| 보스 시뮬 `tools/boss_sim.gd` (시드 11·18) | 72전투. 가시갈기는 모든 빌드·정책 승. 봉인 수호자·예언을 먹는 자는 `still`(제자리) 전패, `balanced`/`survival` 전승. `docs/sim/BOSS_SIM.md` |
| 시작 기술 비교 `tools/start_compare.gd` (시드 100·101) | 첫 전투(균형 봇): 검 2승, 회전 칼날 2승, 관통창 0승 2패(test03 근접 약화 적용 상태, Q3 참고). `docs/sim/START_COMPARE.md` |
| 실제 창 자동 진행 `PROPHECY_UI_SMOKE` (시드 1, 봇 balanced) | 새 회차→거점→툴팁→전투(일시정지·조작법·설정·F3)→보상→사건→귀환→상점·대장간·장비·통계→하루 종료→관문→보스전(레벨업 3택)→관문 결과→저장 후 종료→계속하기→거점. 스크립트 오류 0, PNG 24장 |
| 실제 창 전체 회차 `PROPHECY_UI_FULL=1 PROPHECY_UI_SPEED=5` | 위 흐름을 이어 패배 1회(2일차, 패배 화면)→관문 3(가시갈기·봉인 수호자·예언을 먹는 자 모두 처치)→7일차 회차 결과→새 회차 시작 기술 화면까지. 최종 레벨 13, 금화 780, 재도전 0. PNG 26장 |
| Windows 빌드 exe에서 `PROPHECY_UI_SMOKE` | §12-8 |
| **사람이 키보드로 플레이한 확인** | **하지 않음**. 전투 시간·가독성·E 기술 조작감·밀도 체감은 미검증 |

### 12-4. UI 스모크에서 무엇이 "실제 UI 경로"이고 무엇이 "상태 직접 설정"인가
자동 진행(`main.gd` `_auto_tick`)은 **스크립트가 화면 함수를 호출**한다. 키보드·마우스 이벤트를 합성하지 않았으므로 "사람 플레이"가 아니다.
| 구간 | 방식 |
|---|---|
| 제목→새 회차→시작 기술→거점, 출격 카드, 보상→사건→귀환, 상점/대장간/장비/통계 전환, 하루 종료(확인 대화 포함), 관문 입장, 저장 후 종료→계속하기, 회차 결과→새 회차 | 버튼이 호출하는 **같은 함수**(`new_run_flow`·`start_run`·`start_sortie_card`·`after_reward`·`event_choice`·`return_home`·`show`·`end_day`·`start_boss`·`go_title`·`continue_run`)를 스크립트가 호출. 규칙은 전부 `PFlow.actions`/`PRun`/`PSortie` 경로 |
| 전투 | **건너뛰지 않음**. 봇(`PBot balanced`)이 실제 입력 사전을 만들어 `CombatState.step`를 돌린다(사람 입력 경로 `PStepDriver.frame`과 같은 함수, 입력만 봇). `PROPHECY_UI_SPEED=5`는 프레임당 진행 시간 배율(고정 단계 결과 동일, 벽시계만 단축) |
| 3택(레벨업·희귀 보상·임무·사건) | 오버레이가 열리면 **첫 후보를 선택**(`_on_pick(choice.key)`, 버튼과 같은 함수). 후보 내용은 규칙이 만든 것 |
| 툴팁 | `tips._on_click("auto_skill")`로 고정·해제(마우스 좌표 없음) |
| 일시정지·조작법·설정·F3 | 전투 4.5초 시점에 화면 함수 호출 후 캡처 |
| 상태 직접 설정 | 없음(회차 상태를 손으로 바꾼 곳 없음). 시드만 1로 고정 |
| 하지 않은 것 | 키 입력 합성(E·Space·WASD 실제 키), 마우스 클릭 좌표, 상점 구매·교체·개조 변경 조작(회차 봇 헤드리스에서는 수행), 방문 상인·재선택권·E 변형 변경 화면 |

### 12-5. 기준 전투(D33)와 회차 전투의 관계
- 기준 전투는 `first_fight.json`(0.3.1 값)을 `CombatState.first_fight(cfg, seed)`로 실행한다. 늑대 25/12, 동시 돌진 2, 검격 12/0.55, 회피 70~150/1.5초, 감속장, 넉백 ×2 모두 그대로. 제목 화면 검증 메뉴(사람/봇)와 headless(`tests/run_tests.gd`·`tools/density_report.gd`) 양쪽에서 실행된다.
- 회차 전투는 같은 `CombatState`에 카탈로그(`data/*.json`)·빌드·편성 변환(`PFormation.from_waves`)을 넣어 실행한다. 늑대·회피 규칙은 기준 전투와 같은 코드다.
- 밀도 적용 현황(지역×일차×시간대×더 깊이 59행, 종류별 전체 수·동시 상한·역할별 상한·배율·경험치·금화·체력 배율): `FORMATION_TABLE.md`. 요약: **모든 일반 적 일괄 ×5**(근접·원거리·지원 구분 없음), 정예·구조물·보스 소환 ×1, 역할 차이는 종류별 동시 생존 상한으로만 표현, 경험치 예산은 HTML 편성 기준 고정.

### 12-6. 사용자 판단이 필요한 잠정값 (Q1~Q5) — 이미 결정된 것과 새 결정
| 번호 | 질문 | 잠정값(현재 구현) | 선택 근거 | 영향 | 상태 |
|---|---|---|---|---|---|
| Q1 (C4) | HTML 편성(웨이브 2~4마리)을 Godot 밀도로 어떻게 바꾸나? 일괄 배율인가, 지역별 전체 수인가, 역할별로 다른 배율인가? | 일반 적 전부 ×5, 동시 12, 묶음 3·간격 1.0, 종류별 동시 상한(궁수 3·주술사 1·서리술사 2·거미 2·폭탄 3·방패병 3·멧돼지 2·잠복충 2·도적 3·포자 3·우두머리 2), 정예·구조물·보스 소환 ×1 | D33 기준 전투(늑대 5→25)를 정확히 재현하는 정수 배율. 역할별 배율은 사용자 합의가 없어 상한으로만 제한 | 능선 1일 55마리(궁수 35), 굴 5일 71, 심층 6일 더 깊이 133. 봇은 완주하지만 전투 시간 회차당 6~12분 | **사용자 답변 반영(2026-09-07)**: 일괄 ×5는 비교 설정(최종 아님). 비교 후보 세트 `roles` 추가(근접 ×5·원거리 ×2·지원/봉쇄 ×1~2·정예 ×1, 상한 불변, 종류별 예산 보존) — 두 세트의 전투 시간·위협·반복감 비교는 다음 과제 |
| Q2 (C5) | 적 체력 지역 배율과 보스 체력 세트 | 지역 ×1(base), 4일차부터 정예 ×1.25, 보스 hi 2400/5000/7000 | 늑대 30(D33 유지). 보스는 HTML 기본 세트 test03이 가리키는 값(D27 논의값) | 보스 시뮬: 가시갈기 전승, 수호자·먹는 자는 제자리 봇만 패배 | 지역 ×1은 **D33으로 결정됨**(늑대). 보스 세트는 **새 결정 필요** |
| Q3 (C9) | 관통창 근접 약화(45% 안쪽 ×0.5)·주기 0.85(test03) vs 현재값(0.7·약화 없음) | test03 적용 | HTML 기본 밸런스 세트 | 시작 기술 비교에서 창 0승 2패(검·칼날 2승) | **새 결정 필요**(D09 창 문제 제기 이후 미결) |
| Q4 (C11) | 비용 2 장소(습지·심층)의 저녁 변주는 도달 불가(HTML F2). 오후로 옮기나, 저녁 출발을 허용하나? | 오후(3)로 이동, 굴은 그대로 | 콘텐츠 도달 가능성. 시간 규칙(칸 부족 시 출발 불가)은 사용자 합의라 바꾸지 않음 | 습지 "저녁 포자"·심층 "저녁 심연"이 오후에 등장(금화 ×1.3/×1.4 유지) | **새 결정 필요**(작은 항목) |
| Q5 (C2/C3) | 늑대 우두머리·보스 소환 늑대에 Godot 물기·돌진 재사용·동시 돌진 집계를 적용하나? | 적용(우두머리: HTML 체력 120·피해 18·2연속 돌진 유지 + 물기, 보스 소환 늑대: Godot 늑대 규칙 + 보스전 겹침 1) | D35 늑대 규칙이 우두머리에도 같아야 "가까우면 물기" 리듬이 유지됨 | 우두머리 물기 사거리 52·피해 18, 동시 돌진 2에 포함 | D35는 늑대에 대한 결정 → 우두머리·소환 확장은 **새 결정 필요** |

### 12-7. 밀도 세트 첫 비교 (봇, 회차 시뮬 시드 1·2 × 전략 7종) — 사람 체감 아님
사용자 Q1 답변(2026-09-07)에 따라 `roles` 세트(근접 ×5·원거리 ×2·지원/봉쇄 ×1~2·정예 ×1, 동시 상한 동일)를 추가하고 같은 봇·시드로 돌렸다. `docs/sim/RUN_SIM.md`(uniform_x5) vs `docs/sim/RUN_SIM_ROLES.md`(roles). 경험치 예산은 종류별로 보존되므로 레벨은 거의 같고, 개체 수가 준 만큼 전투 시간이 줄었다.
| 전략 | 전투분 uniform → roles | 패배 | 레벨 | 합계분(메뉴 가정 포함) |
|---|---|---|---|---|
| 쉬운 지역 반복 | 7.4 → 5.9 | 1.5 → 1.0 | 16.0 → 16.5 | 20.1 → 18.8 |
| 점차 위험 지역으로 | 5.9 → 4.8 | 1.5 → 1.0 | 13.0 → 13.5 | 18.5 → 16.7 |
| 위험 지역 우선 | 12.3 → 7.8 | 0.5 → 0.0 | 19.5 → 19.5 | 25.4 → 21.9 |
| 체력 낮으면 일찍 휴식 | 5.9 → 5.1 | 1.5 → 1.0 | 13.0 → 14.0 | 18.1 → 17.5 |
| 더 깊이 탐험 적극 | 8.6 → 6.5 | 1.5 → 1.5 | 19.5 → 19.5 | 22.4 → 19.9 |
| 빌드 맞춤 보상 선택 | 7.3 → 5.7 | 1.5 → 1.0 | 16.5 → 17.5 | 20.0 → 18.3 |
- 위협·반복감은 봇 수치로 판단하지 않는다(D33 원칙). 사람 플레이 비교가 다음 과제. 잔류 투사체·거미줄·서리 장판·포자 구름의 겹침(동시 상한이 제한하지 않는 것)은 아직 측정하지 않았다(관찰 항목, `FORMATION_TABLE.md` 머리말).
- 첫날 새벽 늑대 25마리(D33)는 두 세트에서 동일(늑대 ×5).

### 12-8. 최종 커밋·빌드·해시 (Codex 독립 검수 기준)
| 항목 | 값 |
|---|---|
| **최종 코드 커밋** | **7f36cd9** (브랜치 `claude/prophecy-action-prototype-hehbeo`, 로컬. push 안 함). 이 뒤의 커밋은 문서·ZIP·해시 기록만 |
| Windows 빌드 | `prophecy_godot_build/prophecy_godot_windows_godot-0.4.0_7f36cd9.zip` (안: `prophecy_godot/prophecy_godot.exe` 109,889,552 B + `실행_안내.txt`). exe SHA-256 `ec5325807381511b2c7c8680cd09a662e205a8223467834655400b8ee6258f9e`, ZIP SHA-256 `ea38807ae9419c2d456b6629c97c35eea9ae132a21d889a914e7f25c876470e2` |
| 프로젝트 ZIP | `prophecy_godot_build/prophecy_godot_project_godot-0.4.0_7f36cd9.zip` = `git archive HEAD prophecy_godot` (203 파일). SHA-256 `bec571a17b4abc918e6996f75ce21eb71bfd5c28b39516c30877d02cbe07fe78` |
| 빌드 명령 | `godot --headless --path prophecy_godot --export-release "Windows Desktop" prophecy_godot_build/windows/prophecy_godot.exe` (프리셋 `export_presets.cfg`, 템플릿 4.7.2.stable 공식, PCK 내장, 서명 없음) |
| 빌드 실행 확인 | 같은 PC에서 `PROPHECY_UI_SMOKE`(새 회차→…→관문→저장→계속하기→검증 메뉴 빠른 전투) **종료 코드 0, 스크립트 오류 0, PNG 25장**. `PROPHECY_CAPTURE` 기준 전투도 0 |
| 종료 시 접근 위반(수정됨) | 7f36cd9 이전 빌드(f906b6d·09b3123 코드)는 같은 자동 진행 뒤 종료에서 3/3회 접근 위반(bash 종료 코드 139), `--audio-driver Dummy`에서는 0/1회, `--verbose`에서는 0/1회(경쟁 조건). 원인 = AudioStreamGenerator 재생 중 AudioServer 정리. `PAudio._exit_tree`에서 재생 중지·playback 해제 뒤 2/2회 정상 종료. 편집기 실행(`--path`)에서는 재현되지 않았다 |
| 최종 headless 검증(7f36cd9) | run_tests 72/72 · port_tests 69/69 · boss_tests 34/34 · run_layer_tests 54/54 · 밀도 보고서 36행 결과 열 동일(µs/단계 열만 다름) · HTML 대조 14개 0.3.1 기록과 동일(`dodge_cd_after` 0.6333, `hit_damage_normal` 12 포함) |
| 미커밋으로 남긴 것(의도) | 루트 `index.html`·`CNAME`·`wash.jpg` 삭제(Codex 정리, 홈페이지 파일 — 복원하지 않았고 커밋도 하지 않음), `project.godot`의 편집기 기본값 줄(`window/stretch/aspect`) 제거, `icon.svg.import` 편집기 재작성 |
| 재현 순서(Codex) | ① 7f36cd9(또는 프로젝트 ZIP) 체크아웃 ② Godot 4.7.2 콘솔 실행 파일로 `--headless --path prophecy_godot --import` ③ §12-1 테스트 4종·`tools/density_report.gd`(결과 열을 `docs/DENSITY_REPORT.md`와 비교, µs 열 제외)·`tools/compare_scenario.gd` ④ `PROPHECY_SIM_SEEDS=1,2 -s tools/run_sim.gd`(약 4~5분, `docs/sim/RUN_SIM.md`와 비교; 같은 OS에서만 완전 재현) ⑤ 창: `PROPHECY_UI_SMOKE=<폴더> --path prophecy_godot`(약 5분) ⑥ 빌드 ZIP 해시 대조 |

## 13. Codex 독립 검수(ca027fc) 오류 수정 (godot-0.4.1, 2026-09-07)
검수 문서: `C:\Users\Public\Documents\ESTsoft\CreatorTemp\godot-audit-ca027fc-20260907\AUDIT_REPORT.md`(F1~F6, 프로브 `audit_probes.gd`), `EXE_CHECK.md`. 검수자는 기존 229 테스트·기준 전투 36행·회차 시뮬 14회·배포 해시를 독립 재현했고, 아래 6건을 별도 프로브로 재현했다. 순서: 현재 트리에서 같은 프로브로 **재현 확인** → 수정 → 명세에서 출발한 회귀 테스트 → 프로브 재실행. 재미 조정용 수치(체력·공격력·회피·경험치)는 바꾸지 않았다.

| 번호 | 재현(수정 전, 이 트리) | 원인·수정 | 회귀 검증 |
|---|---|---|---|
| F1 심층 전투 시작 저장이 이전 보상 화면으로 복구 | `deep_resume`: saved_pending=true, screen=after, 전리품 27 회수 | `deep_explore()`가 `pendingSortie`가 남은 상태로 저장한 뒤 전투를 만들었다(`make_encounter`의 null 처리가 저장보다 늦음). **모든 전투 시작 경로(`start_encounter`: 출격·심층·사건 추가 전투·보스)에서 전투 생성 직후 체크포인트 저장** → 디스크에는 항상 pendingSortie=null. 계약(GAME_SPEC §전투 도중 종료): 시간 지불·이미 고른 성장 유지·미정산 전리품 상실·거점 복구 | 새 `tests/ui_flow_tests.gd`(실제 main.tscn, 상태 주입으로 승리 생성·입력 합성 없음): 출격 체크포인트, 심층 중 종료→거점·금화 불변·시간 3칸, 전투 중 3택 뒤 자동 저장·복구, 사건 추가 전투 중 종료, 보스전 중 종료→관문 준비·재도전 0. 프로브: screen=base, restored_loot_gold=0 |
| F2 수호 결계 HUD 60 | hud "보호막 60"(실제 30) | HUD가 `shield + ward_shield`를 더했다(ward_shield는 shield의 구성분). `shield`만 표시 | ui_flow_tests: 결계 30·부분 흡수 18·갑옷 15+결계 30=45·만료 뒤 15 모두 HUD와 실제 일치 |
| F3 철벽 방패 문턱이 강인함 적용 후 | taken 18.0, procs {} | 자격 판정을 강인함 적용 전 명목 피해로(`nominal >= hp_max×0.2`), 차감 계산 순서는 그대로 | port_tests: 20→13.5(발동 1), 19.9→17.9(미발동), 단독 정확히 20→15, 장판은 둘 다 제외. 기존 25→18.8 유지 |
| F4 지속 피해 DPS 분모가 전투 전체 시간 | 쌍검 출혈 active 20·dps 5 | `classify("dot:*@src")`의 보유 시간 키를 원천으로 연결(자동기술→weapon:id, E→skill:id, Q→skill:q, 공용→common:id). 공용 증강·희귀 보상도 `active_t` 기록. 정책: 분모 = 원천 보유 실제 전투 시간(획득~제거), 제거 뒤 잔류 지속 피해도 같은 분모(분모를 늘리지 않음), 획득 전 시간 미포함. `PStats.by_owner()`로 직접+파생 묶음 제공. activeT 없는 옛 기록은 전투 시간 전체 | run_layer_tests: 출혈 dps 20(=직접), 불씨 화상 4, 얼음 파편 1.25, 묶음 쌍검 200/5초=40, 옛 기록 20초, 전투 중 common/reward 보유 시간 1초 기록 |
| F5 톱날 출혈이 씨앗 후보에서 제외 | has_dot_source=false | 개조 ID(`bleed`) 대신 카탈로그 태그(`mods[].tags` bleed)로 판정하는 `has_bleed_source`·`status_sources`로 공통화. 희귀 보상 설명·상점 잔불검 호환 문구가 같은 함수 사용 | port_tests: 톱날→출혈 공급원·씨앗 후보, 검만→없음, 쌍검 출혈+얼음 파편→냉기·출혈. 프로브 true/true |
| F6 승리 정산 2회 호출 시 중복 | 2회째 gold 64·xp 6·wins 2 | `CombatState.settled` 가드 + 자격 검사(승리 정산은 status=won, 패배 정산은 lost/timeout, 보스 동일). 실패 시 `{}` 반환·push_error·상태 불변 | run_layer_tests: 2회째 {} 반환·전리품/경험치/승리/조우 불변·통계 1건, 승리 전투를 패배 정산에 넘겨도 무시, 패배 전투는 승리 정산 거부, 패배 정산 2회째 무시 |

- 검증(이 PC, APPDATA를 별도 폴더로 격리): run_tests 72/72 · port_tests 76/76(+7) · boss_tests 34/34 · run_layer_tests 62/62(+8) · ui_flow_tests 14/14(신설) · 밀도 보고서 36행 결과 열 동일 · Codex 프로브 6항목 모두 기대값. 회차 봇 전체 시뮬은 최종 통합 시점에 다시 비교한다(지시문 §7).
- 검수 로그의 `Failed to read the root certificate store`는 엔진 환경 메시지(게임 스크립트 오류 아님). headless 종료 시 ObjectDB 누수 경고는 테스트 스크립트가 main 씬을 제거하는 경로에서 남는 것으로, 종료 코드는 0이며 장시간 누적 영향은 미측정.
- 실제 사람 키보드·마우스 플레이는 여전히 없음.

## 15. UI·모바일 준비 (2026-09-07, 지시문 §6)
사용자 방향(합의): 마을 홈 구성(클릭 가능한 마을 배경 + 당장 고를 출격 2곳 + 날짜/5칸/관문 정보 + 간결한 현재 빌드), 시설까지 걸어가지 않음, 도트 배경 대량 제작 없음, 설명을 모두 펼치지 않음(핵심 한 줄 + 용어 툴팁/고정), PC 마우스와 모바일 터치 열기/닫기 함께, PC/모바일 규칙·데이터 공유, 장치 무관 행동 입력, 가로 안전 영역·큰 터치 대상·비율별 배치, 왼손 이동 + 오른손 유지 회피·Q·E 동시 입력 확장 지점, hover만으로 닿는 상세를 필수 경로로 쓰지 않음. **범위는 공통 구조 + 입력·UI 준비까지이며 실제 Android/iOS 빌드·실기 성능은 미검증이다(이 절은 '모바일 실행 확인'을 주장하지 않는다).**

### 15-1. 준비한 것 (구현자 선택은 "구현자"로 표시)
| 항목 | 파일 | 내용 |
|---|---|---|
| 장치 무관 행동 입력 | `scripts/game/ui/input_router.gd` (PInputRouter), `combat_view.gd` | 키보드·게임패드 InputMap + 가상 터치 상태 → PStepDriver가 이미 쓰는 형식(mx·my·dodge_press·dodge_held·special·skill_e). 누름은 이벤트 순간 `driver.note_*_press()`로 기록해 다음 단계에서 1번 소비(기존 계약), 유지·이동은 프레임 시작 `poll()`. 가상 상태가 비어 있으면 0.4.3 인라인 코드와 같은 값(-1/0/1 합). 구현자: 이동 벡터 크기는 CombatState가 정규화하므로 스틱 기울기는 방향만 반영(속도 조절 없음) |
| 게임패드 매핑(덤) | `project.godot` [input] | 왼쪽 스틱(축 0/1)·십자키(11~14) 이동, A(0)·B(1) 회피, X(2) Q, Y(3) E, Start(6) 일시정지. 실제 패드로는 확인하지 않음 |
| 터치 오버레이 | `scripts/game/ui/touch_controls.gd` (PTouchControls) | 가로 화면: 왼쪽 45% 끌기 영역의 가상 스틱(누른 자리 중심, 반지름 64, 데드존 0.2 뒤 0..1 재매핑) + 오른쪽 회피(지름 96, 누르는 동안 유지)·Q·E(지름 76). 터치 index마다 잡은 조작을 기억 → 스틱 이동이 잡고 있는 회피를 풀지 않음. 재사용 채움 = HUD와 같은 식. 켜지는 조건: `DisplayServer.is_touchscreen_available()` 또는 `PROPHECY_TOUCH=1`(PC 시험: 마우스 왼쪽을 터치 1개로). 봇·정지·비전투에서는 받지 않음. 구현자: `emulate_touch_from_mouse` 프로젝트 설정 대신 오버레이 안에서 마우스를 취급(전역 입력 동작 불변) |
| 안전 영역·비율 배치 | `scripts/game/ui/layout.gd` (PLayout), `screen_base.gd`, `main.gd _layout_hud`, `choice_overlay.gd`, `glossary_tip.gd` | `project.godot`: stretch canvas_items · aspect **expand**(창이 넓거나 높으면 canvas가 늘어남, 960×640보다 작아지지 않음) · handheld orientation landscape. `safe_rect()` = DisplayServer 안전 영역(화면 px) → 창 위치·stretch 변환으로 canvas 좌표(순수 계산 `map_safe`는 headless 시험). 비율 묶음 wide ≥ 2.0 / standard / narrow < 1.5 → 열 비율(0.6/0.57/0.55)·마을 높이(200/180/220). 화면 여백 = 14·10 + 안전 영역 밖, HUD 왼쪽 묶음은 안전 영역 시작·목적/설정 줄은 안전 영역 끝·경기장은 HUD 아래 가운데(960×640에서는 0.4.3과 같은 좌표), 3택 패널·툴팁도 안전 영역 안. 터치면 버튼 최소 높이 44, 주 버튼 56 |
| 거점 마을 홈 | `screens/base.gd`, `scripts/game/ui/village_map.gd` (PVillageMap) | 왼쪽: 벡터 도형 마을(대장간·상점·장비·통계·기록·휴식 건물, 각 ≥72px 투명 Button + `_draw` 실루엣, 걷기 없음) + 오늘의 출격 2장(주 버튼 큰 크기, 상세는 접힘). 오른쪽: 현재 빌드 한 줄씩(자동기술 3 슬롯·Q/E·장비 3·요약 수치) + "상세" 토글(기존 장비·성장·통계·기록 패널) + 다가오는 보스 + 오늘(미처리 레벨업·하루 종료 확인 창·저장 후 종료·기록). 상단 줄(PUi.header: 날짜·시간대 5칸·관문·체력·금화·세계 변화)과 회차 특징 줄 유지. 휴식은 건물 버튼(라벨 "휴식 → 다음 시간대", PRun.can_rest로 비활성). 최종 준비(boss_prep)·하루 종료 확인·`_open_endday`·`start_sortie_card` 경로 그대로 → `PROPHECY_UI_SMOKE` 자동 진행 유지. 구현자: 건물 배치·모양·"통계·기록" 건물이 통계 화면을 열고 기록은 오늘 카드의 버튼인 점은 임시안 |
| 툴팁 터치 경로 | `glossary_tip.gd` | 고정된 용어를 다시 클릭/탭 → 그 툴팁(과 뒤에 연 것) 닫힘, 바깥 탭(InputEventScreenTouch도) → 모두 닫힘, 터치면 × 버튼 36px·안내 문구. hover 감사: `screens/*.gd`·`ui/*.gd`·`render.gd`에 hover 전용 처리는 툴팁 층뿐이며 그것도 클릭 고정 경로가 있음(hover 필수 경로 없음) |
| 시험·도구 | `tests/input_tests.gd`(60), `tools/layout_shots.gd` | 아래 15-2 |

### 15-2. 검증 (이 PC, Windows, APPDATA 격리, 사람 입력 없음)
- headless: run_tests 72/72 · port_tests 76/76 · boss_tests 34/34 · run_layer_tests 64/64 · ui_flow_tests 14/14 · world_tests 30/30 · content_tests 28/28 · **input_tests 60/60(신설)** — 모두 종료 0, 스크립트 오류 0. `tools/density_report.gd` 36행 결과 열 동일(µs 열만 다름, 파일은 되돌림).
- input_tests 내용: A 키보드 경로 = 0.4.3 인라인 코드와 같은 값(대기·대각·좌우 상쇄·해제) · B 누름 1회 소비(한 프레임 5단계에 회피 1회, echo 무시, 실제 Space 키 InputMap, Q·E) · C 스틱 벡터(데드존·끝·밖 자르기·재매핑 0.5·대각 정규화) · D 라우터 합성(키보드+가상, reset) · E 터치 오버레이 21항목(영역·버튼 크기·비겹침·스틱 잡기·끌기·터치 1 회피 유지 중 터치 0 스틱 이동에도 유지·프레임 뒤 1회 소비·뗌·E/Q 탭·스틱 1개·빈 곳·정지 중 무시·정지 시 해제·재사용 채움) · F 배치(비율 묶음 5, 안전 영역 매핑 노치 80px·없음·전체·비정상 방어) · G 실제 main.tscn 거점 마을(건물 5 ≥72px, 휴식 라벨/활성, 건물→상점/대장간/통계/장비 화면, 휴식→시간 1칸, 상세 토글, 하루 종료 확인 창·Esc).
- 창(사람 경로 회귀): `PROPHECY_DODGE_DEMO` **전/후 동일** `DEMO_RESULT dists [70.0, 86.5, 150.0, 150.0], dodges 4, x 656.5, cd_left 0`(종료 0), `PROPHECY_TOUCH=1`을 켠 채로도 동일. `PROPHECY_CAPTURE` 전/후 CAPTURE_SUMMARY 한 줄 완전 동일(PAUSE_CHECK 5개 true, 종료 0, PNG 7). `PROPHECY_UI_SMOKE`(비전체, 속도 5) "UI_SMOKE done" 종료 0·스크립트 오류 0·PNG 25(거점 마을·툴팁·상점·대장간·장비·통계·하루 종료 확인·관문 준비·계속하기 포함).
- 창 크기별(`tools/layout_shots.gd`, `PROPHECY_TOUCH=1`): 960×640(canvas 960×640 standard) · 1280×720(1137×640 standard) · 2340×1080(1386×640 wide, 실제 창 크기 확인) · 1170×540(같은 비율 wide) · 1024×768(960×720 narrow). 각각 제목·거점·거점 상세·툴팁·상점·장비·3택·하루 종료 확인·전투(터치 오버레이 표시)·일시정지 캡처, LAYOUT_CHECK(본문·상단 줄 가로 넘침 없음, HUD 목적 줄·설정 줄·막대·경기장 위치) 모두 ok, fails=0. 캡처는 이 PC의 임시 폴더에만 두었다(커밋하지 않음).
- 확인한 pre-existing 현상(이번 변경과 무관, 0.4.0 캡처 `docs/captures/0.4.0_run_bot/20_tooltip.png`와 동일): 마우스 없이 `tips._on_click()`으로 고정한 툴팁 패널 테두리가 화면 아래까지 늘어남(내용은 정상).

### 15-3. 하지 않은 것 · 미검증
- **실제 Android/iOS 내보내기·실기 실행·멀티터치·노치 안전 영역·성능 전부 미검증.** `DisplayServer.get_display_safe_area()` 매핑은 합성값 시험(F2)뿐. 실제 게임패드 미확인.
- 사람 키보드·마우스·터치 플레이 없음(모든 창 검증은 스크립트가 화면 함수를 부른 것, §12-4와 같은 구분).
- 터치 오버레이의 마우스 취급은 손가락 1개 상당(동시 입력은 headless 합성 시험 E7~E11로만 확인).
- 스틱 기울기 크기 → 속도 조절, 오버레이 위치·크기 사용자 설정, 세로 화면, 거점 건물 그림의 최종 모양은 다루지 않았다.
