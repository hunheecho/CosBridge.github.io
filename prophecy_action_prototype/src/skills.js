// 수동 기술: Q 감속장(레벨·변형) + E 선택 기술(5종, 레벨·변형). 기술 피해에는 무기 숙련이 적용되지 않는다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Skills = (function () {
  const m = () => PA.m;
  const K = () => PA.Combat;
  const TAU = Math.PI * 2;
  const alive = (st) => st.enemies.filter(e => !e.dead);
  const cdOf = (st, slot) => { const sk = st.build.skills[slot]; if (!sk) return 0; return PA.SKILLS[sk.id].cooldown[Math.min(3, sk.level) - 1] * st.build.skillCdMult - (slot === 'q' ? (st.build.accSpecialBonus || 0) : 0); };
  const sdmg = (st, slot) => { const sk = st.build.skills[slot]; const d = PA.SKILLS[sk.id]; return d.damage ? d.damage[Math.min(3, sk.level) - 1] : 0; };
  const hit = (st, e, dmg, opt) => K().damageEnemy(st, e, dmg, Object.assign({ src: { skill: true, direct: false, skillId: st.build.skills.e ? st.build.skills.e.id : 'e' } }, opt || {}));

  function init(st) { st.skillState = { storm: null, gravity: null, ward: null, target: null, field2: null }; st.player.eCd = 0; }

  // ---------- Q 감속장 ----------
  function castQ(st) {
    const p = st.player, cfg = PA.CONFIG.PLAYER.special, b = st.build, sk = b.skills.q, variant = sk && sk.variant;
    if (st.field) K().endField(st);
    const dur = cfg.duration * b.durationMult;
    if (variant === 'split') {
      st.field = { x: p.x, y: p.y, r: 100, ttl: dur, maxTtl: dur };
      const far = alive(st).filter(e => m().dist(e, p) > 60).sort((a, c) => m().dist(a, p) - m().dist(c, p))[0];
      st.skillState.field2 = far ? { x: far.x, y: far.y, r: 100, ttl: dur, maxTtl: dur } : null;
    } else st.field = { x: p.x, y: p.y, r: cfg.radius, ttl: dur, maxTtl: dur, follow: variant === 'follow' };
    p.special.cd = Math.max(1, cdOf(st, 'q')); st.stats.specialUses++;
    K().ev(st, 'special'); K().text(st, p.x, p.y - 50, '감속장', '#a9d8ff');
  }
  function onFieldEnd(st, f) { // 시간의 잔향
    const sk = st.build.skills.q;
    if (sk && sk.variant === 'echo') K().addZone(st, 'slowecho', f.x, f.y, f.r, 1.5, 0);
    if (st.skillState && st.skillState.field2) { st.skillState.field2 = null; }
  }
  function inField2(st, o) { const f = st.skillState && st.skillState.field2; return f && m().dist(f, o) <= f.r + (o.r || 0); }

  // ---------- E ----------
  function autoTarget(st, range) { const p = st.player, mk = st.markTarget; const inR = (e) => !e.dead && m().dist(p, e) <= range + e.r; if (mk && inR(mk)) return mk; const el = alive(st).filter(e => e.elite && inR(e)); if (el.length) return el[0]; let best = null, bd = Infinity; for (const e of alive(st)) { const d = m().dist(p, e); if (inR(e) && d < bd) { bd = d; best = e; } } return best; }
  function cluster(st, range) { const p = st.player, list = alive(st).filter(e => m().dist(p, e) <= range && !e.boss); if (!list.length) { const t = autoTarget(st, range); return t ? { x: t.x, y: t.y } : null; } let sx = 0, sy = 0; for (const e of list) { sx += e.x; sy += e.y; } return { x: sx / list.length, y: sy / list.length }; }
  function pushEnemy(st, e, dir, amount) { if (e.boss || e.airborne) return; K().moveSwept(st, e, dir.x * amount, dir.y * amount); if (e.state === 'dash') { e.state = 'recover'; e.stateT = 0; } }

  function castE(st) {
    const p = st.player, b = st.build, sk = b.skills.e; if (!sk) return false;
    const d = PA.SKILLS[sk.id], v = sk.variant, dmg = sdmg(st, 'e'), S = st.skillState;
    switch (sk.id) {
      case 'gust': {
        const ang = p.face;
        if (v === 'whirl') { K().fx(st, { kind: 'gust', x: p.x, y: p.y, r: 130, whirl: true, ttl: 0.3, t: 0 }); for (const e of alive(st)) if (m().dist(e, p) <= 130 + e.r) { hit(st, e, dmg); pushEnemy(st, e, m().norm(e.x - p.x, e.y - p.y), 140 + 30 * (sk.level - 1)); } }
        else { K().fx(st, { kind: 'gust', x: p.x, y: p.y, angle: ang, len: 170, w: 120, ttl: 0.3, t: 0 }); for (const e of alive(st)) if (m().inBeam(p, ang, 170, 120, e, e.r) && !K().losBlocked(st, p, e)) { hit(st, e, dmg); pushEnemy(st, e, { x: Math.cos(ang), y: Math.sin(ang) }, 140 + 30 * (sk.level - 1)); } }
        if (v === 'windpath') for (let i = 0; i <= 2; i++) { const pos = K().nearestValidPos(st, p.x + Math.cos(ang) * 55 * i, p.y + Math.sin(ang) * 55 * i, 0, 60); if (pos) K().addZone(st, 'windpath', pos.x, pos.y, 40, 3.0, 0); }
        break;
      }
      case 'bladestorm': S.storm = { x: p.x, y: p.y, t: 1.2, tick: 0, r: v === 'condensed' ? 70 : 110, dmg: dmg * (v === 'condensed' ? 1.8 : 1), advancing: v === 'advancing', dir: { x: Math.cos(p.face), y: Math.sin(p.face) } }; break;
      case 'strike': {
        const t = autoTarget(st, 260); if (!t) return false;
        const at = { x: t.x, y: t.y };
        K().fx(st, { kind: 'strikewarn', x: at.x, y: at.y, r: 45, ttl: 0.25, t: 0 });
        K().text(st, at.x, at.y - 30, '낙뢰', '#fff3a0');
        st.delayed.push({ t: 0.25, fn: () => { boltAt(st, at, 45, dmg); if (v === 'chain') { const others = alive(st).filter(e => m().dist(e, at) <= 150 && m().dist(e, at) > 20).slice(0, 2); for (const o of others) { const oa = { x: o.x, y: o.y }; st.delayed.push({ t: 0.15, fn: () => boltAt(st, oa, 40, dmg * 0.5) }); } } if (v === 'storm') { const z = K().addZone(st, 'storm', at.x, at.y, 50, 2.0, dmg * 0.3); z.tick = 0.5; } } });
        break;
      }
      case 'gravity': {
        const c = cluster(st, 260); if (!c) return false;
        S.gravity = { x: c.x, y: c.y, t: 1.2, hold: v === 'orbit' ? 1.0 : 0, r: 140, pull: 90 * d.pull[Math.min(3, sk.level) - 1], dps: dmg, tick: 0, collapse: v === 'collapse', dmg };
        break;
      }
      case 'ward': {
        const amt = d.shield[Math.min(3, sk.level) - 1];
        S.ward = { t: 4.0, amt, fortress: v === 'fortress', pulse: v === 'pulse', pulseT: 0 };
        p.wardShield = (p.wardShield || 0) + amt; p.shield += amt; p.shieldMax = Math.max(p.shieldMax, p.shield);
        K().fx(st, { kind: 'burst', x: p.x, y: p.y, r: 40, ttl: 0.3, t: 0, color: '#7ef2ff' });
        break;
      }
    }
    p.eCd = cdOf(st, 'e'); st.stats.eUses = (st.stats.eUses || 0) + 1;
    K().ev(st, 'skill_e', { id: sk.id }); K().text(st, p.x, p.y - 62, d.name, '#ffe9a8');
    if (b.bossRewards.includes('volley')) PA.Weapons.volley(st); // 추가 공격은 E 효과를 다시 일으키지 않는다(무기 공격만)
    return true;
  }
  function boltAt(st, at, r, dmg) { K().fx(st, { kind: 'strike', x: at.x, y: at.y, r, ttl: 0.3, t: 0 }); for (const e of alive(st)) if (m().dist(e, at) <= r + e.r) hit(st, e, dmg); K().ev(st, 'explode'); }

  function update(st, dt) {
    const p = st.player, S = st.skillState; if (!S) return;
    if (p.eCd > 0) p.eCd = Math.max(0, p.eCd - dt);
    if (st.field && st.field.follow) { st.field.x = p.x; st.field.y = p.y; }
    if (S.field2) { S.field2.ttl -= dt; if (S.field2.ttl <= 0) S.field2 = null; }
    // E 자동 목표 표시(낙뢰·중력핵)
    const sk = st.build.skills.e;
    if (sk && (sk.id === 'strike' || sk.id === 'gravity') && p.eCd <= 0) { const t = sk.id === 'strike' ? autoTarget(st, 260) : cluster(st, 260); S.target = t ? { x: t.x, y: t.y } : null; } else S.target = null;
    if (S.storm) { const s = S.storm; s.t -= dt; if (s.advancing) { s.x += s.dir.x * 150 * dt; s.y += s.dir.y * 150 * dt; } else { s.x = p.x; s.y = p.y; } s.tick -= dt; if (s.tick <= 0) { s.tick = 0.2; for (const e of alive(st)) if (m().dist(e, s) <= s.r + e.r) hit(st, e, s.dmg, { dir: m().norm(e.x - s.x, e.y - s.y), knock: 8 }); } if (s.t <= 0) S.storm = null; }
    if (S.gravity) { const g = S.gravity; g.t -= dt; const active = g.t > -g.hold; for (const e of alive(st)) { if (e.boss || e.airborne) continue; const dd = m().dist(e, g); if (dd <= g.r + e.r && dd > 8) { const n = m().norm(g.x - e.x, g.y - e.y); K().moveSwept(st, e, n.x * g.pull * dt, n.y * g.pull * dt); } } g.tick -= dt; if (g.tick <= 0 && g.t > 0) { g.tick = 0.25; for (const e of alive(st)) if (m().dist(e, g) <= g.r + e.r) hit(st, e, g.dps * 0.25); } if (!active) { if (g.collapse) { K().fx(st, { kind: 'burst', x: g.x, y: g.y, r: 100, ttl: 0.35, t: 0, color: '#c9a0ff' }); for (const e of alive(st)) if (m().dist(e, g) <= 100 + e.r) hit(st, e, g.dmg * 3, { dir: m().norm(e.x - g.x, e.y - g.y), knock: 60 }); K().ev(st, 'explode'); } S.gravity = null; } }
    if (S.ward) { const w = S.ward; w.t -= dt; if (w.fortress) for (const e of alive(st)) if (m().dist(e, p) <= 60 + e.r) pushEnemy(st, e, m().norm(e.x - p.x, e.y - p.y), 30 * dt); if (w.pulse) { w.pulseT -= dt; if (w.pulseT <= 0) { w.pulseT = 0.8; K().fx(st, { kind: 'spin', x: p.x, y: p.y, r: 110, ttl: 0.2, t: 0 }); for (const e of alive(st)) if (m().dist(e, p) <= 110 + e.r && !K().losBlocked(st, p, e)) hit(st, e, 8, { dir: m().norm(e.x - p.x, e.y - p.y), knock: 10 }); } } if (w.t <= 0) { const rest = Math.min(p.shield, p.wardShield || 0); p.shield -= rest; p.wardShield = 0; S.ward = null; } }
  }
  // 결계 보호막이 피해로 줄면 잔여량 추적
  function onShieldDamaged(st, used) { const p = st.player; if (p.wardShield) p.wardShield = Math.max(0, p.wardShield - used); }

  return { init, castQ, castE, update, onFieldEnd, inField2, autoTarget, cluster, cdOf, onShieldDamaged };
})();
