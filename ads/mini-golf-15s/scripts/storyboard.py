#!/usr/bin/env python3
"""스토리보드: storyboard.py <h|v> → dist/ads/final/sheets/storyboard-<o>.png (6비트 × 한·영 두 줄, 비트 설명 캡션)"""
import sys, cv2
from PIL import Image, ImageDraw, ImageFont
o = sys.argv[1]; F = "/Users/universe/Project/mini-golf/dist/ads/final"
BEATS = [(0, "0.00 훅 — 에디터 아래 띠, 톱(실캡처)"), (11, "0.37 임팩트 — 공이 코드 위로"), (75, "2.50 풀백 뒤 — 메모에 타이핑, 공 비행"),
         (112, "3.73 공 = 마침표"), (250, "8.33 클릭이 띠를 지나 '실행'으로"), (420, "14.0 엔드카드 — 끝 정지")]
W = 480 if o == "h" else 270; H = 270 if o == "h" else 480; CAP = 46 if o == "h" else 70
font = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 17, index=2)
bold = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 20, index=6)
sheet = Image.new("RGB", (W * 6 + 80, (H + CAP) * 2 + 20), "#0B0C0E"); d = ImageDraw.Draw(sheet)
for r, lang in enumerate(["ko", "en"]):
    cap = cv2.VideoCapture(f"{F}/mini-golf-15s-{o}-{lang}.mp4"); fr = []
    while True:
        ok, im = cap.read()
        if not ok: break
        fr.append(im)
    y = 10 + r * (H + CAP)
    d.text((14, y + H // 2 - 10), lang.upper(), fill="#F4F4F1", font=bold)
    for c, (f, txt) in enumerate(BEATS):
        im = Image.fromarray(cv2.cvtColor(fr[f], cv2.COLOR_BGR2RGB)).resize((W, H), Image.LANCZOS)
        sheet.paste(im, (70 + c * W, y)); lab = f"f{f} · {txt}" if o == "h" else f"f{f} · " + txt.replace(" — ", "\n")
        d.multiline_text((74 + c * W, y + H + 8), lab, fill="#B7B8B3", font=font, spacing=4)
sheet.save(f"{F}/sheets/storyboard-{o}.png"); print(f"{F}/sheets/storyboard-{o}.png", sheet.size)
