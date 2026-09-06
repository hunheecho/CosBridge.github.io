const test = require('node:test');
const assert = require('node:assert/strict');
const { load, steps, runWith } = require('./load');
const { runBossFight } = require('./bot');
const PA = load();
const CB = PA.Combat, BZ = PA.Boss, CFG = () => PA.BOSS;

function bossFight(opts) {
  opts = opts || {};
  const run = runWith(PA, opts); if (opts.gear && opts.gear.acc) run.owned.push(opts.gear.acc);
  const st = CB.create({ build: PA.Run.build(run), seed: opts.seed || 5, boss: true, arena: 'clearing', waves: [] });
  if (!opts.keepIntro) { st.intro = 0; st.boss.state = 'approach'; st.boss.stateT = 0; st.boss.approachT = 9; }
  return st;
}
const step = (st, inp, dt) => CB.step(st, inp || {}, dt || PA.CONFIG.STEP);

test('입장 연출 중에는 시간·행동·피해가 없다', () => {
  const st = bossFight({ keepIntro: true });
  const b = st.boss; const x0 = b.x;
  steps(PA, st, 1.0, { mx: 1, my: 0 });
  assert.equal(st.t, 0); assert.equal(b.state, 'intro'); assert.equal(b.x, x0); assert.equal(st.player.x, PA.ARENAS.clearing.playerStart.x);
  assert.equal(CB.damagePlayer(st, 50, 'test'), false); assert.equal(st.player.hp, 100);
  steps(PA, st, 0.7); assert.equal(b.state, 'approach');
});

test('첫 공격은 단일 돌진, 첫 돌진 빈틈 뒤 첫 무리 소환. 소환 늑대는 발자국 예고 뒤 등장하고 즉시 돌진하지 않는다', () => {
  const st = bossFight(); const b = st.boss;
  const seq = [];
  for (let i = 0; i < 120 * 12; i++) { step(st, { mx: 0, my: 0 }); if (!seq.length || seq[seq.length - 1] !== b.state) seq.push(b.state); if (seq.includes('howl') && b.state === 'approach' && seq[seq.length - 1] === 'approach') break; }
  assert.deepEqual(JSON.parse(JSON.stringify(seq.slice(0, 6))), ['dash_aim', 'dash_lock', 'dash', 'recover', 'approach', 'howl']);
  assert.ok(st.pending.some(s => s.summoned) || st.enemies.some(e => e.summoned), '소환 예약/등장');
  steps(PA, st, CFG().howl.warn + 0.05);
  const wolves = st.enemies.filter(e => e.summoned);
  assert.equal(wolves.length, 2);
  for (const w of wolves) { assert.ok(w.grace > 0); assert.equal(w.state, 'approach'); assert.ok(CB.validPos(st, w.x, w.y, w.r)); }
});

test('돌진: 방향 확정 후 재추적 없음, 감속장 통과 시 경로·종료점 유지, 거리는 시간 감속으로 줄지 않는다', () => {
  const st = bossFight(); const b = st.boss, p = st.player;
  for (let i = 0; i < 120 * 5 && b.state !== 'dash_lock'; i++) step(st);
  assert.equal(b.state, 'dash_lock');
  const dir = b.dir, end = Object.assign({}, b.dashEnd), len = b.dashLen;
  // 감속장을 경로 위에 설치
  p.x = end.x; p.y = end.y - 60; st.field = { x: b.x + Math.cos(dir) * 150, y: b.y + Math.sin(dir) * 150, r: 150, ttl: 9, maxTtl: 9 };
  p.x += 200; // 플레이어가 크게 이동해도 방향은 그대로
  for (let i = 0; i < 120 * 6; i++) { step(st); if (b.state === 'recover') break; }
  assert.equal(b.dir, dir); assert.deepEqual([b.dashEnd.x, b.dashEnd.y], [end.x, end.y]);
  assert.ok(Math.abs(b.dashDist - len) < 1.5, `돌진 거리 ${b.dashDist.toFixed(1)} vs 예고 ${len.toFixed(1)}`);
  assert.ok(Math.abs(b.x - end.x) < 2 && Math.abs(b.y - end.y) < 2, '예고한 종료점에 도착');
});

