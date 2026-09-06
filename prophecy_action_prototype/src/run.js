// 회차 상태: 날짜·시간·금화·재료·장비·증강·체력. 저장/불러오기. 전투 밖의 모든 규칙.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Run = (function () {
  const C = () => PA.CONFIG;
  const SAVE_KEY = 'prophecy_action_save_v1';   // 키는 유지(호환), 내용의 version으로 구분
  const RECORDS_KEY = 'prophecy_action_records_v1';
  const VERSION = 4;

  function newRun(seed, startWeapon, mode, balance) {
    const cfg = C(); const B = (balance && PA.BALANCE_SETS && PA.BALANCE_SETS[balance]) ? PA.BALANCE_SETS[balance] : null;
    const run = {
      balance: B ? balance : 'current', bossHpSet: B ? B.bossHpSet : 'base', dayHpSet: B && B.dayHp ? B.dayHp : 'none', // 밸런스 세트(기본 현재값)
      mode: mode && PA.RUN_MODES[mode] ? mode : 'trio', stage: 0, bossesDone: [], bossRecords: {}, // 회차 구조: 새 회차 기본은 3보스
      growth: PA.Growth.newGrowth(startWeapon || 'sword'),
      layout: 'classic', difficulty: B && B.difficulty ? B.difficulty : 'base',
      version: VERSION, seed: seed || (Date.now() % 100000), sortieCount: 0,
      phase: 'prep',            // prep(준비) | boss_prep(관문) | cleared(완주)
      bossRetries: 0, bossClear: null,
      day: 1, hours: cfg.HOURS_PER_DAY, // hours = 남은 시간대 칸 수(새벽=5칸 남음). 현재 시간대 = HOURS_PER_DAY - hours
      gold: cfg.START_GOLD, mats: { pelt: 0, iron: 0, spore: 0, fang: 0 },
      gear: PA.Build.emptyGear(), owned: [], augments: {}, // 레거시 필드(시험실 프리셋·이전 저장 호환). v0.8 장비는 equipment/bag
      equipment: { weapon: null, armor: null, shield: null }, bag: [], forge: 0, // v0.8 런 한정 장비·가방·공용 공격 강화 단계
      visited: {}, schedule: {}, stock: null, merchant: null, // 방문 기록·날짜별 장소·오늘의 상점 재고·방문 상인
      hp: cfg.PLAYER.hp,
      log: [],
      stats: { encounters: 0, wins: 0, losses: 0, kills: 0 },
      dmgStats: { combats: [], byKey: {} }, // 런 누적 피해 통계(정산 시 기록)
      services: {}, cards: null, missionsDone: {}, pendingSortie: null, buffs: {}, lastEvent: null, lastSupplyDay: null, eventsResolved: 0,
      ended: false,
    };
    if (PA.Sortie) PA.Sortie.cardsFor(run); // 1일차 장소·목적 확정
    refreshStock(run);
    return run;
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
    if (r.version === 3) { // v3(v0.7) → v4(v0.8): 옛 장신구·방어구는 판매가로 환산, 대장간 강화는 공용 공격 강화 단계로. 변환 내용은 기록·표시된다(조용히 바꾸지 않음)
      const notes = []; r.equipment = { weapon: null, armor: null, shield: null }; r.bag = []; r.forge = Math.min(3, (r.gear && r.gear.upgrade) || 0); r.visited = {}; r.schedule = {}; r.stock = null; r.merchant = null; r.dmgStats = { combats: [], byKey: {} };
      const legacyItems = (r.owned || []).filter(id => id !== 'pierce_sword'); let refund = 0; for (const id of legacyItems) refund += 30; if (refund) { r.gold += refund; notes.push(`옛 장비 ${legacyItems.length}개 → 금화 +${refund}`); }
      if (r.gear) { r.gear.armor = null; r.gear.acc = null; }
      if (r.forge) notes.push(`대장간 강화 +${r.forge} → 공용 공격 강화 ${r.forge}단계`);
      if (r.growth && r.growth.pendingDeepPick) { r.growth.pendingDeepPick = null; notes.push('보류 중이던 더 깊이 3택은 사라짐(v0.8은 표시형 심층 보상)'); }
      r.cards = null; r.hours = Math.min(r.hours, C().HOURS_PER_DAY); r.version = 4; r.migratedFrom = 3; r.migrationNotes = notes;
      r.log = r.log || []; r.log.unshift(`${r.day}일차 · v0.8 규칙으로 변환: ${notes.join(', ') || '변경 없음'}`);
    }
    if (!r.equipment) r.equipment = { weapon: null, armor: null, shield: null }; if (!r.bag) r.bag = []; if (r.forge == null) r.forge = 0; if (!r.visited) r.visited = {}; if (!r.schedule) r.schedule = {}; if (r.stock === undefined) r.stock = null; if (r.merchant === undefined) r.merchant = null; if (!r.dmgStats) r.dmgStats = { combats: [], byKey: {} }; if (!r.dayHpSet) r.dayHpSet = 'none';
    if (!r.layout || !PA.LAYOUTS[r.layout]) r.layout = 'classic';                       // 이전 저장: 기존 배치 유지
    if (!r.difficulty || !PA.DIFFICULTY.candidates[r.difficulty]) r.difficulty = 'base';
    if (!r.services) r.services = {}; if (!r.missionsDone) r.missionsDone = {}; if (r.cards === undefined) r.cards = null; if (r.pendingSortie === undefined) r.pendingSortie = null; if (!r.buffs) r.buffs = {};
    if (!r.balance || !PA.BALANCE_SETS[r.balance]) r.balance = 'current'; if (!r.bossHpSet) r.bossHpSet = 'base';
    if (!r.mode || !PA.RUN_MODES[r.mode]) r.mode = 'single'; if (r.stage == null) r.stage = 0; if (!r.bossesDone) r.bossesDone = r.bossClear ? ['boss'] : []; if (!r.bossRecords) r.bossRecords = r.bossClear ? { boss: r.bossClear } : {}; // 이전 저장: 단일 보스 규칙 유지 // v0.7 필드: 이전 저장은 기존 규칙 유지, 카드는 오늘부터 생성
    return r;
  }

  function build(run) { return PA.Build.derive(run); }
  // ---------- 회차 구조(v0.7): single(7일 단일 보스, 기존) | trio(보스 3마리 관문) ----------
  function modeDef(run) { return PA.RUN_MODES[(run && run.mode) || 'single'] || PA.RUN_MODES.single; }
  function nextBoss(run) { return modeDef(run).bosses[run.stage || 0] || null; }
  function nextBossCfg(run) { const nb = nextBoss(run); if (nb) return PA.BOSS_DEFS[nb.id]; const done = run.bossesDone && run.bossesDone[run.bossesDone.length - 1]; return PA.BOSS_DEFS[done] || PA.BOSS; } // 완주 후에는 마지막 보스
  function bossHp(run, bossId) { const nb = modeDef(run).bosses.find(b => b.id === bossId); const H = (PA.BOSS_HP_SETS[(run && run.bossHpSet) || PA.BOSS_HP_SET] || PA.BOSS_HP)[bossId]; return nb && H && H[nb.hpKey] ? H[nb.hpKey] : PA.BOSS_DEFS[bossId].hp; }
  function stageCount(run) { return modeDef(run).bosses.length; }
  function bossDaysLeft(run) { const nb = nextBoss(run); return nb ? nb.day - run.day : 0; }
  function isBossDay(run) { const nb = nextBoss(run); return !!nb && run.day >= nb.day; }
  function addLog(run, msg) { run.log.unshift(`${run.day}일차 · ${msg}`); if (run.log.length > 8) run.log.length = 8; }

  // ---------- 시간대 ----------
  function slotIndex(run) { return Math.max(0, Math.min(PA.TIME_SLOTS.length - 1, C().HOURS_PER_DAY - run.hours)); }
  function slotName(run) { return run.hours <= 0 ? '저녁 끝' : PA.TIME_SLOTS[slotIndex(run)]; }
  function nextSlotName(run, cost) { const i = slotIndex(run) + (cost || 1); return i >= PA.TIME_SLOTS.length ? '하루 끝' : PA.TIME_SLOTS[i]; }
  // ---------- 지역/출격 ----------
  function region(id) { return PA.REGIONS.find(r => r.id === id); }
  function placeCost(regionId) { return PA.SCHEDULE.cost[regionId] || region(regionId).cost; }
  // 오늘의 장소 2곳. 6일차 첫 칸은 이전 방문 지역 중 시드로 1곳(재접속으로 바뀌지 않게 run.schedule에 저장)
  function placesFor(run, day) {
    day = day || run.day; if (run.schedule[day]) return run.schedule[day];
    const base = (PA.SCHEDULE.places[day] || []).slice();
    if (base.includes(null)) { const visited = Object.keys(run.visited || {}).filter(id => id !== 'deep' && !base.includes(id)); const pool = visited.length ? visited : ['forest']; const rng = PA.rng.create((run.seed * 53 + day * 977) >>> 0); base[base.indexOf(null)] = pool[rng.int(0, pool.length - 1)]; }
    run.schedule[day] = base; return base;
  }
  function canSortie(run, regionId) { return run.phase === 'prep' && !isBossDay(run) && placesFor(run).includes(regionId) && run.hours >= placeCost(regionId); }
  function slotVariant(regionId, slot) { const V = PA.SLOT_VARIANTS[regionId]; return V && V[slot] ? Object.assign({ slot }, V[slot]) : null; }
  function startSortie(run, regionId) {
    if (!canSortie(run, regionId)) throw new Error(run.hours < placeCost(regionId) ? '시간 부족' : '오늘 갈 수 없는 장소');
    const slot = slotIndex(run), variant = slotVariant(regionId, slot); // 출발 시점의 시간대로 편성·사건·보상 확정
    run.hours -= placeCost(regionId); run.sortieCount++; run.visited[regionId] = (run.visited[regionId] || 0) + 1;
    return { regionId, deep: false, loot: { gold: 0, mats: {}, chestGold: 0 }, encounters: 0, seed: run.seed * 131 + run.sortieCount * 17 + run.day, day: run.day, slot, variant };
  }
  function layoutRegion(regionId, run) { const L = run && run.layout && PA.LAYOUTS[run.layout]; const lr = L && L.regions[regionId]; return lr || null; }
  function regionEnemies(regionId, run) { const w = dayWaves(regionId, run ? run.day : 1); const set = []; for (const g of w.flat()) if (!set.includes(g.type)) set.push(g.type); return set; }
  function regionArena(regionId, run) { const lr = layoutRegion(regionId, run); return lr && lr.arena ? lr.arena : 'forest'; }
  // 날짜별 편성: 그 날짜 이하에서 가장 가까운 정의를 쓴다
  function dayWaves(regionId, day) { const T = PA.DAY_WAVES[regionId]; if (!T) return region(regionId).waves; let best = null; for (const k of Object.keys(T).map(Number).sort((a, b) => a - b)) if (k <= (day || 1)) best = k; if (best == null) best = Math.min(...Object.keys(T).map(Number)); return T[best]; }
  function encounterWaves(regionId, deep, run, sortie) {
    let waves = dayWaves(regionId, run ? run.day : 1).map(w => w.map(g => Object.assign({}, g)));
    const v = sortie && sortie.variant;
    if (v && v.dropLastWave && waves.length > 1) waves = waves.slice(0, -1);
    if (v && v.extra) waves[waves.length - 1] = waves[waves.length - 1].concat(v.extra.map(g => Object.assign({}, g)));
    if (v && v.addElite) { const last = waves[waves.length - 1], e = last.find(g => g.type === 'wolf_alpha'); if (e) e.n += 1; else last.push({ type: 'wolf_alpha', n: 1 }); }
    if (!deep) return waves;
    waves = waves.map(w => w.map(g => ({ type: g.type, n: g.n + 1 }))); // 더 깊이: 웨이브마다 +1, 마지막에 정예 추가(없다면)
    const last = waves[waves.length - 1]; if (!last.some(g => g.type === 'wolf_alpha')) last.push({ type: 'wolf_alpha', n: 1 });
    return waves;
  }
  function encounterObjective(regionId, deep, run) { return deep ? 'elite' : region(regionId).objective; } // 일반·정예·더 깊이 모두 전멸 종료. 'elite'는 HUD 정보
  // 체력 배율: 지역 후보 × 날짜 배율(체력만) × 정예 날짜 보정. 플레이어 공격력과 무관
  function hpMultFor(run, regionId, deep) {
    const c = PA.DIFFICULTY.candidates[(run && run.difficulty) || 'base'] || PA.DIFFICULTY.candidates.base; const day = (run && run.day) || 1;
    const dm = (PA.DAY_HP_SETS[(run && run.dayHpSet) || 'none'] || PA.DAY_HP_SETS.none)[Math.min(6, day)] || 1;
    const v = (c.hp[regionId] || 1) * (deep ? (c.deepMult || 1) : 1) * dm; const em = day >= PA.ELITE_DAY_MULT.from ? PA.ELITE_DAY_MULT.mult : 1;
    return { normal: Math.round(v * 100) / 100, elite: Math.round(v * em * 100) / 100, boss: 1 };
  }
  function layoutText(run) { const parts = []; if (run.balance && run.balance !== 'current' && PA.BALANCE_SETS[run.balance]) parts.push('밸런스: ' + PA.BALANCE_SETS[run.balance].name); if (run.layout && run.layout !== 'classic') parts.push('배치: ' + PA.LAYOUTS[run.layout].name); if (run.difficulty && run.difficulty !== 'base') parts.push('난이도: ' + PA.DIFFICULTY.candidates[run.difficulty].name); return parts.join(' · '); }
  function canDeepExplore(run, sortie) { return run.hours >= C().DEEP_EXPLORE_HOURS && !(sortie && sortie.mission) && !(sortie && sortie.deepDone); } // 출격당 심층 1회, 임무 출격 제외
  // 더 깊이 미리보기(들어가기 전 표시): 추가 시간, 적 변화, 확정 보상 종류, 걸린 전리품. 보상 종류는 출격 시드로 확정(재접속 동일)
  const DEEP_KINDS = ['gold_big', 'equipment', 'voucher', 'steer'];
  function deepPreview(run, sortie) {
    const rng = PA.rng.create((sortie.seed * 3 + 11) >>> 0); let kind = DEEP_KINDS[rng.int(0, DEEP_KINDS.length - 1)];
    const pool = Object.keys(PA.EQUIPMENT).filter(id => !ownsEquip(run, id) && !(sortie.loot.items || []).includes(id));
    if (kind === 'equipment' && !pool.length) kind = 'gold_big';
    if (kind === 'steer' && run.growth.steer) kind = 'gold_big';
    const r = region(sortie.regionId), goldMult = C().DEEP_REWARD_MULT;
    const reward = kind === 'gold_big' ? { kind, text: `금화 큰 묶음 (+${Math.round(r.reward.gold[1] * goldMult)} 추가)`, gold: Math.round(r.reward.gold[1] * goldMult) }
      : kind === 'equipment' ? { kind, text: `장비 1개: ${PA.EQUIPMENT[pool[rng.int(0, pool.length - 1)]].name}`, item: null }
      : kind === 'voucher' ? { kind, text: '개조 교체권 1장', service: 'mod_swap' }
      : { kind, text: '다음 레벨업 예약: 자동기술 개조', steer: 'weapon_mod' };
    if (kind === 'equipment') { reward.item = pool[PA.rng.create((sortie.seed * 3 + 11) >>> 0).int(0, DEEP_KINDS.length - 1) % pool.length]; reward.text = `장비 1개: ${PA.EQUIPMENT[reward.item].name}`; }
    return { extraTime: C().DEEP_EXPLORE_HOURS, nextSlot: nextSlotName(run, C().DEEP_EXPLORE_HOURS), enemyChange: '웨이브마다 적 +1, 마지막에 정예(가시갈기)', hpMult: hpMultFor(run, sortie.regionId, true), reward, lootAtRisk: { gold: sortie.loot.gold, items: (sortie.loot.items || []).slice(), services: (sortie.loot.services || []).slice() } };
  }
  function deepExplore(run, sortie) { if (!canDeepExplore(run, sortie)) throw new Error('더 깊이 불가'); run.hours -= C().DEEP_EXPLORE_HOURS; sortie.deep = true; sortie.deepDone = true; sortie.deepReward = deepPreview(run, sortie).reward; }
  // 더 깊이 승리: 표시된 보상을 미정산 전리품에 얹는다(귀환 시 정산). 승리 뒤에는 귀환만 가능
  function applyDeepReward(run, sortie) {
    const rw = sortie.deepReward; if (!rw || sortie.deepRewarded) return null; sortie.deepRewarded = true;
    if (rw.kind === 'gold_big') sortie.loot.gold += rw.gold;
    else if (rw.kind === 'equipment') { sortie.loot.items = sortie.loot.items || []; sortie.loot.items.push(rw.item); }
    else if (rw.kind === 'voucher') { sortie.loot.services = sortie.loot.services || []; sortie.loot.services.push(rw.service); }
    else if (rw.kind === 'steer') sortie.loot.steer = rw.steer;
    return rw;
  }

  // 조우 승리 보상 계산(실제 난수는 전투의 rng 사용 → 재현 가능)
  function rollReward(run, sortie, rng, combatStats) {
    const r = region(sortie.regionId), mult = sortie.deep ? C().DEEP_REWARD_MULT : 1;
    const gold = Math.round(rng.int(r.reward.gold[0], r.reward.gold[1]) * mult * (sortie.variant && sortie.variant.goldMult ? sortie.variant.goldMult : 1));
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
  // 귀환 정산(정확히 1회): 금화·재료·장비(가방)·이용권·성장 예약이 여기서 확정된다. 원정대의 갑옷 회복도 정산당 1회
  function returnToBase(run, sortie) {
    if (sortie.settled) return; sortie.settled = true;
    run.gold += sortie.loot.gold;
    for (const k in sortie.loot.mats) run.mats[k] = (run.mats[k] || 0) + sortie.loot.mats[k];
    const extras = [];
    for (const id of sortie.loot.items || []) { if (ownsEquip(run, id)) { run.gold += sellPrice(id); extras.push(`${PA.EQUIPMENT[id].name}(중복→금화 +${sellPrice(id)})`); } else { run.bag.push(id); extras.push(PA.EQUIPMENT[id].name); } }
    for (const sv of sortie.loot.services || []) { run.services[sv] = (run.services[sv] || 0) + 1; extras.push(PA.SERVICES[sv].name); }
    if (sortie.loot.steer) { const g = PA.Growth.ensure(run); if (g.steer) { run.gold += 60; extras.push('예약 있음 → 금화 +60'); } else { g.steer = { kind: sortie.loot.steer, regionId: sortie.regionId, day: run.day, fallbackGold: 60, from: 'deep' }; extras.push('다음 레벨업 예약(개조)'); } }
    const heal = onVictoryHeal(run); if (heal > 0) extras.push(`체력 +${heal}(원정대의 갑옷)`);
    const matText = Object.keys(sortie.loot.mats).map(k => `${PA.MATERIALS[k].name} ${sortie.loot.mats[k]}`).join(', ');
    addLog(run, `${region(sortie.regionId).name} 귀환: 금화 +${sortie.loot.gold}${matText ? ', ' + matText : ''}${extras.length ? ', ' + extras.join(', ') : ''}`);
  }
  // 일반 출격 패배: 미정산 전리품 상실(호출자가 sortie를 버림), 남은 하루 상실, 구조되어 다음 날 정상 체력으로 시작. 정산한 재산·성장은 보존
  function defeat(run, sortie) {
    addLog(run, `${region(sortie.regionId).name}에서 패배: 미정산 전리품 상실, 남은 하루 상실`);
    run.hours = 0; run.hp = build(run).hpMax; run.lastDefeatDay = run.day;
    if (run.phase === 'prep') endDay(run); // 구조: 하루 종료 → 다음 날(관문 날이면 관문)
  }

  // ---------- 거점 행동 ----------
  function hasService(run, id) { return !!(run.services && run.services[id] > 0); }
  function useService(run, id) { if (!hasService(run, id)) throw new Error('서비스 없음'); run.services[id]--; addLog(run, `${PA.SERVICES[id].name} 사용`); }
  function canRest(run) { return run.phase === 'prep' && (run.hours >= C().REST_HOURS || hasService(run, 'free_rest')); } // 체력이 가득해도 다음 시간대로 넘길 수 있다(별도 대기 버튼 없음)
  function rest(run) { if (!canRest(run)) throw new Error('휴식 불가'); if (hasService(run, 'free_rest')) useService(run, 'free_rest'); else run.hours -= C().REST_HOURS; run.hp = build(run).hpMax; addLog(run, `휴식: 체력 회복 → ${slotName(run)}`); }
  function endDay(run) {
    if (run.phase !== 'prep') throw new Error('보스 준비 중에는 하루를 넘길 수 없음');
    run.day++; run.hours = C().HOURS_PER_DAY; run.hp = build(run).hpMax; run.buffs = run.buffs || {};
    addLog(run, '새로운 아침');
    if (isBossDay(run)) { run.phase = 'boss_prep'; addLog(run, '보스 관문: 준비 뒤 입장'); }
    placesFor(run); if (PA.Sortie) PA.Sortie.cardsFor(run); refreshStock(run);
  }
  // 하루가 끝나기 전 다음 날 미리보기: 장소 2곳과 핵심 위험
  function previewNextDay(run) { const d = run.day + 1; const nb = nextBoss(run); if (nb && d >= nb.day && !run.bossesDone.includes(nb.id)) return { day: d, boss: nb.id }; return { day: d, places: placesFor(run, d).map(id => ({ id, name: region(id).name, elite: dayWaves(id, d).flat().some(g => PA.ENEMIES[g.type].elite), enemies: dayWaves(id, d).flat().map(g => g.type).filter((t, i, a) => a.indexOf(t) === i).slice(0, 3) })) }; }
  // ---------- 보스전 ----------
  function bossSeed(run) { return run.seed * 997 + 7 + (run.stage || 0) * 31; } // 같은 회차·같은 단계 재도전 = 같은 시드·지형
  function canStartBoss(run) { return run.phase === 'boss_prep' || run.phase === 'cleared'; }
  function startBoss(run) {
    if (!canStartBoss(run)) throw new Error('보스 준비 상태가 아님');
    run.hp = build(run).hpMax; // 입장: 체력 완전 회복(회피·감속장·방벽은 전투 생성 시 초기화)
    run.bossEntry = JSON.parse(JSON.stringify({ growth: run.growth, hp: run.hp, stage: run.stage, gold: run.gold })); // 재도전 복구 기준(소환 경험치 누적 악용 방지)
    const nb = nextBoss(run);
    return { regionId: 'boss', bossId: nb ? nb.id : 'boss', stage: run.stage || 0, seed: bossSeed(run), loot: { gold: 0, mats: {} }, encounters: 0 };
  }
  function bossDefeat(run) {
    run.bossRetries = (run.bossRetries || 0) + 1;
    if (run.bossEntry) { run.growth = JSON.parse(JSON.stringify(run.bossEntry.growth)); if (run.bossEntry.gold != null) run.gold = run.bossEntry.gold; } // 입장 시 준비 상태로 복구(레벨·경험치·선택·금화: 전투 중 건너뛰기 금화 반복 악용 방지)
    run.hp = build(run).hpMax; addLog(run, `보스전 패배 (재도전 ${run.bossRetries}회, 성장은 입장 시점으로 복구)`);
  }
  function bossVictory(run, stats) {
    const b = build(run), nb = nextBoss(run), bossId = nb ? nb.id : 'boss', cfg = PA.BOSS_DEFS[bossId];
    const rec = { bossId, stage: run.stage || 0, time: Math.round(stats.elapsed * 10) / 10, retries: run.bossRetries || 0, weapon: b.weapon.name, upgrade: run.gear.upgrade, acc: run.gear.acc, armor: run.gear.armor, augments: Object.assign({}, run.augments), level: run.growth.level, specialUses: stats.specialUses || 0, bossDamage: Math.round(stats.bossDamage || 0), day: run.day, seed: run.seed, mode: run.mode, at: Date.now() };
    if (!run.bossRecords[bossId]) run.bossRecords[bossId] = rec; // 보스별 처치 기록은 1회(재도전·재정산으로 갱신하지 않음)
    if (bossId === 'boss' && !run.bossClear) run.bossClear = rec; // 단일 보스 회차 호환 필드
    run.lastBossClear = rec; if (!run.bossesDone.includes(bossId)) run.bossesDone.push(bossId);
    addLog(run, `${cfg.name} 처치 (${rec.time}초)`);
    const last = (run.stage || 0) >= stageCount(run) - 1;
    if (last) { run.phase = 'cleared'; run.ended = true; run.stage = stageCount(run); } // 마지막 보스: 회차 종료, 다음 보스 없음, 추가 성장 없음
    else { // 다음 단계 해금: 그날의 5시간 시작, 희귀 보상 3택은 1회 보류 등록(저장됨)
      if (nb.rare) run.growth.pendingBossPick = { bossId, stage: run.stage || 0, key: `${run.seed}:${run.stage}` };
      run.stage = (run.stage || 0) + 1; run.phase = 'prep'; run.hours = C().HOURS_PER_DAY; run.hp = b.hpMax; run.bossRetries = 0; run.bossEntry = null;
      addLog(run, `${run.stage + 1}단계 해금: 오늘 ${C().HOURS_PER_DAY}시간 시작`);
      if (PA.Sortie) PA.Sortie.cardsFor(run);
    }
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

  // ---------- 상점(하루 시드 재고)·장비·대장간 ----------
  const SH = () => PA.SHOP;
  function ownsEquip(run, id) { return run.bag.includes(id) || Object.values(run.equipment).includes(id); }
  function stockSeed(run, day) { return (run.seed * 17 + (day || run.day) * 401 + 9) >>> 0; }
  // 오늘의 재고: 장비 2(미보유) + 자동기술 또는 E 1. 다시 열거나 불러와도 같다(저장). 날짜만으로 가격을 올리지 않는다
  function refreshStock(run) {
    const rng = PA.rng.create(stockSeed(run)), g = PA.Growth.ensure(run);
    const pool = Object.keys(PA.EQUIPMENT).filter(id => !ownsEquip(run, id)); const eq = []; while (eq.length < SH().stock.equipment && pool.length) eq.push(pool.splice(rng.int(0, pool.length - 1), 1)[0]);
    let skill = null; const wpool = Object.keys(PA.WEAPONS).filter(id => PA.WEAPONS[id].impl && !g.weapons.some(w => w.id === id));
    if (g.weapons.length < PA.GROWTH.SLOTS.weapons && wpool.length) skill = { kind: 'weapon', id: wpool[rng.int(0, wpool.length - 1)], price: SH().newSkill };
    else if (!g.skills.e) { const es = PA.E_SKILLS.filter(id => PA.SKILLS[id].impl); skill = { kind: 'e', id: es[rng.int(0, es.length - 1)], price: SH().newE }; }
    run.stock = { day: run.day, equipment: eq, skill, sold: [] };
    // 방문 상인: 예정된 날 점심부터 그날 끝까지. 특별 재고 = 장비 1(할인) + 무료 휴식권
    if (PA.MERCHANT_VISITS.days.includes(run.day)) { const p2 = Object.keys(PA.EQUIPMENT).filter(id => !ownsEquip(run, id) && !eq.includes(id)); run.merchant = { day: run.day, fromSlot: PA.MERCHANT_VISITS.slot, equipment: p2.length ? p2[rng.int(0, p2.length - 1)] : null, service: 'free_rest', servicePrice: 40, sold: [] }; }
    else run.merchant = null;
    return run.stock;
  }
  function stock(run) { if (!run.stock || run.stock.day !== run.day) refreshStock(run); return run.stock; }
  function merchantOpen(run) { return !!(run.merchant && run.merchant.day === run.day && slotIndex(run) >= run.merchant.fromSlot); }
  function equipPrice(id) { const d = PA.EQUIPMENT[id]; return SH().price[d.slot]; }
  function sellPrice(id) { const d = PA.EQUIPMENT[id]; return SH().sellPrice[d.slot]; }
  function canBuyEquipment(run, id, from) { const st = from === 'merchant' ? run.merchant : stock(run); if (!st || !PA.EQUIPMENT[id]) return false; const listed = from === 'merchant' ? (merchantOpen(run) && st.equipment === id) : st.equipment.includes(id); return listed && !st.sold.includes(id) && !ownsEquip(run, id) && run.gold >= equipPriceFor(run, id, from); }
  function equipPriceFor(run, id, from) { let p = equipPrice(id); if (from === 'merchant') p = Math.round(p * (1 - SH().merchantDiscount)); if (hasService(run, 'shop_discount')) p = Math.round(p * (1 - PA.SERVICES.shop_discount.rate)); return p; }
  // 구매: 즉시 장착(equip=true) 또는 보관. 같은 장비 중복 구매 불가
  function buyEquipment(run, id, equip, from) {
    if (!canBuyEquipment(run, id, from)) throw new Error('구매 불가');
    run.gold -= equipPriceFor(run, id, from); if (hasService(run, 'shop_discount')) useService(run, 'shop_discount');
    (from === 'merchant' ? run.merchant : stock(run)).sold.push(id);
    run.bag.push(id); if (equip) equipItem(run, id); addLog(run, `${PA.EQUIPMENT[id].name} 구매${equip ? '·장착' : '·보관'}`);
  }
  function equipItem(run, id) { const d = PA.EQUIPMENT[id]; if (!run.bag.includes(id)) throw new Error('가방에 없음'); const cur = run.equipment[d.slot]; run.bag = run.bag.filter(x => x !== id); if (cur) run.bag.push(cur); run.equipment[d.slot] = id; clampHp(run); }
  function unequipItem(run, slot) { const cur = run.equipment[slot]; if (!cur) return; run.equipment[slot] = null; run.bag.push(cur); clampHp(run); }
  function clampHp(run) { run.hp = Math.min(run.hp, build(run).hpMax); } // 최대 체력이 줄면 현재 체력도 줄어든다. 늘어도 회복하지 않는다(탈착 회복 악용 없음)
  function sellEquipment(run, id) { if (!ownsEquip(run, id)) throw new Error('미보유'); for (const s of PA.EQUIP_SLOTS) if (run.equipment[s] === id) { run.equipment[s] = null; clampHp(run); } run.bag = run.bag.filter(x => x !== id); run.gold += sellPrice(id); addLog(run, `${PA.EQUIPMENT[id].name} 판매 +${sellPrice(id)}`); }
  // 빈 슬롯 획득: 새 자동기술 / 새 E (Lv1, 개조·변형 없음)
  function canBuySkill(run) { const st = stock(run), g = PA.Growth.ensure(run); if (!st.skill || st.sold.includes('skill')) return false; if (st.skill.kind === 'weapon') return g.weapons.length < PA.GROWTH.SLOTS.weapons && !g.weapons.some(w => w.id === st.skill.id) && run.gold >= st.skill.price; return !g.skills.e && run.gold >= st.skill.price; }
  function buySkill(run) { if (!canBuySkill(run)) throw new Error('구매 불가'); const st = stock(run), g = PA.Growth.ensure(run); run.gold -= st.skill.price; st.sold.push('skill'); if (st.skill.kind === 'weapon') g.weapons.push({ id: st.skill.id, level: 1, mods: [] }); else g.skills.e = { id: st.skill.id, level: 1, variant: null }; addLog(run, `${st.skill.kind === 'weapon' ? PA.WEAPONS[st.skill.id].name : PA.SKILLS[st.skill.id].name} 획득 (-${st.skill.price})`); }
  // 보유 자동기술/E 교체 견적: 120 + (레벨-1)×40 + 개조·변형 수×80. 레벨과 개조 수를 보존하는 대가
  function swapQuote(run, slot, index) {
    const g = PA.Growth.ensure(run); const cur = slot === 'e' ? g.skills.e : g.weapons[index]; if (!cur) return null;
    const mods = slot === 'e' ? (cur.variant ? 1 : 0) : cur.mods.length; const price = SH().swap.base + (cur.level - 1) * SH().swap.perLevel + mods * SH().swap.perMod;
    const options = slot === 'e' ? PA.E_SKILLS.filter(id => PA.SKILLS[id].impl && id !== cur.id) : Object.keys(PA.WEAPONS).filter(id => PA.WEAPONS[id].impl && !g.weapons.some(w => w.id === id));
    return { slot, index, current: cur, level: cur.level, modCount: mods, price, options, affordable: run.gold >= price };
  }
  // 교체 확정(마지막 단계에서만 금화 차감·실제 교체). 새 개조/변형은 새 기술 목록에서 modCount만큼 고른다. 취소하면 아무것도 바뀌지 않는다
  function applySwap(run, slot, index, newId, newMods) {
    const q = swapQuote(run, slot, index); if (!q || !q.options.includes(newId)) throw new Error('교체 불가'); if (run.gold < q.price) throw new Error('금화 부족');
    newMods = (newMods || []).slice(0, q.modCount); const g = PA.Growth.ensure(run);
    if (slot === 'e') { const d = PA.SKILLS[newId]; const v = newMods[0] || null; if (v && !(d.variants && d.variants[v] && d.variants[v].impl)) throw new Error('변형 불가'); g.skills.e = { id: newId, level: q.level, variant: v }; }
    else { const d = PA.WEAPONS[newId]; for (const m of newMods) if (!(d.mods[m] && d.mods[m].impl)) throw new Error('개조 불가'); if (new Set(newMods).size !== newMods.length) throw new Error('개조 중복'); g.weapons[index] = { id: newId, level: q.level, mods: newMods }; }
    run.gold -= q.price; g.picks.swap = (g.picks.swap || 0) + 1; addLog(run, `${slot === 'e' ? 'E' : '자동기술'} 교체 → ${slot === 'e' ? PA.SKILLS[newId].name : PA.WEAPONS[newId].name} (-${q.price})`);
    return q.price;
  }
  // 교체로 적용 대상이 사라지는 공용 증강 경고(확정 전 표시용)
  function swapWarnings(run, slot, index, newId) {
    if (slot === 'e') return []; const g = PA.Growth.ensure(run); const after = g.weapons.map((w, i) => i === index ? { id: newId, mods: [] } : w); const out = [];
    for (const id in g.commons) { const d = PA.COMMONS[id]; if (g.commons[id] > 0 && d.applies && !after.some(w => d.applies(PA.WEAPONS[w.id]))) out.push(d.name); }
    return out;
  }
  // 대장간: 공용 공격 강화(보스 관문 통과로 단계 개방), 같은 기술의 개조 1개 변경(140 또는 이용권), E 변형 변경(140)
  function forgeNext(run) { const lv = run.forge || 0; const F = SH().forge[lv]; if (!F) return null; return Object.assign({}, F, { open: (run.bossesDone || []).length >= F.afterBoss, affordable: run.gold >= F.cost }); }
  function forgeUpgrade(run) { const F = forgeNext(run); if (!F || !F.open || !F.affordable) throw new Error('강화 불가'); run.gold -= F.cost; run.forge = F.lv; addLog(run, `공용 공격 강화 ${F.lv}단계 (-${F.cost})`); }
  function modChangeCost(run) { return hasService(run, 'mod_swap') ? { voucher: true, gold: 0 } : { voucher: false, gold: SH().modChange }; }
  function variantChangeCost(run) { return hasService(run, 'mod_swap') ? { voucher: true, gold: 0 } : { voucher: false, gold: SH().variantChange }; }
  function ownedBySlot(run, slot) { return []; } function unequip(run, slot) { unequipItem(run, slot); }
  function item(id) { return null; }
  function sell(run, matId, n) { n = n || 1; if ((run.mats[matId] || 0) < n) throw new Error('재료 부족'); run.mats[matId] -= n; run.gold += PA.MATERIALS[matId].sell * n; }
  function targetInfo(run) { return null; }
  // 승리 정산 시 장비 효과(원정대의 갑옷): 정산당 1회
  function onVictoryHeal(run) { const b = build(run); if (b.equip && b.equip.winHeal) { const before = run.hp; run.hp = Math.min(b.hpMax, run.hp + b.equip.winHeal); return run.hp - before; } return 0; }

  function regionBonusXp(regionId, deep) { const v = (PA.GROWTH.REGION_BONUS_XP[regionId] || 0) * (PA.GROWTH.BONUS_XP_MULT || 1); return Math.round((deep ? v * 1.5 : v) * 100) / 100; }

  // ---------- 저장 ----------
  function serialize(run) { return JSON.stringify(run); }
  function deserialize(s) { const r = JSON.parse(s); if (![1, 2, 3, 4].includes(r.version)) throw new Error('저장 버전 불일치'); return migrate(r); }
  function save(run, storage) { storage = storage || globalThis.localStorage; try { storage.setItem(SAVE_KEY, serialize(run)); return true; } catch (e) { return false; } }
  function load(storage) { storage = storage || globalThis.localStorage; try { const s = storage.getItem(SAVE_KEY); return s ? deserialize(s) : null; } catch (e) { return null; } }
  function clearSave(storage) { storage = storage || globalThis.localStorage; try { storage.removeItem(SAVE_KEY); } catch (e) {} }

  return { SAVE_KEY, RECORDS_KEY, VERSION, hasService, useService, modeDef, nextBoss, nextBossCfg, bossHp, stageCount, regionBonusXp, layoutRegion, regionEnemies, regionArena, hpMultFor, layoutText, migrate, bossSeed, canStartBoss, startBoss, bossDefeat, bossVictory, ownedBySlot, unequip, loadRecords, saveRecord, newRun, build, bossDaysLeft, isBossDay, region, canSortie, startSortie, encounterWaves, encounterObjective, canDeepExplore, deepExplore, deepPreview, applyDeepReward, rollReward, applyEncounterResult, returnToBase, defeat, canRest, rest, endDay, previewNextDay, item, sell, targetInfo, serialize, deserialize, save, load, clearSave, addLog,
    slotIndex, slotName, nextSlotName, placeCost, placesFor, slotVariant, dayWaves, refreshStock, stock, merchantOpen, ownsEquip, equipPrice, sellPrice, equipPriceFor, canBuyEquipment, buyEquipment, equipItem, unequipItem, sellEquipment, canBuySkill, buySkill, swapQuote, applySwap, swapWarnings, forgeNext, forgeUpgrade, modChangeCost, variantChangeCost, onVictoryHeal, clampHp };
})();
