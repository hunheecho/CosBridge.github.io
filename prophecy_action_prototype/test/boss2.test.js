// 신규 보스 2종(봉인 수호자·예언을 먹는 자) 패턴 규칙과 회차 구조(3보스)·희귀 보상 연결
const test = require('node:test'); const assert = require('node:assert');
const { load, fakeStorage } = require('./load');
const PA = load(); const dt = PA.CONFIG.STEP; const j = (x) => JSON.parse(JSON.stringify(x));
function bossFight(bossId, buildId, seed) { const cfg = PA.Lab.decode(`enemy=boss:${bossId};build=${buildId || 'stage2'};seed=${seed || 1};control=bot;bot=balanced;time=300`); const run = PA.Lab.makeRun(cfg); const st = PA.Lab.makeCombat(cfg, run); return { run, st, bz: st.boss }; }
const steps = (st, sec, inp) => { for (let i = 0; i < Math.round(sec / dt); i++) PA.Combat.step(st, inp || {}, dt); };
function skipIntro(st) { steps(st, PA.Boss.cfgOf(st.boss).intro + 0.05); }

test('봉인 수호자: 직선 충격파는 확정 방향으로 파동이 날아가고(재추적 없음) 감속장 안에서 느려지며, 휩쓸기는 부채꼴 안만, 장치 3개는 경험치 0·파괴 시 그 패턴 정지', () => {
  const { st, bz } = bossFight('guardian'); const cfg = PA.Boss.cfgOf(bz); skipIntro(st);
  assert.equal(bz.bossId, 'guardian'); assert.equal(bz.devices.length, 3); assert.ok(bz.devices.every(d => d.structure && PA.Growth.xpValue(d, null) === 0));
  for (let i = 0; i < 3; i++) for (let k = i + 1; k < 3; k++) assert.ok(PA.m.dist(bz.devices[i], bz.devices[k]) >= cfg.devices.minGap - 1);
  // 첫 행동은 충격파: 준비 → 확정(방향 고정) → 파동
  let guard = 0; while (bz.state !== 'shock_lock' && guard++ < 4000) PA.Combat.step(st, {}, dt); assert.equal(bz.state, 'shock_lock'); const dir = bz.dir;
  st.player.x += 200; steps(st, cfg.shock.lock + 0.05); assert.equal(bz.state, 'recover'); const wave = st.projectiles.find(p => p.kind === 'shock'); assert.ok(wave, '파동 생성'); assert.ok(Math.abs(Math.atan2(wave.vy, wave.vx) - dir) < 1e-6, '방향 고정');
  // 감속장 안 파동은 느려진다
  const x0 = wave.x; st.field = { x: wave.x, y: wave.y, r: 400, ttl: 5, maxTtl: 5 }; steps(st, 0.1); const slowMove = Math.hypot(wave.x - x0, wave.y - wave.y); st.field = null;
  assert.ok(slowMove < cfg.shock.speed * 0.1 * 0.5, '감속 ' + slowMove);
  // 장치 파괴: 그 장치의 위험 생성이 멈춘다(다른 장치는 계속)
  const d0 = bz.devices[0]; PA.Combat.damageEnemy(st, d0, 99999, { src: { extra: true } }); assert.ok(d0.dead); assert.equal(st.stats.xp, 0);
  for (const d of bz.devices) d.timer = 0.01; const z0 = st.zones.filter(z => z.type === 'hazard').length; steps(st, 0.1); const made = st.zones.filter(z => z.type === 'hazard').length - z0;
  assert.ok(made > 0 && made <= 2 * cfg.devices.n, '살아 있는 장치 2개만 위험 생성 ' + made);
  assert.ok(!bz.invuln && bz.hp > 0); PA.Combat.damageEnemy(st, bz, 100, { src: { extra: true } }); assert.ok(bz.hp <= bz.hpMax - 99, '완전 무적 없음');
});
test('예언을 먹는 자: 표식은 지난 위치에 공개되어 정해진 시각에 순차 폭발(현재 위치가 아님), 두 줄 직선은 순차 발사, 광역 뒤 긴 빈틈, 소환 총량·동시 상한', () => {
  const { st, bz } = bossFight('eater'); const cfg = PA.Boss.cfgOf(bz); skipIntro(st); const p = st.player;
  // 첫 행동은 두 줄 직선
  let guard = 0; while (bz.state !== 'lanes_lock' && guard++ < 4000) PA.Combat.step(st, {}, dt); assert.equal(bz.lanes.length, 2); assert.ok(Math.abs(((bz.lanes[1].ang - bz.lanes[0].ang) * 180 / Math.PI) - cfg.lanes.secondDeg) < 1e-6);
  steps(st, cfg.lanes.lock + 0.05); assert.equal(st.projectiles.filter(q => q.kind === 'shock').length, 1, '첫 줄만 발사'); steps(st, cfg.lanes.gap + cfg.lanes.lock + 0.1); assert.ok(bz.laneIdx === 2 && bz.lanes.every(l => l.fired) && bz.state === 'recover', '둘째 줄 뒤 빈틈');
  // 표식: 플레이어 이동 궤적을 강제로 넣고 시전
  bz.state = 'approach'; bz.stateT = 0; bz.approachT = 9; bz.history = ['lanes', 'wide']; bz.trail = [{ x: 100, y: 100 }, { x: 160, y: 100 }, { x: 220, y: 100 }, { x: 280, y: 100 }, { x: 340, y: 100 }]; p.x = 600; p.y = 500;
  PA.Boss2.summon; bz.state = 'mark_cast'; bz.stateT = 0; steps(st, cfg.mark.cast + 0.02);
  assert.equal(bz.state, 'mark_wait'); assert.equal(bz.marks.length, cfg.mark.count[0]); assert.ok(bz.marks.every(mk => mk.y === 100 && mk.x !== 600), '표식은 과거 위치');
  const hp0 = p.hp; steps(st, cfg.mark.delay + cfg.mark.gap * cfg.mark.count[0] + 0.1); assert.equal(p.hp, hp0, '표식 밖이면 무피해'); assert.equal(bz.marks.length, 0); assert.equal(bz.state, 'recover');
  // 광역: 원 밖은 무피해, 뒤에 긴 빈틈
  bz.state = 'wide_aim'; bz.stateT = 0; p.x = bz.x + cfg.wide.radius[0] + 60; p.y = bz.y; const h1 = p.hp; steps(st, cfg.wide.aim + cfg.wide.lock + 0.05); assert.equal(p.hp, h1); assert.equal(bz.state, 'recover'); assert.equal(bz.recoverDur, cfg.wide.recover);
  // 소환: 총 예산·동시 상한
  bz.summonBudget = cfg.summon.budget; bz.lastSummon = -999; bz.state = 'summon'; bz.stateT = 0; steps(st, cfg.summon.duration + 0.05); assert.ok(st.pending.filter(s => s.summoned).length + PA.Boss.summonedAlive(st) <= cfg.summon.cap); assert.equal(bz.summonBudget, cfg.summon.budget - Math.min(cfg.summon.count, cfg.summon.cap));
});
test('3보스 회차: 일정(1~2일 준비, 3일차 관문, 승리 시 그날 5시간, 5일차 관문, 7일차 최종), 관문에서는 출격 불가', () => {
  const run = PA.Run.newRun(5, 'sword', 'trio'); const R = PA.Run;
  assert.equal(R.stageCount(run), 3); assert.equal(R.nextBoss(run).id, 'boss'); assert.equal(R.bossDaysLeft(run), 2); assert.equal(R.isBossDay(run), false);
  R.endDay(run); assert.equal(run.phase, 'prep'); R.endDay(run); assert.equal(run.day, 3); assert.equal(run.phase, 'boss_prep'); assert.equal(R.canSortie(run, 'forest'), false); assert.throws(() => R.endDay(run));
  const s = R.startBoss(run); assert.equal(s.bossId, 'boss'); assert.equal(R.bossHp(run, 'boss'), PA.BOSS_HP.boss.stage1); assert.ok(run.bossEntry);
  const st = PA.Flow.makeBossEncounter(run, s); assert.equal(st.boss.hpMax, PA.BOSS_HP.boss.stage1); assert.equal(st.bossId, 'boss');
  st.status = 'won'; st.stats.elapsed = 30; const rec = PA.Flow.settleBossVictory(run, st);
  assert.equal(rec.bossId, 'boss'); assert.equal(run.stage, 1); assert.equal(run.phase, 'prep'); assert.equal(run.day, 3); assert.equal(run.hours, PA.CONFIG.HOURS_PER_DAY); assert.equal(R.canSortie(run, 'forest'), true);
  assert.ok(run.growth.pendingBossPick && run.growth.pendingBossPick.bossId === 'boss'); assert.equal(R.nextBoss(run).id, 'guardian'); assert.equal(R.bossDaysLeft(run), 2);
  R.endDay(run); R.endDay(run); assert.equal(run.day, 5); assert.equal(run.phase, 'boss_prep'); const s2 = R.startBoss(run); assert.equal(s2.bossId, 'guardian'); assert.notEqual(s2.seed, s.seed);
  const st2 = PA.Flow.makeBossEncounter(run, s2); assert.equal(st2.boss.bossId, 'guardian'); assert.equal(st2.boss.hpMax, PA.BOSS_HP.guardian.stage2); st2.status = 'won'; PA.Flow.settleBossVictory(run, st2);
  assert.equal(run.stage, 2); assert.equal(run.phase, 'prep'); R.endDay(run); R.endDay(run); assert.equal(run.day, 7); assert.equal(run.phase, 'boss_prep');
  const s3 = R.startBoss(run); assert.equal(s3.bossId, 'eater'); const st3 = PA.Flow.makeBossEncounter(run, s3); st3.status = 'won'; run.growth.pendingBossPick = null; run.growth.pendingOffer = null; PA.Flow.settleBossVictory(run, st3);
  assert.equal(run.phase, 'cleared'); assert.equal(run.ended, true); assert.equal(run.growth.pendingBossPick, null, '마지막 보스 뒤 희귀 보상 없음'); assert.equal(R.nextBoss(run), null); assert.equal(Object.keys(run.bossRecords).length, 3);
});
test('보스 재도전: 입장 스냅샷으로 복구되어 처치 경험치·보상이 중복되지 않고, 처치 기록은 1회, 희귀 보상은 저장을 거쳐도 1회', () => {
  const run = PA.Run.newRun(6, 'sword', 'trio'); run.growth.level = 8; PA.Run.endDay(run); PA.Run.endDay(run);
  const s = PA.Run.startBoss(run); const snap = j(run.growth);
  const st = PA.Flow.makeBossEncounter(run, s); PA.Growth.addXp(run.growth, 500); // 전투 중 소환 처치 경험치 가정
  st.status = 'lost'; PA.Flow.settleBossDefeat(run, st); assert.deepEqual(j(run.growth), snap, '패배 시 성장 복구'); assert.equal(run.bossRetries, 1);
  const s2 = PA.Run.startBoss(run); assert.equal(s2.seed, s.seed, '같은 시드'); const st2 = PA.Flow.makeBossEncounter(run, s2); st2.status = 'won'; st2.stats.elapsed = 40;
  PA.Flow.settleBossVictory(run, st2); const rec = run.bossRecords.boss; assert.equal(rec.retries, 1); assert.equal(run.stage, 1);
  const store = fakeStorage(); PA.Run.save(run, store); const run2 = PA.Run.load(store);
  const off = PA.Flow.nextOffer(run2, {}); assert.ok(off && off.pool === 'boss', '희귀 보상 제시'); assert.ok(off.choices.length >= 1 && off.choices.length <= 3);
  assert.ok(off.choices.every(c => c.kind === 'boss_reward' && !run2.growth.bossRewards.includes(c.id)));
  PA.Run.save(run2, store); const run3 = PA.Run.load(store); assert.deepEqual(j(PA.Flow.nextOffer(run3, {})), j(off), '저장 뒤 같은 제시(재굴림 없음)');
  PA.Flow.resolveOffer(run3, off, off.choices[0]); assert.equal(run3.growth.bossRewards.length, 1); assert.equal(PA.Flow.nextOffer(run3, {}), null, '두 번째 제시 없음');
  // 다시 정산해도(같은 보스) 기록·보상 중복 없음
  const before = j(run3.bossRecords.boss); const st3 = PA.Flow.makeBossEncounter(run3, PA.Run.startBoss(Object.assign(run3, { phase: 'boss_prep' }))); st3.status = 'won'; run3.stage = 0; PA.Run.bossVictory(run3, st3.stats); assert.deepEqual(j(run3.bossRecords.boss), before);
});
test('희귀 보상 후보: 적용 가능한 것만(투사체 없으면 복제 제외, E 없으면 일제 공격 제외), 부족하면 범용으로 채움, 이전 저장은 단일 보스 규칙', () => {
  const run = PA.Run.newRun(7, 'sword', 'trio'); const g = run.growth; g.skills.e = null; g.commons = {};
  const c = PA.Growth.candidates(run, { pool: 'boss' }); const ids = c.map(x => x.id);
  assert.ok(!ids.includes('clone') && !ids.includes('volley') && !ids.includes('seed') && !ids.includes('resonance'), ids.join(','));
  assert.ok(ids.includes('vigor') && ids.includes('tempo'), '범용 채움');
  const hp0 = PA.Run.build(run).hpMax; PA.Growth.applyChoice(run, { kind: 'boss_reward', id: 'vigor' }); assert.equal(PA.Run.build(run).hpMax, hp0 + 25);
  const cd0 = PA.Run.build(run).specialCd; PA.Growth.applyChoice(run, { kind: 'boss_reward', id: 'tempo' }); assert.ok(PA.Run.build(run).specialCd < cd0);
  const old = PA.Run.newRun(3, 'sword', 'single'); delete old.mode; delete old.stage; delete old.bossesDone; delete old.bossRecords; const store = fakeStorage(); store.setItem(PA.Run.SAVE_KEY, JSON.stringify(old)); const loaded = PA.Run.load(store);
  assert.equal(loaded.mode, 'single'); assert.equal(PA.Run.stageCount(loaded), 1); assert.equal(PA.Run.bossDaysLeft(loaded), 6); assert.equal(PA.Run.bossHp(loaded, 'boss'), 2400);
  // 시험실 빠른 경로: 단계별 관문 직전 회차
  for (let i = 0; i < 3; i++) { const q = PA.Lab.quickRun(i); assert.equal(q.phase, 'boss_prep'); assert.equal(PA.Run.nextBoss(q).id, PA.RUN_MODES.trio.bosses[i].id); assert.equal(q.day, PA.RUN_MODES.trio.bosses[i].day); assert.ok(PA.Run.canStartBoss(q)); }
});
test('밸런스 후보 세트: 추천안 적용 시 경험치 배율·보스 체력·창 기본값이 바뀌고 현재값으로 되돌릴 수 있다. 회차에 기록되고 시험실은 현재값', () => {
  const w0 = PA.Growth.xpValue({ type: 'wolf' }, 'forest'), spear0 = Object.assign({}, PA.WEAPONS.spear.base);
  const run = PA.Run.newRun(3, 'spear', 'trio', 'recommended'); PA.Balance.applyRun(run);
  assert.equal(run.balance, 'recommended'); assert.equal(run.difficulty, 'candE'); assert.equal(PA.Run.bossHp(run, 'guardian'), 5000); assert.equal(PA.Run.bossHp(run, 'boss'), 2400);
  assert.equal(PA.Growth.xpValue({ type: 'wolf' }, 'forest'), Math.round(w0 * 0.5)); assert.equal(PA.WEAPONS.spear.base.interval, 0.85); assert.equal(PA.WEAPONS.spear.base.sweetFrom, 0.45); assert.equal(PA.WEAPONS.spear.base.range, spear0.range);
  assert.equal(PA.Run.regionBonusXp('forest', false), 5); assert.ok(/추천안/.test(PA.Run.layoutText(run)));
  const b = PA.Run.build(run); assert.equal(b.weapons[0].interval > spear0.interval, true, '창 주기 반영');
  PA.Balance.apply('current'); assert.equal(PA.Growth.xpValue({ type: 'wolf' }, 'forest'), w0); assert.deepEqual(PA.WEAPONS.spear.base, spear0); assert.equal(PA.BOSS_HP_SET, 'base');
  const old = PA.Run.newRun(3, 'sword'); assert.equal(old.balance, 'current'); assert.equal(PA.Run.bossHp(old, 'guardian'), 3000);
});
test('창 근접 약화·관통 제한 규칙(데이터): 사거리 45% 안쪽은 피해 ×0.5, maxTargets는 관통 수 제한. 기본값에는 없음', () => {
  const { load, combat, steps } = require('./load'); const P2 = load(); const base = Object.assign({}, P2.WEAPONS.spear.base);
  P2.WEAPONS.spear.base = Object.assign({}, base, { sweetFrom: 0.45, sweetMult: 0.5, maxTargets: 2 });
  const { st } = combat(P2, { start: 'spear', seed: 1 }); const p = st.player; const mk = (x) => { const e = P2.Combat.spawnEnemy(st, 'wolf', p.x + x, p.y); e.hpMax = 1e6; e.hp = 1e6; e.state = 'recover'; e.stateT = -99; return e; };
  const near = mk(40), mid = mk(160), far = mk(200), far2 = mk(220);
  steps(P2, st, 1.0, {}, undefined, [[near, p.x + 40, p.y], [mid, p.x + 160, p.y], [far, p.x + 200, p.y], [far2, p.x + 220, p.y]]);
  const dmg = (e) => 1e6 - e.hp; assert.ok(dmg(near) > 0 && dmg(mid) > 0, '가까운 둘 적중'); assert.ok(Math.abs(dmg(near) * 2 - dmg(mid)) < 1e-6 || dmg(near) < dmg(mid), '근접 약화 ' + dmg(near) + ' vs ' + dmg(mid)); assert.equal(dmg(far), 0, '관통 2명 제한'); assert.equal(dmg(far2), 0);
  P2.WEAPONS.spear.base = base;
});
