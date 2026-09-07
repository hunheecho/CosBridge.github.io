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
write('world.json', { time_slots: PA.TIME_SLOTS, schedule: strip(PA.SCHEDULE), mission_steer: PA.MISSION_STEER, day_waves: strip(PA.DAY_WAVES), day_hp_sets: PA.DAY_HP_SETS, elite_day_mult: PA.ELITE_DAY_MULT, slot_variants: strip(PA.SLOT_VARIANTS), merchant_visits: PA.MERCHANT_VISITS, equipment: strip(PA.EQUIPMENT), equip_slots: PA.EQUIP_SLOTS, equip_slot_names: PA.EQUIP_SLOT_NAMES, shop: strip(PA.SHOP), regions: strip(PA.REGIONS), materials: strip(PA.MATERIALS), density, region_arena: { forest: 'clearing', ridge: 'pillars', marsh: 'forest', den: 'pillars', deep: 'clearing', boss: 'clearing' } });

// ---------- missions / events ----------
const EV = strip(PA.EVENTS); const evIds = PA.EVENT_IDS.slice();
write('missions.json', { objectives: strip(PA.OBJECTIVES), objective_ids: PA.OBJECTIVE_IDS, structures: strip(PA.STRUCTURES), services: strip(PA.SERVICES), missions: strip(PA.MISSIONS), events: EV, event_ids: evIds });

// ---------- balance / lab ----------
write('balance.json', { balance_sets: strip(PA.BALANCE_SETS), balance_default: PA.BALANCE_DEFAULT, difficulty: strip(PA.DIFFICULTY), layouts: strip(PA.LAYOUTS), lab: strip(PA.LAB), lab_combos: strip(PA.LAB_COMBOS) });

// ---------- glossary (body 함수는 현재 데이터로 평가한 문자열) ----------
const G = {}; const all = PA.glossaryAll(); for (const id in all) G[id] = { name: all[id].name, short: all[id].short, body: typeof all[id].body === 'function' ? all[id].body() : String(all[id].body || ''), related: all[id].related || [] };
write('glossary.json', { glossary: G });
console.log('done');
