#!/usr/bin/env python3
"""본편 소재 준비 — dist/cap/ad(실캡처)만으로 컴포지션용 에셋·데이터를 만든다 (게임 실행 없음).

  python3 scripts/prep.py            → assets/gen/*.png, data/*.js

만드는 것
  plate-ko.png / plate-en.png : 3번 홀(절벽 티) 지형 + HUD 판. 티의 스틱맨·공은 걷기 프레임(walk-a)의 같은 영역으로 지운다.
                                영문판은 HUD 글자 영역을 알파 0으로 통째로 지운다(반쯤 잘린 글자 없음).
  swing-*.png                 : 실캡처 스윙 크롭에서 지형선(판과 겹치는 화소)을 빼고, 임팩트 뒤 공·궤적·티 페그를 지운 것.
  data/ground.js              : 지형 프로파일 gy(x) — 판 알파에서 추출 (x 0~1919pt, 화면 y pt)
  data/rig.js                 : 실제 리그 덤프(60Hz)를 광고 타임라인에 맞춘 30fps 포즈 + 스틱 위치
  data/trail.js               : 실제 드라이브 궤적(스크린 pt)과 공 시간 표본
"""
import gzip, json, re, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = HERE + "/../../dist/cap/ad"
GEN = HERE + "/assets/gen"; DATA = HERE + "/data"
os.makedirs(GEN, exist_ok=True); os.makedirs(DATA, exist_ok=True)
load = lambda n: np.array(Image.open(f"{CAP}/{n}.png").convert("RGBA")).astype(np.float32)
save = lambda a, n: Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(f"{GEN}/{n}.png", optimize=True)
P = lambda v: int(round(v * 2))  # pt → px (캡처는 2x)

# ── 1) 판 ──
tee = load("terrain-skytee"); walk = load("walk-a")
plate = tee.copy()
y0, y1, x0, x1 = P(700), P(868), P(80), P(250)          # 티의 스틱맨(조준 라벨 포함)·공
plate[y0:y1, x0:x1] = walk[y0:y1, x0:x1]
save(plate, "plate-ko")
en = plate.copy()
HUD = [(0, 1003, 460, 1080), (690, 1008, 1230, 1080), (1460, 1003, 1920, 1080)]  # pt (x0,y0,x1,y1)
for a, b, c, d in HUD:
    en[P(b):P(d), P(a):P(c), 3] = 0
save(en, "plate-en")

# ── 2) 지형 프로파일: 각 x열에서 700~1000pt 사이 가장 아래 불투명 화소 = 지면선 아래 가장자리 ──
A = en[..., 3]
gy = []
for xp in range(0, 3840, 2):
    col = A[P(700):P(1002), xp:xp + 2].max(axis=1)
    idx = np.nonzero(col > 90)[0]
    gy.append(None if len(idx) == 0 else (P(700) + idx[-1]) / 2 - 0.9)
# 빈 칸 보간
xs = np.arange(len(gy)); v = np.array([np.nan if g is None else g for g in gy])
ok = ~np.isnan(v); v = np.interp(xs, xs[ok], v[ok])
open(f"{DATA}/ground.js", "w").write("window.GROUND=" + json.dumps([round(float(g), 2) for g in v]) + ";\n")

# ── 3) 스윙 크롭 정리 ──
ox, oy = 80, 1432   # manifest origin_px (크롭 좌상단, 전체 프레임 px)
masks = {  # 크롭 px 좌표에서 지울 사각형들 (공·궤적·티 페그) — 크롭 440×400
    "swing-impact": [(225, 236, 440, 282)],
    "swing-follow": [(238, 150, 440, 281)],
    "swing-finish": [(236, 120, 440, 282)],
}
for n in ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"]:
    c = load(n); h, w = c.shape[:2]
    pa = plate[oy:oy + h, ox:ox + w, 3]
    c[..., 3] = np.clip(c[..., 3] - pa * 1.15, 0, 255)          # 판에 이미 있는 지형선은 뺀다
    for a, b, cc, d in masks.get(n, []):
        c[b:d, a:cc, 3] = 0
    save(c, n)
json.dump({"origin_pt": [ox / 2, oy / 2], "size_pt": [220, 200]}, open(f"{DATA}/swing.json", "w"))

# ── 4) 실제 궤적 추출 (flight-land-full: 궤적 전체가 남은 프레임) ──
fl = load("flight-land-full")
d = np.clip(fl[..., 3] - plate[..., 3] * 1.2, 0, 255)
d[:, :P(172)] = 0                                            # 스틱맨 영역 제외
d[P(955):, :] = 0
pts = []
for xp in range(P(172), P(935), 4):
    col = d[P(640):P(980), xp:xp + 4].max(axis=1)
    idx = np.nonzero(col > 25)[0]
    if len(idx):
        pts.append((xp / 2 + 1, (P(640) + idx.mean()) / 2))
