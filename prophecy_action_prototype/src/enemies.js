// 신규 기본 몬스터(v0.6). combat.js가 PA.Enemies.has(type)인 개체에 PA.Enemies.update를 호출한다. (구현은 시험실 2단계에서 채운다)
var PA = (typeof PA !== 'undefined') ? PA : {};
PA.Enemies = (function () {
  const HANDLERS = {};
  function has(type) { return !!HANDLERS[type]; }
  function update(st, e, dt) { HANDLERS[e.type](st, e, dt); }
  function isCommitted(e) { return false; }
  function threats(st, e, out) {}
  return { HANDLERS, has, update, isCommitted, threats };
})();
