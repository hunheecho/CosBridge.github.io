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

## 14. 세계 변화·반복 콘텐츠 (godot-0.4.2~0.4.3, 2026-09-07)
지시문(`godot-audit-ca027fc-20260907/NEXT_CLAUDE_INSTRUCTIONS.md`) §3·§4 구현. 방향은 사용자 합의(D38·D40), 배율·비율·내용은 시험값(Codex 제안 또는 구현자). 규칙 정본: 세계 변화 = `world.json` world_stages + `RULES.md` 변경 이력, 반복 콘텐츠 = `world.json` world_features/formation_sets/boss_gates + `missions.json` events.challenge. 표: `FORMATION_TABLE.md`(등급 열), `docs/sim/STAGE_COMPARE.md`.

### 14-1. 검증 결과(헤드리스, 봇 — 사람 난이도 승인 아님)
| 항목 | 결과 |
|---|---|
| `tests/world_tests.gd` 31 · `tests/content_tests.gd` 28 | 통과. 기존 스위트 72/76/34/64/14 통과, 밀도 보고서 36행 결과 열 동일(기준 전투 보존) |
| 단계 × 밀도 세트 비교(`tools/stage_compare.gd`, 실험실 프리셋 고정, 시드 1·2·3, balanced) | 32행 중 승률 3/3이 31행, 변화 전 심층 6일차(uniform_x5)만 2/3. 1차·2차에서 받은 피해가 변화 전보다 **줄어든** 행이 많다(프리셋이 단계에 맞춰 강해지고 붉은/변이 배율 ×1.25/×1.60이 그보다 작기 때문). 등급이 준비를 요구하는지는 사람 플레이로 판단해야 한다 |
| 잔류 투사체·장판·거미줄 최대 동시 수(사용자 관찰 항목) | 투사체 최대 4(심층), 장판 최대 10~11(심층 6일차: 포자 구름·서리 장판), 거미줄 최대 4(능선). 동시 생존 상한 12와 별개로 장판이 10개까지 겹칠 수 있음 → 후반 심층의 장판 겹침은 사람 가독성 검증 항목 |
| 2단계 위험 임무 정예 +1 | 임무 편성은 `PObjectives.setup`이 만들므로 그 경로에 적용(정예 추적 + 위험 조건 → 정예 2). 봇 3/3 승, 피해 0~6.4 |
| 3일차 성장 중단 빌드(`docs/sim/RUN_SIM_STOP3.md`, 시드 1·2) | 7전략 모두 완주(레벨 5~9, 보스 2.3~4.7분). 성장 없이도 봇이 완주 → 보스·후반 편성이 봇에게는 느슨함. 사람 비교 필요 |
| 실제 창 전체 회차 자동 진행(0.4.3, 격리 프로필) | 새 회차→…→관문 3→7일차 완주→새 회차, 종료 0, 스크립트 오류 0, PNG 26장. 세계 변화 표식·회차 특징 줄·편성 이름 표시 확인(캡처) |

### 14-2. 시드 재현성에 대한 주의
- 사건 추첨: 회차 특징이 없는 회차는 0.4.2와 같은 균등 추첨·같은 rng 소비. 특징 '안개 낀 계절'만 가중 추첨(rng.next 1회 추가).
- 카드 생성: 대안 편성이 있는 카드(2일차 이후 대부분)는 정수 1개를 더 소비하므로 같은 시드라도 0.4.2와 임무·위험 추첨이 달라질 수 있다. 1일차 카드는 동일(첫 전투 보존).
- 관문 승리 로그·세계 변화 기록은 `bossRecords`에 1회.

### 14-3. 다음 결정 대기(사용자)
- Codex 문서 `prophecy-act-themes-plan-20260907.md`(2026-09-07 18:56)는 "본편 7일 → 10일, 관문 3/5/7 → 4/7/10, 3막 × 테마 3 = 9테마/9보스/27경로, 무한 모드·정복자 성장"을 사용자 합의로 기술하고 기존 지시문의 일정 부분을 대체한다고 적었다. 이 세션의 채팅 지시는 기존 지시문 순서였으므로 **이 문서의 일정 변경은 아직 구현하지 않았다**(세계 변화는 관문 완료에서 도출되고 보스 계획 구조가 있어 10일 일정으로 옮길 때 재사용 가능). 사용자 확인 뒤 별도 단계로 진행한다.
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

## 16. 통합·배포 (godot-0.5.0, 2026-09-07, Windows 로컬)
0.4.1(검수 수정) → 0.4.2(세계 변화) → 0.4.3(반복 콘텐츠·밀도 비교 회차) → 병합: 영구 성장·해금·제작(별도 worktree, 1c8933a) + UI·모바일 준비(48fd1f7) → 0.5.0. 변경 단위는 커밋으로 분리돼 있다(§16-3).

### 16-1. 최종 검증 (이 PC, APPDATA 격리, 봇·스크립트 — 사람 입력 없음)
| 스위트 | 결과 |
|---|---|
| run_tests(기준 전투) 72 · port_tests 76 · boss_tests 34 · run_layer_tests 64 · ui_flow_tests 14 · world_tests 31 · content_tests 28 · meta_tests 78 · meta_ui_tests 11 · input_tests 60 | **468/468 통과**, 종료 코드 0 |
| 기준 전투 보존 | `tools/density_report.gd` 36행 결과 열 동일(µs 열 제외), `tools/compare_scenario.gd` 14개 동일(dodge_cd_after 0.6333·hit_damage_normal 12) |
| 실제 창 전체 회차 자동 진행(`PROPHECY_UI_SMOKE` + FULL, 시드 1, 봇 balanced, 시험 프로필) | 새 회차→마을 홈→…→관문 3(붉은 달·상위 변이)→7일차 완주→새 회차, 종료 0, 스크립트 오류 0, PNG 26장 |
| 봇 시뮬 재생성(`docs/sim/`) | RUN_SIM(uniform_x5)·RUN_SIM_ROLES·RUN_SIM_STOP3·BOSS_SIM·START_COMPARE·STAGE_COMPARE — 3택 유형 정규화(D39)·카드 편성 대안(D40) 때문에 0.4.0 표와 값이 다르다(예상된 차이, 시드 재현성은 유지) |
| 경고 | headless 종료 시 ObjectDB 누수 경고(테스트 스크립트의 main 씬 제거 경로), 엔진의 `Failed to read the root certificate store` 환경 메시지 — 게임 스크립트 오류 아님 |

### 16-2. 신규 시험 수치(사용자 승인 아님) 한눈에
| 영역 | 수치 | 출처 |
|---|---|---|
| 세계 변화(D38) | 붉은 ×1.25/×1.10, 변이 ×1.60/×1.20, 60:40, 2단계 위험 임무 정예 +1 | Codex 제안 |
| 반복 콘텐츠(D40) | 특징 3종 값, 편성 대안 24개, 강적의 흔적(정예 +2·×1.6·체력 50%), 보스 후보 1개씩 | 구현자 |
| 영구 성장(D39) | Lv15·기록 140, 특성 12(수치), 장비 6·제작법 6·수수료 60/80, 해금 일정, 3택 유형 정규화 | Codex 초안 + 구현자 |
| UI·모바일(§15) | 스틱 데드존 0.2, 버튼 Ø96/Ø76, 안전 영역 버킷 | 구현자 |

### 16-3. 커밋 (모두 로컬, push 안 함)
| 커밋 | 내용 |
|---|---|
| 88529c1 | godot-0.4.1 Codex 검수 F1~F6 수정 + 회귀 테스트 |
| dc7052f | godot-0.4.2 세계 변화 두 단계(D38) |
| 561be59 · f609fb3 · c08a92a | godot-0.4.3 밀도 비교 회차·반복 콘텐츠(D40), 위험 임무 정예 경로, 단계 비교 도구·보고서 |
| 1c8933a → 6a01988 | 영구 성장·해금·제작 시험 프로필(D39) 병합 |
| 48fd1f7 → df57b13 | UI·모바일 준비(§15) 병합 |
| (아래) | 0.5.0 통합: 버전·문서·시뮬 재생성 / 빌드 ZIP·해시 |

### 16-4. 사람이 먼저 플레이할 경로(추천 3~5)
1. **기준 전투** — 제목 > 검증 메뉴 > 기준 전투(사람): 0.3.1 D33 그대로인지(느낌 변화가 없어야 함).
2. **첫 관문까지 새 회차(검, 밀도 uniform_x5, 프로필 legacy)** — 1~3일차 전투 시간·카드 편성 이름(포위/원거리 호위)·강적의 흔적 거절/수락 → 가시갈기.
3. **같은 시드로 밀도 roles** — 검증 메뉴 > 밀도 비교 회차 > roles: 2·3일차 전투 시간·위협·반복감을 2와 비교(첫날 새벽은 동일).
4. **관문 뒤 붉은 달·상위 변이** — 3일차 관문 승리 뒤 2~4일차 재방문(붉은 표식·피해 체감), 5일차 관문 뒤 옛 지역 재방문(일반 퇴장). 후반 심층의 장판 겹침 가독성.
5. **영구 성장 trial 프로필로 새 회차** — 제목 > 영구 성장 > trial: 시작 3종·해금 카드 폭·특성 1행, 대장간 제작(재료 도달 가능성).
(터치: PC에서 `PROPHECY_TOUCH=1`로 오버레이 확인 가능. Android/iOS 실기는 미검증.)

### 16-5. 최종 커밋·빌드·해시 (Codex 독립 검수 기준)
| 항목 | 값 |
|---|---|
| **최종 코드 커밋** | **d5cb11c** (브랜치 `claude/prophecy-action-prototype-hehbeo`, 로컬, push 안 함). 이 뒤의 커밋은 ZIP·해시 기록만 |
| Windows 빌드 | `prophecy_godot_build/prophecy_godot_windows_godot-0.5.0_d5cb11c.zip` (안: `prophecy_godot/prophecy_godot.exe` 110,014,800 B + `실행_안내.txt`). exe SHA-256 `a53389c9762b51c7c6a125fb860cb81a7e6db328f942980eac0c5ba96982591b`, ZIP SHA-256 `4d5167eb685061e136d5423a8b901e006c86e747483904feb8c565bcd58e4eef` |
| 프로젝트 ZIP | `prophecy_godot_build/prophecy_godot_project_godot-0.5.0_d5cb11c.zip` = `git archive HEAD prophecy_godot` (233 파일). SHA-256 `c40cb23ff9502085abcc3047489d4ad03273ef0e212647e62647bd94aa42c9fc` |
| 빌드 실행 확인 | 같은 PC, APPDATA 격리, 패키지 exe로 `PROPHECY_UI_SMOKE`(새 회차→…→관문→저장→계속하기→검증 메뉴 빠른 전투): **종료 코드 0, 스크립트 오류 0, PNG 25장**. 실제 사람 플레이 없음 |
| 미커밋(의도) | 루트 `index.html`·`CNAME`·`wash.jpg` 삭제(Codex 정리, 복원·커밋 모두 안 함), `icon.svg.import` 편집기 재작성. `project.godot`의 stretch aspect는 UI 준비에서 `expand`로 바뀌어 커밋됨 |
| 재현 순서(Codex) | ① d5cb11c(또는 프로젝트 ZIP) 체크아웃 ② `--headless --path prophecy_godot --import` ③ §16-1의 10개 스위트(`tests/*.gd`, APPDATA 격리) + `tools/density_report.gd`(결과 열 비교) + `tools/compare_scenario.gd` ④ `PROPHECY_SIM_SEEDS=1,2 tools/run_sim.gd` 등 `docs/sim/*.md`와 대조(같은 OS에서만 완전 재현) ⑤ 창: `PROPHECY_UI_SMOKE=<폴더> [PROPHECY_UI_FULL=1 PROPHECY_UI_SPEED=5] --path prophecy_godot` ⑥ ZIP 해시 대조. 검수 폴더의 `audit_probes.gd`는 `tests/tmp/`에 복사해 실행하면 6항목 모두 기대값 |

## 17. 실력별 전투 봇·밸런스 측정 기반 첫 납품 (2026-09-07, godot-0.5.0 fabdaa3 위, Windows 로컬)
지시문: 외부 `prophecy-bot-balance-framework-20260907.md`(Codex). 공식 문서 **`docs/BOT_FRAMEWORK.md`**(봇 규칙·관측 경계·프로필 시험값·통계/태그·기록 형식·배치·보정 상태), 첫 비교 `docs/sim/BOT_COMPARE.md`(run `compare1`), 처리량 `docs/sim/bot_runs/throughput1/meta.json`. 게임 수치·기존 봇 정책(`bot.gd`)·D33 기준 전투는 바꾸지 않았다. **가상 조작 모델·사람 보정 미완료.**

### 17-1. 추가한 것
| 파일 | 내용 |
|---|---|
| `scripts/rules/observe.gd`(PObserve) · `skill_bot.gd`(PSkillBot, PBot 상속) · `hit_recorder.gd`(PHitRecorder) · `replay.gd`(PReplay) · `data/bots.json` | 관측 경계 스냅샷, 프로필 novice/regular/skilled(지시문 §5 값 그대로: 판단 150/100/50ms·인식 350~550/200~350/120~220ms·추적 150/100/50ms·주의 2/4/8·후보 8/8/16·오차 ±15/8/3°·누름 최대/짧음-중간-김), 선택 계측(공격 관측·피격·거절·검산·보호막 분리·태그 9종), 입력 기록/재생(prophecy_replay/1) |
| `combat_state.gd` 훅 4곳 + `recorder` 필드, `note_attack`·`enemies.gd` 늑대 준비 시작의 `attack_n` 카운터 | recorder가 null이면 아무 훅도 실행되지 않는다. 카운터는 관측·계측 전용(규칙·난수 무관) |
| `step_driver.gd` 훅, `main.gd`·`screens/title.gd` | 검증 메뉴 봇 프로필 선택(기존 정책/novice/regular/skilled), '이번 전투 입력 기록' 체크(사람 입력만 `user://recordings/`) |
| `tools/bot_batch.gd` → `bot_batch_core.gd`(PBotBatch) | 시나리오 6종(기준 늑대25·능선 3일차·습지 4일차·보스 3) × 프로필 × seed, results.jsonl 증분·meta 캐시 키·재개·예산·처리량·보고서(Wilson CI·seed 짝·태그·지연·DPS) |
| `tests/bot_tests.gd` 22 | 지시문 §12 1~10(10은 main.tscn 함수 호출, 사람 입력·합성 이벤트 없음) |
| 문서 | `docs/BOT_FRAMEWORK.md`, `README.md`·`docs/PROJECT_CONTEXT.md`·`HANDOFF.md` 연결, `docs/CONTENT_MATRIX.md` L절 5행(bot:observe·bot:skill·stats:hits·bot:replay·bot:batch) |

