#!/usr/bin/env python3
"""T3 QA — 한 편(dist/ads/threads/t3-meeting-v-ko.mp4)을 측정해 JSON으로 출력한다.

  python3 scripts/qa.py [mp4] [--twin 두번째.mp4]

  1) ffprobe: 해상도·fps·길이·프레임 수·코덱
  2) 프레임 차분: 135×240(INTER_AREA) float BGR 평균 절대차 — 최대 ≤ 12, A-B-A(1프레임 튐) 0
  3) 정지 비율: 480px 폭 회색 평균 밝기차 < 0.35 인 프레임 비율
  4) 광과민성: qa/flash-check.py (공용 QA 키트 복사본)
  5) 안전 영역: 컴포지션 ?audit=1 → 자막·엔드카드·채팅·입력·스틱맨·공·커서·음소거 버튼 사각형
       스레드 기준 x 70~930 · y 100~1620 (오른쪽 150·아래 300은 스레드 UI)
  6) 첫 프레임: 평균 밝기 > 0 이고 자막이 이미 보인다(페이드인 없음)
  7) 결정론(--twin): 두 렌더의 디코드 프레임이 모두 같은지(최대 화소차)
"""
import html, json, re, subprocess, sys, os
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
args = sys.argv[1:]
twin = None
if "--twin" in args: i = args.index("--twin"); twin = args[i + 1]; del args[i:i + 2]
MP4 = args[0] if args else os.path.abspath(HERE + "/../../dist/ads/threads/t3-meeting-v-ko.mp4")

def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vcodec": v["codec_name"], "profile": v.get("profile"), "pix": v.get("pix_fmt"), "audio": a[0]["codec_name"] if a else None,
            "sizeMB": round(int(j["format"]["size"]) / 1e6, 2)}

def frames(p):
    cap = cv2.VideoCapture(p); out = []
    while True:
        ok, im = cap.read()
        if not ok: break
        out.append(im)
    return out

fr = frames(MP4)
sm = [cv2.resize(f, (135, 240), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
d = [0.0] + [float(np.abs(sm[i] - sm[i - 1]).mean()) for i in range(1, len(sm))]
aba = [i for i in range(1, len(sm) - 1) if min(d[i], d[i + 1]) >= 3 and float(np.abs(sm[i + 1] - sm[i - 1]).mean()) < 0.5 * min(d[i], d[i + 1])]
mx = int(np.argmax(d))
g = [cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (480, 853), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
still = [float(np.abs(g[i] - g[i - 1]).mean()) < 0.35 for i in range(1, len(g))]
# 가장 긴 '완전 정지' 구간 (멈춘 구간 점검)
run = best = 0; bi = 0
for i, s in enumerate(still):
    run = run + 1 if s else 0
    if run > best: best, bi = run, i + 1 - run + 1
fl = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", MP4, "--json", "/dev/stdout"], capture_output=True, text=True)

s = subprocess.run([CH, "--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--virtual-time-budget=40000", "--window-size=1080,1920",
                    "--dump-dom", f"file://{os.path.abspath(HERE)}/vertical.html?audit=1"], capture_output=True, text=True).stdout
A = json.loads(html.unescape(re.search(r'<pre id="audit">(.*?)</pre>', s, re.S).group(1)))
X0, Y0, X1, Y1 = 70, 100, 930, 1620
viol = {}
for f in A["frames"]:
    for it in f["items"]:
        x0, y0, x1, y1 = it["r"]
        if x0 < X0 or y0 < Y0 or x1 > X1 or y1 > Y1: viol.setdefault(it["name"], []).append((f["f"], it["r"]))
first = A["frames"][0]
res = {"file": MP4, "probe": probe(MP4), "decoded": len(fr),
       "diff": {"max": round(d[mx], 2), "maxFrame": mx, "over12": [i for i in range(len(d)) if d[i] > 12], "aba": aba,
                "top5": sorted([(i, round(d[i], 2)) for i in range(len(d))], key=lambda x: -x[1])[:5]},
       "hold": {"ratio": round(sum(still) / len(still), 3), "longestStillFrames": best, "from": bi},
       "flash": {"exit": fl.returncode, "out": fl.stdout[-900:].strip()},
       "safe": {"zone": [X0, Y0, X1, Y1], "fontsOk": A["fontsOk"], "violations": {k: {"samples": len(v), "first": v[0], "last": v[-1]} for k, v in viol.items()}},
       "firstFrame": {"meanLuma": round(float(cv2.cvtColor(fr[0], cv2.COLOR_BGR2GRAY).mean()), 2), "items": sorted(set(i["name"] for i in first["items"]))}}
if twin:
    fr2 = frames(twin)
    diffs = [int(np.abs(a.astype(np.int16) - b.astype(np.int16)).max()) for a, b in zip(fr, fr2)]
    res["determinism"] = {"twin": twin, "frames": [len(fr), len(fr2)], "maxPixelDiff": max(diffs), "framesDiffering": sum(1 for x in diffs if x > 0)}
print(json.dumps(res, ensure_ascii=False, indent=1))
