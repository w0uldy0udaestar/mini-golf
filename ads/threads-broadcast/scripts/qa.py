#!/usr/bin/env python3
"""T5 QA — 측정만 한다(판정 글은 dist/ads/threads/t5-broadcast-qa.md 에 사람이 쓴다).

  python3 scripts/qa.py <mp4> [<mp4 두 번째 렌더>]   → dist/ads/threads/t5-broadcast-qa.json

  1) ffprobe: 해상도·fps·길이·프레임 수·코덱
  2) 프레임 차분: 135×240 INTER_AREA float BGR 평균 절대차 — 최대 ≤ 12, 1~2프레임 튐(이웃 둘보다 2배·6 이상) 0
  3) 정지 구간: 연속 무변화(차분 < 0.05) 최장 길이
  4) 광과민성: qa/flash-check.py (일반 ≤ 1·적색 0 목표, 판정은 기본 창)
  5) 안전 영역: ?audit=1 로 글자 판·공·(f40 전) 스틱맨 사각형 → x 70~930(오른쪽 150 UI), y 120~1620(아래 300 UI)
  6) 첫 프레임: 평균 밝기·핵심 요소(홀 버그·리더보드·스틱맨) 불투명도 1
  7) 결정론: 두 번째 mp4가 있으면 디코딩 프레임 md5 전수 비교
"""
import hashlib, json, os, subprocess, sys
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = os.path.abspath(HERE + "/../../dist/ads/threads")
CH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SAFE = (70, 120, 930, 1620)

def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vcodec": v["codec_name"], "profile": v.get("profile"), "pix": v.get("pix_fmt"), "audio": a[0]["codec_name"] if a else None}

def frames(p):
    cap = cv2.VideoCapture(p); out = []
    while True:
        ok, im = cap.read()
        if not ok: break
        out.append(im)
    return out

def main():
    mp4 = sys.argv[1]; rep = {"file": os.path.basename(mp4), "probe": probe(mp4)}
    fr = frames(mp4)
    sm = [cv2.resize(f, (135, 240), interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    d = [0.0] + [float(np.abs(sm[i] - sm[i - 1]).mean()) for i in range(1, len(sm))]
    spikes = [i for i in range(1, len(d) - 1) if d[i] > 6 and d[i] > 2 * d[i - 1] and d[i] > 2 * d[i + 1]]
    top = sorted(range(len(d)), key=lambda i: -d[i])[:6]
    run = best = 0; best_end = 0
    for i, x in enumerate(d):
        run = run + 1 if x < 0.05 else 0
        if run > best: best, best_end = run, i
    rep["diff"] = {"max": round(max(d), 2), "argmax": int(np.argmax(d)), "top": [[i, round(d[i], 2)] for i in top], "spikes": spikes,
                   "mean": round(float(np.mean(d)), 3), "longest_still_frames": best, "still_end": best_end}
    rep["first_frame_mean"] = round(float(fr[0].mean()), 2)
    fc = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", mp4, "--json", OUT + "/t5-flash.json"], capture_output=True, text=True)
    rep["flash"] = {"exit": fc.returncode, "tail": fc.stdout.strip().splitlines()[-4:]}
    # 안전 영역 감사
    dom = subprocess.run([CH, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files", "--window-size=1080,1920",
                          "--virtual-time-budget=20000", "--dump-dom", f"file://{os.path.abspath(HERE)}/vertical.html?audit=1"], capture_output=True, text=True).stdout
    import html, re
    m = re.search(r'<pre id="audit">(.*?)</pre>', dom, re.S)
    au = json.loads(html.unescape(m.group(1)))
    bad = []
    for fr_ in au["frames"]:
        for it in fr_["items"]:
            if it["name"] == "man" and fr_["f"] >= 40: continue          # 패닝 뒤 스틱맨은 일부러 화면 밖(공이 주인공)
            if it["name"] == "ball" and fr_["f"] >= 255: continue        # 엔드 딤 아래 공은 배경
            x0, y0, x1, y1 = it["r"]
            if x0 < SAFE[0] or y0 < SAFE[1] or x1 > SAFE[2] or y1 > SAFE[3]:
                bad.append([fr_["f"], it["name"], it["r"]])
    f0 = au["frames"][0]
    rep["safe"] = {"box": SAFE, "violations": bad[:40], "n": len(bad), "fontsOk": au["fontsOk"],
                   "f0_items": {it["name"]: it["o"] for it in f0["items"]}}
    rep["ball_track"] = [[fr_["f"]] + it["r"] for fr_ in au["frames"] for it in fr_["items"] if it["name"] == "ball" and fr_["f"] % 15 == 0]
    if len(sys.argv) > 2:
        h = lambda p: [hashlib.md5(f.tobytes()).hexdigest() for f in frames(p)]
        a, b = h(mp4), h(sys.argv[2])
        rep["determinism"] = {"frames": [len(a), len(b)], "mismatch": [i for i, (x, y) in enumerate(zip(a, b)) if x != y][:30], "identical": a == b}
    json.dump(rep, open(OUT + "/t5-broadcast-qa.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(rep, ensure_ascii=False, indent=1)[:6000])

main()
