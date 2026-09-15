"""analyze_putt.py <name> [t0 t1] — 퍼팅 face-on 키포인트 → 스트로크 이벤트(address·top·impact·finish) + 스틱맨 파라미터 + 오버레이.

풀스윙 검출기(analyze.py)는 손목 '높이' 봉우리를 쓰지만 퍼팅은 손이 거의 안 올라간다. 대신 손목 중점의 **타깃 방향 수평 변위**
(힙 기준)로 찾는다: 뒤로 최대(top) → 어드레스 위치 재통과(impact) → 앞으로 최대(finish). 타깃 방향은 오른손잡이의 왼쪽 =
MediaPipe 왼쪽 힙(23)이 오른쪽 힙(24)보다 화면에서 어느 쪽에 있는지로 판정한다(좌우 식별은 몸 기준이라 미러 영상에도 안전).
출력: events_<name>.json (rows: address·top·impact·finish × hipDx·tilt·handA·handD·headDx), overlay_<name>.png
"""
import json, math, os, sys
import cv2, numpy as np

S = os.environ.get('SWING_WORK', os.path.expanduser('~/swing-work'))
name = sys.argv[1]
T0 = float(sys.argv[2]) if len(sys.argv) > 2 else -1; T1 = float(sys.argv[3]) if len(sys.argv) > 3 else 1e9
D = json.load(open(f'{S}/pose_{name}.json')); fps = D['fps'] / D.get('step', 1); x0, x1 = D['crop']; VIDEO = D.get('video', f'{S}/{name}.mp4')
fr = [f for f in D['frames'] if f['lm'] and T0 <= f['t'] <= T1]
if len(fr) < 10: sys.exit('too few frames with landmarks')
def P(f, i): return np.array([f['lm'][i][0], -f['lm'][i][1]])  # y up
def mid(f, a, b): return (P(f, a) + P(f, b)) / 2
T = np.array([f['t'] for f in fr])
S_ = np.array([mid(f, 11, 12) for f in fr]); H_ = np.array([mid(f, 23, 24) for f in fr]); W_ = np.array([mid(f, 15, 16) for f in fr])
N_ = np.array([P(f, 0) for f in fr])
def sm(a, k=5):
    ker = np.ones(k) / k; return np.stack([np.convolve(a[:, i], ker, mode='same') for i in range(a.shape[1])], axis=1)
S_, H_, W_, N_ = sm(S_), sm(H_), sm(W_), sm(N_)
torso0 = float(np.median(np.linalg.norm(S_ - H_, axis=1)))
# 타깃 방향: 왼쪽 힙(23) x − 오른쪽 힙(24) x 의 중앙값 부호 (오른손잡이 face-on)
TS = 1 if np.median([f['lm'][23][0] - f['lm'][24][0] for f in fr]) > 0 else -1
relx = (W_ - H_)[:, 0] * TS  # + = 타깃 쪽
vel = np.gradient(relx) * fps
w = max(2, int(0.15 * fps))
def local_min(i): return relx[i] <= relx[max(0, i - w):i + w + 1].min()
def local_max(i): return relx[i] >= relx[max(0, i - w):i + w + 1].max()
strokes = []
i = w
while i < len(relx) - w:
    if not local_min(i): i += 1; continue
    top = i
    # finish: top 뒤로 손이 더 나가지 않을 때까지 (최대 8s — 극단 슬로모션 대비). 되돌아오거나(정점 −0.15·몸통) 장면 전환 점프(한 프레임 0.3·몸통)면 정지
    fin = top; best = relx[top]
    for k in range(top + 1, min(len(relx), top + int(8 * fps))):
        if abs(relx[k] - relx[k - 1]) > 0.3 * torso0: break
        if relx[k] > best: best = relx[k]; fin = k
        elif relx[k] < best - 0.15 * torso0: break
    amp = relx[fin] - relx[top]
    if amp < 0.12 * torso0:  # 미세 흔들림 배제
        i += 1; continue
    # address: top에서 거꾸로 가며 손이 타깃 쪽으로 더 가지 않는 첫 정지점 (백스트로크 시작). 최대 2.5s
    j0 = max(0, top - int(2.5 * fps))
    seg = relx[j0:top + 1]
    peak = j0 + int(np.argmax(seg))  # 백스트로크 직전 손 최전방
    # peak 앞쪽으로 속도가 작아지는 구간의 끝을 어드레스로 (포워드 프레스 포함)
    addr = peak
    for k in range(peak, j0, -1):
        if abs(vel[k]) < 0.08 * abs(vel[j0:top + 1]).max(): addr = k; break
    # impact: top 이후 어드레스 x 재통과 (없으면 속도 최대점)
    cross = [k for k in range(top, fin + 1) if relx[k] >= relx[addr]]
    imp = cross[0] if cross else top + int(np.argmax(vel[top:fin + 1]))
    if T[fin] - T[addr] < 0.15 or T[top] - T[addr] < 0.03: i += 1; continue
    strokes.append(dict(address=addr, top=top, impact=imp, finish=fin, amp=amp))
    i = fin + w
