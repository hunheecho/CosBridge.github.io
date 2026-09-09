#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""찍은 영상 클립을 **실제로 열어** 확인한다.

왜 필요한가. "파일이 만들어졌다"와 "재생하면 그 장면이 보인다"는 다른 말이다.
2026-09-09 지시: "대표 영상은 파일을 만든 뒤 실제 재생해서 확인한다.
검은 화면·잘린 화면·잘못된 속도·효과 누락을 확인하지 않은 영상을 검증 완료로 세지 마라."

이 PC에는 ffmpeg이 없다. 대신 Godot의 Movie Maker가 쓰는 **MJPEG AVI**를 직접 뜯는다:
RIFF/AVI 컨테이너의 `movi` 목록 안에 프레임마다 JPEG 하나가 그대로 들어 있으므로,
청크를 훑어 JPEG을 꺼내 PIL로 연다. 즉 **디코더가 실제로 그림을 만들어 낸 것**을 본다.

확인하는 것
  1) 열리는가        — 프레임 JPEG이 실제로 디코딩되는가(깨진 파일이면 여기서 걸린다)
  2) 길이·속도       — 프레임 수 / AVI 헤더의 초당 프레임 수 = 실제 길이. 지정한 초와 맞는가
  3) 잘림            — 모든 프레임 크기가 같고 헤더의 가로·세로와 같은가
  4) 검은 화면       — 프레임 평균 밝기와 '거의 검은' 프레임 비율
  5) 정지 화면       — 이웃 프레임 사이 평균 차이(0이면 그림이 안 움직인 것)
  6) 눈으로 볼 표본   — --save 로 지정한 수만큼 고르게 뽑아 PNG로 저장한다(사람/에이전트가 본다)

사용:
  python tools/clip_check.py docs/captures/1.0.0_clips/mon_new.avi --expect-sec 5 --save 4 --out <폴더>
  python tools/clip_check.py docs/captures/1.0.0_clips --expect-sec 0   (폴더 전체 요약)
