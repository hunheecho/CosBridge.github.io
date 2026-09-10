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
  1) 프로젝트를 임시 폴더로 복사한다(작업본은 손대지 않는다)
  2) 복사본에서 지정한 줄을 지운다
  3) 복사본에서 검사를 돌린다
  4) 결과를 적고 복사본을 지운다
중간에 끊겨도 작업본은 처음부터 끝까지 그대로다.

2026-09-10 보강(사용자 지시) — 말로 적지 않고 **도구가 스스로 확인한다**:
  ① 실행 **전에** 대상 경로를 확인한다. 사본의 저장 자리가 **실제 사용자 저장 위치**와 겹치거나
     격리 표시(userdata__ / prophecy_test_runs)가 없으면 **사본도 만들지 않고 중단**한다(종료 2).
     사람의 저장 폴더는 경로만 계산해 피한다 — 열지도 읽지도 않는다.
  ② 코드 위치뿐 아니라 **저장 위치도 격리**한다(APPDATA·LOCALAPPDATA를 사본 전용 폴더로).
  ③ 실행 **전후로 작업본 전체의 해시를 떠서 대조**한다. 검사가 중단되든 시간을 넘기든
     이 대조는 반드시 돈다(finally). 한 파일이라도 달라지면 결과와 상관없이 **실패**로 끝낸다(종료 3).

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
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# 이 창의 기본 글자표(cp949)로는 못 적는 글자가 있어 출력을 UTF-8로 돌린다.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent

# 통째 복사(--full)일 때 건너뛸 것. **.godot(가져오기 캐시)은 빼지 않는다** —
# 빼면 복사본에서 전체 재가져오기가 걸려 검사가 시간 초과로 끝나지 못한다(실제로 900초를 넘겼다).
SKIP = {".git", "clips", "docs"}

# 기본값은 **작은 격리 사본**이다(2026-09-10 사용자 지시:
# "다음에는 필요한 파일만 담은 작은 격리 사본으로 확인하는 게 좋겠어").
# 통째 복사는 37MB에 가져오기 캐시까지 끌고 와 두 번이나 900초를 넘겼다.
# 여기 담는 것만으로 규칙 검사(tests/*.gd, -s 로 직접 실행)가 돈다:
#   project.godot   설정·자동 적재 두 개(scripts/game/game.gd, audio.gd)
#   scripts/        규칙과 화면 전부
#   data/           자료(자료가 비면 PCatalog.data_ready() 가 거짓이 되어 검사 뜻이 바뀐다)
#   assets/fonts/   gui/theme/custom_font 가 가리키는 글꼴(없으면 적재 오류가 섞인다)
#   icon.svg        config/icon
#   tests/<지정한 검사 하나>
# 그림(assets/icons, 약 6MB)과 clips 는 규칙 검사가 건드리지 않아 뺀다.
MINIMAL_DIRS = ["scripts", "data", "assets/fonts"]
MINIMAL_FILES = ["project.godot", "icon.svg", "icon.svg.import"]


def godot_exe() -> str:
    env = os.environ.get("PROPHECY_GODOT", "")
    if env:
        return env
    guess = (
        r"C:\Users\hunhe\OneDrive\문서\바탕 화면"
        r"\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
    )
    return guess


# ---------------------------------------------------------------------------
# 안전 장치 셋 (2026-09-10 사용자 지시)
#   ① 실행 전 대상 경로를 확인하고, **실제 사용자 저장 위치**를 가리키면 실행 자체를 중단한다
#   ② 고장 주입 사본의 코드 위치뿐 아니라 **저장 위치도 격리**한다(그리고 그것을 확인한다)
#   ③ 중단·시간 초과 뒤에도 실제 작업본의 보호가 살아 있어야 하므로,
#      **작업본을 절대 쓰지 않는다는 것을 도구가 스스로 확인한다**(실행 전후 해시 대조)
# ---------------------------------------------------------------------------

