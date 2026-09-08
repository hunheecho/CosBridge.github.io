#!/usr/bin/env python3
"""웹 빌드 내보내기 한 줄 명령 + 빌드 표식(version.json) 만들기.

왜 있는가
---------
1. 내보내기 명령에 빠뜨리면 안 되는 것들이 있다 — 내보내기 템플릿은 **진짜 AppData**에 있어야
   하므로 이 단계만 APPDATA 격리를 풀어야 하고(테스트 실행기는 반대로 항상 격리한다),
   글꼴이 없으면 브라우저에서 한글이 전부 네모로 나온다(docs/WEB_BUILD.md §2).
2. 갱신 흐름에 쓸 **빌드 표식**이 필요하다. 브라우저는 옛 index.wasm을 캐시에 들고 있을 수 있어서,
   지금 돌고 있는 빌드가 어떤 것인지 스스로 알 방법이 있어야 한다. 산출물 옆에 version.json을 둔다.

version.json (배포 폴더 루트)
    {"build": "<커밋 짧은 해시>", "game_version": "godot-0.7.0", "exported_at": "<UTC ISO>", "files": {...}}

쓰는 법(브라우저 쪽)은 docs/WEB_BUILD.md §5. 요약: 이 파일만 캐시하지 않고 주기적으로 받아
`build`가 지금 켜 둔 것과 다르면 "새 판이 있다"고만 알리고, **새로고침은 전투가 아닌 화면 전환 때**
사람이 누르게 한다. 전투 중에 강제로 새로고침하지 않는다.

사용
----
    python tools/export_web.py                       # ../prophecy_godot_build/web 로
    python tools/export_web.py --out <폴더>
    python tools/export_web.py --debug               # 디버그 템플릿(오류 메시지가 자세하다)
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
DEFAULT_OUT = PROJECT.parent / "prophecy_godot_build" / "web"
PRESET = "Web"
FONT = PROJECT / "assets" / "fonts" / "ui.ttf"

ENGINE_CANDIDATES = [
    os.environ.get("PROPHECY_GODOT", ""),
    r"C:\Users\hunhe\OneDrive\문서\바탕 화면\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    "godot",
]

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def find_engine() -> str:
    for c in ENGINE_CANDIDATES:
        if not c:
            continue
        if c == "godot" and shutil.which("godot"):
            return "godot"
        if Path(c).exists():
            return c
    raise SystemExit("Godot 실행 파일을 찾을 수 없다. PROPHECY_GODOT 환경 변수로 지정하라.")


def git_short() -> str:
    try:
        out = subprocess.run(["git", "-C", str(PROJECT), "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=20)
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def game_version() -> str:
    """scripts/game/game.gd의 VERSION 상수(정본은 그 파일이다)."""
    t = (PROJECT / "scripts" / "game" / "game.gd").read_text(encoding="utf-8")
    for line in t.splitlines():
        if line.startswith("const VERSION"):
            return line.split('"')[1]
    return "unknown"


def main() -> int:
    ap = argparse.ArgumentParser(description="웹 빌드 내보내기 + 빌드 표식")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--debug", action="store_true", help="디버그 템플릿으로 내보낸다")
    a = ap.parse_args()

    out_dir = Path(a.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if not FONT.exists():
        print("경고: %s 가 없다. 브라우저에서 한글이 전부 네모(□)로 나온다." % FONT)
        print("      docs/WEB_BUILD.md §2 를 보고 글꼴을 먼저 넣어라.")

    engine = find_engine()
    mode = "--export-debug" if a.debug else "--export-release"
    cmd = [engine, "--headless", "--path", str(PROJECT), mode, PRESET, str(out_dir / "index.html")]
    print("실행: %s" % " ".join(cmd), flush=True)

    # 내보내기 템플릿은 진짜 AppData에 있어야 한다 → 이 실행만 격리하지 않는다.
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    tail = (r.stdout or "") + (r.stderr or "")
    bad = [ln for ln in tail.splitlines() if "ERROR" in ln or "Failed" in ln]
    if r.returncode != 0 or not (out_dir / "index.wasm").exists():
        print(tail[-4000:])
        print("내보내기 실패(코드 %d)" % r.returncode)
        return 1
    for ln in bad[:10]:
        print("  ! " + ln)

    files = {}
    for p in sorted(out_dir.iterdir()):
        if p.is_file() and p.name != "version.json":
            files[p.name] = p.stat().st_size

    stamp = {
        "build": git_short(),
        "game_version": game_version(),
        "exported_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "debug": bool(a.debug),
        "files": files,
    }
    (out_dir / "version.json").write_text(json.dumps(stamp, ensure_ascii=False, indent=2), encoding="utf-8")

    total = sum(files.values())
    print("\n산출물: %s" % out_dir)
    for n, s in files.items():
        print("  %-34s %10d" % (n, s))
    print("  %-34s %10d (%.1f MB)" % ("합계", total, total / 1048576.0))
    print("빌드 표식: build=%s game_version=%s" % (stamp["build"], stamp["game_version"]))
    print("\n확인: python tools/serve_web.py  →  http://127.0.0.1:8765/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
