# 주술사의 피해 증폭 저주 (§10, 2026-09-10)

**모든 수치는 첫 시험값이다.** 사람이 재미·밸런스를 확인한 값이 아니다.
정본은 `data/pacing.json` → `enemy_tuning.shaman`, 규칙은 `scripts/rules/enemies_new.gd`.

> 이것은 **일반 주술사(shaman)** 의 변경이다. 특수 정예 **역병 조율사(elite_plaguecaller)** 와 아무 관계가 없다.

## 무엇을 바꿨나

**기존 저주 문양(rune)을 개편했다.** 비슷한 패턴을 새로 하나 더 추가하지 않았다.

| 항목 | 개편 전 | 개편 후(시험값) |
|---|---|---|
| 문양 직접 피해 `runeDamage` | 12 | **0** |
| 적중 효과 | (없음) | **플레이어가 받는 피해 +50%** (`curseAdd` 0.5) |
| 지속 `curseDur` | — | **4초** |
| 예고 `runeAim` | 1.0초 | **0.8초** |
| 개체별 재사용 `runeInterval` | 7초 | **10초** |
| 문양 자리 | 예고 시작에 고정 | **그대로**(따라오지 않는다) |
| 반지름 `runeR` · 사거리 `runeRange` · 빈틈 `runeRecover` | 70 · 340 · 1.2 | **그대로** |

- 여러 주술사가 걸어도 배율은 **×1.5를 넘지 않는다.**
- 재적중하면 남은 시간을 **4초로 갱신**한다(더해서 8초가 되지 않는다).
- **회피 무적·피격 보호를 무시하지 않는다.** 그 둘에 막히면 저주도 걸리지 않는다.

## 상태를 어디에 두는가

플레이어 사전의 **시각 한 칸**뿐이다.

```
st.player["curse_until"] = st.t + curseDur      # 걸릴 때
남은 시간  = max(0, curse_until - st.t)          # 어디서도 따로 줄이지 않는다
```

매 단계 줄여 줄 자리(틱)가 필요 없다 — 그 자리는 담당 밖 파일이기 때문이다.
칸이 하나뿐이라 **여러 주술사가 겹쳐 걸어도 배율이 곱해질 방법이 구조적으로 없다.**

읽는 함수(전부 `PEnemiesNew`):

| 함수 | 뜻 |
|---|---|
| `curse_left(st)` | 남은 초 |
| `curse_on(st)` | 걸려 있는가 |
| `curse_mult(st)` | **피해에 곱할 값**(1.0 또는 1.5) |
| `curse_label(st)` | 화면에 적을 한 줄 — `"저주 · 받는 피해 +50%"` |
| `try_curse(st, e, cx, cy, r)` | 문양이 적중했는가(무적·보호 검사 포함) |

## 곱하는 자리 — **아직 붙지 않았다(담당 밖)**

`scripts/rules/combat_state.gd`는 이번 작업의 **금지 파일**이라 손대지 않았다.
붙일 자리는 **한 곳**이며, `apply_player_damage`의 **등급 배율(tier_dmg) 바로 다음**이다.

```gdscript
func apply_player_damage(amount: float, src: String, attacker = null) -> void:
    ...
    if attacker != null and float(attacker.get("tier_dmg", 1.0)) != 1.0:
        amount = round(amount * float(attacker.tier_dmg) * 10.0) / 10.0
        nominal = amount
    # ↓↓↓ 여기 한 줄 (2026-09-10 §10)
    if PEnemiesNew.curse_on(self):
        amount = round(amount * PEnemiesNew.curse_mult(self) * 10.0) / 10.0
        nominal = amount
    # ↑↑↑
    amount = PSupport.on_player_damage(self, amount, src, attacker)
```

### 왜 그 자리인가 (적용 순서)

| 순서 | 단계 | 저주와의 관계 |
|---|---|---|
| 1 | 등급 배율(`tier_dmg`, 세계 변화) | 저주 **앞** |
| 2 | **저주 ×1.5** ← 붙일 자리 | — |
| 3 | 보조무기 경감(수호 방울 차단 · 가시 갑각) | 저주 **뒤** |
| 4 | 강인함(`toughness`) | 저주 뒤 |
| 5 | 장비 경감(큰 타격 `bigHit` · 감속장 안 `fieldTaken`) | 저주 뒤 |
| 6 | **보호막 흡수**(`shield` · 시전자 방패 · 월광 · 연계 방패) | 저주 뒤 |
| 7 | 체력 차감 | — |

