// 탐험 사건 6종(전투 뒤 안전 화면, 출격당 최대 1회). 시드로 생성·저장(run.pendingSortie)·재현. 비용·보상은 정확히 1회 정산. 화면·봇 공용.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.EVENTS = {
  chance: 0.5, // 조우 승리 뒤 사건이 나올 확률(임시)
  weapon_altar: { name: '불안정한 무기 제단', hpCost: 0.25, desc: '체력을 바쳐 보유 무기의 개조 1개를 고른다(3택). 개조 슬롯이 남은 무기가 있어야 한다. 강제 제거 없음.',
    valid: (run, s) => PA.Sortie.kindValid(run, 'weapon_mod') && PA.Events.altarCost(run) < run.hp - 1 },
  supply: { name: '버려진 보급소', heal: 0.5, gold: 40, desc: '회복 또는 물자 중 하나만. 휴식 대신 쓰지 않도록 이틀에 한 번만 나온다.',
    valid: (run) => run.day - (run.lastSupplyDay == null ? -9 : run.lastSupplyDay) >= 2 },
  merchant: { name: '갇힌 상인', desc: '추가 전투(지역 웨이브 + 정예, 체력 회복 없음, 새 전리품 없음)에 이기면 이번 회차 거점 서비스 1종 해금.',
    services: ['mod_swap', 'reroll'], valid: (run, s) => !s.mission && !s.deep && run.hp >= PA.Run.build(run).hpMax * 0.35 },
  time_spring: { name: '시간의 샘', hours: 1, cdBuff: 0.7, desc: '다음 전투 1회 감속장·E 재사용 -30%(무료) 또는 1시간을 내고 완전 회복. 재사용은 조우마다 이미 초기화되므로 임시 강화로 설계(가정 기록).',
    valid: (run) => true },
  sealed_loot: { name: '봉인된 전리품', goldMult: 2, desc: '지금 귀환하거나, 정예 추가 전투(더 깊이 탐험 경로, 1시간)로 밝혀진 특수 보상을 노린다: 이번 더 깊이 전투의 금화 ×2 + 지역 보상 3택.',
    valid: (run, s) => !s.deep && !s.mission && PA.Run.canDeepExplore(run, s) },
  scout: { name: '정찰자의 정보', desc: '오늘 남은 출격 카드 1장의 위험 조건을 교체한다(정보는 이미 공개되어 있으므로 교체 서비스). 새로고침 재선택 없음.',
    valid: (run, s) => PA.Sortie.cardsFor(run).some(c => !c.done && c.id !== s.cardId) },
};
PA.EVENT_IDS = ['weapon_altar', 'supply', 'merchant', 'time_spring', 'sealed_loot', 'scout'];

