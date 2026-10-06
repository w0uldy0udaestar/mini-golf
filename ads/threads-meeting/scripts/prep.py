#!/usr/bin/env python3
"""T3 회의 중 9홀 — 데이터 준비 (4차: 화면에 캡처 비트맵 0장, 전부 벡터).

  swiftc -O -I .build/debug ads/threads-terrain/tools/coursedump.swift .build/debug/GolfCore.o -o <bin>/coursedump
  COURSEDUMP=<bin>/coursedump python3 scripts/prep.py   → data/holes.js

1) 지형: 게임 코스 생성기(GolfCore CourseGenerator.makeCourse)의 1m 표고·구간·장애물을 coursedump로 받아
   GameScene과 같은 식으로 화면 pt로 바꾼다: pxPerM = 1920/worldW, vScale = min(1.4, max(1, min(9/pxPerM, (1080−136)/((표고 폭+66)·pxPerM)))),
   groundBase = max(96, 84 − 최저 표고·pyPerM), y = 1080 − (groundBase + 표고·pyPerM)  (ads/threads-terrain/scripts/prep.py 와 같은 식).
   지형선·러프 틱·그린·물·나무·깃발을 세로 조각(745pt) 좌표의 벡터로 저장한다.
2) 리그: 2·5·7번 홀 컷은 30초판 실캡처 때 함께 받은 60Hz 리그 덤프(dist/cap/ad/30s/<장면>/game.log의 RIG 줄)를
   캡처 프레임 벽시계(times.txt)에 맞춰 컷 프레임마다 한 포즈씩 뽑는다(15초판 prep.py와 같은 정렬, 캡처 지연 53ms 보정).
   샷·컵인 시각(PLAY SHOT / PLAY HOLED)도 컷 프레임으로 바꿔 저장한다(공은 이 시각에 맞춘 코드 근사).
"""
import json, os, re, subprocess
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP = HERE + "/../../dist/cap/ad"
DATA = HERE + "/data"
BIN = os.environ.get("COURSEDUMP", "coursedump")
SW = 745
run = lambda *a: json.loads(subprocess.run([BIN, *map(str, a)], capture_output=True, text=True, check=True).stdout)

HOLES = {  # 광고 홀 → (시드, 홀, 조각 x 시작 pt, HUD 실제 문구)  — 시드·홀은 coursedump list로 아키타입을 확인했다
    1: (1, 1, 0, "1번 홀 · 파 5 · 계단"), 2: (1, 2, 1175, "2번 홀 · 파 4 · 폭포"), 3: (2, 3, 0, "3번 홀 · 파 5 · 절벽 티"),
    4: (2, 4, 1175, "4번 홀 · 파 5 · 계곡"), 5: (1, 5, 850, "5번 홀 · 파 4 · 능선"), 7: (1, 7, 1175, "7번 홀 · 파 4 · 산정 그린"),
    9: (1, 9, 1175, "9번 홀 · 파 4 · 숲"),
}
out = {}
for n, (seed, hn, sx, hud) in HOLES.items():
    hj = run("hole", seed, hn)
    e = np.array(hj["elev"], float); W = hj["worldW"]; ppm = 1920 / W
    vs = min(1.4, max(1.0, min(9 / ppm, (1080 - 136) / ((e.max() - e.min() + 66) * ppm))))
    pyp = ppm * vs; base = max(96, 84 - e.min() * pyp)
    Y = lambda z: 1080 - (base + z * pyp)
    gr = lambda xm: float(np.interp(xm, np.arange(len(e)), e))
    segs = hj["segs"]
    surf = lambda xm: next((s["type"] for s in segs if s["from"] <= xm < s["to"]), "fairway")
    ground = [round(Y(gr(x / ppm)), 2) for x in range(1920)]
    loc = lambda xpt: round(xpt - sx, 2)
    x0m, x1m = (sx - 20) / ppm, (sx + SW + 20) / ppm
    line = [[loc(x * ppm), round(Y(gr(x)), 2)] for x in np.arange(max(0, x0m), min(len(e) - 1, x1m), 0.5)]
    ticks, lean = [], False
    for g in np.arange(max(0, x0m) + 0.9, min(len(e) - 1, x1m), 1.5):
        if surf(g) == "rough": ticks.append([loc(g * ppm), round(Y(gr(g)), 2), 1 if lean else 0])
        lean = not lean
    gs, ge = hj["greenStart"], hj["greenEnd"]
    green = [[loc(x * ppm), round(Y(gr(x)), 2)] for x in np.arange(gs, ge + 0.01, 0.5)] if ge * ppm > sx - 20 and gs * ppm < sx + SW + 20 else []
    water = []
    for s in segs:
        if s["type"] == "water" and s["to"] * ppm > sx and s["from"] * ppm < sx + SW:
            lvl = min(Y(gr(s["from"])), Y(gr(s["to"])))
            water.append({"lvl": round(lvl, 2), "pts": [[loc(x * ppm), round(Y(gr(x)), 2)] for x in np.arange(s["from"], s["to"] + 0.01, 0.5)]})
    trees = [[loc(o["x"] * ppm), round(Y(gr(o["x"])), 2), round(Y(gr(o["x"]) + o["cy"]), 2), round(o["size"] * ppm, 2)]
             for o in hj["obs"] if o["kind"] == "tree" and sx - 40 < o["x"] * ppm < sx + SW + 40]
    flag = [loc(hj["holeX"] * ppm), round(Y(gr(hj["holeX"])), 2)] if sx - 10 < hj["holeX"] * ppm < sx + SW + 10 else None
    out[n] = {"sx": sx, "mirror": hj["teeX"] > W / 2, "hud": hud, "ppm": round(ppm, 4), "ground": ground, "line": line, "ticks": ticks,
              "green": green, "water": water, "trees": trees, "flag": flag, "teeX": round(hj["teeX"] * ppm, 2)}
    print(n, f"seed {seed} h{hn} {hj['sig']} ppm {ppm:.3f} vs {vs:.2f} tee {hj['teeX'] * ppm:.0f}pt y {Y(gr(hj['teeX'])):.1f} · line {len(line)} ticks {len(ticks)} trees {len(trees)} flag {flag} water {len(water)}")

