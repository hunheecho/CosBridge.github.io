// 전투 캔버스 렌더러. 시뮬레이션 상태만 읽는다. 디버그 표시는 opts.debug일 때만.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Render = (function () {
  const FONT = "'Noto Sans KR', 'Malgun Gothic', 'Apple SD Gothic Neo', sans-serif";
  const TAU = Math.PI * 2;

  function drawGround(ctx, st) {
    const a = st.arena;
    ctx.fillStyle = '#1b2128'; ctx.fillRect(0, 0, a.w, a.h);
    ctx.strokeStyle = 'rgba(255,255,255,0.04)'; ctx.lineWidth = 1;
    for (let x = 0; x <= a.w; x += 60) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, a.h); ctx.stroke(); }
    for (let y = 0; y <= a.h; y += 60) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(a.w, y); ctx.stroke(); }
    ctx.strokeStyle = 'rgba(255,255,255,0.18)'; ctx.lineWidth = 3; ctx.strokeRect(1.5, 1.5, a.w - 3, a.h - 3);
  }

  function drawZones(ctx, st) {
    for (const z of st.zones) {
      const life = z.ttl / z.maxTtl;
      if (z.type === 'spore') {
        ctx.fillStyle = `rgba(170,90,230,${0.18 + 0.2 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(210,150,255,${0.5 + 0.3 * life})`; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.stroke(); ctx.setLineDash([]);
        for (let i = 0; i < 5; i++) { const ang = z.t * 0.8 + i * 1.3, rr = z.r * (0.3 + 0.5 * ((i * 0.37 + z.t * 0.2) % 1)); ctx.fillStyle = 'rgba(230,190,255,0.5)'; ctx.beginPath(); ctx.arc(z.x + Math.cos(ang) * rr, z.y + Math.sin(ang) * rr, 4, 0, TAU); ctx.fill(); }
        // 위험 아이콘: 해골 대신 삼각 경고
        ctx.fillStyle = 'rgba(255,255,255,0.7)'; ctx.font = `bold 14px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('☠', z.x, z.y + 5);
      } else if (z.type === 'fire') {
        const fl = 1 + 0.15 * Math.sin(z.t * 20);
        ctx.fillStyle = `rgba(255,120,30,${0.25 + 0.25 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r * fl, 0, TAU); ctx.fill();
        ctx.fillStyle = `rgba(255,220,90,${0.5 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r * 0.5 * fl, 0, TAU); ctx.fill();
      }
    }
    if (st.field) {
      const f = st.field, life = f.ttl / f.maxTtl;
      ctx.fillStyle = 'rgba(120,190,255,0.14)'; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.fill();
      ctx.strokeStyle = 'rgba(160,220,255,0.8)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, -Math.PI / 2, -Math.PI / 2 + TAU * life); ctx.stroke();
      // 시계 아이콘
      ctx.strokeStyle = 'rgba(200,235,255,0.9)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(f.x, f.y - f.r - 14, 8, 0, TAU); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(f.x, f.y - f.r - 14); ctx.lineTo(f.x, f.y - f.r - 20); ctx.lineTo(f.x + 4, f.y - f.r - 20); ctx.stroke();
    }
  }

  function drawChest(ctx, st) {
    const c = st.chest; if (!c) return;
    if (c.opened && c.t > 0.6) return;
    const bob = c.opened ? 0 : Math.sin(st.t * 4) * 2;
    ctx.fillStyle = c.opened ? '#8a6b2f' : '#c9973a'; ctx.fillRect(c.x - 14, c.y - 10 + bob, 28, 20);
    ctx.fillStyle = '#5b3f14'; ctx.fillRect(c.x - 14, c.y - 12 + bob, 28, 6);
    ctx.fillStyle = '#ffe9a8'; ctx.fillRect(c.x - 3, c.y - 4 + bob, 6, 6);
    if (!c.opened) { ctx.fillStyle = '#ffd166'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('보급 상자', c.x, c.y - 20 + bob); }
  }

  function drawPlayerEffects(ctx, st) {
    for (const f of st.effects) {
      const k = 1 - f.t / f.ttl;
      if (f.kind === 'arc') {
        ctx.fillStyle = `rgba(140,200,255,${0.35 * k})`; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.arc(f.x, f.y, f.r, f.angle - f.half, f.angle + f.half); ctx.closePath(); ctx.fill();
        ctx.strokeStyle = `rgba(220,240,255,${0.8 * k})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.6 + 0.4 * (1 - k)), f.angle - f.half, f.angle + f.half); ctx.stroke();
      } else if (f.kind === 'beam') {
        ctx.save(); ctx.translate(f.x, f.y); ctx.rotate(f.angle);
        ctx.fillStyle = `rgba(160,220,255,${0.4 * k})`; ctx.fillRect(0, -f.w / 2, f.len, f.w);
        ctx.fillStyle = `rgba(255,255,255,${0.7 * k})`; ctx.fillRect(0, -2, f.len, 4);
        ctx.restore();
      } else if (f.kind === 'spin') {
        ctx.strokeStyle = `rgba(200,230,255,${0.8 * k})`; ctx.lineWidth = 6 * k + 2; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.7 + 0.3 * (1 - k)), 0, TAU); ctx.stroke();
        ctx.fillStyle = `rgba(140,200,255,${0.2 * k})`; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.fill();
      }
    }
  }

  function statusIcon(ctx, x, y, kind) {
    ctx.lineWidth = 2;
    if (kind === 'chill') { ctx.strokeStyle = '#9fe8ff'; for (let i = 0; i < 3; i++) { const a = i * Math.PI / 3; ctx.beginPath(); ctx.moveTo(x - Math.cos(a) * 6, y - Math.sin(a) * 6); ctx.lineTo(x + Math.cos(a) * 6, y + Math.sin(a) * 6); ctx.stroke(); } }
    if (kind === 'mark') { ctx.strokeStyle = '#ff5a5a'; ctx.beginPath(); ctx.arc(x, y, 6, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.moveTo(x - 9, y); ctx.lineTo(x + 9, y); ctx.moveTo(x, y - 9); ctx.lineTo(x, y + 9); ctx.stroke(); }
    if (kind === 'exposed') { ctx.fillStyle = '#ffd166'; ctx.beginPath(); for (let i = 0; i < 5; i++) { const a = -Math.PI / 2 + i * TAU / 5, b = a + TAU / 10; ctx.lineTo(x + Math.cos(a) * 7, y + Math.sin(a) * 7); ctx.lineTo(x + Math.cos(b) * 3, y + Math.sin(b) * 3); } ctx.closePath(); ctx.fill(); }
    if (kind === 'slow') { ctx.strokeStyle = '#a9d8ff'; ctx.beginPath(); ctx.arc(x, y, 6, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y - 4); ctx.lineTo(x + 3, y - 4); ctx.stroke(); }
  }

  function drawEnemy(ctx, st, e) {
    const d = e.def;
    if (e.dead) return;
    const inField = PA.Combat.inField(st, e);
    ctx.save(); ctx.translate(e.x, e.y);
    let sx = 1, sy = 1, ang = 0;
    if (e.type === 'wolf' || e.type === 'wolf_alpha') {
      ang = e.state === 'approach' ? Math.atan2(st.player.y - e.y, st.player.x - e.x) : (e.state === 'crouch' ? e.aimAngle : e.dir);
      if (e.state === 'crouch') { sx = 1.15; sy = 0.7 + 0.1 * Math.sin(e.stateT * 30); }
      if (e.state === 'lock') { sx = 0.8; sy = 0.75; }
      if (e.state === 'dash') { sx = 1.5; sy = 0.7; for (let i = 1; i <= 2; i++) { ctx.fillStyle = `rgba(200,200,210,${0.25 / i})`; ctx.beginPath(); ctx.ellipse(-Math.cos(ang) * 14 * i, -Math.sin(ang) * 14 * i, e.r * 1.3, e.r * 0.7, ang, 0, TAU); ctx.fill(); } }
      if (e.state === 'recover') { ang += Math.sin(e.stateT * 12) * 0.25; sy = 0.9; }
      if (e.state === 'approach') sy = 1 + 0.08 * Math.sin(e.animT * 14);
      ctx.rotate(ang); ctx.scale(sx, sy);
      ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#b9d8e8' : d.color);
      ctx.beginPath(); ctx.ellipse(0, 0, e.r * 1.2, e.r * 0.85, 0, 0, TAU); ctx.fill();
      // 머리와 귀
      ctx.beginPath(); ctx.arc(e.r * 0.9, 0, e.r * 0.55, 0, TAU); ctx.fill();
      ctx.fillStyle = e.flash > 0 ? '#fff' : '#6a6f78'; ctx.beginPath(); ctx.moveTo(e.r * 0.7, -e.r * 0.5); ctx.lineTo(e.r * 1.1, -e.r * 0.9); ctx.lineTo(e.r * 1.2, -e.r * 0.3); ctx.fill();
      ctx.beginPath(); ctx.moveTo(e.r * 0.7, e.r * 0.5); ctx.lineTo(e.r * 1.1, e.r * 0.9); ctx.lineTo(e.r * 1.2, e.r * 0.3); ctx.fill();
      ctx.fillStyle = '#ff4d4d'; ctx.beginPath(); ctx.arc(e.r * 1.15, -e.r * 0.15, 2.5, 0, TAU); ctx.fill();
      if (e.elite) { ctx.strokeStyle = '#ffe066'; ctx.lineWidth = 3; ctx.beginPath(); ctx.ellipse(0, 0, e.r * 1.25, e.r * 0.9, 0, 0, TAU); ctx.stroke(); }
    } else if (e.type === 'archer') {
      const toP = Math.atan2(st.player.y - e.y, st.player.x - e.x);
      ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#b9e8d0' : d.color);
      ctx.beginPath(); ctx.arc(0, 0, e.r, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2e5a2c'; ctx.beginPath(); ctx.arc(0, -e.r * 0.4, e.r * 0.55, Math.PI, 0); ctx.fill();
      // 활
      const pull = e.state === 'aim' ? Math.min(1, e.stateT / d.aim) : (e.state === 'lock' ? 1 : 0);
      const ba = e.state === 'aim' ? e.aimAngle : (e.state === 'lock' ? e.dir : toP);
      ctx.save(); ctx.rotate(ba); ctx.strokeStyle = '#d9b26f'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(e.r * 0.6, 0, e.r * 0.9, -1.2, 1.2); ctx.stroke();
      ctx.strokeStyle = '#eee'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(e.r * 0.6 + Math.cos(-1.2) * e.r * 0.9, Math.sin(-1.2) * e.r * 0.9); ctx.lineTo(e.r * 0.6 - pull * 10, 0); ctx.lineTo(e.r * 0.6 + Math.cos(1.2) * e.r * 0.9, Math.sin(1.2) * e.r * 0.9); ctx.stroke();
      ctx.restore();
    } else if (e.type === 'spore') {
      const sw = e.state === 'swell' ? 1 + 0.4 * (e.stateT / d.swell) : (e.state === 'recover' ? 0.85 : 1 + 0.05 * Math.sin(e.animT * 6));
      ctx.scale(sw, sw);
      ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#c9b3e8' : d.color);
      ctx.beginPath(); ctx.arc(0, 0, e.r, 0, TAU); ctx.fill();
      for (let i = 0; i < 6; i++) { const a = i * TAU / 6 + e.animT * 0.5; ctx.beginPath(); ctx.arc(Math.cos(a) * e.r * 0.85, Math.sin(a) * e.r * 0.85, e.r * 0.35, 0, TAU); ctx.fill(); }
      ctx.fillStyle = '#3a1d55'; ctx.beginPath(); ctx.arc(-5, -3, 3, 0, TAU); ctx.arc(5, -3, 3, 0, TAU); ctx.fill();
    }
    ctx.restore();
    // 체력 바 (피해를 입었을 때만)
    if (e.hp < e.hpMax) { const w = e.r * 2.4; ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(e.x - w / 2, e.y - e.r - 12, w, 5); ctx.fillStyle = e.elite ? '#ffe066' : '#ff6b6b'; ctx.fillRect(e.x - w / 2, e.y - e.r - 12, w * Math.max(0, e.hp / e.hpMax), 5); }
    // 상태 아이콘
    let ix = e.x - 10, iy = e.y - e.r - 24;
    if (e.state === 'recover') { statusIcon(ctx, ix, iy, 'exposed'); ix += 16; }
    if (e.chill > 0) { statusIcon(ctx, ix, iy, 'chill'); ix += 16; }
    if (inField) { statusIcon(ctx, ix, iy, 'slow'); ix += 16; }
    if (st.markTarget === e) { statusIcon(ctx, e.x, e.y - e.r - 40, 'mark'); }
    if (e.stasis > 0) { for (let i = 0; i < e.stasis; i++) { ctx.fillStyle = '#a9d8ff'; ctx.fillRect(e.x - 12 + i * 6, e.y + e.r + 6, 4, 6); } }
    if (e.elite) { ctx.fillStyle = '#ffe066'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('정예 · ' + e.name, e.x, e.y + e.r + 18); }
  }

  function drawTelegraphs(ctx, st) {
    const a = st.arena;
    for (const e of st.enemies) {
      if (e.dead) continue;
      const d = e.def;
      if ((e.type === 'wolf' || e.type === 'wolf_alpha') && (e.state === 'crouch' || e.state === 'lock')) {
        const ang = e.state === 'crouch' ? e.aimAngle : e.dir;
        const L = d.dashSpeed * d.dashTime;
        const locked = e.state === 'lock';
        const alpha = locked ? (0.7 + 0.3 * Math.sin(st.t * 60)) : 0.45 + 0.3 * (e.stateT / d.crouch);
        ctx.save(); ctx.translate(e.x, e.y); ctx.rotate(ang);
        ctx.fillStyle = `rgba(255,70,70,${alpha * 0.35})`; ctx.fillRect(0, -(e.r + st.player.r) , L, (e.r + st.player.r) * 2);
        ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2;
        ctx.beginPath(); ctx.moveTo(e.r, 0); ctx.lineTo(L - 12, 0); ctx.stroke();
        ctx.fillStyle = `rgba(255,80,80,${alpha})`; ctx.beginPath(); ctx.moveTo(L, 0); ctx.lineTo(L - 16, -9); ctx.lineTo(L - 16, 9); ctx.closePath(); ctx.fill();
        ctx.restore();
        if (locked) { ctx.fillStyle = '#ff7070'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', e.x, e.y - e.r - 28); }
      }
      if (e.type === 'archer' && (e.state === 'aim' || e.state === 'lock')) {
        const ang = e.state === 'aim' ? e.aimAngle : e.dir, locked = e.state === 'lock';
        const L = Math.hypot(a.w, a.h);
        ctx.strokeStyle = locked ? `rgba(255,80,80,${0.8 + 0.2 * Math.sin(st.t * 60)})` : `rgba(255,120,120,${0.35 + 0.35 * (e.stateT / d.aim)})`;
        ctx.lineWidth = locked ? 3 : 1.5; if (!locked) ctx.setLineDash([8, 6]);
        ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.lineTo(e.x + Math.cos(ang) * L, e.y + Math.sin(ang) * L); ctx.stroke(); ctx.setLineDash([]);
        if (locked) { ctx.fillStyle = '#ff7070'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', e.x, e.y - e.r - 20); }
      }
      if (e.type === 'spore' && e.state === 'swell') {
        const k = e.stateT / d.swell, r = d.cloudR * (0.3 + 0.7 * k);
        ctx.fillStyle = `rgba(200,100,255,${0.15 + 0.2 * k})`; ctx.beginPath(); ctx.arc(e.x, e.y, r, 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(255,120,255,${0.5 + 0.5 * k})`; ctx.lineWidth = 2 + 2 * k; ctx.beginPath(); ctx.arc(e.x, e.y, d.cloudR, 0, TAU); ctx.stroke();
      }
    }
    for (const f of st.effects) if (f.kind === 'spawnwarn') {
      const k = f.t / f.ttl; ctx.strokeStyle = `rgba(255,200,80,${0.4 + 0.6 * k})`; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(f.x, f.y, 18 * (1 - k) + 6, 0, TAU); ctx.stroke();
      ctx.fillStyle = 'rgba(255,200,80,0.9)'; ctx.font = `12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(PA.ENEMIES[f.type].name, f.x, f.y - 24);
    }
  }

  function drawProjectiles(ctx, st) {
    for (const p of st.projectiles) {
      if (p.kind === 'arrow') { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.angle); ctx.strokeStyle = '#ffd9a0'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-14, 0); ctx.lineTo(8, 0); ctx.stroke(); ctx.fillStyle = '#ff6b6b'; ctx.beginPath(); ctx.moveTo(12, 0); ctx.lineTo(4, -4); ctx.lineTo(4, 4); ctx.fill(); ctx.restore(); }
      else { ctx.fillStyle = '#bfefff'; ctx.beginPath(); ctx.arc(p.x, p.y, 4, 0, TAU); ctx.fill(); }
    }
  }

  function drawPlayer(ctx, st) {
    const p = st.player, b = st.build;
    // 사거리 표시(옅게)
    ctx.strokeStyle = 'rgba(140,200,255,0.18)'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]);
    if (b.weapon.form === 'beam') { ctx.beginPath(); ctx.arc(p.x, p.y, b.range, 0, TAU); ctx.stroke(); }
    else { ctx.beginPath(); ctx.arc(p.x, p.y, b.range, 0, TAU); ctx.stroke(); }
    ctx.setLineDash([]);
    if (p.dodge.active) for (let i = 1; i <= 3; i++) { ctx.fillStyle = `rgba(120,190,255,${0.25 / i})`; ctx.beginPath(); ctx.arc(p.x - p.dodge.dx * 12 * i, p.y - p.dodge.dy * 12 * i, p.r, 0, TAU); ctx.fill(); }
    const blink = p.hitProt > 0 && Math.floor(st.t * 20) % 2 === 0;
    ctx.save(); ctx.translate(p.x, p.y);
    if (blink) ctx.globalAlpha = 0.45;
    const bob = p.moving ? Math.sin(p.animT * 16) * 1.5 : 0;
    // 몸
    ctx.fillStyle = p.flash > 0 ? '#ff9a9a' : (p.dodge.active ? '#bfe6ff' : '#4d8fe6');
    ctx.beginPath(); ctx.arc(0, bob, p.r, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 2.5; ctx.stroke();
    // 망토/방향 표시
    ctx.fillStyle = '#e8f1ff'; ctx.beginPath(); ctx.arc(Math.cos(p.face) * 6, bob + Math.sin(p.face) * 6, 4, 0, TAU); ctx.fill();
    // 검
    const swing = Math.max(0, 1 - Math.min(1, (b.interval - p.attackTimer) / 0.18));
    const sa = p.face + (swing > 0 ? -1.2 + 2.4 * (1 - swing) : 0.5);
    ctx.strokeStyle = b.weaponId === 'pierce' ? '#bfefff' : '#f2f2f2'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(Math.cos(sa) * 8, bob + Math.sin(sa) * 8); ctx.lineTo(Math.cos(sa) * 30, bob + Math.sin(sa) * 30); ctx.stroke();
    ctx.restore();
    if (p.shield > 0) { ctx.strokeStyle = 'rgba(126,242,255,0.8)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(p.x, p.y, p.r + 6, 0, TAU); ctx.stroke(); }
    ctx.fillStyle = '#fff'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('마검사', p.x, p.y - p.r - 10);
  }

  function drawMisc(ctx, st) {
    for (const f of st.effects) {
      const k = 1 - f.t / f.ttl;
      if (f.kind === 'burst') { ctx.strokeStyle = f.color; ctx.globalAlpha = k; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 - k * 0.6), 0, TAU); ctx.stroke(); ctx.globalAlpha = 1; }
      if (f.kind === 'death') { ctx.globalAlpha = k; ctx.fillStyle = f.color; for (let i = 0; i < 6; i++) { const a = i * TAU / 6; const dd = f.r * (1 + 2 * (1 - k)); ctx.beginPath(); ctx.arc(f.x + Math.cos(a) * dd, f.y + Math.sin(a) * dd, 4 * k + 1, 0, TAU); ctx.fill(); } ctx.globalAlpha = 1; }
    }
    for (const f of st.effects) if (f.kind === 'text') { ctx.globalAlpha = Math.min(1, (1 - f.t / f.ttl) * 2); ctx.font = `bold 15px ${FONT}`; ctx.textAlign = 'center'; ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(0,0,0,0.8)'; ctx.strokeText(f.text, f.x, f.y); ctx.fillStyle = f.color; ctx.fillText(f.text, f.x, f.y); ctx.globalAlpha = 1; }
  }

  function bar(ctx, x, y, w, h, ratio, color, label, text) {
    ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = color; ctx.fillRect(x, y, w * Math.max(0, Math.min(1, ratio)), h);
    ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 1; ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
    ctx.fillStyle = '#fff'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText(label, x + 6, y + h - 5);
    ctx.textAlign = 'right'; ctx.fillText(text, x + w - 6, y + h - 5);
  }
  function slot(ctx, x, y, key, label, ready, ratio, color) {
    ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(x, y, 64, 64);
    ctx.strokeStyle = ready ? color : 'rgba(255,255,255,0.35)'; ctx.lineWidth = ready ? 3 : 1.5; ctx.strokeRect(x + 1.5, y + 1.5, 61, 61);
    if (!ready) { ctx.save(); ctx.beginPath(); ctx.rect(x, y, 64, 64); ctx.clip(); ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.beginPath(); ctx.moveTo(x + 32, y + 32); ctx.arc(x + 32, y + 32, 48, -Math.PI / 2, -Math.PI / 2 + TAU * ratio); ctx.closePath(); ctx.fill(); ctx.restore(); }
    ctx.fillStyle = ready ? '#fff' : 'rgba(255,255,255,0.6)'; ctx.font = `bold 18px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(key, x + 32, y + 30);
    ctx.font = `12px ${FONT}`; ctx.fillText(label, x + 32, y + 52);
  }
  function drawHUD(ctx, st, opts) {
    const p = st.player, b = st.build, a = st.arena;
    bar(ctx, 14, 12, 240, 22, p.hp / p.hpMax, '#d9453d', '체력', `${Math.ceil(p.hp)} / ${p.hpMax}`);
    if (p.shieldMax > 0) bar(ctx, 14, 38, 240, 16, p.shield / p.shieldMax, '#38c6d8', '보호막', `${Math.ceil(p.shield)} / ${p.shieldMax}`);
    // 목적
    const alive = st.enemies.filter(e => !e.dead).length + st.pending.length;
    const objText = st.objective === 'elite' ? '목적: 정예 처치' : '목적: 전멸';
    ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(a.w - 214, 12, 200, 46);
    ctx.fillStyle = '#fff'; ctx.font = `bold 14px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText(objText, a.w - 204, 31);
    ctx.font = `13px ${FONT}`; ctx.fillStyle = '#ddd'; ctx.fillText(`웨이브 ${Math.max(1, st.waveIndex + 1)}/${st.waves.length} · 남은 적 ${alive}`, a.w - 204, 50);
    // 슬롯
    const cfg = PA.CONFIG.PLAYER;
    const dodgeCd = cfg.dodge.cooldown * b.dodgeCdMult;
    slot(ctx, a.w / 2 - 70, a.h - 78, 'Space', '회피', !p.dodge.active && p.dodge.cd <= 0, p.dodge.active ? 1 : Math.max(0, p.dodge.cd) / dodgeCd, '#7ef2ff');
    slot(ctx, a.w / 2 + 6, a.h - 78, 'Q', '감속장', p.special.cd <= 0, p.special.cd / b.specialCd, '#a9d8ff');
    if (p.special.cd > 0) { ctx.fillStyle = '#fff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(p.special.cd.toFixed(1) + 's', a.w / 2 + 38, a.h - 84); }
    // 빌드 요약
    ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(14, a.h - 40, 330, 28);
    ctx.fillStyle = '#fff'; ctx.font = `13px ${FONT}`; ctx.textAlign = 'left';
    const augs = Object.keys(b.aug).filter(k => b.aug[k] > 0).map(k => PA.AUGMENTS.find(x => x.id === k).name + (b.aug[k] > 1 ? b.aug[k] : '')).join(', ');
    ctx.fillText(`${b.weapon.name}${st.build.aug ? '' : ''} · 피해 ${PA.fmt.num(b.damage)} · 주기 ${PA.fmt.num(b.interval)}s` + (augs ? ' · ' + augs : ''), 20, a.h - 21);
    // 조작 안내
    ctx.fillStyle = 'rgba(255,255,255,0.75)'; ctx.font = `12px ${FONT}`; ctx.textAlign = 'right'; ctx.fillText(PA.KEYS_TEXT, a.w - 14, a.h - 18);
    if (st.status !== 'running') {
      ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(0, 0, a.w, a.h);
      ctx.fillStyle = st.status === 'won' ? '#ffe066' : '#ff6b6b'; ctx.font = `bold 40px ${FONT}`; ctx.textAlign = 'center';
      ctx.fillText(st.status === 'won' ? '조우 승리' : '패배', a.w / 2, a.h / 2 - 10);
    }
  }
  function drawDebug(ctx, st) {
    ctx.strokeStyle = '#0f0'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(st.player.x, st.player.y, st.player.r, 0, TAU); ctx.stroke();
    for (const e of st.enemies) { if (e.dead) continue; ctx.strokeStyle = '#f0f'; ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, TAU); ctx.stroke(); ctx.fillStyle = '#0f0'; ctx.font = '10px monospace'; ctx.textAlign = 'left'; ctx.fillText(`${e.type} ${e.state} ${e.stateT.toFixed(2)} hp${Math.round(e.hp)}`, e.x + e.r + 2, e.y); }
    for (const p of st.projectiles) { ctx.strokeStyle = '#ff0'; ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, TAU); ctx.stroke(); }
    ctx.fillStyle = '#0f0'; ctx.font = '11px monospace'; ctx.textAlign = 'left';
    ctx.fillText(`t=${st.t.toFixed(2)} seed=${st.seed} enemies=${st.enemies.length} proj=${st.projectiles.length} zones=${st.zones.length} fx=${st.effects.length} dodge=${st.player.dodge.active} cd=${st.player.dodge.cd.toFixed(2)} prot=${st.player.hitProt.toFixed(2)} atk=${st.player.attackTimer.toFixed(2)}`, 14, 76);
  }

  function draw(ctx, st, opts) {
    opts = opts || {};
    drawGround(ctx, st);
    drawZones(ctx, st);
    drawChest(ctx, st);
    drawPlayerEffects(ctx, st);
    for (const e of st.enemies) drawEnemy(ctx, st, e);
    drawPlayer(ctx, st);
    drawTelegraphs(ctx, st);   // 예고는 내 이펙트와 캐릭터 위에
    drawProjectiles(ctx, st);
    drawMisc(ctx, st);
    drawHUD(ctx, st, opts);
    if (opts.debug) drawDebug(ctx, st);
  }
  return { draw, FONT };
})();
