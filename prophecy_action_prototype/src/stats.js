// 런 누적 피해 통계(v0.8). 전투 정산 시 Combat.metrics(실제 체력 감소 기준, 과잉 피해 제외)를 출처별로 기록하고
// 결과 화면에서 기술별 유효 피해·비중·DPS(실제 전투 시간·기술 보유 시간 기준)·분류별·보스 전용 보기를 만든다. 저장 파일에 남는다.
var PA = (typeof PA !== 'undefined') ? PA : {};
PA.Stats = (function () {
  const CATS = { direct: '직접 공격', projectile: '투사체', ground: '바닥 지대', dot: '지속 피해', skill: 'Q/E', extra: '추가 효과' };
  // 출처 키 → 표시 이름·분류. weapon:id는 무기 정의의 category, dot:*는 지속 피해, skill:*는 Q/E, 나머지는 추가 효과
  function classify(key) {
    const [kind, id] = key.split(':');
    if (kind === 'weapon') { const d = PA.WEAPONS[id]; return { name: d ? d.name : id, cat: d ? d.category : 'direct', skill: key }; }
    if (kind === 'dot') return { name: id === 'burn' ? '화상' : id === 'bleed' ? '출혈' : id, cat: 'dot', skill: null };
    if (kind === 'skill') return { name: id === 'q' || id === 'slowfield' ? '감속장(Q)' : (PA.SKILLS[id] ? PA.SKILLS[id].name + '(E)' : id), cat: 'skill', skill: key === 'skill:q' || id === 'slowfield' ? 'skill:q' : key };
    if (kind === 'common') { const d = PA.COMMONS[id]; return { name: d ? d.name : id, cat: 'extra', skill: null }; }
    return { name: { other: '기타' }[key] || key, cat: 'extra', skill: null };
  }
  // 정산 1회: 같은 전투를 두 번 기록하지 않는다(st.statsRecorded)
  function record(run, st, meta) {
    if (!st || st.statsRecorded || !st.metrics) return null; st.statsRecorded = true;
    run.dmgStats = run.dmgStats || { combats: [], byKey: {} };
    const M = st.metrics; const dmg = {}; let total = 0; for (const k in M.dmg) { dmg[k] = Math.round(M.dmg[k] * 10) / 10; total += M.dmg[k]; }
    const bossDmg = st.boss ? Math.round(st.stats.bossDamage * 10) / 10 : 0;
    const rec = Object.assign({ elapsed: Math.round(st.t * 100) / 100, dmg, total: Math.round(total * 10) / 10, bossDamage: bossDmg, taken: Math.round(st.stats.damageTaken * 10) / 10, kills: st.stats.kills, activeT: Object.assign({}, st.activeT), status: st.status, won: st.status === 'won' }, meta || {});
    run.dmgStats.combats.push(rec);
    return rec;
  }
  // 집계: filter(rec) → { rows: [{ key, name, cat, amount, share, active, dps }], total, elapsed, cats: {cat: amount}, n }
  function aggregate(run, filter) {
    const list = ((run.dmgStats && run.dmgStats.combats) || []).filter(filter || (() => true));
    const sum = {}, act = {}; let total = 0, elapsed = 0, taken = 0;
    for (const r of list) { elapsed += r.elapsed; taken += r.taken; for (const k in r.dmg) { sum[k] = (sum[k] || 0) + r.dmg[k]; total += r.dmg[k]; } for (const k in r.activeT) act[k] = (act[k] || 0) + r.activeT[k]; }
    const rows = Object.keys(sum).map(k => { const c = classify(k); const active = c.skill && act[c.skill] != null ? act[c.skill] : elapsed; return { key: k, name: c.name, cat: c.cat, amount: Math.round(sum[k] * 10) / 10, share: total ? Math.round(sum[k] / total * 1000) / 10 : 0, active: Math.round(active * 10) / 10, dps: active > 0 ? Math.round(sum[k] / active * 10) / 10 : 0 }; }).sort((a, b) => b.amount - a.amount);
    const cats = {}; for (const r of rows) cats[r.cat] = Math.round(((cats[r.cat] || 0) + r.amount) * 10) / 10;
    return { rows, total: Math.round(total * 10) / 10, elapsed: Math.round(elapsed * 10) / 10, taken: Math.round(taken * 10) / 10, cats, n: list.length, dpsAll: elapsed > 0 ? Math.round(total / elapsed * 10) / 10 : 0 };
  }
  const views = (run) => ({ all: aggregate(run), boss: aggregate(run, r => r.kind === 'boss' && r.won), bossFailed: aggregate(run, r => r.kind === 'boss' && !r.won), sortie: aggregate(run, r => r.kind !== 'boss') });
  // 검증: 출처 합 = 총합, 분류 합 = 총합(반올림 오차 허용)
  function verify(run) { const out = []; for (const [name, a] of Object.entries(views(run))) { const rowSum = a.rows.reduce((x, r) => x + r.amount, 0), catSum = Object.values(a.cats).reduce((x, y) => x + y, 0); out.push({ view: name, ok: Math.abs(rowSum - a.total) <= 0.5 * Math.max(1, a.rows.length) && Math.abs(catSum - a.total) <= 0.5 * Math.max(1, a.rows.length), total: a.total, rowSum: Math.round(rowSum * 10) / 10, catSum: Math.round(catSum * 10) / 10 }); } return out; }
  return { record, aggregate, views, verify, classify, CATS };
})();
