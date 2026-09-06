// v0.8 하루 운영·장소 일정·날짜별 편성·시간대 변화·장비·상점 데이터. 모든 수치는 시험값(docs/ASSUMPTIONS.md). 규칙 자체는 docs/GAME_SPEC.md §19.
var PA = (typeof PA !== 'undefined') ? PA : {};

// ---------- 시간대: 하루 5칸 ----------
PA.TIME_SLOTS = ['새벽', '아침', '점심', '오후', '저녁'];

// ---------- 날짜별 출격 장소(기본 2곳). 6일차 첫 칸은 이전 방문 지역 중 시드로 1곳 ----------
PA.SCHEDULE = {
  places: { 1: ['forest', 'ridge'], 2: ['forest', 'marsh'], 3: ['ridge', 'den'], 4: ['marsh', 'den'], 5: ['den', 'deep'], 6: [null, 'deep'], 7: [] },
  cost: { forest: 1, ridge: 1, marsh: 2, den: 2, deep: 2 }, // 출격 비용(칸). 이동·탐험 비용이며 전투 시간과 무관
  missionFromDay: 2,   // 2일차부터 두 장소 중 1곳에 임무 목적이 붙는다
  riskFromDay: 3,      // 3일차부터 위험 조건 후보
};
// 임무 목적별 '다음 자연 레벨업' 유도 계열(예약 1개). rescue는 서비스 3택
PA.MISSION_STEER = { hunt: 'weapon_level', altars: 'weapon_mod', seal: 'skill', rescue: 'service' };

// ---------- 날짜별 편성(지역 × 날짜, 없는 날짜는 가장 가까운 이전 날짜 사용). 역할표는 GAME_SPEC §19.4 ----------
PA.DAY_WAVES = {
  forest: {
    1: [[{ type: 'wolf', n: 2 }], [{ type: 'wolf', n: 3 }], [{ type: 'wolf', n: 4 }]],
    2: [[{ type: 'wolf', n: 2 }, { type: 'boar', n: 1 }], [{ type: 'wolf', n: 3 }, { type: 'archer', n: 1 }], [{ type: 'boar', n: 2 }, { type: 'wolf', n: 2 }]],
    6: [[{ type: 'boar', n: 2 }, { type: 'rogue', n: 1 }], [{ type: 'wolf', n: 4 }, { type: 'shaman', n: 1 }], [{ type: 'boar', n: 2 }, { type: 'rogue', n: 2 }, { type: 'wolf_alpha', n: 1 }]],
  },
  ridge: {
    1: [[{ type: 'archer', n: 2 }], [{ type: 'archer', n: 2 }, { type: 'wolf', n: 2 }], [{ type: 'archer', n: 3 }, { type: 'wolf', n: 2 }]],
    3: [[{ type: 'archer', n: 2 }, { type: 'shieldbearer', n: 1 }], [{ type: 'archer', n: 2 }, { type: 'wolf', n: 3 }], [{ type: 'shieldbearer', n: 2 }, { type: 'archer', n: 2 }, { type: 'spider', n: 1 }]],
    6: [[{ type: 'shieldbearer', n: 2 }, { type: 'archer', n: 3 }], [{ type: 'rogue', n: 2 }, { type: 'archer', n: 2 }], [{ type: 'shieldbearer', n: 2 }, { type: 'archer', n: 3 }, { type: 'rogue', n: 2 }]],
  },
  marsh: {
    2: [[{ type: 'spore', n: 1 }, { type: 'wolf', n: 1 }], [{ type: 'spore', n: 2 }, { type: 'wolf', n: 2 }], [{ type: 'spore', n: 2 }, { type: 'archer', n: 2 }]],
    4: [[{ type: 'spore', n: 2 }, { type: 'frostcaller', n: 1 }], [{ type: 'spider', n: 2 }, { type: 'spore', n: 1 }, { type: 'archer', n: 1 }], [{ type: 'frostcaller', n: 2 }, { type: 'spore', n: 2 }, { type: 'wolf', n: 2 }]],
    6: [[{ type: 'frostcaller', n: 2 }, { type: 'spider', n: 2 }], [{ type: 'spore', n: 3 }, { type: 'bomber', n: 2 }], [{ type: 'frostcaller', n: 2 }, { type: 'spore', n: 2 }, { type: 'burrower', n: 2 }]],
  },
  den: {
    3: [[{ type: 'wolf', n: 3 }], [{ type: 'wolf', n: 3 }, { type: 'archer', n: 2 }], [{ type: 'wolf_alpha', n: 1 }, { type: 'wolf', n: 2 }]],
    4: [[{ type: 'wolf', n: 3 }, { type: 'shaman', n: 1 }], [{ type: 'boar', n: 2 }, { type: 'wolf', n: 2 }, { type: 'shaman', n: 1 }], [{ type: 'wolf_alpha', n: 1 }, { type: 'wolf', n: 3 }, { type: 'shaman', n: 1 }]],
    5: [[{ type: 'boar', n: 2 }, { type: 'rogue', n: 2 }], [{ type: 'burrower', n: 2 }, { type: 'wolf', n: 3 }, { type: 'shaman', n: 1 }], [{ type: 'wolf_alpha', n: 1 }, { type: 'boar', n: 2 }, { type: 'rogue', n: 2 }]],
    6: [[{ type: 'boar', n: 2 }, { type: 'rogue', n: 2 }, { type: 'bomber', n: 1 }], [{ type: 'burrower', n: 2 }, { type: 'wolf', n: 3 }, { type: 'shaman', n: 2 }], [{ type: 'wolf_alpha', n: 2 }, { type: 'boar', n: 2 }, { type: 'rogue', n: 2 }]],
  },
  deep: {
    5: [[{ type: 'spore', n: 2 }, { type: 'archer', n: 2 }, { type: 'frostcaller', n: 1 }], [{ type: 'wolf', n: 4 }, { type: 'spore', n: 1 }, { type: 'shaman', n: 1 }], [{ type: 'wolf_alpha', n: 1 }, { type: 'spore', n: 2 }, { type: 'archer', n: 2 }, { type: 'rogue', n: 1 }]],
    6: [[{ type: 'frostcaller', n: 2 }, { type: 'shieldbearer', n: 2 }, { type: 'archer', n: 2 }], [{ type: 'bomber', n: 3 }, { type: 'spore', n: 2 }, { type: 'shaman', n: 1 }], [{ type: 'wolf_alpha', n: 2 }, { type: 'rogue', n: 2 }, { type: 'frostcaller', n: 1 }, { type: 'archer', n: 2 }]],
  },
};
// 날짜별 적 체력 배율 후보(지역 배율과 곱). 체력만. 편성 변화가 주된 난이도 축이고 체력은 보조
PA.DAY_HP_SETS = { none: [1, 1, 1, 1, 1, 1, 1], dayA: [1, 1, 1.1, 1.2, 1.35, 1.5, 1.65] }; // index = day
// 정예 역할 강화: 4일차부터 정예 체력 ×1.25(여러 번 대응이 필요하게)
PA.ELITE_DAY_MULT = { from: 4, mult: 1.25 };

