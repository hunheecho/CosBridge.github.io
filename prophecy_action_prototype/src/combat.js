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
    const st = {
      t: 0, seed: opts.seed || 1, rng, arena: Object.assign({}, cfg.ARENA),
      build,
      objective: opts.objective || 'clear',
      waves: opts.waves || [[{ type: 'wolf', n: 2 }]],
      waveIndex: -1, waveTimer: 0.4, pending: [], // pending spawns {type,x,y,t}
      player: {
        x: cfg.ARENA.w / 2, y: cfg.ARENA.h / 2, r: cfg.PLAYER.r,
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
      stats: { kills: 0, damageTaken: 0, perfectDodges: 0, chestGold: 0, elapsed: 0, attacks: 0 },
      spawnedAll: false,
    };
    return st;
  }

  // ---------- 이벤트/이펙트 ----------
  function ev(st, name, data) { st.events.push(Object.assign({ name }, data || {})); }
  function fx(st, e) { st.effects.push(e); }
  function text(st, x, y, txt, color) { fx(st, { kind: 'text', x, y, text: txt, color: color || '#fff', ttl: 0.8, t: 0 }); }

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
      while (m().dist(p, st.player) < 160 && tries++ < 8) p = edgePos(st);
      st.pending.push({ type: g.type, x: p.x, y: p.y, t: C().SPAWN_WARN });
      fx(st, { kind: 'spawnwarn', x: p.x, y: p.y, ttl: C().SPAWN_WARN, t: 0, type: g.type });
    }
    ev(st, 'wave', { index: st.waveIndex });
  }
  function spawnEnemy(st, type, x, y) {
    const d = PA.ENEMIES[type];
    const e = {
      id: nextId++, type, def: d, name: d.name, x, y, r: d.r, hp: d.hp, hpMax: d.hpMax || d.hp,
      state: 'approach', stateT: 0, dir: 0, aimAngle: 0, chill: 0, stasis: 0, flash: 0, dead: false, deathT: 0,
      dashLeft: d.dashes || 1, vx: 0, vy: 0, animT: 0, elite: !!d.elite, hitBy: null, biteT: 9, moveT: 0, lastX: x, lastY: y, faceX: 1,
    };
    st.enemies.push(e);
    if (st.build.has('mark')) assignMark(st);
    return e;
  }
  // 표식: 우선순위(정예>궁수>포자>늑대)가 가장 높은 적. 더 위험한 적이 나타나면 옮겨간다.
  function assignMark(st) {
    const alive = st.enemies.filter(e => !e.dead), prio = C().MARK.priority;
    let best = null;
    for (const t of prio) {
      const cands = alive.filter(e => e.type === t);
      if (cands.length) { cands.sort((a, b) => m().dist(a, st.player) - m().dist(b, st.player)); best = cands[0]; break; }
    }
    if (st.markTarget && !st.markTarget.dead && best && prio.indexOf(st.markTarget.type) <= prio.indexOf(best.type)) return;
    st.markTarget = best;
  }

  // ---------- 감속 ----------
  function inField(st, o) { return st.field && m().dist(st.field, o) <= st.field.r + (o.r || 0); }
  function timeFactor(st, o) { return inField(st, o) ? C().PLAYER.special.slow : 1; }

  // ---------- 플레이어 피해 ----------
  function damagePlayer(st, amount, src) {
    const p = st.player;
    if (p.dead || st.status !== 'running') return false;
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
    const p = st.player;
    let rest = amount;
    if (p.shield > 0) {
      const used = Math.min(p.shield, rest);
      p.shield -= used; rest -= used;
      if (p.shield <= 0 && st.build.has('barrier')) barrierBurst(st);
    }
    if (rest > 0) { p.hp -= rest; st.stats.damageTaken += rest; }
    p.flash = 0.2; p.hurtT = 0;
    fx(st, { kind: 'hitflash', x: p.x, y: p.y, ttl: 0.25, t: 0 });
    text(st, p.x, p.y - 28, '-' + Math.round(amount), '#ff6b6b');
    ev(st, 'hurt', { src });
    if (p.hp <= 0) { p.hp = 0; p.dead = true; st.status = 'lost'; ev(st, 'lose'); }
  }
  function zoneDamage(st, amount) {
    const p = st.player;
    if (p.dead || p.dodge.active) return;
    applyPlayerDamage(st, amount, 'zone');
  }
  function barrierBurst(st) {
    const p = st.player, cfg = C().BARRIER;
    for (const e of st.enemies) {
      if (e.dead) continue;
      const d = m().dist(e, p);
      if (d <= cfg.knockRadius) { const n = m().norm(e.x - p.x, e.y - p.y); if (e.state === 'dash' || e.state === 'lock' || e.state === 'crouch') { e.state = 'recover'; e.stateT = 0; e.biteT = 0; } knockEnemy(e, n, cfg.knock); }
    }
    fx(st, { kind: 'burst', x: p.x, y: p.y, r: cfg.knockRadius, ttl: 0.35, t: 0, color: '#7ef2ff' });
    text(st, p.x, p.y - 44, '방벽 파열!', '#7ef2ff');
    ev(st, 'burst');
  }
  function knockEnemy(e, n, amount) { if (e.state === 'dash') return; e.vx += n.x * amount * 4; e.vy += n.y * amount * 4; }

  // ---------- 적 피해 ----------
  function damageEnemy(st, e, amount, opt) {
    opt = opt || {};
    if (e.dead) return 0;
    let dmg = amount;
    if (e.state === 'recover') dmg *= st.build.exposedMult;
    if (st.markTarget === e) dmg *= C().MARK.damageMult;
    dmg = Math.round(dmg * 10) / 10;
    e.hp -= dmg; e.flash = 0.12;
    if (opt.knock && opt.dir) knockEnemy(e, opt.dir, opt.knock);
    if (opt.sword) {
      if (st.build.has('frost')) e.chill = C().FROST.chill;
      if (st.build.has('stasis') && inField(st, e)) e.stasis = Math.min(C().STASIS.maxStacks, e.stasis + 1);
    }
    fx(st, { kind: 'spark', x: e.x, y: e.y, ttl: 0.22, t: 0, angle: opt.dir ? Math.atan2(opt.dir.y, opt.dir.x) : st.rng.range(0, Math.PI * 2), crit: e.state === 'recover' });
    text(st, e.x + st.rng.range(-8, 8), e.y - e.r - 6, String(Math.round(dmg)), e.state === 'recover' ? '#ffd166' : '#fff');
    ev(st, 'hit', { crit: e.state === 'recover' });
    if (e.hp <= 0) killEnemy(st, e, opt);
    return dmg;
  }
  function killEnemy(st, e, opt) {
    e.dead = true; e.deathT = 0; st.stats.kills++;
    ev(st, 'kill', { type: e.type });
    if (st.build.has('saving') && inField(st, e) && st.player.special.cd > 0) {
      st.player.special.cd = Math.max(0, st.player.special.cd - C().SAVING.cdPerKill);
      st.stats.savingKills = (st.stats.savingKills || 0) + 1;
      text(st, e.x, e.y - e.r - 22, '감속장 -' + C().SAVING.cdPerKill + '초', '#a9d8ff');
      ev(st, 'saving');
    }
    fx(st, { kind: 'death', x: e.x, y: e.y, r: e.r, ttl: 0.4, t: 0, color: e.def.color });
    if (e.type === 'spore') addZone(st, 'spore', e.x, e.y, e.def.deathCloudR, e.def.deathCloudTtl, e.def.cloudDamage);
    if (st.build.has('frost') && e.chill > 0) {
      const F = C().FROST;
      for (let i = 0; i < F.shards; i++) {
        const a = (i / F.shards) * Math.PI * 2;
        st.projectiles.push({ owner: 'player', kind: 'shard', x: e.x, y: e.y, vx: Math.cos(a) * F.shardSpeed, vy: Math.sin(a) * F.shardSpeed, r: 4, dmg: F.shardDamage * st.build.damageMult, ttl: F.shardTtl });
      }
      text(st, e.x, e.y - 20, '파편!', '#bfefff');
      ev(st, 'shatter');
    }
    if (st.build.has('flare') && st.zones.some(z => z.type === 'fire' && m().dist(z, e) <= z.r + e.r)) {
      const F = C().FLARE;
      fx(st, { kind: 'flare', x: e.x, y: e.y, r: F.radius, ttl: 0.35, t: 0 });
      for (const o of st.enemies) if (!o.dead && o !== e && m().dist(o, e) <= F.radius + o.r) damageEnemy(st, o, F.damage * st.build.damageMult, { dir: m().norm(o.x - e.x, o.y - e.y), knock: 40 });
      text(st, e.x, e.y - 34, '불꽃 파열!', '#ff9f43');
      ev(st, 'explode');
    }
    if (st.markTarget === e) { st.markTarget = null; assignMark(st); }
  }
  function addZone(st, type, x, y, r, ttl, dmg) { st.zones.push({ type, x, y, r, ttl, maxTtl: ttl, dmg, tick: 0, t: 0 }); }

  // ---------- 플레이어 공격 ----------
  function chooseTarget(st) {
    const p = st.player, b = st.build;
    const reach = (e) => b.weapon.form === 'beam' ? m().inBeam(p, Math.atan2(e.y - p.y, e.x - p.x), b.range, b.weapon.width, e, e.r) : m().dist(p, e) <= b.range + e.r;
    if (st.markTarget && !st.markTarget.dead && reach(st.markTarget)) return st.markTarget;
    let best = null, bd = Infinity;
    for (const e of st.enemies) { if (e.dead) continue; const d = m().dist(p, e); if (d < bd && reach(e)) { bd = d; best = e; } }
    return best;
  }
  function performAttack(st, angle, form) {
    const p = st.player, b = st.build, hit = new Set();
    st.stats.attacks++;
    p.swingT = 0; p.swingForm = form; p.swingAngle = angle;
    if (form === 'spin') {
      const S = C().SPIN, r = S.radius * b.rangeMult;
      fx(st, { kind: 'spin', x: p.x, y: p.y, r, ttl: 0.22, t: 0 });
      for (const e of st.enemies) if (!e.dead && m().dist(p, e) <= r + e.r) { hit.add(e); damageEnemy(st, e, b.damage * S.damageMult, { sword: true, knock: S.knock, dir: m().norm(e.x - p.x, e.y - p.y) }); }
    } else if (form === 'beam') {
      const L = b.range, W = b.weapon.width;
      fx(st, { kind: 'beam', x: p.x, y: p.y, angle, len: L, w: W, ttl: 0.18, t: 0 });
      for (const e of st.enemies) if (!e.dead && m().inBeam(p, angle, L, W, e, e.r)) { hit.add(e); damageEnemy(st, e, b.damage, { sword: true, knock: b.weapon.knock, dir: { x: Math.cos(angle), y: Math.sin(angle) } }); }
    } else {
      const R = b.range, half = (b.weapon.arcDeg * Math.PI / 180) / 2;
      fx(st, { kind: 'arc', x: p.x, y: p.y, angle, r: R, half, ttl: 0.16, t: 0 });
      for (const e of st.enemies) if (!e.dead && m().inArc(p, R, angle, half, e, e.r)) { hit.add(e); damageEnemy(st, e, b.damage, { sword: true, knock: b.weapon.knock, dir: m().norm(e.x - p.x, e.y - p.y) }); }
    }
    ev(st, 'swing', { form, hits: hit.size });
    return hit.size;
  }
  function updateAttack(st, dt) {
    const p = st.player, b = st.build;
    if (p.echo) { p.echo.t -= dt; if (p.echo.t <= 0) { performAttack(st, p.echo.angle, p.echo.form); text(st, p.x, p.y - 40, '메아리', '#dcd6ff'); p.echo = null; } }
    p.attackTimer -= dt;
    if (p.attackTimer > 0) return;
    const target = chooseTarget(st);
    if (!target) { p.attackTimer = 0.05; return; }
    p.attackTimer = Math.max(-b.interval * 0.5, p.attackTimer) + b.interval;
    p.attackCount++;
    const angle = Math.atan2(target.y - p.y, target.x - p.x);
    p.face = angle;
    let form = b.weapon.form;
    if (b.has('spin') && p.attackCount % C().SPIN.every === 0) form = 'spin';
    performAttack(st, angle, form);
    if (b.has('echo') && p.attackCount % C().ECHO.every === 0) p.echo = { t: C().ECHO.delay, angle, form };
  }

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
      if (b.has('ember')) { p.dodge.emberIdx = 0; addZone(st, 'fire', p.x, p.y, C().EMBER.radius, C().EMBER.ttl, C().EMBER.damage); }
      ev(st, 'dodge');
    }
    if (p.dodge.active) {
      const useDt = Math.min(dt, Math.max(0, cfg.dodge.duration - p.dodge.t));
      p.dodge.t += dt;
      const spd = cfg.dodge.distance / cfg.dodge.duration;
      p.x += p.dodge.dx * spd * useDt; p.y += p.dodge.dy * spd * useDt;
      if (b.has('ember')) {
        const E = C().EMBER, frac = p.dodge.t / cfg.dodge.duration;
        const idx = Math.floor(frac * E.count);
        if (idx > p.dodge.emberIdx && idx < E.count) { p.dodge.emberIdx = idx; addZone(st, 'fire', p.x, p.y, E.radius, E.ttl, E.damage); }
      }
      if (p.dodge.t >= cfg.dodge.duration) { p.dodge.active = false; p.dodge.cd = cfg.dodge.cooldown * b.dodgeCdMult - (p.dodge.t - cfg.dodge.duration); }
    } else {
      if (p.dodge.cd > 0) p.dodge.cd -= dt;
      p.x += mv.x * cfg.speed * dt; p.y += mv.y * cfg.speed * dt;
    }
    if (input.special && p.special.cd <= 0) {
      if (st.field) endField(st); // 활성 감속장이 있으면 먼저 정상 종료(정지된 칼날 폭발 포함)
      st.field = { x: p.x, y: p.y, r: cfg.special.radius, ttl: cfg.special.duration, maxTtl: cfg.special.duration };
      p.special.cd = b.specialCd;
      ev(st, 'special');
      text(st, p.x, p.y - 50, '감속장', '#a9d8ff');
    }
    p.x = m().clamp(p.x, p.r, a.w - p.r); p.y = m().clamp(p.y, p.r, a.h - p.r);
    updateAttack(st, dt);
  }

  // ---------- 적 AI ----------
  function moveToward(e, tx, ty, speed, dt) {
    const n = m().norm(tx - e.x, ty - e.y);
    e.x += n.x * speed * dt; e.y += n.y * speed * dt;
  }
  function enemySpeedMult(st, e) { return timeFactor(st, e) * (e.chill > 0 ? C().FROST.slow : 1); }

  function updateWolf(st, e, dt) {
    const d = e.def, p = st.player, tf = timeFactor(st, e), sm = enemySpeedMult(st, e);
    const dist = m().dist(e, p);
    switch (e.state) {
      case 'approach':
        moveToward(e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist) { e.state = 'crouch'; e.stateT = 0; e.dashLeft = d.dashes || 1; }
        break;
      case 'crouch': // 방향 추적 중
        e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x);
        e.stateT += dt * tf;
        if (e.stateT >= (e.dashLeft < (d.dashes || 1) ? d.secondCrouch : d.crouch)) { e.state = 'lock'; e.stateT = 0; e.dir = e.aimAngle; ev(st, 'lock'); }
        break;
      case 'lock': // 방향 고정. 절대 바꾸지 않음
        e.stateT += dt * tf;
        if (e.stateT >= d.lock) { e.state = 'dash'; e.stateT = 0; e.hitBy = null; }
        break;
      case 'dash': {
        const remain = Math.max(0, d.dashTime - e.stateT);
        const useDt = Math.min(dt * tf, remain);
        e.stateT += dt * tf;
        const step = d.dashSpeed * useDt;
        const nx = e.x + Math.cos(e.dir) * step, ny = e.y + Math.sin(e.dir) * step;
        // 스윕 판정: 이동 선분이 플레이어 원과 만나면 피해
        if (!e.hitBy && m().segCircle(e.x, e.y, nx, ny, p, p.r + e.r)) { e.hitBy = 'player'; e.biteT = 0; ev(st, 'bite'); damagePlayer(st, d.damage, 'wolf'); }
        e.x = nx; e.y = ny;
        const a = st.arena;
        const hitWall = e.x < e.r || e.x > a.w - e.r || e.y < e.r || e.y > a.h - e.r;
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
        if (dist < d.keepMin) moveToward(e, e.x * 2 - p.x, e.y * 2 - p.y, d.speed * sm, dt);
        else if (dist > d.keepMax) moveToward(e, p.x, p.y, d.speed * sm, dt);
        e.stateT += dt * tf;
        if (dist <= d.keepMax + 40 && e.stateT >= 0.3) { e.state = 'aim'; e.stateT = 0; }
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
          ev(st, 'shoot');
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
        moveToward(e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist) { e.state = 'swell'; e.stateT = 0; }
        break;
      case 'swell':
        e.stateT += dt * tf;
        if (e.stateT >= d.swell) { addZone(st, 'spore', e.x, e.y, d.cloudR, d.cloudTtl, d.cloudDamage); ev(st, 'spore'); e.state = 'recover'; e.stateT = 0; }
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
      if (e.type === 'wolf' || e.type === 'wolf_alpha') updateWolf(st, e, dt);
      else if (e.type === 'archer') updateArcher(st, e, dt);
      else if (e.type === 'spore') updateSpore(st, e, dt);
      // 넉백 속도 감쇠
      if (e.vx || e.vy) { e.x += e.vx * dt; e.y += e.vy * dt; const k = Math.exp(-10 * dt); e.vx *= k; e.vy *= k; if (Math.abs(e.vx) < 1) e.vx = 0; if (Math.abs(e.vy) < 1) e.vy = 0; }
      e.x = m().clamp(e.x, e.r, a.w - e.r); e.y = m().clamp(e.y, e.r, a.h - e.r);
    }
    // 분리: 완전히 겹치지 않게
    const alive = st.enemies.filter(e => !e.dead);
    for (let i = 0; i < alive.length; i++) for (let j = i + 1; j < alive.length; j++) {
      const A = alive[i], B = alive[j];
      if (A.state === 'dash' || B.state === 'dash') continue;
      const dx = B.x - A.x, dy = B.y - A.y, d = Math.hypot(dx, dy), min = A.r + B.r;
      if (d < min && d > 1e-6) { const push = (min - d) / 2 * C().SEPARATION; A.x -= dx / d * push; A.y -= dy / d * push; B.x += dx / d * push; B.y += dy / d * push; }
    }
    st.enemies = st.enemies.filter(e => !e.dead || e.deathT < 0.9);
  }

  // ---------- 투사체/지역/필드 ----------
  function updateProjectiles(st, dt) {
    const p = st.player, a = st.arena;
    for (const pr of st.projectiles) {
      const tf = pr.owner === 'enemy' ? timeFactor(st, pr) : 1;
      const nx = pr.x + pr.vx * tf * dt, ny = pr.y + pr.vy * tf * dt;
      if (pr.owner === 'enemy') {
        if (m().segCircle(pr.x, pr.y, nx, ny, p, p.r + pr.r)) { pr.dead = true; damagePlayer(st, pr.dmg, pr.kind); }
      } else {
        for (const e of st.enemies) if (!e.dead && m().segCircle(pr.x, pr.y, nx, ny, e, e.r + pr.r)) { pr.dead = true; damageEnemy(st, e, pr.dmg, { dir: m().norm(pr.vx, pr.vy), knock: 10 }); break; }
      }
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
      if (z.type === 'fire') {
        z.tick -= dt;
        if (z.tick <= 0) { z.tick = C().EMBER.tick; for (const e of st.enemies) if (!e.dead && m().dist(z, e) <= z.r + e.r) damageEnemy(st, e, z.dmg * st.build.damageMult, {}); }
      }
    }
    if (maxDmg > 0 && p.zoneTick <= 0) { p.zoneTick = C().PLAYER.zoneTick; zoneDamage(st, maxDmg); }
    if (maxDmg === 0 && p.zoneTick < 0) p.zoneTick = 0;
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
      for (const e of st.enemies) if (!e.dead && e.stasis > 0) { const dmg = e.stasis * C().STASIS.damagePerStack * st.build.damageMult; fx(st, { kind: 'stasisburst', x: e.x, y: e.y, r: 34 + e.stasis * 10, ttl: 0.4, t: 0 }); e.stasis = 0; total += damageEnemy(st, e, dmg, {}); }
      if (total > 0) { text(st, f.x, f.y - f.r - 26, '정지된 칼날 폭발 ' + Math.round(total), '#cfeaff'); ev(st, 'explode'); }
    }
    fx(st, { kind: 'fieldend', x: f.x, y: f.y, r: f.r, ttl: 0.35, t: 0 });
    st.field = null;
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
    for (const s of st.pending) { s.t -= dt; if (s.t <= 0) spawnEnemy(st, s.type, s.x, s.y); }
    st.pending = st.pending.filter(s => s.t > 0);
    const alive = st.enemies.filter(e => !e.dead).length;
    if (st.waveIndex < st.waves.length - 1 && alive === 0 && st.pending.length === 0) {
      st.waveTimer -= dt;
      if (st.waveTimer <= 0) {
        st.waveIndex++; st.waveTimer = C().WAVE_DELAY;
        queueWave(st, st.waves[st.waveIndex]);
        if (st.waveIndex === C().CHEST.wave && !st.chestSpawned) {
          st.chestSpawned = true; const pos = edgePos(st); st.chest = { x: pos.x, y: pos.y, r: C().CHEST.r, opened: false, t: 0 };
        }
      }
    }
    st.spawnedAll = st.waveIndex >= st.waves.length - 1 && st.pending.length === 0;
  }
  function checkObjective(st) {
    if (st.status !== 'running') return;
    const alive = st.enemies.filter(e => !e.dead);
    if (st.objective === 'elite') {
      if (st.enemies.some(e => e.elite && e.dead)) { st.status = 'won'; ev(st, 'win'); }
    } else if (st.objective === 'clear' && st.spawnedAll && alive.length === 0) { st.status = 'won'; ev(st, 'win'); }
  }
  function updateEffects(st, dt) {
    for (const f of st.effects) { f.t += dt; if (f.kind === 'text') f.y -= 30 * dt; }
    st.effects = st.effects.filter(f => f.t < f.ttl);
  }

  function step(st, input, dt) {
    if (st.status !== 'running') { updateEffects(st, dt); for (const e of st.enemies) if (e.dead) e.deathT += dt; return; }
    st.t += dt; st.stats.elapsed += dt;
    updatePlayer(st, input || {}, dt);
    updateEnemies(st, dt);
    updateProjectiles(st, dt);
    updateZones(st, dt);
    updateChest(st, dt);
    updateWaves(st, dt);
    updateEffects(st, dt);
    checkObjective(st);
  }

  return { create, step, damagePlayer, damageEnemy, spawnEnemy, performAttack, chooseTarget, inField, addZone, queueWave, endField };
})();
