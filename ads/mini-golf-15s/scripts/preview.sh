#!/usr/bin/env bash
# 빠른 프레임 미리보기 (헤드리스 Chrome, 렌더러 없이): preview.sh <h|v> <ko|en> <초...> → $OUT/p-<o>-<lang>-<t>.png
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; o=$1; lang=$2; shift 2
OUT="${OUT:-$HERE/../../dist/ads/final/preview}"; mkdir -p "$OUT"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ "$o" = h ]; then size=1920,1080; page=index.html; else size=1080,1920; page=vertical.html; fi
for t in "$@"; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 \
    --virtual-time-budget=4000 --window-size="$size" --screenshot="$OUT/p-$o-$lang-$t.png" "file://$HERE/$page?lang=$lang&t=$t" 2>/dev/null
done
