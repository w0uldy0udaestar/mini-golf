#!/bin/sh
# 렌더 (결정성: 워커 1 · 스크린샷 캡처 · 브라우저 소프트웨어 래스터(--no-browser-gpu) · 텔레메트리 끔): ./scripts/render.sh [출력 경로]
# 기본 → dist/ads/threads/t5-broadcast-v-ko.mp4
#
# 2단계로 나눈다 (2차 수정 때 실측):
#   1) HyperFrames가 PNG 시퀀스로 찍는다. 브라우저 GPU 래스터(기본 auto→hardware)는 5회 중 1회가 풀백 중(f29–31) 판 이미지
#      영역에서 1~2레벨 달랐다(타이밍 경합) → 소프트웨어 래스터로 고정, 4회 연속 360/360 바이트 동일.
#   2) ffmpeg/x264가 고정 설정으로 인코드하고 audio/mix-ko.wav를 AAC로 붙인다(같은 PNG → 같은 mp4, 바이트 동일 확인).
# HyperFrames mp4 직출력은 프레임이 한 장만 달라도 GOP(250f) 끝까지 차이가 번져 원인 추적이 어려워서 나눴다.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-"$root/dist/ads/threads/t5-broadcast-v-ko.mp4"}
seq="$here/renders/seq"                     # renders/ 는 .gitignore
export HYPERFRAMES_NO_TELEMETRY=1
cd "$here"
rm -rf "$seq"; mkdir -p "$(dirname "$out")" "$here/renders"
npx hyperframes render "$here" -c vertical.html --output "$seq" --format png-sequence --workers 1 --no-browser-gpu --experimental-fast-capture=false --quiet
ffmpeg -v error -y -framerate 30 -start_number 1 -i "$seq/frame_%06d.png" -i "$here/audio/mix-ko.wav" \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -profile:v high -c:a aac -b:a 192k -ar 48000 \
  -t 12 -movflags +faststart "$out"
echo "$out"
