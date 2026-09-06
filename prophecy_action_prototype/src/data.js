// 모든 규칙 수치와 콘텐츠 정의. 임시 수치는 docs/ASSUMPTIONS.md 참고.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.CONFIG = {
  STEP: 1 / 120,            // 고정 시뮬레이션 단계(초)
  ARENA: { w: 960, h: 600 },
  VIEW: { pad: 44 },           // 전장 밖 나무 경계 여백(그리기 전용, 판정과 무관)
  HOURS_PER_DAY: 5,
  BOSS_DAY: 7,              // 이 날이 시작되면 보스 도래
  START_GOLD: 60,
  REST_HOURS: 1,
  DEFEAT_HOUR_PENALTY: 1,
  DEFEAT_HP_RATIO: 0.3,
  DEEP_EXPLORE_HOURS: 1,
  DEEP_REWARD_MULT: 1.5,
  SKIP_AUGMENT_GOLD: 20,
  PLAYER: {
    hp: 100, speed: 220, r: 14,
    hitProtect: 0.6,
    zoneTick: 0.5,
    dodge: { duration: 0.26, distance: 150, cooldown: 0.9 },
    special: { radius: 150, duration: 3.0, cooldown: 14, slow: 0.4 },
    exposedMult: 1.5,
  },
  WEAPONS: {
    sword:  { name: '기본검', form: 'arc',   damage: 12, interval: 0.55, range: 95,  arcDeg: 110, knock: 40 },
    pierce: { name: '관통검', form: 'beam',  damage: 14, interval: 0.70, range: 230, width: 44,   knock: 30 },
  },
  SPIN: { radius: 110, damageMult: 1.2, knock: 90, every: 3 },
  ECHO: { every: 4, delay: 0.2 },
  EMBER: { count: 3, radius: 30, ttl: 2.5, tick: 0.4, damage: 5 },
  FROST: { chill: 2.0, slow: 0.6, shards: 6, shardDamage: 8, shardSpeed: 300, shardTtl: 0.5 },
  MARK: { damageMult: 1.3, priority: ['boss', 'wolf_alpha', 'archer', 'spore', 'wolf'] },
  BARRIER: { shield: 30, knockRadius: 120, knock: 140 },
  STASIS: { maxStacks: 5, damagePerStack: 10 },
  FLARE: { radius: 80, damage: 20 },
  SAVING: { cdPerKill: 1 },   // 감속장 안 처치 1마리당 재사용 -1초 (임시값)
  CHEST: { gold: [15, 25], wave: 1, r: 16 },
  WAVE_DELAY: 1.2,
  SPAWN_WARN: 0.6,
  SEPARATION: 1.0,
};

// 전장 정의. 장애물은 원형 충돌체(그림 = 충돌 범위). 첫 시험 배치, 데이터로 관리하는 임시값.
PA.ARENAS = {
  forest: { name: '숲 전장', obstacles: [] },
  clearing: {
    name: '돌과 나무가 있는 숲의 공터',
    obstacles: [
      { id: 'rockA', type: 'rock', x: 285, y: 220, r: 42 },
      { id: 'rockB', type: 'rock', x: 675, y: 380, r: 42 },
      { id: 'treeA', type: 'tree', x: 300, y: 420, r: 26, canopy: 70 },
      { id: 'treeB', type: 'tree', x: 660, y: 180, r: 26, canopy: 70 },
    ],
    playerStart: { x: 480, y: 500 },
    bossStart: { x: 480, y: 120 },
  },
};

