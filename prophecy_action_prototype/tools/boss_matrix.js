// §3 보스 맞으면서 공격하는 시험. 보스 3 × 행동 4(자동 공격만 / Q·E만 / 기본 회피 / 숙련 회피) × 빌드(관문 정상 성장·3일차 중단 최종·같은 투자 직접/지속/방어).
// 기록: 승패·시간, 받은 유효 피해, 흡수·회복, 보스 공격 시도/명중, 패턴 실행, 출처별 피해, Q 사용. 사용: node tools/boss_matrix.js [--seeds 3] → docs/sim/v08/BOSS_MATRIX.md
const fs = require('fs'), path = require('path'); const { load } = require('../test/load'); const PA = load(); PA.Balance.apply('test03');
const args = process.argv.slice(2); const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; }; const N = parseInt(opt('seeds', '3'), 10);
const commit = require('child_process').execSync('git rev-parse --short HEAD').toString().trim();
const dir = path.join(__dirname, '..', 'docs', 'sim', 'v08'); const dumpS = JSON.parse(fs.readFileSync(path.join(dir, 'dump_sword.json'), 'utf8')).filter(r => r.strategy === 'gradual'); const dumpStop = JSON.parse(fs.readFileSync(path.join(dir, 'dump_stop3.json'), 'utf8'));
const BEH = { idle: '자동 공격만(이동·회피·Q/E 없음)', still: '제자리 Q/E', aggressive: '기본 이동·회피', balanced: '숙련 회피 봇' };
const bosses = ['boss', 'guardian', 'eater'];
function mkRun(seed, b) { const run = PA.Run.newRun(seed, b.growth.weapons[0].id, 'trio', 'test03'); run.growth = JSON.parse(JSON.stringify(b.growth)); if (b.equipment) run.equipment = Object.assign({ weapon: null, armor: null, shield: null }, b.equipment); run.forge = b.forge || 0; run.hp = PA.Run.build(run).hpMax; return run; }
function builds(bossId, stage) {
  const out = [];
  for (const r of dumpS.slice(0, N)) { const gb = r.gateBuilds.find(x => x.stage === stage); if (gb) out.push({ id: `normal_s${r.seed}`, name: `관문 정상 성장(시드 ${r.seed}, Lv${gb.level})`, growth: gb.growth, equipment: gb.equipment, forge: gb.forge, cat: '정상 성장' }); }
  if (bossId === 'eater') for (const r of dumpStop.slice(0, N)) { const gb = r.gateBuilds.find(x => x.stage === 2); if (gb) out.push({ id: `stop3_s${r.seed}`, name: `3일차 성장 중단 최종(시드 ${r.seed}, Lv${gb.level})`, growth: gb.growth, equipment: gb.equipment, forge: gb.forge, cat: '3일차 중단' }); }
  for (const id of ['inv_direct', 'inv_dot', 'inv_def']) { const p = PA.LAB.BUILDS[id]; out.push({ id, name: p.name, growth: PA.Lab.growthFromPreset(p), cat: '같은 투자' }); }
  return out;
}
const rows = [];
for (const bossId of bosses) { const stage = bosses.indexOf(bossId);
  for (const b of builds(bossId, stage)) for (const beh of Object.keys(BEH)) { const res = [];
    for (let i = 0; i < N; i++) { const run = mkRun(11 + i * 7, b); const st = PA.Combat.create({ build: PA.Run.build(run), hp: run.hp, seed: 11 + i * 7, boss: true, bossId, bossHp: PA.Run.bossHp(run, bossId), arena: 'clearing', waves: [], run }); PA.Bot.runCombat(st, beh, { maxSec: 300 }); if (st.status === 'running') st.status = 'timeout';
      const sm = PA.Combat.summary(st); const en = sm.enemies; const bossE = Object.keys(en).filter(k => /boss|guardian|eater/.test(k)); const attempts = bossE.reduce((a, k) => a + (en[k].executed || 0), 0); const hitsOn = Object.keys(sm.takenHits || {}).filter(k => /boss|sweep|dash|pounce|shock|wide|mark|lane|slam|beam/.test(k)).reduce((a, k) => a + sm.takenHits[k], 0);
      const heal = (st.stats.healed || 0); const bySrc = {}; for (const k in sm.dmg) bySrc[k] = sm.dmg[k].amount;
      res.push({ status: st.status, t: st.t, taken: sm.damageTaken, absorbed: sm.absorbed, heal, attempts, hitsOn, patterns: sm.patterns || {}, q: sm.specialUses, e: sm.eUses, bd: st.stats.bossDamage, bySrc }); }
    const wins = res.filter(r => r.status === 'won'); const avg = (l, f) => l.length ? Math.round(l.reduce((a, r) => a + f(r), 0) / l.length) : '-'; const pat = {}; for (const r of res) for (const k in r.patterns) pat[k] = (pat[k] || 0) + r.patterns[k]; const src = {}; for (const r of res) for (const k in r.bySrc) src[k] = (src[k] || 0) + r.bySrc[k]; const tot = Object.values(src).reduce((a, b) => a + b, 0) || 1;
    rows.push({ bossId, build: b, beh, n: res.length, wins: wins.length, t: avg(wins, r => r.t), taken: avg(res, r => r.taken), absorbed: avg(res, r => r.absorbed), heal: avg(res, r => r.heal), attempts: avg(res, r => r.attempts), hitsOn: avg(res, r => r.hitsOn), q: avg(res, r => r.q), bd: avg(res, r => r.bd), pat: Object.keys(pat).sort().map(k => `${k} ${Math.round(pat[k] / res.length * 10) / 10}`).join(', '), src: Object.keys(src).sort((a, c) => src[c] - src[a]).slice(0, 3).map(k => `${PA.Stats.classify(k).name} ${Math.round(src[k] / tot * 100)}%`).join(', ') });
    console.log(bossId, b.id, beh, `${wins.length}/${res.length}`); }
}
let md = `# 보스 맞으면서 공격하는 시험 (v${PA.VERSION}, 커밋 ${commit}, test03, 보스 2400/5000/7000, 시드 ${N})\n\n행동: ${Object.entries(BEH).map(([k, v]) => `${k}=${v}`).join(' · ')}. 봇 결과는 사람 승률이 아니다. "정상 성장" 빌드는 run_sim(점진 전략) 덤프의 관문 시점 빌드(장비·강화 포함).\n`;
for (const bossId of bosses) { md += `\n## ${PA.BOSS_DEFS[bossId].name}\n\n| 빌드 | 행동 | 승리 | 평균 초(승) | 받은 피해 | 흡수 | 회복 | 보스 공격 실행 | 명중 | Q | 보스에게 준 피해 | 패턴 실행(평균) | 피해 출처 |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n`; for (const r of rows.filter(x => x.bossId === bossId)) md += `| ${r.build.name} | ${BEH[r.beh]} | ${r.wins}/${r.n} | ${r.t} | ${r.taken} | ${r.absorbed} | ${r.heal} | ${r.attempts} | ${r.hitsOn} | ${r.q} | ${r.bd} | ${r.pat} | ${r.src} |\n`; }
md += `\n## 읽는 법\n- "자동 공격만"과 "제자리 Q/E"의 차이 = Q/E가 보스 행동·생존에 미친 영향(같은 위치·같은 빌드).\n- 보스 공격 실행 대비 명중이 0에 가까우면 정지한 플레이어를 못 맞히는 것이므로 재현·수정 대상.\n- 제자리 행동이 이기는 칸은 "서서 버티며 이김"의 신호. 원인은 체력 부족으로 단정하지 않는다(공격 빈도·명중률·틈을 함께 본다).\n`;
fs.writeFileSync(path.join(dir, 'BOSS_MATRIX.md'), md); fs.writeFileSync(path.join(dir, 'boss_matrix.json'), JSON.stringify(rows, null, 1)); console.log('wrote BOSS_MATRIX.md');
