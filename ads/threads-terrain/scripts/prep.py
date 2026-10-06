#!/usr/bin/env python3
"""T2 「홀마다 다른 산」 데이터: 게임 코스 생성기·탄도 엔진을 그대로 부르는 tools/coursedump(GolfCore 링크)로
홀 지형(1m 표고·구간·나무)과 샷 궤적(240Hz 시뮬레이션 → 120Hz)을 뽑아, 게임 화면 좌표(1920×1080pt, 좌상단 원점)로 바꿔 data/cuts.js에 쓴다.

  swiftc -O -I .build/debug ads/threads-terrain/tools/coursedump.swift .build/debug/GolfCore.o -o <bin>/coursedump
  COURSEDUMP=<bin>/coursedump python3 scripts/prep.py

화면 좌표 변환은 GameScene과 같다: pxPerM = 1920/worldW, 세로 과장 vScale = min(1.4, max(1, min(9/pxPerM, (1080−136)/((표고 폭+66)·pxPerM)))),
groundBase = max(96, 84 − 최저 표고·pyPerM), y = 1080 − (groundBase + 표고·pyPerM). 공 중심 = 접지점 + 5.5pt(게임 ballNode와 같다).
화산 컷은 ../threads-volcano/data/scene.js(실캡처·리그 덤프)를 그대로 쓴다.
"""
import json, os, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
BIN = os.environ.get("COURSEDUMP", "coursedump")
CUTS = [  # 시드·홀은 coursedump list로 찾은 아키타입. 샷은 원하는 장면이 나오는 값을 같은 엔진으로 탐색해 골랐다(scripts 주석 참고)
    dict(key="cliff", word="절벽", bg="#36A2F0", ink="#0E0E10", seed=2, hole=3, x0=54.2, club="7I", h=0.35, shape="standard", lie="tee"),
    dict(key="canyon", word="협곡", bg="#E08F2C", ink="#0E0E10", seed=1, hole=3, x0=151.0, club="PW", h=0.70, shape="standard", lie="fairway"),
    dict(key="cascade", word="폭포", bg="#0FA597", ink="#FFFFFF", seed=4, hole=3, x0=200.0, club="7I", h=0.24, shape="standard", lie="fairway"),
    dict(key="summit", word="산정", bg="#7B4CDF", ink="#FFFFFF", seed=1, hole=7, x0=270.0, club="8I", h=0.44, shape="lob", lie="fairway"),
    dict(key="island", word="섬", bg="#22A35B", ink="#FFFFFF", seed=1, hole=8, x0=25.0, club="6I", h=0.72, shape="standard", lie="tee"),
    dict(key="ridge", word="능선", bg="#F2662B", ink="#0E0E10", seed=2, hole=6, x0=155.0, club="9I", h=0.60, shape="standard", lie="fairway"),
    dict(key="terraces", word="계단", bg="#EA4F8C", ink="#0E0E10", seed=1, hole=1, x0=49.0, club="3W", h=0.50, shape="standard", lie="tee"),
    dict(key="forest", word="숲", bg="#2D3FA8", ink="#FFFFFF", seed=3, hole=6, x0=156.3, club="5I", h=0.35, shape="punch", lie="fairway"),
]
def run(*a): return json.loads(subprocess.run([BIN, *map(str, a)], capture_output=True, text=True, check=True).stdout)
out = []
for c in CUTS:
    hj = run("hole", c["seed"], c["hole"])
    sim = run("sim", c["seed"], c["hole"], c["x0"], c["club"], c["h"], c["shape"], c["lie"])
    e = hj["elev"]; W = hj["worldW"]; ppm = 1920 / W
    vs = min(1.4, max(1.0, min(9 / ppm, (1080 - 136) / ((max(e) - min(e) + 66) * ppm))))
    pyp = ppm * vs; base = max(96, 84 - min(e) * pyp)
    Y = lambda z: 1080 - (base + z * pyp)
    gr = lambda x: e[int(min(len(e) - 2, max(0, x)))] * (1 - (x - int(x))) + e[int(min(len(e) - 2, max(0, x))) + 1] * (x - int(x))
    ev = [x for x in sim["ev"] if x[1] in ("bounce", "water", "holed")]
    land = ev[0]
    xs = [p[1] for p in sim["pts"]]
    xa, xb = max(0, min(xs + [c["x0"]]) - 70), min(len(e) - 1, max(xs) + 70)
    surf = lambda x: next((s["type"] for s in hj["segs"] if s["from"] <= x < s["to"]), "rough")
    terr = [[round(x * ppm, 2), round(Y(e[x]), 2), surf(x + 0.5)] for x in range(int(xa), int(xb) + 1)]
    ticks = []; lean = False; g = xa + 0.9
    while g < xb:
        if surf(g) == "rough": ticks.append([round(g * ppm, 2), round(Y(gr(g)), 2), 1 if lean else 0])
        lean = not lean; g += 1.5
    trees = [[round(o["x"] * ppm, 2), round(Y(gr(o["x"])), 2), round(Y(gr(o["x"]) + o["cy"]), 2), round(o["size"] * ppm, 2)]
             for o in hj["obs"] if o["kind"] == "tree" and xa <= o["x"] <= xb]
    flag = [round(hj["holeX"] * ppm, 2), round(Y(gr(hj["holeX"])), 2)] if xa <= hj["holeX"] <= xb else None
    ball = [[p[0], round(p[1] * ppm, 2), round(Y(p[2]) - 5.5, 2)] for p in sim["pts"]]
    out.append({**c, "ppm": ppm, "vs": vs, "terr": terr, "ticks": ticks, "trees": trees, "flag": flag, "ball": ball,
                "land": [land[0], land[1], round(land[2] * ppm, 2)], "rest": [round(sim["rest"][0] * ppm, 2), round(Y(sim["rest"][1]) - 5.5, 2)],
                "simT": sim["t"], "stick": [round(c["x0"] * ppm, 2), round(Y(gr(c["x0"])), 2)]})
    print(c["key"], f"ppm {ppm:.2f} vs {vs:.2f} land {land[1]}@{land[0]:.2f}s x{land[2]:.1f} rest {sim['rest'][0]:.1f} t {sim['t']:.2f} pts {len(ball)} terr {len(terr)} trees {len(trees)} flag {flag is not None}")
vol = open(HERE + "/../threads-volcano/data/scene.js").read()
open(HERE + "/data/cuts.js", "w").write("window.CUTS=" + json.dumps(out, separators=(",", ":"), ensure_ascii=False) + ";\n" + vol)
print("wrote data/cuts.js")
