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
    cmp_sword:  { name: '비교: 검(7선택)', stage: '비교', purpose: '무기 비교 기준: 검 Lv3 + 개조 1 + 공통 냉기·넓어진 공격 + 패시브 강인함·숙련. 장비·E 없음', growth: { weapons: [{ id: 'sword', level: 3, mods: ['cross'] }], commons: { frost: 1, wide: 1 }, passives: { toughness: 1, mastery: 1 } }, gear: {} },
    cmp_spear:  { name: '비교: 창(7선택)', stage: '비교', purpose: '무기 비교: 관통창 Lv3 + 개조 1(귀환 검기), 나머지 동일', growth: { weapons: [{ id: 'spear', level: 3, mods: ['returning'] }], commons: { frost: 1, wide: 1 }, passives: { toughness: 1, mastery: 1 } }, gear: {} },
    cmp_blades: { name: '비교: 회전 칼날(7선택)', stage: '비교', purpose: '무기 비교: 회전 칼날 Lv3 + 개조 1, 나머지 동일', growth: { weapons: [{ id: 'blades', level: 3, mods: [Object.keys(PA.WEAPONS.blades.mods).find(k => PA.WEAPONS.blades.mods[k].impl)] }], commons: { frost: 1, wide: 1 }, passives: { toughness: 1, mastery: 1 } }, gear: {} },
    stage1: { name: '1단계 빌드(3일차, Lv 9)', stage: '관문 1', purpose: '2일 준비 뒤 가시갈기(체력 후보 1500) 도전 시점의 평균 빌드: 검 3(십자) + 불씨 1 + 냉기 1, E 돌풍 1', growth: { weapons: [{ id: 'sword', level: 3, mods: ['cross'] }, { id: 'ember', level: 1 }], commons: { frost: 1 }, passives: { toughness: 1 }, e: { id: 'gust', level: 1 } }, gear: { upgrade: 0 } },
    stage2: { name: '2단계 빌드(5일차, Lv 18)', stage: '관문 2', purpose: '4일 준비 뒤 봉인 수호자(3000) 도전 시점: 검 5(십자·초승달) + 불씨 3(재점화) + 단검 2, 공통 냉기·화상, E 돌풍 2', growth: { weapons: [{ id: 'sword', level: 5, mods: ['cross', 'crescent'] }, { id: 'ember', level: 3, mods: ['reignite'] }, { id: 'daggers', level: 2 }], commons: { frost: 1, burn: 1 }, passives: { toughness: 1, mastery: 1, focus: 1 }, e: { id: 'gust', level: 2 } }, gear: { upgrade: 1, armor: 'leather_armor' } },
    stage3: { name: '3단계 빌드(7일차, Lv 26)', stage: '관문 3', purpose: '6일 준비 뒤 예언을 먹는 자(3600) 도전 시점: 검 5(십자·초승달) + 불씨 5(재점화·흔적) + 단검 4(출혈·측면), 공통 냉기·화상·불꽃, E 돌풍 3 변형', growth: { weapons: [{ id: 'sword', level: 5, mods: ['cross', 'crescent'] }, { id: 'ember', level: 5, mods: ['reignite', 'trail'] }, { id: 'daggers', level: 4, mods: ['bleed', 'flank'] }], commons: { frost: 1, burn: 1, flare: 1 }, passives: { toughness: 2, mastery: 2, focus: 1, vitality: 1 }, e: { id: 'gust', level: 3 } }, gear: { upgrade: 2, armor: 'leather_armor', acc: 'time_charm' } },
    late_hammer:  { name: '후반 망치·지뢰 조합', stage: '후반', purpose: '전투망치 4(충격파·여진) + 룬 지뢰 3(연결·서리 함정) + 불씨 2 + 넓어진 공격 2 + 강인함·건강. 느리고 큰 한 방 계열의 상한선', growth: { weapons: [{ id: 'hammer', level: 4, mods: ['shockwave', 'aftershock'] }, { id: 'mine', level: 3, mods: ['chain', 'frosttrap'] }, { id: 'ember', level: 2 }], commons: { wide: 2, flare: 1, burn: 1 }, passives: { toughness: 2, vitality: 2, mastery: 1 }, e: { id: 'gravity', level: 2, variant: 'collapse' } }, gear: { upgrade: 2, armor: 'leather_armor' } },
  },
  // 지형 프리셋. auto = 조합 프리셋이 정한 기본 전장(일반 지역: 숲, 보스: 공터)
  TERRAINS: { auto: '조합 기본 지형', forest: '숲 전장(장애물 없음)', clearing: '공터(바위 2·나무 2)', pillars: '기둥 숲(바위 3·나무 1)' },
  ENEMY_ORDER: ['wolf', 'archer', 'spore', 'boar', 'shieldbearer', 'shaman', 'bomber', 'burrower', 'spider', 'frostcaller', 'rogue', 'wolf_alpha', 'boss'],
};

