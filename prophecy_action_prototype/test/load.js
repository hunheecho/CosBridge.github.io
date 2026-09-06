// 브라우저용 전역 스크립트를 Node vm 컨텍스트에 로드한다. index.html의 순서와 동일해야 한다.
const fs = require('fs'), vm = require('vm'), path = require('path');
const ORDER = ['core', 'input', 'data', 'build', 'combat', 'boss', 'run'];
function load() {
  const ctx = { console }; vm.createContext(ctx);
  for (const f of ORDER) vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'src', f + '.js'), 'utf8'), ctx, { filename: f + '.js' });
  return ctx.PA;
}
function fakeStorage() { const m = {}; return { getItem: k => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); }, removeItem: k => { delete m[k]; } }; }
function runWith(PA, opts) { const run = PA.Run.newRun(1); Object.assign(run.gear, opts.gear || {}); Object.assign(run.augments, opts.augments || {}); return run; }
function combat(PA, opts) {
  opts = opts || {};
  const run = runWith(PA, opts);
  const st = PA.Combat.create({ build: PA.Run.build(run), seed: opts.seed || 1, waves: opts.waves || [], objective: opts.objective || 'none', hp: opts.hp });
  st.waveIndex = 99; // 자동 웨이브 스폰 차단(테스트가 직접 배치). objective 'none'은 자동 종료 없음
  return { PA, run, st };
}
function steps(PA, st, seconds, input, dt, pins) { dt = dt || PA.CONFIG.STEP; const n = Math.round(seconds / dt); for (let i = 0; i < n; i++) { PA.Combat.step(st, input || {}, dt); if (pins) for (const [e, x, y] of pins) { e.x = x; e.y = y; e.vx = e.vy = 0; } } }
module.exports = { load, fakeStorage, runWith, combat, steps, ORDER };
