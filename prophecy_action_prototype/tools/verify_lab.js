// 전투 시험실 브라우저 검증(실제 키·클릭 입력). 봇 구간은 시험실의 '봇 조작' 옵션(게임 안 PA.Bot)을 쓴다.
// 사용: NODE_PATH=<playwright> node tools/verify_lab.js
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const OUT = path.join(ROOT, 'shots'); fs.mkdirSync(OUT, { recursive: true });
const url = (q) => 'file://' + path.join(ROOT, 'index.html') + (q || '');
const results = []; const ok = (name, cond, extra) => { results.push([cond ? 'PASS' : 'FAIL', name, extra || '']); console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? ' — ' + extra : '')); };
(async () => {
  const browser = await chromium.launch(); const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const st = () => page.evaluate(() => { const G = PA_G; return { screen: G.screen, overlay: G.overlay, paused: G.paused, scenario: G.scenario, blocked: G.input.blocked, keys: G.input.keys.size, combat: G.combat && { t: G.combat.t, status: G.combat.status, hpMult: G.combat.hpMult, labText: G.combat.labText, px: G.combat.player.x, py: G.combat.player.y, enemies: G.combat.enemies.filter(e => !e.dead).map(e => e.type + ':' + e.state) }, cfg: G.lab && G.lab.cfg && PA.Lab.encode(G.lab.cfg), result: G.labResult && { status: G.labResult.status, elapsed: G.labResult.elapsed }, save: !!localStorage.getItem('prophecy_action_save_v1'), labKey: !!localStorage.getItem('prophecy_action_lab_v1'), run: G.run && { layout: G.run.layout, day: G.run.day, lab: G.run.lab } }; });
  const click = async (sel) => { await page.click(sel); await page.waitForTimeout(200); };
  const waitFor = async (pred, ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const s = await st(); if (pred(s)) return s; await page.waitForTimeout(100); } return await st(); };
  await page.goto(url()); await page.waitForTimeout(400); await page.evaluate(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(400);
  // A. 진입·설정(실제 change 이벤트)
  await click('[data-action=lab]'); let s = await st(); ok('A1 제목 → 전투 시험실 화면', s.screen === 'lab');
  await page.selectOption('#lab-enemy', 'solo:boar'); await page.waitForTimeout(150); await page.selectOption('#lab-hp-normal', '3'); await page.waitForTimeout(150);
  await page.fill('#lab-seed', '7'); await page.dispatchEvent('#lab-seed', 'change'); await page.waitForTimeout(150);
  await page.selectOption('#lab-build', 'mid_melee'); await page.waitForTimeout(150); await page.check('input[name=lab-control][value=human]'); await page.waitForTimeout(150);
  s = await st(); ok('A2 화면에서 적·체력·시드·빌드 변경이 설정에 반영', /enemy=solo:boar/.test(s.cfg) && /hp=3,1,1/.test(s.cfg) && /seed=7/.test(s.cfg) && /build=mid_melee/.test(s.cfg) && /control=human/.test(s.cfg), s.cfg);
  ok('A3 빌드 설명에 실제 장착(검 Lv3 교차 검격·쌍검 출혈·넓어진 공격·숙련)과 선택 횟수 표시', await page.$eval('#ui', el => /검 Lv3 \[교차 검격\]/.test(el.textContent) && /쌍검 Lv2 \[출혈 칼날\]/.test(el.textContent) && /넓어진 공격/.test(el.textContent) && /약 8회/.test(el.textContent)));
  await page.screenshot({ path: path.join(OUT, 'vl_settings.png'), fullPage: true });
  // B. 직접 조작으로 시작 → 실제 키 이동 → 일시정지에 설정 표시 → 중단
  await click('[data-action=lab-start]'); s = await waitFor(x => x.screen === 'combat', 3000); ok('B1 시작 → 전투(체력 배율 3, 기둥 숲, 시험실 표시)', s.screen === 'combat' && s.combat.hpMult.normal === 3 && /멧돼지/.test(s.combat.labText) && s.scenario && s.scenario.lab);
  const bx = await page.evaluate(() => PA_G.combat.player.x); await page.keyboard.down('KeyD'); await page.waitForTimeout(400); await page.keyboard.up('KeyD'); s = await st(); ok('B2 실제 키(D)로 이동', s.combat.px > bx + 30, `${Math.round(bx)} → ${Math.round(s.combat.px)}`);
  const seen = await waitFor(x => x.combat && x.combat.enemies.some(e => /boar:charge_aim|boar:charge_lock/.test(e)), 8000); ok('B3 멧돼지 돌파 예고 관측', seen.combat && seen.combat.enemies.some(e => /boar:charge/.test(e)), seen.combat && seen.combat.enemies.join(','));
  await page.screenshot({ path: path.join(OUT, 'vl_boar_combat.png') });
  await page.keyboard.press('Escape'); await page.waitForTimeout(200); s = await st(); ok('B4 Esc 일시정지에 시험실 설정 표시', s.paused && await page.$eval('#overlay', el => /시험실 설정/.test(el.textContent) && /enemy=solo:boar/.test(el.textContent)));
  await page.screenshot({ path: path.join(OUT, 'vl_pause.png') });
  await click('[data-action=lab-abort]'); s = await st(); ok('B5 중단 → 결과 화면(사용자 중단)', s.screen === 'lab_result' && s.result.status === 'aborted');
  ok('B6 결과 화면에 몬스터 종류별 표·받은 피해·기여도·JSON·CSV', await page.$eval('#ui', el => /몬스터 종류별/.test(el.textContent) && /받은 피해 원인/.test(el.textContent) && /피해 기여도/.test(el.textContent) && /CSV 한 줄/.test(el.textContent) && el.querySelectorAll('textarea').length >= 2));
  // C. 같은 조건 재시작 / 체력 배율만 바꿔 재시작 / 설정 화면 복귀
  await click('[data-action=lab-restart]'); s = await waitFor(x => x.screen === 'combat', 3000); ok('C1 같은 조건으로 재시작(시드 7·체력 3 유지)', s.screen === 'combat' && s.combat.hpMult.normal === 3 && /seed=7/.test(s.cfg));
  await page.keyboard.press('Escape'); await page.waitForTimeout(150); await click('[data-action=lab-abort]');
  await page.selectOption('#lab-result-hp', '1'); await click('[data-action=lab-restart-hp]'); s = await waitFor(x => x.screen === 'combat', 3000); ok('C2 체력 배율만 ×1로 바꿔 재시작(빌드·시드 유지)', s.combat.hpMult.normal === 1 && /seed=7/.test(s.cfg) && /build=mid_melee/.test(s.cfg));
  await page.keyboard.press('Escape'); await page.waitForTimeout(150); await click('[data-action=lab-back]'); s = await st(); ok('C3 결과 없이 설정 화면으로', s.screen === 'lab' && !s.combat && !s.scenario);
  // D. 봇 조작으로 완주 → 결과 → 최근 결과 표 → 설정 복사/불러오기
  await page.selectOption('#lab-enemy', 'region:forest'); await page.waitForTimeout(120); await page.check('input[name=lab-control][value=bot]'); await page.waitForTimeout(120); await page.selectOption('#lab-bot', 'balanced'); await page.waitForTimeout(120); await page.selectOption('#lab-time', '60'); await page.waitForTimeout(120);
  await click('[data-action=lab-start]'); s = await waitFor(x => x.screen === 'lab_result', 70000); ok('D1 봇 조작 완주 → 결과', s.screen === 'lab_result' && ['won', 'lost', 'timeout'].includes(s.result.status), `${s.result.status} ${s.result.elapsed}s`);
  await page.screenshot({ path: path.join(OUT, 'vl_result.png'), fullPage: true });
  await click('[data-action=lab]'); ok('D2 최근 결과 표에 누적(4건)', await page.$eval('#ui', el => (el.textContent.match(/불러오기/g) || []).length >= 4));
  const text = await page.$eval('#lab-config', el => el.value); await page.fill('#lab-config', text.replace('hp=1,1,1', 'hp=6,2,1').replace('seed=7', 'seed=99')); await click('[data-action=lab-apply]'); s = await st(); ok('D3 설정 텍스트 적용(체력 6·시드 99)', /hp=6,2,1/.test(s.cfg) && /seed=99/.test(s.cfg));
  await page.reload(); await page.waitForTimeout(400); await click('[data-action=lab]'); s = await st(); ok('D4 새로고침 뒤 시험실 설정·결과 보존(별도 키), 정식 저장 없음', /seed=99/.test(s.cfg) && s.labKey && !s.save && await page.$eval('#ui', el => /불러오기/.test(el.textContent)));
  // E. 재현성(봇·같은 시드)
  const runOnce = async () => { await page.goto(url('?lab=' + encodeURIComponent('enemy=region:ridge;hp=2,2,1;seed=5;build=mid_ranged;control=bot;bot=balanced;time=60'))); const r = await waitFor(x => x.screen === 'lab_result', 70000); return page.evaluate(() => { const r = Object.assign({}, PA_G.labResult); delete r.at; return JSON.stringify(r); }); };
  const r1 = await runOnce(), r2 = await runOnce(); ok('E1 같은 설정·시드·봇 → 같은 결과(브라우저)', r1 === r2);
  // F. 신규 몬스터 8종 단독 시나리오가 주소로 열리고 예고 상태가 나타난다
  const want = { boar: /charge_aim/, shieldbearer: /bash_aim|approach/, shaman: /cast|hex_aim/, bomber: /fuse/, burrower: /under|warn/, spider: /web_aim/, frostcaller: /cast/, rogue: /slash1_aim/ };
  for (const t of Object.keys(want)) { await page.goto(url('?lab=' + encodeURIComponent(`enemy=solo:${t};hp=3,1,1;seed=2;build=early_sword;control=bot;bot=aggressive;time=60`))); const r = await waitFor(x => x.combat && x.combat.enemies.some(e => want[t].test(e)), 20000); ok(`F ${t} 단독 시나리오 예고 관측`, r.combat && r.combat.enemies.some(e => want[t].test(e)), r.combat ? r.combat.enemies.join(',') : r.screen); }
  // G. 작은 창에서 설정·결과 화면
  await page.setViewportSize({ width: 800, height: 500 }); await page.goto(url()); await page.waitForTimeout(300); await click('[data-action=lab]'); await page.screenshot({ path: path.join(OUT, 'vl_small_settings.png'), fullPage: true });
  await page.goto(url('?lab=' + encodeURIComponent('enemy=combo:late_mix;hp=2,2,1;seed=3;build=late_multi;control=bot;bot=balanced;time=30'))); await page.waitForTimeout(2500); await page.screenshot({ path: path.join(OUT, 'vl_small_combat.png') });
  s = await waitFor(x => x.screen === 'lab_result', 40000); await page.screenshot({ path: path.join(OUT, 'vl_small_result.png'), fullPage: true }); ok('G1 작은 창(800×500)에서 조합 전투·결과 화면 표시', s.screen === 'lab_result');
  await page.setViewportSize({ width: 1280, height: 900 });
  // H. 시험실 종료 → 정식 회차: 배율·입력·시나리오 플래그가 남지 않는다. 이전 저장(layout 없음)도 진행
  await click('[data-action=lab-exit]'); s = await st(); ok('H1 제목으로 복귀(회차·시나리오·입력 차단 없음)', s.screen === 'title' && !s.scenario && !s.blocked && s.keys === 0);
  await click('[data-action=newrun]'); await click('[data-action=start-weapon][data-arg=sword]'); await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); s = await waitFor(x => x.screen === 'combat', 3000);
  ok('H2 정식 출격: 시험실 배율·표시가 새지 않음(회차 설정의 배율만, 기존 배치)', (s.combat.hpMult.normal === 1 || s.combat.hpMult.normal === 1.5) && !/시험실/.test(s.combat.labText || '') && s.run.layout === 'classic' && !s.run.lab && s.save, JSON.stringify({ hp: s.combat.hpMult.normal, text: s.combat.labText }));
  await page.keyboard.down('KeyA'); await page.waitForTimeout(300); await page.keyboard.up('KeyA'); const s2 = await st(); ok('H3 정식 전투에서 실제 키 입력 동작', s2.combat.px < s.combat.px - 20);
  await page.evaluate(() => { const r = JSON.parse(localStorage.getItem('prophecy_action_save_v1')); delete r.layout; delete r.difficulty; localStorage.setItem('prophecy_action_save_v1', JSON.stringify(r)); });
  await page.reload(); await page.waitForTimeout(400); await click('[data-action=continue]'); s = await st(); ok('H4 배치 필드 없는 이전 저장도 거점 진행(기존 배치로)', s.screen === 'base' && s.run.layout === 'classic');
  await click('[data-action=map]'); ok('H5 지도에 지역 카드·기존 배치 적 목록', await page.$eval('#ui', el => /근교 숲/.test(el.textContent) && !/시험안 배치/.test(el.textContent)));
  // I. 시험안 배치·난이도 후보 선택 → 화면 표시
  await click('[data-action=base]'); await click('[data-action=save-quit]'); await click('[data-action=newrun]'); await click('[data-action=newrun-confirm]'); await page.selectOption('#start-layout', 'trial'); await page.selectOption('#start-difficulty', 'candA'); await click('[data-action=start-weapon][data-arg=spear]');
  ok('I1 시험안 배치·난이도 후보가 상단에 표시', await page.$eval('#ui', el => /시험안 배치/.test(el.textContent) && /후보 A/.test(el.textContent)));
  await click('[data-action=map]'); ok('I2 지도 카드에 시험안 적 목록·체력 배율 표시', await page.$eval('#ui', el => /멧돼지/.test(el.textContent) && /체력 ×1.5/.test(el.textContent)));
  await click('[data-action=sortie][data-arg=ridge]'); s = await waitFor(x => x.screen === 'combat', 3000); ok('I3 시험안 출격: 체력 배율 1.5, 전투 상단에 배치·난이도 표시', s.combat.hpMult.normal === 1.5 && /시험안/.test(s.combat.labText));
  await page.screenshot({ path: path.join(OUT, 'vl_trial_combat.png') });
  ok('오류 없음', errors.length === 0, errors.join(' / '));
  fs.writeFileSync(path.join(OUT, 'verify_lab_log.txt'), results.map(r => r.join(' | ')).join('\n'));
  await browser.close();
  const fails = results.filter(r => r[0] === 'FAIL').length; console.log(`\n${results.length - fails}/${results.length} PASS`); if (fails) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