// 적 조합 프리셋. waves: 조우 웨이브. notes: 의도한 판단 / 안전 대응 / 강점 빌드 / 과도 겹침 조건 / 동시 실행 제한. overlapLimit: 동시에 준비·실행 가능한 적 수(0=제한 없음)
PA.LAB_COMBOS = [
  { id: 'wolf_archer', name: '늑대 + 궁수', arena: 'forest', regionId: 'ridge', waves: [[{ type: 'wolf', n: 2 }], [{ type: 'archer', n: 2 }, { type: 'wolf', n: 2 }], [{ type: 'archer', n: 2 }, { type: 'wolf', n: 3 }]], overlapLimit: 0,
    desc: '돌진을 옆으로 피하면서 원거리 적에게 접근하는 기본 조합.', notes: { intent: '늑대 예고를 읽어 옆으로 피하는 동안 궁수 조준선이 겹치는 순간을 고른다', safe: '궁수 조준선 밖으로 비스듬히 이동 → 늑대 확정 뒤 옆으로 → 빈틈 늑대를 먼저 처치 → 궁수에게 접근', builds: '관통창(일렬 유도), 추적궁(접근 전 궁수 처리)', overlap: '늑대 3마리가 동시에 준비하고 화살이 같은 방향에서 오면 회피 공간이 한쪽으로만 남는다', limit: '기본 없음. 겹침이 잦으면 2로 시험' } },
  { id: 'shield_archer', name: '방패병 + 궁수', arena: 'forest', regionId: 'ridge', waves: [[{ type: 'shieldbearer', n: 1 }], [{ type: 'shieldbearer', n: 1 }, { type: 'archer', n: 2 }], [{ type: 'shieldbearer', n: 2 }, { type: 'archer', n: 2 }]], overlapLimit: 0,
    desc: '정면 방어를 우회해 후열에 접근한다.', notes: { intent: '정면에서 밀어붙이지 말고 방패병을 돌아 궁수를 먼저 잡을지, 방패치기 준비(방패 열림)를 기다릴지', safe: '방패병 옆으로 돌면서 궁수 조준선을 끊는 위치로 이동. 방패치기 예고가 뜨면 뒤로 빠졌다가 빈틈에 정면 타격', builds: '회전 칼날·쌍검(측면 타격 자연 발생), 낙뢰(방패 무시)', overlap: '방패병 2가 나란히 서서 궁수를 가리면 통로가 좁아진다', limit: '없음(방패병 공격은 짧다)' } },
  { id: 'boar_terrain', name: '멧돼지 + 장애물', arena: 'pillars', regionId: 'forest', waves: [[{ type: 'boar', n: 1 }], [{ type: 'boar', n: 2 }], [{ type: 'boar', n: 2 }, { type: 'wolf', n: 2 }]], overlapLimit: 0,
    desc: '지형으로 돌진을 유도해 긴 빈틈을 만든다.', notes: { intent: '바위 뒤에 서서 돌파 통로가 바위에서 끊기게 만들 것인가, 넓은 곳에서 옆으로 피할 것인가', safe: '바위 너머에 서 있다가 확정 뒤 옆으로. 충돌한 멧돼지는 2.4초 빈틈', builds: '전투망치(빈틈 큰 한 방), 룬 지뢰(돌진 경로에 설치)', overlap: '멧돼지 2마리가 다른 각도에서 동시에 확정하면 옆으로 피할 방향이 하나로 좁혀진다', limit: '2 권장(동시 돌파 2까지)' } },
  { id: 'boar_shaman', name: '멧돼지 + 주술사', arena: 'pillars', regionId: 'den', waves: [[{ type: 'boar', n: 1 }, { type: 'shaman', n: 1 }], [{ type: 'boar', n: 2 }, { type: 'shaman', n: 1 }]], overlapLimit: 0,
    desc: '긴 빈틈을 활용할지 후열 주술사를 먼저 잡을지 고르는 선택.', notes: { intent: '충돌한 멧돼지의 빈틈에 화력을 쏟을지, 그 사이 치료를 시전하는 주술사에게 갈지', safe: '주술사 시전선이 보이면 12 이상 한 방(망치·관통창)으로 끊고, 멧돼지는 바위에 부딪히게 유도', builds: '관통창(멧돼지와 주술사를 일렬로), 추적궁(주술사 원거리 처치)', overlap: '멧돼지 돌파 확정 중 주술사 저주 구슬이 같은 축에서 오면 회피 방향이 겹친다', limit: '없음' } },
  { id: 'spore_archer', name: '포자 + 궁수', arena: 'forest', regionId: 'marsh', waves: [[{ type: 'spore', n: 1 }, { type: 'archer', n: 1 }], [{ type: 'spore', n: 2 }, { type: 'archer', n: 2 }]], overlapLimit: 0,
    desc: '바닥 위험과 조준선을 동시에 읽는다.', notes: { intent: '구름이 남길 자리를 피하면서 조준선이 닿지 않는 위치를 고른다', safe: '포자가 부풀면 원 밖으로, 궁수 조준선과 직각 방향으로 이동. 포자는 사거리 밖에서 투사체로', builds: '추적궁·서리 수정(원거리), 불씨 정령(포자를 바닥에서 처리)', overlap: '구름 2개가 통로를 막은 상태에서 궁수 2명이 교차 조준하면 안전한 칸이 거의 없다', limit: '2 권장' } },
  { id: 'spider_wolf', name: '거미 + 늑대', arena: 'forest', regionId: 'marsh', waves: [[{ type: 'spider', n: 1 }, { type: 'wolf', n: 2 }], [{ type: 'spider', n: 2 }, { type: 'wolf', n: 3 }]], overlapLimit: 0,
    desc: '거미줄로 좁아진 경로에서 늑대 돌진을 피한다.', notes: { intent: '거미줄을 밟고 느려질지, 회피(Space)로 통과할지, 거미를 먼저 잡을지', safe: '거미줄 예고가 뜨면 진행 방향을 바꾸고, 늑대 확정 시 거미줄 없는 쪽으로 옆걸음. 회피는 거미줄 위에서도 정상 거리', builds: '기동력 패시브, 돌풍(늑대를 거미줄 쪽으로 밀기)', overlap: '거미줄 4개가 플레이어 주변을 둘러싼 상태에서 늑대 2마리 확정', limit: '없음(거미줄 수 상한 4로 제한)' } },
  { id: 'burrower_archer', name: '잠복충 + 궁수', arena: 'forest', regionId: 'den', waves: [[{ type: 'burrower', n: 1 }, { type: 'archer', n: 1 }], [{ type: 'burrower', n: 2 }, { type: 'archer', n: 2 }]], overlapLimit: 0,
    desc: '자리를 옮기면서 궁수에게 접근한다.', notes: { intent: '출현 예고 원 밖으로 나가는 방향을 궁수 조준선과 어긋나게 고른다', safe: '출현 원 밖으로 짧게 이동 → 출현 뒤 2초 빈틈에 처치 → 궁수', builds: '회전 칼날(출현 직후 접촉), 룬 지뢰(출현 지점 근처)', overlap: '잠복충 2마리의 출현 원이 겹치고 궁수 확정이 동시에 오면 피할 자리가 좁다', limit: '2 권장' } },
  { id: 'bomber_shield', name: '폭탄 운반체 + 방패병', arena: 'forest', regionId: 'marsh', waves: [[{ type: 'bomber', n: 2 }, { type: 'shieldbearer', n: 1 }], [{ type: 'bomber', n: 3 }, { type: 'shieldbearer', n: 1 }]], overlapLimit: 0,
    desc: '급한 위협(폭탄)부터 처리하고 방패병은 뒤로 미룬다.', notes: { intent: '방패병에게 막히는 동안 폭탄이 붙는다 — 어느 쪽을 먼저?', safe: '폭탄이 붙기 전에 투사체·원거리로 처치하거나, 준비 원 밖으로 빠져 터뜨리고 방패병은 측면으로', builds: '추적궁·서리 수정(폭탄 원거리 처치), 돌풍(폭탄을 방패병 쪽으로)', overlap: '폭탄 3개가 동시에 준비하면 안전한 칸이 없을 수 있다', limit: '2 권장(폭탄 준비 2까지)' } },
  { id: 'frost_wolf', name: '서리술사 + 늑대', arena: 'forest', regionId: 'deep', waves: [[{ type: 'frostcaller', n: 1 }, { type: 'wolf', n: 2 }], [{ type: 'frostcaller', n: 1 }, { type: 'wolf', n: 3 }]], overlapLimit: 0,
    desc: '순차 영역과 돌진의 순서를 읽는다.', notes: { intent: '1→2→3 순서를 읽어 늑대 돌진을 피할 방향을 정한다(터진 자리로 돌아가기)', safe: '영역 1이 터진 뒤 그 자리로 돌아가면서 늑대를 옆으로', builds: '기동력, 감속장(영역 사이 여유)', overlap: '3영역이 늑대 확정 통로와 직교하면 피할 칸이 하나뿐', limit: '2 권장' } },
  { id: 'rogue_archer', name: '쌍날 도적 + 궁수', arena: 'forest', regionId: 'den', waves: [[{ type: 'rogue', n: 1 }, { type: 'archer', n: 1 }], [{ type: 'rogue', n: 2 }, { type: 'archer', n: 2 }]], overlapLimit: 2,
    desc: '근접 압박 속에서 원거리 우선순위를 정한다.', notes: { intent: '도적 베기 2번을 받아내고 빈틈에 때릴지, 궁수부터 잡을지', safe: '베기 1 예고에 뒤로 한 걸음, 베기 2는 보정 한계(35°) 밖으로 → 1.6초 빈틈에 처치', builds: '쌍검(빈틈 집중), 수호 결계(베기 흡수)', overlap: '도적 2 + 궁수 2가 모두 확정하면 근접 두 방향과 조준선이 겹친다', limit: '2(도적 동시 준비 2까지)' } },
  { id: 'shaman_shield', name: '주술사 + 방패병', arena: 'forest', regionId: 'ridge', waves: [[{ type: 'shieldbearer', n: 2 }, { type: 'shaman', n: 1 }], [{ type: 'shieldbearer', n: 2 }, { type: 'shaman', n: 1 }, { type: 'archer', n: 1 }]], overlapLimit: 0,
    desc: '방어 전선을 돌아 지원 적을 처치한다.', notes: { intent: '방패병 2가 막는 동안 뒤에서 치료하는 주술사를 어떻게 끊을 것인가', safe: '방패병 방패치기 예고를 유도해 방패를 열고, 그 사이 옆으로 돌아 주술사에게', builds: '낙뢰(방패 무시), 추적궁·번개 구체(후열 도달)', overlap: '방패병 2가 나란히 서서 주술사를 완전히 가리면 접근 경로가 없다', limit: '없음' } },
  { id: 'bomber_wolf', name: '폭탄 운반체 + 늑대', arena: 'forest', regionId: 'marsh', waves: [[{ type: 'bomber', n: 1 }, { type: 'wolf', n: 2 }], [{ type: 'bomber', n: 2 }, { type: 'wolf', n: 3 }]], overlapLimit: 0,
    desc: '폭발 원에서 벗어나는 방향이 늑대 통로와 겹치지 않게.', notes: { intent: '폭탄을 먼저 처치할지, 원 밖으로 나가며 늑대를 유도할지', safe: '폭탄 준비 원 밖으로 나가되 늑대 확정 통로의 직각 방향', builds: '관통창(늑대와 폭탄 일렬), 회전 칼날', overlap: '폭발 원 안에서 늑대 2마리 확정', limit: '2 권장' } },
  { id: 'rogue_spider', name: '쌍날 도적 + 거미', arena: 'forest', regionId: 'deep', waves: [[{ type: 'spider', n: 1 }, { type: 'rogue', n: 1 }], [{ type: 'spider', n: 2 }, { type: 'rogue', n: 2 }]], overlapLimit: 2,
    desc: '경로가 제한된 상태의 근접 압박.', notes: { intent: '거미줄 위에서 도적 베기를 받지 않도록 자리를 관리한다', safe: '거미줄 예고 방향을 피해 이동, 도적 빈틈에만 붙기', builds: '기동력, 돌풍(도적 밀어내기)', overlap: '거미줄 안에서 도적 2가 양옆에서 준비', limit: '2' } },
  { id: 'late_mix', name: '후반 혼합(기존 + 신규)', arena: 'clearing', regionId: 'deep', waves: [[{ type: 'wolf', n: 3 }, { type: 'shieldbearer', n: 1 }, { type: 'archer', n: 2 }], [{ type: 'boar', n: 1 }, { type: 'spider', n: 1 }, { type: 'frostcaller', n: 1 }, { type: 'wolf', n: 2 }], [{ type: 'rogue', n: 2 }, { type: 'bomber', n: 2 }, { type: 'shaman', n: 1 }, { type: 'wolf_alpha', n: 1 }]], overlapLimit: 3,
    desc: '기존 적과 신규 적이 함께 등장하는 후반 조합. 후반 빌드 상한선 시험용.', notes: { intent: '우선순위(주술사 > 폭탄 > 궁수 > 나머지)를 매 웨이브 다시 정한다', safe: '공터 바위를 등지고 돌진류를 유도, 후열은 원거리·낙뢰로', builds: '후반 다중 무기, 후반 망치·지뢰', overlap: '3웨이브에서 도적 2·폭탄 2·정예가 동시에 붙으면 예고가 겹친다', limit: '3(동시 준비 3까지)' } },
];

