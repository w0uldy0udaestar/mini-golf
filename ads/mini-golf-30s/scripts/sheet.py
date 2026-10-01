#!/usr/bin/env python3
"""콘택트 시트: sheet.py <mp4> <out.png> [--frames f1,f2,...] [--cols N] [--width W] [--only]
기본: 1fps 30장(각 초의 0.5초 지점 = f15, f45 …) + --frames 로 준 키프레임. 프레임 번호·초 라벨을 붙인다."""
import argparse, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
ap = argparse.ArgumentParser(); ap.add_argument("mp4"); ap.add_argument("out")
ap.add_argument("--frames", default=""); ap.add_argument("--cols", type=int, default=6); ap.add_argument("--width", type=int, default=320)
ap.add_argument("--only", action="store_true", help="--frames 만 (1fps 생략)")
a = ap.parse_args()
cap = cv2.VideoCapture(a.mp4); fr = []
while True:
    ok, im = cap.read()
    if not ok: break
    fr.append(im)
n_sec = len(fr) // 30
want = ([] if a.only else [15 + 30 * i for i in range(n_sec)]) + [int(x) for x in a.frames.split(",") if x]
want = [w for w in want if w < len(fr)]
h0, w0 = fr[0].shape[:2]; W = a.width; H = int(W * h0 / w0); LAB = 20
rows = (len(want) + a.cols - 1) // a.cols
sheet = Image.new("RGB", (a.cols * W, rows * (H + LAB)), "#000"); d = ImageDraw.Draw(sheet)
font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
for k, f in enumerate(want):
    im = Image.fromarray(cv2.cvtColor(fr[f], cv2.COLOR_BGR2RGB)).resize((W, H), Image.LANCZOS)
    r, c = divmod(k, a.cols); sheet.paste(im, (c * W, r * (H + LAB) + LAB))
    d.text((c * W + 4, r * (H + LAB) + 4), f"f{f}  {f / 30:.2f}s" + ("  *key" if k >= (0 if a.only else n_sec) else ""), fill="#ddd", font=font)
sheet.save(a.out); print(a.out, len(want), "frames", sheet.size)
