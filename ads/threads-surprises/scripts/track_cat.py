#!/usr/bin/env python3
"""고양이 위치 추적 (cursorCat 캡처) — 중앙값 배경과의 차이로 고양이 덩어리 중심을 찾고 직선으로 맞춘다.
커서는 창 캡처에 안 찍히므로(설계상) bake.py가 이 직선 앞쪽에 커서를 그린다. 출력: data/cat-track.json"""
import os, glob, json, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = os.path.abspath(HERE + "/../../dist/cap/t1-surprises/cat")
fs = sorted(glob.glob(CAP + "/*.raw.png"), key=os.path.getmtime); t0 = os.path.getmtime(fs[0])
ts = [os.path.getmtime(f) - t0 for f in fs]
K = 4  # 1/4 해상도
def g(f): return np.asarray(Image.open(f).convert("L").reduce(K)).astype(np.float32)
bg_idx = [i for i, t in enumerate(ts) if 1.0 <= t <= 10.5][::4]
bg = np.median(np.stack([g(fs[i]) for i in bg_idx]), axis=0)
pts = []
for i, t in enumerate(ts):
    if not (1.6 <= t <= 4.4): continue
    d = np.abs(g(fs[i]) - bg)
    d[:, : 1700 // K] = 0; d[: 1500 // K] = 0; d[2010 // K :] = 0
    ys, xs = np.nonzero(d > 40)
    if len(xs) < 15: continue
    pts.append((t, float(np.median(xs)) * K, float(np.median(ys)) * K, int(len(xs))))
a = np.array(pts)
px = np.polyfit(a[:, 0], a[:, 1], 1); py = np.polyfit(a[:, 0], a[:, 2], 1)
res = np.abs(np.polyval(px, a[:, 0]) - a[:, 1])
print("n", len(a), "x(t) = %.1f t + %.1f" % tuple(px), "y(t) = %.2f t + %.1f" % tuple(py), "resid max %.1f med %.1f" % (res.max(), np.median(res)))
for p in pts[::3]: print("  t %.2f x %.0f y %.0f n %d" % p)
json.dump({"x": list(px), "y": list(py), "pts": pts}, open(HERE + "/data/cat-track.json", "w"))
