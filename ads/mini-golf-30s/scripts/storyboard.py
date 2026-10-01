#!/usr/bin/env python3
"""스토리보드: storyboard.py <h|v> <mp4> <out.png> — 12비트(프레임·설명 캡션). 가로·세로 모두 6×2 (2단계)."""
import sys, cv2
from PIL import Image, ImageDraw, ImageFont
o, mp4, out = sys.argv[1], sys.argv[2], sys.argv[3]
BEATS = [(15, "0.5s 훅", "실제 리그 60Hz 벡터 — 1/4속 다운스윙, 왕관"), (125, "4.2s 마침표", "공이 창들 위로 날아와 문장의 마침표가 된다"),
         (180, "6.0s 매치컷", "마침표 → 문서 창 위 티의 공 (같은 자리·같은 지름)"), (285, "9.5s 거위 떼", "'거위가 공 위에 앉고,' — 펀치인 컷"),
         (375, "12.5s 강아지", "공을 물고 달아난다 (R8 재캡처, 왕관)"), (425, "14.2s 헛스윙 개그", "자막 없이 개그만 — 끝에 작은 태그"),
         (462, "15.4s 3시 정각", "메뉴바 ECU(가로 ×4.5·세로 ×5.0) — 2:59→3:00 롤"), (505, "16.8s 뻐꾸기", "시계 ECU — 새가 문 밖으로"),
         (575, "19.2s 그래도 버디", "공 줍기 의식 + 배지 토스트"), (645, "21.5s 정직 비트", "클릭이 스틱맨 다리 사이로 '보내기'"),
         (700, "23.3s 흔적 없음", "메뉴바 깃발로 종료 → 같은 자리에 스틱맨이 없다"), (899, "30.0s 끝 정지", "brew 설치 → 띠가 살아난다 · 워드마크·URL")]
cap = cv2.VideoCapture(mp4); fr = []
while True:
    ok, im = cap.read()
    if not ok: break
    fr.append(im)
if o == "h": W, H, cols = 400, 225, 6
else: W, H, cols = 216, 384, 6
CAP = 64; rows = (len(BEATS) + cols - 1) // cols; PAD = 16
font = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 15 if o == "h" else 13, index=2)
bold = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 17 if o == "h" else 14, index=6)
sheet = Image.new("RGB", (cols * (W + PAD) + PAD, rows * (H + CAP + PAD) + PAD), "#0B0C0E"); d = ImageDraw.Draw(sheet)
for k, (f, t1, t2) in enumerate(BEATS):
    r, c = divmod(k, cols); x = PAD + c * (W + PAD); y = PAD + r * (H + CAP + PAD)
    im = Image.fromarray(cv2.cvtColor(fr[f], cv2.COLOR_BGR2RGB)).resize((W, H), Image.LANCZOS)
    sheet.paste(im, (x, y)); d.rectangle((x - 1, y - 1, x + W, y + H), outline="#2A2B30")
    d.text((x, y + H + 8), f"f{f} · {t1}", fill="#F4F4F1", font=bold)
    import textwrap
    d.multiline_text((x, y + H + 30), "\n".join(textwrap.wrap(t2, 28 if o == "h" else 15)), fill="#9A9B96", font=font, spacing=3)
sheet.save(out); print(out, sheet.size)