test('돌진은 바위에 닿으면 접촉 위치에서 멈추고 정상 빈틈으로 전환하며, 바위 뒤 플레이어를 물지 않는다', () => {
  const st = bossFight(); const b = st.boss, p = st.player, rock = st.obstacles[0];
  b.x = rock.x; b.y = rock.y - rock.r - b.r - 140; p.x = rock.x; p.y = rock.y + rock.r + p.r + 8;
  b.state = 'dash_aim'; b.stateT = 0; b.approachT = 9;
  for (let i = 0; i < 120 * 6; i++) { step(st); if (b.state === 'recover') break; }
  assert.equal(b.state, 'recover'); assert.equal(p.hp, 100);
  assert.ok(b.y < rock.y, '바위 앞'); assert.ok(Math.abs(PA.m.dist(b, rock) - (rock.r + b.r)) < 3, '접촉 위치');
  assert.ok(Math.abs(b.dashEnd.y - b.y) < 3, '예고 종료점 = 실제 정지점');
});

test('휩쓸기: 표시된 부채꼴 안만 피해, 장애물 뒤는 무사, 대상당 1회, 이후 빈틈', () => {
  const inside = bossFight(); let b = inside.boss, p = inside.player;
  b.x = 480; b.y = 300; p.x = b.x + 100; p.y = b.y; b.state = 'sweep_aim'; b.stateT = 0;
  for (let i = 0; i < 120 * 3; i++) { step(inside); if (b.state === 'recover') break; }
  assert.equal(p.hp, 100 - CFG().sweep.damage); assert.equal(b.state, 'recover');
  const outside = bossFight(); b = outside.boss; p = outside.player;
  b.x = 480; b.y = 300; p.x = b.x + 100; p.y = b.y; b.state = 'sweep_aim'; b.stateT = 0; // 확정 직후 뒤로 이동
  for (let i = 0; i < 120 * 3; i++) { if (b.state === 'sweep_lock' && b.stateT === 0) { p.x = b.x - 100; } step(outside); if (b.state === 'recover') break; }
  assert.equal(p.hp, 100, '방향 확정 후 뒤로 간 플레이어는 맞지 않음');
  const blocked = bossFight(); b = blocked.boss; p = blocked.player; const rock = blocked.obstacles[0];
  b.x = rock.x - rock.r - b.r - 4; b.y = rock.y; p.x = rock.x + rock.r + p.r + 4; p.y = rock.y; b.state = 'sweep_aim'; b.stateT = 0;
  for (let i = 0; i < 120 * 3; i++) { step(blocked); if (b.state === 'recover') break; }
  assert.equal(p.hp, 100, '바위 뒤는 직접 공격이 관통하지 않음');
});

test('감속장은 보스의 준비·확정·돌진·빈틈 진행을 40%로 늦춘다', () => {
  const st = bossFight(); const b = st.boss;
  b.state = 'sweep_aim'; b.stateT = 0; st.player.x = b.x + 90; st.player.y = b.y + 300; // 멀리
  st.field = { x: b.x, y: b.y, r: 150, ttl: 9, maxTtl: 9 };
  steps(PA, st, 0.5);
  assert.ok(Math.abs(b.stateT - 0.2) < 0.02, `준비 진행 ${b.stateT.toFixed(3)} (0.5초 × 0.4)`);
  st.field = null; b.state = 'recover'; b.stateT = 0; b.recoverDur = 2; st.field = { x: b.x, y: b.y, r: 150, ttl: 9, maxTtl: 9 };
  steps(PA, st, 1.0); assert.ok(Math.abs(b.stateT - 0.4) < 0.02, '빈틈 회복도 감속');
});

