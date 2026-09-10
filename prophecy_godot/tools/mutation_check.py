#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""보호 장치를 **일부러 빼 보고** 검사가 실제로 잡는지 확인한다 — **격리된 사본에서만**.

왜 이 도구가 있는가 (2026-09-10 사용자 지시)
--------------------------------------------
"보호 기능을 일부러 빼는 검사는 격리된 코드 사본에서 해야 해. 실제 작업본에서 제거했다가
복구하는 방식은 이번처럼 중단되면 위험해. 검사가 끊겨도 실제 작업본의 저장 보호는 계속 살아 있어야 해."

실제로 그런 일이 있었다. 저장 보호 관문이 정말 작동하는지 보려고 **작업본에서 그 줄을 지우고**
검사를 돌렸는데, 그 명령이 배경으로 넘어갔다가 복구 단계 **전에** 끊겼다.
그래서 한동안 보호가 빠진 작업본이 남아 있었다.

이 도구는 그 방식을 없앤다. 작업본은 **읽기만** 한다:
  1) 프로젝트를 임시 폴더로 통째 복사한다(작업본은 손대지 않는다)
  2) 복사본에서 지정한 줄을 지운다
  3) 복사본에서 검사를 돌린다
  4) 결과를 적고 복사본을 지운다
중간에 끊겨도 작업본은 처음부터 끝까지 그대로다.

사용:
    python tools/mutation_check.py --file scripts/rules/save.gd \\
        --remove-contains "저장 정리를 건너뛴다" \\
        --test tests/save_repair_tests.gd \\
        --expect-fail "자료를 못 읽으면"

  --remove-contains  그 글자가 든 줄과 이어지는 들여쓰기 블록을 지운다(여러 번 줄 수 있다)
  --expect-fail      그 글자가 든 단언이 **실패해야** 성공이다(여러 번 줄 수 있다)
                     하나도 주지 않으면 "검사 전체가 실패해야 한다"로 본다
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent

# 복사할 때 건너뛸 것(무겁고 검사에 필요 없다)
SKIP = {".godot", ".git", "clips", "docs", ".import"}


def godot_exe() -> str:
    env = os.environ.get("PROPHECY_GODOT", "")
    if env:
        return env
    guess = (
        r"C:\Users\hunhe\OneDrive\문서\바탕 화면"
        r"\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
    )
    return guess


def copy_project(dst: Path) -> None:
    def ignore(_dir, names):
        return [n for n in names if n in SKIP]

    shutil.copytree(PROJECT, dst, ignore=ignore)


def strip_block(text: str, needle: str) -> tuple[str, int]:
    """needle이 든 줄부터, 그 줄보다 깊거나 같은 들여쓰기가 이어지는 동안 지운다."""
    lines = text.split("\n")
    out = []
    i = 0
    removed = 0
    while i < len(lines):
        if needle in lines[i]:
            indent = len(lines[i]) - len(lines[i].lstrip("\t "))
            i += 1
            removed += 1
            # 이어지는 더 깊은 줄(블록 본문)도 함께 지운다
            while i < len(lines):
                nxt = lines[i]
                if nxt.strip() == "":
                    i += 1
                    removed += 1
                    continue
                nxt_indent = len(nxt) - len(nxt.lstrip("\t "))
                if nxt_indent > indent:
                    i += 1
                    removed += 1
                    continue
                break
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out), removed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True, help="복사본에서 고칠 파일(프로젝트 상대 경로)")
    ap.add_argument("--remove-contains", action="append", required=True,
                    help="이 글자가 든 줄과 그 블록을 지운다")
    ap.add_argument("--test", required=True, help="돌릴 검사 스크립트(프로젝트 상대 경로)")
    ap.add_argument("--expect-fail", action="append", default=[],
                    help="이 글자가 든 단언이 실패해야 한다")
    ap.add_argument("--keep", action="store_true", help="복사본을 지우지 않는다(들여다볼 때)")
    a = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="mutation_"))
    dst = tmp / "proj"
    ok = False
    try:
        copy_project(dst)
        target = dst / a.file
        if not target.exists():
            print("고칠 파일이 복사본에 없다:", target)
            return 2
        raw = target.read_bytes().decode("utf-8")
        nl = "\r\n" if "\r\n" in raw else "\n"
        body = raw.replace("\r\n", "\n")
        total = 0
        for needle in a.remove_contains:
            body, n = strip_block(body, needle)
            if n == 0:
                print("지울 줄을 못 찾았다(보호가 이미 없는 것일 수 있다):", needle)
                return 2
            total += n
        target.write_bytes(body.replace("\n", nl).encode("utf-8"))
        print("복사본에서 %d줄을 지웠다 → %s" % (total, a.file))

        subprocess.run([godot_exe(), "--headless", "--path", str(dst), "--import"],
                       capture_output=True, timeout=600)
        r = subprocess.run([godot_exe(), "--headless", "--path", str(dst), "-s", a.test],
                           capture_output=True, timeout=900)
        out = r.stdout.decode("utf-8", "replace")
        fails = [l for l in out.split("\n") if l.startswith("FAIL ")]
        print("복사본 검사 결과: 실패 %d줄" % len(fails))
        for l in fails[:10]:
            print("  " + l.strip())

        if a.expect_fail:
            missing = [n for n in a.expect_fail
                       if not any(n in l for l in fails)]
            ok = not missing
            if missing:
                print("**보호를 뺐는데도 잡히지 않은 단언**:", missing)
                print("→ 그 검사는 보호가 없어도 통과한다. 검사가 실제 결함을 못 잡는다는 뜻이다.")
            else:
                print("→ 보호를 빼자 기대한 단언이 전부 실패했다. 검사가 실제로 그 결함을 잡는다.")
        else:
            ok = len(fails) > 0
            print("→ 실패가 %s" % ("생겼다(검사가 잡는다)" if ok else "없다(검사가 못 잡는다)"))
        print("작업본은 손대지 않았다:", PROJECT)
        return 0 if ok else 1
    finally:
        if a.keep:
            print("복사본을 남긴다:", dst)
        else:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
