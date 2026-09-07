const test = require('node:test');
const assert = require('node:assert/strict');
const { load, runWith, fakeStorage, steps } = require('./load');
const PA = load();
const Gr = PA.Growth, R = PA.Run, CB = PA.Combat;
const j = (x) => JSON.parse(JSON.stringify(x));

test('경험치 곡선과 다중 레벨업: 필요치는 데이터, 한 번에 여러 레벨이면 선택 횟수 누락 없음', () => {
  const g = Gr.newGrowth('sword');
  const saved = Object.assign({}, PA.GROWTH.XP); Object.assign(PA.GROWTH.XP, PA.GROWTH.XP_CURVES.v05); // v0.5 곡선으로 검사(곡선은 데이터)
  assert.equal(Gr.xpNeed(1), 14); assert.equal(Gr.xpNeed(2), 18);
  assert.equal(Gr.addXp(g, 13), 0); assert.equal(g.pendingLevelUps, 0);
  assert.equal(Gr.addXp(g, 1), 1); assert.equal(g.level, 2); assert.equal(g.pendingLevelUps, 1);
  assert.equal(Gr.addXp(g, 18 + 22 + 5), 2); assert.equal(g.level, 4); assert.equal(g.pendingLevelUps, 3); assert.equal(g.xp, 5);
  Object.assign(PA.GROWTH.XP, saved);
  assert.equal(Gr.xpNeed(1), 20); assert.equal(Gr.xpNeed(3), Math.round(20 + 10 + 0.1 * 4)); // v0.6 임시 곡선
});

test('경험치는 적 사망 즉시, 처치 원인과 무관, 같은 적 1회, 동시 처치 합산, 바닥 구슬 없음', () => {
  const run = runWith(PA, { growth: { commons: { ember: 1 } } });
  const st = CB.create({ build: R.build(run), seed: 1, waves: [], objective: 'none' }); st.waveIndex = 99;
  const g = run.growth;
  const a = CB.spawnEnemy(st, 'wolf', 100, 100), b = CB.spawnEnemy(st, 'archer', 200, 100), c = CB.spawnEnemy(st, 'wolf', 300, 100);
  a.hp = 1; b.hp = 1; c.hp = 1;
  CB.damageEnemy(st, a, 5, {});                                   // 직접 공격
  assert.equal(g.xp, 6, '즉시 획득');
  CB.damageEnemy(st, a, 5, {}); assert.equal(g.xp, 6, '같은 적 중복 없음');
  st.zones.push({ type: 'fire', x: 200, y: 100, r: 40, ttl: 5, maxTtl: 5, dmg: 50, tick: 0, t: 0 }); // 지속 피해로 처치
  CB.step(st, {}, PA.CONFIG.STEP);
  assert.equal(g.xp, 13, '불길 처치도 인정');
  st.projectiles.push({ owner: 'player', kind: 'shard_common', x: 260, y: 100, vx: 100000, vy: 0, r: 4, dmg: 50, ttl: 1, hits: new Set() });
  CB.step(st, {}, PA.CONFIG.STEP);
  const total = 19; if (total >= Gr.xpNeed(1)) { assert.equal(g.level, 2); assert.equal(g.xp, total - Gr.xpNeed(1), '파편 처치 + 레벨업'); } else { assert.equal(g.level, 1); assert.equal(g.xp, total, '파편 처치(곡선상 아직 레벨업 전)'); }
  assert.equal(st.pickups.length, 0, '경험치 구슬 없음');
  const xpBefore = g.xp, lvBefore = g.level; const d = CB.spawnEnemy(st, 'wolf_alpha', 400, 100); d.hp = 1; d.summoned = true; CB.damageEnemy(st, d, 5, {}); assert.equal(g.xp + (g.level > lvBefore ? Gr.xpNeed(lvBefore) : 0), xpBefore + 6, '소환 적은 소환 경험치(레벨업 시 필요치 차감)');
});

