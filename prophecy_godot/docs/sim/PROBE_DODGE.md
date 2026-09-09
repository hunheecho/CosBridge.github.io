# 조사: 회피가 정예의 '연계 완주'를 줄였는가 — 행동 순서로 가른 결과

생성 `tools/probe_dodge.gd` · 시험실 장면(정예 1마리 · 1막 시작 빌드 · 최대 90초) · 봇 ["balanced", "aggressive"] · 시드 [1, 2, 3].
장면·연계 판별표는 `tests/elites_bot_measure.gd`와 **같은 값**이다. **봇 승패는 판정이 아니다.**
회피를 끈 판은 비교 전용 스위치 `PEnemiesNew.set_dodge_on(false)`로만 만든다 — 자료·수치는 그대로다.

## 1. 회피 켬/끔 — 같은 시드·같은 봇으로 나란히

| 정예 | 연계 완주(끔→켬) | 연계 시작(끔→켬) | 공격 개시 수(끔→켬) | **공격 사이 빈 시간 중앙값**(끔→켬) | 살아 있던 시간(끔→켬) | 회피 발동 | 회피에 묶인 시간 |
|---|---|---|---|---|---|---:|---:|
| 정예 궁수 | 3.0 → 2.7 (-0.33회) | 3.7 → 3.5 | 3.7 → 3.5 | 1.42초 → 1.86초 (**+0.45초**) | 11.9초 → 12.5초 (+0.59초) | 6회 | 0.9초 |
| 정예 검사 | 4.0 → 4.0 (+0.00회) | 1.0 → 1.0 | 4.0 → 4.0 | 2.22초 → 2.22초 (**+0.00초**) | 18.4초 → 18.7초 (+0.33초) | 8회 | 1.4초 |
| 피의 송곳니 | 3.0 → 3.0 (+0.00회) | 3.0 → 3.0 | 3.0 → 3.0 | 1.62초 → 2.43초 (**+0.82초**) | 10.8초 → 11.0초 (+0.28초) | 6회 | 0.8초 |
| 역병 조율사 | 2.5 → 2.5 (+0.00회) | 2.5 → 2.5 | 4.0 → 3.5 | 1.52초 → 1.99초 (**+0.48초**) | 10.5초 → 10.5초 (-0.00초) | 5회 | 0.7초 |
| 사슬 집행자 | 1.5 → 1.5 (+0.00회) | 1.5 → 1.5 | 7.5 → 6.5 | 0.92초 → 1.00초 (**+0.08초**) | 11.3초 → 11.5초 (+0.18초) | 6회 | 1.2초 |
| 군단 기수 | 5.0 → 4.0 (-1.00회) | 1.0 → 1.0 | 5.0 → 4.0 | 1.22초 → 2.65초 (**+1.43초**) | 9.4초 → 8.8초 (-0.64초) | 6회 | 1.1초 |
| 균열 채굴자 | 2.0 → 1.5 (-0.50회) | 2.0 → 1.8 | 6.0 → 5.3 | 1.02초 → 1.39초 (**+0.37초**) | 14.2초 → 13.3초 (-0.89초) | 6회 | 1.0초 |

## 2. 세 원인 중 무엇인가 — 행동 순서가 말하는 것

| 정예 | ㉮ 연계 진행 중 회피로 끊김 | ㉯ 다음 공격 시작 지연 | ㉰ 먼저 죽어 시간이 줄었나 | **요구 위반: 공격 준비·실행 중 회피** |
|---|---|---|---|---|
| 정예 궁수 | 0회 — 아니다 | **그렇다(+0.45초)** | 아니다(+0.59초) | 없다 |
| 정예 검사 | 0회 — 아니다 | 아니다(+0.00초) | 아니다(+0.33초) | 없다 |
| 피의 송곳니 | 0회 — 아니다 | **그렇다(+0.82초)** | 아니다(+0.28초) | 없다 |
| 역병 조율사 | 0회 — 아니다 | **그렇다(+0.48초)** | 아니다(-0.00초) | 없다 |
| 사슬 집행자 | 0회 — 아니다 | **그렇다(+0.08초)** | 아니다(+0.18초) | 없다 |
| 군단 기수 | 0회 — 아니다 | **그렇다(+1.43초)** | **그렇다(-0.64초)** | 없다 |
| 균열 채굴자 | 0회 — 아니다 | **그렇다(+0.37초)** | **그렇다(-0.89초)** | 없다 |

- 요구 위반이 나온 종류: **없다**
- 회피가 묶는 시간 = 반응 지연 + 이동 + 추스르는 틈. 이 동안 `elite_may_start`가 막히므로 **새 공격을 시작하지 않는다**(설계 그대로).

## 3. 대표 장면의 행동 순서(상태 전이 로그) — 봇 `balanced` · 시드 1

### 군단 기수

**회피 끔** — 연계 시작 1 · 완주 6 · 공격 개시 6 · 살아 있던 시간 10.6초 · 회피 0회(연계 중 0회 · COMMITTED 직후 0회)

```
  0.01 approach→plant_aim | 0.82 plant_aim→recover | 2.02 recover→approach | 2.03 approach→slash_aim
  2.53 slash_aim→recover | 3.74 recover→approach | 3.75 approach→slash_aim | 4.25 slash_aim→recover
  5.46 recover→approach | 5.47 approach→slash_aim | 5.97 slash_aim→recover | 7.18 recover→approach
  7.18 approach→slash_aim | 7.68 slash_aim→recover | 8.89 recover→approach | 8.90 approach→slash_aim
  9.40 slash_aim→recover
```

