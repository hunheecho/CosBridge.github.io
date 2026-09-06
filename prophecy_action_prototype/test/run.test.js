const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'), path = require('path');
const { load, fakeStorage, ORDER, runWith } = require('./load');
const PA = load();
const R = PA.Run;
const j = (x) => JSON.parse(JSON.stringify(x)); // vm 컨텍스트 프로토타입 차이를 없앤다

test('index.html의 스크립트 순서가 테스트 로더의 순서와 일치한다', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const tags = [...html.matchAll(/<script src="src\/(\w+)\.js"><\/script>/g)].map(m => m[1]);
  assert.deepEqual(tags.slice(0, ORDER.length), ORDER);
});

test('빌드 파생: 대장간 강화·무기 숙련·가속·넓어진 공격이 정확히 한 번씩 곱해진다', () => {
  const run = runWith(PA, { gear: { upgrade: 1 }, growth: { weapons: [{ id: 'sword', level: 1 }], commons: { wide: 1 }, passives: { mastery: 2, haste: 1 } } });
  const b = R.build(run), w = b.weapons[0];
  assert.ok(Math.abs(w.damage - 12 * 1.1 * 1.2) < 1e-9, '공용 공격 강화 1단계 ×1.1 × 숙련 2 ×1.2');
  assert.ok(Math.abs(w.interval - 0.55 * 0.92) < 1e-9);
  assert.ok(Math.abs(w.arcDeg - 110 * 1.25) < 1e-9);
  assert.equal(PA.Build.hitsToKill(b, 'wolf'), Math.ceil(30 / w.damage));
});

test('공통 증강: 최대 단계·전제 조건을 지키며, 제시 목록에 무효 선택이 없다', () => {
  const run = runWith(PA, {}); const Gr = PA.Growth;
  Gr.applyChoice(run, { kind: 'common', id: 'wide' }); Gr.applyChoice(run, { kind: 'common', id: 'wide' });
  assert.throws(() => Gr.applyChoice(run, { kind: 'common', id: 'wide' }));
  assert.throws(() => Gr.applyChoice(run, { kind: 'common', id: 'flare' }), '불길 공급원 없이 불꽃 파열 불가');
  for (let i = 0; i < 30; i++) { run.growth.choiceSeq = i; run.growth.pendingOffer = null; for (const c of Gr.generateOffer(run, {}).choices) { assert.notEqual(c.key, 'common:wide'); assert.notEqual(c.key, 'common:flare'); } }
  Gr.applyChoice(run, { kind: 'common', id: 'ember' });
  let seen = false; for (let i = 0; i < 80; i++) { run.growth.choiceSeq = 100 + i; run.growth.pendingOffer = null; if (Gr.generateOffer(run, {}).choices.some(c => c.key === 'common:flare')) seen = true; }
  assert.ok(seen, '잔불 걸음 이후에는 불꽃 파열이 제시됨');
});

test('조우 간 유지/제거: 증강·장비·체력은 유지되고 보호막·감속장·지역은 새 조우에서 초기화된다', () => {
  const run = runWith(PA, { augments: { barrier: 1 } }); run.hp = 55;
  const st = PA.Combat.create({ build: R.build(run), hp: run.hp, seed: 1, waves: [], objective: 'clear' });
  st.player.shield = 0; st.field = { x: 0, y: 0, r: 1, ttl: 9, maxTtl: 9 }; PA.Combat.addZone(st, 'spore', 1, 1, 10, 9, 1);
  const st2 = PA.Combat.create({ build: R.build(run), hp: st.player.hp, seed: 2, waves: [], objective: 'clear' });
  assert.equal(st2.player.shield, 30); assert.equal(st2.field, null); assert.equal(st2.zones.length, 0); assert.equal(st2.player.hp, 55);
  assert.equal(st2.build.has('barrier'), true);
});

