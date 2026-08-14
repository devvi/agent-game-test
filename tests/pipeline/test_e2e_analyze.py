#!/usr/bin/env python3
"""Unit tests for scripts/e2e/analyze_bmp.py — the screenshot anti-fake-evidence analyzer.

Covers the 4 assertions: non-black / color count / theme color / frame diff,
plus PNG decoding (pure stdlib) and exit-code semantics.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
Constraints: no network, no Godot, no sips/PIL — PNGs are synthesized in-test.
"""
import importlib.util
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_ANALYZER_PATH = os.path.join(_REPO_ROOT, "scripts", "e2e", "analyze_bmp.py")

_spec = importlib.util.spec_from_file_location("analyze_bmp", _ANALYZER_PATH)
an = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(an)


def make_png(w: int, h: int, pixel_fn) -> bytes:
    """Synthesize an RGB-8 PNG. pixel_fn(x, y) -> (r, g, b)."""
    def chunk(typ: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    raw = b""
    for y in range(h):
        raw += b"\x00"  # filter: None
        for x in range(w):
            r, g, b = pixel_fn(x, y)
            raw += bytes((r, g, b))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def run_cli(tmpdir: str, png_name: str, *args: str) -> subprocess.CompletedProcess:
    path = os.path.join(tmpdir, png_name)
    return subprocess.run(
        [sys.executable, _ANALYZER_PATH, path, *args],
        capture_output=True, text=True, cwd=_REPO_ROOT)


def write_png(tmpdir: str, name: str, png: bytes) -> str:
    """Write a synthesized PNG and return its path (closed handle)."""
    path = os.path.join(tmpdir, name)
    with open(path, "wb") as f:
        f.write(png)
    return path


class TestPngDecode(unittest.TestCase):
    def test_black_png_detected(self):
        with tempfile.TemporaryDirectory() as td:
            p = write_png(td, "black.png",
                make_png(64, 64, lambda x, y: (0, 0, 0)))
            st = an.analyze(p)
            self.assertEqual(st["black_ratio"], 1.0)
            self.assertEqual(st["avg_rgb"], (0.0, 0.0, 0.0))

    def test_gradient_png_stats(self):
        with tempfile.TemporaryDirectory() as td:
            p = write_png(td, "grad.png",
                make_png(64, 64, lambda x, y: (x * 4, y * 4, 128)))
            st = an.analyze(p)
            self.assertGreater(st["color_buckets"], 10)
            self.assertLess(st["black_ratio"], 0.05)
            self.assertGreater(st["mean_luma"], 0)


class TestAssertions(unittest.TestCase):
    def test_black_fails_non_black(self):
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "b.png",
                make_png(32, 32, lambda x, y: (0, 0, 0)))
            r = run_cli(td, "b.png")
            self.assertEqual(r.returncode, 1)
            self.assertIn("near-black", r.stdout)

    def test_flat_red_fails_color_count(self):
        # 1 color bucket < default min 3 → fail (frozen-frame class)
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "r.png",
                make_png(32, 32, lambda x, y: (255, 0, 0)))
            r = run_cli(td, "r.png", "--max-black-ratio", "0.9")
            self.assertEqual(r.returncode, 1)
            self.assertIn("color buckets", r.stdout)

    def test_theme_color_present_and_absent(self):
        with tempfile.TemporaryDirectory() as td:
            # gradient + a 10x10 patch of theme blue at origin
            def fn(x, y):
                if x < 10 and y < 10:
                    return (0x4a, 0x90, 0xd9)
                return (x * 3 % 256, y * 3 % 256, 40)
            write_png(td, "g.png", make_png(64, 64, fn))
            ok = run_cli(td, "g.png", "--theme", "4a90d9")
            self.assertEqual(ok.returncode, 0, ok.stdout)
            bad = run_cli(td, "g.png", "--theme", "ff00ff")
            self.assertEqual(bad.returncode, 1)

    def test_frame_diff_detects_identical(self):
        with tempfile.TemporaryDirectory() as td:
            png = make_png(64, 64, lambda x, y: (x * 3 % 256, 100, 50))
            write_png(td, "a.png", png)
            write_png(td, "b.png", png)
            r = run_cli(td, "a.png", "--diff-with", os.path.join(td, "b.png"),
                        "--min-delta", "1.0")
            self.assertEqual(r.returncode, 1)
            self.assertIn("frozen", r.stdout)

    def test_frame_diff_passes_on_change(self):
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "a.png",
                make_png(64, 64, lambda x, y: (10, 10, 10)))
            write_png(td, "b.png",
                make_png(64, 64, lambda x, y: (240, 240, 240)))
            # --min-colors 1 isolates the diff assertion (flat colors are
            # legitimately caught by the color-count assertion otherwise)
            r = run_cli(td, "a.png", "--diff-with", os.path.join(td, "b.png"),
                        "--min-delta", "1.0", "--min-colors", "1")
            self.assertEqual(r.returncode, 0, r.stdout)

    def test_json_output(self):
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "g.png",
                make_png(32, 32, lambda x, y: (x * 8, 20, 30)))
            r = run_cli(td, "g.png", "--json")
            self.assertEqual(r.returncode, 0)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            self.assertEqual(payload["width"], 32)
            self.assertIn("passes", payload)


