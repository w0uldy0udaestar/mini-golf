#!/usr/bin/env python3
"""T3 오디오 합성 — 외부 음원 없음. numpy만으로 효과음 + 조용한 로파이 비트를 만들고 −14 LUFS로 맞춘다.

  python3 scripts/make-audio.py   → audio/mix.wav (+ audio/mix.json 측정값)

· 효과음 레시피는 15초판 scripts/make-audio.py(게임 SoundKit.swift 이식: 드라이버 타격음·스윙 우시·착지 탭·차임, 타건·클릭)를 옮겼다.
· 타이밍은 src/main.js 와 같은 값이다(타이핑 TYPE·전송, 임팩트 f11, 착지 f86, 클릭 f118/f122, 컷 CUTS, 자막 진입, 엔드 f344).
· 비트: 95BPM 로파이(킥·림·하이햇·로즈 코드), 음악 버스 저역 통과. 임팩트 순간 0.3초 덕킹. 끝 0.6초 페이드.
· 라우드니스: ffmpeg ebur128로 재며 게인 → 결정적 피크 리미터(샘플 피크 −2.5 dBFS)를 반복해 통합 −14 LUFS · 트루피크 ≤ −1.5 dBTP.
· 결정론: 노이즈는 SoundKit의 LCG 수열(시드 고정), 난수·시계 없음 → 같은 WAV(md5)가 나온다.
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; FPS = 30; DUR = 14.5; N = int(SR * DUR)
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = HERE + "/audio"; os.makedirs(OUT, exist_ok=True)

class LCG:
    def __init__(self, s=0x9E3779B9): self.s = s
    def white(self, n):
        out = np.empty(n); s = self.s
        for i in range(n):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF; out[i] = s / 0xFFFFFFFF * 2 - 1
        self.s = s; return out

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
def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i < 0: s = s[-i:]; i = 0
    if i >= len(buf): return
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g

# ── 효과음 (SoundKit 레시피 이식 + 같은 결의 신규) ──
def impact_wood(power=1.0):
    t = T(0.1); n = LCG().white(len(t))
    return (np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", 2000, 1.2) * np.exp(-t / 0.008) * 0.9) * (0.4 + 0.45 * power)
def whoosh(d=0.26, power=1.0, f0=350, f1=900, seed=77):
    t = T(d); n = LCG(seed).white(len(t)); u = t / d; y = np.zeros_like(t); parts = 8
    for k in range(parts):
        a, b = k * len(t) // parts, (k + 1) * len(t) // parts
        y[a:b] = biquad(n[a:b], "bp", f0 + (f1 - f0) * (k + .5) / parts, 0.9)
    return y * np.sin(np.pi * u) ** 2 * (0.10 + 0.25 * power)
def bounce(speed=9, cutoff=1000):
    t = T(0.04); n = LCG(5).white(len(t)); s = biquad(n, "lp", cutoff, 0.8) * np.exp(-t / 0.01)
    if speed > 8: s += np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.015) * 0.3
    return s * min(1, speed / 10) * 0.5
def roll(d=0.55):
    t = T(d); n = LCG(11).white(len(t)); return biquad(n, "lp", 500, 0.7) * np.exp(-t / 0.18) * 0.12
def chime():
    t = T(1.1); s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.2
def key(v):
    t = T(0.05); n = LCG(1000 + v * 17).white(len(t)); f = [2600, 3100, 2300, 2850, 3400][v % 5]
    return (biquad(n, "bp", f, 1.6) * np.exp(-t / 0.006) * 0.9 + np.sin(2 * np.pi * (420 + 40 * v) * t) * np.exp(-t / 0.008) * 0.25) * 0.30
def space_key():
    t = T(0.08); n = LCG(4242).white(len(t))
    return (biquad(n, "lp", 900, 0.8) * np.exp(-t / 0.014) * 0.8 + np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.02) * 0.4) * 0.32
def click(seed=99, f=3800):
    t = T(0.03); n = LCG(seed).white(len(t))
    return (biquad(n, "bp", f, 1.4) * np.exp(-t / 0.004) + np.sin(2 * np.pi * 1300 * t) * np.exp(-t / 0.005) * 0.3) * 0.34
def pop():   # 채팅 전송 '톡': 짧게 내려가는 음 + 아래 쿵
    t = T(0.09); f = 1150 - 500 * np.minimum(1, t / 0.05)
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.022) * 0.5 + np.sin(2 * np.pi * 210 * t) * np.exp(-t / 0.03) * 0.25) * 0.42
def flap(seed):   # 플립 시계 '착'
    t = T(0.045); n = LCG(seed).white(len(t))
    return (biquad(n, "bp", 2300, 1.1) * np.exp(-t / 0.007) * 0.9 + np.sin(2 * np.pi * 320 * t) * np.exp(-t / 0.01) * 0.35) * 0.36
def tick():   # 자막 날아들 때 틱
    t = T(0.03); n = LCG(321).white(len(t)); return (biquad(n, "bp", 5200, 2.0) * np.exp(-t / 0.004)) * 0.28

# ── 로파이 비트 95BPM ──
BPM = 95; BEAT = 60 / BPM
def note(m): return 440 * 2 ** ((m - 69) / 12)
def kick():
    t = T(0.32); f = 48 + 70 * np.exp(-t / 0.04); return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13) * 0.55
def rim():
    t = T(0.08); n = LCG(808).white(len(t)); return (biquad(n, "bp", 1700, 1.2) * np.exp(-t / 0.02) * 0.7 + np.sin(2 * np.pi * 420 * t) * np.exp(-t / 0.015) * 0.2) * 0.28
def hat(amp=0.08):
    t = T(0.035); n = LCG(3131).white(len(t)); return biquad(n, "bp", 7600, 0.9) * np.exp(-t / 0.01) * amp
def rhodes(f, d, amp):
    t = T(d); mod = np.sin(2 * np.pi * f * 2 * t) * 1.1 * np.exp(-t / 0.35)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 1.4) * np.minimum(1, t / 0.006) * amp
CH = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]   # Fmaj7 · Em7 · Dm7 · Cmaj7

def music():
    m = np.zeros(N)
    for b in range(int(DUR / BEAT) + 2):
        t0 = b * BEAT
        if b % 4 in (0, 2) or (b % 8 == 7): put(m, kick(), t0)
        if b % 4 in (1, 3): put(m, rim(), t0)
        put(m, hat(0.07), t0); put(m, hat(0.045), t0 + BEAT / 2 + 0.02)    # 살짝 늘어진 8분 하이햇(로파이 스윙)
        if b % 4 == 0:
            c = CH[(b // 4) % 4]
            for i, mm in enumerate(c): put(m, rhodes(note(mm + 12), 4 * BEAT + 0.6, 0.075), t0 + 0.012 * i)
            put(m, rhodes(note(c[0] - 12), 2 * BEAT, 0.12), t0)
    return biquad(m, "lp", 3600, 0.7)   # 로파이 톤

# ── 이벤트 (src/main.js 와 같은 값) ──
TYPE = [["네, 확인했습니다", -16, 4, 38], ["네", 199, 3, 205], ["좋습니다", 226, 3, 241], ["다음 주에 뵙겠습니다", 258, 2, 281]]
CUTS = [170, 190, 214, 234, 254, 276]
F = lambda f: f / FPS
sfx = np.zeros(N)
v = 0
for txt, f0, rate, fs in TYPE:
    for i, ch in enumerate(txt):
        ft = f0 + i * rate
        if 0 <= ft < fs: put(sfx, space_key() if ch == " " else key(v), F(ft)); v += 1
    put(sfx, pop(), F(fs))
put(sfx, whoosh(0.24, 1.0), F(11) - 0.2); put(sfx, impact_wood(1.0), F(11) - 1 / FPS)           # 스윙 우시 → 타격(1프레임 먼저)
put(sfx, bounce(9, 1000), F(86)); put(sfx, bounce(4, 800), F(95), 0.6); put(sfx, roll(), F(95))  # 착지·홉·굴림
put(sfx, click(), F(118)); put(sfx, click(101, 3300), F(122), 0.8)                              # 클릭 2톡
for c in CUTS:
    put(sfx, whoosh(0.16, 0.7, 500, 1500, seed=200 + c), F(c - 2) - 0.03)                       # 휩 팬
    put(sfx, flap(500 + c), F(c)); put(sfx, flap(600 + c), F(c + 3), 0.85)                       # 플립 '착착'
put(sfx, flap(166), F(166), 0.7)                                                               # 시계 들어올 때
for f in (98, 101, 312): put(sfx, tick(), F(f))                                                 # 자막 진입
put(sfx, whoosh(0.5, 0.5, 300, 700, seed=9), F(334))                                            # 원형 마스크
put(sfx, chime(), F(344))                                                                       # 엔드카드

mus = music()
t = np.arange(N) / SR
duck = 1 - 0.65 * np.exp(-np.maximum(0, t - F(11)) / 0.12) * (t >= F(11) - 0.02)                 # 임팩트 0.3초 덕킹
duck = np.minimum(duck, 1 - 0.65 * np.clip((t - (F(11) - 0.03)) / 0.03, 0, 1) * (t < F(11)))
mix = mus * 0.55 * duck + sfx
fade = np.clip((DUR - t) / 0.6, 0, 1); mix *= fade

def measure(x):
    tmp = OUT + "/_m.wav"; write(tmp, x)
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", tmp, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    s = r[r.rfind("Summary:"):]; os.remove(tmp)
    return float(re.search(r"I:\s*(-?[\d.]+) LUFS", s).group(1)), float(re.search(r"Peak:\s*(-?[\d.]+) dBFS", s).group(1))
def write(p, x):
    y = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    st = np.stack([y, y], axis=1).reshape(-1)
    with wave.open(p, "wb") as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(st.tobytes())
def limit(x, ceil_db=-2.5):
    c = 10 ** (ceil_db / 20); a = np.abs(x); g = np.minimum(1, c / np.maximum(a, 1e-9))
    w = int(0.004 * SR); gm = g.copy()
    for k in range(1, w + 1): gm[:-k] = np.minimum(gm[:-k], g[k:]); gm[k:] = np.minimum(gm[k:], g[:-k])   # 앞뒤 4ms 최소(룩어헤드)
    sm = np.convolve(gm, np.ones(w) / w, mode="same")   # 부드럽게
    return x * np.minimum(gm, sm)
x = mix
for it in range(4):
    I, TP = measure(x)
    x = limit(x * 10 ** ((-14 - I) / 20))
I, TP = measure(x)
write(OUT + "/mix.wav", x)
json.dump({"integratedLUFS": I, "truePeak_dBTP": TP, "dur": DUR, "sr": SR}, open(OUT + "/mix.json", "w"))
print("mix.wav", "I", I, "TP", TP)
