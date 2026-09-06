// 실제 움직이는 전투 녹화(webm) + 프레임 시트. 사용: NODE_PATH=<playwright> node tools/record.js [scenario query] [seconds]
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'docs', 'video'); fs.mkdirSync(OUT, { recursive: true });
const q = process.argv[2] || '?scenario=forest&seed=11'; const SEC = parseInt(process.argv[3] || '30', 10);
const BOT = fs.readFileSync(path.join(__dirname, 'playthrough.js'), 'utf8').match(/const BOT = `([\s\S]*?)`;/)[1];
(async () => {
  const size = { width: 1048, height: 688 };
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: size, recordVideo: { dir: OUT, size } });
  const page = await ctx.newPage();
  await page.goto('file://' + path.join(ROOT, 'index.html') + q); await page.waitForTimeout(600);
  await page.evaluate(BOT);
  const t0 = Date.now();
  while (Date.now() - t0 < SEC * 1000) { const s = await page.evaluate(() => PA_G.screen); if (s !== 'combat') break; await page.waitForTimeout(250); }
  const stats = await page.evaluate(() => PA_G.lastStats || (PA_G.combat && PA_G.combat.stats));
  await page.waitForTimeout(800);
  const video = page.video(); await ctx.close();
  const tmp = await video.path();
  const name = 'combat_' + (q.match(/scenario=(\w+)/) || [0, 'x'])[1] + '.webm';
  fs.renameSync(tmp, path.join(OUT, name));
  console.log('video', path.join(OUT, name), 'stats', JSON.stringify(stats));
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
