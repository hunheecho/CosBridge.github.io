// DOM 화면(전투 밖). HTML 문자열을 만들고 data-action으로 main에 동작을 위임한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Screens = (function () {
  const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const R = () => PA.Run;
  const stars = (n) => '★'.repeat(n) + '☆'.repeat(3 - n);
  const matName = (k) => PA.MATERIALS[k].name;
  const hoursPips = (h, max) => `<span class="pips">${Array.from({ length: max }, (_, i) => `<i class="${i < h ? 'on' : ''}"></i>`).join('')}</span>`;
  const costText = (cost) => `금화 ${cost.gold}` + Object.keys(cost.mats || {}).map(k => ` + ${matName(k)} ${cost.mats[k]}`).join('');

  function header(run) {
    const b = R().build(run), left = R().bossDaysLeft(run);
    const bossPct = Math.round(((run.day - 1) / (PA.CONFIG.BOSS_DAY - 1)) * 100);
    return `<div class="topbar">
      <div class="stat"><span class="lbl">날짜</span><b>${run.day}일차</b></div>
      <div class="stat"><span class="lbl">오늘 남은 시간</span><b>${run.hours} / ${PA.CONFIG.HOURS_PER_DAY}시간</b> ${hoursPips(run.hours, PA.CONFIG.HOURS_PER_DAY)}</div>
      <div class="stat boss"><span class="lbl">보스 도래까지</span><b class="${left <= 2 ? 'warn' : ''}">${left > 0 ? left + '일' : '오늘'}</b><span class="bossbar"><i style="width:${bossPct}%"></i></span></div>
      <div class="stat"><span class="lbl">체력</span><b>${run.hp} / ${b.hpMax}</b></div>
      <div class="stat"><span class="lbl">금화</span><b class="gold">${run.gold}</b></div>
    </div>`;
  }
  function matsRow(run) {
    return `<div class="mats">${Object.keys(PA.MATERIALS).map(k => `<span class="mat ${run.mats[k] ? '' : 'zero'}">${matName(k)} <b>${run.mats[k] || 0}</b></span>`).join('')}</div>`;
  }
  function targetCard(run) {
    const t = R().targetInfo(run);
    if (!t) return `<div class="card target"><div class="card-title">목표 장비</div><p>목표가 없습니다. 상점·대장간에서 정하세요.</p><button data-action="shop">상점·대장간</button></div>`;
    const needs = t.needs.length ? `<ul class="needs">${t.needs.map(n => `<li><b>${esc(n.name)} ${n.need}</b> 부족 · 획득: ${n.where.join(', ')}</li>`).join('')}</ul>` : `<p class="ok">재료와 금화가 모두 준비되었습니다. 상점·대장간에서 ${t.item.slot === 'upgrade' ? '강화' : '제작'}하세요.</p>`;
    return `<div class="card target"><div class="card-title">목표 장비: ${esc(t.item.name)} <span class="sub">${esc(t.item.short)}</span></div>
      <div class="cost">비용: ${costText(t.cost)}</div>${needs}
      <div class="row"><button data-action="shop" class="${t.ready ? 'primary' : ''}">상점·대장간</button><button data-action="map">지역 보기</button></div></div>`;
  }
  function buildPanel(run) {
    const b = R().build(run), g = run.gear;
    const augs = Object.keys(run.augments).filter(k => run.augments[k] > 0).map(k => { const d = PA.AUGMENTS.find(a => a.id === k); return `<li><b>${esc(d.name)}</b>${d.max > 1 ? ` ${run.augments[k]}단계` : ''} <span class="dim">${esc(d.desc)}</span></li>`; }).join('');
    return `<div class="card"><div class="card-title">현재 빌드</div>
      <ul class="gear">
        <li>무기: <b>${esc(b.weapon.name)}${g.upgrade ? ' +' + g.upgrade : ''}</b> <span class="dim">${b.weapon.form === 'beam' ? '관통 직선' : '부채꼴'} · 피해 ${PA.fmt.num(b.damage)} · 주기 ${PA.fmt.num(b.interval)}초 · 범위 ${Math.round(b.range)}</span>${run.owned.includes('pierce_sword') ? ` <button class="mini" data-action="toggle-weapon">${g.weapon === 'pierce' ? '기본검으로' : '관통검으로'}</button>` : ''}</li>
        <li>방어구: <b>${g.armor ? esc(R().item(g.armor).name) : '없음'}</b> <span class="dim">최대 체력 ${b.hpMax}</span></li>
        <li>장신구: <b>${g.acc ? esc(R().item(g.acc).name) : '없음'}</b> <span class="dim">회피 재사용 ${PA.fmt.num(PA.CONFIG.PLAYER.dodge.cooldown * b.dodgeCdMult)}초 · 감속장 ${b.specialCd}초 · 빈틈 피해 ×${b.exposedMult}</span></li>
        <li>수동 특수기(Q): <b>감속장</b> <span class="dim">반지름 150 · 3초 · 적 속도 40%</span></li>
      </ul>
      <div class="card-title small">증강 (회차 동안 유지)</div>${augs ? `<ul class="augs">${augs}</ul>` : '<p class="dim">아직 없음. 조우 승리 시 선택합니다.</p>'}</div>`;
  }

  function title(G) {
    const hasSave = !!G.saved;
    return `<div class="screen center"><h1>예언의 시간표</h1><p class="subtitle">액션 프로토타입 · 마검사의 준비 기간</p>
      <div class="menu">
        ${hasSave ? `<button class="primary big" data-action="continue">계속하기 <span class="dim">(${G.saved.day}일차 · 금화 ${G.saved.gold})</span></button>` : ''}
        <button class="big ${hasSave ? '' : 'primary'}" data-action="newrun">새 회차</button>
        <button class="big" data-action="controls">조작법</button>
      </div>
      <p class="dim small">${esc(PA.KEYS_TEXT)}</p><p class="dim small">v${PA.VERSION}</p></div>`;
  }
  function newrunConfirm() {
    return `<div class="screen center"><h2>새 회차를 시작할까요?</h2><p>기존 저장(진행 중인 회차)이 덮어씌워집니다.</p><div class="row"><button class="primary" data-action="newrun-confirm">새 회차 시작</button><button data-action="title">돌아가기</button></div></div>`;
  }
  function base(G) {
    const run = G.run;
    const canRest = R().canRest(run);
    return `<div class="screen">${header(run)}
      <div class="grid2">
        <div>
          ${targetCard(run)}
          <div class="card"><div class="card-title">오늘 할 일</div>
            <div class="actions">
              <button class="primary big" data-action="map">출격 · 지역 선택</button>
              <button class="big" data-action="shop">상점 · 대장간</button>
              <button class="big" data-action="rest" ${canRest ? '' : 'disabled'}>휴식 (1시간, 체력 완전 회복)${canRest ? '' : run.hp >= R().build(run).hpMax ? ' · 체력 가득' : ' · 시간 부족'}</button>
              <button class="big" data-action="endday-confirm">하루 종료 → ${run.day + 1}일차${run.hours > 0 ? ` <span class="dim">(남은 ${run.hours}시간 버림)</span>` : ''}</button>
              <button data-action="save-quit">저장 후 종료</button>
            </div></div>
          <div class="card"><div class="card-title">재료</div>${matsRow(run)}<p class="dim small">재료는 상점에서 팔 수 있습니다. 제작에 쓸지 현금으로 바꿀지 선택하세요.</p></div>
        </div>
        <div>
          ${buildPanel(run)}
          <div class="card"><div class="card-title">최근 기록</div>${run.log.length ? `<ul class="log">${run.log.map(l => `<li>${esc(l)}</li>`).join('')}</ul>` : '<p class="dim">아직 없음</p>'}</div>
        </div>
      </div></div>`;
  }
  function map(G) {
    const run = G.run, t = R().targetInfo(run);
    const needKinds = t ? t.needs.map(n => n.kind) : [];
    const cards = PA.REGIONS.map(r => {
      const can = R().canSortie(run, r.id);
      const rewardText = `금화 ${r.reward.gold[0]}~${r.reward.gold[1]}` + Object.keys(r.reward.mats).map(k => `, ${matName(k)} ${k === 'fang' ? '(정예 처치 시 1)' : r.reward.mats[k][0] + '~' + r.reward.mats[k][1]}`).join('');
      const forTarget = Object.keys(r.reward.mats).some(k => needKinds.includes(k)) || (needKinds.includes('gold'));
      const enemies = r.enemies.map(id => `<li><b>${esc(PA.ENEMIES[id].name)}</b> <span class="dim">${esc(PA.ENEMIES[id].role)} — ${esc(PA.ENEMIES[id].readme)}</span></li>`).join('');
      return `<div class="card region ${can ? '' : 'off'}">
        <div class="card-title">${esc(r.name)} <span class="risk">위험 ${stars(r.risk)}</span> <span class="cost-badge">${r.cost}시간</span></div>
        <p>${esc(r.desc)}</p>
        <div class="kv"><span>목적</span><b>${r.objective === 'elite' ? '정예 처치' : '전멸'} · ${r.waves.length}웨이브</b></div>
        <div class="kv"><span>보상</span><b>${rewardText}</b>${forTarget ? ' <span class="tag">목표 장비 재료</span>' : ''}</div>
        <ul class="enemies">${enemies}</ul>
        <button class="primary" data-action="sortie" data-arg="${r.id}" ${can ? '' : 'disabled'}>${can ? `출격 (${r.cost}시간 사용 → ${run.hours - r.cost}시간 남음)` : '시간 부족'}</button>
      </div>`;
    }).join('');
    return `<div class="screen">${header(run)}
      <div class="row between"><h2>지역 선택</h2><button data-action="base">거점으로</button></div>
      <p class="dim">출격 비용은 출발 시 차감됩니다. 전투가 오래 걸려도 추가로 시간을 빼지 않습니다. 조우 승리 후 "더 깊이 탐험"은 별도로 1시간을 씁니다.</p>
      <div class="grid3">${cards}</div></div>`;
  }
  function previewRows(run, patch) {
    const a = R().build(run), b = PA.Build.preview(run, patch);
    const rows = [];
    const add = (name, x, y, fmt) => { if (Math.abs(x - y) > 1e-6) rows.push(`<li>${name}: <span class="dim">${fmt(x)}</span> → <b>${fmt(y)}</b></li>`); };
    add('피해', a.damage, b.damage, v => PA.fmt.num(v));
    add('늑대 처치 타격 수', PA.Build.hitsToKill(a, 'wolf'), PA.Build.hitsToKill(b, 'wolf'), v => v + '타');
    add('우두머리 처치 타격 수', PA.Build.hitsToKill(a, 'wolf_alpha'), PA.Build.hitsToKill(b, 'wolf_alpha'), v => v + '타');
    add('공격 주기', a.interval, b.interval, v => PA.fmt.num(v) + '초');
    add('범위', a.range, b.range, v => Math.round(v));
    add('최대 체력', a.hpMax, b.hpMax, v => v);
    add('회피 재사용', PA.CONFIG.PLAYER.dodge.cooldown * a.dodgeCdMult, PA.CONFIG.PLAYER.dodge.cooldown * b.dodgeCdMult, v => PA.fmt.num(v) + '초');
    add('감속장 재사용', a.specialCd, b.specialCd, v => v + '초');
    add('빈틈 피해 배율', a.exposedMult, b.exposedMult, v => '×' + v);
    if (a.weapon.form !== b.weapon.form) rows.push(`<li>공격 형태: <span class="dim">${a.weapon.form === 'beam' ? '관통 직선' : '부채꼴'}</span> → <b>${b.weapon.form === 'beam' ? '관통 직선 (길이 ' + Math.round(b.range) + ', 폭 ' + b.weapon.width + ')' : '부채꼴'}</b></li>`);
    return rows.length ? `<ul class="preview">${rows.join('')}</ul>` : '<p class="dim small">수치 변화 없음</p>';
  }
  function itemPatch(run, it) {
    if (it.slot === 'upgrade') return { gear: { upgrade: run.gear.upgrade + 1 } };
    if (it.slot === 'weapon') return { gear: { weapon: 'pierce' } };
    if (it.slot === 'armor') return { gear: { armor: it.id } };
    return { gear: { acc: it.id } };
  }
  function shop(G) {
    const run = G.run;
    const items = PA.ITEMS.map(it => {
      const avail = R().itemAvailable(run, it);
      if (!avail) return `<div class="card item done"><div class="card-title">${esc(it.name)} <span class="tag">보유</span></div><p class="dim">${esc(it.desc)}</p></div>`;
      const cost = R().itemCost(run, it), s = R().shortfall(run, it), can = R().canBuy(run, it);
      const costHtml = `<span class="${s.gold > 0 ? 'lack' : ''}">금화 ${cost.gold}${s.gold > 0 ? ` (${s.gold} 부족)` : ''}</span>` + Object.keys(cost.mats || {}).map(k => ` + <span class="${s.mats[k] ? 'lack' : ''}">${matName(k)} ${cost.mats[k]}${s.mats[k] ? ` (${s.mats[k]} 부족 · ${PA.MATERIALS[k].where.map(id => R().region(id).name).join('/')})` : ''}</span>`).join('');
      const name = it.slot === 'upgrade' ? `${it.name} +${run.gear.upgrade + 1}` : it.name;
      return `<div class="card item ${can ? 'can' : ''}"><div class="card-title">${esc(name)} <span class="sub">${esc(it.short)}</span>${run.target === it.id ? ' <span class="tag">목표</span>' : ''}</div>
        <p>${esc(it.desc)}</p><div class="cost">${costHtml}</div>
        <div class="card-title small">구매 시 변화</div>${previewRows(run, itemPatch(run, it))}
        <div class="row"><button class="primary" data-action="buy" data-arg="${it.id}" ${can ? '' : 'disabled'}>${it.slot === 'upgrade' ? '강화' : it.slot === 'weapon' ? '제작' : '구매'}</button>${run.target !== it.id ? `<button data-action="target" data-arg="${it.id}">목표로 지정</button>` : ''}</div></div>`;
    }).join('');
    const sells = Object.keys(PA.MATERIALS).map(k => `<div class="sellrow"><span>${matName(k)} <b>${run.mats[k] || 0}</b> <span class="dim">(개당 ${PA.MATERIALS[k].sell}금)</span></span><button class="mini" data-action="sell" data-arg="${k}" ${run.mats[k] ? '' : 'disabled'}>1개 판매</button></div>`).join('');
    return `<div class="screen">${header(run)}
      <div class="row between"><h2>상점 · 대장간</h2><button data-action="base">거점으로</button></div>
      <p class="dim">살 수 없어도 전 목록이 보입니다. 부족한 것은 붉게, 획득 지역과 함께 표시됩니다. 구매·제작은 즉시 장착되어 다음 전투에 반영됩니다.</p>
      ${matsRow(run)}
      <div class="grid3">${items}</div>
      <div class="card"><div class="card-title">재료 판매</div>${sells}</div>
      ${buildPanel(run)}</div>`;
  }
  function reward(G) {
    const run = G.run, rw = G.lastReward, offers = G.offers || [];
    const matText = Object.keys(rw.mats).map(k => `${matName(k)} ${rw.mats[k]}`).join(', ');
    const cards = offers.map(a => `<div class="card aug"><div class="card-title">${esc(a.name)} <span class="kind">${esc(a.kind)}</span></div>
      <p class="big-desc">${esc(a.desc)}</p><p class="dim">${esc(a.long)}</p>
      <div class="connect">연결: ${esc(PA.Build.connectionText(run, a) || '—')}${a.connect ? ` <span class="tag">${esc(a.connect)}</span>` : ''}</div>
      <button class="primary" data-action="pick" data-arg="${a.id}">선택</button></div>`).join('');
    return `<div class="screen"><h2>조우 승리</h2>
      <div class="card"><div class="card-title">보상 (귀환 시 거점에 반영)</div>
        <p>금화 <b class="gold">+${rw.gold}</b>${rw.chestGold ? ` (보급 상자 +${rw.chestGold} 포함)` : ''}${matText ? ` · ${matText}` : ''}</p>
        <p class="dim small">처치 ${G.lastStats.kills} · 받은 피해 ${Math.round(G.lastStats.damageTaken)} · 아슬아슬한 회피 ${G.lastStats.perfectDodges} · ${Math.round(G.lastStats.elapsed)}초</p></div>
      <h3>증강 선택 (회차 동안 유지)</h3>
      <div class="grid3">${cards.length ? cards : '<p class="dim">제시할 수 있는 증강이 없습니다.</p>'}</div>
      <div class="row"><button data-action="skip">건너뛰기 (금화 +${PA.CONFIG.SKIP_AUGMENT_GOLD})</button></div></div>`;
  }
  function after(G) {
    const run = G.run, s = G.sortie, r = R().region(s.regionId), b = R().build(run);
    const canDeep = !s.deep && R().canDeepExplore(run);
    const lootText = `금화 ${s.loot.gold}` + Object.keys(s.loot.mats).map(k => `, ${matName(k)} ${s.loot.mats[k]}`).join('');
    return `<div class="screen center"><h2>${esc(r.name)} · 다음 행동</h2>
      <p>체력 <b>${run.hp} / ${b.hpMax}</b> · 이번 출격 전리품: <b>${lootText}</b> · 오늘 남은 시간 <b>${run.hours}</b></p>
      <div class="menu">
        <button class="big ${canDeep ? '' : 'off'}" data-action="deep" ${canDeep ? '' : 'disabled'}>더 깊이 탐험 (+1시간) <span class="dim">적 수 +1, 마지막에 정예. 보상 ×${PA.CONFIG.DEEP_REWARD_MULT}${s.deep ? ' · 이미 탐험함' : (canDeep ? '' : ' · 시간 부족')}</span></button>
        <button class="primary big" data-action="return">귀환 (전리품 확정)</button>
      </div><p class="dim small">패배하면 이번 출격의 전리품을 잃습니다.</p></div>`;
  }
  function defeat(G) {
    const run = G.run, r = R().region(G.sortie.regionId);
    return `<div class="screen center"><h2 class="bad">패배</h2><p>${esc(r.name)}에서 쓰러졌습니다. 이번 출격의 전리품을 잃었고, 부상 치료로 1시간을 썼습니다.</p>
      <p>체력 ${run.hp} · 오늘 남은 시간 ${run.hours} · 증강과 장비는 유지됩니다.</p>
      <p class="dim small">처치 ${G.lastStats.kills} · 받은 피해 ${Math.round(G.lastStats.damageTaken)} · ${Math.round(G.lastStats.elapsed)}초</p>
      <button class="primary big" data-action="base">거점으로</button></div>`;
  }
  function enddayConfirm(G) {
    const run = G.run;
    return `<div class="screen center"><h2>하루를 마칠까요?</h2><p>남은 ${run.hours}시간을 버리고 ${run.day + 1}일차로 넘어갑니다. 체력이 완전히 회복되고 시간이 5로 돌아옵니다.</p>
      <p class="dim">보스 도래까지 ${R().bossDaysLeft(run) - 1 > 0 ? (R().bossDaysLeft(run) - 1) + '일 남음' : '내일이 도래일입니다'}</p>
      <div class="row"><button class="primary" data-action="endday">하루 종료</button><button data-action="base">돌아가기</button></div></div>`;
  }
  function bossday(G) {
    const run = G.run;
    return `<div class="screen center"><h2>보스 도래 — ${run.day}일차</h2>
      <p>예언의 날이 왔습니다. 준비 기간이 끝났습니다.</p>
      <div class="card"><div class="card-title">이 빌드의 한계</div><p><b>보스전은 아직 구현되어 있지 않습니다.</b> 이 화면은 결말을 완료된 것처럼 꾸미지 않기 위한 정직한 종료 화면입니다.</p>
      <p class="dim">회차 기록: 조우 ${run.stats.encounters} · 승리 ${run.stats.wins} · 패배 ${run.stats.losses} · 최종 금화 ${run.gold}</p></div>
      ${buildPanel(run)}
      <div class="row"><button class="primary big" data-action="newrun-confirm">새 회차 시작</button><button data-action="title">제목으로</button></div></div>`;
  }
  function scenarioEnd(G) {
    const s = G.lastStats;
    return `<div class="screen center"><h2>시험 전투 종료: ${G.lastResult === 'won' ? '승리' : '패배'}</h2>
      <p class="dim">처치 ${s.kills} · 받은 피해 ${Math.round(s.damageTaken)} · 아슬아슬한 회피 ${s.perfectDodges} · 공격 ${s.attacks}회 · ${Math.round(s.elapsed)}초</p>
      <div class="row"><button class="primary" data-action="scenario-again">같은 시드로 다시</button><button data-action="title">제목으로</button></div></div>`;
  }
  function controls() {
    return `<div class="panel"><h2>조작법</h2>
      <table class="keys"><tr><td>W A S D / 방향키</td><td>이동</td></tr><tr><td>Space</td><td>회피 (0.26초 무적, 이동 방향으로 구르기)</td></tr><tr><td>Q</td><td>감속장 (주변 적을 3초간 느리게)</td></tr><tr><td>Esc</td><td>일시정지 / 메뉴</td></tr><tr><td>Enter · 클릭</td><td>메뉴 확인</td></tr></table>
      <h3>읽어야 할 것</h3><ul>
        <li><b>붉은 화살표</b>: 늑대가 돌진할 직선. 화살표가 굵어지며 "!"가 뜨면 방향이 고정된 것 — 옆으로 피하세요.</li>
        <li><b>붉은 점선</b>: 궁수의 조준선. 굵어지면 발사 직전.</li>
        <li><b>보라색 원</b>: 포자 구름이 생길 자리. 원 밖으로 나가세요. 구름은 5초간 남습니다.</li>
        <li><b>노란 별</b>: 빈틈. 이때 때리면 피해 1.5배.</li>
        <li>자동 공격은 사거리 안에 적이 있을 때만 가장 가까운 적을 향해 나갑니다.</li></ul>
      <button data-action="close-overlay" class="primary">닫기</button></div>`;
  }
  function pause(G) {
    return `<div class="panel"><h2>일시정지</h2><p class="dim">전투가 멈춰 있습니다.</p>
      <div class="row"><label>음량 <input type="range" id="vol" min="0" max="100" value="${Math.round(PA.Audio.volume * 100)}"></label><label><input type="checkbox" id="mute" ${PA.Audio.muted ? 'checked' : ''}> 음소거</label></div>
      <div class="row"><button class="primary" data-action="resume">계속 (Esc)</button><button data-action="show-controls">조작법</button><button class="danger" data-action="give-up">포기하고 거점으로 (패배 처리)</button></div></div>`;
  }
  return { title, newrunConfirm, base, map, shop, reward, after, defeat, enddayConfirm, bossday, scenarioEnd, controls, pause };
})();
