#!/usr/bin/env python3
"""T1 「거위가 공 위에 앉았다」 — 영상층(게임 캡처 몽타주 + 카메라)을 프레임 단위로 굽는다.

  python3 scripts/bake.py [--check]      → assets/gen/footage.mp4 (1080×1920, 30fps, 390프레임) + data/cuts.js
  --check : 컷마다 시작·중간·끝 3프레임만 dist/ads/threads/t1-work/check.png 로 (구도 확인용)

원칙
- 원본: dist/cap/t1-surprises/<종류>/*.raw.png — scripts/capture-window.py로 찍은 게임 창 단위 캡처(--demo --demo-bg, --screen 0).
  캡처 시각 = 파일 mtime(첫 장 기준 초) — data/capture-times.json에 고정해 두고 그것을 읽는다. 출력 프레임마다 '그 시각 이하의 마지막 캡처'를 고른다(보간·합성 프레임 없음).
- 모든 값은 프레임 번호의 순수 함수. 난수·시계 없음. 같은 입력이면 같은 출력.
- 카메라: 2D scale/translate만. 컷마다 공(또는 깃발 밑동)을 같은 화면 점에 두는 매치 컷 + 컷 안의 느린 푸시(+4~5%).
- 마지막 컷(갤러리)은 끊지 않고 데스크탑 전체로 풀백한다(고정점 줌, 로그 배율 보간). 데스크탑 창은 일반형 회색 사각형이며
  게임 그림과 'lighten'으로 겹친다(게임은 창 위에 그려지는 투명 오버레이라서).
- 커서: 창 캡처에는 마우스 커서가 찍히지 않는다(설계상). cursorCat 컷에서만 추적한 고양이 앞에 일반형 화살표 커서를 그린다(코드 근사).
"""
import glob, json, math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.abspath(os.path.dirname(os.path.abspath(__file__)) + "/..")
ROOT = os.path.abspath(HERE + "/../..")
CAP = ROOT + "/dist/cap/t1-surprises"
GEN = HERE + "/assets/gen"
W, H, FPS, NF = 1080, 1920, 30, 390
GRAY = (40, 40, 39)          # 게임 --demo-bg 배경 (NSColor white 0.16) 실측값
OUTER = (19, 19, 20)         # 풀백 뒤 '화면 밖'
CHECK = "--check" in sys.argv

# ── 캡처 색인 ──
IDX = {}
MAN = json.load(open(HERE + "/data/capture-times.json"))   # 캡처 시각 고정본(파일 mtime → 첫 장 기준 초). 폴더를 옮겨도 타이밍이 안 변한다
def index(name):
    if name not in IDX:
        if name in MAN:
            IDX[name] = ([t for t, _ in MAN[name]], [f"{CAP}/{name}/{b}" for _, b in MAN[name]])
        else:
            fs = sorted(glob.glob(f"{CAP}/{name}/*.raw.png"), key=os.path.getmtime)
            t0 = os.path.getmtime(fs[0])
            IDX[name] = ([os.path.getmtime(f) - t0 for f in fs], fs)
    return IDX[name]

def pick(name, ct):
    ts, fs = index(name)
    i = max(0, np.searchsorted(ts, ct, side="right") - 1)
    return fs[i]

_cache = {}
def load(path):
    if path not in _cache:
        if len(_cache) > 10: _cache.pop(next(iter(_cache)))
        _cache[path] = Image.open(path).convert("RGB").crop((0, 0, 3840, 2160))
    return _cache[path]

