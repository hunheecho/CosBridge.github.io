// 신규 몬스터 8종: 행동 요구와 경계 조건에서 출발한 검사(구현을 베끼지 않는다)
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, combat, steps } = require('./load');
const PA = load();
const CB = PA.Combat, E = PA.Enemies, m = PA.m;
const dt = PA.CONFIG.STEP;
const j = (x) => JSON.parse(JSON.stringify(x));
function setup(opts) { opts = opts || {}; const c = combat(PA, Object.assign({ hp: 100000 }, opts)); c.st.player.hpMax = 100000; c.st.player.hp = 100000; if (opts.noWeapons) c.st.weapons = []; return c; }
function pin(st, x, y) { st.player.x = x; st.player.y = y; }
function run(st, sec, input, pins) { steps(PA, st, sec, input || {}, dt, pins); }
function until(st, pred, maxSec, input, pins) { const n = Math.round((maxSec || 10) / dt); for (let i = 0; i < n; i++) { CB.step(st, input || {}, dt); if (pins) for (const [e, x, y] of pins) { e.x = x; e.y = y; e.vx = e.vy = 0; } if (pred()) return true; } return false; }

test('멧돼지: 준비 중에는 방향을 추적하고 확정 뒤에는 고정된 통로로만 이동한다. 예고 종료점과 실제 정지점이 일치한다', () => {
  const { st } = setup(); pin(st, 700, 300); const p = st.player;
  const b = CB.spawnEnemy(st, 'boar', 400, 300);
  assert.ok(until(st, () => b.state === 'charge_aim', 5, {}, [[p, 700, 300]]));
  p.y = 380; run(st, 0.3, {}, [[p, 700, 380]]); assert.ok(Math.abs(m.angDiff(b.aimAngle, Math.atan2(80, 300))) < 0.3, '준비 중 추적');
  assert.ok(until(st, () => b.state === 'charge_lock', 2, {}, [[p, 700, 380]])); const dir = b.dir, end = Object.assign({}, b.chargeEnd);
  p.y = 100; run(st, 0.3, {}, [[p, 700, 100]]); assert.equal(b.dir, dir, '확정 뒤 방향 고정');
  assert.ok(until(st, () => b.state === 'recover' || b.state === 'stagger', 3, {}, [[p, 700, 100]]));
  assert.ok(m.dist(b, end) < 6, `예고 종료점 ${JSON.stringify(end)} 실제 ${Math.round(b.x)},${Math.round(b.y)}`);
  const mt = st.metrics.enemies.boar; assert.equal(mt.prepared, 1); assert.equal(mt.executed, 1);
});

test('멧돼지: 바위에 부딪히면 긴 빈틈(stagger 2.4초)에 들어가고 빈틈 피해가 1.5배다. 감속장 안에서도 돌파 거리는 같다', () => {
  const { st } = setup(); st.obstacles.push({ id: 'rock', type: 'rock', x: 600, y: 300, r: 40 }); // 플레이어 뒤의 바위: 통로가 바위에서 끊긴다
  pin(st, 420, 300); const p = st.player; const b = CB.spawnEnemy(st, 'boar', 200, 300);
  assert.ok(until(st, () => b.state === 'charge', 6, {}, [[p, 420, 300]])); assert.equal(b.chargeBlocked, true); assert.ok(Math.abs(b.chargeEnd.x - (600 - 40 - b.r)) < 2, '예고 종료점 = 바위 접촉점');
  assert.ok(until(st, () => b.state === 'stagger', 3, {}, [[p, 420, 300]]), '충돌 → 비틀거림');
  assert.ok(b.x < 600 - 40 && b.x > 500, '바위 앞에서 정지');
  const before = b.hp; CB.damageEnemy(st, b, 10, { src: { weaponId: 'sword', direct: true } }); assert.equal(before - b.hp, 15, '빈틈 1.5배');
  let t0 = st.t; assert.ok(until(st, () => b.state === 'approach', 4, {}, [[p, 720, 300]])); assert.ok(st.t - t0 >= 2.3);
  // 감속장: 확정된 거리 그대로
  const { st: s2 } = setup(); pin(s2, 900, 300); const p2 = s2.player; const b2 = CB.spawnEnemy(s2, 'boar', 380, 300);
  assert.ok(until(s2, () => b2.state === 'charge', 6, {}, [[p2, 900, 300]])); const len = b2.chargeLen, x0 = b2.x;
  s2.field = { x: b2.x, y: b2.y, r: 400, ttl: 9, maxTtl: 9 };
  const t1 = s2.t; assert.ok(until(s2, () => b2.state !== 'charge', 6, {}, [[p2, 900, 300]])); assert.ok(s2.t - t1 > (len / 700) * 1.8, '감속 중 시간은 더 걸리고'); assert.ok(Math.abs((b2.x - x0) - len) < 8, '거리는 같다');
});

