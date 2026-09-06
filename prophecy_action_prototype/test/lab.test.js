const test = require('node:test');
const assert = require('node:assert/strict');
const { load, fakeStorage, steps } = require('./load');
const PA = load();
const CB = PA.Combat, L = PA.Lab;
const j = (x) => JSON.parse(JSON.stringify(x));
function labCombat(cfgText, extra) { const cfg = L.decode(cfgText); Object.assign(cfg, extra || {}); const run = L.makeRun(cfg); return { cfg, run, st: L.makeCombat(cfg, run) }; }

test('빌드 프리셋 8종 이상이 모두 게임 규칙(슬롯·레벨·방식·전제)을 지키고 선택 횟수가 계산된다', () => {
  const ids = Object.keys(PA.LAB.BUILDS);
  assert.ok(ids.length >= 8);
  for (const id of ids) { const d = L.describeBuild(id); assert.equal(d.errors.length, 0, id + ': ' + d.errors.join(',')); assert.ok(d.picks >= 0); assert.ok(['초반', '중간', '후반'].includes(d.stage)); }
  assert.equal(L.describeBuild('early_sword').picks, 0);
  assert.equal(L.describeBuild('mid_melee').picks, 8);
  // 규칙 위반 프리셋은 잡아낸다
  assert.ok(L.validateBuild({ growth: { weapons: [{ id: 'sword', level: 6 }] } }).length > 0, '레벨 6');
  assert.ok(L.validateBuild({ growth: { weapons: [{ id: 'sword', level: 1, mods: ['cross', 'scar', 'crescent'] }] } }).length > 0, '방식 3개');
  assert.ok(L.validateBuild({ growth: { weapons: [{ id: 'sword' }, { id: 'spear' }, { id: 'bow' }, { id: 'orb' }] } }).length > 0, '무기 4개');
  assert.ok(L.validateBuild({ growth: { weapons: [{ id: 'sword' }], commons: { wide: 1, reach: 1, frost: 1, burn: 1 } } }).length > 0, '공통 4개');
  assert.ok(L.validateBuild({ growth: { weapons: [{ id: 'sword' }], commons: { flare: 1 } } }).length > 0, '불꽃 파열 전제');
});

test('설정 문자열 왕복: 인코딩→디코딩이 같고, 잘못된 값은 기본값으로 정규화된다', () => {
  const c = L.defaultConfig(); c.enemy = 'solo:archer'; c.hp = { normal: 3, elite: 2, boss: 1.5 }; c.seed = 42; c.build = 'late_multi'; c.control = 'bot'; c.bot = 'survival'; c.growth = 'grow'; c.time = 120; c.deep = true; c.overlap = 2;
  assert.deepEqual(j(L.decode(L.encode(c))), j(c));
  const bad = L.decode('enemy=nope;build=nope;bot=nope;hp=0,-1;seed=-5;time=3;control=x;growth=y');
  assert.equal(bad.enemy, 'region:forest'); assert.equal(bad.build, 'early_sword'); assert.equal(bad.bot, 'balanced'); assert.deepEqual(j(bad.hp), { normal: 1, elite: 1, boss: 1 }); assert.equal(bad.seed, 1); assert.equal(bad.time, PA.LAB.DEFAULT_TIME); assert.equal(bad.control, 'human'); assert.equal(bad.growth, 'fixed');
  assert.equal(L.decode(JSON.stringify(c)).seed, 42, 'JSON도 받는다');
});

test('체력 배율은 체력에만 적용된다(일반·정예·보스 따로). 피해·속도·예고 시간·경험치는 그대로', () => {
  const { st } = labCombat('enemy=solo:wolf;hp=3,2,1.5;build=early_sword');
  const w = CB.spawnEnemy(st, 'wolf', 100, 100), a = CB.spawnEnemy(st, 'wolf_alpha', 200, 100), b = CB.spawnEnemy(st, 'boss', 300, 100);
  assert.equal(w.hp, 90); assert.equal(w.hpMax, 90); assert.equal(a.hp, 240); assert.equal(b.hp, 3600);
  assert.equal(w.def.damage, 12); assert.equal(w.def.speed, 150); assert.equal(w.def.crouch, 0.6);
  assert.equal(PA.Growth.xpValue(w), 6);
  const { st: st1 } = labCombat('enemy=solo:wolf;hp=1,1,1'); assert.equal(CB.spawnEnemy(st1, 'wolf', 100, 100).hp, 30);
});

