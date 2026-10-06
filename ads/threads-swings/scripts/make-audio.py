#!/usr/bin/env python3
"""오디오 합성 — 외부 음원 없음, numpy 결정론. 소리 없이도 완결되는 영상의 '켜면 더 좋은' 층.

  python3 scripts/make-audio.py   → audio/mix.wav (+ mix.json 측정값)

효과음 레시피는 ads/mini-golf-15s/scripts/make-audio.py(= 게임 SoundKit.swift 이식)에서 그대로 가져왔다: 드라이버 타격음·착지 탭·차임·스윙 바람.
타이밍은 src/main.js 비트와 같다(소리는 화면 타점보다 1프레임 먼저):
  f0–14 세 스윙 바람 → f14 동시 임팩트(타격음 3겹 + 낮은 쿵) → 정지한 시간 패드
  단어 f30·f88·f144 로즈 음(코드 톤 상행) · 점프 착지 f70 탭 · 트월 f170–204 느린 바람
  3칸 확장 f206 상승 바람 · 관절 점 f240–260 작은 틱 6개 · 마무리 f338 로즈 화음 · 엔드 f385 차임, 15.0초에 무음
라우드니스: 정적 게인으로 통합 -14 LUFS, 트루피크 ≤ -2.5 dBFS (15초 광고와 같은 기준).
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; FPS = 30; DUR = 15.0; N = int(SR * DUR)
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = HERE + "/audio"; os.makedirs(OUT, exist_ok=True)

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

def impact_wood(power=1.0, pitch=1.0, seed=0x9E3779B9):
    t = T(0.1); n = LCG(seed).white(len(t))
    s = np.sin(2 * np.pi * (170 * pitch - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", 2000 * pitch, 1.2) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def whoosh(d=0.26, power=1.0, lo=350, span=550, seed=77):
    t = T(d); n = LCG(seed).white(len(t)); u = t / d
    y = np.zeros_like(t); parts = 8
    for k in range(parts):
        a, b = k * len(t) // parts, (k + 1) * len(t) // parts
        y[a:b] = biquad(n[a:b], "bp", lo + span * (k + .5) / parts, 0.9)
    return y * np.sin(np.pi * u) ** 2 * (0.10 + 0.25 * power)
def bounce(speed=9, cutoff=1000):
    t = T(0.04); n = LCG(5).white(len(t))
    s = biquad(n, "lp", cutoff, 0.8) * np.exp(-t / 0.01)
    if speed > 8: s += np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.015) * 0.3
    return s * min(1, speed / 10) * 0.5
def chime():
    t = T(0.9)
    s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.16
def thump():
    t = T(0.35); return np.sin(2 * np.pi * (58 + 30 * np.exp(-t / 0.04)) * t) * np.exp(-t / 0.12) * np.minimum(1, t / 0.002) * 0.55
def tick(f=2600):
    t = T(0.03); n = LCG(4242).white(len(t)); return biquad(n, "bp", f, 2.5) * np.exp(-t / 0.004) * 0.35
def note(m): return 440 * 2 ** ((m - 69) / 12)
def rhodes(f, d, amp):
    t = T(d); mod = np.sin(2 * np.pi * f * 2 * t) * 1.2 * np.exp(-t / 0.35)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 0.9) * np.minimum(1, t / 0.004) * amp
def pad(freqs, d, amp, att=0.6, rel=0.8):
    t = T(d); s = np.zeros_like(t)
    for i, f in enumerate(freqs):
        for det in (-0.12, 0.12):
            s += np.sin(2 * np.pi * (f * (1 + det / 100)) * t + i) + 0.18 * np.sin(2 * np.pi * 2 * f * t + i)
    env = np.minimum(1, t / att) * np.minimum(1, np.maximum(0, d - t) / rel)
    return s * env * amp / len(freqs)

def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i >= len(buf): return
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g

def write_wav(path, x):
    x = np.clip(x, -1, 1); st = np.stack([x, x], 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st * 32767).astype("<i2").tobytes())

def ebur(path):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True)
    s = p.stderr[p.stderr.rfind("Summary:"):]
    return float(re.search(r"I:\s*(-?[\d.]+) LUFS", s).group(1)), float(re.search(r"Peak:\s*(-?[\d.]+) dBFS", s).group(1))

mix = np.zeros(N); log = []
def add(s, f, g=1.0, name=""):
    put(mix, s, max(0, f - 1) / FPS, g); log.append([name, f])

# 훅: 세 스윙 바람(템포가 달라 시작이 조금씩 다르다) → f14 동시 임팩트
add(whoosh(0.30, 1.0, seed=77), 5, 0.8, "whoosh-a"); add(whoosh(0.36, 1.0, 330, 520, seed=78), 3, 0.6, "whoosh-b"); add(whoosh(0.24, 1.0, 380, 560, seed=79), 7, 0.6, "whoosh-c")
for k, (pt, sd) in enumerate([(1.0, 0x9E3779B9), (0.93, 1234567), (1.08, 7654321)]): add(impact_wood(1.0, pt, sd), 14, 0.75, f"impact-{k}")
add(thump(), 14, 0.9, "thump")
# 정지한 시간: 패드 세 코드가 세 주인공을 따라간다 (Fmaj9 → Dm9 → Bbmaj7 → 엔드 F 해결)
CH = [[53, 57, 60, 64, 67], [50, 57, 60, 64, 65], [46, 57, 62, 65, 69], [41, 53, 57, 60, 64]]
for (f0, f1), c in zip([(14, 92), (84, 148), (140, 300), (296, 450)], CH):
    add(pad([note(m) for m in c], (f1 - f0) / FPS, 0.16, att=0.9, rel=0.9), f0, 1.0, "pad")
# 단어: 코드 톤 상행
for f, m in [(30, 69), (88, 72), (144, 76)]: add(rhodes(note(m), 1.6, 0.22), f, 1.0, f"word-{m}")
add(bounce(6, 900), 70, 0.8, "jump-land")
add(whoosh(1.1, 0.6, 180, 260, seed=91), 170, 0.9, "twirl-swish")
add(whoosh(0.8, 0.5, 250, 700, seed=93), 206, 0.7, "expand-rise")
for f in [240, 250, 254, 256, 258, 260]: add(tick(2400 + 120 * (f - 240)), f, 0.8, "joint")
for m in [65, 69, 72]: add(rhodes(note(m), 2.0, 0.12), 338, 1.0, "closing")
add(tick(1800), 348, 0.6, "menu")
add(chime(), 385, 0.9, "end-chime")
# 15.0초에 무음: 마지막 0.5초 페이드
fade = np.ones(N); k0 = int((DUR - 0.5) * SR); fade[k0:] = np.linspace(1, 0, N - k0); mix *= fade

g = 1.0; path = OUT + "/mix.wav"
for it in range(8):
    y = mix * g
    th, c = 10 ** (-7 / 20), 10 ** (-3.4 / 20); a = np.abs(y); over = a > th
    y[over] = np.sign(y[over]) * (th + (c - th) * np.tanh((a[over] - th) / (c - th)))
    write_wav(path, y); I, TP = ebur(path)
    if abs(I + 14) < 0.3 and TP <= -2.5: break
    g *= 10 ** ((-14 - I) / 20)
    if TP > -2.5: g *= 0.98
json.dump({"I": I, "TP": TP, "gain": g, "events": log}, open(OUT + "/mix.json", "w"), ensure_ascii=False, indent=1)
print("I", I, "LUFS · TP", TP, "dBFS · events", len(log))
