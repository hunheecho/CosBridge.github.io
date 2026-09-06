// 회차 시뮬레이션(헤드리스). 고정 빌드 전투 시뮬레이션(lab_sim)과 분리: 봇이 6일 동안 출격하고 레벨업 카드를 고른다(성장 적용).
// 사용: node tools/run_sim.js [--seeds 1,2,3] [--curve v05|v06|both] [--layout classic|trial] [--difficulty base|candA..] [--bot balanced] [--start sword|spear|blades] [--md docs/sim/run_sim.md]
// 전략 5종: easy(쉬운 지역 반복) gradual(점차 위험 지역) risky(위험 지역 우선) cautious(체력 낮으면 휴식·더 깊이 안 함) deep(더 깊이 탐험 적극)
// 메뉴/선택 시간 가정(시뮬레이션된 전투 시간과 별도 표기): 조우 전후 화면 25초, 카드 1장 6초, 하루 종료 10초, 휴식 5초. 순수 전투 시간이 길다고 좋은 것으로 판정하지 않는다.
const fs = require('fs'), path = require('path');
const { load } = require('../test/load'); const PA = load();
const args = process.argv.slice(2); const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const seeds = opt('seeds', '1,2,3,4,5').split(',').map(Number), curveOpt = opt('curve', 'both'), stratsOpt = opt('strats', ''), xpOpt = opt('xp', ''), regionXpOpt = opt('regionxp', ''), layout = opt('layout', 'classic'), difficulty = opt('difficulty', 'base'), botId = opt('bot', 'balanced'), mdPath = opt('md', path.join(__dirname, '..', 'docs', 'sim', 'run_sim.md'));
const MENU = { encounter: 25, card: 6, dayEnd: 10, rest: 5, event: 8 };
const STRATS = {
  easy:     { name: '쉬운 지역 반복', pick: () => 'forest', restBelow: 0.3, deep: false },
  gradual:  { name: '점차 위험 지역으로', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.3, deep: false },
  risky:    { name: '위험 지역 우선', pick: () => ['deep', 'den'], restBelow: 0.3, deep: false },
  cautious: { name: '체력 낮으면 일찍 휴식', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.6, deep: false },
  deep:     { name: '더 깊이 탐험 적극', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.3, deep: true },
  mission:  { name: '위험 임무 우선', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.3, deep: false, missions: 'risky' }, // 오늘 카드 중 위험 조건 있는 임무부터, 없으면 아무 임무, 임무가 끝나면 일반 탐험
  matched:  { name: '빌드 맞춤 보상 선택', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.3, deep: false, missions: 'linked', matched: true }, // 빌드 연결 카드 우선 + 3택은 보유 무기·기술 강화 우선
};
// 빌드 맞춤 3택: 보유 무기 레벨/개조·기술 레벨·지역 태그 일치 우선, 없으면 기본 봇 선택
function matchedPick(run, off) {
  const g = run.growth, owned = new Set(g.weapons.map(w => w.id));
  const score = (c) => (c.kind === 'weapon_level' && owned.has(c.id) ? 3 : 0) + (c.kind === 'weapon_mod' && owned.has(c.id) ? 3 : 0) + (c.kind === 'skill_level' || c.kind === 'skill_variant' ? 2 : 0) + (c.regionMatch ? 1 : 0);
  const best = off.choices.slice().sort((a, b) => score(b) - score(a))[0];
  return best && score(best) > 0 ? best : PA.Bot.pickChoice(off, run.seed);
}
// 시간 계정(수정 후): 전투(시뮬레이션 초) / 카드(레벨업·지역 3택, 실제 발생 시점에 기록·전투 중 포함) / 화면(조우 전후) / 휴식·하루 종료 / 보스. 합계는 마지막에 한 번만 더한다.
// 시뮬레이션된 시간(전투·보스)과 가정한 메뉴 시간(카드·화면·휴식·하루)을 구분해 표기한다. 시간 초과(봇이 maxSec 안에 못 끝냄)는 패배와 별도로 센다.
const startWeapon = opt('start', 'sword'), runMode = opt('mode', 'trio');
// 비교 후보 파라미터(기본 = 현재값): 처치 경험치 배율, 지역 경험치 배율, 보스 체력 세트, 성장 중단일(그 날 이후 출격 없음 = '3일차까지만 성장한 빌드' 시험)
const killXp = Number(opt('killxp', '1')), bonusXp = Number(opt('bonusxp', '1')), bossHpSet = opt('bosshp', 'base'), stopDay = Number(opt('stopday', '0')), tag = opt('tag', '');
const balanceId = opt('balance', ''); if (balanceId) PA.Balance.apply(balanceId); else { PA.GROWTH.XP_KILL_MULT = killXp; PA.GROWTH.BONUS_XP_MULT = bonusXp; PA.BOSS_HP_SET = bossHpSet; }
function simulate(seed, stratId) {
  const S = STRATS[stratId], run = PA.Run.newRun(seed, startWeapon, runMode, balanceId || 'current'); run.layout = layout; if (!balanceId) run.difficulty = difficulty; let g = run.growth; // 보스 패배 복구 뒤 run.growth 객체가 바뀌므로 관문 뒤에 다시 잡는다 // 밸런스 세트가 있으면 회차 필드(보스 체력 세트·난이도)도 세트를 따른다
  const T = { combat: 0, cards: 0, screens: 0, rest: 0, dayEnd: 0, boss: 0 }; // 초 단위 버킷
  const log = { goldEarnedByDay: [], goldSpent: 0, equipBought: [], skillsBought: 0, swaps: 0, forge: 0, deepRewards: [], daysLostToDefeat: 0, steered: 0, encounters: 0, losses: 0, timeouts: 0, rests: 0, deeps: 0, cards: 0, cardsInCombat: 0, deepPicks: 0, missions: 0, missionPicks: 0, eventCount: 0, eventChoices: [], eventFights: 0, levelUpsByDay: [], weapon2: null, weapon3: null, eSkill: null, events: [], spawned: 0, executed: 0, dba: 0, killedN: 0, taken: 0, bossTaken: 0, bossPatterns: {}, stopDay };
  let clock = 0; // 실제 경과 시점(초): 카드 획득 시점 기록용
  const mark = () => { const t = Math.round(clock); if (log.weapon2 == null && g.weapons.length >= 2) log.weapon2 = t; if (log.weapon3 == null && g.weapons.length >= 3) log.weapon3 = t; if (log.eSkill == null && g.skills.e) log.eSkill = t; };
  const pick = (off) => S.matched ? matchedPick(run, off) : PA.Bot.pickChoice(off, run.seed);
  const onPick = (where) => (off, c) => { T.cards += MENU.card; clock += MENU.card; log.cards++; if (where === 'combat') log.cardsInCombat++; if (off.pool === 'deep') log.deepPicks++; if (off.pool === 'mission') log.missionPicks++; log.events.push({ t: Math.round(clock), kind: off.pool, key: c ? c.key : 'skip', where }); mark(); };
  const fight = (s) => {
    const st = PA.Flow.makeEncounter(run, s); const t0 = clock; let cardSec = 0;
    PA.Bot.runCombat(st, botId, { maxSec: 240, onLevelUp: (st2) => { clock = t0 + st2.t + cardSec; const before = T.cards; PA.Flow.resolveAll(run, { regionId: s.regionId }, pick, onPick('combat')); cardSec += T.cards - before; PA.Combat.rebuild(st2, PA.Run.build(run)); } });
    T.combat += st.t; clock = t0 + st.t + cardSec; log.encounters++;
    { const sm = PA.Combat.summary(st); const en = Object.values(sm.enemies); const sum = (k) => en.reduce((a, e) => a + (e[k] || 0), 0); log.spawned += sum('spawned'); log.executed += sum('executed'); log.dba += sum('diedBeforeAttack'); log.killedN += sum('killed'); log.taken += sm.damageTaken; }
    T.screens += MENU.encounter; clock += MENU.encounter;
    if (st.status === 'running') { st.status = 'timeout'; log.timeouts++; }
    return st;
  };
  const settleWin = (s, st) => { PA.Flow.settleVictory(run, s, st); PA.Flow.resolveAll(run, { regionId: s.regionId }, pick, onPick('screen')); mark(); };
  // 탐험 사건(출격당 최대 1회): 봇 정책으로 선택. 추가 전투/더 깊이는 같은 조우 경로. 반환: 'fight' | 'deep' | null
  const handleEvent = (s) => { if (!s.event || s.event.resolved) return null; const choice = PA.Events.botChoose(run, s, stratId); const r = PA.Events.resolve(run, s, choice); log.eventCount++; log.eventChoices.push(s.event.id + ':' + choice); T.screens += MENU.event; clock += MENU.event; if (r.next === 'offer') PA.Flow.resolveAll(run, { regionId: s.regionId }, pick, onPick('screen')); return r.next === 'fight' || r.next === 'deep' ? r.next : null; };
  const settleLoss = (s, st) => { PA.Flow.settleDefeat(run, s, st); if (st.status === 'lost') log.losses++; mark(); };
  // 보스 관문(회차 구조 공유 흐름): 승리하면 다음 단계·희귀 보상 3택(봇 선택), 패배하면 입장 스냅샷으로 재도전(최대 3회)
  log.bosses = []; log.bossSec = 0; log.bossRetries = 0; log.rarePicks = [];
  const bossGate = () => {
    while (PA.Run.canStartBoss(run) && run.phase === 'boss_prep') {
      const bs = PA.Run.startBoss(run); const st = PA.Flow.makeBossEncounter(run, bs); PA.Bot.runCombat(st, botId, { maxSec: 300 });
      if (st.status === 'running') st.status = 'timeout';
      T.boss += st.t; clock += st.t; log.bossSec += Math.round(st.t);
      const sm = PA.Combat.summary(st); log.bossTaken += sm.damageTaken; for (const k in sm.patterns) log.bossPatterns[bs.bossId + ':' + k] = (log.bossPatterns[bs.bossId + ':' + k] || 0) + sm.patterns[k];
      const row = { id: bs.bossId, stage: bs.stage, status: st.status, sec: Math.round(st.t), hp: Math.round(st.player.hp), bossHp: Math.round(st.boss.hp), bossHpMax: st.boss.hpMax, taken: Math.round(sm.damageTaken), patterns: sm.patterns, level: g.level, day: run.day, retries: run.bossRetries };
      log.bosses.push(row);
      if (st.status === 'won') { PA.Flow.settleBossVictory(run, st); const before = log.cards; PA.Flow.resolveAll(run, {}, pick, (off, c) => { onPick('screen')(off, c); if (off.pool === 'boss') log.rarePicks.push(c ? c.key : 'skip'); }); }
      else { PA.Flow.settleBossDefeat(run, st); log.bossRetries++; if (run.bossRetries >= 3) { log.failedAt = bs.id; g = run.growth; return false; } }
      g = run.growth;
    }
    g = run.growth; return true;
  };
  // 거점 경제 봇(v0.8): 예비 금화 40을 남기고 ① 빈 슬롯 새 기술 ② 공용 공격 강화(개방 시) ③ 오늘의 장비(같은 슬롯이 비어 있으면 우선). 교체는 하지 않는다(비교 기준 단순화)
  const RESERVE = 40;
  const shopBot = () => {
    if (S.noShop || stopDay && run.day > stopDay) return;
    let guard = 0;
    while (guard++ < 6) {
      const g0 = run.gold; let did = false;
      if (PA.Run.canBuySkill(run) && run.gold - PA.Run.stock(run).skill.price >= RESERVE) { PA.Run.buySkill(run); log.skillsBought++; did = true; }
      const F = PA.Run.forgeNext(run); if (F && F.open && run.gold - F.cost >= RESERVE) { PA.Run.forgeUpgrade(run); log.forge = run.forge; did = true; }
      const st = PA.Run.stock(run); const cand = st.equipment.filter(id => PA.Run.canBuyEquipment(run, id) && run.gold - PA.Run.equipPriceFor(run, id) >= RESERVE).sort((a, b) => (run.equipment[PA.EQUIPMENT[a].slot] ? 1 : 0) - (run.equipment[PA.EQUIPMENT[b].slot] ? 1 : 0));
      if (cand.length) { PA.Run.buyEquipment(run, cand[0], true); log.equipBought.push(cand[0]); did = true; }
      log.goldSpent += g0 - run.gold; if (!did) break;
    }
  };
  let dayGuard = 0;
  while (dayGuard++ < 20 && !run.ended && run.phase !== 'cleared') {
    if (run.phase === 'boss_prep') { shopBot(); if (!bossGate()) break; }
    if (run.phase === 'cleared' || run.ended) break;
    const day = run.day, dayStart = run.day, goldStart = run.gold + log.goldSpent; const lvStart = g.level; let guard = 0;
    shopBot();
    while (guard++ < 20 && run.day === dayStart && !(stopDay && day > stopDay)) { // 성장 중단일 이후는 출격 없이 하루 종료만(휴식으로 체력 회복)
      const hpMax = PA.Run.build(run).hpMax;
      if (run.hp < hpMax * S.restBelow && PA.Run.canRest(run)) { PA.Run.rest(run); log.rests++; T.rest += MENU.rest; clock += MENU.rest; continue; }
      // 임무 카드(전략에 따라): risky = 위험 조건 카드 우선, linked = 빌드 연결 카드 우선. 시작 가능한 카드가 없으면 일반 탐험
      let s = null;
      if (S.missions) { const cards = PA.Sortie.cardsFor(run).filter(c => PA.Sortie.canStart(run, c)); const pref = cards.filter(c => S.missions === 'risky' ? !!c.risk : c.linked); const c = (pref[0] || cards[0]); if (c) { s = PA.Sortie.start(run, c.id); log.missions++; } }
      if (!s) {
        const want = [].concat(S.pick(day)); let rid = want.find(id => PA.Run.canSortie(run, id));
        if (!rid) { const alt = PA.REGIONS.slice().reverse().find(r => PA.Run.canSortie(run, r.id) && want.some(w => PA.REGIONS.findIndex(x => x.id === w) >= PA.REGIONS.findIndex(x => x.id === r.id))) || PA.REGIONS.find(r => PA.Run.canSortie(run, r.id)); if (!alt) break; rid = alt.id; }
        s = PA.Run.startSortie(run, rid);
      }
      const rid = s.regionId;
      let st = fight(s);
      if (st.status === 'won') {
        settleWin(s, st);
        let lost = false;
        const evNext = handleEvent(s);
        if (evNext === 'fight') { log.eventFights++; st = fight(s); if (st.status === 'won') settleWin(s, st); else { settleLoss(s, st); lost = true; } }
        else if (evNext === 'deep') { log.deeps++; st = fight(s); if (st.status === 'won') settleWin(s, st); else { settleLoss(s, st); lost = true; } }
        if (lost) continue;
        if (!s.deep && S.deep && PA.Run.canDeepExplore(run, s) && run.hp >= PA.Run.build(run).hpMax * 0.5) {
          PA.Run.deepExplore(run, s); log.deeps++; log.deepRewards.push(s.deepReward ? s.deepReward.kind : '?'); st = fight(s);
          if (st.status === 'won') settleWin(s, st); else { settleLoss(s, st); continue; }
        }
        PA.Flow.returnHome(run, s);
      } else settleLoss(s, st);
    }
    log.levelUpsByDay.push(g.level - lvStart); log.levelAtBoss = log.levelAtBoss || []; T.dayEnd += MENU.dayEnd; clock += MENU.dayEnd;
    log.goldEarnedByDay.push(run.gold + log.goldSpent - goldStart); log.steered = (g.picks && g.picks.steered) || 0;
    if (run.day !== dayStart) { log.daysLostToDefeat++; continue; } // 패배로 이미 다음 날(구조)
    if (day < PA.Run.modeDef(run).days) PA.Run.endDay(run); else if (run.phase === 'prep' && runMode === 'single') { run.day++; run.phase = 'boss_prep'; } else break;
  }
  if (run.phase === 'boss_prep') bossGate();
  // 성장 선택 간격: 전투력 선택(레벨업·임무·심층·사건·희귀) 사이의 실제 경과 초(가정 메뉴 시간 포함). 첫 선택까지의 시간도 기록
  { const ts = log.events.filter(e => e.kind !== 'skip').map(e => e.t).sort((a, b) => a - b); const gaps = []; for (let i = 1; i < ts.length; i++) gaps.push(ts[i] - ts[i - 1]); log.pickGapAvg = gaps.length ? Math.round(gaps.reduce((a, b) => a + b, 0) / gaps.length) : 0; log.pickGapMed = gaps.length ? gaps.slice().sort((a, b) => a - b)[Math.floor(gaps.length / 2)] : 0; log.firstPickSec = ts.length ? ts[0] : 0; log.picksTotal = ts.length; }
  const P = g.picks || {}; log.picks = Object.assign({}, P); log.combatPicks = ['weapon_new', 'weapon_level', 'weapon_mod', 'common', 'skill_new', 'skill_level', 'skill_variant', 'passive'].reduce((a, k) => a + (P[k] || 0), 0); log.servicePicks = (P.service || 0); log.bossRewardPicks = (P.boss_reward || 0); log.skips = P.skip || 0; log.rarePicksN = log.rarePicks.length;
  log.dbaPct = log.spawned ? Math.round(log.dba / Math.max(1, log.killedN) * 100) : 0; log.execPerSpawn = log.spawned ? Math.round(log.executed / log.spawned * 100) / 100 : 0;
  log.level = g.level; log.gold = run.gold; log.goldPerDay = log.goldEarnedByDay.length ? Math.round(log.goldEarnedByDay.reduce((a, b) => a + b, 0) / log.goldEarnedByDay.length) : 0; log.equipN = log.equipBought.length; log.deepRewardText = log.deepRewards.join(','); log.mats = Object.assign({}, run.mats); log.hpBeforeBoss = run.hp;
  log.build = `${g.weapons.map(w => w.id + w.level + (w.mods.length ? '[' + w.mods.join('+') + ']' : '')).join(' ')} | 공통 ${Object.keys(g.commons).map(k => k + g.commons[k]).join(',') || '-'} | E ${g.skills.e ? g.skills.e.id + g.skills.e.level : '-'} | 패시브 ${Object.keys(g.passives).map(k => k + g.passives[k]).join(',') || '-'}`;
  const lastB = log.bosses[log.bosses.length - 1] || { status: 'none', sec: 0, hp: 0, bossHp: 0 };
  log.boss = log.bosses.map(b => `${b.id}:${b.status}@${b.sec}s`).join(' '); log.bossStatus = run.phase === 'cleared' ? 'won' : lastB.status; log.cleared = run.phase === 'cleared';
  // 합계는 여기서 한 번만: 버킷 합 = 시계(clock)와 같아야 한다(검증)
  const sum = Object.values(T).reduce((a, b) => a + b, 0); if (Math.abs(sum - clock) > 0.5) throw new Error(`시간 계정 불일치 ${sum} vs ${clock}`);
  log.time = Object.fromEntries(Object.keys(T).map(k => [k, Math.round(T[k])])); log.simulatedSec = Math.round(T.combat + T.boss); log.assumedSec = Math.round(T.cards + T.screens + T.rest + T.dayEnd);
  log.totalMin = Math.round(sum / 60 * 10) / 10; log.combatMin = Math.round(T.combat / 60 * 10) / 10; log.cardMin = Math.round(T.cards / 60 * 10) / 10; log.menuMin = Math.round(log.assumedSec / 60 * 10) / 10; log.bossMin = Math.round(T.boss / 60 * 10) / 10;
  return log;
}
if (xpOpt) { const [b, st, q] = xpOpt.split(',').map(Number); PA.GROWTH.XP_CURVES.custom = { base: b, step: st, quad: q || 0, regionMult: regionXpOpt ? Object.fromEntries(['forest', 'ridge', 'marsh', 'den', 'deep'].map((k, i) => [k, Number(regionXpOpt.split(',')[i]) || 1])) : PA.GROWTH.XP_CURVES.v06.regionMult }; }
const curves = xpOpt ? ['custom'] : curveOpt === 'both' ? ['v05', 'v06'] : [curveOpt];
if (stratsOpt) for (const k of Object.keys(STRATS)) if (!stratsOpt.split(',').includes(k)) delete STRATS[k];
let md = `# 회차 시뮬레이션 ${tag ? '[' + tag + '] ' : ''}(v${PA.VERSION}, 봇 ${botId}, 배치 ${layout}, 난이도 ${difficulty}, 시작 무기 ${startWeapon}, 회차 구조 ${runMode}, 처치 경험치 ×${killXp}, 지역 경험치 ×${bonusXp}, 보스 체력 ${bossHpSet}${stopDay ? ', 성장 중단 ' + stopDay + '일차' : ''})\n\n전략 ${Object.keys(STRATS).length}종 × 시드 ${seeds.join(',')} × 경험치 곡선 ${curves.join('/')}. 봇 결과는 정책 비교용이며 사람의 체감 플레이타임·재미와 다르다.\n\n시간 계정(검수 수정 후): 시뮬레이션된 시간 = 전투 + 보스(고정 단계 시계). 가정한 메뉴 시간 = 카드 1장 ${MENU.card}초(전투 중 레벨업·지역 3택 포함, 실제 발생 시점에 기록) + 조우 전후 화면 ${MENU.encounter}초 + 하루 종료 ${MENU.dayEnd}초 + 휴식 ${MENU.rest}초. 합계는 보스전까지 포함해 마지막에 한 번만 더한다. 시간 초과(봇이 조우 240초/보스 300초 안에 못 끝냄)는 패배와 별도 열. 조우 생성·정산·3택은 게임과 같은 PA.Flow 경로(더 깊이 지역 3택 포함).\n`;
const all = [];
for (const curve of curves) {
  const C = PA.GROWTH.XP_CURVES[curve]; Object.assign(PA.GROWTH.XP, { base: C.base, step: C.step, quad: C.quad }); PA.GROWTH.REGION_XP_MULT = Object.assign({}, C.regionMult);
  md += `\n## 경험치 곡선 ${curve} (필요치 ${PA.GROWTH.XP.base}+${PA.GROWTH.XP.step}k+${PA.GROWTH.XP.quad}k², 지역 처치 경험치 배율 ${Object.values(C.regionMult).slice(0, 5).join('/')})\n\n| 전략 | 시드 | 레벨 | 레벨업/일 | 조우(패배/초과) | 휴식 | 더깊이(3택) | 임무(3택) | 사건(전투) | 카드(전투중) | 전투분 | 카드분 | 메뉴분(가정) | 보스분 | 합계분 | 무기2/무기3/E 시점(초) | 금화 | 보스 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) for (const seed of seeds) {
    const L = simulate(seed, sid); all.push(Object.assign({ curve, strategy: sid, seed }, L));
    md += `| ${STRATS[sid].name} | ${seed} | ${L.level} | ${L.levelUpsByDay.join('/')} | ${L.encounters}(${L.losses}/${L.timeouts}) | ${L.rests} | ${L.deeps}(${L.deepPicks}) | ${L.missions}(${L.missionPicks}) | ${L.eventCount}(${L.eventFights}) | ${L.cards}(${L.cardsInCombat}) | ${L.combatMin} | ${L.cardMin} | ${L.menuMin} | ${L.bossMin} | ${L.totalMin} | ${L.weapon2}/${L.weapon3}/${L.eSkill} | ${L.gold} | ${L.boss} |\n`;
  }
  md += `\n성장·전투 지표(곡선 ${curve}): 전투력 선택 = 무기/공통/기술/패시브 선택 수, 서비스 = 거점 서비스 선택, 사망전 처치% = 첫 공격을 실행하기 전에 죽은 적 비율, 실행/스폰 = 적 1마리당 실행한 공격 수\n\n| 전략 | 레벨업 | 전투력 선택 | 임무 3택 | 더깊이 3택 | 사건 선택 | 희귀 선택 | 서비스 | 건너뜀 | 선택 간격 평균/중앙(초) | 첫 선택(초) | 무기2/무기3/E(초) | 사망전 처치% | 실행/스폰 | 받은 피해(조우) | 받은 피해(보스) | 휴식 | 보스 패턴(시작 횟수) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) { const rows = all.filter(r => r.curve === curve && r.strategy === sid); if (!rows.length) continue; const avg = (f) => Math.round(rows.reduce((a, r) => a + f(r), 0) / rows.length * 10) / 10; const pat = {}; for (const r of rows) for (const k in r.bossPatterns) pat[k] = (pat[k] || 0) + r.bossPatterns[k]; const patText = Object.keys(pat).sort().map(k => `${k} ${Math.round(pat[k] / rows.length * 10) / 10}`).join(', '); md += `| ${STRATS[sid].name} | ${avg(r => r.level - 1)} | ${avg(r => r.combatPicks)} | ${avg(r => r.missionPicks)} | ${avg(r => r.deepPicks)} | ${avg(r => r.eventCount)} | ${avg(r => r.rarePicksN)} | ${avg(r => r.servicePicks)} | ${avg(r => r.skips)} | ${avg(r => r.pickGapAvg)}/${avg(r => r.pickGapMed)} | ${avg(r => r.firstPickSec)} | ${avg(r => r.weapon2 || 0)}/${avg(r => r.weapon3 || 0)}/${avg(r => r.eSkill || 0)} | ${avg(r => r.dbaPct)} | ${avg(r => r.execPerSpawn)} | ${avg(r => r.taken)} | ${avg(r => r.bossTaken)} | ${avg(r => r.rests)} | ${patText} |\n`; }
  md += `\n전략별 평균(곡선 ${curve}):\n\n| 전략 | 레벨 | 1일차 레벨업 | 1일차 비중% | 조우 | 패배 | 초과 | 휴식 | 더깊이 3택 | 임무 | 사건 | 전투분 | 보스분 | 메뉴분(가정) | 합계분 | 금화 | 완주 | 보스 총초 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) { const rows = all.filter(r => r.curve === curve && r.strategy === sid); const avg = (f) => Math.round(rows.reduce((a, r) => a + f(r), 0) / rows.length * 10) / 10; const d1 = avg(r => r.levelUpsByDay[0]); md += `| ${STRATS[sid].name} | ${avg(r => r.level)} | ${d1} | ${Math.round(d1 / Math.max(1, avg(r => r.level - 1)) * 100)} | ${avg(r => r.encounters)} | ${avg(r => r.losses)} | ${avg(r => r.timeouts)} | ${avg(r => r.rests)} | ${avg(r => r.deepPicks)} | ${avg(r => r.missions)} | ${avg(r => r.eventCount)} | ${avg(r => r.combatMin)} | ${avg(r => r.bossMin)} | ${avg(r => r.menuMin)} | ${avg(r => r.totalMin)} | ${avg(r => r.gold)} | ${rows.filter(r => r.cleared).length}/${rows.length} | ${avg(r => r.bossSec)} |\n`; }
}
md += `\n## 보스 관문 결과(전략 × 시드)\n\n| 전략 | 시드 | 보스 | 단계 | 결과 | 초 | 남은 체력 | 보스 남은/최대 | 받은 피해 | Lv | 재도전 | 패턴(시작) |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n` + all.filter(r => r.curve === curves[curves.length - 1]).flatMap(r => r.bosses.map(b => `| ${STRATS[r.strategy].name} | ${r.seed} | ${PA.BOSS_DEFS[b.id].name} | ${b.stage + 1} | ${b.status} | ${b.sec} | ${b.hp} | ${b.bossHp}/${b.bossHpMax} | ${b.taken} | ${b.level} | ${b.retries} | ${Object.keys(b.patterns || {}).map(k => k + ' ' + b.patterns[k]).join(', ')} |`)).join('\n') + '\n';
md += `\n## 6일차 빌드 예시(곡선 ${curves[curves.length - 1]}, 시드 ${seeds[0]})\n\n` + Object.keys(STRATS).map(sid => { const r = all.find(x => x.curve === curves[curves.length - 1] && x.strategy === sid && x.seed === seeds[0]); return `- ${STRATS[sid].name}: ${r.build}`; }).join('\n') + '\n';
md += `\n## 경제(v0.8): 하루 획득 금화(정산 기준, 사용분 포함)·구매·강화·교체·예약·패배로 잃은 날\n\n| 전략 | 시드 | 하루 금화(평균) | 일별 | 총 사용 | 장비 | 새 기술 | 강화 | 예약 소비 | 심층 보상 | 패배로 잃은 날 | 최종 금화 |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
for (const r of all) md += `| ${STRATS[r.strategy].name} | ${r.seed} | ${r.goldPerDay} | ${r.goldEarnedByDay.join('/')} | ${r.goldSpent} | ${r.equipBought.map(id => PA.EQUIPMENT[id].name).join(',') || '-'} | ${r.skillsBought} | ${r.forge} | ${r.steered} | ${r.deepRewardText || '-'} | ${r.daysLostToDefeat} | ${r.gold} |\n`;
for (const sid of Object.keys(STRATS)) { const rows = all.filter(r => r.strategy === sid); if (!rows.length) continue; const avg = (f) => Math.round(rows.reduce((a, r) => a + f(r), 0) / rows.length * 10) / 10; md += `- ${STRATS[sid].name} 평균: 하루 금화 ${avg(r => r.goldPerDay)} · 사용 ${avg(r => r.goldSpent)} · 장비 ${avg(r => r.equipN)}개 · 강화 ${avg(r => r.forge)} · 예약 ${avg(r => r.steered)} · 패배로 잃은 날 ${avg(r => r.daysLostToDefeat)}\n`; }
fs.mkdirSync(path.dirname(mdPath), { recursive: true }); fs.writeFileSync(mdPath, md); fs.writeFileSync(mdPath.replace(/\.md$/, '.json'), JSON.stringify(all, null, 1));
console.log(md);
