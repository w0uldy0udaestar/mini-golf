#!/bin/sh
# 본편 렌더 (결정성: 워커 1 · 스크린샷 캡처 고정 · 소프트웨어 래스터 고정(--no-browser-gpu: GPU 래스터는 부하 중 5회 중 1~2회 경로 AA가 달랐다) · 텔레메트리 끔): ./scripts/render.sh [draft|delivery] [출력 경로]
# 기본 출력: dist/ads/threads/t4-swings-v-ko.mp4 (delivery) / dist/ads/threads/draft/t4-swings-v-ko-<q>.mp4
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
q=${1:-draft}
if [ "$q" = delivery ]; then out=${2:-"$root/dist/ads/threads/t4-swings-v-ko.mp4"}; else out=${2:-"$root/dist/ads/threads/draft/t4-swings-v-ko-$q.mp4"}; fi
mkdir -p "$(dirname "$out")"
export HYPERFRAMES_NO_TELEMETRY=1
cd "$here"
npx hyperframes render "$here" -c vertical.html --output "$out" --workers 1 --quality "$q" --experimental-fast-capture=false --no-browser-gpu --quiet
echo "$out"
