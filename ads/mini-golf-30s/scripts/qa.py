#!/usr/bin/env python3
"""30초판 QA — qa.py <mp4> [<mp4> ...] → 같은 폴더 qa-<이름>.json + 요약 출력

측정: ffprobe(해상도·fps·길이·오디오) · 프레임 차분(가로 240×135 / 세로 135×240 INTER_AREA, BGR 평균 절대차 — 이 판은 게이트가 아니라
컷 목록용: 차분 > 12 = 컷/급변 후보, 1–2프레임 A-B-A 이상치) · 정지 비율(480px 회색 평균차 < 0.35) · 라우드니스(ebur128) ·
광과민성(qa/flash-check.py — general·red 0 게이트) · 타임라인 컷(src/timeline.js)과 대조."""
import json, os, re, subprocess, sys
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
TL = json.loads(re.search(r"window\.TL\s*=\s*(\{.*\});", open(HERE + "/src/timeline.js").read(), re.S).group(1))

def probe(p):
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", p], capture_output=True, text=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"][0]; a = [s for s in j["streams"] if s["codec_type"] == "audio"]
    return {"w": v["width"], "h": v["height"], "fps": v["r_frame_rate"], "frames": int(v.get("nb_frames", 0)), "dur": float(j["format"]["duration"]),
            "vcodec": v["codec_name"], "pix": v.get("pix_fmt"), "audio": {"codec": a[0]["codec_name"], "ch": a[0]["channels"], "sr": a[0]["sample_rate"]} if a else None}
def frames(p):
    cap = cv2.VideoCapture(p); out = []
    while True:
        ok, im = cap.read()
        if not ok: break
        out.append(im)
    return out
def planned_cuts():
    cuts = {0: "start"}
    for s in TL["shots"]:
        cuts[s["f0"]] = s["id"]
        for c in s.get("cuts", []): cuts[c] = s["id"] + "-cut"
    H, E = TL["honest"], TL["end"]
    cuts.update({180: "m1 (match cut)", H["f0"]: "honest", H["flagCut"]: "honest-flag", H["backCut"]: "honest-back", E["f0"]: "end"})
    return dict(sorted(cuts.items()))
def diff_scan(fr, portrait):
    size = (135, 240) if portrait else (240, 135)
    sm = [cv2.resize(f, size, interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    d = [0.0] + [float(np.abs(sm[i] - sm[i - 1]).mean()) for i in range(1, len(sm))]
    aba = [i for i in range(1, len(sm) - 1) if min(d[i], d[i + 1]) >= 3 and float(np.abs(sm[i + 1] - sm[i - 1]).mean()) < 0.5 * min(d[i], d[i + 1])]
    over = [i for i in range(len(d)) if d[i] > 12]
    return d, over, aba
def hold_ratio(fr):
    g = []
    for f in fr:
        h, w = f.shape[:2]; g.append(cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (480, int(480 * h / w)), interpolation=cv2.INTER_AREA).astype(np.float32))
    still = [float(np.abs(g[i] - g[i - 1]).mean()) < 0.35 for i in range(1, len(g))]
    return round(sum(still) / len(still), 3)
def loud(p):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", p, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    t = r[r.rfind("Summary:"):]; g = lambda pat: float(re.search(pat, t).group(1))
    return {"I": g(r"I:\s*(-?[\d.]+) LUFS"), "LRA": g(r"LRA:\s*(-?[\d.]+) LU"), "TP": g(r"Peak:\s*(-?[\d.]+) dBFS")}
def flash(p):
    r = subprocess.run([sys.executable, HERE + "/qa/flash-check.py", p, "--json", "/dev/stdout"], capture_output=True, text=True)
    j = json.loads(r.stdout[: r.stdout.rfind("}") + 1]) if "{" in r.stdout else {}
    return {"exit": r.returncode, "general": j.get("general", {}).get("max_per_second"), "red": j.get("red", {}).get("max_per_second"),
            "strict_general": j.get("strict", {}).get("general", {}).get("max_per_second"), "strict_red": j.get("strict", {}).get("red", {}).get("max_per_second"), "pass": j.get("pass")}
for p in sys.argv[1:]:
    fr = frames(p); pr = probe(p); portrait = pr["h"] > pr["w"]
    d, over, aba = diff_scan(fr, portrait)
    pc = planned_cuts()
    unplanned = [i for i in over if all(abs(i - c) > 1 for c in pc)]
    res = {"file": p, "probe": pr, "decoded": len(fr), "hold": hold_ratio(fr), "loud": loud(p), "flash": flash(p),
           "diff": {"max": round(max(d), 2), "maxFrame": int(np.argmax(d)), "over12": over, "aba": aba, "unplannedOver12": unplanned,
                    "atPlannedCuts": {str(c): round(d[c], 2) for c in pc if c < len(d)}}}
    out = os.path.join(os.path.dirname(p), "qa-" + os.path.splitext(os.path.basename(p))[0] + ".json")
    json.dump(res, open(out, "w"), ensure_ascii=False, indent=1)
    print(os.path.basename(p), json.dumps({k: res[k] for k in ("decoded", "hold", "loud", "flash")}, ensure_ascii=False))
    print("  diff max", res["diff"]["max"], "@f", res["diff"]["maxFrame"], "| >12:", over, "| A-B-A:", aba, "| unplanned >12:", unplanned)
