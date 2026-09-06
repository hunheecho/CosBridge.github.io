// 시뮬레이션 원시 결과(docs/sim/raw_<suite>.jsonl.gz) 집계 → docs/sim/report_<suite>.md + summary_<suite>.json
// 사용: node tools/lab_report.js A|B|C [--in docs/sim/raw_A.jsonl.gz]
// 주의: 승리한 전투만의 평균 시간에는 생존자 편향이 있다. 시간 초과는 실패와 별도로 센다. 길찾기 의심 = 시간 초과이면서 적과 300 이상 떨어져 있던 시간 비율 50% 이상.
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const args = process.argv.slice(2), suite = (args[0] || 'A').toUpperCase();
const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const dir = path.join(__dirname, '..', 'docs', 'sim'), inPath = opt('in', path.join(dir, `raw_${suite}.jsonl.gz`));
const rows = zlib.gunzipSync(fs.readFileSync(inPath)).toString('utf8').split('\n').filter(Boolean).map(l => JSON.parse(l)).filter(r => !r.error);
const NAMES = { 'dummy:boss': '정지 보스', early_sword: '초반 검', early_spear: '초반 창', early_blades: '초반 칼날', mid_melee: '중간 근접', mid_ranged: '중간 원거리', slowfield: '감속장', dot: '불길', late_multi: '후반 다중', late_hammer: '후반 망치', aggressive: '공격', balanced: '균형', survival: '생존' };
const nm = (k) => NAMES[k] || k.replace(/^(region|solo|combo):/, '');
const pct = (a, b) => b ? Math.round(a / b * 100) : 0, r1 = (x) => Math.round(x * 10) / 10;
function agg(list) {
  const n = list.length, won = list.filter(r => r.status === 'won'), lost = list.filter(r => r.status === 'lost'), to = list.filter(r => r.status === 'timeout');
  const stuck = to.filter(r => (r.farFrac || 0) >= 0.5);
  const avg = (arr, f) => arr.length ? arr.reduce((a, r) => a + f(r), 0) / arr.length : NaN;
  const med = (arr, f) => { if (!arr.length) return NaN; const v = arr.map(f).sort((a, b) => a - b); return v[Math.floor(v.length / 2)]; };
  const killed = list.reduce((a, r) => a + r.killed + (r.exploded || 0), 0), dba = list.reduce((a, r) => a + r.dba, 0), spawned = list.reduce((a, r) => a + r.spawned, 0), prep = list.reduce((a, r) => a + r.prepared, 0), exec = list.reduce((a, r) => a + r.executed, 0);
  return { n, win: pct(won.length, n), loss: pct(lost.length, n), timeout: pct(to.length, n), stuck: stuck.length, tWon: r1(avg(won, r => r.elapsed)), tWonMed: r1(med(won, r => r.elapsed)), tAll: r1(avg(list, r => r.elapsed)), taken: r1(avg(list, r => r.taken)), takenMed: r1(med(list, r => r.taken)), dba: pct(dba, killed), execPerSpawn: spawned ? r1(exec / spawned) : 0, prepPerSpawn: spawned ? r1(prep / spawned) : 0, killedRate: pct(killed, spawned) };
}
function group(list, keyFn) { const g = new Map(); for (const r of list) { const k = keyFn(r); if (!g.has(k)) g.set(k, []); g.get(k).push(r); } return g; }
const cols = ['n', 'win', 'loss', 'timeout', 'stuck', 'tWon', 'tWonMed', 'taken', 'takenMed', 'dba', 'prepPerSpawn', 'execPerSpawn'];
const colNames = { n: '전투', win: '승리%', loss: '패배%', timeout: '시간초과%', stuck: '길찾기 의심', tWon: '승리 평균초*', tWonMed: '승리 중앙초*', taken: '받은 피해', takenMed: '피해 중앙', dba: '공격 전 사망%', prepPerSpawn: '준비/등장', execPerSpawn: '실행/등장' };
function table(title, g, labelName) { const keys = [...g.keys()]; let s = `\n### ${title}\n\n| ${labelName} | ${cols.map(c => colNames[c]).join(' | ')} |\n|---|${cols.map(() => '---').join('|')}|\n`; for (const k of keys) { const a = agg(g.get(k)); s += `| ${k} | ${cols.map(c => isNaN(a[c]) ? '—' : a[c]).join(' | ')} |\n`; } return s; }
const hpOf = (r) => '×' + r.hp;
let md = `# 시뮬레이션 요약 ${suite} (v${rows[0] ? rows[0].version : '?'})\n\n원시 결과: \`docs/sim/raw_${suite}.jsonl.gz\` (${rows.length}전) · 집계: \`node tools/lab_report.js ${suite}\`\n\n봇 결과는 정책 비교용 관측이며 사람의 승률·재미·적정 체력에 대한 승인이 아니다. 전투 중 성장 선택은 적용하지 않았다(빌드 고정). *승리한 전투만의 평균/중앙 시간에는 생존자 편향이 있다. 시간 초과(120초)는 패배와 별도이며, "길찾기 의심"은 시간 초과 중 적과 300 이상 떨어져 있던 시간이 절반 이상인 전투 수다.\n`;
const summary = {};
if (suite === 'A') {
  md += table('체력 배율별(전체)', group(rows, hpOf), '체력');
  const byBuild = group(rows, r => nm(r.build)); md += '\n## 빌드별\n'; for (const [b, list] of byBuild) md += table(`빌드 ${b}`, group(list, hpOf), '체력');
  const byRegion = group(rows, r => nm(r.enemy)); md += '\n## 지역별\n'; for (const [b, list] of byRegion) md += table(`지역 ${b}`, group(list, hpOf), '체력');
  md += '\n## 봇 정책별\n'; for (const [b, list] of group(rows, r => nm(r.bot))) md += table(`봇 ${b}`, group(list, hpOf), '체력');
  // 질문 1: 공격도 못 하고 죽는 조건(빌드×지역×체력, 공격 전 사망 ≥ 70%)
  const cells = group(rows, r => `${nm(r.build)} | ${nm(r.enemy)} | ×${r.hp}`);
  const q1 = [...cells].map(([k, l]) => [k, agg(l)]).filter(([k, a]) => a.dba >= 70).sort((x, y) => y[1].dba - x[1].dba);
  md += `\n## Q1. 적이 공격도 못 하고 죽는 조건(공격 전 사망 ≥ 70%, ${q1.length}개 조건)\n\n| 빌드 | 지역 | 체력 | 공격 전 사망% | 실행/등장 | 승리 평균초* |\n|---|---|---|---|---|---|\n`;
  for (const [k, a] of q1.slice(0, 40)) md += `| ${k} | ${a.dba} | ${a.execPerSpawn} | ${a.tWon} |\n`;
  // 질문 2: 체력만 높아져 시간이 과도(승리 시간이 ×1 대비 2.5배 이상이거나 60초 초과, 또는 시간 초과 발생)
  md += `\n## Q2. 체력만 높아져 전투 시간이 과도하게 늘어나는 조건\n\n| 빌드 | 지역 | ×1 승리초 | 체력 | 승리초 | 배수 | 시간초과% | 공격 전 사망% |\n|---|---|---|---|---|---|---|---|\n`;
  const q2 = [];
  for (const [b, bl] of group(rows, r => nm(r.build))) for (const [reg, rl] of group(bl, r => nm(r.enemy))) { const base = agg(rl.filter(r => r.hp === 1)); for (const [hp, hl] of group(rl, r => r.hp)) { if (hp === 1) continue; const a = agg(hl); const mult = base.tWon ? a.tWon / base.tWon : NaN; if ((mult >= 2.5) || a.tWon > 60 || a.timeout >= 20) q2.push([b, reg, base.tWon, hp, a.tWon, r1(mult), a.timeout, a.dba]); } }
  q2.sort((x, y) => y[3] - x[3] || y[4] - x[4]); for (const row of q2.slice(0, 60)) md += `| ${row.join(' | ')} |\n`;
  // 질문 4: 무기 조합 극단(체력 ×2·×3 기준 빌드별 승률·피해 범위)
  md += `\n## Q4. 빌드 간 극단(체력 ×2, ×3)\n\n| 빌드 | 체력 | 승리% | 받은 피해 | 공격 전 사망% | 가장 어려운 지역(승리%) | 가장 쉬운 지역(승리%) |\n|---|---|---|---|---|---|---|\n`;
  for (const hp of [2, 3]) for (const [b, bl] of group(rows.filter(r => r.hp === hp), r => nm(r.build))) { const a = agg(bl); const regs = [...group(bl, r => nm(r.enemy))].map(([k, l]) => [k, agg(l).win]).sort((x, y) => x[1] - y[1]); md += `| ${b} | ×${hp} | ${a.win} | ${a.taken} | ${a.dba} | ${regs[0][0]} (${regs[0][1]}) | ${regs[regs.length - 1][0]} (${regs[regs.length - 1][1]}) |\n`; }
  summary.byHp = Object.fromEntries([...group(rows, hpOf)].map(([k, l]) => [k, agg(l)])); summary.q1 = q1.map(([k, a]) => ({ cond: k, dba: a.dba })); summary.q2 = q2;
}
if (suite === 'B') {
  const byEnemy = group(rows, r => nm(r.enemy));
  md += '\n## 적별 × 체력 배율(모든 빌드·봇)\n'; for (const [e, l] of byEnemy) md += table(`${e}`, group(l, r => hpOf(r) + (r.arena !== 'forest' ? ' ' + r.arena : '')), '체력·지형');
  md += '\n## 적별 × 빌드(체력 ×2)\n\n| 적 | 빌드 | 전투 | 승리% | 시간초과% | 받은 피해 | 공격 전 사망% | 실행/등장 |\n|---|---|---|---|---|---|---|---|\n';
  for (const [e, l] of byEnemy) for (const [b, bl] of group(l.filter(r => r.hp === 2), r => nm(r.build))) { const a = agg(bl); md += `| ${e} | ${b} | ${a.n} | ${a.win} | ${a.timeout} | ${a.taken} | ${a.dba} | ${a.execPerSpawn} |\n`; }
  md += '\n## 적별 × 봇(체력 ×2)\n\n| 적 | 봇 | 승리% | 시간초과% | 길찾기 의심 | 받은 피해 |\n|---|---|---|---|---|---|\n';
  for (const [e, l] of byEnemy) for (const [b, bl] of group(l.filter(r => r.hp === 2), r => nm(r.bot))) { const a = agg(bl); md += `| ${e} | ${b} | ${a.win} | ${a.timeout} | ${a.stuck} | ${a.taken} |\n`; }
  const heals = rows.filter(r => r.enemy === 'solo:shaman'); if (heals.length) md += `\n주술사(늑대 2 동반): 치료 ${heals.reduce((a, r) => a + (r.heals || 0), 0)}회 / 방해 ${heals.reduce((a, r) => a + (r.interrupts || 0), 0)}회 (${heals.length}전)\n`;
  summary.byEnemyHp = Object.fromEntries([...byEnemy].map(([e, l]) => [e, Object.fromEntries([...group(l, hpOf)].map(([k, x]) => [k, agg(x)]))]));
}
if (suite === 'C') {
  const byCombo = group(rows, r => nm(r.enemy));
  md += '\n## 조합별 × 체력 배율(모든 빌드·봇)\n'; for (const [c, l] of byCombo) md += table(`${c}`, group(l, hpOf), '체력');
  md += '\n## 조합별 × 빌드(체력 ×2)\n\n| 조합 | 빌드 | 승리% | 패배% | 시간초과% | 받은 피해 | 공격 전 사망% |\n|---|---|---|---|---|---|---|\n';
  for (const [c, l] of byCombo) for (const [b, bl] of group(l.filter(r => r.hp === 2), r => nm(r.build))) { const a = agg(bl); md += `| ${c} | ${b} | ${a.win} | ${a.loss} | ${a.timeout} | ${a.taken} | ${a.dba} |\n`; }
  const shc = rows.filter(r => /shaman/.test(r.enemy)); if (shc.length) md += `\n주술사 조합(${shc.length}전): 치료 ${shc.reduce((a, r) => a + (r.heals || 0), 0)}회 / 방해 ${shc.reduce((a, r) => a + (r.interrupts || 0), 0)}회\n`;
  // 질문 3: 피해·실패 급증(체력 ×1 대비 ×2/×3에서 패배율 ≥ 30% 또는 피해 2배 이상·40 이상)
  md += '\n## Q3. 피해·실패가 급증하는 조합\n\n| 조합 | 체력 | 패배% | 시간초과% | 받은 피해 | ×1 받은 피해 | 공격 전 사망% |\n|---|---|---|---|---|---|---|\n';
  const q3 = [];
  for (const [c, l] of byCombo) { const base = agg(l.filter(r => r.hp === 1)); for (const [hp, hl] of group(l, r => r.hp)) { const a = agg(hl); if (a.loss >= 30 || (a.taken >= 40 && a.taken >= base.taken * 2) || a.timeout >= 20) q3.push([c, '×' + hp, a.loss, a.timeout, a.taken, base.taken, a.dba]); } }
  q3.sort((x, y) => y[2] - x[2] || y[4] - x[4]); for (const row of q3) md += `| ${row.join(' | ')} |\n`;
  summary.byComboHp = Object.fromEntries([...byCombo].map(([c, l]) => [c, Object.fromEntries([...group(l, hpOf)].map(([k, x]) => [k, agg(x)]))])); summary.q3 = q3;
}
if (suite === 'D' || suite === 'D2' || suite === 'D3' || suite === 'E') {
  const VN = { cmp_sword: '검', cmp_blades: '회전 칼날', cmp_spear: '창 ×1.0', 'cmp_spear@0.85': '창 ×0.85', 'cmp_spear@0.75': '창 ×0.75', 'cmp_spear@sweet': '창 근접 약화(45% 안쪽 ×0.5)', 'cmp_spear@narrow': '창 폭 28', 'cmp_spear@pierce2': '창 관통 2명', 'cmp_spear@sweet+narrow': '창 근접 약화+폭 28', 'cmp_spear@int0.85': '창 주기 0.85', 'cmp_spear@dmg12': '창 피해 12', 'cmp_spear@sweet+int0.85': '창 근접 약화+주기 0.85', 'cmp_spear@sweet+dmg12': '창 근접 약화+피해 12' };
  const vn = (r) => VN[r.variant] || r.variant, order = ['cmp_sword', 'cmp_blades', 'cmp_spear', 'cmp_spear@0.85', 'cmp_spear@0.75', 'cmp_spear@sweet', 'cmp_spear@narrow', 'cmp_spear@pierce2', 'cmp_spear@sweet+narrow', 'cmp_spear@int0.85', 'cmp_spear@dmg12', 'cmp_spear@sweet+int0.85', 'cmp_spear@sweet+dmg12'];
  const sorted = (g) => new Map([...g.entries()].sort((a, b) => order.indexOf(a[0]) - order.indexOf(b[0])));
  md += `\n## 무기별(전체: ${suite === 'E' ? '지역 5 + 조합 4 + 보스 3 + 정지 보스, 체력 ×1·×2, 봇 4(제자리 포함)' : '지역 5 + 보스 3, 체력 ×1·×2, 봇 3'})\n` + table('전체', sorted(group(rows, r => r.variant)), '무기').replace(/\| cmp_[^ |]+/g, (m) => '| ' + (VN[m.slice(2)] || m.slice(2)));
  md += '\n## 적별 × 무기\n';
  for (const [e, l] of group(rows, r => nm(r.enemy))) md += table(`${e}`, sorted(group(l, r => r.variant)), '무기').replace(/\| cmp_[^ |]+/g, (m) => '| ' + (VN[m.slice(2)] || m.slice(2)));
  // 보스 패턴: 무기별 × 보스 → 전투당 시작된 패턴 종류·횟수, 실행된 공격 수, 받은 피해
  md += '\n## 보스전: 무기별 실행된 패턴(전투당 평균)\n\n| 보스 | 무기 | 전투 | 승리% | 승리 평균초 | 받은 피해 | 보스 공격 실행/전투 | 패턴 시작(평균) |\n|---|---|---|---|---|---|---|---|\n';
  for (const [e, l] of group(rows.filter(r => /boss/.test(r.enemy)), r => nm(r.enemy))) for (const [v, vl] of sorted(group(l, r => r.variant))) { const a = agg(vl); const pat = {}; for (const r of vl) for (const k in r.patterns) pat[k] = (pat[k] || 0) + r.patterns[k]; const exec = vl.reduce((s, r) => s + (r.executed || 0), 0) / vl.length; md += `| ${e} | ${VN[v] || v} | ${a.n} | ${a.win} | ${a.tWon} | ${a.taken} | ${r1(exec)} | ${Object.keys(pat).sort().map(k => k + ' ' + r1(pat[k] / vl.length)).join(', ')} |\n`; }
  summary.byVariant = Object.fromEntries([...group(rows, r => r.variant)].map(([v, l]) => [v, agg(l)]));
  summary.byEnemyVariant = Object.fromEntries([...group(rows, r => nm(r.enemy))].map(([e, l]) => [e, Object.fromEntries([...group(l, r => r.variant)].map(([v, x]) => [v, agg(x)]))]));
}
fs.writeFileSync(path.join(dir, `report_${suite}.md`), md); fs.writeFileSync(path.join(dir, `summary_${suite}.json`), JSON.stringify(summary, null, 1));
console.log('wrote', path.join(dir, `report_${suite}.md`), rows.length, 'rows');
