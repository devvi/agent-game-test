#!/usr/bin/env python3
"""Unit tests for event-processor.py — the pipeline's deterministic core.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
Run in CI:    .github/workflows/pipeline-tests.yml (on scripts/ changes)

Constraints:
  - Must NOT require network, gh CLI, or the ~/.hermes environment.
  - All gh() calls must be mocked.
  - Tests the PURE functions: parsing, prioritization, time windows,
    grouping/dedup, and the issue picker.
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


class TestParseDependencies(unittest.TestCase):
    def test_english_full_deps(self):
        body = "## Dependencies\nDepends on: #42\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 42, "type": "full"}])

    def test_english_design_deps(self):
        body = "## Dependencies\nDepends on (design): #49\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 49, "type": "design"}])

    def test_chinese_heading_and_bare_refs(self):
        body = "## 前置依赖\n#42, #43\n"
        deps = ep.parse_dependencies(body)
        self.assertEqual(len(deps), 2)
        self.assertIn({"issue": 42, "type": "full"}, deps)
        self.assertIn({"issue": 43, "type": "full"}, deps)

    def test_dedup_within_section(self):
        body = "## Dependencies\nDepends on: #42\n#42\n"
        deps = ep.parse_dependencies(body)
        self.assertEqual(len(deps), 1)

    def test_no_deps_section(self):
        self.assertEqual(ep.parse_dependencies("No deps here #99"), [])

    def test_exits_at_next_heading(self):
        body = "## Dependencies\nDepends on: #42\n## Acceptance Criteria\n#43 not a dep\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 42, "type": "full"}])

    def test_unknown_dep_type_defaults_to_full(self):
        body = "## Dependencies\nDepends on (weird): #7\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 7, "type": "full"}])


class TestEventPriority(unittest.TestCase):
    def test_check_run_completed_actionable(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "branch": "impl/154-x", "conclusion": "failure"}
        self.assertEqual(ep.event_priority(ev), 1)

    def test_check_run_completed_success(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "branch": "impl/154-x", "conclusion": "success"}
        self.assertEqual(ep.event_priority(ev), 1)

    def test_check_run_incomplete_forwarded(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "branch": "impl/154-x", "conclusion": ""}
        self.assertEqual(ep.event_priority(ev), 2)

    def test_check_run_empty_discard(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_issues_labeled_workflow(self):
        ev = {"_key": "issues.labeled#154:workflow/plan", "type": "issues.labeled",
              "label": "workflow/plan"}
        self.assertEqual(ep.event_priority(ev), 2)

    def test_issues_labeled_lock_discard(self):
        ev = {"_key": "issues.labeled#154:workflow/lock-pi", "type": "issues.labeled",
              "label": "workflow/lock-pi"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_issues_labeled_non_workflow_discard(self):
        ev = {"_key": "issues.labeled#154:enhancement", "type": "issues.labeled",
              "label": "enhancement"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_pull_request_discard(self):
        ev = {"_key": "pull_request.opened#154", "type": "pull_request"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_should_discard(self):
        self.assertTrue(ep.should_discard({"type": "pull_request"}))
        self.assertFalse(ep.should_discard(
            {"_key": "check_run.completed#1", "type": "check_run",
             "branch": "impl/1", "conclusion": "success"}))


class TestValidateCheckRun(unittest.TestCase):
    def test_valid(self):
        ev = {"_key": "check_run.completed#1", "type": "check_run",
              "branch": "impl/1-x", "conclusion": "success"}
        self.assertTrue(ep.validate_check_run(ev))

    def test_missing_branch_invalid(self):
        ev = {"_key": "check_run.completed#1", "type": "check_run", "conclusion": "success"}
        self.assertFalse(ep.validate_check_run(ev))

    def test_skipped_invalid(self):
        ev = {"_key": "check_run.completed#1", "type": "check_run",
              "branch": "research/1", "conclusion": "skipped"}
        self.assertFalse(ep.validate_check_run(ev))

    def test_non_check_run_passes(self):
        self.assertTrue(ep.validate_check_run({"type": "issues.labeled", "label": "workflow/plan"}))


class TestTimeWindow(unittest.TestCase):
    def test_daytime_within(self):
        cfg = {"enabled": True, "work_start_hour": 8, "work_end_hour": 22}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            dt.now.return_value.hour = 12
            self.assertTrue(ep._time_in_window(cfg))

    def test_daytime_outside(self):
        cfg = {"enabled": True, "work_start_hour": 8, "work_end_hour": 22}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            dt.now.return_value.hour = 23
            self.assertFalse(ep._time_in_window(cfg))

    def test_wrapping_window(self):
        cfg = {"enabled": True, "work_start_hour": 23, "work_end_hour": 8}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            dt.now.return_value.hour = 2
            self.assertTrue(ep._time_in_window(cfg))
            dt.now.return_value.hour = 15
            self.assertFalse(ep._time_in_window(cfg))

    def test_multi_window_preset(self):
        cfg = {"enabled": True, "work_windows": [[0, 9], [12, 14], [18, 24]]}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            for hour, expected in [(6, True), (10, False), (13, True), (15, False), (20, True)]:
                dt.now.return_value.hour = hour
                self.assertEqual(ep._time_in_window(cfg), expected, f"hour={hour}")


class TestReadWorkflowConfig(unittest.TestCase):
    """Regression tests for the 2026-07-31 preset-window merge fix."""

    # read_workflow_config lives in event_processor_lib (split P1-7);
    # mock the lib's WORKFLOW_CONFIG constant, not the main module's.
    LIB = __import__("event_processor_lib")

    def _write_config(self, tmpdir, content):
        path = os.path.join(tmpdir, "workflow-config.json")
        with open(path, "w") as f:
            json.dump(content, f)
        return path

    def test_best_deepseek_windows_not_clobbered_by_explicit_hours(self):
        """The bug: explicit work_start_hour/work_end_hour in the file silently
        disabled the best-deepseek multi-window preset. Fix: windows are authoritative."""
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = self._write_config(tmp, {
                "enabled": True, "preset": "best-deepseek",
                "work_start_hour": 0, "work_end_hour": 8,
            })
            with mock.patch.object(self.LIB, "WORKFLOW_CONFIG", cfg_path):
                merged = ep.read_workflow_config()
            self.assertEqual(merged.get("work_windows"), [[0, 9], [12, 14], [18, 24]])

    def test_simple_preset_explicit_hours_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = self._write_config(tmp, {
                "enabled": True, "preset": "daytime",
                "work_start_hour": 10, "work_end_hour": 18,
            })
            with mock.patch.object(self.LIB, "WORKFLOW_CONFIG", cfg_path):
                merged = ep.read_workflow_config()
            self.assertEqual(merged["work_start_hour"], 10)
            self.assertEqual(merged["work_end_hour"], 18)

    def test_defaults_when_no_config(self):
        with mock.patch.object(self.LIB, "WORKFLOW_CONFIG", "/definitely/missing.json"):
            merged = ep.read_workflow_config()
        self.assertTrue(merged["enabled"])
        self.assertEqual(merged["work_start_hour"], 8)
        self.assertEqual(merged["work_end_hour"], 22)


class TestPreprocess(unittest.TestCase):
    """Grouping, dedup, and SPAWN generation — the script's core contract."""

    def _events(self, *evs):
        return list(evs)

    def _run_preprocess(self, events, fake_run=None):
        # Mock the subprocess gh call inside preprocess (PR body lookup) so
        # tests stay hermetic and fast. Empty body → no parent match → falls
        # back to issue=PR number.
        if fake_run is None:
            fake_run = mock.Mock(return_value=mock.Mock(stdout=""))
        with mock.patch.object(ep, "read_pending", return_value=events), \
             mock.patch.object(ep, "write_pending", return_value=None), \
             mock.patch("subprocess.run", fake_run), \
             mock.patch.object(ep, "_is_pr_merged", return_value=False), \
             mock.patch.object(ep, "_is_issue_closed", return_value=False), \
             mock.patch.object(ep, "_extract_parent_issue", return_value=None), \
             mock.patch.object(ep, "_is_pr_blocked", return_value=False), \
             mock.patch.object(ep, "_parent_issue_blocked", return_value=False):
            return ep.preprocess()

    def test_check_run_failure_spawns_self_correct(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "issue": 154, "branch": "impl/154-x", "conclusion": "failure"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("SPAWN: self-correct,issue=154") for l in out),
                        f"unexpected output: {out}")

    def test_check_run_success_spawns_review(self):
        ev = {"_key": "check_run.completed#155", "type": "check_run",
              "issue": 155, "branch": "impl/155-y", "conclusion": "success"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("SPAWN: review,issue=155") for l in out),
                        f"unexpected output: {out}")

    def test_non_impl_branch_passes_to_llm(self):
        ev = {"_key": "check_run.completed#156", "type": "check_run",
              "issue": 156, "branch": "plan/156-z", "conclusion": "success"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("P1: check_run.completed,issue=156") for l in out))

    def test_idle_fast_path_not_silent_when_backlog_exists(self):
        """Backlog-only repo must NOT short-circuit to [SILENT] — the picker
        must run to promote backlog → available (canary #358 regression,
        2026-08-10). Note: [SILENT] may still print at the end when preprocess
        has no events — the regression signal is that pick_next_issue ran."""
        issue = {"number": 358, "labels": [{"name": "workflow/backlog"}]}
        with mock.patch.object(ep, "read_pending", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "_time_in_window", return_value=True), \
             mock.patch.object(ep, "health_check", return_value="ok"), \
             mock.patch.object(ep, "reconcile"), \
             mock.patch.object(ep, "pick_next_issue") as pick, \
             mock.patch.object(ep, "reconcile_check_runs"), \
             mock.patch.object(ep, "_read_reconcile_state", return_value={}), \
             mock.patch.object(ep, "_write_reconcile_state"), \
             mock.patch.object(ep, "preprocess", return_value=[]), \
             mock.patch.object(ep, "_quick_stalled_scan", return_value=[]), \
             mock.patch.object(ep, "_count_active_phase_agents", return_value=0), \
             mock.patch.object(ep, "_audit"), \
             mock.patch("sys.stdout") as out:
            ep.main()
        pick.assert_called()  # window-entry pick + no-events fallback pick
        output = "".join(str(c.args[0]) for c in out.write.call_args_list)
        self.assertIn("[SILENT]", output,  # expected: no events → silent tail
                      "no SPAWN lines → [SILENT] tail is normal")

    def test_idle_fast_path_silent_when_all_done(self):
        """All issues done + no pending → true idle: picker must NOT run."""
        issue = {"number": 100, "labels": [{"name": "status/done"}]}
        with mock.patch.object(ep, "read_pending", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "_time_in_window", return_value=True), \
             mock.patch.object(ep, "health_check", return_value="ok"), \
             mock.patch.object(ep, "reconcile"), \
             mock.patch.object(ep, "pick_next_issue") as pick, \
             mock.patch.object(ep, "reconcile_check_runs"), \
             mock.patch.object(ep, "_read_reconcile_state", return_value={}), \
             mock.patch.object(ep, "_write_reconcile_state"), \
             mock.patch.object(ep, "preprocess", return_value=[]), \
             mock.patch.object(ep, "_count_active_phase_agents", return_value=0), \
             mock.patch.object(ep, "_audit"), \
             mock.patch("sys.stdout") as out:
            ep.main()
        pick.assert_not_called()
        output = "".join(str(c.args[0]) for c in out.write.call_args_list)
        self.assertIn("[SILENT]", output)

    def test_group_keeps_highest_priority_only(self):
        """Same issue with both a labeled event and a check_run event →
        only the check_run (P1) survives."""
        ev_high = {"_key": "check_run.completed#160", "type": "check_run",
                   "issue": 160, "branch": "impl/160-a", "conclusion": "success"}
        ev_low = {"_key": "issues.labeled#160:workflow/implement", "type": "issues.labeled",
                  "issue": 160, "label": "workflow/implement"}
        out = self._run_preprocess(self._events(ev_high, ev_low))
        self.assertEqual(len(out), 1, f"expected 1 SPAWN, got {out}")
        self.assertIn("SPAWN: review,issue=160", out[0])

    def test_success_beats_newer_failure(self):
        """CI success is the definitive state — an older success must beat a
        newer failure in the same group (success-before-failure sort)."""
        ev_success = {"_key": "check_run.completed#161", "type": "check_run",
                      "issue": 161, "branch": "impl/161-b", "conclusion": "success",
                      "ts": 1000}
        ev_failure = {"_key": "check_run.completed#161", "type": "check_run",
                      "issue": 161, "branch": "impl/161-b", "conclusion": "failure",
                      "ts": 2000}
        out = self._run_preprocess(self._events(ev_success, ev_failure))
        self.assertEqual(len(out), 1)
        self.assertIn("SPAWN: review", out[0])

    def test_label_self_correct_enriched_with_impl_pr(self):
        """Review-agent local-e2e path: workflow/self-correct label with NO
        pending CI failure → SPAWN carries pr/branch/source=local-e2e."""
        ev = {"_key": "issues.labeled#42:workflow/self-correct",
              "type": "issues.labeled", "issue": 42, "label": "workflow/self-correct"}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "head:impl/42" in joined:
                # Real `gh pr list --json ... --jq .[0]` prints the OBJECT
                return mock.Mock(stdout='{"number": 42, "headRefName": "impl/42-x"}',
                                 returncode=0)
            return mock.Mock(stdout="", returncode=1)

        out = self._run_preprocess(self._events(ev), fake_run=fake_run)
        hit = [l for l in out if l.startswith("SPAWN: self-correct,issue=42")]
        self.assertEqual(len(hit), 1, f"unexpected output: {out}")
        self.assertIn("pr=42", hit[0])
        self.assertIn("branch=impl/42-x", hit[0])
        self.assertIn("source=local-e2e", hit[0])

    def test_label_self_correct_fallback_without_pr(self):
        """No impl PR found (gh error/empty) → bare label spawn, still valid."""
        ev = {"_key": "issues.labeled#44:workflow/self-correct",
              "type": "issues.labeled", "issue": 44, "label": "workflow/self-correct"}
        out = self._run_preprocess(self._events(ev))
        hit = [l for l in out if l.startswith("SPAWN: self-correct,issue=44")]
        self.assertEqual(len(hit), 1, f"unexpected output: {out}")
        self.assertNotIn("source=local-e2e", hit[0])

    def test_label_self_correct_loses_to_pending_ci_failure(self):
        """CI failure outranks the label in the per-issue group — the label
        path must NOT double-spawn when a check_run(failure) is pending."""
        ev_ci = {"_key": "check_run.completed#43", "type": "check_run",
                 "issue": 43, "branch": "impl/43-y", "conclusion": "failure"}
        ev_lbl = {"_key": "issues.labeled#43:workflow/self-correct",
                  "type": "issues.labeled", "issue": 43, "label": "workflow/self-correct"}
        out = self._run_preprocess(self._events(ev_ci, ev_lbl))
        self.assertEqual(len(out), 1, f"expected 1 SPAWN, got {out}")
        self.assertIn("conclusion=failure", out[0])
        self.assertNotIn("source=local-e2e", out[0])

    def test_different_issues_both_kept(self):
        ev1 = {"_key": "check_run.completed#170", "type": "check_run",
               "issue": 170, "branch": "impl/170-a", "conclusion": "failure"}
        ev2 = {"_key": "issues.labeled#171:workflow/plan", "type": "issues.labeled",
               "issue": 171, "label": "workflow/plan"}
        out = self._run_preprocess(self._events(ev1, ev2))
        self.assertEqual(len(out), 2, f"expected 2 lines, got {out}")

    def test_pull_request_discarded_from_file(self):
        ev = {"_key": "pull_request.opened#180", "type": "pull_request", "issue": 180}
        written = {}

        def fake_write(events):
            written["events"] = events

        with mock.patch.object(ep, "read_pending", return_value=[ev]), \
             mock.patch.object(ep, "write_pending", side_effect=fake_write):
            out = ep.preprocess()
        self.assertEqual(out, [])
        self.assertEqual(written["events"], [])  # removed from file


