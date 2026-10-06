"""캡처 로그(scripts/capture-window.py가 남긴 log.txt) → 리그 표본 목록. prep.py·calib.py가 같이 쓴다.

한 줄: `[ 1.23] RIG[106924.446] aim x,y ×10 head dx,dy phi P len L butt B curved C dir D`
좌표는 facing 로컬(px=pt, 지면 0, y 위) — 렌더는 x·head dx·phi에 dir을 곱한다(게임 StickmanNode 규칙).
"""
import os, re

CAP = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../dist/cap/threads-swings"))
LINE = re.compile(r"\[\s*([\d.]+)\] RIG\[([\d.]+)\] (\w+) (.*)")
STICK = re.compile(r"\[\s*([\d.]+)\] STICK\[([\d.]+)\] (\d+) (\d+) (\d+) (\w+)")


def load(name):
    rows, sticks, events = [], [], []
    for l in open(f"{CAP}/{name}/log.txt"):
        m = LINE.match(l)
        if m:
            p = m.group(4).split()
            kv = dict(zip(p[10::2], p[11::2]))
            rows.append({
                "recv": float(m.group(1)), "st": float(m.group(2)), "mode": m.group(3),
                "pts": [list(map(float, q.split(","))) for q in p[:10]],
                "head": list(map(float, kv["head"].split(","))), "phi": float(kv["phi"]), "len": float(kv["len"]),
                "butt": float(kv["butt"]), "curved": int(kv["curved"]), "dir": int(kv["dir"]),
            })
            continue
        m = STICK.match(l)
        if m:
            sticks.append({"recv": float(m.group(1)), "x": int(m.group(3)), "gy": int(m.group(4)), "h": int(m.group(5)), "mode": m.group(6)})
            continue
        m = re.match(r"\[\s*([\d.]+)\] (.*)", l)
        if m:
            events.append((float(m.group(1)), m.group(2).strip()))
    return rows, sticks, events


def impact(rows):
    """임팩트 = 다운스윙 중 클럽각 phi가 2π(샤프트 수직 아래)를 지나는 순간 (선형 보간, 장면 시각)."""
    import math
    two = 2 * math.pi
    for a, b in zip(rows, rows[1:]):
        if a["mode"] in ("swinging", "motion") and a["phi"] < two <= b["phi"] and b["st"] - a["st"] < 0.05:
            u = (two - a["phi"]) / (b["phi"] - a["phi"])
            return a["st"] + u * (b["st"] - a["st"])
    raise SystemExit("impact not found")
