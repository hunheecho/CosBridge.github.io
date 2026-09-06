// 실시간 전투 시뮬레이션. 렌더링·입력 장치와 무관하게 dt만 받아 진행한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Combat = (function () {
  const C = () => PA.CONFIG;
  const m = () => PA.m;
  let nextId = 1;

  function create(opts) {
    const cfg = C();
    const build = opts.build;
    const rng = PA.rng.create(opts.seed || 1);
    const arenaDef = PA.ARENAS[opts.arena || 'forest'] || PA.ARENAS.forest;
    const st = {
      t: 0, seed: opts.seed || 1, rng, arena: Object.assign({}, cfg.ARENA), arenaId: opts.arena || 'forest',
      obstacles: (opts.obstacles || arenaDef.obstacles || []).map(o => Object.assign({}, o)),
      build,
      objective: opts.objective || 'clear',
      waves: opts.waves || [[{ type: 'wolf', n: 2 }]],
      waveIndex: -1, waveTimer: 0.4, pending: [], // pending spawns {type,x,y,t}
      player: {
        x: (arenaDef.playerStart || { x: cfg.ARENA.w / 2 }).x, y: (arenaDef.playerStart || { y: cfg.ARENA.h / 2 }).y, r: cfg.PLAYER.r,
        hp: opts.hp != null ? Math.min(opts.hp, build.hpMax) : build.hpMax, hpMax: build.hpMax,
        shield: build.shield, shieldMax: build.shield,
        face: 0, moving: false, animT: 0,
        dodge: { active: false, t: 0, dx: 0, dy: 0, cd: 0 },
        hitProt: 0, zoneTick: 0,
        attackTimer: 0.2, attackCount: 0, echo: null,
        swingT: 9, swingForm: 'arc', swingAngle: 0, walkT: 0, hurtT: 9,
        special: { cd: 0 },
        dead: false, flash: 0,
      },
      field: null,          // 감속장 {x,y,r,ttl}
      enemies: [], projectiles: [], zones: [], effects: [], events: [],
      chest: null, chestSpawned: false,
      markTarget: null,
      status: 'running',    // running | won | lost
      stats: { kills: 0, damageTaken: 0, perfectDodges: 0, chestGold: 0, elapsed: 0, attacks: 0, bossDamage: 0, specialUses: 0 },
      spawnedAll: false,
      mode: opts.boss ? 'boss' : 'normal', intro: 0, boss: null, pickups: [], orbsSpawned: {}, phaseEvents: [], pendingLoss: false, bossDownT: 0,
      weapons: [], mines: [], delayed: [], levelUps: 0, xpGained: 0,
      // 시험실·측정(v0.6): 체력 배율은 체력에만 적용, 시간 제한, 빌드 고정, 동시 공격 제한, 지역
      hpMult: Object.assign({ normal: 1, elite: 1, boss: 1 }, opts.hpMult || {}), timeLimit: opts.timeLimit || 0, fixedBuild: !!opts.fixedBuild, overlapLimit: opts.overlapLimit || 0, regionId: opts.regionId || null,
      metrics: newMetrics(), labText: opts.labText || null,
      objects: [], obj: null, mission: opts.mission || null, // v0.7 목표 구조물 외 객체(우리·봉인·출구·포로)와 목표 진행 상태
    };
    st.stats.xp = 0; st.stats.levelUps = 0; st.stats.eUses = 0; st.stats.absorbed = 0;
    st.weapons = PA.Weapons.init(st);
    PA.Skills.init(st);
    if (!opts.boss && PA.Objectives && PA.Objectives.is(st.objective)) PA.Objectives.setup(st, { risk: opts.risk || null, regionId: opts.regionId, run: opts.run || null });
    if (opts.boss) {
      st.objective = 'boss'; st.waveIndex = 99; st.spawnedAll = true;
      const bs = arenaDef.bossStart || { x: cfg.ARENA.w / 2, y: 120 };
      const bz = PA.Boss.spawn(st, bs.x, bs.y, opts.bossId || 'boss');
      if (opts.bossHp) { bz.hp = opts.bossHp; bz.hpMax = opts.bossHp; } // 단계별 체력 후보(회차 구조). 배율은 체력에만
      st.bossId = bz.bossId; st.intro = PA.Boss.cfgOf(bz).intro; // 입장 연출: 아무도 행동하지 않고 피해도 없다
    }
    return st;
  }

  // ---------- 이벤트/이펙트 ----------
  function ev(st, name, data) { st.events.push(Object.assign({ name }, data || {})); }
  function fx(st, e) { st.effects.push(e); }
  function text(st, x, y, txt, color) { fx(st, { kind: 'text', x, y, text: txt, color: color || '#fff', ttl: 0.8, t: 0 }); }

  // ---------- 측정(시험실·시뮬레이션 공용) ----------
  // 적 종류별 등장·처치·공격 준비·실행·공격 전 사망·처치 소요, 피해 출처별 실제 체력 감소(과잉 피해 제외), 받은 피해 원인별
  function newMetrics() { return { enemies: {}, dmg: {}, taken: {}, takenHits: {}, absorbed: 0, deathEffects: {}, interrupts: 0, webs: 0, heals: 0, healAmount: 0 }; }
  function enemyKey(e) { return e.type + (e.summoned ? ':summoned' : ''); }
  function metricsFor(st, e) { const k = enemyKey(e); return st.metrics.enemies[k] || (st.metrics.enemies[k] = { spawned: 0, killed: 0, prepared: 0, executed: 0, diedBeforeAttack: 0, ttk: [], ttkFromHit: [], deathEffects: 0 }); }
  // 공격 준비(예고 시작)·실행(피해 판정 발생 시점)을 구분해 센다. 죽으면서 생기는 효과(포자 사망 구름)는 deathEffect로 따로.
  function noteAttack(st, e, phase) { const m = metricsFor(st, e); if (phase === 'prepare') { m.prepared++; e.prepared = true; } else if (phase === 'execute') { m.executed++; e.acted = true; } else if (phase === 'death') m.deathEffects++; }
  function srcKey(st, opt) {
    const sr = opt.src || {};
    if (opt.tag) return opt.tag; if (sr.tag) return sr.tag;
    if (opt.dot) return 'dot:' + opt.dot;
    if (sr.skill) return 'skill:' + (sr.skillId || 'e');
    if (sr.weaponId) return 'weapon:' + sr.weaponId;
    return 'other';
  }
  function summary(st) {
    const M = st.metrics, en = {};
    const avg = (a) => a.length ? Math.round(a.reduce((x, y) => x + y, 0) / a.length * 100) / 100 : null;
    for (const k in M.enemies) { const m = M.enemies[k], ended = m.killed + (m.exploded || 0); en[k] = { spawned: m.spawned, killed: m.killed, exploded: m.exploded || 0, prepared: m.prepared, executed: m.executed, diedBeforeAttack: m.diedBeforeAttack, diedBeforeAttackRate: ended ? Math.round(m.diedBeforeAttack / ended * 1000) / 1000 : null, ttkAvg: avg(m.ttk), ttkFromHitAvg: avg(m.ttkFromHit), deathEffects: m.deathEffects }; } // 공격 전 사망률 분모 = 처치 + 자폭(폭탄 운반체)
    const dmgTotal = Object.values(M.dmg).reduce((a, b) => a + b, 0);
    const dmg = {}; for (const k in M.dmg) dmg[k] = { amount: Math.round(M.dmg[k] * 10) / 10, share: dmgTotal ? Math.round(M.dmg[k] / dmgTotal * 1000) / 1000 : 0 };
    return {
      version: PA.VERSION, seed: st.seed, arena: st.arenaId, regionId: st.regionId, hpMult: st.hpMult, timeLimit: st.timeLimit, fixedBuild: st.fixedBuild,
      status: st.status, elapsed: Math.round(st.t * 100) / 100, hp: Math.round(st.player.hp), hpMax: st.player.hpMax,
      damageTaken: Math.round(st.stats.damageTaken), absorbed: Math.round(M.absorbed), kills: st.stats.kills, specialUses: st.stats.specialUses, eUses: st.stats.eUses || 0, dodges: st.stats.dodges || 0,
      taken: M.taken, takenHits: M.takenHits, enemies: en, dmg, dmgTotal: Math.round(dmgTotal), interrupts: M.interrupts, heals: M.heals, healAmount: Math.round(M.healAmount), webs: M.webs,
      farFrac: M.farFrac != null ? M.farFrac : null, patterns: M.patterns || {}, xp: st.stats.xp, levelUps: st.stats.levelUps, build: st.build.growth ? { level: st.build.growth.level, weapons: st.build.growth.weapons.map(w => w.id + ':' + w.level + (w.mods.length ? ':' + w.mods.join('+') : '')), commons: st.build.growth.commons, passives: st.build.growth.passives, e: st.build.growth.skills.e, q: st.build.growth.skills.q } : null,
    };
  }

  // ---------- 지형 ----------
  // 원형 개체를 장애물·벽 밖으로 밀어낸다(표면을 따라 미끄러짐). 반환: 밀려났는지
  function pushOut(st, o) {
    let moved = false;
    for (const ob of st.obstacles) {
      const dx = o.x - ob.x, dy = o.y - ob.y, d = Math.hypot(dx, dy), min = ob.r + o.r;
      if (d < min) { const n = d > 1e-6 ? { x: dx / d, y: dy / d } : { x: 1, y: 0 }; o.x = ob.x + n.x * min; o.y = ob.y + n.y * min; moved = true; }
    }
    const a = st.arena;
    const cx = m().clamp(o.x, o.r, a.w - o.r), cy = m().clamp(o.y, o.r, a.h - o.r);
    if (cx !== o.x || cy !== o.y) { o.x = cx; o.y = cy; moved = true; }
    return moved;
  }
  // 스윕 이동: 이동 구간 전체에서 장애물·벽 충돌을 검사해 처음 닿는 지점에서 멈춘다. 반환 {hit: 장애물|'wall'|null, t}
  function moveSwept(st, o, dx, dy, slide) {
    const a = st.arena, x0 = o.x, y0 = o.y;
    let x1 = x0 + dx, y1 = y0 + dy, t = 1, hit = null;
    // 벽
    const wx = m().clamp(x1, o.r, a.w - o.r), wy = m().clamp(y1, o.r, a.h - o.r);
    if (wx !== x1 || wy !== y1) { const tx = wx !== x1 ? (wx - x0) / dx : 1, ty = wy !== y1 ? (wy - y0) / dy : 1; t = Math.max(0, Math.min(t, tx, ty)); hit = 'wall'; } // 바뀐 축만 계산(미세 dx로 t=0이 되는 오류 방지)
    const sw = m().sweepCircle(x0, y0, x0 + dx, y0 + dy, o.r, st.obstacles);
    if (sw && sw.t < t) { t = sw.t; hit = sw.ob; }
    if (hit) { const tt = Math.max(0, t - 1e-3); o.x = x0 + dx * tt; o.y = y0 + dy * tt; } else { o.x = x1; o.y = y1; }
    pushOut(st, o);
    if (hit && slide) {
      // 남은 이동량을 접촉면의 접선 방향으로(미끄러짐). 한 번만 다시 스윕한다
      let rx = dx * (1 - t), ry = dy * (1 - t);
      if (hit === 'wall') { if (wx !== x1) rx = 0; if (wy !== y1) ry = 0; }
      else { const nx = o.x - hit.x, ny = o.y - hit.y, nl = Math.hypot(nx, ny) || 1; const n = { x: nx / nl, y: ny / nl }; const dot = rx * n.x + ry * n.y; rx -= dot * n.x; ry -= dot * n.y; }
      if (Math.abs(rx) + Math.abs(ry) > 1e-6) {
        const sw2 = m().sweepCircle(o.x, o.y, o.x + rx, o.y + ry, o.r, st.obstacles);
        const t2 = sw2 ? Math.max(0, sw2.t - 1e-3) : 1;
        o.x += rx * t2; o.y += ry * t2; pushOut(st, o);
      }
    }
    return { hit, t };
  }
  // 두 점 사이에 장애물이 있는가(직접 공격의 가림 판정). 장애물 반지름 = 그림 크기
  function losBlocked(st, a, b) {
    for (const ob of st.obstacles) if (m().segCircle(a.x, a.y, b.x, b.y, ob, ob.r)) return true;
    return false;
  }
  // 반지름 r 개체가 놓일 수 있는 위치인가
  function validPos(st, x, y, r) {
    const a = st.arena;
    if (x < r || x > a.w - r || y < r || y > a.h - r) return false;
    for (const ob of st.obstacles) if (Math.hypot(x - ob.x, y - ob.y) < ob.r + r + 2) return false;
    return true;
  }
  // 가장 가까운 유효 위치(나선 탐색). 없으면 null
  function nearestValidPos(st, x, y, r, maxR) {
    if (validPos(st, x, y, r)) return { x, y };
    for (let rad = 12; rad <= (maxR || 260); rad += 12) for (let i = 0; i < 16; i++) { const a = i / 16 * Math.PI * 2; const px = x + Math.cos(a) * rad, py = y + Math.sin(a) * rad; if (validPos(st, px, py, r)) return { x: px, y: py }; }
    return null;
  }
  // 직선 빔이 장애물에 막히는 길이
  function beamLength(st, from, angle, L) {
    const ex = from.x + Math.cos(angle) * L, ey = from.y + Math.sin(angle) * L;
    let best = L;
    for (const ob of st.obstacles) { const t = m().segCircleT(from.x, from.y, ex, ey, ob, ob.r); if (t != null) best = Math.min(best, t * L); }
    return best;
  }
  // 장애물을 돌아가는 조향: 직진 경로가 막히면 접선 방향으로 이동. 반환 이동 방향(단위 벡터)
  function steerDir(st, e, tx, ty) {
    const dx = tx - e.x, dy = ty - e.y, dist = Math.hypot(dx, dy);
    if (dist < 1e-6) return { x: 0, y: 0 };
    const d = { x: dx / dist, y: dy / dist };
    let blocker = null, bestAlong = Infinity;
    for (const ob of st.obstacles) {
      const R = ob.r + e.r + 6;
      const ox = ob.x - e.x, oy = ob.y - e.y, along = ox * d.x + oy * d.y;
      if (along <= 0 || along > Math.min(dist, 200) + R) continue;
      const side = Math.abs(-ox * d.y + oy * d.x);
      if (side < R && along < bestAlong) { bestAlong = along; blocker = ob; }
    }
    if (!blocker) { e.steerSide = 0; return d; }
    const ox = blocker.x - e.x, oy = blocker.y - e.y, od = Math.hypot(ox, oy), R = blocker.r + e.r + 6;
    const cross = d.x * oy - d.y * ox; // >0: 장애물이 진행 방향 왼쪽
    if (!e.steerSide || e.steerT <= 0) { e.steerSide = cross > 0 ? -1 : 1; e.steerT = 0.8; }
    const sideSign = e.steerSide;
    if (od <= R + 0.5) { // 이미 접해 있음: 접선 방향(둘레를 따라)
      const nx = ox / od, ny = oy / od; return { x: -ny * sideSign, y: nx * sideSign };
    }
    const base = Math.atan2(oy, ox), off = Math.asin(Math.min(1, R / od));
    const ang = base + off * sideSign;
    return { x: Math.cos(ang), y: Math.sin(ang) };
  }

  // ---------- 스폰 ----------
  function edgePos(st) {
    const a = st.arena, rng = st.rng, side = rng.int(0, 3), pad = 30;
    if (side === 0) return { x: rng.range(pad, a.w - pad), y: pad };
    if (side === 1) return { x: a.w - pad, y: rng.range(pad, a.h - pad) };
    if (side === 2) return { x: rng.range(pad, a.w - pad), y: a.h - pad };
    return { x: pad, y: rng.range(pad, a.h - pad) };
  }
  function queueWave(st, wave) {
    for (const g of wave) for (let i = 0; i < g.n; i++) {
      let p = edgePos(st);
      // 플레이어 바로 옆에 등장하지 않게
      let tries = 0;
      while ((m().dist(p, st.player) < 160 || !validPos(st, p.x, p.y, PA.ENEMIES[g.type].r)) && tries++ < 12) p = edgePos(st);
      const vp = nearestValidPos(st, p.x, p.y, PA.ENEMIES[g.type].r) || p; p = vp;
      st.pending.push({ type: g.type, x: p.x, y: p.y, t: C().SPAWN_WARN });
      fx(st, { kind: 'spawnwarn', x: p.x, y: p.y, ttl: C().SPAWN_WARN, t: 0, type: g.type });
    }
    ev(st, 'wave', { index: st.waveIndex });
  }
  function spawnEnemy(st, type, x, y) {
    const d = PA.ENEMIES[type];
    const e = {
      id: nextId++, type, def: d, name: d.name, x, y, r: d.r, hp: d.hp, hpMax: d.hpMax || d.hp,
      spawnT: st.t, firstHitT: null, acted: false, prepared: false,
      state: 'approach', stateT: 0, dir: 0, aimAngle: 0, chill: 0, stasis: 0, flash: 0, dead: false, deathT: 0,
      dashLeft: d.dashes || 1, vx: 0, vy: 0, animT: 0, elite: !!d.elite, hitBy: null, biteT: 9, moveT: 0, lastX: x, lastY: y, faceX: 1,
    };
    const cls = d.boss ? 'boss' : d.elite ? 'elite' : 'normal', mult = st.hpMult ? (st.hpMult[cls] || 1) : 1; // 체력 배율: 체력만(피해·속도·예고·경험치 불변)
    e.hp = e.hp * mult; e.hpMax = e.hpMax * mult; e.hpClass = cls; if (d.structure) e.structure = true;
    st.enemies.push(e);
    if (st.metrics) metricsFor(st, e).spawned++;
    if (st.build.has('mark')) assignMark(st);
    return e;
  }
  // 표식: 우선순위(정예>궁수>포자>늑대)가 가장 높은 적. 더 위험한 적이 나타나면 옮겨간다.
  function assignMark(st) {
    const alive = st.enemies.filter(e => !e.dead), prio = C().MARK.priority;
    let best = null;
    for (const t of prio) {
      const cands = alive.filter(e => e.type === t && !e.hidden);
      if (cands.length) { cands.sort((a, b) => m().dist(a, st.player) - m().dist(b, st.player)); best = cands[0]; break; }
    }
    if (st.markTarget && !st.markTarget.dead && best && prio.indexOf(st.markTarget.type) <= prio.indexOf(best.type)) return;
    st.markTarget = best;
  }

  // ---------- 감속 ----------
  function inField(st, o) { return (st.field && m().dist(st.field, o) <= st.field.r + (o.r || 0)) || PA.Skills.inField2(st, o) || false; }
  function inSlowEcho(st, o) { return st.zones.some(z => z.type === 'slowecho' && m().dist(z, o) <= z.r + (o.r || 0)); }
  function timeFactor(st, o) { return inField(st, o) ? C().PLAYER.special.slow : (inSlowEcho(st, o) ? 0.7 : 1); }

  // ---------- 플레이어 피해 ----------
  function damagePlayer(st, amount, src) {
    const p = st.player;
    if (p.dead || st.status !== 'running' || st.intro > 0) return false;
    if (st.boss && st.boss.dead) return false; // 보스가 쓰러진 뒤에는 추가 피해 없음
    if (p.dodge.active) { // 아슬아슬한 회피
      st.stats.perfectDodges++; // 내부 통계(성장 보상과 연결하지 않는다)
      text(st, p.x, p.y - 30, '회피!', '#7ef2ff');
      ev(st, 'perfect');
      return false;
    }
    if (p.hitProt > 0) return false;
    applyPlayerDamage(st, amount, src);
    p.hitProt = C().PLAYER.hitProtect;
    return true;
  }
  function applyPlayerDamage(st, amount, src) {
    if (st.obj && PA.Objectives) PA.Objectives.onPlayerHit(st);
    const p = st.player;
    if (src !== 'zone' && st.build.toughness) amount = Math.round(amount * (1 - st.build.toughness) * 10) / 10; // 강인함: 직접 공격만
    let rest = amount;
    if (p.shield > 0) {
      const used = Math.min(p.shield, rest);
      p.shield -= used; rest -= used;
      PA.Skills.onShieldDamaged(st, used);
      if (p.shield <= 0 && st.build.has('barrier')) barrierBurst(st);
    }
    if (rest > 0) { p.hp -= rest; st.stats.damageTaken += rest; }
    if (st.metrics) { const M = st.metrics, k = src || 'unknown'; M.taken[k] = (M.taken[k] || 0) + rest; M.takenHits[k] = (M.takenHits[k] || 0) + 1; M.absorbed += amount - rest; st.stats.absorbed += amount - rest; }
    p.flash = 0.2; p.hurtT = 0;
    fx(st, { kind: 'hitflash', x: p.x, y: p.y, ttl: 0.25, t: 0 });
    text(st, p.x, p.y - 28, '-' + Math.round(amount), '#ff6b6b');
    ev(st, 'hurt', { src });
    if (p.hp <= 0) { p.hp = 0; p.dead = true; st.pendingLoss = true; }
  }
  function zoneDamage(st, amount) {
    const p = st.player;
    if (p.dead || p.dodge.active || st.intro > 0 || (st.boss && st.boss.dead)) return;
    applyPlayerDamage(st, amount, 'zone');
  }
  function barrierBurst(st) {
    const p = st.player, cfg = C().BARRIER;
    for (const e of st.enemies) {
      if (e.dead) continue;
      const d = m().dist(e, p);
      if (d <= cfg.knockRadius) {
        if (e.boss) { PA.Boss.stagger(st, e); continue; }
        const n = m().norm(e.x - p.x, e.y - p.y); if (e.state === 'dash' || e.state === 'lock' || e.state === 'crouch') { e.state = 'recover'; e.stateT = 0; e.biteT = 0; } knockEnemy(e, n, cfg.knock);
      }
    }
    fx(st, { kind: 'burst', x: p.x, y: p.y, r: cfg.knockRadius, ttl: 0.35, t: 0, color: '#7ef2ff' });
    text(st, p.x, p.y - 44, '방벽 파열!', '#7ef2ff');
    ev(st, 'burst');
  }
  function knockEnemy(e, n, amount) {
    if (e.state === 'dash' || e.state === 'leap') return;
    if (e.boss) amount *= PA.Boss.cfgOf(e).knockMult; // 보스는 일반 넉백의 20%(신규 보스 15%)
    if (e.def && e.def.knockMult) amount *= e.def.knockMult; // 방패병 50%
    if (e.state === 'charge' || e.state === 'under' || e.state === 'warn') return; // 돌파·지하 이동 중 넉백 무시
    e.vx += n.x * amount * 4; e.vy += n.y * amount * 4;
  }

  // ---------- 적 피해 ----------
  function damageEnemy(st, e, amount, opt) {
    opt = opt || {};
    if (e.dead) return 0;
    const sr = opt.src || { direct: !!opt.sword };
    const direct = sr.direct !== false && !sr.extra && !sr.skill;
    let dmg = amount;
    if (e.state === 'recover' || e.state === 'stagger') dmg *= st.build.exposedMult;
    if (st.markTarget === e) dmg *= C().MARK.damageMult;
    if (PA.Enemies && PA.Enemies.shieldMult) { const sm = PA.Enemies.shieldMult(st, e, opt); if (sm !== 1) { dmg *= sm; e.blockedT = 0.2; } } // 방패병 정면 감소
    dmg = Math.round(dmg * 10) / 10;
    if (e.boss) st.stats.bossDamage += Math.min(dmg, Math.max(0, e.hp)); // 실제 체력 감소 기준(과잉 피해 제외)
    if (st.metrics) { const k = srcKey(st, opt); st.metrics.dmg[k] = (st.metrics.dmg[k] || 0) + Math.min(dmg, Math.max(0, e.hp)); if (e.firstHitT == null) e.firstHitT = st.t; }
    e.hp -= dmg; e.flash = 0.12;
    if (e.boss && e.hp > 0) PA.Boss.checkPhase(st, e);
    if (opt.knock && opt.dir) knockEnemy(e, opt.dir, opt.knock);
    if (PA.Enemies && PA.Enemies.onDamaged) PA.Enemies.onDamaged(st, e, dmg, opt);
    const b = st.build, dm = b.durationMult || 1;
    if (direct) { // 기본 공격 적중 효과(공통 규칙): 냉기·화상은 중첩 없이 유지 시간만 갱신, 흔적은 감속장 안에서만
      if (b.has('frost')) e.chill = Math.max(e.chill, C().FROST.chill * dm);
      if (b.has('burn')) { const BV = PA.GROWTH.COMMON_VALUES.burn; if (!e.burn || e.burn.dps <= BV.dps) e.burn = { t: Math.max(e.burn ? e.burn.t : 0, BV.dur * dm), dps: BV.dps }; }
      if (b.has('stasis') && inField(st, e)) e.stasis = Math.min(C().STASIS.maxStacks, e.stasis + 1);
    }
    if (opt.chill) e.chill = Math.max(e.chill, opt.chill * dm);                 // 무기 고유 냉기(서리 수정·서리 함정): 같은 규칙
    if (opt.bleed && sr.weapon) { const dps = sr.weapon.damage * 0.3; if (!e.bleed || e.bleed.dps <= dps) e.bleed = { t: Math.max(e.bleed ? e.bleed.t : 0, opt.bleed), dps }; }
    PA.Weapons.onHit(st, e, opt, dmg);
    const crit = e.state === 'recover' || e.state === 'stagger';
    fx(st, { kind: 'spark', x: e.x, y: e.y, ttl: 0.22, t: 0, angle: opt.dir ? Math.atan2(opt.dir.y, opt.dir.x) : st.rng.range(0, Math.PI * 2), crit });
    text(st, e.x + st.rng.range(-8, 8), e.y - e.r - 6, String(Math.round(dmg)), crit ? '#ffd166' : '#fff');
    ev(st, 'hit', { crit });
    if (e.hp <= 0) killEnemy(st, e, opt);
    return dmg;
  }
  function killEnemy(st, e, opt) {
    e.dead = true; e.deathT = 0; if (!e.structure) st.stats.kills++; if (e.elite && !e.structure) st.stats.eliteKills = (st.stats.eliteKills || 0) + 1;
    if (st.metrics) { const m = metricsFor(st, e); m.killed++; if (!e.acted) m.diedBeforeAttack++; m.ttk.push(Math.round((st.t - e.spawnT) * 100) / 100); if (e.firstHitT != null) m.ttkFromHit.push(Math.round((st.t - e.firstHitT) * 100) / 100); }
    ev(st, 'kill', { type: e.type });
    // 경험치: 처치 원인과 무관하게 즉시, 같은 적은 1회(dead 플래그)
    const xp = PA.Growth.xpValue(e, st.regionId);
    if (xp > 0 && st.build.growth && !st.fixedBuild) { st.stats.xp += xp; st.xpGained += xp; const gained = PA.Growth.addXp(st.build.growth, xp); if (gained) { st.levelUps += gained; st.stats.levelUps += gained; ev(st, 'levelup', { n: gained }); text(st, st.player.x, st.player.y - 62, '레벨 업!', '#ffe066'); } }
    if (e.boss) { e.state = 'dead'; e.airborne = false; st.bossDownT = 0; ev(st, 'boss_down'); }
    if (!e.structure && st.build.has('saving') && inField(st, e) && st.player.special.cd > 0) {
      st.player.special.cd = Math.max(0, st.player.special.cd - C().SAVING.cdPerKill);
      st.stats.savingKills = (st.stats.savingKills || 0) + 1;
      text(st, e.x, e.y - e.r - 22, '감속장 -' + C().SAVING.cdPerKill + '초', '#a9d8ff');
      ev(st, 'saving');
    }
    fx(st, { kind: 'death', x: e.x, y: e.y, r: e.r, ttl: 0.4, t: 0, color: e.def.color });
    if (e.type === 'spore') { addZone(st, 'spore', e.x, e.y, e.def.deathCloudR, e.def.deathCloudTtl, e.def.cloudDamage); noteAttack(st, e, 'death'); }
    if (st.build.has('frost') && e.chill > 0) { // 파편: 추가 피해(냉기를 다시 부여하지 않음)
      const F = C().FROST;
      for (let i = 0; i < F.shards; i++) {
        const a = (i / F.shards) * Math.PI * 2;
        st.projectiles.push({ owner: 'player', kind: 'shard_common', x: e.x, y: e.y, vx: Math.cos(a) * F.shardSpeed, vy: Math.sin(a) * F.shardSpeed, r: 4, dmg: F.shardDamage * st.build.masteryMult, ttl: F.shardTtl, hits: new Set([e.id]), tag: 'common:frost' });
      }
      text(st, e.x, e.y - 20, '파편!', '#bfefff');
      ev(st, 'shatter');
    }
    if (st.build.has('flare') && st.zones.some(z => z.type === 'fire' && m().dist(z, e) <= z.r + e.r)) {
      const F = C().FLARE;
      fx(st, { kind: 'flare', x: e.x, y: e.y, r: F.radius, ttl: 0.35, t: 0 });
      for (const o of st.enemies) if (!o.dead && o !== e && m().dist(o, e) <= F.radius + o.r) damageEnemy(st, o, F.damage * st.build.masteryMult, { dir: m().norm(o.x - e.x, o.y - e.y), knock: 40, src: { extra: true, direct: false, tag: 'common:flare' } });
      text(st, e.x, e.y - 34, '불꽃 파열!', '#ff9f43');
      ev(st, 'explode');
    }
    PA.Weapons.onKill(st, e, opt);
    if (st.markTarget === e) { st.markTarget = null; assignMark(st); }
  }
  function addZone(st, type, x, y, r, ttl, dmg) { const z = { type, x, y, r, ttl, maxTtl: ttl, dmg, tick: 0, t: 0 }; st.zones.push(z); return z; }
  // 잔불: 장애물 안쪽(바닥이 아닌 곳)이면 그 조각은 생략한다(플레이어 위치는 항상 유효하므로 보통 발생하지 않음)
  function addFireAt(st, x, y) {
    const E = C().EMBER;
    if (!validPos(st, x, y, 0)) return false;
    addZone(st, 'fire', x, y, E.radius * (st.build.widthMult || 1), E.ttl * (st.build.durationMult || 1), E.damage); return true;
  }

  // ---------- 플레이어 공격(무기 엔진) ----------
  // 레거시 호환: 첫 무기 기준 대상 선택·발사(기존 테스트·디버그용)
  function chooseTarget(st) { const w = st.weapons[0]; return PA.Weapons.pickTarget(st, w, w.stats.range || 95, true); }
  function performAttack(st, angle, form) {
    const w = st.weapons[0], p = st.player, fake = { x: p.x + Math.cos(angle) * 50, y: p.y + Math.sin(angle) * 50, r: 1, dead: false };
    st.stats.attacks++; w.count++;
    const kind = form === 'beam' ? 'beam' : (w.stats.kind === 'beam' ? 'beam' : 'arc');
    if (form === 'spin') { const S = C().SPIN, r = S.radius * st.build.widthMult; fx(st, { kind: 'spin', x: p.x, y: p.y, r, ttl: 0.22, t: 0 }); PA.Weapons.hitCircle(st, w, p.x, p.y, r, S.damageMult, { knock: S.knock }); return; }
    PA.Weapons.FIRE[kind](st, w, fake, true);
  }
  function updateAttack(st, dt) { const before = st.weapons.reduce((n, w) => n + w.count, 0); PA.Weapons.update(st, dt); st.stats.attacks += st.weapons.reduce((n, w) => n + w.count, 0) - before; }

  // ---------- 플레이어 이동/회피/특수기 ----------
  function updatePlayer(st, input, dt) {
    const p = st.player, cfg = C().PLAYER, a = st.arena, b = st.build;
    p.animT += dt; p.swingT += dt; p.hurtT += dt;
    if (p.hitProt > 0) p.hitProt -= dt;
    if (p.flash > 0) p.flash -= dt;
    if (p.special.cd > 0) p.special.cd = Math.max(0, p.special.cd - dt);
    const mv = m().norm(input.mx || 0, input.my || 0);
    p.moving = mv.x !== 0 || mv.y !== 0;
    if (p.moving) p.walkT += dt;
    if (p.moving) p.face = Math.atan2(mv.y, mv.x);

    // 회피 입력은 같은 단계에서 즉시 시작한다(입력 반응성, dt 독립 거리)
    if (!p.dodge.active && input.dodge && p.dodge.cd <= 0) {
      const d = p.moving ? mv : { x: Math.cos(p.face), y: Math.sin(p.face) };
      p.dodge.active = true; p.dodge.t = 0; p.dodge.dx = d.x; p.dodge.dy = d.y; p.dodge.emberIdx = -1;
      if (b.has('ember')) { p.dodge.emberIdx = 0; addFireAt(st, p.x, p.y); }
      st.stats.dodges = (st.stats.dodges || 0) + 1;
      ev(st, 'dodge');
    }
    if (p.dodge.active) {
      const useDt = Math.min(dt, Math.max(0, cfg.dodge.duration - p.dodge.t));
      p.dodge.t += dt;
      const spd = cfg.dodge.distance / cfg.dodge.duration;
      const mv1 = moveSwept(st, p, p.dodge.dx * spd * useDt, p.dodge.dy * spd * useDt); // 회피도 장애물을 통과하지 않는다
      if (mv1.hit && mv1.hit !== 'wall') { /* 장애물에 닿으면 남은 거리를 버리고 표면에서 멈춘다 */ }
      if (b.has('ember')) {
        const E = C().EMBER, frac = p.dodge.t / cfg.dodge.duration;
        const idx = Math.floor(frac * E.count);
        if (idx > p.dodge.emberIdx && idx < E.count) { p.dodge.emberIdx = idx; addFireAt(st, p.x, p.y); }
      }
      if (p.dodge.t >= cfg.dodge.duration) { p.dodge.active = false; p.dodge.cd = cfg.dodge.cooldown * b.dodgeCdMult - (p.dodge.t - cfg.dodge.duration); }
    } else {
      if (p.dodge.cd > 0) p.dodge.cd -= dt;
      const wind = st.zones.some(z => z.type === 'windpath' && m().dist(z, p) <= z.r) ? 1.4 : 1;
      const web = st.zones.some(z => z.type === 'web' && m().dist(z, p) <= z.r + p.r * 0.5) ? 0.5 : 1; // 거미줄: 걷기만 50%(회피는 정상)
      moveSwept(st, p, mv.x * cfg.speed * b.speedMult * wind * web * dt, mv.y * cfg.speed * b.speedMult * wind * web * dt, true); // 표면을 따라 미끄러진다
    }
    if (input.special && p.special.cd <= 0) PA.Skills.castQ(st);
    if (input.skillE && p.eCd <= 0 && b.skills.e) PA.Skills.castE(st);
    pushOut(st, p);
    updateAttack(st, dt);
  }

  // ---------- 적 AI ----------
  function moveToward(e, tx, ty, speed, dt) {
    const n = m().norm(tx - e.x, ty - e.y);
    e.x += n.x * speed * dt; e.y += n.y * speed * dt;
  }
  // 장애물을 돌아 접근한다
  function approach(st, e, tx, ty, speed, dt) {
    if (e.steerT > 0) e.steerT -= dt;
    const n = st.obstacles.length ? steerDir(st, e, tx, ty) : m().norm(tx - e.x, ty - e.y);
    moveSwept(st, e, n.x * speed * dt, n.y * speed * dt, true);
  }
  // 이동 속도: 냉기 60%, 감속장 40%, 둘 다면 더 강한 40%(곱하지 않는다). 준비·빈틈 진행 감소는 감속장만(timeFactor)
  function enemySpeedMult(st, e) { return Math.min(timeFactor(st, e), e.chill > 0 ? C().FROST.slow : 1); }

  // 보스전 겹침 제한: 늑대의 돌진 준비·실행은 동시에 1마리, 보스의 큰 공격 확정·실행 중에는 시작 금지.
  // 조건이 열려도 개체마다 짧은 무작위 지연을 두어 재개 순간 한꺼번에 발동하지 않게 한다.
  function wolfMayAttack(st, e, dt) {
    if (st.mode !== 'boss') return mayAttack(st, e, dt);
    const others = st.enemies.some(o => o !== e && !o.dead && !o.boss && (o.state === 'crouch' || o.state === 'lock' || o.state === 'dash'));
    const bossBusy = st.boss && !st.boss.dead && PA.Boss.bossCommitted(st.boss);
    if (others || bossBusy) { e.readyT = null; return false; }
    if (e.readyT == null) { const d = PA.BOSS.overlap.wolfDelay; e.readyT = st.rng.range(d[0], d[1]); }
    e.readyT -= dt;
    return e.readyT <= 0;
  }
  // 일반 조우의 동시 공격 제한(시험실·조합 프리셋에서 overlapLimit 지정 시). 준비·확정·실행 중인 적 수가 한도 이상이면 새 준비를 미룬다.
  const COMMITTED = new Set(['crouch', 'lock', 'dash', 'aim', 'swell']);
  function isCommitted(e) { return COMMITTED.has(e.state) || (PA.Enemies && PA.Enemies.isCommitted && PA.Enemies.isCommitted(e)); }
  function mayAttack(st, e, dt) {
    if (!st.overlapLimit) return true;
    const n = st.enemies.filter(o => o !== e && !o.dead && !o.boss && isCommitted(o)).length;
    if (n >= st.overlapLimit) { e.readyT = null; return false; }
    if (e.readyT == null) { const d = PA.BOSS.overlap.wolfDelay; e.readyT = st.rng.range(d[0], d[1]); }
    e.readyT -= dt;
    return e.readyT <= 0;
  }
  function updateWolf(st, e, dt) {
    const d = e.def, p = st.player, tf = timeFactor(st, e), sm = enemySpeedMult(st, e);
    const dist = m().dist(e, p);
    switch (e.state) {
      case 'approach':
        approach(st, e, p.x, p.y, d.speed * sm, dt);
        if (e.grace > 0) { e.grace -= dt; break; }
        if (dist <= d.engageDist && !losBlocked(st, e, p) && wolfMayAttack(st, e, dt)) { e.state = 'crouch'; e.stateT = 0; e.dashLeft = d.dashes || 1; e.readyT = null; noteAttack(st, e, 'prepare'); }
        break;
      case 'crouch': // 방향 추적 중
        e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x);
        e.stateT += dt * tf;
        if (e.stateT >= (e.dashLeft < (d.dashes || 1) ? d.secondCrouch : d.crouch)) { e.state = 'lock'; e.stateT = 0; e.dir = e.aimAngle; ev(st, 'lock'); }
        break;
      case 'lock': // 방향 고정. 절대 바꾸지 않음
        e.stateT += dt * tf;
        if (e.stateT >= d.lock) { e.state = 'dash'; e.stateT = 0; e.hitBy = null; noteAttack(st, e, 'execute'); }
        break;
      case 'dash': {
        const remain = Math.max(0, d.dashTime - e.stateT);
        const useDt = Math.min(dt * tf, remain);
        e.stateT += dt * tf;
        const step = d.dashSpeed * useDt;
        const x0 = e.x, y0 = e.y;
        // 스윕 이동: 장애물·벽에 닿으면 그 지점에서 정지. 물기 판정은 실제로 이동한 구간에만 적용(장애물 뒤로 관통하지 않음)
        const mv = moveSwept(st, e, Math.cos(e.dir) * step, Math.sin(e.dir) * step);
        if (!e.hitBy && m().segCircle(x0, y0, e.x, e.y, p, p.r + e.r)) { e.hitBy = 'player'; e.biteT = 0; ev(st, 'bite'); damagePlayer(st, d.damage, 'wolf'); }
        const hitWall = !!mv.hit;
        if (e.stateT >= d.dashTime || hitWall) {
          if (!e.hitBy) e.biteT = 0; // 빗나간 물기도 같은 시점에 턱을 닫는다
          e.dashLeft--;
          if (e.dashLeft > 0) { e.state = 'crouch'; e.stateT = 0; }
          else { e.state = 'recover'; e.stateT = 0; }
        }
        break;
      }
      case 'recover':
        e.stateT += dt * tf;
        if (e.stateT >= d.recover) { e.state = 'approach'; e.stateT = 0; }
        break;
    }
  }
  function updateArcher(st, e, dt) {
    const d = e.def, p = st.player, tf = timeFactor(st, e), sm = enemySpeedMult(st, e);
    const dist = m().dist(e, p);
    switch (e.state) {
      case 'approach':
        if (dist < d.keepMin) approach(st, e, e.x * 2 - p.x, e.y * 2 - p.y, d.speed * sm, dt);
        else if (dist > d.keepMax) approach(st, e, p.x, p.y, d.speed * sm, dt);
        e.stateT += dt * tf;
        if (dist <= d.keepMax + 40 && e.stateT >= 0.3 && mayAttack(st, e, dt)) { e.state = 'aim'; e.stateT = 0; e.readyT = null; noteAttack(st, e, 'prepare'); }
        break;
      case 'aim':
        e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x);
        e.stateT += dt * tf;
        if (e.stateT >= d.aim) { e.state = 'lock'; e.stateT = 0; e.dir = e.aimAngle; ev(st, 'lock'); }
        break;
      case 'lock':
        e.stateT += dt * tf;
        if (e.stateT >= d.lock) {
          st.projectiles.push({ owner: 'enemy', kind: 'arrow', x: e.x + Math.cos(e.dir) * (e.r + 4), y: e.y + Math.sin(e.dir) * (e.r + 4), vx: Math.cos(e.dir) * d.arrowSpeed, vy: Math.sin(e.dir) * d.arrowSpeed, r: d.arrowR, dmg: d.arrowDamage, ttl: 4, angle: e.dir });
          ev(st, 'shoot'); noteAttack(st, e, 'execute');
          e.state = 'recover'; e.stateT = 0;
        }
        break;
      case 'recover':
        e.stateT += dt * tf;
        if (e.stateT >= d.recover) { e.state = 'approach'; e.stateT = 0; }
        break;
    }
  }
  function updateSpore(st, e, dt) {
    const d = e.def, p = st.player, tf = timeFactor(st, e), sm = enemySpeedMult(st, e);
    const dist = m().dist(e, p);
    switch (e.state) {
      case 'approach':
        approach(st, e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist && mayAttack(st, e, dt)) { e.state = 'swell'; e.stateT = 0; e.readyT = null; noteAttack(st, e, 'prepare'); }
        break;
      case 'swell':
        e.stateT += dt * tf;
        if (e.stateT >= d.swell) { addZone(st, 'spore', e.x, e.y, d.cloudR, d.cloudTtl, d.cloudDamage); ev(st, 'spore'); noteAttack(st, e, 'execute'); e.state = 'recover'; e.stateT = 0; }
        break;
      case 'recover':
        e.stateT += dt * tf;
        if (e.stateT >= d.recover) { e.state = 'approach'; e.stateT = 0; }
        break;
    }
  }
  function updateEnemies(st, dt) {
    const a = st.arena;
    for (const e of st.enemies) {
      if (e.dead) { e.deathT += dt; continue; }
      e.animT += dt; e.biteT += dt;
      const mdx = e.x - e.lastX, mdy = e.y - e.lastY; const mlen = Math.hypot(mdx, mdy);
      if (mlen > 0.05) { e.moveT += mlen / 40; if (Math.abs(mdx) > 0.02) e.faceX = mdx > 0 ? 1 : -1; }
      e.lastX = e.x; e.lastY = e.y;
      if (e.flash > 0) e.flash -= dt;
      if (e.chill > 0) e.chill -= dt;
      if (e.conduct > 0) e.conduct -= dt;
      for (const key of ['burn', 'bleed']) { const d = e[key]; if (d && d.t > 0) { d.t -= dt; d.tick = (d.tick || 0) - dt; if (d.tick <= 0) { d.tick = 0.5; damageEnemy(st, e, d.dps * 0.5, { src: { extra: true, direct: false }, dot: key }); if (e.dead) break; } } }
      if (e.dead) continue;
      if (e.boss) PA.Boss.update(st, e, dt);
      else if (e.type === 'wolf' || e.type === 'wolf_alpha') updateWolf(st, e, dt);
      else if (e.type === 'archer') updateArcher(st, e, dt);
      else if (e.type === 'spore') updateSpore(st, e, dt);
      else if (PA.Enemies && PA.Enemies.has(e.type)) PA.Enemies.update(st, e, dt);
      if (e.airborne) continue; // 도약 중: 지형·분리 무시
      // 넉백 속도 감쇠
      if (e.vx || e.vy) { moveSwept(st, e, e.vx * dt, e.vy * dt); const k = Math.exp(-10 * dt); e.vx *= k; e.vy *= k; if (Math.abs(e.vx) < 1) e.vx = 0; if (Math.abs(e.vy) < 1) e.vy = 0; }
      pushOut(st, e);
    }
    // 분리: 완전히 겹치지 않게
    const alive = st.enemies.filter(e => !e.dead);
    for (let i = 0; i < alive.length; i++) for (let j = i + 1; j < alive.length; j++) {
      const A = alive[i], B = alive[j];
      if (A.state === 'dash' || B.state === 'dash' || A.airborne || B.airborne || A.hidden || B.hidden) continue;
      const dx = B.x - A.x, dy = B.y - A.y, d = Math.hypot(dx, dy), min = A.r + B.r;
      if (d < min && d > 1e-6) { const push = (min - d) / 2 * C().SEPARATION; if (A.structure && B.structure) continue; if (A.structure) { B.x += dx / d * push * 2; B.y += dy / d * push * 2; pushOut(st, B); continue; } if (B.structure) { A.x -= dx / d * push * 2; A.y -= dy / d * push * 2; pushOut(st, A); continue; } A.x -= dx / d * push; A.y -= dy / d * push; B.x += dx / d * push; B.y += dy / d * push; pushOut(st, A); pushOut(st, B); }
    }
    st.enemies = st.enemies.filter(e => !e.dead || e.deathT < 0.9 || e.boss);
  }

  // ---------- 투사체/지역/필드 ----------
  function updateProjectiles(st, dt) {
    const p = st.player, a = st.arena;
    for (const pr of st.projectiles) {
      const tf = pr.owner === 'enemy' ? timeFactor(st, pr) : 1;
      if (pr.owner === 'player' && (pr.target || pr.boomerang)) PA.Weapons.steerProjectile(st, pr, dt);
      if (pr.dead) continue;
      // 시간의 복제(보스 보상): 감속장을 통과하는 아군 투사체를 한 번 복제
      if (pr.owner === 'player' && pr.weapon && !pr.cloned && !pr.isClone && st.build.bossRewards.includes('clone') && inField(st, pr)) { pr.cloned = true; const c = Object.assign({}, pr, { hits: new Set(pr.hits), isClone: true, cloned: true, x: pr.x - pr.vy * 0.03, y: pr.y + pr.vx * 0.03, boomerang: null, target: pr.target }); st.projectiles.push(c); }
      const nx = pr.x + pr.vx * tf * dt, ny = pr.y + pr.vy * tf * dt;
      const obs = m().sweepCircle(pr.x, pr.y, nx, ny, pr.r, st.obstacles); const tObs = obs ? obs.t : Infinity;
      if (pr.owner === 'enemy') {
        const tp = m().segCircleT(pr.x, pr.y, nx, ny, p, p.r + pr.r);
        if (tp != null && tp <= tObs) { pr.dead = true; damagePlayer(st, pr.dmg, pr.kind); }
      } else {
        const cands = [];
        for (const e of st.enemies) { if (e.dead || e.hidden || (pr.hits && pr.hits.has(e.id))) continue; const t = m().segCircleT(pr.x, pr.y, nx, ny, e, e.r + pr.r); if (t != null) cands.push([t, e]); }
        cands.sort((a, b) => a[0] - b[0]);
        for (const [t, e] of cands) {
          if (t > tObs) break;
          if (pr.weapon || pr.kind === 'shard_common') { if (!pr.hits) pr.hits = new Set(); if (PA.Weapons.onProjectileHit(st, pr, e)) { pr.dead = true; break; } }
          else { pr.dead = true; damageEnemy(st, e, pr.dmg, { dir: m().norm(pr.vx, pr.vy), knock: 10 }); break; }
        }
      }
      if (!pr.dead && obs) { pr.dead = true; fx(st, { kind: 'spark', x: pr.x + pr.vx * tf * dt * obs.t, y: pr.y + pr.vy * tf * dt * obs.t, ttl: 0.15, t: 0, angle: Math.atan2(-pr.vy, -pr.vx), crit: false }); }
      pr.x = nx; pr.y = ny; pr.ttl -= dt;
      if (pr.x < -10 || pr.x > a.w + 10 || pr.y < -10 || pr.y > a.h + 10 || pr.ttl <= 0) pr.dead = true;
    }
    st.projectiles = st.projectiles.filter(pr => !pr.dead);
  }
  function updateZones(st, dt) {
    const p = st.player;
    // 플레이어 지역 피해: 0.5초마다 최대 1틱, 겹쳐도 가장 큰 피해 1회
    p.zoneTick -= dt;
    let maxDmg = 0;
    for (const z of st.zones) {
      z.ttl -= dt; z.t += dt;
      if (z.type === 'spore' && m().dist(z, p) <= z.r + p.r * 0.5) maxDmg = Math.max(maxDmg, z.dmg);
      if (z.type === 'hazard' && PA.Objectives) maxDmg = Math.max(maxDmg, PA.Objectives.zoneDamage(st, z, p));
      if (z.type === 'fire') {
        z.tick -= dt;
        if (z.tick <= 0) { z.tick = C().EMBER.tick; for (const e of st.enemies) if (!e.dead && m().dist(z, e) <= z.r + e.r) damageEnemy(st, e, z.weapon ? z.dmg : z.dmg * st.build.masteryMult, { src: z.weapon ? { weapon: z.weapon.stats, weaponId: z.weapon.id, direct: false, extra: true } : { extra: true, direct: false, tag: 'common:ember' } }); }
      }
      if (z.type === 'coldground') { z.tick -= dt; if (z.tick <= 0) { z.tick = 0.25; for (const e of st.enemies) if (!e.dead && m().dist(z, e) <= z.r + e.r) e.chill = Math.max(e.chill, 1.0); } }
      if (z.type === 'storm') { z.tick -= dt; if (z.tick <= 0) { z.tick = 0.5; fx(st, { kind: 'strike', x: z.x + st.rng.range(-20, 20), y: z.y + st.rng.range(-20, 20), r: 30, ttl: 0.2, t: 0 }); for (const e of st.enemies) if (!e.dead && m().dist(z, e) <= z.r + e.r) damageEnemy(st, e, z.dmg, { src: { skill: true, direct: false, skillId: 'strike' } }); } }
    }
    if (maxDmg > 0 && p.zoneTick <= 0) { p.zoneTick = C().PLAYER.zoneTick; zoneDamage(st, maxDmg); }
    if (maxDmg === 0 && p.zoneTick < 0) p.zoneTick = 0;
    if (PA.Enemies && PA.Enemies.detonate) for (const z of st.zones) if (z.type === 'frostzone' && z.ttl <= 0) PA.Enemies.detonate(st, z);
    st.zones = st.zones.filter(z => z.ttl > 0);
    if (st.field) {
      st.field.ttl -= dt;
      if (st.field.ttl <= 0) endField(st);
    }
  }
  // 감속장 종료: 정지된 칼날 흔적을 터뜨리고 필드를 제거한다
  function endField(st) {
    const f = st.field; if (!f) return;
    if (st.build.has('stasis')) {
      let total = 0;
      for (const e of st.enemies) if (!e.dead && e.stasis > 0) { const dmg = e.stasis * C().STASIS.damagePerStack * st.build.masteryMult; fx(st, { kind: 'stasisburst', x: e.x, y: e.y, r: 34 + e.stasis * 10, ttl: 0.4, t: 0 }); e.stasis = 0; total += damageEnemy(st, e, dmg, { src: { extra: true, direct: false, tag: 'common:stasis' } }); }
      if (total > 0) { text(st, f.x, f.y - f.r - 26, '정지된 칼날 폭발 ' + Math.round(total), '#cfeaff'); ev(st, 'explode'); }
    }
    fx(st, { kind: 'fieldend', x: f.x, y: f.y, r: f.r, ttl: 0.35, t: 0 });
    st.field = null;
    PA.Skills.onFieldEnd(st, f);
  }
  function updatePickups(st, dt) {
    const p = st.player;
    for (const k of st.pickups) {
      k.t += dt;
      if (!k.taken && m().dist(k, p) <= k.r + p.r) {
        k.taken = true;
        const before = p.hp; p.hp = Math.min(p.hpMax, p.hp + k.amount);
        text(st, p.x, p.y - 34, '+' + Math.round(p.hp - before), '#9cffb0'); ev(st, 'orb');
      }
    }
    st.pickups = st.pickups.filter(k => !k.taken);
  }
  function updateChest(st, dt) {
    const p = st.player;
    if (st.chest && !st.chest.opened && m().dist(st.chest, p) <= st.chest.r + p.r) {
      st.chest.opened = true; st.chest.t = 0;
      const g = st.rng.int(C().CHEST.gold[0], C().CHEST.gold[1]);
      st.stats.chestGold += g;
      text(st, st.chest.x, st.chest.y - 24, '+' + g + ' 금화', '#ffd166');
      ev(st, 'chest');
    }
    if (st.chest && st.chest.opened) st.chest.t += dt;
  }
  function updateWaves(st, dt) {
    // 대기 중 스폰
    for (const s of st.pending) { s.t -= dt; if (s.t <= 0) { const e = spawnEnemy(st, s.type, s.x, s.y); if (s.summoned) { e.summoned = true; e.grace = PA.BOSS.overlap.summonGrace; } } }
    st.pending = st.pending.filter(s => s.t > 0);
    const alive = st.enemies.filter(e => !e.dead && !e.structure).length;
    if (st.mode !== 'boss' && st.waveIndex < st.waves.length - 1 && alive === 0 && st.pending.length === 0) {
      st.waveTimer -= dt;
      if (st.waveTimer <= 0) {
        st.waveIndex++; st.waveTimer = C().WAVE_DELAY;
        queueWave(st, st.waves[st.waveIndex]);
        if (st.waveIndex === C().CHEST.wave && !st.chestSpawned) {
          st.chestSpawned = true; const pos = edgePos(st); st.chest = { x: pos.x, y: pos.y, r: C().CHEST.r, opened: false, t: 0 };
        }
      }
    }
    if (st.mode !== 'boss') st.spawnedAll = st.waveIndex >= st.waves.length - 1 && st.pending.length === 0;
  }
  // 정예 수: 웨이브 정의(남은 웨이브 포함) + 이미 스폰된 정예. 처치 수는 죽은 정예
  // 남은 적 수: 살아 있는 적 + 등장 대기 + 남은 웨이브 정의
  function remaining(st) {
    let n = st.enemies.filter(e => !e.dead && !e.structure).length + st.pending.length;
    for (let i = st.waveIndex + 1; i < st.waves.length; i++) for (const g of st.waves[i]) n += g.n;
    return { total: n, alive: st.enemies.filter(e => !e.dead && !e.structure).length, wavesLeft: Math.max(0, st.waves.length - 1 - Math.max(0, st.waveIndex)), waves: st.waves.length };
  }
  function eliteCount(st) {
    const isE = (t) => !!(PA.ENEMIES[t] && PA.ENEMIES[t].elite);
    let killed = st.stats.eliteKills || 0, total = killed; // 죽은 정예는 잠시 뒤 목록에서 제거되므로 처치 수는 누적 통계로 센다
    for (const e of st.enemies) if (e.elite && !e.structure && !e.dead) total++;
    for (const s of st.pending) if (isE(s.type)) total++;
    for (let i = st.waveIndex + 1; i < st.waves.length; i++) for (const g of st.waves[i]) if (isE(g.type)) total += g.n;
    return { total, killed };
  }
  function checkObjective(st) {
    if (st.status !== 'running') return;
    const alive = st.enemies.filter(e => !e.dead && !e.structure);
    if (PA.Objectives && PA.Objectives.is(st.objective)) { if (PA.Objectives.check(st)) { st.status = 'won'; ev(st, 'win'); } return; } // 목표 4종: 적이 살아 있어도 달성 시 승리
    if (st.objective === 'boss') {
      if (st.boss && st.boss.dead) { st.status = 'won'; ev(st, 'win'); }
    } else if ((st.objective === 'clear' || st.objective === 'elite') && st.spawnedAll && st.pending.length === 0 && alive.length === 0) { st.status = 'won'; ev(st, 'win'); } // 전멸 전투(일반·정예): 남은 웨이브·등장 대기 중인 적까지 모두 처치해야 종료. 정예 표시는 HUD 정보일 뿐
  }
  function updateEffects(st, dt) {
    for (const f of st.effects) { f.t += dt; if (f.kind === 'text') f.y -= 30 * dt; }
    st.effects = st.effects.filter(f => f.t < f.ttl);
  }

  function step(st, input, dt) {
    st.stepN = (st.stepN || 0) + 1; // 고정 단계 번호: 봇 판단 주기(PA.Bot.DECIDE_STEPS)의 기준. 렌더 프레임과 무관
    if (st.status !== 'running') { updateEffects(st, dt); for (const e of st.enemies) if (e.dead) e.deathT += dt; if (st.boss && st.boss.dead) st.bossDownT += dt; return; }
    if (st.intro > 0) { // 입장 연출: 시간·행동·피해 없음
      st.intro -= dt; for (const e of st.enemies) e.animT += dt; updateEffects(st, dt);
      if (st.intro <= 0 && st.boss) { st.boss.state = 'approach'; st.boss.stateT = 0; ev(st, 'boss_roar', { phase: 1 }); }
      return;
    }
    st.t += dt; st.stats.elapsed += dt;
    if (st.timeLimit > 0 && st.t >= st.timeLimit) { st.status = 'timeout'; ev(st, 'timeout'); return; } // 시간 초과: 승패와 별도 상태
    updatePlayer(st, input || {}, dt);
    PA.Skills.update(st, dt);
    updateEnemies(st, dt);
    if (st.obj && PA.Objectives) PA.Objectives.update(st, dt);
    updateProjectiles(st, dt);
    updateZones(st, dt);
    updatePickups(st, dt);
    updateChest(st, dt);
    updateWaves(st, dt);
    updateEffects(st, dt);
    checkObjective(st);
    // 같은 단계에서 보스와 플레이어가 함께 죽으면 승리 우선
    if (st.status === 'running' && st.pendingLoss) { st.status = 'lost'; ev(st, 'lose'); }
    if (st.status === 'won') st.pendingLoss = false;
  }

  // 레벨업 선택 적용 뒤: 파생 수치를 다시 계산하고 무기 목록을 갱신(타이머 유지)
  function rebuild(st, build) {
    const p = st.player, oldMax = p.hpMax;
    st.build = build; p.hpMax = build.hpMax; if (build.hpMax > oldMax) p.hp = Math.min(p.hpMax, p.hp + (build.hpMax - oldMax));
    PA.Weapons.refresh(st);
  }
  return { create, step, rebuild, summary, eliteCount, remaining, noteAttack, metricsFor, enemyKey, srcKey, mayAttack, isCommitted, knockEnemy, addFireAt, damagePlayer, damageEnemy, spawnEnemy, performAttack, chooseTarget, inField, addZone, queueWave, endField, pushOut, moveSwept, losBlocked, validPos, nearestValidPos, beamLength, steerDir, ev, fx, text, approach, timeFactor, enemySpeedMult, wolfMayAttack };
})();
