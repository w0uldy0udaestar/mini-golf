#!/usr/bin/env bash
# 빠른 프레임 미리보기 (헤드리스 Chrome, 렌더러 없이): preview.sh <초...> → $OUT/p-<t>.png
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$HERE/../../dist/ads/threads/preview}"; mkdir -p "$OUT"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for t in "$@"; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 \
    --virtual-time-budget=4000 --window-size=1080,1920 --screenshot="$OUT/p-$t.png" "file://$HERE/vertical.html?t=$t" 2>/dev/null &
done
wait
