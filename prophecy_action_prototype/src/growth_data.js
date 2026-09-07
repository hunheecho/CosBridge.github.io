// 성장 시스템 데이터(v0.5). 모든 수치는 임시값. `impl: false`인 항목은 미구현이며 게임에 후보로 노출되지 않는다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.GROWTH = {
  SLOTS: { weapons: 3, weaponMods: 2, weaponMax: 5, commons: 3, passives: 4, passiveMax: 3, skillMax: 3, skillVariants: 1 },
  LEVEL_MULT: [1.0, 1.2, 1.4, 1.6, 1.8],            // 무기 레벨 1~5 기본 피해 누적 배율(복리 아님)
  // 경험치 곡선: 필요치 = base + step*(n-1) + quad*(n-1)^2. v0.5(14/4/0)는 1일차에 레벨업이 몰렸다(봇 기준 28회 중 10회).
  // v0.6 임시값(16/6/0.4)은 초반 레벨 비용을 올리고, 대신 위험 지역의 처치 경험치를 REGION_XP_MULT로 올려 총량을 유지한다. 비교는 tools/run_sim.js.
  XP: { base: 20, step: 5, quad: 0.1, maxLevel: 40 },
  XP_CURVES: { v05: { base: 14, step: 4, quad: 0, regionMult: { forest: 1, ridge: 1, marsh: 1, den: 1, deep: 1, boss: 1 } }, v06: { base: 20, step: 5, quad: 0.1, regionMult: { forest: 1, ridge: 1.5, marsh: 2, den: 2.5, deep: 3, boss: 1 } } }, // 비교용(tools/run_sim.js). v06 채택 근거: 봇 기준 점진 전략 1일차 레벨업 10→8, 이후 날 4/4/4/3/4로 평탄, 총 레벨 유지
  XP_VALUE: { wolf: 6, archer: 7, spore: 8, wolf_alpha: 30, boss: 0, summoned: 6, boar: 12, shieldbearer: 11, shaman: 10, bomber: 7, burrower: 9, spider: 8, frostcaller: 9, rogue: 9 }, // 보스 처치 자체는 경험치 0(보스 보상은 별도)
  REGION_XP_MULT: { forest: 1, ridge: 1.5, marsh: 2, den: 2.5, deep: 3, boss: 1 },   // 처치 경험치 × 지역 배율(체력 배율과 무관, 임시값)
  REGION_BONUS_XP: { forest: 10, ridge: 16, marsh: 34, den: 50, deep: 90 },        // 조우 승리 시 추가 경험치(조우 3택 증강을 대체). 시간당 경험치가 쉬운 지역 반복보다 낮지 않도록 비용에 비례(임시값)
  XP_KILL_MULT: 1, BONUS_XP_MULT: 1, // 비교 후보용 배율(기본 1 = 현재값). 처치 경험치·지역 경험치
  DEEP_PICK: false,                                     // v0.8: 더 깊이 승리는 3택 대신 표시형 보상(Run.deepPreview). true로 두면 옛 지역 3택 경로
  WEIGHTS: {
    base: { weapon_new: 1.0, weapon_level: 1.0, weapon_mod: 1.0, common: 1.0, skill_new: 1.0, skill_level: 0.8, skill_variant: 0.9, passive: 0.9 },
    early: { untilLevel: 5, weapon_new: 2.0, skill_new: 2.0, weapon_mod: 1.5, passive: 0.6 },   // 초반 보정
    regionTag: 1.8,                                     // 지역 태그와 맞는 후보 가중치
    repeatPenalty: 0.5,                                 // 직전 선택과 같은 종류(무기 레벨업 등) 완화
  },
  COMMON_VALUES: { wide: [1.25, 1.5], reach: [1.25, 1.5], burn: { dps: 4, dur: 2.0 }, echoEvery: 4, echoDelay: 0.2 },
  PASSIVE_VALUES: { vitality: 20, toughness: 0.10, mastery: 0.10, haste: 0.08, mobility: 0.08, focus: 0.10, exploit: 0.25, persistence: 0.20 },
};

