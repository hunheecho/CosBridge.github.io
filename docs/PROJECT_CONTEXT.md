# 예언의 시간표(가칭) — 프로젝트 맥락 · 공통 진입 문서

마지막 정리: 2026-09-07 (Asia/Seoul). 저장소 `hunheecho/CosBridge.github.io`, 브랜치 `claude/prophecy-action-prototype-hehbeo`.
이 문서는 **읽기 순서·현재 초점·문서 위치·운영 규칙**만 담는다. 현재 규칙·수치·검증 상태는 아래 "공식 문서 위치"의 정본에 한 번만 적고, 여기에는 복제하지 않는다.
출처: Codex가 대화를 복원해 저장소 밖에 작성한 공유 문서 초안(2026-09-07, `docs/archives/2026-09-07_codex_shared_context/`)을 저장소 문서·최신 코드와 대조해 통합했다. 초안의 오래된 구현 상태(Godot 56d600f 단계)는 최신 상태로 갱신했고, 사용자 결정·이유는 그대로 옮겼다.

## 1. 새 세션 시작 절차 (구현자 진입 규칙)

읽기 순서:
1. 이 문서.
2. `prophecy_action_prototype/docs/HANDOFF.md` 맨 위 절 — 현재 브랜치·버전·마지막 커밋·다음 작업.
3. `docs/DESIGN_DECISIONS.md` — 무엇을 왜 바꿨는지, 폐기·대체 관계, 최신 사용자 판단(D33).
4. Godot 작업이면: `prophecy_godot/README.md`(실행·검증 명령) → `prophecy_godot/docs/RULES.md`(현재 규칙·변경 이력) → `prophecy_godot/docs/ASSUMPTIONS.md`(시험값 근거) → `prophecy_godot/docs/PORT_NOTES.md`(세션별 검증 기록·환경 제한·다음 이식 순서 §7) → `prophecy_godot/docs/DENSITY_REPORT.md`(봇 측정).
5. HTML 기준선이 필요하면: `prophecy_action_prototype/docs/GAME_SPEC.md` §19, `ASSUMPTIONS.md`, `TRACEABILITY.md`, `TECH_DECISION.md`. HTML에 있는 기능을 Godot에 있다고 간주하지 않는다.
6. HTML 구현을 점검할 때만: 독립 검수 보고 `docs/archives/2026-09-07_codex_shared_context/evidence/V080_AUDIT.md`(F1~F8).

시작 시 확인:
- `git status`·`git log -3`·`git fetch`로 브랜치·HEAD·미커밋 변경·원격 변경을 확인한다. 로컬 수정이 있으면 강제 덮어쓰기·reset·무조건 pull을 하지 않는다. Godot 편집기는 `project.godot`·`*.import`를 다시 써서 diff를 만들 수 있다(동작 차이 없음).
- 이식 기준(HTML ee10fc7)과 최신 검수 커밋이 다르면 미검증 변경 범위를 적는다.
- 적용되는 결정 ID(D번호)와 미해결 항목을 적고, 이미 기록된 결정을 같은 이유로 다시 묻지 않는다.
- 이 문서와 공유 문서는 사람이 갱신한다. 세션 간 자동 기억·자동 동기화·백그라운드 감시를 전제로 하지 않는다.

## 2. 어떤 게임인가

마검사가 제한된 준비 기간 동안 출격하고, 성장과 장비를 선택하며, 다가오는 보스 관문에 대비하는 2D 실시간 액션 게임이다.
전체 설계: 자동기술 3개 + Q 감속장 + E 수동기술 + Space 회피. 장비(무기/갑옷/방패)는 자동기술과 별개이며 런 한정이다.
세계관의 세부 설정은 확인된 범위 이상으로 새로 확정하지 않는다. 게임명 "예언의 시간표"는 가칭이며 새 한국어·영어 이름은 미정이다(D32).

플레이어가 느껴야 할 재미:
- 다양한 적의 예고를 보고 이동·회피·감속장으로 대응한다.
- 새 기술·개조·장비가 다음 전투의 공격 방식과 대응을 어떻게 바꿀지 기대한다.
- 제한된 하루에서 출격·더 깊이·귀환·휴식을 고른다. 오늘의 장소 2곳, 시간대, 체력과 보상을 보고 계획한다.
- 더 깊이 들어갈 이익과 현재 전리품·남은 하루를 잃을 위험을 비교한다.
- 출격이 재료와 영구 능력치만 채우는 반복 노동이 되지 않게 한다.
- 기본 UI는 짧게, 자세한 설명은 상세 보기·용어 설명으로.

