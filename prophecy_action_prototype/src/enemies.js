// 신규 기본 몬스터 8종(v0.6): 멧돼지·방패병·주술사·폭탄 운반체·잠복충·거미·서리술사·쌍날 도적.
// combat.js가 PA.Enemies.has(type)인 개체에 update를 호출한다. 공통 규칙: 준비(예고) → 확정 → 실행 → 빈틈. 이동 중 접촉 피해 없음.
// 상호작용: 감속장은 준비·실행·빈틈 진행(tf)을 늦추고, 냉기는 이동만 늦춘다. 넉백은 돌진·잠복·도약 중에는 무시(기존 규칙), 방패병은 50%.
// 면역(최소 범위): 잠복충 지하 구간은 직접 공격·투사체 대상이 되지 않는다(바닥 효과는 적용). 그 외 면역 없음.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Enemies = (function () {
  const m = () => PA.m;
  const K = () => PA.Combat;
  const TAU = Math.PI * 2;
  const deg = (d) => d * Math.PI / 180;
  const toRecover = (st, e, dur, label) => { e.state = 'recover'; e.stateT = 0; e.recoverDur = dur; if (label !== false) K().text(st, e.x, e.y - e.r - 26, '빈틈!', '#ffd166'); };
  const keepDistance = (st, e, d, dt, sm) => { // 궁수식 거리 유지(장애물 우회)
    const p = st.player, dist = m().dist(e, p);
    if (dist < d.keepMin) K().approach(st, e, e.x * 2 - p.x, e.y * 2 - p.y, d.speed * sm, dt);
    else if (dist > d.keepMax) K().approach(st, e, p.x, p.y, d.speed * sm, dt);
  };
  // 부채꼴 근접 판정(직접 공격: 장애물 가림 적용)
  function arcHit(st, e, ang, R, half, dmg, src) { const p = st.player; if (m().inArc(e, R, ang, half, p, p.r) && !K().losBlocked(st, e, p)) K().damagePlayer(st, dmg, src); }

  const H = {};
  // ---------- A. 멧돼지: 긴 직선 돌파 ----------
  H.boar = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    switch (e.state) {
      case 'approach':
        if (dist < d.minDist) { e.state = 'backoff'; e.stateT = 0; break; } // 너무 가까우면 물러나서 거리를 벌린 뒤 돌파(밀어붙이기 금지)
        K().approach(st, e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist && dist >= d.minDist && !K().losBlocked(st, e, p) && PA.Boss.dashPath(st, e, Math.atan2(p.y - e.y, p.x - e.x), d.chargeDist).len >= d.minDist && K().mayAttack(st, e, dt)) { e.state = 'charge_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); } // 코앞이 막혀 있으면 돌파하지 않는다
        break;
      case 'backoff': { // 최대 1.5초 뒤로 물러남(벽에 막히면 접선 방향). 거리가 벌어지면 접근 상태로
        e.stateT += dt; K().approach(st, e, e.x * 2 - p.x, e.y * 2 - p.y, d.speed * sm, dt);
        if (dist >= d.minDist + 40 || e.stateT >= 1.5) { e.state = 'approach'; e.stateT = 0; }
        break;
      }
      case 'charge_aim': {
        e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv;
        e.preview = PA.Boss.dashPath(st, e, e.aimAngle, d.chargeDist); // 예고와 실제가 같은 계산
        if (e.stateT >= d.aim && e.preview && e.preview.len < d.minDist) { e.state = 'approach'; e.stateT = 0; e.preview = null; break; } // 준비 중 통로가 막히면 돌파 취소
        if (e.stateT >= d.aim) { e.state = 'charge_lock'; e.stateT = 0; e.dir = e.aimAngle; const path = PA.Boss.dashPath(st, e, e.dir, d.chargeDist); e.chargeLen = path.len; e.chargeEnd = path.end; e.chargeBlocked = path.len < d.chargeDist - 1; e.chargeDist = 0; e.hitDone = false; K().ev(st, 'lock'); } // 통로가 장애물·벽에서 끊기면 그 끝에서 충돌(긴 빈틈)
        break;
      }
      case 'charge_lock': e.stateT += adv; if (e.stateT >= d.lock) { e.state = 'charge'; e.stateT = 0; K().noteAttack(st, e, 'execute'); } break;
      case 'charge': { // 거리 기준: 감속되어도 경로·거리 그대로. 장애물·벽에 닿으면 긴 빈틈
        const remain = Math.max(0, e.chargeLen - e.chargeDist), step = Math.min(d.chargeSpeed * tf * dt, remain), x0 = e.x, y0 = e.y;
        const mv = K().moveSwept(st, e, Math.cos(e.dir) * step, Math.sin(e.dir) * step);
        e.chargeDist += Math.hypot(e.x - x0, e.y - y0);
        if (!e.hitDone && m().segCircle(x0, y0, e.x, e.y, p, p.r + e.r)) { e.hitDone = true; e.biteT = 0; K().ev(st, 'bite'); K().damagePlayer(st, d.damage, 'boar'); }
        const done = e.chargeDist >= e.chargeLen - 1e-6 || step <= 1e-9;
        if (mv.hit || (done && e.chargeBlocked)) { e.state = 'stagger'; e.stateT = 0; K().text(st, e.x, e.y - e.r - 26, '충돌! 긴 빈틈', '#ffd166'); K().fx(st, { kind: 'impact', x: e.x + Math.cos(e.dir) * e.r, y: e.y + Math.sin(e.dir) * e.r, r: 40, ttl: 0.3, t: 0 }); K().ev(st, 'boss_land'); }
        else if (done) toRecover(st, e, d.recover);
        break;
      }
      case 'stagger': e.stateT += adv; if (e.stateT >= d.stun) { e.state = 'approach'; e.stateT = 0; } break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; } break;
    }
  };
  // ---------- B. 방패병: 정면 방어 ----------
  H.shieldbearer = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    if (e.face == null) e.face = Math.atan2(p.y - e.y, p.x - e.x);
    // 방향 전환은 즉시가 아니다: 초당 turnRate(감속장 안에서는 더 느리게)
    const want = Math.atan2(p.y - e.y, p.x - e.x), diff = m().angDiff(e.face, want), maxTurn = d.turnRate * adv;
    e.face += Math.max(-maxTurn, Math.min(maxTurn, diff));
    switch (e.state) {
      case 'approach':
        K().approach(st, e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist + e.r && Math.abs(diff) < deg(50) && K().mayAttack(st, e, dt)) { e.state = 'bash_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); }
        break;
      case 'bash_aim': e.stateT += adv; if (e.stateT >= d.aim) { e.state = 'bash'; e.stateT = 0; e.dir = e.face; K().moveSwept(st, e, Math.cos(e.dir) * d.lunge, Math.sin(e.dir) * d.lunge); arcHit(st, e, e.dir, d.bashRange, deg(d.bashDeg) / 2, d.damage, 'bash'); K().fx(st, { kind: 'arc', x: e.x, y: e.y, angle: e.dir, r: d.bashRange, half: deg(d.bashDeg) / 2, ttl: 0.18, t: 0, enemy: true }); K().noteAttack(st, e, 'execute'); K().ev(st, 'boss_sweep'); } break;
      case 'bash': e.stateT += adv; if (e.stateT >= 0.12) toRecover(st, e, d.recover); break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; } break;
    }
  };
  // 방패 판정: 방패가 닫혀 있고(접근·이동 중) 공격 출처가 정면 부채꼴 안이면 30%. 출처 위치가 없는 바닥·추가 효과는 정상 피해
  function shieldMult(st, e, opt) {
    if (e.type !== 'shieldbearer' || e.face == null) return 1;
    if (e.state === 'bash_aim' || e.state === 'bash' || e.state === 'recover') return 1; // 방패 열림
    const sr = opt.src || {};
    if (sr.direct === false || sr.extra || sr.skill || opt.dot) return 1; // 방패는 직접 공격(무기 본체·투사체)만 막는다. 바닥·추가·기술·지속 피해는 정상
    const from = opt.from || st.player;
    const a = Math.atan2(from.y - e.y, from.x - e.x);
    return Math.abs(m().angDiff(e.face, a)) <= deg(e.def.frontDeg) / 2 ? e.def.frontMult : 1;
  }
  // ---------- C. 주술사: 치료 시전(우선 처치 대상) ----------
  function healTarget(st, e) {
    const d = e.def; let best = null, bs = 0;
    for (const o of st.enemies) { if (o === e || o.dead || o.boss || (o.def && o.def.boss) || o.type === 'shaman' || o.hidden) continue; if (o.hp >= o.hpMax) continue; if (m().dist(o, e) > d.healRange) continue; const miss = 1 - o.hp / o.hpMax; if (miss > bs) { bs = miss; best = o; } }
    return best;
  }
  H.shaman = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    if (e.healT == null) { e.healT = 2.0; e.hexT = 1.5; }
    switch (e.state) {
      case 'approach': {
        keepDistance(st, e, d, dt, sm); e.healT -= dt; e.hexT -= dt;
        if (e.healT <= 0) { const t = healTarget(st, e); if (t && K().mayAttack(st, e, dt)) { e.state = 'cast'; e.stateT = 0; e.castTarget = t; e.readyT = null; K().noteAttack(st, e, 'prepare'); K().text(st, e.x, e.y - e.r - 26, '치료 시전', '#e9b6ff'); break; } }
        if (e.hexT <= 0 && dist <= d.keepMax + 40 && !K().losBlocked(st, e, p) && K().mayAttack(st, e, dt)) { e.state = 'hex_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); }
        break;
      }
      case 'cast': {
        const t = e.castTarget; e.stateT += adv;
        if (!t || t.dead || m().dist(t, e) > d.healRange + 40) { e.castTarget = null; e.healT = d.healInterval * 0.5; toRecover(st, e, 0.6, false); break; }
        if (e.stateT >= d.healCast) { const before = t.hp; t.hp = Math.min(t.hpMax, t.hp + t.hpMax * d.healRatio); const amt = t.hp - before; st.metrics.heals++; st.metrics.healAmount += amt; K().text(st, t.x, t.y - t.r - 22, '+' + Math.round(amt), '#9cffb0'); K().fx(st, { kind: 'burst', x: t.x, y: t.y, r: t.r + 14, ttl: 0.3, t: 0, color: '#e9b6ff' }); K().ev(st, 'orb'); K().noteAttack(st, e, 'execute'); e.healT = d.healInterval; e.castTarget = null; toRecover(st, e, d.recover); }
        break;
      }
      case 'hex_aim': e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv; if (e.stateT >= d.hexAim) { e.dir = e.aimAngle; st.projectiles.push({ owner: 'enemy', kind: 'hex', x: e.x + Math.cos(e.dir) * (e.r + 4), y: e.y + Math.sin(e.dir) * (e.r + 4), vx: Math.cos(e.dir) * d.hexSpeed, vy: Math.sin(e.dir) * d.hexSpeed, r: d.hexR, dmg: d.hexDamage, ttl: 4, angle: e.dir }); K().ev(st, 'shoot'); K().noteAttack(st, e, 'execute'); e.hexT = d.hexInterval; toRecover(st, e, d.recover, false); } break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; } break;
    }
  };
  // 시전 방해: 12 이상 한 방 또는 넉백(20 이상)이면 끊긴다. 처치는 당연히 끊는다.
  function onDamaged(st, e, dmg, opt) {
    if (e.type === 'shaman' && e.state === 'cast' && (dmg >= e.def.interruptDamage || (opt.knock || 0) >= 20)) { e.castTarget = null; e.healT = e.def.healInterval * 0.5; st.metrics.interrupts++; K().text(st, e.x, e.y - e.r - 40, '시전 중단!', '#7ef2ff'); toRecover(st, e, 1.0); }
  }
  // ---------- D. 폭탄 운반체 ----------
  H.bomber = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    switch (e.state) {
      case 'approach': K().approach(st, e, p.x, p.y, d.speed * sm, dt); if (dist <= d.engageDist + e.r && K().mayAttack(st, e, dt)) { e.state = 'fuse'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); K().ev(st, 'lock'); } break;
      case 'fuse': // 멈춰 서서 준비. 넉백으로 밀리면 표시 원도 같이 움직인다(실제 범위 = 표시 범위)
        e.stateT += adv;
        if (e.stateT >= d.fuse) { K().noteAttack(st, e, 'execute'); if (dist <= d.blastR + p.r) K().damagePlayer(st, d.damage, 'blast'); K().fx(st, { kind: 'mineburst', x: e.x, y: e.y, r: d.blastR, ttl: 0.4, t: 0 }); K().ev(st, 'explode'); e.exploded = true; e.hp = 0; e.dead = true; e.deathT = 0; e.acted = true; if (st.metrics) K().metricsFor(st, e).exploded = (K().metricsFor(st, e).exploded || 0) + 1; }
        break;
    }
  };
  // ---------- E. 잠복충 ----------
  H.burrower = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    if (e.burrowCd == null) e.burrowCd = 1.0;
    if (e.state !== 'under' && e.state !== 'dive' && e.state !== 'warn') e.burrowCd -= dt;
    switch (e.state) {
      case 'approach':
        K().approach(st, e, p.x, p.y, d.speed * sm, dt);
        if (dist <= d.engageDist && e.burrowCd <= 0 && K().mayAttack(st, e, dt)) { e.state = 'dive'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); }
        else if (dist <= d.biteRange + e.r && K().mayAttack(st, e, dt)) { e.state = 'bite_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); }
        break;
      case 'dive': e.stateT += adv; if (e.stateT >= d.dive) { e.state = 'under'; e.stateT = 0; e.hidden = true; } break;
      case 'under': { // 짧은 지하 이동(플레이어 추적 허용). 끝나면 출현 지점 확정(지형 안 금지)
        e.stateT += adv; const n = m().norm(p.x - e.x, p.y - e.y); K().moveSwept(st, e, n.x * d.underSpeed * sm * dt, n.y * d.underSpeed * sm * dt, true);
        if (e.stateT >= d.under || dist < 30) { const pos = K().nearestValidPos(st, e.x, e.y, e.r, 200) || { x: e.x, y: e.y }; e.emergeAt = pos; e.state = 'warn'; e.stateT = 0; K().ev(st, 'lock'); }
        break;
      }
      case 'warn': e.stateT += adv; if (e.stateT >= d.warn) { e.x = e.emergeAt.x; e.y = e.emergeAt.y; e.hidden = false; e.state = 'emerge'; e.stateT = 0; K().noteAttack(st, e, 'execute'); if (m().dist(e, p) <= d.emergeR + p.r) K().damagePlayer(st, d.damage, 'emerge'); K().fx(st, { kind: 'bossland', x: e.x, y: e.y, r: d.emergeR, ttl: 0.4, t: 0 }); K().ev(st, 'boss_land'); e.burrowCd = d.cooldown; } break;
      case 'emerge': e.stateT += adv; if (e.stateT >= 0.15) { e.state = 'stagger'; e.stateT = 0; K().text(st, e.x, e.y - e.r - 26, '빈틈!', '#ffd166'); } break;
      case 'stagger': e.stateT += adv; if (e.stateT >= d.exposed) { e.state = 'approach'; e.stateT = 0; } break;
      case 'bite_aim': e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv; if (e.stateT >= d.biteAim) { e.dir = e.aimAngle; arcHit(st, e, e.dir, d.biteRange + e.r, deg(d.biteDeg) / 2, d.biteDamage, 'bite'); e.biteT = 0; K().noteAttack(st, e, 'execute'); toRecover(st, e, d.biteRecover); } break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; } break;
    }
  };
  // ---------- F. 거미 ----------
  function webCount(st) { return st.zones.filter(z => z.type === 'web').length; }
  H.spider = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    if (e.webT == null) e.webT = 1.2;
    switch (e.state) {
      case 'approach': {
        if (e.webT > 1.5) K().approach(st, e, p.x, p.y, d.speed * sm, dt); else keepDistance(st, e, d, dt, sm); // 거미줄 직전에만 거리를 두고, 그 외에는 물려고 다가온다
        e.webT -= dt;
        if (dist <= d.biteRange + e.r && K().mayAttack(st, e, dt)) { e.state = 'bite_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); break; }
        if (e.webT <= 0 && dist <= d.keepMax + 60 && K().mayAttack(st, e, dt)) { // 플레이어 진행 방향 앞(70)에 예고. 예고 위치는 시작 때 확정
          const ahead = { x: p.x + Math.cos(p.face) * 70, y: p.y + Math.sin(p.face) * 70 };
          const pos = K().nearestValidPos(st, ahead.x, ahead.y, 0, 120) || { x: p.x, y: p.y };
          e.webAt = pos; e.state = 'web_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare');
        }
        break;
      }
      case 'web_aim': e.stateT += adv; if (e.stateT >= d.webAim) { while (webCount(st) >= d.maxWebs) { const idx = st.zones.findIndex(z => z.type === 'web'); st.zones.splice(idx, 1); } const z = K().addZone(st, 'web', e.webAt.x, e.webAt.y, d.webR, d.webTtl, 0); z.slow = d.webSlow; st.metrics.webs++; K().noteAttack(st, e, 'execute'); e.webT = d.webInterval; K().ev(st, 'spore'); toRecover(st, e, 0.5, false); } break;
      case 'bite_aim': e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv; if (e.stateT >= d.biteAim) { e.dir = e.aimAngle; arcHit(st, e, e.dir, d.biteRange + e.r, deg(d.biteDeg) / 2, d.biteDamage, 'bite'); e.biteT = 0; K().noteAttack(st, e, 'execute'); toRecover(st, e, d.recover); } break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; } break;
    }
  };
  // ---------- G. 서리술사 ----------
  H.frostcaller = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    if (e.castT == null) e.castT = 1.5;
    switch (e.state) {
      case 'approach': {
        keepDistance(st, e, d, dt, sm); e.castT -= dt;
        if (e.castT <= 0 && dist <= d.keepMax + 60 && K().mayAttack(st, e, dt)) { // 위치는 시전 시작 때 확정: 플레이어 위치 + 진행 방향으로 3개
          const ang = p.moving ? p.face : st.rng.range(0, TAU); const pts = [];
          for (let i = 0; i < 3; i++) { const x = p.x + Math.cos(ang) * d.spacing * i, y = p.y + Math.sin(ang) * d.spacing * i; pts.push(K().nearestValidPos(st, Math.max(20, Math.min(st.arena.w - 20, x)), Math.max(20, Math.min(st.arena.h - 20, y)), 0, 120) || { x: p.x, y: p.y }); }
          e.castPts = pts; e.state = 'cast'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); K().ev(st, 'lock');
        }
        break;
      }
      case 'cast': e.stateT += adv; if (e.stateT >= d.castAim) { e.castPts.forEach((pt, i) => { const z = K().addZone(st, 'frostzone', pt.x, pt.y, d.zoneR, d.delays[i], 0); z.order = i + 1; z.dmg = d.damage; z.owner = e; }); K().noteAttack(st, e, 'execute'); e.castT = d.castInterval; e.castPts = null; toRecover(st, e, d.recover); } break;
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; } break;
    }
  };
  // 서리 영역 폭발(combat.updateZones가 ttl 소진 직전에 호출). 회피 무적·피격 보호 적용(damagePlayer)
  function detonate(st, z) {
    const p = st.player;
    if (z.type === 'frostzone') { K().fx(st, { kind: 'frostburst', x: z.x, y: z.y, r: z.r, ttl: 0.35, t: 0 }); K().ev(st, 'shatter'); if (m().dist(z, p) <= z.r + p.r) K().damagePlayer(st, z.dmg, 'frostzone'); }
  }
  // ---------- H. 쌍날 도적 ----------
  H.rogue = function (st, e, dt) {
    const d = e.def, p = st.player, tf = K().timeFactor(st, e), sm = K().enemySpeedMult(st, e), adv = dt * tf, dist = m().dist(e, p);
    if (!e.side) e.side = st.rng.next() < 0.5 ? -1 : 1;
    switch (e.state) {
      case 'approach': {
        if (dist > d.flankDist) K().approach(st, e, p.x, p.y, d.speed * sm, dt);
        else { const n = m().norm(p.x - e.x, p.y - e.y); const tx = p.x - n.x * 30 + (-n.y) * e.side * d.flankOffset, ty = p.y - n.y * 30 + n.x * e.side * d.flankOffset; K().approach(st, e, tx, ty, d.speed * sm, dt); }
        if (dist <= d.engageDist + e.r && K().mayAttack(st, e, dt)) { e.state = 'slash1_aim'; e.stateT = 0; e.readyT = null; K().noteAttack(st, e, 'prepare'); }
        break;
      }
      case 'slash1_aim': e.aimAngle = Math.atan2(p.y - e.y, p.x - e.x); e.stateT += adv; if (e.stateT >= d.aim1) { e.dir = e.aimAngle; slash(st, e, d); e.state = 'slash2_aim'; e.stateT = 0; e.baseDir = e.dir; e.aimAngle = e.dir; } break;
      case 'slash2_aim': { // 두 번째 베기: 첫 방향에서 ±adjust 안에서만 보정
        const want = Math.atan2(p.y - e.y, p.x - e.x), lim = deg(d.adjustDeg); e.aimAngle = e.baseDir + Math.max(-lim, Math.min(lim, m().angDiff(e.baseDir, want)));
        e.stateT += adv; if (e.stateT >= d.aim2) { e.dir = e.aimAngle; slash(st, e, d); toRecover(st, e, d.recover); }
        break;
      }
      case 'recover': e.stateT += adv; if (e.stateT >= e.recoverDur) { e.state = 'approach'; e.stateT = 0; e.side = -e.side; } break;
    }
  };
  function slash(st, e, d) { arcHit(st, e, e.dir, d.slashRange + e.r, deg(d.slashDeg) / 2, d.damage, 'slash'); K().fx(st, { kind: 'arc', x: e.x, y: e.y, angle: e.dir, r: d.slashRange + e.r, half: deg(d.slashDeg) / 2, ttl: 0.14, t: 0, enemy: true }); e.biteT = 0; K().noteAttack(st, e, 'execute'); K().ev(st, 'boss_sweep'); }

  // ---------- 공용 ----------
  const COMMITTED = { boar: ['charge_aim', 'charge_lock', 'charge'], shieldbearer: ['bash_aim', 'bash'], shaman: ['cast', 'hex_aim'], bomber: ['fuse'], burrower: ['dive', 'under', 'warn', 'emerge', 'bite_aim'], spider: ['web_aim', 'bite_aim'], frostcaller: ['cast'], rogue: ['slash1_aim', 'slash2_aim'] };
  function isCommitted(e) { const c = COMMITTED[e.type]; return !!c && c.includes(e.state); }
  function has(type) { return !!H[type]; }
  function update(st, e, dt) { H[e.type](st, e, dt); }
  // 봇용 위협 도형(화면에 보이는 예고와 같은 정보만)
  function threats(st, e, out) {
    const d = e.def, p = st.player;
    if (e.type === 'boar') { if (e.state === 'charge_aim' && e.preview) out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.aimAngle, len: e.preview.len + 30, w: (e.r + p.r) * 2 + 30, prog: e.stateT / d.aim, locked: false }); else if (e.state === 'charge_lock' || e.state === 'charge') out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.dir, len: (e.chargeLen || d.chargeDist) + 30, w: (e.r + p.r) * 2 + 30, prog: 1, locked: true }); }
    else if (e.type === 'shieldbearer' && e.state === 'bash_aim') out.push({ kind: 'arc', e, x: e.x, y: e.y, ang: e.face, r: d.bashRange + d.lunge + 20, half: deg(d.bashDeg) / 2 + 0.2, prog: e.stateT / d.aim, locked: e.stateT / d.aim > 0.6 });
    else if (e.type === 'shaman' && e.state === 'hex_aim') out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.aimAngle, len: 2000, w: 40, prog: e.stateT / d.hexAim, locked: e.stateT / d.hexAim > 0.7 });
    else if (e.type === 'bomber' && e.state === 'fuse') out.push({ kind: 'circle', e, x: e.x, y: e.y, r: d.blastR, prog: e.stateT / d.fuse, locked: true });
    else if (e.type === 'burrower' && e.state === 'warn' && e.emergeAt) out.push({ kind: 'circle', e, x: e.emergeAt.x, y: e.emergeAt.y, r: d.emergeR, prog: e.stateT / d.warn, locked: true });
    else if (e.type === 'burrower' && e.state === 'bite_aim') out.push({ kind: 'arc', e, x: e.x, y: e.y, ang: e.aimAngle, r: d.biteRange + e.r + 10, half: deg(d.biteDeg) / 2 + 0.2, prog: e.stateT / d.biteAim, locked: e.stateT / d.biteAim > 0.6 });
    else if (e.type === 'spider' && e.state === 'bite_aim') out.push({ kind: 'arc', e, x: e.x, y: e.y, ang: e.aimAngle, r: d.biteRange + e.r + 10, half: deg(d.biteDeg) / 2 + 0.2, prog: e.stateT / d.biteAim, locked: e.stateT / d.biteAim > 0.6 });
    else if (e.type === 'rogue' && (e.state === 'slash1_aim' || e.state === 'slash2_aim')) out.push({ kind: 'arc', e, x: e.x, y: e.y, ang: e.aimAngle, r: d.slashRange + e.r + 10, half: deg(d.slashDeg) / 2 + 0.2, prog: e.stateT / (e.state === 'slash1_aim' ? d.aim1 : d.aim2), locked: e.stateT / (e.state === 'slash1_aim' ? d.aim1 : d.aim2) > 0.5 });
  }
  function zoneThreats(st, out) { for (const z of st.zones) { if (z.type === 'frostzone') out.push({ kind: 'circle', x: z.x, y: z.y, r: z.r, prog: 1 - z.ttl / z.maxTtl, locked: z.ttl < 0.45 }); else if (z.type === 'web') out.push({ kind: 'zone', x: z.x, y: z.y, r: z.r, web: true }); } }
  return { HANDLERS: H, has, update, isCommitted, threats, zoneThreats, shieldMult, onDamaged, detonate, healTarget, webCount, COMMITTED };
})();
