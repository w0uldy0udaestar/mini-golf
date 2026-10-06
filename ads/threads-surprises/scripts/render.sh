#!/bin/sh
# T1 렌더 (결정성: 워커 1 · 스크린샷 캡처 고정 · 영상층 프레임 PNG 추출): ./scripts/render.sh [draft|standard|high] [출력 경로]
# 기본 출력: dist/ads/threads/t1-surprises-v-ko.mp4 (high) / dist/ads/threads/t1-work/t1-<q>.mp4 (그 외)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
q=${1:-draft}
if [ "$q" = high ]; then out=${2:-"$root/dist/ads/threads/t1-surprises-v-ko.mp4"}; else out=${2:-"$root/dist/ads/threads/t1-work/t1-$q.mp4"}; fi
mkdir -p "$(dirname "$out")"
export HYPERFRAMES_NO_TELEMETRY=1
cd "$here"
npx hyperframes render "$here" -c vertical.html --output "$out" --workers 1 --quality "$q" --experimental-fast-capture=false \
  --video-frame-format png --quiet
echo "$out"
