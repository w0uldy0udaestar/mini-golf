#!/usr/bin/env python3
"""T1 QA — 납품 mp4를 측정해 dist/ads/threads/t1-work/qa.json 에 모은다 (사람이 읽는 보고는 t1-surprises-qa.md).

  python3 scripts/qa.py <납품.mp4> [<두번째 렌더.mp4>]

측정
  1) ffprobe: 해상도·fps·길이·프레임 수·코덱·픽셀 포맷
  2) 프레임 차분: cv2.resize(프레임, 135×240, INTER_AREA) float BGR 평균 절대차 — 최대 ≤ 12, A-B-A(1프레임 튐) 0
  3) 멈춘 구간: 480px 폭 회색 프레임 차 < 0.35 가 연속되는 가장 긴 구간(초)과 정지 비율
  4) 광과민성: qa/flash-check.py (공용 QA 키트 복사본) — 일반 ≤ 3/초 기준, 적색 0
  5) 첫 프레임: f0이 완결된 그림인지(밝은 화소 수 · f0↔f1 차분 · f0↔f5 차분)
  6) 안전 영역: 컴포지션 ?audit=1 → 글자·표시 사각형이 x 70~930, y 300~1500 안인지 (스레드 UI: 아래 300px·오른쪽 150px)
     + 글자 크기(px) 목록
  7) 결정론: 두 번째 렌더가 주어지면 모든 프레임의 디코드 화소가 같은지(md5)
"""
import hashlib, html, json, os, re, subprocess, sys
import cv2, numpy as np
HERE = os.path.abspath(os.path.dirname(os.path.abspath(__file__)) + "/..")
WORK = os.path.abspath(HERE + "/../../dist/ads/threads/t1-work")
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vcodec": v["codec_name"], "profile": v.get("profile"), "pix": v.get("pix_fmt"), "audio": a[0]["codec_name"] if a else None,
            "bytes": int(j["format"]["size"])}

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
            "top8": sorted([(i, round(d[i], 2)) for i in range(len(d))], key=lambda x: -x[1])[:8]}

def holds(fr):
    g = [cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (480, 853), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    still = [float(np.abs(g[i] - g[i - 1]).mean()) < 0.35 for i in range(1, len(g))]
    runs, cur, start = [], 0, 0
    for i, s in enumerate(still, 1):
        if s:
            if cur == 0: start = i
            cur += 1
        else:
            if cur: runs.append((start, cur))
            cur = 0
    if cur: runs.append((start, cur))
    runs.sort(key=lambda r: -r[1])
    return {"stillRatio": round(sum(still) / len(still), 3), "longestStill": [(s, n, round(n / 30, 2)) for s, n in runs[:4]]}

def first_frame(fr):
    f0 = fr[0].astype(np.float32); gray = cv2.cvtColor(fr[0], cv2.COLOR_BGR2GRAY)
    d1 = float(np.abs(f0 - fr[1].astype(np.float32)).mean()); d5 = float(np.abs(f0 - fr[5].astype(np.float32)).mean())
    return {"meanLuma": round(float(gray.mean()), 1), "brightPx": int((gray > 200).sum()), "diff_f0_f1": round(d1, 2), "diff_f0_f5": round(d5, 2)}

def flash(p):
    r = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", p, "--json", "/dev/stdout"], capture_output=True, text=True)
    return {"exit": r.returncode, "out": r.stdout[-1200:].strip()}

def audit():
    s = subprocess.run([CH, "--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--virtual-time-budget=30000", "--window-size=1080,1920",
                        "--dump-dom", f"file://{HERE}/vertical.html?audit=1"], capture_output=True, text=True).stdout
    d = json.loads(html.unescape(re.search(r'<pre id="audit">(.*?)</pre>', s, re.S).group(1)))
    X0, Y0, X1, Y1 = 70, 300, 930, 1500
    viol, sizes, names = [], {}, set()
    for fr in d["frames"]:
        for it in fr["items"]:
            names.add(it["name"]); x0, y0, x1, y1 = it["r"]
            if "px" in it: sizes[it["name"]] = it["px"]
            if x0 < X0 or y0 < Y0 or x1 > X1 or y1 > Y1: viol.append((fr["f"], it["name"], it["r"]))
    return {"zone": [X0, Y0, X1, Y1], "violations": viol[:20], "nViolations": len(viol), "items": sorted(names), "fontPx": sizes, "fontsLoaded": d["fonts"]}

def md5s(fr): return [hashlib.md5(f.tobytes()).hexdigest() for f in fr]

if __name__ == "__main__":
    p = sys.argv[1]; fr = frames(p)
    res = {"file": p, "probe": probe(p), "decoded": len(fr), "diff": diff_scan(fr), "holds": holds(fr), "first": first_frame(fr),
           "flash": flash(p), "audit": audit()}
    if len(sys.argv) > 2:
        fr2 = frames(sys.argv[2]); a, b = md5s(fr), md5s(fr2)
        res["determinism"] = {"second": sys.argv[2], "frames": [len(a), len(b)], "identical": a == b,
                              "mismatch": [i for i in range(min(len(a), len(b))) if a[i] != b[i]][:20]}
    os.makedirs(WORK, exist_ok=True)
    json.dump(res, open(WORK + "/qa.json", "w"), ensure_ascii=False, indent=1)
    for k in ("probe", "decoded", "diff", "holds", "first", "audit", "determinism"):
        if k in res: print(k, json.dumps(res[k], ensure_ascii=False)[:700])
    print("flash exit", res["flash"]["exit"], res["flash"]["out"][-400:])
