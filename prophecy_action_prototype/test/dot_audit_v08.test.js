// §4 지속 피해·발동 효과 검사: 장판 틱·겹침, 이동 적, 추가 효과 재귀 상한, 프레임 독립, 총 피해 = 실제 체력 감소
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, combat, steps } = require('./load');
const PA = load(); const CB = PA.Combat, S = PA.CONFIG.STEP;
const still = (st, e, x, y) => { e.state = 'idle'; e.x = x; e.y = y; };

test('불길 장판(불씨 정령): 정지한 적은 0.4초마다 1회, 장판을 벗어난 이동 적은 틱 없음, 겹친 장판은 각각 틱(장판 겹침은 규칙상 허용·기록)', () => {
  const { st } = combat(PA, { growth: { weapons: [{ id: 'ember', level: 1 }] } }); st.player.x = 100; st.player.y = 100;
  const e = CB.spawnEnemy(st, 'wolf_alpha', 500, 300); e.hp = 9999; still(st, e, 500, 300);
  const w = st.weapons[0]; const z = CB.addZone(st, 'fire', 500, 300, 40, 10, w.stats.damage); z.weapon = w;
  const h0 = e.hp; steps(PA, st, 2.0, {}, S, [[e, 500, 300]]); const ticks = Math.round((h0 - e.hp) / w.stats.damage);
  assert.ok(ticks >= 4 && ticks <= 5, `2초 동안 틱 ${ticks}(주기 0.4)`);
  const e2 = CB.spawnEnemy(st, 'wolf_alpha', 900, 500); e2.hp = 9999; still(st, e2, 900, 500); const h2 = e2.hp; steps(PA, st, 1.0, {}, S, [[e, 500, 300], [e2, 900, 500]]); assert.equal(e2.hp, h2, '장판 밖 적은 피해 없음');
  const z2 = CB.addZone(st, 'fire', 505, 300, 40, 10, w.stats.damage); z2.weapon = w; const h3 = e.hp; steps(PA, st, 1.0, {}, S, [[e, 500, 300], [e2, 900, 500]]); const ticks2 = Math.round((h3 - e.hp) / w.stats.damage); assert.ok(ticks2 >= 4 && ticks2 <= 6, `겹친 장판 2개: 1초 틱 ${ticks2}(각 2~3)`);
});
test('추가 효과 재귀 상한: 메아리는 메아리를 만들지 않고, 파편은 냉기를 다시 주지 않으며, 불꽃 파열은 연쇄해도 적 수를 넘지 않는다', () => {
  const { st } = combat(PA, { growth: { weapons: [{ id: 'sword', level: 1 }], commons: { echo: 1, frost: 1, ember: 1, flare: 1 } } });
  const p = st.player; const e = CB.spawnEnemy(st, 'wolf_alpha', p.x + 60, p.y); e.hp = 99999; still(st, e, p.x + 60, p.y);
  const m0 = st.metrics.hits.sword || 0; steps(PA, st, 4.0, {}, S, [[e, p.x + 60, p.y]]); const hits = (st.metrics.hits.sword || 0) - m0; const swings = Math.round(4.0 / st.build.weapons[0].interval);
  assert.ok(hits >= swings && hits <= swings + Math.ceil(swings / 4) + 1, `검격 ${swings}회에 메아리 ≤ ${Math.ceil(swings / 4)}회: 명중 ${hits}`);
  // 파편: 냉기 상태 처치 → 파편 6개. 파편에 맞은 적은 냉기가 생기지 않는다
  const a = CB.spawnEnemy(st, 'wolf', 400, 400); a.chill = 1; a.hp = 1; const b = CB.spawnEnemy(st, 'wolf', 430, 400); b.hp = 999; still(st, b, 430, 400); b.chill = 0; CB.damageEnemy(st, a, 5, { src: { direct: true } }); assert.ok(a.dead); assert.ok(st.projectiles.some(pr => pr.kind === 'shard_common'));
  steps(PA, st, 0.5, {}, S, [[b, 430, 400]]); assert.equal(b.chill, 0, '파편은 냉기를 다시 부여하지 않음');
  // 불꽃 파열 연쇄: 불길 위 적 5마리(체력 1)를 하나 처치 → 연쇄 폭발은 최대 4회(적 수 상한), 무한 루프 없음
  st.zones.length = 0; CB.addZone(st, 'fire', 700, 300, 120, 5, 0); const group = []; for (let i = 0; i < 5; i++) { const g = CB.spawnEnemy(st, 'wolf', 700 + i * 20, 300); g.hp = 1; group.push(g); }
  const ev0 = st.events.filter(f => f.name === 'explode').length; CB.damageEnemy(st, group[0], 5, { src: { direct: true } }); const flares = st.events.filter(f => f.name === 'explode').length - ev0; assert.ok(flares >= 1 && flares <= 5, `파열 ${flares}회`); assert.ok(group.every(g => g.dead));
});
test('프레임 독립: 화상·출혈·장판·감속장 흔적의 4초 총 피해가 60fps와 120fps에서 같다(틱 반올림 오차 ≤ 1틱)', () => {
  const total = (dt) => { const { st } = combat(PA, { growth: { weapons: [{ id: 'ember', level: 1 }, { id: 'sword', level: 1, mods: ['bleed'] }], commons: { burn: 1 } } }); st.player.x = 100; st.player.y = 100; const e = CB.spawnEnemy(st, 'wolf_alpha', 600, 300); e.hp = 9999; still(st, e, 600, 300);
    const w = st.weapons[0]; const z = CB.addZone(st, 'fire', 600, 300, 40, 5, w.stats.damage); z.weapon = w; CB.damageEnemy(st, e, 0.1, { src: { direct: true, weapon: st.build.weapons[1] }, bleed: 2.0 }); const h = e.hp; steps(PA, st, 4.0, {}, dt, [[e, 600, 300]]); return h - e.hp; };
  const a = total(1 / 120), b = total(1 / 60); assert.ok(Math.abs(a - b) <= 6, `120fps ${a} vs 60fps ${b}`);
});
test('총 피해 대조: 출처별 유효 피해 합 = 적 실제 체력 감소 합(과잉 피해 제외), 이동하는 적 포함', () => {
  const { st } = combat(PA, { growth: { weapons: [{ id: 'sword', level: 2 }, { id: 'ember', level: 1 }], commons: { burn: 1 } } }); const p = st.player;
  const es = [CB.spawnEnemy(st, 'wolf', p.x + 70, p.y), CB.spawnEnemy(st, 'wolf_alpha', p.x - 80, p.y + 30), CB.spawnEnemy(st, 'archer', p.x + 200, p.y - 100)]; const hp0 = es.map(e => e.hp);
  steps(PA, st, 6.0); // 적은 자유롭게 이동·공격
  const lost = es.reduce((a, e, i) => a + (hp0[i] - Math.max(0, e.hp)), 0); const dealt = Object.values(st.metrics.dmg).reduce((a, b) => a + b, 0);
  assert.ok(Math.abs(lost - dealt) <= 1.0, `체력 감소 ${lost.toFixed(1)} vs 집계 ${dealt.toFixed(1)}`); assert.ok(dealt > 0);
});
test('보스 크기: 검격 한 번에 보스는 한 번만, 회전 칼날은 살 2개가 동시에 겹쳐도 접촉 주기당 한 번', () => {
  const { st } = combat(PA, { growth: { weapons: [{ id: 'sword', level: 1 }] } }); const p = st.player; const bz = CB.spawnEnemy(st, 'boss', p.x + 90, p.y); bz.hp = 99999; bz.state = 'idle'; bz.dummy = true;
  const h0 = (st.metrics.hits.sword || 0); steps(PA, st, 2.0, {}, S, [[bz, p.x + 90, p.y]]); const hits = (st.metrics.hits.sword || 0) - h0; const swings = Math.round(2.0 / st.build.weapons[0].interval); assert.ok(hits <= swings + 1 && hits >= swings - 1, `검격 ${swings}회 → 보스 명중 ${hits}`);
  const { st: s2 } = combat(PA, { growth: { weapons: [{ id: 'blades', level: 1, mods: ['dual'] }] } }); const p2 = s2.player; const b2 = CB.spawnEnemy(s2, 'boss', p2.x + 50, p2.y); b2.hp = 99999; b2.state = 'idle'; b2.dummy = true;
  steps(PA, s2, 2.0, {}, S, [[b2, p2.x + 50, p2.y]]); const bh = s2.metrics.hits.blades || 0; const gap = PA.WEAPONS.blades.base.hitGap; assert.ok(bh >= Math.floor(2 / gap) - 1 && bh <= Math.ceil(2 / gap) + 1, `칼날 3개·큰 보스 2초 명중 ${bh}(주기 ${gap})`);
});
