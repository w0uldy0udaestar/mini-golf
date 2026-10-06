#!/usr/bin/env python3
"""T5 오디오 (4차) — 처음부터 끝까지 끊기지 않는 중계 소리 바닥 + 또렷한 사건 소리. 외부 음원·TTS 없음, 전부 numpy 합성, 결정론.

  python3 scripts/make-audio.py   → audio/mix-ko.wav (+ mix-ko.json 측정값)

바닥 (첫 샘플부터)
  · 갤러리 웅성거림: 대역 잡음 + 말소리 알갱이(대역 잡음 버스트) + 느린 크기 흔들림. 비행 중 조금 부풀었다가 벙커에서 "아…"로 꺼진다
  · 중계 음악 120BPM(박 = 15프레임, 다운비트를 임팩트 f11에 맞춤): 브라스 패드(배음 합성 + 밝기 엔벨로프) · 베이스 · 킥 · 하이햇 · 클랩
    0–5.1초 D–G–A 그루브 → 벙커(5.13초) 드럼이 빠지고 단조 패드로 '김빠짐' → 6.8초 태그라인에서 다시 → 엔드 와이프 뒤 D 장화음 브라스로 해결
사건 (실프레임은 data/shot.js beats — 그림과 같은 히트스톱·속도 램프 반영값)
  임팩트 타격음·우시(15초 광고 SoundKit 레시피, 이전보다 +6dB) · 트레이서 톤(공 높이에 따라 오르내림) · 정점 '반짝' · 착지 '쿵' ·
  벙커 '푹'(모래) · 도장 '쿵' · 갤러리 "아…"(포먼트 합창 하강 + 숨 잡음) · 해설 타건(글자마다, 백스페이스 포함) · 리더보드 '띵' 두 번 ·
  오도미터 '드르륵'(표시 숫자가 정수를 넘을 때마다 틱) · 엔드 와이프 우시 + 차임
라우드니스: 통합 −14 LUFS, 트루피크 ≤ −1.5 dBTP(WAV는 AAC 여유로 −2.0 목표), 끝 0.6초 페이드
"""
import json, os, re, subprocess, wave
import numpy as np

SR = 48000; FPS = 30; DUR = 12.0; N = int(SR * DUR)
HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = HERE + "/audio"; os.makedirs(OUT, exist_ok=True)
SHOT = json.loads(open(HERE + "/data/shot.js").read().split("=", 1)[1].rstrip().rstrip(";"))
Bt = SHOT["beats"]; WARP = np.array(SHOT["warp"]); PTS = np.array(SHOT["pts"])
rng = np.random.default_rng(20261006)                       # 고정 시드 — 같은 numpy에서 항상 같은 수열

def T(d): return np.arange(int(d * SR)) / SR
def fr(f): return f / FPS                                   # 실프레임 → 초
def band(x, lo, hi, soft=0.35):
    """FFT 대역 필터(로그 주파수 반코사인 경계) — 루프 없이 빠르고 결정적"""
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR); lf = np.log2(np.maximum(f, 1))
    m = np.ones_like(f)
    if lo: m *= np.clip((lf - (np.log2(lo) - soft)) / (2 * soft), 0, 1)
    if hi: m *= np.clip(((np.log2(hi) + soft) - lf) / (2 * soft), 0, 1)
    m = 0.5 - 0.5 * np.cos(np.pi * m)
    return np.fft.irfft(X * m, len(x))
def put(buf, s, t0, g=1.0):
    i = int(round(t0 * SR))
    if i >= len(buf): return
    if i < 0: s = s[-i:]; i = 0
    j = min(len(buf), i + len(s)); buf[i:j] += s[: j - i] * g
def note(m): return 440 * 2 ** ((m - 69) / 12)
def env_adsr(n, a, d, s, r, total):
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), np.where(t < a + d, 1 - (1 - s) * (t - a) / max(d, 1e-4), s))
    return e * np.clip((total - t) / max(r, 1e-4), 0, 1)

# ── 효과음 레시피 (15초 광고 SoundKit 이식 + 신규) ──
def impact_wood(power=1.0):
    t = T(0.12); n = band(rng.standard_normal(len(t)), 1400, 2800)
    s = np.sin(2 * np.pi * (170 - 300 * t) * t) * np.exp(-t / 0.03) * 0.8 + n / (np.abs(n).max() + 1e-9) * np.exp(-t / 0.008) * 0.9
    return s * (0.4 + 0.45 * power)