// ---------- 지역 배치안 ----------
// classic: 기존 배치(비교 기준, PA.REGIONS 그대로). trial: 신규 적 소개 순서를 넣은 시험안. 정식 기본값은 classic이며 시험안은 새 회차 시작 화면에서 고른다.
PA.LAYOUTS = {
  classic: { name: '기존 배치(비교 기준)', regions: {} },
  trial: { name: '시험안 배치(신규 적 소개)', regions: {
    forest: { desc: '늑대 무리. 두 번째 웨이브부터 멧돼지 1마리가 긴 돌파를 보여준다(단독 학습).', enemies: ['wolf', 'boar'], arena: 'pillars', waves: [[{ type: 'wolf', n: 2 }], [{ type: 'wolf', n: 2 }, { type: 'boar', n: 1 }], [{ type: 'wolf', n: 3 }, { type: 'boar', n: 1 }]] },
    ridge: { desc: '궁수 뒤에 방패병이 선다. 정면 방어 우회를 배운 뒤 마지막에 도적이 측면으로 온다.', enemies: ['archer', 'shieldbearer', 'rogue'], arena: 'forest', waves: [[{ type: 'archer', n: 2 }], [{ type: 'shieldbearer', n: 1 }, { type: 'archer', n: 2 }], [{ type: 'shieldbearer', n: 1 }, { type: 'archer', n: 2 }, { type: 'rogue', n: 1 }]] },
    marsh: { desc: '포자 구름 사이로 거미줄과 폭탄 운반체. 바닥 위험을 겹쳐 읽는다.', enemies: ['spore', 'spider', 'bomber', 'archer'], arena: 'forest', waves: [[{ type: 'spore', n: 1 }, { type: 'spider', n: 1 }], [{ type: 'spore', n: 2 }, { type: 'bomber', n: 2 }], [{ type: 'spore', n: 2 }, { type: 'spider', n: 1 }, { type: 'bomber', n: 2 }, { type: 'archer', n: 1 }]] },
    den: { desc: '늑대 굴에 주술사와 잠복충. 우두머리를 처치하면 조우 종료.', enemies: ['wolf', 'shaman', 'burrower', 'wolf_alpha'], arena: 'forest', objective: 'elite', waves: [[{ type: 'wolf', n: 3 }], [{ type: 'wolf', n: 2 }, { type: 'shaman', n: 1 }, { type: 'burrower', n: 1 }], [{ type: 'wolf_alpha', n: 1 }, { type: 'wolf', n: 2 }, { type: 'shaman', n: 1 }]] },
    deep: { desc: '서리술사의 순차 영역과 모든 위협의 조합.', enemies: ['frostcaller', 'archer', 'spore', 'boar', 'rogue', 'spider', 'wolf_alpha', 'shaman', 'bomber'], arena: 'clearing', objective: 'elite', waves: [[{ type: 'frostcaller', n: 1 }, { type: 'archer', n: 2 }, { type: 'spore', n: 1 }], [{ type: 'boar', n: 1 }, { type: 'rogue', n: 2 }, { type: 'spider', n: 1 }], [{ type: 'wolf_alpha', n: 1 }, { type: 'shaman', n: 1 }, { type: 'bomber', n: 2 }, { type: 'frostcaller', n: 1 }, { type: 'wolf', n: 2 }]] },
  } },
};
// ---------- 지역별 난이도(체력 배율) 후보 ----------
// 정식 기본값은 base(×1). 후보는 지역/깊이에 연결되며, 플레이어의 현재 화력에 따라 실시간으로 바뀌지 않는다. 보스 배율은 여기서 다루지 않는다(1).
PA.DIFFICULTY = {
  candidates: {
    base:  { name: '기준(전 지역 ×1)', hp: { forest: 1, ridge: 1, marsh: 1, den: 1, deep: 1 }, deepMult: 1 },
    candE: { name: '제안안(숲 1.5 + 후보 A: 1.5 / 1.5 / 2 / 2 / 3)', hp: { forest: 1.5, ridge: 1.5, marsh: 2, den: 2, deep: 3 }, deepMult: 1 },
    candA: { name: '후보 A: 깊이 비례(1 / 1.5 / 2 / 2 / 3)', hp: { forest: 1, ridge: 1.5, marsh: 2, den: 2, deep: 3 }, deepMult: 1 },
    candB: { name: '후보 B: 초반 유지·후반 급증(1 / 1 / 2 / 3 / 4)', hp: { forest: 1, ridge: 1, marsh: 2, den: 3, deep: 4 }, deepMult: 1 },
    candC: { name: '후보 C: 전 지역 ×2 + 더 깊이 ×1.5', hp: { forest: 2, ridge: 2, marsh: 2, den: 2, deep: 2 }, deepMult: 1.5 },
    candD: { name: '후보 D: 완만 상승 + 더 깊이 ×1.5(1 / 1.5 / 1.5 / 2 / 2.5)', hp: { forest: 1, ridge: 1.5, marsh: 1.5, den: 2, deep: 2.5 }, deepMult: 1.5 },
  },
};
