// 밸런스 후보 세트(v0.7.1). 기본은 현재값. 추천안은 docs/sim/COMPARE_v071.md의 비교 결과에 근거한 제안이며 확정값이 아니다.
// 세트는 전역 파라미터(처치·지역 경험치 배율, 보스 체력 세트, 창 기본값)를 바꾸고 회차에는 run.balance로 기록된다. 시험실·제목 화면에서는 현재값으로 되돌린다.
var PA = (typeof PA !== 'undefined') ? PA : {};
PA.BALANCE_SETS = {
  current:     { name: '현재값', difficulty: null, bossHpSet: 'base', killXp: 1, bonusXp: 1, spear: {}, desc: '적 체력 ×1, 보스 1500/3000/3600, 경험치 ×1, 창 피해 14·주기 0.7' },
  recommended: { name: '추천안 A (처치 경험치 ×0.5)', difficulty: 'candE', bossHpSet: 'hi', killXp: 0.5, bonusXp: 0.5, spear: { sweetFrom: 0.45, sweetMult: 0.5, interval: 0.85 }, desc: '적 체력 숲 1.5·능선 1.5·습지 2·굴 2·심층 3, 보스 2400/5000/7000, 처치 경험치 ×0.5, 지역 경험치 ×0.5, 창 근접 약화(사거리 45% 안쪽 ×0.5)+주기 0.85' },
  test03:      { name: '시험 빌드 (경험치 ×0.3)', difficulty: 'candE', bossHpSet: 'hi', killXp: 0.3, bonusXp: 0.3, spear: { sweetFrom: 0.45, sweetMult: 0.5, interval: 0.85 }, desc: '현재값 대비 처치·지역 경험치 ×0.3(중복 적용 없음), 적 체력 숲 1.5·능선 1.5·습지 2·굴 2·심층 3, 보스 2400/5000/7000, 창 근접 약화+주기 0.85' },
  test08:      { name: '시험 빌드 + 날짜 체력 후보 A', difficulty: 'candE', bossHpSet: 'hi', killXp: 0.3, bonusXp: 0.3, dayHp: 'dayA', spear: { sweetFrom: 0.45, sweetMult: 0.5, interval: 0.85 }, desc: '시험 빌드와 같고 날짜별 적 체력 배율(1/1/1.1/1.2/1.35/1.5/1.65)을 추가한 비교 후보. 편성 변화가 주축이고 체력은 보조' },
  recommended_b: { name: '추천안 B (처치 경험치 ×0.7)', difficulty: 'candE', bossHpSet: 'hi', killXp: 0.7, bonusXp: 0.5, spear: { sweetFrom: 0.45, sweetMult: 0.5, interval: 0.85 }, desc: '추천안 A와 같고 처치 경험치만 ×0.7(성장이 너무 느리면)' },
};
PA.BALANCE_DEFAULT = 'test03'; // 시작 화면·빠른 관문 경로의 기본 선택(시험 빌드). 현재값은 여전히 선택 가능
PA.Balance = (function () {
  const SPEAR_BASE = Object.assign({}, PA.WEAPONS.spear.base); // 원본 보존
  let active = 'current';
  function apply(id) {
    const B = PA.BALANCE_SETS[id] || PA.BALANCE_SETS.current; active = PA.BALANCE_SETS[id] ? id : 'current';
    PA.GROWTH.XP_KILL_MULT = B.killXp; PA.GROWTH.BONUS_XP_MULT = B.bonusXp; PA.BOSS_HP_SET = B.bossHpSet;
    PA.WEAPONS.spear.base = Object.assign({}, SPEAR_BASE, B.spear);
    return B;
  }
  function applyRun(run) { return apply((run && run.balance) || 'current'); }
  function current() { return active; }
  // 표시용 설정 요약(제목·결과 화면): 버전·세트·적 체력 후보·보스 체력·경험치 배율
  function text(run) { const id = (run && run.balance) || PA.BALANCE_DEFAULT, B = PA.BALANCE_SETS[id] || PA.BALANCE_SETS.current; const diff = PA.DIFFICULTY.candidates[(run && run.difficulty) || B.difficulty || 'base'] || PA.DIFFICULTY.candidates.base; const H = PA.BOSS_HP_SETS[B.bossHpSet]; const dh = (run && run.dayHpSet) || B.dayHp || 'none'; const lay = run && run.layout && run.layout !== 'classic' && PA.LAYOUTS && PA.LAYOUTS[run.layout] ? ' · 배치: ' + PA.LAYOUTS[run.layout].name : ''; const dif = run && run.difficulty && run.difficulty !== 'base' ? ' · 난이도: ' + diff.name : ''; return `v${PA.VERSION} · ${B.name}${dh !== 'none' ? ' · 날짜 체력 ' + dh : ''}${lay}${dif} · 적 체력 ${Object.values(diff.hp).join('/')} · 보스 체력 ${H.boss.stage1}/${H.guardian.stage2}/${H.eater.stage3} · 처치 경험치 ×${B.killXp} · 지역 경험치 ×${B.bonusXp}${B.spear && B.spear.interval ? ' · 창 주기 ' + B.spear.interval + '·근접 약화' : ''}`; }
  return { apply, applyRun, current, text, SPEAR_BASE };
})();
