#!/bin/bash
# 스틱맨 주변 영역 캡처 (2026-09-28): 데모 로그의 트리거 줄이 찍히면 마지막 STICK 줄(x groundY H)로 스틱맨 주변 340×230pt를
# N장 연사한다. 전체 화면(-D 1)을 찍어 sips로 자르는 방식 — `screencapture -R`은 배치에 따라 "could not create image from rect"로 실패한다.
# 메인 화면(--screen 0)에서만 좌표가 맞는다.
#   scripts/capture-stick.sh OUTDIR TAG "TRIGGER PREFIX" COUNT GAP -- <MiniGolf 인자...>
#   예) scripts/capture-stick.sh /tmp/cap slip "SLIP" 8 0.32 -- --demo --demo-bg --seed 1 --demo-ball 296 --demo-slip --demo-power 0.95 --screen 0
#       scripts/capture-stick.sh /tmp/cap aim "AIM" 1 0.1 -- --demo --demo-bg --seed 2 --demo-hole 4 --demo-ball 280 --club SW --demo-power 0.23 --demo-idle --screen 0
set -u
OUT=$1; TAG=$2; TRIG=$3; COUNT=$4; GAP=$5; shift 5
[ "${1:-}" = "--" ] && shift
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
LOG="$OUT/$TAG.log"
.build/debug/MiniGolf "$@" > "$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 160); do grep -q "^$TRIG" "$LOG" && break; sleep 0.25; done
sleep 1.2 # 스탠스 스무딩이 자리 잡을 시간
ST=$(grep '^STICK' "$LOG" | tail -1)
X=$(echo "$ST" | awk '{print int($2)}'); GY=$(echo "$ST" | awk '{print int($3)}'); H=$(echo "$ST" | awk '{print int($4)}')
RX=$((X-170)); RY=$((H-GY-190)); [ $RX -lt 0 ] && RX=0; [ $RY -lt 0 ] && RY=0
for k in $(seq 0 $((COUNT-1))); do
  FULL="$OUT/$TAG-$k-full.png"
  screencapture -x -C "$FULL"
  PH=$(sips -g pixelHeight "$FULL" 2>/dev/null | awk '/pixelHeight/{print $2}')
  SC=$(( PH / H )); [ "$SC" -lt 1 ] && SC=1
  sips --cropToHeightWidth $((230*SC)) $((340*SC)) --cropOffset $((RY*SC)) $((RX*SC)) "$FULL" --out "$OUT/$TAG-$k.png" >/dev/null 2>&1 && rm -f "$FULL"
  sleep "$GAP"
done
kill "$PID" 2>/dev/null; sleep 0.4; kill -9 "$PID" 2>/dev/null
echo "$TAG: trigger=$(grep -m1 "^$TRIG" "$LOG" || echo none) | $ST | region $RX,$RY scale $SC → $OUT"
