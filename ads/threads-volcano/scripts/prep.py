#!/usr/bin/env python3
"""T2 화산 — 실캡처(게임 창 단위)·로그에서 컴포지션 데이터를 만든다 → data/scene.js

  python3 scripts/prep.py <캡처 루트>     (기본: dist/cap/threads-volcano/raw — 원본 PNG는 커밋하지 않는다)

입력 (scripts/capture-window.py 산출, --screen 0, 4K 창 3840×2160 = 1920×1080pt @2x)
  h56a·h56b·h56c : 홀인  — --demo --demo-bg --demo-trademark --gimmick volcano --seed 3 --demo-ball 402.5 --club SW --demo-shape lob --demo-power 0.56
                   세 번 같은 샷을 찍고 버스트 시작을 0 / 0.047 / 0.094초씩 어긋나게 해서 공 표본을 촘촘히(≈21Hz) 모았다
  m30a·m30b      : 빗나감 — 같은 명령에 --demo-power 0.30
출력 (전부 게임 화면 pt 좌표 = 캡처 px / 2, 좌상단 원점)
  GROUND  1m 간격 지형선 (게임 linePath와 같은 간격) · 표면 종류
  BALL_H / BALL_M  공 중심 (τ초, x, y) — τ=0은 임팩트(PLAY SHOT 줄과 같은 프레임)
  RIG_H / RIG_M    60Hz 리그 덤프 (τ, mode, 관절 10점, head, phi, len, butt, curved, dir)
"""
import json, os, re, sys, glob
import numpy as np, cv2

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
# 원본 PNG는 게임 띠(화산 주변)만 잘라 둔다: 창 3840×2160 중 (2900,1250)–(3840,2160). 읽을 때 원래 좌표로 되돌린다(파일 시각은 보존)
CROP = (2900, 1250)
def imread(f):
    im = cv2.imread(f, cv2.IMREAD_UNCHANGED)
    if im.shape[0] == 2160: return im
    full = np.zeros((2160, 3840, im.shape[2]), im.dtype); full[CROP[1]:CROP[1] + im.shape[0], CROP[0]:CROP[0] + im.shape[1]] = im
    return full
CAP = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(HERE + "/../../dist/cap/threads-volcano/raw")

# ── 지형선: 홀인 런 첫 장(조준 자세)에서 열마다 가장 아래 밝은 줄의 아래 가장자리 → 선 중심 ──
plate = imread(f"{CAP}/h56a/PLAYHOLE1-00.raw.png")[:, :, :3].astype(float)
g = plate.mean(2)
# 컵(어두운 10×9pt 홈): 연결 성분으로 찾는다
m = (g < 24).astype(np.uint8); n, lab, st, cen = cv2.connectedComponentsWithStats(m)
cup = [st[i] for i in range(1, n) if 250 < st[i][4] < 600 and st[i][1] > 1500][0]
CUP_X = (cup[0] + cup[2] / 2) / 2            # pt — px(holeX)
CUP_TOP = cup[1] / 2                          # pt — 컵 홈 윗변 = groundY(holeX)
HOLE_X = 424.3                                # m (과제 문서: seed 3 1번 홀)
PPM = CUP_X / HOLE_X                          # pt/m (= 화면 폭 1920pt / worldW)
GREEN = (417.0, 431.0)                        # 분화구 그린(테두리) m
CUP_HALF = max(1.1, 4.5 / PPM)                # 게임: max(Phys.cupHalfWidth, 4.5/pxPerM)
prof = []
for xm in range(372, 470):
    c = int(round(2 * xm * PPM))
    if c >= 3838: break
    col = g[1560:1840, c - 1:c + 2].max(1)
    ys = np.where(col > 62)[0]
    if len(ys) == 0: prof.append(None); continue
    bottom = (ys[-1] + 1560 + 1) / 2          # 선 아래 가장자리 (pt)
    green = GREEN[0] <= xm <= GREEN[1]
    prof.append(bottom - (1.3 if green else 0.9))   # 선 굵기 절반 (그린 2.6pt, 러프 1.8pt)
xs = list(range(372, 372 + len(prof)))
# 가려진 열(나무 줄기 394–396, 스틱맨 발·티 공 400–404)·컵 열은 이웃으로 메운다
bad = set(range(393, 398)) | set(range(399, 405)) | {424, 425}
good = [(x, y) for x, y in zip(xs, prof) if y is not None and x not in bad]
gx, gy = zip(*good)
ground = [float(np.interp(x, gx, gy)) for x in xs]
# 발치 띠(399–406, 435–449 근처)는 게임에서 평평한 러프 — 측정 잡음(±0.5pt)을 눌러 준다
flatL = [y for x, y in zip(xs, ground) if 398 <= x <= 406]
for i, x in enumerate(xs):
    if 398 <= x <= 406: ground[i] = float(np.median(flatL))
# 컵 자리 지면 = 컵 홈 윗변
STICK_X, STICK_GY = None, None
for l in open(f"{CAP}/h56a/log.txt"):
    mm = re.match(r"\[\s*[\d.]+\] STICK\[[\d.]+\] (\d+) (\d+) (\d+)", l)
    if mm: STICK_X, STICK_GY = float(mm.group(1)), float(mm.group(3)) - float(mm.group(2)); break