def whoosh(d=0.26, lo=350, hi=1100):
    t = T(d); n = band(rng.standard_normal(len(t)), lo, hi); n /= np.abs(n).max() + 1e-9
    return n * np.sin(np.pi * t / d) ** 2 * 0.45
def thud(f0=110, f1=45, d=0.28, noise=0.5):
    t = T(d); n = band(rng.standard_normal(len(t)), 60, 500); n /= np.abs(n).max() + 1e-9
    return np.sin(2 * np.pi * (f0 * t + (f1 - f0) * t * t / (2 * d))) * np.exp(-t / (d / 3.5)) + n * np.exp(-t / 0.03) * noise
def sand(d=0.22):   # 벙커 '푹': 저역 잡음, 부드러운 어택
    t = T(d); n = band(rng.standard_normal(len(t)), 180, 900); n /= np.abs(n).max() + 1e-9
    return n * np.minimum(1, t / 0.006) * np.exp(-t / 0.05) * 0.9 + np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.04) * 0.4
def click(g=1.0):   # 오도미터 틱·타건 바탕
    t = T(0.012); n = band(rng.standard_normal(len(t)), 2800, 6000); n /= np.abs(n).max() + 1e-9
    return (n * np.exp(-t / 0.0025) + np.sin(2 * np.pi * 1300 * t) * np.exp(-t / 0.003) * 0.3) * 0.35 * g
def key(v):
    t = T(0.05); n = band(rng.standard_normal(len(t)), [2300, 2600, 2850, 3100, 3400][v % 5] * 0.8, [2300, 2600, 2850, 3100, 3400][v % 5] * 1.25)
    n /= np.abs(n).max() + 1e-9
    return (n * np.exp(-t / 0.006) * 0.9 + np.sin(2 * np.pi * (420 + 40 * (v % 7)) * t) * np.exp(-t / 0.008) * 0.3) * 0.42
def bell(f, d=0.6, g=1.0):
    t = T(d); s = sum(a * np.sin(2 * np.pi * f * k * t) * np.exp(-t / (d * dec)) for k, a, dec in ((1, 1, 0.5), (2.76, 0.45, 0.22), (5.4, 0.2, 0.1)))
    return s * np.minimum(1, t / 0.002) * 0.3 * g
def chime():
    t = T(1.2); s = np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.35)
    t2 = np.clip(t - 0.14, 0, None); s += (t >= 0.14) * np.sin(2 * np.pi * 880 * t2) * np.exp(-t2 / 0.4)
    return s * 0.22
def sparkle():
    out = np.zeros(int(0.45 * SR))
    for i, f in enumerate((2093, 2637, 3136, 4186)):
        t = T(0.3); put(out, np.sin(2 * np.pi * f * t) * np.exp(-t / 0.07) * 0.22, 0.028 * i)
    n = band(rng.standard_normal(len(out)), 5000, 11000); n /= np.abs(n).max() + 1e-9
    return out + n * np.exp(-np.arange(len(out)) / SR / 0.08) * 0.05
def crowd_aww(d=1.9):   # 갤러리 "아…": 포먼트(아: 750·1200·2500Hz) 합창이 아래로 미끄러진다 + 숨 잡음
    n_s = int(d * SR); t = np.arange(n_s) / SR; out = np.zeros(n_s)
    form = lambda f: np.exp(-((f - 750) / 260) ** 2) + 0.7 * np.exp(-((f - 1200) / 300) ** 2) + 0.25 * np.exp(-((f - 2500) / 400) ** 2) + 0.04
    for v in range(28):
        f0 = 150 + 110 * rng.random(); st = 0.12 * rng.random(); glide = 0.68 + 0.08 * rng.random()
        tt = np.clip(t - st, 0, None); f_t = f0 * (1 - (1 - glide) * np.clip(tt / 1.3, 0, 1)) * (1 + 0.012 * np.sin(2 * np.pi * (4.5 + rng.random()) * tt))
        ph = 2 * np.pi * np.cumsum(f_t) / SR
        e = np.clip(tt / 0.22, 0, 1) * np.clip((d - tt) / 0.9, 0, 1) * (t >= st)
        voice = sum(form(k * f0 * 0.85) / k ** 0.6 * np.sin(k * ph) for k in range(1, 16))
        out += voice * e * (0.6 + 0.4 * rng.random())
    out /= np.abs(out).max() + 1e-9
    br = band(rng.standard_normal(n_s), 500, 2200); br /= np.abs(br).max() + 1e-9
    return (out * 0.85 + br * 0.18) * np.clip(t / 0.22, 0, 1) * np.clip((d - t) / 0.9, 0, 1)

