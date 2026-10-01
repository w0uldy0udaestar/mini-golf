#!/usr/bin/env bash
# 컨셉 시안 스틸 렌더 (헤드리스 Chrome) → dist/ads/concepts/<concept>-{h,v}.png
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "$HERE/../.." && pwd)/dist/ads/concepts"; mkdir -p "$OUT"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
names=(A:onetake B:fullstop C:workday)
for n in "${names[@]}"; do
  k="${n%%:*}"; name="${n#*:}"
  for o in h v; do
    if [ "$o" = h ]; then size=1920,1080; else size=1080,1920; fi
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 \
      --virtual-time-budget=4000 --window-size="$size" --screenshot="$OUT/$name-$o.png" "file://$HERE/stills/stills.html#$k-$o" 2>/dev/null
    echo "$OUT/$name-$o.png"
  done
done
