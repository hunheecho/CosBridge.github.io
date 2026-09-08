#!/usr/bin/env python3
"""테스트 스위트 공통 실행기 (2026-09-08 고아 루프 재발 방지).

왜 있는가
---------
헤드리스 테스트가 GDScript 오류로 중단되면 `_init`이 `quit()`에 도달하지 못해
SceneTree가 종료 신호 없이 계속 돌고, 프로세스가 영원히 남는다. 그 프로세스를 기다리던
상위 루프까지 함께 멈춰 91분을 소모한 사례가 있었다(scratchpad/orphan_evidence).
원인은 필수 환경 변수(PROPHECY_LEGACY_PLACES) 누락이었고, 같은 실수가 두 스위트의
결과를 "기존 결함"으로 잘못 읽게 만들기도 했다.

이 실행기가 보장하는 것
-----------------------
1. 스위트마다 제한 시간을 적용하고, 초과하면 그 실행의 **자식 프로세스까지** 종료한다
   (다른 작업은 건드리지 않는다 — 이름이 아니라 우리가 띄운 프로세스 트리만 종료).
2. 통과 판정은 종료 코드 0만으로 하지 않는다. 정상 완료 요약("N/N PASS" 또는 "N/N 통과"),
   FAIL 0건, GDScript 오류 없음을 모두 확인한다. 실패·오류·시간초과·중단을 각각 다른
   상태와 종료 코드로 구분한다.
3. 스위트별 필수 환경 설정을 `suites.json`에서 관리한다. 빠졌으면 **실행하지 않고**
   이유를 적어 즉시 실패로 끝낸다.
4. 실행마다 고유한 로그 경로(run_id + 스위트 + 시각)를 쓴다. 덮어쓰지 않는다.
   같은 프로젝트·같은 스위트가 이미 돌고 있으면 잠금 파일로 중복 실행을 막는다.
5. 종료·취소(Ctrl+C, SIGTERM, Windows Ctrl+Break) 시 자신이 띄운 프로세스를 정리하고 잠금을 풀며,
   ABORTED.md에 중단으로 기록하고 종료 코드 130을 돌려준다. 계속 돌릴 작업이 있으면
   `--handover` 로 본 세션에 명시적으로 인계 기록을 남긴다(자동으로 남기지 않는다).
6. 시간초과가 스크립트 오류 뒤에 온 것이라면 최종 상태(timeout)와 별개로 **선행 원인**(SCRIPT ERROR와
   그 위치)을 함께 기록한다. 시간초과 숫자만 보고 원인을 "느림"으로 오해하지 않기 위해서다.

사용
----
    python tools/run_suites.py --group all
    python tools/run_suites.py --suites balance_tests,hud_tests --timeout 600
    python tools/run_suites.py --group legacy --jobs 2
    python tools/run_suites.py --self-test          # 재발 방지 고장 주입 검증(설정·오류·시간초과·중복·취소)

종료 코드: 0 전부 pass / 1 실패(FAIL·오류·요약 없음) / 2 시간초과 / 3 설정 오류(필수 env 누락·중복 실행) / 130 사용자 중단
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_DEFAULT = HERE.parent  # prophecy_godot/
MANIFEST = HERE / "suites.json"

ENGINE_CANDIDATES = [
    os.environ.get("PROPHECY_GODOT", ""),
    r"C:\Users\hunhe\OneDrive\문서\바탕 화면\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    "godot",
]

# 상태: 정상 완료 / 검사 실패 / 스크립트 오류 / 시간초과 / 설정 오류 / 중단
ST_PASS, ST_FAIL, ST_ERROR, ST_TIMEOUT, ST_CONFIG, ST_ABORTED = (
    "pass", "fail", "script_error", "timeout", "config_error", "aborted")
EXIT_FOR = {ST_PASS: 0, ST_FAIL: 1, ST_ERROR: 1, ST_TIMEOUT: 2, ST_CONFIG: 3, ST_ABORTED: 130}

_live: list[subprocess.Popen] = []   # 우리가 띄운 프로세스만
_locks: list[str] = []               # 우리가 잡은 잠금 파일만
_run_dir = None                      # 취소 기록을 남길 현재 실행 폴더(Path)
_interrupted = False


# 콘솔 기본 인코딩(cp949 등)에서도 한글 기록이 깨지거나 예외로 죽지 않게 한다
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def log(msg: str) -> None:
    print(msg, flush=True)


def find_engine() -> str:
    for c in ENGINE_CANDIDATES:
        if not c:
            continue
        if c == "godot" and shutil.which("godot"):
            return "godot"
        if Path(c).exists():
            return c
    raise SystemExit("Godot 실행 파일을 찾을 수 없다. PROPHECY_GODOT 환경 변수로 지정하라.")


def pid_alive(pid: int) -> bool:
    """그 PID가 아직 살아 있는가. Windows에서 os.kill은 프로세스를 죽이므로 쓰지 않는다."""
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes
        k = ctypes.windll.kernel32
        h = k.OpenProcess(0x1000, False, pid)   # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            return False
        code = ctypes.c_ulong()
        got = k.GetExitCodeProcess(h, ctypes.byref(code))
        k.CloseHandle(h)
        return bool(got) and code.value == 259  # STILL_ACTIVE
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def take_lock(lock_path: Path) -> tuple[bool, str]:
    """중복 실행 방지 잠금. 죽은 실행이 남긴 잠금은 회수한다.

    돌려주는 값은 (잡았는가, 설명). 강제 종료된 실행기가 남긴 잠금 하나가 그 스위트를
    영구히 막지 않도록, 잠금에 적힌 PID가 살아 있는지 확인한 뒤에만 거부한다.
    """
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in (1, 2):
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, f"{os.getpid()} {datetime.now().isoformat()}\n".encode())
            os.close(fd)
            _locks.append(str(lock_path))
            return True, ("죽은 실행이 남긴 잠금을 회수했다" if attempt == 2 else "")
        except FileExistsError:
            holder = ""
            try:
                holder = lock_path.read_text(encoding="utf-8").strip()
            except Exception:
                pass
            holder_pid = 0
            try:
                holder_pid = int(holder.split()[0])
            except Exception:
                holder_pid = 0
            if attempt == 1 and holder_pid and not pid_alive(holder_pid):
                try:
                    lock_path.unlink()
                    continue
                except Exception:
                    pass
            return False, f"같은 프로젝트의 같은 스위트가 이미 실행 중이다(잠금 {lock_path.name}, 보유 {holder})"
    return False, "잠금을 잡지 못했다"


def kill_tree(proc: subprocess.Popen) -> None:
    """우리가 띄운 프로세스와 그 자식만 종료한다. 이름으로 싹쓸이하지 않는다."""
    if proc.poll() is not None:
        return
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                           capture_output=True, timeout=30)
        else:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass
    try:
        proc.wait(timeout=15)
    except Exception:
        pass


def cleanup_all() -> None:
    """자기가 띄운 프로세스를 정리하고 자기가 잡은 잠금을 푼다(취소·종료 경로 공용)."""
    for p in list(_live):
        kill_tree(p)
    _live.clear()
    for lk in list(_locks):
        try:
            Path(lk).unlink()
        except Exception:
            pass
    _locks.clear()


def _on_signal(signum, frame):  # noqa: ARG001
    global _interrupted
    _interrupted = True
    log(f"\n[중단] 신호 {signum}을 받았다. 이 실행기가 띄운 프로세스를 정리하고 잠금을 푼다.")
    procs = [p.pid for p in _live]
    locks = [Path(l).name for l in _locks]
    cleanup_all()
    if _run_dir is not None:   # 취소도 기록으로 남긴다(통과로 세지 않는다)
        try:
            (_run_dir / "ABORTED.md").write_text(
                "# 실행 취소(aborted)\n\n"
                f"- 신호: {signum}\n- 시각: {datetime.now().isoformat()}\n"
                f"- 정리한 프로세스: {procs}\n- 해제한 잠금: {locks}\n"
                f"- 종료 코드: {EXIT_FOR[ST_ABORTED]}\n\n"
                "이 실행은 **중단**이며 통과로 세지 않는다. 잠금이 풀렸으므로 같은 스위트를 다시 실행할 수 있다.\n",
                encoding="utf-8")
        except Exception:
            pass
    sys.exit(EXIT_FOR[ST_ABORTED])


def load_manifest() -> dict:
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def check_env(spec: dict, incoming: dict) -> tuple[bool, str]:
    """필수 환경 설정 점검.

    실행기가 명세의 값을 자동으로 채워 넣는 것이 1차 예방이다(호출자가 빠뜨릴 수 없다).
    다만 호출 환경이 같은 키를 **다른 값으로 강제**했다면 조용히 덮어쓰지 않고 이유를 적어
    즉시 실패한다. 명세의 값이 비어 있는 경우도 여기서 걸린다.
    """
    problems = []
    for k, v in (spec.get("env") or {}).items():
        if not str(v):
            problems.append(f"{k}: 명세에 값이 비어 있다")
            continue
        got = incoming.get(k)
        if got is not None and got != v:
            problems.append(f"{k}는 {v} 이어야 하는데 호출 환경이 {got!r}로 강제했다")
    if problems:
        return False, "필수 환경 설정 문제: " + "; ".join(problems) + \
            (" — 이유: " + spec["env_reason"] if spec.get("env_reason") else "")
    return True, ""


def judge(rules: dict, exit_code: int, text: str) -> tuple[str, dict]:
    """종료 코드 + 로그 내용으로 상태를 정한다. 코드 0만으로 통과로 보지 않는다."""
    info: dict = {"exit_code": exit_code}
    for pat in rules.get("forbid_patterns", []):
        if re.search(pat, text):
            info["reason"] = f"금지 패턴 발견: {pat}"
            m = re.search(r"^.*" + pat + r".*$", text, re.M)
            info["evidence"] = (m.group(0).strip()[:200] if m else pat)
            return ST_ERROR, info
    fails = re.findall(rules.get("fail_line_pattern", "^FAIL "), text, re.M)
    info["fail_lines"] = len(fails)
    # 장면 실행(자동 진행)처럼 'N/N PASS' 요약이 없는 스위트는 정상 완료 표시로 판정한다.
    # 표시가 없으면 중단·시간초과이며 통과가 아니다.
    if rules.get("success_pattern"):
        m = None
        for m in re.finditer(rules["success_pattern"], text):
            pass
        if m is None:
            info["reason"] = "정상 완료 표시가 없다(중단되었거나 요구한 마지막 단계에 도달하지 못함)"
            return ST_FAIL, info
        info["success_line"] = m.group(0).strip()[:200]
        if rules.get("require_exit_zero", True) and exit_code != 0:
            info["reason"] = f"종료 코드 {exit_code}"
            return ST_FAIL, info
        if info["fail_lines"] > 0:
            info["reason"] = f"FAIL {info['fail_lines']}건"
            return ST_FAIL, info
        return ST_PASS, info
    summary = None
    for pat in rules.get("summary_patterns", []):
        m = None
        for m in re.finditer(pat, text):
            pass  # 마지막 요약을 쓴다
        if m:
            summary = (int(m.group("pass")), int(m.group("total")))
            break
    if summary is None:
        info["reason"] = "정상 완료 요약 줄이 없다(스위트가 끝까지 실행되지 않음)"
        return ST_FAIL, info
    info["passed"], info["total"] = summary
    if rules.get("require_exit_zero", True) and exit_code != 0:
        # 검사는 전부 통과했는데 프로세스가 비정상 종료한 경우를 따로 표시한다.
        # 둘은 다른 사실이다: "21/21 출력"은 검사 결과이고, "종료 코드 0"은 프로세스 정상 종료다.
        # 이 실행은 실패로 남으며, 나중에 성공한 재실행이 이 기록을 지우지 않는다.
        if info["fail_lines"] == 0 and summary[0] == summary[1]:
            info["crash_after_pass"] = True
            info["reason"] = (f"검사는 {summary[0]}/{summary[1]} 통과했으나 프로세스가 비정상 종료했다"
                              f"(종료 코드 {exit_code}"
                              + (" = 접근 위반 0xC0000005" if exit_code in (3221225477, -1073741819) else "")
                              + "). 통과로 세지 않는다")
        else:
            info["reason"] = f"종료 코드 {exit_code}"
        return ST_FAIL, info
    if info["fail_lines"] > 0:
        info["reason"] = f"FAIL {info['fail_lines']}건"
        return ST_FAIL, info
    if summary[0] != summary[1]:
        info["reason"] = f"요약 불일치 {summary[0]}/{summary[1]}"
        return ST_FAIL, info
    return ST_PASS, info


def run_one(name: str, spec: dict, rules: dict, engine: str, project: Path,
            run_dir: Path, timeout_override: int | None, base_env: dict) -> dict:
    started = time.monotonic()
    stamp = datetime.now().strftime("%H%M%S_%f")[:-3]
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", name)         # tmp/foo 같은 이름도 파일명으로 쓸 수 있게
    log_path = run_dir / f"{safe}__{stamp}.log"          # 실행마다 고유 경로(덮어쓰기 없음)
    lock_path = run_dir.parent / "locks" / f"{project.name}__{safe}.lock"
    rec = {"suite": name, "log": str(log_path), "desc": spec.get("desc", "")}
    if spec.get("verdict"):            # 스위트별 판정 규칙(장면 실행 등)은 공통 규칙 위에 덮어쓴다
        rules = dict(rules)
        rules.update(spec["verdict"])

    # --- 필수 환경 설정: 없으면 실행하지 않는다 ---
    ok, why = check_env(spec, base_env)   # 적용 전에 호출 환경과 명세가 충돌하는지 먼저 본다
    env = dict(base_env)
    env.update(spec.get("env") or {})     # 충돌이 없으면 실행기가 명세대로 채워 넣는다(예방)
    if not ok:
        rec.update(status=ST_CONFIG, reason=why, elapsed_sec=0.0)
        log_path.write_text(f"[설정 오류] {why}\n실행하지 않았다.\n", encoding="utf-8")
        return rec

    # --- 중복 실행 방지 ---
    got_lock, note = take_lock(lock_path)   # 취소 경로에서도 확실히 풀기 위해 _locks로 추적한다
    if not got_lock:
        rec.update(status=ST_CONFIG, reason=note, elapsed_sec=0.0)
        log_path.write_text(f"[중복 실행 거부] {note}\n", encoding="utf-8")
        return rec
    if note:
        rec["stale_lock_reclaimed"] = note
        log(f"  · {note}: {name}")

    # --- 사용자 저장·프로필 격리 ---
    user_dir = run_dir / f"userdata__{name}__{stamp}"
    if rules.get("isolate", True):
        user_dir.mkdir(parents=True, exist_ok=True)
        env["APPDATA"] = str(user_dir)
        env["LOCALAPPDATA"] = str(user_dir)

    # 출력 폴더를 요구하는 실행(자동 진행 캡처 등)은 실행 전용 폴더를 만들어 넣는다.
    # 실행마다 다른 경로라 이전 실행 결과를 덮어쓰지 않는다.
    out_dir = None
    if spec.get("out_dir_env"):
        out_dir = run_dir / f"out__{safe}__{stamp}"
        out_dir.mkdir(parents=True, exist_ok=True)
        env[spec["out_dir_env"]] = str(out_dir)
        rec["out_dir"] = str(out_dir)

    timeout = timeout_override or int(spec.get("timeout_sec", 900))
    if spec.get("kind") == "scene":    # 테스트 스크립트가 아니라 실제 장면을 띄우는 실행
        cmd = [engine, "--headless", "--path", str(project)] + list(spec.get("args", []))
    else:
        cmd = [engine, "--headless", "--path", str(project), "-s", f"tests/{name}.gd"]
    rec["cmd"] = " ".join(cmd)
    rec["env_applied"] = {k: v for k, v in (spec.get("env") or {}).items()}
    proc = None
    try:
        with open(log_path, "w", encoding="utf-8", errors="replace") as out:
            out.write(f"# {name}\n# cmd: {rec['cmd']}\n# env: {rec['env_applied']}\n"
                      f"# timeout: {timeout}s\n# started: {datetime.now().isoformat()}\n\n")
            out.flush()
            kw = {}
            if os.name != "nt":
                kw["preexec_fn"] = os.setsid
            proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT,
                                    env=env, cwd=str(project.parent), **kw)
            _live.append(proc)
            # 기다리는 동안 로그를 이어 읽는다.
            # GDScript 오류나 장면 적재 실패로 실행이 중단되면 quit()에 닿지 못하고 헤드리스
            # SceneTree가 최대 속도로 계속 돈다(2026-09-08 고아 루프가 그 형태였다). 그때는
            # 제한 시간까지 기다리지 않고 유예 시간 뒤 바로 종료해 스크립트 오류로 기록한다.
            abort_pats = rules.get("abort_patterns",
                                   ["SCRIPT ERROR", "Parse Error", "Compile Error", "Failed to load script"])
            grace = float(rules.get("error_grace_sec", 15))
            deadline = time.monotonic() + timeout
            scan_pos, first_err, err_seen_at = 0, None, 0.0
            timed_out, code, killed_early = False, None, None
            while True:
                code = proc.poll()
                if code is not None:
                    break
                if time.monotonic() > deadline:
                    timed_out = True
                    break
                if first_err is None:
                    try:                   # 새로 쌓인 부분만 훑는다(로그가 커도 가볍다)
                        with open(log_path, "rb") as peek:
                            peek.seek(scan_pos)
                            chunk = peek.read()
                            scan_pos += len(chunk)
                    except Exception:
                        chunk = b""
                    if chunk:
                        txt = chunk.decode("utf-8", "replace")
                        for pat in abort_pats:
                            m = re.search(r"^.*" + pat + r".*$", txt, re.M)
                            if m:
                                first_err = (pat, m.group(0).strip()[:200])
                                err_seen_at = time.monotonic()
                                break
                elif time.monotonic() - err_seen_at >= grace:
                    killed_early = first_err
                    break
                time.sleep(1.0)
    finally:
        if proc is not None:
            if proc.poll() is None:
                kill_tree(proc)          # 시간초과: 자식까지 종료
            if proc in _live:
                _live.remove(proc)
        try:
            lock_path.unlink()
        except Exception:
            pass
        if str(lock_path) in _locks:
            _locks.remove(str(lock_path))

    elapsed = time.monotonic() - started
    text = log_path.read_text(encoding="utf-8", errors="replace")
    if killed_early:
        pat, ev = killed_early
        reason = f"치명적 오류 뒤 {int(grace)}초가 지나도 스스로 끝나지 않아 프로세스 트리를 종료했다: {pat}"
        with open(log_path, "a", encoding="utf-8") as out:
            out.write(f"\n[조기 종료] {reason}\n[증거] {ev}\n"
                      "  오류로 실행이 중단되면 quit()에 닿지 못해 헤드리스 프로세스가 남는다. 통과로 세지 않는다.\n")
        rec.update(status=ST_ERROR, reason=reason, elapsed_sec=round(elapsed, 1),
                   root_cause=pat, root_cause_evidence=ev, killed_early=True)
        steps = re.findall(r"^UI_SMOKE (?:step|reached)=.*$", text, re.M)
        if steps:
            rec["last_step"] = steps[-1].strip()[:200]
        return rec
    if timed_out:
        # 시간초과 이전에 이미 GDScript 오류가 났다면 그것이 진짜 원인이다.
        # (오류로 _init이 중단되면 quit()에 도달하지 못해 프로세스가 스스로 끝나지 못한다 —
        #  2026-09-08 고아 루프가 정확히 이 형태였다.) 최종 상태는 timeout이지만 원인을 함께 남긴다.
        root, ev = None, None
        for pat in rules.get("forbid_patterns", []):
            m = re.search(r"^.*" + pat + r".*$", text, re.M)
            if m:
                root, ev = pat, m.group(0).strip()[:200]
                break
        reason = f"제한 시간 {timeout}초 초과(프로세스 트리 종료)"
        if root:
            reason += f" · 선행 원인 {root}"
            rec["root_cause"] = root
            rec["root_cause_evidence"] = ev
            # 오류 직후 백트레이스의 위치도 함께(있으면)
            at = re.search(r"^\s*at:\s*(.+)$", text[text.find(ev):], re.M) if ev else None
            if at:
                rec["root_cause_at"] = at.group(1).strip()[:160]
        with open(log_path, "a", encoding="utf-8") as out:
            out.write(f"\n[시간초과] {timeout}초를 넘겨 프로세스 트리를 종료했다. 통과로 세지 않는다.\n")
            if root:
                out.write(f"[선행 원인] {root} — {ev}\n"
                          f"  스크립트 오류로 실행이 중단됐고 quit()에 도달하지 못해 프로세스가 남았다.\n")
        rec.update(status=ST_TIMEOUT, reason=reason, elapsed_sec=round(elapsed, 1))
        # 시간초과 시점까지의 부분 진행도 남긴다(통과 판정에는 쓰지 않는다)
        rec["partial_pass_lines"] = len(re.findall(r"^PASS ", text, re.M))
        rec["partial_fail_lines"] = len(re.findall(r"^FAIL ", text, re.M))
        steps = re.findall(r"^UI_SMOKE (?:step|reached)=.*$", text, re.M)
        if steps:                       # 장면 실행이면 어디까지 갔는지(추정 아닌 기록)
            rec["last_step"] = steps[-1].strip()[:200]
        return rec

    status, info = judge(rules, code, text)
    rec.update(status=status, elapsed_sec=round(elapsed, 1), **info)
    return rec


def write_reports(run_dir: Path, run_id: str, records: list[dict], meta: dict) -> None:
    (run_dir / "summary.json").write_text(
        json.dumps({"run_id": run_id, "meta": meta, "results": records}, ensure_ascii=False, indent=2),
        encoding="utf-8")
    order = {ST_PASS: 0, ST_FAIL: 1, ST_ERROR: 2, ST_TIMEOUT: 3, ST_CONFIG: 4, ST_ABORTED: 5}
    label = {ST_PASS: "통과", ST_FAIL: "실패", ST_ERROR: "스크립트 오류",
             ST_TIMEOUT: "시간초과", ST_CONFIG: "설정 오류", ST_ABORTED: "중단"}
    lines = [f"# 테스트 실행 {run_id}", "",
             f"- 프로젝트: `{meta['project']}`", f"- 엔진: `{meta['engine']}`",
             f"- 시작: {meta['started']} · 실제 경과 {meta['elapsed_sec']}초",
             f"- 로그 폴더: `{run_dir}`", "",
             "판정 규칙: 종료 코드 0 **그리고** 정상 완료 요약(N/N) **그리고** FAIL 0건 **그리고** GDScript 오류 없음.",
             "시간초과·중단·설정 오류는 통과로 세지 않는다.", "",
             "| 스위트 | 상태 | 통과/전체 | 실제 경과(초) | 비고 |", "|---|---|---|---|---|"]
    for r in sorted(records, key=lambda x: (order.get(x["status"], 9), x["suite"])):
        cnt = f"{r.get('passed', '-')}/{r.get('total', '-')}"
        note = r.get("reason", "") or r.get("evidence", "")
        lines.append(f"| {r['suite']} | {label.get(r['status'], r['status'])} | {cnt} | "
                     f"{r.get('elapsed_sec', 0)} | {note} |")
    tally = {}
    for r in records:
        tally[r["status"]] = tally.get(r["status"], 0) + 1
    lines += ["", "집계: " + " · ".join(f"{label.get(k, k)} {v}" for k, v in sorted(tally.items()))]
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="테스트 스위트 공통 실행기")
    ap.add_argument("--suites", default="", help="쉼표로 구분한 스위트 이름")
    ap.add_argument("--group", default="", help="suites.json의 그룹 이름(all/rules/boss/ui/legacy)")
    ap.add_argument("--project", default=str(PROJECT_DEFAULT), help="prophecy_godot 경로")
    ap.add_argument("--timeout", type=int, default=0, help="스위트별 제한 시간 덮어쓰기(초)")
    ap.add_argument("--jobs", type=int, default=1, help="동시에 돌릴 스위트 수")
    ap.add_argument("--out", default="", help="로그 최상위 폴더(기본: 임시 폴더)")
    ap.add_argument("--run-id", default="", help="실행 id(기본: 시각)")
    ap.add_argument("--handover", default="", help="이 실행을 본 세션에 인계한다는 기록을 남긴다(사유)")
    ap.add_argument("--self-test", action="store_true", help="재발 방지 고장 주입 검증(설정·오류·시간초과·중복·취소)")
    ap.add_argument("--allow-adhoc", action="store_true",
                    help="명세에 없는 임시 스위트도 실행한다(자기 검증용. 필수 환경 설정은 적용되지 않으므로 정규 검증에는 쓰지 않는다)")
    args = ap.parse_args()

    signal.signal(signal.SIGINT, _on_signal)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _on_signal)
    if hasattr(signal, "SIGBREAK"):          # Windows의 Ctrl+Break(CTRL_BREAK_EVENT)
        signal.signal(signal.SIGBREAK, _on_signal)

    man = load_manifest()
    if args.self_test:
        return self_test(man, args)

    project = Path(args.project).resolve()
    names = [s for s in args.suites.split(",") if s] or man["groups"].get(args.group or "all", [])
    unknown = [n for n in names if n not in man["suites"]]
    if unknown and not args.allow_adhoc:
        log(f"[설정 오류] 명세(suites.json)에 없는 스위트: {unknown} — 필수 환경 설정을 보장할 수 없어 실행하지 않는다. "
            f"임시 실행이 목적이면 --allow-adhoc")
        return EXIT_FOR[ST_CONFIG]
    for n in unknown:  # 임시 스위트: 환경 설정 없음 + 제한 시간은 반드시 지정
        man["suites"][n] = {"env": {}, "timeout_sec": args.timeout or 60, "desc": "임시(명세 밖)"}

    run_id = args.run_id or datetime.now().strftime("%Y%m%d_%H%M%S")
    root = Path(args.out) if args.out else Path(tempfile.gettempdir()) / "prophecy_test_runs"
    run_dir = root / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    global _run_dir
    _run_dir = run_dir
    engine = find_engine()
    rules = dict(man["verdict_rules"])
    rules["isolate"] = man["defaults"].get("isolate_userdata", True)
    base_env = dict(os.environ)
    for k in ("PROPHECY_LEGACY_PLACES",):
        base_env.pop(k, None)  # 명세에 적힌 스위트만 받도록, 바깥 값이 새어 들어오지 않게 한다

    log(f"실행 {run_id} · 스위트 {len(names)}개 · 동시 {args.jobs} · 로그 {run_dir}")
    t0 = time.monotonic()
    records: list[dict] = []
    try:
        if args.jobs > 1:
            with ThreadPoolExecutor(max_workers=args.jobs) as ex:
                futs = {ex.submit(run_one, n, man["suites"][n], rules, engine, project,
                                  run_dir, args.timeout or None, base_env): n for n in names}
                for f in as_completed(futs):
                    r = f.result()
                    records.append(r)
                    log(f"  {r['suite']}: {r['status']} ({r.get('elapsed_sec', 0)}s) {r.get('reason', '')}")
        else:
            for n in names:
                r = run_one(n, man["suites"][n], rules, engine, project, run_dir,
                            args.timeout or None, base_env)
                records.append(r)
                log(f"  {r['suite']}: {r['status']} ({r.get('elapsed_sec', 0)}s) {r.get('reason', '')}")
    finally:
        cleanup_all()

    elapsed = round(time.monotonic() - t0, 1)
    meta = {"project": str(project), "engine": engine, "started": datetime.now().isoformat(),
            "elapsed_sec": elapsed, "jobs": args.jobs}
    if args.handover:
        meta["handover"] = args.handover
        (run_dir / "HANDOVER.txt").write_text(
            f"이 실행을 본 세션에 인계한다.\n사유: {args.handover}\n실행 id: {run_id}\n"
            f"로그: {run_dir}\n남긴 시각: {datetime.now().isoformat()}\n", encoding="utf-8")
    write_reports(run_dir, run_id, records, meta)
    worst = ST_PASS
    for r in records:
        if EXIT_FOR[r["status"]] > EXIT_FOR[worst]:
            worst = r["status"]
    log(f"\n요약: {run_dir / 'summary.md'} · 최종 상태 {worst}")
    return EXIT_FOR[worst]


# ---------------------------------------------------------------- 자기 검증
def _count_godot(project_hint: str) -> int:
    """그 프로젝트를 대상으로 도는 Godot 프로세스 수(검증용 관찰. 종료하지는 않는다).
    문자열 매칭은 PowerShell 안에서 끝내 콘솔 줄바꿈 때문에 놓치는 일이 없게 한다."""
    try:
        if os.name == "nt":
            ps = ("$h = $env:PROPHECY_COUNT_HINT; "
                  "(Get-CimInstance Win32_Process -Filter \"Name like 'Godot%'\" | "
                  "Where-Object { $_.CommandLine -and $_.CommandLine.Contains($h) } | "
                  "Measure-Object).Count")
            env = dict(os.environ, PROPHECY_COUNT_HINT=project_hint)
            out = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                                 capture_output=True, text=True, timeout=30, env=env).stdout
            return int((out or "0").strip() or 0)
        out = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True, timeout=30).stdout or ""
        return sum(1 for line in out.splitlines() if project_hint in line)
    except Exception:
        return -1


def self_test(man: dict, args) -> int:
    """재발 방지 4종 고장 주입: 필수 설정 누락 / 스크립트 오류 / 강제 시간초과 / 중복 실행.
    각 경우에 실행기가 멈춰 기다리지 않고, 프로세스를 정리하고, 실패·중단으로 기록하는지 확인한다."""
    project = Path(args.project).resolve()
    engine = find_engine()
    run_id = "selftest_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    root = Path(args.out) if args.out else Path(tempfile.gettempdir()) / "prophecy_test_runs"
    run_dir = root / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    tmp_tests = project / "tests" / "tmp"
    tmp_tests.mkdir(parents=True, exist_ok=True)
    rules = dict(man["verdict_rules"])
    rules["isolate"] = True
    base_env = {k: v for k, v in os.environ.items() if k != "PROPHECY_LEGACY_PLACES"}
    results = []

    def case(title, expect, spec, name, timeout=None, pre=None):
        t0 = time.monotonic()
        if pre:
            pre()
        r = run_one(name, spec, rules, engine, project, run_dir, timeout, base_env)
        took = round(time.monotonic() - t0, 1)
        good = r["status"] == expect
        results.append({"case": title, "expected": expect, "got": r["status"],
                        "ok": good, "wall_sec": took, "reason": r.get("reason", ""),
                        "log": r["log"]})
        log(f"  [{'OK' if good else '문제'}] {title}: 기대 {expect} → 실제 {r['status']} ({took}초) {r.get('reason','')}")
        return r

    log(f"자기 검증 {run_id} · 로그 {run_dir}")
    # 1) 필수 설정 충돌: 호출 환경이 PROPHECY_LEGACY_PLACES를 다른 값으로 강제한 경우.
    #    평소에는 실행기가 명세대로 자동 적용하므로 "빠뜨릴" 수 없다 — 그것이 1차 예방이다.
    conflict_env = dict(base_env)
    conflict_env["PROPHECY_LEGACY_PLACES"] = "0"
    t0c = time.monotonic()
    rc = run_one("content_tests", man["suites"]["content_tests"], rules, engine, project,
                 run_dir, 60, conflict_env)
    okc = rc["status"] == ST_CONFIG
    results.append({"case": "필수 설정 충돌(PROPHECY_LEGACY_PLACES=0 강제)", "expected": ST_CONFIG,
                    "got": rc["status"], "ok": okc, "wall_sec": round(time.monotonic() - t0c, 1),
                    "reason": rc.get("reason", ""), "log": rc["log"]})
    log(f"  [{'OK' if okc else '문제'}] 필수 설정 충돌: 기대 {ST_CONFIG} → 실제 {rc['status']} {rc.get('reason', '')}")
    # 1b) 예방이 실제로 동작하는지: 같은 스위트를 그대로 실행하면 실행기가 값을 채워 통과해야 한다
    t0d = time.monotonic()
    rd_ = run_one("content_tests", man["suites"]["content_tests"], rules, engine, project,
                  run_dir, 600, base_env)
    okd = rd_["status"] == ST_PASS and rd_.get("env_applied", {}).get("PROPHECY_LEGACY_PLACES") == "1"
    results.append({"case": "필수 설정 자동 적용(같은 스위트를 그대로 실행)", "expected": ST_PASS,
                    "got": rd_["status"], "ok": okd, "wall_sec": round(time.monotonic() - t0d, 1),
                    "reason": rd_.get("reason", "") or f"env {rd_.get('env_applied')}", "log": rd_["log"]})
    log(f"  [{'OK' if okd else '문제'}] 필수 설정 자동 적용: 기대 {ST_PASS} → 실제 {rd_['status']}")

    # 2) 스크립트 오류: 일부러 없는 키를 읽고 quit()에 도달하지 못하는 테스트
    err = tmp_tests / "selftest_error.gd"
    err.write_text(
        "extends SceneTree\n"
        "## 자기 검증용: GDScript 오류로 _init이 중단되어 quit()에 도달하지 못하는 상황을 만든다\n"
        "func _init() -> void:\n"
        "\tprint(\"PASS 시작은 한다\")\n"
        "\tvar d := {}\n"
        "\tprint(d.no_such_key)\n"
        "\tquit(0)\n", encoding="utf-8")
    # 제한 시간(180초)을 기다리지 않고, 오류 유예 시간 뒤 바로 끝나는 것까지 확인한다
    case("스크립트 오류(quit 미도달) 조기 종료", ST_ERROR,
         {"env": {}, "timeout_sec": 180, "desc": "self test"}, "tmp/selftest_error", timeout=180)

    # 3) 강제 시간초과: 끝나지 않는 루프
    slow = tmp_tests / "selftest_hang.gd"
    slow.write_text(
        "extends SceneTree\n"
        "## 자기 검증용: 절대 끝나지 않는 헤드리스 실행\n"
        "func _process(_d: float) -> bool:\n"
        "\treturn false\n", encoding="utf-8")
    case("강제 시간초과(끝나지 않는 실행)", ST_TIMEOUT,
         {"env": {}, "timeout_sec": 20, "desc": "self test"}, "tmp/selftest_hang", timeout=20)

    # 4) 중복 실행: 잠금을 미리 잡아 둔 상태에서 같은 스위트 실행
    lock = run_dir.parent / "locks" / f"{project.name}__run_tests.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.write_text("selftest holder\n", encoding="utf-8")
    try:
        case("중복 실행 시도(잠금 보유 중)", ST_CONFIG,
             man["suites"]["run_tests"], "run_tests", timeout=60)
    finally:
        try:
            lock.unlink()
        except Exception:
            pass
    # 5) 실행 중 취소: 자식이 남지 않고, 잠금이 풀리고, aborted/130으로 기록되고, 재실행이 되는가
    cancel_src = tmp_tests / "selftest_cancel.gd"
    cancel_src.write_text(
        "extends SceneTree\n"
        "## 자기 검증용: 취소 신호를 받을 때까지 끝나지 않는 실행\n"
        "func _process(_d: float) -> bool:\n"
        "\treturn false\n", encoding="utf-8")
    cancel_dir = run_dir / "cancel_case"
    t0x = time.monotonic()
    child_cmd = [sys.executable, str(Path(__file__).resolve()), "--suites", "tmp/selftest_cancel",
                 "--timeout", "300", "--out", str(cancel_dir), "--run-id", "cancelled",
                 "--project", str(project), "--allow-adhoc"]
    kw = {}
    if os.name == "nt":
        kw["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kw["preexec_fn"] = os.setsid
    child = subprocess.Popen(child_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env=dict(base_env, PYTHONIOENCODING="utf-8"),
                             text=True, encoding="utf-8", errors="replace", **kw)
    lock_file = cancel_dir / "locks" / f"{project.name}__tmp_selftest_cancel.lock"
    lock_seen = False
    for _ in range(160):
        time.sleep(0.25)
        if lock_file.exists():
            lock_seen = True
            break
    time.sleep(2.5)
    godot_before = _count_godot(str(project))
    if os.name == "nt":
        child.send_signal(signal.CTRL_BREAK_EVENT)
    else:
        child.send_signal(signal.SIGINT)
    try:
        child.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        child.kill()
    code = child.returncode
    time.sleep(2.5)
    godot_after = _count_godot(str(project))
    aborted_md = cancel_dir / "cancelled" / "ABORTED.md"
    lock_released = not lock_file.exists()
    okx = (code == EXIT_FOR[ST_ABORTED] and lock_seen and lock_released
           and godot_after < godot_before and aborted_md.exists())
    detail = (f"종료코드 {code}(기대 {EXIT_FOR[ST_ABORTED]}) · 잠금 생성 {lock_seen}/해제 {lock_released} · "
              f"대상 Godot {godot_before}→{godot_after} · 취소 기록 {aborted_md.exists()}")
    results.append({"case": "실행 중 취소(Ctrl+Break)", "expected": "aborted/130", "got": f"code={code}",
                    "ok": okx, "wall_sec": round(time.monotonic() - t0x, 1), "reason": detail,
                    "log": str(aborted_md)})
    log(f"  [{'OK' if okx else '문제'}] 실행 중 취소: {detail}")
    # 5b) 취소 뒤 같은 스위트를 다시 실행할 수 있는가(남은 잠금이 막지 않는가)
    t0y = time.monotonic()
    ry = run_one("tmp/selftest_cancel", {"env": {}, "timeout_sec": 15, "desc": "self test"},
                 rules, engine, project, run_dir, 15, base_env)
    oky = ry["status"] == ST_TIMEOUT
    results.append({"case": "취소 뒤 같은 스위트 재실행", "expected": "timeout(재실행 가능)",
                    "got": ry["status"], "ok": oky, "wall_sec": round(time.monotonic() - t0y, 1),
                    "reason": ry.get("reason", ""), "log": ry["log"]})
    log(f"  [{'OK' if oky else '문제'}] 취소 뒤 재실행: {ry['status']}")
    try:
        cancel_src.unlink()
        u = cancel_src.with_suffix(".gd.uid")
        if u.exists():
            u.unlink()
    except Exception:
        pass

    for f in (err, slow):
        try:
            f.unlink()
            uid = f.with_suffix(".gd.uid")
            if uid.exists():
                uid.unlink()
        except Exception:
            pass
    cleanup_all()

    (run_dir / "selftest.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# 실행기 자기 검증(재발 방지 4종)", "",
             "각 경우에 실행기가 멈춰 기다리지 않고, 프로세스를 정리하고, 통과가 아닌 상태로 기록하는지 확인한다.", "",
             "| 고장 주입 | 기대 상태 | 실제 상태 | 실제 경과(초) | 판정 | 비고 |", "|---|---|---|---|---|---|"]
    for r in results:
        lines.append(f"| {r['case']} | {r['expected']} | {r['got']} | {r['wall_sec']} | "
                     f"{'OK' if r['ok'] else '문제'} | {r['reason']} |")
    ok_all = all(r["ok"] for r in results)
    lines += ["", f"결과: {'4/4 확인' if ok_all else '문제 있음'} · 모든 경우가 통과(pass)로 기록되지 않았는지 함께 확인했다."]
    (run_dir / "selftest.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    log(f"\n자기 검증 요약: {run_dir / 'selftest.md'}")
    return 0 if ok_all else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        cleanup_all()