test('방패병: 정면 공격은 30%, 측면·후면은 정상, 방패치기 준비 중에는 정면도 정상. 방향 전환은 즉시 되지 않는다. 바닥 효과는 정상', () => {
  const { st } = setup({ noWeapons: true }); pin(st, 300, 300); const p = st.player;
  const sb = CB.spawnEnemy(st, 'shieldbearer', 500, 300); CB.step(st, {}, dt); // face 초기화(플레이어 쪽 = 왼쪽)
  const hit = (from, opt) => { const before = sb.hp; CB.damageEnemy(st, sb, 10, Object.assign({ src: { weaponId: 'sword', direct: true }, from }, opt || {})); return before - sb.hp; };
  assert.equal(hit({ x: 300, y: 300 }), 3, '정면 30%');
  assert.equal(hit({ x: 500, y: 100 }), 10, '측면 정상');
  assert.equal(hit({ x: 700, y: 300 }), 10, '후면 정상');
  assert.equal(hit({ x: 300, y: 300 }, { src: { extra: true, direct: false } }), 10, '바닥·추가 효과는 정상');
  const face0 = sb.face; pin(st, 500, 100); CB.step(st, {}, dt); assert.ok(Math.abs(m.angDiff(face0, sb.face)) < 0.1, '한 프레임에 90° 돌지 못함');
  run(st, 1.0, {}, [[p, 500, 100], [sb, 500, 300]]); assert.ok(Math.abs(m.angDiff(sb.face, -Math.PI / 2)) < 0.2, '1초면 따라 돈다');
  pin(st, 500, 240); assert.ok(until(st, () => sb.state === 'bash_aim', 4, {}, [[p, 500, 240], [sb, 500, 300]]));
  assert.equal(hit({ x: 500, y: 240 }), 10, '준비 중 방패 열림');
  assert.ok(until(st, () => sb.state === 'recover', 2, {}, [[p, 500, 240], [sb, 500, 300]])); assert.ok(st.metrics.taken.bash > 0, '방패치기 피해');
});