즉 **저주는 늘어난 뒤 → 방패·감소가 그 늘어난 값에 작용한다.**
그래서 보호막이 있으면 저주가 흡수량을 늘리고, 감소 장비가 있으면 저주분도 함께 줄어든다.
"경감 뒤에 곱하면 방패·감소를 무의미하게 만든다"를 피하려고 이 자리를 골랐다.

`nominal`(명목값)도 함께 갱신하는 이유: 장비 '큰 타격'의 자격 판정이 **경감 전 직접 피해**를 보기 때문이다.
저주가 걸린 큰 타격이 자격에서 빠지지 않게 하려면 명목값에도 반영돼야 한다(등급 배율과 같은 처리).

### 지속 피해(장판·불길)와의 관계

`zone_damage()`도 결국 `apply_player_damage`를 부르므로 **같은 한 줄이 그대로 적용된다.**
따로 곱하는 자리를 만들지 않는다 — 그것이 "**실제 피해 처리에 한 번만 적용**"의 근거다.

| 출처 | 어디를 지나가나 | 저주 적용 |
|---|---|---|
| 근접 부채꼴·원형 착탄(`circle_hit`·`arc_hit`) | `damage_player` → `apply_player_damage` | 1회 |
| 적 투사체(화살·저주탄·검기) | `update_projectiles` → `damage_player` → `apply_player_damage` | 1회 |
| 지속 피해(포자 구름·불길 등 장판) | `update_zones` → `zone_damage` → `apply_player_damage` | 1회 |
| 도마뱀 화염(틱 피해) | `damage_player` → `apply_player_damage` | 틱마다 1회 |

**한 번만 적용되는 근거**: 모든 피해가 `apply_player_damage` 하나를 지나가고, 그 안에 곱하는 지점이 하나뿐이다.
`damage_player`(무적·피격 보호 검사)와 `apply_player_damage`(실제 적용)가 나뉘어 있어,
막힌 피해에는 저주가 적용될 기회 자체가 없다.

## 화면 표시

`scripts/game/ui/combat_hud.gd` — 체력 막대 **바로 아래**에 자주색 줄 하나와
`"저주 · 받는 피해 +50% 3.4초"`. 체력(빨강)·보호막(파랑)과 색·자리·글자를 모두 분리했다.
글자와 남은 시간은 **규칙이 내주는 값**(`curse_label` · `curse_left`)만 쓴다 — 화면이 배율을 새로 짓지 않는다.

바닥 예고(`render.gd`)에도 `"저주 문양 0.6s · 받는 피해 +50%"`라고 적어, 맞기 **전에** 무엇이 오는지 읽히게 했다.

## 여러 주술사의 영구 유지 — 별도 관찰

- 개체별 재사용이 **10초**, 지속이 **4초**이므로 주술사 한 마리로는 **최대 40%**의 시간만 걸린다.
- 주술사 셋이 재사용을 완벽히 엇갈리게 쓰면 이론상 계속 걸려 있을 수 있다.
  다만 세 행동(치료·저주탄·문양)이 **공용 간격 `actGap` 1초**를 공유하고, 문양은 사거리 `runeRange` 340 안에서만 쓰며,
  동시 위험 공격 상한(2막 8)도 함께 걸린다.
- 실제 편성에서 주술사 동시 생존 상한은 **2**(2막 기준, `type_alive_cap_proposal.share_by_type.shaman` 0.15)이므로
  **셋이 동시에 살아 있는 편성이 없다.** 둘이면 최대 80% — 영구는 아니다.
- 검사(`tests/elites_tests.gd` §10 다)가 주술사 둘을 붙여 9초를 굴리며 **관찰한 최대 배율이 ×1.5를 넘지 않는지**를 단언한다.
  "몇 %의 시간 동안 걸려 있었는가"는 판정이 아니라 계측으로 남긴다.
