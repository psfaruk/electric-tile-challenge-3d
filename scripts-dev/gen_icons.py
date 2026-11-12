#!/usr/bin/env python3
"""gen_icons.py -- procedural icon set generator for "Electric Tile Challenge 3D".

Pure Python 3 standard library ONLY (no PIL, no numpy). Implements:
  * a minimal PNG encoder (zlib + struct): signature, IHDR, IDAT (filter byte 0
    per scanline), IEND; supports RGB (color type 2) and RGBA (color type 6);
  * a tiny procedural rasterizer with 4x supersampling (render 4x, then
    box-downsample 4x4 blocks; premultiplied-alpha averaging for clean edges);
  * the icon design: a glowing 3x3 electric floor-tile grid with a gold
    "charged" center tile carrying a white lightning bolt.

Outputs (paths relative to the project root, i.e. parent of scripts-dev/):
    icon.svg                              192x192 vector mirror of icon_192.png
    assets/icons/icon_192.png              192x192 RGB   (dark rounded-square bg)
    assets/icons/icon_adaptive_fg_432.png 432x432 RGBA  (transparent bg, logo
                                          centered in the 55% adaptive safe zone)
    assets/icons/icon_adaptive_bg_432.png  432x432 RGB   (solid #0B131C)

After writing, the script re-reads every generated PNG, manually parses the
chunk stream / IHDR, asserts dimensions + color type (plus CRCs, IDAT payload
size, filter bytes), runs content sanity checks and prints verification lines.
Exit status 1 on any failure, 0 on success.

Design spec (pixel-precise, 192px reference):
  backdrop #0B131B rounded square, corner radius 18% of side, subtle vertical
  gradient to #101B26, faint diagonal scanlines (alpha 0.05), thin outer rim
  highlight #1E2A36.  Grid: 3x3 tiles inset 14% of side, gap 6% of side,
  tile = rounded rect (radius 8% of tile side), fill #10181F, glowing teal
  #2EE6C8 border ~4.5% of tile side (drawn 3x: thick+faint -> thin+bright).
  Center tile: gold #FFC53D fill, #FFE9A8 border, white lightning bolt
  (unit polygon scaled to the tile's inner area) with a slight glow.
"""

import math
import os
import struct
import sys
import time
import zlib

# ---------------------------------------------------------------------------
# constants
# ---------------------------------------------------------------------------

S = 4  # supersampling factor: render 4x, box-downsample

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG_PATH = os.path.join(ROOT, "icon.svg")
ICONS_DIR = os.path.join(ROOT, "assets", "icons")
PNG_192 = os.path.join(ICONS_DIR, "icon_192.png")
PNG_FG = os.path.join(ICONS_DIR, "icon_adaptive_fg_432.png")
PNG_BG = os.path.join(ICONS_DIR, "icon_adaptive_bg_432.png")

# palette (exact spec colors)
BG_TOP = (11, 19, 27)       # #0B131B icon backdrop top
BG_BOT = (16, 27, 38)       # #101B26 icon backdrop bottom (vertical gradient)
BG_ADAPT = (11, 19, 28)     # #0B131C adaptive background layer (solid)
TILE_FILL = (16, 24, 31)    # #10181F normal tile fill
TEAL = (46, 230, 200)       # #2EE6C8 tile border / glow
GOLD = (255, 197, 61)       # #FFC53D charged center tile fill
GOLD_BR = (255, 233, 168)   # #FFE9A8 charged tile border
RIM_COL = (30, 42, 54)      # #1E2A36 thin outer rim highlight
WHITE = (255, 255, 255)

# lightning bolt, unit coords in a 0..1 box (x right, y down)
BOLT_UNIT = [(0.585, 0.10), (0.30, 0.56), (0.47, 0.56), (0.415, 0.90),
             (0.72, 0.42), (0.545, 0.42), (0.635, 0.10)]

GLOW_PASSES = ((3.0, 41), (2.0, 97), (1.0, 255))  # (thickness x border, alpha)
SCAN_ALPHA = 13        # 0.05 * 255, faint diagonal scanlines (icon_192 only)
SCAN_PERIOD = 12.0     # period in (x+y) index space -> 45-degree stripes
SCAN_WIDTH = 4.0       # "on" width in (x+y) index space
BOLT_GLOW = 0.045      # bolt glow radius as fraction of the bolt box side
BOLT_GLOW_A = 100.0    # bolt glow peak alpha (0..255)
RIM_INSET = 1.25       # rim stroke path inset from icon edge
RIM_THICK = 2.5        # rim stroke thickness