if __name__ == "__main__":
    unittest.main()


class TestFrameDiffRatio(unittest.TestCase):
    """#372: frozen heuristic — changed-pixel-ratio channel (--diff-ratio).

    Regression: neon dark-bg frames have tiny mean Δluma (0.5 < 5.0) but
    >0.5% pixels change significantly (1.009% in #371). The ratio channel
    must rescue them while staying backward-compatible (default off).
    """

    def _dark_neon_frames(self, td):
        """64x64 dark bg #0a0a12; frame B adds an 8x5 bright #4a90d9 rect."""
        def dark(x, y):
            return (0x0a, 0x0a, 0x12)
        def dark_plus_rect(x, y):
            if x < 8 and y < 5:
                return (0x4a, 0x90, 0xd9)
            return (0x0a, 0x0a, 0x12)
        a = write_png(td, "dark_a.png", make_png(64, 64, dark))
        b = write_png(td, "dark_b.png", make_png(64, 64, dark_plus_rect))
        return a, b

    def test_frame_diff_identical_fails_diff_ratio(self):
        # Two identical frames → ratio 0% < 0.5% → still frozen (rc=1).
        with tempfile.TemporaryDirectory() as td:
            png = make_png(64, 64, lambda x, y: (x * 3 % 256, 100, 50))
            write_png(td, "a.png", png)
            write_png(td, "b.png", png)
            r = run_cli(td, "a.png", "--diff-with", os.path.join(td, "b.png"),
                        "--diff-ratio", "0.005", "--min-delta", "5.0")
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("frozen", r.stdout)

    def test_frame_diff_full_change_passes_diff_ratio(self):
        # All pixels change → ratio 100% >= 0.5% → pass even though the
        # color-count / black assertions are disabled to isolate the diff.
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "a.png",
                make_png(64, 64, lambda x, y: (0, 0, 0)))
            write_png(td, "b.png",
                make_png(64, 64, lambda x, y: (255, 255, 255)))
            r = run_cli(td, "a.png", "--diff-with", os.path.join(td, "b.png"),
                        "--diff-ratio", "0.005", "--min-delta", "5.0",
                        "--min-colors", "1", "--max-black-ratio", "1.0")
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("变化像素占比", r.stdout)

    def test_frame_diff_dark_neon_change_passes(self):
        # #371 regression: mean Δluma << 5.0 but ~1% pixels change → the
        # ratio channel must rescue the assertion (mirrors #371 real frames:
        # Δluma=0.5, 1.009% pixels changed).
        with tempfile.TemporaryDirectory() as td:
            a, b = self._dark_neon_frames(td)
            r = run_cli(td, "dark_b.png", "--diff-with", a,
                        "--diff-ratio", "0.005", "--min-delta", "5.0",
                        "--min-colors", "1", "--max-black-ratio", "1.0")
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("变化像素占比", r.stdout)

    def test_frame_diff_ratio_default_off(self):
        # No --diff-ratio → pure mean-Δluma behavior (backward compat):
        # identical frames still fail as frozen.
        with tempfile.TemporaryDirectory() as td:
            png = make_png(64, 64, lambda x, y: (x * 3 % 256, 100, 50))
            write_png(td, "a.png", png)
            write_png(td, "b.png", png)
            r = run_cli(td, "a.png", "--diff-with", os.path.join(td, "b.png"),
                        "--min-delta", "1.0")
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("frozen", r.stdout)
# ── #466/#476: visual region assertions (check_visual) — bg-relative ───────
# DESIGN 476 §3.3-3.5 / §9 — synthetic PNGs, pure stdlib, no network/Godot.
# Post-#464 real background is (10,10,18) → 16-level bucket (0,0,1), which is
# NOT near-black (r=10 >= 8). Assertions are therefore RELATIVE to the bg
# color driven by the shot's visual config (#476 fix):
#   * dominant_color excludes the bg bucket (near-black + bg) so element
#     colors (cyan paddle / orange brick) win the mode.
#   * nonbg = RGB distance from bg >= bg_min_dist (bg itself is NOT foreground).
#   * rain_signature must differ from bg by >= rain_bg_min_dist (otherwise
#     the dark blue-tinted bg matches the rain signature itself → false 100%).
#   * paddle region = full-width bottom strip (captures any x position).

