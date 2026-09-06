// 전투 시험실 데이터(v0.6): 체력 배율 후보, 빌드 프리셋, 적 조합 프리셋, 지형 프리셋. 모든 수치는 임시값이며 밸런스 확정이 아니다.
// 빌드 프리셋은 실제 게임 규칙(무기 3·방식 2·레벨 5·공통 3·패시브 4·기술 3레벨·변형 1)을 지켜야 하며 PA.Lab.validateBuild가 검사한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.LAB = {
  HP_MULTS: [1, 1.5, 2, 3, 4, 6, 8],
  TIME_LIMITS: [60, 120, 180, 300],
  DEFAULT_TIME: 180,
  // 빌드 프리셋: 무기와 레벨·전용 방식, 공통, 패시브, Q/E, 장비. approxPicks는 PA.Lab.pickCount가 계산한다.
  BUILDS: {
    early_sword:  { name: '초반 기본 검', stage: '초반', purpose: '시작 직후(선택 0회) 기준선. 검의 부채꼴로 근접 처리', growth: { weapons: [{ id: 'sword', level: 1 }] }, gear: {} },
    early_spear:  { name: '초반 관통창', stage: '초반', purpose: '시작 무기 차이 비교: 직선 관통, 일렬 유도', growth: { weapons: [{ id: 'spear', level: 1 }] }, gear: {} },
    early_blades: { name: '초반 회전 칼날', stage: '초반', purpose: '시작 무기 차이 비교: 궤도 접촉, 이동으로 적을 걸치기', growth: { weapons: [{ id: 'blades', level: 1 }] }, gear: {} },
    mid_melee:    { name: '중간 근접 조합', stage: '중간', purpose: '근접 2무기(검 교차 + 쌍검 출혈)와 넓어진 공격. 방패병·도적 상대 근접 대응 비교', growth: { weapons: [{ id: 'sword', level: 3, mods: ['cross'] }, { id: 'daggers', level: 2, mods: ['bleed'] }], commons: { wide: 1 }, passives: { mastery: 1 } }, gear: { upgrade: 1 } },
    mid_ranged:   { name: '중간 원거리 조합', stage: '중간', purpose: '추적궁 갈래 + 서리 수정 부채 + 긴 사거리 + 낙뢰. 접근 전에 처리하는 빌드가 적의 행동을 얼마나 보여주는가', growth: { weapons: [{ id: 'bow', level: 3, mods: ['spread'] }, { id: 'frost', level: 2, mods: ['fan'] }], commons: { reach: 1 }, passives: { haste: 1 }, e: { id: 'strike', level: 1 } }, gear: { upgrade: 1 } },
    slowfield:    { name: '감속장 중심 조합', stage: '중간', purpose: '감속장 Lv3 동행 + 정지된 칼날 + 시간 저축 + 회전 칼날 이중 궤도 + 집중. 감속장이 예고 읽기에 주는 여유를 비교', growth: { weapons: [{ id: 'sword', level: 2 }, { id: 'blades', level: 3, mods: ['dual'] }], commons: { stasis: 1, saving: 1, wide: 1 }, passives: { focus: 2 }, q: { level: 3, variant: 'follow' } }, gear: { upgrade: 1 } },
    dot:          { name: '불길·지속 피해 조합', stage: '중간', purpose: '불씨 정령(화염 띠·재점화) + 잔불 걸음 + 불꽃 파열 + 불붙은 공격 + 지속력. 바닥 유도형 빌드의 처치 시간 분포', growth: { weapons: [{ id: 'sword', level: 2 }, { id: 'ember', level: 3, mods: ['trail', 'reignite'] }], commons: { ember: 1, flare: 1, burn: 1 }, passives: { persistence: 2 } }, gear: { upgrade: 1 } },
    late_multi:   { name: '후반 다중 무기 조합', stage: '후반', purpose: '관통창 5(귀환·표식) + 회전 4(이중) + 구체 3(분기) + 숙련 3·가속 2 + 낙뢰 2 연쇄 + 강화 3·송곳니 목걸이·가죽 갑옷. 6일차 완성 빌드에 가까운 상한선', growth: { weapons: [{ id: 'spear', level: 5, mods: ['returning', 'brand'] }, { id: 'blades', level: 4, mods: ['dual'] }, { id: 'orb', level: 3, mods: ['fork'] }], commons: { stasis: 1, saving: 1, wide: 2 }, passives: { mastery: 3, haste: 2 }, e: { id: 'strike', level: 2, variant: 'chain' } }, gear: { upgrade: 3, acc: 'fang_necklace', armor: 'leather_armor' } },
    late_hammer:  { name: '후반 망치·지뢰 조합', stage: '후반', purpose: '전투망치 4(충격파·여진) + 룬 지뢰 3(연결·서리 함정) + 불씨 2 + 넓어진 공격 2 + 강인함·건강. 느리고 큰 한 방 계열의 상한선', growth: { weapons: [{ id: 'hammer', level: 4, mods: ['shockwave', 'aftershock'] }, { id: 'mine', level: 3, mods: ['chain', 'frosttrap'] }, { id: 'ember', level: 2 }], commons: { wide: 2, flare: 1, burn: 1 }, passives: { toughness: 2, vitality: 2, mastery: 1 }, e: { id: 'gravity', level: 2, variant: 'collapse' } }, gear: { upgrade: 2, armor: 'leather_armor' } },
  },
  // 지형 프리셋. auto = 조합 프리셋이 정한 기본 전장(일반 지역: 숲, 보스: 공터)
  TERRAINS: { auto: '조합 기본 지형', forest: '숲 전장(장애물 없음)', clearing: '공터(바위 2·나무 2)', pillars: '기둥 숲(바위 3·나무 1)' },
  ENEMY_ORDER: ['wolf', 'archer', 'spore', 'boar', 'shieldbearer', 'shaman', 'bomber', 'burrower', 'spider', 'frostcaller', 'rogue', 'wolf_alpha', 'boss'],
};

// 적 조합 프리셋. waves: 조우 웨이브. notes: 의도한 판단 / 안전 대응 / 강점 빌드 / 과도 겹침 조건 / 동시 실행 제한. overlapLimit: 동시에 준비·실행 가능한 적 수(0=제한 없음)
PA.LAB_COMBOS = [];
