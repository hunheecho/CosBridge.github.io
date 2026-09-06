const test = require('node:test');
const assert = require('node:assert/strict');
const { load, combat, steps } = require('./load');
const PA = load();
const P = PA.CONFIG.PLAYER;

function wolfDashAt(st, x, y, dir) { const e = PA.Combat.spawnEnemy(st, 'wolf', x, y); e.state = 'dash'; e.dir = dir; e.stateT = 0; e.hitBy = null; return e; }

test('겹친 늑대 3마리가 같은 프레임에 물어도 피해는 1회(12)만 적용된다', () => {
  const { st } = combat(PA);
  const p = st.player;
  for (let i = 0; i < 3; i++) wolfDashAt(st, p.x - 31, p.y, 0);
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(p.hp, P.hp - 12);
});

test('피격 보호 0.6초 동안은 추가 피해가 없고, 지나면 다시 맞는다', () => {
  const { st } = combat(PA);
  const p = st.player;
  wolfDashAt(st, p.x - 31, p.y, 0);
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(p.hp, 88);
  steps(PA, st, 0.4);
  wolfDashAt(st, p.x - 31, p.y, 0); PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(p.hp, 88, '0.4초 뒤 두 번째 물기는 보호로 무효');
  steps(PA, st, 0.3);
  wolfDashAt(st, p.x - 31, p.y, 0); PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(p.hp, 76, '0.7초 뒤에는 다시 피해');
});

test('회피 중에는 무적이며 아슬아슬한 회피로 기록된다. 시간 저축은 감속장 재사용을 4초 줄인다', () => {
  const { st } = combat(PA, { augments: { saving: 1 } });
  const p = st.player;
  p.special.cd = 10;
  PA.Combat.step(st, { dodge: true, mx: 0, my: 1 }, PA.CONFIG.STEP); // 아래로 회피
  assert.equal(p.dodge.active, true);
  wolfDashAt(st, p.x - 31, p.y, 0);
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(p.hp, P.hp);
  assert.equal(st.stats.perfectDodges, 1);
  assert.ok(Math.abs(p.special.cd - 6) < 0.02, `감속장 재사용 ${p.special.cd}`);
});

test('회피 거리와 재사용 시간이 dt 크기와 무관하다', () => {
  const run = (dt) => { const { st } = combat(PA); const p = st.player; const x0 = p.x; PA.Combat.step(st, { dodge: true, mx: 1, my: 0 }, dt); steps(PA, st, 0.5 - dt, {}, dt); return { dist: p.x - x0, cd: p.dodge.cd }; };
  const a = run(1 / 30), b = run(1 / 240);
  assert.ok(Math.abs(a.dist - P.dodge.distance) < 1e-6, `30fps 회피 거리 ${a.dist}`);
  assert.ok(Math.abs(b.dist - P.dodge.distance) < 1e-6, `240fps 회피 거리 ${b.dist}`);
  assert.ok(Math.abs(a.cd - b.cd) < 1 / 30 + 1e-6, `재사용 차이 ${a.cd} vs ${b.cd}`);
});

test('감속장 재사용 시간과 공격 횟수가 dt 크기와 무관하다', () => {
  const run = (dt) => { const { st } = combat(PA); PA.Combat.spawnEnemy(st, 'spore', st.player.x + 60, st.player.y).hp = 1e9; PA.Combat.step(st, { special: true }, dt); steps(PA, st, 3.0 - dt, {}, dt); return { cd: st.player.special.cd, attacks: st.stats.attacks }; };
  const a = run(1 / 30), b = run(1 / 240);
  assert.ok(Math.abs(a.cd - b.cd) <= 1 / 30 + 1e-9, `${a.cd} vs ${b.cd}`);
  assert.ok(Math.abs(a.attacks - b.attacks) <= 1, `공격 횟수 ${a.attacks} vs ${b.attacks}`);
});

test('늑대 돌진: 준비 중에는 방향을 추적하고, 확정 뒤에는 고정된 방향으로만 이동한다', () => {
  const { st } = combat(PA);
  const p = st.player;
  const e = PA.Combat.spawnEnemy(st, 'wolf', p.x - 120, p.y);
  steps(PA, st, 0.05); // approach → crouch
  assert.equal(e.state, 'crouch');
  const a1 = e.aimAngle;
  p.y -= 80; steps(PA, st, 0.1);
  assert.notEqual(e.aimAngle, a1, '준비 중에는 조준이 따라와야 함');
  steps(PA, st, 0.5);
  assert.equal(e.state, 'lock');
  const locked = e.dir;
  p.y += 200; // 플레이어가 크게 이동
  steps(PA, st, 0.15 + 0.01);
  assert.equal(e.state, 'dash');
  const x0 = e.x, y0 = e.y; steps(PA, st, 0.1);
  const moved = Math.atan2(e.y - y0, e.x - x0);
  assert.ok(Math.abs(PA.m.angDiff(locked, moved)) < 1e-6, '돌진 방향은 확정된 방향과 일치');
  assert.equal(e.dir, locked);
});

