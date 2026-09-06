// 대량 전투 시뮬레이션(헤드리스, worker_threads 병렬). 원시 결과는 JSONL(.gz)로, 요약은 tools/lab_report.js로 만든다.
// 사용: node tools/lab_sim.js A|B|C [--seeds 10] [--workers 4] [--out docs/sim] [--limit N]
//  A: 빌드 프리셋 × 지역 5(기존 배치) × 체력 배율 7 × 시드 × 봇 3     (빌드 9 × 5 × 7 × 10 × 3 = 9,450전)
//  B: 신규 적 단독 × 체력 배율(1/2/3/4) × 빌드 6 × 시드 × 봇 3 (+ 멧돼지·잠복충은 기둥 숲 지형 추가)
//  C: 조합 프리셋 14 × 빌드 5 × 체력 배율(1/2/3) × 시드 × 봇 3
// 봇 결과는 정책 비교용이며 사람의 승률·재미·적정 체력 승인이 아니다. 전투 중 성장 선택은 적용하지 않는다(빌드 고정).
const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');
const fs = require('fs'), path = require('path'), zlib = require('zlib'), os = require('os');
const { load } = require('../test/load');

function jobsFor(suite, PA, seeds) {
  const jobs = [], bots = Object.keys(PA.Bot.POLICIES);
  const push = (o) => jobs.push(Object.assign({ suite, time: 120, arena: 'auto' }, o));
  if (suite === 'A') { for (const build of Object.keys(PA.LAB.BUILDS)) for (const r of PA.REGIONS) for (const hp of PA.LAB.HP_MULTS) for (const seed of seeds) for (const bot of bots) push({ build, enemy: 'region:' + r.id, hp, seed, bot }); }
  if (suite === 'B') { const builds = ['early_sword', 'early_spear', 'early_blades', 'mid_melee', 'mid_ranged', 'slowfield']; for (const t of ['boar', 'shieldbearer', 'shaman', 'bomber', 'burrower', 'spider', 'frostcaller', 'rogue']) for (const hp of [1, 2, 3, 4]) for (const build of builds) for (const seed of seeds) for (const bot of bots) { push({ build, enemy: 'solo:' + t, hp, seed, bot }); if (t === 'boar' || t === 'burrower' || t === 'shieldbearer') push({ build, enemy: 'solo:' + t, hp, seed, bot, arena: t === 'boar' ? 'forest' : 'pillars' }); } }
  if (suite === 'C') { const builds = ['early_sword', 'mid_melee', 'mid_ranged', 'slowfield', 'late_multi']; for (const c of PA.LAB_COMBOS) for (const build of builds) for (const hp of [1, 2, 3]) for (const seed of seeds) for (const bot of bots) push({ build, enemy: 'combo:' + c.id, hp, seed, bot }); }
  return jobs;
}
function runJob(PA, job) {
  const cfg = PA.Lab.decode(`enemy=${job.enemy};hp=${job.hp},${job.hp},1;seed=${job.seed};build=${job.build};control=bot;bot=${job.bot};growth=fixed;time=${job.time};arena=${job.arena || 'auto'}`);
  const run = PA.Lab.makeRun(cfg), st = PA.Lab.makeCombat(cfg, run);
  PA.Bot.runCombat(st, job.bot, { maxSec: job.time + 1 });
  const s = PA.Combat.summary(st);
  const en = Object.values(s.enemies); const sum = (k) => en.reduce((a, e) => a + (e[k] || 0), 0);
  return { suite: job.suite, build: job.build, enemy: job.enemy, hp: job.hp, seed: job.seed, bot: job.bot, arena: st.arenaId, version: s.version,
    status: s.status, elapsed: s.elapsed, hpLeft: s.hp, hpMax: s.hpMax, taken: s.damageTaken, absorbed: s.absorbed, kills: s.kills, q: s.specialUses, e: s.eUses, dodges: s.dodges, farFrac: s.farFrac,
    spawned: sum('spawned'), killed: sum('killed'), exploded: sum('exploded'), prepared: sum('prepared'), executed: sum('executed'), dba: sum('diedBeforeAttack'), enemies: s.enemies, dmg: s.dmg, takenBy: s.taken, heals: s.heals, interrupts: s.interrupts };
}

if (!isMainThread) {
  const PA = load();
  parentPort.on('message', (jobs) => { const out = []; for (const j of jobs) { try { out.push(runJob(PA, j)); } catch (e) { out.push({ error: String(e && e.stack || e), job: j }); } } parentPort.postMessage(out); });
} else {
  const args = process.argv.slice(2); const suite = (args[0] || 'A').toUpperCase();
  const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
  const seedsN = parseInt(opt('seeds', '10'), 10), workersN = parseInt(opt('workers', String(Math.max(1, Math.min(4, os.cpus().length)))), 10), outDir = opt('out', path.join(__dirname, '..', 'docs', 'sim')), limit = parseInt(opt('limit', '0'), 10);
  const PA = load(); const seeds = Array.from({ length: seedsN }, (_, i) => i + 1);
  let jobs = jobsFor(suite, PA, seeds); if (limit) jobs = jobs.slice(0, limit);
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `raw_${suite}.jsonl.gz`), gz = zlib.createGzip(); gz.pipe(fs.createWriteStream(outPath));
  console.log(`suite ${suite}: ${jobs.length} fights, ${workersN} workers, version ${PA.VERSION}`);
  const t0 = Date.now(); let done = 0, next = 0, errors = 0; const CHUNK = 20;
  const workers = Array.from({ length: workersN }, () => new Worker(__filename));
  const feed = (w) => { if (next >= jobs.length) { w.terminate(); return; } const chunk = jobs.slice(next, next + CHUNK); next += CHUNK; w.postMessage(chunk); };
  let live = workers.length;
  for (const w of workers) {
    w.on('message', (rows) => { for (const r of rows) { if (r.error) { errors++; if (errors <= 5) console.error(r.error); } gz.write(JSON.stringify(r) + '\n'); } done += rows.length; if (done % 200 < CHUNK) process.stdout.write(`  ${done}/${jobs.length} (${Math.round((Date.now() - t0) / 1000)}s)\n`); feed(w); });
    w.on('exit', () => { live--; if (live === 0) { gz.end(); console.log(`done ${done} fights, errors ${errors}, ${Math.round((Date.now() - t0) / 1000)}s → ${outPath}`); } });
    feed(w);
  }
}
