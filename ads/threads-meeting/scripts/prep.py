#!/usr/bin/env python3
"""T3 회의 중 9홀 — 소재 준비. dist/cap/ad(실캡처)만 쓴다. 게임은 다시 실행하지 않는다.

  python3 scripts/prep.py   → assets/gen/hole-*.png · seq-*-*.png · swing-*.png, data/holes.js

1) 홀 판(plate): 실캡처 terrain-*.png(3840×2160, 2x, 알파)에서 세로 화면 조각(745pt 폭)과 띠(y 600~1080pt)만 잘라 낸다.
   왼쪽 티 홀은 x 0~745pt, 오른쪽 티(미러) 홀은 x 1175~1920pt. 벡터 스틱맨(실제 리그)을 올릴 홀(1·4·9번)은
   판에 찍힌 티 위 스틱맨·조준 라벨·공을 옆 평지 30pt 기둥으로 덮어 지운다. 3번 홀은 15초판 plate-ko(티를 이미 지운 판).
2) 연번 클립(seq): 30초판 실캡처 연번(dist/cap/ad/30s/<장면>/fNNNNN.png, 29.3fps)에서 타임랩스 컷 길이만큼 잘라
   1.5x(1118×720px)로 줄인다 — 2·5·7번 홀 컷은 판 대신 이 프레임이 그대로 재생된다(실제 스윙·퍼트·컵인).
3) 밝기: 띠의 선화(채도 낮고 밝은 화소 = 지형선·러프 틱·스틱맨·공·HUD)를 흰색 100%로 올리고 알파를 ×1.35 한다.
   어두운 채움(나무 속)과 채도 있는 화소(깃발 빨강·왕관)는 그대로 둔다. 15초판 스윙 크롭 5장도 같은 처리.
4) 지형 프로파일: 지운 판의 알파에서 각 열의 가장 아래 불투명 화소(y 700~1002pt) = 지면선 (15초판 prep.py와 같은 방법).
"""
import json, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = HERE + "/../../dist/cap/ad"
S15 = HERE + "/../mini-golf-15s/assets/gen"
GEN = HERE + "/assets/gen"; DATA = HERE + "/data"
os.makedirs(GEN, exist_ok=True)
P = lambda v: int(round(v * 2))
SW, Y0 = 745, 600            # 조각 폭(pt), 띠 위쪽(pt)

NAVY = np.array([11, 30, 107], np.float32)   # 선화 테두리(케이싱): 흰 창·파스텔 타일 위에서도 흰 선이 읽히게

def _dil(m, r):
    """분리형 최대 필터(반경 r px) — 선을 굵게/케이싱 만들기"""
    o = m.copy()
    for d in range(1, r + 1):
        o[:, d:] = np.maximum(o[:, d:], m[:, :-d]); o[:, :-d] = np.maximum(o[:, :-d], m[:, d:])
    m2 = o.copy()
    for d in range(1, r + 1):
        o[d:, :] = np.maximum(o[d:, :], m2[:-d, :]); o[:-d, :] = np.maximum(o[:-d, :], m2[d:, :])
    return o

