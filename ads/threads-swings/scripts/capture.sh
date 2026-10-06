#!/bin/sh
# 소재 재캡처 (창 단위만 — 게임 창 하나, 바탕화면·다른 앱은 찍히지 않는다). 사용: ./scripts/capture.sh jump|twirl|lock
# 준비(한 번): swiftc -O ../../scripts/window-id.swift -o <bin>/window-id 를 만들고 WINDOW_ID_BIN=<bin>/window-id 로 넘긴다.
# 결과: ../../dist/cap/threads-swings/<동작>/ (log.txt = 60Hz 리그 덤프 + 스틸 PNG). 커밋하지 않는다. 띄운 프로세스는 스크립트가 직접 종료한다.
set -e
here=$(cd "$(dirname "$0")/.." && pwd); root=$(cd "$here/../.." && pwd)
case "$1" in
  jump) st=rory ;; twirl) st=tiger ;; lock) st=bryson ;; *) echo "usage: $0 jump|twirl|lock"; exit 1 ;;
esac
python3 "$root/scripts/capture-window.py" "$root/dist/cap/threads-swings/$1" 20 \
  --at "AIM x:1:0.25:2:0.05" --at "PLAY SHOT:1:0.9:4:0.08" --at "TRADEMARK:1:1.6:3:0.1" \
  -- --demo --demo-bg --demo-trademark --style "$st" --demo-power 1.0 --club DR --hat none --screen 0
