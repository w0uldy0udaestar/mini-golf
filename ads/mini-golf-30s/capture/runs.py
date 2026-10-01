#!/usr/bin/env python3
"""30초판 캡처 계획 — 실행 목록(8회 이하, 한 번 30초) + 실행 + 사후 점검.

  python3 runs.py list              → 계획 출력
  python3 runs.py run <tag>         → 그 한 번만 실행 (원본은 $CAPOUT/<tag>/ = 스크래치패드)
  python3 runs.py check <tag>       → 프레임 수·실효 fps·알파·로그 이벤트 점검

원칙: 매 실행은 ScreenCaptureKit 단일 창 스트림(우리 PID 창 하나 — 데스크탑 미포함), 합성 키 입력 없음(--demo* 플래그만),
실행 뒤 개발 인스턴스만 종료(run.py). 모든 실행에 --demo-trademark(굿샷 트월 강제 + 60Hz 리그 덤프 → 벡터 스틱맨 재현)를 건다.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAPOUT = os.environ.get("CAPOUT", "/tmp/cap")
SECS, SCALE, FPS = 30, 2, 30

RUNS = [  # (tag, 게임 인자, 목적 — 어느 광고 컷에 쓰는가)
    ("geese", ["--demo", "--seed", "1", "--demo-hole", "3", "--surprise", "geese", "--hat", "propeller", "--demo-trademark"],
     "M2 거위 떼 — 협곡(seed1 h3 파4, 티 왼쪽). 티샷→정지→거위 다섯 줄지어 옴→둘째가 공 위에 앉음→훠이훠이→흩어짐+알"),
    ("dog", ["--demo", "--seed", "1", "--demo-hole", "2", "--surprise", "dog", "--hat", "top", "--demo-trademark"],
     "M3 강아지 — 폭포(seed1 h2 파4, 미러 홀). 티샷→정지→강아지가 공을 물고 달아나 떨어뜨림. 짧으면 연못 입수(보너스)"),
    ("gallery", ["--demo", "--seed", "1", "--demo-hole", "5", "--surprise", "gallery", "--demo-trademark"],
     "M4 갤러리 — 능선(seed1 h5 파4, 미러 홀). 티샷→관중 넷 입장→둘째 샷→환호/박수/야유→퇴장. 모자 없음(기본 모습)"),
    ("holeout", ["--demo", "--seed", "1", "--demo-hole", "7", "--demo-pickup", "--demo-ball", "312", "--hat", "crown", "--demo-trademark"],
     "M6 홀인·줍기 — 산정 그린(seed1 h7 파4, 컵 319m). 7m 퍼트(프리셋 세기)→컵인→공 줍기 의식. 왕관"),
    ("memes", ["--demo", "--seed", "1", "--demo-hole", "1", "--demo-memes", "--demo-power", "1", "--hat", "straw", "--demo-trademark"],
     "M1 드라이브(계단 대지 seed1 h1 파5, 풀파워) + M5 댄스(첫 걷기 쇼피스 whiffSpin, 둘째 auraFarm) — 댄스는 리그로 벡터 재현. 밀짚모자"),
    ("cuckoo", ["--demo", "--seed", "1", "--demo-hole", "7", "--surprise", "cuckoo", "--demo-hour", "15", "--hat", "crown", "--demo-trademark"],
     "(선택) 3시 정각 뻐꾸기 — 조준 중 화면 위에서 시계가 내려와 세 번 운다. 예산 남으면"),
    # ── 2단계 (2026-10-01, 모자 왕관 통일) ──
    ("terraces-crown", ["--demo", "--seed", "1", "--demo-hole", "1", "--demo-power", "1", "--hat", "crown", "--demo-trademark"],
     "R7 M1 풀파워 드라이브 재촬영 — 왕관 (R5 밀짚모자 대체)"),
    ("dog-crown", ["--demo", "--seed", "1", "--demo-hole", "2", "--demo-power", "0.62", "--surprise", "dog", "--hat", "crown", "--demo-trademark"],
     "R8 M3 강아지 재촬영 — 왕관 (R2 실크햇 대체)"),
]

def plan():
    for i, (tag, args, why) in enumerate(RUNS, 1):
        print(f"R{i} {tag:8s} {SECS}s @{FPS}fps x{SCALE}  {' '.join(args)}\n    → {why}")

def run(tag):
    args = next(a for t, a, _ in RUNS if t == tag)
    env = dict(os.environ, CAPOUT=CAPOUT)
    r = subprocess.run([sys.executable, f"{HERE}/run.py", tag, str(SECS), str(SCALE), str(FPS), "--", *args], env=env)
    return r.returncode

def check(tag):
    from PIL import Image
    d = f"{CAPOUT}/{tag}"
    fr = sorted(f for f in os.listdir(d) if f.startswith("f") and f.endswith(".png"))
    ts = [tuple(map(float, l.split())) for l in open(f"{d}/times.txt")] if os.path.exists(f"{d}/times.txt") else []
    span = ts[-1][0] - ts[0][0] if len(ts) > 1 else 0
    gaps = [b[0] - a[0] for a, b in zip(ts, ts[1:])]
    im = Image.open(f"{d}/{fr[len(fr) // 2]}")
    a = im.getchannel("A") if im.mode == "RGBA" else None
    hist = a.histogram() if a else []
    transp = (hist[0] / sum(hist)) if hist else None
    log = open(f"{d}/game.log").read()
    ev = {k: len(re.findall(k, log)) for k in ["PLAY HOLE", "PLAY SHOT", "PLAY REST", "SURPRISE", "GEESE", "DOG", "GALLERY", "HOLED", "RITUAL ballPickup",
                                                 "SHOWPIECE|showpiece|SHOW", "CUCKOO", "WATER", "RIG\\["]}
    out = {"tag": tag, "frames": len(fr), "size": im.size, "mode": im.mode, "span": round(span, 2),
           "fps": round((len(ts) - 1) / span, 2) if span else 0, "maxGap": round(max(gaps), 3) if gaps else 0,
           "gaps>50ms": sum(g > 0.05 for g in gaps), "transparentFrac": round(transp, 4) if transp is not None else None, "events": ev,
           "hole": (re.search(r"PLAY HOLE .*", log) or [None])[0]}
    print(json.dumps(out, ensure_ascii=False, indent=1))
    json.dump(out, open(f"{d}/check.json", "w"), ensure_ascii=False, indent=1)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list": plan()
    elif cmd == "run": sys.exit(run(sys.argv[2]))
    elif cmd == "check": check(sys.argv[2])
