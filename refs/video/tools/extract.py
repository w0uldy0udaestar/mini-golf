"""extract.py <name> <video> [x0 x1] [step] [t0 t1]  — 포즈 추출 (step 프레임 간격, t0~t1초 창). 출력 pose_<name>.json"""
import cv2, json, sys, time, mediapipe as mp
name, video = sys.argv[1], sys.argv[2]
x0 = int(sys.argv[3]) if len(sys.argv) > 4 else 0; x1 = int(sys.argv[4]) if len(sys.argv) > 4 else None
step = int(sys.argv[5]) if len(sys.argv) > 5 else 1
tw0 = float(sys.argv[6]) if len(sys.argv) > 7 else 0.0; tw1 = float(sys.argv[7]) if len(sys.argv) > 7 else 1e9  # 시간 창 (긴 영상의 일부만)
cap = cv2.VideoCapture(video); fps = cap.get(cv2.CAP_PROP_FPS); n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
out = []; miss = 0; t0 = time.time()
with mp.solutions.pose.Pose(static_image_mode=False, model_complexity=2, smooth_landmarks=True,
                            min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
    fi = 0
    while True:
        ok, fr = cap.read()
        if not ok: break
        if fi % step == 0 and tw0 <= fi / fps <= tw1:
            crop = fr[:, x0:x1] if x1 else fr; h, w = crop.shape[:2]
            res = pose.process(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
            if not res.pose_landmarks: miss += 1; out.append({'f': fi, 't': fi / fps, 'lm': None})
            else: out.append({'f': fi, 't': fi / fps, 'lm': [[round(p.x * w, 1), round(p.y * h, 1), round(p.visibility, 2)] for p in res.pose_landmarks.landmark]})
        fi += 1
json.dump({'fps': fps, 'crop': [x0, x1 or 0], 'step': step, 'video': video, 'frames': out}, open(f'pose_{name}.json', 'w'))
print(f'{name}: {len(out)} samples (step {step}), miss {miss}, {time.time()-t0:.0f}s')
