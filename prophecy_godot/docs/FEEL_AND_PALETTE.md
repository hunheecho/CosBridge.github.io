# 타격감과 막별 색감 (2026-09-08)

전투 화면의 **타격감**(사용자 요구 6번)과 **막별 색감**(사용자 결정)을 어디서 어떻게 다루는지 적는다.
규칙(`scripts/rules/*`)은 한 줄도 바꾸지 않았다. 여기 있는 것은 전부 표시 계층(`scripts/game/render.gd`, `scripts/game/audio.gd`)과 색 정본(`data/palette.json`)이다.

---

## 1. 타격감

### 1.1 무엇을 어디서 하는가

| 항목 | 어디 | 무엇을 읽는가(규칙이 이미 주던 값) |
| --- | --- | --- |
| 적 짧은 점멸 | `PRender.draw_enemy` · `PRender.body_col` | `e.flash`(규칙이 적중 때 0.12초로 정한다). 시간·값을 표시 계층이 늘리지 않는다 |
| 방향성 있는 타격 효과 | `PRender.draw_impacts`의 `spark` | 규칙이 내는 `fx{kind:"spark", angle, crit}` — `angle`은 실제 피해 방향(`dir`) |
| 기술별로 구분되는 소리 | `PAudio._plan` · `PAudio._variant` | `st.events`의 `hit`·`swing`·`shoot` + `st.events_data`의 `{crit}`·`{form}` |
| 사망 반응 | `PRender.draw_impacts`의 `death` + 소리 `kill`/`boss_down` | 규칙이 내는 `fx{kind:"death", r, color}`와 `ev("kill")`·`ev("boss_down")` |
| 강한 공격의 약한 화면 반응 | `PRender.shake_offset` → `PRender.draw`가 기준 변환에만 넣는다 | `st.effects`의 강한 연출 항목만 |

### 1.2 소리 갈래

| 이벤트 | 조건 | 나는 소리 |
| --- | --- | --- |
| `hit` | `crit = true` | `crit` |
| `hit` | 뒤따르는 `swing{form:"arc"}` | `hit_arc`(높은 쇳소리) |
| `hit` | 뒤따르는 `swing{form:"beam"}` | `hit_beam`(낮게 꽂히는 소리) |
| `hit` | 뒤따르는 `swing{form:"melee"}` | `hit_melee`(아주 짧고 높은 톡) |
| `hit` | 뒤따르는 `shoot` | `hit_shot`(딱 하고 박히는 소리) |
| `hit` | 짝을 못 찾음(장판·지속 피해 등) | `hit`(기존 소리) |
| `swing` | `form`별 | `swing_arc` · `swing_beam` · `swing_melee` |
| `boss_down` | 보스 사망 | `boss_down`(무너지는 저음) |

무기 코드가 **피해를 먼저 주고 소리 이름을 나중에** 내므로, 적중 뒤 8칸 안에 오는 발사 이벤트까지만 같은 기술로 본다(`PAudio.FORM_LOOKAHEAD`).
짝을 못 찾으면 기본 `hit`으로 떨어질 뿐, 규칙에는 아무 영향이 없다.

### 1.3 화면 반응(카메라)

- 원인은 `PRender.SHAKE_SOURCES`에 적힌 **강한 타격 연출만**이다: `impact`(망치 내려찍기·보스 착지 충격파) · `bossland` · `mineburst` · `strike` · `slashline`.
- **일부러 뺀 것**: `spark`(모든 적중) · `hitflash`(피격 — 장판 틱마다 난다) · `zone` · `burst` · `flare` · `death`.
  → 장판이 여러 개 켜져 있어도 화면은 흔들리지 않는다(`tests/hit_feel_tests.gd`가 0인 것을 확인한다).
- 세기: `SHAKE_MAX = 3.0px`. 여러 개가 겹쳐도 `limit_length`로 3px를 넘지 않고, 연출이 끝나갈수록 제곱으로 잦아든다.
- 값은 `st.effects`의 `t`·`ttl`·좌표에서만 나온다. 난수도 프레임 시각도 쓰지 않으므로 **같은 상태를 두 번 그리면 같은 값**이다.
- **전역 시간 정지는 어디서도 하지 않는다**(`Engine.time_scale`·`get_tree().paused`를 표시 계층이 건드리지 않는 것을 시험으로 고정).

