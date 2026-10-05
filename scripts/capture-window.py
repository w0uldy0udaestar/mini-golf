#!/usr/bin/env python3
"""창 단위 관찰 캡처 (개발용 — 앱에는 포함되지 않음). 게임 창 하나만 찍는다: 바탕화면·다른 앱은 찍히지 않는다.

    scripts/capture-window.py OUTDIR MAXSEC --at "PREFIX:nth:delay:count:gap" [--at ...] -- <MiniGolf 인자>

개발 바이너리(.build/debug/MiniGolf)를 띄우고, stdout에 PREFIX로 시작하는 줄이 nth번째 나오면 delay초 뒤부터 그 창만
(`screencapture -l <창 번호>`) count장을 gap초 간격으로 찍는다. `--demo-bg` 없이 돌리면 배경이 투명한 PNG가 나온다 —
`scripts/flatten.swift`로 어두운 바탕에 얹고(창 크기 비율로 잘라 확대 가능) 불투명 픽셀 비율을 확인한다.
관찰 모드는 키보드 포커스를 가져가지 않는다. 종료는 띄운 PID만. 결과물은 커밋하지 않는다.

준비(한 번): swiftc -O scripts/window-id.swift -o /tmp/window-id && swiftc -O scripts/flatten.swift -o /tmp/flatten
예) scripts/capture-window.py /tmp/cap 40 --at "PLAY HOLE:1:1.2:1:0" --at "HOLED:1:0.8:1:0" -- --demo --demo-pickup --weather rain --seed 5
    /tmp/flatten /tmp/cap/PLAYHOLE1-00.raw.png /tmp/cap/intro.png 0.2 0.3 0.6 0.25 1500   # x y w h(창 비율) 최대폭
환경 변수 WINDOW_ID_BIN으로 창 번호 도구 경로를 바꿀 수 있다(기본 /tmp/window-id)."""
import subprocess, sys, time, threading, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WINID = os.environ.get("WINDOW_ID_BIN", "/tmp/window-id")
out, maxsec = sys.argv[1], float(sys.argv[2])
args = sys.argv[3:]
ats, app, i = [], [], 0
while i < len(args):
    if args[i] == "--at":
        pre, nth, delay, cnt, gap = args[i + 1].rsplit(":", 4)
        ats.append([pre, int(nth), float(delay), int(cnt), float(gap), 0]); i += 2
    elif args[i] == "--":
        app = args[i + 1:]; break
    else:
        i += 1
os.makedirs(out, exist_ok=True)
proc = subprocess.Popen([ROOT + "/.build/debug/MiniGolf"] + app, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
t0 = time.time(); log = open(os.path.join(out, "log.txt"), "w"); shots = []
wid = None
def winid():
    global wid
    for _ in range(80):
        r = subprocess.run([WINID, str(proc.pid)], capture_output=True, text=True).stdout.strip().splitlines()
        if r:
            wid = r[0].split()[0]; return
        time.sleep(0.1)
threading.Thread(target=winid, daemon=True).start()
def burst(tag, delay, cnt, gap):
    time.sleep(delay)
    for k in range(cnt):
        if wid is None: break
        fn = os.path.join(out, f"{tag}-{k:02d}.raw.png")
        r = subprocess.run(["screencapture", "-x", "-o", "-l", wid, fn], capture_output=True, text=True)
        if os.path.exists(fn): shots.append(fn)
        else: log.write(f"CAPFAIL {r.stderr.strip()}\n")
        time.sleep(gap)
threads = []
try:
    while time.time() - t0 < maxsec:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None: break
            continue
        ts = time.time() - t0
        log.write(f"[{ts:6.2f}] {line}"); log.flush()
        for a in ats:
            if line.startswith(a[0]):
                a[5] += 1
                if a[5] == a[1]:
                    tag = "".join(c for c in a[0] if c.isalnum())[:14] + f"{a[1]}"
                    th = threading.Thread(target=burst, args=(tag, a[2], a[3], a[4]), daemon=True); th.start(); threads.append(th)
        if ats and all(a[5] >= a[1] for a in ats) and all(not th.is_alive() for th in threads) and threads:
            break
    for th in threads: th.join(timeout=20)
finally:
    proc.terminate(); time.sleep(0.4)
    if proc.poll() is None: proc.kill()
    log.close()
print(f"done {out}: wid={wid} shots={len(shots)} fired={[(a[0], a[5]) for a in ats]} secs={time.time()-t0:.1f}")
for s in shots: print(s)
