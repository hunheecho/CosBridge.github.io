// 보스 '가시갈기 — 숲의 왕' 행동. combat.js가 type === 'boss' 개체에 대해 PA.Boss.update를 호출한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Boss = (function () {
  const B = () => PA.BOSS;
  const cfgOf = (e) => (PA.BOSS_DEFS && PA.BOSS_DEFS[e.bossId]) || PA.BOSS; // 보스별 설정(가시갈기는 PA.BOSS)
  const m = () => PA.m;
  const K = () => PA.Combat; // 내부 헬퍼 접근

  function spawn(st, x, y, bossId) {
    bossId = bossId || 'boss';
    const e = K().spawnEnemy(st, bossId, x, y); e.bossId = bossId;
    Object.assign(e, {
      boss: true, phase: 1, phasePending: 0, state: 'intro', stateT: 0, actions: 0, history: [], lastHowl: -999,
      dashSeq: 1, dashTotal: 1, dashDist: 0, dashEnd: null, dashLen: 0, hitDone: false, waitT: 0, approachT: 0,
      land: null, leapFrom: null, leapK: 0, staggerAfterLand: false, exposed: false,
    });
    st.boss = e;
    if (bossId !== 'boss' && PA.Boss2) PA.Boss2.init(st, e);
    return e;
  }

  // ---------- 판단 보조 ----------
  function wolfAttacking(st) { return st.enemies.some(e => !e.dead && !e.boss && (e.type === 'wolf' || e.type === 'wolf_alpha') && (e.state === 'crouch' || e.state === 'lock' || e.state === 'dash')); }
  function bossCommitted(e) { return e.state === 'sweep_lock' || e.state === 'dash_lock' || e.state === 'dash' || e.state === 'pounce_lock' || e.state === 'leap' || (PA.Boss2 && PA.Boss2.isCommitted(e)); }
  function summonedAlive(st) { return st.enemies.filter(e => !e.dead && e.summoned).length; }
  function isExposed(e) { return e.state === 'recover' || e.state === 'stagger'; }

  // 돌진 경로: 장애물·벽까지의 실제 종료점(예고와 실제가 같은 계산을 쓴다)
  function dashPath(st, e, ang, maxDist) {
    const dx = Math.cos(ang) * maxDist, dy = Math.sin(ang) * maxDist;
    let t = 1;
    const a = st.arena;
    const x1 = e.x + dx, y1 = e.y + dy;
    const wx = m().clamp(x1, e.r, a.w - e.r), wy = m().clamp(y1, e.r, a.h - e.r);
    if (wx !== x1 || wy !== y1) { const tx = wx !== x1 ? (wx - e.x) / dx : 1, ty = wy !== y1 ? (wy - e.y) / dy : 1; t = Math.max(0, Math.min(t, tx, ty)); }
    const sw = m().sweepCircle(e.x, e.y, x1, y1, e.r, st.obstacles);
    if (sw && sw.t < t) t = sw.t;
    return { len: maxDist * t, end: { x: e.x + dx * t, y: e.y + dy * t } };
  }
  // 덮쳐찍기 착지점: 보스 몸이 들어가는 빈 공간으로 보정
  function landingFor(st, e, tx, ty) {
    const a = st.arena, r = e.r;
    const cx = m().clamp(tx, r + 4, a.w - r - 4), cy = m().clamp(ty, r + 4, a.h - r - 4);
    return K().nearestValidPos(st, cx, cy, r, 300) || { x: e.x, y: e.y };
  }

  function choosePattern(st, e) {
    const cfg = B(), p = st.player, d = m().dist(e, p), los = !K().losBlocked(st, e, p);
    const cands = [];
    if (e.actions === 0) return 'dash';                       // 첫 공격은 단일 돌진
    if (e.history.length === 1 && e.history[0] === 'dash' && canHowl(st, e)) return 'howl'; // 첫 돌진 뒤 첫 소환
    if (d <= cfg.sweep.maxDist && los) cands.push(['sweep', cfg.weights.sweep]);
    if (d >= cfg.dash.minDist && d <= cfg.dash.maxDist && los) cands.push(['dash', cfg.weights.dash]);
    if (e.phase >= 2 && d >= cfg.pounce.minDist) cands.push(['pounce', cfg.weights.pounce]);
    if (canHowl(st, e)) cands.push(['howl', cfg.weights.howl]);
    // 같은 행동을 세 번 연속 반복하지 않는다
    const h = e.history, last2 = h.length >= 2 && h[h.length - 1] === h[h.length - 2] ? h[h.length - 1] : null;
    const pool = cands.filter(c => c[0] !== last2);
    const use = pool.length ? pool : cands;
    if (!use.length) return null;
    let sum = 0; for (const c of use) sum += c[1];
    let r = st.rng.next() * sum;
    for (const c of use) { r -= c[1]; if (r <= 0) return c[0]; }
    return use[use.length - 1][0];
  }
  function canHowl(st, e) { return (st.t - e.lastHowl) >= B().howl.interval && summonedAlive(st) < B().howl.maxWolves; }

  function begin(st, e, pattern) {
    e.actions++; e.history.push(pattern); if (e.history.length > 6) e.history.shift();
    e.stateT = 0; e.hitDone = false; e.waitT = 0;
    K().noteAttack(st, e, 'prepare');
    if (pattern === 'sweep') e.state = 'sweep_aim';
    else if (pattern === 'dash') { e.state = 'dash_aim'; e.dashSeq = 1; e.dashTotal = e.phase >= 3 ? 2 : 1; }
    else if (pattern === 'pounce') e.state = 'pounce_aim';
    else if (pattern === 'howl') { e.state = 'howl'; e.lastHowl = st.t; K().ev(st, 'boss_howl'); }
  }
  function toRecover(st, e, dur) { e.state = 'recover'; e.stateT = 0; e.recoverDur = dur; K().text(st, e.x, e.y - e.r - 30, '빈틈!', '#ffd166'); }
  function toApproach(st, e) { e.state = 'approach'; e.stateT = 0; e.approachT = 0; }

  // ---------- 단계 ----------
  function checkPhase(st, e) {
    // 체력선을 처음 통과할 때 회복 구슬 생성. 단계 적용은 현재 행동이 끝난 뒤(phasePending).
    const ratio = e.hp / e.hpMax;
    const ph = cfgOf(e).phases;
    for (let i = 0; i < ph.length; i++) {
      const want = i + 2;
      if (ratio <= ph[i] && !st.orbsSpawned[want]) { st.orbsSpawned[want] = true; spawnOrb(st, e); if (e.phasePending < want && e.phase < want) e.phasePending = want; }
    }
  }
  function spawnOrb(st, e) {
    const cfg = cfgOf(e).orb, p = st.player;
    let best = null, bd = Infinity;
    for (let i = 0; i < 24; i++) {
      const a = i / 24 * Math.PI * 2, x = e.x + Math.cos(a) * cfg.ring, y = e.y + Math.sin(a) * cfg.ring;
      if (!K().validPos(st, x, y, cfg.r)) continue;
      if (m().dist({ x, y }, e) < e.r + cfg.r + 30) continue;
      if (inDanger(st, e, { x, y })) continue;
      const d = m().dist({ x, y }, p);
      if (d < bd) { bd = d; best = { x, y }; }
    }
    if (!best) best = K().nearestValidPos(st, p.x + 80, p.y, cfg.r, 300) || { x: p.x, y: p.y };
    st.pickups.push({ kind: 'heal', x: best.x, y: best.y, r: cfg.r, amount: Math.floor(st.player.hpMax * cfg.healRatio), t: 0 });
    K().text(st, best.x, best.y - 24, '회복 구슬', '#9cffb0');
  }
  // 현재 위험 예고 한가운데인가(돌진 통로·휩쓸기 부채꼴·착지 원)
  function inDanger(st, e, pt) {
    if (e.bossId && e.bossId !== 'boss' && PA.Boss2) return PA.Boss2.inDanger(st, e, pt);
    const cfg = B();
    if ((e.state === 'dash_lock' || e.state === 'dash') && e.dashEnd) return m().inBeam(e, e.dir, e.dashLen, (e.r + 14) * 2, pt, 14);
    if (e.state === 'sweep_aim' || e.state === 'sweep_lock') return m().inArc(e, cfg.sweep.radius, e.state === 'sweep_aim' ? e.aimAngle : e.dir, cfg.sweep.arcDeg * Math.PI / 360, pt, 14);
    if ((e.state === 'pounce_lock' || e.state === 'leap') && e.land) return m().dist(e.land, pt) <= cfg.pounce.radius + 14;
    return false;
  }

  // ---------- 갱신 ----------
  function update(st, e, dt) {
    if (e.bossId && e.bossId !== 'boss' && PA.Boss2) return PA.Boss2.update(st, e, dt);
    const cfg = B(), p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e);
    const dist = m().dist(e, p);
    const adv = dt * tf;
    switch (e.state) {
      case 'intro':
        e.stateT += dt;
        if (e.stateT >= cfg.intro) toApproach(st, e);
        break;
      case 'approach': {
        e.stateT += adv; e.approachT += adv;
        // 단계 전환은 행동 사이에서만
        if (e.phasePending > e.phase) { e.phase = e.phasePending; e.state = 'roar'; e.stateT = 0; K().text(st, e.x, e.y - e.r - 40, e.phase === 2 ? '추격 단계' : '마지막 맹공', '#ff9f43'); K().ev(st, 'boss_roar', { phase: e.phase }); st.phaseEvents.push(e.phase); break; }
        if (dist > cfg.stopDist) K().approach(st, e, p.x, p.y, cfg.speed * sm, dt);
        if (e.approachT < cfg.minApproach) break;
        const pat = choosePattern(st, e);
        if (!pat) break;
        // 겹침 제한: 늑대가 돌진 중이면 큰 공격을 잠시 미룬다(최대 bossWaitMax)
        if (pat !== 'howl' && wolfAttacking(st) && e.waitT < cfg.overlap.bossWaitMax) { e.waitT += adv; break; }
        begin(st, e, pat);
        break;
      }
      case 'roar':
        e.stateT += adv;
        if (e.stateT >= cfg.roar) toApproach(st, e);
        break;
      case 'sweep_aim':
        e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x);
        e.stateT += adv;
        if (e.stateT >= cfg.sweep.aim) { e.state = 'sweep_lock'; e.stateT = 0; e.dir = e.aimAngle; K().ev(st, 'boss_lock'); }
        break;
      case 'sweep_lock':
        e.stateT += adv;
        if (e.stateT >= cfg.sweep.lock) {
          // 판정: 표시된 부채꼴과 동일. 직접 공격이므로 장애물 가림 적용
          if (m().inArc(e, cfg.sweep.radius, e.dir, cfg.sweep.arcDeg * Math.PI / 360, p, p.r) && !K().losBlocked(st, e, p)) K().damagePlayer(st, cfg.sweep.damage, 'boss_sweep');
          K().fx(st, { kind: 'bosssweep', x: e.x, y: e.y, angle: e.dir, r: cfg.sweep.radius, half: cfg.sweep.arcDeg * Math.PI / 360, ttl: 0.3, t: 0 });
          K().ev(st, 'boss_sweep'); K().noteAttack(st, e, 'execute');
          toRecover(st, e, cfg.sweep.recover);
        }
        break;
      case 'dash_aim': {
        e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x);
        e.stateT += adv;
        const aimT = e.dashSeq === 2 ? cfg.dash.second.aim : cfg.dash.aim;
        if (e.stateT >= aimT) { e.state = 'dash_lock'; e.stateT = 0; e.dir = e.aimAngle; const path = dashPath(st, e, e.dir, cfg.dash.dist); e.dashLen = path.len; e.dashEnd = path.end; e.dashDist = 0; e.hitDone = false; K().ev(st, 'boss_lock'); }
        break;
      }
      case 'dash_lock': {
        e.stateT += adv;
        const lockT = e.dashSeq === 2 ? cfg.dash.second.lock : cfg.dash.lock;
        if (e.stateT >= lockT) { e.state = 'dash'; e.stateT = 0; K().noteAttack(st, e, 'execute'); }
        break;
      }
      case 'dash': {
        // 거리 기준 진행: 감속되어도 확정된 경로와 거리는 그대로
        const remain = Math.max(0, e.dashLen - e.dashDist);
        const step = Math.min(cfg.dash.speed * tf * dt, remain);
        const x0 = e.x, y0 = e.y;
        const mv = K().moveSwept(st, e, Math.cos(e.dir) * step, Math.sin(e.dir) * step);
        e.dashDist += Math.hypot(e.x - x0, e.y - y0);
        if (!e.hitDone && m().segCircle(x0, y0, e.x, e.y, p, p.r + e.r)) { e.hitDone = true; e.biteT = 0; K().ev(st, 'bite'); K().damagePlayer(st, cfg.dash.damage, 'boss_dash'); }
        if (e.dashDist >= e.dashLen - 1e-6 || mv.hit || step <= 1e-9) {
          if (e.dashSeq < e.dashTotal) { e.dashSeq++; e.state = 'dash_aim'; e.stateT = 0; K().text(st, e.x, e.y - e.r - 30, '연속 돌진 2/2', '#ff9f43'); }
          else toRecover(st, e, e.dashTotal > 1 ? cfg.dash.doubleRecover : cfg.dash.recover);
        }
        break;
      }
      case 'howl':
        e.stateT += adv;
        if (e.stateT >= cfg.howl.duration) { summon(st, e); K().noteAttack(st, e, 'execute'); toApproach(st, e); e.approachT = 0; }
        break;
      case 'pounce_aim':
        e.land = landingFor(st, e, p.x, p.y);
        e.stateT += adv;
        if (e.stateT >= cfg.pounce.aim) { e.state = 'pounce_lock'; e.stateT = 0; e.land = landingFor(st, e, p.x, p.y); K().ev(st, 'boss_lock'); }
        break;
      case 'pounce_lock':
        e.stateT += adv;
        if (e.stateT >= cfg.pounce.lock) { e.state = 'leap'; e.stateT = 0; e.leapFrom = { x: e.x, y: e.y }; e.leapK = 0; e.airborne = true; K().noteAttack(st, e, 'execute'); }
        break;
      case 'leap': {
        e.leapK = Math.min(1, e.leapK + adv / cfg.pounce.leap);
        e.x = e.leapFrom.x + (e.land.x - e.leapFrom.x) * e.leapK; e.y = e.leapFrom.y + (e.land.y - e.leapFrom.y) * e.leapK;
        if (e.leapK >= 1) {
          e.airborne = false; e.x = e.land.x; e.y = e.land.y;
          // 지면 충격: 표시된 원 범위. 장애물 가림 없음
          if (m().dist(e, p) <= cfg.pounce.radius + p.r) K().damagePlayer(st, cfg.pounce.damage, 'boss_pounce');
          K().fx(st, { kind: 'bossland', x: e.x, y: e.y, r: cfg.pounce.radius, ttl: 0.45, t: 0 });
          K().ev(st, 'boss_land');
          if (e.staggerAfterLand) { e.staggerAfterLand = false; e.state = 'stagger'; e.stateT = 0; }
          else toRecover(st, e, cfg.pounce.recover);
        }
        break;
      }
      case 'recover':
        e.stateT += adv;
        if (e.stateT >= e.recoverDur) toApproach(st, e);
        break;
      case 'stagger':
        e.stateT += adv;
        if (e.stateT >= cfg.stagger) toApproach(st, e);
        break;
    }
    if (e.state !== 'leap') K().pushOut(st, e);
  }

  function summon(st, e) {
    const cfg = B().howl, p = st.player;
    const room = cfg.maxWolves - summonedAlive(st) - st.pending.filter(s => s.summoned).length;
    const n = Math.min(cfg.count, Math.max(0, room));
    // 후보를 체계적으로 훑는다(벽 옆·플레이어 근처에서도 자리를 찾도록). 플레이어 160 안, 장애물 안, 전장 밖 제외.
    const wr = PA.ENEMIES.wolf.r, cands = [];
    for (const rr of [cfg.ring[0], cfg.ring[1], cfg.ring[1] + 50, cfg.ring[1] + 100]) for (let i = 0; i < 16; i++) {
      const a = i / 16 * Math.PI * 2 + st.rng.range(-0.1, 0.1), x = e.x + Math.cos(a) * rr, y = e.y + Math.sin(a) * rr;
      if (!K().validPos(st, x, y, wr)) continue;
      cands.push({ x, y, dp: m().dist({ x, y }, p), ring: rr });
    }
    let pool = cands.filter(c => c.dp >= 160); if (pool.length < n) pool = cands.filter(c => c.dp >= 110);
    pool = st.rng.shuffle(pool).sort((a, b) => a.ring - b.ring); // 가까운 링 우선, 같은 링은 무작위
    let placed = 0;
    for (const c of pool) {
      if (placed >= n) break;
      if (st.pending.some(s => m().dist(s, c) < wr * 2 + 4)) continue;
      st.pending.push({ type: 'wolf', x: c.x, y: c.y, t: cfg.warn, summoned: true });
      K().fx(st, { kind: 'pawwarn', x: c.x, y: c.y, ttl: cfg.warn, t: 0, type: 'wolf' });
      placed++;
    }
    if (placed) K().ev(st, 'wave', { summon: true });
  }

  // 방벽 파열: 진행 중 공격을 끊고 비틀거림. 도약 중이면 착지 후 적용
  function stagger(st, e) {
    if (e.dead) return;
    if (e.state === 'leap') { e.staggerAfterLand = true; return; }
    e.state = 'stagger'; e.stateT = 0; e.biteT = 0;
    K().text(st, e.x, e.y - e.r - 30, '비틀거림!', '#7ef2ff');
  }

  return { spawn, update, checkPhase, stagger, isExposed, wolfAttacking, bossCommitted, dashPath, landingFor, summonedAlive, inDanger, cfgOf };
})();
