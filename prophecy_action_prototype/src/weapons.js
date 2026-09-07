// 무기 엔진(전투 쪽): 장착 무기 최대 3개가 각자 주기로 자동 공격한다. 피해 출처(무기·레벨·직접/추가)를 추적해 공통 효과가 정확히 한 번씩 적용되게 한다.
// 판정 범주: direct(장애물 가림) / projectile(장애물 충돌) / ground(바닥 범위)
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Weapons = (function () {
  const m = () => PA.m;
  const K = () => PA.Combat;
  const TAU = Math.PI * 2;

  function init(st) {
    const list = st.build.weapons.map((s, i) => ({ stats: s, id: s.id, timer: 0.25 + i * 0.2, count: 0, orbit: 0, launchT: 0, lastHit: new Map(), burst: null }));
    st.mines = st.mines || []; st.delayed = st.delayed || [];
    return list;
  }
  // 전투 중 성장(레벨업 선택) 반영: 타이머·상태 유지, 수치만 갱신, 새 무기 추가
  function refresh(st) {
    const old = st.weapons || [];
    st.weapons = st.build.weapons.map((s, i) => { const prev = old.find(w => w.id === s.id); return prev ? Object.assign(prev, { stats: s }) : { stats: s, id: s.id, timer: 0.3, count: 0, orbit: 0, launchT: 0, lastHit: new Map(), burst: null }; });
  }

  // ---------- 공통 헬퍼 ----------
  function src(w, opt) { return Object.assign({ weapon: w.stats, weaponId: w.id, level: w.stats.level, direct: true }, opt || {}); }
  function alive(st) { return st.enemies.filter(e => !e.dead && !e.hidden); } // 지하(hidden) 적은 직접·투사체 대상이 아니다
  function reachable(st, from, e) { return !K().losBlocked(st, from, e); }
  // 대상: 표식 우선(사거리 안·가림 없음) → 가장 가까운 가림 없는 적
  function pickTarget(st, w, range, needLos) {
    const p = st.player, mk = st.markTarget;
    const ok = (e) => !e.dead && !e.hidden && m().dist(p, e) <= range + e.r && (!needLos || reachable(st, p, e));
    if (mk && ok(mk)) return mk;
    let best = null, bd = Infinity;
    for (const e of st.enemies) { if (!ok(e)) continue; const d = m().dist(p, e); if (d < bd) { bd = d; best = e; } }
    return best;
  }
  function dmgTo(st, e, w, mult, opt) { if (st.metrics && st.metrics.hits) st.metrics.hits[w.id] = (st.metrics.hits[w.id] || 0) + 1; return K().damageEnemy(st, e, w.stats.damage * mult, Object.assign({ src: src(w, opt) }, opt || {})); } // 명중 횟수(무기별): 실제 명중 빈도 측정
  // 원형 범위 직접 공격(가림 적용)
  function hitCircle(st, w, cx, cy, r, mult, opt) {
    let n = 0;
    for (const e of alive(st)) if (m().dist({ x: cx, y: cy }, e) <= r + e.r && (opt && opt.ground || reachable(st, { x: cx, y: cy }, e))) { dmgTo(st, e, w, mult, Object.assign({ dir: m().norm(e.x - cx, e.y - cy), from: { x: cx, y: cy } }, opt)); n++; }
    return n;
  }
  function hitArc(st, w, from, angle, R, half, mult, opt) {
    let n = 0;
    for (const e of alive(st)) if (m().inArc(from, R, angle, half, e, e.r) && reachable(st, from, e)) { dmgTo(st, e, w, mult, Object.assign({ dir: m().norm(e.x - from.x, e.y - from.y), knock: w.stats.knock, from }, opt)); n++; }
    return n;
  }
  function hitBeam(st, w, from, angle, L, W, mult, opt) {
    const list = [];
    for (const e of alive(st)) if (m().inBeam(from, angle, L, W, e, e.r) && reachable(st, from, e)) list.push(e);
    list.sort((a, b) => m().dist(from, a) - m().dist(from, b));
    // 위치·방향 선정용 후보 규칙(데이터, 기본 없음): sweetFrom = 사거리의 이 비율 안쪽은 sweetMult 피해(가까우면 약함), maxTargets = 한 번에 관통하는 최대 수
    const s = w.stats, hit = []; let n = 0;
    for (const e of list) { if (s.maxTargets && n >= s.maxTargets) break; let mm = mult; if (s.sweetFrom && m().dist(from, e) < L * s.sweetFrom) mm *= (s.sweetMult != null ? s.sweetMult : 0.5); dmgTo(st, e, w, mm, Object.assign({ dir: { x: Math.cos(angle), y: Math.sin(angle) }, knock: w.stats.knock, from }, opt)); hit.push(e); n++; }
    return hit;
  }
  function proj(st, w, o) { // 아군 투사체 생성
    const pr = Object.assign({ owner: 'player', weapon: w, r: 4, ttl: 2, hits: new Set(), dmgMult: 1, opt: {} }, o);
    st.projectiles.push(pr); return pr;
  }
  function later(st, t, fn) { st.delayed.push({ t, fn }); }

  // ---------- 무기별 발사 ----------
  const FIRE = {
    arc(st, w, target, echoed) {
      const p = st.player, s = w.stats, ang = Math.atan2(target.y - p.y, target.x - p.x), half = s.arcDeg * Math.PI / 360;
      p.face = ang; p.swingT = 0; p.swingForm = 'arc'; p.swingAngle = ang;
      K().fx(st, { kind: 'arc', x: p.x, y: p.y, angle: ang, r: s.range, half, ttl: 0.16, t: 0 });
      hitArc(st, w, p, ang, s.range, half, 1, {});
      if (s.mods.includes('cross') && w.count % 3 === 0) { const a2 = ang + Math.PI; K().fx(st, { kind: 'arc', x: p.x, y: p.y, angle: a2, r: s.range, half, ttl: 0.16, t: 0 }); hitArc(st, w, p, a2, s.range, half, 1, {}); }
      if (s.mods.includes('crescent')) { const sx = p.x + Math.cos(ang) * s.range * 0.8, sy = p.y + Math.sin(ang) * s.range * 0.8; proj(st, w, { kind: 'crescent', x: sx, y: sy, vx: Math.cos(ang) * 420, vy: Math.sin(ang) * 420, r: 16, ttl: 120 / 420, pierce: true, dmgMult: 0.6, angle: ang, opt: { direct: false } }); }
      if (s.mods.includes('scar')) { const cx = p.x, cy = p.y; later(st, 0.5, () => { K().fx(st, { kind: 'scar', x: cx, y: cy, angle: ang, r: s.range, half, ttl: 0.25, t: 0 }); hitArc(st, w, { x: cx, y: cy }, ang, s.range, half, 0.5, { direct: false }); }); }
      K().ev(st, 'swing', { form: 'arc' });
    },
    beam(st, w, target, echoed) {
      const p = st.player, s = w.stats, ang = Math.atan2(target.y - p.y, target.x - p.x), L = K().beamLength(st, p, ang, s.range), W = s.width;
      p.face = ang; p.swingT = 0; p.swingForm = 'beam'; p.swingAngle = ang;
      K().fx(st, { kind: 'beam', x: p.x, y: p.y, angle: ang, len: L, w: W, ttl: 0.18, t: 0 });
      const hit = hitBeam(st, w, p, ang, L, W, 1, {});
      if (s.mods.includes('brand')) for (const e of hit) { e.brand = (e.brand || 0) + 1; if (e.brand >= 4) { e.brand = 0; K().fx(st, { kind: 'burst', x: e.x, y: e.y, r: 60, ttl: 0.3, t: 0, color: '#ffd166' }); K().text(st, e.x, e.y - e.r - 30, '표식 폭발!', '#ffd166'); hitCircle(st, w, e.x, e.y, 60, 1.5, { direct: false }); } }
      if (s.mods.includes('split') && hit.length) { const h = hit[0]; for (const da of [-0.6, 0.6]) proj(st, w, { kind: 'shard', x: h.x, y: h.y, vx: Math.cos(ang + da) * 340, vy: Math.sin(ang + da) * 340, r: 4, ttl: 0.5, dmgMult: 0.4, opt: { direct: false } }); }
      if (s.mods.includes('returning') && !echoed) { const fx0 = { x: p.x, y: p.y }; later(st, 0.35, () => { const ex = fx0.x + Math.cos(ang) * L, ey = fx0.y + Math.sin(ang) * L; K().fx(st, { kind: 'beam', x: ex, y: ey, angle: ang + Math.PI, len: L, w: W, ttl: 0.18, t: 0 }); hitBeam(st, w, { x: ex, y: ey }, ang + Math.PI, L, W, 1, { noMods: true }); }); }
      K().ev(st, 'swing', { form: 'beam' });
    },
    melee(st, w, target, echoed) { // 쌍검: 3연속(0.09초 간격) 짧은 부채꼴
      const s = w.stats, p = st.player;
      const one = (i) => { const t = target.dead ? pickTarget(st, w, s.range, true) : target; if (!t) return; const ang = Math.atan2(t.y - p.y, t.x - p.x); p.face = ang; p.swingT = 0; p.swingForm = 'arc'; p.swingAngle = ang;
        const half = s.arcDeg * Math.PI / 360; K().fx(st, { kind: 'dagger', x: p.x, y: p.y, angle: ang, r: s.range, half, ttl: 0.12, t: 0, side: i });
        if (i === s.hits - 1 && s.mods.includes('flank')) { for (const da of [Math.PI / 2, -Math.PI / 2]) { K().fx(st, { kind: 'arc', x: p.x, y: p.y, angle: ang + da, r: s.range * 1.3, half: 0.9, ttl: 0.14, t: 0 }); hitArc(st, w, p, ang + da, s.range * 1.3, 0.9, 1, {}); } }
        hitArc(st, w, p, ang, s.range, half, 1, s.mods.includes('bleed') ? { bleed: 2.0 } : {}); };
      one(0); for (let i = 1; i < s.hits; i++) later(st, s.hitGap * i, () => one(i));
      K().ev(st, 'swing', { form: 'melee' });
    },
    homing(st, w, target, echoed) {
      const s = w.stats, p = st.player, ang = Math.atan2(target.y - p.y, target.x - p.x);
      const angles = s.mods.includes('spread') ? [ang - 0.35, ang, ang + 0.35] : [ang];
      for (const a of angles) proj(st, w, { kind: 'arrow_h', x: p.x, y: p.y, vx: Math.cos(a) * s.speed, vy: Math.sin(a) * s.speed, r: 5, ttl: (s.range / s.speed) * 1.4, target, turn: s.turn, speed: s.speed, pierce: s.mods.includes('pierce'), ricochet: s.mods.includes('ricochet') ? 1 : 0, angle: a });
      p.face = ang; K().ev(st, 'shoot');
    },
    heavy(st, w, target, echoed) { // 망치: 사거리 안 대상 위치에 원형 타격
      const s = w.stats, p = st.player, d = m().dist(p, target), ang = Math.atan2(target.y - p.y, target.x - p.x);
      const ix = p.x + Math.cos(ang) * Math.min(d, s.range), iy = p.y + Math.sin(ang) * Math.min(d, s.range);
      p.face = ang; p.swingT = 0; p.swingForm = 'heavy'; p.swingAngle = ang;
      if (s.mods.includes('pull')) for (const e of alive(st)) if (!e.boss && !e.airborne && m().dist(e, { x: ix, y: iy }) <= 90 + e.r) { const n = m().norm(ix - e.x, iy - e.y); K().moveSwept(st, e, n.x * 30, n.y * 30); }
      K().fx(st, { kind: 'impact', x: ix, y: iy, r: s.radius, ttl: 0.3, t: 0 });
      hitCircle(st, w, ix, iy, s.radius, 1, { knock: s.knock });
      if (s.mods.includes('shockwave')) { K().fx(st, { kind: 'beam', x: ix, y: iy, angle: ang, len: 160, w: 50, ttl: 0.2, t: 0 }); hitBeam(st, w, { x: ix, y: iy }, ang, 160, 50, 0.6, { direct: false }); }
      if (s.mods.includes('aftershock')) later(st, 0.6, () => { K().fx(st, { kind: 'impact', x: ix, y: iy, r: s.radius, ttl: 0.3, t: 0, after: true }); hitCircle(st, w, ix, iy, s.radius, 0.5, { direct: false, ground: true }); });
      K().ev(st, 'boss_land');
    },
    chain(st, w, target, echoed) {
      const s = w.stats, p = st.player, visited = new Set(), pts = [{ x: p.x, y: p.y }];
      const zap = (e, mult) => { const from = pts[pts.length - 1]; visited.add(e.id); pts.push({ x: e.x, y: e.y }); dmgTo(st, e, w, mult, { knock: 0, from }); if (s.mods.includes('conduct')) e.conduct = 2.0; };
      const next = (from) => { let best = null, bd = Infinity; for (const e of alive(st)) { if (visited.has(e.id)) continue; const d = m().dist(from, e); if (d <= s.hop + e.r && d < bd && reachable(st, from, e)) { bd = d; best = e; } } return best; };
      zap(target, 1);
      const first = target;
      if (s.mods.includes('fork')) { const branches = []; for (let k = 0; k < 2; k++) { const n = next(first); if (n) { zap(n, 1); branches.push(n); } } for (const b of branches) { let cur = b; for (let h = 1; h < Math.ceil(s.hops / 2); h++) { const n = next(cur); if (!n) break; zap(n, 1); cur = n; } } }
      else { let cur = first; for (let h = 1; h < s.hops; h++) { const n = next(cur); if (!n) break; zap(n, 1); cur = n; } }
      if (s.mods.includes('loop') && !first.dead && visited.size > 1) { pts.push({ x: first.x, y: first.y }); dmgTo(st, first, w, 1, { knock: 0, loop: true }); } // 명시적 예외: 최초 대상으로 한 번 복귀
      K().fx(st, { kind: 'chain', pts, ttl: 0.22, t: 0 });
      K().ev(st, 'shoot');
    },
    bolt(st, w, target, echoed) {
      const s = w.stats, p = st.player, ang = Math.atan2(target.y - p.y, target.x - p.x);
      const angles = s.mods.includes('fan') ? [ang - 0.44, ang, ang + 0.44] : [ang];
      for (const a of angles) proj(st, w, { kind: 'bolt', x: p.x, y: p.y, vx: Math.cos(a) * s.speed, vy: Math.sin(a) * s.speed, r: 5, ttl: s.range / s.speed, chill: s.chill, angle: a, shatter: s.mods.includes('shatter'), ground: s.mods.includes('ground') });
      K().ev(st, 'shoot');
    },
    ember(st, w, target, echoed) { // 불씨: 대상 위치(±20)에 불길. 바닥 효과
      const s = w.stats, tx = target.x + st.rng.range(-20, 20), ty = target.y + st.rng.range(-20, 20);
      const zones = s.mods.includes('scatter') ? [[tx, ty, s.radius * 0.7], [tx + 40, ty - 30, s.radius * 0.7], [tx - 40, ty + 30, s.radius * 0.7]] : [[tx, ty, s.radius]];
      if (s.mods.includes('trail')) { const ang = Math.atan2(ty - st.player.y, tx - st.player.x); for (let i = 1; i <= 2; i++) zones.push([tx - Math.cos(ang) * 40 * i, ty - Math.sin(ang) * 40 * i, s.radius * 0.8]); }
      K().fx(st, { kind: 'emberthrow', x0: st.player.x, y0: st.player.y, x: tx, y: ty, ttl: 0.3, t: 0 });
      later(st, 0.3, () => { for (const [zx, zy, zr] of zones) { const pos = K().nearestValidPos(st, zx, zy, 0, 60); if (!pos) continue; const z = K().addZone(st, 'fire', pos.x, pos.y, zr, s.ttl * st.build.durationMult, s.damage); z.weapon = w; z.extended = 0; } });
      K().ev(st, 'shoot');
    },
    mine(st, w) {
      const s = w.stats, p = st.player;
      if (st.mines.filter(mn => mn.weapon === w).length >= s.max) return false;
      const pos = K().nearestValidPos(st, p.x, p.y, 8, 40); if (!pos) return false;
      st.mines.push({ weapon: w, x: pos.x, y: pos.y, r: s.trigger, arm: s.arm, t: 0, dead: false });
      return true;
    },
  };

  // ---------- 갱신 ----------
  function update(st, dt) {
    const p = st.player, b = st.build;
    // 지연 효과
    if (st.delayed.length) { const keep = []; for (const d of st.delayed) { d.t -= dt; if (d.t <= 0) { try { d.fn(); } catch (e) { console.error(e); } } else keep.push(d); } st.delayed = keep; }
    for (const w of st.weapons) {
      const s = w.stats;
      if (s.kind === 'orbit') { updateOrbit(st, w, dt); continue; }
      if (w.echo) { w.echo.t -= dt; if (w.echo.t <= 0) { const e = w.echo; w.echo = null; if (!e.target.dead) FIRE[s.kind](st, w, e.target, true); K().text(st, p.x, p.y - 40, '메아리', '#dcd6ff'); } }
      w.timer -= dt;
      if (w.timer > 0) continue;
      if (s.kind === 'mine') { if (FIRE.mine(st, w)) { w.timer = Math.max(-s.interval * 0.5, w.timer) + s.interval; w.count++; } else w.timer = 0.2; continue; }
      const range = s.kind === 'melee' ? s.range : s.range;
      const target = s.kind === 'ember' ? pickEmberTarget(st, w) : pickTarget(st, w, range, s.kind !== 'homing' && s.kind !== 'bolt' ? true : true);
      if (!target) { w.timer = 0.05; continue; }
      w.timer = Math.max(-s.interval * 0.5, w.timer) + s.interval;
      w.count++;
      FIRE[s.kind](st, w, target, false);
      if (b.has('echo') && w.count % PA.GROWTH.COMMON_VALUES.echoEvery === 0) w.echo = { t: PA.GROWTH.COMMON_VALUES.echoDelay, target };
    }
    updateMines(st, dt);
  }
  function pickEmberTarget(st, w) { const p = st.player, list = alive(st).filter(e => m().dist(p, e) <= w.stats.range); return list.length ? st.rng.pick(list) : null; }

  function updateOrbit(st, w, dt) {
    const s = w.stats, p = st.player;
    w.orbit += s.angular * dt;
    // v0.8: 칼날 판정은 '중심 근처(반지름의 35%)부터 칼날 끝까지의 살(spoke)'이다. 이전 판정(칼날 끝 원 16)은 궤도 안쪽에 사각이 있어 붙은 적을 놓쳤다.
    // 이중 궤도 개조는 안쪽 궤도 대신 같은 궤도에 칼날 +1(안쪽은 살이 덮으므로 안쪽 궤도가 무의미)
    const count = s.count + (s.mods.includes('dual') ? 1 : 0), R = s.radius, inner = R * PA.BLADE_SPOKE.innerFrac;
    w.bladePos = [];
    for (let i = 0; i < count; i++) { const a = w.orbit + i * TAU / count; w.bladePos.push({ x: p.x + Math.cos(a) * R, y: p.y + Math.sin(a) * R, a, ix: p.x + Math.cos(a) * inner, iy: p.y + Math.sin(a) * inner }); }
    for (const bp of w.bladePos) for (const e of alive(st)) {
      if (m().distSeg ? m().distSeg(e, bp.ix, bp.iy, bp.x, bp.y) > PA.BLADE_SPOKE.hitR + e.r : m().dist(bp, e) > 16 + e.r) continue;
      const last = w.lastHit.get(e.id) || -9; if (st.t - last < s.hitGap) continue;
      if (!reachable(st, p, e)) continue;
      w.lastHit.set(e.id, st.t); w.count++;
      dmgTo(st, e, w, 1, Object.assign({ dir: m().norm(e.x - p.x, e.y - p.y), knock: s.knock, from: bp }, s.mods.includes('serrated') ? { bleed: 1.5 } : {}));
      if (st.build.has('echo') && w.count % PA.GROWTH.COMMON_VALUES.echoEvery === 0) later(st, PA.GROWTH.COMMON_VALUES.echoDelay, () => { if (!e.dead) dmgTo(st, e, w, 1, { direct: true, noEcho: true }); });
    }
    if (s.mods.includes('launch')) { w.launchT += dt; if (w.launchT >= 3) { const t = pickTarget(st, w, 240, true); if (t) { w.launchT = 0; proj(st, w, { kind: 'blade', x: p.x, y: p.y, vx: 0, vy: 0, r: 12, ttl: 3, boomerang: { tx: t.x, ty: t.y, phase: 0, speed: 520 }, pierce: true, dmgMult: 1.2 }); } } }
  }
  function updateMines(st, dt) {
    const p = st.player;
    for (const mn of st.mines) {
      if (mn.dead) continue;
      mn.t += dt; if (mn.arm > 0) { mn.arm -= dt; continue; }
      const s = mn.weapon.stats;
      if (s.mods.includes('lure')) for (const e of alive(st)) if (!e.boss && !e.airborne && m().dist(e, mn) <= 70 + e.r && m().dist(e, mn) > mn.r) { const n = m().norm(mn.x - e.x, mn.y - e.y); K().moveSwept(st, e, n.x * 40 * dt, n.y * 40 * dt); }
      if (alive(st).some(e => !e.airborne && m().dist(e, mn) <= mn.r + e.r)) explodeMine(st, mn);
    }
    st.mines = st.mines.filter(mn => !mn.dead);
  }
  function explodeMine(st, mn) {
    if (mn.dead) return; mn.dead = true; // 같은 지뢰는 한 번만
    const w = mn.weapon, s = w.stats;
    K().fx(st, { kind: 'mineburst', x: mn.x, y: mn.y, r: s.radius, ttl: 0.35, t: 0 });
    hitCircle(st, w, mn.x, mn.y, s.radius, 1, Object.assign({ ground: true, knock: 30 }, s.mods.includes('frosttrap') ? { chill: 2.0 } : {}));
    if (s.mods.includes('chain')) for (const o of st.mines) if (!o.dead && o !== mn && m().dist(o, mn) <= 90) { const oo = o; later(st, 0.15, () => explodeMine(st, oo)); }
    K().ev(st, 'explode');
  }

  // ---------- 투사체 적중(combat.updateProjectiles에서 호출) ----------
  // 반환: true면 투사체 소멸
  function onProjectileHit(st, pr, e) {
    const w = pr.weapon;
    if (pr.hits.has(e.id)) return false;
    pr.hits.add(e.id);
    const opt = Object.assign({ dir: m().norm(pr.vx, pr.vy), knock: 10, from: { x: pr.x, y: pr.y } }, pr.opt || {});
    if (pr.chill) opt.chill = pr.chill;
    if (pr.kind === 'shard_common') { K().damageEnemy(st, e, pr.dmg, { dir: opt.dir, knock: 10, src: { extra: true, direct: false } }); return true; }
    dmgTo(st, e, w, pr.dmgMult, opt);
    if (pr.kind === 'bolt') {
      if (pr.shatter) for (let i = 0; i < 3; i++) { const a = Math.atan2(pr.vy, pr.vx) + (i - 1) * 0.7; proj(st, w, { kind: 'shard', x: e.x, y: e.y, vx: Math.cos(a) * 300, vy: Math.sin(a) * 300, r: 3, ttl: 0.4, dmgMult: 0.4, opt: { direct: false }, hits: new Set([e.id]) }); }
      if (pr.ground) { const z = K().addZone(st, 'coldground', e.x, e.y, 40, 2.0 * st.build.durationMult, 0); z.weapon = w; }
      return true;
    }
    if (pr.kind === 'arrow_h' && pr.ricochet > 0) { pr.ricochet--; let best = null, bd = Infinity; for (const o of alive(st)) { if (o === e || pr.hits.has(o.id)) continue; const d = m().dist(e, o); if (d <= 160 && d < bd) { bd = d; best = o; } } if (best) { pr.target = best; pr.dmgMult *= 0.7; const a = Math.atan2(best.y - pr.y, best.x - pr.x); pr.vx = Math.cos(a) * pr.speed; pr.vy = Math.sin(a) * pr.speed; return false; } }
    return !pr.pierce;
  }
  // 투사체 이동 보정(추적·부메랑)
  function steerProjectile(st, pr, dt) {
    if (pr.target && pr.turn) {
      if (pr.target.dead) { pr.target = null; return; }
      const want = Math.atan2(pr.target.y - pr.y, pr.target.x - pr.x), cur = Math.atan2(pr.vy, pr.vx), d = m().angDiff(cur, want);
      const a = cur + Math.max(-pr.turn * dt, Math.min(pr.turn * dt, d)); pr.vx = Math.cos(a) * pr.speed; pr.vy = Math.sin(a) * pr.speed;
    }
    if (pr.boomerang) {
      const bm = pr.boomerang, p = st.player, goal = bm.phase === 0 ? bm : p;
      const a = Math.atan2(goal.y - pr.y, goal.x - pr.x); pr.vx = Math.cos(a) * bm.speed; pr.vy = Math.sin(a) * bm.speed;
      if (m().dist(pr, bm.phase === 0 ? { x: bm.tx, y: bm.ty } : p) < 18) { if (bm.phase === 0) { bm.phase = 1; pr.hits = new Set(); } else pr.dead = true; }
    }
  }

  // ---------- 적중·처치 훅(combat.damageEnemy / killEnemy에서 호출) ----------
  function onHit(st, e, opt, dmg) {
    const sr = opt.src || {}, b = st.build;
    if (sr.direct !== false && sr.weaponId) {
      // 전도 표식: 번개 외 무기의 직접 공격이 표식 적을 치면 작은 전기 폭발(구체 피해의 40%)
      if (e.conduct > 0 && sr.weaponId !== 'orb' && !opt.noConduct) { const orb = st.weapons.find(w => w.id === 'orb'); if (orb) { e.conduct = 0; K().fx(st, { kind: 'burst', x: e.x, y: e.y, r: 50, ttl: 0.25, t: 0, color: '#bfe8ff' }); for (const o of alive(st)) if (m().dist(o, e) <= 50 + o.r) K().damageEnemy(st, o, orb.stats.damage * 0.4, { src: src(orb, { direct: false }), noConduct: true }); } }
      // 무기 공명(보스 보상): 서로 다른 무기 3종이 4초 안에 같은 적 → 폭발(적당 6초 간격)
      if (b.bossRewards.includes('resonance')) { e.resonance = e.resonance || {}; e.resonance[sr.weaponId] = st.t; const recent = Object.keys(e.resonance).filter(k => st.t - e.resonance[k] <= 4); if (recent.length >= 3 && (e.resonanceT == null || st.t - e.resonanceT >= 6)) { e.resonanceT = st.t; e.resonance = {}; K().fx(st, { kind: 'burst', x: e.x, y: e.y, r: 70, ttl: 0.35, t: 0, color: '#ffe066' }); K().text(st, e.x, e.y - e.r - 34, '무기 공명!', '#ffe066'); for (const o of alive(st)) if (m().dist(o, e) <= 70 + o.r) K().damageEnemy(st, o, 40 * b.masteryMult, { src: { extra: true, direct: false, tag: 'reward:resonance' }, noConduct: true }); } }
    }
  }
  function onKill(st, e, opt) {
    const sr = (opt && opt.src) || {}, b = st.build;
    // 추격 칼날(쌍검)
    if (sr.weaponId === 'daggers') { const w = st.weapons.find(x => x.id === 'daggers'); if (w && w.stats.mods.includes('pursuit')) { let best = null, bd = Infinity; for (const o of alive(st)) { const d = m().dist(e, o); if (d <= 200 && d < bd) { bd = d; best = o; } } if (best) { const a = Math.atan2(best.y - e.y, best.x - e.x); proj(st, w, { kind: 'blade', x: e.x, y: e.y, vx: Math.cos(a) * 480, vy: Math.sin(a) * 480, r: 6, ttl: 0.6, dmgMult: 0.8, opt: { direct: false } }); } } }
    // 재점화(불씨 정령)
    const emberW = st.weapons.find(x => x.id === 'ember');
    if (emberW && emberW.stats.mods.includes('reignite')) for (const z of st.zones) if (z.type === 'fire' && z.weapon === emberW && m().dist(z, e) <= z.r + e.r && (z.extended || 0) < 4.5) { z.ttl += 1.5; z.extended = (z.extended || 0) + 1.5; }
    // 연쇄의 씨앗(보스 보상): 상태 전파(남은 시간 절반, 더 긴 쪽 유지)
    if (b.bossRewards.includes('seed')) for (const o of alive(st)) if (m().dist(o, e) <= 90 + o.r) { if (e.chill > 0) o.chill = Math.max(o.chill, e.chill / 2); if (e.burn && e.burn.t > 0) { if (!o.burn || o.burn.t < e.burn.t / 2) o.burn = { t: e.burn.t / 2, dps: e.burn.dps }; } if (e.bleed && e.bleed.t > 0) { if (!o.bleed || o.bleed.t < e.bleed.t / 2) o.bleed = { t: e.bleed.t / 2, dps: e.bleed.dps }; } }
  }
  // 일제 공격(보스 보상): E 사용 시 장착 무기 즉시 1회
  function volley(st) {
    for (const w of st.weapons) { const s = w.stats; if (s.kind === 'orbit' || s.kind === 'mine') continue; const t = s.kind === 'ember' ? pickEmberTarget(st, w) : pickTarget(st, w, s.range, true); if (t) { w.count++; FIRE[s.kind](st, w, t, true); } }
  }

  return { init, refresh, update, pickTarget, FIRE, onProjectileHit, steerProjectile, onHit, onKill, volley, explodeMine, hitCircle, hitArc, hitBeam, proj };
})();
