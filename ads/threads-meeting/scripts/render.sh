#!/bin/sh
# 렌더 (결정성: 워커 1 · 스크린샷 캡처 고정): ./scripts/render.sh [draft|standard|high] [출력 경로]
# 기본 → dist/ads/threads/t3-meeting-v-ko.mp4
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
q=${1:-standard}
out=${2:-"$root/dist/ads/threads/t3-meeting-v-ko.mp4"}
export HYPERFRAMES_NO_TELEMETRY=1
mkdir -p "$(dirname "$out")"
cd "$here"
npx hyperframes render "$here" -c vertical.html --output "$out" --workers 1 --quality "$q" --experimental-fast-capture=false --quiet
echo "$out"
