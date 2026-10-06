#!/usr/bin/env python3
"""콘택트 시트: sheet.py <mp4> <out.png> [--frames f1,f2,...] [--cols N] [--width W] [--only]
기본: 1fps(각 초의 0.5초 지점) + --frames 키프레임. 프레임 번호·초 라벨, 스레드 안전 영역(x 70–930, y 300–1620) 점선 상자."""
import argparse, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
ap = argparse.ArgumentParser(); ap.add_argument("mp4"); ap.add_argument("out")
ap.add_argument("--frames", default=""); ap.add_argument("--cols", type=int, default=7); ap.add_argument("--width", type=int, default=300)
ap.add_argument("--only", action="store_true"); ap.add_argument("--labels", default="")
a = ap.parse_args()
cap = cv2.VideoCapture(a.mp4); fr = []
while True:
    ok, im = cap.read()
    if not ok: break
    fr.append(im)
want = ([] if a.only else [15 + 30 * i for i in range(len(fr) // 30 + 1)]) + [int(x) for x in a.frames.split(",") if x]
want = [w for w in want if w < len(fr)]
labs = a.labels.split("|") if a.labels else []
h0, w0 = fr[0].shape[:2]; W = a.width; H = int(W * h0 / w0); LAB = 22
rows = (len(want) + a.cols - 1) // a.cols
sheet = Image.new("RGB", (a.cols * W, rows * (H + LAB)), "#000"); d = ImageDraw.Draw(sheet)
font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 12)
sx = W / w0
for k, f in enumerate(want):
    im = Image.fromarray(cv2.cvtColor(fr[f], cv2.COLOR_BGR2RGB)).resize((W, H), Image.LANCZOS)
    r, c = divmod(k, a.cols); x0, y0 = c * W, r * (H + LAB) + LAB
    sheet.paste(im, (x0, y0))
    for (xa, ya, xb, yb) in [(70, 300, 930, 300), (70, 1620, 930, 1620), (70, 300, 70, 1620), (930, 300, 930, 1620)]:
        d.line((x0 + xa * sx, y0 + ya * sx, x0 + xb * sx, y0 + yb * sx), fill="#1f5f3a", width=1)
    lab = labs[k] if k < len(labs) and labs[k] else ""
    d.text((x0 + 4, r * (H + LAB) + 4), f"f{f} {f / 30:.2f}s {lab}", fill="#ddd", font=font)
sheet.save(a.out); print(a.out, len(want), "frames")