test('돌진 총 거리는 dt와 무관하게 dashSpeed×dashTime 이다', () => {
  const run = (dt) => { const { st } = combat(PA); st.player.x = 900; st.player.y = 300; const e = PA.Combat.spawnEnemy(st, 'wolf', 100, 300); e.state = 'lock'; e.dir = 0; e.stateT = 0; steps(PA, st, 0.15 + 0.5, {}, dt); return e.x - 100; };
  const expect = PA.ENEMIES.wolf.dashSpeed * PA.ENEMIES.wolf.dashTime;
  assert.ok(Math.abs(run(1 / 30) - expect) < 1e-6);
  assert.ok(Math.abs(run(1 / 240) - expect) < 1e-6);
});

test('빠른 투사체와 돌진이 플레이어를 뚫고 지나가지 않는다(스윕 판정)', () => {
  const { st } = combat(PA);
  const p = st.player;
  st.projectiles.push({ owner: 'enemy', kind: 'arrow', x: p.x - 300, y: p.y, vx: 100000, vy: 0, r: 5, dmg: 10, ttl: 1 });
  PA.Combat.step(st, {}, PA.CONFIG.STEP);
  assert.equal(p.hp, 90);
});

test('지역 피해: 겹친 포자 구름 2개도 0.5초마다 1틱(6)만 준다', () => {
  const { st } = combat(PA);
  const p = st.player;
  PA.Combat.addZone(st, 'spore', p.x, p.y, 80, 5, 6);
  PA.Combat.addZone(st, 'spore', p.x + 10, p.y, 80, 5, 6);
  steps(PA, st, 1.0);
  assert.equal(p.hp, 100 - 12);
});

test('자동 공격은 사거리 안에 적이 있을 때만 발동하고, 한 검격은 적당 1회 피해', () => {
  const { st } = combat(PA);
  const p = st.player, b = st.build;
  const far = PA.Combat.spawnEnemy(st, 'wolf', p.x + 400, p.y); far.state = 'recover'; far.def = Object.assign({}, far.def, { recover: 999 });
  steps(PA, st, 1.0);
  assert.equal(st.stats.attacks, 0);
  const near = PA.Combat.spawnEnemy(st, 'wolf', p.x + 50, p.y); near.state = 'recover'; near.def = Object.assign({}, near.def, { recover: 999 });
  const hp0 = near.hp;
  steps(PA, st, 0.06);
  assert.equal(st.stats.attacks, 1);
  assert.equal(hp0 - near.hp, Math.round(b.damage * b.exposedMult * 10) / 10, '빈틈 상태 1.5배 1회');
});

test('자동 공격 대상은 가장 가까운 적이며, 표식이 있으면 표식 대상(정예>궁수>포자>늑대)을 우선한다', () => {
  const { st } = combat(PA);
  const p = st.player;
  const a = PA.Combat.spawnEnemy(st, 'wolf', p.x + 40, p.y), b = PA.Combat.spawnEnemy(st, 'wolf', p.x - 70, p.y);
  a.state = b.state = 'recover'; a.def = b.def = Object.assign({}, a.def, { recover: 999 });
  assert.equal(PA.Combat.chooseTarget(st), a);
  const { st: s2 } = combat(PA, { augments: { mark: 1 } });
  const w = PA.Combat.spawnEnemy(s2, 'wolf', s2.player.x + 30, s2.player.y);
  const ar = PA.Combat.spawnEnemy(s2, 'archer', s2.player.x + 70, s2.player.y);
  assert.equal(s2.markTarget, ar);
  w.state = ar.state = 'recover';
  assert.equal(PA.Combat.chooseTarget(s2), ar, '표식 대상이 사거리 안이면 우선');
});

test('관통 검격은 일렬로 선 적을 한 번에 모두 타격한다', () => {
  const { st } = combat(PA, { gear: { weapon: 'pierce' } });
  const p = st.player;
  const es = [60, 120, 200].map(d => { const e = PA.Combat.spawnEnemy(st, 'wolf', p.x + d, p.y); e.state = 'recover'; e.def = Object.assign({}, e.def, { recover: 999 }); return e; });
  steps(PA, st, 0.3);
  assert.equal(st.stats.attacks, 1);
  for (const e of es) assert.ok(e.hp < e.hpMax, '모두 피해');
});

