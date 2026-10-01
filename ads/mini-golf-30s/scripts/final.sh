#!/bin/sh
# 최종 4편 delivery 렌더 + 결정성 확인(같은 설정 2회 → MD5 비교). 사용: ./scripts/final.sh [h-ko h-en v-ko v-en]
set -e
here=$(cd "$(dirname "$0")/.." && pwd); root=$(cd "$here/../.." && pwd)
list=${*:-"h-ko h-en v-ko v-en"}
out="$root/dist/ads/30s/final"; mkdir -p "$out"
: > "$out/md5.txt"
for v in $list; do
  "$here/scripts/render.sh" delivery "$v" > /dev/null 2>&1
  a=$(md5 -q "$out/mini-golf-30s-$v.mp4")
  cp "$out/mini-golf-30s-$v.mp4" "$out/.first-$v.mp4"
  "$here/scripts/render.sh" delivery "$v" > /dev/null 2>&1
  b=$(md5 -q "$out/mini-golf-30s-$v.mp4")
  rm -f "$out/.first-$v.mp4"
  if [ "$a" = "$b" ]; then s=same; else s=DIFF; fi
  echo "$v $a $b $s" | tee -a "$out/md5.txt"
done
