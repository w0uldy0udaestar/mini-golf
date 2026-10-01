#!/usr/bin/env python3
"""본편 QA — 4편 각각에 대해 측정하고 dist/ads/final/qa.json 에 모은다 (보고서는 qa-report.md 로 사람이 쓴다).

  python3 scripts/qa.py [variants...]   (기본 h-ko h-en v-ko v-en)

측정
  1) ffprobe: 해상도·fps·길이·프레임 수·오디오 코덱/채널/샘플레이트
  2) 프레임 차분: cv2.resize(프레임, 135×240(세로)/240×135(가로), INTER_AREA) float BGR 평균 절대차 — 최대 ≤ 12, A-B-A 0
  3) 정지 비율: 480px 폭 회색 프레임 평균 밝기차 < 0.35 인 프레임 비율 (목표 37~75%)
  4) 광과민성: qa/flash-check.py (공용 QA 키트 복사본) — general ≤ 1, red 0
  5) 라우드니스: ffmpeg ebur128 (통합 LUFS, 트루피크)
  6) 안전 영역(세로): 컴포지션 ?audit=1 로 글자·공·스틱맨 사각형 → x 70~1010, y 300~1500 (가로는 5% 여백)
"""
import html, json, re, subprocess, sys, os
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
FINAL = os.path.abspath(HERE + "/../../dist/ads/final")
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vdur": float(v.get("duration", 0)), "vcodec": v["codec_name"], "pix": v.get("pix_fmt"),
            "audio": {"codec": a[0]["codec_name"], "ch": a[0]["channels"], "sr": a[0]["sample_rate"], "dur": float(a[0].get("duration", 0))} if a else None}

def frames(p):
    cap = cv2.VideoCapture(p); out = []
    while True:
        ok, im = cap.read()
        if not ok: break
        out.append(im)
    return out

def diff_scan(fr, portrait):
    size = (135, 240) if portrait else (240, 135)
    sm = [cv2.resize(f, size, interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    d = [0.0] + [float(np.abs(sm[i] - sm[i - 1]).mean()) for i in range(1, len(sm))]
    aba = []
    for i in range(1, len(sm) - 1):
        d1, d2 = d[i], d[i + 1]; d0 = float(np.abs(sm[i + 1] - sm[i - 1]).mean())
        if min(d1, d2) >= 3 and d0 < 0.5 * min(d1, d2): aba.append(i)
    mx = int(np.argmax(d))
    return {"max": round(d[mx], 2), "maxFrame": mx, "over12": [i for i in range(len(d)) if d[i] > 12], "aba": aba,
            "top5": sorted([(i, round(d[i], 2)) for i in range(len(d))], key=lambda x: -x[1])[:5]}

def hold_ratio(fr):
    g = []
    for f in fr:
        h, w = f.shape[:2]; s = cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (480, int(480 * h / w)), interpolation=cv2.INTER_AREA).astype(np.float32); g.append(s)
    still = [float(np.abs(g[i] - g[i - 1]).mean()) < 0.35 for i in range(1, len(g))]
    return round(sum(still) / len(still), 3)

def loud(p):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", p, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    t = r[r.rfind("Summary:"):]
    g = lambda pat: float(re.search(pat, t).group(1))
    return {"I": g(r"I:\s*(-?[\d.]+) LUFS"), "LRA": g(r"LRA:\s*(-?[\d.]+) LU"), "TP": g(r"Peak:\s*(-?[\d.]+) dBFS")}

def flash(p):
    r = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", p, "--json", "/dev/stdout"], capture_output=True, text=True)
    return {"exit": r.returncode, "out": r.stdout[-1500:].strip()}

def audit(o, lang):
    page = "index.html" if o == "h" else "vertical.html"; size = "1920,1080" if o == "h" else "1080,1920"
    s = subprocess.run([CH, "--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--virtual-time-budget=30000", f"--window-size={size}",
                        "--dump-dom", f"file://{os.path.abspath(HERE)}/{page}?lang={lang}&audit=1"], capture_output=True, text=True).stdout
    d = json.loads(html.unescape(re.search(r'<pre id="audit">(.*?)</pre>', s, re.S).group(1)))
    if o == "v": X0, Y0, X1, Y1 = 70, 300, 1010, 1500
    else: X0, Y0, X1, Y1 = 96, 54, 1824, 1026
    viol = []
    for fr in d["frames"]:
        for it in fr["items"]:
            if it["name"] == "man" and fr["f"] >= 335: continue      # 엔드카드 중 딤된 스틱맨은 판정 제외(보고서에 명시)
            x0, y0, x1, y1 = it["r"]
            if x0 < X0 or y0 < Y0 or x1 > X1 or y1 > Y1: viol.append((fr["f"], it["name"], it["r"]))
    # '머문 채' 위반만 센다: 같은 이름이 연속 3개 표본(=9프레임) 이상
    by = {}
    for f, n, r in viol: by.setdefault(n, []).append(f)
    held = {}
    for n, fs in by.items():
        run = best = 1
        for a, b in zip(fs, fs[1:]):
            run = run + 1 if b - a == 3 else 1; best = max(best, run)
        held[n] = {"samples": len(fs), "longestRunFrames": best * 3, "first": viol[[v[1] for v in viol].index(n)]}
    return {"zone": [X0, Y0, X1, Y1], "violations": held, "textPx": d["textPx"]}

res = {}
for v in (sys.argv[1:] or ["h-ko", "h-en", "v-ko", "v-en"]):
    o, lang = v.split("-"); p = f"{FINAL}/mini-golf-15s-{o}-{lang}.mp4"
    fr = frames(p)
    res[v] = {"file": p, "probe": probe(p), "decoded": len(fr), "diff": diff_scan(fr, o == "v"), "hold": hold_ratio(fr),
              "loud": loud(p), "flash": flash(p), "audit": audit(o, lang)}
    print(v, json.dumps({k: res[v][k] for k in ("decoded", "diff", "hold", "loud")}, ensure_ascii=False)[:600])
    print("  audit", json.dumps(res[v]["audit"]["violations"], ensure_ascii=False)[:400], "| flash exit", res[v]["flash"]["exit"])
old = {}
if os.path.exists(FINAL + "/qa.json"): old = json.load(open(FINAL + "/qa.json"))
old.update(res); json.dump(old, open(FINAL + "/qa.json", "w"), ensure_ascii=False, indent=1)