test('주술사: 다친 아군 하나를 골라 시전하고 30% 치료. 자기·다른 주술사·보스는 대상이 아니다. 12 이상 한 방이나 넉백으로 끊긴다', () => {
  const { st } = setup(); pin(st, 100, 500); const p = st.player;
  const sh = CB.spawnEnemy(st, 'shaman', 600, 300), sh2 = CB.spawnEnemy(st, 'shaman', 640, 300); sh.hp = 5; sh2.hp = 5;
  assert.equal(E.healTarget(st, sh), null, '주술사끼리·자신은 대상 아님');
  const bz = CB.spawnEnemy(st, 'boss', 700, 300); bz.hp = 100; assert.equal(E.healTarget(st, sh), null, '보스 제외(초기)'); bz.dead = true; sh.hp = 40; sh2.hp = 40;
  const w = CB.spawnEnemy(st, 'wolf', 650, 340); w.hp = 6; w.state = 'recover'; w.stateT = -99;
  assert.equal(E.healTarget(st, sh), w);
  sh.healT = 0; assert.ok(until(st, () => sh.state === 'cast', 3, {}, [[p, 100, 500], [w, 650, 340], [sh, 600, 300], [sh2, 640, 300]]));
  assert.ok(until(st, () => w.hp > 6, 3, {}, [[p, 100, 500], [w, 650, 340], [sh, 600, 300], [sh2, 640, 300]]), '치료 실행'); assert.equal(w.hp, 6 + 30 * 0.3); assert.equal(st.metrics.heals, 1);
  // 방해
  w.hp = 6; sh.healT = 0; sh.state = 'approach'; sh.stateT = 0; assert.ok(until(st, () => sh.state === 'cast', 4, {}, [[p, 100, 500], [w, 650, 340], [sh, 600, 300], [sh2, 640, 300]]));
  CB.damageEnemy(st, sh, 5, { src: { weaponId: 'sword', direct: true } }); assert.equal(sh.state, 'cast', '약한 한 방은 못 끊음');
  CB.damageEnemy(st, sh, 12, { src: { weaponId: 'sword', direct: true } }); assert.notEqual(sh.state, 'cast', '12 피해로 중단'); assert.equal(st.metrics.interrupts, 1);
  run(st, 1.5, {}, [[p, 100, 500], [w, 650, 340], [sh, 600, 300], [sh2, 640, 300]]); assert.equal(w.hp, 6, '중단된 시전은 치료하지 않는다');
});

test('주술사: 처치 대상이 없으면 저주 구슬을 쏘고, 치료 대상은 최대 체력을 넘지 않는다', () => {
  const { st } = setup(); pin(st, 300, 300); const p = st.player;
  const sh = CB.spawnEnemy(st, 'shaman', 560, 300); sh.hexT = 0; sh.healT = 99;
  assert.ok(until(st, () => st.projectiles.some(pr => pr.kind === 'hex'), 4, {}, [[p, 300, 300], [sh, 560, 300]]), '저주 구슬 발사');
  const w = CB.spawnEnemy(st, 'wolf', 600, 340); w.hp = 29; w.state = 'recover'; w.stateT = -99; sh.healT = 0; sh.state = 'approach';
  assert.ok(until(st, () => st.metrics.heals >= 1, 6, {}, [[p, 300, 300], [sh, 560, 300], [w, 600, 340]])); assert.equal(w.hp, 30);
});

test('폭탄 운반체: 준비 뒤 표시 반지름(95)대로 터지고, 준비 중 처치하면 터지지 않으며, 죽어도 예고 없는 폭발이 없다', () => {
  const { st } = setup({ noWeapons: true }); pin(st, 300, 300); const p = st.player;
  const bm = CB.spawnEnemy(st, 'bomber', 700, 300);
  assert.ok(until(st, () => bm.state === 'fuse', 6, {}, [[p, 300, 300]])); const fx = bm.x;
  assert.ok(m.dist(bm, p) <= 90 + bm.r + 2, '가까이 와서 멈춤');
  pin(st, bm.x - 95 - p.r - 5, 300); // 범위 바로 밖
  assert.ok(until(st, () => bm.dead, 2, {}, [[p, bm.x - 95 - p.r - 5, 300]])); assert.equal(bm.exploded, true); assert.equal(st.metrics.taken.blast, undefined, '범위 밖은 무피해'); assert.equal(st.stats.kills, 0, '자폭은 처치가 아니다');
  const { st: s2 } = setup({ noWeapons: true }); pin(s2, 300, 300); const b2 = CB.spawnEnemy(s2, 'bomber', 700, 300);
  assert.ok(until(s2, () => b2.state === 'fuse', 6, {}, [[s2.player, 300, 300]])); pin(s2, b2.x - 60, 300);
  assert.ok(until(s2, () => m.dist(b2, s2.player) <= 95, 1, {}, [[s2.player, b2.x - 60, 300]]) || true);
  CB.damageEnemy(s2, b2, 999, { src: { weaponId: 'sword', direct: true } }); run(s2, 2, {}, [[s2.player, b2.x - 60, 300]]);
  assert.equal(b2.exploded, undefined); assert.equal(s2.metrics.taken.blast, undefined, '준비 중 처치 → 폭발 없음');
  const { st: s3 } = setup({ noWeapons: true }); pin(s3, 300, 300); const b3 = CB.spawnEnemy(s3, 'bomber', 700, 300);
  assert.ok(until(s3, () => b3.state === 'fuse', 6, {}, [[s3.player, 300, 300]])); pin(s3, b3.x - 50, 300);
  assert.ok(until(s3, () => b3.dead, 2, {}, [[s3.player, b3.x - 50, 300]])); assert.equal(s3.metrics.taken.blast, 22, '범위 안 22');
});