test('상점(v0.8): 하루 시드 재고(장비 2 + 기술 1), 구매 시 장착/보관 선택, 중복 구매 불가, 판매, 최대 체력 장비 탈착에 회복 없음', () => {
  const run = R.newRun(1); const st = R.stock(run);
  assert.equal(st.equipment.length, 2); assert.ok(st.skill && (st.skill.kind === 'weapon' || st.skill.kind === 'e')); assert.equal(st.skill.price, PA.SHOP.newSkill);
  const store = fakeStorage(); R.save(run, store); assert.deepEqual(j(R.stock(R.load(store))), j(st), '다시 열어도 같은 재고');
  const id = st.equipment[0], d = PA.EQUIPMENT[id]; const price = R.equipPriceFor(run, id);
  assert.equal(price, PA.SHOP.price[d.slot]); run.gold = price - 1; assert.equal(R.canBuyEquipment(run, id), false); assert.throws(() => R.buyEquipment(run, id, true));
  run.gold = price + 10; R.buyEquipment(run, id, true); assert.equal(run.gold, 10); assert.equal(run.equipment[d.slot], id); assert.equal(run.bag.length, 0);
  assert.equal(R.canBuyEquipment(run, id), false, '중복 구매 불가'); run.gold = 999; assert.equal(R.canBuyEquipment(run, id), false);
  const id2 = st.equipment[1]; R.buyEquipment(run, id2, false); assert.ok(run.bag.includes(id2), '보관');
  if (PA.EQUIPMENT[id2].slot === d.slot) { R.equipItem(run, id2); assert.equal(run.equipment[d.slot], id2); assert.ok(run.bag.includes(id), '기존 장비는 가방으로'); }
  const g1 = run.gold; R.sellEquipment(run, id); assert.equal(run.gold, g1 + PA.SHOP.sellPrice[d.slot]); assert.equal(R.ownsEquip(run, id), false);
  // 생명력의 외투: 최대 체력 +20, 장착해도 회복 없음, 해제하면 현재 체력이 최대치로 잘린다
  const r2 = R.newRun(2); r2.bag.push('vitality_coat'); r2.hp = 100; R.equipItem(r2, 'vitality_coat'); assert.equal(R.build(r2).hpMax, 120); assert.equal(r2.hp, 100, '장착 회복 없음');
  r2.hp = 120; R.unequipItem(r2, 'armor'); assert.equal(r2.hp, 100, '해제 시 잘림'); R.equipItem(r2, 'vitality_coat'); assert.equal(r2.hp, 100, '재장착 회복 없음(악용 불가)');
  // 새 기술 구매: 빈 슬롯에 Lv1, 개조 없음
  const r3 = R.newRun(3); const sk = R.stock(r3).skill; r3.gold = sk.price; assert.equal(R.canBuySkill(r3), true); R.buySkill(r3); assert.equal(r3.gold, 0);
  if (sk.kind === 'weapon') assert.deepEqual(j(r3.growth.weapons[1]), { id: sk.id, level: 1, mods: [] }); else assert.deepEqual(j(r3.growth.skills.e), { id: sk.id, level: 1, variant: null });
  assert.equal(R.canBuySkill(r3), false, '하루 1개');
});
test('교체 견적·확정·취소: 120 + (레벨-1)×40 + 개조×80, 레벨·개조 수 보존, 마지막 단계에서만 차감, 취소하면 아무것도 바뀌지 않음', () => {
  const run = R.newRun(4); const g = run.growth; g.weapons[0] = { id: 'sword', level: 3, mods: ['bleed', 'heavy'].filter(m => PA.WEAPONS.sword.mods[m] && PA.WEAPONS.sword.mods[m].impl) };
  const q = R.swapQuote(run, 'weapon', 0); assert.equal(q.price, 120 + 2 * 40 + g.weapons[0].mods.length * 80); assert.ok(q.options.length >= 1 && !q.options.includes('sword'));
  const snap = j(run); run.gold = q.price - 1; assert.throws(() => R.applySwap(run, 'weapon', 0, q.options[0], [])); assert.deepEqual(j(run), j(Object.assign(snap, { gold: q.price - 1 })), '실패·취소 시 상태 불변');
  run.gold = q.price; const target = q.options[0], mods = Object.keys(PA.WEAPONS[target].mods).filter(m => PA.WEAPONS[target].mods[m].impl).slice(0, q.modCount);
  R.applySwap(run, 'weapon', 0, target, mods); assert.equal(run.gold, 0); assert.equal(g.weapons[0].id, target); assert.equal(g.weapons[0].level, 3); assert.equal(g.weapons[0].mods.length, mods.length);
  assert.equal(g.weapons.some(w => w.id === 'sword'), false, '옛 기술은 남지 않음');
  const r2 = R.newRun(5); r2.growth.skills.e = { id: 'ward', level: 2, variant: null }; const q2 = R.swapQuote(r2, 'e'); assert.equal(q2.price, 120 + 40); r2.growth.skills.e.variant = Object.keys(PA.SKILLS.ward.variants)[0]; assert.equal(R.swapQuote(r2, 'e').price, 120 + 40 + 80);
  assert.equal(R.swapQuote(R.newRun(6), 'e'), null, 'E 없으면 견적 없음');
});
test('대장간(v0.8): 공용 공격 강화 90/160/240은 보스 관문 통과로 개방되고 자동기술 공통 배율 1.1/1.2/1.3', () => {
  const run = R.newRun(7, 'sword', 'trio'); run.gold = 1000; const d0 = R.build(run).weapons[0].damage;
  let F = R.forgeNext(run); assert.deepEqual(j([F.lv, F.cost, F.open]), [1, 90, true]); R.forgeUpgrade(run); assert.equal(run.gold, 910); assert.ok(Math.abs(R.build(run).weapons[0].damage - d0 * 1.1) < 1e-9);
  F = R.forgeNext(run); assert.deepEqual(j([F.lv, F.cost, F.open]), [2, 160, false]); assert.throws(() => R.forgeUpgrade(run), '보스 1 이전에는 잠김');
  run.bossesDone.push('boss'); assert.equal(R.forgeNext(run).open, true); R.forgeUpgrade(run); assert.equal(run.forge, 2); assert.ok(Math.abs(R.build(run).weapons[0].damage - d0 * 1.2) < 1e-9);
  assert.equal(R.forgeNext(run).open, false); run.bossesDone.push('guardian'); R.forgeUpgrade(run); assert.equal(run.forge, 3); assert.equal(R.forgeNext(run), null); assert.equal(run.gold, 1000 - 90 - 160 - 240);
  assert.deepEqual(j(R.modChangeCost(run)), { voucher: false, gold: 140 }); run.services.mod_swap = 1; assert.deepEqual(j(R.modChangeCost(run)), { voucher: true, gold: 0 });
});

