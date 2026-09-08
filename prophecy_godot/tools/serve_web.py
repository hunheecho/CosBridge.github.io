#!/usr/bin/env python3
"""웹 내보내기 결과를 **이 PC 안에서만** 띄워 보는 정적 서버.

왜 있는가
---------
브라우저는 `file://`로 연 페이지에서 `fetch`를 막으므로 index.html을 두 번 눌러서는
게임이 뜨지 않는다. 또 파이썬 기본 `http.server`는 `.wasm`의 MIME 형식을 모를 때가 있어
`WebAssembly.instantiateStreaming`이 실패하고 느린 대체 경로로 떨어진다. 이 스크립트는
그 두 가지만 해결한다.

**외부에 공개하지 않는다**: 기본 바인딩 주소가 127.0.0.1이라 같은 PC에서만 열린다.
휴대폰으로 볼 때만 `--host 0.0.0.0`을 직접 붙여라(같은 공유기 안, 임시 확인용).

사용
----
    python tools/serve_web.py                       # ../prophecy_godot_build/web 를 8765 포트로
    python tools/serve_web.py --dir <폴더> --port 8080
    python tools/serve_web.py --host 0.0.0.0        # 같은 공유기의 폰에서 볼 때만
    python tools/serve_web.py --coi                 # COOP/COEP 헤더도 붙인다(스레드 빌드일 때만 필요)

스레드 없는(nothreads) 빌드는 COOP/COEP 헤더가 **필요 없다**. `--coi`는 나중에
`variant/thread_support=true`로 내보낼 때를 위한 것이다.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import socket
import socketserver
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_DIR = HERE.parent.parent / "prophecy_godot_build" / "web"

# 브라우저가 알아야 하는 형식(파이썬 기본 표에 없거나 틀리게 잡히는 것만)
EXTRA_TYPES = {
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".js": "text/javascript",
    ".json": "application/json",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    coi = False  # 교차 출처 격리 헤더를 붙일지

    def guess_type(self, path):  # noqa: A003 (표준 이름)
        ext = Path(str(path)).suffix.lower()
        if ext in EXTRA_TYPES:
            return EXTRA_TYPES[ext]
        return super().guess_type(path)

    def end_headers(self):
        # 시험 중에는 옛 빌드가 캐시에 남아 헷갈리지 않게 매번 새로 받는다
        self.send_header("Cache-Control", "no-store")
        if self.coi:
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def log_message(self, fmt, *args):
        print("  %s" % (fmt % args), flush=True)


class Server(socketserver.ThreadingTCPServer):
    # Windows에서 SO_REUSEADDR는 리눅스와 뜻이 다르다: 이미 그 포트를 듣고 있는 프로세스가 있어도
    # **두 번째 바인딩이 성공**해 버리고, 요청이 둘 중 아무 쪽에나 간다(옛 빌드가 섞여 나온다).
    # 그래서 켜지 않는다 — 포트가 이미 쓰이면 조용히 겹치지 말고 오류로 알려야 한다.
    allow_reuse_address = (os.name != "nt")
    daemon_threads = True


def lan_ip() -> str:
    """같은 공유기의 폰이 칠 주소(추정). 알 수 없으면 빈 문자열."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # 실제로 보내지 않는다(경로 확인용)
        return s.getsockname()[0]
    except OSError:
        return ""
    finally:
        s.close()


def main() -> int:
    ap = argparse.ArgumentParser(description="웹 빌드 로컬 확인용 정적 서버")
    ap.add_argument("--dir", default=str(DEFAULT_DIR), help="띄울 폴더(기본: prophecy_godot_build/web)")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1", help="기본은 이 PC 전용. 폰에서 볼 때만 0.0.0.0")
    ap.add_argument("--coi", action="store_true", help="COOP/COEP 헤더 추가(스레드 빌드 전용)")
    a = ap.parse_args()

    root = Path(a.dir).resolve()
    if not (root / "index.html").exists():
        print("index.html이 없다: %s" % root)
        print("먼저 내보내라: godot --headless --path prophecy_godot --export-release \"Web\" "
              "prophecy_godot_build/web/index.html")
        return 1

    Handler.coi = a.coi
    handler = functools.partial(Handler, directory=str(root))
    with Server((a.host, a.port), handler) as httpd:
        print("폴더: %s" % root)
        print("주소: http://127.0.0.1:%d/" % a.port)
        if a.host == "0.0.0.0":
            ip = lan_ip()
            if ip:
                print("폰(같은 공유기): http://%s:%d/" % (ip, a.port))
            print("주의: 같은 공유기 안에만 열린다. 확인이 끝나면 Ctrl+C로 꺼라.")
        print("멈추려면 Ctrl+C", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n중지")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
