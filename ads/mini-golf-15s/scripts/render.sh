#!/bin/sh
# 본편 렌더 (결정성: 워커 1 · 스크린샷 캡처 고정 · #desk will-change 없음 — qa-report 7장): ./scripts/render.sh [draft|delivery] [h-ko h-en v-ko v-en ...]  (기본: 4편)
# → dist/ads/final/mini-golf-15s-<o>-<lang>.mp4 (delivery) / dist/ads/final/draft/…-draft.mp4 (draft)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
q=${1:-draft}; shift || true
list=${*:-"h-ko h-en v-ko v-en"}
export HYPERFRAMES_NO_TELEMETRY=1
cd "$here"
for v in $list; do
  o=${v%-*}; lang=${v#*-}
  if [ "$o" = h ]; then comp=index.html; else comp=vertical.html; fi
  if [ "$q" = delivery ]; then out="$root/dist/ads/final/mini-golf-15s-$o-$lang.mp4"; else mkdir -p "$root/dist/ads/final/draft"; out="$root/dist/ads/final/draft/mini-golf-15s-$o-$lang-$q.mp4"; fi
  mkdir -p "$(dirname "$out")"
  npx hyperframes render "$here" -c "$comp" --output "$out" --workers 1 --quality "$q" --experimental-fast-capture=false \
    --variables "{\"lang\":\"$lang\",\"mix\":\"audio/mix-$lang.wav\"}" --quiet
  echo "$out"
done
