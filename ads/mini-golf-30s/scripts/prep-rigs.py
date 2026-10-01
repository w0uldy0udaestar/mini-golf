#!/usr/bin/env python3
"""리그 트랙 준비 — 게임 --demo-trademark 60Hz 리그 덤프 → data/rigs.js (벡터 스틱맨 재현용)

  python3 scripts/prep-rigs.py

트랙마다: 표본 [st, mode, 10관절(x,y)…, headDx, headDy, phi, len, butt, curved, dir] (st = 게임 씬 시각 초, 트랙 기준 0으로 정규화)
+ STICK 표본 [st, x(pt), groundY(pt, 화면 위 기준)]. 좌표 규약은 게임 StickmanNode와 같다(로컬 px = pt, y 위쪽, 렌더 때 x·headDx·phi에 dir).
  hero  : 15초판 캡처 logs/hero-drive.rig.gz + hero-drive.log (seed2 h3 절벽 티, 왕관, 드라이버 풀스윙 → 트레이드마크 → 걷기)
  whiff : 30초판 캡처 memes 런 (seed1 h1 계단 대지, 밀짚모자) — 쇼피스 whiffSpin 구간
"""
import gzip, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CAP15 = os.path.abspath(HERE + "/../../dist/cap/ad/logs")
CAP30 = os.path.abspath(HERE + "/../../dist/cap/ad/30s")
DATA = HERE + "/data"

RIG = re.compile(r"^([\d.]+) RIG\[([\d.]+)\] (\w+) (.*)$")
STICK = re.compile(r"STICK\[([\d.]+)\] (-?\d+) (-?\d+) (\d+) (\w+)")

def parse_rig_line(recv, st, mode, rest):
    p = rest.split()
    pts = [tuple(map(float, q.split(","))) for q in p[:10]]
    kv = dict(zip(p[10::2], p[11::2]))
    hx, hy = map(float, kv["head"].split(","))
    return [round(float(st), 4), mode] + [round(v, 2) for xy in pts for v in xy] + \
           [hx, hy, float(kv["phi"]), float(kv["len"]), float(kv["butt"]), int(kv["curved"]), int(kv["dir"])], float(recv)

def load(lines):
    rig, recv, stick = [], [], []
    for l in lines:
        m = RIG.match(l.strip())
        if m:
            r, rv = parse_rig_line(*m.groups()); rig.append(r); recv.append(rv); continue
        m = STICK.search(l)
        if m:  # STICK[벽시계] x y(지면, 아래 기준) H mode
            stick.append((float(m.group(1)), int(m.group(2)), int(m.group(4)) - int(m.group(3)), m.group(5)))
    return rig, recv, stick

def track(rig, recv, stick, st0, st1, name):
    # 씬 시각 ↔ 벽시계: 수신 지연은 더해지기만 한다 → 하위 5% 오프셋 (15초판 prep과 같은 방식)
    offs = sorted(rv - r[0] for r, rv in zip(rig, recv)); off = offs[len(offs) // 20]
    sel = [r for r in rig if st0 <= r[0] <= st1]
    t0 = sel[0][0]
    samples = [[round(r[0] - t0, 4)] + r[1:] for r in sel]
    sticks = [[round(w - off - t0, 3), x, gy, mode] for (w, x, gy, mode) in stick if st0 - 1 <= w - off <= st1 + 1]
    print(f"{name}: {len(samples)} samples {samples[-1][0]:.2f}s · stick {len(sticks)} · modes {sorted(set(s[1] for s in samples))} · off {off:.3f}")
    return {"t0": t0, "wallOffset": off, "samples": samples, "stick": sticks}

out = {}
# hero — 15초판 절벽 티
rig, recv, stick = load(gzip.open(f"{CAP15}/hero-drive.rig.gz", "rt"))
_, _, stick2 = load(open(f"{CAP15}/hero-drive.log"))
out["hero"] = track(rig, recv, stick2, 618045.9, 618063.5, "hero")
# whiff — memes 런 쇼피스
log = open(f"{CAP30}/whiffspin/game.log").read().splitlines()
rig, recv, stick = load(log)
show = [l for l in log if "SHOWPIECE whiffSpin" in l][0]
wall_show = float(show.split()[0])
offs = sorted(rv - r[0] for r, rv in zip(rig, recv)); off = offs[len(offs) // 20]
st_show = wall_show - off
out["whiff"] = track(rig, recv, stick, st_show - 1.5, st_show + 4.5, "whiff")
out["whiff"]["showpiece"] = {"x": int(show.split()[3]), "groundFromBottom": int(show.split()[4]), "dur": float(show.split()[5]), "at": round(st_show - out["whiff"]["t0"], 3)}
os.makedirs(DATA, exist_ok=True)
open(f"{DATA}/rigs.js", "w").write("window.RIGS=" + json.dumps(out, separators=(",", ":")) + ";\n")
print("data/rigs.js", os.path.getsize(f"{DATA}/rigs.js") // 1024, "KB")
