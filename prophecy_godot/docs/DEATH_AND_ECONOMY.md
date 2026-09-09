# 사망과 경제 (사망 = 회차 종료 · 부활 물약 · 판매 · 휴식)

2026-09-09 사용자 확정 사항을 규칙 계층(`scripts/rules/`)에 넣은 결과다.
**화면(마을 UI·확인 창)은 다른 담당이 만든다.** 이 문서의 §6이 화면이 불러야 할 함수 목록이다.

수치는 따로 적지 않은 한 **시험값**이며 사람이 승인한 균형이 아니다.
사용자가 확정한 값에는 **[확정]**, 아직 합의가 없어 이쪽에서 정한 기본안에는 **[시험 규칙]**을 붙였다.

> 2026-09-09 2차 확정: **마지막 날(다음 날이 없는 날)의 부활**이 결정 항목에서 [확정]으로 옮겨졌다(§2 "마지막 날").
> 물약 1개를 쓰고 날짜를 늘리지 않은 채 같은 날 관문 앞에서 체력 25%로 서며, 그날 남은 시간은 전부 소진한다.
> 반복 부활은 매번 물약 1개다. 화면·사망 화면 문구도 이때 함께 넣었다.

---

## 1. 사망 = 회차 종료 [확정]

부활 수단이 없으면 **일반 전투·보스전 모두** 쓰러진 그 자리에서 회차가 끝난다.

없어진 것(옛 규칙):

| 옛 규칙 | 지금 |
|---|---|
| 일반 패배 뒤 무료 체력 회복 + 다음 날 진행 | 없다. 부활 물약이 없으면 회차 종료 |
| 보스 패배 뒤 무료 전투 상태 복원(입장 스냅샷) + 무제한 재도전 | 없다. 부활 물약이 없으면 회차 종료 |

끝난 회차의 상태:

* `run.phase == "dead"`, `run.ended == true`, `run.hours == 0`, `run.hp == 0`
* **완주(`phase == "cleared"`)와 구분된다.** `PRun.is_run_over(run)`이 사망만 true다.
* `PFlow.actions(run)`은 **빈 배열**을 돌려준다(휴식·하루 종료·출격·상점 전부 없음).
* 이미 정산한 금화·재료·장비와 레벨·성장은 그대로 남는다. 회차만 끝난다.
* `run.death = { key, cause("sortie"|"boss"), day, stage, count, seq, regionId, bossId, revived, endedRun, nextDay, sameDay, hp }`
  * `sameDay`가 true면 **마지막 날 부활**이다(날짜를 늘리지 않고 같은 날 관문 앞). 화면은 이 값으로 문구를 고른다.
* `run.reviveUses = { count: int }` — 이 회차에서 부활 물약을 실제로 쓴 횟수. 저장에 남으므로 이어하기로 되돌아가지 않는다
  (`PRun.revive_uses(run)`. dict 안의 `count`는 `PSave`가 정수로 정규화하는 키라 저장 정규화 표를 건드리지 않는다 — `bossEntries`와 같은 방식).

## 2. 부활 물약 [확정]

`data/consumables.json`의 `revive` 항목(id `revive_potion`, 값 **220** — 시험값).

* **보유했을 때만** 자동으로 **한 개**가 소모된다. 쓸지 말지 묻지 않는다(사망 정산에서 즉시).
* **남은 하루를 잃고, 다음 날 최대 체력 25%**(`hpFrac`)로 부활한다.
  **마지막 날에는 날짜를 늘리지 않고 같은 날 관문 앞**에서 같은 체력으로 선다(아래 "마지막 날" 항목).
* 상세 설명(`data/consumables.json`의 `revive.short`·`revive.desc`·`revive.lastDayShort`)이 마지막 날 동작을 적어 둔다 —
  사람이 **사기 전에** 알 수 있어야 한다. 화면이 쓸 한 줄은 `PConsumables.revive_when_line(run)`이 날짜에 맞춰 준다.
* **죽은 출격의 미정산 전리품은 잃는다.** 이미 확보한 성장·정산 보상은 남는다.
* 가방 상한 2개(`rules.reviveCarryMax`). 준비물·회복약과 **별도 계정**이라 서로의 상한을 먹지 않는다.
* 하루 구매 상한은 없다(회복약과 달리 값 자체가 상한 역할).

### 중복·복제 방지(검사로 못박음 — `tests/death_tests.gd`)

