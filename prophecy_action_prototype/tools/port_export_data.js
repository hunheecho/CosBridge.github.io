// Godot 이식용 데이터 내보내기: HTML 카탈로그(src/*_data.js 등)를 그대로 읽어 prophecy_godot/data/*.json으로 쓴다.
// 함수 값(applies·valid·hud·body)은 JSON에 담을 수 없으므로 플래그/문자열로 바꾸고, 규칙 동작은 GDScript에서 다시 쓴다.
// 늑대·늑대 우두머리는 Godot 0.3.1 규칙(first_fight.json, D33/D34/D35)의 물기·돌진 블록을 덧붙인다(HTML 옛 돌진 규칙은 옮기지 않음).
// 사용: node tools/port_export_data.js   (HTML 소스는 수정하지 않는다)
const fs = require('fs'), path = require('path');
const { load } = require('../test/load.js');
const PA = load();
const OUT = path.join(__dirname, '..', '..', 'prophecy_godot', 'data');
const FIRST = JSON.parse(fs.readFileSync(path.join(OUT, 'first_fight.json'), 'utf8'));
const META = { source: { html_version: PA.VERSION, html_commit: 'ee10fc7', exported_by: 'tools/port_export_data.js', godot_rules_from: 'first_fight.json(godot-0.3.1, D33/D34/D35)' } };
const strip = (o) => JSON.parse(JSON.stringify(o, (k, v) => typeof v === 'function' ? undefined : v));
function write(name, obj) { const p = path.join(OUT, name); fs.writeFileSync(p, JSON.stringify(Object.assign({ schema: 'prophecy_port/1' }, META, obj), null, 1) + '\n'); console.log(name, fs.statSync(p).size); }

// ---------- config ----------
const C = strip(PA.CONFIG);
delete C.WEAPONS; delete C.SPIN; delete C.MARK; delete C.BARRIER; // v0.5 이전 레거시(관통검·회전 검격·사냥꾼의 표식·파열 방벽)는 옮기지 않는다
C.PLAYER.dodge = strip(FIRST.player.dodge); // Godot 회피 규칙(D34)
C.PLAYER.hit_protect = C.PLAYER.hitProtect;
write('config.json', { config: C, arenas: strip(PA.ARENAS), blade_spoke: PA.BLADE_SPOKE, keys_text: PA.KEYS_TEXT, boss_action_text: PA.BOSS_ACTION_TEXT, version_html: PA.VERSION });

// ---------- weapons / growth ----------
write('weapons.json', { weapons: strip(PA.WEAPONS), startable: PA.STARTABLE, startable_all: PA.STARTABLE_ALL });
const commons = strip(PA.COMMONS); for (const id in PA.COMMONS) if (PA.COMMONS[id].applies) commons[id].applies = id === 'wide' ? 'width' : 'reach';
write('growth.json', { growth: strip(PA.GROWTH), commons, passives: strip(PA.PASSIVES), skills: strip(PA.SKILLS), e_skills: PA.E_SKILLS, boss_rewards: strip(PA.BOSS_REWARDS), region_tags: PA.REGION_TAGS, region_tag_text: PA.REGION_TAG_TEXT });

// ---------- enemies / bosses ----------
const EN = strip(PA.ENEMIES);
const gw = FIRST.enemies.wolf;
EN.wolf = Object.assign({}, EN.wolf, { godot_rules: true, hp: gw.hp, r: gw.r, speed: gw.speed, bite: gw.bite, dash: gw.dash, note: gw.note });
// 늑대 우두머리(정예): HTML 값(체력 120·r22·피해 18·속도 160·2연속 돌진·빈틈 1.2) + Godot 물기·돌진 재사용·동시 돌진 집계(잠정, PORT_BASELINE C2/Q5)
const ga = EN.wolf_alpha;
EN.wolf_alpha = Object.assign({}, ga, { godot_rules: true, provisional: 'C2/Q5: HTML 2연속 돌진 + Godot 물기·재사용·동시 집계',
  bite: Object.assign({}, gw.bite, { damage: ga.damage, reach: gw.bite.reach + (ga.r - gw.r) }),
  dash: Object.assign({}, gw.dash, { crouch: ga.crouch, lock: ga.lock, dash_time: ga.dashTime, dash_speed: ga.dashSpeed, recover: ga.recover, damage: ga.damage, dashes: ga.dashes, second_crouch: ga.secondCrouch, engage_dist: ga.engageDist }) });
