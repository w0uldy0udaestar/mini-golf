#!/bin/sh
# 렌더 (결정성): ./scripts/render.sh [출력 경로]  → 기본 dist/ads/threads/t3-meeting-v-ko.mp4
#  1) HyperFrames로 PNG 연번을 뽑는다(워커 1 · 스크린샷 캡처 · 소프트웨어 래스터 --no-browser-gpu) — 두 번 렌더한 PNG 435장 md5가 같음을 확인했다
#  2) ffmpeg libx264 단일 스레드 + bitexact로 묶는다 — HyperFrames 내장 mp4 인코딩은 같은 프레임에서도 실행마다 비트가 달랐다(GOP 1 소량)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-"$root/dist/ads/threads/t3-meeting-v-ko.mp4"}
export HYPERFRAMES_NO_TELEMETRY=1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/t3png.XXXXXX")
mkdir -p "$(dirname "$out")"
cd "$here"
npx hyperframes render "$here" -c vertical.html --format png-sequence --output "$tmp/png" --workers 1 --experimental-fast-capture=false --no-browser-gpu --quiet
ffmpeg -v error -y -framerate 30 -i "$tmp/png/frame_%06d.png" -c:v libx264 -preset slow -crf 16 -threads 1 -pix_fmt yuv420p -profile:v high \
  -movflags +faststart -fflags +bitexact -flags:v +bitexact "$out"
rm -rf "$tmp"
echo "$out"