if not strokes: sys.exit('no stroke found')
def sane(s):
    drift = abs(H_[s['finish']][0] - H_[s['address']][0]) / torso0 * 25
    return drift <= 8  # 퍼팅은 몸이 거의 안 움직인다 — 카메라 이동·장면 전환 배제
valid = [s for s in strokes if sane(s)]
print(f'[{name}] frames {len(fr)} fps {fps:.1f} torso {torso0:.0f}px target {TS:+d} strokes {len(strokes)} valid {len(valid)}')
for s in strokes:
    print('  cand', {k: round(T[s[k]], 2) for k in ['address', 'top', 'impact', 'finish']}, 'amp/torso %.2f' % (s['amp'] / torso0), 'ok' if s in valid else 'drop')
if not valid: sys.exit('no valid stroke')
# 포즈는 진폭이 가장 큰(잘 보이는) 스트로크, 템포 비율은 가장 짧은 스트로크에서
PICK = os.environ.get('PICK')  # 유효 스트로크 중 n번째를 강제 (슬로모션 클립이 톱에서 시작하는 등 최대 진폭이 오검출일 때)
if PICK is not None and not (0 <= int(PICK) < len(valid)): sys.exit(f'PICK {PICK} out of range (valid strokes: {len(valid)})')
ev = valid[int(PICK)] if PICK is not None else max(valid, key=lambda s: s['amp']); fast = min(valid, key=lambda s: T[s['finish']] - T[s['address']])
order = ['address', 'top', 'impact', 'finish']
tb, td, tf = (T[fast['top']] - T[fast['address']], T[fast['impact']] - T[fast['top']], T[fast['finish']] - T[fast['impact']])
print('events (t):', {k: round(T[ev[k]], 2) for k in order})
print(f'tempo (shortest) back {tb:.2f}s down {td:.2f}s follow {tf:.2f}s  back:down {tb/max(td,1e-6):.2f}  back:follow amp {(relx[ev["address"]]-relx[ev["top"]]):.0f}:{(relx[ev["finish"]]-relx[ev["address"]]):.0f}px')
armLen = np.percentile(np.linalg.norm(W_ - S_, axis=1), 97)
hip0 = H_[ev['address']][0]
rows = []
for k in order:
    i = ev[k]; sh, hp, wr, nz = S_[i], H_[i], W_[i], N_[i]
    hipDx = (hp[0] - hip0) * TS / torso0 * 25
    tilt = math.degrees(math.atan2((sh[0] - hp[0]) * TS, sh[1] - hp[1]))
    v = wr - sh; handA = math.degrees(math.atan2(v[0] * TS, -v[1])); handD = float(np.linalg.norm(v) / armLen * 35)
    headDx = (nz[0] - sh[0]) * TS / torso0 * 25
    rows.append((k, round(float(T[i]), 2), float(hipDx), float(tilt), float(handA), handD, float(headDx), 0.0))
print(f'{"pose":8s} {"t":>6s} {"hipDx":>6s} {"tilt":>6s} {"handA":>6s} {"handD":>6s} {"headDx":>6s}')
for k, t, hd, ti, ha, hD, hx, _ in rows:
    print(f'{k:8s} {t:6.2f} {hd:6.1f} {ti:6.1f} {ha:6.1f} {hD:6.1f} {hx:6.1f}')
json.dump({'events': {k: int(ev[k]) for k in order}, 'frames': [fr[ev[k]]['f'] for k in order], 'rows': rows,
           'timing': [float(tb), float(td), float(tf)], 'torso_px': torso0, 'target': TS,
           'amp_px': [float(relx[ev['address']] - relx[ev['top']]), float(relx[ev['finish']] - relx[ev['address']])]},
          open(f'{S}/events_{name}.json', 'w'))
cap = cv2.VideoCapture(VIDEO); tiles = []
CONN = [(11,12),(11,13),(13,15),(12,14),(14,16),(11,23),(12,24),(23,24),(23,25),(25,27),(24,26),(26,28),(27,29),(28,30),(29,31),(30,32)]
for k in order:
    f = fr[ev[k]]; cap.set(cv2.CAP_PROP_POS_FRAMES, f['f']); ok, img = cap.read()
    if not ok: continue
    crop = (img[:, x0:x1] if x1 else img).copy()
    for a, b in CONN:
        pa, pb = f['lm'][a], f['lm'][b]
        cv2.line(crop, (int(pa[0]), int(pa[1])), (int(pb[0]), int(pb[1])), (0, 255, 0), 3)
    for p in f['lm']:
        cv2.circle(crop, (int(p[0]), int(p[1])), 4, (0, 0, 255), -1)
    cv2.putText(crop, f'{k} {T[ev[k]]:.2f}s', (12, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (255, 255, 255), 3)
    tiles.append(cv2.resize(crop, (int(crop.shape[1] * 540 / crop.shape[0]), 540)))
cv2.imwrite(f'{S}/overlay_{name}.png', np.concatenate(tiles, axis=1)); print('overlay written')
