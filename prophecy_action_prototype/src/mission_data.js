// 출격 카드·전투 목표·거점 서비스 데이터 (v0.7). 모든 수치는 임시값(docs/ASSUMPTIONS.md).
var PA = (typeof PA !== 'undefined') ? PA : {};

// ---------- 전투 목표 4종(전멸·정예 처치 외) ----------
// 공통 규칙: 목표 달성이면 적이 살아 있어도 승리. 지원병은 유한 예산(budget)과 동시 상한(cap). 배치는 지형 검사(장애물 안·플레이어 근처 금지).
PA.OBJECTIVES = {
  hunt: { name: '정예 추적', short: '정예 처치', desc: '정예가 지원 병력과 함께 처음부터 등장한다. 정예를 처치하면 종료(지원병은 남아도 됨).',
    eliteType: 'wolf_alpha', escortN: 2, leashDist: 380, leashSpeed: 1.35, // 정예가 플레이어에서 멀어지면 접근 속도 상승(화면 밖 배회 금지)
    reinforce: { atHp: 0.5, budget: 3, cap: 5, interval: 1.5 }, // 정예 체력 50% 이하에 지원 1회(예산 3)
    hud: (o) => `정예 ${o.eliteKilled || 0} / ${o.eliteTotal || 1} 처치${o.elite && !o.elite.dead ? ` · 체력 ${Math.max(0, Math.ceil(o.elite.hp))} / ${Math.round(o.elite.hpMax)}` : ''}` },
  altars: { name: '제단 파괴', short: '제단 3개 파괴', desc: '떨어져 놓인 제단 3개를 부순다. 각 제단은 치료·바닥 위험·증원 중 하나를 맡고, 부수면 그 효과가 사라진다.',
    altarHp: 90, minGap: 200, minPlayerGap: 170, // 어떤 시작 무기로도 부술 수 있는 체력(검 9타 안팎)
    heal: { interval: 4, amount: 20, budget: 120, range: 320 },     // 치료 제단: 총 치료량 유한
    hazard: { interval: 5, warn: 1.0, ttl: 1.4, r: 52, dmg: 10, dist: 110, n: 2 }, // 위험 제단: 플레이어 좌우 ±90°에 2개(정면·후면 통로는 남김)
    reinforce: { interval: 6, budget: 5, cap: 4 },                   // 증원 제단: 유한 예산·동시 상한
    hud: (o) => `남은 제단 ${o.altars.filter(a => !a.dead).length} / 3` },
  seal: { name: '봉인 해제', short: '봉인 지점에서 버티기', desc: '봉인 지점 안에 있으면 진행, 벗어나면 멈춘다(진행은 유지). 피해를 받으면 잠시 멈춘다. 절반에서 지점이 옮겨진다.',
    time: 14, stages: 2, r: 66, hitPause: 0.6, moveWarn: 1.0, minGap: 260, // 단계별 목표 시간 7초, 총 14초(임시)
    reinforce: { interval: 4.5, budget: 6, cap: 4, first: 1.5 },
    hud: (o) => `봉인 ${Math.floor(o.progress / o.total * 100)}% · ${o.stage}/${o.stages}단계${o.paused ? ' · 정지' : ''}` },
  rescue: { name: '포로 구출', short: '포로 2명 구출 후 탈출', desc: '우리 2개 근처에 머물면 풀려난다(벗어나면 멈추고 다시 이어짐). 풀려난 포로는 알아서 빠져나간다. 둘 다 구한 뒤 출구에 닿으면 종료.',
    cages: 2, near: 72, time: 3.0, exitR: 44, prisonerSpeed: 130, minGap: 240,
    reinforce: { interval: 5, budget: 6, cap: 4, first: 2 },
    hud: (o) => o.freed >= o.cages ? '출구로 이동' : `구출 ${o.freed} / ${o.cages}${o.active ? ` · ${Math.floor(o.active.progress / o.active.total * 100)}%` : ''}` },
};
PA.OBJECTIVE_IDS = ['hunt', 'altars', 'seal', 'rescue'];