1. **사망 정산은 정확히 1회.** `PRun.settle_death`가 `run.death.key`로 같은 사망을 걸러 낸다.
   키는 일반 출격이 `sortie:<출격 순번>:<조우 순번>`, 관문이 `boss:<관문 입장 순번>:<단계>`다
   (관문 입장 순번 = `run.bossEntries.count`, `PRun.start_boss`에서 1 증가).
   같은 사망을 `PFlow.settle_defeat` → `PRun.defeat` → `PRun.settle_death` 순서로 몇 번 넘겨도 물약은 한 개만 빠지고 하루도 한 번만 지나간다.
2. **입장 스냅샷이 물약을 되살리지 않는다.** 사망 정산 경로는 `run.bossEntry`를 **복구하지 않고 지운다**.
   스냅샷 복구(`PConsumables.restore`)는 시험 재시도 경로에만 남아 있다(§5).
3. **계속하기(저장 복구)로 되살아나지 않는다.** 소모는 정산과 같은 회차 상태에 즉시 반영되고, 화면이 그 뒤 저장한다.
   **개수(`run.consumables`)와 사용 횟수(`run.reviveUses.count`) 둘 다** 저장·복구를 그대로 견딘다 —
   `tests/death_tests.gd` §11이 저장 왕복을 거친 회차로 그 뒤의 사망까지 이어서 검사한다.

### 경계 규칙

* [확정] 부활해도 **미완료 관문을 건너뛰지 않고 다음 막을 해금하지 않는다.**
  관문일에 죽어 부활하면 다시 선 날에도 `phase == "boss_prep"`이고 `run.stage`·`run.bossesDone`은 그대로다.
* [확정] 날짜를 넘긴 뒤에도 미완료 관문이 우선이다. 그 관문을 넘기 전까지 출격(`PRun.can_sortie`)이 잠긴다.
* [시험 규칙] 부활 시각의 체력은 `round(최대 체력 × 0.25)`이며 최소 1이다(비율 0.25는 확정, 반올림·하한 1은 구현 기본안).

### 마지막 날(다음 날이 없는 경우) [확정 — 2026-09-09]

`PRun.has_next_day(run)`가 false인 날(본편 10일차 = 마지막 관문일)에는 "다음 날"이 없다.
**사용자가 확정했다: 물약을 쓰되 날짜를 넘기지 않는다.** 예전의 (가)·(다) 후보는 폐기했다.

* 물약이 **있으면**: 물약 **1개를 소비**하고 **날짜를 늘리지 않은 채 같은 날 관문 앞**(`phase == "boss_prep"`)에 **최대 체력 25%**로 선다.
  **그날 남은 시간은 전부 소진한다**(`run.hours == 0`). 같은 날이므로 장소·카드·상점 재고를 다시 뽑지 않는다.
* 물약이 **없으면**: 회차 종료(다른 날과 같다).
* **부활을 반복하려면 매번 물약을 소비한다.** 관문에 다시 들어가면 `PRun.start_boss`가 `run.bossEntries.count`를 1 올려
  중복 방지 키가 바뀌므로 새 사망으로 정산된다. 한 번 쓰고 무한 재도전이 되는 구멍은 없다.
* 물약이 떨어지면 그다음 죽음이 회차 종료다.

읽는 법: "남은 하루를 잃는다"를 **"그 날의 남은 시간을 잃는다"**로 읽는다. 그래서 물약의 값어치가 회차 어디서나 같고
(마지막 관문 직전에 사도 손해가 아니다) 10일 일정도 늘어나지 않는다. 대신 **마지막 관문은 시간을 쓰지 않고 재도전이 가능**해져
다른 관문보다 관대하다 — 그 대가가 물약 1개(220금)다.

> 남은 관찰(밸런스 판단은 사람 몫): 관문 입장(`PRun.start_boss`)은 원래 **체력을 완전 회복**시키므로,
> 관문에서 죽고 부활한 뒤 다시 입장하면 25% 체력이 그대로 100%가 된다. 즉 관문 사망에서 25%가 실제로 무는 것은 없고,
> 값은 **물약 1개 + 그날 남은 시간**이다. 일반 출격 사망에서는 25%가 그대로 걸린다.
> 마지막 날은 관문 날이라 일반 출격 자체가 잠겨 있어(`PRun.can_sortie`) 마지막 날 사망은 언제나 관문 사망이다.

## 3. 판매 = 구매액의 절반 [확정]

* **구매한 장비**: `floor(실제 지불 금액 × 0.5)`.
* **실제 지불 금액을 개체별로 보존**한다: `run.paidFor[<장비 id>] = { price, from, day }`.
  `PRun.buy_equipment`가 할인(상인 15%·상점 할인권)을 **적용한 뒤의 금액**을 적는다 → 싸게 사서 비싸게 파는 일이 없다.