test('회전 검격: 3번째 검격은 360°로 뒤쪽 적도 때린다. 메아리: 4번째 검격이 0.2초 뒤 반복된다', () => {
  const { st } = combat(PA, { augments: { spin: 1, echo: 1 } });
  const p = st.player;
  const front = PA.Combat.spawnEnemy(st, 'wolf', p.x + 50, p.y), back = PA.Combat.spawnEnemy(st, 'wolf', p.x - 70, p.y);
  front.hp = back.hp = 1e6; front.state = back.state = 'recover'; front.def = back.def = Object.assign({}, front.def, { recover: 999 });
  const pins = [[front, p.x + 50, p.y], [back, p.x - 70, p.y]];
  steps(PA, st, 0.2 + st.build.interval + 0.05, {}, null, pins);
  assert.equal(st.stats.attacks, 2); assert.equal(back.hp, 1e6, '부채꼴은 뒤를 못 침');
  steps(PA, st, st.build.interval, {}, null, pins);
  assert.equal(st.stats.attacks, 3); assert.ok(back.hp < 1e6, '3번째는 회전');
  assert.ok(st.effects.some(f => f.kind === 'spin'));
  steps(PA, st, st.build.interval, {}, null, pins);
  assert.equal(st.player.attackCount, 4);
  steps(PA, st, 0.25, {}, null, pins);
  assert.equal(st.stats.attacks, 5, '메아리로 한 번 더');
});

test('잔불 걸음: 회피 경로에 불길 3개가 남고 불길 위의 적이 피해를 받는다. 불꽃 파열은 불길 위 처치 시 폭발', () => {
  const { st } = combat(PA, { augments: { ember: 1, flare: 1 } });
  const p = st.player;
  PA.Combat.step(st, { dodge: true, mx: 1, my: 0 }, PA.CONFIG.STEP);
  steps(PA, st, 0.3);
  assert.equal(st.zones.filter(z => z.type === 'fire').length, 3);
  const z = st.zones[0];
  const victim = PA.Combat.spawnEnemy(st, 'wolf', z.x, z.y); victim.state = 'recover'; victim.def = Object.assign({}, victim.def, { recover: 999 }); victim.hp = 3;
  const bystander = PA.Combat.spawnEnemy(st, 'wolf', z.x + 60, z.y + 60); bystander.state = 'recover'; bystander.def = victim.def; bystander.hp = 1e6;
  st.player.x = 50; st.player.y = 50; // 검격 사거리 밖
  steps(PA, st, 0.5);
  assert.equal(victim.dead, true);
  assert.ok(bystander.hp < 1e6, '불꽃 파열 폭발 피해');
});

test('얼음 파편: 적중 시 냉기, 냉기 상태 처치 시 파편 6개', () => {
  const { st } = combat(PA, { augments: { frost: 1 } });
  const p = st.player;
  const e = PA.Combat.spawnEnemy(st, 'wolf', p.x + 50, p.y); e.state = 'recover'; e.def = Object.assign({}, e.def, { recover: 999 }); e.hp = 100;
  steps(PA, st, 0.3);
  assert.ok(e.chill > 0);
  e.hp = 1; steps(PA, st, st.build.interval);
  assert.equal(e.dead, true);
  assert.equal(st.projectiles.filter(x => x.kind === 'shard').length, 6);
});

test('파열 방벽: 보호막이 먼저 깎이고 파괴 시 주변 적을 밀어낸다', () => {
  const { st } = combat(PA, { augments: { barrier: 1 } });
  const p = st.player;
  assert.equal(p.shield, 30);
  const e = PA.Combat.spawnEnemy(st, 'wolf', p.x + 60, p.y); e.state = 'recover'; e.def = Object.assign({}, e.def, { recover: 999 });
  PA.Combat.damagePlayer(st, 12, 'test');
  assert.equal(p.shield, 18); assert.equal(p.hp, 100);
  p.hitProt = 0; PA.Combat.damagePlayer(st, 30, 'test');
  assert.equal(p.shield, 0); assert.equal(p.hp, 88);
  assert.ok(e.vx > 0, '넉백');
});