test('잠복충: 지하 구간은 짧고(0.7초) 직접 공격 대상이 아니며, 출현 예고 뒤 위치가 바뀌지 않고, 지형 안에 출현하지 않는다. 출현 뒤 긴 빈틈, 다음 잠복까지 6초', () => {
  const { st } = setup({ growth: { weapons: [{ id: 'sword', level: 1 }] } }); st.obstacles.push({ id: 'rock', type: 'rock', x: 500, y: 300, r: 45 });
  pin(st, 560, 300); const p = st.player; const bw = CB.spawnEnemy(st, 'burrower', 340, 300); bw.burrowCd = 0;
  assert.ok(until(st, () => bw.state === 'under', 4, {}, [[p, 560, 300]]));
  assert.equal(bw.hidden, true); assert.equal(PA.Weapons.pickTarget(st, st.weapons[0], 9999, false), null, '지하는 대상 아님');
  const tU = st.t; assert.ok(until(st, () => bw.state === 'warn', 2, {}, [[p, 560, 300]])); assert.ok(st.t - tU <= 0.75);
  const at = Object.assign({}, bw.emergeAt); assert.ok(CB.validPos(st, at.x, at.y, bw.r), '출현 위치는 지형 밖');
  pin(st, 200, 100); run(st, 0.3, {}, [[p, 200, 100]]); assert.deepEqual([bw.emergeAt.x, bw.emergeAt.y], [at.x, at.y], '예고 뒤 재추적 없음');
  assert.ok(until(st, () => bw.state === 'stagger', 2, {}, [[p, 200, 100]])); assert.equal(bw.hidden, false); assert.ok(m.dist(bw, at) < 1);
  const tS = st.t; assert.ok(until(st, () => bw.state === 'approach', 4, {}, [[p, 200, 100]])); assert.ok(st.t - tS >= 1.9, '긴 빈틈');
  assert.ok(bw.burrowCd > 3, '반복 잠복 제한');
});

