#!/usr/bin/env python3
"""Unit tests for scripts/run-e2e-review.sh — the local E2E verification runner.

The runner is tested end-to-end against a temporary git repository with a
FAKE godot binary (RUNNER_GODOT injection). No network, no gh, no real Godot.

Covers: worktree create/cleanup, layer sequencing, exit codes, visual layer
assertions, baseline mode, dry-run, and the worktree-conflict pre-flight.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
"""
import copy
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_RUNNER = os.path.join(_REPO_ROOT, "scripts", "run-e2e-review.sh")

FAKE_GODOT_SRC = r'''#!/usr/bin/env python3
"""Fake godot for runner tests: logs argv, writes gradient PNGs on visual
invocation (with theme-color patch), exits per config."""
import json, os, struct, sys, zlib

def make_png(w, h, fn):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b""
    for y in range(h):
        raw += b"\x00"
        for x in range(w):
            r, g, b = fn(x, y)
            raw += bytes((r, g, b))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

log_path = os.environ.get("FAKE_LOG", "/tmp/fake_godot.log")
with open(log_path, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")

cfg = {}
cfg_path = os.environ.get("FAKE_CONFIG", "")
if cfg_path and os.path.exists(cfg_path):
    with open(cfg_path) as f:
        cfg = json.load(f)

if "--display-driver" in sys.argv:
    if not cfg.get("no_pngs"):
        plan_path = sys.argv[sys.argv.index("--") + 1]
        with open(plan_path) as f:
            plan = json.load(f)
        out_dir = plan["out_dir"]
        os.makedirs(out_dir, exist_ok=True)
        theme = plan.get("theme_color", "")
        # Per-shot theme patch: shots with a truthy "theme_absent" get NO
        # theme-color block (world hidden); all others draw it as before.
        def pixel(x, y, b, patch):
            if patch and theme and x < 8 and y < 8:
                return (int(theme[0:2], 16), int(theme[2:4], 16), int(theme[4:6], 16))
            return ((x * 3 + b) % 256, (y * 2 + b) % 256, 60)
        # Render at the runner's --resolution WxH (faithful to real Godot;
        # #586 gap 3/AC2 makes the runner assert the PNG size via --size).
        width, height = 320, 180
        if "--resolution" in sys.argv:
            w, h = sys.argv[sys.argv.index("--resolution") + 1].split("x")
            width, height = int(w), int(h)
        for i, s in enumerate(plan.get("shots", [])):
            patch = not s.get("theme_absent")
            with open(os.path.join(out_dir, s["name"] + ".png"), "wb") as f:
                f.write(make_png(width, height, lambda x, y, b=i * 40, pt=patch: pixel(x, y, b, pt)))
    sys.exit(0)

exit_code = 0
joined = " ".join(sys.argv)
for sub, code in cfg.get("exit_by_substring", {}).items():
    if sub in joined:
        exit_code = int(code)
        break
sys.exit(exit_code)
'''

GAME_PLAN = {
    "game": "mini-pong",
    "default_archetype": "loop",
    "max_wall_seconds": 30,
    "state_node": "/root/Main/GameStateMachine",
    "state_property": "current_state",
    "states": {"MENU": 0, "SERVING": 1, "PLAYING": 2, "GAME_OVER": 5},
    "theme_color": "4a90d9",
    "autoplay": {"tweaks": []},
    "groups": {
        "loop": {
            "match": [r"gdscripts/.*\.gd", r"scenes/.*\.tscn"],
            "shots": [
                {"name": "01_title", "state": "MENU", "settle_frames": 2},
                {"name": "02_midgame", "state": "PLAYING", "settle_frames": 2},
                {"name": "03_gameover", "state": "GAME_OVER", "settle_frames": 2},
            ],
        }
    },
}


