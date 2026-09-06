// 공통 네임스페이스와 유틸. 브라우저와 Node(vm) 양쪽에서 로드된다.
var PA = (typeof PA !== 'undefined') ? PA : {};
if (typeof globalThis !== 'undefined') globalThis.PA = PA;

PA.VERSION = '0.7.1';

// mulberry32: 시드 기반 결정적 난수
PA.rng = {
  create(seed) {
    let a = (seed >>> 0) || 1;
    const next = () => {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    return {
      next,
      range(lo, hi) { return lo + (hi - lo) * next(); },
      int(lo, hi) { return lo + Math.floor(next() * (hi - lo + 1)); },
      pick(arr) { return arr[Math.floor(next() * arr.length)]; },
      shuffle(arr) { const b = arr.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(next() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; },
    };
  },
};

PA.m = {
  clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); },
  len(x, y) { return Math.hypot(x, y); },
  dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); },
  norm(x, y) { const l = Math.hypot(x, y); return l > 1e-9 ? { x: x / l, y: y / l } : { x: 0, y: 0 }; },
  lerp(a, b, t) { return a + (b - a) * t; },
  angDiff(a, b) { let d = b - a; while (d > Math.PI) d -= Math.PI * 2; while (d < -Math.PI) d += Math.PI * 2; return d; },
  // 점 p가 원(c, r)과 각도 ang 중심, 반각 half 의 부채꼴 안에 있는가 (p는 반지름 pr의 원)
  inArc(c, r, ang, half, p, pr) {
    const d = Math.hypot(p.x - c.x, p.y - c.y);
    if (d > r + pr) return false;
    if (d <= pr) return true;
    const a = Math.atan2(p.y - c.y, p.x - c.x);
    const dd = Math.abs(PA.m.angDiff(ang, a));
    // 반지름 보정: 가까울수록 각도 허용 폭 넓어짐
    const extra = Math.asin(Math.min(1, pr / Math.max(d, 1e-6)));
    return dd <= half + extra;
  },
  // 원(p, pr)이 시작 s에서 각도 ang 방향 길이 L, 폭 W인 직사각형과 겹치는가
  inBeam(s, ang, L, W, p, pr) {
    const dx = p.x - s.x, dy = p.y - s.y;
    const ca = Math.cos(ang), sa = Math.sin(ang);
    const along = dx * ca + dy * sa;
    const side = -dx * sa + dy * ca;
    return along >= -pr && along <= L + pr && Math.abs(side) <= W / 2 + pr;
  },
  circleHit(a, b) { const d = Math.hypot(a.x - b.x, a.y - b.y); return d <= a.r + b.r; },
  // 선분 (x0,y0)->(x1,y1)이 원(c, r)에 처음 닿는 매개변수 t(0..1). 시작점이 이미 안이면 0. 안 닿으면 null
  segCircleT(x0, y0, x1, y1, c, r) {
    const fx = x0 - c.x, fy = y0 - c.y;
    if (fx * fx + fy * fy <= r * r) return 0;
    const dx = x1 - x0, dy = y1 - y0;
    const a = dx * dx + dy * dy; if (a < 1e-12) return null;
    const b = 2 * (fx * dx + fy * dy), cc = fx * fx + fy * fy - r * r;
    const disc = b * b - 4 * a * cc; if (disc < 0) return null;
    const t = (-b - Math.sqrt(disc)) / (2 * a);
    return (t >= 0 && t <= 1) ? t : null;
  },
  // 반지름 r인 원이 (x0,y0)->(x1,y1)로 쓸고 갈 때 장애물 원 목록과 처음 닿는 t와 장애물
  sweepCircle(x0, y0, x1, y1, r, circles) {
    let best = null;
    for (const ob of circles) { const t = PA.m.segCircleT(x0, y0, x1, y1, ob, ob.r + r); if (t != null && (best == null || t < best.t)) best = { t, ob }; }
    return best;
  },
  // 선분 (x0,y0)-(x1,y1) 과 원 (c, r) 교차 (스윕 충돌용)
  segCircle(x0, y0, x1, y1, c, r) {
    const dx = x1 - x0, dy = y1 - y0;
    const l2 = dx * dx + dy * dy;
    let t = 0;
    if (l2 > 1e-9) t = PA.m.clamp(((c.x - x0) * dx + (c.y - y0) * dy) / l2, 0, 1);
    const px = x0 + dx * t, py = y0 + dy * t;
    return Math.hypot(c.x - px, c.y - py) <= r;
  },
};

PA.fmt = {
  pct(mult) { const p = Math.round((mult - 1) * 100); return (p >= 0 ? '+' : '') + p + '%'; },
  num(n) { return Math.round(n * 10) / 10; },
};
