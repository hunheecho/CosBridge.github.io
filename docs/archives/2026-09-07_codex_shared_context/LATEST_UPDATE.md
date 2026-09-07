# 최신 상태 보충 — 2026-09-07

이 문서는 공유 초안 작성 이후 들어온 보고의 보충이다. 기존 검수 기록을 소급해서 바꾸지 않는다. 공식 문서 통합 시 PROJECT_CONTEXT·TRACEABILITY·HANDOFF에 병합한다.

## Godot 첫 전투

- 구현자 보고: 프로젝트 56d600f, 배포물 73819e2, HTML 기준 ee10fc7.
- 구현자 보고: 규칙 테스트 25/25, HTML 대조 14/14, Linux 실제 렌더·영상, Windows 내보내기 성공.
- 이번 Codex 독립 확인 범위: 공식 Godot 4.7.2-stable 릴리스 페이지, 73819e2의 README·PORT_NOTES·project.godot·first_fight.json 읽기, GitHub 배포 파일 목록·크기 확인.
- 배포 ZIP 메타데이터: Windows 38,115,752바이트 / 프로젝트 973,031바이트. ZIP 내용·실행 성공을 독립 검증한 것은 아니다.
- Windows 실행, 실제 키보드 입력, 테스트 25/25 및 대조 14/14 재실행은 이번 확인에서 수행하지 않았다. 구현자 보고 상태로 유지한다.
- first_fight.json의 늑대 체력은 30. 이전 시험 설정의 숲 ×1.5를 적용한 전투와 같은 난이도라고 간주하지 않는다. 같은 조건의 대조 범위를 확인한 후 판단한다.
- 다음 단계: 사용자가 Windows 첫 전투에서 이동·회피·Q·늑대 예고·장애물·재시작을 확인. 이후 이식 범위 확장.

근거:
- https://github.com/godotengine/godot/releases/tag/4.7.2-stable
- https://github.com/hunheecho/CosBridge.github.io/blob/73819e2/prophecy_godot/docs/PORT_NOTES.md
- https://github.com/hunheecho/CosBridge.github.io/blob/73819e2/prophecy_godot/data/first_fight.json
- https://github.com/hunheecho/CosBridge.github.io/tree/73819e2/prophecy_godot_build

## D31 — 첫 전투 배포 보고 수신

- 결정·기록일: 2026-09-07.
- 상태: 구현자 배포 보고, 문서·설정·파일 존재 일부 독립 확인. 사용자 플레이 승인 전.
- 이전 → 이후: Godot 준비 지시 → 첫 전투 배포물을 받아 사람 조작을 확인할 단계.
- 이유: 사용자 전달 보고의 커밋·산출물이 확인됨.
- 관계: D29·D30의 진행 상태 갱신이며 전체 이식 승인이나 재미·밸런스 승인이 아니다.

## D32 — 기존 게임명 재검토

- 결정·기록일: 2026-09-07.
- 결정 주체: 사용자.
- 상태: 이름 변경 방향 합의, 새 이름 미정.
- 이전 → 이후: 기존 가칭을 계속 사용 → 한국어·영어 명칭을 함께 새로 검토.
- 이유·근거: 사용자 “이름은 왜자꾸 예언의시간표냐 새로좀짓자”, “영어명칭도 확실히 좋아야해”, “겹치는거아니냐”.
- 후보는 채택된 이름이 아니다. GRIMHOUR·BORROWED DAWN·REDWAKE의 기존 사용을 발견했다. DUSK DEBT는 이번 검색에서 정확한 작품명 일치를 못 찾았을 뿐 사용 가능성을 확정하지 않았다.
- 적용: 새 이름 확정 전 저장소·실행 파일·저장 키를 일괄 변경하지 않는다. 문서의 기존 제목은 과거 가칭으로 이해한다.


## 사용자 플레이 후속 확인

Godot 0.3.1의 25마리 편성을 사용자가 직접 플레이하고 전투 느낌·개체 수·난이도·물기와 돌진 비율을 긍정 평가했다. 최신 사용자 판단은 [PLAYER_FEEDBACK.md](PLAYER_FEEDBACK.md)의 D33을 참조한다. 이전 절의 '사용자 플레이 전'은 과거 단계 기록이다.