### 17-2. 검증 (이 PC, APPDATA 격리, 봇·스크립트 — 사람 입력 없음)
| 항목 | 결과 |
|---|---|
| `tests/bot_tests.gd` | **22/22**, 종료 0 |
| 기존 스위트 | run_tests 72 · port_tests 76 · boss_tests 34 · run_layer_tests 64 · world_tests 31 · content_tests 28 · meta_tests 78 · ui_flow_tests 14 · meta_ui_tests 11 · input_tests 60 = **468/468**, 종료 0 |
| 기준 전투 보존 | `tools/density_report.gd` 재생성 42행(36 + 평균 6) 결과 열 동일(µs 열 제외, 커밋된 보고서 그대로 둠) |
| 처리량(§10 레벨 2, regular) | 기준 전투 10 + 가시갈기 5 = 15전투 18.3초, **50 전투/분**, 전투당 평균 기준 1.31초·보스 0.98초, 최장 시뮬 34.9초, 최대 메모리 86.6MB, results.jsonl 30KB. 45전투(기준 평균 기준) 예상 59초 — 실제 능선·습지 전투는 65마리라 전투당 10~17초(§17-3) |
| 첫 비교(§10 레벨 3, run compare1) | 3시나리오 × 3프로필 × 5seed = 45 + 보스 3 × 3 × 3 = 27 + balanced 기준행 24 = **96전투**, 벽시계 약 7.5분(예산 1500초 안), 미구현 0, 검산(HP·보호막) 96/96 통과. 표·태그·지연은 `docs/sim/BOT_COMPARE.md` |
| 재생 | 저장된 재생 파일 표본을 같은 시나리오 초기 상태에 재생해 120단계 해시·결과 일치(같은 PC). 첫 실행에서 `String.num(20)`이 작은 실수를 잘라 1/6 불일치 → `var_to_str`(17유효자리)로 바꾸고 배치를 다시 실행 |
| 스냅샷 비용 | 판단 단계 전체 스냅샷 ≈115µs, 지각용 부분 스냅샷 ≈56µs; 기준 전투 단계당 active 봇 433µs → skilled 봇 572µs → +계측 606µs(같은 PC) |

### 17-3. 관찰(요약, 사람 승률 아님)
- 기준 전투(늑대 25): 세 프로필 5/5 승, 받은 피해 novice 67 → regular 17 → skilled 5, novice 피격 28회 중 24회 `not_perceived`(인식 지연 > 물기 예고 0.35초). balanced 기준행 3/5.
- 능선 3일차·습지 4일차(검 Lv1 고정, 65마리): novice·regular 0/5, skilled 2/5·1/5 + 시간초과 2·3. 생존 시간은 실력 순으로 늘지만 총피해가 적 체력 합에 못 미쳐 승패는 뒤집히지 않는다(무기·성장 축은 별도 표).
- 보스 3종 × 프리셋: 전 프로필 3/3 승(피격은 novice만). 표본 3.
- 설계 결정(구현자): 추적 예고에 대한 공통 반응 문턱(진행률 0.4, 표시 초 0.9) — 첫 실행에서 skilled가 궁수 조준선을 항상 즉시 비켜 정체(stalled)했기 때문. 모든 프로필 동일 규칙, 공개 정보만.

### 17-4. 하지 않은 것·미검증
- 사람 기록 없음(보정 미완료). OS 간 재생 일치 미검증. 무기 비교(§10-4)·9보스·전체 런 확장은 시나리오 목록 추가로 이후 진행. 재생 파일(`bot_runs/*/replays/`)은 Git에 넣지 않았다(같은 run_id·커밋으로 재생성).
- 지시문과 다른 점: attack_id 카운터를 `enemies.gd` 늑대 준비 시작 2곳에도 두었다(늑대는 `note_attack`을 쓰지 않으므로; 규칙·난수 무관, 72/72·밀도 보고서 동일). 관측의 선 예고(궁수·주술사 조준선)는 화면에 폭이 없어 폭 40(PBot과 같은 가정)을 쓴다.

## 18. 10일·3막·테마 9종·신규 보스 6종·무한·정복자 통합 (godot-0.6.0, 2026-09-07, Windows 로컬)
사용자 지시(2026-09-07 채팅, `prophecy-act-themes-plan-20260907.md`·`prophecy-bot-balance-framework-20260907.md`)의 4단계를 순서대로 구현·검증했다. **모든 신규 수치는 시험값이며 사람의 밸런스 승인이 아니다.** 늑대 25마리 기준 전투(D33)는 첫날 사냥 숲 템플릿으로 고정되어 밀도 보고서 결과 열이 동일하다.

### 18-1. 단계와 커밋 (모두 로컬, push 안 함)
| 단계 | 내용 | 커밋 |
|---|---|---|
| 1 | 실력별 전투 봇·관측 경계·계측·입력 기록/재생·배치 실행기 첫 납품(§17, 게임 수치 불변) | 04cfc3e → 병합 ccff702 |
| 2 | 본편 10일·3막·관문 4/7/10(D41): `run_modes.acts`, 막 판정·미리보기·장소 일정·상인 2/5/8·영구 기록 2/3, 옛 7일 저장은 trio로 호환 | b248c71 |
| 3a | 테마 경로 계층 + 기본 3테마(D42): `data/themes.json`(9테마·장소 18·템플릿 36·전장 14), 경로 추첨·고정, 관문 미리보기, 검증 메뉴 경로 지정 | 1d32236 |
| 3b | 신규 관문 보스 6종(`boss3.gd`, `bosses_new.json`, `docs/BOSSES.md`, boss3_tests 111) → 나머지 6테마 자동 편입, 27경로 | f9db235 → 병합 41a2bd6 |
| 4 | 무한 모드·정복자(D43, `endless.gd`, `profile.gd conqueror_*`, `build.gd`), 결과·거점·영구 성장 화면, 봇 `endless_segments` | e879471 |
| 4' | 제작 재료 접근성·기회비용(`tools/craft_economy.gd`), 3일차 성장 중단 vs 정상 × 실력별 봇(`tools/stop3_skill.gd`), 회차 봇 실력 프로필 지원·날짜별 재료 기록, UI 스모크 무한 구간, 문서·보고서 | (이 절의 마지막 커밋) |

### 18-2. 검증 (이 PC, APPDATA 격리, 봇·스크립트 — 사람 입력 없음)
| 스위트 | 결과 |
|---|---|
| run_tests 72 · port_tests 76 · boss_tests 34 · boss3_tests 111 · run_layer_tests 64(옛 일정 env) · ui_flow_tests 14(옛 일정 env) · world_tests 31(옛 일정 env) · content_tests 28(옛 일정 env) · acts_tests 23 · theme_tests 26 · endless_tests 58 · meta_tests 78 · meta_ui_tests 11 · input_tests 60 · bot_tests 22 | **708/708**, 모두 종료 코드 0 (병합 뒤 재실행) |
| 기준 전투 보존 | `tools/density_report.gd` 재생성 42행 결과 열 동일(µs 열 제외, 커밋된 보고서 그대로) |
| 실제 창 전체 회차 자동 진행(`PROPHECY_UI_SMOKE`+`PROPHECY_UI_FULL`, 경로 고정 사냥 숲→붉은 의식터→시간의 심연) | 제목→새 회차→거점→전투→보상→사건→정산→상점/대장간/장비/통계→패배→3택→하루 종료→관문 4(가시갈기)→이어하기→…→10일차 완주(Lv18)→**무한 1구간 전투 1승→마치기→결과**→새 회차. 종료 0, 스크립트 오류 0, PNG 29장(`docs/captures/0.6.0_ui_smoke/` 4장) |
| 시드 1 자동 진행(경로 추첨: 버려진 요새→무너지는 광산) | 7일차 굴착 거수에서 봇이 무한 재도전 → 자동 진행에 재도전 4회 상한(`boss_stuck`) 추가. 사람 판단 항목(18-4) |
| 옛 저장 호환 | trio(7일) 회차 dict는 acts 규칙을 타지 않음(acts_tests·run_layer_tests). 프로필에 `conqueror` 없는 파일은 0 배분으로 정규화(endless_tests) |

### 18-3. 시뮬레이션 관찰 (봇 결과 — 사람 승률·재미·밸런스 승인 아님)
| 보고서 | 요약 |
|---|---|
| `docs/sim/ROUTE_SMOKE.md` 27경로 × 검 × 시드 1(balanced) | **23/27 완주**. 실패 4: 무너지는 광산(굴착 거수) 3경로 — 21초 패배 4회 반복(Lv10, 체력 100, 낙석 3회 = 100), 뒤틀린 성채(종말의 집행관) 1경로 — 45초 패배 4회. 벽시계 1104초. 표 머리말 버전은 s2(코드 동일) |
| `docs/sim/STOP3_SKILL.md` 시드 추첨 경로(신규 보스 포함) × 봇 4 × 정상/3일 중단 | **관측 보완 전(observe-1)**: 정상 성장 완주 balanced 2/3, novice·regular·skilled 0/3 — 실패 전부 신규 보스(파수장 24~28초, 굴착 거수 17~24초, 집행관 21~41초). **관측 보완 후(observe-2, 커밋된 표)**: 정상 성장 novice·regular·skilled **9/9 완주**(Lv14~21, 신규 보스 3종 포함), balanced 2/3(굴착 거수 21초 반복). 3일 중단(Lv2~6) 실력 봇 6/9(실패: 굴착 거수 Lv2 ×2, 핏빛 사냥왕 Lv2 ×1), balanced 1/3. 보스 받은 피해 정상 46~66 → 중단 245~271, 보스 초 186~211 → 391~511. 게임 수치·봇 규칙 변경 없이 관측 범위만 보완했는데 결과가 뒤집혔으므로 **봇 결과는 관측 범위에 강하게 의존**한다 |
| `docs/sim/STOP3_SKILL_BASE.md` 기존 보스 경로 고정 × 봇 4 × 정상/3일 중단 | 정상 12/12 완주, **3일 중단(Lv4~7) 11/12 완주**(novice 시드 1만 수호자 4패). 중단 빌드는 보스전이 2~3배 길고(수호자 99~138초, 먹는 자 126~213초) 보스에게 받은 피해 3~5배(balanced 29→46, novice 75→227, regular 67→204). 일반 전투 받은 피해는 실력 순(정상: novice 526 → regular 373 → skilled 196; 중단: skilled 15). 실력 봇은 일반 전투 시간 초과 3~7회(적을 피하며 처치가 느림) → 전투분 19~33. **후반이 봇에게 느슨하다는 신호이지만 체력·수치를 올리지 않았다(사용자 지시)** |
| `docs/sim/CRAFT_ECONOMY.md`(gradual) · `CRAFT_ECONOMY_DEEP.md`(더 깊이 적극) 경로 9 × 시드 2 | gradual: 17/18 완주(굴착 거수 1패). 종료 시 즉시 제작 가능 — 월광 갑옷 11/18, 연계 방패 9/18, 재생의 여행복 6/18, 잔향의 지팡이 4/18, 반격 방패 2/18(재료는 18/18 충족·재료 장비 2종을 봇이 안 삼), **혈월검 0/18**(송곳니는 정예 처치에서만 — gradual은 위험 임무·더 깊이·강적의 흔적을 안 받아 송곳니 0). 재료만 보면 5종이 평균 1.7~5.2일차(6일차까지 13~18/18)에 모인다. deep(더 깊이 적극): 15/18 완주, 혈월검 5/18 즉시 제작·송곳니 8/18(평균 5.0일차), 나머지 비슷. 실제 비용(수수료+소비 장비 판매가+재료 판매 포기분) 135~190 = 회차 금화 수입(평균 1,200~1,900)의 8~13%. 봇은 제작을 하지 않으므로 "제작 0~2회 관찰"은 사람 항목 |

### 18-4. 사람 판단이 필요한 관찰
- 굴착 거수 낙석: Lv10 검 빌드(체력 100)가 낙석 3회에 죽는다(balanced 봇 21초). boss_sim의 막별 프리셋 빌드로는 2/2 승. 봇 한계(낙석 예고 밖으로 안 나감)인지 난이도인지 사람 플레이로 판단. 수치 변경 없음.
- 성문 파수장: 실력 봇 전원 24~28초 패배(guard 24·bolts 8~20 패턴), balanced는 147초 장기전(guard 38). 방패 자세 판정과 봇의 접근 거리 문제가 겹침.
- 종말의 집행관: 정상 성장(Lv18~22)도 봇 패배 21~45초. 순서 있는 참격선(slash)·guard 패턴.
- 3일차 성장 중단 빌드가 기존 보스 3종을 넘는다(18-3). 10일 구조에서 후반 압력이 부족한지, 봇이 기존 보스에 과적합인지는 사람 비교 필요.
- 무한 모드 계단(적 +10%·보스 +15%/구간)·정복자 경험치(초과 16/레벨)는 시험값. 정복자 0 vs 50 비교 측정은 미수행(도구는 있음: `PRunBot.simulate` opts.profile에 배분 프로필).

### 18-5. 통합 간극·구현자 결정
- 관측 경계(`PObserve`)는 fabdaa3 기준으로 작성되어 신규 보스 6종의 예고 도형(낙석·석궁·참격선·빙판·잔해)을 스냅샷에 담지 않았다 → 실력 봇이 예고 안에 서 있다가 죽는다. 별도 에이전트가 `observe-2`로 보완(163c910 → 병합 661e302): 신규 보스 예고(방패 호·석궁 부채꼴·고리 빈 구간 band·낙석 순번·빙판 harm=slow·잔해·참격선·사냥왕 재조준), `boss.guard` 노출, bot_tests 43(§11 21건 추가), 배치 시나리오 6종(`PROPHECY_BOT_SCENARIOS=boss3`) → `docs/sim/BOT_COMPARE_BOSS3.md` 6보스 × 4봇 × 3시드 = **72/72 승**(27~66초, 받은 피해 novice/regular/skilled: 파수장 30/6/6 · 포자 어미 82/64/68 · 거수 0/9/3 · 추적자 20/0/0 · 사냥왕 6/0/0 · 집행관 7/22/0). 봇 규칙·프로필·게임 수치 변경 없음 → 앞선 17~28초 패배는 관측 간극이 원인. 남은 봇 한계: 포자 어미 고리 빈 구간에 못 들어감, 집행관·파수장 피격은 전부 walking_out, 빙판 위 novice 느림. 실제 회차 경로 재측정은 `STOP3_SKILL.md`(재실행) 참조
- 회차 봇이 실력 프로필(novice/regular/skilled)을 `bot_policy`로 받도록 했다(전투마다 `PSkillBot`, 봇 난수 = 회차 시드×101 + 전투 순번×7). 기존 정책 문자열 경로는 그대로.
- `acts_tests`의 봇 완주 검사는 옛 지역 일정으로 고정(10일 구조 검증 목적). 테마 경로 완주는 `theme_tests`·`route_smoke`.
- 무한 전투에는 탐험 사건·더 깊이·도전 달성이 없다(같은 구간 보상 재수령 금지의 단순한 구현). 구간 보스 승리 기록 0.267/구간(잡몹 없음).
- `run_bot` 날짜별 재료·금화·장비 스냅샷(`matsByDay`) 추가 — 보고서용, 규칙·난수 무관.

### 18-6. 하지 않은 것·미검증
- 사람 키보드·마우스·터치 플레이 없음(모든 창 검증은 봇·스크립트). Android/iOS 실기 없음.
- 정복자 0 vs 50 같은 보스 비교, 무한 구간별 시간당 보상 검사, 테마 전용 사건·애니메이션, BOSS_SIM 재생성(보스 6종 표는 f9db235 시점 0.5.0 라벨).
- 신규 보스 6종에 대한 사람 플레이·난이도 판단, 봇이 진 3종의 원인 분리(18-4).
- OS 간 결정성, 게임명.

### 18-7. 사람이 먼저 플레이할 경로 (추천)
① 검증 메뉴 > 기준 전투(사람): 0.3.1 느낌 유지 확인 ② 새 회차(검, legacy 프로필, 경로 지정 사냥 숲→붉은 의식터→시간의 심연): 1~3일차 → 4일차 가시갈기 → 붉은 달 → 7일차 → 10일차 완주 → "현재 빌드로 계속(무한)" 1구간 ③ 경로 지정 버려진 요새→무너지는 광산→뒤틀린 성채: 성문 파수장(4일차)·굴착 거수(7일차)·종말의 집행관(10일차) — 봇이 진 보스 3종 ④ 포자 정원→얼어붙은 협곡→피의 사냥터: 나머지 신규 보스 3종 ⑤ 영구 성장 trial 프로필로 새 회차: 정복자 카드(Lv15 전엔 잠김 표시)·제작 재료 도달(대장간 제작 1회)