사용자 관측(최종 밸런스 승인이 아님): 액션 전투 방향은 재미있다(D01). 경험치 ×0.3 속도는 유지할 가치가 있다(D08). Godot 0.3.1의 25마리 편성은 전투 느낌·개체 수·난이도·물기와 돌진 비율이 좋다(D33).

## 3. 현재 단계 (2026-09-07)

| 축 | 상태 |
|---|---|
| 개발 방향 | Godot 4.7.2-stable(GDScript, 2D, Compatibility)로 전환(D29). HTML v0.8.0(ee10fc7)은 비교 기준선, 새 HTML 콘텐츠는 추가하지 않는다 |
| Godot 구현 범위 | **합의된 게임 전체**(godot-0.4.0, D37): 자동기술 10+개조 30·Q/E·범용·특성·희귀 보상, 적 12+정예+보스 3, 임무·심층·사건, 7일·5칸 일정, 상점·장비·대장간·교체, 저장/계속하기, 피해 통계, 봇·시뮬. 0.3.1 첫 전투는 "기준 전투"(검증 메뉴·`CombatState.first_fight`)로 보존. 잠정값 Q1~Q5는 사용자 확인 대기(`PORT_BASELINE.md` §6) |
| Godot 버전 | godot-0.4.0(전체 이식). 최종 커밋·빌드 해시는 `prophecy_godot/docs/PORT_NOTES.md` §12-7. 배포물 ZIP `prophecy_godot_build/`(0.4.0 Windows 빌드 + 프로젝트 ZIP) |
| 사용자 플레이 | 0.3.1 기본 설정(x5 25마리)을 직접 플레이하고 긍정 평가 → 이후 변경의 **비교 기준**(D33). 50마리·다른 기술·다른 적·보스·회차 전체로 확대하지 않는다 |
| 독립 검수 | HTML 7ec93cd 검수 F1~F8은 ee10fc7에 모두 남아 있음(HTML에서 고치지 않고 Godot 이식 주의사항으로 보존, `PORT_NOTES.md` §6 A~G). Godot 피해 통계 오류(Codex 지적)는 0.3.1에서 수정·구현자 검증, 독립 재확인은 아직 없음 |
| 다음 작업 후보 | 사용자 판단 Q1~Q5(밀도 배율·역할별 상한, 보스 체력 세트, 창 약화, 저녁 변주 이동, 우두머리 물기 규칙), 사람 키보드 플레이 검증(전투 시간·가독성), Codex 독립 검수, OS 간 결정성 확인, 게임명. 우선순위는 `HANDOFF.md` |

전체 성장·경제·지역·3보스 설계(D03~D26, `GAME_SPEC.md`)는 godot-0.4.0에서 Godot으로 옮겨졌다(D37). HTML은 비교 기준선으로만 남고, 잠정값과 원본과 다른 점은 `PORT_BASELINE.md` §6·`prophecy_godot/docs/ASSUMPTIONS.md`에 있다.

## 4. 되돌리지 말아야 할 방향

- 경험치 구슬·자석 없음. 처치 즉시 획득(D06).
- 경험치 ×0.3을 과거 레벨업 횟수 목표 때문에 임의로 올리지 않음(D08). Godot에서는 적 개체 수가 늘어도 전투 전체 경험치 예산(9.0)이 늘지 않게 한다(D35).
- 회피 성공 보상 획득을 핵심 성장 축으로 다시 만들지 않음(D04).
- 장비 무기와 자동기술을 같은 슬롯·같은 개념으로 섞지 않음(D19). 장비는 런 한정, 영구 장비 강화·반복 재료 노가다를 새로 추가하지 않음(D18).
- 정예 하나를 죽였다고 일반 전멸전을 끝내지 않음(D10). Godot도 예정·대기 중인 적까지 처리해야 승리.
- 전투가 쉽다는 이유로 강제 보스 무적·피해 상한·숨은 플레이어 비례 스케일링을 넣지 않음(D12).
- 그래픽 대량 제작은 후순위. 임시 그래픽·타격 반응을 넣을 때 전투 규칙·수치를 함께 바꾸지 않음(D33).
- 기본 화면에 개발용 설명과 문서를 길게 노출하지 않음(D11). Godot은 검증 정보를 F3 패널로 분리.
- 테스트 통과나 봇 승률을 사람의 재미·밸런스 승인으로 표현하지 않음. 봇 명중률 같은 단일 수치만 보고 검격 넉백·물기 사거리·돌진 빈도를 자동 조정하지 않음(D33).
- 사용자가 좋다고 평가한 기준 조합(D33)을 바꿀 때는 같은 OS에서 수정 전후를 함께 재측정하고 비교 기준으로 재현 가능하게 남긴다.
- 새 이름 확정 전 저장소·실행 파일·저장 키를 일괄 변경하지 않음(D32).