"""
import argparse
import io
import json
import os
import struct
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL(Pillow)이 필요하다: python -m pip install pillow")
    raise SystemExit(2)


def _chunks(buf, start, end):
    """RIFF 청크를 (fourcc, 자료시작, 자료끝)으로 훑는다. 홀수 길이는 1바이트 패딩이 붙는다."""
    i = start
    while i + 8 <= end:
        cc = buf[i:i + 4]
        (sz,) = struct.unpack("<I", buf[i + 4:i + 8])
        d0 = i + 8
        d1 = min(d0 + sz, end)
        yield cc, d0, d1
        i = d1 + (sz & 1)


def read_avi(path):
    """AVI에서 (가로, 세로, 초당프레임, [JPEG 바이트...])를 꺼낸다."""
    with open(path, "rb") as f:
        buf = f.read()
    if buf[0:4] != b"RIFF" or buf[8:12] != b"AVI ":
        raise ValueError("AVI(RIFF) 파일이 아니다: %s" % path)
    w = h = 0
    fps = 0.0
    frames = []

    def walk(start, end):
        nonlocal w, h, fps
        for cc, d0, d1 in _chunks(buf, start, end):
            if cc == b"LIST":
                kind = buf[d0:d0 + 4]
                if kind == b"movi":
                    for c2, e0, e1 in _chunks(buf, d0 + 4, d1):
                        # 00dc = 압축 영상 프레임. rec 묶음 안에 들어 있기도 하다
                        if c2 == b"LIST" and buf[e0:e0 + 4] == b"rec ":
                            for c3, g0, g1 in _chunks(buf, e0 + 4, e1):
                                if c3[2:4] in (b"dc", b"db"):
                                    frames.append(buf[g0:g1])
                        elif c2[2:4] in (b"dc", b"db"):
                            frames.append(buf[e0:e1])
                else:
                    walk(d0 + 4, d1)
            elif cc == b"avih":
                # dwMicroSecPerFrame, ..., dwWidth(32), dwHeight(36)
                (usec,) = struct.unpack("<I", buf[d0:d0 + 4])
                if usec > 0:
                    fps = 1000000.0 / usec
                w, h = struct.unpack("<II", buf[d0 + 32:d0 + 40])

    walk(12, len(buf))
    return w, h, fps, frames


def check(path, expect_sec=0.0, save_n=0, out_dir="", stride=1, preroll=12):
    w, h, fps, raw = read_avi(path)
    n = len(raw)
    if n == 0:
        return {"파일": os.path.basename(path), "판정": "실패", "이유": "프레임이 하나도 없다"}

    sizes = set()
    lum = []
    prev = None
    diffs = []
    black = 0
    idx = list(range(0, n, max(1, stride)))
    for i in idx:
        try:
            im = Image.open(io.BytesIO(raw[i])).convert("L")
        except Exception as e:  # 디코딩 실패 = 재생 불가
            return {"파일": os.path.basename(path), "판정": "실패",
                    "이유": "%d번째 프레임을 디코딩하지 못했다: %s" % (i, e)}
        sizes.add(im.size)
        small = im.resize((64, 36))
        px = list(small.tobytes())
        m = sum(px) / float(len(px))
        lum.append(m)
        if m < 4.0:
            black += 1
        if prev is not None:
            diffs.append(sum(abs(a - b) for a, b in zip(px, prev)) / float(len(px)))
        prev = px

    saved = []
    if save_n > 0 and out_dir:
        os.makedirs(out_dir, exist_ok=True)
        base = os.path.splitext(os.path.basename(path))[0]
        picks = [round(k * (n - 1) / float(max(1, save_n - 1))) for k in range(save_n)]
        for k, i in enumerate(picks):
            im = Image.open(io.BytesIO(raw[i])).convert("RGB")
            p = os.path.join(out_dir, "%s_f%04d.png" % (base, i))
            im.save(p)
            saved.append(p)

    sec = (n / fps) if fps > 0 else 0.0
    black_rate = black / float(len(lum))
    still = (max(diffs) if diffs else 0.0) < 0.5
    bad = []
    if len(sizes) != 1:
        bad.append("프레임 크기가 섞여 있다: %s" % sorted(sizes))
    elif (w, h) != tuple(next(iter(sizes))):
        bad.append("헤더 크기 %dx%d 와 실제 프레임 %s 가 다르다(잘림)" % (w, h, next(iter(sizes))))
    if black_rate > 0.2:
        bad.append("거의 검은 프레임이 %.0f%%" % (black_rate * 100.0))
    if still:
        bad.append("그림이 움직이지 않는다(이웃 프레임 차이 최대 %.2f)" % (max(diffs) if diffs else 0.0))
    want = expect_sec + (preroll / fps if fps > 0 else 0.0)
    if expect_sec > 0 and abs(sec - want) > max(0.25, want * 0.05):
        bad.append("길이 %.2f초 ≠ 기대 %.2f초(지정 %.2f + 앞머리 %d프레임). 속도가 어긋났다"
                   % (sec, want, expect_sec, preroll))

    return {
        "파일": os.path.basename(path),
        "판정": "통과" if not bad else "확인 필요",
        "문제": bad,
        "프레임": n,
        "초당프레임": round(fps, 2),
        "길이초": round(sec, 2),
        "크기": "%dx%d" % (w, h),
        "평균밝기": round(sum(lum) / len(lum), 1),
        "최소밝기": round(min(lum), 1),
        "검은프레임비율": round(black_rate, 3),
        "움직임(이웃 프레임 평균차)": round(sum(diffs) / len(diffs), 2) if diffs else 0.0,
        "앞머리프레임": preroll,
        "저장한표본": saved,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help=".avi 파일 또는 폴더")
    ap.add_argument("--expect-sec", type=float, default=0.0, help="지정한 길이(초). 0이면 길이 검사 생략")
    ap.add_argument("--save", type=int, default=0, help="눈으로 볼 표본 프레임 수")
    ap.add_argument("--out", default="", help="표본 PNG를 저장할 폴더")
    ap.add_argument("--stride", type=int, default=1, help="몇 프레임마다 검사할지(1=전부)")
    ap.add_argument("--preroll", type=int, default=12,
                    help="장면이 시작되기 전 앞머리 프레임 수. main.gd가 창·배치가 잡히도록 12프레임을 흘려보내므로 "
                         "파일은 지정한 길이보다 그만큼 길다. 길이 검사가 이 값을 더해서 본다")
    a = ap.parse_args()

    targets = []
    if os.path.isdir(a.path):
        targets = [os.path.join(a.path, n) for n in sorted(os.listdir(a.path)) if n.lower().endswith(".avi")]
    else:
        targets = [a.path]
    if not targets:
        print("검사할 .avi 가 없다")
        return 1

    out = []
    for t in targets:
        try:
            r = check(t, a.expect_sec, a.save, a.out, a.stride, a.preroll)
        except Exception as e:
            r = {"파일": os.path.basename(t), "판정": "실패", "이유": str(e)}
        out.append(r)
        print(json.dumps(r, ensure_ascii=False))
    bad = [r for r in out if r.get("판정") != "통과"]
    print("\n요약: %d개 중 통과 %d · 확인 필요/실패 %d" % (len(out), len(out) - len(bad), len(bad)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
