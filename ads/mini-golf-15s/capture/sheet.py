"""캡처 프레임 검토용 시트: sheet.py <rawdir> <t0_wall> <t1_wall> <cx_pt> <gy_pt> <out.png> [step] [w_pt] [h_pt] [bg]
씬 좌표(pt, 좌하단 원점) 주변을 크롭해 어두운 배경에 합성, 프레임 번호·상대시간 라벨을 붙인 격자로 만든다."""
import sys, os
from PIL import Image, ImageDraw
raw, t0, t1, cx, gy, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
step = int(sys.argv[7]) if len(sys.argv) > 7 else 1
wpt = float(sys.argv[8]) if len(sys.argv) > 8 else 220
hpt = float(sys.argv[9]) if len(sys.argv) > 9 else 180
bg = sys.argv[10] if len(sys.argv) > 10 else "#1e1f22"
times = [l.split() for l in open(f"{raw}/times.txt")]
sel = [(i, float(w)) for i, (p, w) in enumerate(times) if t0 <= float(w) <= t1][::step]
first = Image.open(f"{raw}/f00000.png"); W, H = first.size; sc = W / 1920
x0 = int((cx - wpt / 2) * sc); y0 = int(H - (gy + hpt * 0.75) * sc)
cw, ch = int(wpt * sc), int(hpt * sc)
tw = 300; th = int(tw * ch / cw); cols = 6; rows = (len(sel) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), "#000")
d = ImageDraw.Draw(sheet)
for k, (i, w) in enumerate(sel):
    im = Image.open(f"{raw}/f{i:05d}.png").crop((x0, y0, x0 + cw, y0 + ch))
    base = Image.new("RGBA", im.size, bg); base.alpha_composite(im)
    r, c = divmod(k, cols)
    sheet.paste(base.convert("RGB").resize((tw, th)), (c * tw, r * (th + 18) + 18))
    d.text((c * tw + 4, r * (th + 18) + 3), f"f{i} +{w - t0:.2f}s", fill="#ccc")
sheet.save(out); print(out, len(sel), "frames")