// 무기 10종. kind: arc(부채꼴) beam(직선) melee(근접 연타) homing(추적 투사체) heavy(범위 타격) orbit(공전) chain(연쇄) bolt(냉기 탄환) ember(불씨) mine(지뢰)
// reach: 긴 사거리 적용 / width: 넓어진 공격 적용. category: direct(장애물 가림) | projectile(장애물 충돌) | ground(바닥 범위)
PA.WEAPONS = {
  sword:   { name: '검', kind: 'arc', startable: true, impl: true, base: { damage: 12, interval: 0.55, range: 95, arcDeg: 110, knock: 40 }, reach: true, width: true, category: 'direct', tags: ['melee', 'combo'],
    desc: '전방 부채꼴 검격. 접근과 광역 처리의 균형.',
    mods: { cross: { name: '교차 검격', desc: '3번째 검격마다 반대 방향으로 한 번 더', impl: true, tags: ['combo'] }, crescent: { name: '날아가는 검광', desc: '검격 끝에서 초승달 검기가 전진(피해 60%, 관통)', impl: true, tags: ['projectile'] }, scar: { name: '잔류 검흔', desc: '벤 자리에 검흔이 남아 0.5초 뒤 한 번 더(피해 50%)', impl: true, tags: ['combo'] } } },
  spear:   { name: '관통창', kind: 'beam', startable: true, impl: true, base: { damage: 14, interval: 0.70, range: 230, width: 44, knock: 30 }, reach: true, width: true, category: 'direct', tags: ['pierce'],
    desc: '긴 직선 관통 검기. 적을 일렬로 세우는 재미. (기존 관통검이 이 무기로 이어진다)',
    mods: { returning: { name: '귀환 검기', desc: '끝까지 간 검기가 0.35초 뒤 돌아오며 다시 공격', impl: true, tags: ['pierce'] }, split: { name: '분열 창날', desc: '첫 적중 뒤 작은 검기 2개가 사선으로 분열(피해 40%)', impl: true, tags: ['projectile'] }, brand: { name: '꿰뚫는 표식', desc: '같은 적을 4번 찌르면 표식 폭발(피해 150%, 반지름 60)', impl: true, tags: ['pierce'] } } },
  daggers: { name: '쌍검', kind: 'melee', startable: true, impl: true, base: { damage: 6, interval: 0.75, range: 62, hits: 3, hitGap: 0.09, arcDeg: 70, knock: 10 }, reach: false, width: true, category: 'direct', tags: ['melee', 'bleed'],
    desc: '가까운 적에게 짧은 3연속 공격. 근접 집중.',
    mods: { bleed: { name: '출혈 칼날', desc: '적중 시 2초 출혈(초당 30%)', impl: true, tags: ['bleed'] }, flank: { name: '측면 연무', desc: '연속 공격 마지막이 좌우 넓은 검격', impl: true, tags: ['melee'] }, pursuit: { name: '추격 칼날', desc: '적 처치 시 가까운 다른 적에게 작은 칼날(피해 80%)', impl: true, tags: ['combo'] } } },
  bow:     { name: '추적궁', kind: 'homing', startable: true, impl: true, base: { damage: 11, interval: 0.8, range: 320, speed: 380, turn: 4.0 }, reach: true, width: false, category: 'projectile', tags: ['projectile'],
    desc: '적을 향해 경로를 보정하는 화살. 이동하며 원거리 공격. 장애물에 막힌다.',
    mods: { spread: { name: '갈래 사격', desc: '화살 3발을 부채꼴로', impl: true, tags: ['projectile'] }, ricochet: { name: '도탄 화살', desc: '적중 후 가까운 다른 적에게 한 번 튕김(피해 70%)', impl: true, tags: ['projectile'] }, pierce: { name: '관통 화살', desc: '적을 통과해 뒤쪽 적까지', impl: true, tags: ['pierce'] } } },
  hammer:  { name: '전투망치', kind: 'heavy', startable: true, impl: true, base: { damage: 30, interval: 1.4, range: 110, radius: 70, knock: 120 }, reach: true, width: true, category: 'direct', tags: ['melee'],
    desc: '느리고 강한 범위 타격. 큰 한 방과 밀어내기.',
    mods: { shockwave: { name: '전방 충격파', desc: '타격 지점에서 앞으로 충격파(길이 160, 피해 60%)', impl: true, tags: ['melee'] }, aftershock: { name: '여진', desc: '타격한 바닥이 0.6초 뒤 다시 폭발(피해 50%)', impl: true, tags: ['zone'] }, pull: { name: '끌어당기는 망치', desc: '타격 직전 근처 작은 적을 타격점으로 조금 당김', impl: true, tags: ['melee'] } } },
  blades:  { name: '회전 칼날', kind: 'orbit', startable: true, impl: true, base: { damage: 10, interval: 0.35, count: 2, radius: 78, angular: 3.2, hitGap: 0.35, knock: 20 }, /* v0.8 시험값 변경: 피해 8→10, 접촉 주기 0.45→0.35 (근거: docs/sim/report_E2.md — 살 판정 뒤에도 승률 56% vs 검 64%·정지 보스 DPS 14 vs 25; 후보 '피해10+주기0.35'가 65%·17.5로 검과 같은 수준) */ reach: false, width: true, category: 'direct', tags: ['melee', 'combo'],
    desc: '플레이어 주변을 도는 칼날. 칼날의 살(중심 근처~끝)에 닿는 적을 벤다. 같은 적은 0.35초마다 한 번.',
    mods: { dual: { name: '세 번째 칼날', desc: '칼날 +1 (같은 궤도, 접촉 빈도 증가)', impl: true, tags: ['melee'] }, launch: { name: '사출 칼날', desc: '3초마다 칼날 하나가 적에게 날아갔다 복귀(피해 120%)', impl: true, tags: ['projectile'] }, serrated: { name: '톱날', desc: '적중한 적에게 짧은 출혈', impl: true, tags: ['bleed'] } } },
  orb:     { name: '번개 구체', kind: 'chain', startable: true, impl: true, base: { damage: 9, interval: 0.9, range: 200, hop: 130, hops: 3 }, reach: true, width: false, category: 'direct', tags: ['chain'],
    desc: '주변 구체가 연쇄 번개를 쏜다. 가까운 적들을 연결. 한 연쇄에서 같은 적은 한 번만.',
    mods: { fork: { name: '분기 번개', desc: '첫 대상에서 두 갈래로 연쇄', impl: true, tags: ['chain'] }, loop: { name: '순환 전류', desc: '연쇄 마지막에 최초 대상으로 한 번 돌아옴(명시적 예외)', impl: true, tags: ['chain'] }, conduct: { name: '전도 표식', desc: '번개에 맞은 적을 다른 무기로 치면 작은 전기 폭발(피해 40%)', impl: true, tags: ['combo'] } } },
  frost:   { name: '서리 수정', kind: 'bolt', startable: false, impl: true, base: { damage: 7, interval: 1.0, range: 260, speed: 360, chill: 2.0 }, reach: true, width: false, category: 'projectile', tags: ['dot', 'projectile'],
    desc: '주기적으로 냉기 탄환 발사. 냉기 공급과 조합 지원. 우선 추가 획득.',
    mods: { fan: { name: '서리 부채', desc: '냉기 탄환 3발을 부채꼴로', impl: true, tags: ['projectile'] }, shatter: { name: '깨지는 수정', desc: '탄환 적중 시 작은 파편 3개로 분열(피해 40%)', impl: true, tags: ['projectile'] }, ground: { name: '차가운 바닥', desc: '적중 지점에 2초 냉기 영역(반지름 40)', impl: true, tags: ['zone'] } } },
  ember:   { name: '불씨 정령', kind: 'ember', startable: false, impl: true, base: { damage: 5, interval: 1.6, range: 260, radius: 34, ttl: 2.5, tick: 0.4 }, reach: true, width: true, category: 'ground', tags: ['dot', 'zone'],
    desc: '적 주변으로 불씨를 던져 불길 생성. 적을 불길로 유도. 우선 추가 획득.',
    mods: { scatter: { name: '불씨 산개', desc: '작은 불씨 3개를 여러 위치로', impl: true, tags: ['zone'] }, trail: { name: '화염 띠', desc: '착탄 지점에서 불길이 길게 이어짐(3조각)', impl: true, tags: ['zone'] }, reignite: { name: '재점화', desc: '불길 위 적 처치 시 그 불길 +1.5초(상한 +4.5초)', impl: true, tags: ['dot'] } } },
  mine:    { name: '룬 지뢰', kind: 'mine', startable: false, impl: true, base: { damage: 22, interval: 1.5, radius: 70, trigger: 30, arm: 0.5, max: 6 }, reach: false, width: true, category: 'ground', tags: ['zone', 'chain'],
    desc: '일정 간격으로 바닥에 지뢰 설치. 뒤따르는 적의 경로 활용. 회피 성공과 무관. 우선 추가 획득.',
    mods: { chain: { name: '연결 폭발', desc: '폭발이 90 안의 다른 지뢰를 0.15초 뒤 연달아 기폭', impl: true, tags: ['chain'] }, frosttrap: { name: '서리 함정', desc: '폭발 범위 적에게 냉기', impl: true, tags: ['dot'] }, lure: { name: '유인 룬', desc: '준비된 지뢰가 70 안의 작은 적을 천천히 당김', impl: true, tags: ['zone'] } } },
};
PA.STARTABLE = ['sword', 'spear', 'blades'];              // 첫 검증 시작 무기. 나머지 시작 후보는 검증 메뉴(?start=)에서
PA.STARTABLE_ALL = Object.keys(PA.WEAPONS).filter(id => PA.WEAPONS[id].startable);

