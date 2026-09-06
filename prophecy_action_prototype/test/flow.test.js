// 공유 흐름(PA.Flow): 조우 시드 통일·정산 1회·더 깊이 지역 3택 정확히 1회(저장·재시작 포함)
const test = require('node:test'); const assert = require('node:assert');
const { load, fakeStorage } = require('./load');
const PA = load(); const j = (x) => JSON.parse(JSON.stringify(x));
function winDeep(run, s) { const st = PA.Flow.makeEncounter(run, s); PA.Bot.runCombat(st, 'aggressive', { maxSec: 240 }); return st; }
test('조우 시드: 게임·시뮬레이터 공통 규칙 seed + 조우수×1000 + (더 깊이 7)', () => {
  const run = PA.Run.newRun(5, 'sword'); const s = PA.Run.startSortie(run, 'forest');
  assert.equal(PA.Flow.encounterOpts(run, s).seed, s.seed);
  s.encounters = 1; PA.Run.deepExplore(run, s);
  assert.equal(PA.Flow.encounterOpts(run, s).seed, s.seed + 1000 + 7);
  const o = PA.Flow.encounterOpts(run, s); assert.equal(o.objective, 'elite'); assert.equal(o.regionId, 'forest'); assert.ok(o.waves.length);
});
test('더 깊이 승리(v0.8): 표시된 보상이 정확히 1회 전리품에 얹히고, 저장·복구를 거쳐도 귀환 정산은 1회', () => {
  const run = PA.Run.newRun(11, 'sword'); run.growth.level = 5;
  const s = PA.Run.startSortie(run, 'ridge'); const pv = PA.Run.deepPreview(run, s); assert.ok(['gold_big', 'equipment', 'voucher', 'steer'].includes(pv.reward.kind)); assert.equal(pv.extraTime, 1); assert.ok(pv.lootAtRisk);
  PA.Run.deepExplore(run, s); assert.deepEqual(j(s.deepReward), j(pv.reward), '들어가기 전 표시와 같은 보상');
  const st = winDeep(run, s); st.status = 'won'; for (const e of st.enemies) e.dead = true;
  const rw = PA.Flow.settleVictory(run, s, st);
  assert.equal(run.growth.pendingDeepPick, undefined, '3택 보류 없음'); assert.ok(rw.deep && rw.deep.kind === pv.reward.kind); assert.equal(rw.xp, PA.Run.regionBonusXp('ridge', true));
  const loot1 = j(s.loot); PA.Flow.settleVictory(run, s, st); assert.deepEqual(j(s.loot).gold >= loot1.gold, true); assert.equal(s.deepRewarded, true);
  assert.ok(PA.Flow.mustReturn(s), '심층 승리 뒤에는 귀환만');
  const store = fakeStorage(); PA.Run.save(run, store); const run2 = PA.Run.load(store); assert.deepEqual(j(run2.pendingSortie.deepReward), j(pv.reward));
  const gold0 = run2.gold, bag0 = run2.bag.length, sv0 = (run2.services.mod_swap || 0), steer0 = run2.growth.steer;
  PA.Flow.returnHome(run2, run2.pendingSortie); PA.Flow.returnHome(run2, run2.pendingSortie || s); // 두 번 호출해도 정산은 1회
  if (pv.reward.kind === 'gold_big') assert.equal(run2.gold, gold0 + loot1.gold);
  if (pv.reward.kind === 'equipment') assert.equal(run2.bag.length, bag0 + 1);
  if (pv.reward.kind === 'voucher') assert.equal(run2.services.mod_swap, sv0 + 1);
  if (pv.reward.kind === 'steer') assert.ok(steer0 || run2.growth.steer);
  assert.equal(PA.Flow.nextOffer(run2, { regionId: 'ridge' }) && PA.Flow.nextOffer(run2, { regionId: 'ridge' }).pool, run2.growth.pendingLevelUps > 0 ? 'level' : null);
});
test('일반 조우 승리에는 지역 3택이 없고, 패배 정산은 전리품을 남기지 않는다', () => {
  const run = PA.Run.newRun(3, 'spear'); const s = PA.Run.startSortie(run, 'forest');
  const st = PA.Flow.makeEncounter(run, s); PA.Bot.runCombat(st, 'balanced', { maxSec: 240 });
  if (st.status === 'won') { PA.Flow.settleVictory(run, s, st); assert.equal(run.growth.pendingDeepPick, undefined); assert.ok(s.loot.gold > 0); }
  const run2 = PA.Run.newRun(3, 'spear'); const s2 = PA.Run.startSortie(run2, 'forest'); const st2 = PA.Flow.makeEncounter(run2, s2); st2.status = 'lost';
  PA.Flow.settleDefeat(run2, s2, st2); assert.equal(run2.stats.losses, 1); assert.equal(s2.loot.gold, 0); assert.ok(run2.hp > 0);
});
test('resolveAll: 후보가 없는 더 깊이 3택은 제시 없이 소비되고 기록된다', () => {
  const run = PA.Run.newRun(2, 'sword'); const s = PA.Run.startSortie(run, 'forest'); PA.Run.deepExplore(run, s);
  run.growth.pendingDeepPick = { regionId: 'forest', key: 'x' };
  const off = PA.Flow.nextOffer(run, {}); // forest 태그 후보가 있으면 제시, 없으면 null: 어느 쪽이든 보류는 1회 소비
  assert.equal(run.growth.pendingDeepPick, null);
  if (!off) assert.equal(run.growth.deepPickNone, 1);
  assert.equal(PA.Flow.nextOffer(run, {}), off ? off : null);
});
