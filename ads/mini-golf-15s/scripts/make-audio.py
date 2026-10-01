#!/usr/bin/env python3
"""오디오 합성 — 외부 음원·TTS 없음. numpy로 효과음 + BGM을 만들고 언어별 믹스를 쓴다.

  python3 scripts/make-audio.py   → audio/mix-ko.wav, audio/mix-en.wav (+ .json 측정값), audio/stems/*.wav

· 효과음 레시피는 게임 SoundKit.swift를 그대로 옮겼다(드라이버 타격음·착지 탭·차임). 타건·클릭은 같은 '작고 마른' 결로 새로 만든다.
· 타이밍은 src/main.js 와 같은 식으로 계산한다(타이핑 시각, 임팩트 f11, 착지 f112, 클릭 f247/f251, 엔드카드 f346).
· BGM: 90BPM(박 = 20프레임), 박자 격자를 임팩트 f11에 맞춰 착지 f111·클릭 f251·엔드 f331이 박에 온다.
  구간: 0–3.7초 패드+로즈 / 착지 뒤 0.8초 거의 무음(마침표의 '조용히') / 4.5–11.2초 베이스·하이햇 그루브 / 엔드 해결 화음, 15.0초에 무음.
· 라우드니스: 정적 게인으로 통합 -14 LUFS, 트루피크 ≤ -2.5 dBFS (HyperFrames AAC 자동 감쇠 회피 — _shared/audio/mix.py 와 같은 기준).
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; FPS = 30; DUR = 15.0; N = int(SR * DUR)
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = HERE + "/audio"; os.makedirs(OUT + "/stems", exist_ok=True)

class LCG:  # SoundKit NoiseLCG 와 같은 수열 (결정론)
    def __init__(self, s=0x9E3779B9): self.s = s
    def white(self, n):
        out = np.empty(n)
        s = self.s
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

# ── 효과음 (SoundKit 레시피) ──
def impact_wood(power=1.0):
    t = T(0.1); n = LCG().white(len(t))
    s = np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", 2000, 1.2) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def whoosh(d=0.26, power=1.0):
    t = T(d); n = LCG(77).white(len(t)); u = t / d
    y = np.zeros_like(t); # 스윕 밴드패스: 구간별 근사
    parts = 8
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
    t = T(0.9)
    s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.16
# ── 타건 (작고 마른 톡, 5종을 돌려 쓴다) ──
def key(v):
    t = T(0.05); n = LCG(1000 + v * 17).white(len(t))
    f = [2600, 3100, 2300, 2850, 3400][v % 5]
    s = biquad(n, "bp", f, 1.6) * np.exp(-t / 0.006) * 0.9 + np.sin(2 * np.pi * (420 + 40 * v) * t) * np.exp(-t / 0.008) * 0.25
    return s * 0.30
def space_key():
    t = T(0.08); n = LCG(4242).white(len(t))
    return (biquad(n, "lp", 900, 0.8) * np.exp(-t / 0.014) * 0.8 + np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.02) * 0.4) * 0.32
def click():
    t = T(0.03); n = LCG(99).white(len(t))
    return (biquad(n, "bp", 3800, 1.4) * np.exp(-t / 0.004) + np.sin(2 * np.pi * 1300 * t) * np.exp(-t / 0.005) * 0.3) * 0.34

# ── BGM ──
BEAT = 20 / FPS; OFF = 11 / FPS
def note(m): return 440 * 2 ** ((m - 69) / 12)
def rhodes(f, d, amp):
    t = T(d); mod = np.sin(2 * np.pi * f * 2 * t) * 1.2 * np.exp(-t / 0.35)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 0.9) * np.minimum(1, t / 0.004) * amp
def pad(freqs, d, amp):
    t = T(d); s = np.zeros_like(t)
    for i, f in enumerate(freqs):
        for det in (-0.12, 0.12):
            s += np.sin(2 * np.pi * (f * (1 + det / 100)) * t + i) + 0.18 * np.sin(2 * np.pi * 2 * f * t + i)
    env = np.minimum(1, t / 0.6) * np.minimum(1, (d - t) / 0.8)
    return s * env * amp / len(freqs)
def hat(amp):
    t = T(0.04); n = LCG(3131).white(len(t))
    return biquad(n, "bp", 7200, 0.9) * np.exp(-t / 0.012) * amp
def bass(f, d, amp):
    t = T(d); return (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 1.1) * np.minimum(1, t / 0.01) * amp

CH = [  # 2박 = 1마디(2/2 느낌) 단위 코드: Fmaj9 · Am7 · Dm9 · Bbmaj7
    [53, 57, 60, 64, 67], [57, 60, 64, 67], [50, 57, 60, 64, 65], [46, 57, 62, 65, 69]]

def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i >= len(buf): return
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g

def bgm():
    b = np.zeros(N)
    # 패드: 4박마다 코드 (첫 프레임부터 울리고 있다 — 페이드인 시작 금지 → 앞 코드가 음수 시각에서 시작한 것처럼)
    for k in range(-1, 6):
        t0 = OFF + k * 4 * BEAT
        c = CH[k % 4] if k < 4 else CH[0]
        s = pad([note(m) for m in c], 4 * BEAT + 0.9, 0.16)
        if t0 < 0: s = s[int(-t0 * SR):]; t0 = 0
        put(b, s, t0)
    # 로즈: 박마다 코드 음 하나(아르페지오), 착지 전은 2박마다
    for k in range(0, 22):
        t0 = OFF + k * BEAT
        c = CH[(k // 4) % 4]
        if t0 < 3.72 and k % 2: continue
        put(b, rhodes(note(c[(k * 2) % len(c)] + 12), 1.2, 0.10), t0)
    # 베이스·하이햇: 착지 뒤 0.8초 쉬고(4.53초) 엔드카드 전까지
    for k in range(0, 22):
        t0 = OFF + k * BEAT
        if 4.5 <= t0 < 11.1:
            put(b, bass(note(CH[(k // 4) % 4][0] - 12), BEAT * 1.9, 0.20), t0) if k % 2 == 0 else None
            put(b, hat(0.05), t0 + BEAT / 2)
    # 엔드: 해결 화음 Fmaj9 (11.03초 = 박) — 길게, 15초 전에 사라진다
    put(b, pad([note(m) for m in CH[0]], 3.7, 0.14), OFF + 16 * BEAT)
    put(b, rhodes(note(72), 2.5, 0.12), OFF + 16 * BEAT); put(b, rhodes(note(76), 2.5, 0.09), OFF + 16 * BEAT + 0.12)
    # 자동화: 착지 직후 딥(마침표 뒤 쉼), 끝 1.2초 페이드 → 15.0초 무음
    t = np.arange(N) / SR
    g = np.ones(N)
    g *= np.interp(t, [0, 3.70, 3.78, 4.45, 4.60, 20], [1, 1, 0.13, 0.13, 1, 1])
    g *= np.interp(t, [0, 13.6, 14.85, 20], [1, 1, 0, 0])
    return b * g

def schedule(lang):
    KO = lang == "ko"
    kick = "코드를 쓰는 동안," if KO else "While you code,"
    s0, s1 = ("9홀이 조용히", "돌아갑니다") if KO else ("nine holes", "play quietly")
    F_K = 36; KR = 3.2 if KO else 2.0
    F_S = round(F_K + len(kick) * KR + 6); SR_ = (106 - F_S) / (len(s0) + len(s1))
    keys = [(F_K + i * KR, c) for i, c in enumerate(kick)] + [(F_S + i * SR_, c) for i, c in enumerate(s0 + s1)]
    ed = []   # 에디터: f0 54자 → f30 67자 (0.45자/프레임)
    prev = 54
    for f in range(0, 31):
        n = min(67, 54 + int(f * 0.45))
        if n > prev: ed.append(f); prev = n
    return keys, ed

def write_wav(path, x):
    x = np.clip(x, -1, 1); st = np.stack([x, x], 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st * 32767).astype("<i2").tobytes())

def ebur(path):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True)
    s = p.stderr[p.stderr.rfind("Summary:"):]
    return float(re.search(r"I:\s*(-?[\d.]+) LUFS", s).group(1)), float(re.search(r"Peak:\s*(-?[\d.]+) dBFS", s).group(1))

BG = bgm()
write_wav(OUT + "/stems/bgm.wav", BG)
for lang in ("ko", "en"):
    keys, ed = schedule(lang)
    fx = np.zeros(N); log = []
    add = lambda s, f, g=1.0, name="": (put(fx, s, max(0, f - 1) / FPS, g), log.append([name, round(f, 2)]))   # 소리는 화면 타점보다 1프레임 먼저
    for i, f in enumerate(ed): add(key(i), f, 0.8, "key-editor")
    add(whoosh(0.24), 8.5, 0.8, "whoosh"); add(impact_wood(1.0), 11, 1.0, "impact")
    for i, (f, c) in enumerate(keys): add(space_key() if c == " " else key(i + 3), f, 1.0, "key")
    add(bounce(10, 1000), 112, 1.1, "land-period"); add(space_key(), 112, 0.7, "period-key"); add(bounce(4, 1000), 122, 0.9, "hop")
    add(click(), 247, 1.0, "click-down"); add(click(), 251, 0.8, "click-up")
    add(chime(), 348, 0.9, "end-chime")
    mix = BG * 0.55 + fx
    tmp = OUT + f"/stems/fx-{lang}.wav"; write_wav(tmp, fx)
    # 라우드니스: 정적 게인 반복 → -14 LUFS, 피크는 부드러운 무릎 클리퍼(-7 dBFS 위만 눌러 천장 -3.4 dBFS — 트랜지언트만 건드린다)
    g = 1.0; path = OUT + f"/mix-{lang}.wav"
    for it in range(6):
        y = mix * g
        th, c = 10 ** (-7 / 20), 10 ** (-3.4 / 20); a = np.abs(y); over = a > th   # 무릎 -7 dBFS, 천장 -3.4 dBFS
        y[over] = np.sign(y[over]) * (th + (c - th) * np.tanh((a[over] - th) / (c - th)))
        write_wav(path, y); I, TP = ebur(path)
        if abs(I + 14) < 0.2 and TP <= -2.5: break
        g *= 10 ** ((-14 - I) / 20)
        if TP > -2.5: g *= 0.98
    json.dump({"lang": lang, "I": I, "TP": TP, "gain": g, "events": log}, open(OUT + f"/mix-{lang}.json", "w"), ensure_ascii=False, indent=1)
    print(lang, "I", I, "LUFS · TP", TP, "dBFS · events", len(log))