# ── 1) 갤러리 웅성거림 (첫 샘플부터) ──
base = band(rng.standard_normal(N), 250, 1800); base /= np.abs(base).max()
tt = np.arange(N) / SR
lfo = 0.75 + 0.12 * np.sin(2 * np.pi * 0.31 * tt + 0.4) + 0.08 * np.sin(2 * np.pi * 0.83 * tt + 1.9) + 0.05 * np.sin(2 * np.pi * 1.7 * tt + 2.6)
babble = np.zeros(N)
for k in range(int(DUR * 26)):                              # 말소리 알갱이 초당 26개
    d = 0.08 + 0.14 * rng.random(); c = 380 + 1200 * rng.random(); n_g = int(d * SR)
    g = band(rng.standard_normal(n_g), c * 0.8, c * 1.25); g /= np.abs(g).max() + 1e-9
    put(babble, g * np.hanning(n_g) * (0.4 + 0.6 * rng.random()), rng.random() * DUR)
crowd = (base * 0.55 + babble * 0.45) * lfo
swell = 1 + 0.35 * np.clip((tt - fr(Bt["imp"])) / 1.2, 0, 1) * np.clip((fr(Bt["restR"]) - tt) / 0.3, 0, 1)   # 비행 중 조금 부풀고
duck = 1 - 0.55 * np.clip((tt - fr(Bt["restR"]) - 0.1) / 0.25, 0, 1) * np.clip((fr(Bt["restR"]) + 2.0 - tt) / 0.6, 0, 1)  # "아…" 동안 웅성거림은 비켜 준다
crowd *= swell * duck * 0.075

# ── 2) 중계 음악 (120BPM, 다운비트 = 임팩트) ──
BEAT = 0.5; T0 = fr(Bt["imp"]); REST = fr(Bt["restR"]); TAGT = fr(Bt["tag"]); WIPE = fr(Bt["wipe"])
music = np.zeros(N)
def brass(freqs, t0, d, amp, bright=1.0):
    n_s = int(d * SR); t = np.arange(n_s) / SR
    e_amp = np.minimum(1, t / 0.035) * np.clip((d - t) / 0.25, 0, 1) * (0.85 + 0.15 * np.exp(-t / 0.3))
    e_br = 0.35 + 0.65 * np.exp(-t / 0.35) * np.minimum(1, t / 0.06)       # '브와' 밝기
    s = np.zeros(n_s)
    for i, f in enumerate(freqs):
        for det in (-0.004, 0.0035):
            ph = 2 * np.pi * f * (1 + det) * t + i
            for k in range(1, 14):
                if f * k > 6000: break
                s += np.sin(k * ph) / k * np.exp(-k / (1.5 + 9 * e_br * bright))
    put(music, s * e_amp * amp / len(freqs), t0)
def bass(f, t0, d, amp):
    t = T(d); put(music, (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 0.22) * np.minimum(1, t / 0.004) * amp, t0)
def kick(t0, amp):
    t = T(0.18); put(music, np.sin(2 * np.pi * (120 * t - 70 * t * t / 0.36)) * np.exp(-t / 0.06) * amp, t0)
def hat(t0, amp):
    n_s = int(0.04 * SR); n = band(rng.standard_normal(n_s), 6500, 12000); n /= np.abs(n).max() + 1e-9
    put(music, n * np.exp(-np.arange(n_s) / SR / 0.012) * amp, t0)
def clap(t0, amp):
    n_s = int(0.14 * SR); n = band(rng.standard_normal(n_s), 1100, 3200); n /= np.abs(n).max() + 1e-9
    put(music, n * np.exp(-np.arange(n_s) / SR / 0.035) * amp, t0)
D = [note(m) for m in (50, 57, 62, 66)]; G = [note(m) for m in (55, 59, 62, 67)]; A = [note(m) for m in (57, 61, 64, 69)]
Am = [note(m) for m in (57, 60, 64)]; Dend = [note(m) for m in (50, 57, 62, 66, 69, 76)]
brass(D, 0.0, T0 + 0.05, 0.24, 0.6); hat(0.0, 0.12); kick(0.0, 0.3)   # 훅: 첫 샘플부터 패드·하이햇(중계 바닥이 첫 프레임부터)
for t0, ch in ((T0, D), (T0 + 2.0, G), (T0 + 4.0, A)):        # 임팩트부터 2초 마디마다
    brass(ch, t0, min(2.0, REST - t0 + 0.05), 0.26)