test('냉기와 감속장의 이동 속도 중첩: 둘 다면 40%(곱하지 않음)', () => {
  const st = bossFight(); const b = st.boss;
  b.chill = 5; assert.ok(Math.abs(CB.enemySpeedMult(st, b) - 0.6) < 1e-9);
  st.field = { x: b.x, y: b.y, r: 150, ttl: 9, maxTtl: 9 }; assert.ok(Math.abs(CB.enemySpeedMult(st, b) - 0.4) < 1e-9);
  b.chill = 0; assert.ok(Math.abs(CB.enemySpeedMult(st, b) - 0.4) < 1e-9);
});

test('단계 전환: 진행 중 공격은 바뀌지 않고 끝난 뒤 포효로 전환, 중복 없음, 체력 경계 피해 잘림 없음, 구슬은 단계당 1개', () => {
  const st = bossFight(); const b = st.boss;
  b.state = 'sweep_aim'; b.stateT = 0;
  const dmg = CB.damageEnemy(st, b, 800, {}); // 2400 → 1600 (66%)
  assert.ok(dmg >= 800 - 1e-9); assert.equal(b.hp, 1600); assert.equal(b.phase, 1); assert.equal(b.phasePending, 2);
  assert.equal(st.pickups.length, 1, '70% 통과 시 구슬 1개');
  assert.equal(b.state, 'sweep_aim', '진행 중 공격 유지');
  for (let i = 0; i < 120 * 5; i++) { step(st); if (b.state === 'roar') break; }
  assert.equal(b.state, 'roar'); assert.equal(b.phase, 2);
  assert.deepEqual(JSON.parse(JSON.stringify(st.phaseEvents)), [2]);
  CB.damageEnemy(st, b, 900, {}); // 1600 → 700 (29%) : 35% 통과
  assert.equal(st.pickups.length, 2); assert.equal(b.phasePending, 3);
  CB.damageEnemy(st, b, 10, {}); assert.equal(st.pickups.length, 2, '중복 생성 없음');
  for (let i = 0; i < 120 * 6; i++) { step(st); if (b.phase === 3 && b.state === 'roar') break; }
  assert.equal(b.phase, 3); assert.deepEqual(JSON.parse(JSON.stringify(st.phaseEvents)), [2, 3]);
  for (const k of st.pickups) { assert.ok(CB.validPos(st, k.x, k.y, k.r)); assert.ok(PA.m.dist(k, b) > b.r + k.r + 20); }
});

test('한 번에 두 체력선을 넘기면 구슬 2개, 단계는 3으로 한 번에', () => {
  const st = bossFight(); const b = st.boss;
  CB.damageEnemy(st, b, 2000, {});
  assert.equal(st.pickups.length, 2); assert.equal(b.phasePending, 3);
  for (let i = 0; i < 120 * 3; i++) { step(st); if (b.state === 'roar') break; }
  assert.equal(b.phase, 3); assert.deepEqual(JSON.parse(JSON.stringify(st.phaseEvents)), [3]);
});

test('회복 구슬: 최대 체력의 15%(내림), 최대치 초과 없음, 같은 구슬 중복 없음, 시간 경과로 사라지지 않음', () => {
  const st = bossFight({ equipment: { armor: 'vitality_coat' } }); const p = st.player;
  assert.equal(p.hpMax, 120);
  st.pickups.push({ kind: 'heal', x: p.x, y: p.y, r: 14, amount: Math.floor(p.hpMax * 0.15), t: 0 });
  assert.equal(st.pickups[0].amount, 18);
  p.hp = 100; steps(PA, st, 0.05); assert.equal(p.hp, 118); assert.equal(st.pickups.length, 0);
  st.pickups.push({ kind: 'heal', x: 100, y: 100, r: 14, amount: 18, t: 0 }); steps(PA, st, 5); assert.equal(st.pickups.length, 1, '사라지지 않음');
  p.hp = 115; p.x = 100; p.y = 100; steps(PA, st, 0.05); assert.equal(p.hp, 120, '최대치 초과 없음');
});

