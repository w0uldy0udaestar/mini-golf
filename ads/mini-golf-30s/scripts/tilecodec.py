"""타일 코덱 — 알파 캡처 연번 PNG를 '정지 판 1장 + 바뀐 32px 타일 아틀라스'로 압축한다 (브라우저 디코드 메모리 절약).

재생(src/main.js): 캔버스 = 판 → 프레임의 타일마다 clearRect(타일) + drawImage(아틀라스 조각). 판과 같은 타일은 저장하지 않는다.
타일은 장면 안에서 해시로 중복 제거한다(한 번 그려진 궤적 선 같은 타일은 한 번만). 비교는 프리멀티플라이드 RGBA(완전 투명 화소의 쓰레기 RGB 무시).
"""
import hashlib, os
import numpy as np
from PIL import Image

T = 32

def load(p):
    return np.array(Image.open(p).convert("RGBA"))

def premul(a):
    f = a.astype(np.int32)
    return np.concatenate([f[..., :3] * f[..., 3:4] // 255, f[..., 3:4]], axis=-1)

def encode(frames, out_prefix, tol=2, atlas_w=2048, crop=None, sample=31):
    """frames: [(label, path)] → 판 png, 아틀라스 png들, 인덱스(dict). crop=(x0,y0,x1,y1) px(원본 프레임 기준)로 잘라 쓴다.
    판은 균등 표본 최대 31장의 화소별 중앙값(메모리 절약), 타일 추출은 한 장씩 흘려 읽는다."""
    def get(p):
        a = load(p)
        return a[crop[1]:crop[3], crop[0]:crop[2]] if crop else a
    first = get(frames[0][1]); H, W = first.shape[:2]
    H2, W2 = (H + T - 1) // T * T, (W + T - 1) // T * T
    pad = lambda a: np.pad(a, ((0, H2 - a.shape[0]), (0, W2 - a.shape[1]), (0, 0)))
    pick = sorted(set(int(round(i)) for i in np.linspace(0, len(frames) - 1, min(sample, len(frames)))))
    plate = np.median(np.stack([pad(get(frames[i][1])) for i in pick]), axis=0).astype(np.uint8)
    ppm = premul(plate)
    ny, nx = H2 // T, W2 // T
    uniq = {}; tiles = []; index = []
    for label, path in frames:
        a = pad(get(path)); pm = premul(a)
        d = np.abs(pm - ppm).max(axis=-1)
        dt = d.reshape(ny, T, nx, T).max(axis=(1, 3))
        refs = []
        for ty, tx in zip(*np.nonzero(dt > tol)):
            blk = a[ty * T:(ty + 1) * T, tx * T:(tx + 1) * T]
            h = hashlib.blake2b(blk.tobytes(), digest_size=12).digest()
            if h not in uniq:
                uniq[h] = len(tiles); tiles.append(blk)
            refs.append([int(tx), int(ty), uniq[h]])
        index.append({"t": label, "tiles": refs})
    per_row = atlas_w // T
    per_atlas = per_row * per_row
    atlases = []
    for ai in range(0, max(1, len(tiles)), per_atlas):
        chunk = tiles[ai:ai + per_atlas]
        rows = (len(chunk) + per_row - 1) // per_row
        at = np.zeros((max(1, rows) * T, atlas_w, 4), np.uint8)
        for k, blk in enumerate(chunk):
            r, c = divmod(k, per_row); at[r * T:(r + 1) * T, c * T:(c + 1) * T] = blk
        name = f"{out_prefix}-atlas{len(atlases)}.png"
        Image.fromarray(at, "RGBA").save(name, optimize=True); atlases.append(os.path.basename(name))
    Image.fromarray(plate[:H, :W], "RGBA").save(f"{out_prefix}-plate.png", optimize=True)
    return {"w": W, "h": H, "tile": T, "perRow": per_row, "perAtlas": per_atlas, "plate": os.path.basename(f"{out_prefix}-plate.png"),
            "atlases": atlases, "frames": index, "uniqueTiles": len(tiles),
            "avgTiles": round(sum(len(f["tiles"]) for f in index) / max(1, len(index)), 1)}

def decode_check(meta, gen_dir, frames, k, crop=None):
    """검증: k번째 프레임을 인덱스로 복원해 원본과 비교 (최대 차)."""
    plate = np.array(Image.open(f"{gen_dir}/{meta['plate']}").convert("RGBA"))
    ats = [np.array(Image.open(f"{gen_dir}/{n}").convert("RGBA")) for n in meta["atlases"]]
    out = plate.copy(); T_ = meta["tile"]; H, W = out.shape[:2]
    for tx, ty, u in meta["frames"][k]["tiles"]:
        ai, j = divmod(u, meta["perAtlas"]); r, c = divmod(j, meta["perRow"])
        blk = ats[ai][r * T_:(r + 1) * T_, c * T_:(c + 1) * T_]
        y0, x0 = ty * T_, tx * T_; hh, ww = min(T_, H - y0), min(T_, W - x0)
        out[y0:y0 + hh, x0:x0 + ww] = blk[:hh, :ww]
    ref = load(frames[k][1])
    if crop: ref = ref[crop[1]:crop[3], crop[0]:crop[2]]
    return int(np.abs(premul(out).astype(int) - premul(ref).astype(int)).max())
