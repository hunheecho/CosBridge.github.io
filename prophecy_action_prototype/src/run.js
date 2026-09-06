// 회차 상태: 날짜·시간·금화·재료·장비·증강·체력. 저장/불러오기. 전투 밖의 모든 규칙.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Run = (function () {
  const C = () => PA.CONFIG;
  const SAVE_KEY = 'prophecy_action_save_v1';   // 키는 유지(호환), 내용의 version으로 구분
  const RECORDS_KEY = 'prophecy_action_records_v1';
  const VERSION = 3;

  function newRun(seed, startWeapon) {
    const cfg = C();
    return {
      growth: PA.Growth.newGrowth(startWeapon || 'sword'),
      layout: 'classic', difficulty: 'base',   // v0.6: 지역 배치안·난이도 후보(기본은 기존 배치·×1)
      version: VERSION, seed: seed || (Date.now() % 100000), sortieCount: 0,
      phase: 'prep',            // prep(준비 기간) | boss_prep(7일차 최종 준비) | cleared(보스 처치)
      bossRetries: 0, bossClear: null,
      day: 1, hours: cfg.HOURS_PER_DAY,
      gold: cfg.START_GOLD, mats: { pelt: 0, iron: 0, spore: 0, fang: 0 },
      gear: PA.Build.emptyGear(), owned: [], augments: {}, // augments는 v2 이하 레거시 입력(growth로 이행)
      hp: cfg.PLAYER.hp,
      target: 'pierce_sword',
      log: [], // 최근 사건 기록(거점 표시)
      stats: { encounters: 0, wins: 0, losses: 0, kills: 0 },
      services: {}, cards: null, missionsDone: {}, // v0.7 거점 서비스 횟수·오늘의 출격 카드·목표별 완료 수
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
    if (r.version === 2 || !r.growth) { // v2 → v3: 증강·무기 소유를 성장 시스템으로 매핑(삭제하지 않음, 초과분은 거점에서 선택)
      r.legacyAugments = Object.assign({}, r.augments || {});
      r.growth = PA.Growth.migrateFromLegacy(r);
      r.version = 3;
    }
    if (r.gear && 'weapon' in r.gear) delete r.gear.weapon;
    if (!r.layout || !PA.LAYOUTS[r.layout]) r.layout = 'classic';                       // 이전 저장: 기존 배치 유지
    if (!r.difficulty || !PA.DIFFICULTY.candidates[r.difficulty]) r.difficulty = 'base';
    if (!r.services) r.services = {}; if (!r.missionsDone) r.missionsDone = {}; if (r.cards === undefined) r.cards = null; // v0.7 필드: 이전 저장은 기존 규칙 유지, 카드는 오늘부터 생성
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
  // 배치안: run.layout이 trial이면 시험안 웨이브, 아니면 기존 웨이브
  function layoutRegion(regionId, run) { const L = run && run.layout && PA.LAYOUTS[run.layout]; const lr = L && L.regions[regionId]; return lr || null; }
  function regionEnemies(regionId, run) { const lr = layoutRegion(regionId, run); return lr ? lr.enemies : region(regionId).enemies; }
  function regionArena(regionId, run) { const lr = layoutRegion(regionId, run); return lr && lr.arena ? lr.arena : 'forest'; }
  function encounterWaves(regionId, deep, run) {
    const r = region(regionId), lr = layoutRegion(regionId, run), base = lr ? lr.waves : r.waves;
    if (!deep) return base.map(w => w.map(g => Object.assign({}, g)));
    // 더 깊이: 웨이브마다 +1, 마지막에 정예 추가(없다면)
    const waves = base.map(w => w.map(g => ({ type: g.type, n: g.n + 1 })));
    const last = waves[waves.length - 1];
    if (!last.some(g => g.type === 'wolf_alpha')) last.push({ type: 'wolf_alpha', n: 1 });
    return waves;
  }
  function encounterObjective(regionId, deep, run) { const r = region(regionId), lr = layoutRegion(regionId, run); return deep ? 'elite' : ((lr && lr.objective) || r.objective); }
  // 지역별 체력 배율(난이도 후보). 보스는 1. 더 깊이 탐험은 후보의 deepMult
  function hpMultFor(run, regionId, deep) { const c = PA.DIFFICULTY.candidates[(run && run.difficulty) || 'base'] || PA.DIFFICULTY.candidates.base; const v = (c.hp[regionId] || 1) * (deep ? (c.deepMult || 1) : 1); return { normal: v, elite: v, boss: 1 }; }
  function layoutText(run) { const parts = []; if (run.layout && run.layout !== 'classic') parts.push('배치: ' + PA.LAYOUTS[run.layout].name); if (run.difficulty && run.difficulty !== 'base') parts.push('난이도: ' + PA.DIFFICULTY.candidates[run.difficulty].name); return parts.join(' · '); }
  function canDeepExplore(run, sortie) { return run.hours >= C().DEEP_EXPLORE_HOURS && !(sortie && sortie.mission); } // 임무 출격은 더 깊이 탐험 없음(특수 보상 반복 금지)
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
  function hasService(run, id) { return !!(run.services && run.services[id] > 0); }
  function useService(run, id) { if (!hasService(run, id)) throw new Error('서비스 없음'); run.services[id]--; addLog(run, `${PA.SERVICES[id].name} 사용`); }
  function canRest(run) { return (run.hours >= C().REST_HOURS || hasService(run, 'free_rest')) && run.hp < build(run).hpMax; }
  function rest(run) { if (!canRest(run)) throw new Error('휴식 불가'); if (hasService(run, 'free_rest')) useService(run, 'free_rest'); else run.hours -= C().REST_HOURS; run.hp = build(run).hpMax; addLog(run, '휴식: 체력 회복'); }
  function endDay(run) {
    if (run.phase !== 'prep') throw new Error('보스 준비 중에는 하루를 넘길 수 없음');
    run.day++; run.hours = C().HOURS_PER_DAY; run.hp = build(run).hpMax;
    addLog(run, '새로운 아침');
    if (isBossDay(run)) { run.phase = 'boss_prep'; addLog(run, '예언의 날: 최종 준비'); }
    if (PA.Sortie) PA.Sortie.cardsFor(run); // 오늘의 출격 카드 확정(시드·저장)
  }
  // ---------- 보스전 ----------
  function bossSeed(run) { return run.seed * 997 + 7; } // 같은 회차·같은 빌드 재도전 = 같은 시드·지형
  function canStartBoss(run) { return run.phase === 'boss_prep' || run.phase === 'cleared'; }
  function startBoss(run) {
    if (!canStartBoss(run)) throw new Error('보스 준비 상태가 아님');
    run.hp = build(run).hpMax; // 입장: 체력 완전 회복(회피·감속장·방벽은 전투 생성 시 초기화)
    run.bossEntry = JSON.parse(JSON.stringify({ growth: run.growth, hp: run.hp })); // 재도전 복구 기준(소환 경험치 누적 악용 방지)
    return { regionId: 'boss', seed: bossSeed(run), loot: { gold: 0, mats: {} }, encounters: 0 };
  }
  function bossDefeat(run) {
    run.bossRetries = (run.bossRetries || 0) + 1;
    if (run.bossEntry) { run.growth = JSON.parse(JSON.stringify(run.bossEntry.growth)); } // 입장 시 준비 상태로 복구(레벨·경험치·선택)
    run.hp = build(run).hpMax; addLog(run, `보스전 패배 (재도전 ${run.bossRetries}회, 성장은 입장 시점으로 복구)`);
  }
  function bossVictory(run, stats) {
    const b = build(run);
    const rec = { time: Math.round(stats.elapsed * 10) / 10, retries: run.bossRetries || 0, weapon: b.weapon.name, upgrade: run.gear.upgrade, acc: run.gear.acc, armor: run.gear.armor, augments: Object.assign({}, run.augments), specialUses: stats.specialUses || 0, bossDamage: Math.round(stats.bossDamage || 0), day: run.day, seed: run.seed, at: Date.now() };
    if (!run.bossClear) run.bossClear = rec; // 첫 처치 기록은 회차 안에서 유지
    run.lastBossClear = rec; run.phase = 'cleared';
    addLog(run, `가시갈기 처치 (${rec.time}초)`);
    return rec;
  }
  function ownedBySlot(run, slot) { return run.owned.filter(id => item(id) && item(id).slot === slot); }
  function unequip(run, slot) { if (slot === 'armor') run.gear.armor = null; else if (slot === 'acc') run.gear.acc = null; run.hp = Math.min(run.hp, build(run).hpMax); }
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
  function itemCost(run, it) { const c = it.slot === 'upgrade' ? it.costs[Math.min(run.gear.upgrade, it.costs.length - 1)] : it.cost; return hasService(run, 'shop_discount') ? Object.assign({}, c, { gold: Math.round(c.gold * (1 - PA.SERVICES.shop_discount.rate)) }) : c; }
  function itemAvailable(run, it) {
    if (it.slot === 'upgrade') return run.gear.upgrade < it.costs.length;
    if (it.slot === 'weapon') { const g = PA.Growth.ensure(run); return !run.owned.includes(it.id) && !PA.Growth.weaponOf(g, 'spear') && g.weapons.length < PA.GROWTH.SLOTS.weapons; }
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
    run.gold -= cost.gold; if (hasService(run, 'shop_discount')) useService(run, 'shop_discount');
    for (const k in cost.mats) run.mats[k] -= cost.mats[k];
    if (it.slot === 'upgrade') { run.gear.upgrade++; addLog(run, `무기 강화 +${run.gear.upgrade} (세 장착 무기 공통)`); }
    else if (it.slot === 'weapon') {
      run.owned.push(it.id);
      const g = PA.Growth.ensure(run);
      if (!PA.Growth.weaponOf(g, 'spear') && g.weapons.length < PA.GROWTH.SLOTS.weapons) { g.weapons.push({ id: 'spear', level: 1, mods: [] }); addLog(run, '관통창 획득(추가 무기 슬롯)'); }
      else addLog(run, '관통창 제작 — 슬롯이 차 있거나 이미 보유');
    } else {
      run.owned.push(it.id);
      equip(run, it.id);
      addLog(run, `${it.name} 획득·장착`);
    }
    if (run.target === it.id && !itemAvailable(run, it)) run.target = nextTarget(run);
  }
  function equip(run, itemId) {
    const it = item(itemId);
    if (!run.owned.includes(itemId)) throw new Error('미보유');
    if (it.slot === 'weapon') { /* 무기는 성장 슬롯에서 관리 */ }
    else if (it.slot === 'armor') run.gear.armor = itemId;
    else if (it.slot === 'acc') run.gear.acc = itemId;
    run.hp = Math.min(run.hp, build(run).hpMax);
  }
  function unequipWeapon(run) { /* v3: 무기 장착은 성장 슬롯. 호환용 no-op */ }
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
  function augmentOffers(run, rng, count) { // v3: 조우 승리 3택은 레벨업으로 통합. 호환용(빈 목록)
    return [];
  }
  function regionBonusXp(regionId, deep) { const v = PA.GROWTH.REGION_BONUS_XP[regionId] || 0; return deep ? Math.round(v * 1.5) : v; }
  function takeAugment(run, id) {
    const def = PA.AUGMENTS.find(a => a.id === id);
    if (!PA.Build.augmentEligible(run, def)) throw new Error('선택 불가');
    run.augments[id] = (run.augments[id] || 0) + 1;
    addLog(run, `증강: ${def.name}${def.max > 1 ? ' ' + run.augments[id] + '단계' : ''}`);
  }
  function skipAugment(run) { run.gold += C().SKIP_AUGMENT_GOLD; }

  // ---------- 저장 ----------
  function serialize(run) { return JSON.stringify(run); }
  function deserialize(s) { const r = JSON.parse(s); if (![1, 2, 3].includes(r.version)) throw new Error('저장 버전 불일치'); return migrate(r); }
  function save(run, storage) { storage = storage || globalThis.localStorage; try { storage.setItem(SAVE_KEY, serialize(run)); return true; } catch (e) { return false; } }
  function load(storage) { storage = storage || globalThis.localStorage; try { const s = storage.getItem(SAVE_KEY); return s ? deserialize(s) : null; } catch (e) { return null; } }
  function clearSave(storage) { storage = storage || globalThis.localStorage; try { storage.removeItem(SAVE_KEY); } catch (e) {} }

  return { SAVE_KEY, RECORDS_KEY, VERSION, hasService, useService, regionBonusXp, layoutRegion, regionEnemies, regionArena, hpMultFor, layoutText, migrate, bossSeed, canStartBoss, startBoss, bossDefeat, bossVictory, ownedBySlot, unequip, loadRecords, saveRecord, newRun, build, bossDaysLeft, isBossDay, region, canSortie, startSortie, encounterWaves, encounterObjective, canDeepExplore, deepExplore, rollReward, applyEncounterResult, returnToBase, defeat, canRest, rest, endDay, item, itemCost, itemAvailable, shortfall, canBuy, buy, equip, unequipWeapon, sell, setTarget, targetInfo, augmentOffers, takeAugment, skipAugment, serialize, deserialize, save, load, clearSave, addLog };
})();
