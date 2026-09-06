// 조작 정책 봇(브라우저 시험실·헤드리스 시뮬레이션 공용). 사람 플레이의 대체가 아니라 서로 다른 정책을 비교하는 도구다.
// 읽는 정보: 화면에 보이는 것만(적 상태·예고 각도·확정 방향·바닥 지역·투사체·체력·재사용). 미래 난수나 미공개 결과는 읽지 않는다.
// 규칙 위반 금지: 순간이동·체력 보정·피해 무효화 없음. 입력은 {mx,my,dodge,special,skillE}로만 나간다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Bot = (function () {
  const m = () => PA.m;
  // 정책 정의(문서용 필드 포함). thresholds는 예고 진행률(0~1)로, 그 이상 진행된 예고에만 반응한다.
  const POLICIES = {
    aggressive: { name: '공격 우선', reactAt: 1.0, dodgeLocked: true, zoneMargin: 0, keepDist: 40, retreatHp: 0, qMinEnemies: 2, eMinEnemies: 1, eRange: 200, giveUp: 'never',
      doc: { period: '40ms(일반)·헤드리스 5스텝', reads: '확정(lock/dash/leap)된 예고와 투사체만, 바닥 지역은 무시', target: '가장 가까운 적(표식이 있으면 표식)', q: '200 안 적 2마리 이상 또는 보스 빈틈', e: '200 안 적 1마리 이상', dodge: '확정 예고 통로/원 안에 있을 때', terrain: 'Combat.steerDir 접선 우회', giveUp: '없음(항상 접근)' } },
    balanced:   { name: '균형',     reactAt: 0.4, dodgeLocked: true, zoneMargin: 30, keepDist: 55, retreatHp: 0.25, qMinEnemies: 3, eMinEnemies: 2, eRange: 200, giveUp: 'hp<25%면 예고 없는 순간에만 접근',
      doc: { period: '40ms(일반)·헤드리스 5스텝', reads: '준비 40% 이상 진행된 예고·확정·투사체·바닥 지역·구름 예고', target: '궁수·주술사·서리술사 같은 후열 우선, 없으면 가장 가까운 적', q: '200 안 적 3마리 이상 또는 보스 빈틈·돌진 확정', e: '200 안 적 2마리 이상', dodge: '확정 예고 안에 있을 때', terrain: 'Combat.steerDir 접선 우회', giveUp: '체력 25% 미만이면 예고가 없을 때만 접근' } },
    survival:   { name: '생존 우선', reactAt: 0.0, dodgeLocked: true, zoneMargin: 60, keepDist: 90, retreatHp: 0.5, qMinEnemies: 1, eMinEnemies: 1, eRange: 160, giveUp: 'hp<50%면 이탈, 위협 없을 때만 사거리까지 접근',
      doc: { period: '40ms(일반)·헤드리스 5스텝', reads: '모든 준비 단계 예고·투사체·바닥 지역(여유 60)', target: '가장 가까운 적을 사거리 끝에서', q: '위협이 확정된 적이 200 안에 1마리 이상', e: '160 안 적 1마리 이상(결계·돌풍은 방어용)', dodge: '확정 예고 안 또는 근접 적 60 안', terrain: 'Combat.steerDir 접선 우회', giveUp: '체력 50% 미만이면 모든 적에서 이탈(시간 초과 가능 — 성공으로 집계하지 않음)' } },
  };

  // ---------- 위협 도형 ----------
  // {kind:'beam', x,y,ang,len,w, prog(0~1), locked} | {kind:'circle', x,y,r, prog, locked} | {kind:'zone', x,y,r}
  function threats(st) {
    const out = [], p = st.player;
    for (const e of st.enemies) {
      if (e.dead) continue;
      const d = e.def;
      if (e.boss) { bossThreats(st, e, out); continue; }
      if (e.type === 'wolf' || e.type === 'wolf_alpha') {
        if (e.state === 'crouch') out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.aimAngle, len: d.dashSpeed * d.dashTime + 40, w: (e.r + p.r) * 2 + 30, prog: e.stateT / d.crouch, locked: false });
        else if (e.state === 'lock' || e.state === 'dash') out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.dir, len: d.dashSpeed * d.dashTime + 40, w: (e.r + p.r) * 2 + 30, prog: 1, locked: true });
      } else if (e.type === 'archer') {
        if (e.state === 'aim') out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.aimAngle, len: 2000, w: 40, prog: e.stateT / d.aim, locked: false });
        else if (e.state === 'lock') out.push({ kind: 'beam', e, x: e.x, y: e.y, ang: e.dir, len: 2000, w: 40, prog: 1, locked: true });
      } else if (e.type === 'spore') {
        if (e.state === 'swell') out.push({ kind: 'circle', e, x: e.x, y: e.y, r: d.cloudR, prog: e.stateT / d.swell, locked: e.stateT / d.swell > 0.6 });
      } else if (PA.Enemies && PA.Enemies.threats) PA.Enemies.threats(st, e, out);
    }
    for (const pr of st.projectiles) if (pr.owner === 'enemy') out.push({ kind: 'beam', x: pr.x, y: pr.y, ang: Math.atan2(pr.vy, pr.vx), len: 220, w: 40 + pr.r * 2, prog: 1, locked: true, proj: true });
    for (const z of st.zones) if (z.type === 'spore') out.push({ kind: 'zone', x: z.x, y: z.y, r: z.r });
    if (PA.Enemies && PA.Enemies.zoneThreats) PA.Enemies.zoneThreats(st, out);
    return out;
  }
  function bossThreats(st, bz, out) {
    const cfg = PA.BOSS, p = st.player;
    if (bz.state === 'dash_aim') out.push({ kind: 'beam', e: bz, x: bz.x, y: bz.y, ang: bz.aimAngle, len: cfg.dash.dist + 40, w: (bz.r + p.r) * 2 + 40, prog: bz.stateT / cfg.dash.aim, locked: false });
    if (bz.state === 'dash_lock' || bz.state === 'dash') out.push({ kind: 'beam', e: bz, x: bz.x, y: bz.y, ang: bz.dir, len: (bz.dashLen || cfg.dash.dist) + 40, w: (bz.r + p.r) * 2 + 40, prog: 1, locked: true });
    if (bz.state === 'sweep_aim') out.push({ kind: 'arc', e: bz, x: bz.x, y: bz.y, ang: bz.aimAngle, r: cfg.sweep.radius + 30, half: cfg.sweep.arcDeg * Math.PI / 360 + 0.2, prog: bz.stateT / cfg.sweep.aim, locked: false });
    if (bz.state === 'sweep_lock') out.push({ kind: 'arc', e: bz, x: bz.x, y: bz.y, ang: bz.dir, r: cfg.sweep.radius + 30, half: cfg.sweep.arcDeg * Math.PI / 360 + 0.2, prog: 1, locked: true });
    if ((bz.state === 'pounce_aim' || bz.state === 'pounce_lock' || bz.state === 'leap') && bz.land) out.push({ kind: 'circle', e: bz, x: bz.land.x, y: bz.land.y, r: cfg.pounce.radius + 40, prog: bz.state === 'pounce_aim' ? bz.stateT / cfg.pounce.aim : 1, locked: bz.state !== 'pounce_aim' });
  }
  function inside(th, p) {
    if (th.kind === 'beam') return m().inBeam(th, th.ang, th.len, th.w, p, p.r);
    if (th.kind === 'circle' || th.kind === 'zone') return m().dist(th, p) <= th.r + p.r;
    if (th.kind === 'arc') return m().inArc(th, th.r, th.ang, th.half, p, p.r);
    return false;
  }
  // 위협에서 벗어나는 방향
  function escapeDir(th, p) {
    if (th.kind === 'beam') { const side = { x: -Math.sin(th.ang), y: Math.cos(th.ang) }; const rel = { x: p.x - th.x, y: p.y - th.y }; const s = (rel.x * side.x + rel.y * side.y) >= 0 ? 1 : -1; return { x: side.x * s, y: side.y * s }; }
    const n = m().norm(p.x - th.x, p.y - th.y); return (n.x || n.y) ? n : { x: 1, y: 0 };
  }

  // ---------- 대상 선택 ----------
  const BACKLINE = ['shaman', 'archer', 'frostcaller', 'spider'];
  function pickTarget(st, pol) {
    const p = st.player, alive = st.enemies.filter(e => !e.dead && !e.hidden);
    if (!alive.length) return null;
    if (st.markTarget && !st.markTarget.dead) return st.markTarget;
    const bz = st.boss; if (bz && !bz.dead) return bz;
    if (pol === POLICIES.balanced) { const back = alive.filter(e => BACKLINE.includes(e.type)).sort((a, b) => m().dist(a, p) - m().dist(b, p)); if (back.length) return back[0]; }
    return alive.slice().sort((a, b) => m().dist(a, p) - m().dist(b, p))[0];
  }
  function weaponRange(st) { let r = 0; for (const w of st.weapons || []) { const s = w.stats; const rr = s.kind === 'orbit' ? s.radius : (s.range || 60); if (rr > r) r = rr; } return r || 80; }

  // ---------- 판단 ----------
  // mem: 봇의 기억(조향 상태 등). 반환 {mx,my,dodge,special,skillE}
  function decide(policyId, st, mem) {
    const pol = POLICIES[policyId] || POLICIES.balanced, p = st.player, M = m();
    mem = mem || {}; mem.steer = mem.steer || { x: 0, y: 0, r: p.r, steerSide: 0, steerT: 0 };
    let mv = { x: 0, y: 0 }, dodge = false, special = false, skillE = false, threatened = false, lockedNear = false;
    const alive = st.enemies.filter(e => !e.dead && !e.hidden);
    const hpRatio = p.hp / p.hpMax;
    // 1) 위협 회피(정책의 반응 시점 이상 진행된 예고만)
    let ex = 0, ey = 0, n = 0;
    for (const th of threats(st)) {
      if (th.kind === 'zone') { if (pol.zoneMargin > 0 && M.dist(th, p) <= th.r + pol.zoneMargin) { const d = escapeDir(th, p); ex += d.x; ey += d.y; n++; } continue; }
      if (th.prog < pol.reactAt && !th.locked) continue;
      const near = th.kind === 'circle' ? M.dist(th, p) <= th.r + pol.zoneMargin + p.r : inside(th, p);
      if (!near) continue;
      const d = escapeDir(th, p); ex += d.x; ey += d.y; n++; threatened = true;
      if (th.locked && pol.dodgeLocked && !th.proj) dodge = true;
      if (th.locked && th.proj) dodge = true;
      if (th.locked && th.e && M.dist(th.e, p) < 200) lockedNear = true;
    }
    if (n) { const d = M.norm(ex, ey); mv = (d.x || d.y) ? d : { x: 1, y: 0 }; }
    // 2) 접근·이탈
    const target = pickTarget(st, pol);
    if (!threatened && n === 0 && target) {
      const d = M.dist(target, p), toT = M.norm(target.x - p.x, target.y - p.y);
      const bz = target.boss ? target : null;
      const range = weaponRange(st);
      const orbitOnly = (st.weapons || []).length > 0 && st.weapons.every(w => w.stats.kind === 'orbit' || w.stats.kind === 'mine'); // 공전 칼날만 있으면 궤도(반지름)에 적이 걸치도록 거리를 둔다
      let want = target.boss ? (PA.Boss.isExposed(target) ? target.r + 40 : target.r + range * 0.7) : Math.max(pol.keepDist, pol === POLICIES.survival ? range * 0.85 : 0, orbitOnly ? range * 0.9 : 0);
      if (pol === POLICIES.survival && hpRatio < pol.retreatHp) want = 260;                     // 생존 우선: 체력이 낮으면 이탈
      if (pol === POLICIES.balanced && hpRatio < pol.retreatHp && alive.some(e => e.state !== 'approach' && e.state !== 'recover')) want = Math.max(want, 160);
      if (pol === POLICIES.survival && alive.some(e => (e.state !== 'approach' && e.state !== 'recover' && e.state !== 'stagger') && M.dist(e, p) < 60)) dodge = true; // 근접 위협에서 굴러 나감
      if (d > want + 10) { const s = mem.steer; s.x = p.x; s.y = p.y; if (s.steerT > 0) s.steerT -= 0.04; mv = st.obstacles.length ? PA.Combat.steerDir(st, s, target.x, target.y) : toT; }
      else if (d < want - 30) mv = { x: -toT.x, y: -toT.y };
    }
    // 3) Q/E
    const near200 = alive.filter(e => M.dist(e, p) < 200).length;
    const bz = st.boss;
    if (p.special.cd <= 0) {
      if (bz && !bz.dead && (bz.state === 'recover' || bz.state === 'dash_lock') && M.dist(bz, p) < 180) special = true;
      if (pol === POLICIES.survival ? (lockedNear || (near200 >= 1 && threatened)) : near200 >= pol.qMinEnemies) special = true;
    }
    const es = st.build.skills && st.build.skills.e;
    if (es && p.eCd <= 0) { const nearE = alive.filter(e => M.dist(e, p) < pol.eRange).length; if (nearE >= pol.eMinEnemies) skillE = true; if (es.id === 'ward' && pol !== POLICIES.survival && !threatened && hpRatio > 0.7) skillE = false; }
    return { mx: mv.x, my: mv.y, dodge, special, skillE };
  }
  // 판단 주기 양자화: 고정 시뮬레이션 단계 번호(st.stepN, 다음에 실행될 단계)가 DECIDE_STEPS의 배수일 때만 판단한다(120단계/초 → 5단계 = 40ms).
  // 판단 결과의 단발 입력(회피·Q·E)은 그 판단이 붙은 단계에서 소비되고, 다음 판단 전까지 이동 입력만 유지된다.
  // 브라우저(main.frame)와 헤드리스(runCombat)가 모두 이 함수를 단계마다 호출하므로 프레임 속도와 무관하게 같은 입력 일정을 만든다.
  const DECIDE_STEPS = 5;
  function stepInput(st, policyId, mem) {
    const n = (st.stepN || 0); // 이번에 실행될 단계 번호(step 호출 전)
    if (!mem.last || n % DECIDE_STEPS === 0) { mem.last = decide(policyId, st, mem); mem.lastN = n; return mem.last; }
    return { mx: mem.last.mx, my: mem.last.my, dodge: false, special: false, skillE: false };
  }
  // 헤드리스 실행 보조: 단계마다 stepInput
  function runCombat(st, policyId, opts) {
    opts = opts || {}; const dt = PA.CONFIG.STEP, maxN = Math.round((opts.maxSec || 180) / dt); let n = 0; const mem = opts.mem || {};
    let farSteps = 0, aliveSteps = 0;
    while (st.status === 'running' && n < maxN) {
      const inp = stepInput(st, policyId, mem);
      PA.Combat.step(st, inp, dt); n++;
      if (n % 12 === 0) { // 길찾기 실패 진단: 적이 살아 있는데 모든 적과 300 이상 떨어진 시간 비율(시간 초과의 원인 구분용)
        const p = st.player; let near = false, any = false; for (const e of st.enemies) { if (e.dead || e.hidden) continue; any = true; if (PA.m.dist(e, p) < 300) { near = true; break; } }
        if (any) { aliveSteps++; if (!near) farSteps++; }
      }
      if (opts.onLevelUp && st.levelUps > 0) { st.levelUps = 0; opts.onLevelUp(st); }
    }
    if (st.metrics) st.metrics.farFrac = aliveSteps ? Math.round(farSteps / aliveSteps * 100) / 100 : 0;
    return st;
  }
  // 브라우저 프레임 재현(검증용): 프레임마다 dt를 누적하고 고정 단계를 실행한다(main.frame과 같은 규칙: 12단계 상한, 초과분 버림)
  function frameLoop(st, policyId, fps, opts) {
    opts = opts || {}; const dt = PA.CONFIG.STEP, mem = {}; let acc = 0, frames = 0; const maxFrames = Math.round((opts.maxSec || 180) * fps);
    while (st.status === 'running' && frames < maxFrames) {
      acc += Math.min(0.1, 1 / fps); let guard = 0;
      while (acc >= dt && guard++ < 12) { PA.Combat.step(st, stepInput(st, policyId, mem), dt); acc -= dt; }
      if (guard >= 12) acc = 0; frames++;
    }
    return st;
  }
  // 성장 모드에서 봇의 카드 선택: 새 무기 > E 습득 > 무기 방식 > 무기 레벨 > 나머지 순, 같은 순위면 시드 난수
  function pickChoice(offer, seed) {
    const order = ['weapon_new', 'skill_new', 'weapon_mod', 'weapon_level', 'common', 'skill_level', 'skill_variant', 'passive', 'boss_reward'];
    const cs = offer.choices; if (!cs.length) return null;
    const best = Math.min(...cs.map(c => order.indexOf(c.kind)));
    const pool = cs.filter(c => order.indexOf(c.kind) === best);
    return pool[Math.floor(PA.rng.create((seed || 1) + offer.seq * 13).next() * pool.length)];
  }
  return { POLICIES, threats, decide, stepInput, runCombat, frameLoop, pickChoice, weaponRange, DECIDE_STEPS };
})();
