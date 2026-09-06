const test = require('node:test');
const assert = require('node:assert/strict');
const { load, combat, steps } = require('./load');
const PA = load();
const I = PA.Input;

test('정지 중 눌렀다 놓은 Space/Q는 재개 후 발동하지 않는다', () => {
  const inp = I.create();
  I.setBlocked(inp, true);                 // 일시정지
  assert.equal(I.keyDown(inp, 'Space'), false); I.keyUp(inp, 'Space');
  assert.equal(I.keyDown(inp, 'KeyQ'), false); I.keyUp(inp, 'KeyQ');
  assert.equal(I.keyDown(inp, 'KeyD'), false);
  assert.equal(inp.pressed.size, 0); assert.equal(inp.keys.size, 0);
  I.setBlocked(inp, false);                // 재개
  const s = I.state(inp);
  assert.deepEqual([s.dodge, s.special, s.mx, s.my], [false, false, 0, 0]);
  // 재개 후의 새 입력은 정상 동작
  I.keyDown(inp, 'Space'); assert.equal(I.state(inp).dodge, true);
  I.consumePressed(inp); assert.equal(I.state(inp).dodge, false, '단발 입력은 한 번만 소비');
});

test('정지 직전 남아 있던 단발 입력과 눌림 상태는 정지·재개 시 정리된다', () => {
  const inp = I.create();
  I.keyDown(inp, 'Space'); I.keyDown(inp, 'KeyW');
  assert.equal(inp.pressed.has('Space'), true); assert.equal(I.state(inp).my, -1);
  I.setBlocked(inp, true);
  assert.equal(inp.pressed.size, 0); assert.equal(I.state(inp).my, 0);
  I.keyUp(inp, 'KeyW');                    // 정지 중 키를 놓아도 안전
  I.setBlocked(inp, false);
  assert.equal(inp.pressed.size, 0); assert.equal(I.state(inp).my, 0, '재개 후 다시 눌러야 이동');
  I.keyDown(inp, 'KeyW'); assert.equal(I.state(inp).my, -1);
});

test('전투 시뮬레이션 연동: 정지 중 입력은 회피·감속장을 발동시키지 않고, 재개 후 입력은 기존 수치대로 발동한다', () => {
  const { st } = combat(PA);
  const inp = I.create();
  I.setBlocked(inp, true); I.keyDown(inp, 'Space'); I.keyUp(inp, 'Space'); I.keyDown(inp, 'KeyQ'); I.keyUp(inp, 'KeyQ'); I.setBlocked(inp, false);
  PA.Combat.step(st, I.state(inp), PA.CONFIG.STEP); I.consumePressed(inp);
  assert.equal(st.player.dodge.active, false); assert.equal(st.field, null); assert.equal(st.player.special.cd, 0);
  I.keyDown(inp, 'Space'); I.keyDown(inp, 'KeyQ');
  const x0 = st.player.x; st.player.face = 0;
  PA.Combat.step(st, I.state(inp), PA.CONFIG.STEP); I.consumePressed(inp);
  assert.equal(st.player.dodge.active, true); assert.ok(st.field);
  steps(PA, st, 0.5, I.state(inp));
  const D = PA.CONFIG.PLAYER.dodge, S = PA.CONFIG.PLAYER.special;
  assert.deepEqual([D.duration, D.distance, D.cooldown, S.radius, S.duration, S.cooldown, S.slow], [0.26, 150, 0.9, 150, 3.0, 14, 0.4], '회피·감속장 수치 유지');
  assert.ok(Math.abs(st.player.x - x0 - D.distance) < 1e-6);
  assert.ok(Math.abs(st.player.special.cd - (S.cooldown - 0.5)) < 1e-6);
});
