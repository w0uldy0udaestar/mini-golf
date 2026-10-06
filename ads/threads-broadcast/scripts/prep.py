#!/usr/bin/env python3
"""T5 중계 패러디 — 소재 준비. dist/cap/ad(15초 광고의 실캡처 hero-drive)와 게임 물리만으로 만든다 (게임 실행 없음).

  python3 scripts/prep.py        → assets/gen/*.png, data/shot.js (+ 계산 근거를 표준 출력에)

1) 판·스윙 크롭: 15초 광고 prep.py와 같은 규칙(티의 스틱맨·공은 걷기 프레임으로 지우고, 크롭에서는 판에 이미 있는 지형선과 임팩트 뒤 공·궤적을 뺀다).
2) 탄도: Sources/GolfCore/Ballistics.swift 의 .fly 스텝(240Hz)을 그대로 옮겨, hero-drive 샷(DR h1.00, 티, 바람 → 1 m/s HUD)을 다시 푼다.
   h1.00 풀파워는 미스힛(정규 근사 난수, 로그에 없음)이 붙으므로, 실캡처 궤적의 정점 높이·정점 위치·착지점(LANDCUE x 326)에
   맞는 미스힛 m을 격자 탐색으로 찾는다. 볼 스피드·정점은 그 해에서, 캐리·토탈은 로그 줄에서 바로 읽는다.
3) 화면 매핑: 공 x(pt) = 153.5 + x(m)·PXM, y(pt) = 851.5 − y(m)·PXM·1.4 (GameScene.pxPerM = 화면폭/worldW, 세로 과장 vScaleMax 1.4).
   화면 시간 = 물리 시간 / K — K는 실캡처 공 표본 3개(f122·f163·착지)에 맞춘다(게임은 비행을 빨리 감아 보여 준다).
"""
import json, math, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = HERE + "/../../dist/cap/ad"
GEN = HERE + "/assets/gen"; DATA = HERE + "/data"
os.makedirs(GEN, exist_ok=True); os.makedirs(DATA, exist_ok=True)
load = lambda n: np.array(Image.open(f"{CAP}/{n}.png").convert("RGBA")).astype(np.float32)
save = lambda a, n: Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(f"{GEN}/{n}.png", optimize=True)
P = lambda v: int(round(v * 2))

# ── 1) 판 + 스윙 크롭 (15초 광고 prep.py 1·3단계와 같은 규칙) ──
tee = load("terrain-skytee"); walk = load("walk-a")
plate = tee.copy()
plate[P(700):P(868), P(80):P(250)] = walk[P(700):P(868), P(80):P(250)]
save(plate, "plate-ko")
masks = {"swing-impact": [(225, 236, 440, 282)], "swing-follow": [(238, 150, 440, 281)], "swing-finish": [(236, 120, 440, 282)]}
ox, oy = 80, 1432
for n in ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"]:
    c = load(n); h, w = c.shape[:2]
    c[..., 3] = np.clip(c[..., 3] - plate[oy:oy + h, ox:ox + w, 3] * 1.15, 0, 255)
    for a, b, cc, d in masks.get(n, []):
        c[b:d, a:cc, 3] = 0
    save(c, n)

# ── 2) 로그 ──
log = open(f"{CAP}/logs/hero-drive.log").read().splitlines()
def line(key):
    return next(l for l in log if key in l)
L_HOLE, L_SHOT, L_LAND, L_REST = line("PLAY HOLE"), line("PLAY SHOT"), line("LANDCUE"), line("PLAY REST")
tee_x = float(L_SHOT.split(" from ")[1].split()[0])          # 54.2
land_x = float(L_LAND.split(" x ")[1].split()[0])            # 326 (LANDCUE는 %.0f — ±0.5 m)
rest_x = float(L_REST.split(" x ")[1].split()[0])            # 342.0
cup_x = float(L_HOLE.split(" cup ")[1].split()[0])           # 632
hole_tee = float(L_HOLE.split(" tee ")[1].split()[0])        # 54
w_land, w_rest = float(L_LAND.split()[0]), float(L_REST.split()[0])
times = [l.split() for l in open(f"{CAP}/logs/hero-drive.times.txt")]
wall = lambda f: float(times[f][1])
W_IMP = wall(73)                                             # 15초 광고와 같은 임팩트 프레임(f73: 공이 아직 티 위)

# ── 3) 화면 매핑 상수 ──
X0, Y0 = 153.5, 851.5                                        # 티 위 공 중심 (pt, 15초 광고 trail.js f73)
PXM = (1792.0 - X0) / (cup_x - tee_x)                        # 깃대 x 1792pt(판에서 실측) ↔ 컵 632 m
VS = 1.4                                                     # GameScene.vScaleMax (이 홀은 예산 안 → 1.4)
G = json.loads(open(f"{DATA}/ground.js").read().split("=", 1)[1].rstrip().rstrip(";"))
tr = json.loads(open(HERE + "/../mini-golf-15s/data/trail.js").read().split("=", 1)[1].rstrip().rstrip(";"))
apex_pt = min(tr["pts"], key=lambda p: p[1])
obs_apex = (Y0 - apex_pt[1]) / (PXM * VS); obs_apx = (apex_pt[0] - X0) / PXM
obs_drop = -(G[round(X0 + (land_x - tee_x) * PXM)] - G[round(X0)]) / (PXM * VS)