# ---------------------------------------------------------------------------
# minimal PNG encoder
# ---------------------------------------------------------------------------

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _chunk(ctype, data):
    crc = zlib.crc32(ctype + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + ctype + data + struct.pack(">I", crc)


def write_png(path, w, h, color_type, pix):
    """Encode pix (row-major, 3 bytes/px for type 2, 4 bytes/px for type 6)."""
    n = 3 if color_type == 2 else 4
    if len(pix) != w * h * n:
        raise ValueError("pixel buffer size mismatch")
    stride = w * n
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (None) for every scanline
        raw += pix[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)
    blob = (PNG_SIG
            + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + _chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


# ---------------------------------------------------------------------------
# rasterizer core (straight-alpha RGBA byte framebuffer, source-over blending)
# ---------------------------------------------------------------------------

def rr_span(x0, y0, x1, y1, r, yt):
    """Horizontal span [xs,xe) of a rounded rect at scanline yt, or None."""
    if yt < y0 or yt > y1:
        return None
    r = min(r, (y1 - y0) * 0.5, (x1 - x0) * 0.5)
    if r <= 0.0:
        return (x0, x1)
    if yt < y0 + r:
        dd = r * r - (y0 + r - yt) ** 2
        if dd <= 0.0:
            return None
        dx = math.sqrt(dd)
        return (x0 + r - dx, x1 - r + dx)
    if yt > y1 - r:
        dd = r * r - (yt - (y1 - r)) ** 2
        if dd <= 0.0:
            return None
        dx = math.sqrt(dd)
        return (x0 + r - dx, x1 - r + dx)
    return (x0, x1)


class Canvas(object):
    """Straight-alpha RGBA framebuffer (bytearray, 4 bytes per pixel)."""

    def __init__(self, w, h, clear):
        self.w = w
        self.h = h
        self.buf = bytearray(bytes(clear) * (w * h))

    def blend_span(self, y, x0f, x1f, col):
        """Blend constant color over float span [x0f, x1f) at row y."""
        if x1f <= x0f:
            return
        x0 = math.ceil(x0f - 0.5)   # first pixel whose center >= x0f
        x1 = math.ceil(x1f - 0.5)   # first pixel whose center >= x1f
        if x0 < 0:
            x0 = 0
        if x1 > self.w:
            x1 = self.w
        if x1 <= x0:
            return
        self.blend_span_i(y, x0, x1, col)

    def blend_span_i(self, y, x0, x1, col):
        buf = self.buf
        r, g, b, a = col
        n = x1 - x0
        i = (y * self.w + x0) * 4
        if a == 0:
            return
        if a == 255:
            # opaque fast path: block fill via slice assignment
            buf[i:i + n * 4] = bytes((r, g, b, 255)) * n
            return
        ia = 255 - a
        end = i + n * 4
        while i < end:
            da = buf[i + 3]
            if da == 0:
                buf[i] = r
                buf[i + 1] = g
                buf[i + 2] = b
                buf[i + 3] = a
            elif da == 255:
                buf[i] = (r * a + buf[i] * ia + 127) // 255
                buf[i + 1] = (g * a + buf[i + 1] * ia + 127) // 255
                buf[i + 2] = (b * a + buf[i + 2] * ia + 127) // 255
            else:
                # general straight-alpha source-over
                af = a * (1.0 / 255.0)
                df = da * (1.0 / 255.0)
                of = af + df * (1.0 - af)
                ws = af / of
                wd = 1.0 - ws
                c0 = int(r * ws + buf[i] * wd + 0.5)
                c1 = int(g * ws + buf[i + 1] * wd + 0.5)
                c2 = int(b * ws + buf[i + 2] * wd + 0.5)
                buf[i] = 255 if c0 > 255 else c0
                buf[i + 1] = 255 if c1 > 255 else c1
                buf[i + 2] = 255 if c2 > 255 else c2
                buf[i + 3] = int(of * 255.0 + 0.5)
            i += 4


def _grad(t):
    """Backdrop vertical gradient color at fraction t in [0,1]."""
    return tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t + 0.5) for i in (0, 1, 2))


class BgOp(object):
    """Rounded-square backdrop with vertical gradient (drawn opaquely)."""

    def __init__(self, cv, d):
        self.cv = cv
        self.L = d["L"] * S
        self.r = d["bg_r"] * S

    def row(self, y):
        sp = rr_span(0.0, 0.0, self.L, self.L, self.r, y + 0.5)
        if sp is None:
            return
        c = _grad((y + 0.5) / self.L)
        self.cv.blend_span(y, sp[0], sp[1], (c[0], c[1], c[2], 255))


