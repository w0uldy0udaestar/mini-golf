#!/usr/bin/env python3
"""광과민성 플래시 검사 (WCAG 2.3.1 Three Flashes or Below Threshold) — 영역 기반.

정의(WCAG 2.x "general flash and red flash thresholds" 요약)
  · 전환(transition): 상대휘도가 최대값의 10% 이상 오르거나 내리는 변화, 단 어두운 쪽 휘도 < 0.80
  · 플래시(flash): 반대 방향 전환 한 쌍
  · 면적: 동시에 일어난 플래시가 시야 10° 안에서 25% 이상을 차지할 때만 센다
  · 기준: 어떤 1초 안에서도 플래시 3회 이하 (일반·적색 각각)
  · 적색 플래시: 포화 적색(R/(R+G+B) ≥ 0.8)이 관여하는 반대 전환 쌍, (R-G-B)×320 의 변화 > 20

v1(프레임 평균 휘도 기반)과 다른 점
  · 화소마다 휘도를 지그재그(히스테리시스 0.10)로 추적해 느린 페이드 안의 누적 변화도 잡는다
  · 화면 전체가 아니라 '시야 10° 창'마다 센다 → 옐로↔브라운 컬러 블록 반전처럼 화면 평균은 그대로인데
    영역은 번쩍이는 경우를 잡는다. 한 창 안에서 올라가는 영역과 내려가는 영역이 동시에 25%를 넘으면(블록 경계)
    더 큰 쪽 하나만 센다(경계 창의 이중 계산 방지)

시야 10° 창 크기 (--field, 프레임 폭 대비)
  · 기본 0.85 = 쇼츠·릴스 시청 조건. 폰(화면 폭 ≈6.5cm, 30~35cm 거리)에서 10° ≈ 5.2~6.1cm ≈ 영상 폭의 80~95%,
    데스크톱 쇼츠 플레이어(폭 ≈405px, 60cm)에서도 ≈94%. 판정은 이 값으로 한다.
  · 참고 0.33 = WCAG 문서의 예시 가정(1024×768 전체 화면 웹 콘텐츠, 10° = 341×256px). 세로 영상이 화면 일부만
    차지하는 실제 시청에는 과하게 엄격하다 → '엄격 기준(참고)'으로 함께 출력만 한다(초과 시 경고).

  python3 ads/_shared/qa/flash-check.py <mp4> [--field 0.85] [--strict-field 0.33] [--scale 4] [--json out.json]
종료 코드: 0 통과 / 1 초과 (기본 창 기준)
"""
import argparse
import json
import subprocess
import sys

import numpy as np

TH_LUM = 0.10       # 전환 임계 (상대휘도)
DARK_MAX = 0.80     # 어두운 쪽이 이 값 미만이어야 센다
AREA = 0.25         # 창 면적 대비
LIMIT = 3           # 1초당 허용 플래시
TH_RED = 20.0       # (R-G-B)*320 변화 임계
RED_SAT = 0.80


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height,r_frame_rate", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip().split(",")
    w, h = int(out[0]), int(out[1])
    n, d = out[2].split("/")
    return w, h, float(n) / float(d)


def frames(path, w, h):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={w}:{h}:flags=area",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)


def linear(rgb8):
    a = rgb8.astype(np.float32) / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


