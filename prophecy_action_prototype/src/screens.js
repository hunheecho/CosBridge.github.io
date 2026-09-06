// DOM 화면(전투 밖). HTML 문자열을 만들고 data-action으로 main에 동작을 위임한다.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Screens = (function () {
  const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const R = () => PA.Run;
  const stars = (n) => '★'.repeat(n) + '☆'.repeat(3 - n);
  const matName = (k) => PA.MATERIALS[k].name;
  const hoursPips = (h, max) => `<span class="pips">${Array.from({ length: max }, (_, i) => `<i class="${i < h ? 'on' : ''}"></i>`).join('')}</span>`;
  const costText = (cost) => `금화 ${cost.gold}` + Object.keys(cost.mats || {}).map(k => ` + ${matName(k)} ${cost.mats[k]}`).join('');

  const slotStrip = (run) => { const cur = R().slotIndex(run), done = run.hours <= 0; return `<span class="slots">${PA.TIME_SLOTS.map((n, i) => `<i class="${done || i < cur ? 'past' : i === cur ? 'now' : ''}">${n}</i>`).join('')}</span>`; };
  const settingsShort = (run) => `v${PA.VERSION} · ${PA.BALANCE_SETS[run.balance] ? PA.BALANCE_SETS[run.balance].name : run.balance}`;
  function header(run) {
    const b = R().build(run), left = R().bossDaysLeft(run), nb = R().nextBoss(run), nbc = R().nextBossCfg(run), stages = R().stageCount(run);
    return `<div class="topbar">
      <div class="stat"><span class="lbl">날짜</span><b>${run.day}일차</b></div>
      <div class="stat wide"><span class="lbl">시간대 <span class="dim">(남은 ${run.hours}칸)</span></span>${slotStrip(run)}</div>
      <div class="stat boss"><span class="lbl">${stages > 1 ? `보스 ${(run.stage || 0) + 1}/${stages} · ${esc(nbc.name)}` : '보스'}</span><b class="${left <= 1 ? 'warn' : ''}">${!nb ? '완료' : left > 0 ? left + '일 뒤' : '오늘'}</b></div>
      <div class="stat"><span class="lbl">체력</span><b>${run.hp} / ${b.hpMax}</b></div>
      <div class="stat"><span class="lbl">금화</span><b class="gold">${run.gold}</b></div>
      <div class="stat"><span class="lbl">설정</span><b class="small dim" title="${esc(PA.Balance.text(run))}">${esc(settingsShort(run))}</b></div>
    </div>`;
  }
  function matsRow(run) {
    return `<div class="mats">${Object.keys(PA.MATERIALS).map(k => `<span class="mat ${run.mats[k] ? '' : 'zero'}">${matName(k)} <b>${run.mats[k] || 0}</b></span>`).join('')}</div>`;
  }
  // 다가오는 보스 정보(준비 기간부터 공개)
  function bossCard(run, full) {
    const B = R().nextBossCfg(run), left = R().bossDaysLeft(run), nb = R().nextBoss(run), stages = R().stageCount(run);
    const when = run.phase === 'cleared' ? '처치함' : left > 0 ? `${left}일 뒤 도래` : '오늘 도래';
    const desc = { boss: '숲과 늑대 무리를 지배하는 거대한 늑대. 목과 등에 부러진 나뭇가지 같은 검은 가시가 돋았고, 한쪽 송곳니가 부러졌다.', guardian: '봉인을 지키는 돌 갑옷의 거인. 느리지만 한 번의 휩쓸기가 무겁고, 봉인 장치가 바닥을 위험하게 만든다.', eater: '예언을 삼키는 시간의 포식자. 당신이 지나온 자리를 표식으로 찍고, 두 줄의 직선과 광역으로 공간을 좁힌다.' }[B.id];
    const hp = R().bossHp(run, B.id);
    if (!full) return `<div class="card boss compact"><div class="card-title">${stages > 1 ? `${(run.stage || 0) + 1}단계 보스` : '보스'}: ${esc(B.name)} <span class="tag">${when}</span> <span class="sub">${esc(B.info[0] || '')}</span></div></div>`;
    return `<div class="card boss"><div class="card-title">${stages > 1 ? `${(run.stage || 0) + 1}단계 보스` : '다가오는 보스'}: ${esc(B.name)} — ${esc(B.title)} <span class="tag">${when}</span></div>
      <div class="bossart">${B.id === 'boss' ? '<canvas class="bossportrait" width="160" height="90"></canvas>' : ''}<div><p>${esc(desc)}</p>
      <ul class="tips">${B.info.map(t => `<li>${esc(t)}</li>`).join('')}</ul>
      <p class="dim small">전장: ${esc(PA.ARENAS.clearing.name)} · 체력 ${hp} · 단계 전환 ${B.phases.map(p => Math.round(p * 100) + '%').join('·')} · 시간제한 없음${nb && nb.rare ? ' · 승리 시 희귀 보상 3택' : ''}</p></div></div></div>`;
  }
  // 장비 한 줄 요약(효과 핵심). 세부는 용어 사전
  const equipLine = (id) => { const d = PA.EQUIPMENT[id]; return `<b>${esc(d.name)}</b> <span class="dim">${esc(d.short)}</span>`; };
  function equipPanel(run) {
    const eq = run.equipment, b = R().build(run);
    const rows = PA.EQUIP_SLOTS.map(sl => `<li><span class="lbl">${esc(PA.EQUIP_SLOT_NAMES[sl])}</span> ${eq[sl] ? equipLine(eq[sl]) : '<span class="dim">비어 있음</span>'}</li>`).join('');
    return `<div class="card"><div class="card-title">장비 <span class="sub">슬롯당 1개 · 이번 회차 한정 · 가방 ${run.bag.length}개</span></div><ul class="gear">${rows}</ul>
      <p class="dim small">최대 체력 ${b.hpMax} · 이동 ×${PA.fmt.num(b.speedMult)} · 시작 보호막 ${b.shield || 0}${b.forge ? ` · 공용 공격 강화 ${b.forge}단계(자동기술 피해 ×${PA.fmt.num(b.forgeMult)})` : ''}</p></div>`;
  }
  function buildPanel(run) {
    const b = R().build(run), g = PA.Growth.ensure(run), S = PA.GROWTH.SLOTS;
    const wrows = b.weapons.map((w, i) => `<li><b>${esc(w.name)}</b> Lv${w.level}/${S.weaponMax} <span class="dim">피해 ${PA.fmt.num(w.damage)} · 주기 ${PA.fmt.num(w.interval)}초${w.range ? ' · 사거리 ' + Math.round(w.range) : ''}</span> <span class="small">개조 ${w.mods.length}/${S.weaponMods}: ${w.mods.length ? w.mods.map(mid => esc(w.def.mods[mid].name)).join(', ') : '없음'}</span></li>`).join('');
    const empties = Array.from({ length: S.weapons - b.weapons.length }, () => '<li class="dim">빈 자동기술 슬롯 (레벨업 또는 상점)</li>').join('');
    const commons = Object.keys(g.commons).filter(k => g.commons[k] > 0).map(k => `<b>${esc(PA.COMMONS[k].name)}</b>${PA.COMMONS[k].max > 1 ? ` ${g.commons[k]}/${PA.COMMONS[k].max}` : ''}`).join(', ');
    const passives = Object.keys(g.passives).filter(k => g.passives[k] > 0).map(k => `<b>${esc(PA.PASSIVES[k].name)}</b> ${g.passives[k]}/${PA.PASSIVES[k].max}`).join(', ');
    const sk = (slot) => { const x = g.skills[slot]; if (!x) return `<li><b>E</b>: <span class="dim">비어 있음 (레벨업 또는 상점)</span></li>`; const d = PA.SKILLS[x.id]; return `<li><b>${d.key}</b>: <b>${esc(d.name)}</b> Lv${x.level}/${S.skillMax} <span class="dim">재사용 ${PA.fmt.num(PA.SKILLS[x.id].cooldown[x.level - 1] * b.skillCdMult)}초${x.variant ? ' · 변형: ' + esc(d.variants[x.variant].name) : ''}</span></li>`; };
    const steer = g.steer ? `<p class="small"><span class="tag">성장 예약</span> 다음 레벨업은 <b>${esc(PA.Sortie.kindName(g.steer.kind))}</b> 후보만 제시 (${g.steer.from === 'deep' ? '심층 보상' : '임무 보상'}, 1회)</p>` : '';
    return `<div class="card"><div class="card-title">성장 <span class="sub">Lv ${g.level} · 경험치 ${Math.floor(g.xp)}/${PA.Growth.xpNeed(g.level)}${g.pendingLevelUps ? ` · <b class="warn">미처리 레벨업 ${g.pendingLevelUps}</b>` : ''}</span></div>
      ${steer}
      <div class="card-title small">자동기술 ${b.weapons.length}/${S.weapons}</div><ul class="gear">${wrows}${empties}</ul>
      <div class="card-title small">수동 기술</div><ul class="gear">${sk('q')}${sk('e')}</ul>
      <p class="small">공용 증강 ${PA.Growth.commonCount(g)}/${S.commons}: ${commons || '<span class="dim">없음</span>'} · 패시브 ${PA.Growth.passiveCount(g)}/${S.passives}: ${passives || '<span class="dim">없음</span>'}${g.bossRewards.length ? ` · 희귀 보상: ${g.bossRewards.map(id => `<b>${esc(PA.BOSS_REWARDS[id].name)}</b>`).join(', ')}` : ''}</p></div>`;
  }
  function logCard(run, n) { const L = run.log.slice(0, n || 6); return `<details class="card small"><summary>최근 기록 ${L.length ? `<span class="dim">· ${esc(L[0])}</span>` : ''}</summary>${L.length ? `<ul class="log">${L.map(l => `<li>${esc(l)}</li>`).join('')}</ul>` : '<p class="dim">아직 없음</p>'}</details>`; }

  // 시작 무기 선택
  function pickStart(G) {
    const list = (G.startAll ? PA.STARTABLE_ALL : PA.STARTABLE).map(id => { const d = PA.WEAPONS[id]; return `<div class="card"><div class="card-title">${esc(d.name)}</div><p>${esc(d.desc)}</p><p class="dim small">기본 피해 ${d.base.damage} · 주기 ${d.base.interval}초 · 전용 방식: ${Object.values(d.mods).map(m => esc(m.name)).join(', ')}</p><button class="primary" data-action="start-weapon" data-arg="${id}">이 자동기술로 시작</button></div>`; }).join('');
    const laySel = `<select id="start-layout">${Object.keys(PA.LAYOUTS).map(k => `<option value="${k}">${esc(PA.LAYOUTS[k].name)}</option>`).join('')}</select>`;
    const modeSel = `<select id="start-mode">${Object.keys(PA.RUN_MODES).map(k => `<option value="${k}" ${k === 'trio' ? 'selected' : ''}>${esc(PA.RUN_MODES[k].name)}</option>`).join('')}</select>`;
    const balSel = `<select id="start-balance">${Object.keys(PA.BALANCE_SETS).map(k => `<option value="${k}" ${k === PA.BALANCE_DEFAULT ? 'selected' : ''} title="${esc(PA.BALANCE_SETS[k].desc)}">${esc(PA.BALANCE_SETS[k].name)}</option>`).join('')}</select>`;
    const difSel = `<select id="start-difficulty">${Object.keys(PA.DIFFICULTY.candidates).map(k => `<option value="${k}">${esc(PA.DIFFICULTY.candidates[k].name)}</option>`).join('')}</select>`;
    return `<div class="screen"><h2>시작 자동기술 선택</h2><p class="dim">자동기술 1개(Lv1, 개조 없음)·감속장(Q) Lv1·체력 100·금화 60으로 1일차 새벽에 시작합니다. 자동기술은 최대 3개, 장비(무기·방어구·방패)는 상점에서 삽니다.</p>
      <div class="card"><div class="card-title small">검증 메뉴: 지역 배치안·난이도 후보 <span class="dim">(기본값은 기존 배치·×1. 시험안은 검증되지 않은 임시값이며 화면에 표시됩니다)</span></div><div class="kv"><span>밸런스</span>${balSel} <span class="dim small">현재값 = 비교 기준. 추천안은 docs/sim/COMPARE_v071.md 비교 결과 기반 제안(적 체력·보스 체력·경험치·창). 확정값 아님</span></div><div class="kv"><span>회차 구조</span>${modeSel} <span class="dim small">3보스: 1~2일 준비 → 3일차 가시갈기 → 3~4일 → 5일차 봉인 수호자 → 5~6일 → 7일차 예언을 먹는 자</span></div><div class="kv"><span>배치</span>${laySel}</div><div class="kv"><span>난이도</span>${difSel}</div></div>
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
    const title = pool === 'boss' ? '보스 희귀 보상' : pool === 'deep' ? '지역 보상 선택' : pool === 'mission' ? `${offer.paidChange ? '개조·변형 변경' : '임무 보상'} · ${PA.MISSIONS.kindText[offer.missionKind] || '3택'}` : `레벨 업! Lv ${run.growth.level}${run.growth.pendingLevelUps > 1 ? ` (남은 선택 ${run.growth.pendingLevelUps})` : ''}${offer.steer ? ` <span class="tag">예약: ${esc(PA.Sortie.kindName(offer.steer))}</span>` : ''}`;
    return `<div class="panel wide"><h2>${title}</h2>${offer.regionId && pool !== 'boss' ? `<p class="dim small">지역 계열: ${esc(PA.REGION_TAG_TEXT[offer.regionId] || '—')}</p>` : ''}
      <div class="grid3">${cards.length ? cards : '<p class="dim">제시할 수 있는 후보가 없습니다.</p>'}</div>
      <div class="row">${pool === 'level' ? `<button data-action="skip">건너뛰기 (금화 +${PA.CONFIG.SKIP_AUGMENT_GOLD})</button>${R().hasService(run, 'reroll') ? `<button data-action="reroll">제시 재선택권 사용 (남은 ${run.services.reroll})</button>` : ''}` : pool === 'deep' || pool === 'mission' ? '<button data-action="skip">받지 않음</button>' : ''}</div></div>`;
  }
  function migration(G) {
    const run = G.run, mp = run.growth.migrationPending, sel = G.migSel || [];
    return `<div class="screen center"><h2>성장 시스템 이행</h2><p>이전 저장에 공통 증강이 ${mp.commons.length}개 있습니다. 새 규칙의 공통 슬롯은 3개입니다. 사용할 3개를 고르세요(나머지는 사라집니다).</p>
      <div class="grid3">${mp.commons.map(c => `<div class="card ${sel.includes(c.id) ? 'can' : ''}"><div class="card-title">${esc(PA.COMMONS[c.id].name)}${c.level > 1 ? ' ' + c.level + '단계' : ''}</div><p class="dim">${esc(PA.COMMONS[c.id].desc)}</p><button data-action="mig-toggle" data-arg="${c.id}">${sel.includes(c.id) ? '선택 해제' : '선택'}</button></div>`).join('')}</div>
      <div class="row"><button class="primary" data-action="mig-confirm" ${sel.length === Math.min(3, mp.commons.length) ? '' : 'disabled'}>확정 (${sel.length}/3)</button></div></div>`;
  }

  function title(G) {
    const hasSave = !!G.saved;
    return `<div class="screen center"><h1>예언의 시간표</h1><p class="subtitle">액션 프로토타입 · 마검사의 준비 기간 · <b>v${PA.VERSION}</b></p>
      <div class="menu">
        ${hasSave ? `<button class="primary big" data-action="continue">계속하기 <span class="dim">(${G.saved.day}일차 · 금화 ${G.saved.gold}${G.saved.migratedFrom ? ' · 이전 버전 저장(변환됨)' : ''})</span></button>` : ''}
        <button class="big ${hasSave ? '' : 'primary'}" data-action="newrun">새 회차</button>
        <button class="big" data-action="controls">조작법</button>
        <button class="big" data-action="lab">전투 시험실 <span class="dim">(정식 회차와 분리 · 체력 배율·빌드·적 조합 비교)</span></button>
        <div class="row"><span class="dim small">검증 메뉴 · 3보스 회차 빠른 경로(현재 저장을 덮어씀):</span>${[0, 1, 2].map(i => `<button class="mini" data-action="quick-run" data-arg="${i}">${i + 1}단계 관문 직전</button>`).join(' ')}</div>
      </div>
      <p class="dim small">${esc(PA.KEYS_TEXT)}</p><p class="dim small">기본 설정: ${esc(PA.Balance.text(null))}</p>${hasSave ? `<p class="dim small">저장된 회차 설정: ${esc(PA.Balance.text(G.saved))}</p>` : ''}</div>`;
  }
  function newrunConfirm() {
    return `<div class="screen center"><h2>새 회차를 시작할까요?</h2><p>기존 저장(진행 중인 회차)이 덮어씌워집니다.</p><div class="row"><button class="primary" data-action="newrun-confirm">새 회차 시작</button><button data-action="title">돌아가기</button></div></div>`;
  }
  function finalPrep(G) {
    const run = G.run, b = R().build(run), cleared = run.phase === 'cleared', stages = R().stageCount(run), g = run.growth;
    const recs = Object.values(run.bossRecords || {});
    return `<div class="screen">${header(run)}
      <h2>${run.day}일차 — ${cleared ? (stages > 1 ? '회차 완주' : '예언의 날을 넘겼다') : stages > 1 ? `${(run.stage || 0) + 1}단계 보스 관문` : '최종 준비'}</h2>
      <p class="dim">${cleared ? '마지막 보스를 넘었습니다. 이 회차의 성장은 여기서 끝납니다. 같은 빌드로 다시 도전하거나 새 회차를 시작하세요.' : '보스전은 하루 시간 밖의 관문입니다. 상점·대장간·장비 교체는 시간을 쓰지 않습니다. 패배하면 입장 시점으로 돌아와 같은 준비로 재도전합니다(하루 손실 없음).' + (stages > 1 && (run.stage || 0) < stages - 1 ? ' 승리하면 그날의 시간대가 새벽부터 시작됩니다.' : '')}</p>
      <div class="card"><div class="card-title small">입장 스냅샷</div><p class="dim small">Lv ${g.level} · ${g.weapons.map(w => PA.WEAPONS[w.id].name + ' Lv' + w.level).join(', ')} · 체력 ${b.hpMax} · 재도전 ${run.bossRetries || 0}회${run.bossRetries ? ' (입장 시점 상태로 복구됨: 처치 경험치·보상 중복 없음)' : ''}</p></div>
      ${recs.length ? `<div class="card ok"><div class="card-title">처치 기록</div>${recs.map(r => `<p>${esc(PA.BOSS_DEFS[r.bossId || 'boss'].name)}: ${r.time}초 · 재도전 ${r.retries}회 · Lv ${r.level || '-'} · 보스에게 준 피해 ${r.bossDamage}</p>`).join('')}</div>` : ''}
      <div class="grid2"><div>
        ${bossCard(run, true)}
        <div class="card"><div class="card-title">준비</div><div class="actions">
          <button class="primary big" data-action="boss-start">${cleared ? '이번 빌드로 보스 다시 도전' : '보스에게 간다 (입장)'}</button>
          <button class="big" data-action="shop">상점 · 대장간 · 장비</button>
          ${cleared ? '<button class="big" data-action="newrun-confirm">새 회차 시작</button>' : ''}
          <button data-action="save-quit">저장 후 종료</button></div></div>
      </div><div>${equipPanel(run)}${buildPanel(run)}${logCard(run)}</div></div></div>`;
  }
  // 오늘의 장소 카드: 이름·비용·목표·주요 적·위험·보상·지금 출발 시 변주. 상세는 접힘
  function placeCard(run, c) {
    const r = R().region(c.regionId), can = PA.Sortie.canStart(run, c), M = PA.MISSIONS, O = c.objective !== 'clear' ? PA.OBJECTIVES[c.objective] : null;
    const slot = R().slotIndex(run), v = run.hours > 0 ? R().slotVariant(c.regionId, slot) : null, hpm = R().hpMultFor(run, c.regionId, false);
    const elite = c.enemies.some(id => PA.ENEMIES[id].elite) || R().encounterWaves(c.regionId, false, run, { variant: v }).flat().some(g => PA.ENEMIES[g.type].elite);
    const gm = (c.risk ? M.riskRewardMult : 1) * (v && v.goldMult ? v.goldMult : 1);
    const reward = `금화 ${Math.round(r.reward.gold[0] * gm)}~${Math.round(r.reward.gold[1] * gm)}`;
    const steer = PA.Sortie.steerState(run, c);
    const riskDesc = c.risk === 'reinforce' ? '지원병 총량 ×1.5' : c.risk === 'escort' ? '첫 웨이브에 정예 1 추가' : c.risk === 'hazard' ? '주기적 바닥 붕괴(안전 통로 있음)' : '';
    const enemies = c.enemies.map(id => `<li><b>${esc(PA.ENEMIES[id].name)}</b> <span class="dim">${esc(PA.ENEMIES[id].role)} — ${esc(PA.ENEMIES[id].readme)}</span></li>`).join('');
    const others = Object.keys(PA.SLOT_VARIANTS[c.regionId] || {}).map(Number).filter(i => i !== slot).map(i => `${PA.TIME_SLOTS[i]} ${esc(PA.SLOT_VARIANTS[c.regionId][i].name)}`).join(' · ');
    const why = c.done ? '오늘 완료' : run.phase !== 'prep' ? '출격 불가' : run.hours < c.timeCost ? `시간 부족 (${c.timeCost}칸 필요)` : '';
    return `<div class="card region ${can ? '' : 'off'} ${c.done ? 'done' : ''}">
      <div class="card-title">${esc(r.name)} <span class="cost-badge">${c.timeCost}칸</span> <span class="sub">${O ? esc(O.name) : '전멸'}${elite ? ' · <b>정예</b>' : ''}${c.risk ? ' · <b class="warn">' + esc(M.riskText[c.risk]) + '</b>' : ''}</span></div>
      <p class="summary">${c.enemies.filter(id => !PA.ENEMIES[id].elite).slice(0, 3).map(id => esc(PA.ENEMIES[id].name)).join('·')} · ${reward}${hpm.normal !== 1 ? ` · 체력 ×${hpm.normal}` : ''}</p>
      <p class="small">${v ? `<span class="tag">${esc(PA.TIME_SLOTS[slot])} ${esc(v.name)}</span> ${esc(v.desc)}` : `<span class="dim">${esc(PA.TIME_SLOTS[Math.min(slot, 4)])} 출발: 기본 편성</span>`}${others ? ` <span class="dim small">· 다른 시간대: ${others}</span>` : ''}</p>
      ${O ? `<p class="small">보상: <b>${esc(steer.text)}</b>${c.rewardTarget ? ` <span class="dim">(${esc(c.rewardTarget)})</span>` : ''}</p>` : ''}
      <details><summary>상세</summary>
        ${O ? `<p class="dim">${esc(O.desc)}</p>` : `<p class="dim">${esc(r.desc)}</p>`}
        ${c.risk ? `<div class="kv"><span>위험 조건</span><b>${esc(M.riskText[c.risk])} <span class="dim small">(${riskDesc}) · 금화 ×${M.riskRewardMult}</span></b></div>` : ''}
        <div class="kv"><span>편성</span><b>${R().encounterWaves(c.regionId, false, run, { variant: v }).length}웨이브 · 전멸(웨이브·대기 포함)</b></div>
        <div class="kv"><span>경험치</span><b>처치 즉시 · 지역 +${R().regionBonusXp(c.regionId, false)}</b></div>
        <ul class="enemies">${enemies}</ul>
      </details>
      <button class="primary" data-action="mission" data-arg="${c.id}" ${can ? '' : 'disabled'}>${can ? `출격 (${c.timeCost}칸 · ${esc(PA.TIME_SLOTS[slot])} 출발)` : why}${c.attempts && !c.done ? ` · 시도 ${c.attempts}` : ''}</button>
    </div>`;
  }
  function merchantCard(run) {
    if (!run.merchant || run.merchant.day !== run.day) return '';
    const m = run.merchant, open = R().merchantOpen(run);
    if (!open) return `<div class="card compact"><div class="card-title small">방문 상인 <span class="dim">${esc(PA.TIME_SLOTS[m.fromSlot])}부터 하루 끝까지 · 장비 1개 할인(${Math.round(PA.SHOP.merchantDiscount * 100)}%)·무료 휴식권</span></div></div>`;
    return `<div class="card can"><div class="card-title">방문 상인 <span class="sub">오늘 끝까지 · 상점 화면에서 거래</span></div><p class="small">${m.equipment && !m.sold.includes(m.equipment) ? `${equipLine(m.equipment)} <b class="gold">${R().equipPriceFor(run, m.equipment, 'merchant')}</b> (${Math.round(PA.SHOP.merchantDiscount * 100)}% 할인)` : '<span class="dim">장비 품절</span>'} · 무료 휴식권 <b class="gold">${m.servicePrice}</b>${m.sold.includes('service') ? ' (판매됨)' : ''}</p><button class="mini" data-action="shop-tab" data-arg="merchant">상인에게</button></div>`;
  }
  function base(G) {
    const run = G.run;
    if (run.phase !== 'prep') return finalPrep(G);
    const canRest = R().canRest(run), full = run.hp >= R().build(run).hpMax, cards = PA.Sortie.cardsFor(run);
    const nx = R().previewNextDay(run);
    const nextText = nx.boss ? `<span class="warn">보스 관문 (${esc(PA.BOSS_DEFS[nx.boss].name)})</span>` : nx.places.map(p => `${esc(p.name)}${p.elite ? '(정예)' : ''}`).join(' · ');
    return `<div class="screen">${header(run)}
      <div class="grid2">
        <div>
          <h3>오늘의 장소 <span class="dim small">2곳 · 출발 시간대에 편성·사건·보상 확정 · 승리 후 더 깊이 1회</span></h3>
          ${cards.map(c => placeCard(run, c)).join('')}
          ${merchantCard(run)}
          <div class="card"><div class="card-title">거점</div>
            <div class="actions">
              ${run.growth.pendingLevelUps ? `<button class="primary big" data-action="resolve-levelup">미처리 레벨업 선택 (${run.growth.pendingLevelUps})</button>` : ''}
              <button class="big" data-action="shop">상점 · 대장간 · 장비 <span class="dim">(시간 소모 없음)</span></button>
              <button class="big" data-action="rest" ${canRest ? '' : 'disabled'}>${R().hasService(run, 'free_rest') ? '휴식 (무료 휴식권 · 시간 소모 없음)' : `휴식 → ${esc(R().nextSlotName(run))}`} <span class="dim">${full ? '체력 가득 · 시간만 넘김' : '체력 완전 회복'}${canRest ? '' : ' · 남은 칸 없음'}</span></button>
              <button class="big" data-action="endday-confirm">하루 종료 → ${run.day + 1}일차 <span class="dim">${run.hours > 0 ? `(남은 ${run.hours}칸 버림) · ` : ''}내일: ${nextText}</span></button>
              <button data-action="save-quit">저장 후 종료</button>
            </div></div>
          ${Object.keys(run.services || {}).some(k => run.services[k] > 0) ? `<div class="card compact"><div class="card-title small">보유 이용권</div><p class="small">${Object.keys(run.services).filter(k => run.services[k] > 0).map(k => `<b>${esc(PA.SERVICES[k].name)}</b> ×${run.services[k]}`).join(' · ')} <span class="dim">(개조 교체권·할인권은 상점·대장간에서 사용)</span></p></div>` : ''}
          ${bossCard(run, false)}
        </div>
        <div>${equipPanel(run)}${buildPanel(run)}${logCard(run)}</div>
      </div></div>`;
  }
  function map(G) { return base(G); }
  // 장비 비교: 같은 슬롯의 현재 장비 효과 vs 새 장비 효과. 적용되지 않는 조건도 표시
  function equipCompare(run, id) {
    const d = PA.EQUIPMENT[id], cur = run.equipment[d.slot], b = R().build(run);
    const na = d.needs === 'dot' && !PA.Growth.hasFireSource(run.growth) && !run.growth.weapons.some(w => w.mods.includes('bleed')) && !(run.growth.commons.frost) ? '<span class="warn small">지금 빌드에는 지속 피해 원천이 없어 효과가 없음</span>' : d.eff.eliteDirect && !PA.Sortie.cardsFor(run).some(c => c.enemies.some(e => PA.ENEMIES[e].elite)) ? '<span class="dim small">오늘 장소에는 정예가 없음</span>' : d.eff.fieldDirect || d.eff.fieldTaken ? '<span class="dim small">감속장(Q) 안에서만</span>' : d.eff.eShield && !b.skills.e ? '<span class="warn small">E 기술이 없어 발동 없음</span>' : '';
    return `<div class="kv"><span>현재 ${esc(PA.EQUIP_SLOT_NAMES[d.slot])}</span><b>${cur ? equipLine(cur) : '<span class="dim">없음</span>'}</b></div><div class="kv"><span>새 장비</span><b>${esc(d.short)}</b></div>${na ? `<div class="kv"><span>주의</span>${na}</div>` : ''}`;
  }
  function shop(G) {
    const run = G.run, tab = G.shopTab || 'stock', st = R().stock(run), g = run.growth, S = PA.GROWTH.SLOTS, inCombat = false;
    const tabs = [['stock', '오늘의 재고'], ['skills', '기술 구매·교체'], ['forge', '대장간'], ['bag', '장비·가방']].concat(R().merchantOpen(run) ? [['merchant', '방문 상인']] : []);
    const tabBar = `<div class="tabs">${tabs.map(([id, n]) => `<button class="${tab === id ? 'primary' : ''}" data-action="shop-tab" data-arg="${id}">${n}</button>`).join('')}</div>`;
    let body = '';
    if (tab === 'stock' || tab === 'merchant') {
      const from = tab === 'merchant' ? 'merchant' : 'stock'; const list = tab === 'merchant' ? (run.merchant.equipment ? [run.merchant.equipment] : []) : st.equipment;
      const eqCards = list.map(id => { const d = PA.EQUIPMENT[id], sold = (from === 'merchant' ? run.merchant : st).sold.includes(id) || R().ownsEquip(run, id), price = R().equipPriceFor(run, id, from), can = R().canBuyEquipment(run, id, from);
        return `<div class="card item ${can ? 'can' : sold ? 'done' : ''}"><div class="card-title">${esc(d.name)} <span class="sub">${esc(PA.EQUIP_SLOT_NAMES[d.slot])}</span></div><p>${esc(d.short)}</p><details><summary class="small">상세</summary><p class="dim small">${esc(d.desc)}</p></details>
          ${equipCompare(run, id)}<div class="cost">금화 <b class="${run.gold < price ? 'lack' : 'gold'}">${price}</b>${sold ? ' · 보유/판매됨' : run.gold < price ? ` (${price - run.gold} 부족)` : ''}${from === 'merchant' ? ` <span class="dim small">(상인 할인 ${Math.round(PA.SHOP.merchantDiscount * 100)}%)</span>` : ''}${R().hasService(run, 'shop_discount') && !sold ? ' <span class="tag">할인권 적용</span>' : ''}</div>
          <div class="row"><button class="primary" data-action="buy-equip" data-arg="${id}:${from}:1" ${can ? '' : 'disabled'}>구매 후 장착</button><button data-action="buy-equip" data-arg="${id}:${from}:0" ${can ? '' : 'disabled'}>구매 후 보관</button></div></div>`; }).join('');
      const svc = tab === 'merchant' ? `<div class="card item ${run.gold >= run.merchant.servicePrice && !run.merchant.sold.includes('service') ? 'can' : ''}"><div class="card-title">무료 휴식권 <span class="sub">서비스</span></div><p>${esc(PA.SERVICES.free_rest.desc)}</p><div class="cost">금화 <b class="gold">${run.merchant.servicePrice}</b></div><button class="primary" data-action="buy-merchant-service" ${run.gold >= run.merchant.servicePrice && !run.merchant.sold.includes('service') ? '' : 'disabled'}>${run.merchant.sold.includes('service') ? '판매됨' : '구매'}</button></div>` : '';
      body = `<p class="dim small">${tab === 'merchant' ? '방문 상인의 재고는 오늘 끝까지 유지됩니다.' : '재고는 날마다 정해지며 다시 열거나 불러와도 같습니다. 같은 장비는 두 번 살 수 없습니다.'} 판매가: 무기 ${PA.SHOP.sellPrice.weapon} · 방어구 ${PA.SHOP.sellPrice.armor} · 방패 ${PA.SHOP.sellPrice.shield}</p><div class="grid3">${eqCards || '<p class="dim">오늘 장비 재고 없음</p>'}${svc}</div>`;
    } else if (tab === 'skills') {
      const sk = st.skill, sold = st.sold.includes('skill'), canSk = R().canBuySkill(run);
      const skName = sk ? (sk.kind === 'weapon' ? PA.WEAPONS[sk.id].name : PA.SKILLS[sk.id].name) : null, skDesc = sk ? (sk.kind === 'weapon' ? PA.WEAPONS[sk.id].desc : PA.SKILLS[sk.id].desc) : '';
      const why = !sk ? '빈 슬롯이 없어 오늘 기술 재고 없음' : sold ? '구매함' : sk.kind === 'weapon' && g.weapons.length >= S.weapons ? '자동기술 슬롯 가득' : sk.kind === 'e' && g.skills.e ? 'E 슬롯 사용 중' : run.gold < sk.price ? `${sk.price - run.gold} 부족` : '';
      const newCard = sk ? `<div class="card item ${canSk ? 'can' : sold ? 'done' : ''}"><div class="card-title">${esc(skName)} <span class="sub">${sk.kind === 'weapon' ? '새 자동기술' : '새 E 기술'} · Lv1 · 개조 없음</span></div><p>${esc(skDesc)}</p><div class="cost">금화 <b class="${run.gold < sk.price ? 'lack' : 'gold'}">${sk.price}</b> ${why ? `<span class="dim small">· ${why}</span>` : ''}</div><button class="primary" data-action="buy-skill" ${canSk ? '' : 'disabled'}>구매 (빈 슬롯에 장착)</button></div>` : `<div class="card dim"><div class="card-title small">새 기술</div><p class="dim">${why}</p></div>`;
      const rows = g.weapons.map((w, i) => { const q = R().swapQuote(run, 'weapon', i); return `<li><b>${esc(PA.WEAPONS[w.id].name)}</b> Lv${w.level} · 개조 ${w.mods.length} <span class="dim">→ 교체 ${q.price}금 (레벨·개조 수 보존, 새 개조는 새 기술에서 선택)</span> <button class="mini" data-action="swap-open" data-arg="weapon:${i}" ${q.options.length && q.affordable ? '' : 'disabled'}>${q.options.length ? (q.affordable ? '교체' : `${q.price - run.gold} 부족`) : '후보 없음'}</button></li>`; }).join('');
      const eq = g.skills.e ? (() => { const q = R().swapQuote(run, 'e'); return `<li><b>E ${esc(PA.SKILLS[g.skills.e.id].name)}</b> Lv${g.skills.e.level}${g.skills.e.variant ? ' · 변형 1' : ''} <span class="dim">→ 교체 ${q.price}금</span> <button class="mini" data-action="swap-open" data-arg="e:0" ${q.options.length && q.affordable ? '' : 'disabled'}>${q.affordable ? '교체' : `${q.price - run.gold} 부족`}</button></li>`; })() : '<li class="dim">E 없음</li>';
      body = `<div class="grid2">${newCard}<div class="card"><div class="card-title">보유 기술 교체 <span class="sub">120 + (레벨−1)×40 + 개조×80</span></div><ul class="gear">${rows}${eq}</ul><p class="dim small">교체하면 옛 기술은 남지 않습니다. 확정 전까지 금화는 차감되지 않습니다.</p></div></div>`;
    } else if (tab === 'forge') {
      const F = R().forgeNext(run); const lv = run.forge || 0;
      const forgeCard = `<div class="card item ${F && F.open && F.affordable ? 'can' : ''}"><div class="card-title">공용 공격 강화 <span class="sub">현재 ${lv}단계 · 자동기술 피해 ×${PA.fmt.num(R().build(run).forgeMult)}</span></div>
        ${F ? `<p>${F.lv}단계: 자동기술 피해 ×${PA.fmt.num(1 + PA.SHOP.forgeMult[F.lv])} · 금화 <b class="${run.gold < F.cost ? 'lack' : 'gold'}">${F.cost}</b>${!F.open ? ` <span class="warn small">· 보스 ${F.afterBoss} 처치 후 개방</span>` : ''}</p><button class="primary" data-action="forge-up" ${F.open && F.affordable ? '' : 'disabled'}>${!F.open ? '잠김' : F.affordable ? '강화' : `${F.cost - run.gold} 부족`}</button>` : '<p class="dim">최대 단계</p>'}
        <p class="dim small">단계별 90 / 160 / 240 · 2단계는 1보스, 3단계는 2보스 처치 후</p></div>`;
      const mc = R().modChangeCost(run), vc = R().variantChangeCost(run);
      const modRows = g.weapons.flatMap(w => w.mods.map(m => `<li><b>${esc(PA.WEAPONS[w.id].name)}</b>: ${esc(PA.WEAPONS[w.id].mods[m].name)} <button class="mini" data-action="mod-change" data-arg="${w.id}:${m}" ${mc.voucher || run.gold >= mc.gold ? '' : 'disabled'}>변경 (${mc.voucher ? '교체권' : mc.gold + '금'})</button></li>`)).join('') || '<li class="dim">변경할 개조 없음</li>';
      const eRow = g.skills.e && g.skills.e.variant ? `<li><b>E ${esc(PA.SKILLS[g.skills.e.id].name)}</b>: ${esc(PA.SKILLS[g.skills.e.id].variants[g.skills.e.variant].name)} <button class="mini" data-action="variant-change" ${vc.voucher || run.gold >= vc.gold ? '' : 'disabled'}>변경 (${vc.voucher ? '교체권' : vc.gold + '금'})</button></li>` : '<li class="dim">E 변형 없음</li>';
      body = `<div class="grid2">${forgeCard}<div class="card"><div class="card-title">개조·변형 변경 <span class="sub">같은 기술의 다른 후보 3택 · ${PA.SHOP.modChange}금 또는 교체권</span></div><ul class="gear">${modRows}${eRow}</ul><p class="dim small">후보가 없으면 아무것도 차감되지 않습니다. 3택에서 '받지 않음'을 고르면 원래 개조가 유지되고 비용은 돌려받습니다.</p></div></div>`;
    } else {
      const eqRows = PA.EQUIP_SLOTS.map(sl => { const id = run.equipment[sl]; return `<li><span class="lbl">${esc(PA.EQUIP_SLOT_NAMES[sl])}</span> ${id ? `${equipLine(id)} <button class="mini" data-action="unequip" data-arg="${sl}">해제</button> <button class="mini" data-action="sell-equip" data-arg="${id}">판매 ${R().sellPrice(id)}</button>` : '<span class="dim">비어 있음</span>'}</li>`; }).join('');
      const bagRows = run.bag.map(id => `<li>${equipLine(id)} <span class="dim small">(${esc(PA.EQUIP_SLOT_NAMES[PA.EQUIPMENT[id].slot])})</span> <button class="mini" data-action="equip" data-arg="${id}">장착</button> <button class="mini" data-action="sell-equip" data-arg="${id}">판매 ${R().sellPrice(id)}</button></li>`).join('') || '<li class="dim">가방 비어 있음</li>';
      const sells = Object.keys(PA.MATERIALS).filter(k => run.mats[k]).map(k => `<span>${matName(k)} <b>${run.mats[k]}</b> <button class="mini" data-action="sell" data-arg="${k}">1개 판매 (${PA.MATERIALS[k].sell}금)</button></span>`).join(' ');
      body = `<div class="grid2"><div class="card"><div class="card-title">장착 중</div><ul class="gear">${eqRows}</ul><p class="dim small">교체는 거점에서 무료. 출격 중에는 바꿀 수 없습니다. 최대 체력이 줄면 현재 체력도 줄고, 늘어도 회복되지 않습니다.</p></div><div class="card"><div class="card-title">가방 <span class="sub">${run.bag.length}개</span></div><ul class="gear">${bagRows}</ul>${sells ? `<div class="card-title small">재료 판매</div><p class="small">${sells}</p>` : ''}</div></div>`;
    }
    return `<div class="screen">${header(run)}
      <div class="row between"><h2>상점 · 대장간 · 장비 <span class="sub">시간 소모 없음</span></h2><button data-action="base">거점으로</button></div>
      ${tabBar}${body}${equipPanel(run)}</div>`;
  }
  // 기술 교체 흐름: 1 새 기술 선택 → 2 개조/변형 선택(보존 수만큼) → 3 확인(가격·변화·경고) → 확정. 취소하면 아무것도 바뀌지 않음
  function swap(G) {
    const run = G.run, sw = G.swap, q = R().swapQuote(run, sw.slot, sw.index); if (!q) return shop(G);
    const isE = sw.slot === 'e', curName = isE ? PA.SKILLS[q.current.id].name : PA.WEAPONS[q.current.id].name;
    const head = `<div class="row between"><h2>기술 교체 <span class="sub">${esc(curName)} Lv${q.level}${q.modCount ? ` · 개조 ${q.modCount}개 보존` : ''} → 비용 <b class="gold">${q.price}</b></span></h2><button data-action="swap-cancel">취소 (변경 없음)</button></div>`;
    if (!sw.newId) {
      const opts = q.options.map(id => { const d = isE ? PA.SKILLS[id] : PA.WEAPONS[id]; return `<div class="card"><div class="card-title">${esc(d.name)}</div><p>${esc(d.desc)}</p>${isE ? '' : `<p class="dim small">기본 피해 ${d.base.damage} · 주기 ${d.base.interval}초 · 개조 후보: ${Object.values(d.mods).filter(m => m.impl).map(m => esc(m.name)).join(', ')}</p>`}<button class="primary" data-action="swap-pick" data-arg="${id}">이 기술로</button></div>`; }).join('');
      return `<div class="screen">${header(run)}${head}<p class="dim small">1/3 새 기술을 고르세요. 레벨 ${q.level}과 개조 수 ${q.modCount}은 그대로 이어집니다.</p><div class="grid3">${opts}</div></div>`;
    }
    const d = isE ? PA.SKILLS[sw.newId] : PA.WEAPONS[sw.newId]; const pool = isE ? Object.keys(d.variants || {}).filter(v => d.variants[v].impl) : Object.keys(d.mods).filter(m => d.mods[m].impl);
    const need = Math.min(q.modCount, pool.length), chosen = sw.mods || [];
    if (chosen.length < need) {
      const cards = pool.filter(m => !chosen.includes(m)).map(m => { const md = isE ? d.variants[m] : d.mods[m]; return `<div class="card"><div class="card-title">${esc(md.name)}</div><p>${esc(md.desc)}</p><button class="primary" data-action="swap-mod" data-arg="${m}">선택</button></div>`; }).join('');
      return `<div class="screen">${header(run)}${head}<p class="dim small">2/3 ${esc(d.name)}의 ${isE ? '변형' : '개조'}를 ${need}개 고르세요 (${chosen.length}/${need}).${chosen.length ? ' 선택: ' + chosen.map(m => esc((isE ? d.variants[m] : d.mods[m]).name)).join(', ') : ''}</p><div class="grid3">${cards}</div><div class="row"><button data-action="swap-open" data-arg="${sw.slot}:${sw.index}">처음부터</button></div></div>`;
    }
    const warns = isE ? [] : R().swapWarnings(run, sw.slot, sw.index, sw.newId);
    return `<div class="screen">${header(run)}${head}<p class="dim small">3/3 확인</p>
      <div class="card"><div class="kv"><span>바뀌는 것</span><b>${esc(curName)} Lv${q.level} → ${esc(d.name)} Lv${q.level}</b></div><div class="kv"><span>${isE ? '변형' : '개조'}</span><b>${chosen.length ? chosen.map(m => esc((isE ? d.variants[m] : d.mods[m]).name)).join(', ') : '없음'}${q.modCount > need ? ` <span class="dim small">(후보가 ${need}개뿐이라 ${q.modCount - need}개는 비어 있음 · 비용은 동일)</span>` : ''}</b></div><div class="kv"><span>비용</span><b class="gold">${q.price}</b> <span class="dim small">(남는 금화 ${run.gold - q.price})</span></div>
        ${warns.length ? `<div class="kv"><span class="warn">경고</span><b class="warn">공용 증강 ${warns.map(esc).join(', ')}이(가) 적용 대상을 잃습니다</b></div>` : ''}
        <div class="row"><button class="primary" data-action="swap-confirm" ${q.affordable ? '' : 'disabled'}>확정 (금화 ${q.price} 차감)</button><button data-action="swap-cancel">취소 (변경 없음)</button></div></div></div>`;
  }
  function reward(G) {
    const run = G.run, rw = G.lastReward, g = run.growth;
    const matText = Object.keys(rw.mats).map(k => `${matName(k)} ${rw.mats[k]}`).join(', ');
    return `<div class="screen"><h2>전투 승리</h2><p class="dim small">설정: ${esc(PA.Balance.text(run))}</p>
      <div class="card"><div class="card-title">보상 (귀환 시 거점에 반영)</div>
        <p>금화 <b class="gold">+${rw.gold}</b>${rw.chestGold ? ` (보급 상자 +${rw.chestGold} 포함)` : ''}${matText ? ` · ${matText}` : ''} · 지역 경험치 <b class="gold">+${rw.xp || 0}</b>${rw.mission ? (rw.missionPick ? ' · <b>임무 완료: 보상 3택은 다음 단계에서</b>' : ' · 임무(오늘 이미 완료: 추가 3택 없음)') : ''}</p>
        <p class="dim small">처치 ${G.lastStats.kills}${G.lastStats.savingKills ? ` (감속장 안 ${G.lastStats.savingKills})` : ''} · 받은 피해 ${Math.round(G.lastStats.damageTaken)} · ${Math.round(G.lastStats.elapsed)}초 · 전투 중 경험치 ${G.lastStats.xp} · 레벨업 ${G.lastStats.levelUps}회 (Lv ${g.level})</p></div>
      ${g.pendingLevelUps ? `<div class="card boss"><div class="card-title">미처리 레벨업 ${g.pendingLevelUps}</div><p>조우 종료와 동시에 오른 레벨입니다. 지금 선택합니다.</p><button class="primary" data-action="resolve-levelup">선택하기</button></div>` : ''}
      <div class="row"><button class="primary big" data-action="after-reward">다음</button></div></div>`;
  }
  function after(G) {
    const run = G.run, s = G.sortie, r = R().region(s.regionId), b = R().build(run);
    const canDeep = !s.deep && R().canDeepExplore(run, s), must = PA.Flow.mustReturn(s);
    const lootText = `금화 ${s.loot.gold}` + Object.keys(s.loot.mats).map(k => `, ${matName(k)} ${s.loot.mats[k]}`).join('') + (s.loot.items || []).map(id => `, ${PA.EQUIPMENT[id].name}`).join('') + (s.loot.services || []).map(k => `, ${PA.SERVICES[k].name}`).join('') + (s.loot.steer ? ', 성장 예약' : '');
    const pv = canDeep ? R().deepPreview(run, s) : null;
    const deepCard = must ? '' : pv ? `<div class="card boss"><div class="card-title">더 깊이 (1회) <span class="sub">시간 +${pv.extraTime}칸 → ${esc(pv.nextSlot)}</span></div>
        <div class="kv"><span>적 변화</span><b>${esc(pv.enemyChange)}${pv.hpMult.normal !== 1 ? ` · 체력 ×${pv.hpMult.normal}` : ''}</b></div>
        <div class="kv"><span>보상</span><b>${esc(pv.reward.text)}</b> <span class="dim small">(승리 시 전리품에 추가, 귀환 때 정산)</span></div>
        <div class="kv"><span>걸린 전리품</span><b class="warn">${esc(lootText)}</b> <span class="dim small">패배하면 모두 잃고 남은 하루도 잃습니다</span></div>
        <button class="big" data-action="deep">더 깊이 들어간다</button></div>` : `<p class="dim small">더 깊이: ${s.deep ? '이미 탐험함' : s.mission ? '임무 출격에서는 불가' : '남은 칸 없음'}</p>`;
    return `<div class="screen center"><h2>${esc(r.name)} · 전투 승리</h2>
      <p>체력 <b>${run.hp} / ${b.hpMax}</b> · 이번 출격 전리품(미정산): <b>${esc(lootText)}</b> · 남은 ${run.hours}칸 (${esc(R().slotName(run))})</p>
      ${deepCard}
      <div class="menu"><button class="primary big" data-action="return">전리품을 가지고 귀환 (정산)</button></div>
      <p class="dim small">시작한 전투는 중간에 안전하게 물러날 수 없습니다. 포기는 패배로 처리됩니다.</p></div>`;
  }
  // 탐험 사건: 비용·위험을 먼저 보여 주고 선택. 선택은 1회
  function event(G) {
    const run = G.run, s = G.sortie, ev = s.event, E = PA.EVENTS[ev.id], opts = PA.Events.options(run, s), b = R().build(run);
    return `<div class="screen center"><h2>${esc(R().region(s.regionId).name)} · ${esc(E.name)}</h2>
      <p>${esc(E.desc)}</p><p class="dim small">체력 ${run.hp} / ${b.hpMax} · 오늘 남은 시간 ${run.hours} · 이번 출격 전리품 금화 ${s.loot.gold}</p>
      <div class="grid3">${opts.map(o => `<div class="card ${o.enabled ? 'can' : 'off'}"><div class="card-title">${esc(o.name)}</div><div class="kv"><span>비용·위험</span><b>${esc(o.cost)}</b></div><div class="kv"><span>효과</span><b>${esc(o.effect)}</b></div><button class="primary" data-action="event-choice" data-arg="${o.id}" ${o.enabled ? '' : 'disabled'}>${o.enabled ? '선택' : '불가'}</button></div>`).join('')}</div>
      <p class="dim small">사건은 출격당 최대 1회, 선택은 되돌릴 수 없습니다. 비용과 보상은 선택 즉시 1회 정산됩니다.</p></div>`;
  }
  function defeat(G) {
    const run = G.run, r = R().region(G.sortie.regionId), lost = G.sortie.loot;
    const lostText = `금화 ${lost.gold}` + Object.keys(lost.mats || {}).map(k => `, ${matName(k)} ${lost.mats[k]}`).join('') + (lost.items || []).map(id => `, ${PA.EQUIPMENT[id].name}`).join('');
    const now = run.phase === 'boss_prep' ? `${run.day}일차 보스 관문` : `${run.day}일차 새벽`;
    return `<div class="screen center"><h2 class="bad">패배</h2><p>${esc(r.name)}에서 쓰러졌습니다. 이번 출격의 미정산 전리품(<b>${esc(lostText)}</b>)과 남은 하루를 잃었습니다.</p>
      <p>구조되어 <b>${esc(now)}</b>에 정상 체력으로 시작합니다. 이미 정산한 금화·장비와 레벨·성장은 그대로입니다.</p>
      <p class="dim small">처치 ${G.lastStats.kills} · 받은 피해 ${Math.round(G.lastStats.damageTaken)} · ${Math.round(G.lastStats.elapsed)}초</p>
      <button class="primary big" data-action="base">${esc(now)}로</button></div>`;
  }
  function bossDefeat(G) {
    const run = G.run, s = G.lastStats, B = R().nextBossCfg(run);
    return `<div class="screen center"><h2 class="bad">쓰러졌다</h2><p class="dim small">설정: ${esc(PA.Balance.text(run))}</p><p>${esc(B.name)}에게 패배했습니다. 준비 기간의 성과는 그대로입니다. 같은 장비·무기·증강으로 바로 다시 도전할 수 있습니다.</p><p class="dim small">재도전은 입장 시점의 상태로 복구됩니다: 레벨·경험치·전투 중 선택은 입장 전으로, 체력·회피·감속장·E는 초기화, 보스·소환 늑대·구슬은 처음부터.</p>
      <p class="dim small">전투 ${Math.round(s.elapsed)}초 · 보스에게 준 피해 ${Math.round(s.bossDamage)} / ${R().bossHp(run, B.id)} · 감속장 ${s.specialUses}회 · 재도전 ${run.bossRetries}회</p>
      <div class="menu"><button class="primary big" data-action="boss-start">같은 준비로 재도전</button><button class="big" data-action="base">최종 준비 화면으로</button><button class="big" data-action="title">제목으로</button></div></div>`;
  }
  function bossVictory(G) {
    const run = G.run, s = G.lastStats, b = R().build(run), rec = G.lastRecord || run.lastBossClear || {}; const B = PA.BOSS_DEFS[rec.bossId || 'boss'], stages = R().stageCount(run), ended = run.phase === 'cleared';
    const eqText = PA.EQUIP_SLOTS.map(sl => run.equipment[sl] ? PA.EQUIPMENT[run.equipment[sl]].name : null).filter(Boolean).join(', ') || '없음';
    if (!ended) return `<div class="screen center"><h1>${(run.stage || 0)}단계 돌파</h1><h2>${esc(B.name)} — ${esc(B.title)} 처치</h2><p class="dim small">설정: ${esc(PA.Balance.text(run))} · 보스 최대 체력 ${R().bossHp(run, B.id)}</p>
      <div class="card"><div class="card-title">기록</div><ul class="gear" style="text-align:left"><li>전투 시간 <b>${Math.round(s.elapsed * 10) / 10}초</b> · 재도전 <b>${rec.retries || 0}회</b> · Lv ${run.growth.level}</li><li>감속장 사용 <b>${s.specialUses}</b>회 · 보스에게 준 총피해 <b>${Math.round(s.bossDamage)}</b></li></ul></div>
      <div class="card boss"><div class="card-title">다음 단계 해금</div><p>${run.day}일차의 ${PA.CONFIG.HOURS_PER_DAY}시간이 시작됩니다. ${R().nextBoss(run) ? `다음 보스 <b>${esc(R().nextBossCfg(run).name)}</b>은(는) ${R().nextBoss(run).day}일차 시작에 옵니다.` : ''}${run.growth.pendingBossPick || (run.growth.pendingOffer && run.growth.pendingOffer.pool === 'boss') ? ' <b>희귀 보상 3택</b>이 거점에서 제시됩니다(1회, 저장됨).' : ''}</p></div>
      <div class="menu"><button class="primary big" data-action="base">거점으로 (오늘 시간 시작)</button></div></div>`;
    return `<div class="screen center"><h1>${stages > 1 ? '회차 완주.' : '예언의 날을 넘겼다.'}</h1><h2>${esc(B.name)} — ${esc(B.title)} 처치</h2><p class="dim small">설정: ${esc(PA.Balance.text(run))} · 보스 최대 체력 ${R().bossHp(run, B.id)}</p>
      <div class="card"><div class="card-title">회차 결과</div>
        <ul class="gear" style="text-align:left">
          <li>전투 시간: <b>${Math.round(s.elapsed * 10) / 10}초</b> · 재도전 <b>${run.bossRetries}회</b></li>
          <li>자동기술: <b>${run.growth.weapons.map(w => PA.WEAPONS[w.id].name + ' Lv' + w.level).join(', ')}</b> · Q Lv${run.growth.skills.q.level}${run.growth.skills.e ? ' · E ' + PA.SKILLS[run.growth.skills.e.id].name + ' Lv' + run.growth.skills.e.level : ''}</li>
          <li>장비: <b>${esc(eqText)}</b>${run.forge ? ` · 공용 공격 강화 ${run.forge}단계` : ''} · 금화 ${run.gold}</li>
          <li>감속장 사용 <b>${s.specialUses}</b>회 · 보스에게 준 총피해 <b>${Math.round(s.bossDamage)}</b> (실제 체력 감소 기준)</li>
          <li class="dim small">첫 처치 기록${G.firstClearNew ? '으로 저장됨' : ': ' + (run.bossClear ? run.bossClear.time + '초' : '—')}</li>
        </ul></div>
      ${PA.Stats && PA.Screens.statsPanel ? PA.Screens.statsPanel(run) : ''}
      <div class="menu"><button class="primary big" data-action="boss-start">이번 빌드로 보스 다시 도전</button><button class="big" data-action="newrun-confirm">새 회차 시작</button><button class="big" data-action="title">제목으로</button></div></div>`;
  }
  function enddayConfirm(G) {
    const run = G.run, nx = R().previewNextDay(run);
    const preview = nx.boss ? `<div class="card boss"><div class="card-title">내일: ${esc(PA.BOSS_DEFS[nx.boss].name)} 관문</div><p>${R().stageCount(run) > 1 ? '내일은 보스 관문으로 시작합니다. 상점·대장간·장비 교체 뒤 보스전에 들어가고, 이기면 그날의 시간대가 시작됩니다.' : '7일차에는 일반 출격이 없습니다. 최종 준비 뒤 보스전에 들어갑니다.'} 패배해도 입장 시점으로 돌아와 같은 준비로 재도전합니다.</p></div>`
      : `<div class="card"><div class="card-title">내일의 장소</div>${nx.places.map(p => `<p><b>${esc(p.name)}</b> <span class="dim">${p.enemies.map(t => esc(PA.ENEMIES[t].name)).join('·')}${p.elite ? ' · <b>정예</b>' : ''}</span></p>`).join('')}${PA.MERCHANT_VISITS.days.includes(nx.day) ? `<p class="small"><span class="tag">상인</span> ${esc(PA.TIME_SLOTS[PA.MERCHANT_VISITS.slot])}부터 방문 상인</p>` : ''}${R().nextBoss(run) && R().bossDaysLeft(run) - 1 > 0 ? `<p class="dim small">다음 보스까지 ${R().bossDaysLeft(run) - 1}일</p>` : ''}</div>`;
    return `<div class="screen center"><h2>하루를 마칠까요?</h2><p>${run.hours > 0 ? `남은 ${run.hours}칸을 버리고 ` : ''}${run.day + 1}일차 새벽으로 넘어갑니다. 체력이 완전히 회복됩니다.</p>
      ${preview}
      <div class="row"><button class="primary" data-action="endday">하루 종료</button><button data-action="base">돌아가기</button></div></div>`;
  }
  function bossday(G) {
    const run = G.run;
    return `<div class="screen center"><h2>보스 도래 — ${run.day}일차</h2>
      <p>예언의 날이 왔습니다. 준비 기간이 끝났습니다.</p>
      <div class="card"><div class="card-title">이 빌드의 한계</div><p><b>보스전은 아직 구현되어 있지 않습니다.</b> 이 화면은 결말을 완료된 것처럼 꾸미지 않기 위한 정직한 종료 화면입니다.</p>
      <p class="dim">회차 기록: 전투 ${run.stats.encounters} · 승리 ${run.stats.wins} · 패배 ${run.stats.losses} · 최종 금화 ${run.gold}</p></div>
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
  return { title, newrunConfirm, base, finalPrep, map, shop, swap, equipPanel, reward, after, event, defeat, bossDefeat, bossVictory, enddayConfirm, bossday, scenarioEnd, controls, pause, paintPortraits, bossCard, pickStart, levelCards, migration, lab, labResult, statusText };
})();