test('슬롯 제한: 무기 3·방식 2·공통 3·패시브 4·기술 3레벨·변형 1. 초과·무효 후보는 제외된다', () => {
  const run = runWith(PA, {}); const g = run.growth;
  for (const id of ['spear', 'blades']) Gr.applyChoice(run, { kind: 'weapon_new', id });
  assert.throws(() => Gr.applyChoice(run, { kind: 'weapon_new', id: 'bow' }));
  assert.ok(!Gr.candidates(run, {}).some(c => c.kind === 'weapon_new'), '무기 슬롯이 차면 새 무기 후보 없음');
  for (let i = 0; i < 4; i++) Gr.applyChoice(run, { kind: 'weapon_level', id: 'sword' });
  assert.equal(Gr.weaponOf(g, 'sword').level, 5); assert.throws(() => Gr.applyChoice(run, { kind: 'weapon_level', id: 'sword' }));
  assert.ok(!Gr.candidates(run, {}).some(c => c.kind === 'weapon_level' && c.id === 'sword'));
  Gr.applyChoice(run, { kind: 'weapon_mod', id: 'sword', mod: 'cross' }); Gr.applyChoice(run, { kind: 'weapon_mod', id: 'sword', mod: 'crescent' });
  assert.throws(() => Gr.applyChoice(run, { kind: 'weapon_mod', id: 'sword', mod: 'scar' }));
  assert.ok(!Gr.candidates(run, {}).some(c => c.kind === 'weapon_mod' && c.id === 'sword'));
  for (const id of ['wide', 'reach', 'frost']) Gr.applyChoice(run, { kind: 'common', id });
  assert.throws(() => Gr.applyChoice(run, { kind: 'common', id: 'burn' }), '공통 슬롯 초과');
  assert.ok(Gr.candidates(run, {}).some(c => c.kind === 'common' && c.id === 'wide'), '보유 증강의 단계 상승은 후보');
  assert.ok(!Gr.candidates(run, {}).some(c => c.kind === 'common' && c.id === 'burn'), '새 종류는 제외');
  Gr.applyChoice(run, { kind: 'common', id: 'wide' }); assert.throws(() => Gr.applyChoice(run, { kind: 'common', id: 'wide' }), '최대 단계');
  for (const id of ['vitality', 'toughness', 'mastery', 'haste']) Gr.applyChoice(run, { kind: 'passive', id });
  assert.throws(() => Gr.applyChoice(run, { kind: 'passive', id: 'focus' }));
  Gr.applyChoice(run, { kind: 'skill_new', id: 'gust' }); assert.throws(() => Gr.applyChoice(run, { kind: 'skill_new', id: 'strike' }), 'E 슬롯 1개');
  assert.ok(!Gr.candidates(run, {}).some(c => c.kind === 'skill_new'));
  Gr.applyChoice(run, { kind: 'skill_variant', id: 'gust', slot: 'e', variant: 'whirl' }); assert.throws(() => Gr.applyChoice(run, { kind: 'skill_variant', id: 'gust', slot: 'e', variant: 'windpath' }), '변형 1개');
  Gr.applyChoice(run, { kind: 'skill_level', id: 'slowfield', slot: 'q' }); Gr.applyChoice(run, { kind: 'skill_level', id: 'slowfield', slot: 'q' }); assert.throws(() => Gr.applyChoice(run, { kind: 'skill_level', id: 'slowfield', slot: 'q' }));
});

