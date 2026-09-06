// 메인 루프·입력·화면 전환. 시뮬레이션은 고정 시간 단계로만 진행한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

(function () {
  const G = {
    screen: 'title', run: null, saved: null, sortie: null, combat: null, offers: null, lastReward: null, lastStats: null, lastResult: null,
    paused: false, debug: false, overlay: null, scenario: null,
    input: PA.Input.create(), acc: 0, last: 0, endTimer: 0, eventCounts: {},
    lab: { cfg: null }, labResults: [], labResult: null, labCsv: null, botMem: null, botLast: null, botT: 0,
  };
  window.PA_G = G; // 검증용 훅(사람용 UI 아님)

  const $ = (s) => document.querySelector(s);
  let canvas, ctx, uiEl, overlayEl, stageEl;

  // ---------- 화면 ----------
  function show(name) {
    G.screen = name;
    const S = PA.Screens;
    const html = {
      title: () => S.title(G), newrun_confirm: () => S.newrunConfirm(G), base: () => S.base(G), map: () => S.map(G), shop: () => S.shop(G),
      reward: () => S.reward(G), after: () => S.after(G), defeat: () => S.defeat(G), endday_confirm: () => S.enddayConfirm(G), scenario_end: () => S.scenarioEnd(G),
      boss_defeat: () => S.bossDefeat(G), event: () => S.event(G), boss_victory: () => S.bossVictory(G), pick_start: () => S.pickStart(G), migration: () => S.migration(G),
      lab: () => S.lab(G), lab_result: () => S.labResult(G),
    }[name];
    uiEl.innerHTML = html ? html() : '';
    if (html) { try { S.paintPortraits(); } catch (e) {} }
    uiEl.hidden = !html;
    stageEl.hidden = !!html;
    if (!html) fitCanvas();
    window.scrollTo(0, 0);
  }
  function openOverlay(kind) {
    G.overlay = kind;
    overlayEl.innerHTML = kind === 'pause' ? PA.Screens.pause(G) : PA.Screens.controls();
    overlayEl.hidden = false;
    const vol = $('#vol'), mute = $('#mute');
    if (vol) vol.addEventListener('input', () => PA.Audio.setVolume(vol.value / 100));
    if (mute) mute.addEventListener('change', () => PA.Audio.setMuted(mute.checked));
  }
  function closeOverlay() { G.overlay = null; overlayEl.hidden = true; overlayEl.innerHTML = ''; }
  // ---------- 레벨업 선택(전투 중: 정지 + 오버레이 / 화면: 오버레이) ----------
  function openChoice(offer) {
    G.choice = offer;
    if (G.screen === 'combat') { G.paused = true; PA.Input.setBlocked(G.input, true); }
    G.overlay = 'choice';
    overlayEl.innerHTML = PA.Screens.levelCards(G, offer, G.run); overlayEl.hidden = false;
  }
  function closeChoice() {
    G.choice = null; closeOverlay();
    if (G.screen === 'combat') { G.paused = false; PA.Input.setBlocked(G.input, false); G.last = 0; }
  }
  // 전투 중 레벨업: 미처리 선택이 있으면 하나씩 제시
  function offerPendingLevelUps(ctx) {
    const g = G.run.growth;
    if (g.pendingLevelUps <= 0) return false;
    openChoice(PA.Growth.generateOffer(G.run, Object.assign({ pool: 'level' }, ctx || {})));
    saveRun(); // 레벨업 시점의 레벨·경험치·보류 제시를 저장(새로고침 재굴림 방지, 미처리 선택 보존)
    return true;
  }
  function afterChoice() {
    if (!G.scenario) saveRun();
    if (G.screen === 'combat' && G.combat) {
      PA.Combat.rebuild(G.combat, PA.Run.build(G.run));
      closeChoice();
      if (G.run.growth.pendingLevelUps > 0) offerPendingLevelUps({ regionId: G.sortie && G.sortie.regionId });
    } else {
      closeChoice();
      const off = G.screen !== 'reward' ? PA.Flow.nextOffer(G.run, { regionId: G.sortie && G.sortie.regionId }) : null; // 보상 화면은 버튼으로 다음 선택을 이어감
      if (off) { openChoice(off); saveRun(); }
      else if (G.screen === 'after' && G.sortie && G.sortie.event && !G.sortie.event.resolved) show('event'); // 재접속 뒤 보류 3택을 마치면 미처리 사건으로 이어감
      else show(G.screen);
    }
  }
  function pauseCombat(on) { if (G.screen !== 'combat') return; G.paused = on; PA.Input.setBlocked(G.input, on); if (on) openOverlay('pause'); else closeOverlay(); }

  // ---------- 회차 흐름 ----------
  function saveRun() { if (G.run && !G.scenario) PA.Run.save(G.run); }
  function goBase() { saveRun(); if (G.run.growth && G.run.growth.migrationPending) { show('migration'); return; } show('base'); const g = G.run.growth; if (g && (g.pendingDeepPick || g.pendingBossPick || g.pendingMissionPick || (g.pendingOffer && g.pendingOffer.pool !== 'level'))) { const off = PA.Flow.nextOffer(G.run); if (off) { openChoice(off); saveRun(); } } } // 7일차(boss_prep/cleared)는 base가 최종 준비 화면을 그린다
  function leaveScenario() { if (G.scenario) { G.scenario = null; try { history.replaceState(null, '', location.pathname); } catch (e) {} } }
  function newRun() { leaveScenario(); G.startAll = false; show('pick_start'); }
  function startRun(weaponId) { const modeEl = $('#start-mode'); G.run = PA.Run.newRun(undefined, weaponId, modeEl ? modeEl.value : 'trio'); const lay = $('#start-layout'), dif = $('#start-difficulty'); if (lay && PA.LAYOUTS[lay.value]) G.run.layout = lay.value; if (dif && PA.DIFFICULTY.candidates[dif.value]) G.run.difficulty = dif.value; G.sortie = null; G.combat = null; saveRun(); show('base'); }
  function startSortie(regionId) {
    G.sortie = PA.Run.startSortie(G.run, regionId);
    saveRun(); // 출격 비용은 지불된 상태로 저장(전투 중 종료 시 복구 기준)
    startEncounter();
  }
  function startEncounter() {
    const run = G.run, s = G.sortie;
    G.choice = null;
    if (s.regionId === 'boss') {
      G.combat = PA.Flow.makeBossEncounter(run, s); // 단계별 보스·체력 후보(공유 흐름)
    } else G.combat = PA.Flow.makeEncounter(run, s); // 시드·웨이브·목표·배율은 공유 흐름(시뮬레이터와 동일)
    G.endTimer = 0; G.acc = 0; G.paused = false; G.eventCounts = {}; PA.Input.setBlocked(G.input, false); closeOverlay();
    show('combat');
  }
  function startBoss() {
    G.sortie = PA.Run.startBoss(G.run);
    saveRun(); // 보스 직전 상태 저장: 전투 중 종료 시 최종 준비에서 다시 시작
    startEncounter();
  }
  function onEncounterEnd() {
    const c = G.combat, run = G.run, s = G.sortie;
    G.lastStats = Object.assign({}, c.stats);
    G.lastResult = c.status;
    if (G.scenario && G.scenario.lab) { finishLab(); return; }
    if (G.scenario) { show('scenario_end'); return; }
    if (c.mode === 'boss') {
      if (c.status === 'won') {
        const hadFirst = !!run.bossClear;
        const rec = PA.Flow.settleBossVictory(run, c); G.lastRecord = rec; // 정산 1회: 기록·다음 단계·희귀 보상 보류(마지막 보스는 없음)
        const R = PA.Run.saveRecord(rec); G.firstClearNew = !hadFirst && R.firstClear && R.firstClear.at === rec.at;
        saveRun(); G.sortie = null; show('boss_victory');
      } else { PA.Flow.settleBossDefeat(run, c); saveRun(); G.sortie = null; show('boss_defeat'); }
      return;
    }
    if (c.status === 'won') {
      G.lastReward = PA.Flow.settleVictory(run, s, c); G.offers = null; // 정산은 공유 흐름에서 정확히 1회(전리품·지역 경험치·더 깊이 3택 보류 등록)
      saveRun();
      show('reward');
      if (run.growth.pendingLevelUps > 0) offerPendingLevelUps({ regionId: s.regionId });
    } else {
      PA.Flow.settleDefeat(run, s, c);
      saveRun();
      show('defeat');
    }
  }

  // ---------- 전투 시험실(정식 회차와 분리: 저장 키·입력·배율이 회차로 새지 않는다) ----------
  function enterLab(cfg) {
    leaveScenario(); G.run = null; G.sortie = null; G.combat = null; G.saved = PA.Run.load();
    G.lab.cfg = cfg || PA.Lab.loadConfig(); G.labResults = PA.Lab.loadResults(); G.labCsv = null;
    show('lab');
  }
  // 화면의 입력 요소 → 설정
  function readLabForm() {
    const c = G.lab.cfg, v = (id) => { const el = $('#' + id); return el ? el.value : null; };
    if (v('lab-enemy')) c.enemy = v('lab-enemy'); if (v('lab-arena')) c.arena = v('lab-arena'); if (v('lab-build')) c.build = v('lab-build'); if (v('lab-bot')) c.bot = v('lab-bot');
    if (v('lab-hp-normal')) c.hp = { normal: parseFloat(v('lab-hp-normal')), elite: parseFloat(v('lab-hp-elite')), boss: parseFloat(v('lab-hp-boss')) };
    if (v('lab-seed') != null) c.seed = parseInt(v('lab-seed') || '0', 10); if (v('lab-time')) c.time = parseInt(v('lab-time'), 10); if (v('lab-overlap') != null) c.overlap = parseInt(v('lab-overlap'), 10);
    const deep = $('#lab-deep'); if (deep) c.deep = deep.checked;
    const ctl = document.querySelector('input[name=lab-control]:checked'); if (ctl) c.control = ctl.value;
    const gr = document.querySelector('input[name=lab-growth]:checked'); if (gr) c.growth = gr.value;
    PA.Lab.normalize(c); PA.Lab.saveConfig(c);
  }
  function startLab(cfg) {
    G.lab.cfg = PA.Lab.normalize(cfg || G.lab.cfg); PA.Lab.saveConfig(G.lab.cfg);
    const c = G.lab.cfg; G.scenario = { lab: true }; G.choice = null;
    G.run = PA.Lab.makeRun(c);
    const ep = PA.Lab.enemyPreset(c.enemy);
    G.sortie = { regionId: ep.regionId || 'lab', deep: c.deep, loot: { gold: 0, mats: {} }, encounters: 0, seed: c.seed, lab: true };
    G.combat = PA.Lab.makeCombat(c, G.run);
    G.botMem = {}; G.botLast = null; G.botT = 0;
    G.endTimer = 0; G.acc = 0; G.paused = false; G.eventCounts = {}; PA.Input.setBlocked(G.input, false); closeOverlay();
    show('combat');
  }
  function finishLab() {
    const c = G.combat; c.levelUps = 0;
    G.labResult = PA.Lab.result(G.lab.cfg, c);
    G.labResults = (G.labResults || []).concat([G.labResult]).slice(-30); PA.Lab.saveResults(G.labResults);
    G.combat = null; G.run = null; G.sortie = null; G.scenario = null; closeOverlay(); PA.Input.clearAll(G.input);
    try { history.replaceState(null, '', location.pathname); } catch (e) {}
    show('lab_result');
  }
  function exitLab() { leaveScenario(); G.run = null; G.sortie = null; G.combat = null; G.paused = false; G.overlay = null; closeOverlay(); PA.Input.setBlocked(G.input, false); PA.Input.clearAll(G.input); G.saved = PA.Run.load(); show('title'); }
  // 봇 조작: 판단은 고정 시뮬레이션 단계 기준(PA.Bot.stepInput). 렌더 프레임 속도와 무관하게 헤드리스와 같은 입력 일정

  // ---------- 동작 처리 ----------
  const actions = {
    'continue': () => { leaveScenario(); G.run = G.saved; G.sortie = null; G.combat = null; if (G.run.pendingSortie) { G.sortie = G.run.pendingSortie; const step = PA.Flow.afterCombatStep(G.run, G.sortie); if (step === 'offer') { show('after'); openChoice(PA.Flow.nextOffer(G.run, { regionId: G.sortie.regionId })); } else show(step); return; } goBase(); }, // 전투 뒤 안전 화면에서 종료했다면 그 자리(보상 선택·사건·다음 행동)로 복귀
    'newrun': () => { if (G.saved) show('newrun_confirm'); else newRun(); },
    'newrun-confirm': () => newRun(),
    'start-weapon': (id) => startRun(id),
    'start-all': () => { G.startAll = true; show('pick_start'); },
    'pick': (key) => { const off = G.choice; if (!off) return; const c = off.choices.find(x => x.key === key); if (!c) return; PA.Flow.resolveOffer(G.run, off, c); PA.Audio.play('buy'); afterChoice(); },
    'skip': () => { const off = G.choice; if (!off) return; PA.Flow.resolveOffer(G.run, off, null); afterChoice(); },
    'resolve-levelup': () => { offerPendingLevelUps({ regionId: G.sortie && G.sortie.regionId }); },
    'reroll': () => { const off = PA.Flow.rerollOffer(G.run); openChoice(off); saveRun(); },
    'mod-swap': (arg) => { const [wid, mid] = arg.split(':'); const off = PA.Flow.modSwapOffer(G.run, wid, mid); saveRun(); if (off) openChoice(off); else show('base'); },
    'after-reward': () => { const step = PA.Flow.afterCombatStep(G.run, G.sortie); if (step === 'offer') { openChoice(PA.Flow.nextOffer(G.run, { regionId: G.sortie.regionId })); saveRun(); return; } show(step); }, // 보류 제시 → 레벨업 → 임무/사건/더 깊이 3택 → 사건 → 다음 행동(공유 흐름)
    'event-choice': (id) => { const r = PA.Events.resolve(G.run, G.sortie, id); saveRun(); if (r.next === 'fight' || r.next === 'deep') { startEncounter(); return; } if (r.next === 'offer') { const off = PA.Flow.nextOffer(G.run, { regionId: G.sortie.regionId }); if (off) { G.screen = 'after'; uiEl.innerHTML = PA.Screens.after(G); openChoice(off); saveRun(); return; } } show('after'); },
    'mig-toggle': (id) => { G.migSel = G.migSel || []; if (G.migSel.includes(id)) G.migSel = G.migSel.filter(x => x !== id); else if (G.migSel.length < 3) G.migSel.push(id); show('migration'); },
    'mig-confirm': () => { PA.Growth.resolveMigration(G.run, G.migSel || []); G.migSel = null; saveRun(); goBase(); },
    'title': () => { leaveScenario(); G.saved = PA.Run.load(); show('title'); },
    'controls': () => openOverlay('controls'),
    'show-controls': () => openOverlay('controls'),
    'close-overlay': () => { if (G.paused) openOverlay('pause'); else closeOverlay(); },
    'base': () => goBase(),
    'map': () => show('map'),
    'shop': () => show('shop'),
    'rest': () => { PA.Run.rest(G.run); saveRun(); show('base'); },
    'endday-confirm': () => show('endday_confirm'),
    'endday': () => { PA.Run.endDay(G.run); saveRun(); goBase(); },
    'boss-start': () => startBoss(),
    'equip': (id) => { PA.Run.equip(G.run, id); saveRun(); show(G.screen); },
    'unequip': (slot) => { PA.Run.unequip(G.run, slot); saveRun(); show(G.screen); },
    'save-quit': () => { saveRun(); G.saved = PA.Run.load(); show('title'); },
    'sortie': (id) => startSortie(id),
    'mission': (id) => { G.sortie = PA.Sortie.start(G.run, id); saveRun(); startEncounter(); },
    'buy': (id) => { PA.Run.buy(G.run, id); PA.Audio.play('buy'); saveRun(); show('shop'); },
    'target': (id) => { PA.Run.setTarget(G.run, id); saveRun(); show('shop'); },
    'sell': (id) => { PA.Run.sell(G.run, id, 1); saveRun(); show('shop'); },
    'toggle-weapon': () => { if (G.run.gear.weapon === 'pierce') PA.Run.unequipWeapon(G.run); else PA.Run.equip(G.run, 'pierce_sword'); saveRun(); show(G.screen); },
    'deep': () => { PA.Run.deepExplore(G.run, G.sortie); saveRun(); startEncounter(); },
    'return': () => { PA.Flow.returnHome(G.run, G.sortie); G.sortie = null; goBase(); },
    'resume': () => pauseCombat(false),
    'give-up': () => { closeOverlay(); G.paused = false; PA.Input.setBlocked(G.input, false); if (G.combat) { G.combat.player.hp = 0; G.combat.player.dead = true; G.combat.status = 'lost'; G.endTimer = 10; } },
    'scenario-again': () => startScenario(G.scenario),
    'lab': () => { if (G.screen === 'lab_result') { G.combat = null; show('lab'); return; } enterLab(); },
    'quick-run': (stage) => { leaveScenario(); G.run = PA.Lab.quickRun(Number(stage) || 0); G.sortie = null; G.combat = null; saveRun(); goBase(); }, // 검증 메뉴: 3보스 회차 관문 직전(현재 저장을 덮어씀)
    'lab-start': () => { readLabForm(); startLab(); },
    'lab-restart': () => startLab(G.lab.cfg),
    'lab-restart-hp': () => { const el = $('#lab-result-hp'); const c = Object.assign({}, G.lab.cfg, { hp: Object.assign({}, G.lab.cfg.hp) }); if (el) c.hp.normal = parseFloat(el.value); startLab(c); },
    'lab-apply': () => { const ta = $('#lab-config'); if (ta) { G.lab.cfg = PA.Lab.decode(ta.value); PA.Lab.saveConfig(G.lab.cfg); } show('lab'); },
    'lab-load': (text) => { G.lab.cfg = PA.Lab.decode(text); PA.Lab.saveConfig(G.lab.cfg); show('lab'); },
    'lab-reset': () => { G.lab.cfg = PA.Lab.defaultConfig(); PA.Lab.saveConfig(G.lab.cfg); show('lab'); },
    'lab-csv': () => { G.labCsv = PA.Lab.toCsv(G.labResults || []); show('lab'); },
    'lab-clear-results': () => { G.labResults = []; G.labCsv = null; PA.Lab.saveResults([]); show('lab'); },
    'lab-abort': () => { if (G.combat && G.combat.status === 'running') { G.combat.status = 'aborted'; } closeOverlay(); G.paused = false; PA.Input.setBlocked(G.input, false); finishLab(); },
    'lab-back': () => { G.combat = null; G.run = null; G.sortie = null; G.scenario = null; G.paused = false; closeOverlay(); PA.Input.setBlocked(G.input, false); PA.Input.clearAll(G.input); enterLab(G.lab.cfg); },
    'lab-exit': () => exitLab(),
  };
  function dispatch(action, arg) {
    PA.Audio.init(); PA.Audio.play('ui');
    const f = actions[action]; if (!f) return;
    try { f(arg); } catch (e) { console.error(e); alert(e.message); }
  }

  // ---------- 시나리오(시험 전투) ----------
  function parseScenario() {
    const q = new URLSearchParams(location.search);
    if (q.get('lab') != null) return { lab: true, cfg: PA.Lab.decode(q.get('lab')) };
    if (!q.get('scenario')) return null;
    return { region: q.get('scenario'), arena: q.get('arena') || null, acc: q.get('acc') || null, armor: q.get('armor') || null, seed: parseInt(q.get('seed') || '1', 10), aug: (q.get('aug') || '').split(',').filter(Boolean), weapon: q.get('weapon') || 'sword', deep: q.get('deep') === '1', upgrade: parseInt(q.get('upgrade') || '0', 10),
      start: q.get('start') || null, weapons: (q.get('weapons') || '').split(',').filter(Boolean), commons: (q.get('commons') || '').split(',').filter(Boolean), passives: (q.get('passives') || '').split(',').filter(Boolean), e: q.get('e') || null, q: q.get('q') || null, level: parseInt(q.get('level') || '0', 10), rewards: (q.get('rewards') || '').split(',').filter(Boolean) };
  }
  function startScenario(sc) {
    G.scenario = sc;
    const run = PA.Run.newRun(sc.seed, sc.start || (sc.weapon === 'pierce' ? 'spear' : 'sword'));
    run.gear.upgrade = sc.upgrade || 0;
    // v3 파라미터: weapons=spear:3:returning+brand,frost:2 commons=frost,wide:2 passives=mastery:2 e=gust:2:whirl q=slowfield:3:follow level=8 rewards=resonance
    const g = run.growth;
    for (const spec of sc.weapons) { const [id, lv, mods] = spec.split(':'); if (!PA.WEAPONS[id]) continue; const w = PA.Growth.weaponOf(g, id) || (g.weapons.length < PA.GROWTH.SLOTS.weapons ? (g.weapons.push({ id, level: 1, mods: [] }), g.weapons[g.weapons.length - 1]) : null); if (!w) continue; w.level = Math.min(5, parseInt(lv || '1', 10)); w.mods = (mods || '').split('+').filter(x => PA.WEAPONS[id].mods[x]).slice(0, 2); }
    for (const spec of sc.commons) { const [id, lv] = spec.split(':'); if (PA.COMMONS[id]) g.commons[id] = Math.min(PA.COMMONS[id].max, parseInt(lv || '1', 10)); }
    for (const spec of sc.passives) { const [id, lv] = spec.split(':'); if (PA.PASSIVES[id]) g.passives[id] = Math.min(3, parseInt(lv || '1', 10)); }
    if (sc.e) { const [id, lv, v] = sc.e.split(':'); if (PA.SKILLS[id] && PA.E_SKILLS.includes(id)) g.skills.e = { id, level: Math.min(3, parseInt(lv || '1', 10)), variant: v && PA.SKILLS[id].variants[v] ? v : null }; }
    if (sc.q) { const [id, lv, v] = sc.q.split(':'); g.skills.q = { id: 'slowfield', level: Math.min(3, parseInt(lv || '1', 10)), variant: v && PA.SKILLS.slowfield.variants[v] ? v : null }; }
    for (const id of sc.rewards) if (PA.BOSS_REWARDS[id]) g.bossRewards.push(id);
    if (sc.level > 1) g.level = sc.level;
    if (sc.acc) { run.owned.push(sc.acc); run.gear.acc = sc.acc; }
    if (sc.armor) { run.owned.push(sc.armor); run.gear.armor = sc.armor; }
    if (sc.aug.length) { for (const a of sc.aug) { const [id, lv] = a.split(':'); run.augments[id] = parseInt(lv || '1', 10); } if (sc.weapon === 'pierce') { run.owned.push('pierce_sword'); run.gear.weapon = 'pierce'; } run.growth = PA.Growth.migrateFromLegacy(run); delete run.gear.weapon; if (run.growth.migrationPending) PA.Growth.resolveMigration(run, run.growth.migrationPending.commons.slice(0, 3).map(c => c.id)); } // 레거시 aug= 파라미터 호환
    run.hp = PA.Run.build(run).hpMax;
    G.run = run;
    G.sortie = { regionId: sc.region, deep: sc.deep, loot: { gold: 0, mats: {} }, encounters: 0, seed: sc.seed, arena: sc.arena };
    startEncounter();
  }

  // ---------- 캔버스 ----------
  function fitCanvas() {
    const W = PA.CONFIG.ARENA.w + PA.CONFIG.VIEW.pad * 2, H = PA.CONFIG.ARENA.h + PA.CONFIG.VIEW.pad * 2;
    const vw = window.innerWidth, vh = window.innerHeight;
    const scale = Math.min(vw / W, vh / H);
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    canvas.style.width = Math.floor(W * scale) + 'px'; canvas.style.height = Math.floor(H * scale) + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  function render() {
    if (G.screen !== 'combat' || !G.combat) return;
    PA.Render.draw(ctx, G.combat, { debug: G.debug });
    if (G.paused) { ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.fillRect(0, 0, PA.CONFIG.ARENA.w + PA.CONFIG.VIEW.pad * 2, PA.CONFIG.ARENA.h + PA.CONFIG.VIEW.pad * 2); }
  }

  // ---------- 루프 ----------
  function inputState() { return PA.Input.state(G.input); }
  function frame(ts) {
    requestAnimationFrame(frame);
    const dt = Math.min(0.1, (ts - (G.last || ts)) / 1000); G.last = ts;
    if (G.screen === 'combat' && G.combat && !G.paused) {
      G.acc += dt;
      const STEP = PA.CONFIG.STEP;
      const bot = G.scenario && G.scenario.lab && G.lab.cfg && G.lab.cfg.control === 'bot';
      let inp = bot ? null : inputState(); let first = true; let guard = 0;
      while (G.acc >= STEP && guard++ < 12) {
        PA.Combat.step(G.combat, bot ? PA.Bot.stepInput(G.combat, G.lab.cfg.bot, G.botMem) : inp, STEP);
        if (first && !bot) { PA.Input.consumePressed(G.input); inp = inputState(); first = false; } // 사람 입력: 단발 입력은 프레임의 첫 단계에서 소비
        G.acc -= STEP;
      }
      if (guard >= 12) G.acc = 0;
      for (const e of G.combat.events) G.eventCounts[e.name] = (G.eventCounts[e.name] || 0) + 1;
      for (const e of G.combat.events) PA.Audio.play(e.name === 'hit' ? (e.crit ? 'crit' : 'hit') : ({ kill: 'kill', hurt: 'hurt', lock: 'lock', dodge: 'dodge', perfect: 'perfect', special: 'special', chest: 'chest', win: 'win', lose: 'lose', wave: 'wave', shoot: 'shoot', spore: 'spore', explode: 'explode', shatter: 'shatter', burst: 'burst', bite: 'bite', swing: 'swing', boss_howl: 'boss_howl', boss_roar: 'boss_roar', boss_land: 'boss_land', boss_sweep: 'boss_sweep', boss_lock: 'boss_lock', boss_down: 'win', orb: 'orb', levelup: 'chest', skill_e: 'special' }[e.name] || null));
      G.combat.events.length = 0;
      if (G.combat.levelUps > 0 && G.combat.status === 'running' && !G.overlay) { G.combat.levelUps = 0; offerPendingLevelUps({ regionId: G.sortie && G.sortie.regionId }); }
      if (bot && G.overlay === 'choice' && G.choice) { const c = PA.Bot.pickChoice(G.choice, G.lab.cfg.seed); if (c) { PA.Growth.applyChoice(G.run, c); afterChoice(); } else actions.skip(); } // 봇 성장 모드: 카드 자동 선택
      if (G.combat.status !== 'running') { G.combat.levelUps = 0; G.endTimer += dt; if (G.endTimer >= (G.combat.mode === 'boss' && G.combat.status === 'won' ? 2.4 : 1.3)) onEncounterEnd(); }
    }
    render();
  }

  // ---------- 입력 ----------
  function onKeyDown(e) {
    if (e.repeat) return;
    if (e.code === 'F3') { G.debug = !G.debug; e.preventDefault(); return; }
    if (G.screen === 'combat') {
      if (e.code === 'Escape') { if (G.overlay === 'choice') { e.preventDefault(); return; } if (G.overlay === 'controls') openOverlay('pause'); else pauseCombat(!G.paused); e.preventDefault(); return; }
      if (['Space', 'KeyQ', 'KeyE', 'KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
      if (G.paused || G.overlay) return;          // 정지·메뉴 중 전투 입력은 버린다
      PA.Input.keyDown(G.input, e.code);
      PA.Audio.init();
    } else if (e.code === 'Enter') {
      const btn = uiEl.querySelector('button.primary:not([disabled])'); if (btn) btn.click();
    } else if (e.code === 'Escape' && G.overlay) closeOverlay();
  }
  function onKeyUp(e) { PA.Input.keyUp(G.input, e.code); }

  function init() {
    canvas = $('#game'); ctx = canvas.getContext('2d'); uiEl = $('#ui'); overlayEl = $('#overlay'); stageEl = $('#stage');
    window.addEventListener('resize', fitCanvas);
    window.addEventListener('keydown', onKeyDown); window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', () => { PA.Input.clearAll(G.input); if (G.screen === 'combat' && !G.paused && G.combat && G.combat.status === 'running') pauseCombat(true); });
    document.addEventListener('visibilitychange', () => { if (document.hidden) { PA.Input.clearAll(G.input); if (G.screen === 'combat' && !G.paused && G.combat && G.combat.status === 'running') pauseCombat(true); } });
    document.addEventListener('click', (e) => { const b = e.target.closest('[data-action]'); if (b && !b.disabled) dispatch(b.dataset.action, b.dataset.arg); });
    document.addEventListener('change', (e) => { if (G.screen === 'lab' && e.target.dataset && e.target.dataset.lab) { readLabForm(); setTimeout(() => { if (G.screen === 'lab') show('lab'); }, 0); } }); // 이벤트 처리 중 DOM 교체를 피한다(포커스 요소 제거 오류 방지)
    fitCanvas();
    G.saved = PA.Run.load();
    const sc = parseScenario();
    if (sc && sc.lab) { enterLab(sc.cfg); startLab(sc.cfg); } else if (sc) startScenario(sc); else show('title');
    requestAnimationFrame(frame);
  }
  if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', init); else init();
})();
