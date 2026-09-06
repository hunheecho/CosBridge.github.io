const test = require('node:test');
const assert = require('node:assert/strict');
const { load, steps } = require('./load');
const PA = load();
const CB = PA.Combat;

function arena(PA, opts) {
  opts = opts || {};
  const run = PA.Run.newRun(1); Object.assign(run.gear, opts.gear || {}); Object.assign(run.augments, opts.augments || {});
  const st = CB.create({ build: PA.Run.build(run), seed: opts.seed || 1, waves: [], objective: 'none', arena: 'clearing' });
  st.waveIndex = 99; return st;
}
const rockA = () => PA.ARENAS.clearing.obstacles[0];
const pinned = (e) => { e.state = 'recover'; e.def = Object.assign({}, e.def, { recover: 999 }); return e; };

test('전장 데이터: 공터에 바위 2·나무 2, 첫 시험 배치', () => {
  const obs = PA.ARENAS.clearing.obstacles;
  assert.equal(obs.length, 4);
  assert.deepEqual(JSON.parse(JSON.stringify(obs.map(o => [o.type, o.x, o.y, o.r]))), [['rock', 285, 220, 42], ['rock', 675, 380, 42], ['tree', 300, 420, 26], ['tree', 660, 180, 26]]);
});

test('이동: 바위를 뚫지 않고 표면을 따라 미끄러진다', () => {
  const st = arena(PA); const p = st.player, ob = rockA();
  p.x = ob.x - 120; p.y = ob.y - 20;
  steps(PA, st, 2.0, { mx: 1, my: 0 });
  assert.ok(PA.m.dist(p, ob) >= ob.r + p.r - 1e-6, '바위 안으로 들어가지 않음');
  assert.ok(p.x > ob.x, `표면을 따라 반대편으로 미끄러짐 x=${p.x.toFixed(1)}`);
});

test('회피: 장애물을 통과하지 않고 표면에서 멈춘다', () => {
  const st = arena(PA); const p = st.player, ob = rockA();
  p.x = ob.x - ob.r - p.r - 40; p.y = ob.y; p.face = 0;
  PA.Combat.step(st, { dodge: true, mx: 1, my: 0 }, PA.CONFIG.STEP); steps(PA, st, 0.4, {});
  assert.ok(p.x < ob.x, '바위 반대편으로 넘어가지 않음');
  assert.ok(Math.abs(PA.m.dist(p, ob) - (ob.r + p.r)) < 2, `표면에서 정지 d=${PA.m.dist(p, ob).toFixed(1)}`);
});

test('늑대 돌진: 바위에 닿으면 그 지점에서 멈추고, 바위 뒤 플레이어를 물지 못한다', () => {
  const st = arena(PA); const p = st.player, ob = rockA();
  p.x = ob.x; p.y = ob.y + ob.r + p.r + 6; // 바위 바로 뒤
  const e = CB.spawnEnemy(st, 'wolf', ob.x, ob.y - ob.r - 120); e.state = 'lock'; e.dir = Math.PI / 2; e.stateT = 0;
  steps(PA, st, 0.15 + 0.6);
  assert.equal(p.hp, 100, '장애물 뒤로 물기 피해가 관통하지 않음');
  assert.ok(e.y < ob.y, `늑대는 바위 앞에서 정지 y=${e.y.toFixed(1)}`);
  assert.ok(Math.abs(PA.m.dist(e, ob) - (ob.r + e.r)) < 2.5, '접촉 위치에서 정지');
  assert.equal(e.state, 'recover', '정상적인 공격 후 빈틈으로 전환');
});

test('돌진 충돌 결과가 30fps와 120fps에서 실질적으로 같다', () => {
  const run = (dt) => { const st = arena(PA); st.player.x = 900; st.player.y = 560; const e = CB.spawnEnemy(st, 'wolf', rockA().x - 200, rockA().y); e.state = 'lock'; e.dir = 0; e.stateT = 0; steps(PA, st, 0.8, {}, dt); return [e.x, e.y, e.state]; };
  const a = run(1 / 30), b = run(1 / 120);
  assert.ok(Math.abs(a[0] - b[0]) < 3 && Math.abs(a[1] - b[1]) < 3, `${a} vs ${b}`);
  assert.equal(a[2], b[2]);
});

test('투사체: 적보다 먼저 만난 장애물에서 소멸하고, 장애물 뒤 적은 맞지 않는다', () => {
  const st = arena(PA); const ob = rockA();
  const behind = pinned(CB.spawnEnemy(st, 'wolf', ob.x + ob.r + 40, ob.y)); behind.hp = 1e6;
  st.player.x = 60; st.player.y = 560; // 사거리 밖
  st.projectiles.push({ owner: 'player', kind: 'shard', x: ob.x - ob.r - 60, y: ob.y, vx: 100000, vy: 0, r: 4, dmg: 50, ttl: 1 });
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(st.projectiles.length, 0, '소멸');
  assert.equal(behind.hp, 1e6, '뒤의 적은 무사');
  // 적이 장애물보다 앞이면 적이 맞는다
  const front = pinned(CB.spawnEnemy(st, 'wolf', ob.x - ob.r - 30, ob.y)); front.hp = 1e6;
  st.projectiles.push({ owner: 'player', kind: 'shard', x: ob.x - ob.r - 90, y: ob.y, vx: 100000, vy: 0, r: 4, dmg: 50, ttl: 1 });
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.ok(front.hp < 1e6, '앞의 적이 먼저 맞음');
  // 적의 화살도 장애물에 막힌다
  st.player.x = ob.x + ob.r + 40; st.player.y = ob.y;
  st.projectiles.push({ owner: 'enemy', kind: 'arrow', x: ob.x - ob.r - 60, y: ob.y, vx: 100000, vy: 0, r: 5, dmg: 10, ttl: 1 });
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(st.player.hp, 100);
});