#### 끄기 옵션

```gdscript
PRender.set_shake(false)   # 끈다(값은 user://render_prefs.json에 남는다)
PRender.shake_on()         # 지금 켜져 있나
```
환경 변수 `PROPHECY_NO_SHAKE=1`로도 끌 수 있다(자동 검증·촬영용).

> **아직 못 한 것**: 설정 화면의 체크 상자는 `scripts/game/ui/settings_panel.gd`에 있어야 하는데 이번 작업 범위 밖(수정 금지)이다. 필요한 변경은 아래 4장에 적었다.

### 1.4 예고를 가리지 않게

그리는 순서(`PRender._draw_layers`):

```
숲 바닥 → 장애물 → 바닥 지역 → 상자·목표 → 사거리 → 무기 몸체
→ 내 공격 잔상 → 개체(y 정렬) → 수관 → **내 적중 연출(draw_impacts)** → **적 예고(draw_telegraphs)** → 투사체 → 숫자
```

- 적중 불티·사망 조각·피격 표시는 전부 적 예고 **아래**다.
- 피격 표시(`hitflash`)는 경기장 전체를 붉게 덮던 것을 **가장자리 26px 띠**로 바꿨다. 화면 가운데의 예고가 붉은 막에 묻히지 않는다.

---

## 2. 막별 색감

### 2.1 정본은 한 곳

`data/palette.json` 하나가 배경·예고 색의 정본이다. `render.gd`는 `palette_for(act, region_id)`로 한 벌을 골라 `pc("키", 기본값)`으로 꺼내 쓴다.

- `acts`: 막 기본값 3벌(1·2·3).
- `themes`: 테마 9종이 **덮어쓸 키만** 가진다. 적지 않은 키는 막 기본값 그대로다 → 막 색감은 유지, 테마 차이는 보존.
- 테마 id가 목록에 없으면(보스 전투 `region_id = "boss"` 등) 그 막 기본값으로 떨어진다.

### 2.2 막·테마 색 표(바닥)

| 막 | 방향 | 막 기본 바닥 | 테마 | 테마 바닥 |
| --- | --- | --- | --- | --- |
| 1막 | 초록(회색 섞인 올리브) | `#303B2A` | 사냥 숲 | `#303B2A` |
| | | | 버려진 요새 | `#343A2E` |
| | | | 포자 정원 | `#2C3B30` |
| 2막 | 연주황(어두운 흙색) | `#55483A` | 붉은 의식터 | `#57443A` |
| | | | 무너지는 광산 | `#4E463C` |
| | | | 얼어붙은 협곡 | `#4E4A44` |
| 3막 | 붉은빛 도는 주황 | `#593D34` | 시간의 심연 | `#523A3C` |
| | | | 피의 사냥터 | `#5E3A30` |
| | | | 뒤틀린 성채 | `#54403A` |

바닥 채도는 세 막 모두 0.45 이하다(1막 0.29 · 2막 0.32 · 3막 0.42).

### 2.3 예고 색과 대비

막마다 예고를 **밝기를 올린 붉은 계열 + 어두운 겹 + 밝은 테두리**로 그린다.

| 막 | 채움 `tele_fill` | 테두리 `tele_edge` | 어두운 겹 `tele_dark` |
| --- | --- | --- | --- |
| 1막 | `#FF5A46` | `#FFB08A` | `#180B07` |
| 2막 | `#FF8A5C` | `#FFC9A8` | `#180B07` |
| 3막 | `#FF7A50` | `#FFD6BC` | `#180B07` |

측정한 상대 명도비(WCAG). 배경은 **비네트 중앙까지 얹은 실제 색**으로 잰다 — 화면에서 배경이 가장 밝아지는 곳이 예고에 가장 불리하기 때문이다.