test('거미: 진행 방향 앞에 거미줄 예고 → 설치(최대 4개, 6초). 거미줄은 걷기만 50%로 늦추고 회피 거리는 그대로', () => {
  const { st } = setup(); pin(st, 300, 300); const p = st.player; p.face = 0;
  const sp = CB.spawnEnemy(st, 'spider', 480, 300); sp.webT = 0;
  assert.ok(until(st, () => sp.state === 'web_aim', 3, {}, [[p, 300, 300]])); assert.ok(Math.abs(sp.webAt.x - 370) < 30 && Math.abs(sp.webAt.y - 300) < 30, '앞쪽(70) 예고');
  assert.ok(until(st, () => st.zones.some(z => z.type === 'web'), 2, {}, [[p, 300, 300]])); const web = st.zones.find(z => z.type === 'web'); assert.equal(web.r, 55); assert.ok(Math.abs(web.ttl - 6) < 0.1);
  for (let i = 0; i < 6; i++) { sp.webT = 0; sp.state = 'approach'; sp.stateT = 0; until(st, () => st.zones.filter(z => z.type === 'web').length >= 1 && sp.state === 'recover', 3, {}, [[p, 300 + i * 10, 300]]); }
  assert.ok(st.zones.filter(z => z.type === 'web').length <= 4, '최대 4개');
  // 이동 비교
  const walk = (inWeb) => { const { st: s } = setup(); if (inWeb) { const z = CB.addZone(s, 'web', 480, 300, 55, 6, 0); z.slow = 0.5; } pin(s, 480, 300); const x0 = s.player.x; run(s, 0.2, { mx: 1, my: 0 }); return s.player.x - x0; };
  assert.ok(Math.abs(walk(true) / walk(false) - 0.5) < 0.05, '걷기 50%');
  const dodge = (inWeb) => { const { st: s } = setup(); if (inWeb) { const z = CB.addZone(s, 'web', 480, 300, 55, 6, 0); z.slow = 0.5; } pin(s, 480, 300); const x0 = s.player.x; CB.step(s, { dodge: true, mx: 1, my: 0 }, dt); run(s, 0.25); return s.player.x - x0; };
  assert.ok(Math.abs(dodge(true) - dodge(false)) < 1, '회피는 정상 거리');
});

test('서리술사: 영역 3개가 시전 시작 때 확정되어 옮겨지지 않고 1→2→3 순서로 터진다. 이미 터진 자리는 안전하다', () => {
  const { st } = setup(); pin(st, 300, 300); const p = st.player; p.moving = true; p.face = 0;
  const fc = CB.spawnEnemy(st, 'frostcaller', 560, 300); fc.castT = 0;
  assert.ok(until(st, () => fc.state === 'cast', 3, { mx: 1, my: 0 }, [[p, 300, 300]])); const pts = fc.castPts.map(q => ({ x: q.x, y: q.y }));
  assert.ok(Math.abs(pts[0].x - 300) < 5 && Math.abs(pts[1].x - 420) < 5 && Math.abs(pts[2].x - 540) < 5, '진행 방향으로 120 간격');
  pin(st, 300, 500); assert.ok(until(st, () => st.zones.filter(z => z.type === 'frostzone').length === 3, 2, {}, [[p, 300, 500]]));
  const zs = st.zones.filter(z => z.type === 'frostzone'); assert.deepEqual(j(zs.map(z => z.order)), [1, 2, 3]); assert.deepEqual(j(zs.map(z => Math.round(z.x))), j(pts.map(q => Math.round(q.x))), '플레이어가 움직여도 위치 그대로');
  const order = []; const t0 = st.t;
  until(st, () => { for (const z of zs) if (z.ttl <= 0 && !order.includes(z.order)) order.push(z.order); return order.length === 3; }, 4, {}, [[p, 300, 500]]);
  assert.deepEqual(j(order), [1, 2, 3]); assert.equal(st.metrics.taken.frostzone, undefined, '밖에 있으면 무피해');
  // 1번 자리에 서 있다가 1번이 터진 뒤 그대로 있으면 2·3은 맞지 않는다
  const { st: s2 } = setup(); pin(s2, 300, 300); s2.player.moving = true; s2.player.face = 0; const f2 = CB.spawnEnemy(s2, 'frostcaller', 560, 300); f2.castT = 0;
  assert.ok(until(s2, () => s2.zones.some(z => z.type === 'frostzone'), 3, { mx: 1, my: 0 }, [[s2.player, 300, 300]])); run(s2, 3, {}, [[s2.player, 300, 300]]);
  assert.equal(s2.metrics.taken.frostzone, 12, '1번만 맞는다'); assert.equal(s2.metrics.takenHits.frostzone, 1);
});

