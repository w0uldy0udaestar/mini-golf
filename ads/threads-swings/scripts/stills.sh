#!/bin/sh
# 빠른 스틸 미리보기 (렌더 전 구도 확인): ./scripts/stills.sh OUTDIR f1 f2 ...  → OUTDIR/f<N>.png (헤드리스 Chrome, ?t=)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
out=$1; shift; mkdir -p "$out"
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for f in "$@"; do
  t=$(python3 -c "print($f/30)")
  "$CH" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 \
    --virtual-time-budget=8000 --window-size=1080,1920 --screenshot="$out/f$f.png" "file://$here/vertical.html?t=$t" >/dev/null 2>&1
done
python3 - "$out" "$@" <<'EOF'
import sys
from PIL import Image, ImageDraw
out, fs = sys.argv[1], sys.argv[2:]
W, H = 270, 480
cols = min(len(fs), 8); rows = (len(fs) + cols - 1) // cols
sh = Image.new("RGB", (cols * W, rows * (H + 20)), "#000"); d = ImageDraw.Draw(sh)
for k, f in enumerate(fs):
    im = Image.open(f"{out}/f{f}.png").convert("RGB").resize((W, H), Image.LANCZOS)
    r, c = divmod(k, cols); sh.paste(im, (c * W, r * (H + 20) + 20)); d.text((c * W + 4, r * (H + 20) + 4), f"f{f} {int(f)/30:.2f}s", fill="#ddd")
sh.save(f"{out}/sheet.png"); print(f"{out}/sheet.png")
EOF
