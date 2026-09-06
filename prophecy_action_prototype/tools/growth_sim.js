// 회차 성장 속도 시뮬레이션(헤드리스). 봇이 6일 동안 출격하고 레벨업 선택은 시드 난수로 고른다.
// 측정: 총 전투 시간, 레벨업 횟수, 첫 공격 변화 시점, 2·3번째 무기·E 획득 시점, 선택 종류 비율, 6일차 빌드, 쉬운 지역 반복 vs 위험 지역 비교.
// 사용: node tools/growth_sim.js [plan] [seeds]   plan: mixed | easy | risky
const { load } = require('../test/load'); const PA = load(); const { policy } = require('../test/bot');
const plan = process.argv[2] || 'mixed'; const seeds = (process.argv[3] || '1,2,3').split(',').map(Number);
const PLANS = {
  mixed: ['forest', 'ridge', 'forest', 'ridge', 'marsh', 'den', 'marsh', 'den', 'deep', 'den', 'deep', 'marsh', 'den', 'deep'],
  easy: ['forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest', 'forest'],
  risky: ['den', 'den', 'deep', 'den', 'deep', 'deep', 'den', 'deep', 'den', 'deep', 'deep', 'den', 'deep', 'deep'],
};
function fight(run, regionId, deep, seed) {
  const st = PA.Combat.create({ build: PA.Run.build(run), hp: run.hp, seed, waves: PA.Run.encounterWaves(regionId, deep), objective: PA.Run.encounterObjective(regionId, deep) });
  const dt = PA.CONFIG.STEP; let n = 0, last = { mx: 0, my: 0 }; const max = 120 * 240;
  while (st.status === 'running' && n < max) {
    const inp = n % 5 === 0 ? policy(PA, st) : Object.assign({}, last, { dodge: false, special: false }); last = inp;
    if (run.growth.skills.e && st.player.eCd <= 0 && n % 60 === 0 && st.enemies.some(e => !e.dead && PA.m.dist(e, st.player) < 200)) inp.skillE = true;
    PA.Combat.step(st, inp, dt); n++;
    if (st.levelUps > 0) { st.levelUps = 0; resolveLevelUps(run, regionId, st); }
  }
  return st;
}
function resolveLevelUps(run, regionId, st) {
  const g = run.growth;
  while (g.pendingLevelUps > 0) {
    const offer = PA.Growth.generateOffer(run, { pool: 'level', regionId });
    if (!offer.choices.length) { PA.Growth.skipChoice(run); continue; }
    const c = offer.choices[Math.floor(PA.rng.create(run.seed + g.choiceSeq * 13).next() * offer.choices.length)];
    PA.Growth.applyChoice(run, c);
    if (st) PA.Combat.rebuild(st, PA.Run.build(run));
  }
}
function simulate(seed, planName) {
  const run = PA.Run.newRun(seed, 'sword'); const g = run.growth; const P = PLANS[planName];
  const log = { combatSec: 0, encounters: 0, losses: 0, firstChange: null, weapon2: null, weapon3: null, eSkill: null, levelUpsByDay: [], picks: null, deaths: 0 };
  let pi = 0, elapsedTotal = 0;
  const marks = () => { if (log.firstChange == null && (g.weapons.length > 1 || g.weapons.some(w => w.mods.length) || g.commons.echo || g.commons.wide)) log.firstChange = Math.round(elapsedTotal); if (log.weapon2 == null && g.weapons.length >= 2) log.weapon2 = Math.round(elapsedTotal); if (log.weapon3 == null && g.weapons.length >= 3) log.weapon3 = Math.round(elapsedTotal); if (log.eSkill == null && g.skills.e) log.eSkill = Math.round(elapsedTotal); };
  for (let day = 1; day <= 6; day++) {
    const lvStart = g.level;
    while (true) {
      const regionId = P[pi % P.length];
      if (!PA.Run.canSortie(run, regionId)) { const alt = PA.REGIONS.find(r => PA.Run.canSortie(run, r.id)); if (!alt) break; if (run.hp < PA.Run.build(run).hpMax * 0.5 && PA.Run.canRest(run)) { PA.Run.rest(run); continue; } var rid = alt.id; } else var rid = regionId;
      pi++;
      const s = PA.Run.startSortie(run, rid);
      const st = fight(run, rid, false, s.seed);
      log.combatSec += st.t; log.encounters++; elapsedTotal += st.t + 25; // 조우 + 거점·화면 전환 약 25초 가정
      if (st.status === 'won') { const rw = PA.Run.rollReward(run, s, st.rng, { chestGold: st.stats.chestGold, eliteKilled: st.enemies.some(e => e.elite && e.dead) }); PA.Run.applyEncounterResult(run, s, 'won', rw, st.player.hp); PA.Growth.addXp(g, PA.Run.regionBonusXp(rid, false)); resolveLevelUps(run, rid); PA.Run.returnToBase(run, s); }
      else { PA.Run.applyEncounterResult(run, s, 'lost', null, 0); PA.Run.defeat(run, s); log.losses++; }
      marks();
    }
    log.levelUpsByDay.push(g.level - lvStart);
    PA.Run.endDay(run);
  }
  log.level = g.level; log.picks = g.picks; log.totalMin = Math.round(elapsedTotal / 60);
  log.build = `${g.weapons.map(w => w.id + w.level + (w.mods.length ? '[' + w.mods.join('+') + ']' : '')).join(' ')} | 공통 ${Object.keys(g.commons).map(k => k + g.commons[k]).join(',') || '-'} | E ${g.skills.e ? g.skills.e.id + g.skills.e.level : '-'} | 패시브 ${Object.keys(g.passives).map(k => k + g.passives[k]).join(',') || '-'}`;
  // 보스전
  run.phase = 'boss_prep'; PA.Run.startBoss(run);
  const { runBossFight } = require('../test/bot'); const bs = runBossFight(PA, run, PA.Run.bossSeed(run), 300);
  log.boss = `${bs.status}@${Math.round(bs.t)}s hp${Math.round(bs.player.hp)} 보스${Math.round(bs.boss.hp)}`;
  return log;
}
for (const seed of seeds) {
  const L = simulate(seed, plan);
  const picks = Object.entries(L.picks).filter(([k, v]) => v).map(([k, v]) => `${k}:${v}`).join(' ');
  console.log(`[${plan} seed ${seed}] 레벨 ${L.level} · 레벨업/일 ${L.levelUpsByDay.join('/')} · 조우 ${L.encounters}(패배 ${L.losses}) · 전투 ${Math.round(L.combatSec / 60)}분 · 추정 회차 ${L.totalMin}분`);
  console.log(`   첫 변화 ${L.firstChange}s · 무기2 ${L.weapon2}s · 무기3 ${L.weapon3}s · E ${L.eSkill}s · 선택 ${picks}`);
  console.log(`   빌드: ${L.build}`);
  console.log(`   보스: ${L.boss}`);
}
