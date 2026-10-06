#!/usr/bin/env python3
"""v3 — 캡처에서 '그림'이 아니라 '데이터'를 뽑는다 → data/scenes.js (window.SCENES).
게임 그림은 main.js가 게임 소스의 도형 치수(Surprises*.swift · GameScene)로 벡터로 다시 그린다. 여기서는 위치와 시각만.

컷마다
  terrain : 지형선(원본 2x 픽셀 좌표) — 배우가 없는 중앙값 배경에서 열마다 띠 안의 가장 아래 밝은 화소 → 중앙값 필터
  ball    : [t, x, y] — 순백(≥250) 화소 덩어리 중심 (공은 게임에서 유일한 순백 채움 원)
  actor   : [t, cx, cy, x0, y0, x1, y1, n] — 배경과의 차이(>40) 덩어리(공 제외)의 중심·외곽 (영역 안)
  t = 캡처 시각(초, data/capture-times.json 기준) — main.js가 30fps로 보간한다
"""
import json, os
import cv2, numpy as np
HERE = os.path.abspath(os.path.dirname(os.path.abspath(__file__)) + "/..")
CAP = os.path.abspath(HERE + "/../../dist/cap/t1-surprises")
MAN = json.load(open(HERE + "/data/capture-times.json"))

def frames(name, ta, tb):
    return [(t, f"{CAP}/{name}/{b}") for t, b in MAN[name] if ta <= t <= tb]

def gray(p): return cv2.imread(p, cv2.IMREAD_GRAYSCALE)[:2160, :3840]

def background(name, ta, tb, k=15):
    fs = frames(name, ta, tb); step = max(1, len(fs) // k)
    return np.median(np.stack([gray(p) for _, p in fs[::step]]), axis=0).astype(np.uint8)

def terrain(bg, x0, x1, y0=1500, y1=2012, step=6):
    pts = []
    for x in range(x0, x1, step):
        col = bg[y0:y1, max(0, x - 1):x + 2].max(axis=1)
        ys = np.nonzero(col > 105)[0]
        pts.append([x, int(y0 + ys.max()) if len(ys) else None])
    ys = [p[1] for p in pts]
    # 빈 칸 메우기 + 중앙값 필터(지형선 위 잔디 틱·튀는 값 제거)
    last = next((y for y in ys if y is not None), 1900)
    ys = [last := (y if y is not None else last) for y in ys]
    sm = [int(np.median(ys[max(0, i - 4):i + 5])) for i in range(len(ys))]
    return [[pts[i][0], sm[i]] for i in range(len(pts))]

def track(name, ta, tb, region, bg, ball_region=None):
    X0, Y0, X1, Y1 = region; ball, actor = [], []
    for t, p in frames(name, ta, tb):
        g = gray(p)
        br = ball_region or region
        sub = g[br[1]:br[3], br[0]:br[2]]
        ys, xs = np.nonzero(sub >= 250)
        if len(xs) > 20: ball.append([round(t, 4), round(float(xs.mean()) + br[0], 1), round(float(ys.mean()) + br[1], 1)])
        d = cv2.absdiff(g[Y0:Y1, X0:X1], bg[Y0:Y1, X0:X1]); m = (d > 40) & (g[Y0:Y1, X0:X1] < 250)
        m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n, lab, st, cen = cv2.connectedComponentsWithStats(m)
        if n > 1:
            big = [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] >= 60]
            if big:
                xs0 = min(st[i, 0] for i in big); ys0 = min(st[i, 1] for i in big)
                xs1 = max(st[i, 0] + st[i, 2] for i in big); ys1 = max(st[i, 1] + st[i, 3] for i in big)
                area = sum(st[i, cv2.CC_STAT_AREA] for i in big)
                cx = sum(cen[i][0] * st[i, cv2.CC_STAT_AREA] for i in big) / area; cy = sum(cen[i][1] * st[i, cv2.CC_STAT_AREA] for i in big) / area
                actor.append([round(t, 4), round(cx + X0, 1), round(cy + Y0, 1), int(xs0 + X0), int(ys0 + Y0), int(xs1 + X0), int(ys1 + Y0), int(area)])
    return ball, actor

def geese_components(name, t, region):
    p = min(MAN[name], key=lambda r: abs(r[0] - t))[1]; g = gray(f"{CAP}/{name}/{p}")
    X0, Y0, X1, Y1 = region; m = (g[Y0:Y1, X0:X1] > 150).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(m)
    out = [[int(st[i, 0] + X0), int(st[i, 1] + Y0), int(st[i, 0] + st[i, 2] + X0), int(st[i, 1] + st[i, 3] + Y0), int(st[i, 4])] for i in range(1, n) if st[i, 4] > 150]
    return sorted(out)

