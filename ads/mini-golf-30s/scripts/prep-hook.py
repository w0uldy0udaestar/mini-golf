#!/usr/bin/env python3
"""훅·헤드라인 장면 소재 — 15초판 실캡처(dist/cap/ad/*.png, logs/)에서 (15초판 scripts/prep.py 1·2·4장과 같은 방법)

  python3 scripts/prep-hook.py  → assets/gen/plate-skytee.png, data/hook.js (지형 프로파일·실제 궤적·공 시간 표본)

plate-skytee: 3번 홀(절벽 티) 지형 판. 티의 스틱맨·공은 걷기 프레임(walk-a)의 같은 영역으로 지우고, HUD 글자 3곳은 알파 0 (한/영 공통 — HUD는 광고 타이포로 옮긴다).
"""
import json, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = os.path.abspath(HERE + "/../../dist/cap/ad")
GEN = HERE + "/assets/gen"; DATA = HERE + "/data"
load = lambda n: np.array(Image.open(f"{CAP}/{n}.png").convert("RGBA")).astype(np.float32)
P = lambda v: int(round(v * 2))

tee = load("terrain-skytee"); walk = load("walk-a")
plate = tee.copy()
plate[P(700):P(868), P(80):P(250)] = walk[P(700):P(868), P(80):P(250)]
for a, b, c, d in [(0, 1003, 460, 1080), (690, 1008, 1230, 1080), (1460, 1003, 1920, 1080)]:
    plate[P(b):P(d), P(a):P(c), 3] = 0
Image.fromarray(np.clip(plate, 0, 255).astype(np.uint8), "RGBA").save(f"{GEN}/plate-skytee.png", optimize=True)

A = plate[..., 3]; gy = []
for xp in range(0, 3840, 2):
    col = A[P(700):P(1002), xp:xp + 2].max(axis=1); idx = np.nonzero(col > 90)[0]
    gy.append(np.nan if len(idx) == 0 else (P(700) + idx[-1]) / 2 - 0.9)
v = np.array(gy); xs = np.arange(len(v)); ok = ~np.isnan(v); v = np.interp(xs, xs[ok], v[ok])

fl = load("flight-land-full")
d = np.clip(fl[..., 3] - plate[..., 3] * 1.2, 0, 255); d[:, :P(172)] = 0; d[P(955):, :] = 0
pts = []
for xp in range(P(172), P(935), 4):
    col = d[P(640):P(980), xp:xp + 4].max(axis=1); idx = np.nonzero(col > 25)[0]
    if len(idx): pts.append((round(xp / 2 + 1, 1), round((P(640) + idx.mean()) / 2, 1)))
def ball(n):
    a = load(n); m = (a[..., 3] > 200) & (a[..., 0] > 235) & (plate[..., 3] < 30)
    m[:, :P(200)] = False; m[P(1000):] = False
    ys, xs_ = np.nonzero(m); return (round(xs_.mean() / 2, 1), round(ys.mean() / 2, 1))
times = [l.split() for l in open(f"{CAP}/logs/hero-drive.times.txt")]
wall = lambda k: float(times[k][1])
samples = {"f73": [153.5, 851.5], "f122": ball("flight-apex-full"), "f163": ball("flight-descent-full"), "f184": ball("flight-land-full")}
ballT = {k: [v[0], v[1], round(wall(int(k[1:])) - wall(73), 3)] for k, v in samples.items()}
json.dump({"ground": [round(float(g), 2) for g in v], "trail": pts, "ball": ballT}, open(f"{DATA}/hook.json", "w"))
open(f"{DATA}/hook.js", "w").write("window.HOOK=" + json.dumps({"ground": [round(float(g), 2) for g in v], "trail": pts, "ball": ballT}, separators=(",", ":")) + ";\n")
print("plate-skytee ok · ground", len(v), "· trail", len(pts), "· ball", ballT)
