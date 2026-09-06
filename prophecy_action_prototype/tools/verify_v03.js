// v0.3 검증: 실제 입력·화면 전환·재실행 포함. (A) 출격 비용 저장, (B) 시험 모드 → 일반 회차 전환, 일시정지 실제 정지,
// 세 조합의 실제 발생, 시간 저축 UI 경로. 결과는 shots/verify_v03_log.txt 와 캡처로 남긴다.
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'shots'); fs.mkdirSync(OUT, { recursive: true });
const url = (q) => 'file://' + path.join(ROOT, 'index.html') + (q || '');
const BOT = fs.readFileSync(path.join(__dirname, 'playthrough.js'), 'utf8').match(/const BOT = `([\s\S]*?)`;/)[1];
const results = []; const ok = (name, cond, detail) => { results.push(`${cond ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`); console.log(results[results.length - 1]); };
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1048, height: 688 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const S = () => page.evaluate(() => ({ screen: PA_G.screen, scenario: !!PA_G.scenario, run: PA_G.run && { hours: PA_G.run.hours, day: PA_G.run.day, gold: PA_G.run.gold, augments: PA_G.run.augments }, combat: PA_G.combat && { t: PA_G.combat.t, status: PA_G.combat.status, field: !!PA_G.combat.field, chilled: PA_G.combat.enemies.filter(e => !e.dead && e.chill > 0).length, spinNow: PA_G.combat.effects.some(f => f.kind === 'spin'), enemiesInField: PA_G.combat.enemies.filter(e => !e.dead && PA.Combat.inField(PA_G.combat, e)).length, stasisMax: Math.max(0, ...PA_G.combat.enemies.map(e => e.stasis || 0)), cd: PA_G.combat.player.special.cd, kills: PA_G.combat.stats.kills, savingKills: PA_G.combat.stats.savingKills || 0 }, ev: PA_G.eventCounts, href: location.href }));
  const click = async (sel) => { await page.click(sel); await page.waitForTimeout(150); };
  const untilNotCombat = async (ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const s = await S(); if (s.screen !== 'combat') return s; await page.waitForTimeout(200); } return S(); };

  // ---- (A) 출격 비용 저장: 새 회차 → 근교 숲 출격 → 전투 중 새로고침 → 계속하기
  await page.goto(url()); await page.waitForTimeout(400); await page.evaluate(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(400);
  await click('[data-action=newrun]'); await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); await page.waitForTimeout(800);
  let s = await S(); ok('A0 출격 후 전투 화면·시간 4', s.screen === 'combat' && s.run.hours === 4, JSON.stringify(s.run));
  await page.reload(); await page.waitForTimeout(500);
  const cont = await page.$('[data-action=continue]'); ok('A1 새로고침 후 계속하기 버튼', !!cont);
  await cont.click(); await page.waitForTimeout(200); s = await S();
  ok('A 전투 중 종료 → 복구 시 출격 비용 지불 상태(4시간)', s.screen === 'base' && s.run.hours === 4, `screen=${s.screen} hours=${s.run.hours}`);
  // 심층 출격 저장: 승리 후 더 깊이 → 새로고침 → 시간 3(1+1 차감)... 근교 숲 승리까지 봇 진행
  await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); await page.evaluate(BOT); s = await untilNotCombat(120000);
  ok('A2 일반 출격 종료 화면', s.screen === 'reward' || s.screen === 'defeat', s.screen);
  if (s.screen === 'reward') {
    const pick = await page.$('[data-action=pick]'); if (pick) await pick.click(); else await click('[data-action=skip]'); await page.waitForTimeout(150);
    const augsBefore = (await S()).run.augments;
    const deep = await page.$('[data-action=deep]:not([disabled])'); ok('A3 더 깊이 버튼', !!deep);
    if (deep) { await deep.click(); await page.waitForTimeout(800); s = await S(); const hoursInDeep = s.run.hours; await page.reload(); await page.waitForTimeout(500); await click('[data-action=continue]'); s = await S(); ok('A4 심층 출격 중 종료 → 복구 시 추가 1시간도 차감됨 + 증강 선택 유지', s.run.hours === hoursInDeep && s.run.hours === 2 && JSON.stringify(s.run.augments) === JSON.stringify(augsBefore), `hours=${s.run.hours} augs=${JSON.stringify(s.run.augments)}`); }
  }

  // ---- 일시정지: 실제 Esc 입력으로 시뮬레이션 시간이 멈추는지
  await page.goto(url('?scenario=forest&seed=3')); await page.waitForTimeout(1200);
  await page.keyboard.press('Escape'); await page.waitForTimeout(150);
  const overlayShown = await page.evaluate(() => !document.querySelector('#overlay').hidden && !!document.querySelector('#vol'));
  const t1 = (await S()).combat.t; await page.waitForTimeout(1200); const t2 = (await S()).combat.t;
  await page.screenshot({ path: path.join(OUT, 'v03_pause.png') });
  await page.keyboard.press('Escape'); await page.waitForTimeout(600); const t3 = (await S()).combat.t;
  ok('일시정지: 오버레이·음량 표시, 1.2초 동안 t 정지, 재개 후 진행', overlayShown && t1 === t2 && t3 > t2 + 0.3, `t1=${t1.toFixed(2)} t2=${t2.toFixed(2)} t3=${t3.toFixed(2)}`);

  // ---- (B) 시험 모드 → 제목 → 새 회차 → 일반 출격이 정상 보상 화면으로
  await page.goto(url('?scenario=forest&seed=5')); await page.waitForTimeout(600); await page.evaluate(BOT); s = await untilNotCombat(120000);
  ok('B0 시험 전투 종료 화면', s.screen === 'scenario_end', s.screen);
  await click('[data-action=title]'); s = await S(); ok('B1 제목에서 시험 모드 해제·URL 정리', !s.scenario && !s.href.includes('scenario='), s.href);
  const nr = await page.$('[data-action=newrun]'); await nr.click(); await page.waitForTimeout(150); s = await S();
  if (s.screen === 'newrun_confirm') { await click('[data-action=newrun-confirm]'); s = await S(); }
  ok('B2 새 회차 거점', s.screen === 'base' && !s.scenario, s.screen);
  await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); await page.waitForTimeout(500);
  await page.reload(); await page.waitForTimeout(500); const c2 = await page.$('[data-action=continue]'); await c2.click(); await page.waitForTimeout(200); s = await S();
  ok('B3 새 회차의 출격이 저장됨(시험 모드 잔류로 저장 차단되지 않음)', s.run.hours === 4, `hours=${s.run.hours}`);
  await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); await page.evaluate(BOT); s = await untilNotCombat(120000);
  ok('B4 일반 출격이 보상/패배 화면으로 감(시험 종료 화면 아님)', s.screen === 'reward' || s.screen === 'defeat', s.screen);

  // ---- 조합 ① 감속장 + 회전 검격
  await page.goto(url('?scenario=forest&seed=11&aug=spin,wide')); await page.waitForTimeout(600); await page.evaluate(BOT);
  let seen = { spinInField: 0, maxInField: 0 };
  for (let i = 0; i < 300; i++) { s = await S(); if (s.screen !== 'combat') break; if (s.combat.field && s.combat.spinNow) { seen.spinInField++; if (seen.spinInField === 1) await page.screenshot({ path: path.join(OUT, 'v03_combo1_spin_field.png') }); } seen.maxInField = Math.max(seen.maxInField, s.combat.field ? s.combat.enemiesInField : 0); await page.waitForTimeout(80); }
  ok('① 감속장 안에서 회전 검격 발생', seen.spinInField > 0 && seen.maxInField >= 2, `spin-in-field frames=${seen.spinInField}, max enemies in field=${seen.maxInField}`);

  // ---- 조합 ② 관통검 + 얼음 파편
  await page.goto(url('?scenario=forest&seed=11&weapon=pierce&aug=frost')); await page.waitForTimeout(600); await page.evaluate(BOT);
  let maxChilled = 0, shotDone = false;
  for (let i = 0; i < 300; i++) { s = await S(); if (s.screen !== 'combat') break; maxChilled = Math.max(maxChilled, s.combat.chilled); if (s.combat.chilled >= 2 && !shotDone) { shotDone = true; await page.screenshot({ path: path.join(OUT, 'v03_combo2_pierce_frost.png') }); } await page.waitForTimeout(80); }
  s = await S(); ok('② 관통으로 동시 냉기 2마리 이상 + 냉기 처치 파편 발생', maxChilled >= 2 && (s.ev.shatter || 0) >= 1, `max chilled=${maxChilled}, shatter events=${s.ev.shatter || 0}`);

  // ---- 조합 ③ 잔불 걸음 + 불꽃 파열
  await page.goto(url('?scenario=forest&seed=11&aug=ember,flare')); await page.waitForTimeout(600); await page.evaluate(BOT);
  let flareShot = false;
  for (let i = 0; i < 300; i++) { s = await S(); if (s.screen !== 'combat') break; if ((s.ev.explode || 0) >= 1 && !flareShot) { flareShot = true; await page.screenshot({ path: path.join(OUT, 'v03_combo3_ember_flare.png') }); } await page.waitForTimeout(80); }
  s = await S(); ok('③ 회피 사용 → 불길 → 불길 위 처치 폭발 발생', (s.ev.explode || 0) >= 1 && (s.ev.dodge || 0) >= 1, `explode=${s.ev.explode || 0}, dodges=${s.ev.dodge || 0}`);

  // ---- 시간 저축 + 정지된 칼날: UI 경로(Q 키)로 감속장 안 처치 시 재사용 감소, 종료 폭발
  await page.goto(url('?scenario=forest&seed=11&aug=saving,stasis,spin')); await page.waitForTimeout(600); await page.evaluate(BOT);
  let stasisSeen = 0, cdDrop = false, lastCd = 0;
  for (let i = 0; i < 300; i++) { s = await S(); if (s.screen !== 'combat') break; stasisSeen = Math.max(stasisSeen, s.combat.stasisMax); if (stasisSeen >= 2 && s.combat.field && !cdDrop) { await page.screenshot({ path: path.join(OUT, 'v03_stasis_saving.png') }); cdDrop = true; } await page.waitForTimeout(80); }
  s = await S(); ok('시간 저축: 감속장 안 처치로 재사용 감소 이벤트(UI 경로) + 흔적 축적 관측', (s.ev.saving || 0) >= 1 && stasisSeen >= 1 && (s.combat.savingKills || 0) === (s.ev.saving || 0), `saving events=${s.ev.saving || 0}, savingKills=${s.combat.savingKills}, max stasis=${stasisSeen}, perfect=${s.ev.perfect || 0}`);

  ok('페이지 오류 없음', errors.length === 0, errors.join(' / '));
  fs.writeFileSync(path.join(OUT, 'verify_v03_log.txt'), results.join('\n'));
  await browser.close();
  if (results.some(r => r.startsWith('FAIL'))) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
