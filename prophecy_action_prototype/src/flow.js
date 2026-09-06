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
      labText: R.layoutText(run) || null, run,
    }, sortie.mission ? { objective: sortie.objective, risk: sortie.risk || null, mission: { cardId: sortie.cardId, objective: sortie.objective, risk: sortie.risk || null } } : {}, sortie.eventFight && PA.Events ? PA.Events.fightOpts(run, sortie) : {}, extra || {});
  }
  function makeEncounter(run, sortie, extra) { const st = PA.Combat.create(encounterOpts(run, sortie, extra)); if (run.buffs && run.buffs.skillCd) st.tempBuff = 'skillCd'; run.pendingSortie = null; return st; } // 임시 강화는 이 전투 내내 적용(레벨업 재계산 포함)되고 정산 때 소비. 전투 시작 시 보류 출격 상태 해제
  function consumeBuff(run, st) { if (st && st.tempBuff === 'skillCd' && run.buffs) delete run.buffs.skillCd; }
  // 조우 승리 정산(정확히 1회): 전리품 굴림 → 출격 전리품 반영 → 지역 경험치 → 더 깊이면 지역 3택을 보류 선택으로 등록(저장됨)
  function settleVictory(run, sortie, st) {
    consumeBuff(run, st);
    const eliteKilled = st.enemies.some(e => e.elite && e.dead) || (st.status === 'won' && st.objective === 'elite');
    const reward = PA.Run.rollReward(run, sortie, st.rng, { chestGold: st.stats.chestGold, eliteKilled });
    if (sortie.eventFight) { reward.gold = 0; reward.mats = {}; reward.chestGold = 0; reward.eventFight = sortie.eventFight; PA.Events.onFightWin(run, sortie); } // 사건 추가 전투: 전리품 없음, 서비스만
    if (sortie.deep && sortie.deepGoldMult) { reward.gold = Math.round(reward.gold * sortie.deepGoldMult); reward.sealedLoot = true; sortie.deepGoldMult = null; } // 봉인된 전리품: 밝혀진 보상(1회)
    if (sortie.mission) { // 임무: 지역 보상의 재료를 종류 지정 3택으로 대체(금화는 유지, 위험 조건이면 ×1.25). 처치 경험치는 전투 중 즉시
      reward.mats = {}; if (sortie.risk) reward.gold = Math.round(reward.gold * PA.MISSIONS.riskRewardMult); reward.mission = true;
      reward.missionPick = PA.Sortie.onMissionWin(run, sortie); // 하루 1회: 이미 완료된 카드면 3택 없음
    }
    PA.Run.applyEncounterResult(run, sortie, 'won', reward, st.player.hp);
    reward.xp = sortie.eventFight || reward.eventFight ? 0 : PA.Run.regionBonusXp(sortie.regionId, sortie.deep); PA.Growth.addXp(run.growth, reward.xp);
    if (!reward.eventFight && PA.Events && !sortie.event) sortie.event = PA.Events.roll(run, sortie); // 탐험 사건: 출격당 최대 1회, 시드 결정적
    run.pendingSortie = sortie; // 전투 뒤 안전 화면 상태를 저장(보상·사건·더 깊이 선택을 새로고침해도 이어감)
    if (sortie.deep && PA.GROWTH.DEEP_PICK && !sortie.deepPicked) { sortie.deepPicked = true; run.growth.pendingDeepPick = { regionId: sortie.regionId, key: `${sortie.seed}:${sortie.encounters}` }; }
    return reward;
  }
  // 보스전(회차 관문): 단계별 보스·체력 후보. 입장 스냅샷은 Run.startBoss가 만든다
  function makeBossEncounter(run, sortie) { const b = PA.Run.build(run); const st = PA.Combat.create({ build: b, hp: b.hpMax, seed: sortie.seed, boss: true, bossId: sortie.bossId || 'boss', bossHp: PA.Run.bossHp(run, sortie.bossId || 'boss'), arena: 'clearing', waves: [], run }); if (run.buffs && run.buffs.skillCd) st.tempBuff = 'skillCd'; run.pendingSortie = null; return st; }
  // 보스 승리 정산(정확히 1회): 처치 기록·다음 단계·희귀 보상 보류(마지막 보스는 없음)
  function settleBossVictory(run, st) { consumeBuff(run, st); const rec = PA.Run.bossVictory(run, st.stats); run.pendingSortie = null; return rec; }
  function settleBossDefeat(run, st) { consumeBuff(run, st); PA.Run.bossDefeat(run); run.pendingSortie = null; }
  function settleDefeat(run, sortie, st) { consumeBuff(run, st); PA.Run.applyEncounterResult(run, sortie, 'lost', null, 0); PA.Run.defeat(run, sortie); run.pendingSortie = null; }
  // 다음에 제시할 선택(순서 고정): 저장된 보류 제시 → 미처리 레벨업 → 임무 보상 3택 → 더 깊이 지역 3택 → 없음(null)
  // 더 깊이 3택은 여기서 보류 등록을 소비하고 pendingOffer로 옮긴다(새로고침해도 같은 제시, 두 번 제시되지 않음). 후보가 없으면 제시 없이 소비
  function nextOffer(run, ctx) {
    const g = run.growth; ctx = ctx || {};
    if (g.pendingOffer) return g.pendingOffer;
    if (g.pendingLevelUps > 0) return PA.Growth.generateOffer(run, { pool: 'level', regionId: ctx.regionId || null });
    if (g.pendingMissionPick) { const off = PA.Sortie.missionOffer(run); return off || nextOffer(run, ctx); } // 임무 보상 3택(후보 없으면 금화로 대체·1회)
    if (g.pendingBossPick) { const bp = g.pendingBossPick; g.pendingBossPick = null; const off = PA.Growth.generateOffer(run, { pool: 'boss', bossId: bp.bossId, stage: bp.stage }); if (!off.choices.length) { g.pendingOffer = null; PA.Run.addLog(run, '희귀 보상: 적용 가능한 후보 없음(제시 생략)'); g.bossPickNone = (g.bossPickNone || 0) + 1; return nextOffer(run, ctx); } return off; } // 보스 희귀 보상(1·2보스 뒤 1회, 유효 후보만)
    if (g.pendingEventPick) { const ep = g.pendingEventPick; g.pendingEventPick = null; const off = PA.Growth.generateOffer(run, { pool: 'mission', kinds: [ep.kind], regionId: ep.regionId, missionKind: ep.kind, event: true }); if (!off.choices.length) { g.pendingOffer = null; return nextOffer(run, ctx); } return off; } // 사건 보상(무기 제단)
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
  // 거점 서비스: 제시 재선택(레벨업 3택 1회) — 순번을 넘겨 다른 제시. 권 소비 1회
  function rerollOffer(run) {
    const g = run.growth, off = g.pendingOffer; if (!off || off.pool !== 'level' || !PA.Run.hasService(run, 'reroll')) throw new Error('재선택 불가');
    PA.Run.useService(run, 'reroll'); g.pendingOffer = null; g.choiceSeq++; g.picks.reroll = (g.picks.reroll || 0) + 1;
    return PA.Growth.generateOffer(run, { pool: 'level', regionId: off.regionId });
  }
  // 거점 서비스: 개조 교체 — 개조 1개를 떼고 그 무기의 다른 개조 3택. 후보가 없으면 되돌리고 권 유지
  function modSwapOffer(run, weaponId, modId) {
    const g = run.growth, w = g.weapons.find(x => x.id === weaponId); if (!w || !w.mods.includes(modId) || !PA.Run.hasService(run, 'mod_swap') || g.pendingOffer) throw new Error('교체 불가');
    w.mods = w.mods.filter(m => m !== modId);
    const cands = PA.Growth.candidates(run, { pool: 'level' }).filter(c => c.kind === 'weapon_mod' && c.id === weaponId && c.mod !== modId);
    if (!cands.length) { w.mods.push(modId); return null; }
    PA.Run.useService(run, 'mod_swap'); g.swappedOut = (g.swappedOut || []).concat([weaponId + ':' + modId]);
    const off = PA.Growth.generateOffer(run, { pool: 'mission', kinds: ['weapon_mod'], missionKind: 'weapon_mod', regionId: null, weaponOnly: weaponId, excludeMod: modId });
    if (!off.choices.length) { g.pendingOffer = null; w.mods.push(modId); run.services.mod_swap++; return null; }
    return off;
  }
  // 전투 뒤 안전 화면의 다음 단계(화면·봇 공용): 남은 선택 → 미처리 사건 → 다음 행동(after)
  function afterCombatStep(run, sortie) { if (nextOffer(run, { regionId: sortie.regionId })) return 'offer'; if (sortie.event && !sortie.event.resolved) return 'event'; return 'after'; }
  function returnHome(run, sortie) { PA.Run.returnToBase(run, sortie); run.pendingSortie = null; }
  return { encounterSeed, encounterOpts, makeEncounter, settleVictory, settleDefeat, nextOffer, resolveOffer, resolveAll, afterCombatStep, returnHome, rerollOffer, modSwapOffer, makeBossEncounter, settleBossVictory, settleBossDefeat };
})();
