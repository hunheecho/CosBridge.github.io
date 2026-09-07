# 실력별 전투 봇·밸런스 측정 기반 (BOT_FRAMEWORK) — 공식 문서

작성 2026-09-07 (godot-0.5.0 위에 첫 납품). 지시문: 외부 `prophecy-bot-balance-framework-20260907.md`(Codex). 이 문서가 봇 규칙·관측 경계·프로필 값·통계/태그 정의·기록 형식·배치 사용법·보정 상태의 **한 곳**이다. 첫 비교 보고서: `docs/sim/BOT_COMPARE.md`. 회귀 검사: `tests/bot_tests.gd`.
2차(같은 날, observe-2): 신규 관문 보스 6종(`scripts/rules/boss3.gd`, `docs/BOSSES.md`)의 화면 예고·빙판·잔해·보스 투사체를 관측 경계에 추가(§2-1), 보스 6종 배치 시나리오·비교 보고서 `docs/sim/BOT_COMPARE_BOSS3.md`(§6), 회귀 검사 §12-11(43). 봇 규칙(§3)·프로필 값·게임 수치는 바꾸지 않았다.

**상태: 사람 보정 미완료.** novice/regular/skilled는 **가상 조작 모델**이며 실제 초보/평균/상위 플레이어 분포가 아니다. 어떤 수치도 사용자 승인값이 아니다. 게임 수치(회피 70~150·재사용 1.5초·무적·늑대 규칙·밀도·경험치)는 바꾸지 않았고, 기존 봇 정책(`bot.gd` stand/active/aggressive/balanced/survival/idle/aware/still)은 코드·동작 그대로다(D33 기준 전투 72/72, `tools/density_report.gd` 결과 열 동일).

## 1. 구성 요소

