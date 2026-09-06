// 성장 시스템(회차 상태 쪽): 경험치·레벨, 무기/공통/패시브/기술 슬롯, 선택지 생성(시드 결정적), 레거시 저장 매핑.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Growth = (function () {
  const G = () => PA.GROWTH;
  const W = () => PA.WEAPONS;

  function newGrowth(startWeapon) {
    return {
      level: 1, xp: 0, pendingLevelUps: 0, choiceSeq: 0, pendingOffer: null, lastKind: null,
      weapons: [{ id: startWeapon || 'sword', level: 1, mods: [] }],
      commons: {}, passives: {}, skills: { q: { id: 'slowfield', level: 1, variant: null }, e: null },
      bossRewards: [], legacy: {}, migrationPending: null, picks: { weapon_new: 0, weapon_level: 0, weapon_mod: 0, common: 0, skill_new: 0, skill_level: 0, skill_variant: 0, passive: 0, skip: 0 },
      log: [],
    };
  }
  function ensure(run) { if (!run.growth) run.growth = migrateFromLegacy(run); return run.growth; }

  // ---------- 경험치 ----------
  function xpNeed(level) { const X = G().XP, k = level - 1; return Math.round(X.base + X.step * k + (X.quad || 0) * k * k); }
  function addXp(g, amount) {
    if (amount <= 0 || g.level >= G().XP.maxLevel) return 0;
    g.xp += amount; let gained = 0;
    while (g.level < G().XP.maxLevel && g.xp >= xpNeed(g.level)) { g.xp -= xpNeed(g.level); g.level++; gained++; }
    g.pendingLevelUps += gained;
    return gained;
  }
  function xpValue(e, regionId) { const v = G().XP_VALUE, mult = (regionId && G().REGION_XP_MULT && G().REGION_XP_MULT[regionId]) || 1; const base = e.summoned ? v.summoned : (v[e.type] != null ? v[e.type] : 5); return Math.round(base * mult); }

  // ---------- 조회 ----------
  const weaponOf = (g, id) => g.weapons.find(w => w.id === id);
  const hasCommon = (g, id) => (g.commons[id] || 0) > 0;
  const commonCount = (g) => Object.keys(g.commons).filter(k => g.commons[k] > 0).length;
  const passiveCount = (g) => Object.keys(g.passives).filter(k => g.passives[k] > 0).length;
  function hasProjectileWeapon(g) { return g.weapons.some(w => ['homing', 'bolt', 'beam'].includes(W()[w.id].kind) || w.mods.includes('crescent') || w.mods.includes('launch')); }
  function hasFireSource(g) { return hasCommon(g, 'ember') || !!weaponOf(g, 'ember'); }

  // ---------- 후보 생성 ----------
  // ctx: { regionId, pool: 'level' | 'deep' | 'boss' }
  function candidates(run, ctx) {
    const g = ensure(run), S = G().SLOTS, out = [];
    const region = (ctx && ctx.regionId) || null, tags = PA.REGION_TAGS[region] || [];
    const push = (c) => { c.tags = c.tags || []; c.regionMatch = c.tags.some(t => tags.includes(t)); out.push(c); };
    if (ctx && ctx.pool === 'boss') {
      for (const id in PA.BOSS_REWARDS) { const d = PA.BOSS_REWARDS[id]; if (!d.impl || g.bossRewards.includes(id)) continue; if (id === 'clone' && !hasProjectileWeapon(g)) continue; push({ kind: 'boss_reward', id, tags: d.tags }); }
      return out;
    }
    // 새 무기
    if (g.weapons.length < S.weapons) for (const id in W()) { const d = W()[id]; if (!d.impl || weaponOf(g, id)) continue; push({ kind: 'weapon_new', id, tags: d.tags }); }
    // 무기 레벨업·전용 증강 (장착 무기만)
    for (const w of g.weapons) {
      const d = W()[w.id];
      if (w.level < S.weaponMax) push({ kind: 'weapon_level', id: w.id, tags: d.tags });
      if (w.mods.length < S.weaponMods) for (const mid in d.mods) { const md = d.mods[mid]; if (!md.impl || w.mods.includes(mid)) continue; push({ kind: 'weapon_mod', id: w.id, mod: mid, tags: md.tags }); }
    }
    // 공통 증강
    for (const id in PA.COMMONS) {
      const d = PA.COMMONS[id]; if (!d.impl) continue;
      const lv = g.commons[id] || 0;
      if (lv >= d.max) continue;
      if (lv === 0 && commonCount(g) >= S.commons) continue;               // 슬롯 초과
      if (d.applies && !g.weapons.some(w => d.applies(W()[w.id]))) continue; // 적용 대상 없음
      if (d.requiresAny && !d.requiresAny.some(r => r === 'common:ember' ? hasCommon(g, 'ember') : r === 'weapon:ember' ? !!weaponOf(g, 'ember') : false)) continue;
      push({ kind: 'common', id, tags: d.tags });
    }
    // 수동 기술
    if (!g.skills.e) { for (const id of PA.E_SKILLS) if (PA.SKILLS[id].impl) push({ kind: 'skill_new', id, tags: [] }); }
    for (const slot of ['q', 'e']) {
      const sk = g.skills[slot]; if (!sk) continue; const d = PA.SKILLS[sk.id];
      if (sk.level < S.skillMax) push({ kind: 'skill_level', id: sk.id, slot, tags: [] });
      if (!sk.variant) for (const vid in d.variants) if (d.variants[vid].impl) push({ kind: 'skill_variant', id: sk.id, slot, variant: vid, tags: [] });
    }
    // 패시브
    for (const id in PA.PASSIVES) {
      const d = PA.PASSIVES[id]; if (!d.impl) continue; const lv = g.passives[id] || 0;
      if (lv >= d.max) continue; if (lv === 0 && passiveCount(g) >= S.passives) continue;
      push({ kind: 'passive', id, tags: [] });
    }
    if (ctx && ctx.pool === 'deep') return out.filter(c => c.regionMatch); // 지역 보상: 지역 태그 후보만
    if (ctx && ctx.pool === 'mission') { // 임무 보상: 종류 제한. 서비스 종류는 거점 서비스 목록
      if (ctx.kinds.includes('service')) { for (const id in PA.SERVICES) push({ kind: 'service', id, tags: [] }); return out.filter(c => c.kind === 'service'); }
      return out.filter(c => ctx.kinds.includes(c.kind));
    }
    return out;
  }
  function weightOf(g, c) {
    const Wt = G().WEIGHTS; let w = Wt.base[c.kind] || 1;
    if (g.level <= Wt.early.untilLevel && Wt.early[c.kind]) w *= Wt.early[c.kind];
    if (c.regionMatch) w *= Wt.regionTag;
    if (g.lastKind && g.lastKind === c.kind && (c.kind === 'weapon_level' || c.kind === 'passive')) w *= Wt.repeatPenalty;
    return w;
  }
  const keyOf = (c) => c.kind + ':' + c.id + (c.mod ? ':' + c.mod : '') + (c.variant ? ':' + c.variant : '');
  // 시드 결정적 3택. 같은 seq는 항상 같은 결과(새로고침 재굴림 방지: pendingOffer에 저장)
  function generateOffer(run, ctx) {
    const g = ensure(run);
    if (g.pendingOffer && g.pendingOffer.pool === ((ctx && ctx.pool) || 'level')) return g.pendingOffer;
    const pool = candidates(run, ctx), rng = PA.rng.create((run.seed * 7919 + g.choiceSeq * 104729 + g.level * 31) >>> 0);
    const picked = [];
    const remaining = pool.slice();
    while (picked.length < 3 && remaining.length) {
      let sum = 0; const ws = remaining.map(c => { const w = weightOf(g, c); sum += w; return w; });
      let r = rng.next() * sum, idx = remaining.length - 1;
      for (let i = 0; i < remaining.length; i++) { r -= ws[i]; if (r <= 0) { idx = i; break; } }
      const c = remaining.splice(idx, 1)[0];
      // 같은 무기의 레벨업과 전용 증강이 한 화면에 둘 이상 나오지 않게(다양성)
      if (picked.some(p => p.kind === c.kind && p.id === c.id)) continue;
      picked.push(c);
    }
    g.pendingOffer = { seq: g.choiceSeq, pool: (ctx && ctx.pool) || 'level', regionId: ctx && ctx.regionId || null, choices: picked.map(c => Object.assign({ key: keyOf(c) }, c)) };
    g.choiceSeq++;
    return g.pendingOffer;
  }
  function applyChoice(run, choice) {
    const g = ensure(run), S = G().SLOTS;
    switch (choice.kind) {
      case 'weapon_new': if (g.weapons.length >= S.weapons || weaponOf(g, choice.id)) throw new Error('무기 슬롯'); g.weapons.push({ id: choice.id, level: 1, mods: [] }); break;
      case 'weapon_level': { const w = weaponOf(g, choice.id); if (!w || w.level >= S.weaponMax) throw new Error('무기 레벨'); w.level++; break; }
      case 'weapon_mod': { const w = weaponOf(g, choice.id); if (!w || w.mods.length >= S.weaponMods || w.mods.includes(choice.mod)) throw new Error('전용 증강'); w.mods.push(choice.mod); break; }
      case 'common': { const d = PA.COMMONS[choice.id], lv = g.commons[choice.id] || 0; if (lv >= d.max || (lv === 0 && commonCount(g) >= S.commons)) throw new Error('공통 증강'); if (d.requiresAny && !d.requiresAny.some(r => r === 'common:ember' ? hasCommon(g, 'ember') : r === 'weapon:ember' ? !!weaponOf(g, 'ember') : false)) throw new Error('전제 미충족'); if (d.applies && !g.weapons.some(w => d.applies(W()[w.id]))) throw new Error('적용 대상 없음'); g.commons[choice.id] = lv + 1; break; }
      case 'skill_new': if (g.skills.e) throw new Error('E 슬롯'); g.skills.e = { id: choice.id, level: 1, variant: null }; break;
      case 'skill_level': { const sk = g.skills[choice.slot]; if (!sk || sk.id !== choice.id || sk.level >= S.skillMax) throw new Error('기술 레벨'); sk.level++; break; }
      case 'skill_variant': { const sk = g.skills[choice.slot]; if (!sk || sk.id !== choice.id || sk.variant) throw new Error('기술 변형'); sk.variant = choice.variant; break; }
      case 'passive': { const d = PA.PASSIVES[choice.id], lv = g.passives[choice.id] || 0; if (lv >= d.max || (lv === 0 && passiveCount(g) >= S.passives)) throw new Error('패시브'); g.passives[choice.id] = lv + 1; if (choice.id === 'vitality') run.hp = (run.hp || 0) + G().PASSIVE_VALUES.vitality; break; }
      case 'boss_reward': if (g.bossRewards.includes(choice.id)) throw new Error('중복'); g.bossRewards.push(choice.id); break;
      case 'service': if (!PA.SERVICES[choice.id]) throw new Error('알 수 없는 서비스'); run.services = run.services || {}; run.services[choice.id] = (run.services[choice.id] || 0) + 1; break;
      default: throw new Error('알 수 없는 선택');
    }
    g.picks[choice.kind] = (g.picks[choice.kind] || 0) + 1;
    g.lastKind = choice.kind;
    g.log.push(keyOf(choice));
    if (g.pendingOffer && g.pendingOffer.pool === 'level') g.pendingLevelUps = Math.max(0, g.pendingLevelUps - 1);
    g.pendingOffer = null;
  }
  function skipChoice(run) { const g = ensure(run); g.picks.skip++; if (g.pendingOffer && g.pendingOffer.pool === 'level') g.pendingLevelUps = Math.max(0, g.pendingLevelUps - 1); g.pendingOffer = null; run.gold = (run.gold || 0) + PA.CONFIG.SKIP_AUGMENT_GOLD; }

  // ---------- 파생 수치 ----------
  function weaponStats(b, w) {
    const d = W()[w.id], base = d.base, lvMult = G().LEVEL_MULT[Math.min(w.level, G().SLOTS.weaponMax) - 1];
    const s = Object.assign({}, base);
    s.id = w.id; s.level = w.level; s.mods = w.mods.slice(); s.def = d; s.kind = d.kind; s.name = d.name;
    s.damage = base.damage * lvMult * b.damageMult;      // 기본 × 레벨 배율 × (대장간 강화 × 무기 숙련) — 각각 한 번씩
    s.interval = base.interval * b.intervalMult;
    if (d.reach && base.range != null) s.range = base.range * b.rangeMult;
    if (d.width) { if (base.arcDeg) s.arcDeg = Math.min(360, base.arcDeg * b.widthMult); if (base.width) s.width = base.width * b.widthMult; if (base.radius) s.radius = base.radius * b.widthMult; if (base.trigger) s.trigger = base.trigger * b.widthMult; }
    if (d.kind === 'arc' && d.width) s.range = (s.range || base.range) * (1 + (b.widthMult - 1) * 0.5); // 검격은 반지름도 조금 커진다
    return s;
  }
  function derive(run, b) {
    const g = ensure(run), PV = G().PASSIVE_VALUES, CV = G().COMMON_VALUES, p = g.passives;
    b.growth = g; b.level = g.level;
    b.masteryMult = 1 + PV.mastery * (p.mastery || 0);
    b.damageMult = (1 + 0.15 * (run.gear.upgrade || 0)) * b.masteryMult;   // 대장간 강화(세 무기 공통) × 무기 숙련
    b.intervalMult = 1 - PV.haste * (p.haste || 0);
    b.rangeMult = CV.reach[(g.commons.reach || 0) - 1] || 1;
    b.widthMult = CV.wide[(g.commons.wide || 0) - 1] || 1;
    b.hpMax += PV.vitality * (p.vitality || 0);
    b.speedMult = 1 + PV.mobility * (p.mobility || 0);
    b.toughness = PV.toughness * (p.toughness || 0);
    b.exposedMult = b.exposedMult + PV.exploit * (p.exploit || 0);       // 기본/목걸이 → 빈틈 포착 가산
    b.durationMult = 1 + PV.persistence * (p.persistence || 0);
    b.skillCdMult = (1 - PV.focus * (p.focus || 0)) * b.skillCdMult;
    b.weapons = g.weapons.map(w => weaponStats(b, w));
    b.commons = Object.assign({}, g.commons);
    b.passives = Object.assign({}, p);
    b.skills = { q: g.skills.q ? Object.assign({}, g.skills.q) : null, e: g.skills.e ? Object.assign({}, g.skills.e) : null };
    b.bossRewards = g.bossRewards.slice();
    b.legacy = Object.assign({}, g.legacy);
    b.has = (id) => (g.commons[id] || 0) > 0 || !!g.legacy[id];
    b.level_ = (id) => g.commons[id] || 0;
    // 감속장 재사용: 레벨 → 부적 -3 → 집중
    const q = g.skills.q; const qcd = PA.SKILLS.slowfield.cooldown[Math.min(3, q ? q.level : 1) - 1];
    b.specialCd = Math.max(1, (qcd - (b.accSpecialBonus || 0)) * b.skillCdMult);
    b.shield = g.skills.e && g.skills.e.id === 'ward' ? 0 : b.shield; // 방벽은 결계로 이행됨(레거시 barrier는 legacy.barrier)
    if (g.legacy.barrier) b.shield = PA.CONFIG.BARRIER.shield;
    return b;
  }

  // ---------- 레거시(v0.4 이하) 매핑 ----------
  // gear.weapon 'pierce' → 관통창 보유, augments: sharp→무기 숙련, wide→넓어진 공격, quick→가속, spin→회전 칼날 추가 무기,
  // ember/frost/flare/echo/saving/stasis→공통, barrier→수호 결계(E, 레벨1) 또는 레거시 방벽, mark→레거시 표식 유지(신규 제시 없음)
  function migrateFromLegacy(run) {
    const a = run.augments || {}, S = G().SLOTS;
    const start = (run.gear && run.gear.weapon === 'pierce') ? 'spear' : 'sword';
    const g = newGrowth(start);
    if (run.gear && run.gear.weapon === 'pierce') { g.weapons.push({ id: 'sword', level: 1, mods: [] }); }
    else if (run.owned && run.owned.includes('pierce_sword')) g.weapons.push({ id: 'spear', level: 1, mods: [] });
    if (a.spin && g.weapons.length < S.weapons) g.weapons.push({ id: 'blades', level: 1, mods: [] });
    const commons = {};
    for (const id of ['wide', 'ember', 'frost', 'flare', 'echo', 'saving', 'stasis']) if (a[id]) commons[id] = Math.min(PA.COMMONS[id].max, a[id]);
    if (a.sharp) g.passives.mastery = Math.min(3, a.sharp);
    if (a.quick) g.passives.haste = Math.min(3, a.quick);
    if (a.barrier) { g.skills.e = { id: 'ward', level: 1, variant: null }; g.legacy.barrier = 1; }
    if (a.mark) g.legacy.mark = 1;
    const ids = Object.keys(commons);
    if (ids.length > S.commons) { g.migrationPending = { commons: ids.map(id => ({ id, level: commons[id] })) }; } // 거점에서 명시적으로 3개 선택
    else g.commons = commons;
    // 레벨: 과거 증강 수만큼 대략 성장한 것으로 간주(경험치 0, 미처리 선택 없음)
    const count = Object.values(a).reduce((s, v) => s + (v || 0), 0);
    g.level = 1 + count; g.xp = 0;
    return g;
  }
  function resolveMigration(run, keepIds) {
    const g = ensure(run); if (!g.migrationPending) return;
    const keep = keepIds.slice(0, G().SLOTS.commons);
    for (const c of g.migrationPending.commons) if (keep.includes(c.id)) g.commons[c.id] = c.level;
    g.migrationPending = null;
  }

  // ---------- 카드 설명(실제 파생 계산 재사용) ----------
  function cloneRun(run) { return JSON.parse(JSON.stringify(run)); }
  function describe(run, c) {
    const S = G().SLOTS, g = ensure(run), before = PA.Build.derive(run);
    const after = cloneRun(run); try { applyChoice(after, c); } catch (e) {}
    const b2 = PA.Build.derive(after);
    const fmt = PA.fmt.num, out = { kind: c.kind, key: keyOf(c), tags: c.tags || [], regionMatch: !!c.regionMatch };
    const wname = (id) => W()[id].name;
    switch (c.kind) {
      case 'weapon_new': { const d = W()[c.id], s = b2.weapons.find(w => w.id === c.id); out.title = `새 무기: ${d.name}`; out.type = '무기 획득'; out.stage = `무기 ${g.weapons.length}/${S.weapons} → ${g.weapons.length + 1}/${S.weapons}`; out.change = d.desc; out.scope = `기본 피해 ${fmt(s.damage)} · 주기 ${fmt(s.interval)}초 · 1레벨부터 ${d.kind === 'beam' ? '관통' : d.kind === 'orbit' ? '공전' : d.kind === 'chain' ? '연쇄' : '고유 방식'}`; out.slot = `무기 슬롯 ${g.weapons.length + 1}/${S.weapons}`; break; }
      case 'weapon_level': { const w = weaponOf(g, c.id), s1 = before.weapons.find(x => x.id === c.id), s2 = b2.weapons.find(x => x.id === c.id); out.title = `${wname(c.id)} ${w.level}→${w.level + 1}`; out.type = '무기 레벨'; out.stage = `${w.level} → ${w.level + 1} / ${S.weaponMax}`; out.change = `기본 피해 ${fmt(s1.damage)} → ${fmt(s2.damage)}`; out.scope = '이 무기만'; out.slot = '슬롯 소비 없음'; break; }
      case 'weapon_mod': { const w = weaponOf(g, c.id), md = W()[c.id].mods[c.mod]; out.title = `${wname(c.id)} 전용: ${md.name}`; out.type = '방식 증강'; out.stage = `방식 슬롯 ${w.mods.length}/${S.weaponMods} → ${w.mods.length + 1}/${S.weaponMods}`; out.change = md.desc; out.scope = `${wname(c.id)}만`; out.slot = `${wname(c.id)} 방식 슬롯 ${w.mods.length + 1}/${S.weaponMods}`; break; }
      case 'common': { const d = PA.COMMONS[c.id], lv = g.commons[c.id] || 0; out.title = `공통: ${d.name}${d.max > 1 ? ` ${lv}→${lv + 1}` : ''}`; out.type = '공통 증강'; out.stage = d.max > 1 ? `${lv} → ${lv + 1} / ${d.max}` : (lv ? '보유' : '획득'); out.change = d.desc; const targets = d.applies ? g.weapons.filter(w => d.applies(W()[w.id])).map(w => wname(w.id)) : g.weapons.map(w => wname(w.id)); out.scope = `적용: ${targets.join(', ') || '없음'} (나중에 얻는 무기도 자동)`; if (c.id === 'wide' || c.id === 'reach') { const ex = before.weapons.find(w => d.applies(W()[w.id])); if (ex) { const ex2 = b2.weapons.find(w => w.id === ex.id); out.change += c.id === 'wide' ? ` · ${wname(ex.id)} ${ex.arcDeg ? '각도 ' + Math.round(ex.arcDeg) + '° → ' + Math.round(ex2.arcDeg) + '°' : ex.width ? '폭 ' + Math.round(ex.width) + ' → ' + Math.round(ex2.width) : ex.radius ? '반지름 ' + Math.round(ex.radius) + ' → ' + Math.round(ex2.radius) : ''}` : ` · ${wname(ex.id)} 사거리 ${Math.round(ex.range)} → ${Math.round(ex2.range)}`; } } out.slot = lv ? '슬롯 소비 없음(단계 상승)' : `공통 슬롯 ${commonCount(g) + 1}/${S.commons}`; break; }
      case 'skill_new': { const d = PA.SKILLS[c.id]; out.title = `E 기술 습득: ${d.name}`; out.type = '수동 기술'; out.stage = 'E 슬롯 비어 있음 → 장착'; out.change = d.desc; out.scope = `재사용 ${fmt(d.cooldown[0] * before.skillCdMult)}초`; out.slot = 'E 슬롯'; break; }
      case 'skill_level': { const sk = g.skills[c.slot], d = PA.SKILLS[c.id]; out.title = `${d.name} ${sk.level}→${sk.level + 1}`; out.type = '기술 레벨'; out.stage = `${sk.level} → ${sk.level + 1} / ${S.skillMax}`; const cd1 = d.cooldown[sk.level - 1] * before.skillCdMult, cd2 = d.cooldown[sk.level] * before.skillCdMult; out.change = `재사용 ${fmt(cd1)}초 → ${fmt(cd2)}초` + (d.damage ? ` · 피해 ${d.damage[sk.level - 1]} → ${d.damage[sk.level]}` : d.shield ? ` · 흡수 ${d.shield[sk.level - 1]} → ${d.shield[sk.level]}` : ''); out.scope = `${d.key} 기술`; out.slot = '슬롯 소비 없음'; break; }
      case 'skill_variant': { const d = PA.SKILLS[c.id], v = d.variants[c.variant]; out.title = `${d.name} 변형: ${v.name}`; out.type = '기술 변형'; out.stage = '변형 없음 → 선택(기술당 1개)'; out.change = v.desc; out.scope = `${d.key} 기술`; out.slot = '변형 슬롯 1/1'; break; }
      case 'passive': { const d = PA.PASSIVES[c.id], lv = g.passives[c.id] || 0; out.title = `${d.name} ${lv}→${lv + 1}`; out.type = '패시브'; out.stage = `${lv} → ${lv + 1} / ${d.max}`; let ch = d.desc; if (c.id === 'vitality') ch += ` · 최대 체력 ${before.hpMax} → ${b2.hpMax}`; if (c.id === 'mastery') ch += ` · ${wname(g.weapons[0].id)} 피해 ${fmt(before.weapons[0].damage)} → ${fmt(b2.weapons[0].damage)}`; if (c.id === 'haste') ch += ` · ${wname(g.weapons[0].id)} 주기 ${fmt(before.weapons[0].interval)} → ${fmt(b2.weapons[0].interval)}초`; if (c.id === 'focus') ch += ` · 감속장 ${fmt(before.specialCd)} → ${fmt(b2.specialCd)}초`; if (c.id === 'exploit') ch += ` · 빈틈 ×${before.exposedMult} → ×${b2.exposedMult}`; out.change = ch; out.scope = '캐릭터 전체'; out.slot = lv ? '슬롯 소비 없음' : `패시브 슬롯 ${passiveCount(g) + 1}/${S.passives}`; break; }
      case 'service': { const d = PA.SERVICES[c.id], n = (run.services || {})[c.id] || 0; out.title = `거점 서비스: ${d.name}`; out.type = '거점 서비스'; out.stage = n ? `보유 ${n} → ${n + 1}회` : '획득(1회)'; out.change = d.desc; out.scope = '이번 회차 거점에서 사용'; out.slot = '슬롯 소비 없음'; break; }
      case 'boss_reward': { const d = PA.BOSS_REWARDS[c.id]; out.title = `보스 보상: ${d.name}`; out.type = '희귀 보상'; out.stage = '획득'; out.change = d.desc; out.scope = '모든 무기·기술'; out.slot = '별도 보관'; break; }
    }
    return out;
  }

  return { newGrowth, ensure, xpNeed, addXp, xpValue, candidates, weightOf, generateOffer, applyChoice, skipChoice, weaponStats, derive, migrateFromLegacy, resolveMigration, describe, keyOf, weaponOf, hasCommon, commonCount, passiveCount, hasProjectileWeapon, hasFireSource };
})();