// 구조물: 적 목록에 들어가 자동 공격 대상이 되지만(모든 무기로 타격 가능) 경험치 0·처치 수 제외·이동 없음
PA.STRUCTURES = {
  altar_heal:      { name: '치료 제단', role: '구조물 · 적 치료', r: 22, hp: 90, speed: 0, color: '#8ee6a0', structure: true, altar: 'heal',      readme: '주기적으로 가장 다친 적을 치료한다(총량 유한). 부수면 멈춘다.' },
  altar_hazard:    { name: '위험 제단', role: '구조물 · 바닥 위험', r: 22, hp: 90, speed: 0, color: '#ff8a5c', structure: true, altar: 'hazard',  readme: '주기적으로 플레이어 좌우에 위험 지역을 예고 후 만든다. 부수면 멈춘다.' },
  altar_reinforce: { name: '증원 제단', role: '구조물 · 증원', r: 22, hp: 90, speed: 0, color: '#c9a2ff', structure: true, altar: 'reinforce', readme: '주기적으로 적을 부른다(예산·동시 상한 유한). 부수면 멈춘다.' },
};
for (const k in PA.STRUCTURES) { PA.ENEMIES[k] = PA.STRUCTURES[k]; PA.GROWTH.XP_VALUE[k] = 0; }

// ---------- 거점 서비스(임무·사건 보상): 회차 안에서만, 횟수제 ----------
PA.SERVICES = {
  free_rest:     { name: '무료 휴식권', desc: '다음 휴식 1회는 시간을 쓰지 않는다.', kind: 'service' },
  shop_discount: { name: '상인 할인권', desc: '다음 구매·제작 1회 금화 30% 할인.', kind: 'service', rate: 0.3 },
  mod_swap:      { name: '개조 교체권', desc: '거점에서 무기 전용 증강 1개를 떼고 그 무기의 다른 개조 3택(1회). 후보가 없으면 되돌리고 권은 유지.', kind: 'service' },
  reroll:        { name: '제시 재선택권', desc: '레벨업 3택 화면에서 1회 다시 제시(다른 순번의 제시, 같은 결과 반복 없음).', kind: 'service' },
};

// ---------- 출격 카드 ----------
// 하루 3장, 하루 시작에 시드로 확정·저장(다시 굴리기 없음). 임무는 하루 1회 완료. 일반 탐험(지역 선택)은 별도 유지.
PA.MISSIONS = {
  perDay: 3,
  // 지역별 등장 가능 날짜(첫 등장 이후 계속)
  regionFromDay: { forest: 1, ridge: 1, marsh: 2, den: 3, deep: 4 },
  // 목표별 기본 보상 종류(현재 빌드에 유효할 때) → 대안 순서. 마지막은 항상 금화(정해진 값)
  rewardByObjective: { hunt: ['weapon_level', 'common', 'gold'], altars: ['weapon_mod', 'common', 'gold'], seal: ['skill', 'common', 'gold'], rescue: ['service', 'gold'] },
  goldFallback: { forest: 40, ridge: 50, marsh: 70, den: 100, deep: 140 },
  kindText: { weapon_level: '무기 강화 3택', weapon_mod: '무기 개조 3택', skill: 'Q·E 기술 3택', common: '공통 증강 3택', service: '거점 서비스 3택', gold: '금화(정액)' },
  kindPools: { weapon_level: ['weapon_level'], weapon_mod: ['weapon_mod'], skill: ['skill_new', 'skill_level', 'skill_variant'], common: ['common'], service: ['service'] },
  // 위험 조건(v0.7-3에서 효과 적용): 지원병 증가·정예 호위·위험 지형. 2일차부터 확률 1/2
  risks: ['reinforce', 'escort', 'hazard'], riskFromDay: 2, riskChance: 0.5,
  riskText: { reinforce: '지원병 증가', escort: '정예 호위', hazard: '위험 지형' },
  riskRewardMult: 1.25, // 위험 조건 카드는 지역 금화 보상 ×1.25(눈에 보이는 증가)
};
