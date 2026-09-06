// 실제 움직이는 전투 녹화. 페이지 안에서 canvas.captureStream + MediaRecorder(VP8)로 캔버스를 직접 녹화한다.
// (헤드리스 환경에서 Playwright recordVideo는 캔버스를 담지 못했다.)
// 사용: NODE_PATH=<playwright> node tools/record.js [scenario query] [seconds]
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'docs', 'video'); fs.mkdirSync(OUT, { recursive: true });
const q = process.argv[2] || '?scenario=forest&seed=11'; const SEC = parseInt(process.argv[3] || '30', 10);
const POLICY_SRC = fs.readFileSync(path.join(__dirname, '..', 'test', 'bot.js'), 'utf8').replace(/module\.exports[\s\S]*$/, '');
const BOT_POLICY = `(() => { ${POLICY_SRC}; if (window.__bot) clearInterval(window.__bot); window.__bot = setInterval(() => { const G = window.PA_G; if (G && G.overlay === 'choice') { const b = document.querySelector('[data-action=pick]'); if (b) b.click(); return; } if (!G || G.screen !== 'combat' || !G.combat || G.combat.status !== 'running' || G.paused) return; const inp = policy(PA, G.combat); const keys = new Set(); if (inp.mx > 0.3) keys.add('KeyD'); if (inp.mx < -0.3) keys.add('KeyA'); if (inp.my > 0.3) keys.add('KeyS'); if (inp.my < -0.3) keys.add('KeyW'); G.input.keys = keys; if (inp.dodge) G.input.pressed.add('Space'); if (inp.special) G.input.pressed.add('KeyQ'); if (G.run.growth.skills.e && G.combat.player.eCd <= 0 && G.combat.enemies.some(e => !e.dead && PA.m.dist(e, G.combat.player) < 220)) G.input.pressed.add('KeyE'); if (G.overlay === 'choice') { const b = document.querySelector('[data-action=pick]'); if (b) b.click(); } }, 40); })()`;
const BOT = BOT_POLICY; // 정책 봇(보스·일반 공통, E 사용 포함)
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1048, height: 688 } });
  await page.goto('file://' + path.join(ROOT, 'index.html') + q); await page.waitForTimeout(600);
  await page.evaluate(BOT);
  await page.evaluate(() => {
    const stream = document.querySelector('#game').captureStream(30);
    const rec = new MediaRecorder(stream, { mimeType: 'video/webm;codecs=vp8', videoBitsPerSecond: 2500000 });
    window.__chunks = []; rec.ondataavailable = (e) => { if (e.data.size) window.__chunks.push(e.data); };
    window.__rec = rec; rec.start(500);
  });
  const t0 = Date.now();
  while (Date.now() - t0 < SEC * 1000) { const s = await page.evaluate(() => PA_G.screen); if (s !== 'combat') break; await page.waitForTimeout(250); }
  const stats = await page.evaluate(() => PA_G.lastStats || (PA_G.combat && PA_G.combat.stats));
  const b64 = await page.evaluate(() => new Promise((res) => { const r = window.__rec; r.onstop = async () => { const blob = new Blob(window.__chunks, { type: 'video/webm' }); const buf = await blob.arrayBuffer(); let s = ''; const bytes = new Uint8Array(buf); for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000)); res(btoa(s)); }; r.stop(); }));
  await browser.close();
  const name = 'combat_' + (q.match(/scenario=(\w+)/) || [0, 'x'])[1] + '.webm';
  fs.writeFileSync(path.join(OUT, name), Buffer.from(b64, 'base64'));
  console.log('video', path.join(OUT, name), Math.round(fs.statSync(path.join(OUT, name)).size / 1024) + 'KB', 'stats', JSON.stringify(stats));
})().catch(e => { console.error(e); process.exit(1); });