test('3단계 돌진은 2연속: 두 번째도 새 준비·확정 예고, 첫 돌진이 장애물에 막혀도 즉시 발동하지 않음, 끝나면 빈틈 3초', () => {
  const st = bossFight(); const b = st.boss, p = st.player, rock = st.obstacles[0];
  b.phase = 3; b.x = rock.x; b.y = rock.y - rock.r - b.r - 120; p.x = rock.x; p.y = rock.y + 200;
  b.state = 'dash_aim'; b.stateT = 0; b.dashSeq = 1; b.dashTotal = 2; b.actions = 3; b.history = ['dash'];
  const seq = []; let secondAim = 0;
  for (let i = 0; i < 120 * 10; i++) { step(st); if (!seq.length || seq[seq.length - 1] !== b.state) seq.push(b.state); if (b.state === 'dash_aim' && b.dashSeq === 2) secondAim += PA.CONFIG.STEP; if (b.state === 'recover') break; }
  assert.deepEqual(seq, ['dash_aim', 'dash_lock', 'dash', 'dash_aim', 'dash_lock', 'dash', 'recover']);
  assert.ok(Math.abs(secondAim - CFG().dash.second.aim) < 0.03, `두 번째 준비 ${secondAim.toFixed(2)}초`);
  assert.equal(b.recoverDur, CFG().dash.doubleRecover);
});

test('덮쳐찍기(2단계): 유효한 착지점을 먼저 확정하고 추적하지 않으며, 착지 순간에만 원 범위 피해, 도약 중 피격 가능', () => {
  const st = bossFight(); const b = st.boss, p = st.player;
  b.phase = 2; b.x = 480; b.y = 120; p.x = 480; p.y = 520; b.state = 'pounce_aim'; b.stateT = 0;
  let land = null, hpDuringLeap = null, hitBefore = st.player.hp;
  for (let i = 0; i < 120 * 4; i++) {
    step(st);
    if (b.state === 'pounce_lock' && !land) { land = Object.assign({}, b.land); p.x = 200; p.y = 300; } // 확정 후 이동
    if (b.state === 'leap') { assert.deepEqual([b.land.x, b.land.y], [land.x, land.y]); if (hpDuringLeap == null) { hpDuringLeap = b.hp; CB.damageEnemy(st, b, 5, {}); assert.equal(b.hp, hpDuringLeap - 5, '도약 중 피격'); } }
    if (b.state === 'recover') break;
  }
  assert.ok(land && CB.validPos(st, land.x, land.y, b.r), '유효 착지점');
  assert.equal(b.state, 'recover'); assert.equal(st.player.hp, hitBefore, '원 밖이면 무사');
  // 원 안이면 착지 순간 1회
  const st2 = bossFight(); const b2 = st2.boss, p2 = st2.player; b2.phase = 2; b2.x = 480; b2.y = 120; p2.x = 480; p2.y = 520; b2.state = 'pounce_aim'; b2.stateT = 0;
  for (let i = 0; i < 120 * 4; i++) { step(st2); if (b2.state === 'recover') break; }
  assert.equal(p2.hp, 100 - CFG().pounce.damage);
  // 장애물 위 착지 요청 → 빈 공간으로 보정
  const st3 = bossFight(); const rock = st3.obstacles[0]; const l = BZ.landingFor(st3, st3.boss, rock.x, rock.y); assert.ok(CB.validPos(st3, l.x, l.y, st3.boss.r));
});