class ScanOp(object):
    """Faint 45-degree scanlines, pre-blended against the gradient row color."""

    def __init__(self, cv, d):
        self.cv = cv
        self.L = d["L"] * S
        self.r = d["bg_r"] * S
        self.period = int(round(SCAN_PERIOD * S))
        self.width = int(round(SCAN_WIDTH * S))

    def row(self, y):
        sp = rr_span(0.0, 0.0, self.L, self.L, self.r, y + 0.5)
        if sp is None:
            return
        bgc = _grad((y + 0.5) / self.L)
        a = SCAN_ALPHA
        ia = 255 - a
        col = ((255 * a + bgc[0] * ia + 127) // 255,
               (255 * a + bgc[1] * ia + 127) // 255,
               (255 * a + bgc[2] * ia + 127) // 255,
               255)
        ix0 = math.ceil(sp[0] - 0.5)
        ix1 = math.ceil(sp[1] - 0.5)
        if ix0 < 0:
            ix0 = 0
        if ix1 > self.cv.w:
            ix1 = self.cv.w
        if ix1 <= ix0:
            return
        P = self.period
        Wd = self.width
        # "on" iff (ix + y) mod P < Wd  ->  on-spans start at multiples of P
        s = ((ix0 + y + P - 1) // P) * P
        while s - y < ix1:
            a0 = s - y
            a1 = a0 + Wd
            if a1 > ix1:
                a1 = ix1
            self.cv.blend_span(y, a0, a1, col)
            s += P


class FillRR(object):
    """Filled rounded rectangle."""

    def __init__(self, cv, x0, y0, x1, y1, r, color):
        self.cv = cv
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.r = r
        self.color = color

    def row(self, y):
        sp = rr_span(self.x0, self.y0, self.x1, self.y1, self.r, y + 0.5)
        if sp is not None:
            self.cv.blend_span(y, sp[0], sp[1], self.color)


class StrokeRR(object):
    """Centered stroke ring around a rounded rect (border + glow passes)."""

    def __init__(self, cv, x0, y0, x1, y1, r, t, color):
        self.cv = cv
        self.x0, self.y0, self.x1, self.y1 = x0, y0, x1, y1
        self.r = r
        self.t = t
        self.color = color

    def row(self, y):
        h = self.t * 0.5
        yt = y + 0.5
        o = rr_span(self.x0 - h, self.y0 - h, self.x1 + h, self.y1 + h,
                    self.r + h, yt)
        if o is None:
            return
        i = rr_span(self.x0 + h, self.y0 + h, self.x1 - h, self.y1 - h,
                    self.r - h, yt)
        if i is None:
            self.cv.blend_span(y, o[0], o[1], self.color)
            return
        self.cv.blend_span(y, o[0], i[0], self.color)
        self.cv.blend_span(y, i[1], o[1], self.color)


class BoltOp(object):
    """Lightning bolt polygon (even-odd fill) with a distance-field soft glow."""

    def __init__(self, cv, bx, by, side, color=WHITE + (255,)):
        self.cv = cv
        pts = [(bx + u * side, by + v * side) for (u, v) in BOLT_UNIT]
        self.edges = []
        m = len(pts)
        for k in range(m):
            ax, ay = pts[k]
            cx, cy = pts[(k + 1) % m]
            dx = cx - ax
            dy = cy - ay
            self.edges.append((ax, ay, dx, dy, dx * dx + dy * dy))
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        self.xmin, self.xmax = min(xs), max(xs)
        self.ymin, self.ymax = min(ys), max(ys)
        self.g = BOLT_GLOW * side
        self.g2 = self.g * self.g
        self.strength = BOLT_GLOW_A
        self.color = color

    def row(self, y):
        yt = y + 0.5
        g = self.g
        if yt < self.ymin - g or yt > self.ymax + g:
            return
        # even-odd crossings at this scanline (horizontal edges are skipped)
        xs = []
        for (ax, ay, dx, dy, _l2) in self.edges:
            if (ay <= yt < ay + dy) or (ay + dy <= yt < ay):
                xs.append(ax + (yt - ay) * dx / dy)
        xs.sort()
        npairs = len(xs) // 2
        cv = self.cv
        ix0 = math.ceil(self.xmin - g - 0.5)
        ix1 = math.ceil(self.xmax + g - 0.5)
        if ix0 < 0:
            ix0 = 0
        if ix1 > cv.w:
            ix1 = cv.w
        if ix1 <= ix0:
            return
        r, gc, bc, _a = self.color
        g2 = self.g2
        strength = self.strength
        edges = self.edges
        sqrt = math.sqrt
        for ix in range(ix0, ix1):
            xt = ix + 0.5
            inside = False
            for k in range(npairs):
                if xs[2 * k] <= xt < xs[2 * k + 1]:
                    inside = True
                    break
            if inside:
                cv.blend_span_i(y, ix, ix + 1, (r, gc, bc, 255))
                continue
            # soft glow: linear falloff with distance to the polygon boundary
            d2 = 1e30
            for (ax, ay, dx, dy, l2) in edges:
                if l2 <= 0.0:
                    dd = (xt - ax) ** 2 + (yt - ay) ** 2
                else:
                    tt = ((xt - ax) * dx + (yt - ay) * dy) / l2
                    if tt < 0.0:
                        tt = 0.0
                    elif tt > 1.0:
                        tt = 1.0
                    dd = (xt - (ax + tt * dx)) ** 2 + (yt - (ay + tt * dy)) ** 2
                if dd < d2:
                    d2 = dd
            if d2 < g2:
                al = int(strength * (1.0 - sqrt(d2) / g) + 0.5)
                if al > 0:
                    cv.blend_span_i(y, ix, ix + 1, (r, gc, bc, al))


# ---------------------------------------------------------------------------
# geometry + scene assembly
# ---------------------------------------------------------------------------

def geo_192():
    """Icon geometry at 192px: grid inset 14%, gap 6%, derived tile metrics."""
    L = 192.0
    inset = 0.14 * L
    gap = 0.06 * L
    tile = (L - 2 * inset - 2 * gap) / 3.0        # 38.4
    return {
        "L": L,
        "bg_r": 0.18 * L,                          # 34.56
        "origin": (inset, inset),
        "gap": gap,
        "tile": tile,
        "tile_r": 0.08 * tile,                      # 8% of tile side
        "border": 0.045 * tile,                     # ~4.5% of tile side
    }


def geo_adaptive():
    """Adaptive fg geometry at 432px: grid fills central 55%, same proportions
    (gap:grid = 1/12 and tile:grid = 5/18, identical to the 192 icon)."""
    L = 432.0
    gs = 0.55 * L                                  # 237.6 = "about 237 px"
    gap = gs / 12.0                                # 19.8
    tile = (gs - 2 * gap) / 3.0                    # 66.0
    return {
        "L": L,
        "bg_r": 0.18 * L,                           # unused (no backdrop)
        "origin": ((L - gs) / 2.0, (L - gs) / 2.0),  # centered safe zone
        "gap": gap,
        "tile": tile,
        "tile_r": 0.08 * tile,
        "border": 0.045 * tile,
    }


def render_icon(d, with_background):
    """Render the full design at S*x supersampling; returns the Canvas."""
    sc = float(S)
    L4 = int(round(d["L"] * sc))
    clear = (0, 0, 0, 255) if with_background else (0, 0, 0, 0)
    cv = Canvas(L4, L4, clear)
    ops = []
    if with_background:
        ops.append(BgOp(cv, d))
        ops.append(ScanOp(cv, d))
        # thin outer rim highlight, stroke centered on a 1.25px-inset path
        ops.append(StrokeRR(cv, RIM_INSET * sc, RIM_INSET * sc,
                            (d["L"] - RIM_INSET) * sc,
                            (d["L"] - RIM_INSET) * sc,
                            (d["bg_r"] - RIM_INSET) * sc,
                            RIM_THICK * sc, RIM_COL + (210,)))
    ox, oy = d["origin"]
    tile, gap = d["tile"], d["gap"]
    rad, bord = d["tile_r"], d["border"]
    for r_i in range(3):
        for c_i in range(3):
            x0 = (ox + c_i * (tile + gap)) * sc
            y0 = (oy + r_i * (tile + gap)) * sc
            x1 = x0 + tile * sc
            y1 = y0 + tile * sc
            center = (r_i == 1 and c_i == 1)
            fill = (GOLD if center else TILE_FILL) + (255,)
            bordc = GOLD_BR if center else TEAL
            ops.append(FillRR(cv, x0, y0, x1, y1, rad * sc, fill))
            for mult, alpha in GLOW_PASSES:
                ops.append(StrokeRR(cv, x0, y0, x1, y1, rad * sc,
                                    mult * bord * sc, bordc + (alpha,)))
            if center:
                bi = bord * sc
                side = (tile - 2 * bord) * sc
                ops.append(BoltOp(cv, x0 + bi, y0 + bi, side))
    for y in range(L4):
        for op in ops:
            op.row(y)
    return cv


def downsample(cv, w, h):
    """Box-downsample the S*x straight-alpha canvas to w x h (premultiplied)."""
    buf = cv.buf
    w4 = cv.w
    stride = w4 * 4
    ns = S * S
    out = bytearray(w * h * 4)
    for oy in range(h):
        obase = oy * w * 4
        ybase = oy * S * stride
        for ox in range(w):
            sr = sg = sb = sa = 0
            i = ybase + ox * S * 4
            for _r in range(S):
                j = i
                for _c in range(S):
                    a = buf[j + 3]
                    if a:
                        sr += buf[j] * a
                        sg += buf[j + 1] * a
                        sb += buf[j + 2] * a
                        sa += a
                    j += 4
                i += stride
            o = obase + ox * 4
            if sa:
                c = (2 * sr + sa) // (2 * sa)
                out[o] = 255 if c > 255 else c
                c = (2 * sg + sa) // (2 * sa)
                out[o + 1] = 255 if c > 255 else c
                c = (2 * sb + sa) // (2 * sa)
                out[o + 2] = 255 if c > 255 else c
                out[o + 3] = (2 * sa + ns) // (2 * ns)
    return bytes(out)


def to_rgb(rgba, w, h):
    """Drop the alpha channel from an RGBA buffer."""
    out = bytearray(w * h * 3)
    j = 0
    for i in range(0, w * h * 4, 4):
        out[j] = rgba[i]
        out[j + 1] = rgba[i + 1]
        out[j + 2] = rgba[i + 2]
        j += 3
    return bytes(out)


# ---------------------------------------------------------------------------
# SVG mirror of icon_192
# ---------------------------------------------------------------------------

def build_svg():
    d = geo_192()
    bg_r = d["bg_r"]
    tile, rad, bord = d["tile"], d["tile_r"], d["border"]
    pos = [d["origin"][0] + i * (tile + d["gap"]) for i in range(3)]

    def f(v):
        s = ("%.3f" % float(v)).rstrip("0").rstrip(".")
        return s if s else "0"

    outer_rects = []
    for r_i in range(3):
        for c_i in range(3):
            if r_i == 1 and c_i == 1:
                continue
            outer_rects.append(
                '    <rect x="%s" y="%s" width="%s" height="%s" rx="%s"/>'
                % (f(pos[c_i]), f(pos[r_i]), f(tile), f(tile), f(rad)))
    outer_rects = "\n".join(outer_rects)
    center_rect = ('    <rect x="%s" y="%s" width="%s" height="%s" rx="%s"/>'
                   % (f(pos[1]), f(pos[1]), f(tile), f(tile), f(rad)))

    box_x = pos[1] + bord
    box_s = tile - 2 * bord
    bolt_pts = " ".join("%s,%s" % (f(box_x + u * box_s), f(box_x + v * box_s))
                        for (u, v) in BOLT_UNIT)
    w1, w2, w0 = f(3.0 * bord), f(2.0 * bord), f(bord)
    p1, ts, rs = f(pos[1]), f(tile), f(rad)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <defs>
    <linearGradient id="bgGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0B131B"/>
      <stop offset="1" stop-color="#101B26"/>
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="1.3"/>
    </filter>
    <filter id="glowBolt" x="-100%" y="-100%" width="300%" height="300%">
      <feGaussianBlur stdDeviation="1.6"/>
    </filter>
    <pattern id="scan" patternUnits="userSpaceOnUse" width="12" height="12" patternTransform="rotate(45)">
      <rect width="12" height="4" fill="#FFFFFF" fill-opacity="0.05"/>
    </pattern>
  </defs>

  <!-- dark rounded-square backdrop, vertical gradient, scanlines, rim -->
  <rect x="0" y="0" width="192" height="192" rx="{f(bg_r)}" ry="{f(bg_r)}" fill="url(#bgGrad)"/>
  <rect x="0" y="0" width="192" height="192" rx="{f(bg_r)}" ry="{f(bg_r)}" fill="url(#scan)"/>
  <rect x="1.25" y="1.25" width="189.5" height="189.5" rx="{f(bg_r - 1.25)}" ry="{f(bg_r - 1.25)}"
        fill="none" stroke="#1E2A36" stroke-width="2.5" stroke-opacity="0.82"/>

  <!-- 3x3 electric floor-tile grid: fills, teal glow passes, crisp borders -->
  <g fill="#10181F">
{outer_rects}
  </g>
  <g fill="none" stroke="#2EE6C8" stroke-width="{w1}" stroke-opacity="0.16" filter="url(#glow)">
{outer_rects}
  </g>
  <g fill="none" stroke="#2EE6C8" stroke-width="{w2}" stroke-opacity="0.38" filter="url(#glow)">
{outer_rects}
  </g>
  <g fill="none" stroke="#2EE6C8" stroke-width="{w0}">
{outer_rects}
  </g>

  <!-- charged gold center tile -->
  <rect x="{p1}" y="{p1}" width="{ts}" height="{ts}" rx="{rs}" fill="#FFC53D"/>
  <g fill="none" stroke="#FFE9A8" stroke-width="{w1}" stroke-opacity="0.16" filter="url(#glow)">
{center_rect}
  </g>
  <g fill="none" stroke="#FFE9A8" stroke-width="{w2}" stroke-opacity="0.38" filter="url(#glow)">
{center_rect}
  </g>
  <rect x="{p1}" y="{p1}" width="{ts}" height="{ts}" rx="{rs}"
        fill="none" stroke="#FFE9A8" stroke-width="{w0}"/>

  <!-- white lightning bolt with soft glow -->
  <polygon points="{bolt_pts}" fill="#FFFFFF" fill-opacity="0.39" filter="url(#glowBolt)"/>
  <polygon points="{bolt_pts}" fill="#FFFFFF"/>
</svg>
'''


# ---------------------------------------------------------------------------
# verification: manual PNG parse + content sanity checks
# ---------------------------------------------------------------------------

def _cls(r, g, b, a):
    """Map a pixel to a preview character."""
    if a < 40 or r + g + b < 15:
        return " "          # transparent / pure black (outside rounded backdrop)
    if r > 235 and g > 235 and b > 235:
        return "#"          # white bolt
    if r > 180 and g > 140 and r > b + 60:
        return "G"          # gold (fill / border / bolt glow over gold)
    if g > 120 and b > 120 and g > r + 40:
        return "T"          # teal (border / glow)
    if r < 40 and g < 50 and b < 60:
        return "."          # dark backdrop / tile fill
    return "+"              # blended glow / anti-aliased edge


def preview_lines(pix, w, h, n, cells=24):
    rows = ["preview %dx%d ('#'=white bolt  G=gold  T=teal  .=dark  ' '=empty):"
            % (cells, cells)]
    for cy in range(cells):
        sy = min(h - 1, int((cy + 0.5) * h / cells))
        chars = []
        for cx in range(cells):
            sx = min(w - 1, int((cx + 0.5) * w / cells))
            i = (sy * w + sx) * n
            chars.append(_cls(pix[i], pix[i + 1], pix[i + 2],
                              pix[i + 3] if n == 4 else 255))
        rows.append("        |" + "".join(chars) + "|")
    return rows


def region_preview(pix, w, h, n, x0, y0, size, cells=24, title=""):
    """High-res preview of a square region (shows the bolt zigzag clearly)."""
    rows = [title]
    for cy in range(cells):
        chars = []
        for cx in range(cells):
            sx = min(w - 1, int(x0 + (cx + 0.5) * size / cells))
            sy = min(h - 1, int(y0 + (cy + 0.5) * size / cells))
            i = (sy * w + sx) * n
            chars.append(_cls(pix[i], pix[i + 1], pix[i + 2],
                              pix[i + 3] if n == 4 else 255))
        rows.append("        |" + "".join(chars) + "|")
    return rows


def sim48_lines(pix, w, h, n):
    """Box-averaged 48x48 render: what a launcher shows at 48 px."""
    rows = ["48px launcher simulation (48x48 box average of the 192px icon):"]
    step = w // 48
    d = step * step
    for cy in range(48):
        chars = []
        for cx in range(48):
            sr = sg = sb = 0
            for yy in range(cy * step, cy * step + step):
                base = yy * w * n
                for xx in range(cx * step, cx * step + step):
                    i = base + xx * n
                    sr += pix[i]
                    sg += pix[i + 1]
                    sb += pix[i + 2]
            chars.append(_cls(sr // d, sg // d, sb // d, 255))
        rows.append("        |" + "".join(chars) + "|")
    return rows


def check_192(pix, w, h):
    n = 3
    lines = []
    if tuple(pix[0:3]) != (0, 0, 0):
        raise AssertionError("corner (0,0)=%s, expected rgb(0,0,0) outside the rounded backdrop"
                             % (tuple(pix[0:3]),))
    lines.append("content: corner (0,0)=rgb(0,0,0) [pure black outside rounded backdrop] - OK")
    ci = ((96 * w) + 96) * n
    c = (pix[ci], pix[ci + 1], pix[ci + 2])
    if min(c) < 240:
        raise AssertionError("center (96,96)=%s, expected white bolt core" % (c,))
    lines.append("content: center (96,96)=rgb%s [white bolt core] - OK" % (c,))
    bi = ((12 * w) + 96) * n
    b = (pix[bi], pix[bi + 1], pix[bi + 2])
    if max(b) >= 60:
        raise AssertionError("backdrop sample (96,12)=%s, expected dark backdrop" % (b,))
    lines.append("content: backdrop sample (96,12)=rgb%s [dark gradient + scanlines] - OK" % (b,))
    gi = ((71 * w) + 96) * n
    gp = (pix[gi], pix[gi + 1], pix[gi + 2])
    if max(gp) >= 60:
        raise AssertionError("tile gap sample (96,71)=%s, expected dark gap" % (gp,))
    lines.append("content: tile-gap sample (96,71)=rgb%s [dark gap between tiles] - OK" % (gp,))
    teal = gold = white = 0
    wt = (255, 255, 255)
    for i in range(0, w * h * n, n):
        p = (pix[i], pix[i + 1], pix[i + 2])
        if p == TEAL:
            teal += 1
        elif p == GOLD:
            gold += 1
        elif p == wt:
            white += 1
    if teal < 100 or gold < 100 or white < 30:
        raise AssertionError("exact-color counts teal=%d gold=%d white=%d"
                             " (need >=100/>=100/>=30)" % (teal, gold, white))
    lines.append("content: exact-color pixels: teal %d, gold %d, white %d "
                 "(thresholds 100/100/30) - OK" % (teal, gold, white))
    lines.extend(preview_lines(pix, w, h, n))
    lines.extend(region_preview(pix, w, h, n, 76.0, 76.0, 40.0, 24,
                                "center-tile zoom 24x24 over [76,116]^2 "
                                "(gold tile, borders, white bolt):"))
    lines.extend(sim48_lines(pix, w, h, n))
    return lines


def check_fg(pix, w, h):
    n = 4
    lines = []
    if pix[3] != 0:
        raise AssertionError("corner (0,0) alpha=%d, expected 0 (fully transparent)" % pix[3])
    lines.append("content: corner (0,0) alpha=0 [fully transparent background] - OK")
    ci = ((216 * w) + 216) * n
    c = (pix[ci], pix[ci + 1], pix[ci + 2], pix[ci + 3])
    if min(c[:3]) < 240 or c[3] != 255:
        raise AssertionError("center (216,216)=%s, expected opaque white bolt core" % (c,))
    lines.append("content: center (216,216)=rgba%s [opaque white bolt core] - OK" % (c,))
    minx, maxx, miny, maxy = w, -1, h, -1
    transp = teal = gold = white = 0
    wt = (255, 255, 255)
    for y in range(h):
        base = y * w * n
        for x in range(w):
            i = base + x * n
            a = pix[i + 3]
            if a == 0:
                transp += 1
                continue
            if x < minx:
                minx = x
            if x > maxx:
                maxx = x
            if y < miny:
                miny = y
            if y > maxy:
                maxy = y
            if a == 255:
                p = (pix[i], pix[i + 1], pix[i + 2])
                if p == TEAL:
                    teal += 1
                elif p == GOLD:
                    gold += 1
                elif p == wt:
                    white += 1
    if maxx < 0:
        raise AssertionError("no non-transparent pixels found")
    lw = maxx - minx + 1
    lh = maxy - miny + 1
    cx = (minx + maxx) / 2.0
    cy = (miny + maxy) / 2.0
    if not (230 <= lw <= 254) or not (230 <= lh <= 254):
        raise AssertionError("logo bbox %dx%d px, expected ~247 (55%% grid + glow)" % (lw, lh))
    if abs(cx - 215.5) > 4 or abs(cy - 215.5) > 4:
        raise AssertionError("logo bbox center (%.1f,%.1f) not centered on 215.5" % (cx, cy))
    if minx < 90 or maxx > 342 or miny < 90 or maxy > 342:
        raise AssertionError("logo bbox x[%d..%d] y[%d..%d] exceeds safe zone"
                             % (minx, maxx, miny, maxy))
    lines.append("content: logo bbox x[%d..%d] y[%d..%d] = %dx%d px, centered at (%.1f,%.1f) "
                 "[grid spans central 55%% = 237.6px + faint glow] - OK"
                 % (minx, maxx, miny, maxy, lw, lh, cx, cy))
    if teal < 100 or gold < 100 or white < 100:
        raise AssertionError("exact-color counts teal=%d gold=%d white=%d (need >=100 each)"
                             % (teal, gold, white))
    lines.append("content: exact-color pixels: teal %d, gold %d, white %d "
                 "(threshold 100 each) - OK" % (teal, gold, white))
    frac = transp / float(w * h)
    if frac < 0.30:
        raise AssertionError("only %.1f%% fully transparent pixels" % (100.0 * frac,))
    lines.append("content: %.1f%% of canvas fully transparent (alpha=0) - OK" % (100.0 * frac,))
    lines.extend(preview_lines(pix, w, h, n))
    lines.extend(region_preview(pix, w, h, n, 183.0, 183.0, 66.0, 24,
                                "center-tile zoom 24x24 over [183,249]^2 "
                                "(gold tile, borders, white bolt):"))
    return lines


def check_bg(pix, w, h):
    if bytes(pix) != bytes(BG_ADAPT) * (w * h):
        raise AssertionError("pixels are not solid #0B131C")
    return ["content: all %d pixels = rgb(11,19,28) #0B131C [solid color layer] - OK" % (w * h)]


def verify_png(path, exp_w, exp_h, exp_ct, pixel_check=None):
    """Re-read a PNG, manually parse chunks/IHDR, assert structure + content."""
    rel = os.path.relpath(path, ROOT)
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != PNG_SIG:
        raise AssertionError("bad PNG signature")
    pos = 8
    chunks = []
    while pos < len(data):
        if pos + 8 > len(data):
            raise AssertionError("truncated chunk header at offset %d" % pos)
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        cstart = pos + 8
        cend = cstart + ln
        if cend + 4 > len(data):
            raise AssertionError("truncated chunk %r" % ctype)
        cdata = data[cstart:cend]
        (crc_stored,) = struct.unpack(">I", data[cend:cend + 4])
        if zlib.crc32(ctype + cdata) & 0xFFFFFFFF != crc_stored:
            raise AssertionError("CRC32 mismatch in chunk %r" % ctype)
        chunks.append((ctype, cdata))
        pos = cend + 4
    if pos != len(data):
        raise AssertionError("trailing bytes after IEND")
    names = [c[0] for c in chunks]
    if names[0] != b"IHDR" or names[-1] != b"IEND" or b"IDAT" not in names:
        raise AssertionError("chunk stream must be IHDR..IDAT..IEND")
    ihdr = chunks[0][1]
    if len(ihdr) != 13:
        raise AssertionError("IHDR length %d != 13" % len(ihdr))
    w, h, depth, ct, comp, filt, inter = struct.unpack(">IIBBBBB", ihdr)
    if (w, h) != (exp_w, exp_h):
        raise AssertionError("dimensions %dx%d, expected %dx%d" % (w, h, exp_w, exp_h))
    if ct != exp_ct:
        raise AssertionError("color type %d, expected %d" % (ct, exp_ct))
    if depth != 8 or comp != 0 or filt != 0 or inter != 0:
        raise AssertionError("unsupported IHDR fields (depth=%d comp=%d filt=%d inter=%d)"
                             % (depth, comp, filt, inter))
    idat = b"".join(c[1] for c in chunks if c[0] == b"IDAT")
    raw = zlib.decompress(idat)
    n = 3 if ct == 2 else 4
    expected = h * (1 + w * n)
    if len(raw) != expected:
        raise AssertionError("IDAT inflates to %d bytes, expected %d" % (len(raw), expected))
    stride = 1 + w * n
    pix = bytearray(w * h * n)
    for yy in range(h):
        if raw[yy * stride] != 0:
            raise AssertionError("scanline %d filter byte != 0" % yy)
        pix[yy * w * n:(yy + 1) * w * n] = raw[yy * stride + 1:(yy + 1) * stride]
    extra = []
    if pixel_check is not None:
        extra = pixel_check(bytes(pix), w, h) or []
    ctn = "RGB" if ct == 2 else "RGBA"
    print("[ok ] %s: %d bytes | IHDR %dx%d color_type=%d (%s) bit_depth=8 | "
          "%d chunks, all CRCs OK | IDAT inflates to %d bytes (expected %d)"
          % (rel, len(data), w, h, ct, ctn, len(chunks), len(raw), expected))
    for line in extra:
        print("        " + line)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    t0 = time.time()
    os.makedirs(ICONS_DIR, exist_ok=True)
    print("=" * 76)
    print('Electric Tile Challenge 3D - procedural icon set generator (pure stdlib)')
    print("=" * 76)
    print("project root : %s" % ROOT)
    print("supersampling: render %dx, box-downsample %dx%d" % (S, S, S))
    print()

    # 1. icon.svg -----------------------------------------------------------
    svg = build_svg()
    with open(SVG_PATH, "w", encoding="utf-8") as fh:
        fh.write(svg)
    print("[out] %-42s %7d bytes  (192x192 viewBox, mirrors icon_192 design)"
          % ("icon.svg", len(svg.encode("utf-8"))))

    # 2. icon_192.png (RGB, full design with backdrop) ----------------------
    print("[gen ] icon_192.png: rasterizing on %dx%d canvas ..."
          % (192 * S, 192 * S))
    t = time.time()
    cv = render_icon(geo_192(), True)
    rgba = downsample(cv, 192, 192)
    nb = write_png(PNG_192, 192, 192, 2, to_rgb(rgba, 192, 192))
    print("[out] %-42s %7d bytes  (%.1fs)"
          % ("assets/icons/icon_192.png", nb, time.time() - t))

    # 3. icon_adaptive_fg_432.png (RGBA, transparent, central 55% logo) ------
    print("[gen ] icon_adaptive_fg_432.png: rasterizing on %dx%d canvas ..."
          % (432 * S, 432 * S))
    t = time.time()
    cv = render_icon(geo_adaptive(), False)
    rgba = downsample(cv, 432, 432)
    nb = write_png(PNG_FG, 432, 432, 6, rgba)
    print("[out] %-42s %7d bytes  (%.1fs)"
          % ("assets/icons/icon_adaptive_fg_432.png", nb, time.time() - t))

    # 4. icon_adaptive_bg_432.png (RGB, solid #0B131C) ------------------------
    # constant color: supersampling-invariant, so emit the solid buffer directly
    nb = write_png(PNG_BG, 432, 432, 2, bytes(BG_ADAPT) * (432 * 432))
    print("[out] %-42s %7d bytes  (solid #0B131C)"
          % ("assets/icons/icon_adaptive_bg_432.png", nb))

    # verification -----------------------------------------------------------
    print()
    print("-" * 76)
    print("verification: re-reading generated PNGs (manual chunk/IHDR parse)")
    print("-" * 76)
    failed = False
    for path, w, h, ct, checker in (
            (PNG_192, 192, 192, 2, check_192),
            (PNG_FG, 432, 432, 6, check_fg),
            (PNG_BG, 432, 432, 2, check_bg)):
        try:
            verify_png(path, w, h, ct, checker)
        except Exception as exc:
            failed = True
            print("[FAIL] %s: %s" % (os.path.relpath(path, ROOT), exc))
        print()

    print("=" * 76)
    if failed:
        print("RESULT: VERIFICATION FAILED (see [FAIL] lines above)")
        return 1
    print("RESULT: ALL PNG FILES VERIFIED OK - 4 deliverables written, %.1fs total"
          % (time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
