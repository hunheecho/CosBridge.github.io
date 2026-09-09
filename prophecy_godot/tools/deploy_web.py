#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""웹 시험 빌드를 **정적 호스팅용 폴더**로 만든다(배포 자체는 별도 단계).

2026-09-09 사용자 승인: "외부에서 안드로이드 크롬으로 플레이할 수 있도록 테스트용 웹 배포를 승인한다."
조건도 함께 받았다 — 이 도구는 그 조건을 그대로 구현한다:

  ① 게임 실행에 필요한 웹 산출물만 담는다. 저장소·내부 보고서·로그는 담지 않는다.
  ② 기존 사이트를 덮어쓰지 않는다 → **다른 저장소**에 올린다(이 도구는 폴더만 만든다).
  ③ 같은 주소에 패치를 반영할 수 있게 한다 → 뿌리의 index.html은 **판본을 물어보고 옮기는 로더**다.
  ④ 화면에 판본을 표시한다 → data/build.json 을 pck 안에 넣어 제목 화면이 커밋 표식을 보여 준다.
  ⑤ 이전 파일이 캐시에 남거나 새 파일과 섞이지 않게 한다 → 판마다 **b/<커밋>/** 폴더를 따로 쓴다.
     로더는 version.json 을 캐시 없이 물어보므로 로더가 캐시돼 있어도 새 판으로 간다.
  ⑥ 저장 데이터는 업데이트 뒤에도 남는다 → IndexedDB는 **출처(origin) 단위**라 경로가 바뀌어도 같다.
     (약속이므로 실제로 확인한 기록을 docs/WEB_DEPLOY.md 에 남긴다.)

만드는 모양:

    <out>/
      .nojekyll            GitHub Pages가 Jekyll로 가공하지 않게
      index.html           로더(판본을 묻고 현재 판으로 옮긴다)
      version.json         {"build","game_version","path","updated"}
      README.md            이게 무엇인지 한 문단(내부 문서가 아니다)
      b/<커밋>/            그 판의 실행 파일 한 벌(index.html/js/wasm/pck/png…)

사용:
    python tools/deploy_web.py --out ../prophecy_godot_build/deploy
    python tools/deploy_web.py --out ../prophecy_godot_build/deploy --keep 2
"""
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
PRESET = "Web"

LOADER = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>예언의 시간표 — 시험 빌드</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<style>
  html,body{margin:0;height:100%;background:#12141a;color:#d9dee8;
            font:15px/1.6 system-ui,-apple-system,"Noto Sans KR",sans-serif}
  .w{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.6rem;padding:1.5rem;text-align:center}
  h1{font-size:1.1rem;margin:0;font-weight:600}
  .s{color:#8a93a6;font-size:.85rem}
  a{color:#8ab4ff}
</style>
</head>
<body>
<div class="w">
  <h1>예언의 시간표</h1>
  <div id="m" class="s">판본을 확인하는 중…</div>
  <div id="f" class="s"></div>
</div>
<script>
// 뿌리 주소는 **로더**다. 최신 판이 어느 폴더인지 물어본 뒤 그리로 옮긴다.
// 물어보는 요청에는 캐시를 쓰지 않으므로, 이 로더 자체가 캐시에 남아 있어도 새 판으로 간다.
// 판마다 폴더가 다르므로 옛 파일과 새 파일이 섞이지 않는다.
(async function () {
  var m = document.getElementById('m');
  var f = document.getElementById('f');
  try {
    var r = await fetch('version.json?ts=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('version.json ' + r.status);
    var v = await r.json();
    m.textContent = v.game_version + ' · ' + v.build + ' 여는 중…';
    location.replace(v.path + '?v=' + encodeURIComponent(v.build));
  } catch (e) {
    m.textContent = '판본을 확인하지 못했습니다.';
    f.textContent = String(e);
  }
})();
</script>
</body>
</html>
"""

README = """# 예언의 시간표 — 웹 시험 빌드

폰(안드로이드 크롬)에서 눌러 보기 위한 **시험 빌드**만 올려 둔 곳이다.
게임 실행에 필요한 파일 한 벌 말고는 아무것도 없다 — 소스·문서·기록은 여기 없다.

- 주소를 열면 로더가 현재 판으로 옮긴다. 판마다 `b/<커밋>/` 폴더가 따로 있어 옛 파일과 섞이지 않는다.
- 지금 보고 있는 판은 **게임 제목 화면 맨 아래**에 `godot-x.y.z (커밋)` 으로 적혀 있다.
- 저장은 브라우저 안(IndexedDB)에 남는다. 판이 바뀌어도 같은 주소면 그대로다.
- 완성본이 아니다. 균형·재미는 아직 시험 중인 값이다.
"""


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


def git_short():
    r = run(["git", "rev-parse", "--short", "HEAD"], cwd=str(PROJECT))
    return (r.stdout or "").strip() or "nogit"


def git_full():
    r = run(["git", "rev-parse", "HEAD"], cwd=str(PROJECT))
    return (r.stdout or "").strip()


def game_version():
    p = PROJECT / "scripts" / "game" / "game.gd"
    for ln in p.read_text(encoding="utf-8").splitlines():
        if ln.strip().startswith("const VERSION"):
            return ln.split('"')[1]
    return "?"


def find_engine():
    env = os.environ.get("GODOT")
    if env and Path(env).exists():
        return env
    cands = [
        r"C:\Users\hunhe\OneDrive\문서\바탕 화면\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    ]
    for c in cands:
        if Path(c).exists():
            return c
    raise SystemExit("Godot 실행 파일을 찾지 못했다. 환경 변수 GODOT 로 알려 달라.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="배포용 폴더(정적 호스팅에 그대로 올릴 것)")
    ap.add_argument("--keep", type=int, default=2, help="남겨 둘 이전 판 수(기본 2 = 현재 + 직전)")
    ap.add_argument("--debug", action="store_true")
    a = ap.parse_args()

    out = Path(a.out).resolve()
    short = git_short()
    full = git_full()
    ver = game_version()
    bdir = out / "b" / short
    bdir.mkdir(parents=True, exist_ok=True)

    # ④ 화면 판본 표시: pck 안에 들어갈 표식을 잠깐 만든다(내보낸 뒤 지운다 — 소스에 남기지 않는다)
    stamp_path = PROJECT / "data" / "build.json"
    stamp = {
        "build": short,
        "commit": full,
        "game_version": ver,
        "exported_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    had_stamp = stamp_path.exists()
    if had_stamp:
        print("경고: data/build.json 이 이미 있다. 덮어쓰고 끝나면 지운다.")
    stamp_path.write_text(json.dumps(stamp, ensure_ascii=False, indent=2), encoding="utf-8")

    try:
        engine = find_engine()
        mode = "--export-debug" if a.debug else "--export-release"
        cmd = [engine, "--headless", "--path", str(PROJECT), mode, PRESET, str(bdir / "index.html")]
        print("실행: %s" % " ".join(cmd), flush=True)
        r = run(cmd)
        tail = (r.stdout or "") + (r.stderr or "")
        if r.returncode != 0 or not (bdir / "index.wasm").exists():
            print(tail[-3000:])
            return 1
        for ln in [l for l in tail.splitlines() if "ERROR" in l or "Failed" in l][:10]:
            print("  ! " + ln)
    finally:
        if stamp_path.exists():
            stamp_path.unlink()

    # **옛 판에 갇히지 않게 한다.**
    # 뿌리(index.html)는 로더라 언제나 현재 판으로 보내지만, 누가 b/<커밋>/ 주소를 그대로
    # 저장해 두면(북마크·대화방에 붙인 링크·새로고침) 로더를 거치지 않아 **영원히 그 판**이다.
    # 실제로 그렇게 됐다(2026-09-09: 친구가 고친 판을 올린 뒤에도 옛 판의 검은 화면을 계속 봤다).
    # 그래서 각 판의 index.html에 "내가 최신인가"를 묻는 짧은 검사를 심는다.
    # 게임이 시작되기 전에 한 번만 묻고, 다르면 뿌리로 보낸다. 진행 중인 회차를 끊지 않는다.
    idx = bdir / "index.html"
    if idx.exists():
        html = idx.read_text(encoding="utf-8")
        guard = """
<script>
// ---------- 오류가 나면 화면에 보이게 한다 ----------
// 폰에서 게임이 죽으면 캔버스가 **까맣게만** 남는다. 사람이 볼 수 있는 단서가 하나도 없다.
// 실제로 두 번 그랬다(2026-09-09: 봉인 임무 뒤 · 돌풍 증강 뒤).
// Godot 웹은 스크립트 오류를 console.error 로 흘리므로 그것을 가로채 화면 아래에 한 줄로 띄운다.
// 게임을 막지 않는다 — 이미 죽은 뒤에 무엇 때문인지만 보여 준다.
(function () {
  var box = null, seen = {};
  function show(msg) {
    try {
      msg = String(msg);
      if (!msg || seen[msg]) return;
      seen[msg] = 1;
      if (!box) {
        box = document.createElement('div');
        box.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:99999;max-height:42%;overflow:auto;' +
          'background:#2a1416;color:#ffb4b4;font:12px/1.5 system-ui,-apple-system,"Noto Sans KR",sans-serif;' +
          'padding:8px 10px;border-top:2px solid #b4444a;white-space:pre-wrap;word-break:break-all';
        var b = document.createElement('button');
        b.textContent = '닫기';
        b.style.cssText = 'float:right;margin-left:8px;background:#b4444a;color:#fff;border:0;border-radius:4px;padding:4px 10px;font-size:12px';
        b.onclick = function () { box.remove(); box = null; };
        box.appendChild(b);
        var t = document.createElement('div');
        t.textContent = '문제가 생겼습니다. 아래 내용을 그대로 찍어 보내 주세요:';
        t.style.cssText = 'color:#ffd9d9;margin-bottom:4px';
        box.appendChild(t);
        document.body.appendChild(box);
      }
      var line = document.createElement('div');
      line.textContent = msg.slice(0, 600);
      box.appendChild(line);
    } catch (e) {}
  }
  var ce = console.error;
  console.error = function () {
    try {
      var s = Array.prototype.slice.call(arguments).join(' ');
      // Godot 스크립트 오류만 고른다(엔진 잡음까지 띄우지 않는다)
      if (s.indexOf('SCRIPT ERROR') >= 0 || s.indexOf('USER ERROR') >= 0 || s.indexOf('Invalid') >= 0) show(s);
    } catch (e) {}
    return ce.apply(console, arguments);
  };
  window.addEventListener('error', function (e) { show((e && e.message) || 'error'); });
  window.addEventListener('unhandledrejection', function (e) {
    show('promise: ' + ((e && e.reason && (e.reason.message || e.reason)) || '?'));
  });
})();
</script>
<script>
// 이 판이 최신인지 한 번만 확인한다. 다르면 뿌리 로더로 보낸다(뿌리가 현재 판으로 옮긴다).
// 캐시를 쓰지 않고 묻는다. 실패하면 아무 일도 하지 않는다 — 게임을 막지 않는다.
(function () {
  try {
    var here = %s;
    fetch('../../version.json?ts=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (v) {
        if (v && v.build && v.build !== here) { location.replace('../../'); }
      })
      .catch(function () {});
  } catch (e) {}
})();
</script>
""" % json.dumps(short)
        if "version.json?ts=" not in html:
            html = html.replace("</body>", guard + "</body>") if "</body>" in html else html + guard
            idx.write_text(html, encoding="utf-8")
            print("판 확인 스크립트 삽입: b/%s/index.html" % short)

    files = {}
    for p in sorted(bdir.iterdir()):
        if p.is_file():
            files[p.name] = p.stat().st_size

    (out / ".nojekyll").write_text("", encoding="utf-8")
    (out / "index.html").write_text(LOADER, encoding="utf-8")
    (out / "README.md").write_text(README, encoding="utf-8")
    (out / "version.json").write_text(json.dumps({
        "build": short,
        "commit": full,
        "game_version": ver,
        "path": "b/%s/" % short,
        "updated": stamp["exported_at"],
        "files": files,
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    # ⑤ 옛 판 정리: 최신 --keep 개만 남긴다(폴더가 다르면 파일이 섞이지 않으므로 지워도 안전하다.
    #    이미 열려 있는 화면은 파일을 받아 놓았으므로 계속 돌아간다 — 강제 새로고침이 아니다)
    root = out / "b"
    kept = []
    if root.exists():
        subs = [d for d in root.iterdir() if d.is_dir()]
        subs.sort(key=lambda d: d.stat().st_mtime, reverse=True)
        kept = [d.name for d in subs[:max(1, a.keep)]]
        for d in subs[max(1, a.keep):]:
            shutil.rmtree(d, ignore_errors=True)
            print("옛 판 정리: b/%s" % d.name)

    total = sum(files.values())
    print("\n배포 폴더: %s" % out)
    for n, s in files.items():
        print("  b/%s/%-30s %10d" % (short, n, s))
    print("  %-34s %10d (%.1f MB)" % ("합계", total, total / 1048576.0))
    print("판본 표시: v%s   (빌드 %s) · 남긴 판: %s" % (ver, short, ", ".join(kept)))
    print("※ 사람에게 알릴 때는 **v%s** 로 말한다. 해시는 추적용이다 — docs/VERSIONING.md" % ver)
    print("\n확인: python tools/serve_web.py --dir %s --port 8794" % out)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