test('소환 늑대: 생존 4마리 제한, 소환 간격 18초, 돌진 준비·실행 동시 1마리, 보스 큰 공격 중 시작 금지', () => {
  const st = bossFight(); const b = st.boss, p = st.player; p.hp = 1e9;
  for (let k = 0; k < 4; k++) { b.state = 'howl'; b.stateT = CFG().howl.duration - 0.01; b.lastHowl = -999; step(st); steps(PA, st, CFG().howl.warn + 0.05); }
  const alive = st.enemies.filter(e => e.summoned && !e.dead).length; assert.ok(alive <= 4, `소환 ${alive}`);
  b.state = 'howl'; b.stateT = CFG().howl.duration - 0.01; b.lastHowl = -999; step(st); assert.equal(st.pending.filter(s => s.summoned).length, 0, '제한이면 추가 생성 없음');
  b.lastHowl = st.t; b.state = 'approach'; b.actions = 5; b.history = ['sweep', 'dash'];
  for (let i = 0; i < 200; i++) { /* 간격 안이면 howl 선택 불가 */ }
  // 겹침: 5초 진행하며 동시에 준비·돌진 중인 늑대가 2마리 이상인 순간이 없어야 한다
  let maxAttacking = 0, violation = false;
  for (let i = 0; i < 120 * 8; i++) {
    step(st, { mx: 0, my: 0 });
    const attacking = st.enemies.filter(e => e.summoned && !e.dead && ['crouch', 'lock', 'dash'].includes(e.state)).length;
    maxAttacking = Math.max(maxAttacking, attacking);
    const starting = st.enemies.filter(e => e.summoned && !e.dead && e.state === 'crouch' && e.stateT === 0).length;
    if (starting && BZ.bossCommitted(b)) violation = true;
  }
  assert.ok(maxAttacking <= 1, `동시 공격 늑대 ${maxAttacking}`); assert.equal(violation, false);
});

test('보스 사망: 같은 단계에서 플레이어도 죽으면 승리 우선, 사망 후 추가 피해 없음, 늑대 정지', () => {
  const st = bossFight(); const b = st.boss, p = st.player;
  const w = CB.spawnEnemy(st, 'wolf', p.x - 31, p.y); w.state = 'dash'; w.dir = 0; w.stateT = 0; w.summoned = true;
  p.hp = 5; b.hp = 1;
  // 늑대가 이 단계에서 물고(플레이어 사망), 같은 단계의 불길 틱이 보스를 죽인다
  st.zones.push({ type: 'fire', x: b.x, y: b.y, r: 40, ttl: 5, maxTtl: 5, dmg: 50, tick: 0, t: 0 }); st.build.aug.ember = 1;
  step(st);
  assert.equal(b.dead, true); assert.equal(st.status, 'won', '승리 우선');
  const hp = p.hp; steps(PA, st, 1.0); assert.equal(p.hp, hp, '추가 피해 없음');
  assert.equal(CB.damagePlayer(st, 30, 'x'), false);
});

test('보스 넉백 20%, 돌진 중 넉백 없음, 방벽 파열은 진행 중 공격을 끊고 1초 비틀거림(빈틈 배율), 중복 없음', () => {
  const st = bossFight({ augments: { barrier: 1 } }); const b = st.boss, p = st.player, wolf = CB.spawnEnemy(st, 'wolf', p.x + 60, p.y);
  b.x = p.x; b.y = p.y - 80; b.state = 'dash_aim'; b.stateT = 0.2;
  CB.damageEnemy(st, b, 10, { knock: 40, dir: { x: 0, y: -1 } }); const bossV = Math.abs(b.vy);
  CB.damageEnemy(st, wolf, 10, { knock: 40, dir: { x: 1, y: 0 } }); const wolfV = Math.abs(wolf.vx);
  assert.ok(Math.abs(bossV / wolfV - 0.2) < 1e-6, `보스 넉백 비율 ${(bossV / wolfV).toFixed(2)}`);
  b.vx = b.vy = 0; b.state = 'dash'; CB.damageEnemy(st, b, 10, { knock: 40, dir: { x: 0, y: -1 } }); assert.equal(b.vy, 0, '돌진 중 넉백 없음');
  b.state = 'dash_lock'; b.stateT = 0.1;
  p.hitProt = 0; CB.damagePlayer(st, 30, 't'); // 보호막 30 파괴
  assert.equal(p.shield, 0); assert.equal(b.state, 'stagger');
  const d = CB.damageEnemy(st, b, 10, {}); assert.ok(Math.abs(d - 15) < 1e-9, '비틀거림 중 빈틈 배율');
  steps(PA, st, 1.05); assert.equal(b.state, 'approach');
  // 도약 중이면 착지 후 적용
  b.state = 'leap'; b.leapFrom = { x: b.x, y: b.y }; b.land = BZ.landingFor(st, b, 480, 400); b.leapK = 0; b.airborne = true;
  BZ.stagger(st, b); assert.equal(b.state, 'leap'); assert.equal(b.staggerAfterLand, true);
});

