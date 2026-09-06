// v0.8 브라우저 검증(실제 클릭·키 입력). 사용: NODE_PATH=<playwright> node tools/verify_v08.js → docs/verify_v08_log.txt, docs/screenshots/v08_*.png, docs/video/v08_combat.webm
// 검증 항목: 새 회차 1일차, 상점 구매/장착/보관/교체/취소, 심층 전리품 정산, 패배→다음 날, 보스 입장/실패/재도전, 결과 피해 통계, 저장·계속, 용어 사전(호버·고정·중첩·Esc·전투 중 정지), 레벨업 입력 차단
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const url = 'file://' + path.join(ROOT, 'index.html');
const results = []; const ok = (name, cond, extra) => { results.push([cond ? 'PASS' : 'FAIL', name, extra || '']); console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? ' — ' + extra : '')); };
(async () => {
  const browser = await chromium.launch(); const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, recordVideo: { dir: path.join(ROOT, 'docs', 'video'), size: { width: 1280, height: 900 } } }); const page = await ctx.newPage();
  const errors = []; page.on('pageerror', e => errors.push(e.message)); page.on('dialog', d => { errors.push('dialog: ' + d.message()); d.dismiss(); });
  const ev = (fn) => page.evaluate(fn); const click = async (sel) => { await page.click(sel); await page.waitForTimeout(220); };
  const shot = (n) => page.screenshot({ path: path.join(ROOT, 'docs', 'screenshots', `v08_${n}.png`), fullPage: true });
  const killAll = () => ev(() => { const c = PA_G.combat; for (const e of c.enemies) if (!e.dead) PA.Combat.damageEnemy(c, e, 99999, { src: { extra: true } }); c.pending = []; c.waveIndex = 99; c.spawnedAll = true; });
  const pickAll = async () => { for (let i = 0; i < 8; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(200); } };
  const finishCombat = async () => { await killAll(); await page.waitForTimeout(400); await pickAll(); await page.waitForTimeout(2500); }; // 처치 경험치로 생긴 레벨업 선택까지 처리
  await page.goto(url); await page.waitForTimeout(300); await ev(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(300);
  // A. 제목: 버전·설정 표시, 용어 사전 패널
  let s = await ev(() => ({ title: document.querySelector('.subtitle').textContent, settings: [...document.querySelectorAll('.dim.small')].map(e => e.textContent).join(' | ') }));
  ok('A1 제목 화면에 버전·기본 설정', /v0\.8/.test(s.title) && /시험 빌드/.test(s.settings), s.title);
  await click('[data-action=glossary]'); s = await ev(() => ({ overlay: PA_G.overlay, items: document.querySelectorAll('.gl-item').length })); ok('A2 용어 사전 패널(제목)', s.overlay === 'glossary' && s.items >= 40, JSON.stringify(s)); await shot('glossary_panel'); await page.keyboard.press('Escape'); await page.waitForTimeout(200);
  // B. 새 회차 → 1일차 새벽 시작 상태
  await click('[data-action=newrun]'); s = await ev(() => document.querySelector('h2').textContent); ok('B0 시작 화면 용어: 자동기술', /자동기술/.test(s), s);
  await click('[data-action=start-weapon][data-arg=blades]');
  s = await ev(() => { const r = PA_G.run; return { screen: PA_G.screen, day: r.day, hours: r.hours, hp: r.hp, gold: r.gold, w: r.growth.weapons.map(w => w.id + w.level + ':' + w.mods.length).join(), q: r.growth.skills.q.level, e: r.growth.skills.e, eq: Object.values(r.equipment).filter(Boolean).length, forge: r.forge, commons: Object.keys(r.growth.commons).length, places: r.cards.list.map(c => c.regionId + ':' + c.objective).join(), slot: PA.Run.slotName(r) }; });
  ok('B1 새 회차: 1일차 새벽, 체력 100, 금화 60, 회전 칼날 Lv1 개조 0, Q Lv1, E 없음, 장비·강화·공용 없음, 장소 숲/능선(전멸)', s.day === 1 && s.hours === 5 && s.hp === 100 && s.gold === 60 && s.w === 'blades1:0' && s.q === 1 && !s.e && s.eq === 0 && s.forge === 0 && s.commons === 0 && s.places === 'forest:clear,ridge:clear' && s.slot === '새벽', JSON.stringify(s));
  await shot('base_day1');
  // C. 용어 툴팁: 호버 → 툴팁, 클릭 → 고정, 중첩, Esc
  const term = await page.$('dfn.term[data-term=equipment]'); await term.hover(); await page.waitForTimeout(250);
  s = await ev(() => ({ hover: !!PA.Glossary.hover(), pinned: PA.Glossary.tips().length })); ok('C1 호버 툴팁', s.hover && s.pinned === 0, JSON.stringify(s));
  await term.click(); await page.waitForTimeout(250); s = await ev(() => ({ pinned: PA.Glossary.tips().length, nested: document.querySelectorAll('.tip dfn.term').length })); ok('C2 클릭 고정 + 중첩 용어 존재', s.pinned === 1 && s.nested >= 1, JSON.stringify(s));
  await page.click('.tip dfn.term'); await page.waitForTimeout(250); s = await ev(() => ({ pinned: PA.Glossary.tips().length, inView: [...document.querySelectorAll('.tip')].every(t => { const r = t.getBoundingClientRect(); return r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight; }) })); ok('C3 중첩 툴팁 고정, 화면 안 배치', s.pinned === 2 && s.inView, JSON.stringify(s)); await shot('glossary_nested');
  await page.keyboard.press('Escape'); await page.waitForTimeout(150); await page.keyboard.press('Escape'); await page.waitForTimeout(150); s = await ev(() => PA.Glossary.tips().length); ok('C4 Esc로 하나씩 닫힘', s === 0, String(s));
  // D. 상점: 구매·장착, 보관, 판매, 교체 취소, 대장간 잠김
  await ev(() => { PA_G.run.gold = 600; }); await click('[data-action=shop]'); await shot('shop_stock');
  const stock = await ev(() => PA_G.run.stock.equipment.slice()); await click(`[data-action=buy-equip][data-arg="${stock[0]}:stock:1"]`); await click(`[data-action=buy-equip][data-arg="${stock[1]}:stock:0"]`);
  s = await ev(() => ({ eq: Object.values(PA_G.run.equipment).filter(Boolean), bag: PA_G.run.bag.slice(), gold: PA_G.run.gold, again: PA.Run.canBuyEquipment(PA_G.run, PA_G.run.stock.equipment[0]) }));
  ok('D1 구매 후 장착/보관, 중복 구매 불가', s.eq.includes(stock[0]) && s.bag.includes(stock[1]) && !s.again, JSON.stringify(s));
  await click('[data-action=shop-tab][data-arg=bag]'); const g0 = await ev(() => PA_G.run.gold); const sp = await page.evaluate((id) => PA.Run.sellPrice(id), stock[1]); await click(`[data-action=sell-equip][data-arg=${stock[1]}]`); s = await ev(() => ({ gold: PA_G.run.gold, bag: PA_G.run.bag.length })); ok('D2 가방 장비 판매', s.gold === g0 + sp && s.bag === 0, JSON.stringify(s));
  await click('[data-action=shop-tab][data-arg=skills]'); const snap = await ev(() => JSON.stringify([PA_G.run.growth, PA_G.run.gold])); await click('[data-action=swap-open][data-arg="weapon:0"]'); await click('[data-action=swap-pick]'); await shot('swap_confirm');
  s = await ev(() => document.querySelector('.screen').textContent); ok('D3 교체 확인 단계: 비용·변경 표시', /확정/.test(s) && /비용/.test(s), ''); await click('[data-action=swap-cancel]'); const snap2 = await ev(() => JSON.stringify([PA_G.run.growth, PA_G.run.gold])); ok('D4 교체 취소 시 상태 불변', snap === snap2, '');
  await click('[data-action=shop-tab][data-arg=forge]'); s = await ev(() => ({ locked: !!document.querySelector('[data-action=forge-up]:not([disabled])'), text: document.querySelector('.card.item').textContent })); await click('[data-action=forge-up]'); s.after = await ev(() => ({ forge: PA_G.run.forge, next: document.querySelector('[data-action=forge-up]') && document.querySelector('[data-action=forge-up]').disabled })); ok('D5 대장간 1단계 개방, 2단계는 보스 전 잠김', s.after.forge === 1 && s.after.next === true, JSON.stringify(s.after));
  await click('[data-action=base]');
  // E. 출격 → 레벨업 입력 차단 → 승리 → 더 깊이 → 승리 → 귀환 정산(심층 보상 포함)
  await click('[data-action=mission][data-arg=d1c1]'); await page.waitForTimeout(400);
  await ev(() => { PA.Growth.addXp(PA_G.run.growth, 200); PA_G.combat.levelUps = 1; }); await page.waitForTimeout(300);
  await page.keyboard.down('ArrowRight'); await page.waitForTimeout(300); const x1 = await ev(() => PA_G.combat.player.x); await page.waitForTimeout(300); const x2 = await ev(() => PA_G.combat.player.x); await page.keyboard.up('ArrowRight');
  s = await ev(() => ({ overlay: PA_G.overlay, paused: PA_G.paused, blocked: PA_G.input.blocked, choices: PA_G.choice && PA_G.choice.choices.length }));
  ok('E1 레벨업: 정지·입력 차단·후보 3', s.overlay === 'choice' && s.paused && s.blocked && Math.abs(x2 - x1) < 0.01 && s.choices === 3, JSON.stringify(s)); await shot('levelup_block');
  await pickAll(); await page.waitForTimeout(3000); // 잠깐 전투(영상용)
  await finishCombat(); s = await ev(() => PA_G.screen); ok('E2 승리 → 보상 화면', s === 'reward', s);
  await click('[data-action=after-reward]'); await pickAll(); s = await ev(() => ({ screen: PA_G.screen })); if (s.screen === 'event') { await click('[data-action=event-choice][data-arg=leave]'); }
  s = await ev(() => ({ screen: PA_G.screen, can: PA.Run.canDeepExplore(PA_G.run, PA_G.sortie), pv: PA.Run.deepPreview(PA_G.run, PA_G.sortie).reward.kind, hours: PA_G.run.hours }));
  ok('E3 더 깊이 미리보기 표시', s.screen === 'after' && s.can, JSON.stringify(s)); await shot('after_deep_preview');
  const lootBefore = await ev(() => JSON.parse(JSON.stringify(PA_G.sortie.loot))); await click('[data-action=deep]'); await page.waitForTimeout(400);
  s = await ev(() => ({ screen: PA_G.screen, deep: PA_G.sortie.deep, hours: PA_G.run.hours, elite: PA_G.combat.waves.flat().some(g => PA.ENEMIES[g.type].elite) })); ok('E4 심층 전투: 시간 +1, 정예 포함', s.screen === 'combat' && s.deep && s.hours === 3 && s.elite, JSON.stringify(s));
  await finishCombat(); await click('[data-action=after-reward]'); await pickAll(); s = await ev(() => ({ screen: PA_G.screen })); if (s.screen === 'event') await click('[data-action=event-choice][data-arg=leave]');
  s = await ev(() => ({ screen: PA_G.screen, deepBtn: !!document.querySelector('[data-action=deep]'), rewarded: PA_G.sortie.deepRewarded, kind: PA_G.sortie.deepReward.kind, loot: PA_G.sortie.loot }));
  ok('E5 심층 승리 뒤 귀환만, 표시된 보상이 전리품에', s.screen === 'after' && !s.deepBtn && s.rewarded && (s.kind !== 'gold_big' || s.loot.gold > lootBefore.gold) && (s.kind !== 'equipment' || s.loot.items.length === 1) && (s.kind !== 'voucher' || s.loot.services.length === 1) && (s.kind !== 'steer' || s.loot.steer), JSON.stringify(s));
  const before = await ev(() => ({ gold: PA_G.run.gold, bag: PA_G.run.bag.length, sv: PA_G.run.services.mod_swap || 0, steer: !!PA_G.run.growth.steer })); const kind = s.kind; const lootG = s.loot.gold;
  await click('[data-action=return]'); s = await ev(() => ({ screen: PA_G.screen, gold: PA_G.run.gold, bag: PA_G.run.bag.length, sv: PA_G.run.services.mod_swap || 0, steer: !!PA_G.run.growth.steer, log: PA_G.run.log[0] }));
  ok('E6 귀환 정산: 금화·심층 보상 반영', s.screen === 'base' && s.gold === before.gold + lootG && (kind !== 'equipment' || s.bag === before.bag + 1) && (kind !== 'voucher' || s.sv === before.sv + 1) && (kind !== 'steer' || s.steer), JSON.stringify(s));
  // F. 저장·계속(피해 통계 포함) → 2일차 → 패배 → 3일차 관문
  await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]'); s = await ev(() => ({ screen: PA_G.screen, combats: PA_G.run.dmgStats.combats.length, v: PA_G.run.version })); ok('F1 저장·계속(v4, 피해 통계 유지)', s.screen === 'base' && s.combats === 2 && s.v === 4, JSON.stringify(s));
  await click('[data-action=endday-confirm]'); await shot('endday_preview'); await click('[data-action=endday]');
  await click('[data-action=mission][data-arg=d2c1]'); await page.waitForTimeout(400); await ev(() => { const c = PA_G.combat; c.player.hp = 0; c.player.dead = true; c.status = 'lost'; }); await page.waitForTimeout(2000);
  s = await ev(() => ({ screen: PA_G.screen, day: PA_G.run.day, hp: PA_G.run.hp, hpMax: PA.Run.build(PA_G.run).hpMax, phase: PA_G.run.phase })); ok('F2 패배 → 남은 하루 상실 → 3일차 관문, 정상 체력', s.screen === 'defeat' && s.day === 3 && s.hp === s.hpMax && s.phase === 'boss_prep', JSON.stringify(s)); await shot('defeat');
  await click('[data-action=base]'); await shot('boss_gate');
  // G. 보스 입장 → 패배 → 재도전(금화·성장 복구) → 승리 → 결과 화면 통계
  const snapG = await ev(() => JSON.stringify([PA_G.run.growth.level, PA_G.run.gold])); await click('[data-action=boss-start]'); await page.waitForTimeout(500);
  await ev(() => { PA.Growth.addXp(PA_G.run.growth, 500); PA_G.run.gold += 999; const c = PA_G.combat; c.player.hp = 0; c.player.dead = true; c.status = 'lost'; }); await page.waitForTimeout(2000);
  s = await ev(() => ({ screen: PA_G.screen, snap: JSON.stringify([PA_G.run.growth.level, PA_G.run.gold]), retries: PA_G.run.bossRetries, failed: PA_G.run.dmgStats.combats.filter(c => c.kind === 'boss' && !c.won).length }));
  ok('G1 보스 패배 → 입장 스냅샷 복구(레벨·금화), 재도전 카운트, 실패 통계 분리', s.screen === 'boss_defeat' && s.snap === snapG && s.retries === 1 && s.failed === 1, JSON.stringify(s));
  await click('[data-action=boss-start]'); await page.waitForTimeout(500); await ev(() => { const c = PA_G.combat; c.intro = 0; PA.Combat.damageEnemy(c, c.boss, 99999, { src: { weaponId: 'blades', direct: true } }); }); await page.waitForTimeout(3500);
  s = await ev(() => ({ screen: PA_G.screen, stage: PA_G.run.stage, hours: PA_G.run.hours })); ok('G2 보스 승리 → 1단계 돌파, 그날 시간 시작', s.screen === 'boss_victory' && s.stage === 1 && s.hours === 5, JSON.stringify(s)); await shot('boss_victory');
  await click('[data-action=base]'); await pickAll(); s = await ev(() => ({ stats: !!document.querySelector('details.card summary') && /피해 통계/.test(document.body.textContent), verify: PA.Stats.verify(PA_G.run).every(v => v.ok), forgeOpen: PA.Run.forgeNext(PA_G.run).open }));
  ok('G3 거점 피해 통계 패널·합계 검증, 대장간 2단계 개방', s.stats && s.verify && s.forgeOpen, JSON.stringify(s)); await shot('base_stats');
  // H. 전투 중 용어 사전: 마우스 이동은 정지 없음, 패널 열면 정지, 닫으면 재개
  await click('[data-action=mission][data-arg=d3c1]'); await page.waitForTimeout(400); await page.mouse.move(400, 400); await page.mouse.move(600, 500); await page.waitForTimeout(200);
  s = await ev(() => ({ paused: PA_G.paused })); ok('H1 전투 중 마우스 이동만으로는 정지 없음', !s.paused, JSON.stringify(s));
  await page.keyboard.press('Escape'); await page.waitForTimeout(200); await click('[data-action=glossary]'); s = await ev(() => ({ overlay: PA_G.overlay, paused: PA_G.paused })); ok('H2 일시정지 메뉴에서 용어 사전 → 정지 유지', s.overlay === 'glossary' && s.paused, JSON.stringify(s)); await shot('glossary_in_combat');
  await page.keyboard.press('Escape'); await page.waitForTimeout(200); s = await ev(() => ({ overlay: PA_G.overlay, paused: PA_G.paused })); ok('H3 사전 닫으면 일시정지 메뉴로 복귀', s.overlay === 'pause' && s.paused, JSON.stringify(s));
  await click('[data-action=resume]'); s = await ev(() => PA_G.paused); ok('H4 재개', s === false, String(s));
  await page.waitForTimeout(4000); await finishCombat();
  // I. 이전 버전(v3) 저장 변환: 조용히 바꾸지 않고 기록·표시
  await ev(() => { const r = PA.Run.newRun(5, 'sword', 'trio', 'test03'); r.version = 3; delete r.equipment; delete r.bag; delete r.forge; delete r.dmgStats; r.gear = { armor: 'leather_armor', acc: 'time_charm', upgrade: 2 }; r.owned = ['leather_armor', 'time_charm']; r.day = 2; localStorage.setItem(PA.Run.SAVE_KEY, JSON.stringify(r)); });
  await page.reload(); await page.waitForTimeout(300); s = await ev(() => ({ btn: document.querySelector('[data-action=continue]').textContent })); await click('[data-action=continue]');
  s = Object.assign(s, await ev(() => ({ v: PA_G.run.version, forge: PA_G.run.forge, notes: PA_G.run.migrationNotes, log: PA_G.run.log[0], gold: PA_G.run.gold })));
  ok('I1 v3 저장 → v4 변환: 옛 장비 환급·강화 단계 변환이 기록·표시됨', s.v === 4 && s.forge === 2 && s.notes && s.notes.length >= 2 && /v0\.8/.test(s.log) && /변환/.test(s.btn) && s.gold === 120, JSON.stringify(s));
  ok('Z 페이지 오류 없음', errors.length === 0, errors.join(' | ').slice(0, 500));
  await ctx.close(); await browser.close();
  const vids = fs.readdirSync(path.join(ROOT, 'docs', 'video')).filter(f => f.endsWith('.webm')); const latest = vids.map(f => ({ f, t: fs.statSync(path.join(ROOT, 'docs', 'video', f)).mtimeMs })).sort((a, b) => b.t - a.t)[0]; if (latest) fs.renameSync(path.join(ROOT, 'docs', 'video', latest.f), path.join(ROOT, 'docs', 'video', 'v08_verify.webm'));
  for (const f of fs.readdirSync(path.join(ROOT, 'docs', 'video'))) if (f !== 'v08_verify.webm') fs.unlinkSync(path.join(ROOT, 'docs', 'video', f));
  fs.writeFileSync(path.join(ROOT, 'docs', 'verify_v08_log.txt'), `v0.8 ${new Date().toISOString()}\n` + results.map(r => r.join(' | ')).join('\n') + '\n');
  console.log(`${results.filter(r => r[0] === 'PASS').length}/${results.length} PASS`);
})();
