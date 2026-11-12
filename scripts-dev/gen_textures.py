#!/usr/bin/env python3
"""Generate all original procedural textures for Electric Tile Challenge 3D.
Pure numpy + zlib PNG writer (no PIL). Deterministic. Run from repo root:
    python3 scripts-dev/gen_textures.py
"""
import os
import struct
import zlib

import numpy as np

SR = 2  # supersample factor (2x keeps generation fast, smooths edges via sdfs)

OUT = "assets/textures"
os.makedirs(OUT, exist_ok=True)


def write_png(path, arr):
    """arr: (h, w, 3) uint8."""
    h, w, ch = arr.shape
    assert ch == 3
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))
    digest = zlib.crc32

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", digest(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print(f"  wrote {path}  {w}x{h}  {len(png)} bytes")


def grid(w, h, s=SR):
    ss = w * s, h * s
    yy, xx = np.mgrid[0:ss[1], 0:ss[0]]
    return xx / s, yy / s  # design-space coords


def sd_rounded_box(px, py, cx, cy, hx, hy, r):
    qx = np.abs(px - cx) - (hx - r)
    qy = np.abs(py - cy) - (hy - r)
    ax = np.maximum(qx, 0.0)
    ay = np.maximum(qy, 0.0)
    out = np.sqrt(ax * ax + ay * ay)
    inside = np.minimum(np.maximum(qx, qy), 0.0)
    return out + inside - r


def band(sd, center, half):
    """Soft band mask around signed-distance value."""
    return np.clip(1.0 - np.abs(sd - center) / half, 0.0, 1.0)


