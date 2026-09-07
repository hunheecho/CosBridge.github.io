// §2 시작 자동기술 3종 집중 비교(헤드리스). 같은 시드·같은 정책을 짝지어 비교한다.
//  A 첫 전투(1일차 새벽 근교 숲, 장비·개조 없음)  B 첫날 전체(점진 전략: 숲→능선, 체력 30% 미만이면 휴식)  D 첫 보스(run_sim 덤프의 3일차 관문 빌드)
//  C(같은 선택 횟수)는 tools/paired_E.js가 raw_E에서 짝지어 계산한다.
// 사용: node tools/start_compare.js [--seeds 10] [--policies balanced,aware] → docs/sim/v08/START_COMPARE.md
const fs = require('fs'), path = require('path'); const { load } = require('../test/load'); const PA = load();
const args = process.argv.slice(2); const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const N = parseInt(opt('seeds', '10'), 10), POLS = opt('policies', 'balanced,aware').split(','), STARTS = ['sword', 'spear', 'blades'];
PA.Balance.apply('test03');
const commit = require('child_process').execSync('git rev-parse --short HEAD').toString().trim();
function fightStats(st, run) {
  const sm = PA.Combat.summary(st); const en = Object.values(sm.enemies); const sum = (k) => en.reduce((a, e) => a + (e[k] || 0), 0);
  const hits = Object.values(sm.hits || {}).reduce((a, b) => a + b, 0); const killed = sum('killed') + sum('exploded');
  const byKey = {}; for (const k in sm.dmg) byKey[k] = sm.dmg[k].amount;
  return { status: st.status, t: Math.round(st.t * 10) / 10, taken: Math.round(sm.damageTaken), hits, hitsPerSec: st.t > 0 ? Math.round(hits / st.t * 100) / 100 : 0, dbaPct: killed ? Math.round(sum('diedBeforeAttack') / killed * 100) : 0, spawned: sum('spawned'), executed: sum('executed'), dmg: byKey, dmgTotal: sm.dmgTotal };
}
const A = [], B = [], D = [];
for (const pol of POLS) for (let i = 0; i < N; i++) { const seed = 100 + i;
  for (const start of STARTS) {
    // A. 첫 전투
    { const run = PA.Run.newRun(seed, start, 'trio', 'test03'); const s = PA.Sortie.start(run, 'd1c1'); const st = PA.Flow.makeEncounter(run, s); PA.Bot.runCombat(st, pol, { maxSec: 180 }); if (st.status === 'running') st.status = 'timeout'; A.push(Object.assign({ pol, seed, start }, fightStats(st, run))); }
    // B. 첫날 전체(점진: 숲 → 능선 → 남은 칸 휴식/추가 출격, 체력 30% 미만이면 휴식). 전투 중 레벨업은 봇 선택
    { const run = PA.Run.newRun(seed, start, 'trio', 'test03'); const g = run.growth; const rec = { pol, seed, start, fights: 0, wins: 0, losses: 0, rests: 0, t: 0, taken: 0, hits: 0, dba: 0, killed: 0, gold: 0, levelUps: 0, dmg: {} };
      let guard = 0; while (guard++ < 10 && run.day === 1 && run.phase === 'prep') {
        if (run.hp < PA.Run.build(run).hpMax * 0.3 && PA.Run.canRest(run)) { PA.Run.rest(run); rec.rests++; continue; }
        const cards = PA.Sortie.cardsFor(run).filter(c => PA.Sortie.canStart(run, c)); if (!cards.length) break; const s = PA.Sortie.start(run, cards[0].id);
        const st = PA.Flow.makeEncounter(run, s); PA.Bot.runCombat(st, pol, { maxSec: 180, onLevelUp: (st2) => { PA.Flow.resolveAll(run, { regionId: s.regionId }, (off) => PA.Bot.pickChoice(off, run.seed)); PA.Combat.rebuild(st2, PA.Run.build(run)); } }); if (st.status === 'running') st.status = 'timeout';
        const f = fightStats(st, run); rec.fights++; rec.t += f.t; rec.taken += f.taken; rec.hits += f.hits; rec.killed += f.spawned; rec.dba += Math.round(f.dbaPct / 100 * f.spawned); for (const k in f.dmg) rec.dmg[k] = (rec.dmg[k] || 0) + f.dmg[k];
        if (st.status === 'won') { rec.wins++; PA.Flow.settleVictory(run, s, st); PA.Flow.resolveAll(run, { regionId: s.regionId }, (off) => PA.Bot.pickChoice(off, run.seed)); if (s.event && !s.event.resolved) PA.Events.resolve(run, s, 'leave'); PA.Flow.returnHome(run, s); } else { rec.losses++; PA.Flow.settleDefeat(run, s, st); }
      }
      rec.gold = run.gold; rec.levelUps = g.level - 1; rec.hp = run.hp; rec.dbaPct = rec.killed ? Math.round(rec.dba / rec.killed * 100) : 0; rec.hitsPerSec = rec.t ? Math.round(rec.hits / rec.t * 100) / 100 : 0; B.push(rec); }
  }
}
// D. 첫 보스: run_sim 덤프(점진 전략, 시드 1~5)의 1단계 관문 빌드로 가시갈기 2400
for (const start of STARTS) { const p = path.join(__dirname, '..', 'docs', 'sim', 'v08', `dump_${start}.json`); if (!fs.existsSync(p)) continue; const dump = JSON.parse(fs.readFileSync(p, 'utf8')).filter(r => r.strategy === 'gradual');
  for (const pol of POLS) for (const r of dump) { const gb = r.gateBuilds.find(b => b.stage === 0); if (!gb) continue; const run = PA.Run.newRun(r.seed, start, 'trio', 'test03'); run.growth = gb.growth; run.equipment = gb.equipment; run.forge = gb.forge; run.hp = PA.Run.build(run).hpMax;
    const st = PA.Combat.create({ build: PA.Run.build(run), hp: run.hp, seed: PA.Run.bossSeed ? PA.Run.bossSeed(run) : r.seed * 31, boss: true, bossId: 'boss', bossHp: PA.Run.bossHp(run, 'boss'), arena: 'clearing', waves: [], run }); PA.Bot.runCombat(st, pol, { maxSec: 300 }); if (st.status === 'running') st.status = 'timeout';
    D.push(Object.assign({ pol, seed: r.seed, start, level: gb.level, build: gb.growth.weapons.map(w => w.id + w.level).join('+'), eq: Object.values(gb.equipment).filter(Boolean).length, forge: gb.forge }, fightStats(st, run))); } }
