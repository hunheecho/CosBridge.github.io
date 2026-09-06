// 출격 카드(하루 3장, 시드 확정·저장)와 임무 보상 규칙. 화면·봇 공용.
var PA = (typeof PA !== 'undefined') ? PA : {};

PA.Sortie = (function () {
  const M = () => PA.MISSIONS;
  function cardSeed(run, day) { return (run.seed * 7 + day * 1009 + 13) >>> 0; }
  // 보상 종류의 유효성: 현재 성장 상태에서 그 종류의 후보가 1개 이상
  function kindValid(run, kind) {
    if (kind === 'gold') return true;
    if (kind === 'service') return Object.keys(PA.SERVICES).length > 0;
    const pools = M().kindPools[kind]; return PA.Growth.candidates(run, { pool: 'level' }).some(c => pools.includes(c.kind));
  }
  function rewardKindFor(run, objective) { for (const k of M().rewardByObjective[objective]) if (kindValid(run, k)) return k; return 'gold'; }
  // 보상 대상 요약(카드 표시용): 어떤 무기·기술이 후보인지
  function rewardTarget(run, kind) {
    const g = run.growth, W = PA.WEAPONS;
    if (kind === 'weapon_level') return g.weapons.filter(w => w.level < PA.GROWTH.SLOTS.weaponMax).map(w => W[w.id].name + ' Lv' + w.level + '→' + (w.level + 1)).join(' / ');
    if (kind === 'weapon_mod') return g.weapons.filter(w => w.mods.length < PA.GROWTH.SLOTS.weaponMods && Object.keys(W[w.id].mods).some(mid => W[w.id].mods[mid].impl && !w.mods.includes(mid))).map(w => W[w.id].name + ' 개조 ' + w.mods.length + '/' + PA.GROWTH.SLOTS.weaponMods).join(' / ');
    if (kind === 'skill') return g.skills.e ? `${PA.SKILLS[g.skills.e.id].name}·감속장 강화/변형` : 'E 기술 습득·감속장 강화';
    if (kind === 'common') return '공통 증강';
    if (kind === 'service') return Object.values(PA.SERVICES).map(s => s.name).join(' / ');
    return '';
  }
  function regionsFor(day) { return PA.REGIONS.filter(r => (M().regionFromDay[r.id] || 1) <= day); }
  // 현재 빌드와의 연결: 보상 종류가 소유 무기·기술에 직접 적용되는가
  function buildLinked(run, kind) { return kind === 'weapon_level' || kind === 'weapon_mod' || (kind === 'skill' && !!run.growth.skills.e); }
  // 하루 카드 = 오늘의 장소 2곳(Run.placesFor). 1일차는 단순 전멸, 2일차부터 임무 목표(시드 확정), 3일차부터 위험 조건.
  // 임무 보상은 다음 자연 레벨업의 종류를 정하는 예약(steer). 이미 예약이 있으면 카드에 금화 대체가 표시된다
  function generate(run, day) {
    const rng = PA.rng.create(cardSeed(run, day)), places = PA.Run.placesFor(run, day), out = [];
    const objs = PA.OBJECTIVE_IDS.slice();
    places.forEach((rid, i) => {
      let obj = 'clear';
      if (rid !== 'deep' && day >= PA.SCHEDULE.missionFromDay && (i === 0 || rng.next() < 0.5)) obj = objs.splice(rng.int(0, objs.length - 1), 1)[0];
      const risk = obj !== 'clear' && day >= PA.SCHEDULE.riskFromDay && rng.next() < M().riskChance ? M().risks[rng.int(0, M().risks.length - 1)] : null;
      const kind = obj === 'clear' ? null : (PA.MISSION_STEER[obj] || 'gold');
      const variant = PA.Run.slotVariant(rid, 0) || PA.Run.slotVariant(rid, 2) || PA.Run.slotVariant(rid, 3) || PA.Run.slotVariant(rid, 4) || null;
      out.push({ id: `d${day}c${i + 1}`, day, regionId: rid, objective: obj, risk, rewardKind: kind, rewardTarget: kind ? rewardTarget(run, kind) : '', fallbackGold: M().goldFallback[rid], timeCost: PA.Run.placeCost(rid), enemies: mainEnemies(run, rid, obj, risk), first: obj !== 'clear' && !((run.missionsDone || {})[obj]), done: false, attempts: 0, linked: kind ? buildLinked(run, kind) : false, variantSlot: variant ? variant.slot : null, variantName: variant ? variant.name : null });
    });
    return out;
  }
  function mainEnemies(run, regionId, objective, risk) {
    const base = PA.Run.regionEnemies(regionId, run).filter(t => !PA.ENEMIES[t].elite).slice(0, 3);
    if (objective === 'hunt' || risk === 'escort' || regionId === 'deep') base.push(PA.OBJECTIVES.hunt.eliteType);
    return Array.from(new Set(base)).slice(0, 4);
  }
  // 오늘의 카드(없거나 날짜가 다르면 생성해 저장 필드에 둔다). 다시 굴리기 없음
  function cardsFor(run) { if (!run.cards || run.cards.day !== run.day) run.cards = { day: run.day, list: generate(run, run.day) }; return run.cards.list; }
  function card(run, id) { return cardsFor(run).find(c => c.id === id) || null; }
  function canStart(run, c) { return !!c && !c.done && PA.Run.canSortie(run, c.regionId); }
  // 카드 출격: 지역 출격과 같은 비용·시드 규칙 + 카드 정보. 목표 'clear'는 일반 출격(임무 아님)
  function start(run, id) {
    const c = card(run, id); if (!canStart(run, c)) throw new Error('임무 시작 불가');
    const s = PA.Run.startSortie(run, c.regionId); s.cardId = c.id; c.attempts++;
    if (c.objective !== 'clear') { s.objective = c.objective; s.risk = c.risk; s.mission = true; }
    return s;
  }
  // 예약 상태 표시: 카드의 보상이 예약으로 들어갈지, 금화 대체가 될지
  function steerState(run, c) {
    if (!c.rewardKind) return { text: '전리품만', gold: true };
    if (c.rewardKind === 'service') return { text: '완료 즉시 3택', gold: false };
    const g = run.growth; if (g.steer) return { text: `이미 예약 있음(${kindName(g.steer.kind)}) → 금화 +${c.fallbackGold} 대체`, gold: true };
    if (!kindValid(run, c.rewardKind)) return { text: `유효 후보 없음 → 금화 +${c.fallbackGold} 대체`, gold: true };
    return { text: `다음 레벨업을 ${kindName(c.rewardKind)}로 예약`, gold: false };
  }
  function kindName(kind) { return { weapon_level: '자동기술 레벨', weapon_mod: '자동기술 개조', skill: 'Q/E 강화', service: '거점 서비스', common: '공용 증강' }[kind] || kind; }
  // 임무 승리 정산(Flow.settleVictory에서 호출): 카드 완료 표시 → 서비스는 즉시 3택 보류, 그 외는 단일 예약(steer). 예약이 이미 있으면 금화 대체(조용히 덮어쓰지 않음)
  function onMissionWin(run, sortie) {
    const c = card(run, sortie.cardId); if (!c || c.done || c.objective === 'clear') return false;
    c.done = true; run.missionsDone = run.missionsDone || {}; run.missionsDone[c.objective] = (run.missionsDone[c.objective] || 0) + 1;
    const g = run.growth, kind = c.rewardKind;
    if (kind === 'service') { g.pendingMissionPick = { cardId: c.id, kind, regionId: c.regionId, fallbackGold: c.fallbackGold, key: `${sortie.seed}:${sortie.encounters}` }; return true; }
    if (g.steer || !kindValid(run, kind)) { run.gold += c.fallbackGold; g.missionGoldFallbacks = (g.missionGoldFallbacks || 0) + 1; PA.Run.addLog(run, `임무 보상: ${g.steer ? '예약이 이미 있어' : '유효 후보가 없어'} 금화 +${c.fallbackGold}`); return { gold: c.fallbackGold }; }
    g.steer = { kind, cardId: c.id, regionId: c.regionId, day: run.day, fallbackGold: c.fallbackGold }; PA.Run.addLog(run, `임무 보상: 다음 레벨업을 ${kindName(kind)}로 예약`);
    return { steer: kind };
  }
  // 임무 보상 제시(서비스 종류만 남음): 유효 후보가 없으면 정해진 금화로 대체
  function missionOffer(run) {
    const g = run.growth, mp = g.pendingMissionPick; if (!mp) return null; g.pendingMissionPick = null;
    const kind = kindValid(run, mp.kind) ? mp.kind : 'gold';
    if (kind === 'gold') { run.gold += mp.fallbackGold; PA.Run.addLog(run, `임무 보상: 유효한 후보가 없어 금화 +${mp.fallbackGold}`); g.missionGoldFallbacks = (g.missionGoldFallbacks || 0) + 1; return null; }
    const off = PA.Growth.generateOffer(run, { pool: 'mission', kinds: M().kindPools[kind], regionId: mp.regionId, missionKind: kind });
    if (!off.choices.length) { g.pendingOffer = null; run.gold += mp.fallbackGold; PA.Run.addLog(run, `임무 보상: 후보 없음 → 금화 +${mp.fallbackGold}`); g.missionGoldFallbacks = (g.missionGoldFallbacks || 0) + 1; return null; }
    return off;
  }
  function objectiveName(id) { return PA.OBJECTIVES[id] ? PA.OBJECTIVES[id].name : id === 'elite' ? '정예 포함 전멸' : '전멸'; }
  return { cardSeed, kindValid, rewardKindFor, rewardTarget, generate, cardsFor, card, canStart, start, onMissionWin, missionOffer, objectiveName, mainEnemies, buildLinked, steerState, kindName };
})();