for (const k in EN) { const d = EN[k]; if (d.engageDist != null && !d.godot_rules) d.engage_dist = d.engageDist; }
write('enemies.json', { enemies: EN, boss_defs: strip(PA.BOSS_DEFS), boss_hp_sets: strip(PA.BOSS_HP_SETS), boss_hp_set_default: 'hi', run_modes: strip(PA.RUN_MODES) });

// ---------- world ----------
// 밀도 모델(PORT_BASELINE C4, 잠정): 일반 적 전체 수 = HTML 편성 합 × 5(정예·구조물·보스 제외), 동시 상한 12, 묶음 3·간격 1.0, 역할별 동시 상한(시험값)
const density = { multiplier: 5, /* D33 기준 전투 = 숲 1일차 새벽(늑대 2+3=5) × 5 = 25마리(0.3.0 'x5') */ alive_cap: 12, group: 3, interval: 1.0, first_delay: FIRST.spawn.first_delay, warn: FIRST.spawn.warn, min_player_dist: FIRST.spawn.min_player_dist, group_spread: FIRST.spawn.group_spread, entry_points: FIRST.spawn.entry_points,
  type_alive_cap: { archer: 3, shaman: 1, frostcaller: 2, spider: 2, bomber: 3, shieldbearer: 3, boar: 2, burrower: 2, rogue: 3, spore: 3, wolf_alpha: 2 },
  note: '잠정 규칙(C4/Q1). 경험치·금화 예산은 HTML 편성 기준으로 고정하고 개체 수에 비례하지 않는다(종류별: HTML 예산 ÷ 해당 종류의 Godot 개체 수)',
  set_default: 'uniform_x5',
  // 비교 후보(2026-09-07 사용자 Q1 답변): 역할별 배율. 동시 상한은 바꾸지 않는다. 분류는 실제 행동 기준(enemies.js), 애매한 것은 reason에 근거.
  sets: {
    uniform_x5: { name: '일괄 ×5(현재 비교 설정, 최종 아님)', multiplier: 5 },
    roles: { name: '역할별(근접 ×5 · 원거리 ×2 · 지원/봉쇄 ×1~2 · 정예/구조물/보스 소환 ×1)', multiplier: 5,
      multiplier_by_type: { wolf: 5, rogue: 5, boar: 5, shieldbearer: 5, bomber: 5, burrower: 5, archer: 2, frostcaller: 2, spore: 2, spider: 1, shaman: 1 },
      role_class: {
        wolf: { role: '근접 무리', reason: '물기·돌진, 몸으로 압박' },
        rogue: { role: '근접 무리', reason: '측면 접근 후 베기' },
        boar: { role: '근접 무리(애매)', reason: '긴 직선 돌파는 통로 예고형 위협이라 원거리 장판처럼 화면을 가를 수 있음. 동시 상한 2가 이미 제한하므로 근접으로 둠' },
        shieldbearer: { role: '근접 무리(애매)', reason: '정면 방어·밀치기는 근접이지만 느린 차단자 역할. 봉쇄로 볼 수도 있음' },
        bomber: { role: '근접 무리(애매)', reason: '접근 후 폭발(범위 22)이라 근접 접근형이지만 폭발 범위가 장판 성격. ×2 후보도 가능' },
        burrower: { role: '근접 무리(애매)', reason: '지하 이동 뒤 발밑 기습·물기. 기습 지점 예고는 장판형이지만 피해는 근접' },
        archer: { role: '원거리', reason: '거리 유지·화살' },
        frostcaller: { role: '원거리(애매)', reason: '거리 유지 + 순차 바닥 장판. 원거리로 분류했으나 장판이 남으므로 봉쇄(×1~2) 후보' },
        spore: { role: '지원·봉쇄', reason: '독구름·사망 구름으로 지역 통제(약한 봉쇄 → ×2)' },
        spider: { role: '지원·봉쇄', reason: '거미줄로 이동 경로 제한(강한 봉쇄 → ×1)' },
        shaman: { role: '지원', reason: '치료·저주(×1)' },
        wolf_alpha: { role: '정예', reason: '배율 없음(×1), 경험치 단위값 그대로' } } } } };