| 막 | 테마 | 실제 배경 | 채움 | 테두리 | 채움 합성(α0.55) | 어두운 겹 대 테두리 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 사냥 숲 | `#38472E` | 3.22 | 5.59 | 1.83 | 10.85 |
| 1 | 버려진 요새 | `#3C4631` | 3.21 | 5.58 | 1.84 | 10.85 |
| 1 | 포자 정원 | `#354732` | 3.23 | 5.62 | 1.83 | 10.85 |
| 2 | 붉은 의식터 | `#5E4939` | 3.63 | 5.69 | 2.12 | 13.00 |
| 2 | 무너지는 광산 | `#574B3B` | 3.67 | 5.76 | 2.13 | 13.00 |
| 2 | 얼어붙은 협곡 | `#574E41` | 3.52 | 5.52 | 2.07 | 13.00 |
| **3** | **시간의 심연** | `#583A3E` | **3.91** | **7.48** | **2.21** | 14.31 |
| **3** | **피의 사냥터** | `#643C30` | **3.68** | **7.03** | **2.14** | 14.31 |
| **3** | **뒤틀린 성채** | `#5C4038` | **3.62** | **6.93** | **2.11** | 14.31 |

기준(`palette.json`의 `contrast`): 채움 ≥ 3.0 · 테두리 ≥ 4.5 · 합성 ≥ 1.7 · 어두운 겹 ≥ 7.0, 3막 테두리는 ≥ 6.0.
**3막이 세 막 중 테두리 대비가 가장 높다**(6.93~7.48 대 1막 5.58 · 2막 5.52). 붉은 배경 위에서 붉은 예고가 가장 안 묻힌다.

### 2.4 형태 대비

명도만으로 부족할 때를 대비해 확정된 예고는 **두 겹 테두리**로 그린다(`PRender.tel_stroke_*`).

- 먼저 `tele_dark`를 3px 더 굵게 깔고, 그 위에 `tele_edge`를 얹는다 → 배경이 밝든 붉든 윤곽이 남는다.
- `!` 표식도 검은 외곽선을 함께 그린다(`tel_bang`).
- 예고 문구는 `tele_label` 색 + 외곽선.
- 위험 장판 예고(`hazard`)도 같은 두 겹 점선을 쓴다.

---

## 3. 검사

| 검사 | 파일 | 확인하는 것 |
| --- | --- | --- |
| `palette_tests` | `tests/palette_tests.gd` | 정본이 테마 목록과 1:1, 막 색감 방향, 테마 차이 보존, **예고 대비 수치**, 하드코딩 없음, 세 막 실제 그리기 |
| `hit_feel_tests` | `tests/hit_feel_tests.gd` | 적중·사망 연출, 기술별 소리 5갈래, **장판 틱 흔들림 0**, 상한·잦아듦, 끄기 옵션, 전역 정지 없음, **연출 유무로 결과 동일**, 그리기 순서 |
| `hud_tests`(추가분) | `tests/hud_tests.gd` | 화면 4종에서 경기장(예고 면)이 잘리지 않고 HUD가 덮는 비율이 15% 이내 |

실행:

```
python tools/run_suites.py --suites palette_tests,hit_feel_tests --jobs 1 --allow-adhoc
python tools/run_suites.py --suites hud_tests,input_tests,ui_flow_tests,run_tests --jobs 1
```

---

## 4. 규칙·범위 밖이라 손대지 않은 것

1. **설정 화면의 '화면 흔들림' 끄기 상자** — `scripts/game/ui/settings_panel.gd`(수정 금지)에 아래를 넣으면 끝난다.
   ```gdscript
   var _shake := CheckBox.new()
   _shake.text = "강한 타격 시 화면 흔들림"
   _shake.button_pressed = PRender.shake_on()
   _shake.toggled.connect(func(on: bool): PRender.set_shake(on))
   v.add_child(_shake)
   ```
   지금은 `PRender.set_shake()`와 환경 변수 `PROPHECY_NO_SHAKE=1`로만 끌 수 있다.

2. **규칙 파일 변경은 필요 없었다.** 적중(`hit{crit}`)·발사(`swing{form}`·`shoot`)·점멸(`e.flash`)·사망(`death` 연출, `kill`·`boss_down`)이 이미 다 있어서 새 신호를 넣지 않았다.
