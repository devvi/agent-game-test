#!/usr/bin/env python3
"""E2E screenshot anti-fake-evidence analyzer (pure stdlib, PNG-native).

Verifies a screenshot PNG is REAL rendered content, not a black/frozen frame.
Four assertions (flag-gated):
  1. non-black     : near-black pixel ratio <= --max-black-ratio (default 0.50)
  2. color count   : distinct colors >= --min-colors (default 3)
  3. theme color   : --theme RRGGBB present within RGB tolerance 32
  4. frame diff    : --diff-with FILE — mean luminance delta >= --min-delta

PNG decoding is implemented with zlib+struct only (no PIL/sips) so it runs in
CI (ubuntu) and on the Mac mini alike. Supports bit depths 8/16 and color
types 0/2/3/4/6.

Usage:
  python3 scripts/e2e/analyze_bmp.py shot.png [--min-colors N] [--max-black-ratio R]
      [--theme 4a90d9] [--diff-with prev.png] [--min-delta D]
      [--diff-ratio R] [--pixel-delta D] [--name LABEL] [--json]
Exit: 0 = all enabled assertions pass, 1 = any fail.
"""
from __future__ import annotations  # py3.9/3.11 dual compat (lazy annotations)

import json
import struct
import sys
import zlib
from pathlib import Path

# ── PNG decoding (pure stdlib) ────────────────────────────────────────────


class PNGError(Exception):
    pass


