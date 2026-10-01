#!/usr/bin/env python3
"""구간 추출: 스크래치 원본(<raw>/<run>/) → dist/cap/ad/30s/<scene>/ (알파 PNG 연번 + times.txt + game.log + segment.json)

  python3 extract.py <rawdir> [scene ...]

- 원본 프레임은 SCK가 가끔 3844×2164(우·하단 빈 4px)를 준다 → (0,0,3840,2160)으로 정규화한 뒤 세로 밴드만 자른다.
- times.txt 각 줄: <스트림 기준 초> <벽시계> <원본 프레임 번호>  (로그의 벽시계·리그 시각과 맞추는 근거)
- 구간은 편집 여유(앞뒤 0.3~1초)를 둔다. 좌표 규약: 2x px, box는 pt(1920×1080 기준)."""
import json, os, shutil, sys
from PIL import Image

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "dist", "cap", "ad", "30s"))
# scene: (run, t0, t1, (x0, y0, x1, y1) pt, 설명)
SEG = {
    "geese-drive":   ("geese", 1.8, 7.2, (0, 480, 1920, 1080), "협곡 티샷(프로펠러캡) — 공이 협곡 바닥으로"),
    "geese":         ("geese", 8.8, 13.6, (0, 480, 1920, 1080), "거위 다섯 줄지어 내려와 둘째가 공 위에 앉음 → 흩어져 날아감 + 알"),
    "geese-close":   ("geese", 24.4, 30.9, (0, 480, 1920, 1080), "(보조) 협곡 바닥 스틱맨 곁으로 거위가 다가옴 — 캡처 끝에서 끊김"),
    "cascade-drive": ("dog", 1.8, 7.2, (0, 480, 1920, 1080), "폭포 티샷(실크햇, 미러 홀) — 계단 위로 긴 호 → 연못 입수·파문"),
    "dog":           ("dog", 18.4, 26.6, (0, 480, 1920, 1080), "강아지가 뛰어와 공을 물고 달아나 떨어뜨림 → 앉아 꼬리 → 스틱맨 곁을 지나 퇴장"),
    "ridge":         ("gallery", 12.4, 21.2, (0, 480, 1920, 1080), "능선 급사면 라이에서 언덕 너머로 드라이브, 뒤에 갤러리 넷(작다) → 박수"),
    "holeout":       ("holeout", 1.6, 7.4, (0, 360, 1920, 1080), "산정 그린 7m 퍼트 → 컵인(게임 토스트 '홀인원!' 3.26~5.11초) → 공 줍기 의식(왕관)"),
    "sprinkler":     ("holeout", 8.6, 14.2, (0, 360, 1920, 1080), "(보조) 파3 절벽 티 역방향 7I — 스프링클러 물줄기 속으로(자연 발생)"),
    "terraces-drive":("memes", 1.8, 8.4, (0, 480, 1920, 1080), "계단 대지 풀파워 드라이브(밀짚모자) — 계단 위로 긴 호"),
    "whiffspin":     ("memes", 11.6, 17.0, (0, 480, 1920, 1080), "쇼피스 whiffSpin — 헛스윙 휘릭 + 아무렇지 않게 잔댄스"),
    "cuckoo":        ("cuckoo", 1.2, 6.8, (0, 0, 1920, 1080), "3시 정각 뻐꾸기 시계가 화면 위에서 내려와 세 번 → 아래 띠에서 드라이브(왕관)"),
    # ── 2단계 (2026-10-01) 왕관 통일 재촬영 ──
    "terraces-crown":("terraces-crown", 1.8, 8.6, (0, 480, 1920, 1080), "R7 계단 대지 풀파워 드라이브(왕관) — M1"),
    "dog-crown":     ("dog-crown", 19.2, 25.9, (0, 480, 1920, 1080), "R8 강아지가 스틱맨 곁으로 들어와 공을 물고 홀 쪽으로 6m 옮겨 떨굼 → 앉아 꼬리 → 왼쪽 퇴장(왕관) — M3"),
}

def run(raw, scenes):
    for sc in scenes:
        run_, t0, t1, box, desc = SEG[sc]
        src = f"{raw}/{run_}"
        rows = [l.split() for l in open(f"{src}/times.txt")]
        sel = [(i, float(p), float(w)) for i, (p, w) in enumerate(rows) if t0 <= float(p) <= t1]
        dst = f"{OUT}/{sc}"
        if os.path.isdir(dst): shutil.rmtree(dst)
        os.makedirs(dst)
        bx = tuple(v * 2 for v in box)
        with open(f"{dst}/times.txt", "w") as tf:
            for k, (i, p, w) in enumerate(sel):
                im = Image.open(f"{src}/f{i:05d}.png").crop((0, 0, 3840, 2160)).crop(bx)
                im.save(f"{dst}/f{k:05d}.png", optimize=False, compress_level=6)
                tf.write(f"{p:.4f} {w:.3f} {i}\n")
        shutil.copy(f"{src}/game.log", f"{dst}/game.log")
        json.dump({"run": run_, "t0": t0, "t1": t1, "box_pt": box, "frames": len(sel), "desc": desc,
                   "check": json.load(open(f"{src}/check.json")) if os.path.exists(f"{src}/check.json") else None},
                  open(f"{dst}/segment.json", "w"), ensure_ascii=False, indent=1)
        sz = sum(os.path.getsize(f"{dst}/{f}") for f in os.listdir(dst))
        print(f"{sc:15s} {run_:8s} {t0:5.1f}–{t1:5.1f}s  {len(sel):4d} frames  {sz / 1e6:6.1f} MB")

if __name__ == "__main__":
    raw = sys.argv[1]
    run(raw, sys.argv[2:] or list(SEG))