class RunnerTestBase(unittest.TestCase):
    """Creates a temp git repo + fake godot; runs the runner as subprocess."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="e2e-runner-")
        self.repo = os.path.join(self.tmp, "repo")
        self.worktree_root = os.path.join(self.tmp, "wt")
        os.makedirs(self.worktree_root)

        # ── repo scaffold ──
        os.makedirs(os.path.join(self.repo, "game-env"))
        os.makedirs(os.path.join(self.repo, "mini-pong", "tests"))
        os.makedirs(os.path.join(self.repo, "framework", "templates"))
        with open(os.path.join(self.repo, "game-env", "manifest.yaml"), "w") as f:
            f.write("project:\n  name: e2e-fixture\n  repo: devvi/agent-game-test\n"
                    "git:\n  default_branch: main\n"
                    "source:\n  subprojects:\n    - mini-pong\n")
        with open(os.path.join(self.repo, "mini-pong", "project.godot"), "w") as f:
            f.write('[application]\nconfig/name="E2EFixture"\n'
                    '[display]\n'
                    'window/size/viewport_width=320\n'
                    'window/size/viewport_height=180\n')
        for t in ("check_compile.gd", "run_tests.gd", "playthrough_test.tscn"):
            with open(os.path.join(self.repo, "mini-pong", "tests", t), "w") as f:
                f.write("# fake\n")
        with open(os.path.join(self.repo, "mini-pong", "e2e_shots.json"), "w") as f:
            json.dump(GAME_PLAN, f, indent=2)
        with open(os.path.join(self.repo, "framework", "templates", "e2e_capture.gd"), "w") as f:
            f.write("# fake capture\n")
        with open(os.path.join(self.repo, "framework", "templates", "e2e_shots.json"), "w") as f:
            json.dump(GAME_PLAN, f, indent=2)

        # ── git init + branches ──
        self._git("init", "-b", "main")
        self._git("config", "user.email", "e2e@test")
        self._git("config", "user.name", "E2E Test")
        self._git("add", "-A")
        self._git("commit", "-m", "fixture main")
        self._git("checkout", "-b", "impl/1-test")
        # The impl branch must NOT be checked out in the main tree —
        # `git worktree add` refuses to check out an already-checked-out branch.
        self._git("checkout", "main")

        # ── fake godot ──
        self.fake_godot = os.path.join(self.tmp, "fake_godot")
        with open(self.fake_godot, "w") as f:
            f.write(FAKE_GODOT_SRC)
        os.chmod(self.fake_godot, 0o755)
        self.fake_log = os.path.join(self.tmp, "fake.log")
        self.fake_config = os.path.join(self.tmp, "fake_config.json")

        self.env = os.environ.copy()
        self.env.update({
            "RUNNER_GODOT": self.fake_godot,
            "E2E_REPO_ROOT": self.repo,
            "E2E_WORKTREE_ROOT": self.worktree_root,
            "E2E_GH_REPO": "devvi/agent-game-test",
            "E2E_BRANCH": "impl/1-test",
            "E2E_DIFF_FILES": "mini-pong/gdscripts/ball.gd",
            "FAKE_LOG": self.fake_log,
            "FAKE_CONFIG": self.fake_config,
        })
        self._write_config({})

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ── helpers ──
    def _git(self, *args):
        subprocess.run(["git", "-C", self.repo, *args], check=True,
                       capture_output=True)

    def _write_config(self, cfg):
        with open(self.fake_config, "w") as f:
            json.dump(cfg, f)

    def _run(self, *extra_args):
        return subprocess.run(
            [_RUNNER, "1", *extra_args],
            env=self.env, capture_output=True, text=True, timeout=120)

    def _godot_calls(self):
        if not os.path.exists(self.fake_log):
            return []
        with open(self.fake_log) as f:
            return [ln for ln in f.read().splitlines() if ln.strip()]

    def _summary(self):
        with open(os.path.join(self.worktree_root, "e2e-1", "summary.json")) as f:
            return json.load(f)

    def _wt_exists(self):
        return os.path.isdir(os.path.join(self.worktree_root, "wt-implement-1"))

    def _shots(self):
        d = os.path.join(self.worktree_root, "e2e-1", "shots")
        return sorted(os.listdir(d)) if os.path.isdir(d) else []


class TestRunnerFlow(RunnerTestBase):
    def test_all_layers_pass_and_worktree_cleaned(self):
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(self._wt_exists(), "worktree must be removed")
        calls = self._godot_calls()
        joined = "\n".join(calls)
        self.assertIn("--headless --script tests/check_compile.gd", joined)
        self.assertIn("--headless --script tests/run_tests.gd", joined)
        self.assertIn("--display-driver macos", joined)
        self.assertEqual(len(self._shots()), 3, self._shots())
        s = self._summary()
        self.assertEqual(s["layers"]["L0_compile"], "0")
        self.assertEqual(s["layers"]["L1_logic"], "0")
        self.assertEqual(s["layers"]["L2_runtime"], "0")
        self.assertEqual(s["layers"]["L3_visual"], "pass")
        # --no-comment ⇒ no comment.md, no gh
        self.assertFalse(os.path.exists(
            os.path.join(self.worktree_root, "e2e-1", "comment.md")))

    def test_logic_failure_exits_1_worktree_still_cleaned(self):
        self._write_config({"exit_by_substring": {"tests/run_tests.gd": 1}})
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(self._wt_exists(), "cleanup must run on failure")
        self.assertEqual(self._summary()["layers"]["L1_logic"], "1")

    def test_worktree_conflict_exits_2(self):
        # 2026-08-17: 命名统一后兜底新建路径是 wt-implement-<N> — 模拟
        # 该路径已被占 (非空目录 → git worktree add 必然失败) → exit 2
        conflict = os.path.join(self.worktree_root, "wt-implement-1")
        os.makedirs(conflict)
        with open(os.path.join(conflict, "occupied.txt"), "w") as f:
            f.write("occupied")
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self._godot_calls(), [],
                         "no godot calls on pre-flight failure")

    def test_reuses_existing_implement_worktree(self):
        """2026-08-17 (复盘修复 #1): implement 保留的 worktree 必须被复用,
        而不是新建 — porcelain 里 branch 行前 2 行才是 worktree 行
        (grep -B2)。复用后 WT_OWNED=0, runner 不删它。"""
        wt = os.path.join(self.worktree_root, "wt-implement-1")
        self._git("worktree", "add", wt, "impl/1-test")
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("P1 reuse existing worktree", r.stdout,
                      f"must reuse implement worktree, got: {r.stdout}")
        self.assertTrue(self._wt_exists(),
                        "reused worktree (WT_OWNED=0) must NOT be removed")
        # L0-L2 在复用的 worktree 里真实执行了
        self.assertGreater(len(self._godot_calls()), 0)

    def test_visual_fail_when_no_pngs(self):
        self._write_config({"no_pngs": True})
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "fail")

    def test_skip_visual(self):
        r = self._run("--no-comment", "--skip-visual")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        joined = "\n".join(self._godot_calls())
        self.assertNotIn("--display-driver", joined)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "skip")

    def test_baseline_runs_main_worktree(self):
        r = self._run("--no-comment", "--baseline")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        calls = self._godot_calls()
        run_tests = [c for c in calls if "tests/run_tests.gd" in c]
        self.assertEqual(len(run_tests), 2, "impl + main baseline")
        self.assertEqual(self._summary()["baseline"], "0")

    def test_dry_run_executes_nothing(self):
        r = self._run("--dry-run")
        self.assertEqual(r.returncode, 0)
        self.assertFalse(self._wt_exists())
        self.assertEqual(self._godot_calls(), [])


if __name__ == "__main__":
    unittest.main()


class TestRunnerP6Comment(RunnerTestBase):
    """#372 T8: P6 comment build with a fake `gh` on PATH.

    Guards the P6 fixes end-to-end:
      - upload_via_gist is DEFINED before the P6 call site (function
        placement regression — the old code crashed with 'command not found')
      - $name_ typo is gone (set -u would abort with 'unbound variable')
      - comment.md embeds gist raw URLs as markdown images
    """

    def setUp(self):
        super().setUp()
        # Fake gh: `gist create` prints a gist.github.com URL (like real gh),
        # `pr comment` is a no-op success. Real gh must NOT be on PATH.
        fake_gh = os.path.join(self.tmp, "fakebin", "gh")
        os.makedirs(os.path.dirname(fake_gh), exist_ok=True)
        with open(fake_gh, "w") as f:
            f.write('#!/usr/bin/env bash\n'
                    'if [[ "$1" == "gist" && "$2" == "create" ]]; then\n'
                    '  echo "https://gist.github.com/devvi/abc123def"\n'
                    '  exit 0\n'
                    'fi\n'
                    'if [[ "$1" == "pr" && "$2" == "comment" ]]; then\n'
                    '  exit 0\n'
                    'fi\n'
                    'exit 0\n')
        os.chmod(fake_gh, 0o755)
        # Prepend fakebin to PATH (runner calls `gh gist create` + `gh pr comment`)
        self.env["PATH"] = os.path.dirname(fake_gh) + os.pathsep + self.env.get("PATH", "")

    def test_p6_comment_embeds_gist_urls_no_unbound(self):
        r = self._run()  # NO --no-comment → P6 runs
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        comment = os.path.join(self.worktree_root, "e2e-1", "comment.md")
        self.assertTrue(os.path.exists(comment), "comment.md must be built")
        with open(comment) as f:
            text = f.read()
        for shot in ("01_title", "02_midgame", "03_gameover"):
            # runner uses basename (with .png) as the markdown alt text
            self.assertIn(f"![{shot}.png](https://gist.githubusercontent.com/devvi/abc123def/raw/{shot}.png)",
                          text, f"{shot} gist image must be embedded")
        self.assertNotIn("name_: unbound variable", text)
        self.assertNotIn("command not found", text)
        self.assertNotIn("_upload failed", text)


class TestRunnerShotTheme(RunnerTestBase):
    """#517 Scenario B: shot-level theme resolution in the L3 loop.

    Verifies run-e2e-review.sh resolves per-shot theme config from $OUT/plan.json:
      theme_absent        → --theme-absent (reverse assertion)
      theme_color: null   → no theme flag (skip assertion)
      theme_color: value  → --theme
      neither             → top-level THEME fallback (backward compatible)
    Fake godot draws the theme patch only for shots WITHOUT a truthy
    theme_absent, so the reverse assertion has clean pixels to assert on.
    """

    def _plan_with(self, shot_overrides):
        """Deep-copy GAME_PLAN, apply shot overrides, write to the fixture's
        mini-pong/e2e_shots.json, commit on the impl branch (the runner reads
        it via the worktree), then run the runner end-to-end."""
        plan = copy.deepcopy(GAME_PLAN)
        for shot in plan["groups"]["loop"]["shots"]:
            if shot["name"] in shot_overrides:
                shot.update(shot_overrides[shot["name"]])
        self._git("checkout", "impl/1-test")
        with open(os.path.join(self.repo, "mini-pong", "e2e_shots.json"), "w") as f:
            json.dump(plan, f, indent=2)
        changed = subprocess.run(
            ["git", "-C", self.repo, "diff", "--quiet", "--",
             "mini-pong/e2e_shots.json"]).returncode == 1
        if changed:
            self._git("add", "mini-pong/e2e_shots.json")
            self._git("commit", "-m", "shot theme fixture")
        self._git("checkout", "main")
        return self._run("--no-comment")

    def _assert_log(self):
        with open(os.path.join(self.worktree_root, "e2e-1", "P5-assert.log")) as f:
            return f.read()

    def _shot_block(self, log, shot_name):
        """Lines belonging to one shot: from the line containing '<shot>.png ['
        up to the next line containing '.png ['."""
        start = log.index(f"{shot_name}.png [")
        end = log.index(".png [", start + 1)
        return log[start:end]

    def test_b1_theme_absent_passthrough(self):
        r = self._plan_with({"01_title": {"theme_absent": "4a90d9"}})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "pass")
        log = self._assert_log()
        self.assertIn("theme #4a90d9 absent (world hidden)", log,
                      "01_title reverse assertion must fire")
        self.assertIn("theme #4a90d9 present", log,
                      "02/03 top-level fallback must stay positive")

    def test_b2_theme_color_null_skips(self):
        r = self._plan_with({"01_title": {"theme_color": None}})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "pass")
        log = self._assert_log()
        block = self._shot_block(log, "01_title")
        self.assertNotIn("theme #", block,
                         "explicit theme_color:null must skip the theme assertion")
        self.assertIn("theme #4a90d9 present", log,
                      "02/03 top-level fallback still fires")

    def test_b3_fallback_top_level(self):
        r = self._plan_with({})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "pass")
        self.assertIn("theme #4a90d9 present", self._assert_log(),
                      "no shot theme fields → top-level fallback (backward compat)")

    def test_b4_mutually_exclusive_fails(self):
        r = self._plan_with({"01_title": {
            "theme_color": "4a90d9", "theme_absent": "4a90d9"}})
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "fail")
        self.assertIn("theme config error", r.stdout)

    def test_b5_unknown_theme_key_warns(self):
        r = self._plan_with({"01_title": {"theme_abset": "4a90d9"}})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "pass")
        self.assertIn("unknown theme key", r.stderr)

    def test_b6_fake_godot_per_shot_pixels(self):
        r = self._plan_with({"01_title": {"theme_absent": "4a90d9"}})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        shots_dir = os.path.join(self.worktree_root, "e2e-1", "shots")
        analyzer = os.path.join(_REPO_ROOT, "scripts", "e2e", "analyze_bmp.py")
        absent = subprocess.run(
            [sys.executable, analyzer,
             os.path.join(shots_dir, "01_title.png"), "--theme-absent", "4a90d9"],
            cwd=_REPO_ROOT, capture_output=True, text=True)
        self.assertEqual(absent.returncode, 0, absent.stdout + absent.stderr)
        present = subprocess.run(
            [sys.executable, analyzer,
             os.path.join(shots_dir, "02_midgame.png"), "--theme", "4a90d9",
             "--max-black-ratio", "0.9"],
            cwd=_REPO_ROOT, capture_output=True, text=True)
        self.assertEqual(present.returncode, 0, present.stdout + present.stderr)
