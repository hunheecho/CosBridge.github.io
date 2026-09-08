# 0.7.0 실제 실행 화면(자동 진행 캡처)

생성: 실제 창 실행 `PROPHECY_UI_SMOKE=<dir> PROPHECY_UI_FULL=1 PROPHECY_UI_SPEED=6 PROPHECY_UI_ROUTE=act1_hunt_forest,act2_crimson_ritual,act3_temporal_abyss`,
APPDATA/LOCALAPPDATA 격리. 자동 진행 봇은 실력 프로필(skilled) — 사람 조작이 아니다.

포함: 제목·검증 메뉴·시작 기술 선택·마을(빌드 아이콘·장비 분리)·전투 HUD(자동기술 3칸 + 개조 칸, 회피/Q/E 분리)·보상·사건·정산·3택·상점·대장간·장비·통계·하루 종료 확인·툴팁·일시정지·조작법·설정·검증 패널·빌드 상세.

한계(정직하게): 이 회차는 2일차까지만 진행됐다. 전투가 길어져(9일차 75마리·보스 체력 상향) 자동 진행 40분 안전장치에 먼저 걸렸다.
관문·완주·무한 화면은 이 묶음에 없다. 10일 일정·반복 탐험·제단·사건·변경권·저장/계속하기 경로는 `tests/ui_flow_tests.gd`·`tests/balance_tests.gd`가 실제 화면 함수로 검사한다.
UI 자체의 디자인 캡처(초광폭·좁은 창·터치 배치·개조 연출 프레임)는 `../0.7.0_ui/`에 있다.
