"""리그 벡터 렌더 교정: 실캡처 프레임 위에 리그로 그린 스틱맨을 겹쳐(빨강) 어긋남을 본다."""
import gzip, json, math, re, numpy as np
from PIL import Image, ImageDraw
CAP = "../../dist/cap/ad"
G = json.loads(open('data/ground.js').read()[len('window.GROUND='):-2])
rig = []
for l in gzip.open(f"{CAP}/logs/hero-drive.rig.gz", "rt"):
    p = l.split(); kv = dict(zip(p[13::2], p[14::2]))
    rig.append((float(p[1][4:-1]), [tuple(map(float, q.split(","))) for q in p[3:13]], tuple(map(float, kv["head"].split(","))), float(kv["phi"]), float(kv["len"]), int(kv["curved"])))
sync = json.load(open('data/sync.json'))
stick = [(float(m.group(1)), int(m.group(2))) for m in (re.search(r"STICK\[([\d.]+)\] (\d+)", l) for l in open(f"{CAP}/logs/hero-drive.log")) if m]
times = [float(l.split()[1]) for l in open(f"{CAP}/logs/hero-drive.times.txt")]
def pose(w):
    st = w - sync["offset"]; i = min(range(len(rig)), key=lambda k: abs(rig[k][0] - st)); return rig[i]
def draw(fidx, name, out, dt=0.0):
    w = times[fidx] + dt
    _, pts, head, phi, ln, curved = pose(w)
    x = float(np.interp(w, [s[0] for s in stick], [s[1] for s in stick]))
    g = G[int(round(x))] + 0.6
    S = 4
    im = Image.open(f"{CAP}/{name}.png").convert("RGBA")
    ov = Image.new("RGBA", (3840 * 1, 2160 * 1), (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    T = lambda p: ((x + p[0]) * 2, (g - p[1]) * 2)
    hip, sh, f1, f2, k1, k2, grip, ht, el, et = [T(p) for p in pts]
    col = (255, 40, 40, 150)
    for seg in [(sh, hip), (hip, k1, f1), (hip, k2, f2), (sh, el, grip), (sh, et, ht)]:
        d.line(seg, fill=col, width=4, joint="curve")
    hx, hy = T((pts[1][0] + head[0], pts[1][1] + head[1]))
    d.ellipse((hx - 20, hy - 20, hx + 20, hy + 20), outline=col, width=3)
    tip = T((pts[6][0] + math.sin(phi) * ln, pts[6][1] - math.cos(phi) * ln))
    d.line((grip, tip), fill=(40, 200, 255, 180), width=3)
    im.alpha_composite(ov)
    b = Image.new("RGBA", im.size, "#1e1f22"); b.alpha_composite(im)
    cx = int((x) * 2)
    b.crop((cx - 260, int(g * 2) - 300, cx + 260, int(g * 2) + 60)).convert("RGB").save(out)
    return x, g
import sys
S = sys.argv[1]
for idx, n in [(60, "swing-top-full"), (73, "swing-impact-full"), (78, "swing-follow-full"), (367, "walk-a"), (372, "walk-b"), (377, "walk-c"), (382, "walk-d")]:
    print(n, draw(idx, n, f"{S}/cal-{n}.png"))
