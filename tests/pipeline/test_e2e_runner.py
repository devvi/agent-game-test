#!/usr/bin/env python3
"""Unit tests for scripts/run-e2e-review.sh — the local E2E verification runner.

The runner is tested end-to-end against a temporary git repository with a
FAKE godot binary (RUNNER_GODOT injection). No network, no gh, no real Godot.

Covers: worktree create/cleanup, layer sequencing, exit codes, visual layer
assertions, baseline mode, dry-run, per-PR concurrency lock (ownership +
stale reclaim), and the worktree-conflict pre-flight.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
"""
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


def _write_file_ensure_dir(path, content):
    """Write content to path, creating parent dirs (closes the file)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    return path

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
        def pixel(x, y, b):
            if theme and x < 8 and y < 8:
                return (int(theme[0:2], 16), int(theme[2:4], 16), int(theme[4:6], 16))
            return ((x * 3 + b) % 256, (y * 2 + b) % 256, 60)
        for i, s in enumerate(plan.get("shots", [])):
            if s["name"] in cfg.get("drop_shots", []):
                continue
            with open(os.path.join(out_dir, s["name"] + ".png"), "wb") as f:
                f.write(make_png(320, 180, lambda x, y, b=i * 40: pixel(x, y, b)))
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
            f.write('[application]\nconfig/name="E2EFixture"\n')
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
        return os.path.isdir(os.path.join(self.worktree_root, "wt-impl-1"))

    def _lock_exists(self):
        return os.path.isdir(os.path.join(self.worktree_root, ".e2e-1.lock"))

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
        self.assertFalse(self._lock_exists(),
                         "own-failure cleanup must release the lock")
        self.assertEqual(self._summary()["layers"]["L1_logic"], "1")

    def test_worktree_conflict_exits_2(self):
        os.makedirs(os.path.join(self.worktree_root, "wt-impl-1"))
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self._godot_calls(), [],
                         "no godot calls on pre-flight failure")
        self.assertTrue(self._wt_exists(),
                        "worktree owned by another instance must NOT be removed")

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
        self.assertFalse(self._lock_exists(),
                         "dry-run must not create the lock")
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


class TestRunnerConcurrency(RunnerTestBase):
    """#480 TC1-TC3: per-PR concurrency lock (mkdir-atomic + PID liveness)."""

    def test_live_lock_rejects_second_instance(self):
        lock = os.path.join(self.worktree_root, ".e2e-1.lock")
        os.makedirs(lock)
        with open(os.path.join(lock, "pid"), "w") as f:
            f.write(str(os.getpid()))
        os.makedirs(os.path.join(self.worktree_root, "wt-impl-1"))
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 2)
        self.assertIn("another instance running", r.stdout)
        self.assertTrue(self._wt_exists(),
                        "live-lock rejection must NOT remove the worktree")
        self.assertEqual(self._godot_calls(), [],
                         "no godot calls on lock rejection")
        self.assertTrue(os.path.isdir(lock),
                        "live lock must be left untouched")
        with open(os.path.join(lock, "pid")) as f:
            self.assertEqual(f.read(), str(os.getpid()),
                             "lock pid file must be untouched")

    def test_stale_lock_reclaimed(self):
        lock = os.path.join(self.worktree_root, ".e2e-1.lock")
        os.makedirs(lock)
        with open(os.path.join(lock, "pid"), "w") as f:
            f.write("999999999")
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(self._lock_exists(),
                         "stale lock must be reclaimed then released")
        self.assertFalse(self._wt_exists(),
                         "normal cleanup must run after stale reclaim")

    def test_lock_creation_failure_exits_2(self):
        os.chmod(self.worktree_root, 0o555)
        try:
            r = self._run("--no-comment")
        finally:
            os.chmod(self.worktree_root, 0o755)
        self.assertEqual(r.returncode, 2)
        self.assertIn("lock creation failed", r.stdout)
        self.assertEqual(self._godot_calls(), [],
                         "no godot calls when the lock cannot be created")


class TestRunnerOwnership(RunnerTestBase):
    """#480 TC6: --keep preserves the worktree but still releases the lock."""

    def test_keep_preserves_worktree_releases_lock(self):
        r = self._run("--no-comment", "--keep")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(self._wt_exists(),
                        "worktree must be kept with --keep")
        self.assertFalse(self._lock_exists(),
                         "lock is a runtime resource — released even with --keep")


