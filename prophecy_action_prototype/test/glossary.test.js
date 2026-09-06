// 용어 사전 데이터: 모든 용어의 본문이 렌더되고 {{연결}}이 실제 용어를 가리키며, 장비 12종·자동기술·E 기술이 포함된다. 규칙 수치는 데이터에서 읽는다
const test = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('./load');
const PA = load();
test('용어 사전: 본문 렌더·연결 유효·데이터 항목 포함·수치 동기화', () => {
  const A = PA.Glossary.all(); const ids = Object.keys(A); assert.ok(ids.length >= 40, ids.length);
  for (const id of ids) { const d = A[id]; assert.ok(d.name && d.short, id); const raw = typeof d.body === 'function' ? d.body() : d.body; assert.ok(raw.length > 10, id); for (const m of raw.matchAll(/\{\{([a-z_:]+)\}\}/g)) assert.ok(A[m[1]], `${id} → ${m[1]} 없음`); for (const r of d.related || []) assert.ok(A[r], `${id} 관련 ${r} 없음`); const html = PA.Glossary.body(id); assert.ok(!/\{\{/.test(html)); }
  for (const id in PA.EQUIPMENT) assert.ok(A['eq:' + id]); for (const id in PA.WEAPONS) if (PA.WEAPONS[id].impl) assert.ok(A['w:' + id]); for (const id of PA.E_SKILLS) assert.ok(A['e:' + id]);
  assert.ok(PA.Glossary.body('swap').includes(String(PA.SHOP.swap.base)) && PA.Glossary.body('forge').includes(String(PA.SHOP.forge[2].cost)), '수치는 데이터와 동일');
  assert.ok(PA.Glossary.T('equipment').includes('dfn') && PA.Glossary.T('nope', 'x') === 'x');
  assert.ok(PA.Glossary.panelHtml('equipment').includes('gl-equipment'));
});