### 18-8. 최종 커밋·빌드·해시 (Codex 독립 검수 기준)
| 항목 | 값 |
|---|---|
| **최종 코드 커밋** | **7d770b3** (브랜치 `claude/prophecy-action-prototype-hehbeo`, 로컬, push 안 함). 이 뒤의 커밋은 ZIP·해시 기록만 |
| 앞선 커밋 | e879471(단계 4) → ccff702(봇 기반 병합 04cfc3e) → 41a2bd6(신규 보스 병합 f9db235) → 661e302(관측 보완 병합 163c910) → 7d770b3(단계 4') |
| Windows 빌드 | `prophecy_godot_build/prophecy_godot_windows_godot-0.6.0_7d770b3.zip` (안: `prophecy_godot/prophecy_godot.exe` 110,249,280 B + `실행_안내.txt`). exe SHA-256 `7de8a882f75a87b6ae5428f33ed44247c11a23872a9c03b0774a4b83b987c883`, ZIP SHA-256 `e6c9102628593b5a2bf77d0165ab650dc40110fa1e8f3fd5e8beee3a618f7d2a` |
| 프로젝트 ZIP | `prophecy_godot_build/prophecy_godot_project_godot-0.6.0_7d770b3.zip` = `git archive HEAD prophecy_godot` (297 파일). SHA-256 `7566f50b25f25d420353f414368f19585c415e94556728bc8350940e72c8cc79` |
| 빌드 실행 확인 | 같은 PC, APPDATA 격리, 패키지 exe로 `PROPHECY_UI_SMOKE`(시드 1 경로 추첨: 새 회차→…→4일차 성문 파수장 승리→저장→계속하기→검증 메뉴 빠른 전투): **종료 코드 0, 스크립트 오류 0, PNG 23장**. 편집기 실행으로는 전체 회차+무한(18-2). 실제 사람 플레이 없음 |
| 미커밋(의도) | 루트 `index.html`·`CNAME`·`wash.jpg` 삭제(Codex 정리, 복원·커밋 모두 안 함), `icon.svg.import` 편집기 재작성, `.claude/`(에이전트 worktree) |
| 재현 순서(Codex) | ① 7d770b3(또는 프로젝트 ZIP) 체크아웃 ② `--headless --path prophecy_godot --import` ③ 18-2의 15개 스위트(APPDATA 격리; run_layer·ui_flow·world·content는 `PROPHECY_LEGACY_PLACES=1`) + `tools/density_report.gd`(결과 열 비교) ④ `PROPHECY_SIM_SEEDS=1 tools/route_smoke.gd`(27경로, 약 18분) · `tools/stop3_skill.gd`(약 15분, `PROPHECY_SIM_ROUTE`로 기존 보스 경로) · `tools/craft_economy.gd`(약 12분, `PROPHECY_SIM_STRAT=deep`) · `PROPHECY_BOT_SCENARIOS=boss3 tools/bot_batch.gd` ⑤ `--export-release "Windows Desktop"` → exe 해시 비교(같은 템플릿·같은 PC에서만 일치 기대) |

## 19. 독립 검수 2(godot-audit-8dfcbd1) 지적 3건 수정 (2026-09-07, Windows 로컬)
검수 보고: `C:\Users\Public\Documents\ESTsoft\CreatorTemp\godot-audit-8dfcbd1-20260907\AUDIT_REPORT.md`(Codex, 기준 7d770b3/8dfcbd1). 게임 밸런스 수치·봇 프로필 값은 바꾸지 않았다. **사람 보정 미완료** 상태 유지.

### 19-1. 재현 → 수정 → 회귀
| 지적 | 재현(현재 트리, 검수 프로브 `audit_probes.gd` 그대로) | 수정 | 수정 뒤 프로브 |
|---|---|---|---|
| 1 다른 장판이 기존 장판의 인식을 상속 | `AUDIT_ZONE with_existing_unrelated_zone=0`(기대 36) | `PSkillBot.perceive`: 상속은 `e<id>#<n>` 공격 인스턴스의 부분에만(`_is_attack_instance`). `zone:`·`proj:`는 각각 새 지연. skillbot-0.2 | 36 = 단독 36 |
| 2 비행 중 투사체 id 변경 | `e5#2:proj0 → e5#3:proj0`, `proj1 → proj0` | 발사 시 `CombatState.stamp_projectile(e, pr)`(궁수 화살·주술사 저주·수호자 충격파·신규 보스 `fire`)로 attack_id·proj_i 고정, `PObserve._shooter_attack`은 찍힌 값만(없으면 처음 본 순간 고정), 피격 기록은 `st.hit_attack_id`(발사 시점 공격). observe-3 | 전부 `e5#2:proj0`(프로브는 같은 dict를 두 번 넘김; 형제 투사체 검사는 bot_tests 12d) |
| 3 캐시 키가 미커밋 코드 변경을 구분 못 함 | `different_dirty_rule_source_same_key=true` | `PReplay.code_hash`(scripts/tools .gd + 장면 .tscn + project.godot 내용 해시, .uid/.import 제외) + rules/observe 버전을 캐시 키에, `PBotBatch.can_resume`(unknown이면 재개 거부)·`cache_diff` | false |
회귀: `tests/bot_tests.gd` **56/56**(§12 13건 추가: 12a~12j), boss_tests 34 · port_tests 76 · boss3_tests 111 · run_tests 72, `density_report` 42행 결과 열 동일 — 모두 종료 0. 12e는 실제 능선 3일차 전투 20초에서 적 투사체 18개 전부 발사 시 id가 찍히고 수명 동안 불변임을, 12f는 발사자가 다음 공격(#3)을 준비해도 피격 기록이 발사 시점(#2)에 붙음을 확인.

### 19-2. 수정 전후 같은 조건 비교 (`docs/sim/BOT_COMPARE_AUDIT2.md`, run `audit2_before`·`audit2_after`)
수정 전 = 8dfcbd1을 별도 worktree에 체크아웃해 새로 실행(기존 보고서 수치 재사용 없음), 수정 후 = 이 커밋. 시나리오 7(기준 늑대25 · 능선 3일차 궁수 · 습지 4일차 장판 · 봉인 수호자 · 성문 파수장 · 포자 어미 · 서리 추적자) × 봇 4 × 시드 5(보스 3) = 108행씩. 데이터는 줄 끝(CRLF)만 다르고 내용 동일.
| 관찰 | 값 |
|---|---|
| balanced(기존 정책, 관측 미사용) 27행 | 결과·피해·시간 **전부 동일** → 게임 규칙·난수 불변 |
| 기준 늑대25(장판·투사체 없음) 실력 봇 15행 | 전부 동일 |
| 능선 3일차(궁수 투사체) | 승 novice 0→1, regular 1→3, skilled 2→2(시간 초과 2→2). regular 평균 피해 98→84 — 투사체 id가 안정되어 추적·회피가 이어짐 |
| 습지 4일차(장판) | novice·regular 0→0, skilled 1→0(시간 초과 3→1, 평균 피해 53→98) — 독립 장판마다 새 지연을 받아 반응이 늦어짐(지적 1의 의도된 결과: 이전 값이 봇을 과대평가) |
| 보스 4종 | 승 전부 3/3 유지. 포자 어미 피해 novice/regular/skilled 82/64/68 → 71/53/56, 서리 추적자 novice 20→4·skilled 0→8, 봉인 수호자 novice 7→0 |
| 행 단위 | 108행 중 54행 변화(전부 실력 봇 × 장판/투사체가 있는 시나리오), 합계 승 novice 17→18 · regular 18→20 · skilled 20→19 · balanced 17→17 (각 27전투) |
`audit2_after`는 버전 문자열을 0.6.1로 올리기 직전(코드는 그 문자열만 다름, 5afb3d7)의 실행이라 meta의 game_version은 0.6.0이다. 방향은 한쪽이 아니다(지적 1은 피격 증가, 지적 2는 감소·증가 모두). 어느 표도 사람 승률·밸런스 승인이 아니다. 기존 `BOT_COMPARE.md`·`BOT_COMPARE_BOSS3.md`에는 "수정 전 결과" 주의를 달았고, 전체 27경로·STOP3 재실행은 관련 비교가 안정된 뒤 범위를 정한다(검수 지시).

### 19-3. 하지 않은 것
- 정복자 0/50 비교, 무한 시간당 보상, 전체 경로 전수 재실행(검수 지시대로 관련 시나리오·대표 보스만).
- `unclassified` 피격 태그가 장판 시나리오에서 늘었다(수정 후 skilled 32). 태그 분류 규칙(장판 안 피격의 원인 구분)은 다음 측정 항목.

## 20. 재검수(godot-audit-427dae9) 잔여 1건 수정 + godot-0.6.1 배포물 (2026-09-08, Windows 로컬)
재검수 보고: `C:\Users\Public\Documents\ESTsoft\CreatorTemp\godot-audit-427dae9-20260907\RECHECK.md`. 핵심 수정 3건은 확인됨. 잔여 = 소스 일부를 못 읽어도 나머지로 만든 부분 해시를 정상 코드 해시로 취급.

### 20-1. 수정·회귀
| 항목 | 내용 |
|---|---|
| 수정(86dadce) | `PReplay.code_hash` → 필수 폴더(scripts/tools/scenes) 열기 실패 또는 파일 하나라도 읽기 실패면 **부분 해시 없이 `unknown`**, 실패 경로는 `code_hash_failed()`·배치 meta `env.code_hash_failed`·`CACHE_INVALID` 메시지에. `_collect_code`는 폴더 열기 실패(false)와 빈 폴더(true)를 구분 |
| 회귀 | `tests/bot_tests.gd` **60/60**(12k 누락 파일 → unknown+경로 · 12l unknown/빈 목록 재개 거부 · 12m 폴더 열기 실패 구분 · 12n 정상 복귀 = 이전 전체 해시) |
| 잠금 파일 수동 확인(검수 절차 재현) | `tools/start_compare.gd`를 PowerShell FileShare.None 읽기 핸들로 잠근 채 검수 `hash_probe.gd` 실행: 정상 `330fce50…`/can_resume true → 잠금 **`unknown`/can_resume false** → 해제 뒤 같은 `330fce50…`/true. (잠금·해제 실행 2회는 결과 출력 뒤 엔진 종료 단계에서 segfault가 찍혔다 — 헤드리스 종료 시 간헐적으로 보이는 현상으로 결과값·종료 전 출력에는 영향 없음, 같은 프로브의 정상 실행과 bot_tests·패키지 exe는 종료 0) |
| 변경하지 않은 것 | 게임 수치·봇 프로필·관측 규칙. 108×2 비교는 재실행하지 않음(해시 예외 처리만 바뀜, 검수 지시) |

### 20-2. godot-0.6.1 배포물 (Codex 독립 검수 기준)
| 항목 | 값 |
|---|---|
| **최종 코드 커밋** | **86dadce** (5afb3d7 검수 2 수정 → 427dae9 버전 문자열 → 86dadce 잔여 1건). 이 뒤의 커밋은 ZIP·해시 기록만 |
| Windows 빌드 | `prophecy_godot_build/prophecy_godot_windows_godot-0.6.1_86dadce.zip` (안: `prophecy_godot/prophecy_godot.exe` 110,252,464 B + `실행_안내.txt`). exe SHA-256 `b31506ffc7ef099338e75b38dee5a2a98ec620b7f1770c4a4d3b1a700d0ffbfc`, ZIP SHA-256 `ef44907d5d47b1a7dcb2901b9271dbb8cfd4f14c6b806643676cf982b2341cc2` |
| 프로젝트 ZIP | `prophecy_godot_build/prophecy_godot_project_godot-0.6.1_86dadce.zip` = `git archive HEAD prophecy_godot` (310 파일). SHA-256 `ba61e4abed154831c8e4dd202f57fca360ed0379206b9fced600ddd13aaf0e6b` |
| 빌드 실행 확인 | 같은 PC, APPDATA 격리, 패키지 exe로 `PROPHECY_UI_SMOKE`(새 회차→…→4일차 성문 파수장 승리→저장→계속하기→검증 메뉴 빠른 전투): **종료 코드 0, 스크립트 오류 0, PNG 23장**. 저장 파일 경로 `%APPDATA%\Godot\app_userdata\예언의 시간표 — Godot 첫 전투\prophecy_save_v1.json` 확인(입력 기록도 같은 폴더의 `recordings\`). 사람 플레이 없음 |
| 사람 입력 기록 | 제목 → [검증 메뉴] → "이번 전투 입력 기록" 체크 → 사람이 직접 전투(기준 전투 또는 회차) → 종료 시 `recordings\<시각>_<시나리오>.json`(사람 입력만, 봇 전투 제외, 업로드 없음). `실행_안내.txt` 6항 |
| 미커밋(의도) | 루트 `index.html`·`CNAME`·`wash.jpg` 삭제, `icon.svg.import`, `.claude/`, `tests/tmp/` |

## 21. 사람 플레이 피드백 19건 반영 (godot-0.7.0, 2026-09-08, Windows 로컬)
근거 문서(저장소 밖): `prophecy-play-review-20260908/REVIEW_AND_BALANCE_OPTIONS.md`(피드백 17 + 직접 측정), `prophecy-ui-build-readability-20260908/UI_REDESIGN_HANDOFF.md`(빌드 가시성 + 임시 아이콘 20종). 결정 요약은 D44, 규칙 요약은 `docs/RULES.md` 변경 기록. **여기 있는 모든 수치는 시험값이며 사람이 승인한 균형값이 아니다.** 사용자 결정은 구조와 목표(25→75, 등급 교체, 금화 -30%, 보스 빈도 2.5배 시험, 지나치기 제거, 남는 시간 경로, 빌드 가시성, 일정 구분)까지다.

### 21-1. 피드백 19건 처리표
| # | 피드백 | 처리 | 상태 |
|---|---|---|---|
| 1 | 무료 이득을 버리는 '지나치기' | 비용·위험 없이 이득만 있는 사건(보급)에서 '지나친다' 제거, '보급품 챙기기'만. 비용·위험 있는 사건의 거절은 유지 | 구현·자동 확인 |
| 2 | 포자 단독 전투 | 지원·통제 역할이 과반인 템플릿 6종 교체(포자 단독 없음), 포자는 근접 압박과 함께 나오는 이동 제한 역할 | 구현·자동 확인 |
| 3 | 회피/Q/E 준비 표시 | 쿨다운 가림막·숫자, 준비 전환 순간 1회 테두리 점등, 기술별 효과음, 일시정지·복구 시 중복 알림 없음 | 구현·자동 확인 / 사람 확인 필요(체감) |
| 4 | 금화 약 30% 감축 | 새로 지급하는 금화 ×0.7(전리품·상자·사건·임무 대체·심층), 판매금·환불·잔액 제외, 최종 지급 1회 | 구현·자동 확인 |
| 5·10 | 남는 시간에 나갈 곳이 없음 | 완료한 같은 장소에 '일반 탐험 · 1칸' 재출격(임무 보상·사건·이용권 재지급 없음). 휴식을 선택/강제로 구분해 집계 | 구현·자동 확인 |
| 6 | 가시갈기가 붙으면 안전 | 근거리 물기·발톱 연계, 옆 뛰기로 스스로 돌진 거리 확보, 도약 후 추격, 연계 끝에만 확실한 빈틈. d=80 후보가 `{sweep:100}` → `{dash:56, sweep:44}` | 구현·자동 확인 |
| 7 | 방패병 역할·표시 | 기능은 이미 있었음(정면 70% 경감, 준비 중 개방). 이번에 체력을 역할표로 올리고(붉은 270·변이 600) 이름·표시를 정리. 방어/개방 비율 조정은 미실시 | 부분 구현 / 사람 확인 필요 |
| 8 | 변경권·문장 혼동 | 용어를 '개조 변경권'으로 통일(서비스 이름·설명·용어 사전·보상 문구·버튼), 보유 수 표시, 버튼은 '변경권 사용' 또는 '140G로 변경' | 구현·자동 확인 |
| 9 | 제단의 목적 | 적 치유 제단 / 소환 제단 / 저주 제단으로 이름 변경 + 짧은 효과 한 줄('적 회복 중 · 파괴하면 멈춤') | 구현·자동 확인 |
| 11 | 후반 성장 격차 | C안: 등급 교체(1막 일반 / 2막 일반+붉은 / 3막 붉은+변이) + 역할별 고정 체력표. 경험치 ×0.3은 그대로 | 구현·자동 확인 |
| 12 | 후반에 한 마리씩 나옴 | 혼합 분대 등장(역할 섞기·묶음 첫 자리 근접·묶음당 지원 비율 상한·말미 묶음 확대). 후반 1~2마리 시간 85.0 → 28.0초, 지원 적만 남은 시간 128.2 → 64.9초 | 구현·자동 확인 |
| 13 | 주술사 즉사 | 주술사 편성에 근접 호위 필수(자동 검사), 지원 체력 붉은 135·변이 300으로 상향 | 구현·자동 확인 / 사람 확인 필요 |
| 14 | 2막 이후 성장 중단으로 완주 | 정상/중단 × 변형 × 봇 비교표(`docs/sim/BALANCE_COMPARE.md`) | 측정 완료 / 사람 판단 |
| 15 | 기술별 DPS 표시 | 기본 표(총 피해·기여율·평균 DPS) + 직접/지속/개조/공용 파생과 분모, 런 전체·최근 전투·보스별 보기, 보호막 흡수·회복·체력 손실 분리 | 구현·자동 확인 |
| 16 | 7일/10일 혼동, 보스 속도 | 계속하기 '이전 회차 · 7일 일정', 새 회차 '본편 · 10일', 상단·결과에 실제 일정·밀도·상한·밸런스·시드. 보스 개시 빈도는 **9종 중 4종만 목표 2.5배 달성**(평균 2.69는 달성 근거가 아님) | 부분 구현 / 사람 판단 필요 |
| 17 | 성장 기반 수치안 | A/B/C 중 C안 적용. 실측 기준 DPS(22/68/150) × 역할 목표 시간으로 고정표 산출 | 구현·자동 확인 |
| 18 | 빌드·개조 가시성 | 아이콘 20종 도입(중앙 매핑), 자동기술 3칸 + 소속 개조 2칸, 회피/Q/E·장비 영역 분리, 개조 발동/적중/피해 계측과 연출 연결 | 구현·자동 확인 / 사람 확인 필요(가독성) |
| 19 | 날짜별 적 수 증가 | 25/30/35/40/45/50/55/60/70(비용 2칸 +7% → 9일차 75). 총 등장 수와 동시 상한 분리, 보상 예산 고정 | 구현·자동 확인 |

### 21-2. 적용된 기본값(전부 시험값)
| 항목 | 값 |
|---|---|
| 일정 | 본편 10일·3막·관문 4/7/10(기본). 옛 7일 저장은 trio로 그대로 진행하며 화면에서 구분 |
| 날짜별 총 등장 수 | 1~9일 25/30/35/40/45/50/55/60/70, 비용 2칸 장소 ×1.07(9일차 75). 10일차는 관문 전용 |
| 막별 동시 상한 | 1막 12 · 2막 15 · 3막 18(대조군 `legacy` = 템플릿 값). 첫날 기준 전투는 항상 12 |
| 등급·역할별 체력 | 기준 DPS 22(출발)/68(2막 초)/150(3막 초) × 목표 시간(무리 0.8 · 지원 2.0 · 주력 2.2 · 중장갑 4.0 · 정예 8.0초) → 늑대 30/150/330, 궁수 22/135/300, 방패병 60/270/600, 무리 35~45/54/120, 정예 막별 120/545/1200 |
| 보스 체력 | 가시갈기 3500 · 봉인 수호자 9000 · 예언을 먹는 자 12500(신규 6종 3200~13000). 1차 후보 6000/15000/18000을 새 행동과 합쳐 실측한 뒤 낮춤 |
| 보스 공격 개시 빈도 | **사용자 목표 2.5배를 채운 보스는 9종 중 4종**(3.82·2.89·2.83·2.70). 미달 5종은 가시갈기 2.45·포자 어미 2.45·거수 2.39·사냥왕 2.38·집행관 2.28. 9종 평균은 2.69지만 **평균은 보스별 목표의 달성 근거가 아니다**. 예고 시간은 일괄 단축하지 않고 첫 공격은 원래 예고 100%, 후속만 ×2.4에 0.45초 하한 |
| 경험치 | ×0.3 유지. 전투 경험치 예산은 개체 수와 무관(27마리 → 75마리에서 동일) |
| 금화 | 새 지급분 ×0.7. 판매·환불·잔액 제외 |

### 21-3. 검증 (이 PC, APPDATA 격리, 봇·스크립트 — 사람 입력 없음)
| 항목 | 결과 |
|---|---|
| 스위트 | run 72 · port 76 · boss 43 · boss3 125 · boss_pace 10 · bot 60 · balance 45(신설) · hud 38(신설) · acts 23 · theme 28 · endless 58 · meta 78 · meta_ui 11 · input 60 · run_layer 64 · world 33 · content 28 · ui_flow 14 = **866**, 모두 종료 0 |
| 승인된 첫 전투 보존 | `tools/density_report.gd` 42행 결과 열 동일(µs 열 제외). 늑대 25·동시 12·경험치 예산 9.0 |
| UI/연출의 규칙 독립성 | 같은 시드·같은 기록 입력으로 UI 변경 전후 승패·시간·피해·처치 동일(steps만 프레임 페이싱으로 ±3). 표시 코드는 전투 난수(`st.rng`)를 소비하지 않음(자동 검사) |
| 성장 체크포인트 | `docs/sim/GROWTH_CHECKPOINTS.md` — 출발 22.0 / 1막 말 42~73 / 2막 초 42~95 / 2막 말 63~155 / 3막 말 68~258(정지 단일 표적 30초) |
| 보스 시간 재측정 | `docs/sim/BOSS_TIME.md` — 가시갈기 56~65초 · 봉인 수호자 91~95초 · 예언을 먹는 자 88~137초(실력 봇). 이동 없음·추적만 정책은 전부 패배 |
| 원인 분리 비교 | `docs/sim/BALANCE_COMPARE.md`(변형 × balanced·regular·skilled × 정상/3일 중단, 12회차씩). **완주율은 성장 조건을 나눠 읽는다** — 정상 성장 off 5/6 · counts 5/6 · hp 2/6 · full 3/6, 3일차 중단 off 2/6 · counts 2/6 · hp 1/6 · full 1/6(합친 7/12·3/12·4/12은 두 실험을 섞은 값). **`off`는 개편 전이 아니다**: 새 보스 행동은 네 변형 모두에 들어 있어 0.6.0 이전 난이도의 대조군이 아니다. **말미 대기 시간은 같은 조건끼리만 비교한다** — 네 변형 모두 10일차까지 간 공통 2회차에서 후반 1~2마리 257.2 → 86.8초, 지원 적만 남은 시간 256.6 → 213.3초(12회 전체 평균 85.0→28.0·128.2→64.9는 일찍 끝난 회차가 만든 값이라 쓰지 않는다). 표본 2회이므로 방향만 읽는다 |
| 보스 행동 비교 | `docs/sim/BOSS_PACE.md` — 개시 빈도 전후, 빈틈 비율, Q 켜짐/꺼짐 |

### 21-4. 사람이 판단할 항목
- 후속 공격 예고 0.45초 하한이 읽히는가(보스 연계의 유일한 사람 판정 값). 3막 최대 10연계의 체감.
- 포자 어미가 실력 봇 기준으로 가장 어렵다(보스 행동 개편 뒤 0/2). 사람 플레이로 난이도인지 봇 한계인지 판단.
- 9일차 75마리·동시 18의 체감(대기 시간 대신 위협이 늘었는가), `legacy` 상한 대조군과 비교.
- **난이도 총량**: 봇 완주가 12회차 중 4회다(개편 전 7회, 새 보스 행동 포함 기준). 사람 기준으로 적절한지, 어느 축(적 체력 / 보스 / 적 수)을 되돌릴지는 사람 판단이다. 봇이 졌다는 이유만으로 수치를 내리지 않았다.
- 붉은 개체가 3막에서 쉬워지고 변이가 주력이 되는 교체가 실제로 느껴지는가.
- 금화 -30% 뒤 첫 구매 시점과 구매 리듬.
- HUD에서 자기 빌드와 개조가 실제로 읽히는가(아이콘 20종 + 누락 81종은 임시 기호).

### 21-5. 하지 않은 것·미검증
- 사람 키보드·마우스·터치 플레이 없음. Android/iOS 실기·세로 모드 미검증.
- 상점 가격, 구조물(제단) 체력, 방패병 방어/개방 비율은 이번에 바꾸지 않았다.
- 아이콘 81종 미제작(임시 기호 + 실제 이름으로 표시, 목록은 `docs/sim/ICON_COVERAGE.md`).
- 27경로 전수 재실행·정복자 0/50 비교·무한 구간 보상은 이번 범위 밖.
- `data/boss_behavior.json` 추가로 `PReplay.data_hash()`가 바뀌어 이전에 저장된 재생 기록은 데이터 해시 불일치로 표시된다(규칙 오류 아님).

### 21-6. 최종 커밋·빌드·해시
| 항목 | 값 |
|---|---|
| **최종 코드 커밋** | **3501e09** (브랜치 `claude/prophecy-action-prototype-hehbeo`, 로컬, push 안 함) |
| 구성 커밋 | 073f74f(개조 계측 훅) → 4223afd(밸런스 코어) → c0c31eb(실측 체력표·회귀 45) → b48c9a4(UI 병합 6ce9b09) → 5acd0e2(UI·규칙 연동) → 569f709(비교 도구·D44) → 542188e(보스 행동 병합 5f3a14a) → 81fa26a(보스 체력 재측정 조정) → ceeb62a(0.7.0·캡처·UI 경로 검증) → 3501e09(§21 최종 수치) |
| Windows 빌드 | `prophecy_godot_build/prophecy_godot_windows_godot-0.7.0_3501e09.zip` (안: `prophecy_godot/prophecy_godot.exe` 110,617,824 B + `실행_안내.txt`). exe SHA-256 `7b061f4cbf43d6fb20591cddac1b6554020c5900159a149e93dda8878e110a33`, ZIP SHA-256 `5f59965d5e23609a2063e6bd41755c1342b5e1e0af639918bd506dfbff6a3a17` |
| 프로젝트 ZIP | `prophecy_godot_build/prophecy_godot_project_godot-0.7.0_3501e09.zip` = `git archive HEAD prophecy_godot` (551 파일). SHA-256 `b1d3355e9857e6e91a5443f6e0abda79366731e70a84bad407b1a7c5178fde93` |
| 패키지 exe 실행 확인 | 같은 PC, APPDATA 격리, `PROPHECY_UI_SMOKE`: **종료 코드 0, 스크립트 오류 0, PNG 23장**(제목→새 회차→마을→전투→상점/대장간/장비/통계→하루 종료→4일차 관문→검증 메뉴). 사람 플레이 없음 |
| 재현 순서 | ① 3501e09 체크아웃 ② `--headless --path prophecy_godot --import` ③ 21-3의 18개 스위트(APPDATA 격리; run_layer·world·content·ui_flow는 `PROPHECY_LEGACY_PLACES=1`) ④ `tools/density_report.gd`(결과 열 비교) ⑤ `tools/growth_checkpoints.gd` · `tools/boss_time_check.gd` · `tools/balance_compare.gd`(`PROPHECY_PACING`으로 변형 전환) ⑥ `--export-release "Windows Desktop"`(내보내기 템플릿은 실제 APPDATA에 있어야 한다) |
| 미커밋(의도) | 루트 `index.html`·`CNAME`·`wash.jpg` 삭제, `icon.svg.import`, `.claude/` |

## 22. 공통 테스트 실행기 · 자동 진행 완료 판정 · 진행 정지 원인 3건 (2026-09-08, Windows 로컬)

0.7.0 검토 지시 §1의 결과다. **난이도 수치는 하나도 바꾸지 않았다** — 적 체력·적 수·보스 행동·성장·금화는 §21 그대로이며, 여기서 고친 것은 실행기·완료 판정과 진행을 막던 결함 3건이다.

### 22-1. 공통 테스트 실행기 (`tools/run_suites.py` + `tools/suites.json`)

2026-09-08 고아 루프(스크립트 오류로 중단된 헤드리스 프로세스가 스스로 끝나지 못해 부모 루프가 91분·75분 막힘, `scratchpad/orphan_evidence/`)의 재발 방지다.

| 항목 | 구현 |
|---|---|
| 개별 제한 시간 | 스위트마다 `timeout_sec`(명세). 초과하면 **그 실행의 프로세스 트리만** `taskkill /T /F`로 종료한다. 우리가 띄운 PID만 다루고 이름으로 싹쓸이하지 않는다 |
| 통과 판정 | 종료 코드 0 **그리고** `N/N PASS` 요약 **그리고** `FAIL` 0건 **그리고** `SCRIPT ERROR`·`Parse Error`·`Compile Error` 없음. 넷 중 하나라도 어긋나면 통과가 아니다 |
| 상태 구분 | pass / fail / script_error / timeout / config_error / aborted → 종료 코드 0 / 1 / 1 / 2 / 3 / 130 |
| 필수 환경 설정 | `suites.json`이 정본. 실행기가 자동으로 넣으므로 **공통 실행기를 사용하는 경로에서 예방된다**(호출자가 빠뜨릴 수 없다). 호출 환경이 다른 값을 강제하면 조용히 덮어쓰지 않고 이유를 적어 즉시 config_error로 끝낸다 |
| 중복 실행 | `locks/<프로젝트>__<스위트>.lock`을 `O_CREAT\|O_EXCL`로 잡는다. 잠금을 쥔 PID가 이미 죽었으면 회수하고 기록한다(강제 종료된 실행 하나가 스위트를 영구히 막지 않게) |
| 고유 로그 | 실행마다 `<스위트>__<시각.밀리초>.log`. 덮어쓰기 없음. 출력 폴더가 필요한 실행은 `out__<스위트>__<시각>` |
| 격리 | 실행마다 APPDATA/LOCALAPPDATA를 전용 폴더로. 사용자 실제 저장·프로필을 건드리지 않는다 |
| 조기 종료 | 치명적 오류(`SCRIPT ERROR`·`Parse Error`·`Failed to load script`)가 로그에 뜬 뒤 15초가 지나도 프로세스가 살아 있으면 제한 시간을 기다리지 않고 종료해 **script_error**로 적는다. 오류로 중단되면 `quit()`에 닿지 못한다는 것이 고아 루프의 형태였다 |
| 시간초과의 선행 원인 | 시간초과 전에 이미 오류가 있었으면 최종 상태는 timeout이되 `root_cause`·`root_cause_evidence`·`root_cause_at`에 그 오류를 함께 남긴다 |
| 취소 | Ctrl+C 시 우리가 띄운 프로세스 트리 종료·잠금 해제·`ABORTED.md` 기록·종료 코드 130. 계속 돌릴 작업은 `HANDOVER.txt`로 본 세션에 명시 인계 |

**실행기 자기 검증 7/7** (`python tools/run_suites.py --self-test`, 로그는 `<run>/selftest.md`).

| 검증 | 기대 | 실제 |
|---|---|---|
| 필수 설정 충돌(호출자가 `PROPHECY_LEGACY_PLACES=0` 강제) | config_error | config_error, 실행하지 않음 |
| 필수 설정 자동 적용 | pass | pass |
| 스크립트 오류(quit 미도달) 조기 종료 | script_error | script_error, 16.2초(제한 시간 180초를 기다리지 않음) |
| 강제 시간초과(끝나지 않는 실행) | timeout | timeout, 20.2초, 트리 종료 |
| 중복 실행 시도(잠금 보유 중) | config_error | config_error, 0.0초 |
| 실행 중 취소 | aborted/130 | 130, 잠금 해제됨, 대상 Godot 2→0, `ABORTED.md` 기록 |
| 취소 뒤 같은 스위트 재실행 | 실행 가능 | 정상 실행됨 |

**이 7건은 실행기 자체의 검증이며, 게임 스위트 통과와는 별개다.**

### 22-2. 자동 진행(`PROPHECY_UI_SMOKE`)의 완료 판정 수정

고친 것은 두 가지다.

1. **프레임 수 → 단조 증가 시계.** 옛 안전장치는 `_auto_frames > 60*60*40`으로, 60FPS일 때만 40분이었다. 배속·부하에 따라 실제 경과와 크게 달랐다. 이제 `Time.get_ticks_msec()` 기준 실제 경과(`PROPHECY_UI_MAXMIN`)로 재고, **게임 속 전투 시간은 따로** 합산해 함께 기록한다.
2. **시간 초과와 정상 완료가 같은 출력·같은 종료 코드였다.** 옛 코드는 40분 상한에 걸려도 `_auto_finish()` → `UI_SMOKE done` → `quit()`(0)이었다. 즉 **중단이 통과로 보였다.** 이제 상태를 나누고 종료 코드를 붙인다.

| 상태 | 뜻 | 종료 코드 |
|---|---|---|
| done | 요구한 마지막 단계까지 도달 | 0 |
| timeout | 실제 경과 상한 초과 | 2 |
| stalled | 진행이 멈춘 채 정체 시간 초과 | 3 |
| incomplete | 끝까지 갔으나 요구 단계 미도달 | 4 |

요구 단계는 모드별로 다르다. **전체 회차**(`PROPHECY_UI_FULL`)는 관문 1·2·3 → 10일차 회차 결과 → 저장/계속하기 전부, **짧은 화면 순회**는 거점·전투·저장/계속하기까지다(짧은 순회는 완주 검증이 아니다). 정체 판정은 화면·날짜·시간대·전투 상태·등장 수·처치 수를 묶은 서명이 `PROPHECY_UI_STALL`초 동안 그대로일 때다.

멈추면 그 자리 상태를 남긴다(추정하지 않기 위해): 화면·자동 상태·선택창 열림·날짜·남은 시간대·단계·레벨·넘은 관문·재도전 수 / 전투의 목표 종류와 진행 문구·경과·상태·생존 수·등장 대기·등장 완료 여부·플레이어 좌표와 체력·가장 가까운 적 거리·장판·투사체·남은 개체 목록(종류·등급·상태·좌표·거리)·장애물과의 겹침 / 마지막 진행 이벤트와 그 뒤 경과·구간별 소요. 같은 내용을 `<출력폴더>/smoke_result.json`으로도 남기고, 30초마다 `UI_SMOKE heartbeat`로 현재 위치를 찍는다.

실행기에는 자동 진행 스위트 2종을 넣었다(`ui_smoke_full`·`ui_smoke_short`, 그룹 `smoke`). 이 둘은 `N/N PASS` 요약이 없으므로 **`UI_SMOKE result=done` + 종료 코드 0**으로 판정한다.

### 22-3. 자동 진행이 멈추던 진짜 원인 3건 (모두 로그 증거로 확인, 추정 아님)

옛 보고는 "2일차에서 40분 프레임 상한"이라고만 적고 원인을 전투가 길어진 탓으로 짐작했다. **그 짐작은 틀렸다.** 실제로는 세 가지 결함이 차례로 막고 있었고, 셋 다 고쳤다. **9일차 편성·보스 체력은 원인이 아니었다.**

| # | 증상(증거) | 원인 | 조치 |
|---|---|---|---|
| 1 | 2일차 `t1a_path`, 게임 속 **1832.9초**, 처치 0, 남은 개체는 `altar_hazard`·`altar_reinforce` 2기뿐(체력 90/90) | 임무 목표가 '제단 파괴'인데 **실력 프로필 봇이 구조물을 전부 건너뛴다**(`skill_bot.gd`의 대상 선택). 정책 봇(`bot.gd`)은 제단을 목표 우선 대상으로 다뤘지만 실력 봇에는 그 규칙이 없었다 | 일반 적이 남지 않았으면 구조물을 대상으로 삼는다. 위협 판단·회피에서는 계속 구조물을 무시한다(제단은 쫓아오지 않는다) |
| 2 | 3일차 같은 지역, 게임 속 **1841.9초**, 남은 적 0, 등장 10/10 완료, 목표 `rescue` 진행 **"구출 0 / 2"** | 목표형 임무(구출·봉인)는 적을 다 죽여도 끝나지 않는다. **두 봇 모두 목표 행동이 없어** 우리 안으로 가지 않았고, 전투에 제한 시간이 없어 영원히 이어졌다 | 때릴 적이 없으면 남은 목표 지점(우리 안·봉인 지점 먼저, 모두 끝나면 출구)으로 이동한다 |
| 3 | 9일차 `t3a_center`, 게임 속 **1823.9초**, 플레이어 좌표 (536,300)에 **완전 고정**, 체력 89 유지, 붉은 궁수 3기 체력 135/135 그대로. 봇은 계속 이동 입력을 냈다(마지막 입력 (0.0,-1.0)) | **게임 버그.** 플레이어가 바위(중심 (480,300)·반지름 42)에 정확히 접해 있었다(거리 56.0 = 42+14, 겹침 0.0). `push_out`이 정확히 접점에 놓고, `sweep_circle`은 접점에서 출발하면 **어느 방향이든 t=0으로 막힌다**고 판정해 미끄러짐까지 0이 된다. 그래서 한 번 붙으면 영원히 못 움직인다 | 이미 닿아(또는 겹쳐) 있는 장애물에서 **멀어지는** 이동은 막지 않도록 `sweep_circle`에 예외를 뒀다(`leaving_ok`). 접근 방향의 판정은 그대로다. **적용 범위는 플레이어 이동뿐이다** — 적에게도 적용하면 승인된 첫 전투(늑대 25)의 결과가 바뀐다(아래 22-4) |

3번은 봇만의 문제가 아니라 **사람이 플레이해도 같은 자리에서 못 움직이게 되는 결함**이었다. 화면 순회(짧은 모드)는 1일차 전투만 하고 끝나서 이 셋을 한 번도 만나지 않았고, 그래서 지금까지 "종료 코드 0"으로 통과 처리돼 왔다.

부수적으로 자동 진행의 3택 선택을 **첫 후보 고정**에서 회차 봇과 같은 규칙(`PBot.pick_choice`)으로 바꿨다. 첫 후보만 고르면 빌드가 한쪽으로 치우쳐 4일차 관문을 넘지 못했다(레벨 8, 4회 연속 패배). 전투 규칙·수치는 건드리지 않았다.

**안전장치를 늘려 해결했다고 적지 않는다.** 상한·정체 감시는 *멈춘 것을 통과로 적지 않기 위한* 판정이고, 진행이 막히던 원인 3건은 위 표대로 코드에서 고쳤다.

### 22-4. 검증 (이 PC, 공통 실행기, APPDATA 격리, 봇 — 사람 입력 없음)

| 항목 | 결과 |
|---|---|
| 실제 UI 경로 전체 회차 (`ui_smoke_full`, 헤드리스, 시드 1, 실력 봇, 경로 고정) | **`UI_SMOKE result=done` · 종료 코드 0**. 아래 초는 전부 **실행 시작 후 누적 실제 경과(도달 시각)**이며, 각 보스전에 걸린 시간이 아니다.

| 도달 단계 | 누적 실제 경과 |
|---|---|
| 저장→종료→계속하기 | 82초 |
| 관문 1 | 81초 |
| 관문 2 | 151초 |
| 관문 3 · 10일차 회차 결과 | 294초 |
| 실행 종료 | 318초 |

같은 실행의 **게임 속 전투 시간 합계는 1548.8초**다(실제 경과 318초와 다른 값이다 — 헤드리스는 화면 주사율에 묶이지 않고, 배속 6이 걸려 있다). 회차 결과 뒤 무한 모드·새 회차 화면까지 진행. 넘은 관문 `["boss","guardian","eater"]`, 최종 레벨 22 |
| 저장 → 종료 → 계속하기 | 위와 **별도 단계로 표시**(`reached=save_continue`, 82초). 4일차 관문 결과에서 저장 후 제목 화면으로 나갔다가 계속하기로 복귀, 날짜 4·단계 1·레벨 8·금화 445 유지 확인 |
| 짧은 화면 순회 (`ui_smoke_short`) | `UI_SMOKE result=done` · 종료 코드 0. 완주 검증이 아니라 화면 순회 확인이다 |
| 승인된 첫 전투(D33) 보존 | `tools/density_report.gd` **44행 전부 동일**(µs 열 제외). 확인 방법: 내 수정을 잠시 빼고(`git stash`) 문서를 재생성해 커밋본과 대조(0/44 차이) → 수정을 되돌리고 다시 재생성해 대조(0/44 차이). 재생성 자체가 문서를 덮어쓰므로, 대조 전에 커밋본을 따로 복사해 두었다 |
| 게임 스위트 18종 | **874개 검사 전부 통과**(공통 실행기, 동시 2). 검사 조건은 하나도 완화하지 않았다 |
| 알려진 간헐 결함 | `ui_flow_tests`가 21/21 통과를 찍은 **뒤 종료 시점에** 접근 위반(0xC0000005)으로 죽는 경우가 있다(동시 실행 중 1회 관측, 이후 단독 3회·동시 2회는 정상). 실행기는 이것을 **통과로 세지 않는다**(종료 코드 0이 아니므로 fail). 원인 미확인 — 검사 자체가 아니라 종료 처리 문제로 보인다 |

### 22-5. 끼임 수정의 적용 범위를 플레이어로 제한한 이유 (측정 기록)

처음에는 플레이어·적 모두에 적용했다. 그러자 승인된 첫 전투 비교표에서 **x5(늑대 25)·x10 행의 결과가 실제로 달라졌다** — 예: x5 stand 시드 6 등장/처치 25/18 → 24/13, x10 stand 시드 4 41/28 → 31/18. 바위에 붙어 멈춰 있던 적들이 움직이기 시작하기 때문이다. base(늑대 5) 행은 그대로였다.

**승인된 첫 전투를 보존하라는 제약이 우선이므로 적에게는 적용하지 않았다.** 플레이어 이동(걷기·회피·밀림)에만 적용하니 44행이 전부 원래 값으로 돌아왔고, 스위트 18종도 검사를 고치지 않은 채 전부 통과했다.

남은 문제: **적도 같은 방식으로 바위에 붙으면 못 움직인다.** 그것까지 고치면 첫 전투 수치가 위처럼 바뀌므로 사람이 정할 일이다. 선택지는 (가) 지금처럼 플레이어만, (나) 적까지 고치고 첫 전투 기준표를 새로 잡기 — 둘 중 하나다.

### 22-6. 하지 않은 것

- **난이도 수치는 그대로다.** 적 체력·날짜별 적 수·동시 상한·보스 체력·보스 행동·경험치·금화 전부 §21 값이며, 이번에 하나도 조정하지 않았다.
- 사람 플레이 없음. 위 완주는 봇 결과이며 난이도 판단이 아니다.
- `ui_flow_tests` 종료 시 간헐 접근 위반의 원인은 찾지 못했다.
- 적 개체의 장애물 끼임은 고치지 않았다(22-5).

## 23. 사람 플레이 2차 피드백 + 성장 구조 변경 (2026-09-08, Windows 로컬)

근거 문서(저장소 밖): `prophecy-player-feedback2-20260908/FEEDBACK_AND_REVIEW.md`(사용자 요구 16건·정적 확인·미재현 구분), `prophecy-growth-hp-rebalance-20260908/GROWTH_HP_HANDOFF.md`(성장 구조 설계안). 결정 기록은 `docs/DESIGN_DECISIONS.md` D45.
**여기 수치는 전부 시험값이며 사람이 승인한 균형이 아니다.**

### 23-1. 사용자 평가를 그대로 둔다

> "이전보다 격차는 줄었지만 여전히 일반 전투가 전반적으로 너무 쉽다. 5일차에는 가만히 있어도 적이 접근하다 죽었다."
> "한 대 맞았을 때 피해량은 나쁘지 않다. 문제는 몬스터 공격이 실제로 적중하는 일이 적다는 것이다."

이 평가를 불씨 정령 한 종·특정 보스·UI 문제로 축소하지 않았고, 봇 승패로 반박하지 않았다.
그래서 이번 작업은 **체력만 올리는 방향이 아니라 "적이 살아서 공격을 실행하고, 그 공격이 실제로 닿는가"**를 함께 고쳤다.

### 23-2. 처리표

| # | 사용자 요구 | 처리 | 상태 |
|---|---|---|---|
| 1 | 전투에는 Space/Q/E만, 재사용 중 흑백, HP 빨강 | 전장 상시 표시를 조작 3칸으로 축소. 미보유/사용 불가/대기(흑백+초)/준비(컬러+점등) 구분. 준비 소리는 실제 전환 1회 | 구현·자동 확인 |
| 2 | 결과의 '계속'을 눈에 띄게 | 요약 옆 큰 버튼 + 스크롤 밖 하단 버튼, 세부 통계는 접힘 | 구현·자동 확인 |
| 3 | 글자 확대·설명 축소·3택에서 빌드 확인 | 본문 11~13 → 13~17, 구현 설명은 상세로, 3택에 '내 빌드 보기'(상세 후 복귀해도 재추첨 없음) | 구현·자동 확인 |
| 4 | 2일차 남는 시간에 나갈 곳 없음 | 완료 카드 안에 '일반 탐험 · 1칸' 버튼 연결(규칙에는 있었고 화면 연결만 빠져 있었다) | 구현·**실제 UI 확인** |
| 5 | 불씨 정령 두 발 의심 | 자동기술 10종 전수 검사. 기본 발사 주기 전부 이론값과 일치. `scatter`(3장판)·`trail`(+2장판)이 한 발에서 만드는 장판이 원인 | 확인 완료(버그 아님) |
| 6 | 타격감 | 막기 연출(방패 타격·금속음·'방어')만 이번에 추가. 나머지 타격감은 미착수 | 부분 |
| 7 | 랜덤 지형 | 미착수 | 남음 |
| 8 | 쿨다운 계산 설명 | 카드에 전→후만 크게, 계산식은 상세. 계산 규칙 자체는 불변 | 구현·자동 확인 |
| 9 | 금화가 남는데 쓸 곳이 부족 | 미착수(상점·장비·소모품) | 남음 |
| 10 | 5일차에도 접근 중 적이 죽는다 | 체력 재조정(H2 → H3) + 방패병 85% + 특수 정예 7종 + 임무 지원 수정 | 구현·사람 판단 필요 |
| 11 | 봉인 지원 부족·목적 안 읽힘 | 임무가 날짜 예산 편성을 버리던 문제 수정. 29.6초 적 1 → 7, 빈 전장 16.9 → 0.4초. 목표 표시에 상태·방향·거리 | 구현·자동 확인 |
| 12 | 제단이 효과 전에 파괴 | 막별 체력·첫 발동·호위·배치 조정. 파괴 5.2 → 33.2초. 무적 없음 | 구현·자동 확인 |
| 13 | 수호자가 돌 뒤에서 안 맞음 | 세 방식 비교 후 우회 재배치 채택. 돌 뒤 정지 피해 0 → 512 | 구현·자동 확인 |
| 14 | 양갈래 가운데가 항상 안전 | 조준 공백 수정 + 예고된 가운데 후속타. 정지 피해 195 → 630, 빈도 불변, 회피 봇 387 → 377 | 구현·자동 확인 |
| 15 | 9일차 이동 불능 | 재현했고 원인은 접점 끼임(§22, fc3a62f)과 같았다. 그 아래 남은 결함은 KD-3으로 기록 | 재현·수정·잔여 기록 |
| 16 | 중력핵 기여가 작음 | 실제 전투에서 측정(읽기 전용 훅). 한 번 눌러 4~5마리를 맞혀도 **회당 처치 0.0~0.7**, 실제로 끌려온 거리 33~52px(반지름 140), 체류 0.69~0.98초. 후보 4종을 같은 시드로 비교해 **폭발 마무리**(기본형도 끝날 때 피해 ×2.0)를 시험안으로 적용 — 회당 처치 0.24 → 0.59, 보스 회당 피해 11.1 → 29.9. 제어력 강화는 측정으로 기각(끌어당김 90→170에도 끌린 거리 +12%, 피해·체류는 감소) | 측정·시험값 적용(`docs/sim/GRAVITY_TUNE_DECISION.md`) |

### 23-3. 성장 구조 변경 (D45)

| 항목 | 전 | 후 |
|---|---|---|
| 레벨 배율 | 1 / 1.2 / 1.4 / 1.6 / 1.8 | **1 / 1.35 / 1.8 / 2.35 / 3.0** |
| 개조 자격 | 레벨과 무관 | **Lv2 첫 개조 · Lv4 두 번째** |
| 대장간 | 전체 자동기술 | **고른 자동기술 하나** |

같은 선택 예산에서 세 정책을 비교했다(`docs/sim/GROWTH_COMPARE.md`). 정지 단일 표적 DPS 중앙값:

| 예산 | A 집중 | B 분산 | C 연계 |
|---:|---:|---:|---:|
| 5 | **89** | 48 | 51 |
| 10 | 94 | 96 | **126** |
| 15 | 94 | 175 | **180** |
| 20 | 122 | **258** | 175 |

세 정책의 장점이 서로 다른 구간에 있다. **Q/E 주력 딜링 트리는 이번 범위가 아니며 추후 확장으로만 기록했다.**

### 23-4. 체력: 중복 상향을 막는 네 단계

`H0`(0.7.0 이전) → `H1`(0.7.0 역할표) → `H2 = H1 + (H1 − H0)`(사용자 지시) → `H3 = H2 × √R`(성장 보정).
R은 같은 선택 예산에서 잰 새·옛 구조 DPS 중앙값 비다(일반 0.94 · 붉은 1.50 · 변이 1.67).
**새 레벨 배율 3.0을 적 체력에 곱하지 않았다.** 일반 등급은 R < 1이라 내리지 않고 H2 그대로 두었다.
종류·등급별 표는 `docs/sim/HP_TABLE_2.md`와 `docs/sim/GROWTH_HP_REBALANCE.md`.

승인된 첫 전투(D33)는 이 오버레이를 적용하지 않는다(`CombatState.reference_fight`). 본편 일반 늑대 48과 기준 전투 늑대 30이 다르며, 그 차이를 문서에 적어 둔다.

### 23-5. 검증 (이 PC, 공통 실행기, APPDATA 격리, 사람 입력 없음)

| 항목 | 결과 |
|---|---|
| 게임 스위트 20종 | **1010개 검사 전부 통과**(순차 실행). 남은 실패 1건은 KD-1(검사 통과 뒤 종료 시 접근 위반)이며 실행기가 통과로 세지 않는다 |
| 실제 UI 전체 회차 | `UI_SMOKE result=done` · 종료 0. **도달 시각은 실행 시작 후 누적 실제 경과다** — 관문 106 / 238 / 392초, 10일차 회차 결과 392초, 저장→계속하기 107초, 종료 431초 |
| 같은 실행의 게임 속 전투 시간 | **2168.4초**(체력 상향 전 1548.8초 → +40%). 실제 경과와 다른 값이다 |
| 승인된 첫 전투(D33) | 44행 그대로(오버레이 미적용) |
| 자동기술 중복 발사 | 10종 전부 이상 없음(`docs/sim/ATTACK_AUDIT.md`) |

체력을 크게 올린 뒤에도 실력 프로필 봇이 10일 전체를 완주했고, **전투 시간만 40% 늘었다.**
반면 회차 봇(balanced 정책)은 시드 16개를 훑어도 완주하지 못한다. 두 봇의 차이는 조작 수준이며, 난이도 판단이 아니다.

### 23-6. 남은 것

- 타격감(적중 점멸·방향성 효과·소리·사망 반응), 랜덤 지형, 막별 색감.
- 상점 새로고침·장비 역할 확장·강화, 100금 휴식권, 소모품 5종.
- 중력핵 측정과 시험안.
- 특수 정예 7종의 2·3막 실측(1막만 측정), 실제 출격 편성 배치.
- 시뮬레이션 실행 효율, 아이콘 보강과 실제 속도 영상, 안드로이드 웹 실행.

## 24. 1차 정적 검토 반영과 체력 효과 재측정 (2026-09-08, Windows 로컬)

근거 문서(저장소 밖): `godot-ac22b74-report-review-20260908/REVIEW.md`. 검토자는 코드와 문서만 읽었고 게임·스위트를 다시 돌리지 않았다.
**검토 의견만으로 수치를 되돌리지 않았다.** 지적된 것은 측정 방법과 보고 표현이므로 그쪽을 고쳤다.

### 24-1. 지적 4건과 조치

| # | 지적 | 조치 |
|---|---|---|
| 1 | 성장 정책 우열의 결론이 측정 범위를 넘어섰다. A는 보조를 데이터 순서로 소진해 방어·제어·범위 투자의 가치가 드러나지 않는다 | 기존 A를 **'단일기술 고수'**로 이름을 바꾸고, **집중우선 정책 D**를 새로 넣었다(첫 기술 완성 → 생존·다수 처리 보조 → 둘째 기술). 상황도 DPS만이 아니라 **다수 처리 시간**과 **방어 투자 가치**를 따로 잰다 |
| 2 | 대장간 변경 효과까지 쟀다는 설명의 근거가 없다. 도구가 강화를 사지 않는다 | **같은 금화 조건**을 넣었다. 예산 단계마다 모든 정책에 같은 금화(90/250/490/490)와 같은 관문 수를 주고, 개방 조건·비용 단계를 그대로 따라 산다. 무강화와 나눠 표로 낸다 |
| 3 | 저프레임·일시정지 검사가 실제 입력 경로가 아니다 | `tools/attack_audit.gd`는 **가변 dt 스트레스**로 성격을 명시하고, 실제 경로 검증을 `tools/frame_path_audit.gd`로 새로 만들었다. 화면이 쓰는 `PStepDriver.frame()`으로 120·20·8프레임과 일시정지·재개를 돌린다 |
| 4 | "1010개 검사 전부 통과"와 "종료 실패 1건"이 같은 줄에 있다 | 실행기 요약이 **단언 통과 / 정상 종료 스위트 / 종료 실패**를 따로 센다. 세 값을 합쳐 "전부 통과"라고 쓰지 않는다 |

### 24-2. 실제 프레임 경로 검증 결과

같은 게임 시간(고정 단계 2400개)에서 프레임률만 바꿔 돌린 결과, 자동기술 10종 전부 **발사 수가 늘지 않았다**.
일시정지 → 재개 뒤 몰아 발사되는 현상도 없고, 대기 중인 누름이 두 번 소비되지도 않았다.

처음 측정에서 검(1.80 → 1.85/초)과 구슬이 늘어난 것처럼 보였는데, **그것은 측정 잘못이었다.**
`t >= 20초`로 멈추면 저프레임에서 한 프레임이 여러 단계를 몰아 처리해 진행한 게임 시간이 조금씩 길어진다.
고정 단계 수를 맞추자 차이가 사라졌다. 이 과정을 남겨 둔다 — **개수 비교는 진행 시간을 정확히 맞춘 뒤에만 유효하다.**

다만 이것은 "사용자가 본 두 발 현상의 원인을 확정했다"는 뜻이 아니다. 원인 후보는 개조가 만드는 다중 장판이며, 사람 화면 확인이 남아 있다.

### 24-3. 체력 상향의 실제 효과 (전투 시간 말고)

`PROPHECY_PACING=counts`(적 수·편성은 같고 체력 오버레이만 끈 상태) 대 현재. 표 전체는 `docs/sim/HP_EFFECT.md`.

**적이 살아서 공격하는가**

| 날짜 | 정책 | 공격 준비(전→후) | 공격 실행(전→후) | 준비 전 사망(전→후) |
|---:|---|---|---|---|
| 5 | 추적·공격 | 30 → 45 | 6 → **25** | 20 → 13 |
| 5 | 제자리 | 27 → 22 | 14 → 12 | 33 → **16** |
| 9 | 추적·공격 | 21 → 29 | 3 → **13** | 35 → 32 |
| 9 | 회피 우선 | 25 → 43 | 18 → **31** | 41 → 35 |

**정지와 회피의 차이가 생겼다** (20초 받은 피해)

| 날짜 | 조건 | 제자리 | 추적·공격 | 회피 우선 |
|---:|---|---:|---:|---:|
| 5 | 전 | 100 | 39 | **5** |
| 5 | 후 | 100 | 91 | **34** |
| 9 | 전 | 158 | 44 | **6** |
| 9 | 후 | 160 | 96 | **22** |

제자리는 전후 모두 최대 체력을 다 잃는다(사망). 달라진 것은 **움직이는 쪽**이다. 회피 정책이 이제 실제로 맞는다(5 → 34, 6 → 22).
그러면서도 제자리(100·160)보다는 훨씬 적게 맞는다 — "예고를 읽고 움직이면 피할 수 있다"에 가까워졌다.

**연속 출격 3회의 잔여 체력**은 대부분 2회째에 0이 된다(회복 없이 이어 나간 값).
휴식과 추가 탐험 사이의 선택이 생겼는지, 아니면 너무 가혹한지는 **사람 판단 항목**이다. 봇 결과로 확정하지 않는다.

### 24-4. 검증 표기 (셋을 따로 센다)

| 항목 | 값 |
|---|---|
| 단언(검사) 통과 | **1105 / 1105** |
| 정상 종료한 스위트 | **23 / 23** |
| 검사는 통과했으나 종료 실패 | **0** (KD-1은 열린 채로 추적) |

이전 보고의 "1010개 검사 전부 통과"는 같은 줄에 종료 실패 1건이 병기돼 있었다. 이제 실행기 요약이 셋을 나눠 적는다.

### 24-5. 아직 하지 않은 것

- 랜덤 지형, 중력핵 측정과 시험안.
- ~~특수 정예 7종의 2·3막 실측과 실제 출격 편성 배치~~ → **§25에서 완료.**
- 시뮬레이션 실행 효율, 아이콘 보강과 실제 속도 영상, 안드로이드 웹 실행.

---

## 25. 특수 정예 7종의 실제 편성 배치와 2·3막 측정 (2026-09-08, Windows 로컬)

§24-5에 "아직 하지 않은 것"으로 남겼던 항목이다. 규칙과 1막 값은 있었지만 **어느 편성에도 들어가 있지
않아 게임에서 만날 수 없었다**(`data/themes.json`의 정예 자리는 전부 늑대 우두머리로 고정돼 있었다).

### 25-1. 붙인 자리 (마리 수는 건드리지 않았다)

`PRun.template_waves`가 읽던 `tpl.get("elite_type", "wolf_alpha")`를 `PRun.elite_types_for`로 넓혔다.

| 템플릿 필드 | 뜻 |
|---|---|
| `elite_type` | 기본 정예 1종 |
| `elite_type_p2` | 비용 2칸(큰 보상) 장소와 **더 깊이 탐험**에서 쓰는 더 강한 정예 |
| `elite_types` | 정예 2마리 이상일 때의 조합(3막 위험 편성) |

정예를 쓰는 편성 12개에 종류를 지정했다. **`elites`(마리 수)는 어느 편성도 바꾸지 않았다** —
사용자 지시 "정예를 넣는다고 예산이 늘면 안 된다"를 구조로 보장하기 위해서다. 자세한 표는 `docs/ELITES.md` §10.

배치 규칙: ① 1막은 위험 편성에만 ② 평범한 편성은 27개 중 3개(11%)만 ③ 큰 보상 장소·더 깊이는
'강한 정예 1 + 호위' ④ 3막 고위험은 서로 다른 두 종류 ⑤ `acts`·`avoid_with`·`requires_allies` 준수.

### 25-2. 더 깊이 탐험 규칙 변경 (테마 장소만)

예전에는 웨이브의 **모든** 묶음에 +1을 해서 정예가 있는 편성이면 정예도 2마리가 됐다.
이제 테마 장소에서는 **호위만 +1** 하고 정예 수는 막별 상한(`data/elites.json placement.max_elites_per_fight`
= 1/1/2)을 넘지 않는다. 대신 종류가 `elite_type_p2`의 더 강한 정예로 바뀐다.
옛 지역 일정(`PROPHECY_LEGACY_PLACES`) 경로는 **한 줄도 바꾸지 않았다**(기존 회귀 보존).

### 25-3. 사전 표시와 추가 보상 (중복 지급 없음)

- 카드 표시 규칙은 `PSortie.elite_notice`에 두고 화면(`base.gd`)은 그리기만 한다. 실제 편성
  (`PRun.encounter_waves`)에서 세므로 표시와 실제가 어긋날 수 없다.
  예: `강적 출현 · 역병 조율사 · 보상 금화 +18`
- 추가 보상은 `data/pacing.json elite_reward` — 정예를 **실제로 잡았을 때만** 조우 1회에 1번,
  막별 15/25/40(금화 감축 ×0.7 뒤 11/18/28).
- **중복 금지**: 이미 '정예 처치 조건부 재료'(송곳니)를 주는 장소(`t1a_core`·`t3b_domain`)에는 주지 않는다.
  더 깊이 배율·위험 조건 배율도 곱하지 않는다(그 배율은 기존 전리품에 이미 붙어 있다).

### 25-4. 경험치 예산을 종류에 무관하게 만들었다

`data/growth.json`의 정예 7종 `XP_VALUE`를 32 → **30**(늑대 우두머리와 같은 값)으로 내렸다.
전투 경험치 예산은 `Σ 종류별 단위값 × ref`이므로, 이 값이 같아야 편성의 정예 종류를 바꿔도
예산이 흔들리지 않는다. 검사로 고정했다.

### 25-5. 부분 실행 도구 (`tools/subset.gd`, `PSubset`)

큰 측정을 통째로 돌리기 전에 **바꾼 것만 작게** 확인하기 위한 것이다. 없어서 새로 만들었다.

```
PROPHECY_SUBSET="act=2;elite=elite_miner,elite_archer;mode=single" \
  python tools/run_suites.py --suites elite_placement_measure --jobs 1
# → docs/sim/ELITE_PLACEMENT_PARTIAL.md
```

- `sub.pick("축", 목록)`으로 축을 줄이고, `sub.describe(...)`가 보고서 머리에 "부분 실행 — act 1/2 · elite 2/7"을 적는다.
- 부분 실행이면 결과 파일 이름에 `_PARTIAL`이 붙어 **전체 결과 파일을 덮어쓰지 않는다.**
- 목록에 없는 값만 지정해 남는 값이 0이 되면 전체를 쓴다(조용히 0회 실행하고 통과로 보이는 것을 막는다).

이번 작업에서 실제로 썼다: 1차 측정에서 균열 채굴자만 연계 완주가 1회였는데, 배치를 바꾼 뒤
**바뀐 두 자리만** 부분 실행으로 확인하고(6회 실행, 수십 초) 그 다음 전체를 다시 돌렸다.

### 25-6. 측정 (2·3막, 실제 편성 안)

`tests/elite_placement_measure.gd` — 편성을 손으로 만들지 않고 `data/themes.json` →
`PRun.formation_waves` → `PFlow.encounter_opts`라는 실제 경로를 그대로 지난다.
공격자별 피해는 `CombatState.recorder` 자리에 꽂은 기록기로 나눠 센다(같은 전투의 일반 적과 섞이지 않는다).

| 확인 | 결과 |
|---|---|
| 맞기 전에 녹아 사라진 정예 | **없다**(18자리 전부에서 살아서 공격을 실행) |
| 고유 연계 2회 이상 완주 | **18자리 전부 충족** |
| 2막 처치 시간 | 8.9 ~ 32.5초(중앙값 22초 근처) |
| 3막 처치 시간 | 11.4 ~ 58.6초 |
| 3막 정예 2마리 | 전투가 5~17초 길어지고 동시 생존 정예는 정확히 2 → **그대로 둔다** |

전체 표는 `docs/sim/ELITE_PLACEMENT.md`, 요약은 `docs/ELITES.md` §12.
**봇 승패는 통과 조건으로 쓰지 않았다.**

### 25-7. 검사

`tests/elites_tests.gd`에 배치 회귀 22개를 더했다(47 → **69개**). 무엇을 고정했는가:

- 정예를 쓰는 편성 12개가 모두 종류를 지정하고, 그 종류가 **실제 웨이브에 그 수만큼** 들어간다.
- 2막·3막 모두 7종이 전부 실제 편성 안에 있다.
- `acts`·`avoid_with`·`requires_allies` 위반 없음. 1막 일반 편성 정예 0. 일반 편성 27개 중 3개 이하.
- **총 등장 수·경험치 예산이 배치 전(늑대 우두머리)과 같다**(편성×장소×3일자 전수 비교).
- 큰 보상 장소의 정예가 1칸 장소보다 약하지 않다. 더 깊이는 막별 상한 + 호위만 +1.
- 추가 보상이 조우 1회에 1번, 송곳니 장소에는 없음, 더 깊이 배율이 곱해지지 않음.
- 출격 카드 사전 표시가 실제 편성과 정확히 일치.

### 25-8. 담당 밖에 남긴 것

- `scripts/game/render.gd`: 정예 7종 전용 그림이 아직 없다(기본 원 + 이름으로 그려진다).
- `scripts/rules/observe.gd`: `threats_of()`에 정예 7종 항목이 없어 실력 프로필 봇이 정예 예고를 못 본다.
- 군단 기수는 처치가 빠르다(2막 14.3초 / 3막 11.4초). 체력이 아니라 깃발 수명·명령 예산 문제로 보이며 사람 판단 항목이다.
- 사슬 집행자는 3막에서 가장 오래 버틴다(45.9~58.6초). 3막 성채가 길게 느껴질 수 있어 조정 후보로 적어 둔다.
## 26. 랜덤 지형(사용자 요구 7)과 KD-3 닫기 (2026-09-08, Windows 로컬)

사용자 요구: **"랜덤 맵/지형 가능성. 밀도 편차 과다·고립·막힌 목표·불공정 배치 방지 필요."**
전장을 통째로 새로 만들지 않았다. **검증된 전장 뼈대 + 장애물 후보 자리 추첨**이다.

### 25-1. 무엇을 만들었나

| 파일 | 내용 |
|---|---|
| `scripts/rules/terrain.gd` (`PTerrain`) | 생성기 + 검사기. 뼈대 위에 후보 자리를 **좌우 대칭 쌍**으로 추첨해 더하고, 조건을 어기면 최대 12회 재추첨 뒤 뼈대로 복귀 |
| `scripts/rules/combat_state.gd` | `_setup_terrain()` 연결(장애물이 정해진 **뒤에** 목표가 놓인다), `terrain` 필드(배치 저장), 시작 위치 읽기 수정(KD-3) |
| `data/themes.json` | 경기장 14곳의 시작 위치 키 `player` → `playerStart`(좌표는 그대로) |
| `tools/subset.gd` (`PSubset`) | **부분 실행** 공용 도우미. 축(시드·전장)을 환경 변수로 자르고, 잘렸으면 보고서를 `_PARTIAL.md`로 돌린다 |
| `tests/terrain_tests.gd` | 검사 25건(아래) |
| `tools/terrain_report.gd` | 측정표 → `docs/TERRAIN_REPORT.md` |

**기본은 꺼짐이다.** `PROPHECY_TERRAIN=1` 또는 조우 옵션 `terrain_random: true`로만 켜진다.
따라서 지금까지의 기준값·측정은 모두 그대로다(승인된 첫 전투 44행 결과 열 동일 — 25-4).

### 25-2. 요구된 안전 조건과 지킨 방법

| 요구 | 방법 | 실측(전장 17 × 시드 12 = 204개) |
|---|---|---|
| 개수·면적 상한/하한 | 3~10개, 1.2~8.0% | 개수 4~10, 면적 1.71~7.14% |
| 통로 폭 > 플레이어 지름 28px | 두 장애물·장애물과 벽 사이 44px 이상(정확값), 격자로도 36px 이상 | 최소 틈 **44.2px**, 격자 통로 폭 최소 **77px**, 벽 틈 최소 66.0px |
| 시작 지점 여유·장애물 안 금지 | 표면까지 70px 이상 | 최소 **97.9px** |
| 적 등장 지점 여유 | 새 장애물 표면까지 46px 이상 + 등장 지점 8곳이 시작 지점과 이어짐 | 어긋난 배치 0건 |
| 목표(봉인·제단·우리·출구) 도달 | 자유 공간이 하나로 이어지게 강제(고립 ≥99.5%). 실제 목표 전투 상태로 **153곳** 확인 | 못 닿는 곳 0, 장애물과 겹친 곳 0, 이어짐 실측 **100.0%** |
| 적 접근 경로 | 등장 지점 8곳에서 실제 조향·이동 규칙(`steer_dir`·`move_swept`)으로 15초 접근 | 최종 거리 최대 **2.0px**(전 전장·전 지점 도달) |
| 파괴되는 지형 | 장애물 하나씩 빼고 다시 검사 | 고립·도달이 나빠진 경우 0건 |
| 정예 돌무더기(균열 채굴자) | 돌무더기는 `st.obstacles`가 아니라 구조물이라 플레이어를 막지 않고 스스로 탈출로 검사를 한다. 놓을 자리 여유를 별도로 잰다 | 반지름 22로 설 수 있는 칸 비율 최소 **0.69** |
| 유한 재추첨 + 안전 기본 배치 | 12회 뒤 뼈대 그대로 | 204개 전부 **1회**에 성공(뼈대 복귀 0건) |
| 보스 전장 별도 | 보스 조우는 아예 제외 | 보스 전장 장애물 수 = 뼈대와 동일 |
| 같은 시드 재현 | 시드 = 전투 시드 ⊕ 전장 이름, 결과를 `st.terrain`에 저장하고 옵션 `terrain`으로 복원 | 같은 시드 12/12 동일, 시드 12개 → 서로 다른 배치 12개 |
| 장식용 난수가 전투 난수를 소비하지 않음 | 지형 전용 `PRng` | 켠 상태/끈 상태에서 `st.rng` 앞 8개 값 **동일** |
| 승인된 기준 전투 고정 지형 | `first_fight`은 아예 제외 | 장애물 4개 그대로, `terrain` 없음 |

### 25-3. KD-3(시작 위치) 닫음

`data/themes.json`은 키가 `player`, `combat_state.gd`는 `playerStart`를 읽어 **테마 경기장 14곳 전부** 기본값(480,300)으로 시작했고 그중 5곳은 그 자리가 바위 안이었다.
키를 `playerStart`로 맞추고(좌표는 그대로) 읽는 쪽이 `player`도 받아 주게 했다. 결과: 14곳 전부 의도한 좌표를 쓰고, 겹침 **5곳 → 0곳**.
`tests/ui_flow_tests.gd`의 "알려진 5곳보다 늘지 않음" 검사를 **0곳**으로 조였다. 자세한 것은 `docs/KNOWN_DEFECTS.md` KD-3.

### 25-4. 검증

| 항목 | 결과 |
|---|---|
| `terrain_tests` | **25/25 PASS**(전장 17 × 시드 12, 51~53초). 부분 실행 `PROPHECY_QUICK=1`에서도 25/25 |
| 랜덤 지형을 **켜고** 실제 화면 흐름 | `PROPHECY_TERRAIN=1 PROPHECY_LEGACY_PLACES=1`로 `ui_flow_tests` → **38/38 PASS**. `PFlow.make_encounter` 경로에서 지형이 추첨되어도 테마 경기장 14곳 전부 시작 겹침 0px·8방향 걷기·화면 이동이 그대로다 |
| 회귀 `run_tests,collision_tests,theme_tests,ui_flow_tests,world_tests,terrain_tests --jobs 1`(2회) | 검사는 매번 전부 통과. 1회차는 `theme_tests`(28/28)·`world_tests`(34/34), 2회차는 `theme_tests`만 **통과 뒤 프로세스 접근 위반**(KD-1). 단독 재실행은 둘 다 종료 0 — KD-1 표에 기록 |
| 승인된 기준 전투 보존 | `PROPHECY_COLLISION_LEGACY=1`로 `tools/density_report.gd` 재생성 → `docs/DENSITY_REPORT.md` **44행 전부 결과 열 동일**. 마지막 `시뮬 µs/단계` 열만 달라져(기계 성능) 되돌렸다 |

### 25-5. 부분 실행(PSubset)

`tools/subset.gd`(같은 날 다른 작업에서 만들어진 공용 도우미)를 **그대로 가져다 쓴다**. 축 이름은 `arena`·`seed`다.

| 환경 변수 | 뜻 |
|---|---|
| `PROPHECY_QUICK=1` | 전장 1곳 × 시드 1개(가장 작은 실행) |
| `PROPHECY_ONLY="arena:clearing,mine_tunnel;seed:1,3"` | 그 값만 |
| `PROPHECY_SKIP="arena:forest"` | 그 값을 뺀다 |
| `PROPHECY_LIMIT=8` | 조합 상한(측정 도구만. 검사 스위트는 쓰지 않는다 — 검사가 잘리면 통과 판정이 흐려진다) |

검사·보고서 첫 줄에 실행 범위가 남는다(`sub.describe(...)`). 부분 실행이면 보고서는 `PTerrain.report_path()`가 `docs/TERRAIN_REPORT_PARTIAL.md`로 돌린다 — 전체 결과 파일을 덮어쓰지 않는다.

**주의(담당 밖).** `tools/subset.gd`는 이 작업과 **다른 작업에서도 새로 만들고 있다**. 여기 있는 파일은 그쪽 원본을 **한 글자도 바꾸지 않고 복사**한 것이라 합칠 때 충돌이 없어야 하지만, 그쪽이 더 고치면 한 벌만 남기고 정리해야 한다.

### 25-6. 아직 하지 않은 것(사람 판단·담당 밖)

- **기본으로 켤지**는 사람 결정이다. 켜면 모든 일반 전투의 지형이 날짜·장소마다 달라지므로 밸런스 측정을 다시 잡아야 한다.
- 화면 확인(사람 눈)으로 새 장애물이 어색하지 않은지, 나무 가림(canopy)이 시야를 과하게 막지 않는지.
- 조우별 지형 시드를 저장에 남길지(`PSortie`·`PSave`). 지금은 전투 상태 안에만 있어 **같은 전투를 이어하기로 복원할 때** 지형이 시드에서 다시 만들어진다(같은 시드면 같은 결과라 실제 차이는 없다).
- 랜덤 지형을 켠 상태의 봇 승률·전투 시간 비교(밀도 편차) 측정.
- **`tools/subset.gd` 한 벌로 정리하기.** 같은 날 다른 작업도 이 파일을 만들고 있다. 여기 있는 것은 그쪽 원본을 그대로 복사한 것이라 합칠 때 충돌이 없어야 하지만, 그쪽이 더 고치면 확인이 필요하다.
- **실행기 잠금이 프로젝트 이름 기준이다.** 서로 다른 작업 폴더(worktree)에서 같은 스위트를 동시에 돌리면 `prophecy_godot__<스위트>.lock` 때문에 뒤쪽이 `config_error`로 끝난다(2026-09-08 21:41 `run_tests`에서 관측, 단독 재실행 통과). 잠금 이름에 프로젝트 경로를 넣는 것이 `tools/run_suites.py` 담당의 몫이다.

## 27. 중간 납품 빌드 (2026-09-08, godot-0.7.2 · 0274f51)

완료된 범위까지 **지금 플레이할 수 있는** 빌드다. 사람 판단이 필요한 시험값이 많이 들어 있으므로 최종 균형이 아니다.

| 대상 | 파일 | 크기 | SHA-256 앞 32 |
|---|---|---:|---|
| Windows | `prophecy_godot_build/prophecy_windows_godot-0.7.2_0274f51.zip` | 39.4 MB | `ef2cb3490cccd7e23c16b732f54f8957` |
| 웹(안드로이드 브라우저용) | `prophecy_godot_build/prophecy_web_godot-0.7.2_0274f51.zip` | 11.5 MB(펼치면 40 MB) | `bece4c18ffa087b9ea70454ffb4298a2` |

- Windows: 압축을 풀고 `prophecy.exe` 실행. 포장된 exe로 자동 진행을 돌려 **`UI_SMOKE result=done`·종료 0**을 확인했다.
- 웹: 정적 서버에 올려서 연다. `.wasm`에 `Content-Type: application/wasm`과 gzip 전송이 필요하고 COOP/COEP는 필요 없다. 자세한 절차·헤더·안드로이드 점검표는 `docs/WEB_BUILD.md`.
  **아직 배포하지 않았다.** 호스팅·도메인·자격 증명을 건드리지 않았고 확인은 `127.0.0.1`에서만 했다.
- 한글 글꼴은 저장소에 넣지 않았다(제3자 파일·라이선스는 사람이 정할 일). 웹에서 글자가 네모로 보이면 `docs/WEB_BUILD.md`의 글꼴 배치 절차를 따른다.

### 이 빌드에 들어간 것

전투 HUD 축소(Space/Q/E) · 일시정지의 '내 빌드' · 결과 화면 계속 버튼 · 남는 시간의 일반 탐험 ·
방패병 정면 85% · 특수 정예 7종과 **실제 편성 배치** · 봉인/제단 임무 수정 · 보스 엄폐·양갈래 수정 ·
성장 구조 변경(레벨 배율·개조 자격 Lv2/Lv4·기술별 대장간) · 체력 H3 · 타격감과 막별 색감 ·
상점 새로고침·잠금 · 출격 준비물 5종 · 회복약 · 100금 휴식권 · 랜덤 지형(기본 꺼짐, `PROPHECY_TERRAIN=1`).

### 아직 들어가지 않은 것

중력핵 시험안 · 아이콘 보강 · 실제 속도 영상(진행 중) · 새 성장 구조(주무기 1 + 공통 보조 2, 세부 설계 대기).
- 랜덤 지형, 중력핵 측정과 시험안. → **§25에서 중력핵 측정·시험안, 아이콘 보강, 실제 속도 영상을 했다.**
- 특수 정예 7종의 2·3막 실측과 실제 출격 편성 배치(1막만 측정, 배치표는 `data/elites.json`에 있다).
- 시뮬레이션 실행 효율, 안드로이드 웹 실행.

## 28. 중력핵 측정·시험안 · 아이콘 보강 · 실제 속도 영상 (2026-09-08, Windows 로컬)

### 25-1. 중력핵(요구 16): 재고 나서 골랐다

`scripts/rules/skills.gd`에 **읽기 전용 훅**(`PSkills.probe`, null이면 실행되지 않음)을 달아
사용·끌기·틱·붕괴·종료를 그대로 받아 적는 `tools/gravity_probe.gd`를 만들었다. 관측한 유효 피해 합계가
게임 통계(`st.metrics.dmg["skill:gravity"]`)와 소수점까지 일치하는 것으로 검산했다.
**간접 기여를 추정 피해로 만들어 총 피해에 더하지 않았다.**

한 번 눌렀을 때(레벨 2, 장면별 3전투): 회당 피해 23~40, 대상 2.5~4.8마리, **회당 처치 0.0~0.7**,
실제로 끌려 들어온 거리 33~52px(반지름은 140), 대상당 체류 0.69~0.98초(유지 1.2초를 못 채운다).
보스는 규칙대로 끌리지 않았고(계측상 0회) 피해만 들어갔다(1관문 회당 10.6).
2관문(수호자)은 봇이 E를 한 번도 누르지 않았다 — balanced 정책이 '200 안 2마리 이상'을 요구하는데 1대1 판이라 조건이 없다.

후보 4종을 같은 시드로 비교해 **폭발 마무리**(기본형도 끝날 때 피해 ×2.0, 반지름 100)를 시험안으로 골랐다.
회당 처치 0.24 → **0.59**, 회당 피해 31.1 → **47.9**, 보스 회당 피해 11.1 → **29.9**.
**제어력 강화는 측정으로 기각**했다(끌어당김 90 → 170에도 끌린 거리 49 → 55px, 회당 피해·체류는 오히려 감소).
표와 근거: `docs/sim/GRAVITY_PROBE.md`, `docs/sim/GRAVITY_TUNE_DECISION.md`. **시험값이며 승인이 아니다.**

측정 도구에는 **부분 실행**(`tools/subset.gd` PSubset)을 붙였다 — `PROPHECY_QUICK` / `PROPHECY_ONLY` / `PROPHECY_SKIP` / `PROPHECY_LIMIT`,
부분 실행이면 `docs/sim/GRAVITY_PROBE_PARTIAL.md`로 따로 나간다.

### 25-2. 아이콘: 임시 20종 → 표시 대상 101종 전부

`assets/icons/manifest_source.json`(도형 정본) + `tools/icon_gen.gd`(생성기)로 **81종을 새로 그렸다**.
외부에서 내려받지 않았고 전부 프로젝트 안의 벡터 도형이다. 중앙 매핑은 `data/icons.json` 그대로가 정본이며 생성기가 함께 갱신한다.
기존 20종의 그림 파일은 바이트까지 그대로다(줄 끝 개행만 맞춤).

우선순위대로 개조 24종 · E 기술 4종을 먼저, 그다음 변형 13 · 공용 8 · 패시브 8 · 장비 18 · 보상 6.
**누락 0.** 적용/누락 목록은 `docs/sim/ICON_COVERAGE.md`가 자동으로 다시 쓴다.

이름이 잘려 구별되지 않는 문제도 검사에 넣었다(`tests/hud_tests.gd`): 실제 칸 폭·글자 크기로 잘라 보고
같은 화면 묶음 안에서 두 줄까지 쓰면 이름이 서로 구별되는지, 개조 이름이 `…` 없이 다 들어가는지 확인한다.

### 25-3. 실제 속도 영상: 연속 프레임이 아니라 재생되는 파일

`PROPHECY_CLIP=<이름>`(`scripts/game/main.gd`)으로 장면만 고르고 Godot Movie Maker(`--write-movie … --fixed-fps 24`)로 찍었다.
**판정·수명·피해·시간 배율은 바꾸지 않았다.** 방패병 두 클립만 사람 입력 자리에 정해진 이동(`ClipBot`)을 넣는다.
12개 · 73초 · 약 102 MB. 용량 때문에 파일은 저장소에 넣지 않고(`.gitignore`) 위치·용량·명령을
`docs/captures/0.8.0_clips/README.md`에 적었다. 임의로 외부에 올리지 않았다.

## 29. 주무기·보조무기 분리 ①단계와 중간 플레이 빌드 (2026-09-08, godot-0.8.0 · 4a81754)

### 무엇을 했나

사용자가 확정한 새 슬롯 구조(주무기 1개 Lv5·개조 2 / 공통 보조 2개 각 Lv3·개조 1)를 규칙·저장·화면에 넣었다.
세부는 `docs/SUPPORT_WEAPONS.md`, 결정 요약은 저장소 루트 `docs/DESIGN_DECISIONS.md` D46.

- `data/supports.json` 새로 추가 — 역할표·슬롯 규칙·보조별 레벨 강화·**효과 발동 자격표**·제압 저항·새 보조 7종(impl:false).
  생성 파일 `data/weapons.json`은 손대지 않고 `PCatalog.weapons()`가 겹쳐 읽는다.
- `PGrowth`에 구조 표시(`structure`)와 역할별 상한. **표시가 없는 저장은 옛 구조로 읽어 그대로 마칠 수 있다.**
- `PSupport` 새로 추가 — 자격표를 읽는 유일한 관문, 제압 저항·둔화 바닥, 역할 지표 계측(`meter`).
- 보조 A조(`supports_a.gd`)·B조(`supports_b.gd`) 파일을 갈라 담당별 소유 범위를 정했다.
- `tools/combo_probe.gd` — 대표 조합 7개만 돌리는 부분 측정 도구(실행기 등록됨).

### 확인한 것

| 무엇 | 결과 |
|---|---|
| 10일 전체 UI 자동 진행 | `result=done` · missing 없음 · gate1 95초 / gate2 220초 / gate3 338초 / run_result 338초 / save_continue 96초(**실행 시작 후 누적 벽시계**) · 게임 속 전투 1820.9초 |
| 완주 시점 빌드 | 검 Lv4+개조 2 / 불씨 정령 Lv3+개조 1 / 회전 칼날 Lv3+개조 1 — 새 구조 그대로 |
| 포장된 exe | `UI_SMOKE result=done` · 종료 0 |
| 회차 전체 불변식 | 상점 교체·대장간 개조 변경·임무 보상을 포함해 상한 위반 0건(`tests/slots_tests.gd` 12절) |

### 중간 플레이 빌드

| 대상 | 파일 | 크기 | SHA-256 앞 32 |
|---|---|---:|---|
| Windows | `prophecy_godot_build/prophecy_windows_godot-0.8.0_4a81754.zip` | 38.1 MB | `f08ebb2229809044d60453f192c77e19` |
| 웹(안드로이드 브라우저용) | `prophecy_godot_build/prophecy_web_godot-0.8.0_4a81754.zip` | 11.6 MB | `f57cdebd4e5b6845290bfdf90a39197f` |

**아직 배포하지 않았다.** 호스팅·도메인·자격 증명을 건드리지 않았다.
웹 실행 절차·헤더·안드로이드 점검표는 `docs/WEB_BUILD.md`.
안드로이드는 **웹 내보내기 성공**까지만 확인했다 — PC 브라우저 실행과 실제 안드로이드 실행은 아직 아니다.

### 이 빌드에 아직 없는 것

새 보조 7종(추격 까마귀·수호 방울·잔영 분신·바람 정령·역병 나비·가시 갑각·도깨비 인형)과 그 개조 21개,
주무기 5종 구분(관통창 폭 축소·전투망치 착탄점 원형 범위), 포자 수정. 넷 다 별도 작업 공간에서 진행 중이다.

## 30. 새 구조 통합 빌드 (2026-09-09, godot-0.9.0 · 10e9d26)

**중간에 보존한 안정 빌드다.** 이후 작업이 끝나지 않아도 이 버전은 실행된다.

| 대상 | 파일 | 크기 | SHA-256 앞 32 |
|---|---|---:|---|
| Windows | `prophecy_godot_build/prophecy_windows_godot-0.9.0_10e9d26.zip` | 38.4 MB | `92c479b769645663f6492edf59900c5d` |
| 웹 | `prophecy_godot_build/prophecy_web_godot-0.9.0_10e9d26.zip` | 11.8 MB | `01ab078a86a1fd053c964b739de05ede` |

포장된 exe로 자동 진행 `result=done` · 종료 0 확인. **배포하지 않았다.**
안드로이드는 **웹 내보내기 성공**까지만이다 — PC 브라우저 실행과 실제 기기 실행은 아직 확인하지 않았다.

### 이 빌드에 들어간 것

주무기 5종 구분(창 폭 44→14 · 망치 착탄점 원형+경직 · 궁 근접 약화 · **쌍검 단일 대상 화력 검의 1.53배**) ·
보조 12종과 개조 36개 전부 · **번개 구체 기본 감전** · **도깨비 인형이 실제로 대신 맞음** ·
포자 접근·접촉 피해 수정 · **방패병 정면 70%** · 주술사 개편(강한 다친 아군 우선 치료 20% · 세 갈래 저주탄 · 저주 문양) ·
**사망 시 회차 종료와 부활 물약** · **판매가 = 구매액의 절반** · 휴식·판매 확인 창 ·
행동 중심 마을 UI(상세는 버튼으로만) · 승리 화면 단순화 · **종류별 동시 생존 상한을 동시 상한 비례로**.

### 아직 없는 것

보스 장애물 파괴(진행 중) · 신규 몬스터 3종과 일반 정예 확장 · 테마별 협공·분대 등장 ·
특수 정예 결투 전환 · 새 보조의 화면 표시(까마귀·분신·인형 몸체가 그려지지 않는다) · 실제 속도 영상.

## 31. 통합 완료 빌드 (2026-09-09, godot-1.0.0 · a482542)

담당 아홉 갈래(주무기·보조·포자·적 피드백·보스 파괴·사망 경제·마을 UI·시너지 검수·신규 몬스터·테마 협공·화면 표시·자체 교차 검수)를 통합했다.

| 대상 | 파일 | 크기 | SHA-256 앞 32 |
|---|---|---:|---|
| Windows | `prophecy_godot_build/prophecy_windows_godot-1.0.0_a482542.zip` | 38.5 MB | `d814bdcc4e4c71ef5ecf640b70967bd7` |
| 웹 | `prophecy_godot_build/prophecy_web_godot-1.0.0_a482542.zip` | 11.9 MB | `f7e22ffed9742ac5b628fcadd5e72e1d` |

**최종 검사: 단언 1674/1674 · 정상 종료 36/36 · 종료 실패 0**(`--group all --jobs 1`).
이번 실행에서 KD-1이 나오지 않았다는 뜻이지 **원인이 해결됐다는 뜻이 아니다.**

10일 전체 UI 경로 `result=done` · missing 없음 · 누적 벽시계 gate1 111 / gate2 199 / gate3 296초 · 게임 속 전투 1416.3초.
포장된 exe로도 `result=done` · 종료 0.

**배포하지 않았다.** 원격 push도 하지 않았다.
자세한 내용은 `docs/MORNING_REPORT.md`(완료·부분 완료·미구현·알려진 결함 표와 플레이 순서).

## 32. 마무리 통합 빌드 (2026-09-09, godot-1.1.0 · 2396eda)

1.0.0 뒤에 받은 지시(남은 확정 요구 · 마지막 날 부활 · 웹 한글 글꼴 · 시너지 연결표 ·
대표 조합 10개 · 전염 상한 비교)를 다섯 갈래로 나눠 진행하고 통합했다.
**새 콘텐츠를 늘리지 않았다** — 기존 구현의 마무리와 시너지 완성만이다.

| 대상 | 파일 | 크기 | SHA-256 |
|---|---|---:|---|
| Windows ZIP | `prophecy_godot_build/prophecy_windows_godot-1.1.0_2396eda.zip` | 39.6 MB | `6f5a093f4b187a465eb4a23176d135c2a3d273be010c9b2aeaa4d986bc6fa263` |
| Windows exe(압축 안) | `prophecy.exe` 113,444,616 B | — | `8d0254109d4a49da1d53b3dedd44f9408abbf894b87018a612ef83b8d696ced7` |
| 웹 ZIP | `prophecy_godot_build/prophecy_web_godot-1.1.0_2396eda.zip` | 13.2 MB | `129c07f99a295f3d1897df103aee32ad0de5278ee010ca9c0883e855fbf2a279` |
| 웹 `index.pck` | 4,278,520 B | — | `38ad4ae661deb6e4e6e0da21dd008087c5be9b6b1a4eb72c19c20ee5e03f7601` |
| 웹 `index.wasm` | 39,514,754 B | — | `fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0` |
| 웹 `index.js` | 279,815 B | — | `33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba` |
| 웹 `index.html` | 5,471 B | — | `7deedc5d2f28fbd662fbc56468d9d6bdc813ffff88f58b32350b1514a605bc61` |

**커밋: `2396eda` (전체 `2396eda…` — `git rev-parse HEAD`로 확인).** 브랜치 `claude/prophecy-action-prototype-hehbeo`.
**push 하지 않았고 배포하지도 않았다.** 확인은 전부 `127.0.0.1`.

### 검사 (분리 보고)

- **단언 통과 1886 / 1886** (`--group all --jobs 1`, 37개 스위트, 실패 0)
- **정상 종료 35 / 37**
- **종료 실패(KD-1) 2** — `ui_flow_tests`(73/73 뒤) · `prep_shop_tests`(42/42 뒤). 둘만 다시 돌리면 종료 0.
  **통과로 세지 않는다. KD-1은 열린 상태 그대로이며 이번 통합이 고친 것이 아니다.**
- `ui_smoke_full`(전체 10일 · 관문 3): 소스에서 `result=done` · missing 없음 · 누적 gate1 95 / gate2 162 / gate3 275초 · 게임 속 전투 1345.5초.
- **포장된 exe로도** 같은 환경 변수로 `result=done` · missing 없음 · **종료 0**(gate1 94 / gate2 159 / gate3 262초).

### 웹 한글 — 이 빌드에서 다시 눈으로 확인했다

`python tools/serve_web.py --dir ../prophecy_godot_build/web_2396eda --port 8793` (127.0.0.1 전용, 확인 뒤 껐다).
브라우저에서 **제목 → 주무기 선택 → 거점 → 전투 HUD**까지 눌러 들어가며 확인:

- 네모(□) **0개**. 제목 아래 `godot-1.1.0 · 시험 빌드(경험치 ×0.3)`와 `글꼴 Noto Sans KR · OFL 1.1` 고지가 보인다.
- 거점에 **`일반 탐험 · 1칸`** 영역이 자기 자리에 있고, 아직 못 나가는 이유를
  `일반 탐험 · 출격을 한 번 마치면 열립니다`로 적고 있다(KD-7을 고친 규칙이 화면에서도 그대로 돈다).
- 전투 HUD 한 줄(`전멸 · 남은 25 · 지금 0/12 · 대기 5 · 돌진 0/2`)과 기술 3칸(`회피 / 감속장 / 미보유`)이 한글로 나온다.
- **실제 안드로이드 기기 실행은 여전히 미검증**이다(기기 없음). 절차는 `docs/WEB_BUILD.md` §10.

### 이번 통합에서 고친 결함

| id | 무엇 |
|---|---|
| KD-7 | 목표 `clear` 카드가 완료되지 않아 **일반 탐험이 열리지 않고** 사건·이용권이 반복 지급됐다 |
| SM-2 | 유인 룬이 정예를 등급 저항 없이 끌어당겼다 |
| BP-2 | 바람의 `slows`가 서리의 `slows`와 뜻이 달랐다(적·프레임 vs 새로 걸린 횟수) |
| — | 부활 물약을 사람이 상점에서 살 수 없었다 |

자세한 항목별 처리는 `docs/FEEDBACK_TABLE.md` 9~11절.
