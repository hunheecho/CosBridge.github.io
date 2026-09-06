// 실제 키 이벤트로 검증: 일시정지 중 눌렀다 놓은 Space/Q가 재개 직후 발동하지 않는다.
const path = require('path'); const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1048, height: 688 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + path.join(ROOT, 'index.html') + '?scenario=forest&seed=11'); await p.waitForTimeout(600);
  const snap = () => p.evaluate(() => ({ paused: PA_G.paused, t: PA_G.combat.t, dodge: PA_G.combat.player.dodge.active, dodgeCd: PA_G.combat.player.dodge.cd, field: !!PA_G.combat.field, specialCd: PA_G.combat.player.special.cd, pressed: [...PA_G.input.pressed], keys: [...PA_G.input.keys] }));
  const results = [];
  const check = (name, ok, detail) => { results.push({ name, ok }); console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail ? ' — ' + detail : '')); };
  // 1) 이동 키를 누른 채 정지 → 정지 중 Space/Q 눌렀다 놓기 → 재개
  await p.keyboard.down('KeyD'); await p.waitForTimeout(150);
  await p.keyboard.press('Escape'); await p.waitForTimeout(100);
  let s = await snap(); check('정지 시 눌림 상태 정리', s.paused && s.keys.length === 0 && s.pressed.length === 0, JSON.stringify(s.keys));
  await p.keyboard.up('KeyD');
  await p.keyboard.press('Space'); await p.keyboard.press('KeyQ'); await p.waitForTimeout(150);
  s = await snap(); check('정지 중 Space/Q가 누적되지 않음', s.pressed.length === 0 && s.keys.length === 0, JSON.stringify(s.pressed));
  const tPaused = s.t;
  await p.keyboard.press('Escape'); await p.waitForTimeout(250);
  s = await snap();
  check('재개 직후 회피·감속장이 발동하지 않음', !s.paused && !s.dodge && s.dodgeCd <= 0 && !s.field && s.specialCd === 0, `dodge=${s.dodge} field=${s.field} specialCd=${s.specialCd}`);
  check('재개 후 시간이 다시 흐름', s.t > tPaused + 0.1, `${tPaused.toFixed(2)} → ${s.t.toFixed(2)}`);
  check('재개 후 이동 키는 다시 눌러야 함', s.keys.length === 0);
  // 2) 재개 후 새 입력은 정상 발동
  await p.keyboard.press('Space'); await p.waitForTimeout(80); s = await snap();
  check('재개 후 Space는 회피 발동', s.dodge === true);
  await p.keyboard.press('KeyQ'); await p.waitForTimeout(80); s = await snap();
  check('재개 후 Q는 감속장 발동', s.field === true && s.specialCd > 13);
  // 3) 조작법 오버레이(Esc → 조작법) 중에도 전투 입력 무시
  await p.keyboard.press('Escape'); await p.waitForTimeout(100); await p.click('[data-action=show-controls]'); await p.waitForTimeout(100);
  await p.keyboard.press('Space'); await p.waitForTimeout(80); s = await snap();
  check('조작법 오버레이 중 Space 무시', s.pressed.length === 0);
  await p.keyboard.press('Escape'); await p.waitForTimeout(80); await p.keyboard.press('Escape'); await p.waitForTimeout(300); s = await snap();
  check('오버레이 닫고 재개해도 남은 입력 없음', !s.paused && s.pressed.length === 0 && !s.dodge);
  console.log('errors:', errs.length ? errs : 'none');
  await b.close();
  if (errs.length || results.some(r => !r.ok)) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
