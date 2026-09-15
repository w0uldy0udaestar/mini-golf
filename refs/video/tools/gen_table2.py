"""gen_table2.py — 2단계(웨지·퍼터) events_<style>_{wg|pt}.json → Swift 코드 (SwingKeyframes 웨지 세트 3 + PutterKeyframes 3).

1단계 gen_table.py와 같은 원리: 세 선수 평균 대비 편차를 EX배 과장, 공 접촉이 걸린 어드레스·임팩트의 손·클럽 기하는 고정하고
tilt·hipDx 변화를 handA로 상쇄. 웨지 톱·피니시 샤프트 각은 검출 불안정 → 선수 특징 기반 상수(아이언보다 짧게).
퍼터: 표준 펜듈럼은 clubA = handA + 손목 오프셋(어드레스 −2·톱 −8·임팩트 −2·피니시 +12, 기존 ptA~ptFin에서),
브라이슨 암록은 clubA == handA (전완과 한 직선) — 손 높이·렌더 길이·butt는 기존 armLock 값 유지.
"""
import json, math, os, sys
W = os.environ.get('SWING_WORK', os.path.expanduser('~/swing-work'))
EX = float(os.environ.get('EX', '2.5'))  # 과장 배율 (1단계와 동일, 2026-09-15)
STYLES = ['rory', 'tiger', 'bryson']
def load(st, gp):
    p = f'{W}/events_{st}_{gp}.json'
    if not os.path.exists(p): return None
    E = json.load(open(p)); rows = E['rows']
    d = {r[0]: dict(hipDx=r[2], tiltDeg=r[3], handA=r[4], handD=r[5], headDx=r[6], heelRaw=r[7]) for r in rows}
    d['_timing'] = E.get('timing'); d['_torso'] = E.get('torso_px'); d['_amp'] = E.get('amp_px')
    return d
def net_from_tilt(deg): return 25 * math.tan(math.radians(deg))
def tilt_game(net): return 2 * (net - 6)
def exag(vals, v): m = sum(vals) / len(vals); return m + EX * (v - m)

# ── 웨지 ──
WKEYS = ['address', 'takeaway', 'top', 'impact', 'follow', 'finish']
wedge = {st: load(st, 'wg') for st in STYLES}
have_w = [st for st in STYLES if wedge[st]]
NAMES = {'address': 'p1', 'takeaway': 'p2', 'top': 'p4', 'impact': 'p7', 'follow': 'p8', 'finish': 'p10'}
TOP_CLUBA = {'rory': -235, 'tiger': -230, 'bryson': -205}     # 웨지 3/4: 아이언(−268/−262/−230)보다 짧게
FIN_CLUBA = {'rory': 250, 'tiger': 250, 'bryson': 285}        # 피니시도 덜 감김 (아이언 270/270/300)
TEMPO = {'rory': (0.24, 0.12, 0.28), 'tiger': (0.24, 0.12, 0.30), 'bryson': (0.17, 0.08, 0.20)}  # 1단계 템포 유지(웨지는 약간 짧게)
TOPHOLD = {'rory': 0.0, 'tiger': 0.08, 'bryson': 0.0}
IRON_FINISH = {'rory': (140, 28), 'tiger': (200, 21.5), 'bryson': (200, 20.2)}  # 1단계 아이언 p10 (handA, handD)
out_w = {}
for st in have_w:
    poses = {}
    for key in WKEYS:
        m = wedge[st][key]
        def ex(param, conv=lambda v: v):
            return exag([conv(wedge[s][key][param]) for s in have_w], conv(m[param]))
        hipDx = 0.0 if key == 'address' else ex('hipDx')
        tilt = tilt_game(ex('tiltDeg', net_from_tilt))
        headDx = max(1.0, ex('headDx') + 4) if key in ('takeaway', 'top') else ex('headDx') + 4  # 백스윙 머리 ≥ +1 (eccf119)
        handA = ex('handA'); handD = ex('handD')
        heel = 0.0
        if key == 'address':
            handD = 34; clubA = 12
            d = 0.5 * (tilt - (-12))
            handA = math.degrees(math.asin(max(-1, min(1, (math.sin(math.radians(12)) * 34 - d) / 34))))
        elif key == 'impact':
            handD = 34; clubA = 6; heel = 1.0
            d = (hipDx - 11) + 0.5 * (tilt - (-19))
            handA = math.degrees(math.asin(max(-1, min(1, (math.sin(math.radians(12)) * 34 - d) / 34))))
        elif key == 'takeaway':
            clubA = -100; handD = max(30, min(34, handD)); handA = max(-95, min(-35, handA))  # 손이 거의 안 움직인 조기 검출 방어
        elif key == 'top':
            clubA = TOP_CLUBA[st]; handD = max(20, min(32, handD))
        elif key == 'follow':
            clubA = 120; handD = max(26, min(34, handD)); handA = max(65, min(95, handA)); heel = 3.0
        elif key == 'finish':
            clubA = FIN_CLUBA[st]; heel = 6.0
            if handA < 0: handA += 360
            if m['handA'] < 100:  # 클립이 팔로스루에서 끝남(타이거 코스티스 영상) → 손·팔은 아이언 피니시로 대체, 몸은 실측
                handA, handD = IRON_FINISH[st]
            handD = max(19, min(30, handD)); handA = max(130, min(200, handA))
        poses[key] = dict(hipDx=round(hipDx, 1), tilt=round(tilt, 1), handA=round(handA, 1), handD=round(handD, 1),
                          clubA=clubA, heel=heel, headDx=round(headDx, 1))
    out_w[st] = poses
