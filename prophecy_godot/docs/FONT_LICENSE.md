# 화면 글꼴 — 무엇을 왜 골랐고, 라이선스가 무엇인가

**한 줄 요약.** 화면 글꼴은 **Noto Sans KR Regular**(SIL Open Font License 1.1)의 **부분집합**이고,
파일은 `assets/fonts/ui.ttf`, 라이선스 전문은 `assets/fonts/OFL.txt`에 있으며 **두 파일 모두 웹·윈도우 빌드에 함께 나간다.**

---

## 1. 왜 넣었나

웹(브라우저) 빌드에는 운영체제 글꼴이 없다. 글꼴 파일이 프로젝트에 없으면 엔진이 기본 글꼴로 그리는데
그 글꼴에는 한글이 없어서 **제목·메뉴·전투 HUD·터치 조작까지 글자가 전부 네모(□)로 나온다.**
PC에서는 엔진이 운영체제 글꼴을 대신 써 주기 때문에 문제가 드러나지 않는다.

원래 방침은 "제3자 글꼴 파일은 저장소에 넣지 않는다"였으나(옛 `docs/WEB_BUILD.md` §2, `.gitignore`),
**2026-09-09에 사용자가 그 방침을 바꿨다** — 재배포 가능한 글꼴을 골라 빌드에 넣고 라이선스 고지도 함께 넣는다.
사용자가 글꼴을 직접 설치하게 하지 않는다.

## 2. 고른 글꼴

| 항목 | 값 |
| --- | --- |
| 이름 | **Noto Sans KR**, Regular |
| 판 | `Version 2.004-H2` (`makeotfexe 2.5.65603` 로 만든 Adobe 빌드) |
| 저작권 | `(c) 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.` |
| 라이선스 | **SIL Open Font License, Version 1.1** — 글꼴 파일 자체의 이름표(name table)에 적혀 있다: nameID 13 = `This Font Software is licensed under the SIL Open Font License, Version 1.1…`, nameID 14 = `http://scripts.sil.org/OFL` |
| 가져온 곳 | 이 PC에 이미 설치돼 있던 `C:\Windows\Fonts\NotoSansKR-Regular.ttf` |
| 전문 출처 | 라이선스 전문은 SIL 공식 문서 `https://openfontlicense.org/documents/OFL.txt` 에서 받아 `assets/fonts/OFL.txt`에 저장했다 |

**왜 이것인가.** OFL 1.1은 "글꼴을 소프트웨어와 함께 묶어 재배포·판매해도 된다"고 명시한다(단독 판매만 금지).
글꼴 파일 스스로가 OFL 1.1임을 밝히고 있어 재배포 허용 여부에 다툼의 여지가 없다.

**나눔고딕은 쓰지 않았다.** 이 PC의 `NanumGothic.ttf`(v3.020)는 이름표의 라이선스 칸에 `NHN Corporation`만 적혀 있고
OFL이라고 밝히지 않는다. 재배포 근거가 파일 안에 없어 후보에서 뺐다.

**계정·결제는 쓰지 않았다.** 유료 가입·자격 증명이 필요한 배포처는 쓰지 않았다.

## 3. 부분집합(subset) — 무엇을 남기고 무엇을 뺐나

원본 6,192,764바이트(24,868 글리프)를 그대로 넣으면 웹 빌드가 무거워진다.
**한자(CJK 통합 한자) 8,138자를 버리고 한글은 하나도 버리지 않는** 부분집합을 만들었다.

| | 원본 | 부분집합 |
| --- | ---: | ---: |
| 파일 크기 | 6,192,764 | **2,550,812** (−58.8%) |
| 코드포인트 수 | 23,174 | 12,128 |
| **현대 한글 음절** | 11,172 | **11,172 (전부 유지)** |
| 한자 | 8,138 | 0 |

### 남긴 범위 (이 목록 밖의 글자는 네모로 나온다)

