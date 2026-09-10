#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""검사 목록과 **실제 파일**을 대조한다 — 돌리기 전에.

왜 이 파일이 있는가 (2026-09-10 사용자 지시)
---------------------------------------------
"실제 검사 파일과 등록 목록을 대조해 미등록·중복·대상 파일 없음이 **실행 전에** 검출되게 한다.
 제외 항목은 파일 이름이 아니라 내용과 제외 사유로 구분한다."

그전까지 이런 것들이 조용히 새고 있었다:
  · `--group all` 에 **진짜 검사 다섯**이 빠져 있었다
    (bank_tests · bank_ui_tests · equip_combat_tests · equip_ui_tests · enemy_pace_tests).
    "전체 검사 57종 통과"라고 보고한 실행이 그것들을 건너뛰고 있었다.
  · `tests/review_tests.gd`(35단언)가 **명세에 아예 없었다.**
  · `duel_card_tests` 가 all 그룹에 **두 번** 들어 있어 매 실행마다 한 번 더 돌았다.
  · `frame_path_audit` 는 `script` 키가 없어 있지도 않은 `tests/frame_path_audit.gd` 를 가리켰다.

무엇을 보는가
  ① 중복      한 그룹 안에 같은 이름이 두 번
  ② 대상 없음  명세가 가리키는 스크립트 파일이 실제로 없다
  ③ 미등록    tests/ 에 파일이 있는데 명세에 없다
  ④ 사유 없음  최종 실행 대상(all)에서 빠졌는데 all_exclusions 에 사유가 없다
  ⑤ 유령 사유  all_exclusions 에 적혀 있는데 명세에 없는 이름

③④는 **이름 규칙으로 봐주지 않는다.** `_probe` 로 끝난다고 자동으로 빼지 않는다 —
이름은 언제든 바뀌고, 이름만 보고 빼면 진짜 검사가 조용히 빠진다(위가 그 사례다).
빼려면 all_exclusions 에 **내용과 사유를 적어야** 한다.

사용:
    python tools/check_suites.py            # 문제가 있으면 종료 코드 1
    python tools/check_suites.py --quiet    # 문제가 있을 때만 출력
"""
import argparse
import json
import os
import sys
from collections import Counter
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent


def target_of(name, spec):
    """그 스위트가 실제로 돌리는 것. (종류, 경로) — 화면 스위트는 경로가 없다."""
    if spec.get("kind") == "scene":
        return ("scene", None)
    return ("script", spec.get("script") or ("tests/%s.gd" % name))


def check():
    spec_path = PROJECT / "tools" / "suites.json"
    doc = json.loads(spec_path.read_text(encoding="utf-8"))
    suites = doc.get("suites", {})
    groups = doc.get("groups", {})
    ex = doc.get("all_exclusions", {})

    problems = []

    # ① 중복
    for gname, members in groups.items():
        dup = [k for k, v in Counter(members).items() if v > 1]
        for d in dup:
            problems.append("중복: 그룹 '%s' 에 '%s' 가 %d번 들어 있다" % (gname, d, Counter(members)[d]))
        for m in members:
            if m not in suites:
                problems.append("유령 항목: 그룹 '%s' 의 '%s' 가 명세에 없다" % (gname, m))

    # ② 대상 파일 없음
    for name, spec in suites.items():
        kind, rel = target_of(name, spec)
        if kind == "script" and not (PROJECT / rel).exists():
            problems.append("대상 없음: '%s' 가 가리키는 %s 가 없다" % (name, rel))

    # ③ 미등록 — tests/ 의 파일이 명세에 있는가
    excused_files = set()
    nas = ex.get("not_a_suite", {})
    for f in nas.get("files", []):
        excused_files.add(f.replace("\\", "/"))
    tests_dir = PROJECT / "tests"
    for f in sorted(os.listdir(tests_dir)):
        if not f.endswith(".gd"):
            continue
        rel = "tests/" + f
        if rel in excused_files:
            continue
        stem = f[:-3]
        # 이름이 같은 항목이 있거나, 어떤 항목이 이 파일을 script 로 가리키면 등록된 것이다
        registered = stem in suites or any(
            (s.get("script") or "").replace("\\", "/") == rel for s in suites.values())
        if not registered:
            problems.append(
                "미등록: %s 가 명세에 없다 — 등록하거나, 스위트가 아니라면 "
                "all_exclusions.not_a_suite.files 에 사유와 함께 적어라" % rel)

    # ④⑤ 최종 실행 대상에서 빠진 것의 사유
    all_members = set(groups.get("all", []))
    reasoned = {}
    for key, blk in ex.items():
        if not isinstance(blk, dict):
            continue
        for s in blk.get("suites", []):
            reasoned[s] = key
    outside = set(suites) - all_members
    for s in sorted(outside):
        if s not in reasoned:
            problems.append(
                "사유 없음: '%s' 가 최종 실행 대상(all)에서 빠졌는데 all_exclusions 에 사유가 없다" % s)
    for s in sorted(reasoned):
        if s not in suites:
            problems.append("유령 사유: all_exclusions 의 '%s' 가 명세에 없다" % s)
        elif s in all_members:
            problems.append(
                "모순: '%s' 는 all 에 들어 있는데 all_exclusions(%s)에도 적혀 있다" % (s, reasoned[s]))

    return doc, suites, groups, outside, reasoned, problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="문제가 있을 때만 적는다")
    a = ap.parse_args()

    doc, suites, groups, outside, reasoned, problems = check()

    if not a.quiet or problems:
        print("검사 명세 대조 — 스위트 %d개 · 최종 실행 대상(all) %d개 · 뺀 것 %d개"
              % (len(suites), len(groups.get("all", [])), len(outside)))
        by_reason = {}
        for s, key in reasoned.items():
            by_reason.setdefault(key, []).append(s)
        for key in sorted(by_reason):
            blk = doc.get("all_exclusions", {}).get(key, {})
            print("  [%s] %d개 — %s" % (key, len(by_reason[key]), (blk.get("why") or "")[:80]))

    if problems:
        print()
        print("**문제 %d건 — 돌리기 전에 고쳐라**" % len(problems))
        for p in problems:
            print("  · " + p)
        return 1
    if not a.quiet:
        print("문제 없음.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
