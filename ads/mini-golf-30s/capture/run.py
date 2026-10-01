"""광고 캡처 오케스트레이터 (30초판) — 개발 바이너리를 --demo로 띄우고 그 창만 ScreenCaptureKit으로 연사한다.

사용: python3 run.py <tag> <secs> <scale> <fps> -- <게임 인자...>
  - 게임 인자는 셸 변수 없이 argv로 그대로 넘긴다 (zsh 단어 분리 사고 방지)
  - 사용자 게임(dist/MiniGolf.app)은 건드리지 않는다: 종료는 우리가 띄운 PID를 kill + `pkill -f "\\.build/debug/MiniGolf"`(개발 바이너리 경로만 맞는 패턴)
  - 개발 인스턴스가 실행 시 가져간 키보드 포커스는 창이 뜨자마자 원래 앱으로 되돌린다 (합성 키 입력은 보내지 않는다)
  - 데스크탑은 찍지 않는다: SCK desktopIndependentWindow 필터 = 우리 PID의 창 하나만
출력: $CAPOUT/<tag>/f*.png (알파 PNG), times.txt(pts, wall), game.log(wall 타임스탬프 붙은 stdout)
(15초판 ads/mini-golf-15s/capture/run.py 복사 + 종료 확인·요약 출력)
"""
import os, subprocess, sys, threading, time

ROOT = "/Users/universe/Project/mini-golf"
BIN = f"{ROOT}/.build/debug/MiniGolf"
CAPCTL = os.environ.get("CAPCTL", "capctl")
OUT = os.environ.get("CAPOUT", "/tmp/cap")

tag, secs, scale, fps = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
game_args = sys.argv[sys.argv.index("--") + 1:]
out = f"{OUT}/{tag}"
os.makedirs(out, exist_ok=True)

front = subprocess.run([CAPCTL, "front"], capture_output=True, text=True).stdout.strip()
t_launch = time.time()
proc = subprocess.Popen([BIN, *game_args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
log = open(f"{out}/game.log", "w")

def pump():
    for line in proc.stdout:
        log.write(f"{time.time():.3f} {line}")
        log.flush()

threading.Thread(target=pump, daemon=True).start()
try:
    wid = "0"
    for _ in range(60):
        wid = subprocess.run([CAPCTL, "winid", str(proc.pid)], capture_output=True, text=True).stdout.strip()
        if wid not in ("", "0"):
            break
        time.sleep(0.05)
    if front and front != "0":
        r = subprocess.run([CAPCTL, "activate", front], capture_output=True, text=True).stdout.strip()
        print(f"focus restore → pid {front}: {r} (+{time.time() - t_launch:.2f}s after launch)", flush=True)
    print(f"game pid {proc.pid} window {wid} args {' '.join(game_args)}", flush=True)
    t_start = time.time()
    s = subprocess.run([CAPCTL, "stream", str(proc.pid), out, fps, str(secs), scale], capture_output=True, text=True)
    print(s.stdout.strip(), s.stderr.strip()[-300:], f"(wall {time.time() - t_start:.1f}s)", flush=True)
finally:
    proc.kill()
    proc.wait()
    log.close()
    subprocess.run(["pkill", "-f", r"\.build/debug/MiniGolf"])
    left = subprocess.run(["pgrep", "-fl", r"\.build/debug/MiniGolf"], capture_output=True, text=True).stdout.strip()
    user = subprocess.run(["pgrep", "-fl", "dist/MiniGolf.app"], capture_output=True, text=True).stdout.strip()
    print(f"dev instance left: {left or 'none'} · user app: {user or 'not running'}", flush=True)
