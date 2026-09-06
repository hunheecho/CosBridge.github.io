// 전투 캔버스 렌더러. 시뮬레이션 상태만 읽는다. 모든 그래픽은 코드로 그린다(외부 자산 없음).
// 그리기 순서: 숲 바닥·경계 → 바닥 지역 → 상자 → 내 공격 잔상(반투명) → 그림자 → 적/플레이어(y 정렬) → 적 예고선(최상단) → 투사체 → 불꽃·숫자 → HUD
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Render = (function () {
  const FONT = "'Noto Sans KR', 'Malgun Gothic', 'Apple SD Gothic Neo', sans-serif";
  const TAU = Math.PI * 2;
  const decorCache = new Map();
  const VS = 1.25; // 캐릭터 시각 배율(판정 반지름과 별개, 실루엣 가독성용)

  // ---------- 숲 장식(시드 결정적, 판정과 무관) ----------
  function decorFor(st) {
    if (decorCache.has(st.seed)) return decorCache.get(st.seed);
    const rng = PA.rng.create(st.seed * 7 + 3), a = st.arena, pad = PA.CONFIG.VIEW.pad;
    const d = { grass: [], leaves: [], stones: [], trees: [], path: [] };
    for (let i = 0; i < 160; i++) d.grass.push({ x: rng.range(10, a.w - 10), y: rng.range(10, a.h - 10), s: rng.range(0.7, 1.3), k: rng.int(0, 2) });
    for (let i = 0; i < 40; i++) d.leaves.push({ x: rng.range(0, a.w), y: rng.range(0, a.h), r: rng.range(2, 4), a: rng.range(0, TAU), c: rng.pick(['#7a5a2e', '#8a6a34', '#5f6b2c']) });
    for (let i = 0; i < 18; i++) d.stones.push({ x: rng.range(20, a.w - 20), y: rng.range(20, a.h - 20), r: rng.range(3, 6) });
    // 흙길(장식): 좌하 → 우상 곡선
    const x0 = rng.range(0, a.w * 0.3), x1 = rng.range(a.w * 0.7, a.w);
    d.path = [{ x: x0, y: a.h + 20 }, { x: a.w * 0.5 + rng.range(-150, 150), y: a.h * 0.5 + rng.range(-100, 100) }, { x: x1, y: -20 }];
    // 경계 나무: 전장 밖 여백에만
    const step = 46;
    const ring = [];
    for (let x = -pad + 10; x <= a.w + pad; x += step) { ring.push({ x, y: -pad + 18 }); ring.push({ x: x + 20, y: a.h + pad - 18 }); }
    for (let y = -pad + 10; y <= a.h + pad; y += step) { ring.push({ x: -pad + 18, y }); ring.push({ x: a.w + pad - 18, y: y + 20 }); }
    for (const t of ring) d.trees.push({ x: t.x + rng.range(-8, 8), y: t.y + rng.range(-6, 6), r: rng.range(16, 26), c: rng.pick(['#233a22', '#1f3320', '#2a4526', '#1b2e1c']), h: rng.range(0.85, 1.15) });
    d.trees.sort((p, q) => p.y - q.y);
    decorCache.set(st.seed, d);
    return d;
  }

  function drawForest(ctx, st) {
    const a = st.arena, pad = PA.CONFIG.VIEW.pad, d = decorFor(st);
    // 바깥 여백(숲 그늘)
    ctx.fillStyle = '#121b12'; ctx.fillRect(-pad, -pad, a.w + pad * 2, a.h + pad * 2);
    // 전장 바닥
    ctx.fillStyle = '#2b3a25'; ctx.fillRect(0, 0, a.w, a.h);
    const g = ctx.createRadialGradient(a.w / 2, a.h / 2, 80, a.w / 2, a.h / 2, Math.max(a.w, a.h) * 0.7);
    g.addColorStop(0, 'rgba(90,120,60,0.22)'); g.addColorStop(1, 'rgba(0,0,0,0.35)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, a.w, a.h);
    // 흙길
    ctx.strokeStyle = 'rgba(110,88,55,0.2)'; ctx.lineWidth = 64; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(d.path[0].x, d.path[0].y); ctx.quadraticCurveTo(d.path[1].x, d.path[1].y, d.path[2].x, d.path[2].y); ctx.stroke();
    ctx.strokeStyle = 'rgba(130,105,65,0.14)'; ctx.lineWidth = 36; ctx.stroke(); ctx.lineCap = 'butt';
    // 낙엽·돌·풀
    for (const l of d.leaves) { ctx.fillStyle = l.c; ctx.beginPath(); ctx.ellipse(l.x, l.y, l.r * 1.6, l.r, l.a, 0, TAU); ctx.fill(); }
    for (const s of d.stones) { ctx.fillStyle = '#4a4f48'; ctx.beginPath(); ctx.ellipse(s.x, s.y, s.r * 1.3, s.r, 0, 0, TAU); ctx.fill(); ctx.fillStyle = '#6a6f66'; ctx.beginPath(); ctx.ellipse(s.x - 1, s.y - 1, s.r * 0.7, s.r * 0.45, 0, 0, TAU); ctx.fill(); }
    ctx.strokeStyle = '#4f7a34'; ctx.lineWidth = 1.5;
    for (const t of d.grass) {
      const sway = Math.sin(st.t * 1.5 + t.x * 0.05) * 1.5;
      ctx.beginPath(); ctx.moveTo(t.x - 3 * t.s, t.y); ctx.lineTo(t.x - 2 * t.s + sway, t.y - 7 * t.s);
      ctx.moveTo(t.x, t.y); ctx.lineTo(t.x + sway, t.y - 9 * t.s);
      ctx.moveTo(t.x + 3 * t.s, t.y); ctx.lineTo(t.x + 2 * t.s + sway, t.y - 6 * t.s); ctx.stroke();
    }
    // 경계선: 전장 가장자리(이동 가능 영역의 끝)
    ctx.strokeStyle = 'rgba(20,30,18,0.9)'; ctx.lineWidth = 6; ctx.strokeRect(0, 0, a.w, a.h);
    ctx.strokeStyle = 'rgba(160,200,120,0.25)'; ctx.lineWidth = 1.5; ctx.strokeRect(1, 1, a.w - 2, a.h - 2);
    // 나무(여백에만)
    for (const t of d.trees) {
      ctx.fillStyle = '#3a2a18'; ctx.fillRect(t.x - 3, t.y, 6, t.r * 0.9);
      ctx.fillStyle = t.c; ctx.beginPath(); ctx.arc(t.x, t.y, t.r * t.h, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.arc(t.x - t.r * 0.5, t.y + t.r * 0.25, t.r * 0.7, 0, TAU); ctx.arc(t.x + t.r * 0.5, t.y + t.r * 0.2, t.r * 0.7, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(120,170,90,0.18)'; ctx.beginPath(); ctx.arc(t.x - t.r * 0.25, t.y - t.r * 0.3, t.r * 0.45, 0, TAU); ctx.fill();
    }
    // 여백은 지나갈 수 없다: 안쪽에 옅은 그림자
    const sh = ctx.createLinearGradient(0, 0, 0, 30); sh.addColorStop(0, 'rgba(0,0,0,0.35)'); sh.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = sh; ctx.fillRect(0, 0, a.w, 30);
  }

  // 장애물: 바위·나무 밑동(충돌 범위 = 그림). 수관은 개체 위에 반투명으로 따로 그린다.
  function drawObstacles(ctx, st) {
    for (const ob of st.obstacles) {
      if (ob.type === 'rock') {
        ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.beginPath(); ctx.ellipse(ob.x + 4, ob.y + ob.r * 0.55, ob.r * 1.05, ob.r * 0.5, 0, 0, TAU); ctx.fill();
        ctx.fillStyle = '#5b6160'; ctx.beginPath(); ctx.moveTo(ob.x - ob.r, ob.y + ob.r * 0.35); ctx.lineTo(ob.x - ob.r * 0.75, ob.y - ob.r * 0.55); ctx.lineTo(ob.x - ob.r * 0.15, ob.y - ob.r); ctx.lineTo(ob.x + ob.r * 0.55, ob.y - ob.r * 0.8); ctx.lineTo(ob.x + ob.r, ob.y - ob.r * 0.1); ctx.lineTo(ob.x + ob.r * 0.85, ob.y + ob.r * 0.6); ctx.lineTo(ob.x + ob.r * 0.1, ob.y + ob.r); ctx.lineTo(ob.x - ob.r * 0.7, ob.y + ob.r * 0.8); ctx.closePath(); ctx.fill();
        ctx.fillStyle = '#7d8482'; ctx.beginPath(); ctx.moveTo(ob.x - ob.r * 0.6, ob.y - ob.r * 0.3); ctx.lineTo(ob.x - ob.r * 0.1, ob.y - ob.r * 0.85); ctx.lineTo(ob.x + ob.r * 0.45, ob.y - ob.r * 0.65); ctx.lineTo(ob.x + ob.r * 0.3, ob.y - ob.r * 0.1); ctx.lineTo(ob.x - ob.r * 0.3, ob.y + ob.r * 0.05); ctx.closePath(); ctx.fill();
        ctx.fillStyle = 'rgba(90,140,70,0.55)'; ctx.beginPath(); ctx.ellipse(ob.x - ob.r * 0.45, ob.y + ob.r * 0.35, ob.r * 0.3, ob.r * 0.16, 0.3, 0, TAU); ctx.fill();
        ctx.strokeStyle = 'rgba(20,24,22,0.7)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(ob.x, ob.y, ob.r, 0, TAU); ctx.stroke();
      } else if (ob.type === 'tree') {
        ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.beginPath(); ctx.ellipse(ob.x + 3, ob.y + 6, ob.r * 1.2, ob.r * 0.55, 0, 0, TAU); ctx.fill();
        // 밑동(충돌 범위 = 이 링)
        ctx.fillStyle = '#4a3420'; ctx.beginPath(); ctx.arc(ob.x, ob.y, ob.r, 0, TAU); ctx.fill();
        ctx.fillStyle = '#5e4429'; ctx.beginPath(); ctx.arc(ob.x, ob.y, ob.r * 0.72, 0, TAU); ctx.fill();
        ctx.strokeStyle = '#3a2816'; ctx.lineWidth = 1.5; for (let i = 1; i <= 3; i++) { ctx.beginPath(); ctx.arc(ob.x, ob.y, ob.r * 0.72 * i / 4, 0, TAU); ctx.stroke(); }
        for (let i = 0; i < 4; i++) { const a = i * TAU / 4 + 0.6; ctx.strokeStyle = '#4a3420'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(ob.x + Math.cos(a) * ob.r * 0.8, ob.y + Math.sin(a) * ob.r * 0.8); ctx.lineTo(ob.x + Math.cos(a) * (ob.r + 12), ob.y + Math.sin(a) * (ob.r + 12)); ctx.stroke(); }
        ctx.strokeStyle = 'rgba(20,24,22,0.7)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(ob.x, ob.y, ob.r, 0, TAU); ctx.stroke();
      }
    }
  }
  function drawCanopies(ctx, st) {
    for (const ob of st.obstacles) {
      if (ob.type !== 'tree') continue;
      const R = ob.canopy || 70;
      const near = st.enemies.some(e => !e.dead && Math.hypot(e.x - ob.x, e.y - ob.y) < R + e.r + 10) || Math.hypot(st.player.x - ob.x, st.player.y - ob.y) < R + 30;
      ctx.globalAlpha = near ? 0.32 : 0.82;
      ctx.fillStyle = '#233a22'; ctx.beginPath(); ctx.arc(ob.x, ob.y - 14, R, 0, TAU); ctx.fill();
      ctx.fillStyle = '#2c4a2a'; ctx.beginPath(); ctx.arc(ob.x - R * 0.35, ob.y - 24, R * 0.55, 0, TAU); ctx.arc(ob.x + R * 0.4, ob.y - 20, R * 0.5, 0, TAU); ctx.arc(ob.x, ob.y - R * 0.55, R * 0.5, 0, TAU); ctx.fill();
      ctx.fillStyle = 'rgba(140,190,100,0.25)'; ctx.beginPath(); ctx.arc(ob.x - R * 0.2, ob.y - R * 0.45, R * 0.35, 0, TAU); ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
  function drawZones(ctx, st) {
    for (const z of st.zones) {
      const life = z.ttl / z.maxTtl;
      if (z.type === 'spore') {
        ctx.fillStyle = `rgba(170,90,230,${0.2 + 0.2 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(215,160,255,${0.5 + 0.3 * life})`; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.stroke(); ctx.setLineDash([]);
        for (let i = 0; i < 6; i++) { const ang = z.t * 0.8 + i * 1.1, rr = z.r * (0.25 + 0.6 * ((i * 0.37 + z.t * 0.2) % 1)); ctx.fillStyle = 'rgba(235,200,255,0.55)'; ctx.beginPath(); ctx.arc(z.x + Math.cos(ang) * rr, z.y + Math.sin(ang) * rr, 3 + (i % 2), 0, TAU); ctx.fill(); }
        ctx.fillStyle = 'rgba(255,255,255,0.75)'; ctx.font = `bold 14px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('☠', z.x, z.y + 5);
      } else if (z.type === 'web') { // 거미줄: 흰 방사선·동심원, 남은 시간은 외곽 호
        ctx.strokeStyle = `rgba(235,235,245,${0.35 + 0.35 * life})`; ctx.lineWidth = 1.2; for (let i = 0; i < 8; i++) { const a = i * TAU / 8; ctx.beginPath(); ctx.moveTo(z.x, z.y); ctx.lineTo(z.x + Math.cos(a) * z.r, z.y + Math.sin(a) * z.r); ctx.stroke(); }
        for (let k = 1; k <= 3; k++) { ctx.beginPath(); ctx.arc(z.x, z.y, z.r * k / 3, 0, TAU); ctx.stroke(); }
        ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(z.x, z.y, z.r + 2, -Math.PI / 2, -Math.PI / 2 + TAU * life); ctx.stroke();
        ctx.fillStyle = 'rgba(255,255,255,0.8)'; ctx.font = `11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('거미줄(걷기 50%)', z.x, z.y - z.r - 6);
      } else if (z.type === 'frostzone') { // 서리 영역: 순서 번호, 남은 시간만큼 안쪽 원이 커진다
        const k = 1 - life; ctx.fillStyle = `rgba(160,220,255,${0.12 + 0.25 * k})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.fill();
        ctx.fillStyle = `rgba(200,240,255,${0.35 + 0.4 * k})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r * k, 0, TAU); ctx.fill();
        ctx.strokeStyle = z.ttl < 0.45 ? `rgba(255,120,120,${0.8 + 0.2 * Math.sin(st.t * 60)})` : 'rgba(200,240,255,0.8)'; ctx.lineWidth = z.ttl < 0.45 ? 3 : 1.5; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.stroke();
        ctx.fillStyle = '#ffffff'; ctx.font = `bold 18px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(String(z.order || ''), z.x, z.y + 6);
      } else if (z.type === 'coldground') {
        ctx.fillStyle = `rgba(160,220,255,${0.22 * life + 0.08})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.fill(); ctx.strokeStyle = `rgba(200,240,255,${0.6 * life})`; ctx.lineWidth = 1.5; ctx.stroke();
      } else if (z.type === 'windpath') {
        ctx.strokeStyle = `rgba(200,255,220,${0.5 * life})`; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
      } else if (z.type === 'slowecho') {
        ctx.fillStyle = `rgba(110,180,255,${0.08 * life + 0.04})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.fill();
      } else if (z.type === 'storm') {
        ctx.strokeStyle = `rgba(255,240,150,${0.5 * life})`; ctx.lineWidth = 2; ctx.setLineDash([3, 5]); ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
      } else if (z.type === 'hazard') { // 바닥 위험(제단·위험 지형): 예고 중 점선 원과 채워지는 내부, 무장 후 붉은 채움
        if (!z.armed) { const k = Math.min(1, z.t / z.warn); ctx.strokeStyle = k > 0.7 ? `rgba(255,90,60,${0.5 + 0.5 * Math.abs(Math.sin(st.t * 20))})` : 'rgba(255,140,90,0.7)'; ctx.lineWidth = k > 0.7 ? 3 : 2; ctx.setLineDash([6, 5]); ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]); ctx.fillStyle = `rgba(255,120,60,${0.1 + 0.2 * k})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r * k, 0, TAU); ctx.fill(); ctx.fillStyle = '#ffd9b0'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(z.tag === 'terrain' ? '지형 붕괴 예고' : '제단 위험 예고', z.x, z.y - z.r - 6); }
        else { ctx.fillStyle = `rgba(255,70,40,${0.3 + 0.25 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r, 0, TAU); ctx.fill(); ctx.strokeStyle = 'rgba(255,150,100,0.8)'; ctx.lineWidth = 2; ctx.stroke(); for (let i = 0; i < 5; i++) { const a = i * 1.26 + z.t * 2; ctx.strokeStyle = 'rgba(255,220,160,0.6)'; ctx.beginPath(); ctx.moveTo(z.x + Math.cos(a) * z.r * 0.3, z.y + Math.sin(a) * z.r * 0.3); ctx.lineTo(z.x + Math.cos(a) * z.r * 0.9, z.y + Math.sin(a) * z.r * 0.9); ctx.stroke(); } }
      } else if (z.type === 'fire') {
        const fl = 1 + 0.12 * Math.sin(z.t * 22);
        ctx.fillStyle = `rgba(255,110,30,${0.25 + 0.25 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r * fl, 0, TAU); ctx.fill();
        ctx.fillStyle = `rgba(255,220,90,${0.55 * life})`; ctx.beginPath(); ctx.arc(z.x, z.y, z.r * 0.5 * fl, 0, TAU); ctx.fill();
        for (let i = 0; i < 4; i++) { const ang = i * 1.57 + z.t * 3, fr = z.r * 0.6; ctx.fillStyle = `rgba(255,200,80,${0.5 * life})`; ctx.beginPath(); ctx.moveTo(z.x + Math.cos(ang) * fr, z.y + Math.sin(ang) * fr - 6 - 4 * Math.sin(z.t * 15 + i)); ctx.lineTo(z.x + Math.cos(ang) * fr - 3, z.y + Math.sin(ang) * fr + 2); ctx.lineTo(z.x + Math.cos(ang) * fr + 3, z.y + Math.sin(ang) * fr + 2); ctx.fill(); }
      }
    }
    if (st.field) {
      const f = st.field, life = f.ttl / f.maxTtl;
      ctx.fillStyle = 'rgba(110,180,255,0.16)'; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.fill();
      ctx.strokeStyle = 'rgba(170,225,255,0.45)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.stroke();
      // 시계 눈금과 남은 시간 호
      for (let i = 0; i < 24; i++) { const ang = i * TAU / 24 - st.t * 0.3; const L = i % 6 === 0 ? 10 : 5; ctx.strokeStyle = 'rgba(200,235,255,0.7)'; ctx.lineWidth = i % 6 === 0 ? 2 : 1; ctx.beginPath(); ctx.moveTo(f.x + Math.cos(ang) * (f.r - L), f.y + Math.sin(ang) * (f.r - L)); ctx.lineTo(f.x + Math.cos(ang) * f.r, f.y + Math.sin(ang) * f.r); ctx.stroke(); }
      ctx.strokeStyle = 'rgba(190,235,255,0.95)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(f.x, f.y, f.r + 3, -Math.PI / 2, -Math.PI / 2 + TAU * life); ctx.stroke();
      for (let i = 0; i < 10; i++) { const ang = i * 0.63 + st.t * 0.4, rr = f.r * (0.2 + 0.7 * ((i * 0.31 + st.t * 0.05) % 1)); ctx.fillStyle = 'rgba(220,245,255,0.6)'; ctx.beginPath(); ctx.arc(f.x + Math.cos(ang) * rr, f.y + Math.sin(ang) * rr, 2, 0, TAU); ctx.fill(); }
      ctx.fillStyle = 'rgba(200,235,255,0.95)'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('감속장 ' + f.ttl.toFixed(1) + 's', f.x, f.y - f.r - 10);
    }
  }

  function drawChest(ctx, st) {
    const c = st.chest; if (!c || (c.opened && c.t > 0.6)) return;
    const bob = c.opened ? 0 : Math.sin(st.t * 4) * 2;
    ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.beginPath(); ctx.ellipse(c.x, c.y + 12, 16, 5, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = c.opened ? '#8a6b2f' : '#c9973a'; ctx.fillRect(c.x - 14, c.y - 10 + bob, 28, 20);
    ctx.fillStyle = '#5b3f14'; ctx.fillRect(c.x - 14, c.y - 12 + bob, 28, 6);
    ctx.fillStyle = '#ffe9a8'; ctx.fillRect(c.x - 3, c.y - 4 + bob, 6, 6);
    if (!c.opened) { ctx.fillStyle = '#ffd166'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('보급 상자', c.x, c.y - 20 + bob); }
  }

  function drawPlayerEffects(ctx, st) {
    for (const f of st.effects) {
      const k = 1 - f.t / f.ttl;
      if (f.kind === 'arc' && f.enemy) { ctx.fillStyle = `rgba(255,120,80,${0.35 * k})`; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.arc(f.x, f.y, f.r, f.angle - f.half, f.angle + f.half); ctx.closePath(); ctx.fill(); ctx.strokeStyle = `rgba(255,220,200,${0.9 * k})`; ctx.lineWidth = 4 * k + 1; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.6 + 0.4 * (1 - k)), f.angle - f.half, f.angle + f.half); ctx.stroke(); }
      else if (f.kind === 'arc') {
        ctx.fillStyle = `rgba(150,205,255,${0.28 * k})`; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.arc(f.x, f.y, f.r, f.angle - f.half, f.angle + f.half); ctx.closePath(); ctx.fill();
        // 초승달 검광
        for (let i = 0; i < 3; i++) { ctx.strokeStyle = `rgba(230,245,255,${(0.9 - i * 0.25) * k})`; ctx.lineWidth = 5 - i * 1.5; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.55 + 0.45 * (1 - k)) - i * 5, f.angle - f.half * (1 - i * 0.15), f.angle + f.half * (1 - i * 0.15)); ctx.stroke(); }
      } else if (f.kind === 'beam') {
        ctx.save(); ctx.translate(f.x, f.y); ctx.rotate(f.angle);
        ctx.fillStyle = `rgba(160,220,255,${0.35 * k})`; ctx.fillRect(0, -f.w / 2, f.len, f.w);
        ctx.fillStyle = `rgba(255,255,255,${0.8 * k})`; ctx.fillRect(0, -2, f.len * (0.6 + 0.4 * (1 - k)), 4);
        ctx.fillStyle = `rgba(200,240,255,${0.6 * k})`; ctx.beginPath(); ctx.moveTo(f.len, 0); ctx.lineTo(f.len - 18, -f.w / 2); ctx.lineTo(f.len - 18, f.w / 2); ctx.fill();
        ctx.restore();
      } else if (f.kind === 'dagger') {
        ctx.strokeStyle = `rgba(255,255,255,${0.9 * k})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * 0.9, f.angle - f.half * (f.side % 2 ? 1 : -1), f.angle + f.half * (f.side % 2 ? -0.2 : 0.2) ); ctx.stroke();
      } else if (f.kind === 'scar') {
        ctx.fillStyle = `rgba(255,120,120,${0.35 * k})`; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.arc(f.x, f.y, f.r, f.angle - f.half, f.angle + f.half); ctx.closePath(); ctx.fill();
      } else if (f.kind === 'impact') {
        ctx.fillStyle = f.after ? `rgba(200,150,90,${0.35 * k})` : `rgba(230,200,150,${0.4 * k})`; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.6 + 0.4 * (1 - k)), 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(255,230,180,${0.9 * k})`; ctx.lineWidth = 5 * k + 1; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 - k * 0.25), 0, TAU); ctx.stroke();
      } else if (f.kind === 'chain') {
        ctx.strokeStyle = `rgba(200,240,255,${0.95 * k})`; ctx.lineWidth = 3; ctx.beginPath(); for (let i = 0; i < f.pts.length; i++) { const p0 = f.pts[i]; if (i === 0) ctx.moveTo(p0.x, p0.y); else { const p1 = f.pts[i - 1]; const mx = (p0.x + p1.x) / 2 + (i % 2 ? 8 : -8), my = (p0.y + p1.y) / 2 + (i % 2 ? -8 : 8); ctx.lineTo(mx, my); ctx.lineTo(p0.x, p0.y); } } ctx.stroke();
        ctx.strokeStyle = `rgba(120,200,255,${0.5 * k})`; ctx.lineWidth = 7; ctx.stroke();
      } else if (f.kind === 'emberthrow') {
        const kk = f.t / f.ttl; const x = f.x0 + (f.x - f.x0) * kk, y = f.y0 + (f.y - f.y0) * kk - Math.sin(kk * Math.PI) * 60; ctx.fillStyle = '#ffb347'; ctx.beginPath(); ctx.arc(x, y, 6, 0, TAU); ctx.fill();
      } else if (f.kind === 'mineburst') {
        ctx.fillStyle = `rgba(190,120,255,${0.4 * k})`; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.5 + 0.5 * (1 - k)), 0, TAU); ctx.fill(); ctx.strokeStyle = `rgba(230,200,255,${0.9 * k})`; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.stroke();
      } else if (f.kind === 'strike' || f.kind === 'strikewarn') {
        if (f.kind === 'strikewarn') { ctx.strokeStyle = `rgba(255,240,150,${0.6 + 0.4 * (1 - k)})`; ctx.lineWidth = 2; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]); }
        else { ctx.fillStyle = `rgba(255,250,200,${0.4 * k})`; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.fill(); ctx.strokeStyle = `rgba(255,255,255,${k})`; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(f.x + 10, f.y - 160); ctx.lineTo(f.x - 8, f.y - 70); ctx.lineTo(f.x + 8, f.y - 60); ctx.lineTo(f.x, f.y); ctx.stroke(); }
      } else if (f.kind === 'gust') {
        ctx.strokeStyle = `rgba(200,255,220,${0.8 * k})`; ctx.lineWidth = 3;
        if (f.whirl) { for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.4 + 0.2 * i) * (1 + (1 - k) * 0.6), i, i + 4); ctx.stroke(); } }
        else { ctx.save(); ctx.translate(f.x, f.y); ctx.rotate(f.angle); for (let i = 0; i < 3; i++) { const xx = f.len * (0.3 + 0.35 * i) * (1 - k * 0.3); ctx.beginPath(); ctx.moveTo(xx, -f.w / 2 * (0.4 + 0.3 * i)); ctx.quadraticCurveTo(xx + 25, 0, xx, f.w / 2 * (0.4 + 0.3 * i)); ctx.stroke(); } ctx.restore(); }
      } else if (f.kind === 'spin') {
        ctx.strokeStyle = `rgba(210,235,255,${0.85 * k})`; ctx.lineWidth = 7 * k + 2; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.7 + 0.3 * (1 - k)), 0, TAU); ctx.stroke();
        ctx.fillStyle = `rgba(150,205,255,${0.18 * k})`; ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, TAU); ctx.fill();
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
  function shadow(ctx, x, y, rx, ry) { ctx.fillStyle = 'rgba(0,0,0,0.32)'; ctx.beginPath(); ctx.ellipse(x, y, rx, ry, 0, 0, TAU); ctx.fill(); }

  // ---------- 늑대 (측면, 좌우 반전) ----------
  function drawWolf(ctx, st, e) {
    const d = e.def, p = st.player, s = e.r / 14 * VS;
    let ang = e.state === 'crouch' ? e.aimAngle : (e.state === 'lock' || e.state === 'dash') ? e.dir : Math.atan2(p.y - e.y, p.x - e.x);
    let faceX = (e.state === 'approach' || e.state === 'recover') ? e.faceX : (Math.cos(ang) >= 0 ? 1 : -1);
    if (e.state === 'approach' && Math.abs(Math.cos(ang)) > 0.2) faceX = Math.cos(ang) >= 0 ? 1 : -1;
    const dying = e.dead;
    const fur = e.elite ? '#a8873f' : '#8d9198', fur2 = e.elite ? '#6b5326' : '#5c6068', belly = e.elite ? '#d6bd85' : '#c2c5ca';
    const alpha = dying ? Math.max(0, 1 - Math.max(0, e.deathT - 0.4) / 0.5) : 1;
    ctx.save(); ctx.translate(e.x, e.y); ctx.globalAlpha = alpha;
    shadow(ctx, 0, 12 * s, 17 * s, 5 * s);
    // 돌진 잔상
    if (e.state === 'dash') for (let i = 1; i <= 3; i++) { ctx.fillStyle = `rgba(210,210,220,${0.22 / i})`; ctx.beginPath(); ctx.ellipse(-Math.cos(e.dir) * 12 * i, -Math.sin(e.dir) * 12 * i, 18 * s, 7 * s, e.dir, 0, TAU); ctx.fill(); }
    ctx.scale(faceX, 1);
    // 자세 파라미터
    let bodyY = 0, stretch = 1, ry = 8, headY = -7, tailUp = 1, legSpread = 0, jaw = 0.12, tilt = 0, legFold = 0;
    const gait = Math.sin(e.moveT * TAU * 0.9);
    if (e.state === 'crouch') { bodyY = 3; ry = 6.5; headY = -2; tailUp = -0.6; legFold = 1; stretch = 1.1; jaw = 0.25; tilt = -0.12; }
    if (e.state === 'lock') { bodyY = 4; ry = 6.5; headY = -1; tailUp = -0.8; legFold = 1; stretch = 0.95; jaw = 0.6; tilt = -0.2; }
    if (e.state === 'dash') { bodyY = 1; ry = 6.5; headY = -3; tailUp = 0; legSpread = 1; stretch = 1.35; jaw = e.biteT < 0.2 ? 0.05 : 0.7; }
    if (e.state === 'recover') { bodyY = 2; headY = -4; tailUp = -0.3; tilt = Math.sin(e.stateT * 14) * 0.12; jaw = 0.35; }
    if (dying) { tilt = Math.min(1.35, e.deathT * 4); bodyY = Math.min(8, e.deathT * 20); jaw = 0.4; }
    ctx.rotate(tilt);
    ctx.scale(s, s);
    const L = 16 * stretch;
    // 꼬리
    ctx.strokeStyle = fur2; ctx.lineWidth = 4; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(-L + 2, bodyY - 1); ctx.quadraticCurveTo(-L - 8, bodyY - 2 - 6 * tailUp, -L - 12, bodyY - 10 * tailUp + 2); ctx.stroke();
    // 다리 (뒤 2, 앞 2)
    ctx.strokeStyle = fur2; ctx.lineWidth = 3.2;
    const legs = [[-9, 0], [-7, Math.PI], [8, Math.PI], [10, 0]];
    for (let i = 0; i < 4; i++) {
      const [hx, ph] = legs[i]; const hipY = bodyY + 4;
      let fx, fy;
      if (legSpread) { fx = hx + (hx > 0 ? 9 : -9); fy = hipY + 7; }
      else if (legFold) { fx = hx + (hx > 0 ? 3 : -3); fy = hipY + 6; }
      else if (dying) { fx = hx + 3; fy = hipY + 6; }
      else { const sw = e.state === 'approach' ? Math.sin(e.moveT * TAU * 0.9 + ph) : 0; fx = hx + sw * 5; fy = hipY + 10 - Math.max(0, Math.cos(e.moveT * TAU * 0.9 + ph)) * 2 * (e.state === 'approach' ? 1 : 0); }
      const kx = (hx + fx) / 2 + (hx > 0 ? 1 : -2), ky = (hipY + fy) / 2;
      ctx.beginPath(); ctx.moveTo(hx, hipY); ctx.lineTo(kx, ky); ctx.lineTo(fx, fy); ctx.stroke();
      ctx.fillStyle = '#2f3136'; ctx.beginPath(); ctx.ellipse(fx + 1, fy, 2.5, 1.6, 0, 0, TAU); ctx.fill();
    }
    // 몸통
    ctx.fillStyle = e.flash > 0 ? '#ffffff' : (e.chill > 0 ? '#b9d4e6' : fur);
    ctx.beginPath(); ctx.ellipse(0, bodyY, L, ry, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = e.flash > 0 ? '#ffffff' : belly; ctx.beginPath(); ctx.ellipse(1, bodyY + 3, L * 0.7, ry * 0.45, 0, 0, TAU); ctx.fill();
    if (e.elite) { ctx.fillStyle = fur2; ctx.beginPath(); ctx.ellipse(L * 0.45, bodyY - 3, L * 0.45, ry * 0.7, 0, 0, TAU); ctx.fill(); }
    // 머리
    const hx = L - 2, hy = bodyY + headY;
    ctx.fillStyle = e.flash > 0 ? '#ffffff' : (e.chill > 0 ? '#b9d4e6' : fur);
    ctx.beginPath(); ctx.arc(hx, hy, 7, 0, TAU); ctx.fill();
    // 주둥이(위턱)
    ctx.beginPath(); ctx.moveTo(hx + 3, hy - 4); ctx.lineTo(hx + 15, hy + 0.5); ctx.lineTo(hx + 4, hy + 3); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#1e1f22'; ctx.beginPath(); ctx.arc(hx + 14.5, hy, 1.6, 0, TAU); ctx.fill();
    // 아래턱(열림 각도 = jaw)
    ctx.save(); ctx.translate(hx + 3, hy + 2); ctx.rotate(jaw);
    ctx.fillStyle = e.flash > 0 ? '#ffffff' : fur2; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(11, 0); ctx.lineTo(1, 3.5); ctx.closePath(); ctx.fill();
    if (jaw > 0.2) { ctx.fillStyle = '#fff'; for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.moveTo(3 + i * 2.6, 0); ctx.lineTo(4 + i * 2.6, -2.2); ctx.lineTo(5 + i * 2.6, 0); ctx.fill(); } }
    if (e.state === 'recover' && !dying) { ctx.fillStyle = '#e06a7a'; ctx.beginPath(); ctx.ellipse(6, 2.5, 3, 1.5, 0.3, 0, TAU); ctx.fill(); }
    ctx.restore();
    if (jaw > 0.2) { ctx.fillStyle = '#fff'; for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.moveTo(hx + 6 + i * 2.6, hy + 1.5); ctx.lineTo(hx + 7 + i * 2.6, hy + 4); ctx.lineTo(hx + 8 + i * 2.6, hy + 1.5); ctx.fill(); } }
    if (e.biteT < 0.15) { ctx.strokeStyle = `rgba(255,255,255,${1 - e.biteT / 0.15})`; ctx.lineWidth = 2; for (let i = -1; i <= 1; i++) { ctx.beginPath(); ctx.arc(hx + 12, hy + 1, 8 + 6 * (e.biteT / 0.15), -0.6 + i * 0.5, -0.2 + i * 0.5); ctx.stroke(); } }
    // 귀 (준비·확정 시 뒤로 젖힘)
    const earBack = (e.state === 'crouch' || e.state === 'lock' || e.state === 'dash') ? -3 : 0;
    ctx.fillStyle = e.flash > 0 ? '#ffffff' : fur2;
    ctx.beginPath(); ctx.moveTo(hx - 3, hy - 4); ctx.lineTo(hx - 6 + earBack, hy - 13); ctx.lineTo(hx + 1, hy - 6); ctx.fill();
    ctx.beginPath(); ctx.moveTo(hx + 1, hy - 5); ctx.lineTo(hx - 1 + earBack, hy - 12); ctx.lineTo(hx + 5, hy - 5); ctx.fill();
    // 눈
    ctx.fillStyle = dying ? '#333' : (e.state === 'approach' ? '#ffd27a' : '#ff4a4a'); ctx.beginPath(); ctx.arc(hx + 3, hy - 1.5, 1.7, 0, TAU); ctx.fill();
    if (e.elite) { ctx.strokeStyle = '#3b2c12'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(hx - 2, hy - 6); ctx.lineTo(hx + 2, hy + 1); ctx.stroke(); }
    ctx.restore();
  }

  // ---------- 보스: 가시갈기 ----------
  // 봉인 수호자: 돌 갑옷 거인(각진 몸통·어깨 판·룬 눈). 실루엣은 늑대(가시갈기)와 구분되는 세로로 긴 사각
  function drawGuardian(ctx, st, e) {
    const s = e.r / 40, dying = e.dead, alpha = dying ? Math.max(0.25, 1 - Math.max(0, e.deathT - 1.2) / 1.5) : 1, glow = 0.5 + 0.5 * Math.sin(st.t * 3);
    ctx.save(); ctx.translate(e.x, e.y); ctx.globalAlpha = alpha; shadow(ctx, 0, 30 * s, 34 * s, 10 * s);
    if (dying) ctx.rotate(Math.min(1.2, e.deathT * 2));
    const flash = e.flash > 0; const armor = flash ? '#ffffff' : '#5a6a9a', dark = flash ? '#eeeeff' : '#38456a';
    ctx.fillStyle = dark; ctx.fillRect(-22 * s, 6 * s, 16 * s, 26 * s); ctx.fillRect(6 * s, 6 * s, 16 * s, 26 * s); // 다리
    ctx.fillStyle = armor; ctx.beginPath(); ctx.moveTo(-30 * s, -26 * s); ctx.lineTo(30 * s, -26 * s); ctx.lineTo(26 * s, 12 * s); ctx.lineTo(-26 * s, 12 * s); ctx.closePath(); ctx.fill(); // 몸통
    ctx.fillStyle = dark; ctx.fillRect(-46 * s, -30 * s, 18 * s, 14 * s); ctx.fillRect(28 * s, -30 * s, 18 * s, 14 * s); // 어깨 판
    const armAng = (e.state === 'sweep_aim' || e.state === 'sweep_lock') ? -0.9 + (e.state === 'sweep_lock' ? 0.3 : 0) : 0.4;
    ctx.save(); ctx.translate(38 * s, -20 * s); ctx.rotate(armAng); ctx.fillStyle = armor; ctx.fillRect(-6 * s, 0, 12 * s, 44 * s); ctx.fillStyle = dark; ctx.fillRect(-12 * s, 40 * s, 24 * s, 14 * s); ctx.restore(); // 오른팔(철퇴)
    ctx.save(); ctx.translate(-38 * s, -20 * s); ctx.rotate(-0.3); ctx.fillStyle = armor; ctx.fillRect(-6 * s, 0, 12 * s, 40 * s); ctx.restore();
    ctx.fillStyle = armor; ctx.fillRect(-14 * s, -44 * s, 28 * s, 20 * s); // 머리
    ctx.fillStyle = `rgba(150,210,255,${0.5 + 0.5 * glow})`; ctx.fillRect(-9 * s, -38 * s, 18 * s, 4 * s); // 룬 눈
    ctx.strokeStyle = `rgba(150,210,255,${0.4 + 0.4 * glow})`; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, -8 * s, 9 * s, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.moveTo(0, -17 * s); ctx.lineTo(0, 1 * s); ctx.stroke(); // 가슴 룬
    ctx.restore();
  }
  // 예언을 먹는 자: 떠 있는 검은 구체·갈라진 입·여러 눈·촉수. 실루엣은 둥글고 비대칭
  function drawEater(ctx, st, e) {
    const s = e.r / 38, dying = e.dead, alpha = dying ? Math.max(0.25, 1 - Math.max(0, e.deathT - 1.2) / 1.5) : 1, bob = Math.sin(st.t * 2.2) * 4;
    ctx.save(); ctx.translate(e.x, e.y); ctx.globalAlpha = alpha; shadow(ctx, 0, 30 * s, 30 * s, 9 * s); ctx.translate(0, -8 * s + bob);
    const flash = e.flash > 0; const body = flash ? '#ffffff' : '#3a1f4a', edge = flash ? '#eeeeff' : '#7a3a8a';
    for (let i = 0; i < 6; i++) { const a = i * TAU / 6 + st.t * 0.7, L = (30 + 10 * Math.sin(st.t * 3 + i)) * s; ctx.strokeStyle = edge; ctx.lineWidth = 4 * s; ctx.beginPath(); ctx.moveTo(Math.cos(a) * 26 * s, Math.sin(a) * 26 * s); ctx.quadraticCurveTo(Math.cos(a + 0.4) * (26 * s + L * 0.6), Math.sin(a + 0.4) * (26 * s + L * 0.6), Math.cos(a) * (26 * s + L), Math.sin(a) * (26 * s + L)); ctx.stroke(); } // 촉수
    ctx.fillStyle = body; ctx.beginPath(); ctx.ellipse(0, 0, 34 * s, 30 * s, 0.2, 0, TAU); ctx.fill(); ctx.strokeStyle = edge; ctx.lineWidth = 3; ctx.stroke();
    const open = (e.state === 'wide_aim' || e.state === 'wide_lock' || e.state === 'mark_cast') ? 0.9 : e.state === 'summon' ? 0.6 : 0.25; // 입
    ctx.fillStyle = '#12060f'; ctx.beginPath(); ctx.ellipse(2 * s, 8 * s, 20 * s, 8 * s * open + 2, 0, 0, TAU); ctx.fill(); ctx.fillStyle = '#e0c0ff'; for (let i = -2; i <= 2; i++) { ctx.beginPath(); ctx.moveTo((i * 7 - 1) * s, (8 - 6 * open) * s); ctx.lineTo((i * 7 + 2) * s, (8 - 6 * open) * s); ctx.lineTo((i * 7) * s, (8 - 6 * open + 6 * open) * s); ctx.fill(); }
    const eyes = [[-14, -10, 6], [8, -14, 8], [18, -2, 4], [-4, -18, 3]]; for (const [ex, ey, er] of eyes) { ctx.fillStyle = e.state === 'recover' || e.state === 'stagger' ? '#ffd166' : '#c080ff'; ctx.beginPath(); ctx.arc(ex * s, ey * s, er * s, 0, TAU); ctx.fill(); ctx.fillStyle = '#12060f'; ctx.beginPath(); ctx.arc(ex * s + 1, ey * s, er * s * 0.45, 0, TAU); ctx.fill(); }
    ctx.restore();
  }
  function drawBoss(ctx, st, e) {
    if (e.bossId === 'guardian') return drawGuardian(ctx, st, e);
    if (e.bossId === 'eater') return drawEater(ctx, st, e);
    const cfg = PA.BOSS, p = st.player, s = e.r / 14 * 0.95;
    const facingAng = (e.state === 'sweep_aim' || e.state === 'pounce_aim' || e.state === 'dash_aim') ? e.aimAngle : (e.state === 'sweep_lock' || e.state === 'dash_lock' || e.state === 'dash') ? e.dir : (e.state === 'leap' && e.land ? Math.atan2(e.land.y - e.leapFrom.y, e.land.x - e.leapFrom.x) : Math.atan2(p.y - e.y, p.x - e.x));
    let faceX = Math.abs(Math.cos(facingAng)) > 0.15 ? (Math.cos(facingAng) >= 0 ? 1 : -1) : e.faceX;
    const dying = e.dead, alpha = dying ? Math.max(0.25, 1 - Math.max(0, e.deathT - 1.2) / 1.5) : 1;
    // 도약: 그림자는 실제 위치(보간 중), 몸은 위로 떠오름
    const air = e.state === 'leap' ? Math.sin(e.leapK * Math.PI) * 90 : 0;
    ctx.save(); ctx.translate(e.x, e.y); ctx.globalAlpha = alpha;
    shadow(ctx, 0, 16 * s, (17 - air * 0.05) * s, (5 - air * 0.02) * s);
    if (e.state === 'dash') for (let i = 1; i <= 3; i++) { ctx.fillStyle = `rgba(120,100,70,${0.22 / i})`; ctx.beginPath(); ctx.ellipse(-Math.cos(e.dir) * 26 * i, -Math.sin(e.dir) * 26 * i, 20 * s, 8 * s, e.dir, 0, TAU); ctx.fill(); }
    ctx.translate(0, -air);
    ctx.scale(faceX, 1);
    let bodyY = 0, ry = 9, headY = -8, headTilt = 0, tailUp = 0.8, stretch = 1, legSpread = 0, legFold = 0, jaw = 0.15, tilt = 0, maneUp = 0, breathe = 0;
    const gait = Math.sin(e.moveT * TAU * 0.6);
    switch (e.state) {
      case 'intro': maneUp = 1; headTilt = -0.9; tailUp = 1; jaw = 0.6; break;
      case 'sweep_aim': headTilt = -0.55 * Math.min(1, e.stateT / 0.3); tilt = -0.06; jaw = 0.3; break;
      case 'sweep_lock': headTilt = -0.75; tilt = -0.1; jaw = 0.6; break;
      case 'dash_aim': bodyY = 4; ry = 7.5; headY = -3; tailUp = -0.5; legFold = 1; tilt = -0.12; jaw = 0.25; break;
      case 'dash_lock': bodyY = 5; ry = 7.5; headY = -2; tailUp = -0.7; legFold = 1; tilt = -0.2; jaw = 0.6; break;
      case 'dash': bodyY = 1; ry = 7.5; headY = -4; stretch = 1.35; legSpread = 1; jaw = e.biteT < 0.2 ? 0.05 : 0.7; break;
      case 'howl': maneUp = 1; headTilt = -1.1; tailUp = 1; jaw = 0.7; break;
      case 'pounce_aim': case 'pounce_lock': bodyY = 6; ry = 7; headY = -1; legFold = 1; stretch = 0.85; tailUp = -0.4; jaw = 0.3; break;
      case 'leap': bodyY = 0; stretch = 1.2; legSpread = 1; headY = -6; jaw = 0.6; tailUp = 0.3; break;
      case 'recover': bodyY = 3; headY = 2; headTilt = 0.35; tailUp = -0.4; breathe = 1; jaw = 0.4; break;
      case 'stagger': tilt = Math.sin(e.stateT * 14) * 0.15; headTilt = 0.2; jaw = 0.4; break;
      case 'roar': maneUp = 1; headTilt = -0.8; jaw = 0.8; tailUp = 1; break;
      case 'dead': tilt = Math.min(1.3, e.deathT * 2.5); bodyY = Math.min(12, e.deathT * 20); jaw = 0.5; break;
      default: ry = 9 + 0.4 * Math.sin(e.animT * 3);
    }
    if (breathe) { const b = 1 + 0.05 * Math.sin(e.stateT * 6); ry *= b; }
    ctx.rotate(tilt); ctx.scale(s, s);
    const L = 18 * stretch;
    const fur = '#6e5a3a', fur2 = '#4a3a24', belly = '#a08a62', thorn = '#1c1a17';
    // 꼬리
    ctx.strokeStyle = fur2; ctx.lineWidth = 5; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(-L + 2, bodyY - 1); ctx.quadraticCurveTo(-L - 9, bodyY - 2 - 7 * tailUp, -L - 15, bodyY - 12 * tailUp + 2); ctx.stroke();
    // 다리(굵게)
    ctx.strokeStyle = fur2; ctx.lineWidth = 4.5;
    const legs = [[-10, 0], [-8, Math.PI], [9, Math.PI], [12, 0]];
    for (let i = 0; i < 4; i++) {
      const [hx, ph] = legs[i]; const hipY = bodyY + 5;
      let fx, fy;
      if (legSpread) { fx = hx + (hx > 0 ? 11 : -11); fy = hipY + 8; }
      else if (legFold) { fx = hx + (hx > 0 ? 3 : -3); fy = hipY + 7; }
      else if (dying) { fx = hx + 3; fy = hipY + 7; }
      else if (e.state === 'recover') { fx = hx + (hx > 0 ? 6 : -2); fy = hipY + 10; }
      else { const sw = e.state === 'approach' ? Math.sin(e.moveT * TAU * 0.6 + ph) : 0; fx = hx + sw * 6; fy = hipY + 11; }
      const kx = (hx + fx) / 2 + (hx > 0 ? 1.5 : -2.5), ky = (hipY + fy) / 2;
      ctx.beginPath(); ctx.moveTo(hx, hipY); ctx.lineTo(kx, ky); ctx.lineTo(fx, fy); ctx.stroke();
      ctx.fillStyle = '#26221e'; ctx.beginPath(); ctx.ellipse(fx + 1, fy, 3.2, 2, 0, 0, TAU); ctx.fill();
    }
    // 몸통 + 큰 어깨
    ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#9fb4c4' : fur);
    ctx.beginPath(); ctx.ellipse(0, bodyY, L, ry, 0, 0, TAU); ctx.fill();
    ctx.beginPath(); ctx.ellipse(L * 0.45, bodyY - 3, L * 0.5, ry * 0.95, 0, 0, TAU); ctx.fill(); // 어깨
    ctx.fillStyle = e.flash > 0 ? '#fff' : belly; ctx.beginPath(); ctx.ellipse(0, bodyY + 3.5, L * 0.7, ry * 0.45, 0, 0, TAU); ctx.fill();
    // 오래된 상처
    ctx.strokeStyle = '#3a2a1c'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(-6, bodyY - 5); ctx.lineTo(-1, bodyY + 1); ctx.moveTo(-3, bodyY - 6); ctx.lineTo(2, bodyY); ctx.stroke();
    // 가시갈기(목·등의 검은 가시). 세우면 길어진다
    ctx.fillStyle = thorn;
    for (let i = 0; i < 7; i++) { const bx = L * 0.75 - i * 4.2, by = bodyY - ry * 0.85 + (i > 3 ? 1 : 0); const h = (6 + (i < 4 ? 4 : 1)) * (1 + 0.6 * maneUp); ctx.beginPath(); ctx.moveTo(bx - 1.6, by + 1); ctx.lineTo(bx - 3 + (i % 2), by - h); ctx.lineTo(bx + 1.6, by + 1); ctx.closePath(); ctx.fill(); }
    // 머리(젖힘)
    const hx = L - 1, hy = bodyY + headY;
    ctx.save(); ctx.translate(hx, hy); ctx.rotate(headTilt);
    ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#9fb4c4' : fur);
    ctx.beginPath(); ctx.arc(0, 0, 9, 0, TAU); ctx.fill();
    ctx.beginPath(); ctx.moveTo(4, -5); ctx.lineTo(19, 1); ctx.lineTo(5, 4); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#1e1f22'; ctx.beginPath(); ctx.arc(18.5, 0.5, 2, 0, TAU); ctx.fill();
    // 위 송곳니: 한쪽은 부러짐
    ctx.fillStyle = '#f3ead8'; ctx.beginPath(); ctx.moveTo(11, 3); ctx.lineTo(12.5, 8.5); ctx.lineTo(14, 3); ctx.fill();
    ctx.beginPath(); ctx.moveTo(6, 3.5); ctx.lineTo(6.8, 5.5); ctx.lineTo(8, 3.5); ctx.fill(); // 부러진 송곳니(짧음)
    // 아래턱
    ctx.save(); ctx.translate(4, 3); ctx.rotate(jaw);
    ctx.fillStyle = e.flash > 0 ? '#fff' : fur2; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(14, 0); ctx.lineTo(1, 4.5); ctx.closePath(); ctx.fill();
    if (jaw > 0.25) { ctx.fillStyle = '#f3ead8'; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(3 + i * 2.8, 0); ctx.lineTo(4 + i * 2.8, -2.6); ctx.lineTo(5 + i * 2.8, 0); ctx.fill(); } }
    ctx.restore();
    // 귀
    const earBack = (e.state === 'dash_aim' || e.state === 'dash_lock' || e.state === 'dash') ? -4 : (maneUp ? 2 : 0);
    ctx.fillStyle = e.flash > 0 ? '#fff' : fur2;
    ctx.beginPath(); ctx.moveTo(-4, -5); ctx.lineTo(-8 + earBack, -17); ctx.lineTo(1, -8); ctx.fill();
    ctx.beginPath(); ctx.moveTo(1, -6); ctx.lineTo(-1 + earBack, -16); ctx.lineTo(6, -6); ctx.fill();
    // 눈
    ctx.fillStyle = dying ? '#333' : (e.state === 'approach' ? '#ffb347' : '#ff3b3b'); ctx.beginPath(); ctx.arc(4, -2.5, 2.2, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#2a1e12'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(-2, -8); ctx.lineTo(2, 1); ctx.stroke(); // 얼굴 흉터
    ctx.restore();
    if (e.biteT < 0.15 && !dying) { ctx.strokeStyle = `rgba(255,255,255,${1 - e.biteT / 0.15})`; ctx.lineWidth = 2.5; for (let i = -1; i <= 1; i++) { ctx.beginPath(); ctx.arc(hx + 16, hy + 1, 10 + 8 * (e.biteT / 0.15), -0.6 + i * 0.5, -0.2 + i * 0.5); ctx.stroke(); } }
    ctx.restore();
    // 상태 아이콘·흔적은 drawEnemy 공통 처리
  }

  // ---------- 궁수·포자(간이 표현, 후속 작업) ----------
  function drawArcher(ctx, st, e) {
    const d = e.def, toP = Math.atan2(st.player.y - e.y, st.player.x - e.x);
    const faceX = Math.cos(toP) >= 0 ? 1 : -1;
    ctx.save(); ctx.translate(e.x, e.y); if (e.dead) ctx.globalAlpha = Math.max(0, 1 - e.deathT / 0.5);
    shadow(ctx, 0, 14, 11, 4); ctx.scale(faceX, 1);
    const walk = e.state === 'approach' ? Math.sin(e.moveT * TAU) * 3 : 0;
    ctx.strokeStyle = '#3d4a2a'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-3, 4); ctx.lineTo(-3 + walk, 14); ctx.moveTo(3, 4); ctx.lineTo(3 - walk, 14); ctx.stroke();
    ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#b9e8d0' : d.color); ctx.beginPath(); ctx.roundRect ? ctx.roundRect(-6, -8, 12, 14, 3) : ctx.rect(-6, -8, 12, 14); ctx.fill();
    ctx.fillStyle = '#e8c39e'; ctx.beginPath(); ctx.arc(0, -13, 5, 0, TAU); ctx.fill();
    ctx.fillStyle = '#2e5a2c'; ctx.beginPath(); ctx.moveTo(-6, -14); ctx.lineTo(0, -21); ctx.lineTo(7, -14); ctx.fill();
    const pull = e.state === 'aim' ? Math.min(1, e.stateT / d.aim) : (e.state === 'lock' ? 1 : 0);
    const ba = e.state === 'aim' ? e.aimAngle : (e.state === 'lock' ? e.dir : toP);
    ctx.save(); ctx.rotate(faceX < 0 ? Math.PI - ba : ba); ctx.strokeStyle = '#d9b26f'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(8, -2, 11, -1.2, 1.2); ctx.stroke();
    ctx.strokeStyle = '#eee'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(8 + Math.cos(-1.2) * 11, -2 + Math.sin(-1.2) * 11); ctx.lineTo(8 - pull * 10, -2); ctx.lineTo(8 + Math.cos(1.2) * 11, -2 + Math.sin(1.2) * 11); ctx.stroke();
    if (pull > 0) { ctx.strokeStyle = '#ffd9a0'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(8 - pull * 10, -2); ctx.lineTo(20, -2); ctx.stroke(); }
    ctx.restore(); ctx.restore();
  }
  function drawSpore(ctx, st, e) {
    const d = e.def;
    ctx.save(); ctx.translate(e.x, e.y); if (e.dead) ctx.globalAlpha = Math.max(0, 1 - e.deathT / 0.5);
    shadow(ctx, 0, 16, 16, 5);
    const sw = e.state === 'swell' ? 1 + 0.45 * (e.stateT / d.swell) : (e.state === 'recover' ? 0.85 : 1 + 0.05 * Math.sin(e.animT * 6));
    ctx.scale(sw, sw);
    ctx.fillStyle = e.flash > 0 ? '#fff' : (e.chill > 0 ? '#c9b3e8' : d.color);
    ctx.beginPath(); ctx.arc(0, 0, e.r, 0, TAU); ctx.fill();
    for (let i = 0; i < 6; i++) { const a = i * TAU / 6 + e.animT * 0.5; ctx.beginPath(); ctx.arc(Math.cos(a) * e.r * 0.85, Math.sin(a) * e.r * 0.85, e.r * 0.35, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#d9a6ff'; for (let i = 0; i < 5; i++) { const a = i * 1.26 + 0.4; ctx.beginPath(); ctx.arc(Math.cos(a) * e.r * 0.5, Math.sin(a) * e.r * 0.5, 2.5, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#3a1d55'; ctx.beginPath(); ctx.arc(-5, -3, 3, 0, TAU); ctx.arc(5, -3, 3, 0, TAU); ctx.fill();
    ctx.restore();
  }

  // ---------- v0.6 신규 몬스터(도형·색·기호·움직임으로 구분. 그래픽 본작업은 나중) ----------
  function begin(ctx, st, e, sy, sx) { ctx.save(); ctx.translate(e.x, e.y); if (e.dead) ctx.globalAlpha = Math.max(0, 1 - e.deathT / 0.5); shadow(ctx, 0, sy || 14, sx || 12, 4); }
  function body(ctx, e, color) { return e.flash > 0 ? '#fff' : (e.chill > 0 ? '#bcd6e6' : color); }
  function drawBoar(ctx, st, e) { // 넓은 타원 몸통 + 흰 엄니 2개, 돌파 중 잔상
    const d = e.def, ang = e.state === 'charge_aim' ? e.aimAngle : (e.state === 'charge_lock' || e.state === 'charge') ? e.dir : Math.atan2(st.player.y - e.y, st.player.x - e.x);
    begin(ctx, st, e, 16, 20);
    if (e.state === 'charge') for (let i = 1; i <= 3; i++) { ctx.fillStyle = `rgba(160,120,80,${0.25 / i})`; ctx.beginPath(); ctx.ellipse(-Math.cos(e.dir) * 14 * i, -Math.sin(e.dir) * 14 * i, 22, 12, e.dir, 0, TAU); ctx.fill(); }
    ctx.rotate(ang); const crouch = e.state === 'charge_aim' || e.state === 'charge_lock';
    if (e.state === 'stagger') ctx.rotate(Math.sin(e.stateT * 10) * 0.2);
    ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.ellipse(crouch ? -4 : 0, 0, 22, crouch ? 11 : 13, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = '#5a4630'; ctx.beginPath(); ctx.ellipse(-6, -4, 14, 5, 0, 0, TAU); ctx.fill(); // 등 갈기
    ctx.fillStyle = body(ctx, e, '#6f5238'); ctx.beginPath(); ctx.arc(20, 0, 9, 0, TAU); ctx.fill(); // 머리
    ctx.fillStyle = '#f5efe0'; ctx.beginPath(); ctx.moveTo(24, -4); ctx.lineTo(34, -10); ctx.lineTo(28, -2); ctx.fill(); ctx.beginPath(); ctx.moveTo(24, 4); ctx.lineTo(34, 10); ctx.lineTo(28, 2); ctx.fill(); // 엄니
    ctx.fillStyle = e.state === 'approach' ? '#ffd27a' : '#ff4a4a'; ctx.beginPath(); ctx.arc(22, -4, 1.8, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#4a3624'; ctx.lineWidth = 3; for (const lx of [-12, -4, 8, 14]) { const sw = e.state === 'approach' ? Math.sin(e.moveT * TAU + lx) * 4 : 0; ctx.beginPath(); ctx.moveTo(lx, 8); ctx.lineTo(lx + sw, 17); ctx.stroke(); }
    if (e.state === 'stagger') { ctx.rotate(-ang); ctx.fillStyle = '#ffe066'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; for (let i = 0; i < 3; i++) { const a = st.t * 4 + i * 2.1; ctx.fillText('★', Math.cos(a) * 16, -26 + Math.sin(a) * 5); } }
    ctx.restore();
  }
  function drawShieldbearer(ctx, st, e) { // 사람 실루엣 + 큰 직사각 방패(바라보는 방향). 준비·공격 중에는 방패가 옆으로 열린다
    const d = e.def, open = e.state === 'bash_aim' || e.state === 'bash' || e.state === 'recover';
    begin(ctx, st, e, 15, 12);
    const walk = e.state === 'approach' ? Math.sin(e.moveT * TAU) * 3 : 0;
    ctx.strokeStyle = '#3d4552'; ctx.lineWidth = 3.5; ctx.beginPath(); ctx.moveTo(-4, 4); ctx.lineTo(-4 + walk, 15); ctx.moveTo(4, 4); ctx.lineTo(4 - walk, 15); ctx.stroke();
    ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.roundRect ? ctx.roundRect(-8, -10, 16, 18, 4) : ctx.rect(-8, -10, 16, 18); ctx.fill();
    ctx.fillStyle = '#d8c8a8'; ctx.beginPath(); ctx.arc(0, -15, 6, 0, TAU); ctx.fill(); ctx.fillStyle = '#4a5566'; ctx.fillRect(-7, -22, 14, 5); // 투구
    const fa = e.face == null ? 0 : e.face;
    ctx.save(); ctx.rotate(fa); if (open) ctx.rotate(-1.2);
    ctx.fillStyle = e.blockedT > 0 ? '#ffffff' : '#c9a44a'; ctx.strokeStyle = '#5a4620'; ctx.lineWidth = 2; ctx.beginPath(); ctx.roundRect ? ctx.roundRect(10, -16, 8, 32, 3) : ctx.rect(10, -16, 8, 32); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#7a5a2a'; ctx.fillRect(13, -3, 2, 6);
    if (e.state === 'bash_aim' || e.state === 'bash') { ctx.rotate(1.2); ctx.strokeStyle = '#e8e8f0'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(6, 0); ctx.lineTo(24, 0); ctx.stroke(); }
    ctx.restore();
    if (e.blockedT > 0) { ctx.fillStyle = '#ffffff'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('막음', 0, -30); }
    ctx.restore();
  }
  function drawShaman(ctx, st, e) { // 보라 로브 삼각형 + 지팡이 구슬. 시전 중 지팡이가 빛난다
    const d = e.def; begin(ctx, st, e, 15, 11);
    const bob = Math.sin(e.animT * 3) * 1.5;
    ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.moveTo(0, -18 + bob); ctx.lineTo(-11, 14); ctx.lineTo(11, 14); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#3a1d55'; ctx.beginPath(); ctx.arc(0, -14 + bob, 6, 0, TAU); ctx.fill(); // 두건 속 얼굴(어둡게)
    ctx.fillStyle = '#e9b6ff'; ctx.beginPath(); ctx.arc(-2, -15 + bob, 1.6, 0, TAU); ctx.arc(2, -15 + bob, 1.6, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#6b4a2a'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(12, 12); ctx.lineTo(14, -20 + bob); ctx.stroke();
    const glow = e.state === 'cast' ? 1 : e.state === 'hex_aim' ? 0.6 : 0.25; ctx.fillStyle = `rgba(233,182,255,${0.3 + glow * 0.6})`; ctx.beginPath(); ctx.arc(14, -22 + bob, 5 + glow * 3, 0, TAU); ctx.fill();
    ctx.restore();
  }
  function drawBomber(ctx, st, e) { // 둥근 폭탄 몸통 + 짧은 다리 + 심지 불꽃. 준비 중 깜빡이며 커진다
    const d = e.def; begin(ctx, st, e, 15, 13);
    const fuse = e.state === 'fuse', k = fuse ? e.stateT / d.fuse : 0, pulse = fuse ? 1 + 0.15 * Math.sin(st.t * (20 + 40 * k)) : 1;
    ctx.strokeStyle = '#4a3020'; ctx.lineWidth = 3; const walk = e.state === 'approach' ? Math.sin(e.moveT * TAU * 1.5) * 3 : 0; ctx.beginPath(); ctx.moveTo(-5, 8); ctx.lineTo(-5 + walk, 16); ctx.moveTo(5, 8); ctx.lineTo(5 - walk, 16); ctx.stroke();
    ctx.fillStyle = e.flash > 0 ? '#fff' : (fuse && Math.floor(st.t * (6 + 20 * k)) % 2 ? '#ff9a6a' : body(ctx, e, d.color)); ctx.beginPath(); ctx.arc(0, 0, 13 * pulse, 0, TAU); ctx.fill();
    ctx.fillStyle = '#2b1d14'; ctx.beginPath(); ctx.arc(-4, -2, 2.5, 0, TAU); ctx.arc(4, -2, 2.5, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#3a2a1a'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(0, -13); ctx.quadraticCurveTo(6, -22, 10, -18); ctx.stroke(); // 심지
    ctx.fillStyle = '#ffd27a'; ctx.beginPath(); ctx.arc(10 + Math.sin(st.t * 30) * 1.5, -18, fuse ? 4 : 2.5, 0, TAU); ctx.fill();
    ctx.restore();
  }
  function drawBurrower(ctx, st, e) { // 마디 진 벌레. 지하에서는 흙더미만 보인다
    const d = e.def;
    if (e.hidden || e.state === 'dive') { ctx.save(); ctx.translate(e.x, e.y); const k = e.state === 'dive' ? 1 - e.stateT / d.dive : 1; ctx.fillStyle = '#5a4630'; ctx.beginPath(); ctx.ellipse(0, 4, 18, 8, 0, 0, TAU); ctx.fill(); ctx.fillStyle = '#7a6040'; ctx.beginPath(); ctx.ellipse(0, 0, 14, 6, 0, 0, TAU); ctx.fill(); if (e.state === 'dive') { ctx.globalAlpha = k; ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.arc(0, -8 * k, 9, 0, TAU); ctx.fill(); } ctx.restore(); return; }
    begin(ctx, st, e, 14, 16);
    const ang = e.state === 'bite_aim' ? e.aimAngle : Math.atan2(st.player.y - e.y, st.player.x - e.x); ctx.rotate(ang);
    const up = e.state === 'emerge' || e.state === 'stagger';
    for (let i = 3; i >= 0; i--) { ctx.fillStyle = body(ctx, e, i % 2 ? d.color : '#8a6840'); ctx.beginPath(); ctx.arc(-i * 9 + 6, up ? -i * 4 : Math.sin(e.moveT * TAU + i) * 2, 9 - i * 0.8, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#2b1d14'; ctx.beginPath(); ctx.arc(10, -3, 2, 0, TAU); ctx.arc(10, 3, 2, 0, TAU); ctx.fill();
    ctx.fillStyle = '#f0e8d8'; ctx.beginPath(); ctx.moveTo(13, -4); ctx.lineTo(20, -7 - (e.state === 'bite_aim' ? 4 : 0)); ctx.lineTo(15, -1); ctx.fill(); ctx.beginPath(); ctx.moveTo(13, 4); ctx.lineTo(20, 7 + (e.state === 'bite_aim' ? 4 : 0)); ctx.lineTo(15, 1); ctx.fill();
    ctx.restore();
  }
  function drawSpider(ctx, st, e) { // 작은 몸 + 다리 8개
    const d = e.def; begin(ctx, st, e, 12, 16);
    const ang = Math.atan2(st.player.y - e.y, st.player.x - e.x); ctx.rotate(ang);
    ctx.strokeStyle = '#2f2f3a'; ctx.lineWidth = 2; for (let i = 0; i < 4; i++) { const a = -0.9 + i * 0.6, sw = e.state === 'approach' ? Math.sin(e.moveT * TAU * 2 + i) * 3 : 0; for (const sgn of [1, -1]) { ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.cos(a) * 12, sgn * (10 + sw)); ctx.lineTo(Math.cos(a) * 20, sgn * (16 + sw)); ctx.stroke(); } }
    ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.ellipse(-4, 0, 11, 8, 0, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.arc(8, 0, 6, 0, TAU); ctx.fill();
    ctx.fillStyle = e.state === 'web_aim' ? '#e8f0ff' : '#ff4a4a'; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.arc(10 + (i % 2) * 2, -4 + i * 2.6, 1.3, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#c9a0ff'; ctx.beginPath(); ctx.moveTo(-8, -4); ctx.lineTo(-2, 0); ctx.lineTo(-8, 4); ctx.fill(); // 등 무늬
    ctx.restore();
  }
  function drawFrostcaller(ctx, st, e) { // 하늘색 로브 + 얼음 지팡이. 시전 중 지팡이를 든다
    const d = e.def; begin(ctx, st, e, 15, 11);
    ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.moveTo(-9, 14); ctx.lineTo(-7, -12); ctx.lineTo(7, -12); ctx.lineTo(9, 14); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#e8f4ff'; ctx.beginPath(); ctx.arc(0, -16, 6, 0, TAU); ctx.fill(); ctx.fillStyle = '#4a7a9a'; ctx.beginPath(); ctx.moveTo(-7, -16); ctx.lineTo(0, -26); ctx.lineTo(7, -16); ctx.fill();
    const raise = e.state === 'cast' ? -10 : 0; ctx.strokeStyle = '#8fb6d0'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(11, 12); ctx.lineTo(13, -18 + raise); ctx.stroke();
    ctx.fillStyle = e.state === 'cast' ? '#ffffff' : '#bfefff'; ctx.beginPath(); ctx.moveTo(13, -28 + raise); ctx.lineTo(18, -20 + raise); ctx.lineTo(13, -14 + raise); ctx.lineTo(8, -20 + raise); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
  function drawRogue(ctx, st, e) { // 가늘고 빠른 붉은 실루엣 + 단검 2개
    const d = e.def; begin(ctx, st, e, 15, 10);
    const ang = (e.state === 'slash1_aim' || e.state === 'slash2_aim') ? e.aimAngle : Math.atan2(st.player.y - e.y, st.player.x - e.x); const faceX = Math.cos(ang) >= 0 ? 1 : -1; ctx.scale(faceX, 1);
    const walk = e.state === 'approach' ? Math.sin(e.moveT * TAU * 1.3) * 4 : 0, lean = e.state === 'approach' ? 0.15 : 0; ctx.rotate(lean);
    ctx.strokeStyle = '#4a2a34'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-3, 4); ctx.lineTo(-3 + walk, 15); ctx.moveTo(3, 4); ctx.lineTo(3 - walk, 15); ctx.stroke();
    ctx.fillStyle = body(ctx, e, d.color); ctx.beginPath(); ctx.roundRect ? ctx.roundRect(-5, -9, 10, 15, 3) : ctx.rect(-5, -9, 10, 15); ctx.fill();
    ctx.fillStyle = '#e8c39e'; ctx.beginPath(); ctx.arc(0, -14, 5, 0, TAU); ctx.fill(); ctx.fillStyle = '#5a2a34'; ctx.fillRect(-5, -16, 10, 3); // 두건 띠
    const k = e.state === 'slash1_aim' ? e.stateT / d.aim1 : e.state === 'slash2_aim' ? e.stateT / d.aim2 : 0; const swing = e.biteT < 0.12 ? 1.2 : 0;
    ctx.strokeStyle = '#e6edf5'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(5, -4); ctx.lineTo(16 + swing * 6, -12 + k * 6 + swing * 8); ctx.moveTo(5, 2); ctx.lineTo(16 + swing * 6, 10 - k * 6 - swing * 8); ctx.stroke();
    ctx.restore();
  }
  const NEW_DRAW = { boar: drawBoar, shieldbearer: drawShieldbearer, shaman: drawShaman, bomber: drawBomber, burrower: drawBurrower, spider: drawSpider, frostcaller: drawFrostcaller, rogue: drawRogue };
  // 구조물(제단): 돌기둥 + 색 문양. 실루엣은 몬스터와 구분(사각 기단·수직 기둥). 파괴되면 무너진 돌
  function drawStructure(ctx, st, e) {
    const c = e.def.color, k = e.dead ? Math.min(1, e.deathT * 2) : 0;
    ctx.fillStyle = '#3a3a44'; ctx.fillRect(e.x - e.r, e.y + e.r * 0.4 - 6, e.r * 2, 12); // 기단
    if (e.dead) { ctx.fillStyle = '#55555f'; for (let i = 0; i < 4; i++) { const a = i * 1.6; ctx.beginPath(); ctx.arc(e.x + Math.cos(a) * e.r * 0.8 * k, e.y + e.r * 0.3 + Math.sin(a) * 6, 6 - k * 2, 0, TAU); ctx.fill(); } return; }
    ctx.fillStyle = e.flash > 0 ? '#ffffff' : '#6a6a78'; ctx.fillRect(e.x - e.r * 0.45, e.y - e.r * 1.5, e.r * 0.9, e.r * 1.9); // 기둥
    ctx.strokeStyle = c; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(e.x, e.y - e.r * 0.7, e.r * 0.28, 0, TAU); ctx.stroke(); // 문양
    const pulse = 0.5 + 0.5 * Math.sin(st.t * 3 + e.id); ctx.fillStyle = c; ctx.globalAlpha = 0.35 + 0.4 * pulse; ctx.beginPath(); ctx.arc(e.x, e.y - e.r * 0.7, e.r * 0.14, 0, TAU); ctx.fill(); ctx.globalAlpha = 1;
    if (e.altar === 'heal') { ctx.strokeStyle = c; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(e.x, e.y - e.r * 1.75); ctx.lineTo(e.x, e.y - e.r * 1.55); ctx.moveTo(e.x - 6, e.y - e.r * 1.65); ctx.lineTo(e.x + 6, e.y - e.r * 1.65); ctx.stroke(); }
    else if (e.altar === 'hazard') { ctx.fillStyle = c; ctx.beginPath(); ctx.moveTo(e.x, e.y - e.r * 1.85); ctx.lineTo(e.x - 6, e.y - e.r * 1.55); ctx.lineTo(e.x + 6, e.y - e.r * 1.55); ctx.fill(); }
    else if (e.altar === 'reinforce') { ctx.strokeStyle = c; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(e.x, e.y - e.r * 1.7, 6, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.arc(e.x, e.y - e.r * 1.7, 2, 0, TAU); ctx.fill(); }
    ctx.fillStyle = '#eee'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(e.def.name + (e.budget !== Infinity && e.budget != null ? ` (${e.altar === 'heal' ? '치료 ' : '증원 '}${Math.round(e.budget)})` : ''), e.x, e.y + e.r + 22);
    if (st.obj && PA.Objectives && PA.Objectives.autoTarget(st) === e) { ctx.strokeStyle = '#ffe066'; ctx.lineWidth = 2; ctx.setLineDash([4, 3]); ctx.beginPath(); ctx.arc(e.x, e.y - e.r * 0.4, e.r + 8, 0, TAU); ctx.stroke(); ctx.setLineDash([]); }
  }
  // 목표 객체: 우리(창살 상자)·봉인 지점(룬 원)·출구(아치)·포로(작은 사람)
  function drawObjects(ctx, st) {
    for (const o of st.objects || []) {
      if (o.kind === 'cage') {
        ctx.fillStyle = o.freed ? 'rgba(60,60,70,0.5)' : '#2b2b33'; ctx.fillRect(o.x - o.r, o.y - o.r * 0.9, o.r * 2, o.r * 1.8);
        ctx.strokeStyle = o.freed ? '#666' : '#c8c8d0'; ctx.lineWidth = 2; for (let i = -2; i <= 2; i++) { ctx.beginPath(); ctx.moveTo(o.x + i * o.r * 0.45, o.y - o.r * 0.9); ctx.lineTo(o.x + i * o.r * 0.45, o.y + o.r * 0.9); ctx.stroke(); }
        ctx.strokeRect(o.x - o.r, o.y - o.r * 0.9, o.r * 2, o.r * 1.8);
        if (!o.freed) { ctx.fillStyle = '#e9c9a8'; ctx.beginPath(); ctx.arc(o.x, o.y - 4, 6, 0, TAU); ctx.fill(); ctx.fillRect(o.x - 5, o.y + 2, 10, 12); const near = PA.OBJECTIVES.rescue.near; ctx.strokeStyle = 'rgba(156,255,176,0.5)'; ctx.setLineDash([5, 5]); ctx.beginPath(); ctx.arc(o.x, o.y, near, 0, TAU); ctx.stroke(); ctx.setLineDash([]); if (o.progress > 0) { ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(o.x - 24, o.y - o.r - 16, 48, 6); ctx.fillStyle = '#9cffb0'; ctx.fillRect(o.x - 24, o.y - o.r - 16, 48 * (o.progress / o.total), 6); } }
        ctx.fillStyle = '#eee'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(o.freed ? '빈 우리' : `포로 ${o.id}`, o.x, o.y + o.r + 16);
      } else if (o.kind === 'seal') {
        const O = st.obj, k = O ? O.progress / O.total : 0, pulse = 0.5 + 0.5 * Math.sin(st.t * 4);
        ctx.fillStyle = O && !O.paused ? `rgba(120,200,255,${0.15 + 0.1 * pulse})` : 'rgba(120,200,255,0.08)'; ctx.beginPath(); ctx.arc(o.x, o.y, o.r, 0, TAU); ctx.fill();
        ctx.strokeStyle = o.moving ? 'rgba(255,200,80,0.9)' : 'rgba(160,220,255,0.9)'; ctx.lineWidth = 3; ctx.setLineDash(o.moving ? [4, 4] : []); ctx.beginPath(); ctx.arc(o.x, o.y, o.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
        for (let i = 0; i < 6; i++) { const a = i * TAU / 6 + st.t * 0.4; ctx.strokeStyle = 'rgba(160,220,255,0.6)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(o.x + Math.cos(a) * o.r * 0.5, o.y + Math.sin(a) * o.r * 0.5); ctx.lineTo(o.x + Math.cos(a) * o.r * 0.85, o.y + Math.sin(a) * o.r * 0.85); ctx.stroke(); }
        ctx.strokeStyle = '#bfefff'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(o.x, o.y, o.r + 6, -Math.PI / 2, -Math.PI / 2 + TAU * k); ctx.stroke();
        if (o.moving && o.next) { ctx.strokeStyle = 'rgba(255,200,80,0.9)'; ctx.lineWidth = 3; ctx.setLineDash([8, 6]); ctx.beginPath(); ctx.moveTo(o.x, o.y); ctx.lineTo(o.next.x, o.next.y); ctx.stroke(); ctx.beginPath(); ctx.arc(o.next.x, o.next.y, o.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]); ctx.fillStyle = '#ffd166'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('봉인 지점 이동!', o.next.x, o.next.y - o.r - 8); }
        ctx.fillStyle = '#eef'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(O && O.paused ? (O.hitPause > 0 ? '피격: 잠시 정지' : '지점 밖: 정지') : '봉인 해제 중', o.x, o.y - o.r - 10);
      } else if (o.kind === 'exit') {
        ctx.strokeStyle = o.open ? '#9cffb0' : '#777'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(o.x, o.y + 10, o.r * 0.7, Math.PI, 0); ctx.stroke(); ctx.beginPath(); ctx.moveTo(o.x - o.r * 0.7, o.y + 10); ctx.lineTo(o.x - o.r * 0.7, o.y + 30); ctx.moveTo(o.x + o.r * 0.7, o.y + 10); ctx.lineTo(o.x + o.r * 0.7, o.y + 30); ctx.stroke();
        if (o.open) { ctx.strokeStyle = 'rgba(156,255,176,0.6)'; ctx.lineWidth = 2; ctx.setLineDash([5, 5]); ctx.beginPath(); ctx.arc(o.x, o.y, o.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]); }
        ctx.fillStyle = o.open ? '#9cffb0' : '#aaa'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(o.open ? '출구 열림 — 여기로' : '출구 (포로를 모두 구하면 열림)', o.x, o.y - 12);
      } else if (o.kind === 'prisoner' && !o.gone) {
        ctx.fillStyle = '#e9c9a8'; ctx.beginPath(); ctx.arc(o.x, o.y - 8, 5, 0, TAU); ctx.fill(); ctx.fillStyle = '#b8a080'; ctx.fillRect(o.x - 4, o.y - 3, 8, 12);
        ctx.fillStyle = '#9cffb0'; ctx.font = `10px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('탈출 중', o.x, o.y - 16);
      }
    }
  }
  function drawEnemy(ctx, st, e) {
    if (e.structure) { drawStructure(ctx, st, e); if (e.dead) return; }
    else if (e.boss) drawBoss(ctx, st, e);
    else if (e.type === 'wolf' || e.type === 'wolf_alpha') drawWolf(ctx, st, e);
    else if (e.type === 'archer') drawArcher(ctx, st, e);
    else if (e.type === 'spore') drawSpore(ctx, st, e);
    else if (NEW_DRAW[e.type]) NEW_DRAW[e.type](ctx, st, e);
    if (e.dead) return;
    if (e.blockedT > 0) e.blockedT -= 1 / 60;
    if (e.hidden) return;
    if (e.state === 'stagger' && !e.boss) { ctx.fillStyle = '#ffe066'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('빈틈', e.x, e.y + e.r + 20); }
    const inField = PA.Combat.inField(st, e);
    if (!e.boss && e.hp < e.hpMax) { const w = e.r * 2.6; ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(e.x - w / 2, e.y - e.r - 16, w, 5); ctx.fillStyle = e.elite ? '#ffe066' : '#ff6b6b'; ctx.fillRect(e.x - w / 2, e.y - e.r - 16, w * Math.max(0, e.hp / e.hpMax), 5); }
    let ix = e.x - 10, iy = e.y - e.r - 28;
    if (e.state === 'recover' || e.state === 'stagger') { statusIcon(ctx, ix, iy, 'exposed'); ix += 16; }
    if (e.chill > 0) { statusIcon(ctx, ix, iy, 'chill'); ix += 16; }
    if (e.burn && e.burn.t > 0) { ctx.fillStyle = '#ff9f43'; ctx.beginPath(); ctx.moveTo(ix, iy - 7); ctx.quadraticCurveTo(ix + 7, iy, ix, iy + 7); ctx.quadraticCurveTo(ix - 7, iy, ix, iy - 7); ctx.fill(); ix += 16; }
    if (e.bleed && e.bleed.t > 0) { ctx.fillStyle = '#ff5a5a'; ctx.beginPath(); ctx.arc(ix, iy + 2, 4, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.moveTo(ix, iy - 7); ctx.lineTo(ix + 4, iy + 1); ctx.lineTo(ix - 4, iy + 1); ctx.fill(); ix += 16; }
    if (e.conduct > 0) { ctx.strokeStyle = '#bfe8ff'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(ix + 3, iy - 7); ctx.lineTo(ix - 3, iy); ctx.lineTo(ix + 2, iy); ctx.lineTo(ix - 3, iy + 7); ctx.stroke(); ix += 16; }
    if (inField) { statusIcon(ctx, ix, iy, 'slow'); ix += 16; }
    if (st.markTarget === e) statusIcon(ctx, e.x, e.y - e.r - 44, 'mark');
    if (e.chill > 0) { ctx.strokeStyle = 'rgba(160,230,255,0.85)'; ctx.lineWidth = 2; ctx.setLineDash([3, 4]); ctx.beginPath(); ctx.arc(e.x, e.y, e.r * 1.4 + 3, st.t * 1.5, st.t * 1.5 + TAU); ctx.stroke(); ctx.setLineDash([]); }
    if (e.stasis > 0) { const w = e.stasis * 7; ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(e.x - w / 2 - 2, e.y + e.r + 8, w + 4, 10); for (let i = 0; i < e.stasis; i++) { ctx.fillStyle = i === e.stasis - 1 && (Math.floor(st.t * 8) % 2) ? '#ffffff' : '#a9d8ff'; ctx.fillRect(e.x - w / 2 + i * 7, e.y + e.r + 10, 5, 6); } ctx.fillStyle = '#cfeaff'; ctx.font = `bold 10px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText('흔적 ' + e.stasis, e.x + w / 2 + 4, e.y + e.r + 17); }
    if (e.elite) { ctx.fillStyle = '#ffe066'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('정예 · ' + e.name, e.x, e.y + e.r + 22); }
    if (e.summoned && e.grace > 0) { ctx.fillStyle = 'rgba(255,200,80,0.9)'; ctx.font = `11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('소환', e.x, e.y - e.r - 34); }
  }

  // ---------- 마검사 (측면, 좌우 반전) ----------
  function drawSwordsman(ctx, st) {
    const p = st.player, b = st.build;
    const faceLeft = Math.cos(p.face) < 0;
    const la = faceLeft ? Math.PI - p.face : p.face; // 반전 좌표계에서의 바라보는 각도
    ctx.save(); ctx.translate(p.x, p.y);
    shadow(ctx, 0, 17 * VS, 13 * VS, 4.5 * VS);
    // 회피 잔상
    if (p.dodge.active) for (let i = 1; i <= 3; i++) { ctx.fillStyle = `rgba(120,190,255,${0.28 / i})`; ctx.beginPath(); ctx.ellipse(-p.dodge.dx * 13 * i, -p.dodge.dy * 13 * i, 10, 14, 0, 0, TAU); ctx.fill(); }
    if (p.hitProt > 0 && Math.floor(st.t * 20) % 2 === 0) ctx.globalAlpha = 0.5;
    if (p.hurtT < 0.2) ctx.translate(Math.sin(st.t * 90) * 2.5, 0); // 피격 흔들림
    ctx.scale(faceLeft ? -VS : VS, VS);
    if (p.dodge.active) { const k = p.dodge.t / PA.CONFIG.PLAYER.dodge.duration; ctx.rotate(k * TAU * ((faceLeft ? -p.dodge.dx : p.dodge.dx) >= 0 ? 1 : -1)); ctx.scale(1, 0.85); }
    const walk = p.moving && !p.dodge.active ? Math.sin(p.walkT * 13) : 0;
    const bob = p.moving && !p.dodge.active ? Math.abs(Math.cos(p.walkT * 13)) * -1.5 : Math.sin(p.animT * 2) * 0.6;
    const hurt = p.flash > 0;
    // 망토
    ctx.fillStyle = hurt ? '#a04050' : '#25335c'; ctx.beginPath(); ctx.moveTo(-3, -8 + bob); ctx.lineTo(-9 - Math.abs(walk) * 4 - (p.moving ? 3 : 0), 6 + bob + Math.sin(p.animT * 6) * 1.5); ctx.lineTo(-2, 9 + bob); ctx.lineTo(4, -6 + bob); ctx.closePath(); ctx.fill();
    // 다리·장화
    ctx.strokeStyle = hurt ? '#c07080' : '#3a3f55'; ctx.lineWidth = 4; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(-3, 6 + bob); ctx.lineTo(-3 + walk * 5, 16); ctx.moveTo(3, 6 + bob); ctx.lineTo(3 - walk * 5, 16); ctx.stroke();
    ctx.fillStyle = '#26221e'; ctx.beginPath(); ctx.ellipse(-3 + walk * 5 + 1, 17, 4, 2, 0, 0, TAU); ctx.ellipse(3 - walk * 5 + 1, 17, 4, 2, 0, 0, TAU); ctx.fill();
    // 몸통(갑옷)
    ctx.fillStyle = hurt ? '#ff9a9a' : '#4d7fd0'; ctx.beginPath(); ctx.roundRect ? ctx.roundRect(-6.5, -9 + bob, 13, 17, 3) : ctx.rect(-6.5, -9 + bob, 13, 17); ctx.fill();
    ctx.fillStyle = hurt ? '#ffc0c0' : '#8fb6ee'; ctx.fillRect(-2, -7 + bob, 5, 12);
    ctx.fillStyle = '#2b2620'; ctx.fillRect(-6.5, 3 + bob, 13, 2.5);
    // 뒷팔
    ctx.strokeStyle = hurt ? '#ffb0b0' : '#e9c8a6'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-5, -5 + bob); ctx.lineTo(-8, 3 + bob); ctx.stroke();
    // 머리
    ctx.fillStyle = hurt ? '#ffd0c0' : '#f1c9a5'; ctx.beginPath(); ctx.arc(0, -16 + bob, 6.5, 0, TAU); ctx.fill();
    ctx.fillStyle = '#2b1d14'; ctx.beginPath(); ctx.arc(0, -17.5 + bob, 6.8, Math.PI * 1.05, Math.PI * 1.95); ctx.lineTo(6.5, -15 + bob); ctx.lineTo(-6.8, -14 + bob); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#1e1a18'; ctx.beginPath(); ctx.arc(3, -15.5 + bob, 1.3, 0, TAU); ctx.fill();
    // 앞팔 + 검
    const sw = p.swingT, swinging = sw < 0.18, form = p.swingForm;
    const swordColor = b.weaponId === 'pierce' ? '#bfefff' : '#e8ecf2';
    let sa, reach = 7;
    if (swinging && form === 'spin') sa = la + (sw / 0.22) * TAU;
    else if (swinging && form === 'beam') { sa = la; reach = 7 + 9 * (1 - sw / 0.18); }
    else if (swinging) sa = la - 1.4 + 2.8 * Math.min(1, sw / 0.16);
    else sa = la + 0.95; // 대기: 앞쪽 아래로 든 자세
    const shx = 5, shy = -6 + bob, hx = shx + Math.cos(sa) * reach, hy = shy + Math.sin(sa) * reach;
    ctx.strokeStyle = hurt ? '#ffb0b0' : '#e9c8a6'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(shx, shy); ctx.lineTo(hx, hy); ctx.stroke();
    ctx.save(); ctx.translate(hx, hy); ctx.rotate(sa);
    const bl = b.weaponId === 'pierce' ? 30 : 26;
    ctx.fillStyle = '#5a4630'; ctx.fillRect(-6, -1.5, 6, 3); // 손잡이
    ctx.fillStyle = '#c9a44a'; ctx.fillRect(-1, -4.5, 3, 9); // 날밑
    ctx.fillStyle = swordColor; ctx.beginPath(); ctx.moveTo(2, -2.2); ctx.lineTo(bl - 5, -2.2); ctx.lineTo(bl, 0); ctx.lineTo(bl - 5, 2.2); ctx.lineTo(2, 2.2); ctx.closePath(); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.7)'; ctx.fillRect(3, -0.6, bl - 8, 1.2);
    if (swinging) { ctx.strokeStyle = `rgba(200,235,255,${0.9 * (1 - sw / 0.18)})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(4, 0); ctx.lineTo(bl + 6, 0); ctx.stroke(); }
    ctx.restore();
    ctx.restore();
    if (p.shield > 0) { ctx.strokeStyle = 'rgba(126,242,255,0.85)'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(p.x, p.y - 2, p.r + 10, 0, TAU); ctx.stroke(); ctx.fillStyle = 'rgba(126,242,255,0.08)'; ctx.fill(); }
  }
  function drawWeaponBodies(ctx, st) {
    const p = st.player;
    for (const w of st.weapons || []) {
      if (w.stats.kind === 'orbit' && w.bladePos) for (const bp of w.bladePos) { ctx.save(); ctx.translate(bp.x, bp.y); ctx.rotate(bp.a + st.t * 8); ctx.fillStyle = '#e6edf5'; ctx.strokeStyle = '#8fb6ee'; ctx.lineWidth = 1.5; for (let i = 0; i < 3; i++) { ctx.rotate(TAU / 3); ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(14, -4); ctx.lineTo(16, 0); ctx.lineTo(14, 4); ctx.closePath(); ctx.fill(); ctx.stroke(); } ctx.restore(); }
      if (w.stats.kind === 'chain') { const ox = p.x + Math.cos(st.t * 2) * 26, oy = p.y - 30 + Math.sin(st.t * 3) * 6; ctx.fillStyle = 'rgba(120,200,255,0.35)'; ctx.beginPath(); ctx.arc(ox, oy, 12, 0, TAU); ctx.fill(); ctx.fillStyle = '#dff4ff'; ctx.beginPath(); ctx.arc(ox, oy, 6, 0, TAU); ctx.fill(); }
      if (w.stats.kind === 'bolt') { const ox = p.x - 22, oy = p.y - 26 + Math.sin(st.t * 3 + 1) * 4; ctx.fillStyle = '#bfefff'; ctx.beginPath(); ctx.moveTo(ox, oy - 9); ctx.lineTo(ox + 6, oy); ctx.lineTo(ox, oy + 9); ctx.lineTo(ox - 6, oy); ctx.closePath(); ctx.fill(); }
      if (w.stats.kind === 'ember') { const ox = p.x + 24, oy = p.y - 28 + Math.sin(st.t * 4) * 4; ctx.fillStyle = 'rgba(255,150,60,0.5)'; ctx.beginPath(); ctx.arc(ox, oy, 9, 0, TAU); ctx.fill(); ctx.fillStyle = '#ffd27a'; ctx.beginPath(); ctx.arc(ox, oy, 4, 0, TAU); ctx.fill(); }
    }
    for (const mn of st.mines || []) { const armed = mn.arm <= 0; ctx.strokeStyle = armed ? 'rgba(200,140,255,0.9)' : 'rgba(200,140,255,0.4)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(mn.x, mn.y, 9, 0, TAU); ctx.stroke(); ctx.fillStyle = armed ? '#d9b3ff' : '#8a6bb0'; ctx.beginPath(); ctx.moveTo(mn.x, mn.y - 6); ctx.lineTo(mn.x + 5, mn.y + 3); ctx.lineTo(mn.x - 5, mn.y + 3); ctx.closePath(); ctx.fill(); if (armed) { ctx.strokeStyle = 'rgba(200,140,255,0.25)'; ctx.setLineDash([3, 5]); ctx.beginPath(); ctx.arc(mn.x, mn.y, mn.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]); } }
    // 기술 상태
    const S = st.skillState; if (S) {
      if (S.storm) { const s = S.storm; ctx.strokeStyle = 'rgba(230,240,255,0.8)'; ctx.lineWidth = 3; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.arc(s.x, s.y, s.r * (0.5 + 0.5 * ((st.t * 2 + i * 0.25) % 1)), st.t * 10 + i, st.t * 10 + i + 2.2); ctx.stroke(); } }
      if (S.gravity) { const g = S.gravity; ctx.fillStyle = 'rgba(150,100,255,0.18)'; ctx.beginPath(); ctx.arc(g.x, g.y, g.r, 0, TAU); ctx.fill(); ctx.strokeStyle = 'rgba(200,170,255,0.8)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(g.x, g.y, 14 + Math.sin(st.t * 12) * 3, 0, TAU); ctx.stroke(); for (let i = 0; i < 8; i++) { const a = i * TAU / 8 - st.t * 4, rr = g.r * (0.3 + 0.6 * ((st.t * 0.8 + i * 0.13) % 1)); ctx.fillStyle = 'rgba(210,190,255,0.7)'; ctx.beginPath(); ctx.arc(g.x + Math.cos(a) * rr, g.y + Math.sin(a) * rr, 2.5, 0, TAU); ctx.fill(); } }
      if (S.ward) { ctx.strokeStyle = 'rgba(126,242,255,0.9)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(p.x, p.y - 2, p.r + 14, 0, TAU); ctx.stroke(); }
      if (S.target) { ctx.strokeStyle = 'rgba(255,240,150,0.85)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(S.target.x, S.target.y, 12, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.moveTo(S.target.x - 16, S.target.y); ctx.lineTo(S.target.x - 8, S.target.y); ctx.moveTo(S.target.x + 8, S.target.y); ctx.lineTo(S.target.x + 16, S.target.y); ctx.stroke(); ctx.fillStyle = 'rgba(255,240,150,0.9)'; ctx.font = `10px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('E', S.target.x, S.target.y - 16); }
    }
  }
  function drawRange(ctx, st) {
    const p = st.player, b = st.build;
    ctx.strokeStyle = 'rgba(150,210,255,0.16)'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]);
    if (b.weapon.form === 'beam') { ctx.beginPath(); ctx.arc(p.x, p.y, b.range, 0, TAU); ctx.stroke(); }
    else { ctx.beginPath(); ctx.arc(p.x, p.y, b.range, 0, TAU); ctx.stroke(); }
    ctx.setLineDash([]);
  }

  function drawTelegraphs(ctx, st) {
    const a = st.arena;
    for (const e of st.enemies) {
      if (e.dead) continue;
      const d = e.def;
      if ((e.type === 'wolf' || e.type === 'wolf_alpha') && (e.state === 'crouch' || e.state === 'lock')) {
        const ang = e.state === 'crouch' ? e.aimAngle : e.dir, L = d.dashSpeed * d.dashTime, locked = e.state === 'lock';
        const alpha = locked ? (0.75 + 0.25 * Math.sin(st.t * 60)) : 0.4 + 0.35 * (e.stateT / d.crouch);
        ctx.save(); ctx.translate(e.x, e.y); ctx.rotate(ang);
        ctx.fillStyle = `rgba(255,60,60,${alpha * 0.3})`; ctx.fillRect(0, -(e.r + st.player.r), L, (e.r + st.player.r) * 2);
        ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.beginPath(); ctx.moveTo(e.r, 0); ctx.lineTo(L - 12, 0); ctx.stroke();
        ctx.fillStyle = `rgba(255,80,80,${alpha})`; ctx.beginPath(); ctx.moveTo(L, 0); ctx.lineTo(L - 16, -9); ctx.lineTo(L - 16, 9); ctx.closePath(); ctx.fill();
        ctx.restore();
        if (locked) { ctx.fillStyle = '#ff7070'; ctx.font = `bold 16px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', e.x, e.y - e.r - 34); }
      }
      if (e.type === 'archer' && (e.state === 'aim' || e.state === 'lock')) {
        const ang = e.state === 'aim' ? e.aimAngle : e.dir, locked = e.state === 'lock', L = Math.hypot(a.w, a.h);
        ctx.strokeStyle = locked ? `rgba(255,80,80,${0.8 + 0.2 * Math.sin(st.t * 60)})` : `rgba(255,120,120,${0.35 + 0.35 * (e.stateT / d.aim)})`;
        ctx.lineWidth = locked ? 3 : 1.5; if (!locked) ctx.setLineDash([8, 6]);
        ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.lineTo(e.x + Math.cos(ang) * L, e.y + Math.sin(ang) * L); ctx.stroke(); ctx.setLineDash([]);
        if (locked) { ctx.fillStyle = '#ff7070'; ctx.font = `bold 16px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', e.x, e.y - e.r - 24); }
      }
      if (e.type === 'spore' && e.state === 'swell') {
        const k = e.stateT / d.swell, r = d.cloudR * (0.3 + 0.7 * k);
        ctx.fillStyle = `rgba(200,100,255,${0.15 + 0.2 * k})`; ctx.beginPath(); ctx.arc(e.x, e.y, r, 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(255,120,255,${0.5 + 0.5 * k})`; ctx.lineWidth = 2 + 2 * k; ctx.beginPath(); ctx.arc(e.x, e.y, d.cloudR, 0, TAU); ctx.stroke();
      }
    }
    const flashT = 0.75 + 0.25 * Math.sin(st.t * 60);
    for (const e of st.enemies) {
      if (e.dead) continue; const d = e.def;
      if (e.type === 'boar' && (e.state === 'charge_aim' || e.state === 'charge_lock')) { // 붉은 통로: 실제 종료점까지(예고 = 실제 계산)
        const locked = e.state === 'charge_lock', ang = locked ? e.dir : e.aimAngle, path = locked ? { len: e.chargeLen, end: e.chargeEnd } : (e.preview || { len: d.chargeDist, end: { x: e.x + Math.cos(ang) * d.chargeDist, y: e.y + Math.sin(ang) * d.chargeDist } });
        const alpha = locked ? flashT : 0.35 + 0.35 * (e.stateT / d.aim), W = (e.r + st.player.r) * 2;
        ctx.save(); ctx.translate(e.x, e.y); ctx.rotate(ang); ctx.fillStyle = `rgba(255,60,60,${alpha * 0.3})`; ctx.fillRect(0, -W / 2, path.len, W); ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.strokeRect(0, -W / 2, path.len, W); ctx.fillStyle = `rgba(255,80,80,${alpha})`; ctx.beginPath(); ctx.moveTo(path.len, 0); ctx.lineTo(path.len - 16, -9); ctx.lineTo(path.len - 16, 9); ctx.closePath(); ctx.fill(); ctx.restore();
        ctx.strokeStyle = `rgba(255,120,120,${alpha})`; ctx.lineWidth = 2; ctx.setLineDash([5, 5]); ctx.beginPath(); ctx.arc(path.end.x, path.end.y, e.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
        ctx.fillStyle = '#ff9a6a'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(locked ? '돌파!' : '돌파 준비', e.x, e.y - e.r - 30);
      }
      if (e.type === 'shieldbearer' && e.state === 'bash_aim') { const k = e.stateT / d.aim, half = d.bashDeg * Math.PI / 360, R = d.bashRange + d.lunge; ctx.fillStyle = `rgba(255,60,60,${0.12 + 0.25 * k})`; ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.arc(e.x, e.y, R, e.face - half, e.face + half); ctx.closePath(); ctx.fill(); ctx.strokeStyle = k > 0.6 ? `rgba(255,80,80,${flashT})` : 'rgba(255,120,120,0.6)'; ctx.lineWidth = k > 0.6 ? 4 : 2; ctx.stroke(); ctx.fillStyle = '#ffd9b0'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('방패 열림 · 방패치기', e.x, e.y - e.r - 30); }
      if (e.type === 'shaman' && e.state === 'cast' && e.castTarget && !e.castTarget.dead) { const t = e.castTarget, k = e.stateT / d.healCast; ctx.strokeStyle = 'rgba(233,182,255,0.85)'; ctx.lineWidth = 2.5; ctx.setLineDash([6, 4]); ctx.beginPath(); ctx.moveTo(e.x, e.y - 10); ctx.lineTo(t.x, t.y); ctx.stroke(); ctx.setLineDash([]); ctx.strokeStyle = '#e9b6ff'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(e.x, e.y - 30, 12, -Math.PI / 2, -Math.PI / 2 + TAU * k); ctx.stroke(); ctx.strokeStyle = 'rgba(233,182,255,0.7)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(t.x, t.y, t.r + 8, 0, TAU); ctx.stroke(); ctx.fillStyle = '#e9b6ff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('치료 시전 중 — 끊어라', e.x, e.y - e.r - 34); }
      if (e.type === 'shaman' && e.state === 'hex_aim') { const k = e.stateT / d.hexAim, L = 600; ctx.strokeStyle = k > 0.7 ? `rgba(233,182,255,${flashT})` : 'rgba(233,182,255,0.45)'; ctx.lineWidth = k > 0.7 ? 3 : 1.5; ctx.setLineDash([8, 6]); ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.lineTo(e.x + Math.cos(e.aimAngle) * L, e.y + Math.sin(e.aimAngle) * L); ctx.stroke(); ctx.setLineDash([]); }
      if (e.type === 'bomber' && e.state === 'fuse') { const k = e.stateT / d.fuse; ctx.fillStyle = `rgba(255,120,40,${0.15 + 0.3 * k})`; ctx.beginPath(); ctx.arc(e.x, e.y, d.blastR, 0, TAU); ctx.fill(); ctx.fillStyle = `rgba(255,200,80,${0.25 * k})`; ctx.beginPath(); ctx.arc(e.x, e.y, d.blastR * k, 0, TAU); ctx.fill(); ctx.strokeStyle = `rgba(255,90,60,${flashT})`; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(e.x, e.y, d.blastR, 0, TAU); ctx.stroke(); ctx.fillStyle = '#ff9a6a'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(`폭발 ${Math.max(0, d.fuse - e.stateT).toFixed(1)}s`, e.x, e.y - e.r - 30); }
      if (e.type === 'burrower' && e.state === 'warn' && e.emergeAt) { const k = e.stateT / d.warn, a = e.emergeAt; ctx.fillStyle = `rgba(255,60,60,${0.15 + 0.25 * k})`; ctx.beginPath(); ctx.arc(a.x, a.y, d.emergeR, 0, TAU); ctx.fill(); ctx.strokeStyle = `rgba(255,80,80,${flashT})`; ctx.lineWidth = 3; ctx.stroke(); ctx.strokeStyle = '#7a6040'; ctx.lineWidth = 2; for (let i = 0; i < 5; i++) { const ang = i * 1.26 + 0.3; ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(a.x + Math.cos(ang) * d.emergeR * k, a.y + Math.sin(ang) * d.emergeR * k); ctx.stroke(); } ctx.fillStyle = '#ffd9b0'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('출현!', a.x, a.y - d.emergeR - 8); }
      if ((e.type === 'burrower' || e.type === 'spider') && e.state === 'bite_aim') { const k = e.stateT / d.biteAim, half = d.biteDeg * Math.PI / 360, R = d.biteRange + e.r; ctx.fillStyle = `rgba(255,60,60,${0.12 + 0.25 * k})`; ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.arc(e.x, e.y, R, e.aimAngle - half, e.aimAngle + half); ctx.closePath(); ctx.fill(); ctx.strokeStyle = k > 0.6 ? `rgba(255,80,80,${flashT})` : 'rgba(255,120,120,0.6)'; ctx.lineWidth = k > 0.6 ? 3 : 1.5; ctx.stroke(); }
      if (e.type === 'spider' && e.state === 'web_aim' && e.webAt) { const k = e.stateT / d.webAim; ctx.strokeStyle = `rgba(235,235,245,${0.4 + 0.5 * k})`; ctx.lineWidth = 2; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.arc(e.webAt.x, e.webAt.y, d.webR, 0, TAU); ctx.stroke(); ctx.setLineDash([]); ctx.strokeStyle = 'rgba(235,235,245,0.5)'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.lineTo(e.webAt.x, e.webAt.y); ctx.stroke(); ctx.fillStyle = '#eef'; ctx.font = `11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('거미줄 예고', e.webAt.x, e.webAt.y - d.webR - 6); }
      if (e.type === 'frostcaller' && e.state === 'cast' && e.castPts) { const k = e.stateT / d.castAim; e.castPts.forEach((pt, i) => { ctx.strokeStyle = `rgba(200,240,255,${0.4 + 0.5 * k})`; ctx.lineWidth = 2; ctx.setLineDash([5, 5]); ctx.beginPath(); ctx.arc(pt.x, pt.y, d.zoneR, 0, TAU); ctx.stroke(); ctx.setLineDash([]); ctx.fillStyle = '#e8f4ff'; ctx.font = `bold 16px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(String(i + 1), pt.x, pt.y + 6); }); ctx.fillStyle = '#bfefff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('서리 1→2→3', e.x, e.y - e.r - 34); }
      if (e.type === 'rogue' && (e.state === 'slash1_aim' || e.state === 'slash2_aim')) { const first = e.state === 'slash1_aim', k = e.stateT / (first ? d.aim1 : d.aim2), half = d.slashDeg * Math.PI / 360, R = d.slashRange + e.r; ctx.fillStyle = `rgba(255,60,60,${0.12 + 0.28 * k})`; ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.arc(e.x, e.y, R, e.aimAngle - half, e.aimAngle + half); ctx.closePath(); ctx.fill(); ctx.strokeStyle = k > 0.5 ? `rgba(255,80,80,${flashT})` : 'rgba(255,120,120,0.6)'; ctx.lineWidth = k > 0.5 ? 3 : 1.5; ctx.stroke(); ctx.fillStyle = '#ffd9b0'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(first ? '베기 1/2' : '베기 2/2', e.x, e.y - e.r - 30); }
    }
    const bz = st.boss;
    if (bz && !bz.dead) {
      const cfg = PA.Boss.cfgOf(bz), flash = 0.75 + 0.25 * Math.sin(st.t * 60);
      if (bz.bossId === 'guardian' || bz.bossId === 'eater') { // 신규 보스 예고: 직선 충격파·두 줄·표식·광역
        const beam = (ang, len, w, locked, k) => { const alpha = locked ? flash : 0.35 + 0.35 * k; ctx.save(); ctx.translate(bz.x, bz.y); ctx.rotate(ang); ctx.fillStyle = `rgba(255,60,60,${alpha * 0.3})`; ctx.fillRect(0, -w / 2, len, w); ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.strokeRect(0, -w / 2, len, w); ctx.restore(); };
        if (bz.state === 'shock_aim' || bz.state === 'shock_lock') { const S = cfg.shock, locked = bz.state === 'shock_lock', ang = locked ? bz.dir : bz.aimAngle, k = bz.stateT / S.aim; if (bz.shockLeft >= 2) { beam(ang - S.spread, S.len, S.width, locked, k); beam(ang + S.spread, S.len, S.width, locked, k); } else beam(ang, S.len, S.width, locked, k); ctx.fillStyle = '#ffd9b0'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(locked ? '충격파!' : '충격파 준비 — 옆으로', bz.x, bz.y - bz.r - 44); }
        if (bz.state === 'lanes_warn' || bz.state === 'lanes_lock' || bz.state === 'lanes_fire') { const L = cfg.lanes; bz.lanes.forEach((ln, i) => { if (ln.fired) return; const locked = bz.state !== 'lanes_warn' && i === bz.laneIdx; beam(ln.ang, L.len, L.width, locked, Math.min(1, bz.stateT / L.warn)); ctx.fillStyle = '#ffd9b0'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(`직선 ${i + 1}/2`, bz.x + Math.cos(ln.ang) * 140, bz.y + Math.sin(ln.ang) * 140); }); }
        if (bz.marks) for (const mk of bz.marks) { const left = Math.max(0, mk.explodeAt - st.t), k = 1 - Math.min(1, left / cfg.mark.delay); ctx.strokeStyle = left < 0.4 ? `rgba(230,120,255,${flash})` : 'rgba(200,120,255,0.8)'; ctx.lineWidth = left < 0.4 ? 4 : 2; ctx.setLineDash([6, 5]); ctx.beginPath(); ctx.arc(mk.x, mk.y, mk.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]); ctx.fillStyle = `rgba(200,120,255,${0.12 + 0.25 * k})`; ctx.beginPath(); ctx.arc(mk.x, mk.y, mk.r * k, 0, TAU); ctx.fill(); ctx.fillStyle = '#e0c0ff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(left.toFixed(1), mk.x, mk.y + 4); }
        if (bz.state === 'wide_aim' || bz.state === 'wide_lock') { const R = cfg.wide.radius[Math.min(2, bz.phase - 1)], locked = bz.state === 'wide_lock', k = bz.stateT / cfg.wide.aim, alpha = locked ? flash : 0.3 + 0.4 * k; ctx.fillStyle = `rgba(200,80,255,${alpha * 0.25})`; ctx.beginPath(); ctx.arc(bz.x, bz.y, R, 0, TAU); ctx.fill(); ctx.strokeStyle = `rgba(230,120,255,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.stroke(); ctx.fillStyle = '#e0c0ff'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(locked ? '광역!' : '광역 준비 — 원 밖으로 (뒤에 긴 빈틈)', bz.x, bz.y - R - 8); }
      }
      if (bz.state === 'sweep_aim' || bz.state === 'sweep_lock') {
        const locked = bz.state === 'sweep_lock', ang = locked ? bz.dir : bz.aimAngle, half = cfg.sweep.arcDeg * Math.PI / 360;
        const alpha = locked ? flash : 0.35 + 0.35 * (bz.stateT / cfg.sweep.aim);
        ctx.fillStyle = `rgba(255,60,60,${alpha * 0.32})`; ctx.beginPath(); ctx.moveTo(bz.x, bz.y); ctx.arc(bz.x, bz.y, cfg.sweep.radius, ang - half, ang + half); ctx.closePath(); ctx.fill();
        ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.stroke();
        if (locked) { ctx.fillStyle = '#ff7070'; ctx.font = `bold 18px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', bz.x, bz.y - bz.r - 44); }
      }
      if (bz.state === 'dash_aim' || bz.state === 'dash_lock') {
        const locked = bz.state === 'dash_lock', ang = locked ? bz.dir : bz.aimAngle;
        const path = locked ? { len: bz.dashLen, end: bz.dashEnd } : PA.Boss.dashPath(st, bz, ang, cfg.dash.dist);
        const alpha = locked ? flash : 0.35 + 0.35 * (bz.stateT / cfg.dash.aim), W = (bz.r + st.player.r) * 2;
        ctx.save(); ctx.translate(bz.x, bz.y); ctx.rotate(ang);
        ctx.fillStyle = `rgba(255,60,60,${alpha * 0.3})`; ctx.fillRect(0, -W / 2, path.len, W);
        ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.strokeRect(0, -W / 2, path.len, W);
        ctx.beginPath(); ctx.moveTo(bz.r, 0); ctx.lineTo(path.len - 14, 0); ctx.stroke();
        ctx.fillStyle = `rgba(255,80,80,${alpha})`; ctx.beginPath(); ctx.moveTo(path.len, 0); ctx.lineTo(path.len - 18, -10); ctx.lineTo(path.len - 18, 10); ctx.closePath(); ctx.fill();
        ctx.restore();
        // 도착 지점
        ctx.strokeStyle = `rgba(255,120,120,${alpha})`; ctx.lineWidth = 2; ctx.setLineDash([5, 5]); ctx.beginPath(); ctx.arc(path.end.x, path.end.y, bz.r, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
        if (locked) { ctx.fillStyle = '#ff7070'; ctx.font = `bold 18px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', bz.x, bz.y - bz.r - 44); }
        if (bz.dashTotal > 1) { ctx.fillStyle = '#ffd166'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(`연속 돌진 ${bz.dashSeq}/${bz.dashTotal}`, bz.x, bz.y - bz.r - 60); }
      }
      if ((bz.state === 'pounce_aim' || bz.state === 'pounce_lock' || bz.state === 'leap') && bz.land) {
        const locked = bz.state !== 'pounce_aim', alpha = locked ? flash : 0.35 + 0.35 * (bz.stateT / cfg.pounce.aim);
        ctx.fillStyle = `rgba(255,60,60,${alpha * 0.3})`; ctx.beginPath(); ctx.arc(bz.land.x, bz.land.y, cfg.pounce.radius, 0, TAU); ctx.fill();
        ctx.strokeStyle = `rgba(255,80,80,${alpha})`; ctx.lineWidth = locked ? 4 : 2; ctx.stroke();
        if (bz.state === 'leap') { const k = bz.leapK; ctx.strokeStyle = 'rgba(255,200,120,0.8)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(bz.land.x, bz.land.y, cfg.pounce.radius * (1 - k) + 6, 0, TAU); ctx.stroke(); }
        if (locked && bz.state !== 'leap') { ctx.fillStyle = '#ff7070'; ctx.font = `bold 18px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('!', bz.land.x, bz.land.y - cfg.pounce.radius - 10); }
      }
      if (bz.state === 'howl') { const k = bz.stateT / cfg.howl.duration; ctx.strokeStyle = `rgba(255,200,120,${0.6 * (1 - k)})`; ctx.lineWidth = 3; for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(bz.x, bz.y - 20, 40 + ((k * 3 + i) % 3) * 40, 0, TAU); ctx.stroke(); } }
    }
    for (const f of st.effects) if (f.kind === 'pawwarn') {
      const k = f.t / f.ttl; ctx.fillStyle = `rgba(255,200,80,${0.4 + 0.6 * k})`;
      ctx.beginPath(); ctx.ellipse(f.x, f.y + 3, 6, 8, 0, 0, TAU); ctx.fill(); for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.arc(f.x - 7 + i * 4.7, f.y - 8 + (i === 0 || i === 3 ? 3 : 0), 2.6, 0, TAU); ctx.fill(); }
      ctx.font = `12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('늑대 등장', f.x, f.y - 18);
    }
    for (const f of st.effects) if (f.kind === 'spawnwarn') {
      const k = f.t / f.ttl; ctx.strokeStyle = `rgba(255,200,80,${0.4 + 0.6 * k})`; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(f.x, f.y, 18 * (1 - k) + 6, 0, TAU); ctx.stroke();
      ctx.fillStyle = 'rgba(255,200,80,0.9)'; ctx.font = `12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(PA.ENEMIES[f.type].name, f.x, f.y - 24);
    }
  }

  function drawProjectiles(ctx, st) {
    for (const p of st.projectiles) {
      if (p.owner === 'player' && p.kind !== 'shard' && p.kind !== 'shard_common') {
        const ang = Math.atan2(p.vy, p.vx);
        if (p.kind === 'crescent') { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(ang); ctx.strokeStyle = 'rgba(220,245,255,0.95)'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(-8, 0, 18, -1.1, 1.1); ctx.stroke(); ctx.restore(); continue; }
        if (p.kind === 'arrow_h') { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(ang); ctx.strokeStyle = '#e8f7ff'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(-12, 0); ctx.lineTo(8, 0); ctx.stroke(); ctx.fillStyle = '#9fd8ff'; ctx.beginPath(); ctx.moveTo(12, 0); ctx.lineTo(4, -4); ctx.lineTo(4, 4); ctx.fill(); ctx.restore(); continue; }
        if (p.kind === 'bolt') { ctx.fillStyle = '#bfefff'; ctx.beginPath(); ctx.arc(p.x, p.y, 6, 0, TAU); ctx.fill(); ctx.strokeStyle = 'rgba(160,230,255,0.7)'; ctx.lineWidth = 2; for (let i = 0; i < 3; i++) { const a = i * Math.PI / 3 + st.t * 6; ctx.beginPath(); ctx.moveTo(p.x - Math.cos(a) * 7, p.y - Math.sin(a) * 7); ctx.lineTo(p.x + Math.cos(a) * 7, p.y + Math.sin(a) * 7); ctx.stroke(); } continue; }
        if (p.kind === 'blade') { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(st.t * 20); ctx.fillStyle = '#e6edf5'; for (let i = 0; i < 3; i++) { ctx.rotate(TAU / 3); ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(12, -3); ctx.lineTo(12, 3); ctx.fill(); } ctx.restore(); continue; }
      }
      if (p.kind === 'shock') { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.angle); ctx.strokeStyle = 'rgba(255,200,120,0.95)'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(-10, 0, p.r, -1.2, 1.2); ctx.stroke(); ctx.strokeStyle = 'rgba(255,120,60,0.6)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(-22, 0, p.r * 0.8, -1.0, 1.0); ctx.stroke(); ctx.restore(); }
      if (p.kind === 'hex') { ctx.fillStyle = 'rgba(200,120,255,0.45)'; ctx.beginPath(); ctx.arc(p.x, p.y, 10, 0, TAU); ctx.fill(); ctx.fillStyle = '#e9b6ff'; ctx.beginPath(); ctx.arc(p.x, p.y, 5, 0, TAU); ctx.fill(); continue; }
      if (p.kind === 'arrow') { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.angle); ctx.strokeStyle = '#ffd9a0'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-14, 0); ctx.lineTo(8, 0); ctx.stroke(); ctx.fillStyle = '#ff6b6b'; ctx.beginPath(); ctx.moveTo(12, 0); ctx.lineTo(4, -4); ctx.lineTo(4, 4); ctx.fill(); ctx.restore(); }
      else { ctx.fillStyle = '#bfefff'; ctx.beginPath(); ctx.arc(p.x, p.y, 4, 0, TAU); ctx.fill(); ctx.fillStyle = 'rgba(191,239,255,0.4)'; ctx.beginPath(); ctx.arc(p.x - p.vx * 0.02, p.y - p.vy * 0.02, 3, 0, TAU); ctx.fill(); }
    }
  }

  function drawPickups(ctx, st) {
    for (const k of st.pickups) {
      const bob = Math.sin(k.t * 4) * 3;
      ctx.fillStyle = 'rgba(120,255,160,0.25)'; ctx.beginPath(); ctx.arc(k.x, k.y + bob, k.r + 6 + Math.sin(k.t * 6) * 2, 0, TAU); ctx.fill();
      ctx.fillStyle = '#7fe8a0'; ctx.beginPath(); ctx.arc(k.x, k.y + bob, k.r, 0, TAU); ctx.fill();
      ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(k.x - 4, k.y + bob - 4, 4, 0, TAU); ctx.fill();
      ctx.strokeStyle = '#1e4a2a'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(k.x - 6, k.y + bob); ctx.lineTo(k.x + 6, k.y + bob); ctx.moveTo(k.x, k.y + bob - 6); ctx.lineTo(k.x, k.y + bob + 6); ctx.stroke();
      ctx.fillStyle = '#bfffd0'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText('+' + k.amount, k.x, k.y + bob - k.r - 6);
    }
  }
  function drawMisc(ctx, st) {
    for (const f of st.effects) {
      const k = 1 - f.t / f.ttl;
      if (f.kind === 'bosssweep') { ctx.globalAlpha = k; ctx.fillStyle = 'rgba(255,120,80,0.35)'; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.arc(f.x, f.y, f.r, f.angle - f.half, f.angle + f.half); ctx.closePath(); ctx.fill(); ctx.strokeStyle = '#ffd9b0'; ctx.lineWidth = 6 * k; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.6 + 0.4 * (1 - k)), f.angle - f.half, f.angle + f.half); ctx.stroke(); ctx.globalAlpha = 1; }
      if (f.kind === 'bossland') { ctx.globalAlpha = k; ctx.fillStyle = 'rgba(200,150,90,0.35)'; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.6 + 0.4 * (1 - k)), 0, TAU); ctx.fill(); ctx.strokeStyle = '#e8c9a0'; ctx.lineWidth = 5; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 - k * 0.2), 0, TAU); ctx.stroke(); for (let i = 0; i < 10; i++) { const a = i * TAU / 10; ctx.fillStyle = '#8a6b45'; ctx.beginPath(); ctx.arc(f.x + Math.cos(a) * f.r * (1 - k) * 0.9, f.y + Math.sin(a) * f.r * (1 - k) * 0.9 - 14 * k, 3, 0, TAU); ctx.fill(); } ctx.globalAlpha = 1; }
      if (f.kind === 'burst') { ctx.strokeStyle = f.color; ctx.globalAlpha = k; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 - k * 0.6), 0, TAU); ctx.stroke(); ctx.globalAlpha = 1; }
      if (f.kind === 'death') { ctx.globalAlpha = k * 0.8; ctx.fillStyle = '#6b6f78'; for (let i = 0; i < 7; i++) { const a = i * TAU / 7 + 0.3; const dd = f.r * (0.6 + 1.8 * (1 - k)); ctx.beginPath(); ctx.arc(f.x + Math.cos(a) * dd, f.y + Math.sin(a) * dd - 10 * (1 - k), 3 * k + 1, 0, TAU); ctx.fill(); } ctx.globalAlpha = 1; }
      if (f.kind === 'spark') { ctx.globalAlpha = k; ctx.strokeStyle = f.crit ? '#ffd166' : '#ffffff'; ctx.lineWidth = 2; for (let i = 0; i < 5; i++) { const a = f.angle + (i - 2) * 0.5; const r0 = 6 + 14 * (1 - k), r1 = r0 + 6; ctx.beginPath(); ctx.moveTo(f.x + Math.cos(a) * r0, f.y + Math.sin(a) * r0); ctx.lineTo(f.x + Math.cos(a) * r1, f.y + Math.sin(a) * r1); ctx.stroke(); } ctx.globalAlpha = 1; }
      if (f.kind === 'flare') { ctx.globalAlpha = k * 0.6; ctx.fillStyle = '#ff9f43'; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.5 + 0.5 * (1 - k)), 0, TAU); ctx.fill(); ctx.globalAlpha = k; ctx.strokeStyle = '#ffe08a'; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 - k * 0.3), 0, TAU); ctx.stroke(); for (let i = 0; i < 8; i++) { const a = i * TAU / 8; ctx.fillStyle = '#ffcc55'; ctx.beginPath(); ctx.arc(f.x + Math.cos(a) * f.r * (1 - k) * 1.1, f.y + Math.sin(a) * f.r * (1 - k) * 1.1, 3, 0, TAU); ctx.fill(); } ctx.globalAlpha = 1; }
      if (f.kind === 'stasisburst') { ctx.globalAlpha = k; ctx.fillStyle = 'rgba(160,210,255,0.35)'; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 - k * 0.4), 0, TAU); ctx.fill(); ctx.strokeStyle = '#e0f4ff'; ctx.lineWidth = 3; for (let i = 0; i < 6; i++) { const a = i * TAU / 6 + 0.4; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.lineTo(f.x + Math.cos(a) * f.r * (1.2 - k * 0.5), f.y + Math.sin(a) * f.r * (1.2 - k * 0.5)); ctx.stroke(); } ctx.globalAlpha = 1; }
      if (f.kind === 'healbeam') { ctx.globalAlpha = k; ctx.strokeStyle = '#8ee6a0'; ctx.lineWidth = 3; ctx.setLineDash([6, 4]); ctx.beginPath(); ctx.moveTo(f.x, f.y - 30); ctx.lineTo(f.tx, f.ty); ctx.stroke(); ctx.setLineDash([]); ctx.globalAlpha = 1; }
      if (f.kind === 'frostburst') { ctx.globalAlpha = k; ctx.fillStyle = 'rgba(200,240,255,0.5)'; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (0.7 + 0.3 * (1 - k)), 0, TAU); ctx.fill(); ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 3; for (let i = 0; i < 6; i++) { const a = i * TAU / 6; ctx.beginPath(); ctx.moveTo(f.x, f.y); ctx.lineTo(f.x + Math.cos(a) * f.r * (1.1 - k * 0.4), f.y + Math.sin(a) * f.r * (1.1 - k * 0.4)); ctx.stroke(); } ctx.globalAlpha = 1; }
      if (f.kind === 'fieldend') { ctx.globalAlpha = k * 0.7; ctx.strokeStyle = '#bfe6ff'; ctx.lineWidth = 6 * k; ctx.beginPath(); ctx.arc(f.x, f.y, f.r * (1 + 0.15 * (1 - k)), 0, TAU); ctx.stroke(); ctx.globalAlpha = 1; }
      if (f.kind === 'hitflash') { ctx.globalAlpha = k * 0.5; ctx.strokeStyle = '#ff5050'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(f.x, f.y, 18 + 16 * (1 - k), 0, TAU); ctx.stroke(); ctx.globalAlpha = 1; }
    }
    for (const f of st.effects) if (f.kind === 'text') { ctx.globalAlpha = Math.min(1, (1 - f.t / f.ttl) * 2); ctx.font = `bold 15px ${FONT}`; ctx.textAlign = 'center'; ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(0,0,0,0.8)'; ctx.strokeText(f.text, f.x, f.y); ctx.fillStyle = f.color; ctx.fillText(f.text, f.x, f.y); ctx.globalAlpha = 1; }
  }

  function bar(ctx, x, y, w, h, ratio, color, label, text) {
    ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = color; ctx.fillRect(x, y, w * Math.max(0, Math.min(1, ratio)), h);
    ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 1; ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
    ctx.fillStyle = '#fff'; ctx.font = `bold 13px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText(label, x + 6, y + h - 5);
    ctx.textAlign = 'right'; ctx.fillText(text, x + w - 6, y + h - 5);
  }
  function slot(ctx, x, y, key, label, ready, ratio, color) {
    ctx.fillStyle = 'rgba(0,0,0,0.65)'; ctx.fillRect(x, y, 64, 64);
    ctx.strokeStyle = ready ? color : 'rgba(255,255,255,0.35)'; ctx.lineWidth = ready ? 3 : 1.5; ctx.strokeRect(x + 1.5, y + 1.5, 61, 61);
    if (!ready) { ctx.save(); ctx.beginPath(); ctx.rect(x, y, 64, 64); ctx.clip(); ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.beginPath(); ctx.moveTo(x + 32, y + 32); ctx.arc(x + 32, y + 32, 48, -Math.PI / 2, -Math.PI / 2 + TAU * ratio); ctx.closePath(); ctx.fill(); ctx.restore(); }
    ctx.fillStyle = ready ? '#fff' : 'rgba(255,255,255,0.6)'; ctx.font = `bold 18px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(key, x + 32, y + 30);
    ctx.font = `12px ${FONT}`; ctx.fillText(label, x + 32, y + 52);
  }
  function drawHUD(ctx, st, W, H) {
    const p = st.player, b = st.build;
    bar(ctx, 14, 12, 240, 22, p.hp / p.hpMax, '#d9453d', '체력', `${Math.ceil(p.hp)} / ${p.hpMax}`);
    if (p.shieldMax > 0) bar(ctx, 14, 38, 240, 16, p.shield / p.shieldMax, '#38c6d8', '보호막', `${Math.ceil(p.shield)} / ${p.shieldMax}`);
    const alive = st.enemies.filter(e => !e.dead).length + st.pending.length;
    if (st.mode === 'boss' && st.boss) {
      const bz = st.boss, cfg = PA.Boss.cfgOf(bz), bw = 520, bx = W / 2 - bw / 2, by = 14;
      ctx.fillStyle = 'rgba(0,0,0,0.65)'; ctx.fillRect(bx - 10, by - 4, bw + 20, 58);
      ctx.fillStyle = '#ffe066'; ctx.font = `bold 15px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText(`${cfg.name} — ${cfg.title}`, bx, by + 12);
      const act = PA.BOSS_ACTION_TEXT[bz.state] || ''; const slow = PA.Combat.inField(st, bz) && !bz.dead;
      let actText = act; if (bz.state === 'dash_aim' || bz.state === 'dash_lock' || bz.state === 'dash') { if (bz.dashTotal > 1) actText = `연속 돌진 ${bz.dashSeq}/${bz.dashTotal}` + (bz.state === 'dash_aim' ? ' 준비' : ''); }
      ctx.fillStyle = (bz.state === 'recover' || bz.state === 'stagger') ? '#ffd166' : '#fff'; ctx.font = `bold 14px ${FONT}`; ctx.textAlign = 'right'; ctx.fillText(actText + (slow ? ' · 감속 중' : ''), bx + bw, by + 12);
      ctx.fillStyle = '#2a0f0f'; ctx.fillRect(bx, by + 20, bw, 18);
      const ratio = Math.max(0, bz.hp / bz.hpMax);
      ctx.fillStyle = bz.phase >= 3 ? '#ff5a3c' : bz.phase === 2 ? '#e0563a' : '#c0392b'; ctx.fillRect(bx, by + 20, bw * ratio, 18);
      for (const ph of cfg.phases) { const px = bx + bw * ph; ctx.fillStyle = '#fff'; ctx.fillRect(px - 1, by + 18, 2, 22); ctx.font = `11px ${FONT}`; ctx.textAlign = 'center'; ctx.fillStyle = '#ffd9b0'; ctx.fillText(Math.round(ph * 100) + '%', px, by + 50); }
      ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.lineWidth = 1; ctx.strokeRect(bx + 0.5, by + 20.5, bw - 1, 17);
      ctx.fillStyle = '#fff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(`${Math.ceil(Math.max(0, bz.hp))} / ${bz.hpMax} · ${bz.phase}단계`, bx + bw / 2, by + 34);
      { const summ = st.enemies.filter(x => !x.dead && !x.boss && !x.structure).length + st.pending.length, dev = st.enemies.filter(x => !x.dead && x.structure).length; if (summ > 0 || dev > 0) { ctx.font = `12px ${FONT}`; ctx.fillStyle = '#ddd'; ctx.textAlign = 'left'; ctx.fillText(`${summ > 0 ? '소환 ' + summ : ''}${summ > 0 && dev > 0 ? ' · ' : ''}${dev > 0 ? '봉인 장치 ' + dev : ''}`, bx, by + 50); } }
      if (st.intro > 0) { ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.fillRect(0, H / 2 - 50, W, 100); ctx.fillStyle = '#ffe066'; ctx.font = `bold 36px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(`${cfg.name} — ${cfg.title}`, W / 2, H / 2 + 2); ctx.fillStyle = '#fff'; ctx.font = `14px ${FONT}`; ctx.fillText(cfg.id === 'boss' ? '예언의 날. 숲의 왕이 나타났다.' : `${cfg.title}이 길을 막는다.`, W / 2, H / 2 + 30); }
    } else {
      const oh = st.obj && PA.Objectives ? PA.Objectives.hud(st) : null; const alive2 = st.enemies.filter(e => !e.dead && !e.structure).length, rm = PA.Combat.remaining(st);
      ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(W - 244, 12, 230, 64);
      ctx.fillStyle = '#fff'; ctx.font = `bold 14px ${FONT}`; ctx.textAlign = 'left'; const ec = st.objective === 'elite' ? PA.Combat.eliteCount(st) : null;
      ctx.fillText(oh ? oh.title + (oh.risk ? ' · ' + oh.risk : '') : (ec ? `목적: 전멸 (정예 ${ec.killed} / ${ec.total})` : '목적: 전멸'), W - 234, 31);
      ctx.font = `13px ${FONT}`; ctx.fillStyle = '#ddd'; ctx.fillText(oh ? oh.line : `남은 적 ${rm.total} (지금 ${rm.alive}) · 남은 웨이브 ${rm.wavesLeft} / ${rm.waves}`, W - 234, 50);
      if (!oh) { ctx.fillStyle = '#9fb3c8'; ctx.font = `12px ${FONT}`; ctx.fillText('모든 적을 처치하면 종료', W - 234, 68); }
      if (oh) { const tg = PA.Objectives.autoTarget(st); ctx.fillStyle = tg && tg.structure ? '#ffe066' : '#cfeaff'; ctx.fillText(`${oh.endRule} · 남은 적 ${rm.total} · 공격: ${tg ? (tg.structure ? tg.def.name : tg.def.name) : '없음'}`, W - 234, 68); }
    }
    const cfg = PA.CONFIG.PLAYER, dodgeCd = cfg.dodge.cooldown * b.dodgeCdMult;
    // 레벨·경험치
    const g = b.growth; if (g) { const need = PA.Growth.xpNeed(g.level), yy = p.shieldMax > 0 ? 58 : 38; ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(14, yy, 240, 14); ctx.fillStyle = '#ffd166'; ctx.fillRect(14, yy, 240 * Math.min(1, g.xp / need), 14); ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 1; ctx.strokeRect(14.5, yy + 0.5, 239, 13); ctx.fillStyle = '#fff'; ctx.font = `bold 11px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText(`Lv ${g.level}`, 20, yy + 11); ctx.textAlign = 'right'; ctx.fillText(`${Math.floor(g.xp)} / ${need}`, 250, yy + 11); }
    slot(ctx, W / 2 - 108, H - 78, 'Space', '회피', !p.dodge.active && p.dodge.cd <= 0, p.dodge.active ? 1 : Math.max(0, p.dodge.cd) / dodgeCd, '#7ef2ff');
    slot(ctx, W / 2 - 32, H - 78, 'Q', '감속장', p.special.cd <= 0, p.special.cd / b.specialCd, '#a9d8ff');
    if (p.special.cd > 0) { ctx.fillStyle = '#fff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(p.special.cd.toFixed(1) + 's', W / 2, H - 84); }
    const es = b.skills && b.skills.e; const ecd = es ? PA.Skills.cdOf(st, 'e') : 1;
    slot(ctx, W / 2 + 44, H - 78, 'E', es ? PA.SKILLS[es.id].name : '비어 있음', !!es && p.eCd <= 0, es ? (p.eCd || 0) / ecd : 1, '#ffe9a8');
    if (es && p.eCd > 0) { ctx.fillStyle = '#fff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'center'; ctx.fillText(p.eCd.toFixed(1) + 's', W / 2 + 76, H - 84); }
    // 무기 아이콘·레벨
    let wx = 14; const wy = H - 46;
    for (const w of st.weapons || []) { const s = w.stats; ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(wx, wy, 96, 34); ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 1; ctx.strokeRect(wx + 0.5, wy + 0.5, 95, 33); weaponIcon(ctx, wx + 16, wy + 17, s.kind); ctx.fillStyle = '#fff'; ctx.font = `bold 12px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText(`${s.name}`, wx + 32, wy + 14); ctx.font = `11px ${FONT}`; ctx.fillStyle = '#ffd166'; ctx.fillText(`Lv${s.level}${s.mods.length ? ' · ' + s.mods.map(mid => s.def.mods[mid].name).join(',') : ''}`, wx + 32, wy + 28); wx += 100; }
    const cm = Object.keys(b.commons || {}).filter(k => b.commons[k] > 0).map(k => PA.COMMONS[k].name + (b.commons[k] > 1 ? b.commons[k] : '')).join(', ');
    if (cm) { ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(14, H - 70, Math.min(360, 16 + cm.length * 12), 20); ctx.fillStyle = '#cfeaff'; ctx.font = `11px ${FONT}`; ctx.textAlign = 'left'; ctx.fillText('공통: ' + cm, 20, H - 56); }
    ctx.fillStyle = 'rgba(255,255,255,0.8)'; ctx.font = `12px ${FONT}`; ctx.textAlign = 'right'; ctx.fillText(PA.KEYS_TEXT, W - 14, H - 18);
    if (st.labText) { // 시험실: 현재 설정과 남은 시간(봇 실행 중에도 확인 가능)
      const tl = st.timeLimit > 0 ? ` · 남은 ${Math.max(0, st.timeLimit - st.t).toFixed(0)}초` : '';
      const ly = st.mode === 'boss' ? H - 118 : 10, lx = 262, lw = W - 222 - lx; let txt = st.labText + tl; ctx.font = `11px ${FONT}`; // 체력 막대와 목적 상자 사이(겹치지 않게), 길면 줄임
      while (txt.length > 8 && ctx.measureText(txt).width > lw - 12) txt = txt.slice(0, -4) + '…';
      ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(lx, ly, lw, 20); ctx.fillStyle = '#ffe9a8'; ctx.textAlign = 'center'; ctx.fillText(txt, lx + lw / 2, ly + 14);
    }
    if (st.status !== 'running') {
      ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = st.status === 'won' ? '#ffe066' : st.status === 'lost' ? '#ff6b6b' : '#cfd8e3'; ctx.font = `bold 40px ${FONT}`; ctx.textAlign = 'center';
      ctx.fillText(st.status === 'won' ? (st.mode === 'boss' ? `${PA.Boss.cfgOf(st.boss).name}을(를) 쓰러뜨렸다` : '전투 승리') : st.status === 'lost' ? '패배' : st.status === 'timeout' ? '시간 초과' : '중단', W / 2, H / 2 - 10);
    }
  }
  function weaponIcon(ctx, x, y, kind) {
    ctx.save(); ctx.translate(x, y); ctx.strokeStyle = '#e6edf5'; ctx.fillStyle = '#e6edf5'; ctx.lineWidth = 2;
    switch (kind) {
      case 'arc': ctx.beginPath(); ctx.arc(-4, 0, 11, -1, 1); ctx.stroke(); break;
      case 'beam': ctx.beginPath(); ctx.moveTo(-11, 0); ctx.lineTo(11, 0); ctx.stroke(); ctx.beginPath(); ctx.moveTo(11, 0); ctx.lineTo(5, -4); ctx.lineTo(5, 4); ctx.fill(); break;
      case 'melee': ctx.beginPath(); ctx.moveTo(-8, 8); ctx.lineTo(4, -8); ctx.moveTo(-2, 8); ctx.lineTo(10, -8); ctx.stroke(); break;
      case 'homing': ctx.beginPath(); ctx.arc(-4, 0, 10, -1.3, 1.3); ctx.stroke(); ctx.beginPath(); ctx.moveTo(-8, 0); ctx.lineTo(10, 0); ctx.stroke(); break;
      case 'heavy': ctx.fillRect(-3, -2, 6, 12); ctx.fillRect(-9, -10, 18, 9); break;
      case 'orbit': ctx.beginPath(); ctx.arc(0, 0, 9, 0, TAU); ctx.stroke(); ctx.beginPath(); ctx.arc(9, 0, 3, 0, TAU); ctx.arc(-9, 0, 3, 0, TAU); ctx.fill(); break;
      case 'chain': ctx.beginPath(); ctx.moveTo(-9, -8); ctx.lineTo(-2, 0); ctx.lineTo(-5, 1); ctx.lineTo(4, 9); ctx.stroke(); ctx.beginPath(); ctx.arc(6, -6, 4, 0, TAU); ctx.fill(); break;
      case 'bolt': ctx.beginPath(); ctx.moveTo(0, -10); ctx.lineTo(7, 0); ctx.lineTo(0, 10); ctx.lineTo(-7, 0); ctx.closePath(); ctx.fill(); break;
      case 'ember': ctx.fillStyle = '#ffb347'; ctx.beginPath(); ctx.arc(0, 2, 7, 0, TAU); ctx.fill(); ctx.fillStyle = '#ffe9a8'; ctx.beginPath(); ctx.arc(0, 0, 3, 0, TAU); ctx.fill(); break;
      case 'mine': ctx.fillStyle = '#d9b3ff'; ctx.beginPath(); ctx.moveTo(0, -9); ctx.lineTo(8, 5); ctx.lineTo(-8, 5); ctx.closePath(); ctx.fill(); break;
    }
    ctx.restore();
  }
  function drawDebug(ctx, st) {
    ctx.strokeStyle = '#0f0'; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(st.player.x, st.player.y, st.player.r, 0, TAU); ctx.stroke();
    for (const e of st.enemies) { if (e.dead) continue; ctx.strokeStyle = '#f0f'; ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, TAU); ctx.stroke(); ctx.fillStyle = '#0f0'; ctx.font = '10px monospace'; ctx.textAlign = 'left'; ctx.fillText(`${e.type} ${e.state} ${e.stateT.toFixed(2)} hp${Math.round(e.hp)}`, e.x + e.r + 2, e.y); }
    for (const p of st.projectiles) { ctx.strokeStyle = '#ff0'; ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, TAU); ctx.stroke(); }
    for (const ob of st.obstacles) { ctx.strokeStyle = '#0ff'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(ob.x, ob.y, ob.r, 0, TAU); ctx.stroke(); ctx.fillStyle = '#0ff'; ctx.font = '10px monospace'; ctx.fillText(`${ob.id || ob.type} r${ob.r}`, ob.x - 20, ob.y - ob.r - 4); }
    ctx.fillStyle = '#0f0'; ctx.font = '11px monospace'; ctx.textAlign = 'left';
    ctx.fillText(`t=${st.t.toFixed(2)} seed=${st.seed} enemies=${st.enemies.length} proj=${st.projectiles.length} zones=${st.zones.length} fx=${st.effects.length} dodge=${st.player.dodge.active} cd=${st.player.dodge.cd.toFixed(2)} prot=${st.player.hitProt.toFixed(2)} atk=${st.player.attackTimer.toFixed(2)}`, 14, 76);
  }

  function draw(ctx, st, opts) {
    opts = opts || {};
    const pad = PA.CONFIG.VIEW.pad, W = st.arena.w + pad * 2, H = st.arena.h + pad * 2;
    ctx.save(); ctx.translate(pad, pad);
    drawForest(ctx, st);
    drawObstacles(ctx, st);
    drawZones(ctx, st);
    drawChest(ctx, st);
    drawObjects(ctx, st);
    drawPickups(ctx, st);
    drawRange(ctx, st);
    drawWeaponBodies(ctx, st);
    drawPlayerEffects(ctx, st);
    // 개체는 y순으로 그려 겹침이 자연스럽게
    const ents = st.enemies.map(e => ({ y: e.y, f: () => drawEnemy(ctx, st, e) }));
    ents.push({ y: st.player.y, f: () => drawSwordsman(ctx, st) });
    ents.sort((a, b) => a.y - b.y); for (const o of ents) o.f();
    drawCanopies(ctx, st);       // 수관은 개체 위, 예고선 아래(가까우면 투명)
    drawTelegraphs(ctx, st);   // 예고는 내 이펙트와 캐릭터 위
    drawProjectiles(ctx, st);
    drawMisc(ctx, st);
    if (opts.debug) drawDebug(ctx, st);
    ctx.restore();
    drawHUD(ctx, st, W, H);
  }
  return { draw, FONT, drawBoss };
})();
