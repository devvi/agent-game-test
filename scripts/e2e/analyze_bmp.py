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
      [--diff-ratio R] [--pixel-delta D] [--name LABEL]
      [--visual-config vcfg.json] [--json]
Exit: 0 = all enabled assertions pass, 1 = any fail.
"""
from __future__ import annotations  # py3.9/3.11 dual compat (lazy annotations)

import json
import math
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



# ── Region assertions (visual regression, #466) ────────────────────────────
# Shot-level `visual` config from e2e_shots.json drives these (Approach A,
# DESIGN 466 §3.1). Pure stdlib, same PNG decode as the 4-fold assertions.


def _parse_hex_color(s) -> tuple | None:
    """Parse 'RRGGBB' (optional leading '#') → (r, g, b) tuple.
    Returns None when missing or unparseable."""
    if not s:
        return None
    t = str(s).strip().lstrip("#")
    if len(t) != 6:
        return None
    try:
        return (int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16))
    except ValueError:
        return None


def region_stats(rows, x0, y0, x1, y1, step=1, bg_color=None, bg_min_dist=24):
    """Sample region pixels → (n_total, n_nonblack, color_bucket_counter).

    Color buckets use the same 16-level granularity as global analyze()
    (r>>4, g>>4, b>>4). bg_color=None keeps the old near-black rule (r<8 and
    g<8 and b<8). bg_color set → a pixel is non-background iff its RGB distance
    from bg_color is >= bg_min_dist, so the bg itself is NOT foreground
    (#476: post-#464 BG_COLOR (10,10,18) counted under the old rule → ratio 100%).
    """
    h = len(rows)
    w = len(rows[0]) // 4 if rows else 0
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, x1), min(h, y1)
    n_total = 0
    n_nonblack = 0
    buckets = {}
    for y in range(y0, y1, step):
        row = rows[y]
        for x in range(x0, x1, step):
            i = x * 4
            r, g, b = row[i], row[i + 1], row[i + 2]
            n_total += 1
            if bg_color is not None:
                if rgb_distance((r, g, b), bg_color) >= bg_min_dist:
                    n_nonblack += 1
            elif not (r < 8 and g < 8 and b < 8):
                n_nonblack += 1
            key = (r >> 4, g >> 4, b >> 4)
            buckets[key] = buckets.get(key, 0) + 1
    return n_total, n_nonblack, buckets


def dominant_color(rows, x0, y0, x1, y1, exclude_buckets=None,
                   fallback_to_most_common=False):
    """Region dominant color = mode of 16-level color buckets, excluding keys
    in exclude_buckets (default {(0,0,0)} — the near-black bucket; bg-relative
    callers also exclude the bg bucket, e.g. (0,0,1) for #0a0a12). Returns the
    bucket's representative (r,g,b) (lower bound of the bucket) or None when
    every bucket is excluded. With fallback_to_most_common, an all-excluded
    region falls back to the most common excluded bucket (the bg) so color
    separation fails honestly (dist 0) instead of a misleading "no dominant".
    """
    _n, _nn, buckets = region_stats(rows, x0, y0, x1, y1)
    exclude_buckets = exclude_buckets or {(0, 0, 0)}
    best_key = None
    best_count = 0
    for key, count in buckets.items():
        if key in exclude_buckets:
            continue
        if count > best_count:
            best_count = count
            best_key = key
    if best_key is None and fallback_to_most_common and buckets:
        best_key = max(buckets, key=buckets.get)
    if best_key is None:
        return None
    return (best_key[0] << 4, best_key[1] << 4, best_key[2] << 4)


def rgb_distance(c1, c2) -> float:
    """Euclidean RGB distance: sqrt((r1-r2)^2 + (g1-g2)^2 + (b1-b2)^2)."""
    return math.sqrt((c1[0] - c2[0]) ** 2 + (c1[1] - c2[1]) ** 2
                     + (c1[2] - c2[2]) ** 2)


def rain_signature(r, g, b, bg_color=None, rain_bg_min_dist=24) -> bool:
    """Rain-drop signature: blue-dominant AND dim (PRD §4.4).
    b - max(r,g) >= 8 and luma < 100. Rain blend ≈ (49,56,71) luma≈56 ✓;
    BgPulse bright phase luma≈149 ✗; dark bg r≈g≈b not blue-dominant ✗.
    With bg_color set, pixels closer than rain_bg_min_dist to the bg are NOT
    rain (#476: the dark bg (10,10,18) matches the old signature — b-max=8,
    luma≈13 — giving a false ~100% coverage on a pure-bg frame).
    """
    if bg_color is not None and rgb_distance((r, g, b), bg_color) < rain_bg_min_dist:
        return False
    return (b - max(r, g)) >= 8 and _luma(r, g, b) < 100


def rain_grid_coverage(rows, w, h, grid=12, step=2, bg_color=None,
                       rain_bg_min_dist=24) -> float:
    """Fraction of grid×grid cells containing ≥1 rain-signature pixel.
    Sampling step matches the other full-frame passes (step=2). bg params
    thread through to rain_signature (#476)."""
    if grid <= 0:
        return 0.0
    cell_w = w / grid
    cell_h = h / grid
    covered = set()
    for y in range(0, h, step):
        row = rows[y]
        for x in range(0, w, step):
            i = x * 4
            if rain_signature(row[i], row[i + 1], row[i + 2],
                              bg_color=bg_color,
                              rain_bg_min_dist=rain_bg_min_dist):
                cx = min(int(x / cell_w), grid - 1)
                cy = min(int(y / cell_h), grid - 1)
                covered.add((cx, cy))
    return len(covered) / (grid * grid)


def check_visual(path, vcfg: dict) -> list[str]:
    """Run all region assertions (#466). Returns fail messages ([] = all pass).

    vcfg schema (shot-level `visual` field, DESIGN §3.2):
      canvas: "WxH" — screenshot must match exactly (防区域错位)
      bg_color/bg_min_dist/rain_bg_min_dist — bg-relative semantics (#476):
        nonbg = RGB distance from bg >= bg_min_dist; rain excludes bg; the
        bg bucket is excluded from dominant-color mode (real bg (10,10,18)
        #0a0a12 is NOT near-black, so it would otherwise win every region).
      regions: [{name, x0, y0, x1, y1, min_nonbg_ratio?}]
      compare_pairs: [[nameA, nameB], ...]  +  rgb_min_dist
      rain: {grid, min_coverage}
    """
    fails: list[str] = []
    w, h, rows = _read_png(path)

    # bg-relative params (#476) — real BG_COLOR is (10,10,18), not near-black
    bg_color = _parse_hex_color(vcfg.get("bg_color"))
    bg_min_dist = float(vcfg.get("bg_min_dist", 24))
    rain_bg_min_dist = float(vcfg.get("rain_bg_min_dist", 24))
    exclude_buckets = {(0, 0, 0)}  # near-black bucket (backward compat)
    if bg_color is not None:
        exclude_buckets.add((bg_color[0] >> 4, bg_color[1] >> 4,
                             bg_color[2] >> 4))

    # 1. canvas check — mismatch fails immediately (regions would be misaligned)
    canvas = vcfg.get("canvas")
    if canvas:
        try:
            cw, ch = (int(p) for p in str(canvas).lower().split("x"))
        except ValueError:
            fails.append(f"canvas '{canvas}' malformed (expected WxH)")
            return fails
        if (w, h) != (cw, ch):
            fails.append(f"canvas {w}x{h} != declared {canvas}")
            return fails

    # 2. per-region: dominant color + non-bg ratio
    dominants: dict[str, tuple] = {}
    for reg in vcfg.get("regions", []):
        name = str(reg.get("name", "?"))
        x0, y0, x1, y1 = reg["x0"], reg["y0"], reg["x1"], reg["y1"]
        n, nn, _b = region_stats(rows, x0, y0, x1, y1,
                                 bg_color=bg_color, bg_min_dist=bg_min_dist)
        dom = dominant_color(rows, x0, y0, x1, y1,
                             exclude_buckets=exclude_buckets,
                             fallback_to_most_common=True)
        dominants[name] = dom
        min_ratio = reg.get("min_nonbg_ratio")
        if min_ratio is not None:
            ratio = nn / n if n else 0.0
            if ratio < float(min_ratio):
                fails.append(f"region '{name}': non-bg {ratio*100:.1f}% < "
                             f"{float(min_ratio)*100:.0f}%")

    # 3. compare_pairs: dominant RGB distance
    min_dist = float(vcfg.get("rgb_min_dist", 60))
    for a, b in vcfg.get("compare_pairs", []):
        ca, cb = dominants.get(a), dominants.get(b)
        if ca is None or cb is None:
            fails.append(f"compare {a} vs {b}: a region is entirely near-black "
                         "(no dominant color)")
            continue
        d = rgb_distance(ca, cb)
        if d < min_dist:
            fails.append(f"compare {a} vs {b}: RGB dist {d:.1f} < {min_dist}")

    # 4. rain grid coverage
    rain = vcfg.get("rain")
    if rain:
        cov = rain_grid_coverage(rows, w, h, grid=int(rain.get("grid", 12)),
                                 bg_color=bg_color,
                                 rain_bg_min_dist=rain_bg_min_dist)
        min_cov = float(rain.get("min_coverage", 0.6))
        if cov < min_cov:
            fails.append(f"rain coverage {cov*100:.1f}% < {min_cov*100:.0f}%")

    return fails


def visual_detail(path, vcfg: dict) -> dict:
    """Structured visual evidence for --json (region dominants/ratios,
    pair distances, rain coverage) — review-agent evidence (DESIGN §3.1)."""
    w, h, rows = _read_png(path)
    bg_color = _parse_hex_color(vcfg.get("bg_color"))
    bg_min_dist = float(vcfg.get("bg_min_dist", 24))
    rain_bg_min_dist = float(vcfg.get("rain_bg_min_dist", 24))
    exclude_buckets = {(0, 0, 0)}  # near-black bucket (backward compat)
    if bg_color is not None:
        exclude_buckets.add((bg_color[0] >> 4, bg_color[1] >> 4,
                             bg_color[2] >> 4))
    detail = {
        "canvas": f"{w}x{h}",
        "bg_color": vcfg.get("bg_color"),
        "bg_min_dist": vcfg.get("bg_min_dist", 24),
        "rain_bg_min_dist": vcfg.get("rain_bg_min_dist", 24),
        "exclude_buckets": sorted([list(b) for b in exclude_buckets]),
    }
    regions = {}
    for reg in vcfg.get("regions", []):
        name = str(reg.get("name", "?"))
        x0, y0, x1, y1 = reg["x0"], reg["y0"], reg["x1"], reg["y1"]
        n, nn, _b = region_stats(rows, x0, y0, x1, y1,
                                 bg_color=bg_color, bg_min_dist=bg_min_dist)
        dom = dominant_color(rows, x0, y0, x1, y1,
                             exclude_buckets=exclude_buckets,
                             fallback_to_most_common=True)
        regions[name] = {
            "dominant": list(dom) if dom else None,
            "nonbg_ratio": round(nn / n, 4) if n else 0.0,
            "min_nonbg_ratio": reg.get("min_nonbg_ratio"),
        }
    detail["regions"] = regions
    pairs = {}
    for a, b in vcfg.get("compare_pairs", []):
        ca = regions.get(a, {}).get("dominant")
        cb = regions.get(b, {}).get("dominant")
        pairs[f"{a}|{b}"] = {
            "dist": round(rgb_distance(tuple(ca), tuple(cb)), 1)
                    if ca and cb else None,
            "rgb_min_dist": vcfg.get("rgb_min_dist", 60),
        }
    detail["pairs"] = pairs
    if "rain" in vcfg:
        detail["rain"] = {
            "coverage": round(rain_grid_coverage(
                rows, w, h, grid=int(vcfg["rain"].get("grid", 12)),
                bg_color=bg_color, rain_bg_min_dist=rain_bg_min_dist), 4),
            "min_coverage": vcfg["rain"].get("min_coverage", 0.6),
        }
    return detail


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
        "--visual-config": None,
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

    # 5. visual region assertions (#466) — flag-gated, backward compatible
    visual_cfg_path = _s("--visual-config")
    visual_detail_data = None
    if visual_cfg_path:
        try:
            with open(visual_cfg_path, "r", encoding="utf-8") as _f:
                vcfg = json.load(_f)
        except (OSError, ValueError) as e:
            fails.append(f"visual config unreadable ({visual_cfg_path}): {e}")
        else:
            try:
                vfails = check_visual(path, vcfg)
                visual_detail_data = visual_detail(path, vcfg)
            except (PNGError, KeyError, ValueError) as e:
                fails.append(f"visual assertions error: {e}")
            else:
                for vf in vfails:
                    fails.append(f"visual: {vf}")
                if not vfails:
                    passes.append("visual region assertions pass")

    line = (f"{path} [{name}]: {st['width']}x{st['height']} "
            f"avgRGB={st['avg_rgb']} colors={st['color_buckets']} "
            f"black={st['black_ratio']*100:.1f}% luma={st['mean_luma']}")
    if opts["--json"]:
        payload = {**st, "name": name, "passes": passes, "fails": fails}
        if visual_detail_data is not None:
            payload["visual"] = visual_detail_data
        print(json.dumps(payload))
    else:
        print(line)
        for p in passes:
            print(f"  ✅ {p}")
        for f in fails:
            print(f"  ❌ {f}")
        if visual_detail_data is not None:
            print("  visual detail:")
            for rname, r in visual_detail_data.get("regions", {}).items():
                dom = "#%02x%02x%02x" % tuple(r["dominant"]) if r["dominant"] else "none"
                print(f"    {rname}: dominant={dom} nonbg={r['nonbg_ratio']*100:.1f}%")
            for pname, p in visual_detail_data.get("pairs", {}).items():
                d = f"{p['dist']:.1f}" if p["dist"] is not None else "none"
                print(f"    pair {pname}: dist={d} (min {p['rgb_min_dist']})")
            if "rain" in visual_detail_data:
                r = visual_detail_data["rain"]
                print(f"    rain: coverage={r['coverage']*100:.1f}% (min {r['min_coverage']*100:.0f}%)")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