**회피 켬** — 연계 시작 1 · 완주 5 · 공격 개시 5 · 살아 있던 시간 9.9초 · 회피 1회(연계 중 0회 · COMMITTED 직후 0회)

```
  0.01 approach→plant_aim | 0.82 plant_aim→recover | 2.02 recover→approach | 2.03 approach→slash_aim
  2.53 slash_aim→recover | 3.74 recover→approach | 3.75 approach→slash_aim | 4.25 slash_aim→recover
  5.46 recover→approach | 5.47 approach→slash_aim | 5.97 slash_aim→recover | 7.18 recover→approach
  7.53 **approach→회피** | 7.78 dodge→approach | 8.28 approach→slash_aim | 8.78 slash_aim→recover
```

### 균열 채굴자

**회피 끔** — 연계 시작 2 · 완주 2 · 공격 개시 6 · 살아 있던 시간 13.7초 · 회피 0회(연계 중 0회 · COMMITTED 직후 0회)

```
  0.63 approach→bite_aim | 1.07 bite_aim→recover | 2.08 recover→approach | 2.09 approach→dive
  2.49 dive→under | 3.09 under→warn | 3.79 warn→erupt | 4.17 erupt→stagger
  6.63 stagger→approach | 6.64 approach→bite_aim | 7.09 bite_aim→recover | 8.10 recover→approach
  8.35 approach→bite_aim | 8.80 bite_aim→recover | 9.81 recover→approach | 9.82 approach→bite_aim
  10.27 bite_aim→recover | 11.28 recover→approach | 11.28 approach→dive | 11.68 dive→under
  12.28 under→warn | 12.98 warn→erupt | 13.13 erupt→stagger
```

**회피 켬** — 연계 시작 2 · 완주 1 · 공격 개시 6 · 살아 있던 시간 12.6초 · 회피 1회(연계 중 0회 · COMMITTED 직후 0회)

```
  0.63 approach→bite_aim | 1.07 bite_aim→recover | 2.08 recover→approach | 2.09 approach→dive
  2.49 dive→under | 3.09 under→warn | 3.79 warn→erupt | 4.17 erupt→stagger
  6.63 stagger→approach | 6.94 **approach→회피** | 7.24 dodge→approach | 7.80 approach→bite_aim
  8.25 bite_aim→recover | 9.26 recover→approach | 9.27 approach→bite_aim | 9.72 bite_aim→recover
  10.73 recover→approach | 10.73 approach→bite_aim | 11.18 bite_aim→recover | 12.19 recover→approach
  12.20 approach→dive
```

### 정예 궁수

**회피 끔** — 연계 시작 4 · 완주 3 · 공격 개시 4 · 살아 있던 시간 12.3초 · 회피 0회(연계 중 0회 · COMMITTED 직후 0회)

```
  0.01 approach→aim | 0.59 aim→shot_lock | 0.72 shot_lock→aim | 1.10 aim→shot_lock
  1.22 shot_lock→aim | 1.61 aim→shot_lock | 1.73 shot_lock→fan_aim | 2.33 fan_aim→fan_lock
  2.48 fan_lock→recover | 3.89 recover→approach | 3.90 approach→aim | 4.48 aim→shot_lock
  4.61 shot_lock→aim | 4.99 aim→shot_lock | 5.12 shot_lock→aim | 5.50 aim→shot_lock
  5.63 shot_lock→fan_aim | 6.23 fan_aim→fan_lock | 6.38 fan_lock→recover | 7.78 recover→approach
  7.79 approach→aim | 8.38 aim→shot_lock | 8.50 shot_lock→aim | 8.88 aim→shot_lock
  9.01 shot_lock→aim | 9.39 aim→shot_lock | 9.52 shot_lock→fan_aim | 10.12 fan_aim→fan_lock
  10.27 fan_lock→recover | 11.67 recover→approach | 11.68 approach→aim | 12.27 aim→shot_lock
```

**회피 켬** — 연계 시작 4 · 완주 3 · 공격 개시 4 · 살아 있던 시간 13.0초 · 회피 1회(연계 중 0회 · COMMITTED 직후 0회)

```
  0.01 approach→aim | 0.59 aim→shot_lock | 0.72 shot_lock→aim | 1.10 aim→shot_lock
  1.22 shot_lock→aim | 1.61 aim→shot_lock | 1.73 shot_lock→fan_aim | 2.33 fan_aim→fan_lock
  2.48 fan_lock→recover | 3.89 recover→approach | 3.90 approach→aim | 4.48 aim→shot_lock
  4.61 shot_lock→aim | 4.99 aim→shot_lock | 5.12 shot_lock→aim | 5.50 aim→shot_lock
  5.63 shot_lock→fan_aim | 6.23 fan_aim→fan_lock | 6.38 fan_lock→recover | 7.78 recover→approach
  8.06 **approach→회피** | 8.28 dodge→approach | 8.68 approach→aim | 9.27 aim→shot_lock
  9.39 shot_lock→aim | 9.78 aim→shot_lock | 9.90 shot_lock→aim | 10.28 aim→shot_lock
  10.41 shot_lock→fan_aim | 11.01 fan_aim→fan_lock | 11.16 fan_lock→recover | 12.57 recover→approach
  12.57 approach→aim
```

