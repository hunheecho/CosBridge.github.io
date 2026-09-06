// 헤드리스 보스전 길이 측정(정책 봇). 사용: node tools/boss_sim.js
const { load } = require('../test/load'); const PA = load(); const { runBossFight } = require('../test/bot');
const builds = {
  '기본(강화0, 증강 없음)': { gear: {}, aug: {} },
  '기본검+강화2+예리한 날2': { gear: { upgrade: 2 }, aug: { sharp: 2 } },
  '감속장+회전+정지된 칼날+시간 저축': { gear: { upgrade: 1 }, aug: { spin: 1, stasis: 1, saving: 1, wide: 1 } },
  '관통검+얼음 파편+빠른 손': { gear: { weapon: 'pierce', upgrade: 1 }, aug: { frost: 1, quick: 1 } },
  '잔불 걸음+불꽃 파열+넓은 검격2': { gear: { upgrade: 1 }, aug: { ember: 1, flare: 1, wide: 2 } },
  '완성(관통+3, 예리3, 빠른손2, 회전, 정지, 저축, 목걸이)': { gear: { weapon: 'pierce', upgrade: 3, acc: 'fang_necklace' }, aug: { sharp: 3, quick: 2, spin: 1, stasis: 1, saving: 1 } },
};
const seeds = (process.argv[2] || '5,11,23').split(',').map(Number);
for (const [name, b] of Object.entries(builds)) {
  const run = PA.Run.newRun(1); Object.assign(run.gear, b.gear); if (b.gear.acc) run.owned.push(b.gear.acc); run.augments = b.aug;
  const res = [];
  for (const seed of seeds) { const st = runBossFight(PA, run, seed, 400); res.push(`${st.status}@${st.t.toFixed(0)}s hp${Math.round(st.player.hp)} 보스${Math.round(st.boss.hp)} ${st.boss.phase}단계 늑대${st.stats.kills} Q${st.stats.specialUses}`); }
  console.log(name.padEnd(34), res.join(' | '));
}
