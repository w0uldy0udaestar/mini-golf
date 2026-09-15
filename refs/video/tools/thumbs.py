"""thumbs.py <video> <out.png> [n] — 영상 각도·구간 확인용 썸네일 시트 (등간격 n프레임, 시각 표기)."""
import sys, cv2, numpy as np
video, out = sys.argv[1], sys.argv[2]; n = int(sys.argv[3]) if len(sys.argv) > 3 else 8
cap = cv2.VideoCapture(video); N = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)); fps = cap.get(cv2.CAP_PROP_FPS)
tiles = []
for k in range(n):
    fi = int((k + 0.5) * N / n); cap.set(cv2.CAP_PROP_POS_FRAMES, fi); ok, img = cap.read()
    if not ok: continue
    cv2.putText(img, f'{fi / fps:.1f}s', (12, 48), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (0, 255, 255), 4)
    tiles.append(cv2.resize(img, (int(img.shape[1] * 360 / img.shape[0]), 360)))
rows = [np.concatenate(tiles[i:i + 4], axis=1) for i in range(0, len(tiles), 4)]
wmax = max(r.shape[1] for r in rows); rows = [np.pad(r, ((0, 0), (0, wmax - r.shape[1]), (0, 0))) for r in rows]
cv2.imwrite(out, np.concatenate(rows, axis=0)); print(out, f'{N} frames {fps:.0f}fps {N / fps:.1f}s')