* **구매액이 없는 장비**(드롭·제작·옛 저장): **정상 기준 구매가의 절반** = `floor(PRun.equip_price(id) × 0.5)`. [시험 규칙 — 사용자가 준 "첫 후보"를 그대로 넣었다]
  * 대안으로 검토할 수 있는 것: **제작품은 재료로 쓴 장비의 지불액 + 수수료를 승계**한다(원가 승계). 지금은 넣지 않았다 — 확정 문구가 "구매액이 없는 장비"로 제작품을 묶었기 때문이다.
* 장비를 팔면 `run.paidFor`에서 그 개체의 기록도 사라진다. 다시 사면 그때 값이 다시 적힌다.
* 제작으로 재료가 된 장비의 기록도 사라진다(완성품은 "구매액 없는 장비"가 된다).
* 옛 고정 판매가표(무기 35·갑옷 30·방패 30)는 `PRun.sell_price(id)`에만 남아 있다. **판매 규칙의 정본은 `PRun.sell_value(run, id)`다.**

### 확인 단계(견적 → 확정)

* 견적 `PRun.sell_quote(run, id)`는 **회차를 전혀 바꾸지 않는다.** 취소 = 그냥 부르지 않으면 된다.
* 견적에 들어 있는 것: 받을 금액(`gold`), 지불액(`paid`, -1이면 구매액 없음), 기준(`basis` = `"paid"`/`"list"`),
  **장착 중이면 해제된다는 사실**(`equipped`·`unequips`), 최대 체력 변화(`hpMax` → `hpMaxAfter`)와 잘린 현재 체력(`hpAfter`),
  그리고 그대로 띄울 수 있는 한 줄(`text`, 예: `"철제 방패을(를) 60금에 판매할까요? (장착 중이라 해제됩니다)"`).
* 확정 `PRun.sell_equipment(run, id, expect_gold)`:
  * 보유하지 않으면 실패 → **두 번 눌러도 한 번만 팔린다**(첫 판매 뒤에는 보유하지 않으므로).
  * `expect_gold >= 0`인데 견적과 다르면 실패 → 확인 창을 띄운 사이 값이 바뀌었으면(저장 복구·다른 경로) 아무것도 하지 않는다.
  * 성공하면: 장착 해제 → 가방에서 제거 → 지불 기록 삭제 → 최대 체력 재적용(`clamp_hp`) → 금화 지급.

## 4. 휴식 [확정]

* 즉시 처리하지 않는다. 견적 `PRun.rest_quote(run)` → 확인 → 확정 `PRun.rest(run)`.
* 견적은 회차를 바꾸지 않는다. **취소하면 상태 변화가 전혀 없다.**
* 견적에 들어 있는 것: 소모 시간 또는 휴식권(`hours`·`useVoucher`·`costText`),
  회복 전후 체력(`hp` → `hpAfter`, `hpMax`, `heal`), 다음 시간대(`slotAfter`), 강제 휴식 여부(`forced`), 한 줄 문구(`text`).
* **휴식권은 100금 유지**(정본 = `data/world.json` `shop.merchantService.free_rest`).
* **표현은 "무료"가 아니라 "시간 소모 없음"이다.** `costText`가 `"시간 소모 없음 (휴식권 1장)"`을 준다 —
  화면은 이 문자열을 쓰고 서비스 이름("무료 휴식권")을 그대로 쓰지 않는다.

## 5. 사람 플레이 경로와 시험 재시도 경로의 분리

사람이 플레이하는 회차는 위 규칙을 그대로 따른다. 자동 진행·측정 도구는 **분리된 재시도 경로**를 쓴다.

* 판정: `PRun.retry_mode(run)` → `run.testRetry`
* 켜는 방법(둘 다 `PRun.new_run` 시점에 정해지고 저장에 남는다):
  1. `PRun.new_run(..., { "test_retry": true })` — 도구·시험이 명시적으로. **opts가 환경 변수보다 우선한다.**
  2. 환경 변수 `PROPHECY_TEST_RETRY=1` — 실제 게임 화면을 자동으로 굴리는 스위트용.
* 켜져 있을 때의 동작 = **옛 규칙 그대로**:
  * 일반 패배 → 미정산 전리품 상실 + 남은 하루 상실 + 다음 날 정상 체력(`PRun.defeat`의 재시도 분기)
  * 보스 패배 → 입장 스냅샷 복구 + 재도전(`PRun.boss_defeat_retry`)
  * 사망 정산 자체가 일어나지 않으므로 **부활 물약을 소모하지 않는다.**