# ── 2·5·7번 컷: 30초판 60Hz 리그 → 컷 프레임별 포즈 ──
SEQ = {2: ("cascade-drive", 4, 24, 170), 5: ("ridge", 46, 24, 234), 7: ("holeout", 20, 26, 254)}
CAP_LAG = 0.053
for n, (scene, s0, cnt, f0) in SEQ.items():
    log = open(f"{CAP}/30s/{scene}/game.log").read().splitlines()
    rig, stick, ev = [], [], {}
    for l in log:
        p = l.split()
        if len(p) > 2 and p[1].startswith("RIG["):
            st = float(p[1][4:-1]); xy = [tuple(map(float, q.split(","))) for q in p[3:13]]; kv = dict(zip(p[13::2], p[14::2]))
            rig.append({"recv": float(p[0]), "st": st, "mode": p[2], "pts": xy, "head": list(map(float, kv["head"].split(","))), "phi": float(kv["phi"]),
                        "len": float(kv["len"]), "butt": float(kv["butt"]), "curved": int(kv["curved"]), "dir": int(kv["dir"])})
        m = re.search(r"STICK\[([\d.]+)\] (\d+)", l)
        if m: stick.append((float(m.group(1)), int(m.group(2))))
        if "PLAY SHOT" in l: ev.setdefault("shots", []).append((float(p[0]), float(re.search(r"from ([\d.]+)", l).group(1))))
        if "PLAY HOLED" in l: ev["holed"] = float(p[0])
    off = np.percentile([r["recv"] - r["st"] for r in rig], 5)
    ws = np.array([r["st"] + off for r in rig])
    times = [l.split() for l in open(f"{CAP}/30s/{scene}/times.txt")]
    frames = []
    for k in range(cnt):
        w = float(times[s0 + k][1]) - CAP_LAG
        i = int(np.clip(np.searchsorted(ws, w), 1, len(rig) - 1)); a, b = rig[i - 1], rig[i]
        u = float(np.clip((w - ws[i - 1]) / max(1e-6, ws[i] - ws[i - 1]), 0, 1)); L = lambda p, q: p + (q - p) * u
        sx_ = float(np.interp(w, [s[0] + off for s in stick], [s[1] for s in stick]))
        frames.append({"pts": [[round(L(p[0], q[0]), 2), round(L(p[1], q[1]), 2)] for p, q in zip(a["pts"], b["pts"])],
                       "head": [round(L(a["head"][j], b["head"][j]), 2) for j in (0, 1)], "phi": round(L(a["phi"], b["phi"]), 4),
                       "len": round(L(a["len"], b["len"]), 2), "butt": round(L(a["butt"], b["butt"]), 2),
                       "curved": a["curved"] if u < .5 else b["curved"], "dir": a["dir"], "x": round(sx_, 2)})
    walls = [float(times[s0 + k][1]) for k in range(cnt)]
    shot = next((sh for sh in ev["shots"] if walls[0] - 1.5 <= sh[0] <= walls[-1] + 0.5), None)   # 이 컷 구간의 샷
    ev["shot"] = shot[0] if shot else None
    if shot:   # 샷 컷의 스틱맨은 공 자리(from m × ppm)에 서 있다 — STICK 로그는 드문드문이라 이 값이 정확하다
        for fr in frames: fr["x"] = round(shot[1] * out[n]["ppm"], 2)
    tof = lambda w: round(f0 + float(np.interp(w, walls, range(cnt))), 2) if w is not None else None
    out[n]["seq"] = {"f0": f0, "n": cnt, "rig": frames, "shotF": tof(ev.get("shot")), "holedF": tof(ev.get("holed"))}
    print("seq", n, scene, cnt, "shotF", out[n]["seq"]["shotF"], "holedF", out[n]["seq"]["holedF"], "stick x", frames[0]["x"], "dir", frames[0]["dir"])
open(f"{DATA}/holes.js", "w").write("window.HOLES=" + json.dumps(out, separators=(",", ":"), ensure_ascii=False) + ";\n")
