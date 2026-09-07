// §6 취소·패배·저장 악용 검사: 금화·이용권·기술·장비가 사라지거나 복제되지 않아야 한다
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, fakeStorage, steps } = require('./load');
const PA = load();
const R = PA.Run, j = (x) => JSON.parse(JSON.stringify(x));
const snap = (run) => j({ gold: run.gold, services: run.services, weapons: run.growth.weapons, e: run.growth.skills.e, equipment: run.equipment, bag: run.bag, forge: run.forge, steer: run.growth.steer });

test('상점 재고: 재진입·재접속·날짜 유지에서 바뀌지 않고, 구매 뒤 다시 열어도 판매 기록이 유지된다', () => {
  const run = R.newRun(21); const a = j(R.stock(run)); const store = fakeStorage(); R.save(run, store); const b = j(R.stock(R.load(store))); assert.deepEqual(a, b);
  run.stock = null; assert.deepEqual(j(R.stock(run)).equipment, a.equipment, '재고 필드를 지워도 같은 시드로 재생성');
  run.gold = 999; R.buyEquipment(run, a.equipment[0], false); R.save(run, store); const back = R.load(store); assert.ok(R.stock(back).sold.includes(a.equipment[0])); assert.equal(R.canBuyEquipment(back, a.equipment[0]), false);
  R.endDay(run); assert.notEqual(run.stock.day, 1); assert.deepEqual(j(R.stock(run).sold), [], '새 날은 새 재고·판매 기록 초기화');
});
test('기술 교체 도중 취소·실패: 견적만 보고 아무것도 확정하지 않으면 상태 불변, 잘못된 개조·중복 개조·금화 부족은 예외이며 상태 불변', () => {
  const run = R.newRun(22); run.growth.weapons[0] = { id: 'sword', level: 3, mods: ['cross', 'crescent'] }; run.gold = 500; run.services.mod_swap = 1; const s0 = snap(run);
  const q = R.swapQuote(run, 'weapon', 0); assert.equal(q.price, 360); assert.deepEqual(snap(run), s0, '견적은 상태를 바꾸지 않음');
  assert.throws(() => R.applySwap(run, 'weapon', 0, 'sword', [])); assert.throws(() => R.applySwap(run, 'weapon', 0, q.options[0], ['nope'])); assert.deepEqual(snap(run), s0);
  const t = q.options[0], mods = Object.keys(PA.WEAPONS[t].mods).filter(m => PA.WEAPONS[t].mods[m].impl); assert.throws(() => R.applySwap(run, 'weapon', 0, t, [mods[0], mods[0]]), /중복/); assert.deepEqual(snap(run), s0);
  run.gold = 359; assert.throws(() => R.applySwap(run, 'weapon', 0, t, [mods[0], mods[1]]), /금화/); assert.equal(run.gold, 359); assert.deepEqual(j(run.growth.weapons), s0.weapons);
  run.gold = 360; R.applySwap(run, 'weapon', 0, t, [mods[0], mods[1]]); assert.equal(run.gold, 0); assert.equal(run.growth.weapons[0].mods.length, 2); assert.equal(run.growth.weapons.length, 1); assert.equal(run.services.mod_swap, 1, '교체는 교체권을 쓰지 않음');
});
test('개조 변경 3택 도중 받지 않음: 원래 개조 복구 + 금화/교체권 환불. 후보가 없으면 아무것도 차감되지 않음. 이미 열린 제시가 있으면 시작 불가', () => {
  const run = R.newRun(23); run.growth.weapons[0] = { id: 'sword', level: 2, mods: ['cross'] }; run.gold = 300; const s0 = snap(run);
  let off = PA.Flow.modChange(run, 'sword', 'cross'); assert.ok(off && off.paidChange); assert.equal(run.gold, 160); assert.deepEqual(j(run.growth.weapons[0].mods), []);
  PA.Flow.resolveOffer(run, off, null); assert.deepEqual(snap(run), s0, '받지 않음 → 원복·환불');
  run.services.mod_swap = 1; off = PA.Flow.modChange(run, 'sword', 'cross'); assert.equal(run.gold, 300); assert.equal(run.services.mod_swap, 0, '교체권 우선 소모'); PA.Flow.resolveOffer(run, off, null); assert.equal(run.services.mod_swap, 1, '취소 시 교체권 복구');
  off = PA.Flow.modChange(run, 'sword', 'cross'); assert.equal(run.services.mod_swap, 0); PA.Flow.resolveOffer(run, off, off.choices[0]); assert.equal(run.growth.weapons[0].mods.length, 1); assert.notEqual(run.growth.weapons[0].mods[0], 'cross'); assert.equal(run.gold, 300);
  run.growth.weapons[0] = { id: 'sword', level: 2, mods: ['cross', 'crescent'] }; run.growth.weapons.push({ id: 'blades', level: 1, mods: [] }); const r2 = R.newRun(24); r2.growth.weapons[0] = { id: 'sword', level: 1, mods: ['cross', 'crescent'] }; r2.gold = 300;
  // 검 개조 후보: cross/crescent/scar 중 남은 것 scar 1개 → 후보 있음. 후보 없음 조건: 3개 모두 보유 불가(개조 2개 제한)이므로 'cross' 제외 시 crescent 보유 → scar만. 후보 0을 만들기 위해 scar를 impl=false로 잠시
  const saved = PA.WEAPONS.sword.mods.scar.impl; PA.WEAPONS.sword.mods.scar.impl = false; assert.equal(PA.Flow.modChange(r2, 'sword', 'cross'), null); assert.equal(r2.gold, 300); assert.deepEqual(j(r2.growth.weapons[0].mods), ['cross', 'crescent']); PA.WEAPONS.sword.mods.scar.impl = saved;
  r2.growth.pendingOffer = { pool: 'level', choices: [] }; assert.throws(() => PA.Flow.modChange(r2, 'sword', 'cross'));
});
test('금화 부족 구매·장비 탈착 반복·판매 반복: 금화가 새지 않고 장비가 복제되지 않는다', () => {
  const run = R.newRun(25); const st = R.stock(run); const id = st.equipment[0]; run.gold = 10;
  assert.throws(() => R.buyEquipment(run, id, true)); assert.throws(() => R.buySkill(run)); assert.equal(run.gold, 10); assert.equal(run.bag.length, 0);
  run.gold = 500; R.buyEquipment(run, id, true); const d = PA.EQUIPMENT[id]; for (let i = 0; i < 20; i++) { R.unequipItem(run, d.slot); R.equipItem(run, id); }
  assert.equal(run.bag.length, 0); assert.equal(run.equipment[d.slot], id); assert.equal(run.bag.filter(x => x === id).length, 0);
  const g1 = run.gold; R.sellEquipment(run, id); assert.throws(() => R.sellEquipment(run, id), '이미 판 장비는 다시 못 팜'); assert.equal(run.gold, g1 + R.sellPrice(id)); assert.equal(R.ownsEquip(run, id), false);
  assert.throws(() => R.equipItem(run, id), '가방에 없는 장비 장착 불가');
});
test('심층 패배: 미정산 전리품(심층 보상 포함)·남은 하루 상실, 정산 금화 유지. 심층 보상은 승리 정산에서만 1회', () => {
  const run = R.newRun(26); const s = R.startSortie(run, 'forest'); R.applyEncounterResult(run, s, 'won', { gold: 40, mats: {}, chestGold: 0 }, 80); R.deepExplore(run, s);
  const st = PA.Flow.makeEncounter(run, s); st.status = 'won'; for (const e of st.enemies) e.dead = true; PA.Flow.settleVictory(run, s, st); PA.Flow.settleVictory(run, s, st); assert.equal(s.deepRewarded, true);
  const gold0 = run.gold, bag0 = run.bag.length; const st2 = PA.Flow.makeEncounter(run, s); st2.status = 'lost'; PA.Flow.settleDefeat(run, s, st2);
  assert.equal(run.gold, gold0); assert.equal(run.bag.length, bag0); assert.equal(run.day, 2); assert.equal(run.pendingSortie, null);
  R.returnToBase(run, s); assert.equal(run.gold, gold0, '패배한 출격을 뒤늦게 정산해도 반영 없음'); // settled 플래그가 없어도 호출자가 버린다 — 여기서는 명시적으로 막는다
});
test('보스 패배 반복 재도전: 금화·성장·장비·이용권이 매번 입장 시점으로 돌아오고 재도전 횟수만 는다', () => {
  const run = R.newRun(27, 'sword', 'trio', 'test03'); R.endDay(run); R.endDay(run); run.gold = 250; run.bag.push('iron_shield'); R.equipItem(run, 'iron_shield'); run.services.free_rest = 1; const s0 = snap(run);
  for (let i = 0; i < 4; i++) { const bs = R.startBoss(run); const st = PA.Flow.makeBossEncounter(run, bs); PA.Growth.addXp(run.growth, 300); run.gold += 100; run.services.free_rest = 0; st.status = 'lost'; PA.Flow.settleBossDefeat(run, st); assert.deepEqual(snap(run), s0, '재도전 ' + (i + 1)); assert.equal(run.bossRetries, i + 1); }
  assert.equal(run.dmgStats.combats.filter(c => c.kind === 'boss' && !c.won).length, 4);
});
test('성장 선택 중 저장 후 이어 하기: 같은 제시가 다시 나오고 두 번 적용되지 않는다', () => {
  const run = R.newRun(28); run.growth.pendingLevelUps = 2; const off = PA.Growth.generateOffer(run, { pool: 'level' }); const store = fakeStorage(); R.save(run, store);
  const back = R.load(store); const off2 = PA.Flow.nextOffer(back, {}); assert.deepEqual(j(off2), j(off));
  PA.Flow.resolveOffer(back, off2, off2.choices[0]); assert.equal(back.growth.pendingLevelUps, 1); R.save(back, store); const back2 = R.load(store); assert.equal(back2.growth.pendingLevelUps, 1); assert.equal(back2.growth.pendingOffer, null);
  const off3 = PA.Flow.nextOffer(back2, {}); assert.notEqual(off3.seq, off2.seq, '다음 제시는 다른 순번'); PA.Flow.resolveOffer(back2, off3, off3.choices[0]); assert.equal(PA.Flow.nextOffer(back2, {}), null);
});
test('성장 예약: 저장·복구 뒤에도 1회만 소비되고, 예약 중 두 번째 임무는 금화로 대체된다', () => {
  const run = R.newRun(29); run.growth.steer = { kind: 'weapon_level', fallbackGold: 40 }; const store = fakeStorage(); R.save(run, store); const back = R.load(store); assert.equal(back.growth.steer.kind, 'weapon_level');
  back.growth.pendingLevelUps = 2; const o1 = PA.Flow.nextOffer(back, {}); assert.equal(o1.steer, 'weapon_level'); PA.Flow.resolveOffer(back, o1, o1.choices[0]); assert.equal(back.growth.steer, null);
  const o2 = PA.Flow.nextOffer(back, {}); assert.equal(o2.steer, null, '두 번째 레벨업은 예약 없음'); PA.Flow.resolveOffer(back, o2, null);
});
test('귀환 정산 중복·통계 중복: 같은 출격을 두 번 정산해도 금화·가방·이용권·통계는 1회', () => {
  const run = R.newRun(30); const s = R.startSortie(run, 'ridge'); const st = PA.Flow.makeEncounter(run, s); st.status = 'won'; for (const e of st.enemies) e.dead = true;
  PA.Flow.settleVictory(run, s, st); s.loot.items = ['iron_shield']; s.loot.services = ['mod_swap']; const g0 = run.gold, L = s.loot.gold;
  PA.Flow.returnHome(run, s); PA.Flow.returnHome(run, s); R.returnToBase(run, s); assert.equal(run.gold, g0 + L); assert.equal(run.bag.filter(x => x === 'iron_shield').length, 1); assert.equal(run.services.mod_swap, 1);
  PA.Stats.record(run, st, { kind: 'sortie' }); assert.equal(run.dmgStats.combats.length, 1);
});
