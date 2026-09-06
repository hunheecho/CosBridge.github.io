// 자세 대조표: 시뮬레이션 상태를 직접 구성해 늑대·마검사의 각 동작을 한 장에 그린다(검증·문서용).
const path = require('path'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1048, height: 688 } });
  await p.goto('file://' + path.join(ROOT, 'index.html') + '?scenario=forest&seed=11'); await p.waitForTimeout(500);
  await p.evaluate(() => {
    const G = PA_G, st = G.combat; G.paused = true;
    st.enemies = []; st.pending = []; st.waveIndex = 99; st.effects = []; st.zones = [];
    const mk = (x, y, state, extra) => { const e = PA.Combat.spawnEnemy(st, 'wolf', x, y); Object.assign(e, { state, stateT: 0.3, aimAngle: 0, dir: 0, faceX: 1, moveT: 0.3 }, extra || {}); return e; };
    mk(120, 120, 'approach'); mk(280, 120, 'crouch'); mk(440, 120, 'lock'); mk(600, 120, 'dash', { biteT: 9 }); mk(760, 120, 'dash', { biteT: 0.05 }); mk(920, 120, 'recover');
    const dead = mk(120, 260, 'recover'); dead.dead = true; dead.deathT = 0.3;
    const alpha = PA.Combat.spawnEnemy(st, 'wolf_alpha', 300, 260); Object.assign(alpha, { state: 'crouch', stateT: 0.3, aimAngle: Math.PI, dir: Math.PI, faceX: -1 });
    st.player.x = 480; st.player.y = 260; st.player.face = 0; st.player.moving = false; st.player.swingT = 9;
    // 라벨
    const labels = [[120, 120, '접근(걷기)'], [280, 120, '준비(웅크림)'], [440, 120, '확정(!)'], [600, 120, '돌진(턱 벌림)'], [760, 120, '물기(턱 닫힘)'], [920, 120, '빈틈(회복)'], [120, 260, '사망'], [300, 260, '우두머리 준비'], [480, 260, '마검사 대기']];
    for (const [x, y, t] of labels) st.effects.push({ kind: 'text', x, y: y + 44, text: t, color: '#ffe9a8', ttl: 999, t: 0 });
    window.__draw = () => PA.Render.draw(document.querySelector('#game').getContext('2d'), st, {});
  });
  await p.waitForTimeout(100); await p.screenshot({ path: path.join(ROOT, 'shots', 'pose_wolves.png') });
  await p.evaluate(() => {
    const st = PA_G.combat; st.enemies = []; st.effects = [];
    const P = st.player; const snaps = [];
    const draw = (x, y, patch, label) => { Object.assign(P, { x, y, face: 0, moving: false, swingT: 9, hurtT: 9, flash: 0, hitProt: 0, walkT: 0.12 }); P.dodge.active = false; Object.assign(P, patch); if (patch.dodge) Object.assign(P.dodge, patch.dodge); PA.Render.draw(document.querySelector('#game').getContext('2d'), st, {}); snaps.push({ x, y, label }); };
    // 각 자세를 별도 캔버스에 그려 합성하기 어려우므로, 자세마다 개체 하나를 두는 대신 그림을 순차 캡처하는 방식은 밖에서 한다.
    window.__poses = [
      ['대기', {}], ['걷기', { moving: true, walkT: 0.12 }], ['검 휘두르기', { swingT: 0.06, swingForm: 'arc' }], ['관통 찌르기', { swingT: 0.05, swingForm: 'beam' }], ['회피(구르기)', { dodge: { active: true, t: 0.13, dx: 1, dy: 0 } }], ['피격', { hurtT: 0.05, flash: 0.15, hitProt: 0.5 }], ['왼쪽 보기', { face: Math.PI }],
    ];
    window.__setPose = (i, x, y) => { const [label, patch] = window.__poses[i]; Object.assign(P, { x, y, face: 0, moving: false, swingT: 9, hurtT: 9, flash: 0, hitProt: 0, walkT: 0.12, swingForm: 'arc' }); P.dodge.active = false; const pp = Object.assign({}, patch); if (pp.dodge) { Object.assign(P.dodge, pp.dodge); delete pp.dodge; } Object.assign(P, pp); st.effects = [{ kind: 'text', x, y: y + 44, text: label, color: '#ffe9a8', ttl: 999, t: 0 }]; PA.Render.draw(document.querySelector('#game').getContext('2d'), st, {}); };
  });
  // 자세별 개별 캡처 후 합성
  const clips = [];
  for (let i = 0; i < 7; i++) { await p.evaluate((i) => window.__setPose(i, 480, 300), i); await p.waitForTimeout(60); clips.push(await p.screenshot({ clip: { x: 480 + 44 - 70, y: 300 + 44 - 70, width: 140, height: 140 } })); }
  await b.close();
  // 합성: 캔버스 없이 단순히 가로로 이어붙이기 위해 다시 브라우저 사용
  const b2 = await chromium.launch(); const p2 = await b2.newPage({ viewport: { width: 140 * clips.length, height: 140 } });
  await p2.setContent('<body style="margin:0;background:#1b2118">' + clips.map(c => `<img style="float:left" src="data:image/png;base64,${c.toString('base64')}">`).join('') + '</body>');
  await p2.screenshot({ path: path.join(ROOT, 'shots', 'pose_swordsman.png') }); await b2.close();
  console.log('pose sheets written');
})().catch(e => { console.error(e); process.exit(1); });