# ── 공: 버스트 PNG에서 가장 밝은 원(공 #FAFAF8, 스틱맨·깃대보다 밝다) ──
def ball_in(img):
    a = img[1300:2080, 2950:3840, :3]
    mk = (a.min(axis=2) > 236).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(mk)
    best = None
    for i in range(1, n):
        x, y, w, h, ar = st[i]
        if 150 <= ar <= 600 and 0.6 < w / max(h, 1) < 1.6 and (best is None or ar > best[2]):
            best = ((cen[i][0] + 2950) / 2, (cen[i][1] + 1300) / 2, int(ar))
    return best

def run_samples(run):
    d = f"{CAP}/{run}"; log = open(d + "/log.txt").read().splitlines()
    t0 = shot = None
    for l in log:
        mm = re.match(r"\[\s*([\d.]+)\] (STICK|MOVE)\[([\d.]+)\]", l)
        if mm and t0 is None: t0 = float(mm.group(3)) - float(mm.group(1))
        mm = re.match(r"\[\s*([\d.]+)\] PLAY SHOT", l)
        if mm and shot is None: shot = float(mm.group(1))
    out = []
    for f in sorted(glob.glob(d + "/PLAYSHOT*.raw.png")):
        b = ball_in(imread(f))
        if b and 1620 < b[0] < 1820 and 760 < b[1] < 905:
            out.append((os.stat(f).st_mtime - t0 - shot, b[0], b[1]))
    return out

def fit_flight(samples, x0, y0, land):
    """비행 구간: 임팩트(τ=0, 티 위 공) 고정 3차 다항식. 캡처 지연 δ(파일 기록 시각 − 실제 화면)를 격자 탐색으로 맞춘다."""
    best = None
    for dl in np.arange(0.0, 0.2, 0.002):
        S = [(t - dl, x, y) for t, x, y in samples if 0 < t - dl < land]
        if len(S) < 5: continue
        T = np.array([s[0] for s in S]); A = np.stack([T, T ** 2, T ** 3], 1)
        cx, rx, *_ = np.linalg.lstsq(A, np.array([s[1] for s in S]) - x0, rcond=None)
        cy, ry, *_ = np.linalg.lstsq(A, np.array([s[2] for s in S]) - y0, rcond=None)
        res = float(np.sqrt(((A @ cx - (np.array([s[1] for s in S]) - x0)) ** 2 + (A @ cy - (np.array([s[2] for s in S]) - y0)) ** 2).mean()))
        if best is None or res < best[0]: best = (res, dl, cx.tolist(), cy.tolist())
    return best

def rig(run):
    rows = []; shot_scene = None; seen_shot = False
    for l in open(f"{CAP}/{run}/log.txt"):
        if "PLAY SHOT" in l: seen_shot = True; continue
        mm = re.match(r"\[\s*[\d.]+\] RIG\[([\d.]+)\] (\S+) (.*) head (\S+) phi (\S+) len (\S+) butt (\S+) curved (\d) dir (-?\d)", l)
        if not mm: continue
        st = float(mm.group(1))
        if seen_shot and shot_scene is None: shot_scene = st      # PLAY SHOT 다음 첫 리그 줄 = 임팩트 프레임
        pts = [[float(v) for v in p.split(",")] for p in mm.group(3).split()]
        hd = [float(v) for v in mm.group(4).split(",")]
        rows.append([st, mm.group(2), pts, hd, float(mm.group(5)), float(mm.group(6)), float(mm.group(7)), int(mm.group(8)), int(mm.group(9))])
    for r in rows: r[0] = round(r[0] - shot_scene, 4)
    return rows

TEE = (402.5 * PPM, None)
H = sum((run_samples(r) for r in ("h56a", "h56b", "h56c")), [])
M = sum((run_samples(r) for r in ("m30a", "m30b")), [])
H.sort(); M.sort()
# 티 위 공 중심: 조준 장면에서 직접
b0 = ball_in(imread(f"{CAP}/h56a/PLAYHOLE1-00.raw.png"))
X0, Y0 = b0[0], b0[1]
fh = fit_flight(H, X0, Y0, 1.20)
fm = fit_flight(M, X0, Y0, 0.74)
print("cup", CUP_X, CUP_TOP, "ppm", PPM, "stick", STICK_X, STICK_GY, "tee ball", X0, Y0)
print("flight fit hole: rms %.2fpt δ %.3fs" % (fh[0], fh[1]), "miss: rms %.2fpt δ %.3fs" % (fm[0], fm[1]))
data = {
    "PPM": PPM, "HOLE_X": HOLE_X, "CUP_X": CUP_X, "CUP_TOP": CUP_TOP, "CUP_HALF": CUP_HALF, "GREEN": GREEN,
    "GX0": xs[0], "GROUND": [round(v, 2) for v in ground], "STICK_X": STICK_X, "STICK_GY": STICK_GY,
    "TEE_BALL": [X0, Y0],
    "FLIGHT_H": {"delta": fh[1], "cx": fh[2], "cy": fh[3], "rms": fh[0]},
    "FLIGHT_M": {"delta": fm[1], "cx": fm[2], "cy": fm[3], "rms": fm[0]},
    "BALL_H": [[round(t - fh[1], 4), round(x, 2), round(y, 2)] for t, x, y in H],
    "BALL_M": [[round(t - fm[1], 4), round(x, 2), round(y, 2)] for t, x, y in M],
    "RIG_H": rig("h56a"), "RIG_M": rig("m30a"),
}
os.makedirs(HERE + "/data", exist_ok=True)
open(HERE + "/data/scene.js", "w").write("window.SCENE=" + json.dumps(data, separators=(",", ":")) + ";\n")
print("wrote data/scene.js", len(data["RIG_H"]), len(data["RIG_M"]), len(H), len(M))