// 공통 증강 9종(별도 3슬롯). max: 단계
PA.COMMONS = {
  wide:   { name: '넓어진 공격', max: 2, impl: true, desc: '적용 가능한 모든 무기의 폭·반경 증가', long: '직접 공격의 크기를 바꿉니다(사거리와 구분). 검격 반지름, 관통 폭, 망치 반지름, 칼날 궤도, 불길·지뢰 반지름.', applies: (w) => w.width, tags: ['mod'] },
  reach:  { name: '긴 사거리', max: 2, impl: true, desc: '적용 가능한 모든 무기의 도달 거리 증가', long: '검격·관통 길이, 화살·탄환·불씨 사거리, 번개 사거리. 쌍검·회전 칼날·지뢰에는 적용되지 않습니다.', applies: (w) => w.reach, tags: ['projectile', 'pierce'] },
  frost:  { name: '얼음 파편', max: 1, impl: true, desc: '모든 무기의 기본 공격이 냉기 부여. 냉기 적 처치 시 파편', long: '냉기는 중첩되지 않고 유지 시간만 갱신됩니다. 파편은 냉기를 다시 부여하지 않습니다.', tags: ['dot', 'chain'] },
  burn:   { name: '불붙은 공격', max: 1, impl: true, desc: '모든 무기의 기본 공격에 짧은 화상(2초, 초당 4)', long: '화상 피해는 화상을 다시 만들지 않습니다.', tags: ['dot'] },
  echo:   { name: '메아리', max: 1, impl: true, desc: '각 무기의 4번째 공격을 한 번 반복', long: '무기마다 공격 횟수를 따로 셉니다. 메아리로 생긴 공격은 다시 메아리를 만들지 않습니다.', tags: ['combo'] },
  ember:  { name: '잔불 걸음', max: 1, impl: true, desc: '회피 경로에 불길 3개', long: '회피를 사용하기만 하면 됩니다(성공 판정 없음).', tags: ['dot', 'zone'] },
  flare:  { name: '불꽃 파열', max: 1, impl: true, desc: '불길 위 적 처치 시 주변 폭발(반지름 80)', long: '불길 공급원(잔불 걸음, 불씨 정령, 불붙은 공격은 제외)이 있을 때 제시됩니다.', requiresAny: ['common:ember', 'weapon:ember'], tags: ['zone', 'chain'] },
  saving: { name: '시간 저축', max: 1, impl: true, desc: '감속장 안 처치마다 감속장 재사용 -1초', long: '어떤 무기로 처치했든 적 1마리당 1회. 0 미만 불가.', tags: ['chain'] },
  stasis: { name: '정지된 칼날', max: 1, impl: true, desc: '감속장 안의 적을 기본 공격으로 치면 흔적(최대 5). 종료 시 폭발', long: '흔적당 10 피해(무기 숙련 배율 적용).', tags: ['combo'] },
};

