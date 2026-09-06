// WebAudio 합성음. 외부 파일 없음. 음량/음소거는 localStorage에 저장.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Audio = (function () {
  let ctx = null, master = null, volume = 0.5, muted = false, last = {};
  const KEY = 'prophecy_action_audio';
  function loadPrefs() { try { const s = JSON.parse(localStorage.getItem(KEY) || '{}'); if (typeof s.volume === 'number') volume = s.volume; if (typeof s.muted === 'boolean') muted = s.muted; } catch (e) {} }
  function savePrefs() { try { localStorage.setItem(KEY, JSON.stringify({ volume, muted })); } catch (e) {} }
  function init() {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
    try {
      const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
      ctx = new AC(); master = ctx.createGain(); master.gain.value = muted ? 0 : volume; master.connect(ctx.destination);
    } catch (e) { ctx = null; }
  }
  function apply() { if (master) master.gain.value = muted ? 0 : volume; savePrefs(); }
  function setVolume(v) { volume = Math.max(0, Math.min(1, v)); apply(); }
  function setMuted(b) { muted = !!b; apply(); }
  function tone(freq, dur, type, gain, sweepTo) {
    const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime;
    o.type = type || 'square'; o.frequency.setValueAtTime(freq, t);
    if (sweepTo) o.frequency.exponentialRampToValueAtTime(sweepTo, t + dur);
    g.gain.setValueAtTime(gain || 0.2, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g); g.connect(master); o.start(t); o.stop(t + dur + 0.02);
  }
  function noise(dur, gain, hp) {
    const n = Math.floor(ctx.sampleRate * dur), buf = ctx.createBuffer(1, n, ctx.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);
    const s = ctx.createBufferSource(), g = ctx.createGain(), f = ctx.createBiquadFilter();
    s.buffer = buf; f.type = hp ? 'highpass' : 'lowpass'; f.frequency.value = hp || 800;
    g.gain.value = gain || 0.2; s.connect(f); f.connect(g); g.connect(master); s.start();
  }
  const SOUNDS = {
    hit: () => { tone(320, 0.06, 'square', 0.12); noise(0.04, 0.08, 2000); },
    crit: () => { tone(520, 0.08, 'square', 0.15, 700); noise(0.05, 0.1, 2500); },
    kill: () => { tone(180, 0.15, 'triangle', 0.2, 60); noise(0.08, 0.12); },
    hurt: () => { tone(140, 0.25, 'sawtooth', 0.25, 60); noise(0.1, 0.15); },
    lock: () => { tone(900, 0.05, 'square', 0.12); setTimeout(() => ctx && tone(1100, 0.06, 'square', 0.12), 60); },
    dodge: () => noise(0.12, 0.12, 1200),
    perfect: () => { tone(1200, 0.12, 'sine', 0.2, 1800); },
    special: () => { tone(220, 0.5, 'sine', 0.2, 110); tone(330, 0.5, 'sine', 0.12, 165); },
    chest: () => { [660, 880, 1100].forEach((f, i) => setTimeout(() => ctx && tone(f, 0.12, 'triangle', 0.15), i * 70)); },
    win: () => { [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => ctx && tone(f, 0.2, 'triangle', 0.18), i * 110)); },
    lose: () => { [400, 300, 200].forEach((f, i) => setTimeout(() => ctx && tone(f, 0.3, 'sawtooth', 0.18), i * 200)); },
    wave: () => { tone(90, 0.3, 'sine', 0.25, 50); },
    shoot: () => noise(0.06, 0.1, 3000),
    spore: () => { tone(200, 0.3, 'sine', 0.15, 80); noise(0.2, 0.08); },
    explode: () => { noise(0.25, 0.25); tone(100, 0.3, 'sawtooth', 0.15, 40); },
    shatter: () => { tone(1500, 0.1, 'square', 0.1, 900); },
    burst: () => { tone(600, 0.3, 'sine', 0.2, 100); noise(0.15, 0.15); },
    buy: () => { [784, 1046].forEach((f, i) => setTimeout(() => ctx && tone(f, 0.12, 'triangle', 0.15), i * 80)); },
    bite: () => { noise(0.05, 0.2, 400); tone(220, 0.08, 'square', 0.15, 90); },
    swing: () => noise(0.07, 0.05, 2500),
    ui: () => tone(700, 0.04, 'square', 0.06),
  };
  function play(name) {
    if (!ctx || muted) return;
    const now = performance.now();
    if (last[name] && now - last[name] < 40) return;
    last[name] = now;
    const f = SOUNDS[name]; if (f) try { f(); } catch (e) {}
  }
  loadPrefs();
  return { init, play, setVolume, setMuted, get volume() { return volume; }, get muted() { return muted; } };
})();
