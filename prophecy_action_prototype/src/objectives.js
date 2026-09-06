// 전투 목표 4종(정예 추적·제단 파괴·봉인 해제·포로 구출) 진행 규칙. Combat.create/step에서 호출된다.
// 구조물(제단)은 적 목록(structure)에, 우리·봉인 지점·출구·포로는 st.objects에 둔다. 사람·봇 공용(입력과 무관).
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Objectives = (function () {
  const m = () => PA.m, K = () => PA.Combat, C = () => PA.CONFIG;
  function is(id) { return !!PA.OBJECTIVES[id]; }
  function spec(st) { return PA.OBJECTIVES[st.objective]; }

  // ---------- 배치(지형 검사): 장애물 밖·플레이어에서 떨어진 곳·서로 떨어진 곳 ----------
  function place(st, r, minGap, minPlayerGap, others, tries) {
    const a = st.arena, rng = st.rng, pad = 70; let best = null, bestScore = -1;
    for (let i = 0; i < (tries || 40); i++) {
      const x = rng.range(pad, a.w - pad), y = rng.range(pad, a.h - pad);
      const p = K().nearestValidPos(st, x, y, r + 6, 80); if (!p) continue;
      const dp = m().dist(p, st.player); if (dp < minPlayerGap) continue;
      let ok = true, minD = Infinity; for (const o of others) { const d = m().dist(p, o); if (d < minGap) { ok = false; break; } if (d < minD) minD = d; }
      if (!ok) continue;
      const score = Math.min(minD, dp); if (score > bestScore) { bestScore = score; best = p; }
      if (others.length === 0) break;
    }
    if (!best) { // 조건을 만족하는 위치가 없으면 조건을 완화(무한 대기 방지): 유효 위치만 보장
      for (let i = 0; i < 60 && !best; i++) { const p = K().nearestValidPos(st, rng.range(pad, a.w - pad), rng.range(pad, a.h - pad), r + 6, 120); if (p && m().dist(p, st.player) >= r + 60) best = p; }
    }
    return best || { x: a.w / 2, y: 80 };
  }
  function edgeExit(st, away) { // 출구: 플레이어·우리에서 가장 먼 가장자리 지점(유효 위치)
    const a = st.arena, cands = [{ x: 60, y: a.h / 2 }, { x: a.w - 60, y: a.h / 2 }, { x: a.w / 2, y: 60 }, { x: a.w / 2, y: a.h - 60 }];
    let best = null, bs = -1; for (const c of cands) { const p = K().nearestValidPos(st, c.x, c.y, 40, 80); if (!p) continue; const s = Math.min(...away.map(o => m().dist(p, o))); if (s > bs) { bs = s; best = p; } }
    return best || { x: a.w / 2, y: 60 };
  }

  // ---------- 지원병(유한 예산·동시 상한) ----------
  function makeReinforce(cfg, pool) { return cfg ? { budget: cfg.budget, cap: cfg.cap, interval: cfg.interval, timer: cfg.first != null ? cfg.first : cfg.interval, pool: pool.slice(), spawned: 0 } : null; }
  function activeEnemies(st) { return st.enemies.filter(e => !e.dead && !e.structure).length + st.pending.length; }
  function reinforce(st, R, dt, n) {
    if (!R || R.budget <= 0) return 0;
    R.timer -= dt; if (R.timer > 0) return 0; R.timer = R.interval;
    let k = 0; const want = n || 1;
    while (k < want && R.budget > 0 && activeEnemies(st) < R.cap) { const type = R.pool[(R.spawned) % R.pool.length]; K().queueWave(st, [{ type, n: 1 }]); R.budget--; R.spawned++; k++; }
    if (k) K().ev(st, 'reinforce', { n: k });
    return k;
  }
  function poolFor(st, opts) { const rid = opts.regionId; const list = rid && PA.Run ? PA.Run.regionEnemies(rid, opts.run || null).filter(t => !PA.ENEMIES[t].elite) : ['wolf']; return list.length ? list : ['wolf']; }

  // ---------- 설정 ----------
  function setup(st, opts) {
    const S = spec(st); if (!S) return;
    const risk = opts.risk || null, pool = poolFor(st, opts);
    const o = st.obj = { type: st.objective, risk, done: false, doneT: null, targetText: '' };
    st.objects = st.objects || [];
    if (st.objective === 'hunt') {
      // 웨이브 1: 호위 + 정예. 정예는 처음부터 등장(숨지 않음)
      const escortType = pool[0];
      st.waves = [[{ type: escortType, n: S.escortN }, { type: S.eliteType, n: 1 }]];
      o.reinforce = makeReinforce(S.reinforce, pool); o.reinforce.timer = 0; o.reinforceFired = false; o.elite = null;
    } else if (st.objective === 'altars') {
      st.waves = [[{ type: pool[0], n: 2 }]];
      const others = []; o.altars = [];
      for (const kind of ['heal', 'hazard', 'reinforce']) {
        const p = place(st, 22, S.minGap, S.minPlayerGap, others); others.push(p);
        const e = K().spawnEnemy(st, 'altar_' + kind, p.x, p.y); e.altar = kind; e.timer = kind === 'heal' ? S.heal.interval : kind === 'hazard' ? 2.5 : S.reinforce.interval; e.budget = kind === 'heal' ? S.heal.budget : kind === 'reinforce' ? S.reinforce.budget : Infinity;
        o.altars.push(e);
      }
      o.reinforce = makeReinforce(S.reinforce, pool);
    } else if (st.objective === 'seal') {
      st.waves = [[{ type: pool[0], n: 2 }]];
      const p1 = place(st, S.r, S.minGap, 120, []); const p2 = place(st, S.r, S.minGap, 120, [p1]);
      o.points = [p1, p2]; o.stage = 1; o.stages = S.stages; o.progress = 0; o.total = S.time; o.paused = false; o.hitPause = 0; o.moveWarnT = 0;
      st.objects.push({ kind: 'seal', x: p1.x, y: p1.y, r: S.r, active: true });
      o.reinforce = makeReinforce(S.reinforce, pool);
    } else if (st.objective === 'rescue') {
      st.waves = [[{ type: pool[0], n: 2 }]];
      const c1 = place(st, 26, S.minGap, 150, []); const c2 = place(st, 26, S.minGap, 150, [c1]);
      const ex = edgeExit(st, [c1, c2, st.player]);
      o.cages = S.cages; o.freed = 0; o.active = null;
      st.objects.push({ kind: 'cage', x: c1.x, y: c1.y, r: 26, progress: 0, total: S.time, freed: false, id: 1 });
      st.objects.push({ kind: 'cage', x: c2.x, y: c2.y, r: 26, progress: 0, total: S.time, freed: false, id: 2 });
      st.objects.push({ kind: 'exit', x: ex.x, y: ex.y, r: S.exitR, open: false });
      o.reinforce = makeReinforce(S.reinforce, pool);
    }
    // 위험 조건(카드): 지원병 증가 = 예산 ×1.5(동시 상한 동일) / 정예 호위 = 첫 웨이브에 정예 1 추가 / 위험 지형 = 주기적 바닥 위험(안전 통로 보장)
    if (risk === 'reinforce' && o.reinforce) o.reinforce.budget = Math.round(o.reinforce.budget * 1.5);
    if (risk === 'escort') { const w0 = st.waves[0]; if (!w0.some(g => g.type === 'wolf_alpha')) w0.push({ type: 'wolf_alpha', n: 1 }); }
    if (risk === 'hazard') o.terrain = { timer: 6, interval: 7, warn: 1.2, ttl: 1.6, r: 60, dmg: 10, lanes: 3 };
    st.spawnedAll = false;
  }

  // ---------- 바닥 위험(예고 → 지역). 항상 안전 통로를 남긴다 ----------
  function coversObjective(st, x, y, r) { // 목표 지점(봉인·우리·출구·제단)을 덮는 위험은 만들지 않는다(모든 목표 지점을 막지 않음)
    for (const o of st.objects || []) if (!o.gone && !o.freed && m().dist(o, { x, y }) <= r + (o.r || 20)) return true;
    for (const e of st.enemies) if (e.structure && !e.dead && m().dist(e, { x, y }) <= r + e.r) return true;
    return false;
  }
  function hazardAt(st, x, y, r, warn, ttl, dmg, tag) {
    const p = K().nearestValidPos(st, x, y, 0, 60); if (!p) return null; if (coversObjective(st, p.x, p.y, r)) return null;
    const z = K().addZone(st, 'hazard', p.x, p.y, r, warn + ttl, dmg); z.warn = warn; z.armed = false; z.tag = tag || 'hazard'; return z;
  }
  function ringHazards(st, cx, cy, n, dist, r, cfg, tag, baseAng) { // 플레이어 주위 n개, 간격 균등: n개 사이의 빈 각도가 안전 통로
    const out = []; for (let i = 0; i < n; i++) { const a = baseAng + i * (Math.PI * 2 / n); const z = hazardAt(st, cx + Math.cos(a) * dist, cy + Math.sin(a) * dist, r, cfg.warn, cfg.ttl, cfg.dmg, tag); if (z) out.push(z); }
    return out;
  }

  // ---------- 진행 ----------
  function update(st, dt) {
    const S = spec(st), o = st.obj; if (!S || !o || st.status !== 'running') return;
    const p = st.player;
    if (o.terrain) { const T = o.terrain; T.timer -= dt; if (T.timer <= 0) { T.timer = T.interval; ringHazards(st, p.x, p.y, T.lanes, 120, T.r, T, 'terrain', p.face + Math.PI / T.lanes); K().ev(st, 'hazard_warn'); } }
    if (st.objective === 'hunt') {
      if (!o.elite) o.elite = st.enemies.find(e => e.elite && !e.structure) || null;
      const el = o.elite;
      if (el && !el.dead) {
        const d = m().dist(el, p);
        el.leash = d > S.leashDist ? (el.leash || 0) + dt : 0; el.leashBoost = el.leash > 1.0 ? S.leashSpeed : 1; // 멀어지면 접근 가속(배회 금지)
        if (!o.reinforceFired && el.hp <= el.hpMax * S.reinforce.atHp) { o.reinforceFired = true; o.reinforce.timer = 0; reinforce(st, o.reinforce, dt, o.reinforce.budget); }
      }
      if (el && el.dead) finish(st);
    } else if (st.objective === 'altars') {
      for (const a of o.altars) {
        if (a.dead) continue; a.timer -= dt; if (a.timer > 0) continue;
        if (a.altar === 'heal') { a.timer = S.heal.interval; if (a.budget > 0) { const tgt = healTarget(st, a, S.heal.range); if (tgt) { const amt = Math.min(S.heal.amount, a.budget, tgt.hpMax - tgt.hp); tgt.hp += amt; a.budget -= amt; K().fx(st, { kind: 'healbeam', x: a.x, y: a.y, tx: tgt.x, ty: tgt.y, ttl: 0.5, t: 0 }); K().text(st, tgt.x, tgt.y - tgt.r - 10, '+' + Math.round(amt), '#8ee6a0'); K().ev(st, 'altar_heal'); } } }
        else if (a.altar === 'hazard') { a.timer = S.hazard.interval; ringHazards(st, p.x, p.y, S.hazard.n, S.hazard.dist, S.hazard.r, S.hazard, 'altar', p.face + Math.PI / 2); K().ev(st, 'hazard_warn'); }
        else if (a.altar === 'reinforce') { a.timer = S.reinforce.interval; if (a.budget > 0 && activeEnemies(st) < S.reinforce.cap) { const type = o.reinforce.pool[o.reinforce.spawned % o.reinforce.pool.length]; K().queueWave(st, [{ type, n: 1 }]); a.budget--; o.reinforce.spawned++; K().ev(st, 'reinforce', { n: 1 }); } }
      }
      if (o.altars.every(a => a.dead)) finish(st);
    } else if (st.objective === 'seal') {
      reinforce(st, o.reinforce, dt);
      const z = st.objects.find(x => x.kind === 'seal');
      if (o.hitPause > 0) o.hitPause -= dt;
      if (o.moveWarnT > 0) { o.moveWarnT -= dt; if (o.moveWarnT <= 0) { z.x = o.points[1].x; z.y = o.points[1].y; z.moving = false; K().ev(st, 'seal_moved'); } o.paused = true; }
      else {
        const inside = m().dist(z, p) <= z.r; o.paused = !inside || o.hitPause > 0;
        if (!o.paused) { o.progress = Math.min(o.total, o.progress + dt); if (o.stage === 1 && o.progress >= o.total / 2) { o.stage = 2; o.moveWarnT = S.moveWarn; z.moving = true; z.next = o.points[1]; K().ev(st, 'seal_move_warn'); } }
        if (o.progress >= o.total) finish(st);
      }
    } else if (st.objective === 'rescue') {
      reinforce(st, o.reinforce, dt);
      const cages = st.objects.filter(x => x.kind === 'cage'), exit = st.objects.find(x => x.kind === 'exit');
      o.active = null;
      for (const c of cages) {
        if (c.freed) continue;
        if (m().dist(c, p) <= S.near + p.r) { c.progress = Math.min(c.total, c.progress + dt); o.active = c; if (c.progress >= c.total) { c.freed = true; o.freed++; st.objects.push({ kind: 'prisoner', x: c.x, y: c.y, r: 10, id: c.id }); K().text(st, c.x, c.y - 40, '풀려났다!', '#9cffb0'); K().ev(st, 'rescued', { n: o.freed }); } }
      }
      for (const pr of st.objects) if (pr.kind === 'prisoner' && !pr.gone) { // 포로는 출구로 스스로 이동(적은 무시, 호위 불필요)
        const d = m().norm(exit.x - pr.x, exit.y - pr.y); const mv = K().steerDir ? K().steerDir(st, pr, exit.x, exit.y) : d; pr.x += mv.x * S.prisonerSpeed * dt; pr.y += mv.y * S.prisonerSpeed * dt;
        if (m().dist(pr, exit) <= 18) pr.gone = true;
      }
      if (o.freed >= o.cages) { exit.open = true; if (m().dist(exit, p) <= exit.r) finish(st); }
    }
  }
  function healTarget(st, a, range) { let best = null, bs = 0; for (const e of st.enemies) { if (e.dead || e.structure || e.hidden || e.hp >= e.hpMax || m().dist(e, a) > range) continue; const miss = 1 - e.hp / e.hpMax; if (miss > bs) { bs = miss; best = e; } } return best; }
  function finish(st) { const o = st.obj; if (o.done) return; o.done = true; o.doneT = st.t; }
  // 승패 판정: Combat.checkObjective에서 호출. 같은 단계에서 목표 달성과 사망이 겹치면 승리 우선(보스전 규칙과 동일)
  function check(st) { const o = st.obj; return !!(o && o.done); }
  // 피해를 받으면 봉인 진행 잠시 정지(제자리에서 맞으며 버티기 금지)
  function onPlayerHit(st) { const o = st.obj; if (o && st.objective === 'seal') o.hitPause = spec(st).hitPause; }

  // ---------- 바닥 위험 지역 갱신(Combat.updateZones에서 호출): 예고 후 무장, 무장 중 플레이어 피해 ----------
  function zoneDamage(st, z, p) { if (!z.armed) { if (z.t >= z.warn) { z.armed = true; K().ev(st, 'hazard_arm'); } return 0; } return m().dist(z, p) <= z.r + p.r * 0.5 ? z.dmg : 0; }

  // ---------- 표시 ----------
  function hud(st) {
    const S = spec(st), o = st.obj; if (!S || !o) return null;
    return { title: `목적: ${S.short}`, line: S.hud(o) + (o.reinforce && o.reinforce.budget > 0 && st.objective !== 'hunt' ? ` · 지원 ${o.reinforce.budget}` : ''), risk: o.risk ? PA.MISSIONS.riskText[o.risk] : null };
  }
  // 자동 공격 대상 표시: 첫 무기 기준 가장 가까운 대상(표식 우선) — 제단인지 적인지
  function autoTarget(st) {
    const p = st.player, mk = st.markTarget; let range = 0; for (const w of st.weapons || []) range = Math.max(range, w.stats.range || w.stats.radius || 60);
    if (mk && !mk.dead && m().dist(p, mk) <= range + mk.r) return mk;
    let best = null, bd = Infinity; for (const e of st.enemies) { if (e.dead || e.hidden) continue; const d = m().dist(p, e); if (d <= range + e.r && d < bd) { bd = d; best = e; } }
    return best;
  }
  // 봇: 목표를 위한 이동 지점(적 위협이 없을 때 향한다) / 우선 대상
  function botGoal(st) {
    const o = st.obj; if (!o || o.done) return null; const p = st.player;
    if (st.objective === 'seal') { const z = st.objects.find(x => x.kind === 'seal'); if (!z) return null; const tgt = z.moving && z.next ? z.next : z; return m().dist(tgt, p) > z.r * 0.6 ? { x: tgt.x, y: tgt.y, r: z.r * 0.6 } : null; }
    if (st.objective === 'rescue') { if (o.freed >= o.cages) { const ex = st.objects.find(x => x.kind === 'exit'); return { x: ex.x, y: ex.y, r: ex.r * 0.5 }; } const c = st.objects.filter(x => x.kind === 'cage' && !x.freed).sort((a, b) => m().dist(a, p) - m().dist(b, p))[0]; return c && m().dist(c, p) > PA.OBJECTIVES.rescue.near * 0.7 ? { x: c.x, y: c.y, r: PA.OBJECTIVES.rescue.near * 0.7 } : null; }
    return null;
  }
  function botTarget(st) {
    const o = st.obj; if (!o || o.done) return null; const p = st.player;
    if (st.objective === 'altars') { const near = st.enemies.filter(e => !e.dead && !e.structure && !e.hidden && m().dist(e, p) < 90); if (near.length) return null; return o.altars.filter(a => !a.dead).sort((a, b) => m().dist(a, p) - m().dist(b, p))[0] || null; }
    if (st.objective === 'hunt' && o.elite && !o.elite.dead) { const near = st.enemies.filter(e => !e.dead && !e.structure && !e.hidden && e !== o.elite && m().dist(e, p) < 70); return near.length ? null : o.elite; }
    return null;
  }
  // 봇 위협: 바닥 위험(예고 중 포함)
  function threats(st, out) { for (const z of st.zones) if (z.type === 'hazard') out.push({ kind: 'zone', x: z.x, y: z.y, r: z.r }); }
  function text(st) { const S = spec(st); return S ? S.short : (st.objective === 'elite' ? '정예 처치' : '전멸'); }
  return { is, setup, update, check, onPlayerHit, zoneDamage, hud, autoTarget, botGoal, botTarget, threats, text, place };
})();
