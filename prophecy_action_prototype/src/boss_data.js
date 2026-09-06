// 보스 3종 데이터와 3보스 회차 구조(v0.7). 모든 수치는 임시값(docs/ASSUMPTIONS.md). 가시갈기(PA.BOSS)는 단일 보스 회차 수치를 그대로 유지한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

// ---------- 봉인 수호자: 무거운 휩쓸기·고정 방향 직선 충격파·봉인 장치(주기적 바닥 위험) ----------
PA.BOSS_GUARDIAN = {
  id: 'guardian', name: '봉인 수호자', title: '봉인의 파수꾼',
  hp: 3000, speed: 95, r: 40, phases: [0.65, 0.3],
  intro: 1.6, roar: 0.9, stagger: 1.0, knockMult: 0.15, stopDist: 130,
  // 패턴 데이터: 준비(aim) → 확정(lock) → 실행 → 빈틈(recover). 피해·범위. 단계(2·3)에서 바뀌는 값은 phase 필드
  sweep: { aim: 0.8, lock: 0.45, radius: 165, arcDeg: 150, damage: 22, recover: 1.8, maxDist: 210 },
  shock: { aim: 0.6, lock: 0.35, len: 520, width: 70, speed: 900, damage: 18, recover: 1.6, minDist: 60, maxDist: 620, count: [1, 1, 2], gap: 0.4, spread: 0.35 }, // 3단계: 2발(±20°)
  devices: { count: 3, hp: 120, minGap: 220, minBossGap: 160, interval: 6, first: 3, warn: 1.1, ttl: 1.5, r: 55, dmg: 10, n: 2, dist: 110 }, // 장치당 주기적 바닥 위험 2개(플레이어 좌우). 파괴 시 그 장치의 패턴 제거
  orb: { healRatio: 0.15, r: 14, ring: 170 },
  overlap: { bossWaitMax: 1.0, maxHazardZones: 6 }, // 동시에 존재하는 장치 위험 상한(잔여+다음이 전장을 다 막지 않게)
  minApproach: 0.5,
  weights: { sweep: 1.2, shock: 1.2 },
  info: ['무거운 휩쓸기: 준비가 길고 부채꼴이 넓다(150°). 등 뒤로 돌아가면 안전.', '직선 충격파: 확정된 방향으로 굳은 뒤 파동이 날아간다. 옆으로 한 걸음.', '봉인 장치 3개가 주기적으로 바닥 위험을 만든다. 장치를 부수면 그 패턴이 사라진다(경험치 없음). 자동 공격 대상이 장치인지 보스인지 표시됨.', '완전 무적 구간 없음. 감속장(Q)은 준비·확정·빈틈과 파동을 늦춘다.', '넉백은 15%만, 방벽 파열은 진행 중 공격을 끊는다.'],
};
// ---------- 예언을 먹는 자: 과거 위치 표식 폭발·두 줄 순차 직선·광역 후 긴 빈틈·제한 소환 ----------
PA.BOSS_EATER = {
  id: 'eater', name: '예언을 먹는 자', title: '시간의 포식자',
  hp: 3600, speed: 100, r: 38, phases: [0.6, 0.3],
  intro: 1.8, roar: 1.0, stagger: 1.0, knockMult: 0.15, stopDist: 150,
  mark: { history: 2.5, sample: 0.5, count: [4, 6, 6], r: 58, cast: 0.5, delay: 1.2, gap: 0.25, damage: 14, recover: 1.4 }, // 플레이어의 지난 2.5초 위치를 표식(공개) → 1.2초 뒤 순차 폭발
  lanes: { warn: 0.7, lock: 0.3, width: 90, len: 720, speed: 1000, damage: 16, gap: 0.5, secondDeg: 70, recover: 1.5, minDist: 90 }, // 두 줄: 첫 줄은 플레이어 방향, 둘째 줄은 +70°(두 줄 사이 사분면은 안전)
  wide: { aim: 1.2, lock: 0.5, radius: [230, 230, 270], damage: 24, recover: 3.0, maxDist: 320 }, // 광역 뒤 긴 빈틈(피해 기회)
  summon: { count: 2, cap: 3, budget: 6, interval: 16, warn: 0.9, ring: [120, 190], pool: ['wolf', 'archer', 'spore'], duration: 1.4 }, // 마지막 단계 몬스터, 총 6마리·동시 3
  orb: { healRatio: 0.15, r: 14, ring: 170 },
  overlap: { bossWaitMax: 1.0 },
  minApproach: 0.5,
  weights: { mark: 1.5, lanes: 1.2, wide: 1.0, summon: 1.3 },
  info: ['표식: 당신이 지나온 자리에 원이 찍히고 잠시 뒤 차례로 터진다. 계속 움직이고 되돌아가지 않기.', '두 줄 직선: 첫 줄은 지금 위치, 둘째 줄은 70° 옆. 두 줄 사이로.', '광역 폭발 뒤에는 긴 빈틈(3초). 이때 몰아치기.', '소환은 총 6마리·동시 3마리로 제한. 숨거나 순간이동하지 않는다.', '체력 구간 무적·피해 상한 없음: 강한 빌드는 빨리 끝낸다.'],
};
PA.BOSS_DEFS = { boss: PA.BOSS, guardian: PA.BOSS_GUARDIAN, eater: PA.BOSS_EATER };
PA.ENEMIES.guardian = { name: '봉인 수호자', role: '보스 · 봉인의 파수꾼', r: 40, hp: 3000, speed: 95, color: '#5a6a9a', boss: true, readme: '무거운 휩쓸기·직선 충격파·봉인 장치.' };
PA.ENEMIES.eater = { name: '예언을 먹는 자', role: '보스 · 시간의 포식자', r: 38, hp: 3600, speed: 100, color: '#7a3a8a', boss: true, readme: '표식 폭발·두 줄 직선·광역·제한 소환.' };
PA.ENEMIES.seal_device = { name: '봉인 장치', role: '구조물 · 바닥 위험', r: 20, hp: 120, speed: 0, color: '#9ad0ff', structure: true, device: true, readme: '주기적으로 바닥 위험을 만든다. 부수면 멈춘다(경험치 없음).' };
PA.GROWTH.XP_VALUE.seal_device = 0; PA.GROWTH.XP_VALUE.guardian = 0; PA.GROWTH.XP_VALUE.eater = 0;
Object.assign(PA.BOSS_ACTION_TEXT, { shock_aim: '충격파 준비', shock_lock: '충격파!', mark_cast: '표식', mark_wait: '표식 폭발 대기', lanes_warn: '두 줄 직선 준비', lanes_lock: '직선!', lanes_fire: '직선 발사', wide_aim: '광역 준비', wide_lock: '광역!', summon: '소환' });

