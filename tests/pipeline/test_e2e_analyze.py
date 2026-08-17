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


class TestThemeAbsent(unittest.TestCase):
    """#517: reverse theme assertion --theme-absent (world-hidden semantics).

    与 _theme_present() 同采样（stride 5 / 容差 32），互为镜像：
    0 个采样点命中 → 「世界隐藏」成立（通过）；任一命中 → 断言 fail。
    """

    def _theme_patch_png(self):
        """64x64 渐变 + 左上 8x8 #4a90d9 色块（模拟世界可见的漏渲染画面）。"""
        def fn(x, y):
            if x < 8 and y < 8:
                return (0x4a, 0x90, 0xd9)
            return (x * 3 % 256, y * 3 % 256, 40)
        return make_png(64, 64, fn)

    def test_theme_patch_fails_absent(self):
        # A1: 含 theme 色 → 反向断言 fail（世界本应隐藏却可见）
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "title.png", self._theme_patch_png())
            r = run_cli(td, "title.png", "--theme-absent", "4a90d9")
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("theme #4a90d9 FOUND — expected hidden", r.stdout)

    def test_plain_gradient_passes_absent(self):
        # A2: 无 theme 色 → 反向断言 pass（世界隐藏成立）
        def fn(x, y):
            return (x * 3 % 256, y * 3 % 256, 40)
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "title.png", make_png(64, 64, fn))
            r = run_cli(td, "title.png", "--theme-absent", "4a90d9")
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("theme #4a90d9 absent (world hidden)", r.stdout)

    def test_mutually_exclusive(self):
        # A3: --theme 与 --theme-absent 互斥 → exit 2（analyzer 层防御）
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "title.png", self._theme_patch_png())
            r = run_cli(td, "title.png", "--theme", "4a90d9",
                        "--theme-absent", "4a90d9")
            self.assertEqual(r.returncode, 2, r.stdout)
            self.assertIn("mutually exclusive", r.stdout)

    def test_symmetry(self):
        # A4: 同一含 theme 的 PNG — 正断言过 / 反向断言 fail（互为镜像）
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "title.png", self._theme_patch_png())
            pos = run_cli(td, "title.png", "--theme", "4a90d9")
            self.assertEqual(pos.returncode, 0, pos.stdout)
            neg = run_cli(td, "title.png", "--theme-absent", "4a90d9")
            self.assertEqual(neg.returncode, 1, neg.stdout)

    def test_tolerance_boundary(self):
        # A5: 容差 32 边界 — Δg=2 命中（fail），Δg=64 越界（pass）
        def near(x, y, g):
            if x < 8 and y < 8:
                return (0x4a, g, 0xd9)
            return (x * 3 % 256, y * 3 % 256, 40)
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "near.png", make_png(64, 64, lambda x, y: near(x, y, 0x92)))
            r_in = run_cli(td, "near.png", "--theme-absent", "4a90d9")
            self.assertEqual(r_in.returncode, 1, r_in.stdout)
            self.assertIn("theme #4a90d9 FOUND — expected hidden", r_in.stdout)
            write_png(td, "far.png", make_png(64, 64, lambda x, y: near(x, y, 0x50)))
            r_out = run_cli(td, "far.png", "--theme-absent", "4a90d9")
            self.assertEqual(r_out.returncode, 0, r_out.stdout)
            self.assertIn("theme #4a90d9 absent (world hidden)", r_out.stdout)

    def test_default_behavior_unchanged(self):
        # A6: 不带任何 theme flag → 既有 4 断言行为不受影响（无回归）
        with tempfile.TemporaryDirectory() as td:
            write_png(td, "grad.png",
                make_png(64, 64, lambda x, y: (x * 3 % 256, y * 3 % 256, 40)))
            r = run_cli(td, "grad.png")
            self.assertEqual(r.returncode, 0, r.stdout)