def swift_wedge(st):
    p = out_w[st]; d, f, fi = TEMPO[st]
    L = [f'    static let {st}Wedge = SwingKeyframes(']
    for key in WKEYS:
        q = p[key]
        L.append(f"        {NAMES[key]}: Pose(hipDx: {q['hipDx']}, tilt: {q['tilt']}, handA: {q['handA']}, handD: {q['handD']}, clubA: {q['clubA']}, heel: {q['heel']}, headDx: {q['headDx']}),")
    L.append(f'        down: {d}, follow: {f}, finish: {fi}, topHold: {TOPHOLD[st]}')
    L.append('    )')
    return '\n'.join(L)

# ── 퍼터 ──
# 원칙: 실측 자세(척추 거의 수직·손은 어깨 아래·공은 스탠스 중앙 약간 앞)를 그대로 쓰고, 어드레스·임팩트 손 각은 "헤드가 공 뒤 5px"가
# 되도록 수치 해로 푼다(구 ptA는 공이 힙 23px 앞(드라이버급)이라 손을 10° 앞으로 밀어야 했다). 암록은 전진 프레스(샤프트 11°)를
# 지키려면 공이 앞쪽이어야 해서 ballFwd를 따로 둔다. 백스트로크 폭은 사용자 입력이라 표준 −32°를 공용으로, 실측에서는
# ① 자세(tilt·머리·힙) ② 팔로스루 길이(피니시 손 각 − 어드레스, 평균 대비 1.5배 과장)만 가져온다.
PKEYS = ['address', 'top', 'impact', 'finish']
PNAME = {'address': 'a', 'top': 'top', 'impact': 'imp', 'finish': 'fin'}
WRIST = {'address': -2, 'top': -8, 'impact': -2, 'finish': 12}  # 표준 펜듈럼 손목 오프셋 (ptA~ptFin 기존값)
EXP = 1.5
BALLFWD = {'std': 6, 'armlock': 16}
putt = {st: load(st, 'pt') for st in STYLES}
have_p = [st for st in STYLES if putt[st]]
def fwd(st): return putt[st]['finish']['handA'] - putt[st]['address']['handA']
fwd_mean = sum(fwd(s) for s in have_p) / max(1, len(have_p))
def solve_handA(shoulder_x, eff, length, wrist_deg, tip_x):
    """shoulder_x + eff·sin a + length·sin(a + wrist) = tip_x 를 이분법으로 (a: −40°~60°)"""
    lo, hi = -40.0, 60.0
    f = lambda a: shoulder_x + eff * math.sin(math.radians(a)) + length * math.sin(math.radians(a + wrist_deg)) - tip_x
    for _ in range(60):
        mid = (lo + hi) / 2
        if f(lo) * f(mid) <= 0: hi = mid
        else: lo = mid
    return (lo + hi) / 2
out_p = {}
for st in have_p:
    armlock = st == 'bryson'
    length = 43 if armlock else 34
    handD = 34 if armlock else 30
    eff = handD - (length - 31)  # RigBuilder 긴 클럽 보정 후 실제 어깨→손 거리
    ballFwd = BALLFWD['armlock' if armlock else 'std']
    poses = {}
    for key in PKEYS:
        m = putt[st][key]
        def ex(param, conv=lambda v: v):
            return exag([conv(putt[s][key][param]) for s in have_p], conv(m[param]))
        hipDx = 0.0 if key == 'address' else max(-3, min(3, ex('hipDx')))
        tilt = max(-14, min(0, tilt_game(ex('tiltDeg', net_from_tilt))))
        headDx = max(0.0, ex('headDx') + 4)
        shoulder_x = -ballFwd + 1 + 0.5 * tilt  # 힙 = −ballFwd−5, 어깨 = 힙+6+0.5·tilt (어드레스 hipDx 0)
        wrist = 0 if armlock else WRIST['address']
        a_handA = solve_handA(shoulder_x, eff, length, wrist, tip_x=-5)  # 헤드 팁은 공 중심 5px 뒤 (기존 어드레스 기하)
        if key == 'address': handA = a_handA
        elif key == 'top': handA = a_handA - 32
        elif key == 'impact': handA = a_handA + 2
        else: handA = a_handA + (fwd_mean + EXP * (fwd(st) - fwd_mean))
        clubA = round(handA if armlock else handA + WRIST[key], 1)
        poses[key] = dict(hipDx=round(hipDx, 1), tilt=round(tilt, 1), handA=round(handA, 1), handD=handD, clubA=clubA, headDx=round(headDx, 1))
    out_p[st] = (poses, ballFwd)
def swift_putt(st):
    (p, ballFwd) = out_p[st]; armlock = st == 'bryson'
    L = [f'    static let {st}Putt = PutterKeyframes(']
    for key in PKEYS:
        q = p[key]
        L.append(f"        {PNAME[key]}: Pose(hipDx: {q['hipDx']}, tilt: {q['tilt']}, handA: {q['handA']}, handD: {q['handD']}, clubA: {q['clubA']}, heel: 0, headDx: {q['headDx']}),")
    L.append(f"        len: {43 if armlock else 34}, butt: {10 if armlock else 0}, ballFwd: {ballFwd}")
    L.append('    )')
    return '\n'.join(L)

for st in have_w: print(swift_wedge(st)); print()
for st in have_p: print(swift_putt(st)); print()
for st in have_w: print(f'// {st} wedge timing (video, slow-mo) back/down/follow:', wedge[st]['_timing'])
for st in have_p: print(f'// {st} putt timing (video, slow-mo) back/down/follow:', putt[st]['_timing'], 'amp back/fwd px:', putt[st]['_amp'])
json.dump({'wedge': out_w, 'putt': {k: v[0] for k, v in out_p.items()}}, open(f'{W}/table2.json', 'w'), indent=1)