BG_DARK = (4, 4, 4)            # near-black synthetic bg (backward-compat tests)
BG_REAL = (10, 10, 18)         # post-#464 BG_COLOR #0a0a12 — NOT near-black
PADDLE_CYAN = (0, 229, 255)    # PADDLE_NEON #00e5ff
BRICK_ORANGE = (255, 157, 69)  # BRICK_NEON #ff9d45
RAIN_BLUE = (50, 56, 70)       # rain-drop blend ≈ (49,56,71) — signature ✓
BG_MIN_DIST = 24               # nonbg distance threshold (DESIGN 476 §3.3.2)
RAIN_BG_MIN_DIST = 24          # rain-vs-bg distance threshold (§3.3.3)
# Paddle strip: y1220-1260 full width — PlayerPaddle center y=1240, height 20
# (spans 1230-1250), moves only in x (Main.tscn position (360,1240)). Old
# fixed region x240-480 had 0/1944 px overlap with the review-measured paddle
# at x15-122 → full-width strip required (§3.3.4).
PADDLE_STRIP = (0, 1220, 720, 1260)


def make_png_fast(w, h, bg=BG_REAL, rects=(), points=()):
    """Fast synthetic RGB-8 PNG via bytearray rows (O(n), no per-pixel lambda).
    rects: (x0,y0,x1,y1,rgb) painted via slice fill; points: (x,y,rgb) set
    directly. A 720x1280 build takes ~0.3s (the per-pixel make_png would take
    minutes — #466 helper requirement). Default bg = real BG_COLOR (#476)."""
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))
    by_y = {}
    for (x, py, c) in points:
        by_y.setdefault(py, []).append((x, c))
    raw = bytearray()
    bg3 = bytes(bg)
    for y in range(h):
        raw.append(0)  # filter: None
        row = bytearray(bg3 * w)
        for (x0, y0, x1, y1, c) in rects:
            if y0 <= y < y1:
                row[x0 * 3:x1 * 3] = bytes(c) * (x1 - x0)
        for (x, c) in by_y.get(y, ()):
            row[x * 3:x * 3 + 3] = bytes(c)
        raw += row
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))


def _visual_config(**over):
    """Shot-level visual config (DESIGN 476 §3.4 shape — bg-relative)."""
    cfg = {
        "canvas": "720x1280",
        "bg_color": "0a0a12",          # real BG_COLOR #0a0a12 (10,10,18)
        "bg_min_dist": BG_MIN_DIST,    # nonbg = RGB dist from bg >= threshold
        "rain_bg_min_dist": RAIN_BG_MIN_DIST,
        "regions": [
            {"name": "paddle", "x0": PADDLE_STRIP[0], "y0": PADDLE_STRIP[1],
             "x1": PADDLE_STRIP[2], "y1": PADDLE_STRIP[3],
             "min_nonbg_ratio": 0.05},
            {"name": "brick", "x0": 0, "y0": 560, "x1": 720, "y1": 720},
            {"name": "bg", "x0": 0, "y0": 0, "x1": 60, "y1": 60},
        ],
        "compare_pairs": [["paddle", "brick"], ["paddle", "bg"], ["brick", "bg"]],
        "rgb_min_dist": 60,
    }
    cfg.update(over)
    return cfg


def _run_visual(td, png_bytes, cfg, *extra):
    """Write PNG + visual-config JSON, run CLI with visual assertions isolated
    (--max-black-ratio 1.0 --min-colors 1 so the 4-fold global assertions
    cannot mask the region assertions under test)."""
    write_png(td, "v.png", png_bytes)
    cfg_path = os.path.join(td, "vcfg.json")
    with open(cfg_path, "w") as f:
        json.dump(cfg, f)
    return run_cli(td, "v.png", "--visual-config", cfg_path,
                   "--max-black-ratio", "1.0", "--min-colors", "1", *extra)