## 5. 근거와 상태의 우선순위

의도한 규칙: 최신 명시적 사용자 결정 → 승인된 구현 지시문 → 현재 명세. 코드가 명세와 다르다고 코드가 저절로 새 합의가 되지 않는다. 동시에 실제 동작 판단은 해당 커밋의 실행 증거를 따른다. 합의했다고 구현됐다고 적지 않는다.

상태는 두 축으로 적는다:
- 설계 상태: 제안 / 사용자 합의 / 시험 적용 / 보류 / 대체됨.
- 구현 상태: 미구현 / 구현자 보고 / 독립 확인 / 문제 재현 / 미검증.

구분해서 적을 것: **사용자 결정**(원문 발언·날짜) / **시험값**(누가 정했는지: 사용자 시험값 vs 구현자가 정한 값) / **구현자 보고**(테스트·캡처 등 실행 증거와 범위) / **독립 검증**(검수자가 어떤 커밋에서 무엇을 재현했는지). 시험값 채택 동의와 최종 밸런스 승인을 구분한다. 구현자가 정한 값을 "사용자 지정"으로 바꾸지 않는다. "완료"에는 범위와 실행 증거가 필요하다.

## 6. 공식 문서 위치 (역할별 한 곳)

| 정보 | 공식 문서 | 비고 |
|---|---|---|
| 의도·읽기 순서·현재 초점·문서 운영 | `docs/PROJECT_CONTEXT.md` (이 문서) | |
| 설계 변경의 이유·과거 결정·대체 관계·사용자 판단 기록 | `docs/DESIGN_DECISIONS.md` | D01~D36 |
| Godot 전체 이식의 기준(기준 커밋·권한 순위·범위·구조·충돌·질문) | `docs/PORT_BASELINE.md` | 2026-09-07 착수 |
| 콘텐츠 대조표(개별 ID·설계/HTML/Godot 상태·포함·검증) | `docs/CONTENT_MATRIX.md` | 구현 진행에 따라 Godot 열 갱신 |
| 전체 게임 규칙(설계 정본, HTML v0.8.0 구현 기준) | `prophecy_action_prototype/docs/GAME_SPEC.md` (§19가 v0.8 규칙) | 초안 `CURRENT_DESIGN_DRAFT.md`의 병합은 **미완**(아래 열린 항목) |
| HTML 시험값·이전값·근거 | `prophecy_action_prototype/docs/ASSUMPTIONS.md` | |
| HTML 요구별 구현·검증 상태 | `prophecy_action_prototype/docs/TRACEABILITY.md` | R-CODEX-* 포함 |
| **Godot 첫 전투 현재 규칙·변경 이력·검증 상태** | `prophecy_godot/docs/RULES.md` | Godot 규칙의 기준. 숫자는 `prophecy_godot/data/first_fight.json` |
| Godot 시험값 근거 | `prophecy_godot/docs/ASSUMPTIONS.md` | 행마다 "사용자 시험값"/"시험값(구현자)" 구분 |
| Godot 구현·검증 기록, 환경 제한, HTML 검수 지적의 이식 주의(A~G), 다음 이식 순서 | `prophecy_godot/docs/PORT_NOTES.md` | §11부터 Windows 로컬 세션 |
| 현재 작업·막힌 것·바로 다음 작업 | `prophecy_action_prototype/docs/HANDOFF.md` 맨 위 절 | HTML·Godot 공용 인수인계. 아래로 갈수록 과거 버전 기록 |
| 기술 선택·Godot 이식 준비 지침·전환 결정 | `prophecy_action_prototype/docs/TECH_DECISION.md` | |
| 봇 측정·시뮬레이션 | Godot `prophecy_godot/docs/DENSITY_REPORT.md`, HTML `prophecy_action_prototype/docs/sim/` | 사람 조작감 판단 아님 |
| 독립 검수 증거(HTML 7ec93cd, F1~F8) | `docs/archives/2026-09-07_codex_shared_context/evidence/V080_AUDIT.md` | 검수자 보고 원문. 저장소 안 다른 문서가 이를 대체하지 않는다 |
| 실행·검증 명령 | `prophecy_godot/README.md`, `prophecy_action_prototype/README.md` | |
| 과거 통합 초안(현재 규칙 아님) | `docs/archives/2026-09-07_codex_shared_context/` | `ARCHIVE_NOTE.md` 참조 |

