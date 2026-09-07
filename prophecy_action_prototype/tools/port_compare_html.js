// Godot 대조 시나리오의 HTML 쪽(같은 조건·같은 측정). 사용: node tools/port_compare_html.js → JSON 1줄(COMPARE_JSON ...)
const { load } = require('../test/load'); const PA = load(); PA.Balance.apply('current');
const STEP = PA.CONFIG.STEP; const R = PA.Run, CB = PA.Combat;
const mk = () => { const run = R.newRun(1, 'sword'); const st = CB.create({ build: R.build(run), seed: 1, waves: [], objective: 'none', arena: 'clearing' }); st.waveIndex = 99; return st; };
const out = {};
let st = mk(); let x0 = st.player.x; for (let i = 0; i < 120; i++) CB.step(st, { mx: 1 }, STEP); out.move_1s = Math.round((st.player.x - x0) * 1000) / 1000;
st = mk(); x0 = st.player.x; let y0 = st.player.y; for (let i = 0; i < 120; i++) CB.step(st, { mx: 1, my: -1 }, STEP); out.move_diag_1s = Math.round(Math.hypot(st.player.x - x0, st.player.y - y0) * 1000) / 1000;
st = mk(); y0 = st.player.y; CB.step(st, { my: -1, dodge: true }, STEP); let inv = 0; while (st.player.dodge.active && inv < 200) { CB.step(st, {}, STEP); inv++; } out.dodge_dist = Math.round((y0 - st.player.y) * 1000) / 1000; out.dodge_invuln_steps = inv + 1; out.dodge_cd_after = Math.round(st.player.dodge.cd * 10000) / 10000;
st = mk(); const w = CB.spawnEnemy(st, 'wolf', 480, 200); st.player.y = 585; w.state = 'crouch'; w.stateT = 0; const counts = { crouch: 0, lock: 0, dash: 0, recover: 0 }; let sx = 0, sy = 0;
for (let i = 0; i < 600; i++) { const before = w.state; if (before === 'dash' && counts.dash === 0) { sx = w.x; sy = w.y; } CB.step(st, {}, STEP); if (before in counts) counts[before]++; if (w.state === 'approach' && before === 'recover') break; }
out.wolf_steps = counts; out.wolf_dash_dist = Math.round(Math.hypot(w.x - sx, w.y - sy) * 100) / 100;
st = mk(); const e = CB.spawnEnemy(st, 'wolf', st.player.x + 60, st.player.y); e.hp = 99999; const hitTimes = []; let lastHits = 0;
for (let i = 0; i < 600; i++) { CB.step(st, {}, STEP); e.x = st.player.x + 60; e.y = st.player.y; const h = st.metrics.hits.sword || 0; if (h > lastHits) { hitTimes.push(Math.round(st.t * 10000) / 10000); lastHits = h; } }
out.attack_times = hitTimes; out.hit_damage_normal = Math.round(st.metrics.dmg['weapon:sword'] / lastHits * 100) / 100;
e.state = 'recover'; const bd = st.metrics.dmg['weapon:sword'], bh = lastHits; for (let i = 0; i < 80; i++) { CB.step(st, {}, STEP); e.x = st.player.x + 60; e.y = st.player.y; e.state = 'recover'; e.stateT = 0; } out.hit_damage_exposed = Math.round((st.metrics.dmg['weapon:sword'] - bd) / ((st.metrics.hits.sword || 0) - bh) * 100) / 100;
st = mk(); const s1 = CB.spawnEnemy(st, 'wolf', 480, 100); st.player.y = 560; CB.step(st, { special: true }, STEP); st.field.x = 480; st.field.y = 100; let ya = s1.y; for (let i = 0; i < 60; i++) CB.step(st, {}, STEP); out.wolf_move_0_5s_in_field = Math.round((s1.y - ya) * 100) / 100;
st = mk(); const s2 = CB.spawnEnemy(st, 'wolf', 480, 100); st.player.y = 560; ya = s2.y; for (let i = 0; i < 60; i++) CB.step(st, {}, STEP); out.wolf_move_0_5s_free = Math.round((s2.y - ya) * 100) / 100;
st = mk(); CB.damagePlayer(st, PA.ENEMIES.wolf.damage, 'wolf'); out.wolf_bite_damage = st.player.hpMax - st.player.hp; out.hit_protect = PA.CONFIG.PLAYER.hitProtect;
console.log('COMPARE_JSON ' + JSON.stringify(out));