class TestVisualRegionAssertions(unittest.TestCase):
    """#466 + #476: region assertions — player paddle visibility (AC2/AC7),
    three-color separation (AC4), rain distribution (AC5), bg-relative
    semantics (bg bucket excluded, nonbg vs bg, rain vs bg)."""

    # ── Scenario A: player paddle visibility (AC2/AC7) ──

    def test_visual_paddle_present(self):
        # AC7: paddle at review-measured x15-122 (old fixed region x240-480
        # had 0/1944 px overlap). Full-width strip captures any x. nonbg =
        # dist-from-bg >= 24 → paddle 107*20=2140px / 720*40=28800px strip
        # ≈ 7.4% > 5% → pass.
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                rects=[(15, 1230, 122, 1250, PADDLE_CYAN)])
            cfg = _visual_config(regions=[
                {"name": "paddle", "x0": 0, "y0": 1220, "x1": 720, "y1": 1260,
                 "min_nonbg_ratio": 0.05}], compare_pairs=[])
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("paddle", r.stdout)
            self.assertIn("7.4%", r.stdout)  # 2140/28800 ≈ 7.4%

    def test_visual_paddle_missing_fails(self):
        # AC5/AC7 reverse: board removed on REAL bg → nonbg (dist>=24) 0% < 5%
        # → rc=1, "paddle" fail. Pre-#476: bg (10,10,18) counted as foreground
        # → ratio was 100% → false PASS (the reported L3 false-green).
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL)
            cfg = _visual_config(regions=[
                {"name": "paddle", "x0": 0, "y0": 1220, "x1": 720, "y1": 1260,
                 "min_nonbg_ratio": 0.05}], compare_pairs=[])
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("paddle", r.stdout)

    def test_visual_paddle_nearblack_bg_backward_compat(self):
        # bg_color=None path: near-black bg (4,4,4) + cyan paddle → old
        # near-black rule still works (backward compat, DESIGN 476 §3.5).
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN)])
            cfg = {"canvas": "720x1280", "regions": [
                {"name": "paddle", "x0": 0, "y0": 1220, "x1": 720, "y1": 1260,
                 "min_nonbg_ratio": 0.05}]}
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("8.3%", r.stdout)  # 2400/28800 ≈ 8.3%

    # ── Scenario B: three-color separation (AC4) ──

    def test_visual_three_color_separation(self):
        # Real bg everywhere; paddle cyan / brick orange / bg region = bg.
        # bg bucket excluded → paddle=cyan bucket, brick=orange bucket, bg
        # region falls back to bg bucket → all pairs dist >= 60 → pass.
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE),
                                       (0, 0, 60, 60, BG_REAL)])
            r = _run_visual(td, png, _visual_config())
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("paddle", r.stdout)
            self.assertIn("brick", r.stdout)

    def test_visual_same_color_fails(self):
        # AC5 reverse: board/brick reverted to bg color on REAL bg → bg bucket
        # excluded everywhere, fallback yields bg bucket → dist 0 < 60 → rc=1.
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                rects=[(300, 1230, 420, 1250, BG_REAL),
                                       (0, 600, 720, 680, BG_REAL),
                                       (0, 0, 60, 60, BG_REAL)])
            r = _run_visual(td, png, _visual_config())
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("RGB dist", r.stdout)

    # ── Scenario C: rain distribution (AC5) ──

    @staticmethod
    def _rain_points(everywhere):
        """One rain pixel per 12x12 grid cell at even coords (sampled by
        step=2). everywhere=False → top-left 6x6 cells only (25% coverage)."""
        pts = []
        for j in range(12):
            for i in range(12):
                if everywhere or (i < 6 and j < 6):
                    pts.append((30 + 60 * i, 54 + 106 * j, RAIN_BLUE))
        return pts

    def test_visual_rain_coverage_pass(self):
        # REAL bg + rain blend pixels everywhere → rain signature hits the
        # droplets (dist from bg ≈ 80 >= 24) and excludes the bg itself →
        # coverage 100% >= 60% → pass.
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                points=self._rain_points(everywhere=True))
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("rain", r.stdout)

    def test_visual_rain_coverage_fail(self):
        # Only top-left corner has rain → coverage 36/144=25% < 60% → rc=1
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                points=self._rain_points(everywhere=False))
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)

    def test_visual_rain_pure_bg_no_rain_fails(self):
        # KEY anti-false-positive regression (#476): on the real dark bg
        # (10,10,18) the OLD signature (b-max(r,g)>=8 AND luma<100) matched the
        # bg itself → coverage ≈100% → false PASS (L3-rain-coverage-15pct).
        # With rain_bg_min_dist the bg is excluded → 0% < 60% → honest FAIL.
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL)  # no rain at all
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("rain", r.stdout)

    def test_rain_signature_excludes_bright(self):
        # Bright blue (luma 117 >= 100) fails the dim condition → no coverage
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(0, 150, 255))
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)

    def test_rain_signature_excludes_gray(self):
        # Neutral gray (not blue-dominant) fails b-max(r,g)>=8 → no coverage
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(70, 70, 70))
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)

    # ── Scenario E: backward compat + canvas + json ──

    def test_visual_canvas_mismatch(self):
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(64, 64, bg=BG_DARK)
            r = _run_visual(td, png, _visual_config())
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("canvas", r.stdout)

    def test_visual_config_absent_backward_compat(self):
        # No --visual-config → behavior unchanged (rc=0 on a gradient frame)
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "g.png",
                      make_png(64, 64, lambda x, y: (x * 4, y * 4, 128)))
            r = run_cli(td, "g.png")
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertNotIn("visual", r.stdout)

    def test_visual_json_has_detail(self):
        # --json output embeds region/pair/rain detail for review (incl. the
        # bg-relative nonbg ratio and bg params)
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE),
                                       (0, 0, 60, 60, BG_REAL)])
            r = _run_visual(td, png, _visual_config(), "--json")
            self.assertEqual(r.returncode, 0, r.stdout)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            self.assertIn("visual", payload)
            v = payload["visual"]
            self.assertEqual(v["bg_color"], "0a0a12")
            self.assertAlmostEqual(v["regions"]["paddle"]["nonbg_ratio"], 0.08, places=2)
            self.assertIsNotNone(v["regions"]["paddle"]["dominant"])
            self.assertGreaterEqual(v["pairs"]["paddle|brick"]["dist"], 60)

    # ── Pure-function units (DESIGN 476 §3.3: 均可独立单测) ──

    def test_region_stats_counts(self):
        rows = [bytearray(bytes((4, 4, 4, 255)) * 4)] * 2  # 4x2 all near-black
        n, nn, buckets = an.region_stats(rows, 0, 0, 4, 2)
        self.assertEqual(n, 8)
        self.assertEqual(nn, 0)
        rows2 = [bytearray(bytes((10, 10, 18, 255)) * 4)]  # bg_color=None → old rule
        n, nn, _ = an.region_stats(rows2, 0, 0, 4, 1)
        self.assertEqual(nn, 4)  # (10,10,18) counts as foreground w/o bg config

    def test_region_stats_bg_relative(self):
        # bg_color set → nonbg = RGB dist from bg >= bg_min_dist. The bg itself
        # is NOT foreground (pre-#476: (10,10,18) counted → ratio恒100%).
        rows = [bytearray(bytes((10, 10, 18, 255)) * 4)] * 2       # 4x2 all bg
        n, nn, _ = an.region_stats(rows, 0, 0, 4, 2,
                                   bg_color=BG_REAL, bg_min_dist=BG_MIN_DIST)
        self.assertEqual(nn, 0)
        rows2 = [bytearray(bytes((10, 10, 18, 255)) * 4
                           + bytes((0, 229, 255, 255)) * 4)] * 2   # + cyan
        n, nn, _ = an.region_stats(rows2, 0, 0, 8, 2,
                                   bg_color=BG_REAL, bg_min_dist=BG_MIN_DIST)
        self.assertEqual(nn, 8)  # cyan paddle pixels are foreground

    def test_dominant_color_none_when_all_near_black(self):
        rows = [bytearray(bytes((4, 4, 4, 255)) * 4)] * 2
        self.assertIsNone(an.dominant_color(rows, 0, 0, 4, 2))

    def test_dominant_color_excludes_near_black_bucket(self):
        rows = [bytearray(bytes((4, 4, 4, 255)) * 4
                          + bytes((0, 229, 255, 255)) * 4)] * 2
        dom = an.dominant_color(rows, 0, 0, 8, 2)
        self.assertEqual(dom, (0, 224, 240))  # bucket rep of (0,229,255)

    def test_dominant_color_excludes_bg_bucket(self):
        # Real bg (10,10,18) → bucket (0,0,1) — must be excluded alongside the
        # near-black bucket or it wins the mode in every region (L3-region-0).
        rows = [bytearray(bytes((10, 10, 18, 255)) * 4
                          + bytes((0, 229, 255, 255)) * 4)] * 2
        dom = an.dominant_color(rows, 0, 0, 8, 2,
                                exclude_buckets={(0, 0, 0), (0, 0, 1)})
        self.assertEqual(dom, (0, 224, 240))  # cyan wins over excluded bg

    def test_dominant_color_fallback_to_most_common(self):
        # All-background region: every bucket excluded → fall back to the most
        # common excluded bucket (bg) so color-separation fails with dist 0
        # (honest failure) instead of a misleading "no dominant" error.
        rows = [bytearray(bytes((10, 10, 18, 255)) * 4)] * 2
        dom = an.dominant_color(rows, 0, 0, 4, 2,
                                exclude_buckets={(0, 0, 0), (0, 0, 1)},
                                fallback_to_most_common=True)
        self.assertEqual(dom, (0, 0, 16))  # (0,0,1)<<4

    def test_rgb_distance(self):
        self.assertAlmostEqual(an.rgb_distance((0, 0, 0), (3, 4, 0)), 5.0)
        self.assertAlmostEqual(an.rgb_distance((0, 229, 255), (255, 157, 69)),
                               323.0, delta=30)  # ≈347 per PRD §2.2 bucket-rep

    def test_rain_signature_matrix(self):
        self.assertTrue(an.rain_signature(50, 56, 70))    # rain blend
        self.assertFalse(an.rain_signature(0, 150, 255))  # luma 117 ≥ 100
        self.assertFalse(an.rain_signature(70, 70, 70))   # not blue-dominant
        self.assertFalse(an.rain_signature(4, 4, 4))      # near-black bg

    def test_rain_signature_excludes_bg(self):
        # #476: the OLD signature matched the real bg itself (b-max=8, luma≈13)
        # → false 100% coverage. With bg_color set the bg is not rain.
        self.assertFalse(an.rain_signature(10, 10, 18,
                                           bg_color=BG_REAL,
                                           rain_bg_min_dist=RAIN_BG_MIN_DIST))
        # Rain blend (dist from bg ≈ 80) still matches → real droplets pass.
        self.assertTrue(an.rain_signature(50, 56, 70,
                                          bg_color=BG_REAL,
                                          rain_bg_min_dist=RAIN_BG_MIN_DIST))

    def test_rain_grid_coverage_small(self):
        rows = [bytearray(bytes((50, 56, 70, 255)) * 4)] * 2  # 4x2 all rain
        cov = an.rain_grid_coverage(rows, 4, 2, grid=2, step=1)
        self.assertEqual(cov, 1.0)
        rows2 = [bytearray(bytes((4, 4, 4, 255)) * 4)] * 2
        self.assertEqual(an.rain_grid_coverage(rows2, 4, 2, grid=2, step=1), 0.0)


