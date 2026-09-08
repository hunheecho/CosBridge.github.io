# 0.7.0 UI 개편 화면 캡처

UI_REDESIGN_HANDOFF(2026-09-08) §2·§4·§5·§6 적용 결과의 실제 실행 화면이다. 시안 이미지가 아니라 창 모드 Godot 실행에서 저장한 PNG다.

## 만든 방법(재현)

기본 화면(설계 크기 960×640 창):

```
APPDATA=<격리폴더> LOCALAPPDATA=<격리폴더> PROPHECY_LEGACY_PLACES=1 \
PROPHECY_UI_SMOKE=<출력폴더> PROPHECY_UI_SPEED=4 \
<godot> --path prophecy_godot
```

창 크기별 재배치(같은 경로에 `--resolution` 만 추가):

- `40_combat_ultrawide_2340x1080.png`, `42_base_ultrawide.png` — `--resolution 2340x1080` (wide 묶음)
- `41_combat_narrow_1024x768.png` — `--resolution 1024x768` (narrow 묶음: 아이콘을 줄이고 Lv 줄을 접는다)

개조 연출 확인 프레임:

```
APPDATA=<격리폴더> LOCALAPPDATA=<격리폴더> PROPHECY_LEGACY_PLACES=1 \
PROPHECY_MOD_DEMO=<출력폴더> <godot> --path prophecy_godot
```

## 파일

| 파일 | 내용 |
| --- | --- |
| `11_combat.png` | 전투 HUD — 자동기술 3칸(+각 칸 아래 개조 2칸) · 장비 3칸(분리된 영역) · 회피/Q/E(키·아이콘·쿨다운 숫자) |
| `10_base.png`, `26_base_continued.png`, `42_base_ultrawide.png` | 마을(거점) — 오른쪽 빌드가 전투 HUD와 같은 아이콘 구성 |
| `13_choice.png` | 선택 카드 — 큰 아이콘 + '붙는 곳' 상위 기술 아이콘 + 효과 한 문장 + 적용 전/후 |
| `14_shop.png`, `15_forge.png` | 상점 / 대장간(개조 변경권 이름·보유 수·최종 금액) |
| `17_stats.png` | 피해 통계 — 기술별 총 피해·기여율·전투 평균 DPS, 필터, 보호막·회복 분리 |
| `16_equip.png`, `12_reward.png`, `18_bossprep.png`, `21_pause.png`, `00_title.png`, `01_pick_start.png` | 그 밖의 흐름 |
| `mod_frames/` | 개조 연출 **연속 프레임**(영상 아님) |

## mod_frames — 정직한 설명

`mod_frames/`는 **동영상이 아니라 연속 PNG 프레임**이다. 파일 이름은
`mod_<번호>_t<전투시각>_<그 프레임에 실제로 살아 있던 개조 표시>.png` 형식이고,
화면에 해당 개조 효과가 실제로 존재하는 프레임만 저장했다(임의 타이머로 만든 장면이 아니다).

관통창(분열 창날 · 귀환 검기) + 서리 수정(서리 부채 · 깨지는 수정) 고정 빌드를 봇이 진행한 검증 전투다.
사람이 조작한 결과가 아니고, 사람 눈으로 본 가독성 평가도 아니다.

- `분열` = 첫 명중 지점의 분기 결절, `분열파편` = 갈라진 두 파편
- `귀환` = 되돌아오는 검기(나갈 때와 선두 모양·잔상이 다르다)
- `부채` = 서리 부채의 양옆 2발(가운데 기본 발사와 꼬리·표식이 다르다)
- `수정파열` = 깨지는 수정의 파열 순간, `수정파편` = 그 파편(실제 판정)
- `검흔` = 잔류 검흔의 남은 흔적(점선 = 무해한 장식, 실제 피해 순간은 채워진 부채꼴)

## 검증하지 않은 것

- 사람 눈으로 본 가독성 판단(“읽기 쉬운가”)은 이 캡처로 주장하지 않는다.
- 안드로이드/iOS 실기와 세로 화면은 확인하지 않았다. 터치 배치는 PC에서 `PROPHECY_TOUCH=1` 경로로만 만들었다.
- 캡처는 설계 크기(캔버스 960×640) 기준이며, 1080p 실기 화면에서 본 결과가 아니다.