// 보스: 가시갈기 — 숲의 왕. 모든 수치는 첫 시험용 임시값(docs/ASSUMPTIONS.md).
PA.BOSS = {
  id: 'boss', name: '가시갈기', title: '숲의 왕',
  hp: 2400, speed: 110, r: 42, phases: [0.7, 0.35],
  intro: 1.6, roar: 0.9, stagger: 1.0, knockMult: 0.2, stopDist: 118,
  sweep:  { aim: 0.65, lock: 0.40, radius: 145, arcDeg: 120, damage: 16, recover: 1.5, maxDist: 200 },
  dash:   { aim: 0.70, lock: 0.45, dist: 460, speed: 800, damage: 20, recover: 2.2, minDist: 150, maxDist: 520, second: { aim: 0.45, lock: 0.40 }, doubleRecover: 3.0 },
  howl:   { duration: 1.6, count: 2, maxWolves: 4, interval: 18, warn: 0.9, ring: [90, 150] },
  pounce: { aim: 0.50, lock: 0.65, leap: 0.45, radius: 105, damage: 18, recover: 1.8, minDist: 300 },
  overlap: { bossWaitMax: 1.2, wolfDelay: [0.15, 0.5], summonGrace: 0.8 },
  orb: { healRatio: 0.15, r: 14, ring: 170 },
  minApproach: 0.4,
  weights: { sweep: 1.0, dash: 1.2, pounce: 1.5, howl: 2.0 },
  info: ['긴 돌진: 붉은 통로가 굳으면 방향이 고정됩니다. 옆으로.', '무리 소환: 울부짖으면 늑대가 발자국 자리에 나타납니다. 광역·파편·폭발의 기회.', '큰 공격 뒤에는 확실히 지칩니다(빈틈 피해 1.5배).', '감속장(Q)은 보스의 준비·돌진·빈틈 모두를 40% 속도로 늦춥니다.', '바위와 나무는 이동과 돌진을 막습니다. 직접 공격은 장애물을 관통하지 않지만 불길·폭발·감속장은 바닥 범위대로 적용됩니다.'],
};

PA.ENEMIES = {
  boss: { name: '가시갈기', role: '보스 · 숲의 왕', r: 42, hp: 2400, speed: 110, color: '#6e5a3a', boss: true, readme: '거대한 늑대. 휩쓸기·돌진·무리 소환·덮쳐찍기.' },
  wolf: {
    name: '늑대', role: '돌진 습격', r: 14, hp: 30, speed: 150, color: '#9aa0a8',
    engageDist: 170, crouch: 0.6, lock: 0.15, dashTime: 0.32, dashSpeed: 800, recover: 0.9, damage: 12, dashes: 1,
    readme: '웅크리고 화살표로 방향을 예고한 뒤 직진 돌진. 확정 신호 뒤에는 방향이 바뀌지 않는다. 옆으로 피하면 빈틈.',
  },
  wolf_alpha: {
    name: '늑대 우두머리', role: '정예', r: 22, hp: 120, speed: 160, color: '#c9b458', elite: true,
    engageDist: 200, crouch: 0.6, lock: 0.15, dashTime: 0.34, dashSpeed: 820, recover: 1.2, damage: 18, dashes: 2, secondCrouch: 0.35,
    readme: '연속 2회 돌진. 두 번째 준비가 짧다. 두 번 모두 옆으로.',
  },
  archer: {
    name: '궁수', role: '원거리 압박', r: 13, hp: 22, speed: 110, color: '#7cc47a',
    keepMin: 220, keepMax: 360, aim: 1.0, lock: 0.25, recover: 1.3, arrowSpeed: 460, arrowDamage: 10, arrowR: 5,
    readme: '붉은 선으로 조준을 예고하고 선이 굵어지면 방향 고정. 체력이 낮으니 접근해서 먼저 처치.',
  },
  spore: {
    name: '포자 괴물', role: '지역 통제', r: 18, hp: 55, speed: 60, color: '#b070d8',
    engageDist: 130, swell: 0.9, recover: 1.6, cloudR: 80, cloudTtl: 5, cloudDamage: 6, deathCloudR: 50, deathCloudTtl: 3,
    readme: '부풀면서 바닥에 원을 그린다. 원 = 구름 범위. 죽어도 작은 구름을 남긴다.',
  },
};

