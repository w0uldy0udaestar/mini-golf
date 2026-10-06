#!/usr/bin/env python3
"""T2 「홀마다 다른 산」 사운드 — 전부 합성(외부 음원 없음, 결정론). 효과음은 15초 본편 make-audio.py의 SoundKit 레시피를 옮겨 썼다.

  python3 scripts/make-audio.py <sfx.json>    (sfx.json = vertical.html?sfx=1 이 찍는 큐: 그림과 소리의 단일 출처)
  → audio/mix.wav (48kHz 스테레오) — ffmpeg loudnorm 2패스로 −14 LUFS 통합 · 트루피크 −2.0 dBTP 목표(AAC 여유 0.5dB)

비트: 128.57bpm(한 박 = 14프레임 = 0.4667초) — 컷 경계가 8분음표(7프레임) 격자에 떨어진다. 킥 매 박, 하이햇 8분 뒷박, 클랩 2·4박, 베이스 마디마다 근음.
엔드카드(f371)부터 비트를 멈추고 엔드 차임만 남겨 끝 0.5초에 페이드.
"""
import json, os, subprocess, sys, wave, re
import numpy as np

SR = 48000; FPS = 30
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
cues = json.load(open(sys.argv[1]))
NF = cues["nf"]; DUR = NF / FPS; N = int(round(SR * DUR))
BEAT = 14 / FPS; END0 = 371 / FPS

class LCG:  # SoundKit NoiseLCG 와 같은 수열
    def __init__(self, s=0x9E3779B9): self.s = s
    def white(self, n):
        out = np.empty(n); s = self.s
        for i in range(n):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF; out[i] = s / 0xFFFFFFFF * 2 - 1
        self.s = s; return out
def biquad(x, kind, f, q):
    w = 2 * np.pi * max(40, min(f, SR * 0.45)) / SR; al = np.sin(w) / (2 * q); cw = np.cos(w); a0 = 1 + al
    if kind == "lp": b0 = (1 - cw) / 2 / a0; b1 = (1 - cw) / a0; b2 = b0
    elif kind == "hp": b0 = (1 + cw) / 2 / a0; b1 = -(1 + cw) / a0; b2 = b0
    else: b0 = al / a0; b1 = 0; b2 = -al / a0
    a1 = -2 * cw / a0; a2 = (1 - al) / a0
    y = np.zeros_like(x); z1 = z2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + z1; z1 = b1 * v - a1 * o + z2; z2 = b2 * v - a2 * o; y[i] = o
    return y
def T(d): return np.arange(int(d * SR)) / SR

# ── 효과음 (SoundKit 레시피 이식 + 같은 결 신규) ──
def impact(power=1.0, bright=2000):
    t = T(0.12); n = LCG(11).white(len(t))
    s = np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", bright, 1.2) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def whoosh(d=0.26, power=1.0, seed=77):
    t = T(d); n = LCG(seed).white(len(t)); u = t / d; y = np.zeros_like(t); parts = 8
    for k in range(parts):
        a, b = k * len(t) // parts, (k + 1) * len(t) // parts; y[a:b] = biquad(n[a:b], "bp", 350 + 900 * (k + .5) / parts, 0.9)
    return y * np.sin(np.pi * u) ** 2 * (0.18 + 0.3 * power)
def bounce(speed=9, cutoff=1000, seed=5):
    t = T(0.05); n = LCG(seed).white(len(t))
    s = biquad(n, "lp", cutoff, 0.8) * np.exp(-t / 0.01)
    if speed > 8: s += np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.015) * 0.3
    return s * min(1, speed / 10) * 0.6
def thud():  # 착지 '쿵' + 굴림 '사각'
    t = T(0.45); n = LCG(21).white(len(t))
    s = np.sin(2 * np.pi * (95 - 50 * t) * t) * np.exp(-t / 0.07) * 0.9
    s[:len(bounce())] += bounce(10, 900) * 1.2
    roll = biquad(n, "bp", 2400, 0.7) * 0.10 * np.clip((t - 0.06) / 0.05, 0, 1) * np.exp(-np.clip(t - 0.06, 0, None) / 0.16)
    return s + roll
