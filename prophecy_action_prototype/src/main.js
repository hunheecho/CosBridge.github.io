// 메인 루프·입력·화면 전환. 시뮬레이션은 고정 시간 단계로만 진행한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

(function () {
  const G = {
    screen: 'title', run: null, saved: null, sortie: null, combat: null, offers: null, lastReward: null, lastStats: null, lastResult: null,
    paused: false, debug: false, overlay: null, scenario: null,
    input: PA.Input.create(), acc: 0, last: 0, endTimer: 0, eventCounts: {},
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
      reward: () => S.reward(G), after: () => S.after(G), defeat: () => S.defeat(G), endday_confirm: () => S.enddayConfirm(G), bossday: () => S.bossday(G), scenario_end: () => S.scenarioEnd(G),
    }[name];
    uiEl.innerHTML = html ? html() : '';
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
  function pauseCombat(on) { if (G.screen !== 'combat') return; G.paused = on; PA.Input.setBlocked(G.input, on); if (on) openOverlay('pause'); else closeOverlay(); }

  // ---------- 회차 흐름 ----------
  function saveRun() { if (G.run && !G.scenario) PA.Run.save(G.run); }
  function goBase() { if (G.run.ended) { show('bossday'); return; } saveRun(); show('base'); }
  function leaveScenario() { if (G.scenario) { G.scenario = null; try { history.replaceState(null, '', location.pathname); } catch (e) {} } }
  function newRun() { leaveScenario(); G.run = PA.Run.newRun(); G.sortie = null; G.combat = null; saveRun(); show('base'); }
  function startSortie(regionId) {
    G.sortie = PA.Run.startSortie(G.run, regionId);
    saveRun(); // 출격 비용은 지불된 상태로 저장(전투 중 종료 시 복구 기준)
    startEncounter();
  }
  function startEncounter() {
    const run = G.run, s = G.sortie;
    G.combat = PA.Combat.create({
      build: PA.Run.build(run), hp: run.hp, seed: s.seed + s.encounters * 1000 + (s.deep ? 7 : 0),
      waves: PA.Run.encounterWaves(s.regionId, s.deep), objective: PA.Run.encounterObjective(s.regionId, s.deep),
    });
    G.endTimer = 0; G.acc = 0; G.paused = false; G.eventCounts = {}; PA.Input.setBlocked(G.input, false); closeOverlay();
    show('combat');
  }
  function onEncounterEnd() {
    const c = G.combat, run = G.run, s = G.sortie;
    G.lastStats = Object.assign({}, c.stats);
    G.lastResult = c.status;
    if (G.scenario) { show('scenario_end'); return; }
    const eliteKilled = c.enemies.some(e => e.elite && e.dead) || c.status === 'won' && c.objective === 'elite';
    if (c.status === 'won') {
      const reward = PA.Run.rollReward(run, s, c.rng, { chestGold: c.stats.chestGold, eliteKilled });
      PA.Run.applyEncounterResult(run, s, 'won', reward, c.player.hp);
      G.lastReward = reward;
      G.offers = PA.Run.augmentOffers(run, c.rng, 3);
      show('reward');
    } else {
      PA.Run.applyEncounterResult(run, s, 'lost', null, 0);
      PA.Run.defeat(run, s);
      saveRun();
      show('defeat');
    }
  }

  // ---------- 동작 처리 ----------
  const actions = {
    'continue': () => { leaveScenario(); G.run = G.saved; G.sortie = null; G.combat = null; goBase(); },
    'newrun': () => { if (G.saved) show('newrun_confirm'); else newRun(); },
    'newrun-confirm': () => newRun(),
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
    'save-quit': () => { saveRun(); G.saved = PA.Run.load(); show('title'); },
    'sortie': (id) => startSortie(id),
    'buy': (id) => { PA.Run.buy(G.run, id); PA.Audio.play('buy'); saveRun(); show('shop'); },
    'target': (id) => { PA.Run.setTarget(G.run, id); saveRun(); show('shop'); },
    'sell': (id) => { PA.Run.sell(G.run, id, 1); saveRun(); show('shop'); },
    'toggle-weapon': () => { if (G.run.gear.weapon === 'pierce') PA.Run.unequipWeapon(G.run); else PA.Run.equip(G.run, 'pierce_sword'); saveRun(); show(G.screen); },
    'pick': (id) => { PA.Run.takeAugment(G.run, id); G.offers = null; saveRun(); show('after'); },
    'skip': () => { PA.Run.skipAugment(G.run); G.offers = null; saveRun(); show('after'); },
    'deep': () => { PA.Run.deepExplore(G.run, G.sortie); saveRun(); startEncounter(); },
    'return': () => { PA.Run.returnToBase(G.run, G.sortie); G.sortie = null; goBase(); },
    'resume': () => pauseCombat(false),
    'give-up': () => { closeOverlay(); G.paused = false; if (G.combat) { G.combat.player.hp = 0; G.combat.player.dead = true; G.combat.status = 'lost'; G.endTimer = 10; } },
    'scenario-again': () => startScenario(G.scenario),
  };
  function dispatch(action, arg) {
    PA.Audio.init(); PA.Audio.play('ui');
    const f = actions[action]; if (!f) return;
    try { f(arg); } catch (e) { console.error(e); alert(e.message); }
  }

  // ---------- 시나리오(시험 전투) ----------
  function parseScenario() {
    const q = new URLSearchParams(location.search);
    if (!q.get('scenario')) return null;
    return { region: q.get('scenario'), seed: parseInt(q.get('seed') || '1', 10), aug: (q.get('aug') || '').split(',').filter(Boolean), weapon: q.get('weapon') || 'sword', deep: q.get('deep') === '1', upgrade: parseInt(q.get('upgrade') || '0', 10) };
  }
  function startScenario(sc) {
    G.scenario = sc;
    const run = PA.Run.newRun(sc.seed);
    run.gear.weapon = sc.weapon === 'pierce' ? 'pierce' : 'sword';
    run.gear.upgrade = sc.upgrade || 0;
    for (const a of sc.aug) { const [id, lv] = a.split(':'); run.augments[id] = parseInt(lv || '1', 10); }
    if (run.augments.barrier) {} // 파생은 Build.derive에서
    run.hp = PA.Run.build(run).hpMax;
    G.run = run;
    G.sortie = { regionId: sc.region, deep: sc.deep, loot: { gold: 0, mats: {} }, encounters: 0, seed: sc.seed };
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
      let inp = inputState(); let first = true; let guard = 0;
      while (G.acc >= STEP && guard++ < 12) {
        PA.Combat.step(G.combat, inp, STEP);
        if (first) { PA.Input.consumePressed(G.input); inp = inputState(); first = false; }
        G.acc -= STEP;
      }
      if (guard >= 12) G.acc = 0;
      for (const e of G.combat.events) G.eventCounts[e.name] = (G.eventCounts[e.name] || 0) + 1;
      for (const e of G.combat.events) PA.Audio.play(e.name === 'hit' ? (e.crit ? 'crit' : 'hit') : ({ kill: 'kill', hurt: 'hurt', lock: 'lock', dodge: 'dodge', perfect: 'perfect', special: 'special', chest: 'chest', win: 'win', lose: 'lose', wave: 'wave', shoot: 'shoot', spore: 'spore', explode: 'explode', shatter: 'shatter', burst: 'burst', bite: 'bite', swing: 'swing' }[e.name] || null));
      G.combat.events.length = 0;
      if (G.combat.status !== 'running') { G.endTimer += dt; if (G.endTimer >= 1.3) onEncounterEnd(); }
    }
    render();
  }

  // ---------- 입력 ----------
  function onKeyDown(e) {
    if (e.repeat) return;
    if (e.code === 'F3') { G.debug = !G.debug; e.preventDefault(); return; }
    if (G.screen === 'combat') {
      if (e.code === 'Escape') { if (G.overlay === 'controls') openOverlay('pause'); else pauseCombat(!G.paused); e.preventDefault(); return; }
      if (['Space', 'KeyQ', 'KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
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
    fitCanvas();
    G.saved = PA.Run.load();
    const sc = parseScenario();
    if (sc) startScenario(sc); else show('title');
    requestAnimationFrame(frame);
  }
  if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', init); else init();
})();
