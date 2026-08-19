#!/usr/bin/env python3
"""Unit tests for the post-merge stage (2026-08-19) — the orphan-gap fix.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
Run in CI:    .github/workflows/pipeline-tests.yml (on scripts/ changes)

Covers:
  - review_followup approved→merged → post-merge state created (pending)
  - post_merge_emitter: pending+no emitted_at → SPAWN line + stamped once
  - post_merge_emitter: emitted_at present → silent (one-shot)
  - post_merge_emitter: status=done → silent
  - merge failure → NO post-merge state (retry path untouched)
  - _ensure_post_merge_state idempotency (done not overwritten)

Constraints (repo-wide): no network, no gh CLI, no ~/.hermes writes — all
state dirs patched to temp dirs (isolation lesson: 4afe339).
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "event-processor.py")

_spec = importlib.util.spec_from_file_location("event_processor", _SCRIPT_PATH)
ep = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(ep)


class TestPostMergeState(unittest.TestCase):
    """_ensure_post_merge_state + post_merge_emitter pure logic."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._state_dir = os.path.join(self._tmp.name, "post-merge-state")
        os.makedirs(self._state_dir, exist_ok=True)
        patcher = mock.patch.object(ep, "POST_MERGE_STATE_DIR", self._state_dir)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self._tmp.cleanup)

    def test_ensure_creates_pending(self):
        ep._ensure_post_merge_state(101, 99)
        state = ep._read_post_merge_state(101)
        self.assertEqual(state["status"], "pending")
        self.assertEqual(state["pr"], 101)
        self.assertEqual(state["issue"], 99)
        self.assertIn("created_at", state)

    def test_ensure_idempotent_when_done(self):
        ep._ensure_post_merge_state(102, 1)
        ep._write_post_merge_state(102, {"pr": 102, "issue": 1, "status": "done",
                                          "created_at": 1.0})
        ep._ensure_post_merge_state(102, 1)  # must NOT overwrite done
        self.assertEqual(ep._read_post_merge_state(102)["status"], "done")

    def test_emitter_emits_once_then_silent(self):
        ep._ensure_post_merge_state(103, 2)
        lines = ep.post_merge_emitter()
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0], "SPAWN: post-merge,pr=103,issue=2")
        # one-shot: second call silent
        self.assertEqual(ep.post_merge_emitter(), [])

    def test_emitter_done_silent(self):
        ep._ensure_post_merge_state(104, 3)
        ep._write_post_merge_state(104, {"pr": 104, "issue": 3, "status": "done",
                                          "emitted_at": 0.0})
        self.assertEqual(ep.post_merge_emitter(), [])

    def test_emitter_empty_dir_silent(self):
        self.assertEqual(ep.post_merge_emitter(), [])

    def test_emitter_issue_zero_ok(self):
        ep._ensure_post_merge_state(105, None)
        lines = ep.post_merge_emitter()
        self.assertEqual(lines, ["SPAWN: post-merge,pr=105,issue=0"])


class TestReviewFollowupPostMerge(unittest.TestCase):
    """review_followup approved path wires _ensure_post_merge_state."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._concl_dir = os.path.join(self._tmp.name, "review-conclusions")
        self._e2e_dir = os.path.join(self._tmp.name, "e2e-state")
        self._pm_dir = os.path.join(self._tmp.name, "post-merge-state")
        for d in (self._concl_dir, self._e2e_dir, self._pm_dir):
            os.makedirs(d, exist_ok=True)
        self._patchers = [
            mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", self._concl_dir),
            mock.patch.object(ep, "E2E_STATE_DIR", self._e2e_dir),
            mock.patch.object(ep, "POST_MERGE_STATE_DIR", self._pm_dir),
        ]
        for p in self._patchers:
            p.start()
        self.addCleanup(self._tmp.cleanup)
        for p in self._patchers:
            self.addCleanup(p.stop)

    def _write_conclusion(self, pr, verdict="approved", parent=42):
        with open(os.path.join(self._concl_dir, f"{pr}.json"), "w") as f:
            json.dump({"pr": pr, "verdict": verdict, "class": "OK",
                       "parent_issue": parent, "fix_issue": None,
                       "evidence": "ok"}, f)

    def test_approved_merge_creates_post_merge_state(self):
        self._write_conclusion(200, "approved", 42)
        with mock.patch.object(ep, "_try_merge", return_value=True):
            lines = ep.review_followup()
        self.assertTrue(any("approved → merged" in l for l in lines))
        state = ep._read_post_merge_state(200)
        self.assertEqual(state["status"], "pending")
        self.assertEqual(state["issue"], 42)
        # conclusion consumed (file deleted)
        self.assertFalse(os.path.exists(os.path.join(self._concl_dir, "200.json")))

    def test_merge_failure_no_post_merge_state(self):
        self._write_conclusion(201, "approved", 43)
        with mock.patch.object(ep, "_try_merge", return_value=False):
            lines = ep.review_followup()
        self.assertTrue(any("merge FAILED" in l for l in lines))
        # conclusion kept for retry, no post-merge state
        self.assertTrue(os.path.exists(os.path.join(self._concl_dir, "201.json")))
        self.assertEqual(ep._read_post_merge_state(201), {})

    def test_blocked_verdict_no_post_merge_state(self):
        self._write_conclusion(202, "blocked", 44)
        with mock.patch.object(ep, "_try_merge", return_value=True) as tm:
            with mock.patch.object(ep, "gh", return_value=""):
                with mock.patch.object(ep, "_has_blocked_label", return_value=True):
                    ep.review_followup()
        tm.assert_not_called()
        self.assertEqual(ep._read_post_merge_state(202), {})


if __name__ == "__main__":
    unittest.main()