class Zigzag:
    """화소별 전환 검출(히스테리시스). step(v) 는 이번 프레임에 새로 확정된 전환의 부호(+1/-1/0) 배열."""

    def __init__(self, v0, th, dark_max=None):
        self.ref = v0.copy()          # 직전 극값
        self.ext = v0.copy()          # 현재 방향의 진행 극값
        self.dir = np.zeros(v0.shape, np.int8)
        self.th, self.dark = th, dark_max

    def step(self, v):
        ev = np.zeros(v.shape, np.int8)
        d0, up, dn = self.dir == 0, self.dir == 1, self.dir == -1
        # 방향 미정: 기준 대비 th 이상 움직이면 시작
        s_up = d0 & (v - self.ref >= self.th)
        s_dn = d0 & (self.ref - v >= self.th)
        # 상승 중: 최대 갱신, 최대 대비 th 이상 떨어지면 하강 전환 확정
        self.ext = np.where(up, np.maximum(self.ext, v), self.ext)
        self.ext = np.where(dn, np.minimum(self.ext, v), self.ext)
        r_dn = up & (self.ext - v >= self.th)
        r_up = dn & (v - self.ext >= self.th)
        new_up = s_up | r_up
        new_dn = s_dn | r_dn
        base = np.where(r_up | r_dn, self.ext, self.ref)       # 전환의 출발 극값
        if self.dark is not None:
            ok = np.minimum(base, v) < self.dark
            new_up &= ok
            new_dn &= ok
        ev[new_up] = 1
        ev[new_dn] = -1
        # 상태 갱신
        turn = s_up | s_dn | r_up | r_dn
        self.ref = np.where(r_up | r_dn, self.ext, self.ref)
        self.dir = np.where(s_up | r_up, 1, np.where(s_dn | r_dn, -1, self.dir)).astype(np.int8)
        self.ext = np.where(turn, v, self.ext)
        return ev


def windows(h, w, size, stride):
    ys = list(range(0, max(1, h - size + 1), stride)) or [0]
    xs = list(range(0, max(1, w - size + 1), stride)) or [0]
    if ys[-1] != h - size and h > size:
        ys.append(h - size)
    if xs[-1] != w - size and w > size:
        xs.append(w - size)
    return [(y, x) for y in ys for x in xs]


def count(events_frames, win, size, fps):
    """창별로 (프레임, 부호) 이벤트 → 반대 부호 쌍 = 플래시. 1초 창 최대값."""
    best = (0, None, None, [])
    for (y, x) in win:
        seq = []
        for f, ev in events_frames:
            sub = ev[y:y + size, x:x + size]
            n = sub.size
            fu, fd = (sub > 0).sum() / n, (sub < 0).sum() / n
            if fu >= AREA or fd >= AREA:
                seq.append((f, 1 if fu >= fd else -1))
        flashes, pend = [], None
        for f, sgn in seq:
            if pend is not None and sgn == -pend:
                flashes.append(f)
                pend = None
            else:
                pend = sgn
        if not flashes:
            continue
        fl = np.array(flashes)
        for f0 in fl:
            k = int(((fl >= f0) & (fl < f0 + fps)).sum())
            if k > best[0]:
                best = (k, (y, x), int(f0), flashes)
    return best


BLOCKS_PER_FIELD = 8    # 시야 창 한 변을 8블록으로 — 블록 안은 선형 휘도 평균. 25% 면적 플래시는 3×3 블록 이상을 덮어 놓치지 않고,
                        # 가는 줄무늬·그레인처럼 블록보다 작은 패턴이 격자와 엇갈려 생기는 가짜 전환은 평균으로 사라진다


