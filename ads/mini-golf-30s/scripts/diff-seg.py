#!/usr/bin/env python3
"""카메라 이동 구간별 프레임 차분 최대값: diff-seg.py <mp4...> (qa.py와 같은 방법: 240×135/135×240 INTER_AREA, BGR 평균 절대차)
+ 끝 정지 길이(마지막 프레임과 화소 단위로 같은 연속 프레임 수, 변화 임계 16/255)."""
import sys, cv2, numpy as np
SEGS = {"풀백 f34–58": (34, 58), "팬 f72–100": (72, 100), "푸시인 f136–179": (136, 179), "M1 추적 f196–210": (196, 210), "엔드 풀백 f782–806": (782, 806)}
for p in sys.argv[1:]:
    cap = cv2.VideoCapture(p); fr = []
    while True:
        ok, im = cap.read()
        if not ok: break
        fr.append(im)
    portrait = fr[0].shape[0] > fr[0].shape[1]; size = (135, 240) if portrait else (240, 135)
    sm = [cv2.resize(f, size, interpolation=cv2.INTER_AREA).astype(np.float32) for f in fr]
    d = [0.0] + [float(np.abs(sm[i] - sm[i - 1]).mean()) for i in range(1, len(sm))]
    out = {k: (round(max(d[a:b + 1]), 2), int(a + int(np.argmax(d[a:b + 1]))), sum(1 for x in d[a:b + 1] if x > 12)) for k, (a, b) in SEGS.items()}
    last = fr[-1].astype(np.int16); hold = 0
    for i in range(len(fr) - 1, -1, -1):
        if (np.abs(fr[i].astype(np.int16) - last).max(axis=2) > 16).sum() == 0: hold += 1
        else: break
    print(p.split("/")[-1], {k: f"max {v[0]} @f{v[1]} · >12 {v[2]}f" for k, v in out.items()}, f"| 끝 정지 {hold}f = {hold / 30:.2f}s (f{len(fr) - hold}–{len(fr) - 1})")
