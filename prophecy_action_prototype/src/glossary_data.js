// 용어 사전 데이터(v0.8). 규칙 수치는 여기서 다시 쓰지 않고 데이터(PA.SHOP·PA.EQUIPMENT·PA.WEAPONS·PA.CONFIG)에서 읽는다(화면과 사전이 같은 값).
// 본문 안의 {{id}}는 다른 용어로의 연결(중첩 툴팁). related는 하단 '관련' 목록.
var PA = (typeof PA !== 'undefined') ? PA : {};
PA.GLOSSARY_STATIC = {
  auto_skill: { name: '자동기술', short: '자동으로 발동하는 공격 기술(검격·관통창·회전 칼날 등)', body: () => `레벨업·상점으로 얻고 최대 ${PA.GROWTH.SLOTS.weapons}개, 각 Lv${PA.GROWTH.SLOTS.weaponMax}까지, {{mod}} ${PA.GROWTH.SLOTS.weaponMods}개까지. 장비 무기({{equipment}})와 다르다: 자동기술은 성장하고, 장비는 사고파는 물건이다.`, related: ['mod', 'swap', 'forge'] },
  equipment: { name: '장비', short: '무기·방어구·방패 슬롯에 1개씩 끼우는 이번 회차 한정 물건', body: () => `상점에서 사고(무기 ${PA.SHOP.price.weapon} · 방어구 ${PA.SHOP.price.armor} · 방패 ${PA.SHOP.price.shield}), 판매가는 ${PA.SHOP.sellPrice.weapon}/${PA.SHOP.sellPrice.armor}/${PA.SHOP.sellPrice.shield}. 거점에서 무료로 바꾸고, 출격 중에는 못 바꾼다. 같은 장비는 두 번 살 수 없다. 회차가 끝나면 사라진다({{bag}}).`, related: ['bag', 'shop'] },
  bag: { name: '가방', short: '장착하지 않은 장비 보관', body: () => '구매 시 "보관"을 고르면 가방으로 간다. 장착하면 같은 슬롯의 기존 장비가 가방으로 들어간다. 가방의 장비는 언제든 판매할 수 있다.', related: ['equipment'] },
  mod: { name: '개조', short: '자동기술 하나에 붙는 전용 방식(최대 2개)', body: () => `레벨업 제시 또는 {{steer}}로 얻는다. 대장간에서 ${PA.SHOP.modChange}금(또는 {{voucher}})으로 같은 기술의 다른 개조로 바꿀 수 있다. 후보가 없으면 아무것도 차감되지 않는다.`, related: ['auto_skill', 'variant'] },
  variant: { name: '변형', short: 'Q(감속장)·E 기술의 방식 1개', body: () => `기술당 1개. 대장간에서 ${PA.SHOP.variantChange}금(또는 {{voucher}})으로 E 변형을 바꿀 수 있다.`, related: ['slowfield', 'e_skill'] },
  slowfield: { name: '감속장(Q)', short: '주변 적을 느리게 하는 수동 기술', body: () => `Lv${PA.GROWTH.SLOTS.skillMax}까지, 변형 1개. 안에 있는 적은 느려진다(지속 피해는 늘지 않는다). 시간술사의 지팡이·시간의 방패는 감속장 안을 조건으로 쓴다.`, related: ['variant', 'e_skill'] },
  e_skill: { name: 'E 기술', short: '선택 수동 기술 1개(돌풍·칼날 폭풍·낙뢰·중력핵·수호 결계)', body: () => `레벨업 또는 상점(${PA.SHOP.newE}금)으로 얻는다. Lv${PA.GROWTH.SLOTS.skillMax}까지, 변형 1개.`, related: ['variant', 'swap'] },
  common: { name: '공용 증강', short: '여러 자동기술에 걸치는 증강(냉기·넓어진 공격 등)', body: () => `최대 ${PA.GROWTH.SLOTS.commons}종. 적용 대상이 있는 기술이 하나도 없으면 효과가 없다(교체 확인 화면에 경고가 뜬다).`, related: ['auto_skill', 'swap'] },
  passive: { name: '패시브', short: '항상 적용되는 능력(숙련·가속·활력 등)', body: () => `최대 ${PA.GROWTH.SLOTS.passives}종, 각 3단계.`, related: [] },
  timeslot: { name: '시간대', short: '하루는 새벽·아침·점심·오후·저녁 5칸', body: () => `출격은 장소마다 1~2칸, 더 깊이 +${PA.CONFIG.DEEP_EXPLORE_HOURS}칸, 휴식 ${PA.CONFIG.REST_HOURS}칸. 상점·대장간·장비 교체는 시간을 쓰지 않는다. 출발 시간대에 따라 편성·보상이 바뀌는 {{variant_slot}}이 있다.`, related: ['variant_slot', 'rest', 'endday'] },
  variant_slot: { name: '시간대 변주', short: '특정 시간대에 출발하면 편성·사건·보상이 바뀜', body: () => '장소 카드에 "지금 출발하면" 표시로 미리 보인다. 출발 시점에 확정되고, 하루 시작에 예정이 공개된다. 모든 시간대에 같은 배율을 주지 않는다.', related: ['timeslot'] },
  rest: { name: '휴식', short: '1칸을 쓰고 체력 완전 회복', body: () => '체력이 가득해도 다음 시간대로 넘기기 위해 쓸 수 있다(별도 대기 버튼 없음). 무료 휴식권이 있으면 시간을 쓰지 않는다.', related: ['timeslot', 'voucher'] },
  endday: { name: '하루 종료', short: '남은 칸을 버리고 다음 날 새벽으로', body: () => '체력이 완전히 회복된다. 넘기기 전에 내일의 장소 2곳과 핵심 위험을 보여 준다. 보스 관문은 휴식·하루 종료로 건너뛸 수 없다.', related: ['timeslot', 'boss_gate'] },
  deep: { name: '더 깊이', short: '승리 뒤 같은 장소를 한 번 더(적 +1, 정예 추가)', body: () => `출격당 1회, +${PA.CONFIG.DEEP_EXPLORE_HOURS}칸. 들어가기 전에 추가 시간·적 변화·확정 보상·걸린 전리품이 표시된다. 이기면 표시된 보상이 미정산 전리품에 얹히고 귀환만 할 수 있다. 지면 {{defeat}}.`, related: ['loot', 'defeat'] },
  loot: { name: '전리품 정산', short: '출격 중 얻은 것은 귀환해야 확정', body: () => '"전리품을 가지고 귀환"을 누르면 금화·재료·장비·이용권·성장 예약이 거점에 반영된다(정확히 1회). 정산 전에 지면 모두 잃는다. 시작한 전투에서 안전하게 물러날 수는 없다(포기 = 패배).', related: ['deep', 'defeat'] },
  defeat: { name: '패배', short: '미정산 전리품과 남은 하루를 잃고 구조됨', body: () => '다음 날 새벽에 정상 체력으로 시작한다. 이미 정산한 금화·장비·레벨·성장은 그대로. 낮은 체력 페널티는 따로 없다. 보스전 패배는 다르다: {{boss_gate}}.', related: ['loot', 'boss_gate'] },
  boss_gate: { name: '보스 관문', short: '3·5·7일차 시작에 오는 보스전(하루 시간 밖)', body: () => '입장 시점의 상태로 재도전한다(하루 손실 없음, 처치 경험치·보상 중복 없음). 이기면 그날의 시간대가 새벽부터 시작된다.', related: ['defeat', 'forge'] },
  steer: { name: '성장 예약', short: '다음 자연 레벨업의 제시 종류를 정하는 임무 보상', body: () => '사냥→자동기술 레벨, 제단→개조, 봉인→Q/E, 구조→서비스 3택(즉시). 예약은 1개만 유지되고, 이미 있으면 새 임무 보상은 금화로 대체된다(조용히 덮어쓰지 않음). 이미 열린 제시에는 적용되지 않고, 후보가 없으면 금화로 대체된다. 추가 레벨업을 주지 않는다.', related: ['mission', 'auto_skill'] },
  mission: { name: '임무', short: '목표가 있는 출격(사냥·제단·봉인·구조)', body: () => '2일차부터. 사냥은 정예 전부 + 실제로 등장한 지원병까지 처치. 제단·봉인·구조는 목표 달성으로 끝난다. 3일차부터 위험 조건이 붙을 수 있다. 완료 보상은 {{steer}}.', related: ['steer', 'elite'] },
  elite: { name: '정예', short: '우두머리급 적(가시갈기 늑대 등). 전부 처치해야 종료', body: () => `전멸 조건은 웨이브·대기 중인 적을 모두 포함한다. 4일차부터 정예 체력 ×${PA.ELITE_DAY_MULT.mult}(시험값).`, related: ['mission'] },
  swap: { name: '기술 교체', short: '보유 자동기술/E를 다른 기술로(레벨·개조 수 보존)', body: () => `비용 ${PA.SHOP.swap.base} + (레벨−1)×${PA.SHOP.swap.perLevel} + 개조 수×${PA.SHOP.swap.perMod}. 새 개조는 새 기술 목록에서 고른다. 옛 기술은 남지 않는다. 확정 전 취소하면 아무것도 바뀌지 않는다.`, related: ['auto_skill', 'shop'] },
  forge: { name: '공용 공격 강화', short: '대장간 서비스: 모든 자동기술 피해 ×1.1/1.2/1.3', body: () => `${PA.SHOP.forge.map(f => `${f.lv}단계 ${f.cost}금${f.afterBoss ? `(보스 ${f.afterBoss} 처치 후)` : ''}`).join(' · ')}. 장비 무기와 무관하다.`, related: ['shop', 'boss_gate'] },
  shop: { name: '상점', short: '하루 시드 재고: 장비 2 + 자동기술 또는 E 1', body: () => `다시 열거나 불러와도 같은 재고. 날짜로 가격이 오르지 않는다. 새 자동기술 ${PA.SHOP.newSkill}금, 새 E ${PA.SHOP.newE}금(Lv1, 빈 슬롯). {{merchant}}는 정해진 날 점심부터 온다.`, related: ['equipment', 'swap', 'forge', 'merchant'] },
  merchant: { name: '방문 상인', short: '2·4·6일차 점심부터 하루 끝까지 특별 재고', body: () => `장비 1개 ${Math.round(PA.SHOP.merchantDiscount * 100)}% 할인 + 무료 휴식권. 재고는 갱신되지 않는다.`, related: ['shop'] },
  voucher: { name: '이용권', short: '무료 휴식권·상인 할인권·개조 교체권·제시 재선택권', body: () => '임무(구조)·사건·심층 보상으로 얻는다. 비용 차감 전에 적용되고, 취소하면 소모되지 않는다.', related: ['rest', 'mod'] },
  direct: { name: '직접 피해', short: '자동기술의 타격·투사체 적중 피해', body: () => '장비의 "직접 피해" 조건은 여기에만 적용된다. {{dot}}·{{zone}}·추가 효과(파열·흔적)는 직접 피해가 아니다.', related: ['dot', 'zone'] },
  dot: { name: '지속 피해', short: '화상·출혈처럼 시간에 따라 들어가는 피해', body: () => '같은 종류는 중첩되지 않고 지속 시간만 갱신된다(출혈은 더 높은 dps로만 대체). 0.5초마다 한 번, 감속장 안에서도 늘지 않는다. 잔불검은 자기 화상·출혈의 지속만 늘린다.', related: ['direct'] },
  zone: { name: '바닥 지대', short: '불길·지뢰·서리 지대처럼 자리에 남는 피해', body: () => '지대에서 나온 피해는 직접 피해가 아니고, 장애물 뒤에도 적용된다.', related: ['direct'] },
  effective: { name: '유효 피해', short: '실제 체력 감소량(과잉 피해 제외)', body: () => '피해 통계의 모든 값은 유효 피해다. 출처는 직접·지속·지대·Q/E·추가 효과로 나뉘고 한 번만 집계된다.', related: ['dps'] },
  dps: { name: 'DPS', short: '유효 피해 ÷ 그 기술을 보유한 실제 전투 시간', body: () => '전투 시간은 메뉴·일시정지·선택 화면을 제외한다. 기술의 보유 시간은 획득 시점부터 제거 시점까지("공격 중일 때만"이 아님). 방어·회복·감속은 피해가 아니므로 포함하지 않는다.', related: ['effective'] },
  dodge: { name: '회피(Space)', short: '짧은 무적 구르기', body: () => `${PA.CONFIG.PLAYER.dodge.duration || 0.26}초 무적. 회피 성공에 보상이 붙는 성장 축은 없다.`, related: [] },
  exposed: { name: '빈틈', short: '큰 공격 뒤 적이 드러내는 순간(피해 배율)', body: () => `빈틈 상태의 적에게 주는 피해 ×${PA.CONFIG.PLAYER.exposedMult}.`, related: ['direct'] },
};
// 데이터에서 생성되는 용어: 장비 12종, 자동기술, E 기술
PA.glossaryAll = function () {
  const out = Object.assign({}, PA.GLOSSARY_STATIC);
  for (const id in PA.EQUIPMENT) { const d = PA.EQUIPMENT[id]; out['eq:' + id] = { name: d.name, short: d.short, body: () => `${d.desc} 슬롯: ${PA.EQUIP_SLOT_NAMES[d.slot]} · 가격 ${PA.SHOP.price[d.slot]} · 판매 ${PA.SHOP.sellPrice[d.slot]}. {{equipment}}`, related: ['equipment'] }; }
  for (const id in PA.WEAPONS) { const d = PA.WEAPONS[id]; if (!d.impl) continue; out['w:' + id] = { name: d.name, short: d.desc, body: () => `{{auto_skill}} · 기본 피해 ${d.base.damage} · 주기 ${d.base.interval}초${d.base.range ? ' · 사거리 ' + d.base.range : ''}${d.base.radius ? ' · 반지름 ' + d.base.radius : ''}. 개조: ${Object.values(d.mods).filter(m => m.impl).map(m => m.name + '(' + m.desc + ')').join(', ')}.${id === 'spear' ? ' 약점: 사거리 45% 안쪽은 피해 ×0.5(시험값) — 붙은 적에게 약하다.' : ''}${id === 'blades' ? ' 판정: 중심 근처부터 칼날 끝까지의 살. 붙은 적도 맞는다.' : ''}`, related: ['auto_skill', 'mod'] }; }
  for (const id of PA.E_SKILLS) { const d = PA.SKILLS[id]; if (!d.impl) continue; out['e:' + id] = { name: d.name + '(E)', short: d.desc, body: () => `{{e_skill}} · 재사용 ${d.cooldown.join('/')}초. 변형: ${Object.values(d.variants || {}).filter(v => v.impl).map(v => v.name + '(' + v.desc + ')').join(', ') || '없음'}.`, related: ['e_skill', 'variant'] }; }
  return out;
};