def tok(seed=31):  # 계단 '톡'
    t = T(0.08); bb = bounce(9, 1800, seed)
    return np.sin(2 * np.pi * 1150 * t) * np.exp(-t / 0.012) * 0.55 + np.pad(bb, (0, len(t) - len(bb)))
def splash(k=1.0):  # '풍덩'
    t = T(0.6); n = LCG(41).white(len(t))
    body = biquad(n, "lp", 1400, 0.7) * np.exp(-t / 0.12) * 1.0 + biquad(n, "bp", 4200, 1.0) * np.exp(-t / 0.05) * 0.5
    low = np.sin(2 * np.pi * (140 - 80 * t) * t) * np.exp(-t / 0.08) * 0.6
    bub = np.zeros_like(t)
    for j, (t0, f) in enumerate([(0.12, 700), (0.2, 950), (0.27, 820), (0.36, 1100)]):
        tt = np.clip(t - t0, 0, None); bub += (t >= t0) * np.sin(2 * np.pi * (f + 900 * tt) * tt) * np.exp(-tt / 0.03) * 0.25
    return (body + low + bub) * 0.8 * k
def swish():  # 숲 캐노피 '사락'
    t = T(0.34); n = LCG(51).white(len(t)); u = t / 0.34
    return biquad(n, "bp", 5200, 0.8) * np.sin(np.pi * u) ** 1.5 * 0.55 + biquad(n, "bp", 2600, 1.2) * np.sin(np.pi * u) ** 2 * 0.25
def tick():  # 컬러 플래시 틱
    t = T(0.06); n = LCG(61).white(len(t))
    return biquad(n, "bp", 3200, 1.4) * np.exp(-t / 0.006) * 0.9 + np.sin(2 * np.pi * 2400 * t) * np.exp(-t / 0.01) * 0.25
def cup():  # 화산 컵인 '툭'
    t = T(0.12); n = LCG(71).white(len(t))
    return np.sin(2 * np.pi * (240 - 120 * t) * t) * np.exp(-t / 0.025) * 0.9 + biquad(n, "lp", 1200, 0.8) * np.exp(-t / 0.012) * 0.6
def chime(k=1.0, d=0.9):
    t = T(d); s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.32 * k
def end_chime():
    t = T(2.4); s = np.zeros_like(t)
    for f, a, dl in [(523.25, 0.5, 0), (659.25, 0.4, 0.06), (783.99, 0.35, 0.12), (1046.5, 0.25, 0.18)]:
        tt = np.clip(t - dl, 0, None); s += (t >= dl) * a * (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)) * np.exp(-tt / 0.9)
    return s * 0.35

# ── 비트 ──
def kick():
    t = T(0.3); f = 45 + 85 * np.exp(-t / 0.03); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.12) * 0.95
def hat(seed):
    t = T(0.04); n = LCG(seed).white(len(t)); return biquad(n, "bp", 8500, 1.0) * np.exp(-t / 0.008) * 0.35
def clap():
    t = T(0.18); n = LCG(91).white(len(t)); env = sum(np.exp(-np.clip(t - d, 0, None) / 0.012) * (t >= d) for d in (0, 0.012, 0.024)) / 3
    return biquad(n, "bp", 1500, 0.9) * (env + 0.4 * np.exp(-t / 0.06)) * 0.6
def bass(f, d):
    t = T(d); s = sum(np.sin(2 * np.pi * f * h * t) / h for h in (1, 2, 3, 4)) * 0.5
    return s * np.minimum(1, t / 0.008) * np.exp(-t / (d * 0.6)) * 0.45

L = np.zeros(N); R = np.zeros(N)
def put(sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR)); j = min(N, i + len(sig))
    if j <= i or i < 0: return
    L[i:j] += sig[:j - i] * gain * (1 - max(0, pan)); R[i:j] += sig[:j - i] * gain * (1 + min(0, pan))