def whiten(a, keep_red_x=None):
    """3차: 띠의 선화 전부를 흰색 100% 굵은 선(+1px)으로, 남색 케이싱(+3px)을 깐다.
    어두운 채움(나무 속·연못)은 흰색 30% 알파. 빨강은 keep_red_x(px) 오른쪽의 깃발만 남기고 나머지(왕관·모자)는 흰색."""
    a = a.astype(np.float32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    lum = np.maximum(np.maximum(r, g), b)
    gray = (np.abs(r - g) < 14) & (np.abs(g - b) < 14)
    red = (r > 150) & (g < 120) & (b < 120) & (al > 40)
    keep = np.zeros_like(red)
    if keep_red_x is not None: keep[:, keep_red_x:] = red[:, keep_red_x:]
    w = np.where(gray & (lum <= 120), 0.3, 1.0)
    wa = np.clip(al * w * 1.35, 0, 255); wa[keep] = 0
    wa = _dil(wa, 1)
    ca = _dil(wa, 3) * 0.9
    A = wa / 255 + (ca / 255) * (1 - wa / 255)
    col = (255 * (wa / 255)[..., None] + NAVY * ((ca / 255) * (1 - wa / 255))[..., None]) / np.maximum(A, 1e-6)[..., None]
    out = np.zeros(a.shape, np.float32); out[..., :3] = col; out[..., 3] = A * 255
    out[keep] = a[keep]   # 깃발 빨강은 원본 그대로
    return np.clip(out, 0, 255).astype(np.uint8)

HOLES = [  # (번호, 원본, 미러, 지울 사각형 pt(x0,y0,x1,y1) 또는 None, 채울 기둥 x, HUD 실제 문구)
    (1, "terrain-terraces", False, (60, 700, 236, 842.6), 30, "1번 홀 · 파 5 · 계단"),
    (2, "terrain-cascade", True, None, None, "2번 홀 · 파 4 · 폭포"),
    (3, "@plate-ko", False, None, None, "3번 홀 · 파 5 · 절벽 티"),
    (4, "terrain-valley", True, (1700, 760, 1885, 905.5), 1885, "4번 홀 · 파 5 · 계곡"),
    (5, "terrain-ridge", True, None, None, "5번 홀 · 파 4 · 능선"),
    (7, "terrain-summit", False, None, None, "7번 홀 · 파 4 · 산정 그린"),
    (9, "terrain-forest", True, (1690, 840, 1880, 982.0), 1660, "9번 홀 · 파 4 · 숲"),
]
# 연번 클립: 홀 → (장면, 조각 x 시작 pt, 장면 프레임 시작, 프레임 수, 컷 시작 광고 프레임, 장면 띠 위쪽 pt)
SEQ = {
    2: ("cascade-drive", 1175, 4, 24, 170, 480),   # 폭포 티샷: 톱 → 임팩트(≈장면 f18) → 공 출발
    5: ("ridge", 850, 46, 24, 234, 480),           # 능선 급사면 둘째 샷: 임팩트(≈장면 f57)
    7: ("holeout", 1175, 20, 26, 254, 360),        # 산정 그린 퍼트 → 컵인(장면 f44) — 게임 토스트(f49~) 전에 끊는다
}
out = {}
for n, src, mirror, erase, fill_x, hud in HOLES:
    path = f"{S15}/plate-ko.png" if src.startswith("@") else f"{CAP}/{src}.png"
    a = np.array(Image.open(path).convert("RGBA"))
    if erase:
        x0, y0, x1, y1 = erase
        tile = a[P(y0):P(y1) + 16, P(fill_x):P(fill_x + 30)].copy()
        for xx in range(P(x0), P(x1), tile.shape[1]):
            w = min(tile.shape[1], P(x1) - xx)
            a[P(y0):P(y1) + 16, xx:xx + w] = tile[:, :w]
    sx = 1920 - SW if mirror else 0
    Image.fromarray(whiten(a[P(Y0):P(1080), P(sx):P(sx + SW)]), "RGBA").save(f"{GEN}/hole-{n}.png", optimize=True)
    A = a[..., 3].astype(np.float32)
    gy = []
    for x in range(0, 1920):
        col = A[P(700):P(1002), P(x):P(x) + 2].max(axis=1)
        idx = np.nonzero(col > 90)[0]
        gy.append(np.nan if len(idx) == 0 else (P(700) + idx[-1]) / 2 - 0.9)
    v = np.array(gy); xs = np.arange(1920); ok = ~np.isnan(v); v = np.interp(xs, xs[ok], v[ok])
    out[n] = {"sx": sx, "mirror": mirror, "hud": hud, "ground": [round(float(g), 1) for g in v]}
    print(n, src, "slice", sx, "tee ground", round(float(v[153 if not mirror else 1767]), 1))

for n, (scene, sx, s0, cnt, f0, top) in SEQ.items():
    for k in range(cnt):
        a = np.array(Image.open(f"{CAP}/30s/{scene}/f{s0 + k:05d}.png").convert("RGBA"))
        c = whiten(a[P(Y0 - top):P(1080 - top), P(sx):P(sx + SW)], keep_red_x=P(1655 - sx) if scene == "holeout" else None)
        Image.fromarray(c, "RGBA").resize((1118, 720), Image.LANCZOS).save(f"{GEN}/seq-{n}-{k}.png", optimize=True)
    out[n]["seq"] = {"scene": scene, "sx": sx, "s0": s0, "n": cnt, "f0": f0}
    print("seq", n, scene, cnt, "frames from", s0)

for nm in ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"]:
    Image.fromarray(whiten(np.array(Image.open(f"{S15}/{nm}.png").convert("RGBA"))), "RGBA").save(f"{GEN}/{nm}.png", optimize=True)
open(f"{DATA}/holes.js", "w").write("window.HOLES=" + json.dumps(out, separators=(",", ":"), ensure_ascii=False) + ";\n")
