#!/usr/bin/env python3
"""Generate the PBR texture library for the realistic TV-game-show studio
environment overhaul. Same pure numpy + zlib pipeline as gen_textures.py
(no PIL). Deterministic: every RNG is np.random.default_rng(fixed_seed).

Run from repo root:
    python3 scripts-dev/gen_textures_pbr.py

Writes to assets/textures/pbr/ (dark indoor-studio palette: steel, graphite,
concrete, rubber, tungsten-warm accents; no neon):
  steel_brushed       brushed stainless, stage trim / podium fascia
                      (albedo/normal/rough 512x512)
  steel_painted_dark  graphite powder-coat with edge wear chips
                      (albedo/normal/rough 512x512)
  concrete_wall       poured studio concrete, form-work seams, pitting
                      (albedo/normal/rough 512x512)
  rubber_mat          anti-slip stage matting, raised diamond tread
                      (albedo/normal/rough 512x512)
  audience_crowd      distant seated-audience billboard
                      (albedo/rough 1024x256)
  led_walls_show      LED video-wall broadcast graphics, 45-degree sweeps
                      (albedo 1024x512 -- map to EMISSION in-engine)
  curtain_stage       heavy theatrical drape, deep burgundy folds
                      (albedo/normal/rough 512x512)
  tile_top_glass      smoked-glass tile caps, frosted streaks, hairlines
                      (albedo/normal/rough 512x512)

TILEABILITY, by construction:
  * value noise comes from periodic_noise(), a wrapped-lattice value noise
    whose cell size must divide the image (asserted) -> the image is exactly
    one period of the pattern in x and y;
  * white speckle (periodic_white) is spatially stationary, so the wrap edge
    is statistically identical to any interior cut;
  * blobs (wear chips, pits, people) sit at random positions but are
    rendered through torus/wrapped distance, so shapes continue across the
    edges instead of being cut;
  * geometric patterns use explicit mod-period coordinates.
Each emitted file is re-audited with a roll-by-half seam check, and every
PNG is re-parsed (signature, IHDR, all chunk CRCs, full IDAT inflate, IEND)
before the script reports success.

NORMAL MAPS: tangent-space, OpenGL/Godot convention. From a heightfield
h(x, y) with y = image row increasing DOWNWARD:
    dhdx = d h / d x (axis 1), dhdy = d h / d y (axis 0)
    nx = -dhdx * strength, ny = +dhdy * strength, nz = 1  (then normalize)
Gradients are np.roll central differences so the normal tiles with the
heightfield. Encoding rgb = (n * 0.5 + 0.5) * 255; a flat field encodes to
exactly (128, 128, 255), asserted by a startup self-test.
"""
import os
import struct
import sys
import zlib

import numpy as np

SR = 2  # supersample factor, same pipeline as gen_textures.py

OUT = "assets/textures/pbr"
os.makedirs(OUT, exist_ok=True)

GENERATED = []  # (filename, w, h) for the re-parse gate
FAILURES = []  # tile-check failures, reported at exit


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


