#!/usr/bin/env python3
"""범용 관찰 캡처: capture2.py OUTDIR MAXSEC --trigger "PREFIX:dur:gap:count" [...] -- <MiniGolf args...>"""
import subprocess, sys, time, threading, os, re, signal
out, maxsec = sys.argv[1], float(sys.argv[2])
args = sys.argv[3:]
triggers, app, i = [], [], 0
while i < len(args):
    if args[i] == "--trigger":
        pre, dur, gap, cnt = args[i + 1].rsplit(":", 3)
        triggers.append((pre, float(dur), float(gap), int(cnt))); i += 2
    elif args[i] == "--":
        app = args[i + 1:]; break
    else:
        i += 1
os.makedirs(out, exist_ok=True)
proc = subprocess.Popen([".build/debug/MiniGolf"] + app, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
t0 = time.time(); log = open(os.path.join(out, "log.txt"), "w"); busy = threading.Lock(); shots = [0]
def burst(tag, dur, gap):
    if not busy.acquire(blocking=False): return
    try:
        tb = time.time(); k = 0
        while time.time() - tb < dur:
            fn = os.path.join(out, f"{tag}-{k:02d}.png")
            subprocess.run(["screencapture", "-x", "-C", fn], check=False)
            subprocess.run(["sips", "-Z", "1600", fn], check=False, stdout=subprocess.DEVNULL)
            shots[0] += 1; k += 1; time.sleep(gap)
    finally:
        busy.release()
fired = {}
try:
    while time.time() - t0 < maxsec:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None: break
            continue
        ts = time.time() - t0
        log.write(f"[{ts:6.2f}] {line}"); log.flush()
        for pre, dur, gap, cnt in triggers:
            if line.startswith(pre) and fired.get(pre, 0) < cnt:
                fired[pre] = fired.get(pre, 0) + 1
                tag = re.sub(r"[^A-Za-z]+", "", pre)[:12] + f"{fired[pre]}-{ts:04.0f}"
                threading.Thread(target=burst, args=(tag, dur, gap), daemon=True).start()
finally:
    proc.send_signal(signal.SIGTERM); time.sleep(0.5)
    if proc.poll() is None: proc.kill()
    log.close()
print(f"done {out}: shots={shots[0]} fired={fired}")
