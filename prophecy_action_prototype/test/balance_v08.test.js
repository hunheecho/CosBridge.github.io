// v0.8 전투 점검: 회전 칼날 사각·접촉, 지속 피해 감사(중첩·갱신·틱·프레임·감속장·보스 크기), 피해 통계(출처·DPS 분모·보스 분리·저장)
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, combat, steps, fakeStorage } = require('./load');
const PA = load();
const R = PA.Run, CB = PA.Combat, S = PA.CONFIG.STEP;
const j = (x) => JSON.parse(JSON.stringify(x));

test('회전 칼날: 궤도 안쪽(반지름 35%~100%)에 붙은 적도 살 판정으로 맞고, 세 번째 칼날 개조는 같은 궤도에 칼날 +1', () => {
  const { st } = combat(PA, { growth: { weapons: [{ id: 'blades', level: 1 }] } }); const p = st.player, w = st.weapons[0];
  const near = CB.spawnEnemy(st, 'wolf', p.x + 40, p.y); near.state = 'idle'; const far = CB.spawnEnemy(st, 'wolf', p.x + 300, p.y);
  const h0 = near.hp; steps(PA, st, 1.0, {}, S, [[near, p.x + 40, p.y], [far, p.x + 300, p.y]]);
  assert.ok(near.hp < h0, '반지름 78 궤도 안쪽 40 거리의 적도 맞는다(이전 판정은 사각)'); assert.equal(far.hp, far.hpMax || far.hp, '멀리 있는 적은 안 맞음');
  assert.equal(w.bladePos.length, 2); assert.ok(w.bladePos[0].ix != null, '살 시작점 표시(그리기와 판정 동일)');
  const { st: st2 } = combat(PA, { growth: { weapons: [{ id: 'blades', level: 1, mods: ['dual'] }] } }); steps(PA, st2, S); assert.equal(st2.weapons[0].bladePos.length, 3, '칼날 3개');
  // 접촉 빈도: 같은 적은 hitGap(0.45초)마다 1회
  const { st: st3 } = combat(PA, { growth: { weapons: [{ id: 'blades', level: 1 }] } }); const p3 = st3.player; const e3 = CB.spawnEnemy(st3, 'wolf_alpha', p3.x + 60, p3.y); e3.hp = 99999; e3.state = 'idle';
  const n0 = st3.weapons[0].count; steps(PA, st3, 2.0, {}, S, [[e3, p3.x + 60, p3.y]]); const hits = st3.weapons[0].count - n0; assert.ok(hits >= 3 && hits <= 5, `2초 동안 접촉 ${hits}회(주기 0.45)`);
});
test('지속 피해 감사: 화상은 중첩 없이 시간만 갱신, 출혈은 높은 dps로 대체, 틱 0.5초, 60/120fps 총량 동일, 감속장 증폭 없음, 큰 보스도 한 틱에 한 번', () => {
  const mkb = () => combat(PA, { growth: { weapons: [{ id: 'sword', level: 1, mods: ['bleed'] }], commons: { burn: 1 } } });
  const { st } = mkb(); const e = CB.spawnEnemy(st, 'wolf_alpha', 400, 400); e.hp = 9999; const BV = PA.GROWTH.COMMON_VALUES.burn;
  CB.damageEnemy(st, e, 1, { src: { direct: true } }); const t1 = e.burn.t; steps(PA, st, 0.3, {}, S, [[e, 400, 400]]); CB.damageEnemy(st, e, 1, { src: { direct: true } });
  assert.ok(Math.abs(e.burn.t - BV.dur) < 1e-6 && e.burn.dps === BV.dps, '두 번째 적중은 시간 갱신만(중첩 없음)'); assert.ok(t1 === BV.dur);
  const w = st.build.weapons[0]; CB.damageEnemy(st, e, 1, { src: { direct: true, weapon: w }, bleed: 2 }); const d1 = e.bleed.dps; CB.damageEnemy(st, e, 1, { src: { direct: true, weapon: Object.assign({}, w, { damage: w.damage * 2 }) }, bleed: 2 }); assert.ok(e.bleed.dps > d1, '높은 dps로 대체'); CB.damageEnemy(st, e, 1, { src: { direct: true, weapon: Object.assign({}, w, { damage: 1 }) }, bleed: 2 }); assert.ok(e.bleed.dps > d1, '낮은 dps는 대체하지 않음');
  // 틱 총량: 60fps vs 120fps
  const total = (dt) => { const { st: s2 } = mkb(); const x = CB.spawnEnemy(s2, 'wolf_alpha', 400, 400); x.hp = 9999; x.state = 'idle'; s2.player.x = 100; s2.player.y = 100; CB.damageEnemy(s2, x, 0.1, { src: { direct: true } }); const h = x.hp; steps(PA, s2, 4.0, {}, dt, [[x, 400, 400]]); return Math.round((h - x.hp) * 10) / 10; };
  const a = total(1 / 120), b = total(1 / 60); assert.ok(Math.abs(a - b) <= BV.dps * 0.5 + 0.1, `틱 총량 120fps ${a} vs 60fps ${b}`); assert.ok(a > 0);
  // 감속장 안에서 지속 피해가 늘지 않는다(감속은 적 행동만)
  const { st: s3 } = mkb(); const y = CB.spawnEnemy(s3, 'wolf_alpha', 400, 400); y.hp = 9999; y.state = 'idle'; s3.player.x = 100; s3.player.y = 100; CB.damageEnemy(s3, y, 0.1, { src: { direct: true } }); const hy = y.hp; s3.field = { x: 400, y: 400, r: 120, ttl: 10 }; steps(PA, s3, 4.0, {}, S, [[y, 400, 400]]); assert.ok(Math.abs((hy - y.hp) - a) <= BV.dps * 0.5 + 0.1, '감속장 안 총량 동일');
  // 보스(큰 반지름): 한 틱에 한 번(1초 동안 화상 틱 ≤ 2)
  const { st: s4 } = combat(PA, { growth: { commons: { burn: 1 } } }); const bz = CB.spawnEnemy(s4, 'boss', 500, 300); bz.hp = 99999; bz.state = 'idle'; s4.player.x = 100; s4.player.y = 100; CB.damageEnemy(s4, bz, 0.1, { src: { direct: true } }); const m0 = s4.metrics.dmg['dot:burn'] || 0; steps(PA, s4, 1.0, {}, S, [[bz, 500, 300]]); const ticks = Math.round(((s4.metrics.dmg['dot:burn'] || 0) - m0) / (BV.dps * 0.5)); assert.ok(ticks <= 2 && ticks >= 1, `보스 1초 화상 틱 ${ticks}`);
});
test('피해 통계: 출처별 유효 피해(과잉 제외)·비중·DPS 분모(기술 보유 시간), 보스 성공/실패 분리, 합계 검증, 저장 유지', () => {
  const run = R.newRun(1, 'sword'); const s = R.startSortie(run, 'forest'); const st = PA.Flow.makeEncounter(run, s); st.waveIndex = 99; st.pending = []; st.spawnedAll = true;
  const keep = CB.spawnEnemy(st, 'wolf_alpha', 900, 500); keep.hp = 99999; keep.state = 'idle'; /* 전투 유지용 */ const e = CB.spawnEnemy(st, 'wolf', 300, 300); e.hp = 10; CB.damageEnemy(st, e, 50, { src: { weaponId: 'sword', direct: true } });
  assert.equal(st.metrics.dmg['weapon:sword'], 10, '과잉 피해 40 제외');
  st.player.x = 100; st.player.y = 100; steps(PA, st, 2.0, {}, S, [[keep, 900, 500]]); assert.ok(st.t > 1.9 && Math.abs(st.activeT['weapon:sword'] - st.t) < 1e-6, '보유 시간 = 실제 전투 시간');
  // 전투 중 무기 추가: 그 시점부터 보유 시간
  run.growth.weapons.push({ id: 'blades', level: 1, mods: [] }); CB.rebuild(st, R.build(run)); steps(PA, st, 1.0, {}, S, [[keep, 900, 500]]); assert.ok(st.activeT['weapon:blades'] < st.activeT['weapon:sword'] && Math.abs(st.activeT['weapon:blades'] - 1.0) < 0.02);
  for (const x of st.enemies) x.dead = true; st.status = 'won'; PA.Flow.settleVictory(run, s, st); PA.Flow.settleVictory(run, s, st); assert.equal(run.dmgStats.combats.length, 1, '정산 1회만 기록');
  const b = R.startBoss(Object.assign(run, { day: 3, phase: 'boss_prep' })); const bs = PA.Flow.makeBossEncounter(run, b); bs.intro = 0; CB.damageEnemy(bs, bs.boss, 100, { src: { weaponId: 'sword', direct: true } }); steps(PA, bs, 0.5); bs.status = 'lost'; PA.Flow.settleBossDefeat(run, bs);
  const b2 = R.startBoss(run); const bs2 = PA.Flow.makeBossEncounter(run, b2); bs2.intro = 0; CB.damageEnemy(bs2, bs2.boss, 200, { src: { weaponId: 'sword', direct: true } }); steps(PA, bs2, 1.0); bs2.status = 'won'; PA.Flow.settleBossVictory(run, bs2);
  const V = PA.Stats.views(run); assert.equal(V.bossFailed.total, 100); assert.equal(V.boss.total, 200); assert.equal(V.all.total, 310); assert.equal(V.sortie.total, 10);
  const row = V.all.rows.find(r => r.key === 'weapon:sword'); assert.ok(Math.abs(row.dps - 310 / row.active) < 0.1); assert.equal(row.share, 100);
  assert.ok(PA.Stats.verify(run).every(v => v.ok), JSON.stringify(PA.Stats.verify(run)));
  const store = fakeStorage(); R.save(run, store); const back = R.load(store); assert.deepEqual(j(PA.Stats.views(back)), j(V), '저장·복구 후 동일');
});
