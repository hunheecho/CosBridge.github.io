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
  // 하루 카드 생성(결정적). 같은 (지역, 목표)는 하루에 한 번. 목표는 가능한 한 서로 다르게. 최소 1장은 빌드와 연결(가능할 때)
  function generate(run, day) {
    const rng = PA.rng.create(cardSeed(run, day)), regions = regionsFor(day), objs = PA.OBJECTIVE_IDS.slice(), out = [], used = new Set();
    let guard = 0;
    while (out.length < M().perDay && guard++ < 60) {
      const r = regions[rng.int(0, regions.length - 1)], obj = objs.length ? objs.splice(rng.int(0, objs.length - 1), 1)[0] : PA.OBJECTIVE_IDS[rng.int(0, 3)];
      const key = r.id + ':' + obj; if (used.has(key)) continue; used.add(key);
      const kind = rewardKindFor(run, obj);
      const riskRoll = rng.next(); const risk = day >= M().riskFromDay && riskRoll < M().riskChance ? M().risks[rng.int(0, M().risks.length - 1)] : null;
      out.push({ id: `d${day}c${out.length + 1}`, day, regionId: r.id, objective: obj, risk, rewardKind: kind, rewardTarget: rewardTarget(run, kind), fallbackGold: M().goldFallback[r.id], timeCost: r.cost, enemies: mainEnemies(run, r.id, obj, risk), first: !((run.missionsDone || {})[obj]), done: false, attempts: 0, linked: buildLinked(run, kind) });
    }
    // 빌드와 연결된 카드가 하나도 없고 가능하다면 마지막 카드의 보상을 무기 강화/개조로 바꾼다(모두 무관한 카드 금지)
    if (!out.some(c => c.linked)) { const alt = ['weapon_mod', 'weapon_level'].find(k => kindValid(run, k)); if (alt) { const c = out[out.length - 1]; c.rewardKind = alt; c.rewardTarget = rewardTarget(run, alt); c.linked = true; } }
    return out;
  }
  function mainEnemies(run, regionId, objective, risk) {
    const base = PA.Run.regionEnemies(regionId, run).filter(t => !PA.ENEMIES[t].elite).slice(0, 3);
    if (objective === 'hunt' || risk === 'escort') base.push(PA.OBJECTIVES.hunt.eliteType);
    return Array.from(new Set(base)).slice(0, 4);
  }
  // 오늘의 카드(없거나 날짜가 다르면 생성해 저장 필드에 둔다). 다시 굴리기 없음
  function cardsFor(run) { if (!run.cards || run.cards.day !== run.day) run.cards = { day: run.day, list: generate(run, run.day) }; return run.cards.list; }
  function card(run, id) { return cardsFor(run).find(c => c.id === id) || null; }
  function canStart(run, c) { return !!c && !c.done && PA.Run.canSortie(run, c.regionId); }
  // 임무 출격: 지역 출격과 같은 비용·시드 규칙 + 카드 정보
  function start(run, id) {
    const c = card(run, id); if (!canStart(run, c)) throw new Error('임무 시작 불가');
    const s = PA.Run.startSortie(run, c.regionId); s.cardId = c.id; s.objective = c.objective; s.risk = c.risk; s.mission = true; c.attempts++;
    return s;
  }
  // 임무 승리 정산(Flow.settleVictory에서 호출): 카드 완료 표시, 보상 종류 3택을 보류 등록(정산 1회)
  function onMissionWin(run, sortie) {
    const c = card(run, sortie.cardId); if (!c || c.done) return false;
    c.done = true; run.missionsDone = run.missionsDone || {}; run.missionsDone[c.objective] = (run.missionsDone[c.objective] || 0) + 1;
    run.growth.pendingMissionPick = { cardId: c.id, kind: c.rewardKind, regionId: c.regionId, fallbackGold: c.fallbackGold, key: `${sortie.seed}:${sortie.encounters}` };
    return true;
  }
  // 임무 보상 제시(Flow.nextOffer에서 호출): 유효 후보가 없으면 정해진 금화로 대체(중복·무효 카드로 채우지 않음)
  function missionOffer(run) {
    const g = run.growth, mp = g.pendingMissionPick; if (!mp) return null; g.pendingMissionPick = null;
    const kind = kindValid(run, mp.kind) ? mp.kind : (M().rewardByObjective[(card(run, mp.cardId) || {}).objective || 'hunt'].find(k => k !== 'gold' && kindValid(run, k)) || 'gold');
    if (kind === 'gold') { run.gold += mp.fallbackGold; PA.Run.addLog(run, `임무 보상: 유효한 후보가 없어 금화 +${mp.fallbackGold}`); g.missionGoldFallbacks = (g.missionGoldFallbacks || 0) + 1; return null; }
    const off = PA.Growth.generateOffer(run, { pool: 'mission', kinds: M().kindPools[kind], regionId: mp.regionId, missionKind: kind });
    if (!off.choices.length) { g.pendingOffer = null; run.gold += mp.fallbackGold; PA.Run.addLog(run, `임무 보상: 후보 없음 → 금화 +${mp.fallbackGold}`); g.missionGoldFallbacks = (g.missionGoldFallbacks || 0) + 1; return null; }
    return off;
  }
  function objectiveName(id) { return PA.OBJECTIVES[id] ? PA.OBJECTIVES[id].name : id === 'elite' ? '정예 처치' : '전멸'; }
  return { cardSeed, kindValid, rewardKindFor, rewardTarget, generate, cardsFor, card, canStart, start, onMissionWin, missionOffer, objectiveName, mainEnemies, buildLinked };
})();