```
U+0020-007E  기본 라틴(ASCII)
U+00A0-00FF  라틴-1 보충            (§ ° ± ² µ · × ÷ Ø …)
U+0100-017F  라틴 확장-A
U+0370-03FF  그리스               (Σ α π …)
U+2010-206F  일반 구두점            (— ‘ ’ “ ” • … ‰)
U+2070-209F  위·아래 첨자
U+20A0-20BF  통화 기호
U+2100-214F  문자꼴 기호
U+2190-21FF  화살표                (← → ↔)
U+2200-22FF  수학 연산자            (∈ − √ ≈ ≠ ≤ ≥ ⊕)
U+2460-24FF  둘러싼 영숫자          (① … ⑫ ⓐ ⓑ ⓒ)
U+2500-257F  괘선                  (└ ├ …)
U+25A0-25FF  기하 도형              (■ □ ▶ ▼ ○ ●)
U+2600-26FF  기타 기호              (★)
U+3000-303F  한중일 기호·구두점      (〃 「 」)
U+3130-318F  한글 호환 자모          (ㄱ ㄴ ㄷ … ㅏ ㅑ)
U+AC00-D7A3  한글 음절 11,172자 전부
```

### 다시 만드는 방법

```
pip install fonttools
python -m fontTools.subset "C:\Windows\Fonts\NotoSansKR-Regular.ttf" ^
  --unicodes=U+0020-007E,U+00A0-00FF,U+0100-017F,U+0370-03FF,U+2010-206F,U+2070-209F,U+20A0-20BF,U+2100-214F,U+2190-21FF,U+2200-22FF,U+2460-24FF,U+2500-257F,U+25A0-25FF,U+2600-26FF,U+3000-303F,U+3130-318F,U+AC00-D7A3 ^
  --output-file=prophecy_godot/assets/fonts/ui.ttf ^
  --name-IDs=* --layout-features=* --drop-tables+=vhea,vmtx --no-hinting --desubroutinize --recalc-bounds
```

`--name-IDs=*` 가 중요하다. 이것이 없으면 저작권(nameID 0)과 라이선스(nameID 13·14) 칸이 잘려 나간다.
지금 파일에는 두 칸이 원본 그대로 들어 있다.

### 빠진 글자 때문에 생길 수 있는 일

- **한글은 빠진 것이 없다.** 현대 한글 음절 11,172자를 전부 담았다(`tests/font_tests.gd`가 한 자씩 단언한다).
- **한자는 화면에 못 쓴다.** 지금 프로젝트에서 한자는 주석에만 있고(`render.gd`의 `종(鐘)`,
  `tools/frame_path_audit.gd`의 `每frame`) 화면 글자에는 없다. 화면에 한자를 쓰려면 범위를 늘려 다시 만들어야 한다.
- **원본 Noto Sans KR에 처음부터 없는 기호**가 몇 개 있다: `▸` `▾` `☠` `⛔` `↳`.
  부분집합 때문이 아니라 원본에 없다. 화면 글자에서는 이미 `▶` `▼` `독` 등으로 바꿔 두었고,
  `tests/font_tests.gd`가 "이 기호를 화면 글자에 다시 쓰지 않았는지"를 회귀로 막는다.

## 4. OFL 1.1이 요구하는 것과, 그것을 어떻게 지켰나

| OFL 1.1 조항 | 지킨 방법 |
| --- | --- |
| 2) 배포하는 사본마다 저작권 표시와 라이선스를 함께 담을 것 | ① 글꼴 파일 안 이름표(nameID 0·13·14)가 그대로 살아 있다. ② `assets/fonts/OFL.txt`에 전문을 두고 **웹·윈도우 두 내보내기의 포함 목록**(`export_presets.cfg`의 `include_filter="assets/fonts/*.txt"`)에 넣어 빌드에 함께 나가게 했다. ③ 게임 화면에도 고지를 띄운다(아래) |
| 3) 수정본은 예약 글꼴 이름(Reserved Font Name)을 쓰지 말 것 | 이 글꼴의 예약 이름은 **`Source`** 다. 우리 파일 이름은 `Noto Sans KR`이라 예약 이름을 쓰지 않는다. `OFL.txt` 머리말에도 이 사본이 부분집합(수정본)이라는 사실과 함께 명시했다 |
| 1) 글꼴만 따로 팔지 말 것 | 게임과 함께 묶여 나갈 뿐 따로 배포·판매하지 않는다 |
| 5) 전체를 이 라이선스로만 배포할 것 | 글꼴 파일과 그 부분집합에만 해당한다. 게임 코드에는 적용되지 않는다(OFL은 "글꼴로 만든 문서"에는 미치지 않는다) |