# ── 컷 (광고 시각 t0~t1, 캡처 시각 c0부터 sp배속, f=화면 앵커 a에 둘 원본 점(2x 픽셀), z=배율 시작→끝) ──
CUTS = [
    # 훅: 0~1.45초 가까이(×4.0→4.1) 붙어 있다가, 거위가 날아오르는 순간(1.5~2.15초) ×3.2로 물러나 알과 비행을 보여 준다(동기 있는 이동 1회)
    dict(id="geese",   src="geese",     t0=0.0,  t1=2.95, c0=5.11, sp=1.0,  f=(2311, 1768), a=(500, 1100), zk=[(0, 4.0), (1.45, 4.1), (2.15, 3.2), (2.95, 3.27)]),
    dict(id="bird",    src="bird",      t0=2.95, t1=4.0,  c0=2.05, sp=1.24, f=(770, 1942),  a=(500, 1330), z=(2.8, 2.9)),
    dict(id="pin",     src="pin",       t0=4.0,  t1=4.95, c0=1.35, sp=1.32, f=(3445, 1794), a=(500, 1270), z=(3.9, 4.05)),
    dict(id="mole",    src="mole",      t0=4.95, t1=5.8,  c0=0.85, sp=1.47, f=(1402, 1953), a=(500, 1180), z=(3.9, 4.05)),
    dict(id="cat",     src="cat",       t0=5.8,  t1=6.55, c0=2.40, sp=1.27, f=None,         a=(500, 1180), z=(2.2, 2.3)),
    dict(id="dog",     src="dog",       t0=6.55, t1=7.2,  c0=1.85, sp=1.54, f=(1160, 1945), a=(500, 1180), z=(2.7, 2.82)),
    dict(id="gallery", src="gallery-b", t0=7.2,  t1=13.0, c0=0.0,  sp=1.0,  f=(1660, 1905), a=(500, 1180), z=(2.25, 2.3)),
]
PULL = (7.85, 9.15)                       # 풀백 구간(초)
SCR = dict(x=60, y=760, w=860)          # 풀백 끝: 화면(3840×2160)을 폭 860px로 → 높이 483.75
Z1 = SCR["w"] / 3840
CAT = json.load(open(HERE + "/data/cat-track.json"))

def ease_io(u):  # 사인 in-out
    return 0.5 - 0.5 * math.cos(math.pi * min(1, max(0, u)))

def smooth(a, b, x):
    u = min(1, max(0, (x - a) / (b - a))); return u * u * (3 - 2 * u)

# ── 데스크탑 창(일반형, 로고·글자 없음) — 원본 좌표 3840×2160 ──
def build_windows():
    im = Image.new("RGB", (3840, 2160), GRAY); d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 3840, 46), fill=(50, 51, 54))                                   # 메뉴바
    for k, x in enumerate([40, 150, 250, 350, 450]): d.rounded_rectangle((x, 15, x + (60 if k else 70), 31), 6, fill=(74, 75, 79))
    for x in (3470, 3560, 3660): d.rounded_rectangle((x, 15, x + 70, 31), 6, fill=(74, 75, 79))
    seed = 7
    def rnd():
        nonlocal seed; seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF; return seed / 0x7FFFFFFF
    def win(x0, y0, x1, y1, rows, indent=True, body=(47, 48, 52)):
        d.rounded_rectangle((x0, y0, x1, y1), 22, fill=body, outline=(60, 61, 66), width=2)
        d.rounded_rectangle((x0, y0, x1, y0 + 66), 22, fill=(55, 56, 60)); d.rectangle((x0, y0 + 40, x1, y0 + 66), fill=(55, 56, 60))
        d.line((x0, y0 + 66, x1, y0 + 66), fill=(62, 63, 68), width=2)
        for k in range(3): d.ellipse((x0 + 26 + k * 38, y0 + 22, x0 + 50 + k * 38, y0 + 46), fill=(78, 79, 84))
        y = y0 + 110
        for r in range(rows):
            if y > y1 - 60: break
            ind = int(rnd() * 4) * 56 if indent else 0
            ln = 260 + int(rnd() * (x1 - x0 - 520))
            if rnd() > 0.12: d.rounded_rectangle((x0 + 70 + ind, y, x0 + 70 + ind + ln, y + 20), 8, fill=(62, 63, 68))
            y += 54
    win(150, 130, 1390, 1880, 40)                  # 왼쪽: 편집기형
    win(2000, 250, 3680, 1880, 40, indent=False)   # 오른쪽: 문서형
    win(1230, 470, 2150, 1290, 14, indent=False, body=(50, 51, 55))  # 가운데 작은 창(갤러리 첫 구도 위쪽 — 확대 컷에는 안 들어온다)
    return np.asarray(im).astype(np.int16)
WIN = None

def with_windows(img, k):
    """게임 프레임(배경 GRAY 불투명)에 창 층을 lighten으로 깐다. k=0..1 창의 진하기."""
    global WIN
    if k <= 0: return img
    if WIN is None: WIN = build_windows()
    g = np.array(GRAY, dtype=np.int16)
    win = g + ((WIN - g) * k).astype(np.int16)
    a = np.asarray(img).astype(np.int16)
    return Image.fromarray(np.maximum(a, win).astype(np.uint8))

