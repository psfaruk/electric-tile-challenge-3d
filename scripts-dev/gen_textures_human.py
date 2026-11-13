#!/usr/bin/env python3
"""Generate original micro-detail textures for the human character GLB
(skin pores / knit fabric / leather / hair strands). These are multiplied
against the material base colors inside the GLB (albedo×factor), so they
are authored near-white / neutral. Deterministic, tileable, pure numpy+zlib
(no PIL) — same pipeline conventions as gen_textures.py / gen_textures_pbr.py.

Run from repo root:  python3 scripts-dev/gen_textures_human.py
"""
import os
import struct
import zlib

import numpy as np

SR = 2  # supersample
OUT = "assets/textures/character"
os.makedirs(OUT, exist_ok=True)


def write_png(path, arr):
    """arr: (h, w, 3) uint8."""
    h, w, ch = arr.shape
    assert ch == 3
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))
    crc = zlib.crc32

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", crc(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print(f"  wrote {path}  {w}x{h}  {len(png)} bytes")


def periodic_noise(w, h, scale, seed, lo=0.0, hi=1.0):
    """Value noise on a wrapped lattice — exactly tileable."""
    assert w % scale == 0 and h % scale == 0, "scale must divide dims"
    rng = np.random.default_rng(seed)
    small = rng.uniform(lo, hi, (h // scale, w // scale, 1))
    return np.repeat(np.repeat(small, scale, 0), scale, 1)


def down(img01, w, h):
    squeeze = False
    if img01.ndim == 2:  # grayscale heightfield -> temporary channel axis
        img01 = img01[..., None]
        squeeze = True
    if SR > 1:
        img01 = img01.reshape(h, SR, w, SR, img01.shape[-1]).mean(axis=(1, 3))
    return img01[..., 0] if squeeze else img01


def as_rgb(x, h, w):
    """Accept (H,W) or (H,W,1) grayscale -> clean (H,W,3) RGB array."""
    a = np.asarray(x, dtype=float)
    if a.ndim == 3 and a.shape[-1] == 1:
        a = a[..., 0]
    assert a.ndim == 2 and a.shape == (h * SR, w * SR), f"bad shape {a.shape}"
    return np.repeat(a[..., None], 3, axis=-1)


def emit(path, img01, w, h):
    arr = (np.clip(img01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    write_png(path, arr)


def normal_png(path, hgt, strength, w, h):
    """Heightfield -> tangent-space normal (OpenGL/Godot convention).
    nx = -dhdx, ny = +dhdy (y-down rows), wrapped central differences.
    Flat input must yield exactly (128,128,255)."""
    dhdx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    dhdy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5
    nx = -dhdx * strength
    ny = dhdy * strength
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    assert np.all(np.abs(n - np.array([0.0, 0.0, 1.0])) < 1e-6) if hgt.std() < 1e-12 else True
    emit(path, n * 0.5 + 0.5, w, h)


def coords(w, h):
    yy, xx = np.mgrid[0:h * SR, 0:w * SR].astype(float)
    return xx / SR, yy / SR  # image-space, y increases downward


# ---------------------------------------------------------------- skin ------
def gen_skin():
    print("skin_detail.png + normal")
    w = h = 256
    ss = h * SR, w * SR
    # very light neutral base with warm micro-mottle (multiplies with skin tone)
    base = 0.955
    mottle = periodic_noise(ss[1], ss[0], 8, 41, -0.018, 0.018)[..., 0] \
        + 0.5 * periodic_noise(ss[1], ss[0], 32, 42, -0.012, 0.012)[..., 0]
    # pore speckle (gentle)
    rng = np.random.default_rng(43)
    pores = (rng.random(ss) > 0.995).astype(float)
    try:
        from scipy import ndimage
        pores = ndimage.uniform_filter(pores, size=5)
    except Exception:
        pass
    albedo = np.clip(base + mottle - pores * 0.05, 0.0, 1.0)
    emit(f"{OUT}/skin_detail.png", down(as_rgb(albedo, h, w), w, h), w, h)
    # normal from pores + mottle height
    hgt = pores * 0.7 + mottle * 0.3
    normal_png(f"{OUT}/skin_detail_normal.png", down(hgt, w, h), 6.0, w, h)


# -------------------------------------------------------------- fabric -----
def gen_fabric():
    print("fabric_weave.png + normal")
    w = h = 256
    px, py = coords(w, h)
    P = 16.0  # weave period (px) — 256/16 tiles exactly
    # warp/weft interlace: ridges alternate direction per half-period cell
    cellx = np.floor(px / (P / 2)) % 2
    celly = np.floor(py / (P / 2)) % 2
    horiz = (cellx == celly)  # checker of half-period cells
    h_yy = np.sin(2.0 * np.pi * py / (P / 2))        # thread ridges along x cells
    h_xx = np.sin(2.0 * np.pi * px / (P / 2))        # thread ridges along y cells
    hgt = np.where(horiz, h_yy, h_xx) * 0.5 + 0.5
    # per-thread brightness variation + fuzz
    ss = h * SR, w * SR
    rng = np.random.default_rng(52)
    fuzz = np.repeat(np.repeat((rng.random((h // 32, w // 32, 1)) - 0.5) * 0.05, 32 * SR, 0), 32 * SR, 1)[..., 0]
    thread_var = 0.04 * np.sin(2.0 * np.pi * (px + py) / (P * 4.0))
    albedo = np.clip(0.90 + 0.08 * (hgt - 0.5) + fuzz + thread_var, 0.0, 1.0)[..., None] * np.ones((1, 1, 3))
    emit(f"{OUT}/fabric_weave.png", down(albedo, w, h), w, h)
    normal_png(f"{OUT}/fabric_weave_normal.png", down(hgt, w, h), 3.5, w, h)


# ------------------------------------------------------------- leather -----
def gen_leather():
    print("leather_shoe.png + normal")
    w = h = 256
    ss = h * SR, w * SR
    # pebble grain: two octaves of wrapped value noise, thresholded into cells
    n1 = periodic_noise(ss[1], ss[0], 16, 61)[..., 0]
    n2 = 0.5 * periodic_noise(ss[1], ss[0], 32, 62)[..., 0]
    grain = n1 + n2
    creases = np.clip(0.5 - np.abs(grain - 0.5) * 4.0, 0.0, 1.0)  # valleys at cell borders
    albedo = np.clip(0.80 + 0.12 * (grain - 0.5) - creases * 0.18, 0.0, 1.0)
    emit(f"{OUT}/leather_shoe.png", down(as_rgb(albedo, h, w), w, h), w, h)
    hgt = grain - creases * 0.5
    normal_png(f"{OUT}/leather_shoe_normal.png", down(hgt, w, h), 2.5, w, h)


# ---------------------------------------------------------------- hair -----
def gen_hair():
    print("hair_strand_normal.png")
    w = h = 256
    px, py = coords(w, h)
    # fine vertical strands (y direction), slight diagonal drift, tileable period 6px
    drift = 6.0 * np.sin(2.0 * np.pi * py / h)  # wraps at edge -> tileable
    hgt = np.sin(2.0 * np.pi * (px + drift) / 6.0)
    rng = np.random.default_rng(71)
    hgt = hgt * (0.85 + 0.3 * np.repeat(np.repeat(rng.random((h // 16, w // 16, 1)), 16 * SR, 0), 16 * SR, 1)[..., 0])
    normal_png(f"{OUT}/hair_strand_normal.png", down(hgt, w, h), 2.2, w, h)


# ------------------------------------------------------- tinted variants ----
# Base colors copied from the source blend's legacy diffuse materials
# (Male_Casual.blend, CC0) so the baked albedo exactly preserves the
# author's palette; detail textures multiply them in sRGB space.
BLEND_COLORS = {
    "Skin": (0.4969, 0.3185, 0.1662),
    "Eyes": (0.0254, 0.0254, 0.0254),
    "Hair": (0.0522, 0.0350, 0.0360),
    "Shirt": (0.1634, 0.2139, 0.2330),
    "Pants": (0.0607, 0.0529, 0.0529),
    "Socks": (0.5071, 0.4348, 0.4348),
    "Shoes": (0.0254, 0.0254, 0.0254),
}

# material -> (detail albedo texture, roughness for the Godot material later)
TINT_MAP = {
    "Skin": "skin_detail.png",
    "Hair": "skin_detail.png",      # fine grain reads as hair scalp under dark tint
    "Shirt": "fabric_weave.png",
    "Pants": "fabric_weave.png",
    "Socks": "fabric_weave.png",
    "Shoes": "leather_shoe.png",
}


def _read_png_rgb(path):
    """Minimal PNG reader for RGB8 (no PIL): parse IHDR + first IDAT."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    w = h = None
    idat = b""
    while pos < len(data):
        ln, = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", chunk[:10])
            assert depth == 8 and ctype == 2, f"unexpected PNG format in {path}"
        elif tag == b"IDAT":
            idat += chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    rows = np.frombuffer(raw, dtype=np.uint8).reshape(h, 1 + w * 3)[:, 1:].reshape(h, w, 3)
    return rows.astype(float) / 255.0


def gen_tinted():
    print("tinted per-material albedos")
    os.makedirs(f"{OUT}/tinted", exist_ok=True)
    cache = {}
    for mat, tex_name in TINT_MAP.items():
        if tex_name not in cache:
            cache[tex_name] = _read_png_rgb(f"{OUT}/{tex_name}")
        tex = cache[tex_name]
        col = np.array(BLEND_COLORS[mat])
        img = np.clip(tex * col[None, None, :], 0.0, 1.0)
        arr = (img * 255.0 + 0.5).astype(np.uint8)
        write_png(f"{OUT}/tinted/{mat}_albedo.png", arr)


if __name__ == "__main__":
    gen_skin()
    gen_fabric()
    gen_leather()
    gen_hair()
    gen_tinted()
    print("HUMAN TEXTURES: ALL GENERATED OK")
