# Godot 전체 이식 기준 명세 (이식 기준 진입 문서)

작성: 2026-09-07, Windows 로컬 세션(Claude 구현자). 이 문서는 "무엇을 정확히 옮기는지"의 기준점이며, 규칙 본문은 복제하지 않고 정본 위치를 연결한다. 항목별 대조는 `docs/CONTENT_MATRIX.md`.

## 1. 기준 커밋·환경
| 항목 | 값 |
|---|---|
| 저장소·브랜치 | `CosBridge.github.io` · `claude/prophecy-action-prototype-hehbeo` |
| 이식 착수 HEAD | 11c12cf (공유 문서 통합). Godot godot-0.3.1 = 2cb7ae6/8cad17f |
| HTML 비교 기준 | `prophecy_action_prototype` v0.8.0, 커밋 ee10fc7 (HTML 코드는 수정하지 않는다) |
| 독립 검수 기준 | HTML 7ec93cd 검수 F1~F8 (`docs/archives/2026-09-07_codex_shared_context/evidence/V080_AUDIT.md`), Godot 5093832 피해 통계 지적(0.3.1에서 수정) |
| 엔진 | Godot 4.7.2-stable 표준판(`C:\Users\hunhe\OneDrive\문서\바탕 화면\Godot_v4.7.2-stable_win64.exe\`). 내보내기 템플릿은 미설치 → 공식 4.7.2 템플릿 설치 후 빌드 |
| 미커밋 정리(보존) | 루트 index.html·CNAME·wash.jpg 삭제, export_presets company_name 비움, 편집기 재기록 project.godot·icon.svg.import |

## 2. 읽기 순서 (이 이식 작업의 세션)
1. `docs/PROJECT_CONTEXT.md` → `docs/DESIGN_DECISIONS.md`(D01~D36, 특히 D33·D34·D35) → `prophecy_action_prototype/docs/HANDOFF.md` 맨 위.
2. 이 문서 → `docs/CONTENT_MATRIX.md`.
3. 규칙 정본: Godot 첫 전투 `prophecy_godot/docs/RULES.md`(회피·늑대·밀도, 사용자 채택 D33), 전체 게임 `prophecy_action_prototype/docs/GAME_SPEC.md`(§3~§19), 수치 `ASSUMPTIONS.md`(양쪽), 카탈로그 = HTML `src/*_data.js`.
4. 구현 원본: HTML `src/combat.js·weapons.js·skills.js·enemies.js·boss.js·boss2.js·objectives.js·growth.js·run.js·sortie.js·flow.js·events.js·stats.js`, 테스트 `test/*.test.js`(170 케이스, 회귀 명세).

## 3. 자료별 권한 (충돌 시 우선순위)
1. **최신 명시적 사용자 결정** — D33(0.3.1 기준 전투 긍정), D34·D35(회피·늑대·밀도 시험값 채택), D06/D08(즉시 경험치·×0.3), D10(전멸), D17(패배), D18~D24(장비·상점 합의), 2026-09-07 이식 지시문(전체 범위·보존 항목).
2. **사용자에게 채택된 시험값** — 0.3.1 `first_fight.json`의 회피·늑대·편성 값. 조합 전체에 대한 채택이며 개별 값 확정은 아니다.
3. **구현자가 정한 값** — HTML `ASSUMPTIONS.md`의 임시값, Godot `ASSUMPTIONS.md`의 "시험값(구현자)". 근거가 있는 임시값.
4. **기존 코드(HTML ee10fc7)** — 실제 동작의 근거. 알려진 오류(F1~F8)와 폐기 규칙은 옮기지 않는다.
5. **테스트** — 특정 조건의 증거. 기대값을 구현 결과에서 베끼지 않는다.
6. **과거 문서/초안** — 이후 결정으로 대체됐을 수 있음(archives).

## 4. 이식 범위 요약 (개수는 CONTENT_MATRIX에서 개별 ID로 펼침)
- 자동기술 10종 + 전용 개조 30종, 공용 증강 9종, 패시브 8종, Q 감속장(Lv3·변형 3), E 5종(Lv3·변형 10), 보스 희귀 보상 4+범용 2.
- 몬스터: 기본 11종(늑대·궁수·포자·멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적) + 정예 늑대 우두머리 + 구조물 4(제단 3·봉인 장치) + 보스 3(가시갈기·봉인 수호자·예언을 먹는 자).
- 회차: 7일·시간대 5칸·장소 2곳/일·시간대 변주 9·날짜별 편성·임무 4종·위험 조건 3·사건 6·서비스 4·심층·패배·보스 관문 3(스냅샷 재도전)·희귀 보상.
- 경제: 장비 12종·상점(하루 재고·방문 상인)·대장간(강화 3단계·개조/변형 변경)·기술 교체·판매.
- 통계·저장: 출처별 유효 피해·DPS(보유 시간)·받은 피해(유효/명목)·보스 성공/실패 분리, `user://` 버전 저장·계속하기.
- UI·임시 그래픽·소리, F3 검증 패널·검증 시나리오, 전투 봇 6정책·회차 봇 7전략·시뮬레이션 도구, 테스트.
- 제외(합의 근거): HTML `single` 회차 모드(v0.7 이전 호환용), HTML 저장 호환, 시험실 전체 UI(핵심 기능은 F3·시나리오로 제공), 모바일 완성판, 정식 아트 대량 제작, 영구 해금(R-META-01 보류).

## 5. 구조 계획 (기존 Godot 구조 확장)
```
prophecy_godot/data/            숫자·카탈로그 JSON(HTML *_data.js에서 변환, 함수 값은 GDScript로)
  config.json        플레이어·전장·상수·FROST/EMBER/STASIS/FLARE/SAVING/MARK/CHEST/BARRIER
  weapons.json       자동기술 10 + 개조 30(이름·설명·수치·태그)
  growth.json        SLOTS·XP 곡선·XP_VALUE·지역 배율·보너스·가중치·COMMONS·PASSIVES·SKILLS·BOSS_REWARDS·REGION_TAGS
  enemies.json       기본 11 + 정예 + 구조물 + 보스 3 정의(색·체력·행동 수치)
  world.json         TIME_SLOTS·SCHEDULE·DAY_WAVES·SLOT_VARIANTS·MERCHANT_VISITS·EQUIPMENT·SHOP·REGIONS(보상)·MATERIALS
  missions.json      OBJECTIVES·STRUCTURES·SERVICES·MISSIONS·EVENTS(텍스트·수치)
  balance.json       BALANCE_SETS·BOSS_HP_SETS·DIFFICULTY·DAY_HP_SETS·ELITE_DAY_MULT·RUN_MODES(trio)
  first_fight.json   (유지) D33 기준 전투 = 검증 시나리오 "기준 전투"
scripts/rules/  (Node·Vector2·입력·그리기 없음, 고정 1/120)
  rng.gd geom.gd catalog.gd build.gd growth.gd combat_state.gd weapons.gd skills.gd enemies.gd boss.gd boss2.gd objectives.gd
  run.gd sortie.gd flow.gd events.gd stats.gd save.gd bot.gd run_bot.gd
scripts/game/   화면·입력·그리기·소리(규칙을 읽기만)
tests/ tools/   headless 규칙·통합·회차 시뮬레이션
```
- 사람·봇 동일 인터페이스: 전투 `{mx,my,dodge_press,dodge_held,special,skill_e}` / 회차 `Flow.actions(run)` → 선택 가능한 행동 목록(출격 카드·휴식·하루 종료·상점·보스 입장…)을 UI와 회차 봇이 같이 쓴다(F1 재발 방지).
- 피해 출처 키: `weapon:<id>`·`dot:<kind>@<weapon>`(F4 수정)·`skill:q|<e>`·`common:<id>`·`reward:<id>`. 받은 피해는 유효/명목 분리(0.3.1 유지).
- 편성 모델: 0.3.0 밀도 모델(전체 수·동시 상한·묶음·간격)을 일반화. 날짜·지역·시간대 편성(HTML DAY_WAVES)은 종류별 전체 수로 변환하고 역할별 동시 상한을 둔다(§6 C4).

## 6. 충돌·미확정 목록 (근거·플레이 차이·처리)
| ID | 충돌/공백 | 근거 위치 | 플레이 차이 | 처리 |
|---|---|---|---|---|
| C1 | 회피: HTML 고정 150·종료 후 0.9 vs Godot 70~150·출발 후 1.5 | GAME_SPEC §3.3 vs RULES §회피, D34 | 회피 리듬 | **해결**: D33/D34 Godot 규칙. HTML 값은 F3 비교 후보로만 |
| C2 | 늑대: HTML 돌진만·재사용 없음 vs Godot 물기+돌진·재사용·동시 2 | GAME_SPEC §4.1 vs RULES §늑대, D35 | 위협 구성 | **해결**: Godot 규칙. 늑대 우두머리(2연속 돌진)는 HTML 규칙에 Godot 물기·재사용 8초·동시 돌진 집계를 더한 **잠정** 구현 → 사용자 확인 |
| C3 | 보스 소환 늑대: HTML 겹침 제한(동시 1) vs Godot 늑대 규칙 | GAME_SPEC §13.5 | 보스전 압박 | 잠정: 소환 늑대도 Godot 물기·돌진 규칙, 보스전 겹침 제한(동시 1·보스 확정 중 금지)은 유지 |
| C4 | 편성 밀도: HTML 웨이브 2~4마리 순차 vs Godot 25/12 연속 보충(D33 채택) | DAY_WAVES vs RULES §밀도 | 전투 길이·압박 | **잠정 규칙**: 종류별 전체 수 = HTML 편성 합 × 밀도 배율 **5**(D33 기준 전투 = 숲 1일차 새벽 변주 2+3 = 5마리 × 5 = 25마리; 정예·구조물·보스는 배율 제외), 동시 상한 12, 묶음 3·간격 1.0, 원거리·지원 역할은 종류별 동시 상한(궁수 3·주술사 1·서리술사 2·거미 2·폭탄 3·방패병 3·멧돼지 2·잠복충 2·도적 3, 시험값). 경험치·금화 예산은 HTML 편성 기준 고정 → **사용자 판단 필요(Q1)** |
| C5 | 적 체력 배율: HTML 기본 세트 test03 = candE(숲 1.5…) vs Godot 늑대 30(×1, D33) | balance_data vs first_fight.json, D31 | 처치 시간 | 잠정: Godot 기본 = 지역 ×1(D33), candE는 F3 후보. 보스 체력은 test03의 2400/5000/7000(D27에서 논의된 값) → **Q2** |
| C6 | 경험치 예산: 0.3.1 "9.0 고정"은 숲 첫 전투 전용 | RULES §밀도 | 성장 속도 | **해결**: 전투 예산 = HTML 편성의 (XP_VALUE × 지역 배율 × 0.3) 합 + 지역 보너스 ×0.3. 개체 수 증가에 비례하지 않음 |
| C7 | 원정대의 갑옷: 합의 "전투 승리 시 8, 승리 정산당 1회" vs HTML 귀환 정산 1회(F7) | D20, 지시문 §8 | 회복량 | **해결**: 전투 승리(일반·심층·보스)마다 1회 |
| C8 | 회전 칼날 10/0.35 | ASSUMPTIONS, D09 | 시작 기술 균형 | 유지(구현자 시험값, 조작감 미승인) |
| C9 | 창 근접 약화(45% 안쪽 ×0.5)·주기 0.85 = test03 세트 | balance_data | 창 손맛 | 잠정: test03 값 적용(HTML 기본 선택), F3에서 현재값 비교 → **Q3** |
| C10 | HTML 오류 F1~F8 | V080_AUDIT | — | 옮기지 않음: F1 행동 목록 공유, F2 도달 불가 변주는 슬롯 이동(C11), F3 개조 후보 중복 제거는 선택지 키 기준, F4 지속 피해 원천 키, F5 심층 미리보기 RNG 한 스트림, F6 실제 값 표시, F7=C7, F8 보고서 메타데이터를 실제 설정에서 생성 |
| C11 | 저녁 변주 도달 불가: 비용 2 장소(습지·굴·심층)의 저녁(4) 변주는 오후(3)까지만 출발 가능 | SLOT_VARIANTS, F2 | 콘텐츠 도달 | 잠정: 습지 저녁 포자·심층 저녁 심연을 **오후(3)**로 이동, 굴은 새벽/오후 그대로 → **Q4** |
| C12 | 게임명·저장 키·폴더명 | D32 | — | 가칭 유지. Godot 저장 키 `prophecy_save_v1` 신설(HTML과 무관) |
| C13 | 부제 "늑대 2 → 3" | 0.3.1 main.tscn | 표시 | 제거 |
| C14 | HTML `single` 회차·이전 저장 이행(v1~v3) | run.js migrate | — | 제외(Godot 저장은 새 형식, D-기록) |
| C15 | 전투 시험실 UI 전체 | GAME_SPEC §14 | 개발 도구 | 부분: 시나리오 실행(빌드 프리셋·적 조합·체력 배율·봇)은 F3/명령줄로, 브라우저형 UI 전체는 제외 |
| C16 | 보스 소환 늑대 경험치 6(HTML) vs 보스 재도전 스냅샷 | GAME_SPEC | 악용 | 유지: 소환 처치 경험치는 주되 재도전 시 스냅샷 복구 |
| C17 | Godot 0.3.1 `hit_damage_normal` 12 vs HTML 대조 14 | PORT_NOTES §10 | 없음(측정 기준 차이) | 기록만 |
| C18 | Q 재사용: 0.3.1 데이터 14 고정 vs Lv 14/12/10·집중·박자·부적(HTML 레거시) | growth_data | — | Lv·집중·박자 적용, 옛 부적(-3)은 없음 |
| C19 | 회차 봇 시뮬레이션 메뉴 시간 가정(카드 6초 등) | run_sim | 보고 값 | 같은 가정으로 이식하고 표기 |
| C20 | OS 간 결정성 | PORT_NOTES §11-3 | 재현 | 같은 OS 재현성만 보장·표기. 원인 분석은 별도 |

**사용자 판단이 필요한 질문(진행은 잠정값으로 계속)**
- Q1(C4) 다수 편성 변환: 숲 새벽 25마리 기준 배율(×5)을 전 지역에 적용(예: 능선 2일차 10마리 편성 → 50마리) + 역할별 동시 상한 — 이 방식으로 갈지, 지역별 전체 수를 따로 정할지.
- Q2(C5) 적 체력 ×1(D33) + 보스 2400/5000/7000 조합으로 시작할지, 보스도 base(1500/3000/3600)로 할지.
- Q3(C9) 창 근접 약화·주기 0.85(test03)를 Godot 기본으로 둘지 현재값(14/0.7, 약화 없음)으로 둘지.
- Q4(C11) 저녁 변주를 오후로 옮길지, 저녁 출발이 가능하게 비용 2 장소의 저녁 출격(칸 부족)을 허용할지.
- Q5(C2) 늑대 우두머리·보스 소환 늑대에 Godot 물기 규칙을 적용하는 잠정안 승인 여부.

## 7. 검증 계획
- 규칙 테스트(headless): 0.3.1의 72개 유지(기준 전투 보존) + HTML 170 케이스를 Godot 규칙으로 재작성(폐기 규칙 제외, D34/D35로 대체된 회피·늑대 케이스는 Godot 규칙 기준).
- 통합: 회차 봇으로 새 회차→최종 보스→결과를 headless 완주(시드·시작 기술·전략별), 저장/복구 왕복, 상점·교체·취소·대장간, 보스 스냅샷.
- 실제 화면: Windows에서 캡처·영상(`PROPHECY_CAPTURE`·`PROPHECY_MOVIE`), 사람 키보드 플레이는 별도 표기.
- 기준 전투 보존: `first_fight.json` 기본값으로 실행하는 "기준 전투" 시나리오(사람·봇)를 제목 화면 검증 메뉴와 headless에 유지, 0.3.1 밀도 보고서와 같은 시드 결과 비교.
- Codex 재현: 명령·시드·설정 문자열·커밋·엔진·OS·결과 파일 위치를 `prophecy_godot/docs/PORT_NOTES.md` §12부터 기록.
