// 헤드리스 보스전 길이 측정(정책 봇). 사용: node tools/boss_sim.js
const { load } = require('../test/load'); const PA = load(); const { runBossFight } = require('../test/bot');
const { runWith } = require('../test/load');
const builds = { // v0.5 성장 표기
  '검 Lv1 (시작 상태)': { growth: { weapons: [{ id: 'sword', level: 1 }] } },
  '검 Lv3 + 강화2 + 숙련2': { gear: { upgrade: 2 }, growth: { weapons: [{ id: 'sword', level: 3 }], passives: { mastery: 2 } } },
  '감속장+회전 칼날+정지된 칼날+시간 저축': { gear: { upgrade: 1 }, growth: { weapons: [{ id: 'sword', level: 2 }, { id: 'blades', level: 3, mods: ['dual'] }], commons: { stasis: 1, saving: 1, wide: 1 } } },
  '관통창+얼음 파편+서리 수정': { gear: { upgrade: 1 }, growth: { weapons: [{ id: 'spear', level: 3, mods: ['returning'] }, { id: 'frost', level: 2, mods: ['fan'] }], commons: { frost: 1 }, passives: { haste: 1 } } },
  '불씨 정령+잔불+불꽃 파열': { gear: { upgrade: 1 }, growth: { weapons: [{ id: 'sword', level: 2 }, { id: 'ember', level: 3, mods: ['trail', 'reignite'] }], commons: { ember: 1, flare: 1, wide: 2 } } },
  '완성(관통창5 귀환+표식, 회전4 이중, 구체3 분기, 숙련3, 가속2, 목걸이, 낙뢰)': { gear: { upgrade: 3, acc: 'fang_necklace' }, growth: { weapons: [{ id: 'spear', level: 5, mods: ['returning', 'brand'] }, { id: 'blades', level: 4, mods: ['dual'] }, { id: 'orb', level: 3, mods: ['fork'] }], commons: { stasis: 1, saving: 1, wide: 2 }, passives: { mastery: 3, haste: 2 }, e: { id: 'strike', level: 2 } } },
};
const seeds = (process.argv[2] || '5,11,23').split(',').map(Number);
for (const [name, b] of Object.entries(builds)) {
  const run = runWith(PA, b); if (b.gear && b.gear.acc) run.owned.push(b.gear.acc);
  const res = [];
  for (const seed of seeds) { const st = runBossFight(PA, run, seed, 400); res.push(`${st.status}@${st.t.toFixed(0)}s hp${Math.round(st.player.hp)} 보스${Math.round(st.boss.hp)} ${st.boss.phase}단계 늑대${st.stats.kills} Q${st.stats.specialUses}`); }
  console.log(name.padEnd(34), res.join(' | '));
}
