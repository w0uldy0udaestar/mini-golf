#!/usr/bin/env python3
"""미리보기 PNG 격자: grid.py <out.png> <cols> <tw> <png...> — 파일명(f번호)을 라벨로"""
import sys, os, re
from PIL import Image, ImageDraw, ImageFont
out, cols, tw, files = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
ims = [Image.open(f).convert("RGB") for f in files]
w0, h0 = ims[0].size; th = int(tw * h0 / w0); lab = 20
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + lab)), "#000"); d = ImageDraw.Draw(sheet)
font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 13)
for k, (f, im) in enumerate(zip(files, ims)):
    r, c = divmod(k, cols)
    sheet.paste(im.resize((tw, th), Image.LANCZOS), (c * tw, r * (th + lab) + lab))
    m = re.search(r"f(\d+)", os.path.basename(f)); fr = int(m.group(1)) if m else 0
    d.text((c * tw + 4, r * (th + lab) + 3), f"f{fr}  {fr / 30:.2f}s", fill="#ddd", font=font)
sheet.save(out); print(out, sheet.size)
