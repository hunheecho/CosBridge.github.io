// 용어 사전 UI(v0.8): 밑줄 용어(dfn.term)에 마우스를 올리면 툴팁, 클릭/Enter/탭하면 고정(중첩 가능), Esc·뒤로가기로 닫힘. 화면 밖으로 나가지 않게 위치를 잡는다.
// 3단계 이상 깊어지면 패널 모드(전체 사전)로 연다. 전투 중에는 고정(클릭)으로 열 때만 일시정지 훅을 부른다(단순 마우스 이동은 정지시키지 않음).
var PA = (typeof PA !== 'undefined') ? PA : {};
PA.Glossary = (function () {
  const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  let ALL = null; const all = () => ALL || (ALL = PA.glossaryAll());
  function get(id) { return all()[id] || null; }
  // 화면용 밑줄 용어. text를 생략하면 용어 이름
  function T(id, text) { const d = get(id); if (!d) return esc(text || id); return `<dfn class="term" data-term="${esc(id)}" tabindex="0">${esc(text || d.name)}</dfn>`; }
  // 본문의 {{id}}를 중첩 용어로 바꾼다
  function body(id) { const d = get(id); if (!d) return ''; const raw = typeof d.body === 'function' ? d.body() : d.body; return esc(raw).replace(/\{\{([a-z_:]+)\}\}/g, (m, k) => T(k)); }
  function tipHtml(id, depth) { const d = get(id); if (!d) return ''; return `<div class="tip-head"><b>${esc(d.name)}</b> <span class="dim small">${esc(d.short)}</span><button class="tip-close" data-tip-close="1" aria-label="닫기">×</button></div><div class="tip-body">${body(id)}</div>${d.related && d.related.length ? `<div class="tip-rel small">관련: ${d.related.map(r => T(r)).join(' · ')}</div>` : ''}${depth >= 2 ? `<div class="tip-rel small"><button class="mini" data-glossary-open="${esc(id)}">사전 패널에서 보기</button></div>` : ''}`; }
  function panelHtml(focusId) { const A = all(); const ids = Object.keys(A); return `<div class="panel glossary"><div class="row between"><h2>용어 사전</h2><button data-action="close-overlay">닫기 (Esc)</button></div><div class="gl-list">${ids.map(id => `<details class="gl-item" ${id === focusId ? 'open' : ''} id="gl-${esc(id)}"><summary><b>${esc(A[id].name)}</b> <span class="dim small">${esc(A[id].short)}</span></summary><div class="tip-body">${body(id)}</div></details>`).join('')}</div></div>`; }
  // ---------- 툴팁 관리(브라우저 전용) ----------
  const tips = []; let hoverTip = null, onPin = null, onUnpinAll = null, hist = 0;
  function place(el, anchor) {
    const r = anchor.getBoundingClientRect(), vw = window.innerWidth, vh = window.innerHeight; el.style.maxWidth = Math.min(360, vw - 16) + 'px';
    const w = el.offsetWidth, h = el.offsetHeight; let x = r.left, y = r.bottom + 6;
    if (x + w > vw - 8) x = Math.max(8, vw - 8 - w); if (y + h > vh - 8) y = Math.max(8, r.top - 6 - h); if (y < 8) y = 8;
    el.style.left = x + 'px'; el.style.top = y + 'px';
  }
  function show(anchor, pinned) {
    const id = anchor.dataset.term; if (!get(id)) return null;
    const depth = tips.filter(t => t.pinned).length;
    if (pinned && depth >= 3) { openPanel(id); return null; } // 너무 깊으면 패널 모드
    if (hoverTip) { hoverTip.el.remove(); hoverTip = null; }
    const el = document.createElement('div'); el.className = 'tip' + (pinned ? ' pinned' : ''); el.innerHTML = tipHtml(id, depth); document.body.appendChild(el); place(el, anchor);
    const t = { el, id, pinned, anchor }; if (pinned) { tips.push(t); if (onPin) onPin(t); try { history.pushState({ tip: ++hist }, ''); } catch (e) {} } else hoverTip = t;
    return t;
  }
  function closeLast() { if (hoverTip) { hoverTip.el.remove(); hoverTip = null; return true; } const t = tips.pop(); if (t) { t.el.remove(); if (!tips.length && onUnpinAll) onUnpinAll(); return true; } return false; }
  function closeAll() { if (hoverTip) { hoverTip.el.remove(); hoverTip = null; } while (tips.length) tips.pop().el.remove(); if (onUnpinAll) onUnpinAll(); }
  function openPanel(focusId) { closeAll(); if (PA.Glossary.onOpenPanel) PA.Glossary.onOpenPanel(focusId); }
  function install(opts) {
    onPin = opts && opts.onPin; onUnpinAll = opts && opts.onUnpinAll;
    document.addEventListener('mouseover', (e) => { const d = e.target.closest && e.target.closest('dfn.term'); if (!d || (hoverTip && hoverTip.anchor === d) || tips.some(t => t.anchor === d)) return; show(d, false); });
    document.addEventListener('mouseout', (e) => { const d = e.target.closest && e.target.closest('dfn.term'); if (d && hoverTip && hoverTip.anchor === d) { const to = e.relatedTarget; if (to && hoverTip.el.contains(to)) return; hoverTip.el.remove(); hoverTip = null; } });
    document.addEventListener('mouseleave', (e) => { if (hoverTip && e.target === hoverTip.el) { hoverTip.el.remove(); hoverTip = null; } }, true);
    document.addEventListener('click', (e) => {
      const c = e.target.closest && e.target.closest('[data-tip-close]'); if (c) { const el = c.closest('.tip'); const i = tips.findIndex(t => t.el === el); if (i >= 0) { while (tips.length > i) tips.pop().el.remove(); if (!tips.length && onUnpinAll) onUnpinAll(); } else if (hoverTip && hoverTip.el === el) { hoverTip.el.remove(); hoverTip = null; } e.stopPropagation(); return; }
      const g = e.target.closest && e.target.closest('[data-glossary-open]'); if (g) { openPanel(g.dataset.glossaryOpen); e.stopPropagation(); return; }
      const d = e.target.closest && e.target.closest('dfn.term'); if (d) { if (hoverTip && hoverTip.anchor === d) { hoverTip.el.remove(); hoverTip = null; } if (!tips.some(t => t.anchor === d)) show(d, true); e.preventDefault(); e.stopPropagation(); return; }
      if (tips.length && !(e.target.closest && e.target.closest('.tip'))) closeAll(); // 바깥 클릭: 모두 닫기
    }, true);
    document.addEventListener('keydown', (e) => { const d = e.target.closest && e.target.closest('dfn.term'); if (d && (e.code === 'Enter' || e.code === 'Space')) { if (!tips.some(t => t.anchor === d)) show(d, true); e.preventDefault(); e.stopPropagation(); return; } if (e.code === 'Escape' && (tips.length || hoverTip)) { closeLast(); e.preventDefault(); e.stopPropagation(); } }, true);
    window.addEventListener('popstate', () => { if (tips.length) closeLast(); }); // 모바일 뒤로가기 = 마지막 툴팁 닫기
    window.addEventListener('resize', () => { for (const t of tips) place(t.el, t.anchor); });
  }
  return { get, all, T, body, tipHtml, panelHtml, install, show, closeLast, closeAll, openPanel, tips: () => tips, hover: () => hoverTip };
})();