class TestDynamicBgSampling(unittest.TestCase):
    """#485: dynamic bg sampling (DESIGN 485 §1.2 Approach B) — BgPulse 相位
    鲁棒。bg_sample=true 时从 R_bg 角落区实测背景色替代静态 bg_color →
    exclude_buckets / region_stats / rain 全用实测 bg_ref: 三区 pair dist 任意
    相位 >= 60 (AC3), 脉冲背景不再被判为 rain 100% 覆盖 (AC2), paddle 阈值按
    实测回填 0.025 (PRD §4.4)。RED 状态: sample_bg_color / _resolve_bg 尚不
    存在 (调用时 AttributeError 为期望红信号), 实现单独落地。
    """

    # BgPulse alpha ∈ {0.01,0.05,0.08,0.13,0.15} → 渲染 bg 五相位
    # (DESIGN 485 §5.1 AC3 夹具; 数学核算 PRD §7 实验 1)
    _PHASES = [
        (11, 11, 20), (13, 17, 28), (15, 21, 34), (18, 27, 44), (20, 30, 48),
    ]

    # ── Scenario F: 5-phase three-region separation (AC3) ──

    def _three_region_frame(self, bg):
        """Scenario F 布局: 青色板 (300,1230)-(420,1250) + 橙色砖条
        (0,600)-(720,680); 角落 R_bg (0,0)-(60,60) 由 make_png_fast 的 bg 参数
        填充（无需显式 rect）→ 采样区纯净。"""
        return make_png_fast(
            720, 1280, bg=bg,
            rects=[(300, 1230, 420, 1250, PADDLE_CYAN),
                   (0, 600, 720, 680, BRICK_ORANGE)])

    def test_f_high_phase_key_case(self):
        # AC3 关键帧（复现帧 959 ≈ alpha 0.13 → bg=(18,27,44)）: 动态采样
        # bg_ref=#121b2c 并出现在 --json detail; 三区 pair dist 全 >= 60 →
        # rc=0（旧逻辑静态排除桶 (1,1,2) 泄漏 → dist 0 → 假 fail）。
        with tempfile.TemporaryDirectory() as td:
            png = self._three_region_frame((18, 27, 44))
            r = _run_visual(td, png, _visual_config(bg_sample=True), "--json")
            self.assertEqual(r.returncode, 0, r.stdout)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            v = payload["visual"]
            self.assertEqual(v["bg_ref"], "#121b2c")  # (18,27,44) hex
            self.assertIs(v["bg_sample"], True)
            self.assertGreaterEqual(v["pairs"]["paddle|brick"]["dist"], 60)
            self.assertGreaterEqual(v["pairs"]["paddle|bg"]["dist"], 60)
            self.assertGreaterEqual(v["pairs"]["brick|bg"]["dist"], 60)

    def test_f_five_phase_no_collapse(self):
        # 核心 AC3 证据: 5 个 BgPulse 相位全部三区 pair dist >= 60 → 无相位
        # 塌缩（旧逻辑高相位恒 dist 0）。
        with tempfile.TemporaryDirectory() as td:
            for bg in self._PHASES:
                with self.subTest(bg=bg):
                    png = self._three_region_frame(bg)
                    r = _run_visual(td, png,
                                    _visual_config(bg_sample=True), "--json")
                    self.assertEqual(r.returncode, 0, r.stdout)
                    payload = json.loads(r.stdout.strip().splitlines()[-1])
                    v = payload["visual"]
                    self.assertGreaterEqual(
                        v["pairs"]["paddle|brick"]["dist"], 60)
                    self.assertGreaterEqual(v["pairs"]["paddle|bg"]["dist"], 60)
                    self.assertGreaterEqual(v["pairs"]["brick|bg"]["dist"], 60)

    def test_f_same_as_bg_still_fails(self):
        # AC5 反向: 板与砖都涂成背景色 → 动态 bg 下断言不得软化, 仍必须失败
        # (pair dist 0 < 60 → "RGB dist" 消息)。
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(
                720, 1280, bg=(18, 27, 44),
                rects=[(300, 1230, 420, 1250, (18, 27, 44)),
                       (0, 600, 720, 680, (18, 27, 44))])
            r = _run_visual(td, png, _visual_config(bg_sample=True))
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("RGB dist", r.stdout)

    # ── Scenario G: rain 非假阳性 (AC2) ──

    def test_g_pulsed_bg_no_rain_fails_clean(self):
        # AC2 核心负例: 高相位纯脉冲背景(无雨) → 旧逻辑覆盖率≈100% 假阳性;
        # 动态 bg_ref 下脉冲背景 dist≈0 被排除 → coverage≈0 < 0.60 → 诚实失败。
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(18, 27, 44))
            cfg = _visual_config(bg_sample=True, regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg, "--json")
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("rain", r.stdout)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            cov = payload["visual"]["rain"]["coverage"]
            self.assertGreaterEqual(cov, 0.0)
            self.assertLess(cov, 0.05)

    def test_g_real_rain_curtain_passes(self):
        # 真实雨幕: 高相位 bg + 全屏雨滴 → 雨滴 dist(bg_ref)≈50 >= 24 保留 →
        # coverage 100% >= 60% → 通过。
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(18, 27, 44),
                                points=TestVisualRegionAssertions._rain_points(
                                    everywhere=True))
            cfg = _visual_config(bg_sample=True, regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 0, r.stdout)

    def test_g_low_phase_symmetry(self):
        # 低相位对称: (11,11,20) + 雨 → 过; (11,11,20) 无雨 → fail (非假阳性)
        with tempfile.TemporaryDirectory() as td:
            with_rain = make_png_fast(
                720, 1280, bg=(11, 11, 20),
                points=TestVisualRegionAssertions._rain_points(everywhere=True))
            r = _run_visual(td, with_rain,
                            _visual_config(bg_sample=True, regions=[],
                                           compare_pairs=[],
                                           rain={"grid": 12,
                                                 "min_coverage": 0.60}))
            self.assertEqual(r.returncode, 0, r.stdout)
            no_rain = make_png_fast(720, 1280, bg=(11, 11, 20))
            r = _run_visual(td, no_rain,
                            _visual_config(bg_sample=True, regions=[],
                                           compare_pairs=[],
                                           rain={"grid": 12,
                                                 "min_coverage": 0.60}))
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("rain", r.stdout)

    # ── Scenario H: 采样退化 / 污染 / 兼容 / 配置错误 (纯函数级) ──

    def test_h_sampling_degradation_fallback(self):
        # 退化兜底 (DESIGN 485 §5.2-2): 角落全近黑 → sample_bg_color None →
        # _resolve_bg 降级静态 bg_color (10,10,18) + exclude_buckets 含 (0,0,1)
        with tempfile.TemporaryDirectory() as td:
            p = write_png(td, "nb.png", make_png_fast(8, 8, bg=BG_DARK))
            _w, _h, rows = an._read_png(p)
            self.assertIsNone(an.sample_bg_color(rows, 0, 0, 8, 8))

            p = write_png(td, "nb64.png", make_png_fast(64, 64, bg=BG_DARK))
            _w, _h, rows = an._read_png(p)
            vcfg = _visual_config(bg_sample=True)
            bg_eff, exclude_buckets = an._resolve_bg(vcfg, rows)
            self.assertEqual(bg_eff, BG_REAL)  # 静态 #0a0a12 兜底
            self.assertIn((0, 0, 1), exclude_buckets)

    def test_h_polluted_corner_fails_not_silent(self):
        # 角落采样污染负例 (DESIGN 485 §5.2-1): R_bg 角落 >50% 青色 → bg_ref
        # 失真 → 行为必须确定且 NOT 静默通过 (rc=1 + "RGB dist")。
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(
                720, 1280, bg=(18, 27, 44),
                rects=[(0, 0, 60, 35, PADDLE_CYAN),   # 35/60 行 = 58% 青
                       (300, 1230, 420, 1250, PADDLE_CYAN),
                       (0, 600, 720, 680, BRICK_ORANGE)])
            r = _run_visual(td, png, _visual_config(bg_sample=True))
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("RGB dist", r.stdout)

    def test_h_no_bg_sample_backward_compat(self):
        # bg_sample 缺省 → 完全旧行为: 静态 bg 帧通过, 且 --json 不新增
        # bg_ref / bg_sample 键 (向后兼容红线)。
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE)])
            r = _run_visual(td, png, _visual_config(), "--json")
            self.assertEqual(r.returncode, 0, r.stdout)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            self.assertNotIn("bg_ref", payload["visual"])
            self.assertNotIn("bg_sample", payload["visual"])

    def test_h_config_error_missing_bg_region(self):
        # bg_sample=true 但 regions 无 'bg' 区 → 配置错误显式失败
        with tempfile.TemporaryDirectory() as td:
            cfg = _visual_config(bg_sample=True, regions=[
                {"name": "paddle", "x0": 0, "y0": 1220, "x1": 720,
                 "y1": 1260, "min_nonbg_ratio": 0.05},
                {"name": "brick", "x0": 0, "y0": 560, "x1": 720,
                 "y1": 720}], compare_pairs=[])
            r = _run_visual(td, make_png_fast(720, 1280), cfg)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("bg_sample requires a region named 'bg'", r.stdout)

    # ── Scenario I: paddle 阈值校准 0.025 (PRD §4.4 实测回填) ──
    # 全宽 720x40 区域 = 28800px; 校准阈值 0.025 (实测 3.5% 下方留安全边际):
    # 8.5% → 过 / 0% → fail / 4.2% 边界 → 过。

    def _paddle_config(self):
        return _visual_config(bg_sample=True, regions=[
            {"name": "paddle", "x0": 0, "y0": 1220, "x1": 720,
             "y1": 1260, "min_nonbg_ratio": 0.025},
            {"name": "brick", "x0": 0, "y0": 560, "x1": 720, "y1": 720},
            {"name": "bg", "x0": 0, "y0": 0, "x1": 60, "y1": 60}])

    def test_i_measured_paddle_position(self):
        # 实测板位 (15,1230)-(137,1250): 122x20=2440px=8.5% >= 2.5% → 过
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(18, 27, 44),
                                rects=[(15, 1230, 137, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE)])
            r = _run_visual(td, png, self._paddle_config())
            self.assertEqual(r.returncode, 0, r.stdout)

    def test_i_paddle_invisible_fails(self):
        # 无板 → paddle 区 nonbg 0% < 2.5% → fail
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(18, 27, 44),
                                rects=[(0, 600, 720, 680, BRICK_ORANGE)])
            r = _run_visual(td, png, self._paddle_config())
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("paddle", r.stdout)

    def test_i_half_visible_boundary(self):
        # 半可见边界: 板 (0,1230)-(60,1250): 60x20=1200px=4.2% >= 2.5% → 过
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=(18, 27, 44),
                                rects=[(0, 1230, 60, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE)])
            r = _run_visual(td, png, self._paddle_config())
            self.assertEqual(r.returncode, 0, r.stdout)


if __name__ == "__main__":
    unittest.main()