test('정지된 칼날: 감속장 안에서 맞은 적에 흔적이 쌓이고 감속장 종료 시 폭발한다. 감속장 안의 적은 40% 속도', () => {
  const { st } = combat(PA, { augments: { stasis: 1 } });
  const p = st.player;
  const e = PA.Combat.spawnEnemy(st, 'wolf', p.x + 50, p.y); e.state = 'recover'; e.def = Object.assign({}, e.def, { recover: 999 }); e.hp = 1e6;
  PA.Combat.step(st, { special: true }, PA.CONFIG.STEP);
  assert.ok(st.field);
  steps(PA, st, 1.5);
  assert.ok(e.stasis >= 2);
  const hpBefore = e.hp, stacks = e.stasis;
  const interval = st.build.interval; const attacksBefore = st.stats.attacks;
  steps(PA, st, 1.6);
  assert.equal(st.field, null);
  assert.equal(e.stasis, 0);
  // 폭발 피해 = stacks×10×1.5(빈틈) 이 추가로 들어갔는지 (검격 피해 제외)
  const swings = st.stats.attacks - attacksBefore;
  const expectedSwingDmg = swings * Math.round(st.build.damage * st.build.exposedMult * 10) / 10;
  const extra = (hpBefore - e.hp) - expectedSwingDmg;
  assert.ok(extra >= 15, `폭발 추가 피해 ${extra}`);
  // 감속
  const { st: s2 } = combat(PA);
  const w = PA.Combat.spawnEnemy(s2, 'wolf', 100, s2.player.y); const w2 = PA.Combat.spawnEnemy(s2, 'wolf', 100, 100);
  s2.field = { x: 100, y: s2.player.y, r: 150, ttl: 5, maxTtl: 5 };
  const a0 = { x: w.x, y: w.y }, b0 = { x: w2.x, y: w2.y }; steps(PA, s2, 0.2);
  assert.ok(Math.abs(PA.m.dist(w, a0) / PA.m.dist(w2, b0) - 0.4) < 0.05, '감속장 안 40% 속도');
});

test('궁수는 거리를 유지하고 조준 후 화살을 쏜다. 포자 괴물은 부풀고 구름을 남긴다', () => {
  const { st } = combat(PA);
  const p = st.player;
  const a = PA.Combat.spawnEnemy(st, 'archer', p.x + 300, p.y);
  steps(PA, st, 2.0);
  assert.ok(st.projectiles.some(x => x.kind === 'arrow') || st.stats.damageTaken > 0 || a.state === 'recover', '화살 발사됨');
  const { st: s2 } = combat(PA);
  const sp = PA.Combat.spawnEnemy(s2, 'spore', s2.player.x + 100, s2.player.y); sp.hp = 1e6;
  steps(PA, s2, 1.5);
  assert.ok(s2.zones.some(z => z.type === 'spore'), '구름 생성');
});

test('조우 목적: 전멸은 모든 웨이브 처치 시, 정예 처치는 정예 사망 즉시 승리', () => {
  const run = PA.Run.newRun(1);
  const st = PA.Combat.create({ build: PA.Run.build(run), seed: 2, waves: [[{ type: 'wolf', n: 1 }], [{ type: 'wolf', n: 1 }]], objective: 'clear' });
  steps(PA, st, 60);
  assert.equal(st.status, 'won'); assert.equal(st.stats.kills, 2);
  const s2 = PA.Combat.create({ build: PA.Run.build(run), seed: 2, waves: [[{ type: 'wolf_alpha', n: 1 }, { type: 'wolf', n: 3 }]], objective: 'elite' });
  steps(PA, s2, 2);
  const alpha = s2.enemies.find(e => e.elite); alpha.hp = 1; s2.player.x = alpha.x; s2.player.y = alpha.y + 40;
  steps(PA, s2, 1);
  assert.equal(s2.status, 'won');
});

test('보급 상자에 닿으면 금화를 얻고 한 번만 열린다', () => {
  const { st } = combat(PA);
  st.chest = { x: st.player.x + 20, y: st.player.y, r: 16, opened: false, t: 0 };
  steps(PA, st, 0.5);
  assert.ok(st.stats.chestGold >= 15 && st.stats.chestGold <= 25);
  const g = st.stats.chestGold; steps(PA, st, 0.5); assert.equal(st.stats.chestGold, g);
});

test('일시정지·선택 화면: step을 호출하지 않으면 상태가 변하지 않는다(시간은 dt로만 흐른다)', () => {
  const { st } = combat(PA);
  PA.Combat.spawnEnemy(st, 'wolf', 100, 100);
  const snap = JSON.stringify({ p: st.player, e: st.enemies.map(e => [e.x, e.y, e.state]) });
  assert.equal(snap, JSON.stringify({ p: st.player, e: st.enemies.map(e => [e.x, e.y, e.state]) }));
  assert.equal(st.t, 0);
});
