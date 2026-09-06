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
      ${R().layoutText(run) ? `<div class="stat"><span class="lbl">시험안</span><b class="warn small">${esc(R().layoutText(run))}</b></div>` : ''}
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
  // 다가오는 보스 정보(준비 기간부터 공개)
  function bossCard(run, full) {
    const B = PA.BOSS, left = R().bossDaysLeft(run);
    const when = run.phase === 'cleared' ? '처치함' : left > 0 ? `${left}일 뒤 도래` : '오늘 도래';
    return `<div class="card boss"><div class="card-title">다가오는 보스: ${esc(B.name)} — ${esc(B.title)} <span class="tag">${when}</span></div>
      <div class="bossart"><canvas class="bossportrait" width="160" height="90"></canvas><div><p>숲과 늑대 무리를 지배하는 거대한 늑대. 목과 등에 부러진 나뭇가지 같은 검은 가시가 돋았고, 한쪽 송곳니가 부러졌다.</p>
      <ul class="tips">${B.info.map(t => `<li>${esc(t)}</li>`).join('')}</ul>
      ${full ? `<p class="dim small">전장: ${esc(PA.ARENAS.clearing.name)} · 바위 2, 나무 2 · 체력 ${B.hp} · 단계 전환 70%·35% · 시간제한 없음</p>` : ''}</div></div></div>`;
  }
  function gearPanel(run) {
    const g = run.gear;
    const accs = R().ownedBySlot(run, 'acc'), armors = R().ownedBySlot(run, 'armor');
    const accBtns = accs.map(id => g.acc === id ? `<span class="tag">${esc(R().item(id).name)} 장착 중</span>` : `<button class="mini" data-action="equip" data-arg="${id}">${esc(R().item(id).name)} 장착</button>`).join(' ');
    const armorBtns = armors.map(id => g.armor === id ? `<span class="tag">${esc(R().item(id).name)} 장착 중</span>` : `<button class="mini" data-action="equip" data-arg="${id}">${esc(R().item(id).name)} 장착</button>`).join(' ');
    return `<div class="card"><div class="card-title">장비 교체 <span class="sub">추가 비용 없음</span></div>
      <div class="kv"><span>무기</span><b>${g.weapon === 'pierce' ? '관통검' : '기본검'}${g.upgrade ? ' +' + g.upgrade : ''}</b> ${run.owned.includes('pierce_sword') ? `<button class="mini" data-action="toggle-weapon">${g.weapon === 'pierce' ? '기본검으로' : '관통검으로'}</button>` : '<span class="dim small">관통검 미보유</span>'}</div>
      <div class="kv"><span>방어구</span>${armorBtns || '<span class="dim">보유 없음</span>'}${g.armor ? ` <button class="mini" data-action="unequip" data-arg="armor">해제</button>` : ''}</div>
      <div class="kv"><span>장신구</span>${accBtns || '<span class="dim">보유 없음</span>'}${g.acc ? ` <button class="mini" data-action="unequip" data-arg="acc">해제</button>` : ''}</div></div>`;
  }
  function buildPanel(run) {
    const b = R().build(run), g = PA.Growth.ensure(run), S = PA.GROWTH.SLOTS;
    const wrows = b.weapons.map((w, i) => `<li><b>${esc(w.name)}</b> Lv${w.level}/${S.weaponMax} <span class="dim">${i === 0 ? '시작 무기' : '추가 무기'} · 피해 ${PA.fmt.num(w.damage)} · 주기 ${PA.fmt.num(w.interval)}초${w.range ? ' · 사거리 ' + Math.round(w.range) : ''}</span><br><span class="small">전용 방식 ${w.mods.length}/${S.weaponMods}: ${w.mods.length ? w.mods.map(mid => esc(w.def.mods[mid].name)).join(', ') : '없음'}</span></li>`).join('');
    const empties = Array.from({ length: S.weapons - b.weapons.length }, () => '<li class="dim">빈 무기 슬롯 (레벨업에서 새 무기 획득)</li>').join('');
    const commons = Object.keys(g.commons).filter(k => g.commons[k] > 0).map(k => `<li><b>${esc(PA.COMMONS[k].name)}</b>${PA.COMMONS[k].max > 1 ? ` ${g.commons[k]}/${PA.COMMONS[k].max}` : ''} <span class="dim">${esc(PA.COMMONS[k].desc)}</span></li>`).join('');
    const passives = Object.keys(g.passives).filter(k => g.passives[k] > 0).map(k => `<li><b>${esc(PA.PASSIVES[k].name)}</b> ${g.passives[k]}/${PA.PASSIVES[k].max} <span class="dim">${esc(PA.PASSIVES[k].desc)}</span></li>`).join('');
    const sk = (slot) => { const x = g.skills[slot]; if (!x) return `<li><b>E</b>: <span class="dim">비어 있음 (레벨업에서 습득)</span></li>`; const d = PA.SKILLS[x.id]; return `<li><b>${d.key}</b>: <b>${esc(d.name)}</b> Lv${x.level}/${S.skillMax} <span class="dim">${esc(d.desc)} · 재사용 ${PA.fmt.num(PA.SKILLS[x.id].cooldown[x.level - 1] * b.skillCdMult - (slot === 'q' ? b.accSpecialBonus : 0))}초${x.variant ? ' · 변형: ' + esc(d.variants[x.variant].name) : ''}</span></li>`; };
    const legacy = Object.keys(g.legacy).length ? `<p class="dim small">레거시 유지: ${Object.keys(g.legacy).map(k => k === 'mark' ? '사냥꾼의 표식(우선 대상)' : k === 'barrier' ? '파열 방벽(조우 시작 보호막 30)' : k).join(', ')} — 신규 제시는 없음</p>` : '';
    return `<div class="card"><div class="card-title">현재 빌드 <span class="sub">캐릭터 Lv ${g.level} · 경험치 ${g.xp}/${PA.Growth.xpNeed(g.level)}${g.pendingLevelUps ? ` · <b class="warn">미처리 레벨업 ${g.pendingLevelUps}</b>` : ''}</span></div>
      <div class="card-title small">무기 ${b.weapons.length}/${S.weapons} <span class="dim">(대장간 강화 +${run.gear.upgrade || 0}은 세 무기 공통 ×${PA.fmt.num(b.forgeMult)})</span></div><ul class="gear">${wrows}${empties}</ul>
      <div class="card-title small">공통 증강 ${PA.Growth.commonCount(g)}/${S.commons}</div>${commons ? `<ul class="augs">${commons}</ul>` : '<p class="dim">없음</p>'}
      <div class="card-title small">수동 기술</div><ul class="gear">${sk('q')}${sk('e')}</ul>
      <div class="card-title small">패시브 ${PA.Growth.passiveCount(g)}/${S.passives}</div>${passives ? `<ul class="augs">${passives}</ul>` : '<p class="dim">없음</p>'}
      ${g.bossRewards.length ? `<div class="card-title small">보스 희귀 보상</div><ul class="augs">${g.bossRewards.map(id => `<li><b>${esc(PA.BOSS_REWARDS[id].name)}</b> <span class="dim">${esc(PA.BOSS_REWARDS[id].desc)}</span></li>`).join('')}</ul>` : ''}
      <div class="card-title small">장비</div><ul class="gear">
        <li>방어구: <b>${g_armor(run)}</b> <span class="dim">최대 체력 ${b.hpMax}</span></li>
        <li>장신구: <b>${run.gear.acc ? esc(R().item(run.gear.acc).name) : '없음'}</b> <span class="dim">회피 재사용 ${PA.fmt.num(PA.CONFIG.PLAYER.dodge.cooldown * b.dodgeCdMult)}초 · 빈틈 피해 ×${PA.fmt.num(b.exposedMult)}</span></li></ul>
      ${legacy}</div>`;
  }
  function g_armor(run) { return run.gear.armor ? esc(R().item(run.gear.armor).name) : '없음'; }

  // 시작 무기 선택
  function pickStart(G) {
    const list = (G.startAll ? PA.STARTABLE_ALL : PA.STARTABLE).map(id => { const d = PA.WEAPONS[id]; return `<div class="card"><div class="card-title">${esc(d.name)}</div><p>${esc(d.desc)}</p><p class="dim small">기본 피해 ${d.base.damage} · 주기 ${d.base.interval}초 · 전용 방식: ${Object.values(d.mods).map(m => esc(m.name)).join(', ')}</p><button class="primary" data-action="start-weapon" data-arg="${id}">이 무기로 시작</button></div>`; }).join('');
    const laySel = `<select id="start-layout">${Object.keys(PA.LAYOUTS).map(k => `<option value="${k}">${esc(PA.LAYOUTS[k].name)}</option>`).join('')}</select>`;
    const difSel = `<select id="start-difficulty">${Object.keys(PA.DIFFICULTY.candidates).map(k => `<option value="${k}">${esc(PA.DIFFICULTY.candidates[k].name)}</option>`).join('')}</select>`;
    return `<div class="screen"><h2>시작 무기 선택</h2><p class="dim">시작 무기 1개로 출발하고, 전투 중 레벨업으로 무기를 최대 2개 더 얻습니다. 시작 무기와 추가 무기는 같은 규칙으로 성장합니다.</p>
      <div class="card"><div class="card-title small">검증 메뉴: 지역 배치안·난이도 후보 <span class="dim">(기본값은 기존 배치·×1. 시험안은 검증되지 않은 임시값이며 화면에 표시됩니다)</span></div><div class="kv"><span>배치</span>${laySel}</div><div class="kv"><span>난이도</span>${difSel}</div></div>
      <div class="grid3">${list}</div>
      <div class="row">${G.startAll ? '' : '<button data-action="start-all">검증 메뉴: 다른 시작 후보 보기 (쌍검·추적궁·전투망치·번개 구체)</button>'}<button data-action="title">돌아가기</button></div></div>`;
  }
  // 레벨업 카드(전투 중 오버레이·거점·보상 화면 공용)
  function levelCards(G, offer, run) {
    const pool = offer.pool;
    const cards = offer.choices.map(c => { const d = PA.Growth.describe(run, c); return `<div class="card aug ${d.regionMatch ? 'region' : ''}"><div class="card-title">${esc(d.title)} <span class="kind">${esc(d.type)}</span>${d.regionMatch ? ' <span class="tag">지역 계열</span>' : ''}</div>
      <p class="big-desc">${esc(d.change)}</p>
      <div class="kv"><span>단계</span><b>${esc(d.stage)}</b></div><div class="kv"><span>적용</span><b>${esc(d.scope)}</b></div><div class="kv"><span>슬롯</span><b>${esc(d.slot)}</b></div>
      <button class="primary" data-action="pick" data-arg="${esc(c.key)}">선택</button></div>`; }).join('');
    const title = pool === 'boss' ? '보스 희귀 보상' : pool === 'deep' ? '지역 보상 선택' : pool === 'mission' ? `임무 보상 · ${PA.MISSIONS.kindText[offer.missionKind] || '3택'}` : `레벨 업! Lv ${run.growth.level}${run.growth.pendingLevelUps > 1 ? ` (남은 선택 ${run.growth.pendingLevelUps})` : ''}`;
    return `<div class="panel wide"><h2>${title}</h2>${offer.regionId && pool !== 'boss' ? `<p class="dim small">지역 계열: ${esc(PA.REGION_TAG_TEXT[offer.regionId] || '—')}</p>` : ''}
      <div class="grid3">${cards.length ? cards : '<p class="dim">제시할 수 있는 후보가 없습니다.</p>'}</div>
      <div class="row">${pool === 'level' ? `<button data-action="skip">건너뛰기 (금화 +${PA.CONFIG.SKIP_AUGMENT_GOLD})</button>` : pool === 'deep' || pool === 'mission' ? '<button data-action="skip">받지 않음</button>' : ''}</div></div>`;
  }
  function migration(G) {
    const run = G.run, mp = run.growth.migrationPending, sel = G.migSel || [];
    return `<div class="screen center"><h2>성장 시스템 이행</h2><p>이전 저장에 공통 증강이 ${mp.commons.length}개 있습니다. 새 규칙의 공통 슬롯은 3개입니다. 사용할 3개를 고르세요(나머지는 사라집니다).</p>
      <div class="grid3">${mp.commons.map(c => `<div class="card ${sel.includes(c.id) ? 'can' : ''}"><div class="card-title">${esc(PA.COMMONS[c.id].name)}${c.level > 1 ? ' ' + c.level + '단계' : ''}</div><p class="dim">${esc(PA.COMMONS[c.id].desc)}</p><button data-action="mig-toggle" data-arg="${c.id}">${sel.includes(c.id) ? '선택 해제' : '선택'}</button></div>`).join('')}</div>
      <div class="row"><button class="primary" data-action="mig-confirm" ${sel.length === Math.min(3, mp.commons.length) ? '' : 'disabled'}>확정 (${sel.length}/3)</button></div></div>`;
  }

  function title(G) {
    const hasSave = !!G.saved;
    return `<div class="screen center"><h1>예언의 시간표</h1><p class="subtitle">액션 프로토타입 · 마검사의 준비 기간</p>
      <div class="menu">
        ${hasSave ? `<button class="primary big" data-action="continue">계속하기 <span class="dim">(${G.saved.day}일차 · 금화 ${G.saved.gold})</span></button>` : ''}
        <button class="big ${hasSave ? '' : 'primary'}" data-action="newrun">새 회차</button>
        <button class="big" data-action="controls">조작법</button>
        <button class="big" data-action="lab">전투 시험실 <span class="dim">(정식 회차와 분리 · 체력 배율·빌드·적 조합 비교)</span></button>
      </div>
      <p class="dim small">${esc(PA.KEYS_TEXT)}</p><p class="dim small">v${PA.VERSION}</p></div>`;
  }
  function newrunConfirm() {
    return `<div class="screen center"><h2>새 회차를 시작할까요?</h2><p>기존 저장(진행 중인 회차)이 덮어씌워집니다.</p><div class="row"><button class="primary" data-action="newrun-confirm">새 회차 시작</button><button data-action="title">돌아가기</button></div></div>`;
  }
  function finalPrep(G) {
    const run = G.run, b = R().build(run), cleared = run.phase === 'cleared';
    const rec = run.bossClear;
    return `<div class="screen">${header(run)}
      <h2>${run.day}일차 — ${cleared ? '예언의 날을 넘겼다' : '최종 준비'}</h2>
      <p class="dim">오늘은 일반 출격이 없습니다. 보유 자금으로 구매·강화하고, 재료를 팔고, 장비를 교체한 뒤 보스에게 갑니다. 입장 시 체력·회피·감속장·방벽이 모두 준비된 상태로 시작합니다.</p>
      ${cleared && rec ? `<div class="card ok"><div class="card-title">첫 처치 기록</div><p>${rec.time}초 · 재도전 ${rec.retries}회 · ${esc(rec.weapon)}${rec.upgrade ? ' +' + rec.upgrade : ''} · 보스에게 준 피해 ${rec.bossDamage}</p></div>` : ''}
      <div class="grid2"><div>
        ${bossCard(run, true)}
        <div class="card"><div class="card-title">준비</div><div class="actions">
          <button class="primary big" data-action="boss-start">${cleared ? '이번 빌드로 보스 다시 도전' : '보스에게 간다 (입장)'}</button>
          <button class="big" data-action="shop">상점 · 대장간 · 재료 판매</button>
          ${cleared ? '<button class="big" data-action="newrun-confirm">새 회차 시작</button>' : ''}
          <button data-action="save-quit">저장 후 종료</button></div></div>
        <div class="card"><div class="card-title">재료</div>${matsRow(run)}</div>
      </div><div>${gearPanel(run)}${buildPanel(run)}
        <div class="card"><div class="card-title">최근 기록</div>${run.log.length ? `<ul class="log">${run.log.map(l => `<li>${esc(l)}</li>`).join('')}</ul>` : '<p class="dim">아직 없음</p>'}</div>
      </div></div></div>`;
  }
  function base(G) {
    const run = G.run;
    if (run.phase !== 'prep') return finalPrep(G);
    const canRest = R().canRest(run);
    return `<div class="screen">${header(run)}
      <div class="grid2">
        <div>
          ${targetCard(run)}
          ${bossCard(run, false)}
          <div class="card"><div class="card-title">오늘 할 일</div>
            <div class="actions">
              ${run.growth.pendingLevelUps ? `<button class="primary big" data-action="resolve-levelup">미처리 레벨업 선택 (${run.growth.pendingLevelUps})</button>` : ''}
              <button class="${run.growth.pendingLevelUps ? '' : 'primary'} big" data-action="map">출격 · 지역 선택</button>
              <button class="big" data-action="shop">상점 · 대장간</button>
              <button class="big" data-action="rest" ${canRest ? '' : 'disabled'}>휴식 (1시간, 체력 완전 회복)${canRest ? '' : run.hp >= R().build(run).hpMax ? ' · 체력 가득' : ' · 시간 부족'}</button>
              <button class="big" data-action="endday-confirm">하루 종료 → ${run.day + 1}일차${run.day + 1 >= PA.CONFIG.BOSS_DAY ? ' <span class="warn">(보스 도래)</span>' : ''}${run.hours > 0 ? ` <span class="dim">(남은 ${run.hours}시간 버림)</span>` : ''}</button>
              <button data-action="save-quit">저장 후 종료</button>
            </div></div>
          ${Object.keys(run.services || {}).some(k => run.services[k] > 0) ? `<div class="card"><div class="card-title">거점 서비스</div><p>${Object.keys(run.services).filter(k => run.services[k] > 0).map(k => `<b>${esc(PA.SERVICES[k].name)}</b> ×${run.services[k]} <span class="dim small">${esc(PA.SERVICES[k].desc)}</span>`).join('<br>')}</p></div>` : ''}
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
      const lr = R().layoutRegion(r.id, run), hpm = R().hpMultFor(run, r.id, false).normal;
      const enemies = R().regionEnemies(r.id, run).map(id => `<li><b>${esc(PA.ENEMIES[id].name)}</b> <span class="dim">${esc(PA.ENEMIES[id].role)} — ${esc(PA.ENEMIES[id].readme)}</span></li>`).join('');
      return `<div class="card region ${can ? '' : 'off'}">
        <div class="card-title">${esc(r.name)} <span class="risk">위험 ${stars(r.risk)}</span> <span class="cost-badge">${r.cost}시간</span></div>
        <p>${esc(lr ? lr.desc : r.desc)}${lr ? ' <span class="tag">시험안 배치</span>' : ''}${hpm !== 1 ? ` <span class="tag">체력 ×${hpm}</span>` : ''}</p>
        <div class="kv"><span>목적</span><b>${R().encounterObjective(r.id, false, run) === 'elite' ? '정예 처치' : '전멸'} · ${R().encounterWaves(r.id, false, run).length}웨이브</b></div>
        <div class="kv"><span>보상</span><b>${rewardText}</b>${forTarget ? ' <span class="tag">목표 장비 재료</span>' : ''}</div>
        <div class="kv"><span>성장</span><b>${esc(PA.REGION_TAG_TEXT[r.id] || '—')}</b> <span class="dim small">경험치 +${PA.GROWTH.REGION_BONUS_XP[r.id]} · 더 깊이 승리 시 지역 보상 선택</span></div>
        <ul class="enemies">${enemies}</ul>
        <button class="primary" data-action="sortie" data-arg="${r.id}" ${can ? '' : 'disabled'}>${can ? `출격 (${r.cost}시간 사용 → ${run.hours - r.cost}시간 남음)` : run.phase !== 'prep' ? '7일차: 출격 종료' : '시간 부족'}</button>
      </div>`;
    }).join('');
    return `<div class="screen">${header(run)}
      <div class="row between"><h2>출격</h2><button data-action="base">거점으로</button></div>
      <h3>오늘의 출격 카드 <span class="dim small">하루 3장 · 아침에 확정(다시 굴리기 없음) · 임무는 하루 1회 완료</span></h3>
      <div class="grid3">${missionCards(run)}</div>
      <h3>일반 탐험 <span class="dim small">지역 선택 · 승리 후 더 깊이 탐험 가능</span></h3>
      <p class="dim">출격 비용은 출발 시 차감됩니다. 전투가 오래 걸려도 추가로 시간을 빼지 않습니다. 조우 승리 후 "더 깊이 탐험"은 별도로 1시간을 씁니다.</p>
      <div class="grid3">${cards}</div></div>`;
  }
  // 출격 카드: 지역+목표, 시간, 주요 적 2~3, 위험 조건, 보상 종류·대상, 빌드 연결, 첫 도입
  function missionCards(run) {
    return PA.Sortie.cardsFor(run).map(c => {
      const r = R().region(c.regionId), O = PA.OBJECTIVES[c.objective], can = PA.Sortie.canStart(run, c), M = PA.MISSIONS;
      const enemies = c.enemies.map(id => `<li><b>${esc(PA.ENEMIES[id].name)}</b> <span class="dim">${esc(PA.ENEMIES[id].role)}</span></li>`).join('');
      const rewardGold = `금화 ${Math.round(r.reward.gold[0] * (c.risk ? M.riskRewardMult : 1))}~${Math.round(r.reward.gold[1] * (c.risk ? M.riskRewardMult : 1))}`;
      const riskDesc = c.risk === 'reinforce' ? '지원병 총량 ×1.5, 동시 수 동일' : c.risk === 'escort' ? '첫 웨이브에 정예 1 추가' : '주기적 바닥 붕괴 예고, 안전 통로 있음';
      return `<div class="card region mission ${can ? '' : 'off'} ${c.done ? 'done' : ''}">
        <div class="card-title">${esc(r.name)} · ${esc(O.name)} <span class="cost-badge">${c.timeCost}시간</span>${c.first ? ' <span class="tag">첫 도입</span>' : ''}${c.linked ? ' <span class="tag">내 빌드</span>' : ''}</div>
        <p>${esc(O.desc)}</p>
        <div class="kv"><span>주요 적</span><b>${c.enemies.map(id => esc(PA.ENEMIES[id].name)).join(', ')}</b></div>
        <div class="kv"><span>위험 조건</span><b>${c.risk ? esc(M.riskText[c.risk]) + ' <span class="dim small">(' + riskDesc + ')</span>' : '없음'}</b></div>
        <div class="kv"><span>보상</span><b>${esc(M.kindText[c.rewardKind])}${c.rewardTarget ? ' <span class="dim small">' + esc(c.rewardTarget) + '</span>' : ''}</b></div>
        <div class="kv"><span>기타</span><b>${rewardGold}${c.risk ? ' (위험 ×' + M.riskRewardMult + ')' : ''} · 처치 경험치 즉시 · 지역 경험치 +${PA.GROWTH.REGION_BONUS_XP[c.regionId]}</b> <span class="dim small">재료 대신 위 3택. 후보가 없으면 금화 +${c.fallbackGold}</span></div>
        <ul class="enemies">${enemies}</ul>
        <button class="primary" data-action="mission" data-arg="${c.id}" ${can ? '' : 'disabled'}>${c.done ? '오늘 완료' : can ? `임무 출격 (${c.timeCost}시간 → ${run.hours - c.timeCost}시간 남음)` : run.phase !== 'prep' ? '출격 종료' : '시간 부족'}${c.attempts && !c.done ? ` · 시도 ${c.attempts}` : ''}</button>
      </div>`;
    }).join('');
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
    const run = G.run, rw = G.lastReward, g = run.growth;
    const matText = Object.keys(rw.mats).map(k => `${matName(k)} ${rw.mats[k]}`).join(', ');
    return `<div class="screen"><h2>조우 승리</h2>
      <div class="card"><div class="card-title">보상 (귀환 시 거점에 반영)</div>
        <p>금화 <b class="gold">+${rw.gold}</b>${rw.chestGold ? ` (보급 상자 +${rw.chestGold} 포함)` : ''}${matText ? ` · ${matText}` : ''} · 지역 경험치 <b class="gold">+${rw.xp || 0}</b>${rw.mission ? (rw.missionPick ? ' · <b>임무 완료: 보상 3택은 다음 단계에서</b>' : ' · 임무(오늘 이미 완료: 추가 3택 없음)') : ''}</p>
        <p class="dim small">처치 ${G.lastStats.kills}${G.lastStats.savingKills ? ` (감속장 안 ${G.lastStats.savingKills})` : ''} · 받은 피해 ${Math.round(G.lastStats.damageTaken)} · ${Math.round(G.lastStats.elapsed)}초 · 전투 중 경험치 ${G.lastStats.xp} · 레벨업 ${G.lastStats.levelUps}회 (Lv ${g.level})</p></div>
      ${g.pendingLevelUps ? `<div class="card boss"><div class="card-title">미처리 레벨업 ${g.pendingLevelUps}</div><p>조우 종료와 동시에 오른 레벨입니다. 지금 선택합니다.</p><button class="primary" data-action="resolve-levelup">선택하기</button></div>` : ''}
      <div class="row"><button class="primary big" data-action="after-reward">다음</button></div></div>`;
  }
  function after(G) {
    const run = G.run, s = G.sortie, r = R().region(s.regionId), b = R().build(run);
    const canDeep = !s.deep && R().canDeepExplore(run, s);
    const lootText = `금화 ${s.loot.gold}` + Object.keys(s.loot.mats).map(k => `, ${matName(k)} ${s.loot.mats[k]}`).join('');
    return `<div class="screen center"><h2>${esc(r.name)} · 다음 행동</h2>
      <p>체력 <b>${run.hp} / ${b.hpMax}</b> · 이번 출격 전리품: <b>${lootText}</b> · 오늘 남은 시간 <b>${run.hours}</b></p>
      <div class="menu">
        <button class="big ${canDeep ? '' : 'off'}" data-action="deep" ${canDeep ? '' : 'disabled'}>더 깊이 탐험 (+1시간) <span class="dim">적 수 +1, 마지막에 정예. 보상 ×${PA.CONFIG.DEEP_REWARD_MULT}${s.deep ? ' · 이미 탐험함' : s.mission ? ' · 임무 출격에서는 불가' : (canDeep ? '' : ' · 시간 부족')}</span></button>
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
  function bossDefeat(G) {
    const run = G.run, s = G.lastStats;
    return `<div class="screen center"><h2 class="bad">쓰러졌다</h2><p>${esc(PA.BOSS.name)}에게 패배했습니다. 준비 기간의 성과는 그대로입니다. 같은 장비·무기·증강으로 바로 다시 도전할 수 있습니다.</p><p class="dim small">재도전은 입장 시점의 상태로 복구됩니다: 레벨·경험치·전투 중 선택은 입장 전으로, 체력·회피·감속장·E는 초기화, 보스·소환 늑대·구슬은 처음부터.</p>
      <p class="dim small">전투 ${Math.round(s.elapsed)}초 · 보스에게 준 피해 ${Math.round(s.bossDamage)} / ${PA.BOSS.hp} · 감속장 ${s.specialUses}회 · 재도전 ${run.bossRetries}회</p>
      <div class="menu"><button class="primary big" data-action="boss-start">같은 준비로 재도전</button><button class="big" data-action="base">최종 준비 화면으로</button><button class="big" data-action="title">제목으로</button></div></div>`;
  }
  function bossVictory(G) {
    const run = G.run, s = G.lastStats, b = R().build(run), rec = G.lastRecord || run.lastBossClear || {};
    const augs = Object.keys(run.augments).filter(k => run.augments[k] > 0).map(k => { const d = PA.AUGMENTS.find(a => a.id === k); return d.name + (d.max > 1 ? ' ' + run.augments[k] : ''); }).join(', ') || '없음';
    return `<div class="screen center"><h1>예언의 날을 넘겼다.</h1><h2>${esc(PA.BOSS.name)} — ${esc(PA.BOSS.title)} 처치</h2>
      <div class="card"><div class="card-title">회차 결과</div>
        <ul class="gear" style="text-align:left">
          <li>전투 시간: <b>${Math.round(s.elapsed * 10) / 10}초</b> · 재도전 <b>${run.bossRetries}회</b></li>
          <li>무기: <b>${esc(b.weapon.name)}${run.gear.upgrade ? ' +' + run.gear.upgrade : ''}</b> · 장신구: <b>${run.gear.acc ? esc(R().item(run.gear.acc).name) : '없음'}</b> · 방어구: <b>${run.gear.armor ? esc(R().item(run.gear.armor).name) : '없음'}</b></li>
          <li>증강: ${esc(augs)}</li>
          <li>감속장 사용 <b>${s.specialUses}</b>회 · 보스에게 준 총피해 <b>${Math.round(s.bossDamage)}</b> (실제 체력 감소 기준)</li>
          <li class="dim small">첫 처치 기록${G.firstClearNew ? '으로 저장됨' : ': ' + (run.bossClear ? run.bossClear.time + '초' : '—')} · 효과별 피해 통계는 후속</li>
        </ul></div>
      <div class="menu"><button class="primary big" data-action="boss-start">이번 빌드로 보스 다시 도전</button><button class="big" data-action="newrun-confirm">새 회차 시작</button><button class="big" data-action="title">제목으로</button></div></div>`;
  }
  function enddayConfirm(G) {
    const run = G.run;
    return `<div class="screen center"><h2>하루를 마칠까요?</h2><p>남은 ${run.hours}시간을 버리고 ${run.day + 1}일차로 넘어갑니다. 체력이 완전히 회복되고 시간이 5로 돌아옵니다.</p>
      ${run.day + 1 >= PA.CONFIG.BOSS_DAY ? `<div class="card boss"><div class="card-title">내일 ${esc(PA.BOSS.name)}가 도래합니다</div><p>7일차에는 일반 출격이 없습니다. 최종 준비(구매·강화·판매·장비 교체) 뒤 보스전에 들어갑니다. 패배해도 같은 준비로 바로 재도전할 수 있습니다.</p></div>` : `<p class="dim">보스 도래까지 ${R().bossDaysLeft(run) - 1}일 남음</p>`}
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
      <p class="dim">처치 ${s.kills}${s.savingKills ? ` (감속장 안 ${s.savingKills})` : ''} · 받은 피해 ${Math.round(s.damageTaken)} · 공격 ${s.attacks}회 · ${Math.round(s.elapsed)}초${s.bossDamage ? ` · 보스 피해 ${Math.round(s.bossDamage)} · 감속장 ${s.specialUses}회` : ''}</p>
      <div class="row"><button class="primary" data-action="scenario-again">같은 시드로 다시</button><button data-action="title">제목으로</button></div></div>`;
  }
  function controls() {
    return `<div class="panel"><h2>조작법</h2>
      <table class="keys"><tr><td>W A S D / 방향키</td><td>이동</td></tr><tr><td>Space</td><td>회피 (0.26초 무적, 이동 방향으로 구르기)</td></tr><tr><td>Q</td><td>감속장 (주변 적을 3초간 느리게)</td></tr><tr><td>E</td><td>선택 수동 기술 (레벨업에서 습득: 돌풍·칼날 폭풍·낙뢰·중력핵·수호 결계)</td></tr><tr><td>Esc</td><td>일시정지 / 메뉴</td></tr><tr><td>Enter · 클릭</td><td>메뉴 확인</td></tr></table>
      <h3>읽어야 할 것</h3><ul>
        <li><b>붉은 화살표</b>: 늑대가 돌진할 직선. 화살표가 굵어지며 "!"가 뜨면 방향이 고정된 것 — 옆으로 피하세요.</li>
        <li><b>붉은 점선</b>: 궁수의 조준선. 굵어지면 발사 직전.</li>
        <li><b>보라색 원</b>: 포자 구름이 생길 자리. 원 밖으로 나가세요. 구름은 5초간 남습니다.</li>
        <li><b>노란 별</b>: 빈틈. 이때 때리면 피해 1.5배.</li>
        <li>자동 공격은 사거리 안에 적이 있을 때만 가장 가까운 적을 향해 나갑니다.</li>
        <li><b>바위·나무</b>: 이동·회피·돌진을 막습니다. 검격·관통·회전 같은 <b>직접 공격</b>은 장애물 뒤를 때리지 못하지만, <b>불길·폭발·감속장·정지된 칼날</b>은 바닥 범위대로 적용됩니다.</li>
        <li><b>보스</b>: 붉은 통로(돌진), 부채꼴(휩쓸기), 원(덮쳐찍기), 발자국(늑대 등장). 큰 공격 뒤 "빈틈!"에 붙어서 때리세요. 감속장은 보스도 늦춥니다.</li></ul>
      <button data-action="close-overlay" class="primary">닫기</button></div>`;
  }
  function pause(G) {
    const lab = G.scenario && G.scenario.lab && G.combat ? `<div class="card"><div class="card-title small">시험실 설정</div><p class="small">${esc(G.combat.labText || '')}</p><p class="small dim">${esc(PA.Lab.encode(G.lab.cfg))}</p><div class="row"><button data-action="lab-abort">중단하고 결과 보기</button><button data-action="lab-back">설정 화면으로(결과 없이)</button></div></div>` : '';
    return `<div class="panel"><h2>일시정지</h2><p class="dim">전투가 멈춰 있습니다.</p>${lab}
      <div class="row"><label>음량 <input type="range" id="vol" min="0" max="100" value="${Math.round(PA.Audio.volume * 100)}"></label><label><input type="checkbox" id="mute" ${PA.Audio.muted ? 'checked' : ''}> 음소거</label></div>
      <div class="row"><button class="primary" data-action="resume">계속 (Esc)</button><button data-action="show-controls">조작법</button><button class="danger" data-action="give-up">포기하고 거점으로 (패배 처리)</button></div></div>`;
  }
  // ---------- 전투 시험실 ----------
  function lab(G) {
    const L = PA.Lab, cfg = G.lab.cfg, bd = L.describeBuild(cfg.build), ep = L.enemyPreset(cfg.enemy);
    const presets = L.enemyPresets(); const groups = [];
    for (const p of presets) { let g = groups.find(x => x.name === p.group); if (!g) { g = { name: p.group, items: [] }; groups.push(g); } g.items.push(p); }
    const sel = (id, opts, cur) => `<select id="${id}" data-lab="${id}">${opts.map(o => `<option value="${esc(o.v)}" ${String(o.v) === String(cur) ? 'selected' : ''}>${esc(o.t)}</option>`).join('')}</select>`;
    const hpOpts = PA.LAB.HP_MULTS.map(v => ({ v, t: '×' + v }));
    const enemySel = `<select id="lab-enemy" data-lab="lab-enemy">${groups.map(g => `<optgroup label="${esc(g.name)}">${g.items.map(p => `<option value="${esc(p.id)}" ${p.id === cfg.enemy ? 'selected' : ''}>${esc(p.name)}</option>`).join('')}</optgroup>`).join('')}</select>`;
    const buildSel = sel('lab-build', Object.keys(PA.LAB.BUILDS).map(k => ({ v: k, t: `[${PA.LAB.BUILDS[k].stage}] ${PA.LAB.BUILDS[k].name}` })), cfg.build);
    const notes = ep && ep.notes ? `<ul class="tips">${Object.entries({ intent: '의도한 판단', safe: '안전한 대응', builds: '강점 빌드', overlap: '과도한 겹침 조건', limit: '동시 실행 제한' }).filter(([k]) => ep.notes[k]).map(([k, t]) => `<li><b>${t}</b>: ${esc(ep.notes[k])}</li>`).join('')}</ul>` : '';
    const waves = ep && ep.waves ? ep.waves.map((w, i) => `${i + 1}: ` + w.map(g => `${PA.ENEMIES[g.type] ? PA.ENEMIES[g.type].name : g.type}×${g.n}`).join(', ')).join(' / ') : (ep && ep.boss ? '보스' : '');
    const results = (G.labResults || []).slice(-8).reverse();
    const rrow = (r) => { const en = Object.values(r.enemies || {}); const killed = en.reduce((a, e) => a + e.killed, 0), dba = en.reduce((a, e) => a + e.diedBeforeAttack, 0); return `<tr><td>${esc(statusText(r.status))}</td><td>${r.elapsed}s</td><td>${r.damageTaken}${r.absorbed ? ` (+막음 ${r.absorbed})` : ''}</td><td>${killed}/${en.reduce((a, e) => a + e.spawned, 0)}</td><td>${killed ? Math.round(dba / killed * 100) : 0}%</td><td class="small dim">${esc(r.configText.replace(/;arena=auto|;deep=0|;layout=classic|;overlap=-1/g, ''))}</td><td><button class="mini" data-action="lab-load" data-arg="${esc(r.configText)}">불러오기</button></td></tr>`; };
    return `<div class="screen"><div class="row between"><h2>전투 시험실 <span class="sub">정식 회차 저장과 분리 · v${PA.VERSION}</span></h2><button data-action="lab-exit">제목으로</button></div>
      <p class="dim small">처음이라면: 아래 기본값 그대로 <b>시작</b>을 누르고, 결과 화면에서 <b>체력 배율만 바꿔 재시작</b>으로 ×1 → ×2 → ×3을 비교하세요. 체력 배율은 체력에만 적용됩니다(공격력·속도·예고·경험치·보상 불변).</p>
      <div class="grid2"><div>
        <div class="card"><div class="card-title">적·전장</div>
          <div class="kv"><span>적 조합</span>${enemySel}</div>
          <p class="small dim">${esc(ep ? ep.desc || '' : '')}</p><p class="small">웨이브: ${esc(waves)}${ep && ep.arena ? ` · 기본 지형: ${esc(PA.LAB.TERRAINS[ep.arena] || ep.arena)}` : ''}${ep && ep.overlapLimit ? ` · 동시 공격 제한 ${ep.overlapLimit}` : ''}</p>${notes}
          <div class="kv"><span>지형</span>${sel('lab-arena', Object.keys(PA.LAB.TERRAINS).map(k => ({ v: k, t: PA.LAB.TERRAINS[k] })), cfg.arena)}</div>
          <div class="kv"><span>체력 배율</span>일반 ${sel('lab-hp-normal', hpOpts, cfg.hp.normal)} 정예 ${sel('lab-hp-elite', hpOpts, cfg.hp.elite)} 보스 ${sel('lab-hp-boss', hpOpts, cfg.hp.boss)}</div>
          <div class="kv"><span>시드</span><input id="lab-seed" data-lab="lab-seed" type="number" min="0" value="${cfg.seed}" style="width:110px"> <span class="dim small">같은 시드·같은 입력 = 같은 결과</span></div>
          <div class="kv"><span>동시 공격 제한</span>${sel('lab-overlap', [{ v: -1, t: '프리셋 기본' }, { v: 0, t: '없음' }, { v: 1, t: '1마리' }, { v: 2, t: '2마리' }, { v: 3, t: '3마리' }], cfg.overlap)}</div>
          <div class="kv"><span>시간 제한</span>${sel('lab-time', PA.LAB.TIME_LIMITS.map(v => ({ v, t: v + '초' })), cfg.time)} <label><input type="checkbox" id="lab-deep" data-lab="lab-deep" ${cfg.deep ? 'checked' : ''}> 더 깊이(지역 프리셋만: 적 +1, 정예)</label></div>
        </div>
        <div class="card"><div class="card-title">조작·성장</div>
          <div class="kv"><span>조작</span><label><input type="radio" name="lab-control" data-lab="lab-control" value="human" ${cfg.control === 'human' ? 'checked' : ''}> 직접 조작</label> <label><input type="radio" name="lab-control" data-lab="lab-control" value="bot" ${cfg.control === 'bot' ? 'checked' : ''}> 봇 조작</label> ${sel('lab-bot', Object.keys(PA.Bot.POLICIES).map(k => ({ v: k, t: PA.Bot.POLICIES[k].name })), cfg.bot)}</div>
          <p class="small dim">봇: ${esc(PA.Bot.POLICIES[cfg.bot].doc.reads)} · Q ${esc(PA.Bot.POLICIES[cfg.bot].doc.q)} · 포기 ${esc(PA.Bot.POLICIES[cfg.bot].doc.giveUp)}. 봇 결과는 정책 비교용이며 사람의 승률·재미를 뜻하지 않습니다.</p>
          <div class="kv"><span>성장</span><label><input type="radio" name="lab-growth" data-lab="lab-growth" value="fixed" ${cfg.growth === 'fixed' ? 'checked' : ''}> 빌드 고정(경험치 없음, 화력 고정)</label> <label><input type="radio" name="lab-growth" data-lab="lab-growth" value="grow" ${cfg.growth === 'grow' ? 'checked' : ''}> 성장 모드(레벨업 선택 적용)</label></div>
        </div>
        <div class="row"><button class="primary big" data-action="lab-start" style="width:auto">시작</button></div>
        <div class="card"><div class="card-title small">설정 복사 · 불러오기</div><textarea id="lab-config" rows="2" style="width:100%">${esc(L.encode(cfg))}</textarea><div class="row"><button class="mini" data-action="lab-apply">텍스트 적용</button><button class="mini" data-action="lab-reset">기본값</button></div><p class="dim small">주소로 열기: <code>index.html?lab=${esc(encodeURIComponent(L.encode(cfg)))}</code></p></div>
      </div><div>
        <div class="card"><div class="card-title">빌드 프리셋</div>
          <div class="kv"><span>빌드</span>${buildSel}</div>
          ${bd ? `<p><b>${esc(bd.name)}</b> <span class="kind">${esc(bd.stage)}</span> · 성장 선택 약 <b>${bd.picks}회</b> 상당(Lv ${bd.level}) ${bd.errors.length ? `<span class="bad">규칙 위반: ${esc(bd.errors.join(', '))}</span>` : '<span class="ok small">규칙 검사 통과</span>'}</p><p class="small">${esc(bd.purpose)}</p>
          <ul class="gear"><li>무기: ${bd.weapons.map(esc).join(' · ')}</li><li>공통 증강: ${bd.commons.length ? bd.commons.map(esc).join(', ') : '없음'}</li><li>패시브: ${bd.passives.length ? bd.passives.map(esc).join(', ') : '없음'}</li><li>Q: ${esc(bd.q)} · E: ${esc(bd.e)}</li><li>장비: ${bd.gear.length ? bd.gear.map(esc).join(', ') : '없음'}</li></ul>
          <p class="dim small">"초반/중간/후반"은 시험용 분류입니다. 실제 회차에서 이 조합을 얻을 확률을 보장하지 않으며, 강도 비교 시 선택 횟수와 장비 차이를 함께 보세요.</p>` : ''}
        </div>
        <div class="card"><div class="card-title">최근 결과 <span class="sub">${(G.labResults || []).length}건 · 브라우저에 보관</span></div>${results.length ? `<div style="overflow-x:auto"><table class="keys small"><tr><th>결과</th><th>시간</th><th>체력 피해</th><th>처치</th><th>공격 전 사망</th><th>설정</th><th></th></tr>${results.map(rrow).join('')}</table></div><div class="row"><button class="mini" data-action="lab-csv">CSV 보기</button><button class="mini" data-action="lab-clear-results">결과 지우기</button></div>${G.labCsv ? `<textarea rows="6" style="width:100%">${esc(G.labCsv)}</textarea>` : ''}` : '<p class="dim">아직 없음</p>'}</div>
      </div></div></div>`;
  }
  function statusText(s) { return { won: '승리', lost: '패배', timeout: '시간 초과', aborted: '사용자 중단' }[s] || s; }
  function labResult(G) {
    const r = G.labResult, cfg = G.lab.cfg, L = PA.Lab;
    const en = Object.keys(r.enemies).map(k => { const e = r.enemies[k]; const name = (PA.ENEMIES[k.split(':')[0]] || { name: k }).name + (k.includes(':summoned') ? '(소환)' : ''); return `<tr><td>${esc(name)}</td><td>${e.spawned}</td><td>${e.killed}</td><td>${e.prepared}</td><td>${e.executed}</td><td>${e.killed ? Math.round(e.diedBeforeAttack / e.killed * 100) + '%' : '—'} (${e.diedBeforeAttack})</td><td>${e.ttkAvg != null ? e.ttkAvg + 's' : '—'}</td><td>${e.ttkFromHitAvg != null ? e.ttkFromHitAvg + 's' : '—'}</td><td>${e.deathEffects || 0}</td></tr>`; }).join('');
    const taken = Object.keys(r.taken).map(k => `<li>${esc(takenName(k))}: <b>${Math.round(r.taken[k])}</b> (${r.takenHits[k]}회)</li>`).join('') || '<li class="dim">없음</li>';
    const dmg = Object.keys(r.dmg).sort((a, b) => r.dmg[b].amount - r.dmg[a].amount).map(k => `<li>${esc(dmgName(k))}: <b>${r.dmg[k].amount}</b> (${Math.round(r.dmg[k].share * 100)}%)</li>`).join('') || '<li class="dim">없음</li>';
    const hpOpts = PA.LAB.HP_MULTS.map(v => `<option value="${v}" ${v === cfg.hp.normal ? 'selected' : ''}>×${v}</option>`).join('');
    return `<div class="screen"><h2>시험 결과: <span class="${r.status === 'won' ? 'ok' : r.status === 'lost' ? 'bad' : 'gold'}">${esc(statusText(r.status))}</span> <span class="sub">${r.elapsed}초 · v${r.version} · 시드 ${r.seed}</span></h2>
      <p class="small dim">${esc(r.configText)}</p>
      <div class="grid2"><div>
        <div class="card"><div class="card-title">요약</div><ul class="gear">
          <li>체력 ${r.hp}/${r.hpMax} · 받은 체력 피해 <b>${r.damageTaken}</b> · 보호막 흡수 <b>${r.absorbed}</b></li>
          <li>처치 ${r.kills} · 감속장(Q) ${r.specialUses}회 · E ${r.eUses}회 · 회피 ${r.dodges}회${r.levelUps ? ` · 레벨업 ${r.levelUps}회(경험치 ${r.xp})` : ''}</li>
          <li>피해 기여 합계(실제 체력 감소, 과잉 피해 제외) ${r.dmgTotal}${r.heals ? ` · 적 치료 ${r.heals}회 ${r.healAmount}` : ''}${r.interrupts ? ` · 시전 방해 ${r.interrupts}회` : ''}${r.webs ? ` · 거미줄 ${r.webs}개` : ''}</li></ul>
          <div class="card-title small">받은 피해 원인</div><ul class="augs">${taken}</ul>
          <div class="card-title small">피해 기여도(무기·기술·지속·공통 효과)</div><ul class="augs">${dmg}</ul>
        </div>
        <div class="row"><button class="primary" data-action="lab-restart">같은 조건으로 재시작</button><span>체력 배율만 바꿔 재시작: 일반 <select id="lab-result-hp">${hpOpts}</select></span><button data-action="lab-restart-hp">재시작</button><button data-action="lab">설정 화면으로</button><button data-action="lab-exit">제목으로</button></div>
      </div><div>
        <div class="card"><div class="card-title">몬스터 종류별</div><div style="overflow-x:auto"><table class="keys small"><tr><th>종류</th><th>등장</th><th>처치</th><th>공격 준비</th><th>실행</th><th>공격 전 사망</th><th>등장→처치</th><th>첫 피격→처치</th><th>사망 효과</th></tr>${en}</table></div><p class="dim small">준비 = 예고 시작, 실행 = 판정 발생. 사망 효과(포자 구름 등)는 능동 공격과 따로 셉니다. 소환 몬스터는 별도 행.</p></div>
        <div class="card"><div class="card-title small">JSON</div><textarea rows="5" style="width:100%">${esc(JSON.stringify(r))}</textarea><div class="card-title small">CSV 한 줄(머리글 포함)</div><textarea rows="3" style="width:100%">${esc(L.CSV_COLS.join(',') + '\n' + L.csvRow(r))}</textarea></div>
      </div></div></div>`;
  }
  const TAKEN_NAMES = { wolf: '늑대 물기', arrow: '궁수 화살', zone: '바닥 지역(구름 등)', boss_sweep: '보스 휩쓸기', boss_dash: '보스 돌진', boss_pounce: '보스 덮쳐찍기', boar: '멧돼지 돌파', bash: '방패병 방패치기', hex: '주술사 저주', blast: '폭탄 폭발', emerge: '잠복충 출현', bite: '물기', frostzone: '서리 폭발', slash: '도적 베기' };
  function takenName(k) { return TAKEN_NAMES[k] || k; }
  function dmgName(k) { const [kind, id] = k.split(':'); if (kind === 'weapon') return '무기 ' + (PA.WEAPONS[id] ? PA.WEAPONS[id].name : id); if (kind === 'skill') return '기술 ' + (PA.SKILLS[id] ? PA.SKILLS[id].name : id); if (kind === 'dot') return { burn: '화상', bleed: '출혈' }[id] || id; if (kind === 'common') return '공통 ' + (PA.COMMONS[id] ? PA.COMMONS[id].name : id); if (kind === 'reward') return '보상 ' + (PA.BOSS_REWARDS[id] ? PA.BOSS_REWARDS[id].name : id); return k; }
  // 보스 초상(카드용 작은 캔버스): 렌더러의 보스 그리기를 재사용
  function paintPortraits() {
    for (const c of document.querySelectorAll('canvas.bossportrait')) {
      const ctx = c.getContext('2d'); ctx.fillStyle = '#1b2118'; ctx.fillRect(0, 0, c.width, c.height);
      const fake = { arena: PA.CONFIG.ARENA, obstacles: [], player: { x: 400, y: 45, r: 14 }, enemies: [], effects: [], zones: [], pickups: [], field: null, t: 0, boss: null, markTarget: null };
      const e = { boss: true, type: 'boss', def: PA.ENEMIES.boss, x: 70, y: 52, r: 42, hp: 1, hpMax: 1, state: 'intro', stateT: 0, animT: 0, moveT: 0, faceX: 1, flash: 0, chill: 0, stasis: 0, biteT: 9, dead: false, deathT: 0, aimAngle: 0, dir: 0, leapK: 0 };
      ctx.save(); ctx.scale(0.8, 0.8); PA.Render.drawBoss(ctx, fake, e); ctx.restore();
    }
  }
  return { title, newrunConfirm, base, finalPrep, map, shop, reward, after, defeat, bossDefeat, bossVictory, enddayConfirm, bossday, scenarioEnd, controls, pause, paintPortraits, bossCard, pickStart, levelCards, migration, lab, labResult, statusText };
})();
