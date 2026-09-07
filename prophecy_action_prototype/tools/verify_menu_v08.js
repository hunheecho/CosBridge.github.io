// 검증 메뉴(§7 테스트 묶음)와 배포 단일 HTML 핵심 흐름 확인. 사용: NODE_PATH=<playwright> node tools/verify_menu_v08.js → docs/verify_menu_v08_log.txt
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const results = []; const ok = (n, c, x) => { results.push([c ? 'PASS' : 'FAIL', n, x || '']); console.log((c ? 'PASS ' : 'FAIL ') + n + (x ? ' — ' + x : '')); };
(async () => {
  const browser = await chromium.launch();
  for (const [label, file] of [['index', 'index.html'], ['dist', 'dist/prophecy_single.html']]) {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } }); const errors = []; page.on('pageerror', e => errors.push(e.message)); page.on('dialog', d => { errors.push('dialog: ' + d.message()); d.dismiss(); });
    const url = 'file://' + path.join(ROOT, file); const ev = (fn) => page.evaluate(fn); const click = async (sel) => { await page.click(sel); await page.waitForTimeout(250); };
    await page.goto(url); await page.waitForTimeout(300); await ev(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(300);
    let s = await ev(() => ({ v: PA.VERSION, blades: PA.WEAPONS.blades.base.damage + '/' + PA.WEAPONS.blades.base.hitGap, title: document.querySelector('.subtitle').textContent })); ok(`${label} 버전 v0.8.0·회전 칼날 시험값 10/0.35`, s.v === '0.8.0' && s.blades === '10/0.35' && /v0\.8\.0/.test(s.title), JSON.stringify(s));
    // 검증 메뉴: 시작 기술 첫 전투(회전 칼날)
    await page.click('details.card summary'); await page.waitForTimeout(150); await click('[data-action=quick-lab][data-arg*="start_blades"]');
    s = await ev(() => ({ screen: PA_G.screen, build: PA_G.lab.cfg.build, enemy: PA_G.lab.cfg.enemy, bal: PA_G.lab.cfg.balance, text: document.querySelector('#ui').textContent })); ok(`${label} 검증 메뉴 → 시험실(회전 칼날 Lv1 · 1일차 숲 · test03)`, s.screen === 'lab' && s.build === 'start_blades' && s.enemy === 'day:forest:1' && s.bal === 'test03' && /시작 자동기술 3종/.test(s.text) && /v0\.8\.0/.test(s.text), JSON.stringify([s.screen, s.build, s.enemy, s.bal]));
    await click('[data-action=lab-start]'); await page.waitForTimeout(500); s = await ev(() => ({ screen: PA_G.screen, label: PA_G.combat.labText, spear: PA.WEAPONS.spear.base.interval, waves: PA_G.combat.waves.length, hp: PA_G.combat.hpMult.normal })); ok(`${label} 시험실 전투 시작(라벨에 버전·세트·빌드, test03 창 규칙 적용, 체력 ×1.5)`, s.screen === 'combat' && /v0\.8\.0/.test(s.label) && /시험 빌드/.test(s.label) && s.spear === 0.85 && s.hp === 1.5, JSON.stringify(s));
    await page.keyboard.press('Escape'); await page.waitForTimeout(200); await click('[data-action=lab-back]'); await click('[data-action=lab-exit]');
    // 3일차 성장 중단 최종 보스
    await page.click('details.card summary'); await page.waitForTimeout(150); await click('[data-action=quick-run][data-arg="3"]');
    s = await ev(() => ({ screen: PA_G.screen, day: PA_G.run.day, quick: PA_G.run.quick, lv: PA_G.run.growth.level, badge: /검증용 회차/.test(document.querySelector('.topbar').textContent), phase: PA_G.run.phase })); ok(`${label} 3일차 중단 최종 보스 입장 화면(검증용 표시)`, s.screen === 'base' && s.day === 7 && s.quick && s.badge && s.phase === 'boss_prep', JSON.stringify(s));
    await click('[data-action=boss-start]'); await page.waitForTimeout(500); s = await ev(() => ({ screen: PA_G.screen, boss: PA_G.combat.bossId, hp: PA_G.combat.boss.hpMax })); ok(`${label} 최종 보스 전투 시작(예언을 먹는 자 7000)`, s.screen === 'combat' && s.boss === 'eater' && s.hp === 7000, JSON.stringify(s));
    await page.keyboard.press('Escape'); await page.waitForTimeout(200); await click('[data-action=give-up]'); await page.waitForTimeout(2500); await click('[data-action=title]');
    // 상점 비교
    await page.click('details.card summary'); await page.waitForTimeout(150); await click('[data-action=quick-shop]'); s = await ev(() => ({ screen: PA_G.screen, gold: PA_G.run.gold, cards: document.querySelectorAll('.card.item').length, cmp: /현재 방어구|현재 무기|현재 방패/.test(document.querySelector('#ui').textContent) })); ok(`${label} 상점 구매·교체·장비 비교 화면(금화 400, 비교 표시)`, s.screen === 'shop' && s.gold === 400 && s.cards >= 2 && s.cmp, JSON.stringify(s));
    await click('[data-action=base]'); await click('[data-action=save-quit]');
    // 통계 화면
    await page.click('details.card summary'); await page.waitForTimeout(150); await click('[data-action=quick-stats]'); await page.waitForTimeout(500); s = await ev(() => ({ screen: PA_G.screen, combats: PA_G.run.dmgStats.combats.length, kind: PA_G.run.dmgStats.combats[0] && PA_G.run.dmgStats.combats[0].kind, panel: /피해 통계/.test(document.querySelector('#ui').textContent), verify: PA.Stats.verify(PA_G.run).every(v => v.ok), recorded: !localStorage.getItem(PA.Run.RECORDS_KEY) })); ok(`${label} 런 피해 통계 화면(봇 보스전 1회 실제 기록, 합계 검증, 기록 파일 미생성)`, s.combats === 1 && s.kind === 'boss' && s.panel && s.verify && s.recorded, JSON.stringify(s));
    await click('[data-action=save-quit]');
    // 정상 새 회차 핵심 흐름(배포 파일에서도): 새 회차 → 첫 전투 → 승리 → 귀환 → 저장·계속
    await click('[data-action=newrun]'); if (await page.$('[data-action=newrun-confirm]')) await click('[data-action=newrun-confirm]'); await click('[data-action=start-weapon][data-arg=sword]'); s = await ev(() => ({ quick: PA_G.run.quick, day: PA_G.run.day, gold: PA_G.run.gold })); ok(`${label} 정상 새 회차(검증 플래그 없음)`, !s.quick && s.day === 1 && s.gold === 60, JSON.stringify(s));
    await click('[data-action=mission][data-arg=d1c1]'); await page.waitForTimeout(400); await ev(() => { const c = PA_G.combat; for (const e of c.enemies) PA.Combat.damageEnemy(c, e, 99999, { src: { extra: true } }); c.pending = []; c.waveIndex = 99; c.spawnedAll = true; }); await page.waitForTimeout(500); for (let i = 0; i < 8; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(200); } await page.waitForTimeout(2500);
    await click('[data-action=after-reward]'); for (let i = 0; i < 8; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(200); } if ((await ev(() => PA_G.screen)) === 'event') await click('[data-action=event-choice][data-arg=leave]'); await click('[data-action=return]');
    await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]'); s = await ev(() => ({ screen: PA_G.screen, gold: PA_G.run.gold, combats: PA_G.run.dmgStats.combats.length, hours: PA_G.run.hours })); ok(`${label} 첫 전투 승리 → 귀환 정산 → 저장·계속`, s.screen === 'base' && s.gold > 60 && s.combats === 1 && s.hours === 4, JSON.stringify(s));
    ok(`${label} 페이지 오류 없음`, errors.length === 0, errors.join(' | ').slice(0, 300)); await page.close();
  }
  await browser.close(); fs.writeFileSync(path.join(ROOT, 'docs', 'verify_menu_v08_log.txt'), results.map(r => r.join(' | ')).join('\n') + '\n'); console.log(`${results.filter(r => r[0] === 'PASS').length}/${results.length} PASS`);
})();
