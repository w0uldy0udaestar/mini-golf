#!/usr/bin/env python3
"""T1 소재 캡처 드라이버 — scripts/capture-window.py(게임 창 단위 캡처)를 종류별로 부른다.
게임 인자는 셸 변수 없이 argv 리스트로 넘긴다(zsh 단어 분리 사고 방지). 화면은 --screen 0, 배경은 --demo-bg.
속도: screencapture -l 1장 ≈ 0.135초 → 같은 줄에 접두어를 달리한 --at 4개(시차 0.034초)로 겹쳐 찍어 ≈ 25fps.
출력: dist/cap/t1-surprises/<name>/ (커밋 금지 — 저장소 밖 규칙)
사용: shoot.py name kind seed trigger nth count [maxsec]   예) shoot.py geese geese 3 SURPRISE 1 52"""
import os, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
name, kind, seed, trig, nth, count = sys.argv[1:7]
maxsec = sys.argv[7] if len(sys.argv) > 7 else "75"
out = f"{ROOT}/dist/cap/t1-surprises/{name}"
pres = [trig[:max(4, len(trig) - k)] for k in range(4)]  # SURPRISE/SURPRIS/SURPRI/SURPR → 파일 태그가 서로 다르다
args = [sys.executable, f"{ROOT}/scripts/capture-window.py", out, maxsec]
for k, p in enumerate(pres):
    args += ["--at", f"{p}:{nth}:{0.034 * k:.3f}:{count}:0"]
args += ["--", "--demo", "--demo-bg", "--surprise", kind, "--screen", "0", "--seed", seed]
r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
print(name, r.stdout.splitlines()[0] if r.stdout else r.stderr[-400:])