# ── 커서 스프라이트 (일반형 화살표: 검정 채움 + 흰 테두리, 4배 그려 줄인다) ──
def cursor_sprite(h_px):
    S = 8; pts = [(2, 2), (2, 25), (7.6, 19.8), (11.4, 28.6), (15, 27), (11.3, 18.4), (18.8, 18.4)]
    big = Image.new("RGBA", (int(22 * S), int(32 * S)), (0, 0, 0, 0)); d = ImageDraw.Draw(big)
    P = [(x * S, y * S) for x, y in pts]
    d.polygon(P, fill=(255, 255, 255, 255))
    # 안쪽 검정: 테두리 두께만큼 줄인 다각형 (중심 쪽으로 수축)
    cx = sum(p[0] for p in P) / len(P); cy = sum(p[1] for p in P) / len(P)
    inner = [(cx + (x - cx) * 0.80, cy + (y - cy) * 0.86) for x, y in P]
    d.polygon(inner, fill=(17, 17, 18, 255))
    return big.resize((int(22 * h_px / 32), int(h_px)), Image.LANCZOS)
CURSOR = cursor_sprite(96)

def place(src, z, f, a, fill):
    """원본 src를 배율 z로, 원본 점 f가 화면 점 a에 오도록 W×H 캔버스에 놓는다 (2D scale/translate)."""
    fx, fy = f
    if z < 0.5:
        k = int(1 / z); src = src.reduce(k); z *= k; fx /= k; fy /= k
    m = (1 / z, 0, fx - a[0] / z, 0, 1 / z, fy - a[1] / z)
    return src.transform((W, H), Image.AFFINE, m, resample=Image.BICUBIC, fillcolor=fill)

def gallery_cam(t, c):
    """갤러리 컷 → 풀백 → 데스크탑 정지. (z, f, a, k) k=창·바깥 어둠의 진하기"""
    z0 = c["z"][0] + (c["z"][1] - c["z"][0]) * smooth(c["t0"], PULL[0], t)
    if t <= PULL[0]: return z0, c["f"], c["a"], 0.0
    zA, fA, aA = c["z"][1], c["f"], c["a"]
    zB, fB, aB = Z1, (0.0, 0.0), (SCR["x"], SCR["y"])
    # 고정점 p: 두 변환에서 같은 화면 점으로 가는 원본 점 → 그 점을 중심으로 순수 확대/축소
    p = [(fA[i] * zA - fB[i] * zB + aB[i] - aA[i]) / (zA - zB) for i in (0, 1)]
    D = [(p[i] - fA[i]) * zA + aA[i] for i in (0, 1)]
    u = ease_io((t - PULL[0]) / (PULL[1] - PULL[0]))
    z = math.exp(math.log(zA) + (math.log(zB) - math.log(zA)) * u)
    k = smooth(0.12, 0.75, (t - PULL[0]) / (PULL[1] - PULL[0]))
    return z, tuple(p), tuple(D), k