test('측정: 공격 준비·실행·공격 전 사망·처치 소요·피해 출처(과잉 피해 제외)·받은 피해 원인이 기록된다', () => {
  const { st } = labCombat('enemy=solo:wolf;hp=1,1,1;build=early_sword;time=60');
  st.waveIndex = 99; st.spawnedAll = true;
  const p = st.player; p.x = 480; p.y = 300;
  const w1 = CB.spawnEnemy(st, 'wolf', 900, 300); // 접근 중 사망: 공격 전
  CB.damageEnemy(st, w1, 100, { src: { weaponId: 'sword', direct: true } });
  assert.equal(st.metrics.dmg['weapon:sword'], 30, '과잉 피해 제외');
  const w2 = CB.spawnEnemy(st, 'wolf', p.x + 120, p.y); // 돌진까지 수행
  steps(PA, st, 1.2, {}, PA.CONFIG.STEP, [[p, 480, 300]]);
  assert.ok(st.metrics.enemies.wolf.prepared >= 1); assert.ok(st.metrics.enemies.wolf.executed >= 1, '돌진 실행');
  assert.ok(st.metrics.taken.wolf > 0, '받은 피해 원인 늑대'); assert.equal(st.metrics.takenHits.wolf, 1);
  CB.damageEnemy(st, w2, 100, { src: { skill: true, skillId: 'strike', direct: false } });
  const m = st.metrics.enemies.wolf;
  assert.equal(m.spawned, 2); assert.equal(m.killed, 2); assert.equal(m.diedBeforeAttack, 1); assert.equal(m.ttk.length, 2); assert.ok(m.ttk[0] < 0.01 && m.ttk[1] >= 1.19);
  assert.ok(st.metrics.dmg['skill:strike'] > 0);
  // 포자 사망 구름은 능동 공격과 따로
  const sp = CB.spawnEnemy(st, 'spore', 100, 100); CB.damageEnemy(st, sp, 999, { src: { weaponId: 'sword', direct: true } });
  assert.equal(st.metrics.enemies.spore.executed, 0); assert.equal(st.metrics.enemies.spore.deathEffects, 1); assert.equal(st.metrics.enemies.spore.diedBeforeAttack, 1);
  // 지속 피해·공통 효과 출처
  const w3 = CB.spawnEnemy(st, 'wolf', 700, 500); w3.burn = { t: 2, dps: 4 }; steps(PA, st, 0.6, {}, PA.CONFIG.STEP, [[p, 480, 300], [w3, 700, 500]]);
  assert.ok(st.metrics.dmg['dot:burn'] > 0, '화상 출처');
  const s = CB.summary(st); assert.equal(s.enemies.wolf.diedBeforeAttackRate, 0.5); assert.ok(s.dmgTotal > 0); assert.equal(s.hpMult.normal, 1);
});

test('시간 제한에 닿으면 승패와 별도인 timeout 상태가 되고, 봇 실행은 그 상태로 멈춘다', () => {
  const { st } = labCombat('enemy=solo:wolf;build=early_sword;time=10;control=bot');
  st.waveIndex = 99; st.objective = 'none'; // 자동 승리 방지
  PA.Bot.runCombat(st, 'balanced', { maxSec: 60 });
  assert.equal(st.status, 'timeout'); assert.ok(Math.abs(st.t - 10) < 0.02);
  assert.equal(CB.summary(st).status, 'timeout');
});

test('빌드 고정 모드에서는 경험치·레벨업이 없고, 성장 모드에서는 있다', () => {
  const fixed = labCombat('enemy=solo:wolf;build=early_sword;growth=fixed'); const grow = labCombat('enemy=solo:wolf;build=early_sword;growth=grow');
  for (const { st } of [fixed, grow]) { const w = CB.spawnEnemy(st, 'wolf', 100, 100); CB.damageEnemy(st, w, 999, {}); }
  assert.equal(fixed.run.growth.xp, 0); assert.equal(fixed.st.stats.xp, 0);
  assert.equal(grow.run.growth.xp, 6); assert.equal(grow.st.stats.xp, 6);
});

