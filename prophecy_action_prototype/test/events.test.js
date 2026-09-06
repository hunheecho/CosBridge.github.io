// 탐험 사건 6종·위험 조건 3종: 시드 결정·저장·1회 정산·파밍 경로 없음
const test = require('node:test'); const assert = require('node:assert');
const { load, fakeStorage } = require('./load');
const PA = load(); const j = (x) => JSON.parse(JSON.stringify(x));
function wonSortie(seed, regionId, deep) { const run = PA.Run.newRun(seed, 'sword'); run.growth.level = 6; const s = PA.Run.startSortie(run, regionId || 'forest'); if (deep) PA.Run.deepExplore(run, s); const st = PA.Flow.makeEncounter(run, s); st.status = 'won'; return { run, s, st }; }
function forceEvent(run, s, id, extra) { s.event = Object.assign({ id, seed: 5, resolved: false, choice: null }, extra || {}); return s.event; }

test('사건 생성: 출격 시드로 결정적, 출격당 최대 1회, 더 깊이·추가 전투 뒤에는 없음, 유효 조건을 지킨다', () => {
  const seen = {}; let n = 0;
  for (let seed = 1; seed <= 60; seed++) { const { run, s, st } = wonSortie(seed, 'ridge'); PA.Flow.settleVictory(run, s, st); const a = s.event; const s2 = Object.assign({}, s, { event: null }); const b = PA.Events.roll(run, s2); assert.deepEqual(j(a), j(b), '같은 시드 → 같은 사건'); if (a) { n++; seen[a.id] = (seen[a.id] || 0) + 1; assert.ok(PA.EVENTS[a.id].valid(run, s2)); assert.equal(PA.Events.roll(run, s), null, '이미 사건이 있으면 없음'); } }
  assert.ok(n >= 15 && n <= 45, '사건 빈도 ' + n + '/60'); assert.ok(Object.keys(seen).length >= 4, '종류 다양 ' + JSON.stringify(seen));
  const { run, s, st } = wonSortie(3, 'forest', true); PA.Flow.settleVictory(run, s, st); assert.equal(s.event, null, '더 깊이 전투 뒤에는 사건 없음');
});
test('A 불안정한 무기 제단: 체력을 내고 개조 3택, 체력이 1 이하가 되면 선택 불가, 후보 없으면 사건 무효, 정산 1회', () => {
  const { run, s } = wonSortie(4, 'forest'); forceEvent(run, s, 'weapon_altar'); const cost = PA.Events.altarCost(run);
  const hp0 = run.hp; const r = PA.Events.resolve(run, s, 'pay'); assert.equal(r.next, 'offer'); assert.equal(run.hp, hp0 - cost); assert.ok(run.hp > 1);
  const off = PA.Flow.nextOffer(run, { regionId: 'forest' }); assert.ok(off && off.pool === 'mission' && off.choices.every(c => c.kind === 'weapon_mod' && c.id === 'sword'));
  PA.Flow.resolveOffer(run, off, off.choices[0]); assert.equal(run.growth.weapons[0].mods.length, 1); assert.equal(PA.Flow.nextOffer(run, {}), null);
  assert.throws(() => PA.Events.resolve(run, s, 'pay'), '두 번 정산 불가');
  const { run: r2, s: s2 } = wonSortie(4, 'forest'); r2.hp = cost + 1; forceEvent(r2, s2, 'weapon_altar'); assert.equal(PA.Events.options(r2, s2).find(o => o.id === 'pay').enabled, false, '체력 부족이면 불가'); assert.throws(() => PA.Events.resolve(r2, s2, 'pay'));
  const { run: r3, s: s3 } = wonSortie(4, 'forest'); r3.growth.weapons[0].mods = Object.keys(PA.WEAPONS.sword.mods).filter(k => PA.WEAPONS.sword.mods[k].impl).slice(0, PA.GROWTH.SLOTS.weaponMods); assert.equal(PA.EVENTS.weapon_altar.valid(r3, s3), false, '유효 개조 없으면 사건 제외');
});
test('B 버려진 보급소: 치료 또는 물자 중 하나, 이틀에 한 번', () => {
  const { run, s } = wonSortie(5, 'ridge'); run.hp = 40; forceEvent(run, s, 'supply'); const opts = PA.Events.options(run, s); assert.equal(opts.length, 3);
  PA.Events.resolve(run, s, 'loot'); assert.equal(s.loot.gold >= PA.EVENTS.supply.gold, true); assert.equal(run.hp, 40); assert.equal(run.lastSupplyDay, 1);
  assert.equal(PA.EVENTS.supply.valid(run, s), false, '같은 날·다음 날은 무효'); run.day = 3; assert.equal(PA.EVENTS.supply.valid(run, s), true);
  const { run: r2, s: s2 } = wonSortie(5, 'ridge'); r2.hp = 40; forceEvent(r2, s2, 'supply'); const g0 = s2.loot.gold; PA.Events.resolve(r2, s2, 'heal'); assert.equal(r2.hp, 40 + Math.round(PA.Run.build(r2).hpMax * 0.5)); assert.equal(s2.loot.gold, g0, '둘 다 받지 않음');
});
test('C 갇힌 상인: 추가 전투는 전리품·지역 경험치 없이 서비스 1종만 해금, 1회', () => {
  const { run, s } = wonSortie(6, 'forest'); forceEvent(run, s, 'merchant', { service: 'mod_swap' }); const gold0 = s.loot.gold, xp0 = run.growth.xp + run.growth.level * 1000;
  const r = PA.Events.resolve(run, s, 'fight'); assert.equal(r.next, 'fight'); assert.equal(s.eventFight, 'merchant');
  const st = PA.Flow.makeEncounter(run, s); assert.equal(st.objective, 'clear'); assert.ok(st.waves.some(w => w.some(g => g.type === 'wolf_alpha')), '정예 포함');
  st.status = 'won'; const rw = PA.Flow.settleVictory(run, s, st); assert.equal(rw.gold, 0); assert.deepEqual(rw.mats, {}); assert.equal(rw.xp, 0); assert.equal(s.loot.gold, gold0);
  assert.equal(run.services.mod_swap, 1); assert.equal(s.eventFight, null); assert.equal(s.event.resolved, true);
  const rw2 = PA.Flow.settleVictory(run, s, st); assert.equal(run.services.mod_swap, 1, '재정산해도 1회'); assert.equal(s.event.resolved, true);
});
test('D 시간의 샘: 무료 임시 강화(다음 전투 1회 소비) 또는 1시간 치료. 무료 시간 없음', () => {
  const { run, s } = wonSortie(7, 'forest'); forceEvent(run, s, 'time_spring'); const h0 = run.hours;
  PA.Events.resolve(run, s, 'buff'); assert.equal(run.buffs.skillCd, 0.7); assert.equal(run.hours, h0);
  const b1 = PA.Run.build(run); const s2 = PA.Run.startSortie(run, 'forest'); const st = PA.Flow.makeEncounter(run, s2); assert.equal(st.tempBuff, 'skillCd'); assert.equal(run.buffs.skillCd, undefined, '전투 시작 시 소비');
  assert.ok(st.build.specialCd < PA.Run.build(run).specialCd, '강화된 재사용이 그 전투에만 적용');
  const { run: r2, s: s3 } = wonSortie(7, 'forest'); r2.hp = 30; forceEvent(r2, s3, 'time_spring'); const h1 = r2.hours; PA.Events.resolve(r2, s3, 'heal'); assert.equal(r2.hours, h1 - 1); assert.equal(r2.hp, PA.Run.build(r2).hpMax);
  const { run: r3, s: s4 } = wonSortie(7, 'forest'); r3.hours = 0; r3.hp = 30; forceEvent(r3, s4, 'time_spring'); assert.equal(PA.Events.options(r3, s4).find(o => o.id === 'heal').enabled, false);
});
test('E 봉인된 전리품: 더 깊이 경로 재사용(1시간), 금화 ×2는 그 전투 1회, 지역 3택은 1회', () => {
  const { run, s } = wonSortie(8, 'ridge'); forceEvent(run, s, 'sealed_loot'); const h0 = run.hours;
  const r = PA.Events.resolve(run, s, 'fight'); assert.equal(r.next, 'deep'); assert.equal(s.deep, true); assert.equal(run.hours, h0 - 1);
  const st = PA.Flow.makeEncounter(run, s); assert.equal(st.objective, 'elite'); st.status = 'won';
  const rw = PA.Flow.settleVictory(run, s, st); assert.ok(rw.sealedLoot); assert.ok(run.growth.pendingDeepPick); assert.equal(s.deepGoldMult, null);
  assert.equal(PA.Run.canDeepExplore(run, s) && !s.deep, false, '다시 더 깊이 없음'); assert.equal(s.event.resolved, true);
});
test('F 정찰자의 정보: 남은 카드 1장의 위험 조건을 교체(1회), 완료 카드는 제외', () => {
  const { run, s } = wonSortie(9, 'forest'); run.day = 2; run.cards = null; const cards = PA.Sortie.cardsFor(run); const target = cards.find(c => !c.done);
  forceEvent(run, s, 'scout', { cardId: target.id, fromRisk: target.risk, toRisk: target.risk === 'hazard' ? 'escort' : 'hazard' });
  PA.Events.resolve(run, s, 'swap'); assert.equal(target.risk, target.risk); assert.equal(PA.Sortie.card(run, target.id).risk, s.event.toRisk);
  assert.throws(() => PA.Events.resolve(run, s, 'swap'));
  for (const c of cards) c.done = true; assert.equal(PA.EVENTS.scout.valid(run, s), false);
});
test('전투 뒤 안전 화면 상태는 저장·복구된다(사건·보류 선택 1회), 귀환하면 해제', () => {
  const { run, s, st } = wonSortie(10, 'ridge'); PA.Flow.settleVictory(run, s, st); assert.equal(run.pendingSortie, s);
  const store = fakeStorage(); PA.Run.save(run, store); const run2 = PA.Run.load(store); assert.ok(run2.pendingSortie); assert.deepEqual(j(run2.pendingSortie), j(s));
  const step = PA.Flow.afterCombatStep(run2, run2.pendingSortie); assert.ok(['offer', 'event', 'after'].includes(step));
  PA.Flow.resolveAll(run2, { regionId: 'ridge' }, (off) => off.choices[0]); if (run2.pendingSortie.event) PA.Events.resolve(run2, run2.pendingSortie, 'leave');
  assert.equal(PA.Flow.afterCombatStep(run2, run2.pendingSortie), 'after'); PA.Flow.returnHome(run2, run2.pendingSortie); assert.equal(run2.pendingSortie, null);
});
test('위험 조건 3종: 지원병 증가(총량 ×1.5, 동시 상한 동일), 정예 호위(첫 웨이브 정예), 위험 지형(예고·안전 통로·목표 지점 회피)', () => {
  const mk = (risk) => { const run = PA.Run.newRun(11, 'sword'); const s = PA.Run.startSortie(run, 'ridge'); Object.assign(s, { mission: true, objective: 'seal', cardId: 'x', risk }); return PA.Flow.makeEncounter(run, s); };
  const base = mk(null), rf = mk('reinforce'), es = mk('escort'), hz = mk('hazard');
  assert.equal(rf.obj.reinforce.budget, Math.round(base.obj.reinforce.budget * 1.5)); assert.equal(rf.obj.reinforce.cap, base.obj.reinforce.cap);
  assert.ok(es.waves[0].some(g => g.type === 'wolf_alpha') && !base.waves[0].some(g => g.type === 'wolf_alpha'));
  assert.ok(hz.obj.terrain); const dt = PA.CONFIG.STEP; hz.waveIndex = 99; hz.pending = []; hz.obj.reinforce.budget = 0; for (const e of hz.enemies) e.dead = true;
  for (let i = 0; i < Math.round(7 / dt); i++) PA.Combat.step(hz, {}, dt);
  const zones = hz.zones.filter(z => z.type === 'hazard'); assert.ok(zones.length >= 2, '지형 위험 생성 ' + zones.length); assert.ok(zones.length < hz.obj.terrain.lanes + 1);
  const seal = hz.objects.find(o => o.kind === 'seal'); for (const z of zones) assert.ok(PA.m.dist(z, seal) > z.r + seal.r, '봉인 지점을 덮지 않음');
  for (const z of zones) assert.ok(z.warn > 0 && (z.t < z.warn ? !z.armed : true), '예고 뒤 무장');
  const p = hz.player; const angles = zones.map(z => Math.atan2(z.y - p.y, z.x - p.x)).sort((a, b) => a - b); if (angles.length >= 2) { let maxGap = 0; for (let i = 0; i < angles.length; i++) { const g = (i + 1 < angles.length ? angles[i + 1] : angles[0] + Math.PI * 2) - angles[i]; maxGap = Math.max(maxGap, g); } assert.ok(maxGap > 1.2, '안전 통로 각도 ' + maxGap.toFixed(2)); }
});
test('거점 서비스: 제시 재선택권은 다른 순번의 레벨업 제시(1회 소비), 개조 교체권은 개조를 떼고 그 무기의 다른 개조 3택(후보 없으면 되돌림)', () => {
  const run = PA.Run.newRun(12, 'sword'); run.growth.level = 5; run.growth.pendingLevelUps = 1; run.services = { reroll: 1, mod_swap: 1 };
  const a = PA.Flow.nextOffer(run, {}); const b = PA.Flow.rerollOffer(run); assert.notEqual(a.seq, b.seq); assert.equal(run.services.reroll, 0); assert.throws(() => PA.Flow.rerollOffer(run));
  PA.Flow.resolveOffer(run, b, b.choices[0]); assert.equal(run.growth.pendingLevelUps, 0);
  run.growth.weapons[0].mods = ['cross']; const off = PA.Flow.modSwapOffer(run, 'sword', 'cross'); assert.ok(off); assert.ok(off.choices.every(c => c.kind === 'weapon_mod' && c.id === 'sword' && c.mod !== 'cross')); assert.equal(run.services.mod_swap, 0); assert.deepEqual(run.growth.weapons[0].mods, []);
  PA.Flow.resolveOffer(run, off, off.choices[0]); assert.equal(run.growth.weapons[0].mods.length, 1); assert.notEqual(run.growth.weapons[0].mods[0], 'cross');
  const run2 = PA.Run.newRun(12, 'sword'); run2.services = { mod_swap: 1 }; const all = Object.keys(PA.WEAPONS.sword.mods).filter(k => PA.WEAPONS.sword.mods[k].impl); run2.growth.weapons[0].mods = all.slice(0, 2);
  // 남은 후보가 있으면 제시, 없으면 되돌리고 권 유지
  const res = PA.Flow.modSwapOffer(run2, 'sword', all[0]); if (!res) { assert.deepEqual(run2.growth.weapons[0].mods.sort(), all.slice(0, 2).sort()); assert.equal(run2.services.mod_swap, 1); }
});
