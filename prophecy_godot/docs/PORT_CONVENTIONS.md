# Godot 이식 코드 규약 (규칙 계층 API 계약)

모든 규칙 모듈은 `RefCounted` + `class_name P*`의 **static 함수**로 쓰고, 첫 인자로 `st: CombatState`를 받는다. 개체·상태는 모두 `Dictionary`(HTML 객체와 1:1), 좌표는 `float`(double). Node·Vector2·Input·그리기·파일·시간(Time)·난수(randi) 금지. 난수는 `st.rng`(PRng, mulberry32)만. 이름은 HTML 함수명을 snake_case로 옮긴다(`damageEnemy` → `damage_enemy`).

## 데이터 접근
`PCatalog.config()/weapons()/growth()/commons()/passives()/skills()/boss_rewards()/enemies()/boss_defs()/world()/missions()/balance()/glossary()`(모두 Dictionary, 1회 로드 캐시). `PCatalog.enemy(type)`, `PCatalog.weapon(id)`. JSON 숫자는 float이므로 정수는 `int()`.

## 전투 상태(CombatState) 필드
`t, step_n, status("running|won|lost|timeout"), seed_value, rng, cfg(첫 전투 호환 설정), build, player, enemies[], pending[], projectiles[], zones[], effects[], events[], field({}=없음), skill_state, mines[], delayed[], pickups[], objects[], obj, chest, mark_target(null), boss(null|Dictionary), boss_id, intro, mode("normal|boss"), objective, region_id, hp_mult, time_limit, fixed_build, overlap_limit, spawn_hold, formation, arena_w/h, obstacles[], stats{}, metrics{dmg, taken, taken_hits, enemies, hits, patterns, ...}, active_t{}, attack_log[]`.

### 플레이어(dict)
`x,y,r,hp,hp_max,shield,shield_max,face,moving,dodge_active,dodge_t,dodge_dx,dodge_dy,dodge_cd,dodge_dist,dodge_released,dodge_end,hit_prot,zone_tick,special_cd,e_cd,swing_t,swing_form,swing_angle,walk_t,hurt_t,flash,dead,ward_shield`

### 적(dict) — `spawn_enemy(type, x, y)`가 만든다
공통: `id,type,def(카탈로그 dict),name,x,y,r,hp,hp_max,hp_class,spawn_t,first_hit_t(-1),acted,prepared,state,state_t,dir,aim_angle,chill,burn({}|{t,dps,tick,src}),bleed({}),stasis,conduct,flash,dead,death_t,vx,vy,elite,boss,structure,hidden,airborne,summoned,grace,bite_t,steer_side,steer_t,face_x,last_x,last_y,ready_t(-1),recover_dur,blocked_t,resonance{},resonance_t,brand`
늑대(Godot 규칙): `dash_ready_at,dash_cd,bite_cd,last_dash_end,dash_granted,bite_hit_done,bites,dashes,dash_left`
상태 이름은 HTML 그대로: 늑대 `approach|bite_track|bite_lock|bite_hit|bite_recover|crouch|lock|dash|recover`, 궁수 `approach|aim|lock|recover`, 포자 `approach|swell|recover`, 신규 8종·보스는 enemies.js/boss.js/boss2.js의 문자열 그대로.

### 투사체(dict)
`owner("player|enemy"), kind, x,y,vx,vy,r,ttl,dead, hits(Dictionary id→true), dmg(적 투사체), shooter(적 dict|null), weapon(무기 런타임 dict|null), dmg_mult, opt(Dictionary), target(dict|null), turn, speed, pierce, ricochet, boomerang({tx,ty,phase,speed}|{}), chill, shatter, ground, angle, width, cloned, is_clone, tag`

### 지역(zone dict) — `add_zone(type, x, y, r, ttl, dmg)`
`type("spore|fire|coldground|storm|slowecho|windpath|web|frostzone|hazard"), x,y,r,ttl,max_ttl,dmg,tick,t` + 확장 `weapon, extended, slow, order, owner, warn, armed, tag`

### 무기 런타임(dict) — `st.weapons[]`
`stats(파생 수치: id,level,mods[],kind,name,damage,interval,range,arc_deg,width,radius,count,angular,hit_gap,hits,speed,turn,hop,hops,chill,ttl,tick,trigger,arm,max,knock,def), id, timer, count, orbit, launch_t, last_hit(Dictionary id→t), echo({}|{t,target}), blade_pos[]`

## 핵심 API (combat_state.gd)
- 이벤트/효과: `st.ev(name, data={})`, `st.fx(dict)`, `st.text(x, y, txt, color)`
- 지형: `push_out(o)`, `move_swept(o, dx, dy, slide=false) -> {hit:""|"wall"|id, t}`, `los_blocked(ax,ay,bx,by)`, `valid_pos(x,y,r)`, `nearest_valid_pos(x,y,r,max_r=260) -> [] | [x,y]`, `beam_length(fx,fy,ang,L)`, `steer_dir(e,tx,ty) -> [x,y]`, `approach(e,tx,ty,speed,dt)`
- 시간: `time_factor(o) -> float`(감속장 0.4 / 잔향 0.7 / 1), `enemy_speed_mult(e)`(min(tf, 냉기 0.6)), `in_field(o)`
- 피해: `damage_player(amount, src:String, attacker=null) -> bool`(유효/명목 분리 유지), `zone_damage(amount)`, `damage_enemy(e, amount, opt) -> float` — `opt`는 Dictionary `{src:{weapon,weapon_id,level,direct,extra,skill,skill_id,tag}, dir:[x,y], knock, from:{x,y}, bleed, chill, dot, ground, no_conduct, loop, tag}` 또는 문자열 src_key(첫 전투 호환). `kill_enemy(e, opt)`
- 스폰: `spawn_enemy(type,x,y)`, `queue_wave(wave:Array[{type,n}])`(가장자리 예고 등장, HTML), `queue_group(type,n)`(밀도 모델), `remaining()`, `elite_count()`
- 판단 보조: `may_attack(e, dt)`, `wolf_may_attack(e, dt)`, `is_committed(e)`, `note_attack(e, "prepare|execute|death")`, `metrics_for(e)`, `alive_enemies()`(structure 포함, hidden 포함), `alive_targets()`(hidden 제외)
- 상태: `add_zone`, `end_field()`, `rebuild(build)`, `summary()`, `step(input, dt)`
- 입력 dict: `{mx,my,dodge_press,dodge_held,special,skill_e}`

## 피해 출처 키(피해 통계)
`weapon:<id>` · `dot:burn@<weapon_id|common>` · `dot:bleed@<weapon_id>` · `skill:q` · `skill:<e_id>` · `common:frost|flare|stasis|ember` · `reward:resonance` · `other`. 받은 피해 src: `wolf:bite|wolf:dash|arrow|zone|boss_sweep|boss_dash|boss_pounce|boss_mark|boss_wide|shock|boar|bash|hex|blast|emerge|bite|frostzone|slash|hazard`.

## 첫 전투 호환(D33 기준 전투 보존)
`CombatState.first_fight(cfg, seed)`가 `first_fight.json` 설정으로 상태를 만들며 RNG 소비 순서·늑대 규칙·겹침 해소·넉백(×2)·검격 타이밍이 0.3.1과 같아야 한다(`tests/run_tests.gd` 72개가 그 증거). 늑대 규칙 코드는 `enemies.gd`로 옮기되 동작은 바꾸지 않는다.
