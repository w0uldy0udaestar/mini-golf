#!/usr/bin/env python3
"""공 추적(검토용): track.py <scene> <t0> <t1> [xmin xmax] — 밝고 둥근 흰 덩어리(공) 중심을 pt로 출력"""
import sys, numpy as np, cv2, json
CAP = "/Users/universe/Project/mini-golf/dist/cap/ad/30s"
def balls(sc, t0, t1, xmin=0, xmax=1920):
    y0 = json.load(open(f"{CAP}/{sc}/segment.json"))["box_pt"][1]
    rows = [l.split() for l in open(f"{CAP}/{sc}/times.txt")]
    res = []
    for k, (p, w, i) in enumerate(rows):
        p = float(p)
        if not (t0 <= p <= t1): continue
        a = cv2.imread(f"{CAP}/{sc}/f{k:05d}.png", cv2.IMREAD_UNCHANGED).astype(int)  # BGRA
        m = ((a[..., 3] > 200) & (a[..., 0] > 238) & (a[..., 1] > 238) & (a[..., 2] > 238)).astype(np.uint8)
        n, lab, st, cen = cv2.connectedComponentsWithStats(m, 8)
        out = []
        for j in range(1, n):
            x, y, w_, h_, area = st[j]
            if 6 <= w_ <= 22 and 6 <= h_ <= 22 and abs(w_ - h_) <= 3 and area >= 30 and xmin * 2 <= cen[j][0] <= xmax * 2:
                out.append((round(cen[j][0] / 2, 1), round(y0 + cen[j][1] / 2, 1), int(area)))
        res.append((k, round(p, 3), out))
    return res
if __name__ == "__main__":
    sc, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    xs = [float(v) for v in sys.argv[4:6]] if len(sys.argv) > 5 else [0, 1920]
    for k, p, out in balls(sc, t0, t1, *xs):
        print(f"k{k} t{p}", out)
