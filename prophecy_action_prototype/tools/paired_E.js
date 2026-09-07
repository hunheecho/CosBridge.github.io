// §2-C 같은 선택 횟수(7선택) 비교를 raw_E에서 시드·적·체력·봇 조건으로 짝지어 계산한다. 사용: node tools/paired_E.js → docs/sim/v08/PAIRED_E.md
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const raw = zlib.gunzipSync(fs.readFileSync(path.join(__dirname, '..', 'docs', 'sim', 'raw_E.jsonl.gz'))).toString().split('\n').filter(Boolean).map(l => JSON.parse(l));
const key = (r) => `${r.enemy}|${r.hp}|${r.seed}|${r.bot}`; const by = {}; for (const r of raw) { (by[key(r)] = by[key(r)] || {})[r.build] = r; }
const V = ['cmp_sword', 'cmp_spear', 'cmp_blades'], N = { cmp_sword: '검격', cmp_spear: '관통창', cmp_blades: '회전 칼날' };
const groups = {}; for (const k in by) { const g = by[k]; if (!V.every(v => g[v])) continue; const [enemy, hp, seed, bot] = k.split('|'); (groups[bot] = groups[bot] || []).push({ enemy, hp, seed, g }); }
let md = '# 같은 선택 횟수(7선택) 짝 비교 — raw_E (지역 5·조합 4·보스 3·정지 보스, 체력 ×1·×2, 시드 5)\n\n각 칸은 같은 (적, 체력, 시드, 봇) 조건에서의 결과다. 승리 시간 비교는 셋 다 이긴 짝만 센다.\n';
for (const bot in groups) { const L = groups[bot]; const wins = (v) => L.filter(x => x.g[v].status === 'won').length; const both = L.filter(x => V.every(v => x.g[v].status === 'won'));
  const avg = (v, f, l) => l.length ? Math.round(l.reduce((a, x) => a + f(x.g[v]), 0) / l.length * 10) / 10 : '-';
  md += `\n## 봇 ${bot} (짝 ${L.length}개, 셋 다 승리 ${both.length})\n\n| 자동기술 | 승리 | 셋 다 승리한 짝의 평균 초 | 받은 피해(전체) | 공격 전 사망%(전체) | 준 피해/초 |\n|---|---|---|---|---|---|\n`;
  for (const v of V) { const hps = (r) => r.elapsed > 0 ? Object.values(r.hits || {}).reduce((a, b) => a + b, 0) / r.elapsed : 0; const dba = (r) => (r.killed + (r.exploded || 0)) ? r.dba / (r.killed + (r.exploded || 0)) * 100 : 0; md += `| ${N[v]} | ${wins(v)}/${L.length} | ${avg(v, r => r.elapsed, both)} | ${avg(v, r => r.taken, L)} | ${avg(v, r => dba(r), L)} | ${avg(v, r => r.dpsDealt || 0, L)} |\n`; }
  const head = {}; for (const x of L) { const best = V.slice().sort((a, b) => (x.g[a].status === 'won' ? x.g[a].elapsed : 1e9) - (x.g[b].status === 'won' ? x.g[b].elapsed : 1e9))[0]; head[best] = (head[best] || 0) + 1; } md += `\n가장 빨리 이긴 짝 수: ${V.map(v => `${N[v]} ${head[v] || 0}`).join(' · ')}\n`;
}
fs.writeFileSync(path.join(__dirname, '..', 'docs', 'sim', 'v08', 'PAIRED_E.md'), md); console.log(md);
