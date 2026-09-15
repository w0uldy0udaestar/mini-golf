"""정면 패널 프레임에 MediaPipe Pose(레거시 0.10, heavy)를 돌려 33개 랜드마크(픽셀·가시성)를 JSON으로 저장."""
import cv2, json, time
import mediapipe as mp
import os
S = os.environ.get('SWING_WORK', os.path.expanduser('~/swing-work'))  # 영상·키포인트 작업 폴더 (저장소 밖)
segments = {'slow': (27.0, 63.5, 960, 1920), 'normal': (0.0, 12.0, 459, 1460)}  # name: (t0, t1, x0, x1)
cap = cv2.VideoCapture(f'{S}/rory.mp4'); fps = cap.get(cv2.CAP_PROP_FPS)
for name, (t0, t1, x0, x1) in segments.items():
    out = []; f0 = int(t0 * fps); f1 = int(t1 * fps); miss = 0; t_start = time.time()
    cap.set(cv2.CAP_PROP_POS_FRAMES, f0)
    with mp.solutions.pose.Pose(static_image_mode=False, model_complexity=2, smooth_landmarks=True,
                                min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
        for fi in range(f0, f1):
            ok, fr = cap.read()
            if not ok: break
            crop = fr[:, x0:x1]; h, w = crop.shape[:2]
            res = pose.process(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
            if not res.pose_landmarks:
                miss += 1; out.append({'f': fi, 't': fi / fps, 'lm': None}); continue
            pts = [[round(p.x * w, 1), round(p.y * h, 1), round(p.visibility, 2)] for p in res.pose_landmarks.landmark]
            out.append({'f': fi, 't': fi / fps, 'lm': pts})
    json.dump({'fps': fps, 'crop': [x0, x1], 'frames': out}, open(f'{S}/pose_{name}.json', 'w'))
    print(f'{name}: {len(out)} frames, miss {miss}, {time.time()-t_start:.0f}s')