def seg_dist(px, py, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy
    t = np.clip(((px - x0) * dx + (py - y0) * dy) / L2, 0.0, 1.0)
    cx_ = x0 + t * dx
    cy_ = y0 + t * dy
    return np.sqrt((px - cx_) ** 2 + (py - cy_) ** 2)


def rgb(r, g, b):
    """Stack three (h, w) planes into an (h, w, 3) image."""
    return np.concatenate([r[..., None], g[..., None], b[..., None]], axis=-1)


def down(img01, w, h):
    """(h*SR, w*SR, C) -> (h, w, C) via 2x2 box average (supersample fold)."""
    if SR > 1:
        img01 = img01.reshape(h, SR, w, SR, *img01.shape[2:]).mean(axis=(1, 3))
    return img01


def periodic_noise(w, h, cellx, celly, seed, lo=0.0, hi=1.0):
    """Smooth value noise that tiles EXACTLY: the lattice repeats with period
    cellx/celly pixels and the interpolation wraps at the lattice, so the
    generated image is one full period of the pattern. Requires cellx | w and
    celly | h (asserted). Supersedes gen_textures.noise_field, whose +2/crop
    lattice breaks periodicity."""
    assert w % cellx == 0 and h % celly == 0, "periodic_noise: cell must divide dims"
    rng = np.random.default_rng(seed)
    gw, gh = w // cellx, h // celly
    if gw == 1 and gh == 1:
        return np.full((h, w), float(rng.uniform(lo, hi)))
    lat = rng.uniform(lo, hi, (gh, gw))
    yy, xx = np.mgrid[0:h, 0:w]
    fx = xx / cellx
    fy = yy / celly
    x0 = np.floor(fx).astype(np.int64) % gw
    y0 = np.floor(fy).astype(np.int64) % gh
    x1 = (x0 + 1) % gw
    y1 = (y0 + 1) % gh
    sx = fx - np.floor(fx)
    sy = fy - np.floor(fy)
    sx = sx * sx * (3.0 - 2.0 * sx)
    sy = sy * sy * (3.0 - 2.0 * sy)
    a = lat[y0, x0]
    b = lat[y0, x1]
    c = lat[y1, x0]
    d = lat[y1, x1]
    out = a * (1 - sx) * (1 - sy) + b * sx * (1 - sy) + c * (1 - sx) * sy + d * sx * sy
    return out


def periodic_fbm(w, h, seed, octaves, lo=0.0, hi=1.0):
    """Sum of periodic_noise octaves [(cellx, celly, weight), ...]; every cell
    must divide the image, so the sum is exactly tileable."""
    acc = np.zeros((h, w))
    wsum = 0.0
    for i, (cx, cy, wt) in enumerate(octaves):
        acc += periodic_noise(w, h, cx, cy, seed + i * 101) * wt
        wsum += wt
    acc /= wsum
    return lo + acc * (hi - lo)


def periodic_white(w, h, seed, lo=0.0, hi=1.0):
    """Per-pixel stationary white noise. Not pattern-periodic, but spatially
    stationary: the wrap border is statistically identical to any interior
    cut, so the tiled result shows no seam."""
    rng = np.random.default_rng(seed)
    return rng.uniform(lo, hi, (h, w))


def wrap_dx(px, cx, w):
    d = np.abs(px - cx)
    return np.minimum(d, w - d)


def wrap_dist(px, py, cx, cy, w, h):
    """Torus (wrapped) distance so blobs continue across tile edges."""
    dx = wrap_dx(px, cx, w)
    dy = np.abs(py - cy)
    dy = np.minimum(dy, h - dy)
    return np.sqrt(dx * dx + dy * dy)


def tile_check(label, img01, w, h):
    """img01: final-res float image (h, w, 3). Roll by (h//2, w//2) and audit
    seam discontinuity at the rolled borders AND at the rolled mid-lines --
    the roll relocates the image's own wrap seam to the interior mid-lines,
    so the four checks cover both interior continuity and true wrap seams.
    A seam passes if it is no worse than the image's own adjacent-pixel
    difference statistics (99.9th pct with headroom, or a small floor)."""
    img = np.asarray(img01, dtype=np.float64)
    r = np.roll(img, (h // 2, w // 2), axis=(0, 1))

    def ad(a, b):
        return float(np.mean(np.abs(a - b)))

    dx_ = np.abs(np.diff(img, axis=1))
    dy_ = np.abs(np.diff(img, axis=0))
    tests = [
        ("x", ad(r[:, 0], r[:, -1]), dx_),
        ("y", ad(r[0, :], r[-1, :]), dy_),
        ("x@mid", ad(r[:, w // 2 - 1], r[:, w // 2]), dx_),
        ("y@mid", ad(r[h // 2 - 1, :], r[h // 2, :]), dy_),
    ]
    ok = True
    worst = 0.0
    for name, seam, diffs in tests:
        d = diffs.reshape(-1)
        mean = float(d.mean())
        hi = float(np.percentile(d, 99.9))
        thr = max(1.5 * hi, 6.0 * mean, 0.02)
        worst = max(worst, seam / thr)
        if seam > thr:
            ok = False
            print(f"  TILE CHECK FAIL [{label}] {name}: seam={seam:.4f} thr={thr:.4f}")
    if ok:
        print(f"  tileable OK [{label}] (worst seam/threshold {worst:.2f})")
    return ok


def emit(path, img01, w, h):
    """Final-res float image (h, w, 3) 0..1 -> seam audit -> quantize -> png."""
    if not tile_check(os.path.basename(path), img01, w, h):
        FAILURES.append(path)
    arr = (np.clip(img01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    write_png(path, arr)
    GENERATED.append((os.path.basename(path), w, h))


def _normal_rgb(hgt, strength):
    """Heightfield (h, w) -> tangent-space normal image, OpenGL/Godot:
    nx = -dhdx, ny = +dhdy (y-down rows), wrapped central differences."""
    dhdx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    dhdy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5
    nx = -dhdx * strength
    ny = dhdy * strength
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], axis=-1)
    return n


def normal_from_height(path, hgt_ss, strength, w, h):
    """hgt_ss: supersampled heightfield -> fold to final res -> normal png."""
    n = _normal_rgb(down(hgt_ss, w, h), strength)
    tilt = float(np.max(np.abs(n[..., :2])))
    r_ = np.clip(n[..., 0] * 0.5 + 0.5, 0.0, 1.0)
    g_ = np.clip(n[..., 1] * 0.5 + 0.5, 0.0, 1.0)
    print(f"    normal: max tilt {tilt:.3f} "
          f"(red {r_.min() * 255:.0f}..{r_.max() * 255:.0f}, green {g_.min() * 255:.0f}..{g_.max() * 255:.0f})")
    emit(path, n * 0.5 + 0.5, w, h)


def selftest_normal_flat():
    """Flat heightfield must encode to exactly (128, 128, 255)."""
    n = _normal_rgb(np.zeros((64, 64)), 3.0)
    arr = (np.clip(n * 0.5 + 0.5, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    assert (arr == np.array([128, 128, 255])).all(), "flat normal != (128,128,255)"
    print("normal self-test: flat field -> (128,128,255) OK")


def verify_png(path, ew, eh):
    """Re-parse a written PNG: signature, IHDR dims, all chunk CRCs, full
    IDAT inflate, IEND present, 8-bit RGB scanlines of the expected length."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"bad signature {path}"
    pos, idat, iend = 8, b"", False
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + ln]
        (crc,) = struct.unpack(">I", data[pos + 8 + ln:pos + 12 + ln])
        assert crc == (zlib.crc32(tag + payload) & 0xFFFFFFFF), f"CRC mismatch {path} {tag}"
        if tag == b"IHDR":
            iw, ih = struct.unpack(">II", payload[:8])
            assert (iw, ih, payload[8], payload[9]) == (ew, eh, 8, 2), f"IHDR mismatch {path}"
        elif tag == b"IDAT":
            idat += payload
        elif tag == b"IEND":
            assert ln == 0
            iend = True
        pos += 12 + ln
    assert iend, f"missing IEND {path}"
    raw = zlib.decompress(idat)
    assert len(raw) == eh * (1 + ew * 3), f"pixel stream size {path}"
    print(f"  verified {path}  {ew}x{eh}  {len(data)} bytes")


def lum01(img):
    return img[..., 0] * 0.30 + img[..., 1] * 0.59 + img[..., 2] * 0.11


def stat_line(tag, img):
    l = lum01(img)
    print(f"    {tag}: lum mean={l.mean():.3f} p01={np.percentile(l, 1):.3f} p99={np.percentile(l, 99):.3f}")


# --------------------------------------------------------------------------
# A) brushed stainless
# --------------------------------------------------------------------------
def gen_steel_brushed():
    print("steel_brushed: brushed stainless (stage trim, podium fascia)")
    w = h = 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    # anisotropic brushing: strands 256px long in x, 1px apart in y
    streak = periodic_noise(W, H, 256 * SR, SR, 401)
    fine = periodic_noise(W, H, 4 * SR, 4 * SR, 402)
    mottle = periodic_noise(W, H, 128 * SR, 128 * SR, 403)
    s = 0.55 * streak + 0.30 * fine + 0.15 * mottle  # brushing field 0..1
    lum = 0.62 + (s - 0.5) * 0.20  # ~0.52..0.72, flat (vignette-free)
    img = rgb(lum * 0.985, lum * 0.995, lum * 1.010)
    img += periodic_white(W, H, 404, -0.006, 0.006)[..., None]
    rough = 0.30 + (s - 0.5) * 0.16  # 0.30 +- 0.08 streak modulation
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    assert 0.55 <= lum01(alb).mean() <= 0.70, "brushed albedo luminance band"
    assert 0.20 <= lum01(rgh).min() and lum01(rgh).max() <= 0.42, "brushed roughness band"
    emit(f"{OUT}/steel_brushed_albedo.png", alb, w, h)
    emit(f"{OUT}/steel_brushed_rough.png", rgh, w, h)
    # shallow horizontal grooves -> low-strength normal
    normal_from_height(f"{OUT}/steel_brushed_normal.png",
                       (streak - 0.5) * 0.16 + (fine - 0.5) * 0.02, 2.5, w, h)


# --------------------------------------------------------------------------
# B) graphite powder-coat with wear chips
# --------------------------------------------------------------------------
def gen_steel_painted_dark():
    print("steel_painted_dark: graphite powder-coat with edge wear chips")
    w = h = 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    peel = periodic_noise(W, H, 2 * SR, 2 * SR, 901)  # orange-peel micro relief
    mottle = periodic_noise(W, H, 128 * SR, 128 * SR, 902)
    img = np.tile(np.array([0.092, 0.098, 0.106]), (H, W, 1))
    img += (peel - 0.5)[..., None] * np.array([0.028, 0.028, 0.032])
    img += (mottle - 0.5)[..., None] * np.array([0.010, 0.010, 0.012])
    rng = np.random.default_rng(903)
    wob = periodic_noise(W, H, 8 * SR, 8 * SR, 904)   # chip-edge wobble
    fine = periodic_noise(W, H, 4 * SR, 4 * SR, 905)   # chip-internal grind
    chip = np.zeros((H, W))
    ring = np.zeros((H, W))
    for _ in range(13):
        if rng.random() < 0.72:  # wear gathers along panel edges / corners
            e = int(rng.integers(0, 4))
            d = rng.uniform(5.0, 30.0)
            t = rng.uniform(0.0, w)
            cx, cy = [(t, d), (t, h - d), (d, t), (w - d, t)][e]
        else:
            cx, cy = rng.uniform(0.0, w), rng.uniform(0.0, h)
        r0 = rng.uniform(4.0, 12.0)
        dd = wrap_dist(px, py, cx, cy, w, h) + (wob - 0.5) * r0 * 1.1
        m = np.clip(1.0 - (dd - 0.7 * r0) / (0.5 * r0), 0.0, 1.0)
        chip = np.maximum(chip, m)
        ring = np.maximum(ring,
                          np.clip(1.0 - np.abs(dd - 1.25 * r0) / 2.2, 0.0, 1.0) * (1.0 - m))
    metal = 0.45 * (0.90 + 0.20 * fine)  # bare steel exposed in the chips
    img = img * (1 - chip[..., None]) + rgb(metal * 0.97, metal, metal * 1.06) * chip[..., None]
    img *= (1 - 0.35 * ring)[..., None]  # paint shadow at the chip lip
    rough = (0.45 + (peel - 0.5) * 0.06) * (1 - chip) + (0.25 + (fine - 0.5) * 0.08) * chip
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    la = lum01(alb)
    assert 0.075 <= np.percentile(la, 50) <= 0.13, "paint tone band"
    assert la.max() >= 0.35, "chips must expose bright metal"
    lr = lum01(rgh)
    assert 0.35 <= lr.mean() <= 0.55 and 0.18 <= lr.min() and lr.max() <= 0.55
    emit(f"{OUT}/steel_painted_dark_albedo.png", alb, w, h)
    emit(f"{OUT}/steel_painted_dark_rough.png", rgh, w, h)
    # chips recessed below the paint film, tiny burr at the lip
    normal_from_height(f"{OUT}/steel_painted_dark_normal.png",
                       (peel - 0.5) * 0.05 - chip * 0.42 + ring * 0.10, 2.0, w, h)


# --------------------------------------------------------------------------
# C) poured concrete wall
# --------------------------------------------------------------------------
def gen_concrete_wall():
    print("concrete_wall: poured studio concrete, form seams, pitting")
    w = h = 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    blotch = periodic_fbm(W, H, 801, [(128 * SR, 128 * SR, 1.0),
                                      (32 * SR, 32 * SR, 0.6),
                                      (8 * SR, 8 * SR, 0.35)])
    grain = periodic_white(W, H, 802)
    img = np.tile(np.array([0.455, 0.450, 0.440]), (H, W, 1))
    img *= (0.80 + 0.40 * blotch)[..., None]
    img += (grain - 0.5)[..., None] * 0.030
    hgt = (blotch - 0.5) * 0.35 + (grain - 0.5) * 0.08
    for sy in (h / 3.0, 2.0 * h / 3.0):  # form-work seams at 1/3 and 2/3
        g = np.clip(1.0 - np.abs(py - sy) / 1.8, 0.0, 1.0)
        img *= (1.0 - 0.32 * g)[..., None]
        gl = np.clip(1.0 - np.abs(py - (sy + 2.5)) / 1.4, 0.0, 1.0)
        img += gl[..., None] * np.array([0.050, 0.050, 0.048])
        hgt = hgt - 0.40 * g
    rng = np.random.default_rng(803)
    wob = periodic_noise(W, H, 4 * SR, 4 * SR, 804)
    pits = np.zeros((H, W))
    for _ in range(26):
        cx, cy = rng.uniform(0.0, w), rng.uniform(0.0, h)
        r0 = rng.uniform(0.9, 2.6)
        dd = wrap_dist(px, py, cx, cy, w, h) + (wob - 0.5) * r0 * 0.9
        pits = np.maximum(pits, np.clip(1.15 - dd / r0, 0.0, 1.0))
    img *= (1.0 - 0.45 * pits)[..., None]
    hgt = hgt - 0.30 * pits
    rough = 0.85 + (blotch - 0.5) * 0.18 + (grain - 0.5) * 0.05 - pits * 0.05
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    la = lum01(alb)
    assert 0.28 <= np.percentile(la, 1) and np.percentile(la, 99) <= 0.58, "concrete tone band"
    lr = lum01(rgh)
    assert 0.72 <= lr.mean() <= 0.98, "concrete roughness ~0.85 +- 0.1"
    emit(f"{OUT}/concrete_wall_albedo.png", alb, w, h)
    emit(f"{OUT}/concrete_wall_rough.png", rgh, w, h)
    normal_from_height(f"{OUT}/concrete_wall_normal.png", hgt, 1.2, w, h)


# --------------------------------------------------------------------------
# D) anti-slip rubber matting
# --------------------------------------------------------------------------
def gen_rubber_mat():
    print("rubber_mat: anti-slip stage matting, raised diamond tread")
    w = h = 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    P = 64.0

    def tdi(u, v, cx, cy):
        dx = np.abs(u - cx)
        dx = np.minimum(dx, P - dx)
        dy = np.abs(v - cy)
        dy = np.minimum(dy, P - dy)
        return dx * 0.82 + dy * 1.18  # diamonds elongated along x

    d = np.minimum(tdi(px % P, py % P, 16.0, 16.0), tdi(px % P, py % P, 48.0, 48.0))
    diam = np.clip(1.0 - d / 22.0, 0.0, 1.0) ** 1.5  # low-relief dome tread
    speck = periodic_white(W, H, 1001)
    grit = periodic_noise(W, H, 2 * SR, 2 * SR, 1002)
    gran = np.clip((periodic_noise(W, H, 4 * SR, 4 * SR, 1003) - 0.86) / 0.14, 0.0, 1.0)
    img = np.tile(np.array([0.046, 0.047, 0.051]), (H, W, 1))
    img += (speck - 0.5)[..., None] * 0.010
    img += (grit - 0.5)[..., None] * 0.008
    img += diam[..., None] * np.array([0.010, 0.010, 0.011])
    img += gran[..., None] * np.array([0.020, 0.021, 0.019])  # rubber granules
    rough = 0.95 - diam * 0.05 + (speck - 0.5) * 0.05 + gran * 0.02
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    la = lum01(alb)
    assert np.percentile(la, 99) <= 0.10 and la.mean() >= 0.03, "rubber tone band"
    assert 0.85 <= lum01(rgh).mean() <= 1.0, "rubber roughness ~0.95"
    emit(f"{OUT}/rubber_mat_albedo.png", alb, w, h)
    emit(f"{OUT}/rubber_mat_rough.png", rgh, w, h)
    normal_from_height(f"{OUT}/rubber_mat_normal.png",
                       diam * 0.50 + (grit - 0.5) * 0.012 + (speck - 0.5) * 0.008, 12.0, w, h)


# --------------------------------------------------------------------------
# E) seated audience billboard
# --------------------------------------------------------------------------
def gen_audience_crowd():
    print("audience_crowd: distant seated-audience billboard (albedo+rough)")
    w, h = 1024, 256
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    btop = h - 38.0  # bottom ~15% barrier / railing
    img = np.tile(np.array([0.020, 0.023, 0.030]), (H, W, 1))  # dark hall behind
    img += (periodic_noise(W, H, 64 * SR, 64 * SR, 501) - 0.5)[..., None] * 0.008
    rough = np.full((H, W), 0.90)
    rng = np.random.default_rng(502)
    palette = np.array([
        [0.100, 0.115, 0.140],  # dark slate
        [0.135, 0.115, 0.100],  # dark warm gray
        [0.095, 0.125, 0.130],  # dark teal-gray
        [0.120, 0.115, 0.090],  # dark olive-gray
        [0.065, 0.070, 0.080],  # near-black coat
    ])
    rows = [  # back row first (occluded by later rows): y_sh, head_r, shoulder_hw, shoulder_hh, count
        (42.0, 5.2, 15.5, 8.0, 40),
        (74.0, 6.4, 19.0, 10.0, 32),
        (108.0, 8.0, 23.5, 12.5, 26),
        (146.0, 10.4, 29.0, 16.0, 20),
        (188.0, 13.0, 37.0, 20.0, 16),
    ]
    for ri, (y_sh, hr, sw, sh, n) in enumerate(rows):
        dim = 1.0 - 0.095 * (len(rows) - 1 - ri)  # back rows fall into shadow
        spacing = w / n
        stag = rng.uniform(0.0, spacing)
        for _k in range(n):
            cx = (stag + _k * spacing + rng.uniform(-4.0, 4.0)) % w
            lean = rng.uniform(-3.0, 3.0)
            col = palette[int(rng.integers(0, len(palette)))] * dim * rng.uniform(0.90, 1.10)
            swp = sw * rng.uniform(0.88, 1.12)
            shp = sh * rng.uniform(0.90, 1.10)
            hrp = hr * rng.uniform(0.88, 1.12)
            hy = y_sh - shp - hrp * 0.55
            body = np.clip(1.18 - np.sqrt((wrap_dx(px, cx, w) / swp) ** 2
                                          + ((py - y_sh) / shp) ** 2), 0.0, 1.0)
            body = np.maximum(body, np.clip(1.25 - np.sqrt((wrap_dx(px, cx + lean, w) / hrp) ** 2
                                                           + ((py - hy) / hrp) ** 2), 0.0, 1.0))
            if y_sh >= 100.0:  # nearer rows catch a faint rim from the stage
                rim = np.clip(1.18 - np.sqrt((wrap_dx(px, cx, w) / swp) ** 2
                                             + ((py - (y_sh - 1.5)) / shp) ** 2), 0.0, 1.0)
                rim = np.maximum(rim, np.clip(1.25 - np.sqrt((wrap_dx(px, cx + lean, w) / hrp) ** 2
                                                            + ((py - (hy - 1.2)) / hrp) ** 2), 0.0, 1.0))
                colrim = np.clip(col * 1.55 + 0.012, 0.0, 0.30)
                img = img * (1 - rim[..., None]) + colrim[None, None, :] * rim[..., None]
            img = img * (1 - body[..., None]) + col[None, None, :] * body[..., None]
            rough = rough * (1 - body) + (0.80 + rng.uniform(-0.04, 0.04)) * body
            if rng.random() < 0.07:  # occasional phone screen glow
                gx = cx + rng.uniform(-swp * 0.4, swp * 0.4)
                gy = y_sh - shp * 0.35
                dp = wrap_dist(px, py, gx, gy, w, h)
                pm = np.clip(1.0 - dp / 1.5, 0.0, 1.0)
                halo = np.clip(1.0 - dp / 5.0, 0.0, 1.0) * 0.35
                img += (halo * 0.25)[..., None] * np.array([0.70, 0.80, 1.00])
                img = img * (1 - pm[..., None]) + np.array([0.82, 0.90, 1.00])[None, None, :] * pm[..., None]
                rough = rough * (1 - pm) + 0.22 * pm
    # dark barrier / railing across the bottom 15%
    b = np.clip((py - btop) / 1.2, 0.0, 1.0)
    bshade = 1.0 - 0.35 * np.clip((py - btop) / (h - btop), 0.0, 1.0)
    bcol = np.array([0.055, 0.058, 0.066])[None, None, :] * bshade[..., None]
    img = img * (1 - b[..., None]) + bcol * b[..., None]
    rail = np.clip(1.0 - np.abs(py - (btop + 1.6)) / 1.6, 0.0, 1.0) * b
    img += rail[..., None] * np.array([0.060, 0.065, 0.075])
    post = np.zeros((H, W))
    for sx in range(24, w, 128):
        post = np.maximum(post, np.clip(1.0 - wrap_dx(px, float(sx), w) / 2.4, 0.0, 1.0))
    post *= b * np.clip((py - (btop + 4.0)) / 2.0, 0.0, 1.0)
    img = img * (1 - 0.45 * post)[..., None] + np.array([0.030, 0.032, 0.040])[None, None, :] * (0.45 * post)[..., None]
    rough = rough * (1 - b) + 0.55 * b
    rough = rough * (1 - post) + 0.45 * post
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    la = lum01(alb)
    assert la.max() > 0.5, "phone glows must read as bright dots"
    assert la.mean() < 0.25, "crowd stays very dark"
    assert 0.70 <= lum01(rgh).mean() <= 0.95, "crowd roughness ~0.8 flat-ish"
    emit(f"{OUT}/audience_crowd_albedo.png", alb, w, h)
    emit(f"{OUT}/audience_crowd_rough.png", rgh, w, h)


# --------------------------------------------------------------------------
# F) LED video-wall show content (map to EMISSION in-engine)
# --------------------------------------------------------------------------
def gen_led_walls_show():
    print("led_walls_show: LED wall broadcast graphics (map to EMISSION)")
    w, h = 1024, 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    u = (px + py) % 512.0  # 45-degree sweep; 512 divides both dims -> tiles
    img = np.tile(np.array([0.020, 0.027, 0.039]), (H, W, 1))  # ~#05070a base

    def pulse(c, hw, soft):
        t = np.clip((hw - np.abs(u - c)) / soft, 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    for c, hw, soft, col, op in (
        (80.0, 62.0, 34.0, (1.00, 0.75, 0.25), 1.00),  # broad warm amber-white sweep
        (232.0, 34.0, 18.0, (0.90, 0.95, 1.00), 1.00),  # cool white band
        (330.0, 18.0, 10.0, (1.00, 0.72, 0.30), 0.45),  # faint amber echo
        (392.0, 9.0, 5.0, (0.16, 0.90, 0.78), 1.00),  # single thin electric teal
        (454.0, 12.0, 7.0, (0.85, 0.90, 1.00), 0.30),  # dim cool white
    ):
        p = pulse(c, hw, soft)
        img += (p * op)[..., None] * np.array(col)[None, None, :]
    # faint hex-circuit overlay: 2:1 iso line lattice + node dots. True 60-degree
    # hexagons have irrational slopes and cannot wrap exactly; the 2:1 iso grid
    # is the pixel-art hex convention and tiles perfectly.
    def ldist(v, c):
        m = v % c
        return np.minimum(m, c - m)

    d0 = ldist(py, 128.0)
    d1 = ldist(px + 2.0 * py, 128.0)
    d2 = ldist(px - 2.0 * py, 128.0)
    lines = np.clip(1.3 - np.minimum(np.minimum(d0, d1), d2) / 1.3, 0.0, 1.0)
    nodes = np.clip(2.0 - d1, 0.0, 1.0) * np.clip(2.0 - d2, 0.0, 1.0)
    img += lines[..., None] * np.array([0.028, 0.048, 0.056])
    img += nodes[..., None] * np.array([0.050, 0.100, 0.110])
    img *= (1.0 - 0.13 * (py % 8.0 < 1.0))[..., None]  # LED scanline grid
    alb = down(img, w, h)
    stat_line("albedo", alb)
    la = lum01(alb)
    assert la.max() > 0.6 and np.percentile(la, 50) < 0.10, "emission contrast"
    assert alb[..., 0].max() > 0.85, "warm band must stay saturated"
    emit(f"{OUT}/led_walls_show_albedo.png", alb, w, h)


# --------------------------------------------------------------------------
# G) theatrical curtain
# --------------------------------------------------------------------------
def gen_curtain_stage():
    print("curtain_stage: heavy theatrical drape, deep burgundy folds")
    w = h = 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    P = 64.0
    warp = periodic_noise(W, H, 128 * SR, 64 * SR, 601, -4.0, 4.0)  # slow fold drift
    u = (px + warp) % P
    fold = 0.5 - 0.5 * np.cos(2.0 * np.pi * u / P)  # 0 at crease .. 1 at ridge
    wr = periodic_noise(W, H, 16, 256, 602)  # vertical fabric wrinkles
    wr2 = periodic_noise(W, H, 64, 128, 603)
    hgt = fold * 0.85 + (wr - 0.5) * 0.06 + (wr2 - 0.5) * 0.04
    hn = np.clip(hgt, 0.0, 1.0)
    base = np.array([0.16, 0.05, 0.05])
    img = base[None, None, :] * (0.55 + 0.50 * hn)[..., None]
    img += hn[..., None] * np.array([0.014, 0.002, 0.002])  # ridges run warmer
    img += (periodic_white(W, H, 604) - 0.5)[..., None] * 0.008  # fabric weave
    rough = 0.85 - 0.20 * hn + (wr - 0.5) * 0.06  # 0.65 ridges / 0.85 valleys
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    assert 0.60 <= lum01(rgh).min() and lum01(rgh).max() <= 0.92, "curtain roughness band"
    assert alb[..., 0].mean() > 2.0 * alb[..., 1].mean(), "curtain must stay warm"
    emit(f"{OUT}/curtain_stage_albedo.png", alb, w, h)
    emit(f"{OUT}/curtain_stage_rough.png", rgh, w, h)
    normal_from_height(f"{OUT}/curtain_stage_normal.png", hgt, 10.0, w, h)


# --------------------------------------------------------------------------
# H) smoked-glass tile caps
# --------------------------------------------------------------------------
def gen_tile_top_glass():
    print("tile_top_glass: smoked-glass tile caps, frosted streaks, hairlines")
    w = h = 512
    px, py = grid(w, h)
    W, H = w * SR, h * SR
    streak = periodic_noise(W, H, 128 * SR, 2 * SR, 701)  # horizontal frost bands
    speck = periodic_white(W, H, 702)
    img = np.tile(np.array([0.030, 0.034, 0.045]), (H, W, 1))
    img += (streak - 0.5)[..., None] * np.array([0.010, 0.010, 0.013])
    img += (speck - 0.5)[..., None] * 0.006
    rng = np.random.default_rng(703)
    scr = np.zeros((H, W))
    for _ in range(9):  # sparse hairline micro-scratches, kept off the seam
        cx = rng.uniform(40.0, w - 40.0)
        cy = rng.uniform(40.0, h - 40.0)
        ang = rng.uniform(-0.35, 0.35) if rng.random() < 0.7 else rng.uniform(-1.25, 1.25)
        L = rng.uniform(25.0, 150.0)
        dxmax = (w - 20.0 - cx) if np.cos(ang) >= 0 else (cx - 20.0)
        dymax = (h - 20.0 - cy) if np.sin(ang) >= 0 else (cy - 20.0)
        L = min(L, dxmax / max(abs(np.cos(ang)), 1e-6), dymax / max(abs(np.sin(ang)), 1e-6))
        if L <= 4.0:
            continue
        m = np.clip(1.0 - seg_dist(px, py, cx, cy,
                                  cx + np.cos(ang) * L, cy + np.sin(ang) * L) / 1.1, 0.0, 1.0)
        scr = np.maximum(scr, m * rng.uniform(0.5, 1.0))
    img += scr[..., None] * 0.022
    rough = 0.12 + (streak - 0.5) * 0.08 + (speck - 0.5) * 0.02 + scr * 0.05
    alb = down(img, w, h)
    rgh = down(rgb(rough, rough, rough), w, h)
    stat_line("albedo", alb)
    stat_line("rough", rgh)
    assert np.percentile(lum01(alb), 99) <= 0.09, "glass stays very dark"
    lr = lum01(rgh)
    assert 0.04 <= lr.min() and lr.max() <= 0.24, "glass roughness ~0.08-0.18"
    emit(f"{OUT}/tile_top_glass_albedo.png", alb, w, h)
    emit(f"{OUT}/tile_top_glass_rough.png", rgh, w, h)
    normal_from_height(f"{OUT}/tile_top_glass_normal.png",
                       (streak - 0.5) * 0.06 + (speck - 0.5) * 0.015 - scr * 0.10, 0.8, w, h)


if __name__ == "__main__":
    print("PBR TEXTURES: TV-studio material library")
    selftest_normal_flat()
    gen_steel_brushed()
    gen_steel_painted_dark()
    gen_concrete_wall()
    gen_rubber_mat()
    gen_audience_crowd()
    gen_led_walls_show()
    gen_curtain_stage()
    gen_tile_top_glass()
    print("\nre-parse gate:")
    for fn, ew, eh in GENERATED:
        verify_png(f"{OUT}/{fn}", ew, eh)
    print("\nsummary:")
    for fn, ew, eh in GENERATED:
        p = f"{OUT}/{fn}"
        print(f"  {fn}  {ew}x{eh}  {os.path.getsize(p)} bytes")
    if FAILURES:
        print("PBR TEXTURES: FAILED tile checks:")
        for f in FAILURES:
            print("  FAIL", f)
        sys.exit(1)
    print("PBR TEXTURES: ALL GENERATED OK")
