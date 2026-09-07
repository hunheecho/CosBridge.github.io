# 실력별 전투 봇·밸런스 측정 기반 (BOT_FRAMEWORK) — 공식 문서

작성 2026-09-07 (godot-0.5.0 위에 첫 납품). 지시문: 외부 `prophecy-bot-balance-framework-20260907.md`(Codex). 이 문서가 봇 규칙·관측 경계·프로필 값·통계/태그 정의·기록 형식·배치 사용법·보정 상태의 **한 곳**이다. 첫 비교 보고서: `docs/sim/BOT_COMPARE.md`. 회귀 검사: `tests/bot_tests.gd`.

**상태: 사람 보정 미완료.** novice/regular/skilled는 **가상 조작 모델**이며 실제 초보/평균/상위 플레이어 분포가 아니다. 어떤 수치도 사용자 승인값이 아니다. 게임 수치(회피 70~150·재사용 1.5초·무적·늑대 규칙·밀도·경험치)는 바꾸지 않았고, 기존 봇 정책(`bot.gd` stand/active/aggressive/balanced/survival/idle/aware/still)은 코드·동작 그대로다(D33 기준 전투 72/72, `tools/density_report.gd` 결과 열 동일).

## 1. 구성 요소

| 파일 | 역할 |
|---|---|
| `scripts/rules/observe.gd` (`PObserve`, observe-1) | CombatState → 화면에 그려지는 것만 담은 읽기 전용 스냅샷(깊은 복사). 위협 도형·attack_id·수정 번호(rev) |
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
- 위협 도형(`threats`): render.gd `draw_telegraphs`/`draw_boss_telegraphs`/`draw_zones`/`draw_projectiles`와 같은 수치. `kind` = sector(부채꼴: x,y,ang,r,half) · corridor(통로: x,y,ang,len,w) · circle(원: x,y,r) · lane(선 예고: x,y,ang,len,w — 화면의 선에는 폭이 없으므로 폭 40을 가정, PBot과 같은 값). `phase` = warn(추적/준비) · lock(확정: 색이 진해지고 '!'/굵은 테두리) · active(실행 중: 달리는 몸·유효 구간). `prog` = 그려지는 진행률(0~1, 알파/두께 변화의 근거). `shown_left` = 화면에 **글자로** 표시되는 남은 초(폭탄 운반체 "폭발 1.2s", 예언을 먹는 자 표식)만, 그 외 −1. `harm` = damage | slow(거미줄·거미줄 예고).
- 적 투사체: 위치·속도·반지름(진행 방향 220px 외삽 통로로도 제공 — 공개 정보의 제한적 외삽).
- 바닥 지역: 종류·위치·반지름·표시되는 생명 비율(life), 서리 순번, 제단/붕괴 위험의 예고/활성.
- 목표물·회복 구슬·장애물·경기장 크기·등장 예고(화면의 `spawnwarn`/`pawwarn` 효과와 남은 시간).
- 자기 상태: 위치·체력·보호막·회피 재사용(HUD 막대)·회피 중·감속장/E 재사용·E 보유 여부.
- 조작 규칙(`rules`, 조작법 화면에 적힌 값): 회피 방식/최소·최대 거리/시간/재사용, 이동 속도, 자동기술 사거리(기술 설명상 성능).
- 보스 막대: 체력 비율·단계·상태 이름.

금지(스냅샷에 없음, 검사 §12-1이 숨은 값을 바꿔도 스냅샷·입력이 같음을 확인):
- 게임 난수 상태·다음 공격의 난수 결과, 아직 예고되지 않은 착탄 지점/방향(예: 서리술사가 시전을 시작하기 전의 위치, 표식이 찍히기 전의 과거 궤적), 숨은 적 좌표, 미등장 대기열(`pending`) 좌표/시간, 예고에 없는 내부 타이머(`dash_ready_at`·`bite_cd`·`dash_cd`·`ready_t`·`heal_t`·`web_t`·`cast_t`), 최종 충돌 결과, 규칙 엔진을 미리 실행해 얻은 정답, 화면에 없는 정확한 발동 시각(진행률 `prog`만 준다).

attack_id: `e<적 id>#<attack_n>`. `attack_n`은 공격 준비(예고)가 시작될 때 1 오른다(`note_attack("prepare")`, 늑대는 `update_wolf`의 물기/돌진 시작). 한 공격의 부분은 접미사(`:lane1`, `:shock0`, `:mark2`, `:pt1`(서리 3점), `:s2`(도적 2타), `:proj0`(그 공격이 쏜 투사체)). 지역은 `zone:<종류>:<x>:<y>`. 발사자가 없는 투사체는 추적기가 `proj:<n>`을 준다. `rev`는 그려지는 기하(각도 0.5°, 위치/길이 1px, 단계)가 바뀔 때만 오른다(추적 인스턴스 `take()`).

## 3. 봇 규칙 (PSkillBot)