# 비트(엔드카드 전까지): 마디 근음 A–F–C–G
roots = [55.0, 43.65, 65.41, 49.0]
K, CL = kick(), clap()
nb = int(END0 / BEAT)
for b in range(nb):
    t = b * BEAT
    put(K, t, 0.9)
    if b % 4 in (1, 3): put(CL, t, 0.55, 0.1)
    put(hat(300 + b), t + BEAT / 2, 0.5, -0.2)
    put(bass(roots[(b // 4) % 4], BEAT * 0.9), t, 0.8)
# 효과음
club = ["iron", "wedge", "driver", "wedge", "iron", "wedge", "driver", "iron"]
cut_starts = [0, 42, 77, 112, 147, 182, 217, 252]
for f, kind in cues["cues"]:
    t = f / FPS
    if kind == "whoosh": put(whoosh(0.26, 1.0, 77 + f), max(0, t - 3 / FPS), 1.0, 0.3)
    elif kind == "whoosh-up": put(whoosh(0.32, 0.8, 7), t, 0.9)
    elif kind == "flash": put(tick(), t, 1.0); put(whoosh(0.16, 0.6, 9 + f), t, 0.6)
    elif kind.startswith("impact"):
        ci = max([k for k, s0 in enumerate(cut_starts) if s0 <= f] or [0]) if f < 287 else 1
        c = club[ci] if f < 287 else "wedge"
        put(impact(1.0 if c == "driver" else 0.8 if c == "iron" else 0.6, 2600 if c == "driver" else 2000 if c == "iron" else 1500), t, 1.0, -0.15)
    elif kind == "thud": put(thud(), t, 1.0)
    elif kind == "tok": put(tok(31 + f), t, 1.0, 0.1)
    elif kind == "splash": put(splash(1.0), t, 1.0)
    elif kind == "splash-small": put(splash(0.5), t, 1.0)
    elif kind == "swish": put(swish(), t, 1.0, -0.2)
    elif kind == "cup": put(cup(), t, 1.0)
    elif kind == "chime": put(chime(1.2), t, 1.0)
    elif kind == "end-chime": put(end_chime(), t, 1.0)
# 끝 0.5초 페이드 · 소프트 리미트
fade = np.ones(N); nf = int(0.5 * SR); fade[-nf:] = np.linspace(1, 0, nf)
L *= fade; R *= fade
pk = max(np.abs(L).max(), np.abs(R).max()); L /= pk; R /= pk
L = np.tanh(L * 1.4) / np.tanh(1.4); R = np.tanh(R * 1.4) / np.tanh(1.4)
os.makedirs(HERE + "/audio", exist_ok=True)
raw = HERE + "/audio/raw.wav"; out = HERE + "/audio/mix.wav"
def write(p, l, r):
    data = (np.clip(np.stack([l, r], 1), -1, 1) * 32767 * 0.7).astype("<i2").tobytes()
    with wave.open(p, "wb") as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
write(raw, L, R)
# ffmpeg loudnorm 2패스 (결정적)
m = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", raw, "-af", "loudnorm=I=-14:TP=-2.0:LRA=11:print_format=json", "-f", "null", "-"], capture_output=True, text=True).stderr
j = json.loads(m[m.rfind("{"):m.rfind("}") + 1])
af = (f"loudnorm=I=-14:TP=-2.0:LRA=11:measured_I={j['input_i']}:measured_TP={j['input_tp']}:measured_LRA={j['input_lra']}:"
      f"measured_thresh={j['input_thresh']}:offset={j['target_offset']}:linear=true:print_format=summary")
subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-y", "-i", raw, "-af", af, "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", out], capture_output=True, check=True)
os.remove(raw)
r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", out, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
t = r[r.rfind("Summary:"):]
print("mix.wav", re.search(r"I:\s*(-?[\d.]+) LUFS", t).group(1), "LUFS · TP", re.search(r"Peak:\s*(-?[\d.]+) dBFS", t).group(1), "dBTP · dur", round(DUR, 3))
