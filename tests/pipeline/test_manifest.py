#!/usr/bin/env python3
"""Guard for the project manifest (P0, 2026-07-31).

game-env/manifest.yaml is the single source of truth for project config
(repo/branch/subprojects). It must exist AND be tracked in git — an untracked
manifest means fresh clones/worktrees/CI lack it and the P3 parameterization
never actually landed.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
"""
import os
import subprocess
import unittest

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_MANIFEST = os.path.join(_REPO_ROOT, "game-env", "manifest.yaml")


class TestManifest(unittest.TestCase):
    def test_manifest_exists(self):
        self.assertTrue(os.path.exists(_MANIFEST),
                        "game-env/manifest.yaml is missing")

    def test_manifest_has_required_keys(self):
        with open(_MANIFEST, encoding="utf-8") as f:
            txt = f.read()
        for key in ("repo:", "default_branch:", "subprojects:", "entry:"):
            self.assertIn(key, txt, f"manifest missing key: {key}")

    def test_manifest_is_tracked_in_git(self):
        """P0 regression: the manifest must never be untracked again."""
        r = subprocess.run(
            ["git", "-C", _REPO_ROOT, "ls-files", "game-env/manifest.yaml"],
            capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertTrue(r.stdout.strip(),
                        "game-env/manifest.yaml is NOT tracked in git")


if __name__ == "__main__":
    unittest.main()