test('재료 판매', () => {
  const run = R.newRun(1); run.mats.pelt = 2;
  R.sell(run, 'pelt', 1); assert.equal(run.gold, 75); assert.equal(run.mats.pelt, 1);
  assert.throws(() => R.sell(run, 'pelt', 5));
});

test('하루 일정(v0.8): 5칸(새벽~저녁), 오늘의 장소만 출격, 비용 1~2칸, 더 깊이 +1칸, 휴식은 가득 차도 가능, 하루 종료·보스 도래', () => {
  const run = R.newRun(1, 'sword', 'single'); // 단일 보스 회차(7일차 최종)
  assert.equal(R.slotName(run), '새벽'); assert.deepEqual(j(R.placesFor(run)), ['forest', 'ridge']);
  assert.equal(R.canSortie(run, 'deep'), false, '오늘 갈 수 없는 장소'); assert.throws(() => R.startSortie(run, 'marsh'));
  const s = R.startSortie(run, 'forest'); assert.equal(run.hours, 4); assert.equal(s.slot, 0); assert.ok(s.variant && s.variant.dropLastWave, '새벽 순찰 변주'); assert.equal(R.slotName(run), '아침');
  R.deepExplore(run, s); assert.equal(run.hours, 3); assert.equal(s.deep, true); assert.throws(() => R.deepExplore(run, s), '출격당 1회');
  run.hp = 10; R.rest(run); assert.equal(run.hours, 2); assert.equal(run.hp, 100);
  assert.equal(R.canRest(run), true, '체력이 가득해도 다음 칸으로'); assert.equal(R.nextSlotName(run), '저녁'); R.rest(run); assert.equal(run.hours, 1);
  const s2 = R.startSortie(run, 'ridge'); assert.equal(run.hours, 0); assert.equal(s2.slot, 4); assert.ok(s2.variant && s2.variant.extra, '저녁 매복 변주');
  assert.throws(() => R.rest(run)); assert.equal(R.canSortie(run, 'forest'), false);
  assert.deepEqual(j(R.previewNextDay(run).places.map(p => p.id)), ['forest', 'marsh']);
  for (let d = 1; d < 6; d++) { R.endDay(run); assert.equal(run.day, d + 1); assert.equal(run.hours, 5); assert.equal(run.phase, 'prep'); }
  assert.equal(run.visited.forest, 1); assert.equal(run.visited.ridge, 1); assert.ok(['forest', 'ridge'].includes(R.placesFor(run, 6)[0]), '6일차 첫 칸은 방문한 지역'); assert.equal(R.placesFor(run, 6)[1], 'deep');
  R.endDay(run); assert.equal(run.day, 7); assert.equal(run.phase, 'boss_prep'); assert.equal(run.ended, false); assert.equal(R.canSortie(run, 'forest'), false);
  assert.throws(() => R.endDay(run), /보스 준비/); assert.equal(R.canStartBoss(run), true);
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

test('승리 귀환은 전리품을 더하고(1회), 일반 패배는 미정산 전리품과 남은 하루를 잃고 다음 날 정상 체력으로 시작한다', () => {
  const run = R.newRun(1); const s = R.startSortie(run, 'forest');
  R.applyEncounterResult(run, s, 'won', { gold: 40, mats: { pelt: 2 }, chestGold: 20 }, 70);
  assert.equal(run.hp, 70); assert.equal(s.loot.gold, 60); assert.equal(run.gold, 60, '귀환 전에는 반영 안 됨');
  R.returnToBase(run, s); assert.equal(run.gold, 120); assert.equal(run.mats.pelt, 2); R.returnToBase(run, s); assert.equal(run.gold, 120, '정산은 1회');
  const s2 = R.startSortie(run, 'ridge'); const lv = run.growth.level;
  R.applyEncounterResult(run, s2, 'won', { gold: 40, mats: { pelt: 1 }, chestGold: 0 }, 50);
  R.applyEncounterResult(run, s2, 'lost', null, 0);
  R.defeat(run, s2);
  assert.equal(run.gold, 120); assert.equal(run.mats.pelt, 2); assert.equal(run.day, 2, '구조 → 다음 날'); assert.equal(run.hours, 5); assert.equal(run.hp, 100); assert.equal(run.growth.level, lv); assert.equal(run.lastDefeatDay, 1);
});

test('저장·복구: 핵심 상태가 동일하다', () => {
  const st = fakeStorage();
  const run = R.newRun(1); run.gold = 321; run.mats.pelt = 4; run.augments.spin = 1; run.augments.sharp = 2; run.bag.push('vitality_coat'); R.equipItem(run, 'vitality_coat'); run.day = 3; run.hours = 2; run.hp = 77; run.forge = 1;
  assert.equal(R.save(run, st), true);
  const back = R.load(st);
  assert.deepEqual(j(back), j(run));
  assert.equal(R.build(back).hpMax, 120);
  R.clearSave(st); assert.equal(R.load(st), null);
});

test('시드가 같으면 전투가 동일하게 재현된다', () => {
  const run = R.newRun(1);
  const play = () => { const st = PA.Combat.create({ build: R.build(run), seed: 42, waves: PA.REGIONS[1].waves, objective: 'clear' }); for (let i = 0; i < 120 * 30; i++) PA.Combat.step(st, { mx: i % 240 < 120 ? 1 : -1, my: 0, dodge: i % 90 === 0 }, PA.CONFIG.STEP); return [st.player.hp, st.stats.kills, st.stats.attacks, st.status]; };
  assert.deepEqual(j(play()), j(play()));
});

test('카드 미리보기 수치가 실제 파생값과 일치한다(넓어진 공격, 무기 숙련)', () => {
  const run = runWith(PA, { growth: { weapons: [{ id: 'spear', level: 1 }], commons: { wide: 1 } } });
  const d = PA.Growth.describe(run, { kind: 'common', id: 'wide' });
  const nb = PA.Build.preview(run, { augment: { kind: 'common', id: 'wide' } });
  assert.ok(d.change.includes(`→ ${Math.round(nb.weapons[0].width)}`), d.change);
  const dm = PA.Growth.describe(run, { kind: 'passive', id: 'mastery' });
  const nb2 = PA.Build.preview(run, { augment: { kind: 'passive', id: 'mastery' } });
  assert.ok(dm.change.includes(`→ ${PA.fmt.num(nb2.weapons[0].damage)}`), dm.change);
});

test('기존 저장의 시간 저축(saving)이 새 규칙으로 이어진다', () => {
  const st = fakeStorage();
  const old = R.newRun(1); old.version = 1; delete old.growth; old.augments.saving = 1; old.day = 2;
  st.setItem(R.SAVE_KEY, JSON.stringify(old));
  const back = R.load(st);
  const b = R.build(back);
  assert.equal(b.has('saving'), true); assert.equal(back.version, 4);
  assert.equal(PA.COMMONS.saving.desc.includes('처치'), true);
  const c = PA.Combat.create({ build: b, seed: 1, waves: [], objective: 'none' }); c.waveIndex = 99;
  PA.Combat.step(c, { special: true }, PA.CONFIG.STEP); const cd = c.player.special.cd;
  const e = PA.Combat.spawnEnemy(c, 'wolf', c.player.x + 30, c.player.y); e.hp = 1; PA.Combat.damageEnemy(c, e, 5, {});
  assert.ok(Math.abs(c.player.special.cd - (cd - 1)) < 1e-9);
});