| 파일 | 역할 |
|---|---|
| `scripts/rules/observe.gd` (`PObserve`, observe-3) | CombatState → 화면에 그려지는 것만 담은 읽기 전용 스냅샷(깊은 복사). 위협 도형·attack_id·수정 번호(rev). observe-2 = 신규 보스 6종 예고·빙판·잔해 추가(§2-1) |
| `scripts/rules/skill_bot.gd` (`PSkillBot`, skillbot-0.1) | 실력 프로필 봇. `PBot`을 상속해 `step_input`만 덮어씀(PStepDriver·PBot.run_combat에 그대로 꽂힌다) |
| `data/bots.json` | 프로필 값(시험값)·공통 규칙·진단 성향 기본값. 보고서 머리말은 이 데이터에서 생성 |
| `scripts/rules/hit_recorder.gd` (`PHitRecorder`) | 선택 계측: 공격 관측·피격 사건·거절·검산·보호막 분리·피격 태그. `st.recorder = PHitRecorder.new()`로만 켜진다 |
| `scripts/rules/replay.gd` (`PReplay`, prophecy_replay/1) | 입력 기록·재생·주기 상태 해시·버전 거부·data/*.json 해시. 사람 경로는 `attach_recorder(driver)` |
| `tools/bot_batch.gd` → `tools/bot_batch_core.gd` (`PBotBatch`) | 배치 실행기: 시나리오 × 프로필 × seed, 증분 저장·재개·캐시 키·벽시계 예산·처리량 측정·보고서 |
| `combat_state.gd` 훅 | `recorder` 필드와 `on_step_begin/on_hit/on_reject/on_step_end` 호출(null이면 실행 안 됨), `note_attack(prepare)`의 `attack_n` 증가. `enemies.gd` 늑대 물기/돌진 준비 시작에 같은 `attack_n` 증가 1줄씩(규칙·난수 무관) |
| `step_driver.gd` 훅 | `recorder`(PReplay)가 있으면 단계마다 `note()`, `reset()`에 `mark("reset")` |
| `main.gd`·`screens/title.gd` | 검증 메뉴: 봇 프로필 선택(기존 정책/novice/regular/skilled), '이번 전투 입력 기록' 체크(사람 입력만, `user://recordings/`, 업로드 없음) |

## 2. 관측 경계 (봇에게 허용되는 정보)

`PObserve.snapshot(st)`/`take(st)`가 만드는 사전만 봇이 읽는다. 값은 전부 스칼라·문자열·새 컨테이너라 원본 참조가 없다(과거 스냅샷은 적이 방향을 바꿔도 변하지 않는다 — 검사 §12-3).

허용(화면에 실제로 그려지는 것):
- 적: id, 종류, 등급, 위치·반지름, 좌우 방향(`face_x`), 상태 이름(애니메이션으로 보이는 것), 체력 막대 비율, 정예/구조물/보스, 빈틈(노란색) 여부. **hidden(지하 잠복)·죽은 적은 없다.**
- 위협 도형(`threats`): render.gd `draw_telegraphs`/`draw_boss_telegraphs`/`draw_boss3_telegraphs`/`draw_zones`/`draw_projectiles`와 같은 수치. `kind` = sector(부채꼴: x,y,ang,r,half) · corridor(통로: x,y,ang,len,w) · circle(원: x,y,r) · lane(선 예고: x,y,ang,len,w — 화면의 선에는 폭이 없으므로 폭 40을 가정, PBot과 같은 값) · band(띠: 바깥 반지름 r, 안쪽 r−w, 각 ang±half — 포자 어미의 확산 중인 고리 전용, observe-2). `phase` = warn(추적/준비) · lock(확정: 색이 진해지고 '!'/굵은 테두리) · active(실행 중: 달리는 몸·유효 구간). `prog` = 그려지는 진행률(0~1, 알파/두께 변화의 근거). `shown_left` = 화면에 **글자로** 표시되는 남은 초(폭탄 운반체 "폭발 1.2s", 예언을 먹는 자 표식, 포자 탄·낙석 순번 옆 초, 사냥왕 "방향 고정 n초 뒤")만, 그 외 −1. `harm` = damage | slow(거미줄·거미줄 예고·빙판).
- 적 투사체: 위치·속도·반지름(진행 방향 220px 외삽 통로로도 제공 — 공개 정보의 제한적 외삽). 보스 볼트(`boss_bolt`)·얼음 탄(`boss_icebolt`)도 같은 규칙(발사한 공격의 부분 `e<id>#<n>:proj<i>`).
- 바닥 지역: 종류·위치·반지름·표시되는 생명 비율(life), 서리 순번, 제단/붕괴 위험의 예고/활성, 걷기 감속 배율(`slow`: 거미줄 0.5·빙판 0.6 — 화면 문구 "걷기 n%"·보스 설명값).
- 보스 방패/방어 자세(`boss.guard`, 위협 아님): 파수장 guard_aim/lock·집행관 guard 중 그려지는 정면 부채꼴(각·반각·반지름·경감률)과 집행관 자세의 글자 남은 초(`left`). 그려지지 않으면 `{}`.
- 목표물·회복 구슬·장애물·경기장 크기·등장 예고(화면의 `spawnwarn`/`pawwarn` 효과와 남은 시간).
- 자기 상태: 위치·체력·보호막·회피 재사용(HUD 막대)·회피 중·감속장/E 재사용·E 보유 여부.
- 조작 규칙(`rules`, 조작법 화면에 적힌 값): 회피 방식/최소·최대 거리/시간/재사용, 이동 속도, 자동기술 사거리(기술 설명상 성능).
- 보스 막대: 체력 비율·단계·상태 이름.

금지(스냅샷에 없음, 검사 §12-1이 숨은 값을 바꿔도 스냅샷·입력이 같음을 확인):
- 게임 난수 상태·다음 공격의 난수 결과, 아직 예고되지 않은 착탄 지점/방향(예: 서리술사가 시전을 시작하기 전의 위치, 표식이 찍히기 전의 과거 궤적), 숨은 적 좌표, 미등장 대기열(`pending`) 좌표/시간, 예고에 없는 내부 타이머(`dash_ready_at`·`bite_cd`·`dash_cd`·`ready_t`·`heal_t`·`web_t`·`cast_t`), 최종 충돌 결과, 규칙 엔진을 미리 실행해 얻은 정답, 화면에 없는 정확한 발동 시각(진행률 `prog`만 준다).

attack_id: `e<적 id>#<attack_n>`. `attack_n`은 공격 준비(예고)가 시작될 때 1 오른다(`note_attack("prepare")`, 늑대는 `update_wolf`의 물기/돌진 시작; 신규 보스는 `PBoss3.begin`). 한 공격의 부분은 접미사(`:lane1`, `:shock0`, `:mark2`, `:pt1`(서리 3점), `:s2`(도적 2타), `:proj0`(그 공격이 쏜 투사체 — **발사 순간** `CombatState.stamp_projectile`이 발사자의 그때 attack_n과 그 공격 안 순번을 투사체에 고정하며, 발사자가 다음 공격을 준비하거나 형제 투사체가 사라져도 바뀌지 않는다. 피격 기록도 발사 시점 공격에 붙는다(`st.hit_attack_id`). 검수 2 수정)). 지역은 `zone:<종류>:<x>:<y>`. 발사자가 없는 투사체는 추적기가 `proj:<n>`을 준다. `rev`는 그려지는 기하(각도 0.5°, 위치/길이 1px, 단계)가 바뀔 때만 오른다(추적 인스턴스 `take()`).

### 2-1. 신규 관문 보스 6종 관측표 (observe-2, `PObserve._boss3_threats` = render.gd `draw_boss3_telegraphs`)

경계는 그대로: 화면에 그려지는 도형·글자만. 굴착 계획의 "그 순간 플레이어 방향"은 고정 시점에 두 통로가 함께 그려지므로 그때부터만, 고리의 빈 구간 각은 준비 중 초록 부채꼴로 그려지므로 그 각(부채꼴 밖)으로, 착탄/낙하 시각은 화면 글자의 남은 초로만 준다. 난수·`land_at`·`burrow_plan`·`hit_done`·`wait_t`·`shot_timer`·`rubble_tick`·`guard_real`·`summon_budget` 같은 내부 필드 이름은 스냅샷에 없다(검사 §12-11p).

| 보스 | 화면 | attack_id 부분 | kind | phase | 수치(render와 동일) | shown_left |
|---|---|---|---|---|---|---|
| 성문 파수장 | 방패 자세 → 밀치기 | `e#n` label shove | sector | guard_aim warn(추적 각, prog st/0.8) → guard_lock lock | r 110, 반각 100°/2 | −1 |
| | 방패 정면 경감 부채꼴 | `boss.guard` | (위협 아님) | 자세 중만 | r 110+40, 반각 120°/2, reduce 0.4 | −1 |
| | 방패 돌파 | `e#n` breach | corridor | breach_aim warn(추적 각·`path_from` 길이) → breach_lock lock(`dash_len`) → breach active | 폭 (보스 r+플레이어 r)×2 | −1 |
| | 넓은 휩쓸기(2단계~) | `:sweep` bsweep | sector | bsweep_aim warn → bsweep_lock lock | r 150, 반각 200°/2 | −1 |
| | 석궁 3발 | `:bolt0~2` → 발사 뒤 `:proj0~2`(boss_bolt) | corridor → lane | bolts_aim warn → bolts_lock lock → 투사체 active | 0°·±18°, 길이 620, 폭 16+10; 투사체 폭 16+4·외삽 220 | −1 |
| 포자 어미 | 포자 탄 표식 | `:mark<순번>` shot<n> | circle | 남은 초 ≥0.4 warn, <0.4 lock(굵은 테두리·점멸), 착탄 뒤 사라지고 `zone:spore` active | 표시 자리, r 62, prog = 1 − 남은/1.0 | 남은 초(1.0→0) |
| | 포자 고리 준비/확정 | `e#n` ring | sector | ring_aim warn(prog st/0.9) → ring_lock lock | r 340, 각 = 빈 구간 반대편, 반각 = π − 빈 구간 반각(70°/2, 3단계 55°/2) | −1 |
| | 포자 고리 확산 | `e#n` ring | **band** | active | 바깥 r = ring_r + 22, 폭 44, 같은 각 범위 | −1 |
| | 분사 | `e#n` spray | sector | spray_aim warn → spray_lock lock | r 120, 반각 90°/2 | −1 |
| 굴착 거수 | 낙석 3구역 | `:rock<순번>` rock<n> | circle | 남은 초 ≥0.4 warn, <0.4 lock, 착지 뒤 `zone:rubble` active(잔해 r 72, damage) | r 72, prog = 1 − 남은/0.9 | 남은 초(0.9 / 1.4 / 1.9 → 0) |
| | 굴착 돌파 | `:burrow1`(+2단계 `:burrow2`) | corridor | burrow_aim warn → burrow_lock: 현재 경로 lock + 다음 경로 lock(첫 경로 끝에서, 옅게 그려짐) → burrow active | 길이 = 경로 길이(벽·장애물 끊김), 폭 (r+플레이어 r)×2 | −1 |
| 서리 추적자 | 얼음 발사 | `e#n` icebolt → `:proj0`(boss_icebolt) | corridor → lane | bolt_aim warn → bolt_lock lock → 투사체 active | 길이 640, 폭 18+10; 투사체 폭 18+4 | −1 |
| | 얼음길 3줄 | `:lane0~2` icepath<n> → `zone:ice` | corridor → circle(harm slow) | path_aim warn → path_lock lock → 빙판 active(slow 0.6, 걷기만) | 0°·±40°, 길이 420, 폭 70; 빙판 r 38 | −1 |
| | 옆 이동 → 돌진 | `e#n` dash | (없음) → corridor | sidestep: 예고 없음(몸만 이동) → dash_aim warn → dash_lock lock → dash active | 위와 같은 돌진 통로 | −1 |
| 핏빛 사냥왕 | 발톱 휩쓸기 | `e#n` claw | sector | claw_aim warn → claw_lock lock | r 170, 반각 170°/2 | −1 |
| | 추적 돌진 2회 | `:dash1`, 재조준 뒤 `:dash2` | corridor | dash_aim warn → dash_lock lock → dash active → dash_reaim warn(재조준 표식, 추적 각) → dash_relock lock → dash active | 돌진 통로 | 재조준 중 "방향 고정 n초 뒤"의 n(0.45→0), 그 외 −1 |
| 종말의 집행관 | 세로 절단선 2 | `:slash1`(붉은 실선), `:slash2`(보라 점선) | corridor | slash_warn warn(1번은 플레이어 x를 따라옴, prog st/0.8) → slash_lock lock → 1번 뒤 2번 slash_gap warn(x 고정, prog st/0.5) → lock | x = 선의 x, y = 0, 각 π/2, 길이 = 경기장 높이, 폭 80 | −1 |
| | 회전 방어 자세 | `boss.guard` | (위협 아님) | guard 중만 | 각 = face, 반각 110°/2, r 160, left = 자세 남은 초 | (left) |
| | 큰 베기 | `:strike` gstrike | sector | gstrike_aim warn → gstrike_lock lock | r 160, 반각 140°/2 | −1 |

넣지 않은 것: 절단 뒤 0.3초 잔상 효과 `slashline`·휩쓸기 잔상 `bosssweep`·착지 효과 `bossland`(피해가 끝난 뒤의 그림), 소환 `summon`(등장 예고 `pawwarn`으로 이미 있음), 고리 준비 중 돌진 통로의 알파(render는 1초에 걸쳐 짙어지고 prog는 준비 시간 비율 — 둘 다 공개 정보라 준비 시간 비율을 쓴다).

## 3. 봇 규칙 (PSkillBot)

흐름(매 고정 단계): `PObserve.take` → 지각 → (판단 간격마다) 판단 → 입력 `{mx,my,dodge_press,dodge_held,special,skill_e}`(사람과 같은 형식, 같은 `CombatState.step`).

지각:
- 새 attack_id를 처음 보면 인식 지연을 **봇 RNG**(`PRng.new(bot_seed)`, 게임 난수와 분리)에서 프로필 범위로 1회 표본화한다. 인식 전에는 그 위협 때문에 어떤 입력도 바꾸지 않는다. 인식 전에 사라진 위협(예고 중 사망)은 입력 없이 버린다.
- 인식한 위협은 **추적 갱신 지연**마다만 새 기하를 복사한다. 그 사이 봇이 아는 기하는 오래된 복사본이다(조준선이 갱신돼도 인식을 다시 시작하지 않는다).
- 같은 **공격 인스턴스**(`e<적 id>#<n>`)의 새 부분(조준선 `e5#2` → 날아가는 화살 `e5#2:proj0`, 2번째 직선 `:lane1`)만 이미 인식한 공격을 이어받는다. 서로 다른 지역(`zone:…`)·발사자 없는 투사체(`proj:…`)는 접두사가 같아도 독립 위험이라 각각 새 지연을 받는다(검수 2 지적 1 수정, skillbot-0.2; `_is_attack_instance`).
- `inside_first` = 그 위협이 처음으로 플레이어를 담은 단계(최초 입력 지연의 기준).

판단(프로필의 판단 간격마다, 그 사이에는 이동 입력만 유지):
1. 주의력: 인식한 위협을 공통 긴급도(안에 있음 +3, 단계 active 2/lock 1.5/warn 진행률, 도형까지 거리의 역수, slow는 ×0.3)로 정렬해 상위 N(`attention`)만 고려. 동률은 attack_id 순.
2. 반응 문턱(공통, 공개 정보만): 추적 중인 예고(warn)는 진행률 ≥ 0.4(`warn_react_prog`)일 때, 남은 초가 글자로 표시되는 예고(폭탄·표식)는 ≤ 0.9초(`shown_react_sec`)일 때만 '벗어날 위협'으로 본다. 그 전에는 접근을 계속한다(조준선은 플레이어를 따라오므로 항상 즉시 비키면 궁수에게 영원히 거리를 못 좁힌다 — 첫 실행에서 skilled가 능선 시나리오에서 정체(stalled)한 원인, 문턱 도입 뒤 재실행). 고려한 위협 중 플레이어를 담은(harm=damage, 안전 여유 6px) 것이 있으면 탈출: 후보 방향(`dodge_dirs`개, 균등) 각각을 10px 간격으로 최대 150px까지 훑어 고려한 위협 합집합 밖으로 나가는 가장 짧은 거리(`d_free`)를 구한다. 지형(경계·장애물, `PObserve.valid_pos`)에 먼저 막히는 후보는 제외. 동률은 끝점에서 가장 가까운 적까지 거리가 큰 쪽. 어느 방향도 못 벗어나면 가장 트인 방향.
3. 예고 잔여 추정(정확한 발동 시각은 없다): `shown_left`가 있으면 그 값, active 0, lock 0.15초, warn (1−prog)×0.6초. `d_free ≤ 이동속도×잔여×0.8`이면 **걸어서** 벗어난다. 아니면 회피 가능(회피 중 아님·재사용 표시가 판단 간격×0.5 이하)할 때 회피 누름, 불가능하면 걷는다.
4. 방향 오차: 판단당 1회 봇 RNG로 ±`angle_err_deg` 표본(매 단계 흔들지 않는다). 회피 방향은 게임 규칙대로 누른 순간의 이동 벡터로 고정된다.
5. 누름 길이: novice `press:"max"` = 끝날 때까지 유지. regular/skilled `"smart"` = `d_free ≤ 75` 짧음(누른 단계에 뗌 → 실제 최소 70), `≤ 115` 중간(110에 해당하는 시간 = ceil(110/(150/0.26)/STEP) 단계 유지), 그 외 김. **실제 거리는 게임 규칙(최소거리·충돌·최대거리·hold 방식)이 정한다.** 요청 종류와 결과 거리를 모두 기록한다.
6. 위협이 없으면 접근: 가장 가까운(보스 우선) 적에게 유지 거리(공전 칼날만이면 사거리×0.9, 보스는 빈틈이면 r+40 아니면 r+사거리×0.7)까지 조향(`PObserve.steer`, CombatState.steer_dir와 같은 접선 규칙을 스냅샷 지형에 적용), 너무 가까우면 물러남. 앞 30px가 고려 중인 활성 장판이면 비켜 간다.
7. Q/E(모든 프로필 동일): Q = 재사용 0이고 200 안 적 3 이상 또는 보스 180 안. E = 보유·재사용 0·200 안 적 2 이상(수호 결계는 위협이 없고 체력 70% 초과면 아낌). 자동 공격은 게임이 한다.

프로필 값(`data/bots.json`, 지시문 §5 시험값 그대로):

| 설정 | novice | regular | skilled |
|---|---:|---:|---:|
| 판단 간격 | 150ms(18단계) | 100ms(12) | 50ms(6) |
| 새 위협 인식 지연 | 350~550ms | 200~350ms | 120~220ms |
| 추적 갱신 지연 | 150ms | 100ms | 50ms |
| 고려 위험 수 | 2 | 4 | 8 |
| 회피 방향 후보 | 8 | 8 | 16 |
| 방향 오차 | ±15° | ±8° | ±3° |
| 누름 길이 | 최대거리 시도 | 짧음/중간/김 | 짧음/중간/김 |

진단 성향(`traits`, 기본 전부 꺼짐, `PSkillBot.new(id, seed, {"traits": {...}})`로 하나씩): `greedy_attack`(warn 단계엔 이동 안 함) · `nearest_only`(주의력 1) · `long_dodge`(항상 김) · `hoard_qe`(Q는 체력 50% 미만, E는 4마리 이상). 첫 비교에서는 쓰지 않았다.

기존 정책과의 차이: 기존 `balanced` 등은 CombatState/적 dict를 직접 읽고 예고 진행률(react_at)로 즉시 반응하며 반응 지연이 없다. 이번 비교에서 `balanced`는 **기준 행**으로만 실행했다(기존 정밀 정책, 최적·완벽 회피 증명 아님). `stand`/`active`는 D33 기준선(밀도 보고서)이며 건드리지 않았다.

지연 기록(`PSkillBot.latency_report()`): 판단 간격, 위협별 인식 지연(표본값), **실제 최초 입력 지연** = 위협이 나타난 뒤(예고 시작과 '플레이어를 담기 시작' 중 늦은 쪽) 봇이 그 위협 때문에 처음 입력을 바꾼 단계까지(ms), 누름 종류별 수, 봇 난수 소비 수.

## 4. 통계 계약 (PHitRecorder, §7) · 피격 태그 (§8)

- 전투 결과(배치 행): 상태 `won|lost|timeout|stalled|error|unimplemented`(시간초과는 그대로 남긴다; `stalled` = 처치·피해·체력 변화 없이 60초, 별도 상태), 시뮬 초, 벽시계 ms, 처치/전체, 레벨업, 공격 관측 수, HP 피해(유효/명목)·보호막 흡수·회복, 회피 횟수·거리 목록·차단·누름 시도/거절·회피!, Q/E, 최대 동시 적/예고/투사체/장판.
- 공격 관측(attack_id별, 화면 예고 기준): 예고 시작·고정(lock 또는 active가 처음 그려진 단계)·활성·종료 단계, 결과 `killed_during_telegraph`(예고 중 사망) / `cancelled`(실행 없이 종료: 멧돼지 통로 막힘, 시전 중단) / `executed` / `hit`(실행 + 이 공격에 귀속된 피격 ≥1). 실행 수는 적의 `executed`(+늑대 bites/dashes) 증가로 판정. 치료 시전·구조물은 예고가 없어 분모에 들어가지 않는다. 지역 피해(포자 구름·서리 폭발)는 `zone:*` id로 피격에 남고 공격의 hit에는 더하지 않는다(실행의 결과물).
- 피격 사건: step/t, 출처(src), attack_id, 명목(nominal), 경감 후 요청(requested), 보호막 흡수, 유효(실제 체력 감소), 과잉, 체력/보호막 전후, 회피 중 여부, 피격 보호 잔여, 회피 재사용 잔여, 마지막 입력, 그 순간 봇이 인식한 위협 목록, 태그.
- 거절된 타격: `dodge_invuln`(회피 무적) / `hit_protection` / `inactive`(사망·종료·입장) / `boss_dead` — 따로 세고 피해에 더하지 않는다.
- 검산: `최종 HP = 초기 HP + gained(회복·최대 체력 증가 등 단계별 설명되는 증가) − 유효 피해`, `unexplained`(설명 안 되는 감소)는 0이어야 한다. 과잉 피해는 유효에 넣지 않는다. 보호막은 부여(granted)/흡수(absorbed)/만료·덮어쓰기(expired)로 분리(단계별 차분).
- 출처별 준 피해는 `PStats.record/aggregate` 재사용(유효 피해, 보유 시간 DPS = 피해/보유 시간, 전체 DPS = 총피해/총전투시간). 기술별 DPS를 합쳐 런 DPS로 쓰지 않는다. 정산은 `stats_recorded`로 1회.

피격 태그(중복 허용, **당시 조건**이지 원인 확정이 아니다):

| 태그 | 조건 |
|---|---|
| `not_perceived` | 피격 순간 봇이 그 attack_id(또는 같은 공격의 부분)를 아직 인식하지 못함 |
| `perceived_no_input` | 인식했지만 인식 이후 이동 입력도 회피 누름도 없었음 |
| `dodge_rejected_cooldown` | 최근 0.5초 안에 재사용 중이라 거절된 회피 누름이 있음 |
| `dodge_blocked_terrain` | 최근 0.5초 안에 지형에 막혀 끝난 회피가 있음 |
| `after_dodge_025` | 회피 종료 뒤 0.25초 이내(시험 관찰 창) |
| `hit_by_other_while_escaping` | 봇이 벗어나려던 위협 A와 다른 공격 B에 피격 |
| `walking_out` | 벗어나려던 바로 그 위협 밖으로 걸어 나가던 중(회피 아님) 피격 |
| `overlap` | 마지막 판단에서 플레이어를 담은 고려 위협이 2개 이상 |
| `unclassified` | 위 어느 것도 아님 |

사람 입력(봇 문맥 없음)에는 `not_perceived`/`perceived_no_input`/`hit_by_other…`/`walking_out`/`overlap`을 붙이지 않는다. '다른 방향이면 피했다'·'회피 불가능'은 태그로 판정하지 않는다(재생 + 대안 입력 별도 검사, 그 결과를 봇에 공급하지 않는다). 회피 성공은 관찰 지표일 뿐 보상·성장 조건으로 쓰지 않는다(D04 유지).

## 5. 기록·재생 형식 (PReplay, `prophecy_replay/1`)

```
{ "format": "prophecy_replay/1",
  "header": { game_version, rules_version("rules@<game>/observe-1"), bot_version("human" | "skillbot-0.1/…" | "legacy:<정책>"), engine, os, commit(git HEAD, 배치가 기록; 없으면 "unknown"), dirty,
              data_hash(data/*.json 이름순 연결 SHA-256), scenario, build_fixture, game_seed, bot_seed, profile, step(1/120), hash_every(120), start_step },
  "inputs": [[단계 번호, {mx,my,dodge_press,dodge_held,special,skill_e}], …]   // 입력 사전이 바뀐 단계만(press true→false 전환도 자기 항목). mx/my는 var_to_str 문자열(17유효자리, 정확 복원; JSON 실수는 15자리라 재생이 갈라진다)
  "marks":  [[단계, "reset"], …]                                              // 일시정지·포커스 상실·재시작의 대기 입력 폐기
  "hashes": [[단계, sha256], …]                                               // 120단계마다 + 마지막: 플레이어 위치·체력·보호막·재사용·회피 중 + 살아 있는 적 id/종류/위치/체력/상태 + t·처치·유효 피해
  "result": { status, steps, t, hp, kills, damage_taken } }
```
`PReplay.replay(st, rec)`: 같은 초기 상태에 입력을 단계별로 넣고 같은 단계의 해시를 대조한다(`{ok, refused, reason, mismatches[], hash_checked, status}`). `check_header`가 형식·게임 버전·규칙 버전·(주어지면) 데이터 해시 불일치를 **명시적으로 거부**한다. 벽시계는 섞지 않는다. OS 간 일치는 검증하지 않았다(PORT_NOTES §11-3).
사람 경로: 제목 화면 검증 메뉴 '이번 전투 입력 기록'(기본 꺼짐) → 봇이 아닌 전투에서 `PStepDriver`가 단계마다 기록 → 전투 종료 시 `user://recordings/<시각>_<시나리오>.json`(로컬만, 업로드 없음, HUD·통계 변화 없음). 시나리오 id: `first_fight:<편성>:<회피방식><재사용>:dash<n>` · `lab_start:<무기>` · `lab_boss:<프리셋>` · `run:<지역>:day<n>`.

## 6. 배치 실행기 (`tools/bot_batch.gd`)

```
PROPHECY_BOT_RUN_ID=<id> [PROPHECY_BOT_MODE=compare|throughput|report] [PROPHECY_BOT_SCENARIOS=…] [PROPHECY_BOT_PROFILES=novice,regular,skilled,balanced]
[PROPHECY_BOT_SEEDS=1,2,3,4,5] [PROPHECY_BOT_BOSS_SEEDS=1,2,3] [PROPHECY_BOT_BOT_SEED=<정수|비움=게임 seed>] [PROPHECY_BOT_BUDGET_SEC=600] [PROPHECY_BOT_MAX_SEC=<초>]
[PROPHECY_BOT_SAMPLE=5] [PROPHECY_BOT_FORCE=1] [PROPHECY_BOT_REPORT=res://docs/sim/BOT_COMPARE.md]
godot --headless --path prophecy_godot -s tools/bot_batch.gd        # APPDATA 격리 권장(사람 저장·프로필과 분리)
```
- 시나리오(첫 납품): `baseline_wolf25`(D33 기준 전투, 상한 240초) · `ranged_mix`(능선 3일차 기본 편성, uniform_x5, 검 Lv1 고정 `fixed_build`) · `zone_mix`(습지 4일차) · `boss_thornmane|boss_guardian|boss_eater`(실험실 stage1/2/3 프리셋, 상한 300초, boss_sim make_run과 같은 절차). 만들 수 없으면 `unimplemented` 행.
- 시나리오(2차, 신규 보스 6종): `boss_warden|boss_matriarch`(1막, stage1 프리셋) · `boss_behemoth|boss_stalker`(2막, stage2) · `boss_hunt_king|boss_executor`(3막, stage3). 체력은 boss_sim과 같은 규칙(회차 모드에 없으면 `boss_hp_sets.hi[id].stage<막>` = 2400/5000/7000). `PROPHECY_BOT_SCENARIOS=boss3`가 6종으로 펼쳐지고, `PROPHECY_BOT_TITLE`로 보고서 제목을 준다. 보고서: `docs/sim/BOT_COMPARE_BOSS3.md`(run `boss3_compare1`).
- 출력 `docs/sim/bot_runs/<run_id>/`: `results.jsonl`(행마다 즉시 flush), `meta.json`(캐시 키: git HEAD·prophecy_godot 미커밋 여부·**코드 내용 해시**(`PReplay.code_hash`: scripts/tools/scenes의 .gd·.tscn + 최상위 .tscn + project.godot, .uid/.import 제외 — 미커밋 코드 변경·git 없는 ZIP도 구분, 검수 2 지적 3. 필수 폴더를 못 열거나 파일을 하나라도 못 읽으면 부분 해시 대신 `unknown`을 돌려주고 실패 경로를 `code_hash_failed()`·meta `env.code_hash_failed`에 남긴다 — 재검수 지적)·규칙 버전·관측 버전·데이터 해시·프로필 해시·설정 해시·엔진·OS·게임/봇 버전·기록 형식), `summary.md`, `git_head.txt`, `replays/`(실패 전부 + 성공 표본 1/5).
- 재개: 같은 run_id면 완료 행을 건너뛴다. 캐시 키가 다르면(옛 meta에 코드 해시가 없거나 코드 해시가 `unknown`이어서 식별할 수 없는 경우 포함) `CACHE_INVALID`를 찍고 종료 코드 2(재개 거부; `PROPHECY_BOT_FORCE=1`이면 기존 결과를 `results.invalidated_<시각>.jsonl`로 옮기고 새로). 벽시계 예산을 넘으면 현재 전투를 마친 뒤 `BUDGET_EXCEEDED`와 재개 방법을 찍고 종료 코드 3.
- 처리량(`throughput`): 기준 전투 10회 + 가시갈기 5회(regular)로 전투/분·평균 벽시계·최장 시뮬·최대 메모리·결과 파일 크기를 재고 45전투·보스 27전투 예상 시간을 찍는다.
- 병렬 실행은 run_id를 다르게(공유 폴더에 두 프로세스가 쓰지 않는다). 긴 프레임 로그는 run 폴더에만 두고 Git 문서에는 요약만.

## 7. 회귀 검사 (`tests/bot_tests.gd`, §12)

1 미래 정보 누출(숨은 난수·대기열·늑대 타이머 변경 → 같은 스냅샷·같은 입력) · 2 인식 지연 전후 입력 시점, 조준선 갱신에도 인식 시각 불변·기억 기하는 마지막 추적 갱신값, 인식 전 사망한 위협 폐기 · 3 스냅샷 격리 · 4 봇 seed와 편성/난수 독립 · 5 짧음/중간/김·지형 차단·재사용 거절·일시정지 뒤 재발동 방지(사람과 같은 `st.step`/`PStepDriver`) · 6 계측 켜짐/꺼짐 결과·난수·공격 순서 동일 · 7 검산(보호막 부여/흡수·회복·과잉·거절)·출처 합·보유시간 DPS·정산 1회 · 8 재생 해시 일치·JSON 왕복·버전 거부·변조 감지 · 9 배치 예산 중단→재개 중복 없음·캐시 무효화 · 10 실제 장면(main.tscn) 프로필 선택→시작→결과→재시작과 사람 경로 기록 저장 — **모두 함수 호출**(사람 입력·합성 키 이벤트 없음) · 11 신규 보스 6종 관측(11a~11o: 패턴마다 warn/lock/active 단계의 스냅샷 위협이 §2-1 표의 kind·phase·수치·attack_id 부분·shown_left와 같음, 띠(band) 안/빈 구간/지나간 안쪽 판정, 잔해·빙판 지역 이어짐, 방패 표시; 11p: 보스별 실력 봇 15초 전투에서 매 단계 숨은 값(난수·대기열·보스 타이머·소환 예산)을 바꿔도 스냅샷·입력 동일, 숨은 필드 이름 없음). 총 43.

## 8. 보정 상태·다음 단계

- **사람 보정 미완료.** 비교 기준은 사용자 긍정 평가를 받은 0.3.1 늑대25/동시12 전투(D33)지만 그 평가에는 반응 시간·승률 수치가 없으므로 임의로 넣지 않았다. 사람이 같은 조건으로 5~10회 플레이한 기록(입력 기록 체크)이 모이면 전투 시간·피해 출처·회피 빈도/거리·Q/E를 비교한다. 일부 기록은 조정에, 다른 기록은 확인에 쓴다. 한 전투의 피해 총량만 맞추려고 봇을 조정하지 않는다.
- 사람은 화면을 읽고 봇은 수치 관측(공개 도형을 수치로)을 받는 픽셀 인식이 아닌 모델이므로, 보정 뒤에도 가독성·피로·재미는 봇 결과로 확정하지 않는다.
- 게임 난이도 수치를 승률 목표에 자동으로 맞추는 루프는 없다. 보고서는 원인 후보·조정 대상만 적는다.
- 확장(지시문 §10 4~6): 무기 비교(창·칼날, 선택 횟수·개조·장비 명시), 9보스 동일 규격(신규 6종은 2차에서 추가, 아래), 전체 런(대표 경로부터). 시나리오 목록(`PBotBatch.SCENARIOS`)에 추가한다.

### 8-1. 신규 관문 보스 6종에 대한 범용 봇의 한계 (2차, `docs/sim/BOT_COMPARE_BOSS3.md`) — 사람 보정 미완료

관측(§2-1)을 넣은 뒤에도 봇 규칙(§3)은 그대로이므로 봇은 모든 위협을 "고려한 도형 합집합에서 가장 짧게 벗어나기"로만 다룬다. 보스별 설계 답(빈 구간 진입·줄 사이 통로·좌우 한 걸음·옆·뒤로 돌기)을 아는 특수 전략은 넣지 않았다(측정이 목적). 알려진 한계:
- 포자 고리: 준비 중 부채꼴(r340)은 150px 탐색 안에서 벗어날 수 없는 경우가 많아 "가장 트인 방향"(보스 반대쪽)으로 걷고, 확산 띠(250/s)가 따라잡는다. 빈 구간이 후보 방향 안에 우연히 들 때만 통과한다.
- 낙석: 세 원과 잔해를 한 도형 합집합으로 보므로 고려 위험 수(novice 2)가 모자라면 3번 원이나 잔해 위로 걸어 들어갈 수 있다. 출구 검사(≥4)는 게임 쪽 보장이고 봇은 그 방향을 고르지 않는다.
- 빙판: `harm=slow`라 긴급도가 낮고 회피 대상이 아니다. 봇은 빙판 위에서 그냥 60%로 걷는다(걸어서 벗어나기 판단이 기본 속도 기준이라 빙판 위에서는 늦을 수 있다 — 거미줄과 같은 기존 한계).
- 절단선: 세로 통로에서 좌우로 벗어나는 것은 범용 규칙으로 되지만, 2번 선이 1번이 떨어지는 순간 플레이어 x에 고정되므로 1번을 피한 자리가 곧 2번 자리다. 봇은 2번을 새 부분(`:slash2`)으로 이어받아 다시 벗어난다.
- 방패/방어 자세(`boss.guard`)는 스냅샷에 있지만 봇은 쓰지 않는다(옆·뒤로 돌아 공격하지 않음).
- 돌진 통로의 확정 뒤 "정확한 발동 시각"은 주지 않으므로(lock 잔여 추정 0.15초) 고정 0.3~0.4초 돌진은 회피 재사용 중이면 걸어서만 벗어난다.

## 9. 독립 검수 2(godot-audit-8dfcbd1) 수정 기록 (2026-09-07)
| 지적 | 수정 | 회귀 검사 |
|---|---|---|
| 1 서로 다른 장판이 같은 공격으로 인식돼 새 지연 생략 | `PSkillBot.perceive`: 부모 상속은 `e<id>#<n>` 꼴 공격 인스턴스의 부분에만. `zone:`·`proj:`는 각각 새 지연 | bot_tests 12a·12b·12b2 |
| 2 비행 중 투사체 식별자 변경 | 발사 시 `CombatState.stamp_projectile(e, pr)`(궁수·주술사·수호자 충격·신규 보스 fire), `PObserve._shooter_attack`은 찍힌 값만 사용(없으면 처음 본 순간 고정), 피격 기록은 `st.hit_attack_id`(발사 시점 공격) | bot_tests 12c~12f2 |
| 3 미커밋 코드 변경을 구분 못 하는 캐시 키 | `PReplay.code_hash` + 규칙/관측 버전을 캐시 키에, `PBotBatch.can_resume`(unknown이면 재개 거부), `cache_diff` | bot_tests 12g~12j |
수정 전후 같은 조건 비교: `docs/sim/BOT_COMPARE_AUDIT2.md`(run `audit2_before` = 8dfcbd1 worktree, `audit2_after` = 수정 커밋). 게임 수치·프로필 값 변경 없음. 기존 보고서 `BOT_COMPARE.md`·`BOT_COMPARE_BOSS3.md`는 수정 전(observe-1/2·skillbot-0.1) 결과이며 새 코드의 결과로 재사용하지 않는다. **사람 보정 미완료** 상태는 그대로다.

### 9-1. 재검수(godot-audit-427dae9) 잔여 1건
| 지적 | 수정 | 회귀 |
|---|---|---|
| 소스 일부 읽기 실패를 정상 코드 해시로 취급 | `code_hash_of`: 파일 하나라도 못 읽으면 `unknown` + 실패 경로(부분 해시 없음), `_collect_code`는 폴더 열기 실패를 false로 돌려주어 빈 폴더와 구분, 배치는 `CACHE_INVALID`에 실패 경로를 찍고 재개 거부 | bot_tests 12k~12n(누락 파일·빈 목록·폴더 열기 실패·정상 복귀), 잠금 파일 수동 확인(PORT_NOTES §20) |
게임 수치·봇 프로필 변경 없음. 108×2 비교는 다시 돌리지 않았다(해시 예외 처리만 바뀜).
