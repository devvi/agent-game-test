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



# ── #466: visual region assertions (check_visual) ──────────────────────────
# DESIGN 466 §3.5 / §9 — synthetic PNGs, pure stdlib, no network/Godot.
# Near-black rule: r<8 AND g<8 AND b<8 (same as global analyze). Background
# (4,4,4) is near-black → counts as background; (10,10,18) is FOREGROUND.
# Paddle region x240-480/y1220-1260 (240x40=9600px); board 120x20=2400px →
# expected nonbg = 25% (PRD §5.1), threshold min 5% leaves 5x margin.

BG_DARK = (4, 4, 4)            # near-black synthetic bg (r<8)
BG_REAL = (10, 10, 18)         # post-#464 BG_COLOR — NOT near-black (foreground)
PADDLE_CYAN = (0, 229, 255)    # PADDLE_NEON #00e5ff
BRICK_ORANGE = (255, 157, 69)  # BRICK_NEON #ff9d45
RAIN_BLUE = (50, 56, 70)       # rain-drop blend ≈ (49,56,71) — signature ✓


def make_png_fast(w, h, bg=BG_DARK, rects=(), points=()):
    """Fast synthetic RGB-8 PNG via bytearray rows (O(n), no per-pixel lambda).
    rects: (x0,y0,x1,y1,rgb) painted via slice fill; points: (x,y,rgb) set
    directly. A 720x1280 build takes ~0.3s (the per-pixel make_png would take
    minutes — #466 helper requirement)."""
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
    """Shot-level visual config (DESIGN §3.2 shape)."""
    cfg = {
        "canvas": "720x1280",
        "regions": [
            {"name": "paddle", "x0": 240, "y0": 1220, "x1": 480, "y1": 1260,
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
    """#466: region assertions — player paddle visibility (AC2), three-color
    separation (AC3), rain distribution (AC4), AC5 reverse cases."""

    # ── Scenario A: player paddle visibility (AC2) ──

    def test_visual_paddle_present(self):
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN)])
            cfg = {"canvas": "720x1280", "regions": [
                {"name": "paddle", "x0": 240, "y0": 1220, "x1": 480, "y1": 1260,
                 "min_nonbg_ratio": 0.05}]}
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("paddle", r.stdout)
            self.assertIn("25.0%", r.stdout)  # board 2400/9600 ≈ 25%

    def test_visual_paddle_missing_fails(self):
        # AC5 reverse: board removed → nonbg 0% < 5% → rc=1, "paddle" fail
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK)
            cfg = {"canvas": "720x1280", "regions": [
                {"name": "paddle", "x0": 240, "y0": 1220, "x1": 480, "y1": 1260,
                 "min_nonbg_ratio": 0.05}]}
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("paddle", r.stdout)

    # ── Scenario B: three-color separation (AC3) ──

    def test_visual_three_color_separation(self):
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE),
                                       (0, 0, 60, 60, BG_REAL)])
            r = _run_visual(td, png, _visual_config())
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("paddle", r.stdout)
            self.assertIn("brick", r.stdout)

    def test_visual_same_color_fails(self):
        # AC5 reverse: board/brick reverted to bg color → dist 0 < 60 → rc=1
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_REAL,
                                rects=[(300, 1230, 420, 1250, BG_REAL),
                                       (0, 600, 720, 680, BG_REAL),
                                       (0, 0, 60, 60, BG_REAL)])
            r = _run_visual(td, png, _visual_config())
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("RGB dist", r.stdout)

    # ── Scenario C: rain distribution (AC4) ──

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
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK,
                                points=self._rain_points(everywhere=True))
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("rain", r.stdout)

    def test_visual_rain_coverage_fail(self):
        # Only top-left corner has rain → coverage 36/144=25% < 60% → rc=1
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK,
                                points=self._rain_points(everywhere=False))
            cfg = _visual_config(regions=[], compare_pairs=[],
                                 rain={"grid": 12, "min_coverage": 0.60})
            r = _run_visual(td, png, cfg)
            self.assertEqual(r.returncode, 1, r.stdout)

    def test_rain_signature_excludes_bright(self):
        # Bright blue (luma 117 ≥ 100) fails the dim condition → no coverage
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
        # Test 13: --json output embeds region/pair/rain detail for review
        with tempfile.TemporaryDirectory() as td:
            png = make_png_fast(720, 1280, bg=BG_DARK,
                                rects=[(300, 1230, 420, 1250, PADDLE_CYAN),
                                       (0, 600, 720, 680, BRICK_ORANGE),
                                       (0, 0, 60, 60, BG_REAL)])
            r = _run_visual(td, png, _visual_config(), "--json")
            self.assertEqual(r.returncode, 0, r.stdout)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            self.assertIn("visual", payload)
            v = payload["visual"]
            self.assertAlmostEqual(v["regions"]["paddle"]["nonbg_ratio"], 0.25, places=2)
            self.assertIsNotNone(v["regions"]["paddle"]["dominant"])
            self.assertGreaterEqual(v["pairs"]["paddle|brick"]["dist"], 60)

    # ── Pure-function units (DESIGN §3.1: 均可独立单测) ──

    def test_region_stats_counts(self):
        rows = [bytearray(bytes((4, 4, 4, 255)) * 4)] * 2  # 4x2 all near-black
        n, nn, buckets = an.region_stats(rows, 0, 0, 4, 2)
        self.assertEqual(n, 8)
        self.assertEqual(nn, 0)
        rows2 = [bytearray(bytes((10, 10, 18, 255)) * 4)]  # foreground (r=10)
        n, nn, _ = an.region_stats(rows2, 0, 0, 4, 1)
        self.assertEqual(nn, 4)  # (10,10,18) counts as foreground

    def test_dominant_color_none_when_all_near_black(self):
        rows = [bytearray(bytes((4, 4, 4, 255)) * 4)] * 2
        self.assertIsNone(an.dominant_color(rows, 0, 0, 4, 2))

    def test_dominant_color_excludes_near_black_bucket(self):
        rows = [bytearray(bytes((4, 4, 4, 255)) * 4
                          + bytes((0, 229, 255, 255)) * 4)] * 2
        dom = an.dominant_color(rows, 0, 0, 8, 2)
        self.assertEqual(dom, (0, 224, 240))  # bucket rep of (0,229,255)

    def test_rgb_distance(self):
        self.assertAlmostEqual(an.rgb_distance((0, 0, 0), (3, 4, 0)), 5.0)
        self.assertAlmostEqual(an.rgb_distance((0, 229, 255), (255, 157, 69)),
                               323.0, delta=30)  # ≈347 per PRD §2.2 bucket-rep

    def test_rain_signature_matrix(self):
        self.assertTrue(an.rain_signature(50, 56, 70))    # rain blend
        self.assertFalse(an.rain_signature(0, 150, 255))  # luma 117 ≥ 100
        self.assertFalse(an.rain_signature(70, 70, 70))   # not blue-dominant
        self.assertFalse(an.rain_signature(4, 4, 4))      # near-black bg

    def test_rain_grid_coverage_small(self):
        rows = [bytearray(bytes((50, 56, 70, 255)) * 4)] * 2  # 4x2 all rain
        cov = an.rain_grid_coverage(rows, 4, 2, grid=2, step=1)
        self.assertEqual(cov, 1.0)
        rows2 = [bytearray(bytes((4, 4, 4, 255)) * 4)] * 2
        self.assertEqual(an.rain_grid_coverage(rows2, 4, 2, grid=2, step=1), 0.0)
