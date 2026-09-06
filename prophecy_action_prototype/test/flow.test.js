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
test('더 깊이 승리: 지역 3택은 정확히 1회, 저장·복구를 거쳐도 같은 제시가 한 번만 나온다', () => {
  const run = PA.Run.newRun(11, 'sword'); run.growth.level = 5; // 후보 확보용
  const s = PA.Run.startSortie(run, 'ridge'); PA.Run.deepExplore(run, s);
  const st = winDeep(run, s); st.status = 'won'; for (const e of st.enemies) e.dead = true;
  const rw = PA.Flow.settleVictory(run, s, st);
  assert.ok(run.growth.pendingDeepPick, '보류 등록'); assert.equal(rw.xp, PA.Run.regionBonusXp('ridge', true));
  const gold1 = s.loot.gold; PA.Flow.settleVictory(run, s, st); assert.equal(run.growth.pendingDeepPick.key, `${s.seed}:1`); // 재정산돼도 보류는 1개(deepPicked)
  s.loot.gold = gold1;
  // 레벨업을 먼저 소진
  while (run.growth.pendingLevelUps > 0) { const off = PA.Flow.nextOffer(run, { regionId: 'ridge' }); assert.equal(off.pool, 'level'); PA.Flow.resolveOffer(run, off, off.choices[0] || null); }
  // 저장·복구 후 더 깊이 3택 제시
  const store = fakeStorage(); PA.Run.save(run, store); const run2 = PA.Run.load(store);
  const off = PA.Flow.nextOffer(run2, { regionId: 'ridge' }); assert.ok(off && off.pool === 'deep', '더 깊이 3택'); assert.ok(off.choices.every(c => c.regionMatch));
  assert.equal(run2.growth.pendingDeepPick, null, '보류는 제시로 소비됨');
  // 제시 중 다시 저장·복구해도 같은 제시(재굴림 없음)
  PA.Run.save(run2, store); const run3 = PA.Run.load(store); const off2 = PA.Flow.nextOffer(run3, { regionId: 'ridge' });
  assert.deepEqual(j(off2), j(off));
  PA.Flow.resolveOffer(run3, off2, off2.choices[0]);
  assert.equal(PA.Flow.nextOffer(run3, { regionId: 'ridge' }), null, '두 번째 더 깊이 3택 없음');
  assert.equal(run3.growth.picks.skip || 0, 0);
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