test('표식: 보스가 최우선이지만 가려지거나 사거리 밖이면 공격 가능한 늑대를 때린다', () => {
  const st = bossFight({ augments: { mark: 1 } }); const b = st.boss, p = st.player;
  assert.equal(st.markTarget, b);
  const rock = st.obstacles[0]; b.x = rock.x + rock.r + b.r + 2; b.y = rock.y; p.x = rock.x - rock.r - p.r - 30; p.y = rock.y;
  const w = CB.spawnEnemy(st, 'wolf', p.x, p.y - 50); w.state = 'recover'; w.def = Object.assign({}, w.def, { recover: 999 }); w.hp = 1e6;
  assert.equal(st.markTarget, b, '표식은 보스 유지');
  assert.equal(CB.chooseTarget(st), w, '가려진 보스 대신 늑대');
  steps(PA, st, 0.5, {}, null, [[w, w.x, w.y]]); assert.ok(w.hp < 1e6);
});

test('시간 저축: 감속장 안 소환 늑대 처치로 재사용 감소, 관통·회전·정지된 칼날·파편이 보스에 적용된다', () => {
  const st = bossFight({ gear: { weapon: 'pierce' }, augments: { saving: 1, frost: 1, stasis: 1, spin: 1 } }); const b = st.boss, p = st.player;
  b.state = 'recover'; b.recoverDur = 999; b.x = p.x; b.y = p.y - 120;
  step(st, { special: true }); const cd = p.special.cd;
  const w = CB.spawnEnemy(st, 'wolf', p.x, p.y - 60); w.summoned = true; w.hp = 1;
  CB.damageEnemy(st, w, 5, {}); assert.ok(Math.abs(p.special.cd - (cd - 1)) < 1e-9, '소환 늑대 처치도 -1초');
  steps(PA, st, 0.8, {}, null, [[b, b.x, b.y]]);
  assert.ok(b.chill > 0, '보스 냉기'); assert.ok(b.stasis > 0, '보스 흔적'); assert.ok(st.stats.bossDamage > 0);
  assert.ok(st.stats.bossDamage <= 2400 - b.hp + 1e-6, '보스 피해 집계 = 실제 체력 감소');
});

test('재도전 결정성: 같은 시드·같은 입력이면 같은 결과', () => {
  const run = PA.Run.newRun(1); run.augments = { spin: 1 };
  const a = runBossFight(PA, run, 5, 60), b = runBossFight(PA, run, 5, 60);
  assert.deepEqual([a.status, a.t, a.boss.hp, a.player.hp, a.stats.kills], [b.status, b.t, b.boss.hp, b.player.hp, b.stats.kills]);
});

test('정책 봇 완주: 기본 장비도 승리 가능하며 강한 빌드는 더 빠르다(길이 참고값)', () => {
  const base = PA.Run.newRun(1); const sb = runBossFight(PA, base, 5, 400);
  const strong = runWith(PA, { gear: { upgrade: 3, acc: 'fang_necklace' }, growth: { weapons: [{ id: 'spear', level: 5, mods: ['returning', 'brand'] }, { id: 'blades', level: 4, mods: ['dual'] }, { id: 'orb', level: 3 }], commons: { stasis: 1, saving: 1, wide: 2 }, passives: { mastery: 3, haste: 2 } } }); strong.owned.push('fang_necklace');
  const ss = runBossFight(PA, strong, 5, 400);
  assert.equal(sb.status, 'won'); assert.equal(ss.status, 'won'); assert.ok(ss.t < sb.t / 2, `${ss.t.toFixed(0)}s vs ${sb.t.toFixed(0)}s`);
});
