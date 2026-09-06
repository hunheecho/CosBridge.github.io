const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'), path = require('path');
const { load, fakeStorage, ORDER } = require('./load');
const PA = load();
const R = PA.Run;
const j = (x) => JSON.parse(JSON.stringify(x)); // vm 컨텍스트 프로토타입 차이를 없앤다

test('index.html의 스크립트 순서가 테스트 로더의 순서와 일치한다', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const tags = [...html.matchAll(/<script src="src\/(\w+)\.js"><\/script>/g)].map(m => m[1]);
  assert.deepEqual(tags.slice(0, ORDER.length), ORDER);
});

test('빌드 파생: 증강·강화가 정확히 한 번씩 곱해진다', () => {
  const run = R.newRun(1); run.augments.sharp = 2; run.gear.upgrade = 1; run.augments.quick = 1; run.augments.wide = 1;
  const b = R.build(run);
  assert.ok(Math.abs(b.damage - 12 * 1.5 * 1.15) < 1e-9);
  assert.ok(Math.abs(b.interval - 0.55 * 0.85) < 1e-9);
  assert.ok(Math.abs(b.range - 95 * 1.25) < 1e-9);
  assert.equal(PA.Build.hitsToKill(b, 'wolf'), Math.ceil(30 / b.damage));
});

test('증강: 최대 단계·전제 조건을 지키며, 제시 목록에 무효 선택이 없다', () => {
  const run = R.newRun(1);
  R.takeAugment(run, 'sharp'); R.takeAugment(run, 'sharp'); R.takeAugment(run, 'sharp');
  assert.equal(run.augments.sharp, 3);
  assert.throws(() => R.takeAugment(run, 'sharp'));
  assert.throws(() => R.takeAugment(run, 'flare'), '잔불 걸음 없이 불꽃 파열 불가');
  const rng = PA.rng.create(5);
  for (let i = 0; i < 50; i++) for (const a of R.augmentOffers(run, rng, 3)) { assert.notEqual(a.id, 'sharp'); assert.notEqual(a.id, 'flare'); }
  R.takeAugment(run, 'ember');
  let seen = false; for (let i = 0; i < 100; i++) if (R.augmentOffers(run, rng, 3).some(a => a.id === 'flare')) seen = true;
  assert.ok(seen, '잔불 걸음 이후에는 불꽃 파열이 제시됨');
  R.takeAugment(run, 'spin'); assert.throws(() => R.takeAugment(run, 'spin'), '1회 증강 중복 불가');
});

test('조우 간 유지/제거: 증강·장비·체력은 유지되고 보호막·감속장·지역은 새 조우에서 초기화된다', () => {
  const run = R.newRun(1); run.augments.barrier = 1; run.hp = 55;
  const st = PA.Combat.create({ build: R.build(run), hp: run.hp, seed: 1, waves: [], objective: 'clear' });
  st.player.shield = 0; st.field = { x: 0, y: 0, r: 1, ttl: 9, maxTtl: 9 }; PA.Combat.addZone(st, 'spore', 1, 1, 10, 9, 1);
  const st2 = PA.Combat.create({ build: R.build(run), hp: st.player.hp, seed: 2, waves: [], objective: 'clear' });
  assert.equal(st2.player.shield, 30); assert.equal(st2.field, null); assert.equal(st2.zones.length, 0); assert.equal(st2.player.hp, 55);
  assert.equal(st2.build.has('barrier'), true);
});

test('구매·제작: 비용이 정확히 차감되고 즉시 장착되어 전투 수치에 반영된다', () => {
  const run = R.newRun(1);
  const it = R.item('pierce_sword');
  assert.equal(R.canBuy(run, it), false);
  assert.throws(() => R.buy(run, 'pierce_sword'));
  run.gold = 300; run.mats.pelt = 3; run.mats.iron = 2;
  assert.equal(R.canBuy(run, it), true);
  R.buy(run, 'pierce_sword');
  assert.equal(run.gold, 40); assert.equal(run.mats.pelt, 0); assert.equal(run.mats.iron, 0);
  assert.equal(run.gear.weapon, 'pierce');
  assert.equal(R.build(run).weapon.form, 'beam');
  assert.equal(R.itemAvailable(run, it), false);
  assert.notEqual(run.target, 'pierce_sword', '목표 달성 후 다음 목표로');
  // 강화 3단계 비용 진행
  run.gold = 1000; run.mats.iron = 3;
  R.buy(run, 'whetstone'); R.buy(run, 'whetstone'); R.buy(run, 'whetstone');
  assert.equal(run.gear.upgrade, 3); assert.equal(run.gold, 1000 - 80 - 140 - 220); assert.equal(run.mats.iron, 0);
  assert.equal(R.itemAvailable(run, R.item('whetstone')), false);
  assert.ok(Math.abs(R.build(run).damage - 14 * 1.45) < 1e-9);
  // 장신구/방어구
  run.gold = 500; run.mats.spore = 1; run.mats.pelt = 2;
  R.buy(run, 'time_charm'); R.buy(run, 'leather_armor');
  const b = R.build(run);
  assert.equal(b.hpMax, 130); assert.equal(b.specialCd, 11); assert.equal(b.dodgeCdMult, 0.7);
});