PA.AUGMENTS = [
  { id: 'sharp',   name: '예리한 날',   kind: '일반',     max: 3, desc: '공격력 +25%', long: '모든 검격·회전·관통 피해가 25% 증가합니다. 단계마다 중첩.' },
  { id: 'wide',    name: '넓은 검격',   kind: '일반',     max: 3, desc: '검격 범위 +25%', long: '부채꼴 반지름 또는 관통 길이가 25% 늘어납니다.' },
  { id: 'quick',   name: '빠른 손',     kind: '일반',     max: 3, desc: '공격 주기 -15%', long: '자동 공격 간격이 15% 짧아집니다.' },
  { id: 'spin',    name: '회전 검격',   kind: '무기 변형', max: 1, desc: '3번째 검격마다 360° 회전 검격', long: '세 번째 공격이 주변 전체를 베는 회전 검격이 되고 적을 크게 밀어냅니다. 둘러싸였을 때의 해법.' },
  { id: 'ember',   name: '잔불 걸음',   kind: '행동',     max: 1, desc: '회피한 자리에 불길을 남김', long: '회피 경로에 불길 3개가 2.5초 남아 지나가는 적을 태웁니다. 늑대의 추격을 공격 기회로.' },
  { id: 'frost',   name: '얼음 파편',   kind: '조건부',   max: 1, desc: '적중한 적을 냉기로 감속. 냉기 적 처치 시 파편 확산', long: '검격에 맞은 적은 2초간 느려지고, 그 상태로 죽으면 파편 6개가 주변 적을 때립니다.' },
  { id: 'mark',    name: '사냥꾼의 표식', kind: '행동',   max: 1, desc: '위험한 적에 표식. 우선 공격, 피해 +30%', long: '정예 > 궁수 > 포자 > 늑대 순으로 표식이 붙고, 사거리 안이면 자동 공격이 그 적을 노립니다. 처치하면 다음 대상으로 옮겨갑니다.' },
  { id: 'echo',    name: '메아리 검격', kind: '리듬',     max: 1, desc: '4번째 검격이 한 번 더 반복', long: '네 번째 검격 0.2초 뒤 같은 방향으로 한 번 더 베어냅니다.' },
  { id: 'barrier', name: '파열 방벽',   kind: '방어',     max: 1, desc: '조우 시작 시 보호막 30. 파괴 시 주변 넉백', long: '보호막이 깨지는 순간 주변 적을 밀쳐 탈출 기회를 만듭니다.' },
  { id: 'stasis',  name: '정지된 칼날', kind: '결합',     max: 1, requires: [], connect: '감속장 + 검격', desc: '감속장 안의 적을 치면 흔적이 쌓이고, 감속장 종료 시 폭발', long: '감속장 안에서 검격에 맞은 적은 흔적(최대 5)을 얻습니다. 감속장이 끝나면 흔적×10 피해로 터집니다.' },
  { id: 'flare',   name: '불꽃 파열',   kind: '결합',     max: 1, requires: ['ember'], connect: '잔불 걸음 + 처치', desc: '불길 위에서 적 처치 시 폭발', long: '불길 위에 서 있던 적이 죽으면 반지름 80 안의 적에게 20 피해. 잔불 걸음이 있어야 제시됩니다.' },
  { id: 'saving',  name: '시간 저축',   kind: '결합',     max: 1, connect: '감속장 + 처치', desc: '감속장 안의 적을 처치할 때마다 감속장 재사용 -1초', long: '감속 효과를 받고 있는 적이 죽으면 감속장 재사용 시간이 1초 줄어듭니다(적 1마리당 1회). 감속장 안에서 많이 잡을수록 다음 감속장이 빨리 옵니다.' },
];

PA.MATERIALS = {
  pelt:  { name: '늑대 가죽', sell: 15, where: ['forest', 'den'] },
  iron:  { name: '철 조각',   sell: 20, where: ['ridge', 'deep'] },
  spore: { name: '포자 결정', sell: 25, where: ['marsh', 'deep'] },
  fang:  { name: '우두머리 송곳니', sell: 60, where: ['den', 'deep'] },
};

PA.ITEMS = [
  { id: 'pierce_sword', name: '관통검', slot: 'weapon', cost: { gold: 260, mats: { pelt: 3, iron: 2 } },
    desc: '기본 공격이 관통 검격으로 바뀝니다. 직선으로 늘어선 적을 한 번에 베어냅니다.', short: '무기: 관통 검격' },
  { id: 'leather_armor', name: '가죽 갑옷', slot: 'armor', cost: { gold: 120, mats: { pelt: 2 } },
    desc: '최대 체력 +30.', short: '방어구: 최대 체력 +30' },
  { id: 'time_charm', name: '시간의 부적', slot: 'acc', cost: { gold: 150, mats: { spore: 1 } },
    desc: '회피 재사용 -30%, 감속장 재사용 -3초.', short: '장신구: 회피·감속장 재사용 단축' },
  { id: 'fang_necklace', name: '송곳니 목걸이', slot: 'acc', cost: { gold: 200, mats: { fang: 1 } },
    desc: '빈틈 상태의 적에게 주는 피해 1.5배 → 2.0배.', short: '장신구: 빈틈 피해 2배' },
  { id: 'whetstone', name: '무기 강화', slot: 'upgrade', costs: [ { gold: 80, mats: { iron: 1 } }, { gold: 140, mats: { iron: 1 } }, { gold: 220, mats: { iron: 1 } } ],
    desc: '무기 공격력 +15% (최대 +3).', short: '강화: 공격력 +15%씩' },
];

