// 신규 보스 2종 행동: 봉인 수호자(guardian)·예언을 먹는 자(eater). PA.Boss.update가 bossId로 여기로 넘긴다.
// 공통: 준비 → 확정 → 실행 → 빈틈. 감속장(timeFactor)은 모든 단계에 적용. 완전 무적·체력 구간 피해 상한 없음.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Boss2 = (function () {
  const m = () => PA.m, K = () => PA.Combat;
  const cfgOf = (e) => PA.BOSS_DEFS[e.bossId];
  const COMMITTED = ['sweep_lock', 'shock_lock', 'mark_wait', 'lanes_lock', 'lanes_fire', 'wide_lock'];
  function isCommitted(e) { return COMMITTED.includes(e.state); }
  function toRecover(st, e, dur) { e.state = 'recover'; e.stateT = 0; e.recoverDur = dur; K().text(st, e.x, e.y - e.r - 30, '빈틈!', '#ffd166'); }
  function toApproach(st, e) { e.state = 'approach'; e.stateT = 0; e.approachT = 0; }
  function alliesCommitted(st) { return st.enemies.some(o => !o.dead && !o.boss && !o.structure && K().isCommitted(o)); }

  // ---------- 설정(스폰 시) ----------
  function init(st, e) {
    const cfg = cfgOf(e);
    e.history = []; e.actions = 0; e.waitT = 0; e.approachT = 0; e.marks = []; e.lanes = []; e.trail = []; e.trailT = 0; e.summonBudget = cfg.summon ? cfg.summon.budget : 0; e.lastSummon = -999; e.shockLeft = 0;
    if (e.bossId === 'guardian') {
      const D = cfg.devices; e.devices = []; const others = [{ x: e.x, y: e.y }, { x: st.player.x, y: st.player.y }];
      for (let i = 0; i < D.count; i++) { const p = PA.Objectives.place(st, 20, D.minGap, 150, others); others.push(p); const d = K().spawnEnemy(st, 'seal_device', p.x, p.y); d.timer = D.first + i * 1.5; d.deviceIndex = i; e.devices.push(d); }
    }
  }
  // ---------- 패턴 선택 ----------
  function choose(st, e) {
    const cfg = cfgOf(e), p = st.player, d = m().dist(e, p), los = !K().losBlocked(st, e, p), cands = [];
    if (e.bossId === 'guardian') {
      if (e.actions === 0) return 'shock';
      if (d <= cfg.sweep.maxDist && los) cands.push(['sweep', cfg.weights.sweep]);
      if (d >= cfg.shock.minDist && d <= cfg.shock.maxDist) cands.push(['shock', cfg.weights.shock]);
      if (!cands.length) return d <= cfg.sweep.maxDist ? 'sweep' : 'shock';
    } else {
      if (e.actions === 0) return 'lanes';
      if (e.marks.length) return null; // 표식이 남아 있으면 새 패턴 없음(잔여+다음이 전부를 막지 않게)
      cands.push(['mark', cfg.weights.mark]);
      if (d >= cfg.lanes.minDist) cands.push(['lanes', cfg.weights.lanes]);
      if (d <= cfg.wide.maxDist) cands.push(['wide', cfg.weights.wide]);
      if (canSummon(st, e)) cands.push(['summon', cfg.weights.summon]);
    }
    const h = e.history, last2 = h.length >= 2 && h[h.length - 1] === h[h.length - 2] ? h[h.length - 1] : null;
    const pool = cands.filter(c => c[0] !== last2), use = pool.length ? pool : cands; if (!use.length) return null;
    let sum = 0; for (const c of use) sum += c[1]; let r = st.rng.next() * sum; for (const c of use) { r -= c[1]; if (r <= 0) return c[0]; } return use[use.length - 1][0];
  }
  function canSummon(st, e) { const S = cfgOf(e).summon; return S && e.summonBudget > 0 && (st.t - e.lastSummon) >= S.interval && PA.Boss.summonedAlive(st) < S.cap; }
  function begin(st, e, pat) {
    const cfg = cfgOf(e); e.actions++; e.history.push(pat); if (e.history.length > 6) e.history.shift(); e.stateT = 0; e.waitT = 0; K().noteAttack(st, e, 'prepare');
    if (pat === 'sweep') e.state = 'sweep_aim';
    else if (pat === 'shock') { e.state = 'shock_aim'; e.shockLeft = cfg.shock.count[Math.min(2, e.phase - 1)]; }
    else if (pat === 'mark') e.state = 'mark_cast';
    else if (pat === 'lanes') { e.state = 'lanes_warn'; const a1 = Math.atan2(st.player.y - e.y, st.player.x - e.x); e.lanes = [{ ang: a1 }, { ang: a1 + cfg.lanes.secondDeg * Math.PI / 180 }]; e.laneIdx = 0; }
    else if (pat === 'wide') e.state = 'wide_aim';
    else if (pat === 'summon') { e.state = 'summon'; e.lastSummon = st.t; K().ev(st, 'boss_howl'); }
  }
  // 직선 충격파: 방향 고정, 파동(적 투사체)이 날아간다. 감속장 안에서는 파동도 느려짐(투사체 규칙)
  function fireShock(st, e, ang, S) { st.projectiles.push({ owner: 'enemy', kind: 'shock', x: e.x + Math.cos(ang) * e.r, y: e.y + Math.sin(ang) * e.r, vx: Math.cos(ang) * S.speed, vy: Math.sin(ang) * S.speed, r: S.width / 2, dmg: S.damage, ttl: S.len / S.speed, angle: ang, width: S.width }); K().ev(st, 'boss_sweep'); }

  // ---------- 갱신 ----------
  function update(st, e, dt) {
    const cfg = cfgOf(e), p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    // 플레이어 위치 기록(표식용, 공개 정보)
    if (e.bossId === 'eater') { e.trailT += dt; if (e.trailT >= cfg.mark.sample) { e.trailT = 0; e.trail.push({ x: p.x, y: p.y, t: st.t }); while (e.trail.length > Math.ceil(cfg.mark.history / cfg.mark.sample) + 1) e.trail.shift(); } updateMarks(st, e, dt); }
    if (e.bossId === 'guardian') updateDevices(st, e, dt);
    switch (e.state) {
      case 'intro': e.stateT += dt; if (e.stateT >= cfg.intro) toApproach(st, e); break;
      case 'approach': {
        e.stateT += adv; e.approachT += adv;
        if (e.phasePending > e.phase) { e.phase = e.phasePending; e.state = 'roar'; e.stateT = 0; K().text(st, e.x, e.y - e.r - 40, e.phase === 2 ? '2단계' : '마지막 단계', '#ff9f43'); K().ev(st, 'boss_roar', { phase: e.phase }); st.phaseEvents.push({ t: st.t, phase: e.phase }); break; }
        if (dist > cfg.stopDist) K().approach(st, e, p.x, p.y, cfg.speed * sm, dt);
        if (e.approachT < cfg.minApproach) break;
        const pat = choose(st, e); if (!pat) break;
        if (pat !== 'summon' && alliesCommitted(st) && e.waitT < cfg.overlap.bossWaitMax) { e.waitT += adv; break; }
        begin(st, e, pat); break;
      }
      case 'roar': e.stateT += adv; if (e.stateT >= cfg.roar) toApproach(st, e); break;
      // 봉인 수호자
      case 'sweep_aim': e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv; if (e.stateT >= cfg.sweep.aim) { e.state = 'sweep_lock'; e.stateT = 0; e.dir = e.aimAngle; K().ev(st, 'boss_lock'); } break;
      case 'sweep_lock': e.stateT += adv; if (e.stateT >= cfg.sweep.lock) { if (m().inArc(e, cfg.sweep.radius, e.dir, cfg.sweep.arcDeg * Math.PI / 360, p, p.r) && !K().losBlocked(st, e, p)) K().damagePlayer(st, cfg.sweep.damage, 'boss_sweep'); K().fx(st, { kind: 'bosssweep', x: e.x, y: e.y, angle: e.dir, r: cfg.sweep.radius, half: cfg.sweep.arcDeg * Math.PI / 360, ttl: 0.3, t: 0 }); K().ev(st, 'boss_sweep'); K().noteAttack(st, e, 'execute'); toRecover(st, e, cfg.sweep.recover); } break;
      case 'shock_aim': e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv; if (e.stateT >= cfg.shock.aim) { e.state = 'shock_lock'; e.stateT = 0; e.dir = e.aimAngle; K().ev(st, 'boss_lock'); } break;
      case 'shock_lock': e.stateT += adv; if (e.stateT >= cfg.shock.lock) { const S = cfg.shock; if (e.shockLeft >= 2) { fireShock(st, e, e.dir - S.spread, S); fireShock(st, e, e.dir + S.spread, S); } else fireShock(st, e, e.dir, S); K().noteAttack(st, e, 'execute'); toRecover(st, e, S.recover); } break;
      // 예언을 먹는 자
      case 'mark_cast': { e.stateT += adv; if (e.stateT >= cfg.mark.cast) { const M = cfg.mark, n = M.count[Math.min(2, e.phase - 1)]; const pts = e.trail.filter(q => q.t == null || st.t - q.t >= M.sample).slice(-n); /* 시전 시점 기준 0.5초 이상 지난 위치만(현재 위치 제외) */ e.marks = pts.map((q, i) => ({ x: q.x, y: q.y, r: M.r, explodeAt: st.t + M.delay + i * M.gap, done: false })); if (!e.marks.length) e.marks = [{ x: p.x, y: p.y, r: M.r, explodeAt: st.t + M.delay, done: false }]; e.state = 'mark_wait'; e.stateT = 0; K().noteAttack(st, e, 'execute'); K().ev(st, 'boss_lock'); } break; }
      case 'mark_wait': e.stateT += adv; if (!e.marks.length) toRecover(st, e, cfg.mark.recover); break;
      case 'lanes_warn': { e.stateT += adv; if (e.stateT >= cfg.lanes.warn) { e.state = 'lanes_lock'; e.stateT = 0; K().ev(st, 'boss_lock'); } break; }
      case 'lanes_lock': { e.stateT += adv; if (e.stateT >= cfg.lanes.lock) { const L = cfg.lanes, ln = e.lanes[e.laneIdx]; fireShock(st, e, ln.ang, L); ln.fired = true; K().noteAttack(st, e, 'execute'); e.laneIdx++; if (e.laneIdx < e.lanes.length) { e.state = 'lanes_fire'; e.stateT = 0; } else toRecover(st, e, L.recover); } break; }
      case 'lanes_fire': e.stateT += adv; if (e.stateT >= cfg.lanes.gap) { e.state = 'lanes_lock'; e.stateT = 0; } break;
      case 'wide_aim': e.stateT += adv; if (e.stateT >= cfg.wide.aim) { e.state = 'wide_lock'; e.stateT = 0; K().ev(st, 'boss_lock'); } break;
      case 'wide_lock': e.stateT += adv; if (e.stateT >= cfg.wide.lock) { const R = cfg.wide.radius[Math.min(2, e.phase - 1)]; if (m().dist(e, p) <= R + p.r) K().damagePlayer(st, cfg.wide.damage, 'boss_wide'); K().fx(st, { kind: 'bossland', x: e.x, y: e.y, r: R, ttl: 0.5, t: 0 }); K().ev(st, 'boss_land'); K().noteAttack(st, e, 'execute'); toRecover(st, e, cfg.wide.recover); } break;
      case 'summon': e.stateT += adv; if (e.stateT >= cfg.summon.duration) { summon(st, e); K().noteAttack(st, e, 'execute'); toApproach(st, e); } break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) toApproach(st, e); break;
      case 'stagger': e.stateT += adv; if (e.stateT >= cfg.stagger) toApproach(st, e); break;
    }
    K().pushOut(st, e);
  }
  // 표식 폭발: 공개된 위치, 정해진 시각에 순차. 감속장은 표식 시계를 늦추지 않는다(위치 기반 예고이므로 회피 여유가 이미 큼)
  function updateMarks(st, e, dt) {
    const p = st.player; for (const mk of e.marks) { if (mk.done || st.t < mk.explodeAt) continue; mk.done = true; if (m().dist(mk, p) <= mk.r + p.r) K().damagePlayer(st, cfgOf(e).mark.damage, 'boss_mark'); K().fx(st, { kind: 'burst', x: mk.x, y: mk.y, r: mk.r, ttl: 0.35, t: 0, color: '#c080ff' }); K().ev(st, 'explode'); }
    e.marks = e.marks.filter(mk => !mk.done);
  }
  // 봉인 장치: 살아 있는 장치마다 주기적으로 플레이어 좌우에 바닥 위험. 동시 위험 상한
  function updateDevices(st, e, dt) {
    const D = cfgOf(e).devices, p = st.player;
    for (const d of e.devices) { if (d.dead) continue; d.timer -= dt; if (d.timer > 0) continue; d.timer = D.interval; if (st.zones.filter(z => z.type === 'hazard').length >= cfgOf(e).overlap.maxHazardZones) continue; PA.Objectives.ringHazards(st, p.x, p.y, D.n, D.dist, D.r, D, 'device', p.face + Math.PI / 2 + d.deviceIndex * 0.6); K().ev(st, 'hazard_warn'); }
  }
  function summon(st, e) {
    const S = cfgOf(e).summon, p = st.player; let n = Math.min(S.count, e.summonBudget, S.cap - PA.Boss.summonedAlive(st) - st.pending.filter(s => s.summoned).length); if (n <= 0) return;
    let placed = 0;
    for (const rr of [S.ring[0], S.ring[1], S.ring[1] + 60]) for (let i = 0; i < 12 && placed < n; i++) { const a = i / 12 * Math.PI * 2 + st.rng.range(-0.1, 0.1), x = e.x + Math.cos(a) * rr, y = e.y + Math.sin(a) * rr; const type = S.pool[(e.summonBudget + placed) % S.pool.length]; if (!K().validPos(st, x, y, PA.ENEMIES[type].r) || m().dist({ x, y }, p) < 150) continue; if (st.pending.some(s => m().dist(s, { x, y }) < 30)) continue; st.pending.push({ type, x, y, t: S.warn, summoned: true }); K().fx(st, { kind: 'pawwarn', x, y, ttl: S.warn, t: 0, type }); placed++; }
    e.summonBudget -= placed; if (placed) K().ev(st, 'wave', { summon: true });
  }
  // 현재 위험 예고 안인가(회복 구슬 배치용)
  function inDanger(st, e, pt) {
    const cfg = cfgOf(e);
    if ((e.state === 'sweep_aim' || e.state === 'sweep_lock') && cfg.sweep) return m().inArc(e, cfg.sweep.radius, e.state === 'sweep_aim' ? e.aimAngle : e.dir, cfg.sweep.arcDeg * Math.PI / 360, pt, 14);
    if ((e.state === 'shock_aim' || e.state === 'shock_lock') && cfg.shock) return m().inBeam(e, e.state === 'shock_aim' ? e.aimAngle : e.dir, cfg.shock.len, cfg.shock.width + 28, pt, 14);
    if (e.marks && e.marks.some(mk => m().dist(mk, pt) <= mk.r + 14)) return true;
    if ((e.state === 'wide_aim' || e.state === 'wide_lock') && cfg.wide) return m().dist(e, pt) <= cfg.wide.radius[Math.min(2, e.phase - 1)] + 14;
    if (e.state === 'lanes_warn' || e.state === 'lanes_lock' || e.state === 'lanes_fire') return e.lanes.some(l => !l.fired && m().inBeam(e, l.ang, cfg.lanes.len, cfg.lanes.width + 28, pt, 14));
    return false;
  }
  // 봇 위협 도형
  function threats(st, bz, out) {
    const cfg = cfgOf(bz), p = st.player;
    if (bz.state === 'sweep_aim') out.push({ kind: 'arc', e: bz, x: bz.x, y: bz.y, ang: bz.aimAngle, r: cfg.sweep.radius + 30, half: cfg.sweep.arcDeg * Math.PI / 360 + 0.2, prog: bz.stateT / cfg.sweep.aim, locked: false });
    if (bz.state === 'sweep_lock') out.push({ kind: 'arc', e: bz, x: bz.x, y: bz.y, ang: bz.dir, r: cfg.sweep.radius + 30, half: cfg.sweep.arcDeg * Math.PI / 360 + 0.2, prog: 1, locked: true });
    if (bz.state === 'shock_aim') out.push({ kind: 'beam', e: bz, x: bz.x, y: bz.y, ang: bz.aimAngle, len: cfg.shock.len, w: cfg.shock.width + 30 + (bz.shockLeft >= 2 ? 200 : 0), prog: bz.stateT / cfg.shock.aim, locked: false });
    if (bz.state === 'shock_lock') out.push({ kind: 'beam', e: bz, x: bz.x, y: bz.y, ang: bz.dir, len: cfg.shock.len, w: cfg.shock.width + 30 + (bz.shockLeft >= 2 ? 200 : 0), prog: 1, locked: true });
    if (bz.marks) for (const mk of bz.marks) out.push({ kind: 'circle', e: bz, x: mk.x, y: mk.y, r: mk.r + 10, prog: Math.min(1, 1 - (mk.explodeAt - st.t) / cfg.mark.delay), locked: mk.explodeAt - st.t < 0.6 });
    if (bz.state === 'lanes_warn' || bz.state === 'lanes_lock' || bz.state === 'lanes_fire') for (const l of bz.lanes) if (!l.fired) out.push({ kind: 'beam', e: bz, x: bz.x, y: bz.y, ang: l.ang, len: cfg.lanes.len, w: cfg.lanes.width + 30, prog: bz.state === 'lanes_warn' ? bz.stateT / cfg.lanes.warn : 1, locked: bz.state !== 'lanes_warn' });
    if (bz.state === 'wide_aim' || bz.state === 'wide_lock') out.push({ kind: 'circle', e: bz, x: bz.x, y: bz.y, r: cfg.wide.radius[Math.min(2, bz.phase - 1)] + 30, prog: bz.state === 'wide_aim' ? bz.stateT / cfg.wide.aim : 1, locked: bz.state === 'wide_lock' });
  }
  return { init, update, inDanger, threats, isCommitted, COMMITTED, choose, summon };
})();