// 공통 패시브 8종(서로 다른 4종, 각 3레벨)
PA.PASSIVES = {
  vitality:    { name: '건강', max: 3, impl: true, desc: '최대 체력 +20/레벨', long: '증가분만큼 현재 체력도 오릅니다. 사망을 되돌리지 않습니다.' },
  toughness:   { name: '강인함', max: 3, impl: true, desc: '직접 공격 피해 -10%/레벨', long: '늑대 물기·화살·휩쓸기·돌진·덮쳐찍기. 포자 구름 같은 지면 지속 피해에는 적용되지 않습니다(첫 구현).' },
  mastery:     { name: '무기 숙련', max: 3, impl: true, desc: '모든 자동 무기 피해 +10%/레벨', long: '수동 기술(Q/E) 피해에는 적용되지 않습니다.' },
  haste:       { name: '가속', max: 3, impl: true, desc: '모든 자동 무기 공격 주기 -8%/레벨', long: '' },
  mobility:    { name: '기동력', max: 3, impl: true, desc: '이동 속도 +8%/레벨', long: '회피 거리·무적 시간은 그대로입니다.' },
  focus:       { name: '집중', max: 3, impl: true, desc: 'Q/E 재사용 시간 -10%/레벨', long: '' },
  exploit:     { name: '빈틈 포착', max: 3, impl: true, desc: '빈틈 상태 적 피해 배율 +0.25/레벨', long: '계산 순서: 기본 1.5 → 송곳니 목걸이면 2.0 → 빈틈 포착 레벨×0.25를 더함.' },
  persistence: { name: '지속력', max: 3, impl: true, desc: '불길·냉기·감속장·화상 유지 시간 +20%/레벨', long: '적용: 잔불·불씨 정령 불길, 냉기, 화상, 감속장. 적의 포자 구름 등은 늘리지 않습니다.' },
};