* 회차 봇(`PRunBot.simulate`)은 **기본값이 재시도 경로**다(`max_retries`가 뜻을 잃지 않고 기존 측정값이 흔들리지 않게).
  사람 플레이 규칙으로 재려면 `opts.death_rule = "run_end"`. 그때만 봇이 부활 물약을 산다.
* 어느 스위트가 환경 변수를 쓰는지는 `tools/suites.json`의 `env`/`env_reason`에 적어 두었다:
  `ui_smoke_short` · `ui_smoke_full` · `ui_flow_tests` · `meta_tests` · `meta_ui_tests` · `input_tests` · `hud_tests` · `bot_tests`.
  `death_tests`는 이 환경 없이 **사람 플레이 규칙**을 검증한다(회차도 `test_retry: false`를 명시한다).

## 6. 화면 담당이 부를 함수 (이름 · 인자 · 반환)

### 사망

| 함수 | 인자 | 반환 | 쓰는 곳 |
|---|---|---|---|
| `PRun.is_run_over(run)` | `run: Dictionary` | `bool` | 패배·보스 결과 화면에서 "거점으로" 대신 **회차 결과**로 보낼지 판단 |
| `PRun.retry_mode(run)` | `run` | `bool` | 사람 플레이인지(=재도전 버튼을 아예 감출지) 판단 |
| `PRun.can_revive(run)` | `run` | `bool` | 출격·관문 입장 전 "지금 죽으면 회차가 끝난다" 경고 표시 |
| `PRun.has_next_day(run)` | `run` | `bool` | 마지막 날 경고 문구 |
| `PRun.revived_same_day(run)` | `run` | `bool` | **마지막 날 부활 안내**(다음 날이 아니라 같은 날 관문 앞이라는 문구를 고르는 유일한 근거) |
| `PRun.revive_uses(run)` | `run` | `int` | 이 회차에서 부활 물약을 쓴 횟수(저장에 남는다) |
| `PConsumables.revive_count(run)` | `run` | `int` | HUD·거점의 보유 수 표시 |
| `PConsumables.revive_when_line(run)` | `run` | `String` | 상점·확인 창의 한 줄 안내(오늘이 마지막 날이면 그 동작을 적는다) |
| `run.death` (필드) | — | `Dictionary` | 사망 화면: `cause`·`day`·`revived`·`sameDay`·`count`. `revived`가 true면 부활 안내, false면 회차 종료 안내 |

화면 문구는 **화면 파일 안의 static 함수**가 정본이고, 시험이 화면을 띄우지 않고 같은 함수를 부른다
(같은 문자열을 화면과 시험이 함께 본다 — 문구가 갈라지지 않는다):

| 함수 | 쓰는 곳 |
|---|---|
| `PDefeatScreen.death_lines(run)` · `PDefeatScreen.next_label(run)` | 일반 출격 패배 화면 |
| `PBossResultScreen.defeat_lines(run)` · `retry_label(run)` · `can_retry_now(run)` | 관문 패배 화면 |

`can_retry_now`는 **마지막 날 부활**(과 시험 재시도 경로)에서만 true다 — 그 날은 남은 시간이 0이라 거점에서 할 일이 없으므로
관문으로 바로 들어가는 버튼을 연다. 다음 날 부활은 하루가 통째로 남으므로 거점(준비 화면)을 거치게 둔다.

> 사망 자체는 화면이 부르지 않는다. 기존 경로(`PFlow.settle_defeat` / `PFlow.settle_boss_defeat`)가 그대로 처리한다.
> 저장도 기존 자리 그대로다 — `main.gd`가 정산 직후 `save_run()`을 한 번 부른다.
> **사망 정산과 물약 소모는 그 한 번의 저장 안에서 이미 끝나 있다**(규칙 계층은 파일을 건드리지 않는다).
>
> 화면이 할 일은 **결과를 읽고 다음 화면을 고르는 것**뿐이다:
> * `PRun.is_run_over(run)`가 true → 회차 결과 화면(`run_result`). 거점으로 보내면 안 된다(행동 목록이 비어 있다).
> * false이고 `run.death.revived`가 true → 부활 안내(다음 날 · 체력 25% · 잃은 전리품). 그다음 거점으로.

### 판매(아이템 선택 → 판매 → 확인)

| 함수 | 인자 | 반환 |
|---|---|---|
| `PRun.sell_quote(run, id)` | `run: Dictionary`, `id: String` | `Dictionary { id, name, slot, gold, price(=gold 별칭), paid, basis, equipped, unequips, hp, hpAfter, hpMax, hpMaxAfter, goldAfter, can, reason, text }` |
| `PRun.can_sell_equipment(run, id)` | 〃 | `bool` |
| `PRun.sell_equipment(run, id, expect_gold := -1)` | 〃 + `expect_gold: int` | `bool`(확정 성공) |
| `PRun.sell_value(run, id)` | 〃 | `int`(받을 금액만) |
| `PRun.paid_for(run, id)` | 〃 | `int`(-1 = 구매액 없음) |