test('전제·적용 대상: 불꽃 파열은 불길 공급원 필요, 긴 사거리는 적용 무기 필요, 시간의 복제는 투사체 무기 필요', () => {
  const run = runWith(PA, { start: 'blades' });
  const ids = (ctx) => Gr.candidates(run, ctx).map(c => c.key || Gr.keyOf(c));
  assert.ok(!ids({}).includes('common:flare'), '불길 없음 → 불꽃 파열 제외');
  assert.ok(!ids({}).includes('common:reach'), '회전 칼날만 → 긴 사거리 제외(적용 대상 없음)');
  Gr.applyChoice(run, { kind: 'common', id: 'ember' }); assert.ok(ids({}).includes('common:flare'));
  assert.ok(!ids({ pool: 'boss' }).includes('boss_reward:clone'), '투사체 무기 없음 → 시간의 복제 제외');
  Gr.applyChoice(run, { kind: 'weapon_new', id: 'bow' }); assert.ok(ids({ pool: 'boss' }).includes('boss_reward:clone')); assert.ok(ids({}).includes('common:reach'));
  assert.ok(!ids({}).some(k => k.startsWith('weapon_level:') && !['blades', 'bow'].some(w => k === 'weapon_level:' + w)), '장착하지 않은 무기의 강화 없음');
});

test('선택지 생성: 시드 결정적, 3개 서로 다른 대상, 같은 seq는 같은 결과(새로고침 재굴림 방지), 적용 후 다음 seq', () => {
  const a = runWith(PA, {}), b = runWith(PA, {});
  const oa = Gr.generateOffer(a, { regionId: 'forest' }), ob = Gr.generateOffer(b, { regionId: 'forest' });
  assert.deepEqual(j(oa.choices.map(c => c.key)), j(ob.choices.map(c => c.key)));
  assert.equal(oa.choices.length, 3); assert.equal(new Set(oa.choices.map(c => c.kind + c.id)).size, 3);
  const again = Gr.generateOffer(a, { regionId: 'forest' }); assert.equal(again, oa, '보류 중인 제시는 그대로');
  const saved = JSON.parse(R.serialize(a)); assert.deepEqual(j(saved.growth.pendingOffer.choices.map(c => c.key)), j(oa.choices.map(c => c.key)), '저장에 포함');
  Gr.applyChoice(a, oa.choices[0]); assert.equal(a.growth.pendingOffer, null);
  const o2 = Gr.generateOffer(a, { regionId: 'forest' }); assert.notEqual(o2.seq, oa.seq);
});

test('지역 태그·초반 보정 가중치: 태그 일치 후보와 초반 새 무기·E가 더 자주 나온다', () => {
  const run = runWith(PA, {}); const g = run.growth;
  const cands = Gr.candidates(run, { regionId: 'ridge' });
  const spearNew = cands.find(c => c.kind === 'weapon_new' && c.id === 'spear'), vit = cands.find(c => c.kind === 'passive' && c.id === 'vitality');
  assert.ok(spearNew.regionMatch); assert.ok(Gr.weightOf(g, spearNew) > Gr.weightOf(g, vit) * 3, `${Gr.weightOf(g, spearNew)} vs ${Gr.weightOf(g, vit)}`);
  let newW = 0, N = 60; for (let s = 0; s < N; s++) { const r = runWith(PA, {}); r.seed = s + 1; const o = Gr.generateOffer(r, { regionId: 'forest' }); if (o.choices.some(c => c.kind === 'weapon_new' || c.kind === 'skill_new')) newW++; }
  assert.ok(newW / N > 0.7, `초반 새 무기/E 제시 비율 ${newW}/${N}`);
  const deep = Gr.candidates(run, { regionId: 'marsh', pool: 'deep' }); assert.ok(deep.length && deep.every(c => c.regionMatch), '지역 보상 풀은 태그 후보만');
});