PA.REGIONS = [
  { id: 'forest', name: '근교 숲', cost: 1, risk: 1, objective: 'clear',
    enemies: ['wolf'], desc: '늑대 무리. 돌진 예고를 읽고 옆으로 피하는 연습.',
    waves: [ [ { type: 'wolf', n: 2 } ], [ { type: 'wolf', n: 3 } ], [ { type: 'wolf', n: 4 } ] ],
    reward: { gold: [30, 45], mats: { pelt: [1, 2] } } },
  { id: 'ridge', name: '바람 능선', cost: 1, risk: 2, objective: 'clear',
    enemies: ['archer', 'wolf'], desc: '궁수가 먼 곳에서 조준한다. 늑대를 피하면서 궁수에게 다가가 먼저 처치.',
    waves: [ [ { type: 'archer', n: 2 } ], [ { type: 'archer', n: 2 }, { type: 'wolf', n: 2 } ], [ { type: 'archer', n: 3 }, { type: 'wolf', n: 2 } ] ],
    reward: { gold: [35, 50], mats: { iron: [1, 2] } } },
  { id: 'marsh', name: '포자 습지', cost: 2, risk: 2, objective: 'clear',
    enemies: ['spore', 'wolf', 'archer'], desc: '포자 괴물이 바닥을 구름으로 덮는다. 안전한 공간이 줄어든다.',
    waves: [ [ { type: 'spore', n: 1 }, { type: 'wolf', n: 1 } ], [ { type: 'spore', n: 2 }, { type: 'wolf', n: 2 } ], [ { type: 'spore', n: 2 }, { type: 'archer', n: 2 } ] ],
    reward: { gold: [50, 70], mats: { spore: [1, 2] } } },
  { id: 'den', name: '늑대 굴', cost: 2, risk: 3, objective: 'elite',
    enemies: ['wolf', 'archer', 'wolf_alpha'], desc: '늑대 우두머리를 처치하면 조우 종료. 연속 돌진에 주의.',
    waves: [ [ { type: 'wolf', n: 3 } ], [ { type: 'wolf', n: 3 }, { type: 'archer', n: 2 } ], [ { type: 'wolf_alpha', n: 1 }, { type: 'wolf', n: 2 } ] ],
    reward: { gold: [70, 100], mats: { pelt: [2, 3], fang: [1, 1] } } },
  { id: 'deep', name: '심층 습지', cost: 3, risk: 3, objective: 'elite',
    enemies: ['spore', 'archer', 'wolf', 'wolf_alpha'], desc: '모든 위협의 조합. 구름·화살·돌진을 동시에 읽어야 한다.',
    waves: [ [ { type: 'spore', n: 2 }, { type: 'archer', n: 2 } ], [ { type: 'wolf', n: 4 }, { type: 'spore', n: 1 } ], [ { type: 'wolf_alpha', n: 1 }, { type: 'spore', n: 2 }, { type: 'archer', n: 2 } ] ],
    reward: { gold: [100, 140], mats: { spore: [2, 3], iron: [2, 2], fang: [1, 1] } } },
];

PA.BOSS_ACTION_TEXT = { intro: '입장', approach: '접근', sweep_aim: '송곳니 휩쓸기 준비', sweep_lock: '휩쓸기!', dash_aim: '사냥 돌진 준비', dash_lock: '돌진!', dash: '돌진 중', howl: '무리 소환', pounce_aim: '덮쳐찍기 준비', pounce_lock: '덮쳐찍기!', leap: '도약 중', recover: '빈틈!', roar: '포효', stagger: '비틀거림!', dead: '쓰러짐' };

PA.KEYS_TEXT = 'WASD/방향키 이동 · Space 회피 · Q 감속장 · E 기술 · Esc 일시정지';
