"""콘택트 시트: dist/ads/concepts/{onetake,fullstop,workday}-{h,v}.png → sheet.png (컨셉별 한 줄, 가로+세로)"""
import os
from PIL import Image, ImageDraw, ImageFont
D = os.path.join(os.path.dirname(__file__), "../../../dist/ads/concepts")
rows = [("A  원테이크 — 내 창 위의 한 홀", "onetake", "가로 KO · 세로 EN"),
        ("B  마침표 — 문장이 그린이 된다", "fullstop", "가로 KO · 세로 EN"),
        ("C  9시 1번 홀, 6시 9번 홀 — 하루 한 라운드", "workday", "가로 KO · 세로 EN")]
H = 720; HW = 1280; VW = 405; PAD = 40; LAB = 70
W = PAD * 3 + HW + VW
sheet = Image.new("RGB", (W, PAD + len(rows) * (LAB + H + PAD)), "#0B0C0E")
d = ImageDraw.Draw(sheet)
f1 = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 34, index=6)
f2 = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 22, index=2)
y = PAD
for title, key, note in rows:
    d.text((PAD, y + 12), title, fill="#F4F4F1", font=f1)
    d.text((PAD + HW + PAD, y + 22), note, fill="#8E8F8B", font=f2)
    y += LAB
    sheet.paste(Image.open(f"{D}/{key}-h.png").convert("RGB").resize((HW, H), Image.LANCZOS), (PAD, y))
    sheet.paste(Image.open(f"{D}/{key}-v.png").convert("RGB").resize((VW, H), Image.LANCZOS), (PAD * 2 + HW, y))
    d.rectangle((PAD - 1, y - 1, PAD + HW, y + H), outline="#2A2B30")
    d.rectangle((PAD * 2 + HW - 1, y - 1, PAD * 2 + HW + VW, y + H), outline="#2A2B30")
    y += H + PAD
sheet.save(f"{D}/sheet.png"); print(f"{D}/sheet.png", sheet.size)
