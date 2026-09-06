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
};
// 시간 계정(수정 후): 전투(시뮬레이션 초) / 카드(레벨업·지역 3택, 실제 발생 시점에 기록·전투 중 포함) / 화면(조우 전후) / 휴식·하루 종료 / 보스. 합계는 마지막에 한 번만 더한다.
// 시뮬레이션된 시간(전투·보스)과 가정한 메뉴 시간(카드·화면·휴식·하루)을 구분해 표기한다. 시간 초과(봇이 maxSec 안에 못 끝냄)는 패배와 별도로 센다.
const startWeapon = opt('start', 'sword');
function simulate(seed, stratId) {
  const S = STRATS[stratId], run = PA.Run.newRun(seed, startWeapon); run.layout = layout; run.difficulty = difficulty; const g = run.growth;
  const T = { combat: 0, cards: 0, screens: 0, rest: 0, dayEnd: 0, boss: 0 }; // 초 단위 버킷
  const log = { encounters: 0, losses: 0, timeouts: 0, rests: 0, deeps: 0, cards: 0, cardsInCombat: 0, deepPicks: 0, missions: 0, missionPicks: 0, eventCount: 0, eventChoices: [], eventFights: 0, levelUpsByDay: [], weapon2: null, weapon3: null, eSkill: null, events: [] };
  let clock = 0; // 실제 경과 시점(초): 카드 획득 시점 기록용
  const mark = () => { const t = Math.round(clock); if (log.weapon2 == null && g.weapons.length >= 2) log.weapon2 = t; if (log.weapon3 == null && g.weapons.length >= 3) log.weapon3 = t; if (log.eSkill == null && g.skills.e) log.eSkill = t; };
  const pick = (off) => PA.Bot.pickChoice(off, run.seed);
  const onPick = (where) => (off, c) => { T.cards += MENU.card; clock += MENU.card; log.cards++; if (where === 'combat') log.cardsInCombat++; if (off.pool === 'deep') log.deepPicks++; log.events.push({ t: Math.round(clock), kind: off.pool, key: c ? c.key : 'skip', where }); mark(); };
  const fight = (s) => {
    const st = PA.Flow.makeEncounter(run, s); const t0 = clock; let cardSec = 0;
    PA.Bot.runCombat(st, botId, { maxSec: 240, onLevelUp: (st2) => { clock = t0 + st2.t + cardSec; const before = T.cards; PA.Flow.resolveAll(run, { regionId: s.regionId }, pick, onPick('combat')); cardSec += T.cards - before; PA.Combat.rebuild(st2, PA.Run.build(run)); } });
    T.combat += st.t; clock = t0 + st.t + cardSec; log.encounters++;
    T.screens += MENU.encounter; clock += MENU.encounter;
    if (st.status === 'running') { st.status = 'timeout'; log.timeouts++; }
    return st;
  };
  const settleWin = (s, st) => { PA.Flow.settleVictory(run, s, st); PA.Flow.resolveAll(run, { regionId: s.regionId }, pick, onPick('screen')); mark(); };
  // 탐험 사건(출격당 최대 1회): 봇 정책으로 선택. 추가 전투/더 깊이는 같은 조우 경로. 반환: 'fight' | 'deep' | null
  const handleEvent = (s) => { if (!s.event || s.event.resolved) return null; const choice = PA.Events.botChoose(run, s, stratId); const r = PA.Events.resolve(run, s, choice); log.eventCount++; log.eventChoices.push(s.event.id + ':' + choice); T.screens += MENU.event; clock += MENU.event; if (r.next === 'offer') PA.Flow.resolveAll(run, { regionId: s.regionId }, pick, onPick('screen')); return r.next === 'fight' || r.next === 'deep' ? r.next : null; };
  const settleLoss = (s, st) => { PA.Flow.settleDefeat(run, s, st); if (st.status === 'lost') log.losses++; mark(); };
  for (let day = 1; day <= 6; day++) {
    const lvStart = g.level; let guard = 0;
    while (guard++ < 20) {
      const hpMax = PA.Run.build(run).hpMax;
      if (run.hp < hpMax * S.restBelow && PA.Run.canRest(run)) { PA.Run.rest(run); log.rests++; T.rest += MENU.rest; clock += MENU.rest; continue; }
      const want = [].concat(S.pick(day)); let rid = want.find(id => PA.Run.canSortie(run, id));
      if (!rid) { const alt = PA.REGIONS.slice().reverse().find(r => PA.Run.canSortie(run, r.id) && want.some(w => PA.REGIONS.findIndex(x => x.id === w) >= PA.REGIONS.findIndex(x => x.id === r.id))) || PA.REGIONS.find(r => PA.Run.canSortie(run, r.id)); if (!alt) break; rid = alt.id; }
      const s = PA.Run.startSortie(run, rid);
      let st = fight(s);
      if (st.status === 'won') {
        settleWin(s, st);
        let lost = false;
        const evNext = handleEvent(s);
        if (evNext === 'fight') { log.eventFights++; st = fight(s); if (st.status === 'won') settleWin(s, st); else { settleLoss(s, st); lost = true; } }
        else if (evNext === 'deep') { log.deeps++; st = fight(s); if (st.status === 'won') settleWin(s, st); else { settleLoss(s, st); lost = true; } }
        if (lost) continue;
        if (!s.deep && S.deep && PA.Run.canDeepExplore(run, s) && run.hp >= PA.Run.build(run).hpMax * 0.5) {
          PA.Run.deepExplore(run, s); log.deeps++; st = fight(s);
          if (st.status === 'won') settleWin(s, st); else { settleLoss(s, st); continue; }
        }
        PA.Flow.returnHome(run, s);
      } else settleLoss(s, st);
    }
    log.levelUpsByDay.push(g.level - lvStart); T.dayEnd += MENU.dayEnd; clock += MENU.dayEnd;
    PA.Run.endDay(run);
  }
  log.level = g.level; log.gold = run.gold; log.mats = Object.assign({}, run.mats); log.hpBeforeBoss = run.hp;
  log.build = `${g.weapons.map(w => w.id + w.level + (w.mods.length ? '[' + w.mods.join('+') + ']' : '')).join(' ')} | 공통 ${Object.keys(g.commons).map(k => k + g.commons[k]).join(',') || '-'} | E ${g.skills.e ? g.skills.e.id + g.skills.e.level : '-'} | 패시브 ${Object.keys(g.passives).map(k => k + g.passives[k]).join(',') || '-'}`;
  run.phase = 'boss_prep'; PA.Run.startBoss(run);
  const bs = PA.Combat.create({ build: PA.Run.build(run), seed: PA.Run.bossSeed(run), boss: true, arena: 'clearing', waves: [] }); PA.Bot.runCombat(bs, botId, { maxSec: 300 });
  if (bs.status === 'running') bs.status = 'timeout';
  T.boss += bs.t; clock += bs.t;
  log.boss = `${bs.status}@${Math.round(bs.t)}s hp${Math.round(bs.player.hp)} 보스${Math.round(bs.boss.hp)}`; log.bossStatus = bs.status; log.bossSec = Math.round(bs.t);
  // 합계는 여기서 한 번만: 버킷 합 = 시계(clock)와 같아야 한다(검증)
  const sum = Object.values(T).reduce((a, b) => a + b, 0); if (Math.abs(sum - clock) > 0.5) throw new Error(`시간 계정 불일치 ${sum} vs ${clock}`);
  log.time = Object.fromEntries(Object.keys(T).map(k => [k, Math.round(T[k])])); log.simulatedSec = Math.round(T.combat + T.boss); log.assumedSec = Math.round(T.cards + T.screens + T.rest + T.dayEnd);
  log.totalMin = Math.round(sum / 60 * 10) / 10; log.combatMin = Math.round(T.combat / 60 * 10) / 10; log.cardMin = Math.round(T.cards / 60 * 10) / 10; log.menuMin = Math.round(log.assumedSec / 60 * 10) / 10; log.bossMin = Math.round(T.boss / 60 * 10) / 10;
  return log;
}
if (xpOpt) { const [b, st, q] = xpOpt.split(',').map(Number); PA.GROWTH.XP_CURVES.custom = { base: b, step: st, quad: q || 0, regionMult: regionXpOpt ? Object.fromEntries(['forest', 'ridge', 'marsh', 'den', 'deep'].map((k, i) => [k, Number(regionXpOpt.split(',')[i]) || 1])) : PA.GROWTH.XP_CURVES.v06.regionMult }; }
const curves = xpOpt ? ['custom'] : curveOpt === 'both' ? ['v05', 'v06'] : [curveOpt];
if (stratsOpt) for (const k of Object.keys(STRATS)) if (!stratsOpt.split(',').includes(k)) delete STRATS[k];
let md = `# 회차 시뮬레이션 (v${PA.VERSION}, 봇 ${botId}, 배치 ${layout}, 난이도 ${difficulty}, 시작 무기 ${startWeapon})\n\n전략 ${Object.keys(STRATS).length}종 × 시드 ${seeds.join(',')} × 경험치 곡선 ${curves.join('/')}. 봇 결과는 정책 비교용이며 사람의 체감 플레이타임·재미와 다르다.\n\n시간 계정(검수 수정 후): 시뮬레이션된 시간 = 전투 + 보스(고정 단계 시계). 가정한 메뉴 시간 = 카드 1장 ${MENU.card}초(전투 중 레벨업·지역 3택 포함, 실제 발생 시점에 기록) + 조우 전후 화면 ${MENU.encounter}초 + 하루 종료 ${MENU.dayEnd}초 + 휴식 ${MENU.rest}초. 합계는 보스전까지 포함해 마지막에 한 번만 더한다. 시간 초과(봇이 조우 240초/보스 300초 안에 못 끝냄)는 패배와 별도 열. 조우 생성·정산·3택은 게임과 같은 PA.Flow 경로(더 깊이 지역 3택 포함).\n`;
const all = [];
for (const curve of curves) {
  const C = PA.GROWTH.XP_CURVES[curve]; Object.assign(PA.GROWTH.XP, { base: C.base, step: C.step, quad: C.quad }); PA.GROWTH.REGION_XP_MULT = Object.assign({}, C.regionMult);
  md += `\n## 경험치 곡선 ${curve} (필요치 ${PA.GROWTH.XP.base}+${PA.GROWTH.XP.step}k+${PA.GROWTH.XP.quad}k², 지역 처치 경험치 배율 ${Object.values(C.regionMult).slice(0, 5).join('/')})\n\n| 전략 | 시드 | 레벨 | 레벨업/일 | 조우(패배/초과) | 휴식 | 더깊이(3택) | 카드(전투중) | 전투분 | 카드분 | 메뉴분(가정) | 보스분 | 합계분 | 무기2/무기3/E 시점(초) | 금화 | 보스 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) for (const seed of seeds) {
    const L = simulate(seed, sid); all.push(Object.assign({ curve, strategy: sid, seed }, L));
    md += `| ${STRATS[sid].name} | ${seed} | ${L.level} | ${L.levelUpsByDay.join('/')} | ${L.encounters}(${L.losses}/${L.timeouts}) | ${L.rests} | ${L.deeps}(${L.deepPicks}) | ${L.cards}(${L.cardsInCombat}) | ${L.combatMin} | ${L.cardMin} | ${L.menuMin} | ${L.bossMin} | ${L.totalMin} | ${L.weapon2}/${L.weapon3}/${L.eSkill} | ${L.gold} | ${L.boss} |\n`;
  }
  md += `\n전략별 평균(곡선 ${curve}):\n\n| 전략 | 레벨 | 1일차 레벨업 | 1일차 비중% | 조우 | 패배 | 초과 | 휴식 | 더깊이 3택 | 전투분 | 메뉴분(가정) | 합계분 | 금화 | 보스 승리 | 보스 평균초 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
  for (const sid of Object.keys(STRATS)) { const rows = all.filter(r => r.curve === curve && r.strategy === sid); const avg = (f) => Math.round(rows.reduce((a, r) => a + f(r), 0) / rows.length * 10) / 10; const d1 = avg(r => r.levelUpsByDay[0]); md += `| ${STRATS[sid].name} | ${avg(r => r.level)} | ${d1} | ${Math.round(d1 / Math.max(1, avg(r => r.level - 1)) * 100)} | ${avg(r => r.encounters)} | ${avg(r => r.losses)} | ${avg(r => r.timeouts)} | ${avg(r => r.rests)} | ${avg(r => r.deepPicks)} | ${avg(r => r.combatMin)} | ${avg(r => r.menuMin)} | ${avg(r => r.totalMin)} | ${avg(r => r.gold)} | ${rows.filter(r => r.bossStatus === 'won').length}/${rows.length} | ${avg(r => r.bossSec)} |\n`; }
}
md += `\n## 6일차 빌드 예시(곡선 ${curves[curves.length - 1]}, 시드 ${seeds[0]})\n\n` + Object.keys(STRATS).map(sid => { const r = all.find(x => x.curve === curves[curves.length - 1] && x.strategy === sid && x.seed === seeds[0]); return `- ${STRATS[sid].name}: ${r.build}`; }).join('\n') + '\n';
fs.mkdirSync(path.dirname(mdPath), { recursive: true }); fs.writeFileSync(mdPath, md); fs.writeFileSync(mdPath.replace(/\.md$/, '.json'), JSON.stringify(all, null, 1));
console.log(md);
