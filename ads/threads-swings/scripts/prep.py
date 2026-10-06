#!/usr/bin/env python3
"""소재 준비 — dist/cap/threads-swings/{jump,twirl,lock}(창 단위 실캡처 + 60Hz 리그 덤프)만으로 컴포지션 데이터를 만든다.

  python3 scripts/prep.py      → data/rigs.js, assets/cap/twirl-hold.png, 핵심 시각 표 출력

- data/rigs.js : 스타일별 리그 표본(임팩트 기준 상대 시각 t, 60Hz 원본 그대로). 임팩트 = 다운스윙 중 phi가 2π를 지나는 순간.
                 렌더는 facing 로컬 좌표에 dir=+1을 곱한다(돌리는 스윙은 미러 홀에서 찍혀 왼쪽을 봤다 → 셋 다 오른쪽을 보게).
- twirl-hold   : '클럽을 돌리는 스윙' 트월 뒤 정지 실캡처(창 단위 screencapture, --demo-bg 불투명 회색) 크롭·좌우 반전.
                 같은 자세의 리그 표본을 IoU 최대로 찾아(scripts/calib.py와 같은 방식) capture.rigT로 적는다.
파일명·화면 어디에도 선수 이름이나 코드 식별자를 쓰지 않는다 — 폴더 이름은 동작 이름(jump/twirl/lock)이다.
"""
import json, math, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from riglog import CAP, load, impact
from calib import joints, draw_mask

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
out = {}
for name in ["jump", "twirl", "lock"]:
    rows, sticks, ev = load(name)
    ti = impact(rows)
    # 임팩트 −1.0s ~ +2.4s (첫 스윙만 — 이후 서프라이즈·걷기는 쓰지 않는다)
    sel = [r for r in rows if -1.0 <= r["st"] - ti <= 2.4]
    S = [{"t": round(r["st"] - ti, 4), "m": r["mode"][0], "p": [[round(a, 1), round(b, 1)] for a, b in r["pts"]],
          "h": r["head"], "phi": round(r["phi"], 4), "len": r["len"], "butt": r["butt"], "c": r["curved"]} for r in sel]
    # 핵심 시각
    top = next(r["st"] - ti for r in rows if r["mode"] == "swinging")
    phis = [(r["st"] - ti, r["phi"]) for r in sel]
    hip = [(r["st"] - ti, r["pts"][0][1], r["pts"][2][1]) for r in sel]
    jpk = max(hip, key=lambda x: x[1])
    # 피니시: 임팩트 뒤 phi 변화율이 처음으로 0.5 rad/s 아래로 떨어지는 시각
    fin = None
    for (t0, p0), (t1, p1) in zip(phis, phis[1:]):
        if t0 > 0.05 and abs(p1 - p0) / max(1e-6, t1 - t0) < 0.5:
            fin = t0; break
    # 트월: 피니시 뒤 phi가 다시 빠르게 도는 구간
    tw = [t for (t0, p0), (t1, p1) in zip(phis, phis[1:]) for t in [t0] if t0 > (fin or 0) + 0.1 and abs(p1 - p0) / max(1e-6, t1 - t0) > 2]
    ext = []
    for r in sel:
        J = joints(r, 0, 0, d=1)
        xs = [p[0] for k, p in J.items()]; ys = [p[1] for k, p in J.items()]
        ext.append((min(xs), max(xs), min(ys), max(ys)))
    ex = [min(e[0] for e in ext), max(e[1] for e in ext), min(e[2] for e in ext), max(e[3] for e in ext)]
    print(f"{name:6s} n={len(S)} top {top:+.3f} finish {fin} twirl {tw[0] if tw else None}..{tw[-1] if tw else None} "
          f"jumpPeak t{jpk[0]:+.3f} hipY {jpk[1]} footY {jpk[2]} extent x[{ex[0]:.0f},{ex[1]:.0f}] y[{ex[2]:.0f},{ex[3]:.0f}]")
    out[name] = {"samples": S, "top": round(top, 3), "finish": fin, "twirl": [tw[0], tw[-1]] if tw else None,
                 "stick": {"x": sticks[0]["x"], "gy": sticks[0]["h"] - sticks[0]["gy"]}}

# 실캡처 크롭: 돌리는 스윙의 트월 뒤 정지 자세(리코일 — 팔이 몸에서 떨어져 관절선이 잘 읽힌다). 창 단위 캡처, 불투명 회색 배경.
# 이 스윙은 미러 홀(왼쪽 보기)에서 찍혔다 → 스틱 기준 좌우 대칭으로 잘라 좌우 반전(셋 다 오른쪽을 보게, 리그도 dir=+1로 그린다)
name = "twirl"; rows, sticks, ev = load(name)
gx, gy = sticks[0]["x"], sticks[0]["h"] - sticks[0]["gy"]
ti = impact(rows)
cap = Image.open(f"{CAP}/{name}/TRADEMARK1-00.raw.png").convert("RGB")
LF, RT, UP, DN = 70, 90, 125, 25  # pt: 스틱 기준 (반전 뒤) 왼쪽·오른쪽·위·아래 — 머리 꼭대기(−99)가 위 페더(−125~−107) 밖에 오게
FF_S = 10.4                         # 전체 화면 배율(px/pt) — src/main.js FF.S가 이 값을 읽는다
ox = gx - RT                        # 원본(왼쪽 보기)에서는 오른쪽 RT가 반전 뒤 왼쪽이 된다
crop = cap.crop((ox * 2, (gy - UP) * 2, (gx + LF) * 2, (gy + DN) * 2))
m = np.asarray(crop.convert("L")) > 120
m[int((UP - 2) * 2):] = False
best = None
for r in rows:
    t = r["st"] - ti
    if not (1.2 < t < 2.4): continue
    mk = np.asarray(draw_mask(joints(r, gx, gy), ((LF + RT) * 2, (UP + DN) * 2), ox, gy - UP)) > 0
    mk[int((UP - 2) * 2):] = False
    iou = (m & mk).sum() / max(1, (m | mk).sum())
    if best is None or iou > best[0]: best = (iou, t)
crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
a = np.asarray(crop).astype(np.float32)
rowsum = a.mean(axis=(1, 2)); band = list(range(int((UP - 6) * 2), int((UP + 6) * 2)))
gl = max(band, key=lambda i: rowsum[i]) / 2 - UP
bg = [int(v) for v in np.median(a[:20, :20].reshape(-1, 3), axis=0)]
os.makedirs(HERE + "/assets/cap", exist_ok=True)
# 위·아래 12% 알파 페더를 PNG에 굽는다(CSS mask는 합성 레이어를 만들어 렌더가 비결정적이었다 — qa 결정론 실측)
# 3차(컬러): 회색 바탕을 버리고 선만 남긴다 — 알파 = 밝기(배경 rgb 40 → 0, 흰 선 → 1), 색은 흰색. 칸 색 위에 실캡처 선화가 그대로 얹힌다
lum = np.asarray(crop.convert("L")).astype(np.float32)
alpha = np.clip((lum - 46) / (225 - 46), 0, 1) * 255
rgba = np.dstack([np.full(lum.shape, 255, np.float32)] * 3 + [alpha])
hh = rgba.shape[0]; ramp = np.clip(np.minimum(np.arange(hh), hh - 1 - np.arange(hh)) / (0.12 * hh), 0, 1)
rgba[..., 3] *= (ramp * ramp * (3 - 2 * ramp))[:, None]
# 전체 화면 배율로 미리 Lanczos 확대 → 정지 구간에서 브라우저가 1:1로 그린다(실시간 리샘플 품질이 렌더마다 달라졌다 — 결정론 실측)
Image.fromarray(rgba.astype(np.uint8), "RGBA").resize((round((LF + RT) * FF_S), round((UP + DN) * FF_S)), Image.LANCZOS).save(HERE + "/assets/cap/twirl-hold.png", optimize=True)
# ── 지형선 벡터화: 조준 스틸(샷 전)에서 실제 지면선 중심 높이와 러프 틱을 뽑는다(이미지 대신 벡터 — 리샘플 비결정성 회피) ──
def terrain(name, mirror):
    rows_, sticks_, _ = load(name)
    gx_, gy_ = sticks_[0]["x"], sticks_[0]["h"] - sticks_[0]["gy"]
    L = np.asarray(Image.open(f"{CAP}/{name}/AIMx1-00.raw.png").convert("L")).astype(np.float32)
    prof, ticks, run = [], [], []
    xs = np.arange(-140, 310.01, 0.5)
    for rx in xs:
        x = gx_ + (-rx if mirror else rx)
        col = L[int((gy_ - 22) * 2):int((gy_ + 10) * 2), int(round(x * 2))]
        br = np.nonzero(col > 110)[0]
        if len(br) == 0: prof.append(None); continue
        bottom = br.max() / 2 + (gy_ - 22)                      # 밝은 구간의 아래 가장자리(pt)
        center = bottom - 0.75                                   # 선 굵기 1.5pt의 중심
        prof.append(round(gy_ - center, 2))                      # 지면 기준 높이(+ 위)
        top = br.min() / 2 + (gy_ - 22)
        h_ = (center - 0.75) - top                               # 선 위로 솟은 길이
        if -45 < rx < 30: h_ = 0                                 # 스틱맨·티·공 자리 제외
        if h_ > 1.2: run.append((rx, h_))
        elif run:
            if len(run) <= 6: ticks.append([round(sum(r[0] for r in run) / len(run), 2), round(max(r[1] for r in run), 2)])
            run = []
    v = np.array([np.nan if q is None else q for q in prof]); ok = ~np.isnan(v)
    v = np.interp(np.arange(len(v)), np.nonzero(ok)[0], v[ok])
    v[(xs > -45) & (xs < 30)] = np.median(v[(xs > -60) & (xs < 40)])  # 티 박스는 평평
    return {"x0": -140, "dx": 0.5, "y": [round(float(q), 2) for q in v], "ticks": ticks}
for nm, mir in [("jump", False), ("lock", False), ("twirl", True)]:
    out[nm]["terrain"] = terrain(nm, mir)
    tr = out[nm]["terrain"]; print("terrain", nm, "range", min(tr["y"]), max(tr["y"]), "ticks", len(tr["ticks"]))
out["capture"] = {"file": "assets/cap/twirl-hold.png", "rel": [-LF, -UP], "size": [LF + RT, UP + DN], "scale": FF_S, "px": 2, "mirrored": True,
                  "groundLineRel": gl, "bg": bg, "rigT": round(best[1], 4), "iou": round(float(best[0]), 3)}
print("capture", out["capture"])
open(HERE + "/data/rigs.js", "w").write("window.RIGS=" + json.dumps(out, separators=(",", ":")) + ";\n")
print("wrote data/rigs.js", os.path.getsize(HERE + "/data/rigs.js"))