test('레거시 v2 저장 이행: 관통검·증강·강화가 새 슬롯으로 매핑되고, 공통 3개 초과는 삭제 대신 거점 선택으로', () => {
  const st = fakeStorage();
  const old = R.newRun(9); old.version = 2; delete old.growth; old.gear.weapon = 'pierce'; old.owned.push('pierce_sword'); old.gear.upgrade = 2; old.augments = { spin: 1, sharp: 2, quick: 1, wide: 1, ember: 1, frost: 1, flare: 1, saving: 1, barrier: 1, mark: 1 };
  st.setItem(R.SAVE_KEY, JSON.stringify(old));
  const r = R.load(st); const g = r.growth;
  assert.equal(r.version, 4); assert.equal(r.gear.weapon, undefined); assert.equal(r.forge, 2, '대장간 강화 → 공용 공격 강화 단계'); assert.ok(r.migrationNotes && r.log[0].includes('v0.8'), '변환 내용 기록');
  assert.deepEqual(j(g.weapons.map(w => w.id)), ['spear', 'sword', 'blades']);
  assert.equal(g.passives.mastery, 2); assert.equal(g.passives.haste, 1);
  assert.equal(g.skills.e.id, 'ward'); assert.equal(g.legacy.mark, 1);
  assert.ok(g.migrationPending && g.migrationPending.commons.length === 5, '공통 5개 → 이행 대기');
  assert.deepEqual(j(Object.keys(g.commons)), []);
  Gr.resolveMigration(r, ['frost', 'flare', 'saving', 'wide']); assert.deepEqual(j(Object.keys(r.growth.commons)).sort(), ['flare', 'frost', 'saving']); assert.equal(r.growth.migrationPending, null);
  const b = R.build(r); assert.equal(b.weapons.length, 3); assert.ok(Math.abs(b.damageMult - 1.2 * 1.2) < 1e-9, '공용 공격 강화 2단계(×1.2) × 무기 숙련 각 1회');
});

test('무기 레벨 배율은 누적(100/120/140/160/180%)이며 대장간 강화·숙련과 한 번씩 곱한다. 시작·추가 무기 성능 동일', () => {
  const run = runWith(PA, { gear: { upgrade: 1 }, growth: { weapons: [{ id: 'sword', level: 3 }, { id: 'blades', level: 1 }], passives: { mastery: 1 } } });
  const b = R.build(run);
  assert.ok(Math.abs(b.weapons[0].damage - 12 * 1.4 * 1.1 * 1.1) < 1e-9);
  const run2 = runWith(PA, { gear: { upgrade: 1 }, growth: { weapons: [{ id: 'blades', level: 1 }, { id: 'sword', level: 3 }], passives: { mastery: 1 } } });
  const b2 = R.build(run2);
  assert.equal(b2.weapons[1].damage, b.weapons[0].damage, '같은 무기·같은 레벨이면 시작/추가와 무관하게 같은 피해');
  assert.equal(b2.weapons[0].damage, b.weapons[1].damage);
  assert.ok(Math.abs(b.weapons[1].damage - PA.WEAPONS.blades.base.damage * 1.0 * 1.1 * 1.1) < 1e-9, '추가 무기 피해에 시작 무기 레벨을 쓰지 않음');
});

test('보스 재도전은 입장 시점 성장으로 복구된다(소환 경험치 누적 악용 방지)', () => {
  const run = runWith(PA, {}); run.day = 7; run.phase = 'boss_prep';
  run.growth.level = 5; run.growth.xp = 3;
  R.startBoss(run);
  Gr.addXp(run.growth, 500); Gr.applyChoice(run, { kind: 'passive', id: 'vitality' });
  assert.ok(run.growth.level > 5);
  R.bossDefeat(run);
  assert.equal(run.growth.level, 5); assert.equal(run.growth.xp, 3); assert.equal(run.growth.passives.vitality, undefined);
});

test('카드 설명은 실제 파생 계산을 재사용한다(관통창 2→3 기본 피해)', () => {
  const run = runWith(PA, { growth: { weapons: [{ id: 'spear', level: 2 }] } });
  const d = Gr.describe(run, { kind: 'weapon_level', id: 'spear' });
  const b1 = R.build(run); const r2 = j(run); Gr.applyChoice(r2, { kind: 'weapon_level', id: 'spear' }); const b2 = R.build(r2);
  assert.equal(d.title, '관통창 2→3'); assert.ok(d.change.includes(`${PA.fmt.num(b1.weapons[0].damage)} → ${PA.fmt.num(b2.weapons[0].damage)}`), d.change);
  const dm = Gr.describe(run, { kind: 'weapon_mod', id: 'spear', mod: 'returning' }); assert.ok(dm.slot.includes('1/2'));
});