class TestPickCandidates(unittest.TestCase):
    def _issue(self, n, labels, body=""):
        return {"number": n, "labels": [{"name": l} for l in labels],
                "title": f"Issue {n}", "body": body}

    def test_picks_backlog_with_resolved_deps(self):
        issues = [
            self._issue(1, ["workflow/backlog"]),
            self._issue(2, ["workflow/backlog", "priority/high"]),
            self._issue(3, ["workflow/available"]),  # not backlog → skip
        ]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()), \
             mock.patch.object(ep, "_has_unresolved_dependencies", return_value=[]), \
             mock.patch.object(ep, "_has_file_conflict", return_value=False):
            picked = ep._pick_candidates(4)
        self.assertEqual(picked, [2, 1])  # priority/high sorts first

    def test_skips_unresolved_deps_and_conflicts(self):
        issues = [
            self._issue(10, ["workflow/backlog"]),
            self._issue(11, ["workflow/backlog"]),
        ]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()):
            with mock.patch.object(ep, "_has_unresolved_dependencies",
                                   side_effect=[[{"issue": 5, "type": "full"}], []]):
                # Conflict check only runs for candidates that PASS the dep
                # check (issue 11). Issue 10 never reaches it.
                with mock.patch.object(ep, "_has_file_conflict", return_value=False):
                    picked = ep._pick_candidates(4)
        self.assertEqual(picked, [11])

    def test_respects_limit(self):
        issues = [self._issue(n, ["workflow/backlog"]) for n in range(20, 26)]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()), \
             mock.patch.object(ep, "_has_unresolved_dependencies", return_value=[]), \
             mock.patch.object(ep, "_has_file_conflict", return_value=False):
            picked = ep._pick_candidates(2)
        self.assertEqual(len(picked), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
