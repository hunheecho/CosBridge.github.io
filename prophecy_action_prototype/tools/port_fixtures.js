// 이식 비교 자료: 대표 전투의 설정·입력(스텝별)·결과를 기록하고, 기록된 입력만으로 재실행해 같은 결과가 나오는지 확인한다.
// 봇은 기록 단계에서만 쓰고, 재실행은 입력 열만 쓴다(다른 엔진에서 같은 입력을 넣어 비교하는 기준). 사용: node tools/port_fixtures.js [--verify]
const fs = require('fs'), path = require('path'); const { load } = require('../test/load'); const PA = load(); PA.Balance.apply('test03');
const OUT = path.join(__dirname, '..', 'docs', 'port'); const STEP = PA.CONFIG.STEP;
const CASES = [
  { id: 'blades_day1', desc: '회전 칼날 Lv1 · 1일차 숲 편성 · 체력 ×1.5 · 봇 aware', lab: 'enemy=day:forest:1;hp=1.5,1.5,1;seed=3;build=start_blades;control=bot;bot=aware;growth=fixed;time=90;balance=test03', maxSec: 90 },
  { id: 'sword_day1', desc: '검격 Lv1 · 1일차 숲 · 봇 balanced', lab: 'enemy=day:forest:1;hp=1.5,1.5,1;seed=3;build=start_sword;control=bot;bot=balanced;growth=fixed;time=90;balance=test03', maxSec: 90 },
  { id: 'spear_ridge3', desc: '관통창 7선택 · 능선 3일차 편성 · 체력 ×1.5 · 봇 balanced', lab: 'enemy=day:ridge:3;hp=1.5,1.5,1;seed=5;build=cmp_spear;control=bot;bot=balanced;growth=fixed;time=120;balance=test03', maxSec: 120 },
  { id: 'stage3_deep6', desc: '3단계 관문 빌드 · 심층 6일차 편성 · 체력 ×3 · 봇 balanced', lab: 'enemy=day:deep:6;hp=3,3.75,1;seed=3;build=stage3;control=bot;bot=balanced;growth=fixed;time=120;balance=test03', maxSec: 120 },
  { id: 'stage1_boss', desc: '1단계 관문 빌드 · 가시갈기 2400 · 봇 aggressive', lab: 'enemy=boss;hp=1,1,1;seed=11;build=stage1;control=bot;bot=aggressive;growth=fixed;time=200;balance=test03', maxSec: 200 },
  { id: 'stage3_eater', desc: '3단계 관문 빌드 · 예언을 먹는 자 7000 · 봇 balanced', lab: 'enemy=boss:eater;hp=1,1,1;seed=3;build=stage3;control=bot;bot=balanced;growth=fixed;time=200;balance=test03', maxSec: 200 },
];
function make(c) { const cfg = PA.Lab.decode(c.lab); if (cfg.enemy.startsWith('boss') || cfg.enemy.startsWith('dummy')) { const p = PA.Lab.enemyPreset(cfg.enemy); if (p.bossId) cfg.bossHp = PA.BOSS_HP_SETS.hi[p.bossId]['stage' + (['boss', 'guardian', 'eater'].indexOf(p.bossId) + 1)]; } const run = PA.Lab.makeRun(cfg); return { cfg, run, st: PA.Lab.makeCombat(cfg, run) }; }
const enc = (i) => [i.mx || 0, i.my || 0, i.dodge ? 1 : 0, i.special ? 1 : 0, i.skillE ? 1 : 0];
function summary(st) { const s = PA.Combat.summary(st); const dmg = {}; for (const k in s.dmg) dmg[k] = s.dmg[k].amount; return { status: s.status, elapsed: s.elapsed, hp: s.hp, kills: s.kills, damageTaken: s.damageTaken, q: s.specialUses, e: s.eUses, dodges: s.dodges, dmg, hits: s.hits, player: { x: Math.round(st.player.x * 100) / 100, y: Math.round(st.player.y * 100) / 100 }, bossHp: st.boss ? Math.round(st.boss.hp * 10) / 10 : null, steps: st.stepN }; }
function record(c) {
  const { cfg, run, st } = make(c); const mem = {}; const inputs = []; const maxSteps = Math.round(c.maxSec / STEP);
  while (st.status === 'running' && inputs.length < maxSteps) { const inp = PA.Bot.stepInput(st, cfg.bot, mem); inputs.push(enc(inp)); PA.Combat.step(st, inp, STEP); }
  if (st.status === 'running') st.status = 'timeout';
  return { id: c.id, desc: c.desc, version: PA.VERSION, balance: cfg.balance, lab: c.lab, cfgText: PA.Lab.encode(cfg), bossHp: cfg.bossHp || null, build: PA.Lab.describeBuild(cfg.build), step: STEP, inputFormat: '[mx,my,dodge,special,skillE] per fixed step', inputs, result: summary(st) };
}
function replay(fx) { const c = CASES.find(x => x.id === fx.id); const { st } = make(c); for (const i of fx.inputs) { if (st.status !== 'running') break; PA.Combat.step(st, { mx: i[0], my: i[1], dodge: !!i[2], special: !!i[3], skillE: !!i[4] }, STEP); } if (st.status === 'running') st.status = 'timeout'; return summary(st); }
const verify = process.argv.includes('--verify'); const file = path.join(OUT, 'fixtures_v08.json');
if (verify) { const fxs = JSON.parse(fs.readFileSync(file, 'utf8')); let okAll = true; for (const fx of fxs.cases) { const r = replay(fx); const same = JSON.stringify(r) === JSON.stringify(fx.result); okAll = okAll && same; console.log((same ? 'PASS ' : 'FAIL ') + fx.id + ' ' + r.status + ' ' + r.elapsed + 's' + (same ? '' : ' expected ' + JSON.stringify(fx.result).slice(0, 200))); } process.exit(okAll ? 0 : 1); }
const cases = CASES.map(record); const commit = require('child_process').execSync('git rev-parse --short HEAD').toString().trim();
fs.mkdirSync(OUT, { recursive: true }); fs.writeFileSync(file, JSON.stringify({ version: PA.VERSION, commit, balance: 'test03', step: STEP, note: '입력 열은 고정 단계(1/120초)마다 하나. 같은 설정·시드·입력으로 다른 엔진에서 실행해 result와 비교한다. 난수는 PA.rng(mulberry32, 시드), 시간은 고정 단계.', cases }, null, 0));
let md = `# 이식 비교 자료 (v${PA.VERSION}, 커밋 ${commit}, test03)\n\n\`fixtures_v08.json\`: 대표 전투 ${cases.length}개의 설정(시험실 문자열)·빌드·입력 열(고정 단계 1/120초, [mx,my,dodge,special,skillE])·결과. \`node tools/port_fixtures.js --verify\`가 입력 열만으로 재실행해 결과 일치를 확인한다(봇 없이). 다른 엔진 이식 시 같은 시드·입력을 넣고 result(상태·경과·체력·처치·받은 피해·출처별 피해·명중·플레이어 위치·보스 체력·스텝 수)를 비교한다.\n\n| id | 설명 | 스텝 | 결과 | 경과 | 남은 체력 | 처치 | 받은 피해 | 보스 체력 |\n|---|---|---|---|---|---|---|---|---|\n`;
for (const c of cases) md += `| ${c.id} | ${c.desc} | ${c.inputs.length} | ${c.result.status} | ${c.result.elapsed} | ${c.result.hp} | ${c.result.kills} | ${c.result.damageTaken} | ${c.result.bossHp == null ? '-' : c.result.bossHp} |\n`;
md += `\n결정성 전제: 난수 PA.rng.create(seed) 단일 스트림, 고정 단계, 봇 판단 주기 5스텝. 브라우저 프레임 루프는 같은 단계 함수를 호출하므로(test/lab.test.js 프레임 독립 테스트) 입력 열이 같으면 결과가 같다.\n`;
fs.writeFileSync(path.join(OUT, 'FIXTURES.md'), md); console.log(md);
