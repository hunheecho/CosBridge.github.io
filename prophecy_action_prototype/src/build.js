// 회차 상태(장비·증강) → 전투에서 쓰는 실제 수치. 중복 적용을 막기 위해 항상 여기서만 계산한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Build = {
  emptyGear() { return { weapon: 'sword', armor: null, acc: null, upgrade: 0 }; },

  derive(run) {
    const C = PA.CONFIG;
    const gear = run.gear || PA.Build.emptyGear();
    const aug = run.augments || {};
    const level = (id) => aug[id] || 0;
    const has = (id) => level(id) > 0;
    const weaponId = gear.weapon || 'sword';
    const weapon = Object.assign({}, PA.CONFIG.WEAPONS[weaponId]);

    let damageMult = 1, rangeMult = 1, intervalMult = 1;
    damageMult *= 1 + 0.25 * level('sharp');
    rangeMult *= 1 + 0.25 * level('wide');
    intervalMult *= Math.pow(0.85, level('quick'));
    damageMult *= 1 + 0.15 * (gear.upgrade || 0);

    let hpMax = C.PLAYER.hp;
    if (gear.armor === 'leather_armor') hpMax += 30;

    let dodgeCdMult = 1, specialCd = C.PLAYER.special.cooldown, exposedMult = C.PLAYER.exposedMult;
    if (gear.acc === 'time_charm') { dodgeCdMult = 0.7; specialCd -= 3; }
    if (gear.acc === 'fang_necklace') exposedMult = 2.0;

    return {
      weaponId, weapon, damageMult, rangeMult, intervalMult, hpMax, dodgeCdMult, specialCd, exposedMult,
      damage: weapon.damage * damageMult,
      interval: weapon.interval * intervalMult,
      range: weapon.range * rangeMult,
      aug: Object.assign({}, aug), has, level,
      shield: has('barrier') ? C.BARRIER.shield : 0,
    };
  },

  // 미리보기용: 장비/증강 후보를 적용했을 때의 파생 수치
  preview(run, patch) {
    const r = { gear: Object.assign({}, run.gear), augments: Object.assign({}, run.augments) };
    if (patch.gear) Object.assign(r.gear, patch.gear);
    if (patch.augment) r.augments[patch.augment] = (r.augments[patch.augment] || 0) + 1;
    return PA.Build.derive(r);
  },

  // 실제 계산에 근거한 "늑대 처치 필요 타격 수"
  hitsToKill(build, enemyType) {
    const hp = PA.ENEMIES[enemyType].hp;
    return Math.ceil(hp / build.damage);
  },

  // 증강 제시 가능 여부
  augmentEligible(run, def) {
    const lv = (run.augments || {})[def.id] || 0;
    if (lv >= def.max) return false;
    if (def.requires && def.requires.some(r => !((run.augments || {})[r] > 0))) return false;
    return true;
  },

  // 증강이 현재 빌드에서 갖는 연결 설명 (선택 화면용)
  connectionText(run, def) {
    const b = PA.Build.derive(run);
    const lv = (run.augments || {})[def.id] || 0;
    const parts = [];
    if (def.id === 'wide') parts.push(b.weaponId === 'pierce' ? `관통 길이 ${Math.round(b.range)} → ${Math.round(b.range * 1.25)}` : `검격 반지름 ${Math.round(b.range)} → ${Math.round(b.range * 1.25)}`);
    if (def.id === 'sharp') { const nb = PA.Build.preview(run, { augment: 'sharp' }); parts.push(`피해 ${PA.fmt.num(b.damage)} → ${PA.fmt.num(nb.damage)} · 늑대 ${PA.Build.hitsToKill(b, 'wolf')}타 → ${PA.Build.hitsToKill(nb, 'wolf')}타`); }
    if (def.id === 'quick') parts.push(`공격 주기 ${PA.fmt.num(b.interval)}초 → ${PA.fmt.num(b.interval * 0.85)}초`);
    if (def.id === 'spin') parts.push(b.weaponId === 'pierce' ? '관통검과 함께: 3번째 공격만 회전' : '기본검과 함께: 3번째 검격이 회전');
    if (def.id === 'frost') parts.push(b.has('spin') ? '회전 검격으로 다수 냉기 부여 가능' : '검격 적중마다 냉기');
    if (def.id === 'ember') parts.push(b.has('flare') ? '불꽃 파열의 전제' : '회피 = 공격 기회. 이후 "불꽃 파열" 결합이 열림');
    if (def.id === 'flare') parts.push('잔불 걸음 보유 → 연결됨');
    if (def.id === 'stasis') parts.push('감속장(Q) 보유 → 연결됨');
    if (def.id === 'saving') parts.push('감속장(Q) 재사용 ' + PA.fmt.num(b.specialCd) + '초. 회피 성공마다 -4초');
    if (def.id === 'mark') parts.push('자동 공격 우선순위가 바뀝니다');
    if (def.id === 'echo') parts.push(b.weaponId === 'pierce' ? '관통 검격 반복' : '검격 반복');
    if (def.id === 'barrier') parts.push('체력과 별도의 보호막 게이지');
    if (lv > 0) parts.unshift(`현재 ${lv}단계 → ${lv + 1}단계`);
    return parts.join(' · ');
  },
};
