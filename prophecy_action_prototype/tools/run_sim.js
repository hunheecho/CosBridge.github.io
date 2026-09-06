// 회차 시뮬레이션(헤드리스). 고정 빌드 전투 시뮬레이션(lab_sim)과 분리: 봇이 6일 동안 출격하고 레벨업 카드를 고른다(성장 적용).
// 사용: node tools/run_sim.js [--seeds 1,2,3] [--curve v05|v06|both] [--layout classic|trial] [--difficulty base|candA..] [--bot balanced] [--md docs/sim/run_sim.md]
// 전략 5종: easy(쉬운 지역 반복) gradual(점차 위험 지역) risky(위험 지역 우선) cautious(체력 낮으면 휴식·더 깊이 안 함) deep(더 깊이 탐험 적극)
// 메뉴/선택 시간 가정(전투 시간과 별도 표기): 조우 전후 화면 25초, 레벨업 카드 1장 6초, 하루 종료 10초, 휴식 5초. 순수 전투 시간이 길다고 좋은 것으로 판정하지 않는다.
const fs = require('fs'), path = require('path');
const { load } = require('../test/load'); const PA = load();
const args = process.argv.slice(2); const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const seeds = opt('seeds', '1,2,3,4,5').split(',').map(Number), curveOpt = opt('curve', 'both'), stratsOpt = opt('strats', ''), xpOpt = opt('xp', ''), regionXpOpt = opt('regionxp', ''), layout = opt('layout', 'classic'), difficulty = opt('difficulty', 'base'), botId = opt('bot', 'balanced'), mdPath = opt('md', path.join(__dirname, '..', 'docs', 'sim', 'run_sim.md'));
const MENU = { encounter: 25, card: 6, dayEnd: 10, rest: 5 };
const STRATS = {
  easy:     { name: '쉬운 지역 반복', pick: () => 'forest', restBelow: 0.3, deep: false },
  gradual:  { name: '점차 위험 지역으로', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.3, deep: false },
  risky:    { name: '위험 지역 우선', pick: () => ['deep', 'den'], restBelow: 0.3, deep: false },
  cautious: { name: '체력 낮으면 일찍 휴식', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.6, deep: false },
  deep:     { name: '더 깊이 탐험 적극', pick: (day) => day <= 2 ? ['forest', 'ridge'] : day <= 4 ? ['marsh', 'den'] : ['den', 'deep'], restBelow: 0.3, deep: true },
};
function resolveLevelUps(run, regionId, st, log) {
  const g = run.growth;
  while (g.pendingLevelUps > 0) {
    const offer = PA.Growth.generateOffer(run, { pool: 'level', regionId });
    if (!offer.choices.length) { PA.Growth.skipChoice(run); continue; }
    const c = PA.Bot.pickChoice(offer, run.seed); PA.Growth.applyChoice(run, c); log.cards++;
    if (st) PA.Combat.rebuild(st, PA.Run.build(run));
  }
}
function fight(run, regionId, deep, seed, log) {
  const st = PA.Combat.create({ build: PA.Run.build(run), hp: run.hp, seed, waves: PA.Run.encounterWaves(regionId, deep, run), objective: PA.Run.encounterObjective(regionId, deep, run), arena: PA.Run.regionArena(regionId, run), hpMult: PA.Run.hpMultFor(run, regionId, deep), regionId });
  PA.Bot.runCombat(st, botId, { maxSec: 240, onLevelUp: (s) => resolveLevelUps(run, regionId, s, log) });
  return st;
}
function simulate(seed, stratId) {
  const S = STRATS[stratId], run = PA.Run.newRun(seed, 'sword'); run.layout = layout; run.difficulty = difficulty; const g = run.growth;
  const log = { combatSec: 0, menuSec: 0, encounters: 0, losses: 0, rests: 0, deeps: 0, cards: 0, levelUpsByDay: [], weapon2: null, weapon3: null, eSkill: null, hpAtBoss: 0 };
  let total = 0; const mark = () => { const t = Math.round(total); if (log.weapon2 == null && g.weapons.length >= 2) log.weapon2 = t; if (log.weapon3 == null && g.weapons.length >= 3) log.weapon3 = t; if (log.eSkill == null && g.skills.e) log.eSkill = t; };
  for (let day = 1; day <= 6; day++) {
    const lvStart = g.level; let guard = 0;
    while (guard++ < 20) {
      const hpMax = PA.Run.build(run).hpMax;
      if (run.hp < hpMax * S.restBelow && PA.Run.canRest(run)) { PA.Run.rest(run); log.rests++; total += MENU.rest; log.menuSec += MENU.rest; continue; }
      const want = [].concat(S.pick(day)); let rid = want.find(id => PA.Run.canSortie(run, id));
      if (!rid) { const alt = PA.REGIONS.slice().reverse().find(r => PA.Run.canSortie(run, r.id) && want.some(w => PA.REGIONS.findIndex(x => x.id === w) >= PA.REGIONS.findIndex(x => x.id === r.id))) || PA.REGIONS.find(r => PA.Run.canSortie(run, r.id)); if (!alt) break; rid = alt.id; }
      const s = PA.Run.startSortie(run, rid);
      let st = fight(run, rid, false, s.seed, log); log.combatSec += st.t; log.encounters++; total += st.t + MENU.encounter; log.menuSec += MENU.encounter;
      const settle = (st, deep) => { const rw = PA.Run.rollReward(run, s, st.rng, { chestGold: st.stats.chestGold, eliteKilled: st.enemies.some(e => e.elite && e.dead) }); PA.Run.applyEncounterResult(run, s, 'won', rw, st.player.hp); PA.Growth.addXp(g, PA.Run.regionBonusXp(rid, deep)); const before = log.cards; resolveLevelUps(run, rid, null, log); total += (log.cards - before) * MENU.card; log.menuSec += (log.cards - before) * MENU.card; };
      if (st.status === 'won') {
        settle(st, false);
        if (S.deep && PA.Run.canDeepExplore(run) && run.hp >= PA.Run.build(run).hpMax * 0.5) { PA.Run.deepExplore(run, s); log.deeps++; st = fight(run, rid, true, s.seed + 7, log); log.combatSec += st.t; log.encounters++; total += st.t + MENU.encounter; log.menuSec += MENU.encounter; if (st.status === 'won') settle(st, true); else { PA.Run.applyEncounterResult(run, s, 'lost', null, 0); PA.Run.defeat(run, s); log.losses++; mark(); continue; } }
        PA.Run.returnToBase(run, s);
      } else { PA.Run.applyEncounterResult(run, s, 'lost', null, 0); PA.Run.defeat(run, s); log.losses++; }
      mark();
    }
    log.levelUpsByDay.push(g.level - lvStart); total += MENU.dayEnd; log.menuSec += MENU.dayEnd;
    PA.Run.endDay(run);
  }
  log.level = g.level; log.gold = run.gold; log.mats = Object.assign({}, run.mats); log.totalMin = Math.round(total / 60); log.combatMin = Math.round(log.combatSec / 60 * 10) / 10; log.menuMin = Math.round(log.menuSec / 60 * 10) / 10;
  log.build = `${g.weapons.map(w => w.id + w.level + (w.mods.length ? '[' + w.mods.join('+') + ']' : '')).join(' ')} | 공통 ${Object.keys(g.commons).map(k => k + g.commons[k]).join(',') || '-'} | E ${g.skills.e ? g.skills.e.id + g.skills.e.level : '-'} | 패시브 ${Object.keys(g.passives).map(k => k + g.passives[k]).join(',') || '-'}`;
  run.phase = 'boss_prep'; PA.Run.startBoss(run);
  const bs = PA.Combat.create({ build: PA.Run.build(run), seed: PA.Run.bossSeed(run), boss: true, arena: 'clearing', waves: [] }); PA.Bot.runCombat(bs, botId, { maxSec: 300 });
  log.boss = `${bs.status}@${Math.round(bs.t)}s hp${Math.round(bs.player.hp)} 보스${Math.round(bs.boss.hp)}`; log.bossStatus = bs.status; log.bossSec = Math.round(bs.t);
  return log;
}
if (xpOpt) { const [b, st, q] = xpOpt.split(',').map(Number); PA.GROWTH.XP_CURVES.custom = { base: b, step: st, quad: q || 0, regionMult: regionXpOpt ? Object.fromEntries(['forest', 'ridge', 'marsh', 'den', 'deep'].map((k, i) => [k, Number(regionXpOpt.split(',')[i]) || 1])) : PA.GROWTH.XP_CURVES.v06.regionMult }; }
const curves = xpOpt ? ['custom'] : curveOpt === 'both' ? ['v05', 'v06'] : [curveOpt];
if (stratsOpt) for (const k of Object.keys(STRATS)) if (!stratsOpt.split(',').includes(k)) delete STRATS[k];
let md = `# 회차 시뮬레이션 (v${PA.VERSION}, 봇 ${botId}, 배치 ${layout}, 난이도 ${difficulty})\n\n전략 5종 × 시드 ${seeds.join(',')} × 경험치 곡선 ${curves.join('/')}. 봇 결과는 정책 비교용이며 사람의 체감 플레이타임·재미와 다르다. 추정 회차 시간 = 전투 시간 + 가정한 메뉴 시간(조우 전후 ${MENU.encounter}초, 카드 1장 ${MENU.card}초, 하루 종료 ${MENU.dayEnd}초, 휴식 ${MENU.rest}초).\n`;
const all = [];
for (const curve of curves) {
  const C = PA.GROWTH.XP_CURVES[curve]; Object.assign(PA.GROWTH.XP, { base: C.base, step: C.step, quad: C.quad }); PA.GROWTH.REGION_XP_MULT = Object.assign({}, C.regionMult);
  md += `\n## 경험치 곡선 ${curve} (필요치 ${PA.GROWTH.XP.base}+${PA.GROWTH.XP.step}k+${PA.GROWTH.XP.quad}k², 지역 처치 경험치 배율 ${Object.values(C.regionMult).slice(0, 5).join('/')})\n\n| 전략 | 시드 | 레벨 | 레벨업/일 | 조우(패배) | 휴식 | 더깊이 | 전투분 | 메뉴분 | 추정분 | 무기2/무기3/E 시점(초) | 금화 | 보스 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) for (const seed of seeds) {
    const L = simulate(seed, sid); all.push(Object.assign({ curve, strategy: sid, seed }, L));
    md += `| ${STRATS[sid].name} | ${seed} | ${L.level} | ${L.levelUpsByDay.join('/')} | ${L.encounters}(${L.losses}) | ${L.rests} | ${L.deeps} | ${L.combatMin} | ${L.menuMin} | ${L.totalMin} | ${L.weapon2}/${L.weapon3}/${L.eSkill} | ${L.gold} | ${L.boss} |\n`;
  }
  md += `\n전략별 평균(곡선 ${curve}):\n\n| 전략 | 레벨 | 1일차 레벨업 | 1일차 비중% | 조우 | 패배 | 휴식 | 추정분 | 금화 | 보스 승리 | 보스 평균초 |\n|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) { const rows = all.filter(r => r.curve === curve && r.strategy === sid); const avg = (f) => Math.round(rows.reduce((a, r) => a + f(r), 0) / rows.length * 10) / 10; const d1 = avg(r => r.levelUpsByDay[0]); md += `| ${STRATS[sid].name} | ${avg(r => r.level)} | ${d1} | ${Math.round(d1 / Math.max(1, avg(r => r.level - 1)) * 100)} | ${avg(r => r.encounters)} | ${avg(r => r.losses)} | ${avg(r => r.rests)} | ${avg(r => r.totalMin)} | ${avg(r => r.gold)} | ${rows.filter(r => r.bossStatus === 'won').length}/${rows.length} | ${avg(r => r.bossSec)} |\n`; }
}
md += `\n## 6일차 빌드 예시(곡선 ${curves[curves.length - 1]}, 시드 ${seeds[0]})\n\n` + Object.keys(STRATS).map(sid => { const r = all.find(x => x.curve === curves[curves.length - 1] && x.strategy === sid && x.seed === seeds[0]); return `- ${STRATS[sid].name}: ${r.build}`; }).join('\n') + '\n';
fs.mkdirSync(path.dirname(mdPath), { recursive: true }); fs.writeFileSync(mdPath, md); fs.writeFileSync(mdPath.replace(/\.md$/, '.json'), JSON.stringify(all, null, 1));
console.log(md);
