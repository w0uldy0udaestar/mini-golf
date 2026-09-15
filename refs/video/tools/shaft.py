"""키 프레임에서 클럽 샤프트 각 검출: 손목 중점 주변 직선(HoughLinesP) 중 손목을 지나고 팔·다리 방향이 아닌 가장 긴 선.
각 규약(스틱맨): 0 = 그립에서 아래, + = 타깃 쪽, 단위 도. 결과를 events_<name>.json에 clubA로 추가."""
import json, math, sys, cv2, numpy as np
import os
S = os.environ.get('SWING_WORK', os.path.expanduser('~/swing-work'))  # 영상·키포인트 작업 폴더 (저장소 밖)
name = sys.argv[1]
E = json.load(open(f'{S}/events_{name}.json')); D = json.load(open(f'{S}/pose_{name}.json')); x0, x1 = D['crop']; VIDEO = D.get('video', f'{S}/rory.mp4')
byf = {f['f']: f for f in D['frames']}
cap = cv2.VideoCapture(VIDEO)
order = ['address', 'takeaway', 'top', 'impact', 'follow', 'finish']
tiles = []; out = {}
TS = 1
for k, fi in zip(order, E['frames']):
    f = byf[fi]; lm = f['lm']
    cap.set(cv2.CAP_PROP_POS_FRAMES, fi); ok, img = cap.read(); crop = (img[:, x0:x1] if x1 else img).copy()
    wr = np.array([(lm[15][0] + lm[16][0]) / 2, (lm[15][1] + lm[16][1]) / 2])
    torso = abs((lm[23][1] + lm[24][1]) / 2 - (lm[11][1] + lm[12][1]) / 2)
    # 손목 주변 ROI에서 직선 검출
    R = int(torso * 1.6); xa, ya = max(0, int(wr[0] - R)), max(0, int(wr[1] - R)); xb, yb = min(crop.shape[1], int(wr[0] + R)), min(crop.shape[0], int(wr[1] + R))
    roi = crop[ya:yb, xa:xb]; g = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY); g = cv2.GaussianBlur(g, (3, 3), 0)
    edges = cv2.Canny(g, 60, 160)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 360, threshold=40, minLineLength=int(torso * 0.45), maxLineGap=12)
    # 제외 방향: 두 팔의 팔꿈치→손목, 어깨→팔꿈치, 다리
    arms = []
    for a, b in [(13, 15), (14, 16), (11, 13), (12, 14), (23, 25), (24, 26), (25, 27), (26, 28)]:
        v = np.array([lm[b][0] - lm[a][0], lm[b][1] - lm[a][1]]); arms.append(math.degrees(math.atan2(v[1], v[0])) % 180)
    best = None
    if lines is not None:
        for l in lines[:, 0]:
            p1 = np.array([l[0] + xa, l[1] + ya], float); p2 = np.array([l[2] + xa, l[3] + ya], float)
            d = p2 - p1; L = np.linalg.norm(d)
            if L < 1: continue
            # 손목까지의 거리 (직선 연장 기준)와 세그먼트 끝점까지 거리
            dist_line = abs(np.cross(d / L, wr - p1))
            near_end = min(np.linalg.norm(wr - p1), np.linalg.norm(wr - p2))
            if dist_line > 0.12 * torso or near_end > 0.9 * torso: continue
            ang = math.degrees(math.atan2(d[1], d[0])) % 180
            if any(min(abs(ang - a), 180 - abs(ang - a)) < 14 for a in arms): continue
            if best is None or L > best[0]: best = (L, p1, p2)
    if best:
        L, p1, p2 = best
        # 그립(손목 가까운 끝) → 팁 방향
        if np.linalg.norm(wr - p1) > np.linalg.norm(wr - p2): p1, p2 = p2, p1
        d = p2 - p1; dx, dy_up = d[0] * TS, -d[1]
        clubA = math.degrees(math.atan2(dx, -dy_up))  # 0 = 아래, + = 타깃(+x) 쪽
        out[k] = round(clubA, 1)
        cv2.line(crop, tuple(p1.astype(int)), tuple(p2.astype(int)), (0, 200, 255), 4)
    else:
        out[k] = None
    cv2.circle(crop, tuple(wr.astype(int)), 6, (255, 0, 0), -1)
    cv2.rectangle(crop, (xa, ya), (xb, yb), (80, 80, 80), 1)
    cv2.putText(crop, f'{k} clubA={out[k]}', (12, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 3)
    tiles.append(cv2.resize(crop, (int(crop.shape[1] * 540 / crop.shape[0]), 540)))
cv2.imwrite(f'{S}/shaft_{name}.png', np.concatenate(tiles, axis=1))
E['clubA'] = out; json.dump(E, open(f'{S}/events_{name}.json', 'w'))
print(name, 'clubA:', out)