// 보스 체력 후보: 단일 보스 회차는 기존 수치, 3보스 회차는 단계 빌드 기준 후보(임시)
PA.BOSS_HP = { boss: { single: 2400, stage1: 1500 }, guardian: { stage2: 3000 }, eater: { stage3: 3600 } };

// ---------- 회차 구조 ----------
// single: 7일 단일 보스(기존 규칙, 이전 저장). trio: 1~2일 준비 → 3일차 시작에 보스1 → 3~4일 → 5일차 보스2 → 5~6일 → 7일차 최종
PA.RUN_MODES = {
  single: { name: '단일 보스 (7일, 기존)', days: 7, bosses: [{ id: 'boss', day: 7, hpKey: 'single', rare: false }] },
  trio:   { name: '보스 3마리 (7일, 시험)', days: 7, bosses: [{ id: 'boss', day: 3, hpKey: 'stage1', rare: true }, { id: 'guardian', day: 5, hpKey: 'stage2', rare: true }, { id: 'eater', day: 7, hpKey: 'stage3', rare: false }] },
};
// 범용 희귀 보상(유효 후보가 3개 미만일 때 채움용). 기존 4종은 적용 가능한 것만 후보
Object.assign(PA.BOSS_REWARDS, {
  vigor: { name: '불굴의 심장', impl: true, generic: true, desc: '최대 체력 +25(즉시 회복). 모든 빌드에 적용', tags: [] },
  tempo: { name: '시간의 박자', impl: true, generic: true, desc: '감속장(Q)·E 기술 재사용 15% 감소. 모든 빌드에 적용', tags: [] },
});
