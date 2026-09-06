// 전투 입력 큐. 눌림 상태(keys)와 단발 입력(pressed)을 관리하고, 정지 중에는 전투 입력을 받지 않는다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Input = (function () {
  const MOVE = { KeyA: [-1, 0], ArrowLeft: [-1, 0], KeyD: [1, 0], ArrowRight: [1, 0], KeyW: [0, -1], ArrowUp: [0, -1], KeyS: [0, 1], ArrowDown: [0, 1] };
  const ONESHOT = { Space: 'dodge', KeyQ: 'special' };
  function create() { return { keys: new Set(), pressed: new Set(), blocked: false }; }
  // 정지(blocked=true)·재개(blocked=false) 양쪽에서 남은 눌림/단발 입력을 모두 비운다
  function setBlocked(inp, blocked) { inp.blocked = !!blocked; inp.keys.clear(); inp.pressed.clear(); }
  function keyDown(inp, code) {
    if (inp.blocked) return false;            // 정지 중에는 누적하지 않는다
    inp.keys.add(code);
    if (ONESHOT[code]) inp.pressed.add(code);
    return true;
  }
  function keyUp(inp, code) { inp.keys.delete(code); }
  function clearAll(inp) { inp.keys.clear(); inp.pressed.clear(); }
  function state(inp) {
    let mx = 0, my = 0;
    for (const code of inp.keys) { const m = MOVE[code]; if (m) { mx += m[0]; my += m[1]; } }
    return { mx: Math.max(-1, Math.min(1, mx)), my: Math.max(-1, Math.min(1, my)), dodge: inp.pressed.has('Space'), special: inp.pressed.has('KeyQ') };
  }
  function consumePressed(inp) { inp.pressed.clear(); }
  return { create, setBlocked, keyDown, keyUp, clearAll, state, consumePressed, MOVE, ONESHOT };
})();
