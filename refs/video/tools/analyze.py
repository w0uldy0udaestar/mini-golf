"""키포인트 → 스윙 이벤트 검출 + 스틱맨 파라미터 변환 + 오버레이 시트.
좌표계: 이미지(y 아래) → 분석은 y 위(up)로 뒤집음. 타깃은 화면 오른쪽(+x) — 오른손잡이 face-on.
"""
import json, math, sys, cv2, numpy as np
import os
S = os.environ.get('SWING_WORK', os.path.expanduser('~/swing-work'))  # 영상·키포인트 작업 폴더 (저장소 밖)
name = sys.argv[1] if len(sys.argv) > 1 else 'slow'
D = json.load(open(f'{S}/pose_{name}.json')); fps = D['fps'] / D.get('step', 1); x0, x1 = D['crop']; VIDEO = D.get('video', f'{S}/rory.mp4')
T0 = float(sys.argv[2]) if len(sys.argv) > 2 else -1; T1 = float(sys.argv[3]) if len(sys.argv) > 3 else 1e9  # 분석 시간 창 (인트로·장면 전환 배제)
fr = [f for f in D['frames'] if f['lm'] and T0 <= f['t'] <= T1]
def P(f, i): return np.array([f['lm'][i][0], -f['lm'][i][1]])  # y up
def mid(f, a, b): return (P(f, a) + P(f, b)) / 2
T = np.array([f['t'] for f in fr])
S_ = np.array([mid(f, 11, 12) for f in fr]); H_ = np.array([mid(f, 23, 24) for f in fr]); W_ = np.array([mid(f, 15, 16) for f in fr])
N_ = np.array([P(f, 0) for f in fr])
# 스무딩 (5프레임 이동평균)
def sm(a, k=5):
    ker = np.ones(k) / k; return np.stack([np.convolve(a[:, i], ker, mode='same') for i in range(a.shape[1])], axis=1)
S_, H_, W_, N_ = sm(S_), sm(H_), sm(W_), sm(N_)
torso = np.linalg.norm(S_ - H_, axis=1); torso0 = np.median(torso)
# 손 높이(어깨 기준)로 스윙 구간 찾기: 손이 어깨 위로 올라갔다 내려오는 봉우리
handY = (W_ - S_)[:, 1]
speed = np.linalg.norm(np.gradient(W_, axis=0), axis=1) * fps  # px/s
# 이벤트: address = 스윙 시작 전 정지(손 낮고 속도 작음), top = 손 최고점(타깃 반대편), impact = 손이 address 높이로 복귀 & 속도 최대 부근, finish = 그 뒤 손 최고점
def find_swings():
    """손 높이(어깨 기준)의 국소 최대(봉우리)를 찾아 (i0, i1) 구간으로 돌려준다 — 봉우리 주변 ±0.35s.
    임계: 어깨보다 0.25·torso 이상 높고, 이웃 봉우리와 0.6s 이상 떨어짐 (구 0.6·torso 절대 임계는 작은 골퍼에서 톱을 놓쳤다)"""
    w = max(2, int(0.35 * fps)); gap = int(0.6 * fps)
    peaks = []
    for i in range(w, len(handY) - w):
        if handY[i] < 0.25 * torso0: continue
        if handY[i] >= handY[i - w:i + w + 1].max():
            if peaks and i - peaks[-1] < gap:
                if handY[i] > handY[peaks[-1]]: peaks[-1] = i
                continue
            peaks.append(i)
    return [(max(0, p - w), min(len(handY), p + w + 1)) for p in peaks]
segs = find_swings()
print(f'[{name}] frames {len(fr)}  fps {fps}  torso {torso0:.0f}px  high-hand segments: {[(round(T[a],1), round(T[b-1],1)) for a,b in segs]}')
# 스윙 = (톱 봉우리, 피니시 봉우리) 짝. face-on에서 톱·피니시 손은 둘 다 머리 뒤(타깃 반대쪽)에 있고,
# 그 사이 팔로스루에서 손이 타깃 쪽으로 크게 뻗는다 — 타깃 방향은 그 뻗음의 부호로 판정한다.
swings = []
last_finish = 0  # 어드레스 탐색 창은 직전 '스윙'의 피니시 이후 (봉우리가 아니라) — 톱 근처 이중 봉우리에 창이 잘리지 않게
for k in range(len(segs) - 1):
    a0, a1 = segs[k]; b0, b1 = segs[k + 1]
    if T[b0] - T[a1] < 0.05: continue
    topi = a0 + int(np.argmax(handY[a0:a1])); fini = b0 + int(np.argmax(handY[b0:b1]))
    relx = (W_ - S_)[:, 0]
    mid_lo, mid_hi = a1, b0
    ext = relx[mid_lo:mid_hi]
    if len(ext) < 3: continue
    fol = mid_lo + int(np.argmax(np.abs(ext)))
    tsign = 1 if relx[fol] > 0 else -1
    if abs(relx[fol]) < 0.6 * torso0: continue
    if relx[topi] * tsign > 0: continue  # 톱의 손은 타깃 반대쪽
    if topi <= last_finish: continue  # 직전 스윙의 피니시 봉우리를 톱으로 재사용하지 않는다
    win0 = last_finish
    minY = handY[win0:topi].min()
    low = [i for i in range(win0, topi) if handY[i] <= minY + 0.03 * torso0]
    addr = low[-1] if low else win0
    addrY = handY[addr]
    imp = topi + int(np.argmin(handY[topi:fol + 1]))
    tk = [i for i in range(addr, topi) if handY[i] > addrY + 0.33 * (handY[topi] - addrY)]
    swings.append({'address': addr, 'takeaway': tk[0] if tk else addr, 'top': topi, 'impact': imp, 'follow': fol, 'finish': fini, 'tsign': tsign})
    last_finish = fini
