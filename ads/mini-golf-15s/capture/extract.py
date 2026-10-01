"""키포즈 추출: 스크래치 원본(raw)에서 골라 dist/cap/ad/에 알파 PNG로 저장 + manifest.json.
crop 항목은 스틱맨 주변 영역(pt)을 잘라 저장하고, 원본 전체 프레임(3840×2160 px, 2x) 기준 좌상단 위치를 기록한다."""
import json, os, sys
from PIL import Image
RAW, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

def frame_at(tag, wall=None, idx=None):
    if idx is None:
        ts = [float(l.split()[1]) for l in open(f"{RAW}/{tag}/times.txt")]
        idx = min(range(len(ts)), key=lambda j: abs(ts[j] - wall))
    im = Image.open(f"{RAW}/{tag}/f{idx:05d}.png")
    return idx, im.crop((0, 0, 3840, 2160))  # SCK가 가끔 3844×2164(우·하단 빈 4px)를 준다 — 내용은 좌상단 기준이라 잘라 정규화

# (이름, 태그, 프레임, 크롭(cx_pt, gy_pt, w_pt, h_pt) 또는 None=전체, 설명)
ITEMS = [
    ("swing-address", "hero-drive", {"wall": 1790669760.95}, (150, 220, 220, 200), "드라이버 어드레스 (DR·100 조준 라벨 포함)"),
    ("swing-top", "hero-drive", {"idx": 60}, (150, 220, 220, 200), "톱 — 풀파워 오버스윙"),
    ("swing-down", "hero-drive", {"idx": 72}, (150, 220, 220, 200), "다운스윙"),
    ("swing-impact", "hero-drive", {"idx": 73}, (150, 220, 220, 200), "임팩트 (공 출발 + 스윙 호 잔상)"),
    ("swing-follow", "hero-drive", {"idx": 78}, (150, 220, 220, 200), "팔로스루"),
    ("swing-finish", "hero-drive", {"idx": 81}, (150, 220, 220, 200), "피니시"),
    ("swing-twirl", "hero-drive", {"idx": 86}, (150, 220, 220, 200), "트레이드마크 — 굿샷 트월 후 클럽 어깨 걸침"),
    ("walk-a", "hero-drive", {"wall": 1790669772.00}, None, "걷기(평지) 1"),
    ("walk-b", "hero-drive", {"wall": 1790669772.17}, None, "걷기(평지) 2"),
    ("walk-c", "hero-drive", {"wall": 1790669772.33}, None, "걷기(평지) 3"),
    ("walk-d", "hero-drive", {"wall": 1790669772.50}, None, "걷기(평지) 4"),
    ("flight-apex-full", "hero-drive", {"idx": 122}, None, "절벽 티 드라이브 — 정점 직후, 실제 탄도 궤적"),
    ("flight-descent-full", "hero-drive", {"idx": 163}, None, "드라이브 하강 — 궤적 전체"),
    ("flight-land-full", "hero-drive", {"idx": 184}, None, "착지 순간"),
    ("motion-twirl", "motions", {"idx": 205}, None, "잔동작 twirl"),
    ("motion-helicopter", "motions", {"idx": 265}, None, "잔동작 helicopter"),
    ("putt-stroke", "pickup", {"idx": 33}, (200, 188, 160, 150), "퍼트 (PT·12)"),
    ("holed-toast", "pickup", {"idx": 93}, (200, 188, 260, 190), "홀인 토스트 '홀인원!'"),
    ("pickup-bend", "pickup", {"idx": 135}, (200, 188, 160, 150), "공 줍기 — 숙임"),
    ("pickup-raise", "pickup", {"idx": 171}, (200, 188, 160, 150), "공 줍기 — 공 들어 올림"),
    ("swing-address-full", "hero-drive", {"wall": 1790669760.95}, None, "어드레스 전체 프레임 (절벽 티 + HUD)"),
    ("swing-top-full", "hero-drive", {"idx": 60}, None, "톱 전체 프레임"),
    ("swing-impact-full", "hero-drive", {"idx": 73}, None, "임팩트 전체 프레임"),
    ("swing-follow-full", "hero-drive", {"idx": 78}, None, "팔로스루 전체 프레임 (공 출발 직후 궤적)"),
    ("putt-stroke-full", "pickup", {"idx": 33}, None, "퍼트 전체 프레임 (숲 9번 홀 그린)"),
    ("holed-toast-full", "pickup", {"idx": 93}, None, "홀인 토스트 전체 프레임"),
    ("pickup-raise-full", "pickup", {"idx": 171}, None, "공 들어 올림 전체 프레임"),
    ("geese-line-full", "geese", {"idx": 92}, None, "서프라이즈 거위 떼 — '거위?' 말풍선"),
    ("geese-cross-full", "geese", {"idx": 152}, None, "거위 떼가 공 쪽으로"),
    ("terrain-terraces", "terrain-s1-h1", {"idx": 8}, None, "계단 대지 (seed1 h1 파5)"),
    ("terrain-cascade", "terrain-s1-h2", {"idx": 8}, None, "폭포 (seed1 h2 파4)"),
    ("terrain-canyon", "terrain-s1-h3", {"idx": 8}, None, "협곡 (seed1 h3 파4)"),
    ("terrain-skytee", "terrain-s2-h3", {"idx": 8}, None, "절벽 티 (seed2 h3 파5)"),
    ("terrain-ridge", "terrain-s1-h5", {"idx": 8}, None, "능선 (seed1 h5 파4)"),
    ("terrain-summit", "terrain-s1-h7", {"idx": 8}, None, "산정 그린 (seed1 h7 파4)"),
    ("terrain-forest", "terrain-s1-h9", {"idx": 8}, None, "숲 (seed1 h9 파4)"),
    ("terrain-valley", "terrain-s2-h4", {"idx": 8}, None, "계곡 (seed2 h4 파5)"),
]
man = {}
for name, tag, sel, crop, desc in ITEMS:
    idx, im = frame_at(tag, **sel)
    W, H = im.size; sc = W / 1920
    if crop:
        cx, gy, w, h = crop
        box = (int((cx - w / 2) * sc), int(H - (gy + h * 0.72) * sc), int((cx + w / 2) * sc), int(H - (gy - h * 0.28) * sc))
        im = im.crop(box)
        origin = box[:2]
    else:
        origin = (0, 0)
    im.save(f"{OUT}/{name}.png", optimize=True)
    bb = im.getchannel("A").getbbox()
    man[name] = {"src": f"{tag}/f{idx:05d}", "origin_px": origin, "size_px": im.size, "alpha_bbox": bb, "desc": desc}
    print(name, tag, idx, im.size, bb)
json.dump(man, open(f"{OUT}/manifest.json", "w"), ensure_ascii=False, indent=1)
