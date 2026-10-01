#!/usr/bin/env python3
"""오디오 합성 — 외부 음원·TTS 없음. numpy로 효과음 + 120BPM BGM을 만들고 언어별 믹스를 쓴다.

  python3 scripts/make-audio.py   → audio/mix-ko.wav, audio/mix-en.wav (+ .json 측정값·이벤트 목록), audio/stems/*.wav

· 타이밍 단일 출처: src/timeline.js (컴포지션과 같은 파일). 클립 안의 게임 사건(거위 꽥·강아지 멍·뻐꾸기·컵인)은
  게임 로그의 원본 시각을 timeline.js 클립 맵으로 광고 프레임에 옮긴다 (map_src).
· 효과음 레시피는 게임 SoundKit.swift를 옮겼다(드라이버 타격음·착지 탭·홀인·차임·꽥·멍·뻐꾹·틱). 소리는 화면 타점보다 1프레임 먼저 둔다.
· BGM 120BPM(1박 = 15프레임): 0–1초 슬로모 인트로(패드 + 라이저) → f30 임팩트에서 드롭 → 그루브 A → f120 마침표에서 1박 정적
  → 빌드업 → f180 몽타주 그루브 B(7마디) → f600 브레이크다운(정직 비트) → f720 엔드(타건) → f780 엔터 = 마지막 화음 → 29.7초 무음.
· 라우드니스: 통합 −14 LUFS, 트루피크 ≤ −1.5 dBTP (정적 게인 + 부드러운 무릎 클리퍼).
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
TL = json.loads(re.search(r"window\.TL\s*=\s*(\{.*\});", open(HERE + "/src/timeline.js").read(), re.S).group(1))
FPS = TL["fps"]; NF = TL["frames"]; DUR = NF / FPS; N = int(SR * DUR)
BEAT = TL["beat"] / FPS                      # 0.5초
OUT = HERE + "/audio"; os.makedirs(OUT + "/stems", exist_ok=True)
F = lambda f: f / FPS                        # 프레임 → 초

class LCG:  # SoundKit NoiseLCG 와 같은 수열 (결정론)
    def __init__(self, s=0x9E3779B9): self.s = s
    def white(self, n):
        out = np.empty(n); s = self.s
        for i in range(n):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            out[i] = s / 0xFFFFFFFF * 2 - 1
        self.s = s; return out
def noise(n, seed): return np.random.default_rng(seed).uniform(-1, 1, n)   # 긴 잡음은 시드 고정 numpy (결정론)

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
def fft_band(x, lo, hi, soft=0.15):
    """주파수 영역 대역 통과 (긴 잡음용, 벡터화)"""
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    m = np.clip((fr - lo * (1 - soft)) / (lo * soft + 1e-9), 0, 1) * np.clip((hi * (1 + soft) - fr) / (hi * soft + 1e-9), 0, 1)
    return np.fft.irfft(X * m, len(x))
def T(d): return np.arange(int(d * SR)) / SR

# ── 효과음 (SoundKit 레시피 이식) ──
def impact_wood(power=1.0):
    t = T(0.12); n = LCG().white(len(t))
    s = np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + biquad(n, "bp", 2000, 1.2) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def putter_tap():
    t = T(0.09); n = LCG().white(len(t))
    return (np.sin(2 * np.pi * 1200 * t) * np.exp(-t / 0.008) * 0.35 + np.sin(2 * np.pi * 430 * t) * np.exp(-t / 0.022) * 0.45
            + biquad(n, "bp", 1800, 1.2) * np.exp(-t / 0.006) * 0.8) * 0.5
def whoosh(d=0.26, power=1.0, seed=77, lo=350, hi=900):
    t = T(d); n = LCG(seed).white(len(t)); y = np.zeros_like(t); parts = 10
    for k in range(parts):
        a, b = k * len(t) // parts, (k + 1) * len(t) // parts
        y[a:b] = biquad(n[a:b], "bp", lo + (hi - lo) * (k + .5) / parts, 0.9)
    return y * np.sin(np.pi * t / d) ** 2 * (0.10 + 0.25 * power)
def bounce(speed=9, cutoff=1000):
    t = T(0.05); n = LCG(5).white(len(t)); s = biquad(n, "lp", cutoff, 0.8) * np.exp(-t / 0.01)
    if speed > 8: s += np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.015) * 0.3
    return s * min(1, speed / 10) * 0.5
def hole_in():
    t = T(0.45); n = biquad(LCG().white(len(t)), "bp", 1400, 1.2); s = np.sin(2 * np.pi * 240 * t) * np.exp(-t / 0.12) * 0.22
    for t0, amp in [(0, 1), (0.055, 0.8), (0.125, 0.62), (0.21, 0.45)]:
        m = t >= t0; dt = t[m] - t0; s[m] += (n[m] * np.exp(-dt / 0.006) + np.sin(2 * np.pi * 900 * dt) * np.exp(-dt / 0.01) * 0.4) * amp
    return s * 0.55
def chime():
    t = T(1.0); s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.3)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.3)
    return s * 0.16
def honk():
    t = T(0.3); u = t / 0.3; f = 300 + 40 * np.sin(2 * np.pi * 9 * t) - 60 * u
    ph = np.cumsum(f) / SR; saw = 2 * (ph - np.floor(ph + 0.5)); sq = np.where(np.sin(2 * np.pi * 2 * ph) > 0, 0.3, -0.3)
    return (saw * 0.7 + sq) * np.sin(np.pi * u) * 0.06
def woof():
    t = T(0.16); f = 420 - 1200 * t; ph = np.cumsum(f) / SR; saw = 2 * (ph - np.floor(ph + 0.5))
    return biquad(saw, "lp", 1400, 0.9) * np.minimum(1, t / 0.01) * np.exp(-t / 0.05) * 0.14
def cuckoo():
    t = T(0.5); s = np.zeros_like(t)
    for t0, f, d in [(0, 784.0, 0.2), (0.23, 622.0, 0.27)]:
        m = (t >= t0) & (t < t0 + d + 0.2); tt = t[m] - t0
        s[m] += (np.sin(2 * np.pi * f * tt) + 0.15 * np.sin(2 * np.pi * 2 * f * tt)) * np.minimum(1, tt / 0.015) * np.exp(-tt / 0.12)
    return s * 0.11
def tick():
    t = T(0.05); n = LCG(31).white(len(t))
    return biquad(n, "bp", 3200, 2.0) * np.exp(-t / 0.004) * 0.35 + np.sin(2 * np.pi * 1900 * t) * np.exp(-t / 0.006) * 0.05
def key(v):
    t = T(0.05); n = LCG(1000 + v * 17).white(len(t)); f = [2600, 3100, 2300, 2850, 3400][v % 5]
    return (biquad(n, "bp", f, 1.6) * np.exp(-t / 0.006) * 0.9 + np.sin(2 * np.pi * (420 + 40 * (v % 5)) * t) * np.exp(-t / 0.008) * 0.25) * 0.30
def space_key():
    t = T(0.08); n = LCG(4242).white(len(t))
    return (biquad(n, "lp", 900, 0.8) * np.exp(-t / 0.014) * 0.8 + np.sin(2 * np.pi * 180 * t) * np.exp(-t / 0.02) * 0.4) * 0.32
def enter_key():
    t = T(0.14); n = LCG(777).white(len(t))
    return (biquad(n, "lp", 700, 0.8) * np.exp(-t / 0.02) * 0.9 + np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.035) * 0.55) * 0.42
def click():
    t = T(0.03); n = LCG(99).white(len(t))
    return (biquad(n, "bp", 3800, 1.4) * np.exp(-t / 0.004) + np.sin(2 * np.pi * 1300 * t) * np.exp(-t / 0.005) * 0.3) * 0.34
def pop():
    t = T(0.12); n = LCG(55).white(len(t))
    return n * np.exp(-t / 0.006) * 0.25 + np.sin(2 * np.pi * 240 * t) * np.exp(-t / 0.03) * 0.18
def blip_down():  # 종료 — 아래로 가라앉는 두 음 (조용한 사라짐)
    t = T(0.36); s = np.zeros_like(t)
    for t0, f, d in [(0, 660.0, 0.12), (0.11, 440.0, 0.25)]:
        m = (t >= t0) & (t < t0 + d); tt = t[m] - t0
        s[m] += np.sin(2 * np.pi * f * tt) * np.minimum(1, tt / 0.005) * np.exp(-tt / 0.08)
    return s * 0.10

# ── BGM 악기 ──
def note(m): return 440 * 2 ** ((m - 69) / 12)
def kick(v=1.0):
    t = T(0.45); f = 44 + 110 * np.exp(-t / 0.035); ph = np.cumsum(f) / SR
    body = np.sin(2 * np.pi * ph) * np.exp(-t / 0.26)
    clk = np.diff(np.concatenate([[0], noise(len(t), 11)])) * np.exp(-t / 0.002) * 0.25
    return (body + clk) * 0.62 * v
def clap(v=1.0, seed=21):
    t = T(0.25); n = noise(len(t), seed); env = np.zeros_like(t)
    for t0 in (0, 0.009, 0.018): env += (t >= t0) * np.exp(-np.clip(t - t0, 0, None) / 0.007)
    env += (t >= 0.027) * np.exp(-np.clip(t - 0.027, 0, None) / 0.09) * 0.55
    return fft_band(n * env, 900, 3200) * 0.55 * v
def hat(v=1.0, open_=False, seed=31):
    d = 0.22 if open_ else 0.05; t = T(d); n = fft_band(noise(len(t), seed), 7000, 15000)
    return n * np.exp(-t / (0.09 if open_ else 0.014)) * 0.22 * v
def bass(m, d, v=1.0):
    t = T(d); f = note(m); s = np.zeros_like(t)
    for k, a in [(1, 1), (2, 0.42), (3, 0.2), (4, 0.09)]: s += a * np.sin(2 * np.pi * f * k * t)
    env = np.minimum(1, t / 0.006) * (0.62 + 0.38 * np.exp(-t / 0.09)) * np.minimum(1, (d - t) / 0.03)
    return s * env * 0.20 * v
def rhodes(f, d, amp):
    t = T(d); mod = np.sin(2 * np.pi * f * 2 * t) * 1.1 * np.exp(-t / 0.3)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 0.7) * np.minimum(1, t / 0.004) * np.minimum(1, (d - t) / 0.02) * amp
def stab(ch, d=0.26, amp=0.05): return sum(rhodes(note(m + 12), d, amp) for m in ch[1:])
def pad(ms, d, amp, att=0.5, rel=0.8):
    t = T(d); s = np.zeros_like(t)
    for i, m in enumerate(ms):
        f = note(m)
        for det in (-0.10, 0.10): s += np.sin(2 * np.pi * f * (1 + det / 100) * t + i) + 0.16 * np.sin(2 * np.pi * 2 * f * t + i)
    env = np.minimum(1, t / att) * np.minimum(1, (d - t) / rel)
    return s * env * amp / len(ms)
def pluck(m, amp=0.06):
    t = T(0.35); f = note(m)
    return (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 0.12) * np.minimum(1, t / 0.003) * amp
def riser(d, amp=0.08, seed=5, lo=300, hi=6000):
    t = T(d); n = noise(len(t), seed); y = np.zeros_like(t); parts = 24; L = len(t)
    for k in range(parts):
        a, b = k * L // parts, (k + 1) * L // parts
        c = lo * (hi / lo) ** ((k + .5) / parts); y[a:b] = fft_band(n[a:b], c * 0.6, c * 1.6)
    return y * (t / d) ** 2.2 * amp
def crash(amp=0.07, seed=9):
    t = T(1.4); n = fft_band(noise(len(t), seed), 3000, 11000)
    return n * np.exp(-t / 0.45) * np.minimum(1, t / 0.002) * amp
def subdrop(amp=0.30):
    t = T(0.9); f = 58 * np.exp(-t / 0.9) + 30; ph = np.cumsum(f) / SR
    return np.sin(2 * np.pi * ph) * np.exp(-t / 0.5) * np.minimum(1, t / 0.004) * amp

def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i < 0: s = s[-i:]; i = 0
    if i >= len(buf): return
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g

# 코드 진행 (1마디 = 2초 = 4박): F — C/E — Dm7 — B♭maj7 (I · V/3 · vi · IV), 밝게
PROG = [[41, 57, 60, 64, 69], [40, 55, 60, 64, 67], [38, 57, 60, 62, 65], [34, 58, 62, 65, 69]]
BASSN = [41, 40, 38, 34]
def chord(bar): return PROG[bar % 4]

def bgm():
    drums = np.zeros(N); music = np.zeros(N)
    beats = int(DUR / BEAT)
    for b in range(beats):
        t0 = b * BEAT; f0 = b * TL["beat"]; bar = b // 4; pos = b % 4
        ch = chord(bar)
        # ── 구간 ──
        intro = f0 < 30; groove_a = 30 <= f0 < 120; stop = 120 <= f0 < 135; build = 135 <= f0 < 180
        groove_b = 180 <= f0 < 600; brk = 600 <= f0 < 720; endtype = 720 <= f0 < 780; endhit = 780 <= f0 < 840; tail = f0 >= 840
        if groove_a or groove_b or endhit:
            put(drums, kick(1.0 if pos == 0 else 0.85), t0 - 1 / FPS)
            if pos in (1, 3): put(drums, clap(0.9, seed=21 + b % 3), t0)
            for e in (0, 0.5): put(drums, hat(0.8 if e else 0.55, seed=31 + (b * 2 + int(e * 2)) % 5), t0 + e * BEAT)
            if groove_b and pos in (1, 3): put(drums, hat(0.45, open_=True, seed=41 + b % 3), t0 + 0.5 * BEAT)
            # 베이스: 8분음, 킥 뒤 사이드체인 느낌(짧게)
            root = BASSN[bar % 4]
            for e, oct_ in ((0, 0), (0.5, 12 if groove_b and pos == 3 else 0)):
                put(music, bass(root + oct_, BEAT * 0.46, 0.85 if e else 1.0), t0 + e * BEAT)
            # 건반 스탭: 뒷박(엇박)에
            put(music, stab(ch, 0.24, 0.045 if groove_a else 0.05), t0 + 0.5 * BEAT)
        if build:
            k = b - 9                                                   # f135 = 9박째
            for e in range(4 if k >= 1 else 2):                          # 16분음 하이햇 크레센도
                put(drums, hat(0.25 + 0.2 * (f0 - 135) / 45, seed=51 + e), t0 + e * BEAT / (4 if k >= 1 else 2))
            put(music, bass(BASSN[bar % 4], BEAT * 0.9, 0.7), t0)
        if brk:
            if pos == 0: put(music, pad([m + 12 for m in ch[1:]], 4 * BEAT + 0.6, 0.10, att=0.2), t0)
            put(drums, hat(0.35, seed=61 + b % 4), t0 + 0.5 * BEAT)
            if pos in (0, 2): put(music, bass(BASSN[bar % 4], BEAT * 0.9, 0.7), t0)
        if endtype:
            if pos == 0: put(music, pad([m + 12 for m in ch[1:]], 4 * BEAT + 0.4, 0.09, att=0.1), t0)
            if pos in (0, 2): put(music, bass(BASSN[bar % 4], BEAT * 0.9, 0.6), t0)
    # 인트로 (f0–30): 슬로모 — 낮은 패드가 이미 울리고(페이드인 시작 아님) 라이저가 임팩트로 모인다
    put(music, pad([m for m in PROG[0][1:]], 1.6, 0.10, att=0.001, rel=0.5), 0)
    put(music, bass(29, 1.1, 0.8), 0)
    put(drums, riser(F(30), amp=0.11, seed=5, lo=250, hi=7000), 0)
    # 임팩트 드롭 (f30): 서브 드롭 + 크래시
    put(music, subdrop(0.34), F(30) - 1 / FPS); put(drums, crash(0.06), F(30))
    # 몽타주 컷 악센트 (다운비트 컷): 크래시 작게
    for fcut in (180, 240, 390, 450, 510, 540):
        put(drums, crash(0.045 if fcut != 180 else 0.06, seed=fcut), F(fcut))
    # 빌드업 라이저 → f180
    put(drums, riser(F(45), amp=0.09, seed=7, lo=400, hi=9000), F(135))
    # 리드 플럭 모티프 (몽타주 1·5마디): F 펜타토닉 4음 × 2
    motif = [72, 74, 77, 79, 77, 74, 72, 69]
    for bar0 in (3, 7):
        for i, m in enumerate(motif): put(music, pluck(m, 0.055), bar0 * 2 + i * BEAT / 2)
    # 엔드: f780 마지막 화음 → 길게 울리고 29.7초 무음
    put(music, pad([m + 12 for m in PROG[0][1:]] + [81], 3.6, 0.13, att=0.01, rel=1.6), F(780))
    put(music, rhodes(note(72), 3.0, 0.10), F(780)); put(music, rhodes(note(76), 3.0, 0.08), F(780) + 0.09); put(music, rhodes(note(81), 3.0, 0.06), F(780) + 0.18)
    put(drums, crash(0.06, seed=780), F(780)); put(music, subdrop(0.22), F(780) - 1 / FPS)
    # 마침표 뒤 1박 정적: f120–134 음악만 딥 (꼬리는 자연 감쇠 대신 12ms 램프로 끊는다)
    t = np.arange(N) / SR
    g = np.interp(t, [0, F(119.6), F(120.2), F(134.4), F(135), 40], [1, 1, 0.0, 0.0, 1, 1])
    g *= np.interp(t, [0, 28.4, 29.75, 40], [1, 1, 0, 0])
    return drums * g, music * g

# ── 이벤트 (광고 프레임) ──
def pw(mp, f):
    if f <= mp[0][0]: return mp[0][1]
    for a, b in zip(mp, mp[1:]):
        if f <= b[0]: return a[1] if b[0] == a[0] else a[1] + (b[1] - a[1]) * (f - a[0]) / (b[0] - a[0])
    return mp[-1][1]
def map_src(shot, src):
    """원본 초 → 광고 프레임 (구간 선형 맵의 역). 여러 구간이면 그 원본을 포함하는 첫 구간"""
    mp = next(s for s in TL["shots"] if s["id"] == shot)["map"]
    for a, b in zip(mp, mp[1:]):
        if b[0] > a[0] and a[1] <= src <= b[1]: return a[0] + (src - a[1]) / (b[1] - a[1]) * (b[0] - a[0])
    return None

KEY_G = 0.5   # 타건·UI 클릭 −6dB (2단계 결정: 청취 전 여유). 임팩트·마침표·엔터(마지막 화음)는 그대로
def events(lang):
    H = TL["hook"]; ev = []
    add = lambda name, snd, f, g=1.0: ev.append((name, snd, f, g))
    # 훅
    add("whoosh-down", whoosh(0.9, 1.0, lo=250, hi=700), H["impact"] - 26, 0.9)       # 슬로모 다운스윙 바람
    add("impact", impact_wood(1.0), H["impact"], 1.25)
    add("whoosh-pull", whoosh(0.7, 0.9, seed=78, lo=500, hi=1400), H["pullFrom"], 0.8)
    # 헤드라인 타건: 윗줄 12자 + 단어 3개(4프레임씩)
    kick_n = 12 if lang == "ko" else 16
    for i in range(kick_n): add("key", key(i), H["kick"][0] + i * (H["kick"][1] - H["kick"][0]) / kick_n, 0.8 * KEY_G)
    for j, fw in enumerate(H["words"]):
        for i in range(3): add("key", key(20 + j * 3 + i), fw + i * 1.4, 0.95 * KEY_G)
    add("period-land", bounce(10, 1000), H["land"], 1.1); add("period-key", space_key(), H["land"], 0.8)
    # M1 드라이브
    m1 = next(s for s in TL["shots"] if s["id"] == "m1")
    add("impact-m1", impact_wood(0.9), map_src("m1", m1["impactSrc"]) or 195, 1.0); add("whoosh-m1", whoosh(0.35, 0.8, seed=79), 188, 0.7)
    add("whoosh-track", whoosh(0.6, 0.7, seed=83, lo=500, hi=1300), 204, 0.55)                     # 추적 가속 구간
    add("land-m1", bounce(10, 800), map_src("m1", m1["landSrc"]) or 234, 1.1)
    # M2 거위 (게임 로그 순서: 앉음 꽥 → +0.5 훠이 꽥 → +1.2 흩어짐 꽥 + 0.25 꽥, 원본 초 → 맵)
    add("honk", honk(), 241, 0.9)                                                    # 들어올 때 (게임은 등장 직후 꽥 ×2)
    add("honk-sit", honk(), 270, 1.1)
    for src, g in ((11.30, 1.0), (12.50, 1.1), (12.75, 0.9)):
        f = map_src("m2", src); add("honk", honk(), f, g) if f else None
    add("scatter-tap", bounce(1.5, 1000), map_src("m2", 12.50) or 306, 0.8)
    # M3 강아지
    add("woof", woof(), 333, 1.0); add("woof", woof(), 344, 0.9)
    for name, src, snd, g in (("grab", 21.628, bounce(2, 800), 1.0), ("woof", 21.978, woof(), 1.0), ("drop", 22.678, bounce(2.5, 800), 1.0), ("woof", 22.978, woof(), 0.9)):
        f = map_src("m3", src); add(name, snd, f, g) if f else None
    # M4 헛스윙
    add("whiff", whoosh(0.32, 1.0, seed=80, lo=450, hi=1200), 399, 1.0)
    # M5a 뻐꾸기
    m5 = next(s for s in TL["shots"] if s["id"] == "m5a"); c0 = m5["clockT0"]
    add("clock-tick", tick(), 470, 1.0); add("clock-tick", tick(), map_src("m5a", c0 + 0.70) or 477, 1.0)
    for src in (c0 + 1.2, c0 + 2.0):
        f = map_src("m5a", src); add("cuckoo", cuckoo(), f, 1.6) if f else None
    add("roll-tick", click(), m5["roll"], 0.6 * KEY_G)
    # M5b 퍼트 → 컵인 → 배지
    add("putt", putter_tap(), map_src("m5b", 2.47) or 518, 1.1)
    add("hole-in", hole_in(), map_src("m5b", 3.08) or 535, 1.2)
    add("chime", chime(), next(s for s in TL["shots"] if s["id"] == "m5b")["toast"], 1.1)
    # 정직 비트
    Ho = TL["honest"]
    add("click-down", click(), Ho["press"] - 1, KEY_G); add("click-up", click(), Ho["press"] + 3, 0.8 * KEY_G); add("send-pop", pop(), Ho["press"] + 3, 0.7)
    add("click-flag", click(), Ho["flagClick"] - 1, KEY_G); add("click-flag-up", click(), Ho["flagClick"] + 3, 0.7 * KEY_G)
    add("quit", blip_down(), Ho["quit"], 1.0)
    # 엔드: 타건(2프레임마다 한 번 — 30타/초를 그대로 치면 윙 소리가 된다) → 엔터
    E = TL["end"]; nb = len("brew install --cask w0uldy0udaestar/tap/mini-golf")
    for i in range(0, nb, 2): add("key-end", key(40 + i // 2), E["type0"] + i / E["typeRate"], 0.75 * KEY_G)
    add("enter", enter_key(), E["enter"], 1.1)
    add("whoosh-reveal", whoosh(0.8, 0.6, seed=82, lo=300, hi=900), E["pullFrom"], 0.6)
    return ev

def write_wav(path, x):
    x = np.clip(x, -1, 1); st = np.stack([x, x], 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st * 32767).astype("<i2").tobytes())

def ebur(path):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True)
    s = p.stderr[p.stderr.rfind("Summary:"):]
    return float(re.search(r"I:\s*(-?[\d.]+) LUFS", s).group(1)), float(re.search(r"Peak:\s*(-?[\d.]+) dBFS", s).group(1))

DR, MU = bgm()
write_wav(OUT + "/stems/drums.wav", DR); write_wav(OUT + "/stems/music.wav", MU)
for lang in ("ko", "en"):
    fx = np.zeros(N); log = []
    for name, snd, f, g in events(lang):
        put(fx, snd, max(0, f - 1) / FPS, g); log.append([name, round(f, 2)])     # 소리는 화면 타점보다 1프레임 먼저
    write_wav(OUT + f"/stems/fx-{lang}.wav", fx)
    mix = DR * 0.8 + MU * 0.75 + fx * 1.0
    g = 1.0; path = OUT + f"/mix-{lang}.wav"
    for it in range(8):
        y = mix * g
        th, c = 10 ** (-6 / 20), 10 ** (-2.0 / 20); a = np.abs(y); over = a > th
        y[over] = np.sign(y[over]) * (th + (c - th) * np.tanh((a[over] - th) / (c - th)))
        write_wav(path, y); I, TP = ebur(path)
        if abs(I + 14) < 0.15 and TP <= -1.5: break
        g *= 10 ** ((-14 - I) / 20)
        if TP > -1.5: g *= 0.985
    json.dump({"lang": lang, "I": I, "TP": TP, "gain": g, "events": log}, open(OUT + f"/mix-{lang}.json", "w"), ensure_ascii=False, indent=1)
    print(lang, "I", I, "LUFS · TP", TP, "dBFS · events", len(log), "· gain", round(g, 3))