# 공(흰 원) 위치: 각 비행 프레임에서 밝고 불투명한 덩어리의 중심
def ball(n):
    a = load(n); m = (a[..., 3] > 200) & (a[..., 0] > 235) & (plate[..., 3] < 30)
    m[:, :P(200)] = False; m[P(1000):] = False
    ys, xs_ = np.nonzero(m)
    return (xs_.mean() / 2, ys.mean() / 2) if len(xs_) else None
samples = {"f73": [153.5, 851.5], "f122": ball("flight-apex-full"), "f163": ball("flight-descent-full"), "f184": ball("flight-land-full")}
times = [l.split() for l in open(f"{CAP}/logs/hero-drive.times.txt")]
wall = {k: float(times[int(k[1:])][1]) for k in samples}
open(f"{DATA}/trail.js", "w").write("window.TRAIL=" + json.dumps({"pts": [[round(x, 1), round(y, 1)] for x, y in pts],
    "ball": {k: [round(v[0], 1), round(v[1], 1), round(wall[k] - wall["f73"], 3)] for k, v in samples.items()}}) + ";\n")

# ── 5) 리그 → 광고 타임라인 ──
log = open(f"{CAP}/logs/hero-drive.log").read().splitlines()
stick = []
for l in log:
    m = re.search(r"STICK\[([\d.]+)\] (\d+) (\d+) \d+ (\w+)", l)
    if m: stick.append((float(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)))
rig = []
for l in gzip.open(f"{CAP}/logs/hero-drive.rig.gz", "rt"):
    p = l.split()
    recv, st, mode = float(p[0]), float(p[1][4:-1]), p[2]
    xy = [tuple(map(float, q.split(","))) for q in p[3:13]]
    kv = dict(zip(p[13::2], p[14::2]))
    hx, hy = map(float, kv["head"].split(","))
    rig.append({"recv": recv, "st": st, "mode": mode, "pts": xy, "head": [hx, hy], "phi": float(kv["phi"]),
                "len": float(kv["len"]), "butt": float(kv["butt"]), "curved": int(kv["curved"]), "dir": int(kv["dir"])})
off = np.percentile([r["recv"] - r["st"] for r in rig], 5)      # 씬 시각 → 벽시계 (지연은 더해지기만 한다)
for r in rig: r["wall"] = r["st"] + off
CAP_LAG = 0.053   # 캡처 벽시계는 리그보다 53ms 늦다 (팔로스루 f78 클럽 끝 정합으로 실측, scripts/rigcal.py)
W_IMPACT = wall["f73"] - CAP_LAG
json.dump({"offset": off, "wallImpact": W_IMPACT, "capLag": CAP_LAG}, open(f"{DATA}/sync.json", "w"))
T_IMPACT_AD = 11 / 30                                            # 광고에서 임팩트 프레임 f11
def at_wall(w):
    ws = [r["wall"] for r in rig]; i = int(np.searchsorted(ws, w))
    i = max(1, min(len(rig) - 1, i)); a, b = rig[i - 1], rig[i]
    u = 0 if b["wall"] == a["wall"] else min(1, max(0, (w - a["wall"]) / (b["wall"] - a["wall"])))
    L = lambda p, q: p + (q - p) * u
    return {"mode": b["mode"] if u > .5 else a["mode"],
            "pts": [[round(L(p[0], q[0]), 2), round(L(p[1], q[1]), 2)] for p, q in zip(a["pts"], b["pts"])],
            "head": [round(L(a["head"][k], b["head"][k]), 2) for k in (0, 1)],
            "phi": round(L(a["phi"], b["phi"]), 4), "len": round(L(a["len"], b["len"]), 2),
            "butt": round(L(a["butt"], b["butt"]), 2), "curved": a["curved"] if u < .5 else b["curved"], "dir": a["dir"]}
sw = [s[0] for s in stick]
def stick_x(w):
    return float(np.interp(w, sw, [s[1] for s in stick]))
frames = []
for f in range(450):
    w = W_IMPACT + (f / 30 - T_IMPACT_AD)
    w = min(w, rig[-1]["wall"])
    p = at_wall(w); x = stick_x(w)
    frames.append({**p, "x": round(x, 2)})
open(f"{DATA}/rig.js", "w").write("window.RIG=" + json.dumps(frames, separators=(",", ":")) + ";\n")
print("plate/crops ok · ground", len(v), "· trail pts", len(pts), "· ball", samples, "· rig frames", len(frames),
      "· modes", sorted(set(f["mode"] for f in frames)), "· stick span", stick[0][0], stick[-1][0])
