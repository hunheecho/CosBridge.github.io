# 실제 속도 영상 클립 (0.8.0)

**연속 프레임 묶음이 아니라 재생되는 영상 파일이다.** Godot Movie Maker(`--write-movie … --fixed-fps 24`)로 찍었고,
`--fixed-fps`가 한 프레임을 정확히 1/24초로 고정하므로 파일을 그대로 재생하면 게임이 실제 속도로 움직인다.

## 촬영을 위해 무엇도 바꾸지 않았다

- 판정·수명·피해·시간 배율은 그대로다(`time_scale = 1`). 규칙 코드에는 촬영용 분기가 없다.
- 바뀐 것은 **어떤 장면을 띄울지**뿐이다(`PROPHECY_CLIP`, `scripts/game/main.gd`의 `CLIPS`).
- 방패병 두 클립만 사람 입력 자리에 정해진 이동을 넣는다(`ClipBot`: 정면에서 버티기 / 상대 주위를 돌기).
  규칙 우회가 아니라 **이동 입력**이며, 공격·회피·피해 계산은 평소 그대로다.
- 그 밖의 클립은 기존 봇(balanced)이 조작한다.

## 찍은 것

| 파일 | 내용 | 길이 | 용량 |
| --- | --- | --- | --- |
| `hud.avi` | 조작 3칸(Space 회피 · Q 감속장 · E 중력핵)의 상태 전환 — 준비됨 / 사용 / 흑백 + 남은 초 | 10초 | 13.2 MB |
| `mixed.avi` | 일반 혼합 전투(습지 4일차 실제 편성) | 6초 | 8.8 MB |
| `elite.avi` | 특수 정예(칼날 장인 · 역병술사 · 사슬 파괴자) + 늑대 | 6초 | 8.3 MB |
| `shield_front.avi` | 방패병 **정면** — 막히는 쪽(방패병 3기, 6초 뒤에도 2기 남는다) | 6초 | 7.8 MB |
| `shield_flank.avi` | 방패병 **측후방** — 돌아 들어가는 쪽(같은 3기가 약 4초 만에 전멸) | 5초 | 6.6 MB |
| `mission_seal.avi` | 봉인 임무(봉인 지점에서 버티기, 진행률 표시) | 6초 | 8.9 MB |
| `mission_altar.avi` | 제단 임무 | 6초 | 9.4 MB |
| `guardian_cover.avi` | 수호자 엄폐 대응(2관문 보스) | 8초 | 11.3 MB |
| `mod_spear_off.avi` | 개조 **전**: 관통창 Lv3, 개조 없음 | 5초 | 6.8 MB |
| `mod_spear_on.avi` | 개조 **후**: 관통창 Lv3 + 귀환 검기 | 5초 | 6.7 MB |
| `mod_frost_off.avi` | 개조 **전**: 서리 수정 Lv3, 개조 없음 | 5초 | 6.9 MB |
| `mod_frost_on.avi` | 개조 **후**: 서리 수정 Lv3 + 서리 부채 · 깨지는 수정 | 5초 | 6.9 MB |

합계 12개 · 73초 · 약 102 MB.

개조 전/후 두 쌍은 같은 시드·같은 지역·같은 레벨이고 개조만 다르다(비교용).
방패병 두 클립도 같은 배치(3기)·같은 빌드이고 **이동만** 다르다 — 정면에서 버티느냐, 돌아 들어가느냐.

## 찍은 명령

```sh
# 클립 하나 (이름과 초는 표대로)
PROPHECY_CLIP=<이름> PROPHECY_CLIP_SEC=<초> PROPHECY_CLIP_FPS=24 \
  godot --path prophecy_godot \
        --write-movie prophecy_godot/docs/captures/0.8.0_clips/<이름>.avi --fixed-fps 24
```

- 클립 이름 목록은 `scripts/game/main.gd`의 `CLIPS` 상수에 있다(없는 이름을 주면 목록을 찍고 종료한다).
- 길이는 프레임 수로 센다(`_clip_tick`). `--fixed-fps`와 `PROPHECY_CLIP_FPS`를 같게 두면 파일 길이가 정확히 그 초가 된다.
- 실행마다 `APPDATA`/`LOCALAPPDATA`를 실행 전용 폴더로 격리해 실제 저장·프로필을 건드리지 않았다.

## 파일을 저장소에 넣지 않은 이유

MJPEG AVI는 이 해상도(960×640)에서 **초당 약 1.5 MB**다. 12개 합계가 `docs/captures` 전체(17 MB)의 몇 배가 된다.
`editor/movie_writer/mjpeg_quality`는 4.7.2에서 결과 크기를 바꾸지 않았다(0.35와 0.05가 바이트까지 같은 파일).
그래서 파일은 `.gitignore`에 넣고(`prophecy_godot/docs/captures/0.8.0_clips/*.avi`) **이 문서만 저장소에 둔다**.
파일은 위 명령으로 언제든 같은 자리에 다시 만든다. 임의로 외부에 올리지 않았다.

찍어 둔 실제 파일 위치와 용량은 이 문서 아래 "이번 촬영 결과"에 적는다.

## 이번 촬영 결과 (2026-09-08)

- 위치: 이 폴더(`prophecy_godot/docs/captures/0.8.0_clips/`) — 저장소에는 이 README만 들어간다.
- 12개 파일 · 합계 73초 · **약 102 MB**(가장 큰 것 `hud.avi` 13.2 MB, 가장 작은 것 `shield_flank.avi` 6.6 MB).
- 엔진: Godot 4.7.2 (GL Compatibility), 기록 해상도 960×640 @ 24 FPS, MJPEG AVI.
- 실행마다 콘솔이 `movie length`와 실제 기록 시간을 찍는다(예: `132 frames at 24 FPS (movie length: 00:00:05:12)`).
  기록에 걸린 벽시계는 실제 속도의 50~76%였지만 **파일은 24 FPS로 저장되어 재생은 실제 속도**다.
- 내용 확인: ffmpeg 없이 AVI의 `movi` 청크에서 프레임(JPEG)을 꺼내 눈으로 봤다. 12개 모두 의도한 장면이 들어 있다.
- 외부에 올리지 않았다.