// ---- 표 ----
const W = { sword: '검격', spear: '관통창', blades: '회전 칼날' }; const PN = (p) => PA.Bot.POLICIES[p].name;
const avg = (l, f) => l.length ? Math.round(l.reduce((a, r) => a + f(r), 0) / l.length * 10) / 10 : '-';
const dmgText = (l) => { const s = {}; for (const r of l) for (const k in r.dmg) s[k] = (s[k] || 0) + r.dmg[k]; const tot = Object.values(s).reduce((a, b) => a + b, 0) || 1; return Object.keys(s).sort((a, b) => s[b] - s[a]).slice(0, 4).map(k => `${PA.Stats.classify(k).name} ${Math.round(s[k] / tot * 100)}%`).join(', '); };
let md = `# 시작 자동기술 3종 집중 비교 (v${PA.VERSION}, 커밋 ${commit}, 밸런스 test03, 시드 ${N}개 짝지음, 정책 ${POLS.map(PN).join(' / ')})\n\n봇 결과는 정책 비교용이며 사람 승률·재미 승인이 아니다. '기술 특성 이해' 정책은 균형 정책에 거리 규칙만 더한 것(회전 칼날: 살 중간, 관통창: 근접 약화 밖).\n`;
md += `\n## A. 첫 전투(1일차 새벽 근교 숲, Lv1, 개조·장비 없음)\n\n| 정책 | 자동기술 | 승/패/초과 | 평균 초 | 받은 피해 | 명중/초 | 공격 전 사망% | 적 공격 실행/전투 | 피해 기여 |\n|---|---|---|---|---|---|---|---|---|\n`;
for (const pol of POLS) for (const start of STARTS) { const l = A.filter(r => r.pol === pol && r.start === start); md += `| ${PN(pol)} | ${W[start]} | ${l.filter(r => r.status === 'won').length}/${l.filter(r => r.status === 'lost').length}/${l.filter(r => r.status === 'timeout').length} | ${avg(l, r => r.t)} | ${avg(l, r => r.taken)} | ${avg(l, r => r.hitsPerSec)} | ${avg(l, r => r.dbaPct)} | ${avg(l, r => r.executed)} | ${dmgText(l)} |\n`; }
md += `\n### A. 시드별 짝 비교(균형 정책): 전투 초 / 받은 피해\n\n| 시드 | 검격 | 관통창 | 회전 칼날 |\n|---|---|---|---|\n`;
for (let i = 0; i < N; i++) { const seed = 100 + i; const c = (st) => { const r = A.find(x => x.pol === POLS[0] && x.seed === seed && x.start === st); return r ? `${r.status === 'won' ? '' : r.status + ' '}${r.t}s / ${r.taken}` : '-'; }; md += `| ${seed} | ${c('sword')} | ${c('spear')} | ${c('blades')} |\n`; }
md += `\n## B. 첫날 전체(점진: 오늘의 장소 순서, 체력 30% 미만이면 휴식, 봇 성장 선택)\n\n| 정책 | 자동기술 | 전투 | 승/패 | 휴식 | 레벨업 | 전투 초 합 | 받은 피해 합 | 명중/초 | 공격 전 사망% | 정산 금화 | 하루 끝 체력 | 피해 기여 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
for (const pol of POLS) for (const start of STARTS) { const l = B.filter(r => r.pol === pol && r.start === start); md += `| ${PN(pol)} | ${W[start]} | ${avg(l, r => r.fights)} | ${avg(l, r => r.wins)}/${avg(l, r => r.losses)} | ${avg(l, r => r.rests)} | ${avg(l, r => r.levelUps)} | ${avg(l, r => r.t)} | ${avg(l, r => r.taken)} | ${avg(l, r => r.hitsPerSec)} | ${avg(l, r => r.dbaPct)} | ${avg(l, r => r.gold)} | ${avg(l, r => r.hp)} | ${dmgText(l)} |\n`; }
if (D.length) { md += `\n## D. 첫 보스(가시갈기 2400): 점진 전략 3일차 관문 빌드(run_sim 덤프, 시드 1~5)\n\n| 정책 | 자동기술 | 빌드(평균 Lv·장비·강화) | 승/패/초과 | 평균 초(승리) | 받은 피해 | 명중/초 | 보스 공격 실행/전투 | 피해 기여 |\n|---|---|---|---|---|---|---|---|---|\n`;
  for (const pol of POLS) for (const start of STARTS) { const l = D.filter(r => r.pol === pol && r.start === start); if (!l.length) continue; const w = l.filter(r => r.status === 'won'); md += `| ${PN(pol)} | ${W[start]} | Lv${avg(l, r => r.level)} · 장비 ${avg(l, r => r.eq)} · 강화 ${avg(l, r => r.forge)} · ${l[0].build} | ${w.length}/${l.filter(r => r.status === 'lost').length}/${l.filter(r => r.status === 'timeout').length} | ${avg(w, r => r.t)} | ${avg(l, r => r.taken)} | ${avg(l, r => r.hitsPerSec)} | ${avg(l, r => r.executed)} | ${dmgText(l)} |\n`; } }
md += `\n같은 선택 횟수(C)의 짝 비교는 docs/sim/v08/PAIRED_E.md.\n`;
fs.writeFileSync(path.join(__dirname, '..', 'docs', 'sim', 'v08', 'START_COMPARE.md'), md); fs.writeFileSync(path.join(__dirname, '..', 'docs', 'sim', 'v08', 'start_compare.json'), JSON.stringify({ A, B, D }, null, 1));
console.log(md);
