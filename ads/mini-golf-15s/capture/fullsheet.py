"""전체 프레임 시트: fullsheet.py <rawdir> <out.png> <wall_t...> — 각 시각에 가장 가까운 프레임을 어두운 배경에 합성"""
import sys
from PIL import Image, ImageDraw
raw, out, ts = sys.argv[1], sys.argv[2], [float(x) for x in sys.argv[3:]]
times = [float(l.split()[1]) for l in open(f"{raw}/times.txt")]
tw, th = 960, 540; cols = 2; rows = (len(ts) + 1) // 2
sheet = Image.new("RGB", (tw * cols, rows * (th + 20)), "#000"); d = ImageDraw.Draw(sheet)
for k, t in enumerate(ts):
    i = min(range(len(times)), key=lambda j: abs(times[j] - t))
    im = Image.open(f"{raw}/f{i:05d}.png"); b = Image.new("RGBA", im.size, "#1e1f22"); b.alpha_composite(im)
    r, c = divmod(k, cols); sheet.paste(b.convert("RGB").resize((tw, th)), (c * tw, r * (th + 20) + 20))
    d.text((c * tw + 6, r * (th + 20) + 4), f"f{i} t={t:.2f}", fill="#ddd")
sheet.save(out); print(out)