### 게임 안에서 보이는 고지

- **제목 화면 맨 아래 한 줄**: `글꼴 Noto Sans KR · OFL 1.1` (`PUi.font_notice_short()`)
- **설정 화면**: `글꼴 Noto Sans KR (c) 2014-2021 Adobe · SIL Open Font License 1.1` 과
  전문 위치 `res://assets/fonts/OFL.txt` (`PUi.font_notice()` · `PUi.font_license_path()`)
- 정본 문자열은 `scripts/game/game.gd`의 상수 `UI_FONT_NOTICE` · `UI_FONT_NOTICE_SHORT` 하나뿐이다.
- 그림: `docs/captures/web_font_9bd00bd/02_settings_font_license.png`

## 5. 프로젝트에 붙인 방법

| 자리 | 무엇 |
| --- | --- |
| `assets/fonts/ui.ttf` | 글꼴 파일(부분집합). 저장소에 함께 커밋한다 |
| `assets/fonts/ui.ttf.import` | Godot 가져오기 표식. **이것이 없으면 내보내기에 담기지 않는다** |
| `assets/fonts/OFL.txt` | 라이선스 전문 |
| `project.godot` → `[gui] theme/custom_font` | 엔진 시작 때 기본 테마의 글꼴과 `ThemeDB.fallback_font`를 함께 채운다. **이것 하나로 화면 전체가 바뀐다**(헤드리스 시험에서 확인) |
| `scripts/game/game.gd` → `_apply_ui_font()` | 같은 값을 코드에서 한 번 더 못 박는다(기본 테마 `default_font` + `ThemeDB.fallback_font`). 파일이 없으면 아무것도 하지 않는다 |
| `export_presets.cfg` → 두 프리셋의 `include_filter` | `.ttf`는 `export_filter="all_resources"`가 알아서 담지만 **`.txt`는 담지 않는다**(실제 `index.pck`를 뜯어 확인). 그래서 `assets/fonts/*.txt`를 포함 목록에 적었다 |
| `.gitignore` | `prophecy_godot/assets/fonts/` 제외 규칙을 풀었다 |

글꼴을 읽는 경로가 **두 갈래**라 두 곳을 모두 채워야 한다:

- 기본 테마 `default_font` — `Label`·`Button`·`RichTextLabel` 같은 Control이 읽는다
- `ThemeDB.fallback_font` — 직접 그리는 쪽(`PRender.font()`, `PTouchControls._draw()`)이 읽는다

## 6. 크기에 미친 영향

내보낸 웹 빌드(`index.pck`) 안에서 글꼴이 차지하는 몫:

| 항목 | 바이트 |
| --- | ---: |
| `.godot/imported/ui.ttf-….fontdata` (엔진이 압축해 담은 글꼴) | 1,363,207 |
| `assets/fonts/ui.ttf.import` | 159 |
| `assets/fonts/OFL.txt` | 4,802 |
| **글꼴 때문에 늘어난 값** | **약 1,368,168 (1.30 MB)** |

원본 글꼴(6.2 MB)을 그대로 넣었다면 이 자리가 약 3.85 MB였다(옛 `docs/WEB_BUILD.md` §3 기록).
부분집합으로 **약 2.5 MB를 아꼈다.**

## 7. 무엇이 이것을 지키는가

`tests/font_tests.gd` (`python tools/run_suites.py --suites font_tests --jobs 1`)가 단언한다 —
파일과 가져오기 표식이 있는가 · 현대 한글 11,172자와 화면 기호가 전부 있는가 ·
기본 테마 세 곳(`gui/theme/custom_font` · `default_font` · `fallback_font`)에 붙었는가 ·
두 내보내기 프리셋이 글꼴과 라이선스를 담는가 · 고지가 설정·제목 화면에 실제로 들어가는가 ·
글꼴에 없는 기호를 화면 글자에 쓰지 않았는가.

**눈으로 보는 확인은 이 시험의 몫이 아니다.** 그것은 `docs/captures/web_font_9bd00bd/`에 있다.
