// 대표 전투 실제 브라우저 영상(봇 조작, 시험실 경로): 회전 칼날 초반(1일차 숲, Lv1) / 후반 일반전(심층 6일차 편성, 3단계 관문 빌드) / 보스전(예언을 먹는 자, 3단계 관문 빌드)
// 사용: NODE_PATH=<playwright> node tools/record_videos.js → docs/video/v08_blades_day1.webm, v08_late_deep6.webm, v08_boss_eater.webm
const path = require('path'), fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const url = 'file://' + path.join(ROOT, 'index.html'); const outDir = path.join(ROOT, 'docs', 'video');
const CLIPS = [
  ['v08_blades_day1', 'enemy=day:forest:1;hp=1.5,1.5,1;seed=3;build=start_blades;control=bot;bot=aware;growth=fixed;time=90;balance=test03', 95],
  ['v08_late_deep6', 'enemy=day:deep:6;hp=3,3.75,1;seed=3;build=stage3;control=bot;bot=balanced;growth=fixed;time=120;balance=test03', 125],
  ['v08_boss_eater', 'enemy=boss:eater;hp=1,1,1;seed=3;build=stage3;control=bot;bot=balanced;growth=fixed;time=180;balance=test03', 185],
];
(async () => {
  const browser = await chromium.launch(); const log = [];
  for (const [name, cfg, maxSec] of CLIPS) {
    const tmp = path.join(outDir, 'tmp_' + name); fs.mkdirSync(tmp, { recursive: true });
    const ctx = await browser.newContext({ viewport: { width: 1100, height: 760 }, recordVideo: { dir: tmp, size: { width: 1100, height: 760 } } }); const page = await ctx.newPage();
    await page.goto(url + '?lab=' + encodeURIComponent(cfg)); await page.waitForTimeout(500);
    const t0 = Date.now(); let s = null; while (Date.now() - t0 < maxSec * 1000) { s = await page.evaluate(() => ({ screen: PA_G.screen, t: PA_G.combat ? Math.round(PA_G.combat.t) : null, status: PA_G.combat ? PA_G.combat.status : null, label: PA_G.combat ? PA_G.combat.labText : null })); if (s.screen === 'lab_result') break; await page.waitForTimeout(1000); }
    await page.waitForTimeout(1500); const res = await page.evaluate(() => PA_G.labResult ? { status: PA_G.labResult.status, elapsed: PA_G.labResult.elapsed, taken: PA_G.labResult.damageTaken, kills: PA_G.labResult.kills } : null);
    await ctx.close(); const v = fs.readdirSync(tmp).find(f => f.endsWith('.webm')); fs.renameSync(path.join(tmp, v), path.join(outDir, name + '.webm')); fs.rmSync(tmp, { recursive: true, force: true });
    log.push(`${name}.webm — ${cfg} — 결과 ${JSON.stringify(res)}`); console.log(log[log.length - 1]);
  }
  await browser.close(); fs.writeFileSync(path.join(outDir, 'README.md'), `# 대표 전투 영상 (v0.8, 봇 조작, 시험실 경로)\n\n${log.map(l => '- ' + l).join('\n')}\n\n- v08_verify.webm: tools/verify_v08.js 전체 검증 세션 녹화(새 회차·상점·심층·패배·보스·통계·용어 사전).\n`);
})();
