#!/bin/sh
# T2 화산 렌더: ./scripts/render.sh [draft|standard|high] [출력 경로]
# 결정성: 워커 1 · 스크린샷 캡처 고정(--experimental-fast-capture=false) · 소프트웨어 래스터(--no-browser-gpu: ×9.75 근접에서 GPU 래스터가 렌더마다 달랐다) · 텔레메트리 끔
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
q=${1:-draft}
out=${2:-"$root/dist/ads/threads/t2-volcano-v-ko.mp4"}
export HYPERFRAMES_NO_TELEMETRY=1
mkdir -p "$(dirname "$out")"
cd "$here"
npx hyperframes render "$here" -c vertical.html --output "$out" --workers 1 --quality "$q" --experimental-fast-capture=false --no-browser-gpu --quiet
echo "$out"