// 세계 변화 두 단계(2026-09-07 사용자 합의: 매일 미세 강화 대신 관문 승리 뒤 세계가 바뀐다). 수치는 Codex 시험 제안(사용자 승인값 아님).
// 등급은 정예와 별개(elite 정의는 등급 배정에서 제외). 같은 붉은 개체는 1차·2차에서 같은 수치. 속도·예고·회피 시간은 등급으로 바꾸지 않는다.
const world_stages = {
  note: '사용자 합의: 변화 전 → 3일차 관문 뒤 붉은 달(일반+붉은) → 5일차 관문 뒤 일반 퇴장(붉은+상위 변이). 실제 관문 완료(bossesDone)에서만 도출. 배율·비율은 시험값',
  tiers: { normal: { name: '일반', hp: 1, dmg: 1 },
    red: { name: '붉은 개체', prefix: '붉은 ', hp: 1.25, dmg: 1.10, tint: '#d24a3a', mark: 'red' },
    apex: { name: '상위 변이', prefix: '변이 ', hp: 1.60, dmg: 1.20, tint: '#8a3fc9', mark: 'apex' } },
  stages: [ { id: 0, name: '변화 전', mix: { normal: 1 } },
    { id: 1, name: '붉은 달', after_boss: 'boss', mix: { normal: 0.6, red: 0.4 } },
    { id: 2, name: '붉은 달 · 상위 변이', after_boss: 'guardian', mix: { red: 0.6, apex: 0.4 } } ],
  mix_note: '비율 60:40은 첫 후보. 종류별 정수 편성(등장 순서 뒤쪽이 높은 등급). 정예·구조물·보스 소환은 등급 배정 제외',
  risk_elite_from_stage: 2, risk_elite_extra: 1, risk_elite_note: '2단계부터 위험 임무 출격의 마지막 웨이브에 정예(늑대 우두머리) +1 — 일부 위험 전투에만(잠정). 정예 경험치 단위값은 XP_VALUE 그대로 예산에 더해진다',
  excludes_day_hp_set: true, exclude_note: '세계 변화가 켜진 회차에서는 날짜 체력 세트(dayA 등)를 적용하지 않는다(중복 강화 금지)' };
// 반복 콘텐츠(2026-09-07 사용자 합의 방향 4가지, 내용·수치는 구현자 시험값 — 사용자 승인 아님)
// 1) 회차 특징: 회차 시작 시 하나(시드 결정, 재접속 재추첨 없음). 방문 상인 시점 / 사건 편성 / 위험 임무 편성 중 하나에만 영향. 핵심 세계 변화 일정·경험치 배율은 바꾸지 않는다.
const world_features = {
  note: '시험값(구현자). 한 줄로 이해되는 작은 차이. 세계 변화 일정·경험치 배율 불변',
  list: [
    { id: 'wandering_merchant', name: '떠돌이 상인의 해', line: '방문 상인이 1·3·5일차 점심부터 온다(원래 2·4·6)', kind: 'merchant', merchant_days: [1, 3, 5] },
    { id: 'misty_season', name: '안개 낀 계절', line: '탐험 사건에 보급소·정찰자가 더 자주 나오고 시간의 샘은 나오지 않는다', kind: 'events', event_weights: { supply: 2, scout: 2, time_spring: 0 } },
    { id: 'bounty_year', name: '위험한 의뢰의 해', line: '임무 카드에 위험 조건이 더 자주 붙고(75%) 위험 임무 보상 ×1.35', kind: 'risk', risk_chance: 0.75, risk_reward_mult: 1.35 } ] };