def frame(n):
    t = n / FPS
    c = next(c for c in CUTS if c["t0"] <= t < c["t1"] or c is CUTS[-1])
    ct = c["c0"] + (t - c["t0"]) * c["sp"]
    src = load(pick(c["src"], ct))
    if c["id"] == "gallery":
        z, f, a, k = gallery_cam(t, c)
        img = with_windows(src, k) if k > 0 else src
        if k < 1:   # 확대 구간에서만 HUD 미션 문구(잘려 보이는 회색 글줄)를 배경색으로 덮는다 — 풀백하며 원래대로 드러난다
            img = img.copy(); hud = Image.new("RGB", (365, 46), GRAY)
            img.paste(Image.blend(img.crop((1735, 2020, 2100, 2066)), hud, 1 - k), (1735, 2020))
        fill = tuple(int(GRAY[i] + (OUTER[i] - GRAY[i]) * k) for i in range(3))
        out = place(img, z, f, a, fill)
        if k > 0:   # 화면 테두리(얇은 선) — 풀백하며 드러난다
            x0 = a[0] - f[0] * z; y0 = a[1] - f[1] * z; x1 = x0 + 3840 * z; y1 = y0 + 2160 * z
            d = ImageDraw.Draw(out); col = tuple(int(fill[i] + ((66, 67, 72)[i] - fill[i]) * k) for i in range(3))
            d.rectangle((round(x0) - 2, round(y0) - 2, round(x1) + 1, round(y1) + 1), outline=col, width=2)
        return out, dict(cut=c["id"], z=round(z, 4))
    if "zk" in c:   # 배율 키프레임(컷 안 상대 초) 사이를 사인 in-out으로
        tr = t - c["t0"]; ks = c["zk"]; z = ks[-1][1]
        for (ta, za), (tb, zb) in zip(ks, ks[1:]):
            if ta <= tr <= tb: z = za + (zb - za) * ease_io((tr - ta) / (tb - ta)); break
    else:
        u = (t - c["t0"]) / (c["t1"] - c["t0"])
        z = c["z"][0] + (c["z"][1] - c["z"][0]) * ease_io(u)
    if c["id"] == "cat":
        cx = np.polyval(CAT["x"], ct); cy = np.polyval(CAT["y"], ct)
        f = (cx - 60, cy + 40)
        out = place(src, z, f, c["a"], GRAY)
        # 커서: 고양이보다 150px(원본) 앞, 몸 높이 위쪽 — 손으로 움직이는 듯 작은 흔들림(결정적 사인)
        tipx = (cx - 115 - f[0]) * z + c["a"][0] + 14 * math.sin(ct * 7.1)
        tipy = (cy - 60 - f[1]) * z + c["a"][1] + 10 * math.sin(ct * 5.3 + 1.2)
        out.paste(CURSOR, (int(round(tipx - 2 * 96 / 32)), int(round(tipy - 2 * 96 / 32))), CURSOR)
        return out, dict(cut=c["id"], z=round(z, 4))
    return place(src, z, c["f"], c["a"], GRAY), dict(cut=c["id"], z=round(z, 4))

if __name__ == "__main__":
    os.makedirs(GEN + "/frames", exist_ok=True)
    meta = []
    if CHECK:
        want = []
        for c in CUTS[:-1]:
            a, b = int(round(c["t0"] * FPS)), int(round(c["t1"] * FPS)) - 1
            want += [a, (a + b) // 2, b]
        want += [210, 228, 240, 250, 258, 267, 300, 389]
        tw = 270; th = 480; cols = 8
        sheet = Image.new("RGB", (cols * tw, ((len(want) + cols - 1) // cols) * th), "#000")
        for k, n in enumerate(want):
            im, m = frame(n); r, cc = divmod(k, cols)
            sheet.paste(im.resize((tw, th), Image.LANCZOS), (cc * tw, r * th))
            ImageDraw.Draw(sheet).text((cc * tw + 6, r * th + 6), f"f{n} {m['cut']} z{m['z']}", fill="#ff0")
        os.makedirs(ROOT + "/dist/ads/threads/t1-work", exist_ok=True)
        sheet.save(ROOT + "/dist/ads/threads/t1-work/check.png"); print("check", len(want)); sys.exit()
    for n in range(NF):
        im, m = frame(n); im.save(f"{GEN}/frames/f{n:04d}.png", compress_level=1); meta.append(m)
        if n % 60 == 0: print("frame", n, m, flush=True)
    cuts = [dict(id=c["id"], t0=c["t0"], t1=c["t1"]) for c in CUTS]
    with open(HERE + "/data/cuts.js", "w") as fh:
        fh.write("/* bake.py가 쓴다 — 컷 경계(초)와 풀백 구간. 손으로 고치지 말 것 */\nwindow.CUTS = " + json.dumps(cuts) +
                 ";\nwindow.PULL = " + json.dumps(list(PULL)) + ";\nwindow.SCR = " + json.dumps(dict(SCR, h=round(2160 * Z1, 2))) + ";\n")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-i", f"{GEN}/frames/f%04d.png",
                    "-c:v", "libx264", "-preset", "slow", "-crf", "8", "-tune", "animation", "-pix_fmt", "yuv420p",
                    "-g", "1", "-movflags", "+faststart", f"{GEN}/footage.mp4"], check=True)
    print("ok", GEN + "/footage.mp4")