def analyze(lin_frames, field_frac, fps):
    """선형 RGB 프레임들 → (일반, 적색) 결과. 필름 그레인·미세 질감처럼 블록보다 작은 변화는 평균으로 사라진다."""
    import cv2
    h, w = lin_frames[0].shape[:2]
    field = max(8.0, w * field_frac)
    blk = max(1.0, field / BLOCKS_PER_FIELD)
    gw, gh = max(4, int(round(w / blk))), max(4, int(round(h / blk)))
    size = BLOCKS_PER_FIELD if field < w else gw
    win = windows(gh, gw, min(size, gh, gw), max(2, size // 2))
    size = min(size, gh, gw)
    zl = zr = None
    lum_ev, red_ev = [], []
    wts = np.array([0.2126, 0.7152, 0.0722], np.float32)
    for i, lin in enumerate(lin_frames):
        g = cv2.resize(lin, (gw, gh), interpolation=cv2.INTER_AREA)
        L = g @ wts
        s = g.sum(axis=2) + 1e-6
        red = np.where(g[..., 0] / s >= RED_SAT, np.maximum(0.0, (g[..., 0] - g[..., 1] - g[..., 2]) * 320), 0.0)
        if zl is None:
            zl, zr = Zigzag(L, TH_LUM, DARK_MAX), Zigzag(red, TH_RED)
            continue
        e1, e2 = zl.step(L), zr.step(red)
        if np.abs(e1).sum():
            lum_ev.append((i, e1))
        if np.abs(e2).sum():
            red_ev.append((i, e2))
    F1 = int(round(fps))
    gl = count(lum_ev, win, size, F1)
    gr = count(red_ev, win, size, F1)
    to_px = w / gw
    return gl, gr, {"field_px": field, "grid": [gw, gh], "block_px": to_px, "windows": len(win), "win_size": size}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mp4")
    ap.add_argument("--field", type=float, default=0.85, help="시야 10° 창 크기(프레임 폭 대비) — 판정 기준")
    ap.add_argument("--strict-field", type=float, default=0.33, help="참고용 엄격 창(WCAG 1024×768 가정)")
    ap.add_argument("--scale", type=int, default=4, help="분석 축소 배율")
    ap.add_argument("--json")
    a = ap.parse_args()
    W, H, fps = probe(a.mp4)
    w, h = W // a.scale, H // a.scale
    F = frames(a.mp4, w, h)
    LIN = [linear(f) for f in F]
    F1 = int(round(fps))
    gl, gr, m1 = analyze(LIN, a.field, fps)
    sl, sr, m2 = analyze(LIN, a.strict_field, fps)
    ok = gl[0] <= LIMIT and gr[0] <= LIMIT
    k1, k2 = m1["block_px"] * a.scale, m2["block_px"] * a.scale
    xy = lambda g, k: [round(g[1][1] * k), round(g[1][0] * k)] if g[1] else None
    pack = lambda g, k: {"max_per_second": g[0], "window_xy": xy(g, k), "at_frame": g[2], "flash_frames": g[3][:40]}
    res = {"file": a.mp4, "frames": len(F), "fps": fps, "field_px": round(m1["field_px"] * a.scale),
           "block_px": round(k1, 1), "windows": m1["windows"],
           "general": pack(gl, k1), "red": pack(gr, k1),
           "strict": {"field_px": round(m2["field_px"] * a.scale), "block_px": round(k2, 1),
                      "general": pack(sl, k2), "red": pack(sr, k2), "exceeds": sl[0] > LIMIT or sr[0] > LIMIT},
           "limit": LIMIT, "pass": ok}
    print(f"광과민성 검사 — {a.mp4}")
    print(f"  프레임 {len(F)} · {fps:g}fps · 시야 10° 창 {res['field_px']}px (쇼츠·릴스 시청 기준, {m1['windows']}개, "
          f"블록 {k1:.0f}px 평균, 면적 {int(AREA * 100)}%)")
    for name, g in (("일반 플래시", gl), ("적색 플래시", gr)):
        where = f" 창 x{xy(g, k1)[0]},y{xy(g, k1)[1]} · f{g[2]}~f{g[2] + F1 - 1}" if g[1] else ""
        print(f"  {name}: 1초 창 최대 {g[0]}회 / 허용 {LIMIT}회{where}")
        if g[3]:
            print(f"      해당 창 플래시 프레임: {g[3][:20]}")
    warn = sl[0] > LIMIT or sr[0] > LIMIT
    print(f"  엄격 기준(참고, 창 {res['strict']['field_px']}px = WCAG 1024×768 가정): 일반 {sl[0]}회 · 적색 {sr[0]}회"
          + (f"  ⚠ 초과 — 창 x{xy(sl, k2)[0]},y{xy(sl, k2)[1]} f{sl[2]}~ 을 눈으로 확인 (큰 물체의 빠른 명암 교차 등)" if warn and sl[1] else ""))
    print("  판정: " + ("통과 ✓" if ok else "초과 ✗"))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