test('쌍날 도적: 측면으로 접근하고, 베기 2번을 각각 예고하며, 두 번째 방향 보정은 ±35° 안이다. 끝나면 빈틈. 순간이동·접촉 피해 없음', () => {
  const { st } = setup(); pin(st, 480, 300); const p = st.player;
  const r = CB.spawnEnemy(st, 'rogue', 200, 300); let maxStep = 0, lastX = r.x, lastY = r.y, contact = false;
  assert.ok(until(st, () => { const d = Math.hypot(r.x - lastX, r.y - lastY); if (d > maxStep) maxStep = d; lastX = r.x; lastY = r.y; if (m.dist(r, p) < 100 && r.state === 'approach' && Math.abs(r.y - 300) > 25) contact = true; return r.state === 'slash1_aim'; }, 6, {}, [[p, 480, 300]]));
  assert.ok(maxStep < 175 * dt * 1.5 + 0.5, '순간이동 없음'); assert.ok(contact, '측면 우회 경로');
  assert.equal(st.stats.damageTaken, 0, '접근 중 접촉 피해 없음');
  assert.ok(until(st, () => r.state === 'slash2_aim', 2, {}, [[p, 480, 300]])); const base = r.baseDir;
  pin(st, r.x + Math.cos(base + Math.PI / 2) * 60, r.y + Math.sin(base + Math.PI / 2) * 60); // 90° 옆으로
  run(st, 0.2, {}, [[p, p.x, p.y]]); assert.ok(Math.abs(m.angDiff(base, r.aimAngle)) <= 35 * Math.PI / 180 + 1e-6, '보정 한계');
  assert.ok(until(st, () => r.state === 'recover', 2, {}, [[p, p.x, p.y]])); assert.ok(r.recoverDur >= 1.5, '확실한 빈틈');
  assert.equal(st.metrics.enemies.rogue.prepared, 1); assert.equal(st.metrics.enemies.rogue.executed, 2);
});

test('공통: 감속장은 신규 적의 준비 시간을 늦추고, 신규 적의 예고 상태는 동시 공격 제한에 포함되며, 봇 위협 도형에 나타난다', () => {
  for (const [type, state] of [['bomber', 'fuse'], ['rogue', 'slash1_aim'], ['shieldbearer', 'bash_aim']]) {
    const t = (slow) => { const { st } = setup({ noWeapons: true }); pin(st, 480, 300); const e = CB.spawnEnemy(st, type, 480 + 40, 300); e.state = state; e.stateT = 0; if (type === 'shieldbearer') e.face = Math.PI; if (slow) st.field = { x: 480, y: 300, r: 200, ttl: 9, maxTtl: 9 }; const t0 = st.t; until(st, () => e.state !== state || e.dead, 5, {}, [[st.player, 480, 300], [e, 520, 300]]); return st.t - t0; };
    assert.ok(t(true) > t(false) * 2, type + ' 감속장 안 준비 시간 2배 이상');
    const { st } = setup(); const e = CB.spawnEnemy(st, type, 520, 300); e.state = state; e.stateT = 0.1; if (type === 'shieldbearer') e.face = Math.PI; if (type === 'rogue') e.aimAngle = Math.PI;
    assert.equal(CB.isCommitted(e), true, type + ' 동시 제한 포함');
    const out = []; E.threats(st, e, out); assert.ok(out.length >= 1, type + ' 위협 도형');
  }
});

test('데이터 표와 코드 일치: 신규 8종이 모두 ENEMIES에 있고 처리기·그림 대상이며, 단독 시험 프리셋이 존재한다', () => {
  const ids = ['boar', 'shieldbearer', 'shaman', 'bomber', 'burrower', 'spider', 'frostcaller', 'rogue'];
  for (const id of ids) { assert.ok(PA.ENEMIES[id], id); assert.ok(E.has(id), id + ' 처리기'); assert.ok(PA.Lab.enemyPreset('solo:' + id), id + ' 단독 프리셋'); assert.ok(E.COMMITTED[id].length >= 1); }
  assert.equal(Object.keys(PA.ENEMIES).filter(k => !PA.ENEMIES[k].boss && !PA.ENEMIES[k].elite).length, 11, '기본 몬스터 11종');
});
