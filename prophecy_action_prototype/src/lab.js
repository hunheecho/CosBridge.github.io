// 전투 시험실 논리(v0.6): 설정 ↔ 문자열, 프리셋 검증, 회차·전투 생성, 결과 정리. 정식 회차 저장(prophecy_action_save_v1)은 건드리지 않는다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Lab = (function () {
  const LAB_KEY = 'prophecy_action_lab_v1';           // 시험실 설정만(정식 회차 저장과 별도 키)
  const RESULTS_KEY = 'prophecy_action_lab_results_v1'; // 최근 결과(비교 표)
  const S = () => PA.GROWTH.SLOTS;

  function defaultConfig() { return { enemy: 'region:forest', arena: 'auto', hp: { normal: 1, elite: 1, boss: 1 }, seed: 1, build: 'early_sword', control: 'human', bot: 'balanced', growth: 'fixed', time: PA.LAB.DEFAULT_TIME, deep: false, layout: 'classic', overlap: -1 }; }
  // ---------- 문자열 ----------
  function encode(c) { return [`enemy=${c.enemy}`, `arena=${c.arena}`, `hp=${c.hp.normal},${c.hp.elite},${c.hp.boss}`, `seed=${c.seed}`, `build=${c.build}`, `control=${c.control}`, `bot=${c.bot}`, `growth=${c.growth}`, `time=${c.time}`, `deep=${c.deep ? 1 : 0}`, `layout=${c.layout || 'classic'}`, `overlap=${c.overlap == null ? -1 : c.overlap}`].join(';'); }
  function decode(str) {
    const c = defaultConfig(); if (!str) return c;
    let src = String(str).trim();
    if (src.startsWith('{')) { try { const o = JSON.parse(src); return normalize(Object.assign(c, o)); } catch (e) { return c; } }
    for (const part of src.split(/[;&\n]/)) { const i = part.indexOf('='); if (i < 0) continue; const k = part.slice(0, i).trim(), v = decodeURIComponent(part.slice(i + 1).trim());
      if (k === 'hp') { const [a, b, d] = v.split(',').map(Number); c.hp = { normal: a || 1, elite: b || a || 1, boss: d || a || 1 }; }
      else if (k === 'seed' || k === 'time' || k === 'overlap') c[k] = parseInt(v, 10);
      else if (k === 'deep') c.deep = v === '1' || v === 'true';
      else if (k in c) c[k] = v; }
    return normalize(c);
  }
  function normalize(c) {
    const d = defaultConfig();
    if (!enemyPreset(c.enemy)) c.enemy = d.enemy;
    if (!PA.LAB.TERRAINS[c.arena]) c.arena = 'auto';
    if (!PA.LAB.BUILDS[c.build]) c.build = d.build;
    if (!PA.Bot.POLICIES[c.bot]) c.bot = 'balanced';
    if (c.control !== 'bot') c.control = 'human';
    if (c.growth !== 'grow') c.growth = 'fixed';
    if (!(c.seed >= 0)) c.seed = 1;
    if (!(c.time >= 10)) c.time = d.time;
    if (!c.hp) c.hp = d.hp; for (const k of ['normal', 'elite', 'boss']) if (!(c.hp[k] > 0)) c.hp[k] = 1;
    if (!(PA.LAYOUTS && PA.LAYOUTS[c.layout])) c.layout = 'classic';
    if (c.overlap == null || isNaN(c.overlap)) c.overlap = -1;
    return c;
  }

  // ---------- 적 프리셋 ----------
  // id: region:<지역> | solo:<적> | combo:<조합> | boss
  function enemyPresets() {
    const list = [];
    for (const r of PA.REGIONS) list.push({ id: 'region:' + r.id, group: '지역(기존 배치)', name: r.name, regionId: r.id, waves: r.waves, objective: r.objective, arena: 'forest', desc: r.desc });
    if (PA.LAYOUTS && PA.LAYOUTS.trial) for (const r of PA.REGIONS) { const L = PA.LAYOUTS.trial.regions[r.id]; if (L) list.push({ id: 'trial:' + r.id, group: '지역(시험안 배치)', name: r.name + ' · 시험안', regionId: r.id, waves: L.waves, objective: L.objective || r.objective, arena: L.arena || 'forest', desc: L.desc || r.desc }); }
    for (const t of PA.LAB.ENEMY_ORDER) { const d = PA.ENEMIES[t]; if (!d || t === 'boss') continue; const n = t === 'wolf' ? 2 : 1; const ally = t === 'shaman' ? [{ type: 'wolf', n: 2 }] : []; list.push({ id: 'solo:' + t, group: '단독 시험', name: d.name + (n > 1 ? ` ×${n}` : '') + (ally.length ? ' (+늑대 2: 치료 대상)' : '') + (d.impl === false ? ' (미구현)' : ''), regionId: null, waves: [[{ type: t, n }].concat(ally), [{ type: t, n: n + 1 }].concat(ally)], objective: 'clear', arena: d.arena || 'forest', desc: d.readme, impl: d.impl !== false }); }
    for (const c of PA.LAB_COMBOS) list.push(Object.assign({}, c, { id: 'combo:' + c.id, comboId: c.id, group: '조합 프리셋', regionId: c.regionId || null, objective: c.objective || 'clear', arena: c.arena || 'forest' }));
    list.push({ id: 'boss', group: '보스', name: PA.BOSS.name + ' — ' + PA.BOSS.title, regionId: 'boss', waves: [], objective: 'boss', arena: 'clearing', boss: true, desc: PA.ENEMIES.boss.readme });
    return list;
  }
  function enemyPreset(id) { return enemyPresets().find(p => p.id === id) || null; }

  // ---------- 빌드 프리셋 ----------
  function growthFromPreset(preset) {
    const g = PA.Growth.newGrowth(preset.growth.weapons[0].id), gp = preset.growth;
    g.weapons = gp.weapons.map(w => ({ id: w.id, level: w.level || 1, mods: (w.mods || []).slice() }));
    g.commons = Object.assign({}, gp.commons || {}); g.passives = Object.assign({}, gp.passives || {});
    if (gp.e) g.skills.e = { id: gp.e.id, level: gp.e.level || 1, variant: gp.e.variant || null };
    if (gp.q) g.skills.q = { id: 'slowfield', level: gp.q.level || 1, variant: gp.q.variant || null };
    g.level = 1 + pickCount(g); g.xp = 0;
    return g;
  }
  // 성장 선택 횟수 환산: 새 무기(시작 제외) + 무기 레벨(−1) + 방식 + 공통 단계 + 패시브 단계 + E 습득·레벨·변형 + Q 레벨·변형
  function pickCount(g) {
    let n = Math.max(0, g.weapons.length - 1);
    for (const w of g.weapons) n += (w.level - 1) + w.mods.length;
    for (const k in g.commons) n += g.commons[k] || 0;
    for (const k in g.passives) n += g.passives[k] || 0;
    if (g.skills.e) n += 1 + (g.skills.e.level - 1) + (g.skills.e.variant ? 1 : 0);
    if (g.skills.q) n += (g.skills.q.level - 1) + (g.skills.q.variant ? 1 : 0);
    return n;
  }
  // 게임 규칙 위반 검사. 반환: 문제 문자열 목록(비면 합법)
  function validateBuild(preset) {
    const errs = [], g = growthFromPreset(preset), s = S();
    if (g.weapons.length < 1 || g.weapons.length > s.weapons) errs.push('무기 수 ' + g.weapons.length);
    const ids = new Set();
    for (const w of g.weapons) { const d = PA.WEAPONS[w.id]; if (!d || !d.impl) { errs.push('무기 없음 ' + w.id); continue; } if (ids.has(w.id)) errs.push('무기 중복 ' + w.id); ids.add(w.id); if (w.level < 1 || w.level > s.weaponMax) errs.push(`${w.id} 레벨 ${w.level}`); if (w.mods.length > s.weaponMods) errs.push(`${w.id} 방식 ${w.mods.length}개`); for (const mid of w.mods) if (!d.mods[mid] || !d.mods[mid].impl) errs.push(`${w.id} 방식 없음 ${mid}`); }
    const cc = Object.keys(g.commons).filter(k => g.commons[k] > 0); if (cc.length > s.commons) errs.push('공통 ' + cc.length + '개');
    for (const k of cc) { const d = PA.COMMONS[k]; if (!d) { errs.push('공통 없음 ' + k); continue; } if (g.commons[k] > d.max) errs.push(`공통 ${k} ${g.commons[k]}단계`); if (d.applies && !g.weapons.some(w => d.applies(PA.WEAPONS[w.id]))) errs.push(`공통 ${k} 적용 대상 없음`); if (d.requiresAny && !d.requiresAny.some(r => r === 'common:ember' ? g.commons.ember > 0 : r === 'weapon:ember' ? g.weapons.some(w => w.id === 'ember') : false)) errs.push(`공통 ${k} 전제 미충족`); }
    const pc = Object.keys(g.passives).filter(k => g.passives[k] > 0); if (pc.length > s.passives) errs.push('패시브 ' + pc.length + '종');
    for (const k of pc) { const d = PA.PASSIVES[k]; if (!d) errs.push('패시브 없음 ' + k); else if (g.passives[k] > d.max) errs.push(`패시브 ${k} ${g.passives[k]}`); }
    if (g.skills.e) { const d = PA.SKILLS[g.skills.e.id]; if (!d || !PA.E_SKILLS.includes(g.skills.e.id)) errs.push('E 없음'); else { if (g.skills.e.level > s.skillMax) errs.push('E 레벨'); if (g.skills.e.variant && !d.variants[g.skills.e.variant]) errs.push('E 변형 없음'); } }
    if (g.skills.q.level > s.skillMax) errs.push('Q 레벨'); if (g.skills.q.variant && !PA.SKILLS.slowfield.variants[g.skills.q.variant]) errs.push('Q 변형 없음');
    const gear = preset.gear || {}; if ((gear.upgrade || 0) > PA.ITEMS.find(i => i.id === 'whetstone').costs.length) errs.push('강화 단계'); if (gear.acc && !PA.ITEMS.some(i => i.id === gear.acc && i.slot === 'acc')) errs.push('장신구 없음'); if (gear.armor && !PA.ITEMS.some(i => i.id === gear.armor && i.slot === 'armor')) errs.push('방어구 없음');
    return errs;
  }
  function describeBuild(id) {
    const p = PA.LAB.BUILDS[id]; if (!p) return null;
    const g = growthFromPreset(p), gear = p.gear || {};
    return {
      id, name: p.name, stage: p.stage, purpose: p.purpose, picks: pickCount(g), level: g.level,
      weapons: g.weapons.map(w => `${PA.WEAPONS[w.id].name} Lv${w.level}${w.mods.length ? ' [' + w.mods.map(mid => PA.WEAPONS[w.id].mods[mid].name).join(', ') + ']' : ''}`),
      commons: Object.keys(g.commons).filter(k => g.commons[k] > 0).map(k => PA.COMMONS[k].name + (PA.COMMONS[k].max > 1 ? ' ' + g.commons[k] : '')),
      passives: Object.keys(g.passives).filter(k => g.passives[k] > 0).map(k => PA.PASSIVES[k].name + ' ' + g.passives[k]),
      q: `감속장 Lv${g.skills.q.level}${g.skills.q.variant ? ' · ' + PA.SKILLS.slowfield.variants[g.skills.q.variant].name : ''}`,
      e: g.skills.e ? `${PA.SKILLS[g.skills.e.id].name} Lv${g.skills.e.level}${g.skills.e.variant ? ' · ' + PA.SKILLS[g.skills.e.id].variants[g.skills.e.variant].name : ''}` : '없음',
      gear: [gear.upgrade ? `대장간 강화 +${gear.upgrade}` : null, gear.acc ? PA.ITEMS.find(i => i.id === gear.acc).name : null, gear.armor ? PA.ITEMS.find(i => i.id === gear.armor).name : null].filter(Boolean),
      errors: validateBuild(p),
    };
  }

  // ---------- 회차·전투 생성 ----------
  function makeRun(cfg) {
    const preset = PA.LAB.BUILDS[cfg.build], run = PA.Run.newRun(cfg.seed, preset.growth.weapons[0].id);
    run.growth = growthFromPreset(preset);
    const gear = preset.gear || {};
    run.gear.upgrade = gear.upgrade || 0; if (gear.acc) { run.owned.push(gear.acc); run.gear.acc = gear.acc; } if (gear.armor) { run.owned.push(gear.armor); run.gear.armor = gear.armor; }
    run.layout = cfg.layout || 'classic';
    run.hp = PA.Run.build(run).hpMax; run.lab = true;
    return run;
  }
  function makeCombat(cfg, run) {
    const ep = enemyPreset(cfg.enemy), build = PA.Run.build(run);
    const arena = cfg.arena === 'auto' ? (ep.arena || 'forest') : cfg.arena;
    const common = { build, hp: build.hpMax, seed: cfg.seed, arena, hpMult: cfg.hp, timeLimit: cfg.time, fixedBuild: cfg.growth !== 'grow', regionId: ep.regionId, labText: labText(cfg), overlapLimit: cfg.overlap >= 0 ? cfg.overlap : (ep.overlapLimit || 0) };
    if (ep.boss) return PA.Combat.create(Object.assign(common, { boss: true, waves: [] }));
    let waves = ep.waves.map(w => w.map(g => Object.assign({}, g)));
    if (cfg.deep && ep.regionId && ep.regionId !== 'lab') { const r2 = Object.assign({}, run, { layout: cfg.enemy.startsWith('trial:') ? 'trial' : 'classic' }); waves = PA.Run.encounterWaves(ep.regionId, true, r2); }
    return PA.Combat.create(Object.assign(common, { waves, objective: cfg.deep && ep.regionId ? 'elite' : (ep.objective || 'clear') }));
  }
  function labText(cfg) { const ep = enemyPreset(cfg.enemy), b = PA.LAB.BUILDS[cfg.build]; return `시험실 · ${ep ? ep.name : cfg.enemy} · 체력 ×${cfg.hp.normal}/${cfg.hp.elite}/${cfg.hp.boss} · ${b ? b.name : cfg.build} · 시드 ${cfg.seed} · ${cfg.control === 'bot' ? '봇 ' + PA.Bot.POLICIES[cfg.bot].name : '직접 조작'} · ${cfg.growth === 'grow' ? '성장' : '빌드 고정'} · 제한 ${cfg.time}초`; }

  // ---------- 결과 ----------
  function result(cfg, st) { const s = PA.Combat.summary(st); s.config = Object.assign({}, cfg, { hp: Object.assign({}, cfg.hp) }); s.configText = encode(cfg); s.at = Date.now(); return s; }
  const CSV_COLS = ['at', 'version', 'configText', 'status', 'elapsed', 'hp', 'hpMax', 'damageTaken', 'absorbed', 'kills', 'specialUses', 'eUses', 'dodges', 'xp', 'levelUps', 'dmgTotal', 'enemiesSpawned', 'enemiesKilled', 'prepared', 'executed', 'diedBeforeAttack', 'ttkAvg', 'takenBy', 'dmgBy'];
  function csvRow(r) {
    const en = Object.values(r.enemies || {}), sum = (k) => en.reduce((a, e) => a + (e[k] || 0), 0);
    const ttk = en.flatMap(e => e.ttkAvg != null ? [e.ttkAvg] : []); const ttkAvg = ttk.length ? Math.round(ttk.reduce((a, b) => a + b, 0) / ttk.length * 100) / 100 : '';
    const takenBy = Object.keys(r.taken || {}).map(k => `${k}:${Math.round(r.taken[k])}`).join(' '), dmgBy = Object.keys(r.dmg || {}).map(k => `${k}:${r.dmg[k].amount}`).join(' ');
    const vals = { at: new Date(r.at || 0).toISOString(), version: r.version, configText: r.configText, status: r.status, elapsed: r.elapsed, hp: r.hp, hpMax: r.hpMax, damageTaken: r.damageTaken, absorbed: r.absorbed, kills: r.kills, specialUses: r.specialUses, eUses: r.eUses, dodges: r.dodges, xp: r.xp, levelUps: r.levelUps, dmgTotal: r.dmgTotal, enemiesSpawned: sum('spawned'), enemiesKilled: sum('killed'), prepared: sum('prepared'), executed: sum('executed'), diedBeforeAttack: sum('diedBeforeAttack'), ttkAvg, takenBy, dmgBy };
    return CSV_COLS.map(k => { const v = vals[k] == null ? '' : String(vals[k]); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }).join(',');
  }
  function toCsv(results) { return [CSV_COLS.join(',')].concat(results.map(csvRow)).join('\n'); }

  // ---------- 저장(시험실 전용 키) ----------
  function saveConfig(cfg, storage) { storage = storage || globalThis.localStorage; try { storage.setItem(LAB_KEY, encode(cfg)); } catch (e) {} }
  function loadConfig(storage) { storage = storage || globalThis.localStorage; try { const s = storage.getItem(LAB_KEY); return s ? decode(s) : defaultConfig(); } catch (e) { return defaultConfig(); } }
  function saveResults(list, storage) { storage = storage || globalThis.localStorage; try { storage.setItem(RESULTS_KEY, JSON.stringify(list.slice(-30))); } catch (e) {} }
  function loadResults(storage) { storage = storage || globalThis.localStorage; try { const s = storage.getItem(RESULTS_KEY); return s ? JSON.parse(s) : []; } catch (e) { return []; } }

  return { LAB_KEY, RESULTS_KEY, defaultConfig, encode, decode, normalize, enemyPresets, enemyPreset, growthFromPreset, pickCount, validateBuild, describeBuild, makeRun, makeCombat, labText, result, csvRow, toCsv, CSV_COLS, saveConfig, loadConfig, saveResults, loadResults };
})();
