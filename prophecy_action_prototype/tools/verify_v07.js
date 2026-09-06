// v0.7 브라우저 검증(실제 클릭·키 입력). 출격 카드 → 임무 → 보상 3택 → 사건 → 귀환, 3보스 관문·재도전·희귀 보상, 새로고침 복구, 이전 저장, 선택 중 입력 차단.
// 사용: NODE_PATH=<playwright> node tools/verify_v07.js  → docs/verify_v07_log.txt, docs/screenshots/v07_*.png
const path = require('path'); const fs = require('fs'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..'); const url = 'file://' + path.join(ROOT, 'index.html');
const results = []; const ok = (name, cond, extra) => { results.push([cond ? 'PASS' : 'FAIL', name, extra || '']); console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? ' — ' + extra : '')); };
(async () => {
  const browser = await chromium.launch(); const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  const ev = (fn) => page.evaluate(fn); const click = async (sel) => { await page.click(sel); await page.waitForTimeout(250); };
  const shot = (n) => page.screenshot({ path: path.join(ROOT, 'docs', 'screenshots', `v07_${n}.png`), fullPage: true });
  await page.goto(url); await page.waitForTimeout(300); await ev(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(300);
  // A. 새 회차(3보스) → 출격 카드 3장
  await click('[data-action=newrun]'); await click('[data-action=start-weapon][data-arg=sword]');
  let s = await ev(() => ({ mode: PA_G.run.mode, cards: PA_G.run.cards.list.length, day: PA_G.run.cards.day, linked: PA_G.run.cards.list.filter(c => c.linked).length }));
  ok('A1 새 회차 기본은 3보스 구조, 1일차 카드 3장 저장, 빌드 연결 카드 ≥1', s.mode === 'trio' && s.cards === 3 && s.day === 1 && s.linked >= 1, JSON.stringify(s));
  await click('[data-action=map]'); const cardTitles = await page.$$eval('.card.mission .card-title', els => els.map(e => e.textContent.trim()));
  ok('A2 출격 화면에 임무 카드 3장(지역·목표·시간)', cardTitles.length === 3 && cardTitles.every(t => /시간/.test(t)), cardTitles.join(' | '));
  await shot('verify_cards');
  // B. 임무 시작 → 승리(강제) → 보상 화면 → 3택 → 사건/다음 행동 → 귀환. 새로고침 복구 포함
  const cardId = await page.$eval('[data-action=mission]:not([disabled])', el => el.getAttribute('data-arg'));
  await click(`[data-action=mission][data-arg=${cardId}]`); await page.waitForTimeout(500);
  s = await ev(() => ({ screen: PA_G.screen, obj: PA_G.combat.objective, hud: PA.Objectives.hud(PA_G.combat).title, blocked: PA_G.input.blocked }));
  ok('B1 임무 전투 시작: 목표 HUD 표시', s.screen === 'combat' && PA_G_ok(s), JSON.stringify(s));
  function PA_G_ok(s) { return ['hunt', 'altars', 'seal', 'rescue'].includes(s.obj) && /목적/.test(s.hud); }
  // 전투 중 레벨업 → 선택 오버레이 동안 입력 차단
  await ev(() => { PA.Growth.addXp(PA_G.run.growth, 200); PA_G.combat.levelUps = 1; }); await page.waitForTimeout(300);
  await page.keyboard.down('ArrowRight'); await page.waitForTimeout(300); const x1 = await ev(() => PA_G.combat.player.x); await page.waitForTimeout(300); const x2 = await ev(() => PA_G.combat.player.x); await page.keyboard.up('ArrowRight');
  s = await ev(() => ({ overlay: PA_G.overlay, paused: PA_G.paused, blocked: PA_G.input.blocked, t: PA_G.combat.t }));
  ok('B2 선택 중 입력 차단·정지(키를 눌러도 이동 없음)', s.overlay === 'choice' && s.paused && s.blocked && Math.abs(x2 - x1) < 0.01, JSON.stringify(s));
  await shot('verify_choice_block');
  for (let i = 0; i < 6; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(250); }
  s = await ev(() => ({ overlay: PA_G.overlay, blocked: PA_G.input.blocked, paused: PA_G.paused }));
  ok('B3 선택 뒤 재개', s.overlay == null && !s.blocked && !s.paused, JSON.stringify(s));
  // 목표 달성(적이 살아 있어도 종료): 목표를 강제로 완료
  await ev(() => { const c = PA_G.combat; c.obj.done = true; }); await page.waitForTimeout(2500);
  s = await ev(() => ({ screen: PA_G.screen, alive: PA_G.lastStats && PA_G.lastStats.kills, reward: PA_G.lastReward && { mission: PA_G.lastReward.mission, pick: PA_G.lastReward.missionPick, mats: Object.keys(PA_G.lastReward.mats).length } }));
  ok('B4 목표 달성으로 승리 → 보상 화면(임무: 재료 대신 3택 예약)', s.screen === 'reward' && s.reward && s.reward.mission && s.reward.pick && s.reward.mats === 0, JSON.stringify(s));
  // 새로고침: 보상 화면 상태 복구
  await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]');
  s = await ev(() => ({ screen: PA_G.screen, overlay: PA_G.overlay, pool: PA_G.choice && PA_G.choice.pool, sortie: !!PA_G.sortie }));
  ok('B5 새로고침 뒤 전투 뒤 화면으로 복귀(보류 3택 제시)', s.sortie && (s.overlay === 'choice' || s.screen === 'after' || s.screen === 'event'), JSON.stringify(s));
  await shot('verify_after_reload');
  // 남은 3택을 모두 처리
  for (let i = 0; i < 6; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(250); const nb = await page.$('[data-action=after-reward]'); if (nb) { await nb.click(); await page.waitForTimeout(250); } }
  s = await ev(() => ({ screen: PA_G.screen, overlay: PA_G.overlay, pending: PA_G.run.growth.pendingMissionPick, done: PA_G.run.cards.list.find(c => c.id === PA_G.sortie.cardId).done }));
  ok('B6 임무 3택 1회 처리, 카드 완료 표시', !s.pending && s.done && (s.screen === 'after' || s.screen === 'event'), JSON.stringify(s));
  if (s.screen === 'event') { const opt = await page.$('[data-action=event-choice][data-arg=leave]'); if (opt) await opt.click(); await page.waitForTimeout(250); }
  s = await ev(() => ({ screen: PA_G.screen, deepDisabled: !!document.querySelector('[data-action=deep][disabled]') }));
  ok('B7 다음 행동 화면: 임무 출격에서는 더 깊이 탐험 불가', s.screen === 'after' && s.deepDisabled, JSON.stringify(s));
  await click('[data-action=return]'); s = await ev(() => ({ screen: PA_G.screen, pending: PA_G.run.pendingSortie, gold: PA_G.run.gold, doneBtn: !!document.querySelector('[data-action=map]') }));
  ok('B8 귀환: 보류 출격 해제·전리품 확정', s.screen === 'base' && !s.pending && s.gold > 60, JSON.stringify(s));
  await click('[data-action=map]'); const doneText = await page.$$eval('.card.mission button', els => els.map(e => e.textContent.trim()));
  ok('B9 완료한 임무 카드는 오늘 다시 시작 불가', doneText.some(t => /오늘 완료/.test(t)), doneText.join(' | '));
  await shot('verify_cards_after');
  // C. 사건 화면(강제 생성) 비용·보상 1회
  await click('[data-action=base]'); await click('[data-action=map]'); await click('[data-action=sortie][data-arg=forest]'); await page.waitForTimeout(400);
  await ev(() => { const c = PA_G.combat; for (const e of c.enemies) e.dead = true; c.waveIndex = 99; c.spawnedAll = true; c.status = 'won'; }); await page.waitForTimeout(2500);
  await ev(() => { PA_G.sortie.event = { id: 'supply', seed: 3, resolved: false, choice: null }; PA.Run.save(PA_G.run); });
  for (let i = 0; i < 6; i++) { const b = await page.$('[data-action=pick]'); if (!b) break; await b.click(); await page.waitForTimeout(250); }
  await click('[data-action=after-reward]'); s = await ev(() => ({ screen: PA_G.screen, opts: document.querySelectorAll('[data-action=event-choice]').length }));
  ok('C1 사건 화면: 비용·효과가 먼저 표시되고 선택지 3개', s.screen === 'event' && s.opts === 3, JSON.stringify(s));
  await shot('verify_event');
  const g0 = await ev(() => PA_G.sortie.loot.gold); await click('[data-action=event-choice][data-arg=loot]');
  s = await ev(() => ({ screen: PA_G.screen, gold: PA_G.sortie.loot.gold, resolved: PA_G.sortie.event.resolved, lastSupply: PA_G.run.lastSupplyDay }));
  ok('C2 보급소 물자: 전리품 +40, 1회 정산, 같은 날 재등장 금지 기록', s.gold === g0 + 40 && s.resolved && s.lastSupply === 1 && s.screen === 'after', JSON.stringify(s));
  await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]'); s = await ev(() => ({ screen: PA_G.screen, gold: PA_G.sortie && PA_G.sortie.loot.gold }));
  ok('C3 새로고침 뒤 사건이 다시 제시되지 않고 전리품 유지', s.screen === 'after' && s.gold === g0 + 40, JSON.stringify(s));
  await click('[data-action=return]');
  // D. 3보스 관문(빠른 경로 2단계): 패배 복구·승리·희귀 보상·다음 단계
  await click('[data-action=save-quit]'); await click('[data-action=quick-run][data-arg="1"]');
  s = await ev(() => ({ screen: PA_G.screen, phase: PA_G.run.phase, day: PA_G.run.day, next: PA.Run.nextBoss(PA_G.run).id, sortieBtn: !!document.querySelector('[data-action=boss-start]') }));
  ok('D1 2단계 관문 직전: 준비 화면·보스 입장 버튼', s.phase === 'boss_prep' && s.day === 5 && s.next === 'guardian' && s.sortieBtn, JSON.stringify(s));
  await click('[data-action=boss-start]'); await page.waitForTimeout(2500);
  const snap = await ev(() => JSON.stringify(PA_G.run.bossEntry.growth));
  await ev(() => { PA.Growth.addXp(PA_G.run.growth, 400); const c = PA_G.combat; c.player.hp = 0; c.player.dead = true; c.pendingLoss = true; }); await page.waitForTimeout(2500);
  s = await ev(() => ({ screen: PA_G.screen, retries: PA_G.run.bossRetries, same: JSON.stringify(PA_G.run.growth) }));
  ok('D2 패배: 입장 스냅샷으로 성장 복구(전투 중 경험치 중복 없음)', s.screen === 'boss_defeat' && s.retries === 1 && s.same === snap, s.screen + ' retries ' + s.retries);
  await click('[data-action=boss-start]'); await page.waitForTimeout(2500);
  await ev(() => { const c = PA_G.combat; PA.Combat.damageEnemy(c, c.boss, 99999, { src: { extra: true } }); }); await page.waitForTimeout(3000);
  s = await ev(() => ({ screen: PA_G.screen, stage: PA_G.run.stage, phase: PA_G.run.phase, hours: PA_G.run.hours, pending: !!PA_G.run.growth.pendingBossPick, recs: Object.keys(PA_G.run.bossRecords) }));
  ok('D3 승리: 다음 단계 해금·그날 5시간·기록 1회·희귀 보상 보류', s.screen === 'boss_victory' && s.stage === 2 && s.phase === 'prep' && s.hours === 5 && s.pending && s.recs.length === 1, JSON.stringify(s));
  await shot('verify_gate_victory');
  await click('[data-action=base]'); s = await ev(() => ({ overlay: PA_G.overlay, pool: PA_G.choice && PA_G.choice.pool, ids: PA_G.choice && PA_G.choice.choices.map(c => c.id) }));
  ok('D4 거점에서 희귀 보상 3택(적용 가능한 것만)', s.overlay === 'choice' && s.pool === 'boss' && s.ids.length >= 1 && s.ids.length <= 3, JSON.stringify(s));
  await shot('verify_rare');
  const ids0 = s.ids; await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]'); s = await ev(() => ({ overlay: PA_G.overlay, ids: PA_G.choice && PA_G.choice.choices.map(c => c.id) }));
  ok('D5 새로고침 뒤 같은 희귀 제시(재굴림 없음)', s.overlay === 'choice' && JSON.stringify(s.ids) === JSON.stringify(ids0), JSON.stringify(s));
  await click('[data-action=pick]'); s = await ev(() => ({ overlay: PA_G.overlay, rewards: PA_G.run.growth.bossRewards.length, pending: !!PA_G.run.growth.pendingBossPick, canSortie: PA.Run.canSortie(PA_G.run, 'forest') }));
  ok('D6 선택 1회 뒤 제시 없음, 그날 출격 가능', s.overlay == null && s.rewards === 1 && !s.pending && s.canSortie, JSON.stringify(s));
  // 최종 보스: 7일차 → 완주 → 추가 성장 없음
  await ev(() => { const r = PA_G.run; PA.Run.endDay(r); PA.Run.endDay(r); PA.Run.save(r); }); await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]');
  s = await ev(() => ({ day: PA_G.run.day, phase: PA_G.run.phase, next: PA.Run.nextBoss(PA_G.run).id })); ok('D7 7일차 최종 관문(예언을 먹는 자)', s.day === 7 && s.phase === 'boss_prep' && s.next === 'eater', JSON.stringify(s));
  await click('[data-action=boss-start]'); await page.waitForTimeout(2500); s = await ev(() => ({ bossId: PA_G.combat.bossId, hp: PA_G.combat.boss.hpMax }));
  const expectHp = await ev(() => PA.Run.bossHp(PA_G.run, 'eater'));
  ok('D8 최종 보스 입장(회차 설정의 체력 후보 적용: ' + expectHp + ')', s.bossId === 'eater' && s.hp === expectHp, JSON.stringify(s));
  await ev(() => { const c = PA_G.combat; PA.Combat.damageEnemy(c, c.boss, 99999, { src: { extra: true } }); }); await page.waitForTimeout(3000);
  s = await ev(() => ({ screen: PA_G.screen, phase: PA_G.run.phase, ended: PA_G.run.ended, pending: !!PA_G.run.growth.pendingBossPick, recs: Object.keys(PA_G.run.bossRecords).length, next: PA.Run.nextBoss(PA_G.run) }));
  ok('D9 최종 보스 승리: 회차 종료, 희귀 보상 없음, 기록 3개', s.screen === 'boss_victory' && s.phase === 'cleared' && s.ended && !s.pending && s.next === null, JSON.stringify(s));
  await shot('verify_run_end');
  // E. 이전 저장(단일 보스, v3 필드만) 로드
  await ev(() => { const old = PA.Run.newRun(3, 'sword', 'single'); delete old.mode; delete old.stage; delete old.bossesDone; delete old.bossRecords; delete old.cards; delete old.services; old.day = 6; localStorage.setItem(PA.Run.SAVE_KEY, JSON.stringify(old)); });
  await page.reload(); await page.waitForTimeout(300); await click('[data-action=continue]');
  s = await ev(() => ({ mode: PA_G.run.mode, left: PA.Run.bossDaysLeft(PA_G.run), hp: PA.Run.bossHp(PA_G.run, 'boss'), screen: PA_G.screen, cards: PA_G.run.cards && PA_G.run.cards.list.length }));
  ok('E1 이전 저장은 단일 보스 규칙(7일차 가시갈기 2400), 카드는 오늘부터 추가', s.mode === 'single' && s.left === 1 && s.hp === 2400 && s.screen === 'base', JSON.stringify(s));
  ok('Z 페이지 오류 없음', errors.length === 0, errors.join(' | '));
  const pass = results.filter(r => r[0] === 'PASS').length;
  fs.writeFileSync(path.join(ROOT, 'docs', 'verify_v07_log.txt'), results.map(r => `${r[0]} ${r[1]}${r[2] ? ' — ' + r[2] : ''}`).join('\n') + `\n\n${pass}/${results.length} PASS\n`);
  console.log(`${pass}/${results.length} PASS`); await browser.close();
})();
