// 회차 상태: 날짜·시간·금화·재료·장비·증강·체력. 저장/불러오기. 전투 밖의 모든 규칙.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Run = (function () {
  const C = () => PA.CONFIG;
  const SAVE_KEY = 'prophecy_action_save_v1';   // 키는 유지(호환), 내용의 version으로 구분
  const RECORDS_KEY = 'prophecy_action_records_v1';
  const VERSION = 2;

  function newRun(seed) {
    const cfg = C();
    return {
      version: VERSION, seed: seed || (Date.now() % 100000), sortieCount: 0,
      phase: 'prep',            // prep(준비 기간) | boss_prep(7일차 최종 준비) | cleared(보스 처치)
      bossRetries: 0, bossClear: null,
      day: 1, hours: cfg.HOURS_PER_DAY,
      gold: cfg.START_GOLD, mats: { pelt: 0, iron: 0, spore: 0, fang: 0 },
      gear: PA.Build.emptyGear(), owned: [], augments: {},
      hp: cfg.PLAYER.hp,
      target: 'pierce_sword',
      log: [], // 최근 사건 기록(거점 표시)
      stats: { encounters: 0, wins: 0, losses: 0, kills: 0 },
      ended: false,            // v1 호환 필드. v2에서는 phase를 사용
    };
  }
  // v1 저장 → v2: 7일차 ended=true 저장은 보스 준비 상태로 복구. 삭제하지 않는다.
  function migrate(r) {
    if (!r.version || r.version === 1) {
      r.version = 2;
      r.phase = (r.day >= C().BOSS_DAY) ? 'boss_prep' : 'prep';
      r.bossRetries = r.bossRetries || 0; r.bossClear = r.bossClear || null; r.ended = false;
    }
    if (!r.phase) r.phase = r.day >= C().BOSS_DAY ? 'boss_prep' : 'prep';
    return r;
  }

  function build(run) { return PA.Build.derive(run); }
  function bossDaysLeft(run) { return C().BOSS_DAY - run.day; }
  function isBossDay(run) { return run.day >= C().BOSS_DAY; }
  function addLog(run, msg) { run.log.unshift(`${run.day}일차 · ${msg}`); if (run.log.length > 8) run.log.length = 8; }

  // ---------- 지역/출격 ----------
  function region(id) { return PA.REGIONS.find(r => r.id === id); }
  function canSortie(run, regionId) { const r = region(regionId); return run.phase === 'prep' && !isBossDay(run) && run.hours >= r.cost; }
  function startSortie(run, regionId) {
    const r = region(regionId);
    if (!canSortie(run, regionId)) throw new Error('시간 부족');
    run.hours -= r.cost; run.sortieCount++;
    return { regionId, deep: false, loot: { gold: 0, mats: {}, chestGold: 0 }, encounters: 0, seed: run.seed * 131 + run.sortieCount * 17 + run.day };
  }
  function encounterWaves(regionId, deep) {
    const r = region(regionId);
    if (!deep) return r.waves.map(w => w.map(g => Object.assign({}, g)));
    // 더 깊이: 웨이브마다 +1, 마지막에 정예 추가(없다면)
    const waves = r.waves.map(w => w.map(g => ({ type: g.type, n: g.n + 1 })));
    const last = waves[waves.length - 1];
    if (!last.some(g => g.type === 'wolf_alpha')) last.push({ type: 'wolf_alpha', n: 1 });
    return waves;
  }
  function encounterObjective(regionId, deep) { const r = region(regionId); return deep ? 'elite' : r.objective; }
  function canDeepExplore(run) { return run.hours >= C().DEEP_EXPLORE_HOURS; }
  function deepExplore(run, sortie) { if (!canDeepExplore(run)) throw new Error('시간 부족'); run.hours -= C().DEEP_EXPLORE_HOURS; sortie.deep = true; }

  // 조우 승리 보상 계산(실제 난수는 전투의 rng 사용 → 재현 가능)
  function rollReward(run, sortie, rng, combatStats) {
    const r = region(sortie.regionId), mult = sortie.deep ? C().DEEP_REWARD_MULT : 1;
    const gold = Math.round(rng.int(r.reward.gold[0], r.reward.gold[1]) * mult);
    const mats = {};
    for (const k in r.reward.mats) {
      const [lo, hi] = r.reward.mats[k];
      let n = rng.int(lo, hi);
      if (k === 'fang') n = combatStats.eliteKilled ? 1 : 0; // 송곳니는 정예 처치 시에만
      else if (sortie.deep) n = Math.round(n * mult);
      if (n > 0) mats[k] = n;
    }
    return { gold, mats, chestGold: combatStats.chestGold || 0 };
  }
  function applyEncounterResult(run, sortie, result, reward, combatHp) {
    run.stats.encounters++; sortie.encounters++;
    run.hp = Math.max(0, combatHp);
    if (result === 'won') {
      run.stats.wins++;
      sortie.loot.gold += reward.gold + reward.chestGold;
      for (const k in reward.mats) sortie.loot.mats[k] = (sortie.loot.mats[k] || 0) + reward.mats[k];
    } else {
      run.stats.losses++;
    }
  }
  // 귀환: 전리품을 거점에 반영
  function returnToBase(run, sortie) {
    run.gold += sortie.loot.gold;
    for (const k in sortie.loot.mats) run.mats[k] = (run.mats[k] || 0) + sortie.loot.mats[k];
    const matText = Object.keys(sortie.loot.mats).map(k => `${PA.MATERIALS[k].name} ${sortie.loot.mats[k]}`).join(', ');
    addLog(run, `${region(sortie.regionId).name} 귀환: 금화 +${sortie.loot.gold}${matText ? ', ' + matText : ''}`);
  }
  // 패배: 전리품 상실, 시간 차감, 체력 30%
  function defeat(run, sortie) {
    const cfg = C();
    if (run.hours > 0) run.hours = Math.max(0, run.hours - cfg.DEFEAT_HOUR_PENALTY);
    run.hp = Math.round(build(run).hpMax * cfg.DEFEAT_HP_RATIO);
    addLog(run, `${region(sortie.regionId).name}에서 패배: 전리품 상실, 부상 치료 1시간`);
  }

  // ---------- 거점 행동 ----------
  function canRest(run) { return run.hours >= C().REST_HOURS && run.hp < build(run).hpMax; }
  function rest(run) { if (!canRest(run)) throw new Error('휴식 불가'); run.hours -= C().REST_HOURS; run.hp = build(run).hpMax; addLog(run, '휴식: 체력 회복'); }
  function endDay(run) {
    if (run.phase !== 'prep') throw new Error('보스 준비 중에는 하루를 넘길 수 없음');
    run.day++; run.hours = C().HOURS_PER_DAY; run.hp = build(run).hpMax;
    addLog(run, '새로운 아침');
    if (isBossDay(run)) { run.phase = 'boss_prep'; addLog(run, '예언의 날: 최종 준비'); }
  }
  // ---------- 보스전 ----------
  function bossSeed(run) { return run.seed * 997 + 7; } // 같은 회차·같은 빌드 재도전 = 같은 시드·지형
  function canStartBoss(run) { return run.phase === 'boss_prep' || run.phase === 'cleared'; }
  function startBoss(run) {
    if (!canStartBoss(run)) throw new Error('보스 준비 상태가 아님');
    run.hp = build(run).hpMax; // 입장: 체력 완전 회복(회피·감속장·방벽은 전투 생성 시 초기화)
    return { regionId: 'boss', seed: bossSeed(run), loot: { gold: 0, mats: {} }, encounters: 0 };
  }
  function bossDefeat(run) { run.bossRetries = (run.bossRetries || 0) + 1; run.hp = build(run).hpMax; addLog(run, `보스전 패배 (재도전 ${run.bossRetries}회)`); }
  function bossVictory(run, stats) {
    const b = build(run);
    const rec = { time: Math.round(stats.elapsed * 10) / 10, retries: run.bossRetries || 0, weapon: b.weapon.name, upgrade: run.gear.upgrade, acc: run.gear.acc, armor: run.gear.armor, augments: Object.assign({}, run.augments), specialUses: stats.specialUses || 0, bossDamage: Math.round(stats.bossDamage || 0), day: run.day, seed: run.seed, at: Date.now() };
    if (!run.bossClear) run.bossClear = rec; // 첫 처치 기록은 회차 안에서 유지
    run.lastBossClear = rec; run.phase = 'cleared';
    addLog(run, `가시갈기 처치 (${rec.time}초)`);
    return rec;
  }
  function ownedBySlot(run, slot) { return run.owned.filter(id => item(id) && item(id).slot === slot); }
  function unequip(run, slot) { if (slot === 'armor') run.gear.armor = null; else if (slot === 'acc') run.gear.acc = null; else if (slot === 'weapon') run.gear.weapon = 'sword'; run.hp = Math.min(run.hp, build(run).hpMax); }
  // 처치 기록(회차와 별도 보관, 새 회차로 삭제되지 않음)
  function loadRecords(storage) { storage = storage || globalThis.localStorage; try { const s = storage.getItem(RECORDS_KEY); return s ? JSON.parse(s) : { firstClear: null, clears: [] }; } catch (e) { return { firstClear: null, clears: [] }; } }
  function saveRecord(rec, storage) {
    storage = storage || globalThis.localStorage;
    const R = loadRecords(storage);
    if (!R.firstClear) R.firstClear = rec;
    R.clears.push(rec); if (R.clears.length > 20) R.clears.shift();
    try { storage.setItem(RECORDS_KEY, JSON.stringify(R)); } catch (e) {}
    return R;
  }

  // ---------- 상점/대장간 ----------
  function item(id) { return PA.ITEMS.find(i => i.id === id); }
  function itemCost(run, it) { return it.slot === 'upgrade' ? it.costs[Math.min(run.gear.upgrade, it.costs.length - 1)] : it.cost; }
  function itemAvailable(run, it) {
    if (it.slot === 'upgrade') return run.gear.upgrade < it.costs.length;
    return !run.owned.includes(it.id);
  }
  function shortfall(run, it) {
    const cost = itemCost(run, it), s = { gold: Math.max(0, cost.gold - run.gold), mats: {} };
    for (const k in cost.mats) { const need = cost.mats[k] - (run.mats[k] || 0); if (need > 0) s.mats[k] = need; }
    s.any = s.gold > 0 || Object.keys(s.mats).length > 0;
    return s;
  }
  function canBuy(run, it) { return itemAvailable(run, it) && !shortfall(run, it).any; }
  function buy(run, itemId) {
    const it = item(itemId);
    if (!canBuy(run, it)) throw new Error('구매 불가');
    const cost = itemCost(run, it);
    run.gold -= cost.gold;
    for (const k in cost.mats) run.mats[k] -= cost.mats[k];
    if (it.slot === 'upgrade') { run.gear.upgrade++; addLog(run, `무기 강화 +${run.gear.upgrade}`); }
    else {
      run.owned.push(it.id);
      equip(run, it.id);
      addLog(run, `${it.name} 획득·장착`);
    }
    if (run.target === it.id && !itemAvailable(run, it)) run.target = nextTarget(run);
  }
  function equip(run, itemId) {
    const it = item(itemId);
    if (!run.owned.includes(itemId)) throw new Error('미보유');
    if (it.slot === 'weapon') run.gear.weapon = itemId === 'pierce_sword' ? 'pierce' : 'sword';
    else if (it.slot === 'armor') run.gear.armor = itemId;
    else if (it.slot === 'acc') run.gear.acc = itemId;
    run.hp = Math.min(run.hp, build(run).hpMax);
  }
  function unequipWeapon(run) { run.gear.weapon = 'sword'; }
  function sell(run, matId, n) {
    n = n || 1;
    if ((run.mats[matId] || 0) < n) throw new Error('재료 부족');
    run.mats[matId] -= n; run.gold += PA.MATERIALS[matId].sell * n;
  }
  function nextTarget(run) { const c = PA.ITEMS.find(i => itemAvailable(run, i)); return c ? c.id : null; }
  function setTarget(run, itemId) { run.target = itemId; }
  // 목표 장비 안내: 부족분과 획득 지역
  function targetInfo(run) {
    if (!run.target) return null;
    const it = item(run.target); if (!it || !itemAvailable(run, it)) return null;
    const s = shortfall(run, it), cost = itemCost(run, it);
    const needs = [];
    if (s.gold > 0) needs.push({ kind: 'gold', name: '금화', need: s.gold, where: PA.REGIONS.map(r => r.name) });
    for (const k in s.mats) needs.push({ kind: k, name: PA.MATERIALS[k].name, need: s.mats[k], where: PA.MATERIALS[k].where.map(id => region(id).name) });
    return { item: it, cost, needs, ready: !s.any };
  }

  // ---------- 증강 ----------
  function augmentOffers(run, rng, count) {
    const pool = PA.AUGMENTS.filter(a => PA.Build.augmentEligible(run, a));
    return rng.shuffle(pool).slice(0, count || 3);
  }
  function takeAugment(run, id) {
    const def = PA.AUGMENTS.find(a => a.id === id);
    if (!PA.Build.augmentEligible(run, def)) throw new Error('선택 불가');
    run.augments[id] = (run.augments[id] || 0) + 1;
    addLog(run, `증강: ${def.name}${def.max > 1 ? ' ' + run.augments[id] + '단계' : ''}`);
  }
  function skipAugment(run) { run.gold += C().SKIP_AUGMENT_GOLD; }

  // ---------- 저장 ----------
  function serialize(run) { return JSON.stringify(run); }
  function deserialize(s) { const r = JSON.parse(s); if (r.version !== 1 && r.version !== 2) throw new Error('저장 버전 불일치'); return migrate(r); }
  function save(run, storage) { storage = storage || globalThis.localStorage; try { storage.setItem(SAVE_KEY, serialize(run)); return true; } catch (e) { return false; } }
  function load(storage) { storage = storage || globalThis.localStorage; try { const s = storage.getItem(SAVE_KEY); return s ? deserialize(s) : null; } catch (e) { return null; } }
  function clearSave(storage) { storage = storage || globalThis.localStorage; try { storage.removeItem(SAVE_KEY); } catch (e) {} }

  return { SAVE_KEY, RECORDS_KEY, VERSION, migrate, bossSeed, canStartBoss, startBoss, bossDefeat, bossVictory, ownedBySlot, unequip, loadRecords, saveRecord, newRun, build, bossDaysLeft, isBossDay, region, canSortie, startSortie, encounterWaves, encounterObjective, canDeepExplore, deepExplore, rollReward, applyEncounterResult, returnToBase, defeat, canRest, rest, endDay, item, itemCost, itemAvailable, shortfall, canBuy, buy, equip, unequipWeapon, sell, setTarget, targetInfo, augmentOffers, takeAugment, skipAugment, serialize, deserialize, save, load, clearSave, addLog };
})();