// 수동 기술. Q는 감속장 고정, E는 5종 중 1개
PA.SKILLS = {
  slowfield: { key: 'Q', name: '감속장', impl: true, max: 3, cooldown: [14, 12, 10], desc: '반지름 150, 3초, 적 속도·준비 40%', long: '레벨: 재사용 단축.',
    variants: { follow: { name: '동행하는 시간', impl: true, desc: '감속장이 플레이어를 따라 이동' }, split: { name: '분할된 시간', impl: true, desc: '플레이어 주변과 가장 가까운 적 무리 위치에 작은 감속장 2개(반지름 100). 겹쳐도 감속·처치 보상은 1회' }, echo: { name: '시간의 잔향', impl: true, desc: '종료 뒤 1.5초 동안 약한 감속(70%) 영역이 남음' } } },
  gust:      { key: 'E', name: '돌풍', impl: true, max: 3, cooldown: [8, 7, 6], damage: [10, 14, 18], desc: '바라보는 방향 전방의 적을 밀어냄(길이 170, 폭 120)', long: '레벨: 피해·밀어내는 힘. 보스는 밀리지 않고 피해만.',
    variants: { whirl: { name: '회오리', impl: true, desc: '전방 밀어내기를 주변 전체(반지름 130) 밀어내기로' }, windpath: { name: '바람길', impl: true, desc: '지나간 자리에 3초 동안 플레이어 이동 속도 +40% 영역' } } },
  bladestorm:{ key: 'E', name: '칼날 폭풍', impl: true, max: 3, cooldown: [10, 9, 8], damage: [8, 11, 14], desc: '주변(반지름 110)을 1.2초 동안 0.2초마다 공격', long: '레벨: 피해.',
    variants: { advancing: { name: '전진하는 폭풍', impl: true, desc: '바라보는 방향으로 이동하는 폭풍(속도 150)' }, condensed: { name: '응축된 폭풍', impl: true, desc: '반지름 70으로 줄고 피해 1.8배' } } },
  strike:    { key: 'E', name: '낙뢰', impl: true, max: 3, cooldown: [9, 8, 7], damage: [40, 55, 70], desc: '범위(260) 안 자동 선택 대상(표식 > 정예 > 가장 가까운)에 강한 번개(반지름 45)', long: '레벨: 피해. 자동 목표는 작은 표시로 확인.',
    variants: { chain: { name: '연쇄 낙뢰', impl: true, desc: '주변 대상 2개에 추가 낙뢰(피해 50%)' }, storm: { name: '뇌우 지대', impl: true, desc: '타격 위치에 2초 동안 0.5초마다 약한 낙뢰(피해 30%)' } } },
  gravity:   { key: 'E', name: '중력핵', impl: true, max: 3, cooldown: [12, 11, 10], damage: [6, 9, 12], pull: [1.0, 1.3, 1.6], desc: '범위(260) 안 적 무리 중심에 1.2초 동안 작은 적을 끌어모음(반지름 140), 초당 피해', long: '레벨: 피해·끌어당김. 보스는 끌리지 않고 피해만.',
    variants: { collapse: { name: '붕괴', impl: true, desc: '끝날 때 폭발(피해 3배, 반지름 100)' }, orbit: { name: '궤도 포획', impl: true, desc: '작은 적이 1초 더 중심 주변에 붙잡힘' } } },
  ward:      { key: 'E', name: '수호 결계', impl: true, max: 3, cooldown: [14, 12, 10], shield: [30, 45, 60], desc: '4초 동안 피해를 흡수하는 보호막', long: '레벨: 흡수량. 파열 방벽처럼 깨져야 효과가 나오지 않습니다.',
    variants: { fortress: { name: '이동 요새', impl: true, desc: '유지 중 주변(반지름 60) 적을 조금씩 밀어냄' }, pulse: { name: '공격 결계', impl: true, desc: '유지 중 0.8초마다 주변(반지름 110) 공격 파동(피해 8)' } } },
};
PA.E_SKILLS = ['gust', 'bladestorm', 'strike', 'gravity', 'ward'];

