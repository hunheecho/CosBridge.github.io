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
      stats: { kills: 0, damageTaken: 0, perfectDodges: 0, chestGold: 0, elapsed: 0, attacks: 0 },
      spawnedAll: false,
    };
    return st;
  }

  // ---------- 이벤트/이펙트 ----------
  function ev(st, name, data) { st.events.push(Object.assign({ name }, data || {})); }
  function fx(st, e) { st.effects.push(e); }
  function text(st, x, y, txt, color) { fx(st, { kind: 'text', x, y, text: txt, color: color || '#fff', ttl: 0.8, t: 0 }); }

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
    if (wx !== x1 || wy !== y1) { const tx = dx !== 0 ? (wx - x0) / dx : 1, ty = dy !== 0 ? (wy - y0) / dy : 1; t = Math.max(0, Math.min(t, tx, ty)); hit = 'wall'; }
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
  // 잔불: 장애물 안쪽(바닥이 아닌 곳)이면 그 조각은 생략한다(플레이어 위치는 항상 유효하므로 보통 발생하지 않음)
  function addFireAt(st, x, y) {
    const E = C().EMBER;
    if (!validPos(st, x, y, 0)) return false;
    addZone(st, 'fire', x, y, E.radius, E.ttl, E.damage); return true;
  }

  // ---------- 플레이어 공격 ----------
  function chooseTarget(st) {
    const p = st.player, b = st.build;
    const reach = (e) => {
      if (losBlocked(st, p, e)) return false; // 장애물에 가려진 대상은 공격 대상이 아니다
      if (b.weapon.form === 'beam') { const ang = Math.atan2(e.y - p.y, e.x - p.x); return m().inBeam(p, ang, beamLength(st, p, ang, b.range), b.weapon.width, e, e.r); }
      return m().dist(p, e) <= b.range + e.r;
    };
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
      for (const e of st.enemies) if (!e.dead && m().dist(p, e) <= r + e.r && !losBlocked(st, p, e)) { hit.add(e); damageEnemy(st, e, b.damage * S.damageMult, { sword: true, knock: S.knock, dir: m().norm(e.x - p.x, e.y - p.y) }); }
    } else if (form === 'beam') {
      const L = beamLength(st, p, angle, b.range), W = b.weapon.width; // 검광은 장애물에서 멈춘다
      fx(st, { kind: 'beam', x: p.x, y: p.y, angle, len: L, w: W, ttl: 0.18, t: 0 });
      for (const e of st.enemies) if (!e.dead && m().inBeam(p, angle, L, W, e, e.r) && !losBlocked(st, p, e)) { hit.add(e); damageEnemy(st, e, b.damage, { sword: true, knock: b.weapon.knock, dir: { x: Math.cos(angle), y: Math.sin(angle) } }); }
    } else {
      const R = b.range, half = (b.weapon.arcDeg * Math.PI / 180) / 2;
      fx(st, { kind: 'arc', x: p.x, y: p.y, angle, r: R, half, ttl: 0.16, t: 0 });
      for (const e of st.enemies) if (!e.dead && m().inArc(p, R, angle, half, e, e.r) && !losBlocked(st, p, e)) { hit.add(e); damageEnemy(st, e, b.damage, { sword: true, knock: b.weapon.knock, dir: m().norm(e.x - p.x, e.y - p.y) }); }
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
      if (b.has('ember')) { p.dodge.emberIdx = 0; addFireAt(st, p.x, p.y); }
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
      moveSwept(st, p, mv.x * cfg.speed * dt, mv.y * cfg.speed * dt, true); // 표면을 따라 미끄러진다
    }
    if (input.special && p.special.cd <= 0) {
      if (st.field) endField(st); // 활성 감속장이 있으면 먼저 정상 종료(정지된 칼날 폭발 포함)
      st.field = { x: p.x, y: p.y, r: cfg.special.radius, ttl: cfg.special.duration, maxTtl: cfg.special.duration };
      p.special.cd = b.specialCd;
      ev(st, 'special');
      text(st, p.x, p.y - 50, '감속장', '#a9d8ff');
    }
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
  function enemySpeedMult(st, e) { return timeFactor(st, e) * (e.chill > 0 ? C().FROST.slow : 1); }

  function updateWolf(st, e, dt) {
    const d = e.def, p = st.player, tf = timeFactor(st, e), sm = enemySpeedMult(st, e);
    const dist = m().dist(e, p);
    switch (e.state) {
      case 'approach':
        approach(st, e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist && !losBlocked(st, e, p)) { e.state = 'crouch'; e.stateT = 0; e.dashLeft = d.dashes || 1; }
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
        approach(st, e, p.x, p.y, d.speed * sm, dt);
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
      if (e.vx || e.vy) { moveSwept(st, e, e.vx * dt, e.vy * dt); const k = Math.exp(-10 * dt); e.vx *= k; e.vy *= k; if (Math.abs(e.vx) < 1) e.vx = 0; if (Math.abs(e.vy) < 1) e.vy = 0; }
      pushOut(st, e);
    }
    // 분리: 완전히 겹치지 않게
    const alive = st.enemies.filter(e => !e.dead);
    for (let i = 0; i < alive.length; i++) for (let j = i + 1; j < alive.length; j++) {
      const A = alive[i], B = alive[j];
      if (A.state === 'dash' || B.state === 'dash') continue;
      const dx = B.x - A.x, dy = B.y - A.y, d = Math.hypot(dx, dy), min = A.r + B.r;
      if (d < min && d > 1e-6) { const push = (min - d) / 2 * C().SEPARATION; A.x -= dx / d * push; A.y -= dy / d * push; B.x += dx / d * push; B.y += dy / d * push; pushOut(st, A); pushOut(st, B); }
    }
    st.enemies = st.enemies.filter(e => !e.dead || e.deathT < 0.9);
  }

  // ---------- 투사체/지역/필드 ----------
  function updateProjectiles(st, dt) {
    const p = st.player, a = st.arena;
    for (const pr of st.projectiles) {
      const tf = pr.owner === 'enemy' ? timeFactor(st, pr) : 1;
      const nx = pr.x + pr.vx * tf * dt, ny = pr.y + pr.vy * tf * dt;
      const obs = m().sweepCircle(pr.x, pr.y, nx, ny, pr.r, st.obstacles); const tObs = obs ? obs.t : Infinity;
      if (pr.owner === 'enemy') {
        const tp = m().segCircleT(pr.x, pr.y, nx, ny, p, p.r + pr.r);
        if (tp != null && tp <= tObs) { pr.dead = true; damagePlayer(st, pr.dmg, pr.kind); }
      } else {
        let best = null, bt = Infinity;
        for (const e of st.enemies) { if (e.dead) continue; const t = m().segCircleT(pr.x, pr.y, nx, ny, e, e.r + pr.r); if (t != null && t < bt) { bt = t; best = e; } }
        if (best && bt <= tObs) { pr.dead = true; damageEnemy(st, best, pr.dmg, { dir: m().norm(pr.vx, pr.vy), knock: 10 }); }
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

  return { create, step, damagePlayer, damageEnemy, spawnEnemy, performAttack, chooseTarget, inField, addZone, queueWave, endField, pushOut, moveSwept, losBlocked, validPos, nearestValidPos, beamLength, steerDir };
})();
