// v0.8 빠른 연기 테스트(브라우저): 새 회차 → 거점 → 출격 → 승리 강제 → 더 깊이 미리보기 → 귀환 정산 → 상점 구매/보관/교체/취소 → 휴식 → 하루 종료 → 패배 → 저장 복구
const path = require('path'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const url = 'file://' + path.join(ROOT, 'index.html');
const ok = (n, c, x) => console.log((c ? 'PASS ' : 'FAIL ') + n + (x ? ' — ' + x : ''));
(async () => {
  const browser = await chromium.launch(); const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message)); page.on('dialog', d => { errors.push('dialog: ' + d.message()); d.dismiss(); });
  const ev = (fn) => page.evaluate(fn); const click = async (sel) => { await page.click(sel); await page.waitForTimeout(200); };
  await page.goto(url); await page.waitForTimeout(300); await ev(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(300);
  await click('[data-action=newrun]'); await click('[data-action=start-weapon][data-arg=sword]');
  let s = await ev(() => ({ screen: PA_G.screen, hours: PA_G.run.hours, cards: PA_G.run.cards.list.map(c => c.regionId + ':' + c.objective), gold: PA_G.run.gold, stock: PA_G.run.stock.equipment.length }));
  ok('S1 새 회차 거점', s.screen === 'base' && s.hours === 5 && s.cards.join() === 'forest:clear,ridge:clear' && s.gold === 60 && s.stock === 2, JSON.stringify(s));
  await page.screenshot({ path: 'docs/screenshots/v08_smoke_base.png', fullPage: true });
  await click('[data-action=mission][data-arg=d1c1]'); await page.waitForTimeout(400);
  s = await ev(() => ({ screen: PA_G.screen, slot: PA_G.sortie.slot, variant: PA_G.sortie.variant && PA_G.sortie.variant.name, waves: PA_G.combat.waves.length }));
  ok('S2 출격(새벽 변주: 마지막 웨이브 없음)', s.screen === 'combat' && s.slot === 0 && s.variant === '소규모 순찰' && s.waves === 2, JSON.stringify(s));
  await ev(() => { const c = PA_G.combat; for (const e of c.enemies) PA.Combat.damageEnemy(c, e, 99999, { src: { extra: true } }); c.pending = []; c.waveIndex = 99; c.spawnedAll = true; }); await page.waitForTimeout(2500);
  s = await ev(() => ({ screen: PA_G.screen }));
  ok('S3 승리 → 보상 화면', s.screen === 'reward', JSON.stringify(s));
  await click('[data-action=after-reward]'); await page.waitForTimeout(200);
  for (let i = 0; i < 4; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(200); }
  s = await ev(() => ({ screen: PA_G.screen, ev: PA_G.sortie.event && PA_G.sortie.event.id }));
  if (s.screen === 'event') { await click('[data-action=event-choice][data-arg=leave]'); s = await ev(() => ({ screen: PA_G.screen })); }
  ok('S4 다음 행동 화면(더 깊이 미리보기)', s.screen === 'after', JSON.stringify(s));
  const deepText = await page.$eval('.card.boss', el => el.textContent.replace(/\s+/g, ' ')).catch(() => '');
  ok('S5 더 깊이 카드: 시간·적 변화·보상·걸린 전리품 표시', /칸/.test(deepText) && /보상/.test(deepText) && /걸린 전리품/.test(deepText), deepText.slice(0, 160));
  await page.screenshot({ path: 'docs/screenshots/v08_smoke_after.png', fullPage: true });
  const g0 = await ev(() => PA_G.run.gold); await click('[data-action=return]');
  s = await ev(() => ({ screen: PA_G.screen, gold: PA_G.run.gold, log: PA_G.run.log[0] }));
  ok('S6 귀환 정산', s.screen === 'base' && s.gold > g0, JSON.stringify(s));
  // 상점
  await ev(() => { PA_G.run.gold = 500; }); await click('[data-action=shop]');
  const st = await ev(() => PA_G.run.stock.equipment);
  await click(`[data-action=buy-equip][data-arg="${st[0]}:stock:1"]`);
  s = await ev(() => ({ eq: Object.values(PA_G.run.equipment).filter(Boolean), bag: PA_G.run.bag.length, gold: PA_G.run.gold }));
  ok('S7 구매 후 장착', s.eq.includes(st[0]) && s.gold < 500, JSON.stringify(s));
  await click(`[data-action=buy-equip][data-arg="${st[1]}:stock:0"]`);
  s = await ev(() => ({ bag: PA_G.run.bag, gold: PA_G.run.gold }));
  ok('S8 구매 후 보관', s.bag.includes(st[1]), JSON.stringify(s));
  await click('[data-action=shop-tab][data-arg=skills]'); await page.screenshot({ path: 'docs/screenshots/v08_smoke_shop_skills.png', fullPage: true });
  const canSkill = await page.$('[data-action=buy-skill]:not([disabled])'); if (canSkill) { await canSkill.click(); await page.waitForTimeout(200); }
  s = await ev(() => ({ w: PA_G.run.growth.weapons.length, e: !!PA_G.run.growth.skills.e }));
  ok('S9 새 기술 구매', s.w === 2 || s.e, JSON.stringify(s));
  await ev(() => { PA_G.run.gold = 500; }); await click('[data-action=shop-tab][data-arg=skills]'); const snap = await ev(() => JSON.stringify([PA_G.run.growth.weapons, PA_G.run.gold]));
  await click('[data-action=swap-open][data-arg="weapon:0"]'); const opt = await page.$('[data-action=swap-pick]'); await opt.click(); await page.waitForTimeout(200);
  s = await ev(() => PA_G.screen); ok('S10 교체 화면 진행(확인 단계)', s === 'swap');
  await page.screenshot({ path: 'docs/screenshots/v08_smoke_swap.png', fullPage: true });
  await click('[data-action=swap-cancel]'); const snap2 = await ev(() => JSON.stringify([PA_G.run.growth.weapons, PA_G.run.gold]));
  ok('S11 교체 취소: 상태 불변', snap === snap2, snap2);
  await click('[data-action=shop-tab][data-arg=forge]'); await click('[data-action=forge-up]');
  s = await ev(() => ({ forge: PA_G.run.forge, gold: PA_G.run.gold })); ok('S12 대장간 1단계', s.forge === 1, JSON.stringify(s));
  await click('[data-action=shop-tab][data-arg=bag]'); await page.screenshot({ path: 'docs/screenshots/v08_smoke_bag.png', fullPage: true });
  await click('[data-action=base]'); await click('[data-action=rest]');
  s = await ev(() => ({ hours: PA_G.run.hours, slot: PA.Run.slotName(PA_G.run) })); ok('S13 휴식(가득 찬 체력에서도 다음 칸)', s.hours === 3 && s.slot === '점심', JSON.stringify(s));
  await click('[data-action=endday-confirm]'); const pv = await page.$eval('.screen', el => el.textContent.replace(/\s+/g, ' ')); ok('S14 하루 종료 전 내일 미리보기', /내일의 장소/.test(pv) && /포자 습지/.test(pv), pv.slice(0, 120));
  await click('[data-action=endday]');
  s = await ev(() => ({ day: PA_G.run.day, cards: PA_G.run.cards.list.map(c => c.regionId + ':' + c.objective), merchant: !!PA_G.run.merchant }));
  ok('S15 2일차: 숲(임무)/습지, 상인 예정', s.day === 2 && s.cards[0].startsWith('forest:') && !s.cards[0].endsWith('clear') && s.cards[1].startsWith('marsh') && s.merchant, JSON.stringify(s));
  // 패배
  await click('[data-action=mission][data-arg=d2c1]'); await page.waitForTimeout(400);
  await ev(() => { const c = PA_G.combat; c.player.hp = 0; c.player.dead = true; c.status = 'lost'; }); await page.waitForTimeout(2000);
  s = await ev(() => ({ screen: PA_G.screen, day: PA_G.run.day, hours: PA_G.run.hours, hp: PA_G.run.hp, hpMax: PA.Run.build(PA_G.run).hpMax, gold: PA_G.run.gold }));
  ok('S16 패배 → 남은 하루 상실 → 3일차(관문) 정상 체력', s.screen === 'defeat' && s.day === 3 && s.hp === s.hpMax, JSON.stringify(s));
  await page.screenshot({ path: 'docs/screenshots/v08_smoke_defeat.png', fullPage: true });
  await click('[data-action=base]'); s = await ev(() => ({ screen: PA_G.screen, phase: PA_G.run.phase })); ok('S17 관문 화면', s.screen === 'base' && s.phase === 'boss_prep', JSON.stringify(s));
  await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]');
  s = await ev(() => ({ screen: PA_G.screen, day: PA_G.run.day, forge: PA_G.run.forge, bag: PA_G.run.bag.length, v: PA_G.run.version }));
  ok('S18 저장 복구(v4)', s.day === 3 && s.forge === 1 && s.v === 4, JSON.stringify(s));
  ok('S19 페이지 오류 없음', errors.length === 0, errors.join(' | ').slice(0, 400));
  await browser.close();
})();