def seg_dist(px, py, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy
    t = np.clip(((px - x0) * dx + (py - y0) * dy) / L2, 0.0, 1.0)
    cx_ = x0 + t * dx
    cy_ = y0 + t * dy
    return np.sqrt((px - cx_) ** 2 + (py - cy_) ** 2)


def save(path, img01, w, h):
    """img01: (h, w, 3) float 0..1 -> downsample (SR) -> uint8 png."""
    if SR > 1:
        img01 = img01.reshape(h, SR, w, SR, 3).mean(axis=(1, 3))
    arr = (np.clip(img01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    write_png(path, arr)


def noise_field(w, h, scale, seed, lo=0.0, hi=1.0):
    rng = np.random.default_rng(seed)
    small = rng.uniform(lo, hi, (h // scale + 2, w // scale + 2, 1))
    small = np.repeat(small, scale, 0)[:h]
    small = np.repeat(small, scale, 1)[:, :w]
    return small


def gen_tile_face():
    print("tile_face.png")
    w = h = 512
    px, py = grid(w, h)
    rng = np.random.default_rng(7)
    base = np.array([0.055, 0.078, 0.104])  # dark steel
    img = np.tile(base, (h * SR, w * SR, 1))
    img += (rng.uniform(-0.02, 0.02, (h * SR, w * SR, 1)))

    sd = sd_rounded_box(px, py, 255.5, 255.5, 241.0, 241.0, 36.0)
    # glowing border band (16 px thick, inside edge)
    border = band(sd, -8.0, 9.0)
    halo = band(sd, -30.0, 22.0) * 0.30
    border_col = np.array([0.78, 1.0, 0.95])
    halo_col = np.array([0.2, 0.75, 0.66])
    for mask, col, op in ((halo, halo_col, 1.0), (border, border_col, 1.0)):
        m = (mask * op)[..., None]
        img = img * (1 - m) + col * m

    # faint circuit traces from the center chip to the border
    traces = [
        (256, 256, 256, 60), (256, 256, 256, 452),
        (256, 256, 60, 256), (256, 256, 452, 256),
        (256, 120, 150, 120), (256, 392, 362, 392),
        (120, 256, 120, 180), (392, 256, 392, 332),
    ]
    trace_mask = np.zeros_like(px)
    for x0, y0, x1, y1 in traces:
        trace_mask = np.maximum(trace_mask, np.clip(1.0 - seg_dist(px, py, x0, y0, x1, y1) / 3.0, 0, 1))
    trace_col = np.array([0.16, 0.5, 0.44])
    m = trace_mask[..., None]
    img = img * (1 - m * 0.85) + trace_col * (m * 0.85)

    # center chip outline
    chip = band(sd_rounded_box(px, py, 256, 256, 58, 58, 12), 0.0, 4.0) * 0.8
    img = img * (1 - chip[..., None]) + np.array([0.14, 0.42, 0.38]) * chip[..., None]

    # corner bolts
    bolts = np.zeros_like(px)
    for bx, by in ((66, 66), (446, 66), (66, 446), (446, 446)):
        bolts = np.maximum(bolts, np.clip(1.0 - np.sqrt((px - bx) ** 2 + (py - by) ** 2) / 6.0, 0, 1))
    img = img * (1 - bolts[..., None]) + np.array([0.1, 0.13, 0.16]) * bolts[..., None]

    save(f"{OUT}/tile_face.png", img, w, h)


def gen_floor_metal():
    print("floor_metal.png")
    w = h = 512
    px, py = grid(w, h)
    img = np.tile(np.array([0.047, 0.067, 0.086]), (h * SR, w * SR, 1))
    img += noise_field(h * SR, w * SR, 8, 3, -0.012, 0.012)

    # panel seams at wrap edges (tile-safe)
    seam = np.clip(1.0 - np.minimum(px, w - px) / 3.0, 0, 1)
    seam = np.maximum(seam, np.clip(1.0 - np.minimum(py, h - py) / 3.0, 0, 1))
    dark = np.array([0.02, 0.03, 0.045])[None, None, :]
    img = img * (1 - seam[..., None]) + dark * seam[..., None]

    # faint diagonal scratches
    rng = np.random.default_rng(11)
    for _ in range(14):
        x0 = rng.uniform(0, w)
        y0 = rng.uniform(0, h)
        x1 = x0 + rng.uniform(-120, 120)
        y1 = y0 + rng.uniform(-120, 120)
        d = np.clip(1.0 - seg_dist(px, py, x0, y0, x1, y1) / 1.6, 0, 1) * rng.uniform(0.02, 0.06)
        img += d[..., None] * np.array([[0.5, 0.6, 0.7]])

    # rivets
    riv = np.zeros_like(px)
    for rx, ry in ((36, 36), (476, 36), (36, 476), (476, 476), (256, 36), (256, 476), (36, 256), (476, 256)):
        riv = np.maximum(riv, np.clip(1.0 - np.sqrt((px - rx) ** 2 + (py - ry) ** 2) / 5.0, 0, 1))
    img = img * (1 - riv[..., None]) + np.array([0.09, 0.12, 0.15]) * riv[..., None]

    save(f"{OUT}/floor_metal.png", img, w, h)


def gen_wall_panel():
    print("wall_panel.png")
    w = h = 1024
    px, py = grid(w, h)
    img = np.tile(np.array([0.067, 0.086, 0.114]), (h * SR, w * SR, 1))
    img += noise_field(h * SR, w * SR, 8, 5, -0.015, 0.015)

    # vertical gradient (darker toward bottom)
    grad = (1.0 - 0.22 * py / h)[..., None]
    img *= grad

    # bevel frame
    sd = sd_rounded_box(px, py, 511.5, 511.5, 500.0, 500.0, 10.0)
    frame = band(sd, -6.0, 8.0)
    inner = band(sd, -18.0, 10.0) * 0.5
    img = img * (1 - frame[..., None]) + np.array([0.10, 0.13, 0.17]) * frame[..., None]
    img = img * (1 - inner[..., None]) + np.array([0.035, 0.05, 0.07]) * inner[..., None]

    # horizontal grooves
    for gy in (300, 700):
        g = np.clip(1.0 - np.abs(py - gy) / 3.5, 0, 1)
        img = img * (1 - g[..., None]) + np.array([0.03, 0.04, 0.055]) * g[..., None]
        gl = np.clip(1.0 - np.abs(py - (gy + 5)) / 2.0, 0, 1) * 0.5
        img += gl[..., None] * np.array([[0.35, 0.45, 0.55]])

    # small accent light slot
    slot = np.clip(1.0 - np.abs(px - 160) / 7.0, 0, 1) * np.clip(1.0 - np.abs(py - 700) / 26.0, 0, 1)
    img = img * (1 - slot[..., None] * 0.8) + np.array([0.45, 0.85, 0.78]) * (slot[..., None] * 0.8)

    save(f"{OUT}/wall_panel.png", img, w, h)


def gen_hazard():
    print("hazard.png")
    w = h = 256
    px, py = grid(w, h)
    u = (px + py) % 72.0
    stripe = (u < 36.0).astype(float)
    yellow = np.array([0.87, 0.68, 0.20])
    darkc = np.array([0.075, 0.085, 0.10])
    img = darkc[None, None, :] * (1 - stripe[..., None]) + yellow[None, None, :] * stripe[..., None]
    img += noise_field(h * SR, w * SR, 4, 9, -0.03, 0.03)
    img *= (1.0 - 0.15 * np.abs(py - h / 2) / (h / 2))[..., None]
    save(f"{OUT}/hazard.png", img, w, h)


def gen_pad_start():
    print("pad_start.png")
    w = h = 512
    px, py = grid(w, h)
    img = np.tile(np.array([0.05, 0.12, 0.08]), (h * SR, w * SR, 1))
    img += noise_field(h * SR, w * SR, 8, 21, -0.008, 0.008)
    sd = sd_rounded_box(px, py, 255.5, 255.5, 244.0, 244.0, 26.0)
    ring = band(sd, -10.0, 10.0)
    img = img * (1 - ring[..., None]) + np.array([0.55, 1.0, 0.72]) * ring[..., None]
    # chevrons pointing up (toward the grid)
    chev = np.zeros_like(px)
    for yc in (176, 256, 336):
        arm = np.abs(px - 256.0) - (yc + 44.0 - py) * 1.25
        chev = np.maximum(chev, np.clip(1.0 - np.abs(arm) / 8.0, 0, 1) * np.clip(1.0 - np.abs(py - (yc + 22.0)) / 24.0, 0, 1))
    img = img * (1 - chev[..., None]) + np.array([0.62, 1.0, 0.78]) * chev[..., None]
    save(f"{OUT}/pad_start.png", img, w, h)


def gen_pad_finish():
    print("pad_finish.png")
    w = h = 512
    px, py = grid(w, h)
    img = np.tile(np.array([0.13, 0.10, 0.035]), (h * SR, w * SR, 1))
    img += noise_field(h * SR, w * SR, 8, 33, -0.008, 0.008)
    sd = sd_rounded_box(px, py, 255.5, 255.5, 244.0, 244.0, 26.0)
    ring = band(sd, -10.0, 10.0)
    img = img * (1 - ring[..., None]) + np.array([1.0, 0.85, 0.42]) * ring[..., None]
    # checkerboard flag
    ix = np.floor((px - 136.0) / 60.0)
    iy = np.floor((py - 136.0) / 60.0)
    inside = (px >= 136) & (px < 376) & (py >= 136) & (py < 376)
    alt = ((ix + iy) % 2 == 0) & inside
    checker = alt.astype(float) * 0.8 + (~alt & inside).astype(float) * 0.28
    img = img * (1 - inside[..., None]) + np.array([1.0, 0.9, 0.55]) * checker[..., None]
    save(f"{OUT}/pad_finish.png", img, w, h)


if __name__ == "__main__":
    gen_tile_face()
    gen_floor_metal()
    gen_wall_panel()
    gen_hazard()
    gen_pad_start()
    gen_pad_finish()
    print("TEXTURES: ALL GENERATED OK")