k = 0
while T0 + k * BEAT < REST:
    tb = T0 + k * BEAT
    kick(tb, 0.55 if k % 2 == 0 else 0.35); bass([D, G, A][min(2, int(k // 4))][0] / 2, tb, 0.45, 0.42)
    if k % 2 == 1: clap(tb, 0.16)
    hat(tb + BEAT / 2, 0.10); hat(tb, 0.06)
    k += 1
for kk in range(-1, 1): hat(T0 + kk * BEAT - BEAT / 2, 0.09)  # 카운트인 하이햇(첫 프레임 근처)
brass(Am, REST + 0.02, TAGT - REST + 0.5, 0.17, 0.35)         # 벙커: 드럼 빠지고 단조 패드(김빠짐)
k = 0
while TAGT + k * BEAT < WIPE:                                  # 태그라인: 가볍게 다시
    tb = TAGT + k * BEAT; hat(tb + BEAT / 2, 0.13); hat(tb, 0.07); bass((D if k < 2 else G)[0] / 2, tb, 0.4, 0.44)
    kick(tb, 0.45 if k % 2 == 0 else 0.3)
    if k % 2 == 1: clap(tb, 0.14)
    k += 1
brass(D, TAGT, 1.0, 0.32); brass(G, TAGT + 1.0, WIPE - TAGT - 1.0 + 0.1, 0.34)
brass(A, WIPE, 0.62, 0.34)                                     # 와이프 동안 V
brass(Dend, WIPE + 0.6, DUR - WIPE - 0.6, 0.55, 1.1)           # 엔드: D 장화음 브라스 해결
for kk in range(int((DUR - WIPE - 0.6) / BEAT)): hat(WIPE + 0.6 + kk * BEAT + BEAT / 2, 0.08)
kick(WIPE + 0.6, 0.7); bass(note(38), WIPE + 0.6, 1.6, 0.6)

# ── 3) 사건 소리 ──
fx = np.zeros(N)
imp = fr(Bt["imp"])
put(fx, whoosh(0.26), imp - 8 / FPS, 2.6); put(fx, impact_wood(1.0), imp - 1 / FPS, 3.4)     # 이전(1.4·1.8)보다 +6dB
put(fx, thud(140, 60, 0.12, 0.2), imp - 1 / FPS, 0.5)
# 트레이서 톤: 공의 실제 높이(장면 시간)에 따라 오르내리는 휘슬 — 임팩트 → 착지
t_land = fr(Bt["landR"]); ts = np.arange(int(imp * SR), int(t_land * SR)) / SR
sf = np.interp(ts * FPS, np.arange(len(WARP)), WARP)
y = np.interp(sf, PTS[:, 0], PTS[:, 2]); hgt = (SHOT["tee"][1] - y) / 108.5                     # 1 = 정점(실캡처 정점 높이 108.5pt)
f_t = 380 + 620 * np.clip(hgt, -0.4, 1.2)
ph = 2 * np.pi * np.cumsum(f_t * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * ts))) / SR
tone = (np.sin(ph) + 0.22 * np.sin(3 * ph)) * np.clip((ts - imp) / 0.06, 0, 1) * np.clip((t_land - ts) / 0.12, 0, 1)
put(fx, tone * 0.16, imp)
put(fx, sparkle(), fr(Bt["apexR"]) - 0.02, 1.6)                                                 # 정점 '반짝'
put(fx, thud(110, 42, 0.32, 0.6), t_land, 1.5)                                                   # 착지 '쿵'
put(fx, thud(90, 40, 0.18, 0.4), fr(Bt["hopR"]), 0.6)                                            # 튐 착지
REST_F = round(Bt["restR"])
put(fx, sand(), fr(REST_F - 7), 1.5)                                                             # 벙커 '푹' (모래로 굴러드는 순간)
put(fx, thud(85, 45, 0.2, 0.9), fr(REST_F), 1.5); put(fx, click(3.0), fr(REST_F), 1.0)          # 도장 '쿵' + 종이 탁
put(fx, crowd_aww(), fr(REST_F + 2), 0.55)                                                       # 갤러리 "아…"
CM1 = "이 샷, 코드 창 위를 넘어갑니다."; CM2 = "…벙커입니다."
for i, c in enumerate(CM1):
    if c != " ": put(fx, key(i), fr(Bt["cmt1"] + i * Bt["cmtRate"]), 1.25)
for j in range(9): put(fx, key(j + 2) * 0.7, fr(REST_F + j), 1.0)                                # 백스페이스(2자/프레임)
for i, c in enumerate(CM2): put(fx, key(i + 3), fr(Bt["cmt2"] + i * Bt["cmtRate"]), 1.35)
put(fx, bell(1568), fr(Bt["lbBlink"]), 1.4); put(fx, bell(1568), fr(Bt["lbBlink"] + 6), 1.4)    # 리더보드 '띵' 두 번
# 오도미터 '드르륵': 그림(main.js)과 같은 값 함수로, 표시 숫자가 정수를 넘을 때마다 틱
def bez(x1, y1, x2, y2):
    def f(p):
        if p <= 0: return 0.0
        if p >= 1: return 1.0
        a, b = 0.0, 1.0
        for _ in range(30):
            t = (a + b) / 2; x = 3 * x1 * (1 - t) ** 2 * t + 3 * x2 * (1 - t) * t * t + t ** 3
            a, b = (t, b) if x < p else (a, t)
        return 3 * y1 * (1 - t) ** 2 * t + 3 * y2 * (1 - t) * t * t + t ** 3
    return f
easeOut = bez(0.2, 0.7, 0.3, 1)
seg = lambda f, a, b: min(1.0, max(0.0, (f - a) / (b - a)))
AR = round(Bt["apexR"]); LR = Bt["landR"]; X0 = SHOT["tee"][0]; PXM = SHOT["pxm"]
def carry(f):
    if f >= LR: return SHOT["nums"]["carry"]
    return max(0.0, (np.interp(WARP[f], PTS[:, 0], PTS[:, 1]) - X0) / PXM)
series = [(lambda f: SHOT["nums"]["speed"] * easeOut(seg(f, imp * FPS, imp * FPS + 14)), Bt["imp"], Bt["imp"] + 16, 0.9),
          (lambda f: SHOT["nums"]["apex"] * easeOut(seg(f, AR - 4, AR + 8)), AR - 4, AR + 10, 0.9),
          (carry, AR, int(LR) + 2, 0.55)]
for val, f0, f1, g in series:
    prev = val(f0 - 1)
    for f in range(f0, f1):
        cur = val(f); n = int(np.floor(cur)) - int(np.floor(prev))
        for i in range(max(0, n)): put(fx, click(g), fr(f - 1) + (i + 0.5) / max(1, n) / FPS)
        prev = cur
put(fx, whoosh(0.62, 300, 2400), fr(Bt["wipe"]), 2.4)                                           # 엔드 와이프 우시
put(fx, chime(), fr(Bt["wipe"] + 14), 2.2)                                                       # 차임 (게임 배지 소리)

# ── 4) 믹스 · 끝 페이드 · 라우드니스 ──
buf = crowd * 1.25 + music * 0.42 + fx * 0.8                 # 바닥은 낮게, 사건은 바닥 위로 10dB 안팎 솟게
buf *= np.clip((DUR - tt) / 0.6, 0, 1)                                                           # 끝 0.6초 페이드
def write_wav(path, x):
    st = np.clip(np.stack([x, x], 1), -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st * 32767).astype("<i2").tobytes())
def ebur(path):
    r = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", r)[-1]), float(re.findall(r"Peak:\s+(-?[\d.]+) dBFS", r)[-1])
path = OUT + "/mix-ko.wav"
def limit(x, th=0.5, ceil=0.76):                                 # 소프트니 리미터: −6dBFS 아래는 그대로, 위만 ceil(−2.4dBFS) 아래로 부드럽게
    a = np.abs(x); over = a > th
    y = x.copy(); y[over] = np.sign(x[over]) * (th + (ceil - th) * np.tanh((a[over] - th) / (ceil - th)))
    return y
x = buf / (np.abs(buf).max() + 1e-9) * 0.5
write_wav(path, x); I, TP = ebur(path)
for _ in range(5):                                               # 게인으로 −14에 맞추고 → 리미터 → 다시 잰다(리미터가 깎은 만큼 보정)
    x = limit(x * 10 ** ((-14 - I) / 20)); write_wav(path, x); I, TP = ebur(path)
    if abs(I + 14) < 0.15: break
if TP > -2.0:                                                    # AAC 여유: WAV 트루피크 −2.0 이하
    x = x * 10 ** ((-2.0 - TP) / 20); write_wav(path, x); I, TP = ebur(path)
first = int(np.argmax(np.abs(x) > 10 ** (-50 / 20)))
json.dump({"lufs": I, "truePeak": TP, "firstSoundSec": round(first / SR, 4)}, open(OUT + "/mix-ko.json", "w"))
print(path, "LUFS", I, "TP", TP, "first sound", round(first / SR, 4), "s")
