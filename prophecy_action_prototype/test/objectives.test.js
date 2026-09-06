// 전투 목표 4종·출격 카드·임무 보상: 규칙 검증(사람·봇 공용 흐름)
const test = require('node:test'); const assert = require('node:assert');
const { load, fakeStorage } = require('./load');
const PA = load(); const j = (x) => JSON.parse(JSON.stringify(x));
function mission(seed, objective, regionId, extra) { const run = PA.Run.newRun(seed, 'sword'); run.growth.level = 6; const s = PA.Run.startSortie(run, regionId || 'forest'); Object.assign(s, { mission: true, objective, cardId: 'x' }, extra || {}); return { run, s, st: PA.Flow.makeEncounter(run, s) }; }
const dt = PA.CONFIG.STEP; const steps = (st, sec, inp) => { for (let i = 0; i < Math.round(sec / dt); i++) PA.Combat.step(st, inp || {}, dt); };

test('출격 카드: 하루 3장, 시드 결정적, (지역,목표) 중복 없음, 최소 1장은 빌드 연결, 저장·복구 후 동일', () => {
  const run = PA.Run.newRun(21, 'spear'); const a = PA.Sortie.cardsFor(run), b = PA.Sortie.generate(run, 1);
  assert.equal(a.length, 3); assert.deepEqual(j(a), j(b));
  assert.equal(new Set(a.map(c => c.regionId + ':' + c.objective)).size, 3);
  assert.ok(a.some(c => c.linked)); assert.ok(a.every(c => PA.OBJECTIVE_IDS.includes(c.objective) && c.timeCost >= 1 && c.enemies.length >= 1 && c.enemies.length <= 4));
  assert.ok(a.every(c => c.first), '1일차는 모두 첫 도입');
  const store = fakeStorage(); PA.Run.save(run, store); const run2 = PA.Run.load(store); assert.deepEqual(j(PA.Sortie.cardsFor(run2)), j(a), '저장된 카드 유지(재굴림 없음)');
  PA.Run.endDay(run); assert.equal(run.cards.day, 2); assert.equal(run.cards.list.length, 3); assert.ok(run.cards.list.every(c => (PA.MISSIONS.regionFromDay[c.regionId] || 1) <= 2));
});
test('임무 출격: 카드 시간 차감, 하루 1회 완료, 재도전은 3택 없음, 더 깊이 탐험 불가', () => {
  const run = PA.Run.newRun(5, 'sword'); const cards = PA.Sortie.cardsFor(run); const c = cards[0]; const h0 = run.hours;
  const s = PA.Sortie.start(run, c.id); assert.equal(run.hours, h0 - c.timeCost); assert.equal(s.objective, c.objective); assert.equal(c.attempts, 1);
  assert.equal(PA.Run.canDeepExplore(run, s), false);
  const st = PA.Flow.makeEncounter(run, s); assert.equal(st.objective, c.objective); assert.ok(st.obj);
  st.status = 'won'; const rw = PA.Flow.settleVictory(run, s, st);
  assert.ok(rw.mission && rw.missionPick); assert.deepEqual(rw.mats, {}); assert.ok(run.growth.pendingMissionPick); assert.equal(c.done, true);
  // 같은 카드는 다시 시작 불가, 정산을 한 번 더 해도 3택은 등록되지 않음
  assert.equal(PA.Sortie.canStart(run, c), false); assert.throws(() => PA.Sortie.start(run, c.id));
  run.growth.pendingMissionPick = null; const s2 = Object.assign({}, s); const rw2 = PA.Flow.settleVictory(run, s2, st); assert.equal(rw2.missionPick, false); assert.equal(run.growth.pendingMissionPick, null);
});
test('임무 보상 3택: 종류 제한·유효 후보만·건너뛰기 가능, 후보가 없으면 정해진 금화(1회)', () => {
  const run = PA.Run.newRun(8, 'sword'); run.growth.level = 4; while (run.growth.pendingLevelUps) run.growth.pendingLevelUps = 0;
  run.growth.pendingMissionPick = { cardId: 'd1c1', kind: 'weapon_level', regionId: 'forest', fallbackGold: 40, key: 'k' };
  const off = PA.Flow.nextOffer(run, {}); assert.equal(off.pool, 'mission'); assert.ok(off.choices.length >= 1); assert.ok(off.choices.every(c => c.kind === 'weapon_level' && c.id === 'sword'));
  PA.Flow.resolveOffer(run, off, off.choices[0]); assert.equal(run.growth.weapons[0].level, 2); assert.equal(PA.Flow.nextOffer(run, {}), null);
  // 무기 최대 레벨이면 무기 강화 후보 없음 → 대안(공통) → 그것도 없으면 금화
  const run2 = PA.Run.newRun(8, 'sword'); run2.growth.weapons[0].level = PA.GROWTH.SLOTS.weaponMax; const g0 = run2.gold;
  run2.growth.pendingMissionPick = { cardId: 'd1c1', kind: 'weapon_level', regionId: 'forest', fallbackGold: 40, key: 'k' };
  const off2 = PA.Flow.nextOffer(run2, {}); assert.ok(!off2 || off2.choices.every(c => c.kind !== 'weapon_level'));
  if (!off2) assert.equal(run2.gold, g0 + 40);
  const run3 = PA.Run.newRun(9, 'sword'); run3.growth.pendingMissionPick = { cardId: 'd1c1', kind: 'service', regionId: 'forest', fallbackGold: 40, key: 'k' };
  const off3 = PA.Flow.nextOffer(run3, {}); assert.equal(off3.pool, 'mission'); assert.ok(off3.choices.every(c => c.kind === 'service'));
  PA.Flow.resolveOffer(run3, off3, off3.choices.find(c => c.id === 'free_rest') || off3.choices[0]);
  if (run3.services.free_rest) { run3.hp = 10; run3.hours = 0; assert.ok(PA.Run.canRest(run3)); PA.Run.rest(run3); assert.equal(run3.hours, 0); assert.equal(run3.services.free_rest, 0); }
});
test('정예 추적: 정예가 첫 웨이브에 등장, 정예 체력 50%에 지원 1회(예산 유한), 정예와 지원병을 모두 처치해야 승리', () => {
  const { st } = mission(3, 'hunt'); steps(st, 1.5, {});
  const el = st.enemies.find(e => e.elite); assert.ok(el, '정예 등장'); assert.ok(st.enemies.filter(e => !e.elite && !e.structure).length >= 2, '호위');
  const before = st.enemies.length; el.hp = el.hpMax * 0.4; steps(st, 0.2, {}); steps(st, 1.0, {});
  assert.ok(st.obj.reinforceFired && st.obj.reinforce.spawned >= 1, '지원 소환'); assert.ok(st.obj.reinforce.budget < PA.OBJECTIVES.hunt.reinforce.budget, '예산 차감'); assert.ok(st.enemies.filter(e => !e.dead && !e.structure).length + st.pending.length <= PA.OBJECTIVES.hunt.reinforce.cap, '동시 상한');
  PA.Combat.damageEnemy(st, el, 99999, { src: { extra: true } }); PA.Combat.step(st, {}, dt);
  assert.equal(st.status, 'running', '지원병이 남아 있으면 계속'); steps(st, 1.2, {}); for (const e of st.enemies) if (!e.dead && !e.structure) PA.Combat.damageEnemy(st, e, 99999, { src: { extra: true } }); st.pending = []; PA.Combat.step(st, {}, dt); assert.equal(st.status, 'won', '정예·지원병 전멸 시 종료');
});
test('제단 파괴: 제단 3개가 서로·플레이어와 떨어져 유효 위치에 놓이고, 경험치 0·처치 수 제외, 모두 부수면 적이 남아도 승리, 부순 제단은 효과 정지', () => {
  const { st } = mission(4, 'altars', 'ridge'); const S = PA.OBJECTIVES.altars; const alts = st.obj.altars;
  assert.equal(alts.length, 3); for (let i = 0; i < 3; i++) { assert.ok(PA.Combat.validPos(st, alts[i].x, alts[i].y, alts[i].r)); assert.ok(PA.m.dist(alts[i], st.player) >= S.minPlayerGap - 1); for (let k = i + 1; k < 3; k++) assert.ok(PA.m.dist(alts[i], alts[k]) >= S.minGap - 1); }
  assert.equal(PA.Growth.xpValue(alts[0], 'ridge'), 0);
  const kills0 = st.stats.kills, xp0 = st.stats.xp; const heal = alts.find(a => a.altar === 'heal'), hz = alts.find(a => a.altar === 'hazard'), rf = alts.find(a => a.altar === 'reinforce');
  steps(st, 1.5, {}); const wolf = st.enemies.find(e => !e.structure && !e.dead); assert.ok(wolf); wolf.x = heal.x + 60; wolf.y = heal.y; wolf.hpMax = 1e6; wolf.hp = 1e6; wolf.state = 'recover'; wolf.stateT = -99; st.player.x = 20; st.player.y = 20;
  wolf.hp = 5; heal.timer = 0.01; steps(st, 0.1, {}); assert.ok(wolf.hp > 5, '치료 제단이 치료'); assert.ok(heal.budget < S.heal.budget);
  hz.timer = 0.01; steps(st, 0.1, {}); assert.ok(st.zones.some(z => z.type === 'hazard'), '위험 제단이 바닥 위험 예고');
  const hzZones = st.zones.filter(z => z.type === 'hazard'); assert.ok(hzZones.every(z => PA.m.dist(z, st.player) > z.r + st.player.r * 0.5), '예고 시점에 플레이어 위치를 덮지 않음(안전 통로)');
  PA.Combat.damageEnemy(st, heal, 99999, { src: { extra: true } }); assert.equal(st.stats.kills, kills0); assert.equal(st.stats.xp, xp0, '구조물은 경험치 없음');
  wolf.hp = 5; heal.timer = 0.01; steps(st, 0.5, {}); assert.equal(wolf.hp <= 5 + 0.01 || wolf.dead, true, '부순 치료 제단은 치료하지 않음');
  PA.Combat.damageEnemy(st, hz, 99999, { src: { extra: true } }); PA.Combat.damageEnemy(st, rf, 99999, { src: { extra: true } }); PA.Combat.step(st, {}, dt);
  assert.equal(st.status, 'won'); assert.ok(st.enemies.some(e => !e.dead && !e.structure), '적이 남아 있어도 승리');
});
test('봉인 해제: 지점 안에서만 진행, 밖에서는 멈추되 유지, 피격 시 잠시 정지, 절반에서 지점 이동(예고), 적이 남아도 완료', () => {
  const { st } = mission(6, 'seal'); const S = PA.OBJECTIVES.seal, o = st.obj, z = st.objects.find(x => x.kind === 'seal'); const p = st.player;
  st.waveIndex = 99; st.pending = []; o.reinforce.budget = 0; // 진행 규칙만 확인
  p.x = z.x; p.y = z.y; steps(st, 2, {}); assert.ok(o.progress > 1.8 && o.progress <= 2.01, '안에서 진행 ' + o.progress);
  p.x = z.x + z.r + 100; p.y = z.y; const keep = o.progress; steps(st, 1, {}); assert.equal(Math.round(o.progress * 100), Math.round(keep * 100), '밖에서는 유지');
  p.x = z.x; p.y = z.y; PA.Combat.damagePlayer(st, 1, 'test'); const k2 = o.progress; steps(st, S.hitPause * 0.8, {}); assert.equal(Math.round(o.progress * 100), Math.round(k2 * 100), '피격 후 정지');
  steps(st, S.time / 2, {}); assert.equal(o.stage, 2); assert.ok(z.moving || (z.x === o.points[1].x && z.y === o.points[1].y), '절반에서 지점 이동');
  steps(st, S.moveWarn + 0.1, {}); assert.equal(z.x, o.points[1].x); const st2 = st; p.x = z.x; p.y = z.y;
  const w2 = PA.Combat.spawnEnemy(st2, 'wolf', 60, 60); w2.hpMax = 1e6; w2.hp = 1e6; steps(st2, S.time, {}); assert.equal(st2.status, 'won'); assert.ok(st2.enemies.some(e => !e.dead && !e.structure));
});
test('포로 구출: 우리 근처에서만 진행·이어서 진행, 풀려난 포로는 스스로 출구로, 둘 다 구한 뒤 출구에 닿아야 승리', () => {
  const { st } = mission(7, 'rescue'); const S = PA.OBJECTIVES.rescue, o = st.obj, cages = st.objects.filter(x => x.kind === 'cage'), exit = st.objects.find(x => x.kind === 'exit'); const p = st.player;
  st.waveIndex = 99; st.pending = []; o.reinforce.budget = 0; for (const e of st.enemies) e.dead = true;
  assert.ok(PA.m.dist(cages[0], cages[1]) >= S.minGap - 1);
  p.x = cages[0].x + 20; p.y = cages[0].y; steps(st, S.time * 0.5, {}); assert.ok(cages[0].progress > 0 && !cages[0].freed);
  p.x = cages[0].x + 400; steps(st, 1, {}); const keep = cages[0].progress; assert.ok(keep > 0, '유지');
  p.x = cages[0].x + 20; steps(st, S.time * 0.6, {}); assert.ok(cages[0].freed); assert.equal(o.freed, 1); assert.ok(st.objects.some(x => x.kind === 'prisoner'));
  assert.equal(exit.open, false); p.x = exit.x; p.y = exit.y; steps(st, 0.5, {}); assert.equal(st.status, 'running', '한 명만 구하면 출구 닫힘');
  p.x = cages[1].x + 20; p.y = cages[1].y; steps(st, S.time + 0.2, {}); assert.equal(o.freed, 2); assert.equal(exit.open, true);
  steps(st, 6, {}); assert.ok(st.objects.filter(x => x.kind === 'prisoner').every(pr => pr.gone), '포로 탈출 완료'); assert.equal(st.status, 'running');
  p.x = exit.x; p.y = exit.y; PA.Combat.step(st, {}, dt); assert.equal(st.status, 'won');
});
test('목표 달성과 사망이 같은 단계에 겹치면 승리 우선(보스전 규칙과 동일), 시험실에서 목표 4종 시작 가능', () => {
  const { st } = mission(9, 'rescue'); const o = st.obj, exit = st.objects.find(x => x.kind === 'exit'); st.waveIndex = 99; st.pending = []; o.reinforce.budget = 0;
  for (const c of st.objects) if (c.kind === 'cage') { c.freed = true; c.progress = c.total; } o.freed = 2; PA.Combat.step(st, {}, dt); assert.equal(exit.open, true);
  st.player.x = exit.x; st.player.y = exit.y; st.player.hp = 1; PA.Combat.damagePlayer(st, 5, 'test'); assert.ok(st.pendingLoss); PA.Combat.step(st, {}, dt);
  assert.equal(st.status, 'won');
  for (const oid of PA.OBJECTIVE_IDS) { const cfg = PA.Lab.decode(`enemy=mission:${oid}:ridge;build=early_spear;seed=2;control=bot;bot=aggressive;time=90`); const run = PA.Lab.makeRun(cfg); const c = PA.Lab.makeCombat(cfg, run); assert.equal(c.objective, oid); assert.ok(c.obj); PA.Bot.runCombat(c, 'aggressive', { maxSec: 90 }); assert.equal(c.status, 'won', oid + ' 봇 완주 ' + c.status); }
});