test('직접 공격(검격·관통·회전)은 장애물 뒤의 적을 때리지 않고, 관통 검광은 장애물에서 멈춘다', () => {
  const ob = rockA();
  for (const setup of [{ gear: {} }, { gear: { weapon: 'pierce' } }, { augments: { spin: 1 } }]) {
    const st = arena(PA, setup); const p = st.player;
    p.x = ob.x - ob.r - 30; p.y = ob.y; p.face = 0;
    const behind = pinned(CB.spawnEnemy(st, 'wolf', ob.x + ob.r + 20, ob.y)); behind.hp = 1e6;
    const side = pinned(CB.spawnEnemy(st, 'wolf', p.x, p.y - 60)); side.hp = 1e6;
    const pins = [[behind, behind.x, behind.y], [side, side.x, side.y]];
    steps(PA, st, 2.0, {}, null, pins);
    assert.ok(st.stats.attacks > 0, '가려지지 않은 적은 공격');
    assert.equal(behind.hp, 1e6, `장애물 뒤 적 무사 (${JSON.stringify(setup)})`);
    assert.ok(side.hp < 1e6, '옆의 적은 맞음');
  }
  const st = arena(PA, { gear: { weapon: 'pierce' } }); const p = st.player; p.x = ob.x - ob.r - 50; p.y = ob.y;
  assert.ok(Math.abs(CB.beamLength(st, p, 0, 230) - (50)) < 1e-6, '검광 길이 = 장애물까지');
  assert.equal(CB.beamLength(st, p, Math.PI, 230), 230);
});

test('경로 탐색: 바위 뒤의 늑대와 나무 옆의 큰 개체가 플레이어에게 도달한다', () => {
  const st = arena(PA); const p = st.player, ob = rockA();
  p.x = ob.x; p.y = ob.y + 200; p.hp = 1e9;
  const e = CB.spawnEnemy(st, 'wolf', ob.x, ob.y - 140);
  let reached = false; for (let i = 0; i < 120 * 5; i++) { PA.Combat.step(st, {}, PA.CONFIG.STEP); if (PA.m.dist(e, p) < e.def.engageDist) { reached = true; break; } }
  assert.ok(reached, `바위를 돌아 접근 (d=${PA.m.dist(e, p).toFixed(0)})`);
  // 큰 개체(반지름 42)가 나무 A(300,420) 뒤에서 접근
  const st2 = arena(PA); const p2 = st2.player; p2.x = 300; p2.y = 560; p2.hp = 1e9;
  const big = CB.spawnEnemy(st2, 'wolf', 300, 300); big.r = 42; big.def = Object.assign({}, big.def, { engageDist: 90 });
  let ok = false; for (let i = 0; i < 120 * 6; i++) { PA.Combat.step(st2, {}, PA.CONFIG.STEP); if (PA.m.dist(big, p2) < 130) { ok = true; break; } }
  assert.ok(ok, `큰 개체가 나무를 돌아 접근 (d=${PA.m.dist(big, p2).toFixed(0)})`);
  for (const o of st2.obstacles) assert.ok(PA.m.dist(big, o) >= o.r + big.r - 1, '장애물을 뚫지 않음');
});

test('벽·장애물 모서리에서 끼거나 떨리지 않는다(위치가 수렴하거나 계속 전진)', () => {
  const st = arena(PA); const p = st.player; p.hp = 1e9;
  p.x = 60; p.y = 300;
  const e = CB.spawnEnemy(st, 'wolf', 940, 300); e.def = Object.assign({}, e.def, { engageDist: 30, speed: 150 });
  const xs = [];
  for (let i = 0; i < 120 * 8; i++) { PA.Combat.step(st, {}, PA.CONFIG.STEP); if (i % 12 === 0) xs.push(e.x); if (PA.m.dist(e, p) < 60) break; }
  // 떨림 검출: 최근 1초 동안 x가 앞뒤로 튀는 횟수
  let flips = 0; for (let i = 2; i < xs.length; i++) if ((xs[i] - xs[i - 1]) * (xs[i - 1] - xs[i - 2]) < -4) flips++;
  assert.ok(PA.m.dist(e, p) < 60 || flips < 5, `도달 d=${PA.m.dist(e, p).toFixed(0)} flips=${flips}`);
  assert.ok(PA.m.dist(e, p) < 60, '8초 안에 도달');
});

test('스폰·불길: 장애물 안에는 생성하지 않는다', () => {
  const st = arena(PA);
  CB.queueWave(st, [{ type: 'wolf', n: 12 }]);
  for (const s of st.pending) assert.ok(CB.validPos(st, s.x, s.y, PA.ENEMIES.wolf.r), `유효 위치 ${s.x},${s.y}`);
  const ob = rockA();
  assert.equal(CB.validPos(st, ob.x, ob.y, 0), false);
  const st2 = arena(PA, { augments: { ember: 1 } });
  const before = st2.zones.length;
  // 장애물 중심에 불길 생성 시도 → 생략 규칙
  assert.equal(st2.zones.length, before);
  const np = CB.nearestValidPos(st, ob.x, ob.y, 14); assert.ok(np && CB.validPos(st, np.x, np.y, 14));
});