if not swings:
    sys.exit('no swing found')
print('swings found:', len(swings), [(round(T[s["address"]],1), round(T[s["finish"]],1)) for s in swings])
for sw in swings: sw['span'] = T[sw['finish']] - T[sw['address']]
for sw in swings: print('  cand', {k: round(T[sw[k]],2) for k in ['address','takeaway','top','impact','follow','finish']})
def sane(sw):
    # 카메라·골퍼 이동 구간 배제: 어드레스→피니시 힙 이동 ≤ 25(스틱맨 px), 톱·임팩트 척추각 ≤ 40°
    drift = abs(H_[sw['finish']][0] - H_[sw['address']][0]) / torso0 * 25
    def tilt(i):
        v = S_[i] - H_[i]; return abs(math.degrees(math.atan2(v[0], v[1])))
    return drift <= 25 and tilt(sw['top']) <= 40 and tilt(sw['impact']) <= 40
valid = [sw for sw in swings if T[sw['top']] - T[sw['address']] >= 0.2 * sw['span'] and sw['takeaway'] > sw['address'] and sane(sw)]
print('valid swings:', len(valid), 'of', len(swings))
if not valid: sys.exit('no valid swing (address before top)')
swings = valid
swings.sort(key=lambda s: -s['span'])
events = swings[0]; TS = events['tsign']  # 포즈는 가장 느린(긴) 스윙에서
fast = swings[-1]
print('tempo (fastest swing) back %.2f down %.2f follow %.2f' % (T[fast['top']]-T[fast['address']], T[fast['impact']]-T[fast['top']], T[fast['finish']]-T[fast['impact']]))
order = ['address', 'takeaway', 'top', 'impact', 'follow', 'finish']
print('target sign', TS); print('events (t):', {k: round(T[events[k]], 2) for k in order})
tb = T[events['top']] - T[events['address']]; td = T[events['impact']] - T[events['top']]; tf = T[events['finish']] - T[events['impact']]
print(f'timing  backswing {tb:.2f}s  downswing {td:.2f}s  follow {tf:.2f}s  ratio back:down = {tb/td:.2f}')
# 파라미터 (스틱맨 스케일: 몸통 25px, 팔 35px)
armLen = np.percentile(np.linalg.norm(W_ - S_, axis=1), 97)  # 거의 완전 신전
hip0 = H_[events['address']][0]; sh0 = S_[events['address']]
rows = []
for k in order:
    i = events[k]; f = fr[i]
    sh, hp, wr, nz = S_[i], H_[i], W_[i], N_[i]
    hipDx = (hp[0] - hip0) * TS / torso0 * 25
    tilt = math.degrees(math.atan2((sh[0] - hp[0]) * TS, sh[1] - hp[1]))  # + = 타깃 쪽 기울기
    v = wr - sh; handA = math.degrees(math.atan2(v[0] * TS, -v[1])); handD = np.linalg.norm(v) / armLen * 35
    headDx = (nz[0] - sh[0]) * TS / torso0 * 25
    # 뒤꿈치 들림: 트레일(오른발=화면 왼쪽, 인덱스 30) 뒤꿈치 y − 발끝(32) y 대비 어드레스
    heelR = -f['lm'][30][1]; toeR = -f['lm'][32][1]
    rows.append((k, round(T[i], 2), hipDx, tilt, handA, handD, headDx, heelR - toeR))
heel0 = rows[0][7]
print(f'{"pose":9s} {"t":>6s} {"hipDx":>6s} {"tilt":>6s} {"handA":>6s} {"handD":>6s} {"headDx":>6s} {"heel":>5s}')
for k, t, hd, ti, ha, hD, hx, he in rows:
    print(f'{k:9s} {t:6.2f} {hd:6.1f} {ti:6.1f} {ha:6.1f} {hD:6.1f} {hx:6.1f} {(he-heel0)/torso0*25:5.1f}')
json.dump({'events': {k: int(events[k]) for k in order}, 'frames': [fr[events[k]]['f'] for k in order], 'rows': rows, 'timing': [tb, td, tf]}, open(f'{S}/events_{name}.json', 'w'))
# 오버레이 시트
cap = cv2.VideoCapture(VIDEO); tiles = []
CONN = [(11,12),(11,13),(13,15),(12,14),(14,16),(11,23),(12,24),(23,24),(23,25),(25,27),(24,26),(26,28),(27,29),(28,30),(29,31),(30,32)]
for k in order:
    f = fr[events[k]]; cap.set(cv2.CAP_PROP_POS_FRAMES, f['f']); ok, img = cap.read(); crop = (img[:, x0:x1] if x1 else img).copy()
    for a, b in CONN:
        pa, pb = f['lm'][a], f['lm'][b]
        cv2.line(crop, (int(pa[0]), int(pa[1])), (int(pb[0]), int(pb[1])), (0, 255, 0), 3)
    for p in f['lm']:
        cv2.circle(crop, (int(p[0]), int(p[1])), 4, (0, 0, 255), -1)
    cv2.putText(crop, f'{k} {T[events[k]]:.2f}s', (12, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (255, 255, 255), 3)
    tiles.append(cv2.resize(crop, (int(crop.shape[1] * 540 / crop.shape[0]), 540)))
cv2.imwrite(f'{S}/overlay_{name}.png', np.concatenate(tiles, axis=1)); print('overlay written')