흐름(매 고정 단계): `PObserve.take` → 지각 → (판단 간격마다) 판단 → 입력 `{mx,my,dodge_press,dodge_held,special,skill_e}`(사람과 같은 형식, 같은 `CombatState.step`).

지각:
- 새 attack_id를 처음 보면 인식 지연을 **봇 RNG**(`PRng.new(bot_seed)`, 게임 난수와 분리)에서 프로필 범위로 1회 표본화한다. 인식 전에는 그 위협 때문에 어떤 입력도 바꾸지 않는다. 인식 전에 사라진 위협(예고 중 사망)은 입력 없이 버린다.
- 인식한 위협은 **추적 갱신 지연**마다만 새 기하를 복사한다. 그 사이 봇이 아는 기하는 오래된 복사본이다(조준선이 갱신돼도 인식을 다시 시작하지 않는다).
- 같은 공격의 새 부분(조준선 `e5#2` → 날아가는 화살 `e5#2:proj0`, 2번째 직선)은 이미 인식한 공격을 이어받는다.
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
- 출력 `docs/sim/bot_runs/<run_id>/`: `results.jsonl`(행마다 즉시 flush), `meta.json`(캐시 키: git HEAD·prophecy_godot 미커밋 여부·데이터 해시·프로필 해시·설정 해시·엔진·OS·게임/봇 버전·기록 형식), `summary.md`, `git_head.txt`, `replays/`(실패 전부 + 성공 표본 1/5).
- 재개: 같은 run_id면 완료 행을 건너뛴다. 캐시 키가 다르면 `CACHE_INVALID`를 찍고 종료 코드 2(재개 거부; `PROPHECY_BOT_FORCE=1`이면 기존 결과를 `results.invalidated_<시각>.jsonl`로 옮기고 새로). 벽시계 예산을 넘으면 현재 전투를 마친 뒤 `BUDGET_EXCEEDED`와 재개 방법을 찍고 종료 코드 3.
- 처리량(`throughput`): 기준 전투 10회 + 가시갈기 5회(regular)로 전투/분·평균 벽시계·최장 시뮬·최대 메모리·결과 파일 크기를 재고 45전투·보스 27전투 예상 시간을 찍는다.
- 병렬 실행은 run_id를 다르게(공유 폴더에 두 프로세스가 쓰지 않는다). 긴 프레임 로그는 run 폴더에만 두고 Git 문서에는 요약만.

## 7. 회귀 검사 (`tests/bot_tests.gd`, §12)

1 미래 정보 누출(숨은 난수·대기열·늑대 타이머 변경 → 같은 스냅샷·같은 입력) · 2 인식 지연 전후 입력 시점, 조준선 갱신에도 인식 시각 불변·기억 기하는 마지막 추적 갱신값, 인식 전 사망한 위협 폐기 · 3 스냅샷 격리 · 4 봇 seed와 편성/난수 독립 · 5 짧음/중간/김·지형 차단·재사용 거절·일시정지 뒤 재발동 방지(사람과 같은 `st.step`/`PStepDriver`) · 6 계측 켜짐/꺼짐 결과·난수·공격 순서 동일 · 7 검산(보호막 부여/흡수·회복·과잉·거절)·출처 합·보유시간 DPS·정산 1회 · 8 재생 해시 일치·JSON 왕복·버전 거부·변조 감지 · 9 배치 예산 중단→재개 중복 없음·캐시 무효화 · 10 실제 장면(main.tscn) 프로필 선택→시작→결과→재시작과 사람 경로 기록 저장 — **모두 함수 호출**(사람 입력·합성 키 이벤트 없음).

## 8. 보정 상태·다음 단계

- **사람 보정 미완료.** 비교 기준은 사용자 긍정 평가를 받은 0.3.1 늑대25/동시12 전투(D33)지만 그 평가에는 반응 시간·승률 수치가 없으므로 임의로 넣지 않았다. 사람이 같은 조건으로 5~10회 플레이한 기록(입력 기록 체크)이 모이면 전투 시간·피해 출처·회피 빈도/거리·Q/E를 비교한다. 일부 기록은 조정에, 다른 기록은 확인에 쓴다. 한 전투의 피해 총량만 맞추려고 봇을 조정하지 않는다.
- 사람은 화면을 읽고 봇은 수치 관측(공개 도형을 수치로)을 받는 픽셀 인식이 아닌 모델이므로, 보정 뒤에도 가독성·피로·재미는 봇 결과로 확정하지 않는다.
- 게임 난이도 수치를 승률 목표에 자동으로 맞추는 루프는 없다. 보고서는 원인 후보·조정 대상만 적는다.
- 확장(지시문 §10 4~6): 무기 비교(창·칼날, 선택 횟수·개조·장비 명시), 9보스 동일 규격, 전체 런(대표 경로부터). 시나리오 목록(`PBotBatch.SCENARIOS`)에 추가한다.
