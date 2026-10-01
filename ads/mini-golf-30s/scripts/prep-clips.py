#!/usr/bin/env python3
"""픽셀 클립 준비 — dist/cap/ad/30s/<scene>/ 실캡처 연번(2x 알파 PNG) → assets/gen/clip-<name>-{plate,atlas*}.png + data/clips.js

  python3 scripts/prep-clips.py [name ...]

각 클립: 원본 장면·시간 구간(스트림 기준 초)·잘라 쓸 영역(pt, 1920×1080 데스크탑 좌표)·제외 구간(게임 토스트가 스틱맨에 겹치는 구간 등).
게임 HUD(y ≥ 1001pt)는 모든 클립에서 잘라 낸다 — 한/영 공통, HUD 내용은 광고 타이포로 옮긴다."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tilecodec import encode, decode_check

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = os.path.abspath(HERE + "/../../dist/cap/ad/30s")
GEN = HERE + "/assets/gen"; DATA = HERE + "/data"
os.makedirs(GEN, exist_ok=True); os.makedirs(DATA, exist_ok=True)

# name: (scene, [(t0,t1),...], box pt (x0,y0,x1,y1), mirror, 설명)
CLIPS = {
    "terraces": ("terraces-crown", [(1.95, 6.4)], (0, 690, 1340, 1001), False, "M1 계단 대지 풀파워 드라이브 (R7 재촬영, 왕관) — 착지·바운스까지"),
    "geese":    ("geese", [(9.2, 13.4)], (420, 600, 1120, 1001), False, "M2 거위 떼 — 줄지어 내려와 공 위에 앉고 흩어진다"),
    "dog":      ("dog-crown", [(20.3, 23.3)], (250, 820, 1540, 1001), False, "M3 강아지 — 스틱맨 곁으로 들어와 공을 물고 홀 쪽으로 6m (R8 재촬영, 왕관)"),
    "cuckoo":   ("cuckoo", [(1.8, 4.2)], (0, 0, 880, 1001), False, "M5a 3시 정각 뻐꾸기 + 드라이브 (산정 그린 홀 티) — x ≤ 880pt: 가운데 한국어 토스트('3시 정각')를 잘라 낸다"),
    "holeout":  ("holeout", [(1.9, 3.25), (5.14, 6.95)], (1300, 480, 1920, 900), False, "M5b 7m 퍼트 컵인 → (토스트 구간 건너뜀) → 공 줍기"),
}

def build(name):
    scene, ranges, box, mirror, desc = CLIPS[name]
    d = f"{CAP}/{scene}"
    seg = json.load(open(f"{d}/segment.json"))
    y_off = seg["box_pt"][1]                                  # 추출 밴드의 위쪽(pt)
    rows = [l.split() for l in open(f"{d}/times.txt")]
    frames = [(round(float(p), 4), f"{d}/f{k:05d}.png") for k, (p, w, i) in enumerate(rows)
              if any(a <= float(p) <= b for a, b in ranges)]
    crop = (int(box[0] * 2), int((box[1] - y_off) * 2), int(box[2] * 2), int((box[3] - y_off) * 2))
    meta = encode(frames, f"{GEN}/clip-{name}", crop=crop)
    meta.update({"name": name, "scene": scene, "box": list(box), "ranges": ranges, "mirror": mirror, "desc": desc})
    errs = [decode_check(meta, GEN, frames, k, crop=crop) for k in (0, len(frames) // 2, len(frames) - 1)]
    print(f"{name:9s} frames {len(frames):3d} size {meta['w']}x{meta['h']} unique tiles {meta['uniqueTiles']:5d} avg/frame {meta['avgTiles']:6.1f} atlases {len(meta['atlases'])} decode max err {errs}")
    return meta

if __name__ == "__main__":
    names = sys.argv[1:] or list(CLIPS)
    path = f"{DATA}/clips.json"
    allm = json.load(open(path)) if os.path.exists(path) else {}
    for n in names:
        allm[n] = build(n)
    json.dump(allm, open(path, "w"), separators=(",", ":"))
    open(f"{DATA}/clips.js", "w").write("window.CLIPS=" + json.dumps(allm, separators=(",", ":")) + ";\n")
    print("data/clips.js", os.path.getsize(f"{DATA}/clips.js") // 1024, "KB")

# ── M1 공 경로 (추적 카메라·궤적 보강용): 실캡처에서 공(밝고 둥근 흰 덩어리) 중심을 프레임마다 잰다 → data/paths.js ──
def ball_path(scene, t0, t1, xmin, xmax, y0_pt):
    import cv2, numpy as np
    d = f"{CAP}/{scene}"
    rows = [l.split() for l in open(f"{d}/times.txt")]
    out = []
    for k, (p, w, i) in enumerate(rows):
        p = float(p)
        if not (t0 <= p <= t1): continue
        a = cv2.imread(f"{d}/f{k:05d}.png", cv2.IMREAD_UNCHANGED).astype(int)
        m = ((a[..., 3] > 200) & (a[..., 0] > 238) & (a[..., 1] > 238) & (a[..., 2] > 238)).astype(np.uint8)
        n, lab, st, cen = cv2.connectedComponentsWithStats(m, 8)
        best = None
        for j in range(1, n):
            x, y, w_, h_, area = st[j]
            if 6 <= w_ <= 22 and 6 <= h_ <= 22 and abs(w_ - h_) <= 3 and area >= 150 and xmin * 2 <= cen[j][0] <= xmax * 2 and cen[j][1] / 2 + y0_pt < 1000:
                best = (round(p, 4), round(cen[j][0] / 2, 1), round(y0_pt + cen[j][1] / 2, 1))
        if best: out.append(best)
    return out

if __name__ == "__main__" and (not sys.argv[1:] or "terraces" in sys.argv[1:]):
    seg = json.load(open(f"{CAP}/terraces-crown/segment.json"))
    P = ball_path("terraces-crown", 1.95, 6.45, 60, 1340, seg["box_pt"][1])
    json.dump({"terraces": P}, open(f"{DATA}/paths.json", "w"))
    open(f"{DATA}/paths.js", "w").write("window.PATHS=" + json.dumps({"terraces": P}, separators=(",", ":")) + ";\n")
    print("data/paths.js terraces ball samples", len(P), "first", P[0], "last", P[-1])
