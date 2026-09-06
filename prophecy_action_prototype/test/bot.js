// 헤드리스 시험용 조작 정책. 실제 정책은 src/bot.js(PA.Bot)에 있고 여기서는 '균형' 정책을 감싼다(브라우저 시험실과 같은 코드).
const MEM = new WeakMap();
function policy(PA, st, policyId) { let mem = MEM.get(st); if (!mem) { mem = {}; MEM.set(st, mem); } return PA.Bot.decide(policyId || 'balanced', st, mem); }
// 보스전을 정책 봇으로 끝까지 실행
function runBossFight(PA, run, seed, maxSec, policyId) {
  const st = PA.Combat.create({ build: PA.Run.build(run), seed: seed || 5, boss: true, arena: 'clearing', waves: [] });
  return PA.Bot.runCombat(st, policyId || 'balanced', { maxSec: maxSec || 300 });
}
module.exports = { policy, runBossFight };
