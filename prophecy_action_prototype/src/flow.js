// 회차 진행 공유 흐름: 조우 생성·정산·다음 선택을 브라우저(main.js)와 헤드리스 시뮬레이터(tools/run_sim.js)가 같은 함수로 처리한다.
// 화면은 결과를 표시하고 선택을 전달할 뿐, 보상·경험치·3택의 규칙은 여기서만 결정된다.
PA.Flow = (function () {
  // 조우 시드: 출격 시드 + 조우 순번×1000 + (더 깊이 7). 게임과 시뮬레이터가 같은 값을 쓴다
  function encounterSeed(sortie) { return sortie.seed + (sortie.encounters || 0) * 1000 + (sortie.deep ? 7 : 0); }
  // 조우 생성 옵션(일반 조우). 보스는 Run.startBoss/bossSeed 경로
  function encounterOpts(run, sortie, extra) {
    const R = PA.Run;
    return Object.assign({
      build: R.build(run), hp: run.hp, seed: encounterSeed(sortie),
      waves: R.encounterWaves(sortie.regionId, sortie.deep, run), objective: R.encounterObjective(sortie.regionId, sortie.deep, run),
      arena: sortie.arena || R.regionArena(sortie.regionId, run), hpMult: R.hpMultFor(run, sortie.regionId, sortie.deep), regionId: sortie.regionId,
      labText: R.layoutText(run) || null,
    }, extra || {});
  }
  function makeEncounter(run, sortie, extra) { return PA.Combat.create(encounterOpts(run, sortie, extra)); }
  // 조우 승리 정산(정확히 1회): 전리품 굴림 → 출격 전리품 반영 → 지역 경험치 → 더 깊이면 지역 3택을 보류 선택으로 등록(저장됨)
  function settleVictory(run, sortie, st) {
    const eliteKilled = st.enemies.some(e => e.elite && e.dead) || (st.status === 'won' && st.objective === 'elite');
    const reward = PA.Run.rollReward(run, sortie, st.rng, { chestGold: st.stats.chestGold, eliteKilled });
    PA.Run.applyEncounterResult(run, sortie, 'won', reward, st.player.hp);
    reward.xp = PA.Run.regionBonusXp(sortie.regionId, sortie.deep); PA.Growth.addXp(run.growth, reward.xp);
    if (sortie.deep && PA.GROWTH.DEEP_PICK && !sortie.deepPicked) { sortie.deepPicked = true; run.growth.pendingDeepPick = { regionId: sortie.regionId, key: `${sortie.seed}:${sortie.encounters}` }; }
    return reward;
  }
  function settleDefeat(run, sortie, st) { PA.Run.applyEncounterResult(run, sortie, 'lost', null, 0); PA.Run.defeat(run, sortie); }
  // 다음에 제시할 선택(순서 고정): 저장된 보류 제시 → 미처리 레벨업 → 더 깊이 지역 3택 → 없음(null)
  // 더 깊이 3택은 여기서 보류 등록을 소비하고 pendingOffer로 옮긴다(새로고침해도 같은 제시, 두 번 제시되지 않음). 후보가 없으면 제시 없이 소비
  function nextOffer(run, ctx) {
    const g = run.growth; ctx = ctx || {};
    if (g.pendingOffer) return g.pendingOffer;
    if (g.pendingLevelUps > 0) return PA.Growth.generateOffer(run, { pool: 'level', regionId: ctx.regionId || null });
    if (g.pendingDeepPick) {
      const rid = g.pendingDeepPick.regionId; g.pendingDeepPick = null;
      const off = PA.Growth.generateOffer(run, { pool: 'deep', regionId: rid });
      if (!off.choices.length) { g.pendingOffer = null; g.deepPickNone = (g.deepPickNone || 0) + 1; PA.Run.addLog(run, '지역 보상: 남은 후보 없음(제시 생략)'); return nextOffer(run, ctx); } // 유효 후보 0개: 명시적으로 생략·기록
      return off;
    }
    return null;
  }
  // 제시된 선택을 적용(choice) 또는 건너뜀(null). 레벨업 건너뜀은 금화, 그 외 건너뜀은 제시만 닫힘
  function resolveOffer(run, offer, choice) {
    if (choice) PA.Growth.applyChoice(run, choice);
    else if (offer.pool === 'level') PA.Growth.skipChoice(run);
    else run.growth.pendingOffer = null;
  }
  // 헤드리스: 남은 선택을 봇 정책으로 전부 처리. onPick(offer, choice) 콜백으로 기록
  function resolveAll(run, ctx, pick, onPick) {
    let guard = 0, n = 0;
    for (;;) {
      const off = nextOffer(run, ctx); if (!off || guard++ > 200) break;
      const c = off.choices.length ? pick(off) : null; resolveOffer(run, off, c); n++; if (onPick) onPick(off, c);
    }
    return n;
  }
  return { encounterSeed, encounterOpts, makeEncounter, settleVictory, settleDefeat, nextOffer, resolveOffer, resolveAll };
})();