def _read_png(path: str) -> tuple[int, int, list]:
    """Decode PNG → (width, height, rows) where rows are bytearrays of RGBA."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise PNGError("not a PNG file")
    pos = 8
    width = height = bit_depth = color_type = 0
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
            if chunk[10] != 0:
                raise PNGError("interlaced PNG not supported")
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
        pos += 12 + length
    if not idat:
        raise PNGError("no IDAT chunk")

    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    bpp = max(1, channels * bit_depth // 8)
    stride = (width * channels * bit_depth + 7) // 8

    rows: list[bytearray] = []
    prev = bytearray(stride)
    off = 0
    for _y in range(height):
        filt = raw[off]
        off += 1
        line = bytearray(raw[off:off + stride])
        off += stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if filt == 1:      # Sub
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:    # Up
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:    # Average
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif filt == 4:    # Paeth
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
            elif filt != 0:
                raise PNGError(f"unknown filter {filt}")
        rows.append(line)
        prev = line

    # Convert to RGBA rows (8-bit)
    out: list[bytearray] = []
    step = bit_depth // 8
    for line in rows:
        rgba = bytearray(width * 4)
        for x in range(width):
            base = x * channels * step
            if color_type == 3:  # palette — not expected for screenshots
                raise PNGError("palette PNG not supported")
            if color_type in (0, 4):  # gray
                g = line[base]
                rgba[x * 4:x * 4 + 4] = bytes((g, g, g, 255))
            else:  # 2 or 6 RGB(A)
                r = line[base]
                g = line[base + step]
                b = line[base + 2 * step]
                a = line[base + 3 * step] if channels == 4 else 255
                rgba[x * 4:x * 4 + 4] = bytes((r, g, b, a))
        out.append(rgba)
    return width, height, out


# ── Stats ──────────────────────────────────────────────────────────────────


def _luma(r: int, g: int, b: int) -> float:
    return 0.299 * r + 0.587 * g + 0.114 * b


def analyze(path: str) -> dict:
    w, h, rows = _read_png(path)
    tot = [0, 0, 0]
    n = 0
    black = 0
    colors: set[tuple[int, int, int]] = set()
    lumas: list[float] = []
    # Sample every 3rd pixel for speed; full pass for small images
    step = 1 if w * h <= 262144 else 3
    for y in range(0, h, step):
        row = rows[y]
        for x in range(0, w, step):
            i = x * 4
            r, g, b = row[i], row[i + 1], row[i + 2]
            tot[0] += r
            tot[1] += g
            tot[2] += b
            n += 1
            if r < 8 and g < 8 and b < 8:
                black += 1
            colors.add((r >> 4, g >> 4, b >> 4))  # 16-level buckets
            lumas.append(_luma(r, g, b))
    avg = (tot[0] / n, tot[1] / n, tot[2] / n)
    black_ratio = black / n
    mean_luma = sum(lumas) / len(lumas)
    return {
        "path": path,
        "width": w,
        "height": h,
        "avg_rgb": tuple(round(v, 1) for v in avg),
        "color_buckets": len(colors),
        "black_ratio": round(black_ratio, 4),
        "mean_luma": round(mean_luma, 1),
        "n_sampled": n,
    }


def _luma_delta(path_a: str, path_b: str) -> float:
    wa, ha, ra = _read_png(path_a)
    wb, hb, rb = _read_png(path_b)
    if wa != wb or ha != hb:
        return float("inf")  # different sizes = definitely different frames
    step = 3
    total = 0.0
    n = 0
    for y in range(0, ha, step):
        ra_ = ra[y]
        rb_ = rb[y]
        for x in range(0, wa, step):
            i = x * 4
            la = _luma(ra_[i], ra_[i + 1], ra_[i + 2])
            lb = _luma(rb_[i], rb_[i + 1], rb_[i + 2])
            total += abs(la - lb)
            n += 1
    return total / n if n else 0.0


def _changed_ratio(path_a: str, path_b: str, pixel_delta: float = 20.0) -> float:
    """Fraction of sampled pixels whose |Δluma| exceeds pixel_delta.

    Robust to neon dark-background games where the mean Δluma stays tiny
    (large near-black areas dilute the average) while a significant share
    of pixels genuinely change (#371: Δluma=0.5 but 1.009% pixels changed).
    Different sizes = definitely different frames → 1.0 (mirrors _luma_delta
    returning inf). Sampling step matches _luma_delta (step=3).
    """
    wa, ha, ra = _read_png(path_a)
    wb, hb, rb = _read_png(path_b)
    if wa != wb or ha != hb:
        return 1.0
    step = 3
    changed = 0
    n = 0
    for y in range(0, ha, step):
        ra_ = ra[y]
        rb_ = rb[y]
        for x in range(0, wa, step):
            i = x * 4
            la = _luma(ra_[i], ra_[i + 1], ra_[i + 2])
            lb = _luma(rb_[i], rb_[i + 1], rb_[i + 2])
            if abs(la - lb) > pixel_delta:
                changed += 1
            n += 1
    return changed / n if n else 0.0


def _theme_present(path: str, hex_color: str, tol: int = 32) -> bool:
    r, g, b = (int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    _w, _h, rows = _read_png(path)
    for y in range(0, _h, 5):
        row = rows[y]
        for x in range(0, _w, 5):
            i = x * 4
            if (abs(row[i] - r) <= tol and abs(row[i + 1] - g) <= tol
                    and abs(row[i + 2] - b) <= tol):
                return True
    return False


# ── CLI ────────────────────────────────────────────────────────────────────


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    path = args[0]
    opts: dict[str, object] = {
        "--min-colors": None, "--max-black-ratio": None, "--theme": None,
        "--diff-with": None, "--min-delta": None, "--name": None,
        "--diff-ratio": None, "--pixel-delta": None,
        "--json": False,
    }

    def _s(arg: str) -> str | None:
        v = opts.get(arg)
        return v if isinstance(v, str) else None

    def _f(arg: str, default: float | None) -> float | None:
        v = opts.get(arg)
        if v is None:
            return default
        try:
            return float(v)
        except (TypeError, ValueError):
            return default

    def _i(arg: str, default: int) -> int:
        v = opts.get(arg)
        return int(v) if isinstance(v, (int, float, str)) and str(v) else default
    i = 1
    while i < len(args):
        a = args[i]
        if a in opts and i + 1 < len(args):
            opts[a] = args[i + 1]
            i += 2
        elif a == "--json":
            opts["--json"] = True
            i += 1
        else:
            print(f"unknown arg: {a}")
            return 2

    try:
        st = analyze(path)
    except (PNGError, OSError, struct.error, zlib.error) as e:
        print(f"❌ {path}: decode failed — {e}")
        return 1

    name = _s("--name") or Path(path).name
    fails: list[str] = []
    passes: list[str] = []

    # 1. non-black
    max_black = _f("--max-black-ratio", 0.50)
    if st["black_ratio"] <= max_black:
        passes.append(f"non-black (black {st['black_ratio']*100:.1f}% <= {max_black*100:.0f}%)")
    else:
        fails.append(f"near-black ratio {st['black_ratio']*100:.1f}% > {max_black*100:.0f}%")

    # 2. color count
    min_colors = _i("--min-colors", 3)
    if st["color_buckets"] >= min_colors:
        passes.append(f"colors {st['color_buckets']} >= {min_colors}")
    else:
        fails.append(f"only {st['color_buckets']} color buckets (< {min_colors}) — flat/frozen frame")

    # 3. theme color
    theme_arg = _s("--theme")
    if theme_arg:
        theme = theme_arg.lstrip("#")
        if _theme_present(path, theme):
            passes.append(f"theme #{theme} present")
        else:
            fails.append(f"theme #{theme} NOT found")

    # 4. frame diff — mean Δluma OR changed-pixel ratio (dual channel)
    diff_with = _s("--diff-with")
    if diff_with:
        min_delta = _f("--min-delta", 5.0)
        delta = _luma_delta(path, diff_with)
        diff_ratio_arg = _f("--diff-ratio", None)   # None → ratio channel off
        ratio = 0.0
        ratio_ok = False
        if diff_ratio_arg is not None:
            ratio = _changed_ratio(path, diff_with, _f("--pixel-delta", 20.0))
            ratio_ok = ratio >= diff_ratio_arg
        ratio_txt = (f" 变化像素占比 {ratio*100:.3f}% >= {diff_ratio_arg*100:.3f}%"
                     if diff_ratio_arg is not None else "")
        if delta >= min_delta or ratio_ok:
            if delta >= min_delta:
                passes.append(f"diff vs {Path(diff_with).name}: Δluma={delta:.1f} >= {min_delta}"
                              + ratio_txt)
            else:
                passes.append(f"diff vs {Path(diff_with).name}: Δluma={delta:.1f} < {min_delta}"
                              + f" 但 {ratio_txt.lstrip()}")
        else:
            fails.append(f"diff vs {Path(diff_with).name}: Δluma={delta:.1f} < {min_delta}"
                         + (f" 且 变化像素占比 {ratio*100:.3f}% < {diff_ratio_arg*100:.3f}%"
                            if diff_ratio_arg is not None else "") + " — frozen?")

    line = (f"{path} [{name}]: {st['width']}x{st['height']} "
            f"avgRGB={st['avg_rgb']} colors={st['color_buckets']} "
            f"black={st['black_ratio']*100:.1f}% luma={st['mean_luma']}")
    if opts["--json"]:
        print(json.dumps({**st, "name": name, "passes": passes, "fails": fails}))
    else:
        print(line)
        for p in passes:
            print(f"  ✅ {p}")
        for f in fails:
            print(f"  ❌ {f}")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