PA.Events = (function () {
  const E = () => PA.EVENTS;
  function altarCost(run) { return Math.round(PA.Run.build(run).hpMax * E().weapon_altar.hpCost); }
  function nextRisk(cur, seed) { const list = [null].concat(PA.MISSIONS.risks).filter(r => r !== cur); return list[seed % list.length]; }
  // 사건 생성(결정적): 출격 시드 기준. 같은 출격에서 다시 굴려도 같은 결과. 직전 사건과 같은 종류는 피한다
  function roll(run, sortie) {
    if (sortie.event || sortie.deep || sortie.eventFight) return null;
    const rng = PA.rng.create((sortie.seed * 13 + 101 + (sortie.encounters || 0) * 7) >>> 0);
    if (rng.next() >= E().chance) return null;
    const valid = PA.EVENT_IDS.filter(id => E()[id].valid(run, sortie) && id !== run.lastEvent);
    if (!valid.length) return null;
    const id = valid[rng.int(0, valid.length - 1)];
    const ev = { id, seed: rng.int(0, 1e9), resolved: false, choice: null };
    if (id === 'scout') { const cards = PA.Sortie.cardsFor(run).filter(c => !c.done && c.id !== sortie.cardId); const c = cards[ev.seed % cards.length]; ev.cardId = c.id; ev.fromRisk = c.risk; ev.toRisk = nextRisk(c.risk, ev.seed >> 3); }
    if (id === 'merchant') ev.service = E().merchant.services[ev.seed % 2];
    return ev;
  }
  // 선택지(화면·봇 공용): {id, name, cost, effect, enabled}
  function options(run, sortie) {
    const ev = sortie.event, b = PA.Run.build(run), out = [];
    if (!ev) return out;
    if (ev.id === 'weapon_altar') { const cost = altarCost(run); out.push({ id: 'pay', name: `체력 ${cost}을 바치고 개조 3택`, cost: `체력 -${cost} (${run.hp} → ${run.hp - cost})`, effect: '보유 무기 개조 3택(유효 후보만)', enabled: run.hp - cost > 1 && PA.Sortie.kindValid(run, 'weapon_mod') }); out.push({ id: 'leave', name: '지나친다', cost: '없음', effect: '없음', enabled: true }); }
    else if (ev.id === 'supply') { const heal = Math.round(b.hpMax * E().supply.heal); const r = PA.Run.region(sortie.regionId), mat = Object.keys(r.reward.mats).filter(k => k !== 'fang')[0]; out.push({ id: 'heal', name: `치료 (+${heal})`, cost: '없음', effect: `체력 ${run.hp} → ${Math.min(b.hpMax, run.hp + heal)}`, enabled: run.hp < b.hpMax }); out.push({ id: 'loot', name: `물자 (금화 +${E().supply.gold}${mat ? ', ' + PA.MATERIALS[mat].name + ' +1' : ''})`, cost: '없음', effect: '이번 출격 전리품에 추가(귀환 시 확정)', enabled: true }); out.push({ id: 'leave', name: '지나친다', cost: '없음', effect: '없음', enabled: true }); }
    else if (ev.id === 'merchant') { const S = PA.SERVICES[ev.service]; out.push({ id: 'fight', name: '상인을 구한다 (추가 전투)', cost: `지역 웨이브 + 정예 1, 체력 회복 없음(${run.hp}/${b.hpMax}), 패배 시 이번 출격 전리품 상실`, effect: `승리 시 해금: ${S ? S.name : ev.service} — ${S ? S.desc : ''}. 새 전리품·재료 없음`, enabled: true }); out.push({ id: 'leave', name: '지나친다', cost: '없음', effect: '없음', enabled: true }); }
    else if (ev.id === 'time_spring') { out.push({ id: 'buff', name: '샘물을 마신다 (다음 전투 강화)', cost: '없음', effect: '다음 전투 1회: 감속장·E 재사용 ×0.7', enabled: !(run.buffs && run.buffs.skillCd) }); out.push({ id: 'heal', name: `치료를 받는다 (1시간)`, cost: `시간 -1 (${run.hours} → ${run.hours - 1})`, effect: `체력 ${run.hp} → ${b.hpMax}`, enabled: run.hours >= E().time_spring.hours && run.hp < b.hpMax }); out.push({ id: 'leave', name: '지나친다', cost: '없음', effect: '없음', enabled: true }); }
    else if (ev.id === 'sealed_loot') { out.push({ id: 'fight', name: '봉인을 깨러 간다 (더 깊이 탐험, 1시간)', cost: `시간 -1 (${run.hours} → ${run.hours - 1}), 적 수 +1·마지막에 정예`, effect: `밝혀진 보상: 금화 ×${E().sealed_loot.goldMult}(더 깊이 ×${PA.CONFIG.DEEP_REWARD_MULT} 위에) + 지역 보상 3택 1회 (${PA.REGION_TAG_TEXT[sortie.regionId] || ''})`, enabled: PA.Run.canDeepExplore(run, sortie) }); out.push({ id: 'leave', name: '전리품을 가지고 귀환', cost: '없음', effect: '현재 전리품 유지', enabled: true }); }
    else if (ev.id === 'scout') { const c = PA.Sortie.card(run, ev.cardId); const R = PA.MISSIONS.riskText; out.push({ id: 'swap', name: `카드 교체: ${c ? PA.Run.region(c.regionId).name + ' · ' + PA.Sortie.objectiveName(c.objective) : ev.cardId}`, cost: '없음', effect: `위험 조건 ${ev.fromRisk ? R[ev.fromRisk] : '없음'} → ${ev.toRisk ? R[ev.toRisk] : '없음'}${ev.toRisk ? ' (금화 ×' + PA.MISSIONS.riskRewardMult + ')' : ''}`, enabled: !!c && !c.done }); out.push({ id: 'leave', name: '듣지 않는다', cost: '없음', effect: '없음', enabled: true }); }
    return out;
  }
  // 선택 적용(정확히 1회). 반환: { next: 'after' | 'fight' | 'deep' | 'offer', offer? }
  function resolve(run, sortie, optId) {
    const ev = sortie.event; if (!ev || ev.resolved) throw new Error('사건 없음/이미 처리');
    const opt = options(run, sortie).find(o => o.id === optId); if (!opt || !opt.enabled) throw new Error('선택 불가');
    ev.resolved = true; ev.choice = optId; run.lastEvent = ev.id; run.eventsResolved = (run.eventsResolved || 0) + 1; const g = run.growth; g.picks.event = (g.picks.event || 0) + 1;
    const b = PA.Run.build(run);
    if (optId === 'leave') { PA.Run.addLog(run, `${E()[ev.id].name}: 지나침`); return { next: 'after' }; }
    switch (ev.id) {
      case 'weapon_altar': { const cost = altarCost(run); run.hp = Math.max(1, run.hp - cost); g.pendingEventPick = { kind: 'weapon_mod', regionId: sortie.regionId, key: ev.id + ':' + sortie.seed }; PA.Run.addLog(run, `무기 제단: 체력 -${cost}, 개조 3택`); return { next: 'offer' }; }
      case 'supply': { if (optId === 'heal') { run.hp = Math.min(b.hpMax, run.hp + Math.round(b.hpMax * E().supply.heal)); PA.Run.addLog(run, '보급소: 치료'); } else { const r = PA.Run.region(sortie.regionId), mat = Object.keys(r.reward.mats).filter(k => k !== 'fang')[0]; sortie.loot.gold += E().supply.gold; if (mat) sortie.loot.mats[mat] = (sortie.loot.mats[mat] || 0) + 1; PA.Run.addLog(run, `보급소: 금화 +${E().supply.gold}`); } run.lastSupplyDay = run.day; return { next: 'after' }; }
      case 'merchant': { sortie.eventFight = 'merchant'; sortie.eventService = ev.service; return { next: 'fight' }; }
      case 'time_spring': { if (optId === 'buff') { run.buffs = run.buffs || {}; run.buffs.skillCd = E().time_spring.cdBuff; PA.Run.addLog(run, '시간의 샘: 다음 전투 재사용 ×0.7'); } else { run.hours -= E().time_spring.hours; run.hp = b.hpMax; PA.Run.addLog(run, '시간의 샘: 치료(1시간)'); } return { next: 'after' }; }
      case 'sealed_loot': { PA.Run.deepExplore(run, sortie); sortie.deepGoldMult = E().sealed_loot.goldMult; PA.Run.addLog(run, '봉인된 전리품: 더 깊이 탐험'); return { next: 'deep' }; }
      case 'scout': { const c = PA.Sortie.card(run, ev.cardId); c.risk = ev.toRisk; c.enemies = PA.Sortie.mainEnemies(run, c.regionId, c.objective, c.risk); PA.Run.addLog(run, `정찰자: ${PA.Run.region(c.regionId).name} 카드 위험 조건 교체`); return { next: 'after' }; }
    }
    return { next: 'after' };
  }
  // 상인 추가 전투: 지역 웨이브 + 정예(더 깊이와 같은 구성), 전멸 목표, 전리품 없음
  function fightOpts(run, sortie) { const waves = PA.Run.encounterWaves(sortie.regionId, true, run); return { waves, objective: 'clear', seed: sortie.seed + 9000 + (sortie.encounters || 0) * 1000, eventFight: sortie.eventFight }; }
  // 추가 전투 승리 정산(Flow.settleVictory에서): 서비스 해금만
  function onFightWin(run, sortie) { if (sortie.eventFight === 'merchant' && !sortie.eventFightDone) { sortie.eventFightDone = true; run.services = run.services || {}; run.services[sortie.eventService] = (run.services[sortie.eventService] || 0) + 1; PA.Run.addLog(run, `상인 구출: ${PA.SERVICES[sortie.eventService].name} 해금`); } sortie.eventFight = null; }
  // 봇 선택 정책(회차 시뮬레이션): risky는 전투·제단, cautious는 치료, 기본은 무료 이득만
  function botChoose(run, sortie, strat) {
    const opts = options(run, sortie).filter(o => o.enabled), ev = sortie.event, has = (id) => opts.find(o => o.id === id);
    const risky = strat === 'risky' || strat === 'deep', cautious = strat === 'cautious';
    if (ev.id === 'weapon_altar') return risky && run.hp > PA.Run.build(run).hpMax * 0.6 && has('pay') ? 'pay' : 'leave';
    if (ev.id === 'supply') return cautious && has('heal') ? 'heal' : run.hp < PA.Run.build(run).hpMax * 0.5 && has('heal') ? 'heal' : 'loot';
    if (ev.id === 'merchant') return risky && has('fight') ? 'fight' : 'leave';
    if (ev.id === 'time_spring') return cautious && has('heal') && run.hp < PA.Run.build(run).hpMax * 0.6 ? 'heal' : has('buff') ? 'buff' : 'leave';
    if (ev.id === 'sealed_loot') return risky && has('fight') && run.hp >= PA.Run.build(run).hpMax * 0.5 ? 'fight' : 'leave';
    if (ev.id === 'scout') return has('swap') && !ev.toRisk ? 'swap' : 'leave';
    return 'leave';
  }
  return { altarCost, roll, options, resolve, fightOpts, onFightWin, botChoose };
})();
