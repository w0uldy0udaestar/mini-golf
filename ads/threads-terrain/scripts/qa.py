#!/usr/bin/env python3
"""T2 홀마다 다른 산 QA — python3 scripts/qa.py <mp4> [두 번째 렌더 mp4(결정론 비교)] → JSON을 stdout과 dist/ads/threads/t2-volcano-qa.json에

  1) ffprobe: 해상도·fps·길이·프레임 수·코덱
  2) 프레임 차분: 135×240(INTER_AREA) BGR 평균 절대차 — 최대 ≤ 12, A-B-A(1~2프레임 튐) 0
  3) 정지 비율: 480px 폭 회색 평균 밝기차 < 0.35인 프레임 비율(참고)
  4) 광과민성: qa/flash-check.py — general ≤ 1, red 0
  5) 안전 영역: vertical.html?audit=1 → 글자·공·컵+깃발·스틱맨 사각형. 스레드 기준 x 70–930, y 300–1620(아래 300·오른쪽 150은 UI)
  6) 첫 프레임: 페이드인 아님(밝은 선화 픽셀 수가 f1과 같은 수준)
  7) 결정론: 두 렌더의 디코드 프레임이 같은가(최대 픽셀 차)
"""
import html, json, re, subprocess, sys, os
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUTD = os.path.abspath(HERE + "/../../dist/ads/threads")
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vcodec": v["codec_name"], "profile": v.get("profile"), "pix": v.get("pix_fmt"), "audio": (a[0]["codec_name"] if a else None)}

def frames(p):
    cap = cv2.VideoCapture(p); out = []
    while True:
        ok, im = cap.read()
        if not ok: break
        out.append(im)
    return out

def diff_scan(fr):
    sm = [cv2.resize(f, (135, 240), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    d = [0.0] + [float(np.abs(sm[i] - sm[i - 1]).mean()) for i in range(1, len(sm))]
    aba = []
    for i in range(1, len(sm) - 1):
        d1, d2 = d[i], d[i + 1]; d0 = float(np.abs(sm[i + 1] - sm[i - 1]).mean())
        if min(d1, d2) >= 3 and d0 < 0.5 * min(d1, d2): aba.append(i)
    mx = int(np.argmax(d))
    return {"max": round(d[mx], 2), "maxFrame": mx, "over12": [i for i in range(len(d)) if d[i] > 12], "aba": aba,
            "top5": sorted([(i, round(d[i], 2)) for i in range(len(d))], key=lambda x: -x[1])[:5]}

def hold_ratio(fr):
    g = [cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (480, 853), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    still = [float(np.abs(g[i] - g[i - 1]).mean()) < 0.35 for i in range(1, len(g))]
    # 가장 긴 연속 정지(초) — 죽은 시간 감시
    best = run = 0
    for s in still:
        run = run + 1 if s else 0; best = max(best, run)
    return {"ratio": round(sum(still) / len(still), 3), "longestStillSec": round(best / 30, 2)}

def flash(p):
    r = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", p, "--json", "/dev/stdout"], capture_output=True, text=True)
    return {"exit": r.returncode, "out": r.stdout[-900:].strip()}

def audit():
    s = subprocess.run([CH, "--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--virtual-time-budget=30000", "--window-size=1080,1920",
                        "--dump-dom", f"file://{os.path.abspath(HERE)}/vertical.html?audit=1"], capture_output=True, text=True).stdout
    d = json.loads(html.unescape(re.search(r'<pre id="audit">(.*?)</pre>', s, re.S).group(1)))
    zones = {"threads": (70, 300, 930, 1620), "shorts": (70, 300, 1010, 1500)}
    res = {}
    for zn, (X0, Y0, X1, Y1) in zones.items():
        viol = {}
        for fr in d["frames"]:
            for it in fr["items"]:
                x0, y0, x1, y1 = it["r"]
                if x0 < X0 or y0 < Y0 or x1 > X1 or y1 > Y1:
                    v = viol.setdefault(it["name"], {"samples": 0, "frames": [], "worst": None})
                    v["samples"] += 1; v["frames"].append(fr["f"])
                    if v["worst"] is None: v["worst"] = [fr["f"], it["r"]]
        for v in viol.values(): v["frames"] = [v["frames"][0], v["frames"][-1]]
        res[zn] = viol
    return {"violations": res, "cams": d.get("cams")}

p = sys.argv[1]
fr = frames(p)
res = {"file": p, "probe": probe(p), "decoded": len(fr), "diff": diff_scan(fr), "hold": hold_ratio(fr), "flash": flash(p), "audit": audit()}
lum = lambda f: int((cv2.cvtColor(f, cv2.COLOR_BGR2GRAY) > 180).sum())
res["firstFrame"] = {"bright_f0": lum(fr[0]), "bright_f1": lum(fr[1]), "mean_f0": round(float(fr[0].mean()), 2), "mean_f1": round(float(fr[1].mean()), 2)}
if len(sys.argv) > 2:
    fr2 = frames(sys.argv[2])
    md = max(int(np.abs(a.astype(np.int16) - b.astype(np.int16)).max()) for a, b in zip(fr, fr2)) if len(fr2) == len(fr) else None
    nd = sum(1 for a, b in zip(fr, fr2) if not np.array_equal(a, b)) if len(fr2) == len(fr) else None
    res["determinism"] = {"frames2": len(fr2), "maxPixelDiff": md, "framesDiffering": nd}
os.makedirs(OUTD, exist_ok=True)
json.dump(res, open(OUTD + "/t2-terrain-qa.json", "w"), ensure_ascii=False, indent=1)
print(json.dumps(res, ensure_ascii=False, indent=1)[:6000])
