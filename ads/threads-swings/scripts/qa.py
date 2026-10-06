#!/usr/bin/env python3
"""T4 QA — 측정만 한다(보고서는 dist/ads/threads/t4-swings-qa.md에 사람이 쓴다). 결과 JSON: dist/ads/threads/t4-swings-qa.json

  python3 scripts/qa.py <mp4> [<mp4 두 번째 렌더>]

  1) ffprobe: 해상도·fps·길이·코덱
  2) 프레임 차분: 135×240 INTER_AREA 평균 절대차 — 최대·12 초과 프레임·A-B-A
  3) 멈춤: 480px 회색 평균차 < 0.35 프레임 비율과 가장 긴 연속 정지
  4) 광과민성: qa/flash-check.py (공용 QA 키트 복사본)
  5) 안전 영역: 컴포지션 ?audit=1 → 글자·스틱맨 사각형이 x 70–930(오른쪽 150px 스레드 UI), y 100–1620(아래 300px 스레드 UI) 안인가
  6) 첫 프레임: 평균 밝기·스틱맨 화소가 이미 있는가(페이드인 없음)
  7) 결정론: 두 렌더의 디코드 프레임 최대 화소차
"""
import html, json, re, subprocess, sys, os
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = os.path.abspath(HERE + "/../../dist/ads/threads")
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vcodec": v["codec_name"], "profile": v.get("profile"), "pix": v.get("pix_fmt"), "audio": bool(a)}


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
    return {"max": round(max(d), 2), "maxFrame": int(np.argmax(d)), "over12": [i for i in range(len(d)) if d[i] > 12], "aba": aba,
            "top6": sorted([(i, round(d[i], 2)) for i in range(len(d))], key=lambda x: -x[1])[:6]}


def holds(fr):
    g = [cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (480, 853), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    still = [float(np.abs(g[i] - g[i - 1]).mean()) < 0.35 for i in range(1, len(g))]
    run = best = 0; best_end = 0
    for i, s in enumerate(still):
        run = run + 1 if s else 0
        if run > best: best, best_end = run, i + 1
    return {"ratio": round(sum(still) / len(still), 3), "longestStillFrames": best, "longestStillEnd": best_end}


def flash(p):
    r = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", p, "--json", "/dev/stdout"], capture_output=True, text=True)
    return {"exit": r.returncode, "out": r.stdout[-1200:].strip()}


def audit():
    s = subprocess.run([CH, "--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--virtual-time-budget=60000", "--window-size=1080,1920",
                        "--dump-dom", f"file://{os.path.abspath(HERE)}/vertical.html?audit=1"], capture_output=True, text=True).stdout
    d = json.loads(html.unescape(re.search(r'<pre id="audit">(.*?)</pre>', s, re.S).group(1)))
    X0, Y0, X1, Y1 = 70, 100, 930, 1620
    viol = {}
    for fr in d["frames"]:
        for it in fr["items"]:
            if it["o"] < 0.3: continue        # 거의 안 보이는 것(페이드 중 꼬리)은 판정 제외
            x0, y0, x1, y1 = it["r"]
            if x0 < X0 or y0 < Y0 or x1 > X1 or y1 > Y1:
                viol.setdefault(it["name"], []).append((fr["f"], it["r"]))
    return {"zone": [X0, Y0, X1, Y1], "sampled": len(d["frames"]), "violations": {k: {"n": len(v), "first": v[0], "last": v[-1]} for k, v in viol.items()}}


def first_frame(fr):
    g = cv2.cvtColor(fr[0], cv2.COLOR_BGR2GRAY)
    return {"meanLuma": round(float(g.mean()), 2), "brightPx": int((g > 200).sum()), "meanLumaF30": round(float(cv2.cvtColor(fr[30], cv2.COLOR_BGR2GRAY).mean()), 2)}


p = sys.argv[1]
fr = frames(p)
res = {"file": os.path.basename(p), "probe": probe(p), "decoded": len(fr), "diff": diff_scan(fr), "holds": holds(fr), "flash": flash(p),
       "audit": audit(), "first": first_frame(fr)}
if len(sys.argv) > 2:
    fr2 = frames(sys.argv[2])
    md = max(int(np.abs(a.astype(np.int16) - b.astype(np.int16)).max()) for a, b in zip(fr, fr2)) if len(fr2) == len(fr) else None
    res["determinism"] = {"second": os.path.basename(sys.argv[2]), "frames2": len(fr2), "maxPixelDiff": md,
                          "md5": [subprocess.run(["md5", "-q", x], capture_output=True, text=True).stdout.strip() for x in sys.argv[1:3]]}
ROOT = os.path.abspath(HERE + "/../..") + "/"
res = json.loads(json.dumps(res, ensure_ascii=False).replace(ROOT, ""))   # 절대 경로를 남기지 않는다(익명 저장소)
json.dump(res, open(OUT + "/t4-swings-qa.json", "w"), ensure_ascii=False, indent=1)
print(json.dumps(res, ensure_ascii=False, indent=1)[:4000])
