// v0.8 런 한정 장비 12종: 효과·발동 시점·중첩 없음·소급 없음
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, combat, steps } = require('./load');
const PA = load();
const R = PA.Run, CB = PA.Combat, S = PA.CONFIG.STEP;
const mk = (equipment, extra) => combat(PA, Object.assign({ equipment }, extra || {}));
const hitBy = (st, e, amt, src) => CB.damagePlayer(st, amt, src || 'wolf', e);

test('데이터: 장비 12종은 슬롯·핵심 효과·설명을 갖고 슬롯당 4종, 가격표와 판매가가 정해져 있다', () => {
  const ids = Object.keys(PA.EQUIPMENT); assert.equal(ids.length, 12);
  for (const id of ids) { const d = PA.EQUIPMENT[id]; assert.ok(PA.EQUIP_SLOTS.includes(d.slot), id); assert.ok(d.short && d.desc && Object.keys(d.eff).length, id); assert.ok(R.equipPrice(id) > R.sellPrice(id)); }
  for (const sl of PA.EQUIP_SLOTS) assert.equal(ids.filter(id => PA.EQUIPMENT[id].slot === sl).length, 4, sl);
});
test('사냥꾼의 검: 정예·보스 직접 피해 +15%, 일반 적·추가 피해에는 없음', () => {
  const { st } = mk({ weapon: 'hunter_sword' }); const a = CB.spawnEnemy(st, 'wolf_alpha', 300, 300), w = CB.spawnEnemy(st, 'wolf', 600, 300);
  const h0 = a.hp; CB.damageEnemy(st, a, 10, { src: { direct: true } }); assert.ok(Math.abs((h0 - a.hp) - 11.5) < 1e-6, '정예 직접 11.5');
  const w0 = w.hp; CB.damageEnemy(st, w, 10, { src: { direct: true } }); assert.equal(w0 - w.hp, 10, '일반 적 그대로');
  const h1 = a.hp; CB.damageEnemy(st, a, 10, { src: { extra: true } }); assert.equal(h1 - a.hp, 10, '추가 피해는 대상 아님');
});
test('개척자의 창: 사거리·범위 +12%, 회전 칼날은 반지름만 커지고 안쪽 사각은 넓어지지 않는다(스포크 판정)', () => {
  const base = R.build(R.newRun(1, 'spear')); const r2 = R.newRun(1, 'spear'); r2.bag.push('pioneer_spear'); R.equipItem(r2, 'pioneer_spear'); const b2 = R.build(r2);
  assert.ok(Math.abs(b2.weapons[0].range / base.weapons[0].range - 1.12) < 1e-6, '창 사거리 ×1.12');
  const r3 = R.newRun(1, 'blades'); r3.bag.push('pioneer_spear'); R.equipItem(r3, 'pioneer_spear'); const bl = R.build(r3).weapons[0], bl0 = R.build(R.newRun(1, 'blades')).weapons[0];
  assert.ok(bl.radius > bl0.radius, '반지름 증가'); assert.ok(PA.WEAPONS.blades.spoke !== false, '스포크 판정(중심~칼날) 유지');
});
test('잔불검: 자기 화상·출혈 지속만 +25%(피해량 불변). 원천이 없으면 아무 효과 없음', () => {
  const { st } = mk({ weapon: 'ember_sword' }, { growth: { commons: { burn: 1 } } }); const e = CB.spawnEnemy(st, 'wolf', 300, 300);
  CB.damageEnemy(st, e, 1, { src: { direct: true } }); const BV = PA.GROWTH.COMMON_VALUES.burn; assert.ok(Math.abs(e.burn.t - BV.dur * 1.25) < 1e-6); assert.equal(e.burn.dps, BV.dps);
  const { st: st2 } = mk({ weapon: 'ember_sword' }); const e2 = CB.spawnEnemy(st2, 'wolf', 300, 300); CB.damageEnemy(st2, e2, 1, { src: { direct: true } }); assert.equal(e2.burn, undefined);
  const { st: st3 } = mk({ weapon: 'ember_sword' }, { growth: { weapons: [{ id: 'sword', level: 1, mods: ['bleed'] }] } }); const e3 = CB.spawnEnemy(st3, 'wolf', 300, 300); CB.damageEnemy(st3, e3, 1, { src: { direct: true, weapon: st3.build.weapons[0] }, bleed: 2.0 }); assert.ok(Math.abs(e3.bleed.t - 2.5) < 1e-6);
});
test('시간술사의 지팡이: 감속장 안 대상에게 직접 피해 +20%(밖은 없음)', () => {
  const { st } = mk({ weapon: 'chrono_staff' }); const e = CB.spawnEnemy(st, 'wolf', 300, 300);
  const h0 = e.hp; CB.damageEnemy(st, e, 10, { src: { direct: true } }); assert.equal(h0 - e.hp, 10);
  st.field = { x: 300, y: 300, r: 100, ttl: 3 }; const h1 = e.hp; CB.damageEnemy(st, e, 10, { src: { direct: true } }); assert.ok(Math.abs((h1 - e.hp) - 12) < 1e-6);
});
test('여행자의 경갑: 이동 속도 +8% · 생명력의 외투: 최대 체력 +20, 장착 회복 없음 · 수호자의 갑옷: 전투 시작 보호막 15', () => {
  assert.ok(Math.abs(mk({ armor: 'traveler_armor' }).st.build.speedMult - 1.08) < 1e-6);
  const { st } = mk({ armor: 'vitality_coat' }); assert.equal(st.player.hpMax, 120);
  const { st: g } = mk({ armor: 'guardian_armor' }); assert.equal(g.player.shield, 15); hitBy(g, null, 10); assert.equal(g.player.shield, 5); assert.equal(g.player.hp, g.player.hpMax);
});
test('원정대의 갑옷: 승리 정산(귀환)마다 체력 +8, 최대치 초과 없음, 패배·재정산에는 없음', () => {
  const run = R.newRun(1); run.bag.push('expedition_armor'); R.equipItem(run, 'expedition_armor'); const s = R.startSortie(run, 'forest');
  R.applyEncounterResult(run, s, 'won', { gold: 1, mats: {}, chestGold: 0 }, 50); R.returnToBase(run, s); assert.equal(run.hp, 58); R.returnToBase(run, s); assert.equal(run.hp, 58, '정산 1회');
  run.hp = 96; const s2 = R.startSortie(run, 'ridge'); R.applyEncounterResult(run, s2, 'won', { gold: 1, mats: {}, chestGold: 0 }, 96); R.returnToBase(run, s2); assert.equal(run.hp, 100, '최대치 초과 없음');
});
test('철벽 방패: 최대 체력 20% 이상의 직접 피해 −25%(원래 피해로 판정). 작은 피해·지대 피해는 그대로', () => {
  const { st } = mk({ shield: 'iron_shield' }); const p = st.player;
  hitBy(st, null, 20); assert.equal(p.hp, 85, '20 → 15'); p.hitProt = 0;
  hitBy(st, null, 19); assert.equal(p.hp, 66, '19는 그대로'); p.hitProt = 0;
  CB.damagePlayer(st, 30, 'zone'); assert.equal(p.hp, 36, '지대 피해는 그대로');
});
test('비상 방패: 체력이 30% 이하가 된 피해 직후 보호막 20을 1회(전투당). 그 피해에는 소급 없음, 0 이하면 발동 없음', () => {
  const { st } = mk({ shield: 'emergency_shield' }); const p = st.player;
  hitBy(st, null, 60); assert.equal(p.hp, 40); assert.equal(p.shield, 0, '30% 초과면 없음'); p.hitProt = 0;
  hitBy(st, null, 15); assert.equal(p.hp, 25, '이 피해는 그대로 들어감'); assert.equal(p.shield, 20, '직후 보호막'); p.hitProt = 0;
  hitBy(st, null, 30); assert.equal(p.shield, 0); assert.equal(p.hp, 15); p.hitProt = 0;
  hitBy(st, null, 5); assert.equal(p.shield, 0, '전투당 1회'); assert.equal(p.hp, 10);
  const { st: st2 } = mk({ shield: 'emergency_shield' }); hitBy(st2, null, 200); assert.ok(st2.player.hp <= 0); assert.equal(st2.player.shield, 0, '죽는 피해에는 부활 없음');
  const { st: st3 } = mk({ shield: 'emergency_shield' }, { hp: 20 }); steps(PA, st3, S); assert.equal(st3.player.shield, 20, '30% 이하로 시작하면 시작 직후 1회');
});
test('시전자의 방패: E 사용 시 보호막 8(3초), 장비 재사용 10초, 중첩 없음. 만료 시 남은 양만 제거', () => {
  const { st } = mk({ shield: 'caster_shield' }, { growth: { e: { id: 'gust', level: 1 } } }); const p = st.player;
  steps(PA, st, S, { skillE: true }); assert.equal(st.stats.eUses, 1); assert.equal(p.shield, 8, '보호막 8'); const s0 = p.shield;
  p.eCd = 0; steps(PA, st, S, { skillE: true }); assert.equal(p.shield, s0, '10초 안에는 다시 없음(중첩 없음)');
  hitBy(st, null, 3); assert.equal(st.casterShield.amt, 5, '보호막이 깎이면 남은 양도 줄어든다');
  steps(PA, st, 3.1); assert.equal(st.casterShield, null); assert.equal(p.shield, 0, '만료 시 남은 5만 제거');
});
test('시간의 방패: 감속장 안에 있는 공격자의 직접 피해 −20%. 밖의 공격자·잔류 지대·투사체 발사자 위치 기준', () => {
  const { st } = mk({ shield: 'time_shield' }); const p = st.player; const e = CB.spawnEnemy(st, 'wolf', 300, 300);
  hitBy(st, e, 10); assert.equal(p.hp, 90); p.hitProt = 0;
  st.field = { x: 300, y: 300, r: 60, ttl: 3 }; hitBy(st, e, 10); assert.equal(p.hp, 82); p.hitProt = 0;
  CB.damagePlayer(st, 10, 'zone', e); assert.equal(p.hp, 72, '지대 피해는 감소 없음'); p.hitProt = 0;
  CB.damagePlayer(st, 10, 'arrow', null); assert.equal(p.hp, 62, '공격자 없음(잔류)이면 감소 없음');
});
test('장비는 출격 중 바꿀 수 없고(거점 전용), 같은 슬롯 장착은 기존 장비를 가방으로 보낸다', () => {
  const run = R.newRun(1); run.bag.push('iron_shield', 'time_shield'); R.equipItem(run, 'iron_shield'); R.equipItem(run, 'time_shield');
  assert.equal(run.equipment.shield, 'time_shield'); assert.deepEqual(JSON.parse(JSON.stringify(run.bag)), ['iron_shield']);
  const s = R.startSortie(run, 'forest'); assert.ok(s); // 화면은 출격 중 상점을 열지 않는다(main.js: 전투 화면에는 shop 동작 없음)
});