// 보스 희귀 보상 4종. 현재 보스 목록에서 마지막 보스 뒤에는 제시하지 않는다(사용처 없음).
PA.BOSS_REWARDS = {
  resonance: { name: '무기 공명', impl: true, desc: '서로 다른 무기 3종이 4초 안에 같은 적을 치면 추가 폭발(피해 40, 반지름 70). 적당 6초 간격', tags: ['combo'] },
  seed:      { name: '연쇄의 씨앗', impl: true, desc: '냉기·화상·출혈이 있는 적 처치 시 반지름 90 안 적에게 남은 시간의 절반 전파(중첩 없음, 더 긴 쪽 유지)', tags: ['dot', 'chain'] },
  clone:     { name: '시간의 복제', impl: true, desc: '감속장을 통과하는 아군 투사체를 한 번 복제(복제본은 재복제 없음). 투사체 무기가 없으면 후보 제외', tags: ['projectile'] },
  volley:    { name: '일제 공격', impl: true, desc: 'E 기술 사용 시 장착 무기들이 즉시 한 번씩 추가 공격(추가 공격은 E 효과를 다시 일으키지 않음)', tags: ['combo'] },
};
PA.BOSSES = ['boss']; // 회차의 보스 순서. 마지막 보스 뒤에는 희귀 보상 없음(추적표 R-BOSS-13)

// 지역 성장 태그
PA.REGION_TAGS = { forest: ['melee', 'combo', 'bleed'], ridge: ['pierce', 'projectile', 'mod'], marsh: ['dot', 'zone', 'chain'], den: ['melee', 'bleed', 'combo'], deep: ['dot', 'zone', 'chain', 'projectile'], boss: [] };
PA.REGION_TAG_TEXT = { forest: '근접·연속 공격·출혈', ridge: '관통·투사체·무기 개조', marsh: '지속 피해·영역·처치 연쇄', den: '근접·출혈·연속 공격', deep: '지속 피해·영역·연쇄·투사체' };