// 2) 같은 지역의 사전 편성(역할 조합): 지역×날짜 정의마다 기본 + 2안. 첫날 숲(승인된 첫 전투)은 고정. 합계는 기본과 같게 두어 경험치 예산 차이를 줄였다(종류별 단위값 차이는 남는다).
//    선택은 카드 생성 시드로 1회(카드마다 정수 1개 소비), 같은 지역에서 직전에 쓴 편성은 피한다. 역할: siege 포위(근접 다수) / escort 원거리 호위 / breach 돌파(돌파·측면) / shieldwall 방진 / ambush 매복(지하·폭발)
const FN = { siege: '포위', escort: '원거리 호위', breach: '돌파', shieldwall: '방진', ambush: '매복' };
const FD = { siege: '근접 무리가 사방에서 조여 온다', escort: '원거리가 뒤에서 쏘고 근접이 앞을 막는다', breach: '돌파·측면 공격이 직선으로 들어온다', shieldwall: '방패병이 앞을 막고 궁수가 뒤에서 쏜다', ambush: '지하·폭발 개체가 발밑과 근접에서 터진다' };
const F = (id, waves) => ({ id, name: FN[id], desc: FD[id], waves: waves.map(w => w.map(([type, n]) => ({ type, n }))) });
const formation_sets = {
  note: '시험값(구현자). 기본 편성(day_waves)은 그대로 두고 대안 2개씩. 첫날 숲은 고정(D33)',
  forest: {
    '2': [F('siege', [[['wolf', 3]], [['wolf', 4]], [['boar', 1], ['wolf', 3]]]), F('escort', [[['archer', 2], ['wolf', 1]], [['archer', 2], ['wolf', 2]], [['archer', 1], ['boar', 1], ['wolf', 2]]])],
    '6': [F('breach', [[['boar', 3], ['wolf', 1]], [['boar', 3], ['rogue', 1]], [['boar', 2], ['wolf', 2], ['wolf_alpha', 1]]]), F('escort', [[['shaman', 1], ['wolf', 3]], [['archer', 3], ['rogue', 2]], [['shaman', 1], ['wolf', 2], ['wolf_alpha', 1]]])] },
  ridge: {
    '1': [F('siege', [[['wolf', 3]], [['wolf', 3], ['archer', 1]], [['wolf', 3], ['archer', 1]]]), F('shieldwall', [[['shieldbearer', 2], ['archer', 1]], [['shieldbearer', 2], ['archer', 2]], [['archer', 2], ['wolf', 2]]])],
    '3': [F('siege', [[['wolf', 3], ['spider', 1]], [['wolf', 4], ['archer', 1]], [['wolf', 3], ['archer', 1]]]), F('escort', [[['archer', 3], ['shieldbearer', 1]], [['archer', 3], ['shieldbearer', 2]], [['archer', 2], ['spider', 1], ['shieldbearer', 1]]])],
    '6': [F('breach', [[['rogue', 3], ['shieldbearer', 1]], [['rogue', 3], ['archer', 2]], [['rogue', 3], ['shieldbearer', 2], ['archer', 2]]]), F('siege', [[['wolf', 4], ['archer', 1]], [['wolf', 4], ['rogue', 2]], [['wolf', 3], ['archer', 2]]])] },
  marsh: {
    '2': [F('escort', [[['archer', 2], ['spore', 1]], [['archer', 2], ['wolf', 2]], [['archer', 1], ['spore', 2]]]), F('siege', [[['wolf', 3]], [['wolf', 3], ['spore', 1]], [['wolf', 2], ['spore', 1]]])],
    '4': [F('escort', [[['archer', 2], ['spore', 1]], [['frostcaller', 2], ['archer', 2]], [['archer', 2], ['spider', 1], ['spore', 3]]]), F('ambush', [[['burrower', 2], ['spore', 1]], [['burrower', 2], ['wolf', 2]], [['spider', 2], ['burrower', 1], ['spore', 3]]])],
    '6': [F('escort', [[['frostcaller', 2], ['archer', 2]], [['archer', 3], ['spore', 2]], [['frostcaller', 2], ['archer', 2], ['spider', 2]]]), F('ambush', [[['burrower', 2], ['bomber', 1]], [['burrower', 2], ['spore', 2], ['bomber', 1]], [['burrower', 2], ['spider', 2], ['bomber', 3]]])] },
  den: {
    '3': [F('escort', [[['archer', 2], ['wolf', 2]], [['archer', 2], ['wolf', 2]], [['archer', 1], ['wolf', 1], ['wolf_alpha', 1]]]), F('breach', [[['boar', 2], ['wolf', 1]], [['boar', 2], ['wolf', 2]], [['boar', 1], ['wolf', 2], ['wolf_alpha', 1]]])],
    '4': [F('siege', [[['wolf', 4]], [['wolf', 4], ['shaman', 1]], [['wolf', 3], ['boar', 1], ['wolf_alpha', 1]]]), F('escort', [[['archer', 2], ['wolf', 2]], [['archer', 2], ['wolf', 2], ['shaman', 1]], [['archer', 2], ['wolf', 1], ['shaman', 1], ['wolf_alpha', 1]]])],
    '5': [F('siege', [[['wolf', 4], ['rogue', 1]], [['wolf', 4], ['rogue', 1]], [['wolf', 2], ['rogue', 2], ['wolf_alpha', 1]]]), F('ambush', [[['burrower', 2], ['rogue', 2]], [['burrower', 2], ['boar', 2], ['wolf', 2]], [['burrower', 2], ['bomber', 2], ['wolf_alpha', 1]]])],
    '6': [F('breach', [[['boar', 3], ['rogue', 2]], [['boar', 3], ['rogue', 2], ['bomber', 1]], [['boar', 2], ['rogue', 2], ['shaman', 1], ['wolf_alpha', 2]]]), F('escort', [[['archer', 3], ['wolf', 2]], [['archer', 3], ['shaman', 1], ['wolf', 2]], [['archer', 2], ['shaman', 1], ['wolf', 2], ['wolf_alpha', 2]]])] },
  deep: {
    '5': [F('siege', [[['wolf', 4], ['rogue', 2]], [['wolf', 4], ['rogue', 2]], [['wolf', 2], ['rogue', 2], ['wolf_alpha', 1]]]), F('escort', [[['archer', 3], ['frostcaller', 1], ['spore', 1]], [['archer', 3], ['frostcaller', 2], ['spore', 1]], [['archer', 2], ['shaman', 1], ['spore', 2], ['wolf_alpha', 1]]])],
    '6': [F('breach', [[['boar', 3], ['rogue', 2]], [['boar', 3], ['rogue', 2], ['bomber', 2]], [['boar', 2], ['rogue', 2], ['shieldbearer', 1], ['wolf_alpha', 2]]]), F('ambush', [[['burrower', 2], ['bomber', 2], ['spore', 1]], [['burrower', 3], ['spider', 2], ['bomber', 2]], [['burrower', 2], ['frostcaller', 2], ['spore', 1], ['wolf_alpha', 2]]])] } };
