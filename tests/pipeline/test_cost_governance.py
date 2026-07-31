#!/usr/bin/env python3
"""Unit tests for P4b cost governance (depth_for_issue, count_self_correct_cycles)
and its integration into preprocess SPAWN generation."""
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_LIB_PATH = os.path.join(_REPO_ROOT, "scripts", "event_processor_lib.py")
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "event-processor.py")

_spec = importlib.util.spec_from_file_location("event_processor_lib", _LIB_PATH)
lib = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(lib)

_spec2 = importlib.util.spec_from_file_location("event_processor", _SCRIPT_PATH)
ep = importlib.util.module_from_spec(_spec2)
assert _spec2 is not None and _spec2.loader is not None
_spec2.loader.exec_module(ep)


class TestDepthForIssue(unittest.TestCase):
    def test_under_threshold_keeps_depth(self):
        self.assertEqual(lib.depth_for_issue(0, "standard"), "standard")
        self.assertEqual(lib.depth_for_issue(2, "deep"), "deep")

    def test_at_threshold_downgrades(self):
        self.assertEqual(lib.depth_for_issue(3, "standard"), "light")
        self.assertEqual(lib.depth_for_issue(3, "deep"), "light")

    def test_over_threshold_downgrades(self):
        self.assertEqual(lib.depth_for_issue(5, "deep"), "light")

    def test_already_light_stays_light(self):
        self.assertEqual(lib.depth_for_issue(0, "light"), "light")


class TestCountSelfCorrectCycles(unittest.TestCase):
    def test_counts_marker_comments(self):
        comments = [
            {"body": "🔄 #12 → self-correct"},
            {"body": "📋 #12 → implement"},
            {"body": "🔄 #12 → self-correct (2nd attempt)"},
        ]
        self.assertEqual(lib.count_self_correct_cycles(comments), 2)

    def test_plain_string_comments(self):
        comments = ["🔄 retry", "normal comment"]
        self.assertEqual(lib.count_self_correct_cycles(comments), 1)

    def test_no_markers(self):
        self.assertEqual(lib.count_self_correct_cycles([{"body": "hi"}]), 0)


class TestImplementSpawnBudget(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = self.tmp.name
        ep.PENDING_FILE = os.path.join(self.base, "pending.json")

    def tearDown(self):
        self.tmp.cleanup()

    def _write_pending(self, events):
        with open(ep.PENDING_FILE, "w") as f:
            json.dump({"events": events}, f)

    def _preprocess_with_comments(self, comments):
        ev = {"_key": "issues.labeled#400:workflow/implement", "type": "issues.labeled",
              "issue": 400, "label": "workflow/implement"}
        self._write_pending([ev])
        fake_run = mock.Mock(return_value=mock.Mock(stdout=""))
        with mock.patch.object(ep, "gh", return_value=json.dumps(comments)), \
             mock.patch.object(ep, "issue_priority_sort_key", return_value=2), \
             mock.patch("subprocess.run", fake_run), \
             mock.patch.object(ep, "_is_issue_closed", return_value=False), \
             mock.patch.object(ep, "_pr_exists_for_issue", return_value=False), \
             mock.patch.object(ep, "write_pending", return_value=None):
            return ep.preprocess()

    def test_high_burn_implement_spawns_light(self):
        comments = [{"body": f"🔄 #400 → self-correct"} for _ in range(4)]
        out = self._preprocess_with_comments(comments)
        line = next(l for l in out if l.startswith("SPAWN: implement"))
        self.assertIn("depth=light", line)

    def test_low_burn_implement_spawns_standard(self):
        comments = [{"body": "📋 #400 → research"}, {"body": "📋 #400 → plan"}]
        out = self._preprocess_with_comments(comments)
        line = next(l for l in out if l.startswith("SPAWN: implement"))
        self.assertNotIn("depth=", line)

    def test_gh_failure_does_not_block_spawn(self):
        ev = {"_key": "issues.labeled#401:workflow/implement", "type": "issues.labeled",
              "issue": 401, "label": "workflow/implement"}
        self._write_pending([ev])
        with mock.patch.object(ep, "gh", side_effect=Exception("gh down")), \
             mock.patch.object(ep, "issue_priority_sort_key", return_value=2), \
             mock.patch.object(ep, "_is_issue_closed", return_value=False), \
             mock.patch.object(ep, "_pr_exists_for_issue", return_value=False), \
             mock.patch.object(ep, "write_pending", return_value=None):
            out = ep.preprocess()
        line = next(l for l in out if l.startswith("SPAWN: implement"))
        self.assertIn("issue=401", line)
        self.assertNotIn("depth=", line)


if __name__ == "__main__":
    unittest.main(verbosity=2)
