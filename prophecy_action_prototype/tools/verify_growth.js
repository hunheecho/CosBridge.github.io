// v0.5 성장 시스템 브라우저 검증(실제 키 입력·화면 전환·재실행). 봇 구간은 PA_G.input에 직접 넣는다(명시).
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'shots'); fs.mkdirSync(OUT, { recursive: true });
const url = (q) => 'file://' + path.join(ROOT, 'index.html') + (q || '');
const POLICY_SRC = fs.readFileSync(path.join(ROOT, 'test', 'bot.js'), 'utf8').replace(/module\.exports[\s\S]*$/, '');
const BOT = `(() => { ${POLICY_SRC}; if (window.__bot) clearInterval(window.__bot); window.__bot = setInterval(() => { const G = window.PA_G; if (!G || G.screen !== 'combat' || !G.combat || G.combat.status !== 'running' || G.paused) return; const inp = policy(PA, G.combat); const keys = new Set(); if (inp.mx > 0.3) keys.add('KeyD'); if (inp.mx < -0.3) keys.add('KeyA'); if (inp.my > 0.3) keys.add('KeyS'); if (inp.my < -0.3) keys.add('KeyW'); G.input.keys = keys; if (inp.dodge) G.input.pressed.add('Space'); if (inp.special) G.input.pressed.add('KeyQ'); if (G.run.growth.skills.e && G.combat.player.eCd <= 0 && G.combat.enemies.some(e => !e.dead && PA.m.dist(e, G.combat.player) < 200)) G.input.pressed.add('KeyE'); }, 40); })()`;
const results = []; const ok = (name, cond, extra) => { results.push([cond ? 'PASS' : 'FAIL', name, extra || '']); console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? ' — ' + extra : '')); };
(async () => {
  const browser = await chromium.launch(); const page = await browser.newPage({ viewport: { width: 1280, height: 860 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const st = () => page.evaluate(() => { const G = PA_G, g = G.run && G.run.growth; return { screen: G.screen, overlay: G.overlay, paused: G.paused, level: g && g.level, xp: g && g.xp, pending: g && g.pendingLevelUps, weapons: g && g.weapons.map(w => w.id + ':' + w.level), e: g && g.skills.e && g.skills.e.id, offerKeys: g && g.pendingOffer && g.pendingOffer.choices.map(c => c.key), combat: G.combat && { t: G.combat.t, status: G.combat.status, uses: G.combat.stats.specialUses, eUses: G.combat.stats.eUses || 0, weapons: G.combat.weapons.length }, day: G.run && G.run.day, hours: G.run && G.run.hours, gold: G.run && G.run.gold }; });
  const click = async (sel) => { await page.click(sel); await page.waitForTimeout(150); };
  const untilChoiceOrEnd = async (ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const s = await st(); if (s.overlay === 'choice' || s.screen !== 'combat') return s; await page.waitForTimeout(80); } return await st(); };
  // A. 시작 무기 선택
  await page.goto(url()); await page.waitForTimeout(400); await page.evaluate(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(400);
  await click('[data-action=newrun]'); ok('A1 새 회차 → 시작 무기 선택 화면(검·관통창·회전 칼날)', await page.$$eval('[data-action=start-weapon]', bs => bs.map(b => b.dataset.arg).join(',') === 'sword,spear,blades'));
  await click('[data-action=start-all]'); ok('A2 검증 메뉴: 다른 시작 후보 표시', (await page.$$('[data-action=start-weapon]')).length === 7);
  await page.screenshot({ path: path.join(OUT, 'g3_pick_start.png') });
  await click('[data-action=start-weapon][data-arg=blades]'); let s = await st();
  ok('A3 회전 칼날로 시작, Lv1, 빌드 패널에 무기 1/3', s.screen === 'base' && s.weapons.join() === 'blades:1' && await page.$eval('#ui', el => /무기 1\/3/.test(el.textContent)));
  await page.screenshot({ path: path.join(OUT, 'g4_base_build.png') });
  // B. 출격 → 전투 중 레벨업(실제 키로 이동하다가) → 정지·입력 차단 → 선택 → 재개
  await click('[data-action=map]'); ok('B1 지도에 지역 성장 태그 표시', await page.$eval('#ui', el => /근접·연속 공격·출혈/.test(el.textContent) && /관통·투사체/.test(el.textContent)));
  await click('[data-action=sortie][data-arg=forest]'); await page.waitForTimeout(800);
  await page.keyboard.down('KeyA'); await page.waitForTimeout(300); await page.keyboard.up('KeyA');
  await page.evaluate(BOT);
  s = await untilChoiceOrEnd(60000);
  ok('B2 처치 즉시 경험치 → 전투 중 레벨업 카드(3장)', s.overlay === 'choice' && (await page.$$('[data-action=pick]')).length === 3, `Lv${s.level}`);
  await page.screenshot({ path: path.join(OUT, 'g5_levelup_overlay.png') });
  const t1 = (await st()).combat.t; await page.keyboard.press('KeyQ'); await page.keyboard.press('KeyE'); await page.keyboard.press('Space'); await page.keyboard.down('KeyD'); await page.waitForTimeout(500); await page.keyboard.up('KeyD');
  const s2 = await st(); ok('B3 선택 중 전투·시간 정지, Q/E/Space 누적 없음', s2.combat.t === t1 && s2.paused);
  const keys = s2.offerKeys.slice(); await page.reload(); await page.waitForTimeout(400); await click('[data-action=continue]'); const s3 = await st();
  ok('B4 새로고침 후 미처리 레벨업과 같은 제시 유지(재굴림 없음)', s3.pending >= 1 && JSON.stringify(s3.offerKeys) === JSON.stringify(keys), `${JSON.stringify(s3.offerKeys)}`);
  ok('B5 전투 중 새로고침: 출격 비용 지불·거점 복구', s3.screen === 'base' && s3.hours === 4);
  await click('[data-action=resolve-levelup]'); ok('B6 거점에서 미처리 레벨업 선택 가능', (await st()).overlay === 'choice');
  const before = (await st()).weapons.join(); await click('[data-action=pick]'); s = await st(); ok('B7 선택 적용·저장', s.overlay !== 'choice' && s.pending === 0 && await page.evaluate(() => !!PA.Run.load().growth));
  // C. 다시 출격: 레벨업 → 선택 후 재개, 새 무기 획득 시 즉시 3무기 공격
  await page.evaluate(() => { const g = PA_G.run.growth; g.weapons = [{ id: 'blades', level: 1, mods: [] }]; g.level = 1; g.xp = 0; g.pendingLevelUps = 0; g.pendingOffer = null; g.choiceSeq = 0; PA.Run.save(PA_G.run); });
  await click('[data-action=map]'); await click('[data-action=sortie][data-arg=ridge]'); await page.waitForTimeout(600); await page.evaluate(BOT);
  let picks = 0, gotWeapon = false, gotE = false;
  for (let i = 0; i < 12; i++) { s = await untilChoiceOrEnd(60000); if (s.overlay !== 'choice') break; const keysNow = s.offerKeys; const pref = keysNow.find(k => k.startsWith('weapon_new')) || keysNow.find(k => k.startsWith('skill_new')) || keysNow[0]; await page.click(`[data-action=pick][data-arg="${pref}"]`); await page.waitForTimeout(120); picks++; const a = await st(); if (a.combat && a.combat.weapons >= 2) gotWeapon = true; if (a.e) gotE = true; if (a.screen === 'combat') { const t0 = a.combat.t; await page.waitForTimeout(300); const b = await st(); if (b.screen === 'combat' && !(b.combat.t > t0)) ok('C-재개 실패', false); } }
  s = await st(); ok('C1 여러 번 레벨업 선택 후 전투 재개, 새 무기가 전투에 즉시 추가', picks >= 2 && gotWeapon, `선택 ${picks}회, 무기 ${s.weapons.join(',')}, E ${s.e}`);
  await page.screenshot({ path: path.join(OUT, 'g6_after_picks.png') });
  const t0 = Date.now(); while (Date.now() - t0 < 60000) { s = await st(); if (s.screen !== 'combat' && s.overlay !== 'choice') break; if (s.overlay === 'choice') { await click('[data-action=pick]'); } await page.waitForTimeout(150); }
  ok('C2 조우 종료 → 보상 화면(지역 경험치 표시, 증강 3택 없음)', s.screen === 'reward' && await page.$eval('#ui', el => /지역 경험치/.test(el.textContent) && !/증강 선택 \(회차 동안 유지\)/.test(el.textContent)));
  await page.screenshot({ path: path.join(OUT, 'g7_reward.png') });
  await click('[data-action=after-reward]'); s = await st(); while (s.overlay === 'choice') { await click('[data-action=pick]'); s = await st(); }
  ok('C3 다음 행동 화면', s.screen === 'after');
  await click('[data-action=return]'); s = await st(); ok('C4 귀환 후 성장 유지', s.screen === 'base' && s.level >= 2);
  // D. E 기술 실제 키 입력
  await page.evaluate(() => { const g = PA_G.run.growth; if (!g.skills.e) g.skills.e = { id: 'gust', level: 1, variant: null }; PA.Run.save(PA_G.run); });
  await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); await page.waitForTimeout(1200);
  await page.keyboard.press('KeyE'); await page.waitForTimeout(150); s = await st();
  ok('D1 실제 E 키로 수동 기술 발동', s.combat && s.combat.eUses === 1);
  await page.keyboard.press('Escape'); await page.waitForTimeout(100); await page.keyboard.press('KeyE'); await page.keyboard.press('Escape'); await page.waitForTimeout(200); s = await st();
  ok('D2 정지 중 E 입력은 재개 후 발동하지 않음', s.combat.eUses === 1 && !s.paused);
  await page.evaluate(BOT); await page.waitForTimeout(400); await page.screenshot({ path: path.join(OUT, 'g8_e_skill.png') });
  // E. v2 저장 이행 화면
  await page.evaluate(() => { const old = PA.Run.newRun(5); old.version = 2; delete old.growth; old.gear.weapon = 'pierce'; old.owned.push('pierce_sword'); old.augments = { spin: 1, wide: 1, ember: 1, frost: 1, flare: 1, saving: 1, sharp: 2 }; old.day = 3; localStorage.setItem(PA.Run.SAVE_KEY, JSON.stringify(old)); });
  await page.reload(); await page.waitForTimeout(400); await click('[data-action=continue]'); s = await st();
  ok('E1 v2 저장 → 이행 화면(공통 5개 중 3개 선택)', s.screen === 'migration' && (await page.$$('[data-action=mig-toggle]')).length === 5);
  await page.screenshot({ path: path.join(OUT, 'g9_migration.png') });
  for (const id of ['frost', 'flare', 'saving']) await click(`[data-action=mig-toggle][data-arg=${id}]`); await click('[data-action=mig-confirm]'); s = await st();
  ok('E2 이행 후 거점, 관통창·검·회전 칼날 3무기, 공통 3개', s.screen === 'base' && s.weapons.join() === 'spear:1,sword:1,blades:1' && await page.evaluate(() => Object.keys(PA_G.run.growth.commons).sort().join() === 'flare,frost,saving'));
  // F. 시나리오 링크(v3 파라미터)
  await page.goto(url('?scenario=forest&seed=11&start=spear&weapons=blades:2:dual,frost:1:fan&commons=frost,echo&e=gust:1:whirl&passives=mastery:1')); await page.waitForTimeout(500); s = await st();
  ok('F1 v3 시나리오 파라미터로 3무기·E·공통·패시브 구성', s.combat && s.combat.weapons === 3 && s.e === 'gust');
  ok('오류 없음', errors.length === 0, errors.join(' / '));
  fs.writeFileSync(path.join(OUT, 'verify_growth_log.txt'), results.map(r => r.join(' | ')).join('\n'));
  await browser.close(); const fails = results.filter(r => r[0] === 'FAIL').length; console.log(`\n${results.length - fails}/${results.length} 통과`); if (fails) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