# ── 4) Ballistics.step(.fly) 이식 + Ballistics.launch(DR, h1.00, tee, mishit m) ──
g, q, cd, R = 9.81, 0.01869, 0.25, 0.0213
clB, clS, clM, srM, sdec, dt = 0.04, 1.8, 0.35, 0.30, 0.00067, 1 / 240
POWER, LOFT, SPIN, TEE_WOOD = 69.0, 10.5, 2700.0, 0.85       # ClubTable DR · Ballistics.launch teeWood
def fly(m, wind, until_x=None):
    v0 = POWER * 1.0 * (0.25 + 0.75 * 1.0) * (1 - abs(m) * 0.12)
    lo = math.radians(LOFT + m * 4)
    x = y = t = 0.0; vx, vy = v0 * math.cos(lo), v0 * math.sin(lo); s = SPIN * TEE_WOOD * 1.0 * (1 - abs(m) * 0.3)
    out = [(0.0, 0.0, 0.0)]; apex = (0, 0, 0)
    while t < 15:
        rvx = vx - wind; v = max(math.hypot(rvx, vy), 1e-9)
        cl = min(clM, clB + clS * min(R * s * 2 * math.pi / 60 / v, srM))
        ax = -q * cd * v * rvx + q * cl * v * -vy; ay = -g - q * cd * v * vy + q * cl * v * rvx
        vx += ax * dt; vy += ay * dt; x += vx * dt; y += vy * dt; s *= 1 - min(0.06, max(0.01, sdec * v)) * dt; t += dt
        out.append((t, x, y))
        if y > apex[0]: apex = (y, x, t)
        if until_x is not None and x >= until_x: break
    return v0, math.degrees(lo), apex, out

fits = []
for mi in range(-100, 101):
    for wind in (0.5, 0.75, 1.0, 1.25, 1.5):                    # HUD "바람 → 1m/s" = 반올림 표시
        v0, lo, ap, out = fly(mi / 100, wind, land_x - tee_x)
        err = (ap[0] - obs_apex) ** 2 + ((ap[1] - obs_apx) / 6) ** 2 + (out[-1][2] - obs_drop) ** 2
        fits.append((err, mi / 100, wind, v0, ap[0], lo))
fits.sort()
good = [f for f in fits if f[0] <= fits[0][0] * 2 + 0.3]
best = fits[0]; m_b, w_b = best[1], best[2]
v0, lo, ap, path = fly(m_b, w_b, land_x - tee_x)
spd_lo, spd_hi = min(f[3] for f in good), max(f[3] for f in good)
apx_lo, apx_hi = min(f[4] for f in good), max(f[4] for f in good)

# 화면 시간 배율 K: 실캡처 공 표본에 맞춘다
samples = [(wall(122) - W_IMP, tr["ball"]["f122"][0]), (wall(163) - W_IMP, tr["ball"]["f163"][0]), (w_land - W_IMP, X0 + (land_x - tee_x) * PXM)]
def t_at_xpt(xpt):
    xm = (xpt - X0) / PXM
    return next(t for t, x, y in path if x >= xm - 1e-9) if xm <= path[-1][1] else path[-1][0]
K = float(np.mean([t_at_xpt(xp) / ts for ts, xp in samples]))

F_IMP = 11                                                   # 광고 임팩트 프레임 (15초 광고 리그와 같은 정렬)
pts = []
for t, x, y in path[::4]:
    pts.append([round(F_IMP + t / K * 30, 3), round(X0 + x * PXM, 2), round(Y0 - y * PXM * VS, 2)])
t, x, y = path[-1]; pts.append([round(F_IMP + t / K * 30, 3), round(X0 + x * PXM, 2), round(Y0 - y * PXM * VS, 2)])
f_land = F_IMP + (w_land - W_IMP) * 30; f_rest = F_IMP + (w_rest - W_IMP) * 30
s184 = tr["ball"]["f184"]; f184 = F_IMP + (wall(184) - W_IMP) * 30

nums = {"carry": round(land_x - tee_x), "total": round(rest_x - tee_x), "speed": round(v0), "apex": round(ap[0]),
        "hole": int(L_HOLE.split()[3]), "par": int(L_HOLE.split()[5]), "len": round(cup_x - hole_tee)}
shot = {"pts": pts, "fLand": round(f_land, 2), "fRest": round(f_rest, 2), "xLand": round(X0 + (land_x - tee_x) * PXM, 2),
        "xRest": round(X0 + (rest_x - tee_x) * PXM, 2), "hop": [round(f184, 2), s184[0], s184[1]], "nums": nums,
        "pxm": round(PXM, 4), "tee": [X0, Y0], "fApex": round(F_IMP + ap[2] / K * 30, 2)}
open(f"{DATA}/shot.js", "w").write("window.SHOT=" + json.dumps(shot, separators=(",", ":")) + ";\n")

print("로그:", L_HOLE.split(" ", 1)[1], "|", L_SHOT.split(" ", 1)[1], "|", L_LAND.split(" ", 1)[1], "|", L_REST.split(" ", 1)[1])
print(f"PXM {PXM:.4f} pt/m · 실캡처 정점 {obs_apex:.1f} m @ {obs_apx:.1f} m · 착지점 표고차 {obs_drop:.1f} m")
print(f"최적 미스힛 m {m_b:+.2f} · 바람 {w_b} m/s · v0 {v0:.2f} m/s · 발사각 {lo:.1f}° · 정점 {ap[0]:.1f} m @ {ap[1]:.1f} m (t {ap[2]:.2f}s)")
print(f"근접 해 {len(good)}개: 볼 스피드 {spd_lo:.2f}–{spd_hi:.2f} m/s · 정점 {apx_lo:.1f}–{apx_hi:.1f} m")
print(f"화면 시간 배율 K {K:.3f} (표본별 {[round(t_at_xpt(xp) / ts, 3) for ts, xp in samples]}) · 착지 f{f_land:.1f} · 정지 f{f_rest:.1f}")
print("자막 숫자:", nums)