// 3) 선택형 위험 전투: 기존 사건 틀의 '강적의 흔적'(events에 추가, missions.json). 4) 관문별 보스 후보: 지금은 기존 3종을 그대로 후보 1개씩. 후보가 늘면 회차 시작 시 계획(bossPlan)으로 확정해 거점에 미리 보여준다.
const boss_gates = { note: '관문별 후보 구조(확장용). 후보가 2개 이상이면 회차 시작 시 시드로 하나를 정하고(bossPlan) 거점 상단 줄에 미리 표시한다. 새 보스 제작은 이번 범위 아님',
  gates: [ { day: 3, candidates: ['boss'] }, { day: 5, candidates: ['guardian'] }, { day: 7, candidates: ['eater'] } ] };
write('world.json', { world_stages, world_features, formation_sets, boss_gates, time_slots: PA.TIME_SLOTS, schedule: strip(PA.SCHEDULE), mission_steer: PA.MISSION_STEER, day_waves: strip(PA.DAY_WAVES), day_hp_sets: PA.DAY_HP_SETS, elite_day_mult: PA.ELITE_DAY_MULT, slot_variants: strip(PA.SLOT_VARIANTS), merchant_visits: PA.MERCHANT_VISITS, equipment: strip(PA.EQUIPMENT), equip_slots: PA.EQUIP_SLOTS, equip_slot_names: PA.EQUIP_SLOT_NAMES, shop: strip(PA.SHOP), regions: strip(PA.REGIONS), materials: strip(PA.MATERIALS), density, region_arena: { forest: 'clearing', ridge: 'pillars', marsh: 'forest', den: 'pillars', deep: 'clearing', boss: 'clearing' } });

// ---------- missions / events ----------
const EV = strip(PA.EVENTS); const evIds = PA.EVENT_IDS.slice();
// 선택형 위험 전투(2026-09-07 사용자 합의 방향, 수치는 구현자 시험값): 기존 사건 틀. 거절 가능. 선택 전에 보상·시간·손실을 표시한다.
EV.challenge = { name: '강적의 흔적', desc: '정예 2마리가 이끄는 무리(한 단계 높은 등급)와의 추가 전투. 시간 소모 없음, 체력 회복 없음. 승리: 이번 출격 전리품 금화 ×1.6 + 지역 보상 3택 1회. 패배: 이번 출격 미정산 전리품 상실.', elites: 2, goldMult: 1.6, minHp: 0.5, provisional: true };
evIds.push('challenge');
write('missions.json', { objectives: strip(PA.OBJECTIVES), objective_ids: PA.OBJECTIVE_IDS, structures: strip(PA.STRUCTURES), services: strip(PA.SERVICES), missions: strip(PA.MISSIONS), events: EV, event_ids: evIds });

// ---------- balance / lab ----------
write('balance.json', { balance_sets: strip(PA.BALANCE_SETS), balance_default: PA.BALANCE_DEFAULT, difficulty: strip(PA.DIFFICULTY), layouts: strip(PA.LAYOUTS), lab: strip(PA.LAB), lab_combos: strip(PA.LAB_COMBOS) });

// ---------- glossary (body 함수는 현재 데이터로 평가한 문자열) ----------
const G = {}; const all = PA.glossaryAll(); for (const id in all) G[id] = { name: all[id].name, short: all[id].short, body: typeof all[id].body === 'function' ? all[id].body() : String(all[id].body || ''), related: all[id].related || [] };
write('glossary.json', { glossary: G });
console.log('done');
