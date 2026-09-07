# 예언의 시간표 — 공유 맥락 문서 초안

최신 보충: 먼저 [LATEST_UPDATE.md](LATEST_UPDATE.md)를 읽는다. Godot 배포 보고와 게임명 재검토 상태가 추가됐다.

작성일: 2026-09-07 (Asia/Seoul).
기록 범위: 이 대화의 사용자 결정, 전달 완료된 구현 지시문, HTML v0.8.0 7ec93cd 독립 검수, 이후 Godot 준비 지시.
대화 복원본이다. 과거 결정의 정확한 날짜가 없는 경우 버전·대화 순서만 기록한다.

## 목적

새 세션의 사용자·Claude·Codex가 전체 대화를 다시 읽지 않고 현재 목표, 바뀐 이유, 검증 상태를 파악한다.
이 ZIP은 저장소에 아직 통합하지 않은 초안이다. 현재 실행 코드나 Godot 완료 상태를 뜻하지 않는다.

## 먼저 읽기

1. PROJECT_CONTEXT.md — 게임의 의도, 현재 단계, 금지한 우회책, 문서 운영 규칙.
2. CURRENT_DESIGN_DRAFT.md — 사용자 합의를 복원한 현재 설계. 기존 GAME_SPEC.md에 병합할 임시 문서.
3. DESIGN_DECISIONS.md — 무엇을 왜 바꿨고 무엇을 폐기했는가.
4. IMPLEMENTATION_STATUS.md — 구현자 보고와 독립 확인을 분리한 현재 상태.
5. evidence/V080_AUDIT.md — 실제 발견한 오류의 코드 위치와 재현.

Claude에게 CLAUDE_DOCS_HANDOFF.txt를 전달하고 이 ZIP을 함께 제공하면 된다.
Windows의 로컬 경로는 원격 Claude에서 자동으로 읽히지 않는다. 첨부 또는 저장소에 반영되어야 공유된다.

## 저장소 통합 후 공식 문서 소유권

| 정보 | 공식 문서 |
|---|---|
| 방향·읽기 순서·현재 작업 초점 | docs/PROJECT_CONTEXT.md |
| 현재 게임 규칙 | 기존 docs/GAME_SPEC.md |
| 현재 시험 수치·근거 | 기존 docs/ASSUMPTIONS.md |
| 설계 변경의 이유와 과거 결정 | docs/DESIGN_DECISIONS.md |
| 요구별 구현·검증 상태 | 기존 docs/TRACEABILITY.md |
| 현재 작업·차단·다음 순서 | 기존 docs/HANDOFF.md |
| 개별 검수·시뮬레이션 증거 | docs/audits/ 또는 docs/sim/ |

CURRENT_DESIGN_DRAFT와 IMPLEMENTATION_STATUS는 통합용이다.
병합 후 현재 규칙의 두 번째 정본으로 계속 유지하지 않는다.
필요하다면 날짜가 붙은 archives 폴더에 보관하되 “현재 문서 아님”을 명시한다.

## 권한과 갱신

- 사용자: 방향, 범위, 설계 변경과 최종 재미·밸런스 판단.
- Claude 구현자: 승인된 변경을 구현하고 공식 문서 갱신.
- Codex 검수자: 주장을 독립 확인하고 검수 보고·문서 변경 제안 제출.
- 현 AGENTS.md상 Codex는 저장소 파일을 쓰지 않는다. 이 묶음은 저장소 밖에 작성했다.
- 두 에이전트가 같은 공식 문서를 동시에 편집하지 않는다.
- 다음 작업을 시작할 때 위 문서를 읽고, 결정이 바뀐 작업을 마칠 때 해당 문서만 갱신한다.
- 세션 간 자동 기억이나 자동 동기화를 전제로 하지 않는다.

