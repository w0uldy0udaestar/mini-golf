#!/usr/bin/env python3
"""오디오 구간 측정: audio-seg.py <mp4> — 핵심 사건 구간의 RMS·피크(dBFS). 2단계 오디오 요청(타건·클릭 −6dB, 임팩트·마침표 정적·엔터 화음 유지) 확인용."""
import subprocess, sys, numpy as np
p = sys.argv[1]
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-map", "0:a", "-ar", "48000", "-f", "f32le", "-"], capture_output=True).stdout
st = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2); SR = 48000   # 스테레오 그대로(모노 다운믹스는 피크를 부풀린다)
db = lambda x: round(20 * np.log10(max(x, 1e-9)), 1)
def seg(f0, f1):
    x = st[int(f0 / 30 * SR):int(f1 / 30 * SR)]
    return {"rms": round(float(db(np.sqrt(np.mean(x * x)))), 1), "samplePeak": round(float(db(np.abs(x).max())), 1)}
S = {"impact f29–33": (29, 33), "groove f60–84": (60, 84), "hook typing f84–118": (84, 118), "period silence f121–134": (121, 134),
     "montage f180–599": (180, 599), "H click f643–650": (643, 650), "breakdown f600–719": (600, 719), "end typing f726–778": (726, 778),
     "enter+chord f780–800": (780, 800), "tail f890–900": (890, 900)}
for k, (f0, f1) in S.items(): print(f"{k:24s}", seg(f0, f1))
