"""events_<name>.json(rows) → 스타일×클럽군 SwingKeyframes Swift 코드. 편차 1.3배 과장 + 공 접촉 기하 보정."""
import json, math, sys, os
W = os.environ.get('SWING_WORK', os.path.expanduser('~/swing-work'))
SRC = {('rory','ir'): f'{W}/events_rory_ir.json', ('rory','dr'): f'{W}/events_rory_dr.json',
       ('tiger','dr'): f'{W}/events_tiger_dr2.json', ('tiger','ir'): f'{W}/events_tiger_ir.json',
       ('bryson','dr'): f'{W}/events_bryson_dr.json', ('bryson','ir'): f'{W}/events_bryson_ir.json'}
KEYS = ['address','takeaway','top','impact','follow','finish']
EX = 1.3  # 과장 배율 (사용자 결정 2026-09-15)
raw = {}
for (st, gp), path in SRC.items():
    if not os.path.exists(path): print('missing', st, gp); continue
    rows = json.load(open(path))['rows']
    raw[(st, gp)] = {r[0]: dict(hipDx=r[2], tiltDeg=r[3], handA=r[4], handD=r[5], headDx=r[6], heel=r[7]) for r in rows}
    # heel: 실측 rows[7]은 원시(픽셀) — analyze.py 출력과 같은 정규화: (heel-heel0)/torso*25 는 표에만 있었으므로 여기선 rows 값 그대로 쓰지 않고 상대값 계산
    h0 = rows[0][7]; torso_px = None
    for r in rows: raw[(st, gp)][r[0]]['heel'] = r[7] - h0
# 몸통 px는 events에 없으므로 heel은 스틱맨 단위로 근사 변환: 로리 슬로 166px, 로리dr 99, 타이거dr 91, 타이거ir(720p) ~140, 브라이슨dr ~140, 브라이슨ir ~120
TORSO = {('rory','ir'):166, ('rory','dr'):99, ('tiger','dr'):91, ('tiger','ir'):140, ('bryson','dr'):140, ('bryson','ir'):120}
for k, d in raw.items():
    for key in KEYS: d[key]['heel'] = max(0.0, d[key]['heel'] / TORSO[k] * 25)
def net_from_tilt(deg): return 25 * math.tan(math.radians(deg))
def tilt_game(net): return 2 * (net - 6)
styles = ['rory','tiger','bryson']
out = {}
for gp in ['dr','ir']:
    have = [st for st in styles if (st, gp) in raw]
    for st in have:
        poses = {}
        for key in KEYS:
            m = raw[(st, gp)][key]
            def ex(param, conv=lambda v: v):
                vals = [conv(raw[(s, gp)][key][param]) for s in have]
                mean = sum(vals) / len(vals); v = conv(m[param])
                return mean + EX * (v - mean)
            hipDx = 0.0 if key == 'address' else ex('hipDx')
            net = ex('tiltDeg', net_from_tilt); tilt = tilt_game(net)
            headDx = ex('headDx') + 4; heel = max(0.0, ex('heel'))  # 머리 +4: 스틱맨 관례(어드레스 ≈5, 공을 내려다봄)
            handA = ex('handA'); handD = ex('handD')
            if key == 'address':
                handD = 34; clubA = 12
                d = 0.5 * (tilt - (-12))  # 로리 아이언 기준 어깨 x 변화 → 손 각으로 상쇄 (헤드 위치 불변)
                handA = math.degrees(math.asin(max(-1, min(1, (math.sin(math.radians(12)) * 34 - d) / 34))))
            elif key == 'impact':
                handD = 34; clubA = 6
                d = (hipDx - 11) + 0.5 * (tilt - (-19))
                handA = math.degrees(math.asin(max(-1, min(1, (math.sin(math.radians(12)) * 34 - d) / 34))))
                heel = max(heel, 1.0)
            elif key == 'takeaway':
                clubA = -110; handD = max(30, min(34, handD))  # 저해상도 오검출 하한
            elif key == 'top':
                clubA = {'rory': {'dr': -275, 'ir': -268}, 'tiger': {'dr': -268, 'ir': -262}, 'bryson': {'dr': -235, 'ir': -230}}[st][gp]
                handD = max(17, min(30, handD))
            elif key == 'follow':
                clubA = 125; handD = max(26, min(34, handD)); handA = max(70, min(95, handA))
            elif key == 'finish':
                clubA = {'rory': 270, 'tiger': 270, 'bryson': 300}[st]
                handD = max(19, min(28, handD))
                if handA < 0: handA += 360  # 머리 뒤로 감김(196°) 표기 — 팔로(87°)에서 연속으로 올라가도록
                handA = max(140, min(200, handA))
            poses[key] = dict(hipDx=round(hipDx,1), tilt=round(tilt,1), handA=round(handA,1), handD=round(handD,1), clubA=clubA, heel=round(heel,1), headDx=round(headDx,1))
        tempo = {'rory': (0.24, 0.12, 0.30), 'tiger': (0.24, 0.12, 0.32), 'bryson': (0.21, 0.10, 0.26)}[st]
        out[(st, gp)] = (poses, tempo)
names = {'address':'p1','takeaway':'p2','top':'p4','impact':'p7','follow':'p8','finish':'p10'}
def swift(st, gp):
    poses, (d, f, fi) = out[(st, gp)]
    lines = [f"    static let {st}{'Driver' if gp=='dr' else 'Iron'} = SwingKeyframes("]
    for key in KEYS:
        p = poses[key]
        lines.append(f"        {names[key]}: Pose(hipDx: {p['hipDx']}, tilt: {p['tilt']}, handA: {p['handA']}, handD: {p['handD']}, clubA: {p['clubA']}, heel: {p['heel']}, headDx: {p['headDx']}),")
    lines.append(f"        down: {d}, follow: {f}, finish: {fi}")
    lines.append("    )")
    return '\n'.join(lines)
for (st, gp) in out:
    print(swift(st, gp)); print()
json.dump({f'{st}_{gp}': v for (st, gp), v in out.items()}, open(f'{W}/table.json', 'w'), indent=1)