확인 창 순서: `sell_quote`로 창을 띄우고 → 사용자가 "예" → `sell_equipment(run, id, int(quote.gold))`.
**`expect_gold`를 반드시 넘겨라.** 창을 띄운 사이 상태가 바뀌었으면 실행되지 않는다.

### 휴식

| 함수 | 인자 | 반환 |
|---|---|---|
| `PRun.rest_quote(run)` | `run` | `Dictionary { can, reason, useVoucher, hours, costText, slotNow, slotAfter, hp, hpAfter, hpMax, heal, voucherLeft, voucherPrice, forced, text }` |
| `PRun.rest(run)` | `run` | `bool`(확정 성공) |

### 부활 물약 구매

| 함수 | 인자 | 반환 |
|---|---|---|
| `PConsumables.revive_id()` | — | `String`(`"revive_potion"`) |
| `PConsumables.revive_def()` | — | `Dictionary { id, name, price, hpFrac, short, desc }` |
| `PConsumables.buy_reason(run, id)` | `run`, `id` | `String`(""이면 살 수 있음 — 화면은 이 문구를 그대로 쓴다) |
| `PConsumables.buy(run, id)` | 〃 | `bool` |

### 행동 목록(화면·봇 공용)

`PFlow.actions(run)`에 아래 항목이 추가/변경되었다. 각 항목의 `data`가 위 견적을 그대로 싣고 있으므로 **화면이 다시 계산하지 않는다.**

| id | kind | data |
|---|---|---|
| `buy_revive` | `buy_revive` | `{ id, price, have }` |
| `sell:<장비 id>` | `sell` | `PRun.sell_quote`의 결과 전체 |
| `rest` | `rest` | `PRun.rest_quote`의 결과 전체 |

## 7. 경제에 대한 메모

* 금화 **수급은 낮추지 않았다.** 새로 생긴 것은 지출처(부활 물약 220)와,
  판매 기준의 변화(정가 구매 장비: 무기 35 → 70, 갑옷·방패 30 → 60. 드롭·제작도 같은 기준)다.
* 중복 드롭의 자동 금화 전환(`PRun.return_to_base`)도 같은 기준(`sell_value`)을 쓴다.
* 새 지출처는 **`PFlow.actions`에 있고 실제로 선택 가능하다** — 봇(`PRunBot._shop_bot`)이 사람 플레이 규칙 회차에서
  실제로 고르는 것을 `tests/death_tests.gd` §10이 검사한다. (예전에 새 지출 경로가 화면에만 있어 봇이 살 수 없던 사고의 재발 방지.)

## 8. 아직 남은 것 / 다른 담당의 몫

* **화면**: 마을 UI의 판매·휴식 확인 창.
  `scripts/game/screens/equip.gd`·`shop.gd`의 판매 버튼은 아직 옛 표(`PRun.sell_price`)를 보여 준다 → `PRun.sell_quote`로 바꿔야 한다.
  (사망 화면 문구와 `boss_result.gd`의 재도전 버튼은 2026-09-09에 끝냈다 — §6의 static 함수들.)
* **필요한데 아직 없는 훅(다른 담당 파일)**: `scripts/game/screens/shop.gd`에 **부활 물약 카드가 없다.**
  준비물·회복약 카드(`_prep_card`·`_potion_card`)는 있는데 부활 물약은 `PFlow.actions`의 `buy_revive`(봇 전용 경로)에만 있어
  **사람이 상점 화면에서 살 방법이 없다.** `_potion_card`와 같은 모양으로 카드를 하나 추가하고
  `PConsumables.revive_def().short` / `revive_when_line(run)` / `revive_def().desc`를 그대로 띄우면 된다
  (그래야 "마지막 날에는 같은 날 관문 앞"이라는 안내가 사람에게 닿는다).
* **`tests/meta_tests.gd`**(다른 담당 소유): 새 판매 규칙과 충돌하는 단언 2건이 남아 있다.
  * `"완성품 판매 = 무기 판매가 35"` → 새 기준으로 **70**(혈월검 = 무기, 정상가 140의 절반).
  * `"행동 목록·장비 이름이 제작품도 처리"`의 `int(a.data.price) == 30` → **60**(월광 갑옷 = 갑옷, 정상가 120의 절반).
