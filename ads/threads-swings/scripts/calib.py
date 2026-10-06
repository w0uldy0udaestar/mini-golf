"""리그 ↔ 실캡처 정합 확인: 캡처 스틸마다 가장 잘 겹치는 리그 표본을 찾아(밝은 화소 IoU 최대) 빨간 가는 선으로 겹쳐 본다.

  python3 scripts/calib.py OUTDIR          → OUTDIR/cal-<name>-<still>.png + 표 출력 (교정 전용, 광고에는 안 들어간다)
게임 StickmanNode 렌더 규칙(선 굵기 6·트레일 팔 5.5·샤프트 3·머리 r10)을 그대로 따른다 — src/main.js drawMan과 같은 식.
"""
import glob, math, os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from riglog import CAP, load

S = 2  # 캡처 배율 (pt → px)


def joints(r, gx, gy, d=None):
    d = r["dir"] if d is None else d
    T = lambda p: (gx + p[0] * d, gy - p[1])
    hip, sh, f1, f2, k1, k2, grip, ht, el, et = [T(p) for p in r["pts"]]
    sp, cp = math.sin(r["phi"]), math.cos(r["phi"])
    tip = (grip[0] + sp * r["len"] * d, grip[1] + cp * r["len"])
    butt = (grip[0] - sp * r["butt"] * d, grip[1] - cp * r["butt"])
    hd = (sh[0] + d * r["head"][0], sh[1] - r["head"][1])
    return dict(hip=hip, sh=sh, f1=f1, f2=f2, k1=k1, k2=k2, grip=grip, ht=ht, el=el, et=et, tip=tip, butt=butt, hd=hd)


def draw_mask(J, size, ox, oy, scale=S, widths=True):
    im = Image.new("L", size, 0); d = ImageDraw.Draw(im)
    P = lambda p: ((p[0] - ox) * scale, (p[1] - oy) * scale)
    w = lambda x: max(1, int(round(x * scale))) if widths else 2
    for seg in [(J["sh"], J["hip"]), (J["hip"], J["k1"], J["f1"]), (J["hip"], J["k2"], J["f2"]), (J["sh"], J["el"], J["grip"])]:
        d.line([P(p) for p in seg], fill=255, width=w(6), joint="curve")
    d.line([P(J["sh"]), P(J["et"]), P(J["ht"])], fill=150, width=w(5.5), joint="curve")
    d.line([P(J["butt"]), P(J["tip"])], fill=255, width=w(3))
    hx, hy = P(J["hd"]); r = 10 * scale
    d.ellipse((hx - r, hy - r, hx + r, hy + r), fill=255)
    return im


def main(out):
    os.makedirs(out, exist_ok=True)
    for name in ["jump", "twirl", "lock"]:
        rows, sticks, ev = load(name)
        st = sticks[0]; gx, gy = st["x"], st["h"] - st["gy"]
        off = sorted(r["recv"] - r["st"] for r in rows)[len(rows) // 20]
        for f in sorted(glob.glob(f"{CAP}/{name}/*.raw.png")):
            cap = Image.open(f).convert("RGB")
            ox, oy = gx - 150, gy - 170; W, H = 300, 190
            crop = cap.crop((ox * S, oy * S, (ox + W) * S, (oy + H) * S))
            a = np.asarray(crop.convert("L")).astype(np.float32)
            m = a > 120
            m[int((gy - oy - 2) * S):] = False  # 지면선 제외
            best = None
            for r in rows:
                if r["mode"] in ("ritual", "walking"): continue
                J = joints(r, gx, gy)
                mk = np.asarray(draw_mask(J, (W * S, H * S), ox, oy)) > 0
                mk[int((gy - oy - 2) * S):] = False
                inter = (m & mk).sum(); uni = (m | mk).sum()
                iou = inter / max(1, uni)
                if best is None or iou > best[0]: best = (iou, r)
            iou, r = best
            J = joints(r, gx, gy)
            ov = crop.copy(); d = ImageDraw.Draw(ov)
            P = lambda p: ((p[0] - ox) * S, (p[1] - oy) * S)
            for seg in [(J["sh"], J["hip"]), (J["hip"], J["k1"], J["f1"]), (J["hip"], J["k2"], J["f2"]), (J["sh"], J["el"], J["grip"]), (J["sh"], J["et"], J["ht"])]:
                d.line([P(p) for p in seg], fill=(255, 40, 40), width=2)
            d.line([P(J["butt"]), P(J["tip"])], fill=(40, 200, 255), width=2)
            hx, hy = P(J["hd"]); d.ellipse((hx - 20, hy - 20, hx + 20, hy + 20), outline=(255, 40, 40), width=2)
            base = os.path.basename(f).split(".")[0]
            ov.save(f"{out}/cal-{name}-{base}.png")
            print(f"{name:6s} {base:14s} iou {iou:.3f} mode {r['mode']:9s} st-impact? recv {r['st'] + off:.2f}")


if __name__ == "__main__":
    main(sys.argv[1])