S = {}
# 거위: 앉은 프레임의 다섯 마리 외곽(지형선 위만) + 공 + 날아오르는 무리의 궤적
bg = background("geese", 9.0, 12.8)
S["geese"] = dict(terrain=terrain(bg, 1900, 2800), geese=geese_components("geese", 5.11, (2150, 1640, 2560, 1772)))
S["geese"]["ball"], S["geese"]["actor"] = track("geese", 6.5, 7.6, (1900, 1100, 2800, 1760), bg, ball_region=(2250, 1700, 2400, 1800))
# 새: 나무 옆 공을 채서 솟는다
bg = background("bird", 4.3, 10.5)
S["bird"] = dict(terrain=terrain(bg, 300, 1300))
S["bird"]["ball"], S["bird"]["actor"] = track("bird", 1.5, 3.9, (420, 1350, 1150, 1975), bg)
# 핀: 깃발(빨강 천 + 흰 폴)의 위치 — 빨강 화소 중심으로
bg = background("pin", 4.0, 13.0)
S["pin"] = dict(terrain=terrain(bg, 3100, 3800))
red = []
for t, p in frames("pin", 0.9, 3.4):
    im = cv2.imread(p)[:2160, :3840]; b, g, r = [im[1600:1820, 3250:3650, k].astype(int) for k in range(3)]
    ys, xs = np.nonzero((r > 150) & (g < 110) & (b < 110))
    if len(xs) > 30: red.append([round(t, 4), round(float(xs.min()) + 3250, 1), round(float(ys.min()) + 1600, 1)])
S["pin"]["flag"] = red   # [t, 천의 왼쪽 끝 x(=폴), 천 위 y]
# 두더지
bg = background("mole", 3.2, 11.0)
S["mole"] = dict(terrain=terrain(bg, 1000, 1800))
S["mole"]["ball"], S["mole"]["actor"] = track("mole", 0.3, 2.6, (1300, 1850, 1520, 1990), bg)
# 고양이: data/cat-track.json(직선 맞춤)을 그대로 쓴다 + 지형
bg = background("cat", 1.0, 10.5)
S["cat"] = dict(terrain=terrain(bg, 1500, 3300), fit=json.load(open(HERE + "/data/cat-track.json")))
# 강아지
bg = background("dog", 5.0, 7.3)
S["dog"] = dict(terrain=terrain(bg, 700, 1700))
S["dog"]["ball"], S["dog"]["actor"] = track("dog", 1.2, 4.5, (900, 1780, 1650, 1975), bg)
# 갤러리(환호): 지형 + 관중·스틱맨 외곽(첫 프레임)
bg = background("gallery-b", 4.0, 8.2)
S["gallery"] = dict(terrain=terrain(bg, 0, 3840, step=8), crowd=geese_components("gallery-b", 0.0, (1590, 1840, 1900, 1990)),
                    man=geese_components("gallery-b", 0.0, (1440, 1740, 1640, 1990)))
im = np.median(np.stack([cv2.imread(p)[:2160, :3840] for _, p in frames("gallery-b", 4.0, 8.2)[::10]]), axis=0).astype(np.uint8)
b_, g_, r_ = [im[1400:2050, :, k].astype(int) for k in range(3)]
ys, xs = np.nonzero((r_ > 150) & (g_ < 110) & (b_ < 110))
S["gallery"]["flag"] = [int(xs.min()), int(ys.min()) + 1400] if len(xs) else None   # 깃발 천 왼쪽 끝(=폴 x), 천 위 y
gb = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)[1500:2012, :]; ys, xs = np.nonzero(gb >= 250)
S["gallery"]["ballxy"] = [round(float(xs.mean()), 1), round(float(ys.mean()) + 1500, 1)] if len(xs) else None
open(HERE + "/data/scenes.js", "w").write("/* scripts/extract.py가 쓴다 — 캡처에서 뽑은 위치·시각(원본 2x 픽셀). 손으로 고치지 말 것 */\nwindow.SCENES = " + json.dumps(S, separators=(",", ":")) + ";\n")
for k, v in S.items():
    print(k, {kk: (len(vv) if isinstance(vv, list) else "obj") for kk, vv in v.items()})
print("geese", S["geese"]["geese"]); print("crowd", S["gallery"]["crowd"]); print("man", S["gallery"]["man"])
print("bird actor sample", S["bird"]["actor"][::6][:8]); print("bird ball", S["bird"]["ball"][::5][:8])
print("dog actor", S["dog"]["actor"][::5][:10]); print("dog ball", S["dog"]["ball"][::5][:10])
print("mole actor", S["mole"]["actor"][::4][:10]); print("mole ball", S["mole"]["ball"][::4][:8])
print("pin flag", S["pin"]["flag"][::5]); print("geese actor", S["geese"]["actor"][::3]); print("geese ball", S["geese"]["ball"][::4])
