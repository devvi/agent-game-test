#!/usr/bin/env python3
"""Unit tests for reconcile_check_runs() (P3b webhook-loss fallback)."""
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "event-processor.py")

_spec = importlib.util.spec_from_file_location("event_processor", _SCRIPT_PATH)
ep = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(ep)


class TestReconcileCheckRuns(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = self.tmp.name
        ep.PENDING_FILE = os.path.join(self.base, "workflow-pending.json")
        ep.RECONCILE_STATE_FILE = os.path.join(self.base, "reconcile-state.json")
        ep.PROJECT_REPO = "devvi/agent-game-test"
        self._write_pending([])

    def tearDown(self):
        self.tmp.cleanup()

    def _write_pending(self, events):
        with open(ep.PENDING_FILE, "w") as f:
            json.dump({"events": events}, f)

    def _read_pending(self):
        with open(ep.PENDING_FILE) as f:
            return json.load(f)["events"]

    def _write_state(self, state):
        with open(ep.RECONCILE_STATE_FILE, "w") as f:
            json.dump(state, f)

    def _read_state(self):
        with open(ep.RECONCILE_STATE_FILE) as f:
            return json.load(f)

    def _run(self, prs, checks_result):
        """prs: list of dicts {number, headRefName, headRefOid}.
        checks_result: dict {sha: conclusion} — or None to simulate no CI yet."""
        def fake_gh(*args):
            if args[0] == "pr" and args[1] == "list":
                return json.dumps(prs)
            if args[0] == "api":
                # args: ("api", "repos/.../commits/<sha>/check-runs", "--jq", ...)
                sha = args[1].split("/commits/")[1].split("/")[0]
                concl = checks_result.get(sha)
                # gh --jq outputs bare strings (no quotes)
                return concl if concl else ""
            return ""

        with mock.patch.object(ep, "gh", side_effect=fake_gh):
            ep.reconcile_check_runs()

    def test_lost_success_event_reemitted(self):
        prs = [{"number": 300, "headRefName": "impl/300-feature",
                "headRefOid": "abc123"}]
        self._run(prs, {"abc123": "success"})
        events = self._read_pending()
        self.assertEqual(len(events), 1)
        ev = events[0]
        self.assertEqual(ev["_key"], "check_run.completed#300")
        self.assertEqual(ev["branch"], "impl/300-feature")
        self.assertEqual(ev["conclusion"], "success")

    def test_failure_event_reemitted(self):
        prs = [{"number": 301, "headRefName": "impl/301-x", "headRefOid": "def456"}]
        self._run(prs, {"def456": "failure"})
        events = self._read_pending()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["conclusion"], "failure")

    def test_no_duplicate_for_same_sha(self):
        prs = [{"number": 302, "headRefName": "impl/302-y", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": "success"})
        self._run(prs, {"sha1": "success"})  # same sha again
        events = self._read_pending()
        self.assertEqual(len(events), 1, "second run must not duplicate")

    def test_new_sha_after_push_reemits(self):
        prs = [{"number": 303, "headRefName": "impl/303-z", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": "failure"})
        # preprocess consumes the failure event (spawns self-correct), so
        # pending is emptied but reconcile state keeps sha1 recorded
        self._write_pending([])
        # implement agent pushes a fix → new sha → CI success
        prs = [{"number": 303, "headRefName": "impl/303-z", "headRefOid": "sha2"}]
        self._run(prs, {"sha2": "success"})
        events = self._read_pending()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["conclusion"], "success")
        self.assertEqual(events[0]["branch"], "impl/303-z")

    def test_event_pending_same_sha_only_records_state(self):
        """When the same-key event is STILL pending (not yet consumed), a new
        CI conclusion must not duplicate it — the webhook has the same dedup
        key semantics, so reconcile matches: record sha, skip re-emit."""
        prs = [{"number": 308, "headRefName": "impl/308-a", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": "failure"})
        # Same PR, new sha, but old event not yet consumed
        prs = [{"number": 308, "headRefName": "impl/308-a", "headRefOid": "sha2"}]
        self._run(prs, {"sha2": "success"})
        events = self._read_pending()
        self.assertEqual(len(events), 1, "must not duplicate while pending")
        self.assertEqual(events[0]["conclusion"], "failure", "old event wins while pending")

    def test_non_impl_branch_skipped(self):
        prs = [{"number": 304, "headRefName": "research/304-r", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": "success"})
        self.assertEqual(self._read_pending(), [])

    def test_pending_ci_waits(self):
        prs = [{"number": 305, "headRefName": "impl/305-q", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": None})  # CI not run yet
        self.assertEqual(self._read_pending(), [])

    def test_merged_pr_state_cleaned(self):
        prs = [{"number": 306, "headRefName": "impl/306-w", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": "success"})
        self._write_state({"_ticks": 7, "306": {"sha": "sha1", "conclusion": "success"}})
        # PR now merged → no longer in open list
        self._run([], {})
        state = self._read_state()
        self.assertNotIn("306", state)

    def test_existing_event_not_duplicated(self):
        # Event already pending (webhook worked) — reconcile must not re-add
        self._write_pending([{
            "_key": "check_run.completed#307", "type": "check_run",
            "issue": 307, "branch": "impl/307-v", "conclusion": "success",
        }])
        prs = [{"number": 307, "headRefName": "impl/307-v", "headRefOid": "sha1"}]
        self._run(prs, {"sha1": "success"})
        events = self._read_pending()
        self.assertEqual(len(events), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