class TestRunnerP5WorktreeFirst(RunnerTestBase):
    """#480 TC7-TC11: P5 must exercise the PR worktree's template + plan."""

    def _commit_edit(self, rel_path, write_fn):
        self._git("checkout", "impl/1-test")
        write_fn(os.path.join(self.repo, rel_path))
        self._git("add", rel_path)
        self._git("commit", "-m", "branch edit: %s" % rel_path)
        self._git("checkout", "main")

    def _write_json(self, path, data):
        with open(path, "w") as f:
            json.dump(data, f, indent=2)

    def test_capture_template_from_worktree(self):
        def write_marker(p):
            with open(p, "w") as f:
                f.write("# branch-marker\n")
        self._commit_edit("framework/templates/e2e_capture.gd", write_marker)
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        cap = os.path.join(self.worktree_root, "e2e-1", "capture.gd")
        self.assertTrue(os.path.exists(cap), "capture.gd must be copied out")
        with open(cap) as f:
            self.assertIn("branch-marker", f.read(),
                          "worktree template must be preferred over REPO_ROOT")

    def test_capture_template_fallback_repo_root(self):
        self._commit_edit(
            "framework/templates/e2e_capture.gd",
            lambda p: os.remove(p))
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        cap = os.path.join(self.worktree_root, "e2e-1", "capture.gd")
        self.assertTrue(os.path.exists(cap), "capture.gd must be copied out")
        with open(cap) as f:
            self.assertEqual(f.read(), "# fake capture\n",
                             "missing worktree template must fall back to REPO_ROOT")

    def test_plan_src_worktree_first(self):
        plan = json.loads(json.dumps(GAME_PLAN))
        plan["theme_color"] = "112233"
        self._commit_edit(
            "mini-pong/e2e_shots.json",
            lambda p: self._write_json(p, plan))
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("wt-impl-1/mini-pong/e2e_shots.json", r.stdout,
                      "plan source must be the worktree PR plan")
        with open(os.path.join(self.worktree_root, "e2e-1", "plan.json")) as f:
            self.assertEqual(json.load(f)["theme_color"], "112233",
                             "resolved plan must come from the PR branch")

    def test_visual_config_passthrough(self):
        # A fake analyzer on the branch that ACCEPTS --visual-config (like
        # #475's real one) — without it the flag would hit main's analyzer
        # which rejects it ("unknown arg") → L3 false fail. This is the exact
        # merge-order hazard #480 exists to fix: the runner must use the PR
        # worktree's analyzer, not main's.
        analyze_log = os.path.join(self.tmp, "fake_analyze.log")
        self.env["FAKE_ANALYZE_LOG"] = analyze_log
        self._commit_edit(
            "scripts/e2e/analyze_bmp.py",
            lambda p: _write_file_ensure_dir(p,
                           "#!/usr/bin/env python3\n"
                           "import os, sys\n"
                           "with open(os.environ['FAKE_ANALYZE_LOG'], 'a') as f:\n"
                           "    f.write(' '.join(sys.argv[1:]) + '\\n')\n"
                           "print('FAKE_ANALYZE ' + ' '.join(sys.argv[1:]))\n"
                           "sys.exit(0)\n"))
        plan = json.loads(json.dumps(GAME_PLAN))
        for s in plan["groups"]["loop"]["shots"]:
            if s["name"] == "02_midgame":
                s["visual"] = {
                    "regions": [{"name": "mid", "x0": 0, "y0": 0,
                                 "x1": 320, "y1": 180,
                                 "min_nonbg_ratio": 0.01}],
                }
        self._commit_edit(
            "mini-pong/e2e_shots.json",
            lambda p: self._write_json(p, plan))
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        vjson = os.path.join(self.worktree_root, "e2e-1",
                             "visual-02_midgame.json")
        self.assertTrue(os.path.exists(vjson),
                        "visual config must be extracted per-shot")
        with open(vjson) as f:
            self.assertEqual(json.load(f)["regions"][0]["name"], "mid")
        self.assertTrue(os.path.exists(analyze_log),
                        "fake analyzer must have run")
        with open(analyze_log) as f:
            lines = f.read().splitlines()
        vc_lines = [ln for ln in lines if "--visual-config" in ln]
        self.assertEqual(len(vc_lines), 1,
                         "only the shot WITH visual gets --visual-config")
        self.assertIn("02_midgame.png", vc_lines[0])
        non_vc = [ln for ln in lines if "--visual-config" not in ln]
        self.assertEqual(len(non_vc), 2,
                         "the other 2 shots must NOT get --visual-config")

    def test_missed_shot_fails_l3(self):
        self._write_config({"drop_shots": ["01_title"]})
        r = self._run("--no-comment")
        self.assertEqual(r.returncode, 1)
        self.assertIn("planned shot missing: 01_title.png", r.stdout)
        self.assertEqual(self._summary()["layers"]["L3_visual"], "fail")
