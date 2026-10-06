#!/usr/bin/env python3
"""T5 오디오 — 외부 음원·TTS 없음(소리 없이도 완결, 켜면 중계 현장감). numpy 합성, 결정론(LCG 잡음).

  python3 scripts/make-audio.py   → audio/mix-ko.wav (+ mix-ko.json 측정값)

· 효과음 레시피는 15초 광고 make-audio.py(= 게임 SoundKit.swift 이식)와 같다: 스윙 우시 · 드라이버 타격음 · 착지 탭 · 차임.
· 타이밍은 src/main.js·data/shot.js와 같은 값: 임팩트 f11(타격음 1프레임 먼저) · 착지 SHOT.fLand · 튐 착지 · 엔드 f262.
· 바닥: 아주 낮은 야외 공기(저역 잡음) + 느린 패드(Fmaj9 → 엔드에서 해결). 중계석 해설 목소리는 넣지 않는다(자막이 말한다).
· 라우드니스: 정적 게인 + 소프트 클립(tanh)으로 통합 -16 LUFS 목표, 트루피크 ≤ -2.5 dBFS.
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; FPS = 30; DUR = 12.0; N = int(SR * DUR)
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = HERE + "/audio"; os.makedirs(OUT, exist_ok=True)
SHOT = json.loads(open(HERE + "/data/shot.js").read().split("=", 1)[1].rstrip().rstrip(";"))

class LCG:  # SoundKit NoiseLCG 와 같은 수열 (결정론)
    def __init__(self, s=0x9E3779B9): self.s = s
    def white(self, n):
        out = np.empty(n); s = self.s
        for i in range(n):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            out[i] = s / 0xFFFFFFFF * 2 - 1
        self.s = s
        return out

def biquad(x, kind, f, q):
    w = 2 * np.pi * max(40, min(f, SR * 0.45)) / SR; al = np.sin(w) / (2 * q); cw = np.cos(w); a0 = 1 + al
    if kind == "lp": b0 = (1 - cw) / 2 / a0; b1 = (1 - cw) / a0; b2 = b0
    else: b0 = al / a0; b1 = 0; b2 = -al / a0
    a1 = -2 * cw / a0; a2 = (1 - al) / a0
    y = np.zeros_like(x); z1 = z2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + z1; z1 = b1 * v - a1 * o + z2; z2 = b2 * v - a2 * o; y[i] = o
    return y

def T(d): return np.arange(int(d * SR)) / SR
def impact_wood(power=1.0):
    t = T(0.1); n = LCG().white(len(t))
    s = np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", 2000, 1.2) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def whoosh(d=0.26, power=1.0):
    t = T(d); n = LCG(77).white(len(t)); u = t / d; y = np.zeros_like(t); parts = 8
    for k in range(parts):
        a, b = k * len(t) // parts, (k + 1) * len(t) // parts
        y[a:b] = biquad(n[a:b], "bp", 350 + 550 * (k + .5) / parts, 0.9)
    return y * np.sin(np.pi * u) ** 2 * (0.10 + 0.25 * power)
def bounce(speed=9, cutoff=1000):
    t = T(0.04); n = LCG(5).white(len(t))
    s = biquad(n, "lp", cutoff, 0.8) * np.exp(-t / 0.01)
    if speed > 8: s += np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.015) * 0.3
    return s * min(1, speed / 10) * 0.5
def chime():
    t = T(0.9); s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.16
def note(m): return 440 * 2 ** ((m - 69) / 12)
def pad(freqs, d, amp, att=0.6, rel=0.8):
    t = T(d); s = np.zeros_like(t)
    for i, f in enumerate(freqs):
        for det in (-0.12, 0.12):
            s += np.sin(2 * np.pi * (f * (1 + det / 100)) * t + i) + 0.18 * np.sin(2 * np.pi * 2 * f * t + i)
    env = np.minimum(1, t / att) * np.minimum(1, (d - t) / rel)
    return s * env * amp / len(freqs)
def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i >= len(buf): return
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g

buf = np.zeros(N)
# 바닥: 야외 공기 — 저역 통과 잡음(400Hz), 엔드에서 사라진다. 첫 샘플부터 이미 울리는 중(페이드인 없음)
air = biquad(LCG(2024).white(N), "lp", 400, 0.7) * 0.08
air *= np.clip((10.6 - np.arange(N) / SR) / 2.0, 0, 1)
buf += air
# 패드: Fmaj9 (0 → 8.4초) → 엔드 해결 (8.4 → 12초)
put(buf, pad([note(m) for m in (53, 57, 60, 64, 67)], 9.2, 0.07, att=0.02), 0.0)
put(buf, pad([note(m) for m in (41, 53, 60, 64, 69)], 3.6, 0.085, att=0.9, rel=1.0), 8.4)
# 스윙·임팩트 (임팩트 f11, 타격음은 한 프레임 먼저 — 15초 광고와 같은 규칙)
put(buf, whoosh(0.26, 1.0), (11 - 8) / FPS, 1.4)
put(buf, impact_wood(1.0), (11 - 1) / FPS, 1.8)
# 착지 탭 → 튐 착지 → 굴림 끝(아주 작게)
fL = SHOT["fLand"]; hop = SHOT["hop"]; fH1 = fL + (hop[0] - fL) / 0.625
put(buf, bounce(28.4 / 2.5, 1100), fL / FPS, 2.0)        # LANDCUE vn 28.4 m/s 착지(화면 시간 배율로 눌러서)
put(buf, bounce(6, 900), fH1 / FPS, 1.4)
# 엔드카드 차임 (게임 배지 소리)
put(buf, chime(), 262 / FPS, 1.6)
# 끝 0.15초 무음으로 닫기
buf[int((DUR - 0.15) * SR):] *= 0

def write_wav(path, x):
    st = np.clip(np.stack([x, x], 1), -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st * 32767).astype("<i2").tobytes())
def ebur(path):
    r = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    I = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", r)[-1]); TP = float(re.findall(r"Peak:\s+(-?[\d.]+) dBFS", r)[-1])
    return I, TP
path = OUT + "/mix-ko.wav"
write_wav(path, buf); I, TP = ebur(path)
buf = buf * 10 ** ((-16 - I) / 20)                       # 목표 라우드니스로 올린 뒤
buf = np.tanh(buf / 0.5) * 0.5                           # 타격음 순간 피크만 부드럽게 눌러(소프트 클립) 트루피크 여유를 만든다
write_wav(path, buf); I, TP = ebur(path)
g = min(10 ** ((-16 - I) / 20), 10 ** ((-2.5 - TP) / 20))
write_wav(path, buf * g); I2, TP2 = ebur(path)
json.dump({"lufs": I2, "truePeak": TP2, "gain": g}, open(OUT + "/mix-ko.json", "w"))
print(path, "LUFS", I2, "TP", TP2)