// ---------- 시간대 변화(지역마다 1~2개). 출발 시점의 시간대로 확정 ----------
PA.SLOT_VARIANTS = {
  forest: { 0: { name: '소규모 순찰', desc: '새벽에는 마지막 웨이브가 오지 않는다', dropLastWave: true, goldMult: 0.8 }, 4: { name: '저녁 습격', desc: '저녁에는 늑대 우두머리가 합류한다. 금화 ×1.3', addElite: true, goldMult: 1.3 } },
  ridge:  { 3: { name: '지원 사수 합류', desc: '오후에는 궁수 2명이 더 온다', extra: [{ type: 'archer', n: 2 }], goldMult: 1.15 }, 4: { name: '저녁 매복', desc: '저녁에는 도적이 측면에서 합류한다. 금화 ×1.3', extra: [{ type: 'rogue', n: 2 }], goldMult: 1.3 } },
  marsh:  { 2: { name: '점심 상인', desc: '점심에는 갇힌 상인 사건이 예정되어 있다', event: 'merchant' }, 4: { name: '저녁 포자', desc: '저녁에는 포자 괴물이 늘고 금화 ×1.3', extra: [{ type: 'spore', n: 2 }], goldMult: 1.3 } },
  den:    { 0: { name: '새벽 순찰', desc: '새벽에는 마지막 웨이브가 오지 않는다', dropLastWave: true, goldMult: 0.8 }, 3: { name: '오후 증원', desc: '오후에는 늑대 3마리가 더 온다', extra: [{ type: 'wolf', n: 3 }], goldMult: 1.15 } },
  deep:   { 4: { name: '저녁 심연', desc: '저녁에는 정예가 하나 더 나오고 금화 ×1.4', addElite: true, goldMult: 1.4 } },
};
// 방문 상인: 예정 시간대부터 그날 끝까지 거점에 머문다(짧게 왔다 가지 않음)
PA.MERCHANT_VISITS = { days: [2, 4, 6], slot: 2 }; // 점심부터

