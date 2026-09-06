// 첫 한 바퀴(A~H) 자동 점검. 간단한 정책 봇이 전투를 치르고, 상점·하루 종료·저장/재실행·보스 도래까지 밟는다.
// 봇은 PA_G.keys/pressed에 직접 입력을 넣는다(키보드 이벤트 경로는 tools/shots.js가 검증).
const path = require('path'); const fs = require('fs');
const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'shots'); fs.mkdirSync(OUT, { recursive: true });
const url = 'file://' + path.join(ROOT, 'index.html');
const BOT = `(() => {
  if (window.__bot) clearInterval(window.__bot);
  window.__bot = setInterval(() => {
    const G = window.PA_G; if (!G || G.screen !== 'combat' || !G.combat || G.combat.status !== 'running' || G.paused) return;
    const st = G.combat, p = st.player, m = PA.m, keys = new Set();
    const alive = st.enemies.filter(e => !e.dead);
    let mv = { x: 0, y: 0 }, dodge = false, special = false;
    // 1) 위협: 확정/돌진 중인 늑대의 직선, 확정된 화살
    for (const e of alive) {
      if ((e.type === 'wolf' || e.type === 'wolf_alpha') && (e.state === 'lock' || e.state === 'dash' || (e.state === 'crouch' && e.stateT > 0.4))) {
        const ang = e.state === 'crouch' ? e.aimAngle : e.dir;
        if (m.inBeam(e, ang, e.def.dashSpeed * e.def.dashTime + 40, (e.r + p.r) * 2 + 30, p, p.r)) {
          const side = { x: -Math.sin(ang), y: Math.cos(ang) };
          const rel = { x: p.x - e.x, y: p.y - e.y }; const s = (rel.x * side.x + rel.y * side.y) >= 0 ? 1 : -1;
          mv = { x: side.x * s, y: side.y * s }; if (e.state !== 'crouch') dodge = true;
        }
      }
      if (e.type === 'archer' && e.state === 'lock') {
        if (m.inBeam(e, e.dir, 2000, 40, p, p.r)) { const side = { x: -Math.sin(e.dir), y: Math.cos(e.dir) }; mv = side; dodge = true; }
      }
    }
    for (const pr of st.projectiles) if (pr.owner === 'enemy') { const ang = Math.atan2(pr.vy, pr.vx); if (m.inBeam(pr, ang, 200, 40, p, p.r)) { mv = { x: -Math.sin(ang), y: Math.cos(ang) }; dodge = true; } }
    // 2) 지역 회피
    if (!dodge) for (const z of st.zones) if (z.type === 'spore' && m.dist(z, p) < z.r + 30) { const n = m.norm(p.x - z.x, p.y - z.y); mv = n.x || n.y ? n : { x: 1, y: 0 }; }
    for (const e of alive) if (e.type === 'spore' && e.state === 'swell' && m.dist(e, p) < e.def.cloudR + 30) { const n = m.norm(p.x - e.x, p.y - e.y); mv = n; }
    // 3) 목표 접근
    if (!mv.x && !mv.y) {
      let target = alive.find(e => e.type === 'archer') || alive.slice().sort((a, b) => m.dist(a, p) - m.dist(b, p))[0];
      if (st.chest && !st.chest.opened && alive.length <= 1) target = st.chest;
      if (target) { const d = m.dist(target, p); const n = m.norm(target.x - p.x, target.y - p.y); if (d > 55 || target === st.chest) mv = n; }
    }
    if (alive.filter(e => m.dist(e, p) < 220).length >= 3 && p.special.cd <= 0) special = true;
    if (mv.x > 0.3) keys.add('KeyD'); if (mv.x < -0.3) keys.add('KeyA'); if (mv.y > 0.3) keys.add('KeyS'); if (mv.y < -0.3) keys.add('KeyW');
    G.keys = keys; if (dodge) G.pressed.add('Space'); if (special) G.pressed.add('KeyQ');
  }, 40);
})()`;

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const log = []; const say = (s) => { log.push(s); console.log(s); };
  const state = () => page.evaluate(() => { const G = PA_G; return { screen: G.screen, run: G.run && { day: G.run.day, hours: G.run.hours, gold: G.run.gold, mats: G.run.mats, hp: G.run.hp, gear: G.run.gear, augments: G.run.augments, owned: G.run.owned, ended: G.run.ended }, combat: G.combat && { status: G.combat.status, kills: G.combat.stats.kills, hp: G.combat.player.hp, beam: G.combat.effects.some(f => f.kind === 'beam') } }; });
  const click = async (sel) => { await page.click(sel); await page.waitForTimeout(150); };
  const waitScreen = async (pred, ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const s = await state(); if (pred(s)) return s; await page.waitForTimeout(150); } throw new Error('timeout waiting'); };
  let sawBeam = false, sawSpin = false;
  async function sortie(region) {
    await click('[data-action=map]'); await click(`[data-action=sortie][data-arg=${region}]`);
    await page.evaluate(BOT);
    let beam = false;
    const s = await waitScreen(async => false, 0).catch(() => null);
    const t0 = Date.now();
    while (Date.now() - t0 < 180000) {
      const st = await state();
      if (st.combat && st.combat.beam) beam = true;
      if (st.screen !== 'combat') break;
      await page.waitForTimeout(200);
    }
    if (beam) sawBeam = true;
    let st = await state();
    if (st.screen === 'reward') {
      const stats = await page.evaluate(() => PA_G.lastStats);
      say(`  ${region}: 승리 · 처치 ${stats.kills} · 받은 피해 ${Math.round(stats.damageTaken)} · 회피! ${stats.perfectDodges} · ${Math.round(stats.elapsed)}초`);
      const offers = await page.$$('[data-action=pick]');
      if (offers.length) { const names = await page.$$eval('.aug .card-title', els => els.map(e => e.textContent.trim())); say(`  제시: ${names.join(' | ')}`); await offers[0].click(); await page.waitForTimeout(150); }
      else await click('[data-action=skip]');
      await click('[data-action=return]');
    } else if (st.screen === 'defeat') {
      const stats = await page.evaluate(() => PA_G.lastStats);
      say(`  ${region}: 패배 · 처치 ${stats.kills} · ${Math.round(stats.elapsed)}초`);
      await click('[data-action=base]');
    } else throw new Error('unexpected screen ' + st.screen);
    st = await state(); say(`  → ${st.run.day}일차 ${st.run.hours}시간 · 금화 ${st.run.gold} · 가죽 ${st.run.mats.pelt} 철 ${st.run.mats.iron} · 체력 ${st.run.hp}`);
    return st;
  }

  await page.goto(url); await page.waitForTimeout(400);
  await page.evaluate(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(400);
  await click('[data-action=newrun]');
  say('A. 거점 시작'); let st = await state(); say(`  ${st.run.day}일차 · ${st.run.hours}시간 · 금화 ${st.run.gold}`);
  say('B/C/D. 출격 반복 (관통검 재료 모으기)');
  const plan = ['forest', 'forest', 'ridge', 'ridge', 'forest', 'ridge', 'forest', 'den', 'ridge', 'forest'];
  let bought = false;
  for (let day = 1; day <= 6 && !bought; day++) {
    for (const region of plan) {
      st = await state();
      const cost = { forest: 1, ridge: 1, marsh: 2, den: 2, deep: 3 }[region];
      if (st.run.hours < cost) continue;
      if (st.run.hp < 45 && st.run.hours >= 1) { await click('[data-action=rest]'); say('  휴식 (1시간)'); st = await state(); if (st.run.hours < cost) continue; }
      st = await sortie(region);
      const can = await page.evaluate(() => PA.Run.canBuy(PA_G.run, PA.Run.item('pierce_sword')));
      if (can) { await click('[data-action=shop]'); await page.screenshot({ path: path.join(OUT, 'p1_shop_ready.png') }); await click('[data-action=buy][data-arg=pierce_sword]'); await page.screenshot({ path: path.join(OUT, 'p2_shop_bought.png') }); st = await state(); say(`F. 관통검 제작·장착: 무기 ${st.run.gear.weapon} · 금화 ${st.run.gold} · 가죽 ${st.run.mats.pelt} 철 ${st.run.mats.iron}`); await click('[data-action=base]'); bought = true; break; }
    }
    if (!bought) { await click('[data-action=endday-confirm]'); await click('[data-action=endday]'); st = await state(); say(`  하루 종료 → ${st.run.day}일차 · 체력 ${st.run.hp}`); }
  }
  if (!bought) say('!! 6일 안에 관통검을 사지 못함');
  say('H. 저장 → 재실행 → 계속하기');
  const before = await state();
  await page.reload(); await page.waitForTimeout(400);
  const cont = await page.$('[data-action=continue]'); if (!cont) throw new Error('계속하기 버튼 없음');
  await cont.click(); await page.waitForTimeout(200);
  const after = await state();
  const same = JSON.stringify(before.run) === JSON.stringify(after.run);
  say(`  복구 동일: ${same}`); if (!same) { say(JSON.stringify(before.run)); say(JSON.stringify(after.run)); }
  say('G. 관통검으로 다시 출격 (성장 유지 확인)');
  st = await state(); if (st.run.hours < 1) { await click('[data-action=endday-confirm]'); await click('[data-action=endday]'); }
  await click('[data-action=map]'); await click('[data-action=sortie][data-arg=ridge]'); await page.evaluate(BOT); await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(OUT, 'p3_pierce_combat.png') });
  const t0 = Date.now(); let beam = false; while (Date.now() - t0 < 120000) { const s = await state(); if (s.combat && s.combat.beam) beam = true; if (s.screen !== 'combat') break; await page.waitForTimeout(200); }
  say(`  관통 검격 관측: ${beam}`); sawBeam = sawBeam || beam;
  st = await state();
  if (st.screen === 'reward') { const o = await page.$('[data-action=pick]'); if (o) await o.click(); else await click('[data-action=skip]'); await page.waitForTimeout(150); const deep = await page.$('[data-action=deep]:not([disabled])'); if (deep) { say('  더 깊이 탐험 (+1시간)'); await deep.click(); await page.waitForTimeout(2000); const t1 = Date.now(); while (Date.now() - t1 < 150000) { const s = await state(); if (s.screen !== 'combat') break; await page.waitForTimeout(200); } st = await state(); if (st.screen === 'reward') { const o2 = await page.$('[data-action=pick]'); if (o2) await o2.click(); else await click('[data-action=skip]'); await page.waitForTimeout(150); await click('[data-action=return]'); } else await click('[data-action=base]'); } else await click('[data-action=return]'); }
  else await click('[data-action=base]');
  st = await state(); say(`  귀환: 금화 ${st.run.gold} · 증강 ${JSON.stringify(st.run.augments)}`);
  say('보스 도래까지 하루 종료 반복');
  while (true) { st = await state(); if (st.screen === 'bossday' || st.run.ended) break; await click('[data-action=endday-confirm]'); await click('[data-action=endday]'); }
  await page.screenshot({ path: path.join(OUT, 'p4_bossday.png') });
  st = await state(); say(`  화면: ${st.screen} · ${st.run.day}일차 · ended=${st.run.ended}`);
  say(`오류: ${errors.length ? errors.join(' / ') : '없음'}`);
  fs.writeFileSync(path.join(OUT, 'playthrough_log.txt'), log.join('\n'));
  await browser.close();
  if (errors.length || !bought || !same || !sawBeam) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