test('시험실 저장은 별도 키만 쓴다: 정식 회차 저장 키에는 아무것도 쓰지 않는다', () => {
  const store = fakeStorage();
  const cfg = L.decode('enemy=region:den;hp=2,2,2;seed=3');
  L.saveConfig(cfg, store); L.saveResults([{ a: 1 }], store);
  assert.equal(store.getItem(PA.Run.SAVE_KEY), null); assert.equal(store.getItem(PA.Run.RECORDS_KEY), null);
  assert.deepEqual(j(L.loadConfig(store)), j(cfg)); assert.deepEqual(j(L.loadResults(store)), [{ a: 1 }]);
  const run = L.makeRun(cfg); assert.equal(run.lab, true);
});

test('봇 정책 3종은 같은 상황에서 다르게 판단한다: 생존 우선은 준비 초기 예고에도 피하고, 공격 우선은 확정 전에는 접근한다', () => {
  const { st } = labCombat('enemy=solo:wolf;build=early_sword');
  st.waveIndex = 99; const p = st.player; p.x = 480; p.y = 300;
  const w = CB.spawnEnemy(st, 'wolf', 480 + 120, 300); w.state = 'crouch'; w.stateT = 0.1; w.aimAngle = Math.PI; // 왼쪽(플레이어)을 향해 준비 시작
  const a = PA.Bot.decide('aggressive', st, {}), b = PA.Bot.decide('balanced', st, {}), s = PA.Bot.decide('survival', st, {});
  assert.ok(a.mx > 0.5 && Math.abs(a.my) < 0.3, '공격 우선: 늑대 쪽으로 접근');
  assert.ok(Math.abs(s.my) > 0.7, '생존 우선: 옆으로 벗어남');
  assert.equal(a.dodge, false); assert.equal(s.dodge, false, '확정 전에는 회피를 쓰지 않음');
  w.state = 'lock'; w.dir = Math.PI; w.stateT = 0;
  for (const id of ['aggressive', 'balanced', 'survival']) { const r = PA.Bot.decide(id, st, {}); assert.equal(r.dodge, true, id + ' 확정 통로 안이면 회피'); assert.ok(Math.abs(r.my) > 0.7, id + ' 옆으로'); }
  const doc = PA.Bot.POLICIES.balanced.doc; for (const k of ['period', 'reads', 'target', 'q', 'e', 'dodge', 'terrain', 'giveUp']) assert.ok(doc[k], k);
});

test('동시 공격 제한: overlapLimit 1이면 준비·확정·실행 중인 늑대가 동시에 1마리를 넘지 않는다(제한 없음이면 넘는다)', () => {
  for (const [limit, expectMax] of [[1, 1], [0, 2]]) {
    const { st } = labCombat('enemy=solo:wolf;build=early_sword', { overlap: limit });
    st.waveIndex = 99; const p = st.player; p.x = 480; p.y = 300; p.hp = 100000; p.hpMax = 100000;
    for (const [x, y] of [[560, 300], [480, 380], [400, 300], [480, 220]]) CB.spawnEnemy(st, 'wolf', x, y);
    let maxCommitted = 0; const dt = PA.CONFIG.STEP;
    for (let i = 0; i < Math.round(3 / dt); i++) { CB.step(st, {}, dt); p.x = 480; p.y = 300; const n = st.enemies.filter(e => !e.dead && CB.isCommitted(e)).length; if (n > maxCommitted) maxCommitted = n; }
    if (limit) assert.ok(maxCommitted <= expectMax, `제한 ${limit}: 최대 ${maxCommitted}`); else assert.ok(maxCommitted >= expectMax, `제한 없음: 최대 ${maxCommitted}`);
  }
});

test('재현성: 같은 설정·시드·봇이면 결과 요약이 완전히 같다', () => {
  const run1 = () => { const { st } = labCombat('enemy=region:ridge;hp=2,2,2;seed=9;build=mid_ranged;control=bot;bot=balanced;time=120'); PA.Bot.runCombat(st, 'balanced', { maxSec: 120 }); const s = CB.summary(st); delete s.version; return j(s); };
  assert.deepEqual(run1(), run1());
});
