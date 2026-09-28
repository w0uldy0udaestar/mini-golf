#!/bin/bash
# 스틱맨 주변 영역 캡처 (2026-09-28): 데모 로그의 트리거 줄이 찍히면 마지막 STICK 줄(x groundY H)로 스틱맨 주변 340×230pt를
# N장 연사한다. 전체 화면 캡처(capture-demo.py)는 스틱맨이 너무 작아 판독이 안 될 때 쓴다. 메인 화면(--screen 0)에서만 좌표가 맞는다.
#   scripts/capture-stick.sh OUTDIR TAG "TRIGGER PREFIX" COUNT GAP -- <MiniGolf 인자...>
#   예) scripts/capture-stick.sh /tmp/cap slip "SLIP" 8 0.32 -- --demo --demo-bg --seed 1 --demo-ball 296 --demo-slip --demo-power 0.95 --screen 0
#       scripts/capture-stick.sh /tmp/cap divot "PLAY SHOT 2" 5 0.14 -- --demo --demo-bg --seed 1 --demo-ball 200 --club 7I --demo-power 0.9 --screen 0
set -u
OUT=$1; TAG=$2; TRIG=$3; COUNT=$4; GAP=$5; shift 5
[ "${1:-}" = "--" ] && shift
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
LOG="$OUT/$TAG.log"
.build/debug/MiniGolf "$@" > "$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 160); do grep -q "^$TRIG" "$LOG" && break; sleep 0.25; done
ST=$(grep '^STICK' "$LOG" | tail -1)
X=$(echo "$ST" | awk '{print int($2)}'); GY=$(echo "$ST" | awk '{print int($3)}'); H=$(echo "$ST" | awk '{print int($4)}')
RX=$((X-170)); RY=$((H-GY-190))
for k in $(seq 0 $((COUNT-1))); do
  screencapture -x -R "$RX,$RY,340,230" "$OUT/$TAG-$k.png"
  sleep "$GAP"
done
kill "$PID" 2>/dev/null; sleep 0.4; kill -9 "$PID" 2>/dev/null
echo "$TAG: trigger=$(grep -m1 "^$TRIG" "$LOG" || echo none) | $ST | $COUNT shots → $OUT"