test('재료 판매와 목표 안내', () => {
  const run = R.newRun(1); run.mats.pelt = 2;
  R.sell(run, 'pelt', 1); assert.equal(run.gold, 75); assert.equal(run.mats.pelt, 1);
  const t = R.targetInfo(run);
  assert.equal(t.item.id, 'pierce_sword');
  const pelt = t.needs.find(n => n.kind === 'pelt'); assert.equal(pelt.need, 2); assert.deepEqual(j(pelt.where), ['근교 숲', '늑대 굴']);
  assert.equal(t.needs.find(n => n.kind === 'gold').need, 185);
});

test('하루 일정: 출격·더 깊이·휴식 비용과 하루 종료·보스 도래', () => {
  const run = R.newRun(1);
  assert.equal(R.canSortie(run, 'deep'), true);
  const s = R.startSortie(run, 'deep'); assert.equal(run.hours, 2);
  assert.equal(R.canSortie(run, 'deep'), false, '3시간 필요');
  assert.equal(R.canSortie(run, 'forest'), true);
  R.deepExplore(run, s); assert.equal(run.hours, 1); assert.equal(s.deep, true);
  run.hp = 10; R.rest(run); assert.equal(run.hours, 0); assert.equal(run.hp, 100);
  assert.throws(() => R.rest(run));
  assert.throws(() => R.deepExplore(run, s), '시간 0이면 더 깊이 불가');
  for (let d = 1; d < 6; d++) { R.endDay(run); assert.equal(run.day, d + 1); assert.equal(run.hours, 5); assert.equal(run.ended, false); }
  R.endDay(run); assert.equal(run.day, 7); assert.equal(run.ended, true); assert.equal(R.canSortie(run, 'forest'), false);
});

test('더 깊이 탐험 웨이브: 적 +1, 마지막에 정예. 보상 배율과 송곳니 조건', () => {
  const w = R.encounterWaves('forest', true);
  assert.equal(w[0][0].n, 3); assert.ok(w[2].some(g => g.type === 'wolf_alpha'));
  assert.equal(R.encounterObjective('forest', true), 'elite');
  const run = R.newRun(1); const s = { regionId: 'den', deep: false };
  const rng = PA.rng.create(3);
  const noElite = R.rollReward(run, s, rng, { eliteKilled: false }); assert.equal(noElite.mats.fang, undefined);
  const withElite = R.rollReward(run, s, PA.rng.create(3), { eliteKilled: true }); assert.equal(withElite.mats.fang, 1);
  const deepR = R.rollReward(run, { regionId: 'forest', deep: true }, PA.rng.create(3), {});
  assert.ok(deepR.gold >= Math.round(30 * 1.5));
});

test('승리 귀환은 전리품을 더하고, 패배는 전리품을 잃고 1시간·체력 30%가 된다', () => {
  const run = R.newRun(1); const s = R.startSortie(run, 'forest');
  R.applyEncounterResult(run, s, 'won', { gold: 40, mats: { pelt: 2 }, chestGold: 20 }, 70);
  assert.equal(run.hp, 70); assert.equal(s.loot.gold, 60); assert.equal(run.gold, 60, '귀환 전에는 반영 안 됨');
  R.returnToBase(run, s); assert.equal(run.gold, 120); assert.equal(run.mats.pelt, 2);
  const s2 = R.startSortie(run, 'forest');
  R.applyEncounterResult(run, s2, 'won', { gold: 40, mats: { pelt: 1 }, chestGold: 0 }, 50);
  R.applyEncounterResult(run, s2, 'lost', null, 0);
  R.defeat(run, s2);
  assert.equal(run.gold, 120); assert.equal(run.mats.pelt, 2); assert.equal(run.hours, 2); assert.equal(run.hp, 30);
});

test('저장·복구: 핵심 상태가 동일하다', () => {
  const st = fakeStorage();
  const run = R.newRun(1); run.gold = 321; run.mats.pelt = 4; run.augments.spin = 1; run.augments.sharp = 2; run.gear.armor = 'leather_armor'; run.owned.push('leather_armor'); run.day = 3; run.hours = 2; run.hp = 77; run.target = 'time_charm';
  assert.equal(R.save(run, st), true);
  const back = R.load(st);
  assert.deepEqual(j(back), j(run));
  assert.equal(R.build(back).hpMax, 130);
  R.clearSave(st); assert.equal(R.load(st), null);
});

test('시드가 같으면 전투가 동일하게 재현된다', () => {
  const run = R.newRun(1);
  const play = () => { const st = PA.Combat.create({ build: R.build(run), seed: 42, waves: PA.REGIONS[1].waves, objective: 'clear' }); for (let i = 0; i < 120 * 30; i++) PA.Combat.step(st, { mx: i % 240 < 120 ? 1 : -1, my: 0, dodge: i % 90 === 0 }, PA.CONFIG.STEP); return [st.player.hp, st.stats.kills, st.stats.attacks, st.status]; };
  assert.deepEqual(j(play()), j(play()));
});
