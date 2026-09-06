// 실제 화면 캡처 도구(개발용). file:// 로 열어 사용자의 실행 경로와 동일하게 검증한다.
// 사용: NODE_PATH=<playwright 위치> node tools/shots.js [출력폴더]
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..');
const OUT = process.argv[2] || path.join(ROOT, 'shots');
fs.mkdirSync(OUT, { recursive: true });
const url = (q) => 'file://' + path.join(ROOT, 'index.html') + (q || '');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); }); // 웹폰트 등 외부 리소스 실패는 무시
  const shot = async (name) => { await page.screenshot({ path: path.join(OUT, name + '.png') }); console.log('shot', name); };
  const holdKeys = async (codes, ms) => { for (const c of codes) await page.keyboard.down(c); await page.waitForTimeout(ms); for (const c of codes) await page.keyboard.up(c); };

  // 1) 제목 → 새 회차 → 거점
  await page.goto(url()); await page.waitForTimeout(500); await shot('01_title');
  await page.click('[data-action=newrun]'); await page.waitForTimeout(300); await shot('02_base');
  await page.click('[data-action=map]'); await page.waitForTimeout(300); await shot('03_map');
  await page.click('[data-action=base]'); await page.waitForTimeout(200); await page.click('[data-action=shop]'); await page.waitForTimeout(300); await shot('04_shop');
  await page.click('[data-action=base]'); await page.waitForTimeout(200);
  // 2) 출격: 근교 숲
  await page.click('[data-action=map]'); await page.waitForTimeout(200);
  await page.click('[data-action=sortie][data-arg=forest]'); await page.waitForTimeout(1500); await shot('05_combat_forest_start');
  await holdKeys(['KeyA'], 600); await page.waitForTimeout(900); await shot('06_combat_forest_telegraph');
  // 조우가 끝날 때까지 회피·이동 반복 (단순 봇: 좌우 왕복 + 주기적 회피)
  for (let i = 0; i < 40; i++) {
    const st = await page.evaluate(() => ({ s: PA_G.combat && PA_G.combat.status, screen: PA_G.screen }));
    if (st.screen !== 'combat' || st.s !== 'running') break;
    await holdKeys([i % 2 ? 'KeyA' : 'KeyD'], 350); await page.keyboard.press('Space'); await page.waitForTimeout(300);
    if (i === 6) await page.keyboard.press('KeyQ');
    if (i === 8) await shot('07_combat_forest_mid');
  }
  await page.waitForTimeout(1800); await shot('08_reward');
  const pick = await page.$('[data-action=pick]'); if (pick) await pick.click(); await page.waitForTimeout(300); await shot('09_after');
  const ret = await page.$('[data-action=return]'); if (ret) await ret.click(); await page.waitForTimeout(300); await shot('10_base_after');
  // 3) 일시정지 화면과 시나리오 모드(늑대 굴, 관통검+회전 검격)
  await page.goto(url('?scenario=den&seed=5&weapon=pierce&aug=spin,ember,mark')); await page.waitForTimeout(1600);
  await holdKeys(['KeyW'], 500); await page.waitForTimeout(700); await shot('11_scenario_den');
  await page.keyboard.press('Escape'); await page.waitForTimeout(200); await shot('12_pause');
  await page.keyboard.press('Escape'); await page.waitForTimeout(100);
  await page.setViewportSize({ width: 800, height: 500 }); await page.waitForTimeout(300); await shot('13_small_window');
  console.log('errors:', errors.length ? errors : 'none');
  await browser.close();
  if (errors.length) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
