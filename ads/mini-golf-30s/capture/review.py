#!/usr/bin/env python3
"""캡처 검토 시트: review.py <rawdir> <out.png> <t0> <t1> [--step N] [--box x0,y0,x1,y1(pt)] [--cols 6] [--tw 320]
스트림 시작(times.txt 첫 pts) 기준 t0~t1초 프레임을 어두운 배경에 합성해 격자로. 라벨 = 프레임 번호 · 상대 초."""
import argparse
from PIL import Image, ImageDraw, ImageFont
ap = argparse.ArgumentParser()
ap.add_argument("raw"); ap.add_argument("out"); ap.add_argument("t0", type=float); ap.add_argument("t1", type=float)
ap.add_argument("--step", type=int, default=3); ap.add_argument("--box", default="0,0,1920,1080")
ap.add_argument("--cols", type=int, default=6); ap.add_argument("--tw", type=int, default=320)
a = ap.parse_args()
ts = [float(l.split()[0]) for l in open(f"{a.raw}/times.txt")]
sel = [i for i, t in enumerate(ts) if a.t0 <= t <= a.t1][:: a.step]
x0, y0, x1, y1 = [float(v) for v in a.box.split(",")]
bx = tuple(int(v * 2) for v in (x0, y0, x1, y1))
tw = a.tw; th = int(tw * (bx[3] - bx[1]) / (bx[2] - bx[0])); rows = (len(sel) + a.cols - 1) // a.cols
sheet = Image.new("RGB", (a.cols * tw, rows * (th + 16)), "#000"); d = ImageDraw.Draw(sheet)
font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 11)
for k, i in enumerate(sel):
    im = Image.open(f"{a.raw}/f{i:05d}.png").convert("RGBA").crop(bx)
    b = Image.new("RGBA", im.size, "#1e1f22"); b.alpha_composite(im)
    r, c = divmod(k, a.cols)
    sheet.paste(b.convert("RGB").resize((tw, th), Image.LANCZOS), (c * tw, r * (th + 16) + 16))
    d.text((c * tw + 3, r * (th + 16) + 2), f"f{i} {ts[i]:.2f}s", fill="#ccc", font=font)
sheet.save(a.out); print(a.out, len(sel), "frames", sheet.size)
