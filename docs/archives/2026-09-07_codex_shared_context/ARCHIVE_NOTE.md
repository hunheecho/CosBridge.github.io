# 보관 안내 — 과거 통합 초안, 현재 규칙 아님

이 폴더는 Codex가 2026-09-07 저장소 밖(`C:\Users\Public\Documents\ESTsoft\CreatorTemp\prophecy-shared-context-20260907`)에 작성한 공유 문서 초안을 **원문 그대로** 보관한 것이다. 같은 날 Claude 구현자가 저장소 문서·최신 코드(godot-0.3.1, 2cb7ae6)와 대조해 통합했다.

- 이 폴더의 파일은 현재 규칙·현재 상태의 정본이 아니다. 특히 `PROJECT_CONTEXT.md`·`LATEST_UPDATE.md`·`IMPLEMENTATION_STATUS.md`의 Godot 상태(56d600f/73819e2, 테스트 25/25, "사용자 플레이 전")는 작성 시점 기록이며 이후 0.2.0·0.3.0·0.3.1로 진행됐다.
- 통합 결과: `PROJECT_CONTEXT.md` → `docs/PROJECT_CONTEXT.md`(경로·상태 갱신, 읽기 순서·운영 규칙 통합). `DESIGN_DECISIONS.md` + `LATEST_UPDATE.md`(D31·D32) + `PLAYER_FEEDBACK.md`(D33) → `docs/DESIGN_DECISIONS.md`(D01~D33 이전 + Godot 결정 D34~D36 추가, "→ 이후" 갱신).
- 아직 통합하지 않은 것: `CURRENT_DESIGN_DRAFT.md`의 `GAME_SPEC.md`·`ASSUMPTIONS.md` 병합, `IMPLEMENTATION_STATUS.md`의 `TRACEABILITY.md`·`HANDOFF.md` 병합. 병합 전까지 두 파일은 참고용이며 두 번째 정본으로 운영하지 않는다.
- `evidence/V080_AUDIT.md`와 그 자료는 HTML 7ec93cd 독립 검수의 **원문 증거**로 계속 유효하다(F1~F8, `prophecy_godot/docs/PORT_NOTES.md` §6 A~G와 대응). 재현 스크립트(`*.cjs`)는 검수 시점 소스 경로를 인자로 받는다.
- `CLAUDE_DOCS_HANDOFF.txt`는 Codex가 Claude에게 보낸 통합 지시 원문이다.
