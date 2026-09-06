// 보스전·7일차 흐름 실제 브라우저 검증. 정책 봇(test/bot.js)은 페이지 안에서 PA_G.input에 입력을 넣는다(키보드 이벤트 경로는 별도 항목으로 검증).
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'shots'); fs.mkdirSync(OUT, { recursive: true });
const url = (q) => 'file://' + path.join(ROOT, 'index.html') + (q || '');
const POLICY_SRC = fs.readFileSync(path.join(ROOT, 'test', 'bot.js'), 'utf8').replace(/module\.exports[\s\S]*$/, '');
const BOT = `(() => { ${POLICY_SRC}; if (window.__bot) clearInterval(window.__bot); window.__bot = setInterval(() => { const G = window.PA_G; if (!G || G.screen !== 'combat' || !G.combat || G.combat.status !== 'running' || G.paused) return; const inp = policy(PA, G.combat); const keys = new Set(); if (inp.mx > 0.3) keys.add('KeyD'); if (inp.mx < -0.3) keys.add('KeyA'); if (inp.my > 0.3) keys.add('KeyS'); if (inp.my < -0.3) keys.add('KeyW'); G.input.keys = keys; if (inp.dodge) G.input.pressed.add('Space'); if (inp.special) G.input.pressed.add('KeyQ'); }, 40); })()`;
const results = []; const ok = (name, cond, extra) => { results.push([cond ? 'PASS' : 'FAIL', name, extra || '']); console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? ' — ' + extra : '')); };

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 860 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const state = () => page.evaluate(() => { const G = PA_G; return { screen: G.screen, phase: G.run && G.run.phase, day: G.run && G.run.day, gold: G.run && G.run.gold, acc: G.run && G.run.gear.acc, owned: G.run && G.run.owned, retries: G.run && G.run.bossRetries, clear: G.run && !!G.run.bossClear, combat: G.combat && { status: G.combat.status, mode: G.combat.mode, t: G.combat.t, bossHp: G.combat.boss && G.combat.boss.hp, phase: G.combat.boss && G.combat.boss.phase, hp: G.combat.player.hp, intro: G.combat.intro } }; });
  const click = async (sel) => { await page.click(sel); await page.waitForTimeout(150); };
  const waitCombatEnd = async (ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const s = await state(); if (s.screen !== 'combat') return s; await page.waitForTimeout(250); } return await state(); };

  // ---- A. 정상 회차: 1일차 → 6일차 종료 안내 → 7일차 최종 준비 ----
  await page.goto(url()); await page.waitForTimeout(400); await page.evaluate(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(400);
  await click('[data-action=newrun]');
  ok('A1 거점에 보스 카드(이름·도래일·정보) 표시', await page.$eval('.card.boss', el => /가시갈기/.test(el.textContent) && /6일 뒤/.test(el.textContent)));
  // 실제 플레이 대신 상점 재화만 부여(장비 교체 UI 검증용). 빌드는 시험 빌드로 표시
  await page.evaluate(() => { const r = PA_G.run; r.gold = 900; r.mats.pelt = 5; r.mats.iron = 4; r.mats.spore = 2; r.mats.fang = 1; PA.Run.save(r); });
  for (let d = 1; d < 6; d++) { await click('[data-action=endday-confirm]'); await click('[data-action=endday]'); }
  let s = await state(); ok('A2 6일차 도달', s.day === 6 && s.phase === 'prep');
  await click('[data-action=endday-confirm]');
  ok('A3 6일차 종료 확인에 "내일 보스 도래" 안내', await page.$eval('#ui', el => /내일 가시갈기가 도래/.test(el.textContent)));
  await page.screenshot({ path: path.join(OUT, 'v05_day6_notice.png') });
  await click('[data-action=endday]'); s = await state();
  ok('A4 7일차 = 최종 준비(boss_prep)', s.day === 7 && s.phase === 'boss_prep' && await page.$eval('#ui', el => /최종 준비/.test(el.textContent)));
  await page.screenshot({ path: path.join(OUT, 'v05_final_prep.png') });
  ok('A5 최종 준비 화면에 출격(지도) 버튼 없음', (await page.$$('[data-action=map]')).length === 0);
  await page.evaluate(() => { document.querySelector('#ui').innerHTML = PA.Screens.map(PA_G); });
  ok('A5b 지도 화면을 강제로 열어도 출격 버튼 잠김', await page.$$eval('[data-action=sortie]', bs => bs.length > 0 && bs.every(b => b.disabled && /출격 종료/.test(b.textContent))));
  await click('[data-action=base]'); ok('A6 지도에서 돌아와도 최종 준비', await page.$eval('#ui', el => /최종 준비/.test(el.textContent)));
  await click('[data-action=shop]'); await click('[data-action=base]'); ok('A7 상점에서 돌아와도 최종 준비(우회 경로 없음)', await page.$eval('#ui', el => /최종 준비/.test(el.textContent)) && (await page.$$('[data-action=map]')).length === 0);
  // ---- B. 상점 구매·장신구 재장착 ----
  await click('[data-action=shop]'); await click('[data-action=buy][data-arg=time_charm]'); await click('[data-action=buy][data-arg=fang_necklace]'); await click('[data-action=buy][data-arg=pierce_sword]');
  await click('[data-action=base]'); s = await state();
  ok('B1 마지막 구매(목걸이) 장착, 부적 보유', s.acc === 'fang_necklace' && s.owned.includes('time_charm'));
  const goldBefore = s.gold;
  await click('[data-action=equip][data-arg=time_charm]'); s = await state();
  ok('B2 먼저 산 장신구로 교체(추가 비용 없음)', s.acc === 'time_charm' && s.gold === goldBefore);
  await click('[data-action=equip][data-arg=fang_necklace]'); s = await state(); ok('B3 다시 목걸이로', s.acc === 'fang_necklace');
  await page.screenshot({ path: path.join(OUT, 'v05_gear_swap.png') });
  // ---- C. 보스 입장 → 실제 키 입력 검증 → 봇 진행 → 승리 ----
  await page.evaluate(() => { const r = PA_G.run; r.augments = { spin: 1, stasis: 1, saving: 1, sharp: 2, frost: 1 }; r.gear.upgrade = 2; PA.Run.save(r); });
  await click('[data-action=boss-start]'); await page.waitForTimeout(300); s = await state();
  ok('C1 입장 연출 중(피해·행동 없음)', s.screen === 'combat' && s.combat.mode === 'boss' && s.combat.intro > 0 && s.combat.hp === 100);
  await page.screenshot({ path: path.join(OUT, 'v05_boss_intro.png') });
  await page.waitForTimeout(1800);
  // 실제 키보드: 이동·회피·Q
  const before = await page.evaluate(() => ({ x: PA_G.combat.player.x, cd: PA_G.combat.player.special.cd }));
  await page.keyboard.down('KeyA'); await page.waitForTimeout(300); await page.keyboard.up('KeyA');
  await page.keyboard.press('Space'); await page.waitForTimeout(80);
  const mid = await page.evaluate(() => ({ x: PA_G.combat.player.x, dodge: PA_G.combat.player.dodge.active || PA_G.combat.player.dodge.cd > 0 }));
  await page.keyboard.press('KeyQ'); await page.waitForTimeout(120);
  const after = await page.evaluate(() => ({ field: !!PA_G.combat.field, cd: PA_G.combat.player.special.cd, uses: PA_G.combat.stats.specialUses }));
  ok('C2 실제 키보드: A 이동·Space 회피·Q 감속장', mid.x < before.x - 30 && mid.dodge && after.field && after.uses === 1);
  // Esc 정지 → 정지 중 Q/Space → 재개
  await page.keyboard.press('Escape'); await page.waitForTimeout(150);
  const t1 = await page.evaluate(() => PA_G.combat.t); await page.keyboard.press('KeyQ'); await page.keyboard.press('Space'); await page.waitForTimeout(600);
  const t2 = await page.evaluate(() => PA_G.combat.t);
  ok('C3 Esc 정지: 시뮬레이션 정지', t2 === t1 && await page.evaluate(() => PA_G.paused));
  await page.keyboard.press('Escape'); await page.waitForTimeout(200);
  const afterResume = await page.evaluate(() => ({ uses: PA_G.combat.stats.specialUses, dodgeT: PA_G.combat.player.dodge.t, t: PA_G.combat.t }));
  ok('C4 재개 직후 정지 중 입력이 발동하지 않음', afterResume.uses === 1 && afterResume.t > t2);
  // 포커스 이탈·복귀
  await page.evaluate(() => window.dispatchEvent(new Event('blur'))); await page.waitForTimeout(100);
  ok('C5 포커스 이탈 시 자동 정지', await page.evaluate(() => PA_G.paused));
  await page.keyboard.press('Escape'); await page.waitForTimeout(100); ok('C6 복귀 후 재개', await page.evaluate(() => !PA_G.paused));
  // 창 크기 변경: 규칙 불변
  await page.setViewportSize({ width: 900, height: 600 }); await page.waitForTimeout(200);
  ok('C7 창 크기 변경 후 전장·장애물 동일', await page.evaluate(() => PA_G.combat.arena.w === 960 && PA_G.combat.obstacles.length === 4));
  await page.setViewportSize({ width: 1280, height: 860 });
  // 봇 진행 + 상태 캡처
  await page.evaluate(BOT);
  const seen = new Set(); const t0 = Date.now(); let phaseSeen = new Set();
  while (Date.now() - t0 < 240000) {
    const st = await page.evaluate(() => { const c = PA_G.combat; return c && c.boss ? { screen: PA_G.screen, state: c.boss.state, phase: c.boss.phase, orbs: c.pickups.length, wolves: c.enemies.filter(e => e.summoned && !e.dead).length, field: !!c.field } : { screen: PA_G.screen }; });
    if (st.screen !== 'combat') break;
    phaseSeen.add(st.phase);
    const key = st.state + (st.phase >= 3 && st.state === 'dash_aim' ? '_p3' : '');
    if (!seen.has(key) && ['dash_lock', 'sweep_lock', 'howl', 'pounce_lock', 'leap', 'recover', 'roar', 'dash_aim_p3'].includes(key)) { seen.add(key); await page.screenshot({ path: path.join(OUT, `v05_boss_${key}.png`) }); }
    if (st.orbs > 0 && !seen.has('orb')) { seen.add('orb'); await page.screenshot({ path: path.join(OUT, 'v05_boss_orb.png') }); }
    await page.waitForTimeout(60);
  }
  s = await state();
  ok('C8 봇이 보스전을 끝냄', s.screen === 'boss_victory' || s.screen === 'boss_defeat', `${s.screen} 단계 ${[...phaseSeen].join('/')} 상태 ${[...seen].join(',')}`);
  await page.screenshot({ path: path.join(OUT, 'v05_boss_result.png') });
  const won = s.screen === 'boss_victory';
  ok('C9 승리 화면 문구·기록 저장', !won || (await page.$eval('#ui', el => /예언의 날을 넘겼다/.test(el.textContent) && /처치/.test(el.textContent)) && s.phase === 'cleared' && s.clear && await page.evaluate(() => !!PA.Run.loadRecords().firstClear)));
  // ---- D. 재도전·전투 중 종료·복구·재화 복제 없음 ----
  const goldPre = s.gold, ownedPre = s.owned.length;
  await click('[data-action=boss-start]'); await page.waitForTimeout(2200); await page.evaluate(BOT); await page.waitForTimeout(3000);
  await page.reload(); await page.waitForTimeout(400);
  await click('[data-action=continue]'); s = await state();
  ok('D1 전투 중 새로고침 → 보스 직전(최종 준비) 상태로 복구', s.screen === 'base' && (s.phase === 'boss_prep' || s.phase === 'cleared') && await page.$eval('#ui', el => /보스/.test(el.textContent)));
  ok('D2 재실행으로 재화·장비 복제 없음', s.gold === goldPre && s.owned.length === ownedPre);
  // 패배 경로: 체력 1로 시작해 패배 → 재도전 버튼 → 같은 빌드
  await click('[data-action=boss-start]'); await page.waitForTimeout(1900);
  await page.evaluate(() => { PA_G.combat.player.hp = 1; }); await page.waitForTimeout(100);
  await page.evaluate(() => { const c = PA_G.combat; PA.Combat.damagePlayer(c, 50, 'test'); });
  s = await waitCombatEnd(8000);
  ok('D3 패배 화면(재도전·최종 준비·제목)', s.screen === 'boss_defeat' && await page.$$eval('[data-action=boss-start],[data-action=base],[data-action=title]', bs => bs.length === 3));
  await page.screenshot({ path: path.join(OUT, 'v05_boss_defeat.png') });
  const retriesBefore = s.retries;
  await click('[data-action=boss-start]'); await page.waitForTimeout(300); s = await state();
  ok('D4 같은 준비로 재도전: 체력·보스 초기화, 재도전 횟수 기록', s.combat.mode === 'boss' && s.combat.hp === 100 && s.combat.bossHp === 2400 && retriesBefore >= 1);
  await page.keyboard.press('Escape'); await click('[data-action=give-up]'); await waitCombatEnd(8000);
  // ---- E. v1(7일차 ended) 저장 마이그레이션 ----
  await page.evaluate(() => { const old = PA.Run.newRun(3); old.version = 1; delete old.phase; delete old.bossRetries; delete old.bossClear; old.day = 7; old.ended = true; old.gold = 123; old.augments = { saving: 1 }; localStorage.setItem(PA.Run.SAVE_KEY, JSON.stringify(old)); });
  await page.reload(); await page.waitForTimeout(400); await click('[data-action=continue]'); s = await state();
  ok('E1 v1 7일차 ended 저장 → 보스 준비로 복구', s.phase === 'boss_prep' && s.day === 7 && s.gold === 123 && await page.$eval('#ui', el => /최종 준비/.test(el.textContent)));
  await page.evaluate(() => { const old = PA.Run.newRun(4); old.version = 1; delete old.phase; old.day = 3; old.ended = false; localStorage.setItem(PA.Run.SAVE_KEY, JSON.stringify(old)); });
  await page.reload(); await page.waitForTimeout(400); await click('[data-action=continue]'); s = await state();
  ok('E2 v1 준비 기간 저장 그대로 이어짐', s.phase === 'prep' && s.day === 3 && await page.$eval('#ui', el => /출격/.test(el.textContent)));
  // ---- F. 보스 시험 링크 ----
  await page.goto(url('?scenario=boss&seed=5&weapon=pierce&aug=frost,quick&upgrade=1')); await page.waitForTimeout(500); s = await state();
  ok('F1 ?scenario=boss 로 바로 보스전', s.screen === 'combat' && s.combat.mode === 'boss');
  ok('오류 없음', errors.length === 0, errors.join(' / '));
  fs.writeFileSync(path.join(OUT, 'verify_boss_log.txt'), results.map(r => r.join(' | ')).join('\n'));
  await browser.close();
  const fails = results.filter(r => r[0] === 'FAIL').length; console.log(`\n${results.length - fails}/${results.length} 통과`); if (fails) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
