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

  // 증강이 현재 빌드에서 갖는 연결 설명 (선택 화면용). 모든 수치는 실제 파생 계산(preview)에서 온다.
  connectionText(run, def) {
    const b = PA.Build.derive(run), nb = PA.Build.preview(run, { augment: def.id });
    const lv = (run.augments || {})[def.id] || 0, has = (id) => b.has(id), pierce = b.weaponId === 'pierce';
    const parts = [];
    const wname = pierce ? '관통검' : '기본검';
    switch (def.id) {
      case 'wide': parts.push(pierce ? `현재 관통검의 길이 ${Math.round(b.range)} → ${Math.round(nb.range)}` : `현재 검격 반지름 ${Math.round(b.range)} → ${Math.round(nb.range)}`); if (has('spin')) parts.push(`회전 검격 반지름 ${Math.round(PA.CONFIG.SPIN.radius * b.rangeMult)} → ${Math.round(PA.CONFIG.SPIN.radius * nb.rangeMult)}`); break;
      case 'sharp': parts.push(`피해 ${PA.fmt.num(b.damage)} → ${PA.fmt.num(nb.damage)} · 늑대 ${PA.Build.hitsToKill(b, 'wolf')}타 → ${PA.Build.hitsToKill(nb, 'wolf')}타`); break;
      case 'quick': parts.push(`공격 주기 ${PA.fmt.num(b.interval)}초 → ${PA.fmt.num(nb.interval)}초`); if (has('spin')) parts.push('회전 검격도 더 자주'); break;
      case 'spin': parts.push(`${wname}의 3번째 공격이 반지름 ${Math.round(PA.CONFIG.SPIN.radius * b.rangeMult)} 회전 검격이 됩니다`); parts.push('감속장(Q) 안에 모인 적을 한 번에 쓸어내는 조합'); if (has('frost')) parts.push('회전으로 여러 적에게 냉기'); if (has('stasis')) parts.push('회전 검격도 흔적을 쌓습니다'); break;
      case 'ember': parts.push('회피(Space)할 때마다 경로에 불길 3개 (판정 성공과 무관)'); parts.push(has('flare') ? '불꽃 파열이 연결됩니다' : '이후 "불꽃 파열"이 제시됩니다'); break;
      case 'frost': parts.push(pierce ? '관통검: 한 줄의 적 모두에게 냉기' : '검격 적중마다 냉기 (관통검을 만들면 한 줄 전체)'); if (has('spin')) parts.push('회전 검격으로 주변 전체 냉기'); parts.push('냉기 상태 처치 시 파편 6개가 다른 적을 때려 연쇄'); break;
      case 'mark': parts.push('자동 공격 우선순위: 정예 > 궁수 > 포자 > 늑대. 표식 대상 피해 +30%'); break;
      case 'echo': parts.push(pierce ? '4번째 관통 검격이 0.2초 뒤 반복' : '4번째 검격이 0.2초 뒤 반복'); if (has('spin')) parts.push('회전 검격이 4번째라면 회전이 반복'); break;
      case 'barrier': parts.push('조우 시작 보호막 30 (체력과 별도). 파괴 시 돌진 중인 늑대도 밀쳐냅니다'); break;
      case 'stasis': parts.push(`감속장(Q) 안에서 ${wname}${has('spin') ? '·회전' : ''} 적중마다 흔적 (최대 5). 종료 시 흔적×${Math.round(PA.CONFIG.STASIS.damagePerStack * b.damageMult)} 피해`); break;
      case 'flare': parts.push(has('ember') ? '잔불 걸음의 불길 위에서 처치하면 반지름 80 폭발 ' + Math.round(PA.CONFIG.FLARE.damage * b.damageMult) + ' 피해' : '잔불 걸음이 필요합니다'); break;
      case 'saving': parts.push(`감속장(Q) 재사용 ${PA.fmt.num(b.specialCd)}초. 감속장 안 처치 1마리당 -${PA.CONFIG.SAVING.cdPerKill}초`); if (has('spin')) parts.push('회전 검격으로 감속장 안 다수 처치 시 크게 단축'); break;
    }
    if (lv > 0) parts.unshift(`현재 ${lv}단계 → ${lv + 1}단계`);
    return parts.join(' · ');
  },
};