# 해시 대조에서 뺄 것. .git 은 우리 소관이 아니고, .godot 은 엔진이 스스로 갱신하는 캐시라
# "우리가 건드렸다"의 증거가 되지 못한다(사본을 만들 때 읽기만 해도 잠금 파일이 움직인다).
HASH_SKIP_DIRS = {".git", ".godot", "clips"}


def project_app_name() -> str:
    """project.godot 의 application/config/name. user:// 폴더 이름이 이 값이다."""
    try:
        txt = (PROJECT / "project.godot").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    m = re.search(r'^config/name\s*=\s*"(.*)"\s*$', txt, re.MULTILINE)
    return m.group(1) if m else ""


def real_user_save_dir() -> Path:
    """**사람이 실제로 쓰는** 저장 폴더. 여기는 읽지도 쓰지도 않는다 — 경로만 계산해 피한다."""
    name = project_app_name()
    if os.name == "nt":
        base = os.environ.get("APPDATA", "")
        if not base:
            return Path("")
        return Path(base) / "Godot" / "app_userdata" / name
    home = Path.home()
    return home / ".local" / "share" / "godot" / "app_userdata" / name


def _inside(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except (ValueError, OSError):
        return False


def guard_paths(dst: Path, user_dir: Path) -> str:
    """실행 전 확인. 위험하면 사유 한 줄을 돌려준다(빈 문자열이면 안전)."""
    real = real_user_save_dir()
    if str(real) and (_inside(user_dir, real) or _inside(real, user_dir) or
                      user_dir.resolve() == real.resolve()):
        return ("사본의 저장 자리가 **실제 사용자 저장 위치**와 겹친다 — 실행하지 않는다\n"
                "  사본 저장 자리: %s\n  사람 저장 자리: %s" % (user_dir, real))
    marker = str(user_dir).replace("\\", "/")
    if "userdata__" not in marker and "prophecy_test_runs" not in marker:
        return ("사본의 저장 자리에 격리 표시(userdata__ / prophecy_test_runs)가 없다 — "
                "이 상태로 보호를 빼고 돌리면 규칙 계층의 관문도 막지 못한다: %s" % user_dir)
    if _inside(dst, PROJECT) or dst.resolve() == PROJECT.resolve():
        return "고장 주입 사본이 작업본 안에 있다 — 실행하지 않는다: %s" % dst
    return ""


def hash_tree(root: Path) -> dict:
    """작업본 전체의 파일별 해시. '작업본을 안 건드렸다'를 값으로 확인하는 데 쓴다."""
    out = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if any(part in HASH_SKIP_DIRS for part in rel.parts):
            continue
        if not path.is_file():
            continue
        h = hashlib.sha256()
        try:
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
        except OSError as e:
            out[str(rel)] = "읽기 실패: %s" % e
            continue
        out[str(rel)] = h.hexdigest()
    return out


def diff_tree(before: dict, after: dict) -> list:
    changed = []
    for k in sorted(set(before) | set(after)):
        b = before.get(k)
        a = after.get(k)
        if b != a:
            changed.append("%s (%s → %s)" % (k, "없음" if b is None else b[:12],
                                             "없음" if a is None else a[:12]))
    return changed


def copy_project(dst: Path) -> None:
    """통째 복사 — 가져오기 캐시까지 들고 간다. 느리다(--full 일 때만)."""
    def ignore(_dir, names):
        return [n for n in names if n in SKIP]

    shutil.copytree(PROJECT, dst, ignore=ignore)


def copy_minimal(dst: Path, tests: list) -> int:
    """필요한 것만 담은 작은 사본을 만든다. 옮긴 파일 수를 돌려준다."""
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for rel in MINIMAL_DIRS:
        src = PROJECT / rel
        if not src.exists():
            continue
        shutil.copytree(src, dst / rel)
        n += sum(1 for _ in (dst / rel).rglob("*") if _.is_file())
    for rel in MINIMAL_FILES:
        src = PROJECT / rel
        if src.exists():
            (dst / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst / rel)
            n += 1
    (dst / "tests").mkdir(exist_ok=True)
    for t in tests:
        src = PROJECT / t
        if not src.exists():
            raise SystemExit("검사 파일이 없다: %s" % src)
        shutil.copy2(src, dst / t)
        n += 1
    # 검사 하나가 **다른 검사 파일을 별개의 프로세스로 띄우는** 경우가 있다
    # (tests/save_guard_tests.gd → tests/save_guard_probe.gd). 그 몸통이 없으면
    # 사본에서 "보호가 없어서 실패"가 아니라 "파일이 없어서 실패"가 되어 결과를 잘못 읽는다.
    # tests/*.gd 는 전부 합쳐도 작으므로 통째로 들고 간다.
    for src2 in sorted((PROJECT / "tests").glob("*.gd")):
        dst2 = dst / "tests" / src2.name
        if not dst2.exists():
            shutil.copy2(src2, dst2)
            n += 1
    for src3 in sorted((PROJECT / "tests").glob("*.uid")):
        dst3 = dst / "tests" / src3.name
        if not dst3.exists():
            shutil.copy2(src3, dst3)
            n += 1
    return n


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
    ap.add_argument("--run-timeout", type=int, default=180,
                    help="복사본 검사 제한 시간(초). 보호를 빼면 검사가 **끝나지 못하는** 경우가 있다")
    ap.add_argument("--full", action="store_true",
                    help="통째 복사(느리다). 기본은 필요한 파일만 담은 작은 사본")
    a = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="mutation_"))
    dst = tmp / "proj"
    # ② 사본의 저장 자리. 이름에 격리 표시(userdata__)를 넣어 규칙 계층의 관문도 통과시킨다
    user_dir = tmp / "userdata__mutation"
    # ① **실행 전** 확인. 위험하면 사본도 만들지 않고 그 자리에서 멈춘다
    why_stop = guard_paths(dst, user_dir)
    if why_stop:
        print("실행 중단 —", why_stop)
        shutil.rmtree(tmp, ignore_errors=True)
        return 2
    print("실행 전 확인 통과 — 사본 저장 자리 %s" % user_dir)
    print("  사람의 저장 자리(계산만 하고 **읽지도 쓰지도 않는다**): %s" % real_user_save_dir())
    # ③ 작업본을 정말 안 건드리는지 스스로 확인한다(실행 전 해시)
    before_hash = hash_tree(PROJECT)
    print("작업본 해시를 떴다 — 파일 %d개(실행이 끝나면 다시 떠서 대조한다)" % len(before_hash))
    ok = False
    try:
        if a.full:
            copy_project(dst)
            print("통째 사본을 만들었다(느린 길) → %s" % dst)
        else:
            n_files = copy_minimal(dst, [a.test])
            print("작은 격리 사본을 만들었다 — 파일 %d개 → %s" % (n_files, dst))
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

        # **사본 실행도 저장 자리를 격리한다.**
        # 이 도구는 보호 장치를 빼고 돌린다. 격리하지 않으면 보호가 빠진 사본이
        # 사람의 실제 저장 폴더(APPDATA\Godot\app_userdata)를 그대로 본다 —
        # 검사한다면서 사고를 내는 꼴이다. 공용 실행기(run_suites.py)와 같은 방식으로 막는다.
        # 위 guard_paths()가 실행 전에 이 자리가 사람의 저장 자리와 겹치지 않는지 이미 확인했다.
        user_dir.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        env["APPDATA"] = str(user_dir)
        env["LOCALAPPDATA"] = str(user_dir)
        print("사본의 저장 자리를 격리했다 → %s" % user_dir)

        subprocess.run([godot_exe(), "--headless", "--path", str(dst), "--import"],
                       capture_output=True, timeout=900, env=env)
        timed_out = False
        out = ""
        rc = -1
        log = dst / "_mutation_out.txt"
        with open(log, "wb") as f:
            proc = subprocess.Popen([godot_exe(), "--headless", "--path", str(dst), "-s", a.test],
                                    stdout=f, stderr=subprocess.STDOUT, env=env)
            t0 = time.time()
            while time.time() - t0 < a.run_timeout and proc.poll() is None:
                time.sleep(1)
            if proc.poll() is None:
                # **보호를 빼면 검사가 끝나지 못하는 일이 실제로 있다.**
                # 검사가 죽은 자리에서 quit() 에 닿지 못하면 SceneTree 가 계속 돈다.
                # 그것도 "보호가 없으면 이 검사는 통과하지 못한다"는 증거이므로 결과로 적는다.
                timed_out = True
                proc.kill()
            else:
                rc = int(proc.returncode)
        out = log.read_text(encoding="utf-8", errors="replace")

        lines = out.split(chr(10))
        fails = [l for l in lines if l.startswith("FAIL ")]
        passes = [l for l in lines if l.startswith("PASS ")]
        errors = [l for l in lines if l.startswith("SCRIPT ERROR")]
        # **검사가 실제로 돌았는지 먼저 본다.** 사본이 아예 못 서면 실패도 0줄이라
        # "보호가 없어도 통과한다"로 잘못 읽힌다.
        if not passes and not fails and not errors:
            print("복사본에서 검사가 한 줄도 못 돌았다 — 이 결과로는 아무것도 말할 수 없다")
            print(out[-2000:])
            return 2
        print("복사본 검사 결과: 통과 %d줄 · 실패 %d줄 · 스크립트 오류 %d줄 · %s"
              % (len(passes), len(fails), len(errors),
                 ("%d초 안에 끝나지 못했다" % a.run_timeout) if timed_out else ("종료 코드 %d" % rc)))
        for l in fails[:10]:
            print("  실패: " + l.strip())
        for l in errors[:6]:
            print("  오류: " + l.strip())

        # 보호를 뺐을 때 **검사가 통과하지 않는** 길은 셋이다. 셋 다 증거로 인정하되
        # 어느 길이었는지 구분해서 적는다 — "단언이 잡았다"와 "죽어서 못 끝났다"는 다르다.
        why = []
        if a.expect_fail:
            hit = [n for n in a.expect_fail if any(n in l for l in fails)]
            if hit:
                why.append("기대한 단언이 실패했다: %s" % hit)
        if errors:
            why.append("스크립트 오류가 났다(%d줄)" % len(errors))
        if timed_out:
            why.append("검사가 끝나지 못했다(%d초 초과)" % a.run_timeout)
        if not why and fails:
            why.append("다른 단언이 실패했다(%d줄)" % len(fails))
        ok = bool(why)
        if ok:
            print("→ 보호를 빼자 검사가 통과하지 못했다 — " + " / ".join(why))
            if a.expect_fail:
                missed = [n for n in a.expect_fail if not any(n in l for l in fails)]
                if missed:
                    print("  다만 이 단언들은 **실패로 잡히지 않았다**(그 앞에서 멈췄을 수 있다): %s" % missed)
        else:
            print("→ 보호를 뺐는데도 검사가 그대로 통과했다. 검사가 실제 결함을 못 잡는다는 뜻이다.")
        return 0 if ok else 1
    finally:
        # ③ **중단·시간 초과로 여기 왔더라도** 반드시 대조한다.
        #    "작업본은 손대지 않았다"를 말로 적지 않고 값으로 확인한다.
        after_hash = hash_tree(PROJECT)
        changed = diff_tree(before_hash, after_hash)
        if a.keep:
            print("복사본을 남긴다:", dst)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
        if changed:
            print("작업본이 바뀌었다 — 이 도구가 건드리지 말아야 할 것을 건드렸다:")
            for c in changed[:20]:
                print("  · " + c)
            print("→ 결과와 상관없이 **실패**로 끝낸다(작업본 보호가 이 도구의 첫째 계약이다).")
            return 3  # 위의 return/예외보다 이 값이 이긴다 — 일부러 그렇게 둔다
        print("작업본 대조: 파일 %d개가 실행 전후로 **한 바이트도 달라지지 않았다** — %s"
              % (len(after_hash), PROJECT))


if __name__ == "__main__":
    raise SystemExit(main())
