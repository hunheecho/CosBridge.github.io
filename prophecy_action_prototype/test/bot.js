// 헤드리스 시험용 조작 정책(브라우저 봇과 같은 규칙). 예고를 읽고 옆으로 피하고, 보스 빈틈에 접근하며, 적이 모이면 Q.
function policy(PA, st) {
  const p = st.player, m = PA.m, alive = st.enemies.filter(e => !e.dead);
  let mv = { x: 0, y: 0 }, dodge = false, special = false;
  const bz = st.boss;
  const sideStep = (from, ang) => { const side = { x: -Math.sin(ang), y: Math.cos(ang) }; const rel = { x: p.x - from.x, y: p.y - from.y }; const s = (rel.x * side.x + rel.y * side.y) >= 0 ? 1 : -1; return { x: side.x * s, y: side.y * s }; };
  // 1) 보스 위험
  if (bz && !bz.dead) {
    const cfg = PA.BOSS;
    if ((bz.state === 'dash_lock' || bz.state === 'dash' || (bz.state === 'dash_aim' && bz.stateT > 0.4))) {
      const ang = bz.state === 'dash_aim' ? bz.aimAngle : bz.dir;
      if (m.inBeam(bz, ang, (bz.dashLen || cfg.dash.dist) + 40, (bz.r + p.r) * 2 + 40, p, p.r)) { mv = sideStep(bz, ang); if (bz.state !== 'dash_aim') dodge = true; }
    }
    if ((bz.state === 'sweep_aim' && bz.stateT > 0.3) || bz.state === 'sweep_lock') {
      const ang = bz.state === 'sweep_aim' ? bz.aimAngle : bz.dir;
      if (m.inArc(bz, cfg.sweep.radius + 30, ang, cfg.sweep.arcDeg * Math.PI / 360 + 0.2, p, p.r)) { const away = m.norm(p.x - bz.x, p.y - bz.y); mv = away; if (bz.state === 'sweep_lock') dodge = true; }
    }
    if ((bz.state === 'pounce_lock' || bz.state === 'leap') && bz.land && m.dist(bz.land, p) < cfg.pounce.radius + 40) { mv = m.norm(p.x - bz.land.x, p.y - bz.land.y); if (bz.state === 'leap') dodge = true; }
  }
  // 2) 늑대 위험
  for (const e of alive) {
    if (e.boss) continue;
    if ((e.type === 'wolf' || e.type === 'wolf_alpha') && (e.state === 'lock' || e.state === 'dash' || (e.state === 'crouch' && e.stateT > 0.4))) {
      const ang = e.state === 'crouch' ? e.aimAngle : e.dir;
      if (m.inBeam(e, ang, e.def.dashSpeed * e.def.dashTime + 40, (e.r + p.r) * 2 + 30, p, p.r)) { mv = sideStep(e, ang); if (e.state !== 'crouch') dodge = true; }
    }
  }
  // 3) 접근: 보스 빈틈이면 붙고, 아니면 사거리 근처 유지
  if (!mv.x && !mv.y) {
    const target = bz && !bz.dead ? bz : alive.sort((a, b) => m.dist(a, p) - m.dist(b, p))[0];
    if (target) {
      const d = m.dist(target, p), n = m.norm(target.x - p.x, target.y - p.y);
      const want = target.boss ? (PA.Boss.isExposed(target) ? target.r + 40 : target.r + st.build.range * 0.7) : 55;
      if (d > want + 10) mv = n; else if (d < want - 30 && target.boss && !PA.Boss.isExposed(target)) mv = { x: -n.x, y: -n.y };
    }
  }
  // 4) 감속장: 보스 빈틈 시작 또는 적 3마리 근접
  if (p.special.cd <= 0) { if (bz && !bz.dead && (bz.state === 'recover' || bz.state === 'dash_lock') && m.dist(bz, p) < 180) special = true; if (alive.filter(e => m.dist(e, p) < 200).length >= 3) special = true; }
  return { mx: mv.x, my: mv.y, dodge, special };
}
// 보스전을 정책 봇으로 끝까지 실행
function runBossFight(PA, run, seed, maxSec) {
  const st = PA.Combat.create({ build: PA.Run.build(run), seed: seed || 5, boss: true, arena: 'clearing', waves: [] });
  const dt = PA.CONFIG.STEP; let n = 0; const max = Math.round((maxSec || 300) / dt);
  let lastInput = { mx: 0, my: 0 };
  while (st.status === 'running' && n < max) {
    const inp = (n % 5 === 0) ? policy(PA, st) : Object.assign({}, lastInput, { dodge: false, special: false }); // 40ms마다 판단, 단발 입력은 그 프레임만
    lastInput = inp; PA.Combat.step(st, inp, dt); n++;
  }
  return st;
}
module.exports = { policy, runBossFight };
