#!/bin/sh
# 본편 렌더 (결정성: 워커 1 · 스크린샷 캡처 고정 · will-change 없음 — 15초판 qa-report 7장 교훈 그대로)
#   + 소프트웨어 래스터(--no-browser-gpu): 하드웨어 GPU(Metal) 래스터는 카메라 줌 구간(f47 등)의 타일이 실행마다 달랐다(2단계 실측, 3회 중 2가지 결과).
#   ./scripts/render.sh [draft|delivery] [h-ko h-en v-ko v-en ...]  (기본: h-ko)
# → dist/ads/30s/draft/mini-golf-30s-<o>-<lang>-draft.mp4 (draft) / dist/ads/30s/final/mini-golf-30s-<o>-<lang>.mp4 (delivery)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/../.." && pwd)
q=${1:-draft}; shift || true
list=${*:-"h-ko"}
export HYPERFRAMES_NO_TELEMETRY=1
cd "$here"
for v in $list; do
  o=${v%-*}; lang=${v#*-}
  if [ "$o" = h ]; then comp=index.html; else comp=vertical.html; fi
  if [ "$q" = delivery ]; then out="$root/dist/ads/30s/final/mini-golf-30s-$o-$lang.mp4"; else out="$root/dist/ads/30s/draft/mini-golf-30s-$o-$lang-$q.mp4"; fi
  mkdir -p "$(dirname "$out")"
  npx hyperframes render "$here" -c "$comp" --output "$out" --workers 1 --quality "$q" --experimental-fast-capture=false --no-browser-gpu \
    --variables "{\"lang\":\"$lang\",\"mix\":\"audio/mix-$lang.wav\"}" --quiet
  echo "$out"
done