지적 사항 ID 대응: 검수 보고의 F1~F7은 `PORT_NOTES.md` §6의 A~G와 순서대로 같은 항목이다(F1=A 봇 출격 경로, F2=B 저녁 변주 도달 불가, F3=C 개조 예약 1장, F4=D 지속 피해 출처, F5=E 심층 장비 편향, F6=F 표시값≠실제값, F7=G 원정대 갑옷 시점). F8(시뮬레이션 보고서 머리말 설정 오류)은 §6에 없고 HTML 도구 문제로 남아 있다.

## 7. 역할과 갱신 규칙

- 사용자: 방향·범위·설계 변경·최종 재미/밸런스 판단.
- Claude 구현자: 승인된 변경을 구현하고 공식 문서를 작업의 일부로 갱신. 사람 플레이·조작감을 대신 판단하지 않는다.
- Codex 검수자: 주장을 독립 확인하고 검수 보고·문서 변경 제안을 저장소 밖에서 제출. 저장소 파일을 직접 쓰지 않는다. 검수자 규칙(Independent Auditor Rules)은 이 저장소에 없으며 여기서 정의·변경하지 않는다.
- 두 에이전트가 같은 공식 문서를 동시에 편집하지 않는다.

작업 종료 시:
- 규칙 변경: Godot은 `RULES.md`, HTML은 `GAME_SPEC.md`의 해당 규칙을 바꾸고 `DESIGN_DECISIONS.md`에 이유·대체 관계를 기록.
- 수치 변경: 해당 `ASSUMPTIONS.md`에 이전→이후·누가 정했는지·적용 커밋·비교 조건.
- 기능 구현·오류 수정: Godot은 `PORT_NOTES.md`(검증 범위: 테스트 / 게임 창 / 스크립트 입력 / 사람 플레이를 구분), HTML은 `TRACEABILITY.md`.
- 다음 작업: `HANDOFF.md` 맨 위 절만 갱신. 과거 버전 일기를 위에 쌓지 않는다.
- 중요한 변경만 이 문서 §3에 반영. 기존 결정의 이유는 삭제하지 않고 새 결정으로 대체 관계를 표시.
- 문서가 충돌하면 숨기지 않고 충돌 항목으로 남긴다. 사용자 판단이 필요한 설계와 명백한 구현 오류를 분리한다.

## 8. 열린 항목 (사용자 결정 또는 별도 작업 필요)

- 게임명(한국어·영어) 미정. 후보 중 채택된 것 없음(D32).
- 회피가 장애물에 막힌 채 눌리면 거리 0으로 끝나며 대기 시간을 소모하는 규칙의 유지 여부(`RULES.md` §회피 미결).
- 늑대 체력 30이 적절한지는 밀도 시험과 별개의 비교 항목(D33은 조합 전체의 체감 평가).
- 런의 목표 플레이 시간, 임무 완료 장소의 재방문·임무 후 심층 허용, 예약 대체 정책, 가방 용량·영구 해금 범위(HTML 설계, `GAME_SPEC.md`·초안 IMPLEMENTATION_STATUS "사람 판단" 절).
- 초안 `CURRENT_DESIGN_DRAFT.md` → `GAME_SPEC.md`·`ASSUMPTIONS.md` 병합, `IMPLEMENTATION_STATUS.md` → `TRACEABILITY.md`·`HANDOFF.md` 병합은 **아직 하지 않았다**(이번 통합은 PROJECT_CONTEXT·DESIGN_DECISIONS·PLAYER_FEEDBACK 범위). 초안은 archives에 원문 보존.
- Godot 피해 통계 수정(0.3.1)의 독립 재확인, Linux↔Windows 결과 차이 원인(`PORT_NOTES.md` §11-3).
