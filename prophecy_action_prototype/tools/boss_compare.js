// v0.8 보스 비교(헤드리스): 보스 3 × 조작 정책 4(제자리 Q/E만 · 기본 회피 · 균형 봇 · 생존 봇) × 빌드 4(시작 상태 · 3일차 중단(×0.3) · 완전 준비(×0.3, 장비·강화 포함) · 완전 준비 장비 없음)
// 목적: 표준 빌드가 제자리에서 버티며 이기면 문제(보스 압박 부족). 사용: node tools/boss_compare.js [--seeds 5] → docs/sim/BOSS_v08.md
const path = require('path'), fs = require('fs');
const { load } = require('../test/load'); const PA = load();
const args = process.argv.slice(2); const nSeeds = parseInt((args.indexOf('--seeds') >= 0 && args[args.indexOf('--seeds') + 1]) || '5', 10);
PA.Balance.apply('test03');
// 대표 빌드(경험치 ×0.3 회차 시뮬레이션 COMPARE_v072: 3일차까지 약 5회, 완주 약 14회 레벨업). 확정값이 아닌 비교용 후보
const BUILDS = {
  start:   { name: '시작 상태(Lv1)', growth: { weapons: [{ id: 'sword', level: 1, mods: [] }] } },
  stop3:   { name: '3일차 중단(5선택)', growth: { weapons: [{ id: 'sword', level: 3, mods: ['cross'] }], commons: { wide: 1 }, passives: { mastery: 1 }, q: { level: 2 } } },
  full:    { name: '완전 준비(14선택 + 장비 3 + 강화 3)', growth: { weapons: [{ id: 'sword', level: 5, mods: ['cross', 'crescent'] }, { id: 'blades', level: 3, mods: ['dual'] }], commons: { wide: 2, frost: 1 }, passives: { mastery: 2, haste: 1 }, q: { level: 3 }, e: { id: 'strike', level: 2 } }, equipment: ['hunter_sword', 'vitality_coat', 'iron_shield'], forge: 3 },
  full_ne: { name: '완전 준비(장비·강화 없음)', growth: { weapons: [{ id: 'sword', level: 5, mods: ['cross', 'crescent'] }, { id: 'blades', level: 3, mods: ['dual'] }], commons: { wide: 2, frost: 1 }, passives: { mastery: 2, haste: 1 }, q: { level: 3 }, e: { id: 'strike', level: 2 } } },
};
const POL = { still: '제자리(Q/E만)', aggressive: '기본 회피(확정 예고만)', balanced: '균형 봇', survival: '생존 봇' };
function mkRun(b) { const run = PA.Run.newRun(7, b.growth.weapons[0].id, 'trio', 'test03'); run.growth = PA.Lab.growthFromPreset(b); for (const id of (b.equipment || [])) { run.bag.push(id); PA.Run.equipItem(run, id); } run.forge = b.forge || 0; run.hp = PA.Run.build(run).hpMax; return run; }
const rows = []; const md = [`# v0.8 보스 비교 (헤드리스 정책 봇 · ${nSeeds}시드 · 보스 체력 세트 hi 2400/5000/7000 · 밸런스 test03)\n`, `커밋: ${require('child_process').execSync('git rev-parse --short HEAD').toString().trim()} · 빌드는 비교용 대표값(확정 아님). 봇 결과는 사람 승률이 아니다.\n`];
md.push('| 보스 | 빌드 | 정책 | 승리 | 평균 시간(승리) | 받은 피해(평균) | Q 사용 | 보스에게 준 피해(평균) | 패턴 실행/전투 |', '|---|---|---|---|---|---|---|---|---|');
for (const bossId of ['boss', 'guardian', 'eater']) for (const [bid, b] of Object.entries(BUILDS)) for (const pol of Object.keys(POL)) {
  const res = [];
  for (let s = 0; s < nSeeds; s++) { const run = mkRun(b); const st = PA.Combat.create({ build: PA.Run.build(run), hp: PA.Run.build(run).hpMax, seed: 11 + s * 7, boss: true, bossId, bossHp: PA.Run.bossHp(run, bossId), arena: 'clearing', waves: [], run }); PA.Bot.runCombat(st, pol, { maxSec: 300 }); const M = st.metrics; const exec = Object.values(M.enemies || {}).reduce((a, e) => a + (e.executed || 0), 0); res.push({ won: st.status === 'won', t: st.t, taken: st.stats.damageTaken, q: st.stats.specialUses, bd: st.stats.bossDamage, exec, status: st.status }); }
  const wins = res.filter(r => r.won); const avg = (l, f) => l.length ? Math.round(l.reduce((a, r) => a + f(r), 0) / l.length) : '-';
  rows.push({ bossId, build: bid, pol, wins: wins.length, n: res.length, t: avg(wins, r => r.t), taken: avg(res, r => r.taken), q: avg(res, r => r.q), bd: avg(res, r => r.bd), exec: avg(res, r => r.exec), statuses: res.map(r => r.status).join(',') });
  md.push(`| ${PA.BOSS_DEFS[bossId].name} | ${b.name} | ${POL[pol]} | ${wins.length}/${res.length} | ${avg(wins, r => r.t)}초 | ${avg(res, r => r.taken)} | ${avg(res, r => r.q)} | ${avg(res, r => r.bd)} | ${avg(res, r => r.exec)} |`);
  console.log(bossId, bid, pol, `${wins.length}/${res.length}`, avg(wins, r => r.t) + 's');
}
md.push('', '## 읽는 법', '- 제자리(Q/E만) 정책이 이기는 칸은 "서서 버티며 이길 수 있음"이므로 보스 압박 부족의 신호다. 시작 상태·3일차 중단 빌드가 제자리로 지고, 완전 준비가 회피 봇으로 이기는 것이 목표 방향.', '- 패턴 실행/전투 = 보스가 실제로 실행한 공격 수(예고만 하고 취소된 것 제외).', '- 수치는 시험값. 사람 플레이 승률·재미 승인이 아니다.');
fs.writeFileSync(path.join(__dirname, '..', 'docs', 'sim', 'BOSS_v08.md'), md.join('\n') + '\n'); fs.writeFileSync(path.join(__dirname, '..', 'docs', 'sim', 'boss_v08.json'), JSON.stringify(rows, null, 1));
console.log('wrote docs/sim/BOSS_v08.md');
