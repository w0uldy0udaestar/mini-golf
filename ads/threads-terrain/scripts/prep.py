#!/usr/bin/env python3
"""T2 「홀마다 다른 산」 데이터 (3차: 지형 실루엣 중심). 게임 코스 생성기·탄도 엔진을 그대로 부르는 tools/coursedump(GolfCore 링크)로
홀 지형(1m 표고·구간·나무)과 샷 궤적(240Hz → 120Hz)을 뽑아 **화면 px**로 바꿔 data/cuts.js에 쓴다.

  swiftc -O -I .build/debug ads/threads-terrain/tools/coursedump.swift .build/debug/GolfCore.o -o <bin>/coursedump
  COURSEDUMP=<bin>/coursedump python3 scripts/prep.py

화면 맵: 지형의 핵심 구간 [xa, xb](m)을 x 60–1020(폭 89%)에. 세로는 실제 표고 × 과장(가로 px/m의 2.5~8배 — 실루엣 높이 ≤ 760px),
실루엣 바닥 y≈1460. 공은 같은 맵(접지점 → 반지름만큼 위가 중심). 여러 샷(산정 계단 오르기)은 이어 붙인다. 화산 컷은 ../threads-volcano 데이터.
"""
import json, os, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
BIN = os.environ.get("COURSEDUMP", "coursedump")
R_BALL = 14
CUTS = [
    dict(key="cliff", word="절벽", bg="#36A2F0", ink="#0E0E10", seed=2, hole=3, win=[18, 172], shots=[(54.2, "7I", 0.35, "standard", "tee")], hatch=True, ybot=1650, hmax=800),
    dict(key="canyon", word="협곡", bg="#E08F2C", ink="#0E0E10", seed=3, hole=1, win=[112, 238], shots=[(186.0, "9I", 0.71, "standard", "rough")], hatch=True),
    dict(key="cascade", word="폭포", bg="#EA4F8C", ink="#0E0E10", seed=6, hole=4, win=[28, 468], shots=[(50.0, "DR", 0.81, "punch", "tee")]),
    dict(key="summit", word="산정", bg="#7B4CDF", ink="#FFFFFF", seed=1, hole=7, win=[96, 345],
         shots=[(110.0, "8I", 0.42, "standard", "fairway"), (165.1, "8I", 0.60, "lob", "fairway"), (230.2, "8I", 0.62, "standard", "fairway")]),
    dict(key="island", word="섬", bg="#22A35B", ink="#FFFFFF", seed=1, hole=8, win=[146, 236], shots=[(25.0, "6I", 0.72, "standard", "tee")]),
    dict(key="ridge", word="능선", bg="#F2662B", ink="#0E0E10", seed=2, hole=6, win=[108, 300], shots=[(155.0, "9I", 0.60, "standard", "fairway")]),
    dict(key="terraces", word="계단", bg="#0FA597", ink="#FFFFFF", seed=1, hole=1, win=[20, 440], shots=[(49.0, "DR", 0.72, "punch", "tee")]),
    dict(key="forest", word="숲", bg="#2D3FA8", ink="#FFFFFF", seed=3, hole=6, win=[142, 445], shots=[(156.3, "5I", 0.35, "punch", "fairway")]),
]
def run(*a): return json.loads(subprocess.run([BIN, *map(str, a)], capture_output=True, text=True, check=True).stdout)
out = []
for c in CUTS:
    hj = run("hole", c["seed"], c["hole"]); e = hj["elev"]
    xa, xb = c["win"]; hpx = 960 / (xb - xa)
    win = e[int(xa):int(xb) + 1]; emin, emax = min(win), max(win)
    hmax = c.get("hmax", 760); ybot = c.get("ybot", 1460)
    vx = max(2.5, min(8.0, hmax / max(1e-6, (emax - emin) * hpx)))
    vpx = hpx * vx; hext = (emax - emin) * vpx
    X = lambda x: 60 + (x - xa) * hpx
    Y = lambda z: ybot - (z - emin) * vpx
    gr = lambda x: e[int(min(len(e) - 2, max(0, x)))] * (1 - (x - int(x))) + e[int(min(len(e) - 2, max(0, x))) + 1] * (x - int(x))
    surf = lambda x: next((s["type"] for s in hj["segs"] if s["from"] <= x < s["to"]), "rough")
    terr = [[round(X(x), 1), round(Y(e[x]), 1), surf(x + 0.5)] for x in range(int(xa) - 4, int(xb) + 5)]
    # 샷(여러 개면 이어 붙임): 첫 바운스까지 + 0.45s, 그 뒤는 0.3s에 걸쳐 정지점으로
    ball, evs, t0 = [], [], 0.0
    for k, (x0, club, h, shape, lie) in enumerate(c["shots"]):
        sim = run("sim", c["seed"], c["hole"], x0, club, h, shape, lie)
        fb = next((v for v in sim["ev"] if v[1] in ("bounce", "water", "holed")), None)
        tcut = sim["t"] if len(c["shots"]) == 1 else min(sim["t"], fb[0] + 0.45)
        for p in sim["pts"]:
            if p[0] <= tcut: ball.append([round(t0 + p[0], 4), round(X(p[1]), 1), round(Y(p[2]) - R_BALL, 1)])
        if len(c["shots"]) > 1 and tcut < sim["t"]:
            lx, ly = ball[-1][1], ball[-1][2]; rx, ry = X(sim["rest"][0]), Y(sim["rest"][1]) - R_BALL
            for q in range(1, 13):
                u = q / 12; ball.append([round(t0 + tcut + 0.3 * u, 4), round(lx + (rx - lx) * u, 1), round(ly + (ry - ly) * u, 1)])
            tcut += 0.3
        for v in sim["ev"]:
            if v[0] <= tcut: evs.append([round(t0 + v[0], 4), v[1], round(X(v[2]), 1), round(v[3], 2) if len(v) > 3 else 0])
        t0 += tcut + (0.12 if k < len(c["shots"]) - 1 else 0)
    land = next(v for v in reversed(evs) if v[1] in ("bounce", "water")) if len(c["shots"]) > 1 else next(v for v in evs if v[1] in ("bounce", "water"))
    trees = []
    for o in hj["obs"]:
        if o["kind"] == "tree" and xa <= o["x"] <= xb:
            g = gr(o["x"]); bottom = Y(g + o["cy"] - o["size"]); rpx = max(o["size"] * hpx, 78)
            trees.append([round(X(o["x"]), 1), round(Y(g), 1), round(bottom - rpx, 1), round(rpx, 1), round(bottom, 1)])
    flag = [round(X(hj["holeX"]), 1), round(Y(gr(hj["holeX"])), 1)] if xa + 3 <= hj["holeX"] <= xb - 3 else None
    x0 = c["shots"][0][0]
    stick = [round(X(x0), 1), round(Y(gr(x0)), 1)] if xa <= x0 <= xb else None
    out.append({**{k: v for k, v in c.items() if k not in ("shots",)}, "club": c["shots"][0][1], "hpx": hpx, "vx": vx, "terr": terr, "trees": trees, "flag": flag,
                "ball": ball, "ev": evs, "land": land, "stick": stick, "T": round(t0, 3)})
    print(c["key"], f"hpx {hpx:.2f} vx {vx:.2f}(실제 대비 ×{vx:.1f}) 높이 {hext:.0f}px land {land[1]}@{land[0]:.2f}s x{land[2]} trees {len(trees)} flag {flag is not None} stick {stick is not None} T {t0:.2f} ev {len(evs)}")
vol = open(HERE + "/../threads-volcano/data/scene.js").read()
open(HERE + "/data/cuts.js", "w").write("window.CUTS=" + json.dumps(out, separators=(",", ":"), ensure_ascii=False) + ";\n" + vol)
print("wrote data/cuts.js")
