#!/usr/bin/env python3
"""T1 오디오 — 전부 numpy 합성(외부 음원·TTS 없음). → audio/mix.wav (48kHz 스테레오) + audio/mix.json(측정값·사건 목록)

  python3 scripts/make-audio.py

· 효과음 결: 15초 편 make-audio.py의 SoundKit 이식 레시피(LCG 잡음, biquad, 나무 타격, 우시, 차임 660→880Hz)를 그대로 옮겨 쓰고,
  동물 소리(꽥·짹·냐·멍)는 같은 '작고 마른' 결의 배음 합성으로 새로 만든다.
· 타이밍은 src/main.js와 같은 상수에서 계산한다(컷 경계, 사건 = 히트스톱 시각, 자막 단어 입장 2f 간격, 풀백, 문장, 엔드카드).
  사건은 그 프레임 시각에 정확히 놓는다 — 영상과 프레임 단위로 맞는다.
· 비트: 123.43BPM(박 = 0.48611초) — 풀백 뒤 문장(8.75초)이 정확히 18박째. 킥 4박·하이햇 8분·박수 2·4박·베이스 3음(E2·G2·A2).
  8.75초에서 반 박 쉰 뒤 하이햇+베이스만 가볍게 → 10.75초 엔드카드 차임(게임 배지 소리)과 마지막 베이스로 끝, 마지막 0.3초 페이드.
· 라우드니스: 정적 게인 반복으로 통합 −14 LUFS, 부드러운 무릎 클리퍼로 트루피크 ≤ −2.5 dBTP(AAC 인코딩 여유 — 납품 기준 ≤ −1.5).
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; FPS = 30; DUR = 12.5; N = int(SR * DUR)
HERE = os.path.abspath(os.path.dirname(os.path.abspath(__file__)) + "/..")
OUT = HERE + "/audio"; os.makedirs(OUT, exist_ok=True)
F = lambda n: n / FPS

class LCG:  # SoundKit NoiseLCG와 같은 수열 (결정론)
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

# ── SoundKit 이식 (15초 편과 같은 레시피) ──
def impact_wood(power=1.0, seed=0x9E3779B9):
    t = T(0.1); n = LCG(seed).white(len(t))
    s = np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", 2000, 1.2) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def whoosh(d=0.26, power=1.0, lo=350, hi=900, seed=77):
    t = T(d); n = LCG(seed).white(len(t)); u = t / d; y = np.zeros_like(t); parts = 8
    for k in range(parts):
        a, b = k * len(t) // parts, (k + 1) * len(t) // parts
        y[a:b] = biquad(n[a:b], "bp", lo + (hi - lo) * (k + .5) / parts, 0.9)
    return y * np.sin(np.pi * u) ** 2 * (0.10 + 0.25 * power)
def chime():   # 게임 배지 소리: 660Hz → 0.14초 뒤 880Hz
    t = T(1.2)
    s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.16
def tick(v=0):   # 자막 단어 입장 '틱' (15초 편 타건 결)
    t = T(0.05); n = LCG(1000 + v * 17).white(len(t)); f = [2600, 3100, 2300, 2850, 3400][v % 5]
    return (biquad(n, "bp", f, 1.6) * np.exp(-t / 0.006) * 0.9 + np.sin(2 * np.pi * (420 + 40 * v) * t) * np.exp(-t / 0.008) * 0.25) * 0.30

# ── 새 소리 (같은 결의 배음 합성) ──
def voice(f0s, d, formant, bw=500, nh=10, noise=0.0, seed=1, vib=0.0):
    """배음 목소리: f0 궤적(시작·중간·끝)을 따라 1..nh 배음, 포먼트 근처 배음을 키운다."""
    t = T(d); u = t / d
    f0 = np.interp(u, np.linspace(0, 1, len(f0s)), f0s) * (1 + vib * np.sin(2 * np.pi * 7 * t))
    ph = 2 * np.pi * np.cumsum(f0) / SR; s = np.zeros_like(t)
    for k in range(1, nh + 1):
        g = np.exp(-((k * f0 - formant) / bw) ** 2) * 0.9 + 0.25 / k
        s += g * np.sin(k * ph)
    if noise: s += biquad(LCG(seed).white(len(t)), "bp", formant, 1.0) * noise
    env = np.minimum(1, t / 0.006) * np.exp(-np.maximum(0, t - 0.03) / (d * 0.45))
    return s * env / nh * 3
def honk(): return voice([520, 470, 400], 0.17, 1250, 420, 12, 0.15, 11) * 0.55
def chirp(): t = T(0.06); f = 3000 + 1300 * t / 0.06; return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.02) * np.minimum(1, t / 0.002) * 0.32
def meow(): return voice([640, 820, 760, 560], 0.30, 1500, 600, 10, 0.05, 23, vib=0.012) * 0.5
def bark(): return voice([420, 360, 300], 0.13, 950, 380, 10, 0.35, 31) * 0.75
def thump(g=1.0, seed=5):   # 히트스톱 '쿵' — 75→42Hz 내림 + 짧은 저역 잡음
    t = T(0.22); f = 42 + 33 * np.exp(-t / 0.05)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09) + biquad(LCG(seed).white(len(t)), "lp", 300, 0.7) * np.exp(-t / 0.012) * 0.5
    return s * 0.9 * g
def flap(seed): t = T(0.07); return biquad(LCG(seed).white(len(t)), "bp", 650, 0.8) * np.exp(-t / 0.022) * np.minimum(1, t / 0.004) * 0.55
def tok(f=1500, d=0.03, seed=7): t = T(0.06); return (np.sin(2 * np.pi * f * t) * np.exp(-t / d * 1.0) * 0.6 + biquad(LCG(seed).white(len(t)), "bp", f * 1.6, 1.4) * np.exp(-t / 0.004) * 0.4) * 0.5
def pop(): t = T(0.09); f = 300 + 700 * np.minimum(1, t / 0.035); return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.03) * np.minimum(1, t / 0.002) * 0.55
def patter(seed, g=0.25): t = T(0.03); return biquad(LCG(seed).white(len(t)), "lp", 1400, 0.7) * np.exp(-t / 0.006) * g
def clap_hit(seed, g=1.0): t = T(0.05); return biquad(LCG(seed).white(len(t)), "bp", 1900, 1.1) * np.exp(-t / 0.009) * np.minimum(1, t / 0.0008) * 0.5 * g
def crowd(d=1.4, seed=909):
    t = T(d); n = LCG(seed).white(len(t))
    s = biquad(n, "bp", 1100, 0.7) * 0.7 + biquad(n, "bp", 2600, 0.9) * 0.4
    env = np.minimum(1, t / 0.25) ** 1.5 * np.exp(-np.maximum(0, t - 0.45) / 0.45)
    return s * env * 0.55

# ── 비트 ──
BEAT = 8.75 / 18   # 123.43 BPM
def note(m): return 440 * 2 ** ((m - 69) / 12)
def kick(): t = T(0.2); f = 45 + 80 * np.exp(-t / 0.03); return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11) + biquad(LCG(3).white(len(t)), "lp", 2500, 0.7) * np.exp(-t / 0.003) * 0.3) * 0.8
def hat(amp): t = T(0.04); return biquad(LCG(3131).white(len(t)), "bp", 7200, 0.9) * np.exp(-t / 0.012) * amp
def clap(): t = T(0.08); n = LCG(4455).white(len(t)); e = sum(np.exp(-np.maximum(0, t - o) / 0.007) * (t >= o) for o in (0, 0.009, 0.018)); return biquad(n, "bp", 1500, 0.9) * e * 0.35
def bass(f, d, amp): t = T(d); return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 0.35) * np.minimum(1, t / 0.006) * np.minimum(1, (d - t) / 0.03) * amp

def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i >= len(buf): return
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g

def bgm():
    b = np.zeros(N); BL = [note(40), None, note(43), note(45)]   # E2 · — · G2 · A2
    nb = int(8.75 / BEAT + 1e-6)
    for k in range(nb):   # 0 ~ 8.75초: 킥 4박, 박수 2·4박, 하이햇 8분, 베이스 3음
        t = k * BEAT
        put(b, kick(), t, 0.9)
        if k % 2 == 1: put(b, clap(), t, 0.8)
        put(b, hat(0.22), t + BEAT / 2); put(b, hat(0.12), t)
        f = BL[k % 4]
        if f: put(b, bass(f, BEAT * 0.9, 0.5), t)
    # 8.75초: 반 박 쉼 → 하이햇과 베이스만 가볍게(문장 읽는 동안)
    t = 8.75 + BEAT / 2
    while t < 10.75 - 1e-6:
        put(b, hat(0.14), t + BEAT / 2)
        if int(round((t - 8.75) / BEAT - 0.5)) % 2 == 0: put(b, bass(note(40), BEAT * 0.8, 0.32), t)
        t += BEAT
    # 10.75초 엔드카드: 마지막 킥 + 길게 남는 베이스(E2)
    put(b, kick(), 10.75, 0.9); put(b, bass(note(40), 1.7, 0.5), 10.75); put(b, bass(note(52), 1.7, 0.18), 10.75)
    return b

# ── 사건 (src/main.js와 같은 상수) ──
CUTS = [("geese", 0, 5.11, 1.0, 6.64), ("bird", 2.75, 2.05, 1.15, 2.45), ("pin", 3.8, 1.25, 1.4, None), ("mole", 4.75, 0.85, 1.5, 1.62),
        ("cat", 5.55, 2.3, 1.3, None), ("dog", 6.25, 1.45, 1.6, 1.99), ("gallery", 6.9, 0.0, 1.0, None)]
HS = 2
def ad_time(cut, ct):   # 캡처 시각 → 광고 시각 (사건 뒤는 히트스톱 2f만큼 밀린다)
    _, t0, c0, sp, ev = cut; t = t0 + (ct - c0) / sp
    return t + (F(HS) if ev is not None and ct > ev else 0)
EV = {c[0]: (c[1] + (c[4] - c[2]) / c[3]) for c in CUTS if c[4] is not None}
CAPS = [(2.05, 3), (2.75, 2), (3.8, 2), (4.75, 2), (5.55, 3), (6.25, 2), (6.9, 2)]   # (입장 시각, 단어 수)
PULL = (7.5, 9.0); REV = 8.75; REV_WORDS = 7; END = 10.75

def schedule():
    fx = np.zeros(N); log = []
    def add(s, t, g=1.0, name=""): put(fx, s, max(0.0, t), g); log.append([name, round(t, 3), round(t * FPS, 1)])
    # 훅: 거위가 공 위에 앉아 있다 — 첫 프레임에 꽥 + 쿵, 0.95초에 한 번 더 작게 꽥(들썩임)
    add(honk(), 0.0, 1.0, "honk"); add(thump(0.7, 9), 0.0, 1.0, "sit-thud"); add(honk(), 0.95, 0.6, "honk2")
    # 거위 이륙: 히트스톱 쿵 → 날개 퍼덕 4회(점점 멀어진다) → 알 '톡'(자막 '알'과 함께)
    te = EV["geese"]; add(thump(), te, 1.0, "hitstop-geese")
    for i in range(4): add(flap(500 + i), te + F(HS) + 0.02 + i * 0.12, 1.0 - 0.18 * i, f"flap{i}")
    add(tok(1700, 0.03, 41), 2.05, 1.1, "egg-tok")
    # 새: 짹짹 → 채는 순간 히트스톱 쿵 + 짹 + 휘익(올라가는 스윕)
    add(chirp(), 2.80, 1.0, "chirp"); add(chirp(), 2.88, 0.8, "chirp2")
    te = EV["bird"]; add(thump(0.8, 13), te, 1.0, "hitstop-bird"); add(chirp(), te, 1.0, "chirp-grab")
    add(whoosh(0.4, 1.2, 500, 2600, 61), te + F(HS), 1.0, "swoosh-up")
    # 핀: 또각또각(다리 0.1초 주기 → 한 걸음 걸러) 캡처 1.3~2.6초
    ct, k = 1.3, 0
    while ct <= 2.6:
        add(tok(1800 if k % 2 else 2300, 0.018, 70 + k), ad_time(CUTS[2], ct), 0.75, "step"); ct += 0.2; k += 1
    # 두더지: 퐁(솟음, 캡처 0.84초 = 컷 시작) → 미는 순간 히트스톱 쿵 + 톡
    add(pop(), 4.75 + F(1), 1.0, "mole-pop")
    te = EV["mole"]; add(thump(0.8, 17), te, 1.0, "hitstop-mole"); add(tok(1100, 0.03, 88), te, 1.0, "mole-tok")
    # 고양이: 냐(한 톤) + 종종걸음
    add(meow(), 5.62, 1.0, "meow")
    t = 5.60; k = 0
    while t < 6.25 - F(2): add(patter(200 + k, 0.22), t, 1.0, "cat-step"); t += 0.09; k += 1
    # 강아지: 멍 + 달림(물기 전후) + 무는 순간 히트스톱 쿵
    add(bark(), 6.29, 1.0, "bark")
    te = EV["dog"]; t = 6.27; k = 0
    while t < 6.9 - F(2):
        if not (te - 0.02 < t < te + F(HS) + 0.02): add(patter(300 + k, 0.3), t, 1.0, "dog-run")
        t += 0.075; k += 1
    add(thump(0.85, 21), te, 1.0, "hitstop-dog")
    # 관중: 환호(잡음 스웰) + 박수 임펄스(결정적 간격)
    add(crowd(), 6.9, 1.0, "cheer")
    r = LCG(7777).white(80); t = 6.95; k = 0
    while t < 7.85:
        add(clap_hit(900 + k, 0.8 - 0.5 * (t - 6.95)), t, 1.0, "clap"); t += 0.035 + 0.03 * (r[k] + 1) / 2; k += 1
    # 휩 팬마다 짧은 우시 (경계 2f 전부터)
    for b in (2.75, 3.8, 4.75, 5.55, 6.25, 6.9): add(whoosh(0.2, 1.0, 600, 1800, int(b * 100)), b - F(2), 1.0, f"whip@{b}")
    # 자막 단어마다 틱(단어 입장 2f 간격) — 문장·엔드카드 포함
    for t0, n in CAPS:
        for i in range(n): add(tick(i), t0 + i * F(2), 0.7, "tick")
    for i in range(REV_WORDS): add(tick(i + 2), REV + i * F(2), 0.6, "tick-rev")
    # 풀백 속도 램프: 가운데가 가장 빠른 긴 우시(아래로 내려가는 스윕)
    add(whoosh(1.3, 1.4, 1600, 300, 4242), PULL[0] + 0.1, 0.9, "pull-whoosh")
    # 띠 테두리 쓸기 + 엔드카드 차임(게임 배지 소리)
    add(whoosh(0.3, 0.6, 900, 1500, 515), REV + 0.25, 0.6, "strip-swish")
    add(tick(0), END, 0.7, "tick-end"); add(chime(), END + F(1), 1.4, "end-chime")
    return fx, log

def write_wav(path, x):
    x = np.clip(x, -1, 1); st = np.stack([x, x], 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st * 32767).astype("<i2").tobytes())

def ebur(path):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True)
    s = p.stderr[p.stderr.rfind("Summary:"):]
    return float(re.search(r"I:\s*(-?[\d.]+) LUFS", s).group(1)), float(re.search(r"Peak:\s*(-?[\d.]+) dBFS", s).group(1))

if __name__ == "__main__":
    fx, log = schedule(); bg = bgm()
    mix = fx + bg * 0.42
    fade = np.ones(N); nf = int(0.3 * SR); fade[-nf:] = np.linspace(1, 0, nf) ** 1.5   # 마지막 0.3초 페이드
    path = OUT + "/mix.wav"; g = 1.0
    for it in range(8):
        y = mix * g
        th, c = 10 ** (-8 / 20), 10 ** (-3.2 / 20); a = np.abs(y); over = a > th   # 무릎 −8 dBFS, 천장 −3.2 dBFS
        y[over] = np.sign(y[over]) * (th + (c - th) * np.tanh((a[over] - th) / (c - th)))
        y *= fade
        write_wav(path, y); I, TP = ebur(path)
        if abs(I + 14) < 0.15 and TP <= -2.5: break
        g *= 10 ** ((-14 - I) / 20)
        if TP > -2.5: g *= 0.985
    first = int(np.argmax(np.abs(y) > 10 ** (-50 / 20))) / SR
    json.dump({"I": I, "TP": TP, "gain": g, "firstSoundSec": first, "bpm": round(60 / BEAT, 2), "events": log}, open(OUT + "/mix.json", "w"), ensure_ascii=False, indent=1)
    print("I", I, "LUFS · TP", TP, "dBTP · gain", round(g, 3), "· first sound", round(first, 4), "s · events", len(log))