// ---------- 런 한정 장비 12종(부위별 4종) ----------
PA.EQUIPMENT = {
  // 무기: 자동기술에 붙는 효과. 장비 무기는 자동기술의 기본 피해를 대신하지 않는다
  hunter_sword:  { name: '사냥꾼의 검', slot: 'weapon', short: '정예·보스 직접 피해 +15%', desc: '자동기술의 직접 피해가 정예·보스에게 +15%. 화상·출혈·장판에는 적용되지 않는다.', eff: { eliteDirect: 0.15 } },
  pioneer_spear: { name: '개척자의 창', slot: 'weapon', short: '자동기술 사거리·범위 +12%', desc: '자동기술의 사거리·폭·반지름 +12%(기술 형태에 맞게). 회전 칼날은 칼날이 중심까지 이어져 안쪽 적도 맞는다.', eff: { reach: 0.12 } },
  ember_sword:   { name: '잔불검', slot: 'weapon', short: '내 화상·출혈 지속시간 +25%', desc: '자신이 부여하는 화상·출혈의 지속시간 +25%. 새로 부여하지는 않으며, 틱 피해·중첩·바닥 장판 지속시간은 그대로.', eff: { dotDur: 0.25 }, needs: 'dot' },
  chrono_staff:  { name: '시간술사의 지팡이', slot: 'weapon', short: '감속장 안의 적에게 직접 피해 +20%', desc: 'Q 감속장 안에 있는 적에게 자동기술 직접 피해 +20%. 화상·출혈·장판 제외. 감속장이 겹쳐도 1회만.', eff: { fieldDirect: 0.20 } },
  // 갑옷
  traveler_armor:  { name: '여행자의 경갑', slot: 'armor', short: '이동속도 +8%', desc: '이동속도 +8%. 회피 거리·무적 시간은 그대로.', eff: { speed: 0.08 } },
  guardian_armor:  { name: '수호자의 갑옷', slot: 'armor', short: '전투 시작 시 보호막 15', desc: '전투 시작 시 보호막 15(체력과 별도, 회복되지 않음).', eff: { startShield: 15 } },
  vitality_coat:   { name: '생명력의 외투', slot: 'armor', short: '최대 체력 +20', desc: '최대 체력 +20. 장착만으로 현재 체력은 회복되지 않고, 해제하면 현재 체력이 최대를 넘지 않게 줄어든다.', eff: { hpMax: 20 } },
  expedition_armor: { name: '원정대의 갑옷', slot: 'armor', short: '전투 승리 시 체력 8 회복', desc: '전투 승리 정산마다 한 번 체력 8 회복(보스 포함).', eff: { winHeal: 8 } },
  // 방패(수동 방어 키 없음)
  iron_shield:      { name: '철벽 방패', slot: 'shield', short: '큰 직접 타격 -25%', desc: '경감 전 직접 피해 1회가 최대 체력의 20% 이상이면 그 타격 -25%. 장판·화상 등 지속 피해 제외.', eff: { bigHit: { frac: 0.20, reduce: 0.25 } } },
  emergency_shield: { name: '비상 방패', slot: 'shield', short: '체력 30% 이하가 되면 보호막 20(전투당 1회)', desc: '타격을 받은 직후 체력이 30% 이하이면 보호막 20(전투당 한 번). 이미 받은 타격을 되돌리거나 사망을 막지는 않는다.', eff: { lowShield: { frac: 0.30, shield: 20 } } },
  caster_shield:    { name: '시전자의 방패', slot: 'shield', short: 'E 사용 시 3초 보호막 8 (재사용 10초)', desc: 'E 기술 사용 시 3초 동안 보호막 8. 장비 재사용 대기 10초, 남은 보호막은 새 보호막으로 대체(누적 없음).', eff: { eShield: { shield: 8, dur: 3, cd: 10 } } },
  time_shield:      { name: '시간의 방패', slot: 'shield', short: '감속장 안 공격자의 직접 피해 -20%', desc: 'Q 감속장 안에 있는 공격자가 준 직접 피해 -20%. 잔류 바닥 피해처럼 공격자가 없는 피해에는 적용되지 않는다.', eff: { fieldTaken: 0.20 } },
};
PA.EQUIP_SLOTS = ['weapon', 'armor', 'shield'];
PA.EQUIP_SLOT_NAMES = { weapon: '무기', armor: '갑옷', shield: '방패' };

// ---------- 상점·대장간 가격(시험값) ----------
PA.SHOP = {
  price: { weapon: 140, armor: 120, shield: 120 }, sellPrice: { weapon: 35, armor: 30, shield: 30 },
  newSkill: 180, newE: 180,
  swap: { base: 120, perLevel: 40, perMod: 80 }, // 교체 = 120 + (레벨-1)×40 + 개조·변형 수×80
  modChange: 140, variantChange: 140,
  forge: [{ lv: 1, cost: 90, afterBoss: 0 }, { lv: 2, cost: 160, afterBoss: 1 }, { lv: 3, cost: 240, afterBoss: 2 }], // 공용 공격 강화: 보스 관문 통과로 개방
  forgeMult: [0, 0.10, 0.20, 0.30], // 단계별 자동기술 기본 피해 +% (자동기술 피해에서 파생되는 출혈 등 포함, E·Q 피해 제외)
  stock: { equipment: 2, skill: 1 },   // 하루 진열: 장비 2 + 자동기술 또는 E 1
  merchantDiscount: 0.15,              // 방문 상인 특별 재고 할인
};
